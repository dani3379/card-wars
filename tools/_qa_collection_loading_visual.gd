extends Node


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		get_tree().quit(1))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().process_frame
	var scene: Control = load("res://scenes/collection.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await _shot("collection_loading_cards")

	var content: VBoxContainer = scene.get("_content")
	var generation: int = int(scene.get("_view_gen"))
	for _i in 360:
		if int(content.get_meta("collection_stage_generation", -1)) == generation:
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.55).timeout
	await _shot("collection_loaded_cards")

	scene.call("show_tab", "relics")
	await get_tree().process_frame
	await _shot("collection_loading_relics")
	print("COLLECTION_LOADING_VISUAL_DONE")
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("res://tools/screenshot/_qa_%s.png" % name)
	print("SAVED ", name, " ", image.get_size())

