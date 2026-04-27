shader_type spatial;
// Lane surface shader. Replaces flat-color lane materials with a painterly,
// constantly-moving surface. Same color identity as before (set lane_color
// to the lane's previous albedo), but the surface now has:
//   • Procedural fBm noise that breaks up the flat color into varied tone
//   • A slow vertical flow on the noise → the lane subtly drifts
//   • A breathing pulse → overall brightness oscillates very slowly
//   • An edge vignette → lanes look inset into the table, not painted on top
//
// Apply in Inspector: replace each lane's StandardMaterial3D with a new
// ShaderMaterial that uses this shader. Set `lane_color` to the lane's
// previous color, then tweak `noise_strength` to taste (start at 0.18).
//
// Performance: 4 fBm octaves per pixel × 4 lanes = nothing. Free.

render_mode unshaded;

uniform vec4 lane_color : source_color = vec4(1.0);
uniform float noise_scale : hint_range(0.5, 30.0) = 6.0;
uniform float noise_strength : hint_range(0.0, 0.6) = 0.22;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;
uniform float pulse_speed : hint_range(0.0, 2.0) = 0.5;
uniform float pulse_strength : hint_range(0.0, 0.2) = 0.05;
uniform float edge_darken : hint_range(0.0, 1.0) = 0.30;
uniform float edge_softness : hint_range(0.5, 1.0) = 0.7;

// Mood-aware tint — reads the global "mood" uniform if registered.
// Falls back gracefully to 0 if the global isn't set up.
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
    for (int i = 0; i < 4; i++) {
        v += amp * vnoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return v;
}


void fragment() {
    vec2 uv = UV;

    // Two layers of fBm at different scales/speeds. Two layers > one because
    // the eye reads "complex motion" instead of "scrolling pattern."
    vec2 flow_uv_a = uv * noise_scale + vec2(TIME * flow_speed * 0.5, TIME * flow_speed);
    vec2 flow_uv_b = uv * noise_scale * 2.5 - vec2(TIME * flow_speed * 0.3, 0.0);
    float n = fbm(flow_uv_a) * 0.65 + fbm(flow_uv_b) * 0.35;

    // Breathing pulse — global brightness oscillation
    float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;

    // Apply noise as multiplicative variation. n in roughly [0.2, 0.8],
    // so col is multiplied by something in [1 - strength, 1 + strength].
    vec3 col = lane_color.rgb;
    col = col * mix(1.0 - noise_strength, 1.0 + noise_strength, n);
    col *= pulse;

    // Edge darkening — UV space vignette per-lane. Makes the lanes feel
    // inset, like recessed panels in the table, instead of painted decals.
    vec2 edge = abs(uv - 0.5) * 2.0;
    float edge_factor = max(edge.x, edge.y);
    edge_factor = smoothstep(edge_softness, 1.0, edge_factor);
    col *= 1.0 - edge_factor * edge_darken;

    // Mood blend — at high mood, lanes pick up warm tint
    float warm = smoothstep(0.3, 1.0, mood) * 0.4;
    col = mix(col, col * mood_tint.rgb, warm);

    ALBEDO = col;
}
