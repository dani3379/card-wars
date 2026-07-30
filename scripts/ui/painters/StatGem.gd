extends Control
## Draw-only stat/doom gem. Kept separate from Card2D's gameplay/input adapter.

const PolyBadge := preload("res://scripts/ui/painters/PolyBadge.gd")
var fill_color: Color = Color.WHITE
var shape: String = "hex"             # hex / shield / drop / diamond / peak
var style: String = "faceted"         # "faceted" or "smooth"
var gloss: float = 1.0                # specular/bevel strength; <1 = calmer/matte
# Light direction (unit vector pointing FROM the light TO the surface).
# Upper-left light → vector points down-right. Stored as where the lit
# normal POINTS: (-0.40, -0.92) means the brightest facet faces up-left.
const LIGHT := Vector2(-0.40, -0.92)
const RIM_DARK := Color(0.04, 0.04, 0.08, 1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var pts := _build_shape(size)
	if pts.size() < 3:
		return
	var center := size * 0.5

	# Emblem style routes to a separate, fully matte renderer — the
	# glossy gem treatment below clashes with the painted parchment
	# frame. Wax-seal / struck-coin look instead.
	if style == "emblem":
		_draw_emblem(pts, center)
		return

	# ── Layer 1: Drop shadow (3 stacked, decreasing alpha) ─────────────
	# One layer reads as a sticker. Three give the orb real "floating"
	# depth — same trick as iOS app icons and Hearthstone gems.
	for i in range(3):
		var off := Vector2(0, i + 2)
		var grow := float(i) * 0.025
		var shadow_pts := PackedVector2Array()
		for p in pts:
			shadow_pts.append(p + (p - center) * grow + off)
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.28 - float(i) * 0.07))

	# ── Layer 2: Outer dark rim (chiseled border) ─────────────────────
	# Slightly enlarged polygon in near-black. Reads as the dark
	# metal/stone setting of a gemstone. This is what separates an orb
	# from "a coloured shape": rim contrast against the card body.
	var rim_pts := PackedVector2Array()
	for p in pts:
		rim_pts.append(p + (p - center) * 0.07)
	draw_colored_polygon(rim_pts, RIM_DARK)

	# ── Layer 3: Body (faceted crystal OR smooth dome) ────────────────
	if style == "faceted":
		_draw_faceted_body(pts, center)
	else:
		_draw_smooth_body(pts, center)

	# ── Layer 4: Specular hotspot cluster ─────────────────────────────
	# Two-circle highlight: wide soft halo + sharp bright core, offset
	# toward the light source. The cluster (not the single dot) is what
	# sells "wet polished glass".
	var min_dim := minf(size.x, size.y)
	if min_dim >= 14.0:
		var spec_pos := center + LIGHT * Vector2(size.x * 0.26, size.y * 0.28)
		var rad_outer := min_dim * 0.20
		var rad_inner := min_dim * 0.085
		draw_circle(spec_pos, rad_outer, Color(1, 1, 1, 0.38 * gloss),
			true, -1.0, true)
		draw_circle(spec_pos + LIGHT * rad_inner * 0.35,
			rad_inner, Color(1, 1, 1, 0.95 * gloss), true, -1.0, true)

	# ── Layer 5: Bottom-right inner rim shadow ────────────────────────
	# Wedge of the polygon facing away from the light gets an extra
	# dark overlay — bounce-shadow at the underside of the gem.
	var shadow_wedge := PackedVector2Array()
	for p in pts:
		var t = (p - center).normalized()
		if t.dot(-LIGHT) > 0.25:
			shadow_wedge.append(p)
	if shadow_wedge.size() >= 3:
		shadow_wedge.insert(0, center - LIGHT * size.x * 0.10)
		draw_colored_polygon(shadow_wedge, Color(0, 0, 0, 0.32))

	# ── Layer 6: Top bevel highlight (lit edge) ───────────────────────
	# Bright hairline along the polygon edges facing the light. The
	# "lit edge" cue that makes the orb feel like a 3D solid rather
	# than a flat shape with shading painted on.
	var n := pts.size()
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var edge_mid := (a + b) * 0.5
		var edge_norm := (edge_mid - center).normalized()
		if edge_norm.dot(LIGHT) > 0.10:
			# Pull bevel slightly inward so the dark rim still reads.
			var ai := a - (a - center) * 0.04
			var bi := b - (b - center) * 0.04
			draw_line(ai, bi, Color(1, 1, 1, 0.55 * gloss), 1.3, true)

# Faceted: each triangle (center → edge a → edge b) gets a flat colour
# based on its angular position. Saturated bases blend toward white
# (highlight) or near-black (shadow) instead of being brightness-
# multiplied, which clips on already-saturated colours like our HP red.
func _draw_faceted_body(pts: PackedVector2Array, center: Vector2) -> void:
	var n := pts.size()
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var facet_center := (a + b + center) / 3.0
		var dir := (facet_center - center).normalized()
		var col := _shade_color(dir)
		draw_colored_polygon(PackedVector2Array([center, a, b]), col)

# Smooth: per-vertex colours, Godot interpolates across the triangulation.
# Each vertex shaded via the same blend-toward-white/black model as
# faceted, so saturated colours retain their hue at full brightness.
func _draw_smooth_body(pts: PackedVector2Array, center: Vector2) -> void:
	var colors := PackedColorArray()
	for p in pts:
		var dir = (p - center).normalized()
		colors.append(_shade_color(dir))
	draw_polygon(pts, colors)

# Shading model: blend toward white when normal faces the light, blend
# toward near-black when it faces away. Wider amplitude than the old
# brightness-multiply approach — saturated colours get real highlights
# rather than clipping at 1.0 with no hue shift.
func _shade_color(normal: Vector2) -> Color:
	var lit = normal.dot(LIGHT)  # [-1, 1]
	if lit >= 0.0:
		# Facing light: lerp(base, white, lit * 0.65).
		# 0.65 cap keeps the hue identifiable at peak highlight — pure
		# white would lose the gem's colour identity entirely.
		return fill_color.lerp(Color(1, 1, 1, fill_color.a), lit * 0.65)
	else:
		# Facing away: lerp(base, deep-dark, |lit| * 0.75).
		var dark := Color(fill_color.r * 0.15, fill_color.g * 0.15,
			fill_color.b * 0.18, fill_color.a)
		return fill_color.lerp(dark, -lit * 0.75)

# Emblem renderer — flat, painted, matte. Built for the parchment/wood
# frame so the orbs read as wax-seal discs set into a gilt rim instead
# of glossy 3D gems. No specular, no bevel, no faceted shading.
#
# Construction (outer→inner):
#   1. Single soft drop shadow — orb sits on the card, doesn't float.
#   2. Antique-gold ring — ties the orb to the card's gilt trim.
#   3. Dark groove — chiseled separator between ring and disc face.
#   4. Disc fill — flat base colour.
#   5. Subtle vignette — barely-perceptible darkening toward the edge,
#      like ink pooling on parchment or wax cooling at the rim. NOT a
#      sphere gradient.
#   6. Faint top crescent — hint of paint catching the light. One soft
#      arc, no specular dot.
func _draw_emblem(pts: PackedVector2Array, center: Vector2) -> void:
	var min_dim := minf(size.x, size.y)
	var radius := min_dim * 0.5

	# Layer 1 — one soft drop shadow.
	var shadow_pts := PackedVector2Array()
	for p in pts:
		shadow_pts.append(p + Vector2(0, 2))
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.42))

	# Layer 2 — antique-gold outer ring (slightly expanded polygon).
	# Colour matches the gilt trim seen elsewhere on the card frame.
	var ring_gold := Color(0.62, 0.46, 0.18, 1.0)       # antique brass
	var ring_gold_lit := Color(0.86, 0.69, 0.34, 1.0)   # lit edge
	var ring_pts := PackedVector2Array()
	for p in pts:
		ring_pts.append(p + (p - center).normalized() * 1.0)
	draw_colored_polygon(ring_pts, ring_gold)
	# A faint lighter arc along the top half of the ring suggests a
	# beveled metal edge catching the room light. Subtle — we're not
	# trying to make a coin, we're making a stamped seal.
	var n := pts.size()
	for i in range(n):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var mid := (a + b) * 0.5
		if (mid - center).y < -radius * 0.15:
			draw_line(a, b, ring_gold_lit, 1.2, true)

	# Layer 3 — dark groove just inside the ring (1 px polyline).
	# Reads as a chiseled valley where the wax/metal disc sits down
	# into its setting.
	var groove_pts := PackedVector2Array()
	for p in pts:
		groove_pts.append(center + (p - center) * 0.91)
	var groove_closed := groove_pts.duplicate()
	groove_closed.append(groove_pts[0])
	draw_polyline(groove_closed, Color(0.08, 0.05, 0.03, 0.88), 1.4, true)

	# Layer 4 — disc face. Slightly inset from the ring so the gold
	# rim is visible all the way around.
	var face_pts := PackedVector2Array()
	for p in pts:
		face_pts.append(center + (p - center) * 0.86)
	draw_colored_polygon(face_pts, fill_color)

	# Layer 5 — rim vignette: a darker polyline traced along the disc's
	# inner edge. Reads as ink pooling at the rim or wax cooling
	# slightly darker at the perimeter. NOT a sphere gradient.
	var vignette_color := Color(fill_color.r * 0.55, fill_color.g * 0.55,
		fill_color.b * 0.58, 0.35)
	var vignette_closed := face_pts.duplicate()
	vignette_closed.append(face_pts[0])
	draw_polyline(vignette_closed, vignette_color, 2.5, true)

	# Layer 6 — faint top crescent hinting at directional light.
	# A short arc of slightly-lightened fill along the upper edge of
	# the disc face. No specular hotspot — the goal is "painted on
	# parchment", not "polished glass".
	if min_dim >= 18.0:
		var lit_color := fill_color.lerp(Color(1, 0.97, 0.88, 1), 0.22)
		for i in range(n):
			var a := pts[i]
			var b := pts[(i + 1) % n]
			var mid := (a + b) * 0.5
			if (mid - center).y < -radius * 0.45:
				var ai := center + (a - center) * 0.83
				var bi := center + (b - center) * 0.83
				draw_line(ai, bi, lit_color, 1.5, true)

func _build_shape(sz: Vector2) -> PackedVector2Array:
	match shape:
		"circle":  return PolyBadge._circle(sz)
		"hex":     return PolyBadge._hex(sz)
		"shield":  return PolyBadge._shield(sz)
		"drop":    return PolyBadge._drop(sz)
		"diamond": return PolyBadge._diamond(sz)
		"peak":    return PolyBadge._peak(sz)
		_:         return PolyBadge._circle(sz)


# ─────────────────────────────────────────────────────────────────────────
