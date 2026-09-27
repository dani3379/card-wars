extends SceneTree
## Diagnostic: captures one cache-owned compact background for pixel A/B checks.

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var preload_service := root.get_node_or_null("ScenePreload")
	var cache := root.get_node("CardTextureCache")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = preload_service == null \
			or bool(preload_service.is_warmup_complete())
		var pipeline_done: bool = preload_service == null \
			or bool(preload_service.get("_prewarmed"))
		if resources_done and pipeline_done and not bool(cache.get("_bake_busy")):
			break
		await create_timer(0.10).timeout

	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260903)
	rs.active_slot = -1
	var data: Dictionary = rs.get_upgraded_card_data(0)
	await CardArtAliases.prewarm_card_art(data)
	var started := Time.get_ticks_usec()
	await cache.bake_battlefield_many([data])
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	var tex: Texture2D = cache.get_battlefield_texture(data)
	if tex == null:
		push_error("battlefield bake produced no texture")
		quit(1)
		return
	var err := tex.get_image().save_png("res://_shot_bfield_bake.png")
	print("[bfield-pixels] saved=%s bake=%.2fms size=%s" % [
		str(err == OK), elapsed, str(tex.get_size())])
	_done = true
	quit(0)
