extends SceneTree
## Attributes the expensive persistent dossier to leaders, labels, and chrome.

const SAMPLE_FRAMES := 40
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
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for _i in 75:
		await process_frame
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var dossier := menu.get_node("CommandDossier") as PanelContainer
	await _sample("full", rid)

	var leaders: Array[CanvasItem] = []
	_collect_leaders(dossier, leaders)
	for item in leaders:
		item.visible = false
	await _sample("no_leaders", rid)
	for item in leaders:
		item.visible = true

	var labels: Array[CanvasItem] = []
	_collect_labels(dossier, labels)
	for item in labels:
		item.visible = false
	await _sample("no_labels", rid)
	for item in labels:
		item.visible = true

	var old_style := dossier.get_theme_stylebox("panel")
	dossier.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	await _sample("no_chrome", rid)
	dossier.add_theme_stylebox_override("panel", old_style)

	print("[menu-dossier] leaders=%d labels=%d" % [leaders.size(), labels.size()])
	RenderingServer.viewport_set_measure_render_time(rid, false)
	menu.queue_free()
	await process_frame
	quit()


func _collect_leaders(node: Node, out: Array[CanvasItem]) -> void:
	if node.get_class() == "Control" and node.get_child_count() == 0 \
			and node.get_parent() is HBoxContainer \
			and node.get_parent().get_child_count() == 3:
		out.append(node as CanvasItem)
	for child in node.get_children():
		_collect_leaders(child, out)


func _collect_labels(node: Node, out: Array[CanvasItem]) -> void:
	if node is Label:
		out.append(node as CanvasItem)
	for child in node.get_children():
		_collect_labels(child, out)


func _sample(label: String, rid: RID) -> void:
	for _i in 7:
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
	print("[menu-dossier] %s cpu=%.3f gpu=%.3f draws=%.1f objects=%.1f primitives=%.1f" % [
		label, cpu / n, gpu / n, draws / n, objects / n, primitives / n])
