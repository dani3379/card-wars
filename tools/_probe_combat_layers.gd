extends SceneTree
## Windowed combat layer-isolation benchmark.
##
## The older _probe_perf.gd reports the global frame monitor, whose samples can
## lag by several frames and do not separate Canvas CPU/GPU work. This probe
## follows the Godot 4.6 profiling contract instead:
##   - wall-clock frame gaps (p50/p95/p99/max),
##   - measured viewport render CPU/GPU time,
##   - Canvas-specific draw calls/objects/primitives,
##   - process time, node/object counts, and TablePlate redraws.
##
## It also changes one variable at a time on the SAME deterministic full board:
## Combat._process, the 8 fps TablePlate ink boil, TablePlate visibility, and
## the shared 30 Hz battlefield-card visual clock. Nothing is persisted.
##
## Run WINDOWED (never --headless):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       --script res://tools/_probe_combat_layers.gd

const HERO := "pyromancer"
const ENC_FALLBACK := "goblin_scouts"
const RUN_SEED := 4242
const SAMPLE_SECONDS := 2.5
const SETTLE_SECONDS := 1.0

var RS: Node
var EDB: Node
var US: Node
var CTC: Node
var SP: Node
var combat: Node
var _started := false
var _done := false
var _table_draws := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	CTC = root.get_node_or_null("CardTextureCache")
	SP = root.get_node_or_null("ScenePreload")
	if RS == null or EDB == null or CTC == null:
		push_error("[combat-layers] required autoloads are missing")
		_finish(1)
		return

	# Stable uncapped native-resolution baseline. Direct assignment deliberately
	# avoids saving probe settings to the player's profile.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.render_scale = 1.0
		US.adaptive_render_scale = false
		US.particles = false
		US.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	await process_frame
	await _wait_for_session_warmup()

	var enc_id := _find_encounter()
	RS.start_new_run(HERO, 0, RUN_SEED)
	RS.current_encounter_id = enc_id
	RS.current_node_type = "combat"
	if SP != null and SP.has_method("warm_run_deck"):
		SP.warm_run_deck()
	await create_timer(3.5).timeout

	var packed := load("res://scenes/combat.tscn") as PackedScene
	var ready_started := Time.get_ticks_usec()
	combat = packed.instantiate()
	root.add_child(combat)
	var ready_ms := float(Time.get_ticks_usec() - ready_started) / 1000.0
	print("[combat-layers] encounter=%s ready_sync=%.2fms renderer=%s gpu=%s" % [
		enc_id, ready_ms, RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name()])

	await _wait_player_turn()
	if not is_instance_valid(combat):
		push_error("[combat-layers] combat disappeared before the player turn")
		_finish(1)
		return
	await create_timer(SETTLE_SECONDS).timeout

	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	await _sample("hand_only", viewport_rid)

	_fill_board(enc_id)
	await create_timer(2.0).timeout
	var table := _find_script_node(combat, "TablePlate.gd")
	if table != null and table.has_signal("draw"):
		table.draw.connect(_on_table_draw)
	var clock := _find_named_node(combat, "BattlefieldVisualClock") as Timer
	print("[combat-layers] full board friendly=%d enemy=%d hand=%d cards=%d baked_faces=%d" % [
		_count_board(false), _count_board(true), combat._hand.size(),
		_count_script_nodes(combat, "Card2D.gd"), _count_baked_faces(combat)])

	await _sample("full_default", viewport_rid)
	var board_cards := _board_cards()
	print("[combat-layers] board overlays stat_labels=%d status_orbs=%d" % [
		_count_card_layer(board_cards, "stats"),
		_count_card_layer(board_cards, "status")])

	_set_card_layer_visible(board_cards, "status", false)
	await _sample("full_status_orbs_hidden", viewport_rid)
	_set_card_layer_visible(board_cards, "status", true)

	_set_card_layer_visible(board_cards, "stats", false)
	await _sample("full_stat_labels_hidden", viewport_rid)
	_set_card_layer_visible(board_cards, "stats", true)

	_set_card_layer_visible(board_cards, "face", false)
	await _sample("full_baked_faces_hidden", viewport_rid)
	_set_card_layer_visible(board_cards, "face", true)

	for card in board_cards:
		card.visible = false
	await _sample("full_board_cards_hidden", viewport_rid)
	for card in board_cards:
		card.visible = true
	await _sample("full_default_after_card_tests", viewport_rid)

	var combat_was_processing: bool = combat.is_processing()
	combat.set_process(false)
	await _sample("full_combat_process_off", viewport_rid)
	combat.set_process(combat_was_processing)

	if table != null:
		var table_was_processing: bool = table.is_processing()
		table.set_process(false)
		table.set("_boil_v", 0)
		table.queue_redraw()
		await process_frame
		await _sample("full_table_static", viewport_rid)
		table.visible = false
		await process_frame
		await _sample("full_table_hidden", viewport_rid)
		table.visible = true
		table.set_process(table_was_processing)
		await process_frame
	else:
		print("[combat-layers] WARN TablePlate not found")

	if clock != null:
		var clock_was_stopped := clock.is_stopped()
		clock.stop()
		await _sample("full_card_clock_off", viewport_rid)
		if not clock_was_stopped:
			clock.start()
	else:
		print("[combat-layers] WARN BattlefieldVisualClock not found")

	await create_timer(0.5).timeout
	await _sample("full_default_repeat", viewport_rid)
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	_finish(0)


func _wait_for_session_warmup() -> void:
	if SP == null:
		return
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var queue_done: bool = not SP.has_method("is_warmup_complete") \
			or bool(SP.is_warmup_complete())
		var pipeline_done: bool = bool(SP.get("_prewarmed"))
		if queue_done and pipeline_done:
			break
		await create_timer(0.1).timeout
	await create_timer(0.5).timeout


func _find_encounter() -> String:
	if EDB.ENCOUNTERS.has(ENC_FALLBACK):
		return ENC_FALLBACK
	for id_variant in EDB.ENCOUNTERS.keys():
		var id := String(id_variant)
		var data: Dictionary = EDB.ENCOUNTERS[id]
		if int(data.get("act", 1)) == 1 \
				and String(data.get("type", "combat")) == "combat":
			return id
	return String(EDB.ENCOUNTERS.keys()[0])


func _wait_player_turn() -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and is_instance_valid(combat):
		if combat.phase == combat.Phase.PLAYER_TURN and not combat._hand.is_empty():
			return
		await create_timer(0.05).timeout


func _fill_board(enc_id: String) -> void:
	var enemy_cards: Array = EDB.build_enemy_deck(enc_id)
	var enemy_index := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				combat.summon_token(2 + lane % 2, 3, lane, false, row)
			if combat._row_array(true, row)[lane] == null and not enemy_cards.is_empty():
				var data: Dictionary = enemy_cards[enemy_index % enemy_cards.size()]
				enemy_index += 1
				combat._place_enemy_card(data.duplicate(true), lane, row)


func _sample(label: String, viewport_rid: RID) -> void:
	# Let mode changes and delayed renderer counters settle before recording.
	for _i in 8:
		await RenderingServer.frame_post_draw
	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var process_ms: Array[float] = []
	var draws: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	var table_draws_before := _table_draws
	while float(Time.get_ticks_usec() - start) / 1000000.0 < SAMPLE_SECONDS:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			+ RenderingServer.get_frame_setup_time_cpu())
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
		process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		draws.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)))
		objects.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)))
		primitives.append(float(RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)))
	var memory_mib := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	print("[combat-layers] %s frames=%d table_redraws=%d nodes=%d objects=%d memory=%.1fMiB" % [
		label, frame_ms.size(), _table_draws - table_draws_before,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), memory_mib])
	print("[combat-layers]   frame  %s" % _summary(frame_ms))
	print("[combat-layers]   render cpu %s | gpu %s" % [
		_summary(cpu_ms), _summary(gpu_ms)])
	print("[combat-layers]   process %s" % _summary(process_ms))
	print("[combat-layers]   canvas draws %s | objects %s | primitives %s" % [
		_summary(draws, 0), _summary(objects, 0), _summary(primitives, 0)])


func _summary(values: Array[float], decimals: int = 2) -> String:
	if values.is_empty():
		return "n/a"
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in values:
		total += value
	var format := "%%.%df" % decimals
	return "avg=%s p50=%s p95=%s p99=%s max=%s" % [
		format % (total / float(values.size())),
		format % _percentile(ordered, 0.50),
		format % _percentile(ordered, 0.95),
		format % _percentile(ordered, 0.99),
		format % ordered[-1]]


func _percentile(ordered: Array, fraction: float) -> float:
	var index := clampi(int(ceil(float(ordered.size()) * fraction)) - 1,
		0, ordered.size() - 1)
	return float(ordered[index])


func _board_cards() -> Array:
	var cards: Array = []
	for enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			for card in combat._row_array(enemy, row):
				if card != null and is_instance_valid(card):
					cards.append(card)
	return cards


func _count_card_layer(cards: Array, layer: String) -> int:
	var count := 0
	for card in cards:
		match layer:
			"stats":
				for key in ["_atk_label", "_hp_label"]:
					var label = card.get(key)
					if label is CanvasItem and is_instance_valid(label):
						count += 1
			"status":
				for orb in card.get("_status_orbs"):
					if orb is CanvasItem and is_instance_valid(orb):
						count += 1
			"face":
				var face = card.get("_compact_face")
				if face is CanvasItem and is_instance_valid(face):
					count += 1
	return count


func _set_card_layer_visible(cards: Array, layer: String, shown: bool) -> void:
	for card in cards:
		match layer:
			"stats":
				for key in ["_atk_label", "_hp_label"]:
					var label = card.get(key)
					if label is CanvasItem and is_instance_valid(label):
						label.visible = shown
			"status":
				for orb in card.get("_status_orbs"):
					if orb is CanvasItem and is_instance_valid(orb):
						orb.visible = shown
			"face":
				var face = card.get("_compact_face")
				if face is CanvasItem and is_instance_valid(face):
					face.visible = shown


func _find_script_node(node: Node, file_name: String) -> Node:
	var script := node.get_script() as Script
	if script != null and String(script.resource_path).get_file() == file_name:
		return node
	for child in node.get_children():
		var found := _find_script_node(child, file_name)
		if found != null:
			return found
	return null


func _find_named_node(node: Node, wanted_name: String) -> Node:
	if node.name == wanted_name:
		return node
	for child in node.get_children():
		var found := _find_named_node(child, wanted_name)
		if found != null:
			return found
	return null


func _count_script_nodes(node: Node, file_name: String) -> int:
	var count := 0
	var script := node.get_script() as Script
	if script != null and String(script.resource_path).get_file() == file_name:
		count += 1
	for child in node.get_children():
		count += _count_script_nodes(child, file_name)
	return count


func _count_baked_faces(node: Node) -> int:
	var count := 0
	var script := node.get_script() as Script
	if script != null and String(script.resource_path).get_file() == "Card2D.gd":
		var face = node.get("_compact_face")
		if face != null and is_instance_valid(face):
			count += 1
	for child in node.get_children():
		count += _count_baked_faces(child)
	return count


func _count_board(is_enemy: bool) -> int:
	var count := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for card in combat._row_array(is_enemy, row):
			if card != null and is_instance_valid(card):
				count += 1
	return count


func _on_table_draw() -> void:
	_table_draws += 1


func _finish(code: int) -> void:
	_done = true
	quit(code)
