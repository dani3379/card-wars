## EventHelm — a legionary kettle-helm as table furniture. Two postures:
## `dome_up` (the Old Army Game's shell — mouth to the drum, hiding the
## coin) and bowl-up (the drawing of lots — mouth open, holding the folded
## slips, `slips` of them poking above the rim). `dented` marks the ONE
## shell whose crease "rings false" — the honest game's tell; it must stay
## legible at 130px. Pure painter.
extends Control

var seed_text := "helm"
var dome_up := true
var dented := false
var slips := 0

const STEEL := Color(0.455, 0.465, 0.505)
const STEEL_LIT := Color(0.600, 0.615, 0.660)
const STEEL_DARK := Color(0.300, 0.310, 0.345)
const PAPER := Color(0.885, 0.855, 0.755)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	if minf(size.x, size.y) <= 20.0:
		return
	var cx := size.x * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	if dome_up:
		var base_y := size.y - 20.0
		var rx := size.x * 0.33
		var ry := size.y * 0.62
		# Contact shadow: wide and flat, the ground-plane convention.
		_ellipse(Vector2(cx, base_y + 8), size.x * 0.48, 7, Color(0, 0, 0, 0.35))
		# Dome: the upper half-ellipse, closed along the base line.
		var pts := PackedVector2Array()
		for i in range(15):
			var a := PI + PI * float(i) / 14.0
			pts.append(Vector2(cx + cos(a) * rx, base_y + sin(a) * ry))
		draw_colored_polygon(pts, STEEL)
		# Crown highlight — lamplight from the left.
		var hl := PackedVector2Array()
		for i in range(8):
			var a := PI * 1.15 + PI * 0.45 * float(i) / 7.0
			hl.append(Vector2(cx + cos(a) * (rx - 6.0), base_y + sin(a) * (ry - 6.0)))
		draw_polyline(hl, Color(STEEL_LIT.r, STEEL_LIT.g, STEEL_LIT.b, 0.75),
			3.0, true)
		# Seeded campaign scuffs.
		for i in range(4):
			var a := PI + PI * rng.randf()
			var p := Vector2(cx + cos(a) * rx * 0.7, base_y + sin(a) * ry * 0.7)
			var d := Vector2(cos(a + 1.4), sin(a + 1.4)) * rng.randf_range(8.0, 18.0)
			draw_line(p, p + d, Color(0.24, 0.25, 0.28, 0.5),
				rng.randf_range(1.2, 2.2), true)
		if dented:
			# The crease that rings false: a pressed-in shadow with a bright
			# folded lip — the tell must read across the table.
			var dc := Vector2(cx + rx * 0.38, base_y - ry * 0.55)
			var blob := PackedVector2Array()
			for i in range(10):
				var a := TAU * float(i) / 10.0
				var w := 1.0 + 0.25 * sin(a * 3.0 + 1.0)
				blob.append(dc + Vector2(cos(a) * 13.0, sin(a) * 9.0) * w)
			draw_colored_polygon(blob, Color(0.235, 0.245, 0.275))
			draw_arc(dc + Vector2(-2, 3), 12.0, PI * 0.65, PI * 1.35, 10,
				Color(0.66, 0.68, 0.72, 0.9), 2.0, true)
		# Brim over the dome's foot, riveted.
		_ellipse(Vector2(cx, base_y), size.x * 0.45, 11, STEEL_DARK)
		_ellipse(Vector2(cx, base_y - 2), size.x * 0.40, 8, STEEL)
		for i in range(5):
			var bx := cx + (float(i) - 2.0) * size.x * 0.16
			draw_circle(Vector2(bx, base_y + 3), 1.8, Color(0.22, 0.23, 0.26),
				true, -1.0, true)
	else:
		# Bowl-up: the helm stands on its crown, mouth open for the lots.
		# The riveted brim flares at the mouth — the helmet cue upside down;
		# without it the bowl reads as crockery.
		var mouth_y := 30.0
		var rx := size.x * 0.30
		var ry := size.y * 0.54
		_ellipse(Vector2(cx, size.y - 10), size.x * 0.40, 9, Color(0, 0, 0, 0.35))
		var pts := PackedVector2Array()
		for i in range(15):
			var a := PI * float(i) / 14.0
			pts.append(Vector2(cx + cos(a) * rx, mouth_y + sin(a) * ry))
		draw_colored_polygon(pts, STEEL)
		# Crown boss it stands on, campaign scuffs, a side highlight.
		_ellipse(Vector2(cx, mouth_y + ry - 4.0), 10.0, 5.0, STEEL_DARK)
		for i in range(4):
			var a := rng.randf_range(PI * 0.15, PI * 0.85)
			var p := Vector2(cx + cos(a) * rx * 0.7, mouth_y + sin(a) * ry * 0.7)
			var d := Vector2(cos(a + 1.4), sin(a + 1.4)) * rng.randf_range(8.0, 16.0)
			draw_line(p, p + d, Color(0.24, 0.25, 0.28, 0.5),
				rng.randf_range(1.2, 2.2), true)
		var hl := PackedVector2Array()
		for i in range(8):
			var a := PI * 0.60 + PI * 0.32 * float(i) / 7.0
			hl.append(Vector2(cx + cos(a) * (rx - 5.0), mouth_y + sin(a) * (ry - 5.0)))
		draw_polyline(hl, Color(STEEL_LIT.r, STEEL_LIT.g, STEEL_LIT.b, 0.7),
			2.5, true)
		# Folded slips poking above the rim — drawn before the near rim so
		# they sit IN the bowl.
		for i in range(slips):
			var sx := cx + (float(i) - float(slips - 1) * 0.5) * 26.0 \
				+ rng.randf_range(-5.0, 5.0)
			var tilt := rng.randf_range(-0.35, 0.35)
			var w := 10.0
			var hgt := rng.randf_range(14.0, 24.0)
			var o := Vector2(sx, mouth_y + 2.0)
			var dirv := Vector2(sin(tilt), -cos(tilt))
			var side := Vector2(cos(tilt), sin(tilt)) * w * 0.5
			var quad := PackedVector2Array([o - side, o - side + dirv * hgt,
				o + side + dirv * hgt, o + side])
			draw_colored_polygon(quad, PAPER)
			draw_line(o - side + dirv * hgt, o + side + dirv * hgt,
				Color(0.55, 0.50, 0.40, 0.8), 1.2, true)
		_ellipse(Vector2(cx, mouth_y + 2), size.x * 0.46, 13, STEEL_DARK)
		_ellipse(Vector2(cx, mouth_y), size.x * 0.40, 10, STEEL)
		for i in range(5):
			var bx := cx + (float(i) - 2.0) * size.x * 0.19
			draw_circle(Vector2(bx, mouth_y + 9), 1.8, Color(0.22, 0.23, 0.26),
				true, -1.0, true)
		_ellipse(Vector2(cx, mouth_y), size.x * 0.33, 8, Color(0.10, 0.095, 0.085))
