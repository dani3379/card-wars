extends Node
## EncounterDB.gd — Premade fight lineups from the master design document.
## 26 encounters: Act 1 (6 combat, 2 elite, 2 boss), Act 2 (5 combat, 2 elite, 2 boss),
## Act 3 (4 combat, 2 elite, 1 boss).
## Each encounter has an ordered creature deck, reinforcement, HP, and optional passive.

var _enc_counter: int = 0


func get_encounter(id: String) -> Dictionary:
	if ENCOUNTERS.has(id):
		return ENCOUNTERS[id].duplicate(true)
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
			{"name": "Goblin", "atk": 2, "hp": 2},
			{"name": "Goblin", "atk": 2, "hp": 2},
			{"name": "Goblin Scout", "atk": 2, "hp": 3},
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
			{"name": "Alpha", "atk": 3, "hp": 4},
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
			{"name": "Captain", "atk": 3, "hp": 3},
		],
		"reinforcement": {"name": "Thug", "atk": 1, "hp": 2},
	},

	"mushroom_grove": {
		"name": "Mushroom Grove", "act": 1, "type": "combat", "hp": 14,
		"passive_id": "mushroom_heal",
		"passive_desc": "Heal all enemy creatures 1 at end of round.",
		"deck": [
			{"name": "Sprout", "atk": 1, "hp": 4},
			{"name": "Sprout", "atk": 1, "hp": 4},
			{"name": "Sprout", "atk": 1, "hp": 4},
			{"name": "Spore Beast", "atk": 2, "hp": 4},
			{"name": "Spore Beast", "atk": 2, "hp": 4},
			{"name": "Mycelium", "atk": 2, "hp": 5,
				"on_death": {"type": "damage_all_enemies", "value": 1}},
		],
		"reinforcement": {"name": "Spore", "atk": 1, "hp": 2},
	},

	"stone_sentinels": {
		"name": "Stone Sentinels", "act": 1, "type": "combat", "hp": 15,
		"passive_id": "stone_armor",
		"passive_desc": "Enemy Armored creatures take 2 less damage instead of 1.",
		"deck": [
			{"name": "Golem", "atk": 2, "hp": 4},
			{"name": "Golem", "atk": 2, "hp": 4},
			{"name": "Golem", "atk": 2, "hp": 4, "kw": ["armored"]},
			{"name": "Golem", "atk": 2, "hp": 4, "kw": ["armored"]},
			{"name": "Rock Hurler", "atk": 3, "hp": 3,
				"on_enter": {"type": "damage_random_player", "value": 2}},
			{"name": "Granite Guard", "atk": 2, "hp": 5, "kw": ["thorns"]},
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
				"on_death": {"type": "damage_opposing", "value": 2}},
		],
		"reinforcement": {"name": "Chick", "atk": 1, "hp": 1},
	},

	# =================== ACT 1 — ELITE ============================

	"orc_warband": {
		"name": "Orc Warband", "act": 1, "type": "elite", "hp": 20,
		"passive_id": "orc_random_buff",
		"passive_desc": "Each round, a random enemy creature gains +1 ATK permanently.",
		"deck": [
			{"name": "Warrior", "atk": 3, "hp": 3},
			{"name": "Warrior", "atk": 3, "hp": 3},
			{"name": "Warrior", "atk": 3, "hp": 3},
			{"name": "Brute", "atk": 3, "hp": 4},
			{"name": "Brute", "atk": 3, "hp": 4},
			{"name": "Drummer", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Chieftain", "atk": 4, "hp": 4},
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
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Dark Acolyte", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Lich", "atk": 3, "hp": 5, "kw": ["regenerate"]},
		],
		"reinforcement": {"name": "Risen Bones", "atk": 1, "hp": 2},
	},

	# =================== ACT 1 — BOSS =============================

	"iron_warden": {
		"name": "The Iron Warden", "act": 1, "type": "boss", "hp": 25,
		"passive_id": "iron_warden_burn",
		"passive_desc": "2 face damage to player at end of each round.",
		"deck": [
			{"name": "Iron Sentinel", "atk": 3, "hp": 4},
			{"name": "Iron Sentinel", "atk": 3, "hp": 4},
			{"name": "Iron Sentinel", "atk": 3, "hp": 4},
			{"name": "Iron Guard", "atk": 2, "hp": 5, "kw": ["armored"]},
			{"name": "Siege Engine", "atk": 3, "hp": 3,
				"on_enter": {"type": "damage_all_enemies", "value": 1}},
			{"name": "Warden's Champion", "atk": 4, "hp": 4, "kw": ["swift"]},
			{"name": "Iron Vanguard", "atk": 4, "hp": 5, "kw": ["last_stand"]},
		],
		"reinforcement": {"name": "Iron Recruit", "atk": 2, "hp": 3},
	},

	"dragon_lord": {
		"name": "Dragon Lord", "act": 1, "type": "boss", "hp": 23,
		"passive_id": "dragon_lord_piercing",
		"passive_desc": "All enemy creatures have Piercing.",
		"deck": [
			{"name": "Drake", "atk": 3, "hp": 3},
			{"name": "Drake", "atk": 3, "hp": 3},
			{"name": "Drake", "atk": 3, "hp": 3},
			{"name": "Wyrm", "atk": 3, "hp": 4, "kw": ["regenerate"]},
			{"name": "Wyrm", "atk": 3, "hp": 4, "kw": ["regenerate"]},
			{"name": "Elder Drake", "atk": 4, "hp": 5,
				"on_enter": {"type": "damage_all_enemies", "value": 2}},
		],
		"reinforcement": {"name": "Whelp", "atk": 2, "hp": 2},
	},

	# =================== ACT 2 — COMBAT ===========================

	"cultist_enclave": {
		"name": "Cultist Enclave", "act": 2, "type": "combat", "hp": 18,
		"passive_id": "cultist_buff",
		"passive_desc": "Each round, a random enemy gains +1/+1.",
		"deck": [
			{"name": "Cultist", "atk": 3, "hp": 3},
			{"name": "Cultist", "atk": 3, "hp": 3},
			{"name": "Cultist", "atk": 3, "hp": 3},
			{"name": "Dark Priest", "atk": 2, "hp": 4, "kw": ["regenerate"]},
			{"name": "Dark Priest", "atk": 2, "hp": 4, "kw": ["regenerate"]},
			{"name": "Zealot", "atk": 3, "hp": 3,
				"on_death": {"type": "damage_face", "value": 2}},
			{"name": "Fanatic", "atk": 4, "hp": 4},
		],
		"reinforcement": {"name": "Initiate", "atk": 2, "hp": 2},
	},

	"swamp_horror": {
		"name": "Swamp Horror", "act": 2, "type": "combat", "hp": 18,
		"passive_id": "swamp_thorns",
		"passive_desc": "All enemy creatures have Thorns.",
		"deck": [
			{"name": "Bog Lurker", "atk": 2, "hp": 5},
			{"name": "Bog Lurker", "atk": 2, "hp": 5},
			{"name": "Bog Lurker", "atk": 2, "hp": 5},
			{"name": "Mire Beast", "atk": 3, "hp": 4},
			{"name": "Mire Beast", "atk": 3, "hp": 4},
			{"name": "Swamp Hag", "atk": 2, "hp": 3,
				"floop": {"type": "heal_all_friendly", "value": 2}},
			{"name": "Hydra Spawn", "atk": 3, "hp": 3, "kw": ["regenerate"]},
		],
		"reinforcement": {"name": "Leech", "atk": 1, "hp": 3},
	},

	"mercenary_company": {
		"name": "Mercenary Company", "act": 2, "type": "combat", "hp": 17,
		"passive_id": "merc_piercing",
		"passive_desc": "Enemy creatures with 4+ ATK have Piercing.",
		"deck": [
			{"name": "Sellsword", "atk": 3, "hp": 3},
			{"name": "Sellsword", "atk": 3, "hp": 3},
			{"name": "Captain", "atk": 4, "hp": 4},
			{"name": "Captain", "atk": 4, "hp": 4},
			{"name": "Sharpshooter", "atk": 3, "hp": 2, "kw": ["ranged"]},
			{"name": "Enforcer", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Brute", "atk": 5, "hp": 4},
		],
		"reinforcement": {"name": "Recruit", "atk": 2, "hp": 3},
	},

	"haunted_crypt": {
		"name": "Haunted Crypt", "act": 2, "type": "combat", "hp": 19,
		"passive_id": "crypt_ghost",
		"passive_desc": "When an enemy creature dies, summon a 1/1 Ghost with Swift in a random empty lane.",
		"deck": [
			{"name": "Wraith", "atk": 3, "hp": 4},
			{"name": "Wraith", "atk": 3, "hp": 4},
			{"name": "Wraith", "atk": 3, "hp": 4},
			{"name": "Banshee", "atk": 2, "hp": 3,
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Banshee", "atk": 2, "hp": 3,
				"on_death": {"type": "debuff_all_player_atk", "value": 1}},
			{"name": "Gravewarden", "atk": 3, "hp": 5, "kw": ["armored"]},
			{"name": "Specter", "atk": 2, "hp": 2, "kw": ["swift"]},
		],
		"reinforcement": {"name": "Shade", "atk": 2, "hp": 2},
	},

	"fire_giants_forge": {
		"name": "Fire Giant's Forge", "act": 2, "type": "combat", "hp": 20,
		"passive_id": "forge_burn_all",
		"passive_desc": "Start of each round, deal 1 damage to ALL creatures on both sides.",
		"deck": [
			{"name": "Flame Golem", "atk": 3, "hp": 5},
			{"name": "Flame Golem", "atk": 3, "hp": 5},
			{"name": "Flame Golem", "atk": 3, "hp": 5},
			{"name": "Forge Guardian", "atk": 2, "hp": 6, "kw": ["armored"]},
			{"name": "Forge Guardian", "atk": 2, "hp": 6, "kw": ["armored"]},
			{"name": "Ember Elemental", "atk": 4, "hp": 3,
				"on_death": {"type": "damage_adjacent", "value": 2}},
			{"name": "Slag Heap", "atk": 0, "hp": 6,
				"on_death": {"type": "damage_opposing_lane", "value": 3}},
		],
		"reinforcement": {"name": "Cinder", "atk": 2, "hp": 2},
	},

	# =================== ACT 2 — ELITE ============================

	"demon_vanguard": {
		"name": "Demon Vanguard", "act": 2, "type": "elite", "hp": 28,
		"passive_id": "demon_spell_buff",
		"passive_desc": "Whenever player plays a spell, a random enemy creature gains +1 ATK permanently.",
		"deck": [
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Hellhound", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Hellhound", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"]},
			{"name": "Infernal", "atk": 5, "hp": 4, "kw": ["piercing"]},
		],
		"reinforcement": {"name": "Imp", "atk": 2, "hp": 3},
	},

	"puppeteer": {
		"name": "The Puppeteer", "act": 2, "type": "elite", "hp": 26,
		"passive_id": "puppet_keyword_copy",
		"passive_desc": "Start of each round, copy keywords from player's highest-ATK creature onto a random enemy.",
		"deck": [
			{"name": "Marionette", "atk": 2, "hp": 3},
			{"name": "Marionette", "atk": 2, "hp": 3},
			{"name": "Marionette", "atk": 2, "hp": 3},
			{"name": "Marionette", "atk": 2, "hp": 3},
			{"name": "Puppet Knight", "atk": 3, "hp": 4},
			{"name": "Puppet Knight", "atk": 3, "hp": 4},
			{"name": "Shadow Double", "atk": 3, "hp": 3},
			{"name": "Puppeteer's Guard", "atk": 3, "hp": 5},
		],
		"reinforcement": {"name": "String", "atk": 1, "hp": 2},
	},

	# =================== ACT 2 — BOSS =============================

	"collector": {
		"name": "The Collector", "act": 2, "type": "boss", "hp": 34,
		"passive_id": "collector_heal",
		"passive_desc": "Whenever player plays a creature from hand, The Collector heals 1 HP.",
		"deck": [
			{"name": "Collector Golem", "atk": 3, "hp": 4},
			{"name": "Collector Golem", "atk": 3, "hp": 4},
			{"name": "Collector Golem", "atk": 3, "hp": 4},
			{"name": "Display Case", "atk": 2, "hp": 5, "kw": ["armored"]},
			{"name": "Collector's Pride", "atk": 4, "hp": 4,
				"on_death": {"type": "summon", "atk": 2, "hp": 2}},
			{"name": "Soul Cage", "atk": 3, "hp": 3,
				"floop": {"type": "steal_atk", "value": 1}},
			{"name": "Collector's Champion", "atk": 4, "hp": 5, "kw": ["swift"]},
		],
		"reinforcement": {"name": "Trinket", "atk": 2, "hp": 3},
	},

	"hollow_king": {
		"name": "The Hollow King", "act": 2, "type": "boss", "hp": 32,
		"passive_id": "hollow_king_snipe",
		"passive_desc": "Start of each round, player's highest-ATK creature takes 3 damage.",
		"deck": [
			{"name": "Hollow Knight", "atk": 3, "hp": 5},
			{"name": "Hollow Knight", "atk": 3, "hp": 5},
			{"name": "Hollow Knight", "atk": 3, "hp": 5},
			{"name": "Void Guard", "atk": 2, "hp": 6, "kw": ["armored", "regenerate"]},
			{"name": "Shadow Blade", "atk": 4, "hp": 3, "kw": ["swift", "piercing"]},
			{"name": "Hollow Champion", "atk": 5, "hp": 5, "kw": ["last_stand"]},
		],
		"reinforcement": {"name": "Shade Knight", "atk": 3, "hp": 3},
	},

	# =================== ACT 3 — COMBAT ===========================

	"mirror_temple": {
		"name": "Mirror Temple", "act": 3, "type": "combat", "hp": 22,
		"passive_id": "mirror_instant_place",
		"passive_desc": "When a player creature dies, enemy draws and places a creature immediately.",
		"deck": [
			{"name": "Mirror Knight", "atk": 3, "hp": 4},
			{"name": "Mirror Knight", "atk": 3, "hp": 4},
			{"name": "Mirror Knight", "atk": 3, "hp": 4},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Reflection", "atk": 2, "hp": 3, "kw": ["swift"]},
			{"name": "Doppel", "atk": 4, "hp": 4},
			{"name": "Temple Guardian", "atk": 4, "hp": 5, "kw": ["last_stand"]},
		],
		"reinforcement": {"name": "Shard", "atk": 2, "hp": 3},
	},

	"elemental_nexus": {
		"name": "Elemental Nexus", "act": 3, "type": "combat", "hp": 23,
		"passive_id": "nexus_rotation",
		"passive_desc": "Rotates each round: R1 all enemies +1 ATK, R2 heal 2, R3 Thorns this round. Repeat.",
		"deck": [
			{"name": "Fire Elemental", "atk": 4, "hp": 3},
			{"name": "Fire Elemental", "atk": 4, "hp": 3},
			{"name": "Ice Elemental", "atk": 2, "hp": 5},
			{"name": "Ice Elemental", "atk": 2, "hp": 5},
			{"name": "Storm Elemental", "atk": 3, "hp": 4, "kw": ["ranged"]},
			{"name": "Earth Elemental", "atk": 3, "hp": 6, "kw": ["armored"]},
			{"name": "Nexus Core", "atk": 2, "hp": 4, "adj_buff": {"atk": 1, "hp": 0}},
		],
		"reinforcement": {"name": "Spark", "atk": 2, "hp": 2},
	},

	"executioners_block": {
		"name": "The Executioner's Block", "act": 3, "type": "combat", "hp": 21,
		"passive_id": "executioner_face",
		"passive_desc": "Each round, the highest-ATK enemy also deals its ATK as face damage to the player.",
		"deck": [
			{"name": "Headsman", "atk": 4, "hp": 4},
			{"name": "Headsman", "atk": 4, "hp": 4},
			{"name": "Torturer", "atk": 3, "hp": 3,
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Torturer", "atk": 3, "hp": 3,
				"on_enter": {"type": "debuff_opposing_atk", "value": 2}},
			{"name": "Condemned", "atk": 2, "hp": 5, "kw": ["thorns", "last_stand"]},
			{"name": "Executioner", "atk": 5, "hp": 4, "kw": ["piercing"]},
		],
		"reinforcement": {"name": "Jailer", "atk": 2, "hp": 4},
	},

	"dragons_lair": {
		"name": "Dragon's Lair", "act": 3, "type": "combat", "hp": 24,
		"passive_id": "dragon_lair_periodic",
		"passive_desc": "Every 3 rounds, deal 3 damage to ALL player creatures.",
		"deck": [
			{"name": "Drake", "atk": 3, "hp": 4, "kw": ["piercing"]},
			{"name": "Drake", "atk": 3, "hp": 4, "kw": ["piercing"]},
			{"name": "Drake", "atk": 3, "hp": 4, "kw": ["piercing"]},
			{"name": "Wyrm", "atk": 4, "hp": 5, "kw": ["regenerate"]},
			{"name": "Wyrm", "atk": 4, "hp": 5, "kw": ["regenerate"]},
			{"name": "Elder Dragon", "atk": 5, "hp": 6, "wither": 1,
				"on_enter": {"type": "damage_all_enemies", "value": 2}},
		],
		"reinforcement": {"name": "Whelp", "atk": 2, "hp": 3},
	},

	# =================== ACT 3 — ELITE ============================

	"archlich": {
		"name": "The Archlich", "act": 3, "type": "elite", "hp": 32,
		"passive_id": "archlich_immortal",
		"passive_desc": "Enemy creatures cannot be reduced below 1 HP by creature attacks. Only spells/effects can finish them.",
		"deck": [
			{"name": "Skeleton Knight", "atk": 3, "hp": 4},
			{"name": "Skeleton Knight", "atk": 3, "hp": 4},
			{"name": "Skeleton Knight", "atk": 3, "hp": 4},
			{"name": "Bone Dragon", "atk": 4, "hp": 5, "kw": ["piercing", "regenerate"]},
			{"name": "Lich Acolyte", "atk": 2, "hp": 3,
				"floop": {"type": "summon_token", "atk": 2, "hp": 2}},
			{"name": "Phylactery", "atk": 0, "hp": 8},
		],
		"reinforcement": {"name": "Risen", "atk": 2, "hp": 3},
	},

	"void_walker": {
		"name": "The Void Walker", "act": 3, "type": "elite", "hp": 30,
		"passive_id": "void_exile",
		"passive_desc": "Start of player's turn, exile top card of deck (removed from fight permanently).",
		"deck": [
			{"name": "Void Spawn", "atk": 3, "hp": 4},
			{"name": "Void Spawn", "atk": 3, "hp": 4},
			{"name": "Void Spawn", "atk": 3, "hp": 4},
			{"name": "Rift Stalker", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Rift Stalker", "atk": 4, "hp": 3, "kw": ["swift"]},
			{"name": "Null Beast", "atk": 3, "hp": 5,
				"on_enter": {"type": "discard_random", "value": 1}},
			{"name": "Void Maw", "atk": 5, "hp": 5},
		],
		"reinforcement": {"name": "Fragment", "atk": 2, "hp": 2},
	},

	# =================== ACT 3 — BOSS =============================

	"the_devil": {
		"name": "THE DEVIL", "act": 3, "type": "boss", "hp": 40,
		"passive_id": "devil_cycle",
		"passive_desc": "Cycle: R1 deal 2 face damage. R2 heal 1 per enemy on board. R3 deal 3 to player's highest-ATK creature. Repeat.",
		"deck": [
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Demon Soldier", "atk": 3, "hp": 4},
			{"name": "Hellfire Imp", "atk": 3, "hp": 3,
				"on_enter": {"type": "damage_face", "value": 2}},
			{"name": "Pit Fiend", "atk": 4, "hp": 5, "kw": ["armored", "regenerate"]},
			{"name": "Soul Reaper", "atk": 3, "hp": 4, "kw": ["swift", "piercing"]},
			{"name": "Devil's Champion", "atk": 5, "hp": 6,
				"kw": ["last_stand"], "adj_buff": {"atk": 1, "hp": 0}},
			{"name": "Iron Vanguard", "atk": 4, "hp": 5, "kw": ["last_stand"]},
		],
		"reinforcement": {"name": "Lesser Demon", "atk": 3, "hp": 3},
	},
}
