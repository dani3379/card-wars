extends Control
## MapView.gd — Branching map across 3 acts. Player clicks connected nodes
## to advance. Node types: combat, elite, boss, rest, shop, event.

const COMBAT_SCENE = "res://scenes/combat.tscn"
const SHOP_SCENE = "res://scenes/shop.tscn"
const REST_SCENE = "res://scenes/rest.tscn"
const EVENT_SCENE = "res://scenes/event.tscn"
const MAIN_MENU = "res://scenes/main_menu.tscn"

const NODE_ICONS: Dictionary = {
	"combat": "⚔", "elite": "★", "boss": "☠",
	"rest": "♨", "shop": "🪙", "event": "?",
}
const NODE_COLORS: Dictionary = {
	"combat": Color(0.20, 0.25, 0.35, 0.95),
	"elite":  Color(0.55, 0.30, 0.20, 0.95),
	"boss":   Color(0.65, 0.10, 0.10, 1.0),
	"rest":   Color(0.15, 0.40, 0.25, 0.95),
	"shop":   Color(0.40, 0.35, 0.15, 0.95),
	"event":  Color(0.30, 0.20, 0.45, 0.95),
}
const NODE_SIZE := Vector2(110, 70)
const ROW_SPACING := 90.0
const COL_SPACING := 140.0

var _node_buttons: Dictionary = {}
var _available_positions: Array = []
var _canvas: Control
var _connection_drawer: Control


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	_build_map()


func _build_map() -> void:
	for child in get_children():
		if child.name != "Background":
			child.queue_free()

	var act_map = RunState.get_current_act_map()
	if act_map.is_empty():
		return

	var act_label = Label.new()
	act_label.text = "ACT %d" % RunState.get_act()
	act_label.add_theme_font_size_override("font_size", 28)
	act_label.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act_label.position = Vector2(700, 15)
	act_label.size = Vector2(200, 40)
	add_child(act_label)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	# Single draw node for all connection lines (replaces many Line2D nodes)
	_connection_drawer = Control.new()
	_connection_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_connection_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_connection_drawer)

	var available = RunState.get_available_nodes()
	_available_positions = []
	for node in available:
		_available_positions.append(Vector2i(node.row, node.col))

	_node_buttons.clear()
	var total_rows = act_map.size()

	# Collect connection line data for batch drawing
	var lines: Array = []
	for row_idx in range(total_rows):
		var row = act_map[row_idx]
		var row_count = row.size()
		for col_idx in range(row_count):
			var node = row[col_idx]
			var pos = _node_position(row_idx, col_idx, row_count, total_rows)
			_collect_connections(node, act_map, lines)
			var btn = _create_node_button(node, pos)
			_canvas.add_child(btn)
			_node_buttons[Vector2i(row_idx, col_idx)] = btn

	# Draw all connections in a single _draw() call
	_connection_drawer.draw.connect(func():
		for line in lines:
			_connection_drawer.draw_line(line.from, line.to, line.color, line.width)
	)
	_connection_drawer.queue_redraw()

	_build_status_bar()
	_build_potion_button()


func _node_position(row: int, col: int, cols_in_row: int, total_rows: int) -> Vector2:
	var center_x = 800.0
	var top_y = 70.0
	var row_y = top_y + (total_rows - 1 - row) * ROW_SPACING
	var total_width = (cols_in_row - 1) * COL_SPACING
	var start_x = center_x - total_width / 2.0
	return Vector2(start_x + col * COL_SPACING, row_y)


func _create_node_button(node: Dictionary, pos: Vector2) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = NODE_SIZE
	btn.size = NODE_SIZE
	btn.position = pos - NODE_SIZE / 2.0

	var ntype: String = node.type
	var icon = NODE_ICONS.get(ntype, "?")
	var label = ntype.capitalize()
	if ntype in ["combat", "elite", "boss"] and node.encounter_id != "":
		var enc = EncounterDB.get_encounter(node.encounter_id)
		if not enc.is_empty():
			label = enc.name
	btn.text = "%s\n%s" % [icon, label]
	btn.add_theme_font_size_override("font_size", 12)

	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.bg_color = NODE_COLORS.get(ntype, Color(0.2, 0.2, 0.2))

	var is_available = _available_positions.has(Vector2i(node.row, node.col))
	if node.visited:
		btn.modulate = Color(0.4, 0.5, 0.4)
		btn.disabled = true
		btn.text = "✓ " + btn.text
	elif is_available:
		style.border_color = Color(1.0, 0.85, 0.3)
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_width_left = 2
		style.border_width_right = 2
		btn.disabled = false
	else:
		btn.modulate = Color(0.6, 0.6, 0.6, 0.7)
		btn.disabled = true

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.pressed.connect(_on_node_pressed.bind(node.row, node.col))
	return btn


func _collect_connections(node: Dictionary, act_map: Array, lines: Array) -> void:
	var next_row_idx = node.row + 1
	if next_row_idx >= act_map.size():
		return
	var next_row = act_map[next_row_idx]
	var from_pos = _node_position(node.row, node.col, act_map[node.row].size(), act_map.size())
	for target_col in node.connections:
		if target_col >= next_row.size():
			continue
		var to_pos = _node_position(next_row_idx, target_col, next_row.size(), act_map.size())
		var color = Color(0.4, 0.35, 0.25, 0.6)
		var width = 2.0
		if node.visited:
			color = Color(0.7, 0.6, 0.3, 0.8)
			width = 3.0
		lines.append({"from": from_pos, "to": to_pos, "color": color, "width": width})


func _build_status_bar() -> void:
	var bar = Label.new()
	bar.text = "♥ %d / %d    💰 %d    Deck: %d    Relics: %d" % [
		RunState.hero_hp, RunState.hero_max_hp,
		RunState.gold, RunState.deck.size(), RunState.relics.size(),
	]
	if RunState.potions > 0:
		bar.text += "    🧪 %d" % RunState.potions
	bar.add_theme_font_size_override("font_size", 18)
	bar.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.position = Vector2(500, 830)
	bar.size = Vector2(600, 30)
	add_child(bar)


func _build_potion_button() -> void:
	if RunState.potions <= 0:
		return
	var btn = Button.new()
	btn.text = "Use Potion (heal 8)"
	btn.custom_minimum_size = Vector2(140, 36)
	btn.position = Vector2(1400, 825)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func():
		if RunState.use_potion():
			_build_map()
	)
	add_child(btn)


func _on_node_pressed(row: int, col: int) -> void:
	if not _available_positions.has(Vector2i(row, col)):
		return
	RunState.visit_node(row, col)
	var ntype = RunState.current_node_type
	var target_scene: String = ""
	match ntype:
		"combat", "elite", "boss":
			target_scene = COMBAT_SCENE
		"shop":
			target_scene = SHOP_SCENE
		"rest":
			target_scene = REST_SCENE
		"event":
			target_scene = EVENT_SCENE
	if target_scene != "":
		var err = get_tree().change_scene_to_file(target_scene)
		if err != OK:
			push_error("MapView: failed to load scene '%s' (error %d)" % [target_scene, err])
	else:
		push_warning("MapView: unknown node type '%s' at (%d,%d)" % [ntype, row, col])
