## CastPatch — the gaming cloth the road's dead lay out for their games: the
## Bone Pit's casting hide, the Old Army Game's drumhead, the sappers' derby
## blanket. Reworked 2026-07-20 ("looks drawn by a 5-year-old" pass) from a
## flat brown blob into a REAL object in the ParchmentPlate school:
##
##   FORM     — cabinet-projection ground plane (far edge tapers, near edge
##              shows the hide's thickness), deep ground shadow, corner drape
##              folds with ridge highlights.
##   MATERIAL — seeded warp/weft grain, mottle, a stitched hem with frayed
##              threads, and 1–2 cruder REPAIR patches in the far reach
##              (the cloth has history; the patches also fill the acreage
##              props don't use).
##   LIGHT    — a real lamplight pool (wide value range, warm center) where
##              the props land; the far reach falls toward black. The old
##              pass had the same ideas at alphas nobody could see.
##   CHALK    — `chalk` names a worn chalk diagram of the game's own layout
##              ("ring", "lanes:N", "posts:N", "line", "court") — the dead
##              chalk their rules onto the blanket, so the diagram doubles
##              as a legibility aid and the empty cloth carries MEANING.
##
## The silhouette/rect contract is unchanged: games keep their hardcoded
## prop coordinates; only the painting got a craft pass. Contrast discipline:
## the cloth still stays quieter than the bones, coins, and helms on it.
extends Control

var seed_text := "patch"
## Chalk diagram motif: "" (none), "ring", "line", "lanes:N", "posts:N", "court".
var chalk := ""
## Where the lamplight pools, as a fraction of size offset from center.
## Default sits just below middle (where most games land their props).
var light_center_frac := Vector2(0.0, 0.10)

const HIDE := Color(0.150, 0.106, 0.075)
const HIDE_EDGE := Color(0.055, 0.040, 0.027)
const HIDE_LIP := Color(0.090, 0.062, 0.042)
const THREAD := Color(0.42, 0.33, 0.20, 0.60)
const CHALK_INK := Color(0.90, 0.87, 0.78)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _edge(inset: float, n: int = 30) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var ph := rng.randf() * TAU
	var c := size * 0.5
	var half := size * 0.5 - Vector2(inset, inset)
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var v := Vector2(cos(a), sin(a))
		# Blend an ellipse toward a rounded rectangle so the patch fills its
		# corners like cut hide, not a rug-oval. The wobble keeps it organic.
		var square := 1.0 / maxf(absf(v.x), absf(v.y))
		var k: float = lerpf(1.0, minf(square, 1.30), 0.45)
		var w := 1.0 + 0.030 * sin(a * 3.0 + ph) + 0.022 * sin(a * 7.0 + ph * 2.3)
		var p := v * k * w * half
		# The perspective taper: far (top) edge narrower, near edge a shade
		# wider — the plane recedes instead of hanging on the wall.
		var depth := clampf((p.y + half.y) / maxf(1.0, 2.0 * half.y), 0.0, 1.0)
		p.x *= lerpf(0.86, 1.05, depth)
		pts.append(c + p)
	return pts


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(24):
		var a := TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)


func _pool_center() -> Vector2:
	return size * 0.5 + size * light_center_frac


func _draw() -> void:
	if minf(size.x, size.y) <= 40.0:
		return
	var c := size * 0.5
	var pool := _pool_center()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 11

	# ── ground shadow (two layers: wide soft + tight dark) ──────────────
	var body := _edge(6.0)
	var shadow_far := PackedVector2Array()
	var shadow_near := PackedVector2Array()
	var lip := PackedVector2Array()
	for p in body:
		shadow_far.append(c + (p - c) * 1.045 + Vector2(4, 20))
		shadow_near.append(p + Vector2(2, 13))
		lip.append(p + Vector2(0, 9))
	draw_colored_polygon(shadow_far, Color(0, 0, 0, 0.22))
	draw_colored_polygon(shadow_near, Color(0, 0, 0, 0.38))

	# ── thickness lip, then the top face ─────────────────────────────────
	draw_colored_polygon(lip, HIDE_LIP)
	var closed_lip := lip.duplicate()
	closed_lip.append(lip[0])
	draw_polyline(closed_lip, HIDE_EDGE, 2.0, true)
	draw_colored_polygon(body, HIDE)

	# ── modeling: the far reach falls to dark, the lamp pools low ───────
	# Far band (top arc chorded across the middle) — twice the old strength.
	var far := _edge(9.0, 30)
	var band := PackedVector2Array()
	for i in range(15, 30):
		band.append(far[i])
	band.append(far[0])
	draw_colored_polygon(band, Color(0.0, 0.0, 0.0, 0.26))
	# Deep-far band: the top quarter falls further off.
	var band2 := PackedVector2Array()
	for i in range(18, 27):
		band2.append(far[i])
	draw_colored_polygon(band2, Color(0.0, 0.0, 0.0, 0.20))
	# The lamplight pool — a real value climb, warm at the heart.
	_ellipse(pool, size.x * 0.40, size.y * 0.26, Color(0.235, 0.170, 0.115, 0.35))
	_ellipse(pool, size.x * 0.30, size.y * 0.19, Color(0.285, 0.208, 0.135, 0.38))
	_ellipse(pool, size.x * 0.21, size.y * 0.13, Color(0.335, 0.248, 0.158, 0.34))
	_ellipse(pool, size.x * 0.13, size.y * 0.08, Color(0.375, 0.282, 0.180, 0.26))

	# ── material: warp/weft grain, denser and brighter inside the pool ──
	# (Quieted 2026-07-20 legibility pass: the cloth is the GROUND — its
	# texture must never compete with the props for the eye.)
	for i in range(58):
		var p := c + Vector2(rng.randf_range(-0.42, 0.42) * size.x,
			rng.randf_range(-0.40, 0.42) * size.y)
		var toward_pool := 1.0 - clampf(p.distance_to(pool) / (size.x * 0.45), 0.0, 1.0)
		var ln := rng.randf_range(7.0, 16.0)
		var warp := i % 3 != 0
		var ang := (-0.06 if warp else (PI * 0.5 + 0.10)) + rng.randf_range(-0.05, 0.05)
		var bright := rng.randf() < 0.5
		var col := Color(0.40, 0.31, 0.20, 0.034 + toward_pool * 0.042) if bright \
			else Color(0.0, 0.0, 0.0, 0.04 + toward_pool * 0.02)
		draw_line(p, p + Vector2(cos(ang), sin(ang)) * ln, col, 1.0, true)
	# Mottle: irregular tonal patches (water, oil, years).
	for i in range(4):
		var mp := c + Vector2(rng.randf_range(-0.34, 0.34) * size.x,
			rng.randf_range(-0.34, 0.36) * size.y)
		var mr := rng.randf_range(0.05, 0.10) * size.x
		var dark := rng.randf() < 0.6
		_ellipse(mp, mr, mr * rng.randf_range(0.5, 0.8),
			Color(0, 0, 0, 0.05) if dark else Color(0.36, 0.28, 0.18, 0.045))

	# ── drape: two corner folds, ridge shade + catch-light ──────────────
	for fi in range(2):
		var corner_a := rng.randf_range(PI * 0.55, PI * 0.95) if fi == 0 \
			else rng.randf_range(PI * 1.15, PI * 1.55)
		var start := c + Vector2(cos(corner_a), sin(corner_a)) * size * 0.42
		var toward := (c - start).normalized()
		var side := Vector2(-toward.y, toward.x)
		var fold := PackedVector2Array()
		var seg := rng.randf_range(0.16, 0.24)
		for t in range(7):
			var tt := float(t) / 6.0
			fold.append(start + toward * (size.x * seg * tt) \
				+ side * sin(tt * PI) * rng.randf_range(6.0, 11.0))
		draw_polyline(fold, Color(0, 0, 0, 0.13), 5.0, true)
		var lit := PackedVector2Array()
		for p in fold:
			lit.append(p + side * 3.4)
		draw_polyline(lit, Color(0.42, 0.33, 0.21, 0.08), 2.0, true)

	# ── the hem: seam line, stitch dashes, frayed threads ────────────────
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, HIDE_EDGE, 2.0, true)
	var hem := _edge(11.0, 40)
	var hem_closed := hem.duplicate()
	hem_closed.append(hem[0])
	draw_polyline(hem_closed, Color(0.06, 0.045, 0.03, 0.55), 1.2, true)
	var rim := _edge(13.0, 40)
	for i in range(0, rim.size(), 2):
		var p := rim[i]
		var toward := (c - p).normalized() * 5.0
		draw_line(p - toward * 0.4, p + toward * 0.6, THREAD, 1.5, true)
	# Fray: little thread curls escaping the hem at seeded points.
	for i in range(6):
		var a := rng.randf() * TAU
		var idx := int(a / TAU * 40.0) % 40
		var p: Vector2 = hem[idx]
		var outward := (p - c).normalized()
		var t0 := p + outward * rng.randf_range(4.0, 8.0)
		var bend := Vector2(-outward.y, outward.x) * rng.randf_range(-4.0, 4.0)
		draw_line(p, t0, THREAD, 1.0, true)
		draw_line(t0, t0 + bend, Color(THREAD.r, THREAD.g, THREAD.b, 0.40), 1.0, true)

	# ── one repair patch: a cruder square stitched into the far reach ───
	# (First cut drew 1-2 near-invisible fills whose radial stitches read
	# as STARBURSTS at game size — now: one patch, a clearly darker fill,
	# a firm outline, and two short cross-stitches per side.)
	var pp := c + Vector2(rng.randf_range(-0.26, 0.26) * size.x,
		rng.randf_range(-0.30, -0.14) * size.y)
	var pr := rng.randf_range(17.0, 23.0)
	var rot := rng.randf_range(-0.22, 0.22)
	var quad := PackedVector2Array()
	for q in range(4):
		var qa := rot + PI * 0.25 + TAU * float(q) / 4.0
		quad.append(pp + Vector2(cos(qa), sin(qa)) * pr * rng.randf_range(0.94, 1.06))
	draw_colored_polygon(quad, Color(0.102, 0.078, 0.060))
	var quad_closed := quad.duplicate()
	quad_closed.append(quad[0])
	draw_polyline(quad_closed, Color(0.045, 0.034, 0.024, 0.85), 1.6, true)
	for q in range(4):
		var a0: Vector2 = quad[q]
		var a1: Vector2 = quad[(q + 1) % 4]
		var edge_dir := (a1 - a0).normalized()
		var outw := Vector2(-edge_dir.y, edge_dir.x) * 2.6
		for s in [0.33, 0.67]:
			var sp := a0.lerp(a1, s)
			draw_line(sp - outw + edge_dir * 1.2, sp + outw - edge_dir * 1.2,
				THREAD, 1.4, true)

	# ── old scuffs (kept from the first pass) ────────────────────────────
	for i in range(5):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.10, 0.34)
		var p := c + Vector2(cos(a), sin(a)) * Vector2(size.x, size.y) * r
		var dir := Vector2(cos(a + 1.3), sin(a + 1.3)) * rng.randf_range(14.0, 34.0)
		draw_line(p, p + dir, Color(0.24, 0.18, 0.12, 0.12), rng.randf_range(1.5, 3.0), true)

	# ── the chalked game ─────────────────────────────────────────────────
	if chalk != "":
		_draw_chalk(rng, pool)


# ══ chalk — worn, double-struck, gapped strokes with dust ═══════════════════

func _chalk_seg(a: Vector2, b: Vector2, rng: RandomNumberGenerator,
		alpha := 0.42) -> void:
	# A chalk line is never one clean stroke: dashes with gaps where the weave
	# ate the chalk, a second fainter pass beside the first, dust beneath.
	var length := a.distance_to(b)
	var dirn := (b - a).normalized()
	var perp := Vector2(-dirn.y, dirn.x)
	var t := 0.0
	while t < length:
		var seg := rng.randf_range(9.0, 18.0)
		var gap := rng.randf_range(2.0, 6.0)
		var s0 := a + dirn * t + perp * rng.randf_range(-1.0, 1.0)
		var s1 := a + dirn * minf(t + seg, length) + perp * rng.randf_range(-1.0, 1.0)
		draw_line(s0, s1, Color(CHALK_INK.r, CHALK_INK.g, CHALK_INK.b, alpha), 2.0, true)
		if rng.randf() < 0.7:
			draw_line(s0 + perp * 1.6, s1 + perp * 1.4,
				Color(CHALK_INK.r, CHALK_INK.g, CHALK_INK.b, alpha * 0.45), 1.2, true)
		t += seg + gap


func _chalk_ellipse(cc: Vector2, rx: float, ry: float,
		rng: RandomNumberGenerator, alpha := 0.42) -> void:
	var n := 26
	var prev := cc + Vector2(rx, 0)
	for i in range(1, n + 1):
		var a := TAU * float(i) / float(n)
		var p := cc + Vector2(cos(a) * rx, sin(a) * ry) \
			+ Vector2(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.2, 1.2))
		if rng.randf() > 0.18:
			draw_line(prev, p, Color(CHALK_INK.r, CHALK_INK.g, CHALK_INK.b, alpha), 2.0, true)
			if rng.randf() < 0.55:
				draw_line(prev + Vector2(0, 1.6), p + Vector2(0, 1.6),
					Color(CHALK_INK.r, CHALK_INK.g, CHALK_INK.b, alpha * 0.4), 1.2, true)
		prev = p


func _chalk_dust(cc: Vector2, rx: float, ry: float) -> void:
	_ellipse(cc, rx, ry, Color(CHALK_INK.r, CHALK_INK.g, CHALK_INK.b, 0.035))


func _draw_chalk(rng: RandomNumberGenerator, pool: Vector2) -> void:
	var kind := chalk
	var arg := 0
	if ":" in chalk:
		var parts := chalk.split(":")
		kind = parts[0]
		arg = int(parts[1])
	match kind:
		"ring":
			# The cast circle, squashed to the plane, around the light pool —
			# with the house-rule tally chalked by the near-left hem.
			var rx := size.x * 0.30
			var ry := size.y * 0.20
			_chalk_dust(pool, rx * 1.05, ry * 1.05)
			_chalk_ellipse(pool, rx, ry, rng)
			_chalk_ellipse(pool, rx * 0.94, ry * 0.94, rng, 0.18)
			var tally0 := Vector2(size.x * 0.16, size.y * 0.80)
			for i in range(5):
				var tx := tally0 + Vector2(float(i) * 7.0, 0)
				if i == 4:
					_chalk_seg(tally0 + Vector2(-3, 5), tx + Vector2(3, -9), rng, 0.34)
				else:
					_chalk_seg(tx, tx + Vector2(-2, -12), rng, 0.34)
		"line":
			# One long baseline under the prop row, ticked at both ends.
			var y := pool.y + size.y * 0.14
			var x0 := size.x * 0.14
			var x1 := size.x * 0.86
			_chalk_dust(Vector2(size.x * 0.5, y + 2), size.x * 0.34, 7.0)
			_chalk_seg(Vector2(x0, y), Vector2(x1, y), rng)
			_chalk_seg(Vector2(x0, y - 7), Vector2(x0, y + 7), rng, 0.34)
			_chalk_seg(Vector2(x1, y - 7), Vector2(x1, y + 7), rng, 0.34)
		"lanes":
			# N receding race lanes: rails plus start / finish posts.
			var n := maxi(arg, 2)
			var x0 := size.x * 0.13
			var x1 := size.x * 0.87
			var y0 := size.y * 0.24
			var y1 := size.y * 0.80
			for i in range(n + 1):
				var yy := lerpf(y0, y1, float(i) / float(n))
				# Far rails sit closer together (the plane recedes).
				var squeeze := lerpf(0.06, 0.0, float(i) / float(n)) * size.x
				_chalk_seg(Vector2(x0 + squeeze, yy), Vector2(x1 - squeeze, yy), rng,
					0.30 + 0.12 * float(i) / float(n))
			_chalk_seg(Vector2(x0 + size.x * 0.03, y0 - 4), Vector2(x0, y1 + 4), rng, 0.34)
			_chalk_seg(Vector2(x1 - size.x * 0.03, y0 - 4), Vector2(x1, y1 + 4), rng, 0.46)
		"posts":
			# N chalked emplacement circles along the pool line.
			var n := maxi(arg, 2)
			for i in range(n):
				var fx := lerpf(0.22, 0.78, float(i) / float(n - 1))
				var cc := Vector2(size.x * fx, pool.y + size.y * 0.16)
				_chalk_dust(cc, 30.0, 12.0)
				_chalk_ellipse(cc, 27.0, 11.0, rng, 0.36)
		"court":
			# The quoits court: a throw line by the near hem, two faint
			# distance arcs walking toward the peg ground.
			var y := size.y * 0.78
			_chalk_seg(Vector2(size.x * 0.20, y), Vector2(size.x * 0.55, y), rng)
			for i in range(2):
				var ay := lerpf(y - size.y * 0.14, y - size.y * 0.30, float(i))
				var arc := PackedVector2Array()
				var prev := Vector2.ZERO
				for t in range(9):
					var tt := float(t) / 8.0
					var p := Vector2(lerpf(size.x * 0.24, size.x * 0.62, tt),
						ay - sin(tt * PI) * 7.0)
					if t > 0 and rng.randf() > 0.25:
						draw_line(prev, p, Color(CHALK_INK.r, CHALK_INK.g,
							CHALK_INK.b, 0.26 - 0.08 * float(i)), 1.8, true)
					prev = p
				arc.clear()
