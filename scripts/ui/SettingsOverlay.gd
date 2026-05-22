extends CanvasLayer
## SettingsOverlay.gd — settings popup accessible from every screen via gear icon
## in the top HUD bar. Lives as child of UserSettings autoload.

const GEAR_PATH = "res://assets/icons/kenney_game-icons/PNG/White/2x/gear.png"
const AUDIO_ON_PATH = "res://assets/icons/kenney_game-icons/PNG/White/2x/audioOn.png"
const DIVIDER_PATH = "res://assets/ui/kenney_fantasy-ui-borders/PNG/Double/Divider Fade/divider-fade-003.png"
const PANEL_9P_PATH = "res://assets/ui/kenney_fantasy-ui-borders/PNG/Double/Panel/panel-009.png"

const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var _gear_btn: TextureButton
var _backdrop: ColorRect
var _panel_root: Control
var _is_open := false

var _master_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _master_pct: Label
var _music_pct: Label
var _sfx_pct: Label
var _res_option: OptionButton
var _display_mode_option: OptionButton
var _fps_cap_option: OptionButton
var _colorblind_option: OptionButton
var _ui_scale_slider: HSlider
var _ui_scale_pct: Label
var _brightness_slider: HSlider
var _brightness_pct: Label
var _anim_speed_option: OptionButton
var _tooltip_delay_slider: HSlider
var _tooltip_delay_pct: Label
var _pending_res: Vector2i
var _pending_display_mode: String
var _available_res: Array = []

var _anim_tween: Tween
var _gear_tween: Tween
# Cached refs for parts that change with run state — the title flips between
# "PAUSED" / "SETTINGS" and the system-action row swaps Abandon / Main Menu
# depending on whether a run is active when the overlay opens.
var _title_label: Label = null
var _system_row: HBoxContainer = null


func _ready() -> void:
	layer = 100
	_build_gear_button()
	_build_overlay()
	_panel_root.visible = false
	_backdrop.visible = false


# ═══════════════════════════════════════════════════
#  GEAR BUTTON  (top HUD bar, far right — matches
#  MapView HUD row at y=14, icon size 40×40)
# ═══════════════════════════════════════════════════

func _build_gear_button() -> void:
	_gear_btn = TextureButton.new()
	var tex = load(GEAR_PATH) as Texture2D
	_gear_btn.texture_normal = tex
	# ignore_texture_size lets custom_minimum_size win — otherwise the button
	# inherits the PNG's native size (which is ~100px) and ignores our setting.
	_gear_btn.ignore_texture_size = true
	_gear_btn.custom_minimum_size = Vector2(48, 48)
	_gear_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_gear_btn.modulate = Color(0.82, 0.66, 0.30, 0.55)
	# Top-right corner, 48×48 to visually match the heart icon, with ~22px
	# padding from the right edge — Slay-the-Spire style.
	_gear_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gear_btn.offset_left = -70
	_gear_btn.offset_top = 14
	_gear_btn.offset_right = -22
	_gear_btn.offset_bottom = 62
	_gear_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_gear_btn.pressed.connect(_toggle)
	_gear_btn.mouse_entered.connect(func():
		if _gear_tween and _gear_tween.is_valid():
			_gear_tween.kill()
		_gear_tween = create_tween()
		_gear_tween.tween_property(_gear_btn, "modulate", Color(1.0, 0.88, 0.35, 1.0), 0.12))
	_gear_btn.mouse_exited.connect(func():
		if not _is_open:
			if _gear_tween and _gear_tween.is_valid():
				_gear_tween.kill()
			_gear_tween = create_tween()
			_gear_tween.tween_property(_gear_btn, "modulate", Color(0.82, 0.66, 0.30, 0.55), 0.12))
	add_child(_gear_btn)


# ═══════════════════════════════════════════════════
#  OVERLAY  (backdrop + centered panel)
# ═══════════════════════════════════════════════════

func _build_overlay() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.75)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(_backdrop)

	_panel_root = Control.new()
	_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(center)

	var panel_wrap := PanelContainer.new()
	# Wider panel to host two side-by-side columns (each ~460 wide + padding +
	# inter-column separator). Was 540 single-column.
	panel_wrap.custom_minimum_size = Vector2(1020, 0)
	_apply_panel_style(panel_wrap)
	center.add_child(panel_wrap)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel_wrap.add_child(vbox)

	# Title + divider span the full panel width.
	_add_title(vbox)
	_add_fancy_divider(vbox)

	# ── Two-column body ──
	# Right column gets the longest section (DISPLAY, 9 rows); left column
	# gets AUDIO + GAMEPLAY + ACCESSIBILITY (3+3+2 = 8 rows). Roughly balanced
	# heights and keeps each section as a self-contained group.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cols)

	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 2)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left_col)

	# Vertical separator between columns.
	var col_sep := ColorRect.new()
	col_sep.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.25)
	col_sep.custom_minimum_size = Vector2(1, 0)
	col_sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(col_sep)

	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 2)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(right_col)

	# ── LEFT COLUMN: Audio + Gameplay + Accessibility ──
	_add_section_label(left_col, "AUDIO", AUDIO_ON_PATH)
	_add_spacer(left_col, 4)

	var master_row: Array = _add_slider_row(left_col, "Master", UserSettings.master_volume)
	_master_slider = master_row[0]; _master_pct = master_row[1]
	var music_row: Array = _add_slider_row(left_col, "Music", UserSettings.music_volume)
	_music_slider = music_row[0]; _music_pct = music_row[1]
	var sfx_row: Array = _add_slider_row(left_col, "Effects", UserSettings.sfx_volume)
	_sfx_slider = sfx_row[0]; _sfx_pct = sfx_row[1]

	_master_slider.value_changed.connect(func(v: float):
		UserSettings.set_master_volume(v); _master_pct.text = "%d%%" % int(v * 100))
	_music_slider.value_changed.connect(func(v: float):
		UserSettings.set_music_volume(v); _music_pct.text = "%d%%" % int(v * 100))
	_sfx_slider.value_changed.connect(func(v: float):
		UserSettings.set_sfx_volume(v); _sfx_pct.text = "%d%%" % int(v * 100))

	_add_fancy_divider(left_col)

	_add_section_label(left_col, "GAMEPLAY")
	_add_spacer(left_col, 4)

	_add_anim_speed_row(left_col)
	_add_tooltip_delay_row(left_col)
	_add_toggle_row(left_col, "End-Turn Warning", UserSettings.end_turn_warning,
		func(v: bool): UserSettings.set_end_turn_warning(v))

	_add_fancy_divider(left_col)

	_add_section_label(left_col, "ACCESSIBILITY")
	_add_spacer(left_col, 4)

	_add_toggle_row(left_col, "Reduce Motion", UserSettings.reduce_motion,
		func(v: bool): UserSettings.set_reduce_motion(v))
	_add_colorblind_row(left_col)

	# ── RIGHT COLUMN: Display ──
	_add_section_label(right_col, "DISPLAY")
	_add_spacer(right_col, 4)

	_add_resolution_row(right_col)
	_add_display_mode_row(right_col)
	_add_toggle_row(right_col, "V-Sync", UserSettings.vsync,
		func(v: bool): UserSettings.set_vsync(v))
	_add_fps_cap_row(right_col)
	_add_ui_scale_row(right_col)
	_add_brightness_row(right_col)
	_add_toggle_row(right_col, "Screen Shake", UserSettings.screen_shake,
		func(v: bool): UserSettings.set_screen_shake(v))
	_add_toggle_row(right_col, "Particles", UserSettings.particles,
		func(v: bool): UserSettings.set_particles(v))
	_add_toggle_row(right_col, "Mute on Focus Loss", UserSettings.mute_on_focus_loss,
		func(v: bool): UserSettings.set_mute_on_focus_loss(v))

	_add_fancy_divider(vbox)

	# ── Buttons ──
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var apply_btn := GameTheme.make_themed_button("APPLY", Color(0.18, 0.35, 0.14),
		Vector2(140, 40), 16)
	apply_btn.pressed.connect(_apply_and_close)
	btn_row.add_child(apply_btn)

	# "Resume" / Close — pill back button, primary way out.
	var close_btn := GameTheme.make_back_button("RESUME", Vector2(150, 40), 16)
	close_btn.pressed.connect(_close)
	btn_row.add_child(close_btn)

	vbox.add_child(btn_row)
	_add_spacer(vbox, 6)

	# Second row: destructive / system actions, visually separated so they're
	# never the first thing the player's hand reaches for. Rebuilt on every
	# _open() so it reflects the current run state.
	_system_row = HBoxContainer.new()
	_system_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_system_row.add_theme_constant_override("separation", 12)
	_system_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_system_row)
	_rebuild_system_row()
	_add_spacer(vbox, 4)


func _rebuild_system_row() -> void:
	# Repopulate the Abandon / Main Menu / Quit row based on current state.
	# Called on every _open() so context changes (started a run, finished it)
	# are reflected.
	if _system_row == null:
		return
	for child in _system_row.get_children():
		child.queue_free()

	if RunState.run_active:
		var abandon_btn := GameTheme.make_themed_button("ABANDON RUN",
			Color(0.36, 0.12, 0.10), Vector2(170, 38), 14)
		abandon_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.75))
		abandon_btn.pressed.connect(_abandon_run)
		_system_row.add_child(abandon_btn)
	elif get_tree() != null and get_tree().current_scene != null:
		# Out of a run: a "MAIN MENU" path makes sense from any scene except the
		# main menu itself.
		if get_tree().current_scene.name != "MainMenu":
			var menu_btn := GameTheme.make_themed_button("MAIN MENU",
				Color(0.18, 0.14, 0.10), Vector2(150, 38), 14)
			menu_btn.pressed.connect(_to_main_menu)
			_system_row.add_child(menu_btn)

	# "Quit Game" — exit to OS. Always present so Esc → Quit Game is one path.
	var quit_btn := GameTheme.make_themed_button("QUIT GAME",
		Color(0.18, 0.14, 0.10), Vector2(150, 38), 14)
	quit_btn.pressed.connect(_quit_game)
	_system_row.add_child(quit_btn)


func _apply_panel_style(panel: PanelContainer) -> void:
	var panel_tex = load(PANEL_9P_PATH) as Texture2D
	if panel_tex:
		var sb := StyleBoxTexture.new()
		sb.texture = panel_tex
		for prop in ["texture_margin_left", "texture_margin_right",
				"texture_margin_top", "texture_margin_bottom"]:
			sb.set(prop, 18)
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 22
		sb.content_margin_bottom = 22
		sb.modulate_color = Color(0.14, 0.11, 0.08, 0.97)
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		panel.add_theme_stylebox_override("panel", sb)
	else:
		panel.add_theme_stylebox_override("panel",
			GameTheme.make_panel_style(GameTheme.PARCHMENT, GameTheme.PARCHMENT_BORDER))


# ═══════════════════════════════════════════════════
#  TITLE
# ═══════════════════════════════════════════════════

func _add_title(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex = load(GEAR_PATH) as Texture2D
	for i in 2:
		var icon := TextureRect.new()
		if tex:
			icon.texture = tex
			icon.custom_minimum_size = Vector2(26, 26)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.modulate = GameTheme.GILT_BRIGHT
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			row.add_child(icon)

	var lbl := Label.new()
	# Title is context-aware: during an active run the overlay acts as the
	# pause menu, so call it "PAUSED" — on the main menu / out of a run it's
	# just configuration so call it "SETTINGS". Updated on every _open().
	lbl.text = "PAUSED" if RunState.run_active else "SETTINGS"
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	_title_label = lbl

	var icon2 := TextureRect.new()
	if tex:
		icon2.texture = tex
		icon2.custom_minimum_size = Vector2(26, 26)
		icon2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon2.modulate = GameTheme.GILT_BRIGHT
		icon2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon2)

	parent.add_child(row)


# ═══════════════════════════════════════════════════
#  DIVIDER
# ═══════════════════════════════════════════════════

func _add_fancy_divider(parent: VBoxContainer) -> void:
	_add_spacer(parent, 5)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var div_tex = load(DIVIDER_PATH) as Texture2D
	if div_tex:
		var tex_rect := TextureRect.new()
		tex_rect.texture = div_tex
		tex_rect.custom_minimum_size = Vector2(420, 8)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.modulate = Color(0.82, 0.66, 0.30, 0.45)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(tex_rect)
	else:
		var line := ColorRect.new()
		line.custom_minimum_size = Vector2(420, 1)
		line.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.2)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(line)
	parent.add_child(center)
	_add_spacer(parent, 5)


func _add_spacer(parent: VBoxContainer, h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


# ═══════════════════════════════════════════════════
#  SECTION LABEL
# ═══════════════════════════════════════════════════

func _add_section_label(parent: VBoxContainer, text: String, icon_path: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 0)
	row.add_child(pad)

	if icon_path != "":
		var icon := TextureRect.new()
		var tex = load(icon_path) as Texture2D
		if tex:
			icon.texture = tex
			icon.custom_minimum_size = Vector2(20, 20)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.modulate = GameTheme.GILT
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)

	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", GameTheme.GILT)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	parent.add_child(row)


# ═══════════════════════════════════════════════════
#  SLIDER ROW
# ═══════════════════════════════════════════════════

func _add_slider_row(parent: VBoxContainer, label_text: String, initial: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	_add_row_pad(row)

	var lbl := _make_row_label(label_text, 100)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.custom_minimum_size = Vector2(220, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(slider)
	row.add_child(slider)

	var pct := Label.new()
	pct.text = "%d%%" % int(initial * 100)
	pct.custom_minimum_size = Vector2(48, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if GameTheme.font_body:
		pct.add_theme_font_override("font", GameTheme.font_body)
	pct.add_theme_font_size_override("font_size", 14)
	pct.add_theme_color_override("font_color", GameTheme.GILT)
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pct)

	_add_row_pad(row)
	parent.add_child(row)
	return [slider, pct]


func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.05, 0.9)
	track.border_color = Color(0.3, 0.22, 0.12, 0.5)
	for prop in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		track.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		track.set(prop, 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)

	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.65, 0.50, 0.18, 0.9)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		filled.set(prop, 4)
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	slider.add_theme_stylebox_override("grabber_area", filled)

	var filled_hl := filled.duplicate() as StyleBoxFlat
	filled_hl.bg_color = Color(0.82, 0.66, 0.30, 1.0)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled_hl)

	slider.add_theme_icon_override("grabber", _make_circle_texture(12, GameTheme.GILT_BRIGHT))
	slider.add_theme_icon_override("grabber_highlight", _make_circle_texture(14, Color(1.0, 0.92, 0.55)))
	slider.add_theme_icon_override("grabber_disabled", _make_circle_texture(12, GameTheme.DIMMED))


# ═══════════════════════════════════════════════════
#  RESOLUTION ROW  (OptionButton dropdown)
# ═══════════════════════════════════════════════════

func _add_resolution_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("Resolution", 160)
	row.add_child(lbl)

	_res_option = OptionButton.new()
	_res_option.custom_minimum_size = Vector2(170, 30)
	_res_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Only show resolutions that fit on the user's monitor.
	_available_res = UserSettings.get_available_resolutions(RESOLUTIONS)

	var current_res := UserSettings.resolution
	var selected_idx := 0
	for i in _available_res.size():
		var r: Vector2i = _available_res[i]
		_res_option.add_item("%d x %d" % [r.x, r.y], i)
		if r == current_res:
			selected_idx = i
	_res_option.selected = selected_idx

	_style_option_button(_res_option)
	_res_option.item_selected.connect(func(idx: int):
		_pending_res = _available_res[idx])

	row.add_child(_res_option)
	parent.add_child(row)


func _style_option_button(opt: OptionButton) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.08, 0.06, 0.9)
	normal.border_color = Color(0.40, 0.30, 0.15, 0.7)
	for prop in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		normal.set(prop, 1)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal.set(prop, 6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	opt.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = GameTheme.GILT_BRIGHT
	hover.bg_color = Color(0.14, 0.11, 0.08, 0.95)
	opt.add_theme_stylebox_override("hover", hover)
	opt.add_theme_stylebox_override("pressed", hover)
	opt.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if GameTheme.font_body:
		opt.add_theme_font_override("font", GameTheme.font_body)
	opt.add_theme_font_size_override("font_size", 14)
	opt.add_theme_color_override("font_color", GameTheme.IVORY)
	opt.add_theme_color_override("font_hover_color", GameTheme.GILT_BRIGHT)

	# Style the popup list
	var popup := opt.get_popup()
	if popup:
		var popup_style := normal.duplicate() as StyleBoxFlat
		popup_style.bg_color = Color(0.10, 0.08, 0.06, 0.97)
		popup_style.border_color = GameTheme.GILT
		for prop in ["border_width_top", "border_width_bottom",
				"border_width_left", "border_width_right"]:
			popup_style.set(prop, 2)
		popup.add_theme_stylebox_override("panel", popup_style)
		popup.add_theme_stylebox_override("hover", _make_popup_hover_style())
		if GameTheme.font_body:
			popup.add_theme_font_override("font", GameTheme.font_body)
		popup.add_theme_font_size_override("font_size", 14)
		popup.add_theme_color_override("font_color", GameTheme.IVORY)
		popup.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))


func _make_popup_hover_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.25, 0.18, 0.08, 0.9)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		s.set(prop, 3)
	return s


# ═══════════════════════════════════════════════════
#  FULLSCREEN ROW  (toggle that disables resolution)
# ═══════════════════════════════════════════════════

func _add_display_mode_row(parent: VBoxContainer) -> void:
	# Three-way: Windowed / Borderless / Fullscreen. Borderless is windowed
	# with no decoration, sized to the monitor — best for streamers and
	# multi-monitor users who want fast Alt-Tab.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("Display Mode", 160)
	row.add_child(lbl)

	_display_mode_option = OptionButton.new()
	_display_mode_option.custom_minimum_size = Vector2(170, 30)
	_display_mode_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var modes := ["windowed", "borderless", "fullscreen"]
	var labels := ["Windowed", "Borderless", "Fullscreen"]
	var current := UserSettings.display_mode
	for i in modes.size():
		_display_mode_option.add_item(labels[i], i)
		if modes[i] == current:
			_display_mode_option.selected = i
	_style_option_button(_display_mode_option)
	_display_mode_option.item_selected.connect(func(idx: int):
		_pending_display_mode = modes[idx]
		_res_option.disabled = (_pending_display_mode != "windowed"))
	_res_option.disabled = (current != "windowed")
	row.add_child(_display_mode_option)
	parent.add_child(row)


func _add_fps_cap_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("FPS Cap", 160)
	row.add_child(lbl)

	_fps_cap_option = OptionButton.new()
	_fps_cap_option.custom_minimum_size = Vector2(170, 30)
	_fps_cap_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var caps := [0, 30, 60, 120, 144, 240]
	var cap_labels := ["Unlimited", "30 FPS", "60 FPS", "120 FPS", "144 FPS", "240 FPS"]
	for i in caps.size():
		_fps_cap_option.add_item(cap_labels[i], i)
		if caps[i] == UserSettings.fps_cap:
			_fps_cap_option.selected = i
	_style_option_button(_fps_cap_option)
	_fps_cap_option.item_selected.connect(func(idx: int):
		UserSettings.set_fps_cap(caps[idx]))
	row.add_child(_fps_cap_option)
	parent.add_child(row)


func _add_ui_scale_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("UI Scale", 100)
	row.add_child(lbl)

	_ui_scale_slider = HSlider.new()
	_ui_scale_slider.min_value = 0.7
	_ui_scale_slider.max_value = 1.5
	_ui_scale_slider.step = 0.05
	_ui_scale_slider.value = UserSettings.ui_scale
	_ui_scale_slider.custom_minimum_size = Vector2(220, 24)
	_ui_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(_ui_scale_slider)
	row.add_child(_ui_scale_slider)

	_ui_scale_pct = _make_pct_label("%d%%" % int(UserSettings.ui_scale * 100))
	row.add_child(_ui_scale_pct)

	_ui_scale_slider.value_changed.connect(func(v: float):
		UserSettings.set_ui_scale(v)
		_ui_scale_pct.text = "%d%%" % int(v * 100))

	_add_row_pad(row)
	parent.add_child(row)


func _add_brightness_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("Brightness", 100)
	row.add_child(lbl)

	_brightness_slider = HSlider.new()
	_brightness_slider.min_value = -0.4
	_brightness_slider.max_value = 0.4
	_brightness_slider.step = 0.05
	_brightness_slider.value = UserSettings.brightness
	_brightness_slider.custom_minimum_size = Vector2(220, 24)
	_brightness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(_brightness_slider)
	row.add_child(_brightness_slider)

	_brightness_pct = _make_pct_label("%+d%%" % int(UserSettings.brightness * 100))
	row.add_child(_brightness_pct)

	_brightness_slider.value_changed.connect(func(v: float):
		UserSettings.set_brightness(v)
		_brightness_pct.text = "%+d%%" % int(v * 100))

	_add_row_pad(row)
	parent.add_child(row)


func _add_anim_speed_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("Animation Speed", 160)
	row.add_child(lbl)

	_anim_speed_option = OptionButton.new()
	_anim_speed_option.custom_minimum_size = Vector2(170, 30)
	_anim_speed_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var speeds := [0.5, 1.0, 1.5, 3.0]
	var speed_labels := ["Slow", "Normal", "Fast", "Instant"]
	var current_speed := UserSettings.anim_speed
	var selected := 1
	for i in speeds.size():
		_anim_speed_option.add_item(speed_labels[i], i)
		if abs(speeds[i] - current_speed) < 0.01:
			selected = i
	_anim_speed_option.selected = selected
	_style_option_button(_anim_speed_option)
	_anim_speed_option.item_selected.connect(func(idx: int):
		UserSettings.set_anim_speed(speeds[idx]))
	row.add_child(_anim_speed_option)
	parent.add_child(row)


func _add_tooltip_delay_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("Tooltip Delay", 100)
	row.add_child(lbl)

	_tooltip_delay_slider = HSlider.new()
	_tooltip_delay_slider.min_value = 0.0
	_tooltip_delay_slider.max_value = 0.5
	_tooltip_delay_slider.step = 0.05
	_tooltip_delay_slider.value = UserSettings.tooltip_delay
	_tooltip_delay_slider.custom_minimum_size = Vector2(220, 24)
	_tooltip_delay_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(_tooltip_delay_slider)
	row.add_child(_tooltip_delay_slider)

	_tooltip_delay_pct = _make_pct_label("%dms" % int(UserSettings.tooltip_delay * 1000))
	row.add_child(_tooltip_delay_pct)

	_tooltip_delay_slider.value_changed.connect(func(v: float):
		UserSettings.set_tooltip_delay(v)
		_tooltip_delay_pct.text = "%dms" % int(v * 1000))

	_add_row_pad(row)
	parent.add_child(row)


func _add_colorblind_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label("Color Blind Mode", 160)
	row.add_child(lbl)

	_colorblind_option = OptionButton.new()
	_colorblind_option.custom_minimum_size = Vector2(170, 30)
	_colorblind_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var modes := ["off", "deuteranopia", "protanopia", "tritanopia"]
	var mode_labels := ["Off", "Deuteranopia", "Protanopia", "Tritanopia"]
	for i in modes.size():
		_colorblind_option.add_item(mode_labels[i], i)
		if modes[i] == UserSettings.colorblind_mode:
			_colorblind_option.selected = i
	_style_option_button(_colorblind_option)
	_colorblind_option.item_selected.connect(func(idx: int):
		UserSettings.set_colorblind_mode(modes[idx]))
	row.add_child(_colorblind_option)
	parent.add_child(row)


func _make_pct_label(text: String) -> Label:
	var pct := Label.new()
	pct.text = text
	pct.custom_minimum_size = Vector2(60, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if GameTheme.font_body:
		pct.add_theme_font_override("font", GameTheme.font_body)
	pct.add_theme_font_size_override("font_size", 14)
	pct.add_theme_color_override("font_color", GameTheme.GILT)
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pct


# ═══════════════════════════════════════════════════
#  TOGGLE ROW
# ═══════════════════════════════════════════════════

func _add_toggle_row(parent: VBoxContainer, label_text: String, initial: bool,
		callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add_row_pad(row)

	var lbl := _make_row_label(label_text, 160)
	row.add_child(lbl)

	var toggle_btn := Button.new()
	toggle_btn.custom_minimum_size = Vector2(70, 30)
	toggle_btn.toggle_mode = true
	toggle_btn.button_pressed = initial
	toggle_btn.text = "ON" if initial else "OFF"
	toggle_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_toggle(toggle_btn, initial)

	toggle_btn.toggled.connect(func(pressed: bool):
		toggle_btn.text = "ON" if pressed else "OFF"
		_style_toggle(toggle_btn, pressed)
		callback.call(pressed))

	row.add_child(toggle_btn)
	parent.add_child(row)


func _style_toggle(btn: Button, is_on: bool) -> void:
	var bg_color := Color(0.20, 0.50, 0.18, 0.9) if is_on else Color(0.15, 0.12, 0.10, 0.9)
	var border_color := Color(0.35, 0.70, 0.30, 0.8) if is_on else Color(0.30, 0.22, 0.15, 0.6)
	var text_color := Color(0.7, 1.0, 0.6) if is_on else Color(0.5, 0.45, 0.4)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = border_color
	for prop in ["border_width_top", "border_width_bottom",
			"border_width_left", "border_width_right"]:
		normal.set(prop, 2)
	for prop in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal.set(prop, 15)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("pressed", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg_color.lightened(0.15)
	hover.border_color = GameTheme.GILT_BRIGHT
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("hover_pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if GameTheme.font_body:
		btn.add_theme_font_override("font", GameTheme.font_body)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color.lightened(0.2))
	btn.add_theme_color_override("font_pressed_color", text_color)


# ═══════════════════════════════════════════════════
#  SHARED HELPERS
# ═══════════════════════════════════════════════════

func _make_row_label(text: String, min_w: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(min_w, 0)
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", GameTheme.IVORY)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _add_row_pad(row: HBoxContainer) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(16, 0)
	row.add_child(pad)


func _make_circle_texture(radius: int, color: Color) -> ImageTexture:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(radius, radius)
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(c)
			if dist <= radius - 1:
				img.set_pixel(x, y, color)
			elif dist <= radius:
				var alpha := 1.0 - (dist - (radius - 1))
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
	return ImageTexture.create_from_image(img)


# ═══════════════════════════════════════════════════
#  OPEN / CLOSE
# ═══════════════════════════════════════════════════

func _toggle() -> void:
	if _is_open: _close()
	else: _open()


func _open() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_is_open = true
	_backdrop.visible = true
	_panel_root.visible = true
	_gear_btn.modulate = GameTheme.GILT_BRIGHT

	# Refresh title + system actions to current context every time the overlay
	# opens — what counted as a "run" might be different now than at boot.
	if _title_label != null:
		_title_label.text = "PAUSED" if RunState.run_active else "SETTINGS"
	_rebuild_system_row()

	_master_slider.value = UserSettings.master_volume
	_music_slider.value = UserSettings.music_volume
	_sfx_slider.value = UserSettings.sfx_volume
	_master_pct.text = "%d%%" % int(UserSettings.master_volume * 100)
	_music_pct.text = "%d%%" % int(UserSettings.music_volume * 100)
	_sfx_pct.text = "%d%%" % int(UserSettings.sfx_volume * 100)

	# Sync resolution dropdown and pending state
	_pending_res = UserSettings.resolution
	_pending_display_mode = UserSettings.display_mode
	for i in _available_res.size():
		if _available_res[i] == UserSettings.resolution:
			_res_option.selected = i
			break
	_res_option.disabled = (UserSettings.display_mode != "windowed")

	_backdrop.modulate = Color(1, 1, 1, 0)
	_panel_root.modulate = Color(1, 1, 1, 0)
	_panel_root.scale = Vector2(0.95, 0.95)
	_panel_root.pivot_offset = get_viewport().get_visible_rect().size / 2.0

	_anim_tween = create_tween()
	_anim_tween.set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate", Color(1, 1, 1, 1), 0.2)
	_anim_tween.tween_property(_panel_root, "modulate", Color(1, 1, 1, 1), 0.25)
	_anim_tween.tween_property(_panel_root, "scale", Vector2.ONE, 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _apply_and_close() -> void:
	# Resolution + display mode flow through UserSettings setters so persistence
	# and DisplayServer changes happen consistently. Other settings (volume,
	# vsync, fps cap, etc.) apply live when toggled, so APPLY only handles the
	# window-mode + resolution pair.
	UserSettings.resolution = _pending_res
	UserSettings.set_display_mode(_pending_display_mode)
	if _pending_display_mode == "windowed":
		await get_tree().process_frame
		UserSettings._apply_resolution()
	_close()


func _abandon_run() -> void:
	# Modal confirm before destroying the run. Players will eventually mis-click
	# the Abandon button — without a yes/no gate, that single click would erase
	# 30 minutes of decisions.
	GameTheme.show_confirm_dialog(self,
		"ABANDON RUN?",
		"Your current progress will be lost and this run will be counted as a defeat. Are you sure?",
		"YES, ABANDON",
		"KEEP PLAYING",
		Callable(self, "_confirm_abandon_run"))


func _confirm_abandon_run() -> void:
	if RunState.run_active:
		RunState.end_run(false)
	_close()
	GameTheme.fade_out_then_change_scene(self, "res://scenes/main_menu.tscn", 0.4)


func _to_main_menu() -> void:
	# Direct path back to the title screen from non-run scenes (Collection,
	# Credits, etc. where Esc was pressed). Closes the overlay then fades.
	_close()
	GameTheme.fade_out_then_change_scene(self, "res://scenes/main_menu.tscn", 0.30)


func _quit_game() -> void:
	# Confirm before quitting if a run is active, otherwise quit immediately.
	if RunState.run_active:
		GameTheme.show_confirm_dialog(self,
			"QUIT GAME?",
			"Your current run will be lost. Quit to desktop?",
			"YES, QUIT",
			"KEEP PLAYING",
			Callable(self, "_do_quit"))
	else:
		_do_quit()


func _do_quit() -> void:
	get_tree().quit()


func _close() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
	_is_open = false

	_anim_tween = create_tween()
	_anim_tween.set_parallel(true)
	_anim_tween.tween_property(_backdrop, "modulate", Color(1, 1, 1, 0), 0.15)
	_anim_tween.tween_property(_panel_root, "modulate", Color(1, 1, 1, 0), 0.15)
	_anim_tween.chain().tween_callback(func():
		_backdrop.visible = false
		_panel_root.visible = false)

	if _gear_tween and _gear_tween.is_valid():
		_gear_tween.kill()
	_gear_tween = create_tween()
	_gear_tween.tween_property(_gear_btn, "modulate", Color(0.82, 0.66, 0.30, 0.55), 0.2)


func _input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open:
		get_viewport().set_input_as_handled()
