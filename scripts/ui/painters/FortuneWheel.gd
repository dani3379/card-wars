## FortuneWheel — the roadside stage's wheel of fortune: an upright carnival
## wheel of tinted, weighted slices spun under a fixed top pointer. The odds
## are drawn INTO the wheel — a wider slice is a more likely (and cheaper)
## call, so reading the wheel's slice widths is reading the table's payouts.
## Pure painter, no motion of its own: the Event scene owns the spin, tweening
## `angle` to turn the wheel and setting `highlight_index` to call the winner;
## this file only ever redraws from whatever state it's handed.
extends Control

## Each entry: {"tint": Color, "weight": float, "label": String}. A slice's
## angular share is weight / sum(all weights) — the WIDER the slice, the more
## often it lands, by construction; the game prices that slice's payout down
## to match. `label` is carried for the caller's own legend/readout; this
## painter draws the dial, not the copy.
var segments: Array = []:
	set(v):
		segments = v
		queue_redraw()

## ANGLE CONVENTION (read this before driving the wheel):
##   * Segments are laid out CLOCKWISE around the dial in array order.
##   * `angle == 0.0` puts the CENTER of segments[0] directly under the
##     fixed top pointer (12 o'clock).
##   * Increasing `angle` spins the wheel CLOCKWISE, i.e. it rotates a LATER
##     segment up to meet the pointer.
## Use `center_angle_of(i)` to get the `angle` that calls segment i, and
## `top_index()` to read which segment the CURRENT `angle` calls. They are
## exact inverses by construction: `top_index()` evaluated while
## `angle == center_angle_of(k)` always returns `k`.
var angle: float = 0.0:
	set(v):
		angle = v
		queue_redraw()

## Index of the slice the spin landed on, or -1 for none yet. The called
## slice is lightened and haloed so the result reads without a caption.
var highlight_index: int = -1:
	set(v):
		highlight_index = v
		queue_redraw()

## Seeds the rim's rivet placement so repeated wheels don't look identical.
var seed_text: String = "wheel"

const RIM_INK := Color(0.24, 0.16, 0.07, 0.95)
const BRONZE_LIT := Color(0.86, 0.68, 0.36)
const BRONZE_MID := Color(0.64, 0.48, 0.24)
const BRONZE_DIM := Color(0.40, 0.29, 0.14)
const HUB_LIT := Color(0.80, 0.62, 0.32)
const GLINT := Color(1.0, 0.96, 0.82)
const POINTER_GOLD := Color(0.95, 0.80, 0.30)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ── angle bookkeeping ───────────────────────────────────────────────────────
# All of this works in one private frame: "natural" angles, measured CLOCKWISE
# FROM TOP (0 = straight up, increasing = clockwise), with segment 0 STARTING
# at natural angle 0 and the rest following in array order. `angle == 0` does
# NOT mean "natural frame == drawn frame" — it means segment 0's own CENTER
# (not its start) sits at the pointer, so every drawn angle is the natural
# angle shifted by `_base_offset()` and then by the live spin `angle`.

## Per-segment [start, end) in the natural (pre-offset) clockwise-from-top
## frame. starts[0] is always 0.0.
func _natural_bounds() -> Dictionary:
	var starts := PackedFloat32Array()
	var ends := PackedFloat32Array()
	var total := 0.0
	for seg in segments:
		total += maxf(0.0001, float(seg.get("weight", 1.0)))
	var cum := 0.0
	for seg in segments:
		var w: float = maxf(0.0001, float(seg.get("weight", 1.0)))
		starts.append(cum / total * TAU)
		cum += w
		ends.append(cum / total * TAU)
	return {"starts": starts, "ends": ends}


## The natural-frame angle of segment 0's own center — subtracting this from
## any natural angle is what pins segment 0's center to the pointer at
## `angle == 0`.
func _base_offset(b: Dictionary) -> float:
	if segments.is_empty():
		return 0.0
	var starts: PackedFloat32Array = b["starts"]
	var ends: PackedFloat32Array = b["ends"]
	return (starts[0] + ends[0]) * 0.5


## Returns the `angle` that centers segment `index` under the pointer.
## Normalized to [0, TAU) — add whole TAU multiples yourself for a spin
## that visibly turns several times before landing.
func center_angle_of(index: int) -> float:
	if index < 0 or index >= segments.size():
		return 0.0
	var b := _natural_bounds()
	var starts: PackedFloat32Array = b["starts"]
	var ends: PackedFloat32Array = b["ends"]
	var base_offset := _base_offset(b)
	var center_i: float = (starts[index] + ends[index]) * 0.5
	return fposmod(base_offset - center_i, TAU)


## Returns which segment is currently under the pointer for the live `angle`.
func top_index() -> int:
	if segments.is_empty():
		return -1
	var b := _natural_bounds()
	var starts: PackedFloat32Array = b["starts"]
	var ends: PackedFloat32Array = b["ends"]
	var base_offset := _base_offset(b)
	var theta := fposmod(base_offset - angle, TAU)
	for i in range(segments.size()):
		if theta >= starts[i] and theta < ends[i]:
			return i
	return segments.size() - 1


# ── drawing helpers ─────────────────────────────────────────────────────────

## Unit direction for a clockwise-from-top angle: 0 -> up, TAU/4 -> right.
func _dir_from_top(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))


func _arc_points(center: Vector2, radius: float, a0: float, a1: float,
		n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a: float = lerpf(a0, a1, float(i) / float(n))
		pts.append(center + _dir_from_top(a) * radius)
	return pts


func _draw_shadow(c: Vector2, R: float) -> void:
	var base := c + Vector2(0, R * 0.94)
	var pts := PackedVector2Array()
	for i in range(33):
		var a: float = TAU * float(i) / 32.0
		pts.append(base + Vector2(cos(a) * R * 1.05, sin(a) * R * 0.24))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))


## Soft warm halo bleeding just past the rim over the winning slice's span —
## drawn FIRST so the crisp rim/hub print cleanly over its outer edge.
func _draw_glow(c: Vector2, R: float, a0: float, a1: float, tint: Color) -> void:
	var mid_col := tint.lerp(Color(1.0, 0.92, 0.65), 0.5)
	var pad := 0.06
	for i in range(4):
		var t: float = float(i) / 3.0
		var rad: float = R * (1.03 + 0.16 * t)
		var a: float = 0.32 * (1.0 - t)
		var pts := _arc_points(c, rad, a0 - pad, a1 + pad, 20)
		draw_polyline(pts, Color(mid_col.r, mid_col.g, mid_col.b, a),
			maxf(3.0, R * 0.05) * (1.0 - t * 0.5), true)


func _draw_hub(c: Vector2, r_hub: float) -> void:
	draw_circle(c, r_hub, BRONZE_DIM, true, -1.0, true)
	draw_circle(c, r_hub * 0.86, BRONZE_MID, true, -1.0, true)
	draw_circle(c + Vector2(-r_hub * 0.18, -r_hub * 0.22), r_hub * 0.46,
		HUB_LIT, true, -1.0, true)
	draw_polyline(_arc_points(c, r_hub, 0.0, TAU, 40), RIM_INK,
		maxf(1.4, r_hub * 0.12), true)
	# Rivets mounted to the spinning hub, so they turn with `angle`.
	for k in range(3):
		var ra: float = angle + TAU * float(k) / 3.0 + 0.4
		var rp: Vector2 = c + _dir_from_top(ra) * r_hub * 0.58
		draw_circle(rp, maxf(1.4, r_hub * 0.14), BRONZE_DIM, true, -1.0, true)
		draw_circle(rp + Vector2(-0.6, -0.6), maxf(0.8, r_hub * 0.07),
			Color(GLINT.r, GLINT.g, GLINT.b, 0.5), true, -1.0, true)
	draw_polyline(_arc_points(c, r_hub * 0.7, -2.1, -0.9, 10),
		Color(GLINT.r, GLINT.g, GLINT.b, 0.5), maxf(1.2, r_hub * 0.1), true)


## The fixed reading marker. Deliberately independent of `angle` — the game's
## motion only ever spins the dial under it.
func _draw_pointer(c: Vector2, R: float) -> void:
	var tip: Vector2 = c + Vector2(0, -R * 0.98)
	var w: float = R * 0.24
	var h: float = R * 0.24
	var pts := PackedVector2Array([
		tip,
		tip + Vector2(-w * 0.5, -h),
		tip + Vector2(w * 0.5, -h),
	])
	draw_colored_polygon(pts, POINTER_GOLD)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, RIM_INK, maxf(1.8, R * 0.035), true)
	# One thin lit edge so the gold reads as struck metal, not a flat sticker.
	draw_line(tip, tip + Vector2(-w * 0.5, -h), Color(GLINT.r, GLINT.g, GLINT.b, 0.5),
		maxf(1.0, R * 0.015), true)
	draw_circle(tip + Vector2(0, -h * 0.14), maxf(1.8, R * 0.04), RIM_INK, true, -1.0, true)


func _draw() -> void:
	if segments.is_empty():
		return
	var R: float = minf(size.x, size.y) * 0.5 * 0.86
	if R <= 6.0:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.47)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	var b := _natural_bounds()
	var starts: PackedFloat32Array = b["starts"]
	var ends: PackedFloat32Array = b["ends"]
	var base_offset := _base_offset(b)
	var n_seg := segments.size()

	var r_hub: float = R * 0.20
	var r_slice: float = R * 0.90

	_draw_shadow(c, R)

	# Halo for the called slice, behind everything else.
	if highlight_index >= 0 and highlight_index < n_seg:
		var hs: float = starts[highlight_index] - base_offset + angle
		var he: float = ends[highlight_index] - base_offset + angle
		var htint: Color = segments[highlight_index].get("tint", BRONZE_LIT)
		_draw_glow(c, R, hs, he, htint)

	# ── pie slices, each a wedge from the hub out to r_slice ────────────────
	for i in range(n_seg):
		var seg: Dictionary = segments[i]
		var tint: Color = seg.get("tint", BRONZE_MID)
		var drawn_start: float = starts[i] - base_offset + angle
		var drawn_end: float = ends[i] - base_offset + angle
		var span: float = ends[i] - starts[i]
		var n_pts: int = clampi(int(span / TAU * 64.0) + 2, 2, 64)
		var fill := tint
		if i == highlight_index:
			fill = tint.lerp(Color(1.0, 0.97, 0.85), 0.45)
		var pts := PackedVector2Array()
		pts.append(c)
		pts.append_array(_arc_points(c, r_slice, drawn_start, drawn_end, n_pts))
		draw_colored_polygon(pts, fill)

	# ── dark ink separators between adjacent slices (kept even when a slice
	# is very thin, so its boundary still reads) ────────────────────────────
	for i in range(n_seg):
		var a: float = starts[i] - base_offset + angle
		var dir := _dir_from_top(a)
		draw_line(c + dir * r_hub * 0.5, c + dir * r_slice,
			RIM_INK, maxf(1.6, R * 0.02), true)

	# ── outer bronze rim ring: annulus (outer loop + reversed inner loop),
	# two tone bands, and dark ink edges top and bottom ─────────────────────
	var outer := _arc_points(c, R, 0.0, TAU, 72)
	var inner := _arc_points(c, r_slice, 0.0, TAU, 72)
	inner.reverse()
	var ring := outer.duplicate()
	ring.append_array(inner)
	draw_colored_polygon(ring, BRONZE_MID)
	draw_polyline(_arc_points(c, lerpf(r_slice, R, 0.35), 0.0, TAU, 72),
		BRONZE_LIT, maxf(2.0, R * 0.05), true)
	draw_polyline(_arc_points(c, R * 0.97, 0.0, TAU, 72),
		BRONZE_DIM, maxf(1.5, R * 0.03), true)
	draw_polyline(outer, RIM_INK, maxf(1.6, R * 0.035), true)
	draw_polyline(_arc_points(c, r_slice, 0.0, TAU, 72), RIM_INK,
		maxf(1.4, R * 0.025), true)

	# ── rivets on the rim at each slice boundary, mid-band ──────────────────
	for i in range(n_seg):
		var a: float = starts[i] - base_offset + angle
		var dir := _dir_from_top(a)
		var rp := c + dir * (r_slice + R) * 0.5
		draw_circle(rp, maxf(2.0, R * 0.028), BRONZE_DIM, true, -1.0, true)
		draw_circle(rp + Vector2(-0.5, -0.5), maxf(1.0, R * 0.014),
			BRONZE_LIT, true, -1.0, true)

	# ── one fixed specular arc so the metal reads as lit from one side;
	# stays screen-fixed (ambient light), not tied to the spin ─────────────
	draw_polyline(_arc_points(c, R * 0.965, -2.5, -1.3, 24),
		Color(GLINT.r, GLINT.g, GLINT.b, 0.4), maxf(1.6, R * 0.045), true)

	# ── hub boss, covering the wedge points ─────────────────────────────────
	_draw_hub(c, r_hub)

	# ── the fixed top pointer, drawn last so it always reads over the dial ──
	_draw_pointer(c, R)
