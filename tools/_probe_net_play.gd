extends SceneTree
## TWO-PROCESS auto-playing integration test. Both sides run the REAL combat.tscn
## over a loopback ENet socket and, on each of their placement turns, seat one
## creature and end the turn. Drives through round 1 (place-only) into round 2
## (the first real clash) and beyond, watching that:
##   - the turn handoff round-trips (each side gets its turn),
##   - the round counter advances in lockstep,
##   - the clash actually deals damage (a lane-0 trade),
##   - no SCRIPT ERRORs / desyncs appear.
##
##   $env:SKIRM_ROLE='host';   Godot...console.exe --headless --path "D:\Godot" --script res://tools/_probe_net_play.gd
##   $env:SKIRM_ROLE='client'; Godot...console.exe --headless --path "D:\Godot" --script res://tools/_probe_net_play.gd

const PORT := 7820
const HOST_ADDR := "127.0.0.1"

var NM: Node
var SS: Node
var BOT: Node
var role := ""
var combat
var _started := false
var _done := false
var _peer := false
var _both := false
var _seed := -1
var _placed_round := {}   # round_no -> true once we've placed this turn


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	if NM != null: NM.leave()
	_done = true
	quit(code)


func _await_until(cond: Callable, what: String, secs := 12.0) -> bool:
	var e := 0.0
	while e < secs:
		if cond.call(): return true
		await create_timer(0.1).timeout
		e += 0.1
	print("  [%s] TIMEOUT: %s" % [role, what])
	return false


func _log(tag: String) -> void:
	if not is_instance_valid(combat):
		print("  [%s] %s combat freed" % [role, tag]); return
	print("  [%s] %s round=%d active=%d myHP=%d foeHP=%d p_board=%d e_board=%d mana=%d/%d over=%s" % [
		role, tag, int(combat._net_turn_round), int(combat._net_active_index),
		int(combat.player_hp), int(combat.enemy_hp),
		_count(false), _count(true),
		int(combat.player_mana), int(combat.player_max_mana), str(combat._net_match_over)])


func _count(enemy: bool) -> int:
	var n := 0
	for row in [0, 1]:
		for c in combat._row_array(enemy, row):
			if c != null and is_instance_valid(c): n += 1
	return n


func _run() -> void:
	role = OS.get_environment("SKIRM_ROLE")
	NM = root.get_node_or_null("NetMatch")
	SS = root.get_node_or_null("SkirmishState")
	BOT = root.get_node_or_null("SkirmishBot")
	NM.peer_joined.connect(func(_i): _peer = true)
	NM.connected_to_host.connect(func(): _peer = true)
	NM.ready_state_changed.connect(func(): if NM.both_ready(): _both = true)
	NM.match_starting.connect(func(s): _seed = s)

	if role == "host":
		if NM.host(PORT) != OK: print("[np] host fail"); _finish(1); return
		if not await _await_until(func(): return _peer, "peer"): _finish(1); return
		NM.set_local_ready(true)
		if not await _await_until(func(): return _both, "both"): _finish(1); return
		NM.start_match(); await create_timer(0.4).timeout
	else:
		await create_timer(3.0).timeout
		if NM.join(HOST_ADDR, PORT) != OK: print("[np] join fail"); _finish(1); return
		if not await _await_until(func(): return _peer, "connect"): _finish(1); return
		NM.set_local_ready(true)
		if not await _await_until(func(): return _both, "both"): _finish(1); return
		if not await _await_until(func(): return _seed >= 0, "seed"): _finish(1); return

	SS.begin_session()
	var slot: int = NM.local_player_index
	for cid in BOT.build_deck(2000 + slot):
		SS.add_card_to(slot, cid)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)

	# Auto-play loop: whenever it's OUR placement turn, seat a brute in lane 0 (once
	# per round), then end the turn. Runs ~24 s → several rounds + clashes.
	var loops := 0
	while loops < 240 and is_instance_valid(combat) and not combat._net_match_over:
		await create_timer(0.1).timeout
		loops += 1
		if not combat._net_signals_wired:
			combat._net_begin_combat()
			continue
		var active_me: bool = int(combat._net_active_index) == NM.local_player_index
		var my_turn: bool = active_me and combat.phase == combat.Phase.PLAYER_TURN and not combat._net_match_over
		if not my_turn:
			continue
		var rnd: int = int(combat._net_turn_round)
		if not _placed_round.get(rnd, false):
			_placed_round[rnd] = true
			_place_one(rnd)
			await create_timer(0.5).timeout
		# End the turn (host finishes directly, client sends END_ACTIONS).
		combat._net_on_done_placing()
		await create_timer(0.8).timeout
		if loops % 10 == 0:
			_log("t")
	_log("FINAL")
	print("[np] %s done round=%d over=%s" % [role, int(combat._net_turn_round) if is_instance_valid(combat) else -1, str(combat._net_match_over) if is_instance_valid(combat) else "?"])
	_finish(0)


func _place_one(rnd: int) -> void:
	var lane := 0
	var row: int = combat.ROW_FRONT
	# My own creatures are always is_enemy=false locally (host AND client).
	if combat._row_array(false, row)[lane] != null:
		return
	var cdb: Node = root.get_node_or_null("CardDB")
	var data: Dictionary = cdb.get_card_data("brute")
	if data.is_empty(): return
	var uid: int = SS.UID_SLOT_STRIDE * NM.local_player_index + 90 + rnd
	if NM.is_host:
		combat._net_spawn_creature(data, uid, lane, row, false, true)
		combat._net_sync_board()
	else:
		NM.send_intent({"t": NM.IN_PLAY_CREATURE, "id": "brute",
			"uid": uid, "lane": lane, "row": row, "mana": 0})
	print("  [%s] placed brute lane0 (round %d)" % [role, rnd])
