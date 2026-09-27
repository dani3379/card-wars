extends SceneTree
## Deterministic Collection plaque visual QA capture. First user arg is tab id.

const SHOT_DIR := "C:/Users/danie/.codex/visualizations/2026/09/03/01a0653e-8eae-7843-bff9-dd655b7455b4"

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
	settings.particles = true
	settings.reduce_motion = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await process_frame
	await create_timer(7.0).timeout
	var tab := "relics"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and String(args[0]) in ["cards", "relics", "potions"]:
		tab = String(args[0])
	var scene: Node = load("res://scenes/collection.tscn").instantiate()
	root.add_child(scene)
	scene.call("show_tab", tab)
	DisplayServer.warp_mouse(Vector2i(960, 20))
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var out := "%s/collection_%s_shader.png" % [SHOT_DIR, tab]
	var image: Image = root.get_texture().get_image()
	var err := image.save_png(out)
	print("[collection-shot] %s err=%d size=%s" % [out, err, image.get_size()])
	scene.queue_free()
	for _i in 5:
		await process_frame
	_done = true
	quit(0)
