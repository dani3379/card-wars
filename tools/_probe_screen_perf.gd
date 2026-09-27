extends SceneTree
## Deterministic, windowed steady-state and entry-spike benchmark for the
## campaign shell. Combat has its own full-board layer probe because a useful
## Combat sample needs a deliberately populated board.
##
## Run WINDOWED (never --headless):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \
##       --script res://tools/_probe_screen_perf.gd
## Optional:
##   -- --screen=map_first,map_reopen   # comma-separated subset
##   -- --quick                         # shorter settle/sample windows
##   -- --check-only                    # parse/autoload smoke only

const RUN_SEED := 20260903
const HERO_ID := "raider"
const SAMPLE_SECONDS := 2.25
const QUICK_SAMPLE_SECONDS := 0.65

const SCREENS: Array[Dictionary] = [
	{"id": "main_menu", "path": "res://scenes/main_menu.tscn", "settle": 2.0},
	{"id": "map_first", "path": "res://scenes/map.tscn", "settle": 4.5},
	{"id": "map_reopen", "path": "res://scenes/map.tscn", "settle": 2.0},
	{"id": "reward_general", "path": "res://scenes/reward.tscn", "settle": 3.0},
	{"id": "shop", "path": "res://scenes/shop.tscn", "settle": 3.0},
	{"id": "rest", "path": "res://scenes/rest.tscn", "settle": 2.2},
	{"id": "event", "path": "res://scenes/event.tscn", "settle": 3.5},
	{"id": "recruit", "path": "res://scenes/recruit.tscn", "settle": 3.0},
	{"id": "treasure", "path": "res://scenes/treasure.tscn", "settle": 2.2},
	{"id": "wayside_cache", "path": "res://scenes/wayside.tscn", "settle": 2.2},
	{"id": "game_over", "path": "res://scenes/game_over.tscn", "settle": 2.2},
	{"id": "game_over_reopen", "path": "res://scenes/game_over.tscn", "settle": 2.2},
	{"id": "credits", "path": "res://scenes/credits.tscn", "settle": 2.0},
	{"id": "net_lobby", "path": "res://scenes/net_lobby.tscn", "settle": 2.2},
	# Collection goes last because its exit deliberately releases gallery caches.
	{"id": "collection_cards", "path": "res://scenes/collection.tscn", "settle": 5.0},
	{"id": "collection_relics", "path": "res://scenes/collection.tscn", "settle": 2.3},
	{"id": "collection_potions", "path": "res://scenes/collection.tscn", "settle": 2.3},
]

var _started := false
var _done := false
var _quick := false
var _particles := true
var _game_over_empty_deck := false
var _game_over_no_music := false
var _game_over_warm_bg := false
var _game_over_no_summary := false
var _only: Dictionary = {}
var _results: Array[Dictionary] = []
var _scene: Node = null
var _run_prepared_for_map := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	_parse_args()
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[screen-perf] CHECK_ONLY_OK screens=%d" % SCREENS.size())
		_finish(0)
		return

	var run_state := root.get_node_or_null("RunState")
	var user_settings := root.get_node_or_null("UserSettings")
	if run_state == null or user_settings == null:
		push_error("[screen-perf] required autoloads are missing")
		_finish(1)
		return

	# The probe never claims a save slot, so screen checkpoint calls are no-ops.
	run_state.active_slot = -1
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	user_settings.graphics_preset = "medium"
	user_settings.anim_speed = 1.0
	user_settings.render_scale = 1.0
	user_settings.adaptive_render_scale = false
	user_settings.particles = _particles
	user_settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()
	if _game_over_warm_bg:
		await _warm_texture_for_probe("res://assets/backgrounds/game_over.png")

	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	print("[screen-perf] BEGIN renderer=%s gpu=%s quick=%s" % [
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
		elif arg == "--no-particles":
			_particles = false
		elif arg == "--game-over-empty-deck":
			_game_over_empty_deck = true
		elif arg == "--game-over-no-music":
			_game_over_no_music = true
		elif arg == "--game-over-warm-bg":
			_game_over_warm_bg = true
		elif arg == "--game-over-no-summary":
			_game_over_no_summary = true
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
	# A few stable frames keep the last texture upload out of screen one.
	for _i in 4:
		await RenderingServer.frame_post_draw


func _warm_texture_for_probe(path: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		return
	var warm := TextureRect.new()
	warm.texture = texture
	warm.position = Vector2.ZERO
	warm.size = Vector2(2, 2)
	warm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warm.stretch_mode = TextureRect.STRETCH_SCALE
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(warm)
	await RenderingServer.frame_post_draw
	warm.queue_free()
	await process_frame
	for _i in 3:
		await RenderingServer.frame_post_draw


func _benchmark_screen(spec: Dictionary, viewport_rid: RID) -> void:
	var id := String(spec.id)
	await _prepare_screen(id)
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var memory_before := OS.get_static_memory_usage()
	var path := String(spec.path)
	var open_started := Time.get_ticks_usec()
	var packed := load(path) as PackedScene
	var loaded_ms := float(Time.get_ticks_usec() - open_started) / 1000.0
	if packed == null:
		push_error("[screen-perf] could not load %s" % path)
		return
	var first_frame_started := Time.get_ticks_usec()
	var instantiate_started := Time.get_ticks_usec()
	_scene = packed.instantiate()
	if id == "game_over" and _game_over_no_summary:
		_scene.set_script(load("res://tools/_game_over_no_summary.gd"))
	root.add_child(_scene)
	var instantiate_ms := float(Time.get_ticks_usec() - instantiate_started) / 1000.0
	_post_open(id)
	await RenderingServer.frame_post_draw
	var first_present_ms := float(Time.get_ticks_usec() - first_frame_started) / 1000.0

	var settle_frames: Array[float] = []
	if id == "event":
		settle_frames.append_array(await _wait_for_event_ready())
	var settle_seconds := float(spec.settle)
	if _quick:
		settle_seconds = minf(settle_seconds, 0.85)
	settle_frames.append_array(await _record_frame_gaps(settle_seconds))
	if not is_instance_valid(_scene) or not _scene.is_inside_tree():
		print("[screen-perf] %s INVALID scene left tree during settle" % id)
		await _close_scene()
		return

	# Stop nondeterministic track selection/stream decode before the visual sample.
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
		"settle_max_ms": _maximum(settle_frames),
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
		"texture_memory_mib": float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
	}
	_results.append(result)
	print("[screen-perf] %s load=%.2fms instantiate=%.2fms first_present=%.2fms settle_max=%.2fms" % [
		id, loaded_ms, instantiate_ms, first_present_ms, result.settle_max_ms])
	print("[screen-perf]   frame avg=%.2f p95=%.2f p99=%.2f max=%.2f | render_cpu=%.2f gpu=%.2f" % [
		result.frame_avg_ms, result.frame_p95_ms, result.frame_p99_ms,
		result.frame_max_ms, result.cpu_avg_ms, result.gpu_avg_ms])
	print("[screen-perf]   canvas draws=%.0f objects=%.0f primitives=%.0f | nodes=%+d objects=%+d static=%+.1fMiB texture=%.1fMiB" % [
		result.draws_avg, result.canvas_objects_avg, result.primitives_avg,
		result.nodes_delta, result.objects_delta, result.static_memory_delta_mib,
		result.texture_memory_mib])
	await _close_scene()


func _prepare_screen(id: String) -> void:
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	if id in ["main_menu", "credits", "net_lobby", "collection_cards",
			"collection_relics", "collection_potions"]:
		rs.run_active = false
		rs.rematch_request = {}
		return
	if id == "map_reopen" and _run_prepared_for_map:
		rs.current_node_type = ""
		rs.current_encounter_id = ""
		return
	rs.start_new_run(HERO_ID, 0, RUN_SEED)
	rs.active_slot = -1
	rs.gold = 214
	rs.hero_hp = 22
	rs.current_bridge = false
	match id:
		"map_first":
			_run_prepared_for_map = true
			rs.current_node_type = ""
			rs.current_encounter_id = ""
		"reward_general":
			rs.current_node_type = "elite"
		"shop":
			rs.current_node_type = "shop"
		"rest":
			rs.current_node_type = "rest"
		"event":
			rs.current_node_type = "event"
			rs.current_bridge = true
		"recruit":
			rs.current_node_type = "recruit"
		"treasure":
			rs.current_node_type = "treasure"
		"wayside_cache":
			rs.current_node_type = "wayside"
			rs.current_wayside_id = "supply_cache"
		"game_over", "game_over_reopen":
			rs.hero_hp = 0
			rs.current_floor = 7
			rs.cause_of_death = "the benchmark"
			if _game_over_empty_deck:
				rs.deck.clear()
				rs.deck_uids.clear()
			if _game_over_no_music:
				var audio := root.get_node_or_null("AudioBank")
				if audio != null:
					audio.set("_current_music_track", "defeat")
	await process_frame


func _post_open(id: String) -> void:
	# These tabs all share one scene; switch after Collection's initial ready pass
	# so its in-flight card builder invalidates itself through the normal gen gate.
	if id == "collection_relics" and _scene.has_method("show_tab"):
		_scene.show_tab("relics")
	elif id == "collection_potions" and _scene.has_method("show_tab"):
		_scene.show_tab("potions")


func _close_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	for _i in 3:
		await process_frame

func _wait_for_event_ready() -> Array[float]:
	# Event paintings hydrate on a ResourceLoader worker after the first usable
	# forest-frame, while the page prose writes on for at most one second. Wait
	# for both before the steady sample; retain every observed gap in settle_max
	# so an expensive art swap remains visible in the entry-spike measurement.
	var values: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var reveal_done_at := started + 1050000
	var deadline := started + 8000000
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		values.append(float(now - previous) / 1000.0)
		previous = now
		if not is_instance_valid(_scene) or not _scene.is_inside_tree():
			break
		if now >= reveal_done_at and not bool(_scene.get("_event_art_loading")):
			break
	if is_instance_valid(_scene) and _scene.is_inside_tree():
		var presentation: Dictionary = _scene.get("_event_data").get(
			"presentation", {})
		var layout := String(presentation.get("layout", "folio"))
		var settings := root.get_node_or_null("UserSettings")
		var tutorial_seen := false
		if settings != null:
			tutorial_seen = bool(settings.lessons_seen.get("event_choice", false))
		print("[screen-perf] event_fixture id=%s layout=%s art=%s hydrated=%s tutorial_seen=%s" % [
			String(_scene.get("_event_id")), layout,
			String(_scene.get("_event_image_path")),
			str(_scene.get("_event_image") != null), str(tutorial_seen)])
	return values
	await create_timer(0.12).timeout


func _record_frame_gaps(seconds: float) -> Array[float]:
	var values: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while float(Time.get_ticks_usec() - start) / 1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		values.append(float(now - previous) / 1000.0)
		previous = now
	return values


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
	print("[screen-perf] RANKING steady_p95_ms (higher is worse)")
	for i in range(ranked.size()):
		var r: Dictionary = ranked[i]
		print("[screen-perf]   %02d %-20s p95=%6.2f cpu=%6.2f gpu=%6.2f draws=%5.0f settle_max=%7.2f" % [
			i + 1, String(r.id), float(r.frame_p95_ms), float(r.cpu_avg_ms),
			float(r.gpu_avg_ms), float(r.draws_avg), float(r.settle_max_ms)])


func _finish(code: int) -> void:
	_done = true
	quit(code)
