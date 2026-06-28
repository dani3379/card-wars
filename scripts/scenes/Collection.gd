extends Control
## Collection.gd — the compendium: every card, relic, and potion in the game,
## browsable from the main menu (the Slay-the-Spire model). Three tabs:
##   CARDS   — real Card2D instances baked through the shared CardTextureCache
##             (pixel-identical to a card in hand; hover pops the detail panel).
##   RELICS  — every relic as a readable plaque (the run-HUD chip + name +
##             effect text laid out in the open, nothing hidden behind hover),
##             sectioned by tier with the tier halo as the quality cue.
##   POTIONS — same plaque pattern off PotionDB.
## `show_tab(name)` is public so screenshot probes can open a specific tab.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MENU_SCENE = "res://scenes/main_menu.tscn"

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

const RELIC_TIERS = [
	{"label": "Starting Relics", "tier": "starting"},
	{"label": "Combat Relics", "tier": "combat"},
	{"label": "Utility Relics", "tier": "utility"},
	{"label": "Boss Relics", "tier": "boss"},
]

const TABS = [
	{"id": "cards", "label": "CARDS"},
	{"id": "relics", "label": "RELICS"},
	{"id": "potions", "label": "POTIONS"},
]

var _scroll: ScrollContainer
var _content: VBoxContainer
var _tab_buttons: Dictionary = {}
var _current_tab: String = ""
# Bumped on every tab switch; the async card bake loop checks it after each
# await so switching tabs mid-bake abandons the stale build cleanly.
var _view_gen: int = 0


func _ready() -> void:
	GameTheme.add_atmosphere(self, "event")

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Left margin bumped 40→80 so the settings gear (top-left, ~62px wide) has
	# room without colliding with the section labels.
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	GameTheme.make_settings_gear(self)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	outer.add_child(header)

	var title := GameTheme.make_screen_title("COLLECTION")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var back_btn := GameTheme.make_back_button("BACK", Vector2(120, 40))
	back_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MENU_SCENE))
	header.add_child(back_btn)

	# Tab row — frameless text, left-aligned; the lit tab is gilt, the rest
	# wait dim. A thin tan rule seats the row (the chart language).
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 26)
	outer.add_child(tab_row)
	for t in TABS:
		var b := Button.new()
		b.flat = true
		b.text = t.label
		b.focus_mode = Control.FOCUS_NONE
		if GameTheme.font_display:
			b.add_theme_font_override("font", GameTheme.font_display)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(show_tab.bind(t.id))
		tab_row.add_child(b)
		_tab_buttons[t.id] = b
	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.50, 0.34, 0.30)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_scroll.add_child(_content)

	show_tab("cards")


func show_tab(tab: String) -> void:
	if tab == _current_tab:
		return
	_current_tab = tab
	_view_gen += 1
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		b.add_theme_color_override("font_color",
			GameTheme.GILT_BRIGHT if id == tab else Color(0.60, 0.53, 0.42))
	for child in _content.get_children():
		child.queue_free()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	match tab:
		"cards":
			_build_cards(_view_gen)
		"relics":
			_build_relics()
		"potions":
			_build_potions()


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", GameTheme.GILT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ── CARDS ────────────────────────────────────────────────────────────────────

func _build_cards(gen: int) -> void:
	# Pre-bake every card's static-display texture into CardTextureCache.
	# ~120 cards × 2 frames ≈ 4 s of one-time load; cards appear section-by-
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

		_content.add_child(_section_label("%s  (%d)" % [section.label, section_cards.size()]))

		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 24)
		_content.add_child(grid)

		section_cards.sort_custom(func(a, b): return a.get("cost", 0) < b.get("cost", 0))

		# Bake then add per card. Sequential so the SubViewport handles one
		# card at a time and the user sees cards appear top-down rather than
		# all popping in at the end of a 4-second freeze. Cards already in
		# the cache (e.g. revisiting after a combat) return immediately.
		for card_data in section_cards:
			await CardTextureCache.bake(card_data)
			if gen != _view_gen or not is_inside_tree():
				return  # user switched tabs / hit Back during bake
			var card = CARD_SCENE.instantiate()
			card.card_data = card_data.duplicate(true)
			card.card_id = card_data.get("id", "")
			# is_on_battlefield = true → no drag, no hover scale; just the
			# detail popup, matching the pre-existing gallery behaviour.
			card.is_on_battlefield = true
			card.live_baked_mode = true
			grid.add_child(card)


# ── RELICS ───────────────────────────────────────────────────────────────────

func _build_relics() -> void:
	for sec in RELIC_TIERS:
		var ids: Array[String] = RelicDB.get_relics_by_tier(sec.tier)
		if ids.is_empty():
			continue
		ids.sort_custom(func(a, b):
			return String(RelicDB.RELICS[a].get("name", a)) < String(RelicDB.RELICS[b].get("name", b)))
		_content.add_child(_section_label("%s  (%d)" % [sec.label, ids.size()]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 12)
		_content.add_child(grid)
		for rid in ids:
			var r: Dictionary = RelicDB.get_relic(rid)
			grid.add_child(_make_plaque(
				GameTheme.make_relic_chip(rid, 56),
				String(r.get("name", rid)), String(r.get("desc", "")),
				RelicDB.get_tier_color(rid)))


# ── POTIONS ──────────────────────────────────────────────────────────────────

func _build_potions() -> void:
	var ids: Array[String] = PotionDB.all_ids()
	_content.add_child(_section_label("Potions  (%d)" % ids.size()))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)
	for pid in ids:
		var p: Dictionary = PotionDB.get_potion(pid)
		var tint: Color = p.get("color", Color.WHITE)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = PotionDB.icon_for(pid)
		# The generic HUD bottle is a neutral painting — the per-potion color
		# is the identity, same tinting the run HUD applies.
		if icon.texture == GameTheme.tex_hud_potion:
			icon.modulate = tint
		grid.add_child(_make_plaque(icon,
			String(p.get("name", pid)), String(p.get("desc", "")), tint))


# ── Shared plaque tile ───────────────────────────────────────────────────────

func _make_plaque(icon_node: Control, name_text: String, desc_text: String,
		accent: Color) -> PanelContainer:
	# Dark-ink tile with an accent left rule (the bark-scrim / map-tooltip
	# language): icon, gilt name, dim effect text — readable without hovering.
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(478, 86)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.065, 0.052, 0.042, 0.80)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.set("border_width_left", 3)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		sb.set(k, 10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	tile.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	tile.add_child(row)

	icon_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon_node)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = name_text
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", Color(0.90, 0.84, 0.73, 1.0))
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)

	return tile
