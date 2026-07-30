extends Node
## _shot_stolen_slate.gd — renders the 2026-07-13 stolen-classics slate (7 new
## cards, base + forged rows) to a PNG for visual inspection:
##   Godot.exe --path "D:\Godot" res://tools/_shot_stolen_slate.tscn
## Output: tools/screenshot/_stolen_slate.png

const CARD_SCENE := preload("res://scenes/card_2d.tscn")
const IDS := ["grave_clutch", "pressed_man", "the_undying",
	"long_roll", "wolf_pits", "informer", "forgefire",
	"grand_melee", "giantfall", "blood_kin", "pit_brawler",
	"farmers_son", "great_bombard", "whisper_widow", "quartermaster"]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1300, 1010))

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Base faces only, 5 per row (forged variants are covered by the probe).
	for i in range(IDS.size()):
		var data: Dictionary = CardDB.get_card_data(IDS[i]).duplicate(true)
		var card = CARD_SCENE.instantiate()
		card.card_id = IDS[i]
		card.card_data = data
		card.static_display = true
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(card)
		card.position = Vector2(24 + (i % 5) * 252, 20 + int(i / 5.0) * 330)

	# Let art loads + layout settle before the shot.
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_stolen_slate.png")
	print("STOLEN_SLATE_SHOT_DONE")
	get_tree().quit()
