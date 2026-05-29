extends PanelContainer
## Card2D.gd — 225x300 card. Three layout modes, picked in _build_layout:
##   - v4 (USE_PROCEDURAL_FRAME on): pure Godot-drawn frame, no PNG dep
##   - v3 (USE_NEW_FRAME on): painted PNG frame with POINT_*-anchored labels
##   - v1/legacy: original gilt-banner layout
## Compact battlefield mode swaps to an art-token layout (no rules text).

signal played
signal destroyed
# Fired when current_hp would drop the card to dead. Listeners (Phantom Veil
# relic, Reborn on_death) can set current_hp back > 0 to cancel the death.
# If no listener rescues, _die() runs and destroyed fires.
signal will_die
# Fires AFTER current_hp is reduced (any path: combat, spell, thorns, on-death
# damage). amount is the post-armor damage actually applied. Used by relics
# like Stalwart's Anvil, Wormwood, Spike Driver that need to react to a
# friendly being hit.
signal damaged(amount: int)
signal floop_clicked
# Drag lifecycle — Combat listens so it can light up the slot the player is
# about to drop on. `dragging` fires each time the cursor moves while the
# card is held; `drag_ended` fires once when the mouse is released, before
# `played` (so highlights are cleared whether or not the drop is valid).
signal dragging(global_pos: Vector2)
signal drag_ended


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
# Identity of this card's copy within RunState.deck (deck_uids). -1 for cards
# with no deck origin (tokens, curses, copies). Lets the combat draw pile carry
# per-copy upgrades through the play→death→discard→reshuffle lifecycle.
var deck_uid: int = -1
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
# Visual-redesign prototype path. ONLY set true by tools/render_cards harness.
# When true, _build_layout dispatches to _build_redesign_proto so the live game
# (which never sets this) is completely unaffected.
@export var redesign_proto: bool = false
# Keyword-treatment A/B for the redesign prototype only. 0 = pill shelf,
# 1 = drop (no icon row), 2 = engraved recessed plaque, 3 = stamps on the
# art's lower-left, 4 = 40px orb rail, 5 = 56px orbs (stat-orb parity).
# 5 is the chosen default: the only size legible at 0.6x battlefield scale.
@export var kw_variant: int = 5

# Per-card font override (used by Collection gallery font A/B test).
# When set, this Font replaces GameTheme.font_display for the name banner
# and stat orbs on this card. Bypasses CardTextureCache (override is per-
# instance, cache is keyed by card data — collisions would mix fonts).
@export var display_font_override: Font = null

var card_data: Dictionary = {}
var current_hp := 0
var current_atk := 0
var current_lane: int = -1
# Sentinel for "ATK never displayed yet" — used by update_stat_display to
# emit a buff/debuff popup only on subsequent changes, not the first paint.
var _displayed_effective_atk: int = -999
# Typed gameplay state — receptacle for flags migrating off set_meta.
# See scripts/state/CreatureInstance.gd for the migration map.
var state: CreatureInstance = CreatureInstance.new()
# ─────────────────────────────────────────────────────────────────────────
#  CardCanvas — single-pass painter for the v5 card body.
# ─────────────────────────────────────────────────────────────────────────
#
# Replaces v4's stack of Panels (banner + art-frame + description-well +
# trim + halo + 6 depth overlays) with ONE _draw() call that paints the
# entire card body as a single continuous surface. The banner is a tapered
# ribbon polygon whose center sags into the art's top edge; the art/
# description seam is a painted scroll divider with a small rosette at the
# center — NOT a 1px ColorRect line. The eye reads "one painted card"
# instead of "spreadsheet of stacked cells."
#
# Why this beats v4: the v4 forensic audit showed the card was 8+ axis-
# aligned `Panel`s with shared 5%/95% X anchors. You could trace the cells
# with a ruler. The fix isn't more overlays — it's making the elements
# OVERLAP cell boundaries (tapered ribbon overruns the art's top edge,
# stat orbs straddle the art/description seam, painted scroll divider
# replaces the rectangular section break).
class CardCanvas extends Control:
	var rarity: String = "common"
	var is_spell_card: bool = false
	var trim_color: Color = Color(0.831, 0.745, 0.541, 1.0)
	var ribbon_color: Color = Color(0.18, 0.12, 0.08, 0.95)
	var divider_color: Color = Color(0.72, 0.55, 0.20, 0.90)
	var parchment_tex: Texture2D
	var compact_draw: bool = false
	var frame_texture: Texture2D
	# Render passes — set draw_back_only=true on the back-layer instance
	# (added before art_clip), draw_ribbon_only=true on the front-layer
	# instance (added after art_clip so its center sag visually overlaps
	# the art window's top edge — the "break the cell" move).
	var draw_back_only: bool = false
	var draw_ribbon_only: bool = false

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var W := size.x
		var H := size.y
		if W <= 0.0 or H <= 0.0:
			return
		if draw_ribbon_only:
			_draw_ribbon(W, H)
			return
		_draw_body(W, H)
		_draw_divider(W, H)
		if not frame_texture:
			_draw_art_inset(W, H)
			_draw_edge_trim(W, H)
		if not draw_back_only:
			_draw_ribbon(W, H)

	func _draw_body(W: float, H: float) -> void:
		if not compact_draw:
			draw_rect(Rect2(Vector2(0, 5), Vector2(W, H)),
				Color(0, 0, 0, 0.32), true)
		if frame_texture:
			draw_texture_rect(frame_texture, Rect2(Vector2.ZERO, Vector2(W, H)), false)
			return
		var body_color := Color(0.918, 0.842, 0.682, 1.0)  # warm parchment
		if is_spell_card:
			body_color = Color(0.840, 0.825, 0.928, 1.0)  # cooled spell wash
		var silhouette := _rounded_rect(Rect2(Vector2(0, 0), Vector2(W, H)), 8.0)
		draw_colored_polygon(silhouette, body_color)
		# One continuous parchment texture stretched across the whole body
		# (NOT 6 stacked TextureRect overlays at low alpha). Done as a
		# textured polygon so the rounded corners clip the texture.
		if parchment_tex:
			var tw := float(parchment_tex.get_width())
			var th := float(parchment_tex.get_height())
			var uvs := PackedVector2Array()
			for p in silhouette:
				uvs.append(Vector2(p.x / tw, p.y / th))
			var cs := PackedColorArray()
			for i in range(silhouette.size()):
				cs.append(Color(1, 1, 1, 0.42))
			draw_polygon(silhouette, cs, uvs, parchment_tex)
		# Soft top-warm / bottom-cool wash — fakes a hint of light direction
		# without stacking 4 separate TextureRect gradients.
		if not compact_draw:
			var top := PackedVector2Array([
				Vector2(0, 0), Vector2(W, 0),
				Vector2(W, H * 0.48), Vector2(0, H * 0.48),
			])
			draw_colored_polygon(top, Color(1.0, 0.97, 0.84, 0.06))
			var bot := PackedVector2Array([
				Vector2(0, H * 0.55), Vector2(W, H * 0.55),
				Vector2(W, H), Vector2(0, H),
			])
			draw_colored_polygon(bot, Color(0.25, 0.15, 0.07, 0.16))

	func _draw_ribbon(W: float, H: float) -> void:
		# Tapered ribbon banner — fishtail ends extend past the rectangular
		# banner zone at left/right; the center sags down into the art
		# window's top edge. THIS is the move that kills "cell stacked on
		# cell": the ribbon's silhouette overlaps the art's silhouette.
		var top := H * 0.058
		var mid := H * 0.118
		var sag := H * 0.160       # overlaps art zone (starts at 0.168)
		var inner_l := W * 0.06
		var inner_r := W * 0.94
		var fish_l := W * 0.030
		var fish_r := W * 0.970
		# Bumped sag from 0.160 → 0.190 so the center clearly dips INTO
		# the art zone (which starts at 0.172). The art_clip will hide
		# half of it unless this CardCanvas is rendered AFTER the art —
		# see draw_ribbon_only mode and the front-pass instance in v5.
		var sag_deep := H * 0.190

		var ribbon := PackedVector2Array([
			Vector2(fish_l, top + 4),             # 0 left fishtail
			Vector2(inner_l + 6, top),            # 1
			Vector2(W * 0.5, top - 1),            # 2 top center
			Vector2(inner_r - 6, top),            # 3
			Vector2(fish_r, top + 4),             # 4 right fishtail
			Vector2(inner_r - 2, mid),            # 5
			Vector2(inner_r - 8, sag),            # 6
			Vector2(W * 0.62, sag_deep - 4),
			Vector2(W * 0.5,  sag_deep),          # 8 center sag (into art)
			Vector2(W * 0.38, sag_deep - 4),
			Vector2(inner_l + 8, sag),            # 10
			Vector2(inner_l + 2, mid),            # 11
		])

		# Shadow under the ribbon
		if not compact_draw:
			var sh := PackedVector2Array()
			for p in ribbon:
				sh.append(p + Vector2(0, 3))
			draw_colored_polygon(sh, Color(0, 0, 0, 0.40))

		# Fill
		draw_colored_polygon(ribbon, ribbon_color)

		# Thin highlight band along the top — fakes the bevel without an
		# emboss-line ColorRect Panel child.
		var hl := PackedVector2Array([
			Vector2(inner_l + 8, top + 1.5),
			Vector2(inner_r - 8, top + 1.5),
			Vector2(inner_r - 8, top + 3),
			Vector2(inner_l + 8, top + 3),
		])
		draw_colored_polygon(hl, Color(1, 1, 1, 0.18))

		# Gilt trim around the ribbon polygon
		var closed := ribbon.duplicate()
		closed.append(ribbon[0])
		draw_polyline(closed, trim_color, 1.3, true)

		# Triangular notch cut into each fishtail end — turns the pointy
		# ends into "swallow-tail" cuts, the period-correct banner shape.
		var notch_l := PackedVector2Array([
			Vector2(fish_l + 1, top + 4),
			Vector2(inner_l + 2, top + 7),
			Vector2(inner_l + 2, top + 1),
		])
		draw_colored_polygon(notch_l, Color(0, 0, 0, 0.55))
		var notch_r := PackedVector2Array([
			Vector2(fish_r - 1, top + 4),
			Vector2(inner_r - 2, top + 7),
			Vector2(inner_r - 2, top + 1),
		])
		draw_colored_polygon(notch_r, Color(0, 0, 0, 0.55))

	func _draw_divider(W: float, H: float) -> void:
		# Painted scroll divider — two tapered gold strokes flanking a
		# rosette. NOT a 1px ColorRect rule. The seam between art and
		# description is a painted feature, not a stroke between Panels.
		var y := H * 0.612
		var li := W * 0.10
		var ri := W * 0.90
		var c := W * 0.5

		# Left tapered stroke
		var ls := PackedVector2Array([
			Vector2(li, y - 1.5),
			Vector2(c - 20, y - 0.5),
			Vector2(c - 20, y + 0.5),
			Vector2(li, y + 1.5),
		])
		draw_colored_polygon(ls, divider_color)
		# Right tapered stroke
		var rs := PackedVector2Array([
			Vector2(c + 20, y - 0.5),
			Vector2(ri, y - 1.5),
			Vector2(ri, y + 1.5),
			Vector2(c + 20, y + 0.5),
		])
		draw_colored_polygon(rs, divider_color)

		# Center rosette — two crossed ellipses + a dark dot
		var v_petal := PackedVector2Array()
		for i in range(18):
			var ang = TAU * float(i) / 18.0
			v_petal.append(Vector2(c + cos(ang) * 2.2, y + sin(ang) * 6.5))
		draw_colored_polygon(v_petal, divider_color)
		var h_petal := PackedVector2Array()
		for i in range(18):
			var ang = TAU * float(i) / 18.0
			h_petal.append(Vector2(c + cos(ang) * 6.5, y + sin(ang) * 2.2))
		draw_colored_polygon(h_petal, divider_color)
		draw_circle(Vector2(c, y), 1.6, Color(0.18, 0.10, 0.04, 0.95),
			true, -1.0, true)

	func _draw_art_inset(W: float, H: float) -> void:
		# Painted dark outline around the art zone — no `Panel.border_width`.
		# Just a 1.4 px polyline + a 3 px gradient strip at top to fake
		# the recessed-window feeling.
		var l := W * 0.075
		var r := W * 0.925
		var t := H * 0.168
		var b := H * 0.572
		var out := PackedVector2Array([
			Vector2(l, t), Vector2(r, t),
			Vector2(r, b), Vector2(l, b), Vector2(l, t),
		])
		draw_polyline(out, Color(0.12, 0.07, 0.04, 0.85), 1.4, true)
		if not compact_draw:
			var top_strip := PackedVector2Array([
				Vector2(l + 1, t + 1),
				Vector2(r - 1, t + 1),
				Vector2(r - 1, t + 4),
				Vector2(l + 1, t + 4),
			])
			draw_colored_polygon(top_strip, Color(0, 0, 0, 0.30))

	func _draw_edge_trim(W: float, H: float) -> void:
		# Gilt trim around the card silhouette; rares get a second darker
		# hairline just inside so the gilt reads as a metal groove edge,
		# not a stuck-on outline.
		var silhouette := _rounded_rect(Rect2(Vector2(0, 0), Vector2(W, H)), 8.0)
		var closed := silhouette.duplicate()
		closed.append(silhouette[0])
		draw_polyline(closed, trim_color, 1.6, true)
		if rarity == "rare":
			var inner := _rounded_rect(Rect2(Vector2(2, 2), Vector2(W - 4, H - 4)), 6.0)
			var ic := inner.duplicate()
			ic.append(inner[0])
			draw_polyline(ic, Color(0.06, 0.03, 0.01, 0.55), 1.0, true)

	func _rounded_rect(rect: Rect2, radius: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var r := radius
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.position.x + rect.size.x
		var y1 := rect.position.y + rect.size.y
		var segs := 5
		for i in range(segs + 1):
			var ang = PI + (PI * 0.5) * (float(i) / float(segs))
			pts.append(Vector2(x0 + r + cos(ang) * r, y0 + r + sin(ang) * r))
		for i in range(segs + 1):
			var ang = -PI * 0.5 + (PI * 0.5) * (float(i) / float(segs))
			pts.append(Vector2(x1 - r + cos(ang) * r, y0 + r + sin(ang) * r))
		for i in range(segs + 1):
			var ang = 0.0 + (PI * 0.5) * (float(i) / float(segs))
			pts.append(Vector2(x1 - r + cos(ang) * r, y1 - r + sin(ang) * r))
		for i in range(segs + 1):
			var ang = PI * 0.5 + (PI * 0.5) * (float(i) / float(segs))
			pts.append(Vector2(x0 + r + cos(ang) * r, y1 - r + sin(ang) * r))
		return pts


var current_row: int = 0  # 0 = front, 1 = back (4x4 board)
var has_attacked_this_turn: bool = false
var will_floop: bool = false
var has_flooped_this_turn: bool = false
var last_stand_used: bool = false
var is_token: bool = false
var temp_atk_buff: int = 0
# Persistent ATK buff (e.g. from Butcher's Cleaver) — counted in effective_atk
# but NOT wiped at end of turn. `persistent_atk_buff_rounds` decrements at
# start of each round (in Combat); when it reaches 0 the bonus is removed.
var persistent_atk_buff: int = 0
var persistent_atk_buff_rounds: int = 0
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
var _floop_pulse_tween: Tween = null
# Bottom-of-card type plate (rarity gem + type text). Always present on both
# spells and creatures, mirrors the StS "Skill" tag. For creatures it's
# hidden when the FLOOP indicator activates — see update_floop_display.
var _type_plate: Control
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
# Static flag: true while ANY Card2D is being dragged anywhere. Hand siblings
# read this in _on_mouse_entered to suppress their hover-pop animation —
# without it, dragging a card over the rest of the hand made each neighbour
# leap up in turn, which is visually noisy and obscures the drop target.
static var _any_card_dragging: bool = false
var _is_playing := false
var _drag_offset := Vector2.ZERO
var _hand_target_position := Vector2.ZERO
var _hand_target_rotation := 0.0
# Resting scale for hand cards. Set via set_hand_target by Combat._layout_hand
# (currently 0.8 for the Hearthstone-style smaller-cards-at-rest look). Hover
# scales to 1.15 — a 1.15/0.8 ≈ 1.44x visual pop relative to rest. Restored
# on _on_mouse_exited and _end_drag-not-played.
var _hand_target_scale := Vector2.ONE
# Tween that slides the card to its hand slot (draw / reflow). Killed when the
# card is hovered, dragged, or re-targeted so those snappy interactions win.
var _hand_tween: Tween = null
var _lunge_tween: Tween = null
var _recoil_tween: Tween = null
# Set true just before a sacrificed creature is destroyed so _die() plays the
# "ash away upward" ritual variant instead of the normal shrink-and-fade.
var _sacrifice_death: bool = false

const CARD_W := 225
const CARD_H := 300
const CARD_SIZE := Vector2(CARD_W, CARD_H)
# Battlefield (compact) cards switch to a LANDSCAPE aspect — creature art
# is generally wider than tall, so a landscape on-field token uses slot
# space far better than a shrunken portrait. The hand layout (drag, hover,
# detail panel) still uses portrait CARD_SIZE; only the slot occupant
# resizes to BATTLEFIELD_SIZE in _apply_compact_layout.
const BATTLEFIELD_W := 200
const BATTLEFIELD_H := 150
const BATTLEFIELD_SIZE := Vector2(BATTLEFIELD_W, BATTLEFIELD_H)
const COMPACT_SCALE := 0.50
# Cards count as "played" when their CENTER crosses above this fraction of
# viewport height. Centered (not top-left) so the player can drop on the
# back row — which sits just above the hand — without the card "not being
# high enough." 0.72 puts the cutoff right at the top of the hand zone.
const PLAY_THRESHOLD_Y := 0.72

# Painted-frame zone rects, in pixel coords of the 300x400 source frame
# (assets/frames/frame_creature_*.png). Each rect is the readable interior of a
# painted region — change a number here, the corresponding label moves. This is
# the single source of truth for text positioning on the v3 (PNG-frame) layout.
# v4 (procedural) uses normalized 0–1 anchors instead and does not consume these.
const FRAME_REF_SIZE := Vector2(300, 400)
# Card scaled to 225x300 from the 300x400 ref → 0.75 ratio.
const FRAME_TO_CARD_SCALE := 0.75

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
## v5 frame layout (frame_v5_b — gold trim variant). Pixel-measured from
## the actual PNG: art window y=16-177, banner y=197-223 (center 210),
## text well y=252-357 (center 304). Orbs use direct corner anchors —
## POINT_COST/ATK/HP are kept for fallback only, the orb positioning code
## hangs them past the card edges via offsets instead.
const POINT_COST    := Vector2(35.0, 35.0)     # legacy — orbs use direct anchors
const POINT_NAME    := Vector2(150.0, 210.0)   # cream ribbon banner center
const POINT_TYPE    := Vector2(150.0, 235.0)   # below banner — keyword strip
const POINT_DESC    := Vector2(150.0, 304.0)   # text well center
const POINT_ATK     := Vector2(30.0, 378.0)    # legacy — orbs use direct anchors
const POINT_HP      := Vector2(270.0, 378.0)   # legacy — orbs use direct anchors
const POINT_FLOOP   := Vector2(150.0, 390.0)   # between bottom orbs (creatures)
# Spell cards have no bottom orbs, so the targeting tag ("FRIENDLY" / "ENEMY" /
# "ANY CREATURE" / "ANY TARGET") used to sit at POINT_FLOOP and clip out of the
# 400px card frame. Anchor it inside the text-well lower band instead — fully
# visible without overlapping the description (well ends at y≈354).
const POINT_SPELL_TARGET := Vector2(150.0, 372.0)

const SIZE_COST     := Vector2(48, 36)
const SIZE_NAME     := Vector2(210, 38)
const SIZE_TYPE     := Vector2(170, 26)
# Text well is 105px tall × ~220px wide (pixel-measured frame_v5_b at y=252-357).
# SIZE_DESC fills it completely so wrap has more room and font isn't cramped.
const SIZE_DESC     := Vector2(240, 100)
const SIZE_STAT     := Vector2(48, 36)    # shared by ATK and HP
const SIZE_FLOOP    := Vector2(150, 24)

# Vertical pixel nudge applied to the cost / ATK / HP numeral labels inside
# their SphereOrb containers. Positive = move text DOWN, negative = move UP.
# Why this exists: Godot's Label vertical_alignment = CENTER centers on the
# font's full line box (ascent + descent), but caps/digits don't occupy the
# descender region — they visually sit in the UPPER portion of the line box,
# so the rendered character appears HIGH inside the orb. The SphereOrb's
# drop shadow below the sphere also shifts the painted "visual center" of
# the orb DOWNWARD relative to the container's geometric center. Both
# effects compound to put numerals visibly above the orb's bright center.
# This offset bypasses Godot's font-metric-driven centering with a direct
# pixel shift. Tune by eye: bigger value pushes numerals further down.
const ORB_NUMERAL_Y_OFFSET := 3


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
	_type_plate = null
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
	# Battlefield cards swap to LANDSCAPE dimensions — internal layout uses
	# anchor-based positioning (anchor_left = 0.06 etc.) so children rescale
	# automatically to the new aspect. Avoid touching `scale` here: Container
	# parents fight with it and the slot reservation desyncs from the visual
	# footprint.
	var target_size: Vector2 = BATTLEFIELD_SIZE if compact_mode else CARD_SIZE
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
	# Plain text — the display font (Lilita One) doesn't ship the U+2192 arrow
	# or U+2726 star glyphs we used earlier, so they rendered as tofu boxes.
	match String(card_data.get("targeting", "")):
		"enemy_creature":    return "ENEMY"
		"friendly_creature": return "FRIENDLY"
		"any_creature":      return "ANY CREATURE"
		"any":               return "ANY TARGET"
		_:                   return ""

func has_floop() -> bool:
	return card_data.has("floop")

func can_attack() -> bool:
	if has_attacked_this_turn: return false
	if will_floop: return false
	if has_flooped_this_turn: return false
	if state.is_frozen: return false
	# Structures are board objects (Pyres, Mausoleums, Altars) — they hold
	# charge counters and trigger encounter effects but never swing themselves.
	if has_keyword("structure"): return false
	if card_data.get("passive", "") == "cannot_attack_wall": return false
	if card_data.get("passive", "") == "siege": return true
	return true

func effective_atk() -> int:
	return current_atk + temp_atk_buff + persistent_atk_buff


# ═══════════════════════════════════════════
#  CARD BACKGROUND
# ═══════════════════════════════════════════

func _build_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Color(0, 0, 0, 0)
	s.set_border_width_all(0)
	s.set_corner_radius_all(0)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	# Drop shadow lifts the card off the scene background. shadow_size 6
	# fits inside CardTextureCache's 12px BAKE_PAD so it survives baking.
	# Offset (0,3) puts the shadow below the card — natural light-from-above.
	# Without this the painted card edge dissolved into the dark scene bg.
	s.shadow_color = Color(0, 0, 0, 0.70)
	s.shadow_size = 6
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
		art = CardArtAliases.try_load_spell_art(cid)
		if art == null:
			art = CardArtAliases.try_load_spell_art(name_id)
	if art == null:
		art = CardArtAliases.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art("e_" + name_id)
	return art


func _build_layout() -> void:
	if card_data.is_empty():
		return
	if redesign_proto:
		_build_redesign_proto()
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
		if GameTheme.USE_V5_OVERLAP_PAINT:
			_build_full_layout_v5()
		else:
			_build_full_layout_v4()
	elif GameTheme.USE_NEW_FRAME:
		# v6 redesign promoted to live. The in-hand card and every static card
		# display flow through this branch; so does the CardTextureCache bake
		# (it sets static_display + bake_strip_stats but no layout flag), so the
		# baked texture is the redesign with blank numerals and the baked-overlay
		# live labels land on the orbs (positions match v3). Battlefield tokens
		# use compact_mode above; the render harness still sets redesign_proto.
		_build_redesign_proto()
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

	var card_art: Texture2D = _find_card_art()
	if card_art == null:
		var placeholder_path := "res://assets/creatures/kindling_alt.png"
		if ResourceLoader.exists(placeholder_path):
			card_art = load(placeholder_path)
	var art_clip := Control.new()
	art_clip.clip_contents = true
	art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_clip.anchor_left = 0.04
	art_clip.anchor_right = 0.96
	art_clip.anchor_top = 0.04
	art_clip.anchor_bottom = 0.96
	root.add_child(art_clip)
	_art_rect = art_clip
	if card_art:
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)

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
	# trio. Shape uniformity reads cleaner than polygons at this scale;
	# position + colour disambiguate ATK/HP.
	#
	# No cost orb on the battlefield: mana cost is a "what does it take to
	# play this" stat, and the card has already been played. Leaving it on
	# the token confused the read (looked like another stat). Cost still
	# shows on the hover detail panel. _cost_badge/_cost_label stay null —
	# set_display_cost guards on is_on_battlefield + a null check.

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

	# Keyword orbs along the top-right so Swift / Piercing / Armored etc.
	# stay readable at a glance on battlefield tokens.
	var keywords: Array = card_data.get("keywords", [])
	if keywords.size() > 0:
		# Filter to icon-bearing, non-floop keywords (floop owns the FLOOP
		# indicator; on_enter et al. have no glyph). Cap at 3 for token width.
		var kw_icons: Array[Texture2D] = []
		for kw in keywords:
			if String(kw) == "floop":
				continue
			var icon_tex: Texture2D = GameTheme.get_keyword_icon(kw)
			if icon_tex == null:
				continue
			kw_icons.append(icon_tex)
			if kw_icons.size() >= 3:
				break
		# Glossy arcane-violet orbs at stat-orb parity (30px vs the token's 32px
		# ATK/HP gems) so keywords read at a glance; the flat 20px gold glyphs
		# washed into the art. Same GemOrb sphere as the stat orbs.
		if kw_icons.size() > 0:
			var kw_orb := 30.0
			var kw_gap := 4.0
			var kw_total := float(kw_icons.size()) * kw_orb + float(kw_icons.size() - 1) * kw_gap
			for i in range(kw_icons.size()):
				var korb := GemOrb.new()
				korb.shape = "circle"
				korb.style = "smooth"
				korb.fill_color = Color(0.247, 0.153, 0.376)  # deep arcane violet
				korb.gloss = 0.42  # calmer than stat orbs so the gilt glyph reads
				korb.anchor_left = 1.0; korb.anchor_right = 1.0
				korb.anchor_top = 0.0; korb.anchor_bottom = 0.0
				korb.offset_left = -4.0 - kw_total + float(i) * (kw_orb + kw_gap)
				korb.offset_right = korb.offset_left + kw_orb
				korb.offset_top = 4.0
				korb.offset_bottom = 4.0 + kw_orb
				korb.mouse_filter = Control.MOUSE_FILTER_IGNORE
				root.add_child(korb)
				var kglyph := TextureRect.new()
				kglyph.texture = kw_icons[i]
				kglyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				kglyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				kglyph.set_anchors_preset(Control.PRESET_FULL_RECT)
				kglyph.offset_left = 6; kglyph.offset_right = -6
				kglyph.offset_top = 6; kglyph.offset_bottom = -6
				kglyph.modulate = GameTheme.GILT_BRIGHT
				kglyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
				korb.add_child(kglyph)


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
	# Centre the 249×324 texture over the 225×300 card. The 12 px padding on
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
	# Wrapper Control concentric with the cost SphereOrb painted into the baked
	# texture. The bake uses the v3 layout, whose orbs are 56px (anchor 0,0 with
	# -9..47 offsets, sphere center at card-local 19px) — so the slot MUST use
	# the same 56px box, not the old v4 44px box (-9..35), or the numeral lands
	# above/left of the sphere. The label inside uses PRESET_FULL_RECT so it
	# centres inside the sphere painted underneath.
	var cost_slot := Control.new()
	cost_slot.anchor_left = 0.0; cost_slot.anchor_right = 0.0
	cost_slot.anchor_top = 0.0; cost_slot.anchor_bottom = 0.0
	cost_slot.offset_left = -9; cost_slot.offset_right = 47
	cost_slot.offset_top = -9; cost_slot.offset_bottom = 47
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
		# 56px box concentric with the v3 ATK sphere (anchor 0,1, -9..47 / -47..9,
		# sphere center at card-local (19, h-19)). Old v4 44px box left the numeral
		# below the sphere center — the worst-offset "bottom orb" case.
		var atk_slot := Control.new()
		atk_slot.anchor_left = 0.0; atk_slot.anchor_right = 0.0
		atk_slot.anchor_top = 1.0; atk_slot.anchor_bottom = 1.0
		atk_slot.offset_left = -9; atk_slot.offset_right = 47
		atk_slot.offset_top = -47; atk_slot.offset_bottom = 9
		atk_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(atk_slot)
		_atk_base_color = Color(0.10, 0.07, 0.02)  # dark-on-gold, matches v4
		_atk_label = _make_stat_number(str(current_atk), _atk_base_color, 0,
			Color(1.00, 0.78, 0.20, 0.90))
		atk_slot.add_child(_atk_label)
		_atk_badge = null

		# ── Live overlay: HP orb numeral (bottom-right) ──
		# 56px box concentric with the v3 HP sphere (anchor 1,1, -47..9 / -47..9,
		# sphere center at card-local (w-19, h-19)).
		var hp_slot := Control.new()
		hp_slot.anchor_left = 1.0; hp_slot.anchor_right = 1.0
		hp_slot.anchor_top = 1.0; hp_slot.anchor_bottom = 1.0
		hp_slot.offset_left = -47; hp_slot.offset_right = 9
		hp_slot.offset_top = -47; hp_slot.offset_bottom = 9
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
	_name_label.add_theme_color_override("font_color", GameTheme.get_name_color(card_data))
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

	# ── Layer 1: Frame overlay — per-card variant (rarity + type) ──
	# Placed first (below the art) so the art_clip below can render ON TOP,
	# covering the frame's dark fill in the art window region. The painted
	# border of the art window stays visible because art_clip is inset
	# slightly from the painted edge.
	var v3_frame: Texture2D = GameTheme.get_card_frame(card_data)
	if v3_frame:
		_frame_tex = TextureRect.new()
		_frame_tex.texture = v3_frame
		_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Rarity tint via self_modulate — v5 frames are visually identical
		# across rarity, so we tint the whole frame here to differentiate.
		# Uncommon = cool blue wash, rare = warm gold wash, starter = neutral.
		var rarity_str := String(card_data.get("rarity", "common"))
		match rarity_str:
			"uncommon": _frame_tex.self_modulate = Color(0.85, 0.95, 1.05)
			"rare":     _frame_tex.self_modulate = Color(1.10, 0.95, 0.78)
			"starter":  _frame_tex.self_modulate = Color(0.92, 0.92, 0.94)
			_:          pass
		# Spells get a slight purple wash so they read different from creatures.
		if is_spell():
			var s := _frame_tex.self_modulate
			_frame_tex.self_modulate = Color(s.r * 0.95, s.g * 0.92, s.b * 1.10)
		# Opponent tint applied last so it dominates over rarity.
		if is_opponent:
			_frame_tex.self_modulate = Color(1.0, 0.82, 0.78)
		root.add_child(_frame_tex)

	# ── Layer 1.5: Flatten the painted text well rectangle ──────────────
	# The frame PNG has a recessed rectangle painted around the description
	# area. This overlay covers it with the card body color so the text
	# floats on the card surface — Slay the Spire / Griftlands approach.
	# Hard text panels chop the card into separate sections; unified body
	# reads as one continuous surface.
	var text_overlay := Panel.new()
	text_overlay.anchor_left = 0.067   # covers painted border on the sides
	text_overlay.anchor_right = 0.933
	text_overlay.anchor_top = 0.625    # just below the banner shadow
	text_overlay.anchor_bottom = 0.920 # just above the bottom painted edge
	text_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var to_style := StyleBoxFlat.new()
	# #393540 — sampled card body color (RGB 57,53,64 from frame_v5_b at y=100).
	to_style.bg_color = Color(0.2235, 0.2078, 0.2510, 1.0)
	to_style.border_color = Color(0, 0, 0, 0)
	to_style.set_border_width_all(0)
	to_style.set_corner_radius_all(0)
	text_overlay.add_theme_stylebox_override("panel", to_style)
	# Paper grain texture overlay — gives the dark body subtle texture so it
	# doesn't read as a flat black rectangle. Same tex_card_grain used by v4.
	# Without this the lower half feels empty / cheap; with it the body
	# reads as "painted parchment in shadow" instead of "untextured surface".
	if GameTheme.tex_card_grain:
		var grain_overlay := TextureRect.new()
		grain_overlay.texture = GameTheme.tex_card_grain
		grain_overlay.stretch_mode = TextureRect.STRETCH_TILE
		# EXPAND_IGNORE_SIZE drops the 256x256 texture min-size so FULL_RECT anchors
		# can shrink the rect to the parent panel; without it the grain keeps its
		# texture size and spills out below/beside the card (visible band in Reward).
		grain_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grain_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		grain_overlay.modulate = Color(1, 1, 1, 0.20)
		grain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_overlay.add_child(grain_overlay)
	# Match the frame's rarity tint so the overlay color shifts with it.
	var rarity_for_overlay := String(card_data.get("rarity", "common"))
	match rarity_for_overlay:
		"uncommon": text_overlay.modulate = Color(0.85, 0.95, 1.05)
		"rare":     text_overlay.modulate = Color(1.10, 0.95, 0.78)
		"starter":  text_overlay.modulate = Color(0.92, 0.92, 0.94)
		_:          pass
	if is_spell():
		var sm := text_overlay.modulate
		text_overlay.modulate = Color(sm.r * 0.95, sm.g * 0.92, sm.b * 1.10)
	if is_opponent:
		text_overlay.modulate = Color(1.0, 0.82, 0.78)
	root.add_child(text_overlay)

	# ── Layer 2: Art with rounded corners (shader-masked) ────────────────
	# Art fills the full upper half from card edge to card edge. A canvas_item
	# shader discards pixels in the corners outside an ellipse, producing
	# rounded corners that match the painted card silhouette. Only the TOP
	# corners are visually relevant — the bottom edge sits against the banner.
	#
	# radius_x / radius_y are in UV space (0-1 normalized). For a card-edge-
	# to-card-edge art rect (~210px wide, ~140px tall in card pixels), a
	# 12px corner radius is ~0.057 in X and ~0.085 in Y. The ellipse-based
	# math makes the visual corner read as circular despite the aspect.
	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_clip := Control.new()
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Edge-to-edge anchors. 1.5% inset on sides leaves room for the
		# painted outer trim line of the card silhouette.
		art_clip.anchor_left = 0.020
		art_clip.anchor_right = 0.980
		art_clip.anchor_top = 0.015
		art_clip.anchor_bottom = 0.490
		root.add_child(art_clip)
		_art_rect = art_clip

		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Rounded-corner shader. Only rounds the TOP two corners so the art
		# meets the banner with a straight bottom edge — "art is the top half
		# of the card, banner cuts across" read. Rounding the bottom corners
		# too made the art look like a separate floating tile.
		var art_shader := Shader.new()
		art_shader.code = """
shader_type canvas_item;

uniform float radius_x : hint_range(0.0, 0.5) = 0.057;
uniform float radius_y : hint_range(0.0, 0.5) = 0.085;

void fragment() {
	vec2 uv = UV;
	float d_x = min(uv.x, 1.0 - uv.x);
	float d_y = uv.y;  // distance from TOP edge only — bottom stays square
	if (d_x < radius_x && d_y < radius_y) {
		vec2 offset = vec2(radius_x - d_x, radius_y - d_y);
		float ed = (offset.x * offset.x) / (radius_x * radius_x) +
				   (offset.y * offset.y) / (radius_y * radius_y);
		if (ed > 1.0) {
			COLOR.a = 0.0;
		}
	}
}
"""
		var art_mat := ShaderMaterial.new()
		art_mat.shader = art_shader
		art_mat.set_shader_parameter("radius_x", 0.057)
		art_mat.set_shader_parameter("radius_y", 0.085)
		art_tex.material = art_mat

		art_clip.add_child(art_tex)
	else:
		_art_rect = _build_placeholder_art(root, 0.020, 0.980, 0.015, 0.490)

	# Every text label below is placed via _center_at_point() using the POINT_*
	# and SIZE_* constants at the top of this file. To move a label, edit its
	# POINT_* coords — there are no other position numbers anywhere else.

	# ── Layer 3: Cost orb + label (top-left corner) ──────────────────────
	# 56px orb hanging 9px past the top-left corner (Hearthstone convention).
	# Direct corner anchors instead of _center_at_point so the orb sits
	# OUTSIDE the card silhouette like a stat gem rather than INSIDE the body.
	var v3_cost_orb := _make_stat_orb(GameTheme.COST_BLUE_GEM, 0.0,
		static_display)
	v3_cost_orb.anchor_left = 0.0; v3_cost_orb.anchor_right = 0.0
	v3_cost_orb.anchor_top = 0.0; v3_cost_orb.anchor_bottom = 0.0
	v3_cost_orb.offset_left = -9; v3_cost_orb.offset_right = 47
	v3_cost_orb.offset_top = -9; v3_cost_orb.offset_bottom = 47
	root.add_child(v3_cost_orb)
	# bake_strip_stats blanks the numeral during baking — the live overlay
	# label paints it on top of the orb. Without this check we'd burn the
	# number into the cached texture AND overlay it, causing "22" doubling.
	var stat_font: Font = display_font_override if display_font_override else GameTheme.font_stat
	# Numerals at 14 pt — matches the compact battlefield's label size so hand
	# cards and field tokens read with consistent number weight. (Earlier
	# experiment at 22 pt looked "giga" relative to the battlefield because
	# the 56 px hand orbs are visibly larger than the 30 px field orbs to
	# begin with — equal font size keeps the absolute glyph height matched.)
	# PRESET_FULL_RECT + CENTER alignment puts the glyph at the orb's visual
	# center; GameTheme.font_stat's FontVariation sets spacing_bottom = −5 so
	# caps/numerals optically center inside the line box instead of sitting high.
	_cost_label = _make_styled_label(
		"" if bake_strip_stats else str(card_data.cost),
		stat_font, 14, Color(0.996, 0.941, 0.800))  # #FEF0CC
	_cost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Shift the label rect DOWN to optically center the numeral on the orb's
	# painted bright center (see ORB_NUMERAL_Y_OFFSET docs above).
	_cost_label.offset_top = ORB_NUMERAL_Y_OFFSET
	_cost_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v3_cost_orb.add_child(_cost_label)

	# ── Layer 4: Name label inside the painted banner ──
	# DARK text on the CREAM banner — tribe-tinted. Each tribe color was hand-
	# tuned for ≥4.5:1 contrast on the cream banner (soldier amber, wretch rust,
	# beast forest, fae teal, undead crimson, construct slate, spell violet,
	# neutral warm brown). No outline — a 3px black outline around tiny dark
	# glyphs blobs them out, fusing letters into illegible smears (the old bug).
	# At ≥4.5:1 contrast Lilita's heavy weight stands on its own. Soft drop
	# shadow adds depth without darkening. Ellipsis-trim handles long names
	# like "Collector's Champion" gracefully when they overflow the banner.
	var display_font: Font = display_font_override if display_font_override else GameTheme.font_display
	_name_label = _make_styled_label(card_data.name, display_font,
		13, GameTheme.get_name_color(card_data))
	_name_label.add_theme_constant_override("outline_size", 0)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.30))
	_name_label.add_theme_constant_override("shadow_offset_x", 0)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_center_at_point(_name_label, POINT_NAME, SIZE_NAME)
	root.add_child(_name_label)

	# ── Layer 5: Keyword medallion strip ──
	# RE-ENABLED to fill the empty space between banner and description that
	# made cards feel bare (especially vanilla creatures with no description).
	# Shows colored medallions for each keyword the card has (Floop, Wither,
	# On-enter, etc.) — adds gameplay info AT A GLANCE + fills visual void.
	_type_label = Label.new()
	_type_label.visible = false
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_type_label)

	var kw_strip := HBoxContainer.new()
	kw_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kw_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	kw_strip.add_theme_constant_override("separation", 3)
	_center_at_point(kw_strip, POINT_TYPE, Vector2(200, 24))
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
	# Description: GameTheme.font_body for normal text, font_body_bold for
	# [b] keyword highlights. The PREVIOUS code set bold_font = font_body
	# which meant keywords got NO weight bump — only a color shift. That
	# made the description look flat ("effects still with this text").
	# Using the dedicated bold variant gives keywords the AAA weight pop.
	var desc_font: Font = display_font_override if display_font_override else GameTheme.font_body
	var desc_bold_font: Font = display_font_override if display_font_override else GameTheme.font_body_bold
	if desc_font:
		desc_rt.add_theme_font_override("normal_font", desc_font)
		desc_rt.add_theme_font_override("bold_font",
			desc_bold_font if desc_bold_font else desc_font)
	# Font size 11 in 300x400 ref → 8.25px screen (×0.75 scale). Was 8 ref
	# (6px screen) — illegible. 11 ref / 8 screen matches Slay the Spire's
	# body-text density at hand-size cards.
	desc_rt.add_theme_font_size_override("normal_font_size", 11)
	desc_rt.add_theme_font_size_override("bold_font_size", 11)
	# WARM CREAM on dark text well (was inverted before — dark on dark is
	# illegible). #E8DCC4 = warm cream, contrast 8.9:1 on #4E4956 (AAA).
	desc_rt.add_theme_color_override("default_color", Color(0.910, 0.863, 0.769))
	# Center-align the description visually (RichTextLabel respects [center]).
	var raw_desc: String = card_data.get("desc", "")
	var colorized: String = KeywordEffects.colorize_keywords(raw_desc)
	desc_rt.text = "[center]%s[/center]" % colorized
	_center_at_point(desc_rt, POINT_DESC, SIZE_DESC)
	root.add_child(desc_rt)

	# ── Layer 7: ATK / HP orbs + labels (bottom corners) ─────────────────
	# 56px orbs hanging 9px past the bottom corners (Hearthstone convention).
	# Direct anchors to bottom-left / bottom-right instead of _center_at_point.
	# Text colors per WCAG contrast research:
	#   ATK: #FFF4D6 warm off-white on bronze → 6.9:1 AAA (large text)
	#   HP:  #FFF0E5 warm porcelain on oxblood → 8.4:1 AAA
	if is_creature():
		var v3_atk_orb := _make_stat_orb(GameTheme.ATK_GOLD_SHIELD, 0.0,
			static_display)
		v3_atk_orb.anchor_left = 0.0; v3_atk_orb.anchor_right = 0.0
		v3_atk_orb.anchor_top = 1.0; v3_atk_orb.anchor_bottom = 1.0
		v3_atk_orb.offset_left = -9; v3_atk_orb.offset_right = 47
		v3_atk_orb.offset_top = -47; v3_atk_orb.offset_bottom = 9
		root.add_child(v3_atk_orb)
		_atk_label = _make_styled_label(
			"" if bake_strip_stats else str(current_atk),
			stat_font, 14, Color(1.000, 0.957, 0.839))  # #FFF4D6
		_atk_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_atk_label.offset_top = ORB_NUMERAL_Y_OFFSET
		_atk_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
		_atk_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v3_atk_orb.add_child(_atk_label)

		var v3_hp_orb := _make_stat_orb(GameTheme.HEALTH_RED_DROP, 0.0,
			static_display)
		v3_hp_orb.anchor_left = 1.0; v3_hp_orb.anchor_right = 1.0
		v3_hp_orb.anchor_top = 1.0; v3_hp_orb.anchor_bottom = 1.0
		v3_hp_orb.offset_left = -47; v3_hp_orb.offset_right = 9
		v3_hp_orb.offset_top = -47; v3_hp_orb.offset_bottom = 9
		root.add_child(v3_hp_orb)
		_hp_label = _make_styled_label(
			"" if bake_strip_stats else str(current_hp),
			stat_font, 14, Color(1.000, 0.941, 0.898))  # #FFF0E5
		_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hp_label.offset_top = ORB_NUMERAL_Y_OFFSET
		_hp_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
		_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v3_hp_orb.add_child(_hp_label)

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
			_center_at_point(tgt_lbl, POINT_SPELL_TARGET, SIZE_FLOOP)
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
#  REDESIGN PROTOTYPE (v6) — visual-audit mockup, gated by `redesign_proto`.
#  Builds on the v3 painted frame + PD-master art (the game's strongest
#  assets) and resolves the four unfinished zones from the design review:
#    1. Rarity is now a card-wide language — colored glow rim + a faceted
#       rarity gem (uncommon/rare only), not just a faint frame tint.
#    2. Keyword medallions are seated on an engraved SHELF instead of
#       floating as mystery glyphs in dead space.
#    3. Description sits on an aged-parchment page, vertically centered, so
#       short cards don't leave a void and the text reads as "a page."
#    4. Spells own their bottom with a forged footer cartouche (targeting /
#       INSTANT / EXHAUST) flanked by gems — no more empty orb wells.
#  NOTE: the painted filigree corners + forged nameplate in the full vision
#  are MJ-commissioned art; this proto fakes them procedurally to show layout.
# ═══════════════════════════════════════════

func _build_redesign_proto() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var rarity := String(card_data.get("rarity", "common"))
	var is_sp := is_spell()
	var glow_col: Color = GameTheme.rarity_color(rarity)

	# ── Layer -1: soft neutral seat shadow ───────────────────────────────
	# A large, soft, rarity-independent dark halo so the hard card edge melts
	# into whatever it sits on instead of stopping abruptly. This is the
	# "transition to the background" — every card casts the same gentle seat;
	# the rarity glow (Layer 0) then adds colour on top for rares/uncommons.
	var seat := Panel.new()
	seat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seat.anchor_left = 0.06; seat.anchor_right = 0.94
	seat.anchor_top = 0.04; seat.anchor_bottom = 0.965
	var seat_st := StyleBoxFlat.new()
	seat_st.bg_color = Color(0, 0, 0, 0.0)
	seat_st.set_corner_radius_all(22)
	seat_st.set_border_width_all(0)
	seat_st.shadow_color = Color(0, 0, 0, 0.55)
	seat_st.shadow_size = 18
	seat_st.shadow_offset = Vector2(0, 4)
	seat.add_theme_stylebox_override("panel", seat_st)
	root.add_child(seat)

	# ── Layer 0: rarity glow rim (behind everything) ─────────────────────
	# A rounded panel inset to the painted silhouette whose colored drop
	# shadow bleeds past the card edge → an unmistakable rarity halo. Rare
	# burns gold, uncommon glows cool blue, common barely whispers.
	var glow_size := 4
	match rarity:
		"rare":     glow_size = 16
		"uncommon": glow_size = 10
		"common":   glow_size = 4
		"starter":  glow_size = 2
	var glow := Panel.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_left = 0.035; glow.anchor_right = 0.965
	glow.anchor_top = 0.02; glow.anchor_bottom = 0.985
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(glow_col.r, glow_col.g, glow_col.b, 0.0)
	gs.set_corner_radius_all(20)
	gs.set_border_width_all(0)
	gs.shadow_color = Color(glow_col.r, glow_col.g, glow_col.b, 0.6)
	gs.shadow_size = glow_size
	glow.add_theme_stylebox_override("panel", gs)
	root.add_child(glow)

	# ── Layer 1: painted frame, tinted per rarity (Marvel-Snap read) ─────
	var v3_frame: Texture2D = GameTheme.get_card_frame(card_data)
	if v3_frame:
		_frame_tex = TextureRect.new()
		_frame_tex.texture = v3_frame
		_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fm := Color(1, 1, 1)
		match rarity:
			"rare":     fm = Color(1.18, 0.98, 0.58)  # hot gold
			"uncommon": fm = Color(0.74, 0.86, 1.10)  # cool steel-blue
			"common":   fm = Color(1.02, 0.96, 0.88)  # warm neutral
			"starter":  fm = Color(0.86, 0.84, 0.80)  # muted pewter
		if is_sp:
			fm = Color(fm.r * 0.90, fm.g * 0.84, fm.b * 1.16)  # violet bias
		_frame_tex.self_modulate = fm
		root.add_child(_frame_tex)

	# ── Layer 2: aged-parchment description page ─────────────────────────
	# Replaces v3's flat dark overlay. A warm tan page with a dark-brown
	# engraved border + grain — dark text on it reads as a real page, which
	# is the single biggest "this card is finished" upgrade.
	var page := Panel.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.anchor_left = 0.105; page.anchor_right = 0.895
	page.anchor_top = 0.620; page.anchor_bottom = 0.905
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(0.737, 0.651, 0.494, 0.98)  # #BCA67E aged parchment
	pst.set_corner_radius_all(7)
	pst.border_color = Color(0.286, 0.196, 0.094, 0.95)  # dark walnut edge
	pst.set_border_width_all(2)
	pst.shadow_color = Color(0, 0, 0, 0.45)
	pst.shadow_size = 4
	page.add_theme_stylebox_override("panel", pst)
	root.add_child(page)
	# Aged-parchment surface: a clipped overlay stack — paper-fiber grain →
	# warm sunlit top sheen → walnut gravity-shade at the bottom → darkened
	# corner vignette — turns the flat tan fill into a lit, weathered page.
	# All baked Gradient/Noise textures (no shaders → GL-compat safe). Added
	# before the description so the text always sits on top.
	var page_surf := Control.new()
	page_surf.clip_contents = true
	page_surf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_surf.anchor_left = 0.0; page_surf.anchor_right = 1.0
	page_surf.anchor_top = 0.0; page_surf.anchor_bottom = 1.0
	page_surf.offset_left = 2; page_surf.offset_right = -2
	page_surf.offset_top = 2; page_surf.offset_bottom = -2
	page.add_child(page_surf)
	if GameTheme.tex_card_grain:
		var pg := TextureRect.new()
		pg.texture = GameTheme.tex_card_grain
		pg.stretch_mode = TextureRect.STRETCH_TILE
		pg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pg.set_anchors_preset(Control.PRESET_FULL_RECT)
		pg.modulate = Color(0.33, 0.22, 0.10, 0.34)  # browner, stronger fiber
		pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page_surf.add_child(pg)
	if GameTheme.tex_card_top_light:
		var tl := TextureRect.new()
		tl.texture = GameTheme.tex_card_top_light
		tl.stretch_mode = TextureRect.STRETCH_SCALE
		tl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tl.set_anchors_preset(Control.PRESET_FULL_RECT)
		tl.modulate = Color(1.0, 0.95, 0.80, 0.30)  # warm sunlit top edge
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page_surf.add_child(tl)
	if GameTheme.tex_card_bottom_shade:
		var bs := TextureRect.new()
		bs.texture = GameTheme.tex_card_bottom_shade
		bs.stretch_mode = TextureRect.STRETCH_SCALE
		bs.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bs.set_anchors_preset(Control.PRESET_FULL_RECT)
		bs.modulate = Color(0.28, 0.18, 0.09, 0.34)  # walnut gravity-shade
		bs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page_surf.add_child(bs)
	if GameTheme.tex_card_vignette:
		var vg := TextureRect.new()
		vg.texture = GameTheme.tex_card_vignette
		vg.stretch_mode = TextureRect.STRETCH_SCALE
		vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vg.set_anchors_preset(Control.PRESET_FULL_RECT)
		vg.modulate = Color(0.22, 0.13, 0.06, 0.30)  # aged darkened edges
		vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page_surf.add_child(vg)

	# ── Layer 3: art with rounded top corners (reused v3 shader) ─────────
	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_clip := Control.new()
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.anchor_left = 0.020; art_clip.anchor_right = 0.980
		art_clip.anchor_top = 0.015; art_clip.anchor_bottom = 0.470
		root.add_child(art_clip)
		_art_rect = art_clip
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art_shader := Shader.new()
		art_shader.code = """
shader_type canvas_item;
uniform float radius_x : hint_range(0.0, 0.5) = 0.057;
uniform float radius_y : hint_range(0.0, 0.5) = 0.085;
void fragment() {
	vec2 uv = UV;
	float d_x = min(uv.x, 1.0 - uv.x);
	float d_y = uv.y;
	if (d_x < radius_x && d_y < radius_y) {
		vec2 offset = vec2(radius_x - d_x, radius_y - d_y);
		float ed = (offset.x * offset.x) / (radius_x * radius_x) +
				   (offset.y * offset.y) / (radius_y * radius_y);
		if (ed > 1.0) { COLOR.a = 0.0; }
	}
}
"""
		var art_mat := ShaderMaterial.new()
		art_mat.shader = art_shader
		art_mat.set_shader_parameter("radius_x", 0.090)
		art_mat.set_shader_parameter("radius_y", 0.135)
		art_tex.material = art_mat
		art_clip.add_child(art_tex)
	else:
		# No dedicated art → a deliberately-styled "empty plate" so it reads as
		# an intentional sealed frame, not a failed image load. Rounded top
		# corners (native StyleBox, matches the real-art window) + muted slate
		# fill + a ghosted gilt monogram of the card's initial.
		var ph := Panel.new()
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.anchor_left = 0.020; ph.anchor_right = 0.980
		ph.anchor_top = 0.015; ph.anchor_bottom = 0.470
		var phst := StyleBoxFlat.new()
		phst.bg_color = Color(0.169, 0.157, 0.192)
		phst.corner_radius_top_left = 16
		phst.corner_radius_top_right = 16
		phst.shadow_color = Color(0, 0, 0, 0.0)
		ph.add_theme_stylebox_override("panel", phst)
		root.add_child(ph)
		_art_rect = ph
		var ph_name := String(card_data.get("name", "")).strip_edges()
		var mono_ch := ph_name.substr(0, 1).to_upper() if ph_name.length() > 0 else "?"
		var mono := _make_styled_label(mono_ch, GameTheme.font_display, 40,
			Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.26))
		mono.add_theme_constant_override("outline_size", 0)
		_center_at_point(mono, Vector2(150, 96), Vector2(80, 80))
		ph.add_child(mono)

	var stat_font: Font = GameTheme.font_stat
	var display_font: Font = GameTheme.font_display

	# ── Layer 4: cost gem (top-left, reused) ─────────────────────────────
	# Full glossy orb (not simple_mode): the prototype renders only 8 cards,
	# so the perf reason for the flat recipe doesn't apply here — the full
	# stack (glow halo + drop shadow + rim + specular) makes each orb read as
	# a distinct 3D object sitting ON the card, so neighbouring orbs no longer
	# bleed into one another.
	var cost_orb := _make_stat_orb(GameTheme.COST_BLUE_GEM, 0.0, false)
	cost_orb.anchor_left = 0.0; cost_orb.anchor_right = 0.0
	cost_orb.anchor_top = 0.0; cost_orb.anchor_bottom = 0.0
	cost_orb.offset_left = -9; cost_orb.offset_right = 47
	cost_orb.offset_top = -9; cost_orb.offset_bottom = 47
	root.add_child(cost_orb)
	_cost_label = _make_styled_label(
		"" if bake_strip_stats else str(card_data.get("cost", 0)),
		stat_font, 14, Color(0.996, 0.941, 0.800))
	_cost_label.add_theme_constant_override("outline_size", 4)
	_cost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cost_label.offset_top = ORB_NUMERAL_Y_OFFSET
	_cost_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_orb.add_child(_cost_label)

	# ── Layer 4b: rarity gem (top-right) — only uncommon / rare ──────────
	if rarity == "uncommon" or rarity == "rare":
		# Rare's rarity_color is a lemon-gold that read cheap on the faceted
		# gem; push it to a warm amber/topaz. Uncommon keeps its sapphire.
		var gem_col: Color = glow_col
		if rarity == "rare":
			gem_col = Color(0.949, 0.616, 0.137)
		var gem := _make_stat_orb(gem_col, 0.0, false)
		gem.anchor_left = 1.0; gem.anchor_right = 1.0
		gem.anchor_top = 0.0; gem.anchor_bottom = 0.0
		gem.offset_left = -38; gem.offset_right = 6
		gem.offset_top = -6; gem.offset_bottom = 38
		root.add_child(gem)

	# ── Layer 5: name in the painted banner (nudged to true center) ──────
	# Spells get a deep-aubergine ink instead of the mid-violet tribe colour.
	# Mid-violet (0.38,0.18,0.55) on the cream banner was the weakest text on
	# the card; this is the same hue family darkened to ~5.5:1 contrast so the
	# spell name reads as crisply as the dark-brown creature names.
	var name_col: Color = GameTheme.get_name_color(card_data)
	if is_sp:
		name_col = Color(0.212, 0.063, 0.290)
	_name_label = _make_styled_label(card_data.get("name", ""), display_font,
		13, name_col)
	_name_label.add_theme_constant_override("outline_size", 0)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.30))
	_name_label.add_theme_constant_override("shadow_offset_x", 0)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_center_at_point(_name_label, Vector2(150, 213), SIZE_NAME)
	root.add_child(_name_label)

	# ── Layer 6: keyword treatment (A/B via kw_variant) ──────────────────
	# `medallions` = every keyword that has an icon. `combat_meds` drops floop,
	# which has its own battlefield indicator and is always spelled "Floop:" in
	# the description, so it's pure redundancy in an icon row.
	var medallions: Array = []
	var combat_meds: Array = []
	for k in card_data.get("keywords", []):
		var k_str := String(k)
		var icon_tex: Texture2D = GameTheme.get_keyword_icon(k_str)
		if icon_tex == null:
			continue
		medallions.append(icon_tex)
		if k_str != "floop":
			combat_meds.append(icon_tex)
		if medallions.size() >= 5:
			break
	if not is_sp:
		match kw_variant:
			1:
				pass  # DROP — keywords already named (colorized) in description.
			2:
				_kw_shelf_engraved(root, combat_meds)
			3:
				_kw_stamps_on_art(root, combat_meds)
			4:
				_kw_orbs_rail(root, combat_meds)
			5:
				_kw_orbs_rail(root, combat_meds, 48.0)
			_:
				_kw_shelf_pill(root, medallions)

	# ── Layer 7: description, vertically centered on the parchment page ──
	var center_box := CenterContainer.new()
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_box.anchor_left = 0.0; center_box.anchor_right = 1.0
	center_box.anchor_top = 0.0; center_box.anchor_bottom = 1.0
	center_box.offset_left = 7; center_box.offset_right = -7
	center_box.offset_top = 5; center_box.offset_bottom = -5
	page.add_child(center_box)

	var desc_rt := RichTextLabel.new()
	desc_rt.bbcode_enabled = true
	desc_rt.fit_content = true
	desc_rt.scroll_active = false
	desc_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_rt.custom_minimum_size = Vector2(150, 0)
	var desc_font: Font = GameTheme.font_body
	var desc_bold_font: Font = GameTheme.font_body_bold
	if desc_font:
		desc_rt.add_theme_font_override("normal_font", desc_font)
		desc_rt.add_theme_font_override("bold_font",
			desc_bold_font if desc_bold_font else desc_font)
	# Auto-shrink long descriptions so 4-5 line rares stay inside the page.
	var raw_desc: String = card_data.get("desc", "")
	var dsz := 11
	if raw_desc.length() > 105:
		dsz = 9
	elif raw_desc.length() > 72:
		dsz = 10
	desc_rt.add_theme_font_size_override("normal_font_size", dsz)
	desc_rt.add_theme_font_size_override("bold_font_size", dsz)
	# DARK ink on the light parchment page (inverted from v3's cream-on-dark).
	desc_rt.add_theme_color_override("default_color", Color(0.176, 0.118, 0.063))
	desc_rt.text = "[center]%s[/center]" % KeywordEffects.colorize_keywords(raw_desc)
	center_box.add_child(desc_rt)

	# ── Layer 8: creature ATK/HP orbs OR spell footer cartouche ──────────
	if is_creature():
		var atk_orb := _make_stat_orb(GameTheme.ATK_GOLD_SHIELD, 0.0, false)
		atk_orb.anchor_left = 0.0; atk_orb.anchor_right = 0.0
		atk_orb.anchor_top = 1.0; atk_orb.anchor_bottom = 1.0
		atk_orb.offset_left = -9; atk_orb.offset_right = 47
		atk_orb.offset_top = -47; atk_orb.offset_bottom = 9
		root.add_child(atk_orb)
		_atk_label = _make_styled_label(
			"" if bake_strip_stats else str(current_atk), stat_font, 14,
			Color(1.000, 0.957, 0.839))
		_atk_label.add_theme_constant_override("outline_size", 4)
		_atk_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_atk_label.offset_top = ORB_NUMERAL_Y_OFFSET
		_atk_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
		_atk_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		atk_orb.add_child(_atk_label)

		var hp_orb := _make_stat_orb(GameTheme.HEALTH_RED_DROP, 0.0, false)
		hp_orb.anchor_left = 1.0; hp_orb.anchor_right = 1.0
		hp_orb.anchor_top = 1.0; hp_orb.anchor_bottom = 1.0
		hp_orb.offset_left = -47; hp_orb.offset_right = 9
		hp_orb.offset_top = -47; hp_orb.offset_bottom = 9
		root.add_child(hp_orb)
		_hp_label = _make_styled_label(
			"" if bake_strip_stats else str(current_hp), stat_font, 14,
			Color(1.000, 0.941, 0.898))
		_hp_label.add_theme_constant_override("outline_size", 4)
		_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hp_label.offset_top = ORB_NUMERAL_Y_OFFSET
		_hp_label.offset_bottom = ORB_NUMERAL_Y_OFFSET
		_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_orb.add_child(_hp_label)
	else:
		var footer_text := "INSTANT"
		var kws: Array = card_data.get("keywords", [])
		if CardDB.is_curse(String(card_data.get("id", ""))):
			footer_text = "CURSE"
		else:
			match String(card_data.get("targeting", "none")):
				"enemy_creature":    footer_text = "TARGET ENEMY"
				"friendly_creature": footer_text = "TARGET ALLY"
				"any_creature":      footer_text = "ANY CREATURE"
				"any":               footer_text = "ANY TARGET"
				_:
					if "exhaust" in kws:
						footer_text = "EXHAUST"
					elif "retain" in kws:
						footer_text = "RETAIN"
		var footer := Panel.new()
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_center_at_point(footer, Vector2(150, 374), Vector2(150, 28))
		var fst := StyleBoxFlat.new()
		fst.bg_color = Color(0.110, 0.075, 0.110, 0.92)  # arcane near-black
		fst.set_corner_radius_all(13)
		fst.border_color = Color(0.65, 0.52, 0.85, 0.85)  # violet trim
		fst.set_border_width_all(1)
		fst.shadow_color = Color(0.4, 0.2, 0.6, 0.35)
		fst.shadow_size = 4
		footer.add_theme_stylebox_override("panel", fst)
		root.add_child(footer)
		var ftl := _make_styled_label(footer_text, display_font, 9,
			Color(0.92, 0.86, 1.0))
		ftl.add_theme_constant_override("outline_size", 2)
		_center_at_point(ftl, Vector2(150, 374), Vector2(140, 24))
		root.add_child(ftl)
		# flanking arcane gems
		for sx in [110.0, 190.0]:
			var fg := _make_stat_orb(Color(0.55, 0.35, 0.75), 0.0, true)
			_center_at_point(fg, Vector2(sx, 374), Vector2(14, 14))
			root.add_child(fg)


# Keyword-treatment variants for the redesign prototype (selected by
# kw_variant). All three sit in the banner→parchment gap or on the art.

# Variant 0 (default): bright-gilt glyphs inlaid in a rounded dark pill.
func _kw_shelf_pill(root: Control, meds: Array) -> void:
	if meds.is_empty():
		return
	var shelf_w: float = float(meds.size()) * 27.0 + 16.0
	var shelf := Panel.new()
	shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_at_point(shelf, Vector2(150, 238), Vector2(shelf_w, 25))
	var shst := StyleBoxFlat.new()
	shst.bg_color = Color(0.070, 0.054, 0.042, 0.92)
	shst.set_corner_radius_all(12)
	shst.border_color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.75)
	shst.set_border_width_all(1)
	shst.shadow_color = Color(0, 0, 0, 0.40)
	shst.shadow_size = 3
	shelf.add_theme_stylebox_override("panel", shst)
	root.add_child(shelf)
	var kw_strip := HBoxContainer.new()
	kw_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kw_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	kw_strip.add_theme_constant_override("separation", 9)
	_center_at_point(kw_strip, Vector2(150, 238), Vector2(shelf_w, 22))
	root.add_child(kw_strip)
	for icon_tex in meds:
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(17, 17)
		ic.modulate = GameTheme.GILT_BRIGHT
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kw_strip.add_child(ic)


# Variant 2: a recessed engraved plaque — rectangular, dark inner edge (no
# bright ring), antique-gold glyphs. Reads as carved INTO the frame, not a
# button stuck ON it.
func _kw_shelf_engraved(root: Control, meds: Array) -> void:
	if meds.is_empty():
		return
	var w: float = float(meds.size()) * 26.0 + 14.0
	var slot := Panel.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_at_point(slot, Vector2(150, 238), Vector2(w, 21))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.055, 0.043, 0.034, 0.80)
	st.set_corner_radius_all(4)
	st.border_color = Color(0.015, 0.010, 0.008, 0.90)  # dark top lip → recessed
	st.border_width_top = 2
	st.border_width_left = 1
	st.border_width_right = 1
	st.border_width_bottom = 0
	slot.add_theme_stylebox_override("panel", st)
	root.add_child(slot)
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 9)
	_center_at_point(strip, Vector2(150, 238), Vector2(w, 19))
	root.add_child(strip)
	for icon_tex in meds:
		var ic := TextureRect.new()
		ic.texture = icon_tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(15, 15)
		ic.modulate = GameTheme.GILT  # antique, not bright
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(ic)


# Variant 3: small gold "set-symbol" coins stamped into the art's lower-left,
# away from the text entirely. Each coin is a dark disc (guaranteed contrast on
# any art) with a gilt glyph.
func _kw_stamps_on_art(root: Control, meds: Array) -> void:
	var n := meds.size()
	if n == 0:
		return
	for i in range(n):
		var px := 24.0 + float(i) * 25.0
		var coin := Panel.new()
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_center_at_point(coin, Vector2(px, 175), Vector2(22, 22))
		var cst := StyleBoxFlat.new()
		cst.bg_color = Color(0.050, 0.040, 0.030, 0.82)
		cst.set_corner_radius_all(11)
		cst.border_color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.70)
		cst.set_border_width_all(1)
		cst.shadow_color = Color(0, 0, 0, 0.55)
		cst.shadow_size = 2
		coin.add_theme_stylebox_override("panel", cst)
		root.add_child(coin)
		var ic := TextureRect.new()
		ic.texture = meds[i]
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 3; ic.offset_right = -3
		ic.offset_top = 3; ic.offset_bottom = -3
		ic.modulate = GameTheme.GILT_BRIGHT
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.add_child(ic)


func _kw_orbs_rail(root: Control, meds: Array, box: float = 40.0) -> void:
	# Keyword affordance as a vertical rail of glossy orbs on the card's right
	# edge, growing downward from just below the rarity gem. Unlike a text shelf
	# or flat stamps, big solid spheres stay readable at the 0.6x battlefield
	# scale — the same reason the four stat orbs survive the shrink while the
	# description text turns to mush. Arcane-violet so they never read as a stat
	# orb (cost=blue, atk=gold, hp=red, rarity=amber). The caller passes
	# combat_meds (floop already dropped — it owns the floop border + indicator
	# on the field), capped at 3 so the rail clears the bottom ATK/HP orbs.
	# `box` is the orb diameter: 40 = subordinate rail, 56 = stat-orb parity
	# (most legible at field scale). Top-anchored so a bigger box never collides
	# with the rarity gem (which ends at ~y=38) — the rail just grows downward.
	var n: int = min(meds.size(), 3)
	if n == 0:
		return
	var pitch: float = box + 8.0
	const TOP0 := 46.0        # just below the rarity gem
	var inset: float = box * 0.225   # ~9 px at box=40, scales with the orb
	for i in range(n):
		# Same deep-violet, low-gloss GemOrb as the battlefield token's keyword
		# orbs (_build_compact_layout) so hand and field read consistently — not
		# the bright glossy SphereOrb from _make_stat_orb.
		var orb := GemOrb.new()
		orb.shape = "circle"
		orb.style = "smooth"
		orb.fill_color = Color(0.247, 0.153, 0.376)  # deep arcane violet
		orb.gloss = 0.42  # calmer than stat orbs so the gilt glyph reads
		orb.anchor_left = 1.0; orb.anchor_right = 1.0
		orb.anchor_top = 0.0; orb.anchor_bottom = 0.0
		orb.offset_right = -3
		orb.offset_left = -3 - box
		orb.offset_top = TOP0 + float(i) * pitch
		orb.offset_bottom = orb.offset_top + box
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(orb)
		var glyph := TextureRect.new()
		glyph.texture = meds[i]
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.offset_left = inset; glyph.offset_right = -inset
		glyph.offset_top = inset; glyph.offset_bottom = -inset
		glyph.modulate = GameTheme.GILT_BRIGHT
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orb.add_child(glyph)


# ═══════════════════════════════════════════
#  V4 LAYOUT — procedural frame, no PNG dependency.
#  Per docs/prompts/card_design_doc.md §5/§15:
#    • 225×300 card (aspect 0.75, matches Hearthstone/MtG conventions)
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
	var is_curse: bool = (CardDB.is_curse(String(card_data.get("id", "")))
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
	# 225×300 rect still reads as "rounded rectangle" / Slack-message
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
	# Painted brush-stroke edge — noise-perturbed border darkening on top of
	# the smooth vignette. Smooth vignette alone reads "digital rectangle";
	# this layer turns the dark-edge boundary into a brush-irregular ink wash
	# so the card body stops reading as flat geometry and starts reading as
	# painted-on-parchment. One baked ImageTexture, modulate-only.
	if not static_display and GameTheme.tex_card_brush_edge:
		var brush := TextureRect.new()
		brush.texture = GameTheme.tex_card_brush_edge
		brush.set_anchors_preset(Control.PRESET_FULL_RECT)
		brush.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		brush.stretch_mode = TextureRect.STRETCH_SCALE
		brush.modulate = Color(1, 1, 1, 0.55)
		brush.mouse_filter = Control.MOUSE_FILTER_IGNORE
		depth_layer.add_child(brush)
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
	# Tribe accent: the engraved top-light hue shifts to the card's tribe
	# color (soldier gold / undead red / fae cyan / etc.) so faction reads
	# at a glance. The walnut + black shadow layers keep the 3D relief.
	_name_label.add_theme_color_override("font_color",
		GameTheme.get_name_color(card_data))
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

		# Creature subtype pill — KEYWORD_GOLD text on a dark pill so the
		# subtype reads against any card body colour underneath (the bottom
		# strip varies from dark walnut to warm wash by rarity). Narrower
		# horizontal anchor than the spell pill so the ATK and HP orbs at
		# the corners stay clear.
		# Anchor band 0.910–0.985 centers the pill at ~y=284 on a 300 px
		# card — same vertical centre as the ATK/HP orb visual midpoints
		# (orbs span y=217–261, centre y=239). Earlier 0.890–0.960 floated
		# the pill ~6 px above the orbs, which read as misaligned.
		_type_plate = _make_type_pill(
			_creature_type_text(),
			GameTheme.KEYWORD_GOLD,
			0.910, 0.985, 0.18, 0.82)
		root.add_child(_type_plate)
	else:
		# Spell pill — same dark pill format with brighter purple text so
		# the gold = creature, purple = spell hue distinction stays clear.
		# Wider anchor than creatures since no stat orbs are in the way.
		var tgt_raw: String = _spell_target_label()
		var spell_text := "SPELL"
		if tgt_raw != "":
			spell_text = "SPELL · %s" % tgt_raw
		_type_plate = _make_type_pill(
			spell_text,
			Color(0.88, 0.70, 1.00),
			0.870, 0.945, 0.04, 0.96)
		root.add_child(_type_plate)

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


# ═══════════════════════════════════════════
#  V5 LAYOUT — "overlap and paint the seams."
#  Replaces v4's stack of Panels (banner + art-frame + well + trim + halo
#  + 6 depth overlays + ornamental divider + type pill) with one CardCanvas
#  drawing the entire body + tapered ribbon banner + scroll divider in a
#  single _draw(). Stat orbs straddle the art/description seam (also fixes
#  the UX bug where ATK/HP sat below the hand-peek line at 0.8 scale).
#
#  Per the council research (Slay the Spire / Across the Obelisk / Roguebook):
#  cells are fine — but the seams between cells must be PAINTED FEATURES
#  (gold scroll, tapered ribbon, fishtail banner) and at least one element
#  must OVERLAP a seam (stat orb half-on-art half-on-description). That's
#  what kills the spreadsheet read.
# ═══════════════════════════════════════════

func _build_full_layout_v5() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var rarity: String = String(card_data.get("rarity", "common"))

	# ── 1. Frame texture ──
	var frame_tex: Texture2D = GameTheme.get_card_frame(card_data)
	if frame_tex:
		var frame := TextureRect.new()
		frame.texture = frame_tex
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(frame)

	# ── 2. Art window ──
	var art_clip := Control.new()
	art_clip.anchor_left = 0.165; art_clip.anchor_right = 0.835
	art_clip.anchor_top = 0.21; art_clip.anchor_bottom = 0.60
	art_clip.clip_contents = true
	art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(art_clip)
	_art_rect = art_clip

	var card_art: Texture2D = _find_card_art()
	if card_art == null:
		var placeholder_path := "res://assets/creatures/kindling_alt.png"
		if ResourceLoader.exists(placeholder_path):
			card_art = load(placeholder_path)
	if card_art:
		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)

	# ── 3. Name label ──
	_name_label = Label.new()
	var name_text: String = card_data.get("name", "")
	_name_label.text = name_text
	if GameTheme.font_display:
		_name_label.add_theme_font_override("font", GameTheme.font_display)
	var name_size := 12
	if name_text.length() > 16:
		name_size = 11
	if name_text.length() > 20:
		name_size = 10
	if name_text.length() > 24:
		name_size = 9
	_name_label.add_theme_font_size_override("font_size", name_size)
	# Tribe accent wins over the old rarity override — rarity is still readable
	# from the frame trim, but tribe was previously not encoded anywhere.
	_name_label.add_theme_color_override("font_color",
		GameTheme.get_name_color(card_data))
	_name_label.add_theme_color_override("font_outline_color",
		Color(0, 0, 0, 0.85))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.anchor_left = 0.18; _name_label.anchor_right = 0.82
	_name_label.anchor_top = 0.13; _name_label.anchor_bottom = 0.20
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_label)

	# ── 4. Description text ──
	var desc_rt := RichTextLabel.new()
	desc_rt.bbcode_enabled = true
	desc_rt.fit_content = false
	desc_rt.scroll_active = false
	desc_rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_rt.anchor_left = 0.18; desc_rt.anchor_right = 0.82
	desc_rt.anchor_top = 0.63;  desc_rt.anchor_bottom = 0.86
	desc_rt.offset_top = 2
	desc_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_body:
		desc_rt.add_theme_font_override("normal_font", GameTheme.font_body)
		desc_rt.add_theme_font_override("bold_font",
			GameTheme.font_body_bold if GameTheme.font_body_bold else GameTheme.font_body)
	var raw_desc: String = card_data.get("desc", "")
	var desc_size := 10
	if raw_desc.length() > 95:
		desc_size = 9
	desc_rt.add_theme_font_size_override("normal_font_size", desc_size)
	desc_rt.add_theme_font_size_override("bold_font_size", desc_size)
	desc_rt.add_theme_color_override("default_color", GameTheme.PARCHMENT_TEXT)
	desc_rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.30))
	desc_rt.add_theme_constant_override("outline_size", 2)
	var colorized: String = KeywordEffects.colorize_keywords(raw_desc) \
		.replace("#c89e4a", "#9a1a1a")
	desc_rt.text = "[center]%s[/center]" % colorized
	root.add_child(desc_rt)
	_desc_label = Label.new()
	_desc_label.visible = false
	_desc_label.text = raw_desc
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_desc_label)

	# ── 5. Cost orb (top-left) ──
	var cost_pulse: float = 0.0 if static_display else 0.18
	var cost_orb := _make_stat_orb(GameTheme.COST_BLUE_GEM, cost_pulse,
		static_display)
	cost_orb.anchor_left = 0.0; cost_orb.anchor_right = 0.0
	cost_orb.anchor_top = 0.0;  cost_orb.anchor_bottom = 0.0
	cost_orb.offset_left = -9;  cost_orb.offset_right = 35
	cost_orb.offset_top = -9;   cost_orb.offset_bottom = 35
	_cost_badge = cost_orb
	root.add_child(cost_orb)
	_cost_label = _make_stat_number(
		"" if bake_strip_stats else str(card_data.get("cost", 0)),
		Color(1, 0.98, 0.90), 0, Color(0.30, 0.65, 1.00, 0.85))
	cost_orb.add_child(_cost_label)

	# ── 6. ATK / HP orbs (bottom corners, creatures only) ──
	if is_creature():
		var atk := _make_stat_orb(GameTheme.ATK_GOLD_SHIELD, 0.0,
			static_display)
		atk.anchor_left = 0.0; atk.anchor_right = 0.0
		atk.anchor_top = 1.0;  atk.anchor_bottom = 1.0
		atk.offset_left = -9;  atk.offset_right = 35
		atk.offset_top = -35;  atk.offset_bottom = 9
		root.add_child(atk)
		_atk_base_color = Color(0.08, 0.05, 0.02)
		_atk_label = _make_stat_number(
			"" if bake_strip_stats else str(current_atk),
			_atk_base_color, 0, Color(1.00, 0.78, 0.20, 0.90))
		atk.add_child(_atk_label)
		_atk_badge = null

		var hp_pulse: float = 0.0 if static_display else 0.10
		var hp := _make_stat_orb(GameTheme.HEALTH_RED_DROP, hp_pulse,
			static_display)
		hp.anchor_left = 1.0; hp.anchor_right = 1.0
		hp.anchor_top = 1.0;  hp.anchor_bottom = 1.0
		hp.offset_left = -35; hp.offset_right = 9
		hp.offset_top = -35;  hp.offset_bottom = 9
		root.add_child(hp)
		_hp_base_color = Color(1, 0.97, 0.92)
		_hp_label = _make_stat_number(
			"" if bake_strip_stats else str(current_hp),
			_hp_base_color, 0, Color(1.00, 0.30, 0.20, 0.90))
		hp.add_child(_hp_label)
		_hp_badge = null

	# ── 7. Floop indicator (hidden by default) ──
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
	_floop_indicator.anchor_left = 0.30; _floop_indicator.anchor_right = 0.70
	_floop_indicator.anchor_top = 0.585; _floop_indicator.anchor_bottom = 0.640
	_floop_indicator.visible = false
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_floop_indicator)

	# Legacy stubs — external code reads these refs.
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
	# Apply ORB_NUMERAL_Y_OFFSET unconditionally so every _make_stat_number
	# caller (baked overlay, v4 layout, v5 layout) gets the same optical-
	# centering nudge. `vertical_offset` callers add on top of that for any
	# additional asymmetric overlay needs.
	var total_y_offset := ORB_NUMERAL_Y_OFFSET + vertical_offset
	lbl.offset_top = total_y_offset
	lbl.offset_bottom = total_y_offset
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


# Map of name/id keywords → subtype label. First match wins; later entries
# are more specific overrides for the earlier generic buckets. Used by
# _creature_type_text when card_data has no explicit "subtype" field.
# Heuristic only — letting designers refine via card_data.subtype later
# without changing this table.
const _SUBTYPE_HINTS: Array = [
	["dragon", "DRAGON"], ["drake", "DRAGON"], ["wyrm", "DRAGON"],
	["hatchling", "DRAGON"],
	["vampire", "VAMPIRE"],  # avoid "blood" — matches Bloodhound (BEAST)
	["demon", "DEMON"], ["imp", "DEMON"], ["devil", "DEMON"],
	["fiend", "DEMON"], ["infernal", "DEMON"], ["chaos", "DEMON"],
	["ghost", "SPIRIT"], ["spirit", "SPIRIT"], ["wraith", "SPIRIT"],
	["shade", "SPIRIT"], ["specter", "SPIRIT"], ["banshee", "SPIRIT"],
	["vengeful", "SPIRIT"], ["phantom", "SPIRIT"],
	["skeleton", "UNDEAD"], ["lich", "UNDEAD"], ["necro", "UNDEAD"],
	["bone", "UNDEAD"], ["corpse", "UNDEAD"], ["grave", "UNDEAD"],
	["warden", "UNDEAD"], ["risen", "UNDEAD"],
	["archmage", "MAGE"], ["mage", "MAGE"], ["wizard", "MAGE"],
	["witch", "MAGE"], ["warlock", "MAGE"], ["sorcer", "MAGE"],
	["acolyte", "CULTIST"], ["cultist", "CULTIST"], ["zealot", "CULTIST"],
	["fanatic", "CULTIST"],
	["titan", "GIANT"], ["giant", "GIANT"],
	["golem", "CONSTRUCT"], ["siege", "CONSTRUCT"], ["bastion", "CONSTRUCT"],
	["iron", "CONSTRUCT"], ["stone", "CONSTRUCT"],
	["paladin", "KNIGHT"], ["doom", "KNIGHT"], ["knight", "KNIGHT"],
	["royal", "KNIGHT"], ["guard", "KNIGHT"], ["veteran", "KNIGHT"],
	["champion", "KNIGHT"], ["templar", "KNIGHT"],
	["assassin", "ROGUE"], ["bandit", "ROGUE"], ["thief", "ROGUE"],
	["scout", "ROGUE"], ["shadow", "ROGUE"],
	["ranger", "ARCHER"], ["archer", "ARCHER"], ["sharpshoot", "ARCHER"],
	["berserker", "MARAUDER"], ["orc", "MARAUDER"], ["goblin", "MARAUDER"],
	["ratling", "MARAUDER"], ["barbarian", "MARAUDER"],
	["wolf", "BEAST"], ["hound", "BEAST"], ["hydra", "BEAST"],
	["beast", "BEAST"], ["thorn", "BEAST"], ["spore", "BEAST"],
	["bog", "BEAST"], ["lurker", "BEAST"],
	["harpy", "HARPY"], ["matron", "HARPY"],
	["doppelganger", "MIMIC"], ["mirror", "MIMIC"], ["puppet", "MIMIC"],
	["reflection", "MIMIC"],
	["sprite", "FAE"], ["fae", "FAE"], ["pixie", "FAE"],
]


func _make_type_pill(text: String, text_color: Color,
		top_anchor: float, bottom_anchor: float,
		left_anchor: float, right_anchor: float) -> CenterContainer:
	# StS / Hearthstone / MtG convention: type tags sit on a small dark
	# "pill" so their contrast is independent of the card body colour.
	# Our previous text-only tag lost contrast against the variable bottom
	# strip (dark walnut behind some keywords, lighter where the parchment
	# well's drop shadow lifts; rare cards have a warm wash; uncommons cool).
	# The pill puts the same neutral dark backdrop behind every card type
	# so the gold/purple text always reads.
	#
	# Layout: CenterContainer anchored to the bottom strip wraps a tight
	# PanelContainer; the panel auto-sizes to the Label inside via the
	# StyleBoxFlat's content_margin. Result: a pill that grows with the
	# text and stays centered, regardless of how long the subtype is.
	var wrap := CenterContainer.new()
	wrap.anchor_left = left_anchor
	wrap.anchor_right = right_anchor
	wrap.anchor_top = top_anchor
	wrap.anchor_bottom = bottom_anchor
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := StyleBoxFlat.new()
	# Dark walnut at 92% alpha — opaque enough to override card body hue,
	# the small transparency lets the body's grain show through faintly so
	# the pill still feels painted on, not pasted on.
	pill_style.bg_color = Color(0.055, 0.035, 0.020, 0.92)
	# Warm gold trim ties the pill to the card's gilt accents; subtle so
	# the dark fill is what the eye reads as contrast.
	pill_style.border_color = Color(0.55, 0.42, 0.18, 0.85)
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(7)
	pill_style.content_margin_left = 7
	pill_style.content_margin_right = 7
	pill_style.content_margin_top = 1
	pill_style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", pill_style)
	wrap.add_child(pill)

	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", text_color)
	# Thinner outline than before — the dark pill provides the bulk of the
	# contrast, so the outline's only job is crisping AA-edges. A heavy
	# outline + pill bg would crush the glyphs into mush.
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)
	return wrap


func _creature_type_text() -> String:
	# Subtype shown on the creature bottom badge. Designers can set
	# card_data.subtype explicitly; otherwise we infer from name + id
	# keywords via _SUBTYPE_HINTS. Falls back to "CREATURE" so unknown
	# entries still get a label.
	var st: String = String(card_data.get("subtype", ""))
	if st != "":
		return st.to_upper()
	var name_lower: String = String(card_data.get("name", "")).to_lower()
	var id_lower: String = String(card_data.get("id", "")).to_lower()
	var search: String = name_lower + " " + id_lower
	for entry in _SUBTYPE_HINTS:
		var needle: String = entry[0]
		if needle in search:
			return entry[1]
	return "CREATURE"


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
	# Same optical-centering nudge as the hand orbs — see ORB_NUMERAL_Y_OFFSET.
	# Field orbs are smaller (30 px vs 56 px), but the cap-high-in-line-box
	# phenomenon is font-metric driven so it applies at every size; the
	# painted shadow ratio is similar too. One value works for both.
	lbl.offset_top = ORB_NUMERAL_Y_OFFSET
	lbl.offset_bottom = ORB_NUMERAL_Y_OFFSET
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
		var display_atk = effective_atk()
		if _displayed_effective_atk != -999 and display_atk != _displayed_effective_atk:
			_spawn_atk_change_popup(display_atk - _displayed_effective_atk)
		_displayed_effective_atk = display_atk
		_atk_label.text = str(display_atk)
		if display_atk > card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.ATK_BUFFED)
		elif display_atk < card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
		else:
			_atk_label.add_theme_color_override("font_color", _atk_base_color)


func update_floop_display() -> void:
	# Three visible states:
	#   - toggled (will_floop): solid cyan badge + cyan border + cool art tint
	#   - available (on battlefield, has_floop, not yet used): "CLICK · FLOOP"
	#     pulsing in cyan with a cyan border so the player can SEE the
	#     affordance from across the room. Previously this was dim brown text
	#     reading "click: floop" — players reported they couldn't tell the
	#     mechanic existed.
	#   - hidden (anything else): pulse killed, label off, default border.
	var toggled := will_floop
	var available := is_on_battlefield and has_floop() and not is_opponent and not toggled
	if _floop_indicator:
		if toggled:
			_floop_indicator.text = "FLOOP"
			_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
			_floop_indicator.modulate = Color(1, 1, 1, 1)
			_floop_indicator.visible = true
			_stop_floop_pulse()
		elif available:
			_floop_indicator.text = "CLICK · FLOOP"
			_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
			_floop_indicator.visible = true
			_start_floop_pulse()
		else:
			_floop_indicator.visible = false
			_floop_indicator.modulate = Color(1, 1, 1, 1)
			_stop_floop_pulse()
	# Type plate occupies the same bottom strip as FLOOP — hide one when
	# the other is showing so they don't overlap into mush.
	if _type_plate:
		_type_plate.visible = (_floop_indicator == null
			or not _floop_indicator.visible)
	if toggled:
		_set_border_color(GameTheme.FLOOP_BLUE)
		if _art_rect:
			_art_rect.modulate = Color(0.6, 0.7, 1.0, 0.9)
	elif available:
		_set_border_color(Color(GameTheme.FLOOP_BLUE.r, GameTheme.FLOOP_BLUE.g, GameTheme.FLOOP_BLUE.b, 0.85))
		if _art_rect:
			_art_rect.modulate = Color.WHITE
	else:
		_set_border_color(_get_default_frame_tint())
		if _art_rect:
			_art_rect.modulate = Color.WHITE


func _start_floop_pulse() -> void:
	# Gentle alpha oscillation on the FLOOP label so it reads as "interactable"
	# from the corner of the eye. Kept slow (1.4s full cycle) and shallow
	# (alpha 0.55-1.0) so it never crosses into "distracting" territory.
	if _floop_indicator == null:
		return
	if _floop_pulse_tween and _floop_pulse_tween.is_valid():
		return
	_floop_pulse_tween = create_tween()
	_floop_pulse_tween.set_loops()
	_floop_pulse_tween.tween_property(_floop_indicator, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
	_floop_pulse_tween.tween_property(_floop_indicator, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _stop_floop_pulse() -> void:
	if _floop_pulse_tween and _floop_pulse_tween.is_valid():
		_floop_pulse_tween.kill()
	_floop_pulse_tween = null
	if _floop_indicator:
		_floop_indicator.modulate.a = 1.0


func toggle_floop() -> void:
	if not has_floop():
		return
	will_floop = not will_floop
	update_floop_display()


# ═══════════════════════════════════════════
#  DAMAGE
# ═══════════════════════════════════════════

func take_damage(amount: int) -> void:
	# Shield: absorb the entire first hit, then pop the shield.
	if state.has_shield:
		state.has_shield = false
		_spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
		update_stat_display()
		_flash_hit()
		return
	var original := amount
	if has_keyword("armored"):
		# Fortress Stone relic makes the player's own armored creatures block 2
		# instead of 1. Enemy armored stays at 1 (the relic is a player buff).
		# Previously the reduction was hardcoded to 1, so Fortress Stone was a
		# dead pickup that did nothing — a wasted shop slot / reward choice.
		var reduction := 1
		if not is_opponent and RunState.has_relic("fortress_stone"):
			reduction = 2
		amount = maxi(1, amount - reduction)
		var blocked: int = original - amount
		if blocked > 0:
			_spawn_keyword_chip("BLOCKED %d" % blocked, Color(0.55, 0.78, 1.0))
	if card_data.get("extra_damage", 0) > 0:
		amount += card_data.extra_damage
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
		_spawn_keyword_chip("LAST STAND", Color(1.0, 0.85, 0.20))
		_play_last_stand_flare()
	update_stat_display()
	_spawn_damage_number(amount)
	if amount > 0:
		damaged.emit(amount)
	if current_hp <= 0:
		try_die()
	else:
		_flash_hit()


func take_damage_bypass_armor(amount: int) -> void:
	# Bypasses Armored, but Shield still absorbs the whole hit and pops.
	if state.has_shield:
		state.has_shield = false
		_spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
		update_stat_display()
		_flash_hit()
		return
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
		_spawn_keyword_chip("LAST STAND", Color(1.0, 0.85, 0.20))
		_play_last_stand_flare()
	update_stat_display()
	_spawn_damage_number(amount)
	if amount > 0:
		damaged.emit(amount)
	if current_hp <= 0:
		try_die()
	else:
		_flash_hit()


# Public death entry point. Gives rescue listeners (Phantom Veil, Reborn) a
# chance to set current_hp back > 0 before _die() runs. Call this anywhere
# you've directly set current_hp <= 0 without going through take_damage —
# e.g. poison kills (Combat.gd:1455/1567).
func try_die() -> void:
	will_die.emit()
	if current_hp > 0:
		update_stat_display()
		return
	_die()


func _spawn_keyword_chip(text: String, color: Color) -> void:
	# Floats a labeled chip above the card so hidden keyword math (Armored
	# blocking, Last Stand triggering, Piercing carrying) reads on-screen.
	if static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	var anchor := global_position + Vector2(size.x * scale.x * 0.5, size.y * scale.y * 0.10)
	vfx.spawn_floating_number(anchor, text, color, false)


# ─────────────────────────────────────────────────────────────────────────
#  Combat juice — damage numbers, hit flash, death flourish, heal pulse
# ─────────────────────────────────────────────────────────────────────────

func _combat_vfx_target() -> Node:
	# The Combat scene exposes spawn_floating_number(); other scenes (gallery,
	# bake viewport) don't, so we no-op there.
	var tree := get_tree()
	if tree == null:
		return null
	var scn := tree.current_scene
	if scn != null and scn.has_method("spawn_floating_number"):
		return scn
	return null


func _spawn_damage_number(amount: int) -> void:
	if amount <= 0 or static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	var anchor := global_position + Vector2(size.x * scale.x * 0.5, size.y * scale.y * 0.30)
	vfx.spawn_floating_number(anchor, "-%d" % amount, Color(1.0, 0.32, 0.22), false)


func _spawn_death_burst() -> void:
	# A one-shot particle pop at the dying creature's body — Card2D's own death
	# tween only fades + shrinks, which felt flat against the rest of the juice.
	# Color flavors by the creature's vibe so a skeleton ashes bone-white, an
	# undead ghosts pale green, a fire creature spits embers, etc.; default is
	# dust brown so anything unclassified still gets a body to its exit.
	var vfx := _combat_vfx_target()
	if vfx == null or not vfx.has_method("spawn_spell_burst"):
		return
	var color := Color(0.78, 0.55, 0.32, 0.95)  # default: ash/dust brown
	var id := String(card_data.get("id", ""))
	var name := String(card_data.get("name", "")).to_lower()
	var kw: Array = card_data.get("keywords", [])
	if "bone" in id or "skeleton" in name or "warden_of_graves" in id:
		color = Color(0.92, 0.88, 0.74, 0.95)  # bone white
	elif "ghost" in name or "spirit" in name or "wraith" in name or "vengeful_spirit" in id:
		color = Color(0.70, 0.92, 0.85, 0.95)  # pale green ghost
	elif "fire" in id or "kindling" in id or "blood_pyre" in id or "torchbearer" in id:
		color = Color(1.0, 0.50, 0.18, 0.95)  # ember orange
	elif "demon" in name or "devil" in name or "imp" in id or "vampire" in name:
		color = Color(0.85, 0.18, 0.20, 0.95)  # devil red
	elif "thorn" in id or "sprite" in id or "naga" in id or "hydra" in id:
		color = Color(0.55, 0.85, 0.45, 0.95)  # plant green
	elif "blood" in id or "pyre" in id or kw.has("wither"):
		color = Color(0.78, 0.20, 0.25, 0.95)  # blood red
	var burst_pos := global_position + size * scale * 0.5
	vfx.spawn_spell_burst(burst_pos, color)


func _spawn_atk_change_popup(delta: int) -> void:
	# Floating "+N ATK" / "-N ATK" so silent buffs (Battle Drummer, War Cry,
	# Curse, Steal, Royal Guard's on-hit, Inspire, etc.) read on-screen instead
	# of just nudging the orb numeral. Anchored slightly above and to the left
	# of the card so it doesn't visually fight the damage number (which spawns
	# center).
	if delta == 0 or static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx == null:
		return
	var anchor := global_position + Vector2(size.x * scale.x * 0.25, size.y * scale.y * 0.12)
	var text: String
	var color: Color
	if delta > 0:
		text = "+%d ATK" % delta
		color = GameTheme.ATK_BUFFED
	else:
		text = "%d ATK" % delta  # delta is already negative
		color = Color(1.0, 0.42, 0.32)
	vfx.spawn_floating_number(anchor, text, color, false)


func show_heal_number(amount: int) -> void:
	# Called by Combat when a creature is healed, so the green number reads at
	# the card's position. Also pulses the card green briefly.
	if amount <= 0 or static_display:
		return
	var vfx := _combat_vfx_target()
	if vfx != null:
		var anchor := global_position + Vector2(size.x * scale.x * 0.5, size.y * scale.y * 0.30)
		vfx.spawn_floating_number(anchor, "+%d" % amount, Color(0.45, 1.0, 0.45), false)
	var base := modulate
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(base.r * 0.6, base.g * 1.5, base.b * 0.6, base.a), 0.08)
	tw.tween_property(self, "modulate", base, 0.25)


func _flash_hit() -> void:
	if static_display:
		return
	# Quick red-tint punch on the card body, then back to its resting tint.
	# Uses modulate (no child nodes) so it never fights the slot container.
	var base := modulate
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(base.r * 1.8, base.g * 0.5, base.b * 0.45, base.a), 0.06)
	tw.tween_property(self, "modulate", base, 0.22).set_ease(Tween.EASE_OUT)
	if AudioBank != null:
		AudioBank.play_sfx("hit")


func _die() -> void:
	destroyed.emit()
	# Stop idle bob from writing position.y each frame — it would fight the death
	# tween (and the sacrifice rise in particular).
	_idle_bob_enabled = false
	if static_display or get_tree() == null:
		if AudioBank != null:
			AudioBank.play_sfx("death")
		queue_free()
		return
	# The field arrays are already nulled by the destroyed signal / _cleanup_dead,
	# so this lingering node is invisible to combat logic.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	z_index = 40
	_spawn_death_burst()
	if _sacrifice_death:
		# Sacrifice ritual: the body ashes away UPWARD — rises, stretches thin, and
		# burns out to amber. Combat._sacrifice_creature plays the crimson veil,
		# ember burst, and altar shake around it; this is the body dissolving.
		var stw := create_tween()
		stw.set_parallel(true)
		stw.tween_property(self, "position:y", position.y - 48.0, 0.6).set_ease(Tween.EASE_OUT)
		stw.tween_property(self, "modulate", Color(1.0, 0.55, 0.20, 0.0), 0.6).set_ease(Tween.EASE_IN)
		stw.tween_property(self, "scale", scale * Vector2(0.85, 1.15), 0.6).set_ease(Tween.EASE_IN)
		stw.tween_property(self, "rotation", rotation + randf_range(-0.12, 0.12), 0.6)
		stw.chain().tween_callback(queue_free)
		return
	if AudioBank != null:
		AudioBank.play_sfx("death")
	# Death flourish: fade to a dark red while shrinking + spinning slightly, then free.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", Color(0.35, 0.08, 0.08, 0.0), 0.34).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", scale * 0.45, 0.34).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "rotation", rotation + randf_range(-0.5, 0.5), 0.34)
	tw.chain().tween_callback(queue_free)


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
		# Smoothly slide to the new slot instead of snapping. This is what makes
		# draws "deal in", plays make the hand close the gap, and discards reflow
		# — all for free, since _layout_hand calls this on every hand change.
		# Hover / drag kill this tween (see _on_mouse_entered / _start_drag) so
		# those interactions stay instant.
		if _hand_tween != null and _hand_tween.is_valid():
			_hand_tween.kill()
		_hand_tween = create_tween()
		_hand_tween.set_parallel(true)
		_hand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_tween.tween_property(self, "position", _hand_target_position, 0.17)
		_hand_tween.tween_property(self, "rotation", _hand_target_rotation, 0.17)
		_hand_tween.tween_property(self, "scale", _hand_target_scale, 0.17)


func play_attack_lunge() -> void:
	# Quick thrust toward the opponent's side, then recoil back. Player creatures
	# lunge up, enemy creatures lunge down. Position is restored exactly, so the
	# slot's CenterContainer layout is unaffected once the tween completes.
	if static_display or get_tree() == null:
		return
	var dir := 1.0 if is_opponent else -1.0
	var rest := position
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(self, "position", rest + Vector2(0, dir * 24.0), 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(self, "position", rest, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_hit_recoil(push_down: bool) -> void:
	# The struck creature snaps back along the hit axis (away from the attacker)
	# and pops slightly, then settles — the second half of the "collision" the
	# attacker's lunge starts. Mirrors the lunge's position-tween approach so it
	# coexists with idle bob the same proven way; restores to the captured rest.
	if static_display or get_tree() == null:
		return
	var dir := 1.0 if push_down else -1.0
	var rest := position
	var rest_scale := scale
	pivot_offset = size * 0.5
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = create_tween()
	_recoil_tween.set_parallel(true)
	# Shove away from the attacker, then ease home.
	_recoil_tween.tween_property(self, "position", rest + Vector2(0, dir * 13.0), 0.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(self, "position", rest, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Quick scale punch for the impact pop (scale isn't touched by idle bob).
	_recoil_tween.tween_property(self, "scale", rest_scale * Vector2(1.12, 0.9), 0.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().tween_property(self, "scale", rest_scale, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_last_stand_flare() -> void:
	# A bright heroic flare the instant Last Stand saves the creature at 1 HP.
	# White overbright flash + a slow scale pulse so the clutch survival reads.
	if static_display or get_tree() == null:
		return
	var base := modulate
	var rest_scale := scale
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.9, 1.8, 1.3, base.a), 0.08) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", rest_scale * 1.18, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "modulate", base, 0.42).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", rest_scale, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func mark_sacrifice_death() -> void:
	_sacrifice_death = true


var _idle_bob_enabled: bool = false
var _bob_time: float = 0.0
var _bob_phase: float = 0.0
var _bob_base_y: float = 0.0
var _bob_amplitude: float = 3.0
var _bob_freq: float = 1.6


func enable_idle_bob() -> void:
	# Battlefield-only subtle breathing/bob. Each card gets a randomized phase so
	# the board doesn't move in lockstep — feels like several creatures alive on
	# their own rhythms. The container that holds the card (CenterContainer in
	# the slot cell) doesn't re-layout unless children change, so writing
	# position.y each frame sticks.
	if _idle_bob_enabled or static_display:
		return
	if not is_on_battlefield:
		return
	_idle_bob_enabled = true
	_bob_phase = randf_range(0.0, TAU)
	_bob_freq = 1.4 + randf_range(-0.3, 0.5)
	_bob_amplitude = 2.5 + randf_range(-0.5, 1.5)
	_bob_base_y = position.y
	set_process(true)


func _process(delta: float) -> void:
	if not _idle_bob_enabled:
		return
	if _is_being_dragged or _is_playing:
		return
	if not is_on_battlefield:
		# Card just left the battlefield — stop bobbing.
		_idle_bob_enabled = false
		return
	_bob_time += delta
	position.y = _bob_base_y + sin(_bob_time * _bob_freq + _bob_phase) * _bob_amplitude


func set_affordable(can_afford: bool) -> void:
	# Slay-the-Spire-style readability: unaffordable cards dim noticeably so the
	# player can see at a glance which cards their mana can play. Skip on
	# battlefield/static cards (no cost concept there).
	if is_on_battlefield or static_display:
		return
	if _is_being_dragged:
		# Dragging owns the modulate during the drag → release flow. Skip.
		return
	if can_afford:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		modulate = Color(0.55, 0.55, 0.62, 0.92)


func set_display_cost(effective_cost: int) -> void:
	# Hearthstone convention: the cost orb shows the actual mana cost to play
	# this card RIGHT NOW, with color encoding whether it differs from the
	# printed base cost:
	#   green = cheaper than printed (Ember Crown free spell, Ironclad discount)
	#   red   = more expensive than printed (Taxed mutator)
	#   white = matches printed
	# This is the single fix for "Fireball says cost 1 but the game won't let
	# me play it" — players can now see the real cost on the orb itself.
	if is_on_battlefield or static_display:
		return
	if _cost_label == null:
		return
	_cost_label.text = str(effective_cost)
	var base_cost: int = int(card_data.get("cost", 0))
	if effective_cost < base_cost:
		_cost_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.50))
	elif effective_cost > base_cost:
		_cost_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	else:
		_cost_label.remove_theme_color_override("font_color")


func play_floop_pulse() -> void:
	# Golden flash + small scale punch when a floop ability resolves on this card.
	# Lets the player track which creature just acted in a busy board state.
	if static_display or get_tree() == null:
		return
	if AudioBank != null:
		AudioBank.play_sfx("floop")
	var base := modulate
	var rest_scale := scale
	pivot_offset = size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate",
		Color(min(base.r * 1.4, 1.0), min(base.g * 1.25, 1.0), base.b * 0.55, base.a), 0.10)
	tw.tween_property(self, "scale", rest_scale * 1.12, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(self, "modulate", base, 0.28) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale", rest_scale, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_mouse_entered() -> void:
	if _is_playing or _is_being_dragged or _any_card_dragging:
		return
	_is_hovered = true
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_set_border_color(GameTheme.GILT_BRIGHT)
	if not is_on_battlefield:
		z_index = 10
		scale = Vector2(1.15, 1.15)
		rotation = 0.0
		position = _hand_target_position + Vector2(0, -80)
	# Honour the tooltip delay setting — 0 = show instantly. The lift/scale
	# still happens immediately; only the detail panel is deferred so brief
	# cursor sweeps don't spam popup creation+free.
	var delay := 0.0
	if UserSettings != null:
		delay = UserSettings.tooltip_delay
	if delay <= 0.001:
		_show_detail_panel()
	else:
		# Wait `delay` seconds then check we're still hovered before showing.
		var t := get_tree().create_timer(delay)
		await t.timeout
		if _is_hovered and is_inside_tree() and not _is_being_dragged:
			_show_detail_panel()


func _on_mouse_exited() -> void:
	if _is_being_dragged or _is_playing:
		return
	_is_hovered = false
	if is_on_battlefield and will_floop:
		_set_border_color(GameTheme.FLOOP_BLUE)
	elif is_on_battlefield and has_floop() and not is_opponent:
		_set_border_color(Color(GameTheme.FLOOP_BLUE.r, GameTheme.FLOOP_BLUE.g, GameTheme.FLOOP_BLUE.b, 0.85))
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
	_any_card_dragging = true
	_is_hovered = false
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	# Scale the card DOWN to ~0.85 while dragging so it doesn't obscure the
	# board the player is trying to drop it on. Hover scale is 1.15 (a "pop"
	# while the card sits in hand) — keeping that during drag made the card
	# fill most of the field. 0.85 matches Hearthstone/Cross Blitz drag size
	# where the picked card is a touch smaller than its hover preview.
	scale = Vector2(0.85, 0.85)
	# Pivot to center so the dragged card scales around the cursor naturally,
	# not from the bottom-center used by hand fans.
	pivot_offset = size * 0.5
	# Adjust drag offset for the new scale: mouse should sit at the visual
	# center of the dragged card.
	_drag_offset = -size * scale * 0.5
	global_position = mouse_pos + _drag_offset
	z_index = 20


func _update_drag(mouse_pos: Vector2) -> void:
	global_position = mouse_pos + _drag_offset
	dragging.emit(global_position + size * scale * 0.5)


func _end_drag() -> void:
	if not _is_being_dragged:
		return
	_is_being_dragged = false
	_any_card_dragging = false
	z_index = 0
	drag_ended.emit()
	var viewport_h = get_viewport_rect().size.y
	# Use the card's visual center, not its top-left corner: a card grabbed
	# at the center has its top ~120px above the cursor, so a top-edge check
	# made the back row (which sits closest to the hand) unreachable.
	var card_center_y: float = global_position.y + size.y * scale.y * 0.5
	if card_center_y < viewport_h * PLAY_THRESHOLD_Y:
		played.emit()
	else:
		# Not high enough to play — snap back into the hand. Restore scale,
		# rotation, position, and pivot from set_hand_target. (Drag moved the
		# pivot to center so the card scaled around the cursor; reset to the
		# bottom-center pivot hand cards expect.)
		scale = _hand_target_scale
		rotation = _hand_target_rotation
		position = _hand_target_position
		pivot_offset = Vector2(size.x * 0.5, size.y)


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
	name_lbl.add_theme_color_override("font_color", GameTheme.get_name_color(card_data))
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

	# Position the detail popup on the RIGHT side, just below the enemy
	# banner (which ends at y~254). The relic grid moved to the LEFT
	# column so this slot is free, and the popup ends up tucked into the
	# enemy column where the player's eye is already going. Uses the
	# actual viewport width so it works at any resolution.
	var vp_w := 1600.0
	if get_viewport() != null:
		vp_w = get_viewport().get_visible_rect().size.x
	panel.position = Vector2(vp_w - PW - MARGIN, 270)
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
