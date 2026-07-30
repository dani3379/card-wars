extends Node
## _shot_more_menus.gd — renders shell screens not covered by the other harnesses
## (skirmish lobby, wayside verbs, hero-select) to PNG for a quality audit
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_more_menus.tscn
## Outputs tools/screenshot/_more_<name>.png

var _scene: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("raider")
	RunState.gold = 214
	RunState.hero_hp = 22
	await get_tree().process_frame

	# Skirmish lobby.
	await _shoot("net_lobby", "res://scenes/net_lobby.tscn")

	# Wayside verbs.
	RunState.current_wayside_id = "supply_cache"
	await _shoot("wayside_cache", "res://scenes/wayside.tscn")
	RunState.current_wayside_id = "drill_yard"
	await _shoot("wayside_drill", "res://scenes/wayside.tscn")
	RunState.current_wayside_id = "standard_bearer"
	await _shoot("wayside_banner", "res://scenes/wayside.tscn")

	# Hero-select subscreen (built on the main menu).
	_scene = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.2).timeout
	if _scene.has_method("_show_hero_select"):
		_scene.call("_show_hero_select")
		await get_tree().create_timer(1.0).timeout
		await _snap("hero_select")
	_scene.queue_free()
	await get_tree().process_frame

	print("MORE_MENUS_DONE")
	get_tree().quit()


func _shoot(name: String, path: String) -> void:
	_scene = load(path).instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.3).timeout
	await _snap(name)
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_more_%s.png" % state)
	print("SAVED ", state, " ", img.get_size())
