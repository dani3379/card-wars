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
	{"label": "Common Armaments", "rarity": "common", "type": "armament"},
	{"label": "Uncommon Armaments", "rarity": "uncommon", "type": "armament"},
	{"label": "Rare Armaments", "rarity": "rare", "type": "armament"},
]

const RELIC_TIERS = [
	{"label": "Signature Relics", "tier": "starting"},
	{"label": "Combat Relics", "tier": "combat"},
	{"label": "Utility Relics", "tier": "utility"},
	{"label": "Boss Relics", "tier": "boss"},
	# Event relics are never rolled into reward pools — they're granted by
	# name from specific events. Without this section they were invisible in
	# the compendium (The Coin, Landed / A Verse of You / Warm Knucklebone /
	# The Sin-Eater's Crust).
	{"label": "Event Relics", "tier": "event"},
]

const TABS = [
	{"id": "cards", "label": "CARDS"},
	{"id": "relics", "label": "RELICS"},
	{"id": "potions", "label": "POTIONS"},
]

const CARD_TILE_SIZE := Vector2(225, 300)
const CARD_PLACEHOLDER_YIELD_EVERY := 36
const CARD_HYDRATE_YIELD_EVERY := 4
const CARD_VIRTUAL_REFRESH := 0.10
const CARD_WARM_MARGIN_SCREENS := 0.75
const CARD_COLD_MARGIN_SCREENS := 1.75

var _scroll: ScrollContainer
var _content: VBoxContainer
var _tab_buttons: Dictionary = {}
var _current_tab: String = ""
# Bumped on every tab switch; the async card bake loop checks it after each
# await so switching tabs mid-bake abandons the stale build cleanly.
var _view_gen: int = 0
var _card_jobs: Array[Dictionary] = []
var _card_hydration_gen: int = -1
var _card_virtual_accum := 0.0


func _ready() -> void:
	# Lift the crushed backdrop. Two crushers were stacking (the same pair the
	# GameOver page had): the .tscn pins Background.self_modulate to ~0.14
	# brightness, and the "event" mood lays a heavy vignette over that. The
	# result was a near-black void — there is a painted library back there
	# (collection_library.png) and nobody had ever seen it. The trophy room
	# gets a room. Kept well under the cards' own brightness so the collection
	# still reads as the subject.
	var bg := get_node_or_null("Background")
	if bg != null:
		bg.self_modulate = Color(0.40, 0.38, 0.42, 1.0)
	GameTheme.add_atmosphere(self, "event", true, {
		"vignette": 0.42,
		"grad_outer": Color(0.02, 0.015, 0.03, 0.46),
	})

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

	var title: VBoxContainer = GameTheme.make_screen_title("COLLECTION")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var back_btn: Button = GameTheme.make_back_button("BACK", Vector2(120, 40))
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
		# The lit-tab bar, parented to the button and pinned to its bottom
		# edge. Hidden until show_tab lights it.
		var mark := ColorRect.new()
		mark.name = "TabMark"
		mark.color = GameTheme.GILT_BRIGHT
		mark.visible = false
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.anchor_left = 0.0
		mark.anchor_right = 1.0
		mark.anchor_top = 1.0
		mark.anchor_bottom = 1.0
		mark.offset_left = 4
		mark.offset_right = -4
		mark.offset_top = -3
		mark.offset_bottom = 0
		b.add_child(mark)
		tab_row.add_child(b)
		_tab_buttons[t.id] = b
	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.50, 0.34, 0.30)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(rule)

	# The shelf the collection is laid out on. The painted library behind this
	# screen is deliberately lit (see _ready above), but it was showing through
	# every gap between tiles, so the cards competed with a tavern for the eye —
	# on the one screen whose entire subject is the cards. An ink plate under the
	# grid answers both at once: the room still frames the screen at the margins
	# and behind the title, and the cards read as paper laid on a dark table.
	# ChartPanelStyle's hand-cut edge and corner tacks keep it a document, not a
	# black box.
	var plate := PanelContainer.new()
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var plate_sb: StyleBox = GameTheme.make_panel_style(
		Color(0.055, 0.045, 0.038, 0.88),
		Color(0.60, 0.51, 0.34, 0.50), 2, 8, true)
	plate_sb.content_margin_left = 18
	plate_sb.content_margin_right = 12
	plate_sb.content_margin_top = 16
	plate_sb.content_margin_bottom = 16
	plate.add_theme_stylebox_override("panel", plate_sb)
	outer.add_child(plate)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The full rail, not the hairline: this screen is nothing BUT scrolling —
	# 130+ card tiles down a single column — so the bar is primary navigation
	# here, not the incidental side-list affordance style_thin_scrollbar serves.
	GameTheme.style_rail_scrollbar(_scroll)
	plate.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	_scroll.add_child(_content)

	show_tab("cards")


func _unhandled_input(event: InputEvent) -> void:
	# Esc = the BACK button: return to the main menu.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.fade_out_then_change_scene(self, MENU_SCENE)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# The compendium can touch the entire card/relic/potion library in one visit.
	# None of those textures are needed by the menu we return to, so release the
	# gallery's global strong references instead of carrying hundreds of MiB for
	# the rest of the session. Run/map warmers repopulate the small live set.
	CardTextureCache.clear()
	CardArtAliases.clear_runtime_caches()
	RelicDB.clear_icon_cache()
	PotionDB.clear_icon_cache()
	ScenePreload.invalidate_encounter_art_warm_state()


func show_tab(tab: String) -> void:
	if tab == _current_tab:
		return
	_current_tab = tab
	_view_gen += 1
	_card_jobs.clear()
	_card_hydration_gen = -1
	_card_virtual_accum = 0.0
	set_process(tab == "cards")
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var lit: bool = id == tab
		b.add_theme_color_override("font_color",
			GameTheme.GILT_BRIGHT if lit else Color(0.60, 0.53, 0.42))
		# The lit tab also carries a gilt bar seated on the row's rule. Colour
		# alone was doing all the work of saying which shelf you're looking at
		# — and doing it in two tones of the same gold.
		var mark: Control = b.get_node_or_null("TabMark")
		if mark != null:
			mark.visible = lit
	for child in _content.get_children():
		child.queue_free()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	match tab:
		"cards":
			_build_cards(_view_gen)
		"relics":
			_build_relics(_view_gen)
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
	# Do not instantiate Card2D until its bake exists. Card2D intentionally
	# falls back to the full ornate build when the cache is cold, which made
	# this screen pay the worst possible cost: render every card, wait two
	# frames for every bake, then build the visible card again. Lightweight
	# placeholders make the tab readable immediately; the cache hydrates them
	# into real cards in the background.
	var all_cards: Array[Dictionary] = []
	for id in CardDB.CARD_POOL:
		all_cards.append(CardDB.CARD_POOL[id])

	var jobs: Array[Dictionary] = []
	var placeholders_since_yield := 0
	for section in SECTIONS:
		var section_cards: Array[Dictionary] = []
		for c in all_cards:
			if c.get("rarity", "") == section.rarity and c.get("type", "") == section.type:
				section_cards.append(c)
		if section_cards.is_empty():
			continue

		_content.add_child(_section_label("%s  (%d)" % [section.label, section_cards.size()]))

		var grid := HFlowContainer.new()
		# Gutters measured, not chosen: the plate's padding and the scroll rail
		# eat 41px of the row, and at the old 22px h_separation six 225px writs
		# no longer fit — the grid dropped to five per row and left a card-wide
		# void down the right of the plate. 14 keeps six across with room to
		# spare, and tighter gutters suit a plate anyway: the tiles read as one
		# laid-out sheet instead of floating apart.
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 20)
		_content.add_child(grid)

		section_cards.sort_custom(func(a, b): return a.get("cost", 0) < b.get("cost", 0))

		for card_data in section_cards:
			var placeholder := _make_card_placeholder(card_data)
			grid.add_child(placeholder)
			jobs.append({
				"data": card_data.duplicate(true),
				"grid": grid,
				"node": placeholder,
				"state": "placeholder",
				"busy": false,
			})
			placeholders_since_yield += 1
			if placeholders_since_yield >= CARD_PLACEHOLDER_YIELD_EVERY:
				placeholders_since_yield = 0
				await get_tree().process_frame
				if gen != _view_gen or not is_inside_tree():
					return

	if gen != _view_gen or not is_inside_tree():
		return
	_card_jobs = jobs
	# Containers need one layout pass before global rects are meaningful.
	await get_tree().process_frame
	if gen == _view_gen and is_inside_tree():
		_refresh_card_virtual_window(gen)


func _process(delta: float) -> void:
	if _current_tab != "cards" or _card_jobs.is_empty():
		return
	_card_virtual_accum += delta
	if _card_virtual_accum < CARD_VIRTUAL_REFRESH:
		return
	_card_virtual_accum = fmod(_card_virtual_accum, CARD_VIRTUAL_REFRESH)
	_refresh_card_virtual_window(_view_gen)


func _card_virtual_rect(margin_screens: float) -> Rect2:
	if _scroll == null or not is_instance_valid(_scroll):
		return Rect2()
	var viewport_rect := _scroll.get_global_rect()
	var margin := viewport_rect.size.y * margin_screens
	return Rect2(
		Vector2(viewport_rect.position.x, viewport_rect.position.y - margin),
		Vector2(viewport_rect.size.x, viewport_rect.size.y + margin * 2.0))


func _card_job_intersects(job: Dictionary, rect: Rect2) -> bool:
	var node: Control = job.get("node", null)
	return node != null and is_instance_valid(node) and node.is_inside_tree() \
		and node.get_global_rect().intersects(rect)


func _refresh_card_virtual_window(gen: int) -> void:
	if gen != _view_gen or _current_tab != "cards" or not is_inside_tree():
		return
	var cold_rect := _card_virtual_rect(CARD_COLD_MARGIN_SCREENS)
	# Once a real card is well beyond the scroll window, put its cheap tile back.
	# This bounds both Card2D nodes and ImageTexture references no matter how far
	# through the 100+ card compendium the player scrolls.
	for i in range(_card_jobs.size()):
		var job: Dictionary = _card_jobs[i]
		if String(job.get("state", "")) != "card" \
				or _card_job_intersects(job, cold_rect):
			continue
		var card: Control = job.get("node", null)
		var grid: HFlowContainer = job.get("grid", null)
		if card == null or grid == null or not is_instance_valid(card) \
				or not is_instance_valid(grid):
			continue
		var insert_at := card.get_index()
		var placeholder := _make_card_placeholder(job.get("data", {}))
		grid.add_child(placeholder)
		grid.move_child(placeholder, insert_at)
		card.queue_free()
		job["node"] = placeholder
		job["state"] = "placeholder"
		job["busy"] = false
		_card_jobs[i] = job
	if _card_hydration_gen != gen:
		_hydrate_visible_card_tiles(gen)


func _gallery_hydration_valid(gen: int) -> bool:
	return gen == _view_gen and _current_tab == "cards" and is_inside_tree()


func _hydrate_visible_card_tiles(gen: int) -> void:
	_card_hydration_gen = gen
	# The dummy renderer never presents gallery textures and may not emit the
	# frame-post-draw signal used by CardTextureCache. Keep headless probes on
	# the immediately-built placeholder model instead of parking a coroutine.
	if DisplayServer.get_name() == "headless":
		_card_hydration_gen = -1
		return
	var hydrated_since_yield := 0
	while gen == _view_gen and _current_tab == "cards" and is_inside_tree():
		var warm_rect := _card_virtual_rect(CARD_WARM_MARGIN_SCREENS)
		var job_index := -1
		for i in range(_card_jobs.size()):
			var candidate: Dictionary = _card_jobs[i]
			if String(candidate.get("state", "")) == "placeholder" \
					and not bool(candidate.get("busy", false)) \
					and _card_job_intersects(candidate, warm_rect):
				job_index = i
				break
		if job_index < 0:
			break

		var job: Dictionary = _card_jobs[job_index]
		job["busy"] = true
		_card_jobs[job_index] = job
		var card_data: Dictionary = job.get("data", {})
		var loaded_art := false
		if not CardTextureCache.has_gallery(card_data):
			# Decode on the loader thread, flatten at native gallery resolution,
			# then release the source painting immediately.
			await CardArtAliases.prewarm_card_art(card_data)
			loaded_art = true
			if not _gallery_hydration_valid(gen):
				CardArtAliases.release_card_art(card_data)
				break
		var baked: Texture2D = await CardTextureCache.bake_gallery(
			card_data, _gallery_hydration_valid.bind(gen))
		if loaded_art:
			CardArtAliases.release_card_art(card_data)
		if gen != _view_gen or _current_tab != "cards" or not is_inside_tree():
			break

		job = _card_jobs[job_index]
		job["busy"] = false
		if baked == null:
			_card_jobs[job_index] = job
			continue
		var placeholder: Control = job.get("node", null)
		var grid: HFlowContainer = job.get("grid", null)
		# The user may have scrolled far away while the GPU snapshot completed.
		# Keep the placeholder rather than materializing an already-cold card.
		if placeholder != null and grid != null and is_instance_valid(placeholder) \
				and is_instance_valid(grid) \
				and _card_job_intersects(job,
					_card_virtual_rect(CARD_COLD_MARGIN_SCREENS)):
			var insert_at := placeholder.get_index()
			var card = CARD_SCENE.instantiate()
			card.card_data = card_data.duplicate(true)
			card.card_id = card_data.get("id", "")
			# No dragging/hover scaling; retain the detail popup used by the
			# previous gallery implementation.
			card.is_on_battlefield = true
			card.static_display = true
			card.live_baked_mode = true
			card.gallery_baked_mode = true
			grid.add_child(card)
			grid.move_child(card, insert_at)
			placeholder.queue_free()
			job["node"] = card
			job["state"] = "card"
		_card_jobs[job_index] = job

		hydrated_since_yield += 1
		if hydrated_since_yield >= CARD_HYDRATE_YIELD_EVERY:
			hydrated_since_yield = 0
			await get_tree().process_frame
	_card_hydration_gen = -1 if _card_hydration_gen == gen else _card_hydration_gen


func _make_card_placeholder(card_data: Dictionary) -> PanelContainer:
	# A GHOST of the illuminated writ, not a different object. The grid hydrates
	# real Card2D bakes in the background; until one lands, this stands in. The
	# old placeholder was a dark rectangle with a cost chip, a "2 / 3" text line
	# and a flat colour band where the painting goes — it shared NOTHING with the
	# card's silhouette, so a half-hydrated grid read as broken rather than
	# loading (and scrolling fast is exactly when you see them). This mirrors the
	# writ's furniture at the same proportions — art plate, name cartouche, rules
	# well, corner seals — in unlit ink, so a card resolving reads as the page
	# being illuminated. Still cheap: plain Panels and Labels, no seeded painters.
	var rarity := String(card_data.get("rarity", "common"))
	var accent: Color = GameTheme.rarity_color(rarity)
	var is_spell := String(card_data.get("type", "")) == "spell"

	var tile := PanelContainer.new()
	tile.custom_minimum_size = CARD_TILE_SIZE
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The sheet, held back so a hydrated card visibly lights up beside it.
	var sheet: Color = GameTheme.PARCHMENT_LIGHT.darkened(0.60)
	var sb: StyleBox = GameTheme.make_panel_style(sheet,
		Color(accent.r, accent.g, accent.b, 0.60), 2, 6, false)
	sb.set_content_margin_all(0.0)
	tile.add_theme_stylebox_override("panel", sb)

	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(body)

	var ink := Color(0.10, 0.078, 0.058, 1.0)
	var well: Color = GameTheme.PARCHMENT_LIGHT.darkened(0.34)

	# Art plate — the writ mounts the painting big across the top half.
	_ghost_panel(body, Rect2(11, 12, 203, 134), ink.lightened(0.05),
		Color(accent.r, accent.g, accent.b, 0.34), 1)
	# Name cartouche band.
	_ghost_panel(body, Rect2(11, 150, 203, 30), ink, Color(0, 0, 0, 0), 0)
	# Rules well.
	_ghost_panel(body, Rect2(13, 184, 199, 78), well, Color(0, 0, 0, 0), 0)

	var name_lbl := _ghost_label(body, Rect2(16, 154, 193, 22),
		String(card_data.get("name", card_data.get("id", ""))),
		16, GameTheme.GILT, HORIZONTAL_ALIGNMENT_CENTER, true)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_ghost_label(body, Rect2(20, 190, 185, 68),
		String(card_data.get("desc", "")), 14,
		Color(0.20, 0.15, 0.10, 0.92), HORIZONTAL_ALIGNMENT_CENTER, false, true)

	# Cost seal, top-left, riding the card edge exactly as the writ prints it.
	_ghost_seal(body, Rect2(4, 2, 38, 36), Color(0.16, 0.24, 0.42, 1.0),
		str(int(card_data.get("cost", 0))))

	if is_spell:
		# Spells declare a contract instead of stats — the writ's one-line footer.
		_ghost_label(body, Rect2(14, 268, 197, 20), "SPELL", 13,
			Color(0.62, 0.54, 0.42, 0.95), HORIZONTAL_ALIGNMENT_CENTER, true)
	else:
		_ghost_seal(body, Rect2(5, 258, 38, 36), Color(0.42, 0.33, 0.12, 1.0),
			str(int(card_data.get("atk", 0))))
		_ghost_seal(body, Rect2(182, 258, 38, 36), Color(0.44, 0.14, 0.12, 1.0),
			str(int(card_data.get("hp", 0))))
		# No rarity/keyword footer on creatures. The writ prints none — the footer
		# is a casting contract, so spells declare and creatures don't — and the
		# gap between the two stat seals is only ~139px, which clipped strings
		# like "Uncommon / Swift, Piercing, Doom, On Death" by 126px. It was
		# leftover debug furniture from the old placeholder either way.
	return tile


func _ghost_panel(parent: Control, rect: Rect2, bg: Color, border: Color,
		border_w: int = 0) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",
		GameTheme.make_panel_style(bg, border, border_w, 3, false))
	# Geometry AFTER add_child: entering the tree re-applies the node's minimum
	# size and clobbers a size assigned beforehand.
	parent.add_child(p)
	p.position = rect.position
	p.size = rect.size
	return p


func _ghost_label(parent: Control, rect: Rect2, text: String, size: int,
		color: Color, align: int, display_font: bool, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wrap mode BEFORE the size is applied. An unwrapped Label's minimum width is
	# its whole text, and minimum size wins over an assigned size — so setting
	# autowrap afterwards left the rules line running out past the card edge.
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.max_lines_visible = 4
	l.clip_text = not wrap
	var f: Font = GameTheme.font_display if display_font else GameTheme.font_body
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# Geometry AFTER add_child — a size set before entering the tree is replaced
	# by the node's minimum size, which left autowrap with no width to wrap at
	# (the rules line ran straight out of its well).
	parent.add_child(l)
	l.position = rect.position
	l.size = rect.size
	return l


func _ghost_seal(parent: Control, rect: Rect2, tint: Color, value: String) -> void:
	_ghost_panel(parent, rect, tint, Color(0.86, 0.78, 0.58, 0.55), 1)
	var l := _ghost_label(parent, Rect2(rect.position.x, rect.position.y + 6.0,
		rect.size.x, rect.size.y), value, 17, GameTheme.IVORY,
		HORIZONTAL_ALIGNMENT_CENTER, true)
	l.size.y = rect.size.y


func _make_cost_badge(cost: int, accent: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(30, 30)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs: StyleBox = GameTheme.make_panel_style(
		Color(0.10, 0.075, 0.050, 0.98),
		Color(accent.r, accent.g, accent.b, 0.82), 1, 15, false)
	bs.content_margin_left = 0
	bs.content_margin_right = 0
	bs.content_margin_top = 0
	bs.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", bs)
	var lbl := Label.new()
	lbl.text = str(cost)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if GameTheme.font_display:
		lbl.add_theme_font_override("font", GameTheme.font_display)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	return badge


# ── RELICS ───────────────────────────────────────────────────────────────────

func _build_relics(gen: int) -> void:
	# Built incrementally, like the cards tab. ~135 relic plaques — each one loads
	# an icon (PNG decode / SVG rasterize) and a shadowed frame — froze the whole
	# screen for the better part of a second when built in a single frame (long
	# enough that the OS flagged the window "not responding"). Yield to the UI
	# every few tiles so input stays live and the list fills in top-down; bail out
	# if the player switches tabs or hits Back mid-build (the _view_gen guard, same
	# contract as _build_cards).
	var since_yield := 0
	for sec in RELIC_TIERS:
		var ids: Array[String] = RelicDB.get_relics_by_tier(sec.tier)
		if ids.is_empty():
			continue
		ids.sort_custom(func(a, b):
			return String(RelicDB.RELICS[a].get("name", a)) < String(RelicDB.RELICS[b].get("name", b)))
		_content.add_child(_section_label("%s  (%d)" % [sec.label, ids.size()]))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_content.add_child(grid)
		for rid in ids:
			var r: Dictionary = RelicDB.get_relic(rid)
			grid.add_child(_make_plaque(
				GameTheme.make_relic_chip(rid, 56),
				String(r.get("name", rid)), String(r.get("desc", "")),
				RelicDB.get_tier_color(rid)))
			since_yield += 1
			if since_yield >= 8:
				since_yield = 0
				await get_tree().process_frame
				if gen != _view_gen or not is_inside_tree():
					return  # user switched tabs / left mid-build


# ── POTIONS ──────────────────────────────────────────────────────────────────

func _build_potions() -> void:
	var ids: Array[String] = PotionDB.all_ids()
	_content.add_child(_section_label("Potions  (%d)" % ids.size()))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
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
		# Silhouette icons carry identity via the potion colour (same tinting
		# the run HUD applies); painted per-potion art renders untinted.
		if not PotionDB.is_painted_icon(pid):
			icon.modulate = tint
		grid.add_child(_make_plaque(icon,
			String(p.get("name", pid)), String(p.get("desc", "")), tint))


# ── Shared plaque tile ───────────────────────────────────────────────────────

func _make_plaque(icon_node: Control, name_text: String, desc_text: String,
		accent: Color) -> PanelContainer:
	# Dark-ink tile with an accent left rule (the bark-scrim / map-tooltip
	# language): icon, gilt name, dim effect text — readable without hovering.
	var tile := PanelContainer.new()
	# 466, not 478, for the same reason the card gutters tightened: three plaques
	# have to clear the plate's padding and the scroll rail, and at 478 they no
	# longer did — the relic and potion shelves fell to two per row and left half
	# the plate empty.
	tile.custom_minimum_size = Vector2(466, 86)
	var sb: StyleBox = GameTheme.make_panel_style(
		Color(0.065, 0.052, 0.042, 0.80),
		Color(accent.r, accent.g, accent.b, 0.55), 1, 4, false)
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
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	desc_lbl.add_theme_font_size_override("font_size", GameTheme.MIN_LABEL_SIZE)
	desc_lbl.add_theme_color_override("font_color", Color(0.90, 0.84, 0.73, 1.0))
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)

	return tile
