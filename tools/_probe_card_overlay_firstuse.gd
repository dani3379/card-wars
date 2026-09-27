extends SceneTree
## Measures the first visible baked-overlay Card2D after its texture bake is warm.

var _started := false
var _done := false
var _recording := false
var _last_usec := 0
var _max_gap := 0.0


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _recording and _last_usec > 0:
		_max_gap = maxf(_max_gap, float(now - _last_usec) / 1000.0)
	_last_usec = now
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _wait_for_session_warmup()
	var variant := "normal"
	var card_id := "grave_goods"
	var warm_overlay_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="):
			variant = arg.trim_prefix("--variant=")
		elif arg.begins_with("--card="):
			card_id = arg.trim_prefix("--card=")
		elif arg.begins_with("--warm-overlay="):
			warm_overlay_id = arg.trim_prefix("--warm-overlay=")
	if warm_overlay_id != "":
		await _warm_overlay(warm_overlay_id)
	var data: Dictionary = root.get_node("CardDB").get_card_data(card_id)
	await CardArtAliases.prewarm_card_art(data)
	await root.get_node("CardTextureCache").bake(data)
	for _i in 3:
		await RenderingServer.frame_post_draw
	var shown := data.duplicate(true)
	match variant:
		"no_desc":
			shown["desc"] = ""
		"short_desc":
			shown["desc"] = "On-Death."
		"no_footer":
			shown["ctype"] = ""
		"bare_text":
			shown["desc"] = ""
			shown["name"] = ""
			shown["ctype"] = ""
	_recording = true
	_last_usec = Time.get_ticks_usec()
	var started := _last_usec
	_max_gap = 0.0
	var card = _make_overlay_card(shown)
	root.add_child(card)
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	for _i in 5:
		await RenderingServer.frame_post_draw
	_recording = false
	print("[overlay-first] card=%s warm=%s variant=%s sync=%.2fms max_gap=%.2fms controls=%d" % [
		card_id, warm_overlay_id, variant, sync_ms, _max_gap,
		_count_controls(card)])
	card.queue_free()
	for _i in 2:
		await process_frame
	_done = true
	quit(0)


func _count_controls(host: Node) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Control:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count

func _make_overlay_card(data: Dictionary) -> Node:
	var card = load("res://scenes/card_2d.tscn").instantiate()
	card.card_data = data
	card.card_id = String(data.get("id", ""))
	card.is_on_battlefield = true
	card.live_baked_mode = true
	return card


func _warm_overlay(card_id: String) -> void:
	var data: Dictionary = root.get_node("CardDB").get_card_data(card_id)
	if data.is_empty():
		return
	await CardArtAliases.prewarm_card_art(data)
	var warm_viewport := SubViewport.new()
	warm_viewport.size = Vector2i(249, 324)
	warm_viewport.transparent_bg = true
	warm_viewport.disable_3d = true
	warm_viewport.gui_disable_input = true
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(warm_viewport)
	await root.get_node("CardTextureCache").bake(data)
	var parts: Array[Dictionary] = [
		{"desc": "On-Death."},
		{"desc": "A friendly creature."},
		{"desc": "Gains +2/+2 this fight."},
		{"desc": "Exhaust. Curse. Guardian."},
		{"desc": "Sphinx of black quartz."},
		{"desc": "Judge my vow. 0123456789"},
		{"name": "Hexwright"},
		{"name": "Black Quartz Vow"},
		{"name": "Sphinx of Black Quartz"},
		{"ctype": "warlock"},
	]
	for part_i in range(parts.size()):
		var part: Dictionary = parts[part_i]
		_recording = true
		_max_gap = 0.0
		_last_usec = Time.get_ticks_usec()
		var started := _last_usec
		var warm_data := data.duplicate(true)
		warm_data["name"] = String(part.get("name", ""))
		warm_data["ctype"] = String(part.get("ctype", ""))
		warm_data["desc"] = String(part.get("desc", ""))
		var card := _make_overlay_card(warm_data)
		warm_viewport.add_child(card)
		var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
		for _i in 3:
			await RenderingServer.frame_post_draw
		_recording = false
		print("[overlay-warm] part=%d sync=%.2fms max_gap=%.2fms" % [
			part_i, sync_ms, _max_gap])
		card.queue_free()
		for _i in 2:
			await process_frame
	warm_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	warm_viewport.queue_free()
	await process_frame


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
