extends SceneTree
## Focused windowed layer-cost attribution for the Main Menu.

const SAMPLE_FRAMES := 45

var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.graphics_preset = "medium"
		settings.render_scale = 1.0
		settings.particles = true
		settings.reduce_motion = false
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for _i in 90:
		await process_frame
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _sample("full", rid)

	var cases: Array[Dictionary] = [
		{"name": "no_motion", "paths": [], "suspend": true},
		{"name": "no_ambient", "paths": ["Atmosphere/AmbientMotes"]},
		{"name": "no_embers", "paths": ["Atmosphere/MenuEmbers"]},
		{"name": "no_particles", "paths": ["Atmosphere/AmbientMotes", "Atmosphere/MenuEmbers"]},
		{"name": "no_frame", "paths": ["Atmosphere/Frame"]},
		{"name": "no_dossier", "paths": ["CommandDossier"]},
		{"name": "no_menu", "paths": ["Menu"]},
		{"name": "no_scrim", "paths": ["MenuScrim"]},
		{"name": "background_only", "paths": ["Atmosphere", "MenuScrim", "Menu", "CommandDossier"]},
	]
	for case in cases:
		var hidden: Array[CanvasItem] = []
		if bool(case.get("suspend", false)):
			menu._set_subscreen_motion_obscured(true)
		for path in case.paths:
			var item := menu.get_node_or_null(String(path)) as CanvasItem
			if item != null and item.visible:
				item.visible = false
				hidden.append(item)
		await _sample(String(case.name), rid)
		for item in hidden:
			item.visible = true
		if bool(case.get("suspend", false)):
			menu._set_subscreen_motion_obscured(false)
		for _i in 4:
			await process_frame

	RenderingServer.viewport_set_measure_render_time(rid, false)
	menu.queue_free()
	await process_frame
	quit()


func _sample(label: String, rid: RID) -> void:
	for _i in 8:
		await RenderingServer.frame_post_draw
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var objects := 0.0
	var primitives := 0.0
	for _i in SAMPLE_FRAMES:
		await RenderingServer.frame_post_draw
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var n := float(SAMPLE_FRAMES)
	print("[menu-layer] %s cpu=%.3f gpu=%.3f draws=%.1f objects=%.1f primitives=%.1f" % [
		label, cpu / n, gpu / n, draws / n, objects / n, primitives / n])
