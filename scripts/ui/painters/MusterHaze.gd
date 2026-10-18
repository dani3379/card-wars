## MusterHaze — "the hold has not taken the field yet."
##
## Round 1 of a solo fight is the MUSTER: the player sets a line into an enemy
## half that is completely empty, and only when they commit does the hold deal
## its opening formation. Combat's own tutorial copy calls that "the ONE beat of
## a Burning Meadow fight that nothing on screen accounts for", and it is right —
## an empty half of the table looks like *no enemy*, not like *an enemy who has
## not arrived*.
##
## WHAT THIS REPLACED, AND WHY IT WAS NOT A STYLING PROBLEM. The old mark was a
## `PanelContainer` + a rounded `StyleBoxFlat` + a `Label` reading "MUSTER  ?",
## built once per empty enemy front slot — four identical copies of one word.
## Three separate faults, only one of which was ugliness:
##
##  1. IT WAS THE LAST WEB-PAGE CHROME ON THE BOARD. The 2026-09-16 lane-forecast
##     redesign deleted exactly this construction (ring + wire + `Label` on a
##     rounded plate) from combat and replaced it with pressed wax; this survived
##     only because it is a round-1 state and the shot harness that pass built
##     stages a mid-fight board, so nothing ever photographed it.
##  2. IT WAS FOUR MARKS CARRYING ONE BIT. The forecast pass settled the rule —
##     "a mark on everything is a texture". Nothing about the hold's arrival is
##     per-lane: it commits to a SHAPE, blind, over its whole ground.
##  3. IT WAS FACTUALLY WRONG, which is the one that actually decided the
##     rebuild. It marked every empty front lane, i.e. normally all four, while
##     `_deal_opening_muster` seats ONE TO THREE bodies (`open_lane_cap` promises
##     a lane stays clear), and its `siege` formation puts the entire opening in
##     the hold's BACK row — in which case all four pills pointed at ground that
##     stayed empty for the rest of the fight. A telegraph naming lanes it cannot
##     know is the `structure`-charge-badge class of defect: a live affordance
##     that is a lie.
##
## So the mark says the only thing that is true — THEIR GROUND IS CLAIMED, NOT
## EMPTY — and says it once, wordlessly, over the whole run of open ground.
##
## THE PICTURE is a column coming on: a bank of lamplit dust massed at the far
## side of the hold's line, thinning as it rolls toward the clash seam, with
## pikes and standards rising out of it. It IS the "?" — you can see that an army
## is arriving and you cannot see who or how many, which is exactly the
## information state round 1 puts the player in.
##
## CRAFT, and the technique argument rather than the taste one. A flat
## `ColorRect` at 40% alpha has UNIFORM OPACITY across its whole area — the same
## property that made every `Line2D` effect in this game read as "lines cosplaying
## as something cool" (see Motion's beam kit). Stacking more flat rects does not
## fix it; it gives a thicker flat rect. The answer is the one the ring and the
## beam both reached: put the structure INSIDE the primitive.
##   · The dust is `Motion.vfx_noise_material` — three-octave fbm, DOMAIN WARPED
##     (the step that separates noise-that-looks-like-noise from noise that looks
##     like a fluid), gradient-mapped so the dense parts go a different COLOUR
##     rather than a brighter one, with a feathered erosion threshold so its
##     silhouette is ragged from the first frame instead of being a rectangle
##     with weather painted on it.
##   · `rim` frays the LEFT AND RIGHT ends, so the bank does not stop at two
##     vertical cuts; `base_fade` (added to that shader for this caller) softens
##     the seat, so it does not sit on a horizontal one.
##   · `grain_aspect` (added in the same pass, same reason) makes the noise CELLS
##     square. UV knows nothing about the shape of the quad, so the material's
##     form-sized defaults over a 1028x150 band produced cells seven times wider
##     than tall and barely two of them across the run: a domain-warped
##     three-octave fbm that photographed as a flat grey smear. A wide band needs
##     a high `grain` and a low aspect, and the first render is the only thing
##     that says so.
##
## THE DUST SITS AT THEIR FEET, which was the first render's other correction.
## Massing it at the FAR edge and rising the pikes into it is the intuitive
## composition and it is backwards: it buries every tip in the densest part of
## the bank and leaves the shafts' bases hanging in clear air, so the rank read
## as reeds growing out of a fog bar. Dust is kicked up by FEET. It is densest
## along the near edge, the shafts rise out of it, and their heads clear it
## against the bare table — which is also what makes the lit edge earn its place.
##
## THE PIKES DRAW OVER THE DUST, NOT UNDER IT — a column's leading rank is
## NEARER than the dust it kicks up. They carry their own veil instead: a
## per-vertex alpha ramp taking each shaft to nothing at its feet.
##
## AND EVERY PIKE IS LIT ON ONE EDGE, which is not decoration. A dark silhouette
## against the dark war table is invisible — the standing house rule is that
## VALUE IS DECIDED BY THE LOCAL GROUND — and these shafts cross two grounds in
## their own length: lit dust at the base, bare table at the tip. The dark core
## reads against the dust, the warm edge reads against the table, and the pike is
## legible along its whole run.
##
## THE CHILD DRAWS ITSELF. `draw_polygon` and friends are methods of the
## CanvasItem they are called ON, and are only valid inside that item's own draw
## pass — so the pike pass takes its target as an argument (`ci`), the same
## convention MapTerrain's plate functions use. Calling them bare inside a
## signal handler silently addresses `self`, whose draw pass is long over.
extends Control

## Lamplit dust. Deliberately ochre-bone rather than ember: ember is this game's
## THREAT colour (the incoming chip, the intent badges, the enemy rim) and a
## warning-coloured cloud over the hold's whole line would read as a hazard the
## player has to solve this turn. Dust is ground, not fire.
##
## DARK AND THIN, NOT PALE AND THICK. The first render ran this at 0.52 alpha
## over a light gradient-mapped body and came out MILK: the loudest thing on the
## screen, brighter than the cards, with the station marks underneath completely
## erased — the exact inverse of "the quietest instrument on the board". The
## contrast that makes a cloud read as a cloud has to live INSIDE it (crests lit,
## troughs dark) rather than between it and the table.
const DUST_TINT := Color(0.40, 0.29, 0.20, 0.26)
const DUST_LIT := Color(0.98, 0.78, 0.50)

## THE MARK SITS AT A PERMANENT PARTIAL EROSION, and it has to.
##
## `erode` reads as an exit animator and is not one — it is the threshold that
## decides how much of the noise field survives at all, and the shader's standing
## 0.14 baseline is tuned for a small form. Left at rest 0 over a band this size
## the whole `ero` term saturates to 1 everywhere: uniform alpha, no internal
## structure, and a rectangle with two dead straight edges on it. Measured on the
## second render — a cloud with beautiful mottling inside a perfect box.
##
## At 0.42 the top of the bank genuinely breaks up into the table while the seat
## stays dense, which is the whole silhouette. `settle` falls TO this value and
## `dissolve` rises FROM it.
const REST_ERODE := 0.42

const PIKE_DARK := Color(0.055, 0.040, 0.030)
const PIKE_LIT := Color(1.0, 0.70, 0.36)
## Cloth, not a hole. The first standard was drawn in the shaft's near-black and
## photographed as a rectangular void — the one shape on the board that looked
## like a missing texture. Colour is what makes it read as a thing.
const CLOTH := Color(0.31, 0.10, 0.08)
const CLOTH_LIT := Color(0.66, 0.24, 0.13)

## One pike per this many px of run. At the full four-lane width that is a real
## column (~50 shafts); over a single lane it is still a rank rather than three
## sticks. Jittered HARD against this pitch — at ±7px the rank photographed as a
## comb, and evenly spaced verticals is the one thing an army never is.
const PIKE_PITCH := 20.0
const PIKE_JITTER := 11.0

## Where the shafts are planted, as a fraction of the band height: down in the
## thick of the dust, so the shafts come out of it rather than stand beside it.
const PIKE_BASE_Y := 0.84

var seed_val: int = 0

var _dust: ColorRect = null
var _dust_mat: ShaderMaterial = null
var _pikes_node: Control = null
var _pikes: Array = []
var _mass: Array = []
var _baked_for := Vector2.ZERO
var _drift := 0.0
var _phase := 0.0
var _dying := false
var _tw: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

	# warp 1.05 — dust IS a fluid, so the domain warp is on. `bite` is high (0.86)
	# because all of this cloud's contrast is internal now; `grain` and
	# `grain_aspect` are set from the band's own rect in `_layout_children`, since
	# a value that reads as billows over four lanes is mush over one.
	_dust_mat = Motion.vfx_noise_material(
		float(seed_val) * 0.37, 0.22, 11.0, 0.86, 1.05, 0.55, DUST_LIT, 0.85)
	_dust_mat.set_shader_parameter("base_fade", 0.14)
	_set_erode(REST_ERODE)

	_dust = ColorRect.new()
	_dust.name = "Dust"
	_dust.color = DUST_TINT
	_dust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dust.material = _dust_mat
	add_child(_dust)

	_pikes_node = Control.new()
	_pikes_node.name = "Pikes"
	_pikes_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pikes_node.draw.connect(_draw_pikes.bind(_pikes_node))
	add_child(_pikes_node)

	_layout_children()
	resized.connect(_layout_children)

	var still: bool = _reduced() or DisplayServer.get_name() == "headless"
	set_process(not still)
	if still:
		# Reduce Motion HOLDS an informational overlay, it does not delete it —
		# the state still has to be on screen, just not moving.
		_drift = 0.6
		_apply_drift()


## THE NOISE SCALE IS DERIVED FROM THE RECT, not fixed. `grain` is in UV, so a
## constant means the cells stretch with the quad — a run of four lanes and a run
## of one would get wildly different weather out of the same numbers. Solving for
## a target cell size in PIXELS keeps the billows the same physical size however
## the hold's ground happens to be broken up.
const DUST_CELL_PX := 96.0

func _layout_children() -> void:
	if _dust == null or not is_instance_valid(_dust):
		return
	_dust.size = size
	_dust.position = Vector2.ZERO
	if _dust_mat != null and size.x > 1.0 and size.y > 1.0:
		var gx: float = maxf(2.5, size.x / DUST_CELL_PX)
		_dust_mat.set_shader_parameter("grain", gx)
		# aspect = (grain_y / grain_x), chosen so a cell is as tall as it is wide.
		_dust_mat.set_shader_parameter("grain_aspect",
			clampf((size.y / DUST_CELL_PX) / gx, 0.06, 1.4))
	if _pikes_node != null and is_instance_valid(_pikes_node):
		_pikes_node.size = size
		_pikes_node.position = Vector2.ZERO
		_pikes_node.queue_redraw()


func _process(delta: float) -> void:
	if _dying:
		return
	# Two independent rates, because one is not enough to stop a noise field
	# reading as a looping texture: `seed` walks the field sideways (the column
	# crossing the ground) and `t` churns it in place (the cloud turning over).
	_drift += delta * 0.045
	_phase += delta
	_apply_drift()
	if _pikes_node != null and is_instance_valid(_pikes_node):
		_pikes_node.queue_redraw()


func _apply_drift() -> void:
	if _dust_mat == null:
		return
	_dust_mat.set_shader_parameter("seed", float(seed_val) * 0.37 + _drift)
	_dust_mat.set_shader_parameter("t", _drift * 2.2)


func _reduced() -> bool:
	return UserSettings != null and UserSettings.reduce_motion


# ── the column ─────────────────────────────────────────────────────────────

func _bake() -> void:
	_pikes.clear()
	_mass.clear()
	_baked_for = size
	if size.x < 24.0 or size.y < 24.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_val) * 7919 + 17
	var count: int = maxi(6, int(size.x / PIKE_PITCH))
	var step: float = size.x / float(count)
	# Standards are placed by FRACTION of the run, not by index, so the count
	# scales with the ground rather than with an arbitrary index.
	#
	# ONE PER BAND UNLESS THE BAND IS WIDE. The mark became per-SLOT once it
	# started showing where the hold will actually stand, and two banners inside a
	# single 204px station reads as repetition rather than as an army — a company
	# carries one set of colours. The second only appears on a run long enough to
	# be more than one company.
	var banners := {int(float(count) * 0.28): true}
	if count >= 16:
		banners[int(float(count) * 0.71)] = true
	for i in range(count):
		# `dim` is the whole depth cue: a shorter, thinner, fainter shaft reads as
		# one further back in the column. Without it the rank is a comb.
		var dim: float = rng.randf_range(0.52, 1.0)
		var banner: bool = banners.has(i) and dim > 0.72
		_pikes.append({
			"x": step * (float(i) + 0.5) + rng.randf_range(-PIKE_JITTER, PIKE_JITTER),
			# FEET ARE NOT ON ONE LINE. Every shaft planted at the same y put a
			# dead straight horizontal cut across the bottom of the whole rank —
			# fifty weapons ending at once, which no ground and no formation does.
			# It is the same defect as the band's own square edges, one scale down.
			"fy": rng.randf_range(-9.0, 9.0),
			"h": size.y * rng.randf_range(0.24, 0.70) * (1.18 if banner else 1.0),
			# ±0.16 rad, which is a LOT more scatter than it sounds and is the
			# single strongest "army" cue in the mark. Pikes held at one angle is
			# a parade; pikes held at every angle is men walking.
			"lean": rng.randf_range(-0.16, 0.16),
			"dim": dim,
			"banner": banner,
			"bob": rng.randf_range(0.0, TAU),
			"rate": rng.randf_range(0.5, 0.9),
		})
	# The mass under them. Roughly one hump per two shafts, sized and seated so
	# the row overlaps itself into a continuous ragged silhouette rather than a
	# line of separate lumps.
	var lumps: int = maxi(5, int(float(count) / 1.6))
	for i in range(lumps):
		_mass.append({
			"x": (size.x / float(lumps)) * (float(i) + 0.5)
				+ rng.randf_range(-16.0, 16.0),
			"y": rng.randf_range(-6.0, 15.0),
			"r": rng.randf_range(18.0, 38.0),
			# 0.20-0.40 measured as a 0.05 luminance drop on a 0.22 ground — the
			# same "it is technically drawn" invisibility the shafts had. A
			# silhouette that cannot be distinguished from its ground is not a
			# subtle silhouette, it is an absent one.
			"a": rng.randf_range(0.38, 0.70),
		})


func _draw_pikes(ci: CanvasItem) -> void:
	if _pikes.is_empty() or _baked_for != size:
		_bake()
	var base_y: float = size.y * PIKE_BASE_Y
	_draw_mass(ci, base_y)
	for p in _pikes:
		_draw_one_pike(ci, p, base_y)


## THE MASS AT THEIR FEET, and it is the difference between an army and a fence.
## Shafts rising out of weather is a picket line in fog no matter how well the
## weather is drawn; what says ARMY is that something dark and irregular is
## moving underneath them. Soft dark humps — shoulders and helmets at the very
## limit of resolution — drawn UNDER the shafts and barely darker than the dust,
## so they register as OCCLUSION rather than as objects the player might try to
## count or target.
##
## `glow_tex` rather than a polygon: a hard-edged lump reads as a lump. The
## texture is white with the falloff in alpha, so a dark modulate multiplies
## through it cleanly — the same property `draw_glow` relies on, minus its
## white-hot core pass, which would be exactly wrong for a shadow.
func _draw_mass(ci: CanvasItem, base_y: float) -> void:
	var tex := Motion.glow_tex(1.4)
	for m in _mass:
		var r: float = float(m["r"])
		var c := Vector2(float(m["x"]), base_y - float(m["y"]))
		ci.draw_texture_rect(tex,
			Rect2(c - Vector2(r, r * 0.66), Vector2(r * 2.0, r * 1.32)),
			false, Color(0.085, 0.058, 0.045, float(m["a"])))


func _draw_one_pike(ci: CanvasItem, p: Dictionary, base_y: float) -> void:
	var dim: float = float(p["dim"])
	# A marching column is never perfectly still. Tiny — 1.5px at full depth —
	# because the eye reads any larger sway as wind, and this is men walking.
	var bob: float = sin(_phase * float(p["rate"]) + float(p["bob"])) * 1.5 * dim
	var h: float = float(p["h"])
	var foot := Vector2(float(p["x"]), base_y + float(p["fy"]) + bob * 0.3)
	var tip := foot + Vector2(sin(float(p["lean"])) * h, -h + bob)

	var dir := (tip - foot).normalized()
	var perp := Vector2(-dir.y, dir.x)
	# 6.8px at the butt on a full-depth shaft. The first render ran 4px and the
	# rank photographed as WHISKERS — at a 45-90px length a shaft needs enough
	# body to read as a held weapon, and thin does not mean far away, dim does.
	var wb: float = 3.4 * dim
	var wt: float = 1.5 * dim
	# THE VEIL IS THE LAST QUARTER, NOT THE WHOLE RUN. Ramping alpha from zero at
	# the feet all the way to the head sounds like "it fades into the dust" and
	# measures as "it is not there": a scanline across mid-shaft came back 0.16
	# against a 0.22 ground, i.e. an effective alpha of 0.34 on a 2px stroke —
	# six hundredths of luminance, which is nothing. A veil has to be SHORT to be
	# a veil; over a long ramp it is just transparency.
	var a_foot: float = 0.40 * dim
	var a_tip: float = 0.95 * dim

	# THE SHAFT, with its veil built in. `draw_polygon` takes PER-VERTEX colours,
	# which is what lets one polygon carry the whole gradient from veiled at the
	# feet to solid at the head — a second, shorter polygon stacked underneath
	# would put a visible terminator across every shaft in the rank.
	ci.draw_polygon(
		PackedVector2Array([foot - perp * wb, foot + perp * wb,
			tip + perp * wt, tip - perp * wt]),
		PackedColorArray([_a(PIKE_DARK, a_foot), _a(PIKE_DARK, a_foot),
			_a(PIKE_DARK, a_tip), _a(PIKE_DARK, a_tip)]))

	# THE LIT EDGE — the lamp on this board comes from the upper left, so the
	# catch is on the shaft's left side.
	#
	# IT IS A FRACTION OF THE LOCAL WIDTH, NEVER A WIDTH IN PIXELS, and getting
	# that wrong reproduced a defect this codebase had already paid for once. A
	# constant 0.9px floor is a sliver at the butt, which is several px across, and
	# is the WHOLE SHAFT at the head, which is barely one — so the top half of
	# every pike was painted in the highlight colour and the rank photographed as
	# PALE REEDS with dark barbs on them — the exact inversion of a dark weapon
	# standing in lit dust.
	# The forecast brackets learned the same thing in the same words: a highlight
	# on a thin stroke is a sliver or it IS the stroke.
	const LIT_FRAC := 0.42
	ci.draw_polygon(
		PackedVector2Array([foot - perp * wb, foot - perp * (wb * (1.0 - LIT_FRAC)),
			tip - perp * (wt * (1.0 - LIT_FRAC)), tip - perp * wt]),
		PackedColorArray([_a(PIKE_LIT, 0.0), _a(PIKE_LIT, 0.0),
			_a(PIKE_LIT, 0.34 * dim), _a(PIKE_LIT, 0.34 * dim)]))

	if bool(p["banner"]):
		_draw_standard(ci, tip, dir, perp, dim)
	else:
		_draw_head(ci, tip, dir, perp, dim, a_tip)


## A leaf-shaped head. This is the whole reason the rank reads as PIKES and not
## as a picket fence, and it is four points.
func _draw_head(ci: CanvasItem, tip: Vector2, dir: Vector2, perp: Vector2,
		dim: float, a_tip: float) -> void:
	var len_h: float = 13.0 * dim
	var half: float = 3.4 * dim
	var neck := tip - dir * (len_h * 0.34)
	var point := tip + dir * (len_h * 0.66)
	var c := _a(PIKE_DARK, a_tip)
	ci.draw_polygon(
		PackedVector2Array([neck, neck + perp * half, point, neck - perp * half]),
		PackedColorArray([c, c, c, c]))
	# One catch of light down the head's lit side, so a spearpoint still reads
	# where the dust has thinned out from under it. HELD WELL DOWN: at 0.62 the
	# blade out-read its own shaft and the rank photographed as a row of little
	# pale pennants — the highlight has to stay a property of the steel, not
	# become the shape.
	ci.draw_line(neck - perp * half * 0.55, point,
		_a(PIKE_LIT, 0.40 * dim), maxf(1.0, 0.9 * dim), true)


## A standard: cloth hung off the near side of a taller pole, with one wave in
## it. Two of them in the column is what turns a rank of pikes into an ARMY —
## somebody in there is carrying colours.
func _draw_standard(ci: CanvasItem, tip: Vector2, dir: Vector2, perp: Vector2,
		dim: float) -> void:
	var drop: float = 23.0 * dim
	var reach: float = 32.0 * dim
	var top := tip + dir * 1.5
	var steps := 5
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	# Top edge, hoist -> fly.
	for i in range(steps + 1):
		var u: float = float(i) / float(steps)
		pts.append(_cloth_pt(top, dir, perp, u, 0.0, reach, drop, dim))
		cols.append(_cloth_col(u, 0.0, dim))
	# THE SWALLOWTAIL, and it is one vertex. A rectangle of cloth is a flag over
	# a municipal building; the notch is what makes it a war banner.
	pts.append(_cloth_pt(top, dir, perp, 0.78, 0.52, reach, drop, dim))
	cols.append(_cloth_col(0.78, 0.52, dim))
	# Bottom edge, fly -> hoist.
	for i in range(steps, -1, -1):
		var u: float = float(i) / float(steps)
		pts.append(_cloth_pt(top, dir, perp, u, 1.0, reach, drop, dim))
		cols.append(_cloth_col(u, 1.0, dim))
	ci.draw_polygon(pts, cols)
	# The head edge catches the lamp like the shafts do. Drawn along the SAMPLED
	# top edge rather than as one straight line, or the highlight ignores the
	# wave underneath it and the cloth stops reading as cloth.
	var lit := PackedVector2Array()
	for i in range(steps + 1):
		lit.append(_cloth_pt(top, dir, perp, float(i) / float(steps), 0.0,
			reach, drop, dim))
	ci.draw_polyline(lit, _a(PIKE_LIT, 0.42 * dim), maxf(1.0, 1.1 * dim), true)


## `v` 0 is the head edge, 1 the foot edge; `u` runs hoist (0) to fly (1). The
## wave is scaled by `u` so the hoist stays pinned to its rings — cloth does not
## flap where it is tied, and letting it do so is what makes a banner look like a
## floating quad.
func _cloth_pt(top: Vector2, dir: Vector2, perp: Vector2, u: float, v: float,
		reach: float, drop: float, dim: float) -> Vector2:
	var sag: float = drop * (1.0 - 0.16 * u)
	var wave: float = sin(u * 3.4 + _phase * 1.1) * 2.4 * dim * u
	return top + perp * (reach * u) - dir * (sag * v) + dir * wave


func _cloth_col(u: float, v: float, dim: float) -> Color:
	# Lit toward the fly and along the head edge, in shadow in the fold beneath —
	# that gradient IS the three-dimensionality. Flat cloth is a sticker.
	var t: float = clampf((0.28 + 0.56 * u) * (1.0 - 0.48 * v), 0.0, 1.0)
	var c := CLOTH.lerp(CLOTH_LIT, t)
	return Color(c.r, c.g, c.b, 0.90 * dim)


func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)


## Mirrored on the instance as well as pushed to the shader. `get_shader_parameter`
## would do, but the value has to be readable when a `dissolve` INTERRUPTS a
## `settle` — starting the dispersal from the constant rather than from wherever
## the arrival had got to snaps the bank solid for one frame on a player who ends
## the muster round quickly, which is the commonest way this will ever be seen.
var _erode_now := 0.0

func _set_erode(v: float) -> void:
	_erode_now = v
	if _dust_mat != null:
		_dust_mat.set_shader_parameter("erode", v)


# ── arrival and departure ──────────────────────────────────────────────────

## The bank rises. Decorative — Reduce Motion gets the settled state on frame one
## rather than a shortened version of the same travel.
func settle() -> void:
	if _dust_mat == null or _reduced() or DisplayServer.get_name() == "headless":
		return
	_set_erode(1.15)
	modulate.a = 0.0
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.set_parallel(true)
	# Bound to a local first. A multi-line lambda written inline in an argument
	# list parses unreliably in GDScript — the chaos-save harness lost a whole
	# run to exactly that, and the failure is a silent wrong answer, not an error.
	var ero := _set_erode
	_tw.tween_method(ero, 1.15, REST_ERODE, 0.95).set_trans(Tween.TRANS_SINE)
	_tw.tween_property(self, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)


## The hold takes the field: the bank lifts and the line walks out of it.
##
## The exit is EROSION, not a fade. The two are not the same picture and the
## difference is the whole argument of the ring rebuild — a cloud that fades is a
## cloud someone turned the opacity down on, while a cloud eaten inward from its
## own ragged edge is a cloud dispersing. The alpha tween rides along at a
## shorter duration purely to guarantee the node leaves.
func dissolve() -> void:
	if _dying:
		return
	_dying = true
	set_process(false)
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if not is_inside_tree() or _dust_mat == null \
			or DisplayServer.get_name() == "headless":
		queue_free()
		return
	var quick: bool = _reduced()
	_tw = create_tween()
	_tw.set_parallel(true)
	var ero := _set_erode
	_tw.tween_method(ero, _erode_now, 1.35, 0.30 if quick else 0.70) \
		.set_trans(Tween.TRANS_SINE)
	_tw.tween_property(self, "modulate:a", 0.0, 0.28 if quick else 0.62) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if not quick:
		# It lifts as it goes — dust rises. The informational content has already
		# landed by here (the line is arriving), so the travel is decorative and
		# Reduce Motion simply skips it.
		_tw.tween_property(self, "position:y", position.y - 22.0, 0.70) \
			.set_trans(Tween.TRANS_SINE)
	_tw.chain().tween_callback(queue_free)
