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
const RECRUIT_SCENE := "res://scenes/recruit.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const CARD_SCENE := preload("res://scenes/card_2d.tscn")

const HIT_R := 26.0           # click radius, normal site chip
const BOSS_HIT := 46.0        # click radius, the keep

# Phase 2.5 — the tooltip's route-planning line per ground type. Keywords
# stay Capitalized (COPY_STYLE §4); the phrasing names what the country
# BREEDS, matching the terrain re-deal in RunState.apply_terrain_redeal.
const TERRAIN_TIPS := {
	"woods": "Wooded road — ambush country. Swift and Ranged favor it.",
	"pass": "High pass — hard going. Armored kits hold passes.",
	"ash": "Ash country — the burn. Doom and fire walk here.",
	"meadow": "Meadow road — open country, lighter resistance.",
}

var _hud_root: Control = null
var _overlay: MapPulseOverlay = null
var _marching := false        # commit march in flight — ignore further clicks
var _site_buttons: Array = []  # MapTipButtons re-seated on every zoom/pan


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file(MAIN_MENU)
		return
	if RunState.finale_stage == 1:
		# The run was saved at the throne door (the finale isn't a map node) —
		# a resume lands here, and the only way out is through.
		get_tree().change_scene_to_file(COMBAT_SCENE)
		return
	AudioBank.play_music("map")
	# No atmosphere overlay here: the chart plate carries its own mood, and
	# the menu-style vignette just dims it.
	overlay_handles_standard = true
	await get_tree().process_frame
	build_map()
	_build_node_buttons()
	# The one animated layer over the static 25k-primitive plate: available-
	# site pulses, the player's army standard, Etna embers, the commit march.
	_overlay = MapPulseOverlay.new()
	_overlay.map = self
	add_child(_overlay)
	_build_top_hud()
	GameTheme.make_settings_gear(self)
	# Open leaning over the army's position on the chart — the player can
	# wheel out to the full island (or back in) at any time. The per-open
	# plate bake is in flight for a few frames (longer on the act's first
	# open, which also generates + bakes the geography) — wait it out so
	# the ease glides over a single-quad plate instead of heavy frames.
	if _plate_tex == null and _plate_bake_pending:
		await plate_baked
	_animate_focus(_player_pos if _has_player else _camp_pos, 1.45)
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
			{"label": "Command Tent", "desc": "+1 max Command while both center lanes are full.",
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
		var btn := MapTipButton.new()
		btn.view = self
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
		btn.set_meta("plate_pos", nd.pos as Vector2)
		btn.set_meta("hit_r", r)
		_site_buttons.append(btn)
		add_child(btn)
	_apply_view_to_buttons()


## The plate draws through the view transform; the invisible hit buttons are
## real Controls, so they get re-seated (and re-scaled) to match every time
## the zoom or pan changes.
func _on_view_changed() -> void:
	_apply_view_to_buttons()


func _apply_view_to_buttons() -> void:
	for btn in _site_buttons:
		if not is_instance_valid(btn):
			continue
		var p: Vector2 = btn.get_meta("plate_pos")
		var r: float = btn.get_meta("hit_r")
		btn.scale = Vector2(_view_zoom, _view_zoom)
		btn.position = p * _view_zoom + _view_pan - Vector2(r, r) * _view_zoom


## Ease the view from wherever it is onto a plate point — used on map open so
## returning from a fight reads as picking the chart back up where you stand.
func _animate_focus(world: Vector2, target_zoom: float, duration := 0.55) -> void:
	var z0 := _view_zoom
	var p0 := _view_pan
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var z: float = lerpf(z0, target_zoom, t)
		_set_view(z, p0.lerp(size * 0.5 - world * target_zoom, t)),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _tip(nd: Dictionary) -> String:
	var t: String = String(nd.type)
	var label: String = t.capitalize()
	if t in ["combat", "elite", "boss"] and String(nd.get("encounter_id", "")) != "":
		var enc: Dictionary = EncounterDB.get_encounter(String(nd.encounter_id))
		if not enc.is_empty():
			label = enc.name
	if t == "recruit":
		label += "\nChoose 1 of 3 cards to join your deck. Free."
	if t == "boss":
		# Rival-lord intel: whose keep this is, and whether the road is open.
		var rival: String = RunState.get_act_rival()
		if rival != "" and String(nd.get("encounter_id", "")) == "rival_%s" % rival:
			var title: String = String(HeroDB.faction_info(
				HeroDB.get_faction(rival)).get("lord_title", ""))
			if title != "":
				label += "\n%s" % title
		if not RunState.is_lord_gate_open():
			var left: int = RunState.HOLDS_TO_OPEN_LORD - RunState.holds_broken_in_act
			label += "\nThe gates are barred — break %d more %s to open the road." \
				% [left, "hold" if left == 1 else "holds"]
	# Mutator tag — surfaces "Stormy: enemies gain Swift" etc. so the player
	# can route around a fight they don't want without entering it first.
	var mut_id: String = String(nd.get("mutator_id", ""))
	if mut_id != "" and MutatorDB.exists(mut_id):
		var mut: Dictionary = MutatorDB.get_mutator(mut_id)
		label += "\n★ %s: %s" % [mut.get("name", mut_id), mut.get("desc", "")]
	# Phase 2.5 — the ground the hold sits on. The terrain line is the
	# route-planning read: it tells you what KIND of fight the country
	# breeds before you commit to the road.
	var terrain: String = String(nd.get("terrain", ""))
	if t in ["combat", "elite"] and TERRAIN_TIPS.has(terrain):
		label += "\n%s" % TERRAIN_TIPS[terrain]
	elif t == "boss" and terrain == "ash":
		label += "\nThe approach is ash the whole way."
	if bool(nd.get("bridge", false)):
		label += "\nA bridge crossing — something always waits at the water."
	return label


func _on_node_pressed(row: int, col: int) -> void:
	if _marching:
		return
	var ok := false
	for n in RunState.get_available_nodes():
		if int(n.row) == row and int(n.col) == col:
			ok = true
			break
	if not ok:
		return
	var dest := Vector2.ZERO
	for nd in _nodes:
		if int(nd.row) == row and int(nd.col) == col:
			dest = nd.pos
			break
	# Capture the march origin before visiting flips availability state.
	var from_p: Vector2 = _player_pos if _has_player else _camp_pos
	_marching = true
	AudioBank.play_sfx("button_click")
	RunState.visit_node(row, col)
	var ntype: String = RunState.current_node_type
	var target := ""
	match ntype:
		"combat", "elite", "boss": target = COMBAT_SCENE
		"shop": target = SHOP_SCENE
		"rest": target = REST_SCENE
		"event": target = EVENT_SCENE
		"treasure": target = TREASURE_SCENE
		"recruit": target = RECRUIT_SCENE
	# The army marches down the carved road to the chosen site, then the
	# scene fades — the commit reads as a move on the campaign map, not a
	# menu click.
	if _overlay != null:
		await _overlay.march_along(road_path_between(from_p, dest))
	if target != "":
		GameTheme.fade_out_then_change_scene(self, target, 0.30)
	else:
		_marching = false


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
	var btn := MapTipButton.new()
	btn.view = self
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
	var btn := MapTipButton.new()
	btn.view = self
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


# ═══════════════════ PARCHMENT TOOLTIP ═══════════════════

## Chart-styled tooltip: gilt name line + dim body on a dark ink panel with
## a tan rule. Replaces the stock gray tooltip box — the one engine-default
## element that would otherwise sit on the hand-drawn plate.
func _build_map_tooltip(text: String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.048, 0.040, 0.97)
	sb.border_color = Color(0.60, 0.51, 0.34, 0.95)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var lines := text.split("\n")
	var name_lbl := Label.new()
	name_lbl.text = lines[0]
	if GameTheme.font_display != null:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.78, 0.52))
	box.add_child(name_lbl)
	if lines.size() > 1:
		var body := Label.new()
		body.text = "\n".join(lines.slice(1))
		if body.text.length() > 36:
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.custom_minimum_size = Vector2(280, 0)
		if GameTheme.font_body != null:
			body.add_theme_font_override("font", GameTheme.font_body)
		body.add_theme_font_size_override("font_size", 13)
		body.add_theme_color_override("font_color", Color(0.82, 0.78, 0.68))
		box.add_child(body)
	return panel


## Button whose tooltip renders as the chart-styled panel above.
class MapTipButton extends Button:
	var view = null   # the owning MapView

	func _make_custom_tooltip(for_text: String) -> Object:
		if view != null and for_text != "":
			return view._build_map_tooltip(for_text)
		return null


# ═══════════════════ ANIMATED OVERLAY ═══════════════════

## The single animated layer over the static plate: (1) breathing rings on
## reachable sites (crimson on the keep when the boss road opens), (2) the
## player's army standard — a swallow-tailed banner with a ground glow,
## unmistakable among the small conquered pennants, (3) ember puffs drifting
## NE off Etna, (4) the commit march — the standard walks the carved road to
## the chosen site. The 25k-primitive terrain plate never redraws; this node
## redraws a dozen primitives per frame instead.
class MapPulseOverlay extends Control:
	var map = null                # the MapView (MapTerrain state lives there)
	var _t := 0.0
	var _march_pts: PackedVector2Array = PackedVector2Array()
	var _march_cum: PackedFloat32Array = PackedFloat32Array()
	var _march_len := 0.0
	var _march_prog := -1.0       # <0 idle · 0..1 marching (stays at 1 after)

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	## Walk the standard along a road curve. Awaitable; progress sticks at 1
	## so the banner stays planted at the destination through the scene fade.
	func march_along(path: PackedVector2Array, duration := 0.55) -> void:
		_march_pts = path
		_march_cum = PackedFloat32Array()
		_march_cum.append(0.0)
		_march_len = 0.0
		for i in range(1, path.size()):
			_march_len += path[i - 1].distance_to(path[i])
			_march_cum.append(_march_len)
		_march_prog = 0.0
		var tw := create_tween()
		tw.tween_property(self, "_march_prog", 1.0, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished

	func _march_pos() -> Vector2:
		if _march_pts.size() < 2 or _march_len <= 0.0:
			return _march_pts[-1] if _march_pts.size() > 0 else Vector2.ZERO
		var d := clampf(_march_prog, 0.0, 1.0) * _march_len
		for i in range(1, _march_pts.size()):
			if d <= _march_cum[i]:
				var seg := _march_cum[i] - _march_cum[i - 1]
				var t := 0.0 if seg <= 0.0 else (d - _march_cum[i - 1]) / seg
				return _march_pts[i - 1].lerp(_march_pts[i], t)
		return _march_pts[-1]

	func _draw() -> void:
		if map == null:
			return
		# All overlay geometry lives in plate coordinates — ride the same
		# view transform as the terrain so rings, standard, and the march
		# stay glued to their sites at any zoom.
		draw_set_transform(map._view_pan, 0.0,
			Vector2(map._view_zoom, map._view_zoom))
		var amber: Color = map.PLAYER_AMBER
		var crimson: Color = map.CRIMSON
		# 1 — breathing rings on the frontier (quiet during the march).
		if _march_prog < 0.0:
			var pulse := 0.5 + 0.5 * sin(_t * 2.6)
			for nd in map._nodes:
				if not bool(nd.avail) or bool(nd.vis):
					continue
				var p: Vector2 = nd.pos
				var is_boss := String(nd.type) == "boss"
				var col := crimson if is_boss else amber
				var rr := (34.0 if is_boss else 24.0) + 3.0 * pulse
				draw_arc(p, rr, 0, TAU, 48,
					Color(col.r, col.g, col.b, 0.10 + 0.24 * pulse), 2.0, true)
				draw_circle(p, rr,
					Color(col.r, col.g, col.b, 0.015 + 0.035 * pulse))
		# 1.5 — march glints: a short runner sliding camp-side → door along
		# each open leg. Direction without shouting — the baked amber dashes
		# carry the state; this just says "that way". Quiet during the march.
		if _march_prog < 0.0:
			for ei in range(map._edges.size()):
				var e: Dictionary = map._edges[ei]
				if not bool(e.to_avail):
					continue
				var pts: PackedVector2Array = map._edge_curves[ei]
				if pts.size() < 2:
					continue
				var cum := PackedFloat32Array()
				cum.append(0.0)
				var total := 0.0
				for i in range(1, pts.size()):
					total += pts[i - 1].distance_to(pts[i])
					cum.append(total)
				if total < 60.0:
					continue
				var ph := fmod(_t * 0.45 + float(ei) * 0.37, 1.0)
				var run := total - 46.0
				var hd := 20.0 + run * ph
				var head: Vector2 = map._route_arc_point(pts, cum, hd)
				var tail: Vector2 = map._route_arc_point(pts, cum,
					maxf(hd - 14.0, 6.0))
				var fade := sin(ph * PI)
				draw_line(tail, head,
					Color(1.0, 0.86, 0.50, 0.30 * fade), 3.0, true)
				draw_circle(head, 2.2, Color(1.0, 0.90, 0.60, 0.50 * fade))
		# 2 — ember puffs off Etna's plume, drifting NE on the strait wind.
		var apex: Vector2 = (map._etna_peak as Vector2) + Vector2(0, -34.0)
		for k in range(3):
			var ph := fmod(_t * 0.16 + float(k) / 3.0, 1.0)
			var pp := apex + Vector2(30.0, -38.0) * ph \
				+ Vector2(sin(_t * 0.9 + float(k) * 2.1) * 4.0, 0)
			draw_circle(pp, 3.5 + 9.0 * ph,
				Color(0.75, 0.70, 0.64, (1.0 - ph) * 0.085))
		# 3 — the army standard: walking the road while marching, otherwise
		# planted at the player's latest conquest (or the camp gate).
		var sp: Vector2
		if _march_prog >= 0.0:
			sp = _march_pos()
		elif bool(map._has_player):
			sp = map._player_pos
		else:
			sp = (map._camp_pos as Vector2) + Vector2(30, -4)
		var sway := sin(_t * 2.3)
		if _march_prog >= 0.0 and _march_prog < 1.0:
			sway = sin(_t * 9.0)   # the banner snaps in the wind on the move
		draw_circle(sp + Vector2(0, 2), 13.0 + 2.0 * sway,
			Color(amber.r, amber.g, amber.b, 0.07))
		draw_arc(sp, 19.0 + 1.5 * sway, 0, TAU, 40,
			Color(amber.r, amber.g, amber.b, 0.22), 1.4, true)
		draw_circle(sp + Vector2(1, 3), 3.4, Color(0, 0, 0, 0.45))
		draw_line(sp + Vector2(0, 4), sp + Vector2(0, -36),
			Color(0.05, 0.04, 0.03), 2.4, true)
		draw_circle(sp + Vector2(0, -36), 1.8, Color(0.92, 0.78, 0.42))
		var tip_x := 26.0 + 2.0 * sway
		var flag := PackedVector2Array([
			sp + Vector2(0, -36),
			sp + Vector2(tip_x, -33.0 + 1.2 * sway),
			sp + Vector2(16, -28.5),
			sp + Vector2(tip_x, -24.0 - 1.2 * sway),
			sp + Vector2(0, -21)])
		draw_colored_polygon(flag, amber)
		var outline := flag.duplicate()
		outline.append(flag[0])
		draw_polyline(outline, Color(0.16, 0.11, 0.05, 0.9), 1.2, true)
