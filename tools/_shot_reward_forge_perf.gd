extends SceneTree
## Settled visual capture for the optimized General's Forge slate.

const OUT_PATH := "res://tools/screenshot/_perf_reward_forge.png"

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.reduce_motion = true
		settings.render_scale = 1.0
		settings.adaptive_render_scale = false
	var preload_service := root.get_node_or_null("ScenePreload")
	var cache := root.get_node("CardTextureCache")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = preload_service == null \
			or bool(preload_service.is_warmup_complete())
		var pipeline_done: bool = preload_service == null \
			or bool(preload_service.get("_prewarmed"))
		if resources_done and pipeline_done and not bool(cache.get("_bake_busy")):
			break
		await create_timer(0.10).timeout

	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("stalwart", 0, 20260903)
	rs.active_slot = -1
	rs.current_node_type = "elite"
	var reward = load("res://scenes/reward.tscn").instantiate()
	root.add_child(reward)
	for _i in 3:
		await RenderingServer.frame_post_draw
	reward._relic_taken = true
	reward._build_ui()

	deadline = Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if reward._forge_card_nodes.size() == reward._forge_candidates().size() \
				and _card_count(reward) == reward._forge_candidates().size():
			break
	for _i in 4:
		await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(OUT_PATH))
	var preview := image.duplicate()
	preview.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	preview.save_jpg(ProjectSettings.globalize_path(
		"res://tools/screenshot/_perf_reward_forge_preview.jpg"), 0.55)

	var candidates: Array[int] = reward._forge_candidates()
	reward._show_forge_confirm(candidates[0])
	deadline = Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var dim = reward.find_child("ForgeDim", true, false)
		if dim != null and _card_count(reward) == candidates.size() + 2 \
				and dim.modulate.a >= 0.99:
			break
	for _i in 4:
		await RenderingServer.frame_post_draw
	var confirm_image := root.get_viewport().get_texture().get_image()
	confirm_image.save_png(ProjectSettings.globalize_path(
		"res://tools/screenshot/_perf_reward_forge_confirm.png"))
	var confirm_preview := confirm_image.duplicate()
	confirm_preview.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	confirm_preview.save_jpg(ProjectSettings.globalize_path(
		"res://tools/screenshot/_perf_reward_forge_confirm_preview.jpg"), 0.55)
	print("[reward-forge-shot] confirm cards=%d dim=%s" % [
		_card_count(reward),
		str(reward.find_child("ForgeDim", true, false) != null)])
	print("[reward-forge-shot] saved=%s size=%s err=%d cards=%d" % [
		OUT_PATH, str(image.get_size()), err, _card_count(reward)])
	reward.queue_free()
	for _i in 3:
		await process_frame
	_done = true
	quit(0)


func _card_count(host: Node) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count
