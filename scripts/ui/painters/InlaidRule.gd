## InlaidRule — the shell's section divider, drawn as a LENGTH OF METAL SET INTO
## THE PAGE rather than as a bar of colour (2026-09-18).
##
## THE DEFECT. `MainMenu._make_ornament_row` built its rule out of `ColorRect`s:
## `custom_minimum_size = Vector2(w, 2)`, one flat colour, hard ends. Measured on
## the shipped RUN SETUP, walking DOWN through the rule under HOW HE FIGHTS:
##
##     0.087  0.087 | 0.450  0.448  0.450 | 0.086  0.086
##
## Three rows, ONE value, a hard step up of 5.2x and a hard step back. That is
## the same sentence this project has now written about `Line2D` ("uniform
## opacity across its width"), about every picture frame (`PlateFrame`), about
## the tracks on the title screen's dossier (`ChannelBand`) and about the rings
## round a choice tile. The dividers were the last flat strokes on the screen,
## and they survived three separate passes at this exact defect because nobody
## looks at a divider.
##
## It is also far too loud for what it says. The same measurement puts the rule
## at 0.450 against a page at 0.084 in the right column and 0.416 against 0.014
## in the left — THIRTY TIMES its ground, for a mark carrying no information at
## all, sitting under a heading that is dimmer than it is. Tufte's data-ink ratio
## inverted, which is finding #3 from the dossier rebuild arriving again.
##
## WHAT IT IS INSTEAD. A rule under a heading, in this game's material language,
## is a length of gilt inlaid into the page — and that is not a new object, it is
## ONE RUN of the moulding `PlateFrame` already draws. A horizontal bead lit from
## up-left presents its top shoulder to the lamp and drops its lower lip into
## shadow, which is exactly `profile_at(u, lam)` for a frame's TOP run. So the
## cross-section is not restated here; it is imported. The same reason
## `PlaqueStyle` shares `draw_molding` — two spellings of one profile is this
## codebase's worst recurring pathology, and a divider lit under a different sun
## from the frame beside it is precisely how it shows.
##
## GLOSS IS BOUGHT WITH CONTRAST, NOT COVERAGE (Marlow & Anderson 2013). The flat
## rule spent 100% of its width at peak value; this spends about a sixth, with a
## sunk body underneath. Mean ink falls hard while the peak barely moves — which
## is how the rule stops out-shouting its own heading without going invisible.
##
## THE ENDS TAPER. A flat rect stops dead at both ends, and a mark that simply
## stops reads as a bar someone laid on the page. This is the beam kit's `taper`
## lesson (`Motion.beam_line`), spent on the two things that actually terminate.
##
## No `class_name`: every painter in this directory is reached by `preload` under
## a same-name const, so it works the moment the file exists with no `--import`.
extends Control

const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")

## Cross-section resolution. 9 slices over a 4-5px bead puts the banding under a
## pixel; more is free and pointless.
const SLICES := 9
## Lengthwise nodes. Only the end taper needs them — the profile is constant
## along the run — so this is the resolution of the fade, not of the moulding.
const NODES := 24

## The metal. Handed in by the caller exactly as a frame's is.
var metal := Color(0.83, 0.74, 0.54, 1.0)
## Height of the bead in px.
##
## A SHAPE NEEDS AREA BEFORE IT CAN BE LIT — the finding the forecast brackets
## paid for at 2.8 -> 4.0px, that `PlateFrame` records for a 1px molding, and
## that `ChannelBand` hit again at `BAND_H` 9. At the 2px the `ColorRect` used
## there is nowhere to put a crest AND a lip, so every slice lands on the same
## pixel and you are back to the stroke. 4 is the floor that carries a profile.
var thickness := 4.0
## Fraction of the length that fades at each end.
var taper := 0.09
## How much this run faces the lamp. +1 is a frame's TOP run: lit shoulder up,
## shadowed lip down, which is what a bead lying on a page looks like.
var lam := 1.0

## The cross-section's own dials. Milder than `PlateFrame`'s defaults, and the
## reason is the JOB rather than taste: a frame is furniture and may read as
## solid bronze, while a divider is chrome that must stay subordinate to the
## heading above it — but it is still a metal, so it keeps its hue rather than
## being pulled most of the way to the alloy.
## TUNED AGAINST THE PAGE, NOT BY EYE. The first build kept `PlateFrame`'s own
## `lit_gain` and measured a crest at 0.619 — BRIGHTER than the flat bar it
## replaced (0.450), which is the opposite of the point: the rule went on
## out-shouting its own heading and merely acquired a nicer falloff. Sinking the
## body and cutting the highlight's reach puts the crest at ~0.40, under the flat
## rule's peak, with the cross-section intact. Contrast, not coverage.
var alloy_mix := 0.34
var body_drop := 0.50
var lit_gain := 0.44
var hot_shift := 0.80
var hot_sigma := 0.20


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Drop-in for the `ColorRect` the ornament row used to build. `w` is a MINIMUM:
## a stretching row lets the container hand it more, and `_draw` reads `size`.
static func make(w: float, col: Color, thick: float = 4.0) -> Control:
	var n = (load("res://scripts/ui/painters/InlaidRule.gd") as GDScript).new()
	n.metal = col
	n.thickness = thick
	n.custom_minimum_size = Vector2(maxf(2.0, w), thick)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return n


## Smoothstep over the end taper, so the run arrives at zero with zero slope. A
## LINEAR fade reads as a flat wash with an edge on it — `LayerStyle.outer_glow`
## and `PlateFrame`'s Cornsweet ramp both settled on a curve for the same reason.
func _end_alpha(t: float) -> float:
	var e := clampf(minf(t, 1.0 - t) / maxf(taper, 0.001), 0.0, 1.0)
	return e * e * (3.0 - 2.0 * e)


func _draw() -> void:
	var w := size.x
	var h := minf(thickness, size.y if size.y > 0.0 else thickness)
	if w <= 2.0 or h <= 0.5:
		return
	var y0 := (size.y - h) * 0.5
	var base: Color = PlateFrame.body_colour({
		"metal": metal, "alloy_mix": alloy_mix, "body_drop": body_drop})
	# Every slice's colour, computed once — the profile is constant along the run,
	# so the only thing that varies lengthwise is the taper's alpha.
	var cols: Array[Color] = []
	for i in range(SLICES + 1):
		cols.append(PlateFrame.profile_at(float(i) / float(SLICES), lam, base,
			Color(1.0, 0.92, 0.72), lit_gain, hot_shift, hot_sigma))
	for i in range(SLICES):
		var ya := y0 + h * float(i) / float(SLICES)
		var yb := y0 + h * float(i + 1) / float(SLICES)
		for k in range(NODES):
			var t0 := float(k) / float(NODES)
			var t1 := float(k + 1) / float(NODES)
			var a0 := _end_alpha(t0)
			var a1 := _end_alpha(t1)
			if a0 <= 0.002 and a1 <= 0.002:
				continue
			var ca := cols[i]
			var cb := cols[i + 1]
			# Adjacent quads share their boundary vertices AND those vertices'
			# colours, so the strips tile with nothing to see between them and
			# nothing overlapping to double-blend a metal that carries alpha.
			draw_polygon(
				PackedVector2Array([
					Vector2(w * t0, ya), Vector2(w * t1, ya),
					Vector2(w * t1, yb), Vector2(w * t0, yb)]),
				PackedColorArray([
					Color(ca.r, ca.g, ca.b, ca.a * a0),
					Color(ca.r, ca.g, ca.b, ca.a * a1),
					Color(cb.r, cb.g, cb.b, cb.a * a1),
					Color(cb.r, cb.g, cb.b, cb.a * a0)]))
