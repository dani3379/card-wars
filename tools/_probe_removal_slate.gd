extends SceneTree
## Correctness probe for the 2026-07-09 removal slate (Into-the-Breach push
## physics). Boots real SOLO combat, builds known boards, fires each spell
## through the real _resolve_custom_spell, and asserts the board changed as the
## card text claims:
##   Shove (rework)     — one lane toward the nearest flank; blocked = crash
##                        (2 damage to each party); "+" bloodies the target first
##   Sapper's Charge    — all physics: 1 scorch on the target, row neighbours
##                        hurled one lane outward, crashes carry the payload (4)
##   Ballista Bolt      — 5 that punches through: overkill carries to the body
##                        behind, then to enemy face; a survivor stops it
##   Scatter the Line   — every enemy blown toward its nearest flank, outer
##                        lanes first; packed lines crash, loose lines slide
##   Earthquake (rework)— the shake now collapses BOTH front lines
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_removal_slate.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
var RS: Node
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
	print("[removal] start")
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null:
		print("[removal] FATAL autoloads"); quit(1); return
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
		print("[removal] FATAL no player turn"); quit(1); return

	await _test_shove_slides_to_flank()
	await _test_shove_edge_crash()
	await _test_shove_body_crash()
	await _test_shove_plus_predamage()
	await _test_sappers_charge()
	await _test_sappers_charge_plus_body_crash()
	await _test_ballista_punch_through()
	await _test_ballista_stopped_by_survivor()
	await _test_scatter_packed_line()
	await _test_scatter_loose_line()
	await _test_earthquake_shakes_both_sides()

	print("[removal] ============ SUMMARY ============")
	print("[removal] passed : %d" % _pass)
	print("[removal] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[removal] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _test_shove_slides_to_flank() -> void:
	_clear_all()
	var e = _place(2, 6, 1, true, combat.ROW_FRONT)   # lane 1 → nearest flank is LEFT
	var hp0 := int(e.current_hp)
	await combat._resolve_custom_spell("shove", e, -1, {})
	_assert("shove: lane-1 body slid to lane 0 (nearest flank)",
		combat._row_array(true, combat.ROW_FRONT)[0] == e and int(e.current_lane) == 0)
	_assert("shove: source lane vacated", combat._row_array(true, combat.ROW_FRONT)[1] == null)
	_assert("shove: a clean slide deals no damage", int(e.current_hp) == hp0)


func _test_shove_edge_crash() -> void:
	_clear_all()
	var e = _place(2, 6, 0, true, combat.ROW_FRONT)   # already on the flank
	var hp0 := int(e.current_hp)
	await combat._resolve_custom_spell("shove", e, -1, {})
	_assert("shove edge: creature holds its lane",
		combat._row_array(true, combat.ROW_FRONT)[0] == e and int(e.current_lane) == 0)
	_assert("shove edge: crash deals 2", int(e.current_hp) == hp0 - 2)


func _test_shove_body_crash() -> void:
	_clear_all()
	var blocker = _place(2, 6, 0, true, combat.ROW_FRONT)
	var e = _place(2, 6, 1, true, combat.ROW_FRONT)
	await combat._resolve_custom_spell("shove", e, -1, {})
	_assert("shove crash: pushed body stays put with 2 damage",
		int(e.current_lane) == 1 and int(e.current_hp) == 4)
	_assert("shove crash: blocker also takes 2", int(blocker.current_hp) == 4)


func _test_shove_plus_predamage() -> void:
	_clear_all()
	var e = _place(2, 6, 2, true, combat.ROW_FRONT)   # lane 2 → nearest flank is RIGHT
	await combat._resolve_custom_spell("shove", e, -1, {"dmg_bonus": 2})
	_assert("shove+: 2 pre-damage landed, then the slide (lane 3)",
		int(e.current_hp) == 4 and int(e.current_lane) == 3)


func _test_sappers_charge() -> void:
	_clear_all()
	var left = _place(2, 6, 0, true, combat.ROW_FRONT)    # blast throws it LEFT → edge crash
	var mid = _place(2, 9, 1, true, combat.ROW_FRONT)     # the bomb target — only scorched
	var right = _place(2, 6, 2, true, combat.ROW_FRONT)   # blast throws it RIGHT → lane 3 open
	await combat._resolve_custom_spell("sappers_charge", mid, -1, {})
	_assert("charge: target only takes the 1-damage scorch", int(mid.current_hp) == 8)
	_assert("charge: edge-bound neighbour crashes for 4 in place",
		int(left.current_lane) == 0 and int(left.current_hp) == 2)
	_assert("charge: open-side neighbour is thrown to lane 3 unharmed",
		combat._row_array(true, combat.ROW_FRONT)[3] == right and int(right.current_hp) == 6)


func _test_sappers_charge_plus_body_crash() -> void:
	_clear_all()
	# Upgraded charge with a packed right side: the lane-2 neighbour is hurled
	# into the occupied lane 3 — a body crash at the upgraded 6, both parties.
	var mid = _place(2, 9, 1, true, combat.ROW_FRONT)
	var n2 = _place(2, 9, 2, true, combat.ROW_FRONT)
	var n3 = _place(2, 9, 3, true, combat.ROW_FRONT)
	await combat._resolve_custom_spell("sappers_charge", mid, -1, {"dmg_bonus": 2})
	_assert("charge+: scorch still 1 (the '+' rides the crash, not the powder)",
		int(mid.current_hp) == 8)
	_assert("charge+: body crash deals 6 to the hurled neighbour",
		int(n2.current_lane) == 2 and int(n2.current_hp) == 3)
	_assert("charge+: body crash deals 6 to the blocker too", int(n3.current_hp) == 3)


func _test_ballista_punch_through() -> void:
	_clear_all()
	var front = _place(2, 2, 2, true, combat.ROW_FRONT)   # absorbs 2
	var back = _place(2, 1, 2, true, combat.ROW_BACK)     # absorbs 1
	var face0: int = int(combat.enemy_hp)
	await combat._resolve_custom_spell("ballista_bolt", front, -1, {})
	_assert("bolt: first body died", not is_instance_valid(front) or front.current_hp <= 0)
	_assert("bolt: spill killed the body behind", not is_instance_valid(back) or back.current_hp <= 0)
	_assert("bolt: remaining 2 punched to face (%d → %d)" % [face0, int(combat.enemy_hp)],
		int(combat.enemy_hp) == face0 - 2)


func _test_ballista_stopped_by_survivor() -> void:
	_clear_all()
	var front = _place(2, 6, 1, true, combat.ROW_FRONT)   # survives on 1
	var back = _place(2, 4, 1, true, combat.ROW_BACK)
	var face0: int = int(combat.enemy_hp)
	await combat._resolve_custom_spell("ballista_bolt", front, -1, {})
	_assert("bolt stopped: survivor holds the bolt at 1 HP", int(front.current_hp) == 1)
	_assert("bolt stopped: the body behind is untouched", int(back.current_hp) == 4)
	_assert("bolt stopped: no face damage", int(combat.enemy_hp) == face0)


func _test_scatter_packed_line() -> void:
	_clear_all()
	var e0 = _place(2, 10, 0, true, combat.ROW_FRONT)
	var e1 = _place(2, 10, 1, true, combat.ROW_FRONT)
	var e2 = _place(2, 10, 2, true, combat.ROW_FRONT)
	var e3 = _place(2, 10, 3, true, combat.ROW_FRONT)
	await combat._resolve_custom_spell("scatter_line", null, -1, {})
	# Outer lanes crash on the edge (2) then eat their neighbour's crash (2 more);
	# inner lanes crash once. Nobody moves on a packed line.
	_assert("scatter packed: lane 0 crushed twice (edge + neighbour) for 4",
		int(e0.current_lane) == 0 and int(e0.current_hp) == 6)
	_assert("scatter packed: lane 1 crashes once for 2",
		int(e1.current_lane) == 1 and int(e1.current_hp) == 8)
	_assert("scatter packed: lane 2 crashes once for 2",
		int(e2.current_lane) == 2 and int(e2.current_hp) == 8)
	_assert("scatter packed: lane 3 crushed twice (edge + neighbour) for 4",
		int(e3.current_lane) == 3 and int(e3.current_hp) == 6)


func _test_scatter_loose_line() -> void:
	_clear_all()
	var e1 = _place(2, 6, 1, true, combat.ROW_FRONT)
	var e2 = _place(2, 6, 2, true, combat.ROW_FRONT)
	await combat._resolve_custom_spell("scatter_line", null, -1, {})
	_assert("scatter loose: lane 1 slid to the open flank unharmed",
		combat._row_array(true, combat.ROW_FRONT)[0] == e1 and int(e1.current_hp) == 6)
	_assert("scatter loose: lane 2 slid to the open flank unharmed",
		combat._row_array(true, combat.ROW_FRONT)[3] == e2 and int(e2.current_hp) == 6)


func _test_earthquake_shakes_both_sides() -> void:
	_clear_all()
	var foe = _place(2, 6, 0, true, combat.ROW_FRONT)
	var own = _place(2, 6, 1, false, combat.ROW_FRONT)
	await combat._resolve_custom_spell("earthquake", null, -1, {})
	_assert("quake: enemy front took 2 and fell back",
		int(foe.current_hp) == 4 and combat._row_array(true, combat.ROW_BACK)[0] == foe)
	_assert("quake: PLAYER front took 2 and fell back too (no side-taking)",
		int(own.current_hp) == 4 and combat._row_array(false, combat.ROW_BACK)[1] == own)


# --- helpers (same kit as _probe_boardverbs) ---

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
		print("[removal] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[removal] FAIL  %s" % name)


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
