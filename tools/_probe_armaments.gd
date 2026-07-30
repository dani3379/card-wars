extends SceneTree
## Focused correctness probe for the six campaign-only Armaments.
##
## Pins their CardDB/upgrade shapes and drives the live Combat hooks for
## attachment, spell growth, death-rattle repetition, adjacent strikes,
## repeat attacks, stack caps, Last Stand, and copy provenance.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" \
##     --log-file "D:\Godot\_codex_probe_armaments.log" \
##     --script res://tools/_probe_armaments.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
const ARMAMENT_IDS: Array[String] = [
	"hooked_pike", "tower_shield", "grave_bell", "witchbrand",
	"forked_spear", "repeating_arbalest",
]

var RS: Node
var US: Node
var SS: Node
var CDB: Node
var KE: Node
var combat: Node
var _started := false
var _pass := 0
var _fail: Array[String] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[armaments] start")
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	CDB = root.get_node_or_null("CardDB")
	KE = root.get_node_or_null("KeywordEffects")
	if RS == null or CDB == null or KE == null or SS == null:
		print("[armaments] FATAL missing autoload")
		quit(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	SS.combat_mode = SS.CombatMode.SOLO

	_static_checks()

	RS.start_new_run("raider", 0, 68426)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[armaments] FATAL no player turn")
		quit(1)
		return

	_test_attach_stats_keywords_and_limit()
	_test_upgrade_bumps()
	_test_witchbrand()
	_test_grave_bell()
	await _test_forked_spear()
	await _test_repeating_arbalest()
	_test_copy_stripping()

	print("[armaments] ============ SUMMARY ============")
	print("[armaments] passed : %d" % _pass)
	print("[armaments] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[armaments] DONE")
	quit(1 if not _fail.is_empty() else 0)


func _static_checks() -> void:
	var expected := {
		"hooked_pike": {
			"name": "Hooked Pike", "cost": 1, "rarity": "common",
			"desc": "Bearer gets +3 ATK and Piercing.",
			"armament": {"atk": 3, "keywords": ["piercing"], "icon": "piercing"},
			"upgrade": "Bearer gets +4 ATK and Piercing.",
		},
		"tower_shield": {
			"name": "Tower Shield", "cost": 1, "rarity": "common",
			"desc": "Bearer gets +5 HP and Armored.",
			"armament": {"hp": 5, "keywords": ["armored"], "icon": "armored"},
			"upgrade": "Bearer gets +7 HP and Armored.",
		},
		"grave_bell": {
			"name": "Grave Bell", "cost": 1, "rarity": "uncommon",
			"desc": "Bearer’s On-Death effects trigger twice.",
			"armament": {"effect": "double_on_death", "icon": "on_death"},
			"upgrade": "Bearer gets +1/+1. Its On-Death effects trigger twice.",
		},
		"witchbrand": {
			"name": "Witchbrand", "cost": 1, "rarity": "uncommon",
			"desc": "After you cast a spell, bearer gets +1/+1 this fight.",
			"armament": {"effect": "spell_growth", "value": 1, "icon": "on_enter"},
			"upgrade": "Bearer gets +1/+1. After you cast a spell, it gets +1/+1 this fight.",
		},
		"forked_spear": {
			"name": "Forked Spear", "cost": 2, "rarity": "uncommon",
			"desc": "Bearer also strikes adjacent enemies.",
			"armament": {"effect": "adjacent_strikes", "icon": "piercing"},
			"upgrade": "Bearer gets +2 ATK and also strikes adjacent enemies.",
		},
		"repeating_arbalest": {
			"name": "Repeating Arbalest", "cost": 2, "rarity": "rare",
			"desc": "Bearer gains Last Stand and attacks twice.",
			"armament": {"effect": "double_attack", "keywords": ["last_stand"], "icon": "last_stand"},
			"upgrade": "Bearer gets +2 HP, Last Stand, and attacks twice.",
		},
	}
	for id in ARMAMENT_IDS:
		var d: Dictionary = CDB.get_card_data(id)
		var e: Dictionary = expected[id]
		_assert("static: %s exact base data" % id,
			String(d.get("name", "")) == String(e.name)
			and String(d.get("type", "")) == "armament"
			and int(d.get("cost", -1)) == int(e.cost)
			and String(d.get("rarity", "")) == String(e.rarity)
			and String(d.get("desc", "")) == String(e.desc)
			and String(d.get("targeting", "")) == "friendly_creature"
			and d.get("keywords", null) == []
			and d.get("armament", {}) == e.armament)
		var upgrade: Dictionary = CDB.get_plus_upgrade(id)
		_assert("static: %s exact forged text and no cost cut" % id,
			String(upgrade.get("desc", "")) == String(e.upgrade)
			and not upgrade.has("cost") and CDB.is_upgradeable(id))

	var legal: Array = SS.skirmish_legal_pool()
	_assert("static: skirmish pool is alive", not legal.is_empty())
	for id in ARMAMENT_IDS:
		_assert("static: %s remains campaign-only" % id, not legal.has(id))


func _test_attach_stats_keywords_and_limit() -> void:
	_clear_all()
	var pike_bearer = _place(2, 4, 0, false, combat.ROW_FRONT)
	_assert("attach: Hooked Pike equips", combat._apply_armament(
		CDB.get_card_data("hooked_pike"), pike_bearer))
	_assert("attach: Hooked Pike grants +3 ATK and Piercing",
		int(pike_bearer.current_atk) == 5 and pike_bearer.has_keyword("piercing")
		and combat._equipped_armament_id(pike_bearer) == "hooked_pike")
	var atk_before: int = int(pike_bearer.current_atk)
	var hp_before: int = int(pike_bearer.current_hp)
	_assert("attach: a bearer rejects a second Armament",
		not combat._apply_armament(CDB.get_card_data("tower_shield"), pike_bearer)
		and int(pike_bearer.current_atk) == atk_before
		and int(pike_bearer.current_hp) == hp_before)

	var shield_bearer = _place(2, 4, 1, false, combat.ROW_FRONT)
	shield_bearer.current_hp = 2
	_assert("attach: Tower Shield equips a damaged bearer",
		combat._apply_armament(CDB.get_card_data("tower_shield"), shield_bearer))
	_assert("attach: Tower Shield raises max/current HP without full-healing",
		int(shield_bearer.card_data.hp) == 9 and int(shield_bearer.current_hp) == 7
		and shield_bearer.has_keyword("armored"))

	var structure = _place(0, 5, 2, false, combat.ROW_BACK)
	structure.card_data.keywords.append("structure")
	_assert("attach: Structures cannot bear Armaments",
		not combat._can_equip_armament(structure)
		and not combat._apply_armament(CDB.get_card_data("hooked_pike"), structure))


func _test_upgrade_bumps() -> void:
	var expected := {
		"hooked_pike": [4, 0],
		"tower_shield": [0, 7],
		"grave_bell": [1, 1],
		"witchbrand": [1, 1],
		"forked_spear": [2, 0],
		"repeating_arbalest": [0, 2],
	}
	for id in ARMAMENT_IDS:
		_clear_all()
		var bearer = _place(2, 4, 0, false, combat.ROW_FRONT)
		var data: Dictionary = CDB.get_card_data(id)
		data["is_upgraded"] = true
		var ok: bool = combat._apply_armament(data, bearer)
		var bump: Array = expected[id]
		_assert("forge: %s applies its exact live stat bump" % id,
			ok and int(bearer.current_atk) == 2 + int(bump[0])
			and int(bearer.current_hp) == 4 + int(bump[1])
			and int(bearer.card_data.hp) == 4 + int(bump[1]))


func _test_witchbrand() -> void:
	_clear_all()
	var bearer = _place(2, 4, 0, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("witchbrand"), bearer)
	var casts_before: int = int(combat._spells_cast_this_turn)
	combat._record_spell_cast_board_payoffs()
	_assert("Witchbrand: one completed spell grants +1/+1",
		int(bearer.current_atk) == 3 and int(bearer.current_hp) == 5
		and int(bearer.card_data.hp) == 5)
	_assert("Witchbrand: the shared hook records exactly one completed spell",
		int(combat._spells_cast_this_turn) == casts_before + 1)


func _test_grave_bell() -> void:
	_clear_all()
	var bell = _place(1, 3, 1, false, combat.ROW_FRONT)
	bell.card_data["on_death"] = {"type": "damage_face", "value": 1}
	combat._apply_armament(CDB.get_card_data("grave_bell"), bell)
	combat.enemy_hp = combat.enemy_max_hp
	var hp0: int = int(combat.enemy_hp)
	KE.dispatch_on_death(bell, 1, false, combat, combat.ROW_FRONT)
	_assert("Grave Bell: its bearer triggers an On-Death twice",
		int(combat.enemy_hp) == hp0 - 2)

	var warden = _place(0, 6, 0, false, combat.ROW_BACK)
	warden.card_data["passive"] = "double_on_death"
	combat.enemy_hp = combat.enemy_max_hp
	hp0 = int(combat.enemy_hp)
	KE.dispatch_on_death(bell, 1, false, combat, combat.ROW_FRONT)
	_assert("Grave Bell: field-wide doubling caps with the Bell at two",
		int(combat.enemy_hp) == hp0 - 2)

	bell.state.offering_extra_on_death = 1
	combat.enemy_hp = combat.enemy_max_hp
	hp0 = int(combat.enemy_hp)
	KE.dispatch_on_death(bell, 1, false, combat, combat.ROW_FRONT)
	_assert("Grave Bell: Offering stays additive after the two-trigger cap",
		int(combat.enemy_hp) == hp0 - 3)


func _test_forked_spear() -> void:
	_clear_all()
	var bearer = _place(2, 8, 1, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("forked_spear"), bearer)
	var left = _place(0, 7, 0, true, combat.ROW_FRONT)
	var right = _place(0, 7, 2, true, combat.ROW_BACK)
	var far = _place(0, 7, 3, true, combat.ROW_FRONT)
	var face0: int = int(combat.enemy_hp)
	await combat._run_forked_spear_strikes(bearer, 1, false)
	_assert("Forked Spear: strikes occupied left and right adjacent lanes",
		int(left.current_hp) == 5 and int(right.current_hp) == 5)
	_assert("Forked Spear: does not reach a non-adjacent lane",
		int(far.current_hp) == 7)
	_assert("Forked Spear: adjacent strikes never spill to face",
		int(combat.enemy_hp) == face0)

	_clear_all()
	bearer = _place(2, 8, 1, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("forked_spear"), bearer)
	left = _place(0, 7, 0, true, combat.ROW_FRONT)
	face0 = int(combat.enemy_hp)
	await combat._run_forked_spear_strikes(bearer, 1, false)
	_assert("Forked Spear: an empty adjacent lane does not hit face",
		int(left.current_hp) == 5 and int(combat.enemy_hp) == face0)


func _test_repeating_arbalest() -> void:
	_clear_all()
	var bearer = _place(2, 4, 1, false, combat.ROW_FRONT)
	bearer.last_stand_used = true
	combat._apply_armament(CDB.get_card_data("repeating_arbalest"), bearer)
	_assert("Repeating Arbalest: grants a fresh Last Stand",
		bearer.has_keyword("last_stand") and not bearer.last_stand_used)
	bearer.take_damage(99)
	_assert("Repeating Arbalest: granted Last Stand really prevents lethal damage",
		is_instance_valid(bearer) and int(bearer.current_hp) == 1
		and bearer.last_stand_used)

	_clear_all()
	bearer = _place(2, 8, 1, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("repeating_arbalest"), bearer)
	var target = _place(0, 10, 1, true, combat.ROW_FRONT)
	bearer.has_attacked_this_turn = true
	await combat._run_armament_second_strikes(_occupied_front_flags(false),
		_occupied_front_flags(true), 0)
	_assert("Repeating Arbalest: completed bearer makes its second full attack",
		int(target.current_hp) == 8 and bearer.has_attacked_this_turn)

	_clear_all()
	bearer = _place(2, 8, 1, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("repeating_arbalest"), bearer)
	target = _place(0, 10, 1, true, combat.ROW_FRONT)
	bearer.has_attacked_this_turn = true
	combat._doubled_hour[0] = true
	await combat._run_armament_second_strikes(_occupied_front_flags(false),
		_occupied_front_flags(true), 0)
	combat._doubled_hour[0] = false
	_assert("Repeating Arbalest: Doubled Hour caps it at two total attacks",
		int(target.current_hp) == 10)

	_clear_all()
	bearer = _place(2, 8, 1, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("repeating_arbalest"), bearer)
	bearer.card_data["passive"] = "attacks_twice"
	target = _place(0, 10, 1, true, combat.ROW_FRONT)
	bearer.has_attacked_this_turn = true
	await combat._run_armament_second_strikes(_occupied_front_flags(false),
		_occupied_front_flags(true), 0)
	_assert("Repeating Arbalest: native Twinblade caps it at two total attacks",
		int(target.current_hp) == 10)

	_clear_all()
	bearer = _place(2, 8, 1, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("repeating_arbalest"), bearer)
	target = _place(0, 10, 1, true, combat.ROW_FRONT)
	bearer.has_attacked_this_turn = true
	bearer.state.battle_order_second_strike = true
	await combat._run_battle_order_strikes(_occupied_front_flags(false),
		_occupied_front_flags(true), 0)
	_assert("Repeating Arbalest: Rain of Blows cannot add a third attack",
		int(target.current_hp) == 10
		and not bearer.has_meta("battle_order_second_strike"))


func _test_copy_stripping() -> void:
	_clear_all()
	var source = _place(2, 4, 0, false, combat.ROW_FRONT)
	combat._apply_armament(CDB.get_card_data("tower_shield"), source)
	var clean: Dictionary = KE._copy_source_without_armament(source.card_data)
	_assert("copy: source snapshot strips the attached Armament",
		not clean.has("equipped_armament") and int(clean.get("hp", 0)) == 4
		and not clean.get("keywords", []).has("armored"))
	var copy = _place(1, 1, 1, false, combat.ROW_FRONT)
	KE._copy_creature_onto(copy, source.card_data)
	_assert("copy: a full copy inherits the base creature, not its gear",
		not copy.card_data.has("equipped_armament")
		and int(copy.card_data.hp) == 4 and int(copy.current_hp) == 4
		and not copy.has_keyword("armored"))


func _place(atk: int, hp: int, lane: int, is_enemy: bool, row: int):
	var arr: Array = combat._row_array(is_enemy, row)
	if arr[lane] != null and is_instance_valid(arr[lane]):
		arr[lane].queue_free()
		arr[lane] = null
	combat.summon_token(atk, hp, lane, is_enemy, row)
	var placed = combat._row_array(is_enemy, row)[lane]
	# THE MUSTER DELAY (2026-07-21) leaves every freshly arrived body with
	# ready_to_swing = FALSE, and _resolve_column_attack gates on can_attack().
	# _start_round() is what sweeps the board ready in real play; a fixture
	# seated straight onto the board never sees that sweep, so without this the
	# Repeating Arbalest's own second strike silently did nothing (and its three
	# "capped at two attacks" siblings passed for the wrong reason — no strike at
	# all looks exactly like a correctly capped one). Stand in for the sweep.
	if placed != null and is_instance_valid(placed):
		placed.state.ready_to_swing = true
	return placed


func _clear_all() -> void:
	for is_enemy in [true, false]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				if arr[lane] != null and is_instance_valid(arr[lane]):
					arr[lane].queue_free()
				arr[lane] = null


func _occupied_front_flags(is_enemy: bool) -> Array[bool]:
	var flags: Array[bool] = []
	for lane in range(combat.LANES_PER_ROW):
		var c = combat._row_array(is_enemy, combat.ROW_FRONT)[lane]
		flags.append(c != null and is_instance_valid(c) and c.current_hp > 0)
	return flags


func _assert(name: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("[armaments] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[armaments] FAIL  %s" % name)


## Wait for a combat that has actually STARTED.
##
## Phase.PLAYER_TURN is enum 0 and is also `phase`'s declared default, so the
## old `phase == PLAYER_TURN` test was true on the very first poll — before
## _ready had finished its interleaved build. Round number only leaves 0 when
## _start_round() has really run, so it is the honest readiness signal.
func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if int(combat.round_number) >= 1 and combat.phase == combat.Phase.PLAYER_TURN:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false
