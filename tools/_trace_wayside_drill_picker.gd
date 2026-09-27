extends SceneTree
## Small, self-contained windowed trace for the cold Drill Yard card picker.
##
## Unlike the older multi-flow trace, this probe installs Wayside as the real
## current_scene and never waits for ScenePreload or frame_post_draw. Ordinary
## process frames let a windowed renderer advance, while phase deadlines plus a
## global watchdog guarantee that the process exits even if a render signal or
## async card bake gets stranded.
##
## Run windowed and serially:
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \
##       --script res://tools/_trace_wayside_drill_picker.gd
## Parse/autoload smoke only:
##   ... --headless --script res://tools/_trace_wayside_drill_picker.gd -- --check-only

const RUN_SEED := 20260910
const HARD_TIMEOUT_MS := 18000
const PHASE_TIMEOUT_MS := 6500
const STABLE_FRAMES := 6
const EXTRA_CARD_IDS: Array[String] = [
	"lookout", "thornguard", "raven", "battle_drummer", "hound",
	"warding_stone", "basilisk", "levy_palisade", "levy_mourner",
]

var _started := false
var _finished := false
var _hard_deadline_ms := 0
var _scene: Node = null
var _run_state: Node = null
var _cache: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_hard_deadline_ms = Time.get_ticks_msec() + HARD_TIMEOUT_MS
		_run()
	elif not _finished and Time.get_ticks_msec() >= _hard_deadline_ms:
		push_error("[wayside-drill] HARD_TIMEOUT after %dms" % HARD_TIMEOUT_MS)
		_finish(124)
	return false


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[wayside-drill] CHECK_ONLY_OK")
		_finish(0)
		return
	_run_state = root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	if _run_state == null or _cache == null or settings == null:
		push_error("[wayside-drill] required autoload missing")
		_finish(2)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = true
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)

	# This trace starts immediately. Stop the unrelated background resource queue
	# from later launching its one-card pipeline warm in the middle of the sample.
	var preloader := root.get_node_or_null("ScenePreload")
	if preloader != null:
		preloader.set_process(false)
		if preloader.has_method("cancel_deck_warm"):
			preloader.cancel_deck_warm()

	_run_state.start_new_run("raider", 0, RUN_SEED)
	_run_state.active_slot = -1
	for card_id: String in EXTRA_CARD_IDS:
		_run_state.add_card(card_id)
	_run_state.current_node_type = "wayside"
	_run_state.current_wayside_id = "drill_yard"
	_cache.clear()

	var packed := load("res://scenes/wayside.tscn") as PackedScene
	if packed == null:
		push_error("[wayside-drill] could not load wayside scene")
		_finish(3)
		return
	var nodes_before := _node_count()
	var objects_before := _object_count()
	var started_usec := Time.get_ticks_usec()
	_scene = packed.instantiate()
	root.add_child(_scene)
	current_scene = _scene
	var construct_call_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var eligible: Array = _scene.call("_drill_eligible")
	var expected := eligible.size()
	var initial_cards := _card_nodes().size()
	var construct := await _observe_card_count(expected, PHASE_TIMEOUT_MS)
	_print_phase("construct", construct_call_ms, started_usec, initial_cards,
		expected, nodes_before, objects_before, construct)
	_print_faces("construct")
	if bool(construct.timed_out) or expected == 0:
		push_error("[wayside-drill] picker did not reach its expected card count")
		_finish(4)
		return

	# Drive the authentic one-pick latch. Reduced motion removes only its cosmetic
	# 100 ms hold, making the reported call isolate the grid -> push-screen rebuild.
	var picked_card := _card_nodes()[0]
	var picked_slot := picked_card.get_parent().get_parent() as Control
	var picked_index := int(eligible[0])
	var picked_data: Dictionary = _run_state.get_upgraded_card_data(picked_index)
	var click_nodes_before := _node_count()
	var click_objects_before := _object_count()
	var click_started_usec := Time.get_ticks_usec()
	_scene.call("_on_grid_card_pressed", picked_slot,
		Callable(_scene, "_on_drill_pick").bind(picked_index))
	var click_call_ms := float(Time.get_ticks_usec() - click_started_usec) / 1000.0
	var click_initial_cards := _card_nodes().size()
	var click := await _observe_drill_push(PHASE_TIMEOUT_MS)
	_print_phase("click", click_call_ms, click_started_usec, click_initial_cards,
		1, click_nodes_before, click_objects_before, click)
	_print_faces("click")
	print("[wayside-drill] click_target index=%d id=%s mutation_ok=%s pending=%s" % [
		picked_index, String(picked_data.get("id", "")),
		str(int(_scene.get("_drill_index")) == picked_index),
		str(_scene.get("_grid_pick_pending"))])

	# Bakes are fire-and-forget in the current implementation. Give them a bounded
	# chance to drain, then report whether the visible push card actually swapped
	# to a snapshot or remained on the expensive live widget tree.
	var cache_wait_started := Time.get_ticks_msec()
	while bool(_cache.get("_bake_busy")) \
			and Time.get_ticks_msec() - cache_wait_started < PHASE_TIMEOUT_MS \
			and Time.get_ticks_msec() < _hard_deadline_ms:
		await process_frame
	print("[wayside-drill] bake_settle elapsed=%dms busy=%s" % [
		Time.get_ticks_msec() - cache_wait_started, str(_cache.get("_bake_busy"))])
	_print_faces("settled")
	print("[wayside-drill] DONE")
	_finish(0 if not bool(click.timed_out) else 5)


func _observe_card_count(target: int, timeout_ms: int) -> Dictionary:
	return await _observe(func() -> bool: return _card_nodes().size() == target,
		timeout_ms)


func _observe_drill_push(timeout_ms: int) -> Dictionary:
	return await _observe(func() -> bool:
		return is_instance_valid(_scene) and _card_nodes().size() == 1 \
			and int(_scene.get("_drill_index")) >= 0 \
			and not bool(_scene.get("_grid_pick_pending")), timeout_ms)


func _observe(done_test: Callable, timeout_ms: int) -> Dictionary:
	var started_ms := Time.get_ticks_msec()
	var deadline_ms := mini(started_ms + timeout_ms, _hard_deadline_ms)
	var previous_usec := Time.get_ticks_usec()
	var gaps: Array[float] = []
	var progression: Array[int] = [_card_nodes().size()]
	var last_count := progression[0]
	var stable := 0
	while Time.get_ticks_msec() < deadline_ms and is_instance_valid(_scene):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		gaps.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		var count := _card_nodes().size()
		if count != last_count:
			progression.append(count)
			last_count = count
		if bool(done_test.call()):
			stable += 1
			if stable >= STABLE_FRAMES:
				break
		else:
			stable = 0
	return {
		"timed_out": stable < STABLE_FRAMES,
		"frames": gaps.size(),
		"progression": progression,
		"max_gap_ms": _maximum(gaps),
		"p95_gap_ms": _percentile(gaps, 0.95),
	}


func _print_phase(label: String, call_ms: float, started_usec: int,
		initial_cards: int, expected: int, nodes_before: int, objects_before: int,
		trace: Dictionary) -> void:
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var render := _render_snapshot()
	print("[wayside-drill] %s call=%.2fms ready=%.2fms initial=%d expected=%d frames=%d max_gap=%.2fms p95=%.2fms progression=%s timeout=%s" % [
		label, call_ms, elapsed_ms, initial_cards, expected, int(trace.frames),
		float(trace.max_gap_ms), float(trace.p95_gap_ms), str(trace.progression),
		str(trace.timed_out)])
	print("[wayside-drill] %s nodes=%+d objects=%+d draws=%d canvas_objects=%d primitives=%d" % [
		label, _node_count() - nodes_before, _object_count() - objects_before,
		int(render.draws), int(render.canvas_objects), int(render.primitives)])


func _print_faces(label: String) -> void:
	var cards := _card_nodes()
	var baked_faces := 0
	var live_mode := 0
	var gallery_mode := 0
	var gameplay_hits := 0
	var gallery_hits := 0
	var seen := {}
	for card: Node in cards:
		if card.get("_baked_face") != null:
			baked_faces += 1
		if bool(card.get("live_baked_mode")):
			live_mode += 1
		if bool(card.get("gallery_baked_mode")):
			gallery_mode += 1
		var data: Dictionary = card.get("card_data")
		var key: String = _cache.cache_key(data)
		if seen.has(key):
			continue
		seen[key] = true
		if _cache.has(data):
			gameplay_hits += 1
		if _cache.has_gallery(data):
			gallery_hits += 1
	print("[wayside-drill] %s faces total=%d baked=%d live=%d live_mode=%d gallery_mode=%d unique=%d gameplay_hits=%d gallery_hits=%d" % [
		label, cards.size(), baked_faces, cards.size() - baked_faces, live_mode,
		gallery_mode, seen.size(), gameplay_hits, gallery_hits])


func _card_nodes() -> Array[Node]:
	var out: Array[Node] = []
	if _scene == null or not is_instance_valid(_scene):
		return out
	var stack: Array[Node] = [_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script := node.get_script() as Script
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _render_snapshot() -> Dictionary:
	var viewport_rid := root.get_viewport_rid()
	return {
		"draws": RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"canvas_objects": RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
	}


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value: float in values:
		result = maxf(result, value)
	return result


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(sorted.size() * fraction)) - 1, 0,
		sorted.size() - 1)]


func _finish(code: int) -> void:
	if _finished:
		return
	_finished = true
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		if audio.has_method("stop_music"):
			audio.stop_music()
		if audio.has_method("stop_ambience"):
			audio.stop_ambience()
	if current_scene == _scene:
		current_scene = null
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	quit(code)
