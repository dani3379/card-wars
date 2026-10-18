## KnuckleboneDie — a cast bone die for the event table (the Bone Pit's
## dice_run stage). Same school as WaxSeal: a seeded irregular silhouette,
## because every knucklebone cooled in a different hand. The waist pinches
## like a real astragalus. `face` = pip count (1–4), `skull = true` replaces
## the pips with the bust mark. Pure painter — the Event scene owns all
## motion; call queue_redraw() after changing the face.
extends Control

var seed_text := "bone"
var face := 2
var skull := false

const BONE := Color(0.875, 0.845, 0.765)
const INK := Color(0.22, 0.17, 0.12, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _blob(center: Vector2, rx: float, ry: float, n: int = 16) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var amp := 0.05 + rng.randf() * 0.04
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + amp * sin(a * 2.0 + ph) + amp * 0.6 * sin(a * 5.0 + ph * 1.7)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry) * w)
	return pts


func _draw() -> void:
	if minf(size.x, size.y) <= 8.0:
		return
	var c := size * 0.5
	var rx := size.x * 0.5 - 2.0
	# Lying on a receding plane: the body squashes a touch vertically and
	# the cast shadow is a wide flat pool, not a copy of the silhouette.
	var ry := (size.y * 0.5 - 2.0) * 0.88
	# The pool must sit at the body's BASE, not under its middle. Drawn at
	# offset (1.4, 3.4) with ry*0.62 it fell entirely inside the die's own
	# silhouette — on a 56px bone the whole shadow was occluded and the die
	# read as floating. EventHelm/CoinProp are the working reference: a
	# separate wide flat ellipse, below the contact point and wider than the
	# body, so it is actually visible.
	draw_colored_polygon(_blob(c + Vector2(rx * 0.10, ry * 0.92), rx * 1.22, ry * 0.30),
		Color(0, 0, 0, 0.30))
	draw_colored_polygon(_blob(c + Vector2(rx * 0.10, ry * 0.92), rx * 1.70, ry * 0.42),
		Color(0, 0, 0, 0.10))
	# Bone body + the astragalus waist (two soft side shadows pinch it).
	var body := _blob(c, rx, ry)
	draw_colored_polygon(body, BONE)
	draw_colored_polygon(_blob(c + Vector2(-rx * 0.55, 0), rx * 0.34, ry * 0.72, 12),
		Color(0.72, 0.68, 0.58, 0.35))
	draw_colored_polygon(_blob(c + Vector2(rx * 0.55, 0), rx * 0.34, ry * 0.72, 12),
		Color(0.72, 0.68, 0.58, 0.35))
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Color(0.30, 0.25, 0.18, 0.9), 1.6, true)
	if skull:
		# The bust mark: dome, jaw, sockets, teeth — legible at 20px.
		var sc := c + Vector2(0, -1)
		draw_circle(sc + Vector2(0, -1.5), 6.0, INK, true, -1.0, true)
		draw_rect(Rect2(sc + Vector2(-3.5, 2.0), Vector2(7, 4)), INK, true)
		draw_circle(sc + Vector2(-2.3, -2.4), 1.5, BONE, true, -1.0, true)
		draw_circle(sc + Vector2(2.3, -2.4), 1.5, BONE, true, -1.0, true)
		for i in range(3):
			draw_line(sc + Vector2(-2.0 + float(i) * 2.0, 3.2),
				sc + Vector2(-2.0 + float(i) * 2.0, 5.6), BONE, 0.8, true)
	else:
		var offs: Array = []
		match clampi(face, 1, 4):
			1: offs = [Vector2.ZERO]
			2: offs = [Vector2(-4.5, -4.5), Vector2(4.5, 4.5)]
			3: offs = [Vector2(-5, -5), Vector2.ZERO, Vector2(5, 5)]
			4: offs = [Vector2(-4.5, -4.5), Vector2(4.5, -4.5),
				Vector2(-4.5, 4.5), Vector2(4.5, 4.5)]
		for o in offs:
			draw_circle(c + o, 2.1, INK, true, -1.0, true)
			# Pressed pip: a lit lower edge, same trick as the wax stamp ring.
			draw_arc(c + o, 2.1, PI * 0.1, PI * 0.6, 6, Color(1, 1, 1, 0.25), 0.8, true)
