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
var _mutator_bonus_gold: int = 0
var _mutator_name: String = ""
# Collector's Tome: how many of the 2 allowed picks have been taken so far.
# Resets implicitly on scene unload (a fresh Reward instance starts at 0).
var _collectors_tome_picks: int = 0


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

	# Busted Crown: only 1 card choice instead of 3.
	# Scout's Emblem: see 4 choices instead of 3 (overrides default, NOT downside).
	var reward_count := 3
	if RunState.has_downside("fewer_rewards"):
		reward_count = 1
	elif RunState.has_relic("scouts_emblem"):
		reward_count = 4
	_card_choices = CardDB.roll_card_reward(
		RunState.get_act(), node_type == "elite", is_boss, reward_count)
	if _card_choices.size() > reward_count:
		_card_choices = _card_choices.slice(0, reward_count)
	# Stardust Vial: append a rare-rarity ("boss-tier" in our schema is rare)
	# card option on non-boss reward screens. Boss rewards already roll rares.
	if not is_boss and RunState.has_relic("stardust_vial"):
		var rare_pool: Array[String] = CardDB.get_pool_by_rarity("rare")
		if rare_pool.size() > 0:
			var picked: String = rare_pool[randi() % rare_pool.size()]
			if not _card_choices.has(picked):
				_card_choices.append(picked)

	# Cursed Key: gain a curse after combat
	if RunState.has_downside("curse_on_reward"):
		RunState.add_card(CardDB.random_curse_id())

	# Mutator bonus gold: the fight we just won carried a per-fight modifier.
	# Pay out its gold_bonus once, then clear the id so subsequent map nodes
	# don't double-pay if the player re-enters Reward via save/load.
	_mutator_bonus_gold = 0
	_mutator_name = ""
	if RunState.current_mutator_id != "" and MutatorDB.exists(RunState.current_mutator_id):
		var mut: Dictionary = MutatorDB.get_mutator(RunState.current_mutator_id)
		_mutator_bonus_gold = int(mut.get("gold_bonus", 0))
		_mutator_name = String(mut.get("name", ""))
		if _mutator_bonus_gold > 0:
			RunState.gold += _mutator_bonus_gold
		RunState.current_mutator_id = ""

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

	# Mutator payout line — sits under the title so it reads as part of the
	# victory beat. Only appears for mutator fights that actually paid bonus
	# gold; pure-gift mutators (gold_bonus == 0) get a softer reminder line.
	if _mutator_name != "":
		var mut_line: Label
		if _mutator_bonus_gold > 0:
			mut_line = GameTheme.make_label(
				"★ %s bonus: +%d gold" % [_mutator_name, _mutator_bonus_gold],
				GameTheme.FONT_SUBHEADER, Color(1.0, 0.78, 0.32))
		else:
			mut_line = GameTheme.make_label(
				"★ Survived %s" % _mutator_name,
				GameTheme.FONT_SUBHEADER, Color(0.55, 1.0, 0.70))
		mut_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(mut_line)

	# Card choices — real Card2D instances with pick buttons
	if _card_choices.size() > 0:
		var subtitle = GameTheme.make_label("Add a Card to Your Deck",
			GameTheme.FONT_SUBHEADER, GameTheme.IVORY)
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(subtitle)

		var card_row = HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 30)
		card_row.alignment = BoxContainer.ALIGNMENT_CENTER
		card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(card_row)

		var slot_idx := 0
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

			var pick_btn = GameTheme.make_back_button("Pick", Vector2(120, 36), 16,
				GameTheme.KEYWORD_GOLD)
			pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			pick_btn.pressed.connect(_pick_card.bind(id))
			slot.add_child(pick_btn)

			# Staggered fan-in reveal: each card starts small + transparent +
			# offset down, then springs into place one after the other. Reads as
			# "the spoils unfurl before you" rather than "everything pops in".
			_animate_card_reveal(card, pick_btn, slot_idx)
			slot_idx += 1

	# Relic choices
	if _is_elite_reward and _relic_choices.size() > 0:
		var sep := GameTheme.make_separator(GameTheme.GILT, 200.0)
		outer.add_child(sep)

		var relic_title = GameTheme.make_label("Choose a Relic",
			GameTheme.FONT_SUBHEADER, GameTheme.KEYWORD_GOLD)
		relic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outer.add_child(relic_title)

		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 24)
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		outer.add_child(relic_row)

		for id in _relic_choices:
			var btn = GameTheme.make_relic_card(id, Color(0.55, 0.30, 0.20),
				Vector2(220, 150))
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
		var skip_gold_btn = GameTheme.make_back_button(
			"Skip Card  →  +%d gold" % skip_gold, Vector2(220, 40), 16)
		skip_gold_btn.pressed.connect(_skip_for_gold)
		skip_row.add_child(skip_gold_btn)
		var skip_btn = GameTheme.make_back_button("Skip", Vector2(140, 40))
		skip_btn.pressed.connect(_skip)
		skip_row.add_child(skip_btn)
	else:
		var skip_btn = GameTheme.make_back_button("Continue", Vector2(160, 42))
		skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		skip_btn.pressed.connect(_skip)
		outer.add_child(skip_btn)


func _animate_card_reveal(card: Control, pick_btn: Control, idx: int) -> void:
	# Hide the card + button, then spring them in after a staggered delay so the
	# three reward choices reveal one-by-one.
	card.modulate.a = 0.0
	card.scale = Vector2(0.6, 0.6)
	pick_btn.modulate.a = 0.0
	var delay := 0.18 + float(idx) * 0.16
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.28).set_delay(delay)
	tw.tween_property(card, "scale", Vector2.ONE, 0.36) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	tw.tween_property(pick_btn, "modulate:a", 1.0, 0.24).set_delay(delay + 0.18)


func _pick_card(id: String) -> void:
	RunState.add_card(id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Collector's Tome: pick 2 cards instead of 1. Track the pick count via
	# _collectors_tome_picks; when the player has chosen the second card,
	# advance normally. Skip the bonus on boss rewards (already chunky).
	if RunState.has_relic("collectors_tome") and _collectors_tome_picks < 1 \
			and not (RunState.current_node_type == "boss"):
		_collectors_tome_picks += 1
		# Remove the just-picked card from the choices and rebuild so the
		# player picks their second from the remaining options.
		_card_choices.erase(id)
		_build_ui()
		return
	if _is_elite_reward and _relic_choices.size() > 0:
		_card_choices.clear()
		_build_ui()
	else:
		_go_to_map()


func _pick_relic(id: String) -> void:
	RunState.add_relic(id)
	if AudioBank != null:
		AudioBank.play_sfx("coin")
	if id == "bottled_talisman":
		await GameTheme.bind_bottled_talisman(self)
	_go_to_map()


func _skip() -> void:
	_go_to_map()


func _skip_for_gold() -> void:
	# "I don't see a card I want — pay me instead." Costs nothing extra and the
	# gold rolls into the next shop/event.
	RunState.gain_gold(SKIP_CARD_GOLD)
	if _is_elite_reward and _relic_choices.size() > 0:
		_card_choices.clear()
		_build_ui()
	else:
		_go_to_map()


func _go_to_map() -> void:
	# Boss rewards advance the act on their way out. Combat used to do this
	# before queuing the Reward transition, but that wiped current_node_type
	# and made Reward render as a normal fight. Holding the advance until
	# now lets Reward read node_type == "boss" while still putting the player
	# on the next act's map on exit.
	if RunState.current_node_type == "boss":
		RunState.advance_act()
	GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
