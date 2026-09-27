extends Node
## _probe_counterorders_live.gd — the COUNTERORDERS slate, on a real board.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_counterorders_live.tscn
##
## Its sibling `_probe_counterorders.gd` checks DATA and SOURCE TEXT: that the
## cards exist, that they are denylisted, that the resolvers are wired. Those
## assertions prove the slate was WIRED as described. They prove nothing about
## whether it WORKS, and `_probe_autorun` runs starter decks so these three cards
## have never once been on a board.
##
## THE ASSUMPTION THIS FILE EXISTS TO TEST. `_apply_combat_strike_riders` reads
## `_wears_an_order(defender)` AFTER the strike has killed that defender
## (Combat.gd:6262 samples `was_lethal`, and the rider call is at :6302). The whole
## Interpreter keystone rests on `state.current_intent` still being readable, and
## the node still being valid, at that point. Code reading says it is safe —
## `_die()` is not called in between, deaths are deferred — but "the rare card I
## shipped silently never fires" is exactly the failure a grep cannot see, so it
## is driven here through a REAL clash rather than by calling the rider directly.

const COMBAT_SCENE := "res://scenes/combat.tscn"

## The live intent vocabulary, minus ATK. These are exactly the intents
## `_update_intent_display` prints a badge for, which is the whole design claim:
## "wears an order" is a thing the player can SEE, never a hidden condition.
const ORDER_INTENTS := ["CHARGE", "GUARD", "HEAL", "RALLY", "RETREAT",
	"SUMMON", "ABILITY", "ENRAGE"]

var _fails := 0


func _ready() -> void:
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame

	var combat = load(COMBAT_SCENE).instantiate()
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

	# ── THE PREDICATE ────────────────────────────────────────────────────────
	# Every non-ATK intent must count, and ATK must not. If these two drift apart
	# the cards stop matching the badge the player is reading, which is the one
	# thing the design promises.
	_clear_board(combat)
	var foe = _put(combat, true, combat.ROW_FRONT, 0, 1, 9)
	if _check(foe != null, "fixture: one enemy body"):
		for intent in ORDER_INTENTS:
			foe.state.current_intent = intent
			_check(combat._wears_an_order(foe),
				"'%s' counts as an order" % intent)
		foe.state.current_intent = "ATK"
		_check(not combat._wears_an_order(foe),
			"plain ATK is NOT an order (else the condition is free)")
		foe.state.current_intent = ""
		_check(not combat._wears_an_order(foe),
			"an unassigned intent is NOT an order")
		# Scenery is not a soldier under orders. A structure wearing a badge would
		# otherwise make the whole slate fire off a Pyre.
		foe.state.current_intent = "GUARD"
		foe.card_data["fortification"] = true
		_check(not combat._wears_an_order(foe),
			"a fortification never counts, even wearing a badge")
		foe.card_data.erase("fortification")

	# A FRIENDLY is never "under orders" — the guard is `card.is_opponent`, and
	# without it the player's own board would trigger their own payoffs.
	_clear_board(combat)
	var mine = _put(combat, false, combat.ROW_FRONT, 0, 1, 9)
	if _check(mine != null, "fixture: one friendly body"):
		mine.state.current_intent = "RALLY"
		_check(not combat._wears_an_order(mine),
			"a FRIENDLY wearing an intent is never 'under an order'")

	# ── THE SPELL ────────────────────────────────────────────────────────────
	# The floor first: against a plain attacker it must still be a fair card, or
	# it is a dead draw whenever the foe is simply swinging.
	_clear_board(combat)
	var plain = _put(combat, true, combat.ROW_FRONT, 1, 1, 40)
	if _check(plain != null, "fixture: a 1/40 enemy on plain ATK"):
		plain.state.current_intent = "ATK"
		var hp0: int = int(plain.current_hp)
		await combat._resolve_custom_spell("counterorders", plain, 1,
			CardDB.get_card_data("counterorders"))
		_check(hp0 - plain.current_hp == 3,
			"vs a plain attacker it deals its base 3 (%d -> %d)"
				% [hp0, plain.current_hp])

	_clear_board(combat)
	var committed = _put(combat, true, combat.ROW_FRONT, 1, 1, 40)
	if _check(committed != null, "fixture: a 1/40 enemy under an order"):
		committed.state.current_intent = "CHARGE"
		var hp1: int = int(committed.current_hp)
		await combat._resolve_custom_spell("counterorders", committed, 1,
			CardDB.get_card_data("counterorders"))
		_check(hp1 - committed.current_hp == 6,
			"vs an order it deals 3 + 3 = 6 (%d -> %d)"
				% [hp1, committed.current_hp])

	# The forge must sharpen the CONDITIONAL half specifically — that is the axis
	# the card is about, and a forge that only moved the floor would be off-design.
	_clear_board(combat)
	var forged_t = _put(combat, true, combat.ROW_FRONT, 1, 1, 40)
	if _check(forged_t != null, "fixture: an enemy under an order, forged spell"):
		forged_t.state.current_intent = "HEAL"
		# Drive the REAL fold (add to deck -> upgrade -> read back) rather than
		# hand-merging the UPGRADES delta. _apply_plus_upgrade merges tail-effect
		# fields through an ALLOW-LIST, so a hand-merge would happily produce a
		# number the shipped game cannot: `order_bonus` was missing from that list
		# and the forged card promised 9 while dealing 6. Going through the real
		# path means any future unregistered field fails here automatically.
		RunState.add_card("counterorders")
		var idx: int = RunState.deck.size() - 1
		RunState.upgrade_card(idx, "plus")
		var forged: Dictionary = RunState.get_upgraded_card_data(idx)
		_check(bool(forged.get("is_upgraded", false)),
			"the real fold produced an upgraded card")
		var hp2: int = int(forged_t.current_hp)
		await combat._resolve_custom_spell("counterorders", forged_t, 1, forged)
		_check(hp2 - forged_t.current_hp == 9,
			"the forge raises the ORDER bonus 3 -> 6, so 3 + 6 = 9 (%d -> %d)"
				% [hp2, forged_t.current_hp])

	# ── THE ON-ENTER ─────────────────────────────────────────────────────────
	_clear_board(combat)
	var ob_foe = _put(combat, true, combat.ROW_FRONT, 2, 1, 40)
	var ob = _put(combat, false, combat.ROW_FRONT, 2, 3, 2)
	if _check(ob_foe != null and ob != null, "fixture: Order-Breaker opposite an order"):
		ob_foe.state.current_intent = "SUMMON"
		ob.card_data["on_enter"] = {"type": "strike_the_order", "value": 4}
		var hp3: int = int(ob_foe.current_hp)
		KeywordEffects.dispatch_on_enter(ob, 2, false, combat)
		_check(hp3 - ob_foe.current_hp == 4,
			"arriving opposite an order deals its printed 4 (%d -> %d)"
				% [hp3, ob_foe.current_hp])

	# The condition must be REAL, not decorative: a plain attacker takes nothing.
	_clear_board(combat)
	var ob_foe2 = _put(combat, true, combat.ROW_FRONT, 2, 1, 40)
	var ob2 = _put(combat, false, combat.ROW_FRONT, 2, 3, 2)
	if _check(ob_foe2 != null and ob2 != null, "fixture: Order-Breaker opposite plain ATK"):
		ob_foe2.state.current_intent = "ATK"
		ob2.card_data["on_enter"] = {"type": "strike_the_order", "value": 4}
		var hp4: int = int(ob_foe2.current_hp)
		KeywordEffects.dispatch_on_enter(ob2, 2, false, combat)
		_check(ob_foe2.current_hp == hp4,
			"arriving opposite a plain attacker deals NOTHING (%d -> %d)"
				% [hp4, ob_foe2.current_hp])

	# An empty column must be a quiet no-op, not a crash.
	_clear_board(combat)
	var ob3 = _put(combat, false, combat.ROW_FRONT, 3, 3, 2)
	if _check(ob3 != null, "fixture: Order-Breaker opposite an empty column"):
		ob3.card_data["on_enter"] = {"type": "strike_the_order", "value": 4}
		KeywordEffects.dispatch_on_enter(ob3, 3, false, combat)
		_check(true, "an empty column is a no-op, not a crash")

	# ── THE KEYSTONE — the post-death intent read ────────────────────────────
	# THE point of this file. A REAL clash, killing an enemy that wears an order,
	# with The Interpreter standing. If `current_intent` were cleared or the node
	# freed before `_apply_combat_strike_riders`, the promotion would silently
	# never happen and the rare would be a blank card.
	_clear_board(combat)
	var victim = _put(combat, true, combat.ROW_FRONT, 0, 1, 2)
	var killer = _put(combat, false, combat.ROW_FRONT, 0, 5, 9)
	var interpreter = _put(combat, false, combat.ROW_BACK, 3, 2, 4)
	if _check(victim != null and killer != null and interpreter != null,
			"fixture: a 5/9 into a 1/2 under orders, Interpreter standing"):
		interpreter.card_data["passive"] = "read_the_orders"
		victim.state.current_intent = "RALLY"
		var atk_before: int = killer.effective_atk()
		var hp_before: int = int(killer.current_hp)
		await combat._creature_attacks_creature(killer, victim, 0, false)
		_check(victim.current_hp <= 0, "the order-wearing enemy died")
		_check(killer.effective_atk() == atk_before + 1,
			"THE POST-DEATH READ HOLDS: the killer was promoted +1 ATK (%d -> %d)"
				% [atk_before, killer.effective_atk()])
		_check(killer.current_hp == hp_before + 1,
			"...and +1 HP (%d -> %d)" % [hp_before, killer.current_hp])
		# Permanent, not a this-round buff — the card says the promotion sticks.
		_check(int(killer.persistent_atk_buff) >= 1,
			"the promotion rode persistent_atk_buff, so it survives round end")

	# Killing a PLAIN attacker must NOT promote, or the condition is decorative.
	_clear_board(combat)
	var victim2 = _put(combat, true, combat.ROW_FRONT, 0, 1, 2)
	var killer2 = _put(combat, false, combat.ROW_FRONT, 0, 5, 9)
	var interp2 = _put(combat, false, combat.ROW_BACK, 3, 2, 4)
	if _check(victim2 != null and killer2 != null and interp2 != null,
			"fixture: same clash, victim on plain ATK"):
		interp2.card_data["passive"] = "read_the_orders"
		victim2.state.current_intent = "ATK"
		var atk_before2: int = killer2.effective_atk()
		await combat._creature_attacks_creature(killer2, victim2, 0, false)
		_check(killer2.effective_atk() == atk_before2,
			"killing a plain attacker promotes NOTHING (%d)" % killer2.effective_atk())

	# No keystone on the board — no promotion, however committed the victim was.
	_clear_board(combat)
	var victim3 = _put(combat, true, combat.ROW_FRONT, 0, 1, 2)
	var killer3 = _put(combat, false, combat.ROW_FRONT, 0, 5, 9)
	if _check(victim3 != null and killer3 != null,
			"fixture: same clash, no Interpreter standing"):
		victim3.state.current_intent = "CHARGE"
		var atk_before3: int = killer3.effective_atk()
		await combat._creature_attacks_creature(killer3, victim3, 0, false)
		_check(killer3.effective_atk() == atk_before3,
			"without the keystone there is no promotion (%d)" % killer3.effective_atk())

	print("[counterorders-live] %s"
		% ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return ""


## Fixture teardown, not a game event — bypasses _die() on purpose so an
## on_death chain from one block cannot contaminate the next block's totals.
func _clear_board(combat) -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null


func _put(combat, is_enemy: bool, row: int, lane: int, atk: int, hp: int,
		kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
