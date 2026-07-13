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
		grid.add_theme_constant_override("h_separation", 22)
		grid.add_theme_constant_override("v_separation", 24)
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
	var rarity := String(card_data.get("rarity", "common"))
	var accent: Color = GameTheme.rarity_color(rarity)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = CARD_TILE_SIZE
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBox = GameTheme.make_panel_style(
		Color(0.075, 0.058, 0.043, 0.92),
		Color(accent.r, accent.g, accent.b, 0.70), 2, 6, false)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	tile.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	tile.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)

	top.add_child(_make_cost_badge(int(card_data.get("cost", 0)), accent))

	var name_lbl := Label.new()
	name_lbl.text = String(card_data.get("name", card_data.get("id", ""))).to_upper()
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_lbl)

	var type_lbl := Label.new()
	var is_spell := String(card_data.get("type", "")) == "spell"
	type_lbl.text = "SPELL" if is_spell else "%d / %d" % [
		int(card_data.get("atk", 0)), int(card_data.get("hp", 0))
	]
	if GameTheme.font_body:
		type_lbl.add_theme_font_override("font", GameTheme.font_body)
	type_lbl.add_theme_font_size_override("font_size", 13)
	type_lbl.add_theme_color_override("font_color", Color(0.91, 0.82, 0.62, 0.95))
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(type_lbl)

	var band := ColorRect.new()
	band.color = Color(accent.r, accent.g, accent.b, 0.16)
	band.custom_minimum_size = Vector2(0, 76)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(band)

	var desc_lbl := Label.new()
	desc_lbl.text = String(card_data.get("desc", ""))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc_lbl.max_lines_visible = 5
	if GameTheme.font_body:
		desc_lbl.add_theme_font_override("font", GameTheme.font_body)
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.88, 0.81, 0.69, 0.96))
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)

	var footer := Label.new()
	footer.text = _placeholder_footer(card_data)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.max_lines_visible = 2
	if GameTheme.font_body:
		footer.add_theme_font_override("font", GameTheme.font_body)
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.66, 0.58, 0.45, 0.92))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(footer)
	return tile


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


func _placeholder_footer(card_data: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(String(card_data.get("rarity", "common")).capitalize())
	var keywords: Array = card_data.get("keywords", [])
	if not keywords.is_empty():
		var names: Array[String] = []
		for kw in keywords:
			names.append(String(kw).capitalize())
		parts.append(", ".join(names))
	return " / ".join(parts)


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
		grid.add_theme_constant_override("h_separation", 14)
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
	tile.custom_minimum_size = Vector2(478, 86)
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
