extends SceneTree
## One-state visual regression capture for the optimized Main Menu.

var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.reduce_motion = false
		settings.particles = true
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for _i in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var out := "res://tools/screenshot/_perf_main_menu.png"
	var error := image.save_png(out)
	print("[menu-shot] saved=%s size=%s error=%d" % [out, image.get_size(), error])
	menu.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
