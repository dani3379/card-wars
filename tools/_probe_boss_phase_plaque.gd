extends SceneTree
## The boss standing-rule plaque — does the HUD state the law actually in force?
##
## EVERY boss in the game is phased (EncounterDB.BOSS_PHASES, 17 kits), and the
## rule plaque is the ONLY permanent statement of a fight's law: the intro banner
## explicitly defers to it. Until 2026-07-27 the plaque was written once at HUD
## build and never again — `_check_boss_phase_transition` moved the passive ID
## while the label kept phase 1's wording, so every boss past its first threshold
## sat under a plaque that lied for the rest of the fight. The transient phase
## banner showed the truth for two seconds, which made it worse, not better.
##
## THREE paths change the law after round 1 and all three are pinned here:
##   A/B  the HP-threshold phase turn        (_check_boss_phase_transition)
##   C    the stall-forced turn, no banner   (_check_escalation, "boss" arm)
##   D    a capital siege waking its lord    (_siege_check_breach)
## E and F guard the two exclusions the build gate depends on.
##
##   Godot.exe --headless --path . --script res://tools/_probe_boss_phase_plaque.gd

const TICK := 0.1
const WAIT_TICKS := 120

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
var combat: Node
var _fails := 0
var _started := false
var _done := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## Let the container sort. `get_line_count()` is only meaningful once the label
## has been laid out at its new width.
func _settle() -> void:
	await create_timer(TICK).timeout
	await create_timer(TICK).timeout


func _plaque_text() -> String:
	if combat == null or not is_instance_valid(combat):
		return "<no combat>"
	var lbl = combat._passive_rule_label
	if lbl == null or not is_instance_valid(lbl):
		return "<no label>"
	return String(lbl.text)


## The width the plaque SHOULD be wearing for `txt`, computed the way
## `_apply_standing_rule` computes it. On its own this only proves "a re-measure
## ran" — so every use below is paired with either an unclamped-width assertion
## or a behavioural `get_line_count()` check, because several boss rules are long
## enough to hit the 620px clamp, where a width assertion is 620 == 620 and would
## pass with no measurement at all.
func _expected_width(txt: String) -> float:
	var f: Font = combat._passive_rule_label.get_theme_font("font")
	return minf(f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 2.0, 620.0)


func _boot(enc_id: String, node_type: String, act_idx: int,
		sp_id: String = "") -> bool:
	if combat != null and is_instance_valid(combat):
		combat.queue_free()
		await create_timer(TICK).timeout
	RS.start_new_run("raider", 0, 4242)
	RS.current_setpiece_id = sp_id
	RS.current_encounter_id = enc_id
	RS.current_node_type = node_type
	RS.current_mutator_id = ""
	RS.current_act_idx = act_idx
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	var waited := 0
	while waited < WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		# NOT `phase == PLAYER_TURN`: that is enum value 0 and the member's
		# default, so it reads true on the very first tick — before _build_hud
		# has run at all. `round_number` only leaves 0 in _start_round, which is
		# strictly after the HUD is built. A set-piece opens on a despatch page
		# the player must dismiss, so it never starts a round unattended — wait
		# on its objective plaque instead.
		if sp_id != "":
			if combat._sp_plaque != null and is_instance_valid(combat._sp_plaque):
				return true
		elif combat.round_number >= 1:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if RS == null or EDB == null:
		print("[phase-plaque] FATAL: RunState or EncounterDB autoload missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()

	# ── A. the plaque follows the law across every threshold ─────────────────
	print("-- A. phased boss: the plaque follows the law")
	var phases: Array = EDB.get_boss_phases("the_devil")
	_check(phases.size() == 3, "the Devil declares three phases")
	if not await _boot("the_devil", "boss", 2):
		_check(false, "combat reaches the first player turn")
		_finish(1)
		return
	_check(combat._passive_banner != null and is_instance_valid(combat._passive_banner),
		"standing-rule plaque is built")
	_check(combat._passive_rule_label != null
			and is_instance_valid(combat._passive_rule_label),
		"its rule label is reachable for rewriting")
	_check(combat._passive_banner.visible, "plaque is visible for an ordinary boss")
	var p0: String = String(phases[0].passive_desc)
	var p1: String = String(phases[1].passive_desc)
	var p2: String = String(phases[2].passive_desc)
	_check(_plaque_text() == p0, "plaque opens on the encounter's own rule")
	# The Devil's opening rule measures ~971px and CLAMPS to 620, so a width
	# assertion here would be 620 == 620. Assert the shape instead: a clamped
	# rule is the one case that is supposed to wrap.
	await _settle()
	_check(combat._passive_rule_label.get_line_count() >= 2,
		"the clamped opening rule wraps, which is what the 620px measure is for")

	# Phase 1 (threshold 20). Phase 2's rule is much SHORTER, and short enough to
	# measure UNCLAMPED — so this arm genuinely exercises the re-measure.
	# Read the LIVE thresholds, never the raw DB numbers: Combat rescales them by
	# the act ratio AND by ENEMY_HP_SCALE, so hardcoding 15/5 silently stops
	# crossing anything the moment the global HP dial moves (which is exactly what
	# happened when it went to 0.60 and the_devil's 20/10 became 12/6).
	combat.enemy_hp = int(combat._boss_phases[0].threshold)
	combat._check_boss_phase_transition()
	await _settle()
	_check(combat._boss_current_phase == 1, "crossing phase 0's threshold turns the phase")
	_check(String(combat._encounter_passive) == "devil_phase2",
		"passive id advances to phase 2")
	_check(String(combat._encounter_passive_desc) == p1,
		"passive DESC advances with the id (they used to desynchronise)")
	_check(_plaque_text() == p1, "PLAQUE now states phase 2's rule")
	_check(_plaque_text() != p0, "plaque no longer keeps phase 1's wording")
	var w1: float = _expected_width(p1)
	_check(w1 < 620.0, "phase 2's rule is short enough to measure UNCLAMPED")
	_check(is_equal_approx(combat._passive_rule_label.custom_minimum_size.x, w1),
		"box re-measured DOWN to the shorter rule's true width")
	_check(combat._passive_rule_label.get_line_count() == 1,
		"and the shorter rule now fits on ONE line")

	# ── B. a brand-new law is not greyed out on the beat it becomes true ─────
	print("-- B. the full-ink hold beats the back-row watermark")
	# Reduce Motion ON for this arm ONLY. With it OFF, _refresh_passive_plaque
	# reaches for a TWEEN, which does not move modulate until the next frame — so
	# the assertion below would pass even with the hold deleted entirely. The
	# reduce-motion branch assigns immediately, which is what makes it bite.
	if US != null:
		US.reduce_motion = true
	_check(combat._passive_rule_hold, "a rule change holds the plaque at full ink")
	combat._passive_banner.modulate.a = 0.42
	combat._refresh_passive_plaque()
	_check(is_equal_approx(combat._passive_banner.modulate.a, 0.42),
		"the watermark refresh is a no-op while the hold stands")
	# Differential: release the hold and the SAME call must move it, proving the
	# guard is what did the work above.
	combat._passive_rule_hold = false
	combat._refresh_passive_plaque()
	# 1.0 with an empty enemy back row, 0.55 with a token mustered under the
	# plaque — either proves the SAME call moved it, i.e. the hold is what
	# suppressed it above rather than the call being inert.
	var released_a: float = combat._passive_banner.modulate.a
	_check(is_equal_approx(released_a, 1.0) or is_equal_approx(released_a, 0.55),
		"with the hold released the same call moves it (got %.2f)" % released_a)
	combat._passive_rule_hold = true
	if US != null:
		US.reduce_motion = false

	# Phase 2 (threshold 10) — and back UP in width. Also the overlapping-hold
	# regression: `damage_enemy_hero` re-checks the phase on EVERY face-damage
	# instance, so two thresholds can fall inside one clash and the FIRST rule's
	# timer must not release the SECOND rule's ink.
	var seq_before: int = combat._passive_hold_seq
	combat.enemy_hp = int(combat._boss_phases[1].threshold)
	combat._check_boss_phase_transition()
	await _settle()
	_check(combat._boss_current_phase == 2, "crossing phase 1's threshold turns the final phase")
	_check(_plaque_text() == p2, "PLAQUE states phase 3's rule")
	_check(combat._passive_hold_seq > seq_before,
		"a second rule change inside the beat takes a FRESH hold token")
	_check(combat._passive_rule_hold, "and its hold is still standing")
	var w2: float = _expected_width(p2)
	_check(w2 < 620.0, "phase 3's rule is also unclamped")
	_check(is_equal_approx(combat._passive_rule_label.custom_minimum_size.x, w2),
		"box re-measured UP for the longer rule")
	_check(combat._passive_rule_label.get_line_count() == 1,
		"and it still fits one line at its own width")

	# ── C. the stall path, which shows no banner at all ──────────────────────
	print("-- C. the stall-forced phase turn posts its rule too")
	if not await _boot("the_devil", "boss", 2):
		_check(false, "combat re-boots for the stall path")
		_finish(1)
		return
	_check(combat._boss_current_phase == 0, "fresh fight opens in phase 0")
	_check(_plaque_text() == p0, "and on the opening rule")
	combat.round_number = 99
	combat._check_escalation()
	await _settle()
	_check(combat._boss_current_phase == 1, "stalling forces the phase")
	_check(_plaque_text() == p1,
		"PLAQUE follows the stall path (its ONLY rules readout — no banner here)")

	# ── D. a capital siege wakes its dormant rule at the breach ──────────────
	print("-- D. the siege's dormant rule finally has somewhere to live")
	if not await _boot("rival_stalwart", "boss", 0):
		_check(false, "the Stalwart siege reaches the first player turn")
		_finish(1)
		return
	_check(combat._siege_active, "the Stalwart declares a siege")
	_check(combat._passive_banner != null and is_instance_valid(combat._passive_banner),
		"siege builds the standing-rule plaque up front")
	_check(not combat._passive_banner.visible,
		"plaque stays HIDDEN while the gate stands")
	_check(_plaque_text() == "", "no rule is posted while the lord is unreachable")
	_check(combat._siege_plaque != combat._passive_banner,
		"objective plaque and rule plaque are distinct nodes (never doubled)")
	# The hidden plaque must not be quietly watermarked while it waits, or the
	# lord's rule arrives pre-dimmed.
	combat._refresh_passive_plaque()
	_check(is_equal_approx(combat._passive_banner.modulate.a, 1.0),
		"the hidden plaque is never dimmed while it waits")
	var guard := 0
	while combat._living_siege_gates().size() > 0 and guard < 20:
		for g in combat._living_siege_gates():
			combat._deal_siege_removal_damage(g)
		await create_timer(TICK).timeout
		guard += 1
	_check(combat._siege_breached, "both gate sections fall")
	var lord_rule: String = String(
		EDB.get_encounter("rival_stalwart").get("passive_desc", ""))
	_check(combat._passive_banner.visible, "plaque APPEARS at the breach")
	_check(_plaque_text() == lord_rule,
		"and states the lord's own formation, which had no widget before")
	_check(is_equal_approx(combat._passive_banner.modulate.a, 1.0),
		"the lord's rule appears at FULL ink, not a watermark")
	_check(combat._passive_rule_hold,
		"the reveal takes a hold like any other rule change")
	_check(String(combat._encounter_passive) == "formation_muster",
		"the restored passive id is unchanged (pass-gate's contract)")

	# ── E. set-pieces keep their own objective plaque, ungrown ───────────────
	print("-- E. a set-piece is not given a second plaque")
	if not await _boot("", "combat", 0, "the_sunken_road"):
		_check(false, "the Sunken Road builds its HUD")
		_finish(1)
		return
	_check(String(combat._sp_id) == "the_sunken_road", "the set-piece is live")
	_check(combat._sp_plaque != null and is_instance_valid(combat._sp_plaque),
		"its objective plaque is built")
	_check(combat._passive_banner == null
			or not is_instance_valid(combat._passive_banner),
		"no encounter rule plaque is hung beside it")

	# ── F. the ordinary case the guard change must not have moved ────────────
	print("-- F. a plain encounter passive still posts exactly as before")
	if not await _boot("elemental_nexus", "combat", 2):
		_check(false, "the Storm Made Flesh reaches the first player turn")
		_finish(1)
		return
	_check(combat._boss_phases.is_empty(), "an ordinary hold has no phases")
	_check(not combat._siege_active, "and no siege")
	_check(combat._passive_banner != null and is_instance_valid(combat._passive_banner)
			and combat._passive_banner.visible,
		"its plaque is built and visible")
	_check(_plaque_text() == String(
		EDB.get_encounter("elemental_nexus").get("passive_desc", "")),
		"stating the encounter's own rule")

	_finish(0 if _fails == 0 else 1)


func _finish(code: int) -> void:
	if _fails == 0 and code == 0:
		print("[phase-plaque] ALL PASS")
	else:
		print("[phase-plaque] %d FAILURE(S)" % _fails)
	_done = true
	quit(code)
