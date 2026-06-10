extends "res://scripts/scenes/MapTerrain.gd"

# ── MAP VIEW — the live map screen ──────────────────────────────────────────
# MapTerrain draws the static campaign plate (Sicily, carved roads, political
# layer); this script layers the game on top: clickable site buttons (hover
# ring + tooltip with encounter/mutator intel), the node → scene flow, the
# top HUD (HP / gold / relics / potions / deck), the deck viewer, per-act
# meta-relic pickers, and the return-to-map save checkpoint.
# The previous parchment-chart implementation is preserved at
# tools/screenshot/MapView_parchment.gd.bak.

const COMBAT_SCENE := "res://scenes/combat.tscn"
const SHOP_SCENE := "res://scenes/shop.tscn"
const REST_SCENE := "res://scenes/rest.tscn"
const EVENT_SCENE := "res://scenes/event.tscn"
const TREASURE_SCENE := "res://scenes/treasure.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const CARD_SCENE := preload("res://scenes/card_2d.tscn")

const HIT_R := 26.0           # click radius, normal site chip
const BOSS_HIT := 46.0        # click radius, the keep

var _hud_root: Control = null


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	AudioBank.play_music("map")
	# No atmosphere overlay here: the chart plate carries its own mood, and
	# the menu-style vignette just dims it.
	await get_tree().process_frame
	build_map()
	_build_node_buttons()
	_build_top_hud()
	GameTheme.make_settings_gear(self)
	# Checkpoint: every return to the map captures post-room state (HP, gold,
	# deck changes, relics earned). Clear the room-in-progress fields first so a
	# later resume lands on the map rather than re-entering the room the player
	# just finished. visit_node still saves on entry, so a quit *during* a room
	# resumes back into that room.
	RunState.current_node_type = ""
	RunState.current_encounter_id = ""
	await _resolve_meta_pickers()
	RunState.save_run()


func _resolve_meta_pickers() -> void:
	# Bottled Talisman: catch-all bind. Reward/Shop/Treasure bind inline at
	# acquire; this covers Event-granted copies and rebinds if the bound card
	# was later removed. The helper no-ops when a valid binding already exists.
	if RunState.has_relic("bottled_talisman"):
		await GameTheme.bind_bottled_talisman(self)
	# Totem Pole: pick a keyword once per act.
	if RunState.has_relic("totem_pole") and RunState.totem_pole_act != RunState.get_act():
		var kw_opts := [
			{"label": "Thorns", "desc": "Friendlies deal 1 damage back when hit.",
				"color": Color(0.30, 0.45, 0.22)},
			{"label": "Swift", "desc": "Friendlies strike in the pre-combat Swift phase.",
				"color": Color(0.25, 0.40, 0.55)},
			{"label": "Regenerate", "desc": "Friendlies heal 1 HP at the start of each round.",
				"color": Color(0.45, 0.35, 0.20)},
			{"label": "Armored", "desc": "Friendlies take 1 less damage from each hit.",
				"color": Color(0.35, 0.35, 0.42)},
		]
		var kw_vals := ["thorns", "swift", "regenerate", "armored"]
		var pick: int = await GameTheme.show_option_picker(self,
			"Totem Pole — keyword for Act %d" % RunState.get_act(), kw_opts)
		if pick >= 0:
			RunState.totem_pole_keyword = kw_vals[pick]
			RunState.totem_pole_act = RunState.get_act()
	# Bone Hourglass: pick a ramp boon once per act.
	if RunState.has_relic("bone_hourglass") and RunState.bone_hourglass_act != RunState.get_act():
		var ramp_opts := [
			{"label": "Front Line", "desc": "+1 ATK to creatures you place in the front row.",
				"color": Color(0.45, 0.25, 0.20)},
			{"label": "Back Line", "desc": "+1 HP to creatures you place in the back row.",
				"color": Color(0.25, 0.35, 0.45)},
			{"label": "Mana Well", "desc": "+1 max mana while both center lanes are full.",
				"color": Color(0.35, 0.30, 0.50)},
		]
		var ramp_vals := ["front_atk", "back_hp", "mana_center"]
		var pick2: int = await GameTheme.show_option_picker(self,
			"Bone Hourglass — boon for Act %d" % RunState.get_act(), ramp_opts)
		if pick2 >= 0:
			RunState.bone_hourglass_choice = ramp_vals[pick2]
			RunState.bone_hourglass_act = RunState.get_act()


# ═══════════════════ SITE BUTTONS ═══════════════════

func _build_node_buttons() -> void:
	# Invisible round-hover buttons over the chips MapTerrain painted. Button
	# hover styleboxes give the highlight without redrawing the 25k-primitive
	# plate; tooltips carry the encounter + mutator intel.
	for nd in _nodes:
		var is_boss: bool = String(nd.type) == "boss"
		var r: float = BOSS_HIT if is_boss else HIT_R
		var btn := Button.new()
		btn.position = (nd.pos as Vector2) - Vector2(r, r)
		btn.size = Vector2(r * 2.0, r * 2.0)
		btn.flat = true
		btn.tooltip_text = _tip(nd)
		var empty := StyleBoxEmpty.new()
		for sb in ["normal", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(sb, empty)
		if bool(nd.vis) or not bool(nd.avail):
			btn.disabled = true
			btn.add_theme_stylebox_override("hover", empty)
		else:
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var hover := StyleBoxFlat.new()
			hover.bg_color = Color(0.95, 0.78, 0.30, 0.16)
			for pr in ["corner_radius_top_left", "corner_radius_top_right",
					"corner_radius_bottom_left", "corner_radius_bottom_right"]:
				hover.set(pr, int(r))
			btn.add_theme_stylebox_override("hover", hover)
		btn.pressed.connect(_on_node_pressed.bind(int(nd.row), int(nd.col)))
		add_child(btn)


func _tip(nd: Dictionary) -> String:
	var t: String = String(nd.type)
	var label: String = t.capitalize()
	if t in ["combat", "elite", "boss"] and String(nd.get("encounter_id", "")) != "":
		var enc: Dictionary = EncounterDB.get_encounter(String(nd.encounter_id))
		if not enc.is_empty():
			label = enc.name
	# Mutator tag — surfaces "Stormy: enemies gain Swift" etc. so the player
	# can route around a fight they don't want without entering it first.
	var mut_id: String = String(nd.get("mutator_id", ""))
	if mut_id != "" and MutatorDB.exists(mut_id):
		var mut: Dictionary = MutatorDB.get_mutator(mut_id)
		label += "\n★ %s: %s" % [mut.get("name", mut_id), mut.get("desc", "")]
	return label


func _on_node_pressed(row: int, col: int) -> void:
	var ok := false
	for n in RunState.get_available_nodes():
		if int(n.row) == row and int(n.col) == col:
			ok = true
			break
	if not ok:
		return
	RunState.visit_node(row, col)
	var ntype: String = RunState.current_node_type
	var target := ""
	match ntype:
		"combat", "elite", "boss": target = COMBAT_SCENE
		"shop": target = SHOP_SCENE
		"rest": target = REST_SCENE
		"event": target = EVENT_SCENE
		"treasure": target = TREASURE_SCENE
	if target != "":
		GameTheme.fade_out_then_change_scene(self, target, 0.30)


# ═══════════════════ TOP HUD ═══════════════════

func _build_top_hud() -> void:
	const ROW_Y := 18.0
	const ROW_H := 40.0
	const ICON := 40.0
	const GAP := 12.0
	const FONT_SZ := 26
	_hud_root = Control.new()
	_hud_root.name = "HudRoot"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)

	# Left group — clear of the settings gear (x=14..62), left of the
	# cartouche band (which starts at x≈680).
	var x := 80.0
	_place_painted_icon(GameTheme.tex_hud_heart, Vector2(x, ROW_Y),
		ICON, Color.WHITE)
	_place_centred_label(
		"%d / %d" % [RunState.hero_hp, RunState.hero_max_hp],
		Rect2(x + ICON + GAP, ROW_Y, 130, ROW_H),
		Color(1.0, 0.95, 0.85), FONT_SZ)
	x += ICON + GAP + 145

	const GOLD_ICON := 50.0
	var gold_y: float = ROW_Y - (GOLD_ICON - ICON) * 0.5
	_place_painted_icon(GameTheme.tex_hud_gold, Vector2(x, gold_y),
		GOLD_ICON, Color.WHITE)
	_place_centred_label(str(RunState.gold),
		Rect2(x + GOLD_ICON + GAP, ROW_Y, 90, ROW_H),
		Color(1.0, 0.95, 0.55), FONT_SZ)
	x += GOLD_ICON + GAP + 105

	if RunState.relics.size() > 0:
		_place_painted_icon(GameTheme.tex_hud_relic, Vector2(x, ROW_Y),
			ICON - 4, Color(0.95, 0.78, 0.30))
		_place_centred_label("×%d" % RunState.relics.size(),
			Rect2(x + ICON + 6, ROW_Y, 60, ROW_H),
			Color(0.95, 0.85, 0.55), 22)

	# Right group — anchored off the right canvas edge. With canvas_items
	# stretch the coordinate space is the 1600×900 project viewport, not
	# window pixels; hardcoded x past 1600 lands off-canvas and never draws.
	var right_edge: float = size.x - 24.0
	var deck_w: float = _place_deck_button(right_edge, ROW_Y, ICON, ROW_H, FONT_SZ)
	var px: float = right_edge - deck_w - 12.0 - RunState.MAX_POTIONS * (ICON + 4.0)
	for i in range(RunState.MAX_POTIONS):
		var pid: String = RunState.potions[i] if i < RunState.potions.size() else ""
		_place_potion_slot(pid, i, Vector2(px, ROW_Y), ICON)
		px += ICON + 4


func _refresh_hud() -> void:
	if _hud_root != null and is_instance_valid(_hud_root):
		_hud_root.queue_free()
	_hud_root = null
	_build_top_hud()


func _place_potion_slot(pid: String, index: int, top_left: Vector2, sz: float) -> void:
	# Empty slot: shaded placeholder icon, not clickable.
	if pid == "":
		_place_painted_icon(GameTheme.tex_hud_potion, top_left, sz,
			Color(0.45, 0.40, 0.35, 0.45))
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var icon: Texture2D = PotionDB.icon_for(pid)
	var tint: Color = data.get("color", Color.WHITE) if not data.is_empty() else Color.WHITE
	_place_painted_icon(icon, top_left, sz, tint)
	# Invisible button overlay handles clicks + tooltip.
	var btn := Button.new()
	btn.flat = true
	btn.position = top_left
	btn.size = Vector2(sz, sz)
	var usable_in: String = data.get("usable_in", "combat")
	var map_usable: bool = usable_in == "map" or usable_in == "both"
	var label: String = "%s\n%s" % [data.get("name", pid), data.get("desc", "")]
	if not map_usable:
		label += "\nUsable in combat only"
	btn.tooltip_text = label
	if map_usable:
		btn.pressed.connect(func():
			_use_map_potion(index)
		)
	_hud_root.add_child(btn)


func _use_map_potion(index: int) -> void:
	var pid: String = RunState.potions[index] if index < RunState.potions.size() else ""
	if pid == "":
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect: String = data.get("effect", "")
	match effect:
		"heal_hp":
			RunState.consume_potion(index)
			RunState.heal_hero(8)
		_:
			# Combat-only effects shouldn't even be wired up here, but be safe.
			return
	_refresh_hud()


func _place_painted_icon(tex: Texture2D, top_left: Vector2, sz: float,
		tint: Color) -> void:
	if tex == null:
		return
	_hud_root.add_child(_make_constrained_tex(tex, top_left + Vector2(2, 2), sz,
		Color(0, 0, 0, 0.55)))
	_hud_root.add_child(_make_constrained_tex(tex, top_left, sz, tint))


func _make_constrained_tex(tex: Texture2D, top_left: Vector2, sz: float,
		mod: Color) -> TextureRect:
	var ico := TextureRect.new()
	ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	ico.texture = tex
	ico.custom_minimum_size = Vector2(sz, sz)
	ico.size = Vector2(sz, sz)
	ico.position = top_left
	ico.modulate = mod
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ico


func _place_centred_label(text: String, rect: Rect2, color: Color,
		font_size: int = 22) -> void:
	var wrap := Control.new()
	wrap.position = rect.position
	wrap.size = rect.size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(wrap)
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)


func _place_deck_button(right_edge: float, top_y: float, icon_sz: float,
		row_h: float, font_sz: int) -> float:
	const PADDING := 10.0
	const COUNT_W := 50.0
	var btn_w: float = PADDING + icon_sz + 8 + COUNT_W + PADDING
	var top_left := Vector2(right_edge - btn_w, top_y)
	var btn := Button.new()
	btn.size = Vector2(btn_w, row_h)
	btn.position = top_left
	btn.flat = true
	btn.tooltip_text = "View your deck"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for sb in ["normal", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(sb, empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.95, 0.78, 0.30, 0.15)
	for p in ["corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_left", "corner_radius_bottom_right"]:
		hover.set(p, 8)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(_show_deck_viewer)
	_hud_root.add_child(btn)
	_place_painted_icon(GameTheme.tex_hud_deck,
		top_left + Vector2(PADDING, 0), icon_sz,
		Color(0.95, 0.88, 0.72))
	_place_centred_label(str(RunState.deck.size()),
		Rect2(top_left.x + PADDING + icon_sz + 8, top_left.y,
			COUNT_W, row_h),
		Color(1.0, 0.95, 0.80), font_sz)
	return btn_w


# ═══════════════════ DECK VIEWER ═══════════════════

func _show_deck_viewer() -> void:
	var overlay := ColorRect.new()
	overlay.name = "DeckOverlay"
	overlay.color = Color(0.03, 0.02, 0.05, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var title = GameTheme.make_label(
		"YOUR DECK  (%d cards)" % RunState.deck.size(),
		GameTheme.FONT_HEADER, GameTheme.GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 20)
	title.size = Vector2(600, 40)
	overlay.add_child(title)

	var creatures := 0
	var spells := 0
	var rarity_counts := {"starter": 0, "common": 0, "uncommon": 0, "rare": 0}
	for card_id in RunState.deck:
		var cdata = CardDB.get_card_data(card_id)
		if cdata.is_empty():
			continue
		if cdata.get("type", "") == "creature":
			creatures += 1
		else:
			spells += 1
		var r = cdata.get("rarity", "common")
		if rarity_counts.has(r):
			rarity_counts[r] += 1

	var stats_bar := HBoxContainer.new()
	stats_bar.position = Vector2(80, 68)
	stats_bar.size = Vector2(1440, 28)
	stats_bar.add_theme_constant_override("separation", 32)
	overlay.add_child(stats_bar)

	var comp_items = [
		["Creatures: %d" % creatures, Color(0.55, 0.85, 0.55)],
		["Spells: %d" % spells, Color(0.55, 0.70, 0.95)],
		["|", Color(0.4, 0.35, 0.3)],
		["Common: %d" % rarity_counts["common"], Color(0.78, 0.75, 0.68)],
		["Uncommon: %d" % rarity_counts["uncommon"], Color(0.40, 0.75, 0.95)],
		["Rare: %d" % rarity_counts["rare"], Color(0.95, 0.78, 0.25)],
	]
	for item in comp_items:
		var sl = GameTheme.make_label(item[0], GameTheme.FONT_BODY, item[1])
		sl.add_theme_constant_override("outline_size", 3)
		sl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		stats_bar.add_child(sl)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(80, 100)
	scroll.size = Vector2(1440, 690)
	overlay.add_child(scroll)

	var grid := GridContainer.new()
	# 225-wide cards at compact scale (0.483) × 7 cols + 6×18 separation = ~870 px, fits 1440 scroll.
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 22)
	scroll.add_child(grid)

	# Same batched-instantiation approach as the Card Gallery — defers
	# card creation across frames so opening the deck viewer doesn't
	# freeze the main thread. 6 per frame keeps the popup responsive
	# while filling top-down. static_display kills the per-frame costs
	# (pulse, shadows, rare halo) so once spawned the cards are cheap.
	var batch_size := 6
	for batch_start in range(0, RunState.deck.size(), batch_size):
		for k in range(batch_size):
			var i := batch_start + k
			if i >= RunState.deck.size():
				break
			var data = RunState.get_upgraded_card_data(i)
			var card = CARD_SCENE.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = data.get("id", "")
			card.is_on_battlefield = true
			card.static_display = true
			grid.add_child(card)
		await get_tree().process_frame

	var close_btn = GameTheme.make_back_button("CLOSE", Vector2(140, 40))
	close_btn.position = Vector2(740, 800)
	close_btn.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(close_btn)
