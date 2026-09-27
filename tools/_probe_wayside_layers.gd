extends SceneTree
## Focused windowed draw-call attribution for the default Supply Cache wayside.
## Measures one settled scene while hiding coherent layers and while replacing
## ChartPanelStyle resources with margin-equivalent empty styles.
##
## Run windowed and serially:
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\\Godot" \\
##       --script res://tools/_probe_wayside_layers.gd
## Parse/autoload smoke only:
##   ... --headless --script res://tools/_probe_wayside_layers.gd -- --check-only

const SAMPLE_SECONDS := 0.75

var _started := false
var _done := false
var _scene: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	if OS.get_cmdline_user_args().has("--check-only"):
		print("[wayside-layers] CHECK_ONLY_OK")
		_done = true
		quit(0)
		return
	var settings := root.get_node_or_null("UserSettings")
	var run_state := root.get_node_or_null("RunState")
	if settings == null or run_state == null:
		push_error("[wayside-layers] required autoload missing")
		_done = true
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = true
	settings.reduce_motion = false
	var supersample := root.get_node_or_null("Supersample")
	if supersample != null and supersample.has_method("apply_scale"):
		supersample.apply_scale(1.0)
	run_state.start_new_run("raider", 0, 20260903)
	run_state.active_slot = -1
	run_state.current_node_type = "wayside"
	run_state.current_wayside_id = "supply_cache"
	await process_frame
	_scene = load("res://scenes/wayside.tscn").instantiate()
	root.add_child(_scene)
	await create_timer(2.4).timeout
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music()
		audio.stop_ambience()

	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var atmosphere := _scene.get_node_or_null("Atmosphere") as CanvasItem
	var tile_stack := _scene.get("_tile_stack") as CanvasItem
	var settings_button := _scene.find_child("SettingsGear", true, false) as CanvasItem
	_print_chart_inventory()
	await _sample("full", viewport_rid)
	await _hide_sample("atmosphere_hidden", viewport_rid, [atmosphere])
	await _hide_sample("tiles_hidden", viewport_rid, [tile_stack])
	await _hide_sample("settings_hidden", viewport_rid, [settings_button])
	await _chart_styles_empty_sample(viewport_rid)
	var all_but_background: Array[CanvasItem] = []
	for child in _scene.get_children():
		if child is CanvasItem and child.name != "Background":
			all_but_background.append(child as CanvasItem)
	await _hide_sample("background_only", viewport_rid, all_but_background)

	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	_scene.queue_free()
	for _i in 4:
		await process_frame
	_done = true
	quit(0)


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _style_slots(control: Control) -> Array[String]:
	if control is PanelContainer:
		return ["panel"]
	if control is Button:
		return ["normal", "focus", "hover", "pressed", "disabled"]
	return []


func _is_chart_panel_style(style: StyleBox) -> bool:
	for property in style.get_property_list():
		if String(property.name) == "corner_tacks":
			return true
	return false


func _chart_style_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for node in _walk(_scene):
		if not node is Control:
			continue
		var control := node as Control
		for slot in _style_slots(control):
			var style := control.get_theme_stylebox(slot)
			if _is_chart_panel_style(style):
				records.append({
					"control": control,
					"slot": slot,
					"style": style,
					"had_override": control.has_theme_stylebox_override(slot),
				})
	return records


func _print_chart_inventory() -> void:
	for record in _chart_style_records():
		var control: Control = record.control
		var style: StyleBox = record.style
		print("[wayside-layers] chart path=%s slot=%s size=%s shadow=%s tacks=%s" % [
			str(control.get_path()), String(record.slot), str(control.size),
			str(style.get("shadow")), str(style.get("corner_tacks"))])


func _empty_with_same_margins(style: StyleBox) -> StyleBoxEmpty:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = style.get_content_margin(SIDE_LEFT)
	empty.content_margin_top = style.get_content_margin(SIDE_TOP)
	empty.content_margin_right = style.get_content_margin(SIDE_RIGHT)
	empty.content_margin_bottom = style.get_content_margin(SIDE_BOTTOM)
	return empty


func _chart_styles_empty_sample(viewport_rid: RID) -> void:
	var records := _chart_style_records()
	for record in records:
		var control: Control = record.control
		control.add_theme_stylebox_override(StringName(record.slot),
			_empty_with_same_margins(record.style))
	await process_frame
	await _sample("chart_styles_empty", viewport_rid)
	for record in records:
		var control: Control = record.control
		var slot := StringName(record.slot)
		if bool(record.had_override):
			control.add_theme_stylebox_override(slot, record.style)
		else:
			control.remove_theme_stylebox_override(slot)
	await process_frame


func _hide_sample(label: String, viewport_rid: RID, items: Array) -> void:
	var hidden: Array[CanvasItem] = []
	for item in items:
		if item is CanvasItem and is_instance_valid(item) and item.visible:
			item.visible = false
			hidden.append(item)
	await process_frame
	await _sample(label, viewport_rid)
	for item in hidden:
		item.visible = true
	await process_frame


func _sample(label: String, viewport_rid: RID) -> void:
	for _i in 5:
		await RenderingServer.frame_post_draw
	var frames: Array[float] = []
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var objects := 0.0
	var primitives := 0.0
	var started := Time.get_ticks_usec()
	var previous := started
	var count := 0
	while float(Time.get_ticks_usec() - started) / 1000000.0 < SAMPLE_SECONDS:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) \
			+ RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		draws += RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		objects += RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		primitives += RenderingServer.viewport_get_render_info(viewport_rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		count += 1
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for value in frames:
		total += value
	var p95: float = sorted[clampi(int(ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)]
	var n := maxf(float(count), 1.0)
	print("[wayside-layers] %s frame_avg=%.2f p95=%.2f cpu=%.2f gpu=%.2f draws=%.0f objects=%.0f primitives=%.0f" % [
		label, total / maxf(float(frames.size()), 1.0), p95, cpu / n, gpu / n,
		draws / n, objects / n, primitives / n])
