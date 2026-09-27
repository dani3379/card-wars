extends SceneTree
## Focused open-latency probe for Combat's player-invoked overlays.
##
## Run:
##   Godot_v4.6.2-stable_win64_console.exe --headless --path D:\Godot \
##     --script res://tools/_probe_combat_overlay_perf.gd

const SETTLE_FRAMES := 90

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var rs := root.get_node_or_null("RunState")
	var us := root.get_node_or_null("UserSettings")
	var cdb := root.get_node_or_null("CardDB")
	if rs == null or us == null or cdb == null:
		print("[combat-overlay-perf] FATAL: autoloads missing")
		_done = true
		quit(1)
		return
	us.anim_speed = 3.0
	us.end_turn_warning = false
	us.reduce_motion = true
	seed(4242)
	rs.start_new_run("stalwart", 0, 4242)
	rs.current_encounter_id = "goblin_scouts"
	rs.current_node_type = "combat"
	var combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	await _settle_seconds(6.0)

	var ids := _representative_ids(cdb, 36)
	print("[combat-overlay-perf] %d representative unique cards" % ids.size())
	await _measure_pile(combat, ids.slice(0, mini(12, ids.size())), "pile_12_cold")
	await _measure_pile(combat, ids.slice(0, mini(12, ids.size())), "pile_12_reopen")
	await _measure_pile(combat, ids.slice(0, mini(30, ids.size())), "pile_30_late_run")
	await _measure_simple(combat, "primer", Callable(combat, "_show_combat_primer"),
		Callable(combat, "_close_glossary"))
	await _measure_simple(combat, "full_glossary", Callable(combat, "_show_full_glossary"),
		Callable(combat, "_close_glossary"))
	await _measure_simple(combat, "emotes", Callable(combat, "_open_emote_menu"),
		Callable(combat, "_close_emote_menu"))

	combat.free()
	await process_frame
	_done = true
	quit(0)


func _representative_ids(cdb: Node, wanted: int) -> Array:
	var out: Array = []
	for id_variant in cdb.CARD_POOL.keys():
		var id := String(id_variant)
		var d: Dictionary = cdb.get_card_data(id)
		if d.is_empty() or not bool(d.get("draftable", true)):
			continue
		if String(d.get("rarity", "")) == "enemy":
			continue
		out.append(id)
		if out.size() >= wanted:
			break
	return out


func _measure_pile(combat: Node, entries: Array, tag: String) -> void:
	combat._close_pile_viewer()
	await process_frame
	combat._player_discard_pile.clear()
	for entry in entries:
		combat._player_discard_pile.append(String(entry))
	var before_nodes := _node_count(combat)
	var opened := Time.get_ticks_usec()
	combat._show_pile_viewer(1)
	var returned_ms := float(Time.get_ticks_usec() - opened) / 1000.0
	var frame_ms := await _sample_frames(combat)
	var ready_ms := -1.0
	if combat.has_method("_pile_viewer_is_ready"):
		var wait_started := Time.get_ticks_usec()
		while not combat._pile_viewer_is_ready() \
				and Time.get_ticks_usec() - wait_started < 8000000:
			await process_frame
		ready_ms = float(Time.get_ticks_usec() - opened) / 1000.0
	print("  %-18s return=%7.2f ms  frame_max=%6.2f  p95=%6.2f  ready=%7.2f  nodes=+%d" % [
		tag, returned_ms, _maxf(frame_ms), _percentile(frame_ms, 0.95), ready_ms,
		_node_count(combat) - before_nodes])
	combat._close_pile_viewer()
	await _settle_seconds(0.25)


func _measure_simple(combat: Node, tag: String, opener: Callable,
		closer: Callable) -> void:
	closer.call()
	await process_frame
	var before_nodes := _node_count(combat)
	var opened := Time.get_ticks_usec()
	opener.call()
	var returned_ms := float(Time.get_ticks_usec() - opened) / 1000.0
	var frame_ms := await _sample_frames(combat, 30)
	print("  %-18s return=%7.2f ms  frame_max=%6.2f  p95=%6.2f  nodes=+%d" % [
		tag, returned_ms, _maxf(frame_ms), _percentile(frame_ms, 0.95),
		_node_count(combat) - before_nodes])
	closer.call()
	await _settle_seconds(0.25)


func _sample_frames(_combat: Node, count: int = SETTLE_FRAMES) -> Array:
	var samples: Array = []
	var mark := Time.get_ticks_usec()
	for _i in range(count):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - mark) / 1000.0)
		mark = now
	return samples


func _settle_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total


func _maxf(values: Array) -> float:
	var out := 0.0
	for v in values:
		out = maxf(out, float(v))
	return out


func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(ceil(fraction * sorted.size())) - 1,
		0, sorted.size() - 1)])
