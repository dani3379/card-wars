## RingProp — a soldier's rope quoit (quoits_game stage). Drawn lying on
## the receding plane: a squashed torus with rope-twist strokes and a
## ground pool. `airborne` lifts the squash toward round and drops the
## shadow (the engine animates position/scale; the prop keeps its own
## projection honest, the CoinProp convention). Pure painter.
extends Control

var seed_text := "quoit"
var airborne := false

const ROPE := Color(0.62, 0.52, 0.36)
const ROPE_DARK := Color(0.45, 0.37, 0.25)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if minf(size.x, size.y) <= 10.0:
		return
	var c := size * 0.5
	var rx := size.x * 0.44
	var squash := 0.88 if airborne else 0.56
	var ry := rx * squash
	if not airborne:
		var pool := PackedVector2Array()
		for i in range(16):
			var a := TAU * float(i) / 16.0
			pool.append(c + Vector2(2, 4) + Vector2(cos(a) * rx * 1.08, sin(a) * ry * 0.9))
		draw_colored_polygon(pool, Color(0, 0, 0, 0.26))
	# The rope body: a thick elliptical ring.
	var w := size.x * 0.16
	var pts := PackedVector2Array()
	for i in range(28):
		var a := TAU * float(i) / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	pts.append(pts[0])
	draw_polyline(pts, ROPE_DARK, w + 2.5, true)
	draw_polyline(pts, ROPE, w, true)
	# Twist strokes around the ring, and a lit top arc.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	for i in range(10):
		var a := TAU * float(i) / 10.0 + rng.randf() * 0.2
		var p := c + Vector2(cos(a) * rx, sin(a) * ry)
		var t := Vector2(-sin(a), cos(a) * squash).normalized()
		draw_line(p - t * w * 0.45 + Vector2(1.5, -1.0),
			p + t * w * 0.45 + Vector2(-1.5, 1.0),
			Color(ROPE_DARK.r, ROPE_DARK.g, ROPE_DARK.b, 0.8), 1.4, true)
	draw_arc(c, rx, PI * 1.1, PI * 1.9, 14, Color(1, 1, 1, 0.16), w * 0.4, true)
