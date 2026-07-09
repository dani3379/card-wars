extends SceneTree
## TWO-PROCESS real-combat deadlock repro. Runs the ACTUAL combat.tscn on both
## host and client over a real ENet loopback socket (the same code path as a live
## match), then watches whether EITHER side's turn ever opens.
##
##   $env:SKIRM_ROLE='host';   Godot...console.exe --headless --path "D:\Godot" --script res://tools/_probe_net_combat2.gd
##   $env:SKIRM_ROLE='client'; Godot...console.exe --headless --path "D:\Godot" --script res://tools/_probe_net_combat2.gd

const PORT := 7806
const HOST_ADDR := "127.0.0.1"

var NM: Node
var SS: Node
var BOT: Node
var role := ""
var combat
var _started := false
var _done := false
var _peer_seen := false
var _both_ready := false
var _seed_seen := -1


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	if NM != null:
		NM.leave()
	_done = true
	quit(code)


func _await_until(cond: Callable, what: String, secs := 10.0) -> bool:
	var e := 0.0
	while e < secs:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		e += 0.1
	print("  [%s] TIMEOUT waiting: %s" % [role, what])
	return false


func _log_state(tag: String) -> void:
	if not is_instance_valid(combat):
		print("  [%s] %s: combat freed" % [role, tag]); return
	var btxt := ""
	if combat._end_turn_btn != null:
		btxt = "%s(disabled=%s)" % [combat._end_turn_btn.text, str(combat._end_turn_btn.disabled)]
	print("  [%s] %s: round=%d active=%d mana=%d/%d hand=%d draw=%d foeMana=%d/%d over=%s btn=%s" % [
		role, tag, int(combat._net_turn_round), int(combat._net_active_index),
		int(combat.player_mana), int(combat.player_max_mana),
		combat._hand.size(), combat._player_draw_pile.size(),
		int(combat._net_opp_mana), int(combat._net_opp_max_mana),
		str(combat._net_match_over), btxt])


func _run() -> void:
	role = OS.get_environment("SKIRM_ROLE")
	NM = root.get_node_or_null("NetMatch")
	SS = root.get_node_or_null("SkirmishState")
	BOT = root.get_node_or_null("SkirmishBot")
	if role != "host" and role != "client":
		print("[nc2] set SKIRM_ROLE"); _finish(1); return
	NM.peer_joined.connect(func(_id): _peer_seen = true)
	NM.connected_to_host.connect(func(): _peer_seen = true)
	NM.ready_state_changed.connect(func(): if NM.both_ready(): _both_ready = true)
	NM.match_starting.connect(func(s): _seed_seen = s)

	if role == "host":
		var err: int = NM.host(PORT)
		if err != OK: print("[nc2] host err %d" % err); _finish(1); return
		if not await _await_until(func(): return _peer_seen, "peer"): _finish(1); return
		NM.set_local_ready(true)
		if not await _await_until(func(): return _both_ready, "both ready"): _finish(1); return
		NM.start_match()
		await create_timer(0.4).timeout
	else:
		await create_timer(4.0).timeout
		var err2: int = NM.join(HOST_ADDR, PORT)
		if err2 != OK: print("[nc2] join err %d" % err2); _finish(1); return
		if not await _await_until(func(): return _peer_seen, "connect"): _finish(1); return
		NM.set_local_ready(true)
		if not await _await_until(func(): return _both_ready, "both ready"): _finish(1); return
		if not await _await_until(func(): return _seed_seen >= 0, "seed"): _finish(1); return

	# ── Both sides now set up SkirmishState exactly like _enter_combat_local + the
	# deck-acquisition scene would, then instantiate the real combat scene. ──
	SS.begin_session()
	var my_slot: int = NM.local_player_index
	var mydeck: Array = BOT.build_deck(1000 + my_slot)
	for cid in mydeck:
		SS.add_card_to(my_slot, cid)
	print("  [%s] set up: is_host=%s local_index=%d style=%d deck=%d" % [
		role, str(NM.is_host), NM.local_player_index, int(NM.battle_style), mydeck.size()])

	# Force the CLIENT to be the first player, so the client MUST receive the
	# host's EV_TURN_BEGIN to open its turn (host-first would open locally and
	# hide the race). Both sides set the same override so they agree.
	# Optionally delay the client's combat entry to simulate a slow prebake — this
	# makes the client subscribe to combat_event_received AFTER the host has already
	# fired EV_TURN_BEGIN, so the event is dropped (no subscriber) → deadlock.
	var delay := float(OS.get_environment("SKIRM_DELAY"))
	if role == "client" and delay > 0.0:
		print("  [client] simulating slow entry: sleeping %.1fs before combat" % delay)
		await create_timer(delay).timeout
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 1   # client (index 1) opens round 1
	root.add_child(combat)

	# Watch the turn machine for ~14 s. A healthy match: within a few seconds one
	# side's turn opens (mana 3/3, btn DONE) and eventually the round advances.
	for i in 28:
		await create_timer(0.5).timeout
		if not combat._net_signals_wired and is_instance_valid(combat):
			# safety: kick the handshake if _ready parked on prebake
			combat._net_begin_combat()
		if i % 4 == 3:
			_log_state("t=%.1f" % ((i + 1) * 0.5))

	_log_state("FINAL")
	print("[nc2] %s done" % role)
	_finish(0)
