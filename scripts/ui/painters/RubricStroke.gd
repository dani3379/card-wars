extends Node2D
## THE RUBRIC — the mark a chronicler makes when a line of the record is struck out.
##
## Replaces `_play_pierce_lance`, which was a 2-point Line2D of constant width 5
## and constant alpha. Three things were wrong with it and only one was polish:
##
##   1. CONSTANT WIDTH IS A TOOL MARK, NOT A PHENOMENON. Nothing physical has
##      uniform width along its length, so the brain files it under *annotation*
##      rather than under *event*.
##   2. A STRAIGHT LINE BETWEEN TWO OBJECTS IS THE UNIVERSAL CONVENTION FOR
##      RELATION (UML, node graphs, tethers) — not for force. Drawn perfectly it
##      would still have said "A is associated with B".
##   3. IT STARTED AT THE WRONG END. Overkill's fiction is force exiting the
##      VICTIM's back. An attacker-origin line is a *reach*; a victim-origin one
##      is a *consequence*, which is the rule actually being narrated.
##
## Straightness itself is kept, and deliberately: a straight line reads as a
## RELATION when it connects two endpoints and stops at both, but a stroke that
## runs THROUGH a body and out past it is a path, and straightness is correct for
## a path. What was wrong was everything else.
##
## MATERIAL — three bands carrying both extremes of the value range at once, so
## the mark reads on dark wood AND on light parchment. A cream core alone is
## lower-contrast than parchment; an ink line alone vanishes on the table. Gilt
## leaf inside an ink keyline is literally how an illuminated page is built, and
## WritLeaf already draws its edge toast and ink contour along one path for the
## same reason.
##
##      ░▓█████▓░   iron-gall knockout   (the bite)
##       ▓█████▓    vermilion body       (the ink)
##        █████     ivory core           (still wet)
##
## THE GUTTER RULE (the reason `gutter_spans` exists). The stroke crosses three
## substrates: token art, the 16 px lane gutter of bare dark wood, then token art
## again. As the ink dries the mark's contrast CARRIER flips from bright (ivory
## core) to dark (wicked shoulders) — and a dark carrier is exactly what vanishes
## on dark wood. The segment that would go invisible is therefore the gutter
## segment, which is the only part of the stroke that means "it CARRIED"; the
## on-token segments only ever mean "this card was struck". So the core narrows
## over the tokens and HOLDS across the gutter. That is also the more honest
## physics: ink wicks into fibre and has nothing to wick into over a gap, so a
## stroke crossing a void genuinely does stay wet longer.

# Geometry, in local space.
var from_pt: Vector2 = Vector2.ZERO
var to_pt: Vector2 = Vector2.ZERO

# 0 → the nib has not landed; 1 → the whole stroke is laid down.
var progress: float = 0.0: set = _set_progress
# 0 → wet (fat ivory core); 1 → dried (core down to a thread over absorbent
# ground, shoulders darkened and wicked outward).
var dry: float = 0.0: set = _set_dry

# Normalised [start, end] spans along the stroke that cross bare table. The core
# refuses to narrow inside these — see THE GUTTER RULE above.
var gutter_spans: Array = []

# PIERCING mode: the stroke widens across the second body instead of tapering to
# a heel, and the last stretch goes dry and splits into two hairlines — a stroke
# that outran its own ink, which is precisely the mechanic.
var pierce: bool = false

# Widths are tuned against a 200x150 battlefield token. At the original 11 px the
# mark read as a hairline scratch running the LONG way down a 156 px column —
# more icicle than authority. A rubric is a mark someone made ON PURPOSE, so it
# has to own roughly a tenth of the token's width before it reads as deliberate.
const BODY_W := 19.0
# The core is a WET SHEEN on ink, not a light source inside it. At 5.5 with a pure
# ivory fill it read as a lit filament running down a candle; the eye saw the core
# as the object and the vermilion as its holder. Narrower, and warmed on contact
# with the ink (see _draw), puts the ink back in charge.
const CORE_W := 4.2
const KNOCKOUT_PAD := 2.4
# NEVER let the dried core reach 1 px. The canvas is 1600x900 with canvas_items
# stretch, so on a 1366x768 panel it scales by 0.853 and a 1 px line lands at
# 0.85 PHYSICAL px — with LINEAR filtering that resolves to a half-alpha smear
# across two pixels. It would not narrow, it would DISSOLVE, and it would do so
# only late in the beat where no shot harness ever catches it. 2.6 keeps ~2.2
# physical px at the worst common resolution while still reading as a 50%
# narrowing against the wet width.
const CORE_DRY_W := 2.6      # over absorbent ground
const CORE_GUTTER_W := 3.4   # the floor across bare table
const SAMPLES := 44

const COL_KNOCKOUT := Color(0.09, 0.05, 0.03, 0.75)
const COL_BODY := Color(0.77, 0.25, 0.16)
const COL_CORE := Color(0.99, 0.97, 0.90)

var _p1: float = 0.0
var _p2: float = 0.0
var _wob: float = 1.5
var _lean: float = 0.0
var _alpha: Array = []


func _set_progress(v: float) -> void:
	progress = clampf(v, 0.0, 1.0)
	queue_redraw()


func _set_dry(v: float) -> void:
	dry = clampf(v, 0.0, 1.0)
	queue_redraw()


## `seed_val` should be stable for one strike (attacker + victim + round) so the
## same blow always draws the same hand, and two blows never draw the same one.
func configure(a: Vector2, b: Vector2, seed_val: int, is_pierce: bool = false) -> void:
	from_pt = a
	to_pt = b
	pierce = is_pierce
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	_p1 = rng.randf_range(0.0, TAU)
	_p2 = rng.randf_range(0.0, TAU)
	_wob = rng.randf_range(2.2, 3.4)
	# A hand does not draw axis-aligned. Both board columns are dead vertical,
	# so without a seeded LEAN every mark came out perfectly plumb and read as
	# an engine primitive no matter how well the ink was painted. ~5 px over the
	# length is about four degrees: enough to be made by somebody.
	_lean = rng.randf_range(-1.0, 1.0) * 5.5
	# Per-segment alpha jitter — WritLeaf's own recipe for uneven ink bite. A
	# perfectly even line is the tool mark this painter exists to get rid of.
	# Range deliberately TIGHT. At 0.70-1.30 the per-segment variation banded into
	# hard horizontal stripes and the mark read as a strip of something rather than
	# as ink — the jitter has to be grain you feel, not rungs you count.
	_alpha.clear()
	for i in SAMPLES + 1:
		_alpha.append(0.88 + rng.randf() * 0.16)
	queue_redraw()


func _in_gutter(t: float) -> bool:
	for span in gutter_spans:
		if t >= float(span.x) and t <= float(span.y):
			return true
	return false


## Half-width of the ink body at normalised position `t`.
func _body_half(t: float) -> float:
	if pierce:
		# Pressure INVERTS: the pen bears down as it crosses the second body, so
		# the mark is at its heaviest where it leaves the board. The spread has to
		# be unmistakable — at a gentler ramp the widening was swamped by the
		# wobble and the stroke read as tapering, i.e. as exactly the opposite
		# rule. Ends ~1.7x the body it started at.
		return BODY_W * (0.55 + 1.15 * t) * 0.5
	# A nib laid down, dragged, and LIFTED: a fast swell, a long body, and a
	# blunt squared heel that is slightly heavier than the run. It ENDS — that
	# terminal weight is the difference between "it stopped" and "it continued",
	# and continuation is Piercing's word, not Overkill's.
	if t < 0.10:
		return BODY_W * (0.45 + 5.5 * t) * 0.5
	if t > 0.90:
		return BODY_W * (1.0 + 0.30 * (t - 0.90) / 0.10) * 0.5
	return BODY_W * 0.5


## Half-width of the wet ivory core at `t`.
func _core_half(t: float) -> float:
	var wet := CORE_W
	var dried: float = CORE_GUTTER_W if _in_gutter(t) else CORE_DRY_W
	var w: float = lerpf(wet, dried, dry)
	if pierce and t > 0.85:
		# Going dry at the far end; the split itself is drawn separately.
		w *= 1.0 - (t - 0.85) / 0.15 * 0.75
	return maxf(w, 0.0) * 0.5


func _centerline(t_max: float) -> Array:
	var out: Array = []
	var d := to_pt - from_pt
	var L := d.length()
	if L < 0.5:
		return out
	var dir := d / L
	var nrm := Vector2(-dir.y, dir.x)
	var n := maxi(2, int(ceil(SAMPLES * t_max)))
	for i in n + 1:
		var t: float = (float(i) / float(n)) * t_max
		# LOW-FREQUENCY wobble — one and a bit periods over the whole length, so
		# it reads as a hand that isn't a ruler. Per-vertex noise would read as
		# aliasing instead, which is the opposite of the intent.
		var swing: float = 0.62 * sin(t * PI * 1.3 + _p1) + 0.38 * sin(t * PI * 2.1 + _p2)
		var w: float = _lean * (t - 0.5) * 2.0 + _wob * swing
		out.append({"t": t, "p": from_pt + dir * (L * t) + nrm * w, "n": nrm})
	return out


func _ribbon(line: Array, half_fn: Callable, pad: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for s in line:
		var h: float = float(half_fn.call(float(s["t"]))) + pad
		if h <= 0.0:
			continue
		var nrm: Vector2 = s["n"]
		var p: Vector2 = s["p"]
		left.append(p + nrm * h)
		right.append(p - nrm * h)
	var poly := PackedVector2Array()
	poly.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly


func _draw() -> void:
	if progress <= 0.001:
		return
	var line := _centerline(progress)
	if line.size() < 2:
		return
	# Knockout first (widest), then the ink, then the wet core on top. Shoulders
	# darken and wick ~1 px outward as the stroke dries.
	var wick: float = KNOCKOUT_PAD + dry * 1.0
	var ko := COL_KNOCKOUT
	ko.a = COL_KNOCKOUT.a * (0.80 + 0.20 * dry)
	draw_colored_polygon(_ribbon(line, _body_half, wick), ko)

	# The ink body, drawn in short segments so the seeded alpha jitter shows as
	# uneven bite rather than as one flat ribbon.
	for i in range(line.size() - 1):
		var seg := [line[i], line[i + 1]]
		var a_idx: int = mini(i, _alpha.size() - 1)
		var c := COL_BODY
		c.a = clampf(float(_alpha[a_idx]) * 0.92, 0.0, 1.0)
		draw_colored_polygon(_ribbon(seg, _body_half, 0.0), c)

	var core_poly := _ribbon(line, _core_half, 0.0)
	if core_poly.size() >= 3:
		# Warmed toward the ink even when fully wet — a sheen ON vermilion picks up
		# vermilion. Pure ivory made the core read as a separate lit object sitting
		# in a red channel rather than as the wet part of one mark.
		var cc := COL_CORE.lerp(Color(0.97, 0.80, 0.58), 0.34)
		# It keeps warming as it dries: ink is not a light going out, it is a wet
		# film losing its sheen.
		cc = cc.lerp(Color(0.93, 0.66, 0.40), dry * 0.6)
		draw_colored_polygon(core_poly, cc)

	if pierce and progress > 0.85:
		_draw_dry_split(line)


func _draw_dry_split(line: Array) -> void:
	# The last stretch of a piercing stroke has outrun its ink: the core fails and
	# the nib's two tines each leave their own hairline with fibre showing between.
	var tines := PackedVector2Array()
	var tines2 := PackedVector2Array()
	for s in line:
		var t: float = float(s["t"])
		if t < 0.85:
			continue
		var nrm: Vector2 = s["n"]
		var p: Vector2 = s["p"]
		var off: float = 1.6 + (t - 0.85) / 0.15 * 2.2
		tines.append(p + nrm * off)
		tines2.append(p - nrm * off)
	if tines.size() >= 2:
		var c := COL_BODY.lerp(COL_CORE, 0.35)
		c.a = 0.85
		draw_polyline(tines, c, 1.6)
		draw_polyline(tines2, c, 1.6)
