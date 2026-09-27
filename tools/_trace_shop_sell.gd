extends SceneTree
## Focused, deterministic windowed trace for the Shop sutler's real sell-card
## picker. It enters through the visible "Sell a Card" button signal, never
## confirms a sale, and compares a deliberately cold cache with a warm reopen.
##
## The trace reports:
##   - synchronous button callback time (the user-visible click hitch),
##   - presented-frame gaps while the grid/cache settle,
##   - sell-grid Card2D count and whether each card took the baked or full-live
##     layout path,
##   - gameplay/gallery cache coverage for unique deck faces,
##   - retained Control/node/object and canvas draw costs.
##
## Run WINDOWED and serially (never alongside another windowed benchmark):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" ^
##       --script res://tools/_trace_shop_sell.gd
## Parse/autoload smoke only:
##   Godot_v4.6.2-stable_win64_console.exe --headless --path "D:\\Godot" ^
##       --script res://tools/_trace_shop_sell.gd -- --check-only

const RUN_SEED := 20260909
const TARGET_DECK_SIZE := 24
const DEADLINE_MS := 30000
const STABLE_FRAMES := 4

var _started := false
var _done := false
var _scene: Node = null
var _unique_datas: Array[Dictionary] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[shop-sell] CHECK_ONLY_OK target_deck=%d" % TARGET_DECK_SIZE)
		_finish(0)
		return

	var settings := root.get_node_or_null("UserSettings")
	var run_state := root.get_node_or_null("RunState")
	var card_db := root.get_node_or_null("CardDB")
	var cache := root.get_node_or_null("CardTextureCache")
	if settings == null or run_state == null or card_db == null or cache == null:
		push_error("[shop-sell] required autoload missing")
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

	# Never claim or write a save slot. The unique additions make the cold path
	# representative of a late-run deck while keeping the medium LRU below its
	# 32-entry cap even when the four shop wares are rebuilt between passes.
	run_state.active_slot = -1
	run_state.start_new_run("raider", 0, RUN_SEED)
	run_state.active_slot = -1
	run_state.current_node_type = "shop"
	run_state.gold = 214
	_pad_deck(run_state, card_db)
	_unique_datas = _unique_deck_faces(run_state, cache)

	_scene = load("res://scenes/shop.tscn").instantiate()
	root.add_child(_scene)
	if not await _wait_for_shop_ready(cache):
		push_error("[shop-sell] Shop did not finish its real _ready path")
		await _cleanup()
		_finish(1)
		return
	_stop_audio()
	for _i in 4:
		await RenderingServer.frame_post_draw

	print("[shop-sell] BEGIN deck=%d unique_faces=%d cache_limit=%d" % [
		run_state.deck.size(), _unique_datas.size(), cache.gameplay_cache_limit()])
	cache.clear()
	for _i in 3:
		await RenderingServer.frame_post_draw
	var cold := await _open_and_trace("cold", run_state, cache)
	if cold.is_empty():
		await _cleanup()
		_finish(1)
		return

	if not await _cancel_sell_mode(cache):
		push_error("[shop-sell] could not return from cold sell grid")
		await _cleanup()
		_finish(1)
		return
	var warm := await _open_and_trace("warm", run_state, cache)
	if warm.is_empty():
		await _cleanup()
		_finish(1)
		return

	print("[shop-sell] DELTA click=%.2fms max_gap=%.2fms controls=%+d draws=%+d" % [
		float(cold.click_ms) - float(warm.click_ms),
		float(cold.max_gap_ms) - float(warm.max_gap_ms),
		int(cold.controls) - int(warm.controls),
		int(cold.draws) - int(warm.draws)])
	print("[shop-sell] DONE deck_unchanged=%s" % str(
		run_state.deck.size() == TARGET_DECK_SIZE))
	await _cancel_sell_mode(cache)
	await _cleanup()
	_finish(0)


func _pad_deck(run_state: Node, card_db: Node) -> void:
	var existing := {}
	for id_variant in run_state.deck:
		existing[String(id_variant)] = true
	var ids: Array = card_db.CARD_POOL.keys()
	ids.sort()
	for id_variant in ids:
		if run_state.deck.size() >= TARGET_DECK_SIZE:
			break
		var id := String(id_variant)
		var data: Dictionary = card_db.get_card_data(id)
		var rarity := String(data.get("rarity", ""))
		if existing.has(id) or data.is_empty() or rarity in ["enemy", "token"] \
				or card_db.is_curse(id):
			continue
		run_state.add_card(id)
		existing[id] = true


func _unique_deck_faces(run_state: Node, cache: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for i in range(run_state.deck.size()):
		var data: Dictionary = run_state.get_upgraded_card_data(i)
		var key := String(cache.cache_key(data))
		if seen.has(key):
			continue
		seen[key] = true
		result.append(data)
	return result


func _open_and_trace(label: String, run_state: Node, cache: Node) -> Dictionary:
	var button := _find_button_named(_scene, "Sell a Card")
	if button == null:
		push_error("[shop-sell] %s: visible Sell a Card button not found" % label)
		return {}
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var memory_before := OS.get_static_memory_usage()
	var opened_usec := Time.get_ticks_usec()
	var previous_usec := opened_usec
	# This is the same signal connection a player's click invokes; calling the
	# private method directly could miss future button-level wiring.
	button.emit_signal("pressed")
	var click_ms := float(Time.get_ticks_usec() - opened_usec) / 1000.0
	var gaps: Array[float] = []
	var progression: Array[String] = []
	var last_signature := ""
	var stable := 0
	var timed_out := false
	while Time.get_ticks_msec() - int(opened_usec / 1000) < DEADLINE_MS:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var gap := float(now - previous_usec) / 1000.0
		previous_usec = now
		gaps.append(gap)
		var stats := _sell_grid_stats()
		var hits := _cache_stats(cache)
		var signature := "cards=%d baked=%d live=%d controls=%d gp=%d gal=%d any=%d/%d busy=%s" % [
			stats.cards, stats.baked, stats.live, stats.controls,
			hits.gameplay, hits.gallery, hits.any, _unique_datas.size(),
			str(bool(cache.get("_bake_busy")))]
		if signature != last_signature:
			progression.append(signature)
		if signature != last_signature or gap >= 16.0:
			print("[shop-sell] %s t=%.2fms gap=%.2fms %s" % [
				label, float(now - opened_usec) / 1000.0, gap, signature])
			last_signature = signature
		var complete: bool = int(stats.cards) == run_state.deck.size() \
			and int(hits.any) == _unique_datas.size() \
			and not bool(cache.get("_bake_busy"))
		stable = stable + 1 if complete else 0
		if stable >= STABLE_FRAMES:
			break
	if stable < STABLE_FRAMES:
		timed_out = true

	var final_stats := _sell_grid_stats()
	var final_hits := _cache_stats(cache)
	var viewport_rid := root.get_viewport_rid()
	var result := {
		"click_ms": click_ms,
		"settle_ms": float(Time.get_ticks_usec() - opened_usec) / 1000.0,
		"max_gap_ms": _maximum(gaps),
		"p95_ms": _percentile(gaps, 0.95),
		"cards": int(final_stats.cards),
		"baked": int(final_stats.baked),
		"live": int(final_stats.live),
		"controls": int(final_stats.controls),
		"gameplay_hits": int(final_hits.gameplay),
		"gallery_hits": int(final_hits.gallery),
		"draws": int(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)),
		"canvas_objects": int(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)),
		"primitives": int(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)),
	}
	print("[shop-sell] %s SUMMARY click=%.2fms settle=%.2fms max_gap=%.2fms p95=%.2fms timed_out=%s" % [
		label, result.click_ms, result.settle_ms, result.max_gap_ms,
		result.p95_ms, str(timed_out)])
	print("[shop-sell] %s RETAINED cards=%d baked=%d live=%d controls=%d nodes=%+d objects=%+d memory=%+.1fMiB" % [
		label, result.cards, result.baked, result.live, result.controls,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before,
		float(OS.get_static_memory_usage() - memory_before) / 1048576.0])
	print("[shop-sell] %s CANVAS draws=%d objects=%d primitives=%d cache gameplay=%d gallery=%d" % [
		label, result.draws, result.canvas_objects, result.primitives,
		result.gameplay_hits, result.gallery_hits])
	print("[shop-sell] %s PROGRESSION %s" % [label, str(progression)])
	return result


func _cancel_sell_mode(cache: Node) -> bool:
	if _scene == null or not is_instance_valid(_scene):
		return false
	var cancel := _find_button_named(_scene, "Cancel")
	if cancel == null:
		return false
	cancel.emit_signal("pressed")
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if _find_button_named(_scene, "Sell a Card") != null \
				and not bool(cache.get("_bake_busy")):
			for _i in 4:
				await RenderingServer.frame_post_draw
			return true
	return false


func _wait_for_shop_ready(cache: Node) -> bool:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if _scene != null and is_instance_valid(_scene) \
				and bool(_scene.get("_entered")) \
				and _find_button_named(_scene, "Sell a Card") != null \
				and not bool(cache.get("_bake_busy")):
			return true
	return false


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var cache := root.get_node_or_null("CardTextureCache")
	if preload_service == null or cache == null:
		return
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = not preload_service.has_method("is_warmup_complete") \
			or bool(preload_service.is_warmup_complete())
		if resources_done and bool(preload_service.get("_prewarmed")) \
				and not bool(cache.get("_bake_busy")):
			break
		await create_timer(0.1).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw


func _cache_stats(cache: Node) -> Dictionary:
	var gameplay := 0
	var gallery := 0
	var any := 0
	for data in _unique_datas:
		var has_gameplay := bool(cache.has(data))
		var has_gallery := bool(cache.has_gallery(data))
		gameplay += 1 if has_gameplay else 0
		gallery += 1 if has_gallery else 0
		any += 1 if has_gameplay or has_gallery else 0
	return {"gameplay": gameplay, "gallery": gallery, "any": any}


func _sell_grid_stats() -> Dictionary:
	var cards := 0
	var baked := 0
	var controls := 0
	if _scene == null or not is_instance_valid(_scene):
		return {"cards": 0, "baked": 0, "live": 0, "controls": 0}
	var slots: Array = _scene.get("_removal_card_nodes")
	for slot_variant in slots:
		if not (slot_variant is Node) or not is_instance_valid(slot_variant):
			continue
		for node in _walk(slot_variant as Node):
			if node is Control:
				controls += 1
			var script = node.get_script()
			if script != null and String(script.resource_path).ends_with("/Card2D.gd"):
				cards += 1
				var face = node.get("_baked_face")
				if face != null and is_instance_valid(face):
					baked += 1
	return {"cards": cards, "baked": baked, "live": cards - baked,
		"controls": controls}


func _find_button_named(host: Node, wanted: String) -> Button:
	if host == null or not is_instance_valid(host):
		return null
	for node in _walk(host):
		if not (node is Button):
			continue
		var button := node as Button
		if button.text.strip_edges().nocasecmp_to(wanted) == 0:
			return button
		for child in _walk(button):
			if child is Label and (child as Label).text.strip_edges().nocasecmp_to(wanted) == 0:
				return button
	return null


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _stop_audio() -> void:
	var audio := root.get_node_or_null("AudioBank")
	if audio == null:
		return
	if audio.has_method("stop_music"):
		audio.stop_music()
	if audio.has_method("stop_ambience"):
		audio.stop_ambience()


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
	return sorted[clampi(int(ceil(sorted.size() * fraction)) - 1,
		0, sorted.size() - 1)]


func _cleanup() -> void:
	_stop_audio()
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	for _i in 5:
		await process_frame
	_scene = null


func _finish(code: int) -> void:
	_done = true
	quit(code)
