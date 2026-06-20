extends SceneTree
## Board-verb CORRECTNESS probe (2026-06-18). The 4×4 position verbs added
## 2026-06-17 — shove_back / haul_front / vanguard_split / snipe_back — are
## exercised by the autorun bot for CRASHES, but never asserted to do the RIGHT
## thing (the curve memory flagged them "runtime feel still needs a playtest").
## This boots real combat, builds a known board, fires each verb through the real
## _resolve_on_play_ability, and ASSERTS the board changed as the card text claims:
## the creature actually relocated, the draw fired, the damage landed, and the
## "no valid move" fallbacks deal their chip instead of whiffing.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_boardverbs.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
var RS: Node
var EDB: Node
var US: Node
var SS: Node
var combat: Node
var _started := false
var _pass := 0
var _fail: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[verbs] start")
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null or EDB == null:
		print("[verbs] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[verbs] FATAL no player turn"); quit(1); return

	await _test_shove_moves()
	await _test_shove_blocked_fallback()
	await _test_haul_moves_and_damages()
	await _test_vanguard_front_buff()
	await _test_vanguard_back_draw()
	await _test_snipe_back()

	print("[verbs] ============ SUMMARY ============")
	print("[verbs] passed : %d" % _pass)
	print("[verbs] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[verbs] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _test_shove_moves() -> void:
	_clear_all()
	var e = _place(2, 3, 1, true, combat.ROW_FRONT)   # enemy front lane 1
	var p = _place(0, 1, 1, false, combat.ROW_FRONT)  # our verb carrier, lane 1
	p.card_data["on_play"] = {"type": "shove_back", "value": 2}
	await combat._resolve_on_play_ability(p, 1, false)
	var front = combat._row_array(true, combat.ROW_FRONT)[1]
	var back = combat._row_array(true, combat.ROW_BACK)[1]
	_assert("shove_back: front→back (front cleared)", front == null)
	_assert("shove_back: creature now in back lane", back == e)


func _test_shove_blocked_fallback() -> void:
	_clear_all()
	var e = _place(2, 5, 1, true, combat.ROW_FRONT)
	_place(2, 5, 1, true, combat.ROW_BACK)            # back lane BLOCKED
	var hp0 := int(e.current_hp)
	var p = _place(0, 1, 1, false, combat.ROW_FRONT)
	p.card_data["on_play"] = {"type": "shove_back", "value": 3}
	await combat._resolve_on_play_ability(p, 1, false)
	var front = combat._row_array(true, combat.ROW_FRONT)[1]
	_assert("shove_back blocked: front stays put", front == e)
	_assert("shove_back blocked: deals value instead (no whiff)", int(e.current_hp) == hp0 - 3)


func _test_haul_moves_and_damages() -> void:
	_clear_all()
	var e = _place(2, 4, 2, true, combat.ROW_BACK)    # enemy hiding in back lane 2
	var hp0 := int(e.current_hp)
	var p = _place(0, 1, 2, false, combat.ROW_FRONT)
	p.card_data["on_play"] = {"type": "haul_front", "value": 2}
	await combat._resolve_on_play_ability(p, 2, false)
	var front = combat._row_array(true, combat.ROW_FRONT)[2]
	var back = combat._row_array(true, combat.ROW_BACK)[2]
	_assert("haul_front: back→front (pulled out)", front == e)
	_assert("haul_front: back lane cleared", back == null)
	_assert("haul_front: deals value to the hooked body", int(e.current_hp) == hp0 - 2)


func _test_vanguard_front_buff() -> void:
	_clear_all()
	var p = _place(2, 3, 0, false, combat.ROW_FRONT)
	var atk0 := int(p.current_atk)
	p.card_data["on_play"] = {"type": "vanguard_split", "value": 2}
	await combat._resolve_on_play_ability(p, 0, false)
	_assert("vanguard_split FRONT: +value ATK", int(p.current_atk) == atk0 + 2)


func _test_vanguard_back_draw() -> void:
	_clear_all()
	# Guarantee something to draw.
	if combat._player_draw_pile.is_empty():
		combat._player_draw_pile.append(combat._pile_entry("goblin", -1))
	var p = _place(2, 3, 0, false, combat.ROW_BACK)
	var hand0: int = combat._hand.size()
	p.card_data["on_play"] = {"type": "vanguard_split", "value": 2}
	await combat._resolve_on_play_ability(p, 0, false)
	_assert("vanguard_split BACK: draws a card", combat._hand.size() == hand0 + 1)


func _test_snipe_back() -> void:
	_clear_all()
	var e = _place(2, 4, 3, true, combat.ROW_BACK)    # the only back-row body
	var hp0 := int(e.current_hp)
	var p = _place(0, 1, 0, false, combat.ROW_FRONT)
	p.card_data["on_play"] = {"type": "snipe_back", "value": 2}
	await combat._resolve_on_play_ability(p, 0, false)
	_assert("snipe_back: hits a back-row creature", int(e.current_hp) == hp0 - 2)


# --- helpers ---

func _place(atk: int, hp: int, lane: int, is_enemy: bool, row: int):
	var arr: Array = combat._row_array(is_enemy, row)
	if arr[lane] != null and is_instance_valid(arr[lane]):
		arr[lane].queue_free()
		arr[lane] = null
	combat.summon_token(atk, hp, lane, is_enemy, row)
	return combat._row_array(is_enemy, row)[lane]


func _clear_all() -> void:
	for is_e in [true, false]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_e, row)
			for l in range(combat.LANES_PER_ROW):
				if arr[l] != null and is_instance_valid(arr[l]):
					arr[l].queue_free()
					arr[l] = null


func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("[verbs] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[verbs] FAIL  %s" % name)


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
