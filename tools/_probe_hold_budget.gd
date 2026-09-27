extends SceneTree

## _probe_hold_budget.gd — THE HOLD'S HAND IS SPENT BY EVERY SOURCE (2026-09-16).
##
## `Combat._enemy_arrivals_this_round` is the hold's per-round budget, and its own
## header has always claimed to cover bodies "across every source". It did not:
## the counter was incremented at exactly ONE site, the reinforcement drip inside
## `_enemy_place_creatures`, while bodies ALSO arrive from the ENCOUNTER PASSIVE
## via `_summon_enemy_token{,_with_keyword}` / `_place_enemy_card`. So a summoning
## hold deployed its signature AND its full drip every round — survivable against a
## flat 3 Command, a flood against the ramp. Fixed by `Combat._spend_hold_hand()`
## plus the `_hold_rule_deploying` window; this is the gate that keeps it fixed.
## See docs/ECONOMY_REDESIGN_20260916.md §3b.
##
## WHY A GATE AND NOT A ONE-OFF MEASUREMENT: the defect's whole shape is "a new
## arrival path forgot to pay". That is invisible to every other probe here —
## `_probe_encwin` measures win rate (and CANNOT see this: §3b's own headline
## encounter moves 20% → 20%, below), `_probe_deploy_curve` averages plain
## combats, and nothing at all reads the counter. The next passive that summons
## through a third funnel should fail a gate, not wait for someone to notice a
## fight feeling wrong.
##
## THE ORACLE DOES NOT READ THE COUNTER, and that is the point. Asserting
## `_enemy_arrivals_this_round <= cap` would be satisfied perfectly by a counter
## that is never incremented — the exact bug. So arrivals are counted
## INDEPENDENTLY, by diffing the set of live enemy Card2D instance ids each round:
## an id never seen before is an arrival, and a freed body never comes back under
## its old id. The budget is then the thing under test rather than the witness.
##
## ROUND 1 IS EXEMPT, deliberately — the opening muster is the FORMATION, not
## reinforcement, and `_deal_opening_muster` returns before the budget is ever
## consulted. Counting it would make every fight fail for doing the right thing.
##
## VACUITY IS CHECKED IN BOTH DIRECTIONS, because this assertion is an UPPER
## bound and upper bounds are the easiest thing in testing to pass by accident:
##   * the passive must actually have summoned (a fight where it never fired
##     proves nothing about whether summons pay), and
##   * the allowance must actually BIND somewhere (a round running level with it).
##     If the hold never approaches its ceiling the bound is never under load, and
##     a counter that is never incremented sails through.
## The board's 8 slots are a SECOND ceiling and a real confound: once the enemy
## side is full, a summon fizzles and arrivals fall to zero for reasons that have
## nothing to do with the budget — a hold overspending wildly then reads as a hold
## within its means. `_thin_enemy_board` clears the enemy line every window to hold
## that confound still. It is not a play policy, it is the experiment; with only
## the front row cleared, the original defect escaped to ONE failing check.
##
## KNOWN SLACK, stated so nobody reads this gate as tighter than it is: the
## allowance adds HOLD_ARRIVALS_SURGE_BONUS for EVERY window, because the spike
## condition is decided inside `_enemy_place_creatures` out of state this probe
## would have to restate — and restating a rule to test it is how two copies of it
## drift apart. So the bound runs ~1 body/round generous, and the printed `slack`
## column is how close a fight actually ran to it. Measured against the original
## defect that is still decisive (5 failing checks, margin widening with the
## fight) but it is a flood detector, not a ledger: a leak of well under one body
## per round would hide inside the surge term.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_hold_budget.gd
## Flags (after a bare `--`):
##   --rounds=N   rounds driven per fight (default 10)
##   --verbose    print the per-round arrival table for every fight

# Encounters whose PASSIVE puts bodies on the board — the population this gate
# exists for. Read from EncounterDB at runtime rather than hardcoded counts, so
# a retuned passive does not silently make the gate vacuous.
const SUMMONING_ENCOUNTERS := [
	"bandit_camp", "haunted_crypt", "necromancer_tower",
	"the_bellringer", "the_crone", "the_black_tide",
]
const DRIVE_HERO := "stalwart"
const TICK := 0.05
const TURN_WAIT_TICKS := 160
# Hand-settle poll — see _settle_hand.
const SETTLE_TICK := 0.03
const STABLE_TICKS := 5
const SETTLE_BUDGET := 40

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node

var combat: Node
var _rounds_to_drive: int = 10
var _verbose: bool = false
var _fails: Array[String] = []
var _checks: int = 0
# Fight-local: instance id -> true for every enemy body ever seen this fight.
var _seen_enemy: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="): _rounds_to_drive = int(arg.substr(9))
		elif arg == "--verbose": _verbose = true

	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if RS == null or EDB == null:
		printerr("[holdbudget] FATAL: autoloads missing")
		quit(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
		US.first_battle_tutorial_complete = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()

	print("[holdbudget] driving %d rounds per fight over %d summoning encounters"
		% [_rounds_to_drive, SUMMONING_ENCOUNTERS.size()])

	var total_summon_rounds := 0
	var total_binding_rounds := 0

	for enc_id in SUMMONING_ENCOUNTERS:
		var enc: Dictionary = EDB.get_encounter(enc_id)
		if enc.is_empty():
			_fail("%s: not in EncounterDB (renamed? then fix this list, do not delete it)" % enc_id)
			continue
		var res: Dictionary = await _fight(enc_id, enc)
		total_summon_rounds += int(res.get("summon_rounds", 0))
		total_binding_rounds += int(res.get("binding_rounds", 0))

	# ---- VACUITY, over the whole corpus ----
	_check(total_summon_rounds > 0,
		"the passives actually summoned somewhere (%d rounds saw an arrival)"
			% total_summon_rounds)
	_check(total_binding_rounds > 0,
		"the allowance actually BINDS somewhere (%d rounds ran level with it) — "
			% total_binding_rounds
			+ "without this the hold never approached its ceiling, the bound is "
			+ "never under load, and a counter that is never incremented passes")

	print("")
	if _fails.is_empty():
		print("[holdbudget] %d checks, all pass" % _checks)
		print("PROBE PASS: hold_budget")
		quit(0)
	else:
		for f in _fails:
			printerr("  FAIL  %s" % f)
		printerr("[holdbudget] %d checks, %d FAIL" % [_checks, _fails.size()])
		printerr("PROBE FAIL: hold_budget")
		quit(1)


## Drive one encounter and audit its per-round arrivals.
func _fight(enc_id: String, enc: Dictionary) -> Dictionary:
	var act: int = clampi(int(enc.get("act", 1)), 1, 3)
	seed(9311)
	RS.start_new_run(DRIVE_HERO, 0, 4242)
	RS.current_act_idx = act - 1
	RS.current_encounter_id = enc_id
	RS.current_node_type = String(enc.get("type", "combat"))

	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	_seen_enemy.clear()

	if not await _wait_turn():
		_fail("%s: never reached a player turn" % enc_id)
		await _teardown()
		return {}

	# Round 1's board is the opening MUSTER — the formation, not reinforcement.
	# Bank its ids as already-seen so they are not billed to the budget.
	#
	# WAIT FOR IT FIRST, and this cost the gate a wrong answer before it was found:
	# at a General or a keep the opening muster is dealt by `_run_opening_muster`
	# from BEHIND the initiative overlay, so it lands AFTER `phase` reads
	# PLAYER_TURN. Harvesting on the flag banked an empty board and then billed the
	# whole authored formation to round 2 — which is precisely the three fights that
	# looked like budget leaks (the_bellringer, the_crone, the_black_tide, all of
	# them initiative fights) while every plain combat passed. Same shape as
	# _settle_hand: a readiness flag answers about the FLAG, not the state it implies.
	await _settle_enemy_board()
	_harvest_enemy_ids()
	# A plain hold has already seated its formation by here, so measuring starts
	# with the very first window. An initiative fight has not (see the loop).
	var formation_done: bool = is_instance_valid(combat) \
		and not bool(combat._opening_muster_pending)

	var summon_rounds := 0
	var binding_rounds := 0
	var rows: Array[String] = []
	var driven := 0
	var total_arrived := 0
	var allowance := 0

	while driven < _rounds_to_drive and is_instance_valid(combat) \
			and combat.phase != combat.Phase.GAME_OVER:
		# End this round, then read what the hold committed for the next one.
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		if not await _wait_turn():
			break
		if not is_instance_valid(combat) or combat.phase == combat.Phase.GAME_OVER:
			break
		await _settle_hand()
		if not is_instance_valid(combat):
			break
		await _settle_enemy_board()
		if not is_instance_valid(combat):
			break
		driven += 1

		var r: int = int(combat.round_number)
		var arrived: int = _harvest_enemy_ids()

		# THE FORMATION IS EXEMPT WHEREVER IT LANDS, and at a General or a keep it
		# does NOT land before the first player turn. Headless auto-takes the field
		# (the house first-option convention), and TAKE THE FIELD is precisely the
		# line whose opening is dealt REACTIVELY — the hold answers what the player
		# set down, so the authored formation arrives at the END of round 1 and
		# reads, to a naive counter, as three or four reinforcements against a
		# round-1 hand of one.
		#
		# That is not a leak: `_enemy_arrivals_this_round`'s own header exempts the
		# opening muster ("it is the formation, not reinforcement"), and
		# `_enemy_place_creatures` returns on `_opening_muster_pending` BEFORE the
		# budget is consulted at all. So the exemption is keyed off the GAME's flag
		# rather than off "before the first turn" — the assumption that cost this
		# gate two wrong readings, which flagged every initiative fight and nothing
		# else. A plain combat consumes the muster during _ready, so it starts
		# measuring at the very first window exactly as before.
		if not formation_done:
			if not bool(combat._opening_muster_pending):
				formation_done = true
			rows.append("r%d formation=%d (exempt)" % [r, arrived])
			_thin_enemy_board()
			continue

		total_arrived += arrived
		# THE BOUND IS CUMULATIVE, NOT PER-ROUND, and that is the contract the fix
		# actually makes rather than the one it is tempting to assert.
		#
		# An END-of-round passive fires in _post_combat_sequence AFTER the drip has
		# already spent, so there is no "later this round" for the drip to yield in
		# — it yields NEXT round, by carrying the overspend as a debt. A per-round
		# ceiling therefore fails on a summon the design explicitly permits, which
		# is a gate testing a property nothing ever promised. (Measured: it flagged
		# every end-of-round summoner and nothing else.) Reserving budget ahead of
		# the passive would fix the per-round shape, but only by PREDICTING what the
		# passive will summon — restating a rule the encounter owns, which is how
		# two copies of one rule drift apart.
		#
		# What the hold must never do is FLOOD, and that is exactly the cumulative
		# statement: through any round, no more bodies than the sum of the hands it
		# has been dealt. The original defect — a passive paying nothing at all —
		# breaks it immediately and by a widening margin.
		#
		# Bodies seen at the top of round r were committed during round r-1, under
		# THAT round's budget, so the allowance sums to r-1. SURGE is included for
		# every round: the spike condition is decided inside _enemy_place_creatures
		# out of state this probe would have to restate, and a generous-but-real
		# bound still catches a defect that doubles the rate.
		var window_round: int = r - 1
		allowance += int(combat.hold_arrivals_for_round(window_round)) \
			+ int(combat.HOLD_ARRIVALS_SURGE_BONUS)
		if arrived > 0:
			summon_rounds += 1
		if total_arrived >= allowance:
			binding_rounds += 1
		rows.append("r%d arrived=%d (run %d/%d, slack %d)"
			% [r, arrived, total_arrived, allowance, allowance - total_arrived])
		_check(total_arrived <= allowance,
			"%s through r%d: hold committed %d bodies against a %d cumulative allowance"
				% [enc_id, r, total_arrived, allowance])

		# Clear the enemy line, or the 8-slot board becomes the binding constraint
		# instead of the budget and the audit goes quiet: a full board fizzles every
		# summon, arrivals fall to zero, and a hold that is massively overspending
		# reads as a hold within its means. This is NOT a play policy — it is the
		# experiment holding the confound still, and it is what gives the mutant
		# room to diverge. Measured: front-row-only thinning let the original defect
		# escape to a single failure by ONE body at round 7.
		_thin_enemy_board()

	if _verbose:
		print("  [%s] %s" % [enc_id, ", ".join(rows)])
	await _teardown()
	return {"summon_rounds": summon_rounds, "binding_rounds": binding_rounds}


## New enemy bodies since the last call. Identity, not a count: a board that
## gained two and lost two has had two ARRIVALS, and a size diff reads zero.
func _harvest_enemy_ids() -> int:
	if not is_instance_valid(combat):
		return 0
	var fresh := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(true, row):
			if c == null or not is_instance_valid(c):
				continue
			var iid: int = c.get_instance_id()
			if not _seen_enemy.has(iid):
				_seen_enemy[iid] = true
				fresh += 1
	return fresh


## Clear the enemy line so the next round's arrivals always have somewhere to land.
func _thin_enemy_board() -> void:
	if not is_instance_valid(combat):
		return
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr: Array = combat._row_array(true, row)
		for lane in range(arr.size()):
			var c = arr[lane]
			if c == null or not is_instance_valid(c):
				continue
			arr[lane] = null
			c.queue_free()


## Poll until the scene hands over a player turn. `round_number >= 1` is the same
## term every driver here carries: Phase.PLAYER_TURN is enum 0, which is also the
## default, so a half-built scene reports ready on the first poll.
func _wait_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN and int(combat.round_number) >= 1:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


## Poll until the hand has finished ARRIVING. Combat._start_round staggers the
## deal onto `create_timer(0.08 * i)` timers with no headless or reduce_motion
## branch, while `phase` already reads PLAYER_TURN — so a driver that proceeds on
## the flag alone is reading a board mid-deal. This probe does not play cards, but
## it does sample the enemy line on that same frame, and the passive summon it is
## auditing fires from `_start_round` too. See CLAUDE.md's settle-until-stable note.
func _settle_hand() -> void:
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


## Poll until the OPENING MUSTER has finished seating the formation.
##
## Two terms, and both are needed. `_opening_muster_pending` is the game's own
## flag and goes false inside `_enemy_place_creatures`, which is a coroutine that
## seats bodies one at a time — so the flag clears while the line is still
## arriving. The size-holds term covers that tail; the flag covers the case the
## size term cannot see, where the muster has not STARTED yet and an empty board
## is trivially stable. Bounded, like every other wait here.
func _settle_enemy_board() -> void:
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat):
			return
		var pending: bool = bool(combat._opening_muster_pending)
		var n := 0
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			for c in combat._row_array(true, row):
				if c != null and is_instance_valid(c):
					n += 1
		if not pending and n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(0.2).timeout


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)


func _fail(msg: String) -> void:
	_checks += 1
	_fails.append(msg)
