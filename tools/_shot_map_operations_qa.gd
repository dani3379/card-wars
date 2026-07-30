extends Node
## Focused visual QA for the live campaign-order overlay. It enters a generated
## mid-run map, chooses the reachable stop in the densest local cluster, and
## records the moving order at focused and full-chart scale.

const HERO_ID := "raider"

var _map: Node = null


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func():
		print("[map-operation-shot] WATCHDOG")
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
	RunState.start_new_run(HERO_ID)
	for _i in range(3):
		var available: Array = RunState.get_available_nodes()
		if available.is_empty():
			break
		RunState.visit_node(int(available[0].row), int(available[0].col))
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""

	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	await get_tree().create_timer(4.0).timeout
	var nd := _densest_available()
	if nd.is_empty():
		print("[map-operation-shot] FAIL: no available destination")
		get_tree().quit(1)
		return
	var origin: Vector2 = _map._player_pos if _map._has_player else _map._camp_pos
	var dest: Vector2 = nd.get("pos", Vector2.ZERO)
	var label: String = _map._site_label_for_preview(nd)
	var path: PackedVector2Array = _map.road_path_between(origin, dest)
	print("[map-operation-shot] destination=%s label=%s nearby=%d" % [
		str(dest), label, _nearby_count(dest)])

	_map._set_view(1.25, Vector2(800, 450) - dest * 1.25)
	_map._overlay.march_along(path, label, 2.8)
	await get_tree().create_timer(1.05).timeout
	await _shoot("_shot_map_operation_focus.png")
	_map._set_view(1.0, Vector2.ZERO)
	await get_tree().create_timer(0.12).timeout
	await _shoot("_shot_map_operation_full.png")

	# The same issued order at its quiet-motion endpoint. The moving rank column
	# must be absent, while the route and destination order remain explicit.
	UserSettings.reduce_motion = true
	_map._set_view(1.25, Vector2(800, 450) - dest * 1.25)
	await _map._overlay.march_along(path, label, 2.8)
	await _shoot("_shot_map_operation_reduce_motion.png")
	print("[map-operation-shot] DONE")
	get_tree().quit(0)


func _densest_available() -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for nd in _map._nodes:
		if not bool(nd.get("avail", false)) or bool(nd.get("vis", false)):
			continue
		var p: Vector2 = nd.get("pos", Vector2.ZERO)
		var score := _nearby_count(p)
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


func _shoot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var err := image.save_png("res://" + filename)
	print("[map-operation-shot] %s %s" % ["SAVED" if err == OK else "FAIL", filename])

