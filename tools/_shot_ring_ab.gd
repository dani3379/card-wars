extends Node
## _shot_ring_ab.gd — A/B for the ring engine rebuild (2026-09-09).
##
##   Godot_v4.6.x-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_shot_ring_ab.tscn
##
## Motion.ring was a Line2D circle: a flat stroke, hard-cut on both sides, whose
## apparent width was ~1.7px and CONSTANT (width tweened 3.0 -> 1.05 over exactly
## the span scale grew 0.55 -> 1.6). This shoots the OLD implementation and the
## NEW distance-field band through the same call sites, at the same instants, on
## the real war-table ground, so the comparison is pixels and not opinion.
##
## The old implementation is reproduced here verbatim rather than kept behind a
## flag in Motion.gd — a dead branch in the shipping engine is worse than a copy
## in a harness that exists to delete it.
##
## Outputs tools/screenshot/_ring_{old,new}_t{1,2,3}.png plus a contact sheet
## per implementation, and prints an ink measurement of each frame.

# The war table, sampled from the combat arena plate: everything here has to
# read against THIS, which is why a lone warm hairline was camouflage.
const GROUND := Color(0.118, 0.094, 0.074)

# The three instants worth judging: just after the strike, mid-expansion, and
# the dissipating tail. ALL THREE MUST LAND INSIDE THE SHORTEST DURATION (0.32s
# — the death burst). A tap at 0.34 sat exactly on two cases' tween end and
# sampled whichever side of the free the machine happened to be on, reporting
# 27k lit px one run and 0 the next. That is the harness measuring itself.
const TAPS: Array[float] = [0.05, 0.15, 0.26]

# The real call sites, lifted from Combat/_trigger_fx_ring and the impact kit.
const CASES: Array[Dictionary] = [
	{"name": "spell impact", "col": Color(1.0, 0.55, 0.18, 0.88),
		"radius": 34.0, "end_scale": 1.65, "dur": 0.34, "width": 3.5},
	{"name": "grace wave", "col": Color(0.55, 0.85, 1.0, 0.88),
		"radius": 26.0, "end_scale": 1.65, "dur": 0.34, "width": 3.5},
	{"name": "death burst", "col": Color(1.0, 0.82, 0.34, 0.60),
		"radius": 30.0, "end_scale": 1.5, "dur": 0.32, "width": 2.5},
	{"name": "shock (kit)", "col": Color(1.0, 0.72, 0.28, 0.62),
		"radius": 17.0, "end_scale": 7.05, "dur": 0.44, "width": 5.0},
]

const CELL := Vector2(300.0, 240.0)

var _rows: Array[String] = []


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[ringab] WATCHDOG fired — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1240, 560))
	DisplayServer.window_move_to_foreground()
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true

	for impl in ["old", "new"]:
		for i in TAPS.size():
			await _shoot_sheet(impl, i)

	# The always-on lane-forecast reticle, which hand-rolled its own flat
	# Line2D circle until 2026-09-09 and is the most-looked-at circle in the
	# game because it is never off screen.
	await _shoot_reticle()

	# GRIT: how far the alpha erosion breaks the wake into radial filaments.
	# 0 is the smooth analytic band (clean, reads CG); too high and the ring
	# stops being a ring. Swept so the shipped default is chosen off pixels.
	await _shoot_grit()

	print("")
	print("[ringab] ============ INK PER FRAME ============")
	print("[ringab] lit px = pixels departing the war-table ground; mean dE =")
	print("[ringab] average departure over those px. A hairline scores few lit")
	print("[ringab] px AND a low mean: it is thin and it is dim.")
	for r in _rows:
		print("[ringab] %s" % r)
	print("[ringab] DONE")
	get_tree().quit(0)


## One contact sheet: all four cases, one implementation, sampled at TAPS[ti].
func _shoot_sheet(impl: String, ti: float) -> void:
	var tap: float = TAPS[int(ti)]
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)

	var bg := ColorRect.new()
	bg.color = GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var font := ThemeDB.fallback_font
	for ci in CASES.size():
		var c: Dictionary = CASES[ci]
		var centre := Vector2(170.0 + float(ci) * CELL.x, 250.0)
		var lab := Label.new()
		lab.text = "%s  ·  %s  ·  t=%.2fs" % [String(c["name"]), impl.to_upper(), tap]
		lab.add_theme_font_override("font", font)
		lab.add_theme_font_size_override("font_size", 15)
		lab.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
		lab.position = Vector2(centre.x - 140.0, 60.0)
		host.add_child(lab)

		var opts := {
			"radius": float(c["radius"]), "end_scale": float(c["end_scale"]),
			"duration": float(c["dur"]), "width": float(c["width"]),
			"width_end": maxf(1.0, float(c["width"]) * 0.35),
			"start_scale": 0.55, "z_index": 50,
		}
		if impl == "old":
			_ring_legacy(host, centre, c["col"], opts)
		else:
			Motion.ring(host, centre, c["col"], opts)

	await get_tree().create_timer(tap).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var p := "res://tools/screenshot/_ring_%s_t%d.png" % [impl, int(ti) + 1]
	img.save_png(p)
	_measure(img, "%s t=%.2fs" % [impl.to_upper(), tap])
	print("[ringab] SAVED %s" % p.get_file())
	host.queue_free()
	await get_tree().create_timer(0.25).timeout


## One row of the spell-impact ring at five grit values, sampled mid-flight.
func _shoot_grit() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	var font := ThemeDB.fallback_font
	var vals: Array[float] = [0.0, 0.35, 0.55, 0.75, 1.0]
	for i in vals.size():
		var g: float = vals[i]
		var centre := Vector2(150.0 + float(i) * 230.0, 270.0)
		var lab := Label.new()
		lab.text = "grit %.2f" % g
		lab.add_theme_font_override("font", font)
		lab.add_theme_font_size_override("font_size", 15)
		lab.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
		lab.position = Vector2(centre.x - 40.0, 60.0)
		host.add_child(lab)
		Motion.ring(host, centre, Color(1.0, 0.55, 0.18, 0.88), {
			"radius": 34.0, "end_scale": 1.65, "duration": 0.34,
			"width": 3.5, "width_end": 1.2, "start_scale": 0.55,
			"z_index": 50, "grit": g,
		})

	await get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_ring_grit.png")
	print("[ringab] SAVED _ring_grit.png")
	host.queue_free()
	await get_tree().create_timer(0.25).timeout


## The forecast reticle, old beside new, held (it does not animate).
func _shoot_reticle() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)

	# The two live radii and the real danger tint from _add_lane_forecast_target_ring.
	var danger := Color(0.92, 0.32, 0.22, 0.60)
	var col := Color(danger.r, danger.g, danger.b, minf(danger.a + 0.12, 0.72))
	var font := ThemeDB.fallback_font
	var i := 0
	for spec in [{"r": 50.0, "t": "body strike (r50)"},
			{"r": 34.0, "t": "face strike (r34)"}]:
		for impl in ["OLD", "NEW"]:
			var centre := Vector2(210.0 + float(i) * 290.0, 260.0)
			var lab := Label.new()
			lab.text = "%s · %s" % [String(spec["t"]), impl]
			lab.add_theme_font_override("font", font)
			lab.add_theme_font_size_override("font_size", 15)
			lab.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
			lab.position = Vector2(centre.x - 110.0, 60.0)
			host.add_child(lab)
			if impl == "OLD":
				_reticle_legacy(host, centre, col, float(spec["r"]))
			else:
				Motion.ring_static(host, centre, col,
					{"radius": float(spec["r"]), "width": 2.5, "z_index": 50})
			_reticle_cross(host, centre, danger, float(spec["r"]))
			i += 1

	await get_tree().create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_ring_reticle.png")
	print("[ringab] SAVED _ring_reticle.png")
	host.queue_free()


func _reticle_legacy(host: Node, centre: Vector2, col: Color, radius: float) -> void:
	var ring := Line2D.new()
	ring.width = 2.5
	ring.antialiased = true
	ring.z_index = 50
	ring.default_color = col
	var pts := PackedVector2Array()
	for k in range(41):
		var a := TAU * float(k) / 40.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	ring.points = pts
	ring.position = centre
	host.add_child(ring)


## The crosshair is unchanged by the rebuild; drawn here so each cell is the
## whole mark and not half of it.
func _reticle_cross(host: Node, centre: Vector2, danger: Color,
		radius: float) -> void:
	var cross := Line2D.new()
	cross.width = 2.0
	cross.antialiased = true
	cross.z_index = 51
	cross.default_color = Color(danger.r, danger.g, danger.b, 0.42)
	cross.points = PackedVector2Array([
		Vector2(-radius * 0.54, 0), Vector2(radius * 0.54, 0),
		Vector2(0, 0),
		Vector2(0, -radius * 0.54), Vector2(0, radius * 0.54),
	])
	cross.position = centre
	host.add_child(cross)


## Count pixels that depart the ground, and by how much. This is the whole
## argument in two numbers: a hairline lights few pixels and lights them faintly.
func _measure(img: Image, tag: String) -> void:
	var lit := 0
	var acc := 0.0
	var peak := 0.0
	# Skip the caption band so label ink never enters the measurement.
	for y in range(120, img.get_height()):
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var d: float = absf(c.r - GROUND.r) + absf(c.g - GROUND.g) \
				+ absf(c.b - GROUND.b)
			if d > 0.05:
				lit += 1
				acc += d
				peak = maxf(peak, d)
	var mean: float = acc / maxf(float(lit), 1.0)
	_rows.append("%-16s lit px %6d   mean dE %.3f   peak dE %.3f"
		% [tag, lit, mean, peak])


## ── The Line2D circle, as it stood before 2026-09-09 ──────────────────
func _ring_legacy(host: Node, center: Vector2, color: Color,
		opts: Dictionary) -> void:
	var radius: float = float(opts.get("radius", 16.0))
	var dur: float = float(opts.get("duration", 0.42))
	var width: float = float(opts.get("width", 3.0))
	var width_end: float = float(opts.get("width_end", 0.0))
	var oval: Vector2 = opts.get("oval", Vector2.ONE)
	var rg := Line2D.new()
	rg.width = width
	rg.antialiased = true
	rg.z_index = int(opts.get("z_index", 0))
	rg.default_color = color
	var pts := PackedVector2Array()
	for i in range(49):
		var a := TAU * float(i) / 48.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	rg.points = pts
	rg.position = center
	rg.scale = oval * float(opts.get("start_scale", 0.55))
	host.add_child(rg)
	var tw := rg.create_tween()
	var sc := tw.tween_property(rg, "scale",
		oval * float(opts.get("end_scale", 1.6)), dur).set_ease(Tween.EASE_OUT)
	if opts.has("trans"):
		sc.set_trans(opts["trans"])
	if width_end > 0.0:
		tw.parallel().tween_property(rg, "width", width_end, dur) \
			.set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(rg, "modulate:a", 0.0, dur) \
		.set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(rg.queue_free)
