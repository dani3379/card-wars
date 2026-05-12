extends Control
## Reward.gd — after a non-boss victory. Pick 1 of 3 cards, or skip.
## On elite floors also offers a relic choice. Fully programmatic UI.

const MAP_SCENE = "res://scenes/map.tscn"

var _card_choices: Array[String] = []
var _relic_choices: Array[String] = []
var _is_elite_reward: bool = false


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	GameTheme.add_atmosphere(self, "reward")
	var node_type = RunState.current_node_type
	_is_elite_reward = (node_type == "elite" or node_type == "boss")
	var is_boss = (node_type == "boss")

	# Busted Crown: only 1 card choice instead of 3
	var reward_count := 3
	if RunState.has_downside("fewer_rewards"):
		reward_count = 1
	_card_choices = CardDB.roll_card_reward(RunState.get_act(), node_type == "elite", is_boss)
	if _card_choices.size() > reward_count:
		_card_choices = _card_choices.slice(0, reward_count)

	# Cursed Key: gain a curse after combat
	if RunState.has_downside("curse_on_reward"):
		RunState.add_card("curse")

	if is_boss:
		_relic_choices = RelicDB.roll_boss_relics(RunState.relics)
	elif _is_elite_reward:
		_relic_choices = RelicDB.roll_relic_reward("combat", RunState.relics)

	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	# Title
	var title = GameTheme.make_screen_title(
		"VICTORY  —  Floor %d" % RunState.current_floor, GameTheme.GILT_BRIGHT,
		GameTheme.FONT_HEADER)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 22
	title.offset_bottom = 70
	add_child(title)

	# Subtitle
	if _card_choices.size() > 0:
		var subtitle = GameTheme.make_label("Add a card to your deck",
			GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
		subtitle.offset_top = 72
		subtitle.offset_bottom = 102
		add_child(subtitle)

	# Card choices — centered
	var card_row = HBoxContainer.new()
	card_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	card_row.offset_top = 120
	card_row.offset_bottom = 300
	card_row.add_theme_constant_override("separation", 24)
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(card_row)

	for id in _card_choices:
		var data = CardDB.get_card_data(id)
		var card_text: String
		if data.get("type", "creature") == "spell":
			card_text = "%s\n%d mana  SPELL\n%s" % [data.name, data.cost, _kw_text(data)]
		else:
			card_text = "%s\n%d mana  %d/%d\n%s" % [data.name, data.cost, data.atk, data.hp, _kw_text(data)]
		var color = Color(0.15, 0.12, 0.30) if data.get("type", "") == "spell" else Color(0.20, 0.25, 0.35)
		var btn = GameTheme.make_themed_button(card_text, color, Vector2(200, 160), 13, data.desc)
		btn.pressed.connect(_pick_card.bind(id))
		card_row.add_child(btn)

	# Relic choices
	if _is_elite_reward and _relic_choices.size() > 0:
		var relic_title = GameTheme.make_label("Choose a relic",
			GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
		relic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		relic_title.position = Vector2(500, 330)
		relic_title.size = Vector2(600, 30)
		add_child(relic_title)

		var relic_row = HBoxContainer.new()
		relic_row.position = Vector2(300, 370)
		relic_row.add_theme_constant_override("separation", 24)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		add_child(relic_row)

		for id in _relic_choices:
			var relic = RelicDB.get_relic(id)
			var btn = GameTheme.make_themed_button("%s\n%s" % [relic.name, relic.desc],
				Color(0.55, 0.30, 0.20), Vector2(220, 120), 13)
			btn.pressed.connect(_pick_relic.bind(id))
			relic_row.add_child(btn)

	# Skip button
	var skip_btn = GameTheme.make_themed_button("Skip", Color(0.30, 0.20, 0.15), Vector2(120, 36))
	skip_btn.position = Vector2(740, 810)
	skip_btn.pressed.connect(_skip)
	add_child(skip_btn)


func _kw_text(data: Dictionary) -> String:
	if not data.has("keywords") or data.keywords.is_empty():
		return ""
	return ", ".join(data.keywords)


func _pick_card(id: String) -> void:
	RunState.add_card(id)
	if _is_elite_reward and _relic_choices.size() > 0:
		_card_choices.clear()
		_build_ui()
	else:
		get_tree().change_scene_to_file(MAP_SCENE)


func _pick_relic(id: String) -> void:
	RunState.add_relic(id)
	get_tree().change_scene_to_file(MAP_SCENE)


func _skip() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
