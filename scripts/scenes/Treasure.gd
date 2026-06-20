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
	_gold_reward = GOLD_BY_ACT[clampi(RunState.get_act() - 1, 0, 2)]
	# Gold is paid out at the exit (_pick_relic / _leave) rather than here, so
	# quitting mid-room and continuing back into Treasure doesn't double-pay.
	_build_ui()
	GameTheme.make_settings_gear(self)


func _build_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 24)
	margin.add_child(outer)

	var title = GameTheme.make_screen_title("TREASURE", GameTheme.KEYWORD_GOLD,
		GameTheme.FONT_HEADER)
	outer.add_child(title)

	var gold_label = GameTheme.make_label("+%d gold" % _gold_reward, 20, GameTheme.GILT_BRIGHT)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(gold_label)

	# Parchment divider + cartouche subheader (matches Event / Recruit): a
	# ruled "Choose a Relic" plaque rather than a bare floating label.
	outer.add_child(_make_section_header("Choose a Relic"))

	var relics = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
	var relic_row = HBoxContainer.new()
	relic_row.add_theme_constant_override("separation", 24)
	relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	relic_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(relic_row)

	for id in relics:
		# Chart-look tile: dark-ink PARCHMENT body so make_relic_card's internal
		# make_btn_style paints a document tile (gilt rule, small corners) instead
		# of the old flat orange slab. The painted relic icon rides on top.
		var btn = GameTheme.make_relic_card(id, GameTheme.PARCHMENT,
			Vector2(220, 150))
		# Hold the tile at its natural 220×150 and center it in the expanded row —
		# without this the Button fills the tall row vertically and reads as a big
		# slab with the content marooned in the middle.
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_pick_relic.bind(id))
		relic_row.add_child(btn)

	var skip_btn = GameTheme.make_back_button("Skip Relic", Vector2(160, 42))
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_leave)
	outer.add_child(skip_btn)


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
	var lbl := GameTheme.make_label(text, GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
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


func _pick_relic(id: String) -> void:
	if _resolved:
		return
	_resolved = true
	RunState.add_relic(id)
	RunState.gain_gold(_gold_reward)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


func _leave() -> void:
	if _resolved:
		return
	_resolved = true
	RunState.gain_gold(_gold_reward)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
