extends Node
## Catches Motion.stamp_in mid-strike and at rest. A settled shot alone can't
## tell a correct stamp from one that never ran (or that scaled from the wrong
## pivot) — both look identical once the tween lands.

const SHOP_SCENE := "res://scenes/shop.tscn"


func _ready() -> void:
	# The prelude every windowed shot tool needs: let settings boot, drop SSAA
	# (otherwise the scene renders into the supersample SubViewport and the
	# root-window capture comes back as bare background), and pin the window.
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("stalwart")
	RunState.gold = 214
	await get_tree().process_frame
	var shop = load(SHOP_SCENE).instantiate()
	add_child(shop)
	# Mid-strike: the title should be oversized, pale and CENTRED on its own
	# midline (a bad pivot shows as the word hanging off to the right).
	# The shop fades in before it builds its HUD, so the strike happens some way
	# in — sample a burst rather than guessing one timestamp.
	await get_tree().create_timer(0.45).timeout
	for i in 5:
		await _capture("stamp_b%d" % i)
		await get_tree().create_timer(0.09).timeout
	await get_tree().create_timer(1.6).timeout
	await _capture("stamp_rest")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)


func _capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2,
		Image.INTERPOLATE_LANCZOS)
	image.save_png("res://tools/screenshot/_%s.png" % tag)
	print("  SAVED  ", tag, " ", image.get_size())
