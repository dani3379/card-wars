shader_type spatial;
// Procedural walnut wood-grain. Replaces flat brown plane that read as plastic.
// Built from three layers:
//   1. fBm warp along the grain direction → the long parallel grain lines
//   2. Sparse rings/whorls noise → knots and tonal variation
//   3. Subtle low-frequency brightness drift → the surface isn't uniformly lit
//
// All procedural, no textures needed. Two octaves of fBm at the table's
// scale = trivial cost.

render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec4 wood_dark : source_color = vec4(0.08, 0.05, 0.035, 1.0);
uniform vec4 wood_mid  : source_color = vec4(0.18, 0.11, 0.07, 1.0);
uniform vec4 wood_light : source_color = vec4(0.30, 0.20, 0.13, 1.0);

uniform float grain_scale : hint_range(2.0, 80.0) = 22.0;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.55;
uniform float grain_warp : hint_range(0.0, 2.0) = 0.6;

uniform float ring_scale : hint_range(0.5, 8.0) = 2.5;
uniform float ring_strength : hint_range(0.0, 1.0) = 0.35;

uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float rough : hint_range(0.0, 1.0) = 0.85;


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
        p *= 2.07;
        amp *= 0.5;
    }
    return v;
}


void fragment() {
    vec2 uv = UV;

    // Warp the UV before sampling the grain so grain lines aren't perfectly
    // straight — they wave like real wood instead of looking like a barcode.
    vec2 warp = vec2(fbm(uv * 3.0) - 0.5, fbm(uv * 3.0 + 17.3) - 0.5) * grain_warp;
    vec2 wuv = uv + warp;

    // Anisotropic sample: stretch UV along Y so the noise reads as long
    // parallel grain lines along X, not isotropic blobs.
    float grain = fbm(vec2(wuv.x * grain_scale, wuv.y * grain_scale * 0.12));
    // Squash the grain into a darker line every period — that's what the eye
    // reads as "wood grain"
    grain = abs(grain - 0.5) * 2.0;
    grain = pow(grain, 1.6);

    // Rings/whorls — sparse, low-frequency, multiplied in for tonal depth
    float rings = fbm(wuv * ring_scale);

    // Three-stop ramp: dark grain lines → mid wood → highlight
    vec3 col = mix(wood_dark.rgb, wood_mid.rgb, smoothstep(0.0, 0.6, rings));
    col = mix(col, wood_light.rgb, smoothstep(0.65, 1.0, rings) * 0.6);
    // Apply grain as darkening
    col = mix(col, wood_dark.rgb, grain * grain_strength);

    // Tiny per-pixel sparkle from the underlying noise — keeps the surface
    // from looking dead flat under the bloomed candlelight
    float sparkle = vnoise(uv * 600.0) * 0.04;
    col += vec3(sparkle * 0.5, sparkle * 0.4, sparkle * 0.3);

    ALBEDO = col;
    METALLIC = metal;
    ROUGHNESS = rough;
}
