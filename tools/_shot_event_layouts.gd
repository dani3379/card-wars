extends Node
## Focused visual/runtime verifier for the four ordinary-event compositions.

const EVENT_SCENE := "res://scenes/event.tscn"
const CASES := [
	{"id": "the_siege_kitchen", "layout": "character", "node": "ChoiceDevices"},
	{"id": "the_crossing", "layout": "location", "node": "ChoiceDevices"},
	{"id": "pawnbrokers_window", "layout": "bargain", "node": "ChoiceContracts"},
	{"id": "sin_eater", "layout": "ritual", "node": "ChoiceSeals"},
]

var _fails := 0


func _ready() -> void:
	RunState.start_new_run("stalwart")
	RunState.gold = 180
	RunState.hero_hp = 18
	await get_tree().process_frame
	for test in CASES:
		var ev = await _spawn_event(String(test.id))
		await get_tree().create_timer(0.85).timeout
		_check(ev._event_presentation_layout() == String(test.layout),
			"%s selected %s" % [test.id, test.layout])
		_check(not ev.find_children("EventLayoutStage*", "", false, false).is_empty(),
			"%s built layout stage" % test.id)
		_check(not ev.find_children(String(test.node) + "*", "", false, false).is_empty(),
			"%s built choice composition" % test.id)
		await _capture(String(test.layout))
		var visible_choices: Array = ev._visible_event_choices()
		if not visible_choices.is_empty():
			ev._selected_choice_for_result = visible_choices[0]
		ev._show_result("The company carries the consequence onto the road. Gained 12 gold.")
		await get_tree().create_timer(0.55).timeout

		_check(not ev.find_children("OutcomeStamp", "Label", true, false).is_empty(),
			"%s stamped its selected choice" % test.id)
		await _capture(String(test.layout) + "_result")
		ev.queue_free()
		await get_tree().process_frame
	print("[event-layouts] ALL PASS" if _fails == 0 else
		"[event-layouts] FAILURES=%d" % _fails)
	get_tree().quit(_fails)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		push_error("  FAIL  " + label)


func _spawn_event(id: String) -> Node:
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
	ev._event_id = id
	ev._event_data = ev.EVENTS[id]
	ev._current_node = ev._event_data
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image = null
	ev._event_image_path = ""
	ev._build_ui()
	ev._begin_event_art_hydration()
	return ev


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://tools/screenshot/_event_layout_%s.png" % tag)
	print("  SAVED  ", tag, " ", image.get_size())
