class_name TutorialCoach
extends CanvasLayer
## THE COACHING LAYER — the overlay that says LOOK HERE, and then DO THIS.
##
## WHY IT IS ITS OWN CANVASLAYER, AND WHY THAT IS THE WHOLE BUG. Combat draws the
## hand on layer 20 and the HUD on layer 12, and every piece of the old guided
## first fight was built into `_hud_layer` — so a highlight on a HAND CARD could
## not be drawn over the card at all. What it did instead was set the card's own
## `modulate` to Color(1.16, 1.10, 0.72): a flat 16% warm tint, with no motion,
## on warm parchment, on a warm table. That is close to invisible, and it is the
## reason "drag the glowing creature" named a glow the player could not find.
## The coach sits at layer 30 — above the hand, below the layer-100 modals (the
## pile viewer and the glossary must still cover it).
##
## THREE DEVICES, in the order the onboarding literature says a player reads them
## (NN/g on instructional overlays; the coach-mark/spotlight pattern; Hearthstone's
## tutorial, which is still the reference implementation for a card game):
##   · THE SPOTLIGHT — one full-canvas scrim with soft-edged holes punched over
##     what matters. Attention is a subtraction problem before it is an addition
##     problem: dimming the other 90% of the screen is stronger than brightening
##     the 10%, and it costs the target no legibility.
##   · THE GLOW — a hot rim tracing the target's own silhouette plus an outward
##     halo, BREATHING on a slow loop. Motion is what makes a mark findable in
##     peripheral vision; a static highlight has to be looked at to be seen.
##   · THE GESTURE — an ink arrow that points, and a travelling dashed arc that
##     shows the DRAG ITSELF, from this card to that slot. A sentence describing
##     a gesture is a worse teacher than the gesture drawn on the board.
##
## EVERY DEVICE FOLLOWS ITS TARGET'S LIVE GLOBAL TRANSFORM, once per frame. This
## is not defensive coding — a hand card is re-laid-out on every play, lifts and
## scales on hover, and sits ROTATED in the fan, so a mark placed once from a
## rect is wrong by the next frame and wrong by ~8 degrees the whole time. Marks
## carry the target's rotation and scale, so the rim sits ON the card's edge.
##
## REDUCE MOTION: a coach mark is INFORMATIONAL — it is the only thing on screen
## telling the player what to do, so it must still LAND. The house contract for
## that case is "hold steady, don't remove": the pulse parks at its bright
## midpoint, the arrow stops bobbing, the dashes stop travelling. Nothing is
## deleted, and the read is unchanged.
##
## The three painters are inner classes rather than files in ui/painters/: they
## are one device in three parts, they are useless apart, and they share the
## follow-the-target contract that is the only subtle thing in here.

signal action_pressed
signal skip_pressed

## Holes in the scrim are FOUR scalar uniforms, not a `vec4[]` array uniform.
## Grouping is a feature and not a limit: a spotlight wearing eight small holes
## over eight lane slots reads as swiss cheese, where one hole over "your side of
## the field" reads as a place. `focus()` merges what it is given.
const SCRIM_MAX_HOLES := 4

## The narrowest the step panel may be squeezed to in order to sit BESIDE a tall
## spotlight rather than on top of it — see the narrowing branch in `_place_panel`.
## Below this the body's measure gets too short to read comfortably (COPY_STYLE
## §11 wants 50-80 characters a line), so a narrower panel is the worse trade and
## the placement gives up instead.
const MIN_PANEL_W := 420.0

## Layer 30: over the hand (20) and the HUD (12), under the modals (100).
const COACH_LAYER := 30

const SCRIM_CODE := """shader_type canvas_item;

uniform vec2 rect_size = vec2(1600.0, 900.0);
uniform vec4 dim : source_color = vec4(0.010, 0.008, 0.016, 1.0);
uniform float amount = 0.70;
uniform int hole_count = 0;
uniform vec4 hole0 = vec4(0.0);
uniform vec4 hole1 = vec4(0.0);
uniform vec4 hole2 = vec4(0.0);
uniform vec4 hole3 = vec4(0.0);
uniform float corner = 16.0;
// The feather is generous on purpose. A hard-edged hole reads as a cut-out
// rectangle sitting ON the game; a soft one reads as light falling on the
// thing underneath, which is what a spotlight is.
//
// AND THE PENUMBRA FALLS OUTSIDE THE LIT THING. The band used to run from 34px
// INSIDE the opening to 10px outside it, so the target's own border — the exact
// pixels the glow rim traces — was still being dimmed by the spotlight that was
// meant to be revealing it, and the hole read as a soft-cornered window rather
// than as a beam. It now sits almost entirely OUTSIDE: full brightness from a
// few px inside the edge, dying ~31px out, the way a real beam spills past what
// it lights.
uniform float feather = 34.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float opening(vec4 h, vec2 p) {
	// xy = centre, zw = half-extents.
	float d = sd_round_box(p - h.xy, max(h.zw, vec2(1.0)), corner);
	float o = 1.0 - smoothstep(-feather * 0.20, feather * 0.90, d);
	// Light does not fall off in a straight line. The gamma widens the fully-lit
	// core and leaves a long thin tail, which is the shape of a real penumbra —
	// a plain smoothstep has its steepest change in the middle and reads as a
	// blurred edge instead of as a beam.
	return pow(clamp(o, 0.0, 1.0), 0.72);
}

void fragment() {
	vec2 p = UV * rect_size;
	float open = 0.0;
	if (hole_count > 0) { open = max(open, opening(hole0, p)); }
	if (hole_count > 1) { open = max(open, opening(hole1, p)); }
	if (hole_count > 2) { open = max(open, opening(hole2, p)); }
	if (hole_count > 3) { open = max(open, opening(hole3, p)); }
	// SCATTER. The half-open band is where light is spilling INTO the shadow, not
	// where it stops, so the dim warms there rather than staying flat and cold —
	// the same reason a lamp in a dark room has a glow around it and not a rim.
	// It costs nothing (the alpha is already low there) and it is most of what
	// separates "a beam" from "a hole cut in a grey rectangle".
	float bleed = clamp(open * (1.0 - open) * 4.0, 0.0, 1.0);
	vec3 tone = dim.rgb + vec3(0.080, 0.045, 0.015) * bleed;
	COLOR = vec4(tone, amount * (1.0 - open));
}
"""

## THE GLOW. A rounded-box SDF gives the rim and the halo from one distance, so
## the mark traces the target's real silhouette instead of being a rectangle
## bolted near it.
##
## THE INTERIOR IS LEFT CLEAR, and that is load-bearing: this is a card with
## rules text on it, and washing the inside to prove it is highlighted would
## make the highlighted card the one card you cannot read. The halo is strictly
## outward; the rim sits on the border and goes white-hot at its centre, which is
## the house contrast rule (a warm-only mark on a warm table is camouflage).
const GLOW_CODE := """shader_type canvas_item;

uniform vec2 rect_size = vec2(64.0);
uniform vec2 box = vec2(24.0);
uniform float corner = 10.0;
uniform vec4 tint : source_color = vec4(1.0, 0.83, 0.38, 1.0);
uniform float spread = 20.0;
uniform float rim = 2.4;
uniform float pulse = 0.0;
uniform float intensity = 1.0;
// THE RAKE, in the MARK'S OWN space. `sync()` counter-rotates one fixed screen
// direction into it, so a card sitting at 8 degrees in the fan is lit from the
// same place as the slot beside it instead of carrying its own highlight around
// with it as it tilts.
uniform vec2 light_dir = vec2(-0.55, -0.84);

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * rect_size;
	vec2 b = max(box, vec2(1.0));
	float d = sd_round_box(p, b, corner);

	// THE BREATH LIVES IN THE HALO, AND ALMOST NOWHERE ELSE. A mark whose OUTLINE
	// dims and brightens by 40% reads as a failing bulb; one whose halo swells and
	// settles while the outline holds steady reads as something alive standing on
	// the board. So `pulse` moves the halo's reach and its weight — and the rim's
	// width, which is a swell rather than a flicker — while the rim's opacity
	// barely moves at all. The "where" channel must never be the thing that dims.
	float sp = spread * (0.78 + 0.46 * pulse);
	float halo = exp(-max(d, 0.0) / max(sp, 0.5));
	halo *= smoothstep(-1.5, 1.0, d);
	// TWO FALLOFFS, NOT ONE. A single exponential is a blur: it leaves the same
	// soft grey-gold mush at 4px out as at 20px, which is why the mark read as a
	// glow FILTER applied to a rectangle. Real light has a tight hot skirt sitting
	// inside a wide soft spill, and the two together are most of what separates
	// "something is shining here" from "someone turned the bloom up".
	float bloom = exp(-max(d, 0.0) / max(sp * 0.30, 0.5));
	bloom *= smoothstep(-1.5, 1.0, d);
	// ...AND IT MAY NEVER TERMINATE IN A RECTANGLE. The halo is drawn inside a
	// quad, and at the old padding it was still worth ~0.25 alpha where it met
	// that quad's edge — a soft light ending on a hard box, on every mark in the
	// game. `sync()` now sizes the quad to the halo's real reach; this windows the
	// last few pixels so no combination of pad and spread can bring the seam back.
	vec2 room = min(UV, vec2(1.0) - UV) * rect_size;
	float window = smoothstep(0.0, 7.0, min(room.x, room.y));
	halo *= window;
	bloom *= window;

	// THE RIM IS NOT UNIFORM, because nothing gilt ever is. The outward normal
	// comes off the SDF by finite difference; a raking light lifts the edges
	// facing it and lets the far ones fall back, and three harmonics keep the
	// stroke from reading as a machine-drawn outline.
	//
	// THE OLD NUMBERS WERE BELOW THE PERCEPTUAL FLOOR AND THE SHOT PROVED IT. A
	// rake of mix(0.80, 1.15) is a 17% swing and a 5.5% grain is a rounding error:
	// photographed on a board slot, all four sides of the mark measured the same
	// value, so the rim rendered as an extruded tube of even width and even
	// brightness — a CSS box-shadow, the single loudest programmer-art tell there
	// is. The swing is now wide enough to see (the shaded side falls to ~0.46)
	// because the CORE below is what carries the read, which is exactly what frees
	// the shoulders to be a light rather than an outline.
	float e = 1.25;
	vec2 g = vec2(
		sd_round_box(p + vec2(e, 0.0), b, corner) - sd_round_box(p - vec2(e, 0.0), b, corner),
		sd_round_box(p + vec2(0.0, e), b, corner) - sd_round_box(p - vec2(0.0, e), b, corner));
	vec2 nrm = normalize(g + vec2(0.00001, 0.00001));
	float lit = 0.5 + 0.5 * dot(nrm, normalize(light_dir + vec2(0.00001, 0.00001)));
	float ang = atan(nrm.y, nrm.x);
	float grain = 1.0 + 0.105 * sin(ang * 3.0 + 0.9) + 0.062 * sin(ang * 7.0 - 2.1)
		+ 0.034 * sin(ang * 13.0 + 1.7);
	float rake = clamp(mix(0.46, 1.22, lit) * grain, 0.0, 1.5);

	// NIB PRESSURE. The rake above only ever changed the rim's OPACITY, and an
	// outline of constant width is the other half of why this photographed as an
	// extruded tube: a stroke that a hand or a light made is WIDER where it is
	// brighter. Feeding the same lit/grain signal into the width as well is what
	// turns the outline into the quill language the pointing arrow is already
	// drawn in — and it costs nothing, because `band`, `core` and `filament` are
	// all measured against `rw` and follow it automatically.
	float press = clamp(0.5 + 0.80 * (lit - 0.5) + 2.2 * (grain - 1.0), 0.0, 1.0);
	float rw = max(rim * (1.0 + 0.55 * pulse) * mix(0.80, 1.24, press), 0.8);
	float band = 1.0 - smoothstep(0.0, rw, abs(d));
	// A WHITE-HOT CORE, NARROWER THAN THE BAND IT SITS IN — AND WIDE ENOUGH TO
	// SURVIVE THE SCREENSHOT. The house contrast rule is that a warm mark on warm
	// parchment over a warm table is camouflage, and the rim was failing it while
	// claiming not to: sampled across a lit slot, the hottest pixel in the whole
	// mark measured (237, 217, 173) — a warm cream, two pixels wide, the same hue
	// as the ember ground a hand card sits on. The core was a hairline (0.55 of
	// the band) at 95% of the way to white, so it never reached white and never
	// covered enough pixels to be seen. It is now 0.85 of the band, goes all the
	// way, and CONTRIBUTES TO ALPHA so the rake can never dim it out: the
	// "where" channel must be continuous all the way round the silhouette even
	// where the light is not.
	//
	// AND THE FILAMENT HAS TO COVER PIXELS. The first attempt at this put the
	// pure-white line at 0.40 of a 2px rim — a band 0.8px wide, which a pixel
	// centre almost never lands inside, so the measured peak came back at
	// (237, 221, 187): still a cream, still the ground's own hue. A hot core that
	// falls between the samples is not a hot core. 0.55 of the band with a 1.3px
	// floor is the narrowest that reliably lights a pixel at the smallest rim any
	// caller asks for.
	float core = 1.0 - smoothstep(0.0, max(rw * 0.88, 1.5), abs(d));
	float filament = 1.0 - smoothstep(0.0, max(rw * 0.55, 1.3), abs(d));
	// A short INWARD bleed, so the rim sits ON the silhouette rather than beside
	// it. Deliberately faint and shallow — this is a card with rules text on it,
	// the interior is left clear on purpose, and this is an edge catching light,
	// not a wash proving the card is selected.
	float inner = 0.24 * (1.0 - smoothstep(0.0, rw * 2.2, max(-d, 0.0)))
		* (1.0 - smoothstep(-0.5, 1.5, d));

	// COLOUR: white at the core, the mark's own gold on the shoulders, pushed
	// toward ember out in the halo. Light scatters warm as it goes — a glow that
	// holds one flat hue all the way out is a gradient, not a light.
	vec3 ember = tint.rgb * vec3(1.0, 0.68, 0.36);
	float far = clamp(max(d, 0.0) / max(sp * 1.8, 1.0), 0.0, 1.0);
	vec3 col = mix(tint.rgb, ember, far * 0.72);
	col = mix(col, mix(tint.rgb, vec3(1.0), 0.72), clamp(core, 0.0, 1.0));
	col = mix(col, vec3(1.0), clamp(filament, 0.0, 1.0));

	float rim_a = clamp(band * rake + core * 0.80 + inner, 0.0, 1.0)
		* (0.90 + 0.10 * pulse);
	float halo_a = halo * (0.50 + 0.34 * pulse) + bloom * (0.34 + 0.26 * pulse);
	float a = clamp(halo_a + rim_a, 0.0, 1.0);
	COLOR = vec4(col, a * tint.a * intensity);
}
"""

var _scrim: ColorRect = null
## The openings, rebuilt every frame from the live targets below.
var _scrim_holes: Array[Rect2] = []
## Controls whose current rect is an opening (held weakly — a spotlit body can
## die mid-lesson), plus any fixed rects a caller asked for outright.
var _focus_targets: Array = []
var _focus_rects: Array[Rect2] = []
## Every live mark: {"node": Control, "ref": WeakRef, "kind": String, ...}.
var _marks: Array[Dictionary] = []
var _panel: PanelContainer = null
var _title: Label = null
var _body: Label = null
## The recoverability line — see `show_panel`'s `note`.
var _note: Label = null
var _step_chip: Label = null
var _action: Button = null
var _skip: Button = null
## Bumped per placement request so a superseded one drops out — see _place_panel.
var _place_token: int = 0
## A panel is not interactive until its final, collision-free rect is known.
var _panel_ready: bool = false
var _panel_reveal_tween: Tween = null



## A cheap "have the openings stopped moving?" fingerprint, rounded so sub-pixel
## drift does not read as motion.
func _holes_signature() -> String:
	var parts: Array[String] = []
	for r in _scrim_holes:
		parts.append("%d,%d,%d,%d" % [roundi(r.position.x), roundi(r.position.y),
			roundi(r.size.x), roundi(r.size.y)])
	return "|".join(parts)


static func reduced() -> bool:
	return UserSettings != null and UserSettings.reduce_motion


static func headless() -> bool:
	return DisplayServer.get_name() == "headless"


## The AABB a control actually occupies on screen, THROUGH its transform. A hand
## card is rotated in the fan and scaled by the hover lift, so `get_global_rect()`
## — which is position + size and knows about neither — is the wrong rect by
## enough to miss the card's corners entirely.
static func visual_rect(c: Control) -> Rect2:
	var xf := c.get_global_transform()
	var s := c.size
	var r := Rect2(xf * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]:
		r = r.expand(xf * corner)
	return r


## WHERE A RAY INTO A CONTROL CROSSES ITS REAL EDGE, plus `out` px of standoff.
##
## The AABB is the wrong shape to stand off from and a hand card is why: a
## 162x216 card tilted 8 degrees in the fan has a 190px-wide `visual_rect`, so a
## mark placed a flat gap outside that box sits ~28px clear of the art it is
## naming, in the empty wedge beside the corner. This walks the ray in the
## target's OWN space — through its live transform, so rotation and the hover
## scale are both already in it — and comes back with a point on the card.
##
## `dir` points INTO the target (the direction the arrow travels), matching
## `PointerMark._dir`; the returned point lies on the far side, standing off
## against that travel.
static func edge_standoff(c: Control, dir: Vector2, out: float) -> Vector2:
	var xf := c.get_global_transform()
	var half := c.size * 0.5
	var outward := xf.affine_inverse().basis_xform(-dir)
	var sx: float = half.x / maxf(absf(outward.x), 0.0001)
	var sy: float = half.y / maxf(absf(outward.y), 0.0001)
	return (xf * (half + outward * minf(sx, sy))) - dir * out


## A NOTCHED ARROWHEAD — the back edge cut in toward the point. Shared by the
## pointing arrow and the drag arc so the two devices are visibly one hand's
## work. A plain isoceles triangle is the programmer-art default and reads as a
## mouse cursor; the notch is what every drawn arrow in every margin has.
##
## THE DEFAULT WAS 0.30 AND IT WAS TOO DEEP TO BE A HEAD. Cutting 30% of the
## length out of the back edge leaves two thin wings and an empty V on the
## centreline — photographed at size, the head read as a "greater-than" sign and
## the shaft, which stopped at the back edge, could not reach across the void to
## join it. So: a shallower notch (a mark, not a fork) and a shaft that runs INTO
## it (see `PointerMark._draw`). Both halves were needed; either alone still
## leaves a seam where the arrow's two pieces meet.
static func arrow_head(tip: Vector2, dir: Vector2, perp: Vector2,
		head_len: float, head_w: float, notch: float = 0.20) -> PackedVector2Array:
	var back := tip - dir * head_len
	return PackedVector2Array([tip, back + perp * head_w,
		back + dir * (head_len * notch), back - perp * head_w])


## Expand a polygon about its centroid — a cheap even outline at these sizes,
## and correct on the shallow notch of an arrowhead: the notch vertex sits almost
## ON the centroid, so it barely moves while the three outer points push out, and
## the under-stroke stays behind the body instead of cutting through it.
static func grow_poly(poly: PackedVector2Array, by: float) -> PackedVector2Array:
	if poly.is_empty():
		return poly
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var out := PackedVector2Array()
	for p in poly:
		var d := p - c
		out.append(p + (d.normalized() if d.length() > 0.01 else Vector2.ZERO) * by)
	return out


func _init() -> void:
	layer = COACH_LAYER
	set_process(false)


func _ready() -> void:
	set_process(not _marks.is_empty() or _scrim != null)


## ESC LEAVES THE LESSON — WCAG 2.1.1, and the modal-dismissal convention every
## player already has in their hands.
##
## IT IS DELIBERATELY NARROW, because Esc belongs to the pause menu on every
## screen this layer appears over. The binding exists only while a panel is up
## AND that panel is showing a skip button — i.e. during the guided walkthrough
## and nowhere else — and the coach is freed the moment the walkthrough ends, so
## the hijack cannot outlive its window. A panel with a primary button instead
## already answers Enter and Space (see `show_panel`) and is left alone here, so
## Esc keeps reaching the pause menu on every read-and-acknowledge card.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not _panel_ready:
		return
	if _panel == null or not is_instance_valid(_panel):
		return
	if _skip == null or not is_instance_valid(_skip) or not _skip.visible:
		return
	get_viewport().set_input_as_handled()
	skip_pressed.emit()


# ── The spotlight ──────────────────────────────────────────────────────

## Dim the screen except over `targets`. Passing an empty array (or calling
## `clear_focus`) fades the scrim out and drops it.
##
## Rects are MERGED before they are punched: nearby openings become one opening,
## because "your side of the field" is a place a player can look at and eight
## lane-sized holes are a texture.
func focus(targets: Array, amount: float = 0.66) -> void:
	_focus_targets.clear()
	_focus_rects.clear()
	for t in targets:
		if t is Rect2:
			_focus_rects.append(t)
		elif t is Control and is_instance_valid(t):
			_focus_targets.append(weakref(t))
	if _focus_targets.is_empty() and _focus_rects.is_empty():
		clear_focus()
		return
	_ensure_scrim()
	_scrim.material.set_shader_parameter("amount", amount)
	_recompute_holes()
	_push_holes()
	set_process(true)


## Rebuild the openings from wherever their targets are RIGHT NOW.
##
## Called every frame, and it has to be: a creature that was just played is
## still flying to its slot, so a rect taken at `focus()` time is the rect of the
## animation. Holding the targets and re-measuring means the opening snaps onto
## the body when it lands — and travels with a card the player drags.
func _recompute_holes() -> void:
	var rects: Array[Rect2] = _focus_rects.duplicate()
	var dead: Array = []
	for ref in _focus_targets:
		var t = (ref as WeakRef).get_ref()
		if t == null or not is_instance_valid(t):
			dead.append(ref)
			continue
		rects.append(visual_rect(t).grow(10.0))
	for d in dead:
		_focus_targets.erase(d)
	# NOT a ternary with `[] as Array[Rect2]` (2026-09-16). **`as` DOES NOT RETYPE
	# AN EMPTY ARRAY LITERAL** — `[] as Array[Rect2]` is still an untyped `Array`,
	# so assigning it to `_scrim_holes` threw "Trying to assign an array of type
	# Array to a variable of type Array[Rect2]" and, because a failed assignment
	# ABORTS the function where it stands, `_scrim_holes` kept its previous value.
	# The visible result is the spotlight staying punched over bodies that are gone
	# instead of closing, and it only happens on the branch where every focus target
	# has died — which is why no gate had ever reached it. Found by a procedural
	# persona, whose back-row placement fires the `back_row` lesson and then lets
	# those targets die. Verified in isolation: the non-empty branch is fine and the
	# empty branch throws every time.
	if rects.is_empty():
		_scrim_holes.clear()
	else:
		_scrim_holes = _merge_rects(rects)


func clear_focus() -> void:
	_focus_targets.clear()
	_focus_rects.clear()
	_scrim_holes.clear()
	if _scrim == null or not is_instance_valid(_scrim):
		_scrim = null
		return
	var s := _scrim
	_scrim = null
	if headless() or reduced():
		s.queue_free()
		return
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, 0.22)
	tw.tween_callback(s.queue_free)


func _ensure_scrim() -> void:
	if _scrim != null and is_instance_valid(_scrim):
		return
	var sh := Shader.new()
	sh.code = SCRIM_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var rect := ColorRect.new()
	rect.name = "CoachScrim"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.WHITE
	# The scrim must never eat a click: the whole point of the hole is that the
	# player reaches through it, and the drag they are being taught crosses the
	# dimmed part of the screen on its way.
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.z_index = 0
	add_child(rect)
	_scrim = rect
	if not headless() and not reduced():
		rect.modulate.a = 0.0
		rect.create_tween().tween_property(rect, "modulate:a", 1.0, 0.26)


## Push the current openings into the shader. Called every frame while marks are
## live, because a hole tracks the card being dragged through it.
func _push_holes() -> void:
	if _scrim == null or not is_instance_valid(_scrim):
		return
	var mat: ShaderMaterial = _scrim.material
	# THE CANVAS, NOT THE PROJECT SETTING. Under `canvas_items` stretch, UI Scale
	# 60% lays the UI out on 2667x1500 — reading the size from ProjectSettings
	# (which is static) is the C32 defect, and it puts the whole scrim in the
	# top-left corner of the screen at four of the five scales offered.
	mat.set_shader_parameter("rect_size", _scrim.size)
	mat.set_shader_parameter("hole_count", mini(_scrim_holes.size(), SCRIM_MAX_HOLES))
	for i in SCRIM_MAX_HOLES:
		if i >= _scrim_holes.size():
			break
		var r: Rect2 = _scrim_holes[i]
		mat.set_shader_parameter("hole%d" % i, Vector4(
			r.get_center().x, r.get_center().y, r.size.x * 0.5, r.size.y * 0.5))


## Merge rects that touch or nearly touch, then keep the largest few. Repeated
## until nothing merges, so a row of adjacent lane slots collapses to one band in
## a single call rather than pairwise-by-luck.
func _merge_rects(rects: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = rects.duplicate()
	var merged := true
	while merged:
		merged = false
		for i in out.size():
			for j in range(i + 1, out.size()):
				if out[i].grow(26.0).intersects(out[j].grow(26.0)):
					out[i] = out[i].merge(out[j])
					out.remove_at(j)
					merged = true
					break
			if merged:
				break
	out.sort_custom(func(a: Rect2, b: Rect2) -> bool:
		return a.get_area() > b.get_area())
	if out.size() > SCRIM_MAX_HOLES:
		out.resize(SCRIM_MAX_HOLES)
	return out


# ── The marks ──────────────────────────────────────────────────────────

## Trace `target` with a breathing rim + halo. `opts`: color, pad, corner,
## spread, rim, delay.
func mark(target: Control, opts: Dictionary = {}) -> void:
	if target == null or not is_instance_valid(target):
		return
	var pad: float = float(opts.get("pad", 26.0))
	var g := GlowMark.new()
	g.pad = pad
	g.tint = opts.get("color", Color(1.0, 0.82, 0.34, 1.0))
	g.corner = float(opts.get("corner", 12.0))
	g.spread = float(opts.get("spread", 20.0))
	g.rim_px = float(opts.get("rim", 2.4))
	g.z_index = 10
	add_child(g)
	g.bind(target)
	g.begin(float(opts.get("delay", 0.0)))
	_marks.append({"node": g, "ref": weakref(target), "kind": "glow"})
	set_process(true)


## An ink arrow that points AT `target` from the given side ("left", "right",
## "up", "down", or "auto"), bobbing along its own axis so the eye catches it.
##
## THE SIDE IS A PREFERENCE, NOT AN ORDER. A named side is taken whenever the
## whole stroke fits on the canvas and quietly swapped for one that does when it
## does not — a 96px arrow asked for from the left of something 40px from the
## left edge used to be drawn off-screen, head first. "auto" skips the preference
## and comes in from the roomiest face. The tip lands on the target's REAL edge
## (rotation and hover scale included), not on its bounding box.
func point_at(target: Control, opts: Dictionary = {}) -> void:
	if target == null or not is_instance_valid(target):
		return
	var a := PointerMark.new()
	a.side = String(opts.get("from", "left"))
	a.tint = opts.get("color", Color(1.0, 0.80, 0.30, 1.0))
	a.length = float(opts.get("length", 96.0))
	a.gap = float(opts.get("gap", 16.0))
	a.z_index = 12
	add_child(a)
	a.bind(target)
	a.begin()
	_marks.append({"node": a, "ref": weakref(target), "kind": "arrow"})
	set_process(true)


## THE GESTURE: a dashed ink arc from `from` to `to`, dashes travelling toward
## the destination. This is the one device that teaches a VERB rather than a
## place — "drag this card onto that slot" is a sentence; this is the movement.
func gesture(from: Control, to: Control, opts: Dictionary = {}) -> void:
	if from == null or to == null or not is_instance_valid(from) \
			or not is_instance_valid(to):
		return
	var p := PathMark.new()
	p.tint = opts.get("color", Color(1.0, 0.80, 0.30, 1.0))
	p.head_tint = opts.get("head_color", Color(1.0, 0.42, 0.13, 1.0))
	p.lift = float(opts.get("lift", 0.28))
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 11
	add_child(p)
	p.bind_pair(from, to)
	p.begin()
	_marks.append({"node": p, "ref": weakref(from), "ref_b": weakref(to),
		"kind": "path"})
	set_process(true)


func clear_marks() -> void:
	for m in _marks:
		var n = m.get("node")
		if n != null and is_instance_valid(n):
			n.dismiss()
	_marks.clear()
	set_process(_scrim != null)


## Flare everything, once. For the moment a player does something the current
## step cannot accept: the answer to "why did that do nothing" should be a flash
## where they have to act, not only a line of text somewhere else on the screen.
func nudge() -> void:
	if headless():
		return
	if _panel != null and is_instance_valid(_panel):
		Motion.punch(_panel, 1.04)
	for m in _marks:
		var n = m.get("node")
		if n != null and is_instance_valid(n) and n.has_method("kick"):
			n.kick()


## One sync per frame. A mark whose target has been freed or hidden leaves with
## it — a glowing rim around a card that is no longer there is worse than no
## mark, because the player goes looking for the card.
func _process(_delta: float) -> void:
	var dead: Array[Dictionary] = []
	for m in _marks:
		var n = m.get("node")
		if n == null or not is_instance_valid(n):
			dead.append(m)
			continue
		var t = (m["ref"] as WeakRef).get_ref()
		var alive: bool = t != null and is_instance_valid(t) \
			and (t as Control).is_visible_in_tree()
		if alive and m.has("ref_b"):
			var b = (m["ref_b"] as WeakRef).get_ref()
			alive = b != null and is_instance_valid(b) \
				and (b as Control).is_visible_in_tree()
		if not alive:
			n.dismiss()
			dead.append(m)
			continue
		n.sync()
	for m in dead:
		_marks.erase(m)
	# The openings follow their targets too: the hole over the card the player is
	# being taught to drag has to travel WITH the card, or the lesson dims the
	# thing it just told them to pick up.
	if _scrim != null and is_instance_valid(_scrim):
		_recompute_holes()
		_push_holes()
	if _marks.is_empty() and _scrim == null:
		set_process(false)


# ── The panel ──────────────────────────────────────────────────────────

## Post the step. `step`/`steps` draw a progress chip — knowing a walkthrough is
## three steps long and not thirty is most of what stops a player skipping it.
## An `action_text` swaps the SKIP button for a commit button.
##
## `opts` — `skip_text` overrides the secondary button's label and "" hides it
## outright; `note` prints a small line under the copy. The note exists for ONE
## sentence and it is the most important sentence in here: where the coaching
## went when you skip it. A skip that cannot be undone is not a skip, it is a
## trapdoor, and the player has to be told the ladder is in Settings AT the
## moment they are deciding — not in a help screen they have no reason to open.
func show_panel(title: String, body: String, action_text: String = "",
		step: int = 0, steps: int = 0, opts: Dictionary = {}) -> void:
	_ensure_panel()
	_title.text = title
	_body.text = body
	if steps > 0:
		_step_chip.text = "STEP %d OF %d" % [step, steps]
		_step_chip.visible = true
	else:
		_step_chip.visible = false
	_action.visible = action_text != ""
	if action_text != "":
		_action.text = action_text
	# "SKIP TUTORIAL", not "SKIP" and never an X. A bare SKIP does not say whether
	# it drops this step or the whole walkthrough, and NN/g's onboarding component
	# analysis asks for a highly visible skip that names its consequence. (It is
	# also two capped words, which is what keeps `_check_shouting` off it — a lone
	# capped word of 3+ chars fails the copy lint.)
	var skip_text := String(opts.get("skip_text",
		"SKIP TUTORIAL" if action_text == "" else ""))
	_skip.visible = skip_text != ""
	if skip_text != "":
		_skip.text = skip_text
	var note := String(opts.get("note", ""))
	_note.text = note
	_note.visible = note != ""
	# Placement owns reveal, focus, and input; it can safely wait for moving
	# spotlight targets without exposing the origin or the prior step's rect.
	_place_panel()
	# KEYBOARD DISMISSAL, and only where it is safe. A panel with a primary button
	# is a read-and-acknowledge panel, so Enter/Space landing on GOT IT is exactly
	# right. A panel WITHOUT one is a step whose affordance is the board — parking
	# focus on SKIP there would make the space bar quit the walkthrough, which is
	# the opposite of an accessibility win.


func hide_panel() -> void:
	_place_token += 1
	_panel_ready = false
	if _panel_reveal_tween != null and _panel_reveal_tween.is_valid():
		_panel_reveal_tween.kill()
	_panel_reveal_tween = null
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_title = null
	_body = null
	_note = null
	_step_chip = null
	_action = null
	_skip = null


func dismiss() -> void:
	clear_marks()
	clear_focus()
	hide_panel()


func _ensure_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	var panel := PanelContainer.new()
	panel.name = "CoachPanel"
	panel.z_index = 20
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("_coach_placement_ready", false)
	var style := GameTheme.make_panel_style(
		Color(0.035, 0.024, 0.025, 0.97),
		Color(0.96, 0.76, 0.30, 0.92), 2, 6, false)
	style.content_margin_left = 20
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_panel = panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 3)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)

	_step_chip = GameTheme.make_label("", 14, Color(0.80, 0.68, 0.44), true)
	copy.add_child(_step_chip)
	_title = GameTheme.make_label("", 21, Color(1.0, 0.84, 0.42), true)
	copy.add_child(_title)
	# 18, not the 17 this used to run at: COPY_STYLE §11 puts the reading floor at
	# 18px and a walkthrough body is READING text, not a caption. It is also the
	# one paragraph in the game aimed at someone who has never played it.
	_body = GameTheme.make_label("", 18, Color(0.96, 0.92, 0.80), true)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(_body)
	# 15px: a caption chip riding a bigger element, which is precisely COPY_STYLE
	# §11's middle register and its floor. It is subordinate to the lesson and must
	# not compete with it — but it states where a control lives, so it is
	# informational and may not go below 15.
	_note = GameTheme.make_label("", 15, Color(0.74, 0.64, 0.46), true)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	copy.add_child(_note)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	_action = _make_button("GOT IT")
	_action.visible = false
	_action.pressed.connect(func(): action_pressed.emit())
	actions.add_child(_action)
	_skip = _make_button("SKIP")
	_skip.pressed.connect(func(): skip_pressed.emit())
	actions.add_child(_skip)


## Sit the panel where it covers nothing it is talking about.
##
## THE CANDIDATE LIST IS ORDERED BY PREFERENCE, NOT BY DISTANCE TO THE CENTRE,
## and that ordering is the whole fix. Scoring by "closest to the middle of the
## screen" is the obvious rule and it is wrong: the lane lesson opens a column
## from the enemy's front row down to yours, and the roomiest central gap in
## that layout is the gap BETWEEN the two creatures being compared — so the
## panel parked itself exactly between the two things the sentence was asking the
## player to look at. Going round the block (above, below, beside) instead puts
## it out of the way of a tall opening and keeps it central for a wide one.
##
## Everything is derived from the live canvas rect, never a constant — see the
## C32 note in `_push_holes`.
func _place_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var canvas := get_viewport().get_visible_rect()
	_place_token += 1
	var token := _place_token
	_panel_ready = false
	if _panel_reveal_tween != null and _panel_reveal_tween.is_valid():
		_panel_reveal_tween.kill()
	_panel_reveal_tween = null
	_panel.modulate.a = 0.0
	_panel.scale = Vector2.ONE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_meta("_coach_placement_ready", false)
	if _action != null and is_instance_valid(_action):
		_action.release_focus()
		_action.disabled = true
	if _skip != null and is_instance_valid(_skip):
		_skip.release_focus()
		_skip.disabled = true
	var w: float = clampf(canvas.size.x * 0.50, 520.0, 820.0)
	_panel.custom_minimum_size = Vector2(w, 0.0)
	# SETTLE BEFORE MEASURING. The panel's height is only known once the body has
	# wrapped to that width — but more importantly the OPENINGS are still moving:
	# a creature that was just played is flying to its slot, and a rect read on
	# the next frame is the rect of the animation rather than of the board. Poll
	# until the openings HOLD, then measure. (`_token` makes the newest call the
	# only one that lands, since two steps in quick succession would otherwise
	# both be parked in here.)
	#
	# AND IT HAS TO HOLD FOR MORE THAN ONE FRAME. Breaking on the first pair of
	# equal signatures is not a settle, it is a coin toss: a creature easing into
	# its slot passes through frames whose rounded rect repeats, and a hand still
	# dealing has not started moving the card that is about to move. Photographed,
	# step 2 measured a keep-out that was still in flight, narrowed the panel to
	# fit a gutter beside a block that then settled 180px to the right, and parked
	# the copy across the top of the very creature its own sentence names. Nothing
	# re-places the panel afterwards, so a single bad reading is permanent.
	var prev := _holes_signature()
	var held := 0
	for _i in 48:
		await get_tree().process_frame
		if _panel == null or not is_instance_valid(_panel) or token != _place_token:
			return
		var now := _holes_signature()
		if now == prev:
			held += 1
			if held >= 3:
				break
		else:
			held = 0
		prev = now
	var h: float = maxf(_panel.get_combined_minimum_size().y, 104.0)
	_panel.pivot_offset = Vector2(w, h) * 0.5   # so `nudge`'s punch grows from the middle
	var pad := 24.0
	var cx: float = canvas.position.x + (canvas.size.x - w) * 0.5
	var fallback := Vector2(cx, canvas.position.y + canvas.size.y * 0.30)

	# The hand is never a valid resting place, spotlight or not: a panel over the
	# fan hides the cards in every step that asks the player to play one. Taken as
	# a FRACTION of the live canvas so it survives UI Scale.
	var hand_band := Rect2(
		Vector2(canvas.position.x, canvas.position.y + canvas.size.y * 0.80),
		Vector2(canvas.size.x, canvas.size.y * 0.20))

	# The keep-out IS the spotlight: whatever the step opened is, by definition,
	# what the step is talking about, so the copy must not sit on it.
	var block := Rect2()
	var has_block := false
	for a in _scrim_holes:
		block = a if not has_block else block.merge(a)
		has_block = true

	var candidates: Array[Vector2] = []
	if has_block:
		var side_y: float = clampf(block.get_center().y - h * 0.5,
			canvas.position.y + 12.0, canvas.end.y - h - 12.0)
		candidates.append(Vector2(cx, block.position.y - h - pad))
		candidates.append(Vector2(cx, block.end.y + pad))
		candidates.append(Vector2(block.end.x + pad, side_y))
		candidates.append(Vector2(block.position.x - w - pad, side_y))
	candidates.append(fallback)
	# A LADDER OF FALLBACKS, not one. With a single fallback the "least-worst"
	# scoring below has nothing to choose between, and that was the whole reason
	# the Recruit fix did not take: its spotlight is the card row in the middle of
	# the screen, so the four side candidates are all rejected and the ONE
	# remaining position happened to sit on the season subtitle. Offering the
	# panel several heights down the canvas gives the scoring something to do —
	# these are ordered top-down and only reached when everything above failed.
	for frac in [0.06, 0.18, 0.44, 0.58, 0.70]:
		candidates.append(Vector2(cx, canvas.position.y + canvas.size.y * frac))

	var text_rects := _host_text_rects()
	var chosen := fallback
	var soft := fallback
	var soft_cost := INF
	var has_soft := false
	var found := false
	for c in candidates:
		var rect := Rect2(c, Vector2(w, h))
		if rect.position.x < canvas.position.x + 12.0 \
				or rect.position.y < canvas.position.y + 12.0 \
				or rect.end.x > canvas.end.x - 12.0 \
				or rect.end.y > canvas.end.y - 12.0:
			continue
		if rect.intersects(hand_band):
			continue
		if has_block and rect.intersects(block):
			continue
		# ...AND IT MUST NOT BURY THE SCREEN'S OWN WORDS. The keep-out above is
		# only the spotlight, so on any screen with prose outside it the panel was
		# free to land on that prose: `_probe_occlusion` caught this panel sitting
		# on Recruit's season subtitle at 63% overlap, and its GOT IT button on the
		# same line at 67%. A lesson that explains the screen by hiding the screen
		# is the same defect as one that covers its own spotlight — a softer
		# preference, though, not a veto, because on a dense screen every candidate
		# may touch SOME label and a placed panel beats no panel.
		var buried := _buried_area(rect, text_rects)
		if buried > 0.0:
			# LEAST-WORST, not first-worst. Keeping the first text-burying
			# candidate was the same as having no rule at all on a dense screen:
			# Recruit's spotlight is the card row in the middle, so EVERY
			# candidate touches something, and "first" is the above-slot — which
			# is exactly the subtitle the gate was complaining about. Scoring by
			# how much prose is actually lost picks the gap that costs least.
			if not has_soft or buried < soft_cost:
				soft = c
				soft_cost = buried
				has_soft = true
			continue
		chosen = c
		found = true
		break
	if not found and has_soft:
		chosen = soft

	# NOTHING FITS AT FULL WIDTH — SO NARROW, DON'T SURRENDER.
	#
	# The four candidates above are all-or-nothing at the panel's preferred width,
	# and `fallback` is accepted unconditionally when they all fail. For a TALL
	# opening that is a silent defect: the lane lesson spotlights a column from the
	# enemy's back row down to yours (~632px of a 900px canvas), which leaves no
	# room above or below, and the side gutters are narrower than the panel — so
	# every candidate was rejected and the copy parked itself squarely on the two
	# creatures the sentence was asking the player to compare. That is the exact
	# failure this function's header claims to have fixed; it was fixed for the
	# ORDERING and not for the case where nothing fits at all.
	#
	# A side gutter that cannot take an 820px panel can very often take a 520px
	# one, and a narrower panel beside the thing beats a wide panel on top of it.
	# Re-measured after narrowing, because the body rewraps and the height grows.
	if has_block and Rect2(chosen, Vector2(w, h)).intersects(block):
		var right_gutter: float = canvas.end.x - 12.0 - (block.end.x + pad)
		var left_gutter: float = (block.position.x - pad) - (canvas.position.x + 12.0)
		var use_right: bool = right_gutter >= left_gutter
		var gutter: float = maxf(right_gutter, left_gutter)
		if gutter >= MIN_PANEL_W:
			w = minf(w, gutter)
			_panel.custom_minimum_size = Vector2(w, 0.0)
			h = maxf(_panel.get_combined_minimum_size().y, 104.0)
			_panel.pivot_offset = Vector2(w, h) * 0.5
			var side_y2: float = clampf(block.get_center().y - h * 0.5,
				canvas.position.y + 12.0, canvas.end.y - h - 12.0)
			chosen = Vector2(block.end.x + pad, side_y2) if use_right \
				else Vector2(block.position.x - pad - w, side_y2)
	chosen.x = clampf(chosen.x, canvas.position.x + 12.0,
		canvas.end.x - w - 12.0)
	chosen.y = clampf(chosen.y, canvas.position.y + 12.0,
		canvas.end.y - h - 12.0)
	_panel.position = chosen
	_panel.size = Vector2(w, h)

	if token != _place_token:
		return

	if headless() or reduced():
		_finish_panel_reveal(token)
		return

	# One scene-owned timeline: ink rises as the settled card gives a restrained
	# physical answer, then input and keyboard focus arrive together. No tween
	# ever owns position or size; those remain placement/container geometry.
	_panel.scale = Vector2(0.985, 0.985)
	var tw := _panel.create_tween()
	_panel_reveal_tween = tw
	tw.set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "scale", Vector2(1.018, 1.018), 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_panel, "scale", Vector2.ONE, 0.10) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_finish_panel_reveal.bind(token))


func _finish_panel_reveal(token: int) -> void:
	if token != _place_token or _panel == null or not is_instance_valid(_panel):
		return
	_panel_reveal_tween = null
	_panel.modulate.a = 1.0
	_panel.scale = Vector2.ONE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_meta("_coach_placement_ready", true)
	_panel_ready = true
	if _action != null and is_instance_valid(_action):
		_action.disabled = false
	if _skip != null and is_instance_valid(_skip):
		_skip.disabled = false
	# A read-and-acknowledge panel parks Enter/Space on GOT IT. A board-action
	# step deliberately leaves focus elsewhere so those keys cannot hit SKIP.
	if not headless() and _action != null and is_instance_valid(_action) \
			and _action.visible:
		_action.grab_focus()

## Does this panel rect sit on top of the screen's own worded controls enough to
## matter? A few pixels of a long label is not "buried"; a third of it is.
func _buried_area(rect: Rect2, text_rects: Array[Rect2]) -> float:
	# The COST is the prose actually lost, summed. A few pixels of a long label is
	# not "buried" and must not outvote a real collision elsewhere, so anything
	# under a quarter of a label is forgiven outright.
	var cost := 0.0
	for tr in text_rects:
		if not rect.intersects(tr):
			continue
		var area := tr.get_area()
		if area <= 1.0:
			continue
		var covered := rect.intersection(tr).get_area()
		if (covered / area) > 0.25:
			cost += covered
	return cost


## Every visible worded Control on the screen the coach is attached to.
##
## Walked live rather than cached: the coach is built while the host is still
## laying out, and a rect read at construction is the rect of the animation.
## Skips the coach's own subtree (it would otherwise treat its own panel as
## something to dodge) and any nested CanvasLayer — a modal on its own layer is
## either above us and irrelevant, or it is the pile viewer and the fight is over.
func _host_text_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var host := get_parent()
	if host != null and is_instance_valid(host):
		_collect_text_rects(host, out)
	return out


func _collect_text_rects(n: Node, out: Array[Rect2]) -> void:
	for child in n.get_children():
		if child == self or child is CanvasLayer:
			continue
		if child is Control:
			var c: Control = child
			if c.is_visible_in_tree():
				var t := ""
				if c is Label:
					t = (c as Label).text
				elif c is Button:
					t = (c as Button).text
				elif c is RichTextLabel:
					t = (c as RichTextLabel).get_parsed_text()
				# A sliver is a spacer or an icon's caption box, not prose worth
				# protecting; the floor keeps the walk from producing noise.
				if t.strip_edges() != "" and c.size.x >= 24.0 and c.size.y >= 10.0:
					out.append(visual_rect(c))
		_collect_text_rects(child, out)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 38)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.98, 0.89, 0.67))
	if GameTheme.font_display:
		button.add_theme_font_override("font", GameTheme.font_display)
	# ── FRAMELESS (2026-09-18, owner's call). These were plated on 2026-09-17,
	# and the whole plated-button direction was reversed — the house rule is that
	# the text IS the button (see feedback_ui_aesthetic). It applies here with
	# extra force: the coach panel is 420-820px of PROSE, and a boxed control
	# under a sentence is the loudest thing in a layout whose entire job is to be
	# read.
	#
	# CONTENT MARGINS ARE STILL SET EXPLICITLY, and that has not stopped
	# mattering. A stylebox's margins feed the control's minimum size, so
	# dropping them silently reflows the panel — and this panel is placement-
	# gated by `_probe_coach_a11y`, which would then fail for a reason that has
	# nothing to do with placement logic. The values match what the plaque
	# contributed (1px rest, 2px on the lit states) so nothing moves.
	var coach_rest := StyleBoxEmpty.new()
	coach_rest.set_content_margin_all(1.0)
	var coach_hover := StyleBoxFlat.new()
	coach_hover.bg_color = Color(0.85, 0.62, 0.25, 0.10)
	coach_hover.border_color = Color(1.0, 0.80, 0.34, 0.96)
	coach_hover.border_width_bottom = 2
	coach_hover.set_content_margin_all(2.0)
	var coach_press := coach_hover.duplicate() as StyleBoxFlat
	coach_press.bg_color = Color(0.85, 0.62, 0.25, 0.04)
	coach_press.border_color = Color(0.86, 0.68, 0.30, 0.96)
	button.add_theme_stylebox_override("normal", coach_rest)
	button.add_theme_stylebox_override("hover", coach_hover)
	button.add_theme_stylebox_override("focus", coach_hover)
	button.add_theme_stylebox_override("pressed", coach_press)
	button.mouse_entered.connect(func(): AudioBank.play_ui("hover"))
	return button


# ── The one-call lesson ────────────────────────────────────────────────

## True when `lesson_id` should be taught right now: coaching is on, this profile
## has not been shown it, and the id is real. Every teaching site asks this first,
## so "off" is honoured in ONE place and cannot be forgotten at a new call site.
##
## A KIND_STEP lesson additionally requires COACH_FULL — TIPS ONLY is defined as
## "leave me alone but tell me the rules", and a walkthrough that takes the board
## away from you is not a rule, it is a walkthrough.
static func should_teach(lesson_id: String) -> bool:
	if UserSettings == null or not TutorialDB.has(lesson_id):
		return false
	if UserSettings.coaching_mode == TutorialDB.COACH_OFF:
		return false
	if TutorialDB.kind(lesson_id) == TutorialDB.KIND_STEP \
			and UserSettings.coaching_mode != TutorialDB.COACH_FULL:
		return false
	return not UserSettings.lesson_seen(lesson_id)


## Teach one lesson on any screen and then get out of the way. Returns the coach
## it built, or null if there was nothing to teach.
##
## THIS IS THE WHOLE API THE NON-COMBAT SCREENS USE. Combat has an info channel, a
## round structure and a step machine to hang teaching off; the map, the shop, the
## camp, the reward slate and the event page have none of those, and asking each
## of them to grow one is how five screens end up with five slightly different
## ideas of what a lesson looks like. One call, one panel, one tick:
##
##     TutorialCoach.teach(self, "shop_trade", [_gold_label])
##
## `opts` — `amount` (scrim strength), `body_args` (token substitution, see
## TutorialDB.body), `note`, and `mark` (false to leave the target unringed when
## the spotlight alone is enough).
static func teach(host: Node, lesson_id: String, targets: Array = [],
		opts: Dictionary = {}) -> TutorialCoach:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	if not should_teach(lesson_id):
		return null
	var coach := TutorialCoach.new()
	coach.name = "TutorialCoach"
	host.add_child(coach)

	var live: Array = []
	for t in targets:
		if t is Rect2:
			live.append(t)
		elif t is Control and is_instance_valid(t) and t.is_visible_in_tree():
			live.append(t)
	if not live.is_empty():
		coach.focus(live, float(opts.get("amount", 0.58)))
		if bool(opts.get("mark", true)) and live[0] is Control:
			coach.mark(live[0], {"color": Color(1.0, 0.84, 0.38, 0.95),
				"pad": 22.0, "corner": 10.0, "spread": 20.0, "rim": 2.6})

	coach.show_panel(
		TutorialDB.title(lesson_id),
		TutorialDB.body(lesson_id, opts.get("body_args", {})),
		"GOT IT", 0, 0, {"note": String(opts.get("note", ""))})

	# STAMPED ON SHOW, not on dismissal. A lesson is spent the moment it is put in
	# front of someone — if the screen changes under it, or the player walks away,
	# re-teaching it on the next visit is a worse outcome than missing it once, and
	# the Field Manual has it either way now. (This is also the behaviour the six
	# original tips always had; keeping it means the two paths agree.)
	UserSettings.mark_lesson_seen(lesson_id)

	var close := func() -> void:
		if is_instance_valid(coach):
			coach.dismiss()
			coach.queue_free()
	coach.action_pressed.connect(close)
	coach.skip_pressed.connect(close)
	return coach


# ══ PAINTERS ═══════════════════════════════════════════════════════════

## The breathing rim. Carries the target's rotation and scale so it sits ON the
## card's edge rather than in an axis-aligned box near it.
class GlowMark extends ColorRect:
	## The lamp, in SCREEN space. One direction for every mark on the board, so
	## eight rims lit at once read as eight objects under one light rather than as
	## eight independently-drawn outlines. Up and to the left, the studio default.
	const LIGHT_SCREEN := Vector2(-0.55, -0.84)
	## How many `spread`s of the exponential halo the quad has to hold before the
	## tail is genuinely invisible. exp(-2.8) is 0.06, and the window in the shader
	## takes the rest.
	const HALO_ROOM := 2.8

	var pad: float = 26.0
	var tint: Color = Color(1.0, 0.82, 0.34, 1.0)
	var corner: float = 12.0
	var spread: float = 20.0
	var rim_px: float = 2.4
	var _target: WeakRef = null

	func _init() -> void:
		color = Color.WHITE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = TutorialCoach.GLOW_CODE
		var mat := ShaderMaterial.new()
		mat.shader = sh
		material = mat

	func bind(t: Control) -> void:
		_target = weakref(t)
		sync()

	func begin(delay: float = 0.0) -> void:
		var mat: ShaderMaterial = material
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("corner", corner)
		if TutorialCoach.headless():
			mat.set_shader_parameter("pulse", 0.5)
			return
		if TutorialCoach.reduced():
			# Informational: hold at the bright end of the breath rather than
			# switching the mark off. Nothing is lost but the movement.
			mat.set_shader_parameter("pulse", 0.75)
			return
		mat.set_shader_parameter("pulse", 0.0)
		modulate.a = 0.0
		var intro := create_tween()
		intro.tween_interval(delay)
		intro.tween_property(self, "modulate:a", 1.0, 0.20)
		# NOT wrapped in Motion.time(). That scales with the combat animation
		# speed, and at Instant (3x) this breath would become a strobe — the
		# setting is clash PACING, and a coach mark is not part of the clash.
		var tw := create_tween().set_loops()
		tw.tween_interval(delay)
		tw.tween_property(self, "material:shader_parameter/pulse", 1.0, 0.72) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(self, "material:shader_parameter/pulse", 0.0, 0.86) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	## PAD, SPREAD AND RIM ARE SCREEN PIXELS, divided back out through the
	## target's own scale here.
	##
	## They used to be the mark's LOCAL pixels, which quietly made a mark's
	## weight depend on how big its target happened to be drawn: a hand card sits
	## at scale 0.72, so its "3px" rim rendered at 2.2px and its halo at 0.72 of
	## the reach the slots got. The chosen card — the single most important mark
	## in the walkthrough — came out as the softest, spilling a diffuse wash over
	## the neighbour it overlaps in the fan instead of drawing an outline on
	## itself. Marks now weigh the same wherever they land.
	##
	## AND THE QUAD IS SIZED TO THE HALO, NOT TO THE PAD. `pad` is what the caller
	## asked for as breathing room around the silhouette; the halo's own reach is
	## `spread`, and an exponential still carries a quarter of its weight three
	## spreads out. Sizing the quad to the pad alone CLIPPED the glow — every mark
	## in the game was a soft light ending on a hard rectangle at ~0.25 alpha,
	## which is the loudest programmer-art tell there is. Take whichever is larger:
	## the quad is transparent and ignores the mouse, so the only cost is overdraw.
	func sync() -> void:
		var t = _target.get_ref() if _target != null else null
		if t == null or not is_instance_valid(t):
			return
		var c: Control = t
		var xf := c.get_global_transform()
		var s: float = maxf(xf.get_scale().x, 0.05)
		var lp: float = maxf(pad, spread * HALO_ROOM + rim_px * 1.5) / s
		size = c.size + Vector2(lp, lp) * 2.0
		pivot_offset = Vector2.ZERO
		var rot := xf.get_rotation()
		rotation = rot
		scale = xf.get_scale()
		position = xf * Vector2(-lp, -lp)
		var mat: ShaderMaterial = material
		mat.set_shader_parameter("rect_size", size)
		mat.set_shader_parameter("box", c.size * 0.5)
		mat.set_shader_parameter("spread", spread / s)
		mat.set_shader_parameter("rim", rim_px / s)
		# The rake is a fixed direction ON SCREEN, counter-rotated into the mark's
		# own space — the mark carries the card's rotation, so without this the
		# highlight would ride round the rim as the card tilts in the fan.
		mat.set_shader_parameter("light_dir", LIGHT_SCREEN.rotated(-rot))

	## One bright flare, then back to the breath. Rides `intensity` rather than
	## `scale`, because `sync()` rewrites scale from the target every frame and
	## would eat a scale tween mid-flight.
	func kick() -> void:
		var mat: ShaderMaterial = material
		var tw := create_tween()
		tw.tween_property(mat, "shader_parameter/intensity", 1.85, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "shader_parameter/intensity", 1.0, 0.34) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func dismiss() -> void:
		if TutorialCoach.headless() or TutorialCoach.reduced():
			queue_free()
			return
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.16)
		tw.tween_callback(queue_free)


## The pointing arrow: a bowed, tapered quill stroke with a notched head, drawn
## with a dark under-stroke and a hot spine so it holds its read over parchment,
## over the dark table and over a lit card alike (the same contrast rule the
## combat FX pass settled on).
##
## WHERE IT ENDS IS THE WHOLE DEVICE, and it used to end in the wrong place. The
## tip was planted a flat `gap` outside the target's AXIS-ALIGNED bounding box —
## and a hand card is ROTATED in the fan, so a 162x216 card tilted 8 degrees has
## a 190px-wide box and the arrow stood off ~30px, in the empty wedge beside the
## corner rather than at the art it was naming. It now walks the ray to the
## card's REAL edge (`TutorialCoach.edge_standoff`, through the card's own live
## transform, so rotation and hover scale are both already accounted for) and
## stands off from THERE, by `gap` plus a little of the target's own size —
## because one flat number is crowded on a chip and arbitrary on a card.
##
## AND IT CHECKS IT HAS ROOM. Nothing used to stop the stroke being laid down off
## the canvas: `point_at(x, {"from": "left"})` on anything near the left edge drew
## a 96px arrow starting at a negative x, i.e. an arrowhead floating with nothing
## behind it. The caller's side is still a PREFERENCE and is taken whenever the
## whole stroke fits; `{"from": "auto"}` asks for the roomiest side outright.
class PointerMark extends Control:
	const SIDES := ["left", "right", "up", "down"]

	var side: String = "left"
	var tint: Color = Color(1.0, 0.80, 0.30, 1.0)
	var length: float = 96.0
	var gap: float = 16.0
	var _target: WeakRef = null
	var _tip: Vector2 = Vector2.ZERO
	var _dir: Vector2 = Vector2.RIGHT
	var _nudge: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func bind(t: Control) -> void:
		_target = weakref(t)
		sync()

	func begin() -> void:
		if TutorialCoach.headless():
			return
		if TutorialCoach.reduced():
			modulate.a = 1.0
			return
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.22)
		# The bob runs along the pointing axis — an arrow that nods AT the thing
		# reads as insistence; one that bobs across its own axis reads as drift.
		var tw := create_tween().set_loops()
		tw.tween_method(_set_nudge, 0.0, 1.0, 0.62) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_method(_set_nudge, 1.0, 0.0, 0.72) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	func _set_nudge(v: float) -> void:
		_nudge = v
		queue_redraw()

	## The direction the arrow TRAVELS — from where it is drawn, into the target.
	static func _dir_for(s: String) -> Vector2:
		match s:
			"right":
				return Vector2.LEFT
			"up":
				return Vector2.DOWN
			"down":
				return Vector2.UP
			_:
				return Vector2.RIGHT

	## THE LIVE CANVAS, never a constant — under `canvas_items` stretch, UI Scale
	## 60% lays the UI out on 2667x1500 and a hardcoded 1600x900 would think every
	## right-hand target had run off the screen (class C32).
	func _canvas() -> Rect2:
		if is_inside_tree() and get_viewport() != null:
			return get_viewport_rect()
		return Rect2(Vector2.ZERO, size)

	## Head geometry scales with the stroke. A 26px head on a 104px arrow and the
	## same 26px head on a 60px one is the tell that these numbers were typed once
	## and never looked at.
	func _head_len() -> float:
		return clampf(maxf(length, 44.0) * 0.27, 17.0, 34.0)

	func _head_w() -> float:
		return clampf(maxf(length, 44.0) * 0.155, 9.5, 19.0)

	## How much of the whole stroke lands on the canvas: 1.0 when it fits outright,
	## otherwise the fraction that does, so a side that is merely tight still beats
	## one that is half off the screen.
	##
	## THE PADDING IS THE INK'S, NOT THE HEAD'S DIAGONAL. Growing the spine's box
	## by a full `_head_w() + 6` claims a 21px half-height for a stroke that is 1px
	## at the tail and 16px only at the very head — and the over-claim had a
	## consequence, because a side scoring 0.99 loses outright to one scoring 1.0.
	## Anything sitting in the bottom 26px of the canvas (which is every card in
	## the hand) therefore had the CALLER'S STATED SIDE silently overruled by a 3px
	## phantom overhang. The preference is meant to be a preference.
	func _fit_score(tip: Vector2, d: Vector2, canvas: Rect2) -> float:
		var tail := tip - d * maxf(length, 44.0)
		var box := Rect2(tip, Vector2.ZERO).expand(tail).grow(maxf(_head_w() * 0.62, 6.0))
		var inner := canvas.grow(-8.0)
		if inner.encloses(box):
			return 1.0
		var clip := inner.intersection(box)
		return (clip.size.x * clip.size.y) / maxf(box.size.x * box.size.y, 1.0) * 0.98

	## The sides to try, best first. An explicit `side` leads and the rest are
	## fallbacks; "auto" comes in from whichever face of the target looks at the
	## most canvas, horizontal first — an arrow crossing the reading direction is
	## caught sooner than one coming up off the floor.
	func _side_order(c: Control, canvas: Rect2) -> Array:
		var out: Array = []
		if side != "auto":
			out.append(side if SIDES.has(side) else "left")
		else:
			var ctr := TutorialCoach.visual_rect(c).get_center()
			var mid := canvas.get_center()
			out.append("left" if ctr.x > mid.x else "right")
			out.append("up" if ctr.y > mid.y else "down")
		for s in SIDES:
			if not out.has(s):
				out.append(s)
		return out

	func sync() -> void:
		var t = _target.get_ref() if _target != null else null
		if t == null or not is_instance_valid(t):
			return
		var c: Control = t
		var canvas := _canvas()
		var best_dir := Vector2.RIGHT
		var best_tip := Vector2.ZERO
		var best := -1.0
		for s in _side_order(c, canvas):
			var d := TutorialCoach.PointerMark._dir_for(String(s))
			# The standoff: the target's real edge, then `gap` plus a seventh of a
			# tenth of the target's own extent, capped. Proportional, so the mark
			# breathes the same amount beside a 60px chip and a 220px card.
			var reach := TutorialCoach.visual_rect(c).size.length() * 0.5
			var tip := TutorialCoach.edge_standoff(c, d,
				gap + minf(14.0, reach * 0.07))
			var score := _fit_score(tip, d, canvas)
			if score > best:
				best = score
				best_dir = d
				best_tip = tip
			if score >= 1.0:
				break
		_dir = best_dir
		_tip = best_tip
		queue_redraw()

	func _draw() -> void:
		var run: float = maxf(length, 44.0)
		var dir := _dir
		var perp := Vector2(-dir.y, dir.x)
		# The stroke bows the way a wrist does. Upward on screen where the arrow
		# runs across the page; away from the canvas mid-line where it runs up and
		# down it, so a pair of vertical arrows never curl in on each other.
		if absf(perp.y) > 0.25:
			if perp.y > 0.0:
				perp = -perp
		elif perp.dot(_tip - _canvas().get_center()) < 0.0:
			perp = -perp

		var tip: Vector2 = _tip - dir * (run * 0.075 * _nudge)
		var hl := _head_len()
		var hw := _head_w()
		# THE SHAFT ENDS INSIDE THE HEAD, NOT AT ITS BACK EDGE. `base` used to be
		# the head's back — and the head is notched, so at the centreline (which is
		# exactly where the shaft is) the head does not begin until `notch * hl`
		# further forward. The arrow was therefore drawn with a wedge of empty table
		# between its two pieces, and with the shaft in gold and the head in ember
		# the seam read as two unrelated marks: a yellow dash and an orange chevron.
		# Running the shaft up to the notch vertex closes it for good, at any size.
		var base := tip - dir * (hl * (1.0 - NOTCH * 0.95))
		var tail := tip - dir * run
		var bow := perp * (run * 0.065)
		var head := TutorialCoach.arrow_head(tip, dir, perp, hl, hw, NOTCH)
		var hot := Color(1.0, 0.45, 0.14, tint.a)
		# THE UNDER-STROKE HAS TO BE SEEN TO BE DOING ANYTHING. At 13.4 against a
		# 10.8 body it stood 1.3px proud at 62% alpha, which measured as literally
		# no dark pixels on either side of the stroke — so the arrow's whole claim
		# to survive any ground was resting on a line that was not being drawn. It
		# now carries ~2.5px of near-black on each flank, which is what lets one
		# colour of arrow read over the dark table AND over the ember-lit grass by
		# the commit button, where the old mark simply disappeared.
		var ink := Color(0.05, 0.03, 0.02, 0.82)
		draw_colored_polygon(_stroke(tail, base, bow, 6.6, 17.4), ink)
		draw_colored_polygon(TutorialCoach.grow_poly(head, 3.4), ink)

		# THE BODY IS ONE OBJECT, RAMPED. Per-vertex colour rather than two flat
		# fills: the stroke leaves the tail in the mark's own gold and arrives at
		# the head already ember, so the head is the END of the stroke instead of a
		# second shape sitting on it. The tail also starts at 3.2px, not 1.6 — a
		# stroke that tapers to a hairline has no back end, it just stops being
		# visible, which is why it photographed as a spike rather than a mark.
		var body := _stroke(tail, base, bow, 3.2, 12.6)
		draw_polygon(body, _stroke_ramp(tint, hot))
		draw_colored_polygon(head, hot)
		# THE HOT CORE, down the spine and up into the head. The house contrast rule
		# is that a warm mark on warm parchment over a warm table is camouflage —
		# and the old core was 4.4px at half alpha inside a 10.8px gold stroke, so
		# the shaft measured (255, 204, 76) flat across its whole width with a
		# slightly creamier middle. Nothing in it was white. It is now a real
		# filament: wider, opaque at the front, fading out toward the tail so the
		# stroke still reads as loaded ink rather than as a neon tube.
		var core := _stroke(tail + dir * (run * 0.14), base, bow * 0.72, 1.2, 6.0)
		draw_polygon(core, _stroke_ramp(
			Color(1.0, 0.97, 0.88, 0.06 * tint.a),
			Color(1.0, 0.98, 0.92, 0.95 * tint.a)))
		draw_colored_polygon(TutorialCoach.arrow_head(tip - dir * 2.6, dir, perp,
			hl * 0.58, hw * 0.42, NOTCH), Color(1.0, 0.97, 0.88, 0.92 * tint.a))

	## How deep the back of the head is cut in, as a fraction of its length. Named
	## because `_draw` has to know it too — the shaft is laid up to the notch
	## vertex, and a head whose notch and shaft disagree is the seam this fixes.
	const NOTCH := 0.20
	## Bezier samples per stroke. The colour ramp has to be built from the same
	## count, hence the constant rather than a local.
	const STROKE_STEPS := 12

	## A tapered, slightly bowed quill stroke from `a` to `b`, opening from `w0`
	## to `w1` across it. Built as a real outline off a bezier rather than as a
	## four-point quad: a straight constant-width wedge is exactly the thing that
	## reads as UI chrome instead of as a mark somebody made. The width ramps on an
	## eased curve, so the nib loads gradually rather than in a straight taper.
	func _stroke(a: Vector2, b: Vector2, bow: Vector2, w0: float,
			w1: float) -> PackedVector2Array:
		var ctrl: Vector2 = a.lerp(b, 0.42) + bow
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in STROKE_STEPS + 1:
			var t := float(i) / float(STROKE_STEPS)
			var u := 1.0 - t
			var p: Vector2 = a * (u * u) + ctrl * (2.0 * u * t) + b * (t * t)
			var der: Vector2 = (ctrl - a) * (2.0 * u) + (b - ctrl) * (2.0 * t)
			var n := Vector2(-der.y, der.x)
			n = n.normalized() if n.length() > 0.001 else Vector2.ZERO
			var w: float = lerpf(w0, w1, t * t * (3.0 - 2.0 * t)) * 0.5
			left.append(p + n * w)
			right.append(p - n * w)
		for i in range(right.size() - 1, -1, -1):
			left.append(right[i])
		return left

	## The per-vertex colours matching `_stroke`'s point order — the left bank
	## walked tail-to-head, then the right bank walked back. Eased on the same
	## curve the width uses, so the hue turns where the stroke thickens.
	func _stroke_ramp(c0: Color, c1: Color) -> PackedColorArray:
		var out := PackedColorArray()
		for _side in 2:
			for i in STROKE_STEPS + 1:
				var t := float(i) / float(STROKE_STEPS)
				if _side == 1:
					t = 1.0 - t
				out.append(c0.lerp(c1, t * t * (3.0 - 2.0 * t)))
		return out

	## Kept as the class's own name for the shared centroid-expand — see
	## `TutorialCoach.grow_poly`, which the drag arc's head uses too.
	func _grow(poly: PackedVector2Array, by: float) -> PackedVector2Array:
		return TutorialCoach.grow_poly(poly, by)

	func dismiss() -> void:
		if TutorialCoach.headless() or TutorialCoach.reduced():
			queue_free()
			return
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.16)
		tw.tween_callback(queue_free)


## THE DRAG ARC. Dashes travel from the card toward the slot, thickening as they
## go, with the head planted on the destination — so the arc reads DIRECTIONALLY
## even in a still frame, which matters because half the players who need it are
## looking at a paused screen.
class PathMark extends Control:
	## The travelling dash pattern, in pixels along the arc.
	const DASH := 19.0
	const GAP := 13.0

	var tint: Color = Color(1.0, 0.80, 0.30, 1.0)
	var head_tint: Color = Color(1.0, 0.42, 0.13, 1.0)
	var lift: float = 0.28
	var _from: WeakRef = null
	var _to: WeakRef = null
	var _a: Vector2 = Vector2.ZERO
	var _b: Vector2 = Vector2.ZERO
	var _phase: float = 0.0

	func bind_pair(f: Control, t: Control) -> void:
		_from = weakref(f)
		_to = weakref(t)
		sync()

	func begin() -> void:
		if TutorialCoach.headless():
			return
		if TutorialCoach.reduced():
			modulate.a = 1.0
			return
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.24)

	func _process(delta: float) -> void:
		if TutorialCoach.reduced():
			return
		_phase = fmod(_phase + delta * 46.0, DASH + GAP)
		queue_redraw()

	func sync() -> void:
		var f = _from.get_ref() if _from != null else null
		var t = _to.get_ref() if _to != null else null
		if f == null or t == null or not is_instance_valid(f) \
				or not is_instance_valid(t):
			return
		# THE ARC LEAVES THE CARD'S EDGE, not its middle. Starting at the centre
		# ran the first third of the stroke straight across the card's own
		# painting — over the art, the name cartouche and the rules box of the one
		# card the player is being told to read.
		#
		# ...AND IT IS THE CARD'S REAL EDGE, NOT ITS BOUNDING BOX. This used to walk
		# an AXIS-ALIGNED rect, and a hand card is rotated ~5 degrees in the fan, so
		# its box stands ~15px proud of the paper at the top. Add the 8px standoff
		# and the leading dash gap and the stroke began about 30px above the card,
		# floating in the dark band between the board and the hand, attached to
		# nothing — a gesture that does not touch the thing it is asking you to pick
		# up. `edge_standoff` walks the ray in the card's OWN space (rotation and
		# hover scale included) and lands on the paper.
		#
		# The destination stays a CENTRE, because that is where the card is
		# dropped: the gesture ends where the hand ends.
		_b = TutorialCoach.visual_rect(t).get_center()
		var into: Vector2 = TutorialCoach.visual_rect(f).get_center() - _b
		_a = TutorialCoach.edge_standoff(f, into.normalized(), 3.0) \
			if into.length() > 0.01 else TutorialCoach.visual_rect(f).get_center()
		set_process(not TutorialCoach.reduced() and not TutorialCoach.headless())
		queue_redraw()

	## Quadratic bezier, bowed perpendicular to the run so the arc arrives at the
	## slot from OUTSIDE the straight line — a straight line between two cards
	## looks like a connection, a bow looks like a throw.
	func _point(t: float) -> Vector2:
		var mid := (_a + _b) * 0.5
		var run := _b - _a
		var perp := Vector2(-run.y, run.x).normalized()
		# Always bow away from the board's centre-line, i.e. upward on screen.
		if perp.y > 0.0:
			perp = -perp
		var ctrl := mid + perp * run.length() * lift
		var u := 1.0 - t
		return _a * (u * u) + ctrl * (2.0 * u * t) + _b * (t * t)

	func _draw() -> void:
		if _a == _b:
			return
		var steps := 44
		var pts: Array[Vector2] = []
		for i in steps + 1:
			pts.append(_point(float(i) / float(steps)))
		# DASH + GAP is the modulus `_process` wraps `_phase` on — they are one
		# constant now precisely because they used to be two numbers that had to
		# agree, and the dashes jump on every rollover if they stop agreeing. The
		# gap is the shorter of the pair: the arc's START is wherever the first
		# dash happens to fall, so a long gap leaves the stroke beginning in empty
		# air beside the card for half of every cycle.
		var dash := DASH
		var gap := GAP
		var period := dash + gap
		var travelled := 0.0
		var ink := Color(0.05, 0.03, 0.02, 0.55)
		# A warm scatter under the whole stroke, so the arc separates from the wood
		# without the ink having to get any heavier.
		var scatter := Color(tint.r, tint.g * 0.70, tint.b * 0.40, 0.16 * tint.a)
		for i in steps:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var seg := a.distance_to(b)
			# THE DASHES TRAVEL TOWARD THE SLOT, and SUBTRACTING the phase is what
			# makes them do it. Adding it — which is what this did — marches them
			# the other way, from the ground back to the card: the one device in
			# the coach whose entire job is to teach a DIRECTION was drawing the
			# reverse of the drag it is demonstrating. (`fposmod`, not `fmod`: the
			# subtraction goes negative and `fmod` keeps the sign, which would blank
			# every dash in the first period of the arc.)
			var here := fposmod(travelled - _phase, period)
			travelled += seg
			if here > dash:
				continue
			var t := float(i) / float(steps)
			# The stroke thickens toward the destination: the end of a gesture
			# carries more weight than its start.
			var w: float = 3.4 + 3.6 * t
			draw_line(a, b, scatter, w + 9.0, true)
			draw_line(a, b, ink, w + 3.0, true)
			draw_line(a, b, tint.lerp(Color(1.0, 0.97, 0.88), 0.35 * t), w, true)
			# The hot core again, hottest where the gesture lands.
			draw_line(a, b, Color(1.0, 0.97, 0.90, (0.26 + 0.34 * t) * tint.a),
				maxf(w * 0.36, 1.2), true)
		# The head, planted on the destination and squared to the final tangent —
		# and notched, the same head the pointing arrow wears, so the two devices
		# read as one hand's work.
		var tip: Vector2 = pts[steps]
		var dir: Vector2 = (pts[steps] - pts[steps - 2]).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var hl: float = clampf(_a.distance_to(_b) * 0.075, 20.0, 32.0)
		var hw: float = hl * 0.52
		var head := TutorialCoach.arrow_head(tip, dir, perp, hl, hw)
		draw_colored_polygon(TutorialCoach.grow_poly(head, 3.0), ink)
		draw_colored_polygon(head, head_tint)
		draw_colored_polygon(TutorialCoach.arrow_head(tip - dir * 3.0, dir, perp,
			hl * 0.58, hw * 0.44), Color(1.0, 0.96, 0.86, 0.85 * tint.a))

	func dismiss() -> void:
		set_process(false)
		if TutorialCoach.headless() or TutorialCoach.reduced():
			queue_free()
			return
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.16)
		tw.tween_callback(queue_free)
