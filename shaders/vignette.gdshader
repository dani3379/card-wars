shader_type canvas_item;
// Screen-space vignette + faint film grain. Applied via a fullscreen ColorRect
// on a CanvasLayer above the 3D viewport. This is what frames the scene and
// makes the empty void around the table feel intentional.
//
// Single fullscreen quad, no read of viewport texture → essentially free.
// We're just modulating alpha based on screen position.

render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float radius : hint_range(0.1, 1.5) = 0.85;
uniform float softness : hint_range(0.1, 2.0) = 0.8;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform float grain_strength : hint_range(0.0, 0.2) = 0.025;
uniform float grain_speed : hint_range(0.0, 60.0) = 12.0;


float hash3(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract(p.x * p.y * p.z);
}


void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 c = uv - 0.5;
    // Aspect-correct radial distance so the vignette is a circle, not an oval
    c.x *= 16.0 / 9.0;
    float d = length(c);

    // Soft radial falloff
    float v = smoothstep(radius, radius + softness, d);
    float a = v * strength;

    // Tiny film grain — drives uniformly per-frame so it shimmers, not crawls
    float g = (hash3(vec3(FRAGCOORD.xy, floor(TIME * grain_speed))) - 0.5) * grain_strength;

    COLOR = vec4(vignette_color.rgb + g, a + abs(g) * 0.5);
}
