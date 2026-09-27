extends SceneTree
## Headless lifecycle regression for coordinated Quick and Sealed card reveals.
##
## Exercises the real scenes through the practice-bot connection contract:
##   - every final slot exists before the first rich-card hydration yield;
##   - no rich face is visible until the whole logical set is complete;
##   - loading-time input is inert and unlocks only after the group reveal;
##   - a ready-state reroll replaces the complete set atomically;
##   - only the current deck/pool survives;
##   - Sealed's real pool button still adds/removes the correct card;
##   - the network-only chart-style pass also reaches replacement Arsenal slates.

const MATCH_SEED := 20260910
const DEADLINE_MS := 20000

var _fails: int = 0
var _net_match: Node
var _skirmish: Node
var _settings: Node
var _cache: Node


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _run() -> void:
	print("[net-quick-sealed-progressive] BEGIN")
	_check(DisplayServer.get_name() == "headless",
		"probe is running on the headless display server")
	_net_match = root.get_node_or_null("NetMatch")
	_skirmish = root.get_node_or_null("SkirmishState")
	_settings = root.get_node_or_null("UserSettings")
	_cache = root.get_node_or_null("CardTextureCache")
	_check(
		_net_match != null and _skirmish != null and _settings != null
		and _cache != null,
		"required autoloads exist")
	if _net_match == null or _skirmish == null or _settings == null or _cache == null:
		_finish()
		return
	_settings.reduce_motion = true
	_settings.particles = false

	await _test_quick()
	await _test_sealed()
	_finish()


func _prepare_mode(mode: int) -> void:
	_net_match.local_hero = "raider"
	_net_match.start_vs_bot(mode, 1)
	_net_match.match_seed = MATCH_SEED
	_net_match.match_mode = mode
	_net_match.best_of = 1
	_skirmish.reset()
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	await process_frame


func _open_screen(path: String) -> Control:
	var packed: PackedScene = load(path)
	var screen: Control = packed.instantiate()
	root.add_child(screen)
	await process_frame
	return screen


func _skip_arsenal(screen: Control, label: String) -> void:
	_check(bool(screen.call("arsenal_active")),
		"%s begins behind the authentic Arsenal stage" % label)
	for pick in 5:
		var deadline := Time.get_ticks_msec() + DEADLINE_MS
		while bool(screen.call("arsenal_active")) \
				and not bool(screen.call("arsenal_slate_ready")) \
				and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(not bool(screen.call("arsenal_active")) \
			or bool(screen.call("arsenal_slate_ready")),
			"%s Arsenal slate %d reveals before input" % [label, pick + 1])
		if not bool(screen.call("arsenal_active")):
			break
		var before: Dictionary = _chart_style_counts(screen)
		_check(int(before.rich) == 0 and int(before.batched) > 0,
			"%s Arsenal slate %d is already batched" % [label, pick + 1])
		screen.call("_on_ars_pass")
		await process_frame
	_check(not bool(screen.call("arsenal_active")),
		"%s Arsenal completes through the real pass action" % label)


func _test_quick() -> void:
	print("[net-quick-sealed-progressive] QUICK")
	await _prepare_mode(_skirmish.MatchMode.QUICK)
	var screen: Control = await _open_screen("res://scenes/net_quick.tscn")
	await _skip_arsenal(screen, "Quick")

	var first_expected: int = _unique_ids(screen.get("_local_deck")).size()
	var first_count: int = (screen.get("_deck_box") as Node).get_child_count()
	_check(first_count == first_expected,
		"Quick reserves every final deck slot before cold hydration completes")
	_check(not bool(screen.call("quick_cards_ready")),
		"Quick remains input-locked while rich faces hydrate behind sleeves")
	var old_generation: int = int(screen.get("_deck_gen"))
	screen.call("_on_reroll")
	_check(int(screen.get("_deck_gen")) == old_generation,
		"Quick rejects a loading-time reroll")

	var initial_sample: Dictionary = await _wait_quick_ready(screen)
	print("[net-quick-sealed-progressive] quick slots=", initial_sample.slots,
		" visible=", initial_sample.visible)
	_check(_all_equal(initial_sample.slots, first_expected),
		"Quick keeps its complete slot geometry stable throughout hydration")
	_check(_no_partial_visible(initial_sample.visible, first_expected),
		"Quick reveals no load-order subset of the deck")

	var ready_generation: int = int(screen.get("_deck_gen"))
	screen.call("_on_reroll")
	var replacement_expected: int = _unique_ids(screen.get("_local_deck")).size()
	_check(int(screen.get("_deck_gen")) == ready_generation + 1,
		"Quick accepts one reroll after the coordinated reveal")
	_check(not bool(screen.call("quick_cards_ready")) \
		and (screen.get("_deck_box") as Node).get_child_count() == replacement_expected,
		"Quick reroll immediately swaps to a complete face-down geometry")
	var replacement_sample: Dictionary = await _wait_quick_ready(screen)
	_check(_all_equal(replacement_sample.slots, replacement_expected) \
		and _no_partial_visible(replacement_sample.visible, replacement_expected),
		"Quick replacement also stays fixed and reveals atomically")
	var deck: Array = screen.get("_local_deck")
	var expected_ids: Dictionary = _unique_ids(deck)
	var deck_box: Node = screen.get("_deck_box")
	_check(deck_box.get_child_count() == expected_ids.size(),
		"Quick replacement has exactly one tile per unique current card")
	_check(_displayed_card_ids(deck_box) == expected_ids,
		"Quick replacement contains only current-generation card ids")
	var style_counts: Dictionary = _chart_style_counts(screen)
	_check(int(style_counts.rich) == 0 and int(style_counts.batched) > 0,
		"Quick leaves no rich chart style in its persistent screen furniture")

	await _close_screen(screen)


func _wait_quick_ready(screen: Control) -> Dictionary:
	var slot_progression: Array[int] = []
	var visible_progression: Array[int] = []
	var stable: int = 0
	var deadline: int = Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var box: Node = screen.get("_deck_box")
		var count: int = box.get_child_count()
		slot_progression.append(count)
		visible_progression.append(_visible_card_count(box))
		var expected: int = _unique_ids(screen.get("_local_deck")).size()
		if bool(screen.call("quick_cards_ready")) and count == expected:
			stable += 1
			if stable >= 3:
				break
		else:
			stable = 0
	_check(stable >= 3, "Quick replacement reaches a stable complete deck")
	return {"slots": slot_progression, "visible": visible_progression}


func _test_sealed() -> void:
	print("[net-quick-sealed-progressive] SEALED")
	await _prepare_mode(_skirmish.MatchMode.SEALED)
	var screen: Control = await _open_screen("res://scenes/net_sealed.tscn")
	await _skip_arsenal(screen, "Sealed")

	var first_expected: int = (screen.get("_avail") as Dictionary).size()
	var first_count: int = (screen.get("_pool_grid") as Node).get_child_count()
	_check(first_count == first_expected,
		"Sealed reserves every opened-pool slot before cold hydration completes")
	_check(not bool(screen.call("sealed_cards_ready")),
		"Sealed remains input-locked while rich faces hydrate behind sleeves")
	var early_id := String((screen.get("_sorted_pool_ids") as Array)[0])
	screen.call("_on_add", early_id)
	_check((screen.get("_deck") as Array).is_empty(),
		"Sealed rejects a loading-time card choice")
	var old_generation: int = int(screen.get("_pool_gen"))
	screen.call("_on_reroll")
	_check(int(screen.get("_pool_gen")) == old_generation,
		"Sealed rejects a loading-time reroll")
	_check((screen.get("_deck") as Array).is_empty()
		and (screen.get("_counts") as Dictionary).is_empty(),
		"Sealed loading-time actions leave the working deck untouched")

	var initial_sample: Dictionary = await _wait_sealed_ready(screen)
	print("[net-quick-sealed-progressive] sealed slots=", initial_sample.slots,
		" visible=", initial_sample.visible)
	_check(_all_equal(initial_sample.slots, first_expected),
		"Sealed keeps its complete slot geometry stable throughout hydration")
	_check(_no_partial_visible(initial_sample.visible, first_expected),
		"Sealed reveals no load-order subset of its opened pool")

	var ready_generation: int = int(screen.get("_pool_gen"))
	screen.call("_on_reroll")
	var replacement_expected := (screen.get("_avail") as Dictionary).size()
	_check(int(screen.get("_pool_gen")) == ready_generation + 1,
		"Sealed accepts one reroll after the coordinated reveal")
	_check(not bool(screen.call("sealed_cards_ready")) \
		and (screen.get("_pool_grid") as Node).get_child_count() == replacement_expected,
		"Sealed reroll immediately swaps to a complete face-down geometry")
	var replacement_sample: Dictionary = await _wait_sealed_ready(screen)
	_check(_all_equal(replacement_sample.slots, replacement_expected) \
		and _no_partial_visible(replacement_sample.visible, replacement_expected),
		"Sealed replacement also stays fixed and reveals atomically")
	var avail: Dictionary = screen.get("_avail")
	var catalog: Dictionary = screen.get("_pool_catalog")
	var sorted_ids: Array = screen.get("_sorted_pool_ids")
	var pool_grid: Node = screen.get("_pool_grid")
	_check(catalog.size() == avail.size() and sorted_ids.size() == avail.size(),
		"Sealed replacement catalog and sort order match its current pool")
	_check(pool_grid.get_child_count() == avail.size(),
		"Sealed replacement has exactly one tile per opened card id")
	_check(_displayed_card_ids(pool_grid) == _string_key_set(avail),
		"Sealed replacement contains only current-generation card ids")

	var first_id: String = String(sorted_ids[0])
	var refs: Dictionary = (screen.get("_pool_rows") as Dictionary)[first_id]
	var add_button: Button = refs["button"]
	add_button.emit_signal("pressed")
	await process_frame
	_check((screen.get("_deck") as Array).size() == 1
		and int((screen.get("_counts") as Dictionary).get(first_id, 0)) == 1,
		"Sealed's real pool button adds the displayed card exactly once")
	var deck_box: Node = screen.get("_deck_box")
	_check(deck_box.get_child_count() == int(screen.get("_target")),
		"Sealed keeps all twenty deck footprints after an enlistment")
	screen.call("_on_remove", first_id)
	await process_frame
	_check((screen.get("_deck") as Array).is_empty()
		and not add_button.disabled,
		"Sealed removal restores the same pool button")
	_check(deck_box.get_child_count() == int(screen.get("_target")),
		"Sealed restores a ghost without reflowing the deck footprint")
	var style_counts: Dictionary = _chart_style_counts(screen)
	_check(int(style_counts.rich) == 0 and int(style_counts.batched) > 0,
		"Sealed leaves no rich chart style in persistent screen furniture")

	await _close_screen(screen)


func _wait_sealed_ready(screen: Control) -> Dictionary:
	var slot_progression: Array[int] = []
	var visible_progression: Array[int] = []
	var stable: int = 0
	var deadline: int = Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var grid: Node = screen.get("_pool_grid")
		var count: int = grid.get_child_count()
		slot_progression.append(count)
		visible_progression.append(_visible_card_count(grid))
		var expected: int = (screen.get("_avail") as Dictionary).size()
		if bool(screen.call("sealed_cards_ready")) and count == expected:
			stable += 1
			if stable >= 3:
				break
		else:
			stable = 0
	_check(stable >= 3, "Sealed replacement reaches a stable complete pool")
	return {"slots": slot_progression, "visible": visible_progression}


func _unique_ids(values: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw_id in values:
		out[String(raw_id)] = true
	return out


func _string_key_set(values: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_id in values:
		out[String(raw_id)] = true
	return out


func _displayed_card_ids(host: Node) -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if "card_id" in node:
			var id: String = String(node.get("card_id"))
			if id != "":
				out[id] = true
		for child in node.get_children():
			stack.append(child)
	return out


func _visible_card_count(host: Node) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script()
		if node is Control and script != null \
				and String(script.resource_path).ends_with("/Card2D.gd") \
				and (node as Control).is_visible_in_tree():
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count


func _all_equal(values: Array, expected: int) -> bool:
	if values.is_empty():
		return false
	for raw in values:
		if int(raw) != expected:
			return false
	return true


func _no_partial_visible(values: Array, expected: int) -> bool:
	if values.is_empty() or int(values.back()) != expected:
		return false
	for raw in values:
		var count := int(raw)
		if count != 0 and count != expected:
			return false
	return true


func _chart_style_counts(host: Node) -> Dictionary:
	var rich: int = 0
	var batched: int = 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			var control: Control = node
			var slots: Array[StringName] = []
			if control is PanelContainer:
				slots.append(&"panel")
			if control is Button:
				slots.append_array([
					&"normal", &"focus", &"hover", &"pressed", &"disabled"])
			for slot in slots:
				if not control.has_theme_stylebox_override(slot):
					continue
				var style: StyleBox = control.get_theme_stylebox(slot)
				var style_script: Script = style.get_script()
				var script_path: String = ""
				if style_script != null:
					script_path = style_script.resource_path
				if script_path.ends_with("/GameTheme.gd"):
					rich += 1
				elif script_path.ends_with("/BatchedChartPanelStyle.gd"):
					batched += 1
		for child in node.get_children():
			stack.append(child)
	return {"rich": rich, "batched": batched}


func _close_screen(screen: Control) -> void:
	if screen != null and is_instance_valid(screen):
		root.remove_child(screen)
		screen.free()
	_net_match.leave()
	_skirmish.reset()
	for _i in 3:
		await process_frame


func _finish() -> void:
	_cache.clear()
	CardArtAliases.clear_runtime_caches()
	print("[net-quick-sealed-progressive] %s failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
