## CoinProp — the road's coinage for the event stages (the pot heap, the
## spinner, the shell game's stake, flying bank coins). One mint everywhere:
## the Old King's — his crowned profile on heads, crossed pikes on tails, a
## milled rim, and seeded wear so no two pieces match. Pure painter — the
## Event scene owns all motion.
##
## Modes:
##   lying   — cabinet projection handled HERE: face squashes to an ellipse,
##             the edge shows its thickness below, and the ground pool is
##             drawn in. Do NOT also scale the node.
##   face_t  — 1.0 face-on → 0.0 edge-on. The spinner tweens THIS instead of
##             scale.x, so the thin moment flashes the milled edge instead of
##             a squashed picture. Setter redraws.
##   tails   — the pikes face (the spinner's bust lands tails-up).
##   worn    — the clerk's pay-token: stamp and milling rubbed to a ghost.
extends Control

var seed_text := "coin"
var lying := false:
	set(v):
		lying = v
		queue_redraw()
var worn := false:
	set(v):
		worn = v
		queue_redraw()
var tails := false:
	set(v):
		tails = v
		queue_redraw()
var face_t := 1.0:
	set(v):
		face_t = clampf(v, 0.0, 1.0)
		queue_redraw()
var shadow := true

# Aged gold with road-tarnish — warm, never lemon. Rim ink matches the kit.
const RIM_INK := Color(0.27, 0.18, 0.08, 0.95)
const GOLD_LIT := Color(0.89, 0.74, 0.40)
const GOLD_MID := Color(0.71, 0.55, 0.27)
const GOLD_DIM := Color(0.49, 0.36, 0.16)
const STAMP := Color(0.34, 0.24, 0.10, 0.88)
const GLINT := Color(1.0, 0.95, 0.78)

const SQUASH := 0.74  # the stage's one camera pitch (cabinet convention)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ell(c: Vector2, rx: float, ry: float, n: int = 40,
		a0: float = 0.0, a1: float = TAU) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a := a0 + (a1 - a0) * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.0
	if r <= 4.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var stamp_rot := rng.randf_range(-0.22, 0.22)
	var c := size * 0.5
	var squash := SQUASH if lying else 1.0
	var ry := r * squash
	var w := clampf(face_t, 0.03, 1.0)
	var rx := r * w
	var th := maxf(2.0, r * 0.20) if lying else 0.0

	# Ground pool first — wide and flat, never a silhouette copy.
	if lying and shadow:
		draw_colored_polygon(
			_ell(c + Vector2(r * 0.06, th + ry * 0.30), rx * 1.12, ry * 0.55, 24),
			Color(0, 0, 0, 0.28))

	# The edge's thickness (lying): the side band the top face overlaps.
	if lying:
		var side := _ell(c, rx, ry, 24, 0.0, PI)
		var lower := _ell(c + Vector2(0, th), rx, ry, 24, 0.0, PI)
		lower.reverse()
		side.append_array(lower)
		draw_colored_polygon(side, GOLD_DIM.darkened(0.25))
		draw_polyline(_ell(c + Vector2(0, th), rx, ry, 24, 0.0, PI),
			RIM_INK, maxf(1.1, r * 0.06), true)
		if r >= 10.0 and not worn:
			for i in range(7):
				var a := PI * (0.16 + 0.68 * float(i) / 6.0)
				var p := Vector2(cos(a) * rx, sin(a) * ry)
				draw_line(c + p, c + p + Vector2(0, th),
					RIM_INK * Color(1, 1, 1, 0.45), 1.0, true)

	# The face.
	draw_colored_polygon(_ell(c, rx, ry, 40), GOLD_MID)
	# Pooled light upper-left, tarnish crescent lower-right.
	draw_colored_polygon(
		_ell(c + Vector2(-rx * 0.16, -ry * 0.20), rx * 0.66, ry * 0.66, 28),
		Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, 0.55))
	draw_polyline(_ell(c, rx * 0.80, ry * 0.80, 22, -0.25, PI * 0.72),
		Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, 0.55), maxf(1.5, r * 0.24), true)
	# Rim ink + the pale inner rim ring.
	draw_polyline(_ell(c, rx, ry, 48), RIM_INK, maxf(1.2, r * 0.075), true)
	if r >= 9.0:
		draw_polyline(_ell(c, rx * 0.84, ry * 0.84, 36),
			Color(GLINT.r, GLINT.g, GLINT.b, 0.12 if worn else 0.30),
			1.0, true)
	# Milling ticks just inside the rim.
	if r >= 11.0 and not worn and w > 0.30:
		var n_tick := clampi(int(r * 0.8), 8, 18)
		for i in range(n_tick):
			var a := TAU * float(i) / float(n_tick)
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + Vector2(dir.x * rx * 0.86, dir.y * ry * 0.86),
				c + Vector2(dir.x * rx * 0.96, dir.y * ry * 0.96),
				RIM_INK * Color(1, 1, 1, 0.5), 1.0, true)

	# The stamp — skipped while the coin is turning thin.
	if r >= 11.0 and w > 0.30:
		if worn:
			# Rubbed to a ghost: the profile is almost gone, which is the point.
			_draw_heads(c, rx * 0.9, ry * 0.9, stamp_rot,
				Color(STAMP.r, STAMP.g, STAMP.b, 0.10))
		elif tails:
			_draw_tails(c, rx, ry, r)
		else:
			_draw_heads(c, rx, ry, stamp_rot, STAMP)

	# Seeded wear: two tarnish freckles + one rim nick (never on the token —
	# the token is worn EVERYWHERE, freckles would read as dirt).
	if not worn and r >= 11.0 and w > 0.5:
		for i in range(2):
			var fa := rng.randf() * TAU
			var fr := rng.randf_range(0.25, 0.62)
			draw_circle(c + Vector2(cos(fa) * rx * fr, sin(fa) * ry * fr),
				maxf(1.0, r * 0.07), Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, 0.4),
				true, -1.0, true)
		var na := rng.randf() * TAU
		draw_polyline(_ell(c, rx, ry, 6, na, na + 0.35),
			GOLD_DIM.darkened(0.1), maxf(1.4, r * 0.09), true)

	# The one specular that makes metal read.
	draw_polyline(_ell(c, rx * 0.94, ry * 0.94, 10, PI * 1.12, PI * 1.42),
		Color(GLINT.r, GLINT.g, GLINT.b, 0.30 if worn else 0.55),
		maxf(1.2, r * 0.08), true)

	# Edge-on flash: as the face closes, the milled edge takes over.
	if not lying and w < 0.35:
		var k := (0.35 - w) / 0.35
		var bw := maxf(2.5, r * 0.17) * k
		draw_rect(Rect2(c + Vector2(-bw * 0.5, -ry), Vector2(bw, ry * 2.0)),
			Color(GOLD_LIT.r, GOLD_LIT.g, GOLD_LIT.b, k), true)
		if r >= 10.0:
			for i in range(4):
				var ty := -ry + ry * 2.0 * (0.2 + 0.2 * float(i))
				draw_line(c + Vector2(-bw * 0.5, ty), c + Vector2(bw * 0.5, ty),
					Color(RIM_INK.r, RIM_INK.g, RIM_INK.b, 0.5 * k), 1.0, true)


## The Old King, facing the way he marched: profile and three-point crown,
## pressed as one dark shape with a thin lit offset (struck metal, not print).
func _draw_heads(c: Vector2, rx: float, ry: float, rot: float, col: Color) -> void:
	# One clockwise outline, crown spikes walked right-to-left; the crown-front
	# base sits LEFT of the last spike or the closing edge bow-ties (a
	# self-intersecting polygon fails triangulation and the fill vanishes).
	var prof := PackedVector2Array([
		Vector2(-0.13, -0.28), Vector2(-0.11, -0.25), Vector2(-0.29, -0.07),
		Vector2(-0.20, 0.01), Vector2(-0.25, 0.11), Vector2(-0.14, 0.19),
		Vector2(-0.07, 0.36), Vector2(0.20, 0.36), Vector2(0.22, -0.10),
		Vector2(0.15, -0.29), Vector2(0.19, -0.45), Vector2(0.10, -0.31),
		Vector2(0.05, -0.49), Vector2(-0.01, -0.31), Vector2(-0.07, -0.43),
	])
	var pts := PackedVector2Array()
	var hi := PackedVector2Array()
	for p in prof:
		var q := p.rotated(rot)
		var world := c + Vector2(q.x * rx * 1.15, q.y * ry * 1.15)
		pts.append(world)
		hi.append(world + Vector2(-0.9, -0.9))
	draw_colored_polygon(pts, col)
	if col.a > 0.3:
		hi.append(hi[0])
		draw_polyline(hi, Color(GLINT.r, GLINT.g, GLINT.b, 0.18), 1.0, true)


## Tails: crossed pikes and four field dots — legible at 30px.
func _draw_tails(c: Vector2, rx: float, ry: float, r: float) -> void:
	var wdt := maxf(1.6, r * 0.09)
	for s in [1.0, -1.0]:
		var a := c + Vector2(-rx * 0.34 * s, ry * 0.38)
		var b := c + Vector2(rx * 0.30 * s, -ry * 0.40)
		draw_line(a, b, STAMP, wdt, true)
		# Pike head: a small leaf at the raised end.
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * r * 0.07
		draw_colored_polygon(PackedVector2Array([
			b + dir * r * 0.14, b + side, b - side]), STAMP)
	for q in [Vector2(-0.52, 0.0), Vector2(0.52, 0.0), Vector2(0.0, 0.55), Vector2(0.0, -0.58)]:
		draw_circle(c + Vector2(q.x * rx, q.y * ry), maxf(1.0, r * 0.05),
			STAMP, true, -1.0, true)
