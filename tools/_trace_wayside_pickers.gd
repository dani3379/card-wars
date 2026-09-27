extends SceneTree
## Focused windowed trace for Wayside's three deck-sized Card2D pickers:
## Drill Yard, Standard-Bearer (donor -> receiver), and the retired legacy
## Trading Scales sell slate. The run/deck and chosen transitions are fixed.
##
## This intentionally clears only CardTextureCache after the process-level
## prewarm. It therefore isolates the cold face-bake/construction path without
## mixing boot shader/font compilation into every case. It never saves and the
## Standard-Bearer case stops before applying the transfer.
##
## Run windowed and serially (all cases or one named case):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \
##       --script res://tools/_trace_wayside_pickers.gd -- --case=all
##   --case=drill | --case=banner | --case=scales | --case=cancel
##
## Parse/autoload smoke only (safe under the dummy renderer):
##   ... --headless --script res://tools/_trace_wayside_pickers.gd -- --check-only

const RUN_SEED := 20260909
const DEADLINE_MS := 25000
const SETTLE_FRAMES := 4
const EXTRA_CARD_IDS: Array[String] = [
	"lookout", "thornguard", "raven", "battle_drummer", "hound",
	"warding_stone", "basilisk", "adrenaline",
]

var _started := false
var _done := false
var _run_state: Node = null
var _cache: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[wayside-pickers] CHECK_ONLY_OK")
		_done = true
		quit(0)
		return
	var settings := root.get_node_or_null("UserSettings")
	_run_state = root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	if settings == null or _run_state == null or _cache == null:
		push_error("[wayside-pickers] required autoload missing")
		_finish(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = true
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()

	var requested := _arg_value("--case=", "all")
	var cases: Array[String] = ["drill", "banner", "scales", "cancel"] \
		if requested == "all" else [requested]
	for case_name in cases:
		match case_name:
			"drill": await _trace_drill()
			"banner": await _trace_banner()
			"scales": await _trace_scales()
			"cancel": await _trace_cancel_during_population()
			_:
				push_error("[wayside-pickers] unknown --case=%s" % case_name)
				_finish(2)
				return
	print("[wayside-pickers] DONE")
	_finish(0)


func _prepare_run(verb: String) -> void:
	await _retire_bakers()
	_cache.clear()
	_run_state.start_new_run("raider", 0, RUN_SEED)
	_run_state.active_slot = -1
	for card_id in EXTRA_CARD_IDS:
		_run_state.add_card(card_id)
	_run_state.current_node_type = "wayside"
	_run_state.current_wayside_id = verb
	await process_frame


func _open_wayside() -> Dictionary:
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var scene = load("res://scenes/wayside.tscn").instantiate()
	var started := Time.get_ticks_usec()
	root.add_child(scene)
	var call_ms := float(Time.get_ticks_usec() - started) / 1000.0
	return {
		"scene": scene,
		"started": started,
		"call_ms": call_ms,
		"nodes_before": nodes_before,
		"objects_before": objects_before,
	}


func _trace_drill() -> void:
	await _prepare_run("drill_yard")
	var opened := _open_wayside()
	var scene: Node = opened.scene
	var expected: int = (scene.call("_drill_eligible") as Array).size()
	await _trace_population("drill_intro", scene, expected, opened)

	# Exercise the real one-pick latch and the grid -> persistent-card rebuild.
	# The first Outrider has exactly one transferable-independent identity and is
	# deterministic in the Raider opener.
	var deck_index: int = _run_state.deck.find("levy_rider")
	var card: Node = _find_card(scene, "levy_rider")
	if deck_index < 0 or card == null:
		push_error("[wayside-pickers] drill transition target missing")
	else:
		var slot := card.get_parent().get_parent() as Control
		var transition_started := Time.get_ticks_usec()
		var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var call_started := transition_started
		scene.call("_on_grid_card_pressed", slot,
			Callable(scene, "_on_drill_pick").bind(deck_index))
		var transition_call_ms := float(Time.get_ticks_usec() - call_started) / 1000.0
		await _trace_population("drill_push", scene, 1, {
			"started": transition_started,
			"call_ms": transition_call_ms,
			"nodes_before": nodes_before,
			"objects_before": objects_before,
		})
	await _close_scene(scene)


func _trace_banner() -> void:
	await _prepare_run("standard_bearer")
	var opened := _open_wayside()
	var scene: Node = opened.scene
	var expected := _valid_banner_donor_count(scene)
	await _trace_population("banner_donors", scene, expected, opened)

	# Lookout is unique in the fixed deck and carries only Swift, so selecting it
	# deterministically takes the direct donor -> receiver branch (no keyword tile
	# interstitial). Stop on the receiver slate: no deck mutation is committed.
	var donor_index: int = _run_state.deck.find("lookout")
	var donor_card: Node = _find_card(scene, "lookout")
	if donor_index < 0 or donor_card == null:
		push_error("[wayside-pickers] banner transition target missing")
	else:
		var receivers: Array = scene.call("_banner_receivers", donor_index, "swift")
		var slot := donor_card.get_parent().get_parent() as Control
		var transition_started := Time.get_ticks_usec()
		var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var call_started := transition_started
		scene.call("_on_grid_card_pressed", slot,
			Callable(scene, "_on_banner_donor_pick").bind(donor_index))
		var transition_call_ms := float(Time.get_ticks_usec() - call_started) / 1000.0
		await _trace_population("banner_receivers", scene, receivers.size(), {
			"started": transition_started,
			"call_ms": transition_call_ms,
			"nodes_before": nodes_before,
			"objects_before": objects_before,
		})
		print("[wayside-pickers] banner_state from=%d kw=%s upgrades_unchanged=%s" % [
			int(scene.get("_banner_from")), String(scene.get("_banner_kw")),
			str(_run_state.get_card_upgrades(donor_index).is_empty())])
	await _close_scene(scene)


func _trace_scales() -> void:
	await _prepare_run("muster_scale")
	var opened := _open_wayside()
	var scene: Node = opened.scene
	# The legacy stop opens on three trade tiles; only entering Sell creates the
	# deck-sized card grid, so measure that call rather than scene construction.
	for _i in 3:
		await RenderingServer.frame_post_draw
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var started := Time.get_ticks_usec()
	scene.call("_build_scales_sell")
	var call_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await _trace_population("scales_sell", scene, _run_state.deck.size(), {
		"started": started,
		"call_ms": call_ms,
		"nodes_before": nodes_before,
		"objects_before": objects_before,
	})
	await _close_scene(scene)


func _trace_cancel_during_population() -> void:
	await _prepare_run("muster_scale")
	var scene: Node = _open_wayside().scene
	for _i in 3:
		await RenderingServer.frame_post_draw
	_cache.clear()
	# Start the async sell build, allow one presented frame, then take its Cancel
	# destination directly. A generation guard must prevent the suspended builder
	# from appending stale cards into the retired grid afterwards.
	scene.call("_build_scales_sell")
	await RenderingServer.frame_post_draw
	scene.call("_build_scales")
	var max_stale_cards := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 1500:
		await RenderingServer.frame_post_draw
		max_stale_cards = maxi(max_stale_cards, _card_nodes(scene).size())
	print("[wayside-pickers] cancel_guard max_stale_cards=%d final_cards=%d pick_taken=%s pending=%s" % [
		max_stale_cards, _card_nodes(scene).size(), str(scene.get("_grid_pick_taken")),
		str(scene.get("_grid_pick_pending"))])
	await _close_scene(scene)


func _trace_population(label: String, scene: Node, expected: int,
		opened: Dictionary) -> void:
	var gaps: Array[float] = []
	var progression: Array[int] = []
	var last_count := -1
	var previous := Time.get_ticks_usec()
	var stable := 0
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(scene):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		gaps.append(float(now - previous) / 1000.0)
		previous = now
		var count := _card_nodes(scene).size()
		if count != last_count:
			progression.append(count)
			last_count = count
		if count == expected:
			stable += 1
			if stable >= SETTLE_FRAMES:
				break
		else:
			stable = 0
	var elapsed_ms := float(Time.get_ticks_usec() - int(opened.started)) / 1000.0
	var cards := _card_nodes(scene)
	var baked_faces := 0
	var gallery_mode := 0
	var gallery_hits := 0
	var gameplay_hits := 0
	var seen := {}
	for card in cards:
		if card.get("_baked_face") != null:
			baked_faces += 1
		if bool(card.get("gallery_baked_mode")):
			gallery_mode += 1
		var data: Dictionary = card.get("card_data")
		var key: String = _cache.cache_key(data)
		if seen.has(key):
			continue
		seen[key] = true
		if _cache.has_gallery(data):
			gallery_hits += 1
		if _cache.has(data):
			gameplay_hits += 1
	print("[wayside-pickers] %s expected=%d call=%.2fms populate=%.2fms frames=%d max_gap=%.2fms p95=%.2fms progression=%s" % [
		label, expected, float(opened.call_ms), elapsed_ms, gaps.size(),
		_maximum(gaps), _percentile(gaps, 0.95), str(progression)])
	print("[wayside-pickers] %s cards=%d baked_faces=%d gallery_mode=%d unique=%d gallery_hits=%d gameplay_hits=%d nodes=%+d objects=%+d busy=%s" % [
		label, cards.size(), baked_faces, gallery_mode, seen.size(), gallery_hits,
		gameplay_hits,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - int(opened.nodes_before),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)) - int(opened.objects_before),
		str(_cache.get("_bake_busy"))])


func _valid_banner_donor_count(scene: Node) -> int:
	var count := 0
	var donors: Array = scene.call("_banner_donors")
	for donor_index in donors:
		var data: Dictionary = _run_state.get_upgraded_card_data(int(donor_index))
		var keywords: Array = scene.call("_transferable_of", data)
		for keyword in keywords:
			var receivers: Array = scene.call(
				"_banner_receivers", int(donor_index), String(keyword))
			if not receivers.is_empty():
				count += 1
				break
	return count


func _find_card(host: Node, card_id: String):
	for card in _card_nodes(host):
		var data: Dictionary = card.get("card_data")
		if String(data.get("id", "")) == card_id:
			return card
	return null


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _close_scene(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	for _i in 4:
		await process_frame
	await _retire_bakers()


func _retire_bakers() -> void:
	if _cache == null:
		return
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var quiet_frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if bool(_cache.get("_bake_busy")):
			quiet_frames = 0
		else:
			quiet_frames += 1
			if quiet_frames >= 6:
				return


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	if preload_service == null:
		return
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = not preload_service.has_method("is_warmup_complete") \
			or bool(preload_service.is_warmup_complete())
		var cards_done: bool = bool(preload_service.get("_prewarmed")) \
			and not bool(_cache.get("_bake_busy"))
		if resources_done and cards_done:
			break
		await create_timer(0.10).timeout
	# No visual scene is parented yet, so a frame_post_draw signal is not
	# guaranteed. Process frames here; picker measurements use presented frames
	# after their Wayside scene has entered the tree.
	for _i in 4:
		await process_frame


func _arg_value(prefix: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(sorted.size() * fraction)) - 1, 0,
		sorted.size() - 1)]


func _finish(code: int) -> void:
	_done = true
	quit(code)
