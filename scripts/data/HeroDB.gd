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
##
## THE PITCH CONTRACT (re-broken 2026-08-01, second time — see
## docs/RUN_OPENING_REDESIGN_20260728.md §5). `desc` is printed IN FULL in THE
## COLUMN pane of the run opening and is among the first sentences a new player
## reads, so every clause in it must map to something a DAY-ONE player holds:
## a card in the DEFAULT `deck`, or the DEFAULT `relic` (handed over at run
## start and printed directly under the pitch). It may NEVER describe
## `relic_alt` or `deck_alt` — both are unlock-gated, so a pitch that leans on
## one sells a doctrine the reader cannot have. `tagline` carries the same bar
## and is capped by the 430px roster box at ~42 characters.
##
## Three pitches drifted back across that line and were rewritten 2026-08-01:
## the Kindler's third clause was Chain Censer (relic_alt) verbatim; the
## Stalwart's attributed a survival engine to Formation, which is adjacency;
## and the Acolyte's promised a Shade, which was true only while the Funeral
## Lantern was still Soul Lantern's twin (reshaped 2026-07-28). Gate:
## tools/_probe_hero_pitch.tscn.

const HEROES: Dictionary = {
	"raider": {
		"id": "raider",
		"name": "Raider",
		"tagline": "Move first. Strike where they are not.",
		"lore": "The Grasswake wins by never holding the same ground twice.",
		# Clause 3 was "punish enemies driven out of position" — nothing in the
		# opener moves an ENEMY. Enemy displacement exists only on the pool's
		# removal slate (Sapper's Charge / Shove / Scatter the Line). Cut Them Off
		# reads _player_moved_a_friendly_this_round instead, and its own resolver
		# comment says why ("enemy movement is far too rare to carry a card in the
		# Raider's opening ten"). The payoff is YOUR mobility; the pitch says so.
		"desc": "Relocate the line, turn fresh angles into Swift attacks, and strike harder once you have moved a friendly.",
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
		"tagline": "Hold the line. Heal what takes the hit.",
		"lore": "The Last Wall is made from the soldier beside you.",
		# "let Formation turn survival into strength" was two errors in one clause.
		# Formation is ADJACENCY, not endurance (KeywordEffects start-of-round arm:
		# +1/+1 while a friendly stands beside it), and the survival->strength
		# engine it described is Centurion's Rule, the relic — which IS the default
		# signature, so the mechanic was real and only its owner was wrong. One
		# opener card carries Formation (Rank Spearman); the pitch now scopes it to
		# one body, and the repair clause keeps Wall Tender's heal.
		"desc": "Build an adjacent line, heal the bodies that take the blow, and let Formation grow a soldier who never stands alone.",
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
		# The Shade was a FOSSIL. Funeral Lantern shipped as Soul Lantern's twin
		# ("a Shade rises in its lane") and was reshaped 2026-07-28 to double the
		# bequest instead; the pitch was not. The only two Shade sources left in the
		# game are Apocalypse and Raise the Fallen, both rare pool spells. Also
		# retired: "on command" — lowercase, one letter from the resource's name.
		#
		# CLAUSE 3 CUT 2026-08-01 ("and let the first death each round pay twice").
		# It was Funeral Lantern's rule in other words, and when it was written the
		# relic's own text lived in a tooltip, so the pitch was the only place a
		# player could read it. THE COLUMN now prints the signature with its icon,
		# its name and its rule in full five lines below — and prints whichever
		# relic is actually equipped, while this line cannot: a player who toggles
		# ALT RELIC to Ledger Seal was reading a pane that pitched the Lantern above
		# a signature block showing the Seal. Two clauses, both about the DECK the
		# ten card faces underneath are showing.
		"desc": "Arrange different On-Death bequests and call one due early.",
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
		"tagline": "Cast in sequence. Each arms a creature.",
		"lore": "Lanternhall measures a battle before it commits to one.",
		# Every clause here was already backed (Glass Savant + Mirror Primer on the
		# distinct-name sequence, Star Chart on the reveal, three spell-reading
		# bodies). Tightened only: "the next arrival" now matches Star Chart's
		# printed "the next enemy arrival", and "answer each cast" over-promised —
		# the passives fire on the first cast and the second DIFFERENT one, so
		# "each cast in turn" is what actually happens.
		"desc": "Sequence differently named spells, reveal the next enemy arrival, and let each cast in turn arm another creature.",
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
		# "the first detonation pulls the next one forward" was Chain Censer's rule
		# word for word — and Chain Censer is relic_alt, gated on a win WITH this
		# hero. The 2026-07-28 swap below moved War Bellows into the signature slot
		# precisely so run one had a doctrine that fires; the pitch kept selling the
		# locked one. Nothing in the opener chains a fuse: Fuse Tender ADDS a round
		# of fuse and Touchpaper shortens one by hand. Clause 3 WAS War Bellows —
		# cut 2026-08-01 for the same reason as the Acolyte's: the signature block
		# below now prints the equipped relic's own rule, this line always printed
		# the DEFAULT one, and the two disagreed the moment ALT RELIC was toggled to
		# Chain Censer.
		"desc": "Delay one fuse and shorten another.",
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
