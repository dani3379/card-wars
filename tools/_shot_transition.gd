extends Node
# THE TRANSITION BOOKEND (2026-09-11).
#
#   Godot.exe --path "D:\Godot" res://tools/_shot_transition.tscn
#
# The claim is that a screen now OPENS FROM THE POINT THE EXIT CLOSED ON, rather
# than fading up uniformly. That is a claim about WHERE the screen is bright at a
# given moment, so eyeballing it is nearly useless — a half-revealed screen and a
# half-faded screen look much the same in a still.
#
# So it measures. `GameTheme.transition_origin` is set to a deliberately
# off-centre point, `fade_in` is run, and mean luminance is sampled in a disc AT
# the origin versus a disc diagonally opposite. Mid-reveal the origin side must
# be clearly brighter. Under the old flat fade the two are equal BY
# CONSTRUCTION, which is exactly what makes this a real test rather than a
# screenshot to nod at.

const ORIGIN := Vector2(0.22, 0.28)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# A bright, evenly-lit stand-in for "the screen underneath". Using a real
	# scene would let its own art decide which corner is brighter and the
	# measurement would be reading the backdrop, not the wipe.
	# PARENTED TO ROOT, NOT TO THIS NODE. A full-rect preset sizes a Control
	# against its PARENT, and this harness's own root Control has no size — so
	# the stand-in was 0x0, nothing was ever drawn behind the wipe, and the
	# measurement read "dark everywhere" and blamed the shader. Sized from the
	# viewport explicitly so it cannot depend on anyone's layout.
	var bg := ColorRect.new()
	bg.color = Color(0.86, 0.82, 0.74)
	bg.size = get_viewport_rect().size
	bg.position = Vector2.ZERO
	bg.z_index = 0
	get_tree().root.add_child(bg)
	await get_tree().process_frame
	await get_tree().process_frame

	# IDENTIFY THE OVERLAY BY ITS PARAMETER, NOT BY ITS TYPE. The first cut took
	# the last ColorRect-with-a-ShaderMaterial under root — which can be an
	# autoload's own overlay. Its material has no `progress`, so the read came
	# back null, `float(null)` is 0.0, the "wait until part-way" poll exited on
	# its first frame, and the measurement was taken at FULL COVER. It then
	# reported the transition broken when the transition was fine.
	var before := {}
	for c in get_tree().root.get_children():
		before[c.get_instance_id()] = true
	GameTheme.transition_origin = ORIGIN
	GameTheme.fade_in(self, 1.6)
	var mat: ShaderMaterial = null
	var guard := 0
	while mat == null and guard < 600:
		guard += 1
		await get_tree().process_frame
		for c in get_tree().root.get_children():
			if before.has(c.get_instance_id()) or not (c is ColorRect):
				continue
			var m := (c as ColorRect).material as ShaderMaterial
			if m != null and m.get_shader_parameter("progress") != null:
				mat = m
	if mat == null:
		print("SHOT FAIL: no transition overlay")
		get_tree().quit(1)
		return
	print("[t] found overlay: progress=%s invert=%s origin=%s"
		% [str(mat.get_shader_parameter("progress")),
			str(mat.get_shader_parameter("invert")),
			str(mat.get_shader_parameter("origin"))])
	guard = 0
	while float(mat.get_shader_parameter("progress")) > 0.45 and guard < 600:
		guard += 1
		await get_tree().process_frame
	print("[t] sampling at progress=%.3f (waited %d frames)"
		% [float(mat.get_shader_parameter("progress")), guard])

	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://_shot_transition_mid.png")
	var near := _disc(img, ORIGIN)
	var far := _disc(img, Vector2(1.0 - ORIGIN.x, 1.0 - ORIGIN.y))
	print("MID  origin=%.4f  opposite=%.4f  delta=%+.4f" % [near, far, near - far])
	if near > far + 0.05:
		print("TRANSITION OPENS FROM THE ORIGIN")
	else:
		print("TRANSITION FAIL: reveal is not origin-led (flat fade?)")
	print("SHOTS_DONE")
	get_tree().quit()


func _disc(img: Image, uv: Vector2) -> float:
	var cx := int(img.get_width() * uv.x)
	var cy := int(img.get_height() * uv.y)
	var r := 90
	var acc := 0.0
	var n := 0
	for y in range(maxi(cy - r, 0), mini(cy + r, img.get_height()), 3):
		for x in range(maxi(cx - r, 0), mini(cx + r, img.get_width()), 3):
			if Vector2(x - cx, y - cy).length() > float(r):
				continue
			var c := img.get_pixel(x, y)
			acc += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	return acc / maxf(float(n), 1.0)
