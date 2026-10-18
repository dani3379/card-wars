## WaxSeal — extracted from Card2D.gd (backend restructure 2026-07-14).
## A pressed wax seal, fully procedural. Reworked 2026-07-19 ("the blobs
## don't look in place"): the old recipe — centered dark face + pale arc —
## was accidentally the glossy-orb shading formula, so every seal read as a
## jelly button. The new grammar is directional wax material, one light
## (top-left) everywhere:
##   silhouette  — seeded wobble + 1-2 dribble lobes (cooled wax, not an
##                 imprecise circle)
##   body        — two offset polygons: the visible sliver on the shadow
##                 side is the squeeze ridge falling away from the light
##   ridge       — lit arc on the top-left outer edge, shade arc on the
##                 bottom-right (a sticker outline is uniform; a ridge
##                 has a light side)
##   impression  — the stamped recess: occlusion arc on the wall NEAREST
##                 the light, lit arc on the far wall, face sunk dark
##                 (the numeral-legibility contract — light numerals pop
##                 off the dark face on 38px tokens; keep it >= 0.28)
##   NO interior sheen. A pale arc inside the face is a specular ball
##   highlight no matter what the comment calls it.
## All widths/offsets scale with radius (`u`) — the 120px Command seal was
## drawn with 56px pixel constants before and looked like a balloon.
extends Control

const LIGHT_A := PI * 1.25          # light azimuth: top-left (y-down)

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
	var amp1 := 0.026 + rng.randf() * 0.018
	var amp2 := 0.016 + rng.randf() * 0.014
	# Dribble lobes: 1-2 seeded bulges where the wax squeezed out under the
	# stamp — localized, not another sine (that just wobbles the circle).
	var lobe_count := 1 + (rng.randi() % 2)
	var lobe_a: Array[float] = []
	var lobe_amp: Array[float] = []
	var lobe_w: Array[float] = []
	for i in lobe_count:
		lobe_a.append(rng.randf() * TAU)
		lobe_amp.append(0.055 + rng.randf() * 0.045)
		lobe_w.append(0.30 + rng.randf() * 0.22)
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var w := 1.0 + amp1 * sin(a * 3.0 + ph1) + amp2 * sin(a * 7.0 + ph2) \
			+ 0.010 * sin(a * 13.0 + ph1 + ph2)
		for l in lobe_count:
			var d := absf(angle_difference(a, lobe_a[l]))
			w += lobe_amp[l] * exp(-pow(d / lobe_w[l], 2.0))
		pts.append(center + Vector2(cos(a), sin(a)) * base_r * w)
	return pts

func _draw() -> void:
	var min_dim := minf(size.x, size.y)
	if min_dim <= 6.0:
		return
	var center := size * 0.5
	var base_r := min_dim * 0.5 - 1.5
	var u := base_r / 28.0              # scale unit: 1.0 at the 56px hand seal
	var light := Vector2(cos(LIGHT_A), sin(LIGHT_A))
	var dark := Color(wax.r * 0.45, wax.g * 0.45, wax.b * 0.50)
	var lit := Color(minf(wax.r * 1.45 + 0.08, 1.0),
		minf(wax.g * 1.45 + 0.08, 1.0), minf(wax.b * 1.42 + 0.06, 1.0))
	var seg := 18 if simple_mode else 28

	# 1 — contact shadow, cast away from the light and scaled with the seal
	# (a fixed 2px offset vanished under the 120px Command seal).
	draw_colored_polygon(_blob(center - light * base_r * 0.09, base_r * 1.02, seg),
		Color(0, 0, 0, 0.30))
	# 2 — body in ridge-shade, then the face polygon nudged toward the light:
	# the exposed sliver on the shadow side IS the ridge falling away.
	draw_colored_polygon(_blob(center, base_r, seg),
		Color(wax.r * 0.80, wax.g * 0.80, wax.b * 0.82))
	draw_colored_polygon(_blob(center + light * base_r * 0.055, base_r * 0.955, seg), wax)
	# 3 — silhouette AA line (thin — outline is not the material).
	var body := _blob(center, base_r, seg)
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Color(dark.r, dark.g, dark.b, 0.60), 1.1 * u, true)
	# 4 — directional ridge: lit top-left edge, shaded bottom-right edge.
	draw_arc(center, base_r * 0.94, LIGHT_A - 0.42 * PI, LIGHT_A + 0.42 * PI,
		seg, Color(lit.r, lit.g, lit.b, 0.34), 1.5 * u, true)
	draw_arc(center, base_r * 0.94, LIGHT_A + 0.62 * PI, LIGHT_A + 1.38 * PI,
		seg, Color(dark.r, dark.g, dark.b, 0.42), 1.9 * u, true)
	# 5 — the stamped impression (a recess, so the shading is the ridge
	# inverted): occlusion on the wall nearest the light, lit far wall.
	var ring_r := base_r * 0.68
	draw_arc(center, ring_r, LIGHT_A - 0.46 * PI, LIGHT_A + 0.46 * PI,
		seg, Color(0, 0, 0, 0.38), 2.0 * u, true)
	draw_arc(center, ring_r, LIGHT_A + 0.60 * PI, LIGHT_A + 1.40 * PI,
		seg, Color(lit.r, lit.g, lit.b, 0.30), 1.3 * u, true)
	# 6 — pressed face, sunk darker so the light numeral pops off it (this
	# face sits under the stat label on both the 56px hand seal and the 38px
	# battlefield token — the legibility contract).
	draw_circle(center, ring_r - 1.5 * u, Color(0, 0, 0, 0.30), true, -1.0, true)
	if simple_mode:
		return
	# 7 — seeded cooling flecks on the ridge zone: dark, not white — matte
	# wax has pits, not sparkles.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 7
	for i in range(3):
		var a := rng.randf() * TAU
		var rr := base_r * (0.74 + rng.randf() * 0.16)
		draw_circle(center + Vector2(cos(a), sin(a)) * rr,
			(0.7 + rng.randf() * 0.9) * u,
			Color(0, 0, 0, 0.07 + rng.randf() * 0.06), true, -1.0, true)
