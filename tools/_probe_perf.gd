extends SceneTree
## Combat render-perf probe (2026-06-29). Boots the REAL combat scene WINDOWED
## (no --headless, so the GL renderer actually runs) and samples real render
## metrics — draw calls, objects, frame time, FPS — across three states:
##   1. fresh load (round-1 setup board)
##   2. populated board (after auto-playing a couple of turns)
##   3. simulated hand-card drag (the state the user says lags worst)
##
## Run (WINDOWED — do NOT pass --headless):
##   Godot.exe --path "D:\Godot" --script res://tools/_probe_perf.gd
##
## Writes a summary to user://_probe_perf.log and prints it to stdout.

const HERO := "pyromancer"
const ENC := "act1_fight1"          # resolved/fallback below
const SAMPLE_FRAMES := 60
const TICK := 0.1

var RS: Node
var EDB: Node
var US: Node
var combat: Node
var _started := false
var _done := false
var _lines: Array[String] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _log(s: String) -> void:
	print(s)
	_lines.append(s)


func _run() -> void:
	RS  = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US  = root.get_node_or_null("UserSettings")
	if RS == null or EDB == null:
		_log("[perf] FATAL autoloads missing")
		_finish()
		return
	if US != null:
		US.anim_speed = 3.0   # instant pauses so round-1 setup settles fast
		US.end_turn_warning = false

	# Pick a real act-1 combat encounter.
	var enc_id := ENC
	if not EDB.ENCOUNTERS.has(enc_id):
		for id in EDB.ENCOUNTERS.keys():
			var d: Dictionary = EDB.ENCOUNTERS[id]
			if int(d.get("act", 1)) == 1 and String(d.get("type", "combat")) == "combat":
				enc_id = String(id)
				break
	_log("[perf] encounter = %s" % enc_id)

	RS.start_new_run(HERO, 0, 4242)
	RS.current_encounter_id = enc_id
	RS.current_node_type = "combat"

	var scene = load("res://scenes/combat.tscn")
	# COLD boot with NO idle warm — the baseline bake burst at fight start.
	var t0 := Time.get_ticks_msec()
	combat = scene.instantiate()
	root.add_child(combat)
	_log("[perf] COLD add_child(_ready sync)=%dms" % [Time.get_ticks_msec() - t0])
	await _sample_burst("STATE 0a: first ~1s after COLD load (bake burst expected)", 50)
	combat.queue_free()
	await create_timer(0.3).timeout

	# Fresh-session simulation + the map-idle deck warm (what MapView fires on
	# open): the fight booted after it should hold frame rate from frame one.
	var CTC: Node = root.get_node_or_null("CardTextureCache")
	var SP: Node = root.get_node_or_null("ScenePreload")
	if CTC != null:
		CTC.clear()
	RS.start_new_run(HERO, 0, 4242)
	RS.current_encounter_id = enc_id
	RS.current_node_type = "combat"
	if SP != null and SP.has_method("warm_run_deck"):
		SP.warm_run_deck()
	await create_timer(4.5).timeout
	if CTC != null:
		_log("[perf] deck warm done: %d baked textures" % CTC._cache.size())

	var tw := Time.get_ticks_msec()
	combat = scene.instantiate()
	root.add_child(combat)
	_log("[perf] WARMED add_child(_ready sync)=%dms" % [Time.get_ticks_msec() - tw])

	# Measure the FIRST second after load — this catches the _prebake_hand_textures
	# hitch the player used to feel at every fight start.
	await _sample_burst("STATE 0b: first ~1s after WARMED load (should stay smooth)", 50)

	await _wait_player_turn()
	_log("[perf] --- window size = %s ---" % str(root.get_visible_rect().size))
	_log("[perf] node count (whole tree) = %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# Keep the fresh round-1 hand (don't end turns — that discards/redraws and was
	# leaving the hand empty mid-transition). Instead directly fill BOTH boards with
	# enemy-art creatures to a realistic worst case, so idle+drag are measured over a
	# busy board.
	var fill: Array = combat._enemy_deck.duplicate()
	if fill.is_empty():
		# Round flow may have consumed the deck by now — rebuild from the DB so
		# the busy-board states measure over a real formation.
		fill = EDB.build_enemy_deck(enc_id)
	var idx := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if fill.is_empty():
				continue
			var d: Dictionary = fill[idx % fill.size()]
			idx += 1
			if combat._row_array(true, row)[lane] == null:
				combat._place_enemy_card(d.duplicate(true), lane, row)
	await create_timer(0.3).timeout

	var nfriendly := _count_board(false)
	var nenemy := _count_board(true)
	_log("[perf] board now: %d friendly, %d enemy creatures; hand=%d" % [
		nfriendly, nenemy, (combat._hand.size() if is_instance_valid(combat) else 0)])

	# STATE 2: populated board, idle
	await _sample("STATE 2: mid-fight board, idle")

	# STATE 3: simulate dragging a hand card across the board.
	await _sample_drag("STATE 3: simulated hand-card drag")

	_log("[perf] DONE")
	_finish()


func _finish() -> void:
	var f := FileAccess.open("user://_probe_perf.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	_done = true
	quit()


func _wait_player_turn() -> bool:
	# 30s ceiling: the fight intro runs at real time and stretches when the
	# renderer is busy — the old 8s ceiling expired mid-intro and every later
	# state measured an empty board.
	var w := 0
	while w < 300:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN:
			return true
		await create_timer(TICK).timeout
		w += 1
	return false


func _count_board(is_enemy: bool) -> int:
	var n := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(is_enemy, row):
			if c != null and is_instance_valid(c):
				n += 1
	return n


func _sample(label: String) -> void:
	await _sample_burst(label, SAMPLE_FRAMES)


func _sample_burst(label: String, frames: int) -> void:
	await process_frame
	var fps_min := 99999.0
	var fps_sum := 0.0
	var draw_sum := 0.0
	var draw_max := 0.0
	var obj_sum := 0.0
	var proc_min := 99999.0
	var proc_max := 0.0
	var proc_sum := 0.0
	for i in frames:
		await process_frame
		var fps: float = Performance.get_monitor(Performance.TIME_FPS)
		fps_sum += fps
		fps_min = min(fps_min, fps)
		var dc: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		draw_sum += dc
		draw_max = max(draw_max, dc)
		obj_sum += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var pr: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		proc_sum += pr
		proc_min = min(proc_min, pr)
		proc_max = max(proc_max, pr)
	var n := float(frames)
	_log("[perf] %s" % label)
	_log("[perf]   FPS min=%.1f avg=%.1f | draw_calls avg=%.0f max=%.0f | objects=%.0f | process min=%.2f avg=%.2f max=%.2f ms" % [
		fps_min, fps_sum / n, draw_sum / n, draw_max, obj_sum / n, proc_min, proc_sum / n, proc_max])


func _sample_drag(label: String) -> void:
	# Grab a hand card and move it across the board every frame, like a real drag.
	if not is_instance_valid(combat) or combat._hand.is_empty():
		_log("[perf] %s SKIPPED (no hand)" % label)
		return
	var card = combat._hand[0]
	if not is_instance_valid(card):
		_log("[perf] %s SKIPPED (bad card)" % label)
		return
	# Set the drag statics through the INSTANCE's script object, not the Card2D
	# class name — naming the class here makes Card2D.gd a compile-time dependency
	# of this probe, and probe scripts compile BEFORE autoloads register, so
	# Card2D's CardDB references fail and poison the class for the whole session
	# (script-less PanelContainer cards, empty boards, error-spam "frame drops").
	var card_script: Script = card.get_script()
	card_script.set("_any_card_dragging", true)
	card.set("_is_being_dragged", true)
	card.z_index = 20
	var vp := root.get_visible_rect().size
	await process_frame
	var fps_min := 99999.0
	var fps_sum := 0.0
	var draw_sum := 0.0
	var draw_max := 0.0
	var proc_min := 99999.0
	var proc_max := 0.0
	var proc_sum := 0.0
	for i in SAMPLE_FRAMES:
		# Sweep the card across the board area each frame.
		var t: float = float(i) / float(SAMPLE_FRAMES)
		card.global_position = Vector2(vp.x * (0.2 + 0.6 * t), vp.y * (0.35 + 0.15 * sin(t * TAU)))
		if card.has_signal("dragging"):
			card.dragging.emit(card.global_position + card.size * 0.5)
		await process_frame
		var fps: float = Performance.get_monitor(Performance.TIME_FPS)
		fps_sum += fps
		fps_min = min(fps_min, fps)
		var dc: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		draw_sum += dc
		draw_max = max(draw_max, dc)
		var pr: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		proc_sum += pr
		proc_min = min(proc_min, pr)
		proc_max = max(proc_max, pr)
	card_script.set("_any_card_dragging", false)
	card.set("_is_being_dragged", false)
	var n := float(SAMPLE_FRAMES)
	_log("[perf] %s" % label)
	_log("[perf]   FPS min=%.1f avg=%.1f | draw_calls avg=%.0f max=%.0f | process min=%.2f avg=%.2f max=%.2f ms" % [
		fps_min, fps_sum / n, draw_sum / n, draw_max, proc_min, proc_sum / n, proc_max])
