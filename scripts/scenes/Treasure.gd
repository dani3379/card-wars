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

## The strongbox the find comes out of (2026-08-05). Cut wider and taller than
## the 330px tile on purpose: the box has to be visible either side of the relic
## and hang below it, or it reads as a frame rather than as a container.
const CacheChest := preload("res://scripts/ui/painters/CacheChest.gd")
const CARD_SCENE := preload("res://scenes/card_2d.tscn")
const CARD_BACK_TEXTURE := preload("res://assets/ui/card_back.png")
## Measured off the first render, not guessed. At 560x300 behind a ~390px-wide
## tile the box showed ~85px either side and nothing above — it read as two tan
## slivers, not a container. A prop that something sits IN has to be plainly
## bigger than the thing: 860 leaves ~235px of box either side of the tile, and
## the stage is cut taller than the chest so the thrown-back lid clears the
## tile's top edge instead of hiding behind it.
const CHEST_W := 860.0
const CHEST_H := 440.0
const CHEST_STAGE_H := 520.0
const CHEST_TILE_DROP := 150.0

var _gold_reward: int = 40
var _chest: Control = null
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
		options.append({"label": "Take Potions", "desc": "Gain up to 2 random potions.",
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
				"Supply Cache — choose a card to forge", "upgradeable", false)
			if deck_index >= 0:
				RunState.upgrade_card(deck_index, "plus")
				await _show_forged_card(deck_index)
		"potions":
			for _i in 2:
				if not RunState.can_add_potion():
					break
				RunState.add_potion(PotionDB.roll_random_potion())
		"gold":
			RunState.gain_gold(arsenal_gold)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


## THE ARSENAL'S FORGE HAD NO BEAT. show_deck_picker tears its modal down on the
## click, so this stop mutated the card and changed scene in the same frame —
## the one halt on the road whose entire payoff is a card getting better, and the
## card was never on screen when it did. Camp and the General's Forge both show
## the "+" writ and strike it; this now does the same, in one coordinate space
## (a plain dim Control on the scene, not a CanvasLayer) so forge_strike's ring
## and sparks land where the card actually is.
func _show_forged_card(deck_index: int) -> void:
	if deck_index < 0 or deck_index >= RunState.deck.size():
		return
	var data: Dictionary = RunState.get_upgraded_card_data(deck_index)
	var dim := ColorRect.new()
	dim.name = "ForgeReveal"
	dim.color = Color(0.03, 0.02, 0.05, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 120
	add_child(dim)

	var wrapper := Control.new()
	wrapper.name = "ForgeCardSlot"
	wrapper.custom_minimum_size = Vector2(225, 300)
	wrapper.set_anchors_preset(Control.PRESET_CENTER)
	wrapper.offset_left = -112
	wrapper.offset_right = 113
	wrapper.offset_top = -150
	wrapper.offset_bottom = 150
	wrapper.pivot_offset = Vector2(112.5, 150.0)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(wrapper)

	# Reserve the final card rectangle before the first await. A cold gallery bake
	# used to leave this blocking modal as an empty black sheet, then pop the card
	# into existence when the cache finished. The facedown writ is truthful
	# content while the finished face hydrates behind it and changes no geometry.
	var loading_back := TextureRect.new()
	loading_back.name = "LoadingWrit"
	loading_back.texture = CARD_BACK_TEXTURE
	loading_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	loading_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	loading_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.arm_loading_writ(loading_back)
	wrapper.add_child(loading_back)

	var preparing := GameTheme.make_label("TEMPERING THE WRIT...", 17,
		Color(GameTheme.IVORY.r, GameTheme.IVORY.g, GameTheme.IVORY.b, 0.74))
	preparing.name = "ForgePreparing"
	preparing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preparing.set_anchors_preset(Control.PRESET_CENTER)
	preparing.offset_left = -210
	preparing.offset_right = 210
	preparing.offset_top = 168
	preparing.offset_bottom = 198
	preparing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(preparing)

	# Weak references keep dismissal safe while the bake/presentation awaits are
	# parked. Capturing dim directly makes Godot marshal a freed Object before
	# is_instance_valid can inspect it, producing a lambda-capture error.
	var host_ref: WeakRef = weakref(self)
	var dim_ref: WeakRef = weakref(dim)
	var preview_alive := func() -> bool:
		var host: Node = host_ref.get_ref() as Node
		var live_dim: Control = dim_ref.get_ref() as Control
		return host != null and is_instance_valid(host) and host.is_inside_tree() and live_dim != null and is_instance_valid(live_dim)
	# Present the honest loading state before any cold bake starts doing work.
	await _present_frame()
	if not preview_alive.call():
		return
	await CardTextureCache.bake_gallery(data, preview_alive)
	if not preview_alive.call():
		return

	var card = CARD_SCENE.instantiate()
	card.card_data = data.duplicate(true)
	card.card_id = data.get("id", "")
	card.static_display = true
	card.live_baked_mode = true
	card.gallery_baked_mode = true
	card.modulate.a = 0.0
	wrapper.add_child(card)
	# Cold and warm paths share one presentation boundary: the complete card is
	# ready behind the back before either half of the turn becomes visible.
	await _present_frame()
	if not preview_alive.call() or not is_instance_valid(card):
		return

	var snap_reveal := DisplayServer.get_name() == "headless" or (UserSettings != null and UserSettings.reduce_motion)
	card.modulate.a = 1.0
	if snap_reveal:
		loading_back.queue_free()
		preparing.text = "THE WRIT IS FORGED"
	else:
		preparing.text = "UNSEALING THE WRIT..."
		AudioBank.play_sfx("card_draw", 0.04, -6.0)
		Motion.flip_out(loading_back, 0.13)
		Motion.flip_in(card, Motion.time(0.13), 0.17)
		await get_tree().create_timer(maxf(Motion.time(0.34), 0.01)).timeout
		if not preview_alive.call() or not is_instance_valid(card):
			return
	AudioBank.play_sfx("upgrade_confirm")
	await GameTheme.forge_strike(self, wrapper)
	if not preview_alive.call() or not is_instance_valid(preparing):
		return
	preparing.text = "THE WRIT IS FORGED"
	# The outgoing ink transition supplies the readable hold under Reduce Motion;
	# do not make accessibility users wait through two vanished flourishes.
	if not snap_reveal:
		await get_tree().create_timer(maxf(Motion.time(0.28), 0.01)).timeout


func _present_frame() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw

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
	#
	# The gate reads "treasure", not "reliquary": there IS no node type spelled
	# reliquary. `CampaignMapGenerator._force_one(grid, 7, "treasure", rng)` is the
	# Reliquary — the one treasure stop an act deals — and row 13's Arsenal wears
	# "arsenal" and returned at the top of _ready. Written against the display
	# name, the branch could never fire and the five campaign relics stayed
	# stranded, which is the exact bug the paragraph above says it fixed.
	# "reliquary" is kept as an alias so a legacy save that stored it still lands
	# on the campaign tier (MainMenu's resume router already accepts the spelling).
	var relics: Array[String] = []
	if RunState.current_node_type in ["treasure", "reliquary"]:
		relics = RelicDB.roll_campaign_relics(1, RunState.relics, RunState.current_hero_id)
	if relics.is_empty():
		relics = RelicDB.roll_field_relics(1, RunState.relics, RunState.current_hero_id)
	# ── THE STOP GETS A PROP (2026-08-05) ──
	# This was the one roadside verb with nothing physical on it: every sibling
	# stages something (the knucklebone patch, the sappers' kegs, the
	# quartermaster's scale, the Fourth's strongbox), and the stop whose entire
	# copy is "Relic Uncovered" showed a dialog tile on a painted forest. Both
	# 2026-08 hunts logged it.
	#
	# The chest is drawn BEHIND the relic tile and reaches up past it, so the
	# find sits in the box's mouth — the tile is what you click, the box is what
	# it came out of. The lid throws back on entry, which is the beat the coin
	# fountain was already firing for without anything to fire from.
	# One stage holds both, chest added FIRST so it draws behind. The box is cut
	# deliberately wider and taller than the tile, and hangs below it, so what
	# reads is a relic being lifted out of a strongbox rather than a tile with a
	# decoration stuck on.
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, CHEST_STAGE_H)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(stage)

	var chest := CacheChest.new()
	chest.name = "CacheChest"
	chest.seed_text = "cache-%d-%d" % [RunState.current_act_idx, RunState.current_floor]
	chest.open_t = 0.0
	chest.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	chest.offset_left = -CHEST_W * 0.5
	chest.offset_right = CHEST_W * 0.5
	chest.anchor_left = 0.5
	chest.anchor_right = 0.5
	chest.offset_top = -CHEST_H
	chest.offset_bottom = 0
	stage.add_child(chest)
	_chest = chest

	var relic_row = HBoxContainer.new()
	relic_row.add_theme_constant_override("separation", 40)
	relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Pinned to the TOP of the stage: the tile hangs from there and the box
	# rises behind its lower half, which puts the find at the mouth without
	# either control needing to know the other's measured height.
	relic_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	relic_row.offset_top = CHEST_TILE_DROP
	stage.add_child(relic_row)

	var relic_tile: Control = null
	var relic_i := 0
	for id in relics:
		var btn := _make_spoil_tile(id)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_pick_relic.bind(id, btn))
		relic_row.add_child(btn)
		var deal_at := 0.10 + relic_i * 0.08
		# IT COMES OUT OF THE CHEST, so it RISES (2026-09-10). The spoils row on
		# the Reward screen drops its tiles onto the table because that is what
		# happens there; here the box is open directly below the tile (see the
		# anchor note above) and the find is being lifted out of it. Same verb,
		# inverted throw — a relic falling from the sky onto an open chest is the
		# one reading the staging makes impossible.
		Motion.drop_item(btn, deal_at, {
			"from": Vector2(0.0, 86.0), "spin": -0.07, "dur": 0.34,
		})
		# Waits out the rise — `rarity_reveal` drives `modulate` and wants to land
		# on a tile that has stopped moving.
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

	# THE LID THROWS BACK, and the coin fountain finally has something to come
	# out of. This beat has been firing since the 2026-07-19 pass — its own
	# comment already called it "the chest-lid reveal" — against a screen with no
	# chest on it. `open_t` drives the whole prop (lift, foreshortening, the
	# mouth's depth and the find's glow), so one property tween is the entire
	# animation. DECORATIVE by the Motion contract: Reduce Motion gets the box
	# already open rather than a shut one, because the state has to land.
	if _chest != null and is_instance_valid(_chest):
		if UserSettings != null and UserSettings.reduce_motion:
			_chest.open_t = 1.0
			_chest.queue_redraw()
			_chest.call_deferred("freeze_current_pose")
		else:
			var tw := _chest.create_tween()
			tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_method(func(v: float) -> void:
				if is_instance_valid(_chest):
					_chest.open_t = v
					_chest.queue_redraw(),
				0.0, 1.0, Motion.time(0.42)).set_delay(0.10)
			tw.tween_callback(func() -> void:
				if is_instance_valid(_chest):
					_chest.call("freeze_current_pose"))
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
	# The uncovered object leaves the strongbox and travels into the player's
	# pack. Its socket remains in layout while pocket_away renders it top-level,
	# so the chest and page never jump under the moving relic.
	var animate := tile != null and is_instance_valid(tile) \
		and DisplayServer.get_name() != "headless" \
		and not (UserSettings != null and UserSettings.reduce_motion)
	if animate:
		GameTheme.claim_pop(tile)
		await get_tree().create_timer(0.12).timeout
		if not is_inside_tree() or not is_instance_valid(tile):
			return
		await GameTheme.pocket_away(tile, _pack_point(), 0.34)
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)



func _pack_point() -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(viewport_size.x * 0.5, viewport_size.y + 30.0)

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
