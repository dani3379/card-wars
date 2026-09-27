extends SceneTree
## Visual QA for Motion.arm_loading_writ. The upper rank is the untouched card
## back; the lower rank shares the live screen-space lamplight material.

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
	root.get_node("UserSettings").reduce_motion = false
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var table := ColorRect.new()
	table.color = Color(0.025, 0.018, 0.014, 1.0)
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(table)
	var motion_script := load("res://scripts/ui/Motion.gd")
	var texture := load("res://assets/ui/card_back.png") as Texture2D
	for rank in 2:
		for i in 4:
			var back := TextureRect.new()
			back.texture = texture
			back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			back.position = Vector2(300 + i * 250, 70 + rank * 400)
			back.size = Vector2(225, 300)
			back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if rank == 1:
				motion_script.arm_loading_writ(back, host)
			host.add_child(back)
	await RenderingServer.frame_post_draw
	for i in 6:
		await create_timer(0.28).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var err := image.save_png("res://_shot_loading_lamplight_%02d.png" % i)
		print("[loading-lamplight-shot] frame=", i, " err=", err)
	_done = true
