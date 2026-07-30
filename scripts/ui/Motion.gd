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


# ── The ring engine (R5) ───────────────────────────────────────────────
# THE expanding-ring implementation — Combat's spell rings, the shell's
# ring_pulse verb, and the net arsenal's chip burst all draw through here
# (three separate implementations before R5). A Line2D circle, because it's
# the most capable of the three ancestors: per-ring width, oval squash for
# ground rings, z control, and a width tween Panels can't do.
#
# opts (defaults preserve Combat's _spawn_vfx_ring look):
#   radius: float 16      geometry radius before scaling
#   start_scale: float 0.55 · end_scale: float 1.6 · duration: float 0.42
#   width: float 3        stroke; apparent width also grows with scale
#   width_end: float 0    if > 0, tween width to this (counteracts the grow)
#   z_index: int 0 · oval: Vector2.ONE (squash for ground ellipses)
#   trans: Tween.TransitionType — applied to the scale tween when present
#   fade_in: float 0      if > 0, alpha 0→1 first, THEN the expansion
#   delay: float 0 · scale_time: bool false (wrap duration in Motion.time)
static func ring(host: Node, center: Vector2, color: Color,
		opts: Dictionary = {}) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var radius: float = float(opts.get("radius", 16.0))
	var dur: float = float(opts.get("duration", 0.42))
	if opts.get("scale_time", false):
		dur = time(dur)
	var width: float = float(opts.get("width", 3.0))
	var width_end: float = float(opts.get("width_end", 0.0))
	var oval: Vector2 = opts.get("oval", Vector2.ONE)
	var fade_in: float = float(opts.get("fade_in", 0.0))
	var delay: float = float(opts.get("delay", 0.0))
	var rg := Line2D.new()
	rg.width = width
	rg.antialiased = true
	rg.z_index = int(opts.get("z_index", 0))
	rg.default_color = color
	var pts := PackedVector2Array()
	for i in range(49):
		var a := TAU * float(i) / 48.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	rg.points = pts
	rg.position = center
	rg.scale = oval * float(opts.get("start_scale", 0.55))
	if fade_in > 0.0:
		rg.modulate.a = 0.0
	host.add_child(rg)
	var tw := rg.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	if fade_in > 0.0:
		tw.tween_property(rg, "modulate:a", 1.0, fade_in)
	var sc := tw.tween_property(rg, "scale",
		oval * float(opts.get("end_scale", 1.6)), dur).set_ease(Tween.EASE_OUT)
	if opts.has("trans"):
		sc.set_trans(opts["trans"])
	if width_end > 0.0:
		tw.parallel().tween_property(rg, "width", width_end, dur) \
			.set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(rg, "modulate:a", 0.0, dur) \
		.set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(rg.queue_free)


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
	var centre_pivot := func() -> void:
		if is_instance_valid(lbl):
			lbl.pivot_offset = lbl.size * 0.5
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
	tw.tween_method(func(v: float):
		if is_instance_valid(lbl):
			lbl.text = template % int(round(v)),
		float(from_val), float(to_val), dur)
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


static func forge_strike(host: Control, target: Control) -> void:
	# The forge set-piece: the tempered card flashes white-hot, anvil sparks
	# shower off its base and FALL (unlike combat's rising embers — different
	# material, deliberate), a shock ring pops, and the metal cools back to
	# white. Awaitable (~0.6s); Reduce Motion / missing target = no beat.
	if host == null or target == null \
			or not is_instance_valid(host) or not is_instance_valid(target):
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var center: Vector2 = target.global_position + target.size * 0.5
	var base_pt: Vector2 = center + Vector2(0, target.size.y * 0.32)

	# White-hot flash → cool. Scale punch rides the same beat.
	target.pivot_offset = target.size * 0.5
	var tw := target.create_tween()
	tw.tween_property(target, "modulate", Color(2.1, 1.85, 1.35), 0.07) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(target, "scale", Vector2(1.07, 1.07), 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "modulate", Color(1.30, 1.08, 0.86), 0.16)
	tw.parallel().tween_property(target, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "modulate", Color.WHITE, 0.30) \
		.set_ease(Tween.EASE_OUT)

	# Shock ring at the strike point, and the anvil blow thumps the screen —
	# a small trauma impulse (R2), not a combat-sized quake. The shake service
	# is stateful and stays on the GameTheme autoload.
	ring_pulse(host, base_pt, Color(1.0, 0.88, 0.55, 0.75), 18.0, 150.0, 0.34)
	GameTheme.shake_impulse(host, 0.35)

	# Anvil sparks: spray up and out, then fall under gravity.
	burst(host, base_pt, "spark_fall")

	await host.get_tree().create_timer(0.60).timeout


static func rarity_reveal(ctrl: Control, rarity: String, delay: float = 0.0) -> void:
	# One-shot engraved sunburst behind a freshly dealt card offer, scaled to
	# the pull: uncommon = a cool silver ring-glint, rare = a gilt ray halo +
	# a brightness kiss on the card itself. Commons/starters no-op — the shine
	# must stay information ("this slate rolled well"), not wallpaper. Drawn as
	# the burst Control's OWN geometry (draw signal) with show_behind_parent,
	# so the rays sit behind the card face and above the screen background.
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
		var halo := PackedVector2Array()
		for i in range(57):
			var a := TAU * float(i) / 56.0
			halo.append(Vector2(cos(a) * rx, sin(a) * ry))
		sunburst.draw_polyline(halo, Color(col.r, col.g, col.b, 0.80), 2.5, true)
		if is_rare:
			sunburst.draw_polyline(halo, Color(col.r, col.g, col.b, 0.35), 7.0, true)
		for r in rays:
			var d: Vector2 = r[0]
			var p0 := Vector2(d.x * ctrl.size.x * 0.58, d.y * ctrl.size.y * 0.55)
			var p1: Vector2 = p0 * (1.30 if is_rare else 1.18) * float(r[1])
			sunburst.draw_line(p0, p1, Color(col.r, col.g, col.b, 0.75), 3.0, true))
	var tw := ctrl.create_tween()
	tw.tween_interval(maxf(delay, 0.001))
	tw.tween_callback(func():
		if is_instance_valid(sunburst) and is_instance_valid(ctrl):
			sunburst.position = ctrl.size * 0.5
			sunburst.queue_redraw())
	tw.tween_property(sunburst, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sunburst, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sunburst, "rotation", 0.12, 0.55)
	if is_rare:
		tw.parallel().tween_property(ctrl, "modulate",
			Color(1.20, 1.14, 1.00), 0.14)
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
