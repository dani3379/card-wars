## LayerStyle — a drawn shape built the way a designer builds an icon (2026-09-17).
##
## THE NOTE THIS CAME FROM: "look online for techniques like shining and whatever
## else, it isn't complicated, just a series of steps on top of each other."
## That is an exact description of Photoshop's LAYER STYLES, and the reason the
## forecast marks read as vector art is that each was ONE flat `draw_colored_polygon`
## with a dark copy behind it. Two passes. An icon that looks made is eight.
##
## Photoshop applies its effects in a fixed order, bottom to top — drop shadow,
## outer glow, overlay, satin, inner glow, inner shadow, stroke, and bevel ALWAYS
## last, on top of everything. This file is that stack, in that order, for an
## arbitrary polygon, with no shader and no post-process.
##
## THE ONE TRICK THAT MAKES IT POSSIBLE is `Geometry2D.offset_polygon`. Every
## effect that needs to hug an edge — outer glow, inner glow, inner shadow, the
## bevel's two rims — is a copy of the shape grown or shrunk by a few pixels,
## drawn at a falling alpha. Literally a series of steps on top of each other.
## Grow for outside, shrink for inside; no masking, no render target, and it
## works on gl_compatibility where `clip_children` does not
## (see project_clip_children_inert_gl_compat).
##
## ALPHA-OVER, NOT ADDITIVE, AND THAT IS DELIBERATE. A true bloom wants additive
## blending, which in Godot means a `CanvasItemMaterial` on a separate child node
## — and these marks sit on a very dark war table (0.118, 0.094, 0.074), where a
## warm light at low alpha already lifts hard. Additive on top of that goes to
## neon, which is the wrong register for ink and wax: this is a mark somebody
## made, not a light source. Keep the glow WARM and WIDE rather than bright.
##
## Every function is static and takes the target `CanvasItem`, so a painter calls
## these straight out of its own `_draw()`.
## No `class_name`: every painter in this directory is reached by `preload` under
## a same-name const, and a new global class needs an `--import` pass before it
## resolves. Preload keeps it working the moment the file exists.
extends RefCounted

## Light azimuth used across the kit: top-left, y-down. Matches WaxSeal.LIGHT_A,
## because two lit objects sitting beside each other under different suns is the
## single most reliable way to make a UI look assembled rather than designed.
const LIGHT_A := PI * 1.25


static func light_vec() -> Vector2:
	return Vector2(cos(LIGHT_A), sin(LIGHT_A))


## Grow (delta > 0) or shrink (delta < 0) a polygon. Returns the largest piece,
## or an empty array once the shape has been eaten away — callers must check,
## because a shrink past the shape's own half-width legitimately returns nothing
## and blindly indexing [0] is how this crashes on a thin arm.
static func offset(poly: PackedVector2Array, delta: float) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	var pieces := Geometry2D.offset_polygon(poly, delta, Geometry2D.JOIN_ROUND)
	var best := PackedVector2Array()
	var best_n := 0
	for p in pieces:
		if p.size() > best_n:
			best_n = p.size()
			best = p
	return best


# ── 1. DROP SHADOW ─────────────────────────────────────────────────────────
## Grounds the mark. Offset toward the light's opposite, softened by stacking a
## few grown copies at falling alpha rather than by one hard silhouette — a
## single offset copy is the "sticker" look WaxSeal paid to remove in 2026-07-19.
static func drop_shadow(ci: CanvasItem, poly: PackedVector2Array,
		dist: float = 2.0, spread: float = 2.0, alpha: float = 0.55,
		steps: int = 3) -> void:
	var off := -light_vec() * dist
	for i in range(steps, 0, -1):
		var t := float(i) / float(steps)
		var grown := offset(poly, spread * t)
		if grown.is_empty():
			continue
		var moved := PackedVector2Array()
		for p in grown:
			moved.append(p + off)
		ci.draw_colored_polygon(moved, Color(0.02, 0.012, 0.008,
			alpha * (1.0 - t) * 0.9 + alpha * 0.18))


# ── 2. OUTER GLOW ──────────────────────────────────────────────────────────
## The "shining". Concentric grown copies, alpha falling on a square curve so the
## falloff is fast near the shape and long in the tail — a linear ramp reads as a
## flat halo with an edge, which is the thing that makes cheap glow look cheap.
static func outer_glow(ci: CanvasItem, poly: PackedVector2Array, col: Color,
		size: float = 7.0, alpha: float = 0.30, steps: int = 5) -> void:
	for i in range(steps, 0, -1):
		var t := float(i) / float(steps)          # 1 at the outside
		var grown := offset(poly, size * t)
		if grown.is_empty():
			continue
		ci.draw_colored_polygon(grown,
			Color(col.r, col.g, col.b, alpha * pow(1.0 - t, 2.0) + alpha * 0.08))


# ── 3. FILL / GRADIENT OVERLAY ─────────────────────────────────────────────
## A flat fill is the other half of why these read as vector art. The overlay is
## a vertical ramp faked in bands: the shape is drawn in the shadow tone, then
## progressively smaller slices of it are drawn lighter toward the lit edge.
## Bands, not a true gradient — but at a 40px mark the banding is invisible and
## the tonal range is not.
static func fill_graded(ci: CanvasItem, poly: PackedVector2Array, col: Color,
		lift: float = 0.22, bands: int = 4) -> void:
	ci.draw_colored_polygon(poly, col)
	if bands <= 1:
		return
	var lv := light_vec()
	var cen := _centroid(poly)
	for i in range(1, bands + 1):
		var t := float(i) / float(bands)
		# Each band is the shape shifted toward the light and shrunk, so the
		# lift accumulates on the lit side only.
		var band := PackedVector2Array()
		for p in poly:
			band.append(cen + (p - cen) * (1.0 - t * 0.5) + lv * t * 2.2)
		ci.draw_colored_polygon(band,
			Color(col.r, col.g, col.b, 0.0).lerp(col.lightened(lift), 0.55 / float(bands)))


# ── 4. SATIN / SHINE ───────────────────────────────────────────────────────
## The specular sweep — the "shine" the note asked for by name. A chord of the
## shape on the lit side, drawn pale and soft. Built by intersecting the shape
## with a half-plane pushed across it, so it follows the silhouette exactly and
## cannot spill past a wobbled edge the way a drawn ellipse would.
static func shine(ci: CanvasItem, poly: PackedVector2Array,
		coverage: float = 0.42, alpha: float = 0.30, steps: int = 3) -> void:
	if poly.size() < 3:
		return
	var lv := light_vec()
	var cen := _centroid(poly)
	var reach := _radius(poly, cen)
	for i in range(steps):
		var t := float(i + 1) / float(steps)
		# Push the cut further toward the lit edge each step, so the highlight
		# concentrates into a hot sliver instead of one flat wash.
		# ON THE `+lv` SIDE, for the same reason as `bevel` (2026-09-17). Both
		# the cut's offset and the half-plane's direction used to carry a
		# negation, which put this pass's near-white sliver (1.0, 0.97, 0.92)
		# on the SHADOW side -- flatly contradicting this function's own
		# docstring above, which says the chord sits on the lit side. A
		# specular highlight opposite the lamp is the single most legible way
		# to make a solid read as plastic.
		var cut := cen + lv * reach * (1.0 - coverage * (1.0 - t * 0.55))
		var half := _half_plane(cut, lv, reach * 4.0)
		for piece in Geometry2D.intersect_polygons(poly, half):
			if piece.size() >= 3:
				ci.draw_colored_polygon(piece,
					Color(1.0, 0.97, 0.92, alpha / float(steps) * (0.6 + t)))


# ── 5/6. INNER GLOW and INNER SHADOW ───────────────────────────────────────
## Both are the same construction — shrunk copies at falling alpha — differing
## only in colour and in which side of the shape they favour. Inner glow lights
## the whole inside rim; inner shadow darkens the rim away from the light, which
## is what gives a flat shape the sense of having a wall.
static func inner_glow(ci: CanvasItem, poly: PackedVector2Array, col: Color,
		size: float = 4.0, alpha: float = 0.35, steps: int = 4) -> void:
	for i in range(steps):
		var t := float(i) / float(steps)          # 0 at the rim
		var shrunk := offset(poly, -size * t)
		if shrunk.is_empty():
			return
		ci.draw_colored_polygon(shrunk,
			Color(col.r, col.g, col.b, alpha * (1.0 - t) / float(steps) * 2.0))


static func inner_shadow(ci: CanvasItem, poly: PackedVector2Array,
		size: float = 3.0, alpha: float = 0.50, steps: int = 3) -> void:
	var lv := light_vec()
	var cen := _centroid(poly)
	for i in range(steps):
		var t := float(i) / float(steps)
		var shrunk := offset(poly, -size * t)
		if shrunk.is_empty():
			return
		# Slide the dark copy toward the light so it only shows on the far wall.
		var moved := PackedVector2Array()
		for p in shrunk:
			moved.append(p + lv * size * 0.55)
		var _unused := cen
		ci.draw_colored_polygon(moved,
			Color(0.03, 0.015, 0.012, alpha * (1.0 - t) / float(steps) * 1.6))


# ── 7. STROKE ──────────────────────────────────────────────────────────────
## A crisp keyline. Drawn as the outline rather than as another offset fill, so
## it stays one pixel-width honest at any shape size.
static func stroke(ci: CanvasItem, poly: PackedVector2Array, col: Color,
		width: float = 1.4) -> void:
	if poly.size() < 2:
		return
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	ci.draw_polyline(closed, col, width, true)


# ── 8. BEVEL & EMBOSS (always last) ────────────────────────────────────────
## The pass that does the most work for the least code. Walk the silhouette and
## light each edge by how much it faces the light — lit rim on the near side,
## shaded rim on the far side. This is the ONE effect that cannot be faked with
## a symmetric outline, and its absence is exactly why a flat polygon with a dark
## halo reads as clip art.
static func bevel(ci: CanvasItem, poly: PackedVector2Array, col: Color,
		depth: float = 2.0, strength: float = 1.0) -> void:
	var n := poly.size()
	if n < 3:
		return
	var lv := light_vec()
	var cen := _centroid(poly)
	for i in range(n):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		var outn := ((p0 + p1) * 0.5 - cen).normalized()
		# AGAINST `light_vec()` ITSELF, NOT ITS NEGATION (2026-09-17).
		# `light_vec()` points TOWARD the lamp -- which is exactly why
		# `drop_shadow` offsets by its NEGATION to throw the shadow the other
		# way -- so Lambert here is `outn.dot(lv)`: +1 where the edge faces
		# the light. Written `-lv` this pass lit the BOTTOM-RIGHT rim while
		# the drop shadow underneath it also fell bottom-right, i.e. a shape
		# lit and shadowed on the SAME side. That is the "assembled rather
		# than designed" defect this file's own header warns about, happening
		# inside a single object, and at a 4px bracket arm it photographed as
		# "the rim looks a bit noisy" rather than as an obvious break.
		# `PlateFrame._outward` reached the same conclusion independently and
		# documents it; `tools/_shot_layerstyle_light` is the measurement.
		var lam := outn.dot(lv)                   # 1 facing the light
		if lam > 0.0:
			ci.draw_line(p0, p1,
				Color(col.r + 0.36, col.g + 0.30, col.b + 0.26,
					clampf(lam * 0.95 * strength, 0.0, 1.0)), depth)
		else:
			ci.draw_line(p0, p1,
				Color(0.04, 0.02, 0.016, clampf(-lam * 0.72 * strength, 0.0, 1.0)),
				depth)


# ── the whole stack, in Photoshop's order ──────────────────────────────────
## Convenience for the common case: a solid mark that wants the full treatment.
## Effects are applied bottom-to-top exactly as Photoshop applies them, because
## the order is not cosmetic — a stroke drawn after a bevel buries the bevel, and
## a shine drawn before the fill is invisible.
static func draw_shape(ci: CanvasItem, poly: PackedVector2Array, col: Color,
		opts: Dictionary = {}) -> void:
	if poly.size() < 3:
		return
	var glow: Color = opts.get("glow", col)
	if bool(opts.get("shadow", true)):
		drop_shadow(ci, poly, float(opts.get("shadow_dist", 2.0)),
			float(opts.get("shadow_spread", 2.0)))
	if float(opts.get("glow_size", 0.0)) > 0.0:
		outer_glow(ci, poly, glow, float(opts["glow_size"]),
			float(opts.get("glow_alpha", 0.30)))
	fill_graded(ci, poly, col, float(opts.get("lift", 0.22)))
	if float(opts.get("shine", 0.0)) > 0.0:
		shine(ci, poly, 0.42, float(opts["shine"]))
	if float(opts.get("inner_glow", 0.0)) > 0.0:
		inner_glow(ci, poly, glow.lightened(0.35), 4.0, float(opts["inner_glow"]))
	if float(opts.get("inner_shadow", 0.0)) > 0.0:
		inner_shadow(ci, poly, 3.0, float(opts["inner_shadow"]))
	if opts.has("stroke_col"):
		stroke(ci, poly, opts["stroke_col"], float(opts.get("stroke_w", 1.4)))
	if float(opts.get("bevel", 0.0)) > 0.0:
		bevel(ci, poly, col, float(opts.get("bevel_depth", 2.0)),
			float(opts["bevel"]))


# ── helpers ────────────────────────────────────────────────────────────────

static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(float(poly.size()), 1.0)


static func _radius(poly: PackedVector2Array, cen: Vector2) -> float:
	var r := 0.0
	for p in poly:
		r = maxf(r, (p - cen).length())
	return r


## A big rectangle covering everything on one side of a line — the cutting tool
## for `shine`. Returned wound consistently so `intersect_polygons` behaves.
static func _half_plane(at: Vector2, dir: Vector2, reach: float) -> PackedVector2Array:
	var nrm := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		at + nrm * reach,
		at + nrm * reach + dir * reach,
		at - nrm * reach + dir * reach,
		at - nrm * reach,
	])
