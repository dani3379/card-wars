extends Node
## _probe_beat_spacing.gd — THE FORBIDDEN BAND, GATED (2026-07-29).
##
##   Godot_v4.6.2-stable_win64_console.exe --headless --path "D:\Godot" \
##       res://tools/_probe_beat_spacing.tscn
##
## This is the probe docs/COMBAT_LEGIBILITY_20260728.md §8 asked for and §10
## recorded as "still owed": nothing gated a future change from putting combat
## beats back into the 100-500 ms band.
##
## ── THE RULE ─────────────────────────────────────────────────────────────────
## Two measured perceptual limits bracket every beat in the clash (§1, with
## primary sources in §9):
##
##   * Perceived CAUSALITY collapses past ~100 ms. Event pairs judged causal
##     average 66.9 ms apart (SD 29.2); pairs judged non-causal average 164.7 ms
##     (SD 27.2). — Straube & Chatterjee, Front. Hum. Neurosci. 4:28, 2010.
##   * Two events the player must SEPARATELY register need >=500 ms. Between
##     ~200 and ~500 ms the attentional blink reliably eats the second one.
##     — Dux & Marois, Atten. Percept. Psychophys. 71(8), 2009.
##
## So 100-500 ms is the one place to avoid: too slow to FUSE into a single
## perceived event, too fast to REGISTER as two. A beat should be either
## <=~70 ms (fuse it, then hold) or >=~500 ms (serialize it).
##
## ── WHY THIS IS AN ALLOW-LIST AND NOT A FLAT BAN ──────────────────────────────
## Some beats belong in the band ON PURPOSE. A strike and its own damage number
## are ONE event, and the hold on that fused event is legitimately 150-230 ms —
## the band fighting games have shipped for thirty years. Banning the whole
## region outright would fail the very constants the legibility pass DESIGNED.
##
## So each in-band constant carries an explicit waiver with a written reason and
## a PINNED VALUE. That pin is the teeth:
##
##   * a NEW constant that lands in the band with no waiver         -> FAIL
##   * a WAIVED constant whose value drifts off its pin             -> FAIL
##   * a waiver for a constant that no longer exists                -> FAIL
##
## A future edit therefore has to open this file and say what it is doing. It
## cannot drift in.
##
## Waivers are honestly labelled by KIND:
##   "fusion"       — in-band by design; this beat is the internal duration of
##                    ONE perceived event, not the gap between two.
##   "grandfathered"— in-band, NOT justified by the perceptual model, inherited
##                    from before the legibility pass and not yet restructured.
##                    These are printed as a DEBT LIST at the end of the run.
##                    Adding a new one is a decision, not a default.
##
## ── ALSO ENFORCED ─────────────────────────────────────────────────────────────
##   * _impact_hold(damage, lethal) stays inside [IMPACT_HOLD_MIN, IMPACT_HOLD_MAX]
##     for damage 0..99, is monotonic, and a lethal blow always takes the ceiling.
##   * _lane_will_strike() is false on an empty column and true on a column with a
##     live untapped attacker — that predicate is what skips the dwell on a lane
##     where nothing happens (a pause on an empty lane is the same mistake as a
##     caption naming an empty beat).
##   * _downed_count() counts dead-but-still-STANDING bodies while
##     Card2D.defer_deaths holds the corpse — "did this lane produce a kill?"
##     is asked before the flush runs, so it cannot depend on the array emptying.
##   * The structural invariants between beats (kill punctuates longer than a
##     plink, LUNGE_APEX stays DERIVED, the impact band sits inside SF-IV's).
##
## ── HOUSE TRAPS OBSERVED ──────────────────────────────────────────────────────
##   * Readiness is gated on `round_number >= 1`. Phase.PLAYER_TURN is enum 0 —
##     the uninitialised default — so polling on phase alone reports ready before
##     the fight has begun.
##   * `_lane_dwell()` and `_round_beat()` DELIBERATELY return early in headless.
##     This probe does not fight that: it asserts the bail is still there by source
##     inspection (removing it would make every headless probe run sleep through
##     thousands of rounds) and tests the PREDICATES that decide whether a dwell is
##     owed, which are pure and run identically headless.
##   * The NET bail is NOT symmetric with the headless one (2026-08-04).
##     `_round_beat` still takes it, for a structural reason: `_start_round` is
##     called from CombatNet's plain `void` turn-machine entry points and must not
##     become a coroutine there. `_lane_dwell` no longer does — skirmish now paces
##     its clash exactly as solo does, with each peer running the beat against its
##     OWN Clash Pause dial. Both halves are asserted below.

const COMBAT_SCENE := "res://scenes/combat.tscn"

## The condemned region, in seconds.
const BAND_LO := 0.100
const BAND_HI := 0.500

## The census. Every combat pacing constant the clash actually spends. A constant
## reachable from Combat that is NOT in this list is invisible to the gate, so
## adding a beat means adding a row here — that is deliberate.
const CENSUS: Array[String] = [
	"LUNGE_APEX", "POST_HIT_BEAT", "HITSTOP_BEAT", "KILLING_BLOW_HOLD",
	"DEATH_BEAT", "ROUND_BEAT", "LANE_DWELL", "LANE_DWELL_KILL",
	"IMPACT_HOLD_MIN", "IMPACT_HOLD_MAX",
	"COMBAT_PAUSE_SHORT", "COMBAT_PAUSE_MEDIUM",
]

## name -> {value, kind, why}
## `value` is the pin. Change the constant, and you must change the pin here and
## write down why. See the header for what "fusion" and "grandfathered" mean.
const WAIVERS: Dictionary = {
	"LUNGE_APEX": {
		"value": 0.18, "kind": "fusion",
		"why": "The anticipation + drive of ONE swing, not the gap between two events. "
			+ "The impact beat lands at the lunge tween's apex by construction; the "
			+ "player reads a single strike, not a pull-back followed by a hit.",
	},
	"IMPACT_HOLD_MIN": {
		"value": 0.15, "kind": "fusion",
		"why": "Floor of the hold on the FUSED strike-plus-its-damage-number event. "
			+ "Street Fighter IV ships 9/11/13 frames (150/183/217 ms) by attack "
			+ "strength and stays readable at 60 fps. This is the duration of one "
			+ "event, not a separation beat.",
	},
	"IMPACT_HOLD_MAX": {
		"value": 0.23, "kind": "fusion",
		"why": "Ceiling of the same fused hold, and the value a LETHAL blow always "
			+ "takes. Sakurai's rule: scale hitstop with damage, but CAP it.",
	},
	"DEATH_BEAT": {
		"value": 0.21, "kind": "fusion",
		"why": "Chosen 2026-07-28 (was 0.10) so a mass grave reads as ONE event whose "
			+ "bodies are still COUNTABLE. Corpses were falling every 116 ms, which "
			+ "neither fused nor separated. Deliberately NOT pushed past 500 ms — "
			+ "eight sequential half-second deaths would be a cutscene.",
	},
	"LANE_DWELL": {
		"value": 0.30, "kind": "fusion",
		"why": "An EYE-REST on a resolved column, not a gap between two events. "
			+ "Scene-viewing fixations run 200-300 ms and you must budget 250-350 ms "
			+ "per location you actually want read (Rayner 2009). The lane's whole "
			+ "exchange is the one event; this is how long it stays on screen. Its "
			+ "kill-bearing sibling LANE_DWELL_KILL is the real separation beat and "
			+ "clears 500 ms.",
	},
	"ROUND_BEAT": {
		"value": 0.20, "kind": "fusion",
		"why": "Separates the round-open's VISIBLE GROUPS, which are stages of ONE "
			+ "state assembling (ticks, then grants, then intents) rather than "
			+ "independently-registered events. Raised 0.12 -> 0.20 in the same pass; "
			+ "~40 state changes were landing on a single frame.",
	},
	"POST_HIT_BEAT": {
		"value": 0.13, "kind": "grandfathered",
		"why": "Breath after an ordinary hit before the next attacker. Predates the "
			+ "legibility pass and is NOT justified by the model: at 130 ms it is "
			+ "squarely in the dead zone. Superseded at the main strike site by "
			+ "_impact_hold, but still spent by the Swift, sniper and retaliation "
			+ "paths. Tracked as remaining debt, pinned so it cannot move unnoticed.",
	},
	"HITSTOP_BEAT": {
		"value": 0.26, "kind": "grandfathered",
		"why": "Punctuation after a kill or heavy blow. Same story as POST_HIT_BEAT — "
			+ "the strike path now calls _impact_hold instead, but ~8 other sites "
			+ "still await this. Remaining debt.",
	},
	"COMBAT_PAUSE_SHORT": {
		"value": 0.15, "kind": "grandfathered",
		"why": "Generic short punctuation outside the clash proper (phase seams). "
			+ "Not derived from anything; inherited. Remaining debt.",
	},
	"COMBAT_PAUSE_MEDIUM": {
		"value": 0.30, "kind": "grandfathered",
		"why": "Generic medium punctuation (Swift phase seams, reinforcement beat). "
			+ "Not derived from anything; inherited. Remaining debt.",
	},
}

var _fails := 0
var _debt: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		printerr("[beat] WATCHDOG — never finished")
		get_tree().quit(1))

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
	# HOUSE TRAP: Phase.PLAYER_TURN is enum 0, which is also the uninitialised
	# default — polling on phase alone reports ready before anything has happened.
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")

	_test_band(combat)
	_test_invariants(combat)
	_test_impact_hold(combat)
	_test_lane_will_strike(combat)
	_test_downed_count(combat)
	_test_bails_intact()

	print("")
	if _debt.is_empty():
		print("[beat] no grandfathered beats remain — every in-band constant is a fusion beat.")
	else:
		print("[beat] REMAINING DEBT — in-band, waived, NOT justified by the perceptual model:")
		for d in _debt:
			print("[beat]   %s" % d)
	print("[beat] %s" % ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


# ══ 1. THE BAND ═══════════════════════════════════════════════════════════════

func _test_band(combat) -> void:
	print("")
	print("[beat] — the 100-500 ms band: every combat beat constant, censused")
	var seen := {}
	for name in CENSUS:
		var v: float = _const_of(combat, name)
		seen[name] = true
		if v < 0.0:
			_check(false, "%s: not reachable from Combat (renamed or removed?)" % name)
			continue
		var in_band: bool = v > BAND_LO and v < BAND_HI
		if not in_band:
			_check(true, "%-20s %6.0f ms  — outside the band (%s)" % [name, v * 1000.0,
				"fuses" if v <= BAND_LO else "serializes"])
			if WAIVERS.has(name):
				_check(false, "%s is no longer in the band — its waiver is now stale, delete it" % name)
			continue
		if not WAIVERS.has(name):
			_check(false, "%-20s %6.0f ms  — IN THE FORBIDDEN BAND with no waiver. "
				% [name, v * 1000.0]
				+ "Either move it out (<=100 ms to fuse, >=500 ms to serialize) or add "
				+ "a WAIVERS entry in tools/_probe_beat_spacing.gd saying why it belongs "
				+ "inside one perceived event.")
			continue
		var w: Dictionary = WAIVERS[name]
		var pin: float = float(w["value"])
		_check(is_equal_approx(v, pin),
			"%-20s %6.0f ms  — waived (%s), pin matches (%.0f ms)"
				% [name, v * 1000.0, String(w["kind"]), pin * 1000.0])
		if not is_equal_approx(v, pin):
			printerr("        the constant moved to %.0f ms but the waiver still pins %.0f ms. "
				% [v * 1000.0, pin * 1000.0]
				+ "Update the pin AND the reason, or move the beat out of the band.")
		if String(w["kind"]) == "grandfathered":
			_debt.append("%-20s %.0f ms — %s" % [name, v * 1000.0, String(w["why"]).left(96)])

	# No stale waivers: every waived name must still be censused.
	for name in WAIVERS:
		_check(seen.has(String(name)),
			"waiver '%s' still names a censused constant (no dead waivers)" % name)


# ══ 2. STRUCTURAL INVARIANTS ══════════════════════════════════════════════════

func _test_invariants(combat) -> void:
	print("")
	print("[beat] — structural invariants between the beats")

	# Combat's constants are ALIASES of Motion's. Drift here means the conductor
	# and the orchestra are on different clocks (the exact bug Motion.gd was
	# extracted to end).
	_check(is_equal_approx(_const_of(combat, "LUNGE_APEX"), Motion.LUNGE_APEX)
			and is_equal_approx(_const_of(combat, "POST_HIT_BEAT"), Motion.POST_HIT_BEAT)
			and is_equal_approx(_const_of(combat, "HITSTOP_BEAT"), Motion.HITSTOP_BEAT),
		"Combat's beat constants still alias Motion's (one clock, not two)")

	# LUNGE_APEX must stay DERIVED — hardcoding it is how it drifted off the
	# tween's real apex before 2026-07-16.
	_check(is_equal_approx(Motion.LUNGE_APEX,
			Motion.LUNGE_ANTICIPATION + Motion.LUNGE_STRIKE),
		"LUNGE_APEX is DERIVED from the tween's own phases, never hardcoded")

	var hold_min: float = _const_of(combat, "IMPACT_HOLD_MIN")
	var hold_max: float = _const_of(combat, "IMPACT_HOLD_MAX")
	_check(hold_min < hold_max, "IMPACT_HOLD_MIN < IMPACT_HOLD_MAX")
	_check(hold_min >= 0.150 and hold_max <= 0.230,
		"the impact hold band stays inside the shipped 150-230 ms window (%.0f-%.0f ms)"
			% [hold_min * 1000.0, hold_max * 1000.0])

	var dwell: float = _const_of(combat, "LANE_DWELL")
	var dwell_kill: float = _const_of(combat, "LANE_DWELL_KILL")
	_check(dwell >= 0.250 and dwell <= 0.350,
		"LANE_DWELL sits in Rayner's 250-350 ms per-location budget (%.0f ms)"
			% [dwell * 1000.0])
	_check(dwell_kill >= BAND_HI,
		"LANE_DWELL_KILL clears 500 ms — a corpse is an event the player must "
			+ "register SEPARATELY (%.0f ms)" % [dwell_kill * 1000.0])
	_check(dwell_kill > dwell, "a lane that produced a corpse holds longer than one that did not")

	_check(_const_of(combat, "DEATH_BEAT") >= hold_min,
		"DEATH_BEAT is at least the ordinary impact hold — a death is never the "
			+ "shortest beat in the file (it was, at 100 ms, before 2026-07-28)")
	_check(_const_of(combat, "HITSTOP_BEAT") > _const_of(combat, "POST_HIT_BEAT"),
		"a kill / heavy blow punctuates longer than an ordinary plink")
	_check(Motion.KILLING_BLOW_HOLD >= 2.0 * Motion.HITSTOP_BEAT,
		"KILLING_BLOW_HOLD is a different EVENT CLASS from an ordinary hitstop "
			+ "(%.0f ms vs %.0f ms)" % [Motion.KILLING_BLOW_HOLD * 1000.0,
			Motion.HITSTOP_BEAT * 1000.0])


# ══ 3. _impact_hold ═══════════════════════════════════════════════════════════

func _test_impact_hold(combat) -> void:
	print("")
	print("[beat] — _impact_hold(damage, lethal) stays inside its own band")
	var lo: float = _const_of(combat, "IMPACT_HOLD_MIN")
	var hi: float = _const_of(combat, "IMPACT_HOLD_MAX")

	var out_of_band := -1
	var non_monotonic := -1
	var prev: float = -1.0
	for dmg in range(0, 100):
		var h: float = combat._impact_hold(dmg, false)
		if (h < lo - 0.0001 or h > hi + 0.0001) and out_of_band < 0:
			out_of_band = dmg
		if h < prev - 0.0001 and non_monotonic < 0:
			non_monotonic = dmg
		prev = h
	_check(out_of_band < 0,
		"damage 0..99 always holds inside [%.0f, %.0f] ms%s" % [lo * 1000.0, hi * 1000.0,
			"" if out_of_band < 0 else "  (first breach at damage=%d)" % out_of_band])
	_check(non_monotonic < 0,
		"the hold never SHRINKS as damage grows%s" % [
			"" if non_monotonic < 0 else "  (first inversion at damage=%d)" % non_monotonic])

	# A negative amount is a real possibility at a call site that passes a delta.
	_check(combat._impact_hold(-5, false) >= lo,
		"a negative damage value cannot produce a sub-floor hold")

	# The lethal contract: always the ceiling, at any damage.
	var lethal_ok := true
	for dmg in [0, 1, 5, 40, 99]:
		if not is_equal_approx(combat._impact_hold(int(dmg), true), hi):
			lethal_ok = false
	_check(lethal_ok,
		"a LETHAL blow always takes the ceiling (%.0f ms) — it is the beat the "
			% [hi * 1000.0] + "player most needs to attribute, and the corpse is about to leave")

	# The band must actually be SPENT, not merely computed. One call site today
	# (_creature_attacks_creature); zero would mean the two-valued 130/260 split
	# quietly came back.
	var src: String = load("res://scripts/scenes/Combat.gd").source_code
	_check(src.count("_short_pause(_impact_hold(") >= 1,
		"_impact_hold is actually AWAITED at a strike site (not just defined)")


# ══ 4. _lane_will_strike — the empty-lane skip ════════════════════════════════

func _test_lane_will_strike(combat) -> void:
	print("")
	print("[beat] — _lane_will_strike gates the dwell (no pause on a dead lane)")
	_clear_board(combat)

	_check(not combat._lane_will_strike(0, combat.ROW_FRONT),
		"an EMPTY column will not strike (so the spotlight never dwells on it)")

	var mine = _put(combat, false, combat.ROW_FRONT, 0, 3, 5)
	if _check(mine != null, "fixture: one live untapped 3/5 in column 0"):
		_check(combat._lane_will_strike(0, combat.ROW_FRONT),
			"a column with a live untapped attacker WILL strike")

		# Every guard at the top of _resolve_column_attack must be mirrored here,
		# or the dwell and the resolution disagree about whether the lane is live.
		mine.has_attacked_this_turn = true
		_check(not combat._lane_will_strike(0, combat.ROW_FRONT),
			"a body that already swung this turn does not re-arm the dwell")
		mine.has_attacked_this_turn = false

		mine.state.ready_to_swing = false
		_check(not combat._lane_will_strike(0, combat.ROW_FRONT),
			"a MUSTERING body does not arm the dwell (can_attack() is the shared gate)")
		mine.state.ready_to_swing = true

	# The enemy side arms it too — the predicate is about the COLUMN, not about us.
	_clear_board(combat)
	var theirs = _put(combat, true, combat.ROW_FRONT, 2, 2, 2)
	if _check(theirs != null, "fixture: a live enemy body alone in column 2"):
		_check(combat._lane_will_strike(2, combat.ROW_FRONT),
			"an enemy-only column still arms the dwell")
		_check(not combat._lane_will_strike(1, combat.ROW_FRONT),
			"...and its neighbours stay silent")

	# The back rank is a separate column-visit; row must be honoured.
	_check(not combat._lane_will_strike(2, combat.ROW_BACK),
		"the BACK rank of an occupied front column does not arm on the front body")

	# _rank_will_strike is the caption's gate and must agree with its lanes.
	_check(combat._rank_will_strike(combat.ROW_FRONT)
			and not combat._rank_will_strike(combat.ROW_BACK),
		"_rank_will_strike agrees with its lanes (gates THE FRONT/BACK RANK caption)")

	# The dwell must be WIRED to the predicate, not merely adjacent to it.
	var src: String = load("res://scripts/scenes/Combat.gd").source_code
	var body := _fn_body(src, "_clash_lane_pass")
	_check(body.contains("_lane_will_strike(") and body.contains("_lane_dwell("),
		"_clash_lane_pass gates its _lane_dwell on _lane_will_strike")
	_check(body.contains("_downed_count()"),
		"_clash_lane_pass reads _downed_count to decide the longer kill dwell")


# ══ 5. _downed_count — corpses that are still standing ════════════════════════

func _test_downed_count(combat) -> void:
	print("")
	print("[beat] — _downed_count sees dead-but-still-standing bodies")
	_clear_board(combat)
	_check(combat._downed_count() == 0, "a clean board has no downed bodies")

	var victim = _put(combat, true, combat.ROW_FRONT, 0, 1, 3)
	var bystander = _put(combat, true, combat.ROW_FRONT, 1, 1, 3)
	if not _check(victim != null and bystander != null, "fixture: two enemy 1/3 bodies"):
		return
	_check(combat._downed_count() == 0, "two healthy bodies read as zero downed")

	# THE POINT: during the clash Card2D.defer_deaths holds the corpse ON THE
	# BOARD, so "did this lane produce a kill?" cannot be answered by the array
	# emptying — the flush has not run yet. _downed_count is that answer.
	var was_defer: bool = Card2D.defer_deaths
	Card2D.defer_deaths = true
	victim.take_damage(99)
	_check(is_instance_valid(victim)
			and combat._row_array(true, combat.ROW_FRONT)[0] == victim,
		"defer_deaths keeps the corpse standing in its slot")
	_check(int(victim.current_hp) <= 0, "...at or below 0 HP")
	_check(combat._downed_count() == 1,
		"_downed_count counts the deferred corpse (this is what earns LANE_DWELL_KILL)")

	bystander.take_damage(99)
	_check(combat._downed_count() == 2, "a second corpse in the same clash also counts")
	Card2D.defer_deaths = was_defer
	_clear_board(combat)


# ══ 6. THE DELIBERATE BAILS ═══════════════════════════════════════════════════

func _test_bails_intact() -> void:
	print("")
	print("[beat] — the deliberate bails: headless everywhere, NET only where it is structural")
	var src: String = load("res://scripts/scenes/Combat.gd").source_code
	var net_src: String = load("res://scripts/net/CombatNet.gd").source_code

	# THE HEADLESS BAIL is the one that must never go: it is the reason a headless
	# probe run does not sleep through thousands of rounds. Removing it would not
	# fail an assertion anywhere else — it would just make every probe in tools/ 10x
	# slower and eventually trip their watchdogs. So it is gated here, explicitly.
	for fn in ["_lane_dwell", "_lane_dwell_minor", "_round_beat"]:
		var body := _fn_body(src, fn)
		_check(body != "", "%s exists" % fn)
		_check(body.contains("headless"),
			"%s still returns early HEADLESS (probe runs have nothing to look at)" % fn)

	# THE NET BAIL WAS DIFFERENT, AND IT IS GONE FROM THE DWELLS (2026-08-04).
	#
	# `_round_beat` keeps its net bail for a STRUCTURAL reason: `_start_round` is
	# called from CombatNet's plain `void` turn-machine entry points, so letting it
	# suspend would push a coroutine through the hardest-to-verify layer in the
	# project. That reason is still true, so it is still asserted.
	#
	# `_lane_dwell` bailed for a WEAKER reason ("the turn machine's clocks are not
	# ours"), and it produced the gap this pass closed: the campaign clash was a
	# serialized, spotlit, per-column read and the skirmish clash of the same
	# creatures was one undifferentiated burst. Nothing in the net layer is on a
	# clock — no turn timer exists in NetMatch — so the dwell now runs in both modes
	# and each peer paces to its OWN Clash Pause dial. Asserted from the other side
	# now: the skirmish clash must go through the shared paced unit, and the pacing
	# must reach the watching peer as a decision rather than as the host's seconds.
	var rb := _fn_body(src, "_round_beat")
	_check(rb.contains("_is_net()"),
		"_round_beat still returns early in NET (_start_round must not suspend there)")
	var ld := _fn_body(src, "_lane_dwell")
	_check(not ld.contains("_is_net()"),
		"_lane_dwell no longer bails in NET (skirmish paces its clash like solo)")
	var clash := _fn_body(net_src, "_net_run_clash")
	_check(clash.contains("_clash_lane_pass"),
		"the net clash resolves through the SHARED paced column unit")
	_check(clash.contains("_cleanup_dead_paced"),
		"the net clash flushes its corpses on the shared paced beats")
	_check(clash.contains("_post_clash_ledger"),
		"the net clash closes with the same one-line casualty ledger solo prints")
	var lp := _fn_body(src, "_clash_lane_pass")
	_check(lp.contains("_net_log_dwell"),
		"the dwell CHOICE is logged for the watching peer (never the host's seconds)")
	var fc := _fn_body(src, "_focus_combat_lane")
	_check(fc.contains("_net_log_focus"),
		"the spotlight column is logged for the watching peer")


# ══ HELPERS ═══════════════════════════════════════════════════════════════════

## Read a const off the live Combat instance. Returns -1.0 when the name is gone,
## which the census reports as a failure rather than silently skipping.
func _const_of(combat, name: String) -> float:
	if name == "KILLING_BLOW_HOLD":
		return Motion.KILLING_BLOW_HOLD
	var v = combat.get(name)
	if v == null:
		return -1.0
	return float(v)


## Slice one function out of a script's source. Both markers are "\nfunc " so a
## local lambda or a nested string cannot end the slice early.
func _fn_body(src: String, fn_name: String) -> String:
	var head: int = src.find("func %s(" % fn_name)
	if head < 0:
		return ""
	var tail: int = src.find("\nfunc ", head + 1)
	if tail < 0:
		tail = src.length()
	return src.substr(head, tail - head)


func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return ""


## Fixture teardown, not a game event — bypasses _die() on purpose so on_death
## chains never contaminate the next block.
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
	# Tokens arrive MUSTERING (ready_to_swing defaults false). These blocks are
	# about the strike predicates, so stand them up by hand.
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
