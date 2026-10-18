extends Node

const WireProtocol = preload("res://scripts/net/NetProtocol.gd")
const NetPlayerRules = preload("res://scripts/net/NetPlayerState.gd")
## Bump this whenever online combat/resolver logic changes without changing one
## of the data registries included in _compatibility_snapshot().
const COMPAT_RULESET_REVISION: int = 2
## NetMatch.gd — autoload singleton. The networking + match brain for the
## online 1-v-1 Skirmish mode (see docs/MULTIPLAYER_SKIRMISH_PLAN.md).
##
## Phase 0 scope (live): ENet host/join over a LAN / Tailscale overlay, peer
## lifecycle signals, and a "ready" handshake that proves a round-trip RPC.
##
## Designed to grow: the draft (Phase 1) and combat (Phases 2-3) route their
## messages through the RPC functions + signals here so all transport plumbing
## lives in one place and the scenes never touch `multiplayer` directly.
##
## Authority model: HOST is the ENet server (peer id 1) and the single source of
## truth. CLIENT sends intents; host validates and broadcasts authoritative
## events. Determinism across machines is NOT required — only the host computes.

# ── Connection lifecycle signals (re-emitted from the multiplayer API so scenes
#    listen to NetMatch, not to the engine singleton directly) ──
signal peer_joined(peer_id: int)        # host sees a client connect
signal peer_left(peer_id: int)          # either side: the other peer dropped
signal connected_to_host                # client: handshake with host succeeded
signal connection_failed                # client: could not reach host
signal host_closed                      # client: host went away
signal lobby_reset                      # connection fully torn down

# ── Relay / room-code signals (RELAY transport only) ──
signal room_created(code: String)       # host: the relay assigned our shareable code
signal room_error(reason: String)       # joiner: the relay rejected our code (bad / full)

# ── Lobby / handshake signals ──
signal ready_state_changed              # local_ready or remote_ready changed
signal hero_state_changed               # local_hero or remote_hero changed
signal match_starting(seed: int)        # host pressed start; both sides should advance
signal match_config_changed             # host changed the mode / best-of selection
signal protocol_rejected(reason: String) # malformed/stale wire message was dropped

# ── Gameplay signals (consumed by NetDraft / Combat in later phases) ──
signal draft_event_received(event: Dictionary)    # both directions, draft messages
signal combat_intent_received(sender_id: int, intent: Dictionary)  # host-side: client → host
signal combat_event_received(event: Dictionary)   # client-side: host → client

const DEFAULT_PORT: int = 7717
const MAX_CLIENTS: int = 1   # 1-v-1 only (DIRECT transport: host is the ENet server)

# ── RELAY transport (NAT-free play without Tailscale; see plan §5.2 / §21) ──
# Two transports share this one brain. DIRECT = the original LAN/Tailscale path
# (host IS the ENet server, peer id 1, verified). RELAY = both players connect
# OUT to a public relay (= NetMatch running run_as_relay on a VPS) which pairs
# them by room code and forwards each envelope to the room partner only. Outbound
# connections traverse any NAT/CGNAT, so no port-forwarding or VPN is needed.
enum Transport { DIRECT, RELAY }

## The public relay address baked into shipping builds (the VPS you run). Empty in
## the repo — the lobby falls back to an editable field so you can point at your own
## relay / localhost during testing. Set this once the VPS is up.
const RELAY_HOST_DEFAULT: String = ""
const RELAY_PORT_DEFAULT: int = 7717
const RELAY_MAX_PEERS: int = 1024     # plenty of concurrent 1-v-1 rooms
const RELAY_MAX_ROOMS: int = 512
const ROOM_CODE_LEN: int = 6
const RELAY_RATE_WINDOW_MS: int = 10000
const RELAY_RATE_MAX_MESSAGES: int = 120
const RELAY_RATE_MAX_BYTES: int = 1048576
const RELAY_CONTROL_MAX_REQUESTS: int = 8
const RELAY_OPEN_ROOM_TTL_MS: int = 10 * 60 * 1000
const RELAY_PAIRED_IDLE_TTL_MS: int = 2 * 60 * 60 * 1000
## Unambiguous code alphabet — no 0/O/1/I/L so a code is easy to read aloud / type.
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
## One-line override file holding the relay address — point at your VPS (or
## 127.0.0.1) without a rebuild. Checked after the BM_RELAY_HOST env var and before
## the baked-in RELAY_HOST_DEFAULT.
const RELAY_HOST_FILE: String = "user://relay_host.txt"

## Resolve the relay address to use right now. Priority: BM_RELAY_HOST env var →
## user://relay_host.txt → RELAY_HOST_DEFAULT (shipping). Empty means "no relay
## configured" — the lobby then steers the player to LAN/direct play.
static func get_relay_host() -> String:
	var env := OS.get_environment("BM_RELAY_HOST").strip_edges()
	if env != "":
		return env
	if FileAccess.file_exists(RELAY_HOST_FILE):
		var f := FileAccess.open(RELAY_HOST_FILE, FileAccess.READ)
		if f != null:
			var line := f.get_line().strip_edges()
			f.close()
			if line != "":
				return line
	return RELAY_HOST_DEFAULT

# Relay envelope kinds (a partner→partner message forwarded by the relay). These
# carry the SAME payloads the DIRECT @rpc functions send; only the routing differs.
const _RK_READY := WireProtocol.KIND_READY
const _RK_HERO := WireProtocol.KIND_HERO
const _RK_MATCH_START := WireProtocol.KIND_MATCH_START
const _RK_MATCH_CONFIG := WireProtocol.KIND_MATCH_CONFIG
const _RK_DRAFT := WireProtocol.KIND_DRAFT
const _RK_INTENT := WireProtocol.KIND_INTENT
const _RK_EVENT := WireProtocol.KIND_EVENT
const _RK_LAUNCH := WireProtocol.KIND_LAUNCH

# Pending role while a player's ENet link to the relay is still opening.
enum _RelayRole { NONE, CREATE, JOIN }

# ── Message-type strings (the wire vocabulary; see plan §9). Combat.gd reads
#    these by name, so the values must stay exact. Intent.t / event.t fields. ──
# Client → host intents (intent.t)
const IN_PLAY_CREATURE := "play_creature"
const IN_PLAY_SPELL := "play_spell"
const IN_TOGGLE_FLOOP := "toggle_floop"
const IN_REPOSITION := "reposition"
const IN_SNIPER_AIM := "sniper_aim"  # client → host: sniper {eid} takes aim at {tgt} (-1 = clear)
const IN_USE_POTION := "use_potion"  # client → host request: consume remaining {pid,target?}
const IN_END_ACTIONS := "end_actions"
const IN_REMATCH := "rematch"        # client → host: I want to play again
const IN_CHOICE := "choice"          # client → host: my pick for an EV_CHOICE prompt (Copycat / Adaptable)
const IN_ORDER_PICK := "order_pick"  # client → host (client won the toss): the settled opener {first}
# SEALED ORDERS battle style (plan §16.2)
const IN_ORDERS := "orders"          # client → host: my sealed creature bundle {list,mana}
const IN_ORDER_GHOST := "order_ghost"   # client → host: I committed an order at {lane,row} (position only)
const IN_SORCERY_PASS := "sorcery_pass" # client → host: I pass my spell step
# Host → client events (event.t)
const EV_MATCH_BEGIN := "match_begin"
const EV_TURN_BEGIN := "turn_begin"
const EV_HAND_SET := "hand_set"
const EV_HAND_COUNT := "hand_count"
# Both directions (host→event, client→intent, like EV_HAND_COUNT): "I discarded
# N cards at my turn commit" — count only, so the foe can show the beat.
const EV_DISCARD_FX := "discard_fx"
# Host → client presentation: the host drank <pid>. Accepted client drinks are
# shown host-side directly after IN_USE_POTION validation.
const EV_POTION_FX := "potion_fx"
# Both directions: "my relic <rid> just triggered" — the receiver pulses that
# chip on its foe-arsenal rail, Hearthstone-trinket-style. Presentation only,
# like EV_POTION_FX. `mine` is from the SENDER's perspective; the host also
# sends mine=false to tell the client "YOUR board relic fired host-side" (the
# client then pulses its OWN rail chip instead).
const EV_RELIC_FX := "relic_fx"
# Both directions: "I sent emote #idx" — a Hearthstone-style canned phrase the
# opponent sees as a speech bubble over our portrait. Presentation only; never
# touches game state. Rides the generic event/intent envelopes (no relay change).
const EV_EMOTE := "emote"
const EV_MANA := "mana_change"
# Compatibility-only granular private events; live host authority normally sends
# the complete owning-client EV_HAND_SET after these mutations.
const EV_DRAW := "draw"
const EV_GIVE_CARD := "give_card"
const EV_CARD_ENTERED := "card_entered"
const EV_CARD_LEFT := "card_left"
const EV_TAG := "tag_change"
const EV_SPELL := "spell_cast"
const EV_CLASH := "clash_log"
const EV_HP := "hp_change"
const EV_TURN_PASSED := "turn_passed"
const EV_MATCH_OVER := "match_over"
const EV_REMATCH := "rematch"        # host → client: I want to play again
# v1 board channel: instead of fine-grained card_entered/tag_change/hp diffs, the
# host pushes a full board snapshot after every authoritative mutation and the
# client reconciles to it (plan §13.2 strategy A, taken to its simplest form).
# The fine-grained EV_* above stay reserved for a later per-strike replay upgrade.
const EV_BOARD_SYNC := "board_sync"
# Host → the owning client: "your creature needs you to pick an option" (Copycat /
# Adaptable). The client shows the picker and answers with IN_CHOICE; the host (still
# authoritative) applies the pick + board-syncs. Rides the normal event/intent channels.
const EV_CHOICE := "choice_req"
# Host → client: the settled opener {first} after the toss winner's pick (the
# host either made the pick itself or is relaying its own applied choice).
const EV_ORDER_PICK := "order_pick_ev"
# SEALED ORDERS battle style (plan §16.2): host → client phase drivers.
const EV_ORDERS_PHASE := "orders_phase"   # {round, init} — both sides give orders now
const EV_ORDER_GHOST := "order_ghost_ev"  # {lane, row} — the host committed an order there
const EV_REVEAL := "orders_reveal"        # clear pendings/ghosts; the snapshot seats the real lines
const EV_SORCERY := "sorcery_turn"        # {who} — whose open spell step it is

# ── Connection state ──
var is_host: bool = false
## 0 = host's player, 1 = client's player. Mirrors the SkirmishState slot index.
var local_player_index: int = -1
## Shared match seed (host-chosen, sent to client) — drives the draft RNG so
## both machines can generate reproducible card triplets. Set by start_match.
var match_seed: int = 0
## Match config (host-chosen in the lobby, synced to the client). match_mode is a
## SkirmishState.MatchMode value selecting the deck-acquisition flow; best_of is 1
## (single game) or 3. The lobby routes to the mode's scene on START; the Best-of-3
## combat code reads best_of. Both ride the start RPC so the client always has them.
var match_mode: int = 0
var best_of: int = 1
## Battle style (host-chosen, synced like best_of). ALTERNATING = the classic
## turn game (one-directional strikes at each turn's end); SEALED = both sides
## place simultaneously in secret, reveal together, then one simultaneous clash
## per round (plan §16). Orthogonal to match_mode — any deck mode, either style.
const STYLE_ALTERNATING := 0
const STYLE_SEALED := 1
var battle_style: int = STYLE_ALTERNATING
## Arsenal size (host-chosen, synced exactly like best_of): how many battle-relic
## and battle-potion picks the shared Arsenal stage offers EACH player before the
## deck screen. ONE pair of numbers for the whole match — both sides draft the
## same count, so an item advantage is never an accident of who is hosting. 0
## skips that category outright (a bare-steel duel).
##
## These literals MIRROR SkirmishState.ARSENAL_RELIC_ROUNDS / _POTION_ROUNDS,
## which own the defaults and the ceilings. They cannot be read here: NetMatch is
## registered BEFORE SkirmishState in the autoload order, so at field-initializer
## time that singleton does not exist yet. Everything below reads the real
## constants at CALL time; tools/_probe_draft_relic.gd gates the pair.
var arsenal_relics: int = 3
var arsenal_potions: int = 2
## True for a local practice match against SkirmishBot — no real peer. The host
## path runs normally; this just makes is_connected_to_peer() pass, makes the deck
## "finished" handoff answer with a bot deck, and keeps launch_combat off the wire.
var vs_bot: bool = false
var _peer: ENetMultiplayerPeer = null
var _connected: bool = false
## Host-side: the connected client's ENet peer id (0 = no client). Set when the
## client connects; used by send_to_client to target the one client directly.
var client_peer_id: int = 0
## Application session + monotonically increasing wire sequence. Engine-level
## reliable ordering does not identify a stale prior match after a scene swap.
var session_id: String = ""
var _out_sequence: int = 0
var _last_in_sequence: int = 0
var _remote_loadout_received: bool = false
## Host-owned Quick/Sealed generation config. It is recorded when the host
## broadcasts cfg and is never read from the peer's finished loadout message.
var _loadout_source_config: Dictionary = {}
var _compatibility_fingerprint_cache: String = ""
var _compatibility_confirmed: bool = false
var _pending_session_id: String = ""
var _pending_remote_fingerprint: String = ""

## ── Combat-message buffering (startup-race guard) ──
## Combat events/intents arrive over the wire as soon as the peer sends them, but
## the combat scene only subscribes to combat_event_received / combat_intent_received
## partway through its _ready (after a texture prebake). A message that lands in
## that gap would emit to ZERO listeners and be lost forever — Godot signals don't
## buffer. That dropped the very first EV_TURN_BEGIN when the going-first client was
## slow to boot, so its turn never opened and BOTH players deadlocked at round 1.
## We buffer while detached and replay in arrival order once the scene calls
## attach_combat(), so no opening message is ever lost to the boot race.
var _combat_attached: bool = false
var _combat_msg_buffer: Array = []

# ── Relay transport state ──
## Which transport this session uses. DIRECT keeps the verified peer-1-is-host
## path; RELAY routes everything through the relay server.
var transport: int = Transport.DIRECT
## True ONLY in the relay-server process (run_as_relay). A normal game client/host
## leaves this false; the relay leaves its player-facing fields untouched.
var is_relay: bool = false
## Player-side (RELAY): our room partner's peer id on the relay (0 = unpaired).
## Set when the relay pairs us; used only for sender attribution — players never
## address the partner directly (every send goes to the relay).
var relay_partner_id: int = 0
## Player-side (RELAY): the shareable code for the room we created (host only).
var relay_room_code: String = ""
## Last human-readable failure reason (room error / connect fail) for the lobby.
var last_error: String = ""
var _pending_relay_role: int = _RelayRole.NONE
var _pending_room_code: String = ""
# Relay-server-side bookkeeping (is_relay only).
var _relay_rooms: Dictionary = {}      # code -> {host:int, client:int}
var _relay_peer_room: Dictionary = {}  # peer_id -> code
var _relay_partner: Dictionary = {}    # peer_id -> partner peer_id
var _relay_last_sequence: Dictionary = {} # peer_id -> last accepted wire seq
var _relay_rate: Dictionary = {}       # peer_id -> sliding-window counters
var _relay_maintenance_accum: float = 0.0

# ── Lobby handshake state ──
var local_ready: bool = false
var remote_ready: bool = false
var remote_present: bool = false   # the other peer is connected
## Lord picks (HeroDB ids) — cosmetic identity only (portrait + emote voice),
## never decks or rules. local_hero is STICKY across leave() so re-hosting after
## a match keeps your lord; remote_hero clears with the connection. The pair is
## exchanged on pick, re-sent on (re)connect, and carried in the match-start
## envelope as the canonical final word (so a pick racing START can't desync).
var local_hero: String = ""
var remote_hero: String = ""

# ── Entity registry (host-authoritative; populated in Phase 2) ──
# entity_id (int) -> Card2D node. The cross-wire handle for board creatures.
var entities: Dictionary = {}
var _next_entity_id: int = 1


func _ready() -> void:
	# Connect the engine multiplayer signals once. They fire for whichever role
	# (server/client) is active; the handlers branch on is_host where it matters.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if not is_relay:
		return
	_relay_maintenance_accum += delta
	if _relay_maintenance_accum < 5.0:
		return
	_relay_maintenance_accum = 0.0
	_relay_expire_rooms()


func _new_session_id() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


func _reset_wire_session(new_id: String) -> void:
	session_id = new_id
	_out_sequence = 0
	_last_in_sequence = 0


## Stable across Dictionary insertion order and machines. Data changes are picked
## up automatically; COMPAT_RULESET_REVISION covers resolver-only code changes.
func compatibility_fingerprint() -> String:
	if _compatibility_fingerprint_cache.is_empty():
		_compatibility_fingerprint_cache = WireProtocol.compatibility_fingerprint(
			_compatibility_snapshot())
	return _compatibility_fingerprint_cache


func _compatibility_snapshot() -> Dictionary:
	return {
		"ruleset_revision": COMPAT_RULESET_REVISION,
		"protocol": WireProtocol.VERSION,
		"cards": {
			"pool": CardDB.CARD_POOL,
			"upgrades": CardDB.UPGRADES,
		},
		"relics": RelicDB.RELICS,
		"potions": PotionDB.POTIONS,
		"heroes": HeroDB.HEROES,
		"keywords": {
			"definitions": KeywordEffects.KEYWORDS,
			"combat": KeywordEffects.COMBAT_KEYWORDS,
		},
		"skirmish": {
			"start_hp": SkirmishState.START_HP,
			"base_max_mana": SkirmishState.BASE_MAX_MANA,
			"deck_target": SkirmishState.DECK_TARGET,
			"draft_act": SkirmishState.DRAFT_ACT,
			"rarity_tiers": SkirmishState.SKIRMISH_RARITY_TIERS,
			"draft_weights": SkirmishState.SKIRMISH_DRAFT_WEIGHTS,
			"rarity_overrides": SkirmishState.SKIRMISH_RARITY_OVERRIDES,
			"modes": SkirmishState.MODE_DEFS,
			"denylist": SkirmishState.SKIRMISH_DENYLIST,
			"draftable_rarities": SkirmishState.DRAFTABLE_RARITIES,
			"relic_pool": SkirmishState.NET_RELIC_POOL,
			"potion_pool": SkirmishState.NET_POTION_POOL,
			"spell_types": SkirmishState.NET_SPELL_TYPES,
			"spell_customs": SkirmishState.NET_SPELL_CUSTOMS,
			"max_hand": NetPlayerRules.MAX_HAND_SIZE,
			"hand_refill": NetPlayerRules.HAND_REFILL_TARGET,
			"max_banked_mana": NetPlayerRules.MAX_BANKED_MANA,
			"curse_ids": NetPlayerRules.CURSE_IDS,
			"battle_styles": [STYLE_ALTERNATING, STYLE_SEALED],
		},
	}


func _compatibility_error(protocol_version: int, fingerprint: Variant) -> String:
	if protocol_version != WireProtocol.VERSION:
		return "protocol_version"
	if not WireProtocol.valid_fingerprint(fingerprint):
		return "fingerprint_invalid"
	if String(fingerprint) != compatibility_fingerprint():
		return "content_mismatch"
	return ""


func _compatibility_message(reason: String) -> String:
	if reason == "protocol_version":
		return "The other player is running a different network version of the game."
	return "The other player is using different cards or combat rules. Update both copies to the same game build."


func _reject_direct_compatibility(reason: String) -> void:
	last_error = _compatibility_message(reason)
	protocol_rejected.emit("protocol_handshake")
	leave()


func _next_wire(kind: String, payload: Dictionary = {}) -> Dictionary:
	if session_id.is_empty():
		return {}
	_out_sequence += 1
	return WireProtocol.make_envelope(kind, payload, session_id, _out_sequence)


## Validate the common envelope and enforce exactly-once, in-session application
## ordering before an RPC handler unwraps its payload. Returns null on rejection.
func _accept_wire(wire: Variant, expected_kind: String) -> Variant:
	var reason := "session_unset" if session_id.is_empty() \
		else WireProtocol.validate_envelope(wire, session_id)
	if reason == "" and WireProtocol.kind(wire) != expected_kind:
		reason = "unexpected_kind"
	if reason == "":
		var incoming_seq := WireProtocol.sequence(wire)
		if incoming_seq <= _last_in_sequence:
			reason = "sequence_stale"
		else:
			_last_in_sequence = incoming_seq
	if reason != "":
		protocol_rejected.emit(reason)
		return null
	return WireProtocol.payload(wire)


func _valid_match_config(mode: int, bo: int, style: int,
		ars_relics: int = -1, ars_potions: int = -1) -> bool:
	# -1 = "not supplied" (an older peer's payload, or a caller that only means to
	# check the three original terms) — the arsenal size falls back to the default.
	var relics_ok: bool = ars_relics == -1 \
		or (ars_relics >= 0 and ars_relics <= SkirmishState.arsenal_relic_max())
	var potions_ok: bool = ars_potions == -1 \
		or (ars_potions >= 0 and ars_potions <= SkirmishState.arsenal_potion_max())
	return mode >= SkirmishState.MatchMode.DRAFT \
		and mode <= SkirmishState.MatchMode.SEALED \
		and bo in [1, 3] \
		and style in [STYLE_ALTERNATING, STYLE_SEALED] \
		and relics_ok and potions_ok


func _draft_direction_allowed(event: Dictionary, sender_is_host: bool) -> bool:
	var event_type := String(event.get("t", ""))
	if event_type == "cfg":
		return sender_is_host
	return event_type in ["pick", "ready", "finished"]


# ─────────────────────────────────────────────────────────────────────────
#  HOST / JOIN
# ─────────────────────────────────────────────────────────────────────────

## Start hosting. Returns OK or an Error code (the lobby surfaces failures).
func host(port: int = DEFAULT_PORT) -> int:
	leave()
	last_error = ""
	_reset_wire_session(_new_session_id())
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = true
	local_player_index = 0
	_connected = true
	return OK


## Join a host by address. Returns OK or an Error code.
func join(address: String, port: int = DEFAULT_PORT) -> int:
	leave()
	last_error = ""
	_reset_wire_session("")
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = false
	local_player_index = 1
	# _connected flips true on connected_to_server / stays false on failure.
	return OK


# ─────────────────────────────────────────────────────────────────────────
#  RELAY TRANSPORT  (connect out to a public relay; pair by room code)
# ─────────────────────────────────────────────────────────────────────────

## Player: create a room on the relay and become its host. Connects OUT to the
## relay (works through any NAT); on connect we ask the relay for a fresh code,
## which arrives via `room_created`. is_host / local_player_index are decided at
## pairing, not here. Returns OK or an ENet error.
func host_via_relay(relay_addr: String, relay_port: int = RELAY_PORT_DEFAULT) -> int:
	return _connect_to_relay(relay_addr, relay_port, _RelayRole.CREATE, "")


## Player: join an existing room on the relay by its code. On connect we send the
## code; the relay either pairs us (→ `connected_to_host`) or rejects it
## (→ `room_error`). Returns OK or an ENet error.
func join_via_relay(relay_addr: String, relay_port: int, code: String) -> int:
	return _connect_to_relay(relay_addr, relay_port, _RelayRole.JOIN, code.strip_edges().to_upper())


func _connect_to_relay(addr: String, port: int, role: int, code: String) -> int:
	leave()
	last_error = ""
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(addr, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	transport = Transport.RELAY
	_pending_relay_role = role
	_pending_room_code = code
	# Pairing fills is_host / local_player_index / remote_present.
	return OK


## Relay server: listen for players and forward per-room. This is the SAME autoload
## running headless on a VPS (see tools/relay_server.gd). server_relay is turned OFF
## so the engine never cross-connects clients — we forward to the room partner only.
func run_as_relay(port: int = RELAY_PORT_DEFAULT) -> int:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, RELAY_MAX_PEERS)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	var sm := multiplayer as SceneMultiplayer
	if sm != null:
		sm.server_relay = false   # we relay explicitly, per room — no engine cross-talk
	is_relay = true
	transport = Transport.RELAY
	return OK


## Generate a room code not currently in use (relay side).
func _relay_make_code() -> String:
	var crypto := Crypto.new()
	var alphabet_size: int = ROOM_CODE_ALPHABET.length()
	var unbiased_ceiling: int = floori(256.0 / float(alphabet_size)) * alphabet_size
	for _attempt in 64:
		var s := ""
		while s.length() < ROOM_CODE_LEN:
			for byte in crypto.generate_random_bytes(16):
				if int(byte) < unbiased_ceiling:
					s += ROOM_CODE_ALPHABET[int(byte) % alphabet_size]
					if s.length() == ROOM_CODE_LEN:
						break
		if not _relay_rooms.has(s):
			return s
	# 31^6 makes exhausting 64 collision retries effectively impossible.
	return ""


## Tear down any active connection and reset lobby state. Safe to call anytime.
func leave() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	is_host = false
	vs_bot = false
	local_player_index = -1
	_connected = false
	client_peer_id = 0
	_reset_wire_session("")
	_remote_loadout_received = false
	_loadout_source_config.clear()
	_compatibility_confirmed = false
	_pending_session_id = ""
	_pending_remote_fingerprint = ""
	local_ready = false
	remote_ready = false
	remote_present = false
	remote_hero = ""   # the pick leaves with the peer; local_hero stays (sticky)
	match_mode = 0
	best_of = 1
	arsenal_relics = SkirmishState.ARSENAL_RELIC_ROUNDS
	arsenal_potions = SkirmishState.ARSENAL_POTION_ROUNDS
	entities.clear()
	_next_entity_id = 1
	detach_combat()   # drop any buffered combat messages from the torn-down session
	# Relay state (player + server fields). is_relay is left for run_as_relay to set
	# AFTER its own leave() call, so a relay process clearing on startup is harmless.
	transport = Transport.DIRECT
	is_relay = false
	relay_partner_id = 0
	relay_room_code = ""
	_pending_relay_role = _RelayRole.NONE
	_pending_room_code = ""
	_relay_rooms.clear()
	_relay_peer_room.clear()
	_relay_partner.clear()
	_relay_last_sequence.clear()
	_relay_rate.clear()
	_relay_maintenance_accum = 0.0
	lobby_reset.emit()


func is_connected_to_peer() -> bool:
	return vs_bot or (_connected and remote_present and _compatibility_confirmed)


## Fresh session entropy, kept separate from the global randi stream so repeated
## app launches do not accidentally replay the same skirmish seeds.
func fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi())


## Begin a local practice match against SkirmishBot. No networking: we synthesize
## the connection state a finished host handshake leaves behind (host, slot 0,
## chosen mode/format, fresh seed) so the deck-acquisition scenes and combat run
## their normal host path. The opponent "peer" is emulated in send_draft_event
## (auto-finishes with a bot deck) and Combat drives slot 1 via SkirmishBot.
func start_vs_bot(mode: int, bo: int, ars_relics: int = -1, ars_potions: int = -1) -> void:
	leave()                      # clean slate (also clears any relay/peer state)
	_reset_wire_session(_new_session_id())
	vs_bot = true
	is_host = true
	local_player_index = 0
	_connected = true
	_compatibility_confirmed = true
	remote_present = false
	match_mode = mode
	best_of = bo
	# The arsenal size rides the call rather than a pre-set field: leave() above
	# restores the defaults, so a value written before this would be erased.
	if ars_relics >= 0:
		arsenal_relics = mini(ars_relics, SkirmishState.arsenal_relic_max())
	if ars_potions >= 0:
		arsenal_potions = mini(ars_potions, SkirmishState.arsenal_potion_max())
	match_seed = fresh_seed()
	# The bot marches as a random rival lord (never a mirror of your pick), so the
	# foe plate and emote voice have an identity in practice matches too.
	var pool: Array = HeroDB.HERO_ORDER.duplicate()
	pool.erase(local_hero)
	remote_hero = String(pool[randi() % pool.size()])


# ─────────────────────────────────────────────────────────────────────────
#  ENGINE SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if is_relay:
		# Relay server: a player opened a link. Rooms form via explicit register
		# RPCs, not on the raw connect, so there's nothing to do here.
		return
	if transport == Transport.RELAY:
		# Player on the relay: this is the relay itself (peer 1). The opponent's
		# presence is driven by the room-pairing RPC, not this signal.
		return
	# DIRECT: a raw ENet link is not a present opponent yet. The host opens a
	# compatibility round trip; both sides become visible only after it succeeds.
	if not is_host:
		return
	client_peer_id = peer_id
	remote_present = false
	_compatibility_confirmed = false
	_rpc_session_open.rpc_id(peer_id, session_id, WireProtocol.VERSION,
		compatibility_fingerprint())


func _on_peer_disconnected(peer_id: int) -> void:
	if is_relay:
		_relay_on_peer_gone(peer_id)
		return
	if transport == Transport.RELAY:
		# Player: relay loss arrives via server_disconnected; partner loss via the
		# relay's _rpc_partner_left. A raw peer drop here (the relay, id 1) is moot.
		return
	# DIRECT:
	remote_present = false
	remote_ready = false
	_compatibility_confirmed = false
	_pending_session_id = ""
	_pending_remote_fingerprint = ""
	if peer_id == client_peer_id:
		client_peer_id = 0
	peer_left.emit(peer_id)
	ready_state_changed.emit()


func _on_connected_to_server() -> void:
	_connected = true
	if transport == Transport.RELAY:
		# Reached the RELAY, not the opponent yet. Ask for our room; pairing (or a
		# room_error) follows. Do NOT signal connected_to_host here.
		match _pending_relay_role:
			_RelayRole.CREATE:
				_rpc_create_room.rpc_id(1, WireProtocol.VERSION,
					compatibility_fingerprint())
			_RelayRole.JOIN:
				_rpc_join_room.rpc_id(1, _pending_room_code, WireProtocol.VERSION,
					compatibility_fingerprint())
		return
	# DIRECT waits for _rpc_session_result before exposing the opponent.


func _on_connection_failed() -> void:
	_connected = false
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	# Client lost the host mid-session.
	_connected = false
	host_closed.emit()
	leave()


@rpc("authority", "call_remote", "reliable")
func _rpc_session_open(new_id: String, protocol_version: int,
		host_fingerprint: String) -> void:
	if transport != Transport.DIRECT or is_host:
		return
	if new_id.is_empty() or new_id.length() > 64:
		_reject_direct_compatibility("protocol_version")
		return
	var reason := _compatibility_error(protocol_version, host_fingerprint)
	if reason in ["protocol_version", "fingerprint_invalid"]:
		_reject_direct_compatibility(reason)
		return
	_pending_session_id = new_id
	_pending_remote_fingerprint = host_fingerprint
	# Confirm our independently computed fingerprint. A content mismatch still
	# completes this one control round trip so host and joiner both get a clear
	# rejection instead of one side seeing only a generic disconnect.
	_rpc_session_confirm.rpc_id(1, WireProtocol.VERSION, compatibility_fingerprint())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_session_confirm(protocol_version: int, client_fingerprint: String) -> void:
	if transport != Transport.DIRECT or not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != client_peer_id or sender == 0:
		protocol_rejected.emit("protocol_handshake")
		return
	var reason := _compatibility_error(protocol_version, client_fingerprint)
	if reason != "":
		var message := _compatibility_message(reason)
		_rpc_session_result.rpc_id(sender, false, message)
		last_error = message
		protocol_rejected.emit("protocol_handshake")
		# Give the reliable rejection RPC one process frame to enter ENet's queue.
		await get_tree().process_frame
		if client_peer_id == sender and not _compatibility_confirmed:
			leave()
		return
	_compatibility_confirmed = true
	remote_present = true
	_rpc_session_result.rpc_id(sender, true, "")
	peer_joined.emit(sender)
	# Catch up choices made while the compatibility round trip was in flight.
	if local_ready:
		_send_ready(local_ready)
	if local_hero != "":
		_send_hero(local_hero)


@rpc("authority", "call_remote", "reliable")
func _rpc_session_result(accepted: bool, message: String) -> void:
	if transport != Transport.DIRECT or is_host:
		return
	if not accepted:
		last_error = message if message != "" else _compatibility_message("content_mismatch")
		protocol_rejected.emit("protocol_handshake")
		leave()
		return
	var reason := _compatibility_error(WireProtocol.VERSION,
		_pending_remote_fingerprint)
	if _pending_session_id.is_empty() or reason != "":
		_reject_direct_compatibility(reason if reason != "" else "protocol_version")
		return
	_reset_wire_session(_pending_session_id)
	_pending_session_id = ""
	_pending_remote_fingerprint = ""
	_compatibility_confirmed = true
	remote_present = true
	connected_to_host.emit()
	if local_ready:
		_send_ready(local_ready)
	if local_hero != "":
		_send_hero(local_hero)


# ─────────────────────────────────────────────────────────────────────────
#  LOBBY HANDSHAKE  (the Phase-0 round-trip demo)
# ─────────────────────────────────────────────────────────────────────────

func set_local_ready(value: bool) -> void:
	local_ready = value
	ready_state_changed.emit()
	_send_ready(value)


func both_ready() -> bool:
	return local_ready and remote_ready and remote_present and _compatibility_confirmed


func _send_ready(value: bool) -> void:
	if not _can_send():
		return
	var wire := _next_wire(_RK_READY, {"value": value})
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_set_ready.rpc(wire)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_READY)
	if payload == null:
		return
	_apply_remote_ready(bool(payload.get("value", false)))


func _apply_remote_ready(value: bool) -> void:
	remote_ready = value
	ready_state_changed.emit()


## Pick the lord you march as (cosmetic: your portrait on both screens + your
## emote voice). Safe to call any time in the lobby, connected or not.
func set_local_hero(hid: String) -> void:
	local_hero = hid
	_send_hero(hid)
	hero_state_changed.emit()


func _send_hero(hid: String) -> void:
	if not _can_send():
		return
	var wire := _next_wire(_RK_HERO, {"hero": hid})
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_set_hero.rpc(wire)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_hero(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_HERO)
	if payload == null:
		return
	_apply_remote_hero(String(payload.get("hero", "")))


func _apply_remote_hero(hid: String) -> void:
	if not HeroDB.has_hero(hid):
		protocol_rejected.emit("hero_unknown")
		return
	remote_hero = hid
	hero_state_changed.emit()


## True when there's a live link AND a present partner to receive a message —
## the shared guard for every player-side send (DIRECT and RELAY).
func _can_send() -> bool:
	return multiplayer.multiplayer_peer != null and remote_present and not session_id.is_empty()


## Host-only: signal both sides to leave the lobby and start the draft. Picks the
## shared match seed and hands it to the client so both draft reproducibly.
func start_match() -> void:
	if not is_host or not both_ready():
		return
	_remote_loadout_received = false
	_loadout_source_config.clear()
	match_seed = fresh_seed()
	# Carry the match config in the start message too, so the client definitely has
	# the chosen mode / best-of / battle style even if it missed an earlier
	# set_match_config send. The lord pair rides along as the canonical final word:
	# picks were exchanged on click, but a pick racing the START press could leave
	# the two machines disagreeing — the host's view wins at start.
	var payload := {"seed": match_seed, "mode": match_mode, "bo": best_of,
		"style": battle_style, "ar": arsenal_relics, "ap": arsenal_potions,
		"h0": local_hero, "h1": remote_hero}
	var wire := _next_wire(_RK_MATCH_START, payload)
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_match_start.rpc(wire)   # tell the client
	match_starting.emit(match_seed)    # tell ourselves (remote-only path)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_start(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_MATCH_START)
	if payload == null:
		return
	_apply_match_start(int(payload.get("seed", 0)), int(payload.get("mode", 0)),
		int(payload.get("bo", 1)), int(payload.get("style", STYLE_ALTERNATING)),
		String(payload.get("h0", "")), String(payload.get("h1", "")),
		_wire_arsenal(payload, "ar"), _wire_arsenal(payload, "ap"))


## Read an arsenal count out of a peer payload. A MISSING key means an older peer
## that predates the setting, which must keep the fixed 3+2 stage — so it reads
## as -1 ("not supplied") and the apply path leaves our value alone. A present
## key is coerced totally: a Dictionary or Array through a bare int() THROWS and
## aborts the handler where it stands (the C13 fuzz-wire class).
func _wire_arsenal(payload: Dictionary, key: String) -> int:
	if not payload.has(key):
		return -1
	var raw: Variant = payload[key]
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return -1
	return int(raw)


func _apply_match_start(seed: int, mode: int, bo: int, style: int = STYLE_ALTERNATING,
		h0: String = "", h1: String = "", ars_relics: int = -1,
		ars_potions: int = -1) -> void:
	if not _valid_match_config(mode, bo, style, ars_relics, ars_potions):
		protocol_rejected.emit("match_start_config")
		return
	if (h0 != "" and not HeroDB.has_hero(h0)) or (h1 != "" and not HeroDB.has_hero(h1)):
		protocol_rejected.emit("match_start_hero")
		return
	_remote_loadout_received = false
	_loadout_source_config.clear()
	match_seed = seed
	match_mode = mode
	best_of = bo
	battle_style = style
	if ars_relics >= 0:
		arsenal_relics = ars_relics
	if ars_potions >= 0:
		arsenal_potions = ars_potions
	# Runs on the CLIENT: h0 is the host's lord (our foe), h1 the host's view of
	# OUR pick — adopt both so the two machines can't start disagreeing.
	if h0 != "":
		remote_hero = h0
	if h1 != "":
		local_hero = h1
	hero_state_changed.emit()
	match_starting.emit(seed)


## Host-only: choose the deck-acquisition mode + best-of and push the choice to the
## client so its lobby can display it. Safe to call before a client is present (the
## broadcast is skipped until one connects; start_match re-sends it regardless).
func set_match_config(mode: int, bo: int, style: int = -1,
		ars_relics: int = -1, ars_potions: int = -1) -> void:
	if not is_host:
		return
	var resolved_style := battle_style if style < 0 else style
	var resolved_relics := arsenal_relics if ars_relics < 0 else ars_relics
	var resolved_potions := arsenal_potions if ars_potions < 0 else ars_potions
	if not _valid_match_config(mode, bo, resolved_style, resolved_relics, resolved_potions):
		protocol_rejected.emit("local_match_config")
		return
	match_mode = mode
	best_of = bo
	if style >= 0:
		battle_style = resolved_style
	arsenal_relics = resolved_relics
	arsenal_potions = resolved_potions
	if remote_present:
		var wire := _next_wire(_RK_MATCH_CONFIG,
			{"mode": mode, "bo": bo, "style": battle_style,
				"ar": arsenal_relics, "ap": arsenal_potions})
		if transport == Transport.RELAY:
			_relay_ship(wire)
		else:
			_rpc_match_config.rpc(wire)
	match_config_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_match_config(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_MATCH_CONFIG)
	if payload == null:
		return
	_apply_match_config(int(payload.get("mode", 0)), int(payload.get("bo", 1)),
		int(payload.get("style", STYLE_ALTERNATING)),
		_wire_arsenal(payload, "ar"), _wire_arsenal(payload, "ap"))


func _apply_match_config(mode: int, bo: int, style: int = STYLE_ALTERNATING,
		ars_relics: int = -1, ars_potions: int = -1) -> void:
	if not _valid_match_config(mode, bo, style, ars_relics, ars_potions):
		protocol_rejected.emit("match_config")
		return
	match_mode = mode
	best_of = bo
	battle_style = style
	if ars_relics >= 0:
		arsenal_relics = ars_relics
	if ars_potions >= 0:
		arsenal_potions = ars_potions
	match_config_changed.emit()


# ─────────────────────────────────────────────────────────────────────────
#  ENTITY REGISTRY  (host-authoritative; used from Phase 2 on)
# ─────────────────────────────────────────────────────────────────────────

## Host-only: hand out the next stable network id for a board creature.
func issue_entity_id() -> int:
	var id := _next_entity_id
	_next_entity_id += 1
	return id

func register_entity(entity_id: int, card: Object) -> void:
	entities[entity_id] = card

func unregister_entity(entity_id: int) -> void:
	entities.erase(entity_id)

func get_entity(entity_id: int) -> Object:
	return entities.get(entity_id, null)


# ─────────────────────────────────────────────────────────────────────────
#  DRAFT MESSAGING  (Phase 1)
# ─────────────────────────────────────────────────────────────────────────

## Record the host's canonical Quick/Sealed source configuration before sending
## cfg. Finished loadouts never get to choose or override this state.
func set_loadout_source_config(mirror: bool, sub_seed: int) -> void:
	if not is_host:
		return
	if match_mode not in [SkirmishState.MatchMode.QUICK, SkirmishState.MatchMode.SEALED]:
		protocol_rejected.emit("local_loadout_config")
		return
	_loadout_source_config = {"mirror": mirror, "seed": sub_seed}

## Send a draft message to the other peer (e.g. {"t":"pick","n":3}).
func send_draft_event(event: Dictionary) -> void:
	if vs_bot:
		# Emulate the absent opponent so single-player (vs-bot) lobbies clear the same
		# handshakes a real peer would answer — without these echoes the scene waits
		# on "Opponent: waiting" forever. Real multiplayer is unaffected (it never
		# enters this branch and the live peer answers instead).
		var t := String(event.get("t", ""))
		if t == "finished":
			# Deck handoff: answer with the bot's own randomly built warband, plus
			# a drafted arsenal (board-authoritative relics; no potions — see
			# SkirmishState.BOT_RELIC_POOL for why the bot never drinks).
			#
			# THE COUNT IS THE HOST'S ARSENAL SETTING, and it has to be. Read off
			# SkirmishState rather than our own field because that is the number
			# validate_loadout_event judges this very loadout against six lines
			# below — a hardcoded 3 against a host who set fewer is rejected as
			# "loadout_arsenal_size", the bot never finishes, and the drill waits
			# on an opponent that has already answered. (It may still hold fewer:
			# BOT_RELIC_POOL is short by design, and deal_unique_cards caps at
			# what the bag holds.)
			var bot_cards := SkirmishBot.build_deck(match_seed ^ 0x80B0)
			var bot_rng := RandomNumberGenerator.new()
			bot_rng.seed = match_seed ^ 0xB07A
			var bot_relics: Array = SkirmishState.deal_unique_cards(
				SkirmishState.BOT_RELIC_POOL,
				mini(SkirmishState.arsenal_relics, SkirmishState.BOT_RELIC_POOL.size()),
				bot_rng)
			call_deferred("_apply_draft_event", {"t": "finished", "cards": bot_cards,
				"relics": bot_relics, "potions": []})
		elif t == "ready":
			# Quick Battle's both-ready gate: the bot is instantly ready, so echo it
			# back. (Draft/Constructed/Sealed have no ready step — they go straight to
			# "finished" above.)
			call_deferred("_apply_draft_event", {"t": "ready"})
		return
	if not _can_send():
		return
	var wire := _next_wire(_RK_DRAFT, {"event": event})
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_draft_event.rpc(wire)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_draft_event(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_DRAFT)
	if payload == null:
		return
	var event: Dictionary = payload.get("event", {})
	var sender_is_host := multiplayer.get_remote_sender_id() == 1
	if not _draft_direction_allowed(event, sender_is_host):
		protocol_rejected.emit("draft_direction")
		return
	_apply_draft_event(event)


func _apply_draft_event(event: Dictionary) -> void:
	var event_type := String(event.get("t", ""))
	match event_type:
		"pick":
			var pick_count := int(event.get("n", -1))
			if pick_count < 0 or pick_count > SkirmishState.DECK_TARGET:
				protocol_rejected.emit("draft_pick_count")
				return
			if event.has("id") and String(event.get("id", "")) \
					not in SkirmishState.skirmish_legal_pool():
				protocol_rejected.emit("draft_pick_card")
				return
		"ready":
			pass
		"cfg":
			if typeof(event.get("mirror", null)) != TYPE_BOOL \
					or typeof(event.get("seed", null)) != TYPE_INT:
				protocol_rejected.emit("draft_config")
				return
		"finished":
			if _remote_loadout_received:
				protocol_rejected.emit("loadout_duplicate")
				return
			var reason := SkirmishState.validate_loadout_event(event, match_mode)
			if reason == "" and is_host and not vs_bot:
				reason = SkirmishState.validate_loadout_provenance(event, match_mode,
						match_seed, 1, _loadout_source_config)
			if reason != "":
				protocol_rejected.emit(reason)
				return
			_remote_loadout_received = true
		_:
			protocol_rejected.emit("draft_event_unknown")
			return
	draft_event_received.emit(event)


# ─────────────────────────────────────────────────────────────────────────
#  COMBAT MESSAGING  (Phases 2-3)
# ─────────────────────────────────────────────────────────────────────────

## CLIENT → HOST: request an action. Executes on the host only; the host reads
## the sender id and validates before applying.
func send_intent(intent: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	var wire := _next_wire(_RK_INTENT, {"intent": intent})
	if wire.is_empty():
		return
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_combat_intent.rpc_id(1, wire)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_combat_intent(wire: Dictionary) -> void:
	# Runs on the host. Surface the sender so the combat scene can attribute it.
	if not is_host:
		protocol_rejected.emit("intent_to_non_host")
		return
	var payload = _accept_wire(wire, _RK_INTENT)
	if payload == null:
		return
	_apply_combat_intent(multiplayer.get_remote_sender_id(), payload.get("intent", {}))


func _apply_combat_intent(sender_id: int, intent: Dictionary) -> void:
	if not is_host:
		protocol_rejected.emit("intent_to_non_host")
		return
	var expected_sender := relay_partner_id if transport == Transport.RELAY else client_peer_id
	if not vs_bot and (expected_sender == 0 or sender_id != expected_sender):
		protocol_rejected.emit("intent_sender")
		return
	if not _combat_attached:
		_combat_msg_buffer.append({"k": "intent", "sender": sender_id, "intent": intent})
		return
	combat_intent_received.emit(sender_id, intent)

## HOST → CLIENT(S): broadcast an authoritative event. The host applies its own
## state directly (not through this), so this is call_remote only.
func broadcast_event(event: Dictionary) -> void:
	if not _can_send():
		return
	var wire := _next_wire(_RK_EVENT, {"event": event})
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_combat_event.rpc(wire)

@rpc("authority", "call_remote", "reliable")
func _rpc_combat_event(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_EVENT)
	if payload == null:
		return
	_apply_combat_event(payload.get("event", {}))


func _apply_combat_event(event: Dictionary) -> void:
	if is_host:
		protocol_rejected.emit("event_to_host")
		return
	if not _combat_attached:
		_combat_msg_buffer.append({"k": "event", "event": event})
		return
	combat_event_received.emit(event)


## The combat scene calls this ONCE, at the end of its net-combat setup, after it
## has wired the combat_event_received / combat_intent_received listeners AND
## finished its own opening (foe seal, going-second pre-deal, etc.). Any messages
## that arrived during the scene transition + texture prebake were buffered; we
## replay them here in arrival order so the opening EV_TURN_BEGIN / EV_ORDERS_PHASE
## / board sync is delivered to a fully-built scene instead of being lost. Idempotent.
func attach_combat() -> void:
	_combat_attached = true
	if _combat_msg_buffer.is_empty():
		return
	var pending: Array = _combat_msg_buffer
	_combat_msg_buffer = []
	for m in pending:
		if String(m.get("k", "")) == "event":
			combat_event_received.emit(m.get("event", {}))
		else:
			combat_intent_received.emit(int(m.get("sender", 0)), m.get("intent", {}))


## Re-arm buffering for the NEXT combat scene: called when we LEAVE combat (scene
## change / rematch / teardown) so messages that land before the new scene wires
## its listeners are captured again rather than emitted to the dead old scene.
func detach_combat() -> void:
	_combat_attached = false
	_combat_msg_buffer.clear()

## HOST → THE ONE CLIENT: send an authoritative event to the client only. This is
## the redaction path — the host chooses which events to forward, so a private
## payload (e.g. the host's own hand) is simply never sent. With 2 players this
## reaches the same recipient as broadcast_event, but the targeted rpc_id keeps
## the "per-recipient" contract explicit for hand_set and friends (plan §14).
func send_to_client(event: Dictionary) -> void:
	if not is_host or not remote_present:
		return
	var wire := _next_wire(_RK_EVENT, {"event": event})
	if transport == Transport.RELAY:
		# The relay forwards to the one room partner — same single recipient.
		_relay_ship(wire)
	else:
		if client_peer_id == 0:
			return
		_rpc_combat_event.rpc_id(client_peer_id, wire)


# ─────────────────────────────────────────────────────────────────────────
#  COMBAT SCENE LAUNCH  (host-authoritative; both peers transition together)
# ─────────────────────────────────────────────────────────────────────────

## Host-only: drop BOTH peers into the combat scene and set each side's skirmish
## mode. The host triggers the client via RPC, then enters locally, so neither
## side change_scenes on its own (the draft client waits for this).
func launch_combat(animated: bool = false) -> void:
	if not is_host:
		return
	if vs_bot:
		_enter_combat_local(animated)   # no peer to signal — enter locally
		return
	var wire := _next_wire(_RK_LAUNCH, {"animated": animated})
	if transport == Transport.RELAY:
		_relay_ship(wire)
	else:
		_rpc_launch_combat.rpc(wire)
	_enter_combat_local(animated)        # host enters (remote path is call_remote only)


@rpc("authority", "call_remote", "reliable")
func _rpc_launch_combat(wire: Dictionary) -> void:
	var payload = _accept_wire(wire, _RK_LAUNCH)
	if payload == null:
		return
	_enter_combat_local(bool(payload.get("animated", false)))


func _enter_combat_local(animated: bool = false) -> void:
	SkirmishState.combat_mode = SkirmishState.CombatMode.NET_HOST \
		if is_host else SkirmishState.CombatMode.NET_CLIENT
	SkirmishState.local_index = local_player_index
	# Prepare a FRESH fight: restore both heroes to full HP and clear the entity
	# registry. Harmless on the first launch (HP is already full, registry empty);
	# essential on a REMATCH, where it wipes the last match's HP + board so the new
	# combat scene rebuilds cleanly from the same drafted decks (which are kept).
	SkirmishState.refresh_heroes()
	entities.clear()
	_next_entity_id = 1
	# Re-arm the message buffer BEFORE the scene swaps: the peer may send the
	# opening turn-begin before the new combat scene finishes booting and calls
	# attach_combat(). Anything that lands in that gap is captured, not dropped.
	detach_combat()
	# ARM THE LATCH ACROSS THE DEFERRED SWAP. change_scene_to_file lands on the
	# next idle frame, and `leave()` — one Esc away on every deck screen, plus the
	# draft's own BACK TO MENU button — clears every term of is_connected_to_peer()
	# in between. Combat cannot otherwise tell that from an ordinary campaign
	# fight, and used to open the player's live run instead of the match.
	SkirmishState.launch_armed = true
	var tree := get_tree()
	var current := tree.current_scene
	var can_animate := animated and DisplayServer.get_name() != "headless" \
		and (UserSettings == null or not UserSettings.reduce_motion) \
		and current != null and is_instance_valid(current)
	if can_animate:
		GameTheme.fade_out_then_change_scene(
			current, "res://scenes/combat.tscn", 0.30, Vector2(0.50, 0.15))
	else:
		tree.change_scene_to_file("res://scenes/combat.tscn")


# ─────────────────────────────────────────────────────────────────────────
#  RELAY FORWARDING & ROOM CONTROL
#
#  Players talk ONLY to the relay (peer id 1). The relay maps each player to its
#  room partner and forwards. This keeps every gameplay message above transport-
#  agnostic: the public send_* methods just choose _relay_ship (RELAY) vs the
#  DIRECT @rpc, and the receive side dispatches a relayed envelope through the
#  SAME _apply_* bodies the DIRECT @rpc handlers use. The Steam backend (later)
#  slots in here as a third "ship to partner" implementation.
# ─────────────────────────────────────────────────────────────────────────

## Player → relay: ship an envelope; the relay forwards it to our room partner.
func _relay_ship(wire: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or wire.is_empty():
		return
	_rpc_relay_forward.rpc_id(1, wire)


func _relay_rate_allowed(sender: int, encoded_bytes: int, control: bool) -> bool:
	var now := Time.get_ticks_msec()
	var rec: Dictionary = _relay_rate.get(sender,
		{"start": now, "messages": 0, "bytes": 0, "control": 0, "violations": 0})
	if now - int(rec.get("start", now)) >= RELAY_RATE_WINDOW_MS:
		rec.start = now
		rec.messages = 0
		rec.bytes = 0
		rec.control = 0
	if control:
		rec.control = int(rec.get("control", 0)) + 1
	else:
		rec.messages = int(rec.get("messages", 0)) + 1
		rec.bytes = int(rec.get("bytes", 0)) + maxi(0, encoded_bytes)
	_relay_rate[sender] = rec
	return int(rec.control) <= RELAY_CONTROL_MAX_REQUESTS \
		if control else (int(rec.messages) <= RELAY_RATE_MAX_MESSAGES \
			and int(rec.bytes) <= RELAY_RATE_MAX_BYTES)


func _relay_reject(sender: int, reason: String) -> void:
	protocol_rejected.emit("relay_" + reason)
	var now := Time.get_ticks_msec()
	var rec: Dictionary = _relay_rate.get(sender,
		{"start": now, "messages": 0, "bytes": 0, "control": 0, "violations": 0})
	rec.violations = int(rec.get("violations", 0)) + 1
	_relay_rate[sender] = rec
	if int(rec.violations) >= 8:
		var sm := multiplayer as SceneMultiplayer
		if sm != null:
			sm.disconnect_peer(sender)


func _relay_sender_is_host(sender: int, room: Dictionary) -> bool:
	return sender == int(room.get("host", 0))


func _relay_direction_allowed(sender: int, room: Dictionary, wire: Dictionary) -> bool:
	var sender_is_host := _relay_sender_is_host(sender, room)
	var kind := WireProtocol.kind(wire)
	if sender_is_host:
		if kind not in [_RK_READY, _RK_HERO, _RK_MATCH_START, _RK_MATCH_CONFIG,
				_RK_DRAFT, _RK_EVENT, _RK_LAUNCH]:
			return false
	else:
		if kind not in [_RK_READY, _RK_HERO, _RK_DRAFT, _RK_INTENT]:
			return false
	if kind == _RK_DRAFT:
		var payload := WireProtocol.payload(wire)
		return _draft_direction_allowed(payload.get("event", {}), sender_is_host)
	return true


## RELAY: forward a player's envelope to that player's room partner ONLY (no
## cross-room leakage — server_relay is off, so the engine never auto-broadcasts).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_relay_forward(wire: Dictionary) -> void:
	if not is_relay:
		return
	var sender := multiplayer.get_remote_sender_id()
	var encoded_bytes := var_to_bytes(wire).size()
	if not _relay_rate_allowed(sender, encoded_bytes, false):
		_relay_reject(sender, "rate")
		return
	var code := String(_relay_peer_room.get(sender, ""))
	if code.is_empty() or not _relay_rooms.has(code):
		_relay_reject(sender, "room")
		return
	var room: Dictionary = _relay_rooms[code]
	var reason := WireProtocol.validate_envelope(wire, String(room.get("sid", "")))
	if reason != "":
		_relay_reject(sender, reason)
		return
	var incoming_seq := WireProtocol.sequence(wire)
	if incoming_seq <= int(_relay_last_sequence.get(sender, 0)):
		_relay_reject(sender, "sequence_stale")
		return
	if not _relay_direction_allowed(sender, room, wire):
		_relay_reject(sender, "direction")
		return
	var partner: int = int(_relay_partner.get(sender, 0))
	if partner == 0:
		_relay_reject(sender, "partner")
		return
	_relay_last_sequence[sender] = incoming_seq
	room.last_ms = Time.get_ticks_msec()
	_relay_rooms[code] = room
	_rpc_relay_deliver.rpc_id(partner, wire)


## Player: the relay handed us our partner's envelope. Dispatch as though it had
## arrived over the matching DIRECT @rpc — reusing the same _apply_* bodies.
@rpc("authority", "call_remote", "reliable")
func _rpc_relay_deliver(wire: Dictionary) -> void:
	var kind := WireProtocol.kind(wire)
	var payload = _accept_wire(wire, kind)
	if payload == null:
		return
	match kind:
		_RK_READY:
			_apply_remote_ready(bool(payload.get("value", false)))
		_RK_HERO:
			_apply_remote_hero(String(payload.get("hero", "")))
		_RK_MATCH_START:
			_apply_match_start(int(payload.get("seed", 0)), int(payload.get("mode", 0)),
				int(payload.get("bo", 1)), int(payload.get("style", STYLE_ALTERNATING)),
				String(payload.get("h0", "")), String(payload.get("h1", "")),
				_wire_arsenal(payload, "ar"), _wire_arsenal(payload, "ap"))
		_RK_MATCH_CONFIG:
			_apply_match_config(int(payload.get("mode", 0)), int(payload.get("bo", 1)),
				int(payload.get("style", STYLE_ALTERNATING)),
				_wire_arsenal(payload, "ar"), _wire_arsenal(payload, "ap"))
		_RK_DRAFT:
			_apply_draft_event(payload.get("event", {}))
		_RK_INTENT:
			_apply_combat_intent(relay_partner_id, payload.get("intent", {}))
		_RK_EVENT:
			_apply_combat_event(payload.get("event", {}))
		_RK_LAUNCH:
			_enter_combat_local(bool(payload.get("animated", false)))


# ── Room control: player → relay ──

@rpc("any_peer", "call_remote", "reliable")
func _rpc_create_room(protocol_version: int, player_fingerprint: String) -> void:
	if not is_relay:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _relay_rate_allowed(sender, 0, true):
		_relay_reject(sender, "control_rate")
		return
	# A relay pairs two clients without ever letting them address each other
	# directly, so this is its compatibility handshake. The client has already
	# sent both values in _on_connected_to_server(); accepting fewer arguments
	# here made every room-create RPC fail before a code could be issued.
	var compatibility_reason := _compatibility_error(protocol_version, player_fingerprint)
	if compatibility_reason != "":
		_rpc_room_error.rpc_id(sender, _compatibility_message(compatibility_reason))
		return
	if _relay_peer_room.has(sender):
		_rpc_room_error.rpc_id(sender, "You already have a room open.")
		return
	if _relay_rooms.size() >= RELAY_MAX_ROOMS:
		_rpc_room_error.rpc_id(sender, "The relay is full. Try again in a moment.")
		return
	var code := _relay_make_code()
	if code.is_empty():
		_rpc_room_error.rpc_id(sender, "The relay could not open a room. Try again.")
		return
	var now := Time.get_ticks_msec()
	var room_session := _new_session_id()
	_relay_rooms[code] = {"host": sender, "client": 0, "sid": room_session,
		"created_ms": now, "last_ms": now}
	_relay_peer_room[sender] = code
	_rpc_room_created.rpc_id(sender, code, room_session, WireProtocol.VERSION)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_join_room(code: String, protocol_version: int, player_fingerprint: String) -> void:
	if not is_relay:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _relay_rate_allowed(sender, code.to_utf8_buffer().size(), true):
		_relay_reject(sender, "control_rate")
		return
	# Match the creator's check above before the joiner can enter a room. Both
	# clients are therefore known to share the relay's protocol and content
	# fingerprint when _rpc_room_paired marks the peer usable.
	var compatibility_reason := _compatibility_error(protocol_version, player_fingerprint)
	if compatibility_reason != "":
		_rpc_room_error.rpc_id(sender, _compatibility_message(compatibility_reason))
		return
	if _relay_peer_room.has(sender):
		_rpc_room_error.rpc_id(sender, "You are already in a room.")
		return
	code = code.strip_edges().to_upper()
	if code.length() != ROOM_CODE_LEN:
		_rpc_room_error.rpc_id(sender, "That room code isn't valid — check it and retry.")
		return
	for ch in code:
		if ROOM_CODE_ALPHABET.find(ch) < 0:
			_rpc_room_error.rpc_id(sender, "That room code isn't valid — check it and retry.")
			return
	if not _relay_rooms.has(code):
		_rpc_room_error.rpc_id(sender, "No room is open with that code.")
		return
	var room: Dictionary = _relay_rooms[code]
	if int(room.get("client", 0)) != 0:
		_rpc_room_error.rpc_id(sender, "That room already has two players.")
		return
	var host_id := int(room.get("host", 0))
	if host_id == 0 or host_id == sender:
		_rpc_room_error.rpc_id(sender, "That room is no longer open.")
		return
	room["client"] = sender
	_relay_peer_room[sender] = code
	_relay_partner[host_id] = sender
	_relay_partner[sender] = host_id
	_relay_last_sequence[host_id] = 0
	_relay_last_sequence[sender] = 0
	room.last_ms = Time.get_ticks_msec()
	_relay_rooms[code] = room
	# Pair: the room creator is index 0 (host), the joiner index 1 (client).
	var room_session := String(room.get("sid", ""))
	_rpc_room_paired.rpc_id(host_id, sender, 0, room_session, WireProtocol.VERSION)
	_rpc_room_paired.rpc_id(sender, host_id, 1, room_session, WireProtocol.VERSION)


# ── Room control: relay → player (authority = only the relay/peer-1 may call) ──

@rpc("authority", "call_remote", "reliable")
func _rpc_room_created(code: String, room_session: String, protocol_version: int) -> void:
	if protocol_version != WireProtocol.VERSION or room_session.is_empty():
		_rpc_room_error("The relay is running a different version of the game.")
		return
	_reset_wire_session(room_session)
	relay_room_code = code
	# Creating a room makes us its host (index 0). Pairing re-confirms this later;
	# setting it now lets the lobby show the host's mode picker while we wait, and
	# keeps is_host correct for any host-only UI between create and join.
	is_host = true
	local_player_index = 0
	room_created.emit(code)


@rpc("authority", "call_remote", "reliable")
func _rpc_room_paired(partner_id: int, my_index: int, room_session: String,
		protocol_version: int) -> void:
	if protocol_version != WireProtocol.VERSION or room_session.is_empty():
		_rpc_room_error("The relay is running a different version of the game.")
		return
	if not session_id.is_empty() and session_id != room_session:
		_rpc_room_error("The relay lost track of this room. Open a new one.")
		return
	_reset_wire_session(room_session)
	relay_partner_id = partner_id
	local_player_index = my_index
	is_host = (my_index == 0)
	remote_present = true
	# The relay accepted the version + fingerprint of both room members before
	# pairing them. Relay traffic has no DIRECT session-result round trip, so this
	# is the point at which the shared readiness/connected predicates become true.
	_compatibility_confirmed = true
	_connected = true
	# Mirror DIRECT's late-ready resend so a pre-pair toggle still propagates.
	if local_ready:
		_send_ready(local_ready)
	if local_hero != "":
		_send_hero(local_hero)
	if is_host:
		peer_joined.emit(partner_id)
	else:
		connected_to_host.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_room_error(reason: String) -> void:
	last_error = reason
	_connected = false
	leave()
	room_error.emit(reason)


## The relay tells the surviving partner that the other side dropped. Mirrors the
## DIRECT peer-loss signals so Lobby / Draft / Combat handle it identically.
@rpc("authority", "call_remote", "reliable")
func _rpc_partner_left() -> void:
	var was_host := is_host
	var partner := relay_partner_id
	remote_present = false
	remote_ready = false
	relay_partner_id = 0
	if was_host:
		peer_left.emit(partner)
	else:
		host_closed.emit()
	ready_state_changed.emit()


# ── Relay-server cleanup when a peer drops ──

func _relay_expire_rooms() -> void:
	var now := Time.get_ticks_msec()
	var expired_codes: Array[String] = []
	for code_var in _relay_rooms:
		var code := String(code_var)
		var room: Dictionary = _relay_rooms[code]
		var paired := int(room.get("client", 0)) != 0
		var ttl := RELAY_PAIRED_IDLE_TTL_MS if paired else RELAY_OPEN_ROOM_TTL_MS
		if now - int(room.get("last_ms", room.get("created_ms", now))) >= ttl:
			expired_codes.append(code)
	for code in expired_codes:
		var room: Dictionary = _relay_rooms.get(code, {})
		var host_id := int(room.get("host", 0))
		var client_id := int(room.get("client", 0))
		if client_id == 0:
			if host_id != 0:
				_rpc_room_error.rpc_id(host_id, "Your room sat open too long and closed. Open a new one.")
		else:
			if host_id != 0:
				_rpc_partner_left.rpc_id(host_id)
			if client_id != 0:
				_rpc_partner_left.rpc_id(client_id)
		_relay_forget_room(code)


func _relay_forget_room(code: String) -> void:
	if code.is_empty() or not _relay_rooms.has(code):
		return
	var room: Dictionary = _relay_rooms[code]
	for peer_id in [int(room.get("host", 0)), int(room.get("client", 0))]:
		if peer_id == 0:
			continue
		_relay_partner.erase(peer_id)
		_relay_peer_room.erase(peer_id)
		_relay_last_sequence.erase(peer_id)
		_relay_rate.erase(peer_id)
	_relay_rooms.erase(code)


func _relay_on_peer_gone(peer_id: int) -> void:
	var partner: int = int(_relay_partner.get(peer_id, 0))
	if partner != 0:
		_rpc_partner_left.rpc_id(partner)
	var code: String = String(_relay_peer_room.get(peer_id, ""))
	if code != "":
		_relay_forget_room(code)
	else:
		_relay_partner.erase(peer_id)
		_relay_partner.erase(partner)
		_relay_peer_room.erase(peer_id)
		_relay_peer_room.erase(partner)
		_relay_last_sequence.erase(peer_id)
		_relay_last_sequence.erase(partner)
	_relay_rate.erase(peer_id)
