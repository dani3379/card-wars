extends Control
## Shop.gd — Buy cards, relics, healing potions. Remove cards for gold.
## Prices: common 50g, uncommon 75g, rare 120g. Removal 50g. Relic 100g. Potion 40g.
## Merchant's License relic gives 25% discount.

const MAP_SCENE = "res://scenes/map.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

const BASE_PRICES: Dictionary = {
	"common": 50, "uncommon": 75, "rare": 120,
}
const REMOVE_COST := 50
const RELIC_COST := 100
const POTION_COST := 40
const POTION_HEAL := 8

var _card_stock: Array[String] = []
var _relic_stock: Array[String] = []
var _shop_potion_id: String = ""
var _discount: float = 1.0


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "shop")
	AudioBank.play_music("shop")
	_discount = 0.75 if RunState.has_relic("merchants_license") else 1.0
	_roll_stock()
	_build_ui()
	GameTheme.make_settings_gear(self)


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
	_relic_stock = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
	if _relic_stock.size() > 1:
		_relic_stock = [_relic_stock[0]]
	_shop_potion_id = PotionDB.roll_random_potion()


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
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_screen_title("SHOP", GameTheme.GILT_BRIGHT)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 16
	title.offset_bottom = 68
	add_child(title)

	var gold_label = GameTheme.make_label("%d gold" % RunState.gold, 20, GameTheme.KEYWORD_GOLD)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gold_label.offset_top = 72
	gold_label.offset_bottom = 100
	add_child(gold_label)

	# Card stock — real Card2D renders with a Buy button below (matches Reward).
	var cards_label = GameTheme.make_label("Cards for Sale", GameTheme.FONT_SUBHEADER, GameTheme.DESC_DIM)
	cards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cards_label.offset_top = 104
	cards_label.offset_bottom = 132
	add_child(cards_label)

	var card_row = HBoxContainer.new()
	card_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card_row.offset_top = 140
	card_row.offset_bottom = 470
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 28)
	add_child(card_row)

	for id in _card_stock:
		var data = CardDB.get_card_data(id)
		var price = _price(BASE_PRICES.get(data.rarity, 50))
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 8)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		card_row.add_child(slot)

		var card = CARD_SCENE.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = id
		card.is_on_battlefield = true  # no drag / hover-scale; static gallery card
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(card)

		var color = Color(0.15, 0.12, 0.30) if data.type == "spell" else Color(0.20, 0.25, 0.35)
		var buy_btn = GameTheme.make_themed_button("Buy — %dg" % price, color,
			Vector2(160, 38), 15, data.desc)
		buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		buy_btn.disabled = RunState.gold < price
		buy_btn.pressed.connect(_buy_card.bind(id, price))
		slot.add_child(buy_btn)

	# Relic + Services — one centered row below the cards.
	var svc_label = GameTheme.make_label("Relics & Services", GameTheme.FONT_SUBHEADER, GameTheme.DESC_DIM)
	svc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	svc_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	svc_label.offset_top = 486
	svc_label.offset_bottom = 514
	add_child(svc_label)

	var svc_row = HBoxContainer.new()
	svc_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	svc_row.offset_top = 522
	svc_row.offset_bottom = 700
	svc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	svc_row.add_theme_constant_override("separation", 32)
	add_child(svc_row)

	if _relic_stock.size() > 0:
		for id in _relic_stock:
			var price = _price(RELIC_COST)
			var btn = GameTheme.make_relic_card(id, Color(0.55, 0.30, 0.20),
				Vector2(220, 150), price)
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.disabled = RunState.gold < price
			btn.pressed.connect(_buy_relic.bind(id, price))
			svc_row.add_child(btn)

	# Potion service: shop sells a single random potion type (rolled at
	# _roll_stock). Icon falls back to the generic potion sprite if no per-type
	# art exists.
	var potion_price = _price(POTION_COST)
	var pdata: Dictionary = PotionDB.get_potion(_shop_potion_id)
	var pname: String = pdata.get("name", "Healing Potion")
	var pdesc: String = pdata.get("desc", "Heal 8 HP.")
	var pcolor: Color = pdata.get("color", Color(0.25, 0.40, 0.20))
	var picon_path := "res://assets/icons/potions/%s.png" % _shop_potion_id
	if not ResourceLoader.exists(picon_path):
		picon_path = "res://assets/icons/downloaded/potion1.png"
	var potion = _make_service_slot(picon_path,
		"%s\n%s\nBuy — %dg" % [pname, pdesc, potion_price],
		pcolor)
	if RunState.has_downside("no_potions"):
		potion.button.disabled = true
		potion.label.text = "%s\nBlocked by Sozu" % pname
	elif RunState.gold < potion_price:
		potion.button.disabled = true
	elif not RunState.can_add_potion():
		potion.button.disabled = true
		potion.label.text = "%s\nPotion slots full" % pname
	potion.button.pressed.connect(_buy_potion.bind(potion_price))
	svc_row.add_child(potion.slot)

	# Card removal service
	var remove_price = _price(REMOVE_COST)
	var removal = _make_service_slot("res://assets/icons/downloaded/cards1.png",
		"Remove a Card\nBuy — %dg" % remove_price,
		Color(0.45, 0.15, 0.15))
	removal.button.disabled = RunState.gold < remove_price or RunState.deck.size() <= 1
	removal.button.pressed.connect(_start_remove_mode.bind(remove_price))
	svc_row.add_child(removal.slot)

	# Leave button — gold pill with ← arrow, distinct from the buy buttons.
	var leave_btn = GameTheme.make_back_button("Leave Shop", Vector2(180, 44))
	leave_btn.position = Vector2(710, 820)
	leave_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE))
	add_child(leave_btn)


func _make_btn(text: String, tooltip: String, color: Color, min_size: Vector2) -> Button:
	return GameTheme.make_themed_button(text, color, min_size, 13, tooltip)


func _make_service_slot(icon_path: String, text: String, color: Color) -> Dictionary:
	# One cohesive parchment tile (same look as make_relic_card): warm panel +
	# gilt border with the icon stacked above the service text INSIDE the tile.
	# The `color` accent only tints the rest-state border so potion/removal read
	# as a matched set with the relic card beside them — not garish solid-color
	# pills in clashing hues. Returns {slot, button, label}: `slot` is added to
	# the row, `button` carries disabled/pressed wiring, `label` lets callers
	# swap the body text for disabled-state messaging.
	var panel_bg := Color(0.20, 0.13, 0.09)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 150)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var normal := GameTheme.make_btn_style(panel_bg, color.lerp(GameTheme.GILT, 0.45), 10)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = panel_bg.lightened(0.10)
	hover.border_color = GameTheme.GILT_BRIGHT
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = panel_bg.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = panel_bg.darkened(0.30)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 8
	col.offset_bottom = -8
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var icon := TextureRect.new()
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(54, 54)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)

	var lbl := GameTheme.make_label(text, 12, GameTheme.IVORY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(lbl)

	return {"slot": btn, "button": btn, "label": lbl}


func _buy_card(id: String, price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	_spawn_gold_spend(price)
	RunState.add_card(id)
	_card_stock.erase(id)
	_build_ui()


func _buy_relic(id: String, price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	_spawn_gold_spend(price)
	RunState.add_relic(id)
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	_relic_stock.erase(id)
	_build_ui()


func _buy_potion(price: int) -> void:
	if RunState.gold < price:
		return
	if not RunState.add_potion(_shop_potion_id):
		return
	RunState.gold -= price
	_spawn_gold_spend(price)
	# Roll a new random potion so the slot doesn't immediately repeat — keeps
	# shop variety up if the player has gold for two potions.
	_shop_potion_id = PotionDB.roll_random_potion()
	_build_ui()


func _spawn_gold_spend(price: int) -> void:
	# Centered floating "-Ng" so the player gets a beat for every purchase, even
	# though _build_ui() rebuilds the gold label below it.
	var vp := get_viewport_rect().size
	GameTheme.spawn_floating_text(self,
		Vector2(vp.x * 0.5, 90.0),
		"-%d g" % price,
		Color(1.0, 0.55, 0.18),
		true)
	if AudioBank != null:
		AudioBank.play_sfx("coin")


func _start_remove_mode(price: int) -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_label("Choose a card to remove",
		GameTheme.FONT_HEADER, GameTheme.KEYWORD_GOLD)
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
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)

	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		wrapper.add_child(card_node)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_confirm_remove.bind(i, price))
		wrapper.add_child(click_btn)
		grid.add_child(wrapper)

	var cancel_btn = GameTheme.make_back_button("Cancel", Vector2(140, 40))
	cancel_btn.position = Vector2(740, 800)
	cancel_btn.pressed.connect(func(): _build_ui())
	add_child(cancel_btn)


func _confirm_remove(deck_index: int, price: int) -> void:
	if RunState.gold < price:
		return
	RunState.gold -= price
	_spawn_gold_spend(price)
	if RunState.has_relic("scavengers_pouch"):
		RunState.gain_gold(20)
		var vp := get_viewport_rect().size
		GameTheme.spawn_floating_text(self,
			Vector2(vp.x * 0.5, 140.0),
			"+20 g (Scavenger's Pouch)",
			Color(1.0, 0.85, 0.30),
			false)
	RunState.remove_card_at(deck_index)
	_build_ui()
