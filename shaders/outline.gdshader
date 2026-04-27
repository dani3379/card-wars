shader_type spatial;
// Inverted-hull outline. Used as a `next_pass` on the main toon material,
// so the same mesh renders twice: front faces with toon, then back faces
// expanded outward along normals in solid black. Cheap and gives the
// thick cartoon ink line that defines the Card Wars / Adventure Time look.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.06, 0.04, 0.10, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.006;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
