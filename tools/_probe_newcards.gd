extends SceneTree
## New-card mechanics probe (2026-07-02 card-pool overhaul). Boots the real combat
## scene headless and unit-drives every NEW design from the boring/terrible-cards
## pass: the 9 replacements (Headhunter, Bulwark Novice, Cinder Acolyte,
## Condottiere, Necromancer, Last Rites, Unclean Blessing/Virulence, The Doubled
## Hour, Rout) and the reworks (Witch, Hydra, Warchief, Paladin, Summoner, Harpy,
## Ember Warden, Carrion Priest, Basilisk, Fuel the Pyre, War Cry, Griffin).
## The 2026-07-14 replacement pass is covered here too: Mourner, Countermarch,
## Rain of Blows, Offering, Frenzy, Salvage, The Black Contract, and Leyline Conduit.
##
## 2026-07-28 repair: three cards had been reworked out from under their tests.
## Mourner banks Command instead of drawing, and Cinder Acolyte / Ember Warden
## traded grows_on_heal / grows_on_burn for spark_on_spell / shield_on_spell in
## the 2026-07-15 interest slate. Those sections now assert the LIVE contracts
## (and the retired triggers' silence). Same pass: the muster delay was blinding
## every strike scenario — see _seat_data.
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
var _probe_draw_uid := -910000


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
	# Phase.PLAYER_TURN is enum 0 AND `phase`'s declared default, so waiting on
	# the phase alone returns on the first poll — against a combat whose
	# interleaved _ready has not finished building. round_number only leaves 0
	# once _start_round() has really run, so gate on that.
	var ok := false
	for _i in 40:
		await create_timer(0.1).timeout
		if not is_instance_valid(combat):
			break
		if int(combat.round_number) >= 1 and combat.phase == combat.Phase.PLAYER_TURN:
			ok = true
			break
	if not ok:
		print("[newcards] FATAL: never reached a started PLAYER_TURN"); _finish(1); return
	# The opening deal is STAGGERED (_start_round fires draw_one on 0.08s timers
	# so the hand fans in one card at a time), so round_number hits 1 while cards
	# are still arriving. Every hand-size assertion below would otherwise race
	# the deal: a scenario could "draw a card" simply by standing still. Wait for
	# two consecutive polls with an unchanged, non-empty hand.
	var settled := -1
	for _i in 20:
		var now: int = combat._hand.size()
		if now > 0 and now == settled:
			break
		settled = now
		await create_timer(0.1).timeout
	print("[newcards] combat booted (hand settled at %d)" % combat._hand.size())

	await _t_war_cry()
	await _t_last_rites()
	await _t_mass_grave()
	await _t_mourner()
	await _t_countermarch()
	await _t_rain_of_blows()
	await _t_offering()
	await _t_frenzy()
	await _t_salvage()
	await _t_black_contract()
	await _t_leyline()
	await _t_virulence()
	await _t_rout()
	await _t_doubled_hour()
	await _t_headhunter()
	await _t_witch()
	await _t_targeted_refund()
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
	await _t_hex()
	await _t_random_spell_autotarget()
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
	combat._black_contract_active = false
	combat._black_contract_last_round = -1
	combat._black_contract_token_size = 2
	combat._spells_cast_this_turn = 0
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
	# THE MUSTER DELAY (2026-07-21) defaults ready_to_swing to FALSE on every new
	# body, and Card2D.can_attack() gates every strike path on it. _start_round()
	# is what sweeps the board ready in real play; a fixture seated straight onto
	# the board never sees that sweep, so without this line every strike-based
	# scenario below (Rain of Blows, Virulence, The Doubled Hour, Basilisk,
	# Hydra) failed for one reason that had nothing to do with the card it tests.
	# Same repair as tools/_probe_combat_telegraph.gd.
	card.state.ready_to_swing = true
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


## Free at least `n` slots in the hand. A full hand legitimately refuses new
## cards, so any scenario whose assertion is "a card arrived in hand" has to
## guarantee the room first or it measures the hand cap instead of the card.
func _make_hand_room(n: int) -> void:
	while combat._hand.size() > combat.MAX_HAND_SIZE - n:
		var trimmed = combat._hand.pop_back()
		if trimmed != null and is_instance_valid(trimmed):
			if trimmed.get_parent() != null:
				trimmed.get_parent().remove_child(trimmed)
			trimmed.queue_free()


func _seed_local_draws(n: int, card_id: String = "spark") -> void:
	# Draw assertions must not depend on however many cards the booted fight dealt.
	# Trim only when necessary, then put known synthetic entries on top of the pile.
	_make_hand_room(n)
	for _i in n:
		combat._player_draw_pile.push_front(combat._pile_entry(card_id, _probe_draw_uid))
		_probe_draw_uid -= 1


func _loose_spell(card_id: String):
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = card_id
	card.card_data = CDB.get_card_data(card_id)
	card.deck_uid = _probe_draw_uid
	_probe_draw_uid -= 1
	combat.add_child(card)
	return card


func _named_token_count(token_name: String) -> int:
	var total := 0
	for c in combat._all_player_creatures():
		if is_instance_valid(c) and c.is_token \
				and String(c.card_data.get("name", "")) == token_name:
			total += 1
	return total


const NONE4: Array[bool] = [false, false, false, false]


# в”Ђв”Ђ tests в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ

func _t_war_cry() -> void:
	print("\n[newcards] === War Cry: swift-only rally ===")
	_clear()
	var p = _seat_plain(false, 0, 2, 3)
	await _cast("war_cry", null)
	_ck("grants typed war_cry_swift state", p.state.war_cry_swift)
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


func _t_mass_grave() -> void:
	print("\n[newcards] === Mass Grave: 1 to all enemies per fallen friendly ===")
	_clear()
	var front = _seat_plain(true, 0, 0, 6)
	var back = _seat_plain(true, 2, 0, 4, [], 1)
	combat._friendly_deaths_this_fight = 3
	await _cast("mass_grave", null)
	_ck("front foe took the fallen count (3)", is_instance_valid(front) and front.current_hp == 3,
		"hp=%d" % (front.current_hp if is_instance_valid(front) else -99))
	_ck("back foe took the fallen count (3)", is_instance_valid(back) and back.current_hp == 1,
		"hp=%d" % (back.current_hp if is_instance_valid(back) else -99))


func _t_mourner() -> void:
	# The funeral dues. Mourner briefly drew a card on death; the live card banks
	# Command for NEXT turn (on_death type bonus_mana_next_turn), which is what
	# both its printed text and _probe_interest_slate assert. This section tested
	# the retired draw and had been failing for that reason alone.
	print("\n[newcards] === Mourner: On-Death banks Command for next turn ===")
	_clear()
	var hand_before: int = combat._hand.size()
	var mana_before: int = combat.player_mana
	var banked_before: int = combat._bonus_mana_next_turn
	var mourner = _seat_id("mourner", false, 0)
	mourner.take_damage(999)
	await process_frame
	_ck("death banked exactly 1 Command for next turn",
		combat._bonus_mana_next_turn == banked_before + 1,
		"banked %d->%d" % [banked_before, combat._bonus_mana_next_turn])
	_ck("death paid nothing into THIS turn's pool", combat.player_mana == mana_before,
		"mana %d->%d" % [mana_before, combat.player_mana])
	_ck("death drew no card", combat._hand.size() == hand_before,
		"hand %d->%d" % [hand_before, combat._hand.size()])


func _t_countermarch() -> void:
	print("\n[newcards] === Countermarch: change rows, then Shield ===")
	_clear()
	var ordered = _seat_plain(false, 1, 2, 4)
	await _cast("adrenaline", ordered)
	_ck("base order moved front to back", ordered.current_row == combat.ROW_BACK,
		"row=%d" % ordered.current_row)
	_ck("base order Shielded its target", ordered.state.has_shield)

	_clear()
	var left = _seat_plain(false, 0, 1, 3, [], combat.ROW_BACK)
	var forged_target = _seat_plain(false, 1, 2, 4)
	var right = _seat_plain(false, 2, 1, 3, [], combat.ROW_BACK)
	var bystander = _seat_plain(false, 3, 1, 3)
	var RS = root.get_node_or_null("RunState")
	var forged: Dictionary = RS.preview_plus_upgrade(CDB.get_card_data("adrenaline"))
	await combat._resolve_custom_spell("baggage_train", forged_target, -1, forged)
	_ck("forged order moved its target", forged_target.current_row == combat.ROW_BACK)
	_ck("forged order Shielded target and row-neighbours",
		forged_target.state.has_shield and left.state.has_shield and right.state.has_shield)
	_ck("forged order did not Shield a non-adjacent body", not bystander.state.has_shield)


func _t_rain_of_blows() -> void:
	print("\n[newcards] === Rain of Blows: arm exactly one extra strike ===")
	_clear()
	var ordered = _seat_plain(false, 0, 2, 5)
	var defender = _seat_plain(true, 0, 0, 10)
	await _cast("smite_spell", ordered)
	_ck("target carries the second-strike arm",
		ordered.state.battle_order_second_strike)
	await combat._resolve_column_attack(0, combat.ROW_FRONT, false, NONE4)
	_ck("target made its ordinary strike first", defender.current_hp == 8,
		"hp=%d" % defender.current_hp)
	await combat._run_battle_order_strikes(NONE4, NONE4)
	_ck("Rain of Blows made exactly one additional strike", defender.current_hp == 6,
		"hp=%d" % defender.current_hp)
	_ck("second-strike arm was consumed",
		not ordered.state.battle_order_second_strike)


func _t_offering() -> void:
	print("\n[newcards] === Offering: one extra repeatable On-Death; forged draw ===")
	_clear()
	var mourner = _seat_id("mourner", false, 0)
	# Mourner's repeatable On-Death now banks Command for next turn rather than
	# drawing; the thing under test is still "Offering adds exactly one extra
	# copy of a repeatable On-Death", read off the bank instead of the hand.
	var banked_before: int = combat._bonus_mana_next_turn
	var mana_before: int = combat.player_mana
	# Sacrifice is a death condition: neither one-hit survival gate may turn
	# Offering into a free trigger while leaving its target alive.
	mourner.state.has_shield = true
	mourner.card_data["keywords"].append("last_stand")
	await _cast("offering", mourner)
	await process_frame
	_ck("Offering sacrificed its target", not is_instance_valid(mourner) or mourner.current_hp <= 0)
	_ck("Mourner's repeatable On-Death fired twice",
		combat._bonus_mana_next_turn == banked_before + 2,
		"banked %d->%d" % [banked_before, combat._bonus_mana_next_turn])
	_ck("Offering no longer grants Command", combat.player_mana == mana_before,
		"mana %d->%d" % [mana_before, combat.player_mana])

	_clear()
	_seed_local_draws(1)
	var plain = _seat_plain(false, 0, 1, 2)
	var RS = root.get_node_or_null("RunState")
	var forged: Dictionary = RS.preview_plus_upgrade(CDB.get_card_data("offering"))
	var forged_hand_before: int = combat._hand.size()
	await combat._resolve_custom_spell("offering", plain, -1, forged)
	await process_frame
	_ck("Offering+ drew its authored extra card", combat._hand.size() == forged_hand_before + 1,
		"hand %d->%d" % [forged_hand_before, combat._hand.size()])


func _t_frenzy() -> void:
	print("\n[newcards] === Frenzy: round ATK, arm Doom, then detonate ===")
	_clear()
	var fuse = _seat_plain(false, 0, 2, 4)
	await _cast("turbo", fuse)
	_ck("first cast granted +3 ATK this round", fuse.temp_atk_buff == 3,
		"temp=%d" % fuse.temp_atk_buff)
	_ck("first cast armed Doom 2", fuse.has_keyword("doom") and fuse.doom_counter == 2,
		"doom=%d" % fuse.doom_counter)
	var expected_blast: int = fuse.effective_atk() + 3
	var face_before: int = combat.enemy_hp
	fuse.state.has_shield = true
	fuse.card_data["keywords"].append("last_stand")
	await _cast("turbo", fuse)
	await process_frame
	_ck("second cast detonated the existing Doom", not is_instance_valid(fuse) or fuse.current_hp <= 0)
	_ck("detonation used the twice-buffed effective ATK",
		combat.enemy_hp == face_before - expected_blast,
		"expected=%d face %d->%d" % [expected_blast, face_before, combat.enemy_hp])


func _t_salvage() -> void:
	print("\n[newcards] === Salvage: cost-based draw contract ===")
	var data: Dictionary = CDB.get_card_data("recycle")
	var RS = root.get_node_or_null("RunState")
	var forged: Dictionary = RS.preview_plus_upgrade(data)
	_ck("base Salvage exhausts and names cost-based draw",
		int(data.get("cost", -1)) == 1 and data.get("keywords", []).has("exhaust") \
		and String(data.get("desc", "")).contains("Draw cards equal to its cost"))
	_ck("Salvage+ carries the one-card draw rider", int(forged.get("extra_draw", 0)) == 1)


func _t_black_contract() -> void:
	print("\n[newcards] === The Black Contract: debt + bounded non-token death engine ===")
	_clear()
	var RS = root.get_node_or_null("RunState")
	var deck_before: int = RS.deck.size()
	var debts_before: int = RS.deck.count("war_debt")
	await _cast("unholy_bargain", null)
	_ck("cast added exactly one War-Debt",
		RS.deck.size() == deck_before + 1 and RS.deck.count("war_debt") == debts_before + 1)
	_ck("cast armed a 2/2 Contract", combat._black_contract_active \
		and combat._black_contract_token_size == 2)
	_seed_local_draws(2)
	var repeat_hand_before: int = combat._hand.size()
	var repeat_deck_before: int = RS.deck.size()
	await _cast("unholy_bargain", null)
	_ck("a further Contract drew 2 instead of adding another debt",
		combat._hand.size() == repeat_hand_before + 2 \
		and RS.deck.size() == repeat_deck_before \
		and RS.deck.count("war_debt") == debts_before + 1,
		"hand %d->%d deck %d->%d debts=%d" % [repeat_hand_before,
			combat._hand.size(), repeat_deck_before, RS.deck.size(), RS.deck.count("war_debt")])

	var disposable_token = _seat_plain(false, 0, 1, 1)
	disposable_token.is_token = true
	disposable_token.card_data["is_token"] = true
	disposable_token.take_damage(999)
	await process_frame
	_ck("a token death did not muster a Debtor", _named_token_count("Debtor") == 0 \
		and combat._black_contract_last_round == -1)

	var casualty = _seat_plain(false, 1, 1, 1)
	casualty.take_damage(999)
	await process_frame
	var debtor = null
	for c in combat._all_player_creatures():
		if is_instance_valid(c) and c.is_token \
				and String(c.card_data.get("name", "")) == "Debtor":
			debtor = c
			break
	_ck("first real death mustered one Debtor", _named_token_count("Debtor") == 1)
	_ck("Debtor is the promised 2/2 token", debtor != null \
		and debtor.current_atk == 2 and debtor.current_hp == 2)
	var second_casualty = _seat_plain(false, 2, 1, 1)
	second_casualty.take_damage(999)
	await process_frame
	_ck("a second real death in the round did not loop", _named_token_count("Debtor") == 1)

	# The contract mutates the campaign deck by design; restore the probe run so
	# later scenarios still exercise the original boot deck.
	if RS.deck.size() > deck_before:
		RS.remove_card_at(RS.deck.size() - 1)


func _t_leyline() -> void:
	print("\n[newcards] === Leyline Conduit: first-spell column Shield ===")
	_clear()
	var conduit = _seat_id("leyline_conduit", false, 1)
	var mate = _seat_plain(false, 1, 2, 4, [], combat.ROW_BACK)
	var bystander = _seat_plain(false, 3, 2, 4)
	combat._spells_cast_this_turn = 0
	combat._after_spell(_loose_spell("spark"))
	await process_frame
	_ck("first spell Shielded the conduit and column-mate",
		conduit.state.has_shield and mate.state.has_shield)
	_ck("first spell did not Shield an unrelated body", not bystander.state.has_shield)
	conduit.state.has_shield = false
	mate.state.has_shield = false
	combat._after_spell(_loose_spell("spark"))
	await process_frame
	_ck("second spell did not retrigger Leyline",
		not conduit.state.has_shield and not mate.state.has_shield \
		and combat._spells_cast_this_turn == 2)

	_clear()
	conduit = _seat_id("leyline_conduit", false, 1)
	mate = _seat_plain(false, 1, 2, 4, [], combat.ROW_BACK)
	var hexblade = _seat_id("hexblade", false, 0)
	var emberwright = _seat_id("emberwright", false, 3)
	var face_before: int = combat.enemy_hp
	combat._after_generated_spell()
	_ck("a generated spell fed Leyline and the spell-board engines",
		conduit.state.has_shield and mate.state.has_shield \
		and hexblade.temp_atk_buff == 1 and combat.enemy_hp == face_before - 2 \
		and combat._spells_cast_this_turn == 1,
		"hex=%d face %d->%d count=%d" % [hexblade.temp_atk_buff,
			face_before, combat.enemy_hp, combat._spells_cast_this_turn])


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
	print("\n[newcards] === Headhunter: Slay -> heal ===")
	_clear()
	combat.player_hp = 10
	var _p = _seat_id("skirmisher", false, 0)
	var _e = _seat_plain(true, 0, 0, 1)
	await combat._resolve_column_attack(0, 0, false, NONE4)
	combat._cleanup_dead()
	_ck("kill healed the hero 2", combat.player_hp == 12,
		"hp=%d" % combat.player_hp)


func _t_witch() -> void:
	print("\n[newcards] === Witch: first spell в€’1 ===")
	_clear()
	_seat_id("witch", false, 0)
	var spell = combat.CARD_SCENE.instantiate()
	spell.card_id = "smite_spell"
	spell.card_data = CDB.get_card_data("smite_spell")   # Rain of Blows, base cost 2
	combat._first_spell_this_turn = false
	var c1: int = combat._effective_cost(spell)
	combat._first_spell_this_turn = true
	var c2: int = combat._effective_cost(spell)
	_ck("first spell discounted", c1 == 1, "cost=%d" % c1)
	_ck("later spells full price", c2 == 2, "cost=%d" % c2)
	spell.free()


func _t_targeted_refund() -> void:
	print("\n[newcards] === Targeted spell cancel: refund the amount actually paid ===")
	_clear()
	var spell = combat.CARD_SCENE.instantiate()
	spell.card_id = "smite_spell"
	spell.card_data = CDB.get_card_data("smite_spell")
	spell.deck_uid = _probe_draw_uid
	_probe_draw_uid -= 1
	combat._hand_container.add_child(spell)
	combat._hand.append(spell)
	combat.player_mana = 3
	combat._play_spell(spell, 1) # printed 2, discounted to 1
	_ck("discounted targeted spell paid exactly 1", combat.player_mana == 2)
	combat._cancel_targeting()
	_ck("cancel refunded exactly 1, not the printed 2",
		combat.player_mana == 3 and combat._hand.has(spell) \
		and not combat._first_spell_this_turn,
		"mana=%d in_hand=%s first=%s" % [combat.player_mana,
			str(combat._hand.has(spell)), str(combat._first_spell_this_turn)])


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
	# 2026-07-15 interest slate: the old grows_on_heal stoke was replaced by
	# spark_on_spell (Combat._record_spell_cast_board_payoffs), so the retired
	# hero-heal contract this section used to assert can never pass again. The
	# card's live promise is positional: her lane chooses the victim.
	print("\n[newcards] === Cinder Acolyte: every cast sparks the body across ===")
	_clear()
	_seat_id("cinder_acolyte", false, 0)
	var across = _seat_plain(true, 0, 0, 5)
	var unopposed = _seat_plain(true, 2, 0, 5)
	combat.player_hp = 10
	combat._heal_owner_hero(false, 2)
	_ck("a hero heal no longer stokes her (retired grows_on_heal)",
		across.current_hp == 5, "hp=%d" % across.current_hp)
	combat._after_spell(_loose_spell("spark"))
	await process_frame
	_ck("the cast sparked 1 into the enemy she faces", across.current_hp == 4,
		"hp=%d" % across.current_hp)
	_ck("the cast spared a lane she does not face", unopposed.current_hp == 5,
		"hp=%d" % unopposed.current_hp)

	# Positional cost: standing across from nothing sparks nothing (and must not
	# spill onto the face or another lane).
	_clear()
	_seat_id("cinder_acolyte", false, 1)
	var offside = _seat_plain(true, 3, 0, 5)
	var face_before: int = combat.enemy_hp
	combat._after_spell(_loose_spell("spark"))
	await process_frame
	_ck("an empty opposing lane sparks nothing at all",
		offside.current_hp == 5 and combat.enemy_hp == face_before,
		"hp=%d face %d->%d" % [offside.current_hp, face_before, combat.enemy_hp])


func _t_warden() -> void:
	# 2026-07-15 interest slate: grows_on_burn was replaced by shield_on_spell,
	# so the retired face-burn stoke this section used to assert is unreachable.
	print("\n[newcards] === Ember Warden: every cast wraps her in Shield ===")
	_clear()
	var w = _seat_id("ember_warden", false, 0)
	var ally = _seat_plain(false, 2, 1, 3)
	combat.damage_enemy_hero(2)          # effect burn — the retired trigger
	_ck("effect burn no longer stokes her (retired grows_on_burn)",
		not w.state.has_shield and w.temp_atk_buff == 0,
		"shield=%s temp=%d" % [str(w.state.has_shield), w.temp_atk_buff])
	combat._after_spell(_loose_spell("spark"))
	await process_frame
	_ck("the cast wrapped the warden in Shield", w.state.has_shield)
	_ck("the cast did not shield an unrelated body", not ally.state.has_shield)
	# Shield is binary: a repeat cast while shielded must not bank a second one.
	w.state.has_shield = false
	combat._after_spell(_loose_spell("spark"))
	await process_frame
	_ck("a later cast re-shields her once the first Shield is spent",
		w.state.has_shield)


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
	print("\n[newcards] === Harpy: clean back-to-front haul ===")
	_clear()
	var e = _seat_plain(true, 0, 2, 4, [], 1)   # back row
	var h = _seat_id("harpy", false, 0)
	combat._resolve_on_play_ability(h, 0, false)
	await process_frame
	_ck("back enemy hauled to front", e.current_row == 0, "row=%d" % e.current_row)
	_ck("haul dealt no hidden damage", e.current_hp == 4, "hp=%d" % e.current_hp)
	_ck("haul added no hidden stun", not e.state.stunned)


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


func _t_hex() -> void:
	print("\n[newcards] === Hex: strip keywords before damage ===")
	_clear()
	var ward = _seat_plain(true, 0, 0, 5, ["armored", "shield"])
	await _cast("hex", ward)
	var ward_detail := "gone"
	if is_instance_valid(ward):
		ward_detail = "hp=%d shield=%s kws=%s" % [ward.current_hp,
			str(ward.state.has_shield), str(ward.card_data.get("keywords", []))]
	_ck("shield/armored stripped before hit", is_instance_valid(ward) and ward.current_hp == 1,
		ward_detail)
	_ck("no shield or keywords remain", is_instance_valid(ward) and not ward.state.has_shield and ward.card_data.get("keywords", []).is_empty())
	var oath = _seat_plain(true, 1, 0, 4, ["last_stand"])
	await _cast("hex", oath)
	_ck("last stand stripped before lethal hit", not is_instance_valid(oath) or oath.current_hp <= 0,
		"hp=%d" % (oath.current_hp if is_instance_valid(oath) else -99))


func _t_random_spell_autotarget() -> void:
	print("\n[newcards] === Random spell casts: skip fizzles, find legal targets ===")
	_clear()
	var hex_data: Dictionary = CDB.get_card_data("hex")
	var ctx: Dictionary = combat._random_spell_context_for(hex_data)
	_ck("enemy-target spell is skipped when no enemy exists", not bool(ctx.get("ok", false)))
	var enemy = _seat_plain(true, 0, 0, 5)
	ctx = combat._random_spell_context_for(hex_data)
	_ck("enemy-target spell finds an enemy", bool(ctx.get("ok", false)) and ctx.get("target", null) == enemy)

	_clear()
	var charge_data: Dictionary = CDB.get_card_data("charge_spell")
	ctx = combat._random_spell_context_for(charge_data)
	_ck("friendly-target spell is skipped when no friendly exists", not bool(ctx.get("ok", false)))
	var friend = _seat_plain(false, 1, 2, 3)
	ctx = combat._random_spell_context_for(charge_data)
	_ck("friendly-target spell finds a friendly", bool(ctx.get("ok", false)) and ctx.get("target", null) == friend)

	_clear()
	var quick_data: Dictionary = CDB.get_card_data("quick_shot")
	ctx = combat._random_spell_context_for(quick_data)
	_ck("any-target spell can fall back to face", bool(ctx.get("ok", false)) and ctx.get("target", null) == null)

	_clear()
	var mass_data: Dictionary = CDB.get_card_data("mass_grave")
	combat._friendly_deaths_this_fight = 1
	ctx = combat._random_spell_context_for(mass_data)
	_ck("untargeted enemy-board spell skips empty enemy board", not bool(ctx.get("ok", false)))
	_seat_plain(true, 2, 1, 4)
	ctx = combat._random_spell_context_for(mass_data)
	_ck("untargeted enemy-board spell enters pool with enemies", bool(ctx.get("ok", false)))
	combat._friendly_deaths_this_fight = 0
	ctx = combat._random_spell_context_for(mass_data)
	_ck("mass grave stays out of the pool with no fallen", not bool(ctx.get("ok", false)))


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
	# The return needs a free slot: a hand at MAX_HAND_SIZE refuses it by design,
	# and by this point in the run the scenarios above have filled it.
	_make_hand_room(1)
	var hand_before: int = combat._hand.size()
	g.take_damage(999)
	await process_frame
	_ck("returned to hand on death", combat._hand.size() == hand_before + 1,
		"hand %dв†’%d" % [hand_before, combat._hand.size()])


func _t_warchief() -> void:
	print("\n[newcards] === Warchief: buffs other Soldiers, never itself ===")
	_clear()
	var w = _seat_id("warchief", false, 0)
	var a1 = _seat_id("pikeman", false, 1)
	var a2 = _seat_id("skirmisher", false, 2)
	combat._refresh_adjacency_buffs()
	_ck("Warchief kept its printed 2 ATK", w.effective_atk() == 2,
		"atk=%d" % w.effective_atk())
	_ck("other Soldiers each gained +1 ATK",
		a1.effective_atk() == 3 and a2.effective_atk() == 4,
		"pikeman=%d headhunter=%d" % [a1.effective_atk(), a2.effective_atk()])
	w.take_damage(999)
	await process_frame
	combat._cleanup_dead()
	_ck("aura vanished with the Warchief",
		a1.effective_atk() == 2 and a2.effective_atk() == 3,
		"pikeman=%d headhunter=%d" % [a1.effective_atk(), a2.effective_atk()])



# -- 2026-07-07 fun slate ----------------------------------------------------

func _t_petard() -> void:
	print("\n[newcards] === The Petard: targeted blast + row splash ===")
	_clear()
	var left = _seat_plain(true, 0, 0, 9)
	var e = _seat_plain(true, 1, 0, 9)
	var right = _seat_plain(true, 2, 0, 9)
	await _cast("petard", e)
	_ck("chosen creature ate 5", e.current_hp == 4, "hp=%d" % e.current_hp)
	_ck("row neighbours ate 2 splash", left.current_hp == 7 and right.current_hp == 7,
		"L=%d R=%d" % [left.current_hp, right.current_hp])


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
