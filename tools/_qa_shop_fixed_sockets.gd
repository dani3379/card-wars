extends SceneTree

var _started := false
var _fails := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _settle(frames := 4) -> void:
	for _i in frames:
		await process_frame


func _wait_for_child(host: Node, child_name: String, max_frames := 240) -> Node:
	for _i in max_frames:
		var found := host.get_node_or_null(child_name)
		if found != null:
			return found
		await process_frame
	return null


func _x_positions(row: Node) -> Array[float]:
	var out: Array[float] = []
	for child in row.get_children():
		if child is Control:
			out.append((child as Control).global_position.x)
	return out


func _same_positions(a: Array[float], b: Array[float]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > 0.5:
			return false
	return true


func _run() -> void:
	var rs: Node = root.get_node_or_null("RunState")
	rs.start_new_run("raider", 0, 9494)
	rs.gold = 9999
	var shop = load("res://scenes/shop.tscn").instantiate()
	root.add_child(shop)
	var card_row := await _wait_for_child(shop, "ShopCardGroup")
	var service_row := await _wait_for_child(shop, "ShopServiceGroup")
	await _settle(12)
	_check(card_row != null, "card shelf exists")
	_check(service_row != null, "service shelf exists")
	if card_row == null or service_row == null:
		quit(1)
		return

	_check(card_row.get_child_count() == shop.CARD_STOCK_SLOTS,
		"card shelf starts with four reserved sockets")
	_check(service_row.get_child_count() == 3,
		"service shelf starts with three reserved sockets")
	var card_x := _x_positions(card_row)
	var service_x := _x_positions(service_row)
	var deck_before: int = rs.deck.size()
	var first_id: String = shop._card_stock[0]
	var data: Dictionary = root.get_node("CardDB").get_card_data(first_id)
	var price: int = shop._price(int(shop.BASE_PRICES.get(
		String(data.get("rarity", "")), 50)))
	var bought_slot: Control = card_row.get_child(0)
	await shop._buy_card(first_id, price, bought_slot)
	await _settle(8)

	card_row = shop.get_node_or_null("ShopCardGroup")
	service_row = shop.get_node_or_null("ShopServiceGroup")
	_check(rs.deck.size() == deck_before + 1, "card purchase applies exactly once")
	_check(card_row != null and card_row.get_child_count() == shop.CARD_STOCK_SLOTS,
		"card purchase keeps all four sockets")
	_check(card_row != null and card_row.get_child(0).name == "ShopSoldCardSlot",
		"purchased socket becomes a SOLD docket")
	_check(card_row != null and _same_positions(card_x, _x_positions(card_row)),
		"untouched card sockets do not move")
	_check(service_row != null and _same_positions(service_x, _x_positions(service_row)),
		"card purchase does not move service sockets")

	# Exercise the relic-sold render independently of which random relic rolled;
	# bottled talisman opens a separate binding picker and is covered elsewhere.
	shop._relic_sold = true
	await shop._build_ui()
	await _settle(6)
	card_row = shop.get_node_or_null("ShopCardGroup")
	service_row = shop.get_node_or_null("ShopServiceGroup")
	_check(service_row != null and service_row.get_child_count() == 3,
		"sold relic keeps the three-slot service shelf")
	_check(service_row != null and _same_positions(service_x, _x_positions(service_row)),
		"potion and removal sockets do not recenter after relic sale")
	_check(card_row != null and _same_positions(card_x, _x_positions(card_row)),
		"relic sale does not move card sockets")

	shop.queue_free()
	await _settle()
	print("[shop-fixed-sockets] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
