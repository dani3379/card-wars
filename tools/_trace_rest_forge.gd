extends SceneTree
## Focused, windowed trace for Rest's cold forge picker and confirmation pair.
## Reports every long presented frame beside cache/card/build state so a future
## regression cannot silently rebuild an entire deck of full Card2D faces in one
## frame. Nothing is forged and no save slot is touched.

const RUN_SEED := 20260909
const TRACE_SECONDS_PICKER := 7.0
const TRACE_SECONDS_CONFIRM := 4.0

var _started := false
var _done := false
var _scene: Node = null
var _phase := "boot"
var _phase_usec := 0
var _last_post_usec := 0
var _last_signature := ""
var _frame_index := 0
var _eligible: Array[int] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node("UserSettings")
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
	await _wait_for_session_warmup()

	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = "rest"
	for i in range(rs.deck.size()):
		if not rs.has_upgrade_path(i, "plus") \
				and root.get_node("CardDB").is_upgradeable(rs.deck[i]):
			_eligible.append(i)
	await process_frame

	_scene = load("res://scenes/rest.tscn").instantiate()
	root.add_child(_scene)
	for _i in 8:
		await RenderingServer.frame_post_draw

	_begin_phase("picker")
	_scene.call("_begin_pick_card_for_upgrade")
	await _trace_for(TRACE_SECONDS_PICKER)

	if not _eligible.is_empty() and is_instance_valid(_scene):
		_begin_phase("confirm")
		_scene.call("_select_card_for_upgrade", _eligible[0])
		await _trace_for(TRACE_SECONDS_CONFIRM)

	print("[rest-forge] DONE")
	if is_instance_valid(_scene):
		_scene.queue_free()
	for _i in 4:
		await process_frame
	_done = true
	quit(0)


func _begin_phase(next_phase: String) -> void:
	_phase = next_phase
	_phase_usec = Time.get_ticks_usec()
	_last_post_usec = _phase_usec
	_last_signature = ""
	_frame_index = 0
	print("[rest-forge] BEGIN %s eligible=%d" % [_phase, _eligible.size()])


func _trace_for(seconds: float) -> void:
	while is_instance_valid(_scene) \
			and float(Time.get_ticks_usec() - _phase_usec) / 1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		_trace_presented_frame()


func _trace_presented_frame() -> void:
	var now := Time.get_ticks_usec()
	var gap := float(now - _last_post_usec) / 1000.0
	_last_post_usec = now
	_frame_index += 1
	var cards := _count_script_nodes(_scene, "Card2D.gd")
	var cache_hits := 0
	var rs := root.get_node("RunState")
	var cache := root.get_node("CardTextureCache")
	for deck_index in _eligible:
		if cache.has(rs.get_upgraded_card_data(deck_index)):
			cache_hits += 1
	var busy := bool(cache.get("_bake_busy"))
	var mode := int(_scene.get("_mode"))
	var build_gen := int(_scene.get("_ui_build_gen"))
	var controls := _count_controls(_scene)
	var sig := "mode=%d gen=%d cache=%d/%d cards=%d busy=%s controls=%d" % [
		mode, build_gen, cache_hits, _eligible.size(), cards, str(busy), controls]
	if sig != _last_signature or gap >= 16.0:
		print("[rest-forge] %s f=%d t=%.2fms gap=%.2fms %s" % [
			_phase, _frame_index, float(now - _phase_usec) / 1000.0, gap, sig])
		_last_signature = sig


func _count_script_nodes(host: Node, script_name: String) -> int:
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


func _count_controls(host: Node) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node("ScenePreload")
	var cache := root.get_node("CardTextureCache")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if preload_service.is_warmup_complete() \
				and bool(preload_service.get("_prewarmed")) \
				and not bool(cache.get("_bake_busy")):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw
