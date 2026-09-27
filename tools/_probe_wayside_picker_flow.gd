extends SceneTree
## Headless lifecycle regression for Wayside's fixed-slot card grids. Verifies
## hidden paced hydration, atomic visible reveal, stable geometry, selection,
## early Scales Cancel, and donor -> receiver replacement.

const RUN_SEED := 20260910
const CASE_TIMEOUT_MS := 6000
const HARD_TIMEOUT_MS := 26000
const EXTRA_CARD_IDS: Array[String] = [
	"lookout", "thornguard", "raven", "battle_drummer", "hound",
	"warding_stone", "basilisk", "palisade", "mourner",
]

var _started := false
var _done := false
var _hard_deadline_ms := 0
var _failures := 0
var _scene: Node = null
var _run_state: Node = null
var _cache: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_hard_deadline_ms = Time.get_ticks_msec() + HARD_TIMEOUT_MS
		_run()
	elif not _done and Time.get_ticks_msec() >= _hard_deadline_ms:
		_fail("global watchdog expired")
		_finish()
	return false


func _run() -> void:
	_run_state = root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	if _run_state == null or _cache == null or settings == null:
		_fail("required autoloads are present")
		_finish()
		return
	Engine.max_fps = 240
	settings.reduce_motion = true
	settings.particles = false
	await _test_drill_staging_and_click()
	await _test_scales_early_cancel()
	await _test_banner_replacement()
	_finish()


func _test_drill_staging_and_click() -> void:
	print("[wayside-picker-flow] CASE drill_atomic_reveal_click")
	_prepare_run("drill_yard")
	_scene = _open_wayside()
	if _scene == null:
		_fail("drill Wayside scene opens")
		return
	var eligible: Array = _scene.call("_drill_eligible")
	var expected := eligible.size()
	_check(expected >= 4, "drill fixture has a deck-sized slate")
	var grid := _first_grid(_scene)
	_check(grid != null, "drill grid exists before hydration")
	_check(grid != null and grid.get_child_count() == expected,
		"all drill card footprints are reserved before hydration")
	# The first headless process tick is allowed to perform the Container's initial
	# sort. Measure stability only after two calm layout ticks—the player never sees
	# the pre-sort zero positions, and later hydration is the regression in scope.
	var baseline := _grid_positions(grid)
	var layout_stable := 0
	for _i in 12:
		await process_frame
		var current := _grid_positions(grid)
		var layout_delta := 0.0
		if current.size() == baseline.size():
			for i in current.size():
				layout_delta = maxf(layout_delta,
					current[i].distance_to(baseline[i]))
		else:
			layout_delta = INF
		layout_stable = layout_stable + 1 if layout_delta <= 0.01 else 0
		baseline = current
		if layout_stable >= 2:
			break
	var node_progression: Array[int] = [_card_nodes(_scene).size()]
	var visible_progression: Array[int] = [_visible_card_count(_scene)]
	var max_shift := 0.0
	var saw_disabled_partial := false
	var deadline := _case_deadline()
	while Time.get_ticks_msec() < deadline:
		var cards := _card_nodes(_scene)
		var visible_count := _visible_card_count(_scene)
		if cards.size() != node_progression[-1]:
			node_progression.append(cards.size())
		if visible_count != visible_progression[-1]:
			visible_progression.append(visible_count)
		var positions := _grid_positions(grid)
		if positions.size() == baseline.size():
			for i in positions.size():
				max_shift = maxf(max_shift, positions[i].distance_to(baseline[i]))
		var buttons_ready := 0
		var buttons_disabled := 0
		for card in cards:
			var button := _card_click_button(card)
			if button != null:
				if button.disabled:
					buttons_disabled += 1
				else:
					buttons_ready += 1
		if cards.size() > 0 and cards.size() < expected \
				and buttons_disabled == cards.size():
			saw_disabled_partial = true
		if cards.size() == expected and visible_count == expected \
				and buttons_ready == expected:
			break
		await process_frame
	print("[wayside-picker-flow] drill nodes=%s visible=%s slots=%d shift=%.3f" % [
		str(node_progression), str(visible_progression),
		grid.get_child_count() if is_instance_valid(grid) else -1, max_shift])
	_check(node_progression.size() >= 3,
		"hidden hydration remains paced across frames")
	_check(visible_progression == [0, expected],
		"drill faces reveal atomically rather than one by one")
	_check(max_shift <= 0.01, "drill card slots never move during hydration")
	_check(saw_disabled_partial,
		"partially hydrated drill cards remain non-interactive")

	var cards := _card_nodes(_scene)
	var picked_card: Node = cards[0] if not cards.is_empty() else null
	var click := _card_click_button(picked_card)
	var old_grid := _grid_ancestor(picked_card)
	var old_grid_ref: WeakRef = weakref(old_grid) if old_grid != null else null
	var old_count := old_grid.get_child_count() if old_grid != null else -1
	var picked_data: Dictionary = picked_card.get("card_data") \
		if picked_card != null else {}
	var picked_id := String(picked_data.get("id", ""))
	_check(click != null and not click.disabled,
		"drill choice unlocks after the complete reveal")
	_check(old_grid != null, "revealed drill card belongs to the active grid")
	if click != null and not click.disabled:
		click.emit_signal("pressed")
	_check(bool(_scene.get("_grid_pick_taken")),
		"authentic drill click closes the pick latch synchronously")

	deadline = _case_deadline()
	while Time.get_ticks_msec() < deadline:
		if int(_scene.get("_drill_index")) >= 0 \
				and _card_nodes(_scene).size() == 1 \
				and not bool(_scene.get("_grid_pick_pending")):
			break
		await process_frame
	var old_live: Container = old_grid_ref.get_ref() as Container \
		if old_grid_ref != null else null
	_check(old_count == expected, "selected grid kept its complete footprint")
	_check(old_live == null or not is_instance_valid(old_live) \
		or old_live.is_queued_for_deletion(), "selected grid is retired cleanly")
	var picked_index := int(_scene.get("_drill_index"))
	_check(picked_index >= 0, "drill click invokes the bound card callback")
	var selected_data: Dictionary = _run_state.get_upgraded_card_data(picked_index) \
		if picked_index >= 0 else {}
	_check(String(selected_data.get("id", "")) == picked_id,
		"authentic click maps to the displayed drill card")
	_check(_card_nodes(_scene).size() == 1,
		"drill picker is replaced by exactly one push-screen card")
	var drill_entry: Dictionary = _run_state.get_upgrade_entry(picked_index, "drill") \
		if picked_index >= 0 else {}
	_check(int(drill_entry.get("stacks", 0)) == 1,
		"atomic reveal cannot duplicate the drill mutation")
	await create_timer(0.38).timeout
	await _close_scene()


func _test_scales_early_cancel() -> void:
	print("[wayside-picker-flow] CASE scales_early_cancel")
	_prepare_run("muster_scale")
	_scene = _open_wayside()
	if _scene == null:
		_fail("scales Wayside scene opens")
		return
	var generation_before := int(_scene.get("_ui_build_generation"))
	_scene.call("_build_scales_sell")
	var sell_generation := int(_scene.get("_ui_build_generation"))
	var cancel := _find_button(_scene, "Cancel")
	var sell_cards_at_cancel := _card_nodes(_scene).size()
	var old_grid := _first_grid(_scene)
	_check(old_grid != null and old_grid.get_child_count() == _run_state.deck.size(),
		"scales reserves its complete deck footprint before hydration")
	var old_grid_ref: WeakRef = weakref(old_grid) if old_grid != null else null
	print("[wayside-picker-flow] scales shell generation=%d cards=%d cancel=%s" % [
		sell_generation, sell_cards_at_cancel, str(cancel != null)])
	_check(sell_generation > generation_before, "scales sell shell starts a new producer generation")
	_check(cancel != null, "scales Cancel is present before hydration completes")
	_check(sell_cards_at_cancel < _run_state.deck.size(),
		"scales Cancel is available on an incomplete card slate")
	if cancel != null:
		cancel.emit_signal("pressed")
	var generation_after_cancel := int(_scene.get("_ui_build_generation"))
	var max_cards_after_cleanup := 0
	var cleanup_seen := false
	var stable_zero := 0
	var deadline := _case_deadline()
	while Time.get_ticks_msec() < deadline and stable_zero < 12:
		await process_frame
		var count := _card_nodes(_scene).size()
		if cleanup_seen:
			max_cards_after_cleanup = maxi(max_cards_after_cleanup, count)
		if count == 0:
			cleanup_seen = true
			stable_zero += 1
		else:
			stable_zero = 0
	var old_live: Container = old_grid_ref.get_ref() as Container \
		if old_grid_ref != null else null
	print("[wayside-picker-flow] scales cancel generation=%d->%d stable_zero=%d max_after_cleanup=%d old_grid_live=%s" % [
		sell_generation, generation_after_cancel, stable_zero,
		max_cards_after_cleanup, str(old_live != null and is_instance_valid(old_live))])
	_check(generation_after_cancel > sell_generation,
		"scales Cancel invalidates the sell producer generation")
	_check(stable_zero >= 12, "scales Cancel removes the partial card slate")
	_check(max_cards_after_cleanup == 0,
		"scales producer appends no stale cards after cleanup")
	_check(old_live == null or not is_instance_valid(old_live) \
		or old_live.is_queued_for_deletion(),
		"scales producer retains no live old grid")
	await _close_scene()


func _test_banner_replacement() -> void:
	print("[wayside-picker-flow] CASE banner_donor_receiver_replacement")
	_prepare_run("standard_bearer")
	_scene = _open_wayside()
	if _scene == null:
		_fail("banner Wayside scene opens")
		return
	var lookout_index: int = _run_state.deck.find("lookout")
	_check(lookout_index >= 0, "banner fixture contains the deterministic Lookout donor")
	if lookout_index < 0:
		await _close_scene()
		return
	var donor_data: Dictionary = _run_state.get_upgraded_card_data(lookout_index)
	var transferable: Array = _scene.call("_transferable_of", donor_data)
	_check(transferable.size() == 1 and String(transferable[0]) == "swift",
		"Lookout takes the direct single-keyword donor path")
	var receivers: Array = _scene.call("_banner_receivers", lookout_index, "swift")
	var expected_ids: Array[String] = []
	for receiver_value in receivers:
		var receiver_data: Dictionary = _run_state.get_upgraded_card_data(int(receiver_value))
		expected_ids.append(String(receiver_data.get("id", "")))
	expected_ids.sort()
	_check(not expected_ids.is_empty(), "banner fixture has valid Swift receivers")

	var donor_generation := int(_scene.get("_ui_build_generation"))
	var donor_grid := _first_grid(_scene)
	var donor_grid_ref: WeakRef = weakref(donor_grid) if donor_grid != null else null
	var donor_partial := _card_nodes(_scene).size()
	_scene.call("_on_banner_donor_pick", lookout_index)
	if String(_scene.get("_banner_kw")) == "":
		_scene.call("_on_banner_kw_pick", "swift")
	var receiver_generation := int(_scene.get("_ui_build_generation"))
	print("[wayside-picker-flow] banner replace generation=%d->%d donor_partial=%d receivers=%d" % [
		donor_generation, receiver_generation, donor_partial, receivers.size()])
	_check(receiver_generation > donor_generation,
		"banner receiver shell invalidates the donor producer")
	_check(donor_grid != null, "banner replacement interrupts a real donor grid")

	var deadline := _case_deadline()
	var stable := 0
	while Time.get_ticks_msec() < deadline and stable < 10:
		await process_frame
		if _visible_card_count(_scene) == receivers.size() and _all_card_buttons_ready(_scene):
			stable += 1
		else:
			stable = 0
	var displayed_ids := _card_ids(_scene)
	displayed_ids.sort()
	var donor_live: Container = donor_grid_ref.get_ref() as Container \
		if donor_grid_ref != null else null
	print("[wayside-picker-flow] banner expected=%s displayed=%s stable=%d old_grid_live=%s" % [
		str(expected_ids), str(displayed_ids), stable,
		str(donor_live != null and is_instance_valid(donor_live))])
	_check(stable >= 10,
		"banner receivers reveal as one full, interactive slate")
	_check(_first_grid(_scene).get_child_count() == receivers.size(), "receiver footprints are complete")
	_check(displayed_ids == expected_ids,
		"banner replacement contains receivers only, with no stale donor append")
	_check(donor_live == null or not is_instance_valid(donor_live) \
		or donor_live.is_queued_for_deletion(),
		"banner old producer grid is freed or queued")
	_check(int(_scene.get("_ui_build_generation")) == receiver_generation,
		"abandoned banner donor lambda cannot rebuild or invalidate the receiver")
	# Let any joined threaded art request resume after the old grid is gone. A
	# freed-node/lambda bug reports an engine SCRIPT ERROR during this window.
	await create_timer(0.30).timeout
	var after_drain_ids := _card_ids(_scene)
	after_drain_ids.sort()
	_check(after_drain_ids == displayed_ids,
		"banner slate stays unchanged after abandoned producer continuations drain")
	await _close_scene()


func _prepare_run(verb: String) -> void:
	_run_state.start_new_run("raider", 0, RUN_SEED)
	_run_state.active_slot = -1
	for card_id: String in EXTRA_CARD_IDS:
		_run_state.add_card(card_id)
	_run_state.current_node_type = "wayside"
	_run_state.current_wayside_id = verb
	_cache.clear()


func _open_wayside() -> Node:
	var packed := load("res://scenes/wayside.tscn") as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	return scene


func _close_scene() -> void:
	if current_scene == _scene:
		current_scene = null
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	for _i in 5:
		await process_frame
	_scene = null


func _case_deadline() -> int:
	return mini(Time.get_ticks_msec() + CASE_TIMEOUT_MS, _hard_deadline_ms)


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in _walk(host):
		var script := node.get_script() as Script
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
	return out


func _visible_card_count(host: Node) -> int:
	var count := 0
	for card in _card_nodes(host):
		if card.visible and card.modulate.a > 0.99:
			count += 1
	return count


func _all_card_buttons_ready(host: Node) -> bool:
	var cards := _card_nodes(host)
	if cards.is_empty():
		return false
	for card in cards:
		var button := _card_click_button(card)
		if button == null or button.disabled:
			return false
	return true


func _grid_positions(grid: Container) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if grid == null or not is_instance_valid(grid):
		return out
	for child in grid.get_children():
		if child is Control:
			out.append((child as Control).global_position)
	return out


func _card_ids(host: Node) -> Array[String]:
	var ids: Array[String] = []
	for card: Node in _card_nodes(host):
		var data: Dictionary = card.get("card_data")
		ids.append(String(data.get("id", "")))
	return ids


## The picker rank is an HFlowContainer since the short-last-row fix, so match
## either shape — but NOT plain Container, which would return the first VBox
## wrapper on the screen and quietly measure the wrong node.
func _first_grid(host: Node) -> Container:
	for node: Node in _walk(host):
		if node is GridContainer or node is FlowContainer:
			return node as Container
	return null


func _grid_ancestor(node: Node) -> Container:
	var cursor := node
	while cursor != null:
		if cursor is GridContainer or cursor is FlowContainer:
			return cursor as Container
		cursor = cursor.get_parent()
	return null


func _card_click_button(card: Node) -> Button:
	if card == null or not is_instance_valid(card):
		return null
	var wrapper := card.get_parent()
	if wrapper == null:
		return null
	for child: Node in wrapper.get_children():
		if child is Button:
			return child as Button
	return null


func _find_button(host: Node, wanted: String) -> Button:
	for node: Node in _walk(host):
		if node is Button and (node as Button).text.to_lower() == wanted.to_lower():
			return node as Button
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[wayside-picker-flow] PASS ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("[wayside-picker-flow] FAIL %s" % label)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[wayside-picker-flow] RESULT failures=%d" % _failures)
	if current_scene == _scene:
		current_scene = null
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	quit(1 if _failures > 0 else 0)
