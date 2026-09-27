class_name Sheen
extends RefCounted
## Sheen.gd — STANDING MATERIALS for the shell's flat surfaces (2026-09-16).
##
## Motion.gd owns BEATS: a thing happens, a tween runs, the node frees itself.
## This file owns the other half — the materials a surface WEARS while it just
## sits there. They are different problems and they fail differently: a beat that
## is missing reads as an unresponsive control, and a material that is missing
## reads as an EMPTY SCREEN, which is the note that produced this file.
##
## THE DIAGNOSIS IS WORTH KEEPING, because "it feels empty" was not a layout
## complaint and rearranging containers did not fix it. The published
## distinction is between NEGATIVE space, which is intentional and carries
## hierarchy, and DEAD space, which is screen real estate doing no work. Run
## setup had both: a genuine hole under its two panes (a layout bug, fixed by
## making the content reach the foot) AND a page of ink floating on a flat dark
## field with no depth cue anywhere on it. The second one survives any amount of
## rearranging, because every surface on the screen was a rectangle of one value:
## the portrait ended at a hard edge, the tiles were flat washes, and nothing on
## the page was LIT BY anything. The standard answer in the UI literature is
## gradients, rim highlights and vignettes — the three cues that tell an eye
## "this is a surface in a room" rather than "this is a coloured rect".
##
## FOUR MATERIALS, each a different job:
##
##   vignette_material()  burns the EDGES of a painting so art fuses into its
##                        plate instead of stopping at a scissor line. This is
##                        the single biggest flatness fix and it costs one
##                        shader on a node that already exists.
##   sheen()              a standing specular crawl. Balatro's foil, slowed down
##                        and desaturated to a metal highlight: a procedural
##                        interference pattern on TIME, riding the surface's own
##                        luminance rather than painting over it.
##   plinth()             a soft warm pool UNDER a subject, so it stands on the
##                        page rather than floating above it. Drawn behind.
##   inset_material()     the bevel: a dark lip along the top edge and a lit one
##                        along the bottom, which is what makes a small tile read
##                        as pressed INTO the page instead of printed on it.
##
## TWO RULES THE BUILD RESTS ON.
##
## (1) VALUE IS DECIDED BY THE LOCAL GROUND. The shell's ground is warm-black, so
##     highlights here run white-hot and the vignette burns toward black. On
##     parchment every one of these inverts — the same lesson the beam kit paid
##     for. Nothing in this file is safe to drop onto a light surface unchanged.
##
## (2) A STANDING MATERIAL IS DECORATIVE, so Reduce Motion must HOLD it, never
##     remove it: `sheen` freezes its crawl at a fixed phase instead of vanishing,
##     because a surface that loses its highlight loses its shape as well. Only
##     the MOTION is decorative; the shading is information about form.
##
## Headless is not a special case here and must not become one: a ShaderMaterial
## builds fine with no DisplayServer, and every gate that measures ink would go
## blind if these no-opped.

const SHEEN_SPEED := 0.055


# ---------------------------------------------------------------------------
# VIGNETTE — the edge burn
# ---------------------------------------------------------------------------

static var _vignette_cache: Shader = null

## Burn the edges of whatever `target` is showing, as an OVERLAY child.
##
## AN OVERLAY, NOT A MATERIAL ON THE ART (2026-09-16, and this was the second
## render it cost). The first build set a ShaderMaterial on the portrait's own
## TextureRect, which is the obvious way to do it and works perfectly on a bare
## TextureRect in a container — the roster thumbnails proved it. On the big
## plate, where the TextureRect sits inside a `clip_contents` wrapper (the only
## scissor that works on gl_compatibility), the same material rendered NOTHING:
## a blank plate with the sheen's highlights floating in it, which reads exactly
## like a failed texture load. The shader compiled clean, so the log said
## nothing.
##
## Rather than keep bisecting a renderer interaction, the burn moved to where it
## cannot interact with anything: a sibling rect drawn ON TOP, carrying darkness
## in its own alpha. That is strictly more general as well — it burns a painting,
## a wash, a StyleBox or a whole composed subtree without any of them needing a
## material, which is why the tiles and the plate can now share one call.
##
## `strength` 0..1 is how black the corners go. `feather` is the fraction of the
## half-diagonal the falloff occupies; keep it generous (0.45+), because a tight
## vignette is a black frame — the very thing this replaces — and a wide one is
## light falling off.
##
## `warm` tints the burn toward the shell's ember instead of pure black, which
## is what keeps a cool painting (the Acolyte's teal, the Kindler's blue-grey) in
## the same room as the gilt around it. Burning to neutral black leaves five
## portraits at five colour temperatures and the pane reads as a contact sheet.
static func vignette(target: Control, strength: float = 0.62,
		warm: float = 0.16, feather: float = 0.52) -> ColorRect:
	if target == null or not is_instance_valid(target):
		return null
	var burn := ColorRect.new()
	burn.name = "Vignette"
	burn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burn.set_anchors_preset(Control.PRESET_FULL_RECT)
	burn.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _vignette_shader()
	mat.set_shader_parameter("strength", clampf(strength, 0.0, 1.0))
	mat.set_shader_parameter("warm", clampf(warm, 0.0, 1.0))
	mat.set_shader_parameter("feather", maxf(0.08, feather))
	burn.material = mat
	target.add_child(burn)
	return burn


static func _vignette_shader() -> Shader:
	if _vignette_cache != null:
		return _vignette_cache
	var sh := Shader.new()
	# The falloff is measured on a UV RESCALED to the node's aspect, or a wide
	# plate's left and right edges burn while its top and bottom do not — the
	# ellipse would follow the rect instead of the light.
	# THE BURN CARRIES ITSELF IN ALPHA. Ordinary blending, a near-black colour,
	# and an alpha that climbs toward the edge: the surface underneath is
	# untouched in the middle and buried at the rim. Nothing here samples the
	# thing it is darkening, which is the whole point — see the note on
	# `vignette()`.
	sh.code = """shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.62;
uniform float warm : hint_range(0.0, 1.0) = 0.16;
uniform float feather : hint_range(0.08, 1.2) = 0.52;
uniform vec3 ember : source_color = vec3(0.24, 0.10, 0.04);

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	// Chebyshev-ish blend: pure radius rounds the corners off a rectangular
	// plate and leaves the middles of the long edges bright. Mixing in the box
	// distance keeps the burn parallel to the frame it sits inside.
	float r = length(d);
	float b = max(abs(d.x), abs(d.y));
	float dist = mix(r, b, 0.45);
	float v = smoothstep(1.0 - feather, 1.04, dist);
	// The burn is warm-black, not black: a neutral rim on an ember page reads
	// as a hole punched in the art, a warm one reads as shadow.
	vec3 col = mix(vec3(0.0), ember, warm);
	COLOR = vec4(col, v * strength);
}
"""
	_vignette_cache = sh
	return _vignette_cache


# ---------------------------------------------------------------------------
# SHEEN — the standing specular crawl
# ---------------------------------------------------------------------------

static var _sheen_cache: Shader = null

## Lay a slow specular crawl over `target`, sized and positioned to it.
##
## Balatro's foil is the reference and the source is public: a layered-trig
## interference pattern driven by TIME, with its intensity derived from the
## texel's own low/high channels so the shine RIDES the art instead of covering
## it. Two deliberate departures, both because this is furniture rather than a
## trading card:
##
##   SLOW. The card effect runs at roughly a cycle a second and is meant to be
##   noticed. A menu that glitters at that rate is a slot machine, so the crawl
##   is ~18x slower — at rest you should not be able to say it is moving, only
##   that the metal is alive.
##
##   DESATURATED. The card shader pushes blue hard (`texel.b + delta*1.9`) for
##   the rainbow. Here the highlight is the room's own light: mostly white with
##   a single cool fringe, so it reads as a lamp travelling a surface and not as
##   a holographic sticker on it.
##
## Returns the node so a caller can park it (`visible`, `modulate`) — e.g. the
## roster lights only the lord it has focused.
static func sheen(target: Control, accent: Color = Color(1.0, 0.88, 0.58),
		intensity: float = 0.5) -> ColorRect:
	if target == null or not is_instance_valid(target):
		return null
	var band := ColorRect.new()
	band.name = "Sheen"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _sheen_shader()
	mat.set_shader_parameter("tint", Color(accent.r, accent.g, accent.b, 1.0))
	mat.set_shader_parameter("intensity", intensity)
	# REDUCE MOTION HOLDS, IT DOES NOT REMOVE (see the header). A frozen phase
	# is a still highlight, which is still a shading cue; deleting the node
	# would flatten the surface for exactly the players least able to spare
	# the depth cue.
	var moving := UserSettings == null or not UserSettings.reduce_motion
	mat.set_shader_parameter("speed", SHEEN_SPEED if moving else 0.0)
	band.material = mat
	target.add_child(band)
	return band


static func _sheen_shader() -> Shader:
	if _sheen_cache != null:
		return _sheen_cache
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
render_mode blend_add;

uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.58, 1.0);
uniform float speed = 0.055;
uniform float intensity : hint_range(0.0, 2.0) = 0.5;
uniform float phase = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float t = TIME * speed + phase;

	// Two interfering wavefronts at different frequencies and drifts. One would
	// be a moving stripe; the interference is what makes it read as a rippled
	// metal surface rather than a wipe.
	//
	// THE FREQUENCIES ARE THE WHOLE DESIGN and the first pass got them wrong:
	// at 5.4 and 2.3 cycles across the rect, a 282x376 plate carried about six
	// crests, each ~90px across — which is not a highlight, it is a pattern of
	// pale BLOBS, and on the render it read as a rendering fault rather than as
	// a lit surface. A specular band should be narrow relative to the thing it
	// crosses; at 14-19 cycles the plate carries a dozen fine bands and the eye
	// reads "brushed metal" instead of "something is wrong with the image".
	float a = sin((p.x * 19.0 + p.y * 7.5) * 3.14159 + t * 6.0);
	float b = sin((p.x * 8.5 - p.y * 14.0) * 3.14159 - t * 4.1 + 1.7);
	float f = a * 0.6 + b * 0.4;

	// Sharpen the crests into narrow highlights. A raw sine lights half the
	// surface at all times, which is a wash; the power curve leaves most of the
	// plate dark and puts the light in a few fine travelling bands.
	float crest = pow(clamp(f * 0.5 + 0.5, 0.0, 1.0), 7.0);

	// A broad diagonal gradient underneath, so there is a lit SIDE as well as
	// lit bands — one light source, consistently placed.
	float lean = clamp(0.5 + (p.x * 0.7 - p.y * 0.9), 0.0, 1.0);
	float body = pow(lean, 2.6) * 0.30;

	// The single cool fringe. Balatro's rainbow lives here; one step is enough
	// to say "metal" without saying "hologram".
	vec3 hue = mix(tint.rgb, vec3(0.62, 0.80, 1.0), crest * 0.35);
	vec3 col = mix(hue, vec3(1.0), pow(crest, 2.0));

	// Fade at the rect's edge so the highlight belongs to the plate and does
	// not stop dead against the frame.
	float edge = smoothstep(0.52, 0.34, max(abs(p.x), abs(p.y)));

	COLOR = vec4(col, (crest * 0.75 + body) * intensity * edge);
}
"""
	_sheen_cache = sh
	return _sheen_cache


# ---------------------------------------------------------------------------
# PLINTH — the pool a subject stands in
# ---------------------------------------------------------------------------

static var _plinth_cache: Shader = null

## A soft warm pool drawn BEHIND `target`, bleeding `pad` px past it.
##
## This is what stops a portrait floating. Without a pool the plate is a bright
## rectangle on a dark field with a hard boundary all the way round, which the
## eye reads as a cut-out; with one, the same plate is a lit thing standing in a
## room. The pool is deliberately much larger than the subject and very dim —
## if you can see where it ends it is too small or too strong.
##
## `show_behind_parent`, not z_index: the parent is an opaque sibling in a
## container, and a negative z would put the pool under the whole screen. (Same
## trap the map's ink layer paid for.)
static func plinth(target: Control, tint: Color = Color(1.0, 0.56, 0.22),
		pad: float = 120.0, strength: float = 0.28) -> Control:
	if target == null or not is_instance_valid(target):
		return null
	var pool := ColorRect.new()
	pool.name = "Plinth"
	pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool.show_behind_parent = true
	pool.set_anchors_preset(Control.PRESET_FULL_RECT)
	pool.offset_left = -pad
	pool.offset_right = pad
	pool.offset_top = -pad * 0.72
	pool.offset_bottom = pad
	pool.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _plinth_shader()
	mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 1.0))
	mat.set_shader_parameter("strength", strength)
	pool.material = mat
	target.add_child(pool)
	return pool


static func _plinth_shader() -> Shader:
	if _plinth_cache != null:
		return _plinth_cache
	var sh := Shader.new()
	# Two pools, not one: a tight bright core where the subject meets the page
	# and a wide dim bloom around it. A single gaussian either haloes the whole
	# rect or does nothing, because one falloff cannot be both a contact shadow
	# and ambient bounce.
	sh.code = """shader_type canvas_item;
render_mode blend_add;

uniform vec4 tint : source_color = vec4(1.0, 0.56, 0.22, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.56)) * vec2(1.0, 1.25);
	float r = length(p) * 2.0;
	float wide = pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	float core = pow(clamp(1.0 - r * 2.1, 0.0, 1.0), 3.2);
	float a = (wide * 0.55 + core * 0.9) * strength;
	COLOR = vec4(tint.rgb, a);
}
"""
	_plinth_cache = sh
	return _plinth_cache


# ---------------------------------------------------------------------------
# INSET — the bevel that presses a tile into the page
# ---------------------------------------------------------------------------

static var _inset_cache: Shader = null

## A top-edge shadow lip and a bottom-edge light lip, drawn over a tile.
##
## One light source, up and slightly left, which is the convention every
## carved-UI style holds to and the reason a bevel reads at all: the eye decides
## "in" or "out" purely from which edge is dark. Applied as an OVERLAY child so
## it composites over whatever the tile is made of (a painting, a wash, a
## StyleBox) without any of them needing to know about it.
static func inset(target: Control, depth: float = 0.5) -> ColorRect:
	if target == null or not is_instance_valid(target):
		return null
	var lip := ColorRect.new()
	lip.name = "Inset"
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lip.set_anchors_preset(Control.PRESET_FULL_RECT)
	lip.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _inset_shader()
	mat.set_shader_parameter("depth", depth)
	lip.material = mat
	target.add_child(lip)
	return lip


static func _inset_shader() -> Shader:
	if _inset_cache != null:
		return _inset_cache
	var sh := Shader.new()
	# Normal blending with a signed colour: multiply-style darkening at the top
	# and additive-style lift at the bottom cannot be done in one pass, so the
	# lip is an ordinary alpha blend that carries black at the top and warm
	# white at the bottom. Cheaper and — measured on the tiles — indistinguishable.
	sh.code = """shader_type canvas_item;

uniform float depth : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float top = pow(clamp(1.0 - UV.y * 9.0, 0.0, 1.0), 1.6);
	float bottom = pow(clamp(1.0 - (1.0 - UV.y) * 11.0, 0.0, 1.0), 1.8);
	float side = pow(clamp(1.0 - UV.x * 13.0, 0.0, 1.0), 1.7) * 0.5;
	vec3 col = mix(vec3(1.0, 0.86, 0.62), vec3(0.0), clamp(top + side, 0.0, 1.0));
	float a = (top * 0.42 + side * 0.30 + bottom * 0.20) * depth;
	COLOR = vec4(col, a);
}
"""
	_inset_cache = sh
	return _inset_cache
