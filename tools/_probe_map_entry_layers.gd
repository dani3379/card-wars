extends SceneTree
## Windowed decomposition of map entry: CPU generation while hidden, first
## vector presentation, full bake/readback, and cached reopen.

const RUN_SEED := 20260903

var _started := false
var _done := false
var _recording := false
var _previous_usec := 0
var _gaps: Array[float] = []
var _scene: Node = null


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _recording and _previous_usec > 0:
		_gaps.append(float(now - _previous_usec) / 1000.0)
	_previous_usec = now
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await create_timer(7.0).timeout

	# Generation only: the MapTerrain build runs, but the hidden CanvasItem does
	# not submit its thousands of fallback commands and bake mode suppresses the
	# offscreen pipeline.
	_prepare_run(true)
	_scene = load("res://scenes/map.tscn").instantiate()
	_scene.set("bake_mode", "plate")
	_scene.visible = false
	_begin_record()
	root.add_child(_scene)
	await create_timer(1.4).timeout
	_end_record("hidden_generation")
	_scene.visible = true
	_begin_record()
	await create_timer(1.0).timeout
	_end_record("first_vector_present")
	await _close()

	# Generation + live fallback presentation, with no offscreen bake.
	_prepare_run(true)
	_scene = load("res://scenes/map.tscn").instantiate()
	_scene.set("bake_mode", "plate")
	_begin_record()
	root.add_child(_scene)
	await create_timer(2.0).timeout
	_end_record("vector_cold_open")
	_print_canvas("vector_cold_open")
	await _close()

	# Shipping path: generation, vector fallback, geography readback, march
	# readback. Keep the resulting per-act cache for the next state.
	_prepare_run(true)
	_scene = load("res://scenes/map.tscn").instantiate()
	_begin_record()
	root.add_child(_scene)
	await create_timer(5.0).timeout
	_end_record("baked_cold_open")
	_print_canvas("baked_cold_open")
	await _close()

	_scene = load("res://scenes/map.tscn").instantiate()
	_begin_record()
	root.add_child(_scene)
	await create_timer(2.5).timeout
	_end_record("cached_reopen")
	_print_canvas("cached_reopen")
	await _close()

	_done = true
	quit(0)


func _prepare_run(clear_map_cache: bool) -> void:
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = ""
	rs.current_encounter_id = ""
	if clear_map_cache:
		rs.map_plate_cache.clear()


func _begin_record() -> void:
	_gaps.clear()
	_previous_usec = Time.get_ticks_usec()
	_recording = true


func _end_record(label: String) -> void:
	_recording = false
	var s := _stats(_gaps)
	print("[map-entry] %s frames=%d avg=%.2f p95=%.2f p99=%.2f max=%.2f over16=%d over33=%d over100=%d" % [
		label, _gaps.size(), s.avg, s.p95, s.p99, s.max,
		_count_over(16.7), _count_over(33.3), _count_over(100.0)])


func _print_canvas(label: String) -> void:
	var rid := root.get_viewport_rid()
	print("[map-entry] %s canvas draws=%d objects=%d primitives=%d texture=%.1fMiB" % [
		label,
		RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0])


func _count_over(threshold: float) -> int:
	var count := 0
	for gap in _gaps:
		if gap > threshold:
			count += 1
	return count


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"avg": total / values.size(),
		"p95": sorted[clampi(int(ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)],
		"p99": sorted[clampi(int(ceil(sorted.size() * 0.99)) - 1, 0, sorted.size() - 1)],
		"max": sorted[-1],
	}


func _close() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	for _i in 5:
		await process_frame
	await create_timer(0.2).timeout
