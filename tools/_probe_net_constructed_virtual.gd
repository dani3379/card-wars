extends SceneTree
## Headless behavior contract for NetConstructed's virtual pool. The dummy
## renderer leaves cold slots as ghosts; one synthetic gallery cache entry lets
## this probe also exercise hydrate -> click -> cool without a window.

const SCREEN_PATH := "res://scenes/net_constructed.tscn"
const MATCH_SEED := 20260910

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[net-constructed-virtual] BEGIN")
	var net_match := root.get_node_or_null("NetMatch")
	var skirmish := root.get_node_or_null("SkirmishState")
	var cache := root.get_node_or_null("CardTextureCache")
	_check(net_match != null and skirmish != null and cache != null,
		"required autoloads exist")
	if net_match == null or skirmish == null or cache == null:
		_finish()
		return

	net_match.start_vs_bot(1, 1) # NetMatch.MODE_CONSTRUCTED
	net_match.match_seed = MATCH_SEED
	skirmish.reset()
	var screen: Control = load(SCREEN_PATH).instantiate()
	root.add_child(screen)

	# The arsenal deliberately covers the builder. Skip all five slates, then let
	# batched placeholder construction and the deferred layout complete.
	for _i in 5:
		var arsenal_deadline := Time.get_ticks_msec() + 10000
		while screen.arsenal_active() and not screen.arsenal_slate_ready() \
				and Time.get_ticks_msec() < arsenal_deadline:
			await process_frame
		_check(not screen.arsenal_active() or screen.arsenal_slate_ready(),
			"Arsenal slate completes its coordinated reveal before input")
		if not screen.arsenal_active():
			break
		screen._on_ars_pass()
		await process_frame
	_check(not screen.arsenal_active(),
		"all five Arsenal slates complete through the real gated action")
	var deadline := Time.get_ticks_msec() + 5000
	while screen._pool_jobs.size() < screen._pool.size() \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	for _i in 3:
		await process_frame

	var expected_pool: int = skirmish.skirmish_legal_pool().size()
	_check(screen._pool.size() == expected_pool and expected_pool > 100,
		"full legal pool retained")
	_check(screen._pool_data.size() == expected_pool,
		"one cached data dictionary per legal card")
	_check(screen._pool_sort_keys.size() == expected_pool,
		"one cached scalar sort key per legal card")
	_check(screen._pool_jobs.size() == expected_pool,
		"one virtual job per legal card")
	_check(screen._pool_rows.size() == expected_pool,
		"one interactive row record per legal card")
	_check(screen._pool_box.get_child_count() == expected_pool,
		"flow geometry retains every fixed-size slot")

	var sorted_ok := true
	for i in range(1, screen._pool.size()):
		if screen._pool_sort_before(screen._pool[i], screen._pool[i - 1]):
			sorted_ok = false
			break
	_check(sorted_ok, "pool remains sorted by cached cost/name keys")

	var slots_ok := true
	var all_placeholders := true
	for job_value in screen._pool_jobs:
		var job: Dictionary = job_value
		var slot: Control = job.get("slot", null)
		if slot == null or not slot.custom_minimum_size.is_equal_approx(
				screen.POOL_THUMB_SIZE):
			slots_ok = false
		if String(job.get("state", "")) != "placeholder":
			all_placeholders = false
	_check(slots_ok, "all pool slots preserve the 0.46x card footprint")
	_check(all_placeholders and _count_card_nodes(screen._pool_box) == 0,
		"headless cold pool stays on lightweight ghosts")

	# The complete catalogue geometry is usable immediately, but a face-down
	# loading slot is not a card choice yet. Even a synthetic signal must be inert.
	var first_id: String = screen._pool[0]
	var refs: Dictionary = screen._pool_rows[first_id]
	var original_button: Button = refs["button"]
	_check(original_button.disabled and bool(original_button.get_meta(
		"card_loading", false)),
		"cold constructed slot locks click and hover until its ornate face is ready")
	original_button.emit_signal("pressed")
	await process_frame
	refs = screen._pool_rows[first_id]
	_check(screen._deck.is_empty() and not screen._counts.has(first_id),
		"synthetic click cannot select a face-down loading slot")
	original_button.emit_signal("mouse_entered")
	_check(screen._hover_id == "" and not is_instance_valid(screen._hover_preview),
		"loading slot cannot leak a full-card hover preview before group reveal")

	# Seed one tiny gallery entry so the cached branch can hydrate headlessly.
	var data: Dictionary = screen._pool_data[first_id]
	var image := Image.create(249, 324, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.15, 0.10, 0.06, 1.0))
	var texture := ImageTexture.create_from_image(image)
	var cache_key: String = cache.gallery_cache_key(data)
	cache._cache[cache_key] = texture
	cache._cache_order.append(cache_key)
	screen._refresh_pool_virtual_window(screen._pool_generation)
	await process_frame
	var first_job: Dictionary = screen._pool_jobs[0]
	var hydrated_visual: Control = first_job.get("visual", null)
	_check(String(first_job.get("state", "")) == "card" \
		and hydrated_visual != null \
		and bool(hydrated_visual.get("gallery_baked_mode")) \
		and bool(hydrated_visual.get("static_display")),
		"cached visible ghost hydrates into a static 1x gallery Card2D")
	_check((screen._pool_rows[first_id] as Dictionary)["button"] == original_button,
		"hydration preserves the original click/hover Button")
	refs = screen._pool_rows[first_id]
	_check(bool(refs.get("hydrated", false)) and not original_button.disabled \
		and not bool(original_button.get_meta("card_loading", true)),
		"constructed hit target unlocks only after the coordinated reveal settles")

	# Hover/click/count/copy-cap behavior becomes live after the face is revealed.
	original_button.emit_signal("mouse_entered")
	_check(screen._hover_id == first_id and screen._hover_anchor == original_button \
		and is_instance_valid(screen._hover_preview),
		"revealed card retains full-card hover preview semantics")
	original_button.emit_signal("mouse_exited")
	await process_frame
	_check(screen._hover_id == "", "revealed hover preview closes normally")

	original_button.emit_signal("pressed")
	await process_frame
	refs = screen._pool_rows[first_id]
	_check(screen._deck.size() == 1 and int(screen._counts[first_id]) == 1,
		"revealed card adds exactly once")
	_check(screen._deck_box.get_child_count() == screen._target \
		and _count_card_nodes(screen._deck_box) == 1,
		"Constructed keeps twenty footprints while one physical card replaces a ghost")
	_check((refs["badge"] as Label).visible \
		and (refs["badge"] as Label).text == "\u00d71",
		"revealed card updates its count badge")
	original_button.emit_signal("pressed")
	await process_frame
	refs = screen._pool_rows[first_id]
	_check(screen._deck.size() == 2 and original_button.disabled,
		"copy cap disables the permanent hit target")
	_check(screen._deck_box.get_child_count() == screen._target \
		and _count_card_nodes(screen._deck_box) == 2,
		"duplicate copy fills a second footprint without contracting the deck grid")
	_check((refs["card"] as Control).modulate.r < 0.5,
		"copy cap dims the current visual")
	original_button.emit_signal("pressed")
	_check(screen._deck.size() == 2, "disabled/capped card cannot add a third copy")
	screen._on_remove(first_id)
	await process_frame
	_check(screen._deck.size() == 1 and not original_button.disabled,
		"deck removal re-enables the same revealed hit target")
	_check(screen._deck_box.get_child_count() == screen._target \
		and _count_card_nodes(screen._deck_box) == 1,
		"removal restores one ghost without changing the deck grid footprint")

	# Move the scroll window to the opposite end; the original card must shed its
	# Card2D while retaining its slot, badge and permanent button.
	var bar: VScrollBar = screen._pool_scroll.get_v_scroll_bar()
	bar.value = bar.max_value
	for _i in 3:
		await process_frame
	screen._refresh_pool_virtual_window(screen._pool_generation)
	await process_frame
	first_job = screen._pool_jobs[0]
	_check(String(first_job.get("state", "")) == "placeholder",
		"far-away hydrated card cools back to a ghost")
	_check((screen._pool_rows[first_id] as Dictionary)["button"] == original_button,
		"cooling preserves the original click/hover Button")
	_check((screen._pool_rows[first_id] as Dictionary)["card"] == first_job["visual"],
		"row state follows the replacement visual")
	_check(original_button.disabled and bool(original_button.get_meta(
		"card_loading", false)),
		"cooled card returns to a locked back instead of a clickable half-state")

	var old_generation: int = screen._pool_generation
	_check(screen._pool_build_valid(old_generation), "current generation is valid")
	screen._pool_generation += 1
	_check(not screen._pool_build_valid(old_generation),
		"stale generation is rejected after cancellation")

	cache._cache.erase(cache_key)
	cache._cache_order.erase(cache_key)
	root.remove_child(screen)
	screen.free()
	net_match.leave()
	_finish()


func _count_card_nodes(node: Node) -> int:
	var count := 1 if node.get_script() != null \
		and String(node.get_script().resource_path).ends_with("/Card2D.gd") else 0
	for child in node.get_children():
		count += _count_card_nodes(child)
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		print("OK  ", label)
	else:
		_failures += 1
		push_error("FAIL  %s" % label)


func _finish() -> void:
	print("[net-constructed-virtual] PROBE_RESULT %s failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
