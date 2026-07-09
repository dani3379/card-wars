extends SceneTree
## Click-through verifier (frame-accurate): drive modal-picker event flows all
## the way to the result screen and assert the final Continue transitions out.

var RS: Node
var CDB: Node
var EVENTS: Dictionary = {}
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	RS  = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	var EvScript = load("res://scripts/scenes/Event.gd")
	EVENTS = EvScript.EVENTS

	await _flow("pawnbrokers_window", "Trade Coin", 60)   # pay + upgrade picker
	await _flow("beekeeper", "Ask what the hive", 0)        # remove picker
	await _flow("woodcutter", "Take the axe", 0)            # risk_loop jackpot
	await _flow("the_bone_pit", "Take the open seat", 0)    # dice_run
	print("[stuck2] DONE")
	quit(0)


func _fixture() -> void:
	RS.start_new_run("raider", 0, 4242)
	RS.gold = 500
	RS.hero_hp = RS.hero_max_hp


func _all_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_all_buttons(c, out)


func _labels_under(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(String((c as Label).text))
		elif c is RichTextLabel:
			out.append(String((c as RichTextLabel).text))
		out.append_array(_labels_under(c))
	return out


func _find_button(ev, substr: String):
	var btns: Array = []
	_all_buttons(ev, btns)
	for b in btns:
		if substr.to_lower() in String(b.text).to_lower():
			return b
		for lbl in _labels_under(b):
			if substr.to_lower() in lbl.to_lower():
				return b
	return null


func _overlay() -> bool:
	for c in root.get_children():
		if c is ColorRect and c.z_index >= 1000:
			return true
	return false


func _clear_overlay() -> void:
	for c in root.get_children():
		if c is ColorRect and c.z_index >= 1000:
			c.free()


func _flow(event_id: String, choice_substr: String, expect_pay: int) -> void:
	_fixture()
	var start_gold: int = RS.gold
	var ev = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)
	ev._event_id = event_id
	ev._event_data = EVENTS[event_id]
	ev._current_node = EVENTS[event_id]
	ev._build_ui()
	await process_frame

	# Click the named top-level choice.
	var choices: Array = EVENTS[event_id]["choices"]
	var picked: Dictionary = {}
	for c in choices:
		if choice_substr.to_lower() in String(c.get("label", "")).to_lower():
			picked = c; break
	ev._resolve_choice(picked)
	await process_frame
	await process_frame

	# If a picker/loop screen is up, click the FIRST freshly-wired tile/action a
	# few times to reach a result. (Frame settled, so only the new screen's
	# buttons remain.)
	for _step in range(4):
		if _overlay():
			break
		var cont = _find_button(ev, "Continue")
		if cont != null:
			break
		var btns: Array = []
		_all_buttons(ev, btns)
		var clicked := false
		for b in btns:
			if b.pressed.get_connections().size() > 0:
				b.pressed.emit(); clicked = true; break
		if not clicked:
			break
		await process_frame
		await process_frame

	var paid: int = start_gold - RS.gold
	var cont2 = _find_button(ev, "Continue")
	if cont2 != null:
		cont2.pressed.emit()
		await process_frame
	print("[stuck2] %-22s paid=%d (want %d)  Continue=%s  transition=%s"
		% [event_id, paid, expect_pay, str(cont2 != null), str(_overlay())])
	_clear_overlay(); ev.free()
