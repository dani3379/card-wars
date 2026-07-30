extends Node
## Throwaway harness: freezes the ink-wipe transition shader at three
## progress stops over the main menu so the frontier's shape/ember can be
## eyeballed. Saves res://tools/screenshot/_inkwipe_<p>.png and quits.
##   Godot.exe --path . res://tools/_shot_inkwipe.tscn

const MENU := "res://scenes/main_menu.tscn"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	var menu: Node = load(MENU).instantiate()
	get_tree().root.add_child(menu)
	await get_tree().create_timer(1.2).timeout

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.043, 0.031, 0.024, 1.0)
	overlay.z_index = 1000
	var mat := ShaderMaterial.new()
	mat.shader = GameTheme._get_ink_wipe_shader()
	overlay.material = mat
	get_tree().root.add_child(overlay)

	for p in [0.25, 0.55, 0.85]:
		mat.set_shader_parameter("progress", p)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://tools/screenshot/_inkwipe_%02d.png" % int(p * 100))
		print("SAVED inkwipe ", p)
	print("INKWIPE_DONE")
	get_tree().quit()
