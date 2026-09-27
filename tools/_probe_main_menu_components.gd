extends SceneTree
## Windowed decomposition of MainMenu._ready. The scene is attached without its
## script first, then each startup component is invoked in authored order.

const DEADLINE_MS := 25000

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node_or_null("UserSettings")
	var cache := root.get_node_or_null("CardTextureCache")
	var preload_service := root.get_node_or_null("ScenePreload")
	if settings == null or cache == null:
		push_error("[menu-components] required autoload missing")
		_finish(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = true
	settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_warmup(preload_service, cache)

	var packed := load("res://scenes/main_menu.tscn") as PackedScene
	var scene := packed.instantiate() as Control
	var menu_script := load("res://tools/_timed_main_menu.gd") as Script
	scene.set_script(null)
	root.add_child(scene)
	for _i in 4:
		await RenderingServer.frame_post_draw
	scene.set_script(menu_script)

	var theme := root.get_node("GameTheme")
	await _measure("atmosphere", func() -> void:
		theme.call("add_atmosphere", scene, "main_menu"))
	scene.call("perf_reset")
	await _measure("menu_tree", func() -> void:
		scene.call("_rebuild_menu"))
	scene.call("perf_report")
	await _measure("parallax_setup", func() -> void:
		scene.call("_setup_bg_parallax"))
	await _measure("menu_embers", func() -> void:
		scene.call("_add_menu_embers"))
	await _measure("intro", func() -> void:
		scene.call("_animate_intro"))

	for _i in 20:
		await RenderingServer.frame_post_draw
	scene.queue_free()
	for _i in 4:
		await process_frame
	_finish(0)


func _measure(label: String, callback: Callable) -> void:
	var started := Time.get_ticks_usec()
	callback.call()
	var call_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	var present_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("[menu-components] %-16s call=%7.2fms present=%7.2fms" % [
		label, call_ms, present_ms])


func _wait_for_warmup(preload_service: Node, cache: Node) -> void:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
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


func _finish(code: int) -> void:
	_done = true
	quit(code)
