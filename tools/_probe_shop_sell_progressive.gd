extends SceneTree
## Headless behavior regression for Shop's coordinated card-removal picker.
##
## (2026-09-16: this picker used to be the sutler's buy-back, which PAID for the
## card. It now charges Shop.REMOVE_FEE. The file name is kept so the harness
## runner and its history keep resolving.)
##
## Contracts exercised through the real Shop scene and real button signals:
##   1. Cancel, loading copy, and every final card slot exist before hydration.
##      Rich faces remain hidden until the complete deck turns together.
##   2. Cancel rebuilds the shop, advances the generation, and a suspended old
##      hydration cannot append stale cards afterward.
##   3. Loading hit targets stay locked; a revealed card's transparent target
##      removes exactly its captured deck index/UID, charges once, and cannot
##      remove a second card that visit.
##
## No save slot is claimed and the test never opens a window:
##   Godot_v4.6.2-stable_win64_console.exe --headless --path "D:\\Godot" ^
##       --script res://tools/_probe_shop_sell_progressive.gd

const RUN_SEED := 20260910
const TARGET_DECK_SIZE := 14
const DEADLINE_MS := 15000

var _fails := 0
var _shop: Control = null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(DisplayServer.get_name() == "headless",
		"probe is running on the headless display server")
	if DisplayServer.get_name() != "headless":
		print("[shop-sell-progressive] REFUSED: this regression is headless-only")
		quit(1)
		return

	var rs := root.get_node_or_null("RunState")
	var db := root.get_node_or_null("CardDB")
	var cache := root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	_check(rs != null and db != null and cache != null and settings != null,
		"Shop removal-picker dependencies are present")
	if rs == null or db == null or cache == null or settings == null:
		quit(1)
		return

	# Structural half of the first contract: even if card zero is already warm
	# enough to stage synchronously, the source must create and connect Cancel
	# before entering the hydration loop.
	var shop_source := FileAccess.get_file_as_string("res://scripts/scenes/Shop.gd")
	var sell_start := shop_source.find("func _start_removal_mode()")
	var cancel_pos := shop_source.find("var cancel_btn", sell_start)
	var hydration_pos := shop_source.find("for i in range(RunState.deck.size())", sell_start)
	_check(sell_start >= 0 and cancel_pos > sell_start and hydration_pos > cancel_pos,
		"Cancel is constructed before the removal-card hydration loop")
	var predicate_pos := shop_source.find("var grid_ref", sell_start)
	var predicate_end := shop_source.find("for i in range(RunState.deck.size())",
		predicate_pos)
	var predicate_source := shop_source.substr(predicate_pos,
		predicate_end - predicate_pos) if predicate_pos >= 0 and predicate_end > predicate_pos else ""
	_check(predicate_source.contains("weakref(grid)") \
			and predicate_source.contains("grid_ref.get_ref()"),
		"cancellation predicate keeps only a WeakRef to the disposable grid")
	settings.reduce_motion = true
	settings.particles = false
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = "shop"
	# Enough for two strikes at the posted fee. The tile disables itself below
	# the fee now, so an underfunded fixture would test the DENIED path and
	# report a picker that never opened as a broken picker.
	rs.gold = maxi(137, _shop_fee_const() * 2)
	_pad_deck(rs, db)

	_shop = load("res://scenes/shop.tscn").instantiate()
	root.add_child(_shop)
	_check(await _wait_until(func() -> bool:
		return is_instance_valid(_shop) and bool(_shop.get("_entered")) \
			and _find_button_named(_shop, "Remove a Card") != null),
		"real Shop ready path exposes the removal tile")

	# Warm only card zero's painting, not its baked face. This makes entry reach
	# Shop's explicit per-card process-frame yield deterministically: at most one
	# card can stage before we inspect and press the already-created Cancel.
	cache.clear()
	CardArtAliases.clear_runtime_caches()
	var first_data: Dictionary = rs.get_upgraded_card_data(0)
	await CardArtAliases.prewarm_card_art(first_data)

	var generation_before := int(_shop.get("_removal_build_generation"))
	_shop.call("_start_removal_mode")
	var sell_generation := int(_shop.get("_removal_build_generation"))
	var early_cancel := _find_button_named(_shop, "Cancel")
	_check(sell_generation == generation_before + 1,
		"opening removal mode advances its build generation")
	_check(early_cancel != null and not early_cancel.disabled,
		"Cancel is live before coordinated deck hydration completes")
	_check(_removal_loading_label(_shop) != null,
		"loading state is visible while deck hydration is incomplete")
	_check(_active_removal_slot_count(_shop) == rs.deck.size(),
		"entry reserves the complete final deck grid before its first yield")
	_check(_all_removal_buttons_locked(_shop) and _removal_visible_card_count(_shop) == 0,
		"face-down removal slots cannot be clicked and expose no partial face set")

	if early_cancel != null:
		early_cancel.emit_signal("pressed")
	var cancelled_generation := int(_shop.get("_removal_build_generation"))
	_check(cancelled_generation > sell_generation,
		"Cancel rebuild invalidates the suspended removal generation")
	# The old builder is parked on Shop's explicit per-card process-frame yield.
	# Give it several resumptions to observe the generation mismatch and return.
	for _i in 12:
		await process_frame
	var cancelled_settled := _find_button_named(_shop, "Remove a Card") != null \
		and _active_removal_slot_count(_shop) == 0
	_check(cancelled_settled,
		"cancelled staged builder drains back to the normal shop")
	_check(int(_shop.get("_removal_build_generation")) == cancelled_generation,
		"stale coroutine cannot mutate the replacement generation")
	_check(_active_removal_slot_count(_shop) == 0 \
			and _find_label_named(_shop, "Choose a card to remove") == null,
		"cancelled picker appends no stale cards behind the rebuilt shop")
	_check(_find_button_named(_shop, "Remove a Card") != null,
		"normal shop UI remains interactive after cancellation")

	# Open again and let the real headless hydration path complete. Ornate cards
	# may finish one per frame internally, but presentation stays as one fixed grid
	# of backs until the whole deck can be revealed together.
	_shop.set("_transaction_busy", false)
	_shop.set("_struck_this_visit", false)
	_shop.call("_start_removal_mode")
	var second_cancel := _find_button_named(_shop, "Cancel")
	var initial_staged := _active_removal_slot_count(_shop)
	_check(second_cancel != null and initial_staged == rs.deck.size(),
		"second picker is cancellable with its complete face-down grid already reserved")
	_check(_all_removal_buttons_locked(_shop),
		"second picker keeps every transparent hit target locked while loading")
	var sample := await _sample_removal_reveal(_shop, rs.deck.size())
	_check(bool(sample.ready), "coordinated sell picker reveals the full live deck")
	_check(_all_equal(sample.slots, rs.deck.size()),
		"sell grid keeps its final slot count for every sampled frame")
	_check(_no_partial_visible(sample.visible, rs.deck.size()),
		"sell-card faces jump only from zero to the complete deck")
	_check(_removal_loading_label(_shop) == null,
		"preparing copy retires after the final staged card")

	var slots: Array = _shop.get("_removal_card_nodes")
	var chosen_index := mini(5, rs.deck.size() - 1)
	var chosen_slot: Control = slots[chosen_index] as Control if chosen_index >= 0 \
		and chosen_index < slots.size() else null
	var click_target := _direct_overlay_button(chosen_slot)
	_check(click_target != null and not click_target.disabled,
		"revealed card unlocks its real transparent bound click target")

	var deck_before: Array = rs.deck.duplicate()
	var uids_before: Array = rs.deck_uids.duplicate()
	var gold_before := int(rs.gold)
	var chosen_id := String(deck_before[chosen_index])
	var chosen_uid := int(uids_before[chosen_index])
	# The fee takes no argument — it is flat for every card in the pack. Asking
	# the shop rather than restating 60 is what keeps this probe from becoming a
	# second copy of the price rule.
	var fee := int(_shop.call("_removal_fee"))
	var expected_deck := deck_before.duplicate()
	var expected_uids := uids_before.duplicate()
	expected_deck.remove_at(chosen_index)
	expected_uids.remove_at(chosen_index)

	if click_target != null:
		click_target.emit_signal("pressed")
	_check(rs.deck == expected_deck and rs.deck_uids == expected_uids,
		"staged click removes exactly bound index %d (uid %d, %s)" % [
			chosen_index, chosen_uid, chosen_id])
	_check(rs.gold == gold_before - fee and bool(_shop.get("_struck_this_visit")),
		"bound removal CHARGES its exact fee (%d) and latches the one-a-visit" % fee)

	# Retain the old button reference deliberately. The removal queues that picker
	# for deletion while rebuilding the shop; a duplicate signal must still be
	# harmless whether it meets the transaction latch or the struck-this-visit gate.
	var once_deck: Array = rs.deck.duplicate()
	var once_uids: Array = rs.deck_uids.duplicate()
	var once_gold := int(rs.gold)
	if click_target != null and is_instance_valid(click_target):
		click_target.emit_signal("pressed")
	for _i in 5:
		await process_frame
	_check(rs.deck == once_deck and rs.deck_uids == once_uids \
			and rs.gold == once_gold,
		"repeat signal from the stale staged card cannot remove or charge twice")
	_check(_active_removal_slot_count(_shop) == 0 \
			and _find_button_named(_shop, "Remove a Card") != null,
		"successful removal returns to a clean non-stale Shop UI")

	await _cleanup()
	print("[shop-sell-progressive] %s" % (
		"PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


## The posted fee, read off Shop's own constant map — the fixture must fund the
## purse BEFORE the scene builds (the tile disables itself below the fee), so
## the shop instance does not exist yet to be asked.
func _shop_fee_const() -> int:
	var src: GDScript = load("res://scripts/scenes/Shop.gd") as GDScript
	if src == null:
		return 60
	return int(src.get_script_constant_map().get("REMOVE_FEE", 60))


func _pad_deck(rs: Node, db: Node) -> void:
	var existing := {}
	for id_variant in rs.deck:
		existing[String(id_variant)] = true
	var ids: Array = db.CARD_POOL.keys()
	ids.sort()
	for id_variant in ids:
		if rs.deck.size() >= TARGET_DECK_SIZE:
			break
		var id := String(id_variant)
		var data: Dictionary = db.get_card_data(id)
		var rarity := String(data.get("rarity", ""))
		if existing.has(id) or data.is_empty() or rarity in ["enemy", "token"] \
				or db.is_curse(id):
			continue
		rs.add_card(id)
		existing[id] = true


func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		if predicate.is_valid() and bool(predicate.call()):
			return true
		await process_frame
	return false


func _active_removal_slot_count(shop: Node) -> int:
	if shop == null or not is_instance_valid(shop):
		return 0
	var count := 0
	var slots: Array = shop.get("_removal_card_nodes")
	for slot_variant in slots:
		if not is_instance_valid(slot_variant):
			continue
		if slot_variant is Node \
				and (slot_variant as Node).is_inside_tree() \
				and not (slot_variant as Node).is_queued_for_deletion():
			count += 1
	return count


func _removal_visible_card_count(shop: Node) -> int:
	var count := 0
	for raw_slot in shop.get("_removal_card_nodes"):
		var slot := raw_slot as Control
		if slot == null or not is_instance_valid(slot) or not slot.is_inside_tree() \
				or slot.is_queued_for_deletion():
			continue
		for node in _walk(slot):
			var script: Script = node.get_script()
			if node is Control and not node.is_queued_for_deletion() and script != null \
					and String(script.resource_path).ends_with("/Card2D.gd") \
					and (node as Control).is_visible_in_tree():
				count += 1
	return count


func _removal_buttons(shop: Node) -> Array[Button]:
	var out: Array[Button] = []
	if shop == null or not is_instance_valid(shop):
		return out
	for raw_slot in shop.get("_removal_card_nodes"):
		var button := _direct_overlay_button(raw_slot as Control)
		if button != null and is_instance_valid(button):
			out.append(button)
	return out


func _all_removal_buttons_locked(shop: Node) -> bool:
	var buttons := _removal_buttons(shop)
	if buttons.is_empty():
		return false
	for button in buttons:
		if not button.disabled or button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return false
	return true


func _sample_removal_reveal(shop: Node, expected: int) -> Dictionary:
	var slot_counts: Array[int] = []
	var visible_counts: Array[int] = []
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		slot_counts.append(_active_removal_slot_count(shop))
		visible_counts.append(_removal_visible_card_count(shop))
		var buttons := _removal_buttons(shop)
		var unlocked := buttons.size() == expected
		for button in buttons:
			unlocked = unlocked and not button.disabled \
				and button.mouse_filter == Control.MOUSE_FILTER_STOP
		if _removal_loading_label(shop) == null \
				and _removal_visible_card_count(shop) == expected and unlocked:
			return {"ready": true, "slots": slot_counts, "visible": visible_counts}
		await process_frame
	return {"ready": false, "slots": slot_counts, "visible": visible_counts}


func _all_equal(values: Array, expected: int) -> bool:
	return not values.is_empty() and values.all(func(value): return int(value) == expected)


func _no_partial_visible(values: Array, expected: int) -> bool:
	return not values.is_empty() and int(values.back()) == expected \
		and values.all(func(value): return int(value) == 0 or int(value) == expected)


func _direct_overlay_button(slot: Control) -> Button:
	if slot == null or not is_instance_valid(slot) or slot.get_child_count() == 0:
		return null
	var wrapper := slot.get_child(0)
	for child in wrapper.get_children():
		if child is Button:
			return child as Button
	return null


func _find_button_named(host: Node, wanted: String) -> Button:
	if host == null or not is_instance_valid(host):
		return null
	for node in _walk(host):
		if not (node is Button) or node.is_queued_for_deletion():
			continue
		var button := node as Button
		if button.text.strip_edges().nocasecmp_to(wanted) == 0:
			return button
		for child in _walk(button):
			if child is Label and not child.is_queued_for_deletion() \
					and (child as Label).text.strip_edges().nocasecmp_to(wanted) == 0:
				return button
	return null


func _find_label_named(host: Node, wanted: String) -> Label:
	if host == null or not is_instance_valid(host):
		return null
	for node in _walk(host):
		if node is Label and not node.is_queued_for_deletion() \
				and (node as Label).text.strip_edges().nocasecmp_to(wanted) == 0:
			return node as Label
	return null


func _find_label_prefix(host: Node, prefix: String) -> Label:
	if host == null or not is_instance_valid(host):
		return null
	for node in _walk(host):
		if node is Label and not node.is_queued_for_deletion() \
				and (node as Label).text.begins_with(prefix):
			return node as Label
	return null


func _removal_loading_label(host: Node) -> Label:
	var preparing := _find_label_prefix(host, "PREPARING THE DECK")
	if preparing != null:
		return preparing
	return _find_label_prefix(host, "UNSEALING THE DECK")


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _cleanup() -> void:
	if _shop != null and is_instance_valid(_shop):
		_shop.queue_free()
	for _i in 8:
		await process_frame
	_shop = null
	await create_timer(0.25).timeout
	CardArtAliases.clear_runtime_caches()
