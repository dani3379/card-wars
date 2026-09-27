## PlateFrame — a picture frame drawn as a MOLDING, not as a stroke (2026-09-17).
##
## THE DEFECT, AND IT IS THE LIGHTNING DEFECT IN A FRAME'S HAT.
##
## Every frame around a picture in this game was ONE FLAT STROKE:
##   * the run-setup hero plate — `ChartPanelStyle`'s metal rule, which is a
##     `canvas_item_add_polyline` in a single colour;
##   * the opener art tiles — the same rule at 1px;
##   * `Card2D`'s own art fillet — a `StyleBoxFlat` with `draw_center = false`.
##
## A polyline has UNIFORM OPACITY AND ONE VALUE ACROSS ITS WIDTH. That sentence
## is already written down in this project, about `Line2D`, as the reason every
## line effect "looked like a line cosplaying as something cool" — and the fix
## there was not to stack more lines, it was to give the stroke a painted
## CROSS-SECTION (`Motion.beam_tex`, R = heat, A = opacity across the width),
## after which one draw did the whole job.
##
## `ChartPanelStyle` even contains the failed version of that lesson. Step 4 lays
## a dim halo polyline under the crisp rule — precisely the first lightning
## rebuild, which piled halo + bolt + core and got "a thicker hard band with a
## dimmer hard band behind it". Its own comment records the symptom without
## naming the cause: the halo had to be pulled back to "whisper alpha" because on
## panel-dense screens it "stacked into a global brightness lift". Stacking
## symmetric bands can only ever make a line thicker or brighter. It cannot make
## one into an object.
##
## WHAT A FRAME ACTUALLY IS. A picture frame is a MOLDING — a length of material
## with a profile, a solid. Three facts follow, and they are the whole file:
##
##   1. IT HAS A CROSS-SECTION. Crossing a bead from outside to inside you pass
##      an outer chamfer, a crest and an inner chamfer: three surfaces at three
##      angles, so three values. A stroke has one.
##
##   2. THE LIGHT INVERTS BETWEEN OPPOSITE RUNS, and this is the load-bearing
##      one. With a light up-left, the TOP run's outer half faces the light and
##      its inner half is shadowed; on the BOTTOM run that flips, because the
##      same bead is now presenting its other shoulder. That inversion is the
##      single strongest "this is a raised solid" cue an eye has, and it is
##      exactly what a symmetric halo can never fake — a symmetric profile is by
##      construction the same on all four runs.
##
##   3. IT HOLDS SOMETHING. A frame casts a contact shadow INWARD onto the art
##      sitting in its rebate. Without it the art is beside the frame; with it
##      the art is behind it.
##
## HOW IT IS DRAWN. The cross-section is rasterised into `steps` concentric
## paths across the rule's width, each a polyline with PER-POINT colour taken
## from a profile of (u, lambert) — u being depth across the molding and lambert
## being how much that run of the frame faces the light. Same idea as beam_tex,
## resolved by hand because a closed frame path cannot be a textured Line2D.
##
## Geometry reuses the chamfered octagon `ChartPanelStyle` already draws, at a
## varying inset, so the molding sits exactly on the plate silhouette the rest of
## the kit builds and needs no polygon boolean.
##
## TWO THINGS THAT ARE NOT OPTIONAL.
##
## A SHAPE NEEDS AREA BEFORE IT CAN BE LIT. This is the same finding the forecast
## brackets paid for when their arms went 2.8px -> 4.0/5.4px. A 1px molding has
## nowhere to put a crest and a valley; every pass collapses onto the same pixel
## and you are back to a stroke. So adopting this widens a frame — that is a real
## visual change, not a free swap, and it is the point rather than a side effect.
##
## VALUE IS DECIDED BY THE LOCAL GROUND, so `lit` is a PARAMETER. On the shell's
## warm-black the crest runs white-hot; on the cards' parchment a white crest is
## a HOLE and the bright part of a mark is its most saturated, darkest part. Same
## rule the beam kit paid for with its `core` colour, and the reason this file
## will drop onto a card face without being rewritten.
##
## No `class_name`: every painter in this directory is reached by `preload` under
## a same-name const, so it works the moment the file exists with no `--import`.
extends Control

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

## Samples per long run. Fixed rather than length-derived — see `_path`.
const EDGE_SAMPLES := 11

## Lengthwise segments per run in MITRE mode. Only `shimmer` needs them — the
## cross-section itself is constant along a run — so this is the resolution of
## the glint, not of the moulding.
const RUN_SEGMENTS := 10

## The frame's own metal. The body value; the crest is built from `lit`.
var metal := Color(0.60, 0.51, 0.34, 0.90)
## The highlight colour.
##
## NOT WHITE, AND THE REASON IS PHYSICAL RATHER THAN TASTE. A white specular is
## correct for a DIELECTRIC — wax, paper, plastic, which reflect the lamp's own
## colour — and wrong for a METAL, which tints its reflection with its own hue.
## That one substitution is what made the first several passes read as bone: the
## body was a perfectly reasonable bronze and the crest kept bleaching it, so
## measured across the molding the saturation ran 0.22-0.37 against the painting
## beside it at 0.46-0.50, and a warm colour at S 0.3 is a warm GREY.
##
## The other half of the rule still holds: white-hot is only right on a dark
## ground (see the header). Both are the same question — what is the light doing
## when it meets this surface — asked about the material and about the page.
var lit := Color(1.0, 0.92, 0.72)
## How much of `lit` the crest may reach. Dial this, not the colour, for a
## quieter frame.
var lit_gain := 0.55
## How far the BODY is sunk below the colour handed in. Not a taste dial — it is
## the unit conversion between a stroke colour and a molding colour.
##
## EVERY COLOUR IN THIS CODEBASE WAS PICKED FOR A HAIRLINE, and for a hairline
## the colour IS the appearance: there is no crest and no valley, so the value
## you choose is the value you see. `MainMenu._faction_accent` proves it — it
## ends in `_lift_to_luminance(..., 0.80)`, i.e. it deliberately returns a very
## bright colour, which is correct for a 2px gilt rule and completely wrong as
## the body of a 7px solid. Handed in raw it made the hero plate the palest
## object on RUN SETUP, a cream mat competing with the painting inside it.
##
## So the body sinks well below what was handed in and only the crest lifts back
## toward it. MEASURED on the hero plate, across the molding: value runs 0.08 at
## the shadowed inner lip to 0.50 at the crest, against an input sitting at 0.85.
## That is LayerStyle's recorded rule — "once the glow carries the luminance, the
## fill only has to carry the hue, so the fill must get DARKER" — and putting it
## HERE rather than at each call site is what lets existing accents drop in
## unchanged.
##
## RAISED 0.58 -> 0.70 (2026-09-18), and the cause is the specular rather than
## taste. Under the old full-width highlight the body was barely visible, so its
## value hardly mattered: the frame photographed at luminance 0.805 FLAT — the
## palest object on RUN SETUP, against the painting it frames at 0.240 and the
## page at 0.027, and at saturation 0.213, which by this file's own rule ("a warm
## colour at S 0.3 is a warm GREY") is bone. Now that the highlight is a sixth of
## the width, the body IS the frame, and gloss is carried by the CONTRAST between
## the two (Marlow & Anderson 2013). A sunk body is what buys a hot crest without
## the whole molding going pale.
var body_drop := 0.70
## The alloy the frame is cast from, and how far the caller's colour is pulled
## toward it.
##
## A FRAME IS MADE OF SOMETHING. The colours handed in here are UI SIGNAL
## colours, chosen to be legible as thin bright rules and correspondingly pale:
## `_faction_accent` lerps up to 62% toward GILT_BRIGHT and then lifts to
## luminance 0.80, so what arrives is very nearly a neutral cream. Dropping its
## value alone gave a BONE frame with no metal in it.
##
## A SATURATION FLOOR WAS TRIED FIRST AND IS THE WRONG INSTRUMENT — worth
## recording, because it looks like the obvious fix. Standing saturation up in
## HSV amplifies whatever hue happens to arrive, and this accent's hue sits in
## the yellow-green; the hero plate came out CHARTREUSE, which is further from
## the game than the bone it replaced. Pulling toward a known-good alloy cannot
## do that: the worst case is a frame that looks like brass.
##
## The mix is a tint budget, not a wash — a warm faction still reads warm and a
## cool one (the Acolyte's teal) still reads cool, but both are recognisably the
## same metal. It has to be HIGH because of how pale the inputs are: measured,
## `_faction_accent` arrives at roughly S 0.20, so a 50% pull left the body at
## S 0.37, which still photographed as warm grey.
var alloy := Color(0.58, 0.44, 0.22)
var alloy_mix := 0.78
## Width of the molding in px. Below ~3 there is no room for a cross-section and
## this degenerates into the stroke it replaces; `_draw` says so out loud.
var rule_w := 6.0
## Corner cut, matching `ChartPanelStyle.chamfer` so a molding can sit on a plate
## the kit drew.
var chamfer := 12.0
## Cross-section resolution. 7 is enough that the banding is invisible at these
## widths; more is free but pointless.
var steps := 7
## Inward contact shadow onto whatever the frame holds, in px. 0 disables.
var rebate := 3.0
## Outward drop, in px, so the frame sits proud of the page. 0 disables.
var drop := 2.0
## Width in px of the counter-gradient decaying outward from the seam — the
## Cornsweet edge. See stage 2b in `draw_molding`. 0 disables.
var cornsweet := 3.0
## The ink every shadow layer is cut from — the exact mirror of `lit`, for the
## other half of the light (2026-09-18, added when the card face arrived).
##
## SIX layers here are SHADOW — the drop, the mitre, the seam, the Cornsweet
## ramp, the rebate and the tack seat — and every one was authored near-black,
## which is right on the shell's warm-black and WRONG ON PAPER: a shadow on
## parchment is a warm BROWN, because the light reaching it bounced off the page.
## A near-black drop on a card reads as a grey smudge round the art plate.
##
## One colour at six densities rather than six colours: the six sites differed by
## at most ~0.015 per channel, which is below what any of them can show at these
## alphas, so they were never really six decisions.
var shade := Color(0.035, 0.026, 0.017)
## Corner hardware — the mounting tacks, lit as little domes rather than as flat
## diamonds. Auto-hidden on frames too small to carry them.
var tacks := true
## Inset of the whole molding from the control's rect.
var pad := 0.0
## Hand-cut breathing along the long runs, in px, matching the silhouette
## language `ChartPanelStyle._plate` gives every other piece of furniture.
##
## DEFAULTS TO 0, AND THAT IS A CORRECTION (2026-09-18). The argument for it was
## sound and the CHANNEL was wrong. It read: "the lighting is computed from each
## point's own normal, so a run that breathes also catches the lamp unevenly
## along its length — a straight molding is one value per run, a breathing one
## shimmers the way beaten metal does." Both halves of that are true. What it
## missed is that the wobble buys the shimmer by moving the SILHOUETTE, and
## silhouette position is the one channel the eye is HYPERACUTE in.
##
## MEASURED on the shipped hero plate at `wobble 1.0`: the crest of the top run
## wandered y=137..143 — SIX PIXELS of sag across a 300px run. Vernier offsets
## are discriminable down to 2-5 arcsec, an order of magnitude finer than one
## pixel at any normal viewing distance, and curvature detection is hyperacute
## too. So the sag is not a subliminal texture: it is the most visible thing
## about the frame, and it reads as a warped or sagging length of material,
## because a picture frame is a MILLED object and the eye knows it.
##
## The shimmer was worth keeping, so it moved to `shimmer` below — same effect on
## the lamp, spent in a channel with no hyperacuity in it. Vary the shading, not
## the silhouette.
var wobble := 0.0
## Unevenness of the lamp along each run, 0..1 — the beaten-metal glint the
## `wobble` above used to buy as a side effect of bending the frame.
##
## It perturbs each point's LAMBERT rather than its position, so the molding
## stays dead straight while the light still crawls along it. Luminance-gradient
## discrimination is nowhere near hyperacute (Weber fractions of a few percent,
## against vernier's arcseconds), which is the whole reason this channel can
## carry a texture the silhouette cannot.
var shimmer := 0.35
## Where the specular sits across the width, as a fraction of the half-width, and
## how tight it is. See `profile_at` — these two are the gloss cues.
var hot_shift := 0.80
var hot_sigma := 0.15
## How the four runs of moulding MEET. See `_draw_mitred` for the whole argument.
##
##   "chamfer" — the kit's cut octagon. Right for a PLAQUE: a struck plate with
##     its corners taken off, which is exactly what `PlaqueStyle`'s buttons are.
##   "mitre"   — a real picture frame. Four lengths cut at 45 degrees and butted,
##     so the OUTER SILHOUETTE STAYS SQUARE and the joint is a diagonal SEAM.
##
## Defaults to "chamfer" so `PlaqueStyle` and every existing caller are byte
## identical; a frame round a PICTURE opts in.
var corner := "chamfer"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Hang a molding over `parent`, full-rect. Mirrors how the call sites used to
## add a bordered `Panel`, so swapping one for the other preserves child order —
## which matters wherever a chip or a click catcher is added after the frame.
static func over(parent: Control, frame_metal: Color, opts: Dictionary = {}) -> Control:
	var f = (load("res://scripts/ui/painters/PlateFrame.gd") as GDScript).new()
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.metal = frame_metal
	for k in opts:
		f.set(k, opts[k])
	parent.add_child(f)
	return f


# ── geometry ───────────────────────────────────────────────────────────────

## The chamfered octagon, inset by `inset`. Same construction as
## `GameTheme.ChartPanelStyle._oct`, deliberately: the molding has to land on the
## silhouette the rest of the furniture kit draws, and re-deriving a second
## rounded-rect here is how two spellings of one shape drift apart.
static func _oct(r: Rect2, inset: float, ch: float) -> PackedVector2Array:
	var l := r.position.x + inset
	var t := r.position.y + inset
	var rr := r.position.x + r.size.x - inset
	var b := r.position.y + r.size.y - inset
	var c: float = maxf(ch - inset * 0.5, 2.0)
	if rr - l < c * 2.0 or b - t < c * 2.0:
		c = maxf(minf(rr - l, b - t) * 0.5 - 0.5, 0.0)
	return PackedVector2Array([
		Vector2(l + c, t), Vector2(rr - c, t), Vector2(rr, t + c),
		Vector2(rr, b - c), Vector2(rr - c, b), Vector2(l + c, b),
		Vector2(l, b - c), Vector2(l, t + c)])


## The molding path at `inset`, with the kit's hand-cut breathing.
##
## THE POINT COUNT AND THE PARAMETERISATION ARE FIXED ACROSS INSETS ON PURPOSE.
## `ChartPanelStyle._plate` samples each edge by LENGTH (`seg / 22.0`), which
## would give each of the `steps` concentric paths a different point count and a
## different phase — so the bands would cross each other and the cross-section
## would shear apart along the run. Sampling every long edge at a fixed count
## with the same seeded phase keeps all the steps PARALLEL, which is what lets
## the whole molding meander while still reading as one solid.
static func _path(r: Rect2, inset: float, ch: float, amp: float,
		sd: int) -> PackedVector2Array:
	var oct := _oct(r, inset, ch)
	if amp <= 0.05:
		return oct
	var pts := PackedVector2Array()
	for e in range(8):
		var a: Vector2 = oct[e]
		var b: Vector2 = oct[(e + 1) % 8]
		# The chamfer diagonals stay dead straight: a corner cut that wobbles
		# stops reading as a cut.
		if a.distance_to(b) <= 24.0:
			pts.append(a)
			continue
		var n := Vector2(b.y - a.y, a.x - b.x).normalized()
		var ph1 := float(absi((sd ^ (e * 19349663)) % 628)) * 0.01
		var ph2 := float(absi((sd ^ (e * 83492791)) % 628)) * 0.01
		for i in range(EDGE_SAMPLES):
			var t := float(i) / float(EDGE_SAMPLES)
			# Pinned at both ends, so the corners keep their stance and the
			# chamfers meet the runs cleanly.
			var pin := sin(t * PI)
			var d := sin(t * TAU * 1.5 + ph1) * 0.62 + sin(t * TAU * 3.5 + ph2) * 0.38
			pts.append(a.lerp(b, t) + n * d * amp * pin)
	return pts


## The plate silhouette at a given inset. Public because a caller that FILLS the
## plate — `PlaqueStyle`'s button face — has to land on exactly the path this
## molding will be drawn over. Deriving a second rounded-rect there is how a face
## comes to peek out from under its own frame on one screen and not another.
static func path_at(r: Rect2, inset: float, ch: float, amp: float,
		sd: int) -> PackedVector2Array:
	return _path(r, inset, ch, amp, sd)


## OUTWARD normal per point, averaged from the two segments meeting there.
##
## Derived here rather than copied: `ChartPanelStyle._plate`'s comment calls its
## normal "outward" and then multiplies by -1, which for this winding points
## INWARD. It gets away with it because the wobble it feeds is a signed sine that
## breathes both ways, so the sign never mattered there. It matters completely
## here — the sign IS which half of the frame is lit.
##
## `_oct` winds clockwise in screen space (y down), so for a segment a->b the
## outward normal is `(b.y - a.y, a.x - b.x)`. Checked on both axes: the top run
## (b-a = +x) gives (0,-1) = up = out, and the right run (b-a = +y) gives (1,0).
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


## Close a loop with a one-segment overshoot so the joint has no notch — the
## `ChartPanelStyle._closed` idiom, carried over with its colour array.
static func _close(pts: PackedVector2Array, cols: PackedColorArray) -> Array:
	var p := pts.duplicate()
	var c := cols.duplicate()
	if pts.size() >= 2:
		p.append(pts[0]); c.append(cols[0])
		p.append(pts[1]); c.append(cols[1])
	return [p, c]


# ── the mitre ──────────────────────────────────────────────────────────────

## The four runs as [outer A, outer B], wound CLOCKWISE in screen space so the
## outward normal is `(b.y - a.y, a.x - b.x)` — the same winding and the same
## derivation as `_oct` / `_outward`, deliberately, so one sign convention holds
## across the file.
static func _runs(r: Rect2) -> Array:
	var l := r.position.x
	var t := r.position.y
	var rr := r.end.x
	var b := r.end.y
	return [
		[Vector2(l, t), Vector2(rr, t)],
		[Vector2(rr, t), Vector2(rr, b)],
		[Vector2(rr, b), Vector2(l, b)],
		[Vector2(l, b), Vector2(l, t)]]


## A point on one run of the moulding, `d` deep and a fraction `t` along it.
##
## THIS ONE LINE IS THE MITRE. At depth `d` the run is pulled in by `d` at BOTH
## ENDS as well as inward, so the locus of its two ends as `d` runs 0 -> w is a
## 45-degree diagonal from the outside corner to the inside one. That is a mitre
## joint, and it falls out of the geometry rather than being drawn on.
static func _mitre_pt(a: Vector2, b: Vector2, along: Vector2, inward: Vector2,
		d: float, t: float) -> Vector2:
	return (a + inward * d + along * d).lerp(b + inward * d - along * d, t)


## THE MOULDING AS FOUR MITRED LENGTHS — the second half of this file's own
## argument, and it was missing until 2026-09-18.
##
## The header got the CROSS-SECTION right and then inherited the SILHOUETTE from
## `ChartPanelStyle._oct`, reasoning that "the molding has to land on the
## silhouette the rest of the furniture kit draws". But a chamfered octagon is a
## TOKEN — a ticket, a nameplate, a stop sign — and no picture frame ever made
## has cut corners. So every frame on RUN SETUP was a correctly-lit moulding bent
## into the wrong object. That is the same shape of error as the first lightning
## rebuild, which textured the stroke and still read wrong because a bolt is
## SEVERAL STROKES and not one: the drawing was fixed and the OBJECT was not.
##
## MEASURED on the shipped screen, and the chamfer was the loudest thing on it —
## the cut corner peaked at 1.47x the straight run on the hero plate (0.612 vs
## 0.415), 1.24x on a roster thumbnail, 1.18x on a deck tile. That is forced by
## construction rather than by tuning: a chamfer's outward normal sits at 45
## degrees and `LayerStyle.LIGHT_A` IS 45 degrees, so the top-left cut is the one
## place on the whole frame facing the lamp DEAD ON — lam = 1, peak diffuse and
## peak specular together. Four bright diagonal dashes at the corners of every
## frame, and the eye reached all four before it reached the picture.
##
## A mitre inverts that. The joint is a SEAM, so the corner becomes the QUIETEST
## place on the frame, and the value STEP across it — top run lit, right run
## shadowed, because they are two different lengths of material presenting two
## different faces — is the single most recognisable "this is a picture frame"
## cue an eye has. `_oct` cannot produce it: its chamfer is a run of its own that
## BLENDS the two, which is exactly why the result read as a bevelled plaque.
##
## Drawn as quads rather than as concentric polylines, and that is the
## `reference_soft_edge_needs_vertices` recipe rather than a preference: the
## profile is non-linear across `u`, so it wants STRIPS whose every vertex
## carries its own measured colour. Adjacent strips share their boundary vertices
## AND those vertices' colours, so there is no seam to see and no overlap to
## smear the narrow specular — which is what the polyline path has to spend its
## 1.25x band overlap on. It also means no double-blending, so a metal with alpha
## (the deck tiles ship 0.82) comes out at the density it asked for.
static func _draw_mitred(ci: RID, r: Rect2, w: float, base: Color, lit_c: Color,
		lit_g: float, steps_n: int, shim: float, hshift: float, hsigma: float,
		sh: Color, sd: int) -> void:
	var lv := LayerStyle.light_vec()
	var runs := _runs(r)
	for ri in range(4):
		var a: Vector2 = runs[ri][0]
		var b: Vector2 = runs[ri][1]
		var along := (b - a).normalized()
		var n := Vector2(b.y - a.y, a.x - b.x).normalized()
		var inward := -n
		var run_lam := n.dot(lv)
		# The glint, sampled at the lengthwise NODES so neighbouring strips agree
		# exactly. Constant across depth by construction — the same k is the same
		# place on the run at every `u` — so a dent runs across the whole
		# cross-section the way a real one does instead of shearing along it.
		# PINNED AT BOTH ENDS, and this is not a polish detail — it is the whole
		# claim of mitre mode (2026-09-18, caught by `_probe_frame_molding` check
		# 9 on its SECOND run).
		#
		# `_glint` is seeded off the node's instance id, so an unpinned glint can
		# land a +shimmer spike on the segment that touches a JOINT. At the
		# portrait's shimmer 0.40 that takes a run's lambert from 0.707 to the
		# clamp at 1.0 — full diffuse AND full specular — which is exactly the
		# bright corner the chamfer was replaced to remove, arriving by a
		# different route and on some instance ids and not others. Measured: the
		# corner/run ratio read 0.83x on one run of the gate and 1.33x on the
		# next, from the same code.
		#
		# A MEASUREMENT THAT MOVES WITH THE SEED IS NOT A PROPERTY OF THE DESIGN,
		# and a threshold set from one sample of it is set from luck. Pinning
		# makes the corner carry the run's TRUE lambert by construction, so the
		# check is reproducible for the same reason the frame is correct.
		# `_path` already pins its wobble the same way and for the same reason —
		# "the corners keep their stance".
		var lams := PackedFloat32Array()
		for k in range(RUN_SEGMENTS + 1):
			var lam := run_lam
			if shim > 0.0:
				var pin := sin(PI * float(k) / float(RUN_SEGMENTS))
				lam = clampf(lam + _glint(k + ri * 97, sd) * shim * pin, -1.0, 1.0)
			lams.append(lam)
		for i in range(steps_n):
			var u0 := float(i) / float(steps_n)
			var u1 := float(i + 1) / float(steps_n)
			var d0 := u0 * w
			var d1 := u1 * w
			for k in range(RUN_SEGMENTS):
				var t0 := float(k) / float(RUN_SEGMENTS)
				var t1 := float(k + 1) / float(RUN_SEGMENTS)
				RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([
						_mitre_pt(a, b, along, inward, d0, t0),
						_mitre_pt(a, b, along, inward, d0, t1),
						_mitre_pt(a, b, along, inward, d1, t1),
						_mitre_pt(a, b, along, inward, d1, t0)]),
					# `run_lam` as the fourth term: the glint varies the BRIGHTNESS
					# along the run and must not also walk the highlight across it.
					PackedColorArray([
						profile_at(u0, lams[k], base, lit_c, lit_g, hshift, hsigma, run_lam),
						profile_at(u0, lams[k + 1], base, lit_c, lit_g, hshift, hsigma, run_lam),
						profile_at(u1, lams[k + 1], base, lit_c, lit_g, hshift, hsigma, run_lam),
						profile_at(u1, lams[k], base, lit_c, lit_g, hshift, hsigma, run_lam)]))
	# THE JOINTS. A mitre is a cut, and a cut is a fine dark line — the glue seam
	# every real frame shows. It also makes the top-LEFT corner legible, which is
	# the one place the lighting cannot: with the lamp at 45 degrees the top and
	# left runs take an identical lambert, so without a drawn seam those two
	# lengths fuse into one bent piece of metal.
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)]:
		# TYPED, not inferred: `c` comes from an untyped Array literal, so it is a
		# Variant, and Variant arithmetic has no static type for `:=` to infer.
		var inw: Vector2 = (r.get_center() - c).normalized()
		RenderingServer.canvas_item_add_line(ci, c, c + inw * w * 1.4142,
			_ink(sh, 0.50), 1.0, true)


# ── the cross-section ──────────────────────────────────────────────────────

## THE MOLDING IS A SHARED STATIC, AND THE SHARING IS THE POINT (2026-09-17).
##
## `PlaqueStyle` draws a BUTTON as a plate with this same molded edge, and a
## StyleBox is not a Node: it cannot host this Control, it is handed an RID and a
## rect and told to draw. Restating the cross-section over there is this
## codebase's worst recurring pathology — `NetPlayerState` restating every
## relic's magnitude as a literal beside the RelicDB read, `SkirmishBot`'s own
## `_best_creature_slot` sitting beside `BoardEval` — which is equal on the day
## it is written and one retune away from a frame and a button lit by different
## suns, on one screen, silently.
##
## So the profile, the paths and the draw live HERE once, against a RID, and this
## Control's `_draw` is one call into them. Anything that can get a canvas item
## can have a molding.
static func default_cfg() -> Dictionary:
	return {
		"metal": Color(0.60, 0.51, 0.34, 0.90),
		"lit": Color(1.0, 0.92, 0.72),
		"lit_gain": 0.55,
		"body_drop": 0.70,
		"alloy": Color(0.58, 0.44, 0.22),
		"alloy_mix": 0.78,
		"rule_w": 6.0,
		"chamfer": 12.0,
		# More steps than before (7 -> 11) because the profile's narrowest feature
		# is now the specular rather than the crest: at 7 steps across a 6px
		# molding the highlight fell between samples and read as a dashed glint.
		# Extra steps are near-free — they are polylines over the same path.
		"steps": 11,
		"rebate": 3.0,
		"drop": 2.0,
		"cornsweet": 3.0,
		"shade": Color(0.035, 0.026, 0.017),
		"tacks": true,
		"wobble": 0.0,
		"shimmer": 0.35,
		"hot_shift": 0.80,
		"hot_sigma": 0.15,
		## The corner fill. A frame over ART wants it (a cut corner over a
		## rectangular painting leaves a wedge of picture outside the chamfer);
		## a BUTTON does not, because the plate's own face already ends on the
		## chamfer and filling the mitre would paint a dark triangle onto it.
		##
		## IT IS DEAD UNDER `corner: "mitre"`, and that is the point — a mitred
		## corner covers its own picture, so there is no wedge left to patch.
		"mitre": true,
		"corner": "chamfer",
	}


## The width the molding will actually draw at, given the rect. Public because a
## caller that fills the plate needs to know where the metal ends before it can
## lay a face under it — and deriving that twice is how a face peeks out.
static func molding_width(r: Rect2, rule_w_in: float) -> float:
	return clampf(rule_w_in, 1.0, minf(r.size.x, r.size.y) * 0.25)


## The hand-cut breathing amplitude for this rect. Same reason as above.
static func molding_amp(r: Rect2, wobble_in: float) -> float:
	return minf(wobble_in, minf(r.size.x, r.size.y) * 0.012)


## The body colour: the caller's metal pulled toward the alloy, then sunk well
## below the value handed in. See `alloy` and `body_drop` for why both halves are
## needed; the crest lifts it back.
static func body_colour(cfg: Dictionary) -> Color:
	var metal_in: Color = cfg.get("metal", Color(0.60, 0.51, 0.34, 0.90))
	var base: Color = metal_in.lerp(cfg.get("alloy", Color(0.58, 0.44, 0.22)),
		clampf(float(cfg.get("alloy_mix", 0.78)), 0.0, 1.0))
	base = Color.from_hsv(base.h, base.s,
		clampf(base.v * (1.0 - float(cfg.get("body_drop", 0.58))), 0.0, 1.0))
	base.a = metal_in.a
	return base


## The whole molding, drawn against a canvas item. `sd` seeds the hand-cut so a
## caller can keep one silhouette across several styleboxes on the same control.
static func draw_molding(ci: RID, r: Rect2, cfg: Dictionary, sd: int) -> void:
	if r.size.x <= 4.0 or r.size.y <= 4.0:
		return
	var ch := clampf(float(cfg.get("chamfer", 12.0)), 3.0,
		minf(r.size.x, r.size.y) * 0.26)
	var w := molding_width(r, float(cfg.get("rule_w", 6.0)))
	var amp := molding_amp(r, float(cfg.get("wobble", 1.1)))
	var steps_n := maxi(int(cfg.get("steps", 7)), 1)
	var lit_c: Color = cfg.get("lit", Color(1.0, 0.92, 0.72))
	var lit_g := float(cfg.get("lit_gain", 0.55))
	var drop_d := float(cfg.get("drop", 2.0))
	var rebate_d := float(cfg.get("rebate", 3.0))
	var lv := LayerStyle.light_vec()
	var sh: Color = cfg.get("shade", Color(0.035, 0.026, 0.017))

	# A MITRED FRAME IS SQUARE. Every auxiliary contour below — the drop, the ink
	# seam, the counter-gradient, the rebate — is built from `_oct`, so rather
	# than growing a second spelling of the silhouette they are handed the corner
	# FLOOR: a 2px nick that antialiases the corner and is invisible at any size.
	# The hand-cut goes with it, because a mitred length is milled stock.
	var mitred := String(cfg.get("corner", "chamfer")) == "mitre"
	if mitred:
		ch = 2.0
		amp = 0.0

	# ── 1. the drop. The frame stands off the page, so it casts down-light.
	# Offset along -light_vec (down-right for an up-left lamp), a few grown
	# copies at falling alpha rather than one hard silhouette — one offset copy
	# is the sticker look WaxSeal paid to remove.
	if drop_d > 0.0:
		var off := -lv * drop_d
		for i in range(3, 0, -1):
			var t := float(i) / 3.0
			var sp := _oct(r.grow(drop_d * t * 0.9), 0.0, ch + drop_d * t)
			var moved := PackedVector2Array()
			for p in sp:
				moved.append(p + off)
			var dloop := _close(moved, _flat_cols(moved.size(),
				_ink(sh, 0.34 * (1.0 - t) + 0.10)))
			RenderingServer.canvas_item_add_polyline(ci, dloop[0], dloop[1],
				w * 1.5, true)

	# ── 1b. THE MITRE. The molding's corners are CUT, but the thing it frames is
	# a RECTANGLE — so at every corner a triangle of content sits outside the
	# chamfer with nothing over it. On the hero plate that is a wedge of heavily
	# vignetted painting poking past the frame, which reads as a torn corner.
	#
	# It predates this file (the 2px rule left the same gap and the vignette
	# nearly hid it), but a 7px molding makes it legible, so it is this file's to
	# close. Filled with the seam's own dark so it reads as the mitre sitting in
	# shadow rather than as a patch stuck on.
	if ch > 2.0 and bool(cfg.get("mitre", true)) and not mitred:
		var g := r.grow(1.0)
		var o := _oct(g, 0.0, ch + 1.0)
		for tri in [
				[Vector2(g.position.x, g.position.y), o[7], o[0]],
				[Vector2(g.end.x, g.position.y), o[1], o[2]],
				[Vector2(g.end.x, g.end.y), o[3], o[4]],
				[Vector2(g.position.x, g.end.y), o[5], o[6]]]:
			RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array(tri),
				PackedColorArray([_ink(sh, 0.94)]))

	# ── 2. the ink seam. A dark contour just outside the metal, at fixed alpha.
	# This is the aliasing guard the panel kit already relies on: canvas polygons
	# and polylines do not antialias reliably against a painted ground, and a
	# faint metal (a dim tile rule) would leave the staircase uncovered.
	var seam := _path(r, -0.4, ch, amp, sd)
	var seam_loop := _close(seam, _flat_cols(seam.size(), _ink(sh, 0.80)))
	RenderingServer.canvas_item_add_polyline(ci, seam_loop[0], seam_loop[1], 1.6, true)

	# ── 2b. THE COUNTER-GRADIENT, i.e. the cheapest depth in the file (2026-09-18).
	#
	# A short dark ramp decaying OUTWARD from the seam, so that crossing the
	# frame's outer boundary you meet a light-to-dark pair converging on the edge:
	# the molding's lit outer shoulder on one side, this on the other. That is a
	# Craik-O'Brien-Cornsweet edge (Cornsweet 1970) — a luminance gradient
	# confined to the neighbourhood of a boundary makes the regions either side of
	# it read as whole steps apart, though they are unchanged a few px away.
	# Purves, Shimpi & Lotto (1999) give the empirical account; Didyk et al. (2012)
	# and Ritschel et al.'s 3D unsharp masking (SIGGRAPH 2008) both use exactly
	# this to buy apparent DEPTH rather than apparent lightness, which is what is
	# wanted here.
	#
	# It is the right instrument for a frame specifically because a frame has no
	# pixels to spare: the molding is 4-6px, there is no room for a real
	# wide-field gradient, and a Cornsweet profile is defined by being narrow. It
	# is also why this is a DARK ramp rather than the light halo `ChartPanelStyle`
	# tried — a light one lifts the whole page when panels are dense (its own
	# comment records that), while this reads as the page dimming into the frame's
	# contact, which is what a raised object actually does to the surface under it.
	var cornsweet := float(cfg.get("cornsweet", 3.0))
	if cornsweet > 0.0:
		var csteps := 3
		for i in range(csteps):
			var t := (float(i) + 0.5) / float(csteps)
			var path := _path(r, -0.4 - cornsweet * t, ch, amp, sd)
			# Squared falloff: fast out of the seam and long in the tail, the
			# curve `LayerStyle.outer_glow` settled on for the same reason — a
			# linear ramp reads as a flat wash WITH AN EDGE, which would just be
			# a second line beside the one being explained.
			var a := 0.34 * pow(1.0 - t, 2.0)
			var loop := _close(path, _flat_cols(path.size(), _ink(sh, a)))
			RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1],
				maxf(cornsweet / float(csteps) * 2.0, 1.0), true)

	# ── 3. THE MOLDING. `steps` concentric paths across the width, each carrying
	# per-point colour from the profile. The band is drawn 1.9x its nominal pitch
	# so consecutive steps overlap and the cross-section reads continuous rather
	# than as a set of rings.
	# The overlap factor was 1.9x the pitch, which is fine under a profile whose
	# features are half the molding wide and fatal under one whose highlight is a
	# sixth of it: consecutive steps paint over each other's outer half and smear
	# the very feature this profile exists to place. 1.25 keeps the cross-section
	# continuous — the 1.0px floor is what actually guarantees no gap, since a
	# sub-pixel line still rasterises a pixel wide — and lets a narrow specular
	# survive to the framebuffer.
	var band: float = maxf(w / float(steps_n) * 1.25, 1.0)
	var base := body_colour(cfg)
	var shim := clampf(float(cfg.get("shimmer", 0.0)), 0.0, 1.0)
	var hshift := float(cfg.get("hot_shift", 0.80))
	var hsigma := float(cfg.get("hot_sigma", 0.15))
	if mitred:
		_draw_mitred(ci, r, w, base, lit_c, lit_g, steps_n, shim, hshift, hsigma,
			sh, sd)
	# The concentric-polyline path, for `corner: "chamfer"` only. An octagon has
	# no joints to draw, so one closed loop per step is the whole run.
	for i in range(0 if mitred else steps_n):
		var u := (float(i) + 0.5) / float(steps_n)
		var path := _path(r, u * w, ch, amp, sd)
		var norms := _outward(path)
		var cols := PackedColorArray()
		for j in range(path.size()):
			# Light from up-left: lam is +1 on the top and left runs. Computed
			# against `light_vec()` itself, NOT its negation — see `_outward`.
			var lam := norms[j].dot(lv)
			# The beaten-metal glint, spent on the LAMP rather than on the
			# silhouette — see `shimmer`. Keyed on the point INDEX, which is
			# sound only because `_path` fixes the point count and phase across
			# every inset: the same j is the same place on the run at every
			# depth, so a dent runs across the whole cross-section the way a
			# real one does instead of shearing along it.
			if shim > 0.0:
				lam = clampf(lam + _glint(j, sd) * shim, -1.0, 1.0)
			cols.append(profile_at(u, lam, base, lit_c, lit_g, hshift, hsigma))
		var loop := _close(path, cols)
		RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1], band, true)

	# ── 4. the rebate. The frame holds something, so it shadows it. Drawn INSIDE
	# the molding, falling off over `rebate` px.
	if rebate_d > 0.0:
		var rsteps := 3
		for i in range(rsteps):
			var t := float(i) / float(rsteps)
			var path := _path(r, w + rebate_d * t, ch, amp, sd)
			var loop := _close(path, _flat_cols(path.size(),
				_ink(sh, 0.40 * (1.0 - t))))
			RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1],
				maxf(rebate_d / float(rsteps) * 2.0, 1.0), true)

	# ── 5. corner hardware. A tack is a little dome, so it is lit like one: a
	# dark seat, a graded body, and a specular dot up-left of centre. The flat
	# diamond the panel kit draws is the same defect as the flat rule, at 5px.
	# NEVER ON A MITRED FRAME. They are placed at the chamfer midpoints, and a
	# mitre has no chamfer — but the real reason is that a picture frame's
	# hardware is on its BACK. Measured at 3-5px on the shipped hero plate, the
	# dome plus its white specular dot read as a speck of dirt sitting on the
	# corner of the painting.
	if bool(cfg.get("tacks", true)) and not mitred \
			and minf(r.size.x, r.size.y) >= 70.0 and ch >= 7.0:
		var frame := _oct(r, w * 0.5, ch)
		var s: float = clampf(ch * 0.30, 2.6, 4.6)
		for pair in [[7, 0], [1, 2], [3, 4], [5, 6]]:
			var m: Vector2 = (frame[pair[0]] + frame[pair[1]]) * 0.5
			# `antialiased = FALSE`, matching `CanvasItem.draw_circle`'s own
			# default — this stage was `draw_circle` before the move to statics
			# and a tack is 3-5px, where turning AA on is a visible change to
			# another pass's tuning rather than a free one.
			RenderingServer.canvas_item_add_circle(ci, m + -lv * 1.0, s * 1.05,
				_ink(sh, 0.75), false)
			RenderingServer.canvas_item_add_circle(ci, m, s, _sink(base, 0.30), false)
			RenderingServer.canvas_item_add_circle(ci, m + lv * s * 0.30, s * 0.62,
				_lift(base, 0.30), false)
			RenderingServer.canvas_item_add_circle(ci, m + lv * s * 0.44, s * 0.28,
				Color(lit_c.r, lit_c.g, lit_c.b, 0.80 * lit_g), false)


## The molding's profile. `u` runs 0 at the OUTER edge to 1 at the INNER edge;
## `lam` is how much this run of the frame faces the light, -1..1.
##
## `roll` is the bead turning over: +1 at the outer shoulder, 0 at the crest, -1
## at the inner shoulder. Multiplied by `lam` it produces the inversion that is
## the entire argument of this file — on a lit run the outer half brightens and
## the inner half falls away, and on a shadowed run the opposite, because the
## bead is presenting its other shoulder to the same lamp.
##
## THE SPECULAR WAS PAINTED ON, AND THE PERCEPTUAL LITERATURE NAMES THE SYMPTOM
## EXACTLY (2026-09-18). It used to be `pow(facing, 9) * (0.22 + 0.78*max(lam,0))`
## — `facing` being symmetric about the crest and carrying NO dependence on the
## light at all, so the highlight sat at the SAME DEPTH on all four runs and only
## its brightness varied. That is a highlight which does not covary with the
## shading field, and Anderson & Kim (2009) and Kim, Marlow & Anderson (2011)
## report that when highlight and diffuse shading are pulled out of alignment,
## gloss is not merely reduced — it is ABOLISHED, and the specular "appears as
## changes in diffuse reflectance", i.e. the surface reads as PIGMENTED. Which is
## precisely what shipped: measured on the hero plate, the top and bottom runs
## both peaked at luminance 0.805, a flat cream band that reads as a stripe
## somebody painted rather than as light on metal.
##
## So the highlight's POSITION now rides `lam`, which is what physics says anyway.
## A specular appears where the surface normal bisects lamp and eye. On the TOP
## run the outward direction points toward the lamp, so the normal gets there on
## the OUTER shoulder (roll > 0, u < 0.5); on the BOTTOM run outward points away,
## so only the INNER shoulder tilts back up toward it (roll < 0, u > 0.5). The
## highlight therefore CROSSES the molding as you walk around the frame, which is
## the congruence those papers are about and a symmetric term cannot produce.
##
## COVERAGE IS CUT HARD AND THE CONTRAST PAYS FOR IT. Marlow, Kim & Anderson
## (2012) and Marlow & Anderson (2013) find perceived gloss is carried by the
## coverage, contrast and sharpness of the specular — and the old profile was at
## essentially 100% coverage, which is not a highlight, it is the body colour. A
## narrow Gaussian (`hot_sigma`) with a hot tip against a sunk body buys back far
## more gloss per pixel than a wide wash, and it is also what stops the frame
## being the palest object on the screen.
##
## The floor keeps a weak highlight on the shadowed runs: a crest is the nearest
## part of the solid to the eye and catches something even in shadow, and without
## it the bottom and right runs lose their edge and the frame reads as broken on
## two sides.
## `lam_pos` is the lambert that PLACES the highlight, defaulting to `lam`, which
## is the historical behaviour and what the chamfer path still passes.
##
## THE TWO ARE DIFFERENT THINGS AND MITRE MODE SEPARATES THEM (2026-09-18).
## `shimmer` models micro-roughness — a beaten surface whose local brightness
## crawls along the run. Feeding that into `u_hot` makes it also TRANSLATE the
## highlight across the width, and since `hot_shift` is 0.80 a shimmer of 0.40
## walks the crest 0.16 of the moulding, which on a 6px frame is over a pixel of
## wander along a run that is geometrically dead straight. `_probe_frame_molding`
## check 6 reads that as SAG, and it is right to: a highlight that wanders is
## indistinguishable from a warped length of material, which is the hyperacuity
## finding this file already paid for once with `wobble`.
##
## Placing the highlight from the run's MACRO orientation is also what the
## congruence result actually asks for (Anderson & Kim 2009) — the highlight must
## covary with the SHADING FIELD, and the shading field of a straight moulding is
## its run, not its surface grain.
static func profile_at(u: float, lam: float, base: Color, lit: Color,
		lit_gain: float, hot_shift: float = 0.80,
		hot_sigma: float = 0.15, lam_pos: float = INF) -> Color:
	var uu := clampf(u, 0.0, 1.0)
	var roll := cos(PI * uu)
	var shade := lam * roll
	# Where the lamp lands across the width, as a function of which way this run
	# faces. lam = +1 (fully lit run) puts it on the outer shoulder, lam = -1 on
	# the inner one; a run edge-on to the lamp keeps it at the crest.
	var lp: float = lam if is_inf(lam_pos) else lam_pos
	var u_hot := 0.5 - 0.5 * clampf(lp, -1.0, 1.0) * hot_shift
	var d := (uu - u_hot) / maxf(hot_sigma, 0.02)
	# THE SPECULAR IS DRIVEN BY `lp` IN BOTH TERMS — its place AND its strength.
	# Micro-roughness scatters a highlight; it does not brighten one. Letting the
	# glint into the amplitude made the CREST breathe along a run, which showed up
	# twice as gate flake on the same code (`plateaus` reading 3 instead of 4 on
	# one instance id in three, and the corner/run ratio moving because the
	# DENOMINATOR moved). The body still breathes — `shade` above uses `lam` — and
	# that is where beaten metal actually lives.
	var spec: float = exp(-d * d) * (0.20 + 0.80 * maxf(lp, 0.0))
	# ASYMMETRIC ON PURPOSE: the shadow side is pushed harder than the lit side.
	# Lifting and sinking by the same amount made the molding read pale overall,
	# because a lift of 0.6 on a dark body moves a long way up while the same sink
	# has much less room below it. A frame should sit mostly in its own shadow
	# with the light picked out — that is what gives it weight on a dark page.
	var c := base
	if shade >= 0.0:
		c = _lift(c, shade * 0.45)
	else:
		c = _sink(c, -shade * 0.70)
	# Only the crest TIP takes the lamp's own colour. A specular highlight is the
	# colour of the LIGHT, not of the material, so a white kiss here is right —
	# but only where the surface is actually facing the viewer.
	c = c.lerp(Color(lit.r, lit.g, lit.b, c.a), clampf(spec * lit_gain, 0.0, 1.0))
	# The contact darkening where the molding turns down into its rebate. Without
	# it the inner edge reads as the end of a stripe rather than as a lip the art
	# sits behind.
	c = _sink(c, pow(clampf(u, 0.0, 1.0), 2.6) * 0.45)
	c.a = base.a
	return c


## Brighten IN HSV so the metal keeps its hue.
##
## `Color.lightened` walks every channel toward white, which is a desaturation:
## the first render lit a warm ember accent (0.78, 0.36, 0.22) into a pale PINK
## pipe with no metal left in it, and the bronze tile rule went silver. That is
## LayerStyle's own recorded lesson reached from the opposite direction — there,
## three lightening passes across a thin stroke made it neon; here one made it
## chalk. Raise VALUE, hold SATURATION, and let the specular tip carry the white.
##
## The hue nudges a few thousandths toward gold on the way up, which is what
## real gilding does as it catches a warm lamp.
static func _lift(c: Color, amt: float) -> Color:
	var a := clampf(amt, 0.0, 1.0)
	var out := Color.from_hsv(
		fposmod(c.h + a * 0.014, 1.0),
		clampf(c.s * (1.0 - a * 0.14), 0.0, 1.0),
		clampf(c.v + a * (1.0 - c.v) * 0.80, 0.0, 1.0))
	out.a = c.a
	return out


## Darken in HSV. Metal in shadow stays SATURATED — it is still the same alloy —
## so value falls while saturation rises slightly. Walking toward black instead
## greys the shadowed runs and the frame reads as two different materials.
static func _sink(c: Color, amt: float) -> Color:
	var a := clampf(amt, 0.0, 1.0)
	var out := Color.from_hsv(c.h,
		clampf(c.s * (1.0 + a * 0.22), 0.0, 1.0),
		clampf(c.v * (1.0 - a * 0.88), 0.0, 1.0))
	out.a = c.a
	return out


## ONE CALL. Every stage of the molding lives in `draw_molding` above, so this
## Control and `PlaqueStyle`'s button plate cannot drift apart — see that
## function's header for why that mattered enough to restructure the file.
func _draw() -> void:
	var r := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	# Seeded per node, so a frame keeps one stable hand-cut across redraws.
	draw_molding(get_canvas_item(), r, {
		"metal": metal, "lit": lit, "lit_gain": lit_gain,
		"body_drop": body_drop, "alloy": alloy, "alloy_mix": alloy_mix,
		"rule_w": rule_w, "chamfer": chamfer, "steps": steps,
		"rebate": rebate, "drop": drop, "cornsweet": cornsweet,
		"shade": shade,
		"tacks": tacks, "wobble": wobble,
		"shimmer": shimmer, "hot_shift": hot_shift, "hot_sigma": hot_sigma,
		"mitre": true, "corner": corner,
	}, int(get_instance_id() & 0x7FFFFFFF))


## `shade` at a given density. Static because `draw_molding` is — a StyleBox has
## no instance to reach for (see that function's header).
static func _ink(sh: Color, a: float) -> Color:
	return Color(sh.r, sh.g, sh.b, clampf(a, 0.0, 1.0))


## Two incommensurate sines on the point index, so the glint never repeats over a
## run and never lands on a period the eye can lock to. Returns roughly -1..1.
static func _glint(j: int, sd: int) -> float:
	var p1 := float(absi((sd ^ 0x9E3779B9) % 628)) * 0.01
	var p2 := float(absi((sd ^ 0x85EBCA6B) % 628)) * 0.01
	var t := float(j)
	return sin(t * 0.37 + p1) * 0.62 + sin(t * 0.91 + p2) * 0.38


static func _flat_cols(n: int, c: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for _i in range(n):
		out.append(c)
	return out
