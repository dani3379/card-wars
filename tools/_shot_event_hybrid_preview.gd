extends Node
## Visual-only hybrid: full-bleed event art plus a compact vertical choice ladder.

const EVENT_SCENE := "res://scenes/event.tscn"
const EVENT_ID := "the_siege_kitchen"
const ART_PATH := "res://assets/events/the_siege_kitchen-finished-example.png"
const OUTPUT_PATH := "res://tools/screenshot/_event_siege_kitchen_hybrid_preview.png"


func _ready() -> void:
	RunState.run_active = true
	RunState.gold = 180
	RunState.hero_hp = 18
	RunState.hero_max_hp = 30
	await get_tree().process_frame

	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame

	for node_name in ["EventArt", "EventOverlayLeft"]:
		var old = ev.get_node_or_null(node_name)
		if old != null:
			ev.remove_child(old)
			old.free()
	ev._clear_ui()
	await get_tree().process_frame

	ev._event_id = EVENT_ID
	ev._event_data = ev.EVENTS[EVENT_ID].duplicate(true)
	# Exact 16:9 plate: no focal crop, so this preview tests UI rather than art.
	ev._event_data["presentation"] = {"layout": "folio"}
	ev._current_node = ev._event_data
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image_path = ART_PATH
	var raw_image := Image.load_from_file(ProjectSettings.globalize_path(ART_PATH))
	ev._event_image = ImageTexture.create_from_image(raw_image)
	ev._ensure_fullscreen_art(ev._event_image)
	ev._set_event_art_visible(true)
	_build_hybrid(ev)
	ev._refresh_ledger()

	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Could not save hybrid event preview: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("[event-hybrid] SAVED ", OUTPUT_PATH, " ", image.get_size())
	get_tree().quit()


func _build_hybrid(ev: Node) -> void:
	var title = ev._make_event_title(ev._sub_campaign_tokens(String(ev._event_data.name)))
	ev._place_event_control(title, Rect2(80, 58, 700, 76))
	ev.add_child(title)
	GameTheme.deal_in(title, 0.02)

	var desc_copy = ev._illuminate_desc(ev._sub_campaign_tokens(
		String(ev._current_node.get("desc", ""))))
	var desc = ev._make_event_desc(desc_copy)
	ev._place_event_control(desc, Rect2(80, 145, 700, 176))
	ev.add_child(desc)
	GameTheme.write_on(desc, 0.10)

	var prompt := Label.new()
	prompt.text = "CHOOSE YOUR ANSWER"
	prompt.position = Vector2(84, 336)
	prompt.size = Vector2(700, 28)
	prompt.add_theme_font_size_override("font_size", 14)
	prompt.add_theme_color_override("font_color", Color(0.83, 0.67, 0.39, 0.92))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.90))
	prompt.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_body:
		prompt.add_theme_font_override("font", GameTheme.font_body)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ev.add_child(prompt)

	var ladder := VBoxContainer.new()
	ladder.name = "HybridChoiceLadder"
	ladder.position = Vector2(80, 372)
	ladder.size = Vector2(720, 342)
	ladder.add_theme_constant_override("separation", 8)
	ev.add_child(ladder)

	var choices: Array = ev._visible_event_choices()
	var ordinal := 1
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var number := -1
		if not choice.has("blue"):
			number = ordinal
			ordinal += 1
		var row := _make_choice_row(ev, choice, number)
		ladder.add_child(row)
		GameTheme.deal_in(row, 0.11 + float(i) * 0.055)

	var walk = ev._make_walk_on_button()
	ev.add_child(walk)


func _make_choice_row(ev: Node, choice: Dictionary, ordinal: int) -> Button:
	var parts: Dictionary = ev._event_choice_parts(choice)
	var row := Button.new()
	row.flat = false
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(720, 102)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.015, 0.012, 0.08)
	normal.set_border_width_all(0)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.075, 0.035, 0.55)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.10, 0.04, 0.68)
	for state in ["normal", "focus", "disabled"]:
		row.add_theme_stylebox_override(state, normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", pressed)

	var accent := ColorRect.new()
	accent.color = Color(0.82, 0.60, 0.27, 0.78)
	accent.position = Vector2(0, 10)
	accent.size = Vector2(3, 76)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(accent)

	var numeral := Label.new()
	var romans := ["I", "II", "III", "IV"]
	numeral.text = "◆" if choice.has("blue") else romans[mini(ordinal, romans.size()) - 1]
	numeral.position = Vector2(18, 13)
	numeral.size = Vector2(48, 30)
	numeral.add_theme_font_size_override("font_size", 17)
	numeral.add_theme_color_override("font_color", Color(0.86, 0.70, 0.42))
	if GameTheme.font_body:
		numeral.add_theme_font_override("font", GameTheme.font_body)
	numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(numeral)

	var headline := Label.new()
	headline.text = String(parts.headline)
	headline.position = Vector2(72, 9)
	headline.size = Vector2(390, 38)
	headline.add_theme_font_size_override("font_size", 24)
	headline.add_theme_color_override("font_color", GameTheme.IVORY)
	headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	headline.add_theme_constant_override("outline_size", 3)
	if GameTheme.font_display:
		headline.add_theme_font_override("font", GameTheme.font_display)
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(headline)

	var effect := RichTextLabel.new()
	effect.bbcode_enabled = true
	effect.fit_content = false
	effect.scroll_active = false
	effect.text = "[right]" + String(parts.effect) + "[/right]"
	effect.position = Vector2(450, 12)
	effect.size = Vector2(250, 62)
	effect.add_theme_font_size_override("normal_font_size", 18)
	effect.add_theme_color_override("default_color", GameTheme.KEYWORD_GOLD)
	effect.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	effect.add_theme_constant_override("outline_size", 2)
	if GameTheme.font_body:
		effect.add_theme_font_override("normal_font", GameTheme.font_body)
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(effect)

	var rule := ColorRect.new()
	rule.color = Color(0.78, 0.58, 0.28, 0.20)
	rule.position = Vector2(72, 91)
	rule.size = Vector2(628, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row
