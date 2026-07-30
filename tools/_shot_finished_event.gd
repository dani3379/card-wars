extends Node
## Renders one production-style event example through the live Event scene.

const EVENT_SCENE := "res://scenes/event.tscn"
const EVENT_ID := "the_siege_kitchen"
const ART_PATH := "res://assets/events/the_siege_kitchen-finished-example.png"
const OUTPUT_PATH := "res://tools/screenshot/_event_finished_siege_kitchen.png"


func _ready() -> void:
	RunState.run_active = true
	RunState.gold = 180
	RunState.hero_hp = 18
	RunState.hero_max_hp = 30
	await get_tree().process_frame

	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame

	# Cancel the scene's random-event hydration and rebuild it with the example art.
	for node_name in ["EventArt", "EventOverlayLeft"]:
		var node = ev.get_node_or_null(node_name)
		if node != null:
			ev.remove_child(node)
			node.free()
	ev._clear_ui()
	await get_tree().process_frame

	ev._event_id = EVENT_ID
	ev._event_data = ev.EVENTS[EVENT_ID].duplicate(true)
	ev._event_data["presentation"] = {
		"layout": "confrontation",
		"focal_uv": Vector2(0.73, 0.48),
		"zoom": 1.02,
	}
	ev._current_node = ev._event_data
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image_path = ART_PATH
	var raw_image := Image.load_from_file(ProjectSettings.globalize_path(ART_PATH))
	ev._event_image = ImageTexture.create_from_image(raw_image)
	ev._build_ui()

	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Could not save finished event example: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("[finished-event] SAVED ", OUTPUT_PATH, " ", image.get_size())
	get_tree().quit()
