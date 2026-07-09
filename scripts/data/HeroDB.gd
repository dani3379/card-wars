extends Node
## HeroDB.gd — autoload. 5 starter heroes (StS-style: each is a deck + 1 mild
## signature relic). Picked at the start of a run, before the map opens.
##
## Each hero entry:
##   id, name, tagline (one-line vibe), lore (one-line in-world stakes), desc (longer pitch), deck (Array[String]
##   of card ids — always 10 cards), relic (id of a tier:"starting" relic from
##   RelicDB), faction (id into FACTIONS — the kingdom this hero rules as a
##   rival lord), portrait (optional res:// path).
##
## Cross-run muster unlocks (2026-07-04 — progression options, never stats):
##   relic_alt — a second tier:"starting" relic; the run-setup pane offers the
##     CHOICE once the hero has won a march (MetaState wins >= 1).
##   deck_alt — {name, tagline, deck}: an alternate 10-card start, a 2-3 card
##     swap on the default that pushes the hero's secondary theme; offered
##     after a victory at Ascension 4+ (MetaState best_asc >= 4). Both are
##     consumed by RunState.start_new_run via pending_signature_relic /
##     pending_deck_variant.

const HEROES: Dictionary = {
	"raider": {
		"id": "raider",
		"name": "Raider",
		"tagline": "Burn them out fast.",
		"lore": "You don't outlive the road; you outrun it.",
		"desc": "Aggressive Swift rush. Outriders and Ratlings strike in the pre-phase, before the wall goes up.",
		"deck": [
			"goblin", "goblin",
			"levy_rider", "levy_rider",
			"ratling", "ratling",
			"brute", "brute",
			"fireball", "fireball",
		],
		"relic": "veterans_medal",
		"relic_alt": "couriers_bag",
		"deck_alt": {
			"name": "The Grass Levies",
			"tagline": "More riders, lighter gear.",
			"deck": [
				"goblin", "goblin",
				"levy_rider", "levy_rider", "levy_rider", "levy_rider",
				"ratling", "ratling",
				"fireball", "fireball",
			],
		},
		"faction": "grasswake",
	},
	"stalwart": {
		"id": "stalwart",
		"name": "Stalwart",
		"tagline": "Outlast everything.",
		"lore": "Everything here ends eventually. You intend to be the exception.",
		"desc": "A wall that outlasts. Palisades soak the line while Trolls heal, Naga punishes the front, and Strike clears the rest.",
		"deck": [
			"troll", "troll",
			"brute", "brute",
			"naga", "naga",
			"palisade", "palisade",
			"strike", "strike",
		],
		"relic": "iron_buckler",
		"relic_alt": "coin_purse",
		"deck_alt": {
			"name": "The Old Legion",
			"tagline": "All wall, no haste.",
			"deck": [
				"troll", "troll",
				"naga", "naga",
				"palisade", "palisade", "palisade", "palisade",
				"strike", "strike",
			],
		},
		"faction": "last_wall",
	},
	"acolyte": {
		"id": "acolyte",
		"name": "Acolyte",
		"tagline": "Death pays the bill.",
		"lore": "Something underneath is always owed. You pay in others.",
		"desc": "Spend cheap creatures freely — Ratlings sting on the way out and Mourners pay Command from the grave. Each funeral feeds the next turn.",
		"deck": [
			"ratling", "ratling", "ratling",
			"brute",
			"goblin", "goblin",
			"mourner", "mourner",
			"strike", "strike",
		],
		"relic": "soul_lantern",
		"relic_alt": "scouts_emblem",
		"deck_alt": {
			"name": "The Second Funeral",
			"tagline": "More graves, deeper debts.",
			"deck": [
				"ratling", "ratling", "ratling", "ratling",
				"goblin", "goblin",
				"mourner", "mourner",
				"strike", "strike",
			],
		},
		"faction": "owed",
	},
	"pyromancer": {
		"id": "pyromancer",
		"name": "Pyromancer",
		"tagline": "The spells do the work.",
		"lore": "You started this with fire. You see no reason to stop now.",
		"desc": "Most of the deck is burn — Fireball, Strike, and Spark do the work while hired Trolls hold the door.",
		"deck": [
			"fireball", "fireball", "fireball",
			"strike", "strike", "strike",
			"spark", "spark",
			"troll", "troll",
		],
		"relic": "worn_spellbook",
		"relic_alt": "ember_crown",
		"deck_alt": {
			"name": "The Mirror Line",
			"tagline": "More sparks than steel.",
			"deck": [
				"fireball", "fireball", "fireball",
				"strike", "strike",
				"spark", "spark", "spark", "spark",
				"troll",
			],
		},
		"faction": "lanternhall",
	},
	"kindler": {
		"id": "kindler",
		"name": "The Kindler",
		"tagline": "Everything burns on a timer.",
		"lore": "You feed the fire because you remember what happens when it gets hungry.",
		"desc": "Throw cheap bombs that detonate into their face and snowball with Rampage. Spend creatures freely — they were always meant to go up.",
		"deck": [
			"cinder_pup", "cinder_pup",
			"kindling", "kindling",
			"ash_hound", "ash_hound",
			"burning_martyr", "burning_martyr",
			"fireball", "strike",
		],
		"relic": "ember_censer",
		"relic_alt": "couriers_bag",
		"deck_alt": {
			"name": "The Powder Cart",
			"tagline": "More timers, shorter fuses.",
			"deck": [
				"cinder_pup", "cinder_pup", "cinder_pup",
				"kindling", "kindling", "kindling", "kindling",
				"burning_martyr", "burning_martyr",
				"fireball",
			],
		},
		"faction": "everflame",
	},
}

# Display order on the pick screen — left to right, aggro → control → ritual → spell → pyre.
const HERO_ORDER: Array[String] = ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]

# Fallback hero id used by RunState.start_new_run when no hero is specified
# (e.g. legacy save migration or a code path that forgot to pass one).
const DEFAULT_HERO: String = "stalwart"

# ── Successor Wars: the five kingdoms ──
# hero ↔ faction is 1:1 — each hero rules one kingdom, and the heroes you
# didn't pick are the rival lords you march on. Display data lives here (not
# a separate DB) because the mapping IS the hero roster. Names locked per
# CONQUEST_REDESIGN.md §15.1 (#7).
#   name — banner name shown on map/intro surfaces.
#   element / engine — the kingdom's color and its mechanical identity.
#   engine_line — one-line intro flavor for "what this kingdom does to you".
#   lord_title — subtitle under the rival's name on boss surfaces.
#   hero — the lord's hero id (inverse of HEROES[x].faction).
#   color — banner/political-wash tint for map skinning (tuned later in pixels).
const FACTIONS: Dictionary = {
	# History-inspired: each kingdom channels one age of the island's real
	# past (the map IS Sicily). Grasswake = the horse-conquest (landless
	# brothers over the water, forty lances took an island). Last Wall = the
	# legion (drill, rank rotation, lost battles / won wars). Owed = the
	# merchant-god city (hired spears, the furnace altar, the ledger).
	# Lanternhall = the geometer's city (burning mirrors, the harbor claw,
	# circles). Everflame = the liquid fire (the sealed recipe, it burns on
	# water). Ids/mechanics untouched — texture only.
	"grasswake": {
		"id": "grasswake",
		"name": "The Grasswake",
		"element": "Horse & Salt",
		"engine": "Overrun",
		"engine_line": "The empty lane is their highway.",
		"lord_title": "The Landless Brother",
		"hero": "raider",
		"color": Color(0.33, 0.50, 0.55),
	},
	"last_wall": {
		"id": "last_wall",
		"name": "The Last Wall",
		"element": "Stone",
		"engine": "Formation",
		"engine_line": "The longer they stand, the stronger they stand.",
		"lord_title": "The Last Centurion",
		"hero": "stalwart",
		"color": Color(0.58, 0.55, 0.47),
	},
	"owed": {
		"id": "owed",
		"name": "The Owed",
		"element": "Ash & Coin",
		"engine": "The Tithe",
		"engine_line": "Every death here is a deposit. They collect.",
		"lord_title": "The Keeper of Ledgers",
		"hero": "acolyte",
		"color": Color(0.47, 0.52, 0.30),
	},
	"lanternhall": {
		"id": "lanternhall",
		"name": "The Lanternhall",
		"element": "Mirror & Star",
		"engine": "Foresight",
		"engine_line": "They have already seen this turn.",
		"lord_title": "The Measurer of Circles",
		"hero": "pyromancer",
		"color": Color(0.52, 0.60, 0.78),
	},
	"everflame": {
		"id": "everflame",
		"name": "The Everflame",
		"element": "Fire",
		"engine": "The Fuse",
		"engine_line": "Nothing pays now. Everything pays later, bigger.",
		"lord_title": "The Keeper of the Recipe",
		"hero": "kindler",
		"color": Color(0.78, 0.36, 0.20),
	},
}


static func get_hero(id: String) -> Dictionary:
	if HEROES.has(id):
		return HEROES[id]
	push_warning("HeroDB: unknown hero id '%s'" % id)
	return HEROES[DEFAULT_HERO]


static func has_hero(id: String) -> bool:
	return HEROES.has(id)


## Faction id for a hero ("" never happens for live data — every hero entry
## carries one).
static func get_faction(hero_id: String) -> String:
	return String(get_hero(hero_id).get("faction", ""))


static func faction_info(faction_id: String) -> Dictionary:
	if FACTIONS.has(faction_id):
		return FACTIONS[faction_id]
	push_warning("HeroDB: unknown faction id '%s'" % faction_id)
	return {}


## The hero id of the lord who rules a faction (inverse of get_faction).
static func faction_lord(faction_id: String) -> String:
	return String(faction_info(faction_id).get("hero", ""))
