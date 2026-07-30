extends Node
## Visual QA for the committed road when all three marching ranks have room.

var _map: Node = null


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func():
		print("[map-column-shot] WATCHDOG")
		get_tree().quit(1))
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	UserSettings.reduce_motion = false
	RunState.start_new_run("raider")
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	await get_tree().create_timer(4.0).timeout

	var nd := _pick_destination()
	if nd.is_empty():
		print("[map-column-shot] FAIL: no available destination")
		get_tree().quit(1)
		return
	var origin: Vector2 = _map._camp_pos
	var dest: Vector2 = nd.get("pos", Vector2.ZERO)
	var label: String = _map._site_label_for_preview(nd)
	var path: PackedVector2Array = _map.road_path_between(origin, dest)
	print("[map-column-shot] destination=%s label=%s nearby=%d length=%.1f" % [
		str(dest), label, _nearby_count(dest), _path_length(path)])

	_map._set_view(1.25, Vector2(800, 450) - dest * 1.25)
	_map._overlay.march_along(path, label, 2.8)
	await get_tree().create_timer(1.45).timeout
	await _shoot("_shot_map_operation_column_focus.png")
	_map._set_view(1.0, Vector2.ZERO)
	await get_tree().create_timer(0.10).timeout
	await _shoot("_shot_map_operation_column_full.png")

	UserSettings.reduce_motion = true
	_map._set_view(1.25, Vector2(800, 450) - dest * 1.25)
	await _map._overlay.march_along(path, label, 2.8)
	await _shoot("_shot_map_operation_column_reduce_motion.png")
	print("[map-column-shot] DONE")
	get_tree().quit(0)


func _pick_destination() -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for nd in _map._nodes:
		if not bool(nd.get("avail", false)) or bool(nd.get("vis", false)):
			continue
		var p: Vector2 = nd.get("pos", Vector2.ZERO)
		var score: float = float(_nearby_count(p)) * 1000.0 + (_map._camp_pos as Vector2).distance_to(p)
		if score > best_score:
			best = nd
			best_score = score
	return best


func _nearby_count(p: Vector2) -> int:
	var count := 0
	for other in _map._nodes:
		var q: Vector2 = other.get("pos", Vector2.ZERO)
		if q != p and q.distance_to(p) < 155.0:
			count += 1
	return count


func _path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _shoot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var err := image.save_png("res://" + filename)
	print("[map-column-shot] %s %s" % ["SAVED" if err == OK else "FAIL", filename])

