extends Control
## Shop.gd — THE SUTLER'S WAGON, the market that follows the army. Buy cards,
## a relic, potions; sell ONE card per visit (the sutler's buy-back — he pays
## by weight, and lowballs). Prices: common 50g, uncommon 75g, rare 120g.
## Relic 100g. Potion 40g. Merchant's License relic gives 25% discount on buys.
##
## 2026-07-02 rework: the anonymous "SHOP" grew a persona (name + barks) and
## the flat "pay 50g to remove" service became the buy-back — same bounded
## paid-thinning knob, but it no longer contradicts the road's other prices
## (the retired Quartermaster's Scales PAID for removal while the shop
## charged). The colored-slab Buy rectangles under the cards are gone too —
## frameless gem-buttons in the menu/event language.

const MAP_SCENE = "res://scenes/map.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

const BASE_PRICES: Dictionary = {
	"common": 50, "uncommon": 75, "rare": 120,
}
const RELIC_COST := 100
const POTION_COST := 40
const POTION_HEAL := 8
# The sutler's buy-back: one card per visit, paid by Command weight. He pays
# less than the old Quartermaster did — the wagon runs on margin. Curses are
# scrap-rate.
const SELL_BASE := 10
const SELL_PER_COST := 8
const SELL_CURSE_PRICE := 5

# One line of the sutler's patter per visit — picked once in _ready so UI
# rebuilds (purchases) don't make him change the subject mid-sentence.
const BARKS: Array = [
	"\"Everything's for sale. Most of it was somebody's.\"",
	"\"Prices follow the army. Blame the army.\"",
	"\"No refunds. The road doesn't give them either.\"",
	"\"Paid in advance is the only tense I stock.\"",
]

var _card_stock: Array[String] = []
var _relic_stock: Array[String] = []
var _shop_potion_id: String = ""
var _discount: float = 1.0
var _sold_this_visit: bool = false
var _bark: String = ""
# Entrance choreography plays once per visit; purchase rebuilds re-lay the
# shelves without re-dealing them. Gold label rolls between builds.
var _entered: bool = false
var _gold_shown: int = -1
var _gold_label: Label = null
var _transaction_busy: bool = false
var _sell_card_nodes: Array[Control] = []


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	# Lift the painted tavern: the shop mood's outer-alpha (0.60) + vignette
	# (0.45) was crushing the background toward black. Raise the node modulate and
	# soften the atmosphere so the painting reads behind the shelves.
	var bg := get_node_or_null("Background")
	if bg != null:
		bg.self_modulate = Color(0.66, 0.66, 0.64, 1.0)
	GameTheme.add_atmosphere(self, "shop", true, {
		"vignette": 0.36,
		"grad_inner": Color(0.12, 0.09, 0.05, 0.18),
		"grad_outer": Color(0.03, 0.02, 0.01, 0.46),
	})
	AudioBank.play_music_random(["shop", "shop_b"])
	_discount = 0.75 if RunState.has_relic("merchants_license") else 1.0
	_bark = BARKS[randi() % BARKS.size()]
	_roll_stock()
	# Keep art decode + GPU card readbacks out of the shelf-construction frame.
	await ScenePreload.warm_card_ids(_card_stock)
	_build_ui()
	GameTheme.fade_in(self, 0.22)
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay (the run's safe exit), rather than
	# silently bailing the shop back to the map on a mis-tap.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _roll_stock() -> void:
	var act = RunState.get_act()
	_card_stock = []
	# Retry duplicate rolls instead of dropping the slot — the old loop rolled
	# exactly 4 times and silently stocked 3 cards whenever two rolls collided.
	var guard := 0
	while _card_stock.size() < 4 and guard < 40:
		guard += 1
		var rarity = _roll_shop_rarity(act)
		var pool = CardDB.cards_of_rarity(rarity)
		if pool.is_empty():
			continue
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
	_transaction_busy = false
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_screen_title("THE SUTLER'S WAGON", GameTheme.GILT_BRIGHT, GameTheme.FONT_TITLE)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 18
	title.offset_bottom = 74
	add_child(title)
	if not _entered:
		GameTheme.deal_in(title, 0.02)

	var gold_label = GameTheme.make_label("%d gold" % RunState.gold, 26, GameTheme.KEYWORD_GOLD, true)
	_gold_label = gold_label
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gold_label.offset_top = 78
	gold_label.offset_bottom = 112
	add_child(gold_label)
	if not _entered:
		GameTheme.deal_in(gold_label, 0.06)
	# The purse rolls to its new figure instead of teleporting — the spend/gain
	# reads even though the label itself is rebuilt with the screen.
	if _gold_shown >= 0 and _gold_shown != RunState.gold:
		GameTheme.tick_number(gold_label, _gold_shown, RunState.gold, "%d gold", 0.5)
	_gold_shown = RunState.gold

	# Card stock — real Card2D renders with a Buy button below (matches Reward).
	# Shelf label gets the chart's ruled-heading furniture so it reads as a
	# section of the page, not floating text.
	var cards_label = GameTheme.make_section_divider("Cards for Sale", GameTheme.DESC_DIM, 22)
	cards_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cards_label.offset_top = 120
	cards_label.offset_bottom = 152
	add_child(cards_label)
	if not _entered:
		GameTheme.deal_in(cards_label, 0.10)

	add_child(_make_stage_panel(Rect2(250, 148, 1100, 350),
		Color(0.64, 0.42, 0.20, 0.95)))

	var card_row = HBoxContainer.new()
	card_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card_row.offset_top = 160
	card_row.offset_bottom = 492
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
		card.live_baked_mode = true
		CardTextureCache.bake(data)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(card)

		var buy_btn = _make_buy_button("Buy — %dg" % price,
			RunState.gold >= price, _buy_card.bind(id, price, slot),
			"Need %d gold" % price)
		buy_btn.tooltip_text = data.desc
		buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(buy_btn)
		if not _entered:
			GameTheme.deal_in(slot, 0.08 + card_row.get_child_count() * 0.06)

	# Relic + Services — one centered row below the cards.
	var svc_label = GameTheme.make_section_divider("Relics & Services", GameTheme.DESC_DIM, 22)
	svc_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	svc_label.offset_top = 516
	svc_label.offset_bottom = 548
	add_child(svc_label)
	if not _entered:
		GameTheme.deal_in(svc_label, 0.28)

	add_child(_make_stage_panel(Rect2(350, 548, 900, 250),
		Color(0.76, 0.50, 0.26, 0.95)))

	var svc_row = HBoxContainer.new()
	svc_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	svc_row.offset_top = 558
	svc_row.offset_bottom = 786
	svc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	svc_row.add_theme_constant_override("separation", 40)
	add_child(svc_row)

	if _relic_stock.size() > 0:
		for id in _relic_stock:
			var price = _price(RELIC_COST)
			var btn = GameTheme.make_relic_card(id, Color(0.55, 0.30, 0.20),
				Vector2(264, 216), price)
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if RunState.gold >= price:
				btn.pressed.connect(_buy_relic.bind(id, price, btn))
			else:
				_make_unavailable_tile(btn, "Need %d gold" % price)
			svc_row.add_child(btn)
			if not _entered:
				GameTheme.deal_in(btn, 0.34)
			if RunState.gold >= price:
				GameTheme.hover_lift(btn)

	# Potion service: shop sells a single random potion type (rolled at
	# _roll_stock). Icon falls back to the generic potion sprite if no per-type
	# art exists.
	var potion_price = _price(POTION_COST)
	var pdata: Dictionary = PotionDB.get_potion(_shop_potion_id)
	var pname: String = pdata.get("name", "Healing Potion")
	var pdesc: String = pdata.get("desc", "Heal 8 HP.")
	var pcolor: Color = pdata.get("color", Color(0.25, 0.40, 0.20))
	# Same convention as PotionDB.icon_for: painted PNG wins untinted, the white
	# silhouette kit renders tinted by the potion's colour.
	var picon_path := "res://assets/icons/potions/%s.png" % _shop_potion_id
	var picon_tint := Color.WHITE
	if not ResourceLoader.exists(picon_path):
		var psvg := "res://assets/icons/potions/%s.svg" % _shop_potion_id
		if ResourceLoader.exists(psvg):
			picon_path = psvg
			picon_tint = pcolor
		else:
			picon_path = "res://assets/icons/downloaded/potion1.png"
	# Lead with the EFFECT + price (the icon already reads as a potion); the full
	# name rides in the tooltip instead of cramming a 3-line name/desc/price block.
	var potion = _make_service_slot(picon_path,
		"%s\nBuy — %dg" % [pdesc, potion_price],
		pcolor, picon_tint)
	potion.button.tooltip_text = "%s — %s" % [pname, pdesc]
	if RunState.has_downside("no_potions"):
		potion.label.text = "%s\nCan't buy potions (Temperance Vow)" % pname
		_make_unavailable_tile(potion.button, "No potions")
	elif RunState.gold < potion_price:
		_make_unavailable_tile(potion.button, "Need %d gold" % potion_price)
	elif not RunState.can_add_potion():
		potion.label.text = "%s\nPotion slots full" % pname
		_make_unavailable_tile(potion.button, "Slots full")
	else:
		potion.button.pressed.connect(_buy_potion.bind(potion_price, potion.slot))
	svc_row.add_child(potion.slot)
	if not _entered:
		GameTheme.deal_in(potion.slot, 0.42)
	if not RunState.has_downside("no_potions") and RunState.gold >= potion_price \
			and RunState.can_add_potion():
		GameTheme.hover_lift(potion.slot)

	# The sutler's buy-back — sell ONE card per visit, paid by weight. This is
	# the deck-thinning verb now (replaced "pay 50g to remove"): still bounded
	# per shop, but it's a trade with a person instead of a fee to a menu.
	var sell = _make_service_slot("res://assets/icons/downloaded/cards1.png",
		"The sutler buys\nSell 1 card — paid by Command cost",
		Color(0.45, 0.15, 0.15))
	sell.button.tooltip_text = "Sell 1 card per visit. He pays %d gold + %d per Command cost. Curses fetch %d gold. Gone for good." \
		% [SELL_BASE, SELL_PER_COST, SELL_CURSE_PRICE]
	if RunState.has_relic("scavengers_pouch"):
		sell.button.tooltip_text += " Your Sutler's Marker doubles his rates."
	if _sold_this_visit:
		sell.label.text = "The sutler buys\nOne a visit. He's bought his one."
		_make_unavailable_tile(sell.button, "Already sold")
	elif RunState.deck.size() <= 1:
		sell.label.text = "The sutler buys\nHe won't take your last card."
		_make_unavailable_tile(sell.button, "Last card")
	else:
		sell.button.pressed.connect(_start_sell_mode)
	svc_row.add_child(sell.slot)
	if not _entered:
		GameTheme.deal_in(sell.slot, 0.50)
	if not _sold_this_visit and RunState.deck.size() > 1:
		GameTheme.hover_lift(sell.slot)

	# The sutler's patter — bottom-left, out of the wares' way.
	var bark = GameTheme.make_label(_bark, 16, Color(0.72, 0.66, 0.55))
	bark.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bark.offset_left = 44
	bark.offset_right = 640
	bark.offset_top = -66
	bark.offset_bottom = -34
	bark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(bark)
	if not _entered:
		GameTheme.deal_in(bark, 0.54)

	# Leave button — gold pill with ← arrow, distinct from the buy buttons.
	# Centered off size.x (the 1600×900 stretch canvas) rather than a hardcoded
	# window pixel, so it stays put if the canvas changes.
	var leave_btn = GameTheme.make_back_button("Leave the Wagon", Vector2(220, 50), 20)
	leave_btn.anchor_left = 0.5
	leave_btn.anchor_right = 0.5
	leave_btn.offset_left = -110
	leave_btn.offset_right = 110
	leave_btn.offset_top = 822
	leave_btn.offset_bottom = 872
	leave_btn.pressed.connect(_leave_shop)
	add_child(leave_btn)
	if not _entered:
		GameTheme.deal_in(leave_btn, 0.58)
		GameTheme.hover_lift(leave_btn, 1.04)
	_entered = true


func _make_stage_panel(rect: Rect2, accent: Color) -> Panel:
	# Quiet backing shelf for wares: just enough document furniture to group the
	# cards/services without hiding the tavern painting.
	var pan := Panel.new()
	pan.position = rect.position
	pan.size = rect.size
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := GameTheme.make_panel_style(
		Color(0.045, 0.034, 0.026, 0.46),
		Color(accent.r, accent.g, accent.b, 0.42),
		1, 4, true, true)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	pan.add_theme_stylebox_override("panel", sb)
	return pan


func _make_buy_button(text: String, enabled: bool, on_press: Callable,
		deny_text: String = "") -> Button:
	# Frameless buy affordance (the menu/event language): a small gilt gem +
	# gilt text that brightens on hover. No box — these replaced the last
	# colored-slab rectangles on the screen. Disabled = dimmed, no hover.
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(200, 44)
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, empty)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var gem := TextureRect.new()
	var dtex := GameTheme.tex_icon_diamond
	if dtex != null:
		gem.texture = dtex
	gem.custom_minimum_size = Vector2(14, 14)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gem)

	var lbl := Label.new()
	lbl.text = text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	row.add_child(lbl)

	if enabled:
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var rest := GameTheme.GILT
		var hot := GameTheme.GILT_BRIGHT
		lbl.add_theme_color_override("font_color", GameTheme.IVORY)
		gem.modulate = Color(rest.r, rest.g, rest.b, 0.85)
		btn.mouse_entered.connect(func():
			lbl.add_theme_color_override("font_color", hot)
			gem.modulate = Color(hot.r, hot.g, hot.b, 1.0))
		btn.mouse_exited.connect(func():
			lbl.add_theme_color_override("font_color", GameTheme.IVORY)
			gem.modulate = Color(rest.r, rest.g, rest.b, 0.85))
		btn.pressed.connect(on_press)
	else:
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		lbl.add_theme_color_override("font_color", Color(0.52, 0.48, 0.42, 0.85))
		gem.modulate = Color(0.45, 0.42, 0.36, 0.5)
		btn.pressed.connect(_deny_transaction.bind(btn,
			deny_text if deny_text != "" else "Can't buy"))
	return btn


func _make_unavailable_tile(ctrl: Control, message: String) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	ctrl.self_modulate = Color(0.66, 0.60, 0.52, 0.78)
	ctrl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if ctrl is Button:
		(ctrl as Button).pressed.connect(_deny_transaction.bind(ctrl, message))


func _deny_transaction(ctrl: Control, message: String) -> void:
	if _transaction_busy:
		return
	if AudioBank != null:
		AudioBank.play_sfx("button_click", 0.02, -4.0, 0.72)
	var pos := Vector2(get_viewport_rect().size.x * 0.5, 92.0)
	if ctrl != null and is_instance_valid(ctrl):
		pos = ctrl.global_position + ctrl.size * 0.5
		if not (UserSettings != null and UserSettings.reduce_motion):
			ctrl.pivot_offset = ctrl.size * 0.5
			var tw := ctrl.create_tween()
			tw.tween_property(ctrl, "rotation", 0.035, 0.045)
			tw.tween_property(ctrl, "rotation", -0.035, 0.07)
			tw.tween_property(ctrl, "rotation", 0.0, 0.06)
			tw.parallel().tween_property(ctrl, "self_modulate",
				Color(1.0, 0.55, 0.42, 0.92), 0.06)
			tw.chain().tween_property(ctrl, "self_modulate",
				Color(0.66, 0.60, 0.52, 0.78), 0.16)
	GameTheme.spawn_floating_text(self, pos + Vector2(0, -18), message,
		Color(1.0, 0.45, 0.30), false)


func _make_service_slot(icon_path: String, text: String, color: Color,
		icon_tint: Color = Color.WHITE) -> Dictionary:
	# One cohesive parchment tile (same look as make_relic_card): warm panel +
	# gilt border with the icon stacked above the service text INSIDE the tile.
	# The `color` accent only tints the rest-state border so potion/removal read
	# as a matched set with the relic card beside them — not garish solid-color
	# pills in clashing hues. Returns {slot, button, label}: `slot` is added to
	# the row, `button` carries disabled/pressed wiring, `label` lets callers
	# swap the body text for disabled-state messaging.
	# Inked document tile (dark ink body + tan rule + ~4px corners + deep shadow),
	# the praised chart look enforced via the shared parchment panel helper. The
	# `color` accent only tints the rest-state border so potion/removal read as a
	# matched set with the relic card beside them — not pills in clashing hues.
	# Same stacked-tile skeleton as the relic card beside it (one Button hit
	# target + centered inset VBox) so potion/removal read as a matched set; only
	# the stylebox differs — the inked-parchment panel instead of the relic's
	# solid-fill button style.
	var panel_bg := Color(0.055, 0.048, 0.040, 0.96)
	var skel := GameTheme.make_tile_skeleton(Vector2(264, 216), 4)
	var btn: Button = skel.button
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var normal := GameTheme.make_panel_style(panel_bg,
		color.lerp(GameTheme.GILT, 0.55), 1, 4, true, true)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := GameTheme.make_panel_style(Color(0.085, 0.070, 0.052, 0.97),
		GameTheme.GILT_BRIGHT, 1, 4, true, true)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := GameTheme.make_panel_style(Color(0.045, 0.038, 0.032, 0.96),
		color.lerp(GameTheme.GILT, 0.55), 1, 4, true, true)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled := GameTheme.make_panel_style(Color(0.05, 0.045, 0.04, 0.85),
		Color(0.40, 0.30, 0.15, 0.55), 1, 4, true, true)
	btn.add_theme_stylebox_override("disabled", disabled)

	var col: VBoxContainer = skel.col

	var icon := TextureRect.new()
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.modulate = icon_tint
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(icon)

	var lbl := GameTheme.make_label(text, 19, GameTheme.IVORY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(lbl)
	# Long potion texts (4 wrapped lines + price) overflow the fixed 216px tile
	# and printed the last line through the bottom border — grow to fit.
	GameTheme.fit_tile_height(btn, col)

	return {"slot": btn, "button": btn, "label": lbl}


func _buy_card(id: String, price: int, slot: Control = null) -> void:
	if _transaction_busy or RunState.gold < price:
		return
	_transaction_busy = true
	var old_gold := RunState.gold
	RunState.gold -= price
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_spend(price)
	RunState.add_card(id)
	_card_stock.erase(id)
	# The bought ware dives into the player's pack (bottom-centre) before the
	# shelves re-lay — the purchase reads as taking a thing, not a menu refresh.
	if slot != null and is_instance_valid(slot):
		GameTheme.claim_pop(slot)
		await get_tree().create_timer(0.10).timeout
	await GameTheme.pocket_away(slot, _pack_point())
	_build_ui()


func _buy_relic(id: String, price: int, tile: Control = null) -> void:
	if _transaction_busy or RunState.gold < price:
		return
	_transaction_busy = true
	var old_gold := RunState.gold
	RunState.gold -= price
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_spend(price)
	RunState.add_relic(id)
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	_relic_stock.erase(id)
	if tile != null and is_instance_valid(tile):
		GameTheme.claim_pop(tile)
		await get_tree().create_timer(0.10).timeout
	await GameTheme.pocket_away(tile, _pack_point())
	_build_ui()


func _buy_potion(price: int, tile: Control = null) -> void:
	if _transaction_busy or RunState.gold < price:
		return
	if not RunState.add_potion(_shop_potion_id):
		return
	_transaction_busy = true
	var old_gold := RunState.gold
	RunState.gold -= price
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_spend(price)
	# Roll a new random potion so the slot doesn't immediately repeat — keeps
	# shop variety up if the player has gold for two potions.
	_shop_potion_id = PotionDB.roll_random_potion()
	if tile != null and is_instance_valid(tile):
		GameTheme.claim_pop(tile)
		await get_tree().create_timer(0.10).timeout
	await GameTheme.pocket_away(tile, _pack_point())
	_build_ui()


func _pack_point() -> Vector2:
	# Where bought wares dive to: the player's pack, just off the bottom edge.
	var vp := get_viewport_rect().size
	return Vector2(vp.x * 0.5, vp.y + 30.0)


func _leave_shop() -> void:
	if _transaction_busy:
		return
	_transaction_busy = true
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


func _update_gold_display(from_gold: int, to_gold: int) -> void:
	_gold_shown = to_gold
	if _gold_label == null or not is_instance_valid(_gold_label):
		return
	GameTheme.tick_number(_gold_label, from_gold, to_gold, "%d gold", 0.42)


func _spawn_gold_spend(price: int) -> void:
	# Centered floating "-Ng" so the player gets a beat for every purchase, even
	# though _build_ui() rebuilds the gold label below it.
	var vp := get_viewport_rect().size
	_spawn_coin_sparks(Vector2(vp.x * 0.5, 102.0), false)
	GameTheme.spawn_floating_text(self,
		Vector2(vp.x * 0.5, 90.0),
		"-%d g" % price,
		Color(1.0, 0.55, 0.18),
		true)
	if AudioBank != null:
		AudioBank.play_sfx("coin")


func _spawn_gold_gain(price: int) -> void:
	var vp := get_viewport_rect().size
	_spawn_coin_sparks(Vector2(vp.x * 0.5, 102.0), true)
	GameTheme.spawn_floating_text(self,
		Vector2(vp.x * 0.5, 90.0),
		"+%d g" % price,
		Color(1.0, 0.85, 0.30),
		false)
	if AudioBank != null:
		AudioBank.play_sfx("coin")


func _spawn_coin_sparks(pos: Vector2, gain: bool) -> void:
	if UserSettings != null and (not UserSettings.particles or UserSettings.reduce_motion):
		return
	if DisplayServer.get_name() == "headless":
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 210
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = 18 if gain else 12
	p.lifetime = 0.62
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, 430.0)
	p.initial_velocity_min = 150.0 if gain else 90.0
	p.initial_velocity_max = 300.0 if gain else 210.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.90, 0.45, 1.0))
	ramp.set_color(1, Color(0.95, 0.42, 0.12, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)


## The sutler weighs a card by its Command cost. Curses fetch scrap-rate —
## he'll haul anything, but he's not paying for bad luck.
func _sell_price(card_id: String) -> int:
	var price: int = SELL_CURSE_PRICE
	if not CardDB.is_curse(card_id):
		var data = CardDB.get_card_data(card_id)
		price = SELL_BASE + SELL_PER_COST * int(data.get("cost", 0))
	# Sutler's Marker relic: the buy-back pays double (curses included — he
	# honors the marker even on bad luck).
	if RunState.has_relic("scavengers_pouch"):
		price *= int(RelicDB.get_relic("scavengers_pouch").get("value", 2))
	return price


func _start_sell_mode() -> void:
	if _transaction_busy:
		return
	_transaction_busy = false
	_sell_card_nodes.clear()
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_label("Lay one on the counter. He pays by weight.",
		GameTheme.FONT_TITLE, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 26)
	title.size = Vector2(1000, 48)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var purse = GameTheme.make_label("%d gold" % RunState.gold, 22, GameTheme.KEYWORD_GOLD, true)
	_gold_label = purse
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	purse.position = Vector2(680, 62)
	purse.size = Vector2(240, 28)
	add_child(purse)
	GameTheme.deal_in(purse, 0.06)

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
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 4)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.live_baked_mode = true
		CardTextureCache.bake(data)
		wrapper.add_child(card_node)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_confirm_sell.bind(i, slot))
		wrapper.add_child(click_btn)
		slot.add_child(wrapper)
		# Price footer under each card — his figure, up front, like the scales.
		var footer = GameTheme.make_label("%d gold" % _sell_price(RunState.deck[i]),
			16, GameTheme.KEYWORD_GOLD)
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(footer)
		grid.add_child(slot)
		_sell_card_nodes.append(slot)
		# Quick ripple across the laid-out pack — capped so a 30-card deck
		# doesn't take seconds to appear.
		GameTheme.deal_in(slot, 0.04 + minf(float(i), 12.0) * 0.025)
		GameTheme.hover_lift(slot, 1.025)

	var cancel_btn = GameTheme.make_back_button("Keep your pack", Vector2(180, 40))
	cancel_btn.position = Vector2(720, 800)
	cancel_btn.pressed.connect(func():
		if not _transaction_busy:
			_build_ui())
	add_child(cancel_btn)
	GameTheme.deal_in(cancel_btn, 0.18)
	GameTheme.hover_lift(cancel_btn, 1.04)


func _confirm_sell(deck_index: int, slot: Control = null) -> void:
	# One a visit; never the last card. Both are also enforced on the tile,
	# but guard the commit against a stale grid.
	if _transaction_busy:
		return
	if _sold_this_visit or RunState.deck.size() <= 1 \
			or deck_index < 0 or deck_index >= RunState.deck.size():
		_build_ui()
		return
	_transaction_busy = true
	var price := _sell_price(RunState.deck[deck_index])
	_sold_this_visit = true
	var old_gold := RunState.gold
	RunState.remove_card_at(deck_index)
	RunState.gain_gold(price)
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_gain(price)
	if slot != null and is_instance_valid(slot) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(slot)
		for other in _sell_card_nodes:
			if other != slot and other is Control and is_instance_valid(other):
				var tw := (other as Control).create_tween()
				tw.tween_property(other, "modulate:a", 0.0, 0.18) \
					.set_ease(Tween.EASE_IN)
		await get_tree().create_timer(0.16).timeout
	var vp := get_viewport_rect().size
	# The sold card slides up onto the sutler's counter and out of the pack —
	# the trade has a direction (buys dive down to you, sales rise to him).
	await GameTheme.pocket_away(slot, Vector2(vp.x * 0.5, 40.0))
	_build_ui()
