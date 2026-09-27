extends SceneTree
## Windowed decomposition of Game Over's inherited _ready build.

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
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.graphics_preset = "medium"
		settings.render_scale = 1.0
		settings.adaptive_render_scale = false
		settings.particles = true
		settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_warmup()

	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260913)
	rs.active_slot = -1
	rs.hero_hp = 0
	rs.current_floor = 7
	rs.cause_of_death = "the component probe"
	if OS.get_cmdline_user_args().has("--empty-deck"):
		rs.deck.clear()
		rs.deck_uids.clear()

	var scene: Node = load("res://scenes/game_over.tscn").instantiate()
	scene.set_script(load("res://tools/_timed_game_over.gd"))
	var started := Time.get_ticks_usec()
	root.add_child(scene)
	print("[game-over-components] add_child=%7.2fms empty_deck=%s" % [
		float(Time.get_ticks_usec() - started) / 1000.0,
		str(OS.get_cmdline_user_args().has("--empty-deck"))])
	scene.call("perf_report")
	for _i in 90:
		await RenderingServer.frame_post_draw
	print("[game-over-components] after staged build")
	scene.call("perf_report")
	scene.queue_free()
	for _i in 4:
		await process_frame
	_done = true
	quit()


func _wait_for_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var cache := root.get_node_or_null("CardTextureCache")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done := preload_service == null \
			or bool(preload_service.is_warmup_complete())
		var cards_done := preload_service == null \
			or (bool(preload_service.get("_prewarmed")) \
			and not bool(cache.get("_bake_busy")))
		if resources_done and cards_done:
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw
