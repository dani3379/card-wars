extends SceneTree
## Regression for Event result cards: fixed backs, atomic faces, one timeline.

const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const TIMEOUT_MS := 18000

var _started := false
var _failures := 0
var _run_state: Node
var _cache: Node
var _settings: Node
var _card_db: Node


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	_run_state = root.get_node("RunState")
	_cache = root.get_node("CardTextureCache")
	_settings = root.get_node("UserSettings")
	_card_db = root.get_node("CardDB")
	_settings.set("particles", false)
	_settings.set("anim_speed", 1.0)
	await _run_case(false, false)
	await _run_case(false, true)
	await _run_case(true, false)
	print("[event-result-atomic] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _run_case(reduced: bool, pair: bool) -> void:
	await _wait_for_idle()
	_cache.clear()
	_settings.set("reduce_motion", reduced)
	_run_state.active_slot = -1
	_run_state.start_new_run("raider", 0, 20260927)
	_run_state.active_slot = -1
	_run_state.current_node_type = "event"
	_run_state.current_bridge = true
	_run_state.events_seen.erase("the_crossing")
	var scene: Node = load("res://scenes/event.tscn").instantiate()
	root.add_child(scene)
	for _i in 8:
		await RenderingServer.frame_post_draw
	await _wait_for_idle()
	_cache.clear()

	var expected := 2 if pair else 3
	if pair:
		var before: Dictionary = _card_db.get_card_data("levy_rider")
		var after: Dictionary = _run_state.preview_plus_upgrade(before)
		scene.set("_result_pairs", [{"before": before, "after": after}])
		scene.call("_show_result", "The card was forged.")
	else:
		scene.set("_result_cards", [
			_card_db.get_card_data("rat_piper"),
			_card_db.get_card_data("petard"),
			_card_db.get_card_data("trebuchet"),
		])
		scene.call("_show_result", "Three cards join your deck.")

	var timeline := scene.get_node_or_null("ResultCardTimeline") as Control
	var label := ("Reduce Motion " if reduced else "animated ") \
		+ ("pair" if pair else "result")
	_check(timeline != null, "%s owns one result timeline" % label)
	if timeline == null:
		await _close_scene(scene)
		return
	_check(_back_nodes(timeline).size() == expected,
		"%s seats every card back in the build call" % label)
	_check(_card_nodes(timeline).is_empty(),
		"%s exposes no rich face before the loader yields" % label)
	var aux: Array = timeline.get_meta("_event_result_aux", [])
	if pair:
		_check(not aux.is_empty() and _visible_aux_count(aux, timeline) == 0,
			"%s withholds arrow and caption until the pair is ready" % label)

	for _i in 2:
		await process_frame
	var wrappers := _back_slots(timeline)
	var baseline := _centres(wrappers)
	var node_progress: Array[int] = [_card_nodes(timeline).size()]
	var visible_progress: Array[int] = [_visible_card_count(timeline)]
	var back_progress: Array[int] = [_visible_back_count(timeline)]
	var max_shift := 0.0
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		_append_change(node_progress, _card_nodes(timeline).size())
		_append_change(visible_progress, _visible_card_count(timeline))
		_append_change(back_progress, _visible_back_count(timeline))
		max_shift = maxf(max_shift, _max_delta(baseline, _centres(wrappers)))
		if bool(timeline.get_meta("_event_result_ready", false)):
			break
	print("[event-result-atomic] %s nodes=%s visible=%s backs=%s shift=%.3f" % [
		label, str(node_progress), str(visible_progress), str(back_progress), max_shift])
	_check(bool(timeline.get_meta("_event_result_hydrated", false)),
		"%s hydrates the complete group" % label)
	_check(bool(timeline.get_meta("_event_result_ready", false)),
		"%s completes its authored timeline" % label)
	_check(node_progress == [0, expected],
		"%s constructs faces atomically 0 -> N" % label)
	_check(visible_progress == [0, expected],
		"%s publishes faces atomically 0 -> N" % label)
	_check(back_progress == [expected, 0],
		"%s retires the complete back set together" % label)
	_check(max_shift <= 0.01,
		"%s keeps every result socket fixed" % label)
	if pair:
		_check(_visible_aux_count(aux, timeline) == aux.size(),
			"%s reveals dependent arrow/caption only from the shared timeline" % label)
	await _close_scene(scene)


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node in _walk(host):
		var script := node.get_script() as Script
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
	return out


func _back_nodes(host: Node) -> Array[TextureRect]:
	var out: Array[TextureRect] = []
	for node in _walk(host):
		if node is TextureRect and node.texture == CARD_BACK_TEXTURE:
			out.append(node)
	return out


func _back_slots(host: Node) -> Array[Control]:
	var out: Array[Control] = []
	for back in _back_nodes(host):
		var slot := back.get_parent() as Control
		if slot != null:
			out.append(slot)
	return out


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _effective_alpha(node: Node, boundary: Node) -> float:
	var alpha := 1.0
	var cursor := node
	while cursor != null:
		if cursor is CanvasItem:
			if not cursor.visible:
				return 0.0
			alpha *= cursor.modulate.a
		if cursor == boundary:
			break
		cursor = cursor.get_parent()
	return alpha


func _visible_card_count(host: Node) -> int:
	var count := 0
	for card in _card_nodes(host):
		if _effective_alpha(card, host) > 0.99:
			count += 1
	return count


func _visible_back_count(host: Node) -> int:
	var count := 0
	for back in _back_nodes(host):
		if _effective_alpha(back, host) > 0.01:
			count += 1
	return count


func _visible_aux_count(aux: Array, boundary: Node) -> int:
	var count := 0
	for item in aux:
		var ctrl := (item as Dictionary).get("control") as Control
		if ctrl != null and is_instance_valid(ctrl) \
				and _effective_alpha(ctrl, boundary) > 0.99:
			count += 1
	return count


func _centres(nodes: Array[Control]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for node in nodes:
		if node == null or not is_instance_valid(node):
			return []
		out.append(node.global_position + node.size * node.scale * 0.5)
	return out


func _max_delta(a: Array[Vector2], b: Array[Vector2]) -> float:
	if a.size() != b.size():
		return INF
	var value := 0.0
	for i in a.size():
		value = maxf(value, a[i].distance_to(b[i]))
	return value


func _append_change(values: Array[int], value: int) -> void:
	if values.is_empty() or values[-1] != value:
		values.append(value)


func _wait_for_idle() -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while bool(_cache.get("_bake_busy")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(_cache.get("_bake_busy")), "card baker becomes idle")


func _close_scene(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	for _i in 6:
		await process_frame
	await _wait_for_idle()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[event-result-atomic] PASS ", message)
	else:
		_failures += 1
		push_error("[event-result-atomic] FAIL " + message)
