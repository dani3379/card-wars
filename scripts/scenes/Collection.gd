extends Control

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MENU_SCENE = "res://scenes/main_menu.tscn"

# Card Gallery — shows every card in CardDB.CARD_POOL grouped by rarity/type.
# Previously baked cards locally; now shares CardTextureCache with Combat so
# a card baked in the gallery is reused next time it shows up in hand.
# Display nodes are real Card2D instances with `live_baked_mode = true` +
# `is_on_battlefield = true`: the layout dispatches to the baked-overlay
# fast path (single TextureRect + overlay numerals), the is_on_battlefield
# flag disables the hand-card drag system, and Card2D's existing hover
# behaviour pops up the detail panel.

const SECTIONS = [
	{"label": "Starter", "rarity": "starter", "type": "creature"},
	{"label": "Common Creatures", "rarity": "common", "type": "creature"},
	{"label": "Uncommon Creatures", "rarity": "uncommon", "type": "creature"},
	{"label": "Rare Creatures", "rarity": "rare", "type": "creature"},
	{"label": "Starter Spells", "rarity": "starter", "type": "spell"},
	{"label": "Common Spells", "rarity": "common", "type": "spell"},
	{"label": "Uncommon Spells", "rarity": "uncommon", "type": "spell"},
	{"label": "Rare Spells", "rarity": "rare", "type": "spell"},
]


func _ready() -> void:
	GameTheme.add_atmosphere(self, "event")

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	outer.add_child(header)

	var title := GameTheme.make_screen_title("Card Gallery")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var back_btn := GameTheme.make_back_button("BACK", Vector2(120, 40), 16)
	back_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MENU_SCENE))
	header.add_child(back_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	# Pre-bake every card's static-display texture into CardTextureCache.
	# 122 cards × 2 frames ≈ 4 s of one-time load; cards appear section-by-
	# section as they bake. Cached entries from a previous Combat run return
	# instantly, so revisiting the gallery is fast.
	var all_cards: Array[Dictionary] = []
	for id in CardDB.CARD_POOL:
		all_cards.append(CardDB.CARD_POOL[id])

	for section in SECTIONS:
		var section_cards: Array[Dictionary] = []
		for c in all_cards:
			if c.get("rarity", "") == section.rarity and c.get("type", "") == section.type:
				section_cards.append(c)
		if section_cards.is_empty():
			continue

		var section_lbl := Label.new()
		section_lbl.text = "%s  (%d)" % [section.label, section_cards.size()]
		if GameTheme.font_display:
			section_lbl.add_theme_font_override("font", GameTheme.font_display)
		section_lbl.add_theme_font_size_override("font_size", 20)
		section_lbl.add_theme_color_override("font_color", GameTheme.GILT)
		section_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(section_lbl)

		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 24)
		content.add_child(grid)

		section_cards.sort_custom(func(a, b): return a.get("cost", 0) < b.get("cost", 0))

		# Bake then add per card. Sequential so the SubViewport handles one
		# card at a time and the user sees cards appear top-down rather than
		# all popping in at the end of a 4-second freeze. Cards already in
		# the cache (e.g. revisiting after a combat) return immediately.
		for card_data in section_cards:
			await CardTextureCache.bake(card_data)
			if not is_inside_tree():
				return  # user hit Back during bake
			var card = CARD_SCENE.instantiate()
			card.card_data = card_data.duplicate(true)
			card.card_id = card_data.get("id", "")
			# is_on_battlefield = true → no drag, no hover scale; just the
			# detail popup, matching the pre-existing gallery behaviour.
			card.is_on_battlefield = true
			card.live_baked_mode = true
			grid.add_child(card)
