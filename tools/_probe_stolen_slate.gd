extends SceneTree
## Correctness probe for the 2026-07-13 "stolen classics" slate. Boots real
## SOLO combat and drives each design through its real resolver / hook:
##   Grave Clutch — on-death 4/4 hatches in the lane (5/5 forged)
##   Pressed Man  — on-death the ENEMY face heals 3 (capped at its max)
##   The Undying  — each death writes a permanent +1/+1 mod (stacks, folds)
##   The Long Roll— highlander gate (dupes/full HP grey it); heal 10 / 14+
##   Wolf-Pits    — 2 charges queue; the next enemy arrival takes 3 (5+)
##   The Informer — reads the top 3 arrivals, strikes the pick from the deck
##   Forgefire    — every hand card folds its "+" for this fight
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_stolen_slate.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
var RS: Node
var US: Node
var SS: Node
var CDB: Node
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
	print("[stolen] start")
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or CDB == null:
		print("[stolen] FATAL autoloads"); quit(1); return
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
		print("[stolen] FATAL no player turn"); quit(1); return

	_test_schema()
	await _test_grave_clutch()
	await _test_pressed_man()
	await _test_undying_writes_mods()
	_test_undying_folds_on_real_deck_card()
	_test_long_roll_gate()
	await _test_long_roll_heals()
	await _test_wolf_pits()
	await _test_informer()
	await _test_forgefire()
	# (Wave 2 of the slate — Grand Melee / Giantfall / Blood Kin / Pit Brawler /
	# Farmer's Son / Great Bombard / Whisper-Widow / Quartermaster — was REVERTED
	# 2026-07-13, user verdict "weird for my game". Its tests left with it.)

	print("[stolen] ============ SUMMARY ============")
	print("[stolen] passed : %d" % _pass)
	print("[stolen] FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[stolen] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _test_schema() -> void:
	for cid in ["grave_clutch", "pressed_man", "the_undying",
			"long_roll", "wolf_pits", "informer", "forgefire"]:
		var d: Dictionary = CDB.get_card_data(cid)
		_assert("schema: %s exists in CARD_POOL" % cid, not d.is_empty())
		_assert("schema: %s has a hand-crafted UPGRADES entry" % cid,
			CDB.UPGRADES.has(cid))
		if d.get("type", "") == "creature":
			_assert("schema: %s carries a ctype" % cid, d.has("ctype"))


func _test_grave_clutch() -> void:
	_clear_all()
	var egg = _place(0, 2, 0, false, combat.ROW_FRONT)
	egg.card_data = CDB.get_card_data("grave_clutch").duplicate(true)
	await _kill(egg)
	var hatched = _creature_in_column(false, 0)
	_assert("grave clutch: something hatched in the lane", hatched != null)
	if hatched != null:
		_assert("grave clutch: it hatched a 4/4",
			int(hatched.current_atk) == 4 and int(hatched.current_hp) == 4)


func _test_pressed_man() -> void:
	_clear_all()
	combat.enemy_hp = maxi(1, combat.enemy_hp - 5)   # leave room to heal
	var before: int = int(combat.enemy_hp)
	var levy = _place(3, 3, 1, false, combat.ROW_FRONT)
	levy.card_data = CDB.get_card_data("pressed_man").duplicate(true)
	await _kill(levy)
	_assert("pressed man: the enemy face healed 3 on its death",
		int(combat.enemy_hp) == mini(before + 3, int(combat.enemy_max_hp)))


func _test_undying_writes_mods() -> void:
	_clear_all()
	var body = _place(2, 2, 2, false, combat.ROW_FRONT)
	body.card_data = CDB.get_card_data("the_undying").duplicate(true)
	body.deck_uid = 777
	await _kill(body)
	var stack: Array = RS.card_upgrades.get(777, [])
	_assert("undying: first death wrote the permanent mod",
		stack.size() == 1 and String(stack[0].get("path", "")) == "undying"
		and int(stack[0].get("stacks", 0)) == 1)
	var body2 = _place(2, 2, 2, false, combat.ROW_FRONT)
	body2.card_data = CDB.get_card_data("the_undying").duplicate(true)
	body2.deck_uid = 777
	await _kill(body2)
	stack = RS.card_upgrades.get(777, [])
	_assert("undying: second death grew the SAME entry to 2 stacks",
		stack.size() == 1 and int(stack[0].get("stacks", 0)) == 2)
	RS.card_upgrades.erase(777)


func _test_undying_folds_on_real_deck_card() -> void:
	# The fold arm: a real deck uid grown once comes back +1/+1.
	var uid: int = int(RS.deck_uids[0])
	var base: Dictionary = CDB.get_card_data(RS.deck[0])
	RS.grow_undying(uid)
	var folded: Dictionary = RS.get_upgraded_card_data(uid)
	_assert("undying fold: grown deck card reads +1/+1",
		int(folded.get("atk", -99)) == int(base.get("atk", 0)) + 1
		and int(folded.get("hp", -99)) == int(base.get("hp", 0)) + 1)
	# Leave the run state as found — the entry is probe-local.
	RS.card_upgrades.erase(uid)


func _test_long_roll_gate() -> void:
	var lr_data: Dictionary = CDB.get_card_data("long_roll")
	# 2026-07-13 buff pass: the highlander REQUIREMENT was dropped from the gate.
	# Any wounded deck can now read the roll (repeated names just heal the base
	# amount); only full HP greys it. The raider starter deck carries duplicates.
	combat.player_hp = combat.player_max_hp - 5
	_assert("long roll gate: repeated names + missing HP unlocks it (base heal)",
		combat._untargeted_random_spell_can_resolve(lr_data))
	# A highlander deck at full HP is still dead (nothing to heal).
	var saved_deck: Array = RS.deck.duplicate()
	RS.deck.assign(["goblin", "brute", "strike"])
	combat.player_hp = combat.player_max_hp
	_assert("long roll gate: full HP blocks the cast",
		not combat._untargeted_random_spell_can_resolve(lr_data))
	combat.player_hp = combat.player_max_hp - 5
	_assert("long roll gate: unique names + missing HP unlocks it",
		combat._untargeted_random_spell_can_resolve(lr_data))
	RS.deck.assign(saved_deck)


func _test_long_roll_heals() -> void:
	var saved_deck: Array = RS.deck.duplicate()
	# Non-highlander march (a name repeats): the floor heal always answers now
	# (5 base, per the 2026-07-13 buff-pass rework).
	RS.deck.assign(["goblin", "goblin", "strike"])
	combat.player_hp = combat.player_max_hp - 20
	var base_before: int = int(combat.player_hp)
	await combat._resolve_custom_spell("long_roll", null, -1, {})
	_assert("long roll: a repeated-name march heals the base 5",
		int(combat.player_hp) == base_before + 5)
	# Highlander march (no two names repeat): the roll pays far more (12 base).
	RS.deck.assign(["goblin", "brute", "strike"])
	combat.player_hp = combat.player_max_hp - 20
	var before: int = int(combat.player_hp)
	await combat._resolve_custom_spell("long_roll", null, -1, {})
	_assert("long roll: every unique name answered — highlander heals 12",
		int(combat.player_hp) == before + 12)
	await combat._resolve_custom_spell("long_roll", null, -1, {"is_upgraded": true})
	_assert("long roll+: the forged highlander roll heals 16 (capped)",
		int(combat.player_hp) == mini(before + 12 + 16, int(combat.player_max_hp)))
	RS.deck.assign(saved_deck)
	combat.player_hp = combat.player_max_hp


func _test_wolf_pits() -> void:
	_clear_all()
	combat._pit_traps.clear()
	await combat._resolve_custom_spell("wolf_pits", null, -1, {})
	_assert("wolf-pits: two charges dug", combat._pit_traps.size() == 2
		and int(combat._pit_traps[0]) == 3)
	var dummy := {"id": "e_brute", "name": "Pit Tester", "type": "creature",
		"cost": 1, "atk": 2, "hp": 8, "rarity": "enemy", "keywords": []}
	combat._place_enemy_card(dummy.duplicate(true), 3)
	var arrived = combat._row_array(true, combat.ROW_FRONT)[3]
	_assert("wolf-pits: the arrival fell in for 3",
		arrived != null and int(arrived.current_hp) == 5)
	_assert("wolf-pits: one charge remains", combat._pit_traps.size() == 1)
	combat._pit_traps.clear()
	# Forged path uses the REAL "+" fold so the dmg_bonus merge is what's tested.
	var wp_plus: Dictionary = RS._apply_plus_upgrade(CDB.get_card_data("wolf_pits").duplicate(true))
	await combat._resolve_custom_spell("wolf_pits", null, -1, wp_plus)
	_assert("wolf-pits+: forged pits bite for 5", int(combat._pit_traps[0]) == 5)
	combat._pit_traps.clear()


func _test_informer() -> void:
	combat._enemy_deck.assign([
		CDB.get_card_data("e_goblin").duplicate(true),
		CDB.get_card_data("e_brute").duplicate(true),
		CDB.get_card_data("e_archer").duplicate(true),
		CDB.get_card_data("e_golem").duplicate(true),
	])
	# Headless auto-picks the FIRST shown id (e_goblin).
	await combat._resolve_custom_spell("informer", null, -1, {})
	_assert("informer: one arrival struck from the muster",
		combat._enemy_deck.size() == 3)
	_assert("informer: the PICKED name is the one gone",
		String(combat._enemy_deck[0].get("id", "")) == "e_brute")
	_assert("informer gate: an empty muster greys the card",
		combat._untargeted_random_spell_can_resolve(
			CDB.get_card_data("informer")))
	combat._enemy_deck.clear()
	_assert("informer gate: ...and blocks once nothing is coming",
		not combat._untargeted_random_spell_can_resolve(
			CDB.get_card_data("informer")))


func _test_forgefire() -> void:
	var uid: int = combat._add_discovered_card_to_hand("brute")
	var forged = null
	for hc in combat._hand:
		if is_instance_valid(hc) and int(hc.deck_uid) == uid:
			forged = hc
			break
	_assert("forgefire setup: a Brute sits in hand", forged != null)
	if forged == null:
		return
	var base_atk: int = int(forged.card_data.get("atk", 0))
	_assert("forgefire gate: an unforged hand unlocks the cast",
		combat._untargeted_random_spell_can_resolve(
			CDB.get_card_data("forgefire")))
	await combat._resolve_custom_spell("forgefire", null, -1, {})
	_assert("forgefire: the hand card took its +",
		bool(forged.card_data.get("is_upgraded", false))
		and int(forged.card_data.get("atk", 0)) == base_atk + 1)
	_purge_hand_card(forged)


# ── helpers (shared shape with _probe_boring_swap) ────────────────────────

func _place(atk: int, hp: int, lane: int, is_enemy: bool, row: int):
	var arr: Array = combat._row_array(is_enemy, row)
	if arr[lane] != null and is_instance_valid(arr[lane]):
		arr[lane].queue_free()
		arr[lane] = null
	combat.summon_token(atk, hp, lane, is_enemy, row)
	return combat._row_array(is_enemy, row)[lane]


func _kill(c) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.take_damage(999)
	if is_instance_valid(c) and c.current_hp <= 0 and c.has_method("try_die"):
		c.try_die()
	await create_timer(0.3).timeout


func _find_player_creature_named(cname: String):
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(false, row):
			if c != null and is_instance_valid(c) \
					and String(c.card_data.get("name", "")) == cname:
				return c
	return null


func _creature_in_column(is_enemy: bool, lane: int):
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var c = combat._row_array(is_enemy, row)[lane]
		if c != null and is_instance_valid(c):
			return c
	return null


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
		print("[stolen] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[stolen] FAIL  %s" % name)


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
