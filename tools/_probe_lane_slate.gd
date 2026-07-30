extends SceneTree
## Focused correctness probe for the 2026-07-16 Slate / Sideways War cards.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_lane_slate.gd

var combat: Node
var CDB: Node
var RS: Node
var SS: Node
var _started := false
var _pass := 0
var _fail: Array[String] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	var settings = root.get_node_or_null("UserSettings")
	if RS == null or CDB == null:
		print("[lane-slate] FATAL: autoloads missing")
		quit(1)
		return
	if settings != null:
		settings.anim_speed = 4.0
		settings.reduce_motion = true
		settings.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	_static_checks()
	RS.start_new_run("raider", 0, 71616)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_turn():
		print("[lane-slate] FATAL: combat did not boot")
		quit(1)
		return

	await _test_changed_lane_dispatch()
	await _test_two_target_orders()
	await _test_flanking_order()
	await _test_death_cards()
	await _test_arrival_cards()
	await _test_delayed_lanes()
	await _test_wagers_and_roll()

	print("[lane-slate] passed=%d failed=%d %s" % [_pass, _fail.size(), str(_fail)])
	quit(1 if not _fail.is_empty() else 0)


func _static_checks() -> void:
	var ids := [
		"sword_on_credit", "crew_mangonel", "pay_wagon", "pallbearers",
		"gallows_writ", "salted_ground", "body_snatcher", "scapegoat",
		"understudy", "mentioned_dispatches", "drill_serjeant", "crossed_orders",
		"wheeling_lancer", "rolling_tower", "flanking_order", "hook_and_chain",
	]
	for id in ids:
		_ck("CardDB contains %s" % id, CDB.CARD_POOL.has(id))
		_ck("UPGRADES contains %s" % id, CDB.UPGRADES.has(id))
		if SS != null:
			_ck("%s is campaign-only until its net port" % id,
				SS.SKIRMISH_DENYLIST.has(id))
	_ck("lane spells use lane targeting",
		CDB.CARD_POOL["gallows_writ"].targeting == "lane"
		and CDB.CARD_POOL["salted_ground"].targeting == "lane")
	_ck("two-click spells declare their contracts",
		CDB.CARD_POOL["mentioned_dispatches"].targeting == "friendly_then_enemy"
		and CDB.CARD_POOL["crossed_orders"].targeting == "two_enemies"
		and CDB.CARD_POOL["flanking_order"].targeting == "friendly_lane")


func _test_changed_lane_dispatch() -> void:
	_clear()
	var lancer = _seat_id("wheeling_lancer", false, 0)
	var lancer_foe = _seat_plain(true, 1, 0, 8)
	var tower = _seat_id("rolling_tower", false, 1, combat.ROW_BACK)
	var tower_foe = _seat_plain(true, 2, 0, 8, [], combat.ROW_BACK)
	await combat._wheel_side_right(false, false)
	_ck("wheel rotates both rows right", lancer.current_lane == 1 and tower.current_lane == 2)
	_ck("Wheeling Lancer struck its new opposing enemy", lancer_foe.current_hp == 6)
	_ck("Rolling Tower dealt 3 in its new lane", tower_foe.current_hp == 5)


func _test_two_target_orders() -> void:
	_clear()
	var striker = _seat_plain(false, 0, 3, 4)
	var victim = _seat_plain(true, 0, 0, 8)
	await combat._resolve_custom_spell("mentioned_dispatches", victim, 0,
		CDB.get_card_data("mentioned_dispatches"), 0, striker)
	_ck("Mentioned in Dispatches orders a real extra strike", victim.current_hp == 5)
	_ck("ordered strike does not spend the normal clash", not striker.has_attacked_this_turn)

	_clear()
	var a = _seat_plain(true, 0, 1, 5, [], combat.ROW_FRONT)
	var b = _seat_plain(true, 3, 1, 5, [], combat.ROW_BACK)
	await combat._resolve_custom_spell("crossed_orders", b, b.current_lane,
		CDB.get_card_data("crossed_orders"), 0, a)
	_ck("Crossed Orders swaps exact row/lane seats",
		a.current_lane == 3 and a.current_row == combat.ROW_BACK
		and b.current_lane == 0 and b.current_row == combat.ROW_FRONT)


func _test_flanking_order() -> void:
	_clear()
	var flanker = _seat_plain(false, 1, 4, 4)
	combat.enemy_hp = 30
	await combat._resolve_custom_spell("flanking_order", null, 2,
		CDB.get_card_data("flanking_order"), 0, flanker)
	_ck("Flanking Order moved exactly one lane", flanker.current_lane == 2)
	_ck("unguarded destination earned a face strike", combat.enemy_hp == 26)
	_ck("flanking strike preserved the normal clash", not flanker.has_attacked_this_turn)


func _test_death_cards() -> void:
	_clear()
	var crew = _seat_id("crew_mangonel", false, 0)
	var corpse = _seat_plain(false, 1, 2, 4)
	var lane_foe = _seat_plain(true, 1, 0, 10)
	combat._row_array(false, combat.ROW_FRONT)[1] = null
	combat._apply_ally_death_passives(false, corpse)
	_ck("Mangonel hurls the dead creature's printed HP", lane_foe.current_hp == 6)
	_ck("Mangonel itself stayed put", crew.current_lane == 0)

	_clear()
	var lead = _seat_plain(false, 2, 5, 3)
	var understudy = _seat_id("understudy", false, 2, combat.ROW_BACK)
	combat._row_array(false, combat.ROW_FRONT)[2] = null
	combat._apply_ally_death_passives(false, lead)
	_ck("Understudy stepped into the fallen front seat",
		understudy.current_row == combat.ROW_FRONT)
	_ck("Understudy inherited the fallen creature's ATK", understudy.current_atk == 6)

	_clear()
	var snatcher = _seat_id("body_snatcher", false, 0)
	var dead_enemy = _seat_plain(true, 0, 4, 6)
	combat._row_array(true, combat.ROW_FRONT)[0] = null
	combat._try_body_snatch(dead_enemy, 0)
	var risen = combat._player_back[0]
	_ck("Body-Snatcher raises the first lane corpse in back",
		risen != null and risen.current_atk == 4 and risen.current_hp == 6)
	_ck("Body-Snatcher spends its once-per-fight trigger",
		snatcher.state.body_snatcher_used)


func _test_arrival_cards() -> void:
	_clear()
	var wounded_a = _seat_plain(false, 0, 1, 5)
	wounded_a.current_hp = 2
	var wounded_b = _seat_plain(false, 1, 1, 4)
	wounded_b.current_hp = 3
	var goat = _seat_id("scapegoat", false, 2)
	combat._absorb_friendly_wounds(goat, false)
	_ck("Scapegoat fully healed the other creatures",
		wounded_a.current_hp == 5 and wounded_b.current_hp == 4)
	_ck("Scapegoat took all four wounds and died",
		combat._player_field[2] == null or goat.current_hp <= 0)

	_clear()
	var hook = _seat_id("hook_and_chain", false, 1)
	var hooked = _seat_plain(true, 0, 1, 5, [], combat.ROW_BACK)
	await combat._drag_adjacent_enemy(hook, false)
	_ck("Hook-and-Chain drags an adjacent enemy into its lane",
		hooked.current_lane == 1 and hooked.current_row == combat.ROW_BACK)


func _test_delayed_lanes() -> void:
	_clear()
	combat.round_number = 4
	await combat._resolve_custom_spell("salted_ground", null, 1,
		CDB.get_card_data("salted_ground"))
	_ck("Salted Ground blocks its lane now", combat._lane_is_salted(1))
	combat._place_enemy_card(CDB.get_card_data("goblin"), 1, combat.ROW_FRONT)
	_ck("an arrival reroutes away from salted ground", combat._enemy_field[1] == null)

	_clear()
	combat.round_number = 7
	_seat_plain(false, 2, 2, 3)
	_seat_plain(true, 2, 2, 3)
	await combat._resolve_custom_spell("gallows_writ", null, 2,
		CDB.get_card_data("gallows_writ"))
	combat.round_number = 8
	combat._resolve_condemned_lanes()
	await create_timer(0.1).timeout
	_ck("The Gallows Writ kills both sides in the lane",
		combat._player_field[2] == null and combat._enemy_field[2] == null)


func _test_wagers_and_roll() -> void:
	_clear()
	RS.gold = 25
	var wagon = _seat_id("pay_wagon", false, 0)
	await combat._load_pay_wagon(wagon)
	_ck("Pay-Wagon loaded its 20-gold cap", RS.gold == 5
		and wagon.state.pay_wagon_gold == 20)
	var paid: int = combat._settle_pay_wagons()
	_ck("surviving Pay-Wagon returned 30", paid == 30 and RS.gold == 35)

	_clear()
	RS.fallen = [{"uid": -1, "id": "goblin", "name": "Goblin the Grim",
		"enc": "Probe Hold", "act": 1, "round": 2}]
	var pall = _seat_id("pallbearers", false, 0)
	await combat._pallbearers_carry(pall)
	var goblin: Dictionary = CDB.get_card_data("goblin")
	_ck("Pallbearers gained the fallen card's printed body",
		pall.current_atk == 1 + int(goblin.atk)
		and pall.current_hp == 2 + int(goblin.hp))
	_ck("Pallbearers removed the carried name from the Roll", RS.fallen.is_empty())

	_clear()
	combat.round_number = 5
	combat.player_mana = 2
	var sword = _seat_id("sword_on_credit", false, 0)
	sword.state.credit_due_round = 5
	await combat._collect_sword_credit()
	_ck("Sword on Credit can be paid", combat.player_mana == 0
		and combat._player_field[0] == sword)
	var defaulted = _seat_id("sword_on_credit", false, 1)
	defaulted.state.credit_due_round = 5
	await combat._collect_sword_credit()
	_ck("an unpaid Sword deserts to the enemy line",
		combat._player_field[1] != defaulted and defaulted.is_opponent)


func _seat_id(id: String, is_enemy: bool, lane: int, row: int = 0):
	return _seat_data(CDB.get_card_data(id), is_enemy, lane, row)


func _seat_plain(is_enemy: bool, lane: int, atk: int, hp: int,
		keywords: Array = [], row: int = 0):
	return _seat_data({"id": "probe_%d_%d" % [lane, row], "name": "Probe",
		"type": "creature", "ctype": "soldier", "cost": 0, "atk": atk, "hp": hp,
		"rarity": "enemy", "keywords": keywords, "desc": "Probe."}, is_enemy, lane, row)


func _seat_data(data: Dictionary, is_enemy: bool, lane: int, row: int):
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", "probe"))
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.compact_mode = true
	card.card_data = data.duplicate(true)
	card.current_lane = lane
	card.current_row = row
	card.current_atk = int(data.get("atk", 0))
	card.current_hp = int(data.get("hp", 1))
	combat._row_array(is_enemy, row)[lane] = card
	combat._slot_set_card(combat._slot_array(is_enemy, row)[lane], card)
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card


func _clear() -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				if arr[lane] != null and is_instance_valid(arr[lane]):
					arr[lane].queue_free()
				arr[lane] = null
	combat._salted_lanes.clear()
	combat._condemned_lanes.clear()
	combat.enemy_hp = 60
	combat.player_hp = 20


func _wait_for_turn() -> bool:
	for _i in 80:
		if is_instance_valid(combat) and combat.phase == combat.Phase.PLAYER_TURN \
				and combat._hand.size() >= 4:
			return true
		await create_timer(0.1).timeout
	return false


func _ck(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("[lane-slate] PASS  %s" % label)
	else:
		_fail.append(label)
		print("[lane-slate] FAIL  %s" % label)
