extends SceneTree
## Focused regression for Main Menu's full starting-deck inspector.
## The live grid must be complete before its first await, rich faces may hydrate
## over several frames only while hidden, and the reveal must be one N-card beat.

const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const TIMEOUT_MS := 15000

var _started := false
var _failures := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 240
	var settings: Node = root.get_node("UserSettings")
	var cache: Node = root.get_node("CardTextureCache")
	var preload_service: Node = root.get_node("ScenePreload")
	settings.set("reduce_motion", false)
	settings.set("particles", false)
	if preload_service.has_method("cancel_deck_warm"):
		preload_service.cancel_deck_warm()
	await _wait_for_idle(cache)
	cache.clear()

	var scene: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(scene)
	for _i in 4:
		await process_frame
	scene.set("_selected_hero", "raider")
	var opener: Array = root.get_node("RunState").opening_deck_for("raider", false)
	var expected := _unique_count(opener)
	_check(expected >= 5, "fixture contains a deck-sized set of identities")

	scene.call("_show_muster_deck_inspector")
	var overlay: Control = scene.get("_deck_inspect_overlay")
	var grid := _find_grid(overlay, expected)
	_check(grid != null, "inspector exposes its five-column deck grid")
	if grid == null:
		_finish()
		return
	_check(grid.get_child_count() == expected,
		"complete fixed-slot grid exists in the opening call")
	_check(_direct_back_count(grid) == expected,
		"every fixed slot has a face-down back before the first await")
	_check(_card_nodes(grid).is_empty(),
		"no rich Card2D leaks ahead of the reserved loading composition")

	var baseline: Array[Vector2] = []
	for _i in 8:
		await process_frame
		var now := _slot_centers(grid)
		if baseline.size() == now.size() and _max_delta(baseline, now) <= 0.01:
			break
		baseline = now
	_check(baseline.size() == expected, "grid reaches a complete initial layout")

	var visible_progress: Array[int] = [_visible_card_count(grid)]
	var back_progress: Array[int] = [_direct_back_count(grid)]
	var max_shift := 0.0
	var settled := false
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		_append_change(visible_progress, _visible_card_count(grid))
		_append_change(back_progress, _direct_back_count(grid))
		max_shift = maxf(max_shift, _max_delta(baseline, _slot_centers(grid)))
		var cards := _card_nodes(grid)
		if cards.size() == expected and _visible_card_count(grid) == expected \
				and _direct_back_count(grid) == 0 and _faces_at_rest(cards):
			settled = true
			break
	print("[deck-inspector] visible=%s backs=%s shift=%.3f settled=%s" % [
		str(visible_progress), str(back_progress), max_shift, str(settled)])
	_check(settled, "inspector reaches a complete settled deck")
	_check(visible_progress == [0, expected],
		"all rich faces reveal atomically 0 -> N")
	_check(back_progress == [expected, 0],
		"the complete back set leaves as one group")
	_check(max_shift <= 0.01,
		"slot centres never move during bake, hydration, or turn-over")

	# Closing during a cold rebuild must cancel its producer immediately; a new
	# inspector is the only one allowed to publish.
	scene.call("_hide_deck_inspector")
	await _wait_for_idle(cache)
	cache.clear()
	scene.call("_show_muster_deck_inspector")
	var stale: Control = scene.get("_deck_inspect_overlay")
	await process_frame
	scene.call("_hide_deck_inspector")
	scene.call("_show_muster_deck_inspector")
	var latest: Control = scene.get("_deck_inspect_overlay")
	_check(stale != latest, "rapid reopen creates a new guarded composition")
	_check(stale.get_parent() == null,
		"outgoing inspector detaches in the close frame")
	var latest_grid := _find_grid(latest, expected)
	deadline = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and latest_grid != null:
		await process_frame
		if _visible_card_count(latest_grid) == expected \
				and _direct_back_count(latest_grid) == 0:
			break
	_check(scene.get("_deck_inspect_overlay") == latest,
		"only the latest rapid-open generation can publish")
	_check(latest_grid != null and _visible_card_count(latest_grid) == expected,
		"latest rapid-open generation completes")

	# Reduce Motion keeps the same fixed loading state and complete final state,
	# but skips the scale turn.
	settings.set("reduce_motion", true)
	scene.call("_hide_deck_inspector")
	scene.call("_show_muster_deck_inspector")
	var reduced: Control = scene.get("_deck_inspect_overlay")
	var reduced_grid := _find_grid(reduced, expected)
	deadline = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and reduced_grid != null:
		await process_frame
		if _visible_card_count(reduced_grid) == expected \
				and _direct_back_count(reduced_grid) == 0:
			break
	_check(reduced_grid != null and _faces_at_rest(_card_nodes(reduced_grid)),
		"Reduce Motion publishes every face at its resting transform")

	scene.call("_hide_deck_inspector")
	scene.queue_free()
	for _i in 5:
		await process_frame
	_finish()


func _unique_count(deck: Array) -> int:
	var seen := {}
	for id in deck:
		seen[String(id)] = true
	return seen.size()


func _find_grid(host: Node, expected: int) -> GridContainer:
	if host == null:
		return null
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GridContainer and node.columns == 5 \
				and node.get_child_count() == expected:
			return node
		for child in node.get_children():
			stack.append(child)
	return null


func _direct_back_count(grid: Node) -> int:
	var count := 0
	for slot in grid.get_children():
		for child in slot.get_children():
			if child is TextureRect and child.texture == CARD_BACK_TEXTURE:
				count += 1
	return count


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


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node in _walk(host):
		var script := node.get_script() as Script
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
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


func _visible_card_count(grid: Node) -> int:
	var count := 0
	for card in _card_nodes(grid):
		if _effective_alpha(card, grid) > 0.99:
			count += 1
	return count


func _slot_centers(grid: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for child in grid.get_children():
		if child is Control:
			out.append(child.position + child.size * 0.5)
	return out


func _max_delta(a: Array[Vector2], b: Array[Vector2]) -> float:
	if a.size() != b.size():
		return INF
	var value := 0.0
	for i in a.size():
		value = maxf(value, a[i].distance_to(b[i]))
	return value


func _faces_at_rest(cards: Array[Node]) -> bool:
	if cards.is_empty():
		return false
	for card in cards:
		var face := card.get_parent() as Control
		if face == null or not face.scale.is_equal_approx(Vector2.ONE):
			return false
	return true


func _append_change(values: Array[int], value: int) -> void:
	if values.is_empty() or values[-1] != value:
		values.append(value)


func _wait_for_idle(cache: Node) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while bool(cache.get("_bake_busy")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(cache.get("_bake_busy")), "card baker becomes idle")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[deck-inspector] PASS ", message)
	else:
		_failures += 1
		push_error("[deck-inspector] FAIL " + message)


func _finish() -> void:
	print("[deck-inspector] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
