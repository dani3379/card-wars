## PlaqueStyle — a button drawn as a STRUCK METAL PLAQUE (2026-09-17).
##
## THE DEFECT IS THE LIGHTNING DEFECT AGAIN, AND THIS TIME IT IS THE BUTTONS.
##
## `PlateFrame` landed earlier today, proved that a frame is a solid rather than
## a stroke, and MEASURED it: inversion 0.033 -> 0.343. Then it stopped at
## PICTURES — the hero plate, the opener art tiles, the roster thumbs. Every
## BUTTON in the game is still the flat rule, and a button is the thing a player
## actually points at.
##
## Read what a button's edge is today. `GameTheme.ChartPanelStyle` draws, in
## order: a contour ink seam (one polyline), an edge toast (one polyline), a
## "halo" at whisper alpha (one polyline) and a crisp rule (one polyline). That
## is FOUR STACKED SYMMETRIC BANDS in one colour each — bit for bit the first
## lightning rebuild, which piled halo + bolt + core and got "a thicker hard
## band with a dimmer hard band behind it". `ChartPanelStyle`'s own comment even
## records the symptom without naming the cause: the halo had to be pulled back
## to whisper alpha because on panel-dense screens it "stacked into a global
## brightness lift". Stacking symmetric bands can make a line thicker or
## brighter. It cannot make one into an object.
##
## And there is a SECOND defect a molding does not fix, which is the face. The
## plate's fill is a LINEAR TOP-TO-BOTTOM RAMP. That is how you draw paper under
## a window; it is not how metal behaves, and worse, it is lit from a different
## direction than the edge beside it — a vertical ramp against an up-left-lit
## rule is two objects under two suns on one control, which is precisely the
## "assembled rather than designed" failure `LayerStyle`'s header warns about.
##
## WHAT A BUTTON IS, in this game's material language: a brass plate pinned to
## the war table. Five facts, and they are the whole file.
##
##   1. IT HAS THICKNESS, so its edge is a molding whose light INVERTS between
##      the top run and the bottom run. Shared with `PlateFrame` rather than
##      restated — see `PlateFrame.draw_molding`.
##   2. IT IS METAL, so the face is brightest WHERE THE LAMP IS (up-left), and
##      it carries a broad specular sweep. The sweep is the single strongest
##      "this is metal and not a coloured rect" cue available, and it is the one
##      the old fill had no vocabulary for at all.
##   3. THE TYPE IS STRUCK INTO IT, so the plate is raised around the letters.
##      A StyleBox cannot touch a Button's glyphs (a Button draws its own text,
##      which is why `Motion.press_mark` had to become a bloom under the label
##      rather than anything behind it) — but it does not need to. The depth
##      belongs to the FIELD the letters sit in, and the field is ours.
##   4. IT IS PINNED, so it casts a contact shadow and wears dome tacks.
##   5. PRESSING IT DRIVES IT FLUSH. This is the one that pays for the whole
##      exercise: a rectangle can only change COLOUR on press, and every button
##      in this game did exactly that. A solid can change its relationship to
##      the surface it is mounted on — the drop collapses, the molding shallows,
##      the sweep dies, and a rim shadow closes over the plate. The plate goes
##      INTO the table. That is a press you can feel at 1600x900 with no tween
##      running, because it is a different object and not a darker one.
##
## THE STATE IS A PROPERTY, NOT A SUBCLASS. Godot swaps a whole StyleBox on
## hover and press, so the three states are three instances of this file with
## `state` set — which means the press treatment costs no signal wiring and
## cannot desync from the control's actual state the way a hand-tweened overlay
## can.
##
## No `class_name`: every painter in this directory is reached by `preload` under
## a same-name const, so it works the moment the file exists with no `--import`
## pass. Same rule as `LayerStyle` and `PlateFrame`.
extends StyleBox

const PlateFrame := preload("res://scripts/ui/painters/PlateFrame.gd")
const LayerStyle := preload("res://scripts/ui/painters/LayerStyle.gd")

enum { REST, HOVER, PRESS, DISABLED }

## The plate's metal. Handed the caller's accent — the same colours
## `ChartPanelStyle` was given as a border, so existing call sites drop in.
var metal := Color(0.80, 0.61, 0.30, 0.86):
	set(v):
		metal = v
		emit_changed()
## The face's own dark. Not the metal: the plate is an inked plaque, so the field
## is warm-black and the METAL is what the light finds.
var fill := Color(0.125, 0.068, 0.032, 0.93):
	set(v):
		fill = v
		emit_changed()
## REST / HOVER / PRESS / DISABLED — the BASE state.
##
## For a live button this stays REST and the motion rides `hover_t` / `press_t`
## below; `DISABLED` is set by the theme and does not animate. The discrete
## values remain because staging one fixed state is exactly what a shot tool
## wants.
var state := REST:
	set(v):
		state = v
		emit_changed()
## ── THE TRANSITION (2026-09-18). THE PLATE USED TO TELEPORT.
##
## Godot SWAPS a whole StyleBox on hover and press. That is what made the
## three-instance state grammar so cheap to build — and it means every physical
## property this file computes changed in ONE FRAME: the plate's relief, its
## lamp, its sweep, its contact shadow and its rim all jumped. I had built a
## solid that moved like a slide change, and spent the whole pass looking at the
## inside of it.
##
## A press is an EVENT and can be instant; hover and release are MOVEMENTS of a
## physical object, and an object with mass does not arrive in one frame. So the
## plate is now ONE instance assigned to every state, and these two numbers are
## tweened (`arm_transitions`). They are properties of a Resource, so a Tween
## drives them directly and `emit_changed()` repaints — the same mechanism
## `sweep_phase` already proved.
##
## Two numbers rather than one enum, because the states are not a line: you can
## be hovering AND pressing, and releasing while still hovered must land on
## HOVER rather than on REST. A single 0..1 "activation" cannot express that and
## makes a release flicker through the rest pose.
var hover_t := 0.0:
	set(v):
		hover_t = clampf(v, 0.0, 1.0)
		emit_changed()
var press_t := 0.0:
	set(v):
		press_t = clampf(v, 0.0, 1.0)
		emit_changed()
## Colour targets for the two live states. Left transparent = DERIVE from the
## rest colours, which is what lets one plate replace a hand-picked triple
## without every call site restating three sets of browns.
var metal_hot := Color(0, 0, 0, 0)
var fill_hot := Color(0, 0, 0, 0)
var metal_cold := Color(0, 0, 0, 0)
var fill_cold := Color(0, 0, 0, 0)
## Molding width. A SHAPE NEEDS AREA BEFORE IT CAN BE LIT (the StruckBracket
## lesson, then the PlateFrame lesson): below ~3px there is nowhere to put a
## crest and a valley, every pass lands on the same pixel, and this degenerates
## into the 2px rule it replaces. 5 is the floor that reads on a 46px plate.
var rule_width := 5.0
## Corner cut. Matches `ChartPanelStyle.chamfer` so a plaque sits in a row of
## kit furniture without announcing itself as a different shape.
var chamfer := 9.0
## Corner hardware. OFF by default: a button is a small object and four tacks on
## a 340x46 plate is a row of bright dots competing with the word on it. The
## save slots and other big plates turn it on.
var tacks := false
## Hand-cut breathing, px. ZERO, AND IT IS NOT A SIZE COMPROMISE.
##
## This shipped at 0.8 on the reasoning that a button is smaller than a portrait
## plate so it wants less of the kit's deckle. That framing is wrong: the right
## amount of deckle on cast metal is NONE, at any size.
##
## `reference_frame_optics_perception` rule 3 — SILHOUETTE IS THE ONE CHANNEL THE
## EYE IS HYPERACUTE IN. Vernier offsets are discriminable at 2-5 arcsec, far
## below a pixel at any normal viewing distance, so a wobble meant to read as
## subliminal material character reads instead as a WARPED OBJECT; it was
## measured as the single most visible thing about the hero plate. It is also a
## claim about the MATERIAL — deckling is right for torn paper and wrong for a
## struck plate, which is machined. `PlateFrame` reached 0.0 the same day.
##
## Liveliness belongs in the shading, where acuity is a Weber fraction of a few
## percent rather than hyperacute. That is what `PlateFrame.shimmer` is for, and
## it is already on by default, so this costs the plate nothing.
var wobble := 0.0
## The struck field the type sits in (fact 3).
##
## DEFAULT OFF, AND THIS IS A FINDING RATHER THAN A PRECAUTION. It is built, it
## is correct, and at button scale it does not read. On a 46px plate the field
## has to inset past a 5px molding and still leave a 20px label its measure, so
## what is left is a thin rim about 9px in from the metal — and a thin rim
## parallel to another thin rim is not a depression, it is a SECOND FRAME. The
## render showed a box inside a box on every primary in the game.
##
## That is the same judgement `_cartouche_rect` already makes about plates under
## 118x30, arrived at from the other end: a cue that only works at some sizes
## must DECLINE at the others rather than shrink into noise. The measured floor
## is simply much higher than I guessed. Kept for tall plates (a save-slot row
## is 58px and has room), so this stays a caller's opt-in.
var cartouche := false
## Specular sweep strength, 0 disables. The metal cue.
var sweep := 1.0
## Where the sweep sits along the light axis, 0 (shadow corner) .. 1 (lit
## corner).
##
## TWEENABLE, AND THAT IS NOT AN ACCIDENT. A StyleBox is a Resource, so
## `tween_property(style, "sweep_phase", ...)` works and `emit_changed()` makes
## the control repaint — the same mechanism `ChartPanelStyle`'s `bg_color`
## setter already relies on for runtime-retinted HUD chips. `arm_glint` below
## uses it to run the lamp across the brass as the cursor arrives, which is a
## real animation on a stylebox with no extra node and nothing to free.
var sweep_phase := 0.66:
	set(v):
		sweep_phase = v
		emit_changed()
## ── THE STRUCK WORD (2026-09-18) ──────────────────────────────────────────
##
## I WROTE "A STYLEBOX CANNOT TOUCH A BUTTON'S GLYPHS" IN THIS FILE'S OWN HEADER
## AND IT IS FALSE, in the way that matters. What is true is that a StyleBox
## cannot draw OVER the text — `Motion.press_mark` had to become a bloom for
## exactly that reason. But an engrave does not want to be over the text. The
## shadow a raised letter casts, and the lit lip along its top edge, both sit
## UNDER the glyph, which is precisely and only where a StyleBox is allowed to
## draw. The constraint I read as a wall is the correct z-order for the effect.
##
## So the plate draws the word TWICE beneath the Button's own: a dark ghost
## offset down-light, and a faint warm one offset up-light. The Button then
## draws its real glyph on top, unchanged, at full contrast — nothing about
## legibility or the readability floor moves.
##
## RAISED, NOT INCISED, and that is a legibility decision rather than a
## metallurgical one. Letters punched INTO brass are darker than the field, and
## this shell's type has to clear COPY_STYLE §11's contrast floors over a plate
## that is itself warm and mid-valued. Raised letters — polished type standing
## proud of a darkened field, which is how a real pressed nameplate is finished
## anyway — keep the glyph the brightest thing in its own neighbourhood.
##
## The offsets are ~1.5px and ~0.9px. The dark one has to be bigger: a cast
## shadow is a real displacement, while the lit lip is a chamfer a fraction of a
## millimetre wide catching the lamp.
##
## THE TEXT IS PUSHED IN, NOT READ OUT, because a StyleBox has no route back to
## the control that owns it. `GameTheme.arm_plaque_label` is the one funnel that
## sets it, and it also covers the case that makes this dangerous — a caller
## assigning `btn.text` LATER would leave the old word ghosted under the new
## one, which is a visible double-print rather than a quiet miss.
var label := ""
var label_font: Font = null
var label_size := 20
## Set false to keep the plate and drop the engrave (a plate carrying an icon
## rather than a word, or a label the caller draws itself in a child node).
var engrave := true
## The lamp's own colour.
##
## A METAL'S SPECULAR IS NOT WHITE — that is PlateFrame's hardest-won line and
## it cost four tuning passes there. White is right for a DIELECTRIC (wax,
## paper, plastic reflect the lamp's colour); a metal tints its reflection with
## its own hue, and defaulting this to white bleached the frame to bone. Pale
## warm gold.
var lit := Color(1.0, 0.93, 0.74)
## How much of `lit` the crest may reach. Above `PlateFrame`'s 0.55 for the same
## reason `body_drop` is below its default here: a frame must not out-shout the
## painting it holds, and a button is the object being looked at.
var lit_gain := 0.70


# ── the state dials ────────────────────────────────────────────────────────
#
# ONE TABLE, not branches scattered down `_draw`. Every state is the SAME solid
# under a different relationship to the table it is pinned to, so what varies is
# a handful of physical quantities: how far it stands off, how hard the lamp
# catches its crest, how alive the sweep is, and whether its own rim has closed
# over it. Written as data so the three states can be read against each other in
# one glance — which is the only way to notice that a state has been left
# physically incoherent (a plate that sinks AND keeps its drop shadow).

const _DIALS := {
	REST:  {"drop": 2.2, "lit_mul": 1.00, "sweep": 1.00, "face_lift":  0.00, "sink": 0.0},
	HOVER: {"drop": 3.0, "lit_mul": 1.30, "sweep": 1.35, "face_lift":  0.16, "sink": 0.0},
	# FLUSH. The plate is down in its recess: it has nothing left to cast a
	# shadow with, and its crest has swung out of the lamp.
	PRESS: {"drop": 0.0, "lit_mul": 0.46, "sweep": 0.22, "face_lift": -0.10, "sink": 1.0},
	# A DISABLED PLATE MUST NOT LOOK PRESSABLE, AND MUST NOT LOOK PRESSED.
	#
	# This was an affordance bug rather than a missing polish item: the disabled
	# arm took REST's dials, so a control that refuses the click stood fully
	# proud of the page with a full contact shadow — the exact cue that says
	# "push me". Dulling its colour (which is all the old flat style could do,
	# and all `_plaque_style` did) says "unavailable" much more weakly than
	# relief says "available"; the geometry was arguing with the palette.
	#
	# But it cannot borrow PRESS either: `sink` means the rim has closed OVER
	# the plate, which reads as being pressed AT THIS MOMENT. So a disabled
	# plate is its own physical state — LOW RELIEF. It still sits on the page
	# (a third of the drop, so it is an object and not a hole), takes almost no
	# lamp, and has no sweep at all: an unlit plate has nothing to reflect.
	DISABLED: {"drop": 0.7, "lit_mul": 0.30, "sweep": 0.0, "face_lift": -0.04, "sink": 0.0},
}


## Blended along BOTH axes. `DISABLED` bypasses: it is a fixed condition of the
## control, not a place the plate travels to, and letting a hover tween lift a
## dead button is the affordance bug this state exists to remove.
func _dial(key: String) -> float:
	if state == DISABLED:
		return float((_DIALS[DISABLED] as Dictionary).get(key, 0.0))
	var rest := float((_DIALS[REST] as Dictionary).get(key, 0.0))
	var hot := float((_DIALS[HOVER] as Dictionary).get(key, 0.0))
	var cold := float((_DIALS[PRESS] as Dictionary).get(key, 0.0))
	# Hover first, then press ON TOP — a pressed-while-hovered plate must read as
	# pressed, and pressing is the stronger claim.
	return lerpf(lerpf(rest, hot, hover_t), cold, press_t)


## The metal at this instant. Unset targets derive from the rest colour so a
## caller supplies one metal and still gets a lamp that finds the plate on hover
## and leaves it on press.
func _metal_now() -> Color:
	if state == DISABLED:
		return metal
	var hot: Color = metal_hot if metal_hot.a > 0.0 else PlateFrame._lift(metal, 0.45)
	var cold: Color = metal_cold if metal_cold.a > 0.0 else PlateFrame._sink(metal, 0.16)
	return metal.lerp(hot, hover_t).lerp(cold, press_t)


## The field at this instant. DIFFUSE, so it SCALES its own colour and is never
## dragged toward the lamp's — Cook & Torrance, and the rule this codebase has
## already paid for once (a metal's rim-lerp applied to a coloured fill turned a
## bar of oxblood wax very nearly gold).
func _fill_now() -> Color:
	if state == DISABLED:
		return fill
	var hot: Color = fill_hot if fill_hot.a > 0.0 else _scale_rgb(fill, 1.55)
	var cold: Color = fill_cold if fill_cold.a > 0.0 else _scale_rgb(fill, 0.74)
	return fill.lerp(hot, hover_t).lerp(cold, press_t)


static func _scale_rgb(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0),
		clampf(c.b * k, 0.0, 1.0), c.a)


func _get_draw_rect(rect: Rect2) -> Rect2:
	# The drop offsets down-right and its outermost grown copy reaches a little
	# past that; measured worst case (hover) is ~9.5px, so 12 has margin.
	# Generous rather than exact: a clipped shadow reads as a hard edge on the
	# plate, which is the opposite of the whole point.
	return rect.grow(12.0)


func _draw(ci: RID, rect: Rect2) -> void:
	if rect.size.x <= 6.0 or rect.size.y <= 6.0:
		return
	var short: float = minf(rect.size.x, rect.size.y)
	var ch: float = clampf(chamfer, 3.0, short * 0.26)
	var w: float = PlateFrame.molding_width(rect, rule_width)
	var amp: float = PlateFrame.molding_amp(rect, wobble)
	var lv := LayerStyle.light_vec()
	# Seeded per CANVAS ITEM, not per stylebox instance. This is the property
	# that makes the state grammar work at all: a button's three styleboxes are
	# three different objects drawn onto ONE control, so seeding per instance
	# would re-cut the plate's silhouette the moment the cursor touched it — the
	# hand-cut edge would visibly crawl on hover. `ChartPanelStyle` reached the
	# same conclusion and says so.
	var sd := int(ci.get_id() & 0x7FFFFFFF)

	var mcfg := PlateFrame.default_cfg()
	mcfg["metal"] = _metal_now()
	mcfg["lit"] = lit
	mcfg["lit_gain"] = lit_gain * _dial("lit_mul")
	# ── THE BODY STAYS SUNK. I SET IT TO 0.30 AND THAT WAS THE WORST EDIT IN
	# THIS PASS, so the reasoning is kept as a warning rather than deleted.
	#
	# The first render came out muddy — a brown plate with a tan border, plainly
	# less legible as a control than the 2px gilt rule it replaced — and the
	# apparent cause was obvious: `PlateFrame` sinks its body hard so a frame
	# cannot out-shout the painting it holds, and a button has no painting to
	# protect. So I un-sank it (0.70 -> 0.30) and pulled less of the caller's
	# gilt toward the alloy (0.78 -> 0.42). The plate got brighter and it got
	# WORSE: the 8x crop showed a flat tan band with a dark line in it, no
	# cross-section left at all.
	#
	# It is rule 2 of `reference_frame_optics_perception`, from Marlow, Kim &
	# Anderson (2012) and Marlow & Anderson (2013): perceived gloss is
	# COVERAGE x CONTRAST x SHARPNESS, and coverage is the one you overspend.
	# The gloss was living in the GAP between a sunk body and a hot crest.
	# Raising the body toward the crest does not add shine, it deletes the gap
	# the shine was made of.
	#
	# THE MEASUREMENT SAID SO AND I READ IT AS NOISE, which is the part actually
	# worth remembering: SHOULDER r went -0.45 -> +0.01 in that same edit, i.e.
	# the top and bottom cross-sections went from opposed to IDENTICAL — the
	# molding had stopped being a molding — while INVERSION rose 0.228 -> 0.303
	# and I let the rising number carry the verdict.
	#
	# Gilt is bought the other way: a TIGHTER, HOTTER crest (`lit_gain` above,
	# and `hot_sigma` in the profile) against a body that stays down. Both
	# values are now `PlateFrame`'s own, deliberately unset here.
	mcfg["rule_w"] = rule_width
	mcfg["chamfer"] = chamfer
	# 6 -> 11 (2026-09-18). NOT a taste change: `PlateFrame`'s specular stopped
	# being a broad symmetric wash and became a narrow Gaussian riding the light
	# direction, and the molding is rasterised as `steps` concentric paths — so a
	# highlight ~1/6 of the width wide falls BETWEEN samples at 6 steps and reads
	# as a dashed glint. The frames went to 11 for the same reason. Steps are
	# polylines over one path; this is near-free.
	mcfg["steps"] = 11
	# NO COUNTER-GRADIENT ON A BUTTON. `PlateFrame` grew a Cornsweet ramp decaying
	# outward from the seam, which is right for a picture frame — it has no drop
	# to speak of (the hero plate CLIPS, so its shadow is scissored off) and needs
	# the edge to buy its depth. A button already casts a real directional `drop`
	# onto the page, and a second, omnidirectional dark ramp on top of it reads as
	# a smudge round the plate rather than as a lit object standing on it.
	mcfg["cornsweet"] = 0.0
	mcfg["wobble"] = wobble
	# The plate draws its OWN contact shadow — see `_draw_contact`. A frame's
	# drop is a different physical situation and `PlateFrame` should keep it.
	mcfg["drop"] = 0.0
	mcfg["tacks"] = tacks
	# A BUTTON HAS NO MITRE. The fill is a real rounded-rect fill that already
	# ends on the chamfer, so there is no wedge of content outside the cut to
	# cover — and filling it anyway paints four dark triangles ONTO the plate's
	# own corners. The flag exists for exactly this difference.
	mcfg["mitre"] = false
	# The face reaches under the metal, so the molding's inward contact shadow is
	# landing on the plate's OWN field rather than on a picture. Keep it, quietly
	# — it is what stops the face reading as a sticker inside a ring — but well
	# under the frame default, which is sized for a rebate holding a painting.
	mcfg["rebate"] = 1.6 if state != PRESS else 2.6

	# ── 0. the contact shadow, UNDER everything the plate draws.
	_draw_contact(ci, rect, ch, amp, sd, lv, _dial("drop"))

	# ── 0b. THE LIGHT THE PLATE THROWS BACK ONTO THE PAGE.
	#
	# Everything else in this file happens INSIDE the silhouette, and a lit
	# object does not stop at its own outline: if the lamp has found the brass,
	# the brass bounces some of it onto the table it is lying on. Without this
	# the hover reads as the plate changing its own colour — a lightbulb
	# switching on — rather than as light arriving in the scene.
	#
	# Rides `hover_t`, so it is part of the same movement rather than a separate
	# effect with its own timing. It is a WARM BOUNCE, not a glow: the colour is
	# the metal's, because a bounce carries the colour of what it bounced off
	# (Cook & Torrance again — a metal tints its reflection with its own hue), and
	# a neutral white halo here is the "outer glow" tell that reads as a UI
	# sticker. Alpha is tiny and the falloff is wide.
	if hover_t > 0.01 and state != DISABLED:
		_draw_bounce(ci, rect, ch, amp, sd, lv, hover_t * (1.0 - press_t * 0.7))

	# ── 1. the face. Laid at the molding's inner edge so the metal covers its
	# seam; on the SAME path the molding walks (see `PlateFrame.path_at`).
	var face := PlateFrame.path_at(rect, w * 0.82, ch, amp, sd)
	if face.size() < 3:
		return
	_draw_face(ci, face, lv, _dial("face_lift"))

	# ── 2. the struck field. Fact 3: the plate is raised around the letters.
	if cartouche:
		_draw_cartouche(ci, rect, ch, amp, sd, w, lv)

	# ── 3. the sweep. Fact 2, and the cue the old fill had no vocabulary for.
	if sweep > 0.0 and _dial("sweep") > 0.0:
		_draw_sweep(ci, face, lv, sweep * _dial("sweep"), short)

	# ── 3b. the struck word, under the Button's own glyph. See `label`.
	if engrave and label != "" and label_font != null:
		_draw_engrave(ci, rect, lv)

	# ── 4. the molding. Shared, so a button and a frame are lit by one sun.
	PlateFrame.draw_molding(ci, rect, mcfg, sd)

	# ── 5. PRESSED: the rim closes over the plate. A plate driven flush into its
	# recess is overhung on the lamp side, so the shadow it was CASTING becomes a
	# shadow it is RECEIVING. Same total ink, moved from outside the silhouette
	# to inside it, which is why the press reads as depth rather than as dimming.
	if _dial("sink") > 0.0:
		_draw_rim_shadow(ci, rect, ch, amp, sd, w, lv)


# ── the contact shadow ─────────────────────────────────────────────────────

## A CONTACT SHADOW IS NOT A BLURRED COPY OF THE SILHOUETTE (2026-09-18).
##
## `PlateFrame` casts its drop as three grown outlines offset bodily along
## -light_vec at falling alpha. That is correct for what it models — a frame
## standing off a wall, far enough that the whole shadow has travelled. A button
## is a plate PINNED TO A TABLE, and a contact shadow has two parts that behave
## differently:
##
##   * THE CORE hugs the silhouette with almost no offset, and it is much darker
##     than anything a uniform band contains. Ambient light is occluded hardest
##     exactly where two surfaces meet, and that near-black hairline is the cue
##     that actually welds an object to a surface. Offsetting it away — which is
##     what a bodily-shifted band does — is precisely what makes an element read
##     as a sticker floating above the page.
##   * THE PENUMBRA both WIDENS and TRAVELS as it leaves the contact line,
##     because the lamp is an area source and the gap under the plate opens up
##     as you move away from the contact.
##
## So alpha, stroke width and offset are all functions of the same `t`, pulling
## in the directions physics gives them, instead of one offset applied to
## everything. The alpha curve is deliberately steep (`pow(t, 0.62)`) — a linear
## ramp spends most of its ink in the mid penumbra, where it reads as grime
## rather than as contact.
##
## Drawn HERE rather than in `PlateFrame` because a frame genuinely wants the
## other behaviour, and because that file is another session's active work.
func _draw_contact(ci: RID, rect: Rect2, ch: float, amp: float, sd: int,
		lv: Vector2, drop: float) -> void:
	if drop <= 0.0:
		return
	var layers := 5
	for i in range(layers - 1, -1, -1):
		# 0 = the tight dark core at the contact line, 1 = the outermost wash.
		var t := float(i) / float(layers - 1)
		var path := PlateFrame.path_at(rect.grow(t * drop * 1.7), -0.5,
			ch + t * drop * 1.7, amp, sd)
		if path.size() < 3:
			return
		var off := -lv * (drop * (0.15 + 0.85 * t))
		var moved := PackedVector2Array()
		for p in path:
			moved.append(p + off)
		var a: float = lerpf(0.50, 0.05, pow(t, 0.62))
		var width: float = lerpf(1.6, maxf(drop * 2.4, 3.0), t)
		var loop := _close(moved,
			_flat(moved.size(), Color(0.02, 0.012, 0.008, a)))
		RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1],
			width, true)


## The warm bounce onto the page around a lit plate. Widest and faintest at the
## outside, offset AWAY from the lamp — the page it lands on is the part the
## plate is not shading, so the bounce and the contact shadow occupy opposite
## sides of the silhouette and never fight for the same pixels.
func _draw_bounce(ci: RID, rect: Rect2, ch: float, amp: float, sd: int,
		lv: Vector2, gain: float) -> void:
	var m := _metal_now()
	var layers := 4
	for i in range(layers - 1, -1, -1):
		var t := float(i) / float(layers - 1)
		var grow: float = 1.5 + t * 7.0
		var path := PlateFrame.path_at(rect.grow(grow), -0.5, ch + grow, amp, sd)
		if path.size() < 3:
			return
		var off := lv * (1.0 + t * 2.0)
		var moved := PackedVector2Array()
		for p in path:
			moved.append(p + off)
		var a: float = lerpf(0.10, 0.012, t) * clampf(gain, 0.0, 1.0)
		var loop := _close(moved, _flat(moved.size(), Color(m.r, m.g, m.b, a)))
		RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1],
			lerpf(2.0, 9.0, t), true)


static func _flat(n: int, c: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for _i in range(n):
		out.append(c)
	return out


# ── the face ───────────────────────────────────────────────────────────────

## THE GRADE RUNS ALONG THE LAMP, NOT DOWN THE Y AXIS.
##
## `ChartPanelStyle` ramps top-to-bottom, which is a window-light convention and
## is wrong here twice over: metal is brightest where the lamp is, and the
## molding wrapped around this face is lit from up-left. A vertical face inside
## an up-left edge is two objects under two suns, and at 46px that reads as the
## plate being slightly grubby rather than as an obvious break — which is why it
## survived this long.
##
## A LINEAR RAMP IS EXACT UNDER PER-VERTEX COLOUR, which is worth knowing
## because it is why this needs no shader and no bands: barycentric
## interpolation reproduces a linear function precisely, whatever the
## triangulation does with a 90-point wobbled octagon. The non-linear part of
## the material — the sweep — cannot be done this way, and is a separate pass.
func _draw_face(ci: RID, face: PackedVector2Array, lv: Vector2,
		lift: float) -> void:
	var cen := _centroid(face)
	var reach: float = maxf(_reach(face, cen, lv), 1.0)
	var base := _fill_now()
	if lift > 0.0:
		base = base.lerp(Color(0.34, 0.20, 0.10, base.a), lift)
	elif lift < 0.0:
		base = base.lerp(Color(0.0, 0.0, 0.0, base.a), -lift)
	# Toward the lamp the field warms and lifts; away from it, it falls into the
	# plate's own shadow. Anchored on the metal's hue so the light on the face
	# and the light on the edge are recognisably the same lamp.
	# ── THE FACE IS DIFFUSE. IT SCALES ITS OWN COLOUR AND IS NEVER DRAGGED
	# TOWARD THE LAMP'S (2026-09-18).
	#
	# This was `base.lerp(metal, 0.30)` then a further 6% toward white, and it is
	# the single reason the shipped button read as a PALE GOLD BAR — a progress
	# bar, the one bright object on a screen where every other element is a dark
	# field with a gold rule. At hover the metal IS `GILT_BRIGHT` (1.0, 0.88,
	# 0.35), so lerping a (0.135, 0.072, 0.034) plaque 30% toward it lands at
	# roughly (0.39, 0.32, 0.13): the plate stopped being dark and the whole
	# value relationship the game's kit runs on inverted.
	#
	# It is `reference_diffuse_vs_specular_shading` verbatim, and its own "how to
	# spot it without rendering" test names this exact call: *any call that
	# lights a CALLER-SUPPLIED colour through a helper whose highlight argument
	# is the surface's lamp*. Cook & Torrance — DIFFUSE returns the surface's own
	# spectrum, so lighting it must SCALE its channels; only the SPECULAR carries
	# the lamp, and on this plate the specular is the sweep and the crest, both
	# of which already exist and are already doing that job.
	#
	# A DARK PLATE WITH A BRIGHT EDGE IS ALSO THE HOUSE RULE, not a preference:
	# `ChartPanelStyle` is a dark bg under a bright border, `PlateFrame` sinks its
	# body so the crest can be hot without the molding going pale, and the gilt
	# is what says "pressable". The plate is the ground; the metal and the word
	# are the figure.
	var hot := _scale_rgb(base, 1.38)
	var cold := _scale_rgb(base, 0.62)
	var cols := PackedColorArray()
	for p in face:
		var t: float = clampf(((p - cen).dot(lv) / reach) * 0.5 + 0.5, 0.0, 1.0)
		cols.append(cold.lerp(hot, t))
	RenderingServer.canvas_item_add_polygon(ci, face, cols)


# ── the struck field ───────────────────────────────────────────────────────

## The rect the type occupies, or an empty rect when the plate cannot carry one.
##
## SUPPRESSED ON SMALL PLATES ON PURPOSE. The field has to be inset far enough
## to read as a separate surface and still leave the label its measure; below
## roughly a 120x30 plate those two demands cross and the "depression" becomes a
## dark line through the middle of the word. A cue that only works at some sizes
## must decline at the others, not shrink.
func _cartouche_rect(rect: Rect2, w: float) -> Rect2:
	if rect.size.x < 118.0 or rect.size.y < 30.0:
		return Rect2()
	var inset_x: float = maxf(w + 5.0, rect.size.x * 0.035)
	var inset_y: float = maxf(w + 4.0, rect.size.y * 0.16)
	var r := Rect2(rect.position + Vector2(inset_x, inset_y),
		rect.size - Vector2(inset_x, inset_y) * 2.0)
	if r.size.x < 40.0 or r.size.y < 12.0:
		return Rect2()
	return r


## A RECESS IS NOT A BOSS, AND THE LAMBERT SIGN IS THE DIFFERENCE.
##
## Think of a hole lit from up-left. The wall on the up-left side of the hole
## faces DOWN-RIGHT, away from the lamp, so it is SHADOWED; the wall on the
## down-right side faces the lamp and is LIT. That is the exact inverse of
## `LayerStyle.bevel`, which lights the edges whose outward normal faces the
## lamp because it is shading a RAISED solid.
##
## So this is not a copy of `bevel` with a bug in it. The sign is per-OPTIC, not
## per-file (see reference_painter_light_direction, and the octant sweep gate
## that exists because that rule was broken once already), and `Sheen.inset`
## independently states the same convention for its own bevel: "a dark lip along
## the top edge and a lit one along the bottom, which is what makes a small tile
## read as pressed INTO the page instead of printed on it".
func _draw_cartouche(ci: RID, rect: Rect2, ch: float, amp: float, sd: int,
		w: float, lv: Vector2) -> void:
	var cr := _cartouche_rect(rect, w)
	if cr.size.x <= 0.0:
		return
	var poly := PlateFrame.path_at(cr, 0.0, minf(ch * 0.55, cr.size.y * 0.30),
		amp * 0.5, sd ^ 0x5bf03635)
	if poly.size() < 3:
		return
	# The floor of the depression: the face, a touch darker. Small — a strong
	# value change here fights the label, and the depth is carried by the lips.
	RenderingServer.canvas_item_add_polygon(ci, poly,
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.13)]))
	# ── NORMALS PER POINT, NOT FROM THE CENTROID. `LayerStyle.bevel` takes the
	# direction from the shape's centre as its outward normal, which is fine for
	# a compact mark and WRONG for a 340x46 slab: on the top run of a wide
	# rectangle that direction is nearly HORIZONTAL, so the Lambert term is
	# dominated by the x component and flips sign at the run's midpoint. The
	# first render showed it exactly — each run came out half lit and half
	# shadowed, and because the lips were drawn as one `draw_line` per segment
	# with its own alpha, the sign flip broke the rim into a DASHED, beaded
	# line. It read as a row of dots inside the button.
	#
	# `PlateFrame._outward` is the correct construction (averaged from the two
	# segments meeting at each point) and it is already written, so use it. Drawn
	# as ONE polyline with per-point colour, the way the molding is drawn, which
	# is also what makes the dark-to-lit crossover fade smoothly instead of
	# stepping: both sides reach alpha 0 at Lambert 0.
	var norms := PlateFrame._outward(poly)
	var depth: float = clampf(cr.size.y * 0.055, 1.0, 2.2)
	var cols := PackedColorArray()
	for j in range(poly.size()):
		var lam: float = norms[j].dot(lv)
		if lam >= 0.0:
			# Faces the lamp -> it is the NEAR wall of a hole -> shadowed.
			cols.append(Color(0.02, 0.012, 0.008, clampf(lam * 0.50, 0.0, 1.0)))
		else:
			# Faces away -> the far wall, turned up toward the lamp -> lit.
			cols.append(Color(lit.r, lit.g, lit.b,
				clampf(-lam * 0.24, 0.0, 1.0)))
	var loop := _close(poly, cols)
	RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1], depth, true)


# ── the sweep ──────────────────────────────────────────────────────────────

## The specular band, clipped to the plate's own silhouette.
##
## BOUNDED BY THE FACE, NEVER DRAWN OVER IT. `Geometry2D.intersect_polygons`
## against the face is what keeps the highlight inside a hand-cut edge; a drawn
## ellipse or a ColorRect spills past the wobble and past the chamfer, which is
## `LayerStyle.shine`'s own recorded reason for cutting its chord out of the
## shape instead of painting one on.
##
## I MADE THE EXACT MISTAKE THIS PROJECT KEEPS WRITING DOWN, so it is recorded
## here too. The first version was THREE NESTED BANDS, wide-and-faint to
## narrow-and-bright — reasoning that a lobe has a soft shoulder and a hot
## centre, which is true, and then building it out of three FLAT polygons, each
## with a hard boundary, which cannot be soft. It rendered as three hard-edged
## diagonal stripes and read as a cheap glass-shine sticker slapped on the
## plate. That is the lightning rebuild's "halo + bolt + core = a thicker hard
## band with a dimmer hard band behind it", one file after I quoted it in this
## file's own header.
##
## A FLAT POLYGON CANNOT HAVE A SOFT EDGE. What it can have is PER-VERTEX
## COLOUR, which is how the molding and the face are already shaded here, so the
## band is cut into thin strips across its width and every resulting vertex is
## given an alpha from its OWN measured distance to the centreline. Adjacent
## strips therefore agree exactly at their shared boundary — there is no edge to
## see — and the falloff is a real curve rather than three steps.
##
## THE STRIPS ARE NOT OPTIONAL, AND THE REASON IS A FACT ABOUT INTERPOLATION: a
## ridge needs a vertex ON the ridge. Colouring one wide clipped band per vertex
## looks like it should work and does not — the centreline usually has no vertex
## on it, so the interpolation runs straight between boundary vertices and cuts
## the peak off entirely.
##
## BOUNDED BY THE FACE, NEVER DRAWN OVER IT. `Geometry2D.intersect_polygons`
## against the face is what keeps the highlight inside a hand-cut edge; a drawn
## ellipse or a ColorRect spills past the wobble and past the chamfer, which is
## `LayerStyle.shine`'s own recorded reason for cutting its chord out of the
## shape instead of painting one on.
const SWEEP_STRIPS := 8
## How far keyboard focus lifts the plate, as a fraction of a full hover.
## Visible, but nowhere near the hover blaze — see `arm_transitions`.
const FOCUS_LIFT := 0.34

func _draw_sweep(ci: RID, face: PackedVector2Array, lv: Vector2,
		gain: float, short: float) -> void:
	var cen := _centroid(face)
	var reach: float = maxf(_reach(face, cen, lv), 1.0)
	var long: float = _radius(face, cen) * 2.4
	# The direction the band RUNS, perpendicular to the light.
	var perp := Vector2(-lv.y, lv.x)
	var perp_reach: float = maxf(_reach(face, cen, perp), 1.0)
	# 0 -> the shadow corner, 1 -> the lit corner.
	var at: Vector2 = cen + lv * (clampf(sweep_phase, 0.0, 1.0) * 2.0 - 1.0) * reach
	# ── COVERAGE CUT HARD, CONTRAST BUYS IT BACK (2026-09-18).
	#
	# This was `reach * 0.72` at peak alpha 0.135 — a highlight covering 72% of
	# the plate, which by Marlow & Anderson (2013) is not a highlight at all, it
	# is the body colour, and the face duly read as a flat brown field with a
	# vague brightening in it. Exactly the same overspend as the `body_drop`
	# mistake above, on the other half of the plate, made on the same day.
	#
	# A quarter of the width at nearly three times the peak is the same total
	# ink concentrated into something the eye can actually call a reflection.
	# The face's own diagonal grade (`_draw_face`) is what carries the broad
	# falloff — that is the diffuse term, and it was already doing that job
	# while this term duplicated it at low contrast.
	# ── THE HIGHLIGHT IS SIZED OFF THE SHORT SIDE, NOT THE LONG ONE (2026-09-18).
	#
	# THIS IS THE DEFECT THAT MADE THE SHIPPED BUTTON WORSE THAN THE ONE IT
	# REPLACED, and it is worth stating exactly. The width was `reach * 0.26`,
	# where `reach` is the plate's half-extent ALONG THE LIGHT AXIS — so it grew
	# with the button's LENGTH. At the 340px fixture this file was tuned against
	# it was a believable lobe. START RUN has no horizontal size flag inside its
	# HBox, so it FILLS the row at roughly 800px: the same expression put a
	# ~200px band across a 56px-tall plate, which is not a highlight, it is a
	# pale wedge over half the button. A gloss overlay, which is the exact
	# 2005-web-button look this whole pass exists to get away from.
	#
	# A specular lobe's size is a property of the SURFACE AND THE LAMP — the
	# surface's curvature and the light's angular size — and not of how long the
	# plate happens to be. Two plates of the same thickness under one lamp carry
	# the same highlight whether they are 160px or 900px wide. So it comes off
	# the short side, and a button is now the same object at any width.
	var half: float = clampf(short * 0.55, 3.0, reach)
	var peak: float = clampf(0.34 * gain, 0.0, 1.0)
	# ── AND IT IS A LOBE, NOT AN INFINITE BAND.
	#
	# The strips were clipped to the silhouette and nothing else, so the band ran
	# edge to edge and terminated on the plate's own outline — a stripe with two
	# hard ends, which is what reads as something laid ON the surface rather than
	# light in it. A small lamp reflecting off a long plate makes a LOCALISED
	# patch near where it reflects. Falling off along the band's own length over
	# most of the plate's half-extent lets the highlight end in the middle of the
	# metal, where a reflection is allowed to end.
	var lobe: float = maxf(perp_reach * 0.82, short)
	for i in range(SWEEP_STRIPS):
		# Signed offsets across the band, -half .. +half.
		var d0: float = lerpf(-half, half, float(i) / float(SWEEP_STRIPS))
		var d1: float = lerpf(-half, half, float(i + 1) / float(SWEEP_STRIPS))
		var strip := _strip(at, lv, d0, d1, long)
		for piece in Geometry2D.intersect_polygons(face, strip):
			if piece.size() < 3:
				continue
			var cols := PackedColorArray()
			for p in piece:
				var d := p - at
				var t: float = clampf(absf(d.dot(lv)) / half, 0.0, 1.0)
				# Along the band: fades out before the plate's ends, so the
				# highlight never terminates on the silhouette.
				var s: float = clampf(absf(d.dot(perp)) / lobe, 0.0, 1.0)
				# Squared shoulder: fast near the core, long in the tail. A
				# linear ramp reads as a flat wash with an edge, which is
				# `LayerStyle.outer_glow`'s recorded reason for the same curve.
				cols.append(Color(lit.r, lit.g, lit.b,
					peak * pow(1.0 - t, 2.0) * pow(1.0 - s * s, 1.6)))
			RenderingServer.canvas_item_add_polygon(ci, piece, cols)


## One strip of the plane between signed offsets `d0` and `d1` along `dir`,
## running perpendicular for `long` px.
static func _strip(at: Vector2, dir: Vector2, d0: float, d1: float,
		long: float) -> PackedVector2Array:
	var nrm := Vector2(-dir.y, dir.x)
	return PackedVector2Array([
		at + nrm * long + dir * d1,
		at - nrm * long + dir * d1,
		at - nrm * long + dir * d0,
		at + nrm * long + dir * d0,
	])


# ── the struck word ────────────────────────────────────────────────────────

## THE POSITION IS DERIVED THE WAY `Button` DERIVES IT, and it has to be exact:
## a cast shadow one pixel off its caster does not read as a softer shadow, it
## reads as a double print. `Button` lays its text inside the rect deflated by
## the stylebox's own content margins, horizontally centred, and vertically
## centred on the font's full line box — so the baseline is the line box's top
## plus the ascent. All three quantities are available here, because the margins
## being asked about are this object's own.
##
## `get_margin` rather than the raw `content_margin_*` fields: an unset margin is
## -1, and the accessor is what resolves that to the style's real margin. Reading
## the field directly puts the ghost 1px outside the plate on any state that did
## not set all four.
func _draw_engrave(ci: RID, rect: Rect2, lv: Vector2) -> void:
	var ml := get_margin(SIDE_LEFT)
	var mt := get_margin(SIDE_TOP)
	var inner := Rect2(rect.position + Vector2(ml, mt),
		rect.size - Vector2(ml + get_margin(SIDE_RIGHT),
			mt + get_margin(SIDE_BOTTOM)))
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		return
	var sz := label_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label_size)
	var at := Vector2(
		inner.position.x + (inner.size.x - sz.x) * 0.5,
		inner.position.y + (inner.size.y - label_font.get_height(label_size)) * 0.5
			+ label_font.get_ascent(label_size))
	# ── THE RELIEF SCALES WITH THE LETTER (2026-09-18).
	#
	# These were flat 1.6px and 0.9px, which is a fixed relief on a type size
	# that runs 16px in a shop row to 27px on START RUN — so the same plate
	# treatment read as deep embossing on the small labels and as a hairline on
	# the big one. A raised letter's shadow is a property of how far the letter
	# stands off the plate, and that is proportional to the letter.
	#
	# 7.5% and 4.2% of the em reproduce the hand-tuned 20px values (1.5 / 0.84)
	# and hold at both ends of the range. Floored at 1px: below that the
	# rasteriser puts the ghost on the same pixels as the glyph and it reads as a
	# slightly bolder, slightly muddier letter rather than as relief.
	var em := float(label_size)
	var dark_off: float = maxf(em * 0.075, 1.0)
	var lip_off: float = maxf(em * 0.042, 1.0)
	# The shadow the raised letter throws onto the plate: down-light, and the
	# heavier of the two because it is a real displacement.
	label_font.draw_string(ci, at - lv * dark_off, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, label_size,
		Color(0.02, 0.012, 0.008, 0.55))
	# The lit chamfer along the letter's own up-light edge. Faint and tight —
	# it is a fraction of a millimetre of metal, not a second glyph.
	label_font.draw_string(ci, at + lv * lip_off, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, label_size,
		Color(lit.r, lit.g, lit.b, 0.20))


# ── pressed ────────────────────────────────────────────────────────────────

## The rim shadow of a plate sitting flush in its recess: strongest on the lamp
## side, because that is the side the surrounding surface now overhangs. Same
## optic as the cartouche's lips, one scale up.
func _draw_rim_shadow(ci: RID, rect: Rect2, ch: float, amp: float, sd: int,
		w: float, lv: Vector2) -> void:
	var steps := 4
	for i in range(steps):
		var t := float(i) / float(steps)
		var path := PlateFrame.path_at(rect, w + 1.0 + t * 5.0, ch, amp, sd)
		if path.size() < 3:
			return
		# PER-POINT NORMALS. This function had the centroid-radial bug for a
		# whole pass AFTER it was found and fixed in `_draw_cartouche` three
		# functions above — the same wrong construction, in the sibling nobody
		# re-read. That is the C3 guard-audit shape (a predicate applied in one
		# branch and forgotten in another) and it is why the fix note lives in
		# both places now.
		#
		# It matters here as much as it did there: on a 340x46 slab the direction
		# from the centroid is nearly HORIZONTAL along the top run, so
		# `outn.dot(lv)` changes sign at the run's midpoint and the press state's
		# only depth cue came out dark across half of each run and absent across
		# the other half.
		var norms := PlateFrame._outward(path)
		var cols := PackedColorArray()
		for j in range(path.size()):
			# 1 on the lamp side (which is the side the surrounding surface now
			# overhangs, so it is the dark one), 0 opposite.
			var lam: float = clampf(norms[j].dot(lv), 0.0, 1.0)
			cols.append(Color(0.02, 0.012, 0.008,
				(0.10 + 0.34 * lam) * (1.0 - t)))
		var loop := _close(path, cols)
		RenderingServer.canvas_item_add_polyline(ci, loop[0], loop[1],
			maxf(5.0 / float(steps) * 2.2, 1.0), true)


# ── the glint ──────────────────────────────────────────────────────────────

## ── THE TRANSITION, WIRED (2026-09-18) ────────────────────────────────────
##
## Assign ONE plate to every state and drive it, instead of letting Godot swap
## three. `disabled` is deliberately NOT included: that is a genuinely discrete
## condition and it gets its own stylebox from the caller.
##
## THE TIMINGS ARE NOT SYMMETRIC, AND THAT IS THE WHOLE CRAFT OF IT.
##
##   * PRESS DOWN is the fastest thing here (70ms). It is an acknowledgement, and
##     NN/g's 0.1s limit for "reacting instantaneously" is the budget it has to
##     fit inside — the press-feedback pass moved this off `pressed` (which fires
##     on RELEASE) for the same reason. Driven from `button_down`.
##   * RELEASE is slower than press (150ms). Releasing is the plate's mass
##     carrying it back up; matching the press's speed reads as a click artifact
##     rather than as a solid returning.
##   * HOVER IN is slower than press (130ms) and HOVER OUT slower still (190ms).
##     An object the lamp has found should not snap to attention, and a plate
##     that leaves faster than it arrives reads as flinching away from the
##     cursor — which is exactly what a too-fast exit feels like when sweeping a
##     column of buttons.
##
## REDUCE MOTION SNAPS RATHER THAN SKIPS. A state transition is INFORMATIONAL
## under the house contract (it carries "you are hovering / pressing this"), so
## it may never be dropped — but arriving instantly preserves every bit of that
## information, which is what the contract's "hold, don't remove" means here.
static func arm_transitions(btn: Button, plate: StyleBox) -> void:
	if btn == null or plate == null or plate.get("hover_t") == null:
		return
	var go := func(prop: String, to: float, secs: float) -> void:
		if not is_instance_valid(btn):
			return
		var key := "_plaque_tw_" + prop
		if btn.has_meta(key):
			var prev: Variant = btn.get_meta(key)
			if prev is Tween and (prev as Tween).is_valid():
				(prev as Tween).kill()
		if _reduce_motion() or not btn.is_inside_tree():
			plate.set(prop, to)
			return
		var tw := btn.create_tween()
		btn.set_meta(key, tw)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(plate, prop, to, secs)

	btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(btn) and btn.disabled:
			return
		# The lamp crosses the brass on arrival — see `sweep_phase`. Folded in
		# here rather than left to `arm_glint` because with ONE plate the swept
		# phase would otherwise persist into the rest pose.
		plate.set("sweep_phase", 0.10)
		go.call("sweep_phase", 0.78, 0.34)
		go.call("hover_t", 1.0, 0.13))
	btn.mouse_exited.connect(func() -> void:
		go.call("hover_t", 0.0, 0.19)
		# A release that arrives after the cursor has left still has to clear
		# the press — `button_up` is not guaranteed to reach us.
		go.call("press_t", 0.0, 0.15))
	btn.button_down.connect(func() -> void:
		go.call("press_t", 1.0, 0.07))
	btn.button_up.connect(func() -> void:
		go.call("press_t", 0.0, 0.15))
	# ── FOCUS IS NOT HOVER, AND WIRING IT TO FULL HOVER SHIPPED A BUG.
	#
	# `MainMenu._make_begin_button` ends in `take.call_deferred("grab_focus")` —
	# START RUN takes focus the moment RUN SETUP opens. With focus driving
	# `hover_t` to 1.0 the loudest button in the game sat PERMANENTLY in its
	# loudest state, with nobody's cursor near it: full lamp, full sweep, full
	# bounce. That is most of why the live screen looked worse than the staged
	# renders, which never focus anything.
	#
	# Focus still has to be VISIBLE (a keyboard player must see where they are),
	# so it lifts — but to a fraction. A resting default button and a hovered one
	# must remain distinguishable, which they cannot be if focus spends the whole
	# budget.
	btn.focus_entered.connect(func() -> void: go.call("hover_t", FOCUS_LIFT, 0.13))
	btn.focus_exited.connect(func() -> void: go.call("hover_t", 0.0, 0.19))


## Resolved through the tree, never named — a bare `UserSettings` in a script a
## `--script` probe preloads is a hard compile error while parsecheck stays green.
static func _reduce_motion() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var us := tree.root.get_node_or_null("UserSettings")
	return us != null and bool(us.get("reduce_motion"))


## Run the lamp across the brass as the cursor arrives.
##
## The HOVER stylebox is the only one on screen while hovering, so tweening its
## phase on `mouse_entered` needs no state tracking and cannot be caught showing
## a half-swept rest plate. DECORATIVE by the Motion contract — it carries no
## game state — so Reduce Motion holds it at the rest phase rather than removing
## it, per the standing rule that a surface which loses its highlight loses its
## shape too.
static func arm_glint(btn: Button, hover_style: StyleBox) -> void:
	if btn == null or hover_style == null:
		return
	# A PAINTER CANNOT NAME ITS OWN TYPE. There is no `class_name` here (see the
	# header), so `hover_style is PlaqueStyle` does not compile inside this file
	# — and the duck-typed check is the better test anyway: what this needs is a
	# stylebox with a tweenable phase, which is exactly what it asks for.
	if hover_style.get("sweep_phase") == null:
		return
	btn.mouse_entered.connect(func() -> void:
		if not is_instance_valid(btn) or btn.disabled:
			return
		# RESOLVED THROUGH THE TREE, NEVER NAMED. A bare `UserSettings` in a
		# plain RefCounted/Resource script that a tool `preload`s is a HARD
		# compile error in a `--script` context (the dependency compiles before
		# the autoloads register) while parsecheck — which runs as a SCENE —
		# stays green, and it takes the whole depending probe down. Recorded
		# trap; this file is preloaded by GameTheme and by shot tools both.
		var tree := Engine.get_main_loop() as SceneTree
		var us: Node = null
		if tree != null:
			us = tree.root.get_node_or_null("UserSettings")
		if us != null and bool(us.get("reduce_motion")):
			return
		# Killed and restarted rather than layered: two tweens writing one
		# property leaves the loser driving a value the winner just set, which
		# is the same trap the music crossfade paid for.
		# `get_meta(name, null)` STILL THROWS. The default argument only
		# suppresses the error when it is NOT null — "throws an error if the
		# entry does not exist, unless default is not null" — so passing null
		# explicitly is identical to passing nothing, and the FIRST hover on
		# every plated button in the game raised
		# "does not have any 'meta' values with the key '_plaque_glint'".
		#
		# That is not cosmetic: an error like this ABORTS the function it is in,
		# so the glint tween below never ran on a button's first hover. It was
		# invisible because the second hover works (the meta exists by then) and
		# because a missing 0.34s highlight sweep looks like a quieter button,
		# not like a bug. Caught by `_probe_uiscale`, which exercises cold
		# screens — no feel gate hovers anything twice.
		var prev: Variant = btn.get_meta("_plaque_glint") if \
			btn.has_meta("_plaque_glint") else null
		if prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()
		hover_style.set("sweep_phase", 0.10)
		var tw := btn.create_tween()
		btn.set_meta("_plaque_glint", tw)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(hover_style, "sweep_phase", 0.78, 0.34))


# ── helpers ────────────────────────────────────────────────────────────────

static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(float(poly.size()), 1.0)


static func _radius(poly: PackedVector2Array, cen: Vector2) -> float:
	var r := 0.0
	for p in poly:
		r = maxf(r, (p - cen).length())
	return r


## Half-extent of the polygon along `dir`. The face is much wider than it is
## tall, so a plain bounding radius would put the grade's endpoints far outside
## the plate and flatten the whole ramp into its middle third.
static func _reach(poly: PackedVector2Array, cen: Vector2, dir: Vector2) -> float:
	var r := 0.0
	for p in poly:
		r = maxf(r, absf((p - cen).dot(dir)))
	return r


static func _close(pts: PackedVector2Array, cols: PackedColorArray) -> Array:
	var p := pts.duplicate()
	var c := cols.duplicate()
	if pts.size() >= 2:
		p.append(pts[0]); c.append(cols[0])
		p.append(pts[1]); c.append(cols[1])
	return [p, c]
