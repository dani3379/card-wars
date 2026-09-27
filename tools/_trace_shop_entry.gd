extends SceneTree
## Windowed phase trace for Shop's asynchronous _ready path.

var _started := false
var _done := false
var _scene: Node = null
var _last_usec := 0
var _open_usec := 0
var _last_signature := ""
var _max_gap_ms := 0.0
var _all_cards_usec := 0
var _warmup_started_usec := 0
var _warmup_max_gap_ms := 0.0


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _open_usec > 0 and _scene != null and is_instance_valid(_scene):
		var ids: Array = _scene.get("_card_stock")
		var hits := 0
		var gallery_hits := 0
		for id in ids:
			var data: Dictionary = root.get_node("CardDB").get_card_data(String(id))
			if root.get_node("CardTextureCache").has(data):
				hits += 1
			if root.get_node("CardTextureCache").has_gallery(data):
				gallery_hits += 1
		var cards := _count_script_nodes(_scene, "Card2D.gd")
		var busy := bool(root.get_node("CardTextureCache").get("_bake_busy"))
		var sig := "game=%d gallery=%d/%d|cards=%d|busy=%s" % [
			hits, gallery_hits, ids.size(), cards, str(busy)]
		if sig != _last_signature:
			print("[shop-entry] t=%.2fms %s ids=%s" % [
				float(now - _open_usec) / 1000.0, sig, str(ids)])
			_last_signature = sig
		if cards == ids.size() and _all_cards_usec == 0:
			_all_cards_usec = now
	if _last_usec > 0 and _open_usec > 0:
		var gap := float(now - _last_usec) / 1000.0
		_max_gap_ms = maxf(_max_gap_ms, gap)
		if gap >= 20.0:
			print("[shop-entry] GAP %.2fms at t=%.2fms state=%s" % [
				gap, float(now - _open_usec) / 1000.0, _last_signature])
	elif _started and _warmup_started_usec > 0 and _last_usec > 0:
		_warmup_max_gap_ms = maxf(_warmup_max_gap_ms,
			float(now - _last_usec) / 1000.0)
	_last_usec = now
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = true
	settings.reduce_motion = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_warmup_started_usec = Time.get_ticks_usec()
	await process_frame
	await _wait_for_session_warmup()
	print("[shop-entry] WARMUP total=%.2fms max_gap=%.2fms" % [
		float(Time.get_ticks_usec() - _warmup_started_usec) / 1000.0,
		_warmup_max_gap_ms])
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260903)
	rs.active_slot = -1
	rs.gold = 214
	await process_frame
	# Keep Shop stock identical across before/after renderer experiments.
	seed(20260903)
	_open_usec = Time.get_ticks_usec()
	_last_usec = _open_usec
	_scene = load("res://scenes/shop.tscn").instantiate()
	root.add_child(_scene)
	await create_timer(5.0).timeout
	var all_cards_ms := -1.0
	if _all_cards_usec > 0:
		all_cards_ms = float(_all_cards_usec - _open_usec) / 1000.0
	print("[shop-entry] DONE all_cards=%.2fms max_gap=%.2fms" % [
		all_cards_ms, _max_gap_ms])
	_scene.queue_free()
	for _i in 4:
		await process_frame
	_done = true
	quit(0)


func _count_script_nodes(host: Node, script_name: String) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).get_file() == script_name:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node("ScenePreload")
	var cache := root.get_node("CardTextureCache")
	var card_db := root.get_node("CardDB")
	var creature: Dictionary = {}
	var spell: Dictionary = {}
	for id in card_db.CARD_POOL:
		var card: Dictionary = card_db.CARD_POOL[id]
		if creature.is_empty() and card.get("type", "") == "creature":
			creature = card_db.get_card_data(id)
		elif spell.is_empty() and card.get("type", "") == "spell":
			spell = card_db.get_card_data(id)
		if not creature.is_empty() and not spell.is_empty():
			break
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = bool(preload_service.is_warmup_complete())
		var cards_done: bool = bool(preload_service.get("_prewarmed")) \
			and cache.has(creature) and cache.has_battlefield(creature) \
			and cache.has(spell) and not bool(cache.get("_bake_busy"))
		if resources_done and cards_done:
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw
