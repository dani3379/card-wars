## PayToken — one bone pay-chit from the courier's satchel (the counting
## game). A wobbled square token, pips 1–6 in dice layout, lying on the
## plate with a flat offset shadow. Pure painter.
extends Control

var seed_text := "token"
var value := 1

const BONE := Color(0.870, 0.838, 0.750)
const INK := Color(0.22, 0.17, 0.12, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _square(off: Vector2) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var c := size * 0.5
	var half := size * 0.5 - Vector2(3, 3)
	var pts := PackedVector2Array()
	var n := 16
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var v := Vector2(cos(a), sin(a))
		var square := 1.0 / maxf(absf(v.x), absf(v.y))
		var w := 1.0 + 0.05 * sin(a * 3.0 + ph)
		# Lying on the plane: a touch of vertical squash.
		pts.append(c + Vector2(v.x, v.y * 0.90) * minf(square, 1.35) * w * half + off)
	return pts


func _ground_pool(centre: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(21):
		var a := TAU * float(i) / 20.0
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	if minf(size.x, size.y) <= 12.0:
		return
	var c := size * 0.5
	# A silhouette copy offset by (2, 3.5) is not a cast shadow — it hid under
	# the token and left the stud floating. The house convention is a separate
	# wide flat ground pool at the base (see EventHelm / CoinProp).
	_ground_pool(c + Vector2(0, size.y * 0.40), size.x * 0.58, size.y * 0.13,
		Color(0, 0, 0, 0.30))
	_ground_pool(c + Vector2(0, size.y * 0.40), size.x * 0.80, size.y * 0.19,
		Color(0, 0, 0, 0.10))
	var body := _square(Vector2.ZERO)
	draw_colored_polygon(body, BONE)
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Color(0.32, 0.27, 0.20, 0.85), 1.4, true)
	var offs: Array = []
	var s := size.x * 0.20
	match clampi(value, 1, 6):
		1: offs = [Vector2.ZERO]
		2: offs = [Vector2(-s, -s), Vector2(s, s)]
		3: offs = [Vector2(-s, -s), Vector2.ZERO, Vector2(s, s)]
		4: offs = [Vector2(-s, -s), Vector2(s, -s), Vector2(-s, s), Vector2(s, s)]
		5: offs = [Vector2(-s, -s), Vector2(s, -s), Vector2.ZERO,
			Vector2(-s, s), Vector2(s, s)]
		6: offs = [Vector2(-s, -s), Vector2(s, -s), Vector2(-s, 0),
			Vector2(s, 0), Vector2(-s, s), Vector2(s, s)]
	for o in offs:
		draw_circle(c + Vector2(o.x, o.y * 0.9), size.x * 0.065, INK, true, -1.0, true)
		draw_arc(c + Vector2(o.x, o.y * 0.9), size.x * 0.065, PI * 0.1, PI * 0.6,
			6, Color(1, 1, 1, 0.25), 0.8, true)
