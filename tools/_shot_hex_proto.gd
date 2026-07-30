extends Node
# Contact-sheet harness for the hex war-board prototype — shoots the board
# mid-run (act 1), the scout-fog variant, act 3's charred palette, and a
# lean-in zoom on the marching front. Saves PNGs to res://.
#   Godot.exe --path "D:\Godot" res://tools/_shot_hex_proto.tscn

var _proto: Control = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame

	await _open(1, false, 5)
	await _shoot("_shot_hex_board.png")
	# Lean-in on the marching front while the board variant is still up.
	var focus: Vector2 = _proto.get_focus_pos()
	_proto.scale = Vector2(1.9, 1.9)
	_proto.position = Vector2(800, 450) - focus * 1.9
	await _shoot("_shot_hex_zoom.png")
	_close()

	await _open(1, true, 5)
	await _shoot("_shot_hex_fog.png")
	_close()

	await _open(3, false, 5)
	await _shoot("_shot_hex_act3.png")
	_close()

	print("SHOTS_DONE")
	get_tree().quit()


func _open(act_n: int, fog: bool, marched_n: int) -> void:
	_proto = load("res://scenes/map_hex_proto.tscn").instantiate()
	_proto.act = act_n
	_proto.fog_variant = fog
	_proto.marched = marched_n
	get_tree().root.add_child(_proto)
	await get_tree().create_timer(0.8).timeout


func _close() -> void:
	if _proto != null and is_instance_valid(_proto):
		_proto.queue_free()
	_proto = null


func _shoot(path: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	print("SAVED ", path)
