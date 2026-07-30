extends Node
# Multi-state map screenshot harness — shoots the map screen across the states
# that matter for visual verification: act 1 full island / focused open /
# mid-run (3 marches), then acts 2 and 3 full. Saves numbered PNGs to res://.
#   Godot.exe --path "D:\Godot" res://tools/_shot_map_states.tscn

const HERO_ID := "raider"

var _map: Node = null


func _ready() -> void:
	# Let the autoload boot (UserSettings applies saved window scale / SSAA a
	# frame or two in) SETTLE FIRST, then assert the probe's window state on
	# top of it — the other order leaves a 2x-scaled window and the captures
	# come out empty. Player settings on disk are untouched.
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	RunState.start_new_run(HERO_ID)
	await get_tree().process_frame

	await _open_map(3.5)
	_map._set_view(1.0, Vector2.ZERO)
	await _shoot("_shot_a1_full.png")
	_map._set_view(1.15, Vector2(1600, 900) * 0.5
		- (_map._player_pos if _map._has_player else _map._camp_pos) * 1.15)
	await _shoot("_shot_a1_open.png")
	_map._set_view(2.2, Vector2(1600, 900) * 0.5
		- (_map._island_center as Vector2) * 2.2)
	await _shoot("_shot_a1_zoom.png")
	_close_map()

	# March 3 stops deep (always take the first available node).
	for _i in range(3):
		var avail: Array = RunState.get_available_nodes()
		if avail.is_empty():
			break
		RunState.visit_node(int(avail[0].row), int(avail[0].col))
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	await _open_map(2.0)
	_map._set_view(1.0, Vector2.ZERO)
	await _shoot("_shot_a1_mid.png")
	_close_map()

	for act in [2, 3]:
		RunState.advance_act()
		await _open_map(3.5)
		_map._set_view(1.0, Vector2.ZERO)
		await _shoot("_shot_a%d_full.png" % act)
		_close_map()

	print("SHOTS_DONE")
	get_tree().quit()


func _open_map(settle: float) -> void:
	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	await get_tree().create_timer(settle).timeout


func _close_map() -> void:
	if _map != null and is_instance_valid(_map):
		_map.queue_free()
	_map = null
	# Let the free settle before the next open.
	await get_tree().process_frame
	await get_tree().process_frame


func _shoot(path: String) -> void:
	# Give the dress-mix re-record + bake swap a beat to land.
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	print("SAVED ", path)
