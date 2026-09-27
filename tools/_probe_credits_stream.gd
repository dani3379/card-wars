extends SceneTree
## Validates the progressively-built Credits roll, its foot, and early teardown.

var _started := false
var _done := false
var _fails := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.graphics_preset = "medium"
		settings.render_scale = 1.0
		settings.adaptive_render_scale = false
		settings.particles = true
		settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame

	var scene: Node = load("res://scenes/credits.tscn").instantiate()
	root.add_child(scene)
	for _i in 30:
		await RenderingServer.frame_post_draw

	var expected_lines := 0
	for section in scene.SECTIONS:
		expected_lines += (section.get("lines", []) as Array).size()
		_check(_has_label_text(scene, String(section.get("heading", ""))),
			"section heading is present: %s" % String(section.get("heading", "")))
		for line_text in section.get("lines", []):
			_check(_has_label_text(scene, String(line_text).strip_edges()),
				"credit line is present: %s" % String(line_text).strip_edges())
	_check(_has_label_text(scene, "Thank you for playing."),
		"closing thanks is present")

	var page := scene.find_child("CreditsPage", true, false) as Control
	var scroll := scene.get_node_or_null("Roll") as ScrollContainer
	_check(page != null and page.size.y > 900.0,
		"finished chronicle is taller than its temporary viewport minimum")
	_check(scroll != null, "credits scroll exists")
	if scroll != null:
		var limit := maxi(0, int(scroll.get_v_scroll_bar().max_value - scroll.size.y))
		_check(limit > 0, "finished roll has a real scroll range")
		scene.set("_rolled_out", true)
		scene.set("_scroll_pos", float(limit))
		scroll.scroll_vertical = limit
		for _i in 4:
			await RenderingServer.frame_post_draw
		if OS.get_cmdline_user_args().has("--shot"):
			var image := root.get_viewport().get_texture().get_image()
			var path := "res://tools/screenshot/_perf_credits_bottom.png"
			var err := image.save_png(ProjectSettings.globalize_path(path))
			_check(err == OK, "bottom-of-roll screenshot saved")
			print("[credits-stream] shot=%s limit=%d page_h=%.1f lines=%d" % [
				path, limit, page.size.y if page != null else 0.0, expected_lines])

	scene.queue_free()
	for _i in 4:
		await process_frame

	# Exit on the first hydration frame. Late section coroutines must observe
	# their invalid list owner and retire without rebuilding anything.
	var early: Node = load("res://scenes/credits.tscn").instantiate()
	root.add_child(early)
	await RenderingServer.frame_post_draw
	early.queue_free()
	for _i in 16:
		await RenderingServer.frame_post_draw
	_check(not is_instance_valid(early), "early-exit Credits scene is fully retired")

	print("[credits-stream] RESULT: %s (%d fails)" % [
		"ALL PASS" if _fails == 0 else "FAIL", _fails])
	_done = true
	quit(0 if _fails == 0 else 1)


func _has_label_text(host: Node, needle: String) -> bool:
	if needle == "":
		return false
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label and String(node.text) == needle:
			return true
		if node is RichTextLabel and String(node.text) == needle:
			return true
		for child: Node in node.get_children():
			stack.append(child)
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS  " + label)
	else:
		_fails += 1
		push_error("FAIL  " + label)
