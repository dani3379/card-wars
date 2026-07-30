extends Node
## _shot_anim_pass.gd — visual check for the 2026-07-11 shell animation pass
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_anim_pass.tscn
## Shoots the Shop and the elite Reward twice each: mid-entrance (~0.18s, the
## deal-in stagger should be visibly in-flight — tiles at different alphas)
## and settled (~1.4s, everything at rest). Outputs tools/screenshot/_anim_*.png

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	RunState.start_new_run("raider", 0, 4242)
	RunState.gold = 300
	await get_tree().process_frame

	var shop = load("res://scenes/shop.tscn").instantiate()
	get_tree().root.add_child(shop)
	await get_tree().create_timer(0.18).timeout
	await _shoot("shop_mid")
	await get_tree().create_timer(1.3).timeout
	await _shoot("shop_settled")
	shop.queue_free()
	await get_tree().process_frame

	RunState.current_node_type = "elite"
	var rw = load("res://scenes/reward.tscn").instantiate()
	get_tree().root.add_child(rw)
	await get_tree().create_timer(0.20).timeout
	await _shoot("reward_mid")
	await get_tree().create_timer(1.3).timeout
	await _shoot("reward_settled")
	rw.queue_free()
	await get_tree().process_frame

	# Event page (R4 2026-07-16 — kit entrance: title deal-in, prose write-on,
	# ladder fade stagger). Mid should catch the typewriter partway through.
	seed(4242)
	var ev = load("res://scenes/event.tscn").instantiate()
	get_tree().root.add_child(ev)
	await get_tree().create_timer(0.30).timeout
	await _shoot("event_mid")
	await get_tree().create_timer(1.4).timeout
	await _shoot("event_settled")

	print("ANIM_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_anim_%s.png" % tag)
	print("SAVED anim_", tag, " ", img.get_size())
