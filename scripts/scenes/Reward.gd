extends Control
## Reward.gd — after a non-boss victory. Pick 1 of 3 cards, or skip.
## On elite floors also offers a relic choice. Fully programmatic UI.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"
# Skip-card-for-gold payout. Card price floor (50g common) gives the player
# a real reason to skip if they don't see a deck fit.
const SKIP_CARD_GOLD := 20

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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	# Title
	var title = GameTheme.make_screen_title(
		"VICTORY  —  Floor %d" % RunState.current_floor, GameTheme.GILT_BRIGHT,
		GameTheme.FONT_HEADER)
	outer.add_child(title)

	# Card choices — real Card2D instances with pick buttons
	if _card_choices.size() > 0:
		var subtitle = GameTheme.make_label("Add a card to your deck",
			GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(subtitle)

		var card_row = HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 30)
		card_row.alignment = BoxContainer.ALIGNMENT_CENTER
		card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(card_row)

		for id in _card_choices:
			var data = CardDB.get_card_data(id)
			var slot := VBoxContainer.new()
			slot.add_theme_constant_override("separation", 8)
			slot.alignment = BoxContainer.ALIGNMENT_CENTER
			card_row.add_child(slot)

			var card = CARD_SCENE.instantiate()
			card.card_data = data.duplicate(true)
			card.card_id = id
			card.is_on_battlefield = true
			slot.add_child(card)

			var pick_btn = GameTheme.make_themed_button("Pick",
				Color(0.18, 0.30, 0.14), Vector2(120, 36), 15)
			pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pick_btn.pressed.connect(_pick_card.bind(id))
			slot.add_child(pick_btn)

	# Relic choices
	if _is_elite_reward and _relic_choices.size() > 0:
		var sep := GameTheme.make_separator(GameTheme.GILT, 200.0)
		outer.add_child(sep)

		var relic_title = GameTheme.make_label("Choose a relic",
			GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
		relic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(relic_title)

		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 24)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(relic_row)

		for id in _relic_choices:
			var relic = RelicDB.get_relic(id)
			var btn = GameTheme.make_themed_button("%s\n%s" % [relic.name, relic.desc],
				Color(0.55, 0.30, 0.20), Vector2(220, 120), 13)
			btn.pressed.connect(_pick_relic.bind(id))
			relic_row.add_child(btn)

	# Skip choices — bottom center. Skipping the card now pays out gold instead,
	# which gives the "skip for tempo" choice from STS/Monster Train a real payoff.
	if _card_choices.size() > 0:
		var skip_row := HBoxContainer.new()
		skip_row.alignment = BoxContainer.ALIGNMENT_CENTER
		skip_row.add_theme_constant_override("separation", 16)
		outer.add_child(skip_row)
		var skip_gold = SKIP_CARD_GOLD
		var skip_gold_btn = GameTheme.make_themed_button(
			"Skip card  →  +%d gold" % skip_gold, Color(0.30, 0.25, 0.10),
			Vector2(220, 36), 15)
		skip_gold_btn.pressed.connect(_skip_for_gold)
		skip_row.add_child(skip_gold_btn)
		var skip_btn = GameTheme.make_themed_button("Skip", Color(0.30, 0.20, 0.15),
			Vector2(120, 36), 15)
		skip_btn.pressed.connect(_skip)
		skip_row.add_child(skip_btn)
	else:
		var skip_btn = GameTheme.make_themed_button("Continue", Color(0.30, 0.20, 0.15),
			Vector2(140, 36), 15)
		skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		skip_btn.pressed.connect(_skip)
		outer.add_child(skip_btn)


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


func _skip_for_gold() -> void:
	# "I don't see a card I want — pay me instead." Costs nothing extra and the
	# gold rolls into the next shop/event.
	RunState.gain_gold(SKIP_CARD_GOLD)
	if _is_elite_reward and _relic_choices.size() > 0:
		_card_choices.clear()
		_build_ui()
	else:
		get_tree().change_scene_to_file(MAP_SCENE)
