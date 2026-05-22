extends Node
## EncounterDB.gd — Premade fight lineups from the master design document.
## Each encounter has an ordered creature deck, reinforcement, HP, and optional passive.

var _enc_counter: int = 0


func get_encounter(id: String) -> Dictionary:
	if ENCOUNTERS.has(id):
		return ENCOUNTERS[id]
	push_warning("EncounterDB: unknown encounter '%s'" % id)
	return {}


func get_ids_for(act: int, type: String) -> Array:
	var result: Array = []
	for id in ENCOUNTERS:
		var enc = ENCOUNTERS[id]
		if enc.act == act and enc.type == type:
			result.append(id)
	return result


func make_card_data(creature: Dictionary) -> Dictionary:
	_enc_counter += 1
	var safe_name = creature.name.to_lower().replace(" ", "_").replace("'", "")
	var data: Dictionary = {
		"id": "enc_%s_%d" % [safe_name, _enc_counter],
		"name": creature.name,
		"type": "creature",
		"cost": 0,
		"atk": creature.atk,
		"hp": creature.hp,
		"rarity": "enemy",
		"keywords": creature.get("kw", []).duplicate(),
		"desc": "",
	}
	for key in ["on_enter", "on_death", "floop", "adj_buff"]:
		if creature.has(key):
			data[key] = creature[key].duplicate(true)
	if creature.has("wither"):
		data["wither"] = creature.wither
	if creature.has("intents"):
		data["intents"] = creature.intents.duplicate()
	if creature.has("ability"):
		data["ability"] = creature.ability.duplicate(true)
	return data


func build_enemy_deck(encounter_id: String) -> Array[Dictionary]:
	var enc = get_encounter(encounter_id)
	if enc.is_empty():
		return []
	var deck: Array[Dictionary] = []
	for creature in enc.deck:
		deck.append(make_card_data(creature))
	return deck


func get_reinforcement(encounter_id: String) -> Dictionary:
	var enc = get_encounter(encounter_id)
	if enc.is_empty():
		return {}
	return make_card_data(enc.reinforcement)


func get_boss_phases(encounter_id: String) -> Array:
	if BOSS_PHASES.has(encounter_id):
		return BOSS_PHASES[encounter_id]
	return []


func get_reactive_passive(encounter_id: String) -> Dictionary:
	if REACTIVE_PASSIVES.has(encounter_id):
		return REACTIVE_PASSIVES[encounter_id]
	return {}


# Boss phase definitions: each phase has threshold, passive_id, passive_desc,
# and an optional transition effect.
const BOSS_PHASES: Dictionary = {
	"iron_warden": [
		{"threshold": 13, "passive_id": "iron_warden_burn", "passive_desc": "2 face damage to player at end of each round."},
		{"threshold": 0, "passive_id": "iron_warden_siege", "passive_desc": "3 face damage + all enemies gain Armored.",
			"transition_msg": "The Warden enters Siege Mode!",
			"transition_effect": {"type": "summon", "name": "Iron Guard", "atk": 2, "hp": 5, "kw": ["armored"]}},
	],
	"dragon_lord": [
		{"threshold": 12, "passive_id": "dragon_lord_piercing", "passive_desc": "All enemy creatures have Piercing."},
		{"threshold": 0, "passive_id": "dragon_lord_phase2", "passive_desc": "Piercing + all enemies +1 ATK.",
			"transition_msg": "The Dragon Lord roars!",
			"transition_effect": {"type": "heal_all_enemies", "value": 2}},
	],
	"collector": [
		{"threshold": 17, "passive_id": "collector_heal", "passive_desc": "Player creature played: Collector heals 1 HP."},
		{"threshold": 0, "passive_id": "collector_phase2", "passive_desc": "Player creature: heal 2 + random enemy +1 ATK.",
			"transition_msg": "The Collector unveils his gallery!",
			"transition_effect": {"type": "summon_multiple", "name": "Trinket", "atk": 2, "hp": 3, "count": 2}},
	],
	"hollow_king": [
		{"threshold": 16, "passive_id": "hollow_king_snipe", "passive_desc": "Highest-ATK player creature takes 3 damage each round."},
		{"threshold": 0, "passive_id": "hollow_king_phase2", "passive_desc": "Two highest take 3 dmg + Curse added to deck.",
			"transition_msg": "The Hollow King's void spreads!",
			"transition_effect": {"type": "debuff_all_player_atk", "value": 1}},
	],
	"the_devil": [
		{"threshold": 20, "passive_id": "devil_cycle", "passive_desc": "Cycle: R1 2 face, R2 heal 1/enemy, R3 3 to highest-ATK."},
		{"threshold": 10, "passive_id": "devil_phase2", "passive_desc": "Cycle doubled + all enemies +1 ATK.",
			"transition_msg": "THE DEVIL REVEALS HIS TRUE FORM!",
			"transition_effect": {"type": "summon", "name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"]}},
		{"threshold": 0, "passive_id": "devil_phase3", "passive_desc": "DESPERATION: 3 face + summon + all enemies +1 ATK/round.",
			"transition_msg": "THE DEVIL UNLEASHES HIS FULL POWER!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"the_crone": [
		{"threshold": 24, "passive_id": "crone_drip", "passive_desc": "End of round: 1 Curse to discard."},
		{"threshold": 12, "passive_id": "crone_lash", "passive_desc": "Drip + 1 face damage per Curse in your deck.",
			"transition_msg": "The Crone's voice cracks the air!",
			"transition_effect": {"type": "summon", "name": "Wraith", "atk": 2, "hp": 3, "kw": ["swift"]}},
		{"threshold": 0, "passive_id": "crone_doom", "passive_desc": "2 Curses + 1 face per Curse + Wraith summon each round.",
			"transition_msg": "THE CRONE BURIES YOU IN HER GRAVE-DIRT!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 1}},
	],
	"the_black_tide": [
		{"threshold": 26, "passive_id": "tide_swell", "passive_desc": "End of round: summon 2/3 Deepling if board <4."},
		{"threshold": 13, "passive_id": "tide_surge", "passive_desc": "Swell + all enemies +1 ATK each round.",
			"transition_msg": "The tide rises higher!",
			"transition_effect": {"type": "summon", "name": "Anglerfish", "atk": 4, "hp": 3}},
		{"threshold": 0, "passive_id": "tide_drown", "passive_desc": "Surge + 3 damage to your weakest creature each round.",
			"transition_msg": "THE BLACK TIDE DRAGS YOU UNDER!",
			"transition_effect": {"type": "buff_all_enemies_atk", "value": 2}},
	],
}


# Reactive passives: trigger on specific player actions.
# "trigger": what player action triggers it
# "effect": what happens when triggered
const REACTIVE_PASSIVES: Dictionary = {
	"orc_warband": {"trigger": "ON_PLAYER_SPELL", "effect": "buff_chieftain_atk",
		"desc": "Chieftain gains +1 ATK when player plays a spell."},
	"necromancer_tower": {"trigger": "ON_CREATURE_DEATH", "effect": "double_on_death",
		"desc": "Enemy on-death effects trigger twice."},
	"cultist_enclave": {"trigger": "ON_PLAYER_SACRIFICE", "effect": "face_damage",
		"value": 2, "desc": "Deal 2 face damage when player sacrifices."},
	"haunted_crypt": {"trigger": "ON_PLAYER_FLOOP", "effect": "damage_flooper",
		"value": 1, "desc": "Deal 1 to the flooping creature."},
	"demon_vanguard": {"trigger": "ON_PLAYER_FLOOP", "effect": "damage_flooper",
		"value": 1, "desc": "Deal 1 to the flooping creature."},
	"puppeteer": {"trigger": "ON_PLAYER_SUMMON", "effect": "summon_puppet",
		"atk": 2, "hp": 2, "desc": "Summon a 2/2 Puppet when player summons."},
	"mirror_temple": {"trigger": "ON_CREATURE_DEATH", "effect": "heal_all_enemies",
		"value": 1, "desc": "All surviving enemies heal 1 on any death."},
	"executioners_block": {"trigger": "ON_PLAYER_DRAW", "effect": "face_damage_per_draw",
		"desc": "1 face damage per extra card drawn beyond 5."},
	"archlich": {"trigger": "ON_PLAYER_SPELL", "effect": "summon_shard",
		"atk": 1, "hp": 1, "desc": "Summon 1/1 Bone Shard when player plays a spell."},
	"void_walker": {"trigger": "ON_PLAYER_DRAW", "effect": "exile_card",
		"desc": "Exile 1 additional card from deck on extra draw."},
}


# =====================================================================
#  ENCOUNTER DATA
# =====================================================================

const ENCOUNTERS: Dictionary = {

	# =================== ACT 1 — COMBAT ===========================

	"goblin_scouts": {
		"name": "Goblin Scouts", "act": 1, "type": "combat", "hp": 12,
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Goblin", "atk": 2, "hp": 2},
			{"name": "Goblin", "atk": 2, "hp": 2},
			{"name": "Goblin", "atk": 2, "hp": 2,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Goblin", "atk": 2, "hp": 2},
			{"name": "Goblin Scout", "atk": 2, "hp": 3,
				"intents": ["ATK", "RALLY", "ATK", "ATK"]},
			{"name": "Goblin Scout", "atk": 2, "hp": 3},
		],
		"reinforcement": {"name": "Runt", "atk": 1, "hp": 1},
	},

	"wolf_pack": {
		"name": "Wolf Pack", "act": 1, "type": "combat", "hp": 14,
		"passive_id": "wolf_pack_revenge",
		"passive_desc": "When an enemy creature dies, adjacent enemies gain +1 ATK this turn.",
		"deck": [
			{"name": "Wolf", "atk": 2, "hp": 3},
			{"name": "Wolf", "atk": 2, "hp": 3},
			{"name": "Wolf", "atk": 2, "hp": 3},
			{"name": "Dire Wolf", "atk": 3, "hp": 3},
			{"name": "Dire Wolf", "atk": 3, "hp": 3},
			{"name": "Alpha", "atk": 3, "hp": 4,
				"intents": ["ATK", "RALLY", "ATK", "ATK"]},
		],
		"reinforcement": {"name": "Pup", "atk": 1, "hp": 1},
	},

	"bandit_camp": {
		"name": "Bandit Camp", "act": 1, "type": "combat", "hp": 14,
		"passive_id": "bandit_mana_steal",
		"passive_desc": "First enemy placed each turn steals 1 player mana next turn.",
		"deck": [
			{"name": "Bandit", "atk": 2, "hp": 3},
			{"name": "Bandit", "atk": 2, "hp": 3},
			{"name": "Bandit", "atk": 2, "hp": 3},
			{"name": "Archer", "atk": 2, "hp": 3,
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Archer", "atk": 2, "hp": 3,
				"on_enter": {"type": "damage_random_player", "value": 1}},
			{"name": "Captain", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
		],
		"reinforcement": {"name": "Thug", "atk": 1, "hp": 2},
	},

	"mushroom_grove": {
		"name": "Mushroom Grove", "act": 1, "type": "combat", "hp": 10,
		"passive_id": "mushroom_heal",
		"passive_desc": "Heal all enemy creatures 1 at end of round.",
		"deck": [
			{"name": "Sprout", "atk": 1, "hp": 4},
			{"name": "Sprout", "atk": 1, "hp": 4},
			{"name": "Sprout", "atk": 1, "hp": 4},
			{"name": "Spore Beast", "atk": 2, "hp": 4},
			{"name": "Spore Beast", "atk": 2, "hp": 4},
			{"name": "Mycelium", "atk": 2, "hp": 5,
				"on_death": {"type": "damage_all_enemies", "value": 1},
				"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
		],
		"reinforcement": {"name": "Spore", "atk": 1, "hp": 2},
	},

	"stone_sentinels": {
		"name": "Stone Sentinels", "act": 1, "type": "combat", "hp": 12,
		"passive_id": "",
		"passive_desc": "",
		"deck": [
			{"name": "Golem", "atk": 2, "hp": 3},
			{"name": "Golem", "atk": 2, "hp": 3},
			{"name": "Golem", "atk": 2, "hp": 4, "kw": ["armored"]},
			{"name": "Golem", "atk": 2, "hp": 4},
			{"name": "Rock Hurler", "atk": 3, "hp": 3,
				"on_enter": {"type": "damage_random_player", "value": 1},
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Granite Guard", "atk": 2, "hp": 4, "kw": ["armored"]},
		],
		"reinforcement": {"name": "Fragment", "atk": 1, "hp": 2},
	},

	"harpy_nest": {
		"name": "Harpy Nest", "act": 1, "type": "combat", "hp": 13,
		"passive_id": "harpy_swift_face",
		"passive_desc": "Enemy Swift creatures deal +1 face damage through empty lanes.",
		"deck": [
			{"name": "Harpy", "atk": 3, "hp": 2},
			{"name": "Harpy", "atk": 3, "hp": 2},
			{"name": "Harpy", "atk": 3, "hp": 2},
			{"name": "Wind Harpy", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Wind Harpy", "atk": 3, "hp": 2, "kw": ["swift"]},
			{"name": "Matron", "atk": 2, "hp": 4,
				"on_death": {"type": "damage_opposing", "value": 2},
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
		],
		"reinforcement": {"name": "Chick", "atk": 1, "hp": 1},
	},

	"boar_herd": {
		# Vanilla Act 1 brawl — beefy front line, tusker's death rattle teaches lane-trade order.
		"name": "Boar Herd", "act": 1, "type": "combat", "hp": 13,
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Boar", "atk": 3, "hp": 2,
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Boar", "atk": 3, "hp": 2,
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Boar", "atk": 3, "hp": 2,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Sow", "atk": 2, "hp": 4,
				"intents": ["ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Tusker", "atk": 3, "hp": 4,
				"on_death": {"type": "damage_opposing_lane", "value": 2},
				"intents": ["ATK", "ENRAGE", "ATK", "ATK"]},
		],
		"reinforcement": {"name": "Piglet", "atk": 2, "hp": 2},
	},

	"scarecrow_field": {
		# Thorns + Wither tutorial — sticky chaff that punishes greedy attacks; mushroom_heal keeps the witch ticking.
		"name": "Scarecrow Field", "act": 1, "type": "combat", "hp": 11,
		"passive_id": "mushroom_heal",
		"passive_desc": "Heal all enemy creatures 1 at end of round.",
		"deck": [
			{"name": "Scarecrow", "atk": 1, "hp": 4, "kw": ["thorns"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Scarecrow", "atk": 1, "hp": 4, "kw": ["thorns"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Straw Man", "atk": 2, "hp": 3, "wither": 1,
				"intents": ["ATK", "ATK", "ATK", "ATK"]},
			{"name": "Straw Man", "atk": 2, "hp": 3, "wither": 1,
				"intents": ["ATK", "ATK", "ATK", "ATK"]},
			{"name": "Crow Witch", "atk": 2, "hp": 4,
				"on_enter": {"type": "damage_random_player", "value": 1},
				"intents": ["ATK", "ABILITY", "ATK", "ATK"],
				"ability": {"type": "heal_all", "value": 1}},
		],
		"reinforcement": {"name": "Crow", "atk": 2, "hp": 1},
	},

	# =================== ACT 1 — ELITE ============================

	"orc_warband": {
		"name": "Orc Warband", "act": 1, "type": "elite", "hp": 20,
		"passive_id": "orc_random_buff",
		"passive_desc": "Each round, a random enemy creature gains +1 ATK permanently.",
		"deck": [
			{"name": "Warrior", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Warrior", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Warrior", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Brute", "atk": 3, "hp": 4,
				"intents": ["ATK", "ENRAGE", "ATK", "ATK"]},
			{"name": "Brute", "atk": 3, "hp": 4,
				"intents": ["ATK", "ENRAGE", "ATK", "ATK"]},
			{"name": "Drummer", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0},
				"intents": ["RALLY", "ATK", "RALLY", "ATK"]},
			{"name": "Chieftain", "atk": 4, "hp": 4,
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Grunt", "atk": 2, "hp": 2},
	},

	"necromancer_tower": {
		"name": "Necromancer's Tower", "act": 1, "type": "elite", "hp": 22,
		"passive_id": "necro_death_summon",
		"passive_desc": "When an enemy creature dies, summon a 1/2 Skeleton in a random empty lane.",
		"deck": [
			{"name": "Skeleton", "atk": 2, "hp": 3},
			{"name": "Skeleton", "atk": 2, "hp": 3},
			{"name": "Skeleton", "atk": 2, "hp": 3},
			{"name": "Bone Knight", "atk": 3, "hp": 4,
				"on_death": {"type": "summon", "atk": 2, "hp": 2},
				"intents": ["ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Dark Acolyte", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0},
				"intents": ["ATK", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "resurrect"}},
			{"name": "Lich", "atk": 3, "hp": 5, "kw": ["regenerate"],
				"intents": ["ATK", "HEAL", "ATK", "ATK"]},
		],
		"reinforcement": {"name": "Risen Bones", "atk": 1, "hp": 2},
	},

	# =================== ACT 1 — BOSS =============================

	"iron_warden": {
		"name": "The Iron Warden", "act": 1, "type": "boss", "hp": 25,
		"passive_id": "iron_warden_burn",
		"passive_desc": "2 face damage to player at end of each round.",
		"deck": [
			{"name": "Iron Sentinel", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Iron Sentinel", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Iron Sentinel", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Iron Guard", "atk": 2, "hp": 5, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Siege Engine", "atk": 3, "hp": 3,
				"on_enter": {"type": "damage_all_enemies", "value": 1},
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Warden's Champion", "atk": 4, "hp": 4, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "CHARGE", "ATK"],
				"ability": {"type": "mark"}},
			{"name": "Iron Vanguard", "atk": 4, "hp": 5, "kw": ["last_stand"],
				"intents": ["ATK", "ATK", "ENRAGE", "ATK", "ATK"]},
		],
		"reinforcement": {"name": "Iron Recruit", "atk": 2, "hp": 3},
	},

	"dragon_lord": {
		"name": "Dragon Lord", "act": 1, "type": "boss", "hp": 23,
		"passive_id": "dragon_lord_piercing",
		"passive_desc": "All enemy creatures have Piercing.",
		"deck": [
			{"name": "Drake", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Drake", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Drake", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Wyrm", "atk": 3, "hp": 4, "kw": ["regenerate"],
				"intents": ["ATK", "HEAL", "ATK", "ATK"]},
			{"name": "Wyrm", "atk": 3, "hp": 4, "kw": ["regenerate"],
				"intents": ["ATK", "HEAL", "ATK", "ATK"]},
			{"name": "Elder Drake", "atk": 4, "hp": 5,
				"on_enter": {"type": "damage_all_enemies", "value": 2},
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK", "CHARGE"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Whelp", "atk": 2, "hp": 2},
	},

	# =================== ACT 2 — COMBAT ===========================

	"cultist_enclave": {
		"name": "Cultist Enclave", "act": 2, "type": "combat", "hp": 18,
		"passive_id": "cultist_buff",
		"passive_desc": "Each round, a random enemy gains +1/+1.",
		"deck": [
			{"name": "Cultist", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "ENRAGE", "ATK"]},
			{"name": "Cultist", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "ENRAGE", "ATK"]},
			{"name": "Cultist", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "ENRAGE", "ATK"]},
			{"name": "Dark Priest", "atk": 2, "hp": 4, "kw": ["regenerate"],
				"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
			{"name": "Dark Priest", "atk": 2, "hp": 4, "kw": ["regenerate"],
				"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
			{"name": "Zealot", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_face", "value": 2},
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Fanatic", "atk": 4, "hp": 4,
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK"],
				"ability": {"type": "curse"}},
		],
		"reinforcement": {"name": "Initiate", "atk": 2, "hp": 2},
	},

	"swamp_horror": {
		"name": "Swamp Horror", "act": 2, "type": "combat", "hp": 18,
		"passive_id": "swamp_thorns",
		"passive_desc": "All enemy creatures have Thorns.",
		"deck": [
			{"name": "Bog Lurker", "atk": 2, "hp": 5,
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Bog Lurker", "atk": 2, "hp": 5,
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Bog Lurker", "atk": 2, "hp": 5,
				"intents": ["ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Mire Beast", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "CHARGE"]},
			{"name": "Mire Beast", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "CHARGE"]},
			{"name": "Swamp Hag", "atk": 2, "hp": 3,
				"floop": {"type": "heal_all_friendly", "value": 2},
				"intents": ["ABILITY", "ATK", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "heal_all", "value": 2}},
			{"name": "Hydra Spawn", "atk": 3, "hp": 3, "kw": ["regenerate"],
				"intents": ["ATK", "ATK", "HEAL", "ATK"]},
		],
		"reinforcement": {"name": "Leech", "atk": 1, "hp": 3},
	},

	"mercenary_company": {
		"name": "Mercenary Company", "act": 2, "type": "combat", "hp": 17,
		"passive_id": "merc_piercing",
		"passive_desc": "Enemy creatures with 4+ ATK have Piercing.",
		"deck": [
			{"name": "Sellsword", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Sellsword", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Captain", "atk": 4, "hp": 4,
				"intents": ["ATK", "RALLY", "ATK", "ATK", "CHARGE"]},
			{"name": "Captain", "atk": 4, "hp": 4,
				"intents": ["ATK", "RALLY", "ATK", "ATK", "CHARGE"]},
			{"name": "Sharpshooter", "atk": 3, "hp": 2, "kw": ["ranged"]},
			{"name": "Enforcer", "atk": 4, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Brute", "atk": 5, "hp": 4,
				"intents": ["ATK", "ENRAGE", "ATK", "ATK"]},
		],
		"reinforcement": {"name": "Recruit", "atk": 2, "hp": 3},
	},

	"haunted_crypt": {
		"name": "Haunted Crypt", "act": 2, "type": "combat", "hp": 19,
		"passive_id": "crypt_ghost",
		"passive_desc": "When an enemy creature dies, summon a 1/1 Ghost with Swift in a random empty lane.",
		"deck": [
			{"name": "Wraith", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "RETREAT"]},
			{"name": "Wraith", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "RETREAT"]},
			{"name": "Wraith", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "RETREAT"]},
			{"name": "Banshee", "atk": 2, "hp": 3,
				"on_death": {"type": "debuff_all_player_atk", "value": 1},
				"intents": ["ATK", "ABILITY", "ATK", "ATK"],
				"ability": {"type": "terrify"}},
			{"name": "Banshee", "atk": 2, "hp": 3,
				"on_death": {"type": "debuff_all_player_atk", "value": 1},
				"intents": ["ATK", "ABILITY", "ATK", "ATK"],
				"ability": {"type": "terrify"}},
			{"name": "Gravewarden", "atk": 3, "hp": 5, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Specter", "atk": 2, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
		],
		"reinforcement": {"name": "Shade", "atk": 2, "hp": 2},
	},

	"fire_giants_forge": {
		"name": "Fire Giant's Forge", "act": 2, "type": "combat", "hp": 20,
		"passive_id": "forge_burn_all",
		"passive_desc": "Start of each round, deal 1 damage to ALL creatures on both sides.",
		"deck": [
			{"name": "Flame Golem", "atk": 3, "hp": 5,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Flame Golem", "atk": 3, "hp": 5,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Flame Golem", "atk": 3, "hp": 5,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Forge Guardian", "atk": 2, "hp": 6, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Forge Guardian", "atk": 2, "hp": 6, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Ember Elemental", "atk": 4, "hp": 3,
				"on_death": {"type": "damage_adjacent", "value": 2},
				"intents": ["ATK", "ENRAGE", "ATK", "ATK"]},
			{"name": "Slag Heap", "atk": 0, "hp": 6,
				"on_death": {"type": "damage_opposing_lane", "value": 3},
				"intents": ["GUARD", "GUARD", "GUARD", "GUARD"]},
		],
		"reinforcement": {"name": "Cinder", "atk": 2, "hp": 2},
	},

	"oathbroken_knights": {
		# Keyword spread (armored/swift/last_stand). Champion forces a 2-tap decision: kill now or after board's set.
		"name": "Oath-Broken Knights", "act": 2, "type": "combat", "hp": 19,
		"passive_id": "", "passive_desc": "",
		"deck": [
			{"name": "Disgraced Squire", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Disgraced Squire", "atk": 3, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Fallen Knight", "atk": 2, "hp": 5, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Fallen Knight", "atk": 2, "hp": 5, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Black Outrider", "atk": 3, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Forsworn Champion", "atk": 4, "hp": 5, "kw": ["last_stand"],
				"on_death": {"type": "debuff_all_player_atk", "value": 1},
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Footman", "atk": 2, "hp": 3},
	},

	"ash_hounds": {
		# Swift tempo race — forge_burn_all shaves the hounds (intentional). Houndmaster's death rattle keeps pressure post-kill.
		"name": "Ash Hounds", "act": 2, "type": "combat", "hp": 18,
		"passive_id": "forge_burn_all",
		"passive_desc": "Start of each round, deal 1 damage to ALL creatures on both sides.",
		"deck": [
			{"name": "Ash Hound", "atk": 3, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Ash Hound", "atk": 3, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Ash Hound", "atk": 3, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Ember Mastiff", "atk": 3, "hp": 4, "wither": 1,
				"intents": ["ATK", "ATK", "ENRAGE", "ATK"]},
			{"name": "Ember Mastiff", "atk": 3, "hp": 4, "wither": 1,
				"intents": ["ATK", "ATK", "ENRAGE", "ATK"]},
			{"name": "Cinder Warden", "atk": 2, "hp": 5, "kw": ["regenerate"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD", "ATK"]},
			{"name": "Houndmaster", "atk": 3, "hp": 4,
				"on_death": {"type": "damage_face", "value": 3},
				"intents": ["ATK", "RALLY", "ATK", "ATK", "CHARGE"]},
		],
		"reinforcement": {"name": "Cinder Pup", "atk": 2, "hp": 2},
	},

	# =================== ACT 2 — ELITE ============================

	"demon_vanguard": {
		"name": "Demon Vanguard", "act": 2, "type": "elite", "hp": 28,
		"passive_id": "demon_spell_buff",
		"passive_desc": "Whenever player plays a spell, a random enemy creature gains +1 ATK permanently.",
		"deck": [
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Hellhound", "atk": 4, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE"]},
			{"name": "Hellhound", "atk": 4, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE"]},
			{"name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"],
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "devour"}},
			{"name": "Infernal", "atk": 5, "hp": 4, "kw": ["piercing"],
				"intents": ["ATK", "ENRAGE", "ATK", "ATK", "CHARGE", "ATK"]},
		],
		"reinforcement": {"name": "Imp", "atk": 2, "hp": 3},
	},

	"puppeteer": {
		"name": "The Puppeteer", "act": 2, "type": "elite", "hp": 26,
		"passive_id": "puppet_keyword_copy",
		"passive_desc": "Start of each round, copy keywords from player's highest-ATK creature onto a random enemy.",
		"deck": [
			{"name": "Marionette", "atk": 2, "hp": 3,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Marionette", "atk": 2, "hp": 3,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Marionette", "atk": 2, "hp": 3,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Marionette", "atk": 2, "hp": 3,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Puppet Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "GUARD"]},
			{"name": "Puppet Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "GUARD"]},
			{"name": "Shadow Double", "atk": 3, "hp": 3,
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "steal_atk", "value": 1}},
			{"name": "Puppeteer's Guard", "atk": 3, "hp": 5,
				"intents": ["ATK", "GUARD", "ATK", "ATK", "RALLY"]},
		],
		"reinforcement": {"name": "String", "atk": 1, "hp": 2},
	},

	# =================== ACT 2 — BOSS =============================

	"collector": {
		"name": "The Collector", "act": 2, "type": "boss", "hp": 34,
		"passive_id": "collector_heal",
		"passive_desc": "Whenever player plays a creature from hand, The Collector heals 1 HP.",
		"deck": [
			{"name": "Collector Golem", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Collector Golem", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Collector Golem", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Display Case", "atk": 2, "hp": 5, "kw": ["armored"],
				"intents": ["GUARD", "GUARD", "ATK", "GUARD", "GUARD"]},
			{"name": "Collector's Pride", "atk": 4, "hp": 4,
				"on_death": {"type": "summon", "atk": 2, "hp": 2},
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Soul Cage", "atk": 3, "hp": 3,
				"floop": {"type": "steal_atk", "value": 1},
				"intents": ["ATK", "ABILITY", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "steal_atk", "value": 1}},
			{"name": "Collector's Champion", "atk": 4, "hp": 5, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "CHARGE", "ATK"],
				"ability": {"type": "mark"}},
		],
		"reinforcement": {"name": "Trinket", "atk": 2, "hp": 3},
	},

	"hollow_king": {
		"name": "The Hollow King", "act": 2, "type": "boss", "hp": 32,
		"passive_id": "hollow_king_snipe",
		"passive_desc": "Start of each round, player's highest-ATK creature takes 3 damage.",
		"deck": [
			{"name": "Hollow Knight", "atk": 3, "hp": 5,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Hollow Knight", "atk": 3, "hp": 5,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Hollow Knight", "atk": 3, "hp": 5,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Void Guard", "atk": 2, "hp": 6, "kw": ["armored", "regenerate"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD", "GUARD", "ATK"]},
			{"name": "Shadow Blade", "atk": 4, "hp": 3, "kw": ["swift", "piercing"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Hollow Champion", "atk": 5, "hp": 5, "kw": ["last_stand"],
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK", "CHARGE", "ABILITY"],
				"ability": {"type": "hex"}},
		],
		"reinforcement": {"name": "Shade Knight", "atk": 3, "hp": 3},
	},

	# =================== ACT 3 — COMBAT ===========================

	"mirror_temple": {
		"name": "Mirror Temple", "act": 3, "type": "combat", "hp": 22,
		"passive_id": "mirror_instant_place",
		"passive_desc": "When a player creature dies, enemy draws and places a creature immediately.",
		"deck": [
			{"name": "Mirror Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "RETREAT", "ATK", "ATK"]},
			{"name": "Mirror Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "RETREAT", "ATK", "ATK"]},
			{"name": "Mirror Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "RETREAT", "ATK", "ATK"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE"]},
			{"name": "Doppel", "atk": 4, "hp": 4,
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "steal_atk", "value": 1}},
			{"name": "Temple Guardian", "atk": 4, "hp": 5, "kw": ["last_stand"],
				"intents": ["ATK", "GUARD", "ATK", "ATK", "CHARGE"]},
		],
		"reinforcement": {"name": "Shard", "atk": 2, "hp": 3},
	},

	"elemental_nexus": {
		"name": "Elemental Nexus", "act": 3, "type": "combat", "hp": 23,
		"passive_id": "nexus_rotation",
		"passive_desc": "Rotates each round: R1 all enemies +1 ATK, R2 heal 2, R3 Thorns this round. Repeat.",
		"deck": [
			{"name": "Fire Elemental", "atk": 4, "hp": 3,
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Fire Elemental", "atk": 4, "hp": 3,
				"intents": ["ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Ice Elemental", "atk": 2, "hp": 5,
				"intents": ["ATK", "GUARD", "ATK", "GUARD", "ATK"]},
			{"name": "Ice Elemental", "atk": 2, "hp": 5,
				"intents": ["ATK", "GUARD", "ATK", "GUARD", "ATK"]},
			{"name": "Storm Elemental", "atk": 3, "hp": 4, "kw": ["ranged"]},
			{"name": "Earth Elemental", "atk": 3, "hp": 6, "kw": ["armored"],
				"intents": ["ATK", "GUARD", "GUARD", "ATK"]},
			{"name": "Nexus Core", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0},
				"intents": ["RALLY", "ATK", "ABILITY", "RALLY", "ATK", "ATK"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Spark", "atk": 2, "hp": 2},
	},

	"executioners_block": {
		"name": "The Executioner's Block", "act": 3, "type": "combat", "hp": 21,
		"passive_id": "executioner_face",
		"passive_desc": "Each round, the highest-ATK enemy also deals its ATK as face damage to the player.",
		"deck": [
			{"name": "Headsman", "atk": 4, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK", "ENRAGE"]},
			{"name": "Headsman", "atk": 4, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK", "ENRAGE"]},
			{"name": "Torturer", "atk": 3, "hp": 3,
				"on_enter": {"type": "debuff_opposing_atk", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "mark"}},
			{"name": "Torturer", "atk": 3, "hp": 3,
				"on_enter": {"type": "debuff_opposing_atk", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "mark"}},
			{"name": "Condemned", "atk": 2, "hp": 5, "kw": ["thorns", "last_stand"],
				"intents": ["ATK", "GUARD", "ATK", "GUARD", "ATK", "GUARD"]},
			{"name": "Executioner", "atk": 5, "hp": 4, "kw": ["piercing"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK", "ATK"]},
		],
		"reinforcement": {"name": "Jailer", "atk": 2, "hp": 4},
	},

	"dragons_lair": {
		"name": "Dragon's Lair", "act": 3, "type": "combat", "hp": 24,
		"passive_id": "dragon_lair_periodic",
		"passive_desc": "Every 3 rounds, deal 3 damage to ALL player creatures.",
		"deck": [
			{"name": "Drake", "atk": 3, "hp": 4, "kw": ["piercing"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Drake", "atk": 3, "hp": 4, "kw": ["piercing"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Drake", "atk": 3, "hp": 4, "kw": ["piercing"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Wyrm", "atk": 4, "hp": 5, "kw": ["regenerate"],
				"intents": ["ATK", "ATK", "HEAL", "ATK", "ATK"]},
			{"name": "Wyrm", "atk": 4, "hp": 5, "kw": ["regenerate"],
				"intents": ["ATK", "ATK", "HEAL", "ATK", "ATK"]},
			{"name": "Elder Dragon", "atk": 5, "hp": 6, "wither": 1,
				"on_enter": {"type": "damage_all_enemies", "value": 2},
				"intents": ["ATK", "ATK", "ATK", "ABILITY", "ATK", "ATK", "CHARGE"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Whelp", "atk": 2, "hp": 3},
	},

	"pyre_cult": {
		# Fire cult — forge_burn_all + Conflagrant's 3-face on-death demands one-shot kills.
		"name": "The Pyre Cult", "act": 3, "type": "combat", "hp": 22,
		"passive_id": "forge_burn_all",
		"passive_desc": "Start of each round, deal 1 damage to ALL creatures on both sides.",
		"deck": [
			{"name": "Torchbearer", "atk": 3, "hp": 3, "kw": ["thorns"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Torchbearer", "atk": 3, "hp": 3, "kw": ["thorns"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Ash Devotee", "atk": 2, "hp": 5, "kw": ["regenerate"],
				"on_death": {"type": "damage_adjacent", "value": 2},
				"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
			{"name": "Ash Devotee", "atk": 2, "hp": 5, "kw": ["regenerate"],
				"on_death": {"type": "damage_adjacent", "value": 2},
				"intents": ["ATK", "HEAL", "ATK", "HEAL"]},
			{"name": "Kindler", "atk": 3, "hp": 4,
				"on_enter": {"type": "damage_face", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK"]},
			{"name": "Conflagrant", "atk": 5, "hp": 5, "kw": ["piercing"],
				"on_death": {"type": "damage_face", "value": 3},
				"intents": ["ATK", "ATK", "ENRAGE", "ATK", "ATK", "CHARGE"]},
		],
		"reinforcement": {"name": "Cinder Acolyte", "atk": 2, "hp": 2},
	},

	"withered_court": {
		# cultist_buff keeps refreshing one royal. Wither + last_stand royalty force patience-vs-race decision.
		"name": "The Withered Court", "act": 3, "type": "combat", "hp": 24,
		"passive_id": "cultist_buff",
		"passive_desc": "Each round, a random enemy gains +1/+1.",
		"deck": [
			{"name": "Dust Courtier", "atk": 3, "hp": 4, "wither": 1,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Dust Courtier", "atk": 3, "hp": 4, "wither": 1,
				"intents": ["ATK", "ATK", "RETREAT", "ATK"]},
			{"name": "Pale Handmaid", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0},
				"intents": ["RALLY", "ATK", "RALLY", "ATK"]},
			{"name": "Mourner Knight", "atk": 4, "hp": 4, "kw": ["thorns"],
				"on_death": {"type": "debuff_all_player_atk", "value": 1},
				"intents": ["ATK", "GUARD", "ATK", "ATK", "ENRAGE"]},
			{"name": "Mourner Knight", "atk": 4, "hp": 4, "kw": ["thorns"],
				"on_death": {"type": "debuff_all_player_atk", "value": 1},
				"intents": ["ATK", "GUARD", "ATK", "ATK", "ENRAGE"]},
			{"name": "Hollow Princess", "atk": 3, "hp": 6, "kw": ["last_stand", "regenerate"],
				"intents": ["ATK", "ABILITY", "ATK", "HEAL", "ATK", "ABILITY"],
				"ability": {"type": "terrify"}},
			{"name": "Crowned Cadaver", "atk": 5, "hp": 5, "kw": ["last_stand"],
				"adj_buff": {"atk": 1, "hp": 0},
				"intents": ["ATK", "RALLY", "ATK", "ATK", "CHARGE", "ATK"]},
		],
		"reinforcement": {"name": "Court Mourner", "atk": 2, "hp": 2},
	},

	"killing_choir": {
		# Ranged back-row + hollow_king_snipe punishes single-bomb strategy. Forces spreading damage across mediums.
		"name": "The Killing Choir", "act": 3, "type": "combat", "hp": 23,
		"passive_id": "hollow_king_snipe",
		"passive_desc": "Start of each round, player's highest-ATK creature takes 3 damage.",
		"deck": [
			{"name": "Chorister", "atk": 3, "hp": 3, "kw": ["ranged"],
				"intents": ["ATK", "ATK", "ATK", "RETREAT"]},
			{"name": "Chorister", "atk": 3, "hp": 3, "kw": ["ranged"],
				"intents": ["ATK", "ATK", "ATK", "RETREAT"]},
			{"name": "Hymn Bearer", "atk": 2, "hp": 5, "adj_buff": {"atk": 1, "hp": 0},
				"intents": ["RALLY", "ATK", "RALLY", "ATK", "GUARD"]},
			{"name": "Echo Twin", "atk": 3, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_random_player", "value": 2},
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Echo Twin", "atk": 3, "hp": 3, "kw": ["swift"],
				"on_enter": {"type": "damage_random_player", "value": 2},
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Silent Choirmaster", "atk": 3, "hp": 4,
				"on_enter": {"type": "debuff_opposing_atk", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "mark"}},
			{"name": "Lead Cantor", "atk": 4, "hp": 6, "kw": ["piercing"],
				"on_enter": {"type": "damage_all_enemies", "value": 2},
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Hummer", "atk": 2, "hp": 2},
	},

	# =================== ACT 3 — ELITE ============================

	"archlich": {
		"name": "The Archlich", "act": 3, "type": "elite", "hp": 32,
		"passive_id": "archlich_immortal",
		"passive_desc": "Enemy creatures cannot be reduced below 1 HP by creature attacks. Only spells/effects can finish them.",
		"deck": [
			{"name": "Skeleton Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Skeleton Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Skeleton Knight", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Bone Dragon", "atk": 4, "hp": 5, "kw": ["piercing", "regenerate"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK", "ATK", "ENRAGE"]},
			{"name": "Lich Acolyte", "atk": 2, "hp": 3,
				"floop": {"type": "summon_token", "atk": 2, "hp": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "resurrect"}},
			{"name": "Phylactery", "atk": 0, "hp": 8,
				"intents": ["GUARD", "GUARD", "GUARD", "GUARD", "GUARD", "GUARD"]},
		],
		"reinforcement": {"name": "Risen", "atk": 2, "hp": 3},
	},

	"void_walker": {
		"name": "The Void Walker", "act": 3, "type": "elite", "hp": 30,
		"passive_id": "void_exile",
		"passive_desc": "Start of player's turn, exile top card of deck (removed from fight permanently).",
		"deck": [
			{"name": "Void Spawn", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Void Spawn", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Void Spawn", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Rift Stalker", "atk": 4, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "RETREAT", "ATK", "ATK"]},
			{"name": "Rift Stalker", "atk": 4, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "RETREAT", "ATK", "ATK"]},
			{"name": "Null Beast", "atk": 3, "hp": 5,
				"on_enter": {"type": "discard_random", "value": 1},
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK"],
				"ability": {"type": "hex"}},
			{"name": "Void Maw", "atk": 5, "hp": 5,
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "devour"}},
		],
		"reinforcement": {"name": "Fragment", "atk": 2, "hp": 2},
	},

	"corrupted_shepherd": {
		# wolf_pack_revenge weaponizes the clear-the-board instinct. Mad Shepherd's adj_buff stacks with the passive.
		"name": "The Corrupted Shepherd", "act": 3, "type": "elite", "hp": 30,
		"passive_id": "wolf_pack_revenge",
		"passive_desc": "When an enemy creature dies, adjacent enemies gain +1 ATK this turn.",
		"deck": [
			{"name": "Maggot-Lamb", "atk": 3, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Maggot-Lamb", "atk": 3, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Maggot-Lamb", "atk": 3, "hp": 2, "kw": ["swift"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Bone-Ram", "atk": 4, "hp": 3, "kw": ["piercing"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Bone-Ram", "atk": 4, "hp": 3, "kw": ["piercing"],
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Flock Whisperer", "atk": 2, "hp": 5, "kw": ["regenerate"],
				"on_death": {"type": "summon", "name": "Stray Lamb", "atk": 2, "hp": 2},
				"intents": ["ATK", "HEAL", "ATK", "ABILITY", "ATK"],
				"ability": {"type": "resurrect"}},
			{"name": "Mad Shepherd", "atk": 4, "hp": 6, "kw": ["last_stand"],
				"adj_buff": {"atk": 1, "hp": 0},
				"intents": ["ATK", "RALLY", "ATK", "ATK", "ABILITY", "ATK", "CHARGE"],
				"ability": {"type": "warcry", "value": 1}},
		],
		"reinforcement": {"name": "Stray Lamb", "atk": 2, "hp": 2},
	},

	# =================== ACT 3 — BOSS =============================

	"the_devil": {
		"name": "THE DEVIL", "act": 3, "type": "boss", "hp": 40,
		"passive_id": "devil_cycle",
		"passive_desc": "Cycle: R1 deal 2 face damage. R2 heal 1 per enemy on board. R3 deal 3 to player's highest-ATK creature. Repeat.",
		"deck": [
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Demon Soldier", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Hellfire Imp", "atk": 3, "hp": 3,
				"on_enter": {"type": "damage_face", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK", "ABILITY"],
				"ability": {"type": "curse"}},
			{"name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"],
				"intents": ["ATK", "ATK", "ABILITY", "ATK", "ATK", "ATK", "GUARD", "ABILITY"],
				"ability": {"type": "devour"}},
			{"name": "Soul Reaper", "atk": 3, "hp": 4, "kw": ["swift", "piercing"],
				"intents": ["ATK", "ATK", "ATK", "CHARGE", "ATK", "ATK"]},
			{"name": "Devil's Champion", "atk": 5, "hp": 6,
				"kw": ["last_stand"], "adj_buff": {"atk": 1, "hp": 0},
				"intents": ["ATK", "RALLY", "ATK", "ATK", "ABILITY", "ATK", "CHARGE"],
				"ability": {"type": "warcry", "value": 1}},
			{"name": "Iron Vanguard", "atk": 4, "hp": 5, "kw": ["last_stand"],
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ENRAGE"]},
		],
		"reinforcement": {"name": "Lesser Demon", "atk": 3, "hp": 3},
	},

	"the_crone": {
		# Curse-pile boss: passive seeds Curses into your deck every round and
		# eventually punishes you for carrying them. Tempo answer is removal
		# (banish/exhaust) and aggressive face damage to skip the late phases.
		"name": "THE CRONE", "act": 3, "type": "boss", "hp": 36,
		"passive_id": "crone_drip",
		"passive_desc": "End of round: adds 1 Curse to your discard pile.",
		"deck": [
			{"name": "Skeleton", "atk": 2, "hp": 2,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Skeleton", "atk": 2, "hp": 2,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Wraith", "atk": 2, "hp": 3, "kw": ["swift"],
				"intents": ["ATK", "ATK", "ATK", "ATK"]},
			{"name": "Bone Crone", "atk": 3, "hp": 4,
				"on_enter": {"type": "damage_face", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK"]},
			{"name": "Bone Crone", "atk": 3, "hp": 4,
				"on_enter": {"type": "damage_face", "value": 2},
				"intents": ["ATK", "ABILITY", "ATK", "ATK"]},
			{"name": "Marrow Knight", "atk": 4, "hp": 5, "kw": ["armored"],
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Soul Drinker", "atk": 3, "hp": 5, "kw": ["regenerate"],
				"intents": ["ATK", "HEAL", "ATK", "ATK"]},
			{"name": "The Crone", "atk": 5, "hp": 7, "kw": ["regenerate", "last_stand"],
				"intents": ["ATK", "ABILITY", "ATK", "CHARGE", "ATK"],
				"ability": {"type": "curse"}},
		],
		"reinforcement": {"name": "Specter", "atk": 2, "hp": 2, "kw": ["swift"]},
	},

	"the_black_tide": {
		# Swarm boss: keeps refilling its board and eventually buffs every wave.
		# The player needs board clears (Earthquake / Apocalypse / Inferno) and
		# enough single-target damage to finish off the high-HP centerpieces.
		"name": "THE BLACK TIDE", "act": 3, "type": "boss", "hp": 38,
		"passive_id": "tide_swell",
		"passive_desc": "End of round: if fewer than 4 enemy creatures, summon a 2/3 Deepling.",
		"deck": [
			{"name": "Tide Spawn", "atk": 2, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Tide Spawn", "atk": 2, "hp": 3,
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "Deepling", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK"]},
			{"name": "Deepling", "atk": 3, "hp": 4,
				"intents": ["ATK", "ATK", "ATK"]},
			{"name": "Drowned", "atk": 3, "hp": 5, "kw": ["last_stand"],
				"intents": ["ATK", "ATK", "GUARD", "ATK", "ATK"]},
			{"name": "Tentacle", "atk": 2, "hp": 6, "kw": ["regenerate"],
				"intents": ["ATK", "ATK", "ATK", "GUARD", "ATK"]},
			{"name": "Anglerfish", "atk": 4, "hp": 3,
				"on_enter": {"type": "damage_opposing", "value": 2},
				"intents": ["ATK", "ATK", "CHARGE", "ATK"]},
			{"name": "The Black Tide", "atk": 6, "hp": 8, "kw": ["piercing", "regenerate"],
				"intents": ["ATK", "RALLY", "ATK", "ATK", "CHARGE", "ATK"]},
		],
		"reinforcement": {"name": "Spawn", "atk": 2, "hp": 2},
	},
}
