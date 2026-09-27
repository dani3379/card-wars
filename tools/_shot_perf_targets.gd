extends SceneTree
## Focused visual QA capture for screens touched by the performance pass.
## User arg: main_menu, reward, or recruit.

const SHOT_DIR := "C:/Users/danie/.codex/visualizations/2026/09/03/01a0653e-8eae-7843-bff9-dd655b7455b4"
const RUN_SEED := 20260903

var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var target := "main_menu"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and String(args[0]) in ["main_menu", "reward", "recruit"]:
		target = String(args[0])
	var settings := root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = true
	settings.reduce_motion = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame

	var path := "res://scenes/main_menu.tscn"
	if target != "main_menu":
		var rs := root.get_node("RunState")
		rs.active_slot = -1
		rs.start_new_run("raider", 0, RUN_SEED)
		rs.active_slot = -1
		if target == "reward":
			rs.current_node_type = "elite"
			path = "res://scenes/reward.tscn"
		else:
			rs.current_node_type = "recruit"
			path = "res://scenes/recruit.tscn"
	var scene: Node = load(path).instantiate()
	root.add_child(scene)
	DisplayServer.warp_mouse(Vector2i(10, 10))
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var out := "%s/perf_%s.png" % [SHOT_DIR, target]
	var err := image.save_png(out)
	print("[perf-shot] %s err=%d size=%s" % [out, err, image.get_size()])
	scene.queue_free()
	for _i in 5:
		await process_frame
	quit(0 if err == OK else 1)
