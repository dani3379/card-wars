## GibbetPost — the old gallows at the quoits green (quoits_game stage).
## Nobody hangs from it anymore; its empty chain is the game's wind gauge:
## `lean` (-1 / 0 / 1) swings the hanging links downwind, and the crow
## perches on the arm ONLY in a dead calm — two honest tells for one
## truth. The engine tweens `sway` (a small live flutter added to the
## lean) and calls queue_redraw(); Reduce Motion holds sway at zero.
## Same school as EventHelm: pure painter, seeded weathering, cabinet
## contact shadow. (Reworked 2026-07-20 — the first pass was two beige
## rectangles and a bubble chain: no grain, no joinery, no weight.)
extends Control

var seed_text := "gibbet"
var lean := 0.0        # -1..1 — the baked wind, mirrored by the chain
var sway := 0.0        # live flutter the engine may tween; 0 under RM
var crow := true       # perched only in a calm

const WOOD := Color(0.285, 0.225, 0.155)
const WOOD_LIT := Color(0.42, 0.345, 0.245)
const WOOD_SILVER := Color(0.46, 0.43, 0.37)   # weathered-grey crown wood
const EDGE_INK := Color(0.075, 0.055, 0.038)
const IRON := Color(0.24, 0.25, 0.28)
const IRON_LIT := Color(0.48, 0.50, 0.55)
const RUST := Color(0.44, 0.26, 0.14, 0.45)
const CHAIN_LINK := Color(0.58, 0.60, 0.66)
const CHAIN_DK := Color(0.30, 0.31, 0.35)
const CHAIN_SHEEN := Color(0.88, 0.90, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _beam(a: Vector2, b: Vector2, half_w: float, col: Color,
		rng: RandomNumberGenerator, grain := 3) -> void:
	# A timber drawn as a quad with edge ink, a lit face line, and long
	# wavy grain strokes — the difference between wood and a rectangle.
	var dirn := (b - a).normalized()
	var perp := Vector2(-dirn.y, dirn.x) * half_w
	var quad := PackedVector2Array([a - perp, b - perp, b + perp, a + perp])
	draw_colored_polygon(quad, col)
	var closed := quad.duplicate()
	closed.append(quad[0])
	draw_polyline(closed, EDGE_INK, 1.6, true)
	# Lit upper/left face.
	draw_line(a - perp * 0.72, b - perp * 0.72,
		Color(WOOD_LIT.r, WOOD_LIT.g, WOOD_LIT.b, 0.75), maxf(half_w * 0.32, 1.4), true)
	# Shaded under/right face.
	draw_line(a + perp * 0.74, b + perp * 0.74,
		Color(0, 0, 0, 0.26), maxf(half_w * 0.30, 1.2), true)
	# Grain: long wavering strokes along the beam.
	var length := a.distance_to(b)
	for g in range(grain):
		var f := rng.randf_range(-0.55, 0.55)
		var wob := rng.randf_range(0.6, 1.6)
		var pts := PackedVector2Array()
		for i in range(7):
			var t := float(i) / 6.0
			pts.append(a + dirn * (length * lerpf(0.06, 0.94, t)) \
				+ perp * f + perp.normalized() * sin(t * 9.0 + f * 20.0) * wob)
		draw_polyline(pts, Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.30), 1.0, true)


func _draw() -> void:
	if minf(size.x, size.y) <= 30.0:
		return
	var u := size.x / 160.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	# ── ground: shadow pool, footing stones, a grass tuft ────────────────
	var foot := Vector2(44.0 * u, size.y - 10.0 * u)
	var pool := PackedVector2Array()
	for i in range(18):
		var a := TAU * float(i) / 18.0
		pool.append(foot + Vector2(cos(a) * 46.0 * u, sin(a) * 9.0 * u))
	draw_colored_polygon(pool, Color(0, 0, 0, 0.32))
	for i in range(3):
		var sp := foot + Vector2(rng.randf_range(-18.0, 20.0) * u, rng.randf_range(-2.0, 3.0) * u)
		var sr := rng.randf_range(3.5, 6.0) * u
		draw_circle(sp + Vector2(1, 1.5) * u, sr, Color(0, 0, 0, 0.30), true, -1.0, true)
		draw_circle(sp, sr, Color(0.36, 0.34, 0.31), true, -1.0, true)
		draw_circle(sp + Vector2(-sr * 0.3, -sr * 0.35), sr * 0.4,
			Color(0.55, 0.53, 0.49, 0.6), true, -1.0, true)
	for i in range(4):
		var gp := foot + Vector2(rng.randf_range(-30.0, 30.0) * u, rng.randf_range(0.0, 4.0) * u)
		draw_line(gp, gp + Vector2(rng.randf_range(-2.0, 2.0), -rng.randf_range(5.0, 9.0)) * u,
			Color(0.30, 0.32, 0.18, 0.55), 1.2 * u, true)

	# ── timbers: upright, arm, knee brace — real beams with grain ───────
	var post_top := Vector2(44.0 * u, 24.0 * u)
	_beam(foot + Vector2(0, 2.0 * u), post_top, 9.0 * u, WOOD, rng, 4)
	# Weathered-silver crown where rain has bleached the end grain.
	draw_colored_polygon(PackedVector2Array([
		post_top + Vector2(-9, 0) * u, post_top + Vector2(9, 0) * u,
		post_top + Vector2(9, 7) * u, post_top + Vector2(-9, 7) * u]),
		Color(WOOD_SILVER.r, WOOD_SILVER.g, WOOD_SILVER.b, 0.45))
	# Checks and splits.
	for i in range(3):
		var y := rng.randf_range(0.30, 0.80)
		var cp := post_top.lerp(foot, y) + Vector2(rng.randf_range(-4.0, 4.0) * u, 0)
		var dn := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(9.0, 16.0)) * u
		draw_line(cp, cp + dn, EDGE_INK, 1.6 * u, true)
		draw_line(cp + dn, cp + dn + Vector2(dn.x * 0.4, dn.y * 0.35),
			Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.6), 1.0 * u, true)
	var arm_end := Vector2(140.0 * u, 30.0 * u)
	_beam(Vector2(38.0 * u, 30.0 * u), arm_end, 6.5 * u, WOOD, rng, 2)
	_beam(Vector2(50.0 * u, 68.0 * u), Vector2(98.0 * u, 34.0 * u), 4.5 * u, WOOD, rng, 1)

	# ── iron joinery: strap at the joint, eye at the arm end ────────────
	var joint := Vector2(44.0 * u, 30.0 * u)
	draw_rect(Rect2(joint + Vector2(-12.0, -8.0) * u, Vector2(24.0, 18.0) * u),
		IRON)
	draw_rect(Rect2(joint + Vector2(-12.0, -8.0) * u, Vector2(24.0, 3.0) * u),
		Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.5))
	for bp in [Vector2(-7, -3), Vector2(6, -3), Vector2(-7, 6), Vector2(6, 6)]:
		draw_circle(joint + bp * u, 1.6 * u, Color(0.09, 0.09, 0.11), true, -1.0, true)
		draw_circle(joint + bp * u + Vector2(-0.5, -0.5) * u, 0.6 * u,
			Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.8), true, -1.0, true)
	# Rust bleeding down the post from the strap.
	draw_line(joint + Vector2(-6, 9) * u, joint + Vector2(-6, 26) * u, RUST, 2.4 * u, true)
	draw_line(joint + Vector2(5, 9) * u, joint + Vector2(4, 20) * u,
		Color(RUST.r, RUST.g, RUST.b, 0.30), 1.8 * u, true)
	# The eye the chain hangs from.
	var eye := Vector2(128.0 * u, 36.0 * u)
	draw_circle(eye, 4.2 * u, CHAIN_DK, false, 2.6 * u, true)
	draw_circle(eye + Vector2(-1.2, -1.2) * u, 1.0 * u,
		Color(CHAIN_SHEEN.r, CHAIN_SHEEN.g, CHAIN_SHEEN.b, 0.6), true, -1.0, true)

	# ── the chain: interlocked links swung downwind ──────────────────────
	var top := eye + Vector2(0, 4.0 * u)
	var ang: float = clampf(lean + sway, -1.4, 1.4) * 0.5
	var dir := Vector2(sin(ang), cos(ang))
	var perp := Vector2(dir.y, -dir.x)
	var links := 7
	# A faint plumb line marks true-vertical, so the lean is measurable.
	draw_line(top, top + Vector2(0, 1) * (10.0 + float(links) * 11.0) * u,
		Color(0.9, 0.9, 0.86, 0.10), 1.0, true)
	for i in range(links):
		var p := top + dir * (8.0 + float(i) * 11.0) * u
		var facing := i % 2 == 0
		# Alternating link orientation: face-on ovals and edge-on bars —
		# the interlock read a real chain has.
		if facing:
			var pts := PackedVector2Array()
			for k in range(14):
				var a := TAU * float(k) / 14.0
				pts.append(p + dir * sin(a) * 6.4 * u + perp * cos(a) * 4.4 * u)
			pts.append(pts[0])
			draw_polyline(pts, CHAIN_DK, 3.6 * u, true)
			draw_polyline(pts, CHAIN_LINK, 1.8 * u, true)
			draw_circle(p + Vector2(-1.4, -1.6) * u, 1.1 * u,
				Color(CHAIN_SHEEN.r, CHAIN_SHEEN.g, CHAIN_SHEEN.b, 0.65), true, -1.0, true)
		else:
			draw_line(p - dir * 5.2 * u, p + dir * 5.2 * u, CHAIN_DK, 4.6 * u, true)
			draw_line(p - dir * 4.6 * u, p + dir * 4.6 * u, CHAIN_LINK, 2.2 * u, true)
	var cend := top + dir * (8.0 + float(links) * 11.0) * u
	# The collar — open, empty, honest; heavier than the links.
	draw_arc(cend + Vector2(0, 5.0 * u), 8.0 * u, PI * 0.15, PI * 1.85, 14,
		CHAIN_DK, 5.0 * u, true)
	draw_arc(cend + Vector2(0, 5.0 * u), 8.0 * u, PI * 0.15, PI * 1.85, 14,
		CHAIN_LINK, 2.6 * u, true)
	draw_arc(cend + Vector2(-1.5 * u, 3.5 * u), 8.0 * u, PI * 0.9, PI * 1.35, 6,
		Color(CHAIN_SHEEN.r, CHAIN_SHEEN.g, CHAIN_SHEEN.b, 0.5), 1.4 * u, true)

	# ── the crow: only in a calm ─────────────────────────────────────────
	if crow:
		var c := Vector2(96.0 * u, 20.0 * u)
		# Tail, body, head — a hunched silhouette with one wing notch.
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-10, 7) * u, c + Vector2(-4, -3) * u,
			c + Vector2(1, -5) * u, c + Vector2(6, -3) * u,
			c + Vector2(8, 2) * u, c + Vector2(17, 8) * u,
			c + Vector2(9, 7) * u, c + Vector2(4, 9) * u]),
			Color(0.09, 0.08, 0.10))
		draw_circle(c + Vector2(7.0, -4.5) * u, 3.4 * u, Color(0.09, 0.08, 0.10),
			true, -1.0, true)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(10, -5.5) * u, c + Vector2(16, -3.5) * u,
			c + Vector2(10, -2.5) * u]), Color(0.26, 0.22, 0.15))
		# Wing fold line + one glint in the eye.
		draw_line(c + Vector2(-4, 1) * u, c + Vector2(5, 4) * u,
			Color(0.22, 0.20, 0.24, 0.7), 1.2 * u, true)
		draw_circle(c + Vector2(8.2, -5.2) * u, 0.8 * u,
			Color(0.85, 0.82, 0.7, 0.9), true, -1.0, true)
