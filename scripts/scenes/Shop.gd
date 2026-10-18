extends Control
## Shop.gd — THE TRADER'S WAGON, the market that follows the army. Buy cards,
## a relic, potions; strike ONE card out of the deck per visit, for a flat fee
## you PAY. Prices: common 50g, uncommon 75g, rare 120g. Relics use rarity
## pricing. Potion 40g. Merchant's License gives 25% off buys.
##
## 2026-07-02 rework: the anonymous "SHOP" grew a persona (name + barks), and
## the colored-slab Buy rectangles under the cards are gone — frameless
## gem-buttons in the menu/event language.
##
## 2026-09-16: the buy-back is GONE and the fee is back. Thinning is the
## strongest thing you can do to a deck in this genre; the wagon was paying you
## to do it. See the REMOVE_FEE block for the full reasoning and for the faucet
## that was opened to pay for it.

const MAP_SCENE = "res://scenes/map.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")

const BASE_PRICES: Dictionary = {
	"common": 50, "uncommon": 75, "rare": 120,
}
const RELIC_PRICES: Dictionary = {"common": 90, "uncommon": 120, "rare": 160}
const POTION_COST := 40
const CARD_STOCK_SLOTS := 4
const POTION_HEAL := 8
# THE PROVOST'S FEE — you PAY to strike a card out of the deck. One per visit.
#
# This replaced the sutler's buy-back on 2026-09-16, which paid the player
# 10 gold + 4 per Command cost for a card (curses 5). Two reasons, and the
# second is the one that decided it:
#
#   1. Thinning is the strongest thing you can do to a deck in this genre, and
#      here it was not merely free — it was INCOME. Nothing else on the road
#      pays you for improving.
#   2. THE OLD RATE WAS BACKWARDS. It was keyed to Command cost, so it paid
#      LEAST for exactly the cards a player wants gone (cost-1 starter chaff,
#      14 gold) and MOST for the cost-6 bombs nobody dumps (34 gold). The card
#      you most want to strike was the one he valued least. That inversion is
#      not tunable — it is what pricing removal by card power does.
#
# A FLAT fee has no inversion to fix: every card costs the same to strike, so
# the only question left is "is this deck slot worth 60 gold", which is the
# question the mechanic exists to ask.
#
# 60, against a 50-gold common and a ~50-gold fight: priced a little above the
# cheapest thing on the shelf, so thinning COMPETES with buying instead of
# being strictly additive. NOT escalating (Slay the Spire's 75/+25) — the
# one-per-visit cap and a route's ~4 shops already bound it at 4 strikes a run,
# and an escalator would need a new persisted counter to do what the cap does
# for free.
#
# THE FAUCET THAT PAYS FOR IT lives in Combat.gd's victory block: the three
# fight bases went 40/60/55 -> 50/70/65 in the same pass, ~+210 gold over a
# full 21-fight route against the ~84 gold of sale income removed here. Net
# +126 to a player who never strikes; roughly break-even for one who strikes
# twice. Deliberately NOT full compensation — a fee the run always affords is
# a fee that decides nothing.
const REMOVE_FEE := 60

# The "Relics & Services" shelf is ONE set of tiles — relic cards, the potion,
# and the provost's fee all share the same dark-parchment document tile
# (uniform size, gilt name → icon → body → price). The row used to mix a warm-
# brown relic card (make_btn_style, no tacks) against dark inked service tiles
# (make_panel_style, tacks) at two different widths; it read as three
# unfinished styles rather than a merchant's shelf. PARCHMENT matches the Reward
# screen's relic choices, so a relic looks the same wherever the road offers it.
# 220 tall was sized for icon + name + up to four wrapped lines of rule text.
# The rules moved to the hover, so the tile is re-cut to what it actually holds
# now (icon + name + price) instead of keeping a hole where the text used to be.
#
# 2026-07-21: every ware on the shelf is now mounted on its own framed chip at
# SVC_ICON_PX. The tiles read empty because the picture was small, not because
# the box was big — the relics ran through make_relic_card, which derives its
# icon from the BOX (min_size.y * 0.38), a recipe that only balances around a
# ~147px tile and left a 67px painting adrift in a 272-wide shelf slot. Sizing
# the picture first and cutting the box to it fills the same footprint.
const SVC_ICON_PX := 108
const SVC_TILE_SIZE := Vector2(272, 196)

# One line of the sutler's patter per visit — picked once in _ready so UI
# rebuilds (purchases) don't make him change the subject mid-sentence.
const BARKS: Array = [
	"\"Everything on these shelves is for sale.\"",
	"\"Prices rise during a war. Blame the war.\"",
	"\"No refunds. Choose carefully.\"",
	"\"I only accept payment in advance.\"",
]

var _card_stock: Array[String] = []
var _sold_card_ids: Dictionary = {}
var _relic_stock: Array[String] = []
var _relic_sold: bool = false
var _shop_potion_id: String = ""
var _discount: float = 1.0
## STRIKES TAKEN THIS VISIT, not a one-shot latch (2026-09-24).
##
## `REMOVE_FEE`'s own reasoning says the cap is safe because "a route's ~4 shops
## already bound it at 4 strikes a run". The route census measures **0.85 shops
## per act on route - about 2.5 a run** - so the real bound was ~2.5 strikes,
## not 4, and thinning quietly became about 40% scarcer than the price was set
## against. The 09-19 map pass also cut runs from a fixed 21 fights to 12-17, so
## the gold faucet sized as "+210 over a full 21-fight route" now pays about two
## thirds of that. Both numbers were right when written and were invalidated by
## a change in another file.
##
## MEASURED CONSEQUENCE: the starter deck never leaves. Across 100 finished runs
## the 10-card opener was still **50-62% of the finished deck**, and runs that
## died in act 1 ended only 28% new cards.
##
## Raising the CAP rather than dropping the fee keeps the pricing argument the
## comment makes - 60g sits just above the cheapest ware, so thinning still
## COMPETES with buying instead of being strictly additive - while restoring the
## strikes-per-run the cap was reasoned against. Two strikes is 120 gold at one
## counter, so the purse is the real limit.
const STRIKES_PER_VISIT := 2
var _strikes_this_visit: int = 0
var _bark: String = ""
# Entrance choreography plays once per visit; purchase rebuilds re-lay the
# shelves without re-dealing them. Gold label rolls between builds.
var _entered: bool = false
var _gold_shown: int = -1
var _gold_label: Label = null
var _transaction_busy: bool = false
var _removal_card_nodes: Array[Control] = []
var _removal_build_generation := 0


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
	AudioBank.play_music_random(["shop", "shop_b", "shop_c"])
	_discount = 0.75 if RunState.has_relic("merchants_license") else 1.0
	_bark = BARKS[randi() % BARKS.size()]
	_roll_stock()
	# _build_ui streams native 1x gallery snapshots before each static shelf card
	# appears. Prewarming the 3x gameplay class here doubled the work and made
	# the first oversized texture upload the screen's largest frame.
	await _build_ui(true)
	GameTheme.fade_in(self, 0.22)
	GameTheme.make_settings_gear(self)
	# The purse is the subject: the lesson is that gold is spent here AND earned
	# back here, and the buy-back is the only deck-thinning the game has. The
	# stalls themselves are labelled with their prices and teach themselves.
	TutorialCoach.teach(self, "shop_trade", [_gold_label])


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay (the run's safe exit), rather than
	# silently bailing the shop back to the map on a mis-tap.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _roll_stock() -> void:
	var act = RunState.get_act()
	_card_stock = []
	_sold_card_ids.clear()
	_relic_sold = false
	# Retry duplicate rolls instead of dropping the slot — the old loop rolled
	# exactly 4 times and silently stocked 3 cards whenever two rolls collided.
	var guard := 0
	while _card_stock.size() < CARD_STOCK_SLOTS and guard < 40:
		guard += 1
		var rarity = _roll_shop_rarity(act)
		var pool = CardDB.cards_of_rarity(rarity)
		if pool.is_empty():
			continue
		var pick = pool[randi() % pool.size()]
		if not _card_stock.has(pick):
			_card_stock.append(pick)
	# ONE relic on the shelf, not three (2026-07-28). The sutler used to stock two
	# field relics plus a campaign relic every visit, which — stacked on the hero
	# relic, the war chest, every General, the Reliquary and ten relic-paying
	# events — put a typical greedy route at 8-9 relics by the act-1 boss and a
	# best case at 11. Slay the Spire ships about four. A single shelf slot also
	# makes the purchase a decision again: it is this relic or a card, not a menu.
	_relic_stock = RelicDB.roll_field_relics(1, RunState.relics,
		RunState.current_hero_id)
	_shop_potion_id = PotionDB.roll_random_potion()


func _roll_shop_rarity(act: int) -> String:
	var roll = randf()
	match act:
		1: return "rare" if roll < 0.05 else ("uncommon" if roll < 0.30 else "common")
		2: return "rare" if roll < 0.15 else ("uncommon" if roll < 0.50 else "common")
		_: return "rare" if roll < 0.30 else ("uncommon" if roll < 0.65 else "common")


func _price(base: int) -> int:
	return int(base * _discount)


func _build_ui(stagger_initial_cards: bool = false) -> void:
	_removal_build_generation += 1
	var build_generation := _removal_build_generation
	var builder_alive := func() -> bool:
		return is_inside_tree() and build_generation == _removal_build_generation
	_transaction_busy = false
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			remove_child(child)
			child.queue_free()

	var title = GameTheme.make_screen_title("THE TRADER'S WAGON", GameTheme.GILT_BRIGHT, GameTheme.FONT_TITLE)
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

	# Reserve the complete shelf before the first await. Each ornate face is
	# hydrated inside its final-size slot behind a sleeve, so completion order can
	# never change the centred HBox width or shove an earlier card sideways.
	card_row.name = "ShopCardGroup"
	card_row.set_meta("coordinated_card_group", true)
	var stock_staged: Array[Dictionary] = []
	var cold_art_paths: Array[String] = []
	for id in _card_stock:
		var data: Dictionary = CardDB.get_card_data(id)
		if not CardTextureCache.has(data) and not CardTextureCache.has_gallery(data):
			var art_path := String(CardArtAliases.card_art_path(data))
			if art_path != "" and not cold_art_paths.has(art_path):
				cold_art_paths.append(art_path)

		var price := _price(int(BASE_PRICES.get(String(data.get("rarity", "")), 50)))
		var slot := VBoxContainer.new()
		slot.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H + 52.0)
		slot.add_theme_constant_override("separation", 8)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		card_row.add_child(slot)
		if _sold_card_ids.has(id):
			_fill_sold_card_slot(slot)
			continue


		var card_wrap := Control.new()
		card_wrap.name = "ShopCardSlot"
		card_wrap.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H)
		card_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_wrap.pivot_offset = card_wrap.custom_minimum_size * 0.5
		card_wrap.set_meta("coordinated_card_slot", true)
		card_wrap.draw.connect(_draw_shelf_shadow.bind(card_wrap))
		slot.add_child(card_wrap)
		var face_host := Control.new()
		face_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_wrap.add_child(face_host)
		face_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var back := _make_loading_card_back(card_row)
		card_wrap.add_child(back)
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var buy_btn := _make_buy_button("Buy — %dg" % price,
			RunState.gold >= price, _buy_card.bind(id, price, slot),
			"Need %d gold" % price)
		buy_btn.tooltip_text = String(data.get("desc", ""))
		buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		buy_btn.disabled = true
		buy_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(buy_btn)
		stock_staged.append({
			"id": id, "data": data, "wrap": card_wrap, "host": face_host,
			"back": back, "button": buy_btn,
		})

	# Start all cold art requests together, then retain the established one-face-
	# per-frame construction cadence behind the covers.
	if not cold_art_paths.is_empty():
		await CardArtAliases.prewarm_texture_paths(cold_art_paths)
		if not builder_alive.call():
			return

	var staged_cards: Array[Control] = []
	var staged_backs: Array[Control] = []
	var staged_buttons: Array[Button] = []
	var staged_wraps: Array[Control] = []
	var staged_rarities: Array[String] = []
	for entry in stock_staged:
		var data: Dictionary = entry["data"]
		if not CardTextureCache.has(data) and not CardTextureCache.has_gallery(data):
			await CardArtAliases.prewarm_card_art(data)
			if not builder_alive.call():
				CardArtAliases.release_card_art(data)
				return
			var baked_gallery := false
			if not CardTextureCache.has(data):
				await CardTextureCache.bake_gallery(data, builder_alive)
				baked_gallery = CardTextureCache.has_gallery(data)
			CardArtAliases.release_card_art(data)
			if not builder_alive.call():
				return
			if baked_gallery:
				await get_tree().process_frame
		if not builder_alive.call():
			return

		var card = CARD_SCENE.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = String(entry["id"])
		card.is_on_battlefield = true
		card.static_display = true
		card.live_baked_mode = true
		card.gallery_baked_mode = not CardTextureCache.has(data) \
			and CardTextureCache.has_gallery(data)
		card.visible = false
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(entry["host"] as Control).add_child(card)
		staged_cards.append(card)
		staged_backs.append(entry["back"] as Control)
		staged_buttons.append(entry["button"] as Button)
		staged_wraps.append(entry["wrap"] as Control)
		staged_rarities.append(String(data.get("rarity", "")))
		if stagger_initial_cards:
			await get_tree().process_frame
			if not builder_alive.call():
				return

	await _reveal_shop_card_group(staged_cards, staged_backs, staged_buttons,
		staged_wraps, staged_rarities, not _entered, builder_alive)

	# Relic + Services — one centered row below the cards.
	var svc_label = GameTheme.make_section_divider("Relics & Services", GameTheme.DESC_DIM, 22)
	svc_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	svc_label.offset_top = 516
	svc_label.offset_bottom = 548
	add_child(svc_label)
	if not _entered:
		GameTheme.deal_in(svc_label, 0.28)

	# The shelf panel hugs the re-cut tiles — it was 250 tall to contain the old
	# text-grown ones and left an empty band under the row once they shrank.
	#
	# ── AND THE WIDTH WAS THE OTHER HALF OF THAT (2026-09-03) ──
	# Only the HEIGHT was re-cut. The width stayed at 1500 from the text-grown
	# tiles, so a shelf 1500 wide carried 860 of content — ~320px of empty plate
	# at each end — while sitting directly under a Cards shelf that is 1100 wide
	# and nearly full. Two stacked shelves on one page, both centred, one jutting
	# 200px further out on each side than the other.
	# `roll_field_relics(1, ...)` caps this row at three tiles (relic + potion +
	# buy-back), so 1100 holds it with room to spare AND lands the two shelves on
	# the same left and right edges, which is what makes the screen read as one
	# page rather than two unrelated plates. Gate: `tools/_probe_alignment.gd`.
	add_child(_make_stage_panel(Rect2(250, 548, 1100, 218),
		Color(0.76, 0.50, 0.26, 0.95)))

	var svc_row = HBoxContainer.new()
	svc_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	svc_row.offset_top = 559
	svc_row.offset_bottom = 755
	svc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	svc_row.name = "ShopServiceGroup"
	svc_row.add_theme_constant_override("separation", 20)
	add_child(svc_row)

	if _relic_stock.size() > 0 and not _relic_sold:
		var relic_i := 0
		for id in _relic_stock:
			var rarity: String = RelicDB.get_relic_rarity(id)
			var price = _price(int(RELIC_PRICES.get(rarity, 90)))
			var r: Dictionary = RelicDB.get_relic(id)
			# Relics ride the SAME slot builder as the potion and the buy-back
			# now: the rule text lives in the shared hover tip, so every tile is
			# exactly SVC_TILE_SIZE and the prices share one baseline — and a
			# relic differs from a potion by what's painted on it, not by how
			# it's mounted. The chip carries the tier halo the shelf used to
			# lose whenever a ware wasn't a relic.
			var relic = _make_service_slot(
				GameTheme.make_relic_chip(id, SVC_ICON_PX),
				String(r.get("name", id)), String(r.get("desc", "")),
				"— %dg —" % price, RelicDB.get_tier_color(id))
			if RunState.gold >= price:
				relic.button.pressed.connect(_buy_relic.bind(id, price, relic.button))
			else:
				_set_tile_status(relic, "Need %d gold" % price)
				_make_unavailable_tile(relic.button, "Need %d gold" % price)
			svc_row.add_child(relic.slot)
			if not _entered:
				var relic_at: float = 0.34 + relic_i * 0.04
				GameTheme.deal_in(relic.slot, relic_at)
				# Same rolled-offer shine the reliquary and the spoils screen
				# give their relics. The tile is a Button, not a Container, so
				# it can carry the sunburst directly.
				GameTheme.rarity_reveal(relic.slot, rarity, relic_at + 0.36)
			relic_i += 1
			# No hover_lift — _make_service_slot's rich hover already owns scale.

	else:
		# Keep the relic hook in the row after purchase. Its SOLD docket is the
		# same size as a live service tile, so potion and removal never recenter.
		var sold_relic := _make_sold_relic_slot()
		svc_row.add_child(sold_relic.slot)
		if _entered:
			GameTheme.stamp_in(sold_relic.mark, 0.02, Color(0.92, 0.52, 0.30))

	# Potion service: shop sells a single random potion type (rolled at
	# _roll_stock).
	var potion_price = _price(POTION_COST)
	var pdata: Dictionary = PotionDB.get_potion(_shop_potion_id)
	var pname: String = pdata.get("name", "Healing Potion")
	var pdesc: String = pdata.get("desc", "Heal 8 HP.")
	var pcolor: Color = pdata.get("color", Color(0.25, 0.40, 0.20))
	# Chip → name → price, the same fixed stack as the relic tiles beside it; the
	# effect reads on hover. No tooltip_text — the rich hover replaces it, and
	# both at once double-reports the same line. make_potion_chip owns the
	# painted-PNG-wins-untinted / SVG-tints-by-colour convention, so the shop no
	# longer keeps a second copy of it to drift out of sync with PotionDB.icon_for.
	var potion = _make_service_slot(
		GameTheme.make_potion_chip(_shop_potion_id, SVC_ICON_PX),
		pname, pdesc, "— %dg —" % potion_price, pcolor)
	if RunState.has_downside("no_potions"):
		_set_tile_status(potion, "No potions (Temperance Vow)")
		_make_unavailable_tile(potion.button, "No potions (Temperance Vow)")
	elif RunState.gold < potion_price:
		_set_tile_status(potion, "Need %d gold" % potion_price)
		_make_unavailable_tile(potion.button, "Need %d gold" % potion_price)
	elif not RunState.can_add_potion():
		_set_tile_status(potion, "Potion belt full")
		_make_unavailable_tile(potion.button, "Potion belt full")
	else:
		potion.button.pressed.connect(_buy_potion.bind(potion_price, potion.slot))
	svc_row.add_child(potion.slot)
	if not _entered:
		GameTheme.deal_in(potion.slot, 0.42)
	# No hover_lift — _make_service_slot's rich hover already owns scale.

	# The provost's fee — strike ONE card out of the deck per visit, flat rate.
	# One figure for every card in the pack, so the tile can post its price the
	# same way the potion beside it does. The rule text belongs in the hover
	# body, where the relic rules also live.
	var strike_fee := _removal_fee()
	var strike_body := "Remove one card from your deck for %d gold. One per visit. Gone for good." \
		% strike_fee
	if RunState.has_relic("scavengers_pouch"):
		strike_body += " Your Trader's Marker has already halved the fee."
	var strike = _make_service_slot(
		# A purse changing hands — now the PLAYER'S. This chip was
		# assets/icons/downloaded/cards1.png: a raw icon ATLAS, eight unrelated
		# coloured glyphs in a grid, sitting in a gilt chip between a painted relic
		# and a painted potion. It is the only thing in the game still loaded out of
		# `icons/downloaded/`.
		_make_icon_chip("res://assets/icons/relics/coin_purse.png", SVC_ICON_PX),
		"Remove a Card", strike_body, "— %dg —" % strike_fee, Color(0.45, 0.15, 0.15))
	if _strikes_this_visit >= STRIKES_PER_VISIT:
		_set_tile_status(strike, "No more removals this visit")
		_make_unavailable_tile(strike.button, "No more removals this visit")
	elif RunState.deck.size() <= 1:
		_set_tile_status(strike, "Can't remove your last card")
		_make_unavailable_tile(strike.button, "Can't remove your last card")
	elif RunState.gold < strike_fee:
		_set_tile_status(strike, "Need %d gold" % strike_fee)
		_make_unavailable_tile(strike.button, "Need %d gold" % strike_fee)
	else:
		strike.button.pressed.connect(_start_removal_mode)
	svc_row.add_child(strike.slot)
	if not _entered:
		GameTheme.deal_in(strike.slot, 0.50)
	# No hover_lift — _make_service_slot's rich hover already owns scale.

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
	# Worded as a departure, but it is the only way on from this stop — so it
	# wears the forward-move plate, not the frameless retreat treatment.
	var leave_btn = GameTheme.make_primary_button("Leave the Wagon", Vector2(240, 50), 20)
	leave_btn.anchor_left = 0.5
	leave_btn.anchor_right = 0.5
	# Half the button's own width, not a leftover number: `make_primary_button`
	# stamps 240 into custom_minimum_size, and a rect narrower than that is
	# widened RIGHTWARD — so the ±110 the 220-wide back button left behind put
	# this plate 10px right of the centre it claims to sit on.
	leave_btn.offset_left = -120
	leave_btn.offset_right = 120
	leave_btn.offset_top = 822
	leave_btn.offset_bottom = 872
	leave_btn.pressed.connect(_leave_shop)
	GameTheme.arm_ui_press(leave_btn, "commit")
	add_child(leave_btn)
	if not _entered:
		GameTheme.deal_in(leave_btn, 0.58)
		GameTheme.hover_lift(leave_btn, 1.04)
	_entered = true


## The face-down back a shelf slot wears until its ornate face is hydrated, so
## the row's geometry is reserved before any card is built and a late arrival
## cannot re-centre the shelf. Twin of Recruit's helper of the same name — this
## screen already had the CARD_BACK_TEXTURE const and the call site; only the
## function itself was missing, which took Shop.gd (and with it the whole game)
## out of compilation.
func _make_loading_card_back(group: CanvasItem = null) -> TextureRect:
	var back := TextureRect.new()
	back.name = "LoadingBack"
	back.texture = CARD_BACK_TEXTURE
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(back, group)
	return back


## Renderer work may finish one face at a time; presentation never does. All
## backs close together, all ornate faces open together, then and only then do

## A purchased card leaves a physical vacancy on the shelf instead of removing
## a child from the centred row. The socket exactly matches a live card + buy
## line, so every untouched offer keeps its screen position for the whole visit.
func _fill_sold_card_slot(slot: VBoxContainer) -> void:
	slot.name = "ShopSoldCardSlot"
	slot.set_meta("fixed_shop_socket", true)
	var recess := Panel.new()
	recess.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H)
	recess.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	recess.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recess.add_theme_stylebox_override("panel", GameTheme.make_panel_style(
		Color(0.025, 0.020, 0.016, 0.82), Color(0.40, 0.25, 0.14, 0.70),
		2, 8, true, true))

	# Leave the ghost of the card back in the empty berth: the player can see
	# that this was a stocked socket, while the ink stamp makes its state final.
	var ghost := TextureRect.new()
	ghost.texture = CARD_BACK_TEXTURE
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ghost.offset_left = 9
	ghost.offset_top = 9
	ghost.offset_right = -9
	ghost.offset_bottom = -9
	ghost.modulate = Color(0.36, 0.29, 0.22, 0.22)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recess.add_child(ghost)

	var stamp := GameTheme.make_label("SOLD", 36, Color(0.88, 0.43, 0.27))
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.set_anchors_preset(Control.PRESET_CENTER)
	stamp.offset_left = -95
	stamp.offset_right = 95
	stamp.offset_top = -30
	stamp.offset_bottom = 30
	stamp.rotation = -0.08
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recess.add_child(stamp)
	slot.add_child(recess)

	var footer := GameTheme.make_label("PACKED", 18, GameTheme.DESC_DIM)
	footer.custom_minimum_size = Vector2(200, 44)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(footer)
	if _entered:
		GameTheme.stamp_in(stamp, 0.02, Color(1.0, 0.68, 0.36))
## the associated buttons accept input. Container geometry is never animated.
func _reveal_shop_card_group(cards: Array[Control], backs: Array[Control],
		buttons: Array[Button], wraps: Array[Control], rarities: Array[String],
		announce_rarity: bool, validity: Callable) -> void:
	if not validity.call():
		return
	var snap := DisplayServer.get_name() == "headless" \
		or (UserSettings != null and UserSettings.reduce_motion)
	var animate_reveal := not snap and announce_rarity
	if animate_reveal:
		if AudioBank != null:
			AudioBank.play_sfx("card_draw", 0.04, -6.0)
		for back in backs:
			Motion.flip_out(back, 0.13)
		await get_tree().create_timer(maxf(Motion.time(0.13), 0.01)).timeout
		if not validity.call():
			return
	for i in range(cards.size()):
		var card: Control = cards[i]
		var back: Control = backs[i] if i < backs.size() else null
		if not animate_reveal and is_instance_valid(back):
			back.queue_free()
		if is_instance_valid(card):
			card.visible = true
			if animate_reveal:
				Motion.flip_in(card, 0.0, 0.17)
		if announce_rarity and i < wraps.size() and i < rarities.size():
			GameTheme.rarity_reveal(wraps[i], rarities[i],
				0.0 if snap else Motion.time(0.12))
	if animate_reveal:
		await get_tree().create_timer(maxf(Motion.time(0.17), 0.01)).timeout
		if not validity.call():
			return
	for button in buttons:
		if is_instance_valid(button):
			button.disabled = false
			button.mouse_filter = Control.MOUSE_FILTER_STOP


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


## A framed well for a ware with no chip factory of its own (the buy-back's
## painted sprite), cut to match make_relic_chip / make_potion_chip so it isn't
## the one unmounted picture on the shelf.
func _make_icon_chip(icon_path: String, px: int) -> Panel:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(px, px)
	chip.add_theme_stylebox_override("panel",
		GameTheme.make_btn_style(Color(0.06, 0.05, 0.04, 0.95), GameTheme.GILT, 4))
	if ResourceLoader.exists(icon_path):
		var tex := TextureRect.new()
		tex.texture = load(icon_path)
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["offset_left", "offset_top"]:
			tex.set(side, 7)
		for side in ["offset_right", "offset_bottom"]:
			tex.set(side, -7)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(tex)
	return chip


func _make_service_slot(chip: Control, title: String, body: String,
		footer: String, color: Color) -> Dictionary:
	# The one shelf recipe — relics, the potion and the removal fee are all built
	# here, so a ware differs from its neighbour by what's painted on it rather
	# than by how it's mounted: shared dark PARCHMENT fill, the shared
	# make_btn_style chamfer (no corner tacks), and the same stack — framed chip
	# → gilt name → gilt footer, with the rule text on the shared hover. The
	# `color` accent only tints the rest-state border so the tiles keep a faint
	# personal hue without breaking the set. Returns
	# {slot, button, title, label, footer}; `label` (the body) is what callers
	# swap for disabled-state messaging.
	var skel := GameTheme.make_tile_skeleton(SVC_TILE_SIZE, 3)
	var btn: Button = skel.button
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# Keep the border in the relics' gold family — only a whisper of the tile's
	# personal hue — so the five tiles read as one shelf, not five moods.
	var accent := color.lerp(GameTheme.GILT, 0.8)
	btn.add_theme_stylebox_override("normal",
		GameTheme.make_btn_style(GameTheme.PARCHMENT, accent, 10))
	btn.add_theme_stylebox_override("hover",
		GameTheme.make_btn_style(GameTheme.PARCHMENT.lightened(0.06),
			GameTheme.GILT_BRIGHT, 10))
	btn.add_theme_stylebox_override("pressed",
		GameTheme.make_btn_style(GameTheme.PARCHMENT.darkened(0.14), accent, 10))
	btn.add_theme_stylebox_override("disabled",
		GameTheme.make_btn_style(GameTheme.PARCHMENT.darkened(0.30),
			Color(0.40, 0.30, 0.15, 0.55), 10))

	var col: VBoxContainer = skel.col

	# make_relic_chip / make_potion_chip attach their OWN rich hover. Mute the
	# chip's, or the tip flickers as the cursor crosses from the tile onto the
	# picture and back — the tile is the one thing on the shelf that speaks.
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	var title_lbl := GameTheme.make_label(title, 18, GameTheme.KEYWORD_GOLD)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_lbl)

	# The effect line is NOT printed on the tile any more — it rides the shared
	# rich hover with the relics beside it. Inline bodies of 1-4 lines pushed
	# every tile to a different height and left the row's prices floating on four
	# different baselines; a shelf should read as a shelf.
	var status_lbl := GameTheme.make_label("", 16, Color(0.86, 0.52, 0.42))
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.visible = false
	col.add_child(status_lbl)

	var footer_lbl: Label = null
	if footer != "":
		footer_lbl = GameTheme.make_label(footer, GameTheme.FONT_BODY, GameTheme.GILT)
		footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(footer_lbl)

	# No fit_tile_height: the tile keeps exactly SVC_TILE_SIZE. hover_desc mode
	# owns `scale`, so callers must not also hover_lift these.
	GameTheme.attach_rich_hover(btn, title, body, "", accent, 1.03)

	return {"slot": btn, "button": btn, "title": title_lbl, "label": status_lbl,
		"status": status_lbl, "footer": footer_lbl}


## Empty relic hook with the exact shared service footprint. The marker stamps
## in after the bought relic has dived toward the pack.
func _make_sold_relic_slot() -> Dictionary:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(SVC_ICON_PX, SVC_ICON_PX)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", GameTheme.make_btn_style(
		Color(0.025, 0.020, 0.016, 0.88), Color(0.38, 0.24, 0.14, 0.62), 4))
	var mark := GameTheme.make_label("SOLD", 23, Color(0.88, 0.43, 0.27))
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.rotation = -0.08
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(mark)
	var sold := _make_service_slot(chip, "Relic Sold",
		"The hook is empty.", "— SOLD —", Color(0.45, 0.18, 0.12))
	var button: Button = sold.button
	button.disabled = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.self_modulate = Color(0.72, 0.64, 0.55, 0.86)
	sold["mark"] = mark
	return sold


## Show why a ware can't be bought, in the slot the eye already uses for price.
func _set_tile_status(tile: Dictionary, message: String) -> void:
	var status: Label = tile.get("status")
	if status != null:
		status.text = message
		status.visible = true
	var footer: Label = tile.get("footer")
	if footer != null:
		footer.visible = false


func _buy_card(id: String, price: int, slot: Control = null) -> void:
	if _transaction_busy or RunState.gold < price \
			or _sold_card_ids.has(id):
		return
	_transaction_busy = true
	var old_gold := RunState.gold
	RunState.gold -= price
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_spend(price)
	RunState.add_card(id)
	_sold_card_ids[id] = true
	# The bought ware dives into the player's pack (bottom-centre) before the
	# shelves re-lay — the purchase reads as taking a thing, not a menu refresh.
	if slot != null and is_instance_valid(slot):
		GameTheme.claim_pop(slot)
		await get_tree().create_timer(0.10).timeout
	await GameTheme.pocket_away(slot, _pack_point())
	_build_ui()


func _buy_relic(id: String, price: int, tile: Control = null) -> void:
	if _transaction_busy or RunState.gold < price or _relic_sold:
		return
	_transaction_busy = true
	var old_gold := RunState.gold
	RunState.gold -= price
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_spend(price)
	RunState.add_relic(id)
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	_relic_sold = true
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
		"-%dg" % price,
		Color(1.0, 0.55, 0.18),
		true)
	if AudioBank != null:
		AudioBank.play_sfx("coin")


func _spawn_gold_gain(price: int) -> void:
	var vp := get_viewport_rect().size
	_spawn_coin_sparks(Vector2(vp.x * 0.5, 102.0), true)
	GameTheme.spawn_floating_text(self,
		Vector2(vp.x * 0.5, 90.0),
		"+%dg" % price,
		Color(1.0, 0.85, 0.30),
		false)
	if AudioBank != null:
		AudioBank.play_sfx("coin")


func _spawn_coin_sparks(pos: Vector2, gain: bool) -> void:
	# Decorative — reduce_motion gates here; particles/headless gate in the
	# factory. A sale chinks harder than a spend.
	if UserSettings != null and UserSettings.reduce_motion:
		return
	Motion.burst(self, pos, "coin_spark", {
		"amount": 18 if gain else 12,
		"velocity_min": 150.0 if gain else 90.0,
		"velocity_max": 300.0 if gain else 210.0,
	})


## The provost's fee. ONE figure, the same for every card in the pack — it does
## not read the card at all, which is the whole point of the flat rate (see
## REMOVE_FEE). The Trader's Marker takes a percentage off, the same shape the
## Merchant's License uses on the shelf prices.
func _removal_fee() -> int:
	var fee := REMOVE_FEE
	if RunState.has_relic("scavengers_pouch"):
		var pct: int = int(RelicDB.get_relic("scavengers_pouch").get("value", 50))
		fee = int(round(fee * float(100 - pct) / 100.0))
	return maxi(fee, 0)


func _start_removal_mode() -> void:
	if _transaction_busy:
		return
	_removal_build_generation += 1
	var build_generation := _removal_build_generation
	_transaction_busy = false
	_removal_card_nodes.clear()
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	# The header stack has 80px before the scroll starts, and the two labels used
	# to be laid out as if it had more: a 48-tall FONT_TITLE box at y26 runs to
	# y74 and the 28-tall purse sat at y62, so the purse overlapped the title by
	# 12px AND its own bottom 10px fell under the ScrollContainer (added later,
	# so it draws on top). Both are packed against the 80px ceiling now: title
	# 14..54, purse 54..80, nothing overlapping and nothing under the grid.
	var title := GameTheme.make_label("Choose a card to remove",
		GameTheme.FONT_TITLE, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 14)
	title.size = Vector2(1000, 40)
	add_child(title)
	GameTheme.deal_in(title, 0.02)

	var purse := GameTheme.make_label("%d gold" % RunState.gold, 22,
		GameTheme.KEYWORD_GOLD, true)
	_gold_label = purse
	purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	purse.position = Vector2(680, 54)
	purse.size = Vector2(240, 26)
	add_child(purse)
	GameTheme.deal_in(purse, 0.06)

	var preparing := GameTheme.make_label("PREPARING THE DECK...", 15,
		Color(GameTheme.IVORY.r, GameTheme.IVORY.g, GameTheme.IVORY.b, 0.72))
	preparing.position = Vector2(104, 52)
	preparing.size = Vector2(360, 26)
	preparing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preparing)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(95, 80)
	scroll.size = Vector2(1410, 700)
	add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "ShopRemovalCardGroup"
	grid.set_meta("coordinated_card_group", true)
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)

	# Cancellation is live while a cold late-run deck is being flattened.
	# _build_ui advances the generation so stale cards cannot arrive behind it.
	var cancel_btn := GameTheme.make_back_button("Cancel", Vector2(180, 40))
	cancel_btn.position = Vector2(720, 800)
	cancel_btn.pressed.connect(func():
		if not _transaction_busy:
			_build_ui())
	add_child(cancel_btn)
	GameTheme.deal_in(cancel_btn, 0.18)
	GameTheme.hover_lift(cancel_btn, 1.04)

	var grid_ref: WeakRef = weakref(grid)
	var picker_alive := func() -> bool:
		if not is_inside_tree() or build_generation != _removal_build_generation \
				or _transaction_busy:
			return false
		var live_grid: GridContainer = grid_ref.get_ref() as GridContainer
		return live_grid != null and is_instance_valid(live_grid) \
			and not live_grid.is_queued_for_deletion()

	# Build the complete final grid synchronously out of cheap sleeves. The grid
	# reaches its final row/column geometry before any art/cache await, so a cold
	# late-run deck cannot visibly grow one card at a time.
	var staged: Array[Dictionary] = []
	var cold_art_paths: Array[String] = []
	var fee := _removal_fee()
	for i in range(RunState.deck.size()):
		var data: Dictionary = RunState.get_upgraded_card_data(i)
		if not CardTextureCache.has(data) and not CardTextureCache.has_gallery(data):
			var art_path := String(CardArtAliases.card_art_path(data))
			if art_path != "" and not cold_art_paths.has(art_path):
				cold_art_paths.append(art_path)

		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 4)
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		wrapper.name = "ShopRemovalCardSlot"
		wrapper.set_meta("coordinated_card_slot", true)
		var face_host := Control.new()
		face_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(face_host)
		face_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var back := _make_loading_card_back(grid)
		wrapper.add_child(back)
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var click_btn := Button.new()
		click_btn.flat = true
		click_btn.focus_mode = Control.FOCUS_NONE
		click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_btn.disabled = true
		click_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		click_btn.pressed.connect(_confirm_removal.bind(i, slot, build_generation))
		wrapper.add_child(click_btn)
		slot.add_child(wrapper)
		# The fee under each card. It is the same figure on all of them — that is
		# the flat rate being honest — but it belongs on the thing you click, and
		# it is painted in the SPEND colour so it cannot be misread as a payout
		# the way the buy-back's gold figure was.
		var footer = GameTheme.make_label("-%dg" % fee, 16, Color(1.0, 0.55, 0.18))
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(footer)
		grid.add_child(slot)
		_removal_card_nodes.append(slot)
		staged.append({
			"data": data, "slot": slot, "wrapper": wrapper,
			"host": face_host, "back": back, "button": click_btn,
		})

	preparing.text = "PREPARING THE DECK...  0 / %d" % RunState.deck.size()
	if not cold_art_paths.is_empty():
		await CardArtAliases.prewarm_texture_paths(cold_art_paths)
		if not picker_alive.call():
			return

	# Full ornate faces still hydrate one per presented frame to retain the old
	# hitch cap. They stay hidden behind the complete sleeve grid until all are
	# ready, so this internal cadence is no longer presentation order.
	var staged_cards: Array[Control] = []
	var staged_backs: Array[Control] = []
	var staged_buttons: Array[Button] = []
	var staged_wraps: Array[Control] = []
	var staged_rarities: Array[String] = []
	for i in range(staged.size()):
		var entry: Dictionary = staged[i]
		var data: Dictionary = entry["data"]
		if not CardTextureCache.has(data) and not CardTextureCache.has_gallery(data):
			await CardArtAliases.prewarm_card_art(data)
			if not picker_alive.call():
				CardArtAliases.release_card_art(data)
				return
			if not CardTextureCache.has(data):
				await CardTextureCache.bake_gallery(data, picker_alive)
			CardArtAliases.release_card_art(data)
		if not picker_alive.call():
			return
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = data
		card_node.card_id = String(data.get("id", ""))
		card_node.live_baked_mode = true
		card_node.gallery_baked_mode = not CardTextureCache.has(data) \
			and CardTextureCache.has_gallery(data)
		card_node.visible = false
		card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(entry["host"] as Control).add_child(card_node)
		staged_cards.append(card_node)
		staged_backs.append(entry["back"] as Control)
		staged_buttons.append(entry["button"] as Button)
		staged_wraps.append(entry["wrapper"] as Control)
		staged_rarities.append(String(data.get("rarity", "")))
		preparing.text = "PREPARING THE DECK...  %d / %d" % [
			i + 1, staged.size()]
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		if not picker_alive.call():
			return

	preparing.text = "UNSEALING THE DECK..."
	await _reveal_shop_card_group(staged_cards, staged_backs, staged_buttons,
		staged_wraps, staged_rarities, false, picker_alive)
	if not picker_alive.call():
		return
	for slot in _removal_card_nodes:
		if is_instance_valid(slot):
			GameTheme.hover_lift(slot, 1.025)
	if is_instance_valid(preparing):
		preparing.queue_free()


func _confirm_removal(deck_index: int, slot: Control = null,
		expected_generation: int = -1) -> void:
	# One a visit; never the last card; never on credit. All three are also
	# enforced on the tile, but guard the commit against a stale grid — the
	# purse check especially, since a picker opened while affordable outlives
	# nothing else that could spend gold, but the grid does survive a rebuild.
	# A displayed button also carries its build token. The successful commit
	# advances that token before its exit animation, making duplicate signals
	# from the queued old grid inert even when another strike remains this visit.
	if expected_generation >= 0 and expected_generation != _removal_build_generation:
		return
	if _transaction_busy:
		return
	var fee := _removal_fee()
	if _strikes_this_visit >= STRIKES_PER_VISIT or RunState.deck.size() <= 1 \
			or deck_index < 0 or deck_index >= RunState.deck.size() \
			or RunState.gold < fee:
		_build_ui()
		return
	_transaction_busy = true
	_removal_build_generation += 1
	_strikes_this_visit += 1
	var old_gold := RunState.gold
	RunState.gold -= fee
	RunState.remove_card_at(deck_index)
	_update_gold_display(old_gold, RunState.gold)
	_spawn_gold_spend(fee)
	if slot != null and is_instance_valid(slot) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(slot)
		for other in _removal_card_nodes:
			if other != slot and other is Control and is_instance_valid(other):
				var tw := (other as Control).create_tween()
				tw.tween_property(other, "modulate:a", 0.0, 0.18) \
					.set_ease(Tween.EASE_IN)
		await get_tree().create_timer(0.16).timeout
	var vp := get_viewport_rect().size
	# The struck card slides up over the counter and out of the pack — the
	# trade keeps its direction (bought wares dive down to you, cards you give
	# up rise away from you).
	await GameTheme.pocket_away(slot, Vector2(vp.x * 0.5, 40.0))
	_build_ui()


## The counter shadow under a shelved card. Same helper the recruit slate uses,
## reading the height `Motion.deal_card` writes to the wrapper — so the shadow
## spreads and pales while the card is in the air and snaps tight on contact.
func _draw_shelf_shadow(card_wrap: Control) -> void:
	Motion.card_shadow(card_wrap,
		Vector2(Card2D.CARD_W * 0.5, Card2D.CARD_H + 8.0),
		float(card_wrap.get_meta("deal_lift", 0.0)), 96.0,
		card_wrap.get_meta("deal_off", Vector2.ZERO))
