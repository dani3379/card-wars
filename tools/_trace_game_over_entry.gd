extends SceneTree
## Diagnostic timeline for the Game Over screen's deferred entry work.
## Run windowed. Prints only state transitions and frames slower than 10 ms.

const RUN_SEED := 20260903

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var rs := root.get_node("RunState")
	var us := root.get_node("UserSettings")
	var cache := root.get_node("CardTextureCache")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	us.graphics_preset = "medium"
	us.render_scale = 1.0
	us.adaptive_render_scale = false
	us.particles = true
	us.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup(cache)

	rs.active_slot = -1
	rs.start_new_run("raider", 0, RUN_SEED)
	rs.active_slot = -1
	rs.hero_hp = 0
	rs.current_floor = 7
	rs.cause_of_death = "the trace"
	if OS.get_cmdline_user_args().has("--empty-deck"):
		rs.deck.clear()
		rs.deck_uids.clear()
	await process_frame

	var datas := _unique_deck_datas(rs, cache)
	var args := OS.get_cmdline_user_args()
	if args.has("--verdict-delta"):
		# Model the normal final-fight path: Combat's opening warm already covered
		# the deck, then one creature earns a kill and therefore a new visual key.
		await cache.bake_many(datas)
		for i in rs.deck.size():
			var data: Dictionary = rs.get_upgraded_card_data(i)
			if String(data.get("type", "")) != "creature":
				continue
			var uid: int = rs.deck_uids[i]
			rs.creature_kills[uid] = int(rs.creature_kills.get(uid, 0)) + 1
			break
		datas = _unique_deck_datas(rs, cache)
		print("[game-over-trace] verdict delta before warm cache=%d/%d" % [
			_cache_hits(cache, datas), datas.size()])
		root.get_node("ScenePreload").warm_run_deck()
		var verdict_deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < verdict_deadline:
			await process_frame
		print("[game-over-trace] verdict delta after hold cache=%d/%d" % [
			_cache_hits(cache, datas), datas.size()])
	if args.has("--warm") or args.has("--warm-layout"):
		await cache.bake_many(datas)
		for _i in 4:
			await RenderingServer.frame_post_draw
	if args.has("--warm-layout"):
		await _warm_seen_card_layouts(datas)
	if args.has("--warm-summary-fonts"):
		await _warm_summary_fonts()
	if args.has("--warm-summary-worker"):
		await _warm_summary_fonts_on_worker()
	if args.has("--warm-summary-production"):
		var preload_service: Node = root.get_node("ScenePreload")
		var warm_started := Time.get_ticks_usec()
		var warm_previous := warm_started
		var warm_max_gap := 0.0
		preload_service.warm_game_over_ui()
		var warm_deadline := Time.get_ticks_msec() + 1500
		while not bool(preload_service.get("_game_over_ui_warmed")) \
				and Time.get_ticks_msec() < warm_deadline:
			await process_frame
			var warm_now := Time.get_ticks_usec()
			warm_max_gap = maxf(warm_max_gap,
				float(warm_now - warm_previous) / 1000.0)
			warm_previous = warm_now
		print("[game-over-trace] production ui warm=%s total=%.2fms max_gap=%.2fms" % [
			str(bool(preload_service.get("_game_over_ui_warmed"))),
			float(Time.get_ticks_usec() - warm_started) / 1000.0, warm_max_gap])
	var no_summary_script: Script = null
	if args.has("--no-summary"):
		no_summary_script = load("res://tools/_game_over_no_summary.gd") as Script
	print("[game-over-trace] before open cache=%d/%d busy=%s" % [
		_cache_hits(cache, datas), datas.size(), str(bool(cache.get("_bake_busy")))])
	var started := Time.get_ticks_usec()
	var scene = load("res://scenes/game_over.tscn").instantiate()
	if no_summary_script != null:
		scene.set_script(no_summary_script)
	root.add_child(scene)
	print("[game-over-trace] instantiated %.2fms" % [
		float(Time.get_ticks_usec() - started) / 1000.0])

	var previous := Time.get_ticks_usec()
	var last_state := ""
	var trace_started := previous
	var frame := 0
	while float(Time.get_ticks_usec() - trace_started) / 1000000.0 < 3.0:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var gap := float(now - previous) / 1000.0
		previous = now
		var vp = cache.get("_bake_viewport")
		var bake_nodes := -1
		var bake_size := Vector2i.ZERO
		if vp != null and is_instance_valid(vp):
			bake_nodes = vp.get_child_count()
			bake_size = vp.size
		var summary: Node = scene.find_child("RunSummaryPanel", true, false)
		var summary_visible := false
		var summary_sections := -1
		if summary is Control and is_instance_valid(summary):
			summary_visible = (summary as Control).visible
			if summary.get_child_count() > 0:
				var summary_col: Node = summary.get_child(0)
				if summary_col != null:
					summary_sections = summary_col.get_child_count()
		var state := "hits=%d/%d busy=%s bake_nodes=%d bake_size=%s sections=%d page=%s thumbs=%d seal=%s" % [
			_cache_hits(cache, datas), datas.size(), str(bool(cache.get("_bake_busy"))),
			bake_nodes, str(bake_size), summary_sections, str(summary_visible),
			_script_node_count(scene, "Card2D.gd"),
			str(scene.find_child("ClosingSeal", true, false) != null)]
		if gap >= 10.0 or state != last_state:
			print("[game-over-trace] f=%d t=%.1fms gap=%.2fms %s" % [
				frame, float(now - trace_started) / 1000.0, gap, state])
		last_state = state
		frame += 1

	scene.queue_free()
	for _i in 4:
		await process_frame
	_done = true
	quit(0)


func _wait_for_session_warmup(cache: Node) -> void:
	var preload_service := root.get_node_or_null("ScenePreload")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		var resources_done: bool = preload_service == null \
			or not preload_service.has_method("is_warmup_complete") \
			or bool(preload_service.is_warmup_complete())
		var pipeline_done: bool = preload_service == null \
			or bool(preload_service.get("_prewarmed"))
		if resources_done and pipeline_done and not bool(cache.get("_bake_busy")):
			break
		await create_timer(0.10).timeout
	for _i in 4:
		await RenderingServer.frame_post_draw


func _warm_seen_card_layouts(datas: Array) -> void:
	# Real Game Over cards have already appeared in hand/reward/shop screens.
	# Rebuild each exact baked-overlay face once so --warm-layout measures that
	# normal-session path, including the deterministic rules-fit memo.
	var card_scene := load("res://scenes/card_2d.tscn") as PackedScene
	var host := Control.new()
	root.add_child(host)
	for data in datas:
		var card = card_scene.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = String(data.get("id", ""))
		card.is_on_battlefield = true
		card.live_baked_mode = true
		host.add_child(card)
		await process_frame
	await process_frame
	await process_frame
	host.free()
	await process_frame


func _warm_summary_fonts() -> void:
	var game_theme: Node = root.get_node("GameTheme")
	var specs: Array[Dictionary] = [
		{"font": game_theme.get("font_display"), "size": 21, "text": "RUN SUMMARY"},
		{"font": game_theme.get("font_display"), "size": 20, "text": "PLAY AGAIN"},
		{"font": game_theme.get("font_display"), "size": 18, "text": "BACK TO MENU"},
		{"font": game_theme.get("font_display"), "size": 16,
			"text": "RELICS THE DECK BATTLE RULES SURVIVED SPECIAL BATTLES WON"},
		{"font": game_theme.get("font_title_black"), "size": 40,
			"text": "0123456789"},
		{"font": game_theme.get("font_card_body"), "size": 14,
			"text": "PROVINCES FIGHTS WON GOLD KILLS VETERANS LOST"},
		{"font": game_theme.get("font_card_body"), "size": 14,
			"text": "The final deck and relics carried through the march."},
		{"font": game_theme.get("font_card_body"), "size": 13,
			"text": "Total runs 0123456789 Wins"},
	]
	for spec in specs:
		var font: Font = spec.font
		var call_started := Time.get_ticks_usec()
		if font != null:
			font.get_string_size(String(spec.text), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(spec.size))
		print("[game-over-font] size=%d chars=%d call=%.2fms" % [
			int(spec.size), String(spec.text).length(),
			float(Time.get_ticks_usec() - call_started) / 1000.0])
		await process_frame
	for _i in 2:
		await RenderingServer.frame_post_draw


func _warm_summary_fonts_on_worker() -> void:
	var game_theme: Node = root.get_node("GameTheme")
	var specs: Array[Dictionary] = [
		{"font": game_theme.get("font_title_black"), "size": 40,
			"text": "0123456789"},
		{"font": game_theme.get("font_card_body"), "size": 14,
			"text": "PROVINCES FIGHTS WON GOLD KILLS VETERANS LOST"},
		{"font": game_theme.get("font_card_body"), "size": 13,
			"text": "Total runs 0123456789 Wins  \u00b7  \u00d7  \u2014"},
	]
	var jobs: Array[Dictionary] = []
	for spec in specs:
		var font: Font = spec.font
		var rid_started := Time.get_ticks_usec()
		var rids: Array[RID] = []
		if font != null:
			for rid_value in font.get_rids():
				var rid: RID = rid_value
				if rid.is_valid():
					rids.append(rid)
		jobs.append({"rids": rids, "size": int(spec.size),
			"text": String(spec.text)})
		print("[game-over-worker] rids size=%d count=%d call=%.2fms" % [
			int(spec.size), rids.size(),
			float(Time.get_ticks_usec() - rid_started) / 1000.0])
	var task_started := Time.get_ticks_usec()
	var task_id := WorkerThreadPool.add_task(func() -> void:
		var text_server = TextServerManager.get_primary_interface()
		for job in jobs:
			var seen := {}
			var text_value := String(job.text)
			for i in text_value.length():
				var codepoint := text_value.unicode_at(i)
				if seen.has(codepoint):
					continue
				seen[codepoint] = true
				for rid_value in job.rids:
					var rid: RID = rid_value
					if text_server.font_has_char(rid, codepoint):
						text_server.font_render_range(rid,
							Vector2i(int(job.size), 0), codepoint, codepoint)
						break
	)
	var previous := task_started
	var max_gap := 0.0
	while not WorkerThreadPool.is_task_completed(task_id):
		await process_frame
		var now := Time.get_ticks_usec()
		max_gap = maxf(max_gap, float(now - previous) / 1000.0)
		previous = now
	WorkerThreadPool.wait_for_task_completion(task_id)
	print("[game-over-worker] task total=%.2fms main_max_gap=%.2fms" % [
		float(Time.get_ticks_usec() - task_started) / 1000.0, max_gap])
	for spec in specs:
		var font: Font = spec.font
		var shape_started := Time.get_ticks_usec()
		if font != null:
			font.get_string_size(String(spec.text), HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(spec.size))
		print("[game-over-worker] shape size=%d call=%.2fms" % [
			int(spec.size),
			float(Time.get_ticks_usec() - shape_started) / 1000.0])
		await process_frame
	for _i in 2:
		await RenderingServer.frame_post_draw


func _unique_deck_datas(rs: Node, cache: Node) -> Array:
	var out: Array = []
	var seen := {}
	for i in rs.deck.size():
		var data: Dictionary = rs.get_upgraded_card_data(i)
		var key := String(cache.cache_key(data))
		if not seen.has(key):
			seen[key] = true
			out.append(data)
	return out


func _cache_hits(cache: Node, datas: Array) -> int:
	var hits := 0
	for data in datas:
		if cache.has(data):
			hits += 1
	return hits


func _script_node_count(host: Node, script_name: String) -> int:
	var count := 0
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).get_file() == script_name:
			count += 1
		for child in node.get_children():
			stack.append(child)
	return count
