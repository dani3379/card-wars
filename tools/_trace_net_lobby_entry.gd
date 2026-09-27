extends SceneTree
## Focused NetLobby late-frame trace. Diagnostic switches isolate audio and chips.

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = true
	settings.reduce_motion = false
	await process_frame
	await _wait_for_session_warmup()

	var args := OS.get_cmdline_user_args()
	var audio := root.get_node("AudioBank")
	if args.has("--music-warm"):
		for track in ["net_lobby", "net_lobby_b", "rest_c"]:
			audio.play_music(track, 0.0)
			var deadline := Time.get_ticks_msec() + 12000
			while Time.get_ticks_msec() < deadline \
					and not audio._music_streams.has(track):
				await process_frame
		audio.stop_music(0.0)
		for _i in 3:
			await RenderingServer.frame_post_draw

	seed(20260903)
	var started := Time.get_ticks_usec()
	var lobby = load("res://scenes/net_lobby.tscn").instantiate()
	root.add_child(lobby)
	print("[lobby-trace] instantiate=%.2fms music_warm=%s" % [
		float(Time.get_ticks_usec() - started) / 1000.0,
		str(args.has("--music-warm"))])
	if args.has("--hide-chips"):
		for button in lobby._hero_buttons.values():
			if button is Control:
				button.visible = false
	if args.has("--hide-portraits"):
		if lobby._your_portrait != null:
			lobby._your_portrait.visible = false
		if lobby._opp_portrait != null:
			lobby._opp_portrait.visible = false
	if args.has("--cancel-music"):
		audio.stop_music(0.0)

	var previous := Time.get_ticks_usec()
	var trace_started := previous
	var last_state := ""
	var frame := 0
	while float(Time.get_ticks_usec() - trace_started) / 1000000.0 < 2.2:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var gap := float(now - previous) / 1000.0
		previous = now
		var state := "current=%s pending=%s inflight=%d streams=%d" % [
			String(audio._current_music_track), String(audio._pending_music_track),
			audio._music_inflight.size(), audio._music_streams.size()]
		if gap >= 8.0 or state != last_state:
			print("[lobby-trace] f=%d t=%.1fms gap=%.2fms %s tex=%.1fMiB" % [
				frame, float(now - trace_started) / 1000.0, gap, state,
				float(Performance.get_monitor(
					Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0])
		last_state = state
		frame += 1

	lobby.queue_free()
	for _i in 3:
		await process_frame
	_done = true
	quit(0)


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var cache := root.get_node_or_null("CardTextureCache")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = preload_service == null \
			or bool(preload_service.is_warmup_complete())
		var pipeline_done: bool = preload_service == null \
			or bool(preload_service.get("_prewarmed"))
		if resources_done and pipeline_done \
				and (cache == null or not bool(cache.get("_bake_busy"))):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw
