extends SceneTree
## Regression for the combat draw/discard/exhaust viewer's fixed-grid loader.

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
	var run_state: Node = root.get_node("RunState")
	var settings: Node = root.get_node("UserSettings")
	var card_db: Node = root.get_node("CardDB")
	var cache: Node = root.get_node("CardTextureCache")
	settings.set("reduce_motion", true)
	settings.set("particles", false)
	run_state.start_new_run("stalwart", 0, 20260927)
	run_state.set("current_encounter_id", "goblin_scouts")
	run_state.set("current_node_type", "combat")
	var combat: Node = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	for _i in 90:
		await process_frame
	await _wait_for_idle(cache)
	cache.clear()

	var ids := _representative_ids(card_db, 18)
	combat.get("_player_discard_pile").clear()
	for id in ids:
		combat.get("_player_discard_pile").append(id)
	combat.call("_show_pile_viewer", 1)
	var layer: CanvasLayer = combat.get("_pile_viewer_layer")
	var grid := _find_grid(layer, ids.size())
	_check(grid != null, "viewer exposes the complete six-column grid")
	if grid == null:
		_finish()
		return
	_check(grid.get_child_count() == ids.size(),
		"every final slot exists in the opening call")
	_check(_direct_back_count(grid) == ids.size(),
		"every slot is covered before the first async frame")
	_check(_card_nodes(grid).is_empty(),
		"no ornate face leaks ahead of the fixed loading tableau")

	var baseline: Array[Vector2] = []
	for _i in 5:
		await process_frame
		baseline = _slot_centers(grid)
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
		if bool(combat.call("_pile_viewer_is_ready")) \
				and _visible_card_count(grid) == ids.size() \
				and _direct_back_count(grid) == 0:
			settled = true
			break
	print("[pile-atomic] visible=%s backs=%s shift=%.3f settled=%s" % [
		str(visible_progress), str(back_progress), max_shift, str(settled)])
	_check(settled, "viewer reaches a complete ready state")
	_check(visible_progress == [0, ids.size()],
		"visible faces publish atomically 0 -> N")
	_check(back_progress == [ids.size(), 0],
		"the complete back set retires in one frame")
	_check(max_shift <= 0.01,
		"slot centres never move during bake or hydration")

	# A canceled producer cannot repopulate a detached layer.
	cache.clear()
	combat.call("_close_pile_viewer")
	combat.call("_show_pile_viewer", 1)
	var stale: CanvasLayer = combat.get("_pile_viewer_layer")
	await process_frame
	combat.call("_close_pile_viewer")
	combat.call("_show_pile_viewer", 1)
	var latest: CanvasLayer = combat.get("_pile_viewer_layer")
	_check(stale != latest, "rapid reopen creates a fresh generation")
	_check(stale.get_parent() == null,
		"outgoing pile layer detaches in the close frame")
	deadline = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline \
			and not bool(combat.call("_pile_viewer_is_ready")):
		await process_frame
	_check(combat.get("_pile_viewer_layer") == latest,
		"only the latest rapid-open generation can publish")
	_check(bool(combat.call("_pile_viewer_is_ready")),
		"latest rapid-open generation completes")

	combat.call("_close_pile_viewer")
	combat.queue_free()
	for _i in 6:
		await process_frame
	_finish()


func _representative_ids(card_db: Node, wanted: int) -> Array[String]:
	var out: Array[String] = []
	for id_value in card_db.CARD_POOL.keys():
		var id := String(id_value)
		var data: Dictionary = card_db.get_card_data(id)
		if data.is_empty() or not bool(data.get("draftable", true)):
			continue
		if String(data.get("rarity", "")) == "enemy":
			continue
		out.append(id)
		if out.size() >= wanted:
			break
	return out


func _find_grid(host: Node, expected: int) -> GridContainer:
	if host == null:
		return null
	for node in _walk(host):
		if node is GridContainer and node.columns == 6 \
				and node.get_child_count() == expected:
			return node
	return null


func _direct_back_count(grid: Node) -> int:
	var count := 0
	for slot in grid.get_children():
		for child in slot.get_children():
			if child is TextureRect and child.texture == CARD_BACK_TEXTURE \
					and child.visible:
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
		print("[pile-atomic] PASS ", message)
	else:
		_failures += 1
		push_error("[pile-atomic] FAIL " + message)


func _finish() -> void:
	print("[pile-atomic] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
