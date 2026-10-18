## StageTable — the shared piece of stage furniture every event minigame
## plays on: a stretch of the same dark camp-table wood Combat deals on
## and the war chart is pinned to, pulled into lamplight. Drawn as a
## FULL-BLEED plane (no sawn silhouette — the edges are lost in a vignette
## of dark, the map's parchment-on-wood language), so any stage prop is
## contained by construction. Cabinet cues without geometry: plank seams
## converge a touch toward the far edge, the far reach sits in shadow,
## and the light pools just below center where the props land.
## Deliberately LOWER contrast than everything set on it — CastPatch's
## law: the table stays quieter than the props. Games add it FIRST (via
## Event._stage_table) so every patch, prop and caption draws over it.
extends Control

var seed_text := "table"

const WOOD := Color(0.118, 0.086, 0.058)
const WOOD_WARM := Color(0.176, 0.128, 0.084)
const SEAM := Color(0.040, 0.028, 0.020, 0.90)
const GRAIN := Color(0.215, 0.160, 0.105, 0.11)
const KNOT := Color(0.062, 0.044, 0.030, 0.55)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Left/right seam x at a given y: seams pull inward toward the far (top)
## edge — the cabinet convergence read without a hard table outline.
func _seam_x(y: float, left: bool) -> float:
	var depth := clampf(y / maxf(1.0, size.y), 0.0, 1.0)
	var inset: float = lerpf(size.x * 0.040, 0.0, depth)
	return inset if left else size.x - inset


func _draw() -> void:
	if minf(size.x, size.y) <= 60.0:
		return
	var w := size.x
	var h := size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	# ── The planks: horizontal boards, foreshortened (narrow far, wide
	# near), each a seeded shade off the base wood.
	var cuts := [0.0, 0.16, 0.34, 0.55, 0.78, 1.0]
	for i in range(cuts.size() - 1):
		var y0: float = h * float(cuts[i])
		var y1: float = h * float(cuts[i + 1])
		var tone := WOOD.lerp(WOOD_WARM, rng.randf_range(0.0, 0.45))
		draw_colored_polygon(PackedVector2Array([
			Vector2(_seam_x(y0, true), y0), Vector2(_seam_x(y0, false), y0),
			Vector2(_seam_x(y1, false), y1), Vector2(_seam_x(y1, true), y1)]),
			tone)
		if i > 0:
			draw_line(Vector2(_seam_x(y0, true), y0),
				Vector2(_seam_x(y0, false), y0), SEAM, 2.0, true)
			# The seam's lower lip catches a hair of light.
			draw_line(Vector2(_seam_x(y0, true), y0 + 1.8),
				Vector2(_seam_x(y0, false), y0 + 1.8),
				Color(GRAIN.r, GRAIN.g, GRAIN.b, 0.14), 1.0, true)
		# Grain: a few long strokes riding each plank, bowed by seed.
		for _g in range(3):
			var gy := lerpf(y0 + 6.0, y1 - 6.0, rng.randf())
			var gx0 := rng.randf_range(w * 0.02, w * 0.30)
			var gx1 := rng.randf_range(w * 0.62, w * 0.97)
			var bow := rng.randf_range(-3.0, 3.0)
			var prev := Vector2(gx0, gy)
			for s in range(1, 5):
				var t := float(s) / 4.0
				var pt := Vector2(lerpf(gx0, gx1, t), gy + sin(t * PI) * bow)
				draw_line(prev, pt, GRAIN, 1.2, true)
				prev = pt
		# The odd knot.
		if rng.randf() < 0.6:
			var kp := Vector2(rng.randf_range(w * 0.10, w * 0.90),
				lerpf(y0 + 8.0, y1 - 8.0, rng.randf()))
			draw_set_transform(kp, 0.0, Vector2(1.0, 0.55))
			draw_arc(Vector2.ZERO, rng.randf_range(3.0, 6.0), 0.0, TAU, 12,
				KNOT, 1.4, true)
			draw_set_transform_matrix(Transform2D())
	# ── Old scuffs and ring-stains — a table that has held a hundred games.
	for _i in range(4):
		var a := rng.randf() * TAU
		var p := Vector2(w * 0.5, h * 0.55) \
			+ Vector2(cos(a), sin(a)) * Vector2(w, h) * rng.randf_range(0.12, 0.34)
		var dir := Vector2(cos(a + 1.1), sin(a + 1.1)) * rng.randf_range(16.0, 40.0)
		draw_line(p, p + dir, Color(0.05, 0.036, 0.025, 0.30),
			rng.randf_range(1.2, 2.4), true)
	if rng.randf() < 0.8:
		var rp := Vector2(rng.randf_range(w * 0.18, w * 0.80),
			rng.randf_range(h * 0.30, h * 0.72))
		draw_set_transform(rp, 0.0, Vector2(1.0, 0.42))
		draw_arc(Vector2.ZERO, rng.randf_range(14.0, 22.0), 0.0, TAU, 22,
			Color(0.055, 0.040, 0.028, 0.30), 2.6, true)
		draw_set_transform_matrix(Transform2D())
	# ── Lamplight: warm pool just below center, where the props land.
	for i in range(3):
		var k := float(i)
		draw_set_transform(Vector2(w * 0.5, h * 0.60), 0.0, Vector2(1.0, 0.62))
		draw_circle(Vector2.ZERO, w * (0.16 + 0.115 * k),
			Color(0.95, 0.78, 0.46, 0.045), true, -1.0, true)
		draw_set_transform_matrix(Transform2D())
	# ── The dark takes the edges: the far reach first, then a vignette
	# ring, then hard edge strips melting the plane into the scene.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0),
		Vector2(w * 0.94, h * 0.15), Vector2(w * 0.06, h * 0.15)]),
		Color(0, 0, 0, 0.17))
	for i in range(3):
		var k2 := float(i)
		draw_set_transform(Vector2(w * 0.5, h * 0.56), 0.0,
			Vector2(1.0, float(h) / maxf(1.0, float(w))))
		draw_arc(Vector2.ZERO, w * (0.470 + 0.062 * k2), 0.0, TAU, 56,
			Color(0, 0, 0, 0.14 + 0.05 * k2), w * 0.075, true)
		draw_set_transform_matrix(Transform2D())
	var strips := [
		[Rect2(0, 0, w, 16.0), 0.40], [Rect2(0, h - 14.0, w, 14.0), 0.38],
		[Rect2(0, 0, 15.0, h), 0.36], [Rect2(w - 15.0, 0, 15.0, h), 0.36]]
	for s in strips:
		draw_rect(s[0], Color(0, 0, 0, s[1]))
