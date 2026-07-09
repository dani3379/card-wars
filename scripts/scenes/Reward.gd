extends Control
## Reward.gd — the post-victory SPOILS screen (Successor Wars): elites pick
## a relic, bosses pick a boss relic. Cards no longer drop from fights —
## deck growth lives at recruit stops (Recruit.gd) — so normal combats skip
## this screen entirely and march straight back to the map.
## Fully programmatic UI.

const MAP_SCENE = "res://scenes/map.tscn"
const COMBAT_SCENE = "res://scenes/combat.tscn"
const CARD_SCENE = preload("res://scenes/card_2d.tscn")

var _relic_choices: Array[String] = []
var _is_elite_reward: bool = false
# The General's Forge (2026-07-06 progression pass): every fallen General
# lets the player temper ONE card — a chosen "+" forge, same path as the
# rest site. Elite risk pays deck power, not just relic luck. (Olympian's
# Mark still upgrades a random extra card on top — additive, still honest.)
var _relic_taken: bool = false
var _forge_done: bool = false


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
		_relic_choices = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)

	# Olympian's Mark: after every General falls, upgrade one random unforged
	# creature/spell in the deck for free. Applies the same "+" upgrade the
	# rest-site offers, so the relic stays in lockstep with the player-driven
	# forge path instead of carving out a parallel buff.
	if node_type == "elite" and RunState.has_relic("olympians_mark"):
		var candidates: Array[int] = []
		for i in RunState.deck.size():
			if not RunState.has_upgrade_path(i, "plus"):
				var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
				if d.get("type", "") in ["creature", "spell"] \
						and CardDB.is_upgradeable(RunState.deck[i]):
					candidates.append(i)
		if candidates.size() > 0:
			RunState.upgrade_card(candidates[randi() % candidates.size()], "plus")

	_build_ui()
	GameTheme.make_settings_gear(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay instead of skipping the reward on a
	# stray keypress — the "Skip" button is the deliberate way past it.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
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

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 26)
	margin.add_child(outer)

	# Title
	var title = GameTheme.make_screen_title(
		"VICTORY  —  Province %d" % RunState.current_floor, GameTheme.GILT_BRIGHT,
		GameTheme.FONT_TITLE)
	outer.add_child(title)

	# Relic choices
	if _is_elite_reward and _relic_choices.size() > 0 and not _relic_taken:
		# Ruled cartouche subheader (matches Treasure / Event / Recruit).
		outer.add_child(_make_section_header("Choose a Relic"))

		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 40)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		relic_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(relic_row)

		for id in _relic_choices:
			# Chart-look tile: dark-ink PARCHMENT body → document tile (gilt rule,
			# small corners) with the painted relic icon on top, not a flat slab.
			# Big tiles (340×300): the three spoils floated tiny in a sea of empty
			# space at 220×172 — grow them to fill the row and let the rules read.
			var btn = GameTheme.make_relic_card(id, GameTheme.PARCHMENT,
				Vector2(340, 300))
			# Shrink-center: the row owns the freed vertical space now that
			# the card rack is gone, and HBox children stretch by default —
			# without this the relic panels render as full-height columns.
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.pressed.connect(_pick_relic.bind(id))
			relic_row.add_child(btn)

	# The General's Forge — Generals only (bosses hand out the boss tier and
	# an act transition; the forge is the elite ladder's own rung).
	if RunState.current_node_type == "elite" and not _forge_done \
			and _forge_candidates().size() > 0:
		outer.add_child(_make_section_header(
			"The General's Forge — temper one card"))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 240)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
			click_btn.pressed.connect(_show_forge_confirm.bind(i))
			wrapper.add_child(click_btn)
			grid.add_child(wrapper)

	var skip_btn = GameTheme.make_back_button("Continue", Vector2(200, 52), 20)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_skip)
	outer.add_child(skip_btn)


## Deck indices eligible for the General's Forge — same filter as the rest
## site and Olympian's Mark: unforged, upgradeable, a real creature/spell.
func _forge_candidates() -> Array[int]:
	var out: Array[int] = []
	for i in RunState.deck.size():
		if RunState.has_upgrade_path(i, "plus"):
			continue
		if not CardDB.is_upgradeable(RunState.deck[i]):
			continue
		var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
		if d.get("type", "") in ["creature", "spell"]:
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
		var card_node = CARD_SCENE.instantiate()
		card_node.static_display = true
		card_node.card_data = pair[0]
		card_node.live_baked_mode = true
		CardTextureCache.bake(pair[0])
		if pair[1]:
			card_node.modulate = Color(1.06, 1.03, 0.94)
		wrapper.add_child(card_node)
		row.add_child(wrapper)
		if not pair[1]:
			var arrow = GameTheme.make_label("→", 44, GameTheme.GILT_BRIGHT)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)

	var diff = GameTheme.make_label(
		_forge_change_summary(base_data, upgraded_data), 17, GameTheme.IVORY)
	diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(diff)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 24)
	col.add_child(btns)
	var go = GameTheme.make_themed_button("FORGE IT", Color(0.14, 0.10, 0.05),
		Vector2(180, 48), 19)
	go.pressed.connect(func():
		RunState.upgrade_card(deck_index, "plus")
		AudioBank.play_sfx("upgrade_confirm")
		_forge_done = true
		dim.queue_free()
		_after_spoil_taken()
	)
	btns.add_child(go)
	var back = GameTheme.make_back_button("Back", Vector2(140, 48), 18)
	back.pressed.connect(func(): dim.queue_free())
	btns.add_child(back)


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


func _pick_relic(id: String) -> void:
	RunState.add_relic(id)
	_relic_taken = true
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	# Don't march off with the General's Forge still hot — the screen stays
	# until every spoil is taken or the player chooses Continue.
	_after_spoil_taken()


func _skip() -> void:
	_proceed()


## After the spoils: a boss victory with more than one kingdom left to invade
## asks the player where the war goes next (Successor Wars player-chosen
## rival order). Everything else marches straight out.
func _proceed() -> void:
	if RunState.current_node_type == "boss" and not RunState.should_enter_finale():
		var next_idx: int = RunState.current_act_idx + 1
		if RunState.rival_lords.size() - next_idx >= 2:
			_show_march_choice(next_idx)
			return
	_go_to_map()


func _show_march_choice(next_idx: int) -> void:
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

	outer.add_child(_make_section_header("Choose whose kingdom burns next."))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)

	# Lord tiles (2026-07-02): the campaign's biggest narrative decision used
	# to be two generic text banners — now each remaining rival stands as a
	# portrait plaque in his faction's color: face, name, title, kingdom, and
	# how his army fights.
	for i in range(next_idx, RunState.rival_lords.size()):
		var lord: String = RunState.rival_lords[i]
		var tile := _make_lord_tile(lord)
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tile)


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
	btn.pressed.connect(_pick_march.bind(lord))

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


func _pick_march(lord: String) -> void:
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
