extends Node
## _shot_smear.gd — eyes for ▲2. Shoots the frame the smear is alive on, and the
## same body at rest, so the two can be read side by side.
##   Godot.exe --path "D:\Godot" res://tools/_shot_smear.tscn

func _ready() -> void:
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.05, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var host := Control.new()
	host.size = Vector2(600, 600)
	host.position = Vector2(560, 220)
	add_child(host)

	var card = load("res://scenes/card_2d.tscn").instantiate()
	card.card_id = "troll"
	card.card_data = CardDB.get_card_data("troll")
	card.is_on_battlefield = true
	card.compact_mode = true
	host.add_child(card)
	card.current_hp = 3
	card.current_atk = 2
	card.state.ready_to_swing = true
	card.position = Vector2(120, 200)
	await get_tree().create_timer(1.8).timeout

	await _grab("rest")
	card.play_attack_lunge(1.4)
	# Land inside the two-frame smear window: after the wind-up, early in the drive.
	await get_tree().create_timer(Motion.LUNGE_ANTICIPATION + 0.014).timeout
	await _grab("live")
	await get_tree().create_timer(0.6).timeout
	await _grab("after")
	get_tree().quit()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var s := float(img.get_width()) / 1600.0
	img.get_region(Rect2i(int(520 * s), int(280 * s), int(420 * s), int(420 * s))) \
		.save_png("res://tools/_shot_smear_%s.png" % tag)
	print("[shot] %s" % tag)
