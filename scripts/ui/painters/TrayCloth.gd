## TrayCloth — the mourning cloth the widow draws over the tray while the
## question stands. Gray wool with a draped leading edge and fold shadows;
## the Event scene slides the whole control on and off — pure painter.
extends Control

var seed_text := "cloth"

const WOOL := Color(0.200, 0.185, 0.180)
const WOOL_DARK := Color(0.105, 0.098, 0.100)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if minf(size.x, size.y) <= 20.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	# Every edge drapes a little — a straight-sided cover reads as a UI
	# panel, not wool. The leading (left) edge drapes most.
	var pts := PackedVector2Array()
	var x := 6.0
	while x < size.x - 6.0:
		pts.append(Vector2(x, 4.0 + sin(x * 0.035 + ph) * 3.0))
		x += 16.0
	var y := 6.0
	while y < size.y - 6.0:
		pts.append(Vector2(size.x - 4.0 + sin(y * 0.05 + ph * 1.7) * 2.5, y))
		y += 16.0
	x = size.x - 6.0
	while x > 6.0:
		pts.append(Vector2(x, size.y - 4.0 + sin(x * 0.04 + ph * 2.3) * 3.5))
		x -= 16.0
	y = size.y - 6.0
	while y > 6.0:
		pts.append(Vector2(6.0 + sin(y * 0.045 + ph) * 5.0, y))
		y -= 14.0
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(-3, 7))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.38))
	draw_colored_polygon(pts, WOOL)
	# Folds fall away from the drape; a soft light rides the top hem.
	for i in range(4):
		var fx := size.x * (0.18 + 0.20 * float(i)) + rng.randf_range(-5.0, 5.0)
		draw_line(Vector2(fx, 6.0),
			Vector2(fx + rng.randf_range(-10.0, 10.0), size.y - 6.0),
			WOOL_DARK, rng.randf_range(3.0, 5.5), true)
	var hl := PackedVector2Array()
	x = 10.0
	while x < size.x - 8.0:
		hl.append(Vector2(x, 9.0 + sin(x * 0.035 + ph) * 3.0))
		x += 16.0
	draw_polyline(hl, Color(0.42, 0.40, 0.40, 0.5), 2.0, true)
	# The hem, stitched.
	var hem := PackedVector2Array()
	x = 10.0
	while x < size.x - 8.0:
		hem.append(Vector2(x, size.y - 8.0 + sin(x * 0.04 + ph * 2.3) * 3.0))
		x += 12.0
	draw_polyline(hem, Color(0.34, 0.33, 0.36, 0.8), 1.4, true)
