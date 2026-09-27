extends SceneTree
## Focused one-screen Game Over visual QA. Avoids the legacy seal harness's
## rapid teardown/reopen path and captures the same settled production scene.

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings: Node = root.get_node("UserSettings")
	settings.set("graphics_preset", "medium")
	settings.set("render_scale", 1.0)
	settings.set("adaptive_render_scale", false)
	settings.set("particles", true)
	settings.set("reduce_motion", false)
	var supersample: Node = root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()

	var rs: Node = root.get_node("RunState")
	rs.set("active_slot", -1)
	rs.start_new_run("raider", 0, 20260914)
	rs.set("active_slot", -1)
	rs.set("hero_hp", 0)
	rs.set("current_floor", 11)
	rs.set("fights_won", 9)
	rs.set("gold", 186)
	rs.set("cause_of_death", "the Kindler")
	rs.add_relic("whetstone")
	rs.add_relic("war_horn")
	rs.set("fallen", [
		{"uid": 9001, "name": "Pikeman the Grim", "enc": "the Bone Pit", "act": 1},
		{"uid": 9002, "name": "Outrider", "enc": "the Kindler", "act": 2},
	])
	rs.set("creature_kills", {9001: 7})

	var preload_service: Node = root.get_node("ScenePreload")
	preload_service.warm_game_over_ui()
	var deadline := Time.get_ticks_msec() + 1500
	while not bool(preload_service.get("_game_over_ui_warmed")) \
			and Time.get_ticks_msec() < deadline:
		await process_frame

	var scene: Node = load("res://scenes/game_over.tscn").instantiate()
	root.add_child(scene)
	await create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var out := "res://_perf_game_over_defeat_settled.png"
	var err := image.save_png(out)
	print("[game-over-shot] saved=%s err=%d size=%s cards=%d" % [
		out, err, str(image.get_size()), _script_node_count(scene, "Card2D.gd")])
	_done = true
	quit(0)


func _wait_for_session_warmup() -> void:
	var preload_service: Node = root.get_node("ScenePreload")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if bool(preload_service.is_warmup_complete()) \
				and bool(preload_service.get("_prewarmed")):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw


func _script_node_count(host: Node, script_name: String) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).get_file() == script_name:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count
