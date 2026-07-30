## WarPip — the six marks of the Old King's gaming board, for Crown & Pike
## (the Crown-and-Anchor retell). Each mark is doubly distinct — a bold flat
## silhouette AND a saturated tint — so it reads instantly and stays legible
## to a colourblind eye (the lesson of the drum game's four identical heads).
## Pure painter: the Event scene owns all motion and lays out the board.
##
##   kind — 0 CROWN · 1 PIKE · 2 SKULL · 3 BANNER · 4 COIN · 5 WHEEL
##   tint — the mark's colour (betting pad + die face share it)
##   lit  — a rolled die face or a winning pad: brighten + halo
##   dim  — an unbacked pad: fade toward the cloth
extends Control

var kind := 0:
	set(v):
		kind = v
		queue_redraw()
var tint := Color(0.85, 0.68, 0.25):
	set(v):
		tint = v
		queue_redraw()
var lit := false:
	set(v):
		lit = v
		queue_redraw()
var dim := false:
	set(v):
		dim = v
		queue_redraw()

const INK := Color(0.10, 0.07, 0.04, 0.92)

# Human names, for captions/log lines.
const NAMES := ["Crown", "Pike", "Skull", "Banner", "Coin", "Wheel"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _u(p: Vector2) -> Vector2:
	# Unit space [-1,1] → control rect, with a small inset margin.
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * 0.82
	return c + Vector2(p.x * r, p.y * r)


func _poly(pts: PackedVector2Array, col: Color, outline := true) -> void:
	var world := PackedVector2Array()
	for p in pts:
		world.append(_u(p))
	draw_colored_polygon(world, col)
	if outline:
		var loop := world
		loop.append(world[0])
		draw_polyline(loop, INK, maxf(1.5, size.x * 0.012), true)


func _draw() -> void:
	if size.x < 8.0:
		return
	var col := tint
	if lit:
		col = tint.lightened(0.22)
	elif dim:
		col = tint.darkened(0.35)
		col.a = 0.55
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5

	# Lit halo behind a rolled/winning mark.
	if lit:
		draw_circle(c, r * 0.96, Color(tint.r, tint.g, tint.b, 0.22), true, -1.0, true)

	match kind:
		0: _draw_crown(col)
		1: _draw_pike(col)
		2: _draw_skull(col, c, r)
		3: _draw_banner(col)
		4: _draw_coin(col, c, r)
		5: _draw_wheel(col, c, r)


func _draw_crown(col: Color) -> void:
	# A three-point crown band: a broad base and three spikes with ball finials.
	_poly(PackedVector2Array([
		Vector2(-0.72, 0.10), Vector2(-0.80, -0.55), Vector2(-0.42, -0.18),
		Vector2(0.0, -0.68), Vector2(0.42, -0.18), Vector2(0.80, -0.55),
		Vector2(0.72, 0.10),
	]), col)
	# The base band.
	_poly(PackedVector2Array([
		Vector2(-0.74, 0.10), Vector2(0.74, 0.10),
		Vector2(0.66, 0.52), Vector2(-0.66, 0.52),
	]), col)
	for x in [-0.80, 0.0, 0.80]:
		draw_circle(_u(Vector2(x, -0.62)), size.x * 0.045, col, true, -1.0, true)


func _draw_pike(col: Color) -> void:
	# Two crossed pikes: shafts as thick strokes, leaf heads at the raised ends.
	var w := maxf(3.0, size.x * 0.085)
	for s in [1.0, -1.0]:
		var a := _u(Vector2(-0.62 * s, 0.66))
		var b := _u(Vector2(0.55 * s, -0.62))
		draw_line(a, b, col, w, true)
		draw_line(a, b, INK, w * 0.28, true)
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * size.x * 0.075
		draw_colored_polygon(PackedVector2Array([
			b + dir * size.x * 0.11, b + side, b - side]), col)


func _draw_skull(col: Color, c: Vector2, r: float) -> void:
	# Dome + cheekbones + a small jaw; two black eye-holes and a nasal notch.
	draw_circle(c + Vector2(0, -r * 0.14), r * 0.62, col, true, -1.0, true)
	_poly(PackedVector2Array([
		Vector2(-0.52, 0.02), Vector2(0.52, 0.02),
		Vector2(0.34, 0.60), Vector2(0.14, 0.56), Vector2(0.0, 0.70),
		Vector2(-0.14, 0.56), Vector2(-0.34, 0.60),
	]), col, false)
	draw_circle(c + Vector2(-r * 0.24, -r * 0.16), r * 0.17, INK, true, -1.0, true)
	draw_circle(c + Vector2(r * 0.24, -r * 0.16), r * 0.17, INK, true, -1.0, true)
	draw_colored_polygon(PackedVector2Array([
		_u(Vector2(0.0, -0.02)), _u(Vector2(-0.10, 0.16)), _u(Vector2(0.10, 0.16))]),
		INK)


func _draw_banner(col: Color) -> void:
	# A swallowtail standard on a staff.
	draw_line(_u(Vector2(-0.5, -0.78)), _u(Vector2(-0.5, 0.82)),
		INK.lightened(0.15), maxf(2.5, size.x * 0.045), true)
	draw_circle(_u(Vector2(-0.5, -0.80)), size.x * 0.04, col, true, -1.0, true)
	_poly(PackedVector2Array([
		Vector2(-0.5, -0.70), Vector2(0.72, -0.60),
		Vector2(0.48, -0.22), Vector2(0.72, 0.16),
		Vector2(-0.5, 0.06),
	]), col)


func _draw_coin(col: Color, c: Vector2, r: float) -> void:
	# A struck disc with a raised inner ring and a small crossed-pike mark.
	draw_circle(c, r * 0.72, col, true, -1.0, true)
	draw_arc(c, r * 0.72, 0, TAU, 40, INK, maxf(1.5, size.x * 0.012), true)
	draw_arc(c, r * 0.54, 0, TAU, 32, Color(INK.r, INK.g, INK.b, 0.5),
		maxf(1.0, size.x * 0.010), true)
	var w := maxf(2.0, size.x * 0.05)
	draw_line(c + Vector2(-r * 0.28, r * 0.28), c + Vector2(r * 0.28, -r * 0.28),
		INK, w, true)
	draw_line(c + Vector2(r * 0.28, r * 0.28), c + Vector2(-r * 0.28, -r * 0.28),
		INK, w, true)


func _draw_wheel(col: Color, c: Vector2, r: float) -> void:
	# A spoked cart-wheel — the mill, the wheel of the war's fortune.
	draw_arc(c, r * 0.72, 0, TAU, 44, col, maxf(3.0, size.x * 0.085), true)
	draw_arc(c, r * 0.72, 0, TAU, 44, INK, maxf(1.2, size.x * 0.014), true)
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r * 0.10, c + d * r * 0.70, col, maxf(2.5, size.x * 0.05), true)
	draw_circle(c, r * 0.16, col, true, -1.0, true)
	draw_circle(c, r * 0.16, INK, false, maxf(1.2, size.x * 0.012), true)
