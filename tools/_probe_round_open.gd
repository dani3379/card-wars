extends Node
## _probe_round_open.gd — the round-open pacing guard and the tutorial ladder.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_round_open.tscn
##
## Two things landed on 2026-08-01 that are cheap to get subtly wrong and
## expensive to notice:
##
##   1. `_round_beat(state_before)` now SKIPS its 200 ms pause when the group it
##      was meant to close produced no visible change. The failure mode is a
##      guard that is too eager — a beat that swallows itself while regen ticks,
##      a keystone grant or an encounter passive really did fire — and that is
##      invisible in play (the round just reads slightly worse). So this probe
##      asserts the SIGNAL, `_round_visible_state()`, moves for each of the five
##      channels a round-open group can speak through, and holds still otherwise.
##
##   2. The tutorial ladder was re-sequenced onto the rounds where each tip's
##      subject actually exists, and `_show_tutorial_tip` became first-claim-wins
##      returning a bool. The failure mode there is a tip that loses the channel
##      but still stamps its once-EVER UserSettings flag, which costs a new
##      player a rule permanently. Asserted directly.
##
## Headless-safe: _round_beat bails on headless before it can pause, so this
## exercises the STATE function rather than the wall-clock, which is the part
## that decides.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0
var _saved_flags := {}


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_fails += 1


func _ready() -> void:
	# Tutorials are once-EVER on the profile, so a machine that has already seen
	# them would make every ladder assertion below vacuous. Reset first — and put
	# them back at the end: these are the developer's own settings, and a probe
	# that spends them silently re-teaches every tip on their next run.
	# `first_battle_tutorial_complete` MUST be in this list (2026-08-04). It is not a
	# tip flag but a GATE: `_start_round`'s round-1 arm only offers the muster tip
	# once the first-battle walkthrough is done, and `reset_tutorials()` clears it
	# along with everything else. Saving the six tips but not the gate made this
	# probe SELF-POISONING — it passed on a profile that had finished the
	# walkthrough and failed on every run after its own first, because it had spent
	# the flag itself. The failure looked exactly like a regression in the ladder.
	for k in ["muster_tutorial_seen", "intents_tutorial_seen", "pile_tutorial_seen",
			"banking_tutorial_seen", "combat_model_tutorial_seen",
			"dismiss_tutorial_seen", "first_battle_tutorial_complete"]:
		_saved_flags[k] = UserSettings.get(k)
	UserSettings.reset_tutorials()
	# The ladder under test starts at the MUSTER tip, which round 1 only offers once
	# the first-battle walkthrough is behind the player. Stand it down for the run so
	# the probe measures the ladder rather than the walkthrough that gates it.
	UserSettings.first_battle_tutorial_complete = true

	RunState.start_new_run("stalwart", 0, 4242)
	var enc_id := ""
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			enc_id = String(id)
			break
	_check(enc_id != "", "found an act-1 combat fixture (%s)" % enc_id)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = enc_id
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame
	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Gate on round + hand, never on phase — PLAYER_TURN is enum 0, which is also
	# the uninitialised default (the readiness trap _probe_muster_delay documents).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")
	_check(not combat._hand.is_empty(), "the opening hand was dealt")
	# The muster tip is posted inside _start_round and lives 7 s. Read its latch,
	# not the Label, for the ladder assertions below — the latch is permanent.

	_test_visible_state(combat)
	_test_tutorial_ladder(combat)

	for k in _saved_flags:
		UserSettings.set(k, _saved_flags[k])
	UserSettings.save()

	if _fails == 0:
		print("[round-open] ALL PASS")
	else:
		print("[round-open] %d FAILURES" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _test_visible_state(combat) -> void:
	print("── the round-beat signal ──")

	# The whole premise of the skip: on a quiet board the state is stable, so a
	# group that does nothing is indistinguishable from no group at all.
	var a: Array = combat._round_visible_state()
	var b: Array = combat._round_visible_state()
	_check(a == b, "an untouched board reads the same state twice (the skip case)")

	# Round 1 is the case the change was built for: TAKE THE FIELD leaves BOTH
	# boards empty, so every start-of-round group iterates nothing.
	_check(combat._all_creatures_both_sides().is_empty(),
		"round 1 really does open with an empty board (TAKE THE FIELD)")

	# ── Channel 1: a banner. Catches an encounter passive / boss phase / scripted
	# beat that SPOKE without moving a number.
	var before: Array = combat._round_visible_state()
	combat._show_info("probe: a line the player would read")
	_check(combat._round_visible_state() != before, "a banner moves the state")

	# ── Channel 2: a floating number (damage / heal / gold).
	before = combat._round_visible_state()
	combat.spawn_floating_number(Vector2(100, 100), "-3", Color.RED, false)
	_check(combat._round_visible_state() != before, "a floating number moves the state")

	# ── Channel 3: a keyword / trigger / rider chip. This is the one that carries
	# the keystone grants — warden HOLD and the Volley change no HP at all.
	before = combat._round_visible_state()
	combat.spawn_keyword_callout(Vector2(100, 100), "HOLD", Color.WHITE, null)
	_check(combat._round_visible_state() != before, "a keyword callout moves the state")

	# ── Channel 4: a ring (the grace waves and every combat impact ride this).
	before = combat._round_visible_state()
	combat._spawn_vfx_ring(Vector2(100, 100), Color.WHITE, 30.0, 2.0, 0.3)
	_check(combat._round_visible_state() != before, "a vfx ring moves the state")

	# ── Channel 5: the board itself — an arrival, then a stat change on it.
	# This is the standing layer the one-shot funnels do not describe (an ATK ramp
	# that fires silently every round still has to be paced apart from the intents).
	before = combat._round_visible_state()
	combat.summon_token(2, 3, 0, false, combat.ROW_FRONT)   # returns void
	var body = combat._player_field[0]
	_check(body != null and is_instance_valid(body), "fixture: a body on the board")
	_check(combat._round_visible_state() != before, "an arrival moves the state")

	if body != null and is_instance_valid(body):
		before = combat._round_visible_state()
		body.current_hp -= 1
		_check(combat._round_visible_state() != before, "an HP change moves the state")

		before = combat._round_visible_state()
		body.persistent_atk_buff += 1
		_check(combat._round_visible_state() != before, "an ATK change moves the state")

		# ...and holds still again once nothing further happens, which is what
		# makes the comparison a test rather than a coin flip.
		before = combat._round_visible_state()
		_check(combat._round_visible_state() == before,
			"a populated board still reads stable when nothing happens")

	# The faces. An encounter passive on a timer bills these directly, and on an
	# empty board that is the ONLY thing it can move — which is exactly why the
	# guard could not have been `round_number == 1`.
	before = combat._round_visible_state()
	combat.player_hp -= 1
	_check(combat._round_visible_state() != before, "the player's face moves the state")
	before = combat._round_visible_state()
	combat.enemy_hp -= 1
	_check(combat._round_visible_state() != before, "the foe's face moves the state")


func _test_tutorial_ladder(combat) -> void:
	print("── the tutorial ladder ──")

	# Round 1's tip is the MUSTER — the beat nothing on screen accounts for.
	# It is the only tip that may fire on a round with no enemy line, because it
	# is the only one whose subject IS the absence of one.
	# ASKED THROUGH `lesson_seen`, not through Combat's old per-fight bools.
	# Those bools stopped being the gate when the TutorialDB registry landed
	# (2026-09-10) — they were write-only mirrors, and this probe was the last
	# thing reading three of them, which is the only reason they survived the
	# cleanup that deleted the other three. The registry IS the state; the
	# neighbouring assertions below already asked it this way.
	_check(UserSettings.lesson_seen("muster"),
		"round 1 taught the MUSTER (the round that has no clash)")
	_check(UserSettings.muster_tutorial_seen,
		"...and stamped its once-ever flag")
	_check(not UserSettings.lesson_seen("intents"),
		"round 1 did NOT teach the intents (no enemies, no badges, no chips)")
	_check(not UserSettings.intents_tutorial_seen,
		"...and did not burn the intents flag on a tip nobody could see")
	_check(not UserSettings.lesson_seen("piles"), "round 1 did NOT teach the piles")

	# FIRST CLAIM WINS, and a loser must not be spent. This is the regression the
	# bool return exists to prevent: before it, the last writer took the Label and
	# every earlier tip died having already written its UserSettings flag.
	#
	# Posted fresh rather than reusing round 1's tip: a tip releases the channel on
	# a 7 s timer, and the boot poll above can outlast that. Testing "is round 1's
	# tip still up?" would be testing the harness's own latency.
	combat._tutorial_tip_live = ""
	var held := "probe: the tip that claimed the channel"
	_check(combat._show_tutorial_tip(held), "a tip takes a free channel")
	_check(combat._tutorial_tip_live == held, "...and is recorded as the live one")
	var took: bool = combat._show_tutorial_tip("probe: a second tip, same round")
	_check(not took, "a second tip is REFUSED while one is live")
	_check(combat._tutorial_tip_live == held, "...and the live tip is untouched")

	# The loser retries later rather than being lost: the channel releases on its
	# own timer, and every _maybe_show_* is re-attempted on later rounds.
	combat._tutorial_tip_live = ""
	took = combat._show_tutorial_tip("probe: the same tip, a later round")
	_check(took, "once the channel frees, the next tip takes it")
	combat._tutorial_tip_live = ""

	# The intents tip is now round 2's — the first round with a line to read.
	combat._maybe_show_intents_tutorial()
	_check(UserSettings.lesson_seen("intents") and UserSettings.intents_tutorial_seen,
		"the intents tip lands when it wins the channel")
