## PageBorder — the rule scribed round the edge of a screen (2026-09-18).
##
## THE DEFECT, and it is the reason a player said the edges of RUN SETUP "look
## weird". `GameTheme._make_decorative_frame` built the border out of TWELVE
## `ColorRect`s at TWO alphas: eight corner arms at the mood's own colour, four
## connecting rules at half that, plus four corner dots. Measured on the shipped
## screen, walking along the top edge from the left:
##
##     corner arm .......... 0.151  0.156  0.151  0.154  0.156
##     HARD STEP at x=64 ... 0.084          <- -46%, mid-run, on a straight line
##     connecting rule ..... 0.084  0.087  0.090  0.086 ...
##
## EIGHT of those joints round the page, each a visible break in a line that is
## supposed to be one continuous scribed rule. Nothing is more obviously wrong
## than a straight line that changes brightness halfway along for no reason —
## and unlike a subtle shading fault, this one is a HARD step, which is the
## channel the eye is best at.
##
## Its cross-section was `0.091 0.095` — TWO rows at one value, i.e. the flat
## stroke again — and the "corner diamond dot" was a 5x5 AXIS-ALIGNED SQUARE,
## which at 1:1 reads as a stuck pixel rather than as an ornament. (`ColorRect`
## has no rotation available to it in a static layout, so the original comment's
## "diamond" was never drawn.)
##
## WHAT IT IS INSTEAD. One continuous rule per edge whose emphasis RAMPS toward
## the corners instead of stepping there, so the corner accent the old build
## wanted survives and the joint that carried it does not. It gets the house
## cross-section (`PlateFrame.profile_at`, so the border and the frames on the
## page are lit by one lamp), and the corner marks are real diamonds lit as
## little gems.
##
## NO ALLOY PULL. Every other consumer of `PlateFrame`'s profile is FURNITURE and
## wants to read as one metal; this rule is tinted per screen MOOD (bone, ember,
## gilt, verdigris) and that tint is the whole point of it, so the caller's
## colour is used as handed in.
##
## ANCHORED, NOT PLACED. `_draw` reads `size`, which is the LIVE canvas — so this
## is right at any resolution and at every UI Scale with no resize handler. That
## is the C32 lesson (`tools/_probe_uiscale.gd`): `ProjectSettings` is static and
## the runtime canvas is not, and at 60% scale the canvas is 2667x1500.
##
## No `class_name`: every painter in this directory is reached by `preload` under
## a same-name const, so it works the moment the file exists with no `--import`.
extends Control

const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")

## Cross-section resolution across the rule's width.
const SLICES := 5
## Lengthwise nodes per edge. Carries the corner ramp only.
const NODES := 40

## Inset from the canvas edge, px.
var inset := 14.0
## Length over which the corner emphasis decays into the run, px.
var corner_run := 44.0
## Width of the rule, px.
##
## 1.5 -> 2.6: A SHAPE NEEDS AREA BEFORE IT CAN BE LIT. At 1.5px the whole
## cross-section landed in two image rows and every slice collapsed onto the same
## pixel, which is the stroke this replaces reached from the other side.
var rule_w := 2.6
## Alpha at a corner and at mid-run. The old build's two literals, now the two
## ends of a ramp instead of the two sides of a step.
var corner_a := 1.0
var mid_a := 0.46
## Half-diagonal of the corner diamonds, px. 0 hides them.
var pip := 4.0

var tint := Color(0.82, 0.66, 0.30, 0.55)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


static func make(frame_color: Color) -> Control:
	var n = (load("res://scripts/ui/painters/PageBorder.gd") as GDScript).new()
	n.name = "Frame"
	n.tint = frame_color
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Above all sibling UI regardless of add order, as the rects were.
	n.z_as_relative = false
	n.z_index = 10
	return n


## Emphasis at a point `d` px from the nearer end of a run: 1 at the corner,
## decaying to 0 by `corner_run`. Smoothstepped, because a linear ramp reads as a
## flat wash with an edge — which is the step this whole file exists to delete,
## reintroduced more gently.
func _emph(d: float) -> float:
	var x := clampf(d / maxf(corner_run, 1.0), 0.0, 1.0)
	var e := 1.0 - x
	return e * e * (3.0 - 2.0 * e)


func _draw() -> void:
	if size.x < 80.0 or size.y < 80.0:
		return
	var r := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	var base: Color = PlateFrame.body_colour({
		"metal": Color(tint.r, tint.g, tint.b, 1.0),
		"alloy_mix": 0.0, "body_drop": 0.34})
	var lv := Vector2(cos(PI * 1.25), sin(PI * 1.25))
	# Clockwise, so the outward normal is (b.y-a.y, a.x-b.x) — the one winding
	# convention shared with `PlateFrame._runs` and `_oct`.
	var runs := [
		[r.position, Vector2(r.end.x, r.position.y)],
		[Vector2(r.end.x, r.position.y), r.end],
		[r.end, Vector2(r.position.x, r.end.y)],
		[Vector2(r.position.x, r.end.y), r.position]]
	for pair in runs:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var along := (b - a).normalized()
		var n := Vector2(b.y - a.y, a.x - b.x).normalized()
		var inward := -n
		var lam := n.dot(lv)
		var length := a.distance_to(b)
		var cols: Array[Color] = []
		for i in range(SLICES + 1):
			cols.append(PlateFrame.profile_at(float(i) / float(SLICES), lam, base,
				Color(1.0, 0.92, 0.72), 0.55, 0.80, 0.20))
		for i in range(SLICES):
			var d0 := rule_w * float(i) / float(SLICES)
			var d1 := rule_w * float(i + 1) / float(SLICES)
			for k in range(NODES):
				var t0 := float(k) / float(NODES)
				var t1 := float(k + 1) / float(NODES)
				# ONE continuous ramp per edge. The corner accent is still here —
				# it is just a gradient now, so there is no joint to see.
				var e0 := maxf(_emph(t0 * length), _emph((1.0 - t0) * length))
				var e1 := maxf(_emph(t1 * length), _emph((1.0 - t1) * length))
				var a0: float = tint.a * lerpf(mid_a, corner_a, e0)
				var a1: float = tint.a * lerpf(mid_a, corner_a, e1)
				var ca := cols[i]
				var cb := cols[i + 1]
				draw_polygon(
					PackedVector2Array([
						a.lerp(b, t0) + inward * d0, a.lerp(b, t1) + inward * d0,
						a.lerp(b, t1) + inward * d1, a.lerp(b, t0) + inward * d1]),
					PackedColorArray([
						Color(ca.r, ca.g, ca.b, ca.a * a0),
						Color(ca.r, ca.g, ca.b, ca.a * a1),
						Color(cb.r, cb.g, cb.b, cb.a * a1),
						Color(cb.r, cb.g, cb.b, cb.a * a0)]))
	# THE CORNER PIPS, as actual diamonds and actually lit. The old ones were
	# axis-aligned squares of a flat `frame_color * 1.4`; a rotated quad costs the
	# same four points and reads as a set stone, and giving its up-left vertex the
	# lamp and its down-right vertex the shadow makes it a solid rather than a dot.
	if pip > 0.0:
		var hot: Color = base.lerp(Color(1.0, 0.92, 0.72), 0.62)
		var cold: Color = Color(base.r * 0.45, base.g * 0.45, base.b * 0.45, base.a)
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end,
				Vector2(r.position.x, r.end.y)]:
			draw_polygon(
				PackedVector2Array([
					c + Vector2(0, -pip), c + Vector2(pip, 0),
					c + Vector2(0, pip), c + Vector2(-pip, 0)]),
				PackedColorArray([
					Color(hot.r, hot.g, hot.b, tint.a),
					Color(base.r, base.g, base.b, tint.a),
					Color(cold.r, cold.g, cold.b, tint.a),
					Color(hot.r, hot.g, hot.b, tint.a)]))
