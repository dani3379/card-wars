class_name CardArtAliases
## Maps creature ids that don't have dedicated art to ids that DO have art.
## Centralised here so adding a new enemy creature doesn't require touching
## GameTheme — just point its id at an existing portrait.
##
## Loaders memoize their lookups in static caches (negative hits cached too),
## since Card2D probes up to 5 ids per layout build and each probe used to
## fire 2-3 ResourceLoader.exists() stats.

const ALIASES: Dictionary = {
	# ── SET-PIECE bodies (2026-07-20) ────────────────────────────────────
	# Named-action scenarios author their creatures inline (SetPieceDB), so
	# these resolve by NAME through Card2D._find_card_art's name_id path, not
	# by card id — the ids are synthetic (`enc_<name>_<counter>`). Stand-in
	# art until bespoke paintings land; without an entry every body on a
	# scenario board falls back to the same fire placeholder, which is exactly
	# how the first shot of The Sunken Road came out.
	"ditch_raider":         "skirmisher",     # light, fast, in the cut
	"bank_climber":         "e_brute",        # heavier body coming over the top
	"road_breaker":         "breaker",        # its own name, its own art
	"long_knife":           "assassin",
	"road_agent":           "e_enforcer",     # highwayman muscle
	"cart_breaker":         "brute",
	"whistler":             "e_archer",       # the Sniper on the column
	"wheel_cutter":         "duelist",
	"paymasters_cart":      "mule",           # the only draught animal in the set
	"the_bearer":           "doom_knight",    # a dead man still carrying it
	"fourth_legion_dead":   "e_bone_knight",  # the Fourth, ninety years on
	"cornicen":             "battle_drummer", # the horn-player of the legion
	"unpaid_optio":         "ironclad_veteran",
	"gate_section":         "stone_wall",      # Stalwart capital siege objective

	# ── Player-side near-duplicates ──────────────────────────────────────
	# Type keystones (2026-07-15) — stand-in art until bespoke paintings land.
	"bloodmoon_alpha":      "wolf_c",       # pack alpha borrows the distinct wolf
	"warden_sergeant":      "royal_guard",  # a line-holding sergeant
	"gravepact":            "corpse_eater", # grim dead, raises wights
	"coven_mother":         "archmage",     # Warlock keystone — the coven's head
	"siegewright":          "iron_bastion", # Bastion keystone — a great wall-engine
	"kingpin":              "sellsword",    # Stray keystone (Free Company Captain) — the crew's boss
	"deserter":             "skirmisher",   # Stray common — a soldier who ran
	# The four Part C tribe keystones (2026-07-30) — stand-ins until bespoke art
	# lands. Each borrows from its own tribe so the alias never crosses a tribe
	# line, which is the thing a shared stand-in most easily gets wrong.
	"pike_captain":         "royal_guard",  # Soldier keystone — the man who calls the volley
	"siege_bastion":        "iron_bastion", # Bastion keystone — the fortified works
	"the_magister":         "archmage",     # Warlock keystone — the coven's ledger-keeper
	"dire_alpha":           "wolf_c",       # Beast keystone — the pack's biggest wolf
	# THE BANNER's six levy cards (2026-07-31). These were the ONLY cards in any
	# hero's opener with no painting, which put all six blank sigils on the one
	# screen whose entire claim is "your colours add THIS card" — the card the
	# step exists to show was the only one that could not be seen. Each borrows
	# from inside its own tribe so the stand-in never crosses a tribe line.
	"line_marker":          "bannerman",    # Soldier — the man carrying the colours
	"loose_horse":          "hound",        # Beast — loosed and already running
	"ash_marker":           "gravedigger",  # Dead — the one who sets the markers
	"hedge_caster":         "witch",        # Warlock — the hedge-witch off the road
	"marker_stone":         "stone_wall",   # Bastion — a face cut into the works
	"free_lance":           "duelist",      # Stray — a lance nobody has paid for
	# COUNTERORDERS (2026-07-30) — both bodies are Strays who read the enemy's post.
	"order_breaker":        "skirmisher",   # the runner who breaks a committed line
	"the_interpreter":      "sellsword",    # the one who reads the foe's orders
	"sellsword_outrider":   "duelist",      # Stray uncommon — the dancing flanker
	# Rarity-floor vanillas (2026-07-16) — stand-ins until bespoke art lands.
	"man_at_arms":          "militia",
	"war_boar":             "e_bog_lurker",
	"grave_levy":           "e_bone_knight",
	"hexwright":            "crow_witch",
	"curtain_wall":         "hall_watcher",
	"freelance":            "mirror_knight",
	"bloodhound":           "hound",
	"warding_stone":        "stone_sentinel",  # own stone-golem art, not shared iron_bastion
	"crystal_sentry":       "sentinel",         # armored sentry fits better than a novice
	"glass_knight":         "duelist",
	"plague_rat":           "ratling",
	"basilisk":             "hydra",
	"cleave_hound":         "wolf_c",  # distinct wolf, not the shared hound face
	"revenant":             "vengeful_spirit",
	"riteforge":            "siege_golem",
	"hexblade":             "naga",
	"husk":                 "corpse_eater",
	"warchief":             "iron_bastion",
	"mana_sprite":          "sprite",
	"ironclad_veteran":     "pikeman",  # Old Campaigner — a soldier with a record
	"familiar":             "stray_cat",
	"vengeance":            "vengeful_spirit",
	"adaptable":            "sellsword",  # Sellsword — the on-the-nose merc painting
	"tallow_doll":          "copycat",
	"the_glutton":          "corpse_eater",
	"lancer":               "duelist",
	"shieldmaiden":         "royal_guard",
	"the_leveler":          "siege_golem",
	"the_apothecary":       "archmage",     # robed scholar-mage, not a generic witch
	"emberwright":          "ember_mystic",  # fire-mage, not a bow-archer
	"ember_warden":         "torchbearer",
	"old_bones":            "e_bone_knight",
	# Levy starters (2026-07-06) — plain bodies borrow their betters' faces.
	"levy_rider":           "ranger",  # Outrider — a hooded scout, not sharing Lookout's face
	"palisade":             "iron_bastion",
	"mourner":              "the_crone",  # grieving hooded figure, not sharing Gravedigger
	# Hero-retinue starters (2026-07-28); bespoke files auto-win later.
	"grasswake_lancer": "lancer",
	"trail_scout": "lookout",
	"rank_spearman": "pikeman",
	"wall_tender": "torchbearer",
	"standard_page": "bannerman",
	"grave_goods_levy": "gravedigger",
	"debt_guard": "e_dark_priest",
	"lens_apprentice": "witch",
	"mirror_guard": "mirror_knight",
	"glass_savant": "archmage",
	"fuse_tender": "ember_mystic",
	"cinderward": "ember_warden",
	"sin_eater":            "e_dark_priest",
	# 2026-07-07 fun slate — orphaned paintings put back to work.
	# (trebuchet.png exists outright, so Trebuchet needs no alias.)
	"volunteer":            "militia",
	"rat_piper":            "whisper_king",
	# 2026-07-13 stolen-classics slate (creatures; the slate's spells ride
	# SPELL_ALIASES below).
	"grave_clutch":         "corpse_eater",
	"pressed_man":          "militia",
	"the_undying":          "vengeful_spirit",
	# 2026-07-16 interest slate.
	"sword_on_credit":      "sellsword",
	"crew_mangonel":        "trebuchet",
	"pay_wagon":            "mule",
	"pallbearers":          "the_crone",
	"body_snatcher":        "gravedigger",
	"scapegoat":            "mule",
	"understudy":           "sellsword",
	"drill_serjeant":       "royal_guard",
	"wheeling_lancer":      "lancer",
	"rolling_tower":        "siege_golem",
	"hook_and_chain":       "iron_bastion",
	# Placeholder rescues — these had NO alias and rendered a blank gradient.
	"carrion_priest":       "risen_lich",   # Carrion Priest — undead death-priest
	"gravecaller":          "hall_watcher",  # Oathkeeper — armored oath-knight (own art, not Paladin's)
	"e_devil_champ":        "doom_knight",  # Devil's Champion — stopgap; wants bespoke devil art

	# ── Wolves / hounds ──────────────────────────────────────────────────
	"wolf":                 "hound",
	"dire_wolf":            "hound",
	"alpha":                "hound",
	"pup":                  "hound",
	"cub":                  "hound",
	"camp_mutt":            "hound",
	"cinder_pup":           "hound",
	"ash_hound":            "hound",
	"pack_wolf":            "hound",
	"alpha_wolf":           "hound",
	"den_mother":           "hound",
	"hellhound":            "e_brute",
	"houndmaster":          "e_enforcer",
	"pack-master":          "e_enforcer",
	"boar":                 "e_brute",
	"razorback":            "e_brute",
	"tusker":               "e_brute",
	"bristleback":          "e_brute",
	"charging_ram":         "e_brute",
	"bone-ram":             "e_brute",
	"sow":                  "mule",
	"piglet":               "ratling",
	"yearling":             "mule",
	"yearling_boar":        "mule",

	# ── Bandits / scouts / rogues ────────────────────────────────────────
	"goblin_scout":         "e_scout",
	"runt":                 "e_goblin",
	"bandit":               "assassin",
	"thug":                 "sellsword",
	"cutpurse":             "scavenger",
	"plunderer":            "scavenger",
	"looter":               "scavenger",
	"sneak":                "assassin",
	"saboteur":             "assassin",
	"flanker":              "assassin",
	"stalker":              "assassin",
	"ember_stalker":        "blood_pyre",  # Powder Cart — a pyre about to blow
	"archer":               "e_archer",
	"sharpshooter":         "e_archer",
	"crossbowman":          "e_archer",
	"crossbow_guard":       "e_archer",
	"crossbow_knight":      "e_archer",
	"crossbow_lady":        "e_archer",
	"slinger":              "e_archer",
	"ember_sniper":         "e_archer",
	"acolyte_sniper":       "e_archer",
	"bombardier":           "e_archer",
	"captain":              "royal_guard",
	"bandit_captain":       "royal_guard",
	"sellsword":            "berserker",  # legacy art alias
	"brawler":              "berserker",
	"recruit":              "shieldbearer",
	"footman":              "shieldbearer",
	"squire":               "shieldbearer",
	"veteran":              "pikeman",
	"lieutenant":           "squire_captain",
	"standard_bearer":      "bannerman",  # the actual standard-bearer painting
	"banner-bearer":        "royal_guard",
	"hall-watcher":         "royal_guard",
	"fallen_knight":        "e_bone_knight",
	"fallen_paladin":       "paladin",
	"black_lancer":         "doom_knight",
	"forsworn_champion":    "doom_knight",
	"shadow_blade":         "assassin",

	# ── Plants / fungi / swamp ───────────────────────────────────────────
	"sprout":               "thornguard",
	"spore_beast":          "hydra",
	"spore":                "thornguard",
	"mycelium":             "hydra",
	"mire_beast":           "e_bog_lurker",
	"mire_druid":           "witch",
	"bog_beast":            "e_bog_lurker",
	"bog_slime":            "e_bog_lurker",
	"bog_tendril":          "naga",
	"tendril":              "naga",
	"leech":                "naga",
	"swamp_hag":            "witch",
	"hydra_spawn":          "hydra",
	"thornveil":            "thornguard",
	"bloom_husk":           "thornguard",
	"cap_lasher":           "thornguard",
	"anglerfish":           "naga",
	"deepling":             "naga",
	"tentacle":             "naga",
	"mosquito":             "sprite",
	"drowned":              "e_bog_lurker",
	"tide_spawn":           "naga",
	"tide_sprite":          "sprite",

	# ── Stone / iron / siege constructs ──────────────────────────────────
	"rock_hurler":          "e_golem",
	"stone_hurler":         "e_golem",
	"granite_guard":        "shieldbearer",
	"fragment":             "e_golem",
	"flame_golem":          "e_fire_elemental",
	"forge_guardian":       "royal_guard",
	"forgeling":            "e_golem",
	"slag_heap":            "e_golem",
	"ice_elemental":        "royal_guard",
	"earth_elemental":      "e_golem",
	"stone_sprite":         "e_golem",
	"pebble":               "e_golem",
	"earthshaker":          "siege_golem",
	"nexus_core":           "siege_golem",
	"elemental_nexus":      "siege_golem",
	"iron_sentinel":        "iron_bastion",
	"iron_maiden":          "iron_bastion",
	"iron_guard":           "shieldbearer",
	"iron_vanguard":        "e_enforcer",
	"iron_recruit":         "shieldbearer",
	"siege_engine":         "siege_golem",
	"wardens_champion":     "e_warden_champ",
	"display_case":         "royal_guard",
	"trinket":              "leyline_conduit",
	"glass_shard":          "leyline_conduit",
	"glass_sniper":         "e_archer",
	"temple_guardian":      "royal_guard",
	"shard":                "leyline_conduit",
	"collector_golem":      "siege_golem",
	"stone_sentinels":      "shieldbearer",
	"bastion":              "iron_bastion",
	"coal_hulk":            "e_golem",
	"coal_carrier":         "ratling",
	"char-hide":            "e_brute",

	# ── Harpies / flyers ─────────────────────────────────────────────────
	"matron":               "harpy",
	"mother_harpy":         "harpy",
	"brood_harpy":          "harpy",
	"flock_whisperer":      "harpy",
	"egg_mother":           "harpy",
	"chick":                "e_wind_harpy",
	"fledgling":            "e_wind_harpy",
	"storm_harpy":          "e_wind_harpy",
	"wind_harpy":           "e_wind_harpy",
	# Renamed 2026-08-06 (the painting was always an owl, never a harpy). These
	# are NAME-derived keys, so the authored EncounterDB body that now reads
	# "Storm Owl" keeps its portrait; the old key stays for legacy saves.
	"storm_owl":            "e_wind_harpy",
	"sky_stalker":          "griffin",
	"crow":                 "raven",
	"smoldering_crow":      "raven",
	"scrap_crow":           "raven",

	# ── Orcs / warriors ──────────────────────────────────────────────────
	"warrior":              "berserker",
	"drummer":              "ratling",
	"chieftain":            "e_brute",
	"chief":                "e_brute",
	"quarry_brute":         "e_brute",
	"hammerer":             "e_enforcer",
	"grunt":                "sellsword",

	# ── Skeletons / liches / undead ──────────────────────────────────────
	"skeleton":             "e_bone_knight",
	"bone_knight":          "e_bone_knight",
	"bone_walker":          "e_bone_knight",
	"bone_crone":           "witch",
	"bone_dragon":          "e_elder_dragon",
	"skeleton_knight":      "doom_knight",
	"risen_skeleton":       "e_bone_knight",
	"lich":                 "necromancer",
	"lichs_hand":           "warden_of_graves",
	"lich_acolyte":         "e_dark_priest",
	"dark_acolyte":         "e_cultist",
	"risen_bones":          "e_bone_knight",
	"risen":                "vengeful_spirit",
	"phylactery":           "warden_of_graves",
	"crypt_spider":         "corpse_eater",
	"mourner_knight":       "e_bone_knight",
	"marrow_knight":        "e_bone_knight",

	# ── Cultists ─────────────────────────────────────────────────────────
	"zealot":               "e_cultist",
	"fanatic":              "e_cultist",
	"initiate":             "e_cultist",
	"devotee":              "e_cultist",
	"chanter":              "e_cultist",
	"ritual_acolyte":       "e_dark_priest",
	"pyre_acolyte":         "e_dark_priest",
	"cinder_acolyte":       "e_dark_priest",
	"dark_priest":          "e_dark_priest",
	# Renamed 2026-08-06. name_id lowercases and swaps spaces only, so the key
	# for "Candle-Priest" keeps its hyphen — do not "tidy" it to an underscore
	# or the authored EncounterDB bodies fall back to the fire placeholder.
	"candle-priest":        "e_dark_priest",
	"cantor":               "e_dark_priest",
	"burning_martyr":       "torchbearer",
	"kindler":              "torchbearer",
	"hymn_bearer":          "royal_guard",
	"inquisitor":           "paladin",
	"witch_doctor":         "witch",
	"hexer":                "witch",
	"court_hexer":          "witch",
	"geomancer":            "witch",

	# ── Dragons ──────────────────────────────────────────────────────────
	"wyrm":                 "e_drake",
	"ancient_wyrm":         "e_elder_dragon",
	"whelp":                "dragon_hatchling",
	"hatchling":            "dragon_hatchling",
	"elder_drake":          "e_elder_dragon",
	"lava_drake":           "e_drake",
	"dragon_lord":          "e_elder_dragon",
	"fire_giant":           "siege_golem",

	# ── Ghosts / spirits / hollow ────────────────────────────────────────
	"wraith":               "vengeful_spirit",
	"banshee":              "witch",
	"specter":              "vengeful_spirit",
	"shade":                "vengeful_spirit",
	"pale_handmaid":        "vengeful_spirit",
	"gravewarden":          "warden_of_graves",
	"hollow_knight":        "doom_knight",
	"hollow_champion":      "e_warden_champ",
	"void_guard":           "royal_guard",
	"shade_knight":         "e_bone_knight",
	"soul_reaper":          "e_headsman",
	"soul_drinker":         "vampire_lord",
	"whisper-king":         "necromancer",

	# ── Demons / hellfire ────────────────────────────────────────────────
	"demon_soldier":        "e_enforcer",
	"demon_vanguard":       "e_enforcer",
	"pit_fiend":            "e_devil_champ",
	"infernal":             "e_devil_champ",
	"tormentor":            "e_devil_champ",
	"imp":                  "chaos_imp",
	"hellfire_imp":         "chaos_imp",
	"devils_champion":      "e_devil_champ",
	"lesser_demon":         "chaos_imp",
	"cinder":               "torchbearer",
	"cinder_sprite":        "sprite",
	"ember":                "kindling",
	"fire_elemental":       "e_fire_elemental",
	"storm_elemental":      "e_fire_elemental",
	"conflagrant":          "e_fire_elemental",
	"pyro":                 "e_fire_elemental",
	"pyromancer":           "witch",
	"ash_master":           "witch",
	"spark":                "sprite",
	"flame_sprite":         "sprite",
	"ice_sprite":           "sprite",
	"shadow_sprite":        "sprite",
	"storm_sprite":         "sprite",

	# ── Executioners ─────────────────────────────────────────────────────
	"torturer":             "e_headsman",
	"executioner":          "e_headsman",
	"jailer":               "e_headsman",
	"whipman":              "e_headsman",
	"condemned":            "corpse_eater",
	"bound_prisoner":       "corpse_eater",

	# ── Puppets / mirrors / doubles ──────────────────────────────────────
	"marionette":           "doppelganger",
	"puppet_knight":        "mirror_knight",
	"shadow_double":        "doppelganger",
	"puppeteers_guard":     "mirror_knight",
	"string":               "leyline_conduit",
	"string_wraith":        "vengeful_spirit",
	"reflection":           "copycat",
	"doppel":               "doppelganger",
	"echo_twin":            "copycat",
	"shattered_twin":       "copycat",
	"mirror_wisp":          "sprite",

	# ── Void / collector ─────────────────────────────────────────────────
	"void_spawn":           "vengeful_spirit",
	"rift_stalker":         "naga",
	"null_beast":           "corpse_eater",
	"void_maw":             "hydra",
	"soul_cage":            "warden_of_graves",
	"collectors_pride":     "siege_golem",
	"collectors_champion":  "e_collector_champ",
	"hoard_guardian":       "siege_golem",

	# ── Scarecrow / farm ─────────────────────────────────────────────────
	"scarecrow":            "gravedigger",
	"straw_man":            "gravedigger",
	"mad_shepherd":         "gravedigger",
	"field_mouse":          "ratling",
	"stray_lamb":           "mule",
	"maggot-lamb":          "corpse_eater",
	"pumpkin_head":         "troll",

	# ── Court / noble / music ────────────────────────────────────────────
	"court_jester":         "ratling",
	"court_mourner":        "e_dark_priest",
	"apprentice":           "lookout",
	"conductor":            "witch",
	"maestro":              "witch",
	"soprano":              "summoner",
	"tenor":                "berserker",
	"hummer":               "ratling",
	"withered_king":        "necromancer",
	"bleeding_heart":       "blood_pyre",
	"bloodfang":            "vampire_lord",

	# ── Misc named creatures ─────────────────────────────────────────────
	"camp_follower":        "lookout",
	"mercenary_company":    "shieldbearer",
	"stitched_hand":        "corpse_eater",
	"puffer":               "thornguard",
	"spawn":                "e_goblin",
	"kobold_hurler":        "e_goblin",

	# ── Successor Wars rival kits (named per kingdom's island age) ───────
	"outrider":             "e_scout",
	"rider":                "e_scout",
	"salt_harpy":           "e_wind_harpy",
	"wake_hound":           "hound",
	"pennon_griffin":       "griffin",
	"first_ashore":         "e_brute",
	"centurion":            "royal_guard",
	"eagle-bearer":         "royal_guard",
	"first_spear":          "e_enforcer",
	"tithe_collector":      "e_dark_priest",
	"furnace_altar":        "blood_pyre",
	"debtor":               "e_bone_knight",
	"collateral":           "e_bone_knight",
	"furnace_priest":       "e_dark_priest",
	"vault_warden":         "warden_of_graves",
	"repossessed":          "vengeful_spirit",
	"paid_in_full":         "e_collector_champ",
	"star-reader":          "summoner",
	"claw_adept":           "e_cultist",
	"burning_glass":        "e_archer",
	"ink_beast":            "corpse_eater",
	"cold_lector":          "e_dark_priest",
	"glass_sentinel":       "mirror_knight",
	"siphon_imp":           "chaos_imp",
	"pitch_hulk":           "e_golem",
	"pyre_tender":          "torchbearer",

	# ── 2026-08-28 placeholder sweep ─────────────────────────────────────
	# tools/_probe_card_art.tscn found 16 PLAYABLE cards resolving to the
	# line-art stand-in — a blank writ with a thin gold glyph on it, which in a
	# shop row beside four paintings reads as unfinished art rather than as a
	# card. Stand-ins until bespoke paintings land; each is chosen for what the
	# card IS, not just for its tribe, so none of them reads as a wrong picture.
	"bastion_lord":         "scholar",          # the Tally Man keeps the count
	"bramble_stockade":     "thornguard",       # a wall made of thorns
	"grave_goods":          "gravedigger",      # what is buried with them
	"heartwood_elder":      "troll",            # the Herd Bull — the big body
	"ironhide_anvil":       "iron_bastion",     # Iron Rampart, a great wall
	"last_levy":            "militia",          # the Last Recruit is a levy
	"pike_square":          "pikeman",          # the formation, from its man
	"the_sexton":           "warden_of_graves", # a sexton IS the grave's warden
}

## These are strong-reference caches, so an entry keeps the decoded texture in
## memory even after the card/scene that requested it is gone. Keep enough art
## for a deck plus the current encounter, but do not let a Collection visit or
## a long run pin the entire library. Eviction only removes these references;
## Card2D/TextureRect nodes already using a Texture2D retain their own reference.
const MAX_CREATURE_ART_ENTRIES := 48
const MAX_SPELL_ART_ENTRIES := 32
const MAX_THREADED_PATH_ENTRIES := 48

static var _creature_art_cache: Dictionary = {}
static var _creature_art_lru: Array[String] = []
static var _spell_art_cache: Dictionary = {}
static var _spell_art_lru: Array[String] = []
# Shared threaded path loader used by transition/card warmers. Keeping the
# resource reference here both de-duplicates alias requests and pins decoded
# textures so the later synchronous Card2D lookup is a cheap cache hit.
static var _threaded_path_cache: Dictionary = {}
static var _threaded_path_lru: Array[String] = []
static var _threaded_path_busy: Dictionary = {}


static func _touch_lru(order: Array[String], key: String) -> void:
	order.erase(key)
	order.append(key)


static func _remember_creature_art(card_id: String, tex: Texture2D) -> void:
	_creature_art_cache[card_id] = tex
	_touch_lru(_creature_art_lru, card_id)
	while _creature_art_cache.size() > MAX_CREATURE_ART_ENTRIES \
			and not _creature_art_lru.is_empty():
		var oldest: String = _creature_art_lru.pop_front()
		_creature_art_cache.erase(oldest)


static func _remember_spell_art(card_id: String, tex: Texture2D) -> void:
	_spell_art_cache[card_id] = tex
	_touch_lru(_spell_art_lru, card_id)
	while _spell_art_cache.size() > MAX_SPELL_ART_ENTRIES \
			and not _spell_art_lru.is_empty():
		var oldest: String = _spell_art_lru.pop_front()
		_spell_art_cache.erase(oldest)


static func _remember_texture_path(path: String, tex: Texture2D) -> void:
	_threaded_path_cache[path] = tex
	_touch_lru(_threaded_path_lru, path)
	_trim_threaded_path_cache()


static func _trim_threaded_path_cache() -> void:
	# A path may briefly be both pinned and busy when another subsystem joined
	# its ResourceLoader request. Never discard that rendezvous point mid-load.
	var remaining := _threaded_path_lru.size()
	while _threaded_path_cache.size() > MAX_THREADED_PATH_ENTRIES \
			and remaining > 0 and not _threaded_path_lru.is_empty():
		var oldest: String = _threaded_path_lru.pop_front()
		if _threaded_path_busy.has(oldest):
			_threaded_path_lru.append(oldest)
			remaining -= 1
			continue
		_threaded_path_cache.erase(oldest)
		remaining = _threaded_path_lru.size()


static func clear_runtime_caches() -> void:
	# Collection can touch nearly every painting in one visit. Once its card
	# nodes are gone, release those strong references so the ResourceLoader is
	# free to reclaim them; run/map warmers repopulate only what play needs.
	_creature_art_cache.clear()
	_creature_art_lru.clear()
	_spell_art_cache.clear()
	_spell_art_lru.clear()
	_threaded_path_cache.clear()
	_threaded_path_lru.clear()
	# Do not cancel genuine in-flight requests. They erase themselves on land;
	# clearing only completed resources is enough for the gallery-exit path.


static func release_texture_path(path: String) -> void:
	# ResourceLoader keeps its own weak cache; this dictionary is the strong pin
	# owned by our warmers. Dropping it lets one-off event art leave with its scene.
	if path != "" and not _threaded_path_busy.has(path):
		_threaded_path_cache.erase(path)
		_threaded_path_lru.erase(path)


static func release_card_art(card_data: Dictionary) -> void:
	# Gallery hydration only needs the source painting until its flattened card
	# texture is captured. Release every lookup spelling used by prewarm_card_art
	# so scrolling the full compendium does not retain the whole art library.
	var cid := String(card_data.get("id", ""))
	var name_id := String(card_data.get("name", "")).to_lower() \
		.replace(" ", "_").replace("'", "")
	if String(card_data.get("type", "creature")) in ["spell", "armament"]:
		_release_spell_art_key(cid)
		_release_spell_art_key(name_id)
	else:
		_release_creature_art_key(cid)
		_release_creature_art_key(name_id)
		_release_creature_art_key("e_" + name_id if name_id != "" else "")


static func _release_creature_art_key(card_id: String) -> void:
	if card_id == "":
		return
	_creature_art_cache.erase(card_id)
	_creature_art_lru.erase(card_id)
	release_texture_path("res://assets/creatures/%s.png" % card_id)
	release_texture_path("res://assets/creatures/%s.jpg" % card_id)
	if ALIASES.has(card_id):
		var alias_id := String(ALIASES[card_id])
		release_texture_path("res://assets/creatures/%s.png" % alias_id)
		release_texture_path("res://assets/creatures/%s.jpg" % alias_id)


static func _release_spell_art_key(card_id: String) -> void:
	if card_id == "":
		return
	_spell_art_cache.erase(card_id)
	_spell_art_lru.erase(card_id)
	release_texture_path("res://assets/spells/%s.png" % card_id)
	if SPELL_ALIASES.has(card_id):
		release_texture_path(
			"res://assets/spells/%s.png" % String(SPELL_ALIASES[card_id]))


static func prewarm_texture_path(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _threaded_path_cache.has(path):
		_touch_lru(_threaded_path_lru, path)
		return _threaded_path_cache[path] as Texture2D
	if ResourceLoader.has_cached(path):
		var cached := load(path) as Texture2D
		_remember_texture_path(path, cached)
		return cached
	while _threaded_path_busy.has(path):
		var wait_tree := Engine.get_main_loop() as SceneTree
		if wait_tree == null:
			return null
		await wait_tree.process_frame
		if _threaded_path_cache.has(path):
			_touch_lru(_threaded_path_lru, path)
			return _threaded_path_cache[path] as Texture2D
	_threaded_path_busy[path] = true
	var tex: Texture2D = null
	var err := ResourceLoader.load_threaded_request(path, "Texture2D")
	# Another subsystem (notably ScenePreload) may already own the request. In
	# that case load_threaded_request reports busy, but the shared loader status
	# is still pollable; join that request instead of falling back to a blocking
	# load on the transition frame.
	var status := ResourceLoader.load_threaded_get_status(path)
	if err == OK or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
			or status == ResourceLoader.THREAD_LOAD_LOADED:
		var tree := Engine.get_main_loop() as SceneTree
		while tree != null and status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
			status = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			tex = ResourceLoader.load_threaded_get(path) as Texture2D
	if tex == null and ResourceLoader.has_cached(path):
		tex = load(path) as Texture2D
	if tex == null:
		# Rare loader rejection (unsupported importer/request state). Preserve the
		# old graceful behavior rather than turning missing art into a hard error.
		tex = load(path) as Texture2D
	_threaded_path_busy.erase(path)
	_remember_texture_path(path, tex)
	return tex


## Every file `prewarm_card_art` could resolve this card to, in the exact order
## it would try them. Exposed so a caller can pre-resolve a whole roster.
static func card_art_candidates(card_data: Dictionary) -> Array[String]:
	var cid := String(card_data.get("id", ""))
	var name_id := String(card_data.get("name", "")).to_lower() \
		.replace(" ", "_").replace("'", "")
	var out: Array[String] = []
	if String(card_data.get("type", "creature")) in ["spell", "armament"]:
		for k in [cid, name_id]:
			if k == "":
				continue
			out.append("res://assets/spells/%s.png" % k)
			if SPELL_ALIASES.has(k):
				out.append("res://assets/spells/%s.png" % String(SPELL_ALIASES[k]))
		return out
	var keys: Array[String] = [cid, name_id]
	if name_id != "":
		keys.append("e_" + name_id)
	for k in keys:
		if k == "":
			continue
		out.append("res://assets/creatures/%s.png" % k)
		out.append("res://assets/creatures/%s.jpg" % k)
		if ALIASES.has(k):
			var alias := String(ALIASES[k])
			out.append("res://assets/creatures/%s.png" % alias)
			out.append("res://assets/creatures/%s.jpg" % alias)
	return out


## The ONE painting this card will actually resolve to, or "" if it has none.
static func card_art_path(card_data: Dictionary) -> String:
	for path in card_art_candidates(card_data):
		if ResourceLoader.exists(path):
			return path
	return ""


## Decode a whole list of paintings in PARALLEL: fire every ResourceLoader
## request first, then join them. The serial shape (`for p in paths: await
## prewarm_texture_path(p)`) pays a full main-thread round trip per file — with
## a fight's roster that was ~400 ms of blank table before anything got built,
## while the loader's worker pool sat mostly idle.
static func prewarm_texture_paths(paths: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var requested: Array[String] = []
	for path_v in paths:
		var path := String(path_v)
		if path == "" or requested.has(path):
			continue
		if _threaded_path_cache.has(path) or _threaded_path_busy.has(path):
			continue
		if not ResourceLoader.exists(path) or ResourceLoader.has_cached(path):
			continue
		if ResourceLoader.load_threaded_request(path, "Texture2D") != OK:
			continue
		# Claim it so a concurrent prewarm_texture_path joins our request via its
		# busy-wait instead of issuing a competing one.
		_threaded_path_busy[path] = true
		requested.append(path)
	for path in requested:
		while ResourceLoader.load_threaded_get_status(path) \
				== ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
		var tex: Texture2D = null
		if ResourceLoader.load_threaded_get_status(path) \
				== ResourceLoader.THREAD_LOAD_LOADED:
			tex = ResourceLoader.load_threaded_get(path) as Texture2D
		if tex == null:
			# Same graceful fallback prewarm_texture_path keeps: a loader
			# rejection becomes a plain load, never a missing painting.
			tex = load(path) as Texture2D
		_threaded_path_busy.erase(path)
		_remember_texture_path(path, tex)


static func prewarm_creature_art(card_id: String) -> Texture2D:
	if _creature_art_cache.has(card_id):
		_touch_lru(_creature_art_lru, card_id)
		return _creature_art_cache[card_id] as Texture2D
	var paths: Array[String] = [
		"res://assets/creatures/%s.png" % card_id,
		"res://assets/creatures/%s.jpg" % card_id,
	]
	if ALIASES.has(card_id):
		var alias_id: String = ALIASES[card_id]
		paths.append("res://assets/creatures/%s.png" % alias_id)
		paths.append("res://assets/creatures/%s.jpg" % alias_id)
	var tex: Texture2D = null
	for path in paths:
		tex = await prewarm_texture_path(path)
		if tex != null:
			break
	_remember_creature_art(card_id, tex)
	return tex


static func prewarm_spell_art(card_id: String) -> Texture2D:
	if _spell_art_cache.has(card_id):
		_touch_lru(_spell_art_lru, card_id)
		return _spell_art_cache[card_id] as Texture2D
	var paths: Array[String] = ["res://assets/spells/%s.png" % card_id]
	if SPELL_ALIASES.has(card_id):
		paths.append("res://assets/spells/%s.png" % SPELL_ALIASES[card_id])
	var tex: Texture2D = null
	for path in paths:
		tex = await prewarm_texture_path(path)
		if tex != null:
			break
	_remember_spell_art(card_id, tex)
	return tex


static func prewarm_card_art(card_data: Dictionary) -> Texture2D:
	var cid := String(card_data.get("id", ""))
	var name_id := String(card_data.get("name", "")).to_lower() \
		.replace(" ", "_").replace("'", "")
	var tex: Texture2D = null
	if String(card_data.get("type", "creature")) in ["spell", "armament"]:
		tex = await prewarm_spell_art(cid)
		if tex == null and name_id != "":
			tex = await prewarm_spell_art(name_id)
	else:
		tex = await prewarm_creature_art(cid)
		if tex == null and name_id != "":
			tex = await prewarm_creature_art(name_id)
		if tex == null and name_id != "":
			tex = await prewarm_creature_art("e_" + name_id)
	return tex


static func try_load_creature_art(card_id: String) -> Texture2D:
	if _creature_art_cache.has(card_id):
		_touch_lru(_creature_art_lru, card_id)
		return _creature_art_cache[card_id] as Texture2D
	var tex: Texture2D = null
	# Direct PNG first.
	var path = "res://assets/creatures/%s.png" % card_id
	if ResourceLoader.exists(path):
		tex = load(path)
	# Direct JPG if PNG didn't exist OR loaded as null (broken import).
	# Previously this only ran when the PNG didn't exist — a corrupt
	# pikeman.png (`valid=false` import) would short-circuit to tex=null
	# and skip both the JPG fallback AND the alias fallback, rendering a
	# black art window. Now we treat "loaded but null" the same as "no file."
	if tex == null:
		var jpg_path = "res://assets/creatures/%s.jpg" % card_id
		if ResourceLoader.exists(jpg_path):
			tex = load(jpg_path)
	# Alias fallback — same rule: try the alias if the direct files didn't
	# produce a usable texture. This lets a broken master file fall through
	# to a soldier/beast/etc. stand-in instead of a placeholder rectangle.
	if tex == null and ALIASES.has(card_id):
		var alias_target: String = ALIASES[card_id]
		var alias_png := "res://assets/creatures/%s.png" % alias_target
		if ResourceLoader.exists(alias_png):
			tex = load(alias_png)
		if tex == null:
			var alias_jpg := "res://assets/creatures/%s.jpg" % alias_target
			if ResourceLoader.exists(alias_jpg):
				tex = load(alias_jpg)
	_remember_creature_art(card_id, tex)
	return tex


# Spell-art stand-ins, same idea as the creature ALIASES above: a spell id
# with no bespoke painting borrows a cousin's until its own art lands. The
# bespoke file auto-wins once it exists (direct path is tried first).
const SPELL_ALIASES: Dictionary = {
	# 2026-09-17 cost-5 payoff slate (randomness tier).
	"powder_store":        "cataclysm",
	"case_shot":           "petard",
	"press_gang":          "war_chant",
	"craven": "curse",
	"deserters_mark": "curse",
	"war_debt": "curse",
	"grave_debt": "wound",
	"spur_forward": "charge_spell",
	"cut_them_off": "smite_spell",
	"close_ranks_order": "patch_up",
	"read_the_will": "grave_robbery",
	"last_due": "fuel_the_pyre",
	"star_chart": "lost_tome",
	"countermarch_levy": "adrenaline",
	"touchpaper": "turbo",
	# Penance (card id reckless_charge) — the old cavalry-charge painting moved
	# to assets/_unused; Offering's somber art fits the sin-burning.
	"reckless_charge": "offering",
	"mark_of_ash": "hex",
	# Spark (levy starter) — the orphaned lightning painting (its spell id
	# died in the 2026-07-02 overhaul) is exactly a small zap.
	"spark": "lightning",
	# 2026-07-07 fun slate.
	"petard": "ricochet",
	"slow_match": "flame_bolt",
	"muster_fallen": "reanimate",
	# 2026-07-09 removal slate — all three borrow orphaned paintings (their card
	# ids died in earlier overhauls, so no live card shares these faces).
	"sappers_charge": "barricade",     # a powder magazine going up
	"ballista_bolt": "reposition",     # a bolt of force slamming into a body
	"scatter_line": "second_wind",     # the howling gale that scatters them
	# 2026-07-13 stolen-classics slate.
	"long_roll": "lost_tome",          # the roll of names, read as a book
	"wolf_pits": "ambush",             # death waiting under cover
	"informer": "inspire",             # Turncoat's bought-man painting, reshared
	"forgefire": "scrap",              # orphaned smith-pile painting
	# 2026-07-16 interest slate.
	"gallows_writ": "banish",
	"salted_ground": "ambush",
	"mentioned_dispatches": "charge_spell",
	"crossed_orders": "soul_swap",
	"flanking_order": "reposition",
	# Armaments use item/action paintings until bespoke equipment art lands.
	"hooked_pike": "venom_tip",
	"tower_shield": "shield_wall",
	"grave_bell": "plague_bell",
	"witchbrand": "hex",
	"forked_spear": "cataclysm",
	"repeating_arbalest": "reposition",

	# ── 2026-08-28 placeholder sweep (see the ALIASES twin) ──────────────
	# Only two: every ARMAMENT already had an entry a few lines up. The first
	# sweep reported six of them as artless because its probe ran the spell
	# loader for type "spell" only — _find_card_art runs it for `is_spell() OR
	# is_armament()`. Re-adding them here was a DUPLICATE KEY, which is a parse
	# error, which is how the mistake surfaced.
	"close_ranks":          "charge_spell",     # The Pincer — both flanks in
	"counterorders":        "kings_command",    # countermanding an order
}


static func try_load_spell_art(card_id: String) -> Texture2D:
	if _spell_art_cache.has(card_id):
		_touch_lru(_spell_art_lru, card_id)
		return _spell_art_cache[card_id] as Texture2D
	var tex: Texture2D = null
	var path = "res://assets/spells/%s.png" % card_id
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null and SPELL_ALIASES.has(card_id):
		var alias_path = "res://assets/spells/%s.png" % SPELL_ALIASES[card_id]
		if ResourceLoader.exists(alias_path):
			tex = load(alias_path)
	_remember_spell_art(card_id, tex)
	return tex
