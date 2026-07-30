## QuoitsPeg — the ground stake the quoits are pitched at (quoits_game
## stage). A short driven stake, mushroomed at the crown from years of
## mauls, with a chalk ring scratched around its base. Pure painter.
extends Control

var seed_text := "peg"

const WOOD := Color(0.42, 0.33, 0.22)
const WOOD_LIT := Color(0.55, 0.45, 0.31)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if minf(size.x, size.y) <= 12.0:
		return
	var u := size.x / 30.0
	var base := Vector2(size.x * 0.5, size.y - 8.0 * u)
	# The chalk ring, scratched around the base.
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	for i in range(20):
		var a := TAU * float(i) / 20.0
		var r := 13.0 * u * (1.0 + rng.randf_range(-0.06, 0.06))
		pts.append(base + Vector2(cos(a) * r, sin(a) * r * 0.42))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.90, 0.90, 0.86, 0.55), 1.8, true)
	# Contact shadow, then the stake, leaning a hair.
	draw_colored_polygon(PackedVector2Array([
		base + Vector2(-7, 1) * u, base + Vector2(7, 1) * u,
		base + Vector2(10, 4) * u, base + Vector2(-4, 4) * u]),
		Color(0, 0, 0, 0.30))
	var lean := rng.randf_range(-1.5, 1.5) * u
	var top := base + Vector2(lean, -size.y + 14.0 * u)
	draw_line(base, top, WOOD, 7.0 * u, true)
	draw_line(base + Vector2(-1.5 * u, 0), top + Vector2(-1.5 * u, 0),
		WOOD_LIT, 2.2 * u, true)
	# The mushroomed crown — beaten wide and pale.
	draw_circle(top, 5.2 * u, WOOD_LIT, true, -1.0, true)
	draw_arc(top, 5.2 * u, 0, TAU, 12, Color(0.28, 0.22, 0.15, 0.9), 1.4, true)
	draw_line(top + Vector2(-3, -1) * u, top + Vector2(3, 1) * u,
		Color(0.28, 0.22, 0.15, 0.6), 1.0, true)
