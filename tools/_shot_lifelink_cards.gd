extends Node
# Shot tool — 2026-07-10 lifelink buff pass. Renders the three weak cards that
# gained Lifelink (plague_rat, berserker, husk) through the live Card2D
# chart_proto layout so the new keyword device (bottom margin) and the extended
# rules text can be inspected on the real card face. Husk is the crowded case:
# three registered devices (guardian / lifelink / on_death).
#
# Run WINDOWED (NOT --headless):
#   Godot.exe --path "D:\Godot" res://tools/_shot_lifelink_cards.tscn
# Output: tools/renders/lifelink_pass/<id>.png
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const OUT := "res://tools/renders/lifelink_pass/"
const PAD := 12
const IDS := ["plague_rat", "berserker", "husk"]


func _ready() -> void:
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var vp := SubViewport.new()
	vp.size = Vector2i(225 + PAD * 2, 300 + PAD * 2)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.149, 0.137, 0.169, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)

	for id in IDS:
		var d: Dictionary = CardDB.get_card_data(id)
		if d.is_empty():
			print("MISSING_CARD: ", id)
			continue
		var card = CARD_SCENE.instantiate()
		card.card_data = d.duplicate(true)
		card.card_id = str(id)
		card.is_on_battlefield = true
		card.static_display = true
		card.chart_proto = true
		vp.add_child(card)
		card.position = Vector2(PAD, PAD)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		var path: String = OUT + str(id) + ".png"
		img.save_png(path)
		print("SAVED: ", path)
		vp.remove_child(card)
		card.free()
	print("RENDER_DONE")
	get_tree().quit()
