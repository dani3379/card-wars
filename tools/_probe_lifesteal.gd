extends SceneTree
## Lifesteal CORRECTNESS probe (2026-07-10). The keyword was reworked from
## "heal a flat N per strike" to "heal for the damage the strike actually
## dealt" — the HP the target really lost, not the attacker's printed ATK.
## This boots real solo combat and drives the real strike resolvers, asserting
## the four edges of the new rule:
##   overkill  — 5 ATK into a 2 HP body heals 2 (capped at what it lost)
##   Armored   — the -1 trim shrinks the heal with the damage
##   Shield    — a fully absorbed hit heals 0
##   face      — an unblocked swing heals the full face damage
## plus the hero cap (never above player_max_hp).
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_lifesteal.gd

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
	print("[lifesteal] start")
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null:
		print("[lifesteal] FATAL autoloads"); quit(1); return
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
		print("[lifesteal] FATAL no player turn"); quit(1); return

	await _test_overkill_caps_heal()
	await _test_armored_trims_heal()
	await _test_shield_heals_zero()
	await _test_face_swing_heals_full()
	await _test_heal_caps_at_max_hp()

	print("[lifesteal] ============ SUMMARY ============")
	print("[lifesteal] passed : %d" % _pass)
	print("[lifesteal] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[lifesteal] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _test_overkill_caps_heal() -> void:
	_clear_all()
	var p = _place_lifestealer(5, 5, 1)
	var e = _place(0, 2, 1, true, combat.ROW_FRONT)   # 2 HP body, no counter
	combat.player_hp = 10
	await combat._creature_attacks_creature(p, e, 1, false)
	_assert("overkill: 5 ATK into 2 HP heals exactly 2 (10 -> 12)", combat.player_hp == 12)


func _test_armored_trims_heal() -> void:
	_clear_all()
	var p = _place_lifestealer(5, 5, 1)
	var e = _place(0, 10, 1, true, combat.ROW_FRONT)
	e.card_data["keywords"] = ["armored"]
	combat.player_hp = 10
	await combat._creature_attacks_creature(p, e, 1, false)
	_assert("armored: 5 ATK trimmed to 4 damage heals 4 (10 -> 14)", combat.player_hp == 14)


func _test_shield_heals_zero() -> void:
	_clear_all()
	var p = _place_lifestealer(5, 5, 1)
	var e = _place(0, 10, 1, true, combat.ROW_FRONT)
	e.state.has_shield = true
	combat.player_hp = 10
	await combat._creature_attacks_creature(p, e, 1, false)
	_assert("shield: a fully absorbed hit heals 0 (10 -> 10)", combat.player_hp == 10)


func _test_face_swing_heals_full() -> void:
	_clear_all()
	var p = _place_lifestealer(5, 5, 1)
	combat.player_hp = 10
	var foe_before: int = combat.enemy_hp
	await combat._creature_hits_face(p, 1, false)
	_assert("face: the swing landed on the enemy hero", combat.enemy_hp == foe_before - 5)
	_assert("face: an unblocked swing heals the full 5 (10 -> 15)", combat.player_hp == 15)


func _test_heal_caps_at_max_hp() -> void:
	_clear_all()
	var p = _place_lifestealer(5, 5, 1)
	var e = _place(0, 10, 1, true, combat.ROW_FRONT)
	combat.player_hp = combat.player_max_hp - 2
	await combat._creature_attacks_creature(p, e, 1, false)
	_assert("cap: 5 damage dealt but only 2 HP missing heals to max",
		combat.player_hp == combat.player_max_hp)


func _place_lifestealer(atk: int, hp: int, lane: int):
	var p = _place(atk, hp, lane, false, combat.ROW_FRONT)
	p.card_data["keywords"] = ["lifelink"]
	return p


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
		print("[lifesteal] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[lifesteal] FAIL  %s" % name)


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
