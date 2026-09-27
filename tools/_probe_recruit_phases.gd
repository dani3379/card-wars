extends SceneTree
## Windowed micro-profile for Recruit's three-card cold path. It separates art
## prewarm from each gameplay-card bake and reports the largest main-loop gap
## incurred by each phase.

const OFFER: Array[String] = ["pikeman", "shield_wall", "pillage"]

var _started := false
var _done := false
var _phase := "idle"
var _last_usec := 0
var _phase_max_gap_ms := 0.0


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_phase_max_gap_ms = maxf(_phase_max_gap_ms,
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
	settings.reduce_motion = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await _wait_for_session_warmup()
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260903)
	rs.active_slot = -1
	await process_frame

	for id in OFFER:
		var data: Dictionary = root.get_node("CardDB").get_card_data(id)
		await _measure("art:%s" % id,
			func(): await CardArtAliases.prewarm_card_art(data))
	for id in OFFER:
		var data: Dictionary = root.get_node("CardDB").get_card_data(id)
		await _measure("bake:%s" % id,
			func(): await root.get_node("CardTextureCache").bake(data))

	_done = true
	quit(0)


func _measure(name: String, action: Callable) -> void:
	_phase = name
	_phase_max_gap_ms = 0.0
	_last_usec = Time.get_ticks_usec()
	var started := _last_usec
	await action.call()
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	print("[recruit-phase] %-20s wall=%7.2fms max_loop_gap=%7.2fms" % [
		name, elapsed, _phase_max_gap_ms])
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
