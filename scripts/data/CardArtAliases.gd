class_name CardArtAliases
## Maps creature ids that don't have dedicated art to ids that DO have art.
## Centralised here so adding a new enemy creature doesn't require touching
## GameTheme — just point its id at an existing portrait.
##
## Loaders memoize their lookups in static caches (negative hits cached too),
## since Card2D probes up to 5 ids per layout build and each probe used to
## fire 2-3 ResourceLoader.exists() stats.

const ALIASES: Dictionary = {
	# ── Player-side near-duplicates ──────────────────────────────────────
	"bloodhound":           "hound",
	"warding_stone":        "iron_bastion",
	"crystal_sentry":       "shieldbearer",
	"glass_knight":         "duelist",
	"plague_rat":           "ratling",
	"basilisk":             "hydra",
	"cleave_hound":         "hound",
	"revenant":             "vengeful_spirit",
	"riteforge":            "siege_golem",
	"hexblade":             "naga",
	"husk":                 "corpse_eater",
	"warchief":             "iron_bastion",
	"mana_sprite":          "sprite",
	"stone_wall":           "iron_bastion",
	"ironclad_veteran":     "iron_bastion",
	"familiar":             "stray_cat",
	"vengeance":            "vengeful_spirit",
	"adaptable":            "mirror_knight",

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
	"ember_stalker":        "assassin",
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
	# Fallback for Pikeman itself: the master pikeman.png is currently
	# corrupted (Godot logs "Error loading image" on import). Until a
	# clean PNG is dropped in, fall back to the shieldbearer portrait so
	# the card has SOME soldier-tribe art instead of a black window.
	# Direct-load fails → loader now retries via this alias.
	"pikeman":              "shieldbearer",
	"lieutenant":           "squire_captain",
	"standard_bearer":      "royal_guard",
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
}

static var _creature_art_cache: Dictionary = {}
static var _spell_art_cache: Dictionary = {}


static func try_load_creature_art(card_id: String) -> Texture2D:
	if _creature_art_cache.has(card_id):
		return _creature_art_cache[card_id]
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
	_creature_art_cache[card_id] = tex
	return tex


static func try_load_spell_art(card_id: String) -> Texture2D:
	if _spell_art_cache.has(card_id):
		return _spell_art_cache[card_id]
	var tex: Texture2D = null
	var path = "res://assets/spells/%s.png" % card_id
	if ResourceLoader.exists(path):
		tex = load(path)
	_spell_art_cache[card_id] = tex
	return tex
