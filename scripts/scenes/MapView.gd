extends Control
## MapView.gd — the run map. Currently a simple linear progression: shows
## all 8 floors in a row, the next one is highlighted, click it to advance.
## Replace later with a proper Slay-the-Spire branching map.

const COMBAT_SCENE = "res://scenes/combat.tscn"
const MAIN_MENU = "res://scenes/main_menu.tscn"


func _ready() -> void:
	if not RunState.run_active:
		# Got here without an active run — bounce to menu
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	_build_map()


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
