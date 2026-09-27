extends Node
## Focused timing probe for persistent Settings and the shared Field Manual.

const SettingsOverlayScript = preload("res://scripts/ui/SettingsOverlay.gd")

var _recording := false
var _last_usec := 0
var _max_gap_ms := 0.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _recording and _last_usec > 0:
		_max_gap_ms = maxf(_max_gap_ms, float(now - _last_usec) / 1000.0)
	_last_usec = now


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	call_deferred("_run")


func _run() -> void:
	for _i in 3:
		await RenderingServer.frame_post_draw
	await _measure_settings_build()
	await _measure_manual(0, "primer")
	await _measure_manual(1, "coaching")
	get_tree().quit(0)


func _measure_settings_build() -> void:
	_recording = true
	_max_gap_ms = 0.0
	_last_usec = Time.get_ticks_usec()
	var started := _last_usec
	var overlay := SettingsOverlayScript.new()
	add_child(overlay)
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	var present_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_recording = false
	var nodes := _count_nodes(overlay)

	_recording = true
	_max_gap_ms = 0.0
	_last_usec = Time.get_ticks_usec()
	started = _last_usec
	overlay.call("_open")
	var open_sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	var open_present_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_recording = false
	print("[overlay-perf] settings build_sync=%.2f first_present=%.2f nodes=%d open_sync=%.2f open_present=%.2f open_gap=%.2f" % [
		sync_ms, present_ms, nodes, open_sync_ms, open_present_ms, _max_gap_ms])
	overlay.call("_close")
	for _i in 4:
		await RenderingServer.frame_post_draw
	_recording = true
	_max_gap_ms = 0.0
	_last_usec = Time.get_ticks_usec()
	started = _last_usec
	overlay.call("_open")
	var reopen_sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	var reopen_present_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_recording = false
	print("[overlay-perf] settings reopen_sync=%.2f reopen_present=%.2f reopen_gap=%.2f" % [
		reopen_sync_ms, reopen_present_ms, _max_gap_ms])
	overlay.queue_free()
	await get_tree().process_frame


func _measure_manual(tab: int, label: String) -> void:
	_recording = true
	_max_gap_ms = 0.0
	_last_usec = Time.get_ticks_usec()
	var started := _last_usec
	var overlay: Control = GameTheme.make_how_to_play_overlay(tab)
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0
	add_child(overlay)
	var sync_ms := float(Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	var present_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_recording = false
	print("[overlay-perf] manual_%s build=%.2f add_sync=%.2f first_present=%.2f max_gap=%.2f nodes=%d" % [
		label, build_ms, sync_ms, present_ms, _max_gap_ms, _count_nodes(overlay)])
	overlay.queue_free()
	await get_tree().process_frame


func _count_nodes(root_node: Node) -> int:
	var count := 0
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		count += 1
		for child in node.get_children():
			stack.append(child)
	return count
