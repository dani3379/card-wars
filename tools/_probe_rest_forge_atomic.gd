extends SceneTree
## Regression contract for Rest's forge picker: reserve the complete grid before
## hydration, keep all ornate faces/input hidden, then reveal the set atomically.

const RUN_SEED := 20260915
const DEADLINE_MS := 20000

var _fails := 0
var _cache: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[rest-forge-atomic] BEGIN")
	var rs := root.get_node_or_null("RunState")
	var card_db := root.get_node_or_null("CardDB")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	_check(DisplayServer.get_name() == "headless",
		"probe uses deterministic reduced-motion reveals")
	_check(rs != null and card_db != null and _cache != null and settings != null,
		"Rest forge dependencies are present")
	if rs == null or card_db == null or _cache == null or settings == null:
		_finish()
		return
	settings.reduce_motion = true
	settings.particles = false
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = "rest"
	_cache.clear()
	CardArtAliases.clear_runtime_caches()

	var eligible: Array[int] = []
	for i in range(rs.deck.size()):
		if not rs.has_upgrade_path(i, "plus") \
				and card_db.is_upgradeable(rs.deck[i]):
			eligible.append(i)
	var expected := eligible.size()
	var screen: Control = load("res://scenes/rest.tscn").instantiate()
	root.add_child(screen)
	screen.call("_begin_pick_card_for_upgrade")
	# Container, not GridContainer — the forge rank is an HFlowContainer now.
	var grid := _find_named(screen, "ForgeCardGrid") as Container
	_check(grid != null and grid.get_child_count() == expected,
		"Rest reserves every final forge slot synchronously")
	_check(_named_count(grid, "LoadingWrit") == expected,
		"every reserved Rest slot starts with a real card back")
	_check(_visible_card_count(grid) == 0 and _enabled_slot_buttons(grid) == 0,
		"Rest exposes no partial face or live card hit target while loading")

	var slot_counts: Array[int] = [grid.get_child_count()]
	var visible_counts: Array[int] = [_visible_card_count(grid)]
	var baseline: Array[Vector2] = []
	var max_shift := 0.0
	var stable := 0
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(grid):
		await process_frame
		slot_counts.append(grid.get_child_count())
		visible_counts.append(_visible_card_count(grid))
		var positions := _child_positions(grid)
		if baseline.is_empty() and positions.size() == expected:
			baseline = positions
		elif positions.size() == baseline.size():
			for i in positions.size():
				max_shift = maxf(max_shift, positions[i].distance_to(baseline[i]))
		var ready := _visible_card_count(grid) == expected \
			and _named_count(grid, "LoadingWrit") == 0 \
			and _direct_slot_buttons(grid) == expected \
			and _enabled_slot_buttons(grid) == expected
		if ready:
			stable += 1
			if stable >= 3:
				break
		else:
			stable = 0
	print("[rest-forge-atomic] slots=", slot_counts,
		" visible=", visible_counts, " max_shift=", max_shift)
	_check(stable >= 3, "Rest reaches a stable, complete ornate-card reveal")
	_check(slot_counts.all(func(value): return int(value) == expected),
		"Rest slot count stays fixed for every sampled frame")
	_check(visible_counts.all(func(value):
		return int(value) == 0 or int(value) == expected) \
		and visible_counts.back() == expected,
		"Rest visible faces jump only from zero to the complete set")
	_check(max_shift <= 0.01, "Rest reserved slot shift stays below 0.01 px")

	# The before/after screen is a logical pair: base + arrow + forged shell must
	# exist before either ornate face is allowed to show.
	screen.call("_select_card_for_upgrade", eligible[0])
	var compare_row := _find_named(screen, "ForgeCompareRow") as HBoxContainer
	var confirm_button := _find_named(screen, "ForgeConfirmButton") as Button
	_check(compare_row != null and compare_row.get_child_count() == 3,
		"Rest comparison reserves base, arrow, and forged positions synchronously")
	_check(_named_count(compare_row, "LoadingWrit") == 2 \
			and _visible_card_count(compare_row) == 0,
		"Rest comparison starts as a complete two-back proposition")
	_check(confirm_button != null and confirm_button.disabled \
			and confirm_button.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Rest cannot commit the forge while comparison faces are loading")
	var compare_counts: Array[int] = [compare_row.get_child_count()]
	var pair_visible: Array[int] = [_visible_card_count(compare_row)]
	var pair_baseline: Array[Vector2] = []
	var pair_shift := 0.0
	stable = 0
	deadline = Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(compare_row):
		await process_frame
		compare_counts.append(compare_row.get_child_count())
		pair_visible.append(_visible_card_count(compare_row))
		var pair_positions := _child_positions(compare_row)
		if pair_baseline.is_empty() and pair_positions.size() == 3:
			pair_baseline = pair_positions
		elif pair_positions.size() == pair_baseline.size():
			for i in pair_positions.size():
				pair_shift = maxf(pair_shift,
					pair_positions[i].distance_to(pair_baseline[i]))
		var pair_ready := _visible_card_count(compare_row) == 2 \
			and _named_count(compare_row, "LoadingWrit") == 0 \
			and not confirm_button.disabled
		stable = stable + 1 if pair_ready else 0
		if stable >= 3:
			break
	print("[rest-forge-atomic] compare_children=", compare_counts,
		" visible=", pair_visible, " max_shift=", pair_shift)
	_check(stable >= 3, "Rest comparison reaches a complete enabled reveal")
	_check(compare_counts.all(func(value): return int(value) == 3),
		"Rest comparison geometry stays complete for every sampled frame")
	_check(pair_visible.all(func(value): return int(value) == 0 or int(value) == 2) \
			and pair_visible.back() == 2,
		"Rest comparison faces jump only from zero to both cards")
	_check(pair_shift <= 0.01, "Rest comparison slot shift stays below 0.01 px")

	# Rebuild then leave immediately: a suspended hydrator must not repopulate the
	# banner screen after its generation has been cancelled.
	screen.call("_back_to_pick_card")
	var cancelled_grid := _find_named(screen, "ForgeCardGrid")
	_check(cancelled_grid != null and cancelled_grid.get_child_count() == expected,
		"replacement Rest picker also stages its full sleeve grid immediately")
	screen.call("_back_out_of_upgrade")
	for _i in 5:
		await process_frame
	_check(_find_named(screen, "ForgeCardGrid") == null \
			and _visible_card_count(screen) == 0,
		"cancelled Rest hydration cannot install stale cards into the choice screen")

	root.remove_child(screen)
	screen.free()
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music(0.0)
	await process_frame
	_finish()


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


func _direct_slot_buttons(host: Node) -> int:
	var count := 0
	for slot in host.get_children():
		for child in slot.get_children():
			if child is Button and not child.is_queued_for_deletion():
				count += 1
	return count


func _enabled_slot_buttons(host: Node) -> int:
	var count := 0
	for slot in host.get_children():
		for child in slot.get_children():
			if child is Button and not child.is_queued_for_deletion() \
					and not (child as Button).disabled:
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
	print("[rest-forge-atomic] PROBE_RESULT %s failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
