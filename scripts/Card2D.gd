extends PanelContainer
## Card2D.gd — 180x252 card. Three layout modes, picked in _build_layout:
##   - v4 (USE_PROCEDURAL_FRAME on): pure Godot-drawn frame, no PNG dep
##   - v3 (USE_NEW_FRAME on): painted PNG frame with POINT_*-anchored labels
##   - v1/legacy: original gilt-banner layout
## Compact battlefield mode swaps to an art-token layout (no rules text).

signal played
signal destroyed
signal floop_clicked


# ─────────────────────────────────────────────────────────────────────────
#  PolyBadge — procedurally drawn stat-orb shape.
# ─────────────────────────────────────────────────────────────────────────
#
# Used by the v4 card layout for the cost orb (hex), ATK plate (heater
# shield), HP plate (blood drop), rarity gem (diamond), and spell peak
# (triangle/pentagon). Renders one of several silhouettes at any size, with a
# fill colour + darker border + soft top-half highlight that mimics a glossy
# gem. No texture asset — pure draw_colored_polygon calls.
class PolyBadge extends Control:
	var fill_color: Color = Color.WHITE
	var border_color: Color = Color(0, 0, 0, 0.55)
	var border_width: float = 1.5
	var shape: String = "hex"   # hex / shield / drop / diamond / peak

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0 or size.y <= 0:
			return
		var pts := _build_shape()
		if pts.size() < 3:
			return

		# ── Layer 1: Drop shadow ───────────────────────────────────────────
		# Offset polygon down/right, darkened. Lifts the orb off the card
		# frame the way Hearthstone's stat gems sit "above" the card body.
		var shadow_offset := Vector2(0, 2)
		var shadow_pts := PackedVector2Array()
		for p in pts:
			shadow_pts.append(p + shadow_offset)
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.50))

		# ── Layer 2: Gradient fill ─────────────────────────────────────────
		# Per-vertex colors — Godot interpolates across the polygon's
		# triangulation. Top vertices get ~1.25× brightness, bottom ~0.70×.
		# Reads as a directional light source from above (canonical for
		# glossy gems in AAA card art).
		var colors := PackedColorArray()
		for p in pts:
			var t = clampf(p.y / size.y, 0.0, 1.0)
			var brightness = lerpf(1.28, 0.62, t)
			colors.append(Color(
				clampf(fill_color.r * brightness, 0.0, 1.0),
				clampf(fill_color.g * brightness, 0.0, 1.0),
				clampf(fill_color.b * brightness, 0.0, 1.0),
				fill_color.a
			))
		draw_polygon(pts, colors)

		# ── Layer 3: Top-half highlight wedge ──────────────────────────────
		# Translucent white over upper half — boosts the gradient's "light
		# from above" cue with a slight glossy band.
		var hl := PackedVector2Array()
		for p in pts:
			if p.y < size.y * 0.5:
				hl.append(p)
		if hl.size() >= 3:
			hl.append(Vector2(size.x * 0.5, size.y * 0.5))
			draw_colored_polygon(hl, Color(1, 1, 1, 0.18))

		# ── Layer 4: Specular dot ──────────────────────────────────────────
		# Small bright circle near top-left — the "glass highlight" trick
		# every AAA gem orb uses to read as polished/wet. Skipped on very
		# small badges (rarity gem) where it'd just be a fuzzy pixel.
		if minf(size.x, size.y) >= 18.0:
			var spec_pos = Vector2(size.x * 0.34, size.y * 0.24)
			var spec_radius = size.x * 0.12
			draw_circle(spec_pos, spec_radius, Color(1, 1, 1, 0.65),
				true, -1.0, true)
			# Smaller, brighter core for extra glass feel
			draw_circle(spec_pos - Vector2(spec_radius * 0.25, spec_radius * 0.25),
				spec_radius * 0.45, Color(1, 1, 1, 0.85), true, -1.0, true)

		# ── Layer 5: Bottom rim shadow ─────────────────────────────────────
		# Vertices in the lower half get a slight dark overlay — gives the
		# orb a "rim" of darker color at its base, matching how 3D-rendered
		# gems pick up bounce-shadow at their underside.
		var rim := PackedVector2Array()
		for p in pts:
			if p.y > size.y * 0.65:
				rim.append(p)
		if rim.size() >= 3:
			rim.insert(0, Vector2(size.x * 0.5, size.y * 0.65))
			draw_colored_polygon(rim, Color(0, 0, 0, 0.20))

		# ── Layer 6: Beveled outline ───────────────────────────────────────
		# Anti-aliased polyline; slightly darker than fill so the edge reads
		# as a chiseled border, not a sticker outline.
		if border_width > 0:
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, border_color, border_width, true)

	func _build_shape() -> PackedVector2Array:
		match shape:
			"hex":     return _hex(size)
			"shield":  return _shield(size)
			"drop":    return _drop(size)
			"diamond": return _diamond(size)
			"peak":    return _peak(size)
			_:         return _hex(size)

	static func _hex(sz: Vector2) -> PackedVector2Array:
		# Pointy-top hexagon (gem-like). 6 vertices.
		var pts := PackedVector2Array()
		var w := sz.x; var h := sz.y
		pts.append(Vector2(w * 0.5, 0.0))        # top
		pts.append(Vector2(w,       h * 0.30))
		pts.append(Vector2(w,       h * 0.70))
		pts.append(Vector2(w * 0.5, h))          # bottom
		pts.append(Vector2(0.0,     h * 0.70))
		pts.append(Vector2(0.0,     h * 0.30))
		return pts

	static func _shield(sz: Vector2) -> PackedVector2Array:
		# Heater-shield silhouette: flat top with corners clipped, pointed
		# bottom apex. Reads as "knight's shield" at hand-card scale.
		var pts := PackedVector2Array()
		var w := sz.x; var h := sz.y
		pts.append(Vector2(w * 0.10, 0.0))
		pts.append(Vector2(w * 0.90, 0.0))
		pts.append(Vector2(w,        h * 0.22))
		pts.append(Vector2(w * 0.92, h * 0.66))
		pts.append(Vector2(w * 0.5,  h))
		pts.append(Vector2(w * 0.08, h * 0.66))
		pts.append(Vector2(0.0,      h * 0.22))
		return pts

	static func _drop(sz: Vector2) -> PackedVector2Array:
		# Blood-drop silhouette: pointed top, rounded bottom (10-point smooth).
		var pts := PackedVector2Array()
		var w := sz.x; var h := sz.y
		pts.append(Vector2(w * 0.5,  0.0))         # top point
		pts.append(Vector2(w * 0.74, h * 0.18))
		pts.append(Vector2(w * 0.93, h * 0.42))
		pts.append(Vector2(w,        h * 0.62))
		pts.append(Vector2(w * 0.88, h * 0.88))
		pts.append(Vector2(w * 0.5,  h))           # rounded base
		pts.append(Vector2(w * 0.12, h * 0.88))
		pts.append(Vector2(0.0,      h * 0.62))
		pts.append(Vector2(w * 0.07, h * 0.42))
		pts.append(Vector2(w * 0.26, h * 0.18))
		return pts

	static func _diamond(sz: Vector2) -> PackedVector2Array:
		# 4-point rhombus — rarity gem at art-bottom (Hearthstone position).
		var pts := PackedVector2Array()
		var w := sz.x; var h := sz.y
		pts.append(Vector2(w * 0.5, 0.0))
		pts.append(Vector2(w,       h * 0.5))
		pts.append(Vector2(w * 0.5, h))
		pts.append(Vector2(0.0,     h * 0.5))
		return pts

	static func _peak(sz: Vector2) -> PackedVector2Array:
		# Pentagonal cap pointing up — used on spell cards above the banner so
		# the silhouette differs from creatures (Slay-the-Spire convention).
		var pts := PackedVector2Array()
		var w := sz.x; var h := sz.y
		pts.append(Vector2(w * 0.5, 0.0))      # apex
		pts.append(Vector2(w,       h * 0.62))
		pts.append(Vector2(w * 0.78, h))
		pts.append(Vector2(w * 0.22, h))
		pts.append(Vector2(0.0,     h * 0.62))
		return pts

	static func _circle(sz: Vector2, segments: int = 32) -> PackedVector2Array:
		# 32-vertex polygon approximating a circle. Drives the GemOrb's per-
		# vertex shading the same way hex / shield / drop do, but the dense
		# vertex ring makes the silhouette read as a perfect orb at any size.
		# Hearthstone / Marvel Snap / Card Wars all use circles for stat gems
		# — geometric shapes (hex, shield, drop) clash with painted creature
		# art the way the v1 prototype's flat ColorRect circles did. The orb
		# is fantasy-canonical; the polygon-shape detour was a mistake.
		var pts := PackedVector2Array()
		var cx := sz.x * 0.5
		var cy := sz.y * 0.5
		# Slight Y inset (98 %) so the orb isn't perfectly tangent to its
		# bounding box on top and bottom — leaves a hairline of breathing room
		# that lets the drop shadow read against the card body without being
		# clipped by overlapping siblings.
		var rx := sz.x * 0.49
		var ry := sz.y * 0.49
		for i in range(segments):
			var ang = TAU * float(i) / float(segments) - PI * 0.5
			pts.append(Vector2(cx + rx * cos(ang), cy + ry * sin(ang)))
		return pts


# ─────────────────────────────────────────────────────────────────────────
#  GemOrb — premium 3D stat orb (replaces PolyBadge for cost/atk/hp).
# ─────────────────────────────────────────────────────────────────────────
#
# What makes a card-game stat orb look "expensive" (Hearthstone / STS /
# MtG Arena) vs "flat" (early prototype, MtG paper):
#
#   1. Saturated colours need WHITE blending for highlights, not brightness
#      multiplication. (1.4×red is just clipped red — same hue, no glow.)
#   2. Drop shadow lifts the orb off the card surface. One layer reads as a
#      sticker, three stacked layers read as floating glass.
#   3. Outer dark rim (near-black, slightly larger silhouette) gives the
#      chiseled edge AAA gems have, separately from any AA outline.
#   4. Faceted bodies (flat planes of colour per triangle, sharp edges
#      between) read as "cut crystal" — used for STS-style hex mana gems.
#      Smooth bodies (per-vertex interpolation across a polygon) read as
#      "polished glass dome" — used for Hearthstone-style shield / drop.
#   5. Specular hotspot is a cluster, not a dot: wide soft halo + small
#      bright core, offset toward the light. Sells "wet/polished".
#   6. Inner bottom-rim shadow + top bevel highlight together describe the
#      orb as a 3D object lit from upper-left, regardless of facet count.
#
# Pure draw API — no shader (project runs on GL Compatibility), no texture
# dependency, no per-instance allocation beyond the Control itself.
class GemOrb extends Control:
	var fill_color: Color = Color.WHITE
	var shape: String = "hex"             # hex / shield / drop / diamond / peak
	var style: String = "faceted"         # "faceted" or "smooth"
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
			draw_circle(spec_pos, rad_outer, Color(1, 1, 1, 0.38),
				true, -1.0, true)
			draw_circle(spec_pos + LIGHT * rad_inner * 0.35,
				rad_inner, Color(1, 1, 1, 0.95), true, -1.0, true)

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
				draw_line(ai, bi, Color(1, 1, 1, 0.55), 1.3, true)

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
#  SphereOrb — glossy 3D sphere drawn purely via _draw() circle stacks.
# ─────────────────────────────────────────────────────────────────────────
#
# The "make a simple circle look incredible" recipe (per
# cssanimation.rocks/spheres + Lettier's 3D shader primer): the wow factor
# comes from STACKING many subtle layers, not one fancy effect.
#
# Eight layers, back to front:
#   1. Outer glow halo — soft colored bloom past the silhouette.
#   2. Drop shadow — flattened circle below, anchors weight.
#   3. Sphere edge fill — desaturated dark base colour at full radius.
#   4. Directional gradient — ~18 nested circles drifting toward the light,
#      each one a step brighter; fakes a per-pixel radial gradient without
#      a shader and reads as smooth lit shading.
#   5. Ambient-occlusion shadow — bottom-right dark blob, simulates light
#      falloff on the side facing away from the source.
#   6. Top rim arc — thin lit edge curving over the upper silhouette,
#      catches the eye and disambiguates the orb from a flat shape.
#   7. Specular halo — 4 concentric white circles at upper-left, the wide
#      pool of light hitting the wet/glass surface.
#   8. Specular core — small bright pinprick offset toward the light hot
#      centre; sells the "polished glass" reading.
# Optional pulse (set pulse_amount > 0) animates the outer glow with a
# slow sine sweep — used on the cost orb so the mana gem visibly "breathes".
#
# Forward+ shaders would do this in 1/10th the lines but cause compile
# errors on GL Compatibility (see commit be8ef2d); pure _draw is shader-
# free and works on every renderer.
class SphereOrb extends Control:
	var fill_color: Color = Color.WHITE
	var glow_color: Color = Color(0, 0, 0, 0)   # 0-alpha = auto-derive
	var pulse_amount: float = 0.0               # 0 disables animation
	# When true, _draw uses a 5-layer stripped-down recipe instead of
	# the full 39-layer glossy stack. Each SphereOrb's _draw records its
	# draw commands once but those commands are REPLAYED every frame as
	# part of the CanvasItem render — with 122 cards × 3 orbs in the
	# Card Gallery that was 122 × 3 × 39 = ~14 300 sub-draws/frame on
	# the GL Compatibility renderer just for orbs. Simple mode cuts
	# that to ~1 800 — visible orbs still read as 3D spheres, just
	# without the 18-step directional gradient or the rim arc.
	var simple_mode: bool = false
	const LIGHT_DIR := Vector2(-0.45, -0.45)   # upper-left light source

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if pulse_amount > 0.0:
			set_process(true)

	func _process(_delta: float) -> void:
		# Pulse-driven orbs redraw every frame so the glow breathes. 3 orbs
		# x 60 fps = 180 redraws/sec — cheap on any renderer (each redraw
		# is ~50 draw_circle calls and the GPU handles them in microseconds).
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0 or size.y <= 0:
			return
		if simple_mode:
			_draw_simple()
			return
		var center := size * 0.5
		var R: float = minf(size.x, size.y) * 0.42  # sphere radius
		var spec_pos := center + LIGHT_DIR * Vector2(R, R)

		# Pulse factor — 1.0 when pulse_amount = 0, oscillates otherwise.
		var t := float(Time.get_ticks_msec()) / 1000.0
		var pulse := sin(t * 1.6) * 0.5 + 0.5  # 0..1
		var pulse_mul := 1.0 + (pulse - 0.5) * 2.0 * pulse_amount

		# Effective glow color — fall back to fill_color if not overridden.
		var glow: Color = glow_color
		if glow.a < 0.001:
			glow = Color(fill_color.r, fill_color.g, fill_color.b, 1.0)

		# ── 1. Outer glow halo — concentric color-tinted rings ──────────
		# 5 rings, alpha tapering outward. Pulse modulates intensity.
		for i in range(5):
			var ring_r := R * (1.06 + float(i) * 0.16)
			var ring_a := (0.16 - float(i) * 0.028) * pulse_mul
			if ring_a > 0.005:
				draw_circle(center, ring_r,
					Color(glow.r, glow.g, glow.b, ring_a), true, -1.0, true)

		# ── 2. Drop shadow — flattened ovals below the orb ─────────────
		# Faked with offset darker circles (no native ellipse in _draw).
		var sh_pos := center + Vector2(0, R * 0.62)
		for i in range(4):
			var sh_r := R * (0.85 - float(i) * 0.11)
			draw_circle(sh_pos, sh_r,
				Color(0, 0, 0, 0.18 - float(i) * 0.04), true, -1.0, true)

		# ── 3. Sphere edge — dark base, fills the silhouette ───────────
		var edge_col := Color(fill_color.r * 0.28, fill_color.g * 0.28,
			fill_color.b * 0.32, 1.0)
		draw_circle(center, R, edge_col, true, -1.0, true)

		# ── 4. Directional gradient — nested circles drifting toward
		#      the light. 18 layers fakes a smooth radial gradient.
		var bright_col := fill_color.lerp(Color(1, 1, 1, 1), 0.45)
		var N := 18
		for i in range(N):
			var t_n := float(i) / float(N - 1)
			var pos := center.lerp(spec_pos, t_n * 0.55)
			var grad_r := R * (1.0 - t_n) * 0.95
			var col := fill_color.lerp(bright_col, t_n)
			if grad_r > 0.5:
				draw_circle(pos, grad_r, col, true, -1.0, true)

		# ── 5. Ambient-occlusion shadow — bottom-right dark blob ───────
		var ao_pos := center + Vector2(R * 0.38, R * 0.40)
		for i in range(4):
			var ao_r := R * (0.55 - float(i) * 0.09)
			draw_circle(ao_pos, ao_r, Color(0, 0, 0, 0.06),
				true, -1.0, true)

		# ── 6. Top rim arc — thin lit edge curving over the upper half ─
		draw_arc(center, R * 0.93, deg_to_rad(200), deg_to_rad(340),
			48, Color(1, 1, 1, 0.45), 1.6, true)

		# ── 7. Specular halo — 4 concentric whites at the light position
		for i in range(4):
			var sp_r := R * (0.50 - float(i) * 0.10)
			var sp_a := 0.12 + float(i) * 0.10
			if sp_r > 0.5:
				draw_circle(spec_pos, sp_r,
					Color(1, 1, 1, sp_a), true, -1.0, true)

		# ── 8. Specular core — tiny bright pinprick ────────────────────
		# Offset slightly further toward the light from the halo centre
		# so the two read as a cluster, not a single dot.
		var core_pos := spec_pos + LIGHT_DIR * R * 0.12
		if R >= 14.0:
			draw_circle(core_pos, R * 0.10,
				Color(1, 1, 1, 0.92), true, -1.0, true)
			draw_circle(core_pos - Vector2(R * 0.02, R * 0.02), R * 0.05,
				Color(1, 1, 1, 1.0), true, -1.0, true)

	# Stripped-down 5-layer recipe for static_display contexts. Still
	# reads as a 3D sphere (dark rim + lit centre + bright spec dot)
	# but cuts ~34 draw_circle commands out of the per-frame budget.
	# 122 cards × 3 orbs × 34 saved = ~12 500 fewer draws/frame in the
	# Card Gallery, which is the dominant cost after pulse + shadows.
	func _draw_simple() -> void:
		var center := size * 0.5
		var R: float = minf(size.x, size.y) * 0.42
		var spec_pos := center + LIGHT_DIR * Vector2(R, R)
		# 1. Drop shadow (single circle, no stack)
		draw_circle(center + Vector2(0, R * 0.55), R * 0.78,
			Color(0, 0, 0, 0.30), true, -1.0, true)
		# 2. Sphere edge (dark base)
		draw_circle(center, R,
			Color(fill_color.r * 0.30, fill_color.g * 0.30,
				fill_color.b * 0.35, 1.0), true, -1.0, true)
		# 3. Inner lit body (single circle, slightly smaller + offset toward
		#    light, brighter colour). Two-step gradient instead of 18.
		draw_circle(center + LIGHT_DIR * R * 0.12, R * 0.85,
			fill_color, true, -1.0, true)
		# 4. Specular halo (single soft white)
		draw_circle(spec_pos, R * 0.35,
			Color(1, 1, 1, 0.30), true, -1.0, true)
		# 5. Specular core (single bright pinprick)
		draw_circle(spec_pos + LIGHT_DIR * R * 0.10, R * 0.10,
			Color(1, 1, 1, 0.92), true, -1.0, true)


@export var card_id: String = ""
@export var is_opponent: bool = false
@export var is_on_battlefield: bool = false
# When true, the card is being rendered in a non-interactive context
# (Card Gallery, Deck Viewer, Reward preview, etc.). Set BEFORE add_child
# so it's seen by _ready → _build_layout. Disables the SphereOrb pulse
# animations — gallery scenes show 100+ cards at once, and per-frame
# queue_redraw on every cost+HP orb chews ~12 000 draw_circle calls per
# frame even when nothing is moving. Static display kills the animation
# entirely for those contexts; combat cards keep their pulse.
@export var static_display: bool = false
# When true, _build_full_layout_v4 builds the orb spheres with empty stat
# labels. Used by CardTextureCache.bake() — the snapshot becomes a card with
# blank cost/ATK/HP discs, and the live overlay layer painted over the top
# fills in the actual numbers. Without this flag the baked numerals would
# show through and clash with the live overlay text on any stat change.
@export var bake_strip_stats: bool = false
# When true, _build_layout dispatches to _build_baked_overlay_layout instead
# of the heavy v4 layout. That layout is just a TextureRect (pulled from
# CardTextureCache) plus a handful of live overlay nodes (cost / atk / hp /
# floop). update_stat_display still works through the same _cost_label /
# _atk_label / _hp_label refs, so combat logic is unchanged. Falls back to
# v4 silently if CardTextureCache hasn't pre-baked this card yet.
@export var live_baked_mode: bool = false

var card_data: Dictionary = {}
var current_hp := 0
var current_atk := 0
var current_lane: int = -1
var current_row: int = 0  # 0 = front, 1 = back (4x4 board)
var has_attacked_this_turn: bool = false
var summoned_this_turn: bool = true
var will_floop: bool = false
var has_flooped_this_turn: bool = false
var last_stand_used: bool = false
var is_token: bool = false
var temp_atk_buff: int = 0
# Battlefield cards render at ~73% size so 4 rows fit on screen without
# clipping. Hand cards stay full size for readability. Set before _ready
# (e.g. on instantiate) or via set_compact_mode() after.
var compact_mode: bool = false

var _name_label: Label
var _atk_label: Label
var _hp_label: Label
var _cost_label: Label
var _desc_label: Label
var _type_label: Label
var _floop_indicator: Label
var _rarity_strip: ColorRect
var _art_rect: Control
var _cost_badge: Control  # Panel (v3/legacy) or GemOrb (v4/compact) — both Control
var _frame_tex: TextureRect
var _atk_badge: HBoxContainer
var _hp_badge: HBoxContainer
var _default_border_color: Color
# v4 stat plates carry their own base text colour (dark-on-gold for ATK,
# light-on-red for HP). Cache the colours at build time so update_stat_display
# can restore them without forcing the legacy Color.WHITE that would render
# invisible against the gold shield.
var _atk_base_color: Color = Color.WHITE
var _hp_base_color: Color = Color.WHITE

var _is_hovered := false
var _is_being_dragged := false
var _is_playing := false
var _drag_offset := Vector2.ZERO
var _hand_target_position := Vector2.ZERO
var _hand_target_rotation := 0.0
# Resting scale for hand cards. Set via set_hand_target by Combat._layout_hand
# (currently 0.8 for the Hearthstone-style smaller-cards-at-rest look). Hover
# scales to 1.15 — a 1.15/0.8 ≈ 1.44x visual pop relative to rest. Restored
# on _on_mouse_exited and _end_drag-not-played.
var _hand_target_scale := Vector2.ONE

const CARD_W := 180
const CARD_H := 252
const CARD_SIZE := Vector2(CARD_W, CARD_H)
# Battlefield slot is 140×145 (Combat._make_lane_slot). At 180×252 the
# height constraint binds first: 145/252 ≈ 0.575. That yields a 103.5×145
# compact card — fits both dimensions cleanly.
const COMPACT_SCALE := 0.575
const PLAY_THRESHOLD_Y := 0.45

# Painted-frame zone rects, in pixel coords of the 300x400 source frame
# (assets/frames/frame_creature_*.png). Each rect is the readable interior of a
# painted region — change a number here, the corresponding label moves. This is
# the single source of truth for text positioning on the v3 (PNG-frame) layout.
# v4 (procedural) uses normalized 0–1 anchors instead and does not consume these.
const FRAME_REF_SIZE := Vector2(300, 400)
# Card scaled to 180x252 from the 300x400 ref → 0.6 ratio.
const FRAME_TO_CARD_SCALE := 0.6

# ─────────────────────────────────────────────────────────────────────────
# CARD TEXT POSITIONS (read this before changing any number below)
# ─────────────────────────────────────────────────────────────────────────
#
# Each label (cost, name, type, desc, ATK, HP, FLOOP) is placed by anchoring
# to a single POINT_* (the painted-region center, in 300x400 frame ref coords)
# via _center_at_point(label, point, size). The helper sets symmetric offsets
# so the label rect is centered on the point — change a POINT_ and the label
# moves; change a SIZE_ and only the label's text-fit box changes.
#
# HOW TO RE-DERIVE THESE NUMBERS:
#   1. Run:   python tools/measure_frame.py
#   2. The script reads the frame PNG pixel-by-pixel, finds the bbox of each
#      painted region (red orbs by color, banner by dark gray, scroll by gold,
#      well by parchment tan), and prints a Vector2 for each center.
#   3. Paste the printed values into the POINT_* constants below.
#
# DO NOT EYEBALL THESE VALUES.  Earlier guesses put POINT_NAME ~20px above
# where the banner actually is — the gold ornament on top of the banner made
# it visually appear higher. The script measures pixel data, so it can't be
# fooled the same way. If you tweak any value by hand, re-run the script first
# to know the true painted center, then adjust from there.
#
# WHY POINT+SIZE (NOT ANCHOR RECTS):
#   - Godot's Label.vertical_alignment=CENTER misaligns when the rect is
#     smaller than the font's line box (known Godot 4 bug, see forum thread
#     "vertical-alignment-center-wont-center"). Generous SIZE_* avoids this.
#   - Asymmetric anchor rects also bias where horizontal_alignment=CENTER
#     computes the visual midpoint. Point+symmetric-offsets sidesteps that.
#
# FONT OPTICAL CENTERING:
#   - Caps-only text (NAME, CREATURE, FLOOP, all stat numerals) sits visually
#     above geometric center because the font's line box reserves descender
#     space the glyphs don't use.
#   - GameTheme wraps Cinzel in FontVariations with spacing_bottom = -3,
#     which shrinks the line box and shifts centered text ~1.5px down to its
#     optical center. If text still looks high after re-measuring, push that
#     value more negative; if it looks low, push toward 0.
const POINT_COST    := Vector2(50.0, 46.0)    # red sphere top-left core, bbox (23,19)-(77,73)
const POINT_NAME    := Vector2(178.5, 51.5)   # banner DARK interior, bbox (82,38)-(275,65)
const POINT_TYPE    := Vector2(149.5, 268.5)  # gold divider scroll, bbox (45,261)-(254,276)
const POINT_DESC    := Vector2(149.5, 322.5)  # parchment well, bbox (30,284)-(269,361)
const POINT_ATK     := Vector2(35.0, 350.0)   # red atk sphere highlight
const POINT_HP      := Vector2(261.5, 351.0)  # blue hp sphere, bbox (241,330)-(282,372)
const POINT_FLOOP   := Vector2(150.0, 388.0)  # bottom frame strip, between orbs

const SIZE_COST     := Vector2(48, 36)
const SIZE_NAME     := Vector2(210, 38)
const SIZE_TYPE     := Vector2(170, 26)
const SIZE_DESC     := Vector2(220, 80)
const SIZE_STAT     := Vector2(48, 36)    # shared by ATK and HP
const SIZE_FLOOP    := Vector2(150, 24)


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	if compact_mode:
		_apply_compact_layout()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if card_data.is_empty() and card_id != "":
		card_data = CardDB.get_card_data(card_id)
	if card_data.size() > 0:
		if is_creature():
			current_hp = card_data.hp
			current_atk = card_data.atk

	_build_style()
	_build_layout()


func set_compact_mode(enabled: bool) -> void:
	# Switch a card between hand-size (full) and battlefield-size (compact-token).
	# Swaps BOTH the dimensions AND the internal layout tree — the two modes
	# have entirely different visual identities (full card vs art token).
	if compact_mode == enabled:
		return
	compact_mode = enabled
	_apply_compact_layout()
	# Null cached widget references first, then free children. Otherwise any
	# update_stat_display / update_floop_display call between teardown and
	# rebuild would touch freed nodes.
	_name_label = null
	_atk_label = null
	_hp_label = null
	_cost_label = null
	_desc_label = null
	_type_label = null
	_floop_indicator = null
	_rarity_strip = null
	_art_rect = null
	_cost_badge = null
	_frame_tex = null
	_atk_badge = null
	_hp_badge = null
	for child in get_children():
		child.free()
	_build_layout()


func _apply_compact_layout() -> void:
	# Battlefield cards shrink by resizing — internal layout uses anchor-based
	# positioning (anchor_left = 0.06 etc.) so children rescale automatically.
	# Avoid touching `scale` here: Container parents fight with it and the
	# slot reservation desyncs from the visual footprint.
	var target_size: Vector2 = CARD_SIZE * COMPACT_SCALE if compact_mode \
		else CARD_SIZE
	custom_minimum_size = target_size
	size = target_size
	# Hand-card transforms (0.8x rest scale, bottom-centre pivot, fan
	# rotation) need to reset when the card moves to the battlefield — the
	# slot positions cards at scale 1 / rotation 0 / pivot top-left.
	scale = Vector2.ONE
	rotation = 0.0
	pivot_offset = Vector2.ZERO
	_hand_target_scale = Vector2.ONE
	_hand_target_position = Vector2.ZERO
	_hand_target_rotation = 0.0


func is_creature() -> bool:
	return card_data.get("type", "creature") == "creature"

func is_spell() -> bool:
	return card_data.get("type", "") == "spell"

func has_keyword(kw: String) -> bool:
	if not card_data.has("keywords"):
		return false
	return card_data.keywords.has(kw)


func _spell_target_label() -> String:
	# Maps the spell data's `targeting` field to a short display string. Returns
	# empty for "none" so non-targeted spells leave the bottom strip clean.
	match String(card_data.get("targeting", "")):
		"enemy_creature":    return "→ ENEMY"        # → ENEMY
		"friendly_creature": return "→ FRIENDLY"     # → FRIENDLY
		"any_creature":      return "→ ANY CREATURE" # → ANY CREATURE
		"any":               return "✦ ANY TARGET"   # ✦ ANY TARGET
		_:                   return ""

func has_floop() -> bool:
	return card_data.has("floop")

func can_attack() -> bool:
	if has_attacked_this_turn: return false
	if will_floop: return false
	if has_flooped_this_turn: return false
	if card_data.get("passive", "") == "cannot_attack_wall": return false
	if card_data.get("passive", "") == "siege": return true
	return true

func effective_atk() -> int:
	return current_atk + temp_atk_buff


# ═══════════════════════════════════════════
#  CARD BACKGROUND
# ═══════════════════════════════════════════

func _build_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Color(0, 0, 0, 0)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", s)
	_default_border_color = Color(0, 0, 0, 0)


# ═══════════════════════════════════════════
#  LAYOUT — layered: art → frame → banner → content
# ═══════════════════════════════════════════

func _find_card_art() -> Texture2D:
	var cid = card_data.get("id", "")
	var name_id = card_data.get("name", "").to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = null
	if is_spell():
		art = GameTheme.try_load_spell_art(cid)
		if art == null:
			art = GameTheme.try_load_spell_art(name_id)
	if art == null:
		art = GameTheme.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = GameTheme.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = GameTheme.try_load_creature_art("e_" + name_id)
	return art


func _build_layout() -> void:
	if card_data.is_empty():
		return
	# Reset stat base colours each build; v4 overrides per-plate so its ATK
	# reads dark-on-gold and HP light-on-red. Other layouts keep the
	# legacy Color.WHITE.
	_atk_base_color = Color.WHITE
	_hp_base_color = Color.WHITE
	if compact_mode:
		# compact_mode takes priority — once a card is played to the
		# battlefield it switches to a token-style render that doesn't
		# benefit from baking (already ~10 nodes total).
		_build_compact_layout()
	elif live_baked_mode and CardTextureCache.has(card_data):
		# Only enter the fast path if the texture is actually cached. On a
		# cache miss we fall through to the full layout — the next time the
		# same card is drawn after CardTextureCache.bake_many runs, the
		# cache hit kicks us into the cheap render.
		_build_baked_overlay_layout()
	elif GameTheme.USE_PROCEDURAL_FRAME:
		_build_full_layout_v4()
	elif GameTheme.USE_NEW_FRAME:
		_build_full_layout_v3()
	else:
		_build_full_layout()


# ═══════════════════════════════════════════
#  COMPACT (BATTLEFIELD) LAYOUT — token style
#  Full-card art, corner stats only. No name banner, no description, no
#  rarity strip — just the visual identity needed to recognize a creature
#  on the field. Hand-style detail panel still appears on hover.
# ═══════════════════════════════════════════

func _build_compact_layout() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Art fills the card top-to-bottom (with a thin inset for the frame).
	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_clip := Control.new()
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.anchor_left = 0.04
		art_clip.anchor_right = 0.96
		art_clip.anchor_top = 0.04
		art_clip.anchor_bottom = 0.96
		root.add_child(art_clip)
		_art_rect = art_clip
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)
	else:
		# Semantic icon placeholder — bg tinted by card_id hash + centered
		# chess-piece/skull/etc. picked from the creature's name+keywords.
		_art_rect = _build_placeholder_art(root, 0.04, 0.96, 0.04, 0.96)

	# Dark gradient overlay at the bottom so corner badges read against any art.
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.anchor_left = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_top = 0.70
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	# Compact battlefield stat orbs — same GemOrb class as hand cards,
	# scaled down. Shape encodes the stat (hex=cost, shield=ATK, drop=HP),
	# so we drop the kenney sword/heart silhouettes that read "cheap" at
	# 18px. The number sits on the gem directly, Hearthstone-style.

	# Compact battlefield stat orbs — round gems matching the hand-card
	# trio. Shape uniformity (3 circles) reads cleaner than 3 polygons at
	# this scale; position + colour disambiguate cost/ATK/HP.

	# Top-left cost orb.
	var c_cost := GemOrb.new()
	c_cost.shape = "circle"
	c_cost.style = "smooth"
	c_cost.fill_color = GameTheme.COST_BLUE_GEM
	c_cost.position = Vector2(4, 4)
	c_cost.custom_minimum_size = Vector2(30, 30)
	c_cost.size = Vector2(30, 30)
	_cost_badge = c_cost
	root.add_child(c_cost)
	_cost_label = _build_orb_number_label(str(card_data.get("cost", 0)),
		14, true)
	c_cost.add_child(_cost_label)

	# Bottom-left ATK and bottom-right HP gems (creatures only).
	if is_creature():
		var c_atk := GemOrb.new()
		c_atk.shape = "circle"
		c_atk.style = "smooth"
		c_atk.fill_color = GameTheme.ATK_GOLD_SHIELD
		c_atk.anchor_left = 0.0; c_atk.anchor_right = 0.0
		c_atk.anchor_top = 1.0;  c_atk.anchor_bottom = 1.0
		c_atk.offset_left = 4;   c_atk.offset_right = 36
		c_atk.offset_top = -36;  c_atk.offset_bottom = -4
		root.add_child(c_atk)
		_atk_base_color = Color(0.118, 0.078, 0.024)
		_atk_label = _build_orb_number_label(str(current_atk), 14, false)
		c_atk.add_child(_atk_label)
		_atk_badge = null

		var c_hp := GemOrb.new()
		c_hp.shape = "circle"
		c_hp.style = "smooth"
		c_hp.fill_color = GameTheme.HEALTH_RED_DROP
		c_hp.anchor_left = 1.0; c_hp.anchor_right = 1.0
		c_hp.anchor_top = 1.0;  c_hp.anchor_bottom = 1.0
		c_hp.offset_left = -36; c_hp.offset_right = -4
		c_hp.offset_top = -36;  c_hp.offset_bottom = -4
		root.add_child(c_hp)
		_hp_base_color = Color(1, 0.97, 0.92)
		_hp_label = _build_orb_number_label(str(current_hp), 14, true)
		c_hp.add_child(_hp_label)
		_hp_badge = null

	# Floop indicator (only shown when the player has toggled floop on).
	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 10)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_floop_indicator.add_theme_constant_override("outline_size", 4)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.anchor_left = 0.0
	_floop_indicator.anchor_right = 1.0
	_floop_indicator.anchor_top = 0.0
	_floop_indicator.anchor_bottom = 0.0
	_floop_indicator.offset_top = 30
	_floop_indicator.offset_bottom = 46
	_floop_indicator.visible = false
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floop_indicator)


# ═══════════════════════════════════════════
#  BAKED OVERLAY LAYOUT — texture + live stat labels
# ═══════════════════════════════════════════
#
# Fast path for hand cards (and any other context where a pre-baked texture
# exists in CardTextureCache). The heavy v4 frame / art / banner / well /
# orb-sphere visuals are flattened into a single ImageTexture; only the
# dynamic numerals (cost/atk/hp), floop indicator, and an invisible border
# panel remain as live nodes. Per-card render cost drops from ~40 sub-draws
# to ~6 (1 TextureRect quad + ~3 Label glyph batches + 1 Panel border).
#
# Anchor positions for the overlay labels mirror the v4 orb positions exactly
# so they land inside the orb spheres painted in the bake.

func _build_baked_overlay_layout() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Pre-baked texture (cache hit guaranteed by _build_layout's gate).
	var tex: Texture2D = CardTextureCache.get_texture(card_data)

	var tex_rect := TextureRect.new()
	tex_rect.texture = tex
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP
	# Centre the 204×276 texture over the 180×252 card. The 12 px padding on
	# each side carries the cost/ATK/HP orb overhang past the card edge —
	# same visual as the v4 live layout's intentional orb-overhang.
	tex_rect.anchor_left = 0.5; tex_rect.anchor_right = 0.5
	tex_rect.anchor_top = 0.5; tex_rect.anchor_bottom = 0.5
	tex_rect.offset_left = -float(CardTextureCache.TEX_W) * 0.5
	tex_rect.offset_right = float(CardTextureCache.TEX_W) * 0.5
	tex_rect.offset_top = -float(CardTextureCache.TEX_H) * 0.5
	tex_rect.offset_bottom = float(CardTextureCache.TEX_H) * 0.5
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tex_rect)

	# ── Live overlay: cost orb numeral ──
	# Wrapper Control positioned exactly where the v4 cost SphereOrb sits
	# (anchor 0,0 with -9..35 offsets). The label inside uses PRESET_FULL_RECT
	# so it centres inside the sphere painted underneath.
	var cost_slot := Control.new()
	cost_slot.anchor_left = 0.0; cost_slot.anchor_right = 0.0
	cost_slot.anchor_top = 0.0; cost_slot.anchor_bottom = 0.0
	cost_slot.offset_left = -9; cost_slot.offset_right = 35
	cost_slot.offset_top = -9; cost_slot.offset_bottom = 35
	cost_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cost_slot)
	_cost_label = _make_stat_number(str(card_data.get("cost", 0)),
		Color(1, 0.98, 0.90), 0,
		Color(0.30, 0.65, 1.00, 0.85))
	cost_slot.add_child(_cost_label)
	# _cost_badge is read externally by some hover code paths — point it at
	# the overlay anchor so hover effects still have a Control to grab.
	_cost_badge = cost_slot

	if is_creature():
		# ── Live overlay: ATK orb numeral (bottom-left) ──
		var atk_slot := Control.new()
		atk_slot.anchor_left = 0.0; atk_slot.anchor_right = 0.0
		atk_slot.anchor_top = 1.0; atk_slot.anchor_bottom = 1.0
		atk_slot.offset_left = -9; atk_slot.offset_right = 35
		atk_slot.offset_top = -35; atk_slot.offset_bottom = 9
		atk_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(atk_slot)
		_atk_base_color = Color(0.10, 0.07, 0.02)  # dark-on-gold, matches v4
		_atk_label = _make_stat_number(str(current_atk), _atk_base_color, 0,
			Color(1.00, 0.78, 0.20, 0.90))
		atk_slot.add_child(_atk_label)
		_atk_badge = null

		# ── Live overlay: HP orb numeral (bottom-right) ──
		var hp_slot := Control.new()
		hp_slot.anchor_left = 1.0; hp_slot.anchor_right = 1.0
		hp_slot.anchor_top = 1.0; hp_slot.anchor_bottom = 1.0
		hp_slot.offset_left = -35; hp_slot.offset_right = 9
		hp_slot.offset_top = -35; hp_slot.offset_bottom = 9
		hp_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(hp_slot)
		_hp_base_color = Color(1, 0.97, 0.92)
		_hp_label = _make_stat_number(str(current_hp), _hp_base_color, 0,
			Color(1.00, 0.30, 0.20, 0.90))
		hp_slot.add_child(_hp_label)
		_hp_badge = null

	# ── Live overlay: floop indicator ──
	# Same anchors as the v4 layout's floop label so it lands in the same
	# bottom strip. Toggled via update_floop_display().
	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 10)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.add_theme_color_override("font_outline_color",
		Color(0, 0, 0, 0.95))
	_floop_indicator.add_theme_constant_override("outline_size", 3)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_floop_indicator.anchor_left = 0.24; _floop_indicator.anchor_right = 0.76
	_floop_indicator.anchor_top = 0.925; _floop_indicator.anchor_bottom = 1.0
	_floop_indicator.visible = false
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floop_indicator)

	# ── Stub refs ────────────────────────────────────────────────────────
	# External callers (update_floop_display, _on_mouse_entered) read
	# _name_label / _desc_label / _type_label / _rarity_strip / _art_rect.
	# In baked mode the art is part of the texture and can't be tinted
	# individually — set _art_rect = null so update_floop_display's
	# `if _art_rect:` guard skips the art modulate. The other refs get
	# invisible Labels so null-deref paths don't crash.
	_name_label = Label.new()
	_name_label.visible = false
	_name_label.text = card_data.get("name", "")
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_label)
	_desc_label = Label.new()
	_desc_label.visible = false
	_desc_label.text = card_data.get("desc", "")
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_desc_label)
	_type_label = Label.new()
	_type_label.visible = false
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_type_label)
	_rarity_strip = ColorRect.new()
	_rarity_strip.visible = false
	_rarity_strip.color = GameTheme.rarity_color(card_data.get("rarity", "common"))
	_rarity_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_rarity_strip)
	_art_rect = null


# ═══════════════════════════════════════════
#  FULL (HAND) LAYOUT — name banner, art, description, footer stats
# ═══════════════════════════════════════════

func _build_full_layout() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Layer 1: Card art clipped inside frame window ──
	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_clip := Control.new()
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.anchor_left = 0.06
		art_clip.anchor_right = 0.94
		art_clip.anchor_top = 0.05
		art_clip.anchor_bottom = 0.54
		root.add_child(art_clip)
		_art_rect = art_clip

		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.anchor_bottom = 1.5
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)
	else:
		# Semantic icon placeholder for the hand-card layout's art window.
		_art_rect = _build_placeholder_art(root, 0.06, 0.94, 0.05, 0.54)

	# ── Layer 2: Ornate frame overlay ──
	if GameTheme.tex_card_frame_ornate:
		_frame_tex = TextureRect.new()
		_frame_tex.texture = GameTheme.tex_card_frame_ornate
		_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_spell():
			_frame_tex.self_modulate = Color(0.85, 0.78, 1.0)
		elif is_opponent:
			_frame_tex.self_modulate = Color(1.0, 0.82, 0.78)
		root.add_child(_frame_tex)

	# ── Layer 3: Name banner (top, over art) ──
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_left = 0.06
	banner.anchor_right = 0.94
	banner.anchor_top = 0.04
	banner.anchor_bottom = 0.16
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.06, 0.05, 0.04, 0.88)
	bs.border_color = Color(0.65, 0.50, 0.25, 0.8)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(3)
	bs.content_margin_left = 2
	bs.content_margin_right = 4
	bs.content_margin_top = 0
	bs.content_margin_bottom = 0
	banner.add_theme_stylebox_override("panel", bs)
	root.add_child(banner)

	var banner_row := HBoxContainer.new()
	banner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.add_theme_constant_override("separation", 3)
	banner.add_child(banner_row)

	_cost_badge = _make_circle_badge(GameTheme.MANA_BLUE, 18)
	banner_row.add_child(_cost_badge)
	_cost_label = _make_badge_label(str(card_data.cost), 11)
	_cost_badge.add_child(_cost_label)

	_name_label = Label.new()
	_name_label.text = card_data.name
	if GameTheme.font_display:
		_name_label.add_theme_font_override("font", GameTheme.font_display)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", GameTheme.IVORY)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("outline_size", 2)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.add_child(_name_label)

	# ── Gold divider at art-text boundary ──
	var divider := ColorRect.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.anchor_left = 0.07
	divider.anchor_right = 0.93
	divider.anchor_top = 0.555
	divider.anchor_bottom = 0.565
	divider.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.6)
	root.add_child(divider)

	# ── Layer 4: Content in stone area ──
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	content.anchor_left = 0.07
	content.anchor_right = 0.93
	content.anchor_top = 0.57
	content.anchor_bottom = 0.97
	root.add_child(content)

	_rarity_strip = ColorRect.new()
	_rarity_strip.custom_minimum_size = Vector2(0, 2)
	_rarity_strip.color = GameTheme.rarity_color(card_data.get("rarity", "common"))
	_rarity_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_rarity_strip)

	if is_spell():
		_type_label = Label.new()
		_type_label.text = "SPELL"
		if GameTheme.font_display:
			_type_label.add_theme_font_override("font", GameTheme.font_display)
		_type_label.add_theme_font_size_override("font_size", 9)
		_type_label.add_theme_color_override("font_color", GameTheme.SPELL_PURPLE)
		_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_type_label.custom_minimum_size = Vector2(0, 10)
		_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(_type_label)

	_desc_label = Label.new()
	_desc_label.text = card_data.get("desc", "")
	if GameTheme.font_body:
		_desc_label.add_theme_font_override("font", GameTheme.font_body)
	_desc_label.add_theme_font_size_override("font_size", 9)
	_desc_label.add_theme_color_override("font_color", GameTheme.DESC_DIM)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.clip_text = true
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_desc_label)

	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 9)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.custom_minimum_size = Vector2(0, 10)
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floop_indicator.visible = false
	content.add_child(_floop_indicator)

	if is_creature():
		var footer := HBoxContainer.new()
		footer.custom_minimum_size = Vector2(0, 20)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(footer)

		_atk_badge = GameTheme.make_icon_stat(
			GameTheme.tex_icon_sword, str(current_atk),
			GameTheme.ATK_RED, 15)
		footer.add_child(_atk_badge)
		_atk_label = _atk_badge.get_child(1) as Label

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(spacer)

		_hp_badge = GameTheme.make_icon_stat(
			GameTheme.tex_icon_heart, str(current_hp),
			GameTheme.HEALTH_GREEN, 15)
		footer.add_child(_hp_badge)
		_hp_label = _hp_badge.get_child(1) as Label
	else:
		var spell_foot := Label.new()
		spell_foot.text = "— SPELL —"
		if GameTheme.font_display:
			spell_foot.add_theme_font_override("font", GameTheme.font_display)
		spell_foot.add_theme_font_size_override("font_size", 9)
		spell_foot.add_theme_color_override("font_color", GameTheme.SPELL_PURPLE)
		spell_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spell_foot.custom_minimum_size = Vector2(0, 14)
		spell_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(spell_foot)


# ═══════════════════════════════════════════
#  V3 LAYOUT — aligned to the new procedural frame texture.
#  Frame painted zones (normalized): banner y 0.07-0.21, art y 0.22-0.62,
#  type-strip y 0.62-0.69, description well y 0.70-0.92,
#  cost orb top-left, atk/hp chips at bottom corners.
# ═══════════════════════════════════════════

func _build_full_layout_v3() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Layer 1: Art clipped to the frame's painted art window zone ──
	# Pixel-measured from the 300x400 frame texture (alpha=0 region):
	# x 28-272 (0.093-0.907), y 95-241 (0.237-0.603).
	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_clip := Control.new()
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.anchor_left = 0.093
		art_clip.anchor_right = 0.907
		art_clip.anchor_top = 0.237
		art_clip.anchor_bottom = 0.603
		root.add_child(art_clip)
		_art_rect = art_clip

		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)
	else:
		_art_rect = _build_placeholder_art(root, 0.093, 0.907, 0.237, 0.603)

	# ── Layer 2: Frame overlay — per-card variant (rarity + type) ──
	var v3_frame: Texture2D = GameTheme.get_card_frame(card_data)
	if v3_frame:
		_frame_tex = TextureRect.new()
		_frame_tex.texture = v3_frame
		_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Frame variant already encodes spell/creature shape and rarity color;
		# only tint opponent cards red so they still feel hostile in combat.
		if is_opponent:
			_frame_tex.self_modulate = Color(1.0, 0.82, 0.78)
		root.add_child(_frame_tex)

	# Every text label below is placed via _center_at_point() using the POINT_*
	# and SIZE_* constants at the top of this file. To move a label, edit its
	# POINT_* coords — there are no other position numbers anywhere else.

	# ── Layer 3: Cost label inside the painted cost orb (top-left) ──
	# Uses font_stat (Cinzel Black 800) — heavy numerals match AAA card-game
	# stat orb conventions (Hearthstone/MtG style).
	_cost_label = _make_styled_label(str(card_data.cost), GameTheme.font_stat,
		14, Color(1, 0.97, 0.88))
	_center_at_point(_cost_label, POINT_COST, SIZE_COST)
	root.add_child(_cost_label)

	# ── Layer 4: Name label inside the painted banner ──
	_name_label = _make_styled_label(card_data.name, GameTheme.font_display,
		10, Color(0.98, 0.94, 0.86))
	_name_label.clip_text = true
	_center_at_point(_name_label, POINT_NAME, SIZE_NAME)
	root.add_child(_name_label)

	# ── Layer 5: Keyword medallion strip ──
	# Frame shape already encodes creature vs. spell (rectangular vs. arched art
	# window), so the type strip is repurposed for keyword icons. The text label
	# is kept as a hidden stub so external code referring to _type_label doesn't
	# null-deref. Icons are from game-icons.net (CC-BY 3.0, credited).
	_type_label = Label.new()
	_type_label.visible = false
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_type_label)

	# Strip rendered with extra height so icons read at ~18px instead of the
	# strip's painted ~13px. Icons spill slightly above/below the painted
	# scroll but the surrounding parchment absorbs the overflow.
	var kw_strip := HBoxContainer.new()
	kw_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kw_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	kw_strip.add_theme_constant_override("separation", 3)
	_center_at_point(kw_strip, POINT_TYPE, Vector2(190, 42))
	root.add_child(kw_strip)

	var icon_px := 18
	var keywords: Array = card_data.get("keywords", [])
	var shown := 0
	for k in keywords:
		if shown >= 5:
			break
		var k_str := String(k)
		var icon_tex: Texture2D = GameTheme.get_keyword_icon(k_str)
		if icon_tex == null:
			continue
		# Each medallion = PanelContainer with cream-rounded background + dark icon
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.96, 0.88, 0.65, 0.90)
		bsb.set_corner_radius_all(icon_px)
		bsb.border_color = Color(0.50, 0.34, 0.14, 0.90)
		bsb.set_border_width_all(1)
		bsb.content_margin_left = 1
		bsb.content_margin_right = 1
		bsb.content_margin_top = 1
		bsb.content_margin_bottom = 1
		var medallion := PanelContainer.new()
		medallion.add_theme_stylebox_override("panel", bsb)
		medallion.mouse_filter = Control.MOUSE_FILTER_STOP
		medallion.tooltip_text = KeywordEffects.tooltip_for(k_str)
		kw_strip.add_child(medallion)

		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(icon_px, icon_px)
		ic.modulate = Color(0.10, 0.05, 0.02, 1.0)  # near-black — max contrast
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		medallion.add_child(ic)
		shown += 1

	# ── Layer 6: Description — RichTextLabel with BBCode keyword highlight ──
	# Hidden stub Label kept for _desc_label external references; actual
	# rendering uses RichTextLabel so keyword display names are bolded in gold.
	_desc_label = Label.new()
	_desc_label.visible = false
	_desc_label.text = card_data.get("desc", "")
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_desc_label)

	var desc_rt := RichTextLabel.new()
	desc_rt.bbcode_enabled = true
	desc_rt.fit_content = false
	desc_rt.scroll_active = false
	desc_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_body:
		desc_rt.add_theme_font_override("normal_font", GameTheme.font_body)
		desc_rt.add_theme_font_override("bold_font", GameTheme.font_body)
	desc_rt.add_theme_font_size_override("normal_font_size", 8)
	desc_rt.add_theme_font_size_override("bold_font_size", 8)
	desc_rt.add_theme_color_override("default_color", Color(0.14, 0.08, 0.03))
	# Center-align the description visually (RichTextLabel respects [center]).
	var raw_desc: String = card_data.get("desc", "")
	var colorized: String = KeywordEffects.colorize_keywords(raw_desc)
	desc_rt.text = "[center]%s[/center]" % colorized
	_center_at_point(desc_rt, POINT_DESC, SIZE_DESC)
	root.add_child(desc_rt)

	# ── Layer 7: Atk / Hp labels inside the painted stat spheres ──
	if is_creature():
		_atk_label = _make_styled_label(str(current_atk), GameTheme.font_stat,
			14, Color(1, 0.96, 0.88))
		_center_at_point(_atk_label, POINT_ATK, SIZE_STAT)
		root.add_child(_atk_label)

		_hp_label = _make_styled_label(str(current_hp), GameTheme.font_stat,
			14, Color(0.92, 0.96, 1))
		_center_at_point(_hp_label, POINT_HP, SIZE_STAT)
		root.add_child(_hp_label)

	# ── Floop indicator — between the orbs, shown when player toggles will_floop
	_floop_indicator = _make_styled_label("FLOOP", GameTheme.font_display,
		8, GameTheme.FLOOP_BLUE)
	_center_at_point(_floop_indicator, POINT_FLOOP, SIZE_FLOOP)
	_floop_indicator.visible = false
	root.add_child(_floop_indicator)

	# ── Spell targeting tag — fills empty bottom space on spell cards ──
	if is_spell():
		var tgt_text: String = _spell_target_label()
		if tgt_text != "":
			var tgt_lbl: Label = _make_styled_label(
				tgt_text, GameTheme.font_display, 9, Color(0.18, 0.10, 0.04))
			tgt_lbl.add_theme_color_override("font_outline_color",
				Color(1, 0.93, 0.78, 0.50))
			tgt_lbl.add_theme_constant_override("outline_size", 1)
			_center_at_point(tgt_lbl, POINT_FLOOP, SIZE_FLOOP)
			root.add_child(tgt_lbl)

	# Rarity strip — kept as a hidden placeholder so external code that reads
	# this reference (color updates, etc.) doesn't null-deref.
	_rarity_strip = ColorRect.new()
	_rarity_strip.custom_minimum_size = Vector2(0, 1)
	_rarity_strip.color = GameTheme.rarity_color(card_data.get("rarity", "common"))
	_rarity_strip.visible = false
	_rarity_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_rarity_strip)


# ═══════════════════════════════════════════
#  V4 LAYOUT — procedural frame, no PNG dependency.
#  Per docs/prompts/card_design_doc.md §5/§15:
#    • 180×252 card (aspect 0.714, matches Hearthstone/MtG conventions)
#    • Cost = blue hex / ATK = yellow shield / HP = red drop (Hearthstone-canonical)
#    • Rarity gem at art-bottom; gold trim only on `rare`
#    • Art window 48% of card height (Hearthstone band)
#    • Description on light-tan parchment well at 10pt (≥WCAG AAA contrast)
#    • Spell cards: pentagonal peak above banner + SPELL tag at bottom
# ═══════════════════════════════════════════

func _build_full_layout_v4() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var rarity: String = String(card_data.get("rarity", "common"))
	var trim_color: Color = GameTheme.rarity_frame_trim(rarity)
	var is_curse: bool = (String(card_data.get("id", "")) == "curse"
		or String(card_data.get("type", "")) == "curse")
	if is_curse:
		trim_color = Color(0.55, 0.25, 0.55, 1.0)

	# ── Layer 1: Outer frame (walnut body + rarity-tinted border) ────────
	# Carries the base hue + drop shadow only. The depth-overlay cluster
	# (Layer 2) is what turns this flat fill into something that reads as
	# real lit parchment.
	var outer := Panel.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color(0.219, 0.157, 0.110, 1.0)
	if is_spell():
		# Purple-walnut wash so spells read colder than creatures, same
		# luminance so they don't look "underexposed" side by side.
		outer_style.bg_color = Color(0.180, 0.145, 0.227, 1.0)
	outer_style.border_color = trim_color
	# Frame thickness ladders by rarity so the card silhouette itself
	# encodes rarity at thumbnail size (Marvel Snap convention): rare = 4 px
	# gold ring, uncommon = 3 px blue ring, common/starter = 2 px gilt.
	# Combined with the rarity-tinted name plate this is two redundant
	# colour cues — enough to read rarity from across the table.
	var outer_border_w := 2
	if rarity == "rare":
		outer_border_w = 5  # bumped from 4 — rares get a chunkier ring
	elif rarity == "uncommon":
		outer_border_w = 3
	outer_style.set_border_width_all(outer_border_w)
	# Bumped 10 → 14 — softer card silhouette. A 10 px radius on a
	# 180×252 rect still reads as "rounded rectangle" / Slack-message
	# shape at thumbnail size; 14 starts to read as "card object". Going
	# further (18+) crosses into "pill" territory which loses the card
	# feel. 14 is the sweet spot for this aspect ratio.
	outer_style.set_corner_radius_all(14)
	# Default drop shadow for common / uncommon / starter — sits the card
	# above the board. Rare gets a coloured outer halo instead, applied
	# via a sibling Panel below so we keep both effects.
	# StyleBoxFlat blurs its shadow on the GPU every frame even when the
	# content is static — with ~5 shadowed panels per card and 100+ cards
	# in the gallery / deck viewer that's ~500-600 blur ops per frame,
	# which alone tanks the GL Compatibility renderer to single-digit FPS.
	# In static_display contexts we skip all shadow blurs (silhouette
	# still reads fine because the rarity-tinted border carries it).
	outer_style.shadow_color = Color(0, 0, 0, 0.80)
	outer_style.shadow_size = 0 if static_display else 8
	outer_style.shadow_offset = Vector2(0, 3)
	outer.add_theme_stylebox_override("panel", outer_style)

	# ── Rare-only outer halo ───────────────────────────────────────────
	# Rare cards radiate a soft gold bloom past their silhouette — the
	# canonical "legendary glow" used in Hearthstone, MtG Arena foils,
	# and Marvel Snap variant cards. Achieved with a sibling Panel sized
	# slightly larger than `outer`, with a transparent body and a thick
	# gold drop-shadow centred at offset (0, 0). The shadow renders
	# around the (invisible) rect → glow that wraps the whole card.
	#
	# Skipped in static_display contexts — the 18 px shadow blur per
	# rare card adds another ~12 GPU blurs / frame to the gallery on
	# top of the 5 per card we already cut. Gallery players see rare
	# cards on hover (z_index pop) where pulse+halo can be re-enabled.
	if rarity == "rare" and not static_display:
		var rare_halo := Panel.new()
		rare_halo.anchor_left = 0.0; rare_halo.anchor_right = 1.0
		rare_halo.anchor_top = 0.0; rare_halo.anchor_bottom = 1.0
		rare_halo.offset_left = -3; rare_halo.offset_right = 3
		rare_halo.offset_top = -3; rare_halo.offset_bottom = 3
		rare_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var halo_style := StyleBoxFlat.new()
		halo_style.bg_color = Color(0, 0, 0, 0)  # invisible body
		halo_style.set_corner_radius_all(17)  # matches outer 14 + 3 inset
		halo_style.shadow_color = Color(1.0, 0.85, 0.26, 0.55)
		halo_style.shadow_size = 18
		halo_style.shadow_offset = Vector2(0, 0)
		rare_halo.add_theme_stylebox_override("panel", halo_style)
		root.add_child(rare_halo)
	root.add_child(outer)

	# ── Rare-only inner hairline ───────────────────────────────────────
	# A 1 px black ring tucked just inside the gold outer border — the
	# dark hairline between gold and the warm walnut body cranks the
	# gold's apparent contrast (the AA-pixels on the gold's inner edge
	# get a darker neighbour, so the gold reads more saturated than it
	# is). Standard trick in jewelry rendering and AAA card frames.
	if rarity == "rare":
		var hairline := Panel.new()
		hairline.anchor_left = 0.0; hairline.anchor_right = 1.0
		hairline.anchor_top = 0.0; hairline.anchor_bottom = 1.0
		hairline.offset_left = float(outer_border_w)
		hairline.offset_right = -float(outer_border_w)
		hairline.offset_top = float(outer_border_w)
		hairline.offset_bottom = -float(outer_border_w)
		hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hairline_style := StyleBoxFlat.new()
		hairline_style.bg_color = Color(0, 0, 0, 0)
		hairline_style.border_color = Color(0.05, 0.04, 0.02, 0.90)
		hairline_style.set_border_width_all(1)
		hairline_style.set_corner_radius_all(9)  # tracks outer 14 - border_w
		hairline.add_theme_stylebox_override("panel", hairline_style)
		root.add_child(hairline)

	# ── Layer 2: Surface depth overlays ─────────────────────────────────
	# Four stacked textures stop the body reading as a flat fill:
	#   grain (paper fiber) → top_light (directional sheen) →
	#   bottom_shade (gravity shadow) → vignette (corner darkening).
	# Each modulated to a low alpha; together they sell the surface as
	# parchment under directional light. Inset 3 px from the card edge so
	# the rectangular overlays never poke past the rounded corners (the
	# StyleBox's corner_radius=10 clips its bg to rounded but children
	# would render to the axis-aligned rect without this inset).
	var depth_layer := Control.new()
	depth_layer.anchor_left = 0.0; depth_layer.anchor_right = 1.0
	depth_layer.anchor_top = 0.0; depth_layer.anchor_bottom = 1.0
	depth_layer.offset_left = 3; depth_layer.offset_right = -3
	depth_layer.offset_top = 3; depth_layer.offset_bottom = -3
	depth_layer.clip_contents = true
	depth_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(depth_layer)
	if GameTheme.tex_card_grain:
		var grain := TextureRect.new()
		grain.texture = GameTheme.tex_card_grain
		grain.stretch_mode = TextureRect.STRETCH_TILE
		grain.set_anchors_preset(Control.PRESET_FULL_RECT)
		grain.modulate = Color(1, 1, 1, 0.16)
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(grain)
	# Anisotropic wood-grain layer on top of the fine grain. The 256×32
	# texture tiles ~8× vertically across the card, producing horizontal
	# striations that read as wood grain rather than digital noise. Low
	# alpha so the fine grain underneath still contributes its fiber.
	# Skipped in static_display — see header comment at top of layer 2.
	if GameTheme.tex_card_wood_grain and not static_display:
		var wood := TextureRect.new()
		wood.texture = GameTheme.tex_card_wood_grain
		wood.stretch_mode = TextureRect.STRETCH_TILE
		wood.set_anchors_preset(Control.PRESET_FULL_RECT)
		wood.modulate = Color(1, 1, 1, 0.12)
		wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(wood)
	# Top-light + bottom-shade + vignette + rarity wash all skipped in
	# static_display contexts. Each is a per-frame TextureRect draw — 4
	# of them per card × 100+ cards = ~500 fewer CanvasItem submissions
	# per frame in the gallery / deck viewer. The card body still reads
	# as wooden via the StyleBox base colour + the fine grain above.
	if not static_display and GameTheme.tex_card_top_light:
		var top_light := TextureRect.new()
		top_light.texture = GameTheme.tex_card_top_light
		top_light.set_anchors_preset(Control.PRESET_FULL_RECT)
		top_light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		top_light.stretch_mode = TextureRect.STRETCH_SCALE
		top_light.modulate = Color(1, 1, 1, 0.10)
		top_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(top_light)
	if not static_display and GameTheme.tex_card_bottom_shade:
		var bot_shade := TextureRect.new()
		bot_shade.texture = GameTheme.tex_card_bottom_shade
		bot_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		bot_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bot_shade.stretch_mode = TextureRect.STRETCH_SCALE
		bot_shade.modulate = Color(1, 1, 1, 0.22)
		bot_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(bot_shade)
	if not static_display and GameTheme.tex_card_vignette:
		var vig := TextureRect.new()
		vig.texture = GameTheme.tex_card_vignette
		vig.set_anchors_preset(Control.PRESET_FULL_RECT)
		vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vig.stretch_mode = TextureRect.STRETCH_SCALE
		vig.modulate = Color(1, 1, 1, 0.30)
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(vig)
	# Faint full-card colour wash — uncommons cool, rares warm, commons none.
	# Alpha ≤ 0.07 so the wood/parchment stays the dominant surface.
	var card_tint: Color = GameTheme.rarity_card_tint(rarity)
	if not static_display and card_tint.a > 0.0:
		var tint := ColorRect.new()
		tint.color = card_tint
		tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(tint)

	# ── Layer 3: Inner trim line (rarity-tinted accent) ─────────────────
	# Skipped in static_display — one fewer Panel + StyleBoxFlat border
	# draw per card. The outer gold border already carries the rarity
	# colour cue, so the inner accent is decorative-only.
	if not static_display:
		var trim := Panel.new()
		trim.anchor_left = 0.02; trim.anchor_right = 0.98
		trim.anchor_top = 0.02;  trim.anchor_bottom = 0.98
		trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var trim_style := StyleBoxFlat.new()
		trim_style.bg_color = Color(0, 0, 0, 0)
		var trim_alpha: float = 0.85 if rarity == "rare" else 0.50
		trim_style.border_color = Color(trim_color.r, trim_color.g,
			trim_color.b, trim_alpha)
		trim_style.set_border_width_all(2 if rarity == "rare" else 1)
		trim_style.set_corner_radius_all(11)
		trim.add_theme_stylebox_override("panel", trim_style)
		root.add_child(trim)

	# ── Layer 4: Art window ──────────────────────────────────────────────
	# 13.5–64% Y → ~50.5% of card height. The old layout reserved 59–65%
	# for a frame band that hosted the diamond rarity gem; that band is
	# gone (rarity moved to the name plate) so the art gets ~4.5% more
	# vertical real estate without crowding the description well.
	var art_frame := Panel.new()
	art_frame.anchor_left = 0.05; art_frame.anchor_right = 0.95
	art_frame.anchor_top = 0.135; art_frame.anchor_bottom = 0.64
	art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_frame_style := StyleBoxFlat.new()
	art_frame_style.bg_color = Color(0.04, 0.03, 0.025, 1.0)
	art_frame_style.border_color = Color(0, 0, 0, 0.85)
	art_frame_style.set_border_width_all(1)
	art_frame_style.set_corner_radius_all(3)
	# Drop shadow + dark border together make the window read as recessed
	# into the card body, not pasted on top of it.
	art_frame_style.shadow_color = Color(0, 0, 0, 0.55)
	art_frame_style.shadow_size = 0 if static_display else 2
	art_frame_style.shadow_offset = Vector2(0, 1)
	art_frame.add_theme_stylebox_override("panel", art_frame_style)
	root.add_child(art_frame)

	var art_clip := Control.new()
	art_clip.clip_contents = true
	art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_clip.anchor_left = 0.0; art_clip.anchor_right = 1.0
	art_clip.anchor_top = 0.0;  art_clip.anchor_bottom = 1.0
	art_clip.offset_left = 2; art_clip.offset_right = -2
	art_clip.offset_top = 2; art_clip.offset_bottom = -2
	art_frame.add_child(art_clip)
	_art_rect = art_clip

	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Subtle warm color grade — multiply by (0.94, 0.90, 0.83) pulls
		# every illustration toward the card's walnut palette. Light/cool
		# art (Sprite, Ratling, Naga with grey backgrounds) reads as
		# "painted in the same world" as dark/warm art (Goblin, Bloodhound)
		# instead of as photo cutouts pasted on a wooden card. STS and
		# Hearthstone both apply this kind of palette unification in
		# post-processing — without it, mixed art sources fight each other.
		art_tex.modulate = Color(0.94, 0.90, 0.83, 1.0)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)
	else:
		_build_placeholder_art(art_clip, 0.0, 1.0, 0.0, 1.0)

	# Inner shadow gradients inside the art window — top + bottom darkening
	# so the window reads as glass under recessed paper, not a flat photo.
	if not static_display:
		_add_art_inner_shadow(art_clip)

	# Transitional treatment between art and frame — radial vignette +
	# warm sepia wash + crisp inner frame line. Bridges the gap so that
	# art with light/grey natural backgrounds (the Sprite/Ratling cases
	# from the gallery screenshot) stops reading as a bright photo
	# floating in a dark wood frame. Together with the art_tex modulate
	# above this gives every card the same "matted illustration" feel
	# regardless of which source the art came from.
	if not static_display:
		_add_art_unify_treatment(art_clip)

	# ── Layer 5: Name banner (rarity-tinted plate) ───────────────────────
	# Rarity is signaled HERE — bg tint + border colour — instead of bolting
	# a separate gem onto the frame. STS / Marvel Snap convention.
	var banner := Panel.new()
	banner.anchor_left = 0.05; banner.anchor_right = 0.95
	banner.anchor_top = 0.030; banner.anchor_bottom = 0.135
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = GameTheme.rarity_plate_bg(rarity)
	bs.border_color = GameTheme.rarity_plate_border(rarity)
	# Banner border thickness ladders alongside the outer frame: rare = 3 px
	# gold, uncommon = 2 px blue, common/starter = 1 px gilt. Reads as
	# "more elaborate name plate = more important card".
	var banner_border_w := 1
	if rarity == "rare":
		banner_border_w = 3
	elif rarity == "uncommon":
		banner_border_w = 2
	bs.set_border_width_all(banner_border_w)
	bs.corner_radius_top_left = 6
	bs.corner_radius_top_right = 6
	bs.corner_radius_bottom_left = 8
	bs.corner_radius_bottom_right = 8
	bs.shadow_color = Color(0, 0, 0, 0.55)
	bs.shadow_size = 0 if static_display else 4
	bs.shadow_offset = Vector2(0, 2)
	banner.add_theme_stylebox_override("panel", bs)
	root.add_child(banner)
	if not static_display:
		_add_emboss_lines(banner)

	_name_label = Label.new()
	var name_text: String = card_data.get("name", "")
	_name_label.text = name_text
	if GameTheme.font_display:
		_name_label.add_theme_font_override("font", GameTheme.font_display)
	# Auto-shrink: Cinzel SemiBold caps render at ~7 px/char at 12 pt; the
	# banner's text region is ~130 px wide once the cost gem is inset. Long
	# names ("Overwhelming Force", "Collector's Champion") drop to 10–9 pt.
	var name_size := 12
	if name_text.length() >= 19:
		name_size = 9
	elif name_text.length() >= 15:
		name_size = 10
	_name_label.add_theme_font_size_override("font_size", name_size)
	# Engraved-into-the-plate treatment. Three layers stacked via Label's
	# theme overrides (back → front in render order):
	#   1. Drop shadow at (0, 1) in pure black — the "deep interior" of
	#      each carved letter where the stroke recedes into the plate.
	#   2. Outline in warm walnut-dark — the "sides" of the engraving, a
	#      hue shift from the cream glyph instead of a flat black halo.
	#      Reads as wood-tone shadow on the engraved edges, not as a
	#      sticker outline.
	#   3. Bright cream glyph fill — the "lit top" of the carved letter
	#      catching light from above. Slightly brighter than the previous
	#      cream so the engraved effect reads as 3D.
	# Combined: cream-on-walnut-on-black gives a clear three-tone gradient
	# from top of each letter (bright) → side (walnut) → bottom (deep
	# shadow), exactly the cue our eye uses to see relief in real
	# engraved metal / wood. Beats the previous flat outline treatment
	# on every rarity background tested (cool blue plate, warm gold
	# plate, neutral walnut, brass).
	_name_label.add_theme_color_override("font_color",
		Color(0.985, 0.965, 0.890))
	_name_label.add_theme_color_override("font_outline_color",
		Color(0.18, 0.10, 0.05, 0.95))  # warm walnut shadow, not pure black
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.add_theme_color_override("font_shadow_color",
		Color(0, 0, 0, 0.85))
	_name_label.add_theme_constant_override("shadow_offset_x", 0)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.anchor_left = 0.18; _name_label.anchor_right = 0.98
	_name_label.anchor_top = 0.0;   _name_label.anchor_bottom = 1.0
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(_name_label)

	# ── Layer 6: Cost orb — glossy 3D blue sphere (SphereOrb) ──────────
	# Eight-layer draw stack (outer glow → drop shadow → directional
	# gradient → AO shadow → rim light → specular halo → specular core)
	# turns a flat circle into a polished mana gem. Pulse on so the
	# glow breathes — visually says "energy / mana" without text. Skip
	# the pulse in static-display contexts (Card Gallery, Deck Viewer)
	# where per-frame queue_redraw on 100+ cards causes visible lag.
	var cost_pulse: float = 0.0 if static_display else 0.18
	var cost_orb := _make_stat_orb(GameTheme.COST_BLUE_GEM, cost_pulse,
		static_display)
	cost_orb.anchor_left = 0.0; cost_orb.anchor_right = 0.0
	cost_orb.anchor_top = 0.0;  cost_orb.anchor_bottom = 0.0
	# 44 px sphere hanging ~9 px past the top-left corner. Sized to
	# ~24 % of card width (Hearthstone mana-gem proportion); was 56 px /
	# 31 % which dominated the name banner. Card2D extends PanelContainer
	# (clip_contents = false) so children render past the panel rect.
	cost_orb.offset_left = -9;  cost_orb.offset_right = 35
	cost_orb.offset_top = -9;   cost_orb.offset_bottom = 35
	_cost_badge = cost_orb
	root.add_child(cost_orb)

	# Cream numeral with a saturated cyan-blue halo — matches the cost
	# sphere's hue and reads as "the number is made of mana". Blanked in
	# bake_strip_stats so CardTextureCache snapshots the empty sphere; the
	# live overlay paints the number on top.
	_cost_label = _make_stat_number(
		"" if bake_strip_stats else str(card_data.get("cost", 0)),
		Color(1, 0.98, 0.90), 0,
		Color(0.30, 0.65, 1.00, 0.85))
	cost_orb.add_child(_cost_label)

	# Keywords are highlighted inline in the description (gold bold) per
	# Hearthstone/MtG convention — no separate icon strip. Hover panel
	# carries full keyword tooltips.

	# ── Layer 6.5: Ornamental divider between art and well ─────────────
	# Two short gilt rules flanking a small gold gem at the centre. Breaks
	# up the long rectangular silhouette of the card body (without
	# blocking the stat orbs at the corners). Same trick used by old MtG
	# and Renaissance illuminated manuscripts to mark section breaks on
	# otherwise-uniform parchment.
	if not static_display:
		_add_ornamental_divider(root, 0.650, GameTheme.FRAME_TRIM_COMMON)

	# ── Layer 7: Description well (parchment) ───────────────────────────
	# The ornamental divider above marks the boundary; the well's own
	# emboss + parchment colour distinguishes it from the dark frame body.
	var well := Panel.new()
	well.anchor_left = 0.05; well.anchor_right = 0.95
	well.anchor_top = 0.660; well.anchor_bottom = 0.865
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ws := StyleBoxFlat.new()
	ws.bg_color = GameTheme.PARCHMENT_LIGHT
	ws.border_color = Color(0.42, 0.28, 0.10, 0.90)
	ws.set_border_width_all(1)
	ws.set_corner_radius_all(5)
	ws.shadow_color = Color(0, 0, 0, 0.30)
	ws.shadow_size = 0 if static_display else 2
	ws.shadow_offset = Vector2(0, 1)
	well.add_theme_stylebox_override("panel", ws)
	root.add_child(well)
	# Lighter emboss on the parchment — its surface is bright, so the top
	# highlight pops harder and the bottom shadow can be softer.
	if not static_display:
		_add_emboss_lines(well, Color(1, 1, 1, 0.55), Color(0, 0, 0, 0.18))

	var desc_rt := RichTextLabel.new()
	desc_rt.bbcode_enabled = true
	desc_rt.fit_content = false
	desc_rt.scroll_active = false
	desc_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_rt.clip_contents = true
	desc_rt.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_rt.offset_left = 5
	desc_rt.offset_right = -5
	desc_rt.offset_top = 3
	desc_rt.offset_bottom = -3
	desc_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_body:
		desc_rt.add_theme_font_override("normal_font", GameTheme.font_body)
		# bold_font is a heavier-embolden variation so [b]keyword[/b] tags
		# emitted by KeywordEffects.colorize_keywords get a real weight bump,
		# not just a colour shift.
		desc_rt.add_theme_font_override("bold_font",
			GameTheme.font_body_bold if GameTheme.font_body_bold else GameTheme.font_body)
	var raw_desc: String = card_data.get("desc", "")
	# Auto-shrink: well is ~53 px tall × 152 px wide once padded.
	var desc_size := 11
	if raw_desc.length() > 110:
		desc_size = 8
	elif raw_desc.length() > 85:
		desc_size = 9
	elif raw_desc.length() > 60:
		desc_size = 10
	desc_rt.add_theme_font_size_override("normal_font_size", desc_size)
	desc_rt.add_theme_font_size_override("bold_font_size", desc_size)
	desc_rt.add_theme_color_override("default_color", GameTheme.PARCHMENT_TEXT)
	# Faint dark outline thickens rendered strokes — AA-pixels on the edge
	# of each glyph get a darker neighbour, keeping small body text crisp.
	desc_rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	desc_rt.add_theme_constant_override("outline_size", 2)
	# KeywordEffects emits a light gold (#c89e4a) — washed out on this
	# light tan well. Swap for a deep saturated crimson against near-black
	# body text — the strong hue shift is what makes keywords pop here.
	var colorized: String = KeywordEffects.colorize_keywords(raw_desc) \
		.replace("#c89e4a", "#9a1a1a")
	desc_rt.text = "[center]%s[/center]" % colorized
	well.add_child(desc_rt)

	# Stub hidden Label so external code reading _desc_label doesn't crash.
	_desc_label = Label.new()
	_desc_label.visible = false
	_desc_label.text = raw_desc
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_desc_label)

	# NO RARITY GEM — rarity reads from the name plate (Layer 5) plus the
	# outer trim colour (Layer 1). The old PolyBadge diamond fought with
	# the cost orb for the eye and squeezed into a 6 % band that no
	# longer exists.

	# ── Layer 8: ATK / HP plates (creatures) ─────────────────────────────
	if is_creature():
		# Glossy 3D gold sphere — same SphereOrb stack as the cost gem
		# but tinted gold. No pulse: ATK shouldn't draw the eye away
		# from the cost orb's "energy is changing" cue.
		var atk_plate := _make_stat_orb(GameTheme.ATK_GOLD_SHIELD, 0.0,
			static_display)
		atk_plate.anchor_left = 0.0; atk_plate.anchor_right = 0.0
		atk_plate.anchor_top = 1.0;  atk_plate.anchor_bottom = 1.0
		# 44 px sphere hanging ~9 px past the bottom-left (matches cost
		# orb proportions; was 56 px which crowded the card body).
		atk_plate.offset_left = -9;  atk_plate.offset_right = 35
		atk_plate.offset_top = -35;  atk_plate.offset_bottom = 9
		root.add_child(atk_plate)

		_atk_base_color = Color(0.10, 0.07, 0.02)  # near-black — reads dark on gold
		# Dark numeral with a warm amber halo — the gold sphere already
		# provides the warmth, the halo extends it past the orb silhouette
		# so the number "glows like an ember" instead of sitting flat.
		# Blanked under bake_strip_stats — see cost_label comment.
		_atk_label = _make_stat_number(
			"" if bake_strip_stats else str(current_atk),
			_atk_base_color, 0, Color(1.00, 0.78, 0.20, 0.90))
		atk_plate.add_child(_atk_label)
		_atk_badge = null  # v4 doesn't use the legacy HBox stat-badge ref

		# Glossy 3D red sphere — same recipe, red tint, slow pulse
		# (heartbeat-feel for HP). Slower than cost's mana pulse so the
		# two animations read as distinct beats rather than competing.
		# Static-display contexts get no pulse — see cost_pulse comment.
		var hp_pulse: float = 0.0 if static_display else 0.10
		var hp_plate := _make_stat_orb(GameTheme.HEALTH_RED_DROP, hp_pulse,
			static_display)
		hp_plate.anchor_left = 1.0; hp_plate.anchor_right = 1.0
		hp_plate.anchor_top = 1.0;  hp_plate.anchor_bottom = 1.0
		# 44 px sphere hanging ~9 px past the bottom-right.
		hp_plate.offset_left = -35; hp_plate.offset_right = 9
		hp_plate.offset_top = -35;  hp_plate.offset_bottom = 9
		root.add_child(hp_plate)

		_hp_base_color = Color(1, 0.97, 0.92)  # near-white on the red sphere
		# Near-white numeral with a deep crimson halo — reads as the
		# number "bleeding" outward from the orb, matching the HP idiom.
		# Blanked under bake_strip_stats — see cost_label comment.
		_hp_label = _make_stat_number(
			"" if bake_strip_stats else str(current_hp),
			_hp_base_color, 0, Color(1.00, 0.30, 0.20, 0.90))
		hp_plate.add_child(_hp_label)
		_hp_badge = null  # v4 doesn't use the legacy HBox stat-badge ref
	else:
		# Spell card has no ATK/HP plates — the bottom strip carries a single
		# combined "SPELL · TARGET" label so the targeting hint and type tag
		# don't fight each other for vertical room.
		var tgt_raw: String = _spell_target_label()
		var spell_text := "✦ SPELL"
		if tgt_raw != "":
			# Strip the leading arrow/icon from _spell_target_label() so we
			# can compose a clean "SPELL  ·  TARGET" line.
			var trimmed := tgt_raw.replace("→ ", "").replace("✦ ", "")
			spell_text = "✦ SPELL  ·  %s" % trimmed
		var spell_tag := Label.new()
		spell_tag.text = spell_text
		if GameTheme.font_display:
			spell_tag.add_theme_font_override("font", GameTheme.font_display)
		# Same auto-shrink principle as the name label: the longest combined
		# label is "✦ SPELL · FRIENDLY CREATURE" — needs 9 pt to fit the
		# ~165-px bottom strip without clipping.
		var tag_size := 10
		if spell_text.length() > 18:
			tag_size = 9
		spell_tag.add_theme_font_size_override("font_size", tag_size)
		spell_tag.add_theme_color_override("font_color", GameTheme.SPELL_PURPLE)
		spell_tag.add_theme_color_override("font_outline_color",
			Color(0, 0, 0, 0.95))
		spell_tag.add_theme_constant_override("outline_size", 3)
		spell_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spell_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		spell_tag.clip_text = true
		spell_tag.anchor_left = 0.04; spell_tag.anchor_right = 0.96
		# Bumped from 0.86 → 0.875 because the well's bottom edge moved from
		# 0.86 → 0.865 in this layout; old value would have overlapped.
		spell_tag.anchor_top = 0.875; spell_tag.anchor_bottom = 1.0
		spell_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(spell_tag)

	# ── Layer 10: FLOOP indicator (between stat plates, toggled visible) ─
	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 10)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.add_theme_color_override("font_outline_color",
		Color(0, 0, 0, 0.95))
	_floop_indicator.add_theme_constant_override("outline_size", 3)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_floop_indicator.anchor_left = 0.24; _floop_indicator.anchor_right = 0.76
	_floop_indicator.anchor_top = 0.925; _floop_indicator.anchor_bottom = 1.0
	_floop_indicator.visible = false
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floop_indicator)

	# Stub legacy refs — external code reading _type_label / _rarity_strip
	# must not null-deref.
	_type_label = Label.new()
	_type_label.visible = false
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_type_label)
	_rarity_strip = ColorRect.new()
	_rarity_strip.visible = false
	_rarity_strip.color = GameTheme.rarity_color(rarity)
	_rarity_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_rarity_strip)


# ── Layout helpers ──

func _add_emboss_lines(panel: Control,
		top_color: Color = Color(1, 1, 1, 0.18),
		bot_color: Color = Color(0, 0, 0, 0.32)) -> void:
	# Adds a 1 px highlight line at the panel's top inside edge and a 1 px
	# shadow line at the bottom inside edge — the "chisel" trick every
	# painted-frame UI uses to fake bevel depth without a real 3D pass.
	# Anchored panel-relative, so the lines follow the panel's actual rect
	# (not the card root) and survive layout reflows.
	var top_hl := ColorRect.new()
	top_hl.color = top_color
	top_hl.anchor_left = 0.0; top_hl.anchor_right = 1.0
	top_hl.anchor_top = 0.0; top_hl.anchor_bottom = 0.0
	top_hl.offset_left = 2; top_hl.offset_right = -2
	top_hl.offset_top = 1; top_hl.offset_bottom = 2
	top_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(top_hl)

	var bot_sh := ColorRect.new()
	bot_sh.color = bot_color
	bot_sh.anchor_left = 0.0; bot_sh.anchor_right = 1.0
	bot_sh.anchor_top = 1.0; bot_sh.anchor_bottom = 1.0
	bot_sh.offset_left = 2; bot_sh.offset_right = -2
	bot_sh.offset_top = -2; bot_sh.offset_bottom = -1
	bot_sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bot_sh)


func _add_art_inner_shadow(container: Control) -> void:
	# Top + bottom dark-gradient strips inside the art window — makes it
	# read as recessed (light hitting a deeper plane) instead of pasted on
	# top of the frame. Reuses the GameTheme bottom_shade gradient texture
	# (transparent→black); the top strip flips it so the dark end is at
	# top. Falls back to a single dark line if the gradient texture isn't
	# loaded (e.g. GameTheme failed to init).
	if GameTheme.tex_card_bottom_shade == null:
		var fallback := ColorRect.new()
		fallback.color = Color(0, 0, 0, 0.40)
		fallback.anchor_left = 0.0; fallback.anchor_right = 1.0
		fallback.anchor_top = 0.0; fallback.anchor_bottom = 0.0
		fallback.offset_bottom = 3
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(fallback)
		return

	var top_shadow := TextureRect.new()
	top_shadow.texture = GameTheme.tex_card_bottom_shade
	top_shadow.flip_v = true  # dark end at top
	top_shadow.anchor_left = 0.0; top_shadow.anchor_right = 1.0
	top_shadow.anchor_top = 0.0; top_shadow.anchor_bottom = 0.0
	top_shadow.offset_bottom = 14
	top_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	top_shadow.modulate = Color(1, 1, 1, 0.55)
	top_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(top_shadow)

	var bot_shadow := TextureRect.new()
	bot_shadow.texture = GameTheme.tex_card_bottom_shade
	bot_shadow.anchor_left = 0.0; bot_shadow.anchor_right = 1.0
	bot_shadow.anchor_top = 1.0; bot_shadow.anchor_bottom = 1.0
	bot_shadow.offset_top = -14
	bot_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bot_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	bot_shadow.modulate = Color(1, 1, 1, 0.55)
	bot_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bot_shadow)


func _add_ornamental_divider(parent: Control, anchor_y: float,
		color: Color) -> void:
	# Renders a centered ornamental divider at the given vertical anchor:
	# two short gilt rules flanking a small rotated-square gem. Together
	# they read as a single decorative break across the card.
	#
	# Pure Control nodes — no custom _draw, no shaders. Uses Panel's
	# StyleBoxFlat for the gem (with corner_radius=0 + rotation_degrees=45
	# to turn a tiny square into a diamond) and ColorRect for the two rules.

	# Left gilt rule
	var left_rule := ColorRect.new()
	left_rule.anchor_left = 0.18; left_rule.anchor_right = 0.43
	left_rule.anchor_top = anchor_y; left_rule.anchor_bottom = anchor_y
	left_rule.offset_top = -1; left_rule.offset_bottom = 1
	left_rule.color = Color(color.r, color.g, color.b, 0.85)
	left_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(left_rule)

	# Right gilt rule (mirror)
	var right_rule := ColorRect.new()
	right_rule.anchor_left = 0.57; right_rule.anchor_right = 0.82
	right_rule.anchor_top = anchor_y; right_rule.anchor_bottom = anchor_y
	right_rule.offset_top = -1; right_rule.offset_bottom = 1
	right_rule.color = Color(color.r, color.g, color.b, 0.85)
	right_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(right_rule)

	# Centre gem — 9 px square Panel rotated 45° into a diamond. Pivot at
	# its own centre so the rotation stays anchored to the divider line.
	var gem := Panel.new()
	gem.anchor_left = 0.5; gem.anchor_right = 0.5
	gem.anchor_top = anchor_y; gem.anchor_bottom = anchor_y
	gem.offset_left = -4; gem.offset_right = 5  # 9 px wide
	gem.offset_top = -4; gem.offset_bottom = 5  # 9 px tall
	gem.pivot_offset = Vector2(4.5, 4.5)
	gem.rotation = deg_to_rad(45)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.961, 0.784, 0.259, 1.0)  # vivid gold
	gs.border_color = Color(0.20, 0.12, 0.03, 0.95)
	gs.set_border_width_all(1)
	gs.set_corner_radius_all(0)  # crisp diamond, not rounded
	gem.add_theme_stylebox_override("panel", gs)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gem)


func _add_art_unify_treatment(container: Control) -> void:
	# Three overlay layers stacked on top of whatever sits in the art clip
	# (TextureRect for real art, _build_placeholder_art for missing-art
	# cards). Together they bridge the gap between disparate art sources
	# and the walnut frame — STS-style "matted illustration" feel.
	#
	# Layering (back → front, applied AFTER _add_art_inner_shadow):
	#   1. Radial vignette — corners darker than centre. Reuses the same
	#      vignette texture the card body uses, so the visual language
	#      is consistent. This is the layer doing most of the work:
	#      light-background art (Sprite, Ratling, etc.) loses its bright
	#      corners and stops reading as a photo on a card.
	#   2. Warm sepia wash — very low alpha (~7%) walnut multiply over
	#      the whole art. Pulls cool/grey art toward the card's palette
	#      without destroying the natural colour of well-painted dark
	#      art. Combined with the modulate on art_tex this is a
	#      two-stage palette unification.
	#   3. Inner frame line — 1 px dark border just inside the art clip
	#      edge. Crisps the boundary so the art reads as matted into
	#      the frame, not bleeding under it. Same trick gallery framers
	#      use to make wildly-different paintings hang as a coherent set.

	# 1. Radial vignette overlay
	if GameTheme.tex_card_vignette:
		var vig := TextureRect.new()
		vig.texture = GameTheme.tex_card_vignette
		vig.set_anchors_preset(Control.PRESET_FULL_RECT)
		vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vig.stretch_mode = TextureRect.STRETCH_SCALE
		# 0.55 alpha — strong enough to dim a white background to dark
		# walnut at the corners, weak enough that the centre of the art
		# stays clear and readable.
		vig.modulate = Color(1, 1, 1, 0.55)
		vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(vig)

	# 2. Warm sepia wash — translucent walnut over the whole art
	var tint := ColorRect.new()
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Warm wood tone at 7% alpha. Was tempted to go to 10-12% but that
	# starts visibly muddying the good dark art (Bloodhound, Goblin) and
	# we'd lose the contrast we already have. 7% is the sweet spot —
	# enough to nudge cool/grey art warm, invisible on warm/dark art.
	tint.color = Color(0.50, 0.36, 0.22, 0.07)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(tint)

	# 3. Inner frame line — thin dark hairline just inside the art clip
	var frame_line := Panel.new()
	frame_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fls := StyleBoxFlat.new()
	fls.bg_color = Color(0, 0, 0, 0)
	# Warm-dark walnut at 80% — same hue as the card body so the line
	# reads as a tiny inset matte rather than a flat black stripe.
	fls.border_color = Color(0.08, 0.05, 0.03, 0.80)
	fls.set_border_width_all(1)
	fls.set_corner_radius_all(2)
	frame_line.add_theme_stylebox_override("panel", fls)
	container.add_child(frame_line)


# ── Stat-orb factory (painted-icon flavour) ──
# These two helpers replace the GemOrb procedural draw calls for cost / ATK
# / HP. The painted PNGs carry the visual weight; the helpers just position
# the icon and overlay the numeral. Used 3× per creature card and 1× per
# spell card (cost only).

func _make_stat_orb(fill_color: Color, pulse: float = 0.0,
		simple: bool = false) -> Control:
	# Returns a SphereOrb — glossy 3D sphere drawn via stacked _draw
	# circles. The caller sets anchor + offsets to position it, and adds a
	# numeral label as a child.
	#
	# fill_color drives the sphere's base hue. pulse > 0 animates the
	# outer halo. simple = true switches to a 5-layer recipe instead of
	# the full 39-layer stack — used in static_display contexts (Card
	# Gallery, Deck Viewer) where 100+ orbs replaying 39 sub-draws each
	# every frame is the dominant lag source on the GL Compatibility
	# renderer.
	var orb := SphereOrb.new()
	orb.fill_color = fill_color
	orb.pulse_amount = pulse
	orb.simple_mode = simple
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return orb


func _make_stat_number(text: String, color: Color, vertical_offset: int = 0,
		glow_color: Color = Color(0, 0, 0, 0)) -> Label:
	# Numeral overlay for a stat orb. Cinzel Black on top of a coloured
	# halo: `font_shadow_color` at offset (0, 0) with a generous
	# `shadow_outline_size` renders as a soft colored bloom around each
	# glyph — the same trick CSS uses for "neon" text, free in Godot's
	# Label theme. This is what makes the numbers stop reading as plain.
	#
	# Layering (back → front):
	#   1. Shadow glow — expanded glyph silhouette, glow_color tint.
	#   2. Outline — sharp black border keeping the glyph legible against
	#      the sphere's directional gradient.
	#   3. Glyph fill — `color` (cream / dark).
	#
	# `vertical_offset` nudges the label vs geometric centre — unused for
	# symmetric spheres but kept for future asymmetric overlays.
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_stat:
		lbl.add_theme_font_override("font", GameTheme.font_stat)
	# 18 pt sized for the 44 px sphere.
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	# 4 px outline (scaled from 5 to match smaller glyph) pushes the AA
	# edge of every glyph into solid black, guaranteeing legibility on
	# top of the sphere's directional gradient.
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.98))
	lbl.add_theme_constant_override("outline_size", 4)
	# Colored halo via shadow_outline_size — only kicks in if the caller
	# passes a glow_color. Centred (offset 0,0) so it bleeds equally on
	# all sides; outline_size 7 = ~7 px soft halo past the black outline.
	# AAA card games (Hearthstone, MtG Arena) pair this with the orb
	# tint so the number reads as "made of mana / blood / gold".
	if glow_color.a > 0.001:
		lbl.add_theme_color_override("font_shadow_color", glow_color)
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", 0)
		lbl.add_theme_constant_override("shadow_outline_size", 7)
	else:
		# Fallback: traditional offset drop shadow, no glow.
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	if vertical_offset != 0:
		lbl.offset_top = vertical_offset
		lbl.offset_bottom = vertical_offset
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _center_at_point(c: Control, point: Vector2, size: Vector2) -> void:
	# Place `c` with its rect CENTERED on `point` (in 300x400 frame ref coords),
	# at `size` (also in ref coords, scaled to card pixels by FRAME_TO_CARD_SCALE).
	# Anchor x/y are identical for left/right and top/bottom — the rect is built
	# entirely by the symmetric offsets, so it's always centered on `point`
	# regardless of card size or container layout.
	c.anchor_left = point.x / FRAME_REF_SIZE.x
	c.anchor_right = c.anchor_left
	c.anchor_top = point.y / FRAME_REF_SIZE.y
	c.anchor_bottom = c.anchor_top
	var half_w := size.x * FRAME_TO_CARD_SCALE * 0.5
	var half_h := size.y * FRAME_TO_CARD_SCALE * 0.5
	c.offset_left = -half_w
	c.offset_right = half_w
	c.offset_top = -half_h
	c.offset_bottom = half_h


func _make_styled_label(text: String, font: Font, font_size: int,
		color: Color) -> Label:
	# Standard card-text label: centered horizontally and vertically inside its
	# anchor rect, with a black outline for readability over the painted frame
	# art. Callers can override outline color/size after (e.g. parchment text
	# uses a warm outline instead of black).
	var lbl := Label.new()
	lbl.text = text
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _build_placeholder_art(parent: Control, al: float, ar: float,
		at: float, ab: float) -> Control:
	# Plain hash-tinted gradient. No silhouette/icon overlay — board-game
	# icons (chess pieces, swords, etc.) clashed hard with the painterly
	# style of cards that DO have art. Better to be quietly minimalist than
	# loudly mismatched. Cards with dedicated illustrations look painted;
	# cards without look like unrevealed glyphs.
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.anchor_left = al
	wrap.anchor_right = ar
	wrap.anchor_top = at
	wrap.anchor_bottom = ab
	parent.add_child(wrap)

	# Two-tone vertical gradient: dark hash-tinted at the bottom, slightly
	# lighter at the top. Gives the placeholder some visual depth without
	# competing with real card art elsewhere on the screen.
	var hue := float(abs(card_id.hash()) % 360) / 360.0
	var sat := 0.45 if not is_opponent else 0.28
	var top_bg := ColorRect.new()
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_bg.color = Color.from_hsv(hue, sat * 0.6, 0.18)
	wrap.add_child(top_bg)
	var bottom_bg := ColorRect.new()
	bottom_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bg.anchor_left = 0.0
	bottom_bg.anchor_right = 1.0
	bottom_bg.anchor_top = 0.45
	bottom_bg.anchor_bottom = 1.0
	bottom_bg.color = Color.from_hsv(hue, sat, 0.09)
	wrap.add_child(bottom_bg)
	return wrap


func _make_circle_badge(color: Color, sz: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.lightened(0.3)
	s.border_color.a = 0.4
	var r := int(sz * 0.5)
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	p.add_theme_stylebox_override("panel", s)
	return p


func _make_badge_label(text: String, font_sz: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# Engraved-style number for a GemOrb. Same emboss recipe as the hand-card
# stat orbs — thick dark outline (separation from facet shading), soft drop
# shadow (number reads as raised, not painted on), heavy stat font for the
# numeral weight every AAA card game uses (Cinzel Black / Beleren Bold).
#
# light_face=true  → bright cream face on dark gems (cost blue, HP red).
# light_face=false → deep brown face with cream outline on the gold ATK
#                    shield — "stamped into metal" treatment.
func _build_orb_number_label(text: String, font_sz: int,
		light_face: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_stat:
		lbl.add_theme_font_override("font", GameTheme.font_stat)
	elif GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", font_sz)
	if light_face:
		lbl.add_theme_color_override("font_color", Color(1, 0.98, 0.90))
		lbl.add_theme_color_override("font_outline_color",
			Color(0, 0, 0, 0.98))
		lbl.add_theme_constant_override("outline_size", 3)
		lbl.add_theme_color_override("font_shadow_color",
			Color(0, 0, 0, 0.55))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	else:
		lbl.add_theme_color_override("font_color",
			Color(0.118, 0.078, 0.024))
		lbl.add_theme_color_override("font_outline_color",
			Color(1, 0.96, 0.78, 0.85))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_shadow_color",
			Color(0, 0, 0, 0.45))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ═══════════════════════════════════════════
#  STAT UPDATES
# ═══════════════════════════════════════════

func update_stat_display() -> void:
	if _hp_label:
		_hp_label.text = str(max(current_hp, 0))
		if current_hp < card_data.hp:
			_hp_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
		else:
			_hp_label.add_theme_color_override("font_color", _hp_base_color)
	if _atk_label:
		var display_atk = current_atk + temp_atk_buff
		_atk_label.text = str(display_atk)
		if display_atk > card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.ATK_BUFFED)
		elif display_atk < card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
		else:
			_atk_label.add_theme_color_override("font_color", _atk_base_color)


func update_floop_display() -> void:
	if _floop_indicator:
		if will_floop:
			_floop_indicator.text = "FLOOP"
			_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
			_floop_indicator.visible = true
		elif is_on_battlefield and has_floop() and not is_opponent:
			_floop_indicator.text = "click: floop"
			_floop_indicator.visible = true
			_floop_indicator.add_theme_color_override("font_color", Color(0.6, 0.5, 0.3, 0.7))
		else:
			_floop_indicator.visible = false
	if will_floop:
		_set_border_color(GameTheme.FLOOP_BLUE)
		if _art_rect:
			_art_rect.modulate = Color(0.6, 0.7, 1.0, 0.9)
	elif is_on_battlefield and has_floop() and not is_opponent:
		_set_border_color(Color(0.5, 0.4, 0.2, 0.6))
		if _art_rect:
			_art_rect.modulate = Color.WHITE
	else:
		_set_border_color(_get_default_frame_tint())
		if _art_rect:
			_art_rect.modulate = Color.WHITE


func toggle_floop() -> void:
	if not has_floop():
		return
	will_floop = not will_floop
	update_floop_display()


# ═══════════════════════════════════════════
#  DAMAGE
# ═══════════════════════════════════════════

func take_damage(amount: int) -> void:
	if has_keyword("armored"):
		amount = maxi(1, amount - 1)
	if card_data.get("extra_damage", 0) > 0:
		amount += card_data.extra_damage
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
	update_stat_display()
	if current_hp <= 0:
		_die()


func take_damage_bypass_armor(amount: int) -> void:
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
	update_stat_display()
	if current_hp <= 0:
		_die()


func _die() -> void:
	destroyed.emit()
	queue_free()


# ═══════════════════════════════════════════
#  HAND POSITIONING + HOVER
# ═══════════════════════════════════════════

func set_hand_target(pos: Vector2, rot: float, scl: Vector2 = Vector2.ONE) -> void:
	_hand_target_position = pos
	_hand_target_rotation = rot
	_hand_target_scale = scl
	# Pivot at bottom-centre of the card. Two reasons: (1) the fan rotation
	# in Combat._layout_hand wants the card's bottom anchored to the arc
	# while the top swings outward — pivot bottom-centre IS that behaviour.
	# (2) hover scale uses the same pivot so the card grows UPWARD from the
	# hand baseline, never sinking below where the bottom orbs sit.
	pivot_offset = Vector2(size.x * 0.5, size.y)
	if not _is_hovered and not _is_being_dragged:
		position = _hand_target_position
		rotation = _hand_target_rotation
		scale = _hand_target_scale


func _on_mouse_entered() -> void:
	if _is_playing or _is_being_dragged:
		return
	_is_hovered = true
	_set_border_color(GameTheme.GILT_BRIGHT)
	if not is_on_battlefield:
		z_index = 10
		# pivot_offset is set by set_hand_target (bottom-centre) and
		# intentionally not touched here — overwriting it would shift the
		# card's apparent position because its rotation also depends on the
		# pivot. Hover-scale grows from the existing pivot.
		scale = Vector2(1.15, 1.15)
		# Lift the card upward so it pops out of the hand. Combined with
		# Combat._layout_hand's "peek from below" positioning (cards rest
		# with ~25% of their height past the screen edge) and the 0.8→1.15
		# scale pop (1.44x visual), the hovered card visibly leaps free of
		# its neighbours — the Hearthstone signature read.
		rotation = 0.0
		position = _hand_target_position + Vector2(0, -80)
	_show_detail_panel()


func _on_mouse_exited() -> void:
	if _is_being_dragged or _is_playing:
		return
	_is_hovered = false
	if is_on_battlefield and will_floop:
		_set_border_color(GameTheme.FLOOP_BLUE)
	elif is_on_battlefield and has_floop() and not is_opponent:
		_set_border_color(Color(0.5, 0.4, 0.2, 0.6))
	else:
		_set_border_color(_get_default_frame_tint())
	if not is_on_battlefield:
		z_index = 0
		# Restore the resting hand pose set by set_hand_target — scale,
		# rotation, and the lifted Y. pivot_offset stays at bottom-centre.
		scale = _hand_target_scale
		rotation = _hand_target_rotation
		position = _hand_target_position
	_hide_detail_panel()


func _get_default_frame_tint() -> Color:
	return _default_border_color


func _set_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


# ═══════════════════════════════════════════
#  DRAG TO PLAY
# ═══════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_on_battlefield and not is_opponent and has_floop():
					floop_clicked.emit()
				else:
					_start_drag(event.global_position)
			else:
				_end_drag()
	elif event is InputEventMouseMotion and _is_being_dragged:
		_update_drag(event.global_position)


func _start_drag(mouse_pos: Vector2) -> void:
	if _is_playing or is_on_battlefield or is_opponent:
		return
	_is_being_dragged = true
	_is_hovered = false
	_drag_offset = global_position - mouse_pos
	z_index = 20


func _update_drag(mouse_pos: Vector2) -> void:
	global_position = mouse_pos + _drag_offset


func _end_drag() -> void:
	if not _is_being_dragged:
		return
	_is_being_dragged = false
	z_index = 0
	var viewport_h = get_viewport_rect().size.y
	if global_position.y < viewport_h * PLAY_THRESHOLD_Y:
		played.emit()
	else:
		# Not high enough to play — snap back into the hand. Restore scale,
		# rotation, and position from set_hand_target. (The previous
		# `scale = ONE; rotation = 0.0; queue_sort` worked when the hand was
		# an HBoxContainer; the new fan layout is Control + manual position,
		# so we restore the per-card pose explicitly.)
		scale = _hand_target_scale
		rotation = _hand_target_rotation
		position = _hand_target_position


func fly_to_play_area(target_pos: Vector2) -> void:
	_is_playing = true
	global_position = target_pos
	rotation = 0.0
	scale = Vector2.ONE
	_is_playing = false


# ═══════════════════════════════════════════
#  HOVER DETAIL PANEL
# ═══════════════════════════════════════════

static var _detail_popup: Control = null
static var _detail_owner = null

func _show_detail_panel() -> void:
	if card_data.is_empty():
		return
	_detail_owner = self
	if _detail_popup and is_instance_valid(_detail_popup):
		_detail_popup.queue_free()

	var vp = get_viewport()
	if not vp:
		return
	var root = vp.get_child(0) if vp.get_child_count() > 0 else null
	if not root:
		return

	_detail_popup = _build_detail()
	root.add_child(_detail_popup)

	_detail_popup.modulate.a = 0.0
	var tw = _detail_popup.create_tween()
	tw.tween_property(_detail_popup, "modulate:a", 1.0, 0.12)


func _hide_detail_panel() -> void:
	if _detail_owner != self:
		return
	if _detail_popup and is_instance_valid(_detail_popup):
		_detail_popup.queue_free()
		_detail_popup = null
	_detail_owner = null


func _build_detail() -> PanelContainer:
	const PW := 280.0
	const MARGIN := 16.0
	const PAD := 12.0

	var panel := PanelContainer.new()
	panel.z_index = 100
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if GameTheme.tex_panel_9p:
		panel.add_theme_stylebox_override("panel",
			GameTheme.make_panel_textured(Color(0.15, 0.12, 0.08), 20, int(PAD)))
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.05, 0.04, 0.95)
		style.border_color = GameTheme.GILT
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.shadow_color = Color(0, 0, 0, 0.6)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0, 4)
		style.content_margin_left = PAD
		style.content_margin_right = PAD
		style.content_margin_top = PAD
		style.content_margin_bottom = PAD
		panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	# ── Name + cost row ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	var cost_lbl := Label.new()
	cost_lbl.text = "%d" % card_data.get("cost", 0)
	if GameTheme.font_display:
		cost_lbl.add_theme_font_override("font", GameTheme.font_display)
	cost_lbl.add_theme_font_size_override("font_size", 22)
	cost_lbl.add_theme_color_override("font_color", GameTheme.MANA_BLUE)
	cost_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cost_lbl.add_theme_constant_override("outline_size", 3)
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(cost_lbl)

	var name_lbl := Label.new()
	name_lbl.text = card_data.get("name", "")
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", GameTheme.IVORY)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	# ── Type + rarity line ──
	var type_text := "Creature" if is_creature() else "Spell"
	var rarity_text: String = str(card_data.get("rarity", "common")).capitalize()
	var type_lbl := Label.new()
	type_lbl.text = "%s  •  %s" % [type_text, rarity_text]
	if GameTheme.font_body:
		type_lbl.add_theme_font_override("font", GameTheme.font_body)
	type_lbl.add_theme_font_size_override("font_size", 13)
	type_lbl.add_theme_color_override("font_color",
		GameTheme.rarity_color(card_data.get("rarity", "common")))
	type_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	type_lbl.add_theme_constant_override("outline_size", 2)
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(type_lbl)

	# ── Divider ──
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.4)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(div)

	# ── Stats (creatures only) ──
	if is_creature():
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 24)
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(stats)

		var atk_lbl := Label.new()
		atk_lbl.text = "ATK  %d" % card_data.get("atk", 0)
		if GameTheme.font_display:
			atk_lbl.add_theme_font_override("font", GameTheme.font_display)
		atk_lbl.add_theme_font_size_override("font_size", 18)
		atk_lbl.add_theme_color_override("font_color", GameTheme.ATK_RED)
		atk_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		atk_lbl.add_theme_constant_override("outline_size", 2)
		atk_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_child(atk_lbl)

		var hp_lbl := Label.new()
		hp_lbl.text = "HP  %d" % card_data.get("hp", 0)
		if GameTheme.font_display:
			hp_lbl.add_theme_font_override("font", GameTheme.font_display)
		hp_lbl.add_theme_font_size_override("font_size", 18)
		hp_lbl.add_theme_color_override("font_color", GameTheme.HEALTH_GREEN)
		hp_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		hp_lbl.add_theme_constant_override("outline_size", 2)
		hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_child(hp_lbl)

	# ── Description ──
	var desc_text: String = str(card_data.get("desc", ""))
	if desc_text != "":
		var desc := Label.new()
		desc.text = desc_text
		if GameTheme.font_body:
			desc.add_theme_font_override("font", GameTheme.font_body)
		desc.add_theme_font_size_override("font_size", 14)
		desc.add_theme_color_override("font_color", GameTheme.DESC_DIM)
		desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		desc.add_theme_constant_override("outline_size", 2)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(PW - PAD * 2, 0)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc)

	# ── Keywords ──
	var keywords: Array = card_data.get("keywords", [])
	if keywords.size() > 0:
		var kw_div := ColorRect.new()
		kw_div.custom_minimum_size = Vector2(0, 1)
		kw_div.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.25)
		kw_div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(kw_div)

		for kw in keywords:
			var tip := KeywordEffects.tooltip_for(kw)
			if tip == "":
				continue
			var kw_lbl := Label.new()
			kw_lbl.text = tip
			if GameTheme.font_body:
				kw_lbl.add_theme_font_override("font", GameTheme.font_body)
			kw_lbl.add_theme_font_size_override("font_size", 12)
			kw_lbl.add_theme_color_override("font_color", GameTheme.KEYWORD_GOLD)
			kw_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
			kw_lbl.add_theme_constant_override("outline_size", 2)
			kw_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			kw_lbl.custom_minimum_size = Vector2(PW - PAD * 2, 0)
			kw_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(kw_lbl)

	# ── On-enter / on-death / floop descriptions ──
	var extra_lines: Array[String] = []
	if card_data.has("on_enter"):
		extra_lines.append("On Enter: " + card_data.get("desc", ""))
	if card_data.has("on_death"):
		var od = card_data.on_death
		if od.has("type"):
			extra_lines.append("On Death: %s" % _describe_trigger(od))
	if card_data.has("floop"):
		var fl = card_data.floop
		extra_lines.append("Floop: %s" % _describe_trigger(fl))
	if card_data.has("adj_buff"):
		var ab = card_data.adj_buff
		var parts: Array[String] = []
		if ab.get("atk", 0) != 0:
			parts.append("+%d ATK" % ab.atk)
		if ab.get("hp", 0) != 0:
			parts.append("+%d HP" % ab.hp)
		extra_lines.append("Adjacent: %s" % ", ".join(parts))

	for line in extra_lines:
		var el := Label.new()
		el.text = line
		if GameTheme.font_body:
			el.add_theme_font_override("font", GameTheme.font_body)
		el.add_theme_font_size_override("font_size", 12)
		el.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
		el.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		el.add_theme_constant_override("outline_size", 2)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.custom_minimum_size = Vector2(PW - PAD * 2, 0)
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(el)

	# Position top-right
	panel.position = Vector2(1600 - PW - MARGIN, MARGIN)
	panel.size = Vector2(PW, 0)
	return panel


func _describe_trigger(data: Dictionary) -> String:
	var t = data.get("type", "")
	var v = data.get("value", 0)
	match t:
		"damage_opposing": return "Deal %d to opposing creature" % v
		"damage_random_player": return "Deal %d to random friendly creature" % v
		"damage_all_enemies": return "Deal %d to all enemy creatures" % v
		"damage_face": return "Deal %d to enemy hero" % v
		"draw": return "Draw %d card(s)" % v
		"gain_gold": return "Gain %d gold" % v
		"debuff_opposing_atk": return "Reduce opposing ATK by %d" % v
		"discard_random": return "Discard %d random card(s)" % v
		"damage_opposing_lane": return "Deal %d to opposing lane" % v
		"summon": return "Summon a %d/%d token" % [data.get("atk", 1), data.get("hp", 1)]
		"bonus_mana": return "Gain %d bonus mana" % v
		"debuff_all_player_atk": return "Reduce all friendly ATK by %d" % v
		"damage_adjacent": return "Deal %d to adjacent creatures" % v
		"damage_any": return "Deal %d to any target" % v
		"summon_random": return "Summon a random creature"
		"kill_adjacent_summon": return "Kill adjacent, summon in its place"
		"steal_atk": return "Steal %d ATK from opposing" % v
		"heal_all_friendly": return "Heal all friendly creatures %d" % v
		"summon_token": return "Summon a token creature"
	return t.replace("_", " ").capitalize()
