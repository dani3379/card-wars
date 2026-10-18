## ChannelBand — a groove CUT INTO a plate, drawn as a cross-section (2026-09-18).
##
## The shared primitive under `RunRoad` and `VigourBand`, the two marks on the
## title screen's CURRENT RUN plate. Both are "a quantity laid along a track",
## and a track is the one shape this codebase has repeatedly got wrong.
##
## THE DEFECT IT EXISTS TO AVOID. A `draw_line`, a `draw_rect` and a `Line2D` all
## carry UNIFORM OPACITY across their width and ONE value along their length, so
## a track drawn with any of them is a flat band — the same sentence this project
## has now written about the lightning bolt (project_ring_engine_shader_20260909),
## about every picture frame (project_plate_frame_molding_20260917) and about the
## concentric strokes round a choice tile (reference_flat_ring_stack_on_paper).
## Stacking more bands cannot fix it: symmetric layers can only make a line
## thicker or brighter, never turn it into an object.
##
## WHAT A GROOVE IS. A channel cut into a surface has a cross-section, and the
## two walls of that cross-section face OPPOSITE WAYS — so under one lamp they
## take opposite values. That asymmetry is the entire cue, and it is the thing a
## symmetric stack cannot fake. Walking the profile with the lamp fixed at
## top-left (LayerStyle.LIGHT_A, shared with WaxSeal and PlateFrame so every lit
## object on the screen sits under one sun):
##
##   u 0.00 - 0.30   NEAR WALL   faces down-right, away from the lamp -> darkest
##   u 0.30 - 0.72   FLOOR       faces the lamp but is occluded by both walls,
##                               so it recovers only slowly (ambient occlusion)
##   u 0.72 - 1.00   FAR WALL    faces up-left, into the lamp -> the lit rim
##
## The lit rim at the BOTTOM is what reads as "sunk". Invert the profile and the
## identical geometry reads as a raised bead — which is the convex/concave
## ambiguity the light-from-above prior resolves (Ramachandran, Nature 331, 1988;
## Sun & Perona, Nature Neuroscience 1, 1998, who measured the prior as above and
## shifted LEFT, which is why the kit's azimuth is PI*1.25 rather than straight
## up). Getting the sign wrong does not look like a bug, it looks like a
## different object, so the profile is stated once, here, and never per caller.
##
## A FILL SITS IN THE CHANNEL, IT DOES NOT COVER IT. `draw_fill` re-shades the
## caller's colour with the SAME profile, so the marched road and the wax in the
## vigour band are lit by the channel they lie in rather than pasted over it. A
## flat fill colour is how a progress bar announces itself as a web widget.
##
## No `class_name`: every painter in this directory is reached by `preload` under
## a same-name const, so it works the moment the file exists with no `--import`.
extends RefCounted

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

## Cross-section resolution. 9 slices over a 7-9px band puts the banding under a
## pixel; more is free and pointless.
const SLICES := 9

## Profile breakpoints. Named rather than inlined because the two walls are not
## symmetric and a reader has to be able to see that at a glance.
const NEAR_WALL_END := 0.30
const FLOOR_END := 0.72


## Value across the band, -1 (deepest shadow) .. +1 (lit rim), at depth `u`.
##
## Deliberately piecewise-linear rather than a cosine roll: a groove has CORNERS
## where its walls meet its floor, and a smooth roll reads as a soft dent. The
## corner is what says "cut".
static func profile(u: float) -> float:
	if u < NEAR_WALL_END:
		return lerpf(-0.88, -0.58, u / NEAR_WALL_END)
	if u < FLOOR_END:
		return lerpf(-0.58, -0.22, (u - NEAR_WALL_END) / (FLOOR_END - NEAR_WALL_END))
	return lerpf(-0.22, 1.0, (u - FLOOR_END) / (1.0 - FLOOR_END))


## Shade METAL by a profile value: negative sinks toward black, positive lifts
## toward `lit`.
##
## The lift runs toward a WARM colour rather than toward white because this is a
## specular on a METAL, and a metal tints its reflection with its own hue while a
## dielectric returns the lamp's (Cook & Torrance, ACM TOG 1(1), 1982). The same
## substitution bleached PlateFrame to bone through four passes before it was
## named, so it is spelled out here too.
##
## FOR THE STUFF LYING IN THE CHANNEL, USE `shade_material` INSTEAD. Running this
## one over a coloured fill is a measured defect rather than a matter of taste:
## at the lit end it lerps 86% of the way to the lamp, so the bottom of a bar of
## oxblood wax came out very nearly GOLD and the whole band photographed as a
## flat bright stripe with no hue of its own left in it.
## How far the lit rim may travel toward `lit`.
##
## 0.60, DOWN FROM 0.86 after a render. At 0.86 the rim measured luminance ~0.85
## — the same value as the screen's TITLE — so a 388px groove carried a band as
## bright as the loudest type on the page, running its whole length at one value.
## That is the flat-primitive defect arriving from the other side: not a line too
## dim to read as an object, a rim so hot it became the object. The standard
## planted on the road has to be the brightest mark on the plate, and at 0.86 it
## was not.
const RIM_GAIN := 0.60

static func shade(base: Color, lit: Color, v: float) -> Color:
	if v >= 0.0:
		return base.lerp(lit, clampf(v, 0.0, 1.0) * RIM_GAIN)
	var k := clampf(-v, 0.0, 1.0)
	return Color(base.r * (1.0 - k * 0.92), base.g * (1.0 - k * 0.92),
		base.b * (1.0 - k * 0.92), base.a)


## Shade a DIELECTRIC — wax, cloth, stone, the things that lie in the channel —
## by the same profile.
##
## THE SPLIT IS COOK & TORRANCE'S AND IT IS THE WHOLE FIX. A diffuse surface
## returns its own spectrum, so lighting it must scale its colour and must not
## drag it toward the lamp's; only the SPECULAR carries the lamp's hue, and on a
## dielectric a specular is a NARROW highlight, never a wash across the face.
## `draw_fill` therefore lights the body with this and lays the lamp-coloured
## specular in separately, as a single line on the crest.
static func shade_material(fill: Color, v: float) -> Color:
	var k := clampf((v + 1.0) * 0.5, 0.0, 1.0)     # -1..1 -> 0..1
	# Tops out just above 1.0 rather than well above it: a diffuse surface cannot
	# return more than it receives, and a full HEALTH band lit past its own
	# colour stopped reading as oxblood wax and started reading as a lit red bar.
	var d := 0.26 + 0.82 * k
	return Color(fill.r * d, fill.g * d, fill.b * d, fill.a)


## Cut an empty channel across `rect`.
##
## `plate` is the surface the groove is cut into — the shading is relative to it,
## which is what makes one channel work on the dark title plate and on a card.
static func draw_channel(ci: CanvasItem, rect: Rect2, plate: Color,
		lit: Color, shimmer: float = 0.30) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var sh := rect.size.y / float(SLICES)
	# THE RUN IS BROKEN INTO SEGMENTS SO THE LAMP CAN VARY ALONG IT. A perfectly
	# even rim is what makes a long groove read as a WIRE laid on the plate
	# rather than as a cut in it — one value for 388px is the flat-primitive
	# signature whatever the cross-section is doing. So the lamp is perturbed per
	# segment (never the silhouette: PlateFrame paid for that lesson, where a
	# wobbled run measured 6px of sag on an object the eye reads as milled).
	var segs := 1 if shimmer <= 0.001 else maxi(int(rect.size.x / 11.0), 1)
	var sw := rect.size.x / float(segs)
	for s in range(segs):
		# Two low harmonics rather than a hash: beaten metal undulates, it does
		# not speckle, and a per-segment random reads as aliasing (the same note
		# ChartPanelStyle._plate carries about its deckle grain).
		var t := float(s) / float(maxi(segs, 1))
		var jitter := (sin(t * TAU * 2.3) * 0.62 + sin(t * TAU * 5.7 + 1.1) * 0.38) \
			* shimmer * 0.22
		for i in range(SLICES):
			var u := (float(i) + 0.5) / float(SLICES)
			var col := shade(plate, lit, profile(u) + jitter)
			ci.draw_rect(Rect2(rect.position.x + float(s) * sw,
				rect.position.y + float(i) * sh, sw + 0.6, sh + 0.6), col)


## Lay `fill` into the channel from its left edge out to `frac` of its length.
##
## The fill is shaded by the SAME profile, compressed toward the lit end: what is
## lying in a groove is lit by the groove, so its own near edge stays dark and
## its far edge catches the rim. `crown` lifts the material's own top surface —
## a full channel is nearly level with the plate and catches more light than a
## nearly-empty one, which is a second, free reading of the same quantity.
static func draw_fill(ci: CanvasItem, rect: Rect2, frac: float, fill: Color,
		lit: Color, crown: float = 0.30) -> void:
	var f := clampf(frac, 0.0, 1.0)
	if f <= 0.0 or rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var w := rect.size.x * f
	# THE MATERIAL IS INSET, AND THIS IS THE FIX THAT MATTERED MOST. Filling the
	# channel's full height covers both its walls, so what is left on screen is a
	# coloured RECTANGLE — and a rectangle reads as a UI widget however carefully
	# its interior is lit. Measured on the first render: a full HEALTH band was a
	# flat red block with a painted gloss line across it, i.e. a progress bar,
	# which is the one piece of web-page chrome this plate exists to be free of.
	# Leaving the walls proud keeps the groove visible AT EVERY FILL LEVEL, so
	# the mark is a channel with something lying in it rather than a bar.
	var inset: float = clampf(rect.size.y * 0.22, 1.5, 4.0)
	var top := rect.position.y + inset
	var h := rect.size.y - inset * 2.0
	if h < 2.0:
		return
	var sh := h / float(SLICES)
	for i in range(SLICES):
		var u := (float(i) + 0.5) / float(SLICES)
		# The material's own surface: shallower than the empty channel's, so it
		# reads as substance rather than as paint on the floor.
		var v := profile(u) * (1.0 - crown) + crown * 0.35
		ci.draw_rect(Rect2(rect.position.x, top + float(i) * sh, w, sh + 0.6),
			shade_material(fill, v))
	# THE SPECULAR IS A LINE, NOT A BAND. On a dielectric the lamp's own colour
	# comes back in a narrow highlight; drawn as a 16%-height band at 0.22 alpha
	# it photographed as a stripe of paint laid along the bar, which is a
	# different object. One pixel on the crest, and the falloff either side is
	# the diffuse ramp already under it.
	ci.draw_rect(Rect2(rect.position.x, top + h * 0.62, w, 1.0),
		Color(lit.r, lit.g, lit.b, 0.30))
	# The meniscus: where the material ends, its end-grain catches the lamp. One
	# bright vertical is what stops the fill looking like a clipped rectangle —
	# the same reason a beam needs a taper rather than a flat cap.
	if f < 0.998:
		ci.draw_rect(Rect2(rect.position.x + w - 1.5, top, 1.5, h),
			shade_material(fill, 1.0).lerp(lit, 0.30))


## The lip highlight along the channel's lower edge, drawn OUTSIDE it.
##
## Physically this is the plate's own surface rolling over into the cut, and it
## is what separates a groove from a dark stripe painted on. Kept to one pixel:
## the cue is a STEP, not a band.
static func draw_lip(ci: CanvasItem, rect: Rect2, plate: Color,
		lit: Color) -> void:
	ci.draw_rect(Rect2(rect.position.x, rect.position.y + rect.size.y,
		rect.size.x, 1.0), shade(plate, lit, 0.42))
	ci.draw_rect(Rect2(rect.position.x, rect.position.y - 1.0,
		rect.size.x, 1.0), shade(plate, lit, -0.45))
