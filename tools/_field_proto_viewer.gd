extends Node
## _field_proto_viewer.gd — LIVE rating viewer for the four field-ground styles.
##   Godot.exe --path "D:\Godot" res://tools/_field_proto_viewer.tscn
## Boots straight into a real fight (borrowed_faces). Press 1-4 to rebuild the
## battle on each ground: 1 War Table · 2 The Meadow · 3 Obsidian Slate ·
## 4 Battle-Plan. The fight is fully playable on every ground. Esc quits.

const STYLE_NAMES := ["WAR TABLE", "THE MEADOW", "OBSIDIAN SLATE", "BATTLE-PLAN"]

var _combat: Node = null
var _banner: Label = null
var _switching := false


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	_build_banner()
	await _load_style(0)


func _build_banner() -> void:
	# Always-on-top strip naming the active ground + the controls. CanvasLayer
	# 120 sits above Combat's HUD layers.
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -34
	panel.offset_bottom = -4
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.03, 0.02, 0.85)
	st.border_color = Color(0.82, 0.66, 0.30, 0.8)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 14
	st.content_margin_right = 14
	panel.add_theme_stylebox_override("panel", st)
	layer.add_child(panel)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if GameTheme.font_display != null:
		_banner.add_theme_font_override("font", GameTheme.font_display)
	_banner.add_theme_font_size_override("font_size", 16)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 3)
	panel.add_child(_banner)


func _load_style(style: int) -> void:
	_switching = true
	if _banner != null:
		_banner.text = "LOADING…"
	if _combat != null and is_instance_valid(_combat):
		_combat.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	RunState.start_new_run("raider")
	RunState.gold = 138
	RunState.add_potion("healing")
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame
	# Untyped access on purpose — static var through a loaded script object.
	var combat_script = load("res://scripts/scenes/Combat.gd")
	combat_script.field_style_override = style
	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	if _banner != null:
		_banner.text = "%d/4  %s   —   press 1-4 to switch ground · Esc quits" \
			% [style + 1, STYLE_NAMES[style]]
	_switching = false


func _unhandled_key_input(event: InputEvent) -> void:
	if _switching or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _load_style(0)
		KEY_2: _load_style(1)
		KEY_3: _load_style(2)
		KEY_4: _load_style(3)
		KEY_ESCAPE:
			var combat_script = load("res://scripts/scenes/Combat.gd")
			combat_script.field_style_override = -1
			get_tree().quit()
		_:
			return
	get_viewport().set_input_as_handled()
