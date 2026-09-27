extends SceneTree

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var settings := root.get_node("UserSettings")
	settings.reduce_motion = false
	settings.particles = false
	var net_match := root.get_node("NetMatch")
	net_match.local_hero = "raider"
	net_match.start_vs_bot(0, 1)
	net_match.match_seed = 20260909
	root.get_node("SkirmishState").reset()
	var screen: Control = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(screen)
	await RenderingServer.frame_post_draw
	_save("res://_perf_arsenal_sleeves.png")
	for _i in 5:
		await RenderingServer.frame_post_draw
	_save("res://_perf_arsenal_loaded.png")
	var row: HBoxContainer = screen.get("_ars_row")
	var first: Control = row.get_child(0)
	screen.call("_on_ars_pick", String(first.get_meta("ars_id", "")), true)
	await create_timer(0.14).timeout
	await RenderingServer.frame_post_draw
	_save("res://_perf_arsenal_flight.png")
	_done = true


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	var err := image.save_png(path)
	print("[arsenal-shot] saved=", path, " err=", err,
		" size=", image.get_size())
