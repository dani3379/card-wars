extends Node
## _probe_card_pose.gd — THE BOARD TOKEN'S REST POSE (2026-09-17).
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_card_pose.tscn
##
## ONE DEFECT CLASS, FOUR SPELLINGS: a beat that SAMPLES a property another beat
## is still mid-way through writing, and then restores to what it sampled.
##
## Card2D.play_defend_brace's own header already names it — "a tween that captures
## a mid-move point as 'rest' walks the card out of its slot and compounds over
## every trade" — and says the fix is to kill the owning tween before reading.
## That rule was applied to the BRACE and to the ARC and to nothing else, so the
## two functions the header names still read their own previous tween's mid-flight
## value: `play_attack_lunge` captures `position`/`scale` three lines ABOVE the
## `_lunge_tween` / `_lunge_scale_tween` kills, and `play_hit_recoil` captures them
## three lines above its own `_recoil_tween` kill.
##
## The consequence is not symmetric between the two axes, which is why it survived:
##   * position.y SELF-HEALS. The idle bob rewrites it every tick from _bob_base_y,
##     so a drifted y is corrected within 33 ms and no shot ever caught it.
##   * scale DOES NOT. Nothing else writes a battlefield token's scale, so the
##     error is kept and COMPOUNDS multiplicatively — each repeat multiplies by the
##     previous beat's peak (lunge stretch 1.07, recoil squash 1.12/0.90).
##
## So a body that strikes or is struck repeatedly inside the settle window GROWS.
## That window is not exotic: the conductor awaits LUNGE_APEX (0.18 s) and the
## lunge runs 0.36 s, so the second half of every lunge is unawaited by design.
## Repeat strikers are ordinary content — `attacks_twice`, the
## `battle_order_second_strike` rider, a Sniper chaining on kills, `charges_this_turn`
## sweeping four lanes — and a defender is struck twice in any column where the
## hold keeps both rows.
##
## PHASE B is the same fault on `modulate`. SEVEN beats write a board token's tint
## (flash_doom_tick / show_heal_number / _flash_hit's fallback / _mark_mortally_struck
## / _recover_from_mortal_slump / _play_last_stand_flare / play_floop_pulse), every
## one of them "capture base := modulate, wash, restore to base", none of them
## aware of the others. Overlap two and the one that finishes LAST restores to a
## transient wash — the card is left permanently tinted, with nothing to correct it.
## _mark_mortally_struck is the worst of the seven because it stores the poisoned
## sample in a FIELD (_mortal_slump_base) that a later rescue restores from.
##
## PHASE C is the bob. _combat_tween_active() is the bob's yield rule and it names
## _lunge_tween and _recoil_tween. `_brace_tween` tweens `position` — the whole
## Vector2, y included — and is NOT named, so the 30 Hz bob overwrites the brace's
## only axis while it runs. The defender's "set into the blow", whose header calls
## it "the cheapest fix in the whole design", is stomped frame by frame.
##
## Every number below is MEASURED against the card's own rest, captured after the
## board has settled — never against a constant, so a retune of any beat's depth
## cannot make this gate lie.

const COMBAT_SCENE := "res://scenes/combat.tscn"

## Below this the reading is float noise, not drift.
const EPS := 0.01
## The conductor's own cadence: Combat._creature_attacks_creature awaits
## LUNGE_APEX and then moves on, so this is the real gap between two strikes by
## the same body — deliberately NOT a gap long enough to let the settle finish.
const REPEAT_GAP := 0.18
const REPEATS := 4

var _fails := 0
var _findings: Array[String] = []


func _ready() -> void:
	# WATCHDOG. A probe that hangs reports nothing at all, which is strictly worse
	# than a wrong answer because it deletes the evidence (the house lesson from
	# _probe_pilot's unbounded `while await`). Nothing here should take 150 s.
	_watchdog()

	# Both of these decide whether the beats under test run at all; pin them so a
	# developer's own settings file cannot silently empty this probe.
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0

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
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")

	print("")
	print("── A · THE REST POSE (position + scale) ──────────────────────────")
	await _phase_pose(combat)
	print("")
	print("── B · ONE TINT AT A TIME (modulate) ─────────────────────────────")
	await _phase_tint(combat)
	print("")
	print("── C · THE BOB YIELDS TO EVERY POSITION TWEEN ────────────────────")
	await _phase_bob(combat)

	print("")
	if _findings.is_empty():
		print("FINDINGS: none")
	else:
		print("FINDINGS (%d):" % _findings.size())
		for f in _findings:
			print("   * " + f)
	print("")
	if _fails == 0:
		print("PROBE PASS: card_pose")
	else:
		printerr("PROBE FAIL: card_pose (%d)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


# ══════════════════════════════════════════════════════════════════════
#  A · the rest pose
# ══════════════════════════════════════════════════════════════════════

func _phase_pose(combat) -> void:
	# THE ATTACKER — repeated lunges at the conductor's own cadence.
	_clear_board(combat)
	var striker = _put(combat, false, combat.ROW_FRONT, 1, 3, 40)
	if not _check(striker != null, "fixture: a body that can swing"):
		return
	await _settle()
	var rest_scale: Vector2 = striker.scale
	var rest_x: float = striker.position.x
	for i in range(REPEATS):
		striker.play_attack_lunge(1.0)
		await get_tree().create_timer(REPEAT_GAP).timeout
	await _settle()
	_measure("lunge", striker, rest_scale, rest_x)

	# THE DEFENDER — repeated recoils. A body struck twice in one clash is
	# ordinary: both enemy rows strike into the same column.
	_clear_board(combat)
	var struck = _put(combat, false, combat.ROW_FRONT, 2, 1, 40)
	if not _check(struck != null, "fixture: a body that can be struck"):
		return
	await _settle()
	rest_scale = struck.scale
	rest_x = struck.position.x
	for i in range(REPEATS):
		struck.play_hit_recoil(true)
		await get_tree().create_timer(REPEAT_GAP).timeout
	await _settle()
	_measure("recoil", struck, rest_scale, rest_x)


func _measure(label: String, card, rest_scale: Vector2, rest_x: float) -> void:
	var ds: Vector2 = card.scale - rest_scale
	var dx: float = card.position.x - rest_x
	print("   %s x%d: scale %.4f,%.4f -> %.4f,%.4f (d %+.4f,%+.4f)  x %+.2f px"
		% [label, REPEATS, rest_scale.x, rest_scale.y,
			card.scale.x, card.scale.y, ds.x, ds.y, dx])
	var ok_scale: bool = absf(ds.x) < EPS and absf(ds.y) < EPS
	if not _check(ok_scale,
			"%s x%d leaves scale at rest (drift %+.4f,%+.4f)" % [label, REPEATS, ds.x, ds.y]):
		_findings.append(
			"%s COMPOUNDS SCALE: %d repeats leave the body at %.3f x %.3f of its true size"
				% [label, REPEATS, card.scale.x / maxf(rest_scale.x, 0.001),
					card.scale.y / maxf(rest_scale.y, 0.001)])
	if not _check(absf(dx) < 0.5,
			"%s x%d leaves position.x at rest (drift %+.2f px)" % [label, REPEATS, dx]):
		_findings.append("%s DRIFTS X: %d repeats walk the body %+.1f px out of its slot"
			% [label, REPEATS, dx])


# ══════════════════════════════════════════════════════════════════════
#  B · one tint at a time
# ══════════════════════════════════════════════════════════════════════

func _phase_tint(combat) -> void:
	_clear_board(combat)
	var card = _put(combat, false, combat.ROW_FRONT, 0, 2, 40)
	if not _check(card != null, "fixture: a body to tint"):
		return
	await _settle()
	var rest: Color = card.modulate

	# Every pair below is two beats that can and do land on one body inside each
	# other's window. The overlap is 0.10 s — shorter than any of these beats.
	await _tint_pair(card, rest, "heal over a doom tick",
		func(): card.flash_doom_tick(),
		func(): card.show_heal_number(3))
	await _tint_pair(card, rest, "doom tick over a floop pulse",
		func(): card.play_floop_pulse(),
		func(): card.flash_doom_tick())
	await _tint_pair(card, rest, "heal over a Last Stand flare",
		func(): card._play_last_stand_flare(),
		func(): card.show_heal_number(3))

	# THE POISONED FIELD. _mark_mortally_struck stores its sample in
	# _mortal_slump_base, and a rescue (Phantom Veil, Reborn, an hp_floor) restores
	# the body FROM that field — so a sample taken mid-wash is not transient, it is
	# the body's permanent tint from then on.
	card.modulate = rest
	card._mortal_slumped = false
	card.flash_doom_tick()
	await get_tree().create_timer(0.10).timeout
	card._mark_mortally_struck()
	await _settle()
	card._recover_from_mortal_slump()
	await _settle()
	var d := _colour_delta(card.modulate, rest)
	print("   rescue after a slump taken mid-tick: modulate %s (rest %s) d=%.4f"
		% [_fmt(card.modulate), _fmt(rest), d])
	if not _check(d < EPS, "a rescued body comes back to its true tint (d=%.4f)" % d):
		_findings.append(
			"MORTAL SLUMP POISONS ITS BASE: a body rescued after being struck mid-beat "
			+ "is left permanently at %s instead of %s" % [_fmt(card.modulate), _fmt(rest)])


func _tint_pair(card, rest: Color, label: String, first: Callable,
		second: Callable) -> void:
	card.modulate = rest
	card._mortal_slumped = false
	first.call()
	await get_tree().create_timer(0.10).timeout
	second.call()
	await _settle()
	var d := _colour_delta(card.modulate, rest)
	print("   %-32s modulate %s (rest %s) d=%.4f"
		% [label, _fmt(card.modulate), _fmt(rest), d])
	if not _check(d < EPS, "%s settles back to the true tint (d=%.4f)" % [label, d]):
		_findings.append("TINT RACE (%s): the body is left at %s instead of %s"
			% [label, _fmt(card.modulate), _fmt(rest)])


func _colour_delta(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)),
		maxf(absf(a.b - b.b), absf(a.a - b.a)))


func _fmt(c: Color) -> String:
	return "(%.2f %.2f %.2f %.2f)" % [c.r, c.g, c.b, c.a]


# ══════════════════════════════════════════════════════════════════════
#  C · the bob's yield rule
# ══════════════════════════════════════════════════════════════════════

func _phase_bob(combat) -> void:
	_clear_board(combat)
	var card = _put(combat, false, combat.ROW_FRONT, 3, 2, 40)
	if not _check(card != null, "fixture: a body that bobs"):
		return
	await _settle()
	card.enable_idle_bob()
	_check(card._idle_bob_enabled, "the body is bobbing (else this phase is vacuous)")

	# The bob writes position.y at 30 Hz from _bob_base_y and consults exactly one
	# predicate before doing it. Any tween that writes y must be inside that
	# predicate or it is simply overwritten.
	card.play_defend_brace(true)
	await get_tree().process_frame
	var yields_to_brace: bool = card._combat_tween_active()
	print("   brace running -> _combat_tween_active() = %s" % str(yields_to_brace))
	if not _check(yields_to_brace,
			"the bob yields to the brace (it tweens `position`, y included)"):
		_findings.append(
			"THE BOB STOMPS THE BRACE: play_defend_brace tweens `position` but "
			+ "_combat_tween_active() names only the lunge and the recoil, so the 30 Hz "
			+ "bob overwrites the brace's only axis while it runs")
	await _settle()

	# The control arm: the two tweens the rule already names must still be named,
	# so a fix that swaps one predicate for another cannot pass by luck.
	card.play_attack_lunge(1.0)
	await get_tree().process_frame
	_check(card._combat_tween_active(), "the bob still yields to the lunge")
	await _settle()
	card.play_hit_recoil(true)
	await get_tree().process_frame
	_check(card._combat_tween_active(), "the bob still yields to the recoil")
	await _settle()


# ══════════════════════════════════════════════════════════════════════
#  helpers
# ══════════════════════════════════════════════════════════════════════

## Long enough for every beat under test to finish: the slowest is the lunge at
## LUNGE_APEX + LUNGE_SETTLE + the roll's 40 ms follow-through, plus the doom
## tick's 0.50 s wash.
func _settle() -> void:
	await get_tree().create_timer(0.9).timeout


func _watchdog() -> void:
	await get_tree().create_timer(150.0).timeout
	printerr("PROBE FAIL: card_pose (watchdog — the run never reached its report)")
	get_tree().quit(1)


func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return ""


func _clear_board(combat) -> void:
	for is_enemy in [true, false]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr: Array = combat._row_array(is_enemy, row)
			for i in range(arr.size()):
				var c = arr[i]
				if c != null and is_instance_valid(c):
					arr[i] = null
					c.queue_free()


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
