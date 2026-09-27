extends SceneTree
## Measures map cartouche font-cache misses after the normal session warmup.

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await process_frame
	await _wait_for_session_warmup()
	var theme := root.get_node("GameTheme")
	var specs: Array[Dictionary] = [
		{"label": "title_a", "font": theme.font_title,
			"text": "ACT III - THE", "size": 22},
		{"label": "title_b", "font": theme.font_title,
			"text": "BURNING ISLE", "size": 22},
		{"label": "display_upper_a", "font": theme.font_display,
			"text": "ABCDEFGHIJKLM", "size": 15},
		{"label": "display_upper_b", "font": theme.font_display,
			"text": "NOPQRSTUVWXYZ", "size": 15},
		{"label": "display_lower_a", "font": theme.font_display,
			"text": "abcdefghijklm", "size": 15},
		{"label": "display_lower_b", "font": theme.font_display,
			"text": "nopqrstuvwxyz", "size": 15},
		{"label": "display_marks", "font": theme.font_display,
			"text": "0123456789 / -", "size": 15},
	]
	for spec in specs:
		var started := Time.get_ticks_usec()
		(spec.font as Font).get_string_size(String(spec.text),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(spec.size))
		print("[map-font] %s %.2fms" % [spec.label,
			float(Time.get_ticks_usec() - started) / 1000.0])
		await process_frame
	for _i in 3:
		await process_frame
	_done = true
	quit(0)


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node("ScenePreload")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		if preload_service.is_warmup_complete() \
				and bool(preload_service.get("_prewarmed")):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw
