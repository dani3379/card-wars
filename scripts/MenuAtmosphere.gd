extends Node
class_name MenuAtmosphere
## MenuAtmosphere.gd — small helper that adds a grimoire-style background to
## any menu Control: warm vertical gradient, edge vignette, drifting embers
## and dust motes. Call MenuAtmosphere.attach_to(self) from a menu's _ready().
##
## All assets are procedural so the project doesn't need image files.

# Builds the visuals as children of `host` and inserts them at the bottom of
# the child list so existing UI sits on top.
static func attach_to(host: Control) -> void:
	_add_gradient_background(host)
	_add_vignette(host)
	_add_dust_layer(host)
	_add_ember_layer(host)


static func _add_gradient_background(host: Control) -> void:
	# Replace any existing flat ColorRect named "Background" with a vertical
	# gradient TextureRect that sits behind everything else.
	var bg = TextureRect.new()
	bg.name = "GrimoireBackground"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.06, 0.04, 0.07),    # deep purple-black at top
		Color(0.10, 0.05, 0.05),    # ember-tinted middle
		Color(0.04, 0.02, 0.03),    # near-black at bottom
	])
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gtex = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	gtex.width = 16
	gtex.height = 512
	bg.texture = gtex

	host.add_child(bg)
	host.move_child(bg, 0)

	# Hide any flat-colour Background ColorRect that the .tscn may have shipped.
	var legacy = host.get_node_or_null("Background")
	if legacy is ColorRect:
		legacy.visible = false


static func _add_vignette(host: Control) -> void:
	# Radial darkening at the edges.
	var v = TextureRect.new()
	v.name = "Vignette"
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grad = Gradient.new()
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.55),
		Color(0, 0, 0, 0.85),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.85, 1.0])
	var gtex = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 1.0)
	gtex.width = 512
	gtex.height = 512
	v.texture = gtex

	host.add_child(v)
	host.move_child(v, 1)


static func _add_dust_layer(host: Control) -> void:
	# Slow ambient dust drifting upward across the whole screen.
	var p = GPUParticles2D.new()
	p.name = "MenuDust"
	p.amount = 60
	p.lifetime = 8.0
	p.preprocess = 4.0

	var pmat = ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.05, -1, 0)
	pmat.spread = 25.0
	pmat.initial_velocity_min = 8.0
	pmat.initial_velocity_max = 22.0
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.6
	pmat.scale_max = 1.6
	pmat.color = Color(0.95, 0.85, 0.65, 0.35)
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Default viewport ~1600x900; emit from a band along the bottom.
	pmat.emission_box_extents = Vector3(900, 8, 0)
	p.process_material = pmat
	p.texture = _make_soft_dot_texture(8, Color(1, 0.95, 0.8))
	p.position = Vector2(800, 920)

	host.add_child(p)


static func _add_ember_layer(host: Control) -> void:
	# Brighter, faster, warmer particles rising from the bottom corners.
	var p = GPUParticles2D.new()
	p.name = "MenuEmbers"
	p.amount = 35
	p.lifetime = 4.5
	p.preprocess = 2.0

	var pmat = ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.2, -1, 0)
	pmat.spread = 35.0
	pmat.initial_velocity_min = 25.0
	pmat.initial_velocity_max = 55.0
	pmat.gravity = Vector3.ZERO
	pmat.scale_min = 0.4
	pmat.scale_max = 1.2
	pmat.color = Color(1.0, 0.55, 0.2, 0.85)
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(900, 4, 0)
	p.process_material = pmat
	p.texture = _make_soft_dot_texture(6, Color(1, 0.6, 0.25))
	p.position = Vector2(800, 920)

	host.add_child(p)


# Build a small radial-falloff dot texture so particles look like glow points
# instead of hard pixels.
static func _make_soft_dot_texture(radius: int, tint: Color) -> ImageTexture:
	var size = radius * 2
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(radius, radius)
	for y in size:
		for x in size:
			var d = Vector2(x, y).distance_to(center) / float(radius)
			var a = clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # softer falloff
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a))
	return ImageTexture.create_from_image(img)


# Apply a warm-button stylebox to a Button. Call after _ready().
static func style_button(btn: Button, primary: bool = false) -> void:
	var bg = Color(0.18, 0.10, 0.14) if primary else Color(0.13, 0.10, 0.12)
	var bg_hover = Color(0.32, 0.18, 0.18) if primary else Color(0.22, 0.16, 0.18)
	var border = Color(0.85, 0.62, 0.30) if primary else Color(0.55, 0.42, 0.28)
	var text_color = Color(1.0, 0.88, 0.65) if primary else Color(0.85, 0.78, 0.65)

	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s = StyleBoxFlat.new()
		s.bg_color = bg_hover if state_name == "hover" or state_name == "pressed" else bg
		s.border_color = border
		s.set_border_width_all(2)
		s.corner_radius_top_left = 4
		s.corner_radius_top_right = 4
		s.corner_radius_bottom_left = 4
		s.corner_radius_bottom_right = 4
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 10
		s.content_margin_bottom = 10
		btn.add_theme_stylebox_override(state_name, s)

	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.7))
	btn.add_theme_color_override("font_pressed_color", Color(1, 0.9, 0.6))
