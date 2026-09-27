extends SceneTree
## Behavioral contract for Event's deck grids and Stranger's Hand: complete
## sleeves first, hidden hydration, atomic face visibility, and gated input.

const RUN_SEED := 20260915
const DEADLINE_MS := 20000

var _fails := 0
var _cache: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[event-card-groups-atomic] BEGIN")
	var rs := root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	_check(DisplayServer.get_name() == "headless",
		"probe uses deterministic reduced-motion reveals")
	_check(rs != null and _cache != null and settings != null,
		"Event card-group dependencies are present")
	if rs == null or _cache == null or settings == null:
		_finish()
		return
	settings.reduce_motion = true
	settings.particles = false
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = "event"
	rs.current_bridge = true
	rs.events_seen.erase("the_crossing")
	_cache.clear()
	CardArtAliases.clear_runtime_caches()

	var screen: Control = load("res://scenes/event.tscn").instantiate()
	root.add_child(screen)
	await _test_deck_grid(screen, rs.deck.size())
	await _test_stranger_hand(screen)

	root.remove_child(screen)
	screen.free()
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music(0.0)
	await process_frame
	_finish()


func _test_deck_grid(screen: Control, expected: int) -> void:
	print("[event-card-groups-atomic] DECK_GRID")
	screen.call("_start_remove_mode")
	# Container, not GridContainer: the picker rank is an HFlowContainer since the
	# short-last-row fix, and `as GridContainer` on one yields NULL — which this
	# probe's own null check would then report as a real defect.
	var grid := _find_named(screen, "EventCardGrid") as Container
	_check(grid != null and grid.get_child_count() == expected,
		"Event deck picker reserves its complete final grid synchronously")
	_check(_named_count(grid, "LoadingWrit") == expected,
		"every Event deck position starts with a real card back")
	_check(_visible_card_count(grid) == 0 and _enabled_button_count(grid) == 0,
		"Event deck picker exposes no partial face or live hit target")
	var sample := await _sample_group(grid, expected, expected, "LoadingWrit")
	print("[event-card-groups-atomic] deck slots=", sample.slots,
		" visible=", sample.visible, " shift=", sample.max_shift)
	_assert_sample(sample, expected, expected, "Event deck picker")
	_check(_button_count(grid) == expected and _enabled_button_count(grid) == expected,
		"Event deck picker unlocks every bound card only after reveal")

	# A replacement generation must own the screen outright.
	screen.call("_start_remove_mode")
	var abandoned := _find_named(screen, "EventCardGrid")
	_check(abandoned != null and abandoned.get_child_count() == expected,
		"replacement Event grid also stages every sleeve immediately")
	screen.call("_clear_ui")
	for _i in 5:
		await process_frame
	_check(_find_named(screen, "EventCardGrid") == null \
			and _visible_card_count(screen) == 0,
		"cancelled Event grid cannot append stale cards")


func _test_stranger_hand(screen: Control) -> void:
	print("[event-card-groups-atomic] STRANGER_HAND")
	screen.call("_start_stranger_hand_mode")
	var group := _find_named(screen, "StrangerHandGroup") as HBoxContainer
	var expected := 3
	_check(group != null and group.get_child_count() == expected,
		"Stranger's Hand reserves all three final columns synchronously")
	_check(_named_count(group, "WetBack") == expected \
			and _visible_card_count(group) == 0,
		"Stranger's Hand presents one complete face-down offer before hydration")
	_check(_button_count(group) == expected and _enabled_button_count(group) == 0,
		"all Stranger's Hand prices stay unclickable while faces load")
	var sample := await _sample_group(group, expected, expected, "WetBack")
	print("[event-card-groups-atomic] stranger slots=", sample.slots,
		" visible=", sample.visible, " shift=", sample.max_shift)
	_assert_sample(sample, expected, expected, "Stranger's Hand")
	_check(_button_count(group) == expected and _enabled_button_count(group) == expected,
		"Stranger's Hand unlocks all three choices on the shared reveal beat")

	# Cancel before the staging frame resumes; no late face may survive the gen bump.
	screen.call("_start_stranger_hand_mode")
	_check(_named_count(screen, "WetBack") == expected \
			and _visible_card_count(screen) == 0,
		"replacement Stranger's Hand is fully sleeved before its first await")
	screen.call("_clear_ui")
	for _i in 5:
		await process_frame
	_check(_named_count(screen, "WetBack") == 0 and _visible_card_count(screen) == 0,
		"cancelled Stranger's Hand hydration cannot install stale faces")


func _sample_group(group: Control, expected_slots: int, expected_faces: int,
		back_name: String) -> Dictionary:
	var slot_counts: Array[int] = [group.get_child_count()]
	var visible_counts: Array[int] = [_visible_card_count(group)]
	var baseline: Array[Vector2] = []
	var max_shift := 0.0
	var stable := 0
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(group):
		await process_frame
		slot_counts.append(group.get_child_count())
		visible_counts.append(_visible_card_count(group))
		var positions := _child_positions(group)
		if baseline.is_empty() and positions.size() == expected_slots:
			baseline = positions
		elif positions.size() == baseline.size():
			for i in positions.size():
				max_shift = maxf(max_shift, positions[i].distance_to(baseline[i]))
		var ready := _visible_card_count(group) == expected_faces \
			and _named_count(group, back_name) == 0 \
			and _button_count(group) == expected_faces \
			and _enabled_button_count(group) == expected_faces
		stable = stable + 1 if ready else 0
		if stable >= 3:
			break
	return {
		"slots": slot_counts,
		"visible": visible_counts,
		"max_shift": max_shift,
		"stable": stable,
	}


func _assert_sample(sample: Dictionary, expected_slots: int,
		expected_faces: int, label: String) -> void:
	_check(int(sample.stable) >= 3, "%s reaches a stable complete reveal" % label)
	_check((sample.slots as Array).all(func(value): return int(value) == expected_slots),
		"%s keeps its final slot count for every sampled frame" % label)
	_check((sample.visible as Array).all(func(value):
		return int(value) == 0 or int(value) == expected_faces) \
		and int((sample.visible as Array).back()) == expected_faces,
		"%s visible faces jump only from zero to the complete set" % label)
	_check(float(sample.max_shift) <= 0.01,
		"%s slot shift stays below 0.01 px" % label)


func _find_named(host: Node, wanted: String) -> Node:
	for node in _walk(host):
		if node.name == wanted and not node.is_queued_for_deletion():
			return node
	return null


func _named_count(host: Node, wanted: String) -> int:
	var count := 0
	for node in _walk(host):
		if node.name == wanted and not node.is_queued_for_deletion():
			count += 1
	return count


func _visible_card_count(host: Node) -> int:
	var count := 0
	for node in _walk(host):
		var script: Script = node.get_script()
		if node is Control and script != null \
				and String(script.resource_path).ends_with("/Card2D.gd") \
				and (node as Control).is_visible_in_tree():
			count += 1
	return count


func _button_count(host: Node) -> int:
	var count := 0
	for node in _walk(host):
		if node is Button and not node.is_queued_for_deletion():
			count += 1
	return count


func _enabled_button_count(host: Node) -> int:
	var count := 0
	for node in _walk(host):
		if node is Button and not node.is_queued_for_deletion() \
				and not (node as Button).disabled:
			count += 1
	return count


func _child_positions(host: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for child in host.get_children():
		if child is Control and not child.is_queued_for_deletion():
			out.append((child as Control).global_position)
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


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		push_error("FAIL  %s" % label)


func _finish() -> void:
	print("[event-card-groups-atomic] PROBE_RESULT %s failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
