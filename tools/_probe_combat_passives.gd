extends SceneTree
## Verifies the 2026-07-13 "make soft combats interesting" fight passives actually
## FIRE (not just parse): drives each dispatch directly with the passive set.
##   bandit_reinforce  — start-of-round summon (R2+): enemy count grows
##   spore_regrowth    — end-of-round: a damaged enemy heals 1
##   sentinel_stone    — every enemy reads as Armored (keyword grant)
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_combat_passives.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
var RS: Node
var US: Node
var SS: Node
var CDB: Node
var EE: Object
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
	print("[passives] start")
	RS = root.get_node_or_null("RunState"); US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState"); CDB = root.get_node_or_null("CardDB")
	if RS == null or CDB == null:
		print("[passives] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0; US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	EE = load("res://scripts/data/EncounterEffects.gd")
	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		print("[passives] FATAL no player turn"); quit(1); return

	_test_sentinel_stone()
	await _test_spore_regrowth()
	await _test_bandit_reinforce()

	print("[passives] ============ SUMMARY ============")
	print("[passives] passed : %d" % _pass)
	print("[passives] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[passives] %s" % ("ALL PASS" if _fail.is_empty() else "FAILED"))
	quit(1 if _fail.size() > 0 else 0)


func _test_sentinel_stone() -> void:
	_clear()
	combat._encounter_passive = "sentinel_stone"
	var e = _place_enemy(2, 4, 0, combat.ROW_FRONT)   # placed via _place_enemy_card → injects armored
	_assert("sentinel_stone: a placed enemy gains the Armored keyword",
		e.has_keyword("armored"))
	# Behavioural: a 3-damage hit lands as 2 on the stone (Armored −1).
	var hp0: int = e.current_hp
	e.take_damage(3)
	_assert("sentinel_stone: Armored soaks 1 (3 dmg → 2 lost)",
		e.current_hp == hp0 - 2)
	# Escalation: from round 2 the front rank digs in (+1 ATK permanent).
	var atk0: int = e.current_atk
	combat.round_number = 2
	EE.dispatch_passive_start_of_round(combat)
	await _idle()
	_assert("sentinel_stone: front rank digs in +1 ATK at round 2",
		e.current_atk == atk0 + 1)
	combat._encounter_passive = ""


func _test_spore_regrowth() -> void:
	_clear()
	combat._encounter_passive = "spore_regrowth"
	var e = _place_enemy(2, 5, 1, combat.ROW_FRONT)
	e.current_hp = 2                      # wounded (max 5)
	e.update_stat_display()
	var healthy = _place_enemy(2, 3, 2, combat.ROW_FRONT)   # at full — must NOT overheal
	var face0: int = combat.player_hp
	EE.dispatch_passive_end_of_round(combat)
	await _idle()
	_assert("spore_regrowth: the wounded enemy healed 2 (2→4)", e.current_hp == 4)
	_assert("spore_regrowth: the full-HP enemy did not overheal", healthy.current_hp == 3)
	_assert("spore_regrowth: the choke dealt 2 face damage while enemies live",
		combat.player_hp == face0 - 2)
	combat._encounter_passive = ""


func _test_bandit_reinforce() -> void:
	_clear()
	combat._encounter_passive = "bandit_reinforce"
	# Round 1: no reinforcement yet (setup round).
	combat.round_number = 1
	var before1: int = combat._all_enemy_creatures().size()
	EE.dispatch_passive_start_of_round(combat)
	await _idle()
	_assert("bandit_reinforce: round 1 sends nobody",
		combat._all_enemy_creatures().size() == before1)
	# Round 2: a fresh Swift raider joins.
	combat.round_number = 2
	var before2: int = combat._all_enemy_creatures().size()
	EE.dispatch_passive_start_of_round(combat)
	await _idle()
	var after2: int = combat._all_enemy_creatures().size()
	_assert("bandit_reinforce: round 2 summons a raider (%d→%d)" % [before2, after2],
		after2 == before2 + 1)
	# And it's Swift.
	var newest: Control = null
	for c in combat._all_enemy_creatures():
		newest = c
	_assert("bandit_reinforce: the raider is Swift",
		newest != null and newest.has_keyword("swift"))
	combat._encounter_passive = ""


# ── helpers ──────────────────────────────────────────────────────────────
func _place_enemy(atk: int, hp: int, lane: int, row: int) -> Control:
	var data := {"id": "e_test", "name": "Stone", "type": "creature", "cost": 1,
		"atk": atk, "hp": hp, "rarity": "enemy", "keywords": []}
	combat._place_enemy_card(data.duplicate(true), lane, row)
	return combat._row_array(true, row)[lane]


func _clear() -> void:
	for is_enemy in [true, false]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(arr.size()):
				var c = arr[i]
				if c != null and is_instance_valid(c):
					c.queue_free()
					arr[i] = null


func _idle() -> void:
	await create_timer(0.05).timeout


func _assert(name: String, cond: bool) -> void:
	if cond: _pass += 1
	else:
		_fail.append(name)
		print("[passives]   FAIL  %s" % name)


func _wait_turn() -> bool:
	var w := 0
	while w < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		w += 1
	return false
