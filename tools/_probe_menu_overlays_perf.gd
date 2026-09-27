extends SceneTree
## Focused entry benchmark for the two reference overlays opened from MainMenu.
## Run windowed:
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \\
##       --script res://tools/_probe_menu_overlays_perf.gd

const SETTLE_FRAMES := 36

var _started := false
var _done := false
var _menu: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node_or_null("UserSettings")
	if settings == null:
		push_error("[menu-overlays] UserSettings autoload missing")
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
	await _wait_for_session_warmup()

	var packed := load("res://scenes/main_menu.tscn") as PackedScene
	if packed == null:
		push_error("[menu-overlays] main menu failed to load")
		_finish(1)
		return
	_menu = packed.instantiate()
	root.add_child(_menu)
	await create_timer(1.25).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw

	await _measure("settings_cold", Callable(_menu, "_on_open_settings"),
		Callable(self, "_settings_ready"))
	_close_settings()
	await create_timer(0.30).timeout
	await _measure("settings_reopen", Callable(_menu, "_on_open_settings"),
		Callable(self, "_settings_ready"))
	_close_settings()
	await create_timer(0.30).timeout

	await _measure("how_to_play_cold", Callable(_menu, "_show_how_to_play"),
		Callable(self, "_how_to_play_ready"))
	_close_how_to_play()
	await process_frame
	await create_timer(0.20).timeout
	await _measure("how_to_play_reopen", Callable(_menu, "_show_how_to_play"),
		Callable(self, "_how_to_play_ready"))

	print("MENU_OVERLAYS_PERF_DONE")
	_finish(0)


func _measure(label: String, opener: Callable, ready_check: Callable) -> void:
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var started := Time.get_ticks_usec()
	opener.call()
	var call_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var present_started := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var first_present_ms := float(Time.get_ticks_usec() - present_started) / 1000.0
	var gaps: Array[float] = []
	var ready_frame := -1
	for frame in SETTLE_FRAMES:
		var frame_started := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		gaps.append(float(Time.get_ticks_usec() - frame_started) / 1000.0)
		if ready_frame < 0 and bool(ready_check.call()):
			ready_frame = frame + 1
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[menu-overlays] %s call=%.2fms first_present=%.2fms settle_max=%.2fms ready_frame=%d nodes=%+d" % [
		label, call_ms, first_present_ms, _maximum(gaps), ready_frame,
		nodes_after - nodes_before])


func _settings_ready() -> bool:
	for child in root.get_node("UserSettings").get_children():
		if child.has_method("_open") and bool(child.get("_is_open")):
			return true
	return false


func _how_to_play_ready() -> bool:
	if _menu == null or not is_instance_valid(_menu):
		return false
	if _menu.has_method("how_to_play_ready"):
		return bool(_menu.call("how_to_play_ready"))
	return _menu.get_node_or_null("HowToPlayOverlay") != null


func _close_settings() -> void:
	for child in root.get_node("UserSettings").get_children():
		if child.has_method("_close"):
			child.call("_close")
			return


func _close_how_to_play() -> void:
	if _menu == null or not is_instance_valid(_menu):
		return
	var overlay := _menu.get_node_or_null("HowToPlayOverlay")
	if overlay != null:
		overlay.queue_free()


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	if preload_service == null:
		return
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if not preload_service.has_method("is_warmup_complete") \
				or bool(preload_service.is_warmup_complete()):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _finish(code: int) -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_done = true
	quit(code)
