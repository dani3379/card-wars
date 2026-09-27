extends SceneTree
## Settled visual capture for the optimized Rest forge picker and comparison.

const PICKER_PATH := "res://tools/screenshot/_perf_rest_forge.png"
const CONFIRM_PATH := "res://tools/screenshot/_perf_rest_forge_confirm.png"

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
	rs.start_new_run("raider", 0, 20260912)
	rs.active_slot = -1
	rs.current_node_type = "rest"
	var eligible: Array[int] = []
	for i in range(rs.deck.size()):
		if not rs.has_upgrade_path(i, "plus") \
				and root.get_node("CardDB").is_upgradeable(rs.deck[i]):
			eligible.append(i)

	var rest = load("res://scenes/rest.tscn").instantiate()
	root.add_child(rest)
	for _i in 4:
		await RenderingServer.frame_post_draw
	rest.call("_begin_pick_card_for_upgrade")
	deadline = Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if _card_count(rest) == eligible.size() and not bool(cache.get("_bake_busy")):
			break
	for _i in 4:
		await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var picker_err := image.save_png(ProjectSettings.globalize_path(PICKER_PATH))
	var preview := image.duplicate()
	preview.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	preview.save_jpg(ProjectSettings.globalize_path(
		"res://tools/screenshot/_perf_rest_forge_preview.jpg"), 0.60)

	rest.call("_select_card_for_upgrade", eligible[0])
	deadline = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if int(rest.get("_mode")) == 2 and _card_count(rest) == 2:
			break
	for _i in 4:
		await RenderingServer.frame_post_draw
	var confirm := root.get_viewport().get_texture().get_image()
	var confirm_err := confirm.save_png(ProjectSettings.globalize_path(CONFIRM_PATH))
	var confirm_preview := confirm.duplicate()
	confirm_preview.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	confirm_preview.save_jpg(ProjectSettings.globalize_path(
		"res://tools/screenshot/_perf_rest_forge_confirm_preview.jpg"), 0.60)
	print("[rest-forge-shot] picker=%d confirm=%d cards=%d" % [
		picker_err, confirm_err, _card_count(rest)])
	rest.queue_free()
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
