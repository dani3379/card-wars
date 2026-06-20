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

# ── Lobby / handshake signals ──
signal ready_state_changed              # local_ready or remote_ready changed
signal match_starting(seed: int)        # host pressed start; both sides should advance

# ── Gameplay signals (consumed by NetDraft / Combat in later phases) ──
signal draft_event_received(event: Dictionary)    # both directions, draft messages
signal combat_intent_received(sender_id: int, intent: Dictionary)  # host-side: client → host
signal combat_event_received(event: Dictionary)   # client-side: host → client

const DEFAULT_PORT: int = 7717
const MAX_CLIENTS: int = 1   # 1-v-1 only

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
var _peer: ENetMultiplayerPeer = null
var _connected: bool = false
## Host-side: the connected client's ENet peer id (0 = no client). Set when the
## client connects; used by send_to_client to target the one client directly.
var client_peer_id: int = 0

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
	entities.clear()
	_next_entity_id = 1
	lobby_reset.emit()


func is_connected_to_peer() -> bool:
	return _connected and remote_present


# ─────────────────────────────────────────────────────────────────────────
#  ENGINE SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	# On the host this fires when the client arrives; on the client it fires for
	# the server (id 1). Either way it means "the other side is here."
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
	remote_present = false
	remote_ready = false
	if peer_id == client_peer_id:
		client_peer_id = 0
	peer_left.emit(peer_id)
	ready_state_changed.emit()


func _on_connected_to_server() -> void:
	_connected = true
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
	if multiplayer.multiplayer_peer == null or not remote_present:
		return
	_rpc_set_ready.rpc(value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(value: bool) -> void:
	remote_ready = value
	ready_state_changed.emit()


## Host-only: signal both sides to leave the lobby and start the draft. Picks the
## shared match seed and hands it to the client so both draft reproducibly.
func start_match() -> void:
	if not is_host or not both_ready():
		return
	match_seed = randi()
	_rpc_match_start.rpc(match_seed)   # tell the client
	match_starting.emit(match_seed)    # tell ourselves (rpc is call_remote only)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_start(seed: int) -> void:
	match_seed = seed
	match_starting.emit(seed)


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
	if multiplayer.multiplayer_peer == null or not remote_present:
		return
	_rpc_draft_event.rpc(event)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_draft_event(event: Dictionary) -> void:
	draft_event_received.emit(event)


# ─────────────────────────────────────────────────────────────────────────
#  COMBAT MESSAGING  (Phases 2-3)
# ─────────────────────────────────────────────────────────────────────────

## CLIENT → HOST: request an action. Executes on the host only; the host reads
## the sender id and validates before applying.
func send_intent(intent: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_rpc_combat_intent.rpc_id(1, intent)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_combat_intent(intent: Dictionary) -> void:
	# Runs on the host. Surface the sender so the combat scene can attribute it.
	combat_intent_received.emit(multiplayer.get_remote_sender_id(), intent)

## HOST → CLIENT(S): broadcast an authoritative event. The host applies its own
## state directly (not through this), so this is call_remote only.
func broadcast_event(event: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or not remote_present:
		return
	_rpc_combat_event.rpc(event)

@rpc("authority", "call_remote", "reliable")
func _rpc_combat_event(event: Dictionary) -> void:
	combat_event_received.emit(event)

## HOST → THE ONE CLIENT: send an authoritative event to the client only. This is
## the redaction path — the host chooses which events to forward, so a private
## payload (e.g. the host's own hand) is simply never sent. With 2 players this
## reaches the same recipient as broadcast_event, but the targeted rpc_id keeps
## the "per-recipient" contract explicit for hand_set and friends (plan §14).
func send_to_client(event: Dictionary) -> void:
	if not is_host or client_peer_id == 0 or not remote_present:
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
	_rpc_launch_combat.rpc()   # client enters
	_enter_combat_local()      # host enters (rpc is call_remote only)


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
