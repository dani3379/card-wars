extends Node

# ── Fonts ──
var font_display: Font = null
var font_body: Font = null

# ── Textures ──
var tex_card_frame: Texture2D = null
var tex_card_frame_ornate: Texture2D = null
var tex_panel_bg: Texture2D = null
var tex_panel_ornate: Texture2D = null
var tex_icon_sword: Texture2D = null
var tex_icon_heart: Texture2D = null
var tex_icon_shield: Texture2D = null
var tex_icon_diamond: Texture2D = null
var tex_icon_skull: Texture2D = null
var tex_icon_fire: Texture2D = null
var tex_icon_crown: Texture2D = null
var tex_icon_book: Texture2D = null

const NINEPATCH_MARGIN := 18

func _ready() -> void:
	_load_assets()

func _load_assets() -> void:
	font_display = load("res://assets/fonts/PirataOne-Regular.ttf")
	font_body = load("res://assets/fonts/Nunito-Regular.ttf")
	tex_card_frame = load("res://assets/ui/card_frame.png")
	var ornate_path = "res://assets/ui/card_frame_ornate.png"
	if ResourceLoader.exists(ornate_path):
		tex_card_frame_ornate = load(ornate_path)
	tex_panel_bg = load("res://assets/ui/panel_bg.png")
	tex_panel_ornate = load("res://assets/ui/panel_ornate.png")
	tex_icon_sword = load("res://assets/icons/sword.png")
	tex_icon_heart = load("res://assets/icons/heart.png")
	tex_icon_shield = load("res://assets/icons/shield.png")
	tex_icon_diamond = load("res://assets/icons/diamond.png")
	tex_icon_skull = load("res://assets/icons/skull.png")
	tex_icon_fire = load("res://assets/icons/fire.png")
	tex_icon_crown = load("res://assets/icons/crown.png")
	tex_icon_book = load("res://assets/icons/book.png")


# ── Color Palette ──
const PARCHMENT      := Color(0.12, 0.09, 0.07, 0.94)
const PARCHMENT_LITE := Color(0.16, 0.13, 0.10, 0.92)
const PARCHMENT_BORDER := Color(0.60, 0.45, 0.22, 1.0)
const GILT           := Color(0.82, 0.66, 0.30, 1.0)
const GILT_BRIGHT    := Color(1.0, 0.88, 0.35, 1.0)
const IVORY          := Color(0.96, 0.92, 0.78, 1.0)
const BLOOD_RED      := Color(0.85, 0.22, 0.18, 1.0)
const MANA_BLUE      := Color(0.35, 0.58, 0.95, 1.0)
const MANA_BLUE_DIM  := Color(0.12, 0.16, 0.30, 1.0)
const HEALTH_GREEN   := Color(0.25, 0.85, 0.35, 1.0)
const HEALTH_BAR_BG  := Color(0.12, 0.07, 0.05, 0.95)
const ATK_RED        := Color(1.0, 0.35, 0.25, 1.0)
const ATK_BUFFED     := Color(1.0, 0.8, 0.2, 1.0)
const HP_DAMAGED     := Color(1.0, 0.3, 0.3, 1.0)
const SPELL_PURPLE   := Color(0.70, 0.55, 0.95, 1.0)
const KEYWORD_GOLD   := Color(1.0, 0.85, 0.45, 1.0)
const DESC_DIM       := Color(0.78, 0.74, 0.62, 1.0)
const FLOOP_BLUE     := Color(0.30, 0.70, 0.95, 1.0)
const BOARD_BG       := Color(0.075, 0.065, 0.055, 1.0)
const BOARD_TOP      := Color(0.10, 0.055, 0.045, 1.0)
const BOARD_BOT      := Color(0.06, 0.075, 0.055, 1.0)
const LANE_BORDER    := Color(0.38, 0.28, 0.15, 0.85)
const DIMMED         := Color(0.50, 0.50, 0.50, 0.70)
const RARITY_COMMON  := Color(0.75, 0.75, 0.75, 1.0)
const RARITY_UNCOMMON := Color(0.40, 0.60, 0.95, 1.0)
const RARITY_RARE    := Color(0.95, 0.78, 0.22, 1.0)
const RARITY_STARTER := Color(0.55, 0.55, 0.55, 1.0)

# ── Font Sizes ──
const FONT_HEADER := 26
const FONT_SUBHEADER := 19
const FONT_BODY := 15
const FONT_SMALL := 12
const FONT_STAT := 22
const FONT_COST := 17
const FONT_TITLE := 34
const FONT_CARD_NAME := 14

# ── Card Dimensions ──
const CARD_SIZE := Vector2(150, 200)
const CARD_BORDER := 2
const CARD_CORNER := 8

# ── Node map icons ──
const MAP_ICONS: Dictionary = {
	"combat": "⚔", "elite": "★", "boss": "☠",
	"rest": "♨", "shop": "🪙", "event": "?",
}


# ═══════════════════════════════════════════
#  STYLEBOX FACTORIES
# ═══════════════════════════════════════════

static func make_panel_style(bg: Color = PARCHMENT, border: Color = PARCHMENT_BORDER,
		border_w: int = 2, corner: int = 6, shadow: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = border_w
	s.border_width_bottom = border_w
	s.border_width_left = border_w
	s.border_width_right = border_w
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
	return s


static func make_card_style(bg: Color, border: Color = GILT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = CARD_BORDER
	s.border_width_bottom = CARD_BORDER
	s.border_width_left = CARD_BORDER
	s.border_width_right = CARD_BORDER
	s.corner_radius_top_left = CARD_CORNER
	s.corner_radius_top_right = CARD_CORNER
	s.corner_radius_bottom_left = CARD_CORNER
	s.corner_radius_bottom_right = CARD_CORNER
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func make_btn_style(bg: Color, border: Color = GILT, corner: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_top = 2
	s.border_width_bottom = 2
	s.border_width_left = 2
	s.border_width_right = 2
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	return s


static func make_slot_style(is_enemy: bool, lane_idx: int) -> StyleBoxFlat:
	# Slots must be clearly visible — alternating brightness per lane
	var base_alpha = 0.10 if lane_idx % 2 == 0 else 0.15
	var tint: Color
	if is_enemy:
		tint = Color(0.22, 0.08, 0.06, base_alpha)
	else:
		tint = Color(0.06, 0.14, 0.08, base_alpha)
	var s := StyleBoxFlat.new()
	s.bg_color = tint
	s.border_color = LANE_BORDER
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	# Inner padding so cards don't press against slot edges
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


# ═══════════════════════════════════════════
#  BUTTON FACTORY
# ═══════════════════════════════════════════

static func make_themed_button(text: String, bg: Color, min_size: Vector2 = Vector2(160, 44),
		font_size: int = FONT_BODY, tooltip: String = "") -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.78))
	btn.add_theme_color_override("font_disabled_color", Color(0.7, 0.65, 0.55, 0.6))
	var normal = make_btn_style(bg)
	btn.add_theme_stylebox_override("normal", normal)
	var hover = normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = bg.darkened(0.40)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)
	return btn


# ═══════════════════════════════════════════
#  LABEL FACTORY
# ═══════════════════════════════════════════

static func make_label(text: String, font_size: int = FONT_BODY, color: Color = IVORY,
		outline: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline:
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		lbl.add_theme_constant_override("outline_size", 3)
	return lbl


# ═══════════════════════════════════════════
#  HP BAR FACTORY
# ═══════════════════════════════════════════

static func make_hp_bar(current: int, max_hp: int, width: float = 150.0, height: float = 24.0,
		fill_color: Color = BLOOD_RED) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(width, height)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Outer frame — rounded border
	var frame := Panel.new()
	frame.size = Vector2(width, height)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = HEALTH_BAR_BG
	frame_style.border_color = Color(0.35, 0.25, 0.15, 0.8)
	frame_style.border_width_top = 1
	frame_style.border_width_bottom = 1
	frame_style.border_width_left = 1
	frame_style.border_width_right = 1
	frame_style.corner_radius_top_left = 4
	frame_style.corner_radius_top_right = 4
	frame_style.corner_radius_bottom_left = 4
	frame_style.corner_radius_bottom_right = 4
	frame.add_theme_stylebox_override("panel", frame_style)
	container.add_child(frame)
	# Fill — inset 1px so it doesn't cover the border
	var fill := Panel.new()
	fill.name = "Fill"
	var ratio = clampf(float(current) / float(max_hp), 0.0, 1.0)
	fill.position = Vector2(1, 1)
	fill.size = Vector2((width - 2) * ratio, height - 2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	fill.add_theme_stylebox_override("panel", fill_style)
	container.add_child(fill)
	# Highlight strip at top of fill — gives a gloss/depth feel
	var gloss := ColorRect.new()
	gloss.position = Vector2(1, 1)
	gloss.size = Vector2((width - 2) * ratio, maxf(3.0, height * 0.2))
	gloss.color = Color(1, 1, 1, 0.12)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(gloss)
	# Text overlay
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = "%d / %d" % [current, max_hp]
	lbl.size = Vector2(width, height)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", IVORY)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(lbl)
	return container


# ═══════════════════════════════════════════
#  MANA PIP FACTORY
# ═══════════════════════════════════════════

static func make_mana_pips(current: int, max_mana: int, pip_size: float = 20.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(max_mana):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(pip_size, pip_size)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pip_style := StyleBoxFlat.new()
		var r := int(pip_size * 0.5)
		pip_style.corner_radius_top_left = r
		pip_style.corner_radius_top_right = r
		pip_style.corner_radius_bottom_left = r
		pip_style.corner_radius_bottom_right = r
		if i < current:
			pip_style.bg_color = MANA_BLUE
			pip_style.border_color = Color(0.55, 0.75, 1.0, 0.6)
			# Inner glow — brighter top half via shadow trick
			pip_style.shadow_color = Color(0.5, 0.7, 1.0, 0.25)
			pip_style.shadow_size = 3
		else:
			pip_style.bg_color = MANA_BLUE_DIM
			pip_style.border_color = Color(0.25, 0.30, 0.45, 0.5)
		pip_style.border_width_top = 1
		pip_style.border_width_bottom = 1
		pip_style.border_width_left = 1
		pip_style.border_width_right = 1
		pip.add_theme_stylebox_override("panel", pip_style)
		row.add_child(pip)
	return row


# ═══════════════════════════════════════════
#  RARITY HELPERS
# ═══════════════════════════════════════════

static func rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return RARITY_COMMON
		"uncommon": return RARITY_UNCOMMON
		"rare": return RARITY_RARE
		"starter": return RARITY_STARTER
		_: return RARITY_COMMON


# ═══════════════════════════════════════════
#  ATMOSPHERE SYSTEM
# ═══════════════════════════════════════════
# Layered mood lighting: vignette + gradient shader, ambient particles,
# decorative corner frame.  Each screen type gets its own palette.

const SCREEN_MOODS: Dictionary = {
	"main_menu": {
		"grad_inner": Color(0.10, 0.06, 0.08, 0.30),
		"grad_outer": Color(0.02, 0.01, 0.03, 0.65),
		"vignette": 0.55,
		"particle_color": Color(1.0, 0.82, 0.35, 0.45),
		"particle_alt": Color(1.0, 0.60, 0.20, 0.25),
		"particle_count": 35,
		"particle_speed": 12.0,
		"frame_color": Color(0.65, 0.50, 0.25, 0.28),
	},
	"map": {
		"grad_inner": Color(0.08, 0.06, 0.10, 0.25),
		"grad_outer": Color(0.02, 0.01, 0.04, 0.60),
		"vignette": 0.50,
		"particle_color": Color(0.70, 0.60, 0.45, 0.30),
		"particle_alt": Color(0.50, 0.45, 0.35, 0.15),
		"particle_count": 20,
		"particle_speed": 8.0,
		"frame_color": Color(0.55, 0.42, 0.22, 0.22),
	},
	"combat": {
		"grad_inner": Color(0.10, 0.06, 0.04, 0.25),
		"grad_outer": Color(0.02, 0.01, 0.01, 0.55),
		"vignette": 0.40,
		"particle_color": Color(1.0, 0.50, 0.18, 0.35),
		"particle_alt": Color(1.0, 0.28, 0.08, 0.20),
		"particle_count": 20,
		"particle_speed": 18.0,
		"frame_color": Color(0.50, 0.30, 0.15, 0.20),
	},
	"shop": {
		"grad_inner": Color(0.12, 0.09, 0.05, 0.30),
		"grad_outer": Color(0.03, 0.02, 0.01, 0.60),
		"vignette": 0.45,
		"particle_color": Color(1.0, 0.85, 0.40, 0.35),
		"particle_alt": Color(0.90, 0.70, 0.25, 0.20),
		"particle_count": 25,
		"particle_speed": 10.0,
		"frame_color": Color(0.65, 0.50, 0.22, 0.28),
	},
	"rest": {
		"grad_inner": Color(0.05, 0.10, 0.07, 0.25),
		"grad_outer": Color(0.01, 0.03, 0.02, 0.60),
		"vignette": 0.45,
		"particle_color": Color(0.40, 0.85, 0.55, 0.30),
		"particle_alt": Color(0.30, 0.65, 0.80, 0.20),
		"particle_count": 18,
		"particle_speed": 6.0,
		"frame_color": Color(0.30, 0.55, 0.35, 0.25),
	},
	"event": {
		"grad_inner": Color(0.08, 0.05, 0.12, 0.30),
		"grad_outer": Color(0.02, 0.01, 0.05, 0.65),
		"vignette": 0.50,
		"particle_color": Color(0.70, 0.50, 0.95, 0.35),
		"particle_alt": Color(0.55, 0.35, 0.80, 0.20),
		"particle_count": 22,
		"particle_speed": 10.0,
		"frame_color": Color(0.50, 0.35, 0.60, 0.25),
	},
	"reward": {
		"grad_inner": Color(0.12, 0.10, 0.06, 0.30),
		"grad_outer": Color(0.03, 0.02, 0.02, 0.60),
		"vignette": 0.45,
		"particle_color": Color(1.0, 0.90, 0.45, 0.45),
		"particle_alt": Color(1.0, 0.75, 0.25, 0.30),
		"particle_count": 30,
		"particle_speed": 14.0,
		"frame_color": Color(0.65, 0.55, 0.25, 0.30),
	},
	"game_over": {
		"grad_inner": Color(0.06, 0.03, 0.05, 0.25),
		"grad_outer": Color(0.01, 0.00, 0.02, 0.70),
		"vignette": 0.60,
		"particle_color": Color(0.60, 0.40, 0.40, 0.25),
		"particle_alt": Color(0.40, 0.25, 0.30, 0.15),
		"particle_count": 15,
		"particle_speed": 5.0,
		"frame_color": Color(0.40, 0.30, 0.25, 0.20),
	},
}


static var _atmosphere_shader: Shader = null


static func _get_atmosphere_shader() -> Shader:
	if _atmosphere_shader == null:
		_atmosphere_shader = Shader.new()
		_atmosphere_shader.code = ("shader_type canvas_item;\n"
			+ "uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;\n"
			+ "uniform vec4 grad_inner : source_color;\n"
			+ "uniform vec4 grad_outer : source_color;\n"
			+ "void fragment() {\n"
			+ "  vec2 uv = UV - 0.5;\n"
			+ "  float dist = length(uv) * 2.0;\n"
			+ "  float t = smoothstep(0.0, 1.3, dist);\n"
			+ "  vec4 grad = mix(grad_inner, grad_outer, t);\n"
			+ "  float vig = smoothstep(0.4, 1.4, dist) * vignette_strength;\n"
			+ "  float grain = fract(sin(dot(UV * 500.0, vec2(12.9898, 78.233))) * 43758.5453) * 0.015 - 0.0075;\n"
			+ "  vec3 col = grad.rgb * (1.0 - vig * 0.5) + grain;\n"
			+ "  float a = grad.a + vig * (1.0 - grad.a);\n"
			+ "  COLOR = vec4(col, a);\n"
			+ "}\n")
	return _atmosphere_shader


## Adds vignette + gradient overlay, ambient particles, and decorative frame.
## Call once in _ready() — survives _build_ui() if cleanup preserves "Atmosphere".
static func add_atmosphere(parent: Control, screen_type: String,
		include_frame: bool = true) -> void:
	if parent.has_node("Atmosphere"):
		return
	var mood = SCREEN_MOODS.get(screen_type, SCREEN_MOODS["main_menu"])

	var atm := Control.new()
	atm.name = "Atmosphere"
	atm.set_anchors_preset(Control.PRESET_FULL_RECT)
	atm.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# — Vignette + radial gradient (single shader ColorRect) —
	var vig_rect := ColorRect.new()
	vig_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig_rect.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = _get_atmosphere_shader()
	mat.set_shader_parameter("vignette_strength", mood.vignette)
	mat.set_shader_parameter("grad_inner", mood.grad_inner)
	mat.set_shader_parameter("grad_outer", mood.grad_outer)
	vig_rect.material = mat
	atm.add_child(vig_rect)

	# — Ambient floating particles —
	var particles := _make_ambient_particles(mood)
	atm.add_child(particles)

	# — Decorative corner frame —
	if include_frame:
		var frame := _make_decorative_frame(mood.frame_color)
		atm.add_child(frame)

	parent.add_child(atm)
	# Slot right after Background (index 0) so UI builds on top
	parent.move_child(atm, 1)


static func _make_ambient_particles(mood: Dictionary) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "AmbientMotes"
	p.emitting = true
	p.amount = mood.particle_count
	p.lifetime = 6.0
	p.explosiveness = 0.0
	p.randomness = 1.0
	# Emit across the full viewport
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(800, 450)
	p.position = Vector2(800, 450)
	# Slow upward drift with lateral wobble
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.initial_velocity_min = mood.particle_speed * 0.5
	p.initial_velocity_max = mood.particle_speed
	p.gravity = Vector2(0, 0)
	p.linear_accel_min = -2.0
	p.linear_accel_max = 2.0
	# Size
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	# Color ramp: transparent → glow → color-shift → transparent
	var c1: Color = mood.particle_color
	var c2: Color = mood.get("particle_alt", c1)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(c1.r, c1.g, c1.b, 0.0))
	gradient.set_color(1, Color(c2.r, c2.g, c2.b, 0.0))
	gradient.add_point(0.15, c1)
	gradient.add_point(0.7, c2)
	p.color_ramp = gradient
	return p


static func _make_decorative_frame(frame_color: Color) -> Control:
	var frame := Control.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Render above all sibling UI regardless of add-order
	frame.z_as_relative = false
	frame.z_index = 10

	var inset := 14.0
	var clen := 40.0    # corner piece length
	var w := 1.5

	var dim := Color(frame_color.r, frame_color.g, frame_color.b,
		frame_color.a * 0.5)

	# Corner L-shapes (8 rects: 2 per corner)
	_add_frame_rect(frame, Vector2(inset, inset), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(inset, inset), Vector2(w, clen), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - clen, inset), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - w, inset), Vector2(w, clen), frame_color)
	_add_frame_rect(frame, Vector2(inset, 900 - inset - w), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(inset, 900 - inset - clen), Vector2(w, clen), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - clen, 900 - inset - w), Vector2(clen, w), frame_color)
	_add_frame_rect(frame, Vector2(1600 - inset - w, 900 - inset - clen), Vector2(w, clen), frame_color)

	# Thin connecting lines between corners
	_add_frame_rect(frame, Vector2(inset + clen, inset),
		Vector2(1600 - 2 * (inset + clen), w), dim)
	_add_frame_rect(frame, Vector2(inset + clen, 900 - inset - w),
		Vector2(1600 - 2 * (inset + clen), w), dim)
	_add_frame_rect(frame, Vector2(inset, inset + clen),
		Vector2(w, 900 - 2 * (inset + clen)), dim)
	_add_frame_rect(frame, Vector2(1600 - inset - w, inset + clen),
		Vector2(w, 900 - 2 * (inset + clen)), dim)

	# Small diamond dots at the four corners
	var ds := 5.0
	var bright := Color(frame_color.r * 1.4, frame_color.g * 1.4,
		frame_color.b * 1.4, minf(frame_color.a * 1.5, 1.0))
	_add_frame_rect(frame, Vector2(inset - ds / 2, inset - ds / 2),
		Vector2(ds, ds), bright)
	_add_frame_rect(frame, Vector2(1600 - inset - ds / 2, inset - ds / 2),
		Vector2(ds, ds), bright)
	_add_frame_rect(frame, Vector2(inset - ds / 2, 900 - inset - ds / 2),
		Vector2(ds, ds), bright)
	_add_frame_rect(frame, Vector2(1600 - inset - ds / 2, 900 - inset - ds / 2),
		Vector2(ds, ds), bright)

	return frame


static func _add_frame_rect(parent: Control, pos: Vector2, sz: Vector2,
		col: Color) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


# ═══════════════════════════════════════════
#  SCREEN TITLE  (label + decorative separator)
# ═══════════════════════════════════════════

static func make_screen_title(text: String, color: Color = GILT_BRIGHT,
		font_size: int = FONT_TITLE) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", font_size)
	title.add_theme_color_override("font_color", color)
	title.add_theme_color_override("font_outline_color",
		Color(color.r, color.g, color.b, 0.25))
	title.add_theme_constant_override("outline_size", 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	# ── ◆ ── separator
	var sep := HBoxContainer.new()
	sep.alignment = BoxContainer.ALIGNMENT_CENTER
	sep.add_theme_constant_override("separation", 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line_col := Color(color.r, color.g, color.b, 0.30)
	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(50, 1)
	left.color = line_col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(left)

	var diamond := Label.new()
	diamond.text = " ◆ "
	diamond.add_theme_font_size_override("font_size", 8)
	diamond.add_theme_color_override("font_color",
		Color(color.r, color.g, color.b, 0.45))
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(diamond)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(50, 1)
	right.color = line_col
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep.add_child(right)

	vbox.add_child(sep)
	return vbox


## Thin horizontal rule for section breaks.
static func make_separator(color: Color = GILT, width: float = 200.0) -> CenterContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(width, 1)
	line.color = Color(color.r, color.g, color.b, 0.20)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(line)
	return center


# ═══════════════════════════════════════════
#  NINEPATCH CARD FRAME
# ═══════════════════════════════════════════

func make_card_frame(tint: Color = GILT) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = tex_card_frame
	np.patch_margin_left = NINEPATCH_MARGIN
	np.patch_margin_right = NINEPATCH_MARGIN
	np.patch_margin_top = NINEPATCH_MARGIN
	np.patch_margin_bottom = NINEPATCH_MARGIN
	np.modulate = tint
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


func make_panel_frame(tint: Color = Color(0.45, 0.35, 0.20, 0.85)) -> NinePatchRect:
	var np := NinePatchRect.new()
	np.texture = tex_panel_bg
	np.patch_margin_left = NINEPATCH_MARGIN
	np.patch_margin_right = NINEPATCH_MARGIN
	np.patch_margin_top = NINEPATCH_MARGIN
	np.patch_margin_bottom = NINEPATCH_MARGIN
	np.modulate = tint
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


# ═══════════════════════════════════════════
#  ICON + LABEL STAT BADGE
# ═══════════════════════════════════════════

func make_icon_stat(icon: Texture2D, value: String, icon_tint: Color,
		font_size: int = 18) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 1)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := TextureRect.new()
	tex.texture = icon
	tex.custom_minimum_size = Vector2(18, 18)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.modulate = icon_tint
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(tex)
	var lbl := Label.new()
	lbl.text = value
	if font_body:
		lbl.add_theme_font_override("font", font_body)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox


func try_load_creature_art(card_id: String) -> Texture2D:
	var path = "res://assets/creatures/%s.png" % card_id
	if ResourceLoader.exists(path):
		return load(path)
	var jpg_path = "res://assets/creatures/%s.jpg" % card_id
	if ResourceLoader.exists(jpg_path):
		return load(jpg_path)
	return null


func try_load_spell_art(card_id: String) -> Texture2D:
	var path = "res://assets/spells/%s.png" % card_id
	if ResourceLoader.exists(path):
		return load(path)
	return null
