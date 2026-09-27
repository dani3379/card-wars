extends SceneTree
## Deterministic, windowed entry/settle/steady benchmark for the four online
## deck-acquisition screens omitted from _probe_screen_perf.gd.
##
## Each scene enters through NetMatch's real local-practice contract, with the
## normally-random match fields overwritten by fixed values before instancing.
## First-present therefore includes the authentic Relics & Potions overlay. The
## probe then passes one arsenal slate per presented frame; settle_max includes
## those transitions and every asynchronous card bake, while the steady sample
## starts only after the mode-specific card grid is complete.
##
## Run WINDOWED (never --headless for measurements):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \
##       --script res://tools/_probe_net_screen_perf.gd
## Optional:
##   -- --screen=net_quick,net_sealed  # comma-separated subset
##   -- --quick                        # shorter quiet/sample windows
##   -- --check-only                   # safe headless parse/resource smoke

const MATCH_SEED := 20260909
const LOCAL_HERO := "raider"
const REMOTE_HERO := "stalwart"
const SAMPLE_SECONDS := 2.25
const QUICK_SAMPLE_SECONDS := 0.65
const CONTENT_TIMEOUT_SECONDS := 55.0

const SCREENS: Array[Dictionary] = [
	{"id": "net_quick", "path": "res://scenes/net_quick.tscn", "mode": 2,
		"quiet": 1.25},
	{"id": "net_draft", "path": "res://scenes/net_draft.tscn", "mode": 0,
		"quiet": 1.25},
	{"id": "net_sealed", "path": "res://scenes/net_sealed.tscn", "mode": 3,
		"quiet": 1.25},
	{"id": "net_constructed", "path": "res://scenes/net_constructed.tscn", "mode": 1,
		"quiet": 1.25},
]

var _started := false
var _done := false
var _quick := false
var _only: Dictionary = {}
var _results: Array[Dictionary] = []
var _scene: Node = null
var _saved_decks_snapshot: Array = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	_parse_args()
	if OS.get_cmdline_user_args().has("--check-only"):
		var check_failed := false
		for spec in SCREENS:
			var path := String(spec.path)
			if not ResourceLoader.exists(path) or load(path) == null:
				push_error("[net-screen-perf] missing/unloadable scene: %s" % path)
				check_failed = true
		if root.get_node_or_null("NetMatch") == null \
				or root.get_node_or_null("SkirmishState") == null:
			push_error("[net-screen-perf] required net autoloads are missing")
			check_failed = true
		if check_failed:
			_finish(1)
			return
		print("[net-screen-perf] CHECK_ONLY_OK screens=%d" % SCREENS.size())
		_finish(0)
		return

	var net_match := root.get_node_or_null("NetMatch")
	var skirmish := root.get_node_or_null("SkirmishState")
	var user_settings := root.get_node_or_null("UserSettings")
	var saved_decks := root.get_node_or_null("SavedDecks")
	if net_match == null or skirmish == null or user_settings == null \
			or saved_decks == null:
		push_error("[net-screen-perf] required autoloads are missing")
		_finish(1)
		return

	# Constructed's selector must not depend on the tester's personal decks. This
	# is an in-memory substitution only: no SavedDecks write method is called.
	_saved_decks_snapshot = saved_decks.decks.duplicate(true)

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	user_settings.graphics_preset = "medium"
	user_settings.anim_speed = 1.0
	user_settings.render_scale = 1.0
	user_settings.adaptive_render_scale = false
	user_settings.particles = true
	user_settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()

	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	print("[net-screen-perf] BEGIN renderer=%s gpu=%s quick=%s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), str(_quick)])
	for spec in SCREENS:
		var id := String(spec.id)
		if not _only.is_empty() and not _only.has(id):
			continue
		await _benchmark_screen(spec, viewport_rid)
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	_print_ranking()
	_finish(0)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--quick":
			_quick = true
		elif arg.begins_with("--screen="):
			for id in arg.trim_prefix("--screen=").split(",", false):
				_only[String(id).strip_edges()] = true


func _wait_for_session_warmup() -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var cache := root.get_node_or_null("CardTextureCache")
	var card_db := root.get_node_or_null("CardDB")
	if preload_service == null or cache == null or card_db == null:
		return
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
		var resources_done: bool = not preload_service.has_method("is_warmup_complete") \
			or bool(preload_service.is_warmup_complete())
		var cards_done: bool = bool(preload_service.get("_prewarmed")) \
			and (creature.is_empty() or (cache.has(creature) \
				and cache.has_battlefield(creature))) \
			and (spell.is_empty() or cache.has(spell)) \
			and not bool(cache.get("_bake_busy"))
		if resources_done and cards_done:
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw


func _prepare_screen(spec: Dictionary) -> void:
	var net_match := root.get_node("NetMatch")
	var skirmish := root.get_node("SkirmishState")
	var saved_decks := root.get_node("SavedDecks")
	var mode := int(spec.mode)
	net_match.local_hero = LOCAL_HERO
	net_match.start_vs_bot(mode, 1)
	# start_vs_bot deliberately rolls real-session entropy and a random rival.
	# Pin both after it establishes the valid local-practice connection contract.
	net_match.match_seed = MATCH_SEED
	net_match.match_mode = mode
	net_match.best_of = 1
	net_match.battle_style = net_match.STYLE_ALTERNATING
	net_match.local_hero = LOCAL_HERO
	net_match.remote_hero = REMOTE_HERO
	skirmish.reset()
	# Prevent user://decks.json contents from changing Constructed's node count.
	saved_decks.decks = [] if String(spec.id) == "net_constructed" \
		else _saved_decks_snapshot.duplicate(true)
	# Atmosphere placement and music-pool choice also use the global RNG.
	seed(MATCH_SEED)
	await process_frame


func _benchmark_screen(spec: Dictionary, viewport_rid: RID) -> void:
	var id := String(spec.id)
	await _prepare_screen(spec)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var memory_before := OS.get_static_memory_usage()
	var path := String(spec.path)
	var open_started := Time.get_ticks_usec()
	var packed := load(path) as PackedScene
	var loaded_ms := float(Time.get_ticks_usec() - open_started) / 1000.0
	if packed == null:
		push_error("[net-screen-perf] could not load %s" % path)
		return

	var first_frame_started := Time.get_ticks_usec()
	var instantiate_started := Time.get_ticks_usec()
	_scene = packed.instantiate()
	root.add_child(_scene)
	var instantiate_ms := float(Time.get_ticks_usec() - instantiate_started) / 1000.0
	await RenderingServer.frame_post_draw
	var first_present_ms := float(Time.get_ticks_usec() - first_frame_started) / 1000.0

	var settle := await _settle_mode_screen(id, float(spec.quiet))
	if not is_instance_valid(_scene) or not _scene.is_inside_tree():
		print("[net-screen-perf] %s INVALID scene left tree during settle" % id)
		await _close_scene()
		return

	# Exclude track streaming/selection from the steady visual sample.
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		if audio.has_method("stop_music"):
			audio.stop_music()
		if audio.has_method("stop_ambience"):
			audio.stop_ambience()
	for _i in 6:
		await RenderingServer.frame_post_draw

	var sample_seconds := QUICK_SAMPLE_SECONDS if _quick else SAMPLE_SECONDS
	var measured := await _sample_steady(viewport_rid, sample_seconds)
	var result := {
		"id": id,
		"load_ms": loaded_ms,
		"instantiate_ms": instantiate_ms,
		"first_present_ms": first_present_ms,
		"settle_ms": float(settle.elapsed_ms),
		"settle_max_ms": _maximum(settle.frames),
		"content_ready": bool(settle.ready),
		"frame_avg_ms": measured.frame.avg,
		"frame_p95_ms": measured.frame.p95,
		"frame_p99_ms": measured.frame.p99,
		"frame_max_ms": measured.frame.max,
		"cpu_avg_ms": measured.cpu.avg,
		"gpu_avg_ms": measured.gpu.avg,
		"draws_avg": measured.draws.avg,
		"canvas_objects_avg": measured.canvas_objects.avg,
		"primitives_avg": measured.primitives.avg,
		"nodes_delta": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - nodes_before,
		"objects_delta": int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objects_before,
		"static_memory_delta_mib": float(OS.get_static_memory_usage() - memory_before) / 1048576.0,
		"texture_memory_mib": float(Performance.get_monitor(
			Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
	}
	_results.append(result)
	print("[net-screen-perf] %s load=%.2fms instantiate=%.2fms first_present=%.2fms settle=%.2fms settle_max=%.2fms ready=%s" % [
		id, loaded_ms, instantiate_ms, first_present_ms, result.settle_ms,
		result.settle_max_ms, str(result.content_ready)])
	print("[net-screen-perf]   frame avg=%.2f p95=%.2f p99=%.2f max=%.2f | render_cpu=%.2f gpu=%.2f" % [
		result.frame_avg_ms, result.frame_p95_ms, result.frame_p99_ms,
		result.frame_max_ms, result.cpu_avg_ms, result.gpu_avg_ms])
	print("[net-screen-perf]   canvas draws=%.0f objects=%.0f primitives=%.0f | nodes=%+d objects=%+d static=%+.1fMiB texture=%.1fMiB" % [
		result.draws_avg, result.canvas_objects_avg, result.primitives_avg,
		result.nodes_delta, result.objects_delta, result.static_memory_delta_mib,
		result.texture_memory_mib])
	await _close_scene()


func _settle_mode_screen(id: String, quiet_seconds: float) -> Dictionary:
	var frames: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	# PASS is intentionally the instant/no-pick path. One presented frame per
	# slate lets queued frees drain. Wait for progressive rich-tile hydration so
	# settle_max measures the real presentation rather than only its sleeves.
	for _pick in 5:
		if not is_instance_valid(_scene) or not _scene.is_inside_tree():
			break
		while _scene.has_method("arsenal_active") and bool(_scene.arsenal_active()) \
				and _scene.has_method("arsenal_slate_ready") \
				and not bool(_scene.arsenal_slate_ready()):
			await RenderingServer.frame_post_draw
			var hydrate_now := Time.get_ticks_usec()
			frames.append(float(hydrate_now - previous) / 1000.0)
			previous = hydrate_now
		if _scene.has_method("arsenal_active") and bool(_scene.arsenal_active()):
			_scene.call("_on_ars_pass")
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now

	var ready_since := 0
	var quiet_target := 0.40 if _quick else quiet_seconds
	var deadline := started + int(CONTENT_TIMEOUT_SECONDS * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		if not is_instance_valid(_scene) or not _scene.is_inside_tree():
			break
		if _mode_content_ready(id):
			if ready_since == 0:
				ready_since = now
			elif float(now - ready_since) / 1000000.0 >= quiet_target:
				break
		else:
			ready_since = 0
	var ready := is_instance_valid(_scene) and _scene.is_inside_tree() \
		and _mode_content_ready(id)
	if not ready:
		push_warning("[net-screen-perf] %s content did not settle before timeout" % id)
	return {
		"frames": frames,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"ready": ready,
	}


func _mode_content_ready(id: String) -> bool:
	if not is_instance_valid(_scene) or not _scene.is_inside_tree():
		return false
	if _scene.has_method("arsenal_active") and bool(_scene.arsenal_active()):
		return false
	var cache := root.get_node_or_null("CardTextureCache")
	if cache != null and bool(cache.get("_bake_busy")):
		return false
	match id:
		"net_draft":
			var card_row := _scene.get("_card_row") as Node
			return card_row != null and card_row.get_child_count() == 3
		"net_quick":
			var deck_box := _scene.get("_deck_box") as Node
			var local_deck: Array = _scene.get("_local_deck")
			var unique: Dictionary = {}
			for cid in local_deck:
				unique[String(cid)] = true
			return deck_box != null and deck_box.get_child_count() == unique.size()
		"net_sealed":
			var pool_grid := _scene.get("_pool_grid") as Node
			var avail: Dictionary = _scene.get("_avail")
			return pool_grid != null and pool_grid.get_child_count() == avail.size()
		"net_constructed":
			var pool_box := _scene.get("_pool_box") as Node
			var pool: Array = _scene.get("_pool")
			return pool_box != null and pool_box.get_child_count() == pool.size()
	return false


func _close_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	for _i in 3:
		await process_frame
	var net_match := root.get_node_or_null("NetMatch")
	if net_match != null and net_match.has_method("leave"):
		net_match.leave()
	var skirmish := root.get_node_or_null("SkirmishState")
	if skirmish != null and skirmish.has_method("reset"):
		skirmish.reset()
	await create_timer(0.12).timeout


func _sample_steady(viewport_rid: RID, seconds: float) -> Dictionary:
	var frame: Array[float] = []
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var draws: Array[float] = []
	var canvas_objects: Array[float] = []
	var primitives: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while float(Time.get_ticks_usec() - start) / 1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame.append(float(now - previous) / 1000.0)
		previous = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			+ RenderingServer.get_frame_setup_time_cpu())
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		draws.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		canvas_objects.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
		primitives.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
	return {
		"frame": _stats(frame),
		"cpu": _stats(cpu),
		"gpu": _stats(gpu),
		"draws": _stats(draws),
		"canvas_objects": _stats(canvas_objects),
		"primitives": _stats(primitives),
	}


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"avg": total / float(values.size()),
		"p95": sorted[clampi(int(ceil(values.size() * 0.95)) - 1, 0, sorted.size() - 1)],
		"p99": sorted[clampi(int(ceil(values.size() * 0.99)) - 1, 0, sorted.size() - 1)],
		"max": sorted[-1],
	}


func _maximum(values: Array[float]) -> float:
	var out := 0.0
	for value in values:
		out = maxf(out, value)
	return out


func _print_ranking() -> void:
	var ranked := _results.duplicate(true)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.frame_p95_ms) > float(b.frame_p95_ms))
	print("[net-screen-perf] RANKING steady_p95_ms (higher is worse)")
	for i in range(ranked.size()):
		var r: Dictionary = ranked[i]
		print("[net-screen-perf]   %02d %-20s p95=%6.2f cpu=%6.2f gpu=%6.2f draws=%5.0f settle_max=%7.2f ready=%s" % [
			i + 1, String(r.id), float(r.frame_p95_ms), float(r.cpu_avg_ms),
			float(r.gpu_avg_ms), float(r.draws_avg), float(r.settle_max_ms),
			str(r.content_ready)])


func _finish(code: int) -> void:
	var saved_decks := root.get_node_or_null("SavedDecks")
	if saved_decks != null and not _saved_decks_snapshot.is_empty():
		saved_decks.decks = _saved_decks_snapshot
	var net_match := root.get_node_or_null("NetMatch")
	if net_match != null and net_match.has_method("leave"):
		net_match.leave()
	_done = true
	quit(code)
