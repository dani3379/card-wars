extends Control
## Treasure.gd — Treasure node. Open a chest: pick 1 of 3 relics + bonus gold.
## Gold scales by act (40/60/80) to stay relevant in the doubled-gold economy.

const MAP_SCENE = "res://scenes/map.tscn"
const GOLD_BY_ACT := [40, 60, 80]

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
	_gold_reward = GOLD_BY_ACT[clampi(RunState.get_act() - 1, 0, 2)]
	# Gold is paid out at the exit (_pick_relic / _leave) rather than here, so
	# quitting mid-room and continuing back into Treasure doesn't double-pay.
	_build_ui()
	GameTheme.make_settings_gear(self)


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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 28)
	margin.add_child(outer)

	var title = GameTheme.make_screen_title("TREASURE", GameTheme.KEYWORD_GOLD,
		GameTheme.FONT_TITLE)
	outer.add_child(title)
	GameTheme.deal_in(title, 0.02)

	var gold_label = GameTheme.make_label("+%d gold" % _gold_reward, 24, GameTheme.GILT_BRIGHT)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(gold_label)
	GameTheme.deal_in(gold_label, 0.06)
	# The hoard spills as the lid comes up: the gold line counts up from zero
	# while a fountain of coin-sparks bursts from it and rains down the sheet.
	GameTheme.tick_number(gold_label, 0, _gold_reward, "+%d gold", 0.7)
	_spawn_coin_fountain(gold_label)

	# Parchment divider + cartouche subheader (matches Event / Recruit): a
	# ruled "Choose a Relic" plaque rather than a bare floating label.
	var section_header := _make_section_header("Choose a Relic")
	outer.add_child(section_header)
	GameTheme.deal_in(section_header, 0.10)

	var relics = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
	var relic_row = HBoxContainer.new()
	relic_row.add_theme_constant_override("separation", 40)
	relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	relic_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(relic_row)

	var relic_i := 0
	for id in relics:
		# Chart-look tile: dark-ink PARCHMENT body so make_relic_card's internal
		# make_btn_style paints a document tile (gilt rule, small corners) instead
		# of the old flat orange slab. The painted relic icon rides on top.
		# Big tiles (340×300): the relics were narrow/tall slabs marooning their
		# rules text — grow them to fill the row and make the effect legible.
		var btn = GameTheme.make_relic_card(id, GameTheme.PARCHMENT,
			Vector2(340, 300))
		# Hold the tile at its natural 220×150 and center it in the expanded row —
		# without this the Button fills the tall row vertically and reads as a big
		# slab with the content marooned in the middle.
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_pick_relic.bind(id, btn))
		relic_row.add_child(btn)
		GameTheme.deal_in(btn, 0.10 + relic_i * 0.08)
		GameTheme.hover_lift(btn)
		relic_i += 1

	var skip_btn = GameTheme.make_back_button("Take Gold Only", Vector2(220, 52), 20)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_leave.bind(skip_btn))
	outer.add_child(skip_btn)
	GameTheme.deal_in(skip_btn, 0.40)
	GameTheme.hover_lift(skip_btn, 1.04)


func _spawn_coin_fountain(anchor: Control) -> void:
	# One-shot opening flourish: gold coin-sparks fountain up from the gold
	# line itself and rain down the sheet. Runs once on entry; gated the
	# same way as every particle effect.
	if UserSettings != null and (not UserSettings.particles or UserSettings.reduce_motion):
		return
	if DisplayServer.get_name() == "headless":
		return
	# One frame so the VBox has laid the label out — its rect is (0,0) until then.
	await get_tree().process_frame
	if anchor == null or not is_instance_valid(anchor):
		return
	var p := CPUParticles2D.new()
	p.position = anchor.get_global_rect().get_center() + Vector2(0, 6)
	p.z_index = 60
	p.one_shot = true
	p.explosiveness = 0.55
	p.amount = 46
	p.lifetime = 1.5
	p.direction = Vector2(0, -1)
	p.spread = 52.0
	p.gravity = Vector2(0, 460.0)
	# Gentle toss up off the gold line, then a long rain down the sheet —
	# the line sits near the top, so hard velocities would leave the screen.
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.scale_amount_min = 3.6
	p.scale_amount_max = 6.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.92, 0.55, 1.0))
	ramp.set_color(1, Color(0.85, 0.58, 0.16, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.4).timeout.connect(p.queue_free)
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
	bloom.position = p.position - Vector2(300, 230)
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
	RunState.gain_gold(_gold_reward)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
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
