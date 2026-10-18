extends Node
## Lightweight F3 diagnostics overlay. Sampling stays on so the panel has a
## useful rolling history when opened; UI text refreshes only four times/second.

const SAMPLE_CAP := 300
const REFRESH_INTERVAL := 0.25

var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _label: Label = null
var _shown := false
var _samples: Array[float] = []
var _sample_cursor := 0
var _refresh_accum := 0.0
var _last_frame_ms := 0.0

var _last_scene_path := ""
var _transition_target := ""
var _transition_started_usec: int = -1
var _transition_settle_frames := 0
var _last_transition_ms := -1.0
var _previous_process_usec: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	_last_scene_path = _active_scene_path()
	_previous_process_usec = Time.get_ticks_usec()


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PerformanceOverlayLayer"
	_layer.layer = 2000
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.name = "PerformancePanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -410
	_panel.offset_right = -12
	_panel.offset_top = 12
	_panel.offset_bottom = 182
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.022, 0.019, 0.92)
	style.border_color = Color(0.72, 0.58, 0.30, 0.82)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	_panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.94, 0.90, 0.78))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("outline_size", 3)
	_panel.add_child(_label)
	_panel.visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		_shown = not _shown
		_panel.visible = _shown
		if _shown:
			_refresh_text()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if delta > 0.0 and delta < 0.25:
		_last_frame_ms = delta * 1000.0
		if _samples.size() < SAMPLE_CAP:
			_samples.append(_last_frame_ms)
		else:
			# Fixed-size ring: avoid shifting 299 floats every frame once the
			# rolling window is full. Percentile/average calculations are orderless.
			_samples[_sample_cursor] = _last_frame_ms
			_sample_cursor = (_sample_cursor + 1) % SAMPLE_CAP
	_track_scene_transition(now_usec)
	_previous_process_usec = now_usec
	if not _shown:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = fmod(_refresh_accum, REFRESH_INTERVAL)
		_refresh_text()


func begin_transition(target_scene: String) -> void:
	_transition_target = target_scene
	_transition_started_usec = Time.get_ticks_usec()
	_transition_settle_frames = 0


func _track_scene_transition(now_usec: int) -> void:
	var path := _active_scene_path()
	if path != "" and path != _last_scene_path:
		_last_scene_path = path
		# Direct change_scene_to_file calls do not pass through GameTheme's wipe.
		# Use the prior process timestamp as their best load-start boundary so the
		# overlay still reports the blocking frame plus two settle frames.
		if _transition_started_usec < 0 and _previous_process_usec >= 0:
			_transition_started_usec = _previous_process_usec
		_transition_settle_frames = 3
	if _transition_settle_frames > 0:
		_transition_settle_frames -= 1
		if _transition_settle_frames == 0 and _transition_started_usec >= 0:
			_last_transition_ms = float(now_usec - _transition_started_usec) / 1000.0
			_transition_started_usec = -1
			_transition_target = ""


func _active_scene() -> Node:
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("get_active_scene"):
		var nested: Node = ss.get_active_scene()
		if nested != null and is_instance_valid(nested):
			return nested
	return get_tree().current_scene


func _active_scene_path() -> String:
	var scene := _active_scene()
	if scene == null or not is_instance_valid(scene):
		return ""
	return String(scene.scene_file_path)


func _refresh_text() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var avg_ms := 0.0
	for sample in _samples:
		avg_ms += sample
	if not _samples.is_empty():
		avg_ms /= float(_samples.size())
	var p99_ms := avg_ms
	if not _samples.is_empty():
		var ordered: Array[float] = _samples.duplicate()
		ordered.sort()
		var p99_index := clampi(int(floor(float(ordered.size() - 1) * 0.99)),
			0, ordered.size() - 1)
		p99_ms = ordered[p99_index]
	var low_fps := 0.0 if p99_ms <= 0.001 else 1000.0 / p99_ms
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var draws := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory_mib := float(OS.get_static_memory_usage()) / (1024.0 * 1024.0)
	var peak_mib := float(OS.get_static_memory_peak_usage()) / (1024.0 * 1024.0)
	var requested := 1.0
	var effective := 1.0
	var adaptive_note := ""
	var ss := get_node_or_null("/root/Supersample")
	if ss != null:
		if ss.has_method("get_requested_scale"):
			requested = float(ss.get_requested_scale())
		if ss.has_method("get_effective_scale"):
			effective = float(ss.get_effective_scale())
		if effective + 0.01 < requested:
			adaptive_note = "  ADAPTIVE"
	var scene_name := _active_scene_path().get_file().get_basename()
	if scene_name == "":
		scene_name = "(transition)"
	var transition_text := "--"
	if _last_transition_ms >= 0.0:
		transition_text = "%.0f ms" % _last_transition_ms
	elif _transition_started_usec >= 0:
		transition_text = "measuring..."
	_label.text = (
		"PERFORMANCE  [F3]\n"
		+ "FPS %3.0f   frame %5.1f ms   avg %5.1f ms   1%% low %3.0f\n" \
			% [fps, _last_frame_ms, avg_ms, low_fps]
		+ "draws %4d   objects %5d   nodes %5d\n" % [draws, objects, nodes]
		+ "memory %.0f MiB   peak %.0f MiB\n" % [memory_mib, peak_mib]
		+ "render %.2fx / %.2fx%s   scene %s\n" \
			% [effective, requested, adaptive_note, scene_name]
		+ "last scene load %s" % transition_text)


func get_last_transition_ms() -> float:
	return _last_transition_ms
