extends SceneTree
## Windowed cold-entry trace for GameTheme.show_deck_picker. Builds a realistic
## 20-card run deck, clears only the card texture cache, opens the real modal,
## and records synchronous call time plus presented-frame gaps until every card
## is visibly revealed. It also proves the reserved grid never moves while the
## hidden faces hydrate. The modal is then dismissed without changing the run.
##
## Run windowed and serially:
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \\
##       --script res://tools/_trace_deck_picker_entry.gd
## Parse/autoload smoke only:
##   ... --headless --script res://tools/_trace_deck_picker_entry.gd -- --check-only

const TARGET_DECK_SIZE := 20
const DEADLINE_MS := 20000

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[deck-picker-trace] CHECK_ONLY_OK")
		_done = true
		quit(0)
		return
	var settings = root.get_node_or_null("UserSettings")
	var run_state = root.get_node_or_null("RunState")
	var card_db = root.get_node_or_null("CardDB")
	var cache = root.get_node_or_null("CardTextureCache")
	var preload_service = root.get_node_or_null("ScenePreload")
	var theme = root.get_node_or_null("GameTheme")
	if settings == null or run_state == null or card_db == null or cache == null \
			or theme == null:
		push_error("[deck-picker-trace] required autoload missing")
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
	var supersample = root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_warmup(preload_service)

	run_state.start_new_run("raider", 0, 20260903)
	run_state.active_slot = -1
	var existing := {}
	for id in run_state.deck:
		existing[String(id)] = true
	for id_variant in card_db.CARD_POOL.keys():
		if run_state.deck.size() >= TARGET_DECK_SIZE:
			break
		var id := String(id_variant)
		var data: Dictionary = card_db.get_card_data(id)
		if existing.has(id) or data.is_empty():
			continue
		if String(data.get("rarity", "")) in ["enemy", "token"] \
				or card_db.is_curse(id):
			continue
		run_state.add_card(id)
		existing[id] = true
	cache.clear()

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	for _i in 3:
		await RenderingServer.frame_post_draw
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var call_started := Time.get_ticks_usec()
	theme.show_deck_picker(host, "TRACE — CHOOSE A CARD", "", true)
	var call_ms := float(Time.get_ticks_usec() - call_started) / 1000.0
	var previous := Time.get_ticks_usec()
	var opened_at := previous
	var gaps: Array[float] = []
	var card_counts: Array[int] = []
	var visible_counts: Array[int] = []
	var reserved_positions: Array[Vector2] = []
	var max_slot_shift := 0.0
	var stable := 0
	while Time.get_ticks_msec() - int(opened_at / 1000) < DEADLINE_MS:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		gaps.append(float(now - previous) / 1000.0)
		previous = now
		var trace_host: Node = _find_picker_layer(root)
		if trace_host == null:
			trace_host = root
		var count := _count_card_nodes(trace_host)
		var visible_count := _count_visible_card_nodes(trace_host)
		card_counts.append(count)
		visible_counts.append(visible_count)
		var slots := _picker_slots(trace_host)
		if reserved_positions.is_empty() and slots.size() == run_state.deck.size():
			for slot in slots:
				reserved_positions.append(slot.global_position)
		elif slots.size() == reserved_positions.size():
			for i in slots.size():
				max_slot_shift = maxf(max_slot_shift,
					slots[i].global_position.distance_to(reserved_positions[i]))
		if visible_count >= run_state.deck.size():
			stable += 1
			if stable >= 4:
				break
		else:
			stable = 0

	var modal := _find_picker_layer(root)
	var populated_ms := float(Time.get_ticks_usec() - opened_at) / 1000.0
	print("[deck-picker-trace] deck=%d call=%.2fms populate=%.2fms frames=%d max_gap=%.2fms p95=%.2fms final_cards=%d" % [
		run_state.deck.size(), call_ms, populated_ms, gaps.size(), _maximum(gaps),
		_percentile(gaps, 0.95), _count_card_nodes(root)])
	print(("[deck-picker-trace] nodes=%+d objects=%+d node_progression=%s "
		+ "visible_progression=%s max_slot_shift=%.3fpx") % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before,
		str(_compact_progression(card_counts)),
		str(_compact_progression(visible_counts)), max_slot_shift])
	if modal != null:
		modal.queue_free()
	for _i in 5:
		await process_frame
	var cache_deadline := Time.get_ticks_msec() + DEADLINE_MS
	while bool(cache.get("_bake_busy")) and Time.get_ticks_msec() < cache_deadline:
		await process_frame
	host.queue_free()
	for _i in 4:
		await process_frame
	_finish(0)


func _wait_for_warmup(service) -> void:
	if service == null:
		return
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		if (not service.has_method("is_warmup_complete") \
				or bool(service.is_warmup_complete())) and bool(service.get("_prewarmed")):
			return
		await create_timer(0.1).timeout


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _count_card_nodes(host: Node) -> int:
	var count := 0
	for node in _walk(host):
		var script = node.get_script()
		if script != null and String(script.resource_path).ends_with("/Card2D.gd"):
			count += 1
	return count



func _count_visible_card_nodes(host: Node) -> int:
	var count := 0
	for node in _walk(host):
		var script = node.get_script()
		if script != null and String(script.resource_path).ends_with("/Card2D.gd") \
				and node.visible and node.modulate.a > 0.99:
			count += 1
	return count


func _picker_slots(host: Node) -> Array[Control]:
	var slots: Array[Control] = []
	for node in _walk(host):
		if node is Control \
				and (node as Control).custom_minimum_size == Vector2(220, 300):
			slots.append(node as Control)
	slots.sort_custom(func(a: Control, b: Control) -> bool:
		if not is_equal_approx(a.global_position.y, b.global_position.y):
			return a.global_position.y < b.global_position.y
		return a.global_position.x < b.global_position.x)
	return slots

func _find_picker_layer(host: Node) -> CanvasLayer:
	for node in _walk(host):
		if node is CanvasLayer and (node as CanvasLayer).layer == 1000:
			return node as CanvasLayer
	return null


func _compact_progression(values: Array[int]) -> Array[int]:
	var out: Array[int] = []
	var last := -1
	for value in values:
		if value != last:
			out.append(value)
			last = value
	return out


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
	return sorted[clampi(int(ceil(sorted.size() * fraction)) - 1, 0, sorted.size() - 1)]


func _finish(code: int) -> void:
	_done = true
	quit(code)
