## CandleStub — the Burning Inch: a tallow stub on a brass dish standing
## beside a push-your-luck ladder (the Gravesong Choir's verses, any future
## risk_loop). `burn` (0..1) is the risk made physical — the column shortens
## and the spent wax piles up as the presses spend it. `flame_h` scales the
## flame (0 = guttered out) and `flick` sways it; the Event scene drives both
## and calls queue_redraw() — pure painter, no _process.
##
## (2026-07-22 repaint. Was: one flat cream rectangle with a single 3px line
## down its right edge, two pale blobs stranded mid-column that were meant to
## be drips, and a dish shadow mostly hidden under the dish. It read as a
## cream bar, not tallow. Now the column is shaded as an actual CYLINDER —
## strip-filled across a lit band and a form shadow — and its top glows with
## the flame it is carrying, which is the read that says "lit candle" more
## than the flame itself does. Drips start at the crater lip where wax
## actually escapes and run DOWN with a bead at the end; the dish gets its
## thickness, its spent-wax pool and a wide unoccluded contact shadow; and
## the flame's halo is stacked falloff instead of one hard-edged disc.)
extends Control

var seed_text := "candle"
var burn := 0.0
var flame_h := 1.0
var flick := 0.0

const WAX := Color(0.855, 0.790, 0.640)
const WAX_DIM := Color(0.548, 0.470, 0.338)
const WAX_LIT := Color(0.962, 0.928, 0.818)
const WAX_FRESH := Color(0.948, 0.908, 0.792)
const BRASS := Color(0.360, 0.275, 0.130)
const BRASS_LIT := Color(0.592, 0.462, 0.221)
const BRASS_DARK := Color(0.216, 0.160, 0.074)
const FLAME_WARM := Color(1.0, 0.78, 0.42)
const MOLTEN := Color(0.98, 0.87, 0.63)

# Column geometry, resolved once per _draw and read by the slice helpers.
var _cx := 0.0
var _hw := 20.0
var _ph1 := 0.0
var _ph2 := 0.0
var _top_y := 0.0
var _base_y := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


## The wobbled silhouette. `u` runs 0 (left rail) → 1 (right rail); the two
## rails wobble by different amounts so the stub is never a extruded rect.
func _lerp_x(t: float, u: float) -> float:
	var wob := 1.5 * sin(t * 5.0 + _ph1) + 1.0 * sin(t * 11.0 + _ph2)
	return lerpf(_cx - _hw + wob, _cx + _hw + wob * 0.6, u)


func _y_at(t: float) -> float:
	return lerpf(_top_y, _base_y, t)


## One patch of the column between two heights and two rails — the unit the
## cylinder shading and the flame-glow bands are both painted in.
func _slice(t0: float, t1: float, u0: float, u1: float,
		samp: int = 5) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in range(samp):
		var t := lerpf(t0, t1, float(i) / float(samp - 1))
		poly.append(Vector2(_lerp_x(t, u0), _y_at(t)))
	for i in range(samp - 1, -1, -1):
		var t := lerpf(t0, t1, float(i) / float(samp - 1))
		poly.append(Vector2(_lerp_x(t, u1), _y_at(t)))
	return poly


## Cylinder ramp: a lit band left of centre, a form shadow rolling into the
## right rail, and a hint of dark on the extreme left so the edge turns.
func _wax_at(u: float) -> Color:
	var lit_amt := exp(-pow((u - 0.30) / 0.26, 2.0))
	var c := WAX.lerp(WAX_DIM, smoothstep(0.52, 1.0, u) * 0.80)
	c = c.lerp(WAX_LIT, lit_amt * 0.60)
	if u < 0.11:
		c = c.lerp(WAX_DIM, (0.11 - u) / 0.11 * 0.42)
	return c


func _draw() -> void:
	if minf(size.x, size.y) <= 24.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var b := clampf(burn, 0.0, 1.0)
	var glow := clampf(flame_h, 0.0, 1.0)
	_cx = size.x * 0.5
	_hw = 20.0
	_ph1 = rng.randf() * TAU
	_ph2 = rng.randf() * TAU
	var dish_y := size.y - 16.0
	# Never fully gone — a stub is a stub even at the last verse.
	_base_y = dish_y - 4.0
	_top_y = _base_y - (size.y * 0.58 * (1.0 - 0.72 * b) + 10.0)

	# ── the dish ─────────────────────────────────────────────────────────
	# Contact shadow first: wide, flat and thrown clear BELOW the rim, so it
	# is not swallowed by the dish it belongs to.
	_ellipse(Vector2(_cx + 3, dish_y + 19), 88, 17, Color(0, 0, 0, 0.10))
	_ellipse(Vector2(_cx + 2, dish_y + 12), 64, 13, Color(0, 0, 0, 0.30))
	# Cast thickness, then the top face and the turned well.
	_ellipse(Vector2(_cx, dish_y + 6), 52, 11, BRASS_DARK)
	_ellipse(Vector2(_cx, dish_y), 52, 11, BRASS)
	_ellipse(Vector2(_cx, dish_y - 1), 44, 9, BRASS.lerp(BRASS_DARK, 0.45))
	_ellipse(Vector2(_cx, dish_y - 2.5), 38, 7.4, BRASS_LIT.lerp(BRASS, 0.35))
	# The one specular on the rim, upper-left where the lamp is.
	var rim := PackedVector2Array()
	for i in range(14):
		var a := PI * (1.06 + 0.52 * float(i) / 13.0)
		rim.append(Vector2(_cx + cos(a) * 48.0, dish_y + sin(a) * 10.0))
	draw_polyline(rim, Color(0.86, 0.72, 0.42, 0.55), 2.6, true)
	# Spent wax pools in the dish as the inch is spent — risk you can count.
	if b > 0.06:
		_ellipse(Vector2(_cx, dish_y - 3.5), 21.0 + 20.0 * b, 5.0 + 3.4 * b,
			Color(0.900, 0.848, 0.706, 0.92))
		_ellipse(Vector2(_cx - 3.0, dish_y - 5.0), 14.0 + 14.0 * b, 3.0 + 2.0 * b,
			Color(0.960, 0.925, 0.812, 0.75))

	# ── the column, shaded as a cylinder ─────────────────────────────────
	var strips := 16
	for s in range(strips):
		var u0 := float(s) / float(strips)
		var u1 := float(s + 1) / float(strips)
		draw_colored_polygon(_slice(0.0, 1.0, u0, u1), _wax_at((u0 + u1) * 0.5))
	# Pour ridges — tallow was poured in passes and it shows.
	for i in range(3):
		var rt := rng.randf_range(0.22, 0.92)
		var ridge := PackedVector2Array()
		for k in range(6):
			var uu := lerpf(0.10, 0.90, float(k) / 5.0)
			ridge.append(Vector2(_lerp_x(rt, uu), _y_at(rt) + sin(uu * PI) * 1.6))
		draw_polyline(ridge, Color(WAX_DIM.r, WAX_DIM.g, WAX_DIM.b, 0.16), 2.0, true)
	# The flame's own light soaking into the top of the stub. Tallow is
	# translucent; this glow is what actually reads as "carrying a flame".
	if glow > 0.02:
		var bands := 6
		for i in range(bands):
			var g0 := float(i) / float(bands) * 0.42
			var g1 := float(i + 1) / float(bands) * 0.42
			draw_colored_polygon(_slice(g0, g1, 0.0, 1.0),
				Color(FLAME_WARM.r, FLAME_WARM.g, FLAME_WARM.b,
					(1.0 - float(i) / float(bands)) * 0.30 * glow))

	# ── the crater ───────────────────────────────────────────────────────
	var top_c := Vector2(_lerp_x(0.0, 0.5), _top_y)
	var top_rx := (_lerp_x(0.0, 1.0) - _lerp_x(0.0, 0.0)) * 0.5
	_ellipse(top_c, top_rx, top_rx * 0.28, WAX_DIM.lerp(WAX, 0.30))
	_ellipse(top_c + Vector2(0, 0.8), top_rx * 0.80, top_rx * 0.20,
		MOLTEN.lerp(FLAME_WARM, glow * 0.55))
	_ellipse(top_c + Vector2(0, 1.2), top_rx * 0.42, top_rx * 0.10,
		Color(1.0, 0.92, 0.74, 0.85))
	# Lit lip on the lamp side.
	var lip := PackedVector2Array()
	for i in range(12):
		var a := PI * (1.05 + 0.60 * float(i) / 11.0)
		lip.append(top_c + Vector2(cos(a) * top_rx, sin(a) * top_rx * 0.28))
	draw_polyline(lip, Color(1.0, 0.96, 0.86, 0.50), 1.8, true)

	# ── the drips ────────────────────────────────────────────────────────
	# They begin where wax actually escapes — the crater lip — and run down.
	var n_drips := 3 + int(b * 7.0)
	for i in range(n_drips):
		var on_left := i % 2 == 0
		var u := 0.0 if on_left else 1.0
		var side := -1.0 if on_left else 1.0
		var t0 := rng.randf_range(0.0, 0.05)
		var t1 := minf(t0 + rng.randf_range(0.12, 0.44) * (0.55 + 0.75 * b), 0.96)
		var w0 := rng.randf_range(2.6, 4.4)
		var la: Array = []
		var lb: Array = []
		var samp := 7
		for k in range(samp):
			var kk := float(k) / float(samp - 1)
			var tt := lerpf(t0, t1, kk)
			var xx := _lerp_x(tt, u) + side * 0.9
			var yy := _y_at(tt)
			var ww := w0 * lerpf(1.0, 0.60, kk)
			la.append(Vector2(xx - ww, yy))
			lb.append(Vector2(xx + ww, yy))
		var ribbon := PackedVector2Array()
		for p in la:
			ribbon.append(p)
		for k in range(lb.size() - 1, -1, -1):
			ribbon.append(lb[k])
		draw_colored_polygon(ribbon, WAX_FRESH)
		# A lit west flank and a thin shadow east — the drip is round too.
		var sheen := PackedVector2Array()
		for k in range(la.size()):
			sheen.append(la[k].lerp(lb[k], 0.28))
		draw_polyline(sheen, Color(1.0, 0.98, 0.92, 0.55), 1.3, true)
		var dk := PackedVector2Array()
		for k in range(la.size()):
			dk.append(la[k].lerp(lb[k], 0.88))
		draw_polyline(dk, Color(WAX_DIM.r, WAX_DIM.g, WAX_DIM.b, 0.42), 1.2, true)
		# The bead that stopped when it cooled.
		var bead := Vector2(_lerp_x(t1, u) + side * 0.9, _y_at(t1))
		var br := w0 * 0.98
		draw_circle(bead + Vector2(0.8, 1.2), br * 1.05, Color(0, 0, 0, 0.16),
			true, -1.0, true)
		draw_circle(bead, br, WAX_FRESH, true, -1.0, true)
		draw_circle(bead + Vector2(-br * 0.32, -br * 0.34), br * 0.34,
			Color(1.0, 0.99, 0.94, 0.75), true, -1.0, true)

	# Contour: the two rails, inked so the stub separates from the dark.
	var rail_l := PackedVector2Array()
	var rail_r := PackedVector2Array()
	for i in range(9):
		var t := float(i) / 8.0
		rail_l.append(Vector2(_lerp_x(t, 0.0), _y_at(t)))
		rail_r.append(Vector2(_lerp_x(t, 1.0), _y_at(t)))
	draw_polyline(rail_l, Color(0.32, 0.26, 0.18, 0.40), 1.4, true)
	draw_polyline(rail_r, Color(0.26, 0.20, 0.13, 0.60), 1.8, true)

	# ── the flame ────────────────────────────────────────────────────────
	# Wick first: charred, bent the way the last gust left it.
	draw_line(Vector2(top_c.x, top_c.y + 1), Vector2(top_c.x + 1.5, top_c.y - 8),
		Color(0.16, 0.12, 0.09), 2.4, true)
	if flame_h <= 0.02:
		return
	var fb := top_c + Vector2(1.0, -8.0)
	var fh := 34.0 * flame_h
	var sway := sin(flick * TAU) * 2.6 * flame_h
	# Stacked falloff, not one hard-edged disc — and a warm pool thrown down
	# onto the brass, because a flame lights what it stands on.
	_ellipse(Vector2(_cx, dish_y - 3), 46.0, 9.0,
		Color(FLAME_WARM.r, FLAME_WARM.g, FLAME_WARM.b, 0.10 * flame_h))
	for i in range(4):
		var k := float(i) / 3.0
		draw_circle(fb + Vector2(0, -fh * 0.42), fh * lerpf(1.75, 0.42, k),
			Color(1.0, 0.72, 0.30, lerpf(0.035, 0.14, k)), true, -1.0, true)
	var outer := PackedVector2Array([
		fb + Vector2(-5.0, 0.5), fb + Vector2(-3.4, -fh * 0.48),
		fb + Vector2(sway, -fh), fb + Vector2(3.4, -fh * 0.48),
		fb + Vector2(5.0, 0.5)])
	draw_colored_polygon(outer, Color(1.0, 0.63, 0.16, 0.90))
	var mid := PackedVector2Array([
		fb + Vector2(-3.2, 0.4), fb + Vector2(-2.2, -fh * 0.44),
		fb + Vector2(sway * 0.8, -fh * 0.80), fb + Vector2(2.2, -fh * 0.44),
		fb + Vector2(3.2, 0.4)])
	draw_colored_polygon(mid, Color(1.0, 0.86, 0.46, 0.95))
	var inner := PackedVector2Array([
		fb + Vector2(-1.9, 0.2), fb + Vector2(sway * 0.6, -fh * 0.52),
		fb + Vector2(1.9, 0.2)])
	draw_colored_polygon(inner, Color(1.0, 0.98, 0.90, 0.97))
	# The blue root at the wick, and the ember where it is eating the cord.
	draw_circle(fb + Vector2(0, -1.0), 2.6, Color(0.42, 0.56, 1.0, 0.50),
		true, -1.0, true)
	draw_circle(fb + Vector2(0, 0.8), 1.5, Color(1.0, 0.55, 0.18, 0.85),
		true, -1.0, true)
