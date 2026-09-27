extends SceneTree
## Deterministic visual QA capture for map performance A/B changes.

const SHOT_DIR := "C:/Users/danie/.codex/visualizations/2026/09/03/01a0653e-8eae-7843-bff9-dd655b7455b4"
const SHOT_SEED := 20260903

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await create_timer(7.0).timeout
	var rs := root.get_node("RunState")
	rs.active_slot = -1
	rs.start_new_run("raider", 0, SHOT_SEED)
	rs.active_slot = -1
	rs.current_node_type = ""
	rs.current_encounter_id = ""
	rs.map_plate_cache.clear()
	var map: Node = load("res://scenes/map.tscn").instantiate()
	root.add_child(map)
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline and map.get("_march_tex") == null:
		await process_frame
	map.call("_set_view", 1.10, Vector2(1600, 900) * 0.5
		- (map.get("_player_pos") as Vector2) * 1.10)
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var label := "map_perf"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		label = String(args[0]).validate_filename()
	var out := "%s/%s.png" % [SHOT_DIR, label]
	var image: Image = root.get_texture().get_image()
	var err := image.save_png(out)
	print("[map-shot] %s err=%d size=%s" % [out, err, image.get_size()])
	map.queue_free()
	for _i in 5:
		await process_frame
	_done = true
	quit(0)
