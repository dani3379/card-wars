extends SceneTree
## Regression for Event choices: wrapped ladders settle while hidden and then
## publish without moving container-owned geometry.

const TIMEOUT_FRAMES := 90

var _started := false
var _failures := 0
var _settings: Node
var _run_state: Node


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	_settings = root.get_node("UserSettings")
	_run_state = root.get_node("RunState")
	_settings.set("particles", false)
	_run_state.active_slot = -1
	_run_state.start_new_run("raider", 0, 20260927)
	_run_state.active_slot = -1
	_run_state.current_node_type = "event"
	_run_state.current_bridge = true
	_run_state.events_seen.erase("the_crossing")
	var scene: Control = load("res://scenes/event.tscn").instantiate()
	root.add_child(scene)
	for _i in 6:
		await process_frame
	await _run_case(scene, false)
	await _run_case(scene, true)
	print("[event-choice-ladder] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _run_case(scene: Control, reduced: bool) -> void:
	_settings.set("reduce_motion", reduced)
	var ladder := VBoxContainer.new()
	ladder.name = "QAChoiceLadderReduced" if reduced else "QAChoiceLadderAnimated"
	ladder.position = Vector2(60, 50)
	ladder.size = Vector2(620, 600)
	ladder.custom_minimum_size.x = 620
	ladder.add_theme_constant_override("separation", 7)
	scene.add_child(ladder)

	var buttons: Array[Button] = []
	var long_outcome := "Gain a chosen uncommon soldier, teach it Armored, then " \
		+ "place a copy on the next battlefield with its printed attack and health fully restored."
	for i in 3:
		var button := scene.call("_make_frameless_choice",
			"Long choice %d" % (i + 1), long_outcome,
			"The quartermaster waits beside the road.", 52, Callable(), false,
			i + 1) as Button
		ladder.add_child(button)
		buttons.append(button)

	var label := "Reduce Motion" if reduced else "animated"
	_check(_visible_count(buttons) == 0,
		"%s ladder is withheld in its build call" % label)
	_check(_all_mouse_filter(buttons, Control.MOUSE_FILTER_IGNORE),
		"%s ladder ignores input while measuring" % label)

	var hidden_until_ready := true
	var frames := 0
	while not bool(ladder.get_meta("_event_choice_ready", false)) \
			and frames < TIMEOUT_FRAMES:
		if _visible_count(buttons) > 0:
			hidden_until_ready = false
		await process_frame
		frames += 1
	_check(bool(ladder.get_meta("_event_choice_ready", false)),
		"%s ladder reaches one shared ready gate" % label)
	_check(hidden_until_ready,
		"%s ladder stays invisible through every sizing frame" % label)
	_check(_all_mouse_filter(buttons, Control.MOUSE_FILTER_STOP),
		"%s ladder unlocks input as one group" % label)
	_check(_max_height(buttons) > 52.5,
		"%s case exercises wrapped-content growth" % label)

	var baseline := _rects(buttons)
	var visible_progress: Array[int] = [_visible_count(buttons)]
	var max_shift := 0.0
	for _i in 36:
		await process_frame
		_append_change(visible_progress, _visible_count(buttons))
		max_shift = maxf(max_shift, _max_rect_delta(baseline, _rects(buttons)))
	print("[event-choice-ladder] %s visible=%s shift=%.3f heights=%s" % [
		label, str(visible_progress), max_shift, str(_heights(buttons))])
	_check(_visible_count(buttons) == 3,
		"%s ladder publishes every choice" % label)
	_check(max_shift <= 0.01,
		"%s ladder geometry stays fixed after publication" % label)
	if reduced:
		_check(visible_progress == [3],
			"Reduce Motion publishes the complete ladder in one step")

	ladder.queue_free()
	for _i in 4:
		await process_frame


func _visible_count(buttons: Array[Button]) -> int:
	var count := 0
	for button in buttons:
		if is_instance_valid(button) and button.modulate.a > 0.01:
			count += 1
	return count


func _all_mouse_filter(buttons: Array[Button], value: int) -> bool:
	for button in buttons:
		if not is_instance_valid(button) or button.mouse_filter != value:
			return false
	return true


func _heights(buttons: Array[Button]) -> Array[float]:
	var out: Array[float] = []
	for button in buttons:
		out.append(button.size.y)
	return out


func _max_height(buttons: Array[Button]) -> float:
	var value := 0.0
	for button in buttons:
		value = maxf(value, button.size.y)
	return value


func _rects(buttons: Array[Button]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for button in buttons:
		out.append(Rect2(button.global_position, button.size))
	return out


func _max_rect_delta(a: Array[Rect2], b: Array[Rect2]) -> float:
	if a.size() != b.size():
		return INF
	var value := 0.0
	for i in a.size():
		value = maxf(value, a[i].position.distance_to(b[i].position))
		value = maxf(value, a[i].size.distance_to(b[i].size))
	return value


func _append_change(values: Array[int], value: int) -> void:
	if values.is_empty() or values[-1] != value:
		values.append(value)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[event-choice-ladder] PASS ", message)
	else:
		_failures += 1
		push_error("[event-choice-ladder] FAIL " + message)
