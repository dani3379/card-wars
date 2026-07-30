extends Node
## Renders the revised character-stage event through the live Event scene.

const EVENT_SCENE := "res://scenes/event.tscn"
const EVENT_ID := "the_siege_kitchen"
const ART_PATH := "res://assets/events/the_siege_kitchen-character-stage-v2.png"
const OUTPUT_PATH := "res://tools/screenshot/_event_finished_siege_kitchen_v2.png"


func _ready() -> void:
	RunState.run_active = true
	RunState.gold = 180
	RunState.hero_hp = 18
	RunState.hero_max_hp = 30
	await get_tree().process_frame

	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame

	for node_name in ["EventArt", "EventOverlayLeft"]:
		var node = ev.get_node_or_null(node_name)
		if node != null:
			ev.remove_child(node)
			node.free()
	ev._clear_ui()
	await get_tree().process_frame

	ev._event_id = EVENT_ID
	ev._event_data = ev.EVENTS[EVENT_ID].duplicate(true)
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
		push_error("Could not save revised event example: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("[finished-event-v2] SAVED ", OUTPUT_PATH, " ", image.get_size())

	var choices: Array = ev._visible_event_choices()
	if not choices.is_empty():
		ev._selected_choice_for_result = choices[0]
		ev._show_result("The company joins the line. The cook fills every bowl before asking a name. Recovered 9 HP.")
		await get_tree().create_timer(0.65).timeout
		await RenderingServer.frame_post_draw
		var result_image: Image = get_viewport().get_texture().get_image()
		var result_path := "res://tools/screenshot/_event_finished_siege_kitchen_v2_result.png"
		error = result_image.save_png(result_path)
		if error != OK:
			push_error("Could not save revised result example: %s" % error_string(error))
			get_tree().quit(1)
			return
		print("[finished-event-v2] SAVED ", result_path, " ", result_image.get_size())
	get_tree().quit()
