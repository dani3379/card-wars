extends Node
## _shot_layerstyle_light.gd — WHICH WAY IS THE LAMP? (2026-09-17)
##
##   Godot_v4.6.2-stable_win64.exe --path "D:\Godot" \
##       res://tools/_shot_layerstyle_light.tscn
##
## WHY THIS EXISTS. `LayerStyle.LIGHT_A = PI * 1.25` is an up-left lamp, and
## `drop_shadow` agrees with it — it offsets by `-light_vec()`, down-right, and a
## shadow cast down-right can only come from a light up-left. But `bevel` lit its
## edges on `outn.dot(-lv)` and `shine` cut its chord on the `-lv` side, so two of
## the directional passes lit the BOTTOM-RIGHT while the drop shadow and
## `fill_graded` lit the top-left. The file's own header names that defect — "two
## lit objects side by side under different suns is the single most reliable way
## to make a UI look assembled rather than designed" — and it was happening
## INSIDE a single object.
##
## THE CONSUMERS ARE SMALL MARKS, which is why it survived. A 4px bracket arm and
## a 40px wax seal both carry the error at a size where "the rim is lit on the
## wrong side" photographs as "the rim is a bit noisy". So this draws the same
## passes at 90px radius, where a bevel has room to be visibly wrong — and then
## does not trust the eye either.
##
## THE ORACLE IS AN OCTANT SWEEP. For each shape it samples an annulus across the
## silhouette (0.82-1.06 of the radius), bins every sample by angle into the
## eight compass octants, and prints mean luminance per octant. The lamp sits at
## `light_vec()` = (-0.707, -0.707), which in y-down screen space is NW, so the
## expected answer is a number rather than a taste.
##
## EACH PASS IS ISOLATED ON ITS OWN SHAPE, because two of them were inverted and
## a full-stack-only test cannot tell you whether you fixed one, the other, or
## both in opposite directions.
##
## THE VERDICT IS THE NW/SE RATIO, NOT THE BRIGHTEST OCTANT. An earlier cut
## gated on "the brightest octant must be the lamp's" and called `fill_graded`
## and `drop_shadow` inverted when they are not: both are soft, wide passes whose
## peak wanders a neighbouring octant under a wobbled silhouette, while their
## NW/SE ratio sat correctly above 1. A ratio across the lamp axis is the signal;
## an argmax over eight noisy bins is not.
##
## NOT EVERY PASS IS GATED, and the expectation is stated per case:
##   * bevel / shine / full stack -> LAMP. These live on the rim, which is what
##     the annulus samples, so they are held to NW/SE > 1.15.
##   * inner_shadow -> OPPOSITE. Photoshop's inner shadow darkens the lamp-side
##     inner rim; that is what makes a shape read as INSET, and it is correct for
##     WoundSeal's stamped recess. Held to NW/SE < 0.87. Flipping it would change
##     what the effect MEANS, not fix a bug.
##   * fill_graded / drop_shadow -> REPORTED, not gated. `fill_graded`'s lift
##     lives in the interior and `drop_shadow`'s darkening lands OUTSIDE the
##     silhouette, so a rim annulus is simply the wrong probe for either. They
##     are drawn and printed because a regression in them should be visible in
##     the frame, but this harness does not pretend to measure them.

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

## The war table, sampled from the combat arena plate — the ground these marks
## actually have to read against (the constant `_shot_ring_ab` uses).
const GROUND := Color(0.118, 0.094, 0.074)

const SHOT_DIR := "res://tools/screenshot/layerstyle"

## StruckBracket's amber and WoundSeal's oxblood, so the measurement runs on the
## two hues that ship rather than on white.
const AMBER := Color(0.98, 0.72, 0.32)
const WAX := Color(0.510, 0.137, 0.106)

## RENDERED INTO A SUBVIEWPORT OF EXACTLY THIS SIZE, and that is not incidental.
## The first cut of this harness drew onto a full-rect Control over the root
## viewport and then sampled `get_viewport().get_texture().get_image()` at canvas
## coordinates. Those are NOT the same space: the project stretches
## `canvas_items`, so a shape drawn at canvas (180, 180) landed at image (215,
## 200) — a uniform ~1.19x — and whole octants sampled either deep inside the
## flat fill or on bare ground. The giveaway was arithmetic: octants reading
## exactly 0.098 (GROUND's luminance) and exactly 0.747 (flat AMBER's), rather
## than the mix of rim and ground a correctly centred annulus must produce. It
## also reported `fill_graded` and `drop_shadow` as inverted, which they are not.
## A SubViewport of a fixed size makes image pixel == canvas pixel by
## construction, so the oracle cannot be lied to by a window setting again.
const VIEW := Vector2i(1240, 620)

const R := 90.0

## A NARROW band hugging the silhouette. The first cut swept 0.82-1.06 of the
## radius, which on a 90px blob is a 21px-deep annulus — mostly flat interior
## fill, so a 2px rim's contribution was averaged down toward nothing (bevel
## still showed, at a diluted 0.69). The rim passes live within a few px of the
## outline; sample there and nowhere else.
const RIM_LO := 0.94
const RIM_HI := 1.03

## Ratio thresholds across the lamp axis. Deliberately not 1.0 — a wobbled
## silhouette and a hand-seeded blob put a few percent of noise on every bin, so
## a verdict that triggers at 1.01 is reporting the wobble.
const GATE_LIT := 1.15
const GATE_INSET := 0.87
## Typed on purpose: an untyped Array const makes `OCT[i]` a Variant, and `:=`
## then refuses to infer ("Cannot infer the type of ... the value doesn't have a
## set type"). Typing the constant is cheaper than casting at every use.
const OCT: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

var _lamp := ""
var _canvas: Canvas = null
var _sub: SubViewport = null
var _problems: Array[String] = []
var _cases: Array[Dictionary] = []


class Canvas extends Control:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[ls] WATCHDOG — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1240, 620))
		DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	var lv := LayerStyle.light_vec()
	_lamp = OCT[_bin(rad_to_deg(atan2(lv.y, lv.x)))]
	print("[ls] LIGHT_A=%.4f rad  light_vec=(%.3f, %.3f)  -> lamp octant %s"
		% [LayerStyle.LIGHT_A, lv.x, lv.y, _lamp])

	var opp: String = OCT[_bin(rad_to_deg(atan2(-lv.y, -lv.x)))]
	print("[ls] gate: rim passes need NW/SE > %.2f; an inset needs < %.2f"
		% [GATE_LIT, GATE_INSET])
	_cases = [
		{"name": "bevel only", "at": Vector2(180, 180), "col": AMBER,
			"mode": "bevel", "gate": "lamp"},
		{"name": "shine only", "at": Vector2(450, 180), "col": AMBER,
			"mode": "shine", "gate": "lamp"},
		{"name": "full stack amber", "at": Vector2(720, 180), "col": AMBER,
			"mode": "full", "gate": "lamp"},
		{"name": "full stack wax", "at": Vector2(990, 180), "col": WAX,
			"mode": "full", "gate": "lamp"},
		{"name": "graded fill only", "at": Vector2(180, 430), "col": AMBER,
			"mode": "grade", "gate": "report"},
		{"name": "drop shadow only", "at": Vector2(450, 430), "col": AMBER,
			"mode": "drop", "gate": "report"},
		{"name": "inner shadow only", "at": Vector2(720, 430), "col": AMBER,
			"mode": "inner", "gate": "inset"},
	]
	var _unused := opp

	_sub = SubViewport.new()
	_sub.size = VIEW
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The marks are judged on their own drawn pixels; a viewport MSAA or a
	# post-process would be measuring the compositor's opinion of them.
	_sub.msaa_2d = Viewport.MSAA_DISABLED

	_canvas = Canvas.new()
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(VIEW)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.painter = _paint
	_sub.add_child(_canvas)

	# Shown as well as measured, so the window is not a black rectangle while the
	# harness runs and the saved PNG matches what a human would have seen.
	var holder := SubViewportContainer.new()
	holder.position = Vector2.ZERO
	holder.size = Vector2(VIEW)
	holder.add_child(_sub)
	get_tree().root.add_child(holder)
	_canvas.queue_redraw()

	await get_tree().process_frame
	await get_tree().process_frame
	if headless:
		print("[ls] headless — no framebuffer to measure, oracle skipped")
		print("[ls] LAYERSTYLE_LIGHT_DONE")
		get_tree().quit()
		return

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = _sub.get_texture().get_image()
	# THE SPACE CHECK, not a comment claiming it. If the grab is ever not the
	# size drawn into, every octant below is measuring the wrong pixels.
	if img.get_size() != VIEW:
		_problems.append("grab is %s but canvas is %s — oracle space is broken"
			% [str(img.get_size()), str(VIEW)])
		print("[ls] ABORT — grab %s != canvas %s" % [str(img.get_size()), str(VIEW)])
		print("[ls] LAYERSTYLE_LIGHT_DONE_WITH_FINDINGS")
		get_tree().quit(1)
		return
	img.save_png("%s/board.png" % SHOT_DIR)
	print("[ls] SAVED board.png %s" % str(img.get_size()))

	for c in _cases:
		_measure(img, c)

	_zoom(img, Vector2i(180, 180), "zoom_bevel")
	_zoom(img, Vector2i(720, 180), "zoom_full_amber")
	_zoom(img, Vector2i(990, 180), "zoom_full_wax")

	if _problems.is_empty():
		print("[ls] every directional pass agrees with the lamp")
		print("[ls] LAYERSTYLE_LIGHT_DONE")
	else:
		for p in _problems:
			print("[ls] PROBLEM: ", p)
		print("[ls] LAYERSTYLE_LIGHT_DONE_WITH_FINDINGS")
	get_tree().quit()


# -- painting ---------------------------------------------------------------

func _paint(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, _canvas.size), GROUND, true)
	for c in _cases:
		var cen: Vector2 = c["at"]
		var col: Color = c["col"]
		var mode: String = c["mode"]
		var nm: String = c["name"]
		var poly := _blob(cen, R)
		match mode:
			"bevel":
				ci.draw_colored_polygon(poly, col)
				LayerStyle.bevel(ci, poly, col, 7.0, 1.0)
			"shine":
				ci.draw_colored_polygon(poly, col)
				LayerStyle.shine(ci, poly, 0.42, 0.55)
			"inner":
				ci.draw_colored_polygon(poly, col)
				LayerStyle.inner_shadow(ci, poly, 12.0, 0.70)
			"grade":
				LayerStyle.fill_graded(ci, poly, col, 0.40, 5)
			"drop":
				LayerStyle.drop_shadow(ci, poly, 9.0, 6.0, 0.80)
				ci.draw_colored_polygon(poly, col)
			"full":
				LayerStyle.draw_shape(ci, poly, col, {
					"shadow": true, "shadow_dist": 4.0, "shadow_spread": 4.0,
					"glow": col.lightened(0.20),
					"glow_size": 16.0, "glow_alpha": 0.18,
					"lift": 0.22, "shine": 0.30,
					"inner_shadow": 0.40,
					"bevel": 0.95, "bevel_depth": 7.0,
				})
		if GameTheme.font_body != null:
			ci.draw_string(GameTheme.font_body, cen + Vector2(-120.0, R + 36.0),
				nm, HORIZONTAL_ALIGNMENT_CENTER, 240.0, 17,
				Color(0.86, 0.82, 0.76))


## A low-harmonic wobbled circle — WoundSeal._blob's construction with a fixed
## phase, so the silhouette is wax rather than a perfect disc but is identical
## every run (an oracle that re-rolls its own subject measures noise).
func _blob(c: Vector2, base_r: float, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + 0.030 * sin(a * 3.0 + 0.7) + 0.018 * sin(a * 7.0 + 2.1)
		pts.append(c + Vector2(cos(a), sin(a)) * base_r * w)
	return pts


# -- the oracle -------------------------------------------------------------

func _bin(deg: float) -> int:
	return int(fposmod(deg + 22.5, 360.0) / 45.0) % 8


## Mean luminance of the rim, per compass octant. Sampled across an annulus
## rather than on one radius because the rim passes land a few px inboard of the
## outline and a single-radius ring can miss them entirely.
func _measure(img: Image, cs: Dictionary) -> void:
	var cen: Vector2 = cs["at"]
	var nm: String = cs["name"]
	var gate: String = cs["gate"]
	var sums := PackedFloat32Array()
	var counts := PackedInt32Array()
	for i in range(8):
		sums.append(0.0)
		counts.append(0)
	# THE STRADDLE COUNTERS. A correctly centred annulus crosses the silhouette,
	# so it must contain BOTH bare ground and ink. All-ground means the sweep
	# missed the shape; all-ink means it is sampling deep inside the fill. Either
	# way the octant numbers are meaningless, and that is exactly how the first
	# cut of this harness produced six confident false findings.
	var ground_lum := 0.2126 * GROUND.r + 0.7152 * GROUND.g + 0.0722 * GROUND.b
	var ground_n := 0
	var total_n := 0
	for ri in range(25):
		var rr: float = R * (RIM_LO + (RIM_HI - RIM_LO) * float(ri) / 24.0)
		for ai in range(720):
			var deg := 0.5 * float(ai)
			var p := cen + Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * rr
			var x := int(round(p.x))
			var y := int(round(p.y))
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var col := img.get_pixel(x, y)
			var b := _bin(deg)
			var lum := 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
			sums[b] += lum
			counts[b] += 1
			total_n += 1
			if absf(lum - ground_lum) < 0.004:
				ground_n += 1
	var parts: Array[String] = []
	var best := -1.0
	var best_name := "?"
	var vals: Dictionary = {}
	for i in range(8):
		var m: float = (sums[i] / float(counts[i])) if counts[i] > 0 else 0.0
		vals[OCT[i]] = m
		parts.append("%s %.3f" % [OCT[i], m])
		if m > best:
			best = m
			best_name = OCT[i]
	var nw: float = float(vals.get("NW", 0.0))
	var se: float = float(vals.get("SE", 0.0))
	var ratio: float = (nw / se) if se > 0.0001 else 0.0
	var gfrac: float = float(ground_n) / maxf(float(total_n), 1.0)
	print("[ls] %-18s %s" % [nm, "  ".join(parts)])

	# THE ALIGNMENT CHECK COMES FIRST, because if the sweep is not on the rim the
	# verdict is not evidence about anything. Outside the silhouette the band is
	# either bare ground or, on a glowing shape, warm bloom — so "did it find an
	# edge" is asked as a LUMINANCE SPREAD across the band rather than as a count
	# of exactly-ground pixels, which the full-stack glow defeated.
	var spread := 0.0
	var lo := 9.0
	var hi := -9.0
	for i in range(8):
		if counts[i] > 0:
			lo = minf(lo, sums[i] / float(counts[i]))
			hi = maxf(hi, sums[i] / float(counts[i]))
	spread = hi - lo
	if spread < 0.01:
		print("[ls] %-18s BAND IS FLAT (spread %.3f) — verdict void, oracle "
			% ["", spread] + "is not on an edge")
		_problems.append("%s: rim band is flat (spread %.3f) — the oracle is "
			% [nm, spread] + "misaligned, not the painter")
		return

	var ok := true
	var expect := ""
	match gate:
		"lamp":
			expect = "NW/SE > %.2f" % GATE_LIT
			ok = ratio > GATE_LIT
		"inset":
			expect = "NW/SE < %.2f" % GATE_INSET
			ok = ratio < GATE_INSET
		_:
			expect = "(reported, not gated)"
	var verdict := "-- " if gate == "report" else ("OK" if ok else "WRONG")
	print("[ls] %-18s brightest=%-3s  NW/SE=%.2f  need %s  ground=%.0f%%  %s" % [
		"", best_name, ratio, expect, gfrac * 100.0, verdict])
	if gate != "report" and not ok:
		_problems.append("%s: NW/SE %.2f, needed %s (lamp is %s, peak was %s)"
			% [nm, ratio, expect, _lamp, best_name])


func _zoom(img: Image, at: Vector2i, tag: String) -> void:
	var box := Vector2i(240, 240)
	var org := at - box / 2
	org.x = clampi(org.x, 0, img.get_width() - box.x)
	org.y = clampi(org.y, 0, img.get_height() - box.y)
	var crop := img.get_region(Rect2i(org, box))
	crop.resize(box.x * 3, box.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOT_DIR, tag])
	print("[ls] SAVED %s.png (3x zoom at %s)" % [tag, str(at)])
