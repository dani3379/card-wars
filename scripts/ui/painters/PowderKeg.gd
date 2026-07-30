## PowderKeg — one barrel of the sappers' stack in The Powder Move
## (hanoi_game). Front-on (the emplacement posts are vertical), so no
## cabinet squash: a staved oak keg with iron hoops, a chime lip, a bung,
## a powder stencil and a scorch kiss near the foot. Sized by `tier`
## (0 small .. up). `lifted` lights it while carried; `bad` flashes it red
## on an illegal rest. Pure painter; the Event scene owns motion and
## hit-testing. (Reworked 2026-07-20 — the first pass read as a stack of
## pancakes: flat fill, straight hoops, no staves.)
extends Control

var tier := 0
var lifted := false
var bad := false
var seed_text := "keg"

const WOOD := Color(0.400, 0.265, 0.150)
const WOOD_LIT := Color(0.545, 0.375, 0.215)
const WOOD_DK := Color(0.235, 0.150, 0.085)
const EDGE_INK := Color(0.10, 0.062, 0.035)
const HOOP := Color(0.255, 0.235, 0.205)
const HOOP_DK := Color(0.14, 0.13, 0.115)
const HOOP_LIT := Color(0.60, 0.56, 0.48)
const STENCIL := Color(0.13, 0.10, 0.075, 0.75)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Barrel half-width at vertical fraction t (0 top .. 1 bottom) — the stave
## bulge. Returned in 0..0.5 of width units around the centreline.
func _hw(t: float) -> float:
	return 0.36 + 0.115 * sin(PI * clampf(t, 0.0, 1.0))


func _profile_x(t: float, side: float) -> float:
	return size.x * (0.5 + side * _hw(t))


func _draw() -> void:
	if minf(size.x, size.y) <= 8.0:
		return
	var w := size.x
	var h := size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + tier * 131

	# Contact shadow — soft, offset a touch right.
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.10, h - 1), Vector2(w * 0.92, h - 1),
		Vector2(w * 0.84, h + 4), Vector2(w * 0.16, h + 4)]),
		Color(0, 0, 0, 0.32))

	# ── body silhouette: smooth bulged staves ────────────────────────────
	var n := 9
	var body := PackedVector2Array()
	for i in range(n + 1):
		var t := float(i) / float(n)
		body.append(Vector2(_profile_x(t, 1.0), lerpf(h * 0.05, h * 0.95, t)))
	for i in range(n, -1, -1):
		var t := float(i) / float(n)
		body.append(Vector2(_profile_x(t, -1.0), lerpf(h * 0.05, h * 0.95, t)))
	var base := WOOD_LIT if lifted else WOOD
	if bad:
		base = Color(0.58, 0.21, 0.15)
	draw_colored_polygon(body, base)

	# ── cylinder modeling: dark flanks, a lit band left-of-centre ────────
	for side in [-1.0, 1.0]:
		var flank := PackedVector2Array()
		for i in range(n + 1):
			var t := float(i) / float(n)
			flank.append(Vector2(_profile_x(t, side), lerpf(h * 0.05, h * 0.95, t)))
		for i in range(n, -1, -1):
			var t := float(i) / float(n)
			flank.append(Vector2(_profile_x(t, side * 0.60), lerpf(h * 0.05, h * 0.95, t)))
		draw_colored_polygon(flank, Color(WOOD_DK.r, WOOD_DK.g, WOOD_DK.b,
			0.42 if side > 0 else 0.30))
	var band := PackedVector2Array()
	for i in range(n + 1):
		var t := float(i) / float(n)
		band.append(Vector2(_profile_x(t, -0.42), lerpf(h * 0.06, h * 0.94, t)))
	for i in range(n, -1, -1):
		var t := float(i) / float(n)
		band.append(Vector2(_profile_x(t, -0.06), lerpf(h * 0.06, h * 0.94, t)))
	draw_colored_polygon(band, Color(WOOD_LIT.r, WOOD_LIT.g, WOOD_LIT.b, 0.34))

	# ── staves: curved seams + per-stave tone shift ──────────────────────
	var staves := 6
	for s in range(1, staves):
		var fx := -1.0 + 2.0 * float(s) / float(staves)
		var seam := PackedVector2Array()
		for i in range(n + 1):
			var t := float(i) / float(n)
			seam.append(Vector2(_profile_x(t, fx * _hw(t) / _hw(0.5) * 0.98),
				lerpf(h * 0.07, h * 0.93, t)))
		draw_polyline(seam, Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.45), 1.2, true)
		if rng.randf() < 0.5:
			var tinted := seam.duplicate()
			for j in range(tinted.size()):
				tinted[j] += Vector2(1.4, 0)
			draw_polyline(tinted, Color(1, 1, 1, 0.05), 2.2, true)
	# Grain flecks.
	for i in range(7):
		var t := rng.randf_range(0.12, 0.88)
		var fx := rng.randf_range(-0.8, 0.8)
		var p := Vector2(_profile_x(t, fx * _hw(t) / _hw(0.5) * 0.8),
			lerpf(h * 0.05, h * 0.95, t))
		draw_line(p, p + Vector2(rng.randf_range(3.0, 7.0), rng.randf_range(-1.0, 1.0)),
			Color(WOOD_DK.r, WOOD_DK.g, WOOD_DK.b, 0.35), 1.0, true)

	# ── chime lips (top and bottom edge of the staves) ───────────────────
	draw_line(Vector2(_profile_x(0.0, -1.0), h * 0.05),
		Vector2(_profile_x(0.0, 1.0), h * 0.05), EDGE_INK, 2.0, true)
	draw_line(Vector2(_profile_x(0.0, -0.9), h * 0.05 + 1.6),
		Vector2(_profile_x(0.0, 0.9), h * 0.05 + 1.6),
		Color(WOOD_LIT.r, WOOD_LIT.g, WOOD_LIT.b, 0.55), 1.2, true)
	draw_line(Vector2(_profile_x(1.0, -1.0), h * 0.95),
		Vector2(_profile_x(1.0, 1.0), h * 0.95), EDGE_INK, 2.0, true)

	# ── iron hoops riding the bulge (quads, not straight rects) ─────────
	for hy: float in [0.16, 0.46, 0.60, 0.86]:
		var hh := 0.030 if (hy > 0.3 and hy < 0.7) else 0.026
		var t0: float = hy - hh
		var t1: float = hy + hh
		var quad := PackedVector2Array([
			Vector2(_profile_x(t0, -1.0) - 1, lerpf(h * 0.05, h * 0.95, t0)),
			Vector2(_profile_x(t0, 1.0) + 1, lerpf(h * 0.05, h * 0.95, t0)),
			Vector2(_profile_x(t1, 1.0) + 1, lerpf(h * 0.05, h * 0.95, t1)),
			Vector2(_profile_x(t1, -1.0) - 1, lerpf(h * 0.05, h * 0.95, t1))])
		draw_colored_polygon(quad, HOOP)
		# Under-shadow, top catch-light, one specular tick, two rivets.
		var y1 := lerpf(h * 0.05, h * 0.95, t1)
		var y0 := lerpf(h * 0.05, h * 0.95, t0)
		draw_line(Vector2(_profile_x(t1, -0.98), y1 + 1.2),
			Vector2(_profile_x(t1, 0.98), y1 + 1.2),
			Color(0, 0, 0, 0.30), 1.4, true)
		draw_line(Vector2(_profile_x(t0, -0.96), y0 + 0.8),
			Vector2(_profile_x(t0, 0.96), y0 + 0.8),
			Color(HOOP_LIT.r, HOOP_LIT.g, HOOP_LIT.b, 0.65), 1.0, true)
		var sx := _profile_x(hy, -0.38)
		draw_line(Vector2(sx, y0 + 1.0), Vector2(sx + w * 0.10, y0 + 1.0),
			Color(0.92, 0.90, 0.82, 0.35), 2.0, true)
		for rx in [-0.62, 0.62]:
			draw_circle(Vector2(_profile_x(hy, rx), lerpf(y0, y1, 0.5)), 1.3,
				HOOP_DK, true, -1.0, true)

	# ── bung, stencil, scorch ────────────────────────────────────────────
	if w >= 40.0:
		var bung := Vector2(_profile_x(0.52, 0.30), lerpf(h * 0.05, h * 0.95, 0.52))
		draw_circle(bung, 3.4, WOOD_DK, true, -1.0, true)
		draw_circle(bung + Vector2(-0.8, -0.8), 1.0, Color(1, 1, 1, 0.18), true, -1.0, true)
	if w >= 42.0 and not bad:
		var sc := Vector2(_profile_x(0.34, -0.16), lerpf(h * 0.05, h * 0.95, 0.34))
		draw_colored_polygon(PackedVector2Array([
			sc + Vector2(0, -6), sc + Vector2(5, 0), sc + Vector2(0, 6),
			sc + Vector2(-5, 0)]), STENCIL)
		draw_line(sc + Vector2(0, -6), sc + Vector2(3, -11),
			Color(STENCIL.r, STENCIL.g, STENCIL.b, 0.8), 1.4, true)
	# Scorch kiss near the foot — these kegs have been NEAR fires.
	var scorch := Vector2(_profile_x(0.86, 0.34), lerpf(h * 0.05, h * 0.95, 0.86))
	for i in range(3):
		var r := 5.0 - float(i) * 1.4
		draw_circle(scorch + Vector2(rng.randf_range(-2, 2), rng.randf_range(-1, 1)),
			r, Color(0.05, 0.04, 0.03, 0.16 + float(i) * 0.06), true, -1.0, true)

	# ── edge ink + lifted halo ───────────────────────────────────────────
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Color(EDGE_INK.r, EDGE_INK.g, EDGE_INK.b, 0.85), 1.6, true)
	if lifted:
		draw_polyline(closed, Color(0.95, 0.82, 0.45, 0.9), 2.2, true)
