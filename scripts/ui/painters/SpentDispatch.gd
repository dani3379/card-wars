## SpentDispatch — the discard pile's face. The deck beside it carries an
## intact WaxSeal (orders still sealed); this paints what the discard IS: a
## dispatch that has been opened and read. A broken seal — two wax halves
## with a crack of paper showing between them, one half knocked askew — and
## ragged read-ink lines below. Replaces four flat Panel strips that read as
## a gray wireframe. Anchored over the pile's front leaf; all geometry
## derives from size, seeded so every fight's mail broke the same way.
extends Control

var wax := Color(0.47, 0.12, 0.09)
var ink := Color(0.24, 0.17, 0.11, 0.55)
var seed_text := "spent"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _half(c: Vector2, r: float, a0: float, a1: float, tilt: float,
		rag: float) -> PackedVector2Array:
	# One broken half: an arc closed by a slightly ragged chord (the break).
	var pts := PackedVector2Array()
	var n := 12
	for i in range(n + 1):
		var a := a0 + (a1 - a0) * float(i) / float(n) + tilt
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	# The chord back across the break line, with a nick midway.
	var mid := (pts[0] + pts[n]) * 0.5 + Vector2(rag, 0)
	pts.append(mid)
	return pts

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20.0 or h < 30.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var dark := Color(wax.r * 0.5, wax.g * 0.5, wax.b * 0.55)

	# ── The broken seal, where the deck's intact one sits: two halves parted
	# around a crack of bare paper, the right half knocked a few degrees off.
	var c := Vector2(w * 0.5, h * 0.30)
	var r := minf(w, h) * 0.185
	var gap := maxf(2.0, r * 0.22)
	var l_c := c + Vector2(-gap, 0)
	var r_c := c + Vector2(gap, rng.randf_range(0.5, 2.0))
	var l_pts := _half(l_c, r, PI * 0.55, PI * 1.45, 0.0, rng.randf_range(-1.2, 1.2))
	var r_pts := _half(r_c, r, -PI * 0.45, PI * 0.45, rng.randf_range(0.08, 0.2),
		rng.randf_range(-1.2, 1.2))
	for pts_v in [l_pts, r_pts]:
		var pts: PackedVector2Array = pts_v
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(0.5, 1.6))
		draw_colored_polygon(sh, Color(0, 0, 0, 0.22))
		draw_colored_polygon(pts, Color(wax.r * 0.86, wax.g * 0.86, wax.b * 0.88))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, Color(dark.r, dark.g, dark.b, 0.7), 1.0, true)
	# A stray chip of wax that fell when it broke.
	draw_circle(c + Vector2(rng.randf_range(-r, r), r * 1.7),
		1.4, Color(wax.r * 0.8, wax.g * 0.8, wax.b * 0.8), true, -1.0, true)

	# ── Read-ink lines below: wavy baselines with nib-weight sway and ragged
	# ends — a letter, not a wireframe. Kept left of the count badge quadrant.
	var y0 := h * 0.56
	var line_gap := maxf(7.0, h * 0.115)
	for li in range(3):
		var y := y0 + float(li) * line_gap
		var end_x := w * rng.randf_range(0.52, 0.82)
		if li == 2:
			end_x = w * rng.randf_range(0.34, 0.5)   # the letter trails off
		var pts := PackedVector2Array()
		var steps := 8
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			pts.append(Vector2(lerpf(8.0, end_x, t),
				y + sin(t * 7.0 + float(li) * 2.1) * 0.8))
		draw_polyline(pts, ink, 1.6, true)
		# Nib pools a touch of ink where the stroke starts.
		draw_circle(pts[0], 1.1, Color(ink.r, ink.g, ink.b, ink.a * 1.3),
			true, -1.0, true)
