extends Node
## _probe_pilot.gd — THE HUMAN PILOT: plays the game through the mouse.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_pilot.tscn
##   Godot.exe            --path "D:\Godot" res://tools/_probe_pilot.tscn -- --shots
##
## Options (after a bare `--`):
##   --seed=N        run seed (default 20260915)
##   --max-sec=N     wall-clock budget, default 600
##   --max-nodes=N   map stops to visit before stopping, default 40
##   --coach         leave coaching ON (default: OFF, i.e. a returning player)
##   --slow          real pacing (default: anim_speed 3, clash dwell 0.25)
##   --shots         save a PNG at every finding (WINDOWED ONLY — headless never
##                   posts a frame, so `get_image()` would park forever)
##   --trace         print every action the pilot takes (what it pressed, where)
##   --stats-reset   start a fresh per-card ledger (do this after a balance change)
##   --hurry         straight-line teleports instead of human motion (faster
##                   soaks, strictly less faithful — see THE HAND IS HUMAN)
##
## ── WHY THIS EXISTS, AND WHAT IT IS NOT ───────────────────────────────────
## Every other probe in this harness calls the game's functions. `_probe_autorun`
## soaks combat by calling `_on_card_played`; `_probe_card_play` asserts the play
## gesture's bookkeeping the same way; `_probe_campaign_walk` walks the map by
## calling `visit_node`. All of them are correct and all of them share one blind
## spot: **they never touch the input pipeline.** A card that cannot be picked up,
## a slot that cannot be dropped on, a button with a dead scrim parked over it, a
## drag whose release lands one pixel under the play threshold — every one of
## those ships green through the entire existing suite, because no probe has ever
## been the thing holding the mouse.
##
## This one holds the mouse. It moves a synthetic cursor, presses, drags and
## releases, and lets GODOT decide what receives each event. It knows nothing
## about which node "should" get the click; it asks the engine, the same way the
## real cursor does. When the engine's answer is not the control the pilot aimed
## at, that IS the finding — it is the literal mechanism behind the most common
## bug report in existence, "the button doesn't work".
##
## It is a BUG FINDER, not a gate. It does not assert a correct game; it plays one
## and reports what it could not do. Treat its output as leads to verify, and read
## COVERAGE at the bottom of the report before believing an empty finding list —
## a pilot that never reached act 2 has said nothing whatsoever about act 2.
##
## ── THE THREE MECHANICS THAT COST A REBUILD EACH (all verified, 2026-09-15) ──
##
## 1. `Input.parse_input_event()` IS A NO-OP HEADLESS. It hands the event to the
##    dispatch hook that a real DisplayServer installs; the headless one never
##    installs it, so the event is accepted and silently dropped. A pilot built on
##    it reports a perfectly clean run having pressed nothing at all — the exact
##    false green this file exists to avoid. Measured: pressed=false on every one
##    of five methods but the one below.
##
## 2. THE COORDINATES MUST BE CANVAS-LOCAL, so `push_input(ev, true)`. The
##    headless root window boots **64x64 and REJECTS `root.size =`**, while
##    `get_visible_rect()` reports the 1600x900 project canvas. `push_input(ev,
##    false)` runs the event through `get_final_transform().affine_inverse()` —
##    measured as a 0.04 scale — which throws every click ten thousand pixels off
##    the edge of the world. Passing `true` skips that transform, and canvas space
##    is already the space every `get_global_rect()` in this codebase reports, so
##    the pilot speaks one coordinate system headless AND windowed.
##
## 3. A CONTROL IS READ THE WAY A PLAYER READS IT. `Button.text` is EMPTY on every
##    button in the main menu — `MainMenu._make_menu_button` builds a frameless
##    Button whose word lives in a descendant Label. The road screens use
##    `GameTheme.make_primary_button`, which does set `text`. A finder that reads
##    only `Button.text` finds nothing on the title screen and looks, wrongly, like
##    a broken menu. `_readable()` takes either.
##
## ── WHAT IT CANNOT SEE (say it plainly, or the green lies) ────────────────
##  · `Combat._rush_requested()` polls the `Input` SINGLETON, which push_input
##    does not feed. The pilot can therefore never hold-to-rush a clash. Nothing
##    it reports is about that path.
##  · It reads `RunState.get_available_nodes()` to know WHICH map stop is legal,
##    because "which chip is glowing" is a painted-pixel question. The CLICK is
##    still a real click at real coordinates and still fully verified.
##  · It does not drink potions or use the pile viewers.
##  · Headless renders nothing, so it cannot judge what a thing LOOKS like. The
##    pixel gates in `tools/run_ui_gates.ps1` own that.

# ── budgets ──────────────────────────────────────────────────────────────
var _seed: int = 20260915
var _max_sec: float = 600.0
var _max_nodes: int = 40
var _coach: bool = false
var _slow: bool = false
var _shots: bool = false
var _hurry: bool = false
var _trace: bool = false

## THE SAME SCORER THE PRACTICE BOT USES, from the other side of the board.
## `mine_is_enemy` is false here and true there; nothing else differs, which is
## the point — two copies of this judgement would drift the moment either was
## retuned, and nothing in the suite compares them. See BoardEval's header.
const BoardEval = preload("res://scripts/combat/BoardEval.gd")

## ── EXPLORATION IS COVERAGE ──────────────────────────────────────────────
## A pure argmax plays the same line every time. For a game AI that is the goal;
## for a BUG FINDER it is a quiet regression, because the states this pilot's
## findings live in are the ones a good player never visits. It is the founding
## observation of `_probe_runaway` (C24): random decks let cards that would never
## otherwise share a board get to meet, and that is the only way an emergent
## interaction shows up at all.
##
## So the pilot takes the best play MOST of the time and otherwise samples from
## the top few, weighted. Competence where it needs it, drift where it pays.
## `--greedy` turns exploration off entirely so the two can be compared.
const PILOT_GREED := 0.75
const EXPLORE_TOP_N := 3
## What an unscorable spell is worth to the PILOT. BoardEval reports `known:false`
## for the ~40 effect types it does not model, and the bot HOLDS those — correct
## for a bot, wrong for a pilot, because an uncast spell is an unexercised
## resolver. A middling score gets them played often without letting a spell the
## scorer cannot see outrank a play it can.
const UNKNOWN_SPELL_SCORE := 2.0

const CANVAS := Vector2(1600, 900)
## Consecutive fully-blocked ticks before the pilot calls a screen stuck. A
## scene transition's fade scrim legitimately swallows input for ~0.5s, so a
## single blocked tick is normal and only a run of them is a finding.
const BLOCK_PATIENCE := 24

## Never press these, in any screen. Each would end the session or the run and
## then the pilot would be "testing" a title screen for nine minutes.
const DENY := [
	"QUIT", "ABANDON", "BACK TO MENU", "MAIN MENU", "GIVE UP", "RETIRE",
	"DELETE", "ERASE", "SKIRMISH", "CREDITS", "LOAD GAME", "NEW RUN —",
]
## Words that mean "this is the way on". Scored highest so the pilot advances
## instead of orbiting a screen's secondary chrome — EXCEPT on a screen that is
## offering something, where the way on IS the refusal. See OFFER_SCREENS.
const ADVANCE := [
	"START RUN", "CONTINUE", "PROCEED", "ONWARD", "LEAVE", "DONE", "TAKE",
	"CLAIM", "CONFIRM", "GOT IT", "NEXT", "BEGIN", "ACCEPT", "REST",
	"MARCH", "SET OUT", "DEPART", "FORGE", "CLOSE",
]

## ── THE REFUSALS ─────────────────────────────────────────────────────────
## "SKIP" used to sit in ADVANCE at 100, and it cost the pilot every reward in
## the game: `Recruit`'s only Button is `make_back_button("Skip")`, so the pilot
## pressed Skip at every muster, played sixteen consecutive runs on the eleven
## cards the hero opens with, and died in act 1 every time. The COVERAGE line
## `deck at death [11, 11]` was the proof — a deck that never grows has declined
## every card it was ever offered.
##
## They are their own tier rather than a line in LOW_PRIORITY because
## `_modal_button` deliberately ignores everything at or below 5: a picker whose
## only answer is PASS must still be answerable, or the pilot hangs in front of
## it. Above the viewers, below every real offer.
## "WALK ON" is here for a reason worth stating: it is Event's always-available
## exit, it matches no word in any of these lists, and `_make_walk_on_button` is
## `add_child`ed LAST — so at the default 50 it won every tie against the event's
## own choices by tree order alone. Every Event in the game was being walked past.
const DECLINE := [
	"SKIP", "DECLINE", "NO THANKS", "LEAVE IT", "INSTEAD", "NOT NOW",
	"REFUSE", "WALK AWAY", "WALK ON",
]
## Short words that cannot be substring-matched without hitting real ones
## ("PASS" is inside COMPASS and PASSAGE), so they are compared whole.
const DECLINE_EXACT := ["PASS", "NONE", "NO"]

## Screens where the forward button DECLINES something, and the reason the fix
## is a policy rather than a longer word list. Every one of these was losing its
## offer to a *differently worded* advance: Recruit to "Skip", Reward to
## "Continue", Treasure to "Take 3 Gold instead", Shop to "Leave the Wagon",
## Wayside and Event to "Continue", Rest to whichever banner happened to be last
## in tree order. Half of those buttons are built with anonymous lambdas, so
## there is no handler name to key off either. What they share is the SCREEN:
## while one of these is up, advancing is the last resort, not the first choice.
const OFFER_SCREENS := ["Recruit", "Reward", "Shop", "Rest", "Treasure",
	"Wayside", "Event"]
## How many ticks the pilot spends taking things before it accepts that whatever
## is left is unreachable and presses the way on. BOUNDED on purpose: an offer
## that can be pressed forever without the screen changing would otherwise hold
## the pilot on one screen until its whole wall-clock budget was gone.
const OFFER_PATIENCE := 6

## Pressed only when nothing better exists — they open sub-screens the pilot
## would then have to climb back out of.
const LOW_PRIORITY := [
	"SETTINGS", "HOW TO PLAY", "LESSONS", "COLLECTION", "DECK", "RELICS",
	"LOG", "BACK", "?",
]

# ── state ────────────────────────────────────────────────────────────────
var _mouse := Vector2(800.0, 450.0)
var _rng := RandomNumberGenerator.new()
var _t0: float = 0.0
var _findings: Array[Dictionary] = []
var _actions: int = 0
var _clicks: int = 0
var _cards_played: int = 0
var _drags: int = 0
var _rounds: int = 0
var _fights: int = 0
var _nodes_visited: int = 0
var _screens_seen: Dictionary = {}
var _blocked_streak: int = 0
var _shot_n: int = 0
var _stop_reason: String = "budget"
var _acts_seen: Dictionary = {}
var _last_fight_id: int = 0
var _last_over_id: int = 0
var _deaths: int = 0
var _silent_refusals: int = 0
var _browsed: int = 0
var _deck_sizes: Array[int] = []
var _last_over_id_deck: int = 0
## Ticks spent on the CURRENT screen instance, keyed by instance id rather than
## by name — a second Recruit is a fresh decision, not a continuation of the
## first. Drives OFFER_PATIENCE.
var _screen_instance: int = 0
var _screen_ticks: int = 0
## Evidence that the P0 fix actually bites. `deck at death` is the outcome;
## these are the acts that produce it, so a regression names itself.
var _recruits_taken: int = 0
var _purchases: int = 0
var _offers_taken: int = 0
var _potions_drunk: int = 0
## Unspent Command at each commit, and the number of commits. See _end_turn.
var _mana_left_total: int = 0
var _turns_committed: int = 0
## Cards the board refused this turn, keyed by instance id. Without this the
## re-decide loop offers the same unplayable card back on every iteration.
var _refused_this_turn: Dictionary = {}
## `--greedy`: always take the top-scored play. Off by default — see PILOT_GREED.
var _greedy: bool = false
## `--policy=random`: the control arm. Every offer answered by coin-flip, the way
## this pilot answered them before `BoardEval.draft_value` existed.
var _policy_random: bool = false
## Plays made so far this turn. Its only job is to tell "the turn opened with
## nothing playable" apart from "the turn ran out of Command", which are the same
## event to `_play_hand`'s loop and completely different measurements.
var _turn_plays: int = 0


# =========================================================================
#  BOOT — the driver must OUTLIVE every scene change.
# =========================================================================

func _ready() -> void:
	if has_meta("pilot_driver"):
		_run.call_deferred()
		return
	# I am the boot scene, and `change_scene_to_file` FREES the boot scene — a
	# coroutine driver that IS `current_scene` never resumes. So the work goes to
	# a node parented to root, beside current_scene. It must be DEFERRED: a bare
	# `root.add_child` during the main scene's _ready fails with "parent node is
	# busy setting up children", the node is never added, nobody ever calls
	# quit(), and the probe HANGS instead of failing.
	var driver := Node.new()
	driver.name = "Pilot"
	driver.set_meta("pilot_driver", true)
	driver.set_script(load("res://tools/_probe_pilot.gd"))
	get_tree().root.add_child.call_deferred(driver)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--max-sec="):
			_max_sec = float(a.substr(10))
		elif a.begins_with("--max-nodes="):
			_max_nodes = int(a.substr(12))
		elif a == "--coach":
			_coach = true
		elif a == "--slow":
			_slow = true
		elif a == "--shots":
			_shots = true
		elif a == "--stats-reset":
			_stats_reset = true
		elif a == "--trace":
			_trace = true
		elif a == "--greedy":
			# No exploration: always the top-scored play. Strictly stronger play
			# and strictly narrower coverage — see PILOT_GREED.
			_greedy = true
		elif a == "--hurry":
			# Straight-line teleports. Strictly less faithful — for long soaks
			# where reach matters more than realism.
			_hurry = true
		elif a == "--policy=random":
			# THE CONTROL ARM. Restores the coin-flip draft/shop/route policies
			# this pilot shipped with, so a claim that the evaluator helps can be
			# tested instead of asserted. Keeping it in the SAME binary matters:
			# an A/B against a deleted version of the file is an A/B against
			# memory, and this project has already paid for that once.
			_policy_random = true


# =========================================================================
#  THE SYNTHETIC HAND
# =========================================================================

## The ONE way an event enters the game. See header note 2 for why the second
## argument is `true` and why nothing else in Godot's input API works here.
func _send(ev: InputEvent) -> void:
	var root := get_tree().root
	if root == null:
		return
	root.push_input(ev, true)


func _move(to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - _mouse
	# Velocity is px/SECOND, and Card2D's drag lean reads it to decide how far the
	# card tips. At 60Hz a one-frame delta is relative * 60; an invented constant
	# would feed the lean a number no real hand produces.
	ev.velocity = ev.relative * 60.0
	_mouse = to
	_send(ev)


func _btn(to: Vector2, pressed: bool, index: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.position = to
	ev.global_position = to
	if pressed:
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT \
			else MOUSE_BUTTON_MASK_RIGHT
	_mouse = to
	_send(ev)


# ── THE HAND IS HUMAN ─────────────────────────────────────────────────────
#
# A straight line at constant speed is the one thing a hand never produces, and
# for a TEST that is not a cosmetic complaint — it is missed coverage. A cursor
# that teleports between controls never crosses anything on the way, so it never
# raises a hover state, never opens a tooltip, and never lets a mouse_exited fire;
# it arrives dead centre every time, so it never tests the edge of a hit region;
# and it arrives on the same frame every time, so a race that needs a slower or
# faster approach is unreachable. Every one of those is a real bug the old
# straight-line pilot could not have found.
#
# TWO MODELS, both off the shelf:
#
# · WHERE the cursor goes — WINDMOUSE (Ben Land, the SCAR/Simba lineage). The
#   pointer is a point mass under two forces: GRAVITY pulling it at the target
#   and WIND, a random walk that is re-rolled each step while far away and
#   DAMPED (divided by sqrt3) once inside D_0 of the target, which is what makes
#   the path wander on the way out and settle straight on the way in. Velocity is
#   clipped to M_0 with a random fraction, so speed varies continuously and the
#   approach decelerates on its own. Constants are the published defaults:
#   G_0 = 9, W_0 = 3, M_0 = 15, D_0 = 12.
#
# · HOW LONG it takes — FITTS'S LAW, MT = a + b·log2(D/W + 1). Distance and
#   TARGET SIZE both matter: a small button far away takes materially longer than
#   a big one nearby, which is exactly the variation a fixed step count erases.
#   a and b are the mouse-typical order of 100-400 ms.
#
# The pilot emits 1-3 motion events per rendered frame, because a real mouse
# reports at 125-1000 Hz into a 60 Hz game and Godot coalesces the surplus —
# one event per frame would be a slower hand than any human has.
const WM_GRAVITY := 9.0
const WM_WIND := 3.0
const WM_MAX_STEP := 15.0
const WM_DAMP_DIST := 12.0
const SQRT3 := 1.7320508
const SQRT5 := 2.2360680
const FITTS_A := 0.115          # seconds of fixed overhead
const FITTS_B := 0.105          # seconds per bit of difficulty
const MAX_PATH_STEPS := 900


## WindMouse. Returns the path; emitting it is the caller's business.
func _wind_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cur := from
	var v := Vector2.ZERO
	var w := Vector2.ZERO
	var m_step := WM_MAX_STEP
	var guard := 0
	while cur.distance_to(to) >= 1.0 and guard < MAX_PATH_STEPS:
		guard += 1
		var dist := cur.distance_to(to)
		var w_mag: float = minf(WM_WIND, dist)
		if dist >= WM_DAMP_DIST:
			# Far out: the wind is a fresh random walk, so the path wanders.
			w = Vector2(
				w.x / SQRT3 + (_rng.randf() * 2.0 - 1.0) * w_mag / SQRT5,
				w.y / SQRT3 + (_rng.randf() * 2.0 - 1.0) * w_mag / SQRT5)
		else:
			# Close in: the wind decays and the step ceiling shrinks. This is the
			# corrective sub-movement every human pointing motion ends with.
			w /= SQRT3
			if m_step < 3.0:
				m_step = _rng.randf() * 3.0 + 3.0
			else:
				m_step /= SQRT5
		v += w + (to - cur).normalized() * WM_GRAVITY
		var v_mag := v.length()
		if v_mag > m_step:
			# Clipped to a RANDOM fraction of the ceiling, not the ceiling — this
			# is what keeps the speed from flat-topping into a constant again.
			v = v.normalized() * (m_step * 0.5 + _rng.randf() * m_step * 0.5)
		cur += v
		out.append(cur)
	out.append(to)
	return out


## Move the way a hand moves: WindMouse's path, paced by Fitts's law for this
## distance and this target width.
func _move_human(to: Vector2, target_w: float = 48.0) -> void:
	if _hurry:
		_move(to)
		await _frames(1)
		return
	var from := _mouse if _mouse.x >= 0.0 else to
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var idx: float = log(dist / maxf(target_w, 8.0) + 1.0) / log(2.0)
	var mt: float = (FITTS_A + FITTS_B * idx) * _rng.randf_range(0.82, 1.28)
	var path := _wind_path(from, to)
	var frames: int = maxi(2, int(ceil(mt * 60.0)))
	var per_frame: int = maxi(1, int(ceil(float(path.size()) / float(frames))))
	var i := 0
	while i < path.size():
		for k in per_frame:
			if i >= path.size():
				break
			_move(path[i])
			i += 1
		if get_tree() == null:
			return
		await get_tree().process_frame
	# The hand lands and steadies before it presses. Skipping this is how a
	# synthetic click beats the control's own hover tween to the frame.
	await _wait(_rng.randf_range(0.05, 0.13))


## Where inside a control a person actually clicks: near the middle, not ON it.
## Gaussian with sigma = a sixth of the box, clamped into the inner 70% so the
## scatter still lands on the target but does exercise its edges.
func _aim_point(c: Control) -> Vector2:
	var xf := c.get_global_transform()
	var sz := c.size
	var fx: float = clampf(_rng.randfn(0.5, 1.0 / 6.0), 0.15, 0.85)
	var fy: float = clampf(_rng.randfn(0.5, 1.0 / 6.0), 0.15, 0.85)
	return xf * Vector2(sz.x * fx, sz.y * fy)


## Human reaction time before a deliberate act (Hick/Welford territory).
## A new screen gets READ before it gets used. Skimming runs ~200 wpm, so the
## pause is scaled by how much text actually appeared — an Event's prose earns a
## real beat, a Reward screen does not. Capped, because the pilot is testing the
## game and not performing a reading. This is not only manners: it is what lets
## entrance animations finish before anything is measured, which is the same
## settle discipline the pixel gates use.
func _read_screen() -> void:
	if _hurry:
		await _frames(2)
		return
	var words: Array[String] = []
	_collect_text(get_tree().root, words, 0, 14, 120)
	var n := 0
	for w in words:
		n += w.split(" ", false).size()
	var sec: float = clampf(float(n) / 3.3 * 0.35, 0.45, 2.6)
	await _wait(sec * _rng.randf_range(0.85, 1.2))


func _think() -> void:
	if _hurry:
		return
	await _wait(_rng.randf_range(0.12, 0.34))


## A press is held, not toggled — 60-120ms is the ordinary human click.
func _click_at(to: Vector2) -> void:
	await _move_human(to)
	_btn(to, true)
	await _wait(_rng.randf_range(0.06, 0.12))
	_btn(to, false)
	await _frames(2)
	_clicks += 1


## One notch of the wheel. A wheel event is a press AND a release of a button
## index, like any other — Godot has no separate wheel event type.
## One wheel click. `dir` indexes WHEEL_UP / DOWN / LEFT / RIGHT — all four,
## because a ScrollContainer whose content overflows HORIZONTALLY does not move
## for a vertical wheel: the vertical scrollbar exists, has no range, and eats
## the event. See `_scroll_into_view`.
func _wheel_dir(at: Vector2, dir: int) -> void:
	var idx: int = [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT][clampi(dir, 0, 3)]
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = idx
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		ev.factor = 1.0
		_send(ev)


func _wheel(at: Vector2, up: bool) -> void:
	var idx := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = idx
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		ev.factor = 1.0
		_send(ev)


## Turn the wheel over the nearest enclosing scroll until `c` is on canvas.
## Returns whether it got there. Both directions are tried because which way a
## ScrollContainer moves for WHEEL_DOWN depends on which of its scrollbars is
## live, and guessing wrong silently does nothing.
func _scroll_into_view(c: Control) -> bool:
	var sc: ScrollContainer = null
	var walk: Node = c.get_parent()
	while walk != null:
		if walk is ScrollContainer:
			sc = walk as ScrollContainer
			break
		walk = walk.get_parent()
	if sc == null or not sc.is_visible_in_tree():
		return false
	var over := _centre_of(sc)
	if not _on_canvas(over):
		return false
	await _move_human(over, minf(sc.size.x, sc.size.y))
	# ALL FOUR DIRECTIONS, and the horizontal pair is the one that matters here.
	# Reward's General's Forge is a ScrollContainer holding an HBoxContainer, so
	# its content overflows SIDEWAYS — and a vertical wheel does nothing to it,
	# because the vertical scrollbar exists with no range and swallows the event.
	# This exemption has been documented since C12 and could never actually fire:
	# every run reported the forge's fifth card at x=1644 as OFF_CANVAS, which is
	# noise in a findings list whose whole value is being empty.
	const DIR_NAMES := ["up", "down", "left", "right"]
	for dir in [3, 2, 1, 0]:
		for i in 14:
			if not is_instance_valid(c) or not is_instance_valid(sc):
				return false
			if _on_canvas(_centre_of(c)):
				_log("scroll", "wheeled %s to reach %s" % [
					DIR_NAMES[dir], _describe(c)])
				return true
			_wheel_dir(over, dir)
			await _frames(2)
	return is_instance_valid(c) and _on_canvas(_centre_of(c))


func _right_click_at(to: Vector2) -> void:
	await _move_human(to)
	_btn(to, true, MOUSE_BUTTON_RIGHT)
	await _wait(_rng.randf_range(0.06, 0.12))
	_btn(to, false, MOUSE_BUTTON_RIGHT)
	await _frames(2)


## Press, travel, release — the gesture, not a teleport. The intermediate motions
## are what drive Card2D's `_update_drag`, the drop-target highlight and the lean;
## a press/release pair with nothing between tests none of it.
##
## A dragged card is a WIDE target (you are dropping onto a lane, not a pixel), so
## the travel is paced against the slot's width, and the hand PAUSES over the drop
## before letting go — people line a card up, hesitate, then release.
func _drag(from: Vector2, to: Vector2, target_w: float = 120.0) -> void:
	await _move_human(from)
	_btn(from, true)
	await _wait(_rng.randf_range(0.05, 0.11))
	await _move_human(to, target_w)
	await _wait(_rng.randf_range(0.10, 0.26))
	_btn(to, false)
	await _frames(3)
	_drags += 1


## A real player presses keys too, and Esc is the one this game leans on — it is
## GameOver's only exit besides the foot buttons, and it closes the glossary, the
## pile viewers and the coach. An input pilot that never sends a key cannot say
## anything about any of them.
func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	_send(down)
	await _wait(_rng.randf_range(0.05, 0.11))
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	_send(up)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		if get_tree() == null:
			return
		await get_tree().process_frame


func _wait(sec: float) -> void:
	if get_tree() == null:
		return
	await get_tree().create_timer(sec).timeout


# =========================================================================
#  SEEING — everything here is what a player can perceive, or Godot's own answer
# =========================================================================

## Godot's OWN hit-test result, not a re-implementation of its picking rule.
## `_probe_input_reach` (C29) re-implements the rule statically over a settled
## screen; this asks the engine, live, mid-gesture, with every scrim and modal
## and CanvasLayer exactly as the player has them.
func _hover() -> Control:
	var root := get_tree().root
	if root == null:
		return null
	return root.gui_get_hovered_control()


## What a PLAYER reads on this control — its own text, else any descendant label.
func _readable(c: Variant) -> String:
	if c == null or not is_instance_valid(c):
		return ""
	if c is Button and not (c as Button).text.strip_edges().is_empty():
		return (c as Button).text.strip_edges()
	var found: Array[String] = []
	_collect_text(c, found, 0)   # default budget: a control's own words, not a page
	return " ".join(found).strip_edges()


## Two callers want two different things from this walk, so they say so instead of
## sharing one hardcoded cap: `_readable` wants a control's LABEL (a few strings)
## and `_read_screen` wants enough of the page to time a read by.
func _collect_text(n: Node, out: Array[String], depth: int,
		max_depth: int = 6, max_items: int = 4) -> void:
	if depth > max_depth or out.size() >= max_items:
		return
	if n is Label:
		var t := (n as Label).text.strip_edges()
		if not t.is_empty():
			out.append(t)
	elif n is RichTextLabel:
		var t2 := (n as RichTextLabel).get_parsed_text().strip_edges()
		if not t2.is_empty():
			out.append(t2)
	for ch in n.get_children():
		_collect_text(ch, out, depth + 1, max_depth, max_items)


func _describe(c: Variant) -> String:
	if c == null or not is_instance_valid(c):
		return "<freed>"
	var txt := _readable(c)
	var layer := 0
	var walk: Node = c as Node
	while walk != null:
		if walk is CanvasLayer:
			layer = (walk as CanvasLayer).layer
			break
		walk = walk.get_parent()
	return "%s[%s]%s (L%d)" % [
		c.get_class(), c.name,
		("" if txt.is_empty() else " \"%s\"" % txt.substr(0, 40)), layer]


func _all_buttons() -> Array:
	var out: Array = []
	_walk_buttons(get_tree().root, out, 0)
	return out


func _walk_buttons(n: Node, out: Array, depth: int) -> void:
	if depth > 40:
		return
	if n is BaseButton:
		var b := n as BaseButton
		if b.is_visible_in_tree() and not b.disabled \
				and b.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var r := b.get_global_rect()
			if r.size.x >= 4.0 and r.size.y >= 4.0:
				out.append(b)
	for ch in n.get_children():
		_walk_buttons(ch, out, depth + 1)


## ── FINDING A CONTROL THAT IS NOT A BUTTON ───────────────────────────────
## `_all_buttons` walks BaseButton, and on the screen that matters most there
## are none: a Recruit card tile is a `Card2D` with `gui_input` connected to
## `_on_recruit_card_input`, so the entire slate is invisible to the button walk
## and the ONLY pressable control on the muster is the Skip button. No amount of
## scoring can reach a control that was never in the pool.
##
## Identity is the HANDLER, the same stable hook `_map_button_for` uses to find a
## map stop and BROWSE_METHODS uses to find a viewer — a name in the game's own
## source, not a word that a copy pass can change underneath the pilot.
func _wired_controls(sig: String, methods: Array) -> Array:
	var out: Array = []
	_walk_wired(get_tree().root, sig, methods, out, 0)
	return out


func _walk_wired(n: Node, sig: String, methods: Array, out: Array,
		depth: int) -> void:
	if depth > 40:
		return
	if n is Control and (n as Control).is_visible_in_tree() 			and not (n is BaseButton and (n as BaseButton).disabled) 			and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE 			and n.has_signal(sig):
		for con in n.get_signal_connection_list(sig):
			if String((con["callable"] as Callable).get_method()) in methods:
				out.append(n)
				break
	for ch in n.get_children():
		_walk_wired(ch, sig, methods, out, depth + 1)


## What a player reads on a CLICK CATCHER — the transparent full-rect Button that
## a panel puts over itself so the whole tile is one target. Its own text is
## empty and it has no children, so `_readable` returns "" and every camp banner
## scores an identical 20; the words the player is actually choosing between
## ("REST", "FORGE", "HOLD A WAKE") live in a SIBLING subtree under the panel.
## Read the parent, and only for identification — never for scoring, or a tile
## could borrow a DENY word off the panel behind it and silently go unpressed.
func _catcher_label(c: Control) -> String:
	if c == null or not is_instance_valid(c):
		return ""
	var p: Node = c.get_parent()
	if p == null:
		return ""
	var words: Array[String] = []
	_collect_text(p, words, 0, 6, 4)
	return " ".join(words).to_upper()


## The true visual centre of a control. NOT `get_global_rect().get_center()` —
## that ignores `scale`, and a resting hand card sits at 0.72 with a bottom-centre
## pivot, so the rect's centre can be tens of pixels off the painted card.
func _centre_of(c: Control) -> Vector2:
	return c.get_global_transform() * (c.size * 0.5)


## The logical canvas, READ LIVE — never the 1600x900 constant. `SettingsOverlay`
## offers UI Scale 60-100%, which sets `content_scale_factor`, and under
## canvas_items stretch that DIVIDES the logical canvas: at 60% the UI lays itself
## out on 2667x1500. A hardcoded bound would call four of the five settings
## off-canvas (class C32).
func _canvas() -> Vector2:
	var root := get_tree().root
	if root == null:
		return CANVAS
	var r: Vector2 = root.get_visible_rect().size
	return CANVAS if r.x < 2.0 or r.y < 2.0 else r


func _on_canvas(p: Vector2) -> bool:
	var cv := _canvas()
	return p.x >= 2.0 and p.y >= 2.0 and p.x <= cv.x - 2.0 and p.y <= cv.y - 2.0


## Aim at `c`, and ask the engine whether the aim lands. Returns the control that
## would ACTUALLY receive the press, so a refusal can name its blocker.
## `exact` — REQUIRE THE HIT TO BE THE CONTROL ITSELF, and the distinction is not
## pedantry: it decides whether the press reaches a handler at all. A hit on a
## BUTTON's child still fires that button's `pressed`, because the event walks up
## to whatever handles it. A hit on a child of a control wired through
## `gui_input` does NOT — the child consumes the press where it lands and the
## parent's handler never runs. Recruit's card tiles are the second kind, and
## with the lenient rule the pilot pressed the writ's own rules box, reported the
## recruit as taken, and enlisted nobody: `offers taken 1` against a deck still
## sitting at 11.
func _aim(c: Control, p: Vector2, exact: bool = false) -> Dictionary:
	await _move_human(p, minf(c.size.x, c.size.y))
	await _frames(1)
	var got := _hover()
	# The aim lands only if the hit IS the target or something INSIDE it.
	#
	# An ANCESTOR hit is deliberately NOT accepted, and that is the whole point of
	# the check: Godot picks children before parents, so if the engine hands the
	# press to the target's own parent, the target was not picked — which is
	# exactly the occlusion this is looking for. Accepting it would have made the
	# oracle agree with itself on every nested control in the game.
	var inside := got != null and c.is_ancestor_of(got)
	var ok := got != null and (got == c or (inside and not exact))
	# Describe the blocker NOW. A finding is written after several more awaits, and
	# a transient — a fading scrim, a tooltip, a dying tween host — is routinely
	# freed by then, which printed "<freed> is over that part" and told nobody
	# anything. The name is only worth having at the instant of the hit.
	return {"ok": ok, "got": got, "desc": _describe(got), "inside": inside}


## Walk the face for a point the engine hands to THIS control rather than to one
## of its children. Centre first — it is what a person aims at — then outward.
## The same shape as `_find_grab`, which solves the same problem for a fanned
## hand card; a tile's own furniture is no more an occlusion than a neighbouring
## card is.
func _aim_exact(c: Control) -> Dictionary:
	var xf := c.get_global_transform()
	var last: Dictionary = {"ok": false, "got": null, "desc": "<nothing>",
		"inside": false, "point": _centre_of(c)}
	for fy in [0.50, 0.30, 0.14, 0.86, 0.68]:
		for fx in [0.50, 0.28, 0.72]:
			var p: Vector2 = xf * Vector2(c.size.x * fx, c.size.y * fy)
			if not _on_canvas(p):
				continue
			var a: Dictionary = await _aim(c, p, true)
			a["point"] = p
			if not is_instance_valid(c):
				a["ok"] = false
				return a
			if bool(a["ok"]):
				return a
			last = a
	return last


# =========================================================================
#  ACTING — a click is only "done" if the engine agreed it landed
# =========================================================================

func _click_control(c: Control, why: String, exact: bool = false) -> bool:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return false
	var p := _centre_of(c)
	if not _on_canvas(p):
		# Screens slide their controls in, so a rect read mid-entrance measures
		# the machine, not the layout. Only a position that HOLDS off-canvas is a
		# finding — otherwise this reports every entrance animation in the game.
		var settled := p
		for i in 10:
			await _wait(0.15)
			if not is_instance_valid(c):
				return false
			settled = _centre_of(c)
			if _on_canvas(settled):
				break
		# A CONTROL INSIDE A SCROLLCONTAINER IS NOT OFF-CANVAS, IT IS SCROLLED, and
		# the two look identical to a rect check. Reward's General's Forge puts its
		# candidates in a horizontal scroll, so the fifth card sits at x=1644 on a
		# 1600 canvas — reported as a layout defect against a screen that is
		# behaving exactly as designed. `_probe_boundary_ui` already carries this
		# exemption (it is why C12's mutation run caught it failing to see its own
		# founding defect); the pilot did not.
		#
		# Reaching it is a PLAYER's problem too, so solve it the player's way: put
		# the wheel over the scroll and turn it. That also tests the scroll, which
		# nothing else here does.
		if not _on_canvas(settled) and await _scroll_into_view(c):
			settled = _centre_of(c)
		if not _on_canvas(settled):
			_finding("OFF_CANVAS",
				"%s centre rests off-canvas at %s (canvas is %s)" % [
					_describe(c), str(settled), str(_canvas())],
				{"screen": _screen(), "why": why,
				 "rect": str(c.get_global_rect()), "held_for": "1.5s"})
			return false
		p = settled
	# Aim where a hand aims — near the middle, not on it (see _aim_point).
	var p_aim := _aim_point(c)
	if not _on_canvas(p_aim):
		p_aim = p
	var aim: Dictionary
	if exact:
		# The handler is on this control itself, so a child hit is a miss. Find a
		# point the control actually answers to before pressing anything.
		aim = await _aim_exact(c)
		p_aim = aim["point"]
	else:
		aim = await _aim(c, p_aim)
	if not is_instance_valid(c) or not c.is_visible_in_tree():
		return false
	if not bool(aim["ok"]):
		# The off-centre aim missed. Before calling anything blocked, try dead
		# centre: if the CENTRE works and a point 20% in does not, the control is
		# PARTLY covered — real, worth knowing, and a different bug from a control
		# nothing can reach. Without this split an off-centre aim would also
		# manufacture false "occluded" reports on any control with a child over
		# one corner.
		var centre_aim: Dictionary = await _aim(c, p, exact)
		if not is_instance_valid(c) or not c.is_visible_in_tree():
			return false
		if bool(centre_aim["ok"]):
			_finding("PARTLY_COVERED",
				"%s takes a click at its centre but not at %s — %s is over that part" % [
					_describe(c), str(p_aim.round()), String(aim["desc"])],
				{"screen": _screen(), "why": why, "rect": str(c.get_global_rect())})
			p_aim = p
			aim = centre_aim
		else:
			_blocked_streak += 1
			_note_block(c, centre_aim["got"], why, String(centre_aim["desc"]))
			return false
	p = p_aim
	_blocked_streak = 0
	_btn(p, true)
	await _wait(_rng.randf_range(0.06, 0.12))
	_btn(p, false)
	await _frames(3)
	_clicks += 1
	_actions += 1
	_log("click", "%s  <- %s" % [_describe(c), why])
	return true


## A blocked aim is not automatically a bug — a modal is SUPPOSED to swallow the
## screen underneath it. The distinction the report needs is WHERE the blocker
## lives: a higher CanvasLayer is a modal doing its job, a sibling in the SAME
## layer is an occlusion nobody intended.
func _note_block(target: Control, got: Control, why: String,
		got_desc: String = "") -> void:
	var gd := got_desc if not got_desc.is_empty() else _describe(got)
	var tl := _layer_of(target)
	var gl := _layer_of(got)
	var cap := _capture_present()
	if got == null:
		_finding("NO_HIT", "aim at %s hit NOTHING" % _describe(target),
			{"screen": _screen(), "why": why})
	elif cap != null and (got == cap or cap.is_ancestor_of(got)):
		# A full-screen capture is up and it is the thing that answered. That is a
		# modal doing its job, whatever layer it happens to sit on.
		_log("blocked", "%s covered by capture %s" % [_describe(target), _describe(cap)])
	elif gl > tl:
		# Expected shape. Recorded at debug level only; the pilot will now try to
		# act INSIDE the blocker, which is what a player does with a modal.
		_log("blocked", "%s covered by modal %s" % [_describe(target), _describe(got)])
	else:
		_finding("OCCLUDED",
			"%s is unreachable — %s receives the click instead (same layer)" % [
				_describe(target), gd],
			{"screen": _screen(), "why": why})


func _layer_of(c: Variant) -> int:
	if c == null or not is_instance_valid(c):
		return 0
	var walk: Node = c as Node
	while walk != null:
		if walk is CanvasLayer:
			return (walk as CanvasLayer).layer
		walk = walk.get_parent()
	return 0


# =========================================================================
#  CHOOSING — which control would a player press?
# =========================================================================

func _score(b: Variant) -> int:
	if b == null or not is_instance_valid(b):
		return -1000
	var t := _readable(b).to_upper()
	for d in DENY:
		if t.find(d) >= 0:
			return -1000
	# DECLINE IS TESTED BEFORE ADVANCE, and the order is load-bearing rather than
	# tidy: Treasure's refusal reads "Take 3 Gold instead", which contains
	# ADVANCE's own "TAKE". Scored the other way round the pilot walked past the
	# relic on every Treasure in the game and logged it as advancing.
	# A refusal is LAST while there is still something to take, and the WAY OUT
	# once there is not. Without that second half a refusal is permanently
	# outranked by any worded control, so an Event whose choices never run out —
	# a push-your-luck minigame is exactly that shape — would hold the pilot until
	# its wall-clock budget, since "WALK ON" is the only exit those screens have.
	for d in DECLINE:
		if t.find(d) >= 0:
			return 8 if _taking() else 60
	if t in DECLINE_EXACT:
		return 8 if _taking() else 60
	for a in ADVANCE:
		if t.find(a) >= 0:
			return 10 if _taking() else 100
	for l in LOW_PRIORITY:
		if t.find(l) >= 0:
			return 5
	if t.is_empty():
		return 20   # an unworded control is usually a card / tile / map chip
	return 50


## Is the pilot still shopping this screen? While true, ADVANCE drops below both
## an unworded tile (20) and a worded offer (50), so the reward gets taken first
## and the way on is what is left when nothing else can be pressed.
func _taking() -> bool:
	return _screen() in OFFER_SCREENS and _screen_ticks < OFFER_PATIENCE


func _best_button(pool: Array) -> BaseButton:
	var best: BaseButton = null
	var best_s := -999
	# Later in the walk = later in tree order = painted on top. A modal's own
	# buttons therefore win ties against the screen buried behind it.
	for b in pool:
		var s := _score(b)
		if s <= -1000:
			continue
		if s >= best_s:
			best_s = s
			best = b
	return best


## ── CURIOSITY ────────────────────────────────────────────────────────────
## People open things. An advance-seeking policy never does — ADVANCE scores 100
## and these score 5, so the deck viewer, the relic list, the battle log and the
## field manual were unreachable by construction. That is a coverage hole exactly
## where this pilot's findings actually live: every one so far has been a layout
## or a blocker, and overlays are made of both. Opening one and CLOSING it again
## also tests the half nobody writes a probe for — an overlay you cannot get out
## of is a trap, and `_click_control` verifies the way out is genuinely reachable
## rather than merely present.
##
## SETTINGS is deliberately not in the list: it MUTATES config, and a pilot that
## quietly changes the render scale halfway through a run invalidates everything
## it reports afterwards.
const BROWSE := ["DECK", "RELIC", "LOG", "HOW TO PLAY", "LESSONS", "MANUAL",
	"CHRONICLE", "GLOSSARY"]
## Matching by TEXT alone finds nothing on the chart: the map's deck and relic
## viewers are `MapTipButton`s painted over chips and carry no words at all, so
## `_readable` returns "" for them. Their HANDLER is the stable identity, the same
## way `_map_button_for` finds a stop.
const BROWSE_METHODS := [
	"_show_deck_viewer", "_show_relic_viewer", "_show_how_to_play",
	"_show_coaching_lessons", "_show_full_glossary", "_show_combat_primer",
	"_show_keyword_glossary", "_show_pile_viewer",
]
const BROWSE_CHANCE := 0.28


func _maybe_browse() -> bool:
	if _hurry or _rng.randf() > BROWSE_CHANCE:
		return false
	var opts: Array = []
	for b in _all_buttons():
		if _score(b) <= -1000:
			continue
		var t := _readable(b).to_upper()
		var hit := false
		for w in BROWSE:
			if t.find(w) >= 0:
				hit = true
				break
		if not hit:
			for con in b.pressed.get_connections():
				if String((con["callable"] as Callable).get_method()) in BROWSE_METHODS:
					hit = true
					break
		if hit:
			opts.append(b)
	if opts.is_empty():
		return false
	var pick: BaseButton = opts[_rng.randi_range(0, opts.size() - 1)]
	var label := _readable(pick)
	await _think()
	if not await _click_control(pick, "have a look at %s" % label):
		return false
	_browsed += 1
	await _read_screen()

	# ...and back out again. Two ways, because a player has two: the control that
	# says so, then Esc.
	for attempt in 5:
		var top := _modal_button()
		if top == null:
			return true          # closed, or it was never modal to begin with
		var tl := _readable(top).to_upper()
		if tl.find("CLOSE") >= 0 or tl.find("BACK") >= 0 or tl.find("DONE") >= 0 				or tl.find("X") == 0 or tl.is_empty():
			await _click_control(top, "close %s" % label)
		else:
			await _key(KEY_ESCAPE)
		await _wait(0.45)
		if _modal_button() == null:
			return true
	_finding("OVERLAY_STUCK",
		"opened \"%s\" and could not close it with its own control or Esc" % label,
		{"screen": _screen(), "still_up": _describe(_modal_button())})
	return true


# =========================================================================
#  THE DAMAGE LEDGER — why does the hero actually die?
# =========================================================================
##
## The pilot could already say IT LOSES. It could not say WHAT KILLED IT, and
## without that "the game is too hard" is an opinion. This samples the hero's HP
## every frame of every fight and attributes each drop to the beat that produced
## it, using only things the game already exposes — no hooks, no edits.
##
## The attribution that matters is BLOCKABLE vs NOT:
##   · `_phase_caption` names the live beat, so a drop during the CLASH is a
##     creature that got through, while a drop outside it is an effect — an
##     encounter passive, a curse's draw sting, a card's own cost.
##   · `front_mine` is how many bodies were standing in the player's FRONT row at
##     that instant. Damage taken with a FULL front line could not have been
##     prevented by blocking harder, which is the house definition of
##     uncounterable (docs/COMBAT_SHAPE_PASS_20260727.md).
##
## Those two together are the difficulty instrument: a game that kills the pilot
## through a wall of its own bodies is doing something a player cannot answer.
var _fight: Dictionary = {}
var _fights_log: Array[Dictionary] = []
var _last_hp: int = -1
var _card_stats: Dictionary = {}
var _recruit_why: Dictionary = {}
var _stats_reset: bool = false


func _process(_delta: float) -> void:
	# The BOOT node carries this same script and is freed on the first scene
	# change; only the root-parented driver may sample, or the first fight is
	# opened twice and closed by a node that is about to die.
	if not has_meta("pilot_driver"):
		return
	# Sampled from _process, not from the driver coroutine: the driver spends most
	# of a fight parked on an await, and the damage happens while it is parked.
	var c := _scene_root()
	if c == null or not is_instance_valid(c) or _screen() != "Combat":
		_close_fight("left")
		return
	var rn := int(c.get("round_number"))
	if rn < 1:
		return
	var hp := int(c.get("player_hp"))
	if _fight.is_empty() or int(_fight.get("iid", 0)) != c.get_instance_id():
		_close_fight("left")
		var rs_f := get_node_or_null("/root/RunState")
		_fight = {
			"iid": c.get_instance_id(),
			"name": String(c.get("_encounter_name")),
			"passive": String(c.get("_encounter_passive")),
			# WHICH KIND OF FIGHT, because the HP bill is not one population.
			# The 2026-09-19 map pass cut the fight count per act, and the
			# pilot takes 90% of the Generals it is offered — so a rising
			# "HP spent per fight" can be a change in the MIX rather than in
			# any fight's difficulty, and without this column the two are
			# indistinguishable. Same denominator lesson as C26's coverage.
			"node_type": ("" if rs_f == null
				else String(rs_f.get("current_node_type"))),
			"act": _current_act(),
			"hp_in": hp, "hp_out": hp, "rounds": 0, "drops": [], "log": [],
			"plays": [],
			"foe_hp_in": int(c.get("enemy_hp")), "foe_hp_out": int(c.get("enemy_hp")),
		}
		_last_hp = hp
	# PER-ROUND BOARD SNAPSHOT — the measurement that tests "decided by round 5"
	# directly instead of inferring it from how long the fight ran. Board strength
	# is ATK + HP summed over standing bodies: crude, but it is the quantity both
	# sides are actually spending Command to buy, and its SIGN is what matters.
	if rn > int(_fight.get("rounds", 0)):
		var mine := 0
		var theirs := 0
		for side in [false, true]:
			for row in [0, 1]:
				for b in c.call("_row_array", side, row):
					if b == null or not is_instance_valid(b):
						continue
					var v: int = int(b.call("effective_atk")) + int(b.get("current_hp"))
					if side:
						theirs += v
					else:
						mine += v
		_settle_plays(c, rn)
		(_fight["log"] as Array).append({
			"r": rn, "mine": mine, "theirs": theirs,
			"hp": hp, "foe": int(c.get("enemy_hp")),
		})
	_fight["rounds"] = maxi(int(_fight["rounds"]), rn)
	_fight["hp_out"] = hp
	# THE LOW-WATER MARK, because `hp_out` is not what the fight COST.
	# Combat's victory block heals 75% of missing HP after every boss, and this
	# samples every frame — so the last sample is taken AFTER the heal and the
	# cost of the fight is erased by the reward for winning it. Measured: bosses
	# read 1.0 HP each, which is not a fact about bosses. Any mid-fight heal
	# (a potion, Lifelink, a camp relic) hides cost the same way, so the deepest
	# point is the honest figure for every fight, not just a boss.
	_fight["hp_low"] = mini(int(_fight.get("hp_low", hp)), hp)
	_fight["foe_hp_out"] = int(c.get("enemy_hp"))
	if _last_hp >= 0 and hp < _last_hp:
		var front_mine := 0
		var front_foe := 0
		var foe_atk := 0
		for body in c.call("_row_array", false, 0):
			if body != null and is_instance_valid(body):
				front_mine += 1
		for body in c.call("_row_array", true, 0):
			if body != null and is_instance_valid(body):
				front_foe += 1
				foe_atk += int(body.call("effective_atk"))
		(_fight["drops"] as Array).append({
			"amt": _last_hp - hp,
			"round": rn,
			"beat": String(c.get("_phase_caption")),
			# `phase` is the RELIABLE discriminator and the caption is only a
			# label. Classifying by caption alone reported 0% clash damage across
			# 8 fights, which is not a result — it is a broken oracle: the caption
			# is cleared before the hero's damage number resolves, so every drop
			# fell through to "effect". RESOLVING is the clash/resolution step;
			# PLAYER_TURN damage is a card cost, a curse draw sting or a passive
			# that fires on the round open.
			"phase": int(c.get("phase")),
			"front_mine": front_mine,
			"front_foe": front_foe,
			"foe_atk": foe_atk,
		})
	_last_hp = hp


func _current_act() -> int:
	var rs := get_node_or_null("/root/RunState")
	if rs == null or not ("current_act_idx" in rs):
		return 0
	return int(rs.current_act_idx) + 1


## ── WHAT A CARD DOES IN PRACTICE ─────────────────────────────────────────
##
## The simulated table (`tools/_probe_card_value.tscn`) can only score what
## BoardSim models — 19 of 206 cards fully, the rest a floor. This measures the
## other 187 the only way that needs no model at all: PLAY THE CARD AND WATCH.
##
## Two signals per card, and they answer different questions:
##   · BOARD SWING — the change in (my board − their board) across the round the
##     card landed in. Immediate, high sample count, and it is the quantity the
##     card was bought with. Its weakness is that it cannot see a slow card.
##   · WIN RATE WHEN PLAYED — did the fight this card appeared in end in a win?
##     Slow-acting cards show up here and nowhere else, but the signal is noisy:
##     a fight has many cards in it and only one outcome.
##
## Compared against the run's OWN baseline win rate, not against 50% — the bot
## wins ~60% of fights, so a card at 55% is below par, not above it.
##
## SAMPLES ACCUMULATE ACROSS RUNS in `user://pilot_card_stats.json`. One run gives
## most cards 1-3 plays, which is nothing; the table is only worth reading once a
## card has double digits, and it prints `n` so that stays visible. `--stats-reset`
## starts a fresh ledger (do that after any balance change, or you are averaging
## two different games).
const STATS_PATH := "user://pilot_card_stats.json"


## `card` IS UNTYPED ON PURPOSE — see `_in_hand`, which already does this.
##
## A TYPED PARAMETER DEFEATS `is_instance_valid`. GDScript validates an argument's
## CLASS at the CALL, a freed object has no class to report, and the call dies with
## "argument 2 (previously freed) is not a subclass of the expected argument
## class" — so the guard on the next line could never run. Declaring `card:
## Control` here made that guard decorative.
##
## MEASURED CONSEQUENCE (2026-09-19), and it is why this is not a cosmetic fix: a
## spell whose target dies during resolution freed the card, the throw ABORTED
## `_play_spell` mid-cast, and because targeting runs through Combat's `_input()`
## override rather than the drag system the abandoned cast then ate the next
## click — which the pilot reported as a false **[OCCLUDED]** finding blaming the
## lane numerals' ancestor ("i ii iii iv receives the click instead"). That looked
## exactly like a real input bug and REPRODUCED on two clean seeds. The game side
## was innocent on three checks: the whole board chain is MOUSE_FILTER_IGNORE, and
## `_probe_input_reach` (C29) and `_probe_occlusion` both pass.
##
## `_resolve_targeting`'s own header already said it: "one wrong assumption in an
## oracle does not stay one wrong finding."
func _note_play(c: Node, card: Variant) -> void:
	if _fight.is_empty() or card == null or not is_instance_valid(card):
		return
	var data: Dictionary = card.get("card_data")
	var id := String(data.get("id", ""))
	if id.is_empty():
		return
	(_fight["plays"] as Array).append({
		"id": id,
		"name": String(data.get("name", id)),
		"r": int(c.get("round_number")),
		"diff": _board_diff(c),
	})


## (my board − their board) in ATK+HP. The same quantity the point-of-no-return
## sampler uses, so the two readings are on one scale.
func _board_diff(c: Node) -> int:
	var d := 0
	for side in [false, true]:
		for row in [0, 1]:
			for b in c.call("_row_array", side, row):
				if b == null or not is_instance_valid(b):
					continue
				var v: int = int(b.call("effective_atk")) + int(b.get("current_hp"))
				d += (-v if side else v)
	return d


## Called when the round turns over: every card played LAST round now has an
## "after" to be judged against.
func _settle_plays(c: Node, rn: int) -> void:
	var after := _board_diff(c)
	for pl in (_fight.get("plays", []) as Array):
		if bool(pl.get("done", false)) or int(pl["r"]) >= rn:
			continue
		pl["done"] = true
		var rec: Dictionary = _card_stat(String(pl["id"]), String(pl["name"]))
		rec["swing"] = float(rec["swing"]) + float(after - int(pl["diff"]))
		rec["swing_n"] = int(rec["swing_n"]) + 1


func _load_stats() -> void:
	if _stats_reset:
		return
	if not FileAccess.file_exists(STATS_PATH):
		return
	var f := FileAccess.open(STATS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	# A corrupt or half-written ledger must not take the run down — it is
	# telemetry, not state the game depends on.
	if parsed is Dictionary:
		_card_stats = parsed


func _save_stats() -> void:
	var f := FileAccess.open(STATS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_card_stats))
	f.close()


func _card_stat(id: String, nm: String) -> Dictionary:
	if not _card_stats.has(id):
		_card_stats[id] = {"name": nm, "played": 0, "won": 0, "fights": 0,
			"swing": 0.0, "swing_n": 0}
	return _card_stats[id]


func _close_fight(how: String) -> void:
	if _fight.is_empty():
		return
	_fight["end"] = how
	# THE PILOT RECORDS FACTS; THE VERDICT IS DERIVED. Both faces can reach 0 in
	# one clash (both rows strike simultaneously), and `Combat._check_game_over`
	# resolves that tie ONE way — `if player_hp <= 0: ... elif enemy_hp <= 0:` —
	# so a mutual kill is a DEFEAT. These two flags are deliberately INDEPENDENT
	# observations ("the foe's face fell" / "ours did"), and `analyse_journal.py`
	# applies the game's precedence. Keeping the precedence out of here is what
	# lets it be fixed retroactively across every archived arm at once, instead
	# of becoming an instrument change in the middle of a measurement.
	_fight["died"] = int(_fight.get("hp_out", 1)) <= 0
	_fight["won"] = int(_fight.get("foe_hp_out", 1)) <= 0
	# One credit per DISTINCT card per fight — a card played four times in one
	# fight must not count as four wins, or repeats would dominate the table.
	var seen: Dictionary = {}
	for pl in (_fight.get("plays", []) as Array):
		var id := String(pl["id"])
		if seen.has(id):
			continue
		seen[id] = true
		var rec: Dictionary = _card_stat(id, String(pl["name"]))
		rec["fights"] = int(rec["fights"]) + 1
		if bool(_fight["won"]):
			rec["won"] = int(rec["won"]) + 1
	for pl in (_fight.get("plays", []) as Array):
		var r2: Dictionary = _card_stat(String(pl["id"]), String(pl["name"]))
		r2["played"] = int(r2["played"]) + 1
	_jr_write("fight_end", {
		"name": String(_fight.get("name", "?")),
		"passive": String(_fight.get("passive", "")),
		"node_type": String(_fight.get("node_type", "")),
		"fight_act": int(_fight.get("act", 0)),
		"won": bool(_fight["won"]), "died": bool(_fight["died"]),
		"rounds": int(_fight.get("rounds", 0)), "end": how,
		"hp_in": int(_fight.get("hp_in", 0)), "hp_out": int(_fight.get("hp_out", 0)),
		"hp_low": int(_fight.get("hp_low", _fight.get("hp_out", 0))),
		"foe_in": int(_fight.get("foe_hp_in", 0)),
		"foe_out": int(_fight.get("foe_hp_out", 0)),
		# The per-round board trace. This is the series the POINT OF NO RETURN is
		# computed from, and keeping it raw means the question can be re-asked
		# offline with a different definition of "ahead".
		"trace": _fight.get("log", []),
	})
	_fights_log.append(_fight)
	_fight = {}
	_last_hp = -1


## The report half. Kept separate from the printing so the numbers can be read
## back by anything else later.
func _damage_summary() -> Dictionary:
	var tot := 0
	var clash := 0
	var effect := 0
	var walled := 0        # taken with a FULL front line — blocking could not help
	var by_enc: Dictionary = {}
	var beats: Dictionary = {}
	for f in _fights_log:
		var lost := 0
		for d in f["drops"]:
			var amt := int(d["amt"])
			tot += amt
			lost += amt
			if int(d.get("phase", 0)) == 1:      # Phase.RESOLVING
				clash += amt
			else:
				effect += amt
			var bk := String(d["beat"]).strip_edges()
			if bk.is_empty():
				bk = "(no caption)"
			beats[bk] = int(beats.get(bk, 0)) + amt
			if int(d["front_mine"]) >= 4:
				walled += amt
		var key := String(f.get("name", "?"))
		var cur: Dictionary = by_enc.get(key, {"n": 0, "dmg": 0, "won": 0, "rounds": 0})
		cur["n"] = int(cur["n"]) + 1
		cur["dmg"] = int(cur["dmg"]) + lost
		cur["rounds"] = int(cur["rounds"]) + int(f.get("rounds", 0))
		if bool(f.get("won", false)):
			cur["won"] = int(cur["won"]) + 1
		by_enc[key] = cur
	return {"total": tot, "clash": clash, "effect": effect, "walled": walled,
		"by_enc": by_enc, "beats": beats}


# =========================================================================
#  THE DECISION JOURNAL — every choice, and what it was chosen OVER
# =========================================================================
##
## `_card_stats` above records what the pilot PLAYED. This records what it
## DECIDED, and those are not the same measurement.
##
## A log of actions cannot answer the questions a balance pass actually asks. It
## says a card was drafted; it cannot say the two cards it was drafted OVER, so a
## card taken 40 times reads as popular when it may simply be the only one ever
## offered. It says a play was made; it cannot say the four plays that scored
## lower, so nothing can ask whether the scorer's ranking survives contact with
## the outcome. **The alternatives are the data.** One draft with three tiles on
## it is three observations about three cards, not one about the winner.
##
## Two properties make it worth the disk it costs:
##
##  · **EVERY RECORD CARRIES THE STATE IT WAS DECIDED IN** (`_jr_ctx`): act, hero
##    HP, gold, deck size, run id. Without that a decision is uninterpretable —
##    "declined the removal" means one thing at 12 cards and the opposite at 30,
##    and a table that cannot tell them apart will average them into nothing.
##  · **IT IS FLUSHED PER RECORD.** A pilot that hangs or crashes is exactly the
##    run whose evidence is worth most, and a buffered writer is the one thing
##    guaranteed to lose it. The cost is real and it is paid deliberately.
##
## JSONL, one file per invocation, one object per line, accumulating on disk
## across runs. `tools/analyse_journal.py` is the reader.
const JOURNAL_DIR := "user://pilot_journal"

var _jr: FileAccess = null
var _jr_seq: int = 0
var _jr_path: String = ""
var _jr_run: int = 0
var _hero_picks: Dictionary = {}   # hid -> runs taken as that lord
## `_fights_log.size()` when the current run started, so `run_end` can report
## fights in THIS run rather than in the whole session.
var _jr_fights_at_run_start: int = 0
## Set by `_choose_play` and consumed by `_note_play`, so the OUTCOME of a play
## can be stitched to the option set that produced it without threading a
## parameter through four call sites that are already awkward about types.
var _jr_last_play: Dictionary = {}


func _journal_open() -> void:
	DirAccess.make_dir_recursive_absolute(JOURNAL_DIR)
	_jr_path = "%s/seed%d_%d.jsonl" % [
		JOURNAL_DIR, _seed, int(Time.get_unix_time_from_system())]
	_jr = FileAccess.open(_jr_path, FileAccess.WRITE)
	if _jr == null:
		_log("journal", "COULD NOT OPEN %s — decisions will not be saved" % _jr_path)
		return
	_jr_write("header", {
		"seed": _seed, "budget": _max_sec, "max_nodes": _max_nodes,
		"greedy": _greedy, "coach": _coach, "hurry": _hurry,
		"policy": "random" if _policy_random else "value",
		"display": DisplayServer.get_name(),
		"utc": Time.get_datetime_string_from_system(true),
	})


## The state a decision was made in. Cheap enough to stamp on every record, and
## the record is worthless without it.
func _jr_ctx() -> Dictionary:
	var rs := get_node_or_null("/root/RunState")
	if rs == null:
		return {"run": _jr_run}
	return {
		"run": _jr_run,
		"act": _current_act(),
		# THE HERO WAS NOT RECORDED FOR THE FIRST 236 RUNS, AND THAT IS WHY NOBODY
		# NOTICED THEY WERE ALL THE SAME ONE. `_drive_main_menu` pressed NEW RUN then
		# START RUN and never touched the roster, so every run inherited
		# `MainMenu._selected_hero = HeroDB.HERO_ORDER[0]` — the Raider — and the
		# whole corpus described one hero of five, with the Raider's own kingdom
		# (grasswake, 12 authored encounters) unreachable because `_select_rivals`
		# excludes your own lord. Found only by chasing an act-1 General that had
		# never once been met. An UNINSTRUMENTED CONSTANT is invisible in exactly
		# the way a varied one is not. See PLAYTEST_MEASUREMENT_20260919.md §20.
		"hero": String(rs.get("current_hero_id")),
		"hp": int(rs.get("hero_hp")),
		"hp_max": int(rs.get("hero_max_hp")),
		"gold": int(rs.get("gold")),
		"deck": (rs.get("deck") as Array).size(),
		"relics": (rs.get("relics") as Array).size(),
	}


func _jr_write(kind: String, rec: Dictionary) -> void:
	if _jr == null:
		return
	# The envelope is stamped LAST so a payload key cannot clobber it — the same
	# rule PlayLog learned the hard way when a map node's own "type" field
	# overwrote the record type and made a whole class of events unfindable.
	var out: Dictionary = rec.duplicate(true)
	var ctx := _jr_ctx()
	for k in ctx:
		if not out.has(k):
			out[k] = ctx[k]
	out["kind"] = kind
	out["seq"] = _jr_seq
	out["ms"] = Time.get_ticks_msec()
	_jr_seq += 1
	_jr.store_line(JSON.stringify(out))
	_jr.flush()


## A card as the journal records it: enough to re-join against CardDB offline,
## and enough to read without joining at all.
func _jr_card(d: Dictionary) -> Dictionary:
	return {
		"id": String(d.get("id", "?")),
		"name": String(d.get("name", "?")),
		"cost": int(d.get("cost", 0)),
		"type": String(d.get("type", "")),
		"rarity": String(d.get("rarity", "")),
		"atk": int(d.get("atk", 0)),
		"hp": int(d.get("hp", 0)),
		"ctype": String(d.get("ctype", "")),
		"kw": d.get("keywords", []),
		"plus": bool(d.get("is_upgraded", false)),
	}


## THE CARD BEHIND A TILE, and it is never reliably the tile itself.
##
## An offer screen is built three different ways across this codebase: Recruit
## wires `gui_input` on the Card2D directly, the pickers put a transparent
## catcher OVER a card, and Reward's forge row wraps the card in a panel. So the
## card data can sit on the control, on a descendant, or on an ancestor — and a
## reader that checks only one of the three silently records `"?"` for two thirds
## of every draft in the file, which reads as missing data rather than as a bug.
## THE HANDLER KNOWS, AND THE NODE TREE DOES NOT. Three of the four pickers bind
## a DECK INDEX into their callback — `_on_upgrade_card_pressed(wrapper, btn,
## deck_index)`, `_pick_forge_candidate(deck_index, wrapper)`, `_confirm_removal(
## deck_index, slot)` — so the card is one `get_upgraded_card_data` away, exact
## and with its mods folded in.
##
## MEASURED: without this the forge picker logged ELEVEN tiles of `"?"`, because
## a picker tile is a transparent catcher and the card it covers is neither its
## child nor its ancestor. The tree walk below could not see any of them, so the
## forge and the paid removal were being answered by a policy that could not read
## its own options — the exact defect this pass set out to remove, surviving
## inside the fix for it because nothing checked that the tiles were legible.
## Which bound argument carries the DECK INDEX, per handler. Listed explicitly
## rather than "any int argument", because `_on_upgrade_card_pressed` takes two
## Controls before its index and a positional guess would read a truncated
## argument list as card zero — the whole deck's first card, silently, forever.
const PICKER_DECK_INDEX_ARG := {
	"_on_upgrade_card_pressed": 2,
	"_pick_forge_candidate": 0,
	"_confirm_removal": 0,
}


func _jr_tile_data(c: Control) -> Dictionary:
	if c == null or not is_instance_valid(c):
		return {}
	if c is BaseButton:
		for con in (c as BaseButton).pressed.get_connections():
			var call: Callable = con["callable"]
			var args := call.get_bound_arguments()
			var at: int = int(PICKER_DECK_INDEX_ARG.get(call.get_method(), -1))
			if at >= 0 and at < args.size() and args[at] is int:
				var rs := get_node_or_null("/root/RunState")
				if rs != null:
					var d: Variant = rs.call("get_upgraded_card_data", int(args[at]))
					if d is Dictionary and not (d as Dictionary).is_empty():
						var out: Dictionary = (d as Dictionary).duplicate()
						out["deck_index"] = int(args[at])
						return out
			# The other two hand over the WRAPPER (Wayside's drill yard) or the
			# candidate DICT (Hold a Wake). Neither is a deck index, and both
			# carry the card somewhere the tile itself does not.
			for a in args:
				if a is Dictionary and (a as Dictionary).has("id"):
					return a
				if a is Control and is_instance_valid(a):
					var nested := _jr_find_card_data(a as Control, 0)
					if not nested.is_empty():
						return nested
	var here: Variant = c.get("card_data")
	if here is Dictionary and not (here as Dictionary).is_empty():
		return here
	var found := _jr_find_card_data(c, 0)
	if not found.is_empty():
		return found
	var up: Node = c.get_parent()
	for _i in 3:
		if up == null:
			break
		var d: Variant = up.get("card_data")
		if d is Dictionary and not (d as Dictionary).is_empty():
			return d
		up = up.get_parent()
	return {}


func _jr_find_card_data(n: Node, depth: int) -> Dictionary:
	if depth > 4:
		return {}
	for ch in n.get_children():
		var d: Variant = ch.get("card_data")
		if d is Dictionary and not (d as Dictionary).is_empty():
			return d
		var deeper := _jr_find_card_data(ch, depth + 1)
		if not deeper.is_empty():
			return deeper
	return {}


func _jr_tiles(tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		var d := _jr_tile_data(t as Control)
		if d.is_empty():
			out.append({"id": "?", "label": _readable(t).substr(0, 40)})
		else:
			out.append(_jr_card(d))
	return out


func _jr_tile_id(c: Control) -> String:
	var d := _jr_tile_data(c)
	return String(d.get("id", "?")) if not d.is_empty() else _readable(c).substr(0, 40)


## Both boards, as the scorer saw them. The single most useful column in the
## file: a play is only interpretable against the position it was made in.
func _jr_board(c: Node) -> Dictionary:
	var out := {"mine": [], "theirs": []}
	for side in [false, true]:
		var rows: Array = []
		for row in [0, 1]:
			var lane_out: Array = []
			for b in c.call("_row_array", side, row):
				if b == null or not is_instance_valid(b):
					lane_out.append(null)
					continue
				lane_out.append({
					"id": String((b.get("card_data") as Dictionary).get("id", "?")),
					"atk": int(b.call("effective_atk")),
					"hp": int(b.get("current_hp")),
				})
			rows.append(lane_out)
		out["theirs" if side else "mine"] = rows
	return out


func _journal_close(reason: String) -> void:
	if _jr == null:
		return
	_jr_write("close", {"reason": reason, "records": _jr_seq})
	_jr.close()
	_jr = null


# =========================================================================
#  SCREENS
# =========================================================================

func _scene_root() -> Node:
	var t := get_tree()
	return null if t == null else t.current_scene


func _screen() -> String:
	var s := _scene_root()
	if s == null or not is_instance_valid(s):
		return "<none>"
	var scr: Variant = s.get_script()
	if scr != null:
		return String(scr.resource_path).get_file().get_basename()
	return s.name


func _run() -> void:
	_parse_args()
	_rng.seed = _seed
	_t0 = Time.get_ticks_msec() / 1000.0

	print("╔══════════════════════════════════════════════════════════════╗")
	print("║  PILOT — playing Burning Meadow through the mouse             ║")
	print("╚══════════════════════════════════════════════════════════════╝")
	print("  display=%s  seed=%d  budget=%.0fs  max_nodes=%d  coach=%s" % [
		DisplayServer.get_name(), _seed, _max_sec, _max_nodes, str(_coach)])
	print("  policy=%s  greedy=%s" % [
		("random (CONTROL ARM)" if _policy_random else "value"), str(_greedy)])

	_load_stats()
	_journal_open()
	print("  journal: %s" % _jr_path)
	_apply_settings()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(2.5)

	var last_screen := ""
	while not _out_of_budget():
		var before := _screen()
		_note_screen_tick()
		_screens_seen[before] = int(_screens_seen.get(before, 0)) + 1
		if before != last_screen:
			last_screen = before
			await _read_screen()
		match before:
			"MainMenu":   await _drive_main_menu()
			"MapView":    await _drive_map()
			"Combat":     await _drive_combat()
			"GameOver":   await _drive_game_over()
			"<none>":     await _wait(0.3)
			_:            await _drive_generic()
		if _blocked_streak >= BLOCK_PATIENCE:
			_finding("STUCK", "no reachable control on %s for %d ticks" % [
				before, _blocked_streak], {"buttons": _button_dump()})
			_stop_reason = "stuck on %s" % before
			break
		await _frames(1)

	_report()


## Keyed on the scene INSTANCE, not its name: two Recruits in one run are two
## separate decisions, and a name-keyed counter would hand the second one an
## already-exhausted patience budget and skip it outright.
func _note_screen_tick() -> void:
	var s := _scene_root()
	var id := 0 if s == null or not is_instance_valid(s) else s.get_instance_id()
	if id != _screen_instance:
		_screen_instance = id
		_screen_ticks = 0
	else:
		_screen_ticks += 1


func _apply_settings() -> void:
	var us := get_node_or_null("/root/UserSettings")
	if us == null:
		return
	if not _coach:
		# A returning player. The guided walkthrough REFUSES plays that are not
		# the card it is pointing at ("Begin with the glowing creature."), which
		# would make every refusal the pilot sees a tutorial artefact rather than
		# a bug. `tools/_probe_tutorial_live.tscn` owns that path properly.
		var tdb := get_node_or_null("/root/TutorialDB")
		if tdb != null and "COACH_OFF" in tdb:
			us.coaching_mode = tdb.COACH_OFF
		else:
			us.coaching_mode = 2
	if not _slow:
		# The pilot is looking for broken logic, not judging pacing. Full speed
		# buys roughly 3x the run inside the same wall-clock budget.
		us.anim_speed = 3.0
		us.clash_dwell_scale = 0.25
		us.tooltip_delay = 0.0


func _out_of_budget() -> bool:
	if Time.get_ticks_msec() / 1000.0 - _t0 > _max_sec:
		_stop_reason = "wall-clock budget (%.0fs)" % _max_sec
		return true
	if _nodes_visited >= _max_nodes:
		_stop_reason = "visited %d map stops" % _nodes_visited
		return true
	return false


# ── MAIN MENU ────────────────────────────────────────────────────────────

func _drive_main_menu() -> void:
	# The run opening is ONE screen built over the menu, so START RUN and NEW RUN
	# are both live here at different moments. Prefer the one that advances.
	var pool := _all_buttons()
	var start := _named(pool, "START RUN")
	if start != null:
		await _pick_hero_for_run()
		if await _click_control(start, "begin the run"):
			await _wait(2.0)
		return
	var new_run := _named(pool, "NEW RUN")
	if new_run != null:
		if await _click_control(new_run, "open run setup"):
			await _wait(1.6)
		return
	await _drive_generic()


func _named(pool: Array, needle: String) -> BaseButton:
	for b in pool:
		if _readable(b).to_upper().find(needle.to_upper()) >= 0:
			return b
	return null


## ROTATE THE LORD. Before this existed the pilot never touched the roster, so
## every run of every arm ever measured was `HeroDB.HERO_ORDER[0]` — the Raider —
## and four of the five kits, their doctrine relics and their alternate openers had
## never been played once. Worse, `RunState._select_rivals` EXCLUDES the player's
## own lord, so the Raider's kingdom (grasswake: 12 authored encounters, and the
## only act-1 combat pool in the game that needs no cross-act borrowing) was
## unreachable by construction. See PLAYTEST_MEASUREMENT_20260919.md §20.
##
## Rotation is DETERMINISTIC on the run index, not random: a seed must still
## reproduce, and a random hero would make two arms of the same seed disagree about
## which kit they measured — the one thing a matched A/B cannot survive. With 5
## heroes and ~4 runs a seed, a 12-seed arm covers every hero many times over.
##
## The tile is resolved off `MainMenu._hero_cards` (the dictionary the screen builds
## to style its own selected state) and then CLICKED with the synthetic cursor —
## resolving a target from state and driving it through the real input pipeline is
## what every other policy here does. Calling `_focus_hero` directly would bypass
## the pipeline this whole probe exists to exercise.
func _pick_hero_for_run() -> void:
	var menu := get_tree().current_scene
	if menu == null or not is_instance_valid(menu):
		return
	var cards: Variant = menu.get("_hero_cards")
	if not (cards is Dictionary) or (cards as Dictionary).is_empty():
		# Not fatal, and NOT silent: the roster is how a hero gets varied, so a
		# screen that stops exposing it must show up in the report rather than
		# quietly reverting the corpus to one lord.
		_log("hero", "roster not reachable — this run takes the screen's default")
		return
	var order: Array = []
	var hdb := get_node_or_null("/root/HeroDB")
	if hdb != null:
		for hid in (hdb.get("HERO_ORDER") as Array):
			if (cards as Dictionary).has(String(hid)):
				order.append(String(hid))
	if order.is_empty():
		var keys: Array = (cards as Dictionary).keys()
		keys.sort()          # stable, so the rotation is reproducible either way
		order = keys
	var want := String(order[_jr_run % order.size()])
	var tile: Variant = (cards as Dictionary)[want]
	if not (tile is Control) or not is_instance_valid(tile):
		return
	# The press is the oracle only for "a click landed". Whether the LORD CHANGED is
	# read off RunState after the run starts (`_jr_ctx.hero`), the same split the
	# muster uses — there `_click_control` returning true proved nothing and the
	# DECK COUNT was the answer.
	if await _click_control(tile as Control, "take the field as %s" % want):
		_hero_picks[want] = int(_hero_picks.get(want, 0)) + 1
		await _wait(0.35)


# ── MAP ──────────────────────────────────────────────────────────────────

func _drive_map() -> void:
	var rs := get_node_or_null("/root/RunState")
	if rs == null:
		await _drive_generic()
		return
	if "current_act_idx" in rs:
		_acts_seen[int(rs.current_act_idx) + 1] = true

	# WHICH stop is legal is a painted-glow question, so it is read from state.
	# WHICH PIXELS to press, and whether the press lands, is still entirely real.
	var avail: Array = rs.get_available_nodes()
	if avail.is_empty():
		_finding("DEAD_MAP", "map offers no available node", {"act": rs.get("act")})
		await _drive_generic()
		return

	# THE CHART HAS MODALS TOO, and only combat was answering them. `MapView._ready`
	# opens an option picker for any of three relics — the Articles of War asks
	# which tribe, the Totem Pole which keyword, the Bone Hourglass which boon —
	# on a CanvasLayer at 1000, and it holds the chart until it is answered. The
	# pilot had no branch for that: it kept aiming at a map chip, logged 24
	# consecutive "covered by modal" blocks, and reported STUCK against a game
	# that was politely waiting for an answer. Found by the soak, at the exact
	# moment a drafted relic first paid out.
	for _m in MODAL_ANSWER_TRIES:
		if not await _maybe_answer_modal():
			break
	# The chart is where a player checks their deck and purse before committing.
	if await _maybe_browse():
		return
	# Choosing a route is the slowest decision on the road — people look at the
	# chart before they commit to it.
	await _think()
	var want: Dictionary = _choose_stop(avail)
	var offered: Array = []
	for nd in avail:
		offered.append({"type": String((nd as Dictionary).get("type", "?")),
			"row": int((nd as Dictionary).get("row", -1)),
			"col": int((nd as Dictionary).get("col", -1))})
	_jr_write("route", {
		"offered": offered,
		"taken": String(want.get("type", "?")),
		"taken_row": int(want.get("row", -1)),
		"taken_col": int(want.get("col", -1)),
		"forced": offered.size() <= 1,
	})
	var btn := _map_button_for(int(want.get("row", -1)), int(want.get("col", -1)))
	if btn == null:
		_finding("NO_CHIP",
			"available stop row=%d col=%d has no button on the chart" % [
				int(want.get("row", -1)), int(want.get("col", -1))],
			{"type": want.get("type", "?")})
		await _drive_generic()
		return

	var before := _screen()
	if await _click_control(btn, "march on %s" % str(want.get("type", "?"))):
		_nodes_visited += 1
		await _wait(1.8)
		if _screen() == before:
			# A legal, reachable, successfully-pressed stop that goes nowhere.
			_finding("NO_ROUTE",
				"pressing stop type=%s (row %d) did not leave the map" % [
					str(want.get("type", "?")), int(want.get("row", -1))], {})


## WHICH STOP TO MARCH ON — and this is where "the pilot never drafts" actually
## lives. Measured: `visits=1, TOOK A CARD=1` over 13 map stops — the enlist
## policy is already PERFECT, it just almost never reaches a muster. A uniform
## random walk treats a card the deck badly needs as interchangeable with a third
## wayside, which is not how anyone routes.
##
## So the chart is read with a preference, the way a player reads it: while the
## deck is thin, a `recruit` stop outranks everything else; a shop is next (it
## also sells cards). Above the threshold the preference lapses and the walk goes
## back to uniform, which keeps the ROUTING VARIED — a pilot that always takes the
## same node type stops covering the map, and coverage is the other half of this
## tool's job.
const DECK_HUNGRY_BELOW := 18


## ROUTING IS A DECISION, AND IT WAS A COIN-FLIP WITH ONE RULE BOLTED ON.
##
## The old policy steered at a thin deck and went uniform above it, which means
## every other consideration a player routes on was absent: it walked a hurt run
## into a General, skipped the camp before the keep, and passed a wagon with 300
## gold in the purse. Those are not subtle plays — they are the whole of map
## strategy in this genre.
##
## Scored rather than ranked, and the score is deliberately SOFT: the comment
## this replaces was right that a pilot which always takes the same node type
## stops covering the map, and coverage is half this tool's job. So the best stop
## wins most of the time and the rest stay reachable — the same argument as
## PILOT_GREED, for the same reason.
const ROUTE_GREED := 0.8
## Below this fraction of max HP, a General is a bad trade no matter what it pays.
##
## MEASURED 2026-09-24, and 0.6 was not a margin, it was a coin toss. Over 56
## fights the HP bill splits combat **5.7** / elite **20.9** / boss 8.0 — so a
## General costs two thirds of a 30 HP bar, and 19% of fights account for 45% of
## all damage the hero takes. Entering one at 60% HP (18) leaves nothing.
##
## The 2026-09-19 map pass made the elite bands BYPASSABLE — one spike with road
## in every other lane — precisely so this is a choice rather than a tax, and the
## policy was still answering it as if a General were an ordinary stop.
##
## PUT BACK TO 0.6 FOR NOW (2026-09-24), and the reason is experimental rather
## than a change of mind. Raising it to 0.85 at the same time as the elite HP
## nerf meant one run changed the GAME, the BOT and (via `hp_low`) the
## INSTRUMENT together — so nothing in the result was attributable, which is the
## exact mistake this document warns about two sections earlier. The bot is held
## at its original policy so the nerf can be measured alone; the routing question
## is real and gets its own A/B once the game side is settled.
##
## There is a signal in the contaminated run worth keeping: skipping Generals
## made the BOSS fights worse (8.0 -> 18.1 HP, 67% -> 50%), which is what you
## would expect if declining the spike also declines the relic and the forge it
## pays for. That is the §13 design tension showing up in the bot's own results.
const ROUTE_ELITE_HP := 0.6
## Gold worth stopping for. One relic is 100, so a purse past this is idle capital.
const ROUTE_RICH := 110


func _choose_stop(avail: Array) -> Dictionary:
	var rs := get_node_or_null("/root/RunState")
	var hp_frac := 1.0
	var gold := 0
	if rs != null:
		hp_frac = float(rs.get("hero_hp")) / maxf(1.0, float(rs.get("hero_max_hp")))
		gold = int(rs.get("gold"))
	var deck := _deck_size()
	var scored: Array = []
	for nd in avail:
		var t := String((nd as Dictionary).get("type", ""))
		var s := 1.0
		match t:
			"recruit":
				# The only place a card enters the deck. Worth most while the
				# deck is still the 11-card opener.
				s = 6.0 if deck < DECK_HUNGRY_BELOW else 3.0
			"shop":
				s = 4.5 if gold >= ROUTE_RICH else 2.0
				if deck < DECK_HUNGRY_BELOW:
					s += 1.0
			"rest":
				# A camp is a heal OR a forge, so it is never a wasted stop —
				# but it is worth most when the hero is actually hurt.
				s = 2.0 + 6.0 * (1.0 - hp_frac)
			"treasure":
				s = 4.0
			"event":
				s = 2.5
			"wayside":
				s = 2.5
			"elite":
				# The relic is the point, and the HP is the price. Below the
				# threshold that trade stops being one.
				#
				# SCORED BELOW A SAFE STOP EVEN WHEN AFFORDABLE. At 20.9 HP
				# measured, a General is the most expensive thing on the chart
				# by a factor of three — it should be taken when the run is
				# healthy and there is nothing better, not preferred over a
				# muster or a reliquary.
				s = 4.0 if hp_frac >= ROUTE_ELITE_HP else 0.4
			"combat":
				s = 1.5
			"boss":
				# THE KEEP IS REACHABLE FROM ANYWHERE ONCE THE GATE OPENS, and
				# that is a fact about the game, not about this policy.
				# `RunState.get_available_nodes` appends the lord node to EVERY
				# step's options once two holds have fallen, with no adjacency
				# test — only `boss_node.row > row` — so from row 4 onward the
				# keep is a legal march from wherever the army stands.
				#
				# MEASURED, seed 606: the pilot took it at row 8 and again at
				# row 5, finishing act 1 in ten stops of eighteen and act 2 in
				# six. It reached ACT THREE on the eleven-card starting deck,
				# having skipped the second muster (row 10), the Arsenal (13),
				# the second elite band (12) and the camp (16) — the act's only
				# guaranteed heal. Then it died.
				#
				# Rushing is therefore a trap that looks like progress, and a
				# scorer that takes it is measuring a route no player who
				# understood the map would walk. Last resort: below every real
				# stop, so it wins only when nothing else is offered.
				s = 0.05
			_:
				s = 1.0
		scored.append({"nd": nd, "s": s, "t": t})
	if _policy_random:
		# The old rule, verbatim: steer at a thin deck, otherwise walk uniformly.
		if deck < DECK_HUNGRY_BELOW:
			var wanted: Array = []
			for nd in avail:
				if String((nd as Dictionary).get("type", "")) in ["recruit", "shop"]:
					wanted.append(nd)
			if not wanted.is_empty():
				return wanted[_rng.randi_range(0, wanted.size() - 1)]
		return avail[_rng.randi_range(0, avail.size() - 1)]
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["s"]) > float(b["s"]))
	if _rng.randf() < ROUTE_GREED:
		_log("route", "%s (score %.1f, hp %.0f%%, gold %d, deck %d)" % [
			String(scored[0]["t"]), float(scored[0]["s"]),
			hp_frac * 100.0, gold, deck])
		return scored[0]["nd"]
	return scored[_rng.randi_range(0, scored.size() - 1)]["nd"]


func _map_button_for(row: int, col: int) -> BaseButton:
	for b in _all_buttons():
		for con in b.pressed.get_connections():
			var call: Callable = con["callable"]
			if call.get_method() != "_on_node_pressed":
				continue
			var args := call.get_bound_arguments()
			if args.size() >= 2 and int(args[0]) == row and int(args[1]) == col:
				return b
	return null


# ── GAME OVER ────────────────────────────────────────────────────────────

func _drive_game_over() -> void:
	# Once per GameOver INSTANCE — this is re-entered every tick while the screen
	# is up, and a per-tick count would report four hundred deaths.
	var gid := _scene_root().get_instance_id() if _scene_root() != null else 0
	if gid != _last_over_id:
		_last_over_id = gid
		_deaths += 1
	_stop_reason = "the run ended (GameOver)"
	# A run that ends on the STARTING deck never took a single card offered to it,
	# which is a far bigger finding than anything in the list — it means the pilot
	# is declining its own rewards and that every act past the first is unreachable
	# for reasons that have nothing to do with the game.
	var rs := get_node_or_null("/root/RunState")
	if rs != null and gid != _last_over_id_deck:
		_last_over_id_deck = gid
		_deck_sizes.append(int((rs.get("deck") as Array).size()))
		# THE WHOLE DECK, not its size. "What does a deck that gets further look
		# like?" is the question a deckbuilder's balance actually turns on, and a
		# count cannot answer it. Written at GameOver because that is the only
		# instant the finished article exists.
		var final_deck: Array = []
		for cid in (rs.get("deck") as Array):
			final_deck.append(String(cid))
		_jr_write("run_end", {
			"final_deck": final_deck,
			"final_relics": rs.get("relics"),
			"act_reached": _current_act(),
			"upgrades": (rs.get("card_upgrades") as Dictionary).size(),
			# FIGHTS IN *THIS* RUN, not in the session. `_fights_log` accumulates
			# across every run the pilot plays, so this column used to report the
			# session total on every record — which made "fights survived per
			# run" unreadable and correlated with deck size at r = 0.10.
			"fights": _fights_log.size() - _jr_fights_at_run_start,
			# DID IT WIN? Read the RUN's own verdict, not the hero's HP.
			# `end_run(victorious)` is the only thing that knows, and it now
			# records it. The old test here was `hero_hp > 0` — copied from
			# GameOver, which had the same bug: a relic that heals on an enemy
			# death (`stygian_soul`) can fire in the clash that kills the hero,
			# so a LOST run ends at 1 HP and reads as a win. It produced a false
			# positive in a live sweep that I nearly reported as the bot's first
			# victory.
			"victory": bool(rs.get("last_run_victorious")),
		})
		_jr_fights_at_run_start = _fights_log.size()
		_jr_run += 1
	var again := _named(_all_buttons(), "PLAY AGAIN")
	if again != null and not _out_of_budget():
		if await _click_control(again, "rematch"):
			await _wait(2.0)
			return
	await _wait(0.5)


# ── GENERIC ROAD SCREEN (Reward / Shop / Rest / Event / Recruit / …) ──────

func _drive_generic() -> void:
	var pool := _all_buttons()
	# A PICKER FIRST, ALWAYS — it is modal, and while one is up nothing else on the
	# screen can be pressed. Ahead of _maybe_browse too: opening a viewer on top of
	# an unanswered picker is how a pilot buries itself two layers deep.
	if await _drive_picker():
		return
	if await _maybe_browse():
		return
	# Screens that HAND OUT something get a policy before the generic scorer, for
	# the two reasons the scorer cannot cover on its own: Recruit's offer is not a
	# Button at all, and Rest's three offers are indistinguishable to it (identical
	# unworded click catchers, so it took whichever was last in tree order).
	#
	# ABOVE the empty-pool bail on purpose: "no buttons on this screen" and "no
	# offers on this screen" are different questions, and a screen whose only
	# offer is not a Button would otherwise be declared dead before it was asked.
	if _taking():
		match _screen():
			"Recruit":
				if await _drive_recruit():
					return
			"Rest":
				if await _drive_rest():
					return
			"Shop":
				if await _drive_shop():
					return
	if pool.is_empty():
		_blocked_streak += 1
		await _wait(0.25)
		return
	var pick := _best_button(pool)
	if pick == null:
		_blocked_streak += 1
		await _wait(0.25)
		return
	await _think()
	var before := _screen()
	if await _click_control(pick, "advance %s" % before):
		await _wait(0.9)
	else:
		# Blocked. A player would press whatever is ON TOP — so do that, which is
		# how every modal, coach panel and confirm dialog gets answered without
		# the pilot needing to know any of them exist.
		var top := _topmost_button(pool)
		if top != null and top != pick:
			if await _click_control(top, "answer the thing on top"):
				await _wait(0.6)
		else:
			await _wait(0.25)
	if _screen() != before:
		await _wait(0.8)


# ── THE SCREENS THAT HAND SOMETHING OVER ─────────────────────────────────
#
# Each returns TRUE if it acted. A false return is not a failure — it means this
# screen has nothing of its own kind to take right now, and the generic scorer
# should have the tick.

const RECRUIT_TILE_METHOD := "_on_recruit_card_input"
const REST_BANNER_METHOD := "_on_choice_banner_pressed"
const SHOP_BUY_METHODS := ["_buy_card", "_buy_relic", "_buy_potion"]

## ── A PICKER IS MODAL, AND THE PILOT COULD NOT SEE IT ─────────────────────
## "Choose a card to duplicate" opens a grid over the screen it belongs to and
## blocks everything under it. The pilot aimed at a button the picker was
## correctly covering, twenty-four times, and reported OCCLUDED before giving up
## with STUCK — on a live windowed run, against a game doing its job.
##
## NEITHER of the two mechanisms that should have caught it can:
##  · `_capture_present` deliberately EXCLUDES `current_scene`, because every
##    scene root is a full-rect STOP Control and counting those made every screen
##    in the game look modal. Event's picker blocks by way of the Event ROOT — so
##    the one node the detector must ignore is the one doing the blocking.
##  · `_best_button` cannot help either: a picker tile is a transparent catcher
##    over a card, so it reads as UNWORDED (20), while the event's own choice
##    buttons underneath are worded (50) and win — the pilot preferred a button it
##    could not reach over the only ones it could.
##
## So a picker is recognised the way everything else awkward in this file is: by
## HANDLER. If one of these is on screen, answering it is the only move there is.
const PICKER_METHODS := [
	"_on_picker_tile_pressed",     # Event — "choose a card to ..."
	"_on_upgrade_card_pressed",    # Rest — the forge
	"_pick_forge_candidate",       # Reward — the General's Forge
	"_on_grid_card_pressed",       # Wayside — drill yard / standard bearer
	"_on_wake_tile_pressed",       # Rest — Hold a Wake
	"_on_stranger_hand_pick",      # Event — the stranger's hand
	"_confirm_removal",            # Shop — the provost's fee (SEE THIN_FLOOR)
]
## THE SHOP'S REMOVAL IS THE ONE PICKER THAT MAKES THE DECK SMALLER, and
## answering it like the others was an own-goal: measured `deck at death [10, 12]`,
## i.e. a run that FINISHED BELOW the 11-card opener. Every other picker in the
## list above improves a card; this one removes it.
##
## Thinning is a real strategy, but only once there is fat to cut — cutting out of
## an 11-card deck is strictly worse than not stopping. So the removal is
## answered only above this size, which keeps the path COVERED (the reason it was
## added) without letting the pilot dismantle itself.
##
## 2026-09-16: this picker used to be the sutler's BUY-BACK and paid the pilot
## for the card. It now CHARGES `Shop.REMOVE_FEE`, so the floor is doing strictly
## more work than it was — a thin-deck answer now costs gold as well as a card.
const THIN_FLOOR := 16
## Below this fraction of max HP the camp is for healing; above it, for forging.
const REST_HEAL_BELOW := 0.60


## Answer an open picker. Ranked ABOVE the offer-screen policies because a picker
## is not an offer among others — it is the screen, and nothing else on it can be
## pressed until it is answered.
func _drive_picker() -> bool:
	var tiles := _wired_controls("pressed", PICKER_METHODS)
	if tiles.is_empty():
		return false
	# A removal on a thin deck is declined, not answered — and declining means
	# leaving the picker alone so the ordinary screen policy walks out of the shop.
	if _is_removal_picker(tiles) and _deck_size() < THIN_FLOOR:
		_log("shop", "declined the removal — deck only %d" % _deck_size())
		return false
	await _think()
	# A REMOVAL AND A FORGE WANT OPPOSITE ENDS OF THE SAME RANKING, and answering
	# either at random is how a run pays 60 gold to delete its own rare. Strike
	# the worst card; forge the best one, because a "+" is a multiplier on
	# whatever it lands on and the card you most want to draw is the one worth
	# improving.
	var removal := _is_removal_picker(tiles)
	var ranked := _rank_tiles(tiles, removal)
	var pick: Control = ranked[0]["tile"]
	var before := _screen()
	# A picker is where a FORGE lands, where a card is REMOVED, and where several
	# events hand out a permanent change. Recording only "a picker was answered"
	# throws away which card the run actually spent the stop on.
	_jr_write("picker", {
		"screen": before,
		"removal": removal,
		"offered": _jr_tiles(tiles),
		"scored": _jr_ranked(ranked),
		"taken": _jr_tile_id(pick),
	})
	if not await _click_control(pick, "answer the picker on %s" % before):
		return false
	_offers_taken += 1
	await _wait(1.0)
	return true


func _deck_size() -> int:
	var rs := get_node_or_null("/root/RunState")
	if rs == null:
		return 0
	return (rs.get("deck") as Array).size()


# ── CHOOSING A CARD, RATHER THAN ROLLING FOR ONE ──────────────────────────
##
## Every offer screen in this game used to be answered by `randi_range`. That is
## not a small weakness in a DECKBUILDER — the deck is the run, so a bot that
## drafts by coin-flip is playing a deck no human would ever assemble, and any
## difficulty number it produces describes that deck rather than the game.
##
## `BoardEval.draft_value` is the judgement; this is the plumbing that gets a
## deck profile to it and reads the card off a tile. `worst_first` inverts it for
## the one picker that wants the opposite end — the shop's paid removal.
func _rank_tiles(tiles: Array, worst_first: bool) -> Array:
	var profile := BoardEval.deck_profile(_deck_cards())
	var out: Array = []
	if _policy_random:
		# The control arm scores every tile the same, so the shuffle below is the
		# whole policy. Written as a scored path rather than a separate branch so
		# both arms produce the SAME journal shape — an A/B whose two arms log
		# differently cannot be read by one analyser.
		for t in tiles:
			if is_instance_valid(t):
				var dr := _jr_tile_data(t as Control)
				out.append({"tile": t, "value": _rng.randf(),
					"id": String(dr.get("id", "?")), "read": not dr.is_empty()})
		if out.is_empty():
			return [{"tile": tiles[0], "value": 0.0, "id": "?", "read": false}]
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["value"]) > float(b["value"]))
		return out
	for t in tiles:
		if not is_instance_valid(t):
			continue
		var d := _jr_tile_data(t as Control)
		# A TILE WITH NO CARD BEHIND IT IS NOT WORTHLESS, IT IS UNREAD. Scoring
		# it zero would make an unreadable tile the automatic pick of a removal
		# picker (lowest score wins there) and the automatic reject of a draft —
		# a parsing failure quietly becoming a policy. Park it mid-table instead
		# and let a readable sibling decide.
		var v := 0.0 if d.is_empty() else BoardEval.draft_value(d, profile)
		out.append({"tile": t, "value": v, "id": String(d.get("id", "?")),
			"read": not d.is_empty()})
	if out.is_empty():
		return [{"tile": tiles[0], "value": 0.0, "id": "?", "read": false}]
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not bool(a["read"]) or not bool(b["read"]):
			return bool(a["read"]) and not bool(b["read"])
		return (float(a["value"]) < float(b["value"])) if worst_first \
			else (float(a["value"]) > float(b["value"])))
	return out


## The run's deck AS PLAYED — folded upgrades, not the printed base. A forged
## card is a different card, and profiling the base would tell the policy the
## deck holds something it does not.
func _deck_cards() -> Array:
	var rs := get_node_or_null("/root/RunState")
	if rs == null:
		return []
	var out: Array = []
	var n: int = (rs.get("deck") as Array).size()
	for i in n:
		var d: Variant = rs.call("get_upgraded_card_data", i)
		if d is Dictionary and not (d as Dictionary).is_empty():
			out.append(d)
	return out


func _jr_ranked(ranked: Array) -> Array:
	var out: Array = []
	for r in ranked:
		out.append({"id": String(r["id"]),
			"value": snappedf(float(r["value"]), 0.01),
			"read": bool(r["read"])})
	return out


## True when every wired picker tile on screen belongs to the shop's removal.
## Tested across ALL tiles rather than the one we happened to pick, because a
## mixed screen should still be answerable.
func _is_removal_picker(tiles: Array) -> bool:
	for t in tiles:
		if not is_instance_valid(t):
			continue
		for con in (t as Control).pressed.get_connections():
			if String((con["callable"] as Callable).get_method()) != "_confirm_removal":
				return false
	return not tiles.is_empty()


## The muster. Deck growth happens HERE and nowhere else, so a pilot that cannot
## press one of these tiles is a pilot that never tests a deck it built.
func _drive_recruit() -> bool:
	_recruit_why["visits"] = int(_recruit_why.get("visits", 0)) + 1
	var tiles := _wired_controls("gui_input", [RECRUIT_TILE_METHOD])
	if tiles.is_empty():
		_bail_recruit("no tiles wired")
		return false
	# The slate DEALS IN, and Recruit only sets `mouse_filter = STOP` on each card
	# at the end of the reveal. Aiming before that lands on whatever is behind the
	# card and reports an OCCLUSION against a screen that is merely still dealing
	# — the same settle discipline `_click_control` uses for a sliding control.
	var ready: Array = []
	for i in 24:
		ready.clear()
		for t in tiles:
			if is_instance_valid(t) and (t as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				ready.append(t)
		if not ready.is_empty():
			break
		await _wait(0.15)
		tiles = _wired_controls("gui_input", [RECRUIT_TILE_METHOD])
		if tiles.is_empty():
			_bail_recruit("tiles vanished mid-settle")
			return false
	if ready.is_empty():
		_bail_recruit("tiles never became clickable")
		return false
	await _think()
	var ranked := _rank_tiles(ready, false)
	var pick: Control = ranked[0]["tile"]
	_jr_write("recruit", {
		"offered": _jr_tiles(ready),
		"scored": _jr_ranked(ranked),
		"taken": _jr_tile_id(pick),
		"taken_value": snappedf(float(ranked[0]["value"]), 0.01),
	})
	var rs := get_node_or_null("/root/RunState")
	var before: int = 0 if rs == null else (rs.get("deck") as Array).size()
	# `exact` — the handler is `gui_input` on the tile itself. See _aim.
	if not await _click_control(pick, "enlist a recruit", true):
		_bail_recruit("click did not land")
		return false
	await _wait(1.2)
	# THE CLICK LANDING IS NOT THE ORACLE. `_click_control` returns true when the
	# press reached the control, which says nothing about whether the card entered
	# the deck — and that gap is precisely what hid the descendant-hit bug for a
	# whole soak (`offers taken 1`, deck still 11). Count the deck, not the click.
	if rs != null:
		var after: int = (rs.get("deck") as Array).size()
		if after <= before and _screen() == "Recruit":
			_finding("ENLIST_NO_OP",
				"a recruit tile took the press and no card entered the deck",
				{"deck_before": before, "deck_after": after,
				 "tile": _describe(pick)})
			_bail_recruit("pressed but deck did not grow")
			return false
		_recruits_taken += 1
	_bail_recruit("TOOK A CARD")
	_offers_taken += 1
	return true


## Why a muster did or did not produce a card. Counting only the successes told
## us the rate and never the reason, which is the difference between "the policy
## is wrong" and "it never reached a muster".
func _bail_recruit(reason: String) -> void:
	_recruit_why[reason] = int(_recruit_why.get(reason, 0)) + 1
	_log("recruit", reason)


## Camp. The three banners are identical unworded click catchers, so the choice
## has to be made on STATE rather than on the control: heal when the run is
## actually hurt, otherwise spend the stop on the deck.
func _drive_rest() -> bool:
	var banners := _wired_controls("pressed", [REST_BANNER_METHOD])
	if banners.is_empty():
		return false
	var want := "FORGE"
	var rs := get_node_or_null("/root/RunState")
	if rs != null:
		var mx: float = maxf(1.0, float(rs.get("hero_max_hp")))
		if float(rs.get("hero_hp")) / mx < REST_HEAL_BELOW:
			want = "REST"
	var pick: Control = null
	for b in banners:
		if _catcher_label(b as Control).find(want) >= 0:
			pick = b
			break
	if pick == null:
		# The wanted banner is disabled (full HP, or every card already forged —
		# `_wire_banner` leaves a disabled banner unconnected, so it never appears
		# here). Take whatever camp is still offering.
		pick = banners[banners.size() - 1]
	var offers: Array = []
	for b in banners:
		offers.append(_catcher_label(b as Control).substr(0, 32))
	_jr_write("camp", {
		"offered": offers, "wanted": want,
		"taken": _catcher_label(pick as Control).substr(0, 32),
		"got_what_it_wanted": _catcher_label(pick as Control).find(want) >= 0,
	})
	await _think()
	if not await _click_control(pick, "camp: %s" % _catcher_label(pick as Control)):
		return false
	_offers_taken += 1
	await _wait(1.0)
	return true


## The wagon. `_make_buy_button` only wires `_buy_*` when the ware is affordable
## AT BUILD TIME — an unaffordable one is wired to `_deny_transaction` instead —
## so the handler filter does most of the work. It is not sufficient on its own:
## a purchase does not rebuild every sibling, so a button wired when the purse
## was full stays wired after it empties, and `_buy_card` then returns SILENTLY
## on `RunState.gold < price`. Re-check the price the player can read.
func _drive_shop() -> bool:
	var rs := get_node_or_null("/root/RunState")
	if rs == null:
		return false
	var gold := int(rs.get("gold"))
	# READ THE WARE OFF THE HANDLER, NOT OFF THE LABEL. `_buy_card(id, price,
	# slot)` / `_buy_relic(id, price, tile)` / `_buy_potion(price, tile)` are all
	# bound with their arguments, so the id and the true price are available
	# exactly — where `_price_in` re-derives the price by scraping digits out of
	# display text and cannot tell a relic from a card at all.
	var shelf: Array = []
	for b in _wired_controls("pressed", SHOP_BUY_METHODS):
		var w := _shop_ware(b as Control, gold)
		if not w.is_empty():
			shelf.append(w)
	var affordable: Array = []
	for w in shelf:
		if bool(w["afford"]):
			affordable.append(w)
	if affordable.is_empty():
		return false
	await _think()
	if _policy_random:
		for w in affordable:
			w["value"] = _rng.randf() * 100.0
	affordable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["value"]) > float(b["value"]))
	var best: Dictionary = affordable[0]
	# NOT BUYING IS A MOVE. Gold carried to the next wagon buys a relic instead
	# of a fourth mediocre common, and the removal fee is 60 flat — a purse
	# emptied on chaff is a thinning the run cannot afford later.
	if float(best["value"]) < SHOP_MIN_VALUE:
		_jr_write("shop", {"shelf": shelf, "affordable": affordable.size(),
			"taken": "<none>", "best_value": snappedf(float(best["value"]), 0.01),
			"reason": "nothing on the shelf beat holding the gold"})
		return false
	var pick: Control = best["btn"]
	var label := _readable(pick)
	_jr_write("shop", {
		"shelf": shelf, "affordable": affordable.size(),
		"taken": label.substr(0, 48), "taken_card": String(best["id"]),
		"taken_kind": String(best["kind"]),
		"value": snappedf(float(best["value"]), 0.01),
		"price": int(best["price"]),
	})
	if not await _click_control(pick, "buy %s" % label):
		return false
	await _wait(0.9)
	# Same oracle rule as the muster: the press landing says nothing about whether
	# a purchase HAPPENED. `_buy_card` returns silently on `RunState.gold < price`,
	# and a tile wired while the purse was full stays wired after it empties — so
	# a dead buy button would otherwise be counted as a sale forever.
	if int(rs.get("gold")) < gold:
		_purchases += 1
		_offers_taken += 1
		return true
	_log("refused", "%s took the press and cost nothing" % label)
	return false


## Stat points per 100 gold below which the purse is better kept. Set from the
## road's own exchange rate, which this project has already published: one forge
## is worth about 90 gold (`WritDB.road_rule_worth`), and a forge is worth about
## two stat points on a card you actually draw.
const SHOP_MIN_VALUE := 1.6
## What a relic is worth in stat points. A FLAT number, and that is a real
## limitation stated rather than hidden: nothing here models a relic's effect,
## and 135 of them would need 135 models. It is set high because the owner's
## standing rule is that relics are positive — there is no trap relic to avoid —
## so "buy the relic" is right far more often than it is wrong, which is the
## most a flat term can ever be.
const RELIC_WORTH := 7.0
## A potion is one use, and the pilot only drinks when it is already losing.
const POTION_WORTH := 2.0


## One ware on the shelf: what it is, what it costs, what it is worth. Returns {}
## for a button whose handler carries no bound arguments, which is how an
## unaffordable ware is wired (`_deny_transaction`).
func _shop_ware(b: Control, gold: int) -> Dictionary:
	for con in b.pressed.get_connections():
		var call: Callable = con["callable"]
		var m := call.get_method()
		if not (m in SHOP_BUY_METHODS):
			continue
		var args := call.get_bound_arguments()
		var kind := "card"
		var id := ""
		var price := -1
		match m:
			"_buy_card":
				if args.size() < 2:
					continue
				id = String(args[0])
				price = int(args[1])
			"_buy_relic":
				kind = "relic"
				if args.size() < 2:
					continue
				id = String(args[0])
				price = int(args[1])
			"_buy_potion":
				kind = "potion"
				if args.size() < 1:
					continue
				price = int(args[0])
		if price < 0:
			continue
		var worth := 0.0
		match kind:
			"relic":
				worth = RELIC_WORTH
			"potion":
				worth = POTION_WORTH
			_:
				var d: Dictionary = _card_data_for(id)
				worth = 0.0 if d.is_empty() else BoardEval.draft_value(
					d, BoardEval.deck_profile(_deck_cards()))
		# Value per 100 gold, so a 50g common and a 100g relic are comparable.
		# Without the normalisation the policy simply buys the most expensive
		# thing on the shelf every time.
		var per := worth * 100.0 / maxf(float(price), 1.0)
		return {"btn": b, "kind": kind, "id": id, "price": price,
			"worth": snappedf(worth, 0.01), "value": per,
			"afford": price <= gold,
			"label": _readable(b).substr(0, 48)}
	return {}


func _card_data_for(id: String) -> Dictionary:
	var db := get_node_or_null("/root/CardDB")
	if db == null or id == "":
		return {}
	var d: Variant = db.call("get_card_data", id)
	return d if d is Dictionary else {}


## The number a price tag shows, e.g. "Buy — 50g" -> 50. Returns -1 when the
## label carries no price at all, which is the caller's signal to leave it alone
## rather than to treat it as free.
func _price_in(label: String) -> int:
	var digits := ""
	for ch in label:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif not digits.is_empty():
			break
	return -1 if digits.is_empty() else int(digits)


func _topmost_button(pool: Array) -> BaseButton:
	var best: BaseButton = null
	var best_layer := -9999
	for b in pool:
		if _score(b) <= -1000:
			continue
		var l := _layer_of(b)
		if l >= best_layer:
			best_layer = l
			best = b
	return best


# =========================================================================
#  COMBAT — the gesture that matters
# =========================================================================

func _drive_combat() -> void:
	var c := _scene_root()
	if c == null:
		return
	# One count per Combat INSTANCE — _drive_combat can return and be re-entered
	# on the same fight (a modal held the turn, a wait timed out).
	var fid := c.get_instance_id()
	if fid != _last_fight_id:
		_last_fight_id = fid
		_fights += 1
	# TWO separate counters, because they diagnose two different things and the
	# first cut conflated them: `turns` counts loop iterations and `_rounds` is
	# the game's own round number. A loop that spins without the round advancing
	# is NOT a long fight — it is the pilot failing to commit a turn (a disabled
	# END TURN, a modal it could not answer), and reporting that as "long fight"
	# points the investigation at the wrong half of the system.
	var turns := 0
	var last_round := -1
	var stalled := 0
	while _screen() == "Combat" and not _out_of_budget():
		turns += 1
		var rn := int(c.get("round_number"))
		if rn == last_round:
			stalled += 1
		else:
			stalled = 0
			last_round = rn
		if stalled == 4:
			# Before accusing the game, check for a picker holding the board.
			if await _escape_capture(c):
				stalled = 0
				continue
		if stalled >= 10:
			var eb: Variant = c.get("_end_turn_btn")
			_finding("TURN_NOT_COMMITTED",
				"round %d would not advance over 10 attempts" % rn,
				{"end_turn_disabled": (null if eb == null or not is_instance_valid(eb)
						else (eb as BaseButton).disabled),
				 "end_turn_text": ("" if eb == null or not is_instance_valid(eb)
						else _readable(eb)),
				 "modal_up": _modal_button() != null,
				 "phase": c.get("phase"), "hand": (c.get("_hand") as Array).size()})
			break
		if turns > 80:
			_finding("LONG_FIGHT",
				"fight reached round %d without ending" % rn, {"turns": turns})
			break
		await _maybe_answer_modal()
		if not await _wait_for_turn(c):
			break
		if _screen() != "Combat":
			break
		# A rung modal opens AT the top of the player phase, so it is up AFTER
		# readiness says the turn is live. Checking only before the wait misses it.
		# BOUNDED: an unbounded `while await ...` here is how a mis-detected modal
		# becomes a hang instead of a report.
		for _m in MODAL_ANSWER_TRIES:
			if not await _maybe_answer_modal():
				break
		await _maybe_drink(c)
		if _screen() != "Combat":
			break
		await _play_hand(c)
		if _screen() != "Combat":
			break
		await _end_turn(c)
	await _wait(0.6)


## Readiness. `phase == PLAYER_TURN` is NOT a readiness test — Phase is an enum
## whose PLAYER_TURN is 0 AND the member's uninitialised default, so it reads true
## on the very first tick with a null HUD. Gate on `round_number >= 1`, then wait
## for the hand to STOP GROWING: `_layout_hand` deals one card at a time, so a
## pilot that acts on a non-empty hand plays a one-card hand every turn.
func _wait_for_turn(c: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 60000
	var last_size := -1
	var stable := 0
	while Time.get_ticks_msec() < deadline:
		if _screen() != "Combat" or not is_instance_valid(c):
			return false
		if _out_of_budget():
			return false
		var phase: int = int(c.get("phase"))
		var rn: int = int(c.get("round_number"))
		if rn >= 1 and phase == 0:
			var h: Array = c.get("_hand")
			var n := h.size()
			if n == last_size:
				stable += 1
				if stable >= 8:
					if rn > _rounds:
						_rounds = rn
					return true
			else:
				stable = 0
				last_size = n
		elif phase == 2:
			return false   # GAME_OVER
		else:
			# A modal can hold the turn (THE INITIATIVE before round 1, a veterancy
			# rung after it). Answer whatever is on top rather than waiting it out.
			# NOT gated on `round_number >= 1`: the initiative opens at round 0 and
			# that guard is precisely why the pilot used to time out there.
			await _maybe_answer_modal()
		await _frames(2)
	var mb := _modal_button()
	_finding("TURN_TIMEOUT", "no player turn within 60s", {
		"round": c.get("round_number"), "phase": c.get("phase"),
		"unanswered_modal": ("none" if mb == null else _describe(mb)),
		"captured": (await _capture_blocker()) != null})
	return false


## A LAYER THRESHOLD IS THE WRONG ORACLE, and this cost four 60-second stalls in
## one windowed run before it was replaced. The veterancy rung modals do sit on
## their own CanvasLayer at 100 — but THE INITIATIVE's scrim is parented to the
## HUD layer (12) at `z_index = 200`, deliberately, because a plain child of
## Combat draws BENEATH the HUD. A `layer >= 30` rule cannot see it, so the pilot
## sat through `TURN_TIMEOUT` at round 0 four times against a game that was simply
## waiting to be answered.
##
## What actually decides who gets a click is Godot's paint order — (canvas layer,
## effective z, tree order) — so that is what this ranks by. The initiative's
## buttons beat the HUD's on z; a rung modal beats everything on layer.
const MODAL_LAYER := 30
## How many stacked modals the pilot will answer before giving up and letting the
## ordinary STUCK path report it. Bounded on purpose — see _capture_present.
const MODAL_ANSWER_TRIES := 6


func _paint_key(c: Control, order: int) -> Vector3:
	var z := c.z_index
	if c.z_as_relative:
		var p: Node = c.get_parent()
		while p is CanvasItem:
			z += (p as CanvasItem).z_index
			if not (p as CanvasItem).z_as_relative:
				break
			p = p.get_parent()
	return Vector3(float(_layer_of(c)), float(z), float(order))


## Is something modal standing over the screen right now? Synchronous, so it can
## be asked from anywhere: a visible Control with MOUSE_FILTER_STOP covering
## essentially the whole canvas is, by construction, swallowing every click under
## it — whatever the author called it.
##
## THIS REPLACED A LAYER THRESHOLD, WHICH WAS WRONG FOR A THIRD TIME. Godot picks
## by (canvas layer, z, TREE ORDER), and this game uses all three: the veterancy
## rungs get their own CanvasLayer at 100, THE INITIATIVE rides z_index 200 on the
## HUD layer, and `MapView._show_relic_viewer` sets NEITHER — it is a bare
## full-rect ColorRect that is on top purely because it was added last. All three
## are perfectly good modals. A threshold on any single term misses the others,
## and the pilot then cannot find the close button, cannot get out, and thrashes
## against a screen it opened itself.
## IT MUST CONTAIN A BUTTON, and that clause is the whole difference between an
## OVERLAY and a BACKDROP. `ColorRect`'s `mouse_filter` defaults to STOP, so every
## scene's full-rect background satisfies "visible, STOP, covers the canvas" — the
## first cut of this therefore reported a capture on EVERY screen, `_modal_button`
## always returned something, and `while await _maybe_answer_modal(): pass` span
## forever. The pilot did not fail, it HUNG, which is the worse outcome: exit 124
## and no report at all.
##
## A modal has controls in it; a backdrop does not.
func _capture_present() -> Control:
	var found: Array = []
	_walk_captures(get_tree().root, _canvas(), 0, found)
	# Last in the walk = latest in tree order = the one actually on top.
	for i in range(found.size() - 1, -1, -1):
		var c: Control = found[i]
		var inner: Array = []
		_walk_buttons(c, inner, 0)
		if not inner.is_empty():
			return c
	return null


func _walk_captures(n: Node, cv: Vector2, depth: int, out: Array) -> void:
	if depth > 40:
		return
	if n is Control:
		var c := n as Control
		if c.visible and c.mouse_filter == Control.MOUSE_FILTER_STOP 				and c.is_visible_in_tree():
			var r := c.get_global_rect()
			if r.size.x >= cv.x * 0.9 and r.size.y >= cv.y * 0.9 					and c != get_tree().current_scene:
				out.append(c)
	for ch in n.get_children():
		_walk_captures(ch, cv, depth + 1, out)


## The button a modal is asking us to press.
##
## "WHICH BUTTON IS ON TOP" AND "WHICH BUTTON BELONGS TO A MODAL" ARE DIFFERENT
## QUESTIONS, and this asked the first while needing the second. It took the
## GLOBAL highest paint key and then tested whether THAT button was modal - so an
## ordinary button sitting on a higher CanvasLayer than the modal was enough to
## hide the modal completely.
##
## THE INITIATIVE is exactly that shape, and it cost a 60-second stall per
## General fight: its scrim is `z_index = 200` on the **HUD layer (12)** -
## deliberately, because a plain child of Combat draws beneath the HUD - while
## **the hand sits on layer 20**. Any hand-layer button therefore outranked it,
## the `best_key.y > 0` test was applied to the wrong button, and
## `_capture_present`'s containment check failed for the same reason. The pilot
## sat at `round 0, phase 0, captured: true, unanswered_modal: "none"` until it
## timed out - FIVE times in one windowed run, ~300s of a 660s budget. Headless
## never meets it, because the initiative and the rungs auto-pick there.
##
## So: rank ALL candidates by paint order and return the top one that actually
## QUALIFIES as modal, instead of testing only the global maximum.
## LOW_PRIORITY is excluded here specifically - "?" and LOG sit on the HUD and
## would otherwise be a plausible "top" answer on a screen with no modal at all.
func _modal_button() -> BaseButton:
	var pool := _all_buttons()
	var ranked: Array = []
	for i in pool.size():
		var b: BaseButton = pool[i]
		var sc := _score(b)
		if sc <= -1000 or sc <= 5:
			continue
		ranked.append({"b": b, "k": _paint_key(b, i)})
	if ranked.is_empty():
		return null
	ranked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var a: Vector3 = x["k"]
		var c: Vector3 = y["k"]
		if a.x != c.x:
			return a.x > c.x
		if a.y != c.y:
			return a.y > c.y
		return a.z > c.z)
	# Tree-order modals (MapView's relic viewer is a bare full-rect ColorRect with
	# no layer and no z) are recognised by CONTAINMENT, so the capture is resolved
	# once here rather than per candidate.
	var cap := _capture_present()
	for e in ranked:
		var k: Vector3 = e["k"]
		var b2: BaseButton = e["b"]
		# Outranks the ordinary board on its own layer or z...
		if k.x >= float(MODAL_LAYER) or k.y > 0.0:
			return b2
		# ...or is inside the thing demonstrably covering the screen.
		if cap != null and cap.is_ancestor_of(b2):
			return b2
	return null


## Answer whatever is holding the board, and say whether anything was answered.
##
## THE CASE THIS EXISTS FOR, found by the WINDOWED pilot and invisible headless:
## a veterancy rung modal opens at the top of a PLAYER PHASE — `phase` is
## PLAYER_TURN and the hand is dealt and stable, so every readiness test says
## "your move", while a layer-100 overlay holds the board and refuses every drag.
## Headless auto-picks the first option so probes never stall there, which is
## exactly why nothing had ever met it. Without this the pilot spun 60 turns on
## round 11 and reported STUCK against a game that was behaving correctly.
func _maybe_answer_modal() -> bool:
	var top := _modal_button()
	if top == null:
		return false
	var before := _blocked_streak
	if await _click_control(top, "answer modal on L%d" % _layer_of(top)):
		await _wait(0.35)
		return true
	# It could not even be pressed — restore the streak so a truly dead modal
	# still trips STUCK rather than being silently absorbed here.
	_blocked_streak = before + 1
	return false


## NOT EVERY BLOCKER IS A CanvasLayer, and the pilot's first windowed run froze
## on one for 60 turns because of it. `_pick_friendly_creature` and its three
## siblings add a FULL-RECT `MOUSE_FILTER_STOP` ColorRect at `z_index = 155`
## straight onto the combat scene — no layer, no button — so `_modal_button()`
## cannot see it and the board is simply dead. A player answers one by clicking a
## candidate, or by right-clicking to cancel; so does this.
func _capture_blocker() -> Control:
	var cv := _canvas()
	_move(cv * 0.5)
	await _frames(2)
	var got := _hover()
	if got == null or got is BaseButton:
		return null
	var r: Rect2 = got.get_global_rect()
	if r.size.x >= cv.x * 0.9 and r.size.y >= cv.y * 0.9:
		return got
	return null


## Answer a picker the way a player does: offer it a candidate, then cancel.
func _escape_capture(c: Node) -> bool:
	var cap := await _capture_blocker()
	if cap == null:
		return false
	_log("capture", "board held by %s" % _describe(cap))
	# A friendly body is the answer to most of these prompts.
	for row in [0, 1]:
		for body in c.call("_row_array", false, row):
			if body == null or not is_instance_valid(body):
				continue
			await _click_at(_centre_of(body))
			await _wait(0.25)
			if await _capture_blocker() == null:
				return true
	# Otherwise take the universal out.
	await _right_click_at(_canvas() * 0.5)
	await _wait(0.3)
	if await _capture_blocker() == null:
		return true
	_finding("CAPTURE_STUCK",
		"a full-screen input capture held the board and neither a candidate " 		+ "click nor right-click released it",
		{"blocker": _describe(cap)})
	return false


## RE-DECIDE AFTER EVERY PLAY, and that is the whole difference between scoring a
## hand and scoring a turn. A sort ranks the hand ONCE against the board as it was
## at the top of the turn — but the board is exactly what each play changes, so by
## the second card the ranking describes a position that no longer exists. The
## previous version sorted by cost descending and walked the list; this one asks
## "what is the best play available RIGHT NOW" every time, which is what makes a
## removal spell get re-evaluated after the body it was going to kill has already
## been blocked, and what lets a lane choice answer the board it is actually in.
func _play_hand(c: Node) -> void:
	_refused_this_turn.clear()
	_turn_plays = 0
	# Bounded: a hand is at most 10 and every iteration must consume a card, but a
	# refused play leaves it in hand, so an unbounded loop here would spin.
	for _i in 14:
		if _out_of_budget() or _screen() != "Combat":
			return
		if _modal_button() != null:
			# Something opened mid-turn (a rung, a discovery, a pile viewer).
			# Answer it before trying to drag through it.
			for _m in MODAL_ANSWER_TRIES:
				if not await _maybe_answer_modal():
					break
		var choice := _choose_play(c)
		if choice.is_empty():
			return
		var card: Control = choice["card"]
		var play: Dictionary = choice["play"]
		_log("choose", "%s  score=%.2f%s" % [
			String((card.get("card_data") as Dictionary).get("name", "?")),
			float(choice["score"]),
			"" if bool(play.get("known", true)) else "  (unscored)"])
		if String(play.get("kind", "creature")) == "spell":
			await _play_spell(c, card, play.get("target"))
		else:
			await _play_creature(c, card,
				_slot_node(c, int(play.get("row", 0)), int(play.get("lane", 0))))
		# A card that would not go down stays in hand and would be chosen again
		# forever. One refusal is reported by _report_refusal; the loop must not
		# keep re-offering it.
		#
		# `c` IS CHECKED AT THE CALL BOUNDARY, not inside `_in_hand`. GDScript
		# validates a TYPED argument's class at the call, and a freed object has
		# no class to report — so `_in_hand(c: Node, ...)` throws before its own
		# guards can run, exactly the hazard its header documents for `card`.
		# The play above can end the fight, which frees the Combat scene.
		if not is_instance_valid(c) or _screen() != "Combat":
			return
		if _in_hand(c, card):
			_refused_this_turn[card.get_instance_id()] = true


## Score every affordable play on the CURRENT board and pick one. Returns
## {card, play, score, cost} or {}.
func _choose_play(c: Node) -> Dictionary:
	var mana := int(c.get("player_mana"))
	var options: Array = []
	for card in (c.get("_hand") as Array):
		if card == null or not is_instance_valid(card) \
				or not (card as Control).is_visible_in_tree():
			continue
		if _refused_this_turn.has(card.get_instance_id()):
			continue
		var data: Dictionary = card.get("card_data")
		if _is_curse(String(data.get("id", ""))):
			continue
		var cost := _cost_of(c, card)
		if cost > mana:
			continue
		# `mine_is_enemy` is FALSE: the pilot plays the player side. That single
		# argument is why this is the bot's scorer and not a copy of it.
		var play: Dictionary = BoardEval.score_play(c, false, data)
		if play.is_empty():
			continue
		var score := float(play.get("score", 0.0))
		if not bool(play.get("known", true)):
			score = UNKNOWN_SPELL_SCORE
		# Cheap-first nudge, matching the bot: a 1-drop edges out an equal-scored
		# 3-drop, because the Command left over can still buy something.
		score -= float(cost) * 0.15
		options.append({"card": card, "play": play, "score": score, "cost": cost})
	if options.is_empty():
		# NOT SILENCE. "Nothing was playable" is a measurement about the cost
		# curve against the Command ramp, and it is invisible in a log that only
		# records plays that happened.
		#
		# ONLY ON THE FIRST CALL OF THE TURN, and the first version of this got
		# it wrong in a way worth keeping: `_play_hand` loops until this returns
		# {}, so EVERY turn ends here — the record was being written once per
		# turn unconditionally and the analyser duly reported "31.6% of turns had
		# no legal play" about a bot that was spending its Command down to zero.
		# A counter of loop exits wearing the name of a game measurement.
		if _turn_plays == 0:
			_jr_write("no_play", {
				"round": int(c.get("round_number")), "mana": mana,
				"hand": _jr_hand(c), "board": _jr_board(c),
			})
		return {}
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	_jr_last_play = {
		"round": int(c.get("round_number")), "mana": mana,
		"php": int(c.get("player_hp")), "ehp": int(c.get("enemy_hp")),
		"board": _jr_board(c),
		"options": _jr_options(options),
	}
	if _greedy or _rng.randf() < PILOT_GREED:
		_jr_commit_play(options[0], 0)
		return options[0]
	# Explore: sample the top few, weighted by score. Shifted so the weakest
	# candidate still has a real chance and a negative score is not a negative
	# weight — this branch exists precisely to visit plays the argmax would never
	# make, so it must not collapse back onto the argmax.
	var top: Array = options.slice(0, mini(EXPLORE_TOP_N, options.size()))
	var lowest := float(top[top.size() - 1]["score"])
	var total := 0.0
	for o in top:
		total += (float(o["score"]) - lowest) + 1.0
	var roll := _rng.randf() * total
	for i in top.size():
		var o: Dictionary = top[i]
		roll -= (float(o["score"]) - lowest) + 1.0
		if roll <= 0.0:
			_jr_commit_play(o, i)
			return o
	_jr_commit_play(top[0], 0)
	return top[0]


## Every option the scorer ranked, best first. The RANK of the one taken is what
## makes the exploration branch separable from the argmax one offline — without
## it a sampled play and a best play are the same row.
func _jr_options(options: Array) -> Array:
	var out: Array = []
	for o in options:
		var play: Dictionary = o["play"]
		var d: Dictionary = (o["card"] as Control).get("card_data")
		out.append({
			"card": _jr_card(d),
			"score": snappedf(float(o["score"]), 0.01),
			"cost": int(o["cost"]),
			"kind": String(play.get("kind", "creature")),
			"row": int(play.get("row", -1)),
			"lane": int(play.get("lane", -1)),
			"known": bool(play.get("known", true)),
		})
	return out


func _jr_commit_play(chosen: Dictionary, rank: int) -> void:
	_turn_plays += 1
	if _jr_last_play.is_empty():
		return
	var rec: Dictionary = _jr_last_play
	rec["nth_this_turn"] = _turn_plays - 1
	rec["taken"] = String(((chosen["card"] as Control).get("card_data")
		as Dictionary).get("id", "?"))
	rec["taken_rank"] = rank
	rec["explored"] = rank > 0
	_jr_write("play", rec)
	_jr_last_play = {}


func _jr_hand(c: Node) -> Array:
	var out: Array = []
	for card in (c.get("_hand") as Array):
		if card == null or not is_instance_valid(card):
			continue
		out.append(_jr_card((card as Control).get("card_data")))
	return out


## The drop target for a lane/row the scorer chose. Null when that slot is not a
## real, live Control — the caller then falls back to first-empty.
func _slot_node(c: Node, row: int, lane: int) -> Control:
	var slots: Array = c.call("_slot_array", false, row)
	if lane < 0 or lane >= slots.size():
		return null
	var s: Variant = slots[lane]
	return s if s != null and is_instance_valid(s) else null


## `card in _hand` ERRORS when the card has been freed — _hand is Array[Control]
## and a freed element fails the typed-array validation rather than returning
## false. Combat frees cards on cascade/exhaust, so this is the normal case.
func _in_hand(c: Node, card: Variant) -> bool:
	if card == null or not is_instance_valid(card) or not is_instance_valid(c):
		return false
	return card in (c.get("_hand") as Array)


func _is_curse(id: String) -> bool:
	var db := get_node_or_null("/root/CardDB")
	if db == null or not db.has_method("is_curse"):
		return false
	return bool(db.call("is_curse", id))


## Untyped `card` for the same reason as `_note_play` — this is reached from
## `_report_refusal` on the failure path, which is exactly where a freed card
## turns up.
func _cost_of(c: Node, card: Variant) -> int:
	if card == null or not is_instance_valid(card):
		return 99
	if c.has_method("_effective_cost"):
		return int(c.call("_effective_cost", card))
	return int((card.get("card_data") as Dictionary).get("cost", 99))


## The grab point. A resting hand card hangs mostly BELOW the screen fold and is
## scaled to ~0.72 about a bottom-centre pivot, so its rect centre is routinely
## off-canvas. Walk down the card's own axis for the first point that is both on
## canvas and actually hit-testable as this card.
func _grab_point(card: Control) -> Vector2:
	var xf := card.get_global_transform()
	# Upper third first: that is the strip a resting hand card actually shows.
	for fy in [0.18, 0.28, 0.38, 0.10, 0.50]:
		var p: Vector2 = xf * Vector2(card.size.x * 0.5, card.size.y * fy)
		if _on_canvas(p):
			return p
	return xf * (card.size * 0.5)


## FIND A BIT OF THE CARD THAT IS ACTUALLY SHOWING, and ask the engine which bit
## that is rather than assuming the middle.
##
## A hand is a FAN: every card is partly under its neighbour, by design. Aiming at
## the horizontal centre therefore lands on the next card along whenever the hand
## is full — which the pilot dutifully reported as an OCCLUSION, blaming the
## layout for doing the one thing a fan is for. A player does not have this
## problem because they aim at a part they can SEE, so the pilot now does the
## same: walk candidate points across the face and take the first the engine
## agrees belongs to this card. Only if every candidate misses is something
## genuinely in the way.
func _find_grab(card: Control) -> Dictionary:
	var xf := card.get_global_transform()
	var last: Dictionary = {"ok": false, "got": null, "desc": "<nothing>"}
	# Leading edge first, then inward — in a left-to-right fan the left of each
	# card is the exposed strip.
	for fx in [0.22, 0.5, 0.78]:
		for fy in [0.18, 0.32]:
			var p: Vector2 = xf * Vector2(card.size.x * fx, card.size.y * fy)
			if not _on_canvas(p):
				continue
			var a: Dictionary = await _aim(card, p)
			if not is_instance_valid(card):
				return {"ok": false, "got": null, "desc": "<freed>"}
			if bool(a["ok"]):
				a["point"] = p
				# The LOCAL fraction, not just the screen point, and that is the
				# half that matters: the caller hovers the card before it presses,
				# the card LIFTS, and the verified screen point is then stale. A
				# fraction survives the lift — reapplying it to the card's new
				# transform gives the same spot ON THE CARD, which is what was
				# checked. See _play_creature for what the stale version cost.
				a["local"] = Vector2(fx, fy)
				return a
			last = a
	last["point"] = _grab_point(card)
	return last


## Re-derive the engine-verified grab point against the card's CURRENT transform.
func _regrab(card: Control, aim: Dictionary) -> Vector2:
	if not aim.has("local"):
		return _grab_point(card)
	var f: Vector2 = aim["local"]
	var p: Vector2 = card.get_global_transform() * Vector2(
		card.size.x * f.x, card.size.y * f.y)
	return p if _on_canvas(p) else _grab_point(card)


## `want_slot` is the lane/row BoardEval picked. It can legitimately be null — the
## scorer reads the board a moment before the drag and a summon or a death can
## fill that slot in between — so first-empty stays as the fallback.
func _play_creature(c: Node, card: Control, want_slot: Control = null) -> void:
	var slot := want_slot
	if slot == null or not is_instance_valid(slot):
		slot = _empty_slot(c)
	if slot == null:
		return
	var name_s := String((card.get("card_data") as Dictionary).get("name", "?"))

	# Hover first, like a hand does — the card LIFTS, which moves the thing we
	# are about to grab. Re-read the transform after the lift or the press lands
	# where the card used to be.
	var aim: Dictionary = await _find_grab(card)
	if not bool(aim["ok"]):
		# A spell mid-cast is DETACHED from the hand container and floats over it
		# (see Combat's _targeting_spell), so it legitimately covers other cards.
		# Reporting that as an occlusion blames the layout for a live interaction.
		if c.get("_targeting_spell") == null and is_instance_valid(card):
			_note_block(card, aim["got"], "pick up %s" % name_s, String(aim["desc"]))
		return
	await _wait(0.28)
	# The hover-and-settle above is an await, so the card can be freed inside it
	# (a discard sweep, a fight ending). `_regrab(card: Control, ...)` validates
	# its argument's class AT THE CALL and a freed object has none, so the throw
	# lands before any guard inside could run.
	if not is_instance_valid(card):
		return
	# THE VERIFIED POINT, not a fresh guess. `_find_grab` just asked the engine
	# which part of this card the engine agrees is this card — and then this line
	# threw the answer away and re-derived a point from `_grab_point`, which
	# consults nothing. In a full fan that point is routinely under the NEXT card
	# along, so the press grabbed the neighbour, the intended card never moved,
	# and the pilot reported SILENT_REFUSAL against a game that had correctly said
	# nothing because nothing had been dragged. Two of those in one 13-minute soak.
	var grab := _regrab(card, aim)
	var target := _centre_of(slot)
	await _drag(grab, target, maxf(slot.size.x, 90.0))
	await _wait(0.35)

	# Same freed-scene window as `_play_spell` — a creature whose on-enter kills
	# the last foe ends the fight inside the drag.
	if not is_instance_valid(c) or _screen() != "Combat":
		_cards_played += 1
		return

	if _in_hand(c, card):
		_report_refusal(c, card, name_s, "onto an empty lane", {})
		return
	_cards_played += 1
	_note_play(c, card)
	_log("play", "%s -> lane" % name_s)
	await _check_card_landed(c, card, name_s)


## DID THE CARD ACTUALLY ARRIVE? (2026-09-20, from a player report of "cards
## just disappear after you play them".)
##
## `_probe_card_play` already gates this and passes — but it gates a STAGED
## fixture: one card, one slot, no encounter passives, nothing else in flight.
## This asks the same question of every creature the pilot plays across real
## fights, which is the only version of it that can catch a case the fixture
## does not build.
##
## THE CARD IS THE SAME NODE THROUGHOUT. Combat flies the hand card to its lane
## and re-parents it there — it does not spawn a fresh token — so after a
## successful play the node must be alive, visible, and standing inside the
## board. Any other state is the card having disappeared.
##
## Deliberately AFTER a settle: the flight runs 0.40s at normal speed and this
## is called the moment the drag releases, so checking immediately would report
## every card as missing while it is still in the air.
const LANDING_SETTLE_SEC := 0.75


func _check_card_landed(c: Node, card: Variant, name_s: String) -> void:
	await _wait(LANDING_SETTLE_SEC)
	if not is_instance_valid(c) or _screen() != "Combat":
		return
	# A body can legitimately be GONE by now: an on-enter that kills it, a
	# passive that sweeps the board, a trade resolved by a Swift defender. The
	# board arrays are the authority on whether it is supposed to be standing,
	# so a card that is absent from them is not a finding.
	var on_board := false
	for row in [0, 1]:
		for b in c.call("_row_array", false, row):
			if b != null and is_instance_valid(b) and b == card:
				on_board = true
	if not on_board:
		return
	var vis: bool = (card as Control).is_visible_in_tree()
	var mod_a: float = (card as Control).modulate.a
	var r: Rect2 = Rect2((card as Control).global_position,
		(card as Control).size * (card as Control).scale)
	var cv := _canvas()
	var off_canvas: bool = r.end.x < 0.0 or r.end.y < 0.0 \
		or r.position.x > cv.x or r.position.y > cv.y
	if vis and mod_a > 0.05 and not off_canvas:
		return
	_finding("CARD_VANISHED",
		"%s is on the board but cannot be seen" % name_s,
		{"visible_in_tree": vis, "modulate_a": snappedf(mod_a, 0.01),
		 "off_canvas": off_canvas, "rect": str(r),
		 "parent": ("<none>" if (card as Control).get_parent() == null
			else String((card as Control).get_parent().name)),
		 "round": int(c.get("round_number"))})


## `preferred` is the body BoardEval chose to hit. It is only a PREFERENCE: the
## contract still decides how many clicks the spell needs and which sides they
## must come from, so `_resolve_targeting` uses it for the first pick and falls
## back to its own choice for anything it does not satisfy.
func _play_spell(c: Node, card: Control, preferred: Variant = null) -> void:
	var data: Dictionary = card.get("card_data")
	var name_s := String(data.get("name", "?"))
	var targeting := String(data.get("targeting", "none"))
	var aim: Dictionary = await _find_grab(card)
	if not bool(aim["ok"]):
		if is_instance_valid(card):
			_note_block(card, aim["got"], "pick up %s" % name_s, String(aim["desc"]))
		return
	await _wait(0.28)
	if not is_instance_valid(card):
		return
	var grab := _regrab(card, aim)   # see _play_creature
	# Anywhere on the board above the play threshold commits a spell.
	var board := Vector2(_canvas().x * 0.5, _canvas().y * 0.42)
	await _drag(grab, board, 220.0)
	await _wait(0.3)

	# THE SCENE CAN DIE INSIDE THE DRAG, and this cost real data before it was
	# guarded. A spell that kills the last enemy ends the fight, `_check_game_over`
	# arms a fade, and by the time the drag's awaits return `c` is a freed Combat
	# — `c.get(...)` then throws "previously freed instance", which ABORTS this
	# function where it stands. The visible consequence is not the error line: an
	# abandoned cast leaves Combat's `_input()` targeting override armed, it eats
	# the NEXT click, and the pilot reports a false OCCLUDED against whatever
	# happened to be under the cursor. `_note_play`'s header records the same
	# class from the other end. Two of these appeared in the first soak.
	if not is_instance_valid(c) or _screen() != "Combat":
		_cards_played += 1
		_log("cast", "%s (the fight ended on it)" % name_s)
		return

	if c.get("_targeting_spell") != null:
		if not await _resolve_targeting(c, targeting, name_s, board, preferred):
			return
	if not is_instance_valid(c):
		return

	if _in_hand(c, card):
		_report_refusal(c, card, name_s, "onto the board", {"targeting": targeting})
		return
	_cards_played += 1
	_note_play(c, card)
	_log("cast", name_s)


## A refused play is only a defect if the game said NOTHING. `_refuse_play` is
## Combat's one honest way to decline, and it writes the reason to the info line;
## a refusal that leaves that line untouched is a dead drop from the player's
## side — they dragged, nothing happened, and no one told them why. That is
## `_probe_silent_refusal`'s class (C18) caught LIVE, mid-gesture, on a real board
## instead of inferred from source.
## Untyped `card` — same call-boundary hazard as `_note_play`, and this one runs on
## the REFUSAL path, where the card is most likely to have been freed already.
func _report_refusal(c: Node, card: Variant, name_s: String, how: String,
		extra: Dictionary) -> void:
	var info := _info_line(c).strip_edges()
	var detail := {
		"cost": _cost_of(c, card), "command": int(c.get("player_mana")),
		"round": int(c.get("round_number")), "said": info,
	}
	detail.merge(extra)
	if info.is_empty():
		_silent_refusals += 1
		_finding("SILENT_REFUSAL",
			"dragging %s %s left it in hand AND said nothing" % [name_s, how], detail)
	else:
		# Correct behaviour. Logged so the report can prove refusals were exercised.
		_log("refused", "%s — %s" % [name_s, info])


## SOME CONTRACTS TAKE TWO CLICKS, and assuming one cost 10 false findings.
## `two_enemies` wants two DIFFERENT enemies; `friendly_then_enemy` wants one of
## each; `friendly_lane` wants a friendly and then an EMPTY ADJACENT LANE in that
## creature's own row. Clicking once and then asserting "it is still in targeting"
## accused `Crossed Orders` of ignoring a legal target 10 times over, against code
## doing exactly what it says — and then produced two more OCCLUDED reports
## downstream, because the spell it had left mid-cast was floating over the hand.
## One wrong assumption in an oracle does not stay one wrong finding.
func _resolve_targeting(c: Node, targeting: String, name_s: String,
		board: Vector2, preferred: Variant = null) -> bool:
	for step in 3:
		if c.get("_targeting_spell") == null:
			return true
		var tgt := _next_target(c, targeting, step)
		# BoardEval's pick wins the FIRST click when it is still a live body —
		# that is the whole point of scoring a target. It is only used for step 0:
		# the later steps of a multi-click contract are decided against what the
		# game actually accepted, which the scorer knows nothing about.
		if step == 0 and preferred != null and is_instance_valid(preferred) \
				and (preferred as Control).is_visible_in_tree() \
				and _side_allows(c, targeting, preferred):
			tgt = preferred
		if tgt == null:
			break
		await _click_at(_centre_of(tgt))
		await _wait(0.35)
	if c.get("_targeting_spell") == null:
		return true
	# Could not satisfy it. Back out the way a player does, then judge: a refusal
	# to cancel is a genuine trap, an unsatisfiable contract only a note.
	await _right_click_at(board)
	await _wait(0.25)
	if c.get("_targeting_spell") != null:
		_finding("TARGET_STUCK",
			"%s stayed in targeting and right-click did not cancel it" % name_s,
			{"targeting": targeting})
	else:
		_log("cancel", "%s — could not satisfy %s" % [name_s, targeting])
	return false


## The node to click for this contract at this step. Step 1 reads the game's own
## `_targeting_first_target`, so the second pick is chosen against what the game
## actually accepted rather than what the pilot assumed it accepted.
func _next_target(c: Node, targeting: String, step: int) -> Control:
	var first: Variant = c.get("_targeting_first_target")
	var first_ok: bool = first != null and is_instance_valid(first)
	if step == 0:
		match targeting:
			"enemy_creature", "two_enemies":
				return _pick_target(c, "enemy_creature")
			"friendly_creature", "friendly_then_enemy", "friendly_lane":
				return _pick_target(c, "friendly_creature")
			_:
				return _pick_target(c, targeting)
	match targeting:
		"two_enemies":
			# Must be a DIFFERENT enemy — the game rejects a repeat by name.
			for row in [0, 1]:
				for body in c.call("_row_array", true, row):
					if body != null and is_instance_valid(body) and body != first:
						return body
			return null
		"friendly_then_enemy":
			return _pick_target(c, "enemy_creature")
		"friendly_lane":
			if not first_ok:
				return null
			# An EMPTY lane exactly one step away, in the mover's own row.
			var row: int = int(first.current_row)
			var lane: int = int(first.current_lane)
			var bodies: Array = c.call("_row_array", false, row)
			var slots: Array = c.call("_slot_array", false, row)
			for l in [lane - 1, lane + 1]:
				if l >= 0 and l < bodies.size() and bodies[l] == null 						and l < slots.size() and slots[l] != null 						and is_instance_valid(slots[l]):
					return slots[l]
			return null
	return null


## Is `node` on the side this contract's FIRST pick must come from?
##
## BoardEval chooses a target from the EFFECT's semantics (a damage spell wants a
## foe, a buff wants a friendly) while the card's `targeting` string is a separate
## statement of the same thing. They agree on every card today — but a card whose
## two halves disagreed would have the pilot clicking a body the game is going to
## refuse, which reads as a dead click rather than as the disagreement it is. So
## the contract is checked, and the scorer's pick is dropped if it loses.
func _side_allows(c: Node, targeting: String, node: Variant) -> bool:
	var side := _node_side(c, node)
	match targeting:
		"enemy_creature", "two_enemies":
			return side == 1
		"friendly_creature", "friendly_then_enemy", "friendly_lane":
			return side == 0
		"any_creature", "any":
			return side >= 0
	return false


## 0 = the player's side, 1 = the enemy's, -1 = not on the board at all.
func _node_side(c: Node, node: Variant) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	for is_enemy in [false, true]:
		for row in [0, 1]:
			for b in c.call("_row_array", is_enemy, row):
				if b == node:
					return 1 if is_enemy else 0
	return -1


func _pick_target(c: Node, targeting: String) -> Control:
	var want_enemy := targeting == "enemy_creature"
	var want_friend := targeting == "friendly_creature"
	var sides: Array = []
	if want_enemy:
		sides = [true]
	elif want_friend:
		sides = [false]
	else:
		sides = [true, false]
	for is_enemy in sides:
		for row in [0, 1]:
			for body in c.call("_row_array", is_enemy, row):
				if body != null and is_instance_valid(body) \
						and (body as Control).is_visible_in_tree():
					return body
	return null


## WHERE a body goes is a decision, not a scan order. First-empty means lane 0
## every time, so the pilot stacked its whole line into the left of the board and
## left the enemy's heaviest hitter swinging into an empty column all fight — it
## was testing placement without ever testing a block. Answer the biggest threat
## first, then fill left to right.
func _empty_slot(c: Node) -> Control:
	var threat := _hottest_enemy_lane(c)
	# Front row first — that is where a player puts a body they want swinging.
	for row in [0, 1]:
		var bodies: Array = c.call("_row_array", false, row)
		var slots: Array = c.call("_slot_array", false, row)
		var order: Array = []
		if threat >= 0 and threat < bodies.size():
			order.append(threat)
		for lane in range(bodies.size()):
			if lane != threat:
				order.append(lane)
		for lane in order:
			if bodies[lane] == null and lane < slots.size() \
					and slots[lane] != null and is_instance_valid(slots[lane]):
				return slots[lane]
	return null


## The enemy column that hits hardest right now, by the game's own
## `effective_atk` rather than the printed number — a buffed 2/2 is the threat,
## and the printed stat would not say so. -1 when the board is empty.
func _hottest_enemy_lane(c: Node) -> int:
	var best := -1
	var best_atk := 0
	for row in [0, 1]:
		var bodies: Array = c.call("_row_array", true, row)
		for lane in bodies.size():
			var body: Variant = bodies[lane]
			if body == null or not is_instance_valid(body):
				continue
			var atk := int(body.call("effective_atk"))
			if atk > best_atk:
				best_atk = atk
				best = lane
	return best


## ── THE BELT ─────────────────────────────────────────────────────────────
## Nothing in this harness drinks. `_probe_content_census` proves a potion can be
## ROLLED and `_probe_silent_refusal` reads the belt's guards out of source, but
## no test has ever pressed a bottle on a live board — which is exactly where the
## belt's known standing trap lives (it draws whatever the slot holds without
## filtering `usable_in`, so the first map-only potion added to PotionDB renders a
## lit, clickable, completely dead slot). Pressing it is the only way to find that.
##
## Drinking is gated on being genuinely hurt so the pilot does not simply empty
## the belt on round 1 and test the same path with none of the pressure.
const POTION_HP_FRACTION := 0.40


## A BOTTLE UNDRUNK AT THE END OF A RUN IS A BOTTLE WASTED, and the old rule
## (HP under 40%, slot 0 only) left most of the belt corked for the whole game.
## Two additions, both of them things a player does:
##
##  · LOSING THE BOARD IS ALSO AN EMERGENCY. A run that is four stat points
##    behind on round three is losing the fight whatever its HP says, and that
##    is precisely the window where a potion turns a fight — after it, nothing
##    does. Measured shape of every loss in `PILOT_DIFFICULTY_20260915.md`:
##    behind on the first exchange, dead nine rounds later.
##  · THE WHOLE BELT, NOT SLOT 0. Always reaching for the first bottle means a
##    map-only potion parked in that slot blocks every drink for the rest of the
##    run — which is the standing `usable_in` trap, seen from the player's side.
const POTION_BEHIND_BY := 6


func _maybe_drink(c: Node) -> void:
	if int(c.get("phase")) != 0:
		return                       # the belt refuses mid-clash, and says so
	var mx: float = maxf(1.0, float(c.get("player_max_hp")))
	var hurt := float(c.get("player_hp")) / mx < POTION_HP_FRACTION
	var losing := int(c.get("round_number")) >= 2 \
		and _board_gap(c) <= -POTION_BEHIND_BY
	if not hurt and not losing:
		return
	var rs := get_node_or_null("/root/RunState")
	if rs == null:
		return
	var belt: Array = rs.get("potions")
	if belt.is_empty():
		return
	# Rotate the slot with the round so a dead bottle at the front of the belt
	# cannot swallow every attempt for the rest of the fight.
	var btn: Control = null
	for off in belt.size():
		var idx := (int(c.get("round_number")) + off) % belt.size()
		btn = _potion_button(c, idx)
		if btn != null:
			break
	if btn == null:
		return
	var before := belt.size()
	if not await _click_control(btn, "drink at %d%% HP" % int(
			float(c.get("player_hp")) / mx * 100.0)):
		return
	await _wait(0.4)
	# A targeted potion (3 friendly / 1 enemy in PotionDB) enters the same
	# targeting mode a spell does, and leaves the board captured until answered.
	if int(c.get("_targeting_potion_idx")) >= 0:
		var want := "friendly_creature"
		var tgt := _pick_target(c, want)
		if tgt == null:
			tgt = _pick_target(c, "enemy_creature")
		if tgt != null:
			await _click_at(_centre_of(tgt))
			await _wait(0.4)
		if int(c.get("_targeting_potion_idx")) >= 0:
			await _right_click_at(_canvas() * 0.5)
			await _wait(0.3)
			if int(c.get("_targeting_potion_idx")) >= 0:
				_finding("POTION_TARGET_STUCK",
					"a potion stayed in targeting and right-click did not cancel it",
					{"round": c.get("round_number")})
			return
	if int((rs.get("potions") as Array).size()) < before:
		_potions_drunk += 1
		_jr_write("potion", {
			"round": int(c.get("round_number")),
			"php": int(c.get("player_hp")), "ehp": int(c.get("enemy_hp")),
			"belt": str(belt),
		})
		_log("drink", "bottle at %d/%d HP" % [int(c.get("player_hp")), int(mx)])
	else:
		# The belt took the click and the bottle is still there. That is the dead
		# slot described above, seen from the player's side.
		_finding("POTION_DEAD_SLOT",
			"pressing a filled potion slot consumed nothing and left the belt full",
			{"belt": str(belt), "round": c.get("round_number"),
			 "said": _info_line(c).strip_edges()})


## Board strength, mine minus theirs, in the same ATK+HP unit the damage ledger's
## per-round trace uses — so "behind by six" means the same thing in the potion
## rule and in the POINT OF NO RETURN table.
func _board_gap(c: Node) -> int:
	var gap := 0
	for side in [false, true]:
		for row in [0, 1]:
			for b in c.call("_row_array", side, row):
				if b == null or not is_instance_valid(b):
					continue
				var v: int = int(b.call("effective_atk")) + int(b.get("current_hp"))
				gap += -v if side else v
	return gap


## The belt's own button for slot `idx`. `_rebuild_potion_bar` adds one wrapper
## per slot in belt order, and the wrapper's Button is the click target — the
## handler is an anonymous lambda, so the CHILD ORDER is the only stable identity.
func _potion_button(c: Node, idx: int) -> Control:
	var bar: Variant = c.get("_potion_bar_root")
	if bar == null or not is_instance_valid(bar) \
			or not (bar as Control).is_visible_in_tree():
		return null
	var kids: Array = (bar as Control).get_children()
	if idx < 0 or idx >= kids.size():
		return null
	var found: Array = []
	_walk_buttons(kids[idx], found, 0)
	return null if found.is_empty() else found[0]


func _end_turn(c: Node) -> void:
	for _m in MODAL_ANSWER_TRIES:
		if not await _maybe_answer_modal():
			break
	var btn: Variant = c.get("_end_turn_btn")
	if btn == null or not is_instance_valid(btn) or (btn as BaseButton).disabled:
		# Not an error by itself — the button is disabled while the round resolves.
		await _wait(0.4)
		return
	var round_before := int(c.get("round_number"))
	# DIAGNOSTIC, not a finding: how much Command the pilot is leaving on the
	# table. `acts seen [1]` is the pilot's standing coverage limit and "it plays
	# badly" is not an actionable cause — this says whether the curve-out is
	# actually spending the turn, which is the first thing to check before
	# blaming targeting or placement.
	_mana_left_total += int(c.get("player_mana"))
	_turns_committed += 1
	_jr_write("commit", {
		"round": round_before,
		"unspent": int(c.get("player_mana")),
		"max_command": int(c.get("player_max_mana")),
		"hand_left": (c.get("_hand") as Array).size(),
		"php": int(c.get("player_hp")), "ehp": int(c.get("enemy_hp")),
		"board": _jr_board(c),
	})
	if not await _click_control(btn as Control, "end the turn"):
		return
	# The clash runs. Wait for the round to turn over, the fight to end, or the
	# scene to leave — whichever comes first.
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if _screen() != "Combat" or not is_instance_valid(c):
			return
		if int(c.get("phase")) == 2:
			return
		if int(c.get("round_number")) > round_before:
			return
		if _out_of_budget():
			return
		await _frames(2)
	_finding("ROUND_STALL",
		"round %d never resolved within 90s of END TURN" % round_before,
		{"phase": c.get("phase")})


func _info_line(c: Node) -> String:
	for n in ["_info_label", "_info_line", "_message_label"]:
		var v: Variant = c.get(n)
		if v != null and is_instance_valid(v) and v is Label:
			return (v as Label).text
	return ""


# =========================================================================
#  FINDINGS + REPORT
# =========================================================================

## `--trace` rather than `OS.is_stdout_verbose()`: the engine's own verbose mode
## buries the pilot's decisions under thousands of resource-loader lines, and the
## whole point of a trace is to be able to read what the player-substitute DID.
func _log(kind: String, msg: String) -> void:
	if _trace:
		print("    - %-8s [%s] %s" % [kind, _screen(), msg])


func _finding(kind: String, msg: String, detail: Dictionary) -> void:
	# One entry per (kind, message) — a pilot that loops on a broken screen would
	# otherwise print the same line four hundred times and bury everything else.
	for f in _findings:
		if f["kind"] == kind and f["msg"] == msg:
			f["count"] = int(f["count"]) + 1
			return
	var rec := {
		"kind": kind, "msg": msg, "count": 1, "screen": _screen(),
		"t": "%.1fs" % (Time.get_ticks_msec() / 1000.0 - _t0), "detail": detail,
	}
	_findings.append(rec)
	print("  ⚑ %-14s [%s] %s" % [kind, rec["screen"], msg])
	if _shots:
		_shoot(kind)


func _shoot(tag: String) -> void:
	# Headless never posts a frame, so `frame_post_draw` parks forever and the
	# whole pilot hangs. Windowed only, always.
	if DisplayServer.get_name() == "headless":
		return
	_shot_n += 1
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/_pilot_%02d_%s.png" % [_shot_n, tag.to_lower()])


func _button_dump() -> Array:
	var out: Array = []
	for b in _all_buttons():
		out.append("%s @%s" % [_describe(b), str(b.get_global_rect().position)])
	return out


## The empirical half of card valuation. Prints nothing useful after one run and
## says so: sort is by SAMPLE COUNT, and `n` is on every line, because a card with
## three plays has a win rate that is noise wearing a number.
func _print_card_stats() -> void:
	_save_stats()
	if _card_stats.is_empty():
		return
	var rows: Array = []
	var tot_f := 0
	var tot_w := 0
	for id in _card_stats:
		var r: Dictionary = _card_stats[id]
		var fights := int(r.get("fights", 0))
		if fights <= 0:
			continue
		tot_f += fights
		tot_w += int(r.get("won", 0))
		var sn := int(r.get("swing_n", 0))
		rows.append({
			"name": String(r.get("name", id)),
			"n": fights,
			"played": int(r.get("played", 0)),
			"wr": 100.0 * float(r.get("won", 0)) / float(fights),
			"sw": (float(r.get("swing", 0.0)) / float(sn)) if sn > 0 else 0.0,
			"sn": sn,
		})
	if rows.is_empty():
		return
	# The bar is the bot's OWN win rate. A card at 55% is below par here, not above.
	var base := 100.0 * float(tot_w) / float(maxi(tot_f, 1))

	# EVERY RAW SWING IS NEGATIVE, AND THAT IS NOT A FACT ABOUT ANY CARD.
	# The window runs from "card played" to "round turned over", so it contains
	# the clash AND the enemy's deployment/reinforcement — a large common offset
	# no card is responsible for. Measured at roughly -8 per round: the player's
	# relative board position degrades by that much every round even while playing
	# a card, which is the snowball stated as a number.
	#
	# The offset cancels between cards, so the column is reported RELATIVE to the
	# population mean. Comparing cards is what it is for; comparing one card to
	# zero is not a question this window can answer.
	# WEIGHTED BY PLAYS, NOT BY CARDS (2026-09-19). This averaged each card's own
	# mean, so a card with ONE observation counted as much as one with 57. Measured
	# over a 209-observation ledger: the unweighted figure read -8.39 while the
	# play-weighted one is -7.11, because the 9 cards at n<5 average -9.15 against
	# -7.43 for the 7 at n>=5 — a thin tail inflating the headline by ~18%.
	#
	# The offset's whole job is to be SUBTRACTED from every card's swing below, so
	# it has to be the mean of the same population the swings come from: plays.
	var sw_total := 0.0
	var sw_obs := 0
	for r in rows:
		var sn_i := int(r["sn"])
		if sn_i > 0:
			sw_total += float(r["sw"]) * float(sn_i)
			sw_obs += sn_i
	var mean_sw := sw_total / float(maxi(sw_obs, 1))
	rows.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	print("")
	print("  CARDS IN PRACTICE — %d distinct, ledger at %s" % [
		rows.size(), STATS_PATH])
	print("    baseline: fights containing a tracked card were won %.0f%% of the time" % base)
	print("    the board drifts %+.1f per round against the player REGARDLESS of the" % mean_sw)
	print("    card played — that common offset is the snowball, and it is removed")
	print("    below so the column compares cards to each other.")
	print("    %-24s %4s %5s %8s %8s %7s" % [
		"card", "n", "plays", "win%", "vs base", "swing*"])
	var shown := 0
	for r in rows:
		if shown >= 22:
			break
		shown += 1
		print("    %-24s %4d %5d %7.0f%% %+7.0f%% %+7.1f%s" % [
			String(r["name"]).substr(0, 24), int(r["n"]), int(r["played"]),
			float(r["wr"]), float(r["wr"]) - base, float(r["sw"]) - mean_sw,
			("" if int(r["n"]) >= 10 else "  (thin)")])
	print("    swing* = board change across the round it landed, RELATIVE to the")
	print("    population mean (see above). Positive = better than an average play.")
	print("    Lines marked (thin) have too few samples to mean anything yet —")
	print("    run more seeds; the ledger accumulates.")


func _report() -> void:
	var secs := Time.get_ticks_msec() / 1000.0 - _t0
	print("")
	print("╔══════════════════════════════════════════════════════════════╗")
	print("║  PILOT REPORT                                                 ║")
	print("╚══════════════════════════════════════════════════════════════╝")
	print("  stopped: %s   after %.0fs" % [_stop_reason, secs])
	print("")
	print("  COVERAGE — read this before believing the finding list")
	print("    clicks           %d" % _clicks)
	print("    drags            %d" % _drags)
	print("    cards played     %d" % _cards_played)
	print("    fights entered   %d" % _fights)
	print("    rounds reached   %d (highest in one fight)" % _rounds)
	print("    map stops taken  %d" % _nodes_visited)
	print("    runs ended       %d (reached GameOver)" % _deaths)
	print("    silent refusals  %d" % _silent_refusals)
	print("    overlays opened  %d" % _browsed)
	# THE REWARDS. A pilot that declines everything offered to it plays the whole
	# game on its starting deck and dies in act 1 for reasons that have nothing to
	# do with the game — so these are reported beside the deck size that proves it,
	# not buried in a trace.
	print("    offers taken     %d  (recruits %d / purchases %d)" % [
		_offers_taken, _recruits_taken, _purchases])
	print("    potions drunk    %d" % _potions_drunk)
	# WHY IT STILL DIES IN ACT 1. Deck growth is fixed and `acts seen` is still
	# [1], so the remaining limit is how the pilot PLAYS. This is the cheapest
	# measurement of that: Command left unspent when it commits a turn.
	if _turns_committed > 0:
		print("    command unspent  %.2f per turn over %d commits" % [
			float(_mana_left_total) / float(_turns_committed), _turns_committed])
	if not _deck_sizes.is_empty():
		var lo: int = _deck_sizes[0]
		var hi: int = _deck_sizes[0]
		for d in _deck_sizes:
			lo = mini(lo, d)
			hi = maxi(hi, d)
		print("    deck at death    %s  (min %d / max %d — a hero opens on 10)" % [
			str(_deck_sizes), lo, hi])
	# `deck at death` only prints once a run ENDS, so a soak that stops mid-run
	# said nothing about deck growth at all — which is the one number the reward
	# policy has to move. Read it live as well.
	var rs_now := get_node_or_null("/root/RunState")
	if rs_now != null and bool(rs_now.get("run_active")):
		print("    deck right now   %d cards (a hero opens on 10)" % [
			(rs_now.get("deck") as Array).size()])
	# LORDS PLAYED. Read this before believing anything about balance: for the
	# first 236 runs this was one hero and nothing printed it, so the whole corpus
	# described the Raider while reading like a statement about the game (§20). A
	# single value here is a coverage hole, not a result.
	var lords: Array = _hero_picks.keys()
	lords.sort()
	var lord_bits: Array[String] = []
	for hid in lords:
		lord_bits.append("%s x%d" % [String(hid), int(_hero_picks[hid])])
	var lord_line := ", ".join(lord_bits) if not lord_bits.is_empty() else "NONE PICKED — every run took the roster default, see §20"
	print("    lords played     %s" % lord_line)
	var acts: Array = _acts_seen.keys()
	acts.sort()
	print("    acts seen        %s" % str(acts))
	var seen: Array = _screens_seen.keys()
	seen.sort()
	print("    screens visited  %s" % ", ".join(PackedStringArray(seen)))
	print("")
	_close_fight("report")
	var dmg := _damage_summary()
	if not _fights_log.is_empty():
		var won := 0
		var rounds := 0
		for f in _fights_log:
			if bool(f.get("won", false)):
				won += 1
			rounds += int(f.get("rounds", 0))
		print("")
		print("  WHY IT DIES — %d fights, %d won (%.0f%%), %.1f rounds each" % [
			_fights_log.size(), won,
			100.0 * float(won) / float(maxi(_fights_log.size(), 1)),
			float(rounds) / float(maxi(_fights_log.size(), 1))])
		var t: int = maxi(int(dmg["total"]), 1)
		print("    hero damage taken   %d total" % int(dmg["total"]))
		print("      while RESOLVING   %d (%.0f%%)  — the clash: creatures that got through" % [
			int(dmg["clash"]), 100.0 * float(dmg["clash"]) / float(t)])
		print("      on YOUR turn      %d (%.0f%%)  — passives / draw stings / card costs" % [
			int(dmg["effect"]), 100.0 * float(dmg["effect"]) / float(t)])
		print("      behind a FULL wall %d (%.0f%%) — blocking could not have stopped it" % [
			int(dmg["walled"]), 100.0 * float(dmg["walled"]) / float(t)])
		var rows: Array = []
		for k in (dmg["by_enc"] as Dictionary):
			var v: Dictionary = dmg["by_enc"][k]
			rows.append({"k": k, "dmg": int(v["dmg"]), "n": int(v["n"]),
				"won": int(v["won"]), "rounds": int(v["rounds"])})
		rows.sort_custom(func(a, b): return int(a["dmg"]) > int(b["dmg"]))
		var bl: Array = []
		for k in (dmg["beats"] as Dictionary):
			bl.append("%s=%d" % [k, int((dmg["beats"] as Dictionary)[k])])
		print("    beats seen          %s" % ", ".join(PackedStringArray(bl)))
		# THE NUMBER THAT SEPARATES "hard" FROM "unwinnable": how much of the foe
		# was left standing when the hero fell. A run of losses at 5% remaining is
		# a tuning problem; a run of losses at 60% remaining is a structural one.
		# ("fights won" alone is too coarse — a 5-round rout and a 12-round
		# near-miss both score zero; see reference_probe_readiness_trap.)
		var lost_rows: Array = []
		for f in _fights_log:
			if bool(f.get("won", false)) or not bool(f.get("died", false)):
				continue
			var fin: int = maxi(int(f.get("foe_hp_in", 1)), 1)
			var fout: int = maxi(int(f.get("foe_hp_out", 0)), 0)
			lost_rows.append({
				"k": String(f.get("name", "?")),
				"pct": 100.0 * float(fin - fout) / float(fin),
				"left": fout, "of": fin, "rounds": int(f.get("rounds", 0)),
				"act": int(f.get("act", 0))})
		if not lost_rows.is_empty():
			var sum_pct := 0.0
			for r in lost_rows:
				sum_pct += float(r["pct"])
			print("    THE FIGHTS IT LOST — %.0f%% of the foe removed on average:" % [
				sum_pct / float(lost_rows.size())])
			for r in lost_rows:
				print("      act %d  %-26s %3.0f%% removed (%d/%d HP left), %d rounds" % [
					int(r["act"]), String(r["k"]).substr(0, 26), float(r["pct"]),
					int(r["left"]), int(r["of"]), int(r["rounds"])])
		# THE POINT OF NO RETURN: the last round at which the pilot still held a
		# board advantage. If that number is small and the fight ran long, the
		# remaining rounds were not a contest — they were a formality, which is
		# the specific complaint this whole exercise started from.
		var pnr: Array = []
		for f in _fights_log:
			if not bool(f.get("died", false)) or bool(f.get("won", false)):
				continue
			var lg: Array = f.get("log", [])
			if lg.is_empty():
				continue
			var last_ahead := 0
			for e in lg:
				if int(e["mine"]) >= int(e["theirs"]):
					last_ahead = int(e["r"])
			pnr.append({"k": String(f.get("name", "?")), "last": last_ahead,
				"of": int(f.get("rounds", 0)),
				"peak": int((lg[lg.size() - 1] as Dictionary)["theirs"])})
		if not pnr.is_empty():
			var sl := 0.0
			var so := 0.0
			for r in pnr:
				sl += float(r["last"])
				so += float(r["of"])
			print("    POINT OF NO RETURN — last round the pilot was ahead on board:")
			print("      mean: ahead until round %.1f, fight ran %.1f rounds  (%.0f%% of the fight already lost)" % [
				sl / float(pnr.size()), so / float(pnr.size()),
				100.0 * (1.0 - (sl / maxf(so, 1.0)))])
			for r in pnr:
				print("        %-26s ahead to r%d of %d" % [
					String(r["k"]).substr(0, 26), int(r["last"]), int(r["of"])])
		print("    worst encounters (by hero HP taken):")
		for i in mini(6, rows.size()):
			var r: Dictionary = rows[i]
			print("      %-28s %2d HP over %d fight(s), won %d, %.1f rounds" % [
				String(r["k"]).substr(0, 28), int(r["dmg"]), int(r["n"]),
				int(r["won"]), float(r["rounds"]) / float(maxi(int(r["n"]), 1))])
		print("")
	if not _recruit_why.is_empty():
		var rl: Array = []
		for k in _recruit_why:
			rl.append("%s=%d" % [k, int(_recruit_why[k])])
		rl.sort()
		print("    muster outcomes  %s" % ", ".join(PackedStringArray(rl)))
	_print_card_stats()
	if _findings.is_empty():
		print("  FINDINGS: none. NOTE: this is only a claim about what the")
		print("  coverage above actually touched.")
	else:
		print("  FINDINGS: %d distinct" % _findings.size())
		for f in _findings:
			print("")
			print("   [%s] %s" % [f["kind"], f["msg"]])
			print("     screen=%s  at=%s  seen %dx" % [f["screen"], f["t"], f["count"]])
			if not (f["detail"] as Dictionary).is_empty():
				print("     %s" % str(f["detail"]))
	print("")
	if _jr != null:
		print("  DECISION JOURNAL: %d records -> %s" % [_jr_seq, _jr_path])
	_journal_close(_stop_reason)
	print("")
	# The runner greps this line; the exit code alone is not trustworthy, because
	# Godot returns 0 through plenty of in-game script errors.
	if _findings.is_empty():
		print("PILOT: NO FINDINGS (clicks=%d drags=%d fights=%d)" % [
			_clicks, _drags, _fights])
	else:
		print("PILOT: %d FINDINGS (clicks=%d drags=%d fights=%d)" % [
			_findings.size(), _clicks, _drags, _fights])
	get_tree().quit(0)
