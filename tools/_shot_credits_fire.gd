extends Node
# THE CREDITS FIRELIGHT (2026-09-11).
#
#   Godot.exe --path "D:\Godot" res://tools/_shot_credits_fire.tscn
#
# Two frames a beat apart. The claim under test is that the roll now has a focal
# point and that the point is ALIVE — so a pair of frames that photograph
# identically means the guttering is not running, and a pair where the pool has
# obviously jumped means it is guttering too hard to read by.
#
# It also prints a MEASUREMENT, because "is it brighter in the middle" is exactly
# the sort of thing an eye will agree with whether or not it is true: mean
# luminance is sampled in three horizontal bands, and the reading band must come
# out brighter than both the head and the foot of the page. That is the whole
# claim of the effect, stated as a number.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	var scene: Node = load("res://scenes/credits.tscn").instantiate()
	get_tree().root.add_child(scene)
	# Let the roll drift far enough that real names sit in the reading band.
	await get_tree().create_timer(2.2).timeout
	await _snap("_shot_credits_a.png")
	await get_tree().create_timer(0.9).timeout
	await _snap("_shot_credits_b.png")

	print("SHOTS_DONE")
	get_tree().quit()


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	var h := img.get_height()
	var w := img.get_width()
	var bands := {"head": 0.12, "read": 0.46, "foot": 0.86}
	var out := PackedStringArray()
	for name in bands:
		var y0 := int(h * float(bands[name])) - 18
		var acc := 0.0
		var n := 0
		for y in range(maxi(y0, 0), mini(y0 + 36, h)):
			for x in range(0, w, 7):
				var c := img.get_pixel(x, y)
				acc += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				n += 1
		out.append("%s=%.4f" % [name, acc / maxf(float(n), 1.0)])
	print("SAVED %s  %s" % [path, " ".join(out)])
