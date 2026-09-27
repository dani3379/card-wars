extends SceneTree
## Windowed trace for the General's Forge slate that appears after relic claim.

const RUN_SEED := 20260903

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.reduce_motion = false
		settings.render_scale = 1.0
		settings.adaptive_render_scale = false
	var cache := root.get_node("CardTextureCache")
	await _wait_for_session_warmup(cache)

	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("stalwart", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = "elite"
	var reward = load("res://scenes/reward.tscn").instantiate()
	root.add_child(reward)
	for _i in 4:
		await RenderingServer.frame_post_draw

	reward._relic_taken = true
	var datas := _forge_datas(reward, rs, cache)
	if OS.get_cmdline_user_args().has("--warm"):
		await cache.bake_many(datas)
		for _i in 2:
			await RenderingServer.frame_post_draw
	print("[reward-forge-trace] before rebuild cache=%d/%d cards=%d" % [
		_cache_hits(cache, datas), datas.size(), _script_node_count(reward, "Card2D.gd")])
	var started := Time.get_ticks_usec()
	reward._build_ui()
	print("[reward-forge-trace] rebuild_sync=%.2fms" % [
		float(Time.get_ticks_usec() - started) / 1000.0])

	var previous := Time.get_ticks_usec()
	var trace_started := previous
	var last_state := ""
	var frame := 0
	while float(Time.get_ticks_usec() - trace_started) / 1000000.0 < 2.0:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var gap := float(now - previous) / 1000.0
		previous = now
		var state := "cache=%d/%d busy=%s cards=%d wrappers=%d" % [
			_cache_hits(cache, datas), datas.size(), str(bool(cache.get("_bake_busy"))),
			_script_node_count(reward, "Card2D.gd"), reward._forge_card_nodes.size()]
		if gap >= 10.0 or state != last_state:
			print("[reward-forge-trace] f=%d t=%.1fms gap=%.2fms %s" % [
				frame, float(now - trace_started) / 1000.0, gap, state])
		last_state = state
		frame += 1

	if OS.get_cmdline_user_args().has("--confirm"):
		var candidates: Array[int] = reward._forge_candidates()
		var deck_index: int = candidates[0]
		var base_data: Dictionary = rs.get_upgraded_card_data(deck_index)
		var upgraded_data: Dictionary = rs.preview_plus_upgrade(base_data)
		var confirm_started := Time.get_ticks_usec()
		reward._show_forge_confirm(deck_index)
		print("[reward-confirm-trace] call_sync=%.2fms upgraded_cached=%s" % [
			float(Time.get_ticks_usec() - confirm_started) / 1000.0,
			str(cache.has(upgraded_data))])
		previous = Time.get_ticks_usec()
		trace_started = previous
		frame = 0
		last_state = ""
		while float(Time.get_ticks_usec() - trace_started) / 1000000.0 < 1.5:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			var gap := float(now - previous) / 1000.0
			previous = now
			var state := "cached=%s busy=%s cards=%d dim=%s" % [
				str(cache.has(upgraded_data)), str(bool(cache.get("_bake_busy"))),
				_script_node_count(reward, "Card2D.gd"),
				str(reward.find_child("ForgeDim", true, false) != null)]
			if gap >= 10.0 or state != last_state:
				print("[reward-confirm-trace] f=%d t=%.1fms gap=%.2fms %s" % [
					frame, float(now - trace_started) / 1000.0, gap, state])
			last_state = state
			frame += 1

	reward.queue_free()
	for _i in 3:
		await process_frame
	_done = true
	quit(0)


func _wait_for_session_warmup(cache: Node) -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = preload_service == null \
			or bool(preload_service.is_warmup_complete())
		var pipeline_done: bool = preload_service == null \
			or bool(preload_service.get("_prewarmed"))
		if resources_done and pipeline_done and not bool(cache.get("_bake_busy")):
			break
		await create_timer(0.10).timeout
	for _i in 3:
		await RenderingServer.frame_post_draw


func _forge_datas(reward: Node, rs: Node, cache: Node) -> Array:
	var out: Array = []
	var seen := {}
	for i in reward._forge_candidates():
		var data: Dictionary = rs.get_upgraded_card_data(i)
		var key := String(cache.cache_key(data))
		if not seen.has(key):
			seen[key] = true
			out.append(data)
	return out


func _cache_hits(cache: Node, datas: Array) -> int:
	var hits := 0
	for data in datas:
		if cache.has(data):
			hits += 1
	return hits


func _script_node_count(host: Node, script_name: String) -> int:
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
