extends Node
## _probe_press_feedback.gd — every button answers the instant it is pushed.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_press_feedback.tscn
##
## WHY THIS FILE EXISTS. Measured on 2026-09-17, before the press pass: 214
## `pressed.connect` sites, TWO `button_down` connections in the whole repo, 24
## buttons with a press cue, and `Motion.press` called once — on a HUD
## instrument, not a button. Pressing almost anything changed a StyleBox and
## nothing else. The fix is a tree-wide funnel (`GameTheme._install_press_feedback`),
## and a funnel is exactly the kind of thing that rots silently: it is one
## `node_added` connection, and if it stops firing every button in the game goes
## quiet at once with no error anywhere and no visual that looks like a bug — a
## button that does not react looks like a button.
##
## THE FLAG IS NOT THE ORACLE, and that is the design of this file. Checking
## `_motion_press_armed` only proves `arm_press` was CALLED; it says nothing
## about whether a press moves a pixel, which is the entire claim. Every
## behavioural case below drives the real signals and then MEASURES `scale` on
## the node that was supposed to move. (Same lesson as `lesson_seen` in
## `_probe_tutorial_live`: a function that stamps a flag on entry cannot be
## asked whether it worked.)
##
## Phase A  the verb, on a button this probe owns
## Phase B  the audio dedupe — one press is one sound
## Phase C  the funnel, over six real screens
## Phase D  vacuity: the checks above must be able to FAIL

const DIP_SETTLE := 0.14   # > Motion.PRESS_DIP, so the dip has landed
const RISE_SETTLE := 0.26  # > Motion.PRESS_RISE, so the spring has landed

var _fails := 0
var _armed_total := 0


func _ready() -> void:
	await get_tree().process_frame
	await _phase_a_verb()
	await _phase_b_audio()
	await _phase_c_screens()
	await _phase_d_vacuity()
	_finish()


# ── Phase A — the verb ─────────────────────────────────────────────────────
func _phase_a_verb() -> void:
	print("── A. the press verb ──")
	var host := Control.new()
	host.size = Vector2(400, 200)
	get_tree().root.add_child(host)
	var btn := Button.new()
	btn.text = "PRESS ME"
	btn.size = Vector2(160, 44)
	host.add_child(btn)
	await get_tree().process_frame

	_check(btn.has_meta("_motion_press_armed"),
		"a plain Button.new() added to the tree is armed by the funnel")

	# THE DIP. Drive the real signal and measure the node.
	var rest: Vector2 = btn.scale
	btn.button_down.emit()
	await get_tree().create_timer(DIP_SETTLE).timeout
	var dipped: Vector2 = btn.scale
	_check(dipped != rest, "button_down MOVES the control (%s -> %s)"
		% [str(rest), str(dipped)])
	_check(dipped.y < dipped.x,
		"it SQUASHES rather than shrinks — y dips harder than x (%.3f vs %.3f)"
			% [dipped.y, dipped.x])
	_check(dipped.x < rest.x and dipped.y < rest.y,
		"both axes go in, so it reads as pushed in rather than stretched")

	# THE HOLD. Nothing schedules the return; it waits on the finger.
	await get_tree().create_timer(0.25).timeout
	_check(btn.scale.is_equal_approx(dipped),
		"it HOLDS while held — no timer springs it back on its own (%s)"
			% str(btn.scale))

	# THE RELEASE.
	btn.button_up.emit()
	await get_tree().create_timer(RISE_SETTLE).timeout
	_check(btn.scale.is_equal_approx(rest),
		"button_up returns it exactly to rest (%s)" % str(btn.scale))

	# THE CANCEL — held, dragged off. `button_up` arrives over another control,
	# so without the mouse_exited arm the dent outlives the gesture.
	btn.button_down.emit()
	await get_tree().create_timer(DIP_SETTLE).timeout
	_check(not btn.scale.is_equal_approx(rest), "fixture: dented before cancel")
	btn.mouse_exited.emit()
	await get_tree().create_timer(RISE_SETTLE).timeout
	_check(btn.scale.is_equal_approx(rest),
		"dragged off while held springs back (%s)" % str(btn.scale))

	# IDEMPOTENCE — an un-hover on a control that is NOT dented must not put a
	# second tween on `scale`, or it fights hover_lift's own exit tween.
	var before: Vector2 = btn.scale
	btn.mouse_exited.emit()
	btn.mouse_exited.emit()
	await get_tree().process_frame
	_check(btn.scale.is_equal_approx(before),
		"mouse_exited on an undented control is inert (no tween war with hover)")

	# A DISABLED CONTROL DOES NOT ANSWER. It refuses the click; answering the
	# press would promise something it will not do.
	btn.disabled = true
	btn.button_down.emit()
	await get_tree().create_timer(DIP_SETTLE).timeout
	_check(btn.scale.is_equal_approx(rest), "a disabled button does not dip")
	btn.disabled = false
	btn.button_up.emit()
	await get_tree().create_timer(RISE_SETTLE).timeout

	# REDUCE MOTION declines — and is read at PRESS time, because the setting is
	# live and a player can turn it on with the screen already built.
	var was_rm: bool = UserSettings.reduce_motion
	UserSettings.reduce_motion = true
	btn.button_down.emit()
	await get_tree().create_timer(DIP_SETTLE).timeout
	_check(btn.scale.is_equal_approx(rest),
		"Reduce Motion declines the dip, decided at press time (%s)"
			% str(btn.scale))
	UserSettings.reduce_motion = was_rm
	btn.button_up.emit()
	await get_tree().create_timer(RISE_SETTLE).timeout

	# ARMING IS ONCE. The funnel runs on node_added; re-parenting a button fires
	# it again, and a twice-armed control dips twice as far.
	var conns: int = btn.button_down.get_connections().size()
	Motion.arm_press(btn)
	GameTheme._arm_press_default(btn)
	host.remove_child(btn)
	host.add_child(btn)
	await get_tree().process_frame
	_check(btn.button_down.get_connections().size() == conns,
		"re-arming and re-parenting add no second connection (%d)"
			% btn.button_down.get_connections().size())

	# THE MARK'S POINT. `get_local_mouse_position()` is right only when a cursor
	# is actually on the control — a keyboard press (Enter on the focused button,
	# which this game's focus mirroring makes a first-class path) reports
	# wherever the pointer is parked. The first shot caught the bloom 500px off
	# the button in open space, which no state assertion would ever have seen.
	var far := Button.new()
	far.position = Vector2(600, 400)
	far.size = Vector2(160, 44)
	host.add_child(far)
	await get_tree().process_frame
	var pt: Vector2 = Motion.press_point_on(far)
	_check(pt.is_equal_approx(far.size * 0.5),
		"a press with the cursor off the control marks its CENTRE (%s)" % str(pt))
	_check(Rect2(Vector2.ZERO, far.size).has_point(pt),
		"and the point is always inside the control's own rect")

	# THE DIP IS THE SAME PHYSICAL EVENT AT EVERY SIZE. A proportional squash
	# gave the 44px close button 0.40px of travel while the 220px plate got
	# 1.98px — below threshold on one, and "the big button was pressed harder"
	# on the other. Pure, so it is asserted directly rather than by pressing.
	var wide := Motion.press_squash_for(Vector2(220, 52))
	var small := Motion.press_squash_for(Vector2(44, 44))
	var wide_y: float = 52.0 * (1.0 - wide.y) * 0.5
	var small_y: float = 44.0 * (1.0 - small.y) * 0.5
	_check(absf(wide_y - small_y) < 0.05,
		"a 220x52 plate and a 44x44 chip travel the same distance (%.2f vs %.2f px)"
			% [wide_y, small_y])
	_check(wide_y >= 2.0,
		"and that distance is actually visible (%.2f px per edge)" % wide_y)
	# Vertical compression is the 2D shorthand for depth, so it must stay the
	# dominant axis even where fixed travel would invert it — a tall narrow rail
	# would otherwise be nipped at the waist rather than pushed in.
	for s in [Vector2(220, 52), Vector2(44, 44), Vector2(40, 200), Vector2(300, 18)]:
		var q := Motion.press_squash_for(s)
		if q.y > q.x:
			_check(false, "%s squashes sideways harder than down (%s)"
				% [str(s), str(q)])
			break
	_check(Motion.press_squash_for(Vector2(40, 200)).y
			<= Motion.press_squash_for(Vector2(40, 200)).x,
		"y stays the dominant squash axis at every aspect ratio")

	# THE TARGET FOLLOWS THE HOVER. An offer tile is a painted wrapper under an
	# invisible catcher; the press must land on the wrapper, and it must work
	# when hover_lift is wired AFTER the funnel already armed the button.
	var wrapper := Control.new()
	wrapper.size = Vector2(200, 260)
	host.add_child(wrapper)
	var catcher := Button.new()
	catcher.flat = true
	catcher.size = wrapper.size
	wrapper.add_child(catcher)
	await get_tree().process_frame  # funnel arms the catcher here, target unknown
	Motion.hover_lift(catcher, 1.04, wrapper)
	catcher.button_down.emit()
	await get_tree().create_timer(DIP_SETTLE).timeout
	_check(not wrapper.scale.is_equal_approx(Vector2.ONE),
		"the WRAPPER dips, not the invisible catcher (%s)" % str(wrapper.scale))
	_check(catcher.scale.is_equal_approx(Vector2.ONE),
		"and the catcher itself is left alone")
	catcher.button_up.emit()

	host.queue_free()
	await get_tree().process_frame


# ── Phase B — one press is one sound ───────────────────────────────────────
func _phase_b_audio() -> void:
	print("── B. one press is one sound ──")
	# The funnel gives every button a default cue while ~24 already declare
	# their own, so the pair has to collapse. Asserted on the dedupe's own state
	# rather than by listening: the probe is headless and there is no bus to
	# read, but the frame stamp IS the decision and it is exact.
	AudioBank._ui_cue_frame = -1
	AudioBank.play_ui("commit")
	var claimed: int = AudioBank._ui_cue_frame
	_check(claimed == Engine.get_process_frames(),
		"the first cue of a frame claims it")
	AudioBank.play_ui("select")
	_check(AudioBank._ui_cue_frame == claimed,
		"a second cue in the SAME frame is dropped, not layered")

	await get_tree().process_frame
	AudioBank.play_ui("select")
	_check(AudioBank._ui_cue_frame != claimed,
		"the next frame is a new press and sounds again")

	# WHICH cue survives, driven rather than read out of the source. The funnel's
	# default is connected DEFERRED precisely so a screen's explicit cue — wired
	# later, and therefore second in the connection list — still runs first and
	# claims the frame. If that ordering ever inverts, every "commit" in the game
	# quietly becomes a "select": one sound either way, the wrong one, and
	# nothing else in the harness would notice.
	var host := Control.new()
	get_tree().root.add_child(host)
	var weighty := Button.new()
	host.add_child(weighty)
	await get_tree().process_frame          # the funnel arms its default here
	GameTheme.arm_ui_press(weighty, "commit")  # the screen declares its own after
	AudioBank._ui_cue_frame = -1
	AudioBank._ui_cue_kind = ""
	weighty.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(AudioBank._ui_cue_kind == "commit",
		"an explicit cue outranks the funnel's default (heard %s)"
			% AudioBank._ui_cue_kind)

	# And a button that declares nothing still has a voice — the whole point.
	var plain := Button.new()
	host.add_child(plain)
	await get_tree().process_frame
	AudioBank._ui_cue_frame = -1
	AudioBank._ui_cue_kind = ""
	plain.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(AudioBank._ui_cue_kind == "select",
		"a button that declares nothing still sounds (heard '%s')"
			% AudioBank._ui_cue_kind)

	# ADVANCE AND RETREAT MUST STAY DISTINGUISHABLE WITH THE SCREEN UNREAD, which
	# is the entire reason `ui_back` is pitched down. A default cue on every
	# button is exactly how that distinction gets erased by accident: the 32
	# `make_back_button` sites that never called `arm_ui_press` would all have
	# started saying "select".
	_check(GameTheme.press_cue_for(GameTheme.make_back_button("LEAVE")) == "back",
		"a back button retreats in the retreat's voice")
	_check(GameTheme.press_cue_for(
			GameTheme.make_back_button("PICK", Vector2(140, 42), 16, GameTheme.GILT))
			== "select",
		"...but the same helper used as a light confirm does not")
	_check(GameTheme.press_cue_for(GameTheme.make_close_button()) == "back",
		"closing a modal is a retreat too")
	_check(GameTheme.make_primary_button("ON").has_meta("press_weight"),
		"THE WAY ON carries the weight that earns the at-cursor mark")
	_check(not GameTheme.make_back_button("LEAVE").has_meta("press_weight"),
		"and an ordinary retreat does not")
	host.queue_free()
	await get_tree().process_frame


# ── Phase C — the funnel, over real screens ────────────────────────────────
func _phase_c_screens() -> void:
	print("── C. real screens ──")
	var RS = get_node_or_null("/root/RunState")
	if RS != null:
		RS.start_new_run("raider", 0, 4317)
	await _screen("main menu", "res://scenes/main_menu.tscn")
	await _screen("map", "res://scenes/map.tscn")
	await _screen("shop", "res://scenes/shop.tscn")
	await _screen("reward", "res://scenes/reward.tscn")
	await _screen("wayside", "res://scenes/wayside.tscn")
	await _screen("game over", "res://scenes/game_over.tscn")
	# A floor, so a funnel that silently stops firing cannot pass by finding
	# nothing to check — the failure mode this gate exists for produces an empty
	# sweep, not a failing one. Six screens held 69 buttons when this was
	# written (the chart alone is 40 of them).
	_check(_armed_total >= 50,
		"the sweep actually saw a button population (%d armed)" % _armed_total)


func _screen(label: String, path: String) -> void:
	var packed = load(path)
	if packed == null:
		_check(false, "%s: scene loads" % label)
		return
	var scene = packed.instantiate()
	get_tree().root.add_child(scene)
	# SETTLE UNTIL THE COUNT HOLDS, never a fixed frame budget. Half these
	# screens build behind an `await` — MapView's `_build_node_buttons` runs
	# after `await build_map()`, Reward deals its cards one `_present_frame` at a
	# time — so a probe that counts after N frames measures the build mid-flight
	# and reports a screen with no buttons on it as fully armed. That is not
	# hypothetical: at 18 frames this read "map: all 0 buttons armed" and passed.
	# Polled on REAL TIME with a floor, not on process frames. Two traps, both
	# paid for here: headless runs the main loop as fast as it can, so 220
	# process frames can be a fraction of a second while these screens await
	# `create_timer` beats that are measured in seconds; and a bare
	# stability test settles instantly on a screen that has not started building
	# yet, because "0, 0, 0" is perfectly stable — that read FEWER buttons than
	# the fixed budget it replaced, which is the tell.
	var stable := 0
	var last := -1
	var polls := 0
	while polls < 170 and (stable < 8 or polls < 24):
		await get_tree().create_timer(0.05).timeout
		polls += 1
		var now: int = scene.find_children("*", "BaseButton", true, false).size()
		stable = stable + 1 if now == last else 0
		last = now
	var bare: Array[String] = []
	var seen := 0
	for n in scene.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b == null or b.has_meta("no_press_feel"):
			continue
		seen += 1
		if not b.has_meta("_motion_press_armed"):
			bare.append(b.name if b.text == "" else b.text)
	_armed_total += seen - bare.size()
	_check(bare.is_empty(), "%s: all %d buttons armed%s"
		% [label, seen, "" if bare.is_empty() else
			" — BARE: " + ", ".join(bare.slice(0, 6))])
	scene.queue_free()
	await get_tree().process_frame


# ── Phase D — the checks must be able to fail ──────────────────────────────
func _phase_d_vacuity() -> void:
	print("── D. vacuity ──")
	# Phase C passes trivially if `_motion_press_armed` were set on everything
	# unconditionally, so prove the predicate discriminates: a control the
	# funnel is TOLD to skip must come back unarmed.
	var host := Control.new()
	get_tree().root.add_child(host)
	var opted := Button.new()
	opted.set_meta("no_press_feel", true)
	host.add_child(opted)
	await get_tree().process_frame
	_check(not opted.has_meta("_motion_press_armed"),
		"no_press_feel opts a control out — the arming check can say NO")

	# And that the measurement in phase A is reading a real moving value, not a
	# constant: an unarmed control must NOT move when driven the same way.
	var rest: Vector2 = opted.scale
	opted.button_down.emit()
	await get_tree().create_timer(DIP_SETTLE).timeout
	_check(opted.scale.is_equal_approx(rest),
		"an unarmed control does not move when driven — the dip check is real")
	host.queue_free()
	await get_tree().process_frame


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _finish() -> void:
	if _fails == 0:
		print("PROBE PASS: press_feedback")
	else:
		print("PROBE FAIL: press_feedback (%d failures)" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
