extends SceneTree
## Headless behavior regression for the campaign's visible multi-card shelves.
## Recruit and Shop must reserve their complete final rows synchronously, keep
## ornate faces/input hidden while hydration is paced, then reveal as one set.

const RUN_SEED := 20260915
const DEADLINE_MS := 30000

var _fails := 0
var _rs: Node
var _cache: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[campaign-card-groups-atomic] BEGIN")
	_rs = root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	_check(DisplayServer.get_name() == "headless", "probe uses deterministic snap reveals")
	_check(_rs != null and _cache != null and settings != null,
		"campaign card-group dependencies are present")
	if _rs == null or _cache == null or settings == null:
		_finish()
		return
	settings.reduce_motion = true
	settings.particles = false
	_rs.active_slot = -1
	_rs.start_new_run("raider", 0, RUN_SEED)
	_rs.active_slot = -1
	_cache.clear()
	CardArtAliases.clear_runtime_caches()

	await _test_recruit()
	await _test_shop()
	await _cleanup()
	_finish()


func _test_recruit() -> void:
	print("[campaign-card-groups-atomic] RECRUIT")
	_rs.current_node_type = "recruit"
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	var screen: Control = load("res://scenes/recruit.tscn").instantiate()
	root.add_child(screen)
	var group := _find_named(screen, "RecruitCardGroup") as Control
	var expected := (screen.get("_choices") as Array).size()
	_check(group != null and expected >= 2 and group.get_child_count() == expected,
		"Recruit reserves its complete final offer row before the first await")
	_check(_named_count(group, "RecruitCardSlot") == expected \
		and _named_count(group, "LoadingBack") == expected,
		"every Recruit position starts as an exact ornate-card sleeve")
	_check(_visible_card_count(group) == 0 and _all_existing_cards_ignore_input(group),
		"Recruit exposes no partial face or interactive half-state while loading")
	var sample := await _sample_group(group, expected, false)
	print("[campaign-card-groups-atomic] recruit slots=", sample.slots,
		" visible=", sample.visible, " shift=", sample.max_shift)
	_assert_sample(sample, expected, "Recruit")
	_check(_all_existing_cards_accept_input(group),
		"Recruit unlocks its ornate cards only after the complete reveal")
	await _close_screen(screen)


func _test_shop() -> void:
	print("[campaign-card-groups-atomic] SHOP")
	_rs.current_node_type = "shop"
	_rs.gold = 99999
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	seed(RUN_SEED)
	var screen: Control = load("res://scenes/shop.tscn").instantiate()
	root.add_child(screen)
	var group := _find_named(screen, "ShopCardGroup") as Control
	var expected := (screen.get("_card_stock") as Array).size()
	_check(group != null and expected == 4 and group.get_child_count() == expected,
		"Shop reserves all four final shelf slots before the first await")
	_check(_named_count(group, "ShopCardSlot") == expected \
		and _named_count(group, "LoadingBack") == expected,
		"every Shop position starts as an exact ornate-card sleeve")
	_check(_visible_card_count(group) == 0 and _all_buy_buttons_locked(group),
		"Shop exposes no partial face or purchasable half-state while loading")
	var sample := await _sample_group(group, expected, true)
	print("[campaign-card-groups-atomic] shop slots=", sample.slots,
		" visible=", sample.visible, " shift=", sample.max_shift)
	_assert_sample(sample, expected, "Shop")
	_check(_all_buy_buttons_unlocked(group),
		"Shop unlocks every affordable purchase only after the complete reveal")
	await _close_screen(screen)


func _sample_group(group: Control, expected: int, shop: bool) -> Dictionary:
	var slot_counts: Array[int] = []
	var visible_counts: Array[int] = []
	var baseline: Array[Vector2] = []
	var max_shift := 0.0
	var stable := 0
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	# Containers perform their first authoritative sort on the next process frame;
	# measure stability from that final reserved geometry, not from creation at 0,0.
	await process_frame
	while Time.get_ticks_msec() < deadline:
		var live_group := group != null and is_instance_valid(group) \
			and group.is_inside_tree() and not group.is_queued_for_deletion()
		if not live_group:
			break
		slot_counts.append(group.get_child_count())
		visible_counts.append(_visible_card_count(group))
		var positions := _child_positions(group)
		if baseline.is_empty() and positions.size() == expected:
			baseline = positions
		elif positions.size() == baseline.size():
			for i in positions.size():
				max_shift = maxf(max_shift, positions[i].distance_to(baseline[i]))
		var ready := _visible_card_count(group) == expected \
			and _named_count(group, "LoadingBack") == 0
		ready = ready and (_all_buy_buttons_unlocked(group) \
			if shop else _all_existing_cards_accept_input(group))
		if ready:
			stable += 1
			if stable >= 3:
				break
		else:
			stable = 0
		await process_frame
	_check(stable >= 3, "%s reaches a stable complete reveal" % ["Shop" if shop else "Recruit"])
	return {"slots": slot_counts, "visible": visible_counts, "max_shift": max_shift}


func _assert_sample(sample: Dictionary, expected: int, label: String) -> void:
	var fixed := not (sample.slots as Array).is_empty()
	for raw in sample.slots:
		fixed = fixed and int(raw) == expected
	var atomic := not (sample.visible as Array).is_empty() \
		and int((sample.visible as Array).back()) == expected
	for raw in sample.visible:
		atomic = atomic and (int(raw) == 0 or int(raw) == expected)
	_check(fixed, "%s keeps its final slot count for every sampled frame" % label)
	_check(atomic, "%s visible faces jump only from zero to the complete set" % label)
	_check(float(sample.max_shift) <= 0.01, "%s slot shift stays below 0.01 px" % label)


func _find_named(host: Node, wanted: String) -> Node:
	if host == null or not is_instance_valid(host):
		return null
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
		if node is Control and not node.is_queued_for_deletion() and script != null \
				and String(script.resource_path).ends_with("/Card2D.gd") \
				and (node as Control).is_visible_in_tree():
			count += 1
	return count


func _all_existing_cards_ignore_input(host: Node) -> bool:
	for node in _walk(host):
		var script: Script = node.get_script()
		if node is Control and script != null \
				and String(script.resource_path).ends_with("/Card2D.gd") \
				and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true


func _all_existing_cards_accept_input(host: Node) -> bool:
	var count := 0
	for node in _walk(host):
		var script: Script = node.get_script()
		if node is Control and script != null \
				and String(script.resource_path).ends_with("/Card2D.gd"):
			count += 1
			if (node as Control).mouse_filter != Control.MOUSE_FILTER_STOP:
				return false
	return count > 0


func _buy_buttons(host: Node) -> Array[Button]:
	var out: Array[Button] = []
	for node in _walk(host):
		if not (node is Button):
			continue
		for descendant in _walk(node):
			if descendant is Label \
					and (descendant as Label).text.begins_with("Buy"):
				out.append(node as Button)
				break
	return out


func _all_buy_buttons_locked(host: Node) -> bool:
	var buttons := _buy_buttons(host)
	return not buttons.is_empty() and buttons.all(func(button):
		return (button as Button).disabled \
			and (button as Button).mouse_filter == Control.MOUSE_FILTER_IGNORE)


func _all_buy_buttons_unlocked(host: Node) -> bool:
	var buttons := _buy_buttons(host)
	return not buttons.is_empty() and buttons.all(func(button):
		return not (button as Button).disabled \
			and (button as Button).mouse_filter == Control.MOUSE_FILTER_STOP)


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


func _close_screen(screen: Control) -> void:
	if screen != null and is_instance_valid(screen):
		root.remove_child(screen)
		screen.free()
	for _i in 4:
		await process_frame


func _cleanup() -> void:
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music(0.0)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		push_error("FAIL  %s" % label)


func _finish() -> void:
	print("[campaign-card-groups-atomic] PROBE_RESULT %s failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
