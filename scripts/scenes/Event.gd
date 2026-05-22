extends Control
## Event.gd — Random choice encounters. 8 events from the design doc.
## Each presents 2 options with tradeoffs.

const MAP_SCENE = "res://scenes/map.tscn"

var _event_id: String = ""
var _event_data: Dictionary = {}


func _ready() -> void:
	if not RunState.run_active:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	GameTheme.add_atmosphere(self, "event")
	AudioBank.play_music("event")
	_pick_event()
	_build_ui()


func _pick_event() -> void:
	var available: Array = []
	for id in EVENTS:
		if not RunState.events_seen.has(id):
			available.append(id)
	if available.is_empty():
		available = EVENTS.keys()
	available.shuffle()
	_event_id = available[0]
	_event_data = EVENTS[_event_id]
	RunState.events_seen.append(_event_id)


func _build_ui() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_screen_title(_event_data.name, GameTheme.SPELL_PURPLE, 28)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40
	title.offset_bottom = 90
	add_child(title)

	var desc = GameTheme.make_label(_event_data.desc, 16, GameTheme.DESC_DIM)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	desc.offset_left = 200
	desc.offset_right = -200
	desc.offset_top = 110
	desc.offset_bottom = 190
	add_child(desc)

	var row = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_top = 220
	row.offset_bottom = 420
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 60)
	add_child(row)

	for choice in _event_data.choices:
		var btn = _make_btn(choice.label, choice.desc, Color(0.25, 0.20, 0.35), Vector2(350, 160))
		btn.pressed.connect(_resolve_choice.bind(choice))
		row.add_child(btn)

	var skip_btn = GameTheme.make_back_button("LEAVE", Vector2(140, 40), 15)
	skip_btn.position = Vector2(740, 810)
	skip_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE))
	add_child(skip_btn)


func _resolve_choice(choice: Dictionary) -> void:
	var effects = choice.get("effects", [])
	if effects.is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
		return
	var result_text := ""
	for effect in effects:
		result_text += _apply_effect(effect) + "\n"
	if result_text.strip_edges().is_empty():
		GameTheme.fade_out_then_change_scene(self, MAP_SCENE)
	else:
		_show_result(result_text)


func _apply_effect(effect: Dictionary) -> String:
	match effect.type:
		"heal_full":
			RunState.hero_hp = RunState.hero_max_hp
			return "Healed to full HP!"
		"heal":
			RunState.heal_hero(effect.value)
			return "Healed %d HP." % effect.value
		"damage":
			RunState.damage_hero(effect.value)
			return "Took %d damage." % effect.value
		"gold":
			if effect.value > 0:
				RunState.gain_gold(effect.value)
			else:
				RunState.gold += effect.value  # losses bypass ectoplasm
			if effect.value > 0:
				return "Gained %d gold." % effect.value
			else:
				return "Lost %d gold." % abs(effect.value)
		"remove_cards":
			var count = effect.value
			for i in range(count):
				if RunState.deck.size() > 1:
					var idx = randi() % RunState.deck.size()
					RunState.remove_card_at(idx)
			return "Removed %d card(s)." % count
		"add_rare":
			var rares = CardDB.cards_of_rarity("rare")
			if rares.size() > 0:
				rares.shuffle()
				RunState.add_card(rares[0])
				var data = CardDB.get_card_data(rares[0])
				return "Added %s to deck!" % data.name
			return ""
		"add_curse":
			RunState.add_card("curse")
			return "A Curse was added to your deck."
		"random_relic":
			var choices = RelicDB.roll_relic_reward("combat", RunState.relics)
			if choices.size() > 0:
				RunState.add_relic(choices[0])
				var relic = RelicDB.get_relic(choices[0])
				return "Gained relic: %s" % relic.name
			return "No relics available."
		"upgrade_random":
			var upgradeable: Array = []
			for i in range(RunState.deck.size()):
				if not RunState.is_card_upgraded(i):
					upgradeable.append(i)
			if upgradeable.size() > 0:
				var idx = upgradeable[randi() % upgradeable.size()]
				RunState.upgrade_card(idx, "sharpen")
				return "Upgraded a card!"
			return "No cards to upgrade."
		"copy_card":
			if RunState.deck.size() > 0:
				var idx = randi() % RunState.deck.size()
				RunState.add_card(RunState.deck[idx])
				return "Copied a card from your deck."
			return ""
		"remove_choice":
			_start_remove_mode()
			return ""
		"remove_choice_multi":
			_start_multi_remove_mode(effect.value)
			return ""
		"gamble":
			if RunState.gold >= 30:
				RunState.gold -= 30
				if randi() % 2 == 0:
					RunState.gain_gold(90)
					return "Won! +90 gold!"
				else:
					return "Lost 30 gold."
			return "Not enough gold."
		"debuff_starters":
			for i in range(RunState.deck.size()):
				var id = RunState.deck[i]
				if id in ["troll", "sprite", "naga"]:
					if not RunState.is_card_upgraded(i):
						RunState.upgrade_card(i, "fortify_neg")
			return "Starter creatures lose 1 HP permanently."
		"butcher_buff":
			_start_butcher_mode()
			return ""
	return ""


func _show_result(text: String) -> void:
	if text.is_empty():
		return
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var result_label = GameTheme.make_label(text.strip_edges(), 20, GameTheme.IVORY)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.position = Vector2(400, 300)
	result_label.size = Vector2(800, 200)
	add_child(result_label)

	var continue_btn = GameTheme.make_themed_button("Continue",
		Color(0.20, 0.35, 0.20), Vector2(140, 40), 16)
	continue_btn.position = Vector2(730, 550)
	continue_btn.pressed.connect(func(): GameTheme.fade_out_then_change_scene(self, MAP_SCENE))
	add_child(continue_btn)


func _start_remove_mode() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_label("Choose a card to remove", 22, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(150, 80)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		var text: String
		if data.get("type", "creature") == "spell":
			text = "%s\n%dm" % [data.name, data.cost]
		else:
			text = "%s\n%d/%d" % [data.name, data.atk, data.hp]
		var btn = _make_btn(text, "", Color(0.25, 0.2, 0.35), Vector2(130, 70))
		btn.pressed.connect(func():
			RunState.remove_card_at(i)
			_show_result("Card removed.")
		)
		grid.add_child(btn)


func _start_multi_remove_mode(count: int) -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var _remaining = count
	var title = GameTheme.make_label("Choose %d card(s) to remove" % _remaining,
		22, GameTheme.BLOOD_RED)
	title.name = "RemoveTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(500, 30)
	title.size = Vector2(600, 40)
	add_child(title)

	var grid = GridContainer.new()
	grid.name = "RemoveGrid"
	grid.columns = 6
	grid.position = Vector2(150, 80)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	for i in range(RunState.deck.size()):
		var data = RunState.get_upgraded_card_data(i)
		var text: String
		if data.get("type", "creature") == "spell":
			text = "%s\n%dm" % [data.name, data.cost]
		else:
			text = "%s\n%d/%d" % [data.name, data.atk, data.hp]
		var btn = _make_btn(text, "", Color(0.25, 0.2, 0.35), Vector2(130, 70))
		btn.pressed.connect(_on_multi_remove_pick.bind(i, count))
		grid.add_child(btn)


var _multi_remove_remaining: int = 0
var _multi_remove_removed: int = 0

func _on_multi_remove_pick(deck_index: int, total: int) -> void:
	if _multi_remove_remaining <= 0:
		_multi_remove_remaining = total
		_multi_remove_removed = 0
	RunState.remove_card_at(deck_index)
	_multi_remove_removed += 1
	_multi_remove_remaining -= 1
	if _multi_remove_remaining <= 0 or RunState.deck.size() <= 1:
		_show_result("Removed %d card(s)." % _multi_remove_removed)
	else:
		_start_multi_remove_mode(_multi_remove_remaining)


func _start_butcher_mode() -> void:
	for child in get_children():
		if child.name != "Background" and child.name != "Atmosphere":
			child.queue_free()

	var title = GameTheme.make_label("Choose a creature for the Butcher (+2 ATK, +Wither 1)",
		20, GameTheme.KEYWORD_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(300, 30)
	title.size = Vector2(1000, 40)
	add_child(title)

	var grid = GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(150, 80)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	for i in range(RunState.deck.size()):
		var data = CardDB.get_card_data(RunState.deck[i])
		if data.get("type", "creature") != "creature":
			continue
		var text = "%s\n%d/%d" % [data.name, data.atk, data.hp]
		var btn = _make_btn(text, "", Color(0.35, 0.20, 0.15), Vector2(130, 70))
		btn.pressed.connect(func():
			RunState.upgrade_card(i, "sharpen")
			_show_result("The Butcher returns %s with +2 ATK and Wither 1." % data.name)
		)
		grid.add_child(btn)


func _make_btn(text: String, tooltip: String, color: Color, min_size: Vector2) -> Button:
	return GameTheme.make_themed_button(text, color, min_size, 13, tooltip)


# ── Event definitions ──

const EVENTS: Dictionary = {
	"blacksmith_offer": {
		"name": "The Blacksmith's Offer",
		"desc": "A weathered blacksmith offers to improve your equipment... for a price.",
		"choices": [
			{
				"label": "Accept the Offer\n\nUpgrade a card for free.\nThe Blacksmith keeps one\nof your other cards.",
				"desc": "Free upgrade, lose a card",
				"effects": [
					{"type": "upgrade_random"},
					{"type": "remove_cards", "value": 1},
				],
			},
			{
				"label": "Decline\n\nLeave with nothing.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"blood_fountain": {
		"name": "The Blood Fountain",
		"desc": "Crimson waters bubble from an ancient fountain. You feel its healing power... and its cost.",
		"choices": [
			{
				"label": "Drink Deep\n\nHeal to full HP.\nStarter creatures lose\n1 HP permanently.",
				"desc": "Full heal, weaker starters",
				"effects": [
					{"type": "heal_full"},
					{"type": "debuff_starters"},
				],
			},
			{
				"label": "Walk Away\n\nLeave with nothing.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"collector_event": {
		"name": "The Collector",
		"desc": "A hooded figure offers a rare treasure... but demands something in return.",
		"choices": [
			{
				"label": "Take the Rare Card\n\nGain a random rare card.\nA Curse is added to\nyour deck.",
				"desc": "Rare card + curse",
				"effects": [
					{"type": "add_rare"},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Refuse\n\nLeave with nothing.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"dark_altar": {
		"name": "Dark Altar",
		"desc": "A sinister altar pulses with shadow. It promises purification... through pain.",
		"choices": [
			{
				"label": "Make the Sacrifice\n\nChoose 3 cards to remove.\nTake 3 damage.",
				"desc": "Choose 3 cards to remove, take 3 dmg",
				"effects": [
					{"type": "remove_choice_multi", "value": 3},
					{"type": "damage", "value": 3},
				],
			},
			{
				"label": "Turn Away\n\nLeave with nothing.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"gambler": {
		"name": "The Gambler",
		"desc": "A grinning figure shuffles a deck of marked cards. \"Care for a wager?\"",
		"choices": [
			{
				"label": "Bet 30 Gold\n\nHeads: win 90 gold.\nTails: lose 30 gold.",
				"desc": "50/50 gamble",
				"effects": [
					{"type": "gamble"},
				],
			},
			{
				"label": "No Thanks\n\nKeep your gold.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"hermit": {
		"name": "The Hermit",
		"desc": "An old sage sits by the roadside, offering wisdom in exchange for company.",
		"choices": [
			{
				"label": "Copy a Card\n\nGain a copy of a\nrandom card in your deck.",
				"desc": "Duplicate a card",
				"effects": [
					{"type": "copy_card"},
				],
			},
			{
				"label": "Remove a Card\n\nRemove any card\nfor free.",
				"desc": "Free card removal",
				"effects": [
					{"type": "remove_choice"},
				],
			},
		],
	},

	"butcher": {
		"name": "The Butcher",
		"desc": "A burly figure sharpens a cleaver. \"Give me a creature. I'll make it stronger... sort of.\"",
		"choices": [
			{
				"label": "Give a Creature\n\nIt returns with +2 ATK\nand Wither 1.",
				"desc": "+2 ATK but gains Wither",
				"effects": [
					{"type": "butcher_buff"},
				],
			},
			{
				"label": "Keep Walking\n\nLeave with nothing.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"mysterious_shrine": {
		"name": "Mysterious Shrine",
		"desc": "A glowing shrine hums with ancient power. It offers a trade: a card for a relic.",
		"choices": [
			{
				"label": "Make the Trade\n\nLose a random card.\nGain a random relic.",
				"desc": "Lose card, gain relic",
				"effects": [
					{"type": "remove_cards", "value": 1},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Leave It\n\nDon't risk it.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"thrice_blessed_spring": {
		"name": "The Thrice-Blessed Spring",
		"desc": "A spring boils with old miracles. Each sip heals deeper — and rots something deeper still.",
		"choices": [
			{
				"label": "One Sip\n\nHeal 6. A starter weakens.",
				"desc": "+6 HP, starters -1 HP",
				"effects": [
					{"type": "heal", "value": 6},
					{"type": "debuff_starters"},
				],
			},
			{
				"label": "Two Sips\n\nHeal 14. Lose 30 gold to the dregs.",
				"desc": "+14 HP, -30 gold",
				"effects": [
					{"type": "heal", "value": 14},
					{"type": "gold", "value": -30},
				],
			},
			{
				"label": "Drink Deep\n\nHeal fully. Gain a curse.",
				"desc": "Full heal, +curse",
				"effects": [
					{"type": "heal_full"},
					{"type": "add_curse"},
				],
			},
		],
	},

	"pawnbrokers_window": {
		"name": "The Pawnbroker's Window",
		"desc": "Behind smoked glass, the pawnbroker fans her wares. She does not sell. She only trades.",
		"choices": [
			{
				"label": "Trade Steel\n\nLose 6 HP.\nPick a card to remove.",
				"desc": "-6 HP, remove 1 chosen",
				"effects": [
					{"type": "damage", "value": 6},
					{"type": "remove_choice"},
				],
			},
			{
				"label": "Trade Coin\n\nLose 80 gold.\nUpgrade a random card.",
				"desc": "-80 gold, upgrade random",
				"effects": [
					{"type": "gold", "value": -80},
					{"type": "upgrade_random"},
				],
			},
			{
				"label": "Trade Future\n\nGain a curse.\nTake a rare card.",
				"desc": "+curse, +rare card",
				"effects": [
					{"type": "add_curse"},
					{"type": "add_rare"},
				],
			},
		],
	},

	"fork_in_the_long_road": {
		"name": "The Fork in the Long Road",
		"desc": "Two paths split the moor. One smells of woodsmoke. The other, of iron.",
		"choices": [
			{
				"label": "The Smoke Road\n\nHeal 10.\nLose 40 gold to the tollman.",
				"desc": "+10 HP, -40 gold",
				"effects": [
					{"type": "heal", "value": 10},
					{"type": "gold", "value": -40},
				],
			},
			{
				"label": "The Iron Road\n\nTake 8 damage.\nGain 70 gold from the dead.",
				"desc": "-8 HP, +70 gold",
				"effects": [
					{"type": "damage", "value": 8},
					{"type": "gold", "value": 70},
				],
			},
		],
	},

	"beekeeper": {
		"name": "The Beekeeper",
		"desc": "She wears no veil. The bees have made a hood of her face, and they move when she speaks. 'I have honey,' she says. 'And other things. The hive remembers everything that has ever stung.'",
		"choices": [
			{
				"label": "Take the honey jar\n\nIt is warm.\nIt is moving.",
				"desc": "+10 HP, +curse",
				"effects": [
					{"type": "heal", "value": 10},
					{"type": "add_curse"},
				],
			},
			{
				"label": "Let them sting you\n\nThe hive shudders.\nSomething is given back.",
				"desc": "-4 HP, upgrade a card",
				"effects": [
					{"type": "damage", "value": 4},
					{"type": "upgrade_random"},
				],
			},
			{
				"label": "Ask what the hive remembers\n\nShe smiles.\nThe bees do not.",
				"desc": "Remove 1 chosen card",
				"effects": [
					{"type": "remove_choice"},
				],
			},
		],
	},

	"burning_cradle": {
		"name": "The Burning Cradle",
		"desc": "A wicker cradle sits in the middle of the path, alight. Nothing is inside it. Nothing has ever been inside it. It rocks anyway.",
		"choices": [
			{
				"label": "Kneel and sing to it\n\nThe flames lean toward your mouth\nlike they know the words.",
				"desc": "-3 HP, heal to full",
				"effects": [
					{"type": "damage", "value": 3},
					{"type": "heal_full"},
				],
			},
			{
				"label": "Put it out with your cloak\n\nThe cradle goes cold.\nSo does something in your chest.",
				"desc": "-40 gold, +random relic",
				"effects": [
					{"type": "gold", "value": -40},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Walk past. It is not yours.\n\nYou hear it rocking for an hour after.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"woodcutter": {
		"name": "The Woodcutter",
		"desc": "He has been chopping the same tree for thirty years. The tree has not gotten smaller. He has. 'Swing for me,' he says, 'and I'll teach you the trick of it.'",
		"choices": [
			{
				"label": "Take the axe\n\nIt is heavier than it looks.\nMost things are.",
				"desc": "Upgrade a card, -2 HP",
				"effects": [
					{"type": "upgrade_random"},
					{"type": "damage", "value": 2},
				],
			},
			{
				"label": "Sit and watch him work\n\nHe talks the whole time.\nYou learn nothing useful.",
				"desc": "+35 gold",
				"effects": [
					{"type": "gold", "value": 35},
				],
			},
			{
				"label": "Tell him the tree is winning\n\nHe laughs until he cries.\nThen he just cries.",
				"desc": "No effect",
				"effects": [],
			},
		],
	},

	"char_widow": {
		"name": "The Char-Widow's Pyre",
		"desc": "A woman feeds her wedding dress to a fire one inch at a time. She has been doing this since the meadow began to burn. 'Throw something in,' she says without looking up. 'It helps.'",
		"choices": [
			{
				"label": "Throw in a fistful of gold\n\nIt melts.\nShe sighs like a kettle.",
				"desc": "-50 gold, +8 HP",
				"effects": [
					{"type": "gold", "value": -50},
					{"type": "heal", "value": 8},
				],
			},
			{
				"label": "Throw in two of your cards\n\nThey curl, blacken, are gone.\nYou feel lighter.",
				"desc": "Remove 2 chosen cards",
				"effects": [
					{"type": "remove_choice_multi", "value": 2},
				],
			},
			{
				"label": "Throw in your own sleeve\n\nShe finally looks up.\nShe knows you now.",
				"desc": "-5 HP, +random relic",
				"effects": [
					{"type": "damage", "value": 5},
					{"type": "random_relic"},
				],
			},
		],
	},

	"gravesong_choir": {
		"name": "The Gravesong Choir",
		"desc": "Four hooded singers stand around an open grave, humming a tune you almost recognize. One pauses, lifts a finger to her lips, and beckons toward the empty pit.",
		"choices": [
			{
				"label": "Lay 2 cards in the grave\n\nThe choir sings them down.\nGain a rare card and 30 gold.",
				"desc": "Remove 2 chosen, +rare, +30g",
				"effects": [
					{"type": "remove_choice_multi", "value": 2},
					{"type": "add_rare"},
					{"type": "gold", "value": 30},
				],
			},
			{
				"label": "Sing along\n\nThe melody upgrades a card\nin your deck.",
				"desc": "Upgrade a random card",
				"effects": [
					{"type": "upgrade_random"},
				],
			},
			{
				"label": "Cover your ears and leave\n\nYou snatch a coin purse from\nthe offering plate as you go.",
				"desc": "+50 gold",
				"effects": [
					{"type": "gold", "value": 50},
				],
			},
		],
	},

	"glass_familiar": {
		"name": "The Glass Familiar",
		"desc": "A small cat of spun glass watches you from a stone pedestal. It tilts its head. 'Make two of me,' it says, 'or one of anything else.'",
		"choices": [
			{
				"label": "Pay 30 gold\n\nDuplicate a card in\nyour deck twice.",
				"desc": "-30 gold, copy a card x2",
				"effects": [
					{"type": "gold", "value": -30},
					{"type": "copy_card"},
					{"type": "copy_card"},
				],
			},
			{
				"label": "Trade a memory\n\nLose 5 HP.\nGain a random relic.",
				"desc": "-5 HP, +random relic",
				"effects": [
					{"type": "damage", "value": 5},
					{"type": "random_relic"},
				],
			},
			{
				"label": "Pet the cat and walk on\n\nIt purrs, like glass might.",
				"desc": "+5 HP",
				"effects": [
					{"type": "heal", "value": 5},
				],
			},
		],
	},

	"spellwrights_pact": {
		"name": "The Spellwright's Pact",
		"desc": "An old scribe is hunched over a smoldering page. Ink runs upward off the parchment into the air. 'I'll teach you a true word,' he says, 'but the saying of it costs flesh.'",
		"choices": [
			{
				"label": "Sign in blood\n\nLose 8 HP. Gain a rare card\nand upgrade a card.",
				"desc": "-8 HP, +rare, upgrade random",
				"effects": [
					{"type": "damage", "value": 8},
					{"type": "add_rare"},
					{"type": "upgrade_random"},
				],
			},
			{
				"label": "Pay for the page\n\nThe scribe sells you a clean\ncopy for 50 gold.",
				"desc": "-50 gold, +rare card",
				"effects": [
					{"type": "gold", "value": -50},
					{"type": "add_rare"},
				],
			},
			{
				"label": "Refuse and rest\n\nThe scribe pours you tea.",
				"desc": "+10 HP",
				"effects": [
					{"type": "heal", "value": 10},
				],
			},
		],
	},
}
