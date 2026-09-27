extends Node
## _probe_formation_cap.gd — THE GROWING WALL HAS A CEILING (2026-09-26).
##
## `EncounterEffects.formation_drill_tick` is the Last Wall's engine: every enemy
## body with a neighbour takes +1/+1 at the top of a round. It drives SEVEN
## encounters across three escalating tiers (`formation_muster` /
## `formation_drill` / `formation_lockstep`), and until 2026-09-26 it had NO CAP.
##
## Measured over the 12-seed pilot corpus, that showed up as a family signature
## rather than as one hard fight: `The Unfinished Wall` was the WORST act-1
## General in the game at 33% (every other act-1 General 75-100%), THE STALWART
## act 2 was 0 of 3, and the losses ended at hero -4 to -26 HP against a foe face
## still holding 1-8 — routings, not near misses. An eight-round fight handed a
## four-body line +7/+7 each: 56 free stat points on top of an infinite
## reinforcement drip. See docs/PLAYTEST_MEASUREMENT_20260919.md §16.
##
## WHY THIS RUNS ON STUBS. `formation_drill_tick` is STATIC and takes its ctx as
## an argument, so the whole rule is reachable with no Combat scene and no board —
## which makes the gate cheap enough to keep, and is also the standing check that
## the function stays ctx-parameterised rather than reaching into Combat.
##
## It runs as a SCENE rather than `--script`, unlike its cousins `_probe_board_eval`
## and `_probe_personas`: those gate files that name NO autoload, and being
## `--script` is what proves it. `EncounterEffects` DOES name `CardDB`, so a
## `preload` of it in a `--script` probe is dragged into the PRE-autoload compile
## and fails outright (CLAUDE.md, "parsecheck's ONE blind spot"). The stubs are
## still the point; only the launcher differs.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_formation_cap.tscn

const EncounterEffects := preload("res://scripts/data/EncounterEffects.gd")

const ROW_FRONT := 0
const ROW_BACK := 1

var _pass := 0
var _fail := 0


# ---------------------------------------------------------------------------
#  Stubs. A body needs exactly what the drill touches: the two stat pairs, a
#  meta store (get_meta/set_meta are Object methods, so a plain Object is
#  enough), and a no-op display refresh.
# ---------------------------------------------------------------------------

class StubBody:
	extends Object
	var card_data: Dictionary = {}
	var current_atk: int = 0
	var current_hp: int = 0
	var display_updates: int = 0

	func _init(atk: int, hp: int, kws: Array = []) -> void:
		current_atk = atk
		current_hp = hp
		card_data = {"hp": hp, "keywords": kws.duplicate(), "name": "stub"}

	func update_stat_display() -> void:
		display_updates += 1


class StubCtx:
	extends Object
	var round_number: int = 1
	var ROW_FRONT := 0
	var ROW_BACK := 1
	var front: Array = [null, null, null, null]
	var back: Array = [null, null, null, null]
	var said: Array[String] = []
	var logged: Array[String] = []

	func _row_array(_is_enemy: bool, row: int) -> Array:
		return front if row == ROW_FRONT else back

	func _show_info(t: String) -> void:
		said.append(t)

	func _log_event(t: String, _a = null, _b = null) -> void:
		logged.append(t)


func _ck(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  %s%s" % [label, ("  — " + detail) if detail != "" else ""])


func _mk(ctx: StubCtx, row: int, lane: int, atk: int, hp: int) -> StubBody:
	var b := StubBody.new(atk, hp)
	(ctx.front if row == ROW_FRONT else ctx.back)[lane] = b
	return b


func _free_ctx(ctx: StubCtx) -> void:
	for arr in [ctx.front, ctx.back]:
		for b in arr:
			if b != null:
				b.free()
	ctx.free()


# ---------------------------------------------------------------------------

func _ready() -> void:
	print("=== _probe_formation_cap ===")
	print("FORMATION_MAX_STACKS = %d" % EncounterEffects.FORMATION_MAX_STACKS)
	_phase_a_cap_holds()
	_phase_b_late_arrival()
	_phase_c_adjacency()
	_phase_d_tiers()
	_phase_e_announced()
	_phase_f_bound()
	_phase_g_printed()
	print("")
	if _fail == 0:
		print("PROBE PASS: formation_cap  (%d checks)" % _pass)
	else:
		print("PROBE FAIL: formation_cap  (%d passed, %d FAILED)" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _phase_a_cap_holds() -> void:
	print("\nA. THE CEILING — growth stops at FORMATION_MAX_STACKS")
	var cap: int = EncounterEffects.FORMATION_MAX_STACKS
	var ctx := StubCtx.new()
	var a := _mk(ctx, ROW_FRONT, 0, 2, 2)
	var b := _mk(ctx, ROW_FRONT, 1, 3, 4)
	# Drive far past the cap. 12 rounds is a long fight, and the whole point of
	# the defect was that a long fight had no ceiling at all.
	for r in range(2, 14):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false)
	_ck("front body A capped at +%d ATK" % cap, a.current_atk == 2 + cap,
		"atk=%d expected %d" % [a.current_atk, 2 + cap])
	_ck("front body A capped at +%d max HP" % cap, int(a.card_data.hp) == 2 + cap,
		"hp=%d expected %d" % [int(a.card_data.hp), 2 + cap])
	_ck("front body B capped at +%d ATK" % cap, b.current_atk == 3 + cap,
		"atk=%d expected %d" % [b.current_atk, 3 + cap])
	# The HEAL half must not exceed the max it is clamped to.
	_ck("current HP never exceeds max", a.current_hp <= int(a.card_data.hp),
		"cur=%d max=%d" % [a.current_hp, int(a.card_data.hp)])
	_ck("stack meta records exactly the cap", int(a.get_meta("formation_stacks", 0)) == cap,
		"stacks=%d" % int(a.get_meta("formation_stacks", 0)))
	# A capped body must stop paying for display refreshes too — a no-op that
	# still repaints every round is how a "stopped" effect keeps costing.
	var updates_at_cap: int = a.display_updates
	ctx.round_number = 20
	EncounterEffects.formation_drill_tick(ctx, false)
	_ck("a capped body is not re-displayed", a.display_updates == updates_at_cap,
		"updates grew %d -> %d" % [updates_at_cap, a.display_updates])
	_free_ctx(ctx)


func _phase_b_late_arrival() -> void:
	print("\nB. PER BODY, NOT PER FIGHT — a late arrival gets its own allowance")
	var cap: int = EncounterEffects.FORMATION_MAX_STACKS
	var ctx := StubCtx.new()
	# The veteran needs a PARTNER from the start: the drill requires a neighbour
	# (phase C gates that), so a lone body never drills at all and would reach the
	# reinforcement still at zero stacks — which is what the first draft of this
	# phase actually measured, and it read as the cap failing.
	var veteran := _mk(ctx, ROW_FRONT, 0, 2, 2)
	var partner := _mk(ctx, ROW_FRONT, 1, 2, 2)
	for r in range(2, 10):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false)
	_ck("the veteran is capped before the reinforcement lands",
		int(veteran.get_meta("formation_stacks", 0)) == cap,
		"stacks=%d" % int(veteran.get_meta("formation_stacks", 0)))
	_ck("its partner is capped too", int(partner.get_meta("formation_stacks", 0)) == cap)
	# Reinforcement arrives on round 10, beside the capped partner.
	var fresh := _mk(ctx, ROW_FRONT, 2, 1, 1)
	for r in range(10, 10 + cap):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false)
	_ck("the reinforcement drills its full +%d" % cap, fresh.current_atk == 1 + cap,
		"atk=%d expected %d" % [fresh.current_atk, 1 + cap])
	_ck("the veteran did not resume", veteran.current_atk == 2 + cap,
		"atk=%d expected %d" % [veteran.current_atk, 2 + cap])
	# ...and the reinforcement stops at the same ceiling, not a rolling one.
	for r in range(20, 30):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false)
	_ck("the reinforcement stops at the same ceiling", fresh.current_atk == 1 + cap,
		"atk=%d expected %d" % [fresh.current_atk, 1 + cap])
	_free_ctx(ctx)


func _phase_c_adjacency() -> void:
	print("\nC. ADJACENCY — a body with no neighbour never drills")
	var ctx := StubCtx.new()
	var lone := _mk(ctx, ROW_FRONT, 0, 4, 4)
	for r in range(2, 12):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false)
	_ck("a lone body does not grow", lone.current_atk == 4,
		"atk=%d expected 4" % lone.current_atk)
	_ck("a lone body spends no stack", int(lone.get_meta("formation_stacks", 0)) == 0)
	# A gap in the middle isolates lane 0 and lane 2 from each other: lane 0's
	# only neighbour is lane 1 (empty), so it must still be excluded.
	var isolated := _mk(ctx, ROW_FRONT, 2, 1, 1)
	var neighbour := _mk(ctx, ROW_FRONT, 3, 1, 1)
	ctx.round_number = 12
	EncounterEffects.formation_drill_tick(ctx, false)
	_ck("lane 0 still isolated across a gap", lone.current_atk == 4)
	_ck("an adjacent pair does grow", isolated.current_atk == 2 and neighbour.current_atk == 2,
		"%d / %d" % [isolated.current_atk, neighbour.current_atk])
	_free_ctx(ctx)


func _phase_d_tiers() -> void:
	print("\nD. ALL THREE TIERS respect the cap, and keep their own cadence")
	var cap: int = EncounterEffects.FORMATION_MAX_STACKS

	# front_only (formation_muster): front rank only, and NOT before round 3.
	var ctx := StubCtx.new()
	var f := _mk(ctx, ROW_FRONT, 0, 1, 1)
	var f2 := _mk(ctx, ROW_FRONT, 1, 1, 1)
	var bk := _mk(ctx, ROW_BACK, 0, 1, 1)
	var bk2 := _mk(ctx, ROW_BACK, 1, 1, 1)
	ctx.round_number = 2
	EncounterEffects.formation_drill_tick(ctx, false, true)
	_ck("muster is silent on round 2", f.current_atk == 1 and ctx.said.is_empty())
	for r in range(3, 14):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false, true)
	_ck("muster caps the front row", f.current_atk == 1 + cap and f2.current_atk == 1 + cap,
		"%d / %d" % [f.current_atk, f2.current_atk])
	_ck("muster never touches the back row", bk.current_atk == 1 and bk2.current_atk == 1,
		"%d / %d" % [bk.current_atk, bk2.current_atk])
	_free_ctx(ctx)

	# lockstep: both rows, plus Armored on the front — and the keyword grant must
	# NOT be gated by the stat cap, or the wall stops closing ranks too.
	var ctx2 := StubCtx.new()
	var lf := _mk(ctx2, ROW_FRONT, 0, 1, 1)
	var _lf2 := _mk(ctx2, ROW_FRONT, 1, 1, 1)
	var lb := _mk(ctx2, ROW_BACK, 0, 1, 1)
	var _lb2 := _mk(ctx2, ROW_BACK, 1, 1, 1)
	for r in range(2, 14):
		ctx2.round_number = r
		EncounterEffects.formation_drill_tick(ctx2, true)
	_ck("lockstep caps the front row", lf.current_atk == 1 + cap, "atk=%d" % lf.current_atk)
	_ck("lockstep caps the back row too", lb.current_atk == 1 + cap, "atk=%d" % lb.current_atk)
	_ck("lockstep still grants Armored", (lf.card_data.keywords as Array).has("armored"))
	_ck("lockstep leaves the back row unarmored",
		not (lb.card_data.keywords as Array).has("armored"))
	# A fresh body arriving at the front AFTER everyone is capped must still be
	# armored — the grant is per-body state, so a stat ceiling must not swallow it.
	var late := _mk(ctx2, ROW_FRONT, 2, 1, 1)
	ctx2.round_number = 20
	EncounterEffects.formation_drill_tick(ctx2, true)
	_ck("a late front body is still armored", (late.card_data.keywords as Array).has("armored"))
	_free_ctx(ctx2)


func _phase_e_announced() -> void:
	print("\nE. THE CEILING IS SPOKEN — a silent stop is the silent-refusal class")
	var ctx := StubCtx.new()
	_mk(ctx, ROW_FRONT, 0, 1, 1)
	_mk(ctx, ROW_FRONT, 1, 1, 1)
	var growth_lines := 0
	var topped_lines := 0
	for r in range(2, 14):
		ctx.round_number = r
		ctx.said.clear()
		EncounterEffects.formation_drill_tick(ctx, false)
		# EVERY round in a formation fight must say SOMETHING, or the player is
		# left to infer from the stat numerals whether the rule is still running.
		_ck("round %d speaks" % r, ctx.said.size() >= 1, "said nothing")
		for line in ctx.said:
			if line.contains("grows +1/+1"):
				growth_lines += 1
			elif line.contains("grows no further"):
				topped_lines += 1
	_ck("growth was announced exactly %d times" % EncounterEffects.FORMATION_MAX_STACKS,
		growth_lines == EncounterEffects.FORMATION_MAX_STACKS,
		"growth lines=%d" % growth_lines)
	_ck("the ceiling is announced once it is reached", topped_lines >= 1,
		"topped lines=%d" % topped_lines)
	_free_ctx(ctx)


func _phase_f_bound() -> void:
	print("\nF. THE BOUND — what a full line can gain over a long fight")
	var cap: int = EncounterEffects.FORMATION_MAX_STACKS
	# The defect in one number. A full 8-slot line over a 12-round fight: the
	# uncapped rule handed each body +11/+11; the cap bounds the whole line's
	# total gain, which is the property that turns "unwinnable" into "timed".
	var ctx := StubCtx.new()
	var bodies: Array = []
	for lane in 4:
		bodies.append(_mk(ctx, ROW_FRONT, lane, 2, 2))
		bodies.append(_mk(ctx, ROW_BACK, lane, 2, 2))
	for r in range(2, 14):
		ctx.round_number = r
		EncounterEffects.formation_drill_tick(ctx, false)
	var gained := 0
	for b in bodies:
		gained += (b.current_atk - 2) + (int(b.card_data.hp) - 2)
	var want: int = bodies.size() * cap * 2
	_ck("a full line's total gain is bounded at %d stat points" % want, gained == want,
		"gained=%d" % gained)
	# Sanity on the size of the thing being gated: the uncapped rule over the
	# same 12 rounds would have handed out 8 bodies x 11 rounds x 2 = 176.
	_ck("the cap is a real reduction over a long fight", gained < 176,
		"gained=%d is not below the uncapped 176" % gained)
	_free_ctx(ctx)


func _phase_g_printed() -> void:
	print("\nG. THE CAP IS PRINTED — rules text is a design surface (ONBOARDING §5)")
	# A ceiling the CARD does not state is a ceiling the player cannot plan around,
	# and the whole value of this cap is that "you cannot win this" becomes "you
	# have five rounds". Every desc that describes the drill must say how many
	# times it fires, and the LADDER's canonical rung texts must agree with the
	# authored encounters — two statements of one rule is how they drift.
	var ladder_ids: Array = []
	for ladder in EncounterDB.PASSIVE_ACT_LADDERS:
		for id in (ladder as Array):
			ladder_ids.append(String(id))
	_ck("the ladder is non-empty", not ladder_ids.is_empty())
	for id in ladder_ids:
		var txt := String(EncounterDB.PASSIVE_RUNG_DESC.get(id, ""))
		_ck("rung %s has canonical text" % id, txt != "")
		_ck("rung %s states the cap" % id, txt.contains("three times"),
			"text: %s" % txt)
	# Every AUTHORED encounter carrying a ladder rung must state it too — the rung
	# text is only used when a fight is STEPPED, so an authored desc that forgot
	# the cap is read by every player who meets the fight at its own act.
	var checked := 0
	var silent: Array[String] = []
	for enc_id in EncounterDB.ENCOUNTERS.keys():
		var e: Dictionary = EncounterDB.ENCOUNTERS[enc_id]
		for src in [e] + (e.get("phases", []) as Array):
			var pid := String((src as Dictionary).get("passive_id", ""))
			if not ladder_ids.has(pid):
				continue
			checked += 1
			var d := String((src as Dictionary).get("passive_desc", ""))
			if d != "" and not d.contains("three times"):
				silent.append("%s (*%s)" % [enc_id, pid])
	_ck("some authored descs were found to check", checked > 0, "checked=%d" % checked)
	_ck("every authored formation desc states the cap", silent.is_empty(),
		"silent: %s" % ", ".join(silent))
	print("    checked %d authored passive_desc slots carrying a ladder rung" % checked)
