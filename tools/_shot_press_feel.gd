extends Node
## _shot_press_feel.gd — EYES on the press pass (2026-09-17). WINDOWED.
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_press_feel.tscn
##
## `_probe_press_feedback` proves a press MOVES the control. It cannot say
## whether the movement is legible, and the numbers say it might not be: the
## shipped squash is 1.8% on x and 5.6% on y, which on a 220x52 primary button
## is 4px and 3px of total travel. That is a judgement call about pixels, and
## the house rule is that those are made by looking (and at ZOOM — the coach
## device pass found an arrow rendering with no white pixels in it at all, and
## an 8px seam, neither decidable at 1600x900).
##
## So this shoots each of the four house button kinds at REST and at the BOTTOM
## OF THE DIP, prints the measured edge travel per kind, and saves a 4x
## nearest-neighbour crop of the worst case (the smallest control, where the
## proportional squash buys the fewest pixels).
##
## It also shoots the at-cursor mark, which is the one genuinely new thing in
## the pass: every other ring in this game expands, and a ring run backwards has
## never been on screen here before.

const OUT := "res://tools/screenshot/"
const BG := Color(0.086, 0.063, 0.048)

var _log: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[pressfeel] WATCHDOG fired — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1000, 560))
	DisplayServer.window_move_to_foreground()
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true

	var ground := ColorRect.new()
	ground.color = BG
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ground)

	# The four kinds a player actually presses, at their real sizes.
	var kinds := {
		"primary": GameTheme.make_primary_button("TAKE THE FIELD"),
		"back": GameTheme.make_back_button("LEAVE THE WAGON"),
		"themed": GameTheme.make_themed_button("BUY  50g",
			Color(0.85, 0.66, 0.30), Vector2(200, 56), 18),
		"close": GameTheme.make_close_button(),
	}
	var y := 60.0
	var order: Array[String] = ["primary", "back", "themed", "close"]
	for k in order:
		var b: Button = kinds[k]
		b.position = Vector2(120, y)
		add_child(b)
		y += 110.0
	await get_tree().process_frame
	await get_tree().process_frame

	# ── Rest, then the dip, measured on the SAME control ──────────────────
	var rest_rects := {}
	for k in order:
		var b: Button = kinds[k]
		rest_rects[k] = Rect2(b.position, b.size)
	await _shoot("press_rest")

	for k in order:
		(kinds[k] as Button).button_down.emit()
	# Past PRESS_DIP (0.055) so the dip has fully landed, well short of anything
	# springing back — nothing does, because the hold waits on the finger.
	await get_tree().create_timer(0.14).timeout
	await _shoot("press_dip")

	for k in order:
		var b: Button = kinds[k]
		var r: Rect2 = rest_rects[k]
		# `scale` is about the centre (pivot_offset = size * 0.5), so the visible
		# travel at each edge is half the total. That half is the number a player
		# can actually see move, so it is the one reported.
		var dx: float = r.size.x * (1.0 - b.scale.x) * 0.5
		var dy: float = r.size.y * (1.0 - b.scale.y) * 0.5
		_log.append("  %-8s %4.0fx%-3.0f  edge travel  x %.2fpx   y %.2fpx"
			% [k, r.size.x, r.size.y, dx, dy])

	# 4x zoom on the SMALLEST control — the worst case for a proportional squash.
	await _zoom_crop("press_dip_zoom", Rect2i(100, 380, 200, 120))

	for k in order:
		(kinds[k] as Button).button_up.emit()
	await get_tree().create_timer(0.30).timeout
	await _shoot("press_released")

	# ── The at-cursor mark, on its own dark ground ────────────────────────
	for k in order:
		(kinds[k] as Button).visible = false
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	# Three points along the collapse. It starts WIDE and closes onto the
	# cursor, which is the read being checked — an outward mark here would mean
	# the press looks like an emission rather than an absorption.
	Motion.press_mark(stage, Vector2(500, 280))
	await get_tree().create_timer(0.05).timeout
	await _shoot("mark_open")
	await _zoom_crop("mark_open_zoom", Rect2i(410, 190, 180, 180))
	await get_tree().create_timer(0.08).timeout
	await _shoot("mark_closing")
	await _zoom_crop("mark_closing_zoom", Rect2i(410, 190, 180, 180))

	# And in context, where it actually lives: on the plate, at the press point,
	# with the plate dipping under it.
	for k in order:
		(kinds[k] as Button).visible = true
	var prim: Button = kinds["primary"]
	prim.button_down.emit()
	Motion.press_mark(prim, Motion.press_point_on(prim))
	await get_tree().create_timer(0.07).timeout
	await _shoot("mark_on_plate")
	await _zoom_crop("mark_on_plate_zoom", Rect2i(100, 40, 320, 110))

	print("")
	print("[pressfeel] ======== MEASURED EDGE TRAVEL AT THE DIP ========")
	for line in _log:
		print(line)
	print("[pressfeel] frames in %s" % OUT)
	get_tree().quit(0)


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s_pressfeel_%s.png" % [OUT, name])


func _zoom_crop(name: String, region: Rect2i) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# `region` is given in CANVAS coordinates, which are not framebuffer pixels:
	# the stretch canvas is 1600x900 and the backbuffer here came back 1920x1080,
	# so an uncorrected crop lands 20% off and photographs empty ground. That is
	# exactly what the first run produced — a completely black "zoom" frame,
	# which reads identically to an effect that did not render.
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var k: float = float(img.get_width()) / maxf(canvas.x, 1.0)
	var scaled := Rect2i(
		Vector2i(Vector2(region.position) * k), Vector2i(Vector2(region.size) * k))
	var r := scaled.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var crop := img.get_region(r)
	# NEAREST, so a 1px feature stays a hard 4px block and can be counted rather
	# than admired — the same reason _shot_coach_devices zooms.
	crop.resize(r.size.x * 4, r.size.y * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s_pressfeel_%s.png" % [OUT, name])
