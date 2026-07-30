extends Control
class_name ClosedGround
## CLOSED GROUND — the mark a set-piece's twisted rule leaves on a lane that
## no body of either side may hold (Combat._sp_lane_closed, the "closed_lanes"
## rule in scripts/data/SetPieceDB.gd; The Sunken Road's steep banks are the
## first user).
##
## WHY THIS EXISTS: closed ground is enforced by a GATE, not a hook — the drop
## is simply refused. A refusal the player cannot SEE coming reads as a bug in
## the drag code, not as a rule of the ground, so the lane has to look shut
## before anyone tries it. The despatch states the rule in words; this states
## it in the one place the hand actually goes.
##
## ── THE LESSON THIS PAINTER WAS REWRITTEN FOR (2026-07-20, shot-caught) ──
## v1 filled the slot with a near-black ELLIPSE at 0.90 alpha. On the real
## table it read as a HOLE — four black ovals punched through the board — which
## is precisely the failure CLAUDE.md records against the old carved wells:
## "full-size dark fills: with 16 of them they COVERED the table and the board
## read as a grid of voids." Closed ground is not absence. It is ground you may
## not use, and the chart's own idiom for that is a hatched exclusion inside a
## ruled boundary, with the table material still visible THROUGH it.
##
## So: a rectangular trench that follows the slot (an ellipse reads as a hole,
## a rect reads as a cut), a LIGHT fill so the table shows through, and the
## read carried by the HATCH and the bank lips rather than by darkness.
##
## Colour-blind safe by construction — the read is TEXTURE (dense diagonal
## hatch) and EDGE (the lit bank lips), never hue.

## Seed so two closed lanes in the same fight do not hatch identically —
## hand-drawn exclusion is never mechanically regular.
@export var seed_val: int = 0:
	set(v):
		seed_val = v
		queue_redraw()

# Deliberately light. The table has to stay legible underneath — that is the
# whole correction from v1.
const EARTH := Color(0.10, 0.075, 0.052, 0.42)
const HATCH := Color(0.55, 0.44, 0.28, 0.30)
const HATCH_DARK := Color(0.04, 0.03, 0.02, 0.34)
const LIP := Color(0.62, 0.50, 0.31, 0.72)
const SCREE := Color(0.42, 0.34, 0.22, 0.40)

const INSET := 9.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 4.0 or h <= 4.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5E7 + seed_val * 7919

	var x0: float = INSET
	var x1: float = w - INSET
	var y0: float = INSET
	var y1: float = h - INSET

	# The cut: a rectangular trench following the slot, drawn with a slightly
	# wandering edge so it reads as dug ground rather than a UI rectangle. Light
	# enough that the table's wood and the station gutters still read through.
	var body := PackedVector2Array()
	var steps: int = 7
	for i in range(steps):           # top edge, left → right
		var t: float = float(i) / float(steps - 1)
		body.append(Vector2(lerpf(x0, x1, t), y0 + rng.randf_range(-2.0, 2.0)))
	for i in range(steps):           # bottom edge, right → left
		var t: float = float(i) / float(steps - 1)
		body.append(Vector2(lerpf(x1, x0, t), y1 + rng.randf_range(-2.0, 2.0)))
	draw_colored_polygon(body, EARTH)

	# Exclusion hatch — the surveyor's "not ground you may occupy". Drawn as a
	# light stroke with a dark companion one pixel down, so it reads as INCISED
	# on both the dark war table and the light Battle-Plan field.
	var pitch: float = 13.0
	var span: float = y1 - y0
	var x: float = x0 - span
	while x < x1:
		var a := Vector2(x, y1)
		var b := Vector2(x + span, y0)
		# Trim to the trench box so the hatch never bleeds into the gutter.
		if a.x < x0:
			var k: float = (x0 - a.x) / (b.x - a.x)
			a = a.lerp(b, k)
		if b.x > x1:
			var k2: float = (x1 - a.x) / (b.x - a.x)
			b = a.lerp(b, k2)
		if b.x - a.x > 2.0:
			draw_line(a + Vector2(0, 1.0), b + Vector2(0, 1.0), HATCH_DARK, 1.6, true)
			draw_line(a, b, HATCH, 1.6, true)
		x += pitch

	# The bank lips: a lit rule along the top and bottom edge. This is what
	# makes the trench read as DEPTH rather than as a flat sticker — the eye
	# takes a bright edge above a darker field as a cut seen from above.
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var n: int = 11
	for i in range(n):
		var t: float = float(i) / float(n - 1)
		top.append(Vector2(lerpf(x0, x1, t), y0 + rng.randf_range(-1.4, 1.4)))
		bot.append(Vector2(lerpf(x0, x1, t), y1 + rng.randf_range(-1.4, 1.4)))
	draw_polyline(top, LIP, 2.0, true)
	draw_polyline(bot, LIP, 2.0, true)

	# Scree along the foot of each bank — a few fallen stones. Cheap, and it is
	# the detail that stops the trench reading as a texture swatch.
	for _i in range(7):
		var sx: float = rng.randf_range(x0 + 6.0, x1 - 6.0)
		var sy: float = y0 + rng.randf_range(3.0, 7.0) if rng.randf() < 0.5 \
			else y1 - rng.randf_range(3.0, 7.0)
		draw_circle(Vector2(sx, sy), rng.randf_range(1.0, 2.1), SCREE)
