extends Node
# Shot tool — 2026-07-09 removal slate card faces. Renders the reworked and new
# removal spells through the live Card2D chart_proto layout so the art aliases
# (sappers_charge→barricade, ballista_bolt→reposition, scatter_line→second_wind)
# and the longer crash-rule descs can be inspected on the real card face.
#
# Run WINDOWED (NOT --headless):
#   Godot.exe --path "D:\Godot" res://tools/_shot_removal_cards.tscn
# Output: tools/renders/removal_slate/<id>.png

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const OUT := "res://tools/renders/removal_slate/"
const PAD := 12
const IDS := ["shove", "sappers_charge", "ballista_bolt", "scatter_line", "earthquake"]


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
