extends Control
## Reward.gd — after a non-boss victory. Pick 1 of 3 cards, or skip.
## On elite floors also offers a relic choice.

const MAP_SCENE = "res://scenes/map.tscn"

var _card_choices: Array[String] = []
var _relic_choices: Array[String] = []
var _is_elite_reward: bool = false


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	MenuAtmosphere.attach_to(self)
	_is_elite_reward = (RunState.node_type_for_floor(RunState.current_floor) == "elite")
	_card_choices = CardDB.roll_card_reward(RunState.current_floor)
	if _is_elite_reward:
		_relic_choices = RelicDB.roll_relic_reward(2, RunState.relics)

	_build_ui()


func _build_ui() -> void:
	$Title.text = "VICTORY  —  Floor %d" % RunState.current_floor
	$Subtitle.text = "Add a card to your deck"

	for child in $CardRow.get_children():
		child.queue_free()
	for child in $RelicRow.get_children():
		child.queue_free()

	for id in _card_choices:
		var data = CardDB.get_card_data(id)
		var kw_text = KeywordEffects.display_text_for(data.get("keywords", []))
		var btn = _make_choice_button(
			"%s\n%d⚡  %d/%d\n%s" % [data.name, data.cost, data.atk, data.hp, kw_text],
			data.desc, Color(0.20, 0.25, 0.35))
		btn.pressed.connect(_pick_card.bind(id))
		$CardRow.add_child(btn)

	if _is_elite_reward and _relic_choices.size() > 0:
		$RelicTitle.text = "Choose a relic (elite reward)"
		for id in _relic_choices:
			var relic = RelicDB.get_relic(id)
			var btn = _make_choice_button(relic.name, relic.desc,
				Color(0.55, 0.30, 0.20))
			btn.pressed.connect(_pick_relic.bind(id))
			$RelicRow.add_child(btn)
	else:
		$RelicTitle.visible = false

	MenuAtmosphere.style_button($SkipBtn, false)
	$SkipBtn.pressed.connect(_skip)


func _make_choice_button(title: String, tooltip: String, _color: Color) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(200, 150)
	btn.text = title
	btn.tooltip_text = tooltip
	btn.add_theme_font_size_override("font_size", 15)
	MenuAtmosphere.style_button(btn, true)
	return btn


func _pick_card(id: String) -> void:
	RunState.add_card(id)
	# If elite, still need to pick a relic (or skip)
	if _is_elite_reward and _relic_choices.size() > 0:
		_card_choices.clear()
		_build_ui()
		$Title.text = "Now pick a relic"
		$Subtitle.text = ""
	else:
		get_tree().change_scene_to_file(MAP_SCENE)


func _pick_relic(id: String) -> void:
	RunState.add_relic(id)
	get_tree().change_scene_to_file(MAP_SCENE)


func _skip() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)
