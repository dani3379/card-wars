extends SceneTree
## Windowed A/B for short gameplay-card warm lists (Shop/Recruit/Reward).
## Compares one batched sheet, two-card sheets, and serialized single bakes.

const IDS := ["goblin", "brute", "ratling", "strike"]

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
	var cache := root.get_node_or_null("CardTextureCache")
	var db := root.get_node_or_null("CardDB")
	var settings := root.get_node_or_null("UserSettings")
	if cache == null or db == null or settings == null:
		push_error("[card-batch] required autoloads missing")
		quit(1)
		return
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	await _wait_idle(cache)
	var datas: Array = []
	for id in IDS:
		var data: Dictionary = db.get_card_data(id)
		if data.is_empty():
			continue
		datas.append(data)
		await CardArtAliases.prewarm_card_art(data)
	print("[card-batch] cards=%d scale=%d renderer=%s" % [
		datas.size(), cache.gameplay_bake_scale(),
		RenderingServer.get_current_rendering_method()])

	await _run_strategy("batch4", cache, datas, 4)
	await _run_strategy("pairs", cache, datas, 2)
	await _run_strategy("singles", cache, datas, 1)
	await _run_strategy("batch4_repeat", cache, datas, 4)
	_done = true
	quit(0)


func _run_strategy(label: String, cache: Node, datas: Array, chunk_size: int) -> void:
	await _wait_idle(cache)
	cache.clear()
	for _i in 4:
		await RenderingServer.frame_post_draw
	_gaps.clear()
	_previous_usec = Time.get_ticks_usec()
	_recording = true
	var started := Time.get_ticks_usec()
	if chunk_size <= 1:
		for data in datas:
			await cache.bake(data)
	else:
		var i := 0
		while i < datas.size():
			await cache.bake_many(datas.slice(i, mini(i + chunk_size, datas.size())))
			i += chunk_size
	var total_ms := float(Time.get_ticks_usec() - started) / 1000.0
	for _i in 5:
		await RenderingServer.frame_post_draw
	_recording = false
	var s := _stats(_gaps)
	print("[card-batch] %s total=%.2fms frames=%d avg=%.2f p95=%.2f p99=%.2f max=%.2f hits=%d" % [
		label, total_ms, _gaps.size(), s.avg, s.p95, s.p99, s.max,
		_count_hits(cache, datas)])


func _wait_idle(cache: Node) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while bool(cache.get("_bake_busy")) and Time.get_ticks_msec() < deadline:
		await process_frame


func _count_hits(cache: Node, datas: Array) -> int:
	var hits := 0
	for data in datas:
		if cache.has(data):
			hits += 1
	return hits


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"avg": total / values.size(),
		"p95": sorted[clampi(int(ceil(values.size() * 0.95)) - 1, 0, sorted.size() - 1)],
		"p99": sorted[clampi(int(ceil(values.size() * 0.99)) - 1, 0, sorted.size() - 1)],
		"max": sorted[-1],
	}
