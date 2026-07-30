extends Node
## _probe_retinue_spells.gd — the 8 hero-retinue starter spells (2026-07-28).
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_retinue_spells.tscn
##
## Every one of these shipped as DATA ONLY: `spell: {type:"custom", id:"starter_*"}`
## with no arm in Combat._resolve_custom_spell, so each fell through `_: pass` and
## cost Command, exhausted, logged "You cast X" — and did nothing. A spell that
## looks finished and isn't is worse than one that is obviously missing, which is
## why the assertions here are arithmetic on specific numbers rather than
## "it didn't crash".
##
## Three things this file exists to keep honest:
##   1. THE "+" KEYS. These cards use atk_bonus / hp_bonus / extra_reveal /
##      doom_tick, none of which were in _resolve_custom_spell's precomputed
##      header. Reading plus_dmg instead makes the forge print blank.
##   2. THE MAX-HP HALF. A "+N HP this fight" that writes current_hp without
##      card_data.hp is silently erased by the next heal (every heal caps at
##      card_data.hp).
##   3. THE TWO TARGET CONTRACTS. Read the Will and Touchpaper are gated in
##      _target_contract_available — "no dead rewards" — and Read the Will must
##      REFUSE return_to_hand_once / undying_grow, the identity arms that
##      dispatch_on_death short-circuits. undying_grow writes a PERMANENT
##      run-wide +1/+1 through RunState; letting Read the Will reach it is an
##      infinite growth engine for 1 Command.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0
var combat


func _ready() -> void:
	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame

	combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum 0, which is
	# also the uninitialised default (documented trap).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")
	combat.enemy_hp = 400

	await _t_spur_forward()
	await _t_cut_them_off()
	await _t_close_ranks()
	await _t_read_the_will()
	await _t_last_due()
	await _t_star_chart()
	await _t_countermarch()
	await _t_touchpaper()
	await _t_contracts()

	print("[retinue] %d failures" % _fails)
	print("[retinue] " + ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(1 if _fails > 0 else 0)


# ── 1. SPUR FORWARD ──────────────────────────────────────────────────────────
func _t_spur_forward() -> void:
	print("[retinue] --- spur_forward ---")
	await _settle()
	combat._player_moved_a_friendly_this_round = false
	var body = _put(false, combat.ROW_FRONT, 0, 2, 5)
	if not _check(body != null, "fixture placed"): return
	await combat._resolve_spell(_card("spur_forward"), body, 0)
	_check(int(body.current_lane) != 0 or int(body.current_row) != combat.ROW_FRONT,
		"body relocated (now row %d lane %d)" % [body.current_row, body.current_lane])
	_check(int(body.temp_atk_buff) >= 2,
		"+2 ATK rider landed (temp_atk_buff=%d; Marching Spurs may add 1)" % body.temp_atk_buff)
	_check(bool(body.state.war_cry_swift), "Swift rider landed")
	_check(combat._player_moved_a_friendly_this_round,
		"the move armed the Cut Them Off latch")

	await _settle()
	combat._player_moved_a_friendly_this_round = false
	var body2 = _put(false, combat.ROW_FRONT, 0, 2, 5)
	var plus := _card("spur_forward"); plus["atk_bonus"] = 1
	await combat._resolve_spell(plus, body2, 0)
	_check(int(body2.temp_atk_buff) >= 3,
		"the forge reads atk_bonus, not dmg_bonus (temp=%d)" % body2.temp_atk_buff)


# ── 2. CUT THEM OFF ──────────────────────────────────────────────────────────
func _t_cut_them_off() -> void:
	print("[retinue] --- cut_them_off ---")
	await _settle()
	combat._player_moved_a_friendly_this_round = false
	var foe = _put(true, combat.ROW_FRONT, 0, 1, 60)
	var before: int = int(foe.current_hp)
	await combat._resolve_spell(_card("cut_them_off"), foe, 0)
	_check(before - int(foe.current_hp) == 2,
		"unmoved deals 2 (dealt %d)" % [before - int(foe.current_hp)])

	combat._player_moved_a_friendly_this_round = true
	before = int(foe.current_hp)
	await combat._resolve_spell(_card("cut_them_off"), foe, 0)
	_check(before - int(foe.current_hp) == 4,
		"after YOU moved a friendly it deals 4 (dealt %d)" % [before - int(foe.current_hp)])

	var plus := _card("cut_them_off"); plus["dmg_bonus"] = 1
	before = int(foe.current_hp)
	await combat._resolve_spell(plus, foe, 0)
	_check(before - int(foe.current_hp) == 5, "forged + moved deals 5")
	combat._player_moved_a_friendly_this_round = false


# ── 3. DRESS THE LINE ────────────────────────────────────────────────────────
func _t_close_ranks() -> void:
	print("[retinue] --- close_ranks_order ---")
	await _settle()
	var mid = _put(false, combat.ROW_FRONT, 1, 1, 4)
	var side = _put(false, combat.ROW_FRONT, 2, 1, 4)
	var mate = _put(false, combat.ROW_BACK, 1, 1, 4)
	var far = _put(false, combat.ROW_BACK, 3, 1, 4)
	if not _check(mid != null and side != null and mate != null, "fixture placed"): return
	await combat._resolve_spell(_card("close_ranks_order"), mid, 1)
	_check(int(mid.current_hp) == 5 and int(mid.card_data.hp) == 5,
		"the named body gains BOTH current and max (%d/%d)" % [mid.current_hp, mid.card_data.hp])
	_check(int(side.current_hp) == 5, "row neighbour +1")
	_check(int(mate.current_hp) == 5, "column-mate +1 (canonical adjacency)")
	_check(int(far.current_hp) == 4, "a non-adjacent body is untouched")

	var plus := _card("close_ranks_order"); plus["hp_bonus"] = 1
	await combat._resolve_spell(plus, mid, 1)
	_check(int(mid.card_data.hp) == 7, "the forge reads hp_bonus (%d)" % mid.card_data.hp)


# ── 4. READ THE WILL ─────────────────────────────────────────────────────────
func _t_read_the_will() -> void:
	print("[retinue] --- read_the_will ---")
	await _settle()
	var body = _put(false, combat.ROW_FRONT, 0, 1, 5)
	body.card_data["on_death"] = {"type": "bonus_mana_next_turn", "value": 1}
	var before: int = int(combat._bonus_mana_next_turn)
	await combat._resolve_spell(_card("read_the_will"), body, 0)
	_check(int(combat._bonus_mana_next_turn) == before + 1,
		"the bequest fired (%d -> %d)" % [before, combat._bonus_mana_next_turn])
	_check(is_instance_valid(body) and int(body.current_hp) > 0,
		"...and the body is still standing")

	body.card_data["on_death"] = {"type": "undying_grow"}
	var before2: int = int(combat._bonus_mana_next_turn)
	await combat._resolve_spell(_card("read_the_will"), body, 0)
	_check(int(combat._bonus_mana_next_turn) == before2 and is_instance_valid(body),
		"undying_grow is refused, not run (the farmable arm)")


# ── 5. THE LAST DUE ──────────────────────────────────────────────────────────
func _t_last_due() -> void:
	print("[retinue] --- last_due ---")
	await _settle()
	var victim = _put(false, combat.ROW_FRONT, 0, 1, 5)
	var foe = _put(true, combat.ROW_FRONT, 0, 1, 60)
	var foe_before: int = int(foe.current_hp)
	await combat._resolve_spell(_card("last_due"), victim, 0)
	_check(not is_instance_valid(victim) or int(victim.current_hp) <= 0,
		"the victim paid with its body")
	_check(foe_before - int(foe.current_hp) == 2,
		"2 landed across its OWN lane (dealt %d)" % [foe_before - int(foe.current_hp)])

	await _settle()
	var victim2 = _put(false, combat.ROW_FRONT, 2, 1, 5)
	var face_before: int = int(combat.enemy_hp)
	var plus := _card("last_due"); plus["dmg_bonus"] = 2
	await combat._resolve_spell(plus, victim2, 2)
	_check(face_before - int(combat.enemy_hp) == 4,
		"an empty column sends the forged 4 to the FACE, never a random body (dealt %d)"
			% [face_before - int(combat.enemy_hp)])


# ── 6. STAR CHART ────────────────────────────────────────────────────────────
func _t_star_chart() -> void:
	print("[retinue] --- star_chart ---")
	await _settle()
	var deck_before: int = combat._enemy_deck.size()
	await combat._resolve_spell(_card("star_chart"), null, -1)
	_check(combat._enemy_deck.size() == deck_before,
		"reading the road consumes nothing (deck %d)" % combat._enemy_deck.size())
	var plus := _card("star_chart"); plus["extra_reveal"] = 1
	await combat._resolve_spell(plus, null, -1)
	_check(combat._enemy_deck.size() == deck_before, "the forged 2-reveal consumes nothing either")
	var saved: Array = combat._enemy_deck.duplicate()
	combat._enemy_deck.clear()
	await combat._resolve_spell(_card("star_chart"), null, -1)
	_check(true, "an empty road does not crash")
	combat._enemy_deck.assign(saved)


# ── 7. CHANGE STEP ───────────────────────────────────────────────────────────
func _t_countermarch() -> void:
	print("[retinue] --- countermarch_levy ---")
	await _settle()
	var body = _put(false, combat.ROW_FRONT, 3, 1, 4)
	await combat._resolve_spell(_card("countermarch_levy"), body, 3)
	_check(int(body.current_row) == combat.ROW_BACK and int(body.current_lane) == 3,
		"moved to the other row (row %d lane %d)" % [body.current_row, body.current_lane])
	_check(int(body.card_data.hp) == 5 and int(body.current_hp) == 5,
		"+1 HP this fight, current AND max (%d/%d)" % [body.current_hp, body.card_data.hp])

	var mate = _put(false, combat.ROW_FRONT, 3, 2, 6)
	await combat._resolve_spell(_card("countermarch_levy"), body, 3)
	_check(int(body.current_row) == combat.ROW_FRONT and int(mate.current_row) == combat.ROW_BACK,
		"a TAKEN seat swaps rather than no-opping (body row %d, mate row %d)"
			% [body.current_row, mate.current_row])
	_check(int(body.card_data.hp) == 6, "the swap still paid the +1 HP (%d)" % body.card_data.hp)


# ── 8. TOUCHPAPER ────────────────────────────────────────────────────────────
func _t_touchpaper() -> void:
	print("[retinue] --- touchpaper ---")
	await _settle()
	var fuse = _put(false, combat.ROW_FRONT, 0, 2, 5, ["doom"])
	fuse.card_data["doom"] = 3
	fuse.doom_counter = 3
	await combat._resolve_spell(_card("touchpaper"), fuse, 0)
	_check(int(fuse.doom_counter) == 2, "the fuse burned 3 -> %d" % fuse.doom_counter)
	var plus := _card("touchpaper"); plus["doom_tick"] = 1
	await combat._resolve_spell(plus, fuse, 0)
	_check(int(fuse.doom_counter) == 0, "the forge reads doom_tick (now %d)" % fuse.doom_counter)
	await get_tree().create_timer(0.4).timeout
	_check(not is_instance_valid(fuse) or int(fuse.current_hp) <= 0,
		"reaching 0 detonated it")

	await _settle()
	var plain = _put(false, combat.ROW_FRONT, 1, 2, 5)
	await combat._resolve_spell(_card("touchpaper"), plain, 1)
	_check(is_instance_valid(plain) and int(plain.current_hp) == 5,
		"a fuseless body is untouched (the miss telegraph, not a crash)")


# ── 9. TARGET CONTRACTS ──────────────────────────────────────────────────────
func _t_contracts() -> void:
	print("[retinue] --- target contracts ---")
	await _settle()
	var will := _card("read_the_will")
	var touch := _card("touchpaper")
	_check(not combat._target_contract_available(will),
		"Read the Will is uncastable on an empty board")
	_check(not combat._target_contract_available(touch),
		"Touchpaper is uncastable on an empty board")

	var plain = _put(false, combat.ROW_FRONT, 0, 1, 4)
	_check(not combat._target_contract_available(will),
		"...and uncastable with only a bequest-less body")
	plain.card_data["on_death"] = {"type": "undying_grow"}
	_check(not combat._target_contract_available(will),
		"...and uncastable when the only will is a DENIED one")
	plain.card_data["on_death"] = {"type": "bonus_mana_next_turn", "value": 1}
	_check(combat._target_contract_available(will),
		"...castable once a real bequest stands")

	_check(not combat._target_contract_available(touch), "Touchpaper still barred (no Doom)")
	_put(false, combat.ROW_FRONT, 1, 1, 4, ["doom"])
	_check(combat._target_contract_available(touch), "Touchpaper opens on a Doom body")


# ── helpers ──────────────────────────────────────────────────────────────────
func _card(id: String) -> Dictionary:
	return CardDB.CARD_POOL[id].duplicate(true)


## Drop a synthetic body with exact stats, via the engine's own token primitive
## (the _probe_overkill convention). Deliberately not _play_creature, which rolls
## real card data — these assertions are arithmetic on specific numbers.
func _put(is_enemy: bool, row: int, lane: int, atk: int, hp: int, kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


## Clear the board BETWEEN sections, but let the previous section's decorative
## FX tweens expire first. This harness fires spells back to back with no frame
## budget, so a bare queue_free() strands live tween lambdas holding the node and
## the engine prints "Lambda capture at index N was freed" — harness noise that
## looks exactly like a real defect in the log.
func _settle() -> void:
	await get_tree().create_timer(0.9).timeout
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null
	await get_tree().create_timer(0.2).timeout


func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return "goblin_scouts"


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
