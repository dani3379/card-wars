## StruckBracket — the lane forecast's target mark (2026-09-16).
##
## IT REPLACES A CIRCLE, AND THE CIRCLE WAS WRONG TWICE OVER.
##
## The always-on forecast drew a 50px `Motion.ring_static` band centred on the
## body. Measured against a 200x150 battlefield token whose painting runs
## effectively edge to edge, a 100px circle centred on it can only ever be drawn
## ACROSS THE PICTURE — there is nowhere else for it to be. That is the same
## defect the chip had, in a different spelling.
##
## The second fault is the one this project already wrote down and then rebuilt
## the circle anyway. From the FX rebuild's own commit, on the card-offer shine:
## "A ring moving around a thing says 'selected' far louder than it says
## 'uncommon', so it was ugly AND it was lying." A ring around a creature says
## SELECTED. Nothing is selected during the planning phase; a blow is coming.
##
## A bracket says the other thing. Four corner ticks are the registration mark a
## gunsight, a surveyor's plate and every tactics game in the genre use for "this
## one, here" — and being corners, they sit ON the token's border, which is the
## only ground on a battlefield token that is not somebody's face.
##
## THREE CHANNELS, NONE OF THEM COLOUR ALONE (the project's accessibility floor,
## already applied to damage numerals via GameTheme.cb_color):
##   * WEIGHT   — a lethal bracket is drawn heavier.
##   * REACH    — a lethal bracket's arms run further down each edge.
##   * COUNT    — a lethal bracket DOUBLES each tick, the way a draughtsman
##                doubles a register mark that matters. Shape at a glance with
##                the hue switched off entirely. (Two earlier attempts used an
##                inward diagonal barb instead; both photographed as an arrow
##                shot into the card. See the note at the call site.)
##
## The arms are TAPERED QUADS rather than `draw_line`. A line is uniform across
## its width with two hard edges — the precise reason the FX pass found every
## effect in this game "looked like a line" — and a mark that is heaviest at the
## corner and thins along the edge reads as struck by a hand with a tool, which
## is what the war table's whole visual argument rests on. Each arm carries a
## dark offset halo underneath (the StatCaret idiom) so the mark survives a pale
## painting without needing a plate behind it.
extends Control

const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

## How far inboard the lethal tick's SECOND rule is struck, in arm thicknesses.
## Swept against `tools/_shot_forecast.tscn`'s two oracles — the target is
## painting 0 / seal 0, not a look.
const DOUBLE_RULE_GAP := 0.55

var col := Color(0.98, 0.72, 0.32)
var lethal := false
var weight := 1.0                  # extra multiplier for emphasis
var seed_text := "bracket"
## Which edge the blow arrives from: -1 none, 0 top, 1 bottom. The two corners on
## that edge are drawn longer, so the mark points back along the lane at the body
## that is about to swing — the direction cue the old connector line spent a
## whole curved wire to deliver.
var struck_edge := -1
## How far the Control was inflated PAST the token it marks. The arms are a
## fraction of the thing being bracketed, not of the box drawn around it — see
## `_draw`. Left at 0 the bracket behaves exactly as it did.
var outset := 0.0

## WHERE THIS MARK ACTUALLY PUTS INK. A bracket's Control is the whole token —
## it has to be, the corners are at the corners — but it PAINTS only four short
## ticks, so measuring its bounding rect answers a question nobody asked. An
## overlap oracle that used the rect reported a bracket as covering 100% of a
## card's stat seal when the ink misses it entirely.
##
## Accumulated BY `_arm` while drawing, so there is exactly one statement of the
## geometry. A second computation here would be the duplicate-rule pathology
## this codebase has paid for more than once.
var _ink: Array[Rect2] = []


## The arms' bounding rects in GLOBAL space, for anything measuring what this
## mark covers. Empty until the node has drawn once.
func ink_rects() -> Array:
	var out: Array = []
	var o := global_position
	for r in _ink:
		out.append(Rect2(o + r.position, r.size))
	return out


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	_ink.clear()
	if size.x <= 4.0 or size.y <= 4.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)

	# TUNED DOWN HARD off the first render (2026-09-16). At reach 0.21/0.30 the
	# four corners nearly closed into a frame, and a frame round a card is the
	# "selected" read this mark exists to avoid — the same trap in a third
	# spelling. A corner tick has to be unmistakably a CORNER, which means short.
	# THICKER THAN A HAIRLINE ON PURPOSE (2026-09-17). A 2.8px arm has no room for
	# a bevel, a shine or an inner edge — every layer-style pass collapses onto
	# the same two pixels — so the mark could only ever be a flat stroke with a
	# dark copy behind it, which is exactly what "the rings were ugly" was about.
	# An icon needs AREA before it can be lit.
	var thick: float = (5.4 if lethal else 4.0) * weight
	var reach: float = (0.155 if lethal else 0.115) * weight
	# THE ARMS ARE A FRACTION OF THE TOKEN, NOT OF THE BOX DRAWN AROUND IT
	# (2026-09-24). They used to read `size.x * reach`, and `size` is the rect
	# Combat inflates by `FORECAST_BRACKET_OUTSET` — so pushing the bracket
	# outboard to clear the card's stat seals grew the arms by the same
	# proportion and they reached straight back over them. Measured: sweeping
	# the outset 3 -> 4 -> 5 -> 6 left the seal oracle pinned at 13%, because
	# the two were the same dial. Subtracting the outset decouples them.
	var inner := Vector2(maxf(size.x - outset * 2.0, 1.0),
		maxf(size.y - outset * 2.0, 1.0))
	var arm_x: float = inner.x * reach
	var arm_y: float = inner.y * reach * 1.30     # the short edge earns more

	for cx in [0, 1]:
		for cy in [0, 1]:
			var corner := Vector2(size.x if cx == 1 else 0.0,
				size.y if cy == 1 else 0.0)
			var sx: float = -1.0 if cx == 1 else 1.0
			var sy: float = -1.0 if cy == 1 else 1.0
			# The struck edge's corners reach further — a hand bears down where
			# the blow is coming from.
			var emph := 1.0
			if struck_edge == 0 and cy == 0:
				emph = 1.45
			elif struck_edge == 1 and cy == 1:
				emph = 1.45
			# A seeded wobble of a pixel or so. Four mathematically perfect
			# corners read as CAD; this is meant to look struck.
			#
			# BIASED OUTBOARD (2026-09-24), and that is what makes the clearance
			# a fact rather than a coin-flip. The wobble used to run ±1.3px in
			# both directions, so on any given draw a corner could wander that
			# far ONTO the token — and `seed_text` is keyed to
			# `get_instance_id()`, which changes every run. The forecast's own
			# seal oracle duly flickered between 0 and 2 collisions on identical
			# code, which is a measurement you cannot act on. Away from the
			# token only: same amount of hand, none of it on the card.
			var jx := rng.randf() * 1.3 * -sx
			var jy := rng.randf() * 1.3 * -sy
			var o := corner + Vector2(jx, jy)
			_arm(o, Vector2(sx, 0.0), arm_x * emph, thick)
			_arm(o, Vector2(0.0, sy), arm_y * emph, thick)
			if lethal:
				# LETHAL IS A DOUBLED TICK, not a barb. Two attempts at an
				# inward diagonal both photographed as an ARROW shot into the
				# card — clipart, and a direction cue nobody asked for, since
				# the mark is already sitting on the body it is about to happen
				# to. A second rule struck inboard of the first is the register
				# mark a draughtsman doubles when something matters, it cannot
				# be mistaken for an arrow, and it survives colour-blindness on
				# stroke COUNT rather than on hue.
				# STRUCK INBOARD BY ONE RULE, NOT TWO (2026-09-24). At
				# `thick * 2.0` the second rule landed 10.8px inside the
				# bracket's own corner, which on the BOTTOM two corners is
				# squarely on the card's 38px ATK/HP wax seals — the collision
				# the owner reported as the seal "clipping through". One
				# thickness still reads as a doubled register mark and stays on
				# the border where the header says this mark belongs.
				var inb := Vector2(sx, sy) * (thick * DOUBLE_RULE_GAP)
				_arm(o + inb, Vector2(sx, 0.0), arm_x * emph * 0.60, thick * 0.55)
				_arm(o + inb, Vector2(0.0, sy), arm_y * emph * 0.60, thick * 0.55)


## One tapered arm: widest at the corner, easing narrower along the edge.
func _arm(origin: Vector2, dir: Vector2, length: float, thick: float) -> void:
	if length <= 1.0:
		return
	var nrm := Vector2(-dir.y, dir.x)
	var tip := origin + dir * length
	# Record the ink as it is laid down — see `_ink`.
	var half := absf(thick) * 0.5
	_ink.append(Rect2(
		Vector2(minf(origin.x, tip.x) - half, minf(origin.y, tip.y) - half),
		Vector2(absf(tip.x - origin.x) + thick, absf(tip.y - origin.y) + thick)))
	# THE TAPER IS GENTLE ON PURPOSE. At 0.14 the arm came to a needle point and
	# the four corners read as ARROWS shot into the card — a taper steep enough
	# to be a direction cue is steeper than one that just says "struck by hand".
	var quad := PackedVector2Array([
		origin + nrm * thick * 0.5,
		tip + nrm * thick * 0.30,
		tip - nrm * thick * 0.30,
		origin - nrm * thick * 0.5,
	])
	# THE FULL LAYER-STYLE STACK, in Photoshop's own order (see LayerStyle.gd).
	# What was here before was two passes — a dark expanded copy and a flat fill —
	# plus a lit spine that at 0.19 of a 2.8px arm simply washed the whole thing
	# to salmon. Two passes is clip art. This is six:
	#
	#   drop shadow   the arm sits ON the table rather than printed into it
	#   outer glow    THE SHINING — a warm bloom bleeding into the dark wood,
	#                 which is what makes a mark look LIT rather than filled
	#   graded fill   a tonal range across the arm instead of one flat value
	#   shine         a specular sliver along the lit edge
	#   inner shadow  a far wall, so the arm reads as having thickness
	#   bevel         lit rim toward the light, shaded rim away. Always last,
	#                 and the single pass that does the most work here.
	#
	# A keyline stroke is skipped on purpose: a crisp outline drawn over a bevel
	# flattens it straight back into a sticker.
	LayerStyle.draw_shape(self, quad, col, {
		"shadow": true, "shadow_dist": 1.5, "shadow_spread": 1.8,
		"glow": col.lightened(0.20),
		"glow_size": thick * 1.6, "glow_alpha": 0.15,
		# THE INTERIOR PASSES SCALE WITH THE SHAPE, and on an arm this thin they
		# are nearly off. `fill_graded`, `shine` and `bevel` all LIGHTEN, and
		# three lightening passes across four pixels is how the first layer-style
		# cut photographed as pink neon — the exact failure the flat spine had,
		# arrived at from the opposite direction. On a thin stroke the bevel's
		# lit rim IS the highlight; anything else is just washing out the hue
		# that carries the meaning.
		"lift": 0.10,
		"shine": 0.0,
		"inner_shadow": 0.24,
		# 0.30 of the width put a 1.6px lit rim on a 4px arm — 40% of the stroke
		# spent on its own edge, which is another way of saying "lighter".
		"bevel": 0.92, "bevel_depth": maxf(thick * 0.22, 1.2),
	})
