class_name Motion
extends RefCounted
## The shared animation clock and FX vocabulary
## (R1/R5/R6 of docs/ANIMATION_AUDIT_20260716.md).
##
## One home for the combat beat constants that BOTH sides of a clash read:
## Combat's pacing awaits (`_short_pause(LUNGE_APEX)`) and Card2D's lunge /
## recoil tweens used to keep separate copies of these numbers in separate
## files — retuning one silently desynced the other. Combat's same-name
## constants now alias these, and Card2D builds its tween durations from them
## through `Motion.time()`, so the conductor and the orchestra share a clock
## at every animation-speed setting (Instant included).
##
## `time(base)` is the tween-side twin of Combat._short_pause's scaling: it
## divides by UserSettings.anim_speed so a tween shortens exactly in step
## with the pacing pause that waits on it. Wrap a duration in it when the
## tween is part of combat flow (lunges, recoils, hit flashes, death
## flourishes). Shell/kit animations (deal_in etc.) stay unscaled
## by policy — the setting is COMBAT pacing, not a global fast-forward.
##
## Since R5/R6 this file also owns the two FX primitives (`burst`, the
## one-shot CPUParticles2D factory; `ring`, the one expanding-ring engine)
## and the shared motion-kit verbs, extracted from GameTheme behind
## same-name delegators — shell call sites still say `GameTheme.deal_in(...)`
## and keep working; new motion code belongs here. The stateful pieces
## (trauma screen shake, the ink-wipe scene transition) stay on GameTheme:
## they need an autoload Node (_process / cached shader), not a static.

# ── Combat beat clock ──────────────────────────────────────────────────
# The clash grammar, in seconds at speed 1.0. LUNGE_APEX is DERIVED from the
# tween's own phases — the impact beat lands exactly at full extension, by
# construction. (Before 2026-07-16 it was an independent 0.09 that only
# "landed near" the tween's 0.13 apex.)
#
# 2026-07-28 LEGIBILITY PASS. Every one of these is paid 8-13 times a round, so
# they are the whole felt pace of a clash — and the clash was reading as one
# indistinct scuffle rather than a sequence of trades. The fix is NOT a uniform
# slowdown (that just feels sluggish): the ANTICIPATION and the BREATH AFTER got
# most of the increase, because those are the two windows in which a player can
# actually see WHO is swinging and WHAT it did. The strike itself stays fast —
# an impact should still be a snap.
const LUNGE_ANTICIPATION: float = 0.09  # pull-back away from the target (was 0.05)
const LUNGE_STRIKE: float = 0.09        # drive forward into the target (was 0.08)
const LUNGE_APEX: float = LUNGE_ANTICIPATION + LUNGE_STRIKE
const LUNGE_SETTLE: float = 0.18        # ease back home after the blow
const RECOIL_SHOVE: float = 0.05        # struck card snaps away from attacker
const RECOIL_SETTLE: float = 0.20       # and eases back
const POST_HIT_BEAT: float = 0.13       # breath after an ordinary hit (was 0.06)
const HITSTOP_BEAT: float = 0.26        # punctuation after a kill / heavy blow (was 0.18)
# The blow that ends the FIGHT stops the world (★8 of the cool pitch): the
# killer freezes at full extension for this long while the colour drains.
# Deliberately ~3× HITSTOP_BEAT — the climax must be a different event class
# from a heavy hit, not a longer copy of one.
const KILLING_BLOW_HOLD: float = 0.55

# ── The house grammar (R3) ─────────────────────────────────────────────
# The four beats every animation in the game already speaks, measured from
# ~137 call sites and named so new code stops re-deriving them. Pair each
# token with its easing: ANTICIPATE = SINE-out, PUNCH = QUAD-out,
# SETTLE = BACK-out (the house signature), EXIT = EASE_IN, LOOP = SINE
# in-out. The _SLOW variants are the long end of each measured band (big
# tiles, ceremonial exits). GameTheme's verbs (punch / fade_exit / deal_in /
# claim_pop / card_reveal…) are built from these — prefer a verb over
# hand-rolling a tween; reach for the tokens when the motion is genuinely
# bespoke.
const ANTICIPATE: float = 0.05   # SINE-out pull-back before a strike/pop
const PUNCH: float = 0.10        # QUAD-out impact (0.08–0.12 band)
const SETTLE: float = 0.18       # BACK-out return to rest (small tiles)
const SETTLE_SLOW: float = 0.34  # BACK-out settle for big tiles / entrances
const EXIT: float = 0.30         # EASE_IN fade/fly-away
const EXIT_SLOW: float = 0.46    # ceremonial exits (verdict, reveals)
const LOOP: float = 1.1          # SINE breathing loops (0.55–1.8 band)


# ── THE BOIL — line art animated on twos (▲1, docs/TECHNIQUE_HUNT_20260902.md) ──
#
# A line that never moves is not hand-inked; it is PRINTED. Hand-drawn media do
# not animate line art at the frame rate — they animate it on twos or threes, and
# the residual wobble between drawings is the whole reason the line reads as
# having been made by a hand. The effect is famously invisible until removed.
#
# Four numbers, and each of them is the difference between a boil and a defect:
#
#   * BOIL_FPS 8. Not 60. At frame rate this is vibration, not drawing.
#   * BOIL_ORDER 0,1,2,1,0,2 — a PING-PONG, not a loop. A plain 0,1,2 cycle reads
#     as a repeating 3-frame flicker because the eye finds the seam where the last
#     drawing snaps back to the first.
#   * BOIL_AMP 0.6 px. Above ~1.2 it stops being a hand and becomes a vibration;
#     sub-pixel offsets still render because LINEAR filtering resolves them as
#     partial alpha (the fact `RubricStroke` documents for its 0.85 px stroke).
#   * THREE variants. Not one offset animated continuously — three fixed drawings
#     cycled, which is what an animator actually produces and what keeps this free:
#     the offsets are a pure function of (point index, variant), so there is no
#     per-frame math and no state to drift.
#
# Offset the CONTROL POINTS, never the CanvasItem: moving the whole item is a
# shake. `boil_offset` is therefore indexed per point.
#
# It is NOT scaled by `time()`. Anim-speed scales BEATS — things the player is
# waiting on. A boil is a property of the material, not a beat: at Instant the
# ink should still be ink, not a strobe.
const BOIL_FPS: float = 8.0
const BOIL_AMP: float = 0.6
const BOIL_ORDER: PackedInt32Array = [0, 1, 2, 1, 0, 2]


## Which of the three drawings is showing, from elapsed seconds.
static func boil_variant(elapsed: float) -> int:
	var step := int(floor(maxf(elapsed, 0.0) * BOIL_FPS)) % BOIL_ORDER.size()
	return BOIL_ORDER[step]


## Sub-pixel displacement for control point `i` in drawing `variant`.
## Variant 0 is the undisplaced drawing, so a caller that never advances the
## variant — Reduce Motion, headless — draws exactly what it drew before.
static func boil_offset(i: int, variant: int, amp: float = BOIL_AMP) -> Vector2:
	if variant <= 0:
		return Vector2.ZERO
	return Vector2(_boil_hash(i * 2 + 1, variant), _boil_hash(i * 2 + 2, variant)) * amp


## Deterministic value noise in [-1, 1] — the classic sin/fract hash. Stateless,
## so the same point in the same drawing is always displaced identically and the
## chart cannot crawl.
static func _boil_hash(i: int, k: int) -> float:
	var x: float = sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453
	return (x - floor(x)) * 2.0 - 1.0


static func time(base: float) -> float:
	# Scale a combat-visible tween duration by the player's animation-speed
	# setting. Mirrors Combat._short_pause: speed 3.0 (Instant) makes tweens
	# near-instant in step with the collapsed pacing pauses.
	if UserSettings != null and UserSettings.anim_speed > 0.01:
		return base / UserSettings.anim_speed
	return base


# ── Particle silhouettes (2026-07-28) ──────────────────────────────────
# Every burst in the game was an UNTEXTURED CPUParticles2D — that is, a hard
# edged, axis-aligned SQUARE two to six pixels across. It is the whole reason
# ash, sparks, coins and spell motes all read as the same engine primitive:
# they WERE the same primitive. One `texture` key per preset upgrades ~40 call
# sites at once, and it is the cheapest visual win in the codebase.
#
# Baked procedurally rather than shipped as art, so there is no import step and
# no filtering surprise, and cached per kind for the session. The silhouettes
# are deliberately IRREGULAR (three sine harmonics on the radius) for the same
# reason WritLeaf wobbles its deckle: a mathematically perfect disc is the one
# thing a fleck of ash never is. At 3 px only the softness reads; by the time a
# preset scales past ~6 px the lopsidedness starts to show, which is where it
# matters.
static var _ptex_cache: Dictionary = {}

const _PTEX_SIZE := 32

## White-on-transparent particle silhouette; CPUParticles2D tints it per preset.
## Kinds: "fleck" (ash, dust, spell motes) · "spark" (hot contact spray) ·
## "disc" (coins — a struck edge, so a harder rim) · "ink" (wet, blotted).
static func particle_tex(kind: String) -> Texture2D:
	if _ptex_cache.has(kind):
		return _ptex_cache[kind]
	var n := _PTEX_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (float(n) - 1.0) * 0.5
	# `power` steepens the falloff (a tight hot spark vs a soft dust puff),
	# `core` is the fraction of the radius held at full alpha, and `wobble` is
	# how far the silhouette departs from a circle.
	var power := 1.6
	var core := 0.05
	var wobble := 0.18
	match kind:
		"spark":
			power = 2.6; core = 0.16; wobble = 0.10
		"disc":
			power = 0.8; core = 0.62; wobble = 0.06
		"ink":
			power = 1.1; core = 0.34; wobble = 0.30
		_:
			pass  # "fleck" keeps the defaults above
	# Seeded off the kind so a given silhouette is identical every session.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var h1 := rng.randf_range(0.0, TAU)
	var h2 := rng.randf_range(0.0, TAU)
	var h3 := rng.randf_range(0.0, TAU)
	for y in n:
		for x in n:
			var dx := float(x) - c
			var dy := float(y) - c
			var d := sqrt(dx * dx + dy * dy) / c
			var ang := atan2(dy, dx)
			# A lopsided body, a lobe, and a fine nibble.
			var r := 1.0 + wobble * (0.55 * sin(ang * 2.0 + h1) \
				+ 0.30 * sin(ang * 3.0 + h2) + 0.15 * sin(ang * 5.0 + h3))
			var t := clampf(d / maxf(r, 0.05), 0.0, 1.0)
			var a := 0.0
			if t < core:
				a = 1.0
			elif t < 1.0:
				a = pow(1.0 - (t - core) / maxf(1.0 - core, 0.001), power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_ptex_cache[kind] = tex
	return tex


static var _beam_cache: Dictionary = {}
static var _soft_rect_shader: Shader = null
static var _beam_shader_cache: Shader = null

## ── The beam kit (2026-09-09) ─────────────────────────────────────────
## WHY EVERY Line2D EFFECT IN THIS GAME LOOKED LIKE A LINE: a Line2D has
## UNIFORM OPACITY ACROSS ITS WIDTH. It is a hard-edged band — there is no soft
## falloff at its edges and no internal structure, so whatever it is meant to be
## (a bolt, a beam, a tracer) it reads as a stroke from a drawing tool. Stacking
## three of them, which is what the first lightning rebuild did, does not fix
## that; it makes a thicker hard band with a dimmer hard band behind it.
##
## The fix the realtime-VFX practice actually uses is to TEXTURE the line. Once
## the cross-section is a painted profile rather than a constant, one line does
## the whole job — soft outer edge, bright body, white-hot centre — and the
## layer stack collapses into a single draw.
##
## The strip is generated rather than shipped (no asset, no import step, same
## idiom as `particle_tex` right above): **R carries the HEAT profile** (1 at
## the core) and **A carries the OPACITY profile**, which lets the shader ramp
## the core toward white while the body keeps the caller's colour. Multiplying
## by a vertex colour could never do that — multiplication cannot brighten.
##
## U runs ALONG the line, V ACROSS its width (Line2D's STRETCH mapping), so the
## U axis is free for lengthwise grain: a bolt is not equally bright end to end.
##
## Kinds "bolt"/"streak"/"comet"/"trail" are all GLOW profiles (thin hot spine,
## wide soft halo). "ink" (2026-09-10) is the first that is not — see its arm.
static func beam_tex(kind: String) -> Texture2D:
	if _beam_cache.has(kind):
		return _beam_cache[kind]
	var lu := 48   # along the line
	var lv := 64   # across the width
	# core: half-width held near-white · edge: falloff power of the outer halo
	# halo: how much of the wide soft glow survives · grain: lengthwise variation
	# TUNED AGAINST THE LINE'S FULL WIDTH, which is the trap here: `edge` is the
	# power on (1 - t), so 3.6 puts alpha 0.08 at the halfway point and all but
	# the central few pixels of a 26px beam render transparent — the first cut
	# photographed THINNER than the hard line it replaced. Around 1.9 keeps the
	# halo at ~0.5 alpha halfway out, which is what makes the width read.
	var core := 0.14
	var edge := 1.9
	var halo := 0.85
	var grain := 0.18
	# How much the EDGE HARDNESS wanders along the run (lost-and-found). It is
	# per-kind and deliberately smallest on the INFORMATIONAL kinds: a chevron
	# or an aim thread is a read-aid, and Into the Breach's rule applies —
	# clarity before spectacle. A stroke that melts where the player is trying
	# to measure something is a worse stroke, however well drawn.
	var lost_e := 0.30
	# "comet" ramps alpha ALONG the line (0 at the tail, 1 at the head). It lives
	# in the texture rather than in a Line2D `gradient` because the beam shader
	# writes COLOR outright and never reads the vertex colour a gradient sets.
	var comet := false
	match kind:
		"bolt":
			core = 0.11; edge = 1.8; halo = 0.90; grain = 0.22
			lost_e = 0.42   # lightning is the least machined thing here
		"streak":
			core = 0.18; edge = 2.1; halo = 0.80; grain = 0.10
			lost_e = 0.20   # read-aid kind (chevrons): keep it measurable
		"comet":
			core = 0.16; edge = 2.0; halo = 0.82; grain = 0.08; comet = true
			lost_e = 0.22   # the targeting arrow and aim thread ride this
		"trail":
			core = 0.26; edge = 1.5; halo = 0.70; grain = 0.06
			lost_e = 0.38   # a drag ribbon is pure atmosphere; let it breathe
		"ink":
			# INK IS NOT ENERGY, and the profile is where that gets decided.
			# Every other kind here is a GLOW — a thin hot spine with a wide soft
			# halo — because it is drawn on a dark table and has to look like it
			# is emitting. A written stroke is the opposite object: it is a DENSE
			# BODY that has soaked into paper, so the numbers invert.
			#   · core 0.34 — a broad solid centre. A pen lays a flat mass of
			#     pigment, not a filament; at the glow kinds' 0.11-0.18 the
			#     stroke reads as a lit wire lying on the chart.
			#   · edge 1.05 — a SLOW falloff, which is FEATHERING: ink creeping
			#     along the paper fibres either side of the nib's track. The
			#     glow kinds' ~1.9 is a clean optical falloff and looks printed.
			#   · grain 0.34 — the strongest lengthwise variation of any kind,
			#     because that is nib pressure and flow. A hand-drawn line
			#     breathes in weight along its length; a line that does not is
			#     the tell that a machine drew it.
			core = 0.34; edge = 1.05; halo = 0.62; grain = 0.34
			# The HIGHEST here: a nib bleeds into paper unevenly, so a pen stroke
			# has the most wandering edge of anything in the kit.
			lost_e = 0.52
		_:
			pass
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var h1 := rng.randf_range(0.0, TAU)
	var h2 := rng.randf_range(0.0, TAU)
	var h3 := rng.randf_range(0.0, TAU)
	var h4 := rng.randf_range(0.0, TAU)
	var img := Image.create(lu, lv, false, Image.FORMAT_RGBA8)
	for u in lu:
		var fu := float(u) / float(lu - 1)
		# Lengthwise flicker, seamless in U so a TILEd beam has no visible joint.
		var g := 1.0 - grain * (0.5 + 0.5 * sin(fu * TAU * 3.0 + h1)) \
			* (0.5 + 0.5 * sin(fu * TAU * 7.0 + h2))
		if comet:
			g *= pow(fu, 1.6)
		# LOST AND FOUND EDGES, ALONG THE RUN — the ring's angular version of
		# this, applied to the other half of the kit. `grain` already varies a
		# beam's ALPHA down its length, but its EDGE HARDNESS was constant for
		# the whole stroke: the same falloff at the tail as at the head, which
		# is the thing a drawn line never does. Varying the falloff POWER gives
		# passages where the stroke is crisp and passages where it melts into
		# the ground, which is what stops a correct beam still reading as
		# extruded.
		#
		# Harmonics 2 and 3, as on the ring and for the same reason: this works
		# in LONG passages. At `grain`'s 3-and-7 it would read as a dirty edge
		# rather than a lost one. A LOWER power is a SLOWER falloff, i.e. softer.
		var e_u: float = edge * (1.0 + lost_e * (0.62 * sin(fu * TAU * 2.0 + h3)
			+ 0.38 * sin(fu * TAU * 3.0 - h4)))
		for v in lv:
			var t: float = absf(2.0 * float(v) / float(lv - 1) - 1.0)
			var hot: float = pow(clampf(1.0 - t / core, 0.0, 1.0), 0.55)
			var body: float = pow(clampf(1.0 - t, 0.0, 1.0), maxf(e_u, 0.20))
			var a: float = clampf(hot + body * halo, 0.0, 1.0) * g
			img.set_pixel(u, v, Color(hot, hot, hot, a))
	var tex := ImageTexture.create_from_image(img)
	_beam_cache[kind] = tex
	return tex


## Feather a ColorRect's edges — THE CORRECT FORM FOR A SLAB USED AS LIGHT.
##
## A ColorRect is a rectangle of uniform colour with four hard edges, which is
## exactly right for a SCRIM (a dim layer is meant to be even, and a full-rect
## one has no visible edge at all) and exactly wrong for a wash, a sweep or a
## touch: light has no straight sides. `_spell_fx_banner_sweep` documented the
## symptom without naming the cause — "a lone thin bar reads as a UI artifact" —
## and worked around it by adding a SECOND bar.
##
## IT MULTIPLIES `COLOR.a` RATHER THAN WRITING COLOR OUTRIGHT, and that is the
## whole design. `beam_material` assigns COLOR, which is why every caller of it
## has to fade through a `fade` uniform and why three `modulate`/`color:a` tweens
## in this codebase were silently dead. Reading and modifying instead leaves the
## node's own `color` — and therefore every existing `color:a` tween — working
## untouched. A primitive that quietly breaks the callers it is meant to fix is
## not an improvement.
##
## `feather` is in UV, so it scales with the rect: 0.5 on an axis means the
## fade reaches the middle (a blade with no flat centre at all).
static func soft_rect_material(feather: Vector2 = Vector2(0.25, 0.12),
		power: float = 1.35) -> ShaderMaterial:
	if _soft_rect_shader == null:
		_soft_rect_shader = Shader.new()
		_soft_rect_shader.code = """shader_type canvas_item;

uniform vec2 feather = vec2(0.25, 0.12);
uniform float power = 1.35;

void fragment() {
	// Distance to the NEAREST edge on each axis, in UV.
	vec2 d = min(UV, vec2(1.0) - UV);
	float ax = clamp(d.x / max(feather.x, 0.0001), 0.0, 1.0);
	float ay = clamp(d.y / max(feather.y, 0.0001), 0.0, 1.0);
	COLOR.a *= pow(ax, power) * pow(ay, power);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _soft_rect_shader
	mat.set_shader_parameter("feather", feather)
	mat.set_shader_parameter("power", power)
	return mat


## Recolour a beam built by `beam_line`. THE OBVIOUS WAY DOES NOT WORK: setting
## `default_color` or `modulate` on the node changes nothing, because
## `beam_material` writes COLOR outright and reads neither. A caller that
## retints a beam at runtime — the drag ribbon changes colour for a creature
## versus a spell — must go through the shader's `tint` uniform, and the failure
## mode if it does not is SILENT: the old colour simply stays.
static func beam_tint(line: Line2D, tint: Color) -> void:
	if line == null or not is_instance_valid(line):
		return
	var m := line.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("tint", tint)


## A smooth radial falloff, cached — THE REPLACEMENT FOR `draw_circle` USED AS
## LIGHT, and the reason that defect kept getting rebuilt by hand.
##
## A filled circle has a HARD EDGE, so a call site that needs a glow inside a
## `_draw` callback has nowhere to go: `Motion.burst` is particles and
## `Motion.ring` is a band, and neither can be called from a draw. What people
## reach for instead is three concentric discs at descending alpha, which is a
## STEPPED approximation — and steps BAND. Card2D's fuse ember is exactly that,
## r13/r7.5/r4 at alpha 0.26/0.65/1.00, so its two brightest rings are visible
## as rings on the one thing in the frame that is supposed to be a coal.
##
## `power` is the falloff exponent: higher is a tighter, hotter point; ~2.2 is a
## naked flame and ~1.4 is a diffuse haze.
static func glow_tex(power: float = 2.2) -> Texture2D:
	var key := "glow_%.2f" % power
	if _beam_cache.has(key):
		return _beam_cache[key]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n - 1) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = pow(clampf(1.0 - d, 0.0, 1.0), power)
			# White RGB so a draw-time modulate carries the colour intact; the
			# falloff lives entirely in alpha. Baking the tint here instead would
			# make the texture single-use and force a cache entry per colour.
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	_beam_cache[key] = tex
	return tex


## Draw a soft point of light inside a `_draw` callback. Two passes, both smooth:
## a wide body in `tint` and a tight core lifted toward white.
##
## THE CORE IS A SECOND PASS RATHER THAN PART OF THE TEXTURE because the tint is
## applied by `draw_texture_rect`'s modulate, which MULTIPLIES — a white-hot
## centre baked into the image would be multiplied straight back down to the
## tint and vanish. Two passes is also what keeps the house contrast rule
## reachable here: a lone warm glow on the warm table is camouflage, and the
## hot middle is what separates an ember from an orange smudge.
## `power` IS EXPOSED BECAUSE THE DEFAULT LOSES AN EMBER. At 2.2 the falloff is
## so peaked that a 13px coal is bright for ~4px and faint everywhere else: the
## smoothness test passed (6x fewer kinks than the disc stack it replaced) while
## the thing itself had all but vanished from the frame. A metric satisfied by
## deleting the subject is the oldest failure in this file's history — LOOK at
## the shot as well as reading the number. ~1.5 is a coal, 2.2+ is a spark.
static func draw_glow(ci: CanvasItem, centre: Vector2, radius: float,
		tint: Color, core: float = 0.45, power: float = 2.2) -> void:
	if ci == null or not is_instance_valid(ci) or radius <= 0.0:
		return
	var tex := glow_tex(power)
	ci.draw_texture_rect(tex,
		Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		false, tint)
	if core <= 0.0:
		return
	var cr: float = radius * core
	ci.draw_texture_rect(tex,
		Rect2(centre - Vector2(cr, cr), Vector2(cr, cr) * 2.0),
		false, Color(tint.lightened(0.72), minf(tint.a * 1.35, 1.0)))


## The material that reads `beam_tex`: body in the caller's colour, core ramped
## toward `core`. `fade` is a uniform because the shader writes COLOR outright and
## `modulate` therefore never reaches it.
##
## `core` DEFAULTS TO WHITE, which is every energy call site's answer and the
## house contrast rule for a warm dark table: a lone warm line there is
## camouflage, so the middle of the stroke goes white-hot.
##
## IT IS A PARAMETER BECAUSE THAT RULE INVERTS ON A LIGHT GROUND (2026-09-10).
## The war-table CHART is parchment, and a white core on cream is not a hot core,
## it is a hole — the first cut of the map's road ink was drawn with the default
## and photographed as a faint smudge. On paper the "hot" middle of a mark is its
## DARKEST, most saturated part, because that is where the pigment pooled. Same
## shader, same profile, inverted value; the ring engine's own note flagged this
## ground ("would have been unusable on the shell's parchment") one effect early.
static func beam_material(tint: Color, heat: float = 0.95,
		core: Color = Color(1.0, 1.0, 1.0)) -> ShaderMaterial:
	if _beam_shader_cache == null:
		_beam_shader_cache = Shader.new()
		_beam_shader_cache.code = """shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 core : source_color = vec4(1.0);
uniform float heat = 0.95;
uniform float fade = 1.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec3 col = mix(tint.rgb, core.rgb, clamp(t.r * heat, 0.0, 1.0));
	COLOR = vec4(col, t.a * tint.a * fade);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _beam_shader_cache
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("core", core)
	mat.set_shader_parameter("heat", heat)
	mat.set_shader_parameter("fade", 1.0)
	return mat


## Build a Line2D already wearing the beam kit. `width` is the FULL span of the
## painted profile, so it is deliberately wider than the old hard stroke it
## replaces — most of the extra is soft halo that was not being drawn at all.
## `taper` shapes the beam ALONG its length, which the texture cannot do (that
## paints the cross-section). Presets:
##
##   ""       uniform — a lightning channel really is about as wide throughout.
##   "slash"  THE WEAPON ARC. Narrow at the trailing end, swelling to its widest
##            just before impact, easing off at the very tip: the "flag" shape
##            the slash-VFX literature describes, where a narrow tail implies
##            speed and elapsed time and the wide leading edge says which way it
##            went. A uniform-width bowed line with round caps is a ROD, and a
##            rod is what the enemy strike arc looked like.
##   "comet"  narrow tail swelling to a blunt head, no tip taper (a projectile,
##            not a blade).
##   "nib"    THE WRITTEN STROKE, for the "ink" texture kind. A firm entry, a
##            full-pressure belly that eases mid-travel, and the widest point at
##            the terminal — where the pen is still sitting. See the curve below
##            for why a comet is the wrong shape for anything hand-drawn.
static func beam_line(points: PackedVector2Array, tint: Color, width: float,
		kind: String = "bolt", heat: float = 0.95,
		taper: String = "", core: Color = Color(1.0, 1.0, 1.0)) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.texture = beam_tex(kind)
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	line.material = beam_material(tint, heat, core)
	match taper:
		"slash":
			var c := Curve.new()
			c.add_point(Vector2(0.0, 0.06))
			c.add_point(Vector2(0.55, 0.52))
			c.add_point(Vector2(0.86, 1.0))
			c.add_point(Vector2(1.0, 0.42))
			line.width_curve = c
		"comet":
			var c2 := Curve.new()
			c2.add_point(Vector2(0.0, 0.10))
			c2.add_point(Vector2(0.70, 0.62))
			c2.add_point(Vector2(1.0, 1.0))
			line.width_curve = c2
		"nib":
			# THE WRITTEN STROKE. Deliberately NOT "comet", which was the first
			# thing tried here: a comet is 0.10 at the tail, i.e. it starts from
			# nothing, and a written line does not — the pen TOUCHES DOWN with
			# weight and the entry stroke is already most of full width. A comet
			# taper on a route drew a thread that thickened into a road, which
			# reads as a projectile's wake, not as something a hand wrote.
			#
			# So: a firm entry (0.38), the belly at full pressure, a slight ease
			# off mid-stroke as the hand travels, and the widest point at the
			# very end — because that end is WHERE THE NIB IS RIGHT NOW, sitting
			# still and pooling. On a finished stroke that same swell reads as
			# the pen lifting off, which is what a real terminal looks like.
			var c3 := Curve.new()
			c3.add_point(Vector2(0.0, 0.38))
			c3.add_point(Vector2(0.30, 0.94))
			c3.add_point(Vector2(0.74, 0.80))
			c3.add_point(Vector2(1.0, 1.0))
			line.width_curve = c3
		_:
			pass
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	# A round cap re-draws the profile as a disc at each end and reads as a blob
	# on a soft beam; the texture already feathers the ends.
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	return line


# ── The burst factory (R5) ─────────────────────────────────────────────
# Every one-shot CPUParticles2D pop in the game used to hand-configure ~20
# identical setup lines per site; `burst()` is the one emitter with the
# per-site LOOKS preserved as presets (each preset keeps the numbers its
# call site shipped with). `overrides` merges over the preset — pass the
# per-call variables (color, amount, direction) there. Ambient LOOPING
# emitters (Combat's meadow embers, Rest's campfire, screen atmosphere)
# are not bursts and stay hand-built at their sites.
#
# Ramp entries are [offset, Color] pairs: first row must sit at offset 0,
# last at offset 1 (they map onto the Gradient's two built-in points).
# A "ramp" key wins over "color".
const BURST_PRESETS: Dictionary = {
	# Rising ember/ash pop — sacrifice ritual, piercing exit spark, death
	# weight. Embers RISE (negative gravity); pass "color"/"amount" per call.
	"ash": {
		"texture": "fleck",
		"z_index": 215, "explosiveness": 0.85, "amount": 26, "lifetime": 0.9,
		"direction": Vector2(0, -1), "spread": 38.0, "gravity": Vector2(0, -45.0),
		"velocity_min": 45.0, "velocity_max": 120.0,
		"scale_min": 2.0, "scale_max": 5.0,
	},
	# Contact-point spark spray at a struck edge. Sparks FALL where ash
	# rises — different material, so kills read distinct. Direction/amount/
	# velocity_max/color are computed per blow by Combat._spawn_impact_burst.
	"impact": {
		"texture": "spark",
		"z_index": 216, "explosiveness": 1.0, "amount": 16, "lifetime": 0.32,
		"direction": Vector2(0, -1), "spread": 55.0, "gravity": Vector2(0, 240.0),
		"velocity_min": 130.0, "velocity_max": 240.0,
		"scale_min": 1.2, "scale_max": 2.6,
	},
	# All-directions pop where a spell resolves; pass "color" per school.
	"spell": {
		"texture": "fleck",
		"z_index": 150, "explosiveness": 1.0, "amount": 18, "lifetime": 0.55,
		"direction": Vector2(0, -1), "spread": 180.0, "gravity": Vector2(0, 140.0),
		"velocity_min": 90.0, "velocity_max": 210.0,
		"scale_min": 2.0, "scale_max": 4.5,
	},
	# Anvil sparks (the forge set-piece): spray up and out, then fall hard.
	"spark_fall": {
		"texture": "spark",
		"z_index": 220, "explosiveness": 0.92, "amount": 36, "lifetime": 0.7,
		"direction": Vector2(0, -1), "spread": 62.0, "gravity": Vector2(0, 640.0),
		"velocity_min": 180.0, "velocity_max": 360.0,
		"scale_min": 1.4, "scale_max": 3.0,
		"ramp": [[0.0, Color(1.0, 0.95, 0.72, 1.0)], [1.0, Color(1.0, 0.42, 0.10, 0.0)]],
	},
	# The treasure chest's coin fountain: a gentle toss up, then a long
	# tumbling rain down the sheet.
	"coin": {
		"texture": "disc",
		"z_index": 60, "explosiveness": 0.55, "amount": 46, "lifetime": 1.5,
		"direction": Vector2(0, -1), "spread": 52.0, "gravity": Vector2(0, 460.0),
		"velocity_min": 120.0, "velocity_max": 260.0,
		"angular_min": -220.0, "angular_max": 220.0,
		"scale_min": 3.6, "scale_max": 6.6,
		"ramp": [[0.0, Color(1.0, 0.92, 0.55, 1.0)], [1.0, Color(0.85, 0.58, 0.16, 0.0)]],
	},
	# Small gold chink for shop transactions; amount/velocity vary by
	# gain-vs-spend at the call site.
	"coin_spark": {
		"texture": "disc",
		"z_index": 210, "explosiveness": 0.8, "amount": 18, "lifetime": 0.62,
		"direction": Vector2(0, -1), "spread": 70.0, "gravity": Vector2(0, 430.0),
		"velocity_min": 150.0, "velocity_max": 300.0,
		"scale_min": 1.5, "scale_max": 3.1,
		"ramp": [[0.0, Color(1.0, 0.90, 0.45, 1.0)], [1.0, Color(0.95, 0.42, 0.12, 0.0)]],
	},
	# Neutral defaults — Combat's spell-family emitter and fully bespoke
	# one-offs (GameOver's verdict curtain, Rest's heal motes) build on this
	# with overrides.
	"base": {
		"texture": "fleck",
		"z_index": 150, "explosiveness": 1.0, "amount": 18, "lifetime": 0.6,
		"direction": Vector2(0, -1), "spread": 90.0, "gravity": Vector2(0, 140.0),
		"velocity_min": 90.0, "velocity_max": 210.0,
		"scale_min": 2.0, "scale_max": 4.5,
	},
}


static func burst(host: Node, global_pos: Vector2, preset: String = "base",
		overrides: Dictionary = {}) -> void:
	# One-shot particle pop at `global_pos`, parented to `host` (pass a node
	# that outlives the source — Combat uses its HUD layer so a freed card
	# can't take its own death burst with it). Gates on the Particles setting
	# and headless once, here; call sites that are decorative-by-contract
	# additionally gate reduce_motion themselves. Self-frees after lifetime.
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if UserSettings != null and not UserSettings.particles:
		return
	if DisplayServer.get_name() == "headless":
		return
	var pr: Dictionary = BURST_PRESETS.get(preset, BURST_PRESETS["base"]).duplicate()
	pr.merge(overrides, true)
	var p := CPUParticles2D.new()
	if pr.has("name"):
		p.name = String(pr["name"])
	p.position = global_pos
	p.one_shot = true
	p.z_index = int(pr.get("z_index", 150))
	p.explosiveness = float(pr.get("explosiveness", 1.0))
	p.amount = int(pr.get("amount", 18))
	var life: float = float(pr.get("lifetime", 0.6))
	p.lifetime = life
	p.direction = pr.get("direction", Vector2(0, -1))
	p.spread = float(pr.get("spread", 90.0))
	p.gravity = pr.get("gravity", Vector2(0, 140.0))
	p.initial_velocity_min = float(pr.get("velocity_min", 90.0))
	p.initial_velocity_max = float(pr.get("velocity_max", 210.0))
	p.scale_amount_min = float(pr.get("scale_min", 2.0))
	p.scale_amount_max = float(pr.get("scale_max", 4.5))
	if pr.has("angular_min"):
		p.angular_velocity_min = float(pr["angular_min"])
		p.angular_velocity_max = float(pr.get("angular_max", -float(pr["angular_min"])))
	if pr.has("emission_rect"):
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = pr["emission_rect"]
	if pr.has("ramp"):
		var stops: Array = pr["ramp"]
		var g := Gradient.new()
		g.set_color(0, stops[0][1])
		g.set_color(1, stops[stops.size() - 1][1])
		for i in range(1, stops.size() - 1):
			g.add_point(float(stops[i][0]), stops[i][1])
		p.color_ramp = g
	else:
		p.color = pr.get("color", Color.WHITE)
	var tk: String = String(pr.get("texture", ""))
	if tk != "":
		p.texture = particle_tex(tk)
		# CPUParticles2D draws the TEXTURE scaled by scale_amount, where an
		# untextured particle is a 1x1 unit quad. Divide through so every
		# preset's historical scale_amount keeps meaning PIXELS and nothing
		# on screen changes size — only its silhouette.
		p.scale_amount_min /= float(_PTEX_SIZE)
		p.scale_amount_max /= float(_PTEX_SIZE)
	p.emitting = true
	host.add_child(p)
	host.get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


# ── The ring engine (R5; rebuilt on a distance field 2026-09-09) ───────
# THE expanding-ring implementation — Combat's spell rings, the shell's
# ring_pulse verb, the impact kit's shock_rings and the net arsenal's chip
# burst all draw through here (three separate implementations before R5).
#
# IT WAS A Line2D CIRCLE UNTIL 2026-09-09, and that is why every ring in the
# game read as a wireframe instead of as light. Three faults compounded:
#
#   · A Line2D stroke is a FLAT band, hard-cut on BOTH sides. A blast front
#     has no outline — it has a falloff. An outline is what a drawing tool
#     gives you when you ask for a circle, which is exactly how it read.
#   · The apparent stroke was ~1.7px and effectively CONSTANT: `width`
#     tweened DOWN 3.0 → 1.05 over precisely the span `scale` grew
#     0.55 → 1.6, and the two cancelled. So the loudest beats in the game
#     were a hairline "O" expanding. A hairline circle is the shape of a
#     selection indicator, not of force.
#   · A perfect 48-gon at one uniform colour, so nothing in the silhouette
#     or the shading said "energy".
#
# It is now ONE quad carrying a radial distance field, which buys three
# things a stroke cannot:
#
#   · AN ASYMMETRIC BAND. The falloff is tight outside and long inside, so
#     the ring is a leading EDGE with a WAKE behind it. That asymmetry is
#     the whole read — a symmetric band sits still and reads as a bubble,
#     which is the same complaint that put two rings in `shock_rings`.
#   · THE HOT CORE AS A GRADIENT. The house contrast rule (CLAUDE.md — a
#     lone warm ring is camouflage on the warm table) used to need a SECOND
#     white ring inside the first to satisfy it. The ramp now lives in the
#     band: white-hot at the front, accent through the wake. Note this does
#     NOT make the doubled call sites redundant — `shock_rings` and
#     Combat._trigger_fx_ring pair a fast ring with a slow one as a TIMING
#     device ("one ring reads as a bubble"), which is a separate argument
#     from visibility and still holds.
#   · A CIRCLE THAT IS NOT A PRIMITIVE. A two-octave angular wobble keeps
#     the silhouette off perfect-round — the same reason `particle_tex`
#     takes a `wobble` and WritLeaf deckles its edge.
#
# IT STAYS A Node2D (a Sprite2D over a cached blank quad), and that is
# LOAD-BEARING rather than incidental: Card2D._spawn_press_ring hands this a
# PanelContainer as its host, and a Control child would be re-fitted by
# container layout mid-flight — see the note at that call site.
#
# opts (defaults preserve every historical call site's geometry and timing):
#   radius: float 16      front radius before scaling
#   start_scale: float 0.55 · end_scale: float 1.6 · duration: float 0.42
#   width: float 3        the band's weight, in the old stroke's px units
#   width_end: float 0    if > 0, thin the band to this as it expands
#   z_index: int 0 · oval: Vector2.ONE (squash for ground ellipses)
#   trans: Tween.TransitionType — applied to the scale tween when present
#   fade_in: float 0      if > 0, alpha 0→1 first, THEN the expansion
#   delay: float 0 · scale_time: bool false (wrap duration in Motion.time)
#   wake: float 3.2       inner trail length, as a multiple of the band
#   hot: float 0.55       fraction of the band that goes white-hot
#   heat_gain: float 0.92 how far that core is pushed toward white; drop it
#                         when the ring's HUE is the information (see ring_static)
#   wobble: float 0.018   departure from perfect-round, in front-radius units

## Slack left outside the front for the outer feather and the wobble. The front
## sits at `1.0 / RING_QUAD_PAD` in the shader's 0-centre → 1-edge units, so the
## ring lands on the caller's `radius` exactly where the Line2D circle did.
const RING_QUAD_PAD := 1.42

## The deliberate part of the 2026-09-09 rebuild: the caller's px `width` was a
## STROKE and is now a BAND, so it is spent at a gain. Without this the new ring
## is the old hairline with softer edges — which measured as strictly worse,
## because a soft hairline is dimmer than a hard one and says no more.
const RING_BAND_GAIN := 1.5

## …but the band is carried in FRONT-RADIUS units, so a wide `width` on a small
## `radius` (shock_rings opens at radius 17 width 5) would otherwise resolve to
## a band wider than the ring itself and render as a fuzzy ball rather than a
## front. Shot-caught. The ceiling keeps a ring a ring at every call site.
const RING_BAND_MIN := 0.030
const RING_BAND_MAX := 0.140

## ADDITIVE WAS TRIED AND LOST (2026-09-09, _shot_ring_ab). The war table is
## dark, so blend_add looked like the obvious call; measured, it carried 47% of
## the alpha path's ink at mid-flight and reached ZERO lit pixels on the tail,
## because folding alpha into the colour means a fading additive ring stops
## adding anything. It also flattens hue — the grace wave's blue washed to grey
## against the warm ground — and would have been unusable on the shell's
## parchment. There is no `add` option for that reason; don't add one back.
static var _ring_shader_cache: Shader = null
static var _ring_quad_cache: Texture2D = null


static func _ring_shader() -> Shader:
	if _ring_shader_cache != null:
		return _ring_shader_cache
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform float front_r = 0.704;
uniform float thickness = 0.12;
uniform float wake = 3.2;
uniform float hot = 0.55;
// How far the core is pushed toward white. Load-bearing for STANDING marks: a
// forecast reticle's colour IS its meaning (danger red), and whitening the band
// the way an impact beat wants turned the mark grey and silently deleted the
// read. Shot-caught 2026-09-09.
uniform float heat_gain = 0.92;
uniform float wobble = 0.0;
uniform float seed = 0.0;
uniform float fade = 1.0;
// 0 = the smooth analytic band; 1 = fully filamented. See `fil` below.
uniform float grit = 0.0;
uniform float lost = 0.0;   // lost-and-found edge variation (0 = uniform)

// SEAMLESS ANGULAR NOISE, and the seam is the whole reason it is built this way.
// The stylized-shockwave recipe is noise sampled in POLAR space (so it stretches
// into radial streaks) eroding the alpha — but `atan` wraps at +/-PI, and any
// hash-grid noise sampled on that angle draws a hard discontinuity down the
// 3 o'clock line. INTEGER HARMONICS are periodic in TAU by construction, so
// there is no seam to hide: the same layered-trig idiom foil_sweep uses.
//
// Being a function of the ANGLE ALONE, it is constant along any radius — which
// is exactly what makes it read as streaks running outward rather than as
// blotches sitting on the ring.
float ang_noise(float a, float s) {
	return 0.50 * sin(a * 11.0 + s * 1.7)
		+ 0.26 * sin(a * 19.0 - s * 2.3)
		+ 0.14 * sin(a * 31.0 + s * 3.1)
		+ 0.10 * sin(a * 53.0 - s * 1.3);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	float ang = atan(p.y, p.x);
	// Two octaves, so the departure from round is organic rather than a
	// lobed flower. Amplitude is in front-radius units and therefore scales
	// with the ring instead of shrinking away as it grows.
	float w = wobble * (sin(ang * 3.0 + seed) * 0.62
		+ sin(ang * 5.0 - seed * 1.7) * 0.38);
	float off = d - (front_r + w);
	// LOST AND FOUND EDGES — a DRAWING technique, not a shader one, and the one
	// that most separates a drawing from a diagram. A painter does not give a
	// form the same edge the whole way round: some of it is crisp where it wants
	// the eye, and some dissolves into the ground so the shape breathes. Every
	// procedural ring here had ONE feather for its entire circumference, which
	// is why a technically-correct shock front could still read as machined.
	//
	// The harmonics are 2 and 3, NOT `ang_noise`'s 11..53. Lost-and-found works
	// in LARGE passages — two or three arcs of hard edge and soft edge around
	// the ring. Running it at filament frequency would just be fuzz, which is a
	// different thing entirely and reads as a dirty edge rather than a lost one.
	// Integer harmonics keep it seamless across the atan wrap, same as above.
	float lo = sin(ang * 2.0 + seed * 1.3) * 0.62
		+ sin(ang * 3.0 - seed * 0.7) * 0.38;
	float soft = thickness * 0.55 * (1.0 + lost * lo);
	// THE SHOCK FRONT: a TIGHT outer edge, a LONG inner wake. The asymmetry is
	// the whole read. Feathering the outside by the full band (the first cut of
	// this) turns the ring into a fuzzy ball — the front has to stay a front.
	float a = off > 0.0
		? 1.0 - smoothstep(0.0, max(soft, 0.0001), off)
		: 1.0 - smoothstep(0.0, thickness * wake, -off);
	a = pow(clamp(a, 0.0, 1.0), 1.5);
	// RADIAL FILAMENTS BY ALPHA EROSION. A purely analytic band is clean, and
	// clean is the thing that reads as CG rather than as craft — the standing
	// criticism of procedural VFX in a hand-painted game. The fix is the
	// standard one: erode the alpha through a FEATHERED threshold against
	// polar noise, instead of fading every pixel equally.
	//
	// Two things ride the threshold, and both are the physical read:
	//   · it climbs into the WAKE (`wk`), so the front holds its edge while
	//     what trails it shreds — a shock front is coherent, its wake is not;
	//   · it climbs as the ring DIES (1.0 - fade), so the thing dissolves into
	//     filaments rather than dimming uniformly, which is the entire point of
	//     erosion over an alpha fade.
	float fil = 0.5 + 0.5 * ang_noise(ang, seed);
	float wk = clamp(-off / max(thickness * wake, 0.0001), 0.0, 1.0);
	// THE WHOLE THRESHOLD IS WEIGHTED BY `wk`, including the death term. Letting
	// (1.0 - fade) raise it everywhere perforated the FRONT as the ring died,
	// and a front with holes in it is a dashed circle — a different ugly, and
	// the exact failure the grit sweep showed at 0.75 and above.
	float thr = grit * (0.10 + wk * (0.72 + 0.50 * (1.0 - fade)));
	float ero = smoothstep(thr - 0.30, thr + 0.30, fil);
	a *= mix(1.0, ero, grit);
	// THE BURN EDGE. An erosion with no rim reads as FADING, not as being
	// consumed — the standard dissolve-shader fix is to brighten the narrow
	// band of pixels sitting AT the threshold, which is exactly where material
	// is being eaten this frame. The parabola peaks at ero == 0.5 (half gone)
	// and is zero at both settled ends, so only the live front lights up.
	//
	// EVERY TUTORIAL SPENDS THAT BRIGHTNESS AS AN HDR EMISSIVE AND LETS BLOOM
	// CARRY IT, AND THAT DOES NOT TRANSLATE HERE. Godot's Compatibility
	// renderer is SDR-only in 2D and its 2D glow is explicitly not planned, so
	// there is no post-process to pick up a value above 1.0 — an "emissive"
	// rim would simply clamp and look like flat white. The brightness has to be
	// baked into the colour and paid for in VALUE CONTRAST against the ground,
	// which is the same constraint that decided the white-hot core.
	//
	// It rides `grit`, so a ring with no erosion (the held marks, ring_static)
	// is byte-identical to before.
	// CUBED, because the plain parabola is not a BAND. `ero`'s own smoothstep is
	// a wide +/-0.30 window, so ero sits mid-range over a large part of the ring
	// and 4*ero*(1-ero) lit most of it — a milky halo, which is the opposite of
	// the read: a burn edge says "material is being consumed HERE", and a wide
	// one says nothing at all. The cube pulls it into a front.
	float burn = pow(4.0 * ero * (1.0 - ero), 3.0) * grit;
	// The hot core sits JUST INSIDE the front, where alpha is still high. Put
	// it ON the leading edge and the falloff multiplies it away — which is how
	// the first cut silently dropped the house contrast rule it exists to keep.
	float hb = (off + thickness * 0.30) / max(thickness * hot, 0.0001);
	float heat = clamp(exp(-hb * hb), 0.0, 1.0);
	vec3 col = mix(tint.rgb, vec3(1.0),
		clamp(heat * heat_gain + burn * 0.62, 0.0, 1.0));
	// The core carries a little extra opacity too, so the rim is the BRIGHTEST
	// part of the beat and not merely the whitest. The burn front does the same
	// — a consuming edge is DENSER than what it leaves behind, and without this
	// the erosion multiply above would dim the very pixels it just lit.
	float al = clamp(a * (1.0 + heat * 0.30 + burn * 0.45), 0.0, 1.0)
		* tint.a * fade;
	COLOR = vec4(col, al);
}
"""
	_ring_shader_cache = sh
	return _ring_shader_cache


static func _ring_quad() -> Texture2D:
	# The shader writes COLOR outright, so this texture only has to establish
	# the quad and its UVs — 4x4 opaque white is the whole requirement.
	if _ring_quad_cache != null:
		return _ring_quad_cache
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_ring_quad_cache = ImageTexture.create_from_image(img)
	return _ring_quad_cache


## Build the ring node without animating it. Shared by `ring` (which then tweens
## it and frees it) and `ring_static` (which hands it to a caller that owns its
## lifetime). Returns null when there is nothing to draw.
static func _ring_node(center: Vector2, color: Color,
		opts: Dictionary) -> Sprite2D:
	var radius: float = float(opts.get("radius", 16.0))
	var width: float = float(opts.get("width", 3.0))
	var oval: Vector2 = opts.get("oval", Vector2.ONE)
	var fade_in: float = float(opts.get("fade_in", 0.0))

	# The band's half-width, carried in the shader's front-radius units. The
	# `radius * PAD` denominator is the quad's half-extent in px, so a caller's
	# `width` keeps meaning pixels at scale 1.0.
	var half_px: float = maxf(radius * RING_QUAD_PAD, 1.0)
	var th: float = clampf(maxf(width, 0.5) * RING_BAND_GAIN / half_px,
		RING_BAND_MIN, RING_BAND_MAX)

	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader()
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("front_r", 1.0 / RING_QUAD_PAD)
	mat.set_shader_parameter("thickness", th)
	mat.set_shader_parameter("wake", float(opts.get("wake", 3.2)))
	mat.set_shader_parameter("hot", float(opts.get("hot", 0.55)))
	mat.set_shader_parameter("heat_gain", float(opts.get("heat_gain", 0.92)))
	mat.set_shader_parameter("wobble", float(opts.get("wobble", 0.018)))
	# 0.50 chosen off the sweep in tools/_shot_ring_ab.gd, not by taste: 0 is
	# clean CG, 0.35 and 0.55 both read as crafted, and by 0.75 the filaments
	# turn spiky (a sunburst, not a shock front). Re-shoot the sweep before
	# moving it. Bear in mind these rings are only 30-50px, which is why the
	# harmonics are as coarse as they are — finer reads as dirt at this size.
	mat.set_shader_parameter("grit", float(opts.get("grit", 0.50)))
	# LOST-AND-FOUND defaults ON for moving beats and is left OFF by
	# `ring_static`, whose whole job is to be a STEADY held mark — a
	# standing telegraph that breathes at its edges reads as unstable.
	mat.set_shader_parameter("lost", float(opts.get("lost", 0.38)))
	mat.set_shader_parameter("seed", randf() * TAU)
	mat.set_shader_parameter("fade", 0.0 if fade_in > 0.0 else 1.0)

	var rg := Sprite2D.new()
	rg.texture = _ring_quad()
	rg.material = mat
	rg.z_index = int(opts.get("z_index", 0))
	rg.position = center
	# Sprite2D is centred by default, so the quad is already concentric with
	# `center` the way the Line2D's origin-centred point ring was. The base
	# factor turns the 4px stub texture into the quad's real px extent; the
	# expansion multiplies on top of it.
	var base: Vector2 = oval * (half_px * 2.0 / 4.0)
	rg.scale = base * float(opts.get("start_scale", 0.55))
	# Stashed so the animator can read them back without recomputing.
	rg.set_meta("ring_base", base)
	rg.set_meta("ring_half_px", half_px)
	rg.set_meta("ring_th", th)
	return rg


static func ring(host: Node, center: Vector2, color: Color,
		opts: Dictionary = {}) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var dur: float = float(opts.get("duration", 0.42))
	if opts.get("scale_time", false):
		dur = time(dur)
	var width_end: float = float(opts.get("width_end", 0.0))
	var fade_in: float = float(opts.get("fade_in", 0.0))
	var delay: float = float(opts.get("delay", 0.0))

	var rg := _ring_node(center, color, opts)
	if rg == null:
		return
	host.add_child(rg)
	var base: Vector2 = rg.get_meta("ring_base")
	var half_px: float = rg.get_meta("ring_half_px")
	var th: float = rg.get_meta("ring_th")

	var tw := rg.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	if fade_in > 0.0:
		tw.tween_property(rg, "material:shader_parameter/fade", 1.0, fade_in)
	var sc := tw.tween_property(rg, "scale",
		base * float(opts.get("end_scale", 1.6)), dur).set_ease(Tween.EASE_OUT)
	if opts.has("trans"):
		sc.set_trans(opts["trans"])
	if width_end > 0.0:
		# Honour the caller's thinning intent, but floored: the band must not
		# be allowed to collapse back into the hairline this rebuild removed.
		var th_end: float = maxf(clampf(width_end * RING_BAND_GAIN / half_px,
			RING_BAND_MIN, RING_BAND_MAX), th * 0.45)
		tw.parallel().tween_property(rg,
			"material:shader_parameter/thickness", th_end, dur) \
			.set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(rg, "material:shader_parameter/fade",
		0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(rg.queue_free)


## A ring that is HELD rather than fired: same band, same hot core, no tween and
## no self-free. For standing marks — the always-on lane-forecast reticle — where
## the caller owns the node's lifetime and rebuilds it on its own schedule.
##
## It exists because those marks were hand-rolling their own Line2D circles, the
## exact thing the one-ring-engine rule is for (see the note at
## Card2D._spawn_press_ring). A standing mark wants a TIGHTER read than a blast
## front, so the defaults pull the wake in and drop the wobble: a reticle is
## information and should not look like it is dissipating.
##
## THE HOT CORE IS DELIBERATELY ALMOST OFF HERE. A fired ring goes white at the
## front because a warm ring on a warm table is camouflage; a STANDING mark is
## already legible and its colour carries meaning — the forecast reticle is
## danger RED. Shot at the impact defaults it came out grey, which is the read
## deleted. `heat_gain` keeps a thin bright inner lip and nothing more.
##
## Returns the node (already parented to `host`) or null when headless.
static func ring_static(host: Node, center: Vector2, color: Color,
		opts: Dictionary = {}) -> Sprite2D:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	if DisplayServer.get_name() == "headless":
		return null
	var o := opts.duplicate()
	o["start_scale"] = float(o.get("start_scale", 1.0))
	o["wake"] = float(o.get("wake", 1.35))
	o["hot"] = float(o.get("hot", 0.30))
	o["heat_gain"] = float(o.get("heat_gain", 0.30))
	o["wobble"] = float(o.get("wobble", 0.0))
	# NO GRIT ON A STANDING MARK. Erosion is what stops a fired ring reading as
	# clean CG, but a reticle is INFORMATION: a shredding target mark reads as a
	# rendering fault, and its edge is the thing the player measures against.
	o["grit"] = float(o.get("grit", 0.0))
	# AND NO LOST EDGES, for the same reason one step further. Lost-and-found is
	# a drawing technique for making a form breathe, and a held reticle is the
	# one thing here that must NOT: its edge is what the player measures a
	# target against, so it stays uniform all the way round.
	o["lost"] = float(o.get("lost", 0.0))
	o["fade_in"] = 0.0
	var rg := _ring_node(center, color, o)
	if rg == null:
		return null
	host.add_child(rg)
	return rg


# ── The writ burns (★1 of docs/ANIMATION_COOL_PITCH_20260717.md) ───────
# A card is PARCHMENT, so it doesn't fade out — it CATCHES. The sheet is eaten
# from the bottom upward (embers rise, the same house rule that makes forge
# sparks fall and combat embers climb) behind a ragged frontier: a thin
# ember line at the very edge, a charred band just behind it, untouched paper
# beyond. The existing ash burst then reads as what the card BECAME.
#
# WHY IT CAN BE A SHADER AT ALL: `modulate` is hierarchical but ShaderMaterial
# is not, so shading a LIVE card would mean threading use_parent_material
# through both layout builders (~4.6k lines) — the reason the hit flash is
# still a modulate tint. The dodge: a battlefield token's body is already ONE
# baked TextureRect (CardTextureCache.get_battlefield_texture), so the burn
# runs on that single CanvasItem. Death is the free case: the card is leaving,
# so nothing needs to stay live underneath.
#
# The noise is layered at three scales — the ink-wipe's idiom, and what the
# Godot dissolve practice recommends — so the frontier tears like paper fibre
# instead of sweeping like a wipe. `seed` decorrelates neighbouring deaths.
const BURN_CODE := "
shader_type canvas_item;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform vec3 ember_hot : source_color = vec3(1.0, 0.92, 0.55);
uniform vec3 ember_cool : source_color = vec3(1.0, 0.36, 0.07);
uniform float seed = 0.0;
// 1 = CONSUME: burnt pixels are discarded and the thing is gone (★1 — a card
// dying, where a hole is the whole point). 0 = CHAR IN PLACE: burnt pixels go
// to soot but the surface stays, for a panel that is scorched and still there
// (★7 — the hero portrait). Defaults to 1 so ★1 is untouched.
uniform float consume = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec2 p = UV + vec2(seed, seed * 0.7);
	float n = vnoise(p * 6.0) * 0.55 + vnoise(p * 17.0) * 0.30
		+ vnoise(p * 41.0) * 0.15;
	// field ~0 at the bottom edge, ~1 at the top: the sheet catches from below
	// and climbs. The noise term is what makes the frontier ragged.
	float field = (1.0 - UV.y) * 0.62 + n * 0.38;
	// Starts BELOW the minimum field so burn = 0 shows no char at all, and ends
	// just past the maximum so burn = 1 leaves nothing behind. CALIBRATED to the
	// field's REAL range (~0.1–0.9, since the noise term averages ~0.5 rather
	// than spanning 0–1), not its theoretical one: the first cut swept t to 1.30
	// and the sheet was gone by burn ≈ 0.72, wasting the tween's last third as
	// dead air. Verified with tools/_shot_card_burn.
	float t = burn * 1.10 - 0.12;
	float e = field - t;
	if (e < 0.0) {
		if (consume > 0.5) {
			discard;
		}
		// Burnt through but still standing: soot, not a hole.
		COLOR = vec4(vec3(0.05, 0.035, 0.03), tex.a);
	} else {
		vec3 col = tex.rgb;
		float charF = 1.0 - smoothstep(0.0, 0.10, e);
		col = mix(col, vec3(0.07, 0.05, 0.04), charF * 0.92);
		float emberF = 1.0 - smoothstep(0.0, 0.045, e);
		vec3 emb = mix(ember_cool, ember_hot, 1.0 - smoothstep(0.0, 0.025, e));
		col = mix(col, emb, emberF);
		COLOR = vec4(col, tex.a);
	}
}
"
static var _burn_shader: Shader = null


# ── Ink shock (★4) ─────────────────────────────────────────────────────
# The struck-card flash. `modulate` CANNOT do this: it multiplies, so the only
# way it can fake "red" is by darkening green and blue — which is what the old
# hit flash did (`base.r * 1.8, base.g * 0.5, base.b * 0.45`), and why a struck
# card went muddy instead of hot. A shader mixes TOWARD a colour, so the sheet
# actually flashes. Alpha is preserved, so the deckled edge stays honest.
const FLASH_CODE := "
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.94, 0.86);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex.rgb, flash_color, flash), tex.a);
}
"
static var _flash_shader: Shader = null


# ── Gilt catches the light (★2) ────────────────────────────────────────
# A rare's frame is GOLD LEAF ON SKIN, so it shouldn't shimmer by itself — it
# should catch a raking light when the card MOVES. That's the whole argument
# against a rainbow holo here: holo is plastic, and this game is a document.
# The sweep is therefore driven by the card's live tilt (C1's lean/hover
# driver), not by a clock — which is also why it costs no _process of its own:
# the only time the highlight needs to move is the only time the lean is armed.
#
# The gilt MASK is derived from the baked pixels rather than a painted channel:
# gold is the warm, mid-bright band (high red, low blue). That's cheap and it
# tracks the art automatically, at the cost of catching a few warm highlights
# in the painting itself — acceptable, since those are lit surfaces too.
const GILT_CODE := "
shader_type canvas_item;
uniform float tilt = 0.0;      // the card's live rotation, radians
uniform float strength = 1.0;  // 0 = no foil (commons never call this)
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float warm = tex.r - tex.b;
	// A BAND-PASS, not a threshold. The first cut used smoothstep(0.10, 0.32,
	// warm) and washed the whole rules box: parchment is warm too (r-b ~ 0.21)
	// so it scored ~0.5 and took half the shine, which made a rare read merely
	// BRIGHT instead of gilded. Leaf is far warmer (~0.57) but DARKER than the
	// page (lum ~0.70 vs ~0.85), so the discriminator has to be a warmth floor
	// plus a brightness CEILING — gold is never near-white.
	float gilt = smoothstep(0.28, 0.48, warm)
		* smoothstep(0.22, 0.42, lum)
		* (1.0 - smoothstep(0.74, 0.96, lum));
	// A diagonal band raking across the sheet, swept by the tilt.
	float band = UV.x + UV.y * 0.35;
	float pos = 0.5 + tilt * 1.7;
	float shine = exp(-pow((band - pos) * 3.0, 2.0));
	vec3 col = tex.rgb + vec3(1.0, 0.88, 0.55) * gilt * shine * strength * 0.85;
	COLOR = vec4(col, tex.a);
}
"
static var _gilt_shader: Shader = null


static func gilt_material(strength: float = 1.0) -> ShaderMaterial:
	if _gilt_shader == null:
		_gilt_shader = Shader.new()
		_gilt_shader.code = GILT_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _gilt_shader
	mat.set_shader_parameter("tilt", 0.0)
	mat.set_shader_parameter("strength", strength)
	return mat


static func flash_material(color: Color = Color(1.0, 0.94, 0.86)) -> ShaderMaterial:
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _flash_shader
	mat.set_shader_parameter("flash", 0.0)
	mat.set_shader_parameter("flash_color", color)
	return mat


static func burn_material(ember_hot: Color = Color(1.0, 0.92, 0.55),
		ember_cool: Color = Color(1.0, 0.36, 0.07)) -> ShaderMaterial:
	# One shared Shader resource, a fresh material per card (each carries its own
	# `burn` progress and `seed`, so two cards dying together don't burn in
	# lockstep).
	if _burn_shader == null:
		_burn_shader = Shader.new()
		_burn_shader.code = BURN_CODE
	var mat := ShaderMaterial.new()
	mat.shader = _burn_shader
	mat.set_shader_parameter("burn", 0.0)
	mat.set_shader_parameter("seed", randf() * 10.0)
	mat.set_shader_parameter("ember_hot", ember_hot)
	mat.set_shader_parameter("ember_cool", ember_cool)
	return mat


static func burn_away(item: CanvasItem, dur: float,
		ember_hot: Color = Color(1.0, 0.92, 0.55),
		ember_cool: Color = Color(1.0, 0.36, 0.07)) -> Tween:
	# Set `item` alight and consume it over `dur` seconds. Returns the tween so
	# the caller can chain its own exit (the card frees itself when the sheet is
	# gone). Returns null when the burn can't run — headless, or a dead node —
	# so callers can fall back to their old flourish.
	if item == null or not is_instance_valid(item) or not item.is_inside_tree():
		return null
	if DisplayServer.get_name() == "headless":
		return null
	var mat := burn_material(ember_hot, ember_cool)
	item.material = mat
	var tw := item.create_tween()
	tw.tween_method(func(v: float):
		if is_instance_valid(mat):
			mat.set_shader_parameter("burn", v),
		0.0, 1.0, maxf(dur, 0.01)).set_ease(Tween.EASE_IN_OUT)
	return tw


# ── The writ turns (★5) ────────────────────────────────────────────────
# The flip: the most iconic beat in the medium, done the way card games
# actually do it — as TWO HALVES of different nodes in the same place. A back
# closes (scale.x → 0), a face opens (0 → 1), and the eye reads one card
# turning over. There is no single node that is both, so there is no honest way
# to do it as one tween: the face-down ghost and the real card are different
# objects by construction.
#
# Squeeze only the X axis: a turning card foreshortens, it doesn't shrink.
# Both halves are DECORATIVE (the reveal's information is the card that ends up
# on the board), so Reduce Motion snaps them to their end state.


static func flip_out(ctrl: Control, dur: float = 0.13) -> void:
	# The back closes. Frees the node when it's edge-on — pair it with flip_in
	# so the face opens out of the same edge.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		ctrl.queue_free()
		return
	ctrl.pivot_offset = ctrl.size * 0.5
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "scale:x", 0.0, time(dur)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(ctrl.queue_free)


static func flip_in(ctrl: Control, delay: float = 0.0, dur: float = 0.16) -> void:
	# The face opens. Starts edge-on and swings out with a BACK overshoot — the
	# house settle, and the thing that makes it land like a card slapped down
	# rather than a sprite scaling up.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var rest_x: float = ctrl.scale.x
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.scale.x = 0.0
	var tw := ctrl.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(ctrl, "scale:x", rest_x, time(dur)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ── The PLAYED card's turn (★5's other half, 2026-08-03) ───────────────
# flip_out/flip_in above are two nodes standing in for one card, which is the
# only honest shape for a REVEAL. A card being PLAYED is the opposite case: it
# is one node the whole way, so it cannot use either verb — flip_in creates its
# own tween, and a second tween on `scale` during the flight is exactly the
# two-writers bug this kit exists to prevent. What it needs instead is a NUMBER,
# so Combat's one flight tween can carry the turn as part of the pose it was
# already writing.
#
# The turn is split across the gesture's two existing beats rather than stacked
# on either: the FLIGHT closes the writ (rest → foreshortened) and the WAX PRESS
# opens it flat (foreshortened → the squash → rest). That is why the press does
# not need a companion verb here — `play_wax_press` interpolates from whatever
# pose the card lands in, so a card that arrives turned is opened out by the
# press for free, and the seal biting the board IS the second half.
#
# DEPTH SCALES WITH REACH, it is not gated on it. Combat's flight already
# derives its apex, its hang time, its shrink and its spin from one `reach`
# (travel / ARC_FULL_TRAVEL) so a near-slot seat can never pick up a long deal's
# motion; the turn obeys the same rule for the same reason. It also settles the
# arithmetic that would otherwise sink this: a player's own drop is a ~0.13 s
# seat, and a 90° turn crammed into 0.13 s reads as a glitch, not a turn. At
# reach 0 the card only TIPS — cos(45°) of its face width, about as much
# foreshortening as setting a stiff card down on one edge. Full edge-on is
# reserved for the long deals (an enemy line dealt from off the board) that have
# 0.3 s+ to spend on it.
const TURN_FACE_NEAR: float = 0.707   # cos 45° — a seat leans
const TURN_FACE_FAR: float = 0.0      # cos 90° — a deal turns edge-on


## The face-width fraction a card in flight should foreshorten to, for a flight
## of `reach` (0 = seated on the spot, 1 = dealt from off the board). Multiply a
## rest scale's X by this; never write `scale` twice to apply it.
static func turn_face(reach: float) -> float:
	return lerpf(TURN_FACE_NEAR, TURN_FACE_FAR, clampf(reach, 0.0, 1.0))


# ── The shared motion kit (2026-07-11 pass; extracted from GameTheme, R6) ──
# Screen-agnostic entrance/choice motion for the shell screens (Reward, Shop,
# Treasure, Wayside, Recruit, map HUD). deal_in / hover_lift / claim_pop
# animate modulate + scale ONLY — never position or size — so container
# layout is untouched. Everything gates on Reduce Motion. Shell call sites
# reach these through GameTheme's same-name delegators; either spelling is
# fine, new code may call Motion.* directly.


## The letterpress strike: a headline PRESSES onto the page rather than fading
## in. Type starts oversized and pale, drives down onto the sheet, overshoots a
## hair, and settles — the plate biting the parchment. Landing carries a short
## ink bloom (the title flashes toward its own bright ink, then dries back) so
## the word reads as pigment soaking in rather than a UI element appearing.
##
## Decorative: Reduce Motion snaps to the final state (title still lands, just
## instantly), per the animation contract.
##
## `shake` optionally adds a small trauma impulse at the moment of impact — use
## it for a screen's ONE hero headline, never for a column of them.
static func stamp_in(lbl: Control, delay: float = 0.0, bloom: Color = Color(1.0, 0.90, 0.52),
		shake: bool = false) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		lbl.scale = Vector2.ONE
		lbl.modulate.a = 1.0
		return
	var rest_color: Color = lbl.get_theme_color("font_color")
	# Pivot must be read AFTER layout: a freshly built Label still has size 0, so
	# computing it now centres the press on the top-left corner and the headline
	# grows out of its own left edge. Defer the read, not just the assignment.
	#
	# THE CAPTURE MUST BE A WEAKREF, NOT THE NODE (2026-08-25). A deferred lambda
	# is marshalled BEFORE its body runs, so `is_instance_valid(lbl)` inside can
	# never save it — if the label died between the queue and the flush, Godot
	# aborts with `Lambda capture at index 0 was freed`. Every shell screen takes
	# its headline through GameTheme.make_screen_title, and a freshly built Label
	# is always size ZERO, so this deferred path fires on EVERY screen build; a
	# screen torn down inside the frame that built it printed one error each
	# (~135 per run of tools/_probe_flow, which builds and frees the whole
	# non-combat flow in a single frame).
	var lbl_ref: WeakRef = weakref(lbl)
	var centre_pivot := func() -> void:
		var l := lbl_ref.get_ref() as Control
		if l != null:
			l.pivot_offset = l.size * 0.5
	if lbl.size == Vector2.ZERO:
		centre_pivot.call_deferred()
	else:
		centre_pivot.call()
	lbl.scale = Vector2(1.14, 1.14)
	lbl.modulate.a = 0.0
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	# The strike — fast, and it overshoots slightly under the plate's weight.
	tw.tween_property(lbl, "scale", Vector2.ONE, time(0.26)).set_delay(delay) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 1.0, time(0.14)).set_delay(delay)
	# The ink bloom, dried back over a longer beat than the strike itself.
	if lbl is Label or lbl is RichTextLabel:
		var key := "font_color" if lbl is Label else "default_color"
		tw.tween_method(func(c: Color):
				lbl.add_theme_color_override(key, c),
			bloom, rest_color, time(0.46)).set_delay(delay + time(0.16))
	if shake and GameTheme != null and GameTheme.has_method("add_trauma"):
		tw.tween_callback(func(): GameTheme.add_trauma(0.11)) \
			.set_delay(delay + time(0.20))


static func pulse_label(lbl: Label, flash_color: Color = Color(1.0, 0.85, 0.30)) -> void:
	# One-shot color-flash + scale punch on a label. Used by Shop / Rest / Reward
	# to give gold and HP labels feedback when they change.
	if lbl == null or not is_instance_valid(lbl):
		return
	var rest_color: Color = lbl.get_theme_color("font_color")
	var rest_scale := lbl.scale
	lbl.pivot_offset = lbl.size * 0.5
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", rest_scale * 1.20, 0.10) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(c: Color):
			lbl.add_theme_color_override("font_color", c),
		flash_color, rest_color, 0.32)
	tw.chain().tween_property(lbl, "scale", rest_scale, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func deal_in(ctrl: Control, delay: float = 0.0) -> void:
	# Entrance: the tile rises into place with a soft back-settle. Stagger the
	# delay across a row so offers land like dealt cards, not a wall.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	ctrl.modulate.a = 0.0
	ctrl.scale = Vector2(0.92, 0.92)
	var tw := ctrl.create_tween()
	tw.tween_interval(maxf(delay, 0.001))
	# Pivot can only be centred once the container has sized the tile.
	tw.tween_callback(func():
		if is_instance_valid(ctrl):
			ctrl.pivot_offset = ctrl.size * 0.5)
	tw.tween_property(ctrl, "modulate:a", 1.0, 0.22).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ctrl, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## ── The deal (2026-09-10) ─────────────────────────────────────────────
## WHY EVERY CARD IN THIS GAME ARRIVED LIKE A UI PANEL: `deal_in` and
## `card_reveal` animate ALPHA and SCALE, and the kit says so in its own header —
## "modulate + scale ONLY, never position or size, so container layout is
## untouched". That constraint is real (these tiles live in containers) but its
## consequence had never been priced: **alpha and scale are the two properties a
## physical object never changes.** A card does not fade up from nothing and it
## does not grow from 60% — it TRAVELS, it TURNS OVER, and it LANDS. Fading is
## the idiom for "a UI element appeared"; every card game worth copying uses the
## idiom for "an object arrived".
##
## The container constraint is honoured rather than broken. A tile in a container
## owns its `position`, but its CHILD does not — and every card slate in this
## codebase already builds exactly that shape (a `card_wrap` sized by the row,
## holding the Card2D). So the wrapper stays put and the FACE flies.
##
## Four things carry it, and the third is the one that sells physicality:
##   · TRAVEL along a bowed path — a dealt card arcs, it does not lerp.
##   · A TURN. `scale.x` runs from near-edge-on to full, so the card is turning
##     face-up as it lands. `turn_face` already existed for exactly this and had
##     one caller.
##   · A SHADOW THAT KNOWS THE HEIGHT. Wide, pale and offset while the card is in
##     the air; tight, dark and directly under it on contact. This is the cheapest
##     3D cue in 2D and nothing else in the kit was doing it.
##   · A LANDING. Overshoot, a squash on contact, and the rotation settling past
##     zero and back.
##
## And NO ALPHA TWEEN anywhere in it. A card is opaque.
##
## `opts`: face (Control, default the wrapper's first Control child) · from
## (Vector2 offset it flies in from) · spin (radians) · dur · bow (perpendicular
## bow as a fraction of the run) · settle (bool, landing squash).
static func deal_card(wrapper: Control, delay: float = 0.0,
		opts: Dictionary = {}) -> void:
	if wrapper == null or not is_instance_valid(wrapper):
		return
	var face: Control = opts.get("face", null)
	if face == null:
		for ch in wrapper.get_children():
			if ch is Control:
				face = ch
				break
	if face == null or not is_instance_valid(face):
		return
	var rest_scale: Vector2 = face.scale
	if UserSettings != null and UserSettings.reduce_motion:
		# Settled, not skipped: the card must still be there, just already dealt.
		# Position is NOT written here — under Reduce Motion nothing ever moved it,
		# and on a container child (see below) the resting position is the
		# container's to decide, not zero.
		face.modulate.a = 1.0
		face.rotation = 0.0
		face.scale = rest_scale
		wrapper.set_meta("deal_lift", 0.0)
		wrapper.set_meta("deal_off", Vector2.ZERO)
		return
	var from: Vector2 = opts.get("from", Vector2(-110.0, 330.0))
	var spin: float = float(opts.get("spin", 0.40))
	var dur: float = float(opts.get("dur", 0.42))
	var bow_k: float = float(opts.get("bow", 0.28))
	# The bow is PERPENDICULAR to the flight and a FRACTION of its length, so a
	# short hop and a long throw curve alike — the ratio rule, same as everywhere.
	var run: float = from.length()
	var bow: Vector2 = from.normalized().orthogonal() * run * bow_k
	# Foreshortened at the throw, NOT edge-on. turn_face(1.0) is a true zero (an
	# invisible card) and 0.86 gives ~10% width, which photographs as a coloured
	# STICK rather than a card seen at an angle — the eye needs enough of the face
	# to know what is turning. ~27% is the shallowest that still reads as a card.
	var face_w0: float = float(opts.get("turn_from", turn_face(0.62)))
	# THE FLIGHT IS RELATIVE TO WHEREVER THE FACE RESTS, not to zero — which is
	# what lets this work on a CONTAINER CHILD as well as on a wrapper's child.
	# A wrapper's child rests at (0,0) and nothing changes for the card slates;
	# a relic tile in an HBox rests whereever the row put it, and flying it to
	# (0,0) would stack every tile on the row's left edge.
	#
	# The rest position is read at TAKE-OFF, not here, and that matters: a screen
	# that equalises its tile heights (Reward does, by writing
	# `custom_minimum_size` after the row is built) re-sorts the container on the
	# frame after this call, so a position captured now is stale by the time the
	# card actually moves.
	#
	# Held invisible until take-off for the same reason — with no rest position
	# known there is nowhere correct to park it, and a card sitting visibly in its
	# throw pose through its stagger delay is a card that has not been dealt yet.
	#
	# `modulate.a`, NOT `visible`. **A CONTAINER SKIPS HIDDEN CHILDREN WHEN IT
	# SORTS**, so hiding a relic tile took it out of its row's layout entirely:
	# it was never given a slot, `rest_hold` read the unsorted (0,0), and both
	# tiles landed stacked on the row's left edge. Caught by the settled shot and
	# by nothing else — a mid-flight frame looks identical either way.
	#
	# This is a hard on/off with no tween, so it is not the alpha ramp this whole
	# verb exists to remove; the card is absent, and then it is thrown.
	var rest_hold: Array = [Vector2.ZERO]
	face.modulate.a = 0.0
	wrapper.set_meta("deal_lift", 1.0)

	# Typed, not inferred: `weakref()` is declared Variant, so `:=` infers Variant
	# and this project promotes that warning to an error.
	var wref: WeakRef = weakref(wrapper)
	var fref: WeakRef = weakref(face)
	# A plain Array, not a Vector2 local: GDScript lambdas capture BY VALUE, so a
	# captured Vector2 written in the take-off callback would not be visible to
	# the flight. Array is a reference type and is shared.
	var take_off := func() -> void:
		var f: Control = fref.get_ref()
		if f == null:
			return
		rest_hold[0] = f.position
		f.pivot_offset = f.size * 0.5
		f.position = rest_hold[0] + from
		f.rotation = spin
		f.scale = Vector2(rest_scale.x * face_w0, rest_scale.y)
		f.modulate.a = 1.0
	# ONE parametric flight rather than four racing tweeners. The shadow has to
	# stay locked to the card's height every frame, and a `tween_method` is the
	# only shape that gives a per-frame hook to redraw the wrapper from.
	var fly := func(t: float) -> void:
		var w: Control = wref.get_ref()
		var f: Control = fref.get_ref()
		if w == null or f == null:
			return
		# Cubic-out: a dealt card leaves the hand fast and coasts into its slot.
		var e: float = 1.0 - pow(1.0 - t, 3.0)
		var carry: Vector2 = from.lerp(Vector2.ZERO, e) + bow * sin(e * PI)
		f.position = rest_hold[0] + carry
		# Settles PAST zero and back, so the card rocks level instead of easing
		# to a stop — the same reason a landing gets an overshoot.
		f.rotation = spin * (1.0 - e) - 0.055 * sin(e * PI)
		var turn: float = clampf(e * 1.3, 0.0, 1.0)
		f.scale = Vector2(rest_scale.x * lerpf(face_w0, 1.0, turn), rest_scale.y)
		w.set_meta("deal_lift", 1.0 - e)
		# The card's offset FROM ITS SLOT — not its position, which on a container
		# child includes the slot itself and would throw the shadow across the row.
		w.set_meta("deal_off", carry)
		w.queue_redraw()
	var tw := wrapper.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(take_off)
	tw.tween_method(fly, 0.0, 1.0, dur)
	if bool(opts.get("settle", true)):
		# CONTACT. A squash snapped on with no travel time — a squash you can
		# watch arrive is a wobble (the writ_amend lesson) — then released.
		tw.tween_callback(func():
			var f: Control = fref.get_ref()
			if f != null:
				f.scale = Vector2(rest_scale.x * 1.045, rest_scale.y * 0.93))
		tw.tween_property(face, "scale", rest_scale, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		var w: Control = wref.get_ref()
		if w != null:
			w.set_meta("deal_lift", 0.0)
			w.set_meta("deal_off", Vector2.ZERO)
			w.queue_redraw())


## AN ITEM IS SET DOWN, NOT DEALT.
##
## Same machinery, different physics, because they are different events. A card
## is thrown across a table by a dealer: it travels far, arcs, and TURNS OVER
## because it left the hand face-down. A relic is spoils being put on the table
## in front of you — it drops a short way, straight, already face-up, and lands
## heavier than a card does. Giving the spoils row the card's deal made three
## plaques skate in sideways like playing cards, which is the wrong story.
##
## So: a short steep fall, almost no bow, a fraction of the card's spin, and NO
## TURN AT ALL (`turn_from` 1.0 — the thing is not flipping, and foreshortening a
## framed plaque just squashes it). The landing squash from `deal_card` is what
## carries the weight.
##
## `tile` is both the wrapper and the face here: these live directly in a row
## rather than in a `card_wrap`, and `deal_card` reads the resting position at
## take-off so a container child is fine.
static func drop_item(tile: Control, delay: float = 0.0,
		opts: Dictionary = {}) -> void:
	if tile == null or not is_instance_valid(tile):
		return
	var o := {
		"face": tile,
		"from": Vector2(0.0, -104.0),
		"spin": 0.10,
		"dur": 0.30,
		"bow": 0.06,
		"turn_from": 1.0,
	}
	for k in opts:
		o[k] = opts[k]
	deal_card(tile, delay, o)


## The contact shadow under a card, and it KNOWS HOW HIGH THE CARD IS.
##
## `lift` is the value `deal_card` writes to the wrapper's `deal_lift` meta: 0 is
## resting on the table, 1 is at the top of its flight. Read it in the host's
## `_draw` and the shadow does the rest.
##
## ONE TEXTURED DRAW, not a stack of ellipses. Every hand-rolled shadow in this
## codebase was three or four `draw_circle` passes at descending size "to fake
## the blur", which is the same hand-rolled-gradient defect as the map's lamplight
## — a flat primitive has uniform opacity, so stacking them leaves visible steps.
## `particle_tex` paints the falloff, and its slightly lopsided silhouette is a
## better shadow than a perfect ellipse anyway.
## `carry` is where the CARD is relative to its resting slot — pass the same
## offset the flight is applying (`deal_off`). Without it the shadow sits at the
## landing spot while the card is still across the screen, which is not a shadow,
## it is a target marker: the first cut did exactly that and the card read as
## floating free of the table entirely.
##
## The carry is DAMPED, and unequally on the two axes. A light roughly overhead
## and a little to one side puts the shadow almost under the card horizontally
## but much less displaced vertically, because vertical screen distance on a
## flat-laid card is mostly DEPTH, not height. Tracking it 1:1 on both axes makes
## the shadow look welded to the card and kills the separation the whole cue is
## for.
static func card_shadow(host: CanvasItem, foot: Vector2, lift: float = 0.0,
		span: float = 96.0, carry: Vector2 = Vector2.ZERO) -> void:
	if host == null or not is_instance_valid(host):
		return
	var l: float = clampf(lift, 0.0, 1.0)
	# Higher card: wider, softer, paler, and thrown further from the foot —
	# all four move together or the cue does not read.
	var w: float = span * (1.0 + 0.80 * l)
	var h: float = w * 0.145
	var a: float = lerpf(0.32, 0.09, l)
	var off := Vector2(carry.x * 0.86 - 16.0 * l, carry.y * 0.30 + 12.0 * l)
	host.draw_texture_rect(particle_tex("fleck"),
		Rect2(foot + off - Vector2(w * 0.5, h * 0.5), Vector2(w, h)),
		false, Color(0.0, 0.0, 0.0, a))


static func hover_lift(btn: Control, lift: float = 1.03, target: Control = null,
		raise_z: bool = false) -> void:
	# A small scale lift on hover — the stylebox swap says "interactive", the
	# lift says "pick me up". Scale only, so row layout never reflows.
	# `target` is the node that visually lifts (defaults to btn itself) — for
	# invisible click-catchers layered over a card wrapper. `raise_z` pops the
	# target above its row while hovered (grids where neighbors overlap).
	if btn == null or not is_instance_valid(btn):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var tgt: Control = target if target != null else btn
	btn.mouse_entered.connect(func():
		if not is_instance_valid(tgt):
			return
		if raise_z:
			tgt.z_index = 1
		tgt.pivot_offset = tgt.size * 0.5
		var tw := tgt.create_tween()
		tw.tween_property(tgt, "scale", Vector2(lift, lift), 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	btn.mouse_exited.connect(func():
		if not is_instance_valid(tgt):
			return
		if raise_z:
			tgt.z_index = 0
		var tw := tgt.create_tween()
		tw.tween_property(tgt, "scale", Vector2.ONE, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))


static func punch(ctrl: Control, amount: float = 1.08) -> void:
	# The house impact verb (Balatro's juice_up equivalent): a QUAD-out scale
	# punch that BACK-out settles to rest. Keyed kill-before-restart — repeat
	# impacts re-punch cleanly instead of stacking tweens. Settles to scale
	# ONE (shell-tile convention); battlefield cards keep their own
	# lunge/recoil kit in Card2D.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	ctrl.pivot_offset = ctrl.size * 0.5
	if ctrl.has_meta("_motion_punch"):
		var old = ctrl.get_meta("_motion_punch")
		if old is Tween and old.is_valid():
			old.kill()
	var tw := ctrl.create_tween()
	ctrl.set_meta("_motion_punch", tw)
	tw.tween_property(ctrl, "scale", Vector2(amount, amount), PUNCH) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", Vector2.ONE, SETTLE) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func press(ctrl: Control, spread: float = 1.07, dip: float = 0.88,
		on_bite: Callable = Callable(), flat: bool = false) -> void:
	# THE PRESS — the stamp beat, and the counterpart to `punch` (2026-08-04,
	# ✦1 of docs/CARD_PLAY_COOL_HUNT_20260803.md). `punch` grows a tile UNIFORMLY
	# and settles to Vector2.ONE; a seal does neither. Wax takes a die by
	# SPREADING sideways as it dips, and it must settle back onto whatever rest
	# pose the instrument already had — an impact that renormalises a HUD
	# instrument to 1.0 would resize it out from under its own layout.
	#
	# `on_bite` fires at the deepest point, which is the frame the impression
	# exists. It is a parameter rather than a caller-side timer for the same
	# reason Card2D.play_wax_press takes `bite`: a second copy of a duration has
	# to be kept in step by comment, and eventually isn't.
	#
	# `flat` is the press that DOESN'T take — home on a SINE with no overshoot
	# and (by the caller's choice) nothing drawn at the bite, so the same verb
	# succeeding and failing are told apart by whether the wax RINGS and springs
	# (Combat's ✦7b refused Command press).
	#
	# THE PIVOT IS THE CALLER'S. A seal is pressed about the WAX, not about the
	# centre of whatever rect happens to hold it, so this never writes
	# `pivot_offset` — which is precisely the thing that makes `punch` unusable
	# for an off-centre instrument.
	#
	# Keyed kill-before-restart against a REMEMBERED rest: a two-cast turn lands
	# two of these inside one beat, and reading `.scale` mid-dip would adopt the
	# squash as rest and walk the instrument down the screen. Same device
	# `punch` and Combat._pulse_mana_label already pay for.
	#
	# Durations ride time() — the two instruments that press (the board and the
	# Command seal beside it) are both combat-visible, so at Instant the stamp
	# collapses with the rest of the clash instead of outliving it.
	#
	# DECORATIVE: an impact is never the information. Reduce Motion declines,
	# and the caller's `on_bite` never fires — a bare ring with no press under
	# it is a flourish, not a state readout.
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_inside_tree():
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var rest: Vector2 = ctrl.get_meta("_motion_press_rest", ctrl.scale)
	ctrl.set_meta("_motion_press_rest", rest)
	if ctrl.has_meta("_motion_press"):
		var old = ctrl.get_meta("_motion_press")
		if old is Tween and old.is_valid():
			old.kill()
	ctrl.scale = rest
	var tw := ctrl.create_tween()
	ctrl.set_meta("_motion_press", tw)
	tw.tween_property(ctrl, "scale", Vector2(rest.x * spread, rest.y * dip),
		time(PUNCH * 0.7)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if on_bite.is_valid():
		tw.tween_callback(on_bite)
	if flat:
		tw.tween_property(ctrl, "scale", rest, time(SETTLE_SLOW)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(ctrl, "scale", rest, time(SETTLE)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func fade_exit(ctrl: Control, dur: float = EXIT) -> void:
	# The house exit: EASE_IN alpha-out for content leaving the page (unpicked
	# offers, dismissed sheets). Decorative — Reduce Motion snaps it invisible.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		ctrl.modulate.a = 0.0
		return
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)


static func claim_pop(ctrl: Control) -> void:
	# The chosen tile flares bright and punches up, then settles — a pick
	# reads as a physical grab (Combat's _punch_label language, tile-sized).
	# The scale beat IS the punch verb; the gilt flare rides it in parallel.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	punch(ctrl, 1.08)
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "self_modulate", Color(1.35, 1.28, 1.05), PUNCH)
	tw.tween_property(ctrl, "self_modulate", Color.WHITE, SETTLE)


static func pocket_away(ctrl: Control, to_global: Vector2, dur: float = 0.32) -> void:
	# The bought/claimed tile detaches from its container and dives toward a
	# destination point (the player's pack, the merchant's counter), shrinking
	# and fading on the way. Awaitable — callers rebuild their UI after it
	# lands. Reduce Motion collapses it to an instant return.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var gp := ctrl.global_position
	ctrl.top_level = true
	ctrl.global_position = gp
	ctrl.z_index = 220
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "scale", ctrl.scale * 1.06, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "global_position", to_global - ctrl.size * 0.5, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ctrl, "scale", Vector2(0.35, 0.35), dur) \
		.set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ctrl, "modulate:a", 0.0, dur) \
		.set_ease(Tween.EASE_IN)
	await tw.finished


static func tick_number(lbl: Label, from_val: int, to_val: int,
		template: String = "%d", dur: float = 0.5) -> void:
	# Rolls a numeric label from one value to another (gold counters, HP).
	# Pairs with pulse_label for the change-flash; Reduce Motion snaps.
	if lbl == null or not is_instance_valid(lbl):
		return
	if from_val == to_val or (UserSettings != null and UserSettings.reduce_motion):
		lbl.text = template % to_val
		return
	var tw := lbl.create_tween()
	# EASED, NOT LINEAR. A counter climbing at a constant rate is the temporal
	# twin of a flat stroke: nothing in the world changes at a fixed rate, and
	# the eye reads the uniformity instantly as "a machine moved this". QUAD-out
	# puts most of the travel in the first third, so the number LEAPS and then
	# settles onto its answer — which also makes the final value the part that
	# lingers, rather than one more frame of a ramp.
	#
	# DELIBERATELY NOT A SLOT-REEL. The obvious upgrade from the juice
	# literature is Balatro's staggered digit roll, and it is the wrong borrow:
	# that reel works because the number IS the game — vast, dramatic, and the
	# only thing on screen. These are gold and HP, which are INFORMATIONAL, and
	# a reel hides exactly the intermediate values a count-up exists to show.
	# Clarity before spectacle is the house rule and it applies to its own
	# influences too.
	tw.tween_method(func(v: float):
		if is_instance_valid(lbl):
			lbl.text = template % int(round(v)),
		float(from_val), float(to_val), dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse_label(lbl, Color(1.0, 0.85, 0.30) if to_val > from_val \
		else Color(1.0, 0.45, 0.20))


static func write_on(rich_label, delay: float = 0.10) -> void:
	# Quick typewriter for page prose (the writ writes itself in): reveal time
	# scales with length, clamped so long letters never drag. Works on Label
	# or RichTextLabel (anything with visible_ratio). Promoted from Event.gd
	# (R4) — Reduce Motion shows the text whole.
	if rich_label == null or not is_instance_valid(rich_label):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	rich_label.visible_ratio = 0.0
	var reveal: float = clampf(
		rich_label.get_total_character_count() * 0.0032, 0.25, 0.9)
	var tw: Tween = rich_label.create_tween()
	tw.tween_property(rich_label, "visible_ratio", 1.0, reveal).set_delay(delay)


static func ken_burns(art: Control, pivot: Vector2, amount: float = 1.035,
		period: float = 16.0) -> void:
	# The plate breathes: a slow scale-only drift from `pivot`, looping forever
	# (KEEP_ASPECT_COVERED stretch keeps every edge bled while it moves).
	# Promoted from Event.gd (R4). Decorative — Reduce Motion holds it still.
	if art == null or not is_instance_valid(art):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	art.pivot_offset = pivot
	var tw := art.create_tween().set_loops()
	tw.tween_property(art, "scale", Vector2(amount, amount), period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(art, "scale", Vector2.ONE, period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func card_reveal(card: Control, delay: float, rarity: String = "",
		companion: Control = null) -> void:
	# The dealt-card entrance every card slate shares (Recruit + NetDraft used
	# to keep twin copies of this; same beat as Reward's spoils): fan in from
	# small with a BACK-out settle, then the rarity shine if the pull earned
	# one. `companion` (a PICK button riding the card) fades in just after the
	# card lands. Reduce Motion deals everything settled.
	if card == null or not is_instance_valid(card):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		if companion != null and is_instance_valid(companion):
			companion.modulate.a = 1.0
		return
	card.modulate.a = 0.0
	card.scale = Vector2(0.6, 0.6)
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.26).set_delay(delay)
	tw.tween_property(card, "scale", Vector2.ONE, SETTLE_SLOW) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	if companion != null and is_instance_valid(companion):
		companion.modulate.a = 0.0
		tw.tween_property(companion, "modulate:a", 1.0, 0.20) \
			.set_delay(delay + 0.14)
	rarity_reveal(card, rarity, delay + 0.34)


# ── The impact kit (2026-08-28) ────────────────────────────────────────
# Three primitives lifted out of writ_amend so every card moment in the game can
# speak the same language. They are the standard game-feel vocabulary, not
# invention: the over-exposed impact frame from hand-drawn action animation, the
# fast/slow ring pair, and the Balatro-foil specular sweep. Each gates headless
# itself; REDUCE MOTION is the caller's call, because all three are decorative
# and the callers already branch on it.

## Two frames of the target blown to near-white. The cheapest juice in the kit:
## the eye reads a single over-exposed frame as force. `squash` must match
## whatever squash the caller is applying to the target — the flash is sized and
## centred from it, and laid on the target's RESTING rect instead its own hard
## corners stick out past the card.
static func impact_frame(host: Control, target: Control,
		squash: Vector2 = Vector2.ONE,
		tint: Color = Color(1.0, 0.98, 0.92, 0.82)) -> void:
	if host == null or target == null or not is_instance_valid(host) \
			or not is_instance_valid(target) or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var tsize: Vector2 = target.size * target.scale
	var centre: Vector2 = target.global_position + tsize * 0.5
	# GROWN, NOT INSET (2026-09-09). This was inset 5px because the flash was a
	# HARD-EDGED white rectangle and any overhang showed as a visible corner
	# past the card's deckled edge. It is a soft superellipse bloom now, so the
	# overhang IS the effect — light bleeding off the sheet — and the falloff
	# does the containing the inset used to do.
	var fsz: Vector2 = Vector2(tsize.x * squash.x, tsize.y * squash.y) \
		+ Vector2(16.0, 16.0)
	var flash := ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color.WHITE
	flash.material = _bloom_material(tint)
	flash.z_index = 229
	flash.size = fsz
	host.add_child(flash)
	flash.global_position = centre - fsz * 0.5
	var ft := flash.create_tween()
	ft.tween_interval(0.033)
	# The shader writes COLOR outright, so `modulate` never reaches it — fade the
	# uniform. (Tweening modulate:a here left the flash on screen at full
	# strength until queue_free, i.e. a white card for 0.13s.)
	ft.tween_property(flash, "material:shader_parameter/fade", 0.0, 0.10) \
		.set_ease(Tween.EASE_IN)
	ft.tween_callback(flash.queue_free)


static var _vfx_noise_shader_cache: Shader = null


## ── THE VFX MATERIAL (2026-09-10) ────────────────────────────────────
## The canonical stylized-VFX construction is FOUR channels — a colour gradient,
## SCROLLING NOISE, a second noise for EROSION, and a shape mask — and the filled
## forms in this game had only two of them. A `Polygon2D` with `vertex_colors`
## is a mask and a gradient: no internal texture and no ragged edge, which is
## exactly why they read as clean VECTOR shapes rather than as burning, freezing
## or rotting matter. Adding motion to compensate only makes a clean shape wobble.
##
## This supplies the missing two, on top of whatever colour the polygon already
## carries:
##   · SCROLLING FBM drives the internal value — the licking, churning texture
##     that a flat fill cannot have at any amount of vertex detail. It scrolls
##     along -V, so callers map V so that 1 is the SEAT and 0 the tip and the
##     detail travels the way the matter does.
##   · ALPHA EROSION through a FEATHERED threshold (never `step` — a hard step
##     aliases badly on a form this size), biased so the FAR end goes first: a
##     flame's tips break up while its seat holds, and the same is true of a
##     crack's reach and a colony's margin.
##
## It multiplies the incoming COLOR, so `vertex_colors` and any `modulate` fade
## still work exactly as before — this is a detail pass laid over the existing
## art, not a replacement for it.
##
## Procedural rather than a sampled texture ON PURPOSE: no asset, no import step,
## no filtering surprises on gl_compatibility, and the seed decorrelates two
## effects that fire on the same frame.
static func vfx_noise_material(seed: float = 0.0, scroll: float = 1.4,
		grain: float = 2.2, bite: float = 0.55,
		warp: float = 0.0, ramp: float = 0.0,
		ramp_hot: Color = Color(1.0, 0.93, 0.62),
		rim: float = 0.0) -> ShaderMaterial:
	if _vfx_noise_shader_cache == null:
		_vfx_noise_shader_cache = Shader.new()
		_vfx_noise_shader_cache.code = """shader_type canvas_item;

uniform float t = 0.0;        // scroll progress, driven over the form's life
uniform float erode = 0.0;    // 0 = whole, 1 = eaten away
uniform float seed = 0.0;
uniform float scroll = 1.4;   // how fast the detail travels
uniform float grain = 2.2;    // noise frequency: low = billowy, high = fibrous
uniform float bite = 0.55;    // how hard the noise cuts the value
uniform float warp = 0.0;     // domain warping — see the note in fragment()
uniform float ramp = 0.0;     // gradient-map strength (0 = plain brightness)
uniform vec4 ramp_hot : source_color = vec4(1.0, 0.93, 0.62, 1.0);
uniform float rim = 0.0;      // how hard the erosion frays the SILHOUETTE

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// Three octaves: the billow, the detail on the billow, and the fibre. Fewer
// reads as a blob, more is invisible at the sizes these forms are drawn.
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.3) * 0.30 + vnoise(p * 4.7) * 0.15;
}

void fragment() {
	vec2 np = vec2(UV.x * grain + seed, UV.y * grain * 0.72 - t * scroll);
	// DOMAIN WARPING — the step that separates procedural noise that looks like
	// NOISE from noise that looks like a fluid. Plain fbm is isotropic blobs:
	// evenly sized, evenly spaced, and the eye reads the regularity instantly.
	// Feeding the lookup position through a second, coarser fbm bends the field
	// so the blobs stretch, fold and curl into each other — which is what fire
	// and rot actually do, and what no amount of extra octaves will give you.
	//
	// Zero for anything CRYSTALLINE. Ice is faceted, not fluid; warping its
	// marbling would make a solid look like it was flowing.
	if (warp > 0.001) {
		vec2 q = vec2(fbm(np + vec2(1.7, 9.2)), fbm(np + vec2(8.3, 2.8)));
		np += (q - 0.5) * warp;
	}
	float n = fbm(np);
	// The internal value. Centred on 1.0 so the form keeps its overall
	// brightness and the noise only redistributes it.
	vec3 col = COLOR.rgb * ((1.0 - bite * 0.5) + bite * n);
	// GRADIENT MAPPING. The line above MULTIPLIES the tint by the noise, so a
	// hot filament comes out as a LIGHTER VERSION OF THE SAME HUE — and that is
	// not what combustion does. Temperature moves fire along a ramp, deep red to
	// orange to yellow to white, so the hot parts are a different COLOUR and not
	// merely a brighter one. Multiplying an orange by 1.3 gives a pale orange,
	// which is exactly the "looks like tinted smoke" read.
	//
	// The standard fix is to use the noise as a LOOKUP into a palette rather
	// than as a brightness multiplier. Two stops is enough here: the polygons
	// that carry this already have macro ramps in `vertex_colors`, so this only
	// has to supply the MICRO shift inside one form.
	//
	// `ramp` defaults to 0, so every existing call site is byte-identical.
	float heat = clamp((n - 0.42) * 2.4, 0.0, 1.0);
	col = mix(col, ramp_hot.rgb, heat * heat * ramp);
	// EROSION, biased by UV.y so the FAR end goes first — tips break up, the
	// seat holds. Feathered, never `step`: a hard cut aliases on these sizes.
	//
	// THE 0.14 BASELINE IS THE POINT. Driving this purely from `erode` meant the
	// form carried a mathematically PERFECT polygon outline for the whole first
	// half of its life — the part the player actually looks at — and only went
	// ragged as it died. A flame, a crack and a rotting margin are all irregular
	// at their edge from the first frame; the animated part is how much MORE
	// gets eaten, not whether the edge is clean to begin with.
	float far = 1.0 - UV.y;
	float thr = (0.14 + erode) * (0.35 + 0.85 * far);
	// AND IT HAS TO BITE AT THE SILHOUETTE, which is the part the eye actually
	// calls "cut out". Noise keyed to UV alone eats the form EVENLY: the
	// interior gets lovely internal structure and the OUTLINE stays exactly
	// where the polygon put it, facets and all. Fixing the threshold, the
	// offset and the grain all improved the inside of a shape whose edge never
	// moved — three passes at the wrong half of the problem.
	//
	// UV.x runs ACROSS the form, so this is 0 on the spine and 1 at either
	// margin. Squared, so the bite is concentrated in the last stretch rather
	// than thinning the whole body. `rim` defaults to 0: a crystalline form
	// wants its facets, and only callers that should fray opt in.
	// THE EXPONENT MATTERS MORE THAN THE COEFFICIENT, and getting that backwards
	// cost two passes. Squared is not edge-localised: `marg` is 0 only on the
	// spine and 1 at either margin, so at UV.x 0.25 it is still 0.25 and HALF
	// THE FORM was being eroded. Raising the coefficient to compensate just
	// washed the whole tongue out — pale, thin and ghostly, with the body colour
	// gone. The shape was losing its mass to buy a ragged edge.
	//
	// The sixth power confines it to roughly the outer fifth: 0.5 -> 0.016
	// (nothing), 0.8 -> 0.26, 0.96 -> 0.78. That allows a STRONG coefficient,
	// so the margin genuinely breaks up while the body keeps its density.
	float marg = 1.0 - min(UV.x, 1.0 - UV.x) * 2.0;
	float m3 = marg * marg * marg;
	thr += m3 * m3 * 0.95 * rim;
	// THE +0.30 OFFSET MADE THE EROSION INERT, and the comment above described
	// an intent the arithmetic never delivered. `n` is fbm in 0..1; adding 0.30
	// put it above the tip threshold (0.168) almost everywhere, so the minimum
	// alpha multiplier at the NOISE FLOOR was 0.896 — the form stayed opaque and
	// wore its raw polygon silhouette, which is exactly the faceted cut-out read
	// the noise was added to destroy. Measured, not guessed: at 0.30 the whole
	// range 0.25..1.0 mapped to 1.000.
	//
	// 0.12 keeps the seat solid (a flame's base is dense) while letting the tips
	// break up from the first frame, which is what the note above promises.
	float ero = smoothstep(thr - 0.22, thr + 0.22, n + 0.12);
	// THE BURN EDGE, as on the ring: the band being eaten RIGHT NOW is the
	// hottest part of a burning thing, and without it an erosion reads as the
	// form fading rather than being consumed. Cubed for the same reason it is
	// cubed there — the erosion's own smoothstep is wide, so the plain parabola
	// lights most of the form instead of its front. It rides `ramp`, so a call
	// site that has not opted into the palette is unaffected.
	float burn = pow(4.0 * ero * (1.0 - ero), 3.0) * ramp;
	col = mix(col, ramp_hot.rgb, burn * 0.85);
	float a = COLOR.a * clamp(ero + burn * 0.30, 0.0, 1.0);
	COLOR = vec4(col, a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _vfx_noise_shader_cache
	mat.set_shader_parameter("seed", seed)
	mat.set_shader_parameter("scroll", scroll)
	mat.set_shader_parameter("grain", grain)
	mat.set_shader_parameter("bite", bite)
	mat.set_shader_parameter("warp", warp)
	mat.set_shader_parameter("ramp", ramp)
	mat.set_shader_parameter("ramp_hot", ramp_hot)
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("t", 0.0)
	mat.set_shader_parameter("erode", 0.0)
	return mat


static var _white_tex_cache: ImageTexture = null


## A 1x1 opaque white texture, cached.
##
## THE REASON IT EXISTS IS A GODOT TRAP THAT MADE `vfx_noise_material` INERT.
## A `Polygon2D` does not hand usable UVs to its shader unless it has a
## `texture` assigned — with none, every vertex reads (0,0), so a UV-driven
## lookup is CONSTANT across the whole form. Measured, not inferred: the same
## polygon under the same noise material scored a pixel standard deviation of
## 0.0000 without a texture and 0.1931 with one.
##
## Nothing errors. The shader compiles, the material binds, the uniforms are
## set, and the form renders as a clean vertex-colour gradient — which reads
## exactly like a deliberately flat art style, so it survived a full rebuild of
## the flame plus three further passes at the threshold, the offset and the
## grain. Every one of those was tuning the inside of a shape whose shader was
## sampling a single point.
##
## Assigning white changes no colour (it multiplies through) and costs one
## 1x1 texture for the whole game.
static func white_tex() -> Texture2D:
	if _white_tex_cache == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_white_tex_cache = ImageTexture.create_from_image(img)
	return _white_tex_cache


static var _bloom_shader_cache: Shader = null


## The soft over-exposure quad behind `impact_frame`. A flat ColorRect is a WHITE
## BOX with four hard corners — the same defect class as the old Line2D ring, and
## on a deckled parchment card the corners are the tell.
##
## THE FALLOFF IS A SUPERELLIPSE, not a radial one. A plain radial gradient on a
## 225x300 card leaves the corners dark and reads as an OVAL sitting on a
## rectangle; raising the exponent keeps the card's own silhouette while still
## having no hard edge anywhere.
static func _bloom_material(tint: Color) -> ShaderMaterial:
	if _bloom_shader_cache == null:
		_bloom_shader_cache = Shader.new()
		_bloom_shader_cache.code = """shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform float fade = 1.0;
uniform float power = 4.0;

void fragment() {
	vec2 p = abs(UV - vec2(0.5)) * 2.0;
	float d = pow(pow(p.x, power) + pow(p.y, power), 1.0 / power);
	float a = pow(clamp(1.0 - smoothstep(0.52, 1.0, d), 0.0, 1.0), 1.3);
	COLOR = vec4(tint.rgb, a * tint.a * fade);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _bloom_shader_cache
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("fade", 1.0)
	return mat


## A thin fast shock ahead of a slow heavy swell. One ring reads as a bubble;
## the pair reads as an impact.
static func shock_rings(host: Control, at: Vector2, accent: Color,
		scale_mult: float = 1.0) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	ring_pulse(host, at, Color(1.0, 0.98, 0.92, 0.85),
		20.0 * scale_mult, 150.0 * scale_mult, 0.20)
	ring_pulse(host, at, Color(accent.r, accent.g, accent.b, 0.62),
		34.0 * scale_mult, 240.0 * scale_mult, 0.44)


## A tilted band of light crossing the card. The effect goes on a CHILD ColorRect
## in blend_add — a Control's own material does not reach its children, which is
## why the Balatro foil setup puts the shader on a child rect and why this is not
## simply `target.material = ...`.
static func foil_sweep(host: Control, target: Control, accent: Color,
		dur: float = 0.36) -> void:
	if host == null or target == null or not is_instance_valid(host) \
			or not is_instance_valid(target) or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var band := ColorRect.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.color = Color.WHITE
	band.z_index = 228
	band.size = target.size * target.scale
	var mat := ShaderMaterial.new()
	mat.shader = _sweep_shader()
	mat.set_shader_parameter("tint", Color(accent.r, accent.g, accent.b, 1.0))
	band.material = mat
	host.add_child(band)
	band.global_position = target.global_position
	var band_ref: WeakRef = weakref(band)
	var sweep_cb := func(v: float) -> void:
		var b: ColorRect = band_ref.get_ref()
		if b == null or b.material == null:
			return
		b.material.set_shader_parameter("progress", v)
	var bt := band.create_tween()
	bt.tween_method(sweep_cb, 0.0, 1.0, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bt.tween_callback(band.queue_free)


static func forge_strike(host: Control, target: Control) -> void:
	# The forge set-piece: the tempered card flashes white-hot, anvil sparks
	# shower off its base and FALL (unlike combat's rising embers — different
	# material, deliberate), and the metal cools back to white.
	#
	# REBUILT 2026-08-28 on the same five-stage grammar as writ_amend, which was
	# researched after this shipped: it had the flash and the sparks but no
	# wind-up, no squash, and no hitstop, so the loudest card moment in the game
	# was landing softer than its own quieter sibling. It stays the BIGGER of the
	# two — heavier squash, a wider ring pair, anvil sparks, a full-weight shake.
	# Awaitable (~0.72s); Reduce Motion / missing target = no beat.
	if host == null or target == null \
			or not is_instance_valid(host) or not is_instance_valid(target):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var tree := host.get_tree()
	if tree == null:
		return
	var center: Vector2 = target.global_position + target.size * 0.5
	var base_pt: Vector2 = center + Vector2(0, target.size.y * 0.32)
	var base_scale: Vector2 = target.scale
	target.pivot_offset = target.size * 0.5

	# 1. ANTICIPATION — the metal is drawn back and dimmed before the hammer.
	var pre := target.create_tween()
	pre.tween_property(target, "scale", base_scale * 0.975, 0.07) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pre.parallel().tween_property(target, "modulate", Color(0.82, 0.80, 0.78), 0.07)

	# 2. THE SHINE — light travels the blade on the way in.
	foil_sweep(host, target, Color(1.0, 0.86, 0.44), 0.26)

	await tree.create_timer(0.10).timeout
	if not is_instance_valid(target) or not is_instance_valid(host) \
			or not host.is_inside_tree():
		return

	# 3. CONTACT — impact frame, a heavier squash than writ_amend's, white-hot.
	var squash := Vector2(1.12, 0.88)
	impact_frame(host, target, squash, Color(1.0, 0.97, 0.90, 0.90))
	target.scale = Vector2(base_scale.x * squash.x, base_scale.y * squash.y)
	target.modulate = Color(1.85, 1.62, 1.22)
	shock_rings(host, base_pt, Color(1.0, 0.88, 0.55), 1.15)
	GameTheme.shake_impulse(host, 0.40)
	burst(host, base_pt, "spark_fall")

	# 4. HITSTOP — the anvil holds the blow a beat longer than the seal does.
	await tree.create_timer(0.09).timeout
	if not is_instance_valid(target):
		return

	# 5. COOL — back to true colour and true size.
	var tw := target.create_tween()
	tw.set_parallel(true)
	tw.tween_property(target, "scale", base_scale, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "modulate", Color(1.26, 1.06, 0.86), 0.16)
	tw.chain().tween_property(target, "modulate", Color.WHITE, 0.30) \
		.set_ease(Tween.EASE_OUT)

	await tree.create_timer(0.53).timeout


static func writ_amend(host: Control, card: Control, stamp_text: String,
		accent: Color = Color(1.0, 0.84, 0.40), opts: Dictionary = {}) -> void:
	# THE WRIT IS AMENDED — the beat every PERMANENT change to a card in the
	# player's own deck shares: the drill yard's banked +1/+1, the standard-
	# bearer's pinned keyword, and the two veterancy rungs (war school, tribe
	# doctrine). All four used to change a card with NO beat whatsoever — the
	# screen simply rebuilt with different numbers printed on it — which is the
	# one thing a deckbuilder must never do to the player's own cards.
	#
	# forge_strike stays the LOUDER sibling and is not replaced: the forge is the
	# run's most permanent single decision and earns the anvil. This is the road's
	# quieter stamp — a shine sweeping the page, then the new ink struck onto it.
	#
	# The STAMP is INFORMATIONAL (it names what changed), so it still lands under
	# Reduce Motion — placed settled, held long enough to read, then gone. The
	# lift, the sweep, the sparks and the thump are decorative and gate off.
	#
	# opts: "lift" (bool, default true) tweens the card itself — pass false for a
	# LIVE battlefield token, whose idle bob already owns its scale and modulate;
	# "sweep" (bool, default true) the shine band; "hold" (float, default 0.34)
	# how long the stamp is held before it floats off.
	#
	# Awaitable (~0.9s). Headless returns instantly so probes never pay for it.
	if host == null or card == null \
			or not is_instance_valid(host) or not is_instance_valid(card) \
			or not host.is_inside_tree() or not card.is_inside_tree():
		return
	if stamp_text.strip_edges() == "":
		return
	if DisplayServer.get_name() == "headless":
		return
	var tree := host.get_tree()
	if tree == null:
		return
	var reduced: bool = UserSettings != null and UserSettings.reduce_motion
	# Scale is part of a card's footprint here — pickers deal their writs at 0.8
	# (225×300 → 180×240), so size alone would centre the beat off the card.
	var csize: Vector2 = card.size * card.scale
	var centre: Vector2 = card.global_position + csize * 0.5
	var hold: float = float(opts.get("hold", 0.34))
	# The stamp strikes the ART, not the middle of the card. Dead centre on the
	# v9 writ is the name cartouche, so the first build printed "+1/+1" straight
	# through the creature's own name and "GUARDIAN" across a cream rules box —
	# two pale things over each other. A card's upper third is its painting: dark,
	# busy, and the one place gilt-with-a-black-outline always reads.
	var strike: Vector2 = centre + Vector2(0.0, -csize.y * 0.19)

	# The new ink, struck slightly off-square like a seal pressed by hand.
	# Parented to `host`, never to the card: the drill yard swaps its writ
	# between passes, and a stamp parented to the old one would go with it.
	var stamp := Label.new()
	stamp.text = stamp_text
	# FIT THE WORD TO THE WRIT. At a fixed size a long keyword ("GUARDIAN",
	# "REGENERATE") ran a third of its width off both edges of a 180px picker
	# tile and over the cards either side — a stamp that lands on three cards
	# names none of them. Shrink until it sits inside its own card.
	var fsize: int = 44
	var fnt: Font = GameTheme.font_display
	if fnt != null:
		var w: float = fnt.get_string_size(stamp_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
		var room: float = maxf(csize.x * 1.06, 120.0)
		if w > room:
			fsize = maxi(19, int(float(fsize) * room / w))
		stamp.add_theme_font_override("font", fnt)
	var box := Vector2(maxf(csize.x * 1.6, 220.0), float(fsize) * 2.0)
	stamp.add_theme_font_size_override("font_size", fsize)
	stamp.add_theme_color_override("font_color", accent)
	stamp.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.96))
	stamp.add_theme_constant_override("outline_size", maxi(4, fsize / 6))
	# A cast shadow under the ink, so the word reads as PRESSED INTO the page
	# rather than floating over it — the outline alone gives an edge, not a lift.
	stamp.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	stamp.add_theme_constant_override("shadow_offset_x", 2)
	stamp.add_theme_constant_override("shadow_offset_y", 3)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.z_index = 230
	stamp.custom_minimum_size = box
	stamp.size = box
	stamp.pivot_offset = box * 0.5
	stamp.rotation = -0.085
	host.add_child(stamp)
	stamp.global_position = strike - box * 0.5

	if reduced:
		# Settled placement, a reading pause, a plain fade. No lift, no sweep,
		# no spark, no thump — but the player is still TOLD what changed.
		await tree.create_timer(0.62).timeout
		if is_instance_valid(stamp):
			var rt := stamp.create_tween()
			rt.tween_property(stamp, "modulate:a", 0.0, EXIT)
			rt.tween_callback(stamp.queue_free)
		return

	# The stamp comes in BIG, hot and over-rotated, and lands square-ish.
	stamp.modulate.a = 0.0
	stamp.scale = Vector2(2.15, 2.15)
	stamp.rotation = -0.26

	var base_scale: Vector2 = card.scale
	var lift: bool = bool(opts.get("lift", true))

	# ── 1. ANTICIPATION ────────────────────────────────────────────────────
	# The page DIPS and dims before it is struck. Disney's first principle, and
	# the single cheapest thing that separates "a thing appeared" from "a thing
	# happened": the eye needs the wind-up to read the blow.
	if lift:
		card.pivot_offset = card.size * 0.5
		var ct := card.create_tween()
		ct.tween_property(card, "scale", base_scale * 0.982, 0.09) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(card, "modulate", Color(0.86, 0.84, 0.82), 0.09)
		ct.tween_property(card, "scale", base_scale * 1.05, 0.13) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(card, "modulate", Color(1.30, 1.19, 0.99), 0.13)

	# ── 2. THE SHINE ───────────────────────────────────────────────────────
	# A tilted specular band crosses the page and arrives at the strike point on
	# the beat the stamp lands, so the light READS AS THE CAUSE. Drawn by a
	# shader on a ColorRect over the card (the Balatro-foil setup: the effect
	# goes on a child rect, never on the card's own material) — the previous
	# version stacked flat white draw_rects, which is a bar, not a highlight.
	if bool(opts.get("sweep", true)):
		foil_sweep(host, card, accent, 0.36)

	# ── 3. CONTACT ─────────────────────────────────────────────────────────
	await tree.create_timer(0.24).timeout
	if not is_instance_valid(stamp) or not is_instance_valid(host) \
			or not host.is_inside_tree():
		return

	# THE IMPACT FRAME: two frames of the card blown to pure white. Borrowed
	# straight from hand-drawn action animation — the eye reads a single
	# over-exposed frame as force, and it costs one ColorRect.
	var squash := Vector2(1.10, 0.90) if lift else Vector2.ONE
	impact_frame(host, card, squash)

	# SQUASH, then HOLD. The card is snapped wide-and-flat with no tween at all
	# and left there through the hitstop below — a squash you can watch travel
	# is not a squash, it is a wobble. The warm push stays under the impact
	# frame's brightness: two bleaches stacked just erase the parchment.
	if lift:
		card.scale = Vector2(base_scale.x * squash.x, base_scale.y * squash.y)
		card.modulate = Color(1.26, 1.18, 1.02)

	var sT := stamp.create_tween()
	sT.set_parallel(true)
	sT.tween_property(stamp, "modulate:a", 1.0, 0.06)
	sT.tween_property(stamp, "scale", Vector2.ONE, PUNCH) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sT.tween_property(stamp, "rotation", -0.085, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shock_rings(host, strike, accent)
	burst(host, strike, "impact", {
		"color": accent, "amount": 16, "spread": 180.0,
		"velocity_min": 70.0, "velocity_max": 210.0, "gravity": Vector2(0, 320.0)})
	GameTheme.shake_impulse(host, 0.30)

	# ── 4. HITSTOP ─────────────────────────────────────────────────────────
	# ~4 frames of nothing at all. Everything above is already in flight; this
	# just refuses to start the settle, and that refusal is the punch.
	await tree.create_timer(0.07).timeout
	if not is_instance_valid(host) or not host.is_inside_tree():
		return

	# ── 5. SETTLE ──────────────────────────────────────────────────────────
	if lift and is_instance_valid(card):
		var rt2 := card.create_tween()
		rt2.set_parallel(true)
		rt2.tween_property(card, "scale", base_scale, SETTLE_SLOW) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rt2.tween_property(card, "modulate", Color.WHITE, 0.38)
	# Embers lift off the fresh ink as it dries.
	burst(host, strike, "ash", {"color": accent, "amount": 10, "lifetime": 1.0})

	await tree.create_timer(hold).timeout
	if is_instance_valid(stamp):
		var xt := stamp.create_tween()
		xt.set_parallel(true)
		xt.tween_property(stamp, "modulate:a", 0.0, EXIT).set_ease(Tween.EASE_IN)
		xt.tween_property(stamp, "position",
			stamp.position + Vector2(0, -32.0), EXIT).set_ease(Tween.EASE_IN)
		xt.chain().tween_callback(stamp.queue_free)
	await tree.create_timer(0.20).timeout


## The specular sweep, cached for the session. A tilted band of light crossing
## UV space, with the Balatro foil trick for its fringing — layered trig on the
## sweep axis, so the leading edge splits cool while the core stays white-hot.
## That white-hot core is the house contrast rule (CLAUDE.md): a lone warm band
## on warm parchment is camouflage.
static var _sweep_shader_cache: Shader = null

static func _sweep_shader() -> Shader:
	if _sweep_shader_cache != null:
		return _sweep_shader_cache
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
render_mode blend_add;

uniform float progress = 0.0;
uniform float band : hint_range(0.05, 1.0) = 0.34;
uniform float tilt = 0.42;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.44, 1.0);

void fragment() {
	// Project UV onto the tilted sweep axis, normalised so the band always
	// crosses the whole rect whatever the card's aspect.
	float axis = (UV.y * cos(tilt) + UV.x * sin(tilt)) / (cos(tilt) + sin(tilt));
	float head = progress * (1.0 + band * 2.0) - band;
	float d = (axis - head) / band;
	float m = pow(clamp(1.0 - abs(d), 0.0, 1.0), 2.2);
	// Iridescent fringing (Balatro's layered-trig idea, one axis instead of two).
	float ir = 0.5 + 0.5 * sin(axis * 24.0 + progress * 8.0);
	vec3 hue = mix(tint.rgb, vec3(0.52, 0.76, 1.0), ir * 0.5);
	// Tracer-hot core.
	float core = pow(clamp(1.0 - abs(d) * 2.4, 0.0, 1.0), 3.0);
	vec3 col = mix(hue, vec3(1.0), core);
	COLOR = vec4(col, m * 0.9);
}
"""
	_sweep_shader_cache = sh
	return _sweep_shader_cache


static func rarity_reveal(ctrl: Control, rarity: String, delay: float = 0.0) -> void:
	# One-shot glow behind a freshly dealt card offer, scaled to the pull:
	# uncommon = a cool silver bloom with a few short rays, rare = a wider gilt
	# bloom, longer rays, and a brightness kiss on the card itself.
	# Commons/starters no-op — the shine must stay information ("this slate
	# rolled well"), not wallpaper. Drawn as the burst Control's OWN geometry
	# (draw signal) with show_behind_parent, so it sits behind the card face and
	# above the screen background.
	#
	# THIS HEADER SAID "a cool silver RING-GLINT" until 2026-09-10 and there has
	# been no ring since; the description outlived the drawing by exactly one
	# edit. Worth naming because a comment that lies is worse than none — the
	# ring was removed precisely BECAUSE a wire loop round a card reads as
	# "selected", and a stale note claiming it is still there would send the next
	# reader looking for a bug in the wrong place.
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if rarity != "uncommon" and rarity != "rare":
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	if DisplayServer.get_name() == "headless":
		return
	var is_rare := rarity == "rare"
	var col: Color = Color(1.0, 0.83, 0.36) if is_rare else Color(0.74, 0.83, 0.94)
	var sunburst := Control.new()
	sunburst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sunburst.show_behind_parent = true
	sunburst.modulate.a = 0.0
	sunburst.scale = Vector2(0.55, 0.55)
	ctrl.add_child(sunburst)
	# Ray directions rolled once; geometry is drawn in the burst's local space
	# around origin, so the tween animates transform + alpha only.
	var rays: Array = []
	var ray_n: int = 12 if is_rare else 7
	for i in ray_n:
		rays.append([Vector2.from_angle(
			TAU * (float(i) + randf_range(-0.18, 0.18)) / float(ray_n)),
			randf_range(0.85, 1.2)])
	sunburst.draw.connect(func():
		if not is_instance_valid(ctrl):
			return
		# Elliptical halo hugging the card's silhouette, rays ticking outward
		# from just past its edge — an engraved sunburst, not a lens flare.
		var rx: float = ctrl.size.x * 0.62
		var ry: float = ctrl.size.y * 0.58
		# NO RING (2026-09-10). This drew a 2.5px `draw_polyline` ellipse right
		# round the card and then ROTATED it, which is the flat-hairline-circle
		# defect wearing a third spelling — and on a card-choice screen it was
		# the most-looked-at circle in the game. The owner's report was exactly
		# right on both counts: it was ugly, AND nobody could tell what it meant,
		# because a wire loop round a card says "selected" far more loudly than
		# it says "uncommon".
		#
		# What replaces it is a GLOW, which is what the thing always meant: the
		# slate rolled well. Light is one of the few registers a soft-edged beam
		# is genuinely CORRECT for (see the vfx notes: beams are for light, solids
		# for matter), so the rays stay and simply stop being flat 3px lines —
		# they are drawn as tapered strokes, brightest where they leave the card
		# and dying outward, over a soft radial bloom.
		var bloom := 26 if is_rare else 18
		for k in range(bloom):
			var f: float = float(k) / float(bloom - 1)
			var a: float = TAU * f
			var pr := Vector2(cos(a) * rx * 1.06, sin(a) * ry * 1.06)
			# A soft body of light hugging the silhouette: many low-alpha discs
			# rather than one hard outline. Cheap, and it has no EDGE, which is
			# the entire complaint about the ring it replaces.
			sunburst.draw_circle(pr, 26.0 if is_rare else 19.0,
				Color(col.r, col.g, col.b, 0.075 if is_rare else 0.055),
				true, -1.0, true)
		for r in rays:
			var d: Vector2 = r[0]
			var p0 := Vector2(d.x * ctrl.size.x * 0.55, d.y * ctrl.size.y * 0.52)
			var p1: Vector2 = p0 * (1.34 if is_rare else 1.20) * float(r[1])
			# TAPERED: three passes narrowing outward, so a ray leaves the card
			# with weight and dies to a point. A constant-width line is the same
			# uniform-opacity problem the beam kit exists to solve, and inside a
			# `draw` callback a beam node is not available.
			for s in range(3):
				var g: float = float(s) / 2.0
				sunburst.draw_line(p0.lerp(p1, g * 0.55), p1.lerp(p0, 0.05),
					Color(col.r, col.g, col.b, 0.42 - 0.12 * g),
					(4.6 - 1.6 * g) if is_rare else (3.4 - 1.2 * g), true))
	var tw := ctrl.create_tween()
	tw.tween_interval(maxf(delay, 0.001))
	tw.tween_callback(func():
		if is_instance_valid(sunburst) and is_instance_valid(ctrl):
			sunburst.position = ctrl.size * 0.5
			sunburst.queue_redraw())
	tw.tween_property(sunburst, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sunburst, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# NO ROTATION. A mark that travels round a card reads as a SELECTION
	# cursor — which is what made this unreadable as a rarity tell. Light
	# swells, it does not orbit.
	if is_rare:
		tw.parallel().tween_property(ctrl, "modulate",
			Color(1.20, 1.14, 1.00), 0.14)
		# THE RARE ALSO CATCHES THE LIGHT. The halo says "the slate rolled well"
		# from outside the card; the foil says it about the card itself, which is
		# the read every competitor's premium pull uses (Balatro's foil, the
		# golden card). Uncommons deliberately do NOT get it — the shine has to
		# stay information, and two tiers of shine is one tier of noise.
		tw.parallel().tween_callback(func() -> void:
			if is_instance_valid(ctrl):
				foil_sweep(ctrl, ctrl, col, 0.52))
	tw.chain().tween_property(sunburst, "modulate:a", 0.0, 0.46) \
		.set_ease(Tween.EASE_IN)
	if is_rare:
		tw.parallel().tween_property(ctrl, "modulate", Color.WHITE, 0.30)
	tw.chain().tween_callback(func():
		if is_instance_valid(sunburst):
			sunburst.queue_free())


static func ring_pulse(overlay: Control, center: Vector2, color: Color,
		start_d: float, end_d: float, dur: float, delay: float = 0.0) -> void:
	# One expanding ring (a horn-blast / arcane pulse / sealing stamp) for the
	# shell screens (Event's result seal, the reroll flourish, forge shock
	# ring). `start_d` / `end_d` are DIAMETERS. A preset over `ring` — the one
	# ring engine (R5); the shell look (fade-in beat, cubic swell, stroke
	# thickening as it grows) rides the preset.
	ring(overlay, center, color, {
		"radius": start_d * 0.5, "start_scale": 1.0,
		"end_scale": end_d / maxf(start_d, 1.0), "duration": dur,
		"width": 5.0, "trans": Tween.TRANS_CUBIC,
		"fade_in": 0.08, "delay": delay,
	})


static func reroll_sweep(host: Control, cards: Array,
		accent: Color = Color(1.0, 0.82, 0.36)) -> float:
	# The reroll flourish: a double call-ring pulse plus the current choice
	# cards scattering off the table (blown outward from screen-centre,
	# spinning and fading), so a reroll READS as "sweep these away, call new
	# ones." Reparents `cards` onto a temporary top overlay so they animate
	# free of their layout containers; the overlay self-frees after the sweep.
	# Returns the seconds the caller should wait before dealing the fresh
	# slate in. `accent` colours the rings (gold horn-blast vs. arcane pulse).
	if host == null or not is_instance_valid(host):
		return 0.0
	var center: Vector2 = host.get_viewport_rect().size * 0.5
	var overlay := Control.new()
	overlay.name = "RerollSweepFX"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 180
	host.add_child(overlay)

	ring_pulse(overlay, center, Color(accent.r, accent.g, accent.b, 0.95),
		96.0, 580.0, 0.52)
	ring_pulse(overlay, center, Color(1, 1, 1, 0.75), 54.0, 320.0, 0.42, 0.06)

	var longest := 0.30
	for i in cards.size():
		var card = cards[i]
		if card == null or not is_instance_valid(card) or not (card is Control):
			continue
		var gpos: Vector2 = card.global_position
		var par: Node = card.get_parent()
		if par != null:
			par.remove_child(card)
		overlay.add_child(card)
		card.position = gpos
		card.pivot_offset = card.size * 0.5
		var cc: Vector2 = gpos + card.size * 0.5
		var dir: Vector2 = cc - center
		if dir.length() < 1.0:
			dir = Vector2(0, -1)
		dir = dir.normalized()
		var away: Vector2 = dir * 260.0 + Vector2(0, -70.0)
		var d := float(i) * 0.05
		var tw: Tween = card.create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "position", card.position + away, 0.34) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN).set_delay(d)
		tw.tween_property(card, "rotation", randf_range(-0.6, 0.6), 0.34).set_delay(d)
		tw.tween_property(card, "scale", card.scale * 0.5, 0.34).set_delay(d)
		tw.tween_property(card, "modulate:a", 0.0, 0.30).set_delay(d)
		longest = maxf(longest, d + 0.34)

	var kill := overlay.create_tween()
	kill.tween_interval(longest + 0.08)
	kill.tween_callback(overlay.queue_free)
	return longest


## ── ▲3 — THE SPRING (docs/TECHNIQUE_HUNT_20260902.md) ────────────────────────
##
## The whole game is fixed-duration tweens: 165 `create_tween` sites and, until
## this, not one piece of second-order motion anywhere. Filed as **C3** by
## `docs/ANIMATION_AUDIT_20260716.md` and open ever since.
##
## READ THIS BESIDE STRIKE_DESIGN §14, WHICH REJECTS "SPRINGS FOR THE STRIKE".
## That ruling is correct and stands: `LUNGE_APEX` is DERIVED from the tween's
## phases so the conductor's `await` agrees with the animation, and **a spring has
## no apex you can await**. It is a statement about the strike. Hand reflow awaits
## nothing, and it is the case the audit actually named — `set_hand_target`'s tween
## is killed and restarted on every hover, drag and relayout, which is the
## interruption case tweens handle worst and springs handle natively, because a
## spring carries VELOCITY as state and an interruption is therefore continuous.
##
## The formulation is t3ssel8r's second-order system, parameterised the way an
## animator thinks rather than in physical units:
##
##   f     — natural frequency in Hz: how QUICKLY it responds.
##   zeta  — damping. <1 overshoots and settles, 1 is critical, >1 crawls in.
##   r     — initial response. 0 eases out of rest; >1 anticipates; <0 winds up
##           the wrong way first.
class Spring:
	var value: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var _k1: float = 0.0
	var _k2: float = 0.0
	var _k3: float = 0.0

	func _init(f: float = 3.2, zeta: float = 0.72, r: float = 0.0) -> void:
		configure(f, zeta, r)

	func configure(f: float, zeta: float, r: float) -> void:
		f = maxf(f, 0.0001)
		_k1 = zeta / (PI * f)
		_k2 = 1.0 / ((TAU * f) * (TAU * f))
		_k3 = r * zeta / (TAU * f)

	func reset(at: Vector2) -> void:
		value = at
		vel = Vector2.ZERO

	## One step toward `target`. `target_vel` is only used when r != 0.
	##
	## `k2_stable` is not decoration — it is what stops a frame hitch from
	## detonating the system. The integrator is only stable while the timestep is
	## small relative to k2, and this project ships 100 ms+ gaps during a cold
	## board build; without the clamp a single long frame sends the card to
	## infinity and the node is simply gone. Clamping k2 up instead makes a long
	## frame merely SLUGGISH, which is the correct failure.
	func update(dt: float, target: Vector2, target_vel: Vector2 = Vector2.ZERO) -> Vector2:
		if dt <= 0.0:
			return value
		var k2_stable: float = maxf(_k2, maxf(dt * dt * 0.25 + dt * _k1 * 0.5, dt * _k1))
		value += vel * dt
		vel += (target + _k3 * target_vel - value - _k1 * vel) * (dt / k2_stable)
		return value

	## Settled = close enough to stop paying for it. Both terms matter: position
	## alone is true at the top of an overshoot, where the card is still moving.
	func is_settled(target: Vector2, pos_eps: float = 0.35,
			vel_eps: float = 6.0) -> bool:
		return value.distance_to(target) <= pos_eps and vel.length() <= vel_eps
