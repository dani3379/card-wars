shader_type spatial;
// Card front. Replaces flat HSV-tinted plane with:
//   • Aged-parchment base (procedural noise → tonal variation)
//   • Faction tint zone at the top (the lane / element band)
//   • Gilded gold inner border that follows a rounded-rect shape
//   • Faint vellum stains and edge wear
//
// The art panel and stat labels are still added as separate Label3D / Quad
// nodes by the script — this shader only paints the card body itself.
//
// Use as a ShaderMaterial on the card's main mesh. Pair with outline shader
// as next_pass for the inverted-hull ink line.

render_mode cull_back, depth_draw_opaque;

// We pass the surface-normal direction from vertex to fragment so the shader
// can render the top face with full parchment + gilt + corner-rounding logic
// while the side faces just render solid gilt edge (no discard, no UVs).
varying float v_top_face;

uniform vec4 faction_color : source_color = vec4(0.55, 0.42, 0.10, 1.0);
uniform vec4 parchment_light : source_color = vec4(0.72, 0.62, 0.45, 1.0);
uniform vec4 parchment_dark : source_color = vec4(0.48, 0.38, 0.26, 1.0);
uniform vec4 gilt_color : source_color = vec4(0.78, 0.62, 0.28, 1.0);
uniform vec4 ink_color : source_color = vec4(0.05, 0.04, 0.06, 1.0);

// Geometry cues. Card meshes are wide-thin boxes; UVs cover the top face.
uniform float border_width : hint_range(0.005, 0.08) = 0.030;
uniform float gilt_width : hint_range(0.001, 0.03) = 0.008;
uniform float corner_radius : hint_range(0.0, 0.20) = 0.06;

// Top "faction band" — a horizontal stripe of faction_color at the top
uniform float band_height : hint_range(0.0, 0.4) = 0.18;
uniform float band_softness : hint_range(0.0, 0.1) = 0.015;

uniform float stain_strength : hint_range(0.0, 0.6) = 0.25;
uniform float wear_strength : hint_range(0.0, 0.5) = 0.18;


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


// Signed distance to a rounded rectangle centered at (0.5, 0.5) with given
// half-extents and corner radius. Negative inside, positive outside.
float sd_rounded_rect(vec2 uv, vec2 half_extent, float radius) {
    vec2 p = abs(uv - 0.5) - (half_extent - vec2(radius));
    return length(max(p, 0.0)) - radius + min(max(p.x, p.y), 0.0);
}


void vertex() {
    // BoxMesh: top face has NORMAL.y near +1, bottom near -1, sides near 0.
    // Only the top face does the parchment/corner-rounding work.
    v_top_face = step(0.5, NORMAL.y);
}


void fragment() {
    // Side and bottom faces: render solid dark gilt edge so the card looks
    // like a card stock card seen edge-on, with no UV-driven discards.
    if (v_top_face < 0.5) {
        ALBEDO = gilt_color.rgb * 0.35;
        METALLIC = 0.4;
        ROUGHNESS = 0.55;
        return;
    }

    vec2 uv = UV;

    // Distance to the card's outer edge in UV space. UV runs 0..1; the card's
    // half-extent is 0.5 in UV space. We use this to drive border, gilt and
    // corner shaping.
    float d_outer = sd_rounded_rect(uv, vec2(0.5), corner_radius);

    // Discard outside the rounded-rect silhouette so the card has rounded
    // corners despite being a square mesh.
    if (d_outer > 0.0) {
        discard;
    }

    // Aged parchment: two octaves of fBm at different scales.
    float n_macro = fbm(uv * 3.5);
    float n_micro = fbm(uv * 22.0);
    vec3 base = mix(parchment_dark.rgb, parchment_light.rgb,
                    smoothstep(0.2, 0.8, n_macro));
    base *= mix(0.92, 1.06, n_micro);

    // Faction band at the top of the card. UV.y = 0 at top, 1 at bottom in
    // the BoxMesh top-face layout — band_top is 1 inside the band, 0 outside.
    float band_top = 1.0 - smoothstep(band_height - band_softness,
                                      band_height + band_softness, uv.y);
    base = mix(base, mix(base, faction_color.rgb, 0.85), band_top);

    // Faint stains — sparse, soft brown blotches
    float stains = pow(fbm(uv * 6.0 + 13.7), 4.0);
    base = mix(base, parchment_dark.rgb * 0.7, stains * stain_strength);

    // Edge wear — increased darkening close to the silhouette edge
    float edge_dist = -d_outer;  // 0 at edge, larger inside
    float wear = 1.0 - smoothstep(0.0, 0.05, edge_dist);
    base = mix(base, ink_color.rgb, wear * wear_strength);

    // Gilded inner border. Fires in a thin band starting `border_width` in
    // from the silhouette edge.
    float border_dist = -d_outer - border_width;  // 0 at gilt center
    float gilt = 1.0 - smoothstep(0.0, gilt_width * 0.5, abs(border_dist));
    // Subtle anisotropic shimmer along the border
    float shimmer = vnoise(uv * 80.0) * 0.25 + 0.75;
    vec3 with_gilt = mix(base, gilt_color.rgb * shimmer, gilt);

    // Outer ink line, sits just outside the gilt
    float ink_dist = -d_outer - 0.003;
    float ink = 1.0 - smoothstep(0.0, 0.005, abs(ink_dist));
    with_gilt = mix(with_gilt, ink_color.rgb, ink * 0.85);

    ALBEDO = with_gilt;
    METALLIC = gilt * 0.7;
    ROUGHNESS = mix(0.85, 0.30, gilt);
}
