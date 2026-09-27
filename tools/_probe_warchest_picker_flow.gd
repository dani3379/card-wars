extends SceneTree
## Headless behavior coverage for MainMenu's atomic War Chest card pickers.
##
## Rendering is intentionally paced one hidden Card2D at a time, but presentation
## is atomic: every final-size shell and card back exists before the first await,
## no face is exposed early, the whole group reveals on one beat, and input stays
## locked until that reveal is complete.

const MAX_WAIT_FRAMES := 300
const CARD_SCENE_PATH := "/Card2D.gd"
const SLOT_SIZE := Vector2(225, 300)
const POSITION_EPSILON := 0.5

var _started := false
var _done := false
var _failures := 0
var _callback_fired := false
var _callback_value: Variant = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[warchest-picker-flow] CHECK_ONLY_OK")
		_finish()
		return
	var run_state: Node = root.get_node_or_null("RunState")
	var settings: Node = root.get_node_or_null("UserSettings")
	if run_state == null or settings == null:
		_fail("required autoloads are present")
		_finish()
		return
	# Headless is a snap path by design. This verifies that Reduce Motion reaches
	# the same atomic end state without manufacturing intermediate face frames.
	settings.set("reduce_motion", true)
	run_state.call("start_new_run", "raider", 0, 20260910)
	run_state.set("active_slot", -1)

	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	for _i in 3:
		await process_frame

	await _test_live_index_picker(menu, run_state)
	await _test_offer_id_picker(menu)
	await _test_blank_cancel(menu)
	await _test_replacement(menu, run_state)

	for _i in 2:
		await process_frame
	menu.queue_free()
	for _i in 3:
		await process_frame
	_finish()


func _test_live_index_picker(menu: Node, run_state: Node) -> void:
	_reset_callback()
	# Every selected position has a unique card id, so its face independently
	# proves that the callback retained the shell's original deck-index mapping.
	var indices: Array = [6, 2, 9, 4, 7, 5]
	menu.call("_show_blessing_card_picker", "FLOW PROBE — LIVE", indices,
		Callable(self, "_record_pick"))
	_check_initial_shells(menu, indices.size(), "live-index")
	var observed := await _observe_atomic_reveal(menu, indices.size())
	_check_atomic_observation(observed, indices.size(), "live-index")

	var slots: Array[Dictionary] = _coordinated_slots(menu)
	_check(slots.size() == indices.size(),
		"live-index picker retains the complete coordinated group")
	if slots.is_empty():
		return
	var chosen: Dictionary = slots.back()
	var card: Node = chosen["card"]
	var button: Button = chosen["button"]
	var shown_id := String(card.get("card_data").get("id", ""))
	var expected_index := _unique_deck_index_for_id(run_state, indices, shown_id)
	_check(expected_index >= 0,
		"live-index revealed face identifies one supplied deck index")
	_check(not button.disabled,
		"live-index selection is attempted only after input unlocks")
	if not button.disabled:
		button.emit_signal("pressed")
	await _wait_for_callback(20)
	_check(_callback_fired, "live-index click invokes its callback")
	_check(typeof(_callback_value) == TYPE_INT and int(_callback_value) == expected_index,
		"live-index click returns the value mapped to the revealed face")


func _test_offer_id_picker(menu: Node) -> void:
	_reset_callback()
	var ids := _offer_ids(6, {})
	_check(ids.size() == 6, "offer fixture found six distinct card ids")
	if ids.size() < 2:
		return
	menu.call("_show_blessing_offer_picker", "FLOW PROBE — OFFER", ids,
		Callable(self, "_record_pick"))
	_check_initial_shells(menu, ids.size(), "offer-id")
	var observed := await _observe_atomic_reveal(menu, ids.size())
	_check_atomic_observation(observed, ids.size(), "offer-id")

	var slots: Array[Dictionary] = _coordinated_slots(menu)
	if slots.is_empty():
		_fail("offer-id picker retains a selectable coordinated group")
		return
	var chosen: Dictionary = slots.back()
	var card: Node = chosen["card"]
	var button: Button = chosen["button"]
	var shown_id := String(card.get("card_data").get("id", ""))
	_check(not button.disabled,
		"offer-id selection is attempted only after input unlocks")
	if not button.disabled:
		button.emit_signal("pressed")
	await _wait_for_callback(20)
	_check(_callback_fired, "offer-id click invokes its callback")
	_check(typeof(_callback_value) == TYPE_STRING and String(_callback_value) == shown_id,
		"offer-id click returns the id mapped to the revealed face")


func _test_blank_cancel(menu: Node) -> void:
	_reset_callback()
	var ids := _offer_ids(7, {})
	menu.call("_show_blessing_offer_picker", "FLOW PROBE — CANCEL", ids,
		Callable(self, "_record_pick"))
	_check_initial_shells(menu, ids.size(), "cancellation")
	var partial := await _wait_for_partial_hidden_hydration(menu, ids.size())
	_check(partial, "cancellation reaches paced hidden hydration")
	var old_group: Node = _picker_group(menu)
	var old_ref: WeakRef = weakref(old_group) if old_group != null else null
	menu.call("_clear_for_picker")
	for _i in 8:
		await process_frame
	_check(_coordinated_slots(menu).is_empty(),
		"generation cancellation leaves no live coordinated slots")
	_check(not _callback_fired,
		"generation cancellation does not invent a card selection")
	_check(old_ref == null or old_ref.get_ref() == null,
		"generation cancellation retires the old picker group")


func _test_replacement(menu: Node, run_state: Node) -> void:
	_reset_callback()
	var old_indices: Array = [6, 2, 9, 4, 7, 5]
	var old_ids: Dictionary = {}
	var deck: Array = run_state.get("deck")
	for deck_index_v in old_indices:
		old_ids[String(deck[int(deck_index_v)])] = true
	menu.call("_show_blessing_card_picker", "FLOW PROBE — OLD", old_indices,
		Callable(self, "_record_pick"))
	_check_initial_shells(menu, old_indices.size(), "replacement-old")
	_check(await _wait_for_partial_hidden_hydration(menu, old_indices.size()),
		"replacement begins while the old picker is hydrating invisibly")
	var old_group: Node = _picker_group(menu)
	var old_ref: WeakRef = weakref(old_group) if old_group != null else null

	var replacement_ids := _offer_ids(5, old_ids)
	_check(replacement_ids.size() == 5,
		"replacement fixture is disjoint from the old picker")
	menu.call("_show_blessing_offer_picker", "FLOW PROBE — NEW", replacement_ids,
		Callable(self, "_record_pick"))
	_check_initial_shells(menu, replacement_ids.size(), "replacement-new")
	var observed := await _observe_atomic_reveal(menu, replacement_ids.size())
	_check_atomic_observation(observed, replacement_ids.size(), "replacement-new")

	var visible_ids: Dictionary = {}
	for slot in _coordinated_slots(menu):
		var card: Node = slot["card"]
		if card != null and bool(card.get("visible")):
			visible_ids[String(card.get("card_data").get("id", ""))] = true
	var only_replacement := visible_ids.size() == replacement_ids.size()
	for visible_id in visible_ids:
		if not replacement_ids.has(visible_id):
			only_replacement = false
	_check(only_replacement,
		"replacement reveal contains only the new offer's cards")
	_check(old_ref == null or old_ref.get_ref() == null,
		"replacement frees the superseded picker group")
	_check(not _callback_fired,
		"replacing an unpicked group does not invoke its callback")


func _check_initial_shells(host: Node, total: int, label: String) -> void:
	var group := _picker_group(host)
	var slots := _coordinated_slots(host)
	_check(group != null and group.has_meta("coordinated_card_group"),
		"%s picker marks one coordinated card group" % label)
	_check(slots.size() == total,
		"%s picker reserves all %d card slots before its first yield" % [label, total])
	var valid := slots.size() == total
	for slot in slots:
		var wrapper: Control = slot["wrapper"]
		var button: Button = slot["button"]
		var card: Node = slot["card"]
		valid = valid and wrapper.has_meta("coordinated_card_slot") \
			and wrapper.custom_minimum_size == SLOT_SIZE \
			and slot["back"] != null and button != null and button.disabled \
			and (card == null or not bool(card.get("visible")))
	_check(valid,
		"%s shells start full-size, face-down, and input-locked" % label)


func _observe_atomic_reveal(host: Node, total: int) -> Dictionary:
	var hydration: Array[int] = []
	var visible: Array[int] = []
	var enabled: Array[int] = []
	var unit_hydration := true
	var hidden_hydration := true
	var input_gated := true
	var backs_cover_wait := true
	var slot_count_stable := true
	var centers_stable := true
	var centers_locked := false
	var center_candidate: Dictionary = {}
	var center_streak := 0
	var baseline_centers: Dictionary = {}
	var complete := false

	for _frame in MAX_WAIT_FRAMES:
		var slots := _coordinated_slots(host)
		slot_count_stable = slot_count_stable and slots.size() == total
		var hydrated_count := _hydrated_count(slots)
		var visible_count := _visible_count(slots)
		var enabled_count := _enabled_count(slots)
		if hydration.is_empty() or hydration.back() != hydrated_count:
			if not hydration.is_empty():
				var delta: int = hydrated_count - int(hydration.back())
				unit_hydration = unit_hydration and delta >= 0 and delta <= 1
			hydration.append(hydrated_count)
		if visible.is_empty() or visible.back() != visible_count:
			visible.append(visible_count)
		if enabled.is_empty() or enabled.back() != enabled_count:
			enabled.append(enabled_count)

		if hydrated_count > 0 and hydrated_count < total:
			hidden_hydration = hidden_hydration and visible_count == 0
		if visible_count < total:
			input_gated = input_gated and enabled_count == 0
			backs_cover_wait = backs_cover_wait and _all_backs_present(slots)

		var centers := _slot_centers(slots)
		if centers.size() == total:
			if not centers_locked:
				if not center_candidate.is_empty() \
						and _centers_match(center_candidate, centers):
					center_streak += 1
				else:
					center_candidate = centers
					center_streak = 1
				if center_streak >= 2:
					baseline_centers = centers
					centers_locked = true
			elif not _centers_match(baseline_centers, centers):
				centers_stable = false

		if hydrated_count == total and visible_count == total \
				and enabled_count == total:
			complete = true
			break
		await process_frame

	return {
		"complete": complete,
		"hydration": hydration,
		"visible": visible,
		"enabled": enabled,
		"unit_hydration": unit_hydration,
		"hidden_hydration": hidden_hydration,
		"input_gated": input_gated,
		"backs_cover_wait": backs_cover_wait,
		"slot_count_stable": slot_count_stable,
		"centers_locked": centers_locked,
		"centers_stable": centers_stable,
	}


func _check_atomic_observation(observed: Dictionary, total: int,
		label: String) -> void:
	var hydration: Array = observed["hydration"]
	var visible: Array = observed["visible"]
	_check(bool(observed["complete"]),
		"%s picker completes its coordinated reveal" % label)
	_check(_has_partial_count(hydration, total) and bool(observed["unit_hydration"]),
		"%s Card2D hydration remains paced behind the backs" % label)
	_check(bool(observed["hidden_hydration"]),
		"%s never exposes a face while the group is incomplete" % label)
	_check(visible == [0, total],
		"%s visible-face progression is exactly [0, %d], got %s" % [
			label, total, str(visible)])
	_check(bool(observed["input_gated"]),
		"%s keeps every button disabled until the complete reveal" % label)
	_check(bool(observed["backs_cover_wait"]),
		"%s keeps a card back over every reserved slot while waiting" % label)
	_check(bool(observed["slot_count_stable"]),
		"%s never adds or removes layout slots during hydration" % label)
	_check(bool(observed["centers_locked"]) and bool(observed["centers_stable"]),
		"%s slot centers stay fixed after the initial Container sort" % label)


func _wait_for_partial_hidden_hydration(host: Node, total: int) -> bool:
	for _i in MAX_WAIT_FRAMES:
		var slots := _coordinated_slots(host)
		var hydrated := _hydrated_count(slots)
		if hydrated > 0 and hydrated < total:
			return _visible_count(slots) == 0 and _enabled_count(slots) == 0 \
				and _all_backs_present(slots)
		await process_frame
	return false


func _picker_group(host: Node) -> Control:
	for node in _walk(host):
		if node is Control and node.has_meta("coordinated_card_group") \
				and not _has_queued_ancestor(node, host):
			return node as Control
	return null


func _coordinated_slots(host: Node) -> Array[Dictionary]:
	var group := _picker_group(host)
	var out: Array[Dictionary] = []
	if group == null:
		return out
	for node in group.get_children():
		if not node is Control or not node.has_meta("coordinated_card_slot"):
			continue
		var wrapper := node as Control
		var card: Node = null
		var button: Button = null
		var back: Control = null
		for child in wrapper.get_children():
			var script: Script = child.get_script()
			if script != null and String(script.resource_path).ends_with(CARD_SCENE_PATH):
				card = child
			elif child is Button and child.name == "CardPickButton":
				button = child as Button
			elif child is Control and child.name == "LoadingBack":
				back = child as Control
		out.append({
			"wrapper": wrapper,
			"card": card,
			"button": button,
			"back": back,
		})
	return out


func _has_queued_ancestor(node: Node, host: Node) -> bool:
	var cursor: Node = node
	while cursor != null and cursor != host:
		if cursor.is_queued_for_deletion():
			return true
		cursor = cursor.get_parent()
	return false


func _hydrated_count(slots: Array[Dictionary]) -> int:
	var count := 0
	for slot in slots:
		if slot["card"] != null:
			count += 1
	return count


func _visible_count(slots: Array[Dictionary]) -> int:
	var count := 0
	for slot in slots:
		var card: Node = slot["card"]
		if card != null and bool(card.get("visible")):
			count += 1
	return count


func _enabled_count(slots: Array[Dictionary]) -> int:
	var count := 0
	for slot in slots:
		var button: Button = slot["button"]
		if button != null and not button.disabled:
			count += 1
	return count


func _all_backs_present(slots: Array[Dictionary]) -> bool:
	if slots.is_empty():
		return false
	for slot in slots:
		var back: Control = slot["back"]
		if back == null or not back.visible:
			return false
	return true


func _slot_centers(slots: Array[Dictionary]) -> Dictionary:
	var centers: Dictionary = {}
	for slot in slots:
		var wrapper: Control = slot["wrapper"]
		centers[wrapper.get_instance_id()] = wrapper.get_global_rect().get_center()
	return centers


func _centers_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or (a[key] as Vector2).distance_to(b[key] as Vector2) \
				> POSITION_EPSILON:
			return false
	return true


func _wait_for_callback(max_frames: int) -> void:
	for _i in max_frames:
		if _callback_fired:
			return
		await process_frame


func _unique_deck_index_for_id(run_state: Node, indices: Array,
		card_id: String) -> int:
	var found := -1
	var deck: Array = run_state.get("deck")
	for deck_index_v in indices:
		var deck_index := int(deck_index_v)
		if String(deck[deck_index]) != card_id:
			continue
		if found >= 0:
			return -1
		found = deck_index
	return found


func _offer_ids(wanted: int, excluded: Dictionary) -> Array:
	var out: Array = []
	var card_db: Node = root.get_node("CardDB")
	for rarity in ["uncommon", "rare", "common"]:
		var ids: Array = card_db.call("cards_of_rarity", rarity)
		for card_id_v in ids:
			var card_id := String(card_id_v)
			if excluded.has(card_id) or out.has(card_id):
				continue
			out.append(card_id)
			if out.size() >= wanted:
				return out
	return out


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _has_partial_count(progression: Array, total: int) -> bool:
	for count_v in progression:
		var count := int(count_v)
		if count > 0 and count < total:
			return true
	return false


func _record_pick(value: Variant) -> void:
	_callback_fired = true
	_callback_value = value


func _reset_callback() -> void:
	_callback_fired = false
	_callback_value = null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[warchest-picker-flow] PASS ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("[warchest-picker-flow] FAIL %s" % label)


func _finish() -> void:
	print("[warchest-picker-flow] RESULT failures=%d" % _failures)
	_done = true
	quit(1 if _failures > 0 else 0)
