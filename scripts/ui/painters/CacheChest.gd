## CacheChest — the strongbox the Relic Cache is actually dug out of.
##
## Written 2026-08-05. The Relic Cache was the one stop on the road with no
## prop at all: every other roadside verb stages something physical (the
## knucklebone patch, the sappers' kegs, the quartermaster's scale, the
## Fourth's strongbox), and this one — the stop whose entire copy is "Relic
## Uncovered" — put a dialog tile on a painted forest and called it a find.
## Both sibling hunts logged it; this is the fix.
##
## Composition. The chest is BURIED and has just been opened, so it is drawn
## sunk into the ground rather than standing on it: a spoil heap banked against
## its foot, the box itself cut off below the earth line, and the lid thrown
## back behind it. The relic tile mounts in the mouth, which is why `mouth_rect`
## is exposed — the scene reads it to seat the tile rather than guessing.
##
## Light. One source, top-left (LIGHT_A, the WaxSeal convention), so the lid's
## inner face catches it, the far wall of the interior is lit, and the near wall
## falls to occlusion. That inversion is what makes a hole read as a hole rather
## than as a black rectangle.
##
## `open_t` is 0 (shut) → 1 (thrown back). The scene tweens it for the reveal;
## the painter has no motion of its own and no Reduce Motion opinion — a static
## value renders a static chest, which is exactly what a held pose needs.
extends Control

const LIGHT_A := PI * 1.25          # top-left, y-down — the house light

## Darkened after the first render (2026-08-05): at 0.36 luminance the box read
## as pale cardboard against this stop's near-black forest, and one flat fill
## over 860x440 has no material in it at all. Oak on a night road is dark; the
## light does the describing.
const OAK := Color(0.258, 0.166, 0.092)
const OAK_LIT := Color(0.430, 0.288, 0.158)
const OAK_DK := Color(0.128, 0.079, 0.043)
const EDGE_INK := Color(0.085, 0.052, 0.030)
const IRON := Color(0.238, 0.218, 0.192)
const IRON_LIT := Color(0.560, 0.520, 0.448)
const IRON_DK := Color(0.125, 0.115, 0.100)
const EARTH := Color(0.205, 0.152, 0.100)
const EARTH_LIT := Color(0.310, 0.235, 0.152)
const MOUTH := Color(0.045, 0.030, 0.022)
const GLOW := Color(1.0, 0.72, 0.32)

var open_t := 1.0
var seed_text := "cache"
## Set by the scene when it wants the find to burn out of the box — the warm
## wash on the lid's inner face and the mouth's rim. 0 disables it entirely.
var glow_strength := 1.0

## Where the relic sits. Filled every _draw so a resize can never strand the
## tile off the box; callers read it AFTER the first draw.
var mouth_rect := Rect2()

# The open chest is an authored static prop after its 0.42 second reveal, but
# its ~70 Canvas drawing commands used to remain resident and replay every
# frame for the rest of the stop. Capture that final pose once and let the live
# painter become one textured quad. Offscreen clones keep the vector source so
# the snapshot is exact, including this chest's seed and glow.
var bake_mode := false
var _baked_texture: ImageTexture = null
var _baked_for_size := Vector2i.ZERO
var _bake_generation := 0


## Called by Treasure only after the lid reaches its held-open pose. Keeping
## this explicit preserves the real vector animation instead of freezing it.
func freeze_current_pose() -> void:
	if bake_mode or DisplayServer.get_name() == "headless" \
			or size.x < 4.0 or size.y < 4.0:
		return
	var wanted := Vector2i(roundi(size.x), roundi(size.y))
	if _baked_texture != null and wanted == _baked_for_size:
		return
	_bake_generation += 1
	_bake_snapshot(_bake_generation)


## Compatibility has no RenderingDevice pipeline baker, so use the same small
## UPDATE_ONCE SubViewport snapshot path as the campaign-standard painter. The
## viewport is freed immediately after its image has been copied.
func _bake_snapshot(generation: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or generation != _bake_generation:
		return
	var logical_size := Vector2i(roundi(size.x), roundi(size.y))
	var sub := SubViewport.new()
	sub.size = logical_size
	sub.disable_3d = true
	sub.transparent_bg = true
	sub.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var source := (get_script() as Script).new() as Control
	source.set("bake_mode", true)
	source.set("seed_text", seed_text)
	source.set("open_t", open_t)
	source.set("glow_strength", glow_strength)
	source.size = Vector2(logical_size)
	sub.add_child(source)
	add_child(sub)
	# Let the clone enter, settle its Control rect, then record one real draw.
	for _i in 2:
		await get_tree().process_frame
		if not is_inside_tree() or generation != _bake_generation \
				or not is_instance_valid(sub):
			if is_instance_valid(sub):
				sub.queue_free()
			return
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or generation != _bake_generation \
			or not is_instance_valid(sub):
		if is_instance_valid(sub):
			sub.queue_free()
		return
	var viewport_texture: Texture2D = sub.get_texture()
	var image: Image = viewport_texture.get_image() if viewport_texture != null else null
	sub.queue_free()
	if image == null or image.is_empty():
		return
	_baked_texture = ImageTexture.create_from_image(image)
	_baked_for_size = logical_size
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The earth line: how far up the control the ground sits. The box is cut off
## here, which is what sells "dug out" over "placed down".
func _ground_y() -> float:
	return size.y * 0.78


func _draw() -> void:
	if not bake_mode and _baked_texture != null:
		draw_texture_rect(_baked_texture, Rect2(Vector2.ZERO, size), false)
		return

	if minf(size.x, size.y) <= 24.0:
		return
	var w := size.x
	var h := size.y
	var gy := _ground_y()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	var light := Vector2(cos(LIGHT_A), sin(LIGHT_A))
	var t := clampf(open_t, 0.0, 1.0)

	# Box footprint. Deliberately narrower than the control so the spoil heap
	# and the thrown-back lid have room either side without clipping.
	var bx0 := w * 0.17
	var bx1 := w * 0.83
	var top := h * 0.40
	var bw := bx1 - bx0

	# ── 1. the pit ────────────────────────────────────────────────────────
	# A darkened ellipse of disturbed ground the box sits in. Drawn first and
	# wide, so the spoil banked on top of it reads as thrown out of it.
	_ellipse(Vector2(w * 0.5, gy + h * 0.045), Vector2(bw * 0.86, h * 0.085),
		Color(0.055, 0.038, 0.026, 0.55))

	# ── 2. the lid, thrown back ───────────────────────────────────────────
	# Behind the box, so the box's own top edge overlaps it. At t=0 it lies
	# flat on the rim; at t=1 it has fallen back and away, foreshortened.
	# Thinner and lower than the first cut. A lid thrown fully back is seen
	# almost EDGE-ON from the front, so its inner face should be a narrow band
	# with a bright top arris — not the broad pale ramp the first pass drew,
	# which became the biggest and flattest shape on the prop and stole the
	# box's own reading. Measured off the render: the wedge was ~120px tall
	# against a 250px box front.
	var lid_lift := lerpf(0.0, h * 0.22, t)
	var lid_back := lerpf(0.0, bw * 0.075, t)
	var lid_squash := lerpf(1.0, 0.26, t)        # cabinet foreshortening
	var lid_h := h * 0.13 * lid_squash
	var lidy := top - lid_lift
	var lid := PackedVector2Array([
		Vector2(bx0 + lid_back, lidy),
		Vector2(bx1 + lid_back, lidy),
		Vector2(bx1 + lid_back * 0.75, lidy + lid_h),
		Vector2(bx0 + lid_back * 0.75, lidy + lid_h),
	])
	draw_colored_polygon(lid, OAK_DK)
	# The lid's INNER face is what the light finds once it is thrown back —
	# and it is the surface the find's glow spills onto. Without this the open
	# lid is a dark slab and the box reads shut.
	if t > 0.05:
		var inner := PackedVector2Array([
			Vector2(bx0 + lid_back, lidy + lid_h),
			Vector2(bx1 + lid_back, lidy + lid_h),
			Vector2(bx1, top),
			Vector2(bx0, top),
		])
		# The underside is in its own shadow — OAK_DK, not OAK. Only the find's
		# glow lifts it, which is what ties the lid to what is in the box.
		var face := OAK_DK.lerp(GLOW, 0.26 * clampf(glow_strength, 0.0, 1.0))
		draw_colored_polygon(inner, Color(face.r, face.g, face.b, 0.94 * t))
		# Two braces across the inner face: a lid this size is planked too, and
		# an unbroken wedge is the flattest shape on the prop.
		for bi in range(1, 3):
			var bxp := lerpf(bx0, bx1, float(bi) / 3.0)
			draw_line(Vector2(bxp + lid_back * 0.9, lidy + lid_h),
				Vector2(bxp, top),
				Color(OAK_DK.r, OAK_DK.g, OAK_DK.b, 0.55 * t),
				maxf(1.4, w * 0.003), true)
	_band(Vector2(bx0 + lid_back, lidy), Vector2(bx1 + lid_back, lidy),
		maxf(2.0, h * 0.012), IRON_LIT, IRON_DK, light)
	# The lit arris. A thrown-back lid is read almost entirely by this line.
	draw_line(Vector2(bx0 + lid_back, lidy - 1.0), Vector2(bx1 + lid_back, lidy - 1.0),
		Color(OAK_LIT.r, OAK_LIT.g, OAK_LIT.b, 0.85), maxf(1.6, h * 0.007), true)

	# ── 3. the box ────────────────────────────────────────────────────────
	var body := PackedVector2Array([
		Vector2(bx0, top), Vector2(bx1, top),
		Vector2(bx1 - bw * 0.02, gy + h * 0.02),
		Vector2(bx0 + bw * 0.02, gy + h * 0.02),
	])
	draw_colored_polygon(body, OAK)
	# A box lit from above is not one flat fill: lay a darkening wash over the
	# lower half so the front face falls away toward the earth. Four bands
	# rather than a gradient texture — canvas polygons take a flat colour, and
	# four steps at low alpha is below the banding threshold at this size.
	for i in range(4):
		var f := float(i) / 4.0
		var y0 := lerpf(top + (gy - top) * 0.42, gy, f)
		var y1 := lerpf(top + (gy - top) * 0.42, gy, f + 0.25)
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx0 + 1, y0), Vector2(bx1 - 1, y0),
			Vector2(bx1 - 1, y1), Vector2(bx0 + 1, y1)]),
			Color(0.0, 0.0, 0.0, 0.05 + 0.045 * i))
	# Staves: vertical plank joins. A seam is TWO lines — the dark gap and the
	# lit arris of the plank next to it — which is what makes it read as boards
	# rather than as pinstripes. Sines only, no per-point jitter; near-pixel
	# noise reads as aliasing on this renderer.
	for i in range(1, 6):
		var sx := bx0 + bw * (float(i) / 6.0)
		draw_line(Vector2(sx, top + h * 0.01), Vector2(sx, gy),
			Color(OAK_DK.r, OAK_DK.g, OAK_DK.b, 0.85), maxf(1.6, w * 0.0035), true)
		draw_line(Vector2(sx + maxf(1.6, w * 0.0035), top + h * 0.01),
			Vector2(sx + maxf(1.6, w * 0.0035), gy),
			Color(OAK_LIT.r, OAK_LIT.g, OAK_LIT.b, 0.30), maxf(1.0, w * 0.002), true)
	# Lit edge down the light side, shade down the other: a box has two faces.
	draw_line(Vector2(bx0 + 1.0, top), Vector2(bx0 + 1.0, gy),
		Color(OAK_LIT.r, OAK_LIT.g, OAK_LIT.b, 0.55), maxf(1.6, w * 0.006), true)
	draw_line(Vector2(bx1 - 1.0, top), Vector2(bx1 - 1.0, gy),
		Color(OAK_DK.r, OAK_DK.g, OAK_DK.b, 0.72), maxf(1.6, w * 0.006), true)

	# ── ironwork ──────────────────────────────────────────────────────────
	# DETAIL GOES WHERE THE PROP IS ACTUALLY VISIBLE. The relic tile covers the
	# box's middle ~390px of 860, so anything drawn centre-front is drawn for
	# nobody: what carries this prop is the two FLANKS, the mouth slots either
	# side of the tile, and the spoil. Bands, rivets, brackets and grain are all
	# sized and placed to read out there.
	var band_w := maxf(4.2, h * 0.034)
	var band_y1 := top + h * 0.075
	var band_y2 := gy - h * 0.055
	_band(Vector2(bx0, band_y1), Vector2(bx1, band_y1), band_w,
		IRON_LIT, IRON_DK, light)
	_band(Vector2(bx0, band_y2), Vector2(bx1, band_y2), band_w,
		IRON_LIT, IRON_DK, light)

	# Rivets. One detail says "banded iron" faster than any amount of shading,
	# and it is the thing the first pass was missing. Drawn only on the flanks,
	# each a dark seat with a lit crown offset toward the light.
	var rivet_r := maxf(1.8, band_w * 0.30)
	for by: float in [band_y1, band_y2]:
		for u: float in [0.045, 0.115, 0.185, 0.815, 0.885, 0.955]:
			var rx := lerpf(bx0, bx1, u)
			draw_circle(Vector2(rx, by), rivet_r, IRON_DK, true, -1.0, true)
			draw_circle(Vector2(rx, by) + light * rivet_r * 0.32, rivet_r * 0.52,
				Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.85), true, -1.0, true)

	# Corner brackets: a vertical strap wrapping each front edge, top band to
	# bottom band. Without them the horizontals just float on the wood.
	for side: float in [0.0, 1.0]:
		var cxp := lerpf(bx0 + band_w * 0.55, bx1 - band_w * 0.55, side)
		draw_line(Vector2(cxp, band_y1 - band_w * 0.5),
			Vector2(cxp, band_y2 + band_w * 0.5), IRON_DK, band_w * 0.82, true)
		draw_line(Vector2(cxp - band_w * 0.22, band_y1 - band_w * 0.5),
			Vector2(cxp - band_w * 0.22, band_y2 + band_w * 0.5),
			Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.50), band_w * 0.24, true)

	# Grain: a few long strokes per visible plank. Deliberately sparse and low
	# alpha — the house lesson is that near-pixel-scale noise reads as ALIASING,
	# so this is a handful of full-height hairlines, never a texture.
	for gi in range(14):
		var gu := float(gi) / 14.0
		if gu > 0.26 and gu < 0.74:
			continue                       # behind the tile; skip the cost
		var gx := lerpf(bx0 + bw * 0.02, bx1 - bw * 0.02, gu) \
			+ sin(float(gi) * 2.7) * bw * 0.008
		draw_line(Vector2(gx, top + h * 0.02), Vector2(gx + bw * 0.004, gy - h * 0.01),
			Color(OAK_DK.r, OAK_DK.g, OAK_DK.b, 0.26), maxf(1.0, w * 0.0016), true)

	# ── 4. the mouth ──────────────────────────────────────────────────────
	# The interior. Its NEAR wall occludes and its FAR wall catches the light —
	# the same inversion WaxSeal uses for a stamped recess, and the reason this
	# reads as depth rather than as a painted black panel.
	var m0 := bx0 + bw * 0.055
	var m1 := bx1 - bw * 0.055
	var my := top + h * 0.018
	var mh := h * 0.115 * lerpf(0.25, 1.0, t)
	if mh > 2.0:
		draw_colored_polygon(PackedVector2Array([
			Vector2(m0, my), Vector2(m1, my),
			Vector2(m1 - bw * 0.012, my + mh), Vector2(m0 + bw * 0.012, my + mh),
		]), MOUTH)
		# far wall (lit), then near lip (occluded)
		draw_line(Vector2(m0, my + 0.5), Vector2(m1, my + 0.5),
			Color(IRON_LIT.r, IRON_LIT.g, IRON_LIT.b, 0.34 * t),
			maxf(1.2, h * 0.005), true)
		draw_line(Vector2(m0 + bw * 0.012, my + mh), Vector2(m1 - bw * 0.012, my + mh),
			Color(0, 0, 0, 0.55), maxf(1.4, h * 0.006), true)
		# The find, burning out of the box. Warm, low, and clipped to the mouth
		# by being drawn thin — a big soft bloom here would wash the lid.
		var g := clampf(glow_strength, 0.0, 1.0) * t
		if g > 0.01:
			# SEVEN steps at low alpha, not three at 0.20. Caught on a 3x
			# NearestNeighbor crop of the flank: three stacked ellipses over a
			# near-black mouth left each one's rim plainly visible, so the find's
			# glow read as a smudge with hard edges rather than as light. Alpha
			# per step is now under the banding threshold at this size, and the
			# radii step by a constant ratio so no two rims sit on top of each
			# other. Same rule the map plate learned: organic must stay SMOOTH.
			var steps := 7
			for i in range(steps):
				var f := 1.0 - float(i) / float(steps)
				_ellipse(Vector2((m0 + m1) * 0.5, my + mh * 0.42),
					Vector2((m1 - m0) * 0.5 * (0.30 + 0.115 * i),
						mh * (0.30 + 0.135 * i)),
					Color(GLOW.r, GLOW.g, GLOW.b, 0.085 * f * g))

	mouth_rect = Rect2(Vector2(m0, my), Vector2(m1 - m0, maxf(mh, 1.0)))

	# ── 5. spoil ──────────────────────────────────────────────────────────
	# Earth thrown out either side, banked against the box and overlapping its
	# foot — the overlap is what buries it. Two heaps, seeded so the left and
	# right differ.
	# `side` is explicitly typed: an untyped `for side in [-1.0, 1.0]` yields a
	# Variant, and every `var x := ...` derived from it then fails to infer.
	for side: float in [-1.0, 1.0]:
		var cx := w * 0.5 + side * bw * 0.52
		var hw := bw * (0.30 + rng.randf() * 0.10)
		var hh := h * (0.055 + rng.randf() * 0.030)
		var heap := PackedVector2Array()
		var steps := 16
		for i in range(steps + 1):
			var u := float(i) / float(steps)
			var ang := PI * u
			# Two sines: a lumpy bank, not a dome.
			var r := 1.0 + 0.16 * sin(ang * 3.0 + rng_phase(rng, i)) \
				+ 0.09 * sin(ang * 5.0 + side)
			heap.append(Vector2(cx - cos(ang) * hw * r, gy + h * 0.012 - sin(ang) * hh * r))
		heap.append(Vector2(cx + hw, gy + h * 0.030))
		heap.append(Vector2(cx - hw, gy + h * 0.030))
		draw_colored_polygon(heap, EARTH)
		# Lit crest on the light side of each heap.
		var crest := PackedVector2Array()
		for i in range(steps / 2 + 1):
			crest.append(heap[i])
		if crest.size() >= 2:
			draw_polyline(crest, Color(EARTH_LIT.r, EARTH_LIT.g, EARTH_LIT.b, 0.62),
				maxf(1.4, h * 0.006), true)

	# ── 6. the ground line ────────────────────────────────────────────────
	# A soft dark seam where box meets earth. Without it the box floats on the
	# spoil instead of being sunk through it.
	draw_line(Vector2(bx0 - bw * 0.06, gy + h * 0.014),
		Vector2(bx1 + bw * 0.06, gy + h * 0.014),
		Color(0.03, 0.02, 0.014, 0.50), maxf(2.0, h * 0.010), true)


func rng_phase(rng: RandomNumberGenerator, i: int) -> float:
	# Deterministic per-index phase without per-point noise: the heap keeps its
	# shape across redraws and never shimmers.
	return float((hash(seed_text) + i * 37) % 628) * 0.01


func _band(a: Vector2, b: Vector2, wide: float, lit: Color, dk: Color,
		light: Vector2) -> void:
	## One iron strap: shade laid down first, the lit edge riding the side the
	## light comes from. A single flat line reads as tape.
	draw_line(a, b, dk, wide, true)
	var off := -light.y * wide * 0.30
	draw_line(a + Vector2(0, off), b + Vector2(0, off),
		Color(lit.r, lit.g, lit.b, 0.60), maxf(1.0, wide * 0.38), true)


func _ellipse(c: Vector2, r: Vector2, col: Color, seg: int = 30) -> void:
	var pts := PackedVector2Array()
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
