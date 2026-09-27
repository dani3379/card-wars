extends SceneTree
## _probe_runaway.gd — PASS 24 of docs/BUG_SWEEP_METHOD_20260829.md (class C24).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_runaway.gd
##
## EMERGENT INTERACTION — played, not inspected, with an OBJECTIVE oracle.
##
## The method doc lists design, balance and emergent interaction as out of reach,
## and the last four passes finding nothing is the evidence: every remaining static
## question has been asked. But "emergent" does not have to mean "a matter of taste".
## Two things a card game can do wrong are bugs by any standard, need no balance
## judgement at all, and are reachable only by actually playing:
##
##   1. RUNAWAY VALUES. If some sequence of legal plays drives a stat without
##      bound — a creature past any sane ATK, Command climbing forever, a hand over
##      its own cap — that is an unbounded combo, and it is a bug whatever the
##      design intent. Nobody authored "this creature reaches 400 attack".
##   2. NON-TERMINATION. A match that cannot end is a softlock. `_probe_net_soak`
##      drives matches but stops at a turn cap and never asks whether the fight was
##      actually going to finish.
##
## What makes this different from every earlier soak is DECK DIVERSITY. The soak and
## the pairwise pass both hand every player the same twenty cards, so the only
## interactions they can ever produce are the ones in that fixed list. This rolls
## RANDOM legal decks from the whole skirmish pool, so cards that have never shared
## a board here get to meet — which is the entire point of hunting emergent faults.
##
## The oracle is deliberately loose. These ceilings are not balance targets; they
## are absurdity floors, set far above anything the pool can legitimately reach, so
## that crossing one means a rule is compounding rather than a card being strong.

## Absurdity floors — NOT balance targets. A legitimate board does not come close.
const MAX_SANE_ATK := 60
const MAX_SANE_HP := 80
const MAX_SANE_MANA := 25
const MAX_SANE_HAND := 12
const MAX_SANE_BODIES := 8      # 4 lanes x 2 rows, per side, by construction

const MATCHES := 10
const ROUND_CAP := 40           # a fight still going here is not going to end

var SS: Node
var NM: Node
var US: Node
var combat: Node
## LOADED AT RUNTIME, NEVER NAMED AT PARSE TIME. Writing `Card2D.defer_deaths`
## in a `--script` probe drags Card2D.gd into the pre-autoload compile, so
## card_2d.tscn instantiates SCRIPTLESS and the whole match runs as bare panels
## while the audit reports green — a false pass `_probe_invariants` shipped once.
var CardCls

var _rng := RandomNumberGenerator.new()
var _started := false
var _done := false
var _fails := 0
var _findings: Array = []
var _peak := {}
var _matches_run := 0
var _unique_cards := {}


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _note(what: String) -> void:
	if not (what in _findings):
		_findings.append(what)


func _bump(k: String, v: int) -> void:
	if v > int(_peak.get(k, -99999)):
		_peak[k] = v


## Watch the board for anything compounding out of control.
func _audit(tag: String) -> void:
	if not is_instance_valid(combat):
		return
	_bump("player_mana", int(combat.player_mana))
	_bump("player_max_mana", int(combat.player_max_mana))
	_bump("hand_size", combat._hand.size())
	# THE DECLARED CONTRACT, not an absurdity ceiling. `_start_round` sets
	# `player_mana = player_max_mana + banked` where banked is capped at
	# MAX_BANKED_MANA, so Command at the top of a turn can never legitimately
	# exceed that sum. This replaced a loose "> 25 is absurd" check which a real
	# mutant walked straight past: forcing Command to accumulate every round only
	# reached 18 before the match ended, so the gate stayed green while the
	# resource was genuinely unbounded. A contract-derived bound catches the
	# compounding on the FIRST round it happens, whatever the absolute number.
	var mana_ceiling: int = int(combat.player_max_mana) + int(combat.MAX_BANKED_MANA)
	if int(combat.player_mana) > mana_ceiling:
		_note("Command %d exceeds its own contract (max %d + banked %d) (%s)"
			% [int(combat.player_mana), int(combat.player_max_mana),
				int(combat.MAX_BANKED_MANA), tag])
	if int(combat.player_mana) > MAX_SANE_MANA:
		_note("Command ran away: %d (%s)" % [int(combat.player_mana), tag])
	if combat._hand.size() > MAX_SANE_HAND:
		_note("hand exceeded its cap: %d (%s)" % [combat._hand.size(), tag])
	for is_enemy in [false, true]:
		var count := 0
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(arr.size()):
				var c = arr[lane]
				if c == null or not is_instance_valid(c):
					continue
				count += 1
				var atk := int(c.effective_atk())
				var hp := int(c.current_hp)
				_bump("creature_atk", atk)
				_bump("creature_hp", hp)
				if atk > MAX_SANE_ATK:
					_note("%s reached %d ATK (%s)" % [
						String(c.card_data.get("id", "?")), atk, tag])
				if hp > MAX_SANE_HP:
					_note("%s reached %d HP (%s)" % [
						String(c.card_data.get("id", "?")), hp, tag])
				# A CORPSE AT OR BELOW ZERO IS LEGITIMATE MID-CLASH. `defer_deaths`
				# deliberately holds dead bodies standing so a simultaneous trade
				# resolves both ways before anything is swept — so sampling inside
				# that window and calling it a bug reported nine healthy matches as
				# broken. `_probe_invariants` guards the same way; this is the only
				# correct reading of a sub-zero HP.
				if hp < 0 and not bool(CardCls.defer_deaths):
					_note("%s stands at NEGATIVE hp %d OUTSIDE the deferred-death "
						% [String(c.card_data.get("id", "?")), hp]
						+ "window (%s)" % tag)
		_bump("bodies", count)
		if count > MAX_SANE_BODIES:
			_note("%d bodies on one side — the board has more slots than it has (%s)"
				% [count, tag])


## A random legal deck from the WHOLE pool, which is the point of this pass.
func _random_deck(pool: Array) -> Array:
	var out: Array = []
	for _i in 20:
		var id := String(pool[_rng.randi() % pool.size()])
		out.append(id)
		_unique_cards[id] = true
	return out


func _boot(seed_val: int, style: int, pool: Array) -> bool:
	SS.reset()
	for id in _random_deck(pool):
		SS.add_card_to(0, id)
	for id in _random_deck(pool):
		SS.add_card_to(1, id)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = seed_val
	SS.vs_bot = true
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.battle_style = style
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
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


func _first_empty_slot() -> Control:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			if arr[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


## Play everything affordable — creatures AND spells. A policy that only ever seats
## creatures can never find a spell-driven combo, which is most of them.
## Poll until the hand has finished ARRIVING, not just until input is accepted.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. A driver that starts there is playing a hand the
## game has not finished dealing it: on round 1 that is ONE card of five, and at
## Command 1 a single 2-drop means the whole turn plays nothing.
##
## Rounds 2+ hide it, because the hand is PERSISTENT and carries unplayed stock
## forward — so the fault is worst exactly where round-1 measurements live. It
## cost `_probe_deploy_curve` a published number before it was found; see
## CLAUDE.md's settle-until-stable note.
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


func _play_turn(tag: String) -> void:
	for _pass in 10:
		if not is_instance_valid(combat):
			return
		var acted := false
		for card in combat._hand.duplicate():
			if card == null or not is_instance_valid(card):
				continue
			if combat._effective_cost(card) > combat.player_mana:
				continue
			if card.is_creature():
				var slot := _first_empty_slot()
				if slot == null:
					continue
				card.global_position = slot.get_global_rect().get_center() \
					- card.size * 0.5
				combat._on_card_played(card)
			else:
				combat._on_card_played(card)
				await create_timer(0.05).timeout
				# A targeted spell parks in targeting mode; resolve or cancel it so
				# the turn can continue rather than stalling behind a live prompt.
				if is_instance_valid(combat) and combat._targeting_spell != null:
					var foes = combat._all_enemy_creatures()
					if not foes.is_empty():
						combat._try_resolve_target(
							combat._card_center(foes[0]))
					else:
						combat._cancel_targeting()
			await create_timer(0.05).timeout
			acted = true
			_audit(tag)
			break
		if not acted:
			break
	if is_instance_valid(combat):
		combat._net_on_done_placing()
		await create_timer(0.35).timeout
	_audit(tag)


func _run() -> void:
	print("[runaway] PASS 24 — random decks, played out, watching for compounding\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[runaway] FATAL: autoloads missing"); _done = true; quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
	_rng.seed = 771144
	CardCls = load("res://scripts/Card2D.gd")

	var pool: Array = SS.skirmish_legal_pool()
	_check(pool.size() > 20, "the skirmish pool has real breadth (%d cards)" % pool.size())

	var unfinished := 0
	for m in MATCHES:
		var style: int = m % 2
		var tag := "m%d style%d" % [m, style]
		if not await _boot(90000 + m * 613, style, pool):
			_note("failed to boot (%s)" % tag)
			continue
		_matches_run += 1
		var stalls := 0
		while is_instance_valid(combat) and not combat._net_match_over \
				and int(combat.round_number) < ROUND_CAP:
			var mine: bool
			if style == NM.STYLE_SEALED:
				mine = combat._sorcery_active == NM.local_player_index \
					or (combat._sorcery_active < 0 and not combat._sealed_await_foe \
						and combat.phase == combat.Phase.PLAYER_TURN)
			else:
				mine = combat._net_active_index == NM.local_player_index \
					and combat.phase == combat.Phase.PLAYER_TURN
			if not mine:
				stalls += 1
				if stalls > 400:
					_note("turn never came back (%s, round %d) — possible softlock"
						% [tag, int(combat.round_number) if is_instance_valid(combat) else -1])
					break
				await create_timer(0.05).timeout
				continue
			stalls = 0
			await _settle_hand()
			await _play_turn(tag)
		if is_instance_valid(combat) and not combat._net_match_over \
				and int(combat.round_number) >= ROUND_CAP:
			unfinished += 1
		if is_instance_valid(combat):
			combat.queue_free()
		await create_timer(0.3).timeout

	print("\n[runaway] %d matches played, %d distinct cards seen across the decks"
		% [_matches_run, _unique_cards.size()])
	print("[runaway] peak values observed:")
	var ks: Array = _peak.keys()
	ks.sort()
	for k in ks:
		print("        %-18s %d" % [k, int(_peak[k])])
	# VACUITY: a pass whose matches never put anything on the board proves nothing.
	_check(_matches_run > 0, "matches actually ran")
	_check(int(_peak.get("bodies", 0)) > 0, "creatures actually reached the board")
	_check(_unique_cards.size() > 25,
		"the random decks covered real card variety (%d distinct)"
			% _unique_cards.size())
	# NON-TERMINATION. A fight still going at the cap is not a slow fight.
	_check(unfinished == 0,
		"every match reached a verdict inside %d rounds (%d did not)"
			% [ROUND_CAP, unfinished])

	if _findings.is_empty():
		print("  PASS  nothing compounded out of control")
	else:
		for f in _findings:
			_fails += 1
			print("  FAIL  %s" % f)

	print("\n[runaway] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
