extends SceneTree
## Windowed Collection/Cards virtualization benchmark.
## Measures top/middle/bottom scroll windows after hydration, including live
## Card2D bounds and steady canvas submissions. Run without --headless.

const SAMPLE_SECONDS := 0.65
const SETTLE_SECONDS := 5.0

var _scene: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[collection-card-perf] requires a windowed renderer")
		quit(1)
		return
	var settings: Node = root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = true
	settings.reduce_motion = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await _wait_for_warmup()

	var nodes_before: int = int(Performance.get_monitor(
		Performance.OBJECT_NODE_COUNT))
	var objects_before: int = int(Performance.get_monitor(
		Performance.OBJECT_COUNT))
	var memory_before: int = OS.get_static_memory_usage()
	var packed: PackedScene = load("res://scenes/collection.tscn")
	var started: int = Time.get_ticks_usec()
	_scene = packed.instantiate()
	root.add_child(_scene)
	await RenderingServer.frame_post_draw
	var first_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var settle_max: float = await _settle(SETTLE_SECONDS)
	print("[collection-card-perf] first=%.2fms settle_max=%.2fms" % [
		first_ms, settle_max])

	var scroll: ScrollContainer = _scene.get("_scroll")
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	var max_scroll: float = maxf(0.0, bar.max_value - bar.page)
	for stop in [
		{"name": "top", "ratio": 0.0},
		{"name": "middle", "ratio": 0.5},
		{"name": "bottom", "ratio": 1.0},
		{"name": "return_top", "ratio": 0.0},
	]:
		scroll.scroll_vertical = int(round(max_scroll * float(stop.ratio)))
		await _wait_visible(4.0)
		var measured: Dictionary = await _sample()
		var stats: Dictionary = _job_stats()
		print("[collection-card-perf] %s live=%d placeholders=%d visible_pending=%d nodes=%+d objects=%+d static=%+.1fMiB draws=%.0f canvas_objects=%.0f primitives=%.0f frame_p95=%.2f cpu=%.2f gpu=%.2f" % [
			stop.name, stats.live, stats.placeholders, stats.visible_pending,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before,
			int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before,
			float(OS.get_static_memory_usage() - memory_before) / 1048576.0,
			measured.draws, measured.objects, measured.primitives,
			measured.frame_p95, measured.cpu, measured.gpu])

	root.remove_child(_scene)
	_scene.free()
	for _i in 4:
		await process_frame
	quit(0)


func _wait_for_warmup() -> void:
	var service: Node = root.get_node_or_null("ScenePreload")
	if service == null:
		return
	var deadline: int = Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if (
			not service.has_method("is_warmup_complete")
			or bool(service.call("is_warmup_complete"))
		):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw


func _settle(seconds: float) -> float:
	var maximum: float = 0.0
	var previous: int = Time.get_ticks_usec()
	var deadline: int = previous + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		maximum = maxf(maximum, float(now - previous) / 1000.0)
		previous = now
	return maximum


func _wait_visible(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var stable: int = 0
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if int(_job_stats().visible_pending) == 0:
			stable += 1
			if stable >= 4:
				return
		else:
			stable = 0


func _job_stats() -> Dictionary:
	var jobs: Array = _scene.get("_card_jobs")
	var scroll: ScrollContainer = _scene.get("_scroll")
	var viewport_rect: Rect2 = scroll.get_global_rect()
	var live: int = 0
	var placeholders: int = 0
	var visible_pending: int = 0
	for raw_job in jobs:
		var job: Dictionary = raw_job
		var state: String = String(job.get("state", ""))
		var node: Control = job.get("node", null)
		if state == "card":
			live += 1
		else:
			placeholders += 1
			if (
				node != null and is_instance_valid(node)
				and node.get_global_rect().intersects(viewport_rect)
			):
				visible_pending += 1
	return {
		"live": live,
		"placeholders": placeholders,
		"visible_pending": visible_pending,
	}


func _sample() -> Dictionary:
	var viewport_rid: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var frames: Array[float] = []
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var draws: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	var deadline: int = previous + int(SAMPLE_SECONDS * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			+ RenderingServer.get_frame_setup_time_cpu())
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		draws.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
		primitives.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	return {
		"frame_p95": _percentile(frames, 0.95),
		"cpu": _average(cpu),
		"gpu": _average(gpu),
		"draws": _average(draws),
		"objects": _average(objects),
		"primitives": _average(primitives),
	}


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(sorted.size() * ratio)) - 1,
		0, sorted.size() - 1)]


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value in values:
		total += value
	return total / float(values.size())
