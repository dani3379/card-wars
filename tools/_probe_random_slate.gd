extends Node
## _probe_random_slate.gd — the 2026-09-17 cost-5 randomness slate.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_random_slate.tscn
##
## Three new spells (The Powder Store / Case Shot / The Press-Gang) whose whole
## point is that they do something UNPREDICTABLE. That makes them exactly the
## shape of content this harness has been burned by before: a custom spell with
## no resolver arm falls through `_: pass` in _resolve_custom_spell and costs
## Command, exhausts, logs "You cast X" — and does nothing. "It didn't crash" is
## not evidence for a random card, because doing nothing never crashes either.
##
## So every check below is a MEASURED consequence, and each is chosen to survive
## the randomness rather than to hope it cooperates:
##   * Case Shot asserts TOTAL damage across the enemy line, which is fixed at 8
##     even though its distribution is not. Asserting where a pellet landed
##     would be asserting the RNG.
##   * The Press-Gang asserts the COUNT of new friendly bodies and that every
##     one is a token (the deck must not be touched), not which creatures came.
##   * The Powder Store asserts the cast COUNTER moved — it cannot assert an
##     effect, because which spells it rolls is the entire mechanic. It also
##     pins the recursion guard: the roll is capped below the store's own cost,
##     so it must never be able to find itself.
## The "+" halves are driven by a local `is_plus` in the resolver rather than by
## a merged UPGRADES key, so each is exercised separately — a desc-only upgrade
## entry is the documented way this codebase hides an inert forge.

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
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")
	combat.enemy_hp = 400

	await _t_case_shot()
	await _t_press_gang()
	await _t_powder_store()
	await _t_recursion_guard()

	print("[random-slate] %d failures" % _fails)
	print("[random-slate] " + ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(1 if _fails > 0 else 0)


# ── CASE SHOT — 8 damage split at random, but the TOTAL is not random ────────
func _t_case_shot() -> void:
	print("[random-slate] --- case_shot ---")
	await _settle()
	# Four fat bodies: nothing can die, so every pellet must land on the line
	# and the sum is readable. A body that died mid-volley would take its
	# remaining HP out of the accounting.
	var foes := []
	for lane in range(4):
		foes.append(_put(true, combat.ROW_FRONT, lane, 1, 40))
	var before := 0
	for f in foes:
		before += int(f.current_hp)
	await combat._resolve_spell(_card("case_shot"), null, -1)
	var after := 0
	var hit := 0
	for f in foes:
		if f != null and is_instance_valid(f):
			after += int(f.current_hp)
			if int(f.current_hp) < 40:
				hit += 1
	_check(before - after == 8, "base deals 8 total (dealt %d)" % [before - after])
	_check(hit >= 2, "the load SCATTERS — %d of 4 bodies took a pellet" % hit)

	await _settle()
	foes = []
	for lane in range(4):
		foes.append(_put(true, combat.ROW_FRONT, lane, 1, 40))
	before = 0
	for f in foes:
		before += int(f.current_hp)
	var plus := _card("case_shot")
	plus["dmg_bonus"] = 3
	await combat._resolve_spell(plus, null, -1)
	after = 0
	for f in foes:
		if f != null and is_instance_valid(f):
			after += int(f.current_hp)
	_check(before - after == 11, "the forge reads dmg_bonus (dealt %d)" % [before - after])


# ── THE PRESS-GANG — count and provenance, never which bodies ────────────────
func _t_press_gang() -> void:
	print("[random-slate] --- press_gang ---")
	await _settle()
	var deck_before: int = RunState.deck.size()
	await combat._resolve_spell(_card("press_gang"), null, -1)
	var bodies := _friendly_bodies()
	_check(bodies.size() == 3, "base summons 3 (got %d)" % bodies.size())
	var all_tokens := true
	var all_cheap := true
	for b in bodies:
		if not bool(b.is_token):
			all_tokens = false
		if int(b.card_data.get("cost", 0)) > 3:
			all_cheap = false
	_check(all_tokens, "every pressed body is a TOKEN — its death files into no pile")
	_check(all_cheap, "the gang cannot hand over anything above cost 3")
	_check(RunState.deck.size() == deck_before,
		"the deck is untouched (%d -> %d)" % [deck_before, RunState.deck.size()])

	await _settle()
	var plus := _card("press_gang")
	plus["is_upgraded"] = true
	await combat._resolve_spell(plus, null, -1)
	_check(_friendly_bodies().size() == 4,
		"the forge summons 4 (got %d)" % _friendly_bodies().size())


# ── THE POWDER STORE — the counter moved, three times ────────────────────────
func _t_powder_store() -> void:
	print("[random-slate] --- powder_store ---")
	await _settle()
	# Give it something to aim at, or every targeted roll declines to resolve
	# and the store legitimately does nothing.
	for lane in range(4):
		_put(true, combat.ROW_FRONT, lane, 1, 60)
	var before: int = int(combat._spells_cast_this_turn)
	await combat._resolve_spell(_card("powder_store"), null, -1)
	var cast: int = int(combat._spells_cast_this_turn) - before
	_check(cast == 3, "base casts 3 real spells (counter moved %d)" % cast)

	await _settle()
	for lane in range(4):
		_put(true, combat.ROW_FRONT, lane, 1, 60)
	before = int(combat._spells_cast_this_turn)
	var plus := _card("powder_store")
	plus["is_upgraded"] = true
	await combat._resolve_spell(plus, null, -1)
	cast = int(combat._spells_cast_this_turn) - before
	_check(cast == 4, "the forge casts 4 (counter moved %d)" % cast)


# ── THE RECURSION GUARD — the roll must not reach the top of the curve ───────
func _t_recursion_guard() -> void:
	print("[random-slate] --- recursion guard ---")
	# The store rolls at cap 4 and costs 5. That is the ONLY thing stopping it
	# casting itself; if either number moves this must fail rather than hang.
	var cap := 4
	var offenders := []
	for id in CardDB.CARD_POOL:
		var d: Dictionary = CardDB.CARD_POOL[id]
		if String(d.get("type", "")) != "spell":
			continue
		if not bool(d.get("draftable", true)):
			continue
		if String(d.get("spell", {}).get("id", "")) == "powder_store" \
				and int(d.get("cost", 99)) <= cap:
			offenders.append(String(id))
	_check(offenders.is_empty(),
		"no self-casting spell sits at or below the cap (%s)" % str(offenders))
	_check(int(CardDB.CARD_POOL["powder_store"].get("cost", 0)) > cap,
		"the store costs more than it can roll")


func _friendly_bodies() -> Array:
	var out := []
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for i in range(combat.LANES_PER_ROW):
			if arr[i] != null and is_instance_valid(arr[i]):
				out.append(arr[i])
	return out


func _card(id: String) -> Dictionary:
	return CardDB.CARD_POOL[id].duplicate(true)


func _put(is_enemy: bool, row: int, lane: int, atk: int, hp: int, kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


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
