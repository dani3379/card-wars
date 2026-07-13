## WaxSeal — extracted from Card2D.gd (backend restructure 2026-07-14).
## A pressed wax seal, fully procedural. The silhouette is a seeded blob —
## every seal cools a little differently — with a cooled-rim edge, a
## stamped impression ring whose lit wall faces away from the top-left
## light, and a matte sheen. No specular ball highlights anywhere: this is
## wax on paper, not polished glass.
extends Control

var wax := Color(0.5, 0.15, 0.1)
var seed_text := "seal"
var simple_mode := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _blob(center: Vector2, base_r: float, n: int = 28) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph1 := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var amp1 := 0.030 + rng.randf() * 0.022
	var amp2 := 0.020 + rng.randf() * 0.016
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + amp1 * sin(a * 3.0 + ph1) + amp2 * sin(a * 7.0 + ph2)
		pts.append(center + Vector2(cos(a), sin(a)) * base_r * w)
	return pts

func _draw() -> void:
	var min_dim := minf(size.x, size.y)
	if min_dim <= 6.0:
		return
	var center := size * 0.5
	var base_r := min_dim * 0.5 - 1.5
	if simple_mode:
		# Battlefield seals are only 38px wide and up to 32 of them can be
		# visible. Keep the same wax silhouette/pressed face in six commands;
		# the second shadow, micro-nicks and double impression are sub-pixel
		# there but otherwise replay every frame in GL Compatibility.
		var simple_body := _blob(center, base_r, 18)
		draw_colored_polygon(_blob(center + Vector2(0.4, 1.8),
			base_r * 1.02, 18), Color(0, 0, 0, 0.28))
		draw_colored_polygon(simple_body, wax)
		var simple_closed := simple_body.duplicate()
		simple_closed.append(simple_body[0])
		draw_polyline(simple_closed,
			Color(wax.r * 0.50, wax.g * 0.50, wax.b * 0.54, 0.85), 1.8, true)
		var simple_ring := base_r * 0.70
		draw_arc(center, simple_ring, 0, TAU, 24,
			Color(wax.r * 0.42, wax.g * 0.42, wax.b * 0.46, 0.62), 1.5, true)
		draw_circle(center, simple_ring - 2.0,
			Color(0, 0, 0, 0.30), true, -1.0, true)
		draw_arc(center, base_r * 0.54, PI * 1.02, PI * 1.50, 10,
			Color(1.0, 0.96, 0.88, 0.12), 1.8, true)
		return
	# 1 — cast shadow: two stacked soft blobs anchor the seal to the page.
	draw_colored_polygon(_blob(center + Vector2(0.6, 2.4), base_r * 1.03),
		Color(0, 0, 0, 0.26))
	draw_colored_polygon(_blob(center + Vector2(0.3, 1.2), base_r * 1.01),
		Color(0, 0, 0, 0.20))
	# 2 — the wax body.
	var body := _blob(center, base_r)
	draw_colored_polygon(body, wax)
	# 3 — cooled rim: the darker edge line doubles as silhouette AA
	# (draw_colored_polygon has no antialiased flag; the AA polyline
	# straddling the boundary smooths it).
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed,
		Color(wax.r * 0.50, wax.g * 0.50, wax.b * 0.54, 0.85), 2.2, true)
	# 4 — stamp impression: dark groove ring, lit wall on the side away
	# from the top-left light (+y is down: 0.04..0.36 TAU = lower-right).
	var ring_r := base_r * 0.72
	draw_arc(center, ring_r, 0, TAU, 40,
		Color(wax.r * 0.42, wax.g * 0.42, wax.b * 0.46, 0.65), 1.8, true)
	draw_arc(center, ring_r + 1.5, TAU * 0.04, TAU * 0.36, 26,
		Color(minf(wax.r * 1.45 + 0.06, 1.0), minf(wax.g * 1.45 + 0.06, 1.0),
		minf(wax.b * 1.45 + 0.06, 1.0), 0.40), 1.2, true)
	# 5 — pressed face, sunk darker so the light numeral pops off it. This
	# face sits directly under the stat label on both the 56px hand seal and
	# the 38px battlefield token; a deeper well is what lets the brightened
	# field numeral read over dark art (see _build_orb_number_label).
	draw_circle(center, ring_r - 2.5, Color(0, 0, 0, 0.32), true, -1.0, true)
	# 6 — matte sheen: one soft crescent toward the light (PI..1.5PI =
	# left → up-left → up), wide and dim — wax, not glass.
	draw_arc(center, base_r * 0.55, PI * 1.02, PI * 1.55, 18,
		Color(1.0, 0.96, 0.88, 0.13), 2.2, true)
	# 7 — seeded micro-nicks: cooled-wax imperfections.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 7
	for i in range(3):
		var a := rng.randf() * TAU
		var rr := base_r * (0.30 + rng.randf() * 0.45)
		draw_circle(center + Vector2(cos(a), sin(a)) * rr,
			0.8 + rng.randf() * 1.0,
			Color(1, 1, 1, 0.05 + rng.randf() * 0.05), true, -1.0, true)
