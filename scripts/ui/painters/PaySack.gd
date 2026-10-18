## PaySack — the drowned courier's pay-satchel, still wet. Side view on the
## plate: a slumped leather body, the flap thrown back (it stands OPEN —
## the game is drawing from it), a strap trailing, stitching, and the
## water it will never quite dry of, darkening its lower third. Pure
## painter; the Event scene owns the draw interaction.
extends Control

var seed_text := "sack"

const LEATHER := Color(0.240, 0.165, 0.105)
const LEATHER_DK := Color(0.130, 0.088, 0.056)
const WET := Color(0.100, 0.072, 0.050)
const THREAD := Color(0.46, 0.36, 0.22, 0.6)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if minf(size.x, size.y) <= 30.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var cx := size.x * 0.5
	var base_y := size.y - 12.0
	var top_y := base_y - size.y * 0.72
	# Ground shadow.
	var sh := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		sh.append(Vector2(cx + cos(a) * size.x * 0.46, base_y + 5.0 + sin(a) * 8.0))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	# Body: a slumped rounded trapezoid — wide at the foot, narrowing to
	# the open mouth, side seams wobbling like wet leather does.
	var pts := PackedVector2Array()
	for i in range(5):
		var t := float(i) / 4.0
		pts.append(Vector2(
			cx - size.x * lerpf(0.42, 0.26, t) + sin(t * 5.0 + ph) * 3.0,
			lerpf(base_y, top_y, t)))
	for i in range(1, 4):
		var t := float(i) / 3.0
		pts.append(Vector2(cx + size.x * lerpf(-0.26, 0.26, t),
			top_y + sin(t * PI) * 4.0))
	for i in range(1, 5):
		var t := float(i) / 4.0
		pts.append(Vector2(
			cx + size.x * lerpf(0.26, 0.42, t) + sin(t * 4.0 + ph * 1.7) * 3.0,
			lerpf(top_y, base_y, t)))
	draw_colored_polygon(pts, LEATHER)
	# The wet lower third — river water it never dried of.
	var wet := PackedVector2Array()
	wet.append(Vector2(cx - size.x * 0.41, base_y))
	wet.append(Vector2(cx + size.x * 0.41, base_y))
	for i in range(9):
		var t := float(i) / 8.0
		wet.append(Vector2(cx + size.x * 0.40 - t * size.x * 0.80,
			base_y - size.y * 0.17 + sin(t * 9.0 + ph) * 4.0))
	draw_colored_polygon(wet, WET)
	# The mouth stands open — the game is drawing from it.
	var mpts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		mpts.append(Vector2(cx + cos(a) * size.x * 0.24, top_y + sin(a) * 6.5))
	draw_colored_polygon(mpts, Color(0.06, 0.04, 0.03))
	# The flap, thrown back over the right shoulder, buckle swinging free —
	# the satchel cue that separates a courier's bag from a cook's pot.
	var flap := PackedVector2Array([
		Vector2(cx - size.x * 0.22, top_y + 2.0),
		Vector2(cx + size.x * 0.26, top_y - 3.0),
		Vector2(cx + size.x * 0.46, top_y + size.y * 0.24),
		Vector2(cx + size.x * 0.32, top_y + size.y * 0.36),
		Vector2(cx - size.x * 0.04, top_y + size.y * 0.14)])
	draw_colored_polygon(flap, LEATHER_DK)
	var flap_line := flap.duplicate()
	flap_line.append(flap[0])
	draw_polyline(flap_line, Color(0.08, 0.055, 0.035), 1.6, true)
	for i in range(4):
		var t := 0.15 + 0.22 * float(i)
		var p := flap[2].lerp(flap[3], t)
		draw_line(p, p + Vector2(-3.0, -4.0), THREAD, 1.4, true)
	draw_arc(Vector2(cx + size.x * 0.36, top_y + size.y * 0.31), 5.0,
		0.0, TAU, 10, Color(0.62, 0.48, 0.22), 2.2, true)
	# Strap trailing off toward the water it came from.
	var strap := PackedVector2Array()
	for i in range(8):
		var t := float(i) / 7.0
		strap.append(Vector2(cx + size.x * (0.34 + t * 0.26),
			base_y - 4.0 + sin(t * 5.0 + ph) * 5.0))
	draw_polyline(strap, LEATHER_DK, 5.0, true)
	# Stitching along the body seam.
	for i in range(5):
		var sx := cx - size.x * 0.24 + float(i) * size.x * 0.12
		draw_line(Vector2(sx, base_y - size.y * 0.32),
			Vector2(sx + 4.0, base_y - size.y * 0.28), THREAD, 1.5, true)
