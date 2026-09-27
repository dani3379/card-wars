extends SceneTree
## Windowed cold-map timeline. Attributes each process-frame gap to generation,
## geography bake/readback, march bake/readback, or settled presentation.

const RUN_SEED := 20260903

var _started := false
var _done := false
var _recording := false
var _previous_usec := 0
var _previous_stage := "boot"
var _scene: Node = null
var _started_usec := 0
var _max_by_stage := {}


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _recording and _previous_usec > 0:
		var stage := _stage()
		var gap_ms := float(now - _previous_usec) / 1000.0
		var key := "%s -> %s" % [_previous_stage, stage]
		_max_by_stage[key] = maxf(float(_max_by_stage.get(key, 0.0)), gap_ms)
		if gap_ms >= 8.0 or stage != _previous_stage:
			print("[map-trace] t=%7.1fms gap=%7.2fms %s draws=%d" % [
				float(now - _started_usec) / 1000.0, gap_ms, key,
				RenderingServer.viewport_get_render_info(root.get_viewport_rid(),
					RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
					RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
		_previous_stage = stage
	_previous_usec = now
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await _wait_for_session_warmup()
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.current_node_type = ""
	rs.current_encounter_id = ""
	rs.map_plate_cache.clear()
	_scene = load("res://scenes/map.tscn").instantiate()
	_previous_stage = "before_add"
	_previous_usec = Time.get_ticks_usec()
	_started_usec = _previous_usec
	_recording = true
	root.add_child(_scene)
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline and _stage() != "settled":
		await process_frame
	for _i in 30:
		await process_frame
	_recording = false
	print("[map-trace] maxima %s" % str(_max_by_stage))
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	for _i in 5:
		await process_frame
	_done = true
	quit(0)


func _stage() -> String:
	if _scene == null or not is_instance_valid(_scene):
		return "before_add"
	if not bool(_scene.get("_map_data_ready")):
		return "generation"
	if _scene.get("_geo_tex") == null:
		return "geo_bake"
	if _scene.get("_march_tex") == null:
		return "march_bake"
	return "settled"


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
