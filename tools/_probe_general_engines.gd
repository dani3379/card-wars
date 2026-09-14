extends Node
## _probe_general_engines.gd — the new Generals' ENGINES actually run (2026-09-13).
##
##   Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" \
##     res://tools/_probe_general_engines.tscn
##
## WHY IT EXISTS. Five Generals were authored to fill empty faction×act elite
## slots, and every one of them is DATA pointing at a passive that already
## existed — `formation_muster` / `_drill` / `_lockstep` for the Last Wall,
## `pyre_ritual` for the Everflame, `crypt_rite` for the Owed. All five engines
## were implemented and reachable by NO encounter, which is precisely why this
## probe is not optional: authoring content against machinery nobody has run in
## months is exactly how you ship a fight whose whole premise never fires.
##
## `_probe_content_census` proves the encounters can be ROLLED. It cannot prove
## the passive does anything once the fight starts — the same gap that let a
## noise material render nothing for the life of a feature earlier today. So
## this boots each fight for real and asserts the engine MOVES:
##
##   · the structure-driven pair actually SEAT their structure (a `pyre_ritual`
##     encounter with no Pyre on the board is an inert passive looking for a
##     target that was never built), and it is `attackable` — a countdown the
##     player cannot touch is the fake affordance this project already ruled
##     against once;
##   · a death FEEDS the engine, which is the whole loop;
##   · the formation tier GROWS a body that stands beside another, and leaves an
##     isolated body alone — the counterplay the fights are built to teach.

const COMBAT_SCENE := "res://scenes/combat.tscn"

## HOW MANY ASSERTIONS A COMPLETE RUN MAKES. Not bookkeeping — a GUARD.
##
## The first run of this probe printed ALL PASS while two of its checks had
## never executed: a wrong argument order threw an "Invalid type" inside
## `dispatch_encounter_on_enemy_death`, and a GDScript error ABORTS THE
## FUNCTION IT OCCURS IN rather than propagating. Everything after the bad call
## was skipped, `_fail` stayed 0, and the probe reported success for a feed loop
## it had not tested — the exact failure mode it exists to catch, wearing a
## green light.
##
## Counting is the cheap fix: a skipped assertion is now a FAILURE, not a
## silence. Update this when the assertion list changes, deliberately.
const EXPECTED_CHECKS: int = 27

var _fail := 0
var _ran := 0


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[generals] WATCHDOG fired")
		get_tree().quit(1))

	# ── THE WHITELIST, which drops what it does not name ─────────────────────
	# `make_card_data` is a strict whitelist: a key it does not list is silently
	# discarded, which is how The Old King's Body once shipped un-immune while
	# looking entirely correct. The three keyword-driven Generals author
	# magnitudes through it — Overrun 2/3 and Doom fuses — so if a passthrough
	# is missing the fight still boots, still reads right in the file, and just
	# quietly plays at the default. Assert the numbers SURVIVE the builder.
	var horse: Array = EncounterDB.build_enemy_deck("the_horse_sea")
	_check(not horse.is_empty(), "the_horse_sea: builds a deck")
	var ov_max := 0
	var ov_carriers := 0
	for cd in horse:
		if Array(cd.get("keywords", [])).has("overrun"):
			ov_carriers += 1
			ov_max = maxi(ov_max, int(cd.get("overrun", 1)))
	_check(ov_carriers >= 5,
		"the_horse_sea: the line actually CARRIES overrun (%d riders)" % ov_carriers)
	_check(ov_max >= 2,
		"the_horse_sea: an authored Overrun magnitude survives the whitelist "
		+ "(max %d — 1 would mean the key was dropped)" % ov_max)

	var spark: Array = EncounterDB.build_enemy_deck("the_first_spark")
	var fuses := 0
	for cd in spark:
		if int(cd.get("doom", 0)) > 0:
			fuses += 1
			_check(int(cd.get("doom_damage", 0)) > 0,
				"the_first_spark: %s carries its doom_damage, not just the fuse"
					% String(cd.get("name", "?")))
	_check(fuses == 3, "the_first_spark: three bodies are on a fuse (%d)" % fuses)

	for spec in [
		{"id": "the_last_kindling", "structure": "Pyre", "passive": "pyre_ritual"},
		{"id": "the_mausoleum_debt", "structure": "Mausoleum", "passive": "crypt_rite"},
		{"id": "the_testudo", "structure": "", "passive": "formation_drill"},
	]:
		await _run_one(spec)

	if _ran != EXPECTED_CHECKS:
		_fail += 1
		print("[generals] FAIL  %d assertion(s) ran, expected %d — a check was"
			% [_ran, EXPECTED_CHECKS]
			+ " SKIPPED (a GDScript error aborts its function silently)")
	print("[generals] %s" % ("ALL PASS (%d checks)" % _ran if _fail == 0
		else "%d FAILURE(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _run_one(spec: Dictionary) -> void:
	var eid: String = String(spec["id"])
	var enc: Dictionary = EncounterDB.get_encounter(eid)
	if not _check(not enc.is_empty(), "%s: the encounter resolves" % eid):
		return
	_check(String(enc.get("passive_id", "")) == String(spec["passive"]),
		"%s: carries passive %s" % [eid, spec["passive"]])

	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = eid
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = int(enc.get("act", 1)) - 1
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame

	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	if not _check(combat.round_number >= 1, "%s: combat reached round 1" % eid):
		combat.queue_free()
		return

	var want: String = String(spec["structure"])
	if want != "":
		# THE STRUCTURE MUST BE ON THE BOARD. Both these passives look up their
		# engine BY NAME (`"Pyre"`, `"Mausoleum"`) among the live structures — a
		# typo in the encounter's `structures` block leaves the handler
		# searching for something that was never seated, and the fight runs as
		# a plain brawl with a passive line that lies.
		var found = null
		for s in combat._all_structures():
			if String(s.card_data.get("name", "")) == want:
				found = s
				break
		if _check(found != null, "%s: a %s is seated on the board" % [eid, want]):
			_check(bool(found.card_data.get("attackable", false)),
				"%s: the %s is ATTACKABLE — the clock can be raced or broken"
					% [eid, want])
			var before: int = int(found.card_data.get("charge_current", 0))
			# SEAT THE VICTIM RATHER THAN LOOKING FOR ONE. At round 1 the enemy
			# board holds the structure and nothing else — the hold's creatures
			# are placed at the END of the round — so hunting for a live body
			# here found only the Pyre itself and reported a game defect that
			# was entirely the harness's own timing.
			var victim = _put_enemy(combat, combat.ROW_FRONT, 1, 2, 3)
			if _check(victim != null, "%s: a body is seated to fall" % eid):
				# Signature is (ctx, lane_idx, dead_card, row) — the LANE comes
				# second, not the card. Passing the card there threw an "Invalid
				# type" that ABORTED this function where it stood, so both feed
				# assertions below never ran and the probe still printed ALL
				# PASS. See `_expected` for why that cannot happen quietly now.
				EncounterEffects.dispatch_encounter_on_enemy_death(
					combat, int(victim.current_lane), victim, combat.ROW_FRONT)
				var after: int = int(found.card_data.get("charge_current", 0))
				_check(after > before,
					"%s: an enemy death FEEDS the %s (%d -> %d)"
						% [eid, want, before, after])
	else:
		# The formation tier: a body BESIDE another grows; an isolated one does
		# not. That asymmetry is the entire lesson these fights teach, so it is
		# the thing worth asserting rather than "some number went up".
		_clear_enemy(combat)
		combat.round_number = 3
		var pair_a = _put_enemy(combat, combat.ROW_FRONT, 0, 2, 4)
		var _pair_b = _put_enemy(combat, combat.ROW_FRONT, 1, 2, 4)
		var lone = _put_enemy(combat, combat.ROW_FRONT, 3, 2, 4)
		if _check(pair_a != null and lone != null,
				"%s: fixture — two touching bodies and one alone" % eid):
			var pair_atk: int = int(pair_a.current_atk)
			var lone_atk: int = int(lone.current_atk)
			EncounterEffects.dispatch_passive_start_of_round(combat)
			_check(int(pair_a.current_atk) > pair_atk,
				"%s: the body STANDING BESIDE another drilled (%d -> %d)"
					% [eid, pair_atk, int(pair_a.current_atk)])
			_check(int(lone.current_atk) == lone_atk,
				"%s: the ISOLATED body did not (%d -> %d) — isolation is the counterplay"
					% [eid, lone_atk, int(lone.current_atk)])

	combat.queue_free()
	await get_tree().process_frame



func _clear_enemy(combat) -> void:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var field = combat._row_array(true, row)
		for ln in range(combat.LANES_PER_ROW):
			var c = field[ln]
			if c != null and is_instance_valid(c) \
					and not c.has_keyword("structure"):
				c.queue_free()
				field[ln] = null


func _put_enemy(combat, row: int, lane: int, atk: int, hp: int):
	combat.summon_token(atk, hp, lane, true, row, {}, "Probe Body", [])
	return combat._row_array(true, row)[lane]


func _check(ok: bool, what: String) -> bool:
	_ran += 1
	if not ok:
		_fail += 1
	print("[generals] %s  %s" % ["PASS" if ok else "FAIL", what])
	return ok
