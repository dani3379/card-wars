extends SceneTree
## Identifies Shop's deterministic offer and profiles its exact card identities.

var _started := false
var _done := false
var _recording := false
var _previous_usec := 0
var _gaps: Array[float] = []


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _recording and _previous_usec > 0:
		_gaps.append(float(now - _previous_usec) / 1000.0)
	_previous_usec = now
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var rs := root.get_node("RunState")
	var cache := root.get_node("CardTextureCache")
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	rs.active_slot = -1
	rs.start_new_run("raider", 0, 20260903)
	rs.active_slot = -1
	await process_frame
	await _wait_idle(cache)

	var shop: Node = load("res://scenes/shop.tscn").instantiate()
	shop.call("_roll_stock")
	var ids: Array = shop.get("_card_stock")
	shop.free()
	var datas: Array = []
	_gaps.clear()
	_previous_usec = Time.get_ticks_usec()
	_recording = true
	var art_started := Time.get_ticks_usec()
	for id in ids:
		var data: Dictionary = root.get_node("CardDB").get_card_data(String(id))
		datas.append(data)
		var one_art_started := Time.get_ticks_usec()
		await CardArtAliases.prewarm_card_art(data)
		print("[shop-warm]     art %s %.2fms" % [String(id),
			float(Time.get_ticks_usec() - one_art_started) / 1000.0])
	for _i in 4:
		await RenderingServer.frame_post_draw
	_recording = false
	var art_s := _stats(_gaps)
	print("[shop-warm] art_total=%.2fms frames=%d p95=%.2f max=%.2f" % [
		float(Time.get_ticks_usec() - art_started) / 1000.0,
		_gaps.size(), art_s.p95, art_s.max])
	print("[shop-warm] ids=%s" % str(ids))
	for data in datas:
		print("[shop-warm]   %s type=%s rarity=%s keywords=%s" % [
			String(data.get("id", "")), String(data.get("type", "")),
			String(data.get("rarity", "")), str(data.get("keywords", []))])

	await _strategy("one_sheet", cache, datas, 4)
	await _strategy("pairs", cache, datas, 2)
	await _strategy("singles", cache, datas, 1)
	_done = true
	quit(0)


func _strategy(label: String, cache: Node, datas: Array, chunk: int) -> void:
	await _wait_idle(cache)
	cache.clear()
	for _i in 5:
		await RenderingServer.frame_post_draw
	_gaps.clear()
	_previous_usec = Time.get_ticks_usec()
	_recording = true
	var started := Time.get_ticks_usec()
	if chunk == 1:
		for data in datas:
			var one_started := Time.get_ticks_usec()
			await cache.bake(data)
			print("[shop-warm]     single %s %.2fms" % [
				String(data.get("id", "")),
				float(Time.get_ticks_usec() - one_started) / 1000.0])
	else:
		var i := 0
		while i < datas.size():
			await cache.bake_many(datas.slice(i, mini(i + chunk, datas.size())))
			i += chunk
	var total := float(Time.get_ticks_usec() - started) / 1000.0
	for _i in 5:
		await RenderingServer.frame_post_draw
	_recording = false
	var s := _stats(_gaps)
	print("[shop-warm] %s total=%.2fms frames=%d p95=%.2f max=%.2f" % [
		label, total, _gaps.size(), s.p95, s.max])


func _wait_idle(cache: Node) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while bool(cache.get("_bake_busy")) and Time.get_ticks_msec() < deadline:
		await process_frame


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"p95": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	return {
		"p95": sorted[clampi(int(ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)],
		"max": sorted[-1],
	}
