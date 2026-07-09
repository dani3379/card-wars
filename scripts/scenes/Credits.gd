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
			"Kreon — Julia Petretta — SIL Open Font License",
			"Inter — Rasmus Andersson — SIL Open Font License",
			"Marcellus — Astigmatic — SIL Open Font License",
			"Nunito — Vernon Adams — SIL Open Font License",
		],
	},
	{
		"heading": "ART — UI & ICONS",
		"lines": [
			"Kenney Fantasy UI Borders — CC0",
			"Kenney Board Game Icons — CC0",
			"Kenney Game Icons — CC0",
			"game-icons.net — Lorc, Delapouite, willdabeast, sbed",
			"     & contributors — CC-BY 3.0",
			"Fantasy RPG Icons — Lucas (pbmojART) — CC-BY 3.0",
			"Painterly Spell Icons — J. W. Bjerk (eleazzaar) — CC-BY 3.0",
		],
	},
	{
		"heading": "ART — CARDS & PORTRAITS",
		"lines": [
			"Public-domain masters: Gustave Doré, Mikhail Vrubel,",
			"Henry Fuseli, Goya, Bruegel, Bosch, and others",
		],
	},
	{
		"heading": "MUSIC",
		"lines": [
			"Alexander Nakarada (CreatorChords) — CC-BY 4.0 — creatorchords.com",
			"     Battle of the Creek · Valhalla · Medieval Metal",
			"     Prepare for War · Medieval Loop One · Medieval Chateau",
			"Scott Buckley — CC-BY 4.0 — scottbuckley.com.au",
			"     Song of the Forge · Simulacra · Eyes in the Void",
			"     Penumbra · Memories of Stone",
			"Matthew Pablo — CC-BY 3.0 — matthewpablo.com",
			"     Heroic Demise · The Dark Amulet",
			"Jonathan Shaw — CC-BY 3.0 — www.jshaw.co.uk",
			"     Out of Time · A Fight in the Fields · The Fallen",
			"     The Tread of War (with Johan Brodd & cynicmusic)",
			"RandomMind — CC0 — the Medieval series:",
			"     Market Day · Battle · Exploration · The Old Tower Inn",
			"     The Bard's Tale · Minstrel Dance",
			"cynicmusic — CC0 — Battle Theme A · Victory Theme for RPG",
			"yd · Spring · HydroGene · nene · remaxim · CleytonRX · isaiah658",
			"     — CC0 tracks from OpenGameArt.org",
		],
	},
]


func _ready() -> void:
	GameTheme.add_atmosphere(self, "main_menu")
	_build_ui()
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc = the BACK button: return to the main menu.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.fade_out_then_change_scene(self, MENU_SCENE, 0.30)
		get_viewport().set_input_as_handled()


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

	var diamond_tex := GameTheme.tex_icon_diamond
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
