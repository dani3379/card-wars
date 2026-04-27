shader_type spatial;
// Stylized cel shader with proper light response, rim lighting, and a
// global "mood" uniform that bleeds the surface toward warm/desat as the
// match progresses from afternoon meadow to burning grimoire.
//
// Use as the front-pass material; pair with outline.gdshader as next_pass
// (the inverted-hull outline keeps the Card Wars / Adventure Time ink line).
//
// REQUIRED: register `mood` as a global float in
//   Project Settings → Shader Globals (default 0.0).
// Otherwise the shader falls back to mood = 0 and looks fine, just static.

global uniform float mood;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float saturation_boost : hint_range(0.5, 2.5) = 1.15;

// Cel bands. 2 = harsh Adventure Time. 4 = softer. ambient_floor stops
// surfaces from going pitch black in shadow — we always want some ambient.
uniform float bands : hint_range(2.0, 8.0) = 3.0;
uniform float ambient_floor : hint_range(0.0, 0.6) = 0.40;

// Rim catches the silhouette in the dominant light's color.
uniform vec4 rim_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float rim_width : hint_range(0.0, 1.0) = 0.30;

// Mood drives a warm color shift and a partial desaturation. At mood=0
// the surface is unchanged; at mood=1 it leans toward mood_tint and loses
// saturation, isolating the fire colors that survive the desat.
uniform vec4 mood_tint : source_color = vec4(1.0, 0.50, 0.30, 1.0);
uniform float mood_tint_strength : hint_range(0.0, 1.0) = 0.50;
uniform float mood_desat : hint_range(0.0, 1.0) = 0.30;


void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 col = tex.rgb * albedo.rgb;

	// Saturation boost (per-material, art direction)
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(gray), col, saturation_boost);

	// Mood-driven warm tint (smoothstep so daytime stays clean)
	float warm = smoothstep(0.25, 1.0, mood) * mood_tint_strength;
	col = mix(col, col * mood_tint.rgb, warm);

	// Mood-driven partial desaturation (the world losing color as it burns)
	float desat = mix(1.0, 1.0 - mood_desat, mood);
	col = mix(vec3(gray), col, desat);

	ALBEDO = col;
}


void light() {
	// Stepped diffuse — the cel band
	float ndotl = max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION;
	float stepped = max(floor(ndotl * bands) / bands, ambient_floor);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * stepped;

	// Rim (Fresnel) — only fires where the surface is somewhat lit, so
	// the rim isn't visible on the back of unlit objects
	float ndotv = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = smoothstep(1.0 - rim_width, 1.0, ndotv) * stepped;
	SPECULAR_LIGHT += rim_color.rgb * rim * rim_color.a;
}
