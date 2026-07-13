## TablePlate — extracted from Combat.gd (backend restructure 2026-07-14).
## The war-table surface: a faded campaign chart inked straight onto the
## scorched table the battle is fought across — a double-ruled coast with
## sea hatching, dashed march routes, site rings, a compass, cup stains,
## and the burn creeping in along the clash band and the edges (heavier in
## later acts: the war eats the map). Seeded per encounter+act, so every
## fight's table is its own document but stable across rebuilds. Drawn
## once; static — sits between the dark substrate and the lane tracks.
extends Control

var seed_text := "table"
var act := 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _coast_y(t: float, y0: float, amp: float, ph1: float, ph2: float) -> float:
	return y0 + sin(t * 4.2 + ph1) * amp * 0.55 + sin(t * 9.7 + ph2) * amp * 0.30

func _draw() -> void:
	if size.x < 80.0 or size.y < 80.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ink := Color(0.74, 0.58, 0.34)
	# 1 — the coast: a double-ruled wandering line (the chart idiom).
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var y0 := size.y * (0.30 + rng.randf() * 0.40)
	var amp := size.y * 0.14
	var coast := PackedVector2Array()
	var n := 26
	for i in range(n + 1):
		var t := float(i) / float(n)
		coast.append(Vector2(t * size.x, _coast_y(t, y0, amp, ph1, ph2)))
	draw_polyline(coast, Color(ink.r, ink.g, ink.b, 0.15), 2.2, true)
	var coast2 := PackedVector2Array()
	for p in coast:
		coast2.append(p + Vector2(0, 6))
	draw_polyline(coast2, Color(ink.r, ink.g, ink.b, 0.09), 1.1, true)
	# Sea hatching seaward of the coast.
	for i in range(26):
		var t := rng.randf()
		var hy := _coast_y(t, y0, amp, ph1, ph2) + 12.0 + rng.randf() * 46.0
		if hy > size.y - 8.0:
			continue
		draw_line(Vector2(t * size.x, hy),
			Vector2(t * size.x + 10.0 + rng.randf() * 8.0, hy),
			Color(ink.r, ink.g, ink.b, 0.055 + rng.randf() * 0.04), 1.0, true)
	# 2 — march routes: two dashed tracks wandering across the land.
	for r in range(2):
		var ry := size.y * (0.12 + rng.randf() * 0.66)
		var rph := rng.randf() * TAU
		var seg_on := true
		var x := rng.randf() * 40.0
		while x < size.x - 12.0:
			var x2 := minf(x + 14.0, size.x - 8.0)
			if seg_on:
				var ya := ry + sin(x / size.x * 5.0 + rph) * size.y * 0.05
				var yb := ry + sin(x2 / size.x * 5.0 + rph) * size.y * 0.05
				draw_line(Vector2(x, ya), Vector2(x2, yb),
					Color(ink.r, ink.g, ink.b, 0.115), 1.4, true)
			seg_on = not seg_on
			x = x2
	# 3 — site rings: held positions marked on the chart.
	for i in range(5):
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		draw_arc(p, 4.0 + rng.randf() * 5.0, 0, TAU, 18,
			Color(ink.r, ink.g, ink.b, 0.13), 1.2, true)
		draw_circle(p, 1.2, Color(ink.r, ink.g, ink.b, 0.16), true, -1.0, true)
	# 4 — compass cross, upper-right quadrant.
	var cp := Vector2(size.x * (0.74 + rng.randf() * 0.16),
		size.y * (0.12 + rng.randf() * 0.14))
	var cr := 16.0 + rng.randf() * 8.0
	draw_arc(cp, cr, 0, TAU, 26, Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
	draw_line(cp + Vector2(0, -cr * 1.45), cp + Vector2(0, cr * 1.45),
		Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
	draw_line(cp + Vector2(-cr * 1.45, 0), cp + Vector2(cr * 1.45, 0),
		Color(ink.r, ink.g, ink.b, 0.125), 1.0, true)
	# 5 — cup ring stains: someone set their drink on the orders.
	for i in range(2):
		var sp := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var a0 := rng.randf() * TAU
		draw_arc(sp, 13.0 + rng.randf() * 9.0, a0, a0 + TAU * 0.8, 30,
			Color(0.30, 0.20, 0.10, 0.10), 2.6, true)
	# 6 — the burn: scorch along the clash band + creeping from the
	# top/bottom edges; later acts burn hotter.
	var burn := Color(0.04, 0.02, 0.012)
	for i in range(7 + act * 3):
		var bp: Vector2
		if rng.randf() < 0.55:
			bp = Vector2(rng.randf() * size.x,
				size.y * 0.5 + (rng.randf() - 0.5) * size.y * 0.16)
		else:
			bp = Vector2(rng.randf() * size.x,
				size.y * (0.04 + 0.92 * float(rng.randi() % 2)) \
				+ (rng.randf() - 0.5) * size.y * 0.07)
		var br := 14.0 + rng.randf() * 34.0
		draw_circle(bp, br, Color(burn.r, burn.g, burn.b,
			0.09 + rng.randf() * 0.11), true, -1.0, true)
		draw_circle(bp, br * 0.55, Color(burn.r, burn.g, burn.b,
			0.08 + rng.randf() * 0.10), true, -1.0, true)
