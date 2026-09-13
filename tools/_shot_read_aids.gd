extends Node
## _shot_read_aids.gd — eyes on the three combat READ-AIDS (2026-09-12).
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" res://tools/_shot_read_aids.tscn
##
## WHY IT EXISTS. The telegraph arrow (hover a creature to read its next
## attack), the sniper's aim thread (a standing order) and the lane forecast's
## breakthrough chevrons were all untextured `Line2D`s — flat hairlines laid
## over the war table. They are the most-looked-at strokes in the game, because
## unlike a spell beat they are on screen for as long as the player is thinking.
##
## THE ORACLE IS THE FALLOFF, and that is the point of doing it this way. Every
## pixel test tried against the FX work this session failed for the same reason
## — a hue detector aimed at a white core, a brightness threshold below the
## table's own value, a sample slower than the effect. So this asserts the one
## property that DEFINES the defect and cannot be faked by the background:
##
##     A Line2D paints every pixel across its width at the same alpha.
##     A textured beam has a bright core that falls off to its shoulders.
##
## Take a cross-section perpendicular to the stroke and the flat one is a
## plateau while the beam is a peak. That is a structural claim about the
## technique, it needs no taste, and a regression to a flat stroke breaks it
## immediately.
##
## The beams are staged here rather than driven through a real hover, because a
## booted Combat moves: the board's idle bob is +/-3px forever, which already
## defeated one size assertion this session. Construction is what changed, so
## construction is what is measured; that Combat still only writes `.points`
## and `.visible` afterwards is checked by reading it, and by parsecheck.

const AIM_COLOR := Color(0.55, 0.85, 0.95)

var _fail := 0
var _rows: Array = []


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[read-aids] WATCHDOG fired")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1100, 560))
	DisplayServer.window_move_to_foreground()
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0

	# The dark war table these are drawn on. A pale beam tested on grey would
	# pass here and vanish in the game.
	var bg := ColorRect.new()
	bg.color = Color(0.118, 0.094, 0.074)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var host := Node2D.new()
	add_child(host)

	# Each entry mirrors the construction in Combat.gd, one per read-aid. They
	# are drawn as horizontal runs so a vertical column IS the cross-section.
	var danger := Color(1.0, 0.28, 0.18, 0.80)   # the LETHAL forecast colour
	_stage(host, "telegraph", 90.0,
		Motion.beam_line(PackedVector2Array(),
			Color(0.96, 0.50, 0.22, 0.92), 13.0, "comet", 0.62))
	_stage(host, "aim thread", 190.0,
		Motion.beam_line(PackedVector2Array(),
			Color(AIM_COLOR.r, AIM_COLOR.g, AIM_COLOR.b, 0.72), 8.0,
			"comet", 0.50, "", AIM_COLOR.lightened(0.60)))
	_stage(host, "chevron (lethal)", 290.0,
		Motion.beam_line(PackedVector2Array(), danger, 13.5,
			"streak", 0.78, "", danger.lightened(0.82)))
	# The two that the WIDTH EXEMPTION hid: a stroke of 7px or more was assumed
	# to read as a shape, which is true for a draw_line used as a bar and false
	# for a Line2D. These are the most-looked-at strokes in the game.
	_stage(host, "targeting arrow", 390.0,
		Motion.beam_line(PackedVector2Array(),
			Color(1.0, 0.62, 0.22, 0.98), 22.0, "comet", 0.90, "comet"))
	_stage(host, "drag trail", 490.0,
		Motion.beam_line(PackedVector2Array(),
			Color(1.0, 0.74, 0.30, 0.50), 30.0, "trail", 0.45, "comet"))
	# THE CONTROL — the construction that was removed, staged on purpose so the
	# threshold above has something that must fail it. Same colour and a width
	# in the range the old chevrons used.
	var flat := Line2D.new()
	flat.width = 3.6
	flat.antialiased = true
	flat.default_color = Color(danger.r, danger.g, danger.b, 0.80)
	_stage(host, "CONTROL flat Line2D", 590.0, flat)

	# THE EMBER, old construction beside new. Card2D's fuse cord drew its lit
	# head as three concentric FILLED discs at descending alpha — a falloff in
	# three jumps, so its disc boundaries read as rings on the one thing in the
	# frame meant to be a burning coal. Both are drawn here at the SHIPPED size,
	# because banding is a function of radius and a comparison at a flattering
	# scale proves nothing.
	var ember := Control.new()
	ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ember.position = Vector2.ZERO
	ember.size = Vector2(1600.0, 900.0)
	ember.draw.connect(func() -> void:
		var o := Vector2(330.0, 730.0)
		ember.draw_circle(o, 13.0, Color(1.0, 0.45, 0.10, 0.26), true, -1.0, true)
		ember.draw_circle(o, 7.5, Color(1.0, 0.62, 0.16, 0.65), true, -1.0, true)
		ember.draw_circle(o, 4.0, Color(1.0, 0.93, 0.58, 1.0), true, -1.0, true)
		Motion.draw_glow(ember, Vector2(760.0, 730.0), 15.0,
			Color(1.0, 0.52, 0.16, 0.97), 0.34, 1.15))
	add_child(ember)

	# THE SLABS. A ColorRect used as light has four hard edges; `soft_rect_material`
	# feathers them. Three panels, and the THIRD is the one that matters: it is
	# the same feathered material at HALF the node's `color.a`, which proves the
	# shader still answers the node's own colour. That claim is load-bearing —
	# `beam_material` writes COLOR outright and has silently killed three
	# `modulate`/`color:a` tweens in this codebase, so a primitive built the same
	# way would break the very fades it was added to improve.
	var slab_y := 790.0
	for si in 3:
		var sl := ColorRect.new()
		sl.position = Vector2(230.0 + float(si) * 260.0, slab_y)
		sl.size = Vector2(190.0, 76.0)
		sl.color = Color(1.0, 0.86, 0.44, 0.60 if si < 2 else 0.30)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if si > 0:
			sl.material = Motion.soft_rect_material(Vector2(0.46, 0.14))
		add_child(sl)

	var font := ThemeDB.fallback_font
	for r in _rows:
		var lbl := Label.new()
		lbl.text = String(r["name"]).to_upper()
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.74, 0.70, 0.62))
		lbl.position = Vector2(60.0, float(r["y"]) - 58.0)
		add_child(lbl)

	await get_tree().create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_read_aids.png")
	print("[read-aids] SAVED _read_aids.png")

	# THE CAPTURE IS NOT IN THE COORDINATES YOU STAGED IN. `get_image()` returns
	# the VIEWPORT's backing texture, which here came back 1920x1080 against a
	# 1600x900 project canvas and a window I had asked for at 1100x560 — so
	# every hardcoded sample row landed in empty table. Two of three rows
	# reported "invisible" and one PASSED by catching the edge of its stroke at
	# the very bottom of its search band, which is the worst of the three
	# outcomes: a fluke green. Derive the factor, never assume it.
	var scale: float = float(img.get_width()) \
		/ maxf(get_viewport().get_visible_rect().size.x, 1.0)
	print("[read-aids] capture %dx%d · canvas %.0fx%.0f · scale %.3f"
		% [img.get_width(), img.get_height(),
			get_viewport().get_visible_rect().size.x,
			get_viewport().get_visible_rect().size.y, scale])
	for r in _rows:
		_assert_falloff(img, String(r["name"]), int(r["y"]), scale)

	# THE EMBER TEST IS RELATIONAL, and deliberately so. An absolute "max step
	# must be under X" threshold is a number I would pick AFTER seeing the
	# result, i.e. tuned until it passes — which is how a gate becomes
	# decoration. Requiring the new construction to be materially smoother than
	# the old one needs no chosen constant and cannot be satisfied by tuning.
	var step_old := _radial_max_step(img, Vector2(330.0, 730.0), 13.0, scale)
	var step_new := _radial_max_step(img, Vector2(760.0, 730.0), 15.0, scale)
	print("[read-aids] ember max radial KINK — 3-disc %.3f · draw_glow %.3f"
		% [step_old, step_new])
	_check(step_new < step_old * 0.6,
		"draw_glow is materially smoother than the 3-disc stack (%.3f vs %.3f)"
			% [step_new, step_old])

	# Horizontal profile ACROSS each slab: the bare one is a plateau with two
	# cliffs, the feathered ones ramp in from both sides.
	var p_bare := _slab_profile(img, 230.0, 190.0, 828.0, scale)
	var p_soft := _slab_profile(img, 490.0, 190.0, 828.0, scale)
	var p_half := _slab_profile(img, 750.0, 190.0, 828.0, scale)
	print("[read-aids] slab edge-ramp px (of 190 wide) — bare %d · soft %d · soft@half-alpha %d"
		% [p_bare["ramp"], p_soft["ramp"], p_half["ramp"]])
	print("[read-aids] slab peak lift — bare %.3f · soft %.3f · soft@half-alpha %.3f"
		% [p_bare["lift"], p_soft["lift"], p_half["lift"]])
	_check(p_soft["ramp"] > p_bare["ramp"] * 4,
		"the feathered slab ramps in over many px; the bare one cliffs (%d vs %d)"
			% [p_soft["ramp"], p_bare["ramp"]])
	# THE TRAP CHECK. Halving the node's `color.a` must halve what is drawn. If
	# the shader ignored the node's colour this would read as no change at all,
	# and every `color:a` fade in Combat would have died silently.
	_check(p_half["lift"] < p_soft["lift"] * 0.75,
		"the node's own color.a still drives the feathered slab (%.3f vs %.3f)"
			% [p_half["lift"], p_soft["lift"]])

	print("[read-aids] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _stage(host: Node2D, name: String, y: float, beam: Line2D) -> void:
	# A long horizontal run. "comet" ramps alpha along the length, so the
	# cross-section is taken near the HEAD where the stroke is at full weight —
	# sampling the tail would measure the ramp and call a correct beam faint.
	beam.points = PackedVector2Array([Vector2(190.0, y), Vector2(940.0, y)])
	host.add_child(beam)
	_rows.append({"name": name, "y": y})


## The cross-section test, second cut. THE FIRST ONE WAS VACUOUS and its own
## numbers said so: it compared the peak against a fixed 7px shoulder and
## reported ratios of 15,000, which is not a falloff measurement — the shoulder
## had simply landed on bare table. A flat 2px hairline scores exactly the same
## way (bright centre, nothing 7px out), so the test could not tell a beam from
## the wire it replaced. A number that absurd is never a strong pass; it means
## the denominator has gone to zero and the quantity is not the one named.
##
## What actually separates them is the SHAPE of the profile, so measure it:
##   w50 — rows at or above half the peak's lift over the table (the core)
##   w10 — rows at or above a tenth of it              (core + shoulders)
## A flat stroke is a plateau with a cliff: it is either on or off, so w10 and
## w50 are nearly the same and the ratio sits near 1. A textured beam spends
## most of its width in the falloff, so w10 runs well past w50.
##
## The CONTROL row below is what makes this believable. It stages a plain
## untextured Line2D — the exact construction that was removed — and requires it
## to FAIL the same threshold the beams must pass. An oracle that cannot fail is
## not an oracle, and this session has already shipped four that could not.
## ONE CROSS-SECTION IS NO LONGER A MEASUREMENT. Since the beams carry
## lost-and-found edges, the falloff VARIES along the run by design — so a
## single sample reads whatever passage it happened to land in, and a future
## change that flattened part of a stroke could pass or fail purely on where
## the probe looked. Sample several points and gate on the WORST; the spread
## between them is also the only direct evidence the technique is doing
## anything, so it is printed.
func _assert_falloff(img: Image, name: String, y: int, scale: float) -> void:
	var lo := 99.0
	var hi := 0.0
	var worst := {}
	for frac in [0.45, 0.60, 0.75, 0.88]:
		var sx: float = 190.0 + (940.0 - 190.0) * float(frac)
		var r := _falloff_at(img, int(sx * scale), y, scale)
		if r.is_empty():
			continue
		var pr: float = float(r["profile"])
		if pr < lo:
			lo = pr
			worst = r
		hi = maxf(hi, pr)
	if worst.is_empty():
		_check(false, "%s renders at all" % name)
		return
	print("[read-aids] %-20s lift %.3f · w50 %2dpx · w10 %2dpx · profile %.2f"
		% [name, float(worst["lift"]), int(worst["w50"]), int(worst["w10"]), lo]
		+ "  (worst of 4; softest %.2f)" % hi)
	_check(float(worst["lift"]) > 0.08,
		"%s lifts off the table (%.3f)" % [name, float(worst["lift"])])
	if name.begins_with("CONTROL"):
		_check(lo < 1.8,
			"%s (a plain Line2D) is a PLATEAU — profile %.2f, so the test can fail"
				% [name, lo])
	else:
		_check(lo >= 1.8,
			"%s spends its width in FALLOFF at EVERY sample (worst %.2f)"
				% [name, lo])


## The cross-section at one x. Returns {} when nothing is drawn there.
func _falloff_at(img: Image, x: int, y: int, scale: float) -> Dictionary:
	var cy := int(float(y) * scale)
	var band := int(26.0 * scale)
	var peak := 0.0
	var peak_y := cy
	for dy in range(-band, band + 1):
		var sy: int = clampi(cy + dy, 0, img.get_height() - 1)
		var p: Color = img.get_pixel(x, sy)
		var v: float = p.r + p.g + p.b
		if v > peak:
			peak = v
			peak_y = sy
	# The bare table well outside the stroke — the floor everything is measured
	# against (0.286 on this background).
	var far: Color = img.get_pixel(x, clampi(peak_y + int(34.0 * scale),
		0, img.get_height() - 1))
	var table: float = far.r + far.g + far.b
	var lift: float = peak - table
	if lift <= 0.0001:
		return {}

	var w50 := 0
	var w10 := 0
	for dy in range(-band, band + 1):
		var sy: int = clampi(cy + dy, 0, img.get_height() - 1)
		var p: Color = img.get_pixel(x, sy)
		var rel: float = (p.r + p.g + p.b - table) / lift
		if rel >= 0.50:
			w50 += 1
		if rel >= 0.10:
			w10 += 1
	# 1.8 is the floor the caller gates on, modest on purpose: the claim is
	# "this has a profile", not "this is dramatic" — these are READ-AIDS, and
	# Into the Breach's rule applies, clarity before spectacle. The flat
	# Line2D control scores 1.00 and establishes that the test can fail.
	return {
		"lift": lift, "w50": w50, "w10": w10,
		"profile": float(w10) / maxf(float(w50), 1.0),
	}


## The sharpest KINK in a radial profile, as a fraction of the glow's lift.
##
## THE FIRST METRIC HERE WAS WRONG and its failure is worth keeping: it took the
## largest adjacent-pixel STEP, which measures STEEPNESS, not banding. A smooth
## glow with a tight core has big adjacent differences near the centre for an
## entirely correct reason, so it scored 0.206 against the 3-disc stack's 0.265
## and the test reported a real improvement as a failure.
##
## What the eye reads as a band is a DISCONTINUITY — the slope changing abruptly
## at a disc's edge — and the discrete second difference is exactly that. A
## smooth falloff of any steepness has a gently varying slope and scores low;
## a stack of filled discs kinks hard at every boundary.
func _radial_max_step(img: Image, centre: Vector2, radius: float,
		scale: float) -> float:
	var cx := int(centre.x * scale)
	var cy := int(centre.y * scale)
	var n := int(radius * scale) + 6
	var prof: Array[float] = []
	for r in range(n):
		var x: int = clampi(cx + r, 0, img.get_width() - 1)
		var p: Color = img.get_pixel(x, clampi(cy, 0, img.get_height() - 1))
		prof.append(p.r + p.g + p.b)
	if prof.size() < 4:
		return 0.0
	var lift: float = prof[0] - prof[prof.size() - 1]
	if lift <= 0.01:
		return 0.0
	var worst := 0.0
	for i in range(1, prof.size() - 1):
		var kink: float = absf(prof[i - 1] - 2.0 * prof[i] + prof[i + 1])
		worst = maxf(worst, kink / lift)
	return worst


## Walk a horizontal line across a slab and report how many pixels it takes to
## climb from the table to 90% of its peak, plus that peak's lift. A bare
## ColorRect cliffs in one or two pixels; a feathered one ramps.
func _slab_profile(img: Image, x0: float, w: float, y: float,
		scale: float) -> Dictionary:
	var sy := clampi(int(y * scale), 0, img.get_height() - 1)
	var ax := int(x0 * scale)
	var aw := int(w * scale)
	var vals: Array[float] = []
	for i in range(aw):
		var p: Color = img.get_pixel(clampi(ax + i, 0, img.get_width() - 1), sy)
		vals.append(p.r + p.g + p.b)
	# Table = just outside the slab's left edge.
	var far: Color = img.get_pixel(clampi(ax - int(14.0 * scale), 0,
		img.get_width() - 1), sy)
	var table: float = far.r + far.g + far.b
	var peak := table
	for v in vals:
		peak = maxf(peak, v)
	var lift: float = peak - table
	if lift <= 0.001:
		return {"ramp": 0, "lift": 0.0}
	var ramp := 0
	for v in vals:
		if (v - table) / lift < 0.90:
			ramp += 1
		else:
			break
	return {"ramp": ramp, "lift": lift}


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print("[read-aids] %s  %s" % ["PASS" if ok else "FAIL", what])
