extends SceneTree
## Correctness probe for the 2026-07-10 boring-cards swap. Boots real SOLO
## combat, builds known boards, and drives each replacement through its real
## resolver / hook:
##   Testudo (was Shield Wall)      — front row gains Shield; forged reaches back
##   Turncoat (was Inspire)         — ≤3 ATK foe deserts (4 forged); strong foes stun
##   Baggage Train (was Second Wind)— +3 Command NEXT turn (+4 forged)
##   Fetch Hound (was Hound)        — last spell in discard returns to hand;
##                                    curses stay buried; empty pile = draw 1
##   Shieldmaiden (interpose)       — face STRIKES land on her; effect damage passes
##   The Apothecary (toxin_salve)   — a poison kill heals the owner's hero 2
##   Legacy shim                    — old spell ids fold onto the new arms
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_boring_swap.gd

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
	print("[boring] start")
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null:
		print("[boring] FATAL autoloads"); quit(1); return
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
		print("[boring] FATAL no player turn"); quit(1); return

	_test_legacy_shim()
	await _test_testudo_front_row()
	await _test_testudo_forged_back_row()
	await _test_turncoat_desertion()
	await _test_turncoat_strong_foe_stuns()
	await _test_turncoat_forged_gate()
	await _test_baggage_train()
	_test_fetch_spell_returns_last_spell()
	_test_fetch_spell_skips_curses()
	_test_fetch_spell_empty_pile_draws()
	_test_interpose_catches_strikes()
	_test_interpose_lets_effects_through()
	_test_toxin_salve()

	print("[boring] ============ SUMMARY ============")
	print("[boring] passed : %d" % _pass)
	print("[boring] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[boring] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _test_legacy_shim() -> void:
	_assert("shim: shield_wall folds to testudo",
		combat._canonical_custom_spell_id("shield_wall") == "testudo")
	_assert("shim: inspire folds to turncoat",
		combat._canonical_custom_spell_id("inspire") == "turncoat")
	_assert("shim: adrenaline folds to baggage_train",
		combat._canonical_custom_spell_id("adrenaline") == "baggage_train")
	_assert("shim: new ids pass through untouched",
		combat._canonical_custom_spell_id("testudo") == "testudo")


func _test_testudo_front_row() -> void:
	_clear_all()
	var f0 = _place(2, 4, 0, false, combat.ROW_FRONT)
	var f1 = _place(2, 4, 1, false, combat.ROW_FRONT)
	var b0 = _place(2, 4, 0, false, combat.ROW_BACK)
	await combat._resolve_custom_spell("testudo", null, -1, {})
	_assert("testudo: front-left locked its shield", f0.state.has_shield)
	_assert("testudo: front-mid locked its shield", f1.state.has_shield)
	_assert("testudo: base writ does NOT reach the back row", not b0.state.has_shield)


func _test_testudo_forged_back_row() -> void:
	_clear_all()
	var f0 = _place(2, 4, 0, false, combat.ROW_FRONT)
	var b0 = _place(2, 4, 0, false, combat.ROW_BACK)
	await combat._resolve_custom_spell("testudo", null, -1, {"is_upgraded": true})
	_assert("testudo+: front shielded", f0.state.has_shield)
	_assert("testudo+: back row locks in too", b0.state.has_shield)


func _test_turncoat_desertion() -> void:
	_clear_all()
	var e = _place(2, 6, 1, true, combat.ROW_FRONT)   # 2 ATK ≤ gate 3
	e.card_data["name"] = "Waverer"
	await combat._resolve_custom_spell("turncoat", e, -1, {})
	_assert("turncoat: enemy slot vacated",
		combat._row_array(true, combat.ROW_FRONT)[1] == null)
	var deserter = _find_player_creature_named("Waverer")
	_assert("turncoat: the deserter stands on YOUR side", deserter != null)
	if deserter != null:
		_assert("turncoat: live stats crossed over (2/6)",
			int(deserter.current_atk) == 2 and int(deserter.current_hp) == 6)
		_assert("turncoat: the deserter is no deck card (is_token)",
			bool(deserter.is_token))


func _test_turncoat_strong_foe_stuns() -> void:
	_clear_all()
	var e = _place(5, 6, 1, true, combat.ROW_FRONT)   # 5 ATK > gate
	await combat._resolve_custom_spell("turncoat", e, -1, {})
	_assert("turncoat: a strong foe holds its post",
		combat._row_array(true, combat.ROW_FRONT)[1] == e)
	_assert("turncoat: ...but hesitates (stunned)", e.state.stunned)


func _test_turncoat_forged_gate() -> void:
	_clear_all()
	var e = _place(4, 6, 2, true, combat.ROW_FRONT)   # 4 ATK: over base gate, at forged gate
	e.card_data["name"] = "Bought Man"
	await combat._resolve_custom_spell("turncoat", e, -1, {"is_upgraded": true})
	_assert("turncoat+: the forged writ buys a 4-ATK man",
		combat._row_array(true, combat.ROW_FRONT)[2] == null
		and _find_player_creature_named("Bought Man") != null)


func _test_baggage_train() -> void:
	_clear_all()
	var before: int = int(combat._bonus_mana_next_turn)
	await combat._resolve_custom_spell("baggage_train", null, -1, {})
	_assert("baggage train: +3 Command banked for next turn",
		int(combat._bonus_mana_next_turn) == before + 3)
	await combat._resolve_custom_spell("baggage_train", null, -1, {"is_upgraded": true})
	_assert("baggage train+: the forged wagons bank 4",
		int(combat._bonus_mana_next_turn) == before + 7)
	combat._bonus_mana_next_turn = before


func _test_fetch_spell_returns_last_spell() -> void:
	_clear_all()
	combat._player_discard_pile.clear()
	combat._player_discard_pile.append(combat._pile_entry("slash", 901))
	combat._player_discard_pile.append(combat._pile_entry("war_cry", 902))
	combat._player_discard_pile.append(combat._pile_entry("pikeman", 903))  # creature on top
	var hand0: int = combat._hand.size()
	var hound = _place(1, 2, 0, false, combat.ROW_FRONT)
	hound.card_data["on_play"] = {"type": "fetch_spell"}
	combat._resolve_on_play_ability(hound, 0, false)
	_assert("fetch: hand grew by 1", combat._hand.size() == hand0 + 1)
	var fetched = combat._hand[combat._hand.size() - 1] if combat._hand.size() > 0 else null
	_assert("fetch: the LAST spell came back (war_cry, skipping the creature)",
		fetched != null and String(fetched.card_id) == "war_cry")
	_assert("fetch: its pile entry is gone (no duplicate)",
		not combat._player_discard_pile.has(combat._pile_entry("war_cry", 902)))
	_assert("fetch: the older spell stays buried",
		combat._player_discard_pile.has(combat._pile_entry("slash", 901)))
	_purge_hand_card(fetched)


func _test_fetch_spell_skips_curses() -> void:
	_clear_all()
	combat._player_discard_pile.clear()
	combat._player_discard_pile.append("curse")   # bare-id entry, like the prod curse appends
	var hand0: int = combat._hand.size()
	var draw0: int = combat._player_draw_pile.size()
	var hound = _place(1, 2, 0, false, combat.ROW_FRONT)
	hound.card_data["on_play"] = {"type": "fetch_spell"}
	combat._resolve_on_play_ability(hound, 0, false)
	_assert("fetch: a curse is never fetched (falls back to a draw)",
		combat._player_discard_pile.has("curse")
		and combat._hand.size() + combat._player_draw_pile.size() == hand0 + draw0)
	if combat._hand.size() > hand0:
		_purge_hand_card(combat._hand[combat._hand.size() - 1])


func _test_fetch_spell_empty_pile_draws() -> void:
	_clear_all()
	combat._player_discard_pile.clear()
	var hand0: int = combat._hand.size()
	var draw0: int = combat._player_draw_pile.size()
	var hound = _place(1, 2, 0, false, combat.ROW_FRONT)
	hound.card_data["on_play"] = {"type": "fetch_spell"}
	combat._resolve_on_play_ability(hound, 0, false)
	_assert("fetch: empty pile still pays a card (draw 1)",
		combat._hand.size() + combat._player_draw_pile.size() == hand0 + draw0
		and (combat._hand.size() == hand0 + 1 or draw0 == 0))
	if combat._hand.size() > hand0:
		_purge_hand_card(combat._hand[combat._hand.size() - 1])


func _test_interpose_catches_strikes() -> void:
	_clear_all()
	var maiden = _place(1, 5, 1, false, combat.ROW_FRONT)
	maiden.card_data["passive"] = "interpose"
	var hero0: int = int(combat.player_hp)
	combat.damage_player_hero(3, false)   # a creature strike at the face
	_assert("interpose: the hero never bled", int(combat.player_hp) == hero0)
	_assert("interpose: the maiden took the blow (5 → 2)", int(maiden.current_hp) == 2)


func _test_interpose_lets_effects_through() -> void:
	_clear_all()
	var maiden = _place(1, 5, 1, false, combat.ROW_FRONT)
	maiden.card_data["passive"] = "interpose"
	var hero0: int = int(combat.player_hp)
	combat.damage_player_hero(2, true)    # effect damage — a curse sting, Doom, spill
	_assert("interpose: effect damage goes past her (blades, not fate)",
		int(combat.player_hp) == hero0 - 2 and int(maiden.current_hp) == 5)
	combat.player_hp = hero0


func _test_toxin_salve() -> void:
	_clear_all()
	var apoth = _place(1, 4, 0, false, combat.ROW_BACK)
	apoth.card_data["passive"] = "toxin_salve"
	combat.player_hp = 20
	combat._apply_toxin_salve(true)    # an enemy body just dropped to Poison
	_assert("toxin: the apothecary salved the hero (+2 HP)",
		combat.player_hp == 22)
	_clear_all()
	combat.player_hp = 20
	combat._apply_toxin_salve(true)    # no apothecary on the board
	_assert("toxin: no apothecary, no salve", combat.player_hp == 20)


# --- helpers (same kit as _probe_removal_slate) ---

func _place(atk: int, hp: int, lane: int, is_enemy: bool, row: int):
	var arr: Array = combat._row_array(is_enemy, row)
	if arr[lane] != null and is_instance_valid(arr[lane]):
		arr[lane].queue_free()
		arr[lane] = null
	combat.summon_token(atk, hp, lane, is_enemy, row)
	return combat._row_array(is_enemy, row)[lane]


func _find_player_creature_named(cname: String):
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(false, row):
			if c != null and is_instance_valid(c) \
					and String(c.card_data.get("name", "")) == cname:
				return c
	return null


## Pull a probe-drawn card back out of the hand so later hand-size baselines
## stay honest (the entry is NOT refiled — probe cards are throwaways).
func _purge_hand_card(card) -> void:
	if card == null or not is_instance_valid(card):
		return
	combat._hand.erase(card)
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	card.queue_free()


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
		print("[boring] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[boring] FAIL  %s" % name)


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
