extends SceneTree
## _probe_pairwise.gd — PASS 16 of docs/BUG_SWEEP_METHOD_20260829.md (class C16).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_pairwise.gd
##
## COMBINATORIAL COVERAGE — testing the SPACE, not the axes.
##
## Every pass so far varies one thing at a time: the soak fixes a config and varies
## the seed, the relic-parity gate walks the relic pool with everything else held
## still. That finds single-feature defects and is blind to the ones that only exist
## where two features MEET — Sealed Orders plus a hand-size relic, a Best-of-3 plus
## the going-second Coin, a board relic plus the practice bot's spell path. Those
## interactions are exactly where a card game breaks, and nothing here has looked.
##
## The full cross product of the parameters below is 280 matches, which is too many
## to run and mostly redundant. Empirically most interaction faults involve just TWO
## factors, so this builds an ALL-PAIRS covering array: a small set of combinations
## in which every pair of values from every pair of parameters appears at least once.
## That takes 280 down to a few dozen while keeping the property that matters.
##
## The generator is a plain greedy one (pick the candidate covering the most
## uncovered pairs) — not minimal, but small, deterministic, and easy to audit. Its
## coverage is VERIFIED before the matches run: if the array does not actually cover
## every pair, the pass says so instead of quietly testing less than it claims.

var SS: Node
var NM: Node
var US: Node
var combat: Node
var CardCls          # runtime-loaded; see _probe_invariants for why never at parse time

var _rng := RandomNumberGenerator.new()
var _started := false
var _done := false
var _fails := 0
var _violations: Dictionary = {}

## Parameter name -> values. Keep each axis small; pairwise cost grows with the
## product of the two LARGEST axes, not with the number of axes.
var PARAMS := {
	"style":   [0, 1],                       # ALTERNATING / SEALED
	"first":   [0, 1],                       # who the toss gave the opener to
	"best_of": [1, 3],
	"relic":   ["", "ember_crown", "cavalry_sigil", "snecko_eye",
				"marathoners_sash", "tome_of_many", "gravewardens_pact"],
	"potion":  ["", "healing", "inferno_vial", "mana_surge", "doomsday_draught"],
}


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## Every (param_a=value_a, param_b=value_b) pair that a covering array must contain.
func _all_pairs() -> Dictionary:
	var keys: Array = PARAMS.keys()
	var pairs := {}
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			for va in PARAMS[keys[i]]:
				for vb in PARAMS[keys[j]]:
					pairs["%s=%s|%s=%s" % [keys[i], str(va), keys[j], str(vb)]] = false
	return pairs


func _pairs_of(combo: Dictionary) -> Array:
	var keys: Array = PARAMS.keys()
	var out: Array = []
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			out.append("%s=%s|%s=%s" % [
				keys[i], str(combo[keys[i]]), keys[j], str(combo[keys[j]])])
	return out


## Greedy all-pairs: repeatedly take the candidate that covers the most still-
## uncovered pairs. Deterministic given the seed, so a failure is reproducible.
func _covering_array() -> Array:
	var pairs := _all_pairs()
	var keys: Array = PARAMS.keys()
	var chosen: Array = []
	var guard := 0
	while guard < 400:
		guard += 1
		var uncovered := 0
		for k in pairs:
			if not pairs[k]:
				uncovered += 1
		if uncovered == 0:
			break
		var best: Dictionary = {}
		var best_gain := -1
		# Sample candidates rather than enumerating all 280 — cheap and sufficient.
		for _try in 240:
			var cand := {}
			for k in keys:
				var vals: Array = PARAMS[k]
				cand[k] = vals[_rng.randi() % vals.size()]
			var gain := 0
			for p in _pairs_of(cand):
				if pairs.has(p) and not pairs[p]:
					gain += 1
			if gain > best_gain:
				best_gain = gain
				best = cand
		if best_gain <= 0:
			break
		for p in _pairs_of(best):
			pairs[p] = true
		chosen.append(best)
	return chosen


func _boot(combo: Dictionary, seed_val: int) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin",
			"strike", "brute", "goblin", "brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = seed_val
	SS.vs_bot = true
	SS.best_of = int(combo["best_of"])
	var slot = SS.get_slot(0)
	if slot != null:
		slot.relics = [] if String(combo["relic"]) == "" else [String(combo["relic"])]
		slot.potions = [] if String(combo["potion"]) == "" else [String(combo["potion"])]
	NM.is_host = true
	NM.vs_bot = true
	NM.best_of = int(combo["best_of"])
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.battle_style = int(combo["style"])
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = int(combo["first"])
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	var last := -1
	var stable := 0
	for _i in 30:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat):
			return false
		var n: int = combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 3:
			break
	return is_instance_valid(combat)


## The same always-true properties Pass 14 watches, sampled at each turn boundary.
func _audit(tag: String) -> void:
	if not is_instance_valid(combat):
		return
	var seen := {}
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c == null:
					continue
				if not is_instance_valid(c):
					_violations["freed node in a slot (%s)" % tag] = true
					continue
				if seen.has(c):
					_violations["one body in two slots (%s)" % tag] = true
				seen[c] = true
	for eid in NM.entities.keys():
		var n = NM.entities[eid]
		if n == null or not is_instance_valid(n):
			_violations["freed node in the entity registry (%s)" % tag] = true
	if int(combat.player_mana) < 0:
		_violations["negative Command (%s)" % tag] = true
	if combat._hand.size() > 10:
		_violations["hand over cap (%s)" % tag] = true


func _first_empty_slot() -> Control:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			if arr[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


## Poll until the hand has finished ARRIVING, not just until the turn is ours.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. CombatNet routes its round starts through that
## same function, so a skirmish driver inherits the stagger exactly as a solo
## one does. See CLAUDE.md's settle-until-stable note; it cost
## `_probe_deploy_curve` a published number before it was found.
##
## Stability polling, NOT a computed deal window: draw_count is the ramp plus
## four relics plus two mutators, and restating that arithmetic in a probe is
## the duplicate-rule pathology. Bounded, because an unbounded `while await`
## spins to the harness timeout and reports NOTHING at all.
func _settle_hand() -> void:
	const SETTLE_TICK := 0.03    # poll interval
	const STABLE_TICKS := 5      # 0.15s unchanged, a 1.9x margin on the 0.08s gap
	const SETTLE_BUDGET := 40    # ~1.2s ceiling
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _play_turn() -> void:
	var belt: Array = combat._ctx_potions()
	if not belt.is_empty():
		combat._use_combat_potion(0)
		await create_timer(0.08).timeout
		if is_instance_valid(combat) and combat._targeting_potion_idx >= 0:
			combat._cancel_potion_targeting()
	for _pass in 8:
		if not is_instance_valid(combat):
			return
		var played := false
		for card in combat._hand.duplicate():
			if card == null or not is_instance_valid(card) or not card.is_creature():
				continue
			if combat._effective_cost(card) > combat.player_mana:
				continue
			var slot := _first_empty_slot()
			if slot == null:
				break
			card.global_position = slot.get_global_rect().get_center() - card.size * 0.5
			combat._on_card_played(card)
			await create_timer(0.05).timeout
			played = true
			break
		if not played:
			break
	if is_instance_valid(combat):
		combat._net_on_done_placing()
		await create_timer(0.3).timeout


func _run() -> void:
	print("[pairwise] PASS 16 — every pair of settings, at least once\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[pairwise] FATAL: autoloads missing"); _done = true; quit(1); return
	CardCls = load("res://scripts/Card2D.gd")
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
	_rng.seed = 20260829

	var full := 1
	for k in PARAMS:
		full *= (PARAMS[k] as Array).size()
	var array := _covering_array()
	print("[pairwise] full cross product: %d combinations" % full)
	print("[pairwise] covering array:     %d combinations" % array.size())

	# VERIFY THE ARRAY BEFORE TRUSTING IT. A generator that silently misses pairs
	# would make this pass claim coverage it does not have.
	var pairs := _all_pairs()
	for combo in array:
		for p in _pairs_of(combo):
			if pairs.has(p):
				pairs[p] = true
	var missing := 0
	for k in pairs:
		if not pairs[k]:
			missing += 1
	_check(missing == 0, "the covering array really covers every pair (%d missing of %d)"
		% [missing, pairs.size()])
	_check(array.size() < full / 3, "and does it in far fewer runs than the cross product")

	var ran := 0
	for i in array.size():
		var combo: Dictionary = array[i]
		var tag := "style=%d first=%d bo=%d relic=%s potion=%s" % [
			int(combo["style"]), int(combo["first"]), int(combo["best_of"]),
			String(combo["relic"]) if String(combo["relic"]) != "" else "-",
			String(combo["potion"]) if String(combo["potion"]) != "" else "-"]
		if not await _boot(combo, 30011 + i * 7919):
			_violations["failed to boot (%s)" % tag] = true
			continue
		ran += 1
		var turns := 0
		var stalls := 0
		while turns < 6 and is_instance_valid(combat) and not combat._net_match_over:
			var mine: bool
			if int(combo["style"]) == NM.STYLE_SEALED:
				mine = combat._sorcery_active == NM.local_player_index \
					or (combat._sorcery_active < 0 and not combat._sealed_await_foe \
						and combat.phase == combat.Phase.PLAYER_TURN)
			else:
				mine = combat._net_active_index == NM.local_player_index \
					and combat.phase == combat.Phase.PLAYER_TURN
			if not mine:
				stalls += 1
				if stalls > 300:
					break
				await create_timer(0.05).timeout
				continue
			stalls = 0
			turns += 1
			await _settle_hand()
			await _play_turn()
			_audit(tag)
		if turns < 1:
			_violations["never got a turn (%s)" % tag] = true
		if is_instance_valid(combat):
			combat.queue_free()
		await create_timer(0.3).timeout

	print("\n[pairwise] %d of %d combinations played" % [ran, array.size()])
	_check(ran == array.size(), "every combination booted and ran")
	if _violations.is_empty():
		print("  PASS  no combination produced an invariant violation")
	else:
		for v in _violations:
			_fails += 1
			print("  FAIL  %s" % v)

	await _relic_style_matrix()

	print("\n[pairwise] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)


## PHASE B — the (relic × style) CELL MATRIX, and the only oracle in this file
## that is stronger than "nothing crashed".
##
## Phase A proves no combination breaks. It cannot prove a combination WORKS: a
## relic that silently does nothing under Sealed Orders passes every structural
## check ever written, because a relic doing nothing is a perfectly valid board.
## That is the interaction defect this class exists to find, and it needs a
## comparison, not an assertion.
##
## So measure the opening state a relic is supposed to move — max Command and the
## opening hand — once per (relic, style) cell, and require the relic's DELTA FROM
## THE NO-RELIC BASELINE to be the same in both styles. Nothing is hardcoded about
## what any relic ought to do; the relation is that the two styles must agree with
## each other, which stays true through any future retune.
func _relic_style_matrix() -> void:
	print("\n[pairwise] --- phase B: does each relic still work in BOTH styles? ---")
	var cells := {}
	var relics: Array = PARAMS["relic"]
	for style in [0, 1]:
		for r in relics:
			var combo := {"style": style, "first": 0, "best_of": 1,
				"relic": r, "potion": ""}
			if not await _boot(combo, 606060 + style * 31):
				_check(false, "cell (relic=%s style=%d) booted" % [
					r if r != "" else "-", style])
				continue
			cells["%s|%d" % [r, style]] = {
				"mana": int(combat.player_max_mana),
				"hand": int(combat._hand.size()),
			}
			combat.queue_free()
			await create_timer(0.25).timeout

	var base0 = cells.get("|0")
	var base1 = cells.get("|1")
	if base0 == null or base1 == null:
		_check(false, "the no-relic baseline was measured in both styles")
		return
	# VACUITY GUARD. If no relic moved either number in either style, the relation
	# below is trivially satisfied and proves nothing — which is exactly how a
	# symmetry test lies. Require the matrix to have observed at least one real
	# effect before believing its agreement.
	var moved := 0
	var disagreed := 0
	for r in relics:
		if String(r) == "":
			continue
		var c0 = cells.get("%s|0" % r)
		var c1 = cells.get("%s|1" % r)
		if c0 == null or c1 == null:
			continue
		var d0_mana: int = int(c0["mana"]) - int(base0["mana"])
		var d1_mana: int = int(c1["mana"]) - int(base1["mana"])
		var d0_hand: int = int(c0["hand"]) - int(base0["hand"])
		var d1_hand: int = int(c1["hand"]) - int(base1["hand"])
		if d0_mana != 0 or d1_mana != 0 or d0_hand != 0 or d1_hand != 0:
			moved += 1
		var agree := d0_mana == d1_mana and d0_hand == d1_hand
		if not agree:
			disagreed += 1
			print("        %-20s ALTERNATING %+d Cmd %+d hand   SEALED %+d Cmd %+d hand"
				% [r, d0_mana, d0_hand, d1_mana, d1_hand])
		_check(agree, "%s moves the opening the same in both battle styles" % r)
	_check(moved > 0, "the matrix observed a real relic effect (%d relics moved the "
		% moved + "opening) — otherwise the agreement above is vacuous")
	if disagreed == 0:
		print("        every relic's opening delta matched across both styles")
