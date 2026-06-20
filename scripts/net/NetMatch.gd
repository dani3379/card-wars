extends Node
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
signal match_starting(seed: int)        # host pressed start; both sides should advance
signal match_config_changed             # host changed the mode / best-of selection

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
const ROOM_CODE_LEN: int = 4
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
const _RK_READY := "ready"
const _RK_MATCH_START := "mstart"
const _RK_MATCH_CONFIG := "mcfg"
const _RK_DRAFT := "draft"
const _RK_INTENT := "intent"
const _RK_EVENT := "event"
const _RK_LAUNCH := "launch"

# Pending role while a player's ENet link to the relay is still opening.
enum _RelayRole { NONE, CREATE, JOIN }

# ── Message-type strings (the wire vocabulary; see plan §9). Combat.gd reads
#    these by name, so the values must stay exact. Intent.t / event.t fields. ──
# Client → host intents (intent.t)
const IN_PLAY_CREATURE := "play_creature"
const IN_PLAY_SPELL := "play_spell"
const IN_TOGGLE_FLOOP := "toggle_floop"
const IN_REPOSITION := "reposition"
const IN_END_ACTIONS := "end_actions"
const IN_REMATCH := "rematch"        # client → host: I want to play again
# Host → client events (event.t)
const EV_MATCH_BEGIN := "match_begin"
const EV_TURN_BEGIN := "turn_begin"
const EV_HAND_SET := "hand_set"
const EV_HAND_COUNT := "hand_count"
const EV_MANA := "mana_change"
const EV_DRAW := "draw"               # host → client: draw N from your own pile (caster-side spell draw)
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
var _peer: ENetMultiplayerPeer = null
var _connected: bool = false
## Host-side: the connected client's ENet peer id (0 = no client). Set when the
## client connects; used by send_to_client to target the one client directly.
var client_peer_id: int = 0

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

# ── Lobby handshake state ──
var local_ready: bool = false
var remote_ready: bool = false
var remote_present: bool = false   # the other peer is connected

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


# ─────────────────────────────────────────────────────────────────────────
#  HOST / JOIN
# ─────────────────────────────────────────────────────────────────────────

## Start hosting. Returns OK or an Error code (the lobby surfaces failures).
func host(port: int = DEFAULT_PORT) -> int:
	leave()
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
	for _attempt in 64:
		var s := ""
		for _i in ROOM_CODE_LEN:
			s += ROOM_CODE_ALPHABET[randi() % ROOM_CODE_ALPHABET.length()]
		if not _relay_rooms.has(s):
			return s
	# Astronomically unlikely fallback: widen with a numeric suffix.
	return "X" + str(randi() % 100000)


## Tear down any active connection and reset lobby state. Safe to call anytime.
func leave() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	is_host = false
	local_player_index = -1
	_connected = false
	client_peer_id = 0
	local_ready = false
	remote_ready = false
	remote_present = false
	match_mode = 0
	best_of = 1
	entities.clear()
	_next_entity_id = 1
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
	lobby_reset.emit()


func is_connected_to_peer() -> bool:
	return _connected and remote_present


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
	# DIRECT: on the host this fires when the client arrives; on the client it
	# fires for the server (id 1). Either way it means "the other side is here."
	remote_present = true
	# Re-send our current ready state so a peer that connects after we toggled
	# still learns it. (No-op if we haven't toggled.)
	if local_ready:
		_send_ready(local_ready)
	if is_host:
		# Remember the single client's peer id for targeted (redacted) sends.
		client_peer_id = peer_id
		peer_joined.emit(peer_id)


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
			_RelayRole.CREATE: _rpc_create_room.rpc_id(1)
			_RelayRole.JOIN:   _rpc_join_room.rpc_id(1, _pending_room_code)
		return
	# DIRECT: we reached the host directly.
	remote_present = true
	connected_to_host.emit()


func _on_connection_failed() -> void:
	_connected = false
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	# Client lost the host mid-session.
	_connected = false
	host_closed.emit()
	leave()


# ─────────────────────────────────────────────────────────────────────────
#  LOBBY HANDSHAKE  (the Phase-0 round-trip demo)
# ─────────────────────────────────────────────────────────────────────────

func set_local_ready(value: bool) -> void:
	local_ready = value
	ready_state_changed.emit()
	_send_ready(value)


func both_ready() -> bool:
	return local_ready and remote_ready and remote_present


func _send_ready(value: bool) -> void:
	if not _can_send():
		return
	if transport == Transport.RELAY:
		_relay_ship({"t": _RK_READY, "v": value})
	else:
		_rpc_set_ready.rpc(value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(value: bool) -> void:
	_apply_remote_ready(value)


func _apply_remote_ready(value: bool) -> void:
	remote_ready = value
	ready_state_changed.emit()


## True when there's a live link AND a present partner to receive a message —
## the shared guard for every player-side send (DIRECT and RELAY).
func _can_send() -> bool:
	return multiplayer.multiplayer_peer != null and remote_present


## Host-only: signal both sides to leave the lobby and start the draft. Picks the
## shared match seed and hands it to the client so both draft reproducibly.
func start_match() -> void:
	if not is_host or not both_ready():
		return
	match_seed = randi()
	# Carry the match config in the start message too, so the client definitely has
	# the chosen mode / best-of even if it missed an earlier set_match_config send.
	if transport == Transport.RELAY:
		_relay_ship({"t": _RK_MATCH_START, "seed": match_seed, "mode": match_mode, "bo": best_of})
	else:
		_rpc_match_start.rpc(match_seed, match_mode, best_of)   # tell the client
	match_starting.emit(match_seed)    # tell ourselves (remote-only path)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_start(seed: int, mode: int, bo: int) -> void:
	_apply_match_start(seed, mode, bo)


func _apply_match_start(seed: int, mode: int, bo: int) -> void:
	match_seed = seed
	match_mode = mode
	best_of = bo
	match_starting.emit(seed)


## Host-only: choose the deck-acquisition mode + best-of and push the choice to the
## client so its lobby can display it. Safe to call before a client is present (the
## broadcast is skipped until one connects; start_match re-sends it regardless).
func set_match_config(mode: int, bo: int) -> void:
	if not is_host:
		return
	match_mode = mode
	best_of = bo
	if remote_present:
		if transport == Transport.RELAY:
			_relay_ship({"t": _RK_MATCH_CONFIG, "mode": mode, "bo": bo})
		else:
			_rpc_match_config.rpc(mode, bo)
	match_config_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_match_config(mode: int, bo: int) -> void:
	_apply_match_config(mode, bo)


func _apply_match_config(mode: int, bo: int) -> void:
	match_mode = mode
	best_of = bo
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

## Send a draft message to the other peer (e.g. {"t":"pick","n":3}).
func send_draft_event(event: Dictionary) -> void:
	if not _can_send():
		return
	if transport == Transport.RELAY:
		_relay_ship({"t": _RK_DRAFT, "event": event})
	else:
		_rpc_draft_event.rpc(event)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_draft_event(event: Dictionary) -> void:
	_apply_draft_event(event)


func _apply_draft_event(event: Dictionary) -> void:
	draft_event_received.emit(event)


# ─────────────────────────────────────────────────────────────────────────
#  COMBAT MESSAGING  (Phases 2-3)
# ─────────────────────────────────────────────────────────────────────────

## CLIENT → HOST: request an action. Executes on the host only; the host reads
## the sender id and validates before applying.
func send_intent(intent: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if transport == Transport.RELAY:
		_relay_ship({"t": _RK_INTENT, "intent": intent})
	else:
		_rpc_combat_intent.rpc_id(1, intent)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_combat_intent(intent: Dictionary) -> void:
	# Runs on the host. Surface the sender so the combat scene can attribute it.
	_apply_combat_intent(multiplayer.get_remote_sender_id(), intent)


func _apply_combat_intent(sender_id: int, intent: Dictionary) -> void:
	combat_intent_received.emit(sender_id, intent)

## HOST → CLIENT(S): broadcast an authoritative event. The host applies its own
## state directly (not through this), so this is call_remote only.
func broadcast_event(event: Dictionary) -> void:
	if not _can_send():
		return
	if transport == Transport.RELAY:
		_relay_ship({"t": _RK_EVENT, "event": event})
	else:
		_rpc_combat_event.rpc(event)

@rpc("authority", "call_remote", "reliable")
func _rpc_combat_event(event: Dictionary) -> void:
	_apply_combat_event(event)


func _apply_combat_event(event: Dictionary) -> void:
	combat_event_received.emit(event)

## HOST → THE ONE CLIENT: send an authoritative event to the client only. This is
## the redaction path — the host chooses which events to forward, so a private
## payload (e.g. the host's own hand) is simply never sent. With 2 players this
## reaches the same recipient as broadcast_event, but the targeted rpc_id keeps
## the "per-recipient" contract explicit for hand_set and friends (plan §14).
func send_to_client(event: Dictionary) -> void:
	if not is_host or not remote_present:
		return
	if transport == Transport.RELAY:
		# The relay forwards to the one room partner — same single recipient.
		_relay_ship({"t": _RK_EVENT, "event": event})
	else:
		if client_peer_id == 0:
			return
		_rpc_combat_event.rpc_id(client_peer_id, event)


# ─────────────────────────────────────────────────────────────────────────
#  COMBAT SCENE LAUNCH  (host-authoritative; both peers transition together)
# ─────────────────────────────────────────────────────────────────────────

## Host-only: drop BOTH peers into the combat scene and set each side's skirmish
## mode. The host triggers the client via RPC, then enters locally, so neither
## side change_scenes on its own (the draft client waits for this).
func launch_combat() -> void:
	if not is_host:
		return
	if transport == Transport.RELAY:
		_relay_ship({"t": _RK_LAUNCH})   # client enters via the relay
	else:
		_rpc_launch_combat.rpc()         # client enters
	_enter_combat_local()                # host enters (the remote path is call_remote only)


@rpc("authority", "call_remote", "reliable")
func _rpc_launch_combat() -> void:
	_enter_combat_local()


func _enter_combat_local() -> void:
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
	get_tree().change_scene_to_file("res://scenes/combat.tscn")


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
func _relay_ship(env: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_rpc_relay_forward.rpc_id(1, env)


## RELAY: forward a player's envelope to that player's room partner ONLY (no
## cross-room leakage — server_relay is off, so the engine never auto-broadcasts).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_relay_forward(env: Dictionary) -> void:
	if not is_relay:
		return
	var sender := multiplayer.get_remote_sender_id()
	var partner: int = int(_relay_partner.get(sender, 0))
	if partner != 0:
		_rpc_relay_deliver.rpc_id(partner, env)


## Player: the relay handed us our partner's envelope. Dispatch as though it had
## arrived over the matching DIRECT @rpc — reusing the same _apply_* bodies.
@rpc("authority", "call_remote", "reliable")
func _rpc_relay_deliver(env: Dictionary) -> void:
	match String(env.get("t", "")):
		_RK_READY:        _apply_remote_ready(bool(env.get("v", false)))
		_RK_MATCH_START:  _apply_match_start(int(env.get("seed", 0)), int(env.get("mode", 0)), int(env.get("bo", 1)))
		_RK_MATCH_CONFIG: _apply_match_config(int(env.get("mode", 0)), int(env.get("bo", 1)))
		_RK_DRAFT:        _apply_draft_event(env.get("event", {}))
		_RK_INTENT:       _apply_combat_intent(relay_partner_id, env.get("intent", {}))
		_RK_EVENT:        _apply_combat_event(env.get("event", {}))
		_RK_LAUNCH:       _enter_combat_local()


# ── Room control: player → relay ──

@rpc("any_peer", "call_remote", "reliable")
func _rpc_create_room() -> void:
	if not is_relay:
		return
	var sender := multiplayer.get_remote_sender_id()
	var code := _relay_make_code()
	_relay_rooms[code] = {"host": sender, "client": 0}
	_relay_peer_room[sender] = code
	_rpc_room_created.rpc_id(sender, code)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_join_room(code: String) -> void:
	if not is_relay:
		return
	var sender := multiplayer.get_remote_sender_id()
	code = code.strip_edges().to_upper()
	if not _relay_rooms.has(code):
		_rpc_room_error.rpc_id(sender, "No open match with that code.")
		return
	var room: Dictionary = _relay_rooms[code]
	if int(room.get("client", 0)) != 0:
		_rpc_room_error.rpc_id(sender, "That match is already full.")
		return
	var host_id := int(room.get("host", 0))
	if host_id == 0 or host_id == sender:
		_rpc_room_error.rpc_id(sender, "That match is no longer open.")
		return
	room["client"] = sender
	_relay_peer_room[sender] = code
	_relay_partner[host_id] = sender
	_relay_partner[sender] = host_id
	# Pair: the room creator is index 0 (host), the joiner index 1 (client).
	_rpc_room_paired.rpc_id(host_id, sender, 0)
	_rpc_room_paired.rpc_id(sender, host_id, 1)


# ── Room control: relay → player (authority = only the relay/peer-1 may call) ──

@rpc("authority", "call_remote", "reliable")
func _rpc_room_created(code: String) -> void:
	relay_room_code = code
	# Creating a room makes us its host (index 0). Pairing re-confirms this later;
	# setting it now lets the lobby show the host's mode picker while we wait, and
	# keeps is_host correct for any host-only UI between create and join.
	is_host = true
	local_player_index = 0
	room_created.emit(code)


@rpc("authority", "call_remote", "reliable")
func _rpc_room_paired(partner_id: int, my_index: int) -> void:
	relay_partner_id = partner_id
	local_player_index = my_index
	is_host = (my_index == 0)
	remote_present = true
	_connected = true
	# Mirror DIRECT's late-ready resend so a pre-pair toggle still propagates.
	if local_ready:
		_send_ready(local_ready)
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

func _relay_on_peer_gone(peer_id: int) -> void:
	var partner: int = int(_relay_partner.get(peer_id, 0))
	if partner != 0:
		_rpc_partner_left.rpc_id(partner)
	var code: String = String(_relay_peer_room.get(peer_id, ""))
	_relay_partner.erase(peer_id)
	_relay_partner.erase(partner)
	_relay_peer_room.erase(peer_id)
	_relay_peer_room.erase(partner)
	if code != "":
		_relay_rooms.erase(code)
