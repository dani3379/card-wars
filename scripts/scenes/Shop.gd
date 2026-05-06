extends Control
## Shop.gd — Buy cards, relics, healing potions. Remove cards for gold.
## Prices: common 50g, uncommon 75g, rare 120g. Removal 50g. Relic 100g. Potion 40g.
## Merchant's License relic gives 25% discount.

const MAP_SCENE = "res://scenes/map.tscn"

const BASE_PRICES: Dictionary = {
	"common": 50, "uncommon": 75, "rare": 120,
}
const REMOVE_COST := 50
const RELIC_COST := 100
const POTION_COST := 40
const POTION_HEAL := 8

var _card_stock: Array[String] = []
var _relic_stock: Array[String] = []
var _discount: float = 1.0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	_discount = 0.75 if RunState.has_relic("merchants_license") else 1.0
	_roll_stock()
	_build_ui()


func _roll_stock() -> void:
	var act = RunState.get_act()
	_card_stock = []
	var count = 4
	for i in count:
		var rarity = _roll_shop_rarity(act)
		var pool = CardDB.cards_of_rarity(rarity)
		if pool.size() > 0:
			var pick = pool[randi() % pool.size()]
			if not _card_stock.has(pick):
				_card_stock.append(pick)
	_relic_stock = RelicDB.roll_relic_reward("combat", RunState.relics)
	if _relic_stock.size() > 1:
		_relic_stock = [_relic_stock[0]]


func _roll_shop_rarity(act: int) -> String:
	var roll = randf()
	match act:
		1: return "rare" if roll < 0.05 else ("uncommon" if roll < 0.30 else "common")
		2: return "rare" if roll < 0.15 else ("uncommon" if roll < 0.50 else "common")
		_: return "rare" if roll < 0.30 else ("uncommon" if roll < 0.65 else "common")


func _price(base: int) -> int:
	return int(base * _discount)


func _build_ui() -> void:
	for child in get_children():
		if child.name != "Background":
			child.queue_free()

	var title = Label.new()
	title.text = "SHOP"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(650, 20)
	title.size = Vector2(300, 45)
	add_child(title)

	var gold_label = Label.new()
	gold_label.text = "💰 %d gold" % RunState.gold
	gold_label.add_theme_font_size_override("font_size", 20)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.position = Vector2(650, 60)
	gold_label.size = Vector2(300, 30)
	add_child(gold_label)

	# Card stock
	var cards_label = Label.new()
	cards_label.text = "Cards for Sale"
	cards_label.add_theme_font_size_override("font_size", 18)
	cards_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	cards_label.position = Vector2(100, 110)
	add_child(cards_label)

	var card_row = HBoxContainer.new()
	card_row.position = Vector2(100, 140)
	card_row.add_theme_constant_override("separation", 16)
	add_child(card_row)

	for id in _card_stock:
		var data = CardDB.get_card_data(id)
		var price = _price(BASE_PRICES.get(data.rarity, 50))
		var text: String
		if data.get("type", "creature") == "spell":
			text = "%s\n%dm SPELL\n%s\n— %dg —" % [data.name, data.cost, _kw(data), price]
		else:
			text = "%s\n%dm %d/%d\n%s\n— %dg —" % [data.name, data.cost, data.atk, data.hp, _kw(data), price]
		var color = Color(0.15, 0.12, 0.30) if data.type == "spell" else Color(0.20, 0.25, 0.35)
		var btn = _make_btn(text, data.desc, color, Vector2(160, 140))
		btn.disabled = RunState.gold < price
		btn.pressed.connect(_buy_card.bind(id, price))
		card_row.add_child(btn)

	# Relic stock
	if _relic_stock.size() > 0:
		var relic_label = Label.new()
		relic_label.text = "Relic"
		relic_label.add_theme_font_size_override("font_size", 18)
		relic_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
		relic_label.position = Vector2(100, 300)
		add_child(relic_label)

		var relic_row = HBoxContainer.new()
		relic_row.position = Vector2(100, 330)
		relic_row.add_theme_constant_override("separation", 16)
		add_child(relic_row)

		for id in _relic_stock:
			var relic = RelicDB.get_relic(id)
			var price = _price(RELIC_COST)
			var btn = _make_btn("%s\n%s\n— %dg —" % [relic.name, relic.desc, price], "",
				Color(0.55, 0.30, 0.20), Vector2(200, 100))
			btn.disabled = RunState.gold < price
			btn.pressed.connect(_buy_relic.bind(id, price))
			relic_row.add_child(btn)

	# Potion
	var potion_label = Label.new()
	potion_label.text = "Services"
	potion_label.add_theme_font_size_override("font_size", 18)
	potion_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	potion_label.position = Vector2(100, 450)
	add_child(potion_label)

	var services_row = HBoxContainer.new()
	services_row.position = Vector2(100, 480)
	services_row.add_theme_constant_override("separation", 16)
	add_child(services_row)

	var potion_price = _price(POTION_COST)
	var potion_btn = _make_btn("Healing Potion\nHeal %d HP\n— %dg —" % [POTION_HEAL, potion_price], "",
		Color(0.25, 0.40, 0.20), Vector2(160, 90))
	potion_btn.disabled = RunState.gold < potion_price
	potion_btn.pressed.connect(_buy_potion.bind(potion_price))
	services_row.add_child(potion_btn)

	# Card removal
	var remove_price = _price(REMOVE_COST)
	var remove_btn = _make_btn("Remove a Card\n— %dg —" % remove_price, "",
		Color(0.45, 0.15, 0.15), Vector2(160, 90))
	remove_btn.disabled = RunState.gold < remove_price or RunState.deck.size() <= 1
	remove_btn.pressed.connect(_start_remove_mode.bind(remove_price))
	services_row.add_child(remove_btn)

	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.custom_minimum_size = Vector2(160, 40)
	leave_btn.position = Vector2(720, 820)
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.pressed.connect(func(): get_tree().change_scene_to_file(MAP_SCENE))
	add_child(leave_btn)


func _kw(data: Dictionary) -> String:
	if not data.has("keywords") or data.keywords.is_empty():
		return ""
	return ", ".join(data.keywords)


func _make_btn(text: String, tooltip: String, color: Color, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = min_size
	btn.text = text
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", 13)
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.bg_color = color
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn


func _buy_card(id: String, price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	RunState.add_card(id)
	_card_stock.erase(id)
	_build_ui()


func _buy_relic(id: String, price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	RunState.add_relic(id)
	_relic_stock.erase(id)
	_build_ui()


func _buy_potion(price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	RunState.potions += 1
	_build_ui()


func _start_remove_mode(price: int) -> void:
	for child in get_children():
		if child.name != "Background":
			child.queue_free()

	var title = Label.new()
	title.text = "Choose a card to remove"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)

	var scroll = ScrollContainer.new()
	scroll.position = Vector2(100, 80)
	scroll.size = Vector2(1400, 700)
	add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for i in range(RunState.deck.size()):
		var id = RunState.deck[i]
		var data = RunState.get_upgraded_card_data(i)
		var text: String
		if data.get("type", "creature") == "spell":
			text = "%s\n%dm SPELL" % [data.name, data.cost]
		else:
			text = "%s\n%dm %d/%d" % [data.name, data.cost, data.atk, data.hp]
		var color = Color(0.15, 0.12, 0.30) if data.type == "spell" else Color(0.20, 0.25, 0.35)
		var btn = _make_btn(text, data.desc, color, Vector2(140, 90))
		btn.pressed.connect(_confirm_remove.bind(i, price))
		grid.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 36)
	cancel_btn.position = Vector2(740, 800)
	cancel_btn.pressed.connect(func(): _build_ui())
	add_child(cancel_btn)


func _confirm_remove(deck_index: int, price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	if RunState.has_relic("scavengers_pouch"):
		RunState.gold += 20
	RunState.remove_card_at(deck_index)
	_build_ui()
