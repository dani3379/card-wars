## TrinketIcon — one dead man's effect on the Widow's Tray (the Kim's-game
## memory event). `kind` picks the silhouette: ring / key / tooth / thimble /
## button / locket / pipe / ball — each built from a few primitives with an
## ink line and a flat contact shadow, legible at 52px on black cloth. The
## squash rides the house camera pitch (lying things draw as ellipses).
## Pure painter.
extends Control

var kind := "ring"
var seed_text := "trinket"

const INK := Color(0.16, 0.13, 0.10, 0.9)
const BRASS := Color(0.72, 0.56, 0.28)
const SILVER := Color(0.72, 0.74, 0.78)
const BONE := Color(0.875, 0.835, 0.745)
const LEAD := Color(0.42, 0.43, 0.46)
const HORN := Color(0.45, 0.33, 0.20)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _ring_arc(c: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in range(25):
		var a := TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, width, true)


func _draw() -> void:
	if minf(size.x, size.y) <= 16.0:
		return
	var c := size * 0.5
	# All fixed measurements scale off the box (u = 1 at the original 52px),
	# so a bigger wrap draws a BIGGER trinket, not a small one adrift.
	var u := size.x / 52.0
	_ellipse(c + Vector2(1, size.y * 0.30), size.x * 0.36, size.y * 0.10,
		Color(0, 0, 0, 0.35))
	match kind:
		"ring":
			_ring_arc(c + Vector2(0, 3 * u), size.x * 0.26, size.y * 0.17, INK, 7.0 * u)
			_ring_arc(c + Vector2(0, 3 * u), size.x * 0.26, size.y * 0.17, BRASS, 4.5 * u)
			_ring_arc(c + Vector2(-2 * u, u), size.x * 0.24, size.y * 0.15,
				Color(0.92, 0.80, 0.52, 0.7), 1.5 * u)
		"key":
			var bow := c + Vector2(-size.x * 0.24, 2 * u)
			_ring_arc(bow, 7.0 * u, 8.5 * u, INK, 6.0 * u)
			_ring_arc(bow, 7.0 * u, 8.5 * u, BRASS, 3.5 * u)
			draw_line(bow + Vector2(6, 1) * u, c + Vector2(size.x * 0.30, 4 * u),
				INK, 6.0 * u, true)
			draw_line(bow + Vector2(6, 1) * u, c + Vector2(size.x * 0.30, 4 * u),
				BRASS, 3.5 * u, true)
			for off in [Vector2(size.x * 0.28, 4 * u), Vector2(size.x * 0.20, 4 * u)]:
				draw_line(c + off, c + off + Vector2(0, 7 * u), BRASS, 3.0 * u, true)
		"tooth":
			_ellipse(c + Vector2(0, -3 * u), 9.0 * u, 8.0 * u, BONE)
			for sx in [-4.0, 4.0]:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(sx - 2.5, 2) * u, c + Vector2(sx + 2.5, 2) * u,
					c + Vector2(sx * 1.3, 13) * u]), BONE)
			_ring_arc(c + Vector2(0, -3 * u), 9.0 * u, 8.0 * u, INK, 1.2 * u)
		"thimble":
			var b := c + Vector2(0, 6 * u)
			draw_colored_polygon(PackedVector2Array([
				b + Vector2(-8, 0) * u, b + Vector2(-7, -14) * u,
				b + Vector2(7, -14) * u, b + Vector2(8, 0) * u]), SILVER)
			_ellipse(b + Vector2(0, -14 * u), 7.0 * u, 3.0 * u, SILVER)
			_ellipse(b, 8.0 * u, 3.0 * u, Color(0.55, 0.57, 0.62))
			for i in range(5):
				draw_circle(b + Vector2(-4.0 + float(i) * 2.0, -9.0) * u,
					0.7 * u, INK, true, -1.0, true)
		"button":
			_ellipse(c + Vector2(0, 2 * u), 10.0 * u, 7.0 * u, HORN)
			_ring_arc(c + Vector2(0, 2 * u), 10.0 * u, 7.0 * u, INK, 1.3 * u)
			for off in [Vector2(-3, 1), Vector2(3, 1), Vector2(-3, 4), Vector2(3, 4)]:
				draw_circle(c + off * u, 1.1 * u, INK, true, -1.0, true)
		"locket":
			var chain := PackedVector2Array()
			for i in range(9):
				var t := float(i) / 8.0
				chain.append(c + Vector2(-14 + t * 20.0, -12 + sin(t * PI) * -4.0) * u)
			draw_polyline(chain, SILVER, 1.6 * u, true)
			_ellipse(c + Vector2(2, 4) * u, 8.0 * u, 9.5 * u, SILVER)
			_ring_arc(c + Vector2(2, 4) * u, 8.0 * u, 9.5 * u, INK, 1.3 * u)
			draw_circle(c + Vector2(2, -6) * u, 1.8 * u, SILVER, true, -1.0, true)
		"pipe":
			draw_line(c + Vector2(-14, 6) * u, c + Vector2(8, -2) * u, BONE,
				3.5 * u, true)
			_ellipse(c + Vector2(11, -2) * u, 5.5 * u, 6.5 * u, BONE)
			_ellipse(c + Vector2(11, -5) * u, 3.5 * u, 2.0 * u, Color(0.12, 0.10, 0.08))
			_ring_arc(c + Vector2(11, -2) * u, 5.5 * u, 6.5 * u, INK, 1.1 * u)
		"ball":
			draw_circle(c + Vector2(0, u), 8.5 * u, LEAD, true, -1.0, true)
			draw_circle(c + Vector2(-3, -2) * u, 2.4 * u, Color(0.70, 0.72, 0.76, 0.8),
				true, -1.0, true)
			_ring_arc(c + Vector2(0, u), 8.5 * u, 8.5 * u, INK, 1.2 * u)
