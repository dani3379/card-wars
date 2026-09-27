extends Node
## Windowed regression: CoachPanel never exposes a provisional rect and only
## accepts input after its settled reveal completes.

var _failures := 0
var _original_reduce_motion := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_original_reduce_motion = UserSettings.reduce_motion
	await _run_case(false)
	await _run_case(true)
	UserSettings.reduce_motion = _original_reduce_motion
	print("[coach-atomic] DONE failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _run_case(reduced: bool) -> void:
	UserSettings.reduce_motion = reduced
	var stage := Control.new()
	stage.size = get_viewport().get_visible_rect().size
	add_child(stage)
	var target := ColorRect.new()
	target.position = Vector2(stage.size.x * 0.38, stage.size.y * 0.38)
	target.size = Vector2(300, 180)
	target.color = Color(0.3, 0.2, 0.15, 1.0)
	stage.add_child(target)
	var coach := TutorialCoach.new()
	stage.add_child(coach)
	coach.focus([target], 0.58)
	coach.show_panel("READ THE ROAD",
		"Choose a road, inspect what waits there, then commit only when the route is clear.",
		"GOT IT", 1, 3)
	var panel: PanelContainer = coach._panel
	var label := "Reduce Motion" if reduced else "animated"
	_check(panel != null, "%s creates a coach panel" % label)
	_check(panel.modulate.a == 0.0,
		"%s withholds the provisional panel in the show call" % label)
	_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"%s provisional panel cannot block the board" % label)
	_check(coach._action.disabled and coach._skip.disabled,
		"%s provisional panel cannot accept button input" % label)

	var saw_visible := false
	var first_visible_rect := Rect2()
	var first_visible_center := Vector2.ZERO
	var max_layout_shift := 0.0
	var max_center_shift := 0.0
	var input_leaked := false
	var alpha_progress: Array[int] = [0]
	for _i in 150:
		await get_tree().process_frame
		if not is_instance_valid(panel):
			break
		var bucket := 0 if panel.modulate.a <= 0.01 else (2 if panel.modulate.a >= 0.99 else 1)
		if alpha_progress[-1] != bucket:
			alpha_progress.append(bucket)
		if panel.modulate.a > 0.01:
			var rect := Rect2(panel.position, panel.size)
			var center := TutorialCoach.visual_rect(panel).get_center()
			if not saw_visible:
				saw_visible = true
				first_visible_rect = rect
				first_visible_center = center
			else:
				max_layout_shift = maxf(max_layout_shift,
					rect.position.distance_to(first_visible_rect.position))
				max_layout_shift = maxf(max_layout_shift,
					rect.size.distance_to(first_visible_rect.size))
				max_center_shift = maxf(max_center_shift,
					center.distance_to(first_visible_center))
		if not coach._panel_ready and (panel.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				or not coach._action.disabled or not coach._skip.disabled):
			input_leaked = true
		if coach._panel_ready:
			break

	print("[coach-atomic] %s alpha=%s rect_shift=%.3f center_shift=%.3f rect=%s" % [
		label, str(alpha_progress), max_layout_shift, max_center_shift,
		str(first_visible_rect)])
	_check(saw_visible and coach._panel_ready,
		"%s reaches one settled reveal gate" % label)
	_check(first_visible_rect.position.distance_to(Vector2.ZERO) > 8.0,
		"%s first visible frame is not the origin" % label)
	_check(max_layout_shift <= 0.01,
		"%s layout rect never teleports after becoming visible" % label)
	_check(max_center_shift <= 0.05,
		"%s centered pulse does not displace the panel" % label)
	_check(not input_leaked,
		"%s keeps input locked for the entire placement/reveal" % label)
	_check(panel.mouse_filter == Control.MOUSE_FILTER_STOP \
			and not coach._action.disabled and not coach._skip.disabled,
		"%s unlocks panel input only at the final rect" % label)
	if reduced:
		_check(alpha_progress == [0, 2],
			"Reduce Motion snaps directly from hidden to complete")

	stage.queue_free()
	for _i in 4:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[coach-atomic] PASS ", message)
	else:
		_failures += 1
		push_error("[coach-atomic] FAIL " + message)
