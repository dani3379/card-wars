extends Node

# TEMPORARY screenshot harness. Boots a representative Act-1 combat, waits for
# the board to settle, captures the root viewport to a PNG, and quits.
# Remove this file + its autoload entry in project.godot when done.

func _ready() -> void:
	call_deferred("_go")

func _go() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	RunState.start_new_run("raider")
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_node_type = "combat"
	get_tree().change_scene_to_file("res://scenes/combat.tscn")
	await get_tree().create_timer(7.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_shot_combat.png")
	print("[_shot] saved res://_shot_combat.png  size=", img.get_size())
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
