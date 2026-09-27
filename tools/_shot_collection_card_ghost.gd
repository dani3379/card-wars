extends SceneTree
## Visual QA capture for the deliberately unlit one-node card placeholders.

const OUT_PATH := "C:/Users/danie/.codex/visualizations/2026/09/03/01a0653e-8eae-7843-bff9-dd655b7455b4/collection_card_ghost.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings: Node = root.get_node("UserSettings")
	settings.graphics_preset = "medium"
	settings.render_scale = 1.0
	settings.adaptive_render_scale = false
	settings.particles = false
	settings.reduce_motion = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var packed: PackedScene = load("res://scenes/collection.tscn")
	var scene: Control = packed.instantiate()
	root.add_child(scene)
	# _build_cards has already yielded after its first placeholder batch. Keep its
	# generation valid but pause hydration so the capture shows the loading state.
	scene.set("_current_tab", "cards_visual_qa")
	var deadline: int = Time.get_ticks_msec() + 5000
	while (
		(scene.get("_card_jobs") as Array).is_empty()
		and Time.get_ticks_msec() < deadline
	):
		await process_frame
	await RenderingServer.frame_post_draw
	DisplayServer.warp_mouse(Vector2i(20, 20))
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(OUT_PATH)
	print("[collection-card-ghost-shot] path=%s error=%d jobs=%d" % [
		OUT_PATH, error, (scene.get("_card_jobs") as Array).size()])
	root.remove_child(scene)
	scene.free()
	for _i in 3:
		await process_frame
	quit(0 if error == OK else 1)
