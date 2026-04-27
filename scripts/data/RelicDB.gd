extends Node
## RelicDB.gd — relic definitions.
##
## Each relic has:
##   id, name, desc, tier
##   hooks       : Array[String], names of game events this relic responds to.
##                 The Combat scene checks these strings and applies effects.
##                 Hook names:
##                   "turn_start"       — start of player turn
##                   "card_played"      — a card was just played by player
##                   "card_killed"      — a player card killed an enemy card
##                   "hero_damaged"     — player hero took damage
##                   "combat_start"     — first turn of a fight
##   value       : int, effect magnitude (relic-specific meaning)
##   lane        : int, -1 means any lane, 0-3 means specific lane only
##                 (used by lane-restricted relics like Battle Standard)

const RELICS: Dictionary = {
	# ── Common (tier 1) — appear on regular elite rewards ──
	"bloodstone": {
		"id": "bloodstone", "name": "Bloodstone",
		"desc": "Heal 2 HP at the start of your turn.",
		"tier": 1, "hooks": ["turn_start"], "value": 2, "lane": -1,
	},
	"chronograph": {
		"id": "chronograph", "name": "Chronograph",
		"desc": "Your max mana is increased by 1.",
		"tier": 1, "hooks": ["combat_start"], "value": 1, "lane": -1,
	},
	"thorned_pendant": {
		"id": "thorned_pendant", "name": "Thorned Pendant",
		"desc": "When your hero takes damage, deal 1 to a random enemy card.",
		"tier": 1, "hooks": ["hero_damaged"], "value": 1, "lane": -1,
	},
	"forge_banner": {
		"id": "forge_banner", "name": "Forge Banner",
		"desc": "Your cards in the Forge lane have +1 ATK.",
		"tier": 1, "hooks": [], "value": 1, "lane": 0,
	},
	"grove_banner": {
		"id": "grove_banner", "name": "Grove Banner",
		"desc": "Your cards in the Grove lane have +1 HP.",
		"tier": 1, "hooks": [], "value": 1, "lane": 1,
	},

	# ── Uncommon (tier 2) ──
	"vampires_fang": {
		"id": "vampires_fang", "name": "Vampire's Fang",
		"desc": "Once per turn, the first damage you deal heals you for 1.",
		"tier": 2, "hooks": ["card_killed"], "value": 1, "lane": -1,
	},
	"burning_brand": {
		"id": "burning_brand", "name": "Burning Brand",
		"desc": "Your Charge cards deal +1 damage.",
		"tier": 2, "hooks": [], "value": 1, "lane": -1,
	},
	"ash_crown": {
		"id": "ash_crown", "name": "Ash Crown",
		"desc": "Start each combat with +1 mana that turn.",
		"tier": 2, "hooks": ["combat_start"], "value": 1, "lane": -1,
	},
	"witchs_grimoire": {
		"id": "witchs_grimoire", "name": "Witch's Grimoire",
		"desc": "Draw 1 extra card each turn.",
		"tier": 2, "hooks": ["turn_start"], "value": 1, "lane": -1,
	},

	# ── Rare (tier 3) — boss rewards ──
	"phoenix_heart": {
		"id": "phoenix_heart", "name": "Phoenix Heart",
		"desc": "The first time you would die in a run, instead heal to 1 HP.",
		"tier": 3, "hooks": ["hero_damaged"], "value": 1, "lane": -1,
	},
	"meadow_crown": {
		"id": "meadow_crown", "name": "Meadow Crown",
		"desc": "Your hero starts with +5 max HP.",
		"tier": 3, "hooks": [], "value": 5, "lane": -1,
	},
}


static func get_relic(id: String) -> Dictionary:
	if RELICS.has(id):
		return RELICS[id].duplicate()
	push_warning("RelicDB: unknown relic id '%s'" % id)
	return {}


static func random_relic_at_tier(tier: int) -> String:
	var pool: Array = []
	for id in RELICS.keys():
		if RELICS[id].tier == tier:
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


# 3 distinct random relics from elite/boss reward pools
static func roll_relic_reward(tier: int, exclude: Array[String] = []) -> Array[String]:
	var picked: Array[String] = []
	var attempts := 0
	while picked.size() < 3 and attempts < 30:
		attempts += 1
		var id = random_relic_at_tier(tier)
		if id != "" and not picked.has(id) and not exclude.has(id):
			picked.append(id)
	return picked
