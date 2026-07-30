extends Node
## _shot_seal_proto.gd — ground-truth render of the WaxSeal painter (windowed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_seal_proto.tscn
## Draws the three stat waxes + the two Command waxes at 120 / 56 / 38px
## (full + simple modes) on both parchment and dark table swatches, so the
## painter can be judged against in-game captures at native scale.
## Output: tools/screenshot/_seal_proto.png

const WaxSeal := preload("res://scripts/ui/painters/WaxSeal.gd")

func _ready() -> void:
	await get_tree().process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 640))
	await get_tree().process_frame

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Two ground swatches: card parchment / dark war table.
	var parch := ColorRect.new()
	parch.color = Color(0.87, 0.80, 0.66)
	parch.position = Vector2(0, 0)
	parch.size = Vector2(1280, 320)
	root.add_child(parch)
	var table := ColorRect.new()
	table.color = Color(0.09, 0.075, 0.06)
	table.position = Vector2(0, 320)
	table.size = Vector2(1280, 320)
	root.add_child(table)

	var waxes := [
		["cost", GameTheme.COST_BLUE_GEM],
		["atk", GameTheme.ATK_GOLD_SHIELD],
		["hp", GameTheme.HEALTH_RED_DROP],
		["cmd", GameTheme.MANA_BLUE],
		["foe", GameTheme.COMMAND_RED_GEM],
	]
	for row in range(2):
		var y0 := 100.0 + 320.0 * float(row)
		for i in waxes.size():
			var x0 := 60.0 + 240.0 * float(i)
			_put_seal(root, waxes[i][1], String(waxes[i][0]),
				Vector2(x0, y0), 120.0, false)
			_put_seal(root, waxes[i][1], String(waxes[i][0]),
				Vector2(x0 + 130, y0 + 20), 56.0, false)
			_put_seal(root, waxes[i][1], String(waxes[i][0]),
				Vector2(x0 + 130, y0 + 90), 38.0, true)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_seal_proto.png")
	print("SEAL_PROTO_DONE ", img.get_size())
	get_tree().quit()


func _put_seal(root: Control, wax: Color, seed_t: String, pos: Vector2,
		px: float, simple: bool) -> void:
	var s: Control = WaxSeal.new()
	s.wax = wax
	s.seed_text = seed_t + str(px)
	s.simple_mode = simple
	s.position = pos
	s.size = Vector2(px, px)
	root.add_child(s)
	var n := Label.new()
	n.text = "3"
	if GameTheme.font_stat != null:
		n.add_theme_font_override("font", GameTheme.font_stat)
	n.add_theme_font_size_override("font_size", int(px * 0.42))
	n.add_theme_color_override("font_color", Color(1, 0.98, 0.92))
	n.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.9))
	n.add_theme_constant_override("outline_size", maxi(2, int(px * 0.07)))
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.add_child(n)
