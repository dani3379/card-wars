extends SceneTree
## _probe_perf_pass.gd — headless verification for the 2026-07-06 lag pass.
## Run: Godot --headless --path . --script res://tools/_probe_perf_pass.gd
## Checks:
##  1. AudioBank async music: play_music resolves via the threaded loader,
##     caches the stream, and a stop_music cancels an in-flight play.
##  2. ScenePreload: every listed path ends up pinned + resource-cached.

var _fails: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio: Node = root.get_node_or_null("AudioBank")
	var pre: Node = root.get_node_or_null("ScenePreload")
	_check(audio != null, "AudioBank autoload present")
	_check(pre != null, "ScenePreload autoload present")
	if audio == null or pre == null:
		quit(1)
		return

	# --- 1. async music ------------------------------------------------------
	audio.play_music("main_menu", 0.05)
	_check(audio._pending_music_track == "main_menu",
		"play_music marks the pending track immediately")
	var settled := false
	for _i in 600:  # up to ~10s of frames for the threaded load
		await process_frame
		if audio._current_music_track == "main_menu":
			settled = true
			break
	_check(settled, "threaded load lands and the track starts")
	_check(audio._music_streams.has("main_menu"), "stream cached for the session")
	_check(audio._music_inflight.is_empty(), "no in-flight requests left behind")

	# Cache-hit path: switching to a second track then back must be instant.
	audio.play_music("map", 0.05)
	for _i in 600:
		await process_frame
		if audio._current_music_track == "map":
			break
	audio.play_music("main_menu", 0.05)
	_check(audio._current_music_track == "main_menu",
		"cached track starts synchronously (no reload)")

	# stop_music cancels an in-flight play: request an uncached track, stop
	# immediately — when the load lands it must NOT start playing.
	audio.play_music("victory", 0.05)
	audio.stop_music(0.05)
	for _i in 600:
		await process_frame
		if audio._music_streams.has("victory"):
			break
	await process_frame
	_check(audio._music_streams.has("victory"), "cancelled load still caches")
	_check(audio._current_music_track == "", "stop_music wins over in-flight load")

	# --- 2. scene preload ----------------------------------------------------
	var done := false
	for _i in 1800:  # up to ~30s of frames; disk-bound, usually far quicker
		await process_frame
		if pre._pending.is_empty() and not pre._keep.is_empty():
			done = true
			break
	_check(done, "preload queue drains")
	var missing: Array[String] = []
	for path in pre.PRELOAD_PATHS:
		if ResourceLoader.exists(path) and not pre._keep.has(path):
			missing.append(path)
	_check(missing.is_empty(), "every existing path is pinned (missing: %s)" % [missing])
	_check(ResourceLoader.has_cached("res://scenes/shop.tscn"),
		"shop.tscn is resource-cached after preload")
	_check(ResourceLoader.has_cached("res://scenes/combat.tscn"),
		"combat.tscn is resource-cached after preload")

	print("RESULT: %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)
