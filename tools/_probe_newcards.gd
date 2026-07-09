extends SceneTree
## New-card mechanics probe (2026-07-02 card-pool overhaul). Boots the real combat
## scene headless and unit-drives every NEW design from the boring/terrible-cards
## pass: the 9 replacements (Headhunter, Bulwark Novice, Cinder Acolyte,
## Condottiere, Necromancer, Last Rites, Unclean Blessing/Virulence, The Doubled
## Hour, Rout) and the reworks (Witch, Hydra, Warchief, Paladin, Summoner, Harpy,
## Ember Warden, Carrion Priest, Basilisk, Fuel the Pyre, War Cry, Griffin).
##
## Run: Godot_console.exe --headless --path "D:\Godot" --script res://tools/_probe_newcards.gd

var combat: Node
var CDB: Node = null   # CardDB autoload (not a global identifier under --script)
var KFX: GDScript = null
var _started := false
var _done := false
var _pass := 0
var _fail := 0
var _c2d: GDScript = null


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[newcards]   PASS  %s" % label)
	else:
		_fail += 1
		print("[newcards]   FAIL  %s   %s" % [label, detail])


func _run() -> void:
	print("[newcards] start")
	var RS = root.get_node_or_null("RunState")
	var SS = root.get_node_or_null("SkirmishState")
	var US = root.get_node_or_null("UserSettings")
	if RS == null:
		print("[newcards] FATAL: RunState missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	var NM = root.get_node_or_null("NetMatch")
	if NM != null and NM.has_method("leave"):
		NM.leave()

	RS.start_new_run("raider", 0, 777)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	_c2d = load("res://scripts/Card2D.gd")
	CDB = root.get_node_or_null("CardDB")
	KFX = load("res://scripts/data/KeywordEffects.gd")
	if CDB == null:
		print("[newcards] FATAL: CardDB autoload missing"); _finish(1); return

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	var ok := false
	for _i in 40:
		await create_timer(0.1).timeout
		if not is_instance_valid(combat):
			break
		if combat.phase == combat.Phase.PLAYER_TURN:
			ok = true
			break
	if not ok:
		print("[newcards] FATAL: never reached PLAYER_TURN"); _finish(1); return
	print("[newcards] combat booted")

	await _t_war_cry()
	await _t_last_rites()
	await _t_virulence()
	await _t_rout()
	await _t_doubled_hour()
	await _t_headhunter()
	await _t_witch()
	await _t_necromancer()
	await _t_summoner()
	await _t_paladin()
	await _t_acolyte()
	await _t_warden()
	await _t_basilisk()
	await _t_condottiere()
	await _t_harpy()
	await _t_hydra()
	await _t_bulwark()
	await _t_carrion()
	await _t_glutton()
	await _t_fuel_the_pyre()
	await _t_griffin()
	await _t_warchief()
	await _t_petard()
	await _t_slow_match()
	await _t_muster_fallen()
	await _t_volunteer()
	await _t_trebuchet()
	await _t_rat_piper()

	print("\n[newcards] DONE: %d passed, %d failed" % [_pass, _fail])
	_finish(0 if _fail == 0 else 2)


# в”Ђв”Ђ scenario helpers в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

func _clear() -> void:
	for row in [0, 1]:
		for is_enemy in [false, true]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(arr.size()):
				var c = arr[i]
				if c != null and is_instance_valid(c):
					arr[i] = null
					c.queue_free()
	combat._friendly_deaths_this_fight = 0
	combat._virulence_active = [false, false]
	combat._doubled_hour = [false, false]
	combat.enemy_hp = 60
	combat.player_hp = 20
	combat.player_max_hp = 25


func _seat_data(data: Dictionary, is_enemy: bool, lane: int, row: int = 0):
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", "probe"))
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data
	card.current_lane = lane
	card.current_row = row
	combat._row_array(is_enemy, row)[lane] = card
	var slot = combat._slot_array(is_enemy, row)[lane]
	combat._slot_set_card(slot, card)
	card.current_hp = int(data.get("hp", 1))
	card.current_atk = int(data.get("atk", 0))
	if data.get("keywords", []).has("shield"):
		card.state.has_shield = true
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card


func _seat_id(id: String, is_enemy: bool, lane: int, row: int = 0):
	return _seat_data(CDB.get_card_data(id), is_enemy, lane, row)


func _seat_plain(is_enemy: bool, lane: int, atk: int, hp: int, kws: Array = [], row: int = 0):
	return _seat_data({
		"id": "probe_%s" % ("e" if is_enemy else "p"), "name": "Probe",
		"type": "creature", "cost": 1, "atk": atk, "hp": hp,
		"rarity": "common", "keywords": kws, "desc": "",
	}, is_enemy, lane, row)


func _cast(spell_card_id: String, target) -> void:
	var data: Dictionary = CDB.get_card_data(spell_card_id)
	await combat._resolve_custom_spell(String(data.get("spell", {}).get("id", "")), target, -1, data)


const NONE4: Array[bool] = [false, false, false, false]


# в”Ђв”Ђ tests в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

func _t_war_cry() -> void:
	print("\n[newcards] === War Cry: swift-only rally ===")
	_clear()
	var p = _seat_plain(false, 0, 2, 3)
	await _cast("war_cry", null)
	_ck("grants war_cry_swift meta", p.get_meta("war_cry_swift", false) == true)
	_ck("no base ATK buff (swift-only now)", p.temp_atk_buff == 0, "temp=%d" % p.temp_atk_buff)


func _t_last_rites() -> void:
	print("\n[newcards] === Last Rites: morbid removal 3/6 ===")
	_clear()
	var e = _seat_plain(true, 0, 0, 12)
	await _cast("grave_pact", e)
	_ck("deals 3 with no fallen", e.current_hp == 9, "hp=%d" % e.current_hp)
	combat._friendly_deaths_this_fight = 1
	await _cast("grave_pact", e)
	_ck("deals 6 once a friendly has fallen", e.current_hp == 3, "hp=%d" % e.current_hp)


func _t_virulence() -> void:
	print("\n[newcards] === Virulence: side-wide poison round ===")
	_clear()
	var p = _seat_plain(false, 0, 1, 5)
	var e = _seat_plain(true, 0, 1, 5)
	await _cast("lay_on_hands", null)
	_ck("flag armed", combat._virulence_active[0] == true)
	await combat._resolve_column_attack(0, 0, false, NONE4)
	combat._cleanup_dead()
	_ck("1-ATK strike kills via poison", not is_instance_valid(e) or e.current_hp <= 0)
	_ck("attacker unaffected", is_instance_valid(p) and p.current_hp == 5)


func _t_rout() -> void:
	print("\n[newcards] === Rout: shove all + stun ===")
	_clear()
	var e0 = _seat_plain(true, 0, 2, 3)
	var e1 = _seat_plain(true, 1, 2, 3)
	var eb = _seat_plain(true, 2, 2, 3, [], 1)   # already in back row
	await _cast("overwhelming_force", null)
	_ck("front enemy 0 driven to back", e0.current_row == 1, "row=%d" % e0.current_row)
	_ck("front enemy 1 driven to back", e1.current_row == 1, "row=%d" % e1.current_row)
	_ck("all three stunned", e0.state.stunned and e1.state.stunned and eb.state.stunned)


func _t_doubled_hour() -> void:
	print("\n[newcards] === The Doubled Hour: attack twice ===")
	_clear()
	var p = _seat_plain(false, 0, 2, 9)
	var e = _seat_plain(true, 0, 0, 9)
	await _cast("time_snare", null)
	_ck("flag armed", combat._doubled_hour[0] == true)
	await combat._resolve_column_attack(0, 0, false, NONE4)
	_ck("first strike landed", e.current_hp == 7, "hp=%d" % e.current_hp)
	await combat._run_doubled_hour_swing(NONE4, NONE4)
	_ck("second strike landed", e.current_hp == 5, "hp=%d" % e.current_hp)
	_ck("attacker fine", is_instance_valid(p) and p.current_hp == 9)


func _t_headhunter() -> void:
	print("\n[newcards] === Headhunter: Slay в†’ draw ===")
	_clear()
	var _p = _seat_id("skirmisher", false, 0)
	var _e = _seat_plain(true, 0, 0, 1)
	var hand_before: int = combat._hand.size()
	await combat._resolve_column_attack(0, 0, false, NONE4)
	combat._cleanup_dead()
	_ck("kill drew a card", combat._hand.size() == hand_before + 1,
		"hand %dв†’%d" % [hand_before, combat._hand.size()])


func _t_witch() -> void:
	print("\n[newcards] === Witch: first spell в€’1 ===")
	_clear()
	_seat_id("witch", false, 0)
	var spell = combat.CARD_SCENE.instantiate()
	spell.card_id = "smite_spell"
	spell.card_data = CDB.get_card_data("smite_spell")   # base cost 2
	combat._first_spell_this_turn = false
	var c1: int = combat._effective_cost(spell)
	combat._first_spell_this_turn = true
	var c2: int = combat._effective_cost(spell)
	_ck("first spell discounted", c1 == 1, "cost=%d" % c1)
	_ck("later spells full price", c2 == 2, "cost=%d" % c2)
	spell.free()


func _t_necromancer() -> void:
	print("\n[newcards] === Necromancer: dies into both rows of its lane ===")
	_clear()
	var n = _seat_id("necromancer", false, 1)
	n.take_damage(999)
	await process_frame
	var front = combat._row_array(false, 0)[1]
	var back = combat._row_array(false, 1)[1]
	_ck("token raised in the front row", front != null and is_instance_valid(front) and front.is_token,
		"slot=%s" % str(front))
	_ck("token raised in the back row", back != null and is_instance_valid(back) and back.is_token,
		"slot=%s" % str(back))
	if front != null and is_instance_valid(front):
		_ck("tokens are 2/2", front.current_atk == 2 and front.current_hp == 2,
			"%d/%d" % [front.current_atk, front.current_hp])


func _t_summoner() -> void:
	print("\n[newcards] === Summoner: token each round ===")
	_clear()
	_seat_id("summoner", false, 1)
	combat._apply_start_round_passives(false)
	await process_frame
	var t0 = combat._row_array(false, 0)[0]
	var t2 = combat._row_array(false, 0)[2]
	_ck("token mustered in an adjacent lane", (t0 != null and t0.is_token) or (t2 != null and t2.is_token))


func _t_paladin() -> void:
	print("\n[newcards] === Paladin: Last Stand rally ===")
	_clear()
	combat.player_hp = 15
	var pal = _seat_id("paladin", false, 0)
	combat._apply_play_time_passives(pal, false)   # wires last_stand_fired (the play path does this)
	var ally = _seat_plain(false, 1, 2, 4)
	pal.take_damage(99)
	await process_frame
	_ck("paladin survives at 1", is_instance_valid(pal) and pal.current_hp == 1)
	_ck("allies rallied +2 ATK", ally.current_atk == 4, "atk=%d" % ally.current_atk)
	_ck("hero healed 3", combat.player_hp == 18, "hp=%d" % combat.player_hp)


func _t_acolyte() -> void:
	print("\n[newcards] === Cinder Acolyte: grows on heal ===")
	_clear()
	combat.player_hp = 10
	var a = _seat_id("cinder_acolyte", false, 0)
	combat._heal_owner_hero(false, 2)
	_ck("heal stoked +1 ATK", a.current_atk == 2, "atk=%d" % a.current_atk)
	combat.player_hp = combat.player_max_hp
	combat._heal_owner_hero(false, 2)
	_ck("heal at full HP does nothing", a.current_atk == 2, "atk=%d" % a.current_atk)


func _t_warden() -> void:
	print("\n[newcards] === Ember Warden: grows on effect burn ===")
	_clear()
	var w = _seat_id("ember_warden", false, 0)
	combat.damage_enemy_hero(2)          # effect
	_ck("effect burn stoked +1 ATK", w.current_atk == 2, "atk=%d" % w.current_atk)
	combat.damage_enemy_hero(2, false)   # plain creature strike
	_ck("strike damage does NOT stoke", w.current_atk == 2, "atk=%d" % w.current_atk)


func _t_basilisk() -> void:
	print("\n[newcards] === Basilisk: poisonous thorns ===")
	_clear()
	var b = _seat_id("basilisk", false, 0)
	var e = _seat_plain(true, 0, 2, 6)
	await combat._resolve_column_attack(0, 0, true, NONE4)
	combat._cleanup_dead()
	_ck("striker died to venom thorns", not is_instance_valid(e) or e.current_hp <= 0)
	_ck("basilisk survives the hit", is_instance_valid(b) and b.current_hp == 2, "")


func _t_condottiere() -> void:
	print("\n[newcards] === Condottiere: +1/+1 per unspent Command ===")
	_clear()
	combat.player_mana = 2
	var c = _seat_id("duelist", false, 0)
	combat._apply_play_time_passives(c, false)
	_ck("entered at 4/5 with 2 unspent", c.current_atk == 4 and c.current_hp == 5,
		"%d/%d" % [c.current_atk, c.current_hp])


func _t_harpy() -> void:
	print("\n[newcards] === Harpy: haul + wind the target ===")
	_clear()
	var e = _seat_plain(true, 0, 2, 4, [], 1)   # back row
	var h = _seat_id("harpy", false, 0)
	combat._resolve_on_play_ability(h, 0, false)
	await process_frame
	_ck("back enemy hauled to front", e.current_row == 0, "row=%d" % e.current_row)
	_ck("took 2 on the way", e.current_hp == 2, "hp=%d" % e.current_hp)
	_ck("winded (stunned)", e.state.stunned == true)


func _t_hydra() -> void:
	print("\n[newcards] === Hydra: sweep + Rampage per kill + Armored full counter ===")
	# Two 0-ATK dummies die to the sweep -> Rampage +2. They have no attack, so an
	# Armored Hydra takes NO counter and walks away at full HP.
	_clear()
	var h = _seat_id("hydra", false, 0)
	_ck("Hydra is Armored", h.has_keyword("armored"))
	_seat_plain(true, 1, 0, 1)
	_seat_plain(true, 2, 0, 1)
	await combat._resolve_column_attack(0, 0, false, NONE4)
	combat._cleanup_dead()
	_ck("two kills -> Rampage +2", h.persistent_atk_buff == 2, "buff=%d" % h.persistent_atk_buff)
	_ck("0-ATK defenders deal no counter", h.current_hp == 6, "hp=%d" % h.current_hp)

	# Full counter, softened by Armored: a 3-ATK and a 1-ATK blocker both SURVIVE the
	# sweep (hp 10 > 4 dmg), so each counters for maxi(1, atk-1) = 2 and 1; a 0-ATK
	# blocker adds nothing. Hydra loses 3 total.
	_clear()
	var h2 = _seat_id("hydra", false, 0)
	_seat_plain(true, 1, 3, 10)
	_seat_plain(true, 2, 1, 10)
	_seat_plain(true, 3, 0, 10)
	await combat._resolve_column_attack(0, 0, false, NONE4)
	combat._cleanup_dead()
	_ck("no kills -> no Rampage", h2.persistent_atk_buff == 0, "buff=%d" % h2.persistent_atk_buff)
	_ck("Armored full counter 2+1+0=3", h2.current_hp == 3, "hp=%d" % h2.current_hp)


func _t_bulwark() -> void:
	print("\n[newcards] === Bulwark Novice: shield-break rage ===")
	_clear()
	var b = _seat_id("shieldbearer", false, 0)
	b.take_damage(3)
	_ck("shield ate the hit", b.current_hp == 3, "hp=%d" % b.current_hp)
	_ck("rage +2 ATK on the break", b.current_atk == 4, "atk=%d" % b.current_atk)


func _t_carrion() -> void:
	print("\n[newcards] === Carrion Priest: drain + heal per ally death ===")
	_clear()
	combat.player_hp = 10
	_seat_id("carrion_priest", false, 0)
	var f = _seat_plain(false, 1, 1, 1)
	var ehp: int = combat.enemy_hp
	f.take_damage(999)
	await process_frame
	_ck("enemy face drained 1", combat.enemy_hp == ehp - 1, "ehp=%d" % combat.enemy_hp)
	_ck("hero healed 1", combat.player_hp == 11, "php=%d" % combat.player_hp)


func _t_glutton() -> void:
	print("\n[newcards] === The Glutton: devour = stats + keywords ===")
	_clear()
	var g = _seat_id("the_glutton", false, 1)
	_seat_plain(false, 0, 1, 2, ["thorns"])
	KFX.dispatch_on_enter(g, 1, false, combat)
	await process_frame
	_ck("+2/+2 from the meal", g.current_atk == 4 and g.current_hp == 5,
		"%d/%d" % [g.current_atk, g.current_hp])
	_ck("digested the meal's Thorns", g.has_keyword("thorns"))


func _t_fuel_the_pyre() -> void:
	print("\n[newcards] === Fuel the Pyre: deterministic opposing hit ===")
	_clear()
	var f = _seat_plain(false, 2, 3, 3)
	var e = _seat_plain(true, 2, 0, 5)
	var bystander = _seat_plain(true, 0, 0, 5)
	await _cast("fuel_the_pyre", f)
	combat._cleanup_dead()
	_ck("victim sacrificed", not is_instance_valid(f) or f.current_hp <= 0)
	_ck("opposing enemy took its ATK", e.current_hp == 2, "hp=%d" % e.current_hp)
	_ck("bystander untouched", bystander.current_hp == 5, "hp=%d" % bystander.current_hp)


func _t_griffin() -> void:
	print("\n[newcards] === Griffin: returns to hand once ===")
	_clear()
	var g = _seat_id("griffin", false, 0)
	g.deck_uid = 4242
	var hand_before: int = combat._hand.size()
	g.take_damage(999)
	await process_frame
	_ck("returned to hand on death", combat._hand.size() == hand_before + 1,
		"hand %dв†’%d" % [hand_before, combat._hand.size()])


func _t_warchief() -> void:
	print("\n[newcards] === Warchief: ATK is ALWAYS 2 + others ===")
	_clear()
	var w = _seat_id("warchief", false, 0)
	var a1 = _seat_plain(false, 1, 1, 1)
	_seat_plain(false, 2, 1, 1)
	combat._refresh_adjacency_buffs()
	_ck("2 allies в†’ 4 ATK", w.current_atk == 4, "atk=%d" % w.current_atk)
	a1.take_damage(999)
	await process_frame
	combat._cleanup_dead()
	_ck("ally fell в†’ drops to 3 live", w.current_atk == 3, "atk=%d" % w.current_atk)



# -- 2026-07-07 fun slate ----------------------------------------------------

func _t_petard() -> void:
	print("\n[newcards] === The Petard: 6 to a random creature, any side ===")
	_clear()
	var e = _seat_plain(true, 0, 0, 9)
	await _cast("petard", null)
	_ck("the only creature on the board ate 6", e.current_hp == 3, "hp=%d" % e.current_hp)


func _t_slow_match() -> void:
	print("\n[newcards] === Slow Match: charges while it waits ===")
	_clear()
	var e = _seat_plain(true, 0, 0, 9)
	var data: Dictionary = CDB.get_card_data("slow_match")
	await combat._resolve_custom_spell("slow_match", e, -1, data)
	_ck("cold cast deals base 2", e.current_hp == 7, "hp=%d" % e.current_hp)
	data["fuse"] = 2
	await combat._resolve_custom_spell("slow_match", e, -1, data)
	_ck("fuse 2 deals 4", e.current_hp == 3, "hp=%d" % e.current_hp)


func _t_muster_fallen() -> void:
	print("\n[newcards] === Muster the Fallen: the roll marches ===")
	_clear()
	var RS = root.get_node_or_null("RunState")
	var saved: Array = RS.fallen
	RS.fallen = [{}, {}, {}]
	await _cast("muster_fallen", null)
	await process_frame
	var shades := 0
	for l in range(4):
		var c = combat._row_array(false, 0)[l]
		if c != null and is_instance_valid(c) and c.is_token:
			shades += 1
	_ck("three shades mustered", shades == 3, "shades=%d" % shades)
	RS.fallen = saved


func _t_volunteer() -> void:
	print("\n[newcards] === The Volunteer: discarding is deployment ===")
	_clear()
	var v = combat.CARD_SCENE.instantiate()
	v.card_id = "volunteer"
	v.card_data = CDB.get_card_data("volunteer")
	combat.add_child(v)
	combat._hand.append(v)
	combat.phase = combat.Phase.PLAYER_TURN
	# 2026-07-07 rework: right-click MARKS the card; the end-of-turn flush deploys.
	combat._on_card_dismiss_requested(v)
	combat._flush_marked_discards()
	await process_frame
	var b = combat._row_array(false, 0)[0]
	_ck("a copy mustered front-left", b != null and is_instance_valid(b) and b.is_token,
		"slot=%s" % str(b))
	if b != null and is_instance_valid(b):
		_ck("copy wears its stats", b.current_atk == 2 and b.current_hp == 3,
			"%d/%d" % [b.current_atk, b.current_hp])


func _t_trebuchet() -> void:
	print("\n[newcards] === Trebuchet: back-row volley ===")
	_clear()
	var t = _seat_id("trebuchet", false, 0, 1)
	var ehp: int = combat.enemy_hp
	combat._apply_start_round_passives(false)
	_ck("volleyed 3 from the back row", combat.enemy_hp == ehp - 3, "ehp=%d" % combat.enemy_hp)
	combat._relocate_creature(t, false, 0, 0)
	var ehp2: int = combat.enemy_hp
	combat._apply_start_round_passives(false)
	_ck("silent in the front row", combat.enemy_hp == ehp2, "ehp=%d" % combat.enemy_hp)


func _t_rat_piper() -> void:
	print("\n[newcards] === Rat Piper: a rat in the back row ===")
	_clear()
	var p = _seat_id("rat_piper", false, 2)
	combat._resolve_on_play_ability(p, 2, false)
	await process_frame
	var rat = combat._row_array(false, 1)[2]
	_ck("rat scurried into the back row", rat != null and is_instance_valid(rat) and rat.is_token,
		"slot=%s" % str(rat))
	if rat != null and is_instance_valid(rat):
		_ck("rat is 1/1", rat.current_atk == 1 and rat.current_hp == 1)
