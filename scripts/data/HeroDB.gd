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
		"tagline": "Move first. Strike where they are not.",
		"lore": "The Grasswake wins by never holding the same ground twice.",
		"desc": "Relocate the line, turn fresh angles into Swift attacks, and punish enemies driven out of position.",
		"deck": ["levy_rider", "levy_rider", "goblin", "ratling", "sprite", "brute", "grasswake_lancer", "trail_scout", "spur_forward", "cut_them_off"],
		"relic": "marching_spurs",
		"relic_alt": "rearward_horn",
		"deck_alt": {"name": "The Rearward Horn", "tagline": "A heavier reserve answers the horn.",
			"deck": ["levy_rider", "levy_rider", "goblin", "ratling", "sprite", "brute", "grasswake_lancer", "spur_forward", "naga", "strike"]},
		"faction": "grasswake",
	},
	"stalwart": {
		"id": "stalwart",
		"name": "Stalwart",
		"tagline": "Stand together. Survive the answer.",
		"lore": "The Last Wall is made from the soldier beside you.",
		"desc": "Build an adjacent line, repair the bodies that take the blow, and let Formation turn survival into strength.",
		"deck": ["palisade", "palisade", "troll", "sprite", "brute", "rank_spearman", "wall_tender", "standard_page", "close_ranks_order", "strike"],
		"relic": "centurions_rule",
		"relic_alt": "reserve_standard",
		"deck_alt": {"name": "The Reserve Standard", "tagline": "Fresh ranks wait behind the line.",
			"deck": ["palisade", "palisade", "troll", "sprite", "brute", "rank_spearman", "standard_page", "naga", "levy_rider", "strike"]},
		"faction": "last_wall",
	},
	"acolyte": {
		"id": "acolyte",
		"name": "Acolyte",
		"tagline": "Choose the death. Collect what follows.",
		"lore": "The Owed keep accounts even for the nameless dead.",
		"desc": "Arrange different death bequests, call one due on command, and leave a Shade or an inheritance in the opened lane.",
		"deck": ["ratling", "ratling", "mourner", "brute", "troll", "grave_goods_levy", "debt_guard", "read_the_will", "strike", "last_due"],
		"relic": "funeral_lantern",
		"relic_alt": "ledger_seal",
		"deck_alt": {"name": "The Closed Ledger", "tagline": "Less sacrifice. More patient accounting.",
			"deck": ["ratling", "ratling", "mourner", "brute", "troll", "grave_goods_levy", "read_the_will", "sprite", "spark", "strike"]},
		"faction": "owed",
	},
	"pyromancer": {
		"id": "pyromancer",
		"name": "Pyromancer",
		"tagline": "Read the line. Cast the second answer.",
		"lore": "Lanternhall measures a battle before it commits to one.",
		"desc": "Sequence differently named spells, reveal the next arrival, and let the creatures behind the glass answer each cast.",
		"deck": ["lens_apprentice", "lens_apprentice", "troll", "sprite", "mirror_guard", "glass_savant", "strike", "spark", "star_chart", "countermarch_levy"],
		"relic": "mirror_primer",
		"relic_alt": "cinder_crown",
		"deck_alt": {"name": "The Cinder Crown", "tagline": "Plain bodies guard a cheaper first answer.",
			"deck": ["lens_apprentice", "lens_apprentice", "troll", "sprite", "brute", "naga", "strike", "spark", "star_chart", "countermarch_levy"]},
		"faction": "lanternhall",
	},
	"kindler": {
		"id": "kindler",
		"name": "The Kindler",
		"tagline": "Set the fuse. Choose when it catches.",
		"lore": "The Everflame measures time in bodies still burning.",
		"desc": "Delay one fuse, shorten another, and place Doom creatures so the first detonation pulls the next one forward.",
		"deck": ["cinder_pup", "cinder_pup", "kindling", "burning_martyr", "ash_hound", "troll", "fuse_tender", "cinderward", "strike", "touchpaper"],
		# SWAPPED 2026-07-28. It shipped the other way round and that was a
		# deadlock: relic_alt is gated on WINNING with the hero, so the doctrine
		# that makes the Kindler playable was locked behind playing the Kindler.
		# War Bellows is unconditional (the round's first fuse enters +2/+2) and
		# it answers the 1-HP-body problem the OVERKILL pass created, so it is the
		# honest day-one signature. Chain Censer only pays when a detonation
		# happens AND a neighbour carries a fuse — a fine reward for a returning
		# player who can actually field a fuse line, a doctrine that reads blank
		# for whole fights on run one.
		"relic": "war_bellows",
		"relic_alt": "chain_censer",
		"deck_alt": {"name": "The Long Fuse", "tagline": "A slower burn with a second death-line.",
			"deck": ["cinder_pup", "cinder_pup", "kindling", "burning_martyr", "ash_hound", "troll", "cinderward", "mourner", "strike", "spark"]},
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
		"engine": "Death Tax",
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
