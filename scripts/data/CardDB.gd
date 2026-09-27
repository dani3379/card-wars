extends Node
## CardDB.gd — all card definitions: 12 starter (incl. the levy set) + the
## draft pool (common/uncommon/rare) + enemy creatures + tokens/curses.
##
## Card schema:
##   id, name, type ("creature"/"spell"/"armament"), cost, rarity ("starter"/"common"/"uncommon"/"rare"/"enemy")
##   Creature: atk, hp, keywords, desc, and optional: on_enter, on_death, on_play, adj_buff, wither, passive
##   on_play: {"type": "...", "value": X, ...} is an instant battlecry that fires when the creature is placed
##   Spell: keywords, desc, spell {type, value, ...}, targeting
##     ("enemy_creature"/"friendly_creature"/"any_creature"/"any"/"lane"/
##      "friendly_then_enemy"/"two_enemies"/"friendly_lane"/"none")
##   Armament: keywords, desc, armament {atk, hp, keywords, effect, icon}, targeting "friendly_creature"

const CARD_POOL: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTER CARDS — 10-card deck: 4 Peasant, 4 Soldier, 1 Squire, 1 Footman
	# ═══════════════════════════════════════════
	"goblin": {"id": "goblin", "name": "Camp Cur", "type": "creature", "ctype": "beast", "cost": 2, "atk": 2, "hp": 1,
		"rarity": "starter", "keywords": ["on_enter"], "desc": "On-Enter: deal 1 damage to enemy face.",
		"on_enter": {"type": "damage_face", "value": 1}},
	"brute": {"id": "brute", "name": "Goring Boar", "type": "creature", "ctype": "beast", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["on_enter"], "desc": "On-Enter: deal 1 damage to the opposing creature.",
		"on_enter": {"type": "damage_opposing", "value": 1}},
	"troll": {"id": "troll", "name": "Scarback", "type": "creature", "ctype": "beast", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["regenerate"], "desc": "Regenerate."},
	"sprite": {"id": "sprite", "name": "Gamecock", "type": "creature", "ctype": "beast", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "starter", "keywords": [], "desc": "When played: adjacent friendlies get +1 ATK this round.",
		"on_play": {"type": "buff_adjacent_atk", "value": 1}},
	"naga": {"id": "naga", "name": "Baited Bear", "type": "creature", "ctype": "beast", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "starter", "keywords": [], "desc": "When played: deal 2 damage to the opposing creature.",
		"on_play": {"type": "damage_opposing", "value": 2}},
	"ratling": {"id": "ratling", "name": "Fever Rat", "type": "creature", "ctype": "beast", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "starter", "keywords": ["wither", "on_death"], "wither": 1,
		"desc": "Wither 1. On-Death: deal 1 damage to the opposing lane.",
		"on_death": {"type": "damage_opposing_lane", "value": 1}},
	"strike": {"id": "strike", "name": "Run Through", "type": "spell", "cost": 2,
		"rarity": "starter", "keywords": [], "desc": "Deal 3 damage to a creature.",
		"spell": {"type": "damage", "value": 3}, "targeting": "any_creature"},
	# Fireball was mustered out of every opener 2026-07-21 — an unconditional
	# face spell asks no question at cast time (no target, no timing, no board
	# read), and openers are the most-played cards in the game. Don't re-seat
	# it in a hero deck as-is; if it returns, rework it to earn face through
	# the board (lane shot with excess-to-face, a price, or a kill condition).
	"fireball": {"id": "fireball", "name": "Firepot", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 2 damage to enemy face.",
		"spell": {"type": "damage_face", "value": 2}, "targeting": "none", "scope": "ENEMY FACE"},

	# ── Levy starters (2026-07-06 progression pass) — deliberately PLAIN, a
	# notch below the pool's commons. Hero decks are built ONLY from starter-
	# rarity cards now, so every drafted pool card is a visible upgrade over
	# what the march began with (the StS starter contract: nothing in your
	# opening deck should outrank what the road offers).
	# Playability floor (2026-07-21): under simultaneous clash a starter body
	# must still clear the trade floor (ATK >= 2 kills the standard 2-HP chaff)
	# or the block floor (HP >= 3 survives a 2-ATK hit) — the 1/2 statline does
	# neither and is banned from starters. Weak stays legal; useless doesn't.
	"levy_rider": {"id": "levy_rider", "name": "Outrider", "type": "creature", "ctype": "soldier", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "starter", "keywords": ["swift"], "desc": "Swift."},
	"palisade": {"id": "palisade", "name": "Palisade", "type": "creature", "ctype": "soldier", "cost": 1, "atk": 0, "hp": 4,
		"rarity": "starter", "keywords": ["guardian"], "desc": "Guardian."},
	"mourner": {"id": "mourner", "name": "Mourner", "type": "creature", "ctype": "dead", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "starter", "keywords": ["on_death"], "affinities": ["owed"],
		"desc": "On-Death: gain 1 Command next turn.",
		"on_death": {"type": "bonus_mana_next_turn", "value": 1}},
	"spark": {"id": "spark", "name": "Sling Stone", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": ["exhaust"], "desc": "Deal 2 damage to any target. Exhaust.",
		"spell": {"type": "damage", "value": 2}, "targeting": "any"},
	# Banner levies (THE MUSTER): one modest, non-draftable direction card is
	# appended after the hero's ten-card retinue. These are starters, never pool
	# rewards; each names the declared tribe without becoming a second doctrine.
	"line_marker": {"id": "line_marker", "name": "Line Marker", "type": "creature", "ctype": "soldier", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "starter", "draftable": false, "keywords": ["guardian"], "desc": "Guardian."},
	"loose_horse": {"id": "loose_horse", "name": "Loose Hound", "type": "creature", "ctype": "beast", "cost": 2, "atk": 2, "hp": 1,
		"rarity": "starter", "draftable": false, "keywords": ["swift"], "desc": "Swift."},
	"ash_marker": {"id": "ash_marker", "name": "Ash Marker", "type": "creature", "ctype": "dead", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "draftable": false, "keywords": ["on_death"],
		"desc": "On-Death: deal 1 damage to enemy face.",
		"on_death": {"type": "damage_face", "value": 1}},
	"hedge_caster": {"id": "hedge_caster", "name": "Hedge Caster", "type": "creature", "ctype": "warlock", "cost": 2, "atk": 2, "hp": 2,
		"rarity": "starter", "draftable": false, "keywords": ["on_enter"],
		"desc": "On-Enter: deal 1 damage to the opposing creature.",
		"on_enter": {"type": "damage_opposing", "value": 1}},
	"marker_stone": {"id": "marker_stone", "name": "Marker Stone", "type": "creature", "ctype": "bastion", "cost": 1, "atk": 0, "hp": 4,
		"rarity": "starter", "draftable": false, "keywords": ["thorns"], "desc": "Thorns."},
	"free_lance": {"id": "free_lance", "name": "Free Lance", "type": "creature", "ctype": "stray", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "starter", "draftable": false, "keywords": ["on_enter"],
		"desc": "On-Enter: gain 10 gold.", "on_enter": {"type": "gain_gold", "value": 10}},
	# Hero retinues (2026-07-28): campaign-only, low-duplicate starters.
	"grasswake_lancer": {"id": "grasswake_lancer", "name": "Grasswake Lancer", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["grasswake"], "keywords": ["overrun"], "overrun": 1, "desc": "Overrun 1."},
	"trail_scout": {"id": "trail_scout", "name": "Trail Scout", "type": "creature", "ctype": "soldier", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["grasswake"], "keywords": [], "desc": "When played: move a friendly creature to any empty slot.",
		"on_play": {"type": "redeploy_friendly"}},
	"spur_forward": {"id": "spur_forward", "name": "Spur Forward", "type": "spell", "cost": 2,
		"rarity": "starter", "draftable": false, "affinities": ["grasswake"], "keywords": ["exhaust"],
		"desc": "Move a friendly creature. It gets +2 ATK and Swift this round. Exhaust.",
		"spell": {"type": "custom", "id": "starter_spur_forward"}, "targeting": "friendly_creature"},
	"cut_them_off": {"id": "cut_them_off", "name": "Cut Them Off", "type": "spell", "cost": 1,
		"rarity": "starter", "draftable": false, "affinities": ["grasswake"], "keywords": [],
		"desc": "Deal 2 damage to an enemy. Deal 4 if you moved a friendly this round.",
		"spell": {"type": "custom", "id": "starter_cut_them_off"}, "targeting": "enemy_creature"},
	"rank_spearman": {"id": "rank_spearman", "name": "Rank Spearman", "type": "creature", "ctype": "soldier", "cost": 2, "atk": 2, "hp": 2,
		"rarity": "starter", "draftable": false, "affinities": ["last_wall"], "keywords": ["formation"], "formation": 1, "desc": "Formation 1."},
	"wall_tender": {"id": "wall_tender", "name": "Wall Tender", "type": "creature", "ctype": "soldier", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["last_wall"], "keywords": [],
		"desc": "When played: heal adjacent friendlies 2 HP.", "on_play": {"type": "starter_heal_adjacent", "value": 2}},
	"standard_page": {"id": "standard_page", "name": "Standard Page", "type": "creature", "ctype": "soldier", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["last_wall"], "keywords": ["adj_buff"],
		"desc": "Adjacent friendlies have +1 HP.", "adj_buff": {"atk": 0, "hp": 1}},
	"close_ranks_order": {"id": "close_ranks_order", "name": "Dress the Line", "type": "spell", "cost": 1,
		"rarity": "starter", "draftable": false, "affinities": ["last_wall"], "keywords": ["exhaust"],
		"desc": "A friendly and adjacent friendlies gain +1 HP this fight. Exhaust.",
		"spell": {"type": "custom", "id": "starter_close_ranks"}, "targeting": "friendly_creature"},
	"grave_goods_levy": {"id": "grave_goods_levy", "name": "Burial Goods", "type": "creature", "ctype": "dead", "cost": 1, "atk": 0, "hp": 2,
		"rarity": "starter", "draftable": false, "affinities": ["owed"], "keywords": ["on_death"],
		"desc": "On-Death: another friendly in this column gains +1/+1 this fight.",
		"on_death": {"type": "starter_buff_column_ally", "atk": 1, "hp": 1}},
	"debt_guard": {"id": "debt_guard", "name": "Debt Guard", "type": "creature", "ctype": "dead", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["owed"], "keywords": [],
		"desc": "The first time another friendly dies each round: gain +1 ATK this round.", "passive": "starter_debt_guard"},
	"read_the_will": {"id": "read_the_will", "name": "Read the Will", "type": "spell", "cost": 1,
		"rarity": "starter", "draftable": false, "affinities": ["owed"], "keywords": ["exhaust"],
		"desc": "Trigger a friendly creature's On-Death effect without killing it. Exhaust.",
		"spell": {"type": "custom", "id": "starter_read_the_will"}, "targeting": "friendly_creature"},
	"last_due": {"id": "last_due", "name": "The Last Due", "type": "spell", "cost": 1,
		"rarity": "starter", "draftable": false, "affinities": ["owed"], "keywords": ["exhaust"],
		"desc": "Sacrifice a friendly. Deal 2 damage opposite it, or to enemy face if empty. Exhaust.",
		"spell": {"type": "custom", "id": "starter_last_due"}, "targeting": "friendly_creature"},
	"lens_apprentice": {"id": "lens_apprentice", "name": "Lens Grinder", "type": "creature", "ctype": "warlock", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["lanternhall"], "keywords": [],
		"desc": "After your first spell each round: gain +1 ATK this round.", "passive": "starter_lens_apprentice"},
	"mirror_guard": {"id": "mirror_guard", "name": "Mirror Guard", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["lanternhall"], "keywords": [],
		"desc": "After your first non-damage spell each round: gain Shield.", "passive": "starter_mirror_guard"},
	"glass_savant": {"id": "glass_savant", "name": "Glass Cutter", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["lanternhall"], "keywords": [],
		"desc": "Your 2nd differently named spell each round: deal 1 damage to the opposing creature.", "passive": "starter_glass_savant"},
	"star_chart": {"id": "star_chart", "name": "Watch Glass", "type": "spell", "cost": 1,
		"rarity": "starter", "draftable": false, "affinities": ["lanternhall"], "keywords": ["exhaust"],
		"desc": "Reveal the next enemy arrival. Exhaust.", "spell": {"type": "custom", "id": "starter_star_chart"}, "targeting": "none"},
	"countermarch_levy": {"id": "countermarch_levy", "name": "Change Step", "type": "spell", "cost": 2,
		"rarity": "starter", "draftable": false, "affinities": ["lanternhall"], "keywords": ["exhaust"],
		"desc": "Move a friendly to the other row, swapping if taken. It gains +1 HP. Exhaust.",
		"spell": {"type": "custom", "id": "starter_countermarch"}, "targeting": "friendly_creature"},
	"fuse_tender": {"id": "fuse_tender", "name": "Fuse Tender", "type": "creature", "ctype": "warlock", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["everflame"], "keywords": [],
		"desc": "When played: adjacent Doom friendlies gain +1 ATK this fight and 1 round of fuse.",
		"on_play": {"type": "starter_fuse_tender", "value": 1}},
	"cinderward": {"id": "cinderward", "name": "Cinderward", "type": "creature", "ctype": "dead", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "starter", "draftable": false, "affinities": ["everflame"], "keywords": ["guardian", "doom"], "doom": 4, "desc": "Guardian. Doom 4."},
	"touchpaper": {"id": "touchpaper", "name": "Touchpaper", "type": "spell", "cost": 2,
		"rarity": "starter", "draftable": false, "affinities": ["everflame"], "keywords": ["exhaust"],
		"desc": "Reduce a friendly creature's Doom by 1. If it reaches 0, detonate it. Exhaust.",
		"spell": {"type": "custom", "id": "starter_touchpaper"}, "targeting": "friendly_creature"},

	# ═══════════════════════════════════════════
	#  COMMON CREATURES
	# ═══════════════════════════════════════════
	"crystal_sentry": {"id": "crystal_sentry", "name": "Shield Sentry", "type": "creature", "ctype": "bastion", "cost": 3, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["shield"],
		"desc": "Shield. When played: adjacent friendlies gain Shield.",
		"on_play": {"type": "grant_shield_adjacent"}},
	"hound": {"id": "hound", "name": "Fetch Hound", "type": "creature", "ctype": "beast", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": [], "desc": "When played: return your last discarded spell to your hand. If none, draw 1.",
		"on_play": {"type": "fetch_spell"}},
	"shieldbearer": {"id": "shieldbearer", "name": "Grudge-Bearer", "type": "creature", "ctype": "soldier", "cost": 4, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["shield"], "desc": "Shield. When this loses Shield: gain +2 ATK this fight.",
		"passive": "shield_rage"},
	"pikeman": {"id": "pikeman", "name": "Pikeman", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": [], "desc": "When played: move the opposing creature back. If blocked, deal 2 damage to it.",
		"on_play": {"type": "shove_back", "value": 2}},
	"lookout": {"id": "lookout", "name": "Lookout", "type": "creature", "ctype": "soldier", "cost": 2, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. Front row: gain +1 ATK this round. Back row: reveal the next enemy arrival.",
		"on_play": {"type": "vanguard_split", "value": 1}},
	"warding_stone": {"id": "warding_stone", "name": "Cornerstone", "type": "creature", "ctype": "bastion", "cost": 2, "atk": 0, "hp": 3,
		"rarity": "common", "keywords": ["guardian", "on_enter"],
		"desc": "Guardian. On-Enter: your Bastions gain +2 HP this fight.",
		"on_enter": {"type": "buff_ctype_hp", "ctype": "bastion", "value": 2}},
	"hexblade": {"id": "hexblade", "name": "Hedge Knife", "type": "creature", "ctype": "warlock", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": [],
		"desc": "+1 ATK per spell cast this round.",
		"passive": "atk_per_spell"},
	"harpy": {"id": "harpy", "name": "Snatch-Hawk", "type": "creature", "ctype": "beast", "cost": 4, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. When played: move the opposing back-row enemy to the front row.",
		"on_play": {"type": "haul_front", "value": 0}},
	"thornguard": {"id": "thornguard", "name": "Quillback", "type": "creature", "ctype": "beast", "cost": 3, "atk": 1, "hp": 4,
		"rarity": "common", "keywords": ["thorns", "on_death"], "desc": "Thorns. On-Death: deal 1 damage to all enemies.",
		"on_death": {"type": "damage_all_enemies", "value": 1}},
	"raven": {"id": "raven", "name": "Gallows Crow", "type": "creature", "ctype": "beast", "cost": 2, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["sniper"], "desc": "Sniper. When played: deal 2 damage to a random enemy back-row creature.",
		"on_play": {"type": "snipe_back", "value": 2}},
	"squire_captain": {"id": "squire_captain", "name": "Sworn Man", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": [],
		"desc": "Damage to the friendly in this column's other row is dealt to this creature instead.",
		"passive": "bodyguard"},
	"plague_rat": {"id": "plague_rat", "name": "Ditch Adder", "type": "creature", "ctype": "beast", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["poison"],
		"desc": "Poison."},
	"torchbearer": {"id": "torchbearer", "name": "Torchbearer", "type": "creature", "ctype": "soldier", "cost": 2, "atk": 0, "hp": 3,
		"rarity": "common", "keywords": ["adj_buff"], "desc": "Adjacent friendlies +1 ATK.",
		"adj_buff": {"atk": 1, "hp": 0}},
	"gravedigger": {"id": "gravedigger", "name": "Gravedigger", "type": "creature", "ctype": "dead", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": [], "desc": "When a friendly creature dies on your turn: this gains +1/+1.",
		"passive": "swell_on_ally_death"},
	"bloodhound": {"id": "bloodhound", "name": "Ferret", "type": "creature", "ctype": "beast", "cost": 1, "atk": 1, "hp": 1,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-Enter: deal 1 damage to the opposing creature and draw 1.",
		"on_enter": {"type": "damage_opposing_draw", "value": 1}},
	"scavenger": {"id": "scavenger", "name": "Scavenger", "type": "creature", "ctype": "stray", "cost": 3, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["swift", "on_death"], "desc": "Swift. On-Death: gain 4 gold.",
		"on_death": {"type": "gain_gold", "value": 4}},
	# ── Bastion cycle: cheap walls with distinct strike reactions, plus a
	# two-cost keystone that slowly turns the defensive line into an attack. ──
	"ironhide_anvil": {"id": "ironhide_anvil", "name": "Iron Rampart", "type": "creature", "ctype": "bastion", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "common", "keywords": ["guardian"], "passive": "reflect_strike",
		"desc": "Guardian. When struck: deal the same damage to the attacker."},
	# Bastion keystone (SIEGEWORKS): the walls learn to hit back. Every round it
	# stands, your Bastions ramp +1 ATK — a pile of 0-atk walls becomes a slow siege.
	"siegewright": {"id": "siegewright", "name": "War Fortress", "type": "creature", "ctype": "bastion", "cost": 4, "atk": 1, "hp": 6,
		"rarity": "uncommon", "keywords": ["guardian", "thorns"],
		"desc": "Guardian. Thorns. Start of each round: your Bastions gain +1 ATK this fight.",
		"passive": "bastion_ramp"},
	"bramble_stockade": {"id": "bramble_stockade", "name": "Bramble Stockade", "type": "creature", "ctype": "bastion", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "common", "keywords": ["thorns"], "passive": "anvil_spawn",
		"desc": "Thorns. When this survives a hit: summon a 1/1 in an adjacent empty lane."},
	"heartwood_elder": {"id": "heartwood_elder", "name": "Herd Bull", "type": "creature", "ctype": "beast", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "common", "keywords": ["on_enter"],
		"desc": "On-Enter: gain +1/+1 for each other friendly Beast.",
		"on_enter": {"type": "buff_per_ctype", "ctype": "beast", "atk": 1, "hp": 1}},
	"bastion_lord": {"id": "bastion_lord", "name": "Tally Man", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 3, "hp": 8,
		"rarity": "uncommon", "keywords": [], "passive": "bulwark_lord",
		"desc": "When a friendly creature survives a hit: deal 1 damage to enemy face."},
	"tallow_doll": {"id": "tallow_doll", "name": "Tallow Doll", "type": "creature", "ctype": "dead", "cost": 3, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["on_death"],
		"desc": "On-Death: the opposing creature attacks its nearest ally. If alone, it attacks enemy face.",
		"on_death": {"type": "betray_opposing"}},
	"skirmisher": {"id": "skirmisher", "name": "Headhunter", "type": "creature", "ctype": "soldier", "cost": 4, "atk": 3, "hp": 2,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. Slay: heal your hero 2 HP.",
		"passive": "slay_heal"},
	"lancer": {"id": "lancer", "name": "Lancer", "type": "creature", "ctype": "soldier", "cost": 4, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": ["overrun"], "overrun": 2,
		"desc": "Overrun 2."},

	# ═══════════════════════════════════════════
	#  ARMAMENTS — one per non-Structure bearer; Exhaust when equipped
	# ═══════════════════════════════════════════
	"hooked_pike": {"id": "hooked_pike", "name": "Hooked Pike", "type": "armament", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Bearer gets +3 ATK and Piercing.",
		"targeting": "friendly_creature",
		"armament": {"atk": 3, "keywords": ["piercing"], "icon": "piercing"}},
	"tower_shield": {"id": "tower_shield", "name": "Tower Shield", "type": "armament", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Bearer gets +5 HP and Armored.",
		"targeting": "friendly_creature",
		"armament": {"hp": 5, "keywords": ["armored"], "icon": "armored"}},
	"grave_bell": {"id": "grave_bell", "name": "Grave Bell", "type": "armament", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Bearer's On-Death effects trigger twice.",
		"targeting": "friendly_creature",
		"armament": {"effect": "double_on_death", "icon": "on_death"}},
	"witchbrand": {"id": "witchbrand", "name": "Witchbrand", "type": "armament", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "After you cast a spell, bearer gets +1/+1 this fight.",
		"targeting": "friendly_creature",
		"armament": {"effect": "spell_growth", "value": 1, "icon": "on_enter"}},
	"forked_spear": {"id": "forked_spear", "name": "Forked Spear", "type": "armament", "cost": 2,
		"rarity": "uncommon", "keywords": [], "desc": "Bearer also strikes adjacent enemies.",
		"targeting": "friendly_creature",
		"armament": {"effect": "adjacent_strikes", "icon": "piercing"}},
	"repeating_arbalest": {"id": "repeating_arbalest", "name": "Repeating Arbalest", "type": "armament", "cost": 1,
		"rarity": "rare", "keywords": [], "desc": "Bearer gains Last Stand and attacks twice.",
		"targeting": "friendly_creature",
		"armament": {"effect": "double_attack", "keywords": ["last_stand"], "icon": "last_stand"}},

	# ═══════════════════════════════════════════
	#  COMMON SPELLS (12)
	# ═══════════════════════════════════════════
	"slash": {"id": "slash", "name": "Breach Bomb", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to an enemy and move it back. If blocked, deal 2 more damage.",
		"spell": {"type": "custom", "id": "slash"}, "targeting": "enemy_creature"},
	"shield_wall": {"id": "shield_wall", "name": "Lock Shields", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "All friendly front-row creatures gain Shield.",
		"spell": {"type": "custom", "id": "testudo"}, "targeting": "none", "scope": "YOUR FRONT LINE"},
	# Cost 2, not 0 (2026-07-27). Swift is the documented exception to the muster
	# delay, so at cost 0 this was a FREE card that switched the delay off for every
	# body you had just played — a hole straight through a rule shipped six days
	# earlier. Two Command means the yell now costs two-thirds of a turn, so it buys
	# the pre-phase for a line that is already standing (its real job) rather than
	# paying for itself by rushing a fresh one.
	"war_cry": {"id": "war_cry", "name": "War Cry", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "All friendlies gain Swift this round.",
		"spell": {"type": "custom", "id": "war_cry"}, "targeting": "none", "scope": "YOUR ARMY"},
	"provision": {"id": "provision", "name": "Fill the Rank", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Summon a 2/1 Soldier in an empty lane. Exhaust.",
		"spell": {"type": "custom", "id": "provision"}, "targeting": "none"},
	"patch_up": {"id": "patch_up", "name": "Field Surgery", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Fully heal a friendly creature. It gains Last Stand.",
		"spell": {"type": "custom", "id": "patch_up"}, "targeting": "friendly_creature"},
	"flame_bolt": {"id": "flame_bolt", "name": "Fire Arrow", "type": "spell", "cost": 3,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to enemy face. If you already cast a spell this turn, deal 5 instead.",
		"spell": {"type": "custom", "id": "flame_bolt"}, "targeting": "none", "scope": "ENEMY FACE"},
	"shove": {"id": "shove", "name": "Shove", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Move an enemy 1 lane toward the nearest edge. If blocked, deal 2 damage to both.",
		"spell": {"type": "custom", "id": "shove"}, "targeting": "enemy_creature"},
	"gambit": {"id": "gambit", "name": "Fresh Orders", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Discard up to 3 cards, then draw that many.",
		"spell": {"type": "custom", "id": "gambit"}, "targeting": "none"},
	"blood_tithe": {"id": "blood_tithe", "name": "Blood Price", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Deal 4 damage to enemy face. Take 2 damage yourself.",
		"spell": {"type": "custom", "id": "blood_tithe"}, "targeting": "none", "scope": "ENEMY FACE"},
	"reckless_charge": {"id": "reckless_charge", "name": "Penance", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to any target. You may Exhaust a Curse from your hand to deal 6 instead.",
		"spell": {"type": "custom", "id": "penance"}, "targeting": "any"},
	"quick_shot": {"id": "quick_shot", "name": "Quick Shot", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Deal 1 damage to any target. Slay: draw 1. Exhaust.",
		"spell": {"type": "custom", "id": "quick_shot"}, "targeting": "any"},
	"frost_bolt": {"id": "frost_bolt", "name": "Stopped Cold", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "An enemy creature cannot attack this round.",
		"spell": {"type": "custom", "id": "frost_bolt"}, "targeting": "enemy_creature"},
	"adrenaline": {"id": "adrenaline", "name": "Countermarch", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": ["exhaust"], "affinities": ["last_wall", "lanternhall"],
		"desc": "Move a friendly to the other row in its lane. It gains Shield. Exhaust.",
		"spell": {"type": "custom", "id": "baggage_train"}, "targeting": "friendly_creature"},
	"hex": {"id": "hex", "name": "Hex", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Remove an enemy's keywords. Deal 4 damage if it had any; otherwise deal 1.",
		"spell": {"type": "custom", "id": "hex"}, "targeting": "enemy_creature"},

	# ═══════════════════════════════════════════
	#  UNCOMMON CREATURES
	# ═══════════════════════════════════════════
	"battle_drummer": {"id": "battle_drummer", "name": "Battle Drummer", "type": "creature", "ctype": "soldier", "cost": 4, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": ["armored"],
		"desc": "Armored. Adjacent friendlies have Swift.",
		"passive": "drummer_swift"},
	"witch": {"id": "witch", "name": "Witch", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": [], "desc": "Your first spell each turn costs 1 less.",
		"passive": "first_spell_discount"},
	# Warlock keystone (SPELLCRAFT): the coven feeds on every incantation. Each spell
	# you cast permanently grows your Warlocks — the reason to run a caster shell.
	"coven_mother": {"id": "coven_mother", "name": "Coven Mother", "type": "creature", "ctype": "warlock", "cost": 5, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": [],
		"desc": "When you cast a spell: your Warlocks gain +1 ATK this fight.",
		"passive": "coven_spell"},
	"duelist": {"id": "duelist", "name": "Condottiere", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: gain +1/+1 this fight for each unspent Command.",
		"on_enter": {"type": "atk_hp_per_unspent_mana"}},
	"griffin": {"id": "griffin", "name": "Griffin", "type": "creature", "ctype": "beast", "cost": 4, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["swift", "on_death"], "desc": "Swift. On-Death: return this creature to your hand. Once per fight.",
		"on_death": {"type": "return_to_hand_once"}},
	"revenant": {"id": "revenant", "name": "Revenant", "type": "creature", "ctype": "dead", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "common", "keywords": ["on_death"],
		"desc": "On-Death: return this creature to play at full HP. Once per fight.",
		"on_death": {"type": "reborn"}},
	"berserker": {"id": "berserker", "name": "Berserker", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 2, "hp": 6,
		"rarity": "uncommon", "keywords": ["lifelink"],
		"desc": "Lifesteal. When this survives a hit: gain +2 ATK.",
		"passive": "rage_on_hit"},
	"mule": {"id": "mule", "name": "Mule", "type": "creature", "ctype": "beast", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["summon"], "desc": "Summon."},
	"husk": {"id": "husk", "name": "Husk", "type": "creature", "ctype": "dead", "cost": 5, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": ["guardian", "lifelink", "on_death"],
		"desc": "Guardian. Lifesteal. On-Death: summon a 2/2 token in this lane.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2}},
	"basilisk": {"id": "basilisk", "name": "Basilisk", "type": "creature", "ctype": "beast", "cost": 3, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["poison", "thorns"], "venom_thorns": true,
		"desc": "Poison. Thorns. Any creature damaged by its Thorns dies."},
	"necromancer": {"id": "necromancer", "name": "Necromancer", "type": "creature", "ctype": "dead", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": ["on_death"],
		"desc": "On-Death: summon a 2/2 token in each row of this lane.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2, "both_rows": true}},
	"carrion_priest": {"id": "carrion_priest", "name": "Carrion Priest", "type": "creature", "ctype": "dead", "cost": 3, "atk": 1, "hp": 4,
		"rarity": "common", "keywords": ["guardian"], "desc": "Guardian. When a friendly dies: deal 1 damage to enemy face and heal your hero 1 HP.",
		"passive": "drain_on_ally_death"},
	"gravecaller": {"id": "gravecaller", "name": "The Inheritor", "type": "creature", "ctype": "dead", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "common", "keywords": ["on_enter"],
		"desc": "On-Enter: gain +1/+1 for each friendly that died this turn.",
		"on_enter": {"type": "atk_hp_per_fallen"}},
	"breaker": {"id": "breaker", "name": "Twinblade", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 3, "hp": 7,
		"rarity": "uncommon", "keywords": [],
		"desc": "After it attacks, this strikes one adjacent enemy lane, or enemy face if both are empty.",
		"passive": "attacks_twice"},
	"cleave_hound": {"id": "cleave_hound", "name": "Cleave Hound", "type": "creature", "ctype": "beast", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "common", "keywords": [],
		"desc": "When this attacks: deal 1 damage to enemy creatures in adjacent lanes.",
		"passive": "cleave"},
	"blood_pyre": {"id": "blood_pyre", "name": "Blood Pyre", "type": "creature", "ctype": "dead", "cost": 2, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": [], "desc": "When played: sacrifice this creature. Adjacent friendlies get +3 ATK this round. Draw 1.",
		"on_play": {"type": "blood_sacrifice", "value": 3}},
	"copycat": {"id": "copycat", "name": "Changeling", "type": "creature", "ctype": "stray", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-Enter: become a copy of a chosen friendly creature.",
		"on_enter": {"type": "copy_friendly"}},
	"familiar": {"id": "familiar", "name": "Camp Follower", "type": "creature", "ctype": "stray", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: Discover a creature. It costs 1 less.",
		"on_enter": {"type": "discover", "type_filter": "creature", "rarity_filter": ""}},
	"adaptable": {"id": "adaptable", "name": "The Chameleon", "type": "creature", "ctype": "stray", "cost": 4, "atk": 5, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: gain Swift, Piercing, Armored, or Thorns (you choose).",
		"on_enter": {"type": "choose_keyword"}},
	"vengeance": {"id": "vengeance", "name": "Vengeance", "type": "creature", "ctype": "dead", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "When you take face damage: this gains +2 ATK this fight.",
		"passive": "vengeance_growth"},
	"iron_bastion": {"id": "iron_bastion", "name": "Honor Guard", "type": "creature", "ctype": "soldier", "cost": 6, "atk": 3, "hp": 9,
		"rarity": "rare", "keywords": [],
		"desc": "The friendly in the other row of this column cannot drop below 1 HP.",
		"passive": "column_ward"},
	"leyline_conduit": {"id": "leyline_conduit", "name": "The Witch-Post", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 0, "hp": 6,
		"rarity": "uncommon", "keywords": ["formation"], "affinities": ["last_wall", "lanternhall"], "formation": 1,
		"desc": "Formation. Your first spell each turn: this creature's column gains Shield.",
		"passive": "first_spell_column_shield"},
	"the_glutton": {"id": "the_glutton", "name": "The Glutton", "type": "creature", "ctype": "beast", "cost": 4, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter", "overrun"], "overrun": 1,
		"desc": "Overrun. On-Enter: destroy adjacent friendlies. Gain +2/+2 and their keywords each.",
		"on_enter": {"type": "glutton_devour"}},
	# Beast keystone (ARRIVE): the pack's arrival hits twice. Doubles every OTHER
	# friendly Beast's On-Enter (goblin face / naga poke / dragon AoE / imp spell).
	"bloodmoon_alpha": {"id": "bloodmoon_alpha", "name": "Bloodmoon Alpha", "type": "creature", "ctype": "beast", "cost": 4, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": [],
		"desc": "Your other Beasts' On-Enter effects trigger twice.",
		"passive": "beast_encore"},
	"standard_bearer": {"id": "standard_bearer", "name": "Standard Bearer", "type": "creature", "ctype": "soldier", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "common", "keywords": [],
		"desc": "Your summoned tokens enter with +1/+1.",
		"passive": "token_lord"},
	"shieldmaiden": {"id": "shieldmaiden", "name": "The Bodyguard", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": [],
		"desc": "While in the front row, attacks on your face hit this creature instead.",
		"passive": "interpose"},
	"the_apothecary": {"id": "the_apothecary", "name": "The Apothecary", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 1, "hp": 6,
		"rarity": "uncommon", "keywords": [],
		"desc": "When you drink a potion: this gains +2/+2.",
		"passive": "tonic_vigor"},
	"emberwright": {"id": "emberwright", "name": "Emberwright", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "When you cast a spell: deal 2 damage to enemy face.",
		"passive": "ember_per_spell"},
	"sin_eater": {"id": "sin_eater", "name": "Sin-Eater", "type": "creature", "ctype": "dead", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "When played: Exhaust a Curse from your hand. This gains +2/+2. Draw 1.",
		"on_play": {"type": "eat_curse", "value": 2}},

	# ═══════════════════════════════════════════
	#  UNCOMMON SPELLS (11)
	# ═══════════════════════════════════════════
	"smite_spell": {"id": "smite_spell", "name": "Rain of Blows", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "affinities": ["grasswake"],
		"desc": "A friendly creature attacks twice this round. Each target counterattacks. Exhaust.",
		"spell": {"type": "custom", "id": "smite_spell"}, "targeting": "friendly_creature"},
	"inspire": {"id": "inspire", "name": "Turncoat", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Control an enemy with 3 or less ATK. Otherwise, stop it attacking this round. Exhaust.",
		"spell": {"type": "custom", "id": "turncoat"}, "targeting": "enemy_creature"},
	"ambush": {"id": "ambush", "name": "Ambush", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 1 damage to all enemy creatures. Your Swift creatures get +1 ATK this round.",
		"spell": {"type": "custom", "id": "ambush"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"reanimate": {"id": "reanimate", "name": "Press the Dead", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Summon the last enemy to die as a 1/1 with its keywords. If none, your own dead. Exhaust.",
		"spell": {"type": "custom", "id": "reanimate"}, "targeting": "none"},
	"charge_spell": {"id": "charge_spell", "name": "Sound the Charge", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": [], "desc": "A friendly attacks every opposing lane this round. Each target deals 1 damage back.",
		"spell": {"type": "custom", "id": "charge_spell"}, "targeting": "friendly_creature"},
	"ricochet": {"id": "ricochet", "name": "Crossfire", "type": "spell", "cost": 3,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to each back-row enemy. If that row is empty, hit the front instead.",
		"spell": {"type": "custom", "id": "ricochet"}, "targeting": "none", "scope": "ENEMY BACK ROW"},
	"offering": {"id": "offering", "name": "Offering", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "affinities": ["owed"],
		"desc": "Sacrifice a friendly creature. Its On-Death triggers twice. Exhaust.",
		"spell": {"type": "custom", "id": "offering"}, "targeting": "friendly_creature"},
	"grave_pact": {"id": "grave_pact", "name": "Last Rites", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to a creature. If a friendly died this fight, deal 6 instead.",
		"spell": {"type": "custom", "id": "last_rites"}, "targeting": "any_creature"},
	"fuel_the_pyre": {"id": "fuel_the_pyre", "name": "Fuel the Pyre", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Sacrifice a friendly. Deal its ATK to the opposing creature, or a random enemy if empty.",
		"spell": {"type": "custom", "id": "fuel_the_pyre"}, "targeting": "friendly_creature"},
	"venom_tip": {"id": "venom_tip", "name": "Venom Tip", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [],
		"desc": "A friendly creature gains Poison this round.",
		"spell": {"type": "custom", "id": "venom_tip"}, "targeting": "friendly_creature"},
	"mark_of_ash": {"id": "mark_of_ash", "name": "Mark of Ash", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [],
		"desc": "An enemy creature gains Doom 2. The blast hits only it. If it has Doom, detonate instead.",
		"spell": {"type": "custom", "id": "mark_of_ash"}, "targeting": "enemy_creature"},
	"pillage": {"id": "pillage", "name": "Pillage", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to an enemy creature and 1 damage to enemy face. Slay: gain 10 gold.",
		"spell": {"type": "custom", "id": "pillage"}, "targeting": "enemy_creature"},
	"echo_spell": {"id": "echo_spell", "name": "Echo", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Copy the last spell you cast this turn. If you have not cast one, do nothing. Exhaust.",
		"spell": {"type": "custom", "id": "echo_spell"}, "targeting": "none"},
	"turbo": {"id": "turbo", "name": "Frenzy", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "affinities": ["everflame", "owed"],
		"desc": "Give a friendly +3 ATK this round. Detonate its Doom, or give it Doom 2. Exhaust.",
		"spell": {"type": "custom", "id": "turbo"}, "targeting": "friendly_creature"},
	"recycle": {"id": "recycle", "name": "Salvage", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "affinities": ["lanternhall"],
		"desc": "Exhaust another card in your hand. Draw cards equal to its cost. Exhaust.",
		"spell": {"type": "custom", "id": "recycle"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  RARE + UNCOMMON CREATURES — the `rarity` field is authoritative, not this
	#  banner: the 2026-07-13 rarity pass demoted plain-strong bodies to uncommon
	#  (rare = run-warping / build-around / finisher only).
	# ═══════════════════════════════════════════
	"dragon_hatchling": {"id": "dragon_hatchling", "name": "Dragon Hatchling", "type": "creature", "ctype": "beast", "cost": 6, "atk": 5, "hp": 7,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: deal 1 damage to each enemy front-row creature, +1 per other Beast (max 3).",
		"on_enter": {"type": "damage_all_enemies", "value": 1, "per_ctype": "beast", "per_cap": 2, "scope": "front"}},
	"royal_guard": {"id": "royal_guard", "name": "Royal Guard", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 2, "hp": 6,
		"rarity": "uncommon", "keywords": [], "desc": "Adjacent friendlies take 1 less damage. When this is hit: gain +1 ATK.",
		"passive": "royal_guard"},
	"assassin": {"id": "assassin", "name": "Assassin", "type": "creature", "ctype": "stray", "cost": 5, "atk": 5, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift"], "desc": "Swift. When played: destroy the opposing creature, front row first.",
		"on_play": {"type": "execute", "value": 0}},
	# Stray arc — MOBILITY + LARCENY (the 2026-07-24 tribe rework; the old gold
	# spine is retired). The Deserter teaches the verb (Strays rearrange the line),
	# the Outrider is the dancing flanker, and the Captain is the keystone.
	"deserter": {"id": "deserter", "name": "Deserter", "type": "creature", "ctype": "stray", "cost": 3, "atk": 4, "hp": 2,
		"rarity": "common", "keywords": [],
		"desc": "When played: move 1 friendly creature to any empty slot.",
		"on_play": {"type": "redeploy_friendly"}},
	"sellsword_outrider": {"id": "sellsword_outrider", "name": "Roving Sellsword", "type": "creature", "ctype": "stray", "cost": 5, "atk": 6, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "Once each turn this may move for free. After moving, it gains +1 ATK this round.",
		"passive": "free_move"},
	# Stray keystone "Free Company Captain" (id kept as `kingpin` for save/art
	# stability). DEFECTION: on killing an enemy creature it loots one of that
	# creature's keywords — a persistent grant — or free-redeploys if there's
	# nothing worth taking. Turn-on: your other Strays free-redeploy on a kill.
	# Wired host-side in Combat._apply_combat_strike_riders (skirmish-safe).
	"kingpin": {"id": "kingpin", "name": "Free Company Captain", "type": "creature", "ctype": "stray", "cost": 5, "atk": 5, "hp": 4,
		"rarity": "rare", "keywords": [],
		"desc": "Slay: take 1 of the victim's keywords, or move. Your other Strays move on a kill.",
		"passive": "defection"},
	"hydra": {"id": "hydra", "name": "Hydra", "type": "creature", "ctype": "beast", "cost": 6, "atk": 4, "hp": 6,
		"rarity": "rare", "keywords": ["rampage", "armored"], "rampage": 1,
		"desc": "Rampage. Armored. Attacks every opposing lane instead. Each defender counterattacks.",
		"passive": "attacks_all_lanes"},
	"summoner": {"id": "summoner", "name": "The Levymaster", "type": "creature", "ctype": "dead", "cost": 3, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["guardian"],
		"desc": "Guardian. Start of each round: summon a 2/2 token in an adjacent empty lane.",
		"passive": "summon_each_round"},
	"paladin": {"id": "paladin", "name": "The Last Man", "type": "creature", "ctype": "soldier", "cost": 6, "atk": 4, "hp": 6,
		"rarity": "uncommon", "keywords": ["last_stand"],
		"desc": "Last Stand. On trigger: your creatures get +2 ATK this fight. Heal your hero 3 HP.",
		"passive": "paladin_rally"},
	"corpse_eater": {"id": "corpse_eater", "name": "Corpse Eater", "type": "creature", "ctype": "dead", "cost": 4, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["piercing"], "desc": "Piercing. When a friendly creature dies: gain +1 ATK.",
		"passive": "grow_on_ally_death"},
	"ironclad_veteran": {"id": "ironclad_veteran", "name": "Old Campaigner", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: gain +1/+1 for every 3 kills this card has made this run.",
		"on_enter": {"type": "atk_hp_per_own_kills"}},
	"glass_knight": {"id": "glass_knight", "name": "The Bravo", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 5, "hp": 1,
		"rarity": "uncommon", "keywords": ["shield", "swift"],
		"desc": "Shield. Swift. Slay: regain Shield.",
		"passive": "shield_on_slay"},
	"doppelganger": {"id": "doppelganger", "name": "Dead Man's Face", "type": "creature", "ctype": "stray", "cost": 5, "atk": 4, "hp": 6,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-Enter: become a copy of the most recently dead creature.",
		"on_enter": {"type": "copy_last_dead"}},
	"vampire_lord": {"id": "vampire_lord", "name": "The Blood Count", "type": "creature", "cost": 5, "atk": 3, "hp": 5,
		"rarity": "rare", "ctype": "dead", "keywords": ["lifelink"],
		"desc": "Lifesteal. When another friendly Dead dies: gain its ATK.",
		"passive": "vampire_feed"},
	"chaos_imp": {"id": "chaos_imp", "name": "Chaos Imp", "type": "creature", "ctype": "beast", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-Enter: cast a random spell costing 1 or less for free. Targets are automatic.",
		"on_enter": {"type": "cast_random_spell"}},
	"warden_of_graves": {"id": "warden_of_graves", "name": "Warden of Graves", "type": "creature", "ctype": "dead", "cost": 4, "atk": 2, "hp": 5,
		"rarity": "rare", "keywords": ["on_death"], "desc": "On-Death: summon a 2/2 in its lane. Your creatures' On-Death effects trigger twice.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2},
		"passive": "double_on_death"},
	# Dead keystone (DIE): every trade feeds the machine. Each OTHER friendly death
	# raises a 1/1 Wight (ctype dead, so it re-feeds) in this creature's back-row
	# lane, once per round. Mirrors the gravewardens_pact relic; net-safe via the
	# _apply_ally_death_passives funnel + summon_token board snapshot.
	"gravepact": {"id": "gravepact", "name": "Gravepact", "type": "creature", "ctype": "dead", "cost": 4, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": [],
		"desc": "When another friendly dies: summon a 1/1 Wight in your back row. Once per round.",
		"passive": "reap_on_ally_death"},
	# The Sexton (Dead RARE — SECOND WAVE): playing it opens the grave for the
	# whole fight, and the grave stays open even after the Sexton falls. Every
	# third OTHER non-token friendly to die, three 2/2 Wights (ctype dead — they
	# re-feed the grave) claw up into your empty back row (floor: +1/+1 to your
	# Dead if the row is full). Engine on Combat (_grave_armed / _grave_souls),
	# counted in _apply_ally_death_passives, wave via summon_token (rides the
	# board snapshot for net). arm_grave on-enter sets the fight-scoped flag.
	"the_sexton": {"id": "the_sexton", "name": "The Sexton", "type": "creature", "ctype": "dead", "cost": 5, "atk": 4, "hp": 6,
		"rarity": "rare", "keywords": ["on_enter"],
		"desc": "On-Enter: this fight, every 3rd other friendly death summons 3 2/2 Wights in the back row.",
		"on_enter": {"type": "arm_grave"}},
	# ── The other four tribe MOMENTS (2026-07-30) ────────────────────────────
	# docs/DRAW_AND_TRIBE_DIRECTION_20260724.md Part C. ADDITIVE, not reworks:
	# the four existing keystones (warden_line / bastion_ramp / coven_spell /
	# beast_encore) all still work and are all still drafted, so replacing them in
	# place would have churned four verified cards to no player benefit. Each of
	# these is instead the RARE that a committed tribe deck is drafting toward, and
	# each is built on one of the doc's three death-proof devices so a wipe cannot
	# switch the tribe's identity off mid-fight (engine + rationale in Combat.gd).
	"pike_captain": {"id": "pike_captain", "name": "The Pike Captain", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 3, "hp": 6,
		"rarity": "rare", "keywords": [],
		"desc": "Full front row at round start: Soldiers gain +1 ATK and Piercing. Once per fight.",
		"passive": "volley"},
	"siege_bastion": {"id": "siege_bastion", "name": "The Master of Works", "type": "creature", "ctype": "bastion", "cost": 6, "atk": 2, "hp": 8,
		"rarity": "rare", "keywords": ["guardian", "on_enter"],
		"desc": "Guardian. On-Enter: this fight, your struck Bastions deal the same damage to the attacker.",
		"on_enter": {"type": "arm_works"}},
	"the_magister": {"id": "the_magister", "name": "The Magister", "type": "creature", "ctype": "warlock", "cost": 5, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["on_enter"],
		"desc": "On-Enter: this fight, your 2nd spell each round: Warlocks hit the opposing creature for 2.",
		"on_enter": {"type": "arm_ledger"}},
	"dire_alpha": {"id": "dire_alpha", "name": "The Drover", "type": "creature", "ctype": "beast", "cost": 5, "atk": 5, "hp": 4,
		"rarity": "rare", "keywords": [],
		"desc": "Each round, your 2nd Beast to arrive deals its ATK to the opposing creature.",
		"passive": "stampede"},
	"siege_golem": {"id": "siege_golem", "name": "The Siege Ram", "type": "creature", "cost": 6, "atk": 3, "hp": 7,
		"rarity": "uncommon", "ctype": "bastion", "keywords": ["overrun", "on_enter"], "overrun": 3,
		"desc": "Overrun 3. On-Enter: your other Bastions gain Thorns this fight.",
		"on_enter": {"type": "buff_ctype_keyword", "kw": "thorns", "ctype": "bastion"}},
	"old_bones": {"id": "old_bones", "name": "Old Bones", "type": "creature", "ctype": "dead", "cost": 5, "atk": 5, "hp": 4,
		"rarity": "common", "keywords": ["on_death"],
		"desc": "On-Death: return as a 2/2, then as a 1/1.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2, "diminish": true}},

	# ═══════════════════════════════════════════
	#  RARE + UNCOMMON SPELLS — `rarity` field is authoritative (2026-07-13
	#  rarity pass: single-fight tech spells went uncommon).
	# ═══════════════════════════════════════════
	"earthquake": {"id": "earthquake", "name": "Earthquake", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 2 damage to every creature. Move both front rows back where possible. Exhaust.",
		"spell": {"type": "custom", "id": "earthquake"}, "targeting": "none", "scope": "ALL CREATURES"},
	"kings_command": {"id": "kings_command", "name": "King's Command", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "All friendlies get +1 ATK this round for each friendly creature. Exhaust.",
		"spell": {"type": "custom", "id": "kings_command"}, "targeting": "none", "scope": "YOUR ARMY"},
	"unholy_bargain": {"id": "unholy_bargain", "name": "The Black Contract", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"], "affinities": ["owed"],
		"desc": "Add War-Debt. The round's first non-token death summons a 2/2 Debtor. A 2nd draws 2.",
		"spell": {"type": "custom", "id": "unholy_bargain"}, "targeting": "none"},
	"mass_grave": {"id": "mass_grave", "name": "Mass Grave", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 1 damage to every enemy for each friendly death this fight. Exhaust.",
		"spell": {"type": "custom", "id": "mass_grave"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"dark_pact": {"id": "dark_pact", "name": "Thin the Ranks", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Sacrifice a friendly creature. Other friendlies get +1/+1 this fight.",
		"spell": {"type": "custom", "id": "dark_pact"}, "targeting": "friendly_creature"},
	"war_chant": {"id": "war_chant", "name": "Call the Militia", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Discard up to 3 cards. Summon a 2/1 Soldier for each. Exhaust.",
		"spell": {"type": "custom", "id": "war_chant"}, "targeting": "none"},
	"grave_robbery": {"id": "grave_robbery", "name": "Grave Robbery", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Return the last creature to die to your hand. Exhaust.",
		"spell": {"type": "custom", "id": "grave_robbery"}, "targeting": "none"},
	"cataclysm": {"id": "cataclysm", "name": "Sweep the Line", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "A friendly deals its ATK in its lane and adjacent lanes. No counterattacks. Exhaust.",
		"spell": {"type": "custom", "id": "cataclysm"}, "targeting": "friendly_creature"},
	"soul_swap": {"id": "soul_swap", "name": "Soul Swap", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [], "desc": "Swap an enemy creature's ATK and HP. Its HP cannot drop below 1.",
		"spell": {"type": "custom", "id": "soul_swap"}, "targeting": "enemy_creature"},
	"apocalypse": {"id": "apocalypse", "name": "No Quarter", "type": "spell", "cost": 6,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Destroy every creature. Summon a 1/1 Shade for each friendly destroyed this way. Exhaust.",
		"spell": {"type": "custom", "id": "apocalypse"}, "targeting": "none", "scope": "ALL CREATURES"},
	"lay_on_hands": {"id": "lay_on_hands", "name": "Foul the Blades", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Your creatures' attacks are poisonous this round. Exhaust.",
		"spell": {"type": "custom", "id": "virulence"}, "targeting": "none", "scope": "YOUR ARMY"},
	"hoarfrost": {"id": "hoarfrost", "name": "Hoarfrost", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [],
		"desc": "A friendly creature gains Shield. The opposing creature can't attack this round.",
		"spell": {"type": "custom", "id": "hoarfrost"}, "targeting": "friendly_creature"},
	"banish": {"id": "banish", "name": "Banish", "type": "spell", "cost": 4,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Remove an enemy with 4 or less HP. Otherwise, deal 4 damage. Exhaust.",
		"spell": {"type": "custom", "id": "banish"}, "targeting": "enemy_creature"},
	"time_snare": {"id": "time_snare", "name": "The Doubled Hour", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Your creatures attack twice this round. Each target counterattacks. Draw 1. Exhaust.",
		"spell": {"type": "custom", "id": "doubled_hour"}, "targeting": "none", "scope": "YOUR ARMY"},
	"holy_smite": {"id": "holy_smite", "name": "Salt the Wound", "type": "spell", "cost": 4,
		"rarity": "common", "keywords": [], "desc": "Deal damage to an enemy creature equal to its missing HP, at least 3. Slay: draw 1.",
		"spell": {"type": "custom", "id": "holy_smite"}, "targeting": "enemy_creature"},
	"plague_bell": {"id": "plague_bell", "name": "Plague Bell", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Deal 1 damage to every creature. If any creature dies, repeat this effect. Exhaust.",
		"spell": {"type": "custom", "id": "plague_bell"}, "targeting": "none", "scope": "ALL CREATURES"},

	# ═══════════════════════════════════════════
	#  4-COST POWERHOUSES (require mana banking)
	# ═══════════════════════════════════════════
	"riteforge": {"id": "riteforge", "name": "The Field Forge", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 0, "hp": 5,
		"rarity": "uncommon", "keywords": ["formation"], "formation": 1,
		"desc": "Formation. When played and at each round start: all friendlies get +1 ATK this round.",
		"passive": "riteforge_ramp"},
	"warchief": {"id": "warchief", "name": "Warchief", "type": "creature", "cost": 5, "atk": 2, "hp": 7,
		"rarity": "rare", "ctype": "soldier", "keywords": ["formation", "on_enter"], "formation": 1,
		"desc": "Formation. On-Enter: summon 1/1 Soldiers in adjacent empty lanes. Other Soldiers +1 ATK.",
		"on_enter": {"type": "summon_flank", "value": 1},
		"type_buff": {"ctype": "soldier", "atk": 1}},
	# Soldier keystone (ENDURE): the full line grows teeth. Start of each round, if
	# the front row is full, every friendly Soldier gains Armored + Thorns for the
	# round (temp-keyword grant, cleaned up by _post_combat_cleanup; net-safe via
	# the per-side start-round chokepoint).
	"warden_sergeant": {"id": "warden_sergeant", "name": "Warden-Sergeant", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 2, "hp": 6,
		"rarity": "rare", "keywords": ["formation"], "formation": 1,
		"desc": "Formation. Full front row at round start: Soldiers gain Armored and Thorns this round.",
		"passive": "warden_line"},
	"doom_knight": {"id": "doom_knight", "name": "Doom Knight", "type": "creature", "ctype": "dead", "cost": 6, "atk": 6, "hp": 4,
		"rarity": "uncommon", "keywords": ["swift", "piercing", "doom", "on_death"], "doom": 3,
		"desc": "Swift. Piercing. Doom 3. On-Death: deal 4 damage to enemy face.",
		"on_death": {"type": "damage_face", "value": 4}},
	"inferno": {"id": "inferno", "name": "Inferno", "type": "spell", "cost": 6,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 4 damage to all enemy creatures and 4 damage to enemy face. Exhaust.",
		"spell": {"type": "custom", "id": "inferno"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"overwhelming_force": {"id": "overwhelming_force", "name": "Rout", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Move enemies back and deal 1 damage to each. They cannot attack this round. Exhaust.",
		"spell": {"type": "custom", "id": "rout"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"the_leveler": {"id": "the_leveler", "name": "The Leveler", "type": "creature", "ctype": "bastion", "cost": 6, "atk": 6, "hp": 6,
		"rarity": "rare", "keywords": ["on_enter", "piercing"],
		"desc": "Piercing. On-Enter: move the enemy front row back. Deal 3 damage to each blocked enemy.",
		"on_enter": {"type": "ram_row_back", "value": 3}},

	# ═══════════════════════════════════════════
	#  PYRE / DOOM-BURN — showcases doom / rampage / lifelink.
	#  Fragile bodies that detonate into the enemy face on a short timer
	#  (doom), a snowballing killer (rampage), and a little blood back for
	#  the player (lifelink). Beginner-readable; the Kindler hero draws on
	#  these. Each id reuses an existing portrait (see CardArtAliases /
	#  the matching .png stem) so none render blank.
	# ═══════════════════════════════════════════
	# ─── Doom creatures (ticking bombs) ───────────────────────────────────
	# The Kindler's opener (cinder_pup / kindling / burning_martyr / ash_hound)
	# is the sanctioned exception to the starter contract — these four are
	# rarity "common" rather than "starter". They are `draftable: false` so the
	# exception stays cosmetic: without it `get_pool_by_rarity` defaults
	# draftable to true, and a Recruit slate could hand the Kindler a third
	# Cinder Pup as a *reward*. Nothing else in the game may offer them.
	"cinder_pup": {"id": "cinder_pup", "name": "Cinder Pup", "type": "creature", "ctype": "beast", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "common", "draftable": false, "keywords": ["doom"], "doom": 2,
		"desc": "Doom 2."},
	"kindling": {"id": "kindling", "name": "Kindling", "type": "creature", "ctype": "dead", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "draftable": false, "keywords": ["doom", "on_death"], "doom": 2,
		"desc": "Doom 2. On-Death: deal 2 damage to enemy face.",
		"on_death": {"type": "damage_face", "value": 2}},
	"burning_martyr": {"id": "burning_martyr", "name": "Burning Martyr", "type": "creature", "ctype": "dead", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "common", "draftable": false, "keywords": ["doom", "on_death"], "doom": 3,
		"desc": "Doom 3. On-Death: deal 1 damage to all enemies.",
		"on_death": {"type": "damage_all_enemies", "value": 1}},
	"hellfire_imp": {"id": "hellfire_imp", "name": "Live Coal", "type": "creature", "ctype": "beast", "cost": 4, "atk": 5, "hp": 4,
		"rarity": "common", "keywords": ["doom", "swift"], "doom": 2,
		"desc": "Swift. Doom 2."},
	"cinder_whelp": {"id": "cinder_whelp", "name": "Grinning Blaze", "type": "creature", "ctype": "beast", "cost": 5, "atk": 7, "hp": 5,
		"rarity": "uncommon", "keywords": ["doom", "on_death"], "doom": 2,
		"desc": "Doom 2. On-Death: deal 3 damage to all enemies.",
		"on_death": {"type": "damage_all_enemies", "value": 3}},
	# ─── Rampage (snowball) ───────────────────────────────────────────────
	# draftable: false — see the Kindler-opener note above.
	"ash_hound": {"id": "ash_hound", "name": "Ash Hound", "type": "creature", "ctype": "beast", "cost": 2, "atk": 2, "hp": 1,
		"rarity": "common", "draftable": false, "keywords": ["rampage"], "rampage": 1,
		"desc": "Rampage."},
	"ember_stalker": {"id": "ember_stalker", "name": "Powder Cart", "type": "creature", "ctype": "dead", "cost": 1, "atk": 0, "hp": 5,
		"rarity": "uncommon", "keywords": ["doom", "on_death"], "doom": 3,
		"desc": "Doom 3. On-Death: deal 2 damage to all enemies and detonate your other Doom creatures.",
		"on_death": {"type": "detonate_dooms", "value": 2}},
	# ─── Lifesteal (sustain) ───────────────────────────────────────────────
	"bloodsworn": {"id": "bloodsworn", "name": "Bloodsworn", "type": "creature", "ctype": "dead", "cost": 5, "atk": 4, "hp": 4,
		"rarity": "common", "keywords": ["lifelink", "on_enter"],
		"desc": "Lifesteal. On-Enter: your hero takes 2 damage.",
		"on_enter": {"type": "hero_pay", "value": 2}},
	"cinder_acolyte": {"id": "cinder_acolyte", "name": "Spark-Tender", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": [],
		"desc": "When you cast a spell: this deals 1 damage to the opposing creature.",
		"passive": "spark_on_spell"},
	"ember_warden": {"id": "ember_warden", "name": "Ember Warden", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 1, "hp": 6,
		"rarity": "uncommon", "keywords": [],
		"desc": "When you cast a spell: this gains Shield.",
		"passive": "shield_on_spell"},
	# ─── Pyre spells ──────────────────────────────────────────────────────
	# Art is reused from existing spell frames (id == the stem of a painted
	# spell .png) so the card face is never blank.
	"concentrate": {"id": "concentrate", "name": "Burn Through", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": [], "desc": "Deal 4 damage to a creature. If it dies, deal 4 damage to enemy face.",
		"spell": {"type": "custom", "id": "immolate"}, "targeting": "any_creature"},
	"battle_hymn": {"id": "battle_hymn", "name": "Grass Fire", "type": "spell", "cost": 5,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 3 damage to all enemies. Deal 1 damage to enemy face for each killed. Exhaust.",
		"spell": {"type": "custom", "id": "wildfire"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"powder_store": {"id": "powder_store", "name": "The Powder Store", "type": "spell", "cost": 5,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Cast 3 random spells at random targets. Exhaust.",
		"spell": {"type": "custom", "id": "powder_store"}, "targeting": "none"},
	"case_shot": {"id": "case_shot", "name": "Case Shot", "type": "spell", "cost": 5,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 8 damage split at random among enemy creatures. Exhaust.",
		"spell": {"type": "custom", "id": "case_shot"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"press_gang": {"id": "press_gang", "name": "The Press-Gang", "type": "spell", "cost": 5,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Summon 3 random creatures costing 3 or less. Exhaust.",
		"spell": {"type": "custom", "id": "press_gang"}, "targeting": "none"},
	"mending_light": {"id": "mending_light", "name": "Feed the Dead", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Your Dead gain Lifesteal this fight.",
		"spell": {"type": "custom", "id": "censer_light"}, "targeting": "none", "scope": "YOUR DEAD"},

	# ═══════════════════════════════════════════
	#  DISCOVER CARDS — pick 1 of 3 random options.
	#
	#  Discover is a flexible-tutor / value-engine mechanic borrowed from
	#  Hearthstone (Cabal Acolyte, Stonehill Defender) and Cross Blitz. Each
	#  card filters its pool differently so it has a clear identity:
	#    Lost Tome — random common spell (cheap fixer)
	#    Scholar — random spell on a body (tempo + value)
	#    War Council — any card of any rarity (universal flex)
	#    Treasure Hunter — random rare (jackpot ticket)
	#  The picker UI is StS-style (modal, 3 cards, click to pick).
	# ═══════════════════════════════════════════
	"lost_tome": {"id": "lost_tome", "name": "Torn Pages", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": ["exhaust"],
		"desc": "Discover a common spell. It costs 1 less. Exhaust.",
		"spell": {"type": "custom", "id": "lost_tome"}, "targeting": "none"},
	"scholar": {"id": "scholar", "name": "Scholar", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: Discover a spell. It costs 1 less.",
		"on_enter": {"type": "discover", "type_filter": "spell", "rarity_filter": ""}},
	"war_council": {"id": "war_council", "name": "War Council", "type": "spell", "cost": 3,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Discover any card. It costs 1 less. Exhaust.",
		"spell": {"type": "custom", "id": "war_council"}, "targeting": "none"},
	"treasure_hunter": {"id": "treasure_hunter", "name": "The Looter", "type": "creature", "ctype": "stray", "cost": 5, "atk": 4, "hp": 6,
		"rarity": "rare", "keywords": ["on_enter"],
		"desc": "On-Enter: Discover a rare card. It costs 1 less.",
		"on_enter": {"type": "discover", "type_filter": "any", "rarity_filter": "rare"}},

	# ═══════════════════════════════════════════
	#  2026-07-07 "MAKE IT FUN" SLATE — six designs that hook systems the pool
	#  underused: the back row (Trebuchet, Rat Piper), the dismissal action
	#  (The Volunteer), the persistent hand (Slow Match), the run's Roll of
	#  the Fallen (Muster the Fallen), and honest table-flip gambling (Petard).
	# ═══════════════════════════════════════════
	"rat_piper": {"id": "rat_piper", "name": "Rat Piper", "type": "creature", "ctype": "beast", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": [],
		"desc": "When played: summon a 1/1 Rat in this lane's back row.",
		"on_play": {"type": "summon_back", "atk": 1, "hp": 1}},
	"slow_match": {"id": "slow_match", "name": "Slow Match", "type": "spell", "cost": 3,
		"rarity": "common", "keywords": [],
		"desc": "Deal 2 damage to a creature, plus 1 per turn it waited in your hand (max +4).",
		"spell": {"type": "custom", "id": "slow_match"}, "targeting": "any_creature"},
	"petard": {"id": "petard", "name": "The Petard", "type": "spell", "cost": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "Deal 5 damage to a creature and 2 damage to adjacent creatures in its row.",
		"spell": {"type": "custom", "id": "petard"}, "targeting": "any_creature"},
	"volunteer": {"id": "volunteer", "name": "The Volunteer", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift"], "dismiss_muster": true,
		"desc": "Swift. When discarded: summon a copy in your first empty lane."},
	"trebuchet": {"id": "trebuchet", "name": "Trebuchet", "type": "creature", "ctype": "bastion", "cost": 4, "atk": 0, "hp": 9,
		"rarity": "uncommon", "keywords": [],
		"desc": "End of each round: if this is in the back row, deal 3 damage to enemy face.",
		"passive": "trebuchet_volley"},
	"muster_fallen": {"id": "muster_fallen", "name": "Raise the Fallen", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Summon one 1/1 Shade per name on the Roll of the Fallen (min 1, max 4). Exhaust.",
		"spell": {"type": "custom", "id": "muster_fallen"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  2026-07-09 REMOVAL SLATE — Into-the-Breach push physics. One shared rule
	#  the player learns once: a pushed creature that hits the field's edge or
	#  another body CRASHES — each party takes the card's printed crash damage
	#  (see Combat._flank_push; structures block but never move or take crash
	#  damage). Shove (reworked the same day) is the 2-damage common teacher;
	#  Scatter crashes at 2 across the whole line; Sapper's Charge is ALL
	#  physics — 1 scorch, throws crash at 4 — the edge does the killing.
	# ═══════════════════════════════════════════
	"sappers_charge": {"id": "sappers_charge", "name": "Sapper's Charge", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": [],
		"desc": "Deal 1 damage to an enemy. Push adjacent enemies out. If blocked, deal 4 damage to both.",
		"spell": {"type": "custom", "id": "sappers_charge"}, "targeting": "enemy_creature"},
	# ── COUNTERORDERS (2026-07-30) ───────────────────────────────────────────
	# Enemy intents are the game's most expensive piece of legibility work and,
	# until this slate, nothing in the player's hand could act on one. These three
	# make the badge into gameplay: each pays extra against an enemy WEARING AN
	# ORDER — any intent but plain ATTACK, i.e. exactly the cases that print a
	# badge, so the condition is always on screen. All three floor to a plain,
	# fair card when the foe is simply swinging (no dead draws), and all three are
	# skirmish-denylisted because a human opponent has no orders to catch.
	"counterorders": {"id": "counterorders", "name": "Counterorders", "type": "spell", "cost": 2,
		"rarity": "common", "keywords": [],
		"desc": "Deal 3 damage to an enemy. Deal 3 more if it is under an order.",
		"spell": {"type": "custom", "id": "counterorders"}, "targeting": "enemy_creature"},
	"order_breaker": {"id": "order_breaker", "name": "The Order-Breaker", "type": "creature", "ctype": "stray", "cost": 2, "atk": 3, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: deal 4 damage to the opposing creature if it is under an order.",
		"on_enter": {"type": "strike_the_order", "value": 4}},
	"the_interpreter": {"id": "the_interpreter", "name": "The Interpreter", "type": "creature", "ctype": "stray", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "rare", "keywords": [],
		"desc": "While this stands, a friendly that kills an enemy under an order gains +1/+1.",
		"passive": "read_the_orders"},
	"ballista_bolt": {"id": "ballista_bolt", "name": "Ballista Bolt", "type": "spell", "cost": 4,
		"rarity": "common", "keywords": [],
		"desc": "Deal 5 damage to an enemy. Excess hits the creature behind it, then enemy face.",
		"spell": {"type": "custom", "id": "ballista_bolt"}, "targeting": "enemy_creature"},
	"scatter_line": {"id": "scatter_line", "name": "Scatter the Line", "type": "spell", "cost": 4,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Move all enemies toward the nearest edge. If blocked, deal 2 damage to both. Exhaust.",
		"spell": {"type": "custom", "id": "scatter_line"}, "targeting": "none", "scope": "ALL ENEMIES"},
	"close_ranks": {"id": "close_ranks", "name": "The Pincer", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": [],
		"desc": "Move all enemies toward the center. If blocked, deal 2 damage to both.",
		"spell": {"type": "custom", "id": "close_ranks"}, "targeting": "none", "scope": "ALL ENEMIES"},

	# ═══════════════════════════════════════════
	#  2026-07-13 "STOLEN CLASSICS" SLATE — beloved shapes from the genre's
	#  hall of fame, retold in Burning Meadow verbs:
	#    Grave Clutch — the egg that wants to die (HS Nerubian Egg; sacrifice
	#      spells and the every-round clash both crack it open).
	#    Pressed Man — over-muscled 1-drop whose death pays the FOE back
	#      (HS Zombie Chow; the bill is real against 9-23 HP faces).
	#    The Undying — permanently +1/+1 every time it falls, all run
	#      (Inscryption Ouroboros / StS Feed; rides the card-upgrade mod stack).
	#    The Long Roll — the highlander payoff (HS Reno Jackson; the sutler's
	#      buy-back is the deck-thinning enabler).
	#    Wolf-Pits — hidden traps vs the NEXT enemy arrivals (trap-card
	#      fiction; hooks the end of Combat._place_enemy_card).
	#    The Informer — read the foe's next arrivals, strike one from the
	#      muster (MtG Cabal Therapy vs the encounter deck; Discover modal).
	#    Forgefire — every card in hand gains its "+" for this fight
	#      (StS Apotheosis; folds RunState._apply_plus_upgrade in combat).
	#  Solo-campaign designs: all but Grave Clutch are SKIRMISH_DENYLISTed.
	# ═══════════════════════════════════════════
	"grave_clutch": {"id": "grave_clutch", "name": "Grave Clutch", "type": "creature", "ctype": "dead", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death"],
		"desc": "On-Death: summon a 4/4 token in this lane.",
		"on_death": {"type": "summon", "atk": 4, "hp": 4}},
	"pressed_man": {"id": "pressed_man", "name": "Pressed Man", "type": "creature", "ctype": "soldier", "cost": 4, "atk": 4, "hp": 4,
		"rarity": "common", "keywords": ["on_death"],
		"desc": "On-Death: the enemy hero heals 3 HP.",
		"on_death": {"type": "heal_enemy_face", "value": 3}},
	"the_undying": {"id": "the_undying", "name": "The Undying", "type": "creature", "ctype": "dead", "cost": 3, "atk": 4, "hp": 3,
		"rarity": "rare", "keywords": ["on_death"],
		"desc": "On-Death: this card gains +1/+1 for the rest of the run.",
		"on_death": {"type": "undying_grow"}},
	"long_roll": {"id": "long_roll", "name": "The Long Roll", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Heal your hero 5 HP, or 12 HP if every card in your deck has a unique name. Exhaust.",
		"spell": {"type": "custom", "id": "long_roll"}, "targeting": "none"},
	"wolf_pits": {"id": "wolf_pits", "name": "Wolf-Pits", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "The next 2 enemy arrivals take 3 damage when placed.",
		"spell": {"type": "custom", "id": "wolf_pits"}, "targeting": "none"},
	"informer": {"id": "informer", "name": "The Informer", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "View the next 3 enemy arrivals. Choose 1 to remove from this fight. Exhaust.",
		"spell": {"type": "custom", "id": "informer"}, "targeting": "none"},
	"forgefire": {"id": "forgefire", "name": "Forgefire", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Forge every card in your hand for this fight. Exhaust.",
		"spell": {"type": "custom", "id": "forgefire"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  2026-07-20 FUN-LENS SLATE — three lenticular commons, each built on a
	#  different research finding AND on this game's own playlog telemetry
	#  (63-74% of creatures die the round they are played, so "while it stands"
	#  value is fake and banked/on-death value is real — see the smart-sim memo).
	#    Pike Square  — lenticular: eight words, all the depth is WHERE.
	#    Grave-Goods  — enabler, not payoff; turns the guaranteed death into ramp.
	#    Last Levy    — anti-win-more: strongest on the turn you are losing.
	# ═══════════════════════════════════════════
	"pike_square": {"id": "pike_square", "name": "Pike Square", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": [], "desc": "While a friendly is adjacent: +2 ATK and Thorns.",
		"passive": "square_thorns"},
	"grave_goods": {"id": "grave_goods", "name": "Grave-Goods", "type": "creature", "ctype": "dead", "cost": 1, "atk": 0, "hp": 2,
		"rarity": "common", "keywords": ["on_death"], "desc": "On-Death: the friendly in front of this gains +2/+2 this fight.",
		"on_death": {"type": "buff_in_front", "atk": 2, "hp": 2}},
	"last_levy": {"id": "last_levy", "name": "Last Recruit", "type": "creature", "ctype": "soldier", "cost": 3, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-Enter: gain +1/+1 for each creature the enemy has more than you.",
		"on_enter": {"type": "buff_per_deficit", "atk": 1, "hp": 1}},

	# ═══════════════════════════════════════════
	#  2026-07-16 INTEREST SLATE — wagers, battlefield memory, delayed lane
	#  control, and lateral manoeuvre. These share one lane-change dispatch;
	#  the campaign-only economy / Roll / delayed-state designs stay out of net.
	# ═══════════════════════════════════════════
	"sword_on_credit": {"id": "sword_on_credit", "name": "Sword on Credit", "type": "creature", "ctype": "stray", "cost": 4, "atk": 4, "hp": 6,
		"rarity": "uncommon", "keywords": [],
		"desc": "Start of your next turn: pay 2 Command or this creature moves to the enemy side."},
	"crew_mangonel": {"id": "crew_mangonel", "name": "Engine Crew", "type": "creature", "ctype": "bastion", "cost": 3, "atk": 1, "hp": 6,
		"rarity": "rare", "keywords": [], "passive": "mangonel_crew",
		"desc": "An adjacent friendly's death deals its printed HP to the opposing creature or face."},
	"pay_wagon": {"id": "pay_wagon", "name": "The Pay-Wagon", "type": "creature", "ctype": "stray", "cost": 2, "atk": 0, "hp": 6,
		"rarity": "rare", "keywords": [],
		"desc": "When played: load up to 20 gold. If it lives, gain 1.5x back. If it dies, lose it.",
		"on_play": {"type": "load_pay_wagon"}},
	"pallbearers": {"id": "pallbearers", "name": "The Pallbearers", "type": "creature", "ctype": "dead", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": [],
		"desc": "When played: take a name off the Roll of the Fallen. Gain its printed ATK and HP.",
		"on_play": {"type": "pallbearers"}},
	"gallows_writ": {"id": "gallows_writ", "name": "Death Sentence", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Choose a lane. At the end of next round, every creature in it dies. Exhaust.",
		"spell": {"type": "custom", "id": "gallows_writ"}, "targeting": "lane"},
	"salted_ground": {"id": "salted_ground", "name": "Salted Ground", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "Choose a lane. Enemies cannot arrive there for 2 rounds.",
		"spell": {"type": "custom", "id": "salted_ground"}, "targeting": "lane"},
	"body_snatcher": {"id": "body_snatcher", "name": "Body-Snatcher", "type": "creature", "ctype": "dead", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [], "passive": "body_snatcher",
		"desc": "The first enemy to die in this lane rises on your side, in the back row."},
	"scapegoat": {"id": "scapegoat", "name": "Scapegoat", "type": "creature", "ctype": "beast", "cost": 1, "atk": 0, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "When played: move all damage from your other creatures onto this. It may die.",
		"on_play": {"type": "absorb_friendly_wounds"}},
	"understudy": {"id": "understudy", "name": "The Understudy", "type": "creature", "ctype": "stray", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [], "passive": "understudy",
		"desc": "When the friendly in front dies: move this forward and gain its ATK this fight."},
	"mentioned_dispatches": {"id": "mentioned_dispatches", "name": "Mentioned in Dispatches", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [],
		"desc": "A friendly creature immediately deals its ATK as damage to an enemy creature.",
		"spell": {"type": "custom", "id": "mentioned_dispatches"}, "targeting": "friendly_then_enemy"},
	"drill_serjeant": {"id": "drill_serjeant", "name": "Drill Sergeant", "type": "creature", "ctype": "soldier", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "When played: move your creatures 1 lane right. The last lane wraps around.",
		"on_play": {"type": "wheel_right"}},
	"crossed_orders": {"id": "crossed_orders", "name": "Crossed Orders", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "Two enemy creatures trade places.",
		"spell": {"type": "custom", "id": "crossed_orders"}, "targeting": "two_enemies"},
	"wheeling_lancer": {"id": "wheeling_lancer", "name": "Wheeling Lancer", "type": "creature", "ctype": "stray", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": [], "passive": "wheeling_lancer",
		"desc": "When this changes lanes: strike the enemy now facing it."},
	"rolling_tower": {"id": "rolling_tower", "name": "The Rolling Tower", "type": "creature", "ctype": "bastion", "cost": 4, "atk": 0, "hp": 9,
		"rarity": "rare", "keywords": [], "passive": "rolling_tower",
		"desc": "When this changes lanes: deal 3 damage to the enemy now facing it."},
	"flanking_order": {"id": "flanking_order", "name": "Flanking Order", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [],
		"desc": "Move a friendly to an adjacent lane. If unopposed, it deals its ATK to enemy face.",
		"spell": {"type": "custom", "id": "flanking_order"}, "targeting": "friendly_lane"},
	"hook_and_chain": {"id": "hook_and_chain", "name": "Hook-and-Chain", "type": "creature", "ctype": "bastion", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "When played: move an enemy from an adjacent lane into this lane.",
		"on_play": {"type": "drag_adjacent_enemy"}},
	# (Wave 2 of this slate — 8 damage-leaning steals: Grand Melee / Giantfall /
	# Blood Kin / Pit Brawler / The Farmer's Son / The Great Bombard / The
	# Whisper-Widow / The Quartermaster — was built 2026-07-13 and REVERTED the
	# same day: user verdict "weird for my game", redirected the sweep to
	# NON-DAMAGE effects. The turncoat conversion refactor it introduced
	# (_desert_enemy_to_player / _spawn_player_body in Combat.gd) stays live.)

	# ═══════════════════════════════════════════
	#  2026-07-16 RARITY-FLOOR VANILLAS — one honest statline per tribe, zero
	#  text. The common bucket had thinned to 64 vs 93 uncommons, so nearly
	#  every offer read as a build decision; these are the plain soldiery
	#  between the specialists (mule/lancer plain-common precedent — the tribe
	#  stamp IS the identity now that keystones/type_buffs read it). Bodies
	#  sit exactly on the vanilla curve (c1=4, c2=6, c3=8 total stats).
	# ═══════════════════════════════════════════
	"man_at_arms": {"id": "man_at_arms", "name": "Man-at-Arms", "type": "creature", "ctype": "soldier", "cost": 5, "atk": 3, "hp": 5,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift."},
	"war_boar": {"id": "war_boar", "name": "War Boar", "type": "creature", "ctype": "beast", "cost": 4, "atk": 5, "hp": 3,
		"rarity": "common", "keywords": ["charge"], "desc": "Charge."},
	"grave_levy": {"id": "grave_levy", "name": "Grave Soldier", "type": "creature", "ctype": "dead", "cost": 3, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["charge"], "desc": "Charge."},
	"hexwright": {"id": "hexwright", "name": "Hexwright", "type": "creature", "ctype": "warlock", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "common", "keywords": [], "desc": ""},
	"curtain_wall": {"id": "curtain_wall", "name": "Curtain Wall", "type": "creature", "ctype": "bastion", "cost": 4, "atk": 1, "hp": 8,
		"rarity": "common", "keywords": [], "desc": ""},
	"freelance": {"id": "freelance", "name": "Hired Blade", "type": "creature", "ctype": "stray", "cost": 4, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift."},

	# ── Curses (added by events / boss relics / encounter passives / ascension). ──
	# Six branded variants instead of one dead card twice. Two axes:
	#   curse_playable: true  → the card CAN be dragged out (Combat's curse gate
	#     lets it through); pair with Exhaust so playing it purges it at a price.
	#   curse_on_draw: {type, value} → sting fired by Combat._draw_card the moment
	#     it hits the hand (lose_command / hero_damage / lose_gold). Attributed
	#     with floating text so the pain is legible, per the threats-loud rule.
	# Plain clog curses have neither key. All stay rarity "starter" so the
	# discover pool and the skirmish draft pool skip them.
	"curse": {"id": "curse", "name": "Curse", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [], "desc": "Cannot be played.",
		"spell": {"type": "none"}, "targeting": "none"},
	"wound": {"id": "wound", "name": "Wound", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": ["retain"],
		"desc": "Retain. Cannot be played.",
		"spell": {"type": "none"}, "targeting": "none"},
	"craven": {"id": "craven", "name": "Faint Heart", "type": "spell", "cost": 2,
		"rarity": "starter", "keywords": ["exhaust"], "curse_playable": true,
		"desc": "Exhaust. Playing this has no other effect.",
		"spell": {"type": "none"}, "targeting": "none"},
	"deserters_mark": {"id": "deserters_mark", "name": "Deserter's Mark", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [],
		"curse_on_draw": {"type": "lose_command", "value": 1},
		"desc": "Cannot be played. When drawn: lose 1 Command this turn.",
		"spell": {"type": "none"}, "targeting": "none"},
	"grave_debt": {"id": "grave_debt", "name": "Grave-Debt", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [],
		"curse_on_draw": {"type": "hero_damage", "value": 1},
		"desc": "Cannot be played. When drawn: your hero takes 1 damage.",
		"spell": {"type": "none"}, "targeting": "none"},
	"war_debt": {"id": "war_debt", "name": "War-Debt", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [],
		"curse_on_draw": {"type": "lose_gold", "value": 2},
		"desc": "Cannot be played. When drawn: lose 2 gold.",
		"spell": {"type": "none"}, "targeting": "none"},
	# The Coin — handed to whoever goes SECOND in a skirmish (Hearthstone-style),
	# in place of a raw extra opening card. Never drafted or discovered (rarity
	# "starter" is skipped by the discover pool, and its custom id is deliberately
	# kept out of SkirmishState.NET_SPELL_CUSTOMS so the draft pool excludes it);
	# Combat hands it over as a synthetic hand card (uid -1) that vanishes on play.
	"coin": {"id": "coin", "name": "The Coin", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Gain 1 Command this turn.",
		"spell": {"type": "custom", "id": "coin"}, "targeting": "none"},
}

const CURSE_IDS: Array[String] = ["curse", "wound",
	"craven", "deserters_mark", "grave_debt", "war_debt"]

# Weights for random_curse_id. Plain Curse stays the most common outcome;
# Wound (a PERMANENT dead slot — the cruelest) stays the rarest.
const _CURSE_WEIGHTS: Dictionary = {
	"curse": 3, "wound": 1, "craven": 2,
	"deserters_mark": 2, "grave_debt": 2, "war_debt": 2,
}


# ═══════════════════════════════════════════════════════════════════════════
#  UPGRADES — per-card "+" definitions (StS-style)
# ═══════════════════════════════════════════════════════════════════════════
# Every draftable card has a hand-crafted upgrade. The rest-site Upgrade
# action applies these deltas via RunState._apply_upgrade("plus", ...).
# Cards with no entry here fall back to a default upgrade in get_plus_upgrade()
# (+1/+1 for creatures, -1 cost for spells) so missing entries never crash.
#
# Field reference (all optional, only non-zero/non-empty deltas merge):
#   atk, hp, cost                       creature stats / mana cost delta
#   value                               spell.value delta (non-custom spells)
#   dmg_bonus                           custom-spell damage bonus that
#                                       _resolve_custom_spell reads via
#                                       card_data.get("dmg_bonus", 0)
#   add_keywords / remove_keywords      Array[String]
#   on_enter_value, on_death_value,
#   on_play_value, on_play_atk_gain     delta for sub-effect .value fields
#   adj_buff_atk, adj_buff_hp           delta for adj_buff.atk / .hp
#   wither, extra_damage                delta on the top-level integer field
#   slay_draw, slay_gold, slay_mana     custom-spell slay payoff bumps
#                                       (read by specific resolvers)
#   extra_draw, extra_mana              custom-spell tail bonuses
#                                       (read by specific resolvers)
#   desc                                replace description text outright
const UPGRADES: Dictionary = {
	# ─── 2026-07-20 fun-lens slate ────────────────────────────────────────
	# Each "+" deepens the card's OWN question rather than adding a second one:
	# the square holds a wider frontage, the goods pay a bigger bequest, the
	# levy musters harder off an empty field.
	"pike_square":    {"hp": 2},
	"grave_goods":    {"hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: the friendly in front of this gains +3/+3 this fight."},
	"last_levy":      {"atk": 1, "hp": 1},
	# ─── Starters ─────────────────────────────────────────────────────────
	"goblin":         {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to enemy face."},
	"brute":          {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to the opposing creature."},
	"troll":          {"atk": 1, "hp": 1},
	"sprite":         {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When played: adjacent friendlies get +2 ATK this round."},
	"naga":           {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When played: deal 3 damage to the opposing creature."},
	"ratling":        {"atk": 1, "hp": 1, "on_death_value": 1,
		"desc": "Wither 1. On-Death: deal 2 damage to the opposing lane."},
	"strike":         {"value": 3,
		"desc": "Deal 6 damage to a creature."},
	"fireball":       {"value": 2,
		"desc": "Deal 4 damage to enemy face."},
	"levy_rider":     {"atk": 1, "hp": 1,
		"desc": "Swift."},
	"palisade":       {"atk": 0, "hp": 2,
		"desc": "Guardian."},
	"mourner":        {"atk": 1, "hp": 1, "on_death_value": 1,
		"desc": "On-Death: gain 2 Command next turn."},
	"spark":          {"value": 1,
		"desc": "Deal 3 damage to any target. Exhaust."},
	"line_marker":    {"atk": 1, "hp": 1,
		"desc": "Guardian."},
	"loose_horse":    {"atk": 1, "hp": 1,
		"desc": "Swift."},
	"ash_marker":     {"atk": 1, "hp": 1, "on_death_value": 1,
		"desc": "On-Death: deal 2 damage to enemy face."},
	"hedge_caster":   {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to the opposing creature."},
	"marker_stone":   {"hp": 2,
		"desc": "Thorns."},
	"free_lance":     {"atk": 1, "hp": 1, "on_enter_value": 5,
		"desc": "On-Enter: gain 15 gold."},
	"grasswake_lancer": {"atk": 1, "hp": 1},
	"trail_scout": {"atk": 1, "hp": 1},
	"spur_forward": {"atk_bonus": 1, "desc": "Move a friendly creature. It gets +3 ATK and Swift this round. Exhaust."},
	"cut_them_off": {"dmg_bonus": 1, "desc": "Deal 3 damage to an enemy. Deal 5 if you moved a friendly this round."},
	"rank_spearman": {"atk": 1, "hp": 1},
	"wall_tender": {"atk": 1, "hp": 1, "on_play_value": 1, "desc": "When played: heal adjacent friendlies 3 HP."},
	"standard_page": {"hp": 1, "adj_buff_hp": 1, "desc": "Adjacent friendlies have +2 HP."},
	"close_ranks_order": {"hp_bonus": 1, "desc": "A friendly and adjacent friendlies gain +2 HP this fight. Exhaust."},
	"grave_goods_levy": {"hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: another friendly in this column gains +2/+2 this fight."},
	"debt_guard": {"atk": 1, "hp": 1},
	# Was {"cost": -1}; the rescale put the base at 1, where a discount cannot
	# land, so the forge stopped doing anything at all. Dropping Exhaust is the
	# upgrade the card was always reaching for — the will can be read every round
	# instead of once — and it uses the same allow-listed lever as Echo's forge.
	"read_the_will": {"remove_keywords": ["exhaust"],
		"desc": "Trigger a friendly creature's On-Death effect without killing it."},
	"last_due": {"dmg_bonus": 2, "desc": "Sacrifice a friendly. Deal 4 damage opposite it, or to enemy face if empty. Exhaust."},
	"lens_apprentice": {"atk": 1, "hp": 1},
	"mirror_guard": {"atk": 1, "hp": 1},
	"glass_savant": {"atk": 1, "hp": 1, "spell_ping_bonus": 1,
		"desc": "Your 2nd differently named spell each round: deal 2 damage to the opposing creature."},
	"star_chart": {"extra_reveal": 1, "desc": "Reveal the next 2 enemy arrivals. Exhaust."},
	"countermarch_levy": {"hp_bonus": 1, "desc": "Move a friendly to the other row, swapping if taken. It gains +2 HP. Exhaust."},
	"fuse_tender": {"atk": 1, "hp": 1, "doom_atk_bonus": 1,
		"desc": "When played: adjacent Doom friendlies gain +2 ATK this fight and 1 round of fuse."},
	"cinderward": {"atk": 1, "hp": 1},
	"touchpaper": {"doom_tick": 1, "desc": "Reduce a friendly creature's Doom by 2. If it reaches 0, detonate it. Exhaust."},

	# ─── Common creatures ─────────────────────────────────────────────────
	"crystal_sentry": {"atk": 1, "hp": 1,
		"desc": "Shield. When played: adjacent friendlies gain Shield."},
	"hound":          {"atk": 1, "hp": 1,
		"desc": "When played: return your last discarded spell to your hand. If none, draw 1."},
	"shieldbearer":   {"atk": 1, "hp": 1,
		"desc": "Shield. When this loses Shield: gain +3 ATK this fight."},
	"pikeman":        {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When played: move the opposing creature back. If blocked, deal 3 damage to it."},
	"lookout":        {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Swift. Front row: gain +2 ATK this round. Back row: reveal the next enemy arrival."},
	"warding_stone":  {"on_enter_value": 1, "add_keywords": ["thorns"],
		"desc": "Guardian. Thorns. On-Enter: your Bastions gain +3 HP this fight."},
	"hexblade":       {"atk": 1, "hp": 1, "add_keywords": ["sniper"],
		"desc": "Sniper. +1 ATK per spell cast this round."},
	"harpy":          {"atk": 1, "hp": 1,
		"desc": "Swift. When played: move the opposing back-row enemy to the front row."},
	"thornguard":     {"atk": 1, "hp": 2, "on_play_value": 1,
		"desc": "Thorns. On-Death: deal 1 damage to all enemies."},
	"raven":          {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Sniper. When played: deal 3 damage to a random enemy back-row creature."},
	"squire_captain": {"atk": 1, "hp": 2,
		"desc": "Damage to the friendly in this column's other row is dealt to this creature instead."},
	"plague_rat":     {"atk": 1, "hp": 1, "add_keywords": ["lifelink"],
		"desc": "Poison. Lifesteal."},
	"torchbearer":    {"atk": 1, "hp": 1, "adj_buff_atk": 1, "add_keywords": ["formation"],
		"desc": "Formation. Adjacent friendlies +2 ATK."},
	"gravedigger":    {"atk": 1, "hp": 1,
		"desc": "When a friendly creature dies on your turn: this gains +2/+2."},
	"bloodhound":     {"atk": 1, "hp": 1, "on_play_value": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to the opposing creature and draw 1."},
	"scavenger":      {"atk": 1, "hp": 1, "on_death_value": 2,
		"desc": "Swift. On-Death: gain 6 gold."},
	"ironhide_anvil": {"atk": 0, "hp": 2,
		"desc": "Guardian. When struck: deal the same damage to the attacker."},
	"bramble_stockade": {"atk": 0, "hp": 2, "add_keywords": ["guardian"],
		"desc": "Guardian. Thorns. When this survives a hit: summon a 1/1 in an adjacent empty lane."},
	"heartwood_elder": {"atk": 1, "hp": 1,
		"desc": "On-Enter: gain +1/+1 for each other friendly Beast."},
	"bastion_lord":   {"atk": 1, "hp": 2,
		"desc": "When a friendly creature survives a hit: deal 1 damage to enemy face."},
	"tallow_doll":    {"atk": 1, "hp": 1,
		"desc": "On-Death: the opposing creature attacks its nearest ally. If alone, it attacks enemy face."},
	"skirmisher":     {"atk": 1, "hp": 1,
		"desc": "Swift. Slay: heal your hero 3 HP."},
	"lancer":         {"atk": 1, "hp": 1,
		"desc": "Overrun 2."},

	# Armament upgrades are explicit so they keep their intended Command costs.
	# Combat._apply_armament reads the forged flag and applies these live bumps.
	"hooked_pike":     {"desc": "Bearer gets +4 ATK and Piercing."},
	"tower_shield":    {"desc": "Bearer gets +7 HP and Armored."},
	"grave_bell":      {"desc": "Bearer gets +1/+1. Its On-Death effects trigger twice."},
	"witchbrand":      {"desc": "Bearer gets +1/+1. After you cast a spell, it gets +1/+1 this fight."},
	"forked_spear":    {"desc": "Bearer gets +2 ATK and also strikes adjacent enemies."},
	"repeating_arbalest": {"desc": "Bearer gets +2 HP, Last Stand, and attacks twice."},

	# ─── Common spells ────────────────────────────────────────────────────
	"slash":          {"dmg_bonus": 1,
		"desc": "Deal 3 damage to an enemy and move it back. If blocked, deal 2 more damage."},
	"shield_wall":    {   # resolver reads is_upgraded: the back row locks in too
		"desc": "All friendly creatures gain Shield."},
	"war_cry":        {"dmg_bonus": 1,
		"desc": "All friendlies gain Swift and +1 ATK this round."},
	"provision":      {"remove_keywords": ["exhaust"],
		"desc": "Summon a 2/1 Soldier in an empty lane."},
	"patch_up":       {"cost": -1,
		"desc": "Fully heal a friendly creature. It gains Last Stand."},
	"flame_bolt":     {"dmg_bonus": 2,
		"desc": "Deal 5 damage to enemy face. If you already cast a spell this turn, deal 7 instead."},
	"shove":          {"dmg_bonus": 2,
		"desc": "Move an enemy 1 lane toward the nearest edge and deal 2 damage. If blocked, both take 2."},
	"gambit":         {"add_keywords": ["retain"],
		"desc": "Discard up to 3 cards, then draw that many. Retain."},
	"blood_tithe":    {"dmg_bonus": 2,
		"desc": "Deal 6 damage to enemy face. Take 2 damage yourself."},
	"reckless_charge": {"dmg_bonus": 2,
		"desc": "Deal 4 damage to any target. You may Exhaust a Curse from your hand to deal 8 instead."},
	"quick_shot":     {"dmg_bonus": 2,
		"desc": "Deal 3 damage to any target. Slay: draw 1. Exhaust."},
	"frost_bolt":     {"dmg_bonus": 2,
		"desc": "Deal 2 damage to an enemy creature. It cannot attack this round."},
	"adrenaline":     {
		"desc": "Move a friendly to its other row. It and adjacent friendlies gain Shield. Exhaust."},
	"hex":            {"dmg_bonus": 1,
		"desc": "Remove an enemy's keywords. Deal 5 damage if it had any; otherwise deal 2."},
	"ricochet":       {"dmg_bonus": 1,
		"desc": "Deal 3 damage to each back-row enemy. If that row is empty, hit the front instead."},

	# ─── Uncommon creatures ───────────────────────────────────────────────
	"battle_drummer": {"atk": 1, "hp": 1, "add_keywords": ["swift"],
		"desc": "Armored. Swift. Adjacent friendlies have Swift."},
	"witch":          {"atk": 1, "hp": 1,
		"desc": "Your first spell each turn costs 1 less."},
	"duelist":        {"atk": 1, "hp": 1,
		"desc": "On-Enter: gain +1/+1 this fight for each unspent Command."},
	"griffin":        {"atk": 1, "hp": 1,
		"desc": "Swift. On-Death: return this creature to your hand. Once per fight."},
	"revenant":       {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Death: return this creature to play at full HP. Once per fight."},
	"berserker":      {"atk": 1, "hp": 2,
		"desc": "Lifesteal. When this survives a hit: gain +3 ATK."},
	"mule":           {"atk": 1, "hp": 1,
		"desc": "Summon."},
	"husk":           {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "Guardian. Lifesteal. On-Death: summon a 3/3 token in this lane."},
	"basilisk":       {"atk": 1, "hp": 1,
		"desc": "Poison. Thorns. Any creature damaged by its Thorns dies."},
	"necromancer":    {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: summon a 3/3 token in each row of this lane."},
	"carrion_priest": {"atk": 1, "hp": 1,
		"desc": "Guardian. When a friendly dies: deal 2 damage to enemy face and heal your hero 1 HP."},
	"gravecaller":    {"atk": 1, "hp": 1,
		"desc": "On-Enter: gain +1/+1 for each friendly that died this turn."},
	"breaker":        {"atk": 1, "hp": 1,
		"desc": "After it attacks, this strikes one adjacent enemy lane, or enemy face if both are empty."},
	"cleave_hound":   {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When this attacks: deal 1 damage to enemy creatures in adjacent lanes."},
	"blood_pyre":     {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When played: sacrifice this creature. Adjacent friendlies get +4 ATK this round. Draw 1."},
	"copycat":        {"atk": 1, "hp": 2,
		"desc": "On-Enter: become a copy of a chosen friendly creature."},
	"familiar":       {"atk": 1, "hp": 1,
		"desc": "On-Enter: Discover a creature. It costs 1 less."},
	"adaptable":      {"atk": 1, "hp": 1, "add_keywords": ["swift"],
		"desc": "Swift. On-Enter: gain Swift, Piercing, Armored, or Thorns (you choose)."},
	"vengeance":      {"atk": 1, "hp": 1, "add_keywords": ["overrun"],
		"desc": "Overrun. When you take face damage: this gains +3 ATK this fight."},
	"iron_bastion":   {"atk": 1, "hp": 2,
		"desc": "The friendly in the other row of this column cannot drop below 1 HP."},
	"leyline_conduit": {"atk": 0, "hp": 2,
		"desc": "Formation. Your first spell each turn: this creature's column gains Shield."},
	"the_glutton":    {"atk": 1, "hp": 1,
		"desc": "Overrun. On-Enter: destroy adjacent friendlies. Gain +3/+3 and their keywords each."},
	"standard_bearer": {"atk": 1, "hp": 1,
		"desc": "Your summoned tokens enter with +2/+2."},
	"shieldmaiden":   {"atk": 1, "hp": 2,
		"desc": "While in the front row, attacks on your face hit this creature instead."},
	"the_apothecary": {"atk": 1, "hp": 1,
		"desc": "When you drink a potion: this gains +3/+3."},
	"emberwright":    {"atk": 1, "hp": 1,
		"desc": "When you cast a spell: deal 3 damage to enemy face."},
	"summoner":       {"atk": 1, "hp": 1,
		"desc": "Guardian. Start of each round: summon a 3/3 token in an adjacent empty lane."},
	"paladin":        {"atk": 1, "hp": 1,
		"desc": "Last Stand. On trigger: your creatures get +3 ATK this fight. Heal your hero 3 HP."},
	"royal_guard":    {"atk": 1, "hp": 1,
		"desc": "Adjacent friendlies take 1 less damage. When this is hit: gain +2 ATK."},
	"ironclad_veteran": {"atk": 1, "hp": 1,
		"desc": "On-Enter: gain +1/+1 for every 2 kills this card has made this run."},
	"sin_eater":      {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When played: Exhaust a Curse from your hand. This gains +3/+3. Draw 1."},
	"glass_knight":   {"atk": 1, "hp": 1,
		"desc": "Shield. Swift. Slay: regain Shield."},
	"doppelganger":   {"atk": 1, "hp": 1,
		"desc": "On-Enter: become a copy of the most recently dead creature."},

	# ─── Uncommon spells ──────────────────────────────────────────────────
	"smite_spell":    {"cost": -1,
		"desc": "A friendly creature attacks twice this round. Each target counterattacks. Exhaust."},
	"inspire":        {   # resolver reads is_upgraded: desertion gate 4 instead of 3
		"desc": "Control an enemy with 4 or less ATK. Otherwise, stop it attacking this round. Exhaust."},
	"ambush":         {"dmg_bonus": 1,
		"desc": "Deal 2 damage to all enemy creatures. Your Swift creatures get +2 ATK this round."},
	"reanimate":      {"dmg_bonus": 1,  # repurposed: revive stat bump
		"desc": "Summon the last enemy to die as a 2/2 with its keywords. If none, your own dead. Exhaust."},
	"charge_spell":   {"cost": -1,
		"desc": "A friendly attacks every opposing lane this round. Each target deals 1 damage back."},
	"offering":       {"extra_draw": 1,
		"desc": "Sacrifice a friendly creature. Its On-Death triggers twice. Draw 1. Exhaust."},
	"grave_pact":     {"dmg_bonus": 2,
		"desc": "Deal 5 damage to a creature. If a friendly died this fight, deal 8 instead."},
	"fuel_the_pyre":  {"dmg_bonus": 2,
		"desc": "Sacrifice a friendly. Deal its ATK + 2 to the opposing creature; if empty, a random enemy."},
	"venom_tip":      {"desc": "A friendly creature gains Poison for the rest of the fight."},
	"pillage":        {"dmg_bonus": 1, "slay_gold": 5,
		"desc": "Deal 3 damage to an enemy creature and 2 damage to enemy face. Slay: gain 15 gold."},
	"echo_spell":     {"remove_keywords": ["exhaust"],
		"desc": "Copy the last spell you cast this turn."},
	"turbo":          {
		"desc": "Give a friendly +5 ATK this round. Detonate its Doom, or give it Doom 2. Exhaust."},
	"recycle":        {"extra_draw": 1,
		"desc": "Exhaust another hand card. Draw cards equal to its cost, then draw 1 more. Exhaust."},
	"dark_pact":      {"dmg_bonus": 1,
		"desc": "Sacrifice a friendly creature. Other friendlies get +2/+2 this fight."},
	"war_chant":      {"desc": "Discard up to 3 cards. Summon a 3/2 Soldier for each. Exhaust."},
	"grave_robbery":  {"cost": -1,
		"desc": "Return the last creature to die to your hand. Exhaust."},
	"soul_swap":      {"dmg_bonus": 2,
		"desc": "An enemy creature swaps its ATK and HP (never below 1 HP), then takes 2 damage."},
	"lay_on_hands":   {"remove_keywords": ["exhaust"],
		"desc": "Your creatures' attacks are poisonous this round."},
	"hoarfrost":      {"cost": -1,
		"desc": "A friendly creature gains Shield. The opposing creature can't attack this round."},
	"holy_smite":     {"cost": -1, "slay_draw": 1,
		"desc": "Deal damage to an enemy creature equal to its missing HP, at least 3. Slay: draw 2."},
	"overwhelming_force": {"dmg_bonus": 1,
		"desc": "Move all enemies back, deal 2 damage to each, and stop them attacking this round. Exhaust."},

	# ─── Rare creatures ───────────────────────────────────────────────────
	"dragon_hatchling": {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to each enemy front-row creature, +1 per other Beast (max 4)."},
	"assassin":       {"atk": 1, "hp": 1,
		"desc": "Swift. When played: destroy the opposing creature, front row first."},
	"hydra":          {"atk": 1, "hp": 1, "rampage": 1,
		"desc": "Rampage 2. Armored. Attacks every opposing lane instead. Each defender counterattacks."},
	"corpse_eater":   {"atk": 1, "hp": 1,
		"desc": "Piercing. When a friendly creature dies: gain +2 ATK."},
	"vampire_lord":   {"hp": 1,
		"desc": "Lifesteal. When another friendly Dead dies: gain its ATK and HP."},
	"chaos_imp":      {"atk": 1, "hp": 1,
		"desc": "On-Enter: cast a random spell costing 1 or less for free. Targets are automatic."},
	"warden_of_graves": {"atk": 1, "hp": 1,
		"desc": "On-Death: summon a 2/2 in its lane. Your creatures' On-Death effects trigger twice."},
	"siege_golem":    {"hp": 2,
		"desc": "Overrun 3. On-Enter: your other Bastions gain Thorns this fight."},
	"old_bones":      {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: return as a 3/3, then as a 2/2, then as a 1/1."},

	# ─── Rare spells ──────────────────────────────────────────────────────
	"earthquake":     {"dmg_bonus": 1,
		"desc": "Deal 3 damage to every creature. Move both front rows back where possible. Exhaust."},
	"kings_command":  {"cost": -1,
		"desc": "All friendlies get +1 ATK this round for each friendly creature. Exhaust."},
	"unholy_bargain": {
		"desc": "Add War-Debt. The round's first non-token death summons a 3/3 Debtor. A 2nd draws 2."},
	"mass_grave":     {"dmg_bonus": 2,
		"desc": "Deal 2 damage to every enemy, plus 1 for each friendly death this fight. Exhaust."},
	"cataclysm":      {"dmg_bonus": 2,
		"desc": "A friendly deals its ATK + 2 in its lane and adjacent lanes. No counterattacks. Exhaust."},
	"apocalypse":     {"dmg_bonus": 1,
		"desc": "Destroy every creature. Summon a 2/2 Shade for each friendly destroyed. Exhaust."},
	"banish":         {"dmg_bonus": 2, "extra_draw": 1,
		"desc": "Remove an enemy with 6 or less HP. Otherwise, deal 6 damage. Draw 1. Exhaust."},
	"time_snare":     {"cost": -1,
		"desc": "Your creatures attack twice this round. Each target counterattacks. Draw 1. Exhaust."},
	"plague_bell":    {"dmg_bonus": 1,
		"desc": "Deal 2 damage to every creature. If any creature dies, repeat this effect. Exhaust."},

	# ─── 4-cost powerhouses ───────────────────────────────────────────────
	"riteforge":      {"hp": 2,
		"desc": "Formation. When played and at each round start: all friendlies get +2 ATK this round."},
	"warchief":       {"type_buff": {"ctype": "soldier", "atk": 2},
		"desc": "Formation. On-Enter: summon 1/1 Soldiers in adjacent empty lanes. Other Soldiers +2 ATK."},
	"warden_sergeant": {"hp": 1,
		"desc": "Formation. At round start with 3+ in front: Soldiers gain Armored and Thorns this round."},
	"bloodmoon_alpha": {"atk": 1, "hp": 1,
		"desc": "Your other Beasts' On-Enter effects trigger twice."},
	"gravepact":      {"hp": 1,
		"desc": "When another friendly dies: summon a 2/2 Wight in your back row. Once per round."},
	"the_sexton":     {"atk": 1, "hp": 1,
		"desc": "On-Enter: this fight, every 2nd other friendly death summons 3 2/2 Wights in the back row."},
	# The four Part C keystones. Each forge loosens the MOMENT's condition rather
	# than only bumping stats — a forged keystone should fire more often, which is
	# the axis the card is actually about.
	"pike_captain":   {"atk": 1, "hp": 1,
		"desc": "3+ in the front row at round start: Soldiers gain +1 ATK and Piercing. Once per fight."},
	"siege_bastion":  {"atk": 1, "hp": 1,
		"desc": "Guardian. On-Enter: this fight, your struck Bastions deal the same damage to the attacker."},
	"the_magister":   {"atk": 1, "hp": 1,
		"desc": "On-Enter: this fight, your 1st spell each round: Warlocks hit the opposing creature for 2."},
	"dire_alpha":     {"atk": 1, "hp": 1,
		"desc": "Each Beast that arrives deals its ATK to the opposing creature."},
	"coven_mother":   {"hp": 1,
		"desc": "When you cast a spell: your Warlocks gain +1 ATK this fight. Heal your hero 1 HP."},
	"siegewright":    {"hp": 1,
		"desc": "Guardian. Thorns. Start of each round: your Bastions gain +2 ATK this fight."},
	"deserter":       {"atk": 1, "hp": 1,
		"desc": "When played: move 1 friendly creature to any empty slot."},
	"sellsword_outrider": {"atk": 1, "hp": 1,
		"desc": "Once each turn this may move for free. After moving, it gains +2 ATK this round."},
	"kingpin":        {"atk": 1, "hp": 1,
		"desc": "Slay: take 1 of the victim's keywords, or move. Your other Strays move on a kill."},
	"doom_knight":    {"atk": 1, "hp": 2, "on_death_value": 2,
		"desc": "Swift. Piercing. Doom 3. On-Death: deal 6 damage to enemy face."},
	"inferno":        {"dmg_bonus": 1,
		"desc": "Deal 5 damage to all enemy creatures and 5 damage to enemy face. Exhaust."},
	"the_leveler":    {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "Piercing. On-Enter: move the enemy front row back. Deal 4 damage to each blocked enemy."},

	# ─── 2026-07-07 fun slate ─────────────────────────────────────────────
	# rat_piper / trebuchet / muster_fallen scale via is_upgraded reads in
	# their resolvers (token size / volley damage); the descs promise exactly
	# those numbers.
	"rat_piper":      {"atk": 1, "hp": 1,
		"desc": "When played: summon a 2/2 Rat in this lane's back row."},
	"slow_match":     {"dmg_bonus": 2,
		"desc": "Deal 4 damage to a creature, plus 1 per turn it waited in your hand (max +4)."},
	"petard":         {"dmg_bonus": 2,
		"desc": "Deal 7 damage to a creature and 4 damage to adjacent creatures in its row."},
	"volunteer":      {"atk": 1, "hp": 1,
		"desc": "Swift. When discarded: summon a copy in your first empty lane."},
	"sappers_charge": {"dmg_bonus": 2,
		"desc": "Deal 1 damage to an enemy. Push adjacent enemies out. If blocked, deal 6 damage to both."},
	# COUNTERORDERS forges sharpen the CONDITIONAL half, not the floor — the card
	# is about reading the badge, so that is the axis worth paying to improve.
	# order_bonus is SET by the fold, not added, so this is the final value (the
	# base card's default is 3). It must also appear in _apply_plus_upgrade's
	# allow-list or it is silently dropped — see the note there.
	"counterorders":  {"order_bonus": 6,
		"desc": "Deal 3 damage to an enemy. Deal 6 more if it is under an order."},
	"order_breaker":  {"atk": 1, "on_enter_value": 2,
		"desc": "On-Enter: deal 6 damage to the opposing creature if it is under an order."},
	"the_interpreter": {"hp": 2,
		"desc": "While this stands, a friendly that kills an enemy under an order gains +1/+1."},
	"ballista_bolt":  {"dmg_bonus": 2,
		"desc": "Deal 7 damage to an enemy. Excess hits the creature behind it, then enemy face."},
	"scatter_line":   {"dmg_bonus": 1,
		"desc": "Move all enemies toward the nearest edge. If blocked, deal 3 damage to both. Exhaust."},
	"close_ranks":    {"dmg_bonus": 1,
		"desc": "Move all enemies toward the center. If blocked, deal 3 damage to both."},
	"trebuchet":      {"hp": 2,
		"desc": "End of each round: if this is in the back row, deal 4 damage to enemy face."},
	"muster_fallen":  {"desc": "Summon one 2/2 Shade per name on the Roll of the Fallen (min 1, max 4). Exhaust."},

	# ─── 2026-07-13 stolen-classics slate ─────────────────────────────────
	"grave_clutch":   {"hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: summon a 5/5 token in this lane."},
	"pressed_man":    {"atk": 1, "hp": 1,
		"desc": "On-Death: the enemy hero heals 3 HP."},
	"the_undying":    {"atk": 1, "hp": 1,
		"desc": "On-Death: this card gains +1/+1 for the rest of the run."},
	"long_roll":      {"desc": "Heal your hero 7 HP, or 16 HP if every card in your deck has a unique name. Exhaust."},
	"wolf_pits":      {"dmg_bonus": 2,
		"desc": "The next 2 enemy arrivals take 5 damage when placed."},
	"informer":       {"cost": -1,
		"desc": "View the next 3 enemy arrivals. Choose 1 to remove from this fight. Exhaust."},
	"forgefire":      {"cost": -1,
		"desc": "Forge every card in your hand for this fight. Exhaust."},

	# ─── 2026-07-16 interest slate ─────────────────────────────────────────
	"sword_on_credit": {"atk": 1, "hp": 1,
		"desc": "Start of your next turn: pay 2 Command or this creature moves to the enemy side."},
	"crew_mangonel":  {"hp": 2,
		"desc": "An adjacent friendly's death deals its printed HP + 2 to the opposing creature or face."},
	"pay_wagon":      {"hp": 2,
		"desc": "When played: load up to 30 gold. If it lives, gain 1.5x back. If it dies, lose it."},
	"pallbearers":    {"atk": 1, "hp": 1,
		"desc": "When played: take a name off the Roll of the Fallen. Gain its printed ATK and HP."},
	"gallows_writ":   {"cost": -1,
		"desc": "Choose a lane. At the end of next round, every creature in it dies. Exhaust."},
	"salted_ground":  {"desc": "Choose a lane. Enemies cannot arrive there for 3 rounds."},
	"body_snatcher":  {"hp": 1,
		"desc": "The first enemy to die in this lane rises on your side as +1/+1, in the back row."},
	"scapegoat":      {"hp": 2,
		"desc": "When played: move all damage from your other creatures onto this. It may die."},
	"understudy":     {"atk": 1, "hp": 1,
		"desc": "When the friendly in front dies: move this forward and gain its ATK this fight."},
	"mentioned_dispatches": {"dmg_bonus": 2,
		"desc": "A friendly creature immediately deals its ATK + 2 as damage to an enemy creature."},
	"drill_serjeant": {"atk": 1, "hp": 1,
		"desc": "When played: move your creatures 1 lane right, last wraps. They get +1 ATK this round."},
	"crossed_orders": {"dmg_bonus": 2,
		"desc": "Two enemy creatures trade places, then each takes 2 damage."},
	"wheeling_lancer": {"atk": 1, "hp": 1,
		"desc": "When this changes lanes: strike the enemy now facing it."},
	"rolling_tower":  {"hp": 1,
		"desc": "When this changes lanes: deal 4 damage to the enemy now facing it."},
	"flanking_order": {"dmg_bonus": 2,
		"desc": "Move a friendly to an adjacent lane. If unopposed, it deals its ATK + 2 to enemy face."},
	"hook_and_chain": {"hp": 1,
		"desc": "When played: move an enemy from an adjacent lane into this lane. Deal 2 damage to it."},

	# ─── 2026-07-16 rarity-floor vanillas — the "+" stays as plain as the card:
	# a bigger honest body (Curtain Wall forges into more wall, not more sword).
	"man_at_arms":  {"atk": 1, "hp": 1},
	"war_boar":     {"atk": 1, "hp": 1},
	"grave_levy":   {"atk": 1, "hp": 1},
	"hexwright":    {"atk": 1, "hp": 1},
	"curtain_wall": {"hp": 3},
	"freelance":    {"atk": 1, "hp": 1},

	# ─── Discover cards ───────────────────────────────────────────────────
	"lost_tome":      {"cost": -1,
		"desc": "Discover a common spell. It costs 1 less. Exhaust."},
	"scholar":        {"atk": 1, "hp": 1,
		"desc": "On-Enter: Discover a spell. It costs 1 less."},
	"war_council":    {"cost": -1,
		"desc": "Discover any card. It costs 1 less. Exhaust."},
	"treasure_hunter": {"atk": 1, "hp": 1,
		"desc": "On-Enter: Discover a rare card. It costs 1 less."},

	# ─── Pyre / Doom-Burn (Kindler set) ───────────────────────────────────
	# Doom creatures can't bump their timer through the generic merge (there's
	# no "doom" key handler in _apply_plus_upgrade), so they upgrade on body /
	# on_death value instead — a bigger bomb, not a faster one (pacing: keep
	# the fuse short). Rampage / Lifesteal creatures already get +1 to their
	# keyword tick from the is_upgraded flag (see Combat._apply_combat_strike_
	# riders), so their entries just fatten the body. The 3 custom spells carry
	# dmg_bonus so the "+" versions actually hit / buff harder via the resolver.
	"cinder_pup":     {"atk": 1, "hp": 1,
		"desc": "Doom 2."},
	"kindling":       {"hp": 1, "on_death_value": 1,
		"desc": "Doom 2. On-Death: deal 3 damage to enemy face."},
	"burning_martyr": {"hp": 1, "on_death_value": 1,
		"desc": "Doom 3. On-Death: deal 2 damage to all enemies."},
	"hellfire_imp":   {"atk": 1, "hp": 1,
		"desc": "Swift. Doom 2."},
	"cinder_whelp":   {"hp": 1, "on_death_value": 1,
		"desc": "Doom 2. On-Death: deal 4 damage to all enemies."},
	"ash_hound":      {"atk": 1, "hp": 1,
		"desc": "Rampage."},
	"ember_stalker":  {"hp": 2,
		"desc": "Doom 3. On-Death: deal 2 damage to all enemies and detonate your other Doom creatures."},
	"mark_of_ash":    {"desc": "An enemy creature gains Doom 1. The blast hits only it. If it has Doom, detonate instead."},
	"bloodsworn":     {"atk": 1, "hp": 1, "on_enter_value": -1,
		"desc": "Lifesteal. On-Enter: your hero takes 1 damage."},
	"cinder_acolyte": {"atk": 1, "hp": 1,
		"desc": "When you cast a spell: this deals 2 damage to the opposing creature."},
	"ember_warden":   {"atk": 1, "hp": 1,
		"desc": "When you cast a spell: this and its row partner gain Shield."},
	"concentrate":    {"dmg_bonus": 2,
		"desc": "Deal 6 damage to a creature. If it dies, deal 6 damage to enemy face."},
	"battle_hymn":    {"dmg_bonus": 1,
		"desc": "Deal 4 damage to all enemies. Deal 1 damage to enemy face for each killed. Exhaust."},
	"powder_store":   {"desc": "Cast 4 random spells at random targets. Exhaust."},
	"case_shot":      {"dmg_bonus": 3,
		"desc": "Deal 11 damage split at random among enemy creatures. Exhaust."},
	"press_gang":     {"desc": "Summon 4 random creatures costing 3 or less. Exhaust."},
	"mending_light":  {"dmg_bonus": 1,
		"desc": "Your Dead gain Lifesteal and +1 ATK this fight."},
}


# Returns the upgrade delta for a card id. Falls back to a sensible default
# so any future card without a hand-crafted entry still upgrades cleanly:
# creatures get +1/+1, spells get -1 cost. Curses return {} (unupgradeable).
#
# KNOWN EDGE, and it is a LOUD one rather than a silent one: the spell default
# is a discount, and `_apply_plus_upgrade` floors cost at 1 (a free card has no
# round to be affordable on under the Command ramp). So a spell that costs 1 and
# has no hand-crafted entry forges into a byte-identical copy of itself — a "+"
# that advertises a bonus it does not carry, the `reference_keyword_text_lies`
# class. Three cards fell into it when the 2026-09-16 rescale moved their bases
# down to 1 (Read the Will, Venom Tip, Foul the Blades) and all three now carry
# real entries. `tools/_probe_dominance.gd` requires every forge to be strictly
# better than its base, so the next one fails a gate instead of shipping quiet;
# the fix is a hand-crafted entry, never a lower floor.
static func get_plus_upgrade(card_id: String) -> Dictionary:
	if is_curse(card_id):
		return {}
	if UPGRADES.has(card_id):
		return UPGRADES[card_id].duplicate(true)
	var data: Dictionary = CARD_POOL.get(card_id, {})
	if data.is_empty():
		return {}
	if data.get("type", "") == "creature":
		return {"atk": 1, "hp": 1}
	return {"cost": -1}


# Whether a card has a meaningful upgrade available. False for curses and any
# bare entry with no improvement. Used by the Rest screen to filter the grid.
static func is_upgradeable(card_id: String) -> bool:
	return not get_plus_upgrade(card_id).is_empty()


# Enemy creatures — temporary for Phase 2, replaced by EncounterDB in Phase 4
const ENEMY_POOL: Dictionary = {
	# Act 1 — simple
	"e_goblin": {"id": "e_goblin", "name": "Ditch Goblin", "type": "creature", "cost": 0, "atk": 2, "hp": 2,
		"rarity": "enemy", "keywords": [], "act": 1, "desc": ""},
	"e_scout": {"id": "e_scout", "name": "Road Picket", "type": "creature", "cost": 0, "atk": 2, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 1, "desc": ""},
	"e_brute": {"id": "e_brute", "name": "The Mauler", "type": "creature", "cost": 0, "atk": 3, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 1, "desc": ""},
	"e_archer": {"id": "e_archer", "name": "Archer", "type": "creature", "cost": 0, "atk": 2, "hp": 3,
		"rarity": "enemy", "keywords": ["on_enter"], "act": 1, "desc": "On-Enter: deal 1 damage to a random creature on your side.",
		"on_enter": {"type": "damage_random_player", "value": 1}},
	"e_golem": {"id": "e_golem", "name": "Ruin Guard", "type": "creature", "cost": 0, "atk": 2, "hp": 4,
		"rarity": "enemy", "keywords": ["armored"], "act": 1, "desc": "Armored."},
	"e_wind_harpy": {"id": "e_wind_harpy", "name": "Storm Owl", "type": "creature", "cost": 0, "atk": 3, "hp": 2,
		"rarity": "enemy", "keywords": ["swift"], "act": 1, "desc": "Swift."},
	# Act 2 — keywords
	"e_cultist": {"id": "e_cultist", "name": "The Wailer", "type": "creature", "cost": 0, "atk": 3, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 2, "desc": ""},
	"e_dark_priest": {"id": "e_dark_priest", "name": "Candle-Priest", "type": "creature", "cost": 0, "atk": 2, "hp": 4,
		"rarity": "enemy", "keywords": ["regenerate"], "act": 2, "desc": "Regenerate."},
	"e_enforcer": {"id": "e_enforcer", "name": "Chainbreaker", "type": "creature", "cost": 0, "atk": 4, "hp": 3,
		"rarity": "enemy", "keywords": ["swift"], "act": 2, "desc": "Swift."},
	"e_bog_lurker": {"id": "e_bog_lurker", "name": "Bog Lurker", "type": "creature", "cost": 0, "atk": 2, "hp": 5,
		"rarity": "enemy", "keywords": [], "act": 2, "desc": ""},
	"e_bone_knight": {"id": "e_bone_knight", "name": "Bone Knight", "type": "creature", "cost": 0, "atk": 3, "hp": 4,
		"rarity": "enemy", "keywords": ["on_death"], "act": 2, "desc": "On-Death: summon a 2/2 token in this lane.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2}},
	# Act 3 — combos
	"e_fire_elemental": {"id": "e_fire_elemental", "name": "Walking Pyre", "type": "creature", "cost": 0, "atk": 4, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 3, "desc": ""},
	"e_headsman": {"id": "e_headsman", "name": "Headsman", "type": "creature", "cost": 0, "atk": 4, "hp": 4,
		"rarity": "enemy", "keywords": [], "act": 3, "desc": ""},
	"e_drake": {"id": "e_drake", "name": "Drake", "type": "creature", "cost": 0, "atk": 3, "hp": 4,
		"rarity": "enemy", "keywords": ["piercing"], "act": 3, "desc": "Piercing."},
	"e_elder_dragon": {"id": "e_elder_dragon", "name": "Blight-Wyrm", "type": "creature", "cost": 0, "atk": 5, "hp": 6,
		"rarity": "enemy", "keywords": ["wither"], "wither": 1, "act": 3, "desc": "Wither 1."},
	# Bosses
	"e_warden_champ": {"id": "e_warden_champ", "name": "Iron Champion", "type": "creature", "cost": 0, "atk": 4, "hp": 5,
		"rarity": "enemy", "keywords": ["swift"], "act": 1, "desc": "Swift."},
	"e_collector_champ": {"id": "e_collector_champ", "name": "Collector's Champion", "type": "creature", "cost": 0, "atk": 4, "hp": 5,
		"rarity": "enemy", "keywords": ["armored"], "act": 2, "desc": "Armored."},
	"e_devil_champ": {"id": "e_devil_champ", "name": "Devil's Champion", "type": "creature", "cost": 0, "atk": 5, "hp": 6,
		"rarity": "enemy", "keywords": ["last_stand"], "act": 3, "desc": "Last Stand."},
}


const STARTER_DECK: Array[String] = [
	"goblin", "goblin", "goblin", "goblin",
	"brute", "brute", "brute", "brute",
	"sprite",
	"troll",
]


static func random_curse_id() -> String:
	# Used by events / Mark of Pain / Crone / Turbo / etc. to add a random
	# curse variant to the player's discard pile. Centralizing the random
	# pick here means new curse types automatically appear everywhere a
	# curse gets added. Weighted so the plain clog stays the common case.
	var bag: Array[String] = []
	for id in CURSE_IDS:
		for _i in range(int(_CURSE_WEIGHTS.get(id, 1))):
			bag.append(id)
	return bag[randi() % bag.size()]


static func is_curse(id: String) -> bool:
	return CURSE_IDS.has(id)


static func get_card_data(id: String) -> Dictionary:
	if CARD_POOL.has(id):
		return CARD_POOL[id].duplicate(true)
	if ENEMY_POOL.has(id):
		return ENEMY_POOL[id].duplicate(true)
	push_warning("CardDB: unknown card id '%s'" % id)
	return {}


static func cards_of_rarity(rarity: String) -> Array[String]:
	return get_pool_by_rarity(rarity)


static func get_pool_by_rarity(rarity: String) -> Array[String]:
	var result: Array[String] = []
	for id in CARD_POOL.keys():
		if CARD_POOL[id].rarity == rarity and bool(CARD_POOL[id].get("draftable", true)):
			result.append(id)
	return result


static func random_enemy_for_act(act: int) -> String:
	var pool: Array = []
	for id in ENEMY_POOL.keys():
		if ENEMY_POOL[id].get("act", 1) <= act:
			pool.append(id)
	if pool.is_empty():
		return "e_goblin"
	return pool[randi() % pool.size()]


# Rarity weights for card rewards, per act — [common, uncommon, rare], out of
# 100. Reward quality escalates with the campaign, but GENTLY (flattened
# 2026-07-16 from 50/40/10 → 55/38/7 and 30/50/20 → 45/42/13): StS holds
# rares at ~3% ALL run — when act 3 handed out 20% rares, the gold gem
# stopped being an event and rarity inflation was doing the power curve's
# job (that belongs to c4+ pieces, tribe density, and forges). Commons stay
# the majority of what the player SEES in every act. Exposed via
# act_rarity_weights() so other slates can borrow an act's odds; the skirmish
# DRAFT rolls at act-3 weights so a drafted warband feels late-campaign.
const ACT_REWARD_WEIGHTS: Dictionary = {
	1: [65, 30, 5],
	2: [55, 38, 7],
	3: [45, 42, 13],
}


## The [common, uncommon, rare] reward weights for an act. Any act other than 1/2
## (including 3+) falls to the act-3 slate — matches the old inline `match` default.
static func act_rarity_weights(act: int) -> Array:
	return ACT_REWARD_WEIGHTS.get(act, ACT_REWARD_WEIGHTS[3])


static func roll_card_reward(act: int, is_elite: bool = false, is_boss: bool = false,
		count: int = 3) -> Array[String]:
	if is_boss:
		return _roll_from_rarity("rare", count)
	var weights: Array = act_rarity_weights(act)
	if is_elite:
		weights = [15, 55, 30]
	var bags: Dictionary = {
		"common": _shuffled_copy(get_pool_by_rarity("common")),
		"uncommon": _shuffled_copy(get_pool_by_rarity("uncommon")),
		"rare": _shuffled_copy(get_pool_by_rarity("rare")),
	}
	var picked: Array[String] = []
	var attempts := 0
	# Cap attempt budget proportionally so larger counts still terminate even
	# when the rarity pool is small enough that "no duplicates" forces retries.
	var attempt_budget: int = maxi(50, count * 20)
	while picked.size() < count and attempts < attempt_budget:
		attempts += 1
		var roll = randi() % 100
		var rarity: String
		if roll < weights[0]: rarity = "common"
		elif roll < weights[0] + weights[1]: rarity = "uncommon"
		else: rarity = "rare"
		var id := _pop_unpicked(bags.get(rarity, []), picked)
		if id == "":
			id = _pop_any_reward_bag(bags, picked)
		if id != "":
			picked.append(id)
	return picked


static func _roll_from_rarity(rarity: String, count: int) -> Array[String]:
	var pool := _shuffled_copy(get_pool_by_rarity(rarity))
	var picked: Array[String] = []
	while picked.size() < count:
		var id := _pop_unpicked(pool, picked)
		if id == "":
			break
		picked.append(id)
	return picked


static func _shuffled_copy(pool: Array[String]) -> Array[String]:
	var bag := pool.duplicate()
	for i in range(bag.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp: String = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	return bag


static func _pop_unpicked(pool: Array, picked: Array[String]) -> String:
	while not pool.is_empty():
		var id := String(pool.pop_back())
		if not picked.has(id):
			return id
	return ""


static func _pop_any_reward_bag(bags: Dictionary, picked: Array[String]) -> String:
	for rarity in ["common", "uncommon", "rare"]:
		var id := _pop_unpicked(bags.get(rarity, []), picked)
		if id != "":
			return id
	return ""
