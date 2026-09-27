extends Node


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	RunState.start_new_run("stalwart", 0, 9797)
	RunState.hero_hp = 12
	var ev = load("res://scenes/event.tscn").instantiate()
	add_child(ev)
	await get_tree().process_frame
	for node_name in ["EventArt", "EventOverlayLeft"]:
		var old = ev.get_node_or_null(node_name)
		if old != null:
			ev.remove_child(old)
			old.free()
	ev._clear_ui()
	ev._event_id = "the_siege_kitchen"
	ev._event_data = ev.EVENTS[ev._event_id]
	ev._current_node = ev._event_data
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image = null
	ev._event_image_path = ""
	ev._build_ui()
	ev._begin_event_art_hydration()
	await get_tree().create_timer(1.3).timeout
	var groups := ev.find_children("ChoiceDevices", "", true, false)
	if groups.is_empty() or groups[0].get_child_count() == 0:
		push_error("EVENT_CHOICE_VISUAL_NO_CHOICES")
		get_tree().quit(1)
		return
	var first := groups[0].get_child(0) as BaseButton
	first.pressed.emit()
	await get_tree().create_timer(0.06).timeout
	await _snap("mid")
	await get_tree().create_timer(0.48).timeout
	await _snap("result")
	print("EVENT_CHOICE_VISUAL_DONE")
	get_tree().quit()


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_qa_event_choice_%s.png" % tag)
