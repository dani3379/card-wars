extends Control
## Reward.gd — the post-victory SPOILS screen (Successor Wars): elites pick
## a relic, bosses pick a boss relic. Cards no longer drop from fights —
## deck growth lives at recruit stops (Recruit.gd) — so normal combats skip
## this screen entirely and march straight back to the map.
## Fully programmatic UI.

const MAP_SCENE = "res://scenes/map.tscn"
const COMBAT_SCENE = "res://scenes/combat.tscn"

var _relic_choices: Array[String] = []
var _is_elite_reward: bool = false


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	GameTheme.add_atmosphere(self, "reward")
	# Reward continues whatever combat music faded out; if no track is loaded,
	# the map track keeps quiet — no separate "reward" music asset needed.
	var node_type = RunState.current_node_type
	_is_elite_reward = (node_type == "elite" or node_type == "boss")
	var is_boss = (node_type == "boss")

	if is_boss:
		_relic_choices = RelicDB.roll_boss_relics(RunState.relics, RunState.current_hero_id)
	elif _is_elite_reward:
		_relic_choices = RelicDB.roll_relic_reward("combat", RunState.relics, RunState.current_hero_id)

	# Olympian's Mark: after every elite victory, upgrade one random un-upgraded
	# creature/spell in the deck for free. Applies the same "+" upgrade the
	# rest-site offers, so the relic stays in lockstep with the player-driven
	# forge path instead of carving out a parallel buff.
	if node_type == "elite" and RunState.has_relic("olympians_mark"):
		var candidates: Array[int] = []
		for i in RunState.deck.size():
			if not RunState.is_card_upgraded(i):
				var d: Dictionary = CardDB.get_card_data(RunState.deck[i])
				if d.get("type", "") in ["creature", "spell"] \
						and CardDB.is_upgradeable(RunState.deck[i]):
					candidates.append(i)
		if candidates.size() > 0:
			RunState.upgrade_card(candidates[randi() % candidates.size()], "plus")

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

	# Relic choices
	if _is_elite_reward and _relic_choices.size() > 0:
		var relic_title = GameTheme.make_label("Choose a Relic",
			GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
		relic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(relic_title)

		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 24)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		relic_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(relic_row)

		for id in _relic_choices:
			var btn = GameTheme.make_relic_card(id, Color(0.55, 0.30, 0.20),
				Vector2(220, 150))
			# Shrink-center: the row owns the freed vertical space now that
			# the card rack is gone, and HBox children stretch by default —
			# without this the relic panels render as full-height columns.
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.pressed.connect(_pick_relic.bind(id))
			relic_row.add_child(btn)

	var skip_btn = GameTheme.make_back_button("Continue", Vector2(160, 42))
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_skip)
	outer.add_child(skip_btn)


func _pick_relic(id: String) -> void:
	RunState.add_relic(id)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	_proceed()


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

	var sub = GameTheme.make_label("Choose whose kingdom burns next.",
		GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)

	for i in range(next_idx, RunState.rival_lords.size()):
		var lord: String = RunState.rival_lords[i]
		var info: Dictionary = HeroDB.faction_info(HeroDB.get_faction(lord))
		var lord_name := String(HeroDB.get_hero(lord).get("name", lord)).to_upper()
		var desc := "%s — %s\n%s" % [String(info.get("name", "")),
			String(info.get("engine", "")), String(info.get("engine_line", ""))]
		var banner = GameTheme.make_choice_banner(lord_name, desc,
			info.get("color", Color(0.60, 0.51, 0.34)), "", Vector2(380, 170))
		var click := banner.get_node_or_null("ClickButton") as Button
		if click != null:
			click.pressed.connect(_pick_march.bind(lord))
		row.add_child(banner)


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
