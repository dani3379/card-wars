extends Control
## Treasure.gd — Treasure node. Open a chest: pick 1 of 3 relics + bonus gold.
## Gold scales by act (40/60/80) to stay relevant in the doubled-gold economy.

const MAP_SCENE = "res://scenes/map.tscn"
const GOLD_BY_ACT := [40, 60, 80]

var _gold_reward: int = 40


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "reward")
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

	var sep := GameTheme.make_separator(GameTheme.GILT, 200.0)
	outer.add_child(sep)

	var relic_title = GameTheme.make_label("Choose a relic",
		GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
	relic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(relic_title)

	var relics = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)
	var relic_row = HBoxContainer.new()
	relic_row.add_theme_constant_override("separation", 24)
	relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	relic_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(relic_row)

	for id in relics:
		var btn = GameTheme.make_relic_card(id, Color(0.55, 0.30, 0.20),
			Vector2(220, 150))
		# Hold the tile at its natural 220×150 and center it in the expanded row —
		# without this the Button fills the tall row vertically and reads as a big
		# flat orange slab with the content marooned in the middle.
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(_pick_relic.bind(id))
		relic_row.add_child(btn)

	var skip_btn = GameTheme.make_back_button("SKIP RELIC", Vector2(160, 42))
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_leave)
	outer.add_child(skip_btn)


func _pick_relic(id: String) -> void:
	RunState.add_relic(id)
	RunState.gain_gold(_gold_reward)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)


func _leave() -> void:
	RunState.gain_gold(_gold_reward)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
