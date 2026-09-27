extends SceneTree
## Focused regression for combat card-choice presentation and pointer routing.

const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const TIMEOUT_MS := 18000

var _started := false
var _failures := 0
var _combat: Node


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var run_state: Node = root.get_node("RunState")
	var settings: Node = root.get_node("UserSettings")
	var card_db: Node = root.get_node("CardDB")
	var cache: Node = root.get_node("CardTextureCache")
	settings.set("reduce_motion", false)
	settings.set("particles", false)
	settings.set("anim_speed", 1.0)
	settings.set("tooltip_delay", 0.0)
	run_state.start_new_run("stalwart", 0, 20260927)
	run_state.set("current_encounter_id", "goblin_scouts")
	run_state.set("current_node_type", "combat")
	_combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(_combat)
	for _i in 100:
		await process_frame
	await _wait_for_idle(cache)

	await _test_known_hand_picker()
	await _test_discover(card_db, cache, false)
	settings.set("reduce_motion", true)
	await _test_discover(card_db, cache, true)

	if is_instance_valid(_combat):
		_combat.queue_free()
	for _i in 6:
		await process_frame
	print("[choice-overlay] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_known_hand_picker() -> void:
	var expected: int = (_combat.get("_hand") as Array).size()
	_combat.call("_show_recycle_modal")
	var overlay := _latest_modal()
	_check(overlay != null, "Salvage opens a modal")
	if overlay == null:
		return
	var cards := _card_nodes(overlay)
	var hitboxes := _card_hitboxes(overlay)
	_check(cards.size() == expected,
		"Salvage builds every card before its first await")
	_check(hitboxes.size() == expected,
		"every Salvage card has one full-face hitbox")
	var correct_width := true
	for card in cards:
		var parent := card.get_parent() as Control
		if parent == null or parent.custom_minimum_size.x < 224.9:
			correct_width = false
	_check(correct_width, "choice sockets cover the full 225px card face")
	var all_locked := not hitboxes.is_empty()
	for button in hitboxes:
		all_locked = all_locked and button.disabled
	_check(all_locked, "invisible hitboxes stay locked during entrance motion")

	await create_timer(0.55).timeout
	var all_ready := not hitboxes.is_empty()
	for button in hitboxes:
		all_ready = all_ready and not button.disabled
	_check(all_ready, "all card hitboxes unlock together after the tableau settles")

	if not hitboxes.is_empty():
		hitboxes[0].mouse_entered.emit()
		for _i in 3:
			await process_frame
		var detail_layer := _find_named(root, "CardDetailPopupLayer")
		_check(detail_layer != null and _has_visible_control(detail_layer),
			"hover through the selection hitbox opens the card rules inspector")
		hitboxes[0].mouse_exited.emit()

	var cancel := _button_with_text(overlay, "CANCEL")
	_check(cancel != null, "Salvage remains cancellable")
	if cancel != null:
		cancel.pressed.emit()
	await process_frame
	_check(not is_instance_valid(overlay) or overlay.is_queued_for_deletion(),
		"Salvage modal closes cleanly")


func _test_discover(card_db: Node, cache: Node, reduced: bool) -> void:
	await _wait_for_idle(cache)
	cache.clear()
	var ids := _representative_ids(card_db, 3)
	_combat.call("_build_discover_overlay", ids, "QA DISCOVER", "PICK")
	var overlay := _latest_modal()
	var mode := "Reduce Motion" if reduced else "animated"
	_check(overlay != null, "%s Discover opens a modal" % mode)
	if overlay == null:
		return
	var backs := _back_nodes(overlay)
	var buttons := _buttons_with_text(overlay, "PICK")
	_check(backs.size() == ids.size(),
		"%s Discover exposes the complete sleeve row immediately" % mode)
	_check(_card_nodes(overlay).is_empty(),
		"%s Discover leaks no ornate face before its first await" % mode)
	var all_locked := buttons.size() == ids.size()
	for button in buttons:
		all_locked = all_locked and button.disabled
	_check(all_locked, "%s Discover cannot be picked before faces settle" % mode)

	for _i in 2:
		await process_frame
	var slots := _back_slots(overlay)
	var baseline := _control_centres(slots)
	var visible_progress: Array[int] = [_visible_card_count(overlay)]
	var back_progress: Array[int] = [_visible_back_count(overlay)]
	var max_shift := 0.0
	var settled := false
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		_append_change(visible_progress, _visible_card_count(overlay))
		_append_change(back_progress, _visible_back_count(overlay))
		max_shift = maxf(max_shift,
			_max_delta(baseline, _control_centres(slots)))
		buttons = _buttons_with_text(overlay, "PICK")
		var enabled := buttons.size() == ids.size()
		for button in buttons:
			enabled = enabled and not button.disabled
		if enabled and _visible_card_count(overlay) == ids.size() \
				and _visible_back_count(overlay) == 0:
			settled = true
			break
	print("[choice-overlay] discover %s visible=%s backs=%s shift=%.3f" % [
		mode, str(visible_progress), str(back_progress), max_shift])
	_check(settled, "%s Discover reaches a complete ready state" % mode)
	_check(visible_progress == [0, ids.size()],
		"%s Discover publishes faces atomically 0 -> N" % mode)
	_check(back_progress == [ids.size(), 0],
		"%s Discover retires the complete sleeve set together" % mode)
	_check(max_shift <= 0.01,
		"%s Discover sockets never move while loading" % mode)

	if not buttons.is_empty():
		buttons[0].pressed.emit()
	await process_frame
	_check(not is_instance_valid(overlay) or overlay.is_queued_for_deletion(),
		"%s Discover closes after one exact pick" % mode)


func _latest_modal() -> ColorRect:
	var found: ColorRect = null
	for child in _combat.get_children():
		if child is ColorRect and child.z_index >= 200 and child.visible:
			found = child
	return found


func _representative_ids(card_db: Node, wanted: int) -> Array[String]:
	var out: Array[String] = []
	for id_value in card_db.CARD_POOL.keys():
		var id := String(id_value)
		var data: Dictionary = card_db.get_card_data(id)
		if data.is_empty() or not bool(data.get("draftable", true)):
			continue
		if String(data.get("rarity", "")) in ["starter", "enemy"]:
			continue
		out.append(id)
		if out.size() >= wanted:
			break
	return out


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node in _walk(host):
		var script := node.get_script() as Script
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
	return out


func _card_hitboxes(host: Node) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for node in _walk(host):
		if node is Button and node.flat and String(node.text) == "" \
				and node.has_meta("_motion_feel_target"):
			out.append(node)
	return out


func _button_with_text(host: Node, wanted: String) -> BaseButton:
	var matches := _buttons_with_text(host, wanted)
	return matches[0] if not matches.is_empty() else null


func _buttons_with_text(host: Node, wanted: String) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for node in _walk(host):
		if node is BaseButton and String(node.text).to_upper() == wanted:
			out.append(node)
	return out


func _back_nodes(host: Node) -> Array[TextureRect]:
	var out: Array[TextureRect] = []
	for node in _walk(host):
		if node is TextureRect and node.texture == CARD_BACK_TEXTURE:
			out.append(node)
	return out


func _back_slots(host: Node) -> Array[Control]:
	var out: Array[Control] = []
	for back in _back_nodes(host):
		var slot := back.get_parent() as Control
		if slot != null:
			out.append(slot)
	return out


func _effective_alpha(node: Node, boundary: Node) -> float:
	var alpha := 1.0
	var cursor := node
	while cursor != null:
		if cursor is CanvasItem:
			if not cursor.visible:
				return 0.0
			alpha *= cursor.modulate.a
		if cursor == boundary:
			break
		cursor = cursor.get_parent()
	return alpha


func _visible_card_count(host: Node) -> int:
	var count := 0
	for card in _card_nodes(host):
		if _effective_alpha(card, host) > 0.99:
			count += 1
	return count


func _visible_back_count(host: Node) -> int:
	var count := 0
	for back in _back_nodes(host):
		if _effective_alpha(back, host) > 0.01:
			count += 1
	return count


func _control_centres(nodes: Array[Control]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for node in nodes:
		if node == null or not is_instance_valid(node):
			return []
		out.append(node.global_position + node.size * 0.5)
	return out


func _max_delta(a: Array[Vector2], b: Array[Vector2]) -> float:
	if a.size() != b.size():
		return INF
	var value := 0.0
	for i in a.size():
		value = maxf(value, a[i].distance_to(b[i]))
	return value


func _append_change(values: Array[int], value: int) -> void:
	if values.is_empty() or values[-1] != value:
		values.append(value)


func _find_named(host: Node, wanted: String) -> Node:
	for node in _walk(host):
		if node.name == wanted:
			return node
	return null


func _has_visible_control(host: Node) -> bool:
	if host == null:
		return false
	for node in _walk(host):
		if node != host and node is Control and node.visible:
			return true
	return false


func _wait_for_idle(cache: Node) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while bool(cache.get("_bake_busy")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(cache.get("_bake_busy")), "card baker becomes idle")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[choice-overlay] PASS ", message)
	else:
		_failures += 1
		push_error("[choice-overlay] FAIL " + message)
