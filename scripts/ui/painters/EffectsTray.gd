## EffectsTray — the widow's black-cloth tray: a worn wooden rim around a
## dark wool bed the trinkets read against. Same camera pitch as CastPatch:
## the silhouette tapers toward the far edge, the near rim shows thickness,
## the far reach falls into shadow. Pure painter.
extends Control

var seed_text := "tray"

const WOOD := Color(0.285, 0.205, 0.130)
const WOOD_DARK := Color(0.130, 0.090, 0.055)
const CLOTH := Color(0.085, 0.080, 0.088)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _edge(inset: float, n: int = 28) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var c := size * 0.5
	var half := size * 0.5 - Vector2(inset, inset)
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var v := Vector2(cos(a), sin(a))
		var square := 1.0 / maxf(absf(v.x), absf(v.y))
		var k: float = lerpf(1.0, minf(square, 1.42), 0.62)
		var w := 1.0 + 0.014 * sin(a * 5.0 + ph)
		var p := v * k * w * half
		var depth := clampf((p.y + half.y) / maxf(1.0, 2.0 * half.y), 0.0, 1.0)
		p.x *= lerpf(0.88, 1.04, depth)
		pts.append(c + p)
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 40.0:
		return
	var rim := _edge(4.0)
	var shadow := PackedVector2Array()
	var lip := PackedVector2Array()
	for p in rim:
		shadow.append(p + Vector2(0, 13))
		lip.append(p + Vector2(0, 8))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.38))
	draw_colored_polygon(lip, WOOD_DARK)
	draw_colored_polygon(rim, WOOD)
	var closed := rim.duplicate()
	closed.append(rim[0])
	draw_polyline(closed, WOOD_DARK, 2.0, true)
	# The cloth bed, and the far reach falling into shadow.
	draw_colored_polygon(_edge(16.0), CLOTH)
	var far := _edge(19.0, 28)
	var band := PackedVector2Array()
	for i in range(14, 28):
		band.append(far[i])
	band.append(far[0])
	draw_colored_polygon(band, Color(0.0, 0.0, 0.0, 0.22))
	# Wool folds: three soft creases the trinkets sit between.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 5
	for i in range(3):
		var y := size.y * (0.32 + 0.18 * float(i)) + rng.randf_range(-6.0, 6.0)
		var fold := PackedVector2Array()
		var x := size.x * 0.12
		while x < size.x * 0.88:
			fold.append(Vector2(x, y + sin(x * 0.02 + float(i) * 2.0) * 4.0))
			x += 14.0
		draw_polyline(fold, Color(0.0, 0.0, 0.0, 0.30), 3.0, true)
