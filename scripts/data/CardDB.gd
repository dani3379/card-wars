extends Node
## CardDB.gd — all card definitions: 12 starter (incl. the levy set) + the
## draft pool (common/uncommon/rare) + enemy creatures + tokens/curses.
##
## Card schema:
##   id, name, type ("creature"/"spell"), cost, rarity ("starter"/"common"/"uncommon"/"rare"/"enemy")
##   Creature: atk, hp, keywords, desc, and optional: on_enter, on_death, on_play, adj_buff, wither, passive
##   on_play: {"type": "...", "value": X, ...} is an instant battlecry that fires when the creature is placed
##   Spell: keywords, desc, spell {type, value, ...}, targeting ("enemy_creature"/"friendly_creature"/"any_creature"/"any"/"none")

const CARD_POOL: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTER CARDS — 10-card deck: 4 Peasant, 4 Soldier, 1 Squire, 1 Footman
	# ═══════════════════════════════════════════
	"goblin": {"id": "goblin", "name": "Goblin", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": ["on_enter"], "desc": "On-Enter: deal 1 damage to enemy face.",
		"on_enter": {"type": "damage_face", "value": 1}},
	"brute": {"id": "brute", "name": "Brute", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["on_enter"], "desc": "On-Enter: deal 1 damage to the opposing creature.",
		"on_enter": {"type": "damage_opposing", "value": 1}},
	"troll": {"id": "troll", "name": "Troll", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["regenerate"], "desc": "Regenerate."},
	"sprite": {"id": "sprite", "name": "Sprite", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": [], "desc": "On-Enter: adjacent creatures get +1 ATK this round.",
		"on_play": {"type": "buff_adjacent_atk", "value": 1}},
	"naga": {"id": "naga", "name": "Naga", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "starter", "keywords": [], "desc": "On-Enter: deal 2 damage to the opposing creature.",
		"on_play": {"type": "damage_opposing", "value": 2}},
	"ratling": {"id": "ratling", "name": "Ratling", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "starter", "keywords": ["wither", "on_death"], "wither": 1,
		"desc": "Wither 1. On-Death: deal 1 damage to the opposing lane.",
		"on_death": {"type": "damage_opposing_lane", "value": 1}},
	"strike": {"id": "strike", "name": "Strike", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 3 damage to a creature.",
		"spell": {"type": "damage", "value": 3}, "targeting": "any_creature"},
	"fireball": {"id": "fireball", "name": "Fireball", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 2 damage to enemy face.",
		"spell": {"type": "damage_face", "value": 2}, "targeting": "none"},

	# ── Levy starters (2026-07-06 progression pass) — deliberately PLAIN, a
	# notch below the pool's commons. Hero decks are built ONLY from starter-
	# rarity cards now, so every drafted pool card is a visible upgrade over
	# what the march began with (the StS starter contract: nothing in your
	# opening deck should outrank what the road offers).
	"levy_rider": {"id": "levy_rider", "name": "Outrider", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": ["swift"], "desc": "Swift."},
	"palisade": {"id": "palisade", "name": "Palisade", "type": "creature", "cost": 1, "atk": 0, "hp": 4,
		"rarity": "starter", "keywords": ["guardian"], "desc": "Guardian."},
	"mourner": {"id": "mourner", "name": "Mourner", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": ["on_death"],
		"desc": "On-Death: gain 1 Command next turn.",
		"on_death": {"type": "bonus_mana", "value": 1}},
	"spark": {"id": "spark", "name": "Spark", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [], "desc": "Deal 1 damage to a creature.",
		"spell": {"type": "damage", "value": 1}, "targeting": "any_creature"},

	# ═══════════════════════════════════════════
	#  COMMON CREATURES
	# ═══════════════════════════════════════════
	"crystal_sentry": {"id": "crystal_sentry", "name": "Crystal Sentry", "type": "creature", "cost": 2, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["shield"],
		"desc": "Shield. On-Enter: adjacent friendlies gain Shield.",
		"on_play": {"type": "grant_shield_adjacent"}},
	"hound": {"id": "hound", "name": "Hound", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": [], "desc": "On-Enter: deal 2 damage to a random enemy creature.",
		"on_play": {"type": "damage_any", "value": 2}},
	"shieldbearer": {"id": "shieldbearer", "name": "Bulwark Novice", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["shield"], "desc": "Shield. When its Shield breaks: this gains +2 ATK this fight.",
		"passive": "shield_rage"},
	"pikeman": {"id": "pikeman", "name": "Pikeman", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": [], "desc": "On-Enter: shove the opposing creature into its back row. If it can't move, deal 2 damage to it instead.",
		"on_play": {"type": "shove_back", "value": 2}},
	"lookout": {"id": "lookout", "name": "Lookout", "type": "creature", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. Front row: +1 ATK this fight. Back row: draw 1.",
		"on_play": {"type": "vanguard_split", "value": 1}},
	"warding_stone": {"id": "warding_stone", "name": "Warding Stone", "type": "creature", "cost": 1, "atk": 0, "hp": 5,
		"rarity": "common", "keywords": ["guardian", "thorns"],
		"desc": "Guardian. Thorns."},
	"hexblade": {"id": "hexblade", "name": "Hexblade", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["sniper"],
		"desc": "Sniper. Hits the lowest-HP enemy, repeating on a kill. +1 ATK per spell cast this fight.",
		"passive": "atk_per_spell"},
	"harpy": {"id": "harpy", "name": "Harpy", "type": "creature", "cost": 2, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. On-Enter: pull the opposing back-row enemy forward. The opposing creature takes 2 damage and can't attack this round.",
		"on_play": {"type": "haul_front", "value": 2, "stun": true}},
	"thornguard": {"id": "thornguard", "name": "Thornguard", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "common", "keywords": ["thorns", "on_death"], "desc": "Thorns. On-Death: deal 1 damage to all enemies.",
		"on_death": {"type": "damage_all_enemies", "value": 1}},
	"raven": {"id": "raven", "name": "Raven", "type": "creature", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["sniper"], "desc": "Sniper. Hits the lowest-HP enemy and chains on kill. On-Enter: deal 2 damage to a random enemy back-row creature.",
		"on_play": {"type": "snipe_back", "value": 2}},
	"squire_captain": {"id": "squire_captain", "name": "Drillmaster", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": [],
		"desc": "On-Enter: your other creatures in this row get +1 ATK this fight.",
		"on_play": {"type": "buff_row_atk", "value": 1}},
	"plague_rat": {"id": "plague_rat", "name": "Plague Rat", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["poison"],
		"desc": "Poison."},
	"torchbearer": {"id": "torchbearer", "name": "Torchbearer", "type": "creature", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "common", "keywords": ["formation", "adj_buff"], "formation": 1, "desc": "Formation. Adjacent friendlies +1 ATK.",
		"adj_buff": {"atk": 1, "hp": 0}},
	"gravedigger": {"id": "gravedigger", "name": "Gravedigger", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": [], "desc": "When one of your creatures dies, draw 1 (up to twice per round).",
		"passive": "draw_on_ally_death"},
	"bloodhound": {"id": "bloodhound", "name": "Bloodhound", "type": "creature", "cost": 1, "atk": 1, "hp": 1,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-Enter: deal 1 damage to the opposing creature and draw 1.",
		"on_enter": {"type": "damage_opposing_draw", "value": 1}},
	"scavenger": {"id": "scavenger", "name": "Scavenger", "type": "creature", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. Slay: gain 5 gold.",
		"passive": "slay_gold"},
	"stone_wall": {"id": "stone_wall", "name": "Stone Wall", "type": "creature", "cost": 1, "atk": 0, "hp": 6,
		"rarity": "common", "keywords": ["guardian", "armored"],
		"desc": "Guardian. Armored."},
	"tallow_doll": {"id": "tallow_doll", "name": "Tallow Doll", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["on_death"],
		"desc": "On-Death: summon a 1/1 token in this lane.",
		"on_death": {"type": "summon", "atk": 1, "hp": 1}},
	"skirmisher": {"id": "skirmisher", "name": "Headhunter", "type": "creature", "cost": 2, "atk": 3, "hp": 2,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. Slay: draw 1.",
		"passive": "draw_on_slay"},
	"lancer": {"id": "lancer", "name": "Lancer", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["overrun"], "overrun": 2,
		"desc": "Overrun 2."},

	# ═══════════════════════════════════════════
	#  COMMON SPELLS (12)
	# ═══════════════════════════════════════════
	"slash": {"id": "slash", "name": "Breach Bomb", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to an enemy creature and blast it into its back row. If it can't move, deal 2 extra damage. Slay: draw 1.",
		"spell": {"type": "custom", "id": "slash"}, "targeting": "enemy_creature"},
	"shield_wall": {"id": "shield_wall", "name": "Shield Wall", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "A friendly creature gets +4 HP and Thorns this round.",
		"spell": {"type": "custom", "id": "shield_wall"}, "targeting": "friendly_creature"},
	"war_cry": {"id": "war_cry", "name": "War Cry", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "All friendlies gain Swift this round.",
		"spell": {"type": "custom", "id": "war_cry"}, "targeting": "none"},
	"provision": {"id": "provision", "name": "Provision", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Summon a 2/1 Soldier in an empty lane. Exhaust.",
		"spell": {"type": "custom", "id": "provision"}, "targeting": "none"},
	"patch_up": {"id": "patch_up", "name": "Field Surgery", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Fully heal a friendly creature and draw 1. It can't attack this round.",
		"spell": {"type": "custom", "id": "patch_up"}, "targeting": "friendly_creature"},
	"flame_bolt": {"id": "flame_bolt", "name": "Flame Bolt", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to enemy face. Deal 5 instead if you've already cast a spell this turn.",
		"spell": {"type": "custom", "id": "flame_bolt"}, "targeting": "none"},
	"shove": {"id": "shove", "name": "Shove", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Shove an enemy creature into its back row. If it can't move, it can't attack this round.",
		"spell": {"type": "custom", "id": "shove"}, "targeting": "enemy_creature"},
	"gambit": {"id": "gambit", "name": "Gambit", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Discard up to 3 cards, then draw that many.",
		"spell": {"type": "custom", "id": "gambit"}, "targeting": "none"},
	"blood_tithe": {"id": "blood_tithe", "name": "Blood Tithe", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Deal 4 damage to enemy face. Take 2 damage yourself.",
		"spell": {"type": "custom", "id": "blood_tithe"}, "targeting": "none"},
	"reckless_charge": {"id": "reckless_charge", "name": "Penance", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to any target. If a Curse is in your hand, exhaust it: deal 6 instead.",
		"spell": {"type": "custom", "id": "penance"}, "targeting": "any"},
	"quick_shot": {"id": "quick_shot", "name": "Quick Shot", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Deal 1 damage to any target. Slay: draw 1. Exhaust.",
		"spell": {"type": "custom", "id": "quick_shot"}, "targeting": "any"},
	"frost_bolt": {"id": "frost_bolt", "name": "Frost Bolt", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "An enemy creature can't attack this round.",
		"spell": {"type": "custom", "id": "frost_bolt"}, "targeting": "enemy_creature"},
	"adrenaline": {"id": "adrenaline", "name": "Second Wind", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Gain 2 Command. Draw 1 card. Exhaust.",
		"spell": {"type": "custom", "id": "adrenaline"}, "targeting": "none"},
	"hex": {"id": "hex", "name": "Hex", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 1 damage to an enemy creature, or 4 if it has any keywords. Remove all its keywords.",
		"spell": {"type": "custom", "id": "hex"}, "targeting": "enemy_creature"},

	# ═══════════════════════════════════════════
	#  UNCOMMON CREATURES
	# ═══════════════════════════════════════════
	"battle_drummer": {"id": "battle_drummer", "name": "Battle Drummer", "type": "creature", "cost": 2, "atk": 1, "hp": 5,
		"rarity": "uncommon", "keywords": ["armored"],
		"desc": "Armored. Adjacent friendlies have Swift.",
		"passive": "drummer_swift"},
	"witch": {"id": "witch", "name": "Witch", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [], "desc": "Your first spell each turn costs 1 less.",
		"passive": "first_spell_discount"},
	"duelist": {"id": "duelist", "name": "Condottiere", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: gains +1/+1 this fight for each unspent Command you have.",
		"on_enter": {"type": "atk_hp_per_unspent_mana"}},
	"griffin": {"id": "griffin", "name": "Griffin", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift", "on_death"], "desc": "Swift. On-Death: this creature returns to your hand (once per fight).",
		"on_death": {"type": "return_to_hand_once"}},
	"revenant": {"id": "revenant", "name": "Revenant", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death"],
		"desc": "On-Death: this creature returns to play at full HP (once per fight).",
		"on_death": {"type": "reborn"}},
	"berserker": {"id": "berserker", "name": "Berserker", "type": "creature", "cost": 2, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": [], "desc": "Whenever this is hit and survives, it gains +2 ATK.",
		"passive": "rage_on_hit"},
	"mule": {"id": "mule", "name": "Mule", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["summon"], "desc": "Summon."},
	"husk": {"id": "husk", "name": "Husk", "type": "creature", "cost": 2, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": ["guardian", "on_death"],
		"desc": "Guardian. On-Death: summon a 2/2 token in this lane.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2}},
	"basilisk": {"id": "basilisk", "name": "Basilisk", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["poison", "thorns"], "venom_thorns": true,
		"desc": "Poison. Thorns. Its Thorns are poisonous — creatures that strike it die."},
	"necromancer": {"id": "necromancer", "name": "Necromancer", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death"],
		"desc": "On-Death: summon a 2/2 token in both rows of its lane.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2, "both_rows": true}},
	"carrion_priest": {"id": "carrion_priest", "name": "Carrion Priest", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["guardian"], "desc": "Guardian. Whenever one of your creatures dies, deal 1 damage to enemy face and heal your hero 1.",
		"passive": "drain_on_ally_death"},
	"gravecaller": {"id": "gravecaller", "name": "Oathkeeper", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: gains +1/+1 this fight for each friendly that has fallen this fight.",
		"on_enter": {"type": "atk_hp_per_fallen"}},
	"breaker": {"id": "breaker", "name": "Twinblade", "type": "creature", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "Attacks twice each round.",
		"passive": "attacks_twice"},
	"cleave_hound": {"id": "cleave_hound", "name": "Cleave Hound", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": [],
		"desc": "When this attacks: also deals 1 damage to adjacent opposing creatures.",
		"passive": "cleave"},
	"blood_pyre": {"id": "blood_pyre", "name": "Blood Pyre", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "uncommon", "keywords": [], "desc": "On-Enter: sacrifice this creature. Adjacent friendlies get +3 ATK this fight, and draw a card.",
		"on_play": {"type": "blood_sacrifice", "value": 3}},
	"copycat": {"id": "copycat", "name": "Changeling", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-Enter: become a copy of a chosen friendly creature.",
		"on_enter": {"type": "copy_friendly"}},
	"familiar": {"id": "familiar", "name": "Familiar", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: Discover a creature.",
		"on_enter": {"type": "discover", "type_filter": "creature", "rarity_filter": ""}},
	"adaptable": {"id": "adaptable", "name": "Sellsword", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: gain Swift, Piercing, Armored, or Thorns (you choose).",
		"on_enter": {"type": "choose_keyword"}},
	"vengeance": {"id": "vengeance", "name": "Vengeance", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["overrun"], "overrun": 1,
		"desc": "Overrun. Gains +2 ATK this fight whenever you take face damage.",
		"passive": "vengeance_growth"},
	"iron_bastion": {"id": "iron_bastion", "name": "Iron Bastion", "type": "creature", "cost": 3, "atk": 1, "hp": 7,
		"rarity": "uncommon", "keywords": ["armored", "formation"], "formation": 1,
		"desc": "Armored. Formation. Enemy face damage is reduced by 1.",
		"passive": "reduce_face_damage"},
	"leyline_conduit": {"id": "leyline_conduit", "name": "Leyline Conduit", "type": "creature", "cost": 2, "atk": 0, "hp": 4,
		"rarity": "uncommon", "keywords": ["formation"], "formation": 1,
		"desc": "Formation. Start of each of your turns: gain +1 Command.",
		"passive": "mana_per_turn"},
	"the_glutton": {"id": "the_glutton", "name": "The Glutton", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "overrun"], "overrun": 1,
		"desc": "Overrun. On-Enter: devour adjacent friendlies — gain +2/+2 and their keywords for each one eaten.",
		"on_enter": {"type": "glutton_devour"}},
	"standard_bearer": {"id": "standard_bearer", "name": "Standard Bearer", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": [],
		"desc": "Your summoned tokens enter with +1/+1.",
		"passive": "token_lord"},
	"shieldmaiden": {"id": "shieldmaiden", "name": "Shieldmaiden", "type": "creature", "cost": 2, "atk": 1, "hp": 5,
		"rarity": "uncommon", "keywords": ["guardian", "on_death"],
		"desc": "Guardian. On-Death: adjacent friendlies gain Shield.",
		"on_death": {"type": "grant_shield_adjacent"}},
	"the_apothecary": {"id": "the_apothecary", "name": "The Apothecary", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "Whenever an enemy creature dies, deal 1 damage to enemy face.",
		"passive": "plague_doctor"},
	"emberwright": {"id": "emberwright", "name": "Emberwright", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": [],
		"desc": "Whenever you cast a spell, deal 2 damage to enemy face.",
		"passive": "ember_per_spell"},
	"sin_eater": {"id": "sin_eater", "name": "Sin-Eater", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": [],
		"desc": "On-Enter: eat a Curse from your hand (exhaust it) — this gains +2/+2 and you draw 1.",
		"on_play": {"type": "eat_curse", "value": 2}},

	# ═══════════════════════════════════════════
	#  UNCOMMON SPELLS (11)
	# ═══════════════════════════════════════════
	"smite_spell": {"id": "smite_spell", "name": "Smite", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 6 damage to a creature. Slay: gain 1 Command and draw 1. Exhaust.",
		"spell": {"type": "custom", "id": "smite_spell"}, "targeting": "any_creature"},
	"inspire": {"id": "inspire", "name": "Inspire", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "All friendlies gain Swift and Piercing this round. Exhaust.",
		"spell": {"type": "custom", "id": "inspire"}, "targeting": "none"},
	"ambush": {"id": "ambush", "name": "Ambush", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 1 damage to all enemy creatures. Your Swift creatures get +1 ATK this round.",
		"spell": {"type": "custom", "id": "ambush"}, "targeting": "none"},
	"reanimate": {"id": "reanimate", "name": "Reanimate", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Summon the last creature to die as a 1/1 (keeps its keywords). Exhaust.",
		"spell": {"type": "custom", "id": "reanimate"}, "targeting": "none"},
	"charge_spell": {"id": "charge_spell", "name": "Charge!", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "A friendly creature attacks every opposing lane this round.",
		"spell": {"type": "custom", "id": "charge_spell"}, "targeting": "friendly_creature"},
	"ricochet": {"id": "ricochet", "name": "Crossfire", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 2 damage to each back-row enemy. If none are back there, deal 1 damage to a random enemy creature.",
		"spell": {"type": "custom", "id": "ricochet"}, "targeting": "none"},
	"offering": {"id": "offering", "name": "Offering", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Sacrifice a friendly creature. Gain 2 Command. Exhaust.",
		"spell": {"type": "custom", "id": "offering"}, "targeting": "friendly_creature"},
	"grave_pact": {"id": "grave_pact", "name": "Last Rites", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 3 damage to a creature — 6 instead if a friendly has fallen this fight.",
		"spell": {"type": "custom", "id": "last_rites"}, "targeting": "any_creature"},
	"fuel_the_pyre": {"id": "fuel_the_pyre", "name": "Fuel the Pyre", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Sacrifice a friendly creature. Deal damage equal to its ATK to the enemy creature opposing it (or a random enemy).",
		"spell": {"type": "custom", "id": "fuel_the_pyre"}, "targeting": "friendly_creature"},
	"venom_tip": {"id": "venom_tip", "name": "Venom Tip", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "A friendly creature gains Poison this round.",
		"spell": {"type": "custom", "id": "venom_tip"}, "targeting": "friendly_creature"},
	"mark_of_ash": {"id": "mark_of_ash", "name": "Mark of Ash", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "An enemy creature gains Doom 2 with no blast. If it already has Doom, detonate it.",
		"spell": {"type": "custom", "id": "mark_of_ash"}, "targeting": "enemy_creature"},
	"pillage": {"id": "pillage", "name": "Pillage", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 2 damage to an enemy creature and 1 damage to enemy face. Slay: gain 10 gold.",
		"spell": {"type": "custom", "id": "pillage"}, "targeting": "enemy_creature"},
	"echo_spell": {"id": "echo_spell", "name": "Echo", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Copy the last spell you cast this turn. (Does nothing if you haven't cast one.) Exhaust.",
		"spell": {"type": "custom", "id": "echo_spell"}, "targeting": "none"},
	"turbo": {"id": "turbo", "name": "Frenzy", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Gain 2 Command. Add a Curse to your discard pile.",
		"spell": {"type": "custom", "id": "turbo"}, "targeting": "none"},
	"recycle": {"id": "recycle", "name": "Salvage", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Exhaust a card from hand. Gain Command equal to its cost.",
		"spell": {"type": "custom", "id": "recycle"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  RARE CREATURES
	# ═══════════════════════════════════════════
	"dragon_hatchling": {"id": "dragon_hatchling", "name": "Dragon Hatchling", "type": "creature", "cost": 4, "atk": 4, "hp": 5,
		"rarity": "rare", "keywords": ["on_enter", "swift"], "desc": "Swift. On-Enter: deal 2 damage to all enemies.",
		"on_enter": {"type": "damage_all_enemies", "value": 2}},
	"royal_guard": {"id": "royal_guard", "name": "Royal Guard", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": [], "desc": "Adjacent friendlies take -1 damage. Gains +1 ATK each time this is hit.",
		"passive": "royal_guard"},
	"assassin": {"id": "assassin", "name": "Assassin", "type": "creature", "cost": 3, "atk": 4, "hp": 2,
		"rarity": "rare", "keywords": ["swift"], "desc": "Swift. On-Enter: destroy the opposing creature if its HP is 3 or less.",
		"on_play": {"type": "execute", "value": 3}},
	"hydra": {"id": "hydra", "name": "Hydra", "type": "creature", "cost": 3, "atk": 4, "hp": 6,
		"rarity": "rare", "keywords": ["rampage", "armored"], "rampage": 1,
		"desc": "Rampage, Armored. Doesn't attack directly — hits every opposing lane at once, taking each defender's counter.",
		"passive": "attacks_all_lanes"},
	"summoner": {"id": "summoner", "name": "Summoner", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["guardian"],
		"desc": "Guardian. Start of each round: summon a 1/1 token in an adjacent empty lane.",
		"passive": "summon_each_round"},
	"paladin": {"id": "paladin", "name": "Paladin", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": ["last_stand"],
		"desc": "Last Stand. When its Last Stand triggers: your creatures get +2 ATK this fight and your hero heals 3.",
		"passive": "paladin_rally"},
	"corpse_eater": {"id": "corpse_eater", "name": "Corpse Eater", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "rare", "keywords": ["piercing"], "desc": "Piercing. Gains +1 ATK whenever a friendly creature dies.",
		"passive": "grow_on_ally_death"},
	"ironclad_veteran": {"id": "ironclad_veteran", "name": "Old Campaigner", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "Enters with +1/+1 for every 3 kills this card has made this run.",
		"on_enter": {"type": "atk_hp_per_own_kills"}},
	"glass_knight": {"id": "glass_knight", "name": "Glass Knight", "type": "creature", "cost": 2, "atk": 4, "hp": 1,
		"rarity": "uncommon", "keywords": ["shield", "swift"],
		"desc": "Shield. Swift. Slay: regain Shield.",
		"passive": "shield_on_slay"},
	"doppelganger": {"id": "doppelganger", "name": "Doppelganger", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "rare", "keywords": ["on_enter"], "desc": "On-Enter: become a copy of the most recently dead creature.",
		"on_enter": {"type": "copy_last_dead"}},
	"vampire_lord": {"id": "vampire_lord", "name": "Vampire Lord", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "rare", "keywords": ["regenerate"], "desc": "Regenerate. Slay (with this creature): heal you 2 HP and gain +1 ATK.",
		"passive": "vampire_lord"},
	"chaos_imp": {"id": "chaos_imp", "name": "Chaos Imp", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-Enter: cast a random spell that costs 1 or less, for free (auto-targeted).",
		"on_enter": {"type": "cast_random_spell"}},
	"warden_of_graves": {"id": "warden_of_graves", "name": "Warden of Graves", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": [], "desc": "Your friendly On-Death effects trigger twice.",
		"passive": "double_on_death"},
	"siege_golem": {"id": "siege_golem", "name": "Siege Golem", "type": "creature", "cost": 3, "atk": 3, "hp": 6,
		"rarity": "rare", "keywords": ["overrun"], "overrun": 3, "unstoppable": true,
		"desc": "Overrun 3. Ignores Guardian and Thorns."},
	"old_bones": {"id": "old_bones", "name": "Old Bones", "type": "creature", "cost": 3, "atk": 3, "hp": 3,
		"rarity": "rare", "keywords": ["on_death"],
		"desc": "On-Death: rises again, smaller — a 2/2, then a 1/1.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2, "diminish": true}},

	# ═══════════════════════════════════════════
	#  RARE SPELLS (10)
	# ═══════════════════════════════════════════
	"earthquake": {"id": "earthquake", "name": "Earthquake", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 2 damage to every creature. Shove surviving enemy front-row creatures into their back row. Exhaust.",
		"spell": {"type": "custom", "id": "earthquake"}, "targeting": "none"},
	"kings_command": {"id": "kings_command", "name": "King's Command", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "All friendlies get +1/+1 this fight for each friendly creature. Exhaust.",
		"spell": {"type": "custom", "id": "kings_command"}, "targeting": "none"},
	"unholy_bargain": {"id": "unholy_bargain", "name": "Unholy Bargain", "type": "spell", "cost": 0,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Draw 2 cards, +1 if a friendly has fallen this fight. Take 2 face damage. Exhaust.",
		"spell": {"type": "custom", "id": "unholy_bargain"}, "targeting": "none"},
	"mass_grave": {"id": "mass_grave", "name": "Mass Grave", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal damage to every enemy creature equal to the number of cards in your discard pile, but at least 1. Exhaust.",
		"spell": {"type": "custom", "id": "mass_grave"}, "targeting": "none"},
	"dark_pact": {"id": "dark_pact", "name": "Dark Pact", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Sacrifice a friendly creature. Other friendlies get +1/+1 this fight.",
		"spell": {"type": "custom", "id": "dark_pact"}, "targeting": "friendly_creature"},
	"war_chant": {"id": "war_chant", "name": "War Chant", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Discard up to 3 cards. Summon a 2/1 Soldier for each. Exhaust.",
		"spell": {"type": "custom", "id": "war_chant"}, "targeting": "none"},
	"grave_robbery": {"id": "grave_robbery", "name": "Grave Robbery", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Return the last creature to die to your hand. Exhaust.",
		"spell": {"type": "custom", "id": "grave_robbery"}, "targeting": "none"},
	"cataclysm": {"id": "cataclysm", "name": "Cataclysm", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "A friendly creature deals its ATK to all enemies in its lane and adjacent lanes. Exhaust.",
		"spell": {"type": "custom", "id": "cataclysm"}, "targeting": "friendly_creature"},
	"soul_swap": {"id": "soul_swap", "name": "Soul Swap", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "An enemy creature swaps its ATK and HP.",
		"spell": {"type": "custom", "id": "soul_swap"}, "targeting": "enemy_creature"},
	"apocalypse": {"id": "apocalypse", "name": "Apocalypse", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Destroy every creature on the board. Take 1 face damage for each one that dies. Exhaust.",
		"spell": {"type": "custom", "id": "apocalypse"}, "targeting": "none"},
	"lay_on_hands": {"id": "lay_on_hands", "name": "Unclean Blessing", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Your creatures' attacks are poisonous this round. Exhaust.",
		"spell": {"type": "custom", "id": "virulence"}, "targeting": "none"},
	"hoarfrost": {"id": "hoarfrost", "name": "Hoarfrost", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "A friendly creature gains Shield. The opposing creature can't attack this round.",
		"spell": {"type": "custom", "id": "hoarfrost"}, "targeting": "friendly_creature"},
	"banish": {"id": "banish", "name": "Banish", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Remove an enemy creature with 4 or less HP from the fight. If it has more HP, deal 4 damage instead. Exhaust.",
		"spell": {"type": "custom", "id": "banish"}, "targeting": "enemy_creature"},
	"time_snare": {"id": "time_snare", "name": "The Doubled Hour", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "This round, your creatures attack twice. Draw 1. Exhaust.",
		"spell": {"type": "custom", "id": "doubled_hour"}, "targeting": "none"},
	"holy_smite": {"id": "holy_smite", "name": "Holy Smite", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal damage to an enemy creature equal to its missing HP, but at least 3. Slay: draw 1.",
		"spell": {"type": "custom", "id": "holy_smite"}, "targeting": "enemy_creature"},
	"plague_bell": {"id": "plague_bell", "name": "Plague Bell", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Deal 1 damage to every creature on the board. If any died, cast this again. Exhaust.",
		"spell": {"type": "custom", "id": "plague_bell"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  4-COST POWERHOUSES (require mana banking)
	# ═══════════════════════════════════════════
	"riteforge": {"id": "riteforge", "name": "Riteforge", "type": "creature", "cost": 2, "atk": 0, "hp": 5,
		"rarity": "rare", "keywords": ["formation"], "formation": 1,
		"desc": "Formation. On-Enter and start of each round: all friendlies get +1 ATK this fight.",
		"passive": "riteforge_ramp"},
	"warchief": {"id": "warchief", "name": "Warchief", "type": "creature", "cost": 3, "atk": 2, "hp": 6,
		"rarity": "rare", "keywords": ["formation"], "formation": 1,
		"desc": "Formation. Its ATK is always 2 plus the number of your other creatures.",
		"passive": "warchief_aura"},
	"doom_knight": {"id": "doom_knight", "name": "Doom Knight", "type": "creature", "cost": 4, "atk": 5, "hp": 4,
		"rarity": "rare", "keywords": ["piercing", "doom", "on_death"], "doom": 3,
		"desc": "Piercing. Doom 3. On-Death: deal 4 damage to enemy face.",
		"on_death": {"type": "damage_face", "value": 4}},
	"inferno": {"id": "inferno", "name": "Inferno", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 4 damage to all enemy creatures and 4 damage to enemy face. Exhaust.",
		"spell": {"type": "custom", "id": "inferno"}, "targeting": "none"},
	"overwhelming_force": {"id": "overwhelming_force", "name": "Rout", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Shove every enemy creature into its back row, deal 1 damage to each, and stop them attacking this round. Exhaust.",
		"spell": {"type": "custom", "id": "rout"}, "targeting": "none"},
	"the_leveler": {"id": "the_leveler", "name": "The Leveler", "type": "creature", "cost": 5, "atk": 6, "hp": 6,
		"rarity": "rare", "keywords": ["on_enter", "piercing"], "desc": "Piercing. On-Enter: deal 3 damage to all enemies.",
		"on_enter": {"type": "damage_all_enemies", "value": 3}},

	# ═══════════════════════════════════════════
	#  PYRE / DOOM-BURN — showcases doom / rampage / lifelink.
	#  Fragile bodies that detonate into the enemy face on a short timer
	#  (doom), a snowballing killer (rampage), and a little blood back for
	#  the player (lifelink). Beginner-readable; the Kindler hero draws on
	#  these. Each id reuses an existing portrait (see CardArtAliases /
	#  the matching .png stem) so none render blank.
	# ═══════════════════════════════════════════
	# ─── Doom creatures (ticking bombs) ───────────────────────────────────
	"cinder_pup": {"id": "cinder_pup", "name": "Cinder Pup", "type": "creature", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["doom"], "doom": 2,
		"desc": "Doom 2."},
	"kindling": {"id": "kindling", "name": "Kindling", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["doom", "on_death"], "doom": 2,
		"desc": "Doom 2. On-Death: deal 2 damage to enemy face.",
		"on_death": {"type": "damage_face", "value": 2}},
	"burning_martyr": {"id": "burning_martyr", "name": "Burning Martyr", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["doom", "on_death"], "doom": 3,
		"desc": "Doom 3. On-Death: deal 1 damage to all enemies.",
		"on_death": {"type": "damage_all_enemies", "value": 1}},
	"hellfire_imp": {"id": "hellfire_imp", "name": "Hellfire Imp", "type": "creature", "cost": 2, "atk": 4, "hp": 3,
		"rarity": "uncommon", "keywords": ["doom", "swift"], "doom": 2,
		"desc": "Swift. Doom 2."},
	"cinder_whelp": {"id": "cinder_whelp", "name": "Cinder Whelp", "type": "creature", "cost": 3, "atk": 5, "hp": 4,
		"rarity": "rare", "keywords": ["doom", "on_death"], "doom": 2,
		"desc": "Doom 2. On-Death: deal 3 damage to all enemies.",
		"on_death": {"type": "damage_all_enemies", "value": 3}},
	# ─── Rampage (snowball) ───────────────────────────────────────────────
	"ash_hound": {"id": "ash_hound", "name": "Ash Hound", "type": "creature", "cost": 1, "atk": 2, "hp": 1,
		"rarity": "common", "keywords": ["rampage"], "rampage": 1,
		"desc": "Rampage."},
	"ember_stalker": {"id": "ember_stalker", "name": "Powder Cart", "type": "creature", "cost": 2, "atk": 0, "hp": 4,
		"rarity": "uncommon", "keywords": ["doom", "on_death"], "doom": 3,
		"desc": "Doom 3. On-Death: your other Doom creatures detonate immediately.",
		"on_death": {"type": "detonate_dooms"}},
	# ─── Lifelink (sustain) ───────────────────────────────────────────────
	"bloodsworn": {"id": "bloodsworn", "name": "Bloodsworn", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["lifelink"], "lifelink": 1,
		"desc": "Lifelink."},
	"cinder_acolyte": {"id": "cinder_acolyte", "name": "Cinder Acolyte", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["lifelink"], "lifelink": 1,
		"desc": "Lifelink. Whenever your hero heals, this gains +1 ATK this fight.",
		"passive": "grows_on_heal"},
	"ember_warden": {"id": "ember_warden", "name": "Ember Warden", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": [],
		"desc": "Whenever enemy face takes damage from a spell or effect, this gains +1 ATK this fight.",
		"passive": "grows_on_burn"},
	# ─── Pyre spells ──────────────────────────────────────────────────────
	# Art is reused from existing spell frames (id == the stem of a painted
	# spell .png) so the card face is never blank.
	"concentrate": {"id": "concentrate", "name": "Immolate", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 4 damage to a creature. If it dies, deal 4 damage to enemy face.",
		"spell": {"type": "custom", "id": "immolate"}, "targeting": "any_creature"},
	"battle_hymn": {"id": "battle_hymn", "name": "Wildfire", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 2 damage to all enemy creatures. Enemy face takes 1 damage for each enemy that dies this way. Exhaust.",
		"spell": {"type": "custom", "id": "wildfire"}, "targeting": "none"},
	"mending_light": {"id": "mending_light", "name": "Censer Light", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "A friendly creature gains Lifelink and +1 ATK this fight.",
		"spell": {"type": "custom", "id": "censer_light"}, "targeting": "friendly_creature"},

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
	"lost_tome": {"id": "lost_tome", "name": "Lost Tome", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": ["exhaust"],
		"desc": "Discover a common spell. Exhaust.",
		"spell": {"type": "custom", "id": "lost_tome"}, "targeting": "none"},
	"scholar": {"id": "scholar", "name": "Scholar", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"],
		"desc": "On-Enter: Discover a spell.",
		"on_enter": {"type": "discover", "type_filter": "spell", "rarity_filter": ""}},
	"war_council": {"id": "war_council", "name": "War Council", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Discover any card. Exhaust.",
		"spell": {"type": "custom", "id": "war_council"}, "targeting": "none"},
	"treasure_hunter": {"id": "treasure_hunter", "name": "Treasure Hunter", "type": "creature", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": ["on_enter"],
		"desc": "On-Enter: Discover a rare card.",
		"on_enter": {"type": "discover", "type_filter": "any", "rarity_filter": "rare"}},

	# ═══════════════════════════════════════════
	#  2026-07-07 "MAKE IT FUN" SLATE — six designs that hook systems the pool
	#  underused: the back row (Trebuchet, Rat Piper), the dismissal action
	#  (The Volunteer), the persistent hand (Slow Match), the run's Roll of
	#  the Fallen (Muster the Fallen), and honest table-flip gambling (Petard).
	# ═══════════════════════════════════════════
	"rat_piper": {"id": "rat_piper", "name": "Rat Piper", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": [],
		"desc": "On-Enter: a 1/1 Rat scurries into this lane's back row.",
		"on_play": {"type": "summon_back", "atk": 1, "hp": 1}},
	"slow_match": {"id": "slow_match", "name": "Slow Match", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [],
		"desc": "Deal 2 damage to a creature, +1 for every turn this waited in your hand (max +4).",
		"spell": {"type": "custom", "id": "slow_match"}, "targeting": "any_creature"},
	"petard": {"id": "petard", "name": "The Petard", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "Deal 5 damage to a creature and 2 damage to adjacent creatures in its row.",
		"spell": {"type": "custom", "id": "petard"}, "targeting": "any_creature"},
	"volunteer": {"id": "volunteer", "name": "The Volunteer", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": [], "dismiss_muster": true,
		"desc": "When discarded: a copy of it musters into your first open lane anyway."},
	"trebuchet": {"id": "trebuchet", "name": "Trebuchet", "type": "creature", "cost": 3, "atk": 0, "hp": 6,
		"rarity": "rare", "keywords": [],
		"desc": "Each round it holds the back row: deal 3 damage to enemy face.",
		"passive": "trebuchet_volley"},
	"muster_fallen": {"id": "muster_fallen", "name": "Muster the Fallen", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Summon a 1/1 Shade for each name on the Roll of the Fallen (max 4, at least 1). Exhaust.",
		"spell": {"type": "custom", "id": "muster_fallen"}, "targeting": "none"},

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
		"rarity": "starter", "keywords": [], "desc": "A dead card forced into your hand. Can't be played — it just wastes a draw and clogs a slot.",
		"spell": {"type": "none"}, "targeting": "none"},
	"wound": {"id": "wound", "name": "Wound", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": ["retain"],
		"desc": "Retain — sticks in your hand every turn. Can't be played: a permanent dead slot.",
		"spell": {"type": "none"}, "targeting": "none"},
	"craven": {"id": "craven", "name": "Cowardice", "type": "spell", "cost": 2,
		"rarity": "starter", "keywords": ["exhaust"], "curse_playable": true,
		"desc": "Does nothing, then Exhausts. Paying 2 Command buys your fear out of the fight.",
		"spell": {"type": "none"}, "targeting": "none"},
	"deserters_mark": {"id": "deserters_mark", "name": "Deserter's Mark", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [],
		"curse_on_draw": {"type": "lose_command", "value": 1},
		"desc": "Can't be played. When drawn: lose 1 Command this turn.",
		"spell": {"type": "none"}, "targeting": "none"},
	"grave_debt": {"id": "grave_debt", "name": "Grave-Debt", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [],
		"curse_on_draw": {"type": "hero_damage", "value": 1},
		"desc": "Can't be played. When drawn: take 1 damage.",
		"spell": {"type": "none"}, "targeting": "none"},
	"war_debt": {"id": "war_debt", "name": "War-Debt", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [],
		"curse_on_draw": {"type": "lose_gold", "value": 2},
		"desc": "Can't be played. When drawn: the ledger collects 2 gold.",
		"spell": {"type": "none"}, "targeting": "none"},
	# The Coin — handed to whoever goes SECOND in a skirmish (Hearthstone-style),
	# in place of a raw extra opening card. Never drafted or discovered (rarity
	# "starter" is skipped by the discover pool, and its custom id is deliberately
	# kept out of SkirmishState.NET_SPELL_CUSTOMS so the draft pool excludes it);
	# Combat hands it over as a synthetic hand card (uid -1) that vanishes on play.
	"coin": {"id": "coin", "name": "The Coin", "type": "spell", "cost": 0,
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
	# ─── Starters ─────────────────────────────────────────────────────────
	"goblin":         {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to enemy face."},
	"brute":          {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to the opposing creature."},
	"troll":          {"atk": 1, "hp": 1},
	"sprite":         {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Enter: adjacent creatures get +2 ATK this round."},
	"naga":           {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Enter: deal 3 damage to the opposing creature."},
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
		"desc": "Deal 2 damage to a creature."},

	# ─── Common creatures ─────────────────────────────────────────────────
	"crystal_sentry": {"atk": 1, "hp": 1,
		"desc": "Shield. On-Enter: adjacent friendlies gain Shield."},
	"hound":          {"atk": 1, "hp": 1, "on_play_value": 1, "on_death_value": 1,
		"desc": "On-Enter: deal 3 damage to a random enemy creature."},
	"shieldbearer":   {"atk": 1, "hp": 1,
		"desc": "Shield. When its Shield breaks: this gains +3 ATK this fight."},
	"pikeman":        {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Enter: shove the opposing creature into its back row. If it can't move, deal 3 damage to it instead."},
	"lookout":        {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Swift. Front row: +2 ATK this fight. Back row: draw 1."},
	"warding_stone":  {"atk": 0, "hp": 2, "on_play_value": 1,
		"desc": "Guardian. Thorns. Adjacent enemies must attack this. Nearby enemy face damage is reduced by 1."},
	"hexblade":       {"atk": 1, "hp": 1,
		"desc": "Sniper. Hits the lowest-HP enemy, repeating on a kill. +1 ATK per spell cast this fight."},
	"harpy":          {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Swift. On-Enter: pull the opposing back-row enemy forward. Whatever ends up opposing this takes 3 damage and can't attack this round."},
	"thornguard":     {"atk": 1, "hp": 2, "on_play_value": 1,
		"desc": "Thorns. On-Death: deal 1 damage to all enemies."},
	"raven":          {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Sniper. Hits the lowest-HP enemy, repeating on a kill. On-Enter: deal 3 damage to a random enemy back-row creature."},
	"squire_captain": {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Enter: your other creatures in this row get +2 ATK this fight."},
	"plague_rat":     {"atk": 1, "hp": 1,
		"desc": "Poison."},
	"torchbearer":    {"atk": 1, "hp": 1, "adj_buff_atk": 1,
		"desc": "Formation. Adjacent friendlies +2 ATK."},
	"gravedigger":    {"atk": 1, "hp": 1,
		"desc": "When one of your creatures dies, draw 1 (up to twice per round)."},
	"bloodhound":     {"atk": 1, "hp": 1, "on_play_value": 1, "on_enter_value": 1,
		"desc": "On-Enter: deal 2 damage to the opposing creature and draw 1."},
	"scavenger":      {"atk": 1, "hp": 1,
		"desc": "Swift. Slay: gain 5 gold."},
	"stone_wall":     {"atk": 0, "hp": 3,
		"desc": "Guardian. Armored."},
	"tallow_doll":    {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: summon a 2/2 token in this lane."},
	"skirmisher":     {"atk": 1, "hp": 1,
		"desc": "Swift. Slay: draw 2."},
	"lancer":         {"atk": 1, "hp": 1,
		"desc": "Overrun 2."},

	# ─── Common spells ────────────────────────────────────────────────────
	"slash":          {"dmg_bonus": 1, "slay_draw": 1,
		"desc": "Deal 3 damage to an enemy creature and blast it into its back row. If it can't move, deal 2 extra damage. Slay: draw 2."},
	"shield_wall":    {"dmg_bonus": 2,  # bumps the bandage value via resolver
		"desc": "A friendly creature gets +6 HP and Thorns this round."},
	"war_cry":        {"dmg_bonus": 1,
		"desc": "All friendlies get +1 ATK and Swift this round."},
	"provision":      {"remove_keywords": ["exhaust"],
		"desc": "Summon a 2/1 Soldier in an empty lane."},
	"patch_up":       {"cost": -1,
		"desc": "Fully heal a friendly creature and draw 1. It can't attack this round."},
	"flame_bolt":     {"dmg_bonus": 2,
		"desc": "Deal 5 damage to enemy face. Deal 7 instead if you've already cast a spell this turn."},
	"shove":          {"dmg_bonus": 2,
		"desc": "Shove an enemy creature into its back row. If it can't move, deal 2 damage to it and it can't attack this round."},
	"gambit":         {"add_keywords": ["retain"],
		"desc": "Discard up to 3 cards, then draw that many. Retain."},
	"blood_tithe":    {"dmg_bonus": 2,
		"desc": "Deal 6 damage to enemy face. Take 2 damage yourself."},
	"reckless_charge": {"dmg_bonus": 2,
		"desc": "Deal 4 damage to any target. If a Curse is in your hand, exhaust it: deal 8 instead."},
	"quick_shot":     {"dmg_bonus": 2,
		"desc": "Deal 3 damage to any target. Slay: draw 1. Exhaust."},
	"frost_bolt":     {"dmg_bonus": 2,
		"desc": "An enemy creature can't attack this round and takes 2 damage."},
	"adrenaline":     {"extra_draw": 1,
		"desc": "Gain 2 Command. Draw 2 cards. Exhaust."},
	"hex":            {"dmg_bonus": 1,
		"desc": "Deal 2 damage to an enemy creature, or 5 if it has any keywords. Remove all its keywords."},
	"ricochet":       {"dmg_bonus": 1,
		"desc": "Deal 3 damage to each back-row enemy. If none are back there, deal 2 damage to a random enemy creature."},

	# ─── Uncommon creatures ───────────────────────────────────────────────
	"battle_drummer": {"atk": 1, "hp": 1, "add_keywords": ["swift"],
		"desc": "Armored. Swift. Adjacent friendlies have Swift."},
	"witch":          {"atk": 1, "hp": 1,
		"desc": "Your first spell each turn costs 1 less."},
	"duelist":        {"atk": 1, "hp": 1,
		"desc": "On-Enter: gains +1/+1 this fight for each unspent Command you have."},
	"griffin":        {"atk": 1, "hp": 1,
		"desc": "Swift. On-Death: this creature returns to your hand (once per fight)."},
	"revenant":       {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Death: this creature returns to play at full HP (once per fight)."},
	"berserker":      {"atk": 1, "hp": 2,
		"desc": "Whenever this is hit and survives, it gains +3 ATK."},
	"mule":           {"atk": 1, "hp": 1,
		"desc": "Summon."},
	"husk":           {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "Guardian. On-Death: summon a 3/3 token in this lane."},
	"basilisk":       {"atk": 1, "hp": 1,
		"desc": "Poison. Thorns. Its Thorns are poisonous — creatures that strike it die."},
	"necromancer":    {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: summon a 3/3 token in both rows of its lane."},
	"carrion_priest": {"atk": 1, "hp": 1,
		"desc": "Guardian. Whenever one of your creatures dies, deal 2 damage to enemy face and heal your hero 1."},
	"gravecaller":    {"atk": 1, "hp": 1,
		"desc": "On-Enter: gains +1/+1 this fight for each friendly that has fallen this fight."},
	"breaker":        {"atk": 1, "hp": 1,
		"desc": "Attacks twice each round."},
	"cleave_hound":   {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "When this attacks: also deals 1 damage to adjacent opposing creatures."},
	"blood_pyre":     {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Enter: sacrifice this creature. Adjacent friendlies get +4 ATK this fight, and draw a card."},
	"copycat":        {"atk": 1, "hp": 2,
		"desc": "On-Enter: become a copy of a chosen friendly creature."},
	"familiar":       {"atk": 1, "hp": 1,
		"desc": "On-Enter: Discover a creature."},
	"adaptable":      {"atk": 1, "hp": 1, "add_keywords": ["swift"],
		"desc": "Swift. On-Enter: gain Swift, Piercing, Armored, or Thorns (you choose)."},
	"vengeance":      {"atk": 1, "hp": 1,
		"desc": "Overrun. Gains +3 ATK this fight whenever you take face damage."},
	"iron_bastion":   {"atk": 1, "hp": 2,
		"desc": "Armored. Formation. Enemy face damage is reduced by 1."},
	"leyline_conduit": {"atk": 0, "hp": 2,
		"desc": "Formation. Start of each of your turns: gain +1 Command."},
	"the_glutton":    {"atk": 1, "hp": 1,
		"desc": "Overrun. On-Enter: devour adjacent friendlies — gain +3/+3 and their keywords for each one eaten."},
	"standard_bearer": {"atk": 1, "hp": 1,
		"desc": "Your summoned tokens enter with +2/+2."},
	"shieldmaiden":   {"atk": 1, "hp": 2,
		"desc": "Guardian. On-Death: adjacent friendlies gain Shield."},
	"the_apothecary": {"atk": 1, "hp": 1,
		"desc": "Whenever an enemy creature dies, deal 2 damage to enemy face."},
	"emberwright":    {"atk": 1, "hp": 1,
		"desc": "Whenever you cast a spell, deal 3 damage to enemy face."},
	"summoner":       {"atk": 1, "hp": 1,
		"desc": "Guardian. Start of each round: summon a 2/2 token in an adjacent empty lane."},
	"paladin":        {"atk": 1, "hp": 1,
		"desc": "Last Stand. When its Last Stand triggers: your creatures get +3 ATK this fight and your hero heals 3."},
	"royal_guard":    {"atk": 1, "hp": 1,
		"desc": "Adjacent friendlies take -1 damage. Gains +2 ATK each time this is hit."},
	"ironclad_veteran": {"atk": 1, "hp": 1,
		"desc": "Enters with +1/+1 for every 2 kills this card has made this run."},
	"sin_eater":      {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "On-Enter: eat a Curse from your hand (exhaust it) — this gains +3/+3 and you draw 1."},
	"glass_knight":   {"atk": 1, "hp": 1,
		"desc": "Shield. Swift. Slay: regain Shield."},
	"doppelganger":   {"atk": 1, "hp": 1,
		"desc": "On-Enter: become a copy of the most recently dead creature."},

	# ─── Uncommon spells ──────────────────────────────────────────────────
	"smite_spell":    {"dmg_bonus": 3,
		"desc": "Deal 9 damage to a creature. Slay: gain 1 Command and draw 1. Exhaust."},
	"inspire":        {"dmg_bonus": 1,
		"desc": "All friendlies gain Swift and Piercing this round. They get +1 ATK this round. Exhaust."},
	"ambush":         {"dmg_bonus": 1,
		"desc": "Deal 2 damage to all enemy creatures. Your Swift creatures get +2 ATK this round."},
	"reanimate":      {"dmg_bonus": 1,  # repurposed: revive stat bump
		"desc": "Summon the last creature to die as a 2/2 (keeps its keywords). Exhaust."},
	"charge_spell":   {"cost": -1,
		"desc": "A friendly creature attacks every opposing lane this round."},
	"offering":       {"extra_draw": 1,
		"desc": "Sacrifice a friendly creature. Gain 2 Command. Draw 1. Exhaust."},
	"grave_pact":     {"dmg_bonus": 2,
		"desc": "Deal 5 damage to a creature — 8 instead if a friendly has fallen this fight."},
	"fuel_the_pyre":  {"dmg_bonus": 2,
		"desc": "Sacrifice a friendly creature. Deal damage equal to its ATK + 2 to the enemy creature opposing it (or a random enemy)."},
	"venom_tip":      {"cost": -1,
		"desc": "A friendly creature gains Poison this round."},
	"pillage":        {"dmg_bonus": 1, "slay_gold": 5,
		"desc": "Deal 3 damage to an enemy creature and 2 damage to enemy face. Slay: gain 15 gold."},
	"echo_spell":     {"remove_keywords": ["exhaust"],
		"desc": "Copy the last spell you cast this turn."},
	"turbo":          {"extra_draw": 1,
		"desc": "Gain 2 Command. Draw 1 card. Add a Curse to your discard pile."},
	"recycle":        {"extra_draw": 1,
		"desc": "Exhaust a card from hand. Gain Command equal to its cost. Draw 1."},
	"dark_pact":      {"dmg_bonus": 1,
		"desc": "Sacrifice a friendly creature. Other friendlies get +2/+2 this fight."},
	"war_chant":      {"desc": "Discard up to 3 cards. Summon a 3/2 Soldier for each. Exhaust."},
	"grave_robbery":  {"cost": -1,
		"desc": "Return the last creature to die to your hand. Exhaust."},
	"soul_swap":      {"dmg_bonus": 2,
		"desc": "An enemy creature swaps its ATK and HP, then takes 2 damage."},
	"lay_on_hands":   {"cost": -1,
		"desc": "Your creatures' attacks are poisonous this round. Exhaust."},
	"hoarfrost":      {"cost": -1,
		"desc": "A friendly creature gains Shield. The opposing creature can't attack this round."},
	"holy_smite":     {"cost": -1, "slay_draw": 1,
		"desc": "Deal damage to an enemy creature equal to its missing HP, but at least 3. Slay: draw 2."},
	"overwhelming_force": {"dmg_bonus": 1,
		"desc": "Shove every enemy creature into its back row, deal 2 damage to each, and stop them attacking this round. Exhaust."},

	# ─── Rare creatures ───────────────────────────────────────────────────
	"dragon_hatchling": {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "Swift. On-Enter: deal 3 damage to all enemies."},
	"assassin":       {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Swift. On-Enter: destroy the opposing creature if its HP is 4 or less."},
	"hydra":          {"atk": 1, "hp": 1, "rampage": 1,
		"desc": "Rampage 2, Armored. Doesn't attack directly — hits every opposing lane at once, taking each defender's counter."},
	"corpse_eater":   {"atk": 1, "hp": 1,
		"desc": "Piercing. Gains +2 ATK whenever a friendly creature dies."},
	"vampire_lord":   {"atk": 1, "hp": 1, "on_play_value": 1,
		"desc": "Regenerate. Slay (with this creature): heal you 2 HP and gain +2 ATK."},
	"chaos_imp":      {"atk": 1, "hp": 1,
		"desc": "On-Enter: cast a random spell that costs 1 or less, for free (auto-targeted)."},
	"warden_of_graves": {"atk": 1, "hp": 1,
		"desc": "Your friendly On-Death effects trigger twice."},
	"siege_golem":    {"atk": 1, "hp": 2,
		"desc": "Overrun 3. Ignores Guardian and Thorns."},
	"old_bones":      {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"desc": "On-Death: rises again, smaller — a 3/3, then a 2/2, then a 1/1."},

	# ─── Rare spells ──────────────────────────────────────────────────────
	"earthquake":     {"dmg_bonus": 1,
		"desc": "Deal 3 damage to every creature. Shove surviving enemy front-row creatures into their back row. Exhaust."},
	"kings_command":  {"dmg_bonus": 1,
		"desc": "All friendlies get +1/+1 this fight for each friendly creature, and +1/+1 more. Exhaust."},
	"unholy_bargain": {"extra_draw": 1,
		"desc": "Draw 3 cards, +1 if a friendly has fallen this fight. Take 2 face damage. Exhaust."},
	"mass_grave":     {"dmg_bonus": 2,
		"desc": "Deal damage to every enemy creature equal to the number of cards in your discard pile + 2, but at least 3. Exhaust."},
	"cataclysm":      {"dmg_bonus": 2,
		"desc": "A friendly creature deals its ATK + 2 to all enemies in its lane and adjacent lanes. Exhaust."},
	"apocalypse":     {"cost": -1,
		"desc": "Destroy every creature on the board. Take 1 face damage for each one that dies. Exhaust."},
	"banish":         {"dmg_bonus": 2, "extra_draw": 1,
		"desc": "Remove an enemy creature with 6 or less HP from the fight. If it has more HP, deal 6 damage instead. Draw 1. Exhaust."},
	"time_snare":     {"cost": -1,
		"desc": "This round, your creatures attack twice. Draw 1. Exhaust."},
	"plague_bell":    {"dmg_bonus": 1,
		"desc": "Deal 2 damage to every creature on the board. If any died, cast this again. Exhaust."},

	# ─── 4-cost powerhouses ───────────────────────────────────────────────
	"riteforge":      {"hp": 2,
		"desc": "Formation. On-Enter and start of each round: all friendlies get +2 ATK this fight."},
	"warchief":       {"atk": 1, "hp": 1,
		"desc": "Formation. Its ATK is always 3 plus the number of your other creatures."},
	"doom_knight":    {"atk": 1, "hp": 2, "on_death_value": 2,
		"desc": "Piercing. Doom 3. On-Death: deal 6 damage to enemy face."},
	"inferno":        {"dmg_bonus": 1,
		"desc": "Deal 5 damage to all enemy creatures and 5 damage to enemy face. Exhaust."},
	"the_leveler":    {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "Piercing. On-Enter: deal 4 damage to all enemies."},

	# ─── 2026-07-07 fun slate ─────────────────────────────────────────────
	# rat_piper / trebuchet / muster_fallen scale via is_upgraded reads in
	# their resolvers (token size / volley damage); the descs promise exactly
	# those numbers.
	"rat_piper":      {"atk": 1, "hp": 1,
		"desc": "On-Enter: a 2/2 Rat scurries into this lane's back row."},
	"slow_match":     {"dmg_bonus": 2,
		"desc": "Deal 4 damage to a creature, +1 for every turn this waited in your hand (max +4)."},
	"petard":         {"dmg_bonus": 2,
		"desc": "Deal 7 damage to a creature and 4 damage to adjacent creatures in its row."},
	"volunteer":      {"atk": 1, "hp": 1,
		"desc": "When discarded: a copy of it musters into your first open lane anyway."},
	"trebuchet":      {"hp": 2,
		"desc": "Each round it holds the back row: deal 4 damage to enemy face."},
	"muster_fallen":  {"desc": "Summon a 2/2 Shade for each name on the Roll of the Fallen (max 4, at least 1). Exhaust."},

	# ─── Discover cards ───────────────────────────────────────────────────
	"lost_tome":      {"cost": -1,
		"desc": "Discover a common spell. Exhaust."},
	"scholar":        {"atk": 1, "hp": 1,
		"desc": "On-Enter: Discover a spell."},
	"war_council":    {"cost": -1,
		"desc": "Discover any card. Exhaust."},
	"treasure_hunter": {"atk": 1, "hp": 1,
		"desc": "On-Enter: Discover a rare card."},

	# ─── Pyre / Doom-Burn (Kindler set) ───────────────────────────────────
	# Doom creatures can't bump their timer through the generic merge (there's
	# no "doom" key handler in _apply_plus_upgrade), so they upgrade on body /
	# on_death value instead — a bigger bomb, not a faster one (pacing: keep
	# the fuse short). Rampage / Lifelink creatures already get +1 to their
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
		"desc": "Doom 3. On-Death: your other Doom creatures detonate immediately."},
	"mark_of_ash":    {"desc": "An enemy creature gains Doom 1 with no blast. If it already has Doom, detonate it."},
	"bloodsworn":     {"atk": 1, "hp": 1,
		"desc": "Lifelink."},
	"cinder_acolyte": {"atk": 1, "hp": 1,
		"desc": "Lifelink. Whenever your hero heals, this gains +2 ATK this fight."},
	"ember_warden":   {"atk": 1, "hp": 1,
		"desc": "Whenever enemy face takes damage from a spell or effect, this gains +2 ATK this fight."},
	"concentrate":    {"dmg_bonus": 2,
		"desc": "Deal 6 damage to a creature. If it dies, deal 6 damage to enemy face."},
	"battle_hymn":    {"dmg_bonus": 1,
		"desc": "Deal 3 damage to all enemy creatures. Enemy face takes 1 damage for each enemy that dies this way. Exhaust."},
	"mending_light":  {"dmg_bonus": 1,
		"desc": "A friendly creature gains Lifelink and +2 ATK this fight."},
}


# Returns the upgrade delta for a card id. Falls back to a sensible default
# so any future card without a hand-crafted entry still upgrades cleanly:
# creatures get +1/+1, spells get -1 cost. Curses return {} (unupgradeable).
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
	"e_goblin": {"id": "e_goblin", "name": "Goblin", "type": "creature", "cost": 0, "atk": 2, "hp": 2,
		"rarity": "enemy", "keywords": [], "act": 1, "desc": ""},
	"e_scout": {"id": "e_scout", "name": "Scout", "type": "creature", "cost": 0, "atk": 2, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 1, "desc": ""},
	"e_brute": {"id": "e_brute", "name": "Brute", "type": "creature", "cost": 0, "atk": 3, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 1, "desc": ""},
	"e_archer": {"id": "e_archer", "name": "Archer", "type": "creature", "cost": 0, "atk": 2, "hp": 3,
		"rarity": "enemy", "keywords": ["on_enter"], "act": 1, "desc": "",
		"on_enter": {"type": "damage_random_player", "value": 1}},
	"e_golem": {"id": "e_golem", "name": "Golem", "type": "creature", "cost": 0, "atk": 2, "hp": 4,
		"rarity": "enemy", "keywords": ["armored"], "act": 1, "desc": "Armored."},
	"e_wind_harpy": {"id": "e_wind_harpy", "name": "Wind Harpy", "type": "creature", "cost": 0, "atk": 3, "hp": 2,
		"rarity": "enemy", "keywords": ["swift"], "act": 1, "desc": "Swift."},
	# Act 2 — keywords
	"e_cultist": {"id": "e_cultist", "name": "Cultist", "type": "creature", "cost": 0, "atk": 3, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 2, "desc": ""},
	"e_dark_priest": {"id": "e_dark_priest", "name": "Dark Priest", "type": "creature", "cost": 0, "atk": 2, "hp": 4,
		"rarity": "enemy", "keywords": ["regenerate"], "act": 2, "desc": "Regenerate."},
	"e_enforcer": {"id": "e_enforcer", "name": "Enforcer", "type": "creature", "cost": 0, "atk": 4, "hp": 3,
		"rarity": "enemy", "keywords": ["swift"], "act": 2, "desc": "Swift."},
	"e_bog_lurker": {"id": "e_bog_lurker", "name": "Bog Lurker", "type": "creature", "cost": 0, "atk": 2, "hp": 5,
		"rarity": "enemy", "keywords": [], "act": 2, "desc": ""},
	"e_bone_knight": {"id": "e_bone_knight", "name": "Bone Knight", "type": "creature", "cost": 0, "atk": 3, "hp": 4,
		"rarity": "enemy", "keywords": ["on_death"], "act": 2, "desc": "",
		"on_death": {"type": "summon", "atk": 2, "hp": 2}},
	# Act 3 — combos
	"e_fire_elemental": {"id": "e_fire_elemental", "name": "Fire Elemental", "type": "creature", "cost": 0, "atk": 4, "hp": 3,
		"rarity": "enemy", "keywords": [], "act": 3, "desc": ""},
	"e_headsman": {"id": "e_headsman", "name": "Headsman", "type": "creature", "cost": 0, "atk": 4, "hp": 4,
		"rarity": "enemy", "keywords": [], "act": 3, "desc": ""},
	"e_drake": {"id": "e_drake", "name": "Drake", "type": "creature", "cost": 0, "atk": 3, "hp": 4,
		"rarity": "enemy", "keywords": ["piercing"], "act": 3, "desc": "Piercing."},
	"e_elder_dragon": {"id": "e_elder_dragon", "name": "Elder Dragon", "type": "creature", "cost": 0, "atk": 5, "hp": 6,
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
# 100. Reward quality escalates with the campaign: commons are the act-1
# workhorses but near-dead picks by act 3 (the deck outgrows them), so the late
# slates lean uncommon/rare — late picks should feel late. Exposed via
# act_rarity_weights() so other slates can borrow an act's odds; the skirmish
# DRAFT rolls at act-3 weights so a drafted warband feels late-campaign.
const ACT_REWARD_WEIGHTS: Dictionary = {
	1: [65, 30, 5],
	2: [50, 40, 10],
	3: [30, 50, 20],
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
		weights = [0, 70, 30]
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
