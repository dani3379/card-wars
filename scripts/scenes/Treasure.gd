extends Control
## Treasure.gd — Reliquary node. One eligible relic is revealed; claim it or
## liquidate the find for act-scaled gold. The second spoils stop is an Arsenal.

const MAP_SCENE = "res://scenes/map.tscn"
const GOLD_BY_ACT := [80, 100, 120]
const ARSENAL_GOLD_BY_ACT := [70, 90, 110]

# The find's own inks — see _spoil_style. A hole in the ground pays one relic,
# and it is deliberately cut a shade smaller than the pair a broken General
# pays (Reward.SPOIL_ICON_PX 160): the road's three relic stops should rank by
# what they cost the player, and this one cost nothing but the walk.
const SPOIL_FILL := Color(0.155, 0.115, 0.078, 0.96)
const SPOIL_EMBER := Color(1.0, 0.56, 0.20)
const SPOIL_ICON_PX := 148
const SPOIL_TILE_W := 330.0

var _gold_reward: int = 40
# Latches on the first pick/leave so a same-frame double-click can't pay the
# gold reward (and add the relic) twice before the fade-out swaps scenes.
var _resolved: bool = false


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	# Lift the crushed vignette/gradient so the painted treasure art actually
	# reads behind the document tiles (the base "reward" mood crushes it near
	# black). mood_override merges over the base — see GameTheme.add_atmosphere.
	GameTheme.add_atmosphere(self, "reward", true, {
		"vignette": 0.30,
		"grad_outer": Color(0.03, 0.02, 0.02, 0.42),
	})
	GameTheme.fade_in(self, 0.22)
	if RunState.current_node_type == "arsenal":
		await _run_arsenal()
		return
	_gold_reward = GOLD_BY_ACT[clampi(RunState.get_act() - 1, 0, 2)]
	# Gold is paid out only by _leave, so
	# quitting mid-room and continuing back into Treasure doesn't double-pay.
	_build_ui()
	GameTheme.make_settings_gear(self)


func _run_arsenal() -> void:
	GameTheme.make_settings_gear(self)
	var options: Array = []
	var actions: Array[String] = []
	var forge_live := false
	for i in RunState.deck.size():
		if not RunState.has_upgrade_path(i, "plus") \
				and CardDB.is_upgradeable(RunState.deck[i]):
			forge_live = true
			break
	if forge_live:
		options.append({"label": "Forge a Card", "desc": "Choose one card and forge its + version.",
			"color": Color(0.42, 0.23, 0.12)})
		actions.append("forge")
	if RunState.can_add_potion():
		options.append({"label": "Take Provisions", "desc": "Gain up to 2 random potions.",
			"color": Color(0.20, 0.38, 0.24)})
		actions.append("potions")
	var arsenal_gold: int = ARSENAL_GOLD_BY_ACT[clampi(RunState.get_act() - 1, 0, 2)]
	options.append({"label": "Take %d Gold" % arsenal_gold,
		"desc": "Trade the captured supplies for gold.",
		"color": Color(0.46, 0.34, 0.12)})
	actions.append("gold")
	var pick: int = await GameTheme.show_option_picker(self, "SUPPLY CACHE — choose one", options)
	if pick < 0 or pick >= actions.size():
		return
	match actions[pick]:
		"forge":
			var deck_index: int = await GameTheme.show_deck_picker(self,
				"Supply Cache — choose a card to upgrade", "upgradeable", false)
			if deck_index >= 0:
				RunState.upgrade_card(deck_index, "plus")
		"potions":
			for _i in 2:
				if not RunState.can_add_potion():
					break
				RunState.add_potion(PotionDB.roll_random_potion())
		"gold":
			RunState.gain_gold(arsenal_gold)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	# Esc opens the pause/Settings overlay — leaving with the loot is the
	# deliberate "Take Gold Only" button, not a stray keypress.
	if event.is_action_pressed("ui_cancel"):
		GameTheme.open_settings_overlay()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	# Center the whole find as one group: the relic used to float in an
	# EXPAND_FILL row with the reward stated twice (a gold line ABOVE the relic
	# AND a Take-Gold button below it), which read as the fallback announced
	# before the prize. Now it's title → flavor → the relic → "or" → take gold,
	# vertically centered, so the relic is unambiguously the star.
	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 60
	outer.offset_right = -60
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 20)
	add_child(outer)

	var title = GameTheme.make_screen_title("RELIC CACHE", GameTheme.KEYWORD_GOLD,
		GameTheme.FONT_TITLE)
	outer.add_child(title)
	GameTheme.deal_in(title, 0.02)

	# The moment of finding, not the price of leaving — and it echoes the road's
	# promise that everything on it is already expecting you.
	var flavor = GameTheme.make_label(
		"Choose the relic or take the gold.",
		20, GameTheme.DESC_DIM)
	flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(flavor)
	GameTheme.deal_in(flavor, 0.06)

	# Parchment divider + cartouche subheader (matches Event / Recruit): a
	# ruled plaque rather than a bare floating label.
	var section_header := _make_section_header("Relic Uncovered")
	outer.add_child(section_header)
	GameTheme.deal_in(section_header, 0.10)

	# The Reliquary is the act's dedicated relic stop, so it draws the CAMPAIGN
	# tier — the run-shaping relics (forge strength, recruit slate, veterancy
	# speed) that no other roll in the game reaches. Before this, every reward
	# path rolled the field pool and `roll_campaign_relics` had no caller at
	# all, stranding five implemented relics. The campaign tier is small and the
	# war chest spends four of it, so fall through to the field pool once it
	# runs dry rather than showing an empty plinth.
	var relics: Array[String] = []
	if RunState.current_node_type == "reliquary":
		relics = RelicDB.roll_campaign_relics(1, RunState.relics, RunState.current_hero_id)
	if relics.is_empty():
		relics = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
	var relic_row = HBoxContainer.new()
	relic_row.add_theme_constant_override("separation", 40)
	relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(relic_row)

	var relic_tile: Control = null
	var relic_i := 0
	for id in relics:
		var btn := _make_spoil_tile(id)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_pick_relic.bind(id, btn))
		relic_row.add_child(btn)
		var deal_at := 0.10 + relic_i * 0.08
		GameTheme.deal_in(btn, deal_at)
		# Waits out deal_in — both verbs drive `modulate` on the same node.
		GameTheme.rarity_reveal(btn, RelicDB.get_relic_rarity(id), deal_at + 0.36)
		GameTheme.hover_lift(btn)
		if relic_tile == null:
			relic_tile = btn
		relic_i += 1

	# The fork, stated once: claim the relic (tap it) OR take its weight in gold.
	var or_lbl = GameTheme.make_label("— or —", 17, Color(0.66, 0.60, 0.52))
	or_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(or_lbl)
	GameTheme.deal_in(or_lbl, 0.34)

	var skip_btn = GameTheme.make_back_button("Take %d Gold instead" % _gold_reward,
		Vector2(280, 52), 20)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_leave.bind(skip_btn))
	outer.add_child(skip_btn)
	GameTheme.deal_in(skip_btn, 0.40)
	GameTheme.hover_lift(skip_btn, 1.04)

	# The opening flourish bursts from the relic itself — coins fountaining
	# around the find with a warm bloom behind it, the chest-lid reveal beat.
	_spawn_coin_fountain(relic_tile if relic_tile != null else title)


func _spawn_coin_fountain(anchor: Control) -> void:
	# One-shot opening flourish: gold coin-sparks fountain up around the
	# uncovered relic and rain down the sheet, with a warm bloom behind it —
	# the chest-lid reveal. Runs once on entry; gated like every particle effect.
	if UserSettings != null and (not UserSettings.particles or UserSettings.reduce_motion):
		return
	if DisplayServer.get_name() == "headless":
		return
	# One frame so the VBox has laid the label out — its rect is (0,0) until then.
	await get_tree().process_frame
	if anchor == null or not is_instance_valid(anchor):
		return
	# The chest bursting open lands a small thump (trauma shake, R2).
	GameTheme.shake_impulse(self, 0.28)
	# Gentle toss up off the gold line, then a long rain down the sheet —
	# the "coin" preset's soft velocities keep it on-screen (the line sits
	# near the top of the sheet).
	var fountain_pos: Vector2 = anchor.get_global_rect().get_center() + Vector2(0, 6)
	Motion.burst(self, fountain_pos, "coin")
	# A soft golden bloom under the fountain, swelling once then dying.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.82, 0.38, 0.22), Color(1.0, 0.65, 0.20, 0.0)])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)
	grad_tex.width = 256
	grad_tex.height = 256
	var bloom := TextureRect.new()
	bloom.texture = grad_tex
	bloom.stretch_mode = TextureRect.STRETCH_SCALE
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bloom.position = fountain_pos - Vector2(300, 230)
	bloom.size = Vector2(600, 460)
	var bmat := CanvasItemMaterial.new()
	bmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	bloom.material = bmat
	bloom.modulate.a = 0.0
	add_child(bloom)
	var btw := bloom.create_tween()
	btw.tween_property(bloom, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)
	btw.tween_property(bloom, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	btw.tween_callback(bloom.queue_free)


## Rest / hover / pressed faces of the find, one lever (0 = rest, 1 = hot). The
## ember bleed is the stylebox's OWN shadow retinted — the kit's hover-glow
## lever — rather than a gradient pasted behind the tile.
func _spoil_style(lift: float) -> StyleBox:
	var s := GameTheme.make_panel_style(
		SPOIL_FILL.lightened(lift * 0.10),
		GameTheme.GILT.lerp(GameTheme.GILT_BRIGHT, lift), 2, 5, true, true)
	s.set("shadow_color", Color(SPOIL_EMBER.r, SPOIL_EMBER.g, SPOIL_EMBER.b,
		0.20 + 0.16 * lift))
	s.set("shadow_size", 16.0 + 8.0 * lift)
	return s


## The uncovered relic. GameTheme.make_relic_card sizes its icon from the BOX
## (min_size.y * 0.38, capped at 128), a recipe that only balances around a
## ~147px tile — at 360×320 a third of the tile was air, which is why the find
## read as a placeholder floating in a frame rather than a thing dug up. Cut
## the other way round: pick the size of the painting, then let fit_tile_height
## close the box onto it. Mirrors Reward._make_spoil_tile (the same duplication
## these two screens already carry for _make_section_header).
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


func _make_section_header(text: String) -> HBoxContainer:
	# A ruled subheader plaque: tan rule — gold caption — tan rule. Echoes the
	# chart furniture (make_screen_title's divider) so the relic-choice cue reads
	# as a document heading, not a stray label.
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
	# Quiet parchment caption, not gold — a document subheading shouldn't compete
	# with the screen title. Gold is reserved for the "+N gold" reward line.
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


func _pick_relic(id: String, tile: Control = null) -> void:
	if _resolved:
		return
	_resolved = true
	RunState.add_relic(id)
	# Claim beat: the chosen prize flares while the unpicked pair bows out,
	# then the fade takes it — same grab language as the Reward spoils.
	if tile != null and is_instance_valid(tile) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(tile)
		if tile.get_parent() != null:
			for sib in tile.get_parent().get_children():
				if sib != tile and sib is Control:
					var stw := (sib as Control).create_tween()
					stw.tween_property(sib, "modulate:a", 0.0, 0.22) \
						.set_ease(Tween.EASE_IN)
		await get_tree().create_timer(0.38).timeout
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


func _leave(tile: Control = null) -> void:
	if _resolved:
		return
	_resolved = true
	RunState.gain_gold(_gold_reward)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	if tile != null and is_instance_valid(tile) \
			and not (UserSettings != null and UserSettings.reduce_motion):
		GameTheme.claim_pop(tile)
		await get_tree().create_timer(0.18).timeout
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
