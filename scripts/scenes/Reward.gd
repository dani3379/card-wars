extends Control
## Reward.gd — the post-victory SPOILS screen (Successor Wars): elites pick
## a relic, bosses pick a boss relic. Cards no longer drop from fights —
## deck growth lives at recruit stops (Recruit.gd) — so normal combats skip
## this screen entirely and march straight back to the map.
## Fully programmatic UI.

const MAP_SCENE = "res://scenes/map.tscn"
const COMBAT_SCENE = "res://scenes/combat.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const CAMPAIGN_STANDARD = preload("res://scripts/ui/painters/CampaignStandard.gd")
const ACT_VICTORY_STRIP = preload("res://scripts/ui/painters/ActVictoryStrip.gd")

# The spoils sheet's own inks. PARCHMENT is the SHOP-SHELF ink and is
# deliberately not used on the spoil tiles — a prize lit the same as a
# merchant's stock is the whole reason this screen read quieter than the
# roadside Reliquary. See _spoil_style.
const SPOIL_FILL := Color(0.155, 0.115, 0.078, 0.96)
const SPOIL_EMBER := Color(1.0, 0.56, 0.20)
# The painting, not the box, is the prize. Two of these out-weigh the single
# find on the Treasure screen, which is the order the road should present them
# in: a General's death pays better than a hole in the ground.
const SPOIL_ICON_PX := 160
const SPOIL_TILE_W := 340.0

var _relic_choices: Array[String] = []
var _is_elite_reward: bool = false
# The General's Forge (2026-07-06 progression pass): every fallen General
# lets the player temper ONE card — a chosen "+" forge, same path as the
# rest site. Elite risk pays deck power, not just relic luck. (Olympian's
# Mark still upgrades a random extra card on top — additive, still honest.)
var _relic_taken: bool = false
var _forge_done: bool = false
var _forge_card_nodes: Array[Control] = []
var _forge_picking: bool = false
var _march_picking: bool = false
var _spoil_claiming: bool = false
var _company_standard_anchor: Control = null


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	# Lift the crushed vignette/gradient so the painted spoils art reads behind
	# the document tiles (the base "reward" mood crushes it near black).
	GameTheme.add_atmosphere(self, "reward", true, {
		"vignette": 0.30,
		"grad_outer": Color(0.03, 0.02, 0.02, 0.42),
	})
	# Reward continues whatever combat music faded out; if no track is loaded,
	# the map track keeps quiet — no separate "reward" music asset needed.
	var node_type = RunState.current_node_type
	_is_elite_reward = (node_type == "elite" or node_type == "boss")
	var is_boss = (node_type == "boss")

	if is_boss:
		_relic_choices = RelicDB.roll_boss_relics(RunState.relics, RunState.current_hero_id)
	elif _is_elite_reward:
		_relic_choices = RelicDB.roll_field_relics(2, RunState.relics,
			RunState.current_hero_id)

	# Olympian's Mark: after every General falls, upgrade one random unforged
	# creature/spell in the deck for free. Applies the same "+" upgrade the
	# rest-site offers, so the relic stays in lockstep with the player-driven
	# forge path instead of carving out a parallel buff.
	if node_type == "elite" and RunState.has_relic("olympians_mark"):
		var candidates: Array[int] = []
		for i in RunState.deck.size():
			if not RunState.has_upgrade_path(i, "plus"):
				var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
				if d.get("type", "") in ["creature", "spell", "armament"] \
						and CardDB.is_upgradeable(RunState.deck[i]):
					candidates.append(i)
		if candidates.size() > 0:
			RunState.upgrade_card(candidates[randi() % candidates.size()], "plus")

	_build_ui()
	GameTheme.fade_in(self, 0.22)
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay instead of skipping the reward on a
	# stray keypress — the "Skip" button is the deliberate way past it.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_forge_card_nodes.clear()
	_forge_picking = false
	_spoil_claiming = false
	_company_standard_anchor = null
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	# Center the spoils as one group. The relic row used to be EXPAND_FILL, which
	# soaked all the vertical space and left the tiles floating mid-screen with a
	# long gap down to Continue; now the whole stack sits centered and balanced.
	var outer := VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 26)
	margin.add_child(outer)

	# The spoils belong to the company, not a detached menu. Its standard carries
	# completed-march seals, General ribbons, and mourning cloth into this scene;
	# the chosen relic physically flies back to it below.
	var is_boss := RunState.current_node_type == "boss"
	var faction_id: String = RunState.get_act_faction()
	var faction_info: Dictionary = HeroDB.faction_info(faction_id) \
		if faction_id != "" else {}
	var route_color: Color = _heraldry_ink(
		faction_info.get("color", GameTheme.GILT_BRIGHT))
	var hero_faction: String = HeroDB.get_faction(RunState.current_hero_id)
	var hero_info: Dictionary = HeroDB.faction_info(hero_faction)
	var standard_color: Color = _heraldry_ink(
		hero_info.get("color", GameTheme.GILT_BRIGHT))
	var ceremony_row := HBoxContainer.new()
	ceremony_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ceremony_row.add_theme_constant_override("separation", 18)
	outer.add_child(ceremony_row)

	var standard = CAMPAIGN_STANDARD.new()
	standard.name = "CompanyStandard"
	var completed_acts: int = RunState.current_act_idx + (1 if is_boss else 0)
	standard.configure(completed_acts, RunState.generals_broken_run,
		RunState.fallen.size(), standard_color)
	ceremony_row.add_child(standard)
	_company_standard_anchor = standard
	GameTheme.deal_in(standard, 0.02)

	var title_stack := VBoxContainer.new()
	title_stack.custom_minimum_size = Vector2(790, 0)
	title_stack.add_theme_constant_override("separation", 5)
	ceremony_row.add_child(title_stack)
	var march_names := ["FIRST", "SECOND", "LAST"]
	var title_text := "GENERAL BROKEN  /  PROVINCE %d" % RunState.current_floor
	if is_boss:
		title_text = "THE %s MARCH  /  KEEP TAKEN" % \
			march_names[clampi(RunState.current_act_idx, 0, 2)]
	var title = GameTheme.make_screen_title(title_text, GameTheme.GILT_BRIGHT,
		GameTheme.FONT_TITLE if not is_boss else GameTheme.FONT_HEADER)
	title_stack.add_child(title)
	GameTheme.deal_in(title, 0.03)

	var subtitle_text := "Take one Combat relic. Then forge one card."
	if is_boss:
		var kingdom: String = String(faction_info.get("name", "The rival kingdom"))
		subtitle_text = "%s is broken.  %d holds  |  %d Generals  |  %d fallen  |  HP %d/%d" % [
			kingdom, RunState.holds_broken_in_act,
			_count_visited_current_act("elite"), RunState.fallen.size(),
			RunState.hero_hp, RunState.hero_max_hp]
	var subtitle := GameTheme.make_label(subtitle_text, 17, GameTheme.DESC_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_stack.add_child(subtitle)
	GameTheme.deal_in(subtitle, 0.08)

	# Boss rewards retain the conquered route long enough to read it. The line
	# inks itself from camp to the lord's seal before the next map is dealt.
	if is_boss:
		var route = ACT_VICTORY_STRIP.new()
		route.name = "ActVictoryRoute"
		route.configure(RunState.get_current_act_map(), route_color)
		route.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		outer.add_child(route)

	# Relic choices
	if _is_elite_reward and _relic_choices.size() > 0 and not _relic_taken:
		# Ruled cartouche subheader (matches Treasure / Event / Recruit).
		var relic_header := _make_section_header("Choose a Relic")
		outer.add_child(relic_header)
		GameTheme.deal_in(relic_header, 0.08)

		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 40)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(relic_row)

		var spoil_tiles: Array[Button] = []
		var relic_i := 0
		for id in _relic_choices:
			var btn := _make_spoil_tile(id)
			# Shrink-center: the row owns the freed vertical space now that
			# the card rack is gone, and HBox children stretch by default —
			# without this the relic panels render as full-height columns.
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.pressed.connect(_pick_relic.bind(id, btn))
			relic_row.add_child(btn)
			spoil_tiles.append(btn)
			var deal_at := 0.10 + relic_i * 0.08
			GameTheme.deal_in(btn, deal_at)
			# The shine is the pull's own announcement (commons no-op by design).
			# It waits out deal_in rather than racing it — both verbs drive
			# `modulate` on the same node, and overlapping them makes the rare
			# kiss fight the entrance fade.
			GameTheme.rarity_reveal(btn, RelicDB.get_relic_rarity(id),
				deal_at + 0.36)
			GameTheme.hover_lift(btn)
			relic_i += 1
		# One offer, one baseline: the tiles close onto their own content, so a
		# two-line rule beside a one-line rule would otherwise leave the pair
		# hanging at different heights.
		var tallest := 0.0
		for t in spoil_tiles:
			tallest = maxf(tallest, t.custom_minimum_size.y)
		for t in spoil_tiles:
			t.custom_minimum_size.y = tallest

	# The General's Forge — Generals only (bosses hand out the boss tier and
	# an act transition; the forge is the elite ladder's own rung).
	if RunState.current_node_type == "elite" \
			and (_relic_taken or _relic_choices.is_empty()) and not _forge_done \
			and _forge_candidates().size() > 0:
		var forge_header := _make_section_header(
			"The General's Forge — pick a card to forge")
		outer.add_child(forge_header)
		GameTheme.deal_in(forge_header, 0.18)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 240)
		outer.add_child(scroll)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 14)
		grid.alignment = BoxContainer.ALIGNMENT_CENTER
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		for i in _forge_candidates():
			var data: Dictionary = RunState.get_upgraded_card_data(i)
			var wrapper := Control.new()
			# 0.72-scale writ: full 225×300 cards overflow the reward column.
			wrapper.custom_minimum_size = Vector2(162, 216)
			wrapper.pivot_offset = wrapper.custom_minimum_size * 0.5
			wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_add_forge_candidate_halo(wrapper)
			var card_node = CARD_SCENE.instantiate()
			card_node.static_display = true
			card_node.card_data = data
			card_node.live_baked_mode = true
			CardTextureCache.bake(data)
			card_node.scale = Vector2(0.72, 0.72)
			wrapper.add_child(card_node)
			var click_btn := Button.new()
			click_btn.flat = true
			click_btn.focus_mode = Control.FOCUS_NONE
			click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
			click_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			click_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
			click_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			click_btn.mouse_entered.connect(_on_forge_card_hover.bind(wrapper, true))
			click_btn.mouse_exited.connect(_on_forge_card_hover.bind(wrapper, false))
			click_btn.button_down.connect(_on_forge_card_pressed.bind(wrapper, true))
			click_btn.button_up.connect(_on_forge_card_pressed.bind(wrapper, false))
			click_btn.pressed.connect(_pick_forge_candidate.bind(i, wrapper))
			wrapper.add_child(click_btn)
			grid.add_child(wrapper)
			_forge_card_nodes.append(wrapper)
			GameTheme.deal_in(wrapper, 0.22 + grid.get_child_count() * 0.035)

	var skip_btn = GameTheme.make_back_button("Continue", Vector2(200, 52), 20)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_skip)
	outer.add_child(skip_btn)
	GameTheme.deal_in(skip_btn, 0.40)
	GameTheme.hover_lift(skip_btn, 1.04)


## The kingdom dyes exist to tell five factions apart on the war table, and two
## of the five (Grasswake's teal, Lanternhall's blue) are cool. On the spoils
## sheet — blood, ash and gilt — a cool banner stops reading as heraldry and
## starts reading as an unpainted placeholder icon. Warm the dye into the
## screen's own ink: enough of it survives to tell the companies apart, but no
## flag can come out bluer than the fire behind it.
func _heraldry_ink(dye: Color) -> Color:
	return dye.lerp(GameTheme.GILT, 0.55)


## Rest / hover / pressed faces of a spoil tile, one lever (0 = rest, 1 = hot).
## The ember bleed is the stylebox's OWN shadow retinted — the kit's hover-glow
## lever — rather than a gradient pasted behind the tile.
func _spoil_style(lift: float) -> StyleBox:
	var s := GameTheme.make_panel_style(
		SPOIL_FILL.lightened(lift * 0.10),
		GameTheme.GILT.lerp(GameTheme.GILT_BRIGHT, lift), 2, 5, true, true)
	s.set("shadow_color", Color(SPOIL_EMBER.r, SPOIL_EMBER.g, SPOIL_EMBER.b,
		0.20 + 0.16 * lift))
	s.set("shadow_size", 16.0 + 8.0 * lift)
	return s


## A spoil tile. GameTheme.make_relic_card sizes its icon from the BOX
## (min_size.y * 0.38, capped at 128), a recipe that only balances around a
## ~147px tile — at the sizes a spoils screen asks for, a third of the tile is
## air, and that air is exactly what reads as a flat dark panel. This cuts it
## the other way round: pick the size of the painting first, then let
## fit_tile_height close the box onto it. Mirrored in Treasure._make_spoil_tile
## (the same duplication the two screens already carry for _make_section_header).
func _make_spoil_tile(rid: String) -> Button:
	var r: Dictionary = RelicDB.get_relic(rid)
	var skel: Dictionary = GameTheme.make_tile_skeleton(Vector2(SPOIL_TILE_W, 0), 6)
	var btn: Button = skel.button
	btn.tooltip_text = "%s — %s" % [r.get("name", rid), r.get("desc", "")]
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", _spoil_style(0.0))
	btn.add_theme_stylebox_override("hover", _spoil_style(1.0))
	btn.add_theme_stylebox_override("pressed", _spoil_style(0.45))

	var col: VBoxContainer = skel.col
	# The chip keeps its own StS rich hover (it is the only part of the tile
	# that carries the tier halo), exactly as it did under make_relic_card.
	var chip := GameTheme.make_relic_chip(rid, SPOIL_ICON_PX)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(chip)

	var name_lbl := GameTheme.make_label(r.get("name", rid), 22,
		GameTheme.KEYWORD_GOLD)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)

	var desc_lbl := GameTheme.make_label(r.get("desc", ""), 18, GameTheme.IVORY)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_lbl)

	GameTheme.fit_tile_height(btn, col)
	return btn


func _add_forge_candidate_halo(wrapper: Control) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.77, 0.30, 0.20))
	grad.set_color(1, Color(1.0, 0.54, 0.12, 0.0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.56)
	grad_tex.fill_to = Vector2(1.0, 0.56)
	grad_tex.width = 220
	grad_tex.height = 260
	var halo := TextureRect.new()
	halo.texture = grad_tex
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.z_index = -1
	halo.position = Vector2(-26, -22)
	halo.size = Vector2(214, 260)
	wrapper.add_child(halo)


func _on_forge_card_hover(wrapper: Control, hovered: bool) -> void:
	if wrapper == null or not is_instance_valid(wrapper) or _forge_picking:
		return
	wrapper.z_index = 4 if hovered else 0
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var target := Vector2(1.045, 1.045) if hovered else Vector2.ONE
	var tw := wrapper.create_tween()
	tw.tween_property(wrapper, "scale", target, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_forge_card_pressed(wrapper: Control, pressed: bool) -> void:
	if wrapper == null or not is_instance_valid(wrapper) or _forge_picking:
		return
	if UserSettings != null and UserSettings.reduce_motion:
		return
	var target := Vector2(0.985, 0.985) if pressed else Vector2(1.045, 1.045)
	var tw := wrapper.create_tween()
	tw.tween_property(wrapper, "scale", target, 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _pick_forge_candidate(deck_index: int, wrapper: Control = null) -> void:
	if _forge_picking:
		return
	_forge_picking = true
	if AudioBank != null:
		AudioBank.play_sfx("button_click")
	if wrapper != null and is_instance_valid(wrapper) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(wrapper)
		for other in _forge_card_nodes:
			if other != wrapper and other is Control and is_instance_valid(other):
				GameTheme.fade_exit(other, 0.18)
		await get_tree().create_timer(0.20).timeout
	_show_forge_confirm(deck_index)
	_forge_picking = false


## Back out of the forge confirm and put the slate back the way it was.
## fade_exit only tweens modulate.a — it does NOT free the node or stop it taking
## the mouse. Without this restore, cancelling left the passed-over candidates
## invisible but still hoverable and still clickable, so the player saw one card
## and a row of ghosts (reported as "you can't see the other options if you press
## cancel"). _forge_card_nodes is only rebuilt in _build_ui, so it is still valid
## here. Any future pick→confirm→cancel flow on this screen must call this.
func _restore_forge_slate() -> void:
	for other in _forge_card_nodes:
		if other is Control and is_instance_valid(other):
			other.modulate.a = 1.0
			other.scale = Vector2.ONE
			other.z_index = 0
	_forge_picking = false


## Deck indices eligible for the General's Forge — same filter as the rest
## site and Olympian's Mark: unforged, upgradeable, a real playable card.
func _forge_candidates() -> Array[int]:
	var out: Array[int] = []
	for i in RunState.deck.size():
		if RunState.has_upgrade_path(i, "plus"):
			continue
		if not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
		if d.get("type", "") in ["creature", "spell", "armament"]:
			out.append(i)
	return out


## Before/after confirm — the same clean forge moment the rest site sells:
## current writ, arrow, "+" writ, and a one-line diff. Commit or back out.
func _show_forge_confirm(deck_index: int) -> void:
	var base_data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	var upgraded_data: Dictionary = RunState.preview_plus_upgrade(base_data)

	var dim := ColorRect.new()
	dim.name = "ForgeDim"
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	# The confirm sheet fades up instead of snapping into existence; the whole
	# modal rides dim.modulate so one tween covers scrim + cards + buttons.
	if not (UserSettings != null and UserSettings.reduce_motion):
		dim.modulate.a = 0.0
		dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.16) \
			.set_ease(Tween.EASE_OUT)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -400
	col.offset_right = 400
	col.offset_top = -260
	col.offset_bottom = 260
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	dim.add_child(col)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	col.add_child(row)
	for pair in [[base_data, false], [upgraded_data, true]]:
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(225, 300)
		if pair[1]:
			# Named so the forge-strike set-piece can aim at the "+" card.
			wrapper.name = "ForgedPreview"
			_add_forge_preview_halo(wrapper)
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = pair[0]
		card_node.live_baked_mode = true
		CardTextureCache.bake(pair[0])
		if pair[1]:
			card_node.modulate = Color(1.06, 1.03, 0.94)
		wrapper.add_child(card_node)
		row.add_child(wrapper)
		GameTheme.deal_in(wrapper, 0.08 if not pair[1] else 0.18)
		if not pair[1]:
			var arrow = GameTheme.make_label("→", 44, GameTheme.GILT_BRIGHT)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
			GameTheme.deal_in(arrow, 0.13)

	var diff = GameTheme.make_label(
		_forge_change_summary(base_data, upgraded_data), 17, GameTheme.IVORY)
	diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(diff)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 24)
	col.add_child(btns)
	var go = GameTheme.make_themed_button("⚒ Forge +", Color(0.14, 0.10, 0.05),
		Vector2(180, 48), 19)
	go.pressed.connect(func():
		RunState.upgrade_card(deck_index, "plus")
		AudioBank.play_sfx("upgrade_confirm")
		_forge_done = true
		# The strike lands on the "+" card, THEN the sheet closes.
		await GameTheme.forge_strike(self, dim.find_child("ForgedPreview", true, false))
		dim.queue_free()
		_after_spoil_taken()
	)
	btns.add_child(go)
	var back = GameTheme.make_back_button("Back", Vector2(140, 48), 18)
	back.pressed.connect(func():
		dim.queue_free()
		_restore_forge_slate()
	)
	btns.add_child(back)


func _add_forge_preview_halo(wrapper: Control) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.82, 0.42, 0.42))
	grad.set_color(1, Color(0.95, 0.46, 0.10, 0.0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.width = 320
	grad_tex.height = 360
	var halo := TextureRect.new()
	halo.texture = grad_tex
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.z_index = -1
	halo.position = Vector2(-48, -42)
	halo.size = Vector2(321, 384)
	wrapper.add_child(halo)


func _forge_change_summary(base: Dictionary, upgraded: Dictionary) -> String:
	var parts: Array[String] = []
	if base.get("type", "") == "creature":
		if int(upgraded.get("atk", 0)) != int(base.get("atk", 0)):
			parts.append("ATK %d → %d" % [int(base.get("atk", 0)), int(upgraded.get("atk", 0))])
		if int(upgraded.get("hp", 0)) != int(base.get("hp", 0)):
			parts.append("HP %d → %d" % [int(base.get("hp", 0)), int(upgraded.get("hp", 0))])
	if int(upgraded.get("cost", 0)) != int(base.get("cost", 0)):
		parts.append("Cost %d → %d" % [int(base.get("cost", 0)), int(upgraded.get("cost", 0))])
	if parts.is_empty():
		return "Effect improved — see the upgraded card."
	return "   ·   ".join(parts)


## After a spoil (relic or forge) is consumed: leave if nothing actionable
## remains, otherwise rebuild with the remaining offers.
func _after_spoil_taken() -> void:
	var relic_pending: bool = _is_elite_reward \
		and _relic_choices.size() > 0 and not _relic_taken
	var forge_pending: bool = RunState.current_node_type == "elite" \
		and not _forge_done and _forge_candidates().size() > 0
	if relic_pending or forge_pending:
		_build_ui()
	else:
		_proceed()


func _pick_relic(id: String, tile: Control = null) -> void:
	if _spoil_claiming:
		return
	_spoil_claiming = true
	RunState.add_relic(id)
	_relic_taken = true
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	# The chosen spoil is physically taken: rivals bow out, then the relic dives
	# into the company standard instead of disappearing during a UI rebuild.
	if tile != null and is_instance_valid(tile):
		GameTheme.claim_pop(tile)
		if tile.get_parent() != null:
			for sib in tile.get_parent().get_children():
				if sib != tile and sib is Control:
					GameTheme.fade_exit(sib, 0.22)
		await get_tree().create_timer(0.10).timeout
		if _company_standard_anchor != null \
				and is_instance_valid(_company_standard_anchor):
			var target := _company_standard_anchor.global_position \
				+ _company_standard_anchor.size * 0.5
			await GameTheme.pocket_away(tile, target, 0.34)
			GameTheme.punch(_company_standard_anchor, 1.12)
		else:
			await get_tree().create_timer(0.28).timeout
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	# Don't march off with the General's Forge still hot — the screen stays
	# until every spoil is taken or the player chooses Continue.
	_after_spoil_taken()


func _skip() -> void:
	if _spoil_claiming:
		return
	_proceed()


## After the spoils: a boss victory with more than one kingdom left to invade
## asks the player where the war goes next (Successor Wars player-chosen
## rival order). Everything else marches straight out.
func _proceed() -> void:
	if RunState.current_node_type == "boss" and not RunState.should_enter_finale():
		var candidates: Array[String] = RunState.get_next_march_candidates()
		if candidates.size() >= 2:
			_show_march_choice(candidates)
			return
	_go_to_map()


func _show_march_choice(candidates: Array[String]) -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 18)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(outer)

	var title = GameTheme.make_screen_title("THE NEXT MARCH",
		GameTheme.GILT_BRIGHT, GameTheme.FONT_HEADER)
	outer.add_child(title)
	GameTheme.deal_in(title, 0.04)

	var march_header := _make_section_header("Choose whose kingdom burns next.")
	outer.add_child(march_header)
	GameTheme.deal_in(march_header, 0.10)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)

	# Lord tiles (2026-07-02): the campaign's biggest narrative decision used
	# to be two generic text banners — now each living rival stands as a
	# portrait plaque in his faction's color: face, name, title, kingdom, and
	# how his army fights. The provisional finale candidate joins the slate;
	# whichever lord survives the Act 2 choice takes the throne.
	for i in candidates.size():
		var lord: String = candidates[i]
		var tile := _make_lord_tile(lord)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)
		GameTheme.deal_in(tile, 0.12 + i * 0.10)
		GameTheme.hover_lift(tile)


func _make_lord_tile(lord: String) -> Button:
	var faction: String = HeroDB.get_faction(lord)
	var info: Dictionary = HeroDB.faction_info(faction)
	var fcolor: Color = info.get("color", Color(0.60, 0.51, 0.34))
	var hero: Dictionary = HeroDB.get_hero(lord)

	var btn := Button.new()
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	# Fixed footprint — the VBox child is anchored (not size-driving), so the
	# tile must claim its own height: portrait 250 + four text rows + margins.
	btn.custom_minimum_size = Vector2(316, 470)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := GameTheme.make_panel_style(Color(0.055, 0.048, 0.040, 0.96),
		fcolor.lerp(GameTheme.GILT, 0.35), 1, 4, true, true)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := GameTheme.make_panel_style(Color(0.085, 0.070, 0.052, 0.97),
		GameTheme.GILT_BRIGHT, 1, 4, true, true)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.pressed.connect(_pick_march.bind(lord, btn))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 16
	col.offset_bottom = -16
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 7)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	# Portrait — the rival lords ARE the five heroes, so their painted
	# portraits serve double duty. Monogram plate fallback if one is missing.
	var port_path := "res://assets/portraits/hero_portrait_%s.png" % lord
	if ResourceLoader.exists(port_path):
		var portrait := TextureRect.new()
		portrait.texture = load(port_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size = Vector2(200, 250)
		portrait.clip_contents = true
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.modulate = Color(0.94, 0.91, 0.88)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(portrait)
	else:
		var mono = GameTheme.make_label(
			String(hero.get("name", lord)).strip_edges().left(1).to_upper(),
			84, Color(fcolor.r, fcolor.g, fcolor.b, 0.85))
		mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mono.custom_minimum_size = Vector2(200, 250)
		mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(mono)

	var name_lbl = GameTheme.make_label(
		String(hero.get("name", lord)).to_upper(), 23, GameTheme.GILT_BRIGHT, true)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var title_lbl = GameTheme.make_label(String(info.get("lord_title", "")), 15,
		GameTheme.IVORY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_lbl)

	# Faction rule in the kingdom's dye — the tile's heraldry line.
	var rule := ColorRect.new()
	rule.color = Color(fcolor.r, fcolor.g, fcolor.b, 0.85)
	rule.custom_minimum_size = Vector2(120, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)

	var kingdom_lbl = GameTheme.make_label("%s  ·  %s" % [
		String(info.get("name", "")), String(info.get("engine", ""))], 15,
		fcolor.lerp(Color(0.95, 0.92, 0.84), 0.45))
	kingdom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kingdom_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(kingdom_lbl)

	var engine_lbl = GameTheme.make_label(String(info.get("engine_line", "")), 14,
		GameTheme.DESC_DIM)
	engine_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	engine_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	engine_lbl.custom_minimum_size = Vector2(260, 0)
	engine_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(engine_lbl)

	return btn


func _count_visited_current_act(node_type: String) -> int:
	var count := 0
	for row in RunState.get_current_act_map():
		for node in row:
			if bool(node.get("visited", false)) \
					and String(node.get("type", "")) == node_type:
				count += 1
	return count

func _make_section_header(text: String) -> HBoxContainer:
	# A ruled subheader plaque: tan rule — gold caption — tan rule. Echoes the
	# chart furniture (make_screen_title's divider) so the cue reads as a
	# document heading, not a stray label. Mirrors Treasure._make_section_header.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_col := Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.28)
	var left := ColorRect.new()
	left.custom_minimum_size = Vector2(70, 1)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.color = rule_col
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	# Quiet parchment caption, not gold: this is a document subheading, and gold
	# here competes with the screen title. Hierarchy = gold title → dim heading.
	var lbl := GameTheme.make_label(text, 24, GameTheme.DESC_DIM)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var right := ColorRect.new()
	right.custom_minimum_size = Vector2(70, 1)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.color = rule_col
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	return row


func _pick_march(lord: String, tile: Control = null) -> void:
	if _march_picking:
		return
	_march_picking = true
	if AudioBank != null:
		AudioBank.play_sfx("button_click")
	if tile != null and is_instance_valid(tile) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(tile)
		if tile.get_parent() != null:
			for sib in tile.get_parent().get_children():
				if sib != tile and sib is Control:
					GameTheme.fade_exit(sib, 0.22)
		await get_tree().create_timer(0.34).timeout
	RunState.choose_next_rival(lord)
	_go_to_map()


func _go_to_map() -> void:
	# Boss rewards advance the act on their way out. Combat used to do this
	# before queuing the Reward transition, but that wiped current_node_type
	# and made Reward render as a normal fight. Holding the advance until
	# now lets Reward read node_type == "boss" while still putting the player
	# on the next act's map on exit.
	if RunState.current_node_type == "boss":
		# Successor Wars: when the act-3 rival falls, the road leads to the
		# throne, not a fourth map — straight into the amalgam fight.
		if RunState.should_enter_finale():
			RunState.enter_finale()
			GameTheme.fade_out_then_change_scene(self, COMBAT_SCENE)
			return
		RunState.advance_act()
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
