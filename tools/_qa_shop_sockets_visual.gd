extends Node


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	RunState.start_new_run("raider", 0, 9595)
	RunState.gold = 9999
	var shop = load("res://scenes/shop.tscn").instantiate()
	get_tree().root.add_child.call_deferred(shop)
	await get_tree().create_timer(1.8).timeout
	var row: HBoxContainer = shop.get_node_or_null("ShopCardGroup")
	if row != null and row.get_child_count() > 0:
		var id: String = shop._card_stock[1]
		var data: Dictionary = CardDB.get_card_data(id)
		var price: int = shop._price(int(shop.BASE_PRICES.get(
			String(data.get("rarity", "")), 50)))
		await shop._buy_card(id, price, row.get_child(1))
	await get_tree().create_timer(0.75).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_qa_shop_sold.png")
	print("SHOP_SOLD_SCREENSHOT ", img.get_size())
	get_tree().quit()
