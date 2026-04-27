extends Node
## CardDB.gd — all card definitions in one place.
##
## Each card is a Dictionary with:
##   id          : String, stable identifier used for art lookup
##   name        : String, display name
##   cost        : int, mana cost to play
##   atk         : int, attack
##   hp          : int, max HP
##   keywords    : Array[String], one or more of:
##                 "charge"     — attacks the turn it's played
##                 "taunt"      — opponent must engage this lane first
##                 "lifesteal"  — damage dealt heals owner's hero by same amount
##                 "frenzy"     — +1 ATK each time this kills another card
##                 "deathrattle_smite" — on death, deals 2 to opposing card
##                 "deathrattle_burn"  — on death, deals 1 to opposing hero
##                 "onplay_draw"       — drawing 1 card on play
##                 "onplay_smite"      — deals 2 to enemy hero on play
##   tier        : int, 1-3, used by reward and shop pools
##                 1 = starter / common, 2 = uncommon, 3 = rare
##   desc        : String, plain text description (auto-shown on card)
##
## Cards are split into PLAYER_POOL (what you can collect) and ENEMY_POOL
## (what AI uses). Some cards appear in both with different parameters.
##
## To add a new card: add to the appropriate dict. The code reads
## everything dynamically, no other changes needed.

const PLAYER_POOL: Dictionary = {
	# ── STARTER (tier 1) — what every run begins with, plus common rewards ──
	"sapling_guard": {
		"id": "sapling_guard", "name": "Sapling Guard",
		"cost": 1, "atk": 1, "hp": 3, "keywords": ["taunt"],
		"tier": 1, "desc": "Taunt. A small thorn-bound sapling stands its ground."
	},
	"ember_imp": {
		"id": "ember_imp", "name": "Ember Imp",
		"cost": 1, "atk": 2, "hp": 1, "keywords": ["charge"],
		"tier": 1, "desc": "Charge. Bright. Brief. Furious."
	},
	"hedge_witch": {
		"id": "hedge_witch", "name": "Hedge Witch",
		"cost": 2, "atk": 1, "hp": 3, "keywords": ["onplay_draw"],
		"tier": 1, "desc": "On Play: draw a card. She knows what comes next."
	},
	"thorn_acolyte": {
		"id": "thorn_acolyte", "name": "Thorn Acolyte",
		"cost": 2, "atk": 2, "hp": 2, "keywords": [],
		"tier": 1, "desc": "A novice of the burning hedge."
	},
	"meadow_wolf": {
		"id": "meadow_wolf", "name": "Meadow Wolf",
		"cost": 2, "atk": 3, "hp": 2, "keywords": [],
		"tier": 1, "desc": "Lean. Hungry. Fast."
	},
	"scarecrow_lord": {
		"id": "scarecrow_lord", "name": "Scarecrow Lord",
		"cost": 3, "atk": 3, "hp": 4, "keywords": ["taunt"],
		"tier": 1, "desc": "Taunt. The wicker king of the burning fields."
	},

	# ── UNCOMMON (tier 2) ──
	"bone_queen": {
		"id": "bone_queen", "name": "Bone Queen",
		"cost": 3, "atk": 3, "hp": 4, "keywords": ["deathrattle_smite"],
		"tier": 2, "desc": "Deathrattle: deal 2 damage to the opposing card."
	},
	"vampire_thrall": {
		"id": "vampire_thrall", "name": "Vampire Thrall",
		"cost": 3, "atk": 3, "hp": 3, "keywords": ["lifesteal"],
		"tier": 2, "desc": "Lifesteal. Drinks deeply from every wound."
	},
	"iron_titan": {
		"id": "iron_titan", "name": "Iron Titan",
		"cost": 4, "atk": 3, "hp": 6, "keywords": ["taunt"],
		"tier": 2, "desc": "Taunt. Forged in the heart of the meadow."
	},
	"crow_priest": {
		"id": "crow_priest", "name": "Crow Priest",
		"cost": 3, "atk": 2, "hp": 3, "keywords": ["onplay_draw", "deathrattle_burn"],
		"tier": 2, "desc": "On Play: draw 1. Deathrattle: 1 damage to enemy hero."
	},
	"blood_pharaoh": {
		"id": "blood_pharaoh", "name": "Blood Pharaoh",
		"cost": 4, "atk": 4, "hp": 4, "keywords": ["lifesteal"],
		"tier": 2, "desc": "Lifesteal. Ancient and ravenous."
	},
	"ash_revenant": {
		"id": "ash_revenant", "name": "Ash Revenant",
		"cost": 4, "atk": 4, "hp": 3, "keywords": ["frenzy"],
		"tier": 2, "desc": "Frenzy: +1 ATK after killing a card."
	},

	# ── RARE (tier 3) ──
	"void_king": {
		"id": "void_king", "name": "Void King",
		"cost": 5, "atk": 5, "hp": 6, "keywords": ["taunt", "lifesteal"],
		"tier": 3, "desc": "Taunt, Lifesteal. The final darkness, crowned."
	},
	"frost_monarch": {
		"id": "frost_monarch", "name": "Frost Monarch",
		"cost": 6, "atk": 5, "hp": 7, "keywords": ["onplay_smite"],
		"tier": 3, "desc": "On Play: 2 damage to enemy hero. The long winter, crowned."
	},
	"hellfire_drake": {
		"id": "hellfire_drake", "name": "Hellfire Drake",
		"cost": 5, "atk": 6, "hp": 4, "keywords": ["charge"],
		"tier": 3, "desc": "Charge. The sky burns where it passes."
	},
}


const ENEMY_POOL: Dictionary = {
	# Tier 1 enemies (early floors)
	"shadow_imp": {
		"id": "shadow_imp", "name": "Shadow Imp",
		"cost": 1, "atk": 2, "hp": 1, "keywords": ["charge"],
		"tier": 1, "desc": "Charge. Vicious."
	},
	"husk": {
		"id": "husk", "name": "Husk",
		"cost": 1, "atk": 1, "hp": 3, "keywords": ["taunt"],
		"tier": 1, "desc": "Taunt. Hollow but stubborn."
	},
	"crow_swarm": {
		"id": "crow_swarm", "name": "Crow Swarm",
		"cost": 2, "atk": 2, "hp": 2, "keywords": [],
		"tier": 1, "desc": "Black wings."
	},

	# Tier 2 enemies (middle floors)
	"stone_golem": {
		"id": "stone_golem", "name": "Stone Golem",
		"cost": 2, "atk": 2, "hp": 5, "keywords": ["taunt"],
		"tier": 2, "desc": "Taunt. Unyielding."
	},
	"cursed_wraith": {
		"id": "cursed_wraith", "name": "Cursed Wraith",
		"cost": 3, "atk": 4, "hp": 3, "keywords": ["lifesteal"],
		"tier": 2, "desc": "Lifesteal. Feeds on fear."
	},
	"thresher": {
		"id": "thresher", "name": "Thresher",
		"cost": 3, "atk": 3, "hp": 3, "keywords": ["frenzy"],
		"tier": 2, "desc": "Frenzy. Cuts and keeps cutting."
	},

	# Tier 3 enemies (elites and bosses)
	"hellfire_drake": {
		"id": "hellfire_drake", "name": "Hellfire Drake",
		"cost": 4, "atk": 5, "hp": 4, "keywords": ["charge"],
		"tier": 3, "desc": "Charge. Burns all."
	},
	"the_harvester": {
		"id": "the_harvester", "name": "The Harvester",
		"cost": 5, "atk": 5, "hp": 6, "keywords": ["taunt", "deathrattle_smite"],
		"tier": 3, "desc": "Taunt. Deathrattle: 2 damage to opposing card."
	},
	"the_first_flame": {
		"id": "the_first_flame", "name": "The First Flame",
		"cost": 6, "atk": 6, "hp": 8, "keywords": ["charge", "lifesteal"],
		"tier": 3, "desc": "BOSS. Charge, Lifesteal. The fire that started it all."
	},
}


# Initial deck every run starts with — 10 weak cards
const STARTER_DECK: Array[String] = [
	"sapling_guard", "sapling_guard", "sapling_guard",
	"ember_imp", "ember_imp",
	"thorn_acolyte", "thorn_acolyte",
	"meadow_wolf", "meadow_wolf",
	"hedge_witch",
]


# ── Public API ──

static func get_card_data(id: String) -> Dictionary:
	if PLAYER_POOL.has(id):
		return PLAYER_POOL[id].duplicate()
	if ENEMY_POOL.has(id):
		return ENEMY_POOL[id].duplicate()
	push_warning("CardDB: unknown card id '%s'" % id)
	return {}


static func random_player_card_at_tier(tier: int) -> String:
	var pool: Array = []
	for id in PLAYER_POOL.keys():
		if PLAYER_POOL[id].tier == tier:
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


static func random_enemy_card_at_tier(tier: int) -> String:
	var pool: Array = []
	for id in ENEMY_POOL.keys():
		# Don't pick the boss randomly
		if ENEMY_POOL[id].tier == tier and id != "the_first_flame":
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


# Returns 3 distinct random player cards weighted by floor depth.
# Early floors lean tier-1, late floors lean tier-2/3.
static func roll_card_reward(floor_num: int) -> Array[String]:
	var weights: Array
	if floor_num <= 2:
		weights = [70, 25, 5]
	elif floor_num <= 5:
		weights = [40, 50, 10]
	else:
		weights = [20, 50, 30]

	var picked: Array[String] = []
	var attempts := 0
	while picked.size() < 3 and attempts < 50:
		attempts += 1
		var roll = randi() % 100
		var tier: int
		if roll < weights[0]: tier = 1
		elif roll < weights[0] + weights[1]: tier = 2
		else: tier = 3
		var id = random_player_card_at_tier(tier)
		if id != "" and not picked.has(id):
			picked.append(id)
	return picked
