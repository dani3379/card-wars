extends Node
## Bakes the CoinProp painter (the Old King's mint — the coinage the event
## tables and the map purse already use) to a single canonical icon texture.
## BBCode `[img=N]` needs a FILE, not a painter, so inline gold glyphs cannot
## instance CoinProp directly; this is how they share the one mint.
##   Godot.exe --path "D:\Godot" res://tools/_bake_coin_icon.tscn
const OUT := "res://assets/icons/map/hud_gold_coin.png"
const SIZE := 256          # baked large; every consumer downsamples

func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var coin = preload("res://scripts/ui/painters/CoinProp.gd").new()
	# Face-on, upright, unworn: this is the UI register's coin, so it shows the
	# crowned profile square to the reader rather than a table prop's lie.
	coin.seed_text = "hud_mint"
	coin.lying = false
	coin.worn = false
	coin.tails = false
	coin.size = Vector2(SIZE, SIZE)
	vp.add_child(coin)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	# Trim to the drawn disc so the glyph has no dead padding — an [img=20] of a
	# padded square renders a coin far smaller than 20px next to the text.
	var used := img.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		img = img.get_region(used)
	img.save_png(OUT)
	print("[bake-coin] wrote %s  %dx%d (trimmed from %d)" % [OUT, img.get_width(), img.get_height(), SIZE])
	get_tree().quit()
