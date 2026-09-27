extends SceneTree
## Deterministic windowed trace for Event's cold full-deck and Wet Cards pickers.
## No choices are clicked and no save slot is claimed.

const RUN_SEED := 20260912
const DEADLINE_MS := 25000
const EXTRA_CARD_IDS: Array[String] = [
	"lookout", "thornguard", "raven", "battle_drummer",
	"hound", "warding_stone", "basilisk", "adrenaline",
]

var _started := false
var _done := false
var _run_state: Node = null
var _cache: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[event-cards] CHECK_ONLY_OK")
		_finish(0)
		return
	_run_state = root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	if _run_state == null or _cache == null or settings == null:
		push_error("[event-cards] required autoload missing")
		_finish(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()

	var requested := _arg_value("--case=", "all")
	var cases: Array[String] = []
	if requested == "all":
		cases.assign(["full", "stranger", "result", "pair", "appraisal"])
	else:
		cases.append(requested)
	for case_name: String in cases:
		if case_name not in ["full", "stranger", "result", "pair", "appraisal"]:
			push_error("[event-cards] unknown case %s" % case_name)
			_finish(2)
			return
		await _trace_case(case_name)
	print("[event-cards] DONE")
	_finish(0)


func _prepare_run() -> void:
	await _retire_bakers()
	_cache.clear()
	_run_state.active_slot = -1
	_run_state.start_new_run("raider", 0, RUN_SEED)
	_run_state.active_slot = -1
	for card_id in EXTRA_CARD_IDS:
		_run_state.add_card(card_id)
	_run_state.current_node_type = "event"
	_run_state.current_bridge = true
	_run_state.events_seen.erase("the_crossing")
	await process_frame


func _trace_case(case_name: String) -> void:
	await _prepare_run()
	var scene = load("res://scenes/event.tscn").instantiate()
	root.add_child(scene)
	for _i in 6:
		await RenderingServer.frame_post_draw
	await _retire_bakers()
	_cache.clear()
	if case_name in ["stranger", "appraisal"]:
		var event_id := "strangers_hand" if case_name == "stranger" \
			else "pawnbrokers_window"
		scene.set("_event_id", event_id)
		scene.set("_event_data", scene.EVENTS[event_id])
		scene.set("_current_node", scene.EVENTS[event_id])
		seed(RUN_SEED)

	var expected := 0
	match case_name:
		"full": expected = _run_state.deck.size()
		"stranger", "result": expected = 3
		"pair": expected = 2
		"appraisal": expected = 1
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var started := Time.get_ticks_usec()
	match case_name:
		"full": scene.call("_start_remove_mode")
		"stranger": scene.call("_start_stranger_hand_mode")
		"result":
			scene.set("_result_cards", [
				root.get_node("CardDB").get_card_data("rat_piper"),
				root.get_node("CardDB").get_card_data("petard"),
				root.get_node("CardDB").get_card_data("trebuchet"),
			])
			scene.call("_show_result", "Three cards join your deck.")
		"pair":
			var before: Dictionary = root.get_node("CardDB").get_card_data("levy_rider")
			var after: Dictionary = _run_state.preview_plus_upgrade(before)
			scene.set("_result_pairs", [{"before": before, "after": after}])
			scene.call("_show_result", "The card was forged.")
		"appraisal": scene.call("_start_appraisal_mode")
	var call_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await _trace_population(case_name, scene, expected, started, call_ms,
		nodes_before, objects_before)
	if OS.get_cmdline_user_args().has("--shot"):
		# Let the final Wet Cards flip finish before capturing settled pixels.
		await create_timer(1.25).timeout
		for _i in 3:
			await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var path := "res://tools/screenshot/_perf_event_cards_%s.png" % case_name
		var err := image.save_png(ProjectSettings.globalize_path(path))
		print("[event-cards] shot=%s err=%d" % [path, err])
	await _close_scene(scene)


func _trace_population(label: String, scene: Node, expected: int, started: int,
		call_ms: float, nodes_before: int, objects_before: int) -> void:
	var gaps: Array[float] = []
	var progression: Array[int] = []
	var last_count := -1
	var previous := started
	var complete_at := -1
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(scene):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		gaps.append(float(now - previous) / 1000.0)
		previous = now
		var count := _card_nodes(scene).size()
		if count != last_count:
			progression.append(count)
			last_count = count
		if count == expected and complete_at < 0:
			complete_at = now
		if complete_at >= 0 and now - complete_at >= 900000:
			break
	var elapsed_ms := float((previous if complete_at < 0 else complete_at) - started) / 1000.0
	var cards := _card_nodes(scene)
	var baked_faces := 0
	var cache_hits := 0
	var seen := {}
	for card in cards:
		if card.get("_baked_face") != null:
			baked_faces += 1
		var data: Dictionary = card.get("card_data")
		var key: String = _cache.cache_key(data)
		if seen.has(key):
			continue
		seen[key] = true
		if _cache.has(data):
			cache_hits += 1
	print("[event-cards] %s expected=%d call=%.2fms complete=%.2fms frames=%d max=%.2fms p95=%.2fms progression=%s" % [
		label, expected, call_ms, elapsed_ms, gaps.size(), _maximum(gaps),
		_percentile(gaps, 0.95), str(progression)])
	print("[event-cards] %s cards=%d baked_faces=%d unique=%d cache_hits=%d nodes=%+d objects=%+d busy=%s" % [
		label, cards.size(), baked_faces, seen.size(), cache_hits,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before,
		str(_cache.get("_bake_busy"))])


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _close_scene(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	for _i in 4:
		await process_frame
	await _retire_bakers()


func _retire_bakers() -> void:
	if _cache == null:
		return
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var quiet_frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if bool(_cache.get("_bake_busy")):
			quiet_frames = 0
		else:
			quiet_frames += 1
			if quiet_frames >= 6:
				return


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = preload_service == null \
			or bool(preload_service.is_warmup_complete())
		var cards_done: bool = preload_service == null \
			or (bool(preload_service.get("_prewarmed")) \
			and not bool(_cache.get("_bake_busy")))
		if resources_done and cards_done:
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await process_frame


func _arg_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
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
	_done = true
	quit(code)
