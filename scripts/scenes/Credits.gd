extends Control
## Credits.gd — attribution screen accessible from the main menu.
## Lists fonts, art sources, audio sources (when added by the user), and engine.
## Programmatic so the .tscn file stays a one-line stub.

const MENU_SCENE = "res://scenes/main_menu.tscn"

const GILT := Color(0.83, 0.74, 0.54, 1.0)
const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
const PARCHMENT := Color(0.86, 0.78, 0.62, 1.0)

const SECTIONS: Array = [
	{
		"heading": "GAME DESIGN",
		"lines": [
			"Burning Meadow — a lane combat roguelike deckbuilder",
			"Inspired by Card Wars and Slay the Spire",
		],
	},
	{
		"heading": "ENGINE",
		"lines": [
			"Godot Engine 4.6 — godotengine.org",
		],
	},
	{
		"heading": "FONTS",
		"lines": [
			"Cinzel — Natanael Gama — SIL Open Font License",
			"Lilita One — Juan Montoreano — SIL Open Font License",
			"Nunito — Vernon Adams — SIL Open Font License",
		],
	},
	{
		"heading": "ART — UI & ICONS",
		"lines": [
			"Kenney Fantasy UI Borders — CC0",
			"Kenney Board Game Icons — CC0",
			"Kenney Game Icons — CC0",
		],
	},
	{
		"heading": "ART — CARDS & PORTRAITS",
		"lines": [
			"Public-domain masters: Gustave Doré, Mikhail Vrubel,",
			"Henry Fuseli, Goya, Bruegel, Bosch, Beksiński, and others",
		],
	},
	{
		"heading": "MUSIC",
		"lines": [
			"main_menu — \"Tragic Ambient Main Menu\" by yd (CC0)",
			"map — \"Loopable Dungeon Ambience\" by Spring (CC0)",
			"combat (Act 1) — random pick from:",
			"     \"Battle Theme A\" by cynicmusic (CC0)",
			"     \"Out Of Time\" by Jonathan Shaw (CC-BY 3.0)",
			"combat (Act 2) — random pick from:",
			"     \"A Fight in the Fields\" by Jonathan Shaw (CC-BY 3.0)",
			"     \"JRPG Epic Rock Battle Theme #1\" by HydroGene (CC0)",
			"combat (Act 3) — random pick from:",
			"     \"The Tread of War\" by Jonathan Shaw, Johan Brodd & cynicmusic (CC-BY 3.0)",
			"     \"Boss Battle #6 Metal\" by nene (CC0)",
			"combat_elite — \"Fierce Battle!\" by remaxim (CC0)",
			"combat_boss — \"Battle RPG Theme\" by CleytonRX (CC0)",
			"boss (Act 3) — \"Boss Battle #2: Symphonic Metal\" by nene (CC0)",
			"shop — \"Medieval: Market Day\" by RandomMind (CC0)",
			"rest — \"Ambient Relaxing Loop\" by isaiah658 (CC0)",
			"event — \"Dark Cavern Ambient\" by remaxim (CC0)",
			"victory — \"Victory Theme for RPG\" by cynicmusic (CC0)",
			"defeat — \"The Fallen\" by Jonathan Shaw (CC-BY 3.0)",
			"Jonathan Shaw — www.jshaw.co.uk",
			"CC0 + CC-BY 3.0 tracks from OpenGameArt.org",
		],
	},
]


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	_build_ui()


func _build_ui() -> void:
	var vp := get_viewport_rect().size

	# ── Title ──
	var title := _make_display_label("CREDITS", 60, GILT_BRIGHT)
	title.add_theme_color_override("font_outline_color", Color(0.55, 0.18, 0.05, 0.90))
	title.add_theme_constant_override("outline_size", 8)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 36
	title.offset_bottom = 110
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# ── Scrollable list of credit sections ──
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 130
	scroll.offset_bottom = -110
	scroll.offset_left = 180
	scroll.offset_right = -180
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 20)
	scroll.add_child(list)

	for section in SECTIONS:
		list.add_child(_make_section(section))

	# Bottom decorative line + thank-you note
	list.add_child(_make_ornament_row(280.0))
	var thanks := _make_display_label("Thank you for playing.", 18, PARCHMENT)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(thanks)

	# ── Back button — bottom center, pill style ──
	var back_btn := GameTheme.make_back_button("BACK TO MENU", Vector2(220, 48))
	# Manual bottom-center anchoring (PRESET_CENTER_BOTTOM + position pushes it
	# off-screen because PRESET treats position relative to the anchored point).
	back_btn.anchor_left = 0.5
	back_btn.anchor_right = 0.5
	back_btn.anchor_top = 1.0
	back_btn.anchor_bottom = 1.0
	back_btn.offset_left = -110
	back_btn.offset_right = 110
	back_btn.offset_top = -76
	back_btn.offset_bottom = -28
	back_btn.pressed.connect(func():
		GameTheme.fade_out_then_change_scene(self, MENU_SCENE, 0.30))
	add_child(back_btn)


func _make_section(section: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var heading := _make_display_label(section.get("heading", ""), 22, GILT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)

	for line_text in section.get("lines", []):
		var line := _make_body_label(line_text, 15, IVORY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)

	return box


func _make_display_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_body_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_ornament_row(width: float) -> Control:
	# Gold line broken by a central diamond — matches the main menu ornament.
	# Uses a texture diamond (assets/icons/diamond.png) instead of the U+25C6
	# unicode glyph so it doesn't depend on whether the display font ships
	# that codepoint. Lines forced to a fixed thin height so they don't
	# stretch into chunky rectangles next to the diamond.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(width * 0.45, 2)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = Color(GILT.r, GILT.g, GILT.b, 0.55)
	row.add_child(left)

	var diamond_tex := load("res://assets/icons/diamond.png") as Texture2D
	if diamond_tex != null:
		var diamond := TextureRect.new()
		diamond.texture = diamond_tex
		diamond.custom_minimum_size = Vector2(14, 14)
		diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		diamond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		diamond.modulate = GILT_BRIGHT
		diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(diamond)

	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(width * 0.45, 2)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.color = Color(GILT.r, GILT.g, GILT.b, 0.55)
	row.add_child(right)
	return row
