extends Control
## MapView.gd — the run map. Currently a simple linear progression: shows
## all 8 floors in a row, the next one is highlighted, click it to advance.
## Replace later with a proper Slay-the-Spire branching map.
##
## Also hosts deck inspection and the once-per-run "remove a card" event,
## so the player can thin their deck between fights.

const COMBAT_SCENE = "res://scenes/combat.tscn"
const MAIN_MENU = "res://scenes/main_menu.tscn"

var _overlay: ColorRect
var _panel: PanelContainer
var _remove_mode: bool = false


func _ready() -> void:
	if not RunState.run_active:
		# Got here without an active run — bounce to menu
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	_build_map()
	_build_deck_buttons()


func _build_map() -> void:
	# Clear placeholder children
	for child in $HBox.get_children():
		child.queue_free()

	for floor_num in range(1, RunState.FLOOR_COUNT + 1):
		var node_type = RunState.node_type_for_floor(floor_num)
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(110, 90)
		btn.text = _floor_label(floor_num, node_type)
		btn.disabled = (floor_num != RunState.current_floor + 1)
		btn.add_theme_font_size_override("font_size", 14)

		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		match node_type:
			"combat": style.bg_color = Color(0.20, 0.25, 0.35, 0.9)
			"elite":  style.bg_color = Color(0.55, 0.30, 0.20, 0.95)
			"boss":   style.bg_color = Color(0.65, 0.10, 0.10, 1.0)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", Color.WHITE)

		# Highlight already-completed floors
		if floor_num <= RunState.current_floor:
			btn.text = "✓ " + btn.text
			btn.modulate = Color(0.5, 0.6, 0.5)

		btn.pressed.connect(_on_floor_pressed.bind(floor_num))
		$HBox.add_child(btn)

	$HeroStatus.text = "♥ %d / %d        Deck: %d cards        Relics: %d" % [
		RunState.hero_hp, RunState.hero_max_hp,
		RunState.deck.size(), RunState.relics.size(),
	]


func _build_deck_buttons() -> void:
	# Two buttons in the top-right: "View Deck" and "Remove a Card" (if charges left).
	var hbox = $TopRight if has_node("TopRight") else null
	if hbox == null:
		hbox = HBoxContainer.new()
		hbox.name = "TopRight"
		hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		hbox.position = Vector2(-360, 20)
		hbox.add_theme_constant_override("separation", 8)
		add_child(hbox)
	for c in hbox.get_children():
		c.queue_free()

	var view_btn = Button.new()
	view_btn.text = "View Deck (%d)" % RunState.deck.size()
	view_btn.custom_minimum_size = Vector2(150, 36)
	view_btn.pressed.connect(_open_deck_view.bind(false))
	hbox.add_child(view_btn)

	var remove_btn = Button.new()
	remove_btn.text = "Remove a Card (%d)" % RunState.card_removals_remaining
	remove_btn.custom_minimum_size = Vector2(180, 36)
	remove_btn.disabled = RunState.card_removals_remaining <= 0
	remove_btn.pressed.connect(_open_deck_view.bind(true))
	hbox.add_child(remove_btn)


func _floor_label(floor_num: int, node_type: String) -> String:
	var icon = ""
	match node_type:
		"combat": icon = "⚔"
		"elite":  icon = "★"
		"boss":   icon = "☠"
	return "%s\nFloor %d\n%s" % [icon, floor_num, node_type.capitalize()]


func _on_floor_pressed(floor_num: int) -> void:
	if floor_num != RunState.current_floor + 1:
		return
	RunState.advance_floor()
	get_tree().change_scene_to_file(COMBAT_SCENE)


# ── Deck overlay ──
func _open_deck_view(remove_mode: bool) -> void:
	_remove_mode = remove_mode
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.7)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(900, 600)
	_panel.position = Vector2(-450, -300)
	var pstyle = StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.06, 0.10, 1.0)
	pstyle.corner_radius_top_left = 10
	pstyle.corner_radius_top_right = 10
	pstyle.corner_radius_bottom_left = 10
	pstyle.corner_radius_bottom_right = 10
	pstyle.content_margin_left = 16
	pstyle.content_margin_right = 16
	pstyle.content_margin_top = 14
	pstyle.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", pstyle)
	_overlay.add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Remove a Card  —  click to delete (permanent)" if remove_mode else "Your Deck"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45) if remove_mode else Color.WHITE)
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(870, 480)
	vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	# Group identical cards together with a count badge.
	var counts: Dictionary = {}
	for id in RunState.deck:
		counts[id] = counts.get(id, 0) + 1

	for id in counts.keys():
		var data = CardDB.get_card_data(id)
		if data.is_empty(): continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(200, 90)
		btn.text = "%s  ×%d\n%d⚡  %d/%d\n%s" % [
			data.name, counts[id],
			data.cost, data.atk, data.hp,
			KeywordEffects.display_text_for(data.get("keywords", [])),
		]
		btn.add_theme_font_size_override("font_size", 13)
		btn.tooltip_text = data.get("desc", "")
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.bg_color = _tier_color(data.get("tier", 1))
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", Color.WHITE)
		if remove_mode:
			btn.pressed.connect(_remove_card.bind(id))
		grid.add_child(btn)

	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(100, 32)
	close.pressed.connect(_close_overlay)
	vbox.add_child(close)


func _tier_color(tier: int) -> Color:
	match tier:
		1: return Color(0.20, 0.25, 0.35)
		2: return Color(0.45, 0.30, 0.55)
		3: return Color(0.70, 0.45, 0.20)
	return Color(0.20, 0.25, 0.35)


func _remove_card(id: String) -> void:
	if RunState.card_removals_remaining <= 0: return
	if RunState.deck.size() <= 1:
		# Don't let the player softlock themselves with an empty deck.
		return
	if RunState.remove_card(id):
		RunState.card_removals_remaining -= 1
	_close_overlay()
	_build_map()
	_build_deck_buttons()


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		_panel = null
