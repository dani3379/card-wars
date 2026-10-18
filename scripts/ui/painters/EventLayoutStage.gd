extends Control
class_name EventLayoutStage
## Shared composition furniture for ordinary event pages.  The illustration
## remains the star; this painter only pools readable ink and gives each event
## family a different physical silhouette.

var layout: String = "folio"
var accent: Color = Color(0.78, 0.58, 0.24)
var reveal: float = 0.0:
	set(value):
		reveal = value
		queue_redraw()
var attention: float = 0.0:
	set(value):
		attention = value
		queue_redraw()

## Where the head copy actually ends, in design px. The top ink band used to be
## a guessed constant (182 ritual / 190 location) while the description rect ran
## to y=232 — so a three-line paragraph printed its last line BELOW the band, on
## the lit painting, with the hard seam running between line 2 and line 3. The
## band is now authored from the measured text: Event.gd reports the copy's real
## bottom once it has laid out, and the pool is cut to fit it.
var copy_bottom: float = 190.0:
	set(value):
		copy_bottom = value
		queue_redraw()

const BAND_FEATHER := 96.0
## The location rail sits just above the choice row so the tiles hang from the
## road instead of being crossed by it.
const ROUTE_RAIL_Y := 636.0
## The ritual seal's centre, low enough that its rim passes through the choice
## row rather than ringing the painting's focal point. Wide and shallow because
## it lies on the ground under the player's feet.
## Sized so the outer rim closes INSIDE the canvas (y 792+104 = 896 of 900,
## x 800±660 = 140..1460 of 1600). A ring clipped by the frame edge reads as a
## drawing error rather than as ground.
const SEAL_CENTRE := Vector2(800, 792)
const SEAL_RX := 660.0
const SEAL_RY := 104.0

## Design-space y where the bargain ledger's last entry ends.
var ledger_bottom: float = 828.0:
	set(value):
		ledger_bottom = value
		queue_redraw()

## Design-space x of each choice tile's centre, reported after the row lays out.
var route_stops: PackedFloat32Array = PackedFloat32Array():
	set(value):
		route_stops = value
		queue_redraw()


func configure(kind: String, color: Color) -> void:
	layout = kind
	accent = color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ...AND_OFFSETS. `configure()` is called after this node is in the tree, and
	# bare `set_anchors_preset` preserves the CURRENT rect by rewriting the offsets
	# — so a node still sized 0x0 anchors itself to nothing and never draws. This is
	# the same defect that left ClashLaneFocus invisible for its entire life; caught
	# in the same sweep. Harmless where the node is already sized, fatal where it
	# is not, so prefer this form on principle.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reveal = 1.0 if UserSettings.reduce_motion else 0.0
	if not UserSettings.reduce_motion:
		var tween := create_tween()
		tween.tween_property(self, "reveal", 1.0, 0.34) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _ink(alpha: float) -> Color:
	return Color(0.025, 0.018, 0.014, alpha * reveal)


func _rule(alpha: float) -> Color:
	return Color(accent.r, accent.g, accent.b, alpha * reveal * (1.0 + attention * 0.55))


## Ink pools must never end on a razor. A flat `draw_rect` scrim cuts a
## hard-edged line straight across the painting — at 3200x1800 the art visibly
## steps from 58% darkened to full brightness across a single pixel row, and the
## band reads as a letterbox bar laid over the picture rather than as light
## falling off. Every pool below is therefore a solid core plus a feathered
## shoulder: `draw_polygon` interpolates per-vertex colours, and a quad whose
## top pair and bottom pair each share an alpha gives an exact linear ramp
## through both triangles of the split.
func _pool_v(x: float, w: float, solid_from: float, solid_to: float,
		fade_to: float, alpha: float) -> void:
	if absf(solid_to - solid_from) > 0.5:
		draw_rect(Rect2(x, minf(solid_from, solid_to), w,
			absf(solid_to - solid_from)), _ink(alpha))
	_ramp(Rect2(x, minf(solid_to, fade_to), w, absf(fade_to - solid_to)),
		alpha if fade_to > solid_to else 0.0,
		0.0 if fade_to > solid_to else alpha)


func _pool_h(y: float, h: float, solid_from: float, solid_to: float,
		fade_to: float, alpha: float) -> void:
	if absf(solid_to - solid_from) > 0.5:
		draw_rect(Rect2(minf(solid_from, solid_to), y,
			absf(solid_to - solid_from), h), _ink(alpha))
	_ramp_h(Rect2(minf(solid_to, fade_to), y, absf(fade_to - solid_to), h),
		alpha if fade_to > solid_to else 0.0,
		0.0 if fade_to > solid_to else alpha)


func _ramp(rect: Rect2, a_top: float, a_bottom: float) -> void:
	if rect.size.y <= 0.5 or rect.size.x <= 0.5:
		return
	draw_polygon(PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0.0),
		rect.end, rect.position + Vector2(0.0, rect.size.y)
	]), PackedColorArray([
		_ink(a_top), _ink(a_top), _ink(a_bottom), _ink(a_bottom)
	]))


func _ramp_h(rect: Rect2, a_left: float, a_right: float) -> void:
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		return
	draw_polygon(PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0.0),
		rect.end, rect.position + Vector2(0.0, rect.size.y)
	]), PackedColorArray([
		_ink(a_left), _ink(a_right), _ink(a_right), _ink(a_left)
	]))


func _draw() -> void:
	if reveal <= 0.001:
		return
	match layout:
		"character":
			_draw_character()
		"confrontation":
			_draw_confrontation()
		"location":
			_draw_location()
		"bargain":
			_draw_bargain()
		"ritual":
			_draw_ritual()
	if attention > 0.001:
		_draw_attention_echo()


func _draw_character() -> void:
	# Character stage at left, one continuous conversation column at right.
	# The old full-width reply rail made the painting feel like wallpaper and
	# separated the answers from the prose that gave them meaning.
	_pool_h(0, 900, 1600, 960, 790, 0.86)
	draw_line(Vector2(958, 70), Vector2(958, 830), _rule(0.58), 2.0)
	draw_line(Vector2(976, 70), Vector2(1048, 70), _rule(0.58), 2.0)
	draw_line(Vector2(976, 830), Vector2(1048, 830), _rule(0.58), 2.0)
	# Ground the figure like a speaking portrait without boxing the art in.
	draw_line(Vector2(92, 796), Vector2(660, 796), _rule(0.24), 1.0)
	draw_circle(Vector2(92, 796), 4.0, _rule(0.62))

func _draw_confrontation() -> void:
	# Legacy confrontation art was authored for a right-side portrait field and
	# keeps its horizontal reply rail until that painting is recomposed.
	_pool_h(0, 900, 0, 640, 980, 0.68)
	_pool_v(0, 1600, 900, 650, 560, 0.72)
	draw_line(Vector2(742, 70), Vector2(742, 555), _rule(0.52), 2.0)
	draw_line(Vector2(760, 70), Vector2(828, 70), _rule(0.52), 2.0)
	draw_line(Vector2(760, 555), Vector2(828, 555), _rule(0.52), 2.0)


func _draw_location() -> void:
	# The centre stays open as a landscape.  Copy becomes a cartouche above it
	# and the available roads become a route rail along the bottom.
	var head := maxf(copy_bottom + 16.0, 150.0)
	_pool_v(0, 1600, 0, head, head + BAND_FEATHER, 0.58)
	_pool_v(0, 1600, 900, 654, 558, 0.74)
	# The route rail rides ABOVE the tiles as the road they hang off. Drawn at
	# y=708 it ran straight THROUGH every choice, surfacing in the gutters as a
	# stray line, and its five fixed stops never matched the choice count — on a
	# three-choice event a stop landed dead on the middle headline's letterforms.
	# Stops are now reported by Event.gd once the row has laid out, so each mark
	# sits over the tile it belongs to; with no report, the road stays unmarked.
	draw_line(Vector2(120, ROUTE_RAIL_Y), Vector2(1480, ROUTE_RAIL_Y), _rule(0.42), 2.0)
	for x in route_stops:
		draw_circle(Vector2(x, ROUTE_RAIL_Y), 5.0, _rule(0.72))
		draw_line(Vector2(x, ROUTE_RAIL_Y + 4.0), Vector2(x, ROUTE_RAIL_Y + 22.0),
			_rule(0.34), 1.0)
	draw_arc(Vector2(800, 110), 58.0, PI, TAU, 28, _rule(0.30), 2.0)


func _draw_bargain() -> void:
	# A ledger/table field: description above, contracts below, rival or object
	# still visible at right.  The central double rule reads as a folded account.
	_pool_h(0, 900, 0, 980, 1210, 0.66)
	draw_line(Vector2(90, 314), Vector2(960, 314), _rule(0.48), 2.0)
	draw_line(Vector2(90, 322), Vector2(960, 322), _rule(0.20), 1.0)
	# No centre divider. It was drawn for a two-column contract grid, but the
	# offers stack as single-column ledger entries, so the rule ran straight
	# through the middle of every tile.
	# The ruled margin the entries hang off — an account's left edge. It ends
	# where the account does; the old fixed 828 left a rule hanging into empty
	# page below the last entry whenever an event had fewer than four offers.
	draw_line(Vector2(90, 338), Vector2(90, ledger_bottom), _rule(0.30), 1.0)
	# Small balance mark above the contract field.
	draw_line(Vector2(480, 274), Vector2(566, 274), _rule(0.62), 2.0)
	draw_line(Vector2(523, 246), Vector2(523, 292), _rule(0.62), 2.0)
	draw_arc(Vector2(492, 282), 17.0, 0.1, PI - 0.1, 18, _rule(0.46), 2.0)
	draw_arc(Vector2(554, 282), 17.0, 0.1, PI - 0.1, 18, _rule(0.46), 2.0)


func _draw_ritual() -> void:
	# A clear occult/ceremonial centre replaces the document silhouette.  The
	# action seals sit on an arc below it and remain readable over a pooled foot.
	var head := maxf(copy_bottom + 16.0, 150.0)
	_pool_v(0, 1600, 0, head, head + BAND_FEATHER, 0.56)
	_pool_v(0, 1600, 900, 634, 538, 0.73)
	# The seal is the FLOOR the choices stand on, not a reticle behind the art.
	# Centred at (800,430) it ringed whatever the painting had put in the middle
	# of frame — a hooded figure's chest, a skull's brow — and its solid centre
	# pip was the brightest mark on the screen, reading as a stuck cursor. It now
	# sits low, large enough that its rim runs through the choice row, so the
	# answers are stones set in a circle and the rite is the ground, not a target.
	# Drawn as a circle on the GROUND, not a disc facing the camera: the house
	# camera is a cabinet projection, so a ring lying on the floor is an ellipse.
	# A warm ring also vanishes over warm art (the Scapegoat's blaze swallowed
	# the old one whole), so every rim gets a dark under-stroke and survives on a
	# lit painting as well as a dark one.
	# Two rims, not three: at the ellipse's flanks three concentric rings converge
	# into a bunched moiré cluster instead of reading as a circle.
	for scale in [1.0, 0.72]:
		_ground_ring(SEAL_RX * scale, SEAL_RY * scale, 0.34)
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		var inner := SEAL_CENTRE + Vector2(dir.x * SEAL_RX * 0.72, dir.y * SEAL_RY * 0.72)
		var outer := SEAL_CENTRE + Vector2(dir.x * SEAL_RX, dir.y * SEAL_RY)
		draw_line(inner, outer, Color(0, 0, 0, 0.30 * reveal), 4.0)
		draw_line(inner, outer, _rule(0.26), 2.0)


func _ground_ring(rx: float, ry: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in 97:
		var a := TAU * float(i) / 96.0
		pts.append(SEAL_CENTRE + Vector2(cos(a) * rx, sin(a) * ry * reveal))
	draw_polyline(pts, Color(0, 0, 0, alpha * reveal), 4.0)
	draw_polyline(pts, _rule(alpha), 2.0)


## Design-space y at which a choice tile's TOP should sit so the row follows the
## seal's near rim. Event.gd seats the ritual devices with this, which is what
## turns the old flat 15-px "arc offset" (it read as three boxes that failed to
## align) into stones genuinely set around a circle.
static func seal_rim_y(centre_x: float, tile_height: float) -> float:
	var t := clampf(absf(centre_x - SEAL_CENTRE.x) / SEAL_RX, 0.0, 1.0)
	return SEAL_CENTRE.y - SEAL_RY * sqrt(1.0 - t * t) - tile_height * 0.5


func set_attention(active: bool) -> void:
	var target := 1.0 if active else 0.0
	if UserSettings.reduce_motion:
		attention = target
		return
	var tween := create_tween()
	tween.tween_property(self, "attention", target, 0.18 if active else 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _draw_attention_echo() -> void:
	var centre := Vector2(800, 430)
	match layout:
		"character": centre = Vector2(480, 380)
		"confrontation": centre = Vector2(1120, 355)
		"bargain": centre = Vector2(1210, 430)
		"location": centre = Vector2(800, 435)
		"ritual": centre = Vector2(800, 430)
	# A SOFT BAND, NOT A WIRE (2026-09-10). This was ONE 3px arc — a hairline
	# circle, the exact defect the combat ring engine was rebuilt to remove —
	# and because it swells with `attention` it read as a loading spinner rather
	# than as focus. It survived every circle sweep because the call is split
	# across two lines and the width never reached the check; the hunt reads
	# continuation lines now.
	#
	# There is no shader to reach for inside an immediate-mode `_draw()`, so the
	# falloff is built the cheap way: concentric passes widening and fading
	# outward, which is by hand what the ring shader's band does analytically.
	var radius := lerpf(74.0, 104.0, attention)
	for pass_i in 4:
		var k := float(pass_i)
		draw_arc(centre, radius + k * 2.6, 0.0, TAU, 48,
			Color(accent.r, accent.g, accent.b,
				0.20 * attention / (1.0 + k * 1.6)), 3.0 + k * 3.6)
	# FILLED, not outlined. An outlined disc here was a second tiny wire circle
	# sitting inside the first one.
	draw_circle(centre, 10.0 + attention * 5.0,
		Color(accent.r, accent.g, accent.b, 0.13 * attention))