extends SceneTree
## Two-process ENet TRANSPORT smoke test — Online Skirmish.
##
## The logic probe and the combat harness both bypass real sockets (direct calls).
## This one exercises the ACTUAL @rpc plumbing over a real ENet connection on
## loopback (127.0.0.1) — the same code path that carries bytes between the two
## machines over Tailscale. It runs as TWO processes coordinated by an env var:
##
##   $env:SKIRM_ROLE='host';   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish_net.gd
##   $env:SKIRM_ROLE='client'; Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish_net.gd
##
## Verifies, end to end over the socket: host/join, peer signals, the ready
## handshake RPC, match-start seed propagation, a client→host INTENT, and a
## host→client EVENT. Each side prints its own PASS/FAIL and exits 0 (ok) / 1 (fail).

const PORT := 7799
const HOST_ADDR := "127.0.0.1"
const STEP_TIMEOUT := 8.0   # seconds to wait for any single milestone

var NM: Node
var role := ""
var _fails := 0
var _started := false
var _done := false
var _quit_code := 0

# Milestone flags (set by NetMatch signal handlers).
var _peer_seen := false
var _both_ready := false
var _seed_from_host := -1
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
	if role != "host" and role != "client":
		print("[skirmish-net] FATAL: set SKIRM_ROLE=host|client")
		_finish(1)
		return
	NM = root.get_node_or_null("NetMatch")
	if NM == null:
		print("[skirmish-net] FATAL: NetMatch autoload missing")
		_finish(1)
		return
	print("[skirmish-net] start role=%s" % role)

	# Wire the NetMatch signals before connecting so nothing is missed.
	NM.peer_joined.connect(func(_id): _peer_seen = true)
	NM.connected_to_host.connect(func(): _peer_seen = true)
	NM.ready_state_changed.connect(func(): if NM.both_ready(): _both_ready = true)
	NM.match_starting.connect(func(s): _seed_from_host = s)
	NM.combat_intent_received.connect(func(_sid, intent): _intent_seen = intent)
	NM.combat_event_received.connect(func(ev): _event_seen = ev)

	if role == "host":
		await _run_host()
	else:
		await _run_client()

	if _fails == 0:
		print("[skirmish-net] %s ALL PASS" % role)
	else:
		print("[skirmish-net] %s %d FAILURES" % [role, _fails])
	_finish(1 if _fails > 0 else 0)


# Poll a condition (a Callable returning bool) up to STEP_TIMEOUT. True if met.
func _await_until(cond: Callable, what: String) -> bool:
	var elapsed := 0.0
	while elapsed < STEP_TIMEOUT:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		elapsed += 0.1
	_check(false, "timed out waiting for: " + what)
	return false


func _run_host() -> void:
	var err: int = NM.host(PORT)
	_check(err == OK, "host opened a server on :%d" % PORT)
	if err != OK:
		return
	# 1. Client connects.
	if not await _await_until(func(): return _peer_seen, "client to connect"):
		return
	_check(true, "client peer connected over the socket")
	# 2. Ready handshake (both directions): we ready up, client readies up.
	NM.set_local_ready(true)
	if not await _await_until(func(): return _both_ready, "both peers ready"):
		return
	_check(true, "ready handshake round-tripped (both ready)")
	# 3. Start the match — pushes a shared seed to the client.
	NM.start_match()
	await create_timer(0.4).timeout
	# 4. Receive the client's INTENT over the wire.
	if not await _await_until(func(): return not _intent_seen.is_empty(), "client intent"):
		return
	_check(String(_intent_seen.get("t", "")) == NM.IN_PLAY_CREATURE,
		"client→host intent arrived intact (t=%s, lane=%s)" % [_intent_seen.get("t"), str(_intent_seen.get("lane"))])
	_check(int(_intent_seen.get("lane", -1)) == 2 and String(_intent_seen.get("id", "")) == "brute",
		"intent payload fields preserved across the wire")
	# 5. Reply with an authoritative EVENT (board sync) to the client.
	NM.send_to_client({"t": NM.EV_BOARD_SYNC, "host_hp": 25, "client_hp": 22, "active": 1})
	# Hold the connection open a moment so the client receives the reply.
	await create_timer(1.5).timeout


func _run_client() -> void:
	# Give the host a beat to open the server first.
	await create_timer(0.6).timeout
	var err: int = NM.join(HOST_ADDR, PORT)
	_check(err == OK, "join() started toward %s:%d" % [HOST_ADDR, PORT])
	if err != OK:
		return
	# 1. Connected to host.
	if not await _await_until(func(): return _peer_seen, "connection to host"):
		return
	_check(true, "connected to the host over the socket")
	# 2. Ready up; wait for both-ready (host readies too).
	NM.set_local_ready(true)
	if not await _await_until(func(): return _both_ready, "both peers ready"):
		return
	_check(true, "ready handshake round-tripped (both ready)")
	# 3. Receive the shared match seed from the host.
	if not await _await_until(func(): return _seed_from_host >= 0, "match-start seed"):
		return
	_check(NM.match_seed == _seed_from_host, "match-start seed propagated from host (%d)" % _seed_from_host)
	# 4. Send a client→host INTENT over the wire.
	NM.send_intent({"t": NM.IN_PLAY_CREATURE, "uid": 100000, "id": "brute", "lane": 2, "row": 0})
	# 5. Receive the host's authoritative EVENT.
	if not await _await_until(func(): return not _event_seen.is_empty(), "host event"):
		return
	_check(String(_event_seen.get("t", "")) == NM.EV_BOARD_SYNC,
		"host→client event arrived intact (t=%s)" % _event_seen.get("t"))
	_check(int(_event_seen.get("client_hp", -1)) == 22,
		"event payload fields preserved across the wire")


func _finish(code: int) -> void:
	_quit_code = code
	if NM != null:
		NM.leave()
	_done = true
	quit(code)
