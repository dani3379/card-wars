extends Node
# Map screenshot harness — seeds a run so RunState carries a generated act map +
# player position, instances the real MapView, lets the plate bake, captures.
#   Godot.exe --path "D:\Godot" res://tools/_shot_map.tscn

const SHOT_PATH := "res://_shot_map.png"
const HERO_ID := "raider"


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	RunState.start_new_run(HERO_ID)
	await get_tree().process_frame

	var map: Node = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(map)

	# Plate bake + zoom-focus animation settle.
	await get_tree().create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(SHOT_PATH)
	print("MAP_SAVED ", ProjectSettings.globalize_path(SHOT_PATH),
		" rivals=", RunState.rival_lords)
	get_tree().quit()
