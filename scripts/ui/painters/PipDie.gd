## PipDie — the bone die tile for Crown & Pike (the road's Crown-and-Anchor
## retell): a bold rounded-square tile struck in ivory/bone, built to read
## hard against the dark gaming cloth (CastPatch's HIDE). Draws ONLY the
## tile — the war-symbol is a WarPip the game layers on top, and the game
## scene owns all motion (tumble, settle, deal). Pure painter.
##
## seed_text — seeds the tile's carved wear so no two dice match.
## lit        — a just-rolled / winning die: brighter body + a warm accent
##              halo, so a settled winner pops off the cloth.
## blank      — mid-tumble: a soft motion-smear instead of a settled face
##              (the game rests a WarPip on top once this goes false).
## accent     — the riding WarPip's tint; borrowed only for the halo glow
##              and a thin rim thread, so a lit die echoes its own symbol.
extends Control

var seed_text: String = "die":
	set(v):
		seed_text = v
		queue_redraw()
var lit: bool = false:
	set(v):
		lit = v
		queue_redraw()
var blank: bool = true:
	set(v):
		blank = v
		queue_redraw()
var accent: Color = Color(0.85, 0.68, 0.25):
	set(v):
		accent = v
		queue_redraw()

# Bone/ivory, not gold — the die must stay legible against the warm cloth.
const RIM_INK := Color(0.27, 0.18, 0.08, 0.95)
const BONE_BASE := Color(0.86, 0.80, 0.66)
const BONE_LIT := Color(0.94, 0.90, 0.78)
const BONE_DARK := Color(0.62, 0.55, 0.42)
const GLINT := Color(1.0, 0.97, 0.90)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _arc(center: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a := lerpf(a0, a1, float(i) / float(n))
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


func _ell(c: Vector2, rx: float, ry: float, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## A true rounded square (flat sides, quarter-circle corners) — dice read as
## crisp tiles, not the blobby squircle CastPatch uses for its cloth.
func _rounded_square(c: Vector2, hx: float, hy: float, r: float, n_corner: int = 8) -> PackedVector2Array:
	var rr := minf(r, minf(hx, hy) * 0.98)
	var pts := PackedVector2Array()
	pts.append(c + Vector2(-hx + rr, -hy))
	pts.append(c + Vector2(hx - rr, -hy))
	pts.append_array(_arc(c + Vector2(hx - rr, -hy + rr), rr, -PI * 0.5, 0.0, n_corner))
	pts.append(c + Vector2(hx, hy - rr))
	pts.append_array(_arc(c + Vector2(hx - rr, hy - rr), rr, 0.0, PI * 0.5, n_corner))
	pts.append(c + Vector2(-hx + rr, hy))
	pts.append_array(_arc(c + Vector2(-hx + rr, hy - rr), rr, PI * 0.5, PI, n_corner))
	pts.append(c + Vector2(-hx, -hy + rr))
	pts.append_array(_arc(c + Vector2(-hx + rr, -hy + rr), rr, PI, PI * 1.5, n_corner))
	return pts


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s < 8.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	var c := Vector2(size.x * 0.5, size.y * 0.5 - s * 0.04)
	var half := s * 0.5 - s * 0.08
	var rr := half * 0.26
	var lw_thin := maxf(1.2, s * 0.018)

	var base_col := BONE_BASE
	var lit_col := BONE_LIT
	var dark_col := BONE_DARK
	if lit:
		base_col = base_col.lightened(0.10)
		lit_col = lit_col.lightened(0.06)

	# Warm halo behind everything — only the lit/winning tile gets one.
	if lit:
		for i in range(3):
			var k := 3 - i
			draw_circle(c, half * (1.15 + 0.22 * float(k)),
				Color(accent.r, accent.g, accent.b, 0.05 + 0.03 * float(3 - k)),
				true, -1.0, true)

	# Ground-contact shadow: wide, soft, sitting just below the tile.
	draw_colored_polygon(
		_ell(Vector2(c.x, c.y + half + s * 0.07), half * 1.05, half * 0.28, 28),
		Color(0, 0, 0, 0.30))

	# The die body.
	var outer := _rounded_square(c, half, half, rr, 8)
	draw_colored_polygon(outer, base_col)

	# Pooled light upper-left, tarnish/shadow crescent lower-right — the
	# 3-value modeling that reads as a solid tile instead of a flat swatch.
	draw_circle(c + Vector2(-half * 0.20, -half * 0.22), half * 0.58,
		Color(lit_col.r, lit_col.g, lit_col.b, 0.55), true, -1.0, true)
	draw_circle(c + Vector2(half * 0.22, half * 0.24), half * 0.55,
		Color(dark_col.r, dark_col.g, dark_col.b, 0.42), true, -1.0, true)

	# Bevel: a lit edge along top-left, a dark edge along bottom-right —
	# traced along the SAME rounded-rect boundary so it can't drift off-form.
	var hi_edge := PackedVector2Array()
	hi_edge.append(c + Vector2(-half, half * 0.32))
	hi_edge.append(c + Vector2(-half, -half + rr))
	hi_edge.append_array(_arc(c + Vector2(-half + rr, -half + rr), rr, PI, PI * 1.5, 6))
	hi_edge.append(c + Vector2(half * 0.32, -half))
	draw_polyline(hi_edge, Color(GLINT.r, GLINT.g, GLINT.b, 0.55), maxf(1.4, s * 0.030), true)

	var lo_edge := PackedVector2Array()
	lo_edge.append(c + Vector2(half, -half * 0.32))
	lo_edge.append(c + Vector2(half, half - rr))
	lo_edge.append_array(_arc(c + Vector2(half - rr, half - rr), rr, 0.0, PI * 0.5, 6))
	lo_edge.append(c + Vector2(-half * 0.32, half))
	draw_polyline(lo_edge, Color(RIM_INK.r, RIM_INK.g, RIM_INK.b, 0.45), maxf(1.4, s * 0.030), true)

	# The ink outline that pins the whole tile down.
	var closed := outer.duplicate()
	closed.append(outer[0])
	draw_polyline(closed, RIM_INK, maxf(1.5, s * 0.05), true)

	# A lit die's rim carries a thread of its symbol's colour.
	if lit:
		var inset_rim := _rounded_square(c, half - lw_thin * 1.4, half - lw_thin * 1.4,
			maxf(1.0, rr - lw_thin), 6)
		var inset_closed := inset_rim.duplicate()
		inset_closed.append(inset_rim[0])
		draw_polyline(inset_closed, Color(accent.r, accent.g, accent.b, 0.55), lw_thin, true)

	# The inset inner panel — the "cell" the game's WarPip symbol sits in.
	var in_half := half * 0.76
	var in_r := rr * 0.72
	var inner := _rounded_square(c, in_half, in_half, in_r, 8)
	draw_colored_polygon(inner, base_col.darkened(0.16))
	var inner_closed := inner.duplicate()
	inner_closed.append(inner[0])
	draw_polyline(inner_closed, Color(RIM_INK.r, RIM_INK.g, RIM_INK.b, 0.35), 1.0, true)

	# Seeded wear: 1-2 faint carved nicks/freckles, kept off-center so a
	# symbol resting in the panel is never obscured.
	var n_wear := 1 if rng.randf() < 0.5 else 2
	for i in range(n_wear):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.60, 0.88)
		var p := c + Vector2(cos(a) * half * d, sin(a) * half * d)
		if rng.randf() < 0.5:
			draw_circle(p, maxf(1.0, s * 0.018),
				Color(dark_col.r, dark_col.g, dark_col.b, 0.32), true, -1.0, true)
		else:
			var dir := Vector2(cos(a + 1.4), sin(a + 1.4)) * s * 0.045
			draw_line(p - dir * 0.5, p + dir * 0.5,
				Color(RIM_INK.r, RIM_INK.g, RIM_INK.b, 0.25), maxf(1.0, s * 0.012), true)

	# Mid-tumble: the face hasn't settled — a faint horizontal smear instead
	# of a clean panel (the game rests a WarPip here once blank goes false).
	if blank:
		for i in range(3):
			var t := float(i) - 1.0
			var yy := t * in_half * 0.42 + rng.randf_range(-2.0, 2.0)
			var span := in_half * rng.randf_range(1.2, 1.55)
			var xo := rng.randf_range(-in_half * 0.15, in_half * 0.15)
			draw_line(c + Vector2(-span * 0.5 + xo, yy), c + Vector2(span * 0.5 + xo, yy),
				Color(GLINT.r, GLINT.g, GLINT.b, 0.22), maxf(1.2, s * 0.022), true)
