extends SceneTree
## Targeted headless contract probe for the adaptive/cache/virtualization/F3 pass.

var _fails := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cache: Node = root.get_node_or_null("CardTextureCache")
	var db: Node = root.get_node_or_null("CardDB")
	var overlay: Node = root.get_node_or_null("PerformanceOverlay")
	var ss: Node = root.get_node_or_null("Supersample")
	var pre: Node = root.get_node_or_null("ScenePreload")
	var encounters: Node = root.get_node_or_null("EncounterDB")
	var settings: Node = root.get_node_or_null("UserSettings")
	_check(cache != null and db != null, "card cache dependencies are present")
	_check(overlay != null and ss != null and settings != null,
		"diagnostics/scaler/settings autoloads are present")
	if cache == null or db == null or overlay == null or ss == null \
			or settings == null:
		quit(1)
		return

	# Secondary snapshot costs follow the effective quality tier independently
	# from the whole-screen adaptive scaler. Ultra remains pixel-identical to the
	# former fixed path; lower tiers spend less memory and transition work.
	var original_preset := String(settings.graphics_preset)
	var original_render_scale := float(settings.render_scale)
	var original_particles := bool(settings.particles)
	var expected_cards := {
		"low": Vector2i(2, 24),
		"medium": Vector2i(2, 32),
		"high": Vector2i(3, 40),
		"ultra": Vector2i(3, 48),
	}
	var expected_maps := {
		"low": 1.0,
		"medium": 1.5,
		"high": 1.5,
		"ultra": 2.0,
	}
	var terrain: Control = (load("res://scripts/scenes/MapTerrain.gd") \
		as GDScript).new()
	for tier_variant in expected_cards.keys():
		var tier := String(tier_variant)
		settings.graphics_preset = tier
		cache._sync_gameplay_quality()
		var card_contract: Vector2i = expected_cards[tier]
		_check(cache.gameplay_bake_scale() == card_contract.x \
				and cache.gameplay_cache_limit() == card_contract.y,
			"%s hand-card bake quality and cache budget" % tier)
		_check(is_equal_approx(float(terrain._resolve_plate_bake_scale()),
			float(expected_maps[tier])),
			"%s map plate bake quality" % tier)
	settings.graphics_preset = "custom"
	settings.render_scale = 1.0
	settings.particles = false
	_check(String(settings.effective_graphics_tier()) == "low",
		"Custom native/no-particles resolves to the Low cache tier")
	settings.render_scale = 2.0
	settings.particles = true
	_check(String(settings.effective_graphics_tier()) == "ultra",
		"Custom 2x resolves to the Ultra cache tier")
	cache.clear()
	settings.graphics_preset = "low"
	cache._sync_gameplay_quality()
	var low_key := String(cache.gameplay_cache_key({"id": "quality_probe"}))
	cache._cache[low_key] = GradientTexture1D.new()
	cache._touch_key(low_key)
	settings.graphics_preset = "high"
	cache._sync_gameplay_quality()
	_check(not cache._cache.has(low_key) \
			and low_key != String(cache.gameplay_cache_key({"id": "quality_probe"})),
		"changing hand bake resolution invalidates old-resolution snapshots")
	settings.graphics_preset = "low"
	cache.clear()
	cache._sync_gameplay_quality()
	for i in range(30):
		var probe_key := "%sprobe_%d" % [cache.GAMEPLAY_KEY_PREFIX, i]
		cache._cache[probe_key] = GradientTexture1D.new()
		cache._touch_key(probe_key)
	cache._trim_cache()
	_check(cache._cache.size() == 24 and not cache._cache.has("gameplay|probe_0") \
			and cache._cache.has("gameplay|probe_29"),
		"Low hand-card LRU evicts oldest snapshots at 24 entries")
	cache.clear()
	settings.graphics_preset = original_preset
	settings.render_scale = original_render_scale
	settings.particles = original_particles
	cache._sync_gameplay_quality()
	terrain.free()
	if pre != null and encounters != null and not encounters.ENCOUNTERS.is_empty():
		var encounter_id := String(encounters.ENCOUNTERS.keys()[0])
		var counter_before: int = encounters._enc_counter
		seed(77123)
		var expected_rng := randi()
		seed(77123)
		await pre._warm_encounter_art(encounter_id)
		_check(encounters._enc_counter == counter_before and randi() == expected_rng,
			"speculative encounter art warming does not roll or allocate a fight")

	# Seed a fake snapshot so Card2D takes the cached battlefield branch without
	# requiring frame_post_draw under the dummy renderer.
	var data: Dictionary = db.get_card_data("pikeman")
	var image := Image.create(432, 332, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.18, 0.12, 0.07, 1.0))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	var key: String = cache.battlefield_cache_key(data)
	cache._battlefield_cache[key] = texture
	cache._touch_battlefield_key(key)
	var card = load("res://scenes/card_2d.tscn").instantiate()
	card.card_data = data.duplicate(true)
	card.card_id = String(data.get("id", ""))
	card.is_on_battlefield = true
	card.compact_mode = true
	root.add_child(card)
	await process_frame
	_check(_tree_uses_texture(card, texture),
		"battlefield Card2D renders the cached snapshot quad")
	_check(card._atk_label != null and card._hp_label != null,
		"ATK and HP remain live above the snapshot")
	card.current_atk += 3
	card.current_hp -= 1
	card.update_stat_display()
	_check(card._atk_label.text == str(card.effective_atk()) \
			and card._hp_label.text == str(card.current_hp),
		"cached token numerals update without rebaking")
	card.queue_free()
	await process_frame
	cache._battlefield_cache.erase(key)
	var late_card = load("res://scenes/card_2d.tscn").instantiate()
	late_card.card_data = data.duplicate(true)
	late_card.card_id = String(data.get("id", ""))
	late_card.is_on_battlefield = true
	late_card.compact_mode = true
	root.add_child(late_card)
	await process_frame
	cache.battlefield_texture_ready.connect(
		late_card._on_battlefield_texture_ready)
	cache._battlefield_cache[key] = texture
	cache.battlefield_texture_ready.emit(key)
	await process_frame
	_check(_tree_uses_texture(late_card, texture),
		"a late snapshot hot-swaps an already-seated synthetic token")
	_check(not cache.battlefield_texture_ready.is_connected(
		late_card._on_battlefield_texture_ready),
		"late token disconnects from cache notifications after swapping")
	late_card.queue_free()
	await process_frame
	var gallery_key: String = cache.gallery_cache_key(data)
	cache._cache[gallery_key] = texture
	cache._touch_key(gallery_key)
	_check(cache.has_gallery(data) and not cache.has(data),
		"gallery and gameplay snapshots have separate cache identities")
	var gallery_card = load("res://scenes/card_2d.tscn").instantiate()
	gallery_card.card_data = data.duplicate(true)
	gallery_card.card_id = String(data.get("id", ""))
	gallery_card.is_on_battlefield = true
	gallery_card.static_display = true
	gallery_card.live_baked_mode = true
	gallery_card.gallery_baked_mode = true
	root.add_child(gallery_card)
	await process_frame
	_check(_tree_uses_texture(gallery_card, texture),
		"Collection display selects the native gallery cache class")
	gallery_card.queue_free()
	cache._cache.erase(gallery_key)
	await process_frame

	# Collection builds the whole cheap index, but headless deliberately never
	# hydrates it. This verifies the virtualization model without GPU snapshots.
	var collection = load("res://scenes/collection.tscn").instantiate()
	root.add_child(collection)
	for _i in 8:
		await process_frame
	_check(collection._card_jobs.size() > 60,
		"Collection indexes the full card library")
	var placeholder_count := 0
	for job in collection._card_jobs:
		if String(job.get("state", "")) == "placeholder":
			placeholder_count += 1
	_check(placeholder_count == collection._card_jobs.size(),
		"Collection retains cheap off-screen placeholders")
	_check(collection._card_hydration_gen == -1,
		"headless Collection never parks on a GPU bake")
	collection.show_tab("relics")
	await process_frame
	_check(collection._card_jobs.is_empty() and not collection.is_processing(),
		"leaving Cards cancels the virtual card window")
	collection.queue_free()
	await process_frame

	overlay._refresh_text()
	_check("1% low" in overlay._label.text and "last scene load" in overlay._label.text,
		"F3 panel exposes frame consistency and transition timing")
	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	Input.parse_input_event(f3)
	await process_frame
	_check(overlay._shown and overlay._panel.visible,
		"F3 toggles the diagnostics panel")
	var f3_release := InputEventKey.new()
	f3_release.keycode = KEY_F3
	f3_release.pressed = false
	Input.parse_input_event(f3_release)
	await process_frame
	var f3_again := InputEventKey.new()
	f3_again.keycode = KEY_F3
	f3_again.pressed = true
	Input.parse_input_event(f3_again)
	await process_frame
	_check(not overlay._shown, "a second F3 press hides the panel")

	var owner := Node.new()
	root.add_child(owner)
	current_scene = owner
	ss.configure_scale(2.0, true)
	ss.begin_adaptive_scope(owner)
	_check(is_equal_approx(ss.get_requested_scale(), 2.0) \
			and is_equal_approx(ss._next_adaptive_scale(), 1.5),
		"adaptive scale starts from the saved quality ceiling")
	ss._set_effective_scale(1.5)
	_check(ss.is_adaptively_reduced(),
		"temporary adaptive reduction is distinguishable from the saved setting")
	ss.end_adaptive_scope(owner)
	_check(is_equal_approx(ss.get_effective_scale(), 2.0),
		"leaving combat restores the selected render scale")
	ss.apply_scale(1.0)
	_check(current_scene == owner,
		"disabling supersampling restores SceneTree.current_scene")
	current_scene = null
	owner.queue_free()
	cache.clear()

	print("RESULT: %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)


func _tree_uses_texture(node: Node, texture: Texture2D) -> bool:
	if node is TextureRect and node.texture == texture:
		return true
	for child in node.get_children():
		if _tree_uses_texture(child, texture):
			return true
	return false
