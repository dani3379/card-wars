## BoneStraw — one splinter from the watch bundle (The Short Straw's misère
## drawing). A thin seeded bone sliver with a knuckle swell and a snapped,
## marrow-dark foot, lying on the drumhead pointing at the viewer. `lit` is
## the hover telegraph — every straw that would leave with this click warms
## up together, so a move is read before it is made. Pure painter.
##
## (2026-07-20 craft pass: per-straw age tint, side shading, a knuckle
## crease and a hairline check — fifteen identical white picket teeth
## became fifteen individual bones.)
##
## (2026-07-22 shadow + weight pass: the cast shadow was the silhouette
## nudged (2.0, 3.5). On a bone barely 5px across that hides almost wholly
## UNDER its own body — the same defect measured on KnuckleboneDie — and the
## row read as fifteen marks painted ON the cloth. Fixed the house way: a
## broad soft haze plus a tighter contact shadow, both thrown clear of the
## body to the lamp's far side, so each straw visibly sits ABOVE the plane.
## Also widened the age spread and warmed the stock — at 16px across, a
## 0..0.55 lerp between two near-identical creams is no variation at all.)
extends Control

var seed_text := "straw"
var lit := false

const BONE := Color(0.880, 0.830, 0.712)
const BONE_AGED := Color(0.686, 0.598, 0.436)
const BONE_TEA := Color(0.780, 0.660, 0.470)
const BONE_LIT := Color(0.985, 0.930, 0.775)
const GLOW := Color(0.95, 0.72, 0.30, 0.55)
const INK := Color(0.30, 0.25, 0.18)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The seeded crook phase. Matches _sliver's own draw so the body, the
## shadows, the knuckle and the head all agree on one bone.
func _phase() -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	return rng.randf() * TAU


## Half-width along the shaft: a knuckle swell near one end, tapering to the
## snapped foot. Bones are not dowels.
func _half_w(t: float) -> float:
	return (size.x * 0.15 + size.x * 0.11 * exp(-pow((t - 0.22) * 4.0, 2.0))) \
		* lerpf(1.0, 0.78, t)


## The shaft's centre line at t (0 = head, 1 = foot).
func _axis(t: float, ph: float) -> Vector2:
	return Vector2(size.x * 0.5 + sin(t * PI * 1.1 + ph) * size.x * 0.14,
		lerpf(3.0, size.y - 3.0, t))


func _sliver(off: Vector2, squeeze := 1.0) -> PackedVector2Array:
	var ph := _phase()
	var pts_l: Array = []
	var pts_r: Array = []
	for i in range(7):
		var t := float(i) / 6.0
		var a := _axis(t, ph)
		var hw := _half_w(t) * squeeze
		pts_l.append(Vector2(a.x - hw, a.y) + off)
		pts_r.append(Vector2(a.x + hw, a.y) + off)
	var poly := PackedVector2Array()
	for p in pts_l:
		poly.append(p)
	for i in range(pts_r.size() - 1, -1, -1):
		poly.append(pts_r[i])
	return poly


func _draw() -> void:
	if size.y <= 12.0:
		return
	var ph := _phase()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 7
	var head := _axis(0.0, ph)
	var head_r := _half_w(0.0)

	# ── the cast shadow ──────────────────────────────────────────────────
	# Thrown clear of the body, never a silhouette copy: a broad haze, then
	# a tighter contact shadow. The lamp is west (see the catch-light
	# below), so both fall east and down.
	draw_colored_polygon(_sliver(Vector2(size.x * 0.30, size.y * 0.075), 2.4),
		Color(0, 0, 0, 0.11))
	draw_colored_polygon(_sliver(Vector2(size.x * 0.24, size.y * 0.042), 1.35),
		Color(0, 0, 0, 0.26))

	if lit:
		# The telegraph: a warm halo around every straw this click would take.
		draw_colored_polygon(_sliver(Vector2.ZERO, 2.7),
			Color(GLOW.r, GLOW.g, GLOW.b, 0.20))
		draw_colored_polygon(_sliver(Vector2.ZERO, 1.75),
			Color(GLOW.r, GLOW.g, GLOW.b, 0.40))
		draw_circle(head, head_r * 2.3, Color(GLOW.r, GLOW.g, GLOW.b, 0.24),
			true, -1.0, true)

	# ── the bone ─────────────────────────────────────────────────────────
	# Each its own age: fresh-pale through tea-brown, plus an independent
	# warmth nudge so no two of the fifteen land on the same colour.
	var age := rng.randf_range(0.0, 0.85)
	var col := BONE.lerp(BONE_AGED, age).lerp(BONE_TEA, rng.randf_range(0.0, 0.20))
	var face := BONE_LIT if lit else col
	var body := _sliver(Vector2.ZERO)
	draw_circle(head, head_r, face, true, -1.0, true)
	draw_colored_polygon(body, face)
	# Side shading: the east flank turns from the lamp.
	var shade := _sliver(Vector2(size.x * 0.05, 0.4), 0.46)
	for i in range(shade.size()):
		shade[i].x += size.x * 0.075
	draw_colored_polygon(shade, Color(0.34, 0.28, 0.20, 0.26))
	draw_circle(head + Vector2(head_r * 0.42, head_r * 0.16), head_r * 0.62,
		Color(0.34, 0.28, 0.20, 0.20), true, -1.0, true)
	# West catch-light — the one specular that makes the bone read as round.
	var sheen := _sliver(Vector2(-size.x * 0.07, 0.0), 0.17)
	draw_colored_polygon(sheen, Color(1.0, 0.98, 0.90, 0.34))
	draw_circle(head + Vector2(-head_r * 0.34, -head_r * 0.30), head_r * 0.34,
		Color(1.0, 0.98, 0.90, 0.42), true, -1.0, true)

	# The knuckle crease — a short curved shadow under the swell.
	var knuckle := _axis(0.30, ph)
	draw_arc(knuckle, size.x * 0.16, PI * 0.15, PI * 0.85, 8,
		Color(INK.r, INK.g, INK.b, 0.35), 1.4, true)
	# A hairline check down the shaft, on the older bones.
	if age > 0.30:
		var y0 := lerpf(3.0, size.y - 3.0, rng.randf_range(0.42, 0.55))
		var y1 := y0 + size.y * rng.randf_range(0.16, 0.28)
		draw_line(Vector2(knuckle.x + rng.randf_range(-2.0, 2.0), y0),
			Vector2(knuckle.x + rng.randf_range(-3.0, 3.0), y1),
			Color(INK.r, INK.g, INK.b, 0.30), 1.0, true)

	# The snapped foot: the marrow hollow, dark where the bone gave.
	var foot := _axis(1.0, ph)
	var fw := _half_w(1.0)
	draw_circle(foot + Vector2(0, -fw * 0.30), fw * 0.66,
		Color(INK.r, INK.g, INK.b, 0.48), true, -1.0, true)

	# Contour ink, the head's exposed crown included.
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Color(INK.r, INK.g, INK.b, 0.65), 1.1, true)
	draw_arc(head, head_r, PI, TAU, 12, Color(INK.r, INK.g, INK.b, 0.65), 1.1, true)
