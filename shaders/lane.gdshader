shader_type spatial;
// Lane surface — recessed parchment panel with a faint sigil etched into it.
// Replaces the previous neon rainbow with a muted ink-on-parchment palette,
// per-lane sigil, and a soft pulse so each lane feels alive but never noisy.
//
// Apply as a ShaderMaterial on each lane MeshInstance3D. Set:
//   • lane_color    — the lane's identity tint (kept restrained by the shader)
//   • sigil_index   — 0=forge, 1=grove, 2=void, 3=tide
// Everything else has reasonable defaults.

// Lit so the candles cast warm light onto the lanes — at high roughness with
// no metallic so the surface reads as matte parchment, not plastic.
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled;

uniform vec4 lane_color : source_color = vec4(0.55, 0.42, 0.10, 1.0);
uniform vec4 ink_color  : source_color = vec4(0.04, 0.03, 0.05, 1.0);
uniform vec4 parchment  : source_color = vec4(0.20, 0.16, 0.13, 1.0);

uniform int sigil_index : hint_range(0, 3) = 0;
uniform float sigil_strength : hint_range(0.0, 1.0) = 0.55;

uniform float grain_scale : hint_range(2.0, 30.0) = 8.0;
uniform float grain_strength : hint_range(0.0, 0.6) = 0.18;

uniform float pulse_speed : hint_range(0.0, 2.0) = 0.45;
uniform float pulse_strength : hint_range(0.0, 0.2) = 0.04;

uniform float edge_darken : hint_range(0.0, 1.0) = 0.55;
uniform float edge_softness : hint_range(0.5, 1.0) = 0.78;

global uniform float mood;
uniform vec4 mood_tint : source_color = vec4(1.0, 0.4, 0.2, 1.0);


float hash2(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}


float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {
        v += amp * vnoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return v;
}


// — Sigil shapes. Each returns a soft mask in [0,1] where the sigil sits.
// Shapes are drawn in the lane's UV space, centered on (0.5, 0.5).

// Helper: smooth "inside" mask — 1 when value <= inner, 0 when value >= outer.
// Standard "1 - smoothstep" because GLSL smoothstep is undefined for edge0>edge1.
float inside(float value, float inner, float outer) {
    return 1.0 - smoothstep(inner, outer, value);
}


float forge_sigil(vec2 uv) {
    // Anvil silhouette: a horizontal bar with a tapered base
    vec2 p = (uv - vec2(0.5, 0.5)) * vec2(1.0, 3.5);
    float bar = inside(abs(p.y - 0.05), 0.16, 0.18)
              * inside(abs(p.x), 0.40, 0.42);
    float taper = inside(abs(p.x) + abs(p.y + 0.18) * 1.3, 0.0, 0.30) * 0.6;
    return clamp(bar + taper, 0.0, 1.0);
}


float grove_sigil(vec2 uv) {
    // Six-petal flower / leaf cluster — radial cosine
    vec2 p = (uv - vec2(0.5, 0.5)) * vec2(1.0, 3.5);
    float r = length(p);
    float a = atan(p.y, p.x);
    float petals = 0.5 + 0.5 * cos(a * 6.0);
    float shape = inside(r / max(petals, 0.05), 0.10, 0.35);
    float center = inside(r, 0.0, 0.05);
    return clamp(shape + center * 0.6, 0.0, 1.0);
}


float void_sigil(vec2 uv) {
    // Four-pointed star / cross
    vec2 p = (uv - vec2(0.5, 0.5)) * vec2(1.0, 3.5);
    float d1 = abs(p.x) + abs(p.y);
    float d2 = abs(p.x - p.y) + abs(p.x + p.y);
    float star = inside(min(d1, d2), 0.18, 0.32);
    float core = inside(length(p), 0.0, 0.04);
    return clamp(star * 0.7 + core, 0.0, 1.0);
}


float tide_sigil(vec2 uv) {
    // Three stacked sine waves
    vec2 p = (uv - vec2(0.5, 0.5)) * vec2(1.0, 3.5);
    float w = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float y = sin(p.x * 7.0 + fi * 1.7) * 0.07 + (fi - 1.0) * 0.13;
        w = max(w, inside(abs(p.y - y), 0.0, 0.025));
    }
    return w * inside(abs(p.x), 0.30, 0.45);
}


float pick_sigil(vec2 uv, int idx) {
    if (idx == 0) return forge_sigil(uv);
    if (idx == 1) return grove_sigil(uv);
    if (idx == 2) return void_sigil(uv);
    return tide_sigil(uv);
}


void fragment() {
    vec2 uv = UV;

    // Parchment grain — subtle multiplicative variation
    float n = fbm(uv * grain_scale);
    n = mix(0.85, 1.15, n);

    // Mix the lane tint into the parchment base. The lane keeps its identity
    // color but it's no longer dominant — it tints, doesn't shout.
    vec3 base = mix(parchment.rgb, lane_color.rgb, 0.55);
    base *= n * (1.0 + sin(TIME * pulse_speed + float(sigil_index) * 1.3) * pulse_strength);

    // Sigil etched in ink. Sampled with lateral wobble so it reads hand-drawn,
    // not stenciled.
    float sig = pick_sigil(uv, sigil_index);
    // Slight edge irregularity
    float edge_jitter = (vnoise(uv * 80.0) - 0.5) * 0.06;
    sig = clamp(sig + edge_jitter, 0.0, 1.0);
    sig = pow(sig, 1.5);

    vec3 col = mix(base, ink_color.rgb, sig * sigil_strength);

    // Edge vignette per-lane: makes lanes feel inset
    vec2 edge = abs(uv - 0.5) * 2.0;
    float edge_factor = max(edge.x, edge.y);
    edge_factor = smoothstep(edge_softness, 1.0, edge_factor);
    col *= 1.0 - edge_factor * edge_darken;

    // Mood: at high mood, lanes pick up warm tint
    float warm = smoothstep(0.3, 1.0, mood) * 0.4;
    col = mix(col, col * mood_tint.rgb, warm);

    ALBEDO = col;
    ROUGHNESS = 0.95;
    METALLIC = 0.0;
}
