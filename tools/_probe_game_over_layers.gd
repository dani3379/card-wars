extends SceneTree
## Focused windowed A/B for the run-end screen. Distinguishes the one-shot
## flourish from cold Card2D fallbacks and the chronicle itself.

const RUN_SEED := 20260903
const SAMPLE_SECONDS := 1.0

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
	var cache := root.get_node_or_null("CardTextureCache")
	if rs == null or us == null or cache == null:
		push_error("[game-over-layers] required autoloads missing")
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
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)

	cache.clear()
	_prepare_run(rs)
	await _open()
	await create_timer(0.35).timeout
	_print_tree_state("cold_initial", cache, rs)
	await _sample("cold_initial", rid)

	var flourish := _scene.find_child("RunEndFlourish", true, false)
	if flourish != null:
		flourish.visible = false
	await process_frame
	await _sample("cold_flourish_hidden", rid)

	var cards := _find_script_nodes(_scene, "Card2D.gd")
	for card in cards:
		card.visible = false
	await process_frame
	await _sample("cold_cards_hidden", rid)
	for card in cards:
		card.visible = true
	var panel := _scene.get_node_or_null("RunSummaryPanel") as CanvasItem
	if panel != null:
		panel.visible = false
	await process_frame
	await _sample("cold_chronicle_hidden", rid)
	if panel != null:
		panel.visible = true

	# Existing cold Card2Ds do not change construction after their async bake.
	# Sample after every bake and one-shot flourish should have finished.
	await create_timer(3.0).timeout
	_print_tree_state("cold_settled", cache, rs)
	await _sample("cold_settled", rid)
	await _close()

	# The real late-run path should have most of the deck cached. Establish a
	# fully warm bound and compare it with the cold fallback above.
	_prepare_run(rs)
	var datas := _unique_deck_datas(rs)
	await cache.bake_many(datas)
	print("[game-over-layers] prewarmed=%d/%d" % [_cache_hits(cache, datas), datas.size()])
	await _open()
	await create_timer(3.0).timeout
	_print_tree_state("warm_settled", cache, rs)
	await _sample("warm_settled", rid)
	RenderingServer.viewport_set_measure_render_time(rid, false)
	await _close()
	_done = true
	quit(0)


func _prepare_run(rs: Node) -> void:
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.hero_hp = 0
	rs.current_floor = 7
	rs.cause_of_death = "the benchmark"


func _open() -> void:
	_scene = load("res://scenes/game_over.tscn").instantiate()
	root.add_child(_scene)
	await process_frame


func _close() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	for _i in 4:
		await process_frame
	await create_timer(0.2).timeout


func _unique_deck_datas(rs: Node) -> Array:
	var out: Array = []
	var keys: Dictionary = {}
	for i in rs.deck.size():
		var data: Dictionary = rs.get_upgraded_card_data(i)
		var key := String(root.get_node("CardTextureCache").cache_key(data))
		if not keys.has(key):
			keys[key] = true
			out.append(data)
	return out


func _cache_hits(cache: Node, datas: Array) -> int:
	var hits := 0
	for data in datas:
		if cache.has(data):
			hits += 1
	return hits


func _print_tree_state(label: String, cache: Node, rs: Node) -> void:
	var cards := _find_script_nodes(_scene, "Card2D.gd")
	var datas := _unique_deck_datas(rs)
	print("[game-over-layers] %s cards=%d cache=%d/%d flourish=%s nodes=%d objects=%d" % [
		label, cards.size(), _cache_hits(cache, datas), datas.size(),
		str(_scene.find_child("RunEndFlourish", true, false) != null),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])


func _find_script_nodes(host: Node, script_name: String) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if node is CanvasItem and script != null \
				and String(script.resource_path).get_file() == script_name:
			found.append(node)
		for child in node.get_children():
			stack.append(child)
	return found


func _sample(label: String, rid: RID) -> void:
	for _i in 6:
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
	print("[game-over-layers] %s frame_avg=%.2f p95=%.2f cpu=%.2f gpu=%.2f draws=%.0f objects=%.0f primitives=%.0f" % [
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
