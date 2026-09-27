extends SceneTree
## Headless behavior coverage for GameTheme.show_deck_picker's staged build.
## Verifies atomic readiness, deck-index mapping, and cancellation while hidden
## card faces are still hydrating behind the complete set of reserved sleeves.

var _started := false
var _done := false
var _picker_done := false
var _picker_result := -99
var _failures := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var run_state = root.get_node_or_null("RunState")
	var theme = root.get_node_or_null("GameTheme")
	if run_state == null or theme == null:
		_fail("required autoload missing")
		_finish()
		return
	run_state.start_new_run("raider", 0, 20260903)
	run_state.active_slot = -1
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	# Pick the third visual slot and verify it returns the third deck index.
	_picker_done = false
	_picker_result = -99
	_open_picker(theme, host, false)
	var layer := await _wait_for_picker_layer(300)
	_check(layer != null, "selection picker opened")
	var picked_id := ""
	var slots := await _wait_for_ready_slots(layer, 3, 600)
	_check(slots.size() >= 3, "selection picker staged three slots")
	if slots.size() >= 3:
		picked_id = _slot_card_id(slots[2])
		var click := _slot_button(slots[2])
		_check(click != null, "third slot has click target")
		if click != null:
			click.emit_signal("pressed")
	await _wait_for_result(120)
	_check(_picker_done, "selection picker returned")
	var returned_id := ""
	if _picker_result >= 0 and _picker_result < run_state.deck.size():
		returned_id = String(run_state.deck[_picker_result])
	print("[deck-picker-flow] picked_id=%s result=%d returned_id=%s" % [
		picked_id, _picker_result, returned_id])
	_check(_picker_result >= 0 and _picker_result < run_state.deck.size() \
		and returned_id == picked_id,
		"clicked slot maps to its displayed deck card")

	# Cancel immediately after the shell appears, before the staged grid finishes.
	_picker_done = false
	_picker_result = -99
	_open_picker(theme, host, true)
	layer = await _wait_for_picker_layer(300)
	_check(layer != null, "cancel picker opened")
	var cancel := _find_button_text(layer, "CANCEL")
	_check(cancel != null, "cancel is live during population")
	if cancel != null:
		cancel.emit_signal("pressed")
	await _wait_for_result(120)
	_check(_picker_done, "cancel picker returned")
	_check(_picker_result == -1, "cancel returns -1")

	host.queue_free()
	for _i in 3:
		await process_frame
	_finish()


func _open_picker(theme, host: Node, allow_cancel: bool) -> void:
	_picker_result = await theme.show_deck_picker(
		host, "PICKER FLOW PROBE", "", allow_cancel)
	_picker_done = true


func _wait_for_picker_layer(max_frames: int) -> CanvasLayer:
	for _i in max_frames:
		var layer := _find_picker_layer()
		if layer != null:
			return layer
		await process_frame
	return null


func _wait_for_ready_slots(layer: Node, wanted: int,
		max_frames: int) -> Array[Control]:
	for _i in max_frames:
		if layer == null or not is_instance_valid(layer):
			return []
		var slots := _picker_slots(layer)
		if slots.size() >= wanted:
			var ready := true
			for slot in slots:
				var button := _slot_button(slot)
				if _slot_card_id(slot) == "" or button == null or button.disabled:
					ready = false
					break
			if ready:
				return slots
		await process_frame
	return []


func _wait_for_result(max_frames: int) -> void:
	for _i in max_frames:
		if _picker_done:
			return
		await process_frame


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _find_picker_layer() -> CanvasLayer:
	for node in _walk(root):
		if node is CanvasLayer and (node as CanvasLayer).layer == 1000:
			return node as CanvasLayer
	return null


func _picker_slots(layer: Node) -> Array[Control]:
	var slots: Array[Control] = []
	for node in _walk(layer):
		if node is Control and (node as Control).custom_minimum_size == Vector2(220, 300):
			slots.append(node as Control)
	# Grid traversal is insertion-ordered, but the DFS helper walks siblings in
	# reverse. Sort by the card's deck uid-independent left-to-right position.
	slots.sort_custom(func(a: Control, b: Control) -> bool:
		if not is_equal_approx(a.global_position.y, b.global_position.y):
			return a.global_position.y < b.global_position.y
		return a.global_position.x < b.global_position.x)
	return slots


func _slot_card_id(slot: Node) -> String:
	for child in slot.get_children():
		var script = child.get_script()
		if script != null and String(script.resource_path).ends_with("/Card2D.gd"):
			return String(child.card_data.get("id", ""))
	return ""


func _slot_button(slot: Node) -> Button:
	for child in slot.get_children():
		if child is Button:
			return child as Button
	return null


func _find_button_text(host: Node, text: String) -> Button:
	if host == null:
		return null
	for node in _walk(host):
		if node is Button and (node as Button).text == text:
			return node as Button
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[deck-picker-flow] PASS ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("[deck-picker-flow] FAIL %s" % label)


func _finish() -> void:
	print("[deck-picker-flow] RESULT failures=%d" % _failures)
	_done = true
	quit(1 if _failures > 0 else 0)
