## WritLeaf — extracted from Card2D.gd (backend restructure 2026-07-14).
## The cut sheet itself: a deckled (seeded, slightly irregular) leaf
## silhouette with its ink contour and edge toast drawn along the SAME
## wobbled path, so the organic edge never separates from its shading.
## Replaces a StyleBox rounded rect — a mathematically perfect corner is
## the one thing real cut paper never has. The wobble only pushes INWARD,
## so children inset by >=3px always stay on the paper.
##
## ── THE SHEET HAS A THICKNESS NOW (2026-09-17), AND IT IS OPT-IN ──
##
## The historical draw is FOUR CONCENTRIC FLAT RINGS at falling alpha plus a flat
## contour. That is the defect this codebase has already paid for twice under two
## other names — the lightning bolt's halo/bolt/core stack and every picture
## frame's single metal rule — and the sentence is the same both times:
## **stacking symmetric bands can only make a line thicker or dimmer; it cannot
## make one into an object.** On the starting-bonus screen the rings read as a
## wireframe of nested hairlines round each term, which is exactly what they are.
##
## WHAT A SHEET OF PAPER IS. Three facts, and they are the whole opt-in path:
##  1. It has a CUT EDGE with thickness — a little wall standing off the table.
##  2. **THE LIGHT INVERTS BETWEEN OPPOSITE RUNS.** Lit from up-left, the TOP
##     run's wall faces the lamp and its raw fibre glows; the BOTTOM run's wall
##     faces away, sits in its own shadow, and throws the sheet's shadow onto the
##     table. This is the load-bearing cue and a symmetric ring stack cannot fake
##     it by construction — that is why the old rim read as vector art.
##  3. It LIES ON SOMETHING, so it casts a contact shadow.
## Rasterised the way `PlateFrame` rasterises a molding: `EDGE_STEPS` concentric
## paths across the edge band, each a polyline with PER-POINT colour from a
## profile of (depth, lambert). `_ring`'s fixed point count is what makes that
## possible — the paths are parallel by construction, which its own comment
## already noted for the flat rings.
##
## THE VALUE RULE INVERTS HERE AND IT DECIDED EVERY COLOUR. The kit's dark-ground
## grammar (a black band at half alpha = "scorched") laid over cream paper is a
## dead neutral GREY, which is what made the old rim read as a bevelled 90s
## groove. On paper a shadow is a SEPIA STAIN — value down, saturation up, hue
## pulled toward the toast — and a highlight is the LAMP'S OWN warm white,
## because paper is a dielectric and reflects the light's colour rather than
## tinting it with its own.
##
## DEFAULTS ARE OFF, deliberately and not provisionally: every one of the ~260
## card faces in the game is a WritLeaf, and they go through the bake pipeline,
## so a change to the shared draw is a change to every card in the deck and to
## every cached texture. `edge_profile = false` returns the historical draw byte
## for byte. Card2D can adopt this later on its own terms.
extends Control

## The kit's one lamp. Two lit objects side by side under different suns is the
## most reliable way to make a UI look assembled rather than designed.
const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

const EDGE_STEPS := 7
## Deckle amplitude. ONE value for every concentric path, or the bands cross each
## other and the cross-section shears apart along the run.
const DECKLE_AMP := 1.7

var seed_text := "leaf"
var paper := Color(0.871, 0.812, 0.694)
var edge_ink := Color(0.165, 0.125, 0.082)
var toast := Color(0.298, 0.208, 0.110)
var toast_strength := 1.0
var corner_radius := 8.0

## OPT-IN (see header). Draws the edge as a lit cross-section instead of four
## flat rings.
var edge_profile := false
## Width of the edge band in px. Below ~4 there is no room for a cross-section
## and this degenerates into the stroke it replaces.
var edge_w := 7.0
## The raw fibre of the cut edge where it faces the lamp. Warm white, not white:
## paper reflects the LIGHT's colour, where a metal would tint the reflection
## with its own hue.
var stock := Color(1.0, 0.972, 0.902)
## Strength of the lamp gradient across the page, 0 = the historical flat fill.
## Per-vertex on the fill polygon, so it is a LINEAR ramp — the one thing a rim
## polygon's triangulation reproduces exactly. A radial falloff here would
## emboss (a point near the middle is covered by more triangles than one on the
## rim), which is the trap the smoke lobes paid for.
var lamp := 0.0
## Contact shadow onto whatever the sheet lies on, in px. 0 disables.
var drop := 0.0

var _ph1 := 0.0
var _ph2 := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	_ph1 = rng.randf() * TAU
	_ph2 = rng.randf() * TAU


## A Control does NOT redraw itself when it is resized, and every point in this
## file is derived from `size` — so a leaf that changes shape after its first
## draw keeps the old silhouette. It never mattered on a card (Card2D's faces are
## a fixed 225x300), and it showed up the moment a leaf was handed to a tile that
## GROWS to its own text: `GameTheme.fit_tile_height` takes the starting-bonus
## writs from 172 to 226, and the sheet went on being drawn at the taller of the
## two sizes it had seen, hanging ~4px of paper past the bottom of its own rect.
## Measured by an edge walk that found paper 4px BELOW the button it belongs to.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

## Rounded-rect ring at `inset`, deckled: a fixed-count path (so nested
## toast rings stay parallel) where each vertex is pushed inward along
## the local path normal by a smooth two-frequency seeded wave.
func _ring(inset: float, amp: float) -> PackedVector2Array:
	var r := maxf(corner_radius - inset, 0.5)
	var x0 := inset
	var y0 := inset
	var x1 := size.x - inset
	var y1 := size.y - inset
	var cs := [
		[Vector2(x0 + r, y0 + r), PI, PI * 1.5],
		[Vector2(x1 - r, y0 + r), PI * 1.5, TAU],
		[Vector2(x1 - r, y1 - r), 0.0, PI * 0.5],
		[Vector2(x0 + r, y1 - r), PI * 0.5, PI],
	]
	var arc_n := 7
	var edge_n := 21
	var ideal := PackedVector2Array()
	for ci in range(4):
		var ctr: Vector2 = cs[ci][0]
		var a0: float = cs[ci][1]
		var a1: float = cs[ci][2]
		for s in range(arc_n):
			var a := lerpf(a0, a1, float(s) / float(arc_n - 1))
			ideal.append(ctr + Vector2(cos(a), sin(a)) * r)
		var nci := (ci + 1) % 4
		var nctr: Vector2 = cs[nci][0]
		var na0: float = cs[nci][1]
		var p_from := ctr + Vector2(cos(a1), sin(a1)) * r
		var p_to := nctr + Vector2(cos(na0), sin(na0)) * r
		for s in range(1, edge_n + 1):
			ideal.append(p_from.lerp(p_to, float(s) / float(edge_n + 1)))
	var n := ideal.size()
	var pts := PackedVector2Array()
	for i in range(n):
		var prev := ideal[(i - 1 + n) % n]
		var next := ideal[(i + 1) % n]
		var tang := (next - prev).normalized()
		var inward := Vector2(-tang.y, tang.x)
		var u := float(i) / float(n) * TAU
		var wob := clampf(0.34 + 0.33 * sin(u * 5.0 + _ph1)
			+ 0.33 * sin(u * 13.0 + _ph2), 0.0, 1.0) * amp
		pts.append(ideal[i] + inward * wob)
	return pts

## OUTWARD normal per point, averaged from the two segments meeting there.
##
## `_ring` winds CLOCKWISE in screen space (y down) — its first corner arc runs
## PI -> 1.5PI, i.e. from the left edge up to the top, and then along the top to
## the right. So for a segment a->b the outward normal is `(b.y - a.y, a.x - b.x)`,
## which is the negation of the `inward` that `_ring` already computes for its
## wobble. The sign matters completely here: it IS which half of the sheet is lit.
static func _outward(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	for i in range(n):
		var prev: Vector2 = poly[(i - 1 + n) % n]
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % n]
		var n0 := Vector2(cur.y - prev.y, prev.x - cur.x).normalized()
		var n1 := Vector2(nxt.y - cur.y, cur.x - nxt.x).normalized()
		out.append((n0 + n1).normalized())
	return out


## Close a loop with a one-segment overshoot so the joint carries no notch.
static func _close(pts: PackedVector2Array, cols: PackedColorArray) -> Array:
	var p := pts.duplicate()
	var c := cols.duplicate()
	if pts.size() >= 2:
		p.append(pts[0]); c.append(cols[0])
		p.append(pts[1]); c.append(cols[1])
	return [p, c]


## A SEPIA STAIN, not a step toward black. Paper in shadow is still paper: the
## value falls, the saturation RISES, and the hue is pulled toward the sheet's own
## toast. Walking toward black instead is what turned the old rim grey.
func _stain(c: Color, amt: float) -> Color:
	var a := clampf(amt, 0.0, 1.0)
	var t := c.lerp(toast, a * 0.72)
	var out := Color.from_hsv(t.h, clampf(t.s * (1.0 + a * 0.30), 0.0, 1.0),
		clampf(t.v * (1.0 - a * 0.42), 0.0, 1.0))
	out.a = c.a
	return out


## Paper catching the lamp goes toward the LAMP's colour, which is why this is a
## plain lerp toward `stock` rather than an HSV value lift: a dielectric reflects
## the light, a metal tints the reflection with its own hue.
func _catch(c: Color, amt: float) -> Color:
	var out := c.lerp(stock, clampf(amt, 0.0, 1.0))
	out.a = c.a
	return out


## The sheet's edge in cross-section. `u` runs 0 at the silhouette to 1 at the
## inner end of the band; `lam` is how much this run faces the lamp, -1..1.
##
## TWO TERMS, and they are deliberately not one smooth bead — a sheet of paper is
## a STEP, not a moulding, so the shoulder does not roll over into a crest.
##
##   STOCK  the cut wall. Its normal IS the run's outward normal, so it takes the
##          lamp head-on along the top and left runs and sits in shadow along the
##          bottom and right ones. This is the whole inversion.
##   TOAST  the page's own falloff just inside the deckle — the fibre's ambient
##          occlusion plus the dirt a handled edge collects. Present on every run
##          (hence the 0.13 floor) and far heavier where the run is already in
##          shadow, which is the second, quieter half of the same inversion.
##
## **THE STOCK'S WIDTH WAS SET BY MEASUREMENT AND IT IS BOUNDED ON BOTH SIDES.**
## Too wide and it goes CHALKY: at a third of the band (2.3px) the sheet grew a
## pale grey MAT and read as a mount rather than as paper — the same failure the
## molding paid for from the other direction ("three lightening passes made it
## chalk"). Too narrow and it does not survive rasterisation: confined to a fifth
## it was ~1px, an edge walk across the top run read `0.09 0.09 0.26 0.77` and the
## lit band never appeared at all, because that single pixel is the one the
## antialiaser blends with the dark table. 0.30 of a 7px band is ~2px, which
## leaves one clean pixel between the blend and the page.
##
## **AND THE TWO RUNS DO NOT CARRY THEIR CUE IN THE SAME CURRENCY.** `paper` sits
## at 0.82 luminance with only 0.18 of headroom to white, so a lit paper edge
## CANNOT be much brighter than lit paper — that is physics, not tuning. The lit
## run reads as a hard one-pixel STEP out of the dark table; the shade run reads
## as a 3px stained RAMP. Expect the measured inversion to be carried mostly by
## the shaded side, and do not go chasing the lit side with more brightness.
func _edge_profile(u: float, lam: float) -> Color:
	var t := clampf(lam, -1.0, 1.0)
	var stock_k: float = pow(clampf(1.0 - u * 3.4, 0.0, 1.0), 0.75)
	# A softer exponent than the stock's, so what lies inside the cut is a
	# GRADIENT running out into the page rather than a second band beside it.
	var toast_k: float = pow(1.0 - clampf(u, 0.0, 1.0), 2.6) \
		* (0.13 + 0.87 * (0.5 - t * 0.5))
	var c := paper
	if t >= 0.0:
		c = _catch(c, stock_k * t * 0.82)
	else:
		c = _stain(c, stock_k * -t * 0.84)
	return _stain(c, toast_k * 0.34 * toast_strength)


func _draw() -> void:
	if size.x <= 8.0 or size.y <= 8.0:
		return
	if not edge_profile:
		_draw_flat()
		return
	var lv := LayerStyle.light_vec()
	var sheet := _ring(1.0, DECKLE_AMP)

	# 1 — THE CONTACT SHADOW. The sheet lies on something, so it throws a shadow
	# down-light. Several grown copies at falling alpha rather than one offset
	# silhouette, which is the sticker look WaxSeal paid to remove.
	if drop > 0.0:
		var off := -lv * drop
		for i in range(3, 0, -1):
			var k := float(i) / 3.0
			var ring := _ring(1.0 - drop * k * 0.8, DECKLE_AMP)
			var moved := PackedVector2Array()
			for p in ring:
				moved.append(p + off)
			var loop := _close(moved, _flat_cols(moved.size(),
				Color(0.021, 0.014, 0.010, 0.30 * (1.0 - k) + 0.13)))
			draw_polyline_colors(loop[0], loop[1], maxf(drop * 1.4, 1.5), true)

	# 2 — the page, under the lamp. A LINEAR ramp along the light vector: see
	# `lamp` for why nothing radial belongs on a rim polygon.
	if lamp > 0.0:
		var ctr := size * 0.5
		var reach: float = maxf(size.length() * 0.5, 1.0)
		var cols := PackedColorArray()
		for p in sheet:
			var d: float = clampf(((p - ctr).dot(-lv) / reach) * 0.5 + 0.5, 0.0, 1.0)
			# KEPT SMALL, and the shade side smaller than the lit side. At 0.30 of
			# stain the far half of the sheet went visibly brown and the page read
			# DIRTY rather than lit — on a light ground the eye reads a value drop
			# across a broad area as soiling, not as shadow. The job here is only
			# to say which way the lamp is; the edge carries the form.
			cols.append(_stain(_catch(paper, (1.0 - d) * lamp * 0.26),
				d * lamp * 0.13))
		RenderingServer.canvas_item_add_polygon(get_canvas_item(), sheet, cols)
	else:
		draw_colored_polygon(sheet, paper)

	# 3 — the cut line, AND ITS ALPHA RIDES THE LAMP.
	#
	# **THE LIT EDGE CANNOT WIN ON BRIGHTNESS, AND THIS IS WHERE THAT WAS SETTLED.**
	# A printed scanline across the top edge read `0.10 0.20 0.65 0.77` — a soft
	# three-pixel ramp with no highlight in it at all — and no amount of lifting
	# the stock fixed that, because `paper` already sits at 0.82 luminance and
	# there is only 0.18 of headroom to white. A lit sheet's edge is not brighter
	# than a lit sheet; what reads is the CRISP STEP from the dark table straight
	# into paper, and a dark contour drawn all the way round is precisely what
	# destroys it.
	#
	# So the seam is a whisper on the runs facing the lamp and heavy on the runs
	# facing away, where it is no longer an outline but the sheet's own shadow at
	# its own edge. The antialiasing guard the flat version needed this line for
	# is carried by the edge bands below, which are antialiased polylines
	# straddling the same silhouette.
	var norms := _outward(sheet)
	var seam := PackedColorArray()
	for j in range(sheet.size()):
		var lam: float = norms[j].dot(lv)
		seam.append(Color(edge_ink.r, edge_ink.g, edge_ink.b,
			0.10 + 0.72 * (0.5 - lam * 0.5)))
	var seam_loop := _close(sheet, seam)
	draw_polyline_colors(seam_loop[0], seam_loop[1], 1.4, true)

	# 4 — THE EDGE. `EDGE_STEPS` concentric paths across the band, each carrying
	# per-point colour from the profile. Drawn at 1.9x the nominal pitch so
	# consecutive steps overlap and the section reads as one continuous surface
	# rather than as the set of rings it replaced.
	var w: float = clampf(edge_w, 1.0, minf(size.x, size.y) * 0.25)
	var band: float = maxf(w / float(EDGE_STEPS) * 1.9, 1.0)
	for i in range(EDGE_STEPS):
		var u := (float(i) + 0.5) / float(EDGE_STEPS)
		var ring := _ring(1.0 + u * w, DECKLE_AMP)
		var rn := _outward(ring)
		var cols := PackedColorArray()
		for j in range(ring.size()):
			cols.append(_edge_profile(u, rn[j].dot(lv)))
		var loop := _close(ring, cols)
		draw_polyline_colors(loop[0], loop[1], band, true)


## The historical draw, unchanged — every card face in the game takes this path.
func _draw_flat() -> void:
	# 1 — the sheet.
	var sheet := _ring(1.0, 1.7)
	draw_colored_polygon(sheet, paper)
	# 2 — ink contour: hand-cut edge line, doubles as silhouette AA.
	var closed := sheet.duplicate()
	closed.append(sheet[0])
	draw_polyline(closed, edge_ink, 1.3, true)
	# 3 — edge toast along the SAME deckle, fading inward, per-segment
	# alpha jitter so it reads hand-inked rather than printed.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text) + 3
	for k in range(4):
		var ring := _ring(2.2 + float(k) * 1.7, 1.7)
		var base_a := (0.105 - float(k) * 0.019) * toast_strength
		for j in range(ring.size() - 1):
			draw_line(ring[j], ring[j + 1],
				Color(toast.r, toast.g, toast.b,
				base_a * (0.7 + rng.randf() * 0.6)),
				2.4 - float(k) * 0.3, true)


static func _flat_cols(n: int, c: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for _i in range(n):
		out.append(c)
	return out
