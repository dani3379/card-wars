extends SceneTree
## _probe_relay.gd — verification for the RELAY transport (room codes, NAT-free).
##
## Two layers, mirroring the existing skirmish probes:
##
##   LOGIC  (default; no env, no sockets) — room-code generation + collision
##          avoidance, and the relay-deliver envelope DISPATCH table (every kind
##          routes to the same _apply_* body the DIRECT @rpc uses). Fast.
##     Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relay.gd
##
##   SOCKET (SKIRM_ROLE=relay|host|client) — THREE real processes over loopback:
##          a relay, a host that creates a room, and a client that joins by the
##          code. Proves create→code→join→pair→ready→seed→intent/event ALL the way
##          THROUGH the relay (server_relay off; per-room forwarding). The host and
##          client exchange the room code via a shared user:// file (no direct link
##          — that's the whole point). Start the relay first, then host + client:
##     $env:SKIRM_ROLE='relay';  Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relay.gd
##     $env:SKIRM_ROLE='host';   Godot.exe ... (same)
##     $env:SKIRM_ROLE='client'; Godot.exe ... (same)

const PORT := 7798
const ADDR := "127.0.0.1"
const STEP_TIMEOUT := 8.0
const RELAY_TTL := 25.0
const CODE_FILE := "user://_relay_probe_code.txt"

var NM: Node
var role := ""
var _fails := 0
var _started := false
var _done := false

# Milestone flags (set by NetMatch signal handlers).
var _peer_seen := false
var _both_ready := false
var _seed_from_host := -1
var _room_code := ""
var _room_err := ""
var _intent_seen := {}
var _event_seen := {}


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  [%s] %s" % [role, label])
	else:
		_fails += 1
		print("  FAIL  [%s] %s" % [role, label])


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	role = OS.get_environment("SKIRM_ROLE")
	if role == "":
		role = "logic"
	NM = root.get_node_or_null("NetMatch")
	if NM == null:
		print("[relay-probe] FATAL: NetMatch autoload missing")
		_finish(1)
		return
	print("[relay-probe] start role=%s" % role)

	NM.peer_joined.connect(func(_id): _peer_seen = true)
	NM.connected_to_host.connect(func(): _peer_seen = true)
	NM.room_created.connect(func(c): _room_code = c)
	NM.room_error.connect(func(r): _room_err = r)
	NM.ready_state_changed.connect(func(): if NM.both_ready(): _both_ready = true)
	NM.match_starting.connect(func(s): _seed_from_host = s)
	NM.combat_intent_received.connect(func(_sid, intent): _intent_seen = intent)
	NM.combat_event_received.connect(func(ev): _event_seen = ev)

	match role:
		"logic":  _run_logic()
		"relay":  await _run_relay()
		"host":   await _run_host()
		"client": await _run_client()
		_:
			print("[relay-probe] FATAL: bad SKIRM_ROLE")
			_finish(1)
			return

	if _fails == 0:
		print("[relay-probe] %s ALL PASS" % role)
	else:
		print("[relay-probe] %s %d FAILURES" % [role, _fails])
	_finish(1 if _fails > 0 else 0)


func _await_until(cond: Callable, what: String) -> bool:
	var elapsed := 0.0
	while elapsed < STEP_TIMEOUT:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		elapsed += 0.1
	_check(false, "timed out waiting for: " + what)
	return false


# ── LOGIC: code generation + envelope dispatch (no sockets) ──
func _run_logic() -> void:
	# 1. Room-code generation: valid length, safe alphabet, varied.
	var seen := {}
	var bad := 0
	for _i in 300:
		var c: String = NM._relay_make_code()
		if c.length() != NM.ROOM_CODE_LEN:
			bad += 1
		for ch in c:
			if not (String(ch) in NM.ROOM_CODE_ALPHABET):
				bad += 1
		seen[c] = true
	_check(bad == 0, "codes are %d chars from the safe alphabet" % NM.ROOM_CODE_LEN)
	_check(seen.size() > 200, "codes vary (%d distinct of 300)" % seen.size())

	# 2. Collision avoidance against an occupied code.
	NM._relay_rooms.clear()
	var taken: String = NM._relay_make_code()
	NM._relay_rooms[taken] = {"host": 1, "client": 0}
	var collided := false
	for _i in 100:
		if NM._relay_make_code() == taken:
			collided = true
	_check(not collided, "make_code never returns an occupied code")
	NM._relay_rooms.clear()

	# 3. The relay-deliver dispatch table — each kind hits the right _apply_* body.
	NM.relay_partner_id = 4242
	var got := {"event": {}, "intent": {}, "sid": -1, "draft": {}, "ready": false, "seed": -1, "cfg": false}
	NM.combat_event_received.connect(func(e): got["event"] = e)
	NM.combat_intent_received.connect(func(sid, i): got["intent"] = i; got["sid"] = sid)
	NM.draft_event_received.connect(func(e): got["draft"] = e)
	NM.ready_state_changed.connect(func(): got["ready"] = NM.remote_ready)
	NM.match_starting.connect(func(s): got["seed"] = s)
	NM.match_config_changed.connect(func(): got["cfg"] = true)

	NM._rpc_relay_deliver({"t": NM._RK_EVENT, "event": {"t": NM.EV_BOARD_SYNC, "client_hp": 7}})
	_check(int(got["event"].get("client_hp", -1)) == 7, "deliver EVENT → combat_event_received")

	NM._rpc_relay_deliver({"t": NM._RK_INTENT, "intent": {"t": NM.IN_PLAY_CREATURE, "lane": 3}})
	_check(int(got["intent"].get("lane", -1)) == 3 and got["sid"] == 4242,
		"deliver INTENT → combat_intent_received (attributed to the partner)")

	NM._rpc_relay_deliver({"t": NM._RK_DRAFT, "event": {"t": "pick", "n": 5}})
	_check(int(got["draft"].get("n", -1)) == 5, "deliver DRAFT → draft_event_received")

	NM._rpc_relay_deliver({"t": NM._RK_READY, "v": true})
	_check(got["ready"] and NM.remote_ready, "deliver READY → remote_ready set")

	NM._rpc_relay_deliver({"t": NM._RK_MATCH_START, "seed": 9988, "mode": 0, "bo": 3})
	_check(got["seed"] == 9988 and NM.best_of == 3, "deliver MATCH_START → seed + best_of")

	NM._rpc_relay_deliver({"t": NM._RK_MATCH_CONFIG, "mode": 1, "bo": 1})
	_check(got["cfg"] and NM.match_mode == 1, "deliver MATCH_CONFIG → match_mode")

	NM.leave()   # reset the shared autoload after poking it


# ── SOCKET: the relay process (stays up for the test window) ──
func _run_relay() -> void:
	var err: int = NM.run_as_relay(PORT)
	_check(err == OK, "relay opened on :%d (server_relay off)" % PORT)
	if err != OK:
		return
	print("[relay-probe] relay up; holding %ds for host+client" % int(RELAY_TTL))
	await create_timer(RELAY_TTL).timeout


# ── SOCKET: the host process (creates a room, shares the code via a file) ──
func _run_host() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
	if FileAccess.file_exists(CODE_FILE):
		DirAccess.remove_absolute(CODE_FILE)
	await create_timer(0.8).timeout   # let the relay come up first
	var err: int = NM.host_via_relay(ADDR, PORT)
	_check(err == OK, "host_via_relay started toward the relay")
	if err != OK:
		return
	if not await _await_until(func(): return _room_code != "", "room code from the relay"):
		return
	_check(_room_code.length() == NM.ROOM_CODE_LEN, "relay assigned a room code: %s" % _room_code)
	var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_line(_room_code)
		f.close()
	if not await _await_until(func(): return _peer_seen, "client to join the room"):
		return
	_check(NM.is_host and NM.local_player_index == 0, "host paired as index 0")
	NM.set_local_ready(true)
	if not await _await_until(func(): return _both_ready, "both peers ready"):
		return
	_check(true, "ready handshake round-tripped through the relay")
	NM.start_match()
	await create_timer(0.4).timeout
	if not await _await_until(func(): return not _intent_seen.is_empty(), "client intent via relay"):
		return
	_check(String(_intent_seen.get("t", "")) == NM.IN_PLAY_CREATURE and int(_intent_seen.get("lane", -1)) == 2,
		"client→host intent forwarded intact (lane=%s)" % str(_intent_seen.get("lane")))
	NM.send_to_client({"t": NM.EV_BOARD_SYNC, "host_hp": 25, "client_hp": 22, "active": 1})
	await create_timer(1.5).timeout


# ── SOCKET: the client process (reads the code, joins the room) ──
func _run_client() -> void:
	await create_timer(0.8).timeout
	var code := ""
	var elapsed := 0.0
	while elapsed < STEP_TIMEOUT:
		if FileAccess.file_exists(CODE_FILE):
			var f := FileAccess.open(CODE_FILE, FileAccess.READ)
			if f != null:
				code = f.get_line().strip_edges()
				f.close()
			if code != "":
				break
		await create_timer(0.2).timeout
		elapsed += 0.2
	_check(code != "", "received the room code from the host (%s)" % code)
	if code == "":
		return
	var err: int = NM.join_via_relay(ADDR, PORT, code)
	_check(err == OK, "join_via_relay started")
	if err != OK:
		return
	if not await _await_until(func(): return _peer_seen, "pairing with the host"):
		return
	_check(not NM.is_host and NM.local_player_index == 1, "client paired as index 1")
	NM.set_local_ready(true)
	if not await _await_until(func(): return _both_ready, "both peers ready"):
		return
	_check(true, "ready handshake round-tripped through the relay")
	if not await _await_until(func(): return _seed_from_host >= 0, "match-start seed"):
		return
	_check(NM.match_seed == _seed_from_host, "match seed propagated via relay (%d)" % _seed_from_host)
	NM.send_intent({"t": NM.IN_PLAY_CREATURE, "uid": 100000, "id": "brute", "lane": 2, "row": 0})
	if not await _await_until(func(): return not _event_seen.is_empty(), "host event via relay"):
		return
	_check(String(_event_seen.get("t", "")) == NM.EV_BOARD_SYNC and int(_event_seen.get("client_hp", -1)) == 22,
		"host→client event forwarded intact (client_hp=%s)" % str(_event_seen.get("client_hp")))


func _finish(code: int) -> void:
	if NM != null:
		NM.leave()
	_done = true
	quit(code)
