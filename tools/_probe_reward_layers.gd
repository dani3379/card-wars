extends SceneTree
## Focused windowed attribution probe for the elite Reward screen. Each sample
## hides one visual layer from the same settled scene so command-count deltas
## stay directly comparable.

const RUN_SEED := 20260908
const SAMPLE_SECONDS := 0.8

var _started := false
var _done := false
var _scene: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var rs := root.get_node_or_null("RunState")
	var us := root.get_node_or_null("UserSettings")
	if rs == null or us == null:
		push_error("[reward-layers] required autoloads missing")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	us.graphics_preset = "medium"
	us.render_scale = 1.0
	us.adaptive_render_scale = false
	us.particles = true
	us.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await create_timer(1.0).timeout
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = "elite"
	rs.gold = 214
	rs.hero_hp = 22
	_scene = load("res://scenes/reward.tscn").instantiate()
	root.add_child(_scene)
	await create_timer(3.0).timeout
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music()
		audio.stop_ambience()
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	_print_visual_tree(_scene)
	await _sample("all", rid)

	var standard := _scene.find_child("CompanyStandard", true, false) as CanvasItem
	await _hide_sample("standard_hidden", rid, [standard])
	var atmosphere := _scene.get_node_or_null("Atmosphere") as CanvasItem
	await _hide_sample("atmosphere_hidden", rid, [atmosphere])
	var motes := _scene.find_child("AmbientMotes", true, false) as CanvasItem
	await _hide_sample("motes_hidden", rid, [motes])

	var spoil_buttons: Array[CanvasItem] = []
	var relic_chips: Array[CanvasItem] = []
	for node in _walk(_scene):
		if node is Button and (node as Control).custom_minimum_size.x >= 300.0:
			spoil_buttons.append(node)
		if node is Panel and (node as Control).custom_minimum_size.x >= 150.0 \
				and (node as Control).custom_minimum_size.x == (node as Control).custom_minimum_size.y:
			relic_chips.append(node)
	await _hide_sample("spoil_tiles_hidden", rid, spoil_buttons)
	await _hide_sample("relic_chips_hidden", rid, relic_chips)

	RenderingServer.viewport_set_measure_render_time(rid, false)
	_scene.queue_free()
	for _i in 4:
		await process_frame
	_done = true
	quit(0)


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _print_visual_tree(host: Node) -> void:
	for node in _walk(host):
		if node is CanvasItem:
			var script: Script = node.get_script() as Script
			var script_name := String(script.resource_path).get_file() if script != null else ""
			if node is Control and ((node as Control).custom_minimum_size.length() > 100.0 \
					or script_name != ""):
				print("[reward-layers] node=%s type=%s min=%s script=%s" % [
					node.name, node.get_class(), str((node as Control).custom_minimum_size), script_name])


func _hide_sample(label: String, rid: RID, items: Array[CanvasItem]) -> void:
	var valid: Array[CanvasItem] = []
	for item in items:
		if item != null and is_instance_valid(item):
			item.visible = false
			valid.append(item)
	await process_frame
	await _sample(label, rid)
	for item in valid:
		item.visible = true
	await process_frame


func _sample(label: String, rid: RID) -> void:
	for _i in 5:
		await RenderingServer.frame_post_draw
	var frames: Array[float] = []
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var draws: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while float(Time.get_ticks_usec() - start) / 1000000.0 < SAMPLE_SECONDS:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid)
			+ RenderingServer.get_frame_setup_time_cpu())
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		draws.append(float(RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
		primitives.append(float(RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
	var f := _stats(frames)
	print("[reward-layers] %s frame_avg=%.2f p95=%.2f cpu=%.2f gpu=%.2f draws=%.0f objects=%.0f primitives=%.0f" % [
		label, f.avg, f.p95, _stats(cpu).avg, _stats(gpu).avg,
		_stats(draws).avg, _stats(objects).avg, _stats(primitives).avg])


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p95": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {"avg": total / values.size(),
		"p95": sorted[clampi(int(ceil(values.size() * 0.95)) - 1, 0, sorted.size() - 1)]}
