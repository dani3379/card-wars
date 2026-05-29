extends Node
## HeroDB.gd — autoload. 4 starter heroes (StS-style: each is a deck + 1 mild
## signature relic). Picked at the start of a run, before the map opens.
##
## Each hero entry:
##   id, name, tagline (one-line vibe), desc (longer pitch), deck (Array[String]
##   of card ids — always 10 cards), relic (id of a tier:"starting" relic from
##   RelicDB), portrait (optional res:// path).

const HEROES: Dictionary = {
	"raider": {
		"id": "raider",
		"name": "Raider",
		"tagline": "Burn them out fast.",
		"desc": "Aggressive 1-cost rush. Goblins and Ratlings hit before the wall goes up.",
		"deck": [
			"goblin", "goblin", "goblin", "goblin",
			"ratling", "ratling",
			"brute", "brute",
			"fireball", "fireball",
		],
		"relic": "veterans_medal",
	},
	"stalwart": {
		"id": "stalwart",
		"name": "Stalwart",
		"tagline": "Outlast everything.",
		"desc": "Mid-cost trades and removal. Trolls heal, Naga punishes the front, Strike clears the rest.",
		"deck": [
			"troll", "troll", "troll",
			"brute", "brute",
			"naga", "naga",
			"strike", "strike", "strike",
		],
		"relic": "iron_buckler",
	},
	"acolyte": {
		"id": "acolyte",
		"name": "Acolyte",
		"tagline": "Death pays the bill.",
		"desc": "Ratlings die fast and proc value. Every funeral feeds your next turn.",
		"deck": [
			"ratling", "ratling", "ratling",
			"brute", "brute", "brute",
			"goblin", "goblin",
			"strike", "strike",
		],
		"relic": "soul_lantern",
	},
	"pyromancer": {
		"id": "pyromancer",
		"name": "Pyromancer",
		"tagline": "The spells do the work.",
		"desc": "Half the deck is burn. Hexblades grow with every spell you cast while Fireball and Strike close it out.",
		"deck": [
			"fireball", "fireball", "fireball",
			"strike", "strike", "strike",
			"goblin", "goblin",
			"hexblade", "hexblade",
		],
		"relic": "worn_spellbook",
	},
}

# Display order on the pick screen — left to right, aggro → control → ritual → spell.
const HERO_ORDER: Array[String] = ["raider", "stalwart", "acolyte", "pyromancer"]

# Fallback hero id used by RunState.start_new_run when no hero is specified
# (e.g. legacy save migration or a code path that forgot to pass one).
const DEFAULT_HERO: String = "stalwart"


static func get_hero(id: String) -> Dictionary:
	if HEROES.has(id):
		return HEROES[id]
	push_warning("HeroDB: unknown hero id '%s'" % id)
	return HEROES[DEFAULT_HERO]


static func has_hero(id: String) -> bool:
	return HEROES.has(id)
