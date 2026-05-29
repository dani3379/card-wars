extends Node
## CardDB.gd — all card definitions: 6 starter + 83 draft pool + enemy creatures.
##
## Card schema:
##   id, name, type ("creature"/"spell"), cost, rarity ("starter"/"common"/"uncommon"/"rare"/"enemy")
##   Creature: atk, hp, keywords, desc, and optional: on_enter, on_death, floop, adj_buff, wither, passive
##   ALL creatures have a floop: {"type": "...", "value": X, ...}
##   Spell: keywords, desc, spell {type, value, ...}, targeting ("enemy_creature"/"friendly_creature"/"any_creature"/"any"/"none")

const CARD_POOL: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTER CARDS — 10-card deck: 4 Peasant, 4 Soldier, 1 Squire, 1 Footman
	# ═══════════════════════════════════════════
	"goblin": {"id": "goblin", "name": "Goblin", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": ["on_enter"], "desc": "On-enter: deal 1 to enemy face.",
		"on_enter": {"type": "damage_face", "value": 1}},
	"brute": {"id": "brute", "name": "Brute", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["on_enter"], "desc": "On-enter: deal 1 damage to the opposing creature.",
		"on_enter": {"type": "damage_opposing", "value": 1}},
	"troll": {"id": "troll", "name": "Troll", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["floop"], "desc": "Floop: heal this creature 2 HP.",
		"floop": {"type": "heal_self", "value": 2}},
	"sprite": {"id": "sprite", "name": "Sprite", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": ["floop"], "desc": "Floop: adjacent creatures get +1 ATK this round.",
		"floop": {"type": "buff_adjacent_atk", "value": 1}},
	"naga": {"id": "naga", "name": "Naga", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "starter", "keywords": ["floop"], "desc": "Floop: deal 2 damage to the opposing creature.",
		"floop": {"type": "damage_opposing", "value": 2}},
	"ratling": {"id": "ratling", "name": "Ratling", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "starter", "keywords": ["wither", "on_death", "floop"], "wither": 1,
		"desc": "Wither 1. On-death: deal 2 to opposing. Floop: deal 1 to opposing, gain +1 ATK this combat.",
		"on_death": {"type": "damage_opposing_lane", "value": 2},
		"floop": {"type": "damage_opposing_grow", "value": 1, "atk_gain": 1}},
	"strike": {"id": "strike", "name": "Strike", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 3 damage to a creature.",
		"spell": {"type": "damage", "value": 3}, "targeting": "any_creature"},
	"fireball": {"id": "fireball", "name": "Fireball", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 3 damage to enemy face.",
		"spell": {"type": "damage_face", "value": 3}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  COMMON CREATURES (17) — All have Floop
	# ═══════════════════════════════════════════
	"crystal_sentry": {"id": "crystal_sentry", "name": "Crystal Sentry", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": ["shield", "floop"],
		"desc": "Shield. Floop: adjacent friendly gains Shield.",
		"floop": {"type": "grant_shield_adjacent"}},
	"hound": {"id": "hound", "name": "Hound", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["on_death", "floop"], "desc": "On-death: deal 2 to opposing. Floop: deal 2 to a random enemy creature.",
		"on_death": {"type": "damage_opposing_lane", "value": 2},
		"floop": {"type": "damage_any", "value": 2}},
	"shieldbearer": {"id": "shieldbearer", "name": "Shieldbearer", "type": "creature", "cost": 2, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": ["armored", "floop"], "desc": "Armored. Floop: adjacent friendlies take -1 damage this round.",
		"floop": {"type": "shield_adjacent", "value": 1}},
	"pikeman": {"id": "pikeman", "name": "Pikeman", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: deal 1 to opposing. Floop: deal 1 to opposing and adjacent enemy lanes.",
		"on_enter": {"type": "damage_opposing", "value": 1},
		"floop": {"type": "damage_opposing_splash", "value": 1}},
	"lookout": {"id": "lookout", "name": "Lookout", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: draw 1. Floop: look at the top card of your deck; keep it or send it to the bottom.",
		"on_enter": {"type": "draw", "value": 1},
		"floop": {"type": "scry", "value": 1}},
	"warding_stone": {"id": "warding_stone", "name": "Warding Stone", "type": "creature", "cost": 1, "atk": 0, "hp": 5,
		"rarity": "common", "keywords": ["guardian", "thorns", "floop"],
		"desc": "Guardian. Thorns. Adjacent enemies must attack this. Floop: heal this creature 2 HP.",
		"passive": "cannot_attack_wall",
		"floop": {"type": "heal_self", "value": 2}},
	"hexblade": {"id": "hexblade", "name": "Hexblade", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["floop"],
		"desc": "+1 ATK per spell cast this fight. Floop: next spell costs 1 less.",
		"passive": "atk_per_spell",
		"floop": {"type": "discount_next", "value": 1}},
	"harpy": {"id": "harpy", "name": "Harpy", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["swift", "floop"], "desc": "Swift. Floop: move to any empty friendly lane.",
		"floop": {"type": "relocate"}},
	"thornguard": {"id": "thornguard", "name": "Thornguard", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "common", "keywords": ["thorns", "on_death", "floop"], "desc": "Thorns. On-death: deal 1 to all enemies. Floop: gain +2 Thorns this round.",
		"on_death": {"type": "damage_all_enemies", "value": 1},
		"floop": {"type": "buff_thorns", "value": 2}},
	"raven": {"id": "raven", "name": "Raven", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["ranged", "floop"], "desc": "Ranged. Floop: look at the top 3 cards of your deck and reorder them.",
		"floop": {"type": "reorder_deck", "value": 3}},
	"squire_captain": {"id": "squire_captain", "name": "Squire Captain", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": ["summon", "floop"], "desc": "Summon. Floop: your token creatures get +1 ATK this round.",
		"floop": {"type": "buff_tokens_atk", "value": 1}},
	"plague_rat": {"id": "plague_rat", "name": "Plague Rat", "type": "creature", "cost": 1, "atk": 1, "hp": 1,
		"rarity": "common", "keywords": ["poison", "on_death", "floop"],
		"desc": "Poison. On-death: deal 1 to opposing. Floop: deal 1 to opposing.",
		"on_death": {"type": "damage_opposing_lane", "value": 1},
		"floop": {"type": "damage_opposing", "value": 1}},
	"torchbearer": {"id": "torchbearer", "name": "Torchbearer", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["adj_buff", "wither", "floop"], "wither": 1, "desc": "Adjacent friendlies +1 ATK. Wither 1. Floop: adjacent friendlies gain Thorns 1 this round.",
		"adj_buff": {"atk": 1, "hp": 0},
		"floop": {"type": "grant_thorns_adjacent", "value": 1}},
	"gravedigger": {"id": "gravedigger", "name": "Gravedigger", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["floop"], "desc": "When a friendly dies: draw 1. Floop: return a random creature from your discard pile to your hand.",
		"passive": "draw_on_ally_death",
		"floop": {"type": "raise_dead"}},
	"bloodhound": {"id": "bloodhound", "name": "Bloodhound", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: deal 1 to opposing and draw 1. Floop: deal 1 to opposing. Slay: draw 1.",
		"on_enter": {"type": "damage_opposing_draw", "value": 1},
		"floop": {"type": "slay_draw", "value": 1}},
	"scavenger": {"id": "scavenger", "name": "Scavenger", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: gain 5 gold. Floop: gain 2 gold.",
		"on_enter": {"type": "gain_gold", "value": 5},
		"floop": {"type": "gain_gold", "value": 2}},
	"stone_wall": {"id": "stone_wall", "name": "Stone Wall", "type": "creature", "cost": 1, "atk": 0, "hp": 5,
		"rarity": "common", "keywords": ["thorns", "floop"],
		"desc": "Thorns. Can't attack. Reduces face damage from adjacent empty lanes by 1. Floop: adjacent friendlies gain Armored this round.",
		"passive": "cannot_attack_wall",
		"floop": {"type": "shield_adjacent", "value": 1}},
	"mana_sprite": {"id": "mana_sprite", "name": "Mana Sprite", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["floop"], "desc": "Floop: gain 1 mana this turn.",
		"floop": {"type": "gain_mana", "value": 1}},
	"tallow_doll": {"id": "tallow_doll", "name": "Tallow Doll", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["floop"],
		"desc": "Gets +1/+1 for each other Tallow Doll you've played this fight. Floop: deal 1 to opposing.",
		"passive": "tallow_stacking",
		"floop": {"type": "damage_opposing", "value": 1}},

	# ═══════════════════════════════════════════
	#  COMMON SPELLS (13)
	# ═══════════════════════════════════════════
	"slash": {"id": "slash", "name": "Slash", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to a creature. Slay: draw 1.",
		"spell": {"type": "custom", "id": "slash"}, "targeting": "any_creature"},
	"shield_wall": {"id": "shield_wall", "name": "Shield Wall", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Target friendly gets +4 HP and Thorns this round.",
		"spell": {"type": "custom", "id": "shield_wall"}, "targeting": "friendly_creature"},
	"war_cry": {"id": "war_cry", "name": "War Cry", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "All friendlies get +1 ATK and Swift this round.",
		"spell": {"type": "custom", "id": "war_cry"}, "targeting": "none"},
	"provision": {"id": "provision", "name": "Provision", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Draw 2 cards. Exhaust.",
		"spell": {"type": "draw", "value": 2}, "targeting": "none"},
	"patch_up": {"id": "patch_up", "name": "Patch Up", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Heal a friendly creature for 4 HP. If it was already at full HP, draw 1.",
		"spell": {"type": "custom", "id": "patch_up"}, "targeting": "friendly_creature"},
	"flame_bolt": {"id": "flame_bolt", "name": "Flame Bolt", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to enemy face. Deal 5 instead if you've already cast a spell this turn.",
		"spell": {"type": "custom", "id": "flame_bolt"}, "targeting": "none"},
	"shove": {"id": "shove", "name": "Shove", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Deal 2 damage to an enemy creature and reduce its ATK by 1.",
		"spell": {"type": "custom", "id": "shove"}, "targeting": "enemy_creature"},
	"gambit": {"id": "gambit", "name": "Gambit", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Discard up to 3 cards, then draw that many.",
		"spell": {"type": "custom", "id": "gambit"}, "targeting": "none"},
	"blood_tithe": {"id": "blood_tithe", "name": "Blood Tithe", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to enemy face. Take 2 damage yourself.",
		"spell": {"type": "custom", "id": "blood_tithe"}, "targeting": "none"},
	"reckless_charge": {"id": "reckless_charge", "name": "Reckless Charge", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 3 damage to a creature. Draw 1. Take 1 damage yourself.",
		"spell": {"type": "custom", "id": "reckless_charge"}, "targeting": "any_creature"},
	"quick_shot": {"id": "quick_shot", "name": "Quick Shot", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Deal 1 damage to any target (creature or face). Draw 1.",
		"spell": {"type": "custom", "id": "quick_shot"}, "targeting": "any"},
	"scrap": {"id": "scrap", "name": "Scrap", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Discard 1 card. Gain 1 mana this turn.",
		"spell": {"type": "custom", "id": "scrap"}, "targeting": "none"},
	"frost_bolt": {"id": "frost_bolt", "name": "Frost Bolt", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Target creature can't attack this round.",
		"spell": {"type": "custom", "id": "frost_bolt"}, "targeting": "any_creature"},
	"adrenaline": {"id": "adrenaline", "name": "Adrenaline", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Gain 1 mana. Draw 1 card. Exhaust.",
		"spell": {"type": "custom", "id": "adrenaline"}, "targeting": "none"},
	"hex": {"id": "hex", "name": "Hex", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 2 damage to an enemy creature and remove all its keywords.",
		"spell": {"type": "custom", "id": "hex"}, "targeting": "enemy_creature"},

	# ═══════════════════════════════════════════
	#  UNCOMMON CREATURES (17) — All have Floop
	# ═══════════════════════════════════════════
	"battle_drummer": {"id": "battle_drummer", "name": "Battle Drummer", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["adj_buff", "floop"], "desc": "Adjacent friendlies +2 ATK. Floop: all friendlies get +1 ATK this combat.",
		"adj_buff": {"atk": 2, "hp": 0},
		"floop": {"type": "buff_all_atk_permanent", "value": 1}},
	"witch": {"id": "witch", "name": "Witch", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: draw 1. Floop: gain 1 mana.",
		"on_enter": {"type": "draw", "value": 1},
		"floop": {"type": "gain_mana", "value": 1}},
	"duelist": {"id": "duelist", "name": "Duelist", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift", "on_enter", "floop"], "desc": "Swift. On-enter: deal 2 to opposing. Floop: deal 2 to opposing and heal this creature 2 HP.",
		"on_enter": {"type": "damage_opposing", "value": 2},
		"floop": {"type": "damage_opposing_heal", "value": 2, "heal": 2}},
	"griffin": {"id": "griffin", "name": "Griffin", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift", "on_death", "floop"], "desc": "Swift. On-death: this creature returns to your hand (once per fight). Floop: this turn, can attack any opposing lane.",
		"on_death": {"type": "return_to_hand_once"},
		"floop": {"type": "challenge"}},
	"revenant": {"id": "revenant", "name": "Revenant", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death", "floop"],
		"desc": "On-death: this creature returns to play at 1 HP (once per fight). Floop: deal 1 to opposing.",
		"on_death": {"type": "reborn"},
		"floop": {"type": "damage_opposing", "value": 1}},
	"berserker": {"id": "berserker", "name": "Berserker", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "Gains +1 ATK each round this attacks. Takes +1 damage from all sources. Floop: deal 2 to opposing, take 1 damage.",
		"passive": "grow_on_attack", "extra_damage": 1,
		"floop": {"type": "damage_self_opposing", "value": 2, "self_damage": 1}},
	"mule": {"id": "mule", "name": "Mule", "type": "creature", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: draw 1. Floop: discard a card, then draw 1.",
		"on_enter": {"type": "draw", "value": 1},
		"floop": {"type": "filter_draw"}},
	"husk": {"id": "husk", "name": "Husk", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["floop"],
		"desc": "Gains +1/+1 (this combat) whenever any creature on either side dies. Floop: heal this creature 2 HP.",
		"passive": "grow_on_any_death",
		"floop": {"type": "heal_self", "value": 2}},
	"basilisk": {"id": "basilisk", "name": "Basilisk", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["poison", "floop"],
		"desc": "Poison. Floop: deal 1 to opposing.",
		"floop": {"type": "damage_opposing", "value": 1}},
	"necromancer": {"id": "necromancer", "name": "Necromancer", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death", "floop"], "desc": "On-death: summon a 2/2 token in this lane. Floop: destroy an adjacent friendly, then summon a 2/2 token in its lane.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2},
		"floop": {"type": "kill_adjacent_summon", "atk": 2, "hp": 2}},
	"cleave_hound": {"id": "cleave_hound", "name": "Cleave Hound", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"],
		"desc": "When this attacks: also deals 1 damage to adjacent opposing creatures. Floop: +1 ATK this round.",
		"passive": "cleave",
		"floop": {"type": "self_buff_atk", "value": 1}},
	"blood_pyre": {"id": "blood_pyre", "name": "Blood Pyre", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death", "floop"], "desc": "On-death: gain +1 mana next turn. Floop: sacrifice this creature; adjacent friendlies get +2 ATK this combat.",
		"on_death": {"type": "bonus_mana", "value": 1},
		"floop": {"type": "blood_sacrifice", "value": 2}},
	"copycat": {"id": "copycat", "name": "Copycat", "type": "creature", "cost": 2, "atk": 0, "hp": 1,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: become a copy of a chosen friendly creature. Floop: use the opposing creature's floop instead.",
		"on_enter": {"type": "copy_friendly"},
		"floop": {"type": "copy_opposing_floop"}},
	"familiar": {"id": "familiar", "name": "Familiar", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"],
		"desc": "On-enter: Discover a creature. Floop: that creature gains +1/+1 this fight.",
		"on_enter": {"type": "discover_link", "type_filter": "creature", "rarity_filter": ""},
		"floop": {"type": "buff_familiar_pick", "atk": 1, "hp": 1}},
	"adaptable": {"id": "adaptable", "name": "Adaptable", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"],
		"desc": "On-enter: gain Swift, Piercing, Armored, or Thorns (you choose). Floop: +1 ATK this round.",
		"on_enter": {"type": "choose_keyword"},
		"floop": {"type": "self_buff_atk", "value": 1}},
	"vengeance": {"id": "vengeance", "name": "Vengeance", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"],
		"desc": "Gains +2 ATK (this combat) whenever you take face damage. Floop: deal 2 damage to enemy face.",
		"passive": "vengeance_growth",
		"floop": {"type": "damage_face", "value": 2}},
	"iron_bastion": {"id": "iron_bastion", "name": "Iron Bastion", "type": "creature", "cost": 3, "atk": 1, "hp": 7,
		"rarity": "uncommon", "keywords": ["armored", "floop"], "desc": "Armored. Enemy face damage is reduced by 1. Floop: all friendlies gain Armored this round.",
		"passive": "reduce_face_damage",
		"floop": {"type": "grant_armored_all"}},
	"leyline_conduit": {"id": "leyline_conduit", "name": "Leyline Conduit", "type": "creature", "cost": 2, "atk": 0, "hp": 4,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "Gain +1 mana at start of each of your turns. Floop: gain 2 mana this turn.",
		"passive": "mana_per_turn",
		"floop": {"type": "gain_mana", "value": 2}},
	"the_glutton": {"id": "the_glutton", "name": "The Glutton", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"],
		"desc": "On-enter: destroy adjacent friendlies. Gain +2/+2 for each destroyed. Floop: +1 ATK this round.",
		"on_enter": {"type": "glutton_devour"},
		"floop": {"type": "self_buff_atk", "value": 1}},
	"standard_bearer": {"id": "standard_bearer", "name": "Standard Bearer", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"],
		"desc": "The first 1-cost creature you play each turn summons a 1/1 token in an empty lane. Floop: summon a 1/1 in a random empty friendly lane.",
		"passive": "standard_bearer_summon",
		"floop": {"type": "summon_random", "atk": 1, "hp": 1}},

	# ═══════════════════════════════════════════
	#  UNCOMMON SPELLS (12)
	# ═══════════════════════════════════════════
	"smite_spell": {"id": "smite_spell", "name": "Smite", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 6 damage to a creature. Slay: gain 1 mana and draw 1. Exhaust.",
		"spell": {"type": "custom", "id": "smite_spell"}, "targeting": "any_creature"},
	"inspire": {"id": "inspire", "name": "Inspire", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "All friendlies get +2 ATK and Piercing this round. Exhaust.",
		"spell": {"type": "custom", "id": "inspire"}, "targeting": "none"},
	"ambush": {"id": "ambush", "name": "Ambush", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 1 damage to all enemy creatures. Your Swift creatures get +1 ATK this round.",
		"spell": {"type": "custom", "id": "ambush"}, "targeting": "none"},
	"reanimate": {"id": "reanimate", "name": "Reanimate", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Summon the last creature to die as a 1/1 (keeps its keywords). Exhaust.",
		"spell": {"type": "custom", "id": "reanimate"}, "targeting": "none"},
	"charge_spell": {"id": "charge_spell", "name": "Charge!", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Target friendly attacks every opposing lane this round.",
		"spell": {"type": "custom", "id": "charge_spell"}, "targeting": "friendly_creature"},
	"ricochet": {"id": "ricochet", "name": "Ricochet", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Four times, deal 1 damage to a random enemy creature.",
		"spell": {"type": "custom", "id": "ricochet"}, "targeting": "none"},
	"offering": {"id": "offering", "name": "Offering", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Sacrifice a friendly creature. Gain 2 mana. Exhaust.",
		"spell": {"type": "custom", "id": "offering"}, "targeting": "friendly_creature"},
	"grave_pact": {"id": "grave_pact", "name": "Grave Pact", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["retain"], "desc": "The next friendly creature that dies returns to your hand. Retain.",
		"spell": {"type": "custom", "id": "grave_pact"}, "targeting": "none"},
	"fuel_the_pyre": {"id": "fuel_the_pyre", "name": "Fuel the Pyre", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Sacrifice a friendly creature. Deal damage equal to its ATK to any target.",
		"spell": {"type": "custom", "id": "fuel_the_pyre"}, "targeting": "friendly_creature"},
	"venom_tip": {"id": "venom_tip", "name": "Venom Tip", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Target friendly creature gains Poison this round. Exhaust.",
		"spell": {"type": "custom", "id": "venom_tip"}, "targeting": "friendly_creature"},
	"pillage": {"id": "pillage", "name": "Pillage", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 3 damage to a creature. Slay: gain 10 gold.",
		"spell": {"type": "custom", "id": "pillage"}, "targeting": "any_creature"},
	"echo_spell": {"id": "echo_spell", "name": "Echo", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Copy the last spell you cast this turn. (Does nothing if you haven't cast one.) Exhaust.",
		"spell": {"type": "custom", "id": "echo_spell"}, "targeting": "none"},
	"bloodletting": {"id": "bloodletting", "name": "Bloodletting", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Lose 1 HP. Gain 2 mana.",
		"spell": {"type": "custom", "id": "bloodletting"}, "targeting": "none"},
	"turbo": {"id": "turbo", "name": "Turbo", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Gain 2 mana. Add a Curse to your discard pile.",
		"spell": {"type": "custom", "id": "turbo"}, "targeting": "none"},
	"recycle": {"id": "recycle", "name": "Recycle", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Exhaust a card from hand. Gain mana equal to its cost.",
		"spell": {"type": "custom", "id": "recycle"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  RARE CREATURES (14) — All have Floop
	# ═══════════════════════════════════════════
	"dragon_hatchling": {"id": "dragon_hatchling", "name": "Dragon Hatchling", "type": "creature", "cost": 4, "atk": 3, "hp": 4,
		"rarity": "rare", "keywords": ["on_enter", "wither", "floop"], "wither": 1, "desc": "On-enter: deal 2 to all enemies. Wither 1. Floop: deal 1 to every creature on the board (both sides).",
		"on_enter": {"type": "damage_all_enemies", "value": 2},
		"floop": {"type": "damage_all", "value": 1}},
	"royal_guard": {"id": "royal_guard", "name": "Royal Guard", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "Adjacent friendlies take -1 damage. Gains +1 ATK each time this is hit. Floop: redirect attacks against adjacent friendlies to this creature instead.",
		"passive": "royal_guard",
		"floop": {"type": "redirect_adjacent"}},
	"assassin": {"id": "assassin", "name": "Assassin", "type": "creature", "cost": 2, "atk": 5, "hp": 1,
		"rarity": "rare", "keywords": ["swift", "piercing", "floop"], "desc": "Swift. Piercing. Dies at end of round. Floop: destroy the opposing creature if its HP is 2 or less.",
		"passive": "dies_end_of_turn",
		"floop": {"type": "execute", "value": 2}},
	"hydra": {"id": "hydra", "name": "Hydra", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "rare", "keywords": ["floop"], "desc": "Attacks every opposing lane each round. Floop: gains +1 ATK for each enemy creature on the board.",
		"passive": "attacks_all_lanes",
		"floop": {"type": "grow_per_enemies"}},
	"summoner": {"id": "summoner", "name": "Summoner", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["summon", "floop"], "desc": "Summon. Floop: summon a 1/1 token in a random empty friendly lane.",
		"floop": {"type": "summon_random", "atk": 1, "hp": 1}},
	"paladin": {"id": "paladin", "name": "Paladin", "type": "creature", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["last_stand", "adj_buff", "floop"], "desc": "Last Stand. Adjacent friendlies +1 ATK. Floop: heal all your creatures for 2 HP.",
		"adj_buff": {"atk": 1, "hp": 0},
		"floop": {"type": "heal_all_friendly", "value": 2}},
	"corpse_eater": {"id": "corpse_eater", "name": "Corpse Eater", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": ["floop"], "desc": "Gains +1 ATK whenever a friendly creature dies. Floop: destroy an adjacent friendly and gain its ATK and HP.",
		"passive": "grow_on_ally_death",
		"floop": {"type": "devour_adjacent"}},
	"ironclad_veteran": {"id": "ironclad_veteran", "name": "Ironclad Veteran", "type": "creature", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: gains +1 ATK for each card you've played this turn. Floop: your next 2 cards this turn cost 1 less.",
		"on_enter": {"type": "atk_per_cards_played"},
		"floop": {"type": "discount_next", "value": 2}},
	"glass_knight": {"id": "glass_knight", "name": "Glass Knight", "type": "creature", "cost": 2, "atk": 3, "hp": 2,
		"rarity": "uncommon", "keywords": ["shield", "swift", "floop"],
		"desc": "Shield. Swift. Floop: +1 ATK this round.",
		"floop": {"type": "self_buff_atk", "value": 1}},
	"doppelganger": {"id": "doppelganger", "name": "Doppelganger", "type": "creature", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "rare", "keywords": ["on_enter", "floop"], "desc": "On-enter: become a copy of the most recently dead creature. Floop: become a copy of the opposing creature until end of round.",
		"on_enter": {"type": "copy_last_dead"},
		"floop": {"type": "become_copy"}},
	"vampire_lord": {"id": "vampire_lord", "name": "Vampire Lord", "type": "creature", "cost": 3, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": ["regenerate", "floop"], "desc": "Regenerate. Slay (with this creature): heal you 2 HP and gain +1 ATK. Floop: deal 2 to opposing and heal this creature 2 HP.",
		"passive": "vampire_lord",
		"floop": {"type": "drain", "value": 2}},
	"chaos_imp": {"id": "chaos_imp", "name": "Chaos Imp", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: cast a random spell at no mana cost (auto-targeted). Floop: discard the top card of your deck and deal damage equal to its cost to a random enemy.",
		"on_enter": {"type": "cast_random_spell"},
		"floop": {"type": "discard_top_damage"}},
	"warden_of_graves": {"id": "warden_of_graves", "name": "Warden of Graves", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": ["floop"], "desc": "Your friendly on-death effects trigger twice. Floop: deal damage to opposing equal to the number of creatures in your discard pile.",
		"passive": "double_on_death",
		"floop": {"type": "graveyard_damage"}},
	"siege_golem": {"id": "siege_golem", "name": "Siege Golem", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["floop"], "desc": "Only attacks when its opposing lane is empty (face damage only). Floop: deal 3 damage to the opposing creature.",
		"passive": "siege",
		"floop": {"type": "damage_opposing", "value": 3}},

	# ═══════════════════════════════════════════
	#  RARE SPELLS (10)
	# ═══════════════════════════════════════════
	"earthquake": {"id": "earthquake", "name": "Earthquake", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 3 damage to every creature on the board (both sides). Exhaust.",
		"spell": {"type": "damage_all", "value": 3}, "targeting": "none"},
	"kings_command": {"id": "kings_command", "name": "King's Command", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "All friendlies get +3 ATK this round and a permanent +1 HP. Exhaust.",
		"spell": {"type": "custom", "id": "kings_command"}, "targeting": "none"},
	"unholy_bargain": {"id": "unholy_bargain", "name": "Unholy Bargain", "type": "spell", "cost": 0,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Draw 3 cards. Take 3 face damage. Exhaust.",
		"spell": {"type": "custom", "id": "unholy_bargain"}, "targeting": "none"},
	"mass_grave": {"id": "mass_grave", "name": "Mass Grave", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal damage to every enemy creature equal to the number of cards in your discard pile. Exhaust.",
		"spell": {"type": "custom", "id": "mass_grave"}, "targeting": "none"},
	"dark_pact": {"id": "dark_pact", "name": "Dark Pact", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "All friendlies get +1 ATK this combat. Take 2 face damage.",
		"spell": {"type": "custom", "id": "dark_pact"}, "targeting": "none"},
	"war_chant": {"id": "war_chant", "name": "War Chant", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Discard 2 cards. Draw 2 cards.",
		"spell": {"type": "custom", "id": "war_chant"}, "targeting": "none"},
	"grave_robbery": {"id": "grave_robbery", "name": "Grave Robbery", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Return the last creature to die to your hand. Exhaust.",
		"spell": {"type": "custom", "id": "grave_robbery"}, "targeting": "none"},
	"cataclysm": {"id": "cataclysm", "name": "Cataclysm", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal damage to every enemy equal to your highest-ATK friendly's ATK. Exhaust.",
		"spell": {"type": "custom", "id": "cataclysm"}, "targeting": "none"},
	"soul_swap": {"id": "soul_swap", "name": "Soul Swap", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Swap a creature's ATK and HP.",
		"spell": {"type": "custom", "id": "soul_swap"}, "targeting": "any_creature"},
	"apocalypse": {"id": "apocalypse", "name": "Apocalypse", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Destroy every creature on the board. Take 1 face damage for each one that dies. Exhaust.",
		"spell": {"type": "custom", "id": "apocalypse"}, "targeting": "none"},
	"lay_on_hands": {"id": "lay_on_hands", "name": "Lay on Hands", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Heal a friendly to full HP and give it +2 max HP this combat.",
		"spell": {"type": "custom", "id": "lay_on_hands"}, "targeting": "friendly_creature"},
	"hoarfrost": {"id": "hoarfrost", "name": "Hoarfrost", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [],
		"desc": "Target friendly gains Shield. The opposing enemy can't attack this round.",
		"spell": {"type": "custom", "id": "hoarfrost"}, "targeting": "friendly_creature"},
	"banish": {"id": "banish", "name": "Banish", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Remove an enemy creature from the fight. Its on-death does not trigger.",
		"spell": {"type": "custom", "id": "banish"}, "targeting": "enemy_creature"},
	"time_snare": {"id": "time_snare", "name": "Time Snare", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "No enemy creature can attack this round. Exhaust.",
		"spell": {"type": "custom", "id": "time_snare"}, "targeting": "none"},
	"holy_smite": {"id": "holy_smite", "name": "Holy Smite", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal damage to an enemy creature equal to its missing HP.",
		"spell": {"type": "custom", "id": "holy_smite"}, "targeting": "enemy_creature"},
	"plague_bell": {"id": "plague_bell", "name": "Plague Bell", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"],
		"desc": "Deal 1 damage to every creature on the board. If any died, cast this again. Exhaust.",
		"spell": {"type": "custom", "id": "plague_bell"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  4-COST POWERHOUSES (require mana banking)
	# ═══════════════════════════════════════════
	"riteforge": {"id": "riteforge", "name": "Riteforge", "type": "creature", "cost": 4, "atk": 0, "hp": 5,
		"rarity": "rare", "keywords": ["floop"],
		"desc": "Start of each round: all friendlies get +1 ATK this combat. Floop: gain 1 mana.",
		"passive": "riteforge_ramp",
		"floop": {"type": "gain_mana", "value": 1}},
	"warchief": {"id": "warchief", "name": "Warchief", "type": "creature", "cost": 4, "atk": 0, "hp": 5,
		"rarity": "rare", "keywords": ["floop"],
		"desc": "Start of each round: this creature's ATK becomes the number of friendly creatures on the board. Floop: summon a 1/1 token in a random empty lane.",
		"passive": "warchief_aura",
		"floop": {"type": "summon_random", "atk": 1, "hp": 1}},
	"doom_knight": {"id": "doom_knight", "name": "Doom Knight", "type": "creature", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["piercing", "swift", "floop"], "desc": "Swift. Piercing. Floop: +2 ATK this round.",
		"floop": {"type": "self_buff_atk", "value": 2}},
	"inferno": {"id": "inferno", "name": "Inferno", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 4 damage to all enemy creatures and 4 damage to enemy face. Exhaust.",
		"spell": {"type": "custom", "id": "inferno"}, "targeting": "none"},
	"overwhelming_force": {"id": "overwhelming_force", "name": "Overwhelming Force", "type": "spell", "cost": 4,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "All friendly creatures get +3 ATK this combat. Exhaust.",
		"spell": {"type": "custom", "id": "overwhelming_force"}, "targeting": "none"},

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
		"desc": "On-enter: Discover a spell.",
		"on_enter": {"type": "discover", "type_filter": "spell", "rarity_filter": ""}},
	"war_council": {"id": "war_council", "name": "War Council", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"],
		"desc": "Discover any card. Exhaust.",
		"spell": {"type": "custom", "id": "war_council"}, "targeting": "none"},
	"treasure_hunter": {"id": "treasure_hunter", "name": "Treasure Hunter", "type": "creature", "cost": 3, "atk": 2, "hp": 3,
		"rarity": "rare", "keywords": ["on_enter"],
		"desc": "On-enter: Discover a rare card.",
		"on_enter": {"type": "discover", "type_filter": "any", "rarity_filter": "rare"}},

	# Curses (added by events / boss relics / encounter passives).
	"curse": {"id": "curse", "name": "Curse", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [], "desc": "Does nothing. Wastes a draw.",
		"spell": {"type": "none"}, "targeting": "none"},
	"wound": {"id": "wound", "name": "Wound", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": ["retain"],
		"desc": "Retain. Does nothing. Clogs your hand.",
		"spell": {"type": "none"}, "targeting": "none"},
}

const CURSE_IDS: Array[String] = ["curse", "wound"]


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
#   floop_value, floop_atk_gain         delta for sub-effect .value fields
#   adj_buff_atk, adj_buff_hp           delta for adj_buff.atk / .hp
#   wither, extra_damage                delta on the top-level integer field
#   slay_draw, slay_gold, slay_mana     custom-spell slay payoff bumps
#                                       (read by specific resolvers)
#   extra_draw, extra_mana              custom-spell tail bonuses
#                                       (read by specific resolvers)
#   ricochet_hits                       ricochet-only — extra hits
#   desc                                replace description text outright
const UPGRADES: Dictionary = {
	# ─── Starters ─────────────────────────────────────────────────────────
	"goblin":         {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-enter: deal 2 to enemy face."},
	"brute":          {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-enter: deal 2 damage to the opposing creature."},
	"troll":          {"atk": 1, "hp": 2, "floop_value": 1,
		"desc": "Floop: heal this creature 3 HP."},
	"sprite":         {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Floop: adjacent creatures get +2 ATK this round."},
	"naga":           {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Floop: deal 3 damage to the opposing creature."},
	"ratling":        {"atk": 1, "hp": 1, "on_death_value": 1, "floop_atk_gain": 1,
		"desc": "Wither 1. On-death: deal 3 to opposing. Floop: deal 1 to opposing, gain +2 ATK this combat."},
	"strike":         {"value": 3,
		"desc": "Deal 6 damage to a creature."},
	"fireball":       {"value": 2,
		"desc": "Deal 5 damage to enemy face."},

	# ─── Common creatures ─────────────────────────────────────────────────
	"crystal_sentry": {"atk": 1, "hp": 1,
		"desc": "Shield. Floop: adjacent friendly gains Shield."},
	"hound":          {"atk": 1, "hp": 1, "floop_value": 1, "on_death_value": 1,
		"desc": "On-death: deal 3 to opposing. Floop: deal 3 to a random enemy creature."},
	"shieldbearer":   {"atk": 0, "hp": 2,
		"desc": "Armored. Floop: adjacent friendlies take -1 damage this round."},
	"pikeman":        {"atk": 1, "hp": 1, "floop_value": 1, "on_enter_value": 1,
		"desc": "On-enter: deal 2 to opposing. Floop: deal 2 to opposing and adjacent enemy lanes."},
	"lookout":        {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "On-enter: draw 2. Floop: look at the top card of your deck; keep it or send it to the bottom."},
	"warding_stone":  {"atk": 0, "hp": 2, "floop_value": 1,
		"desc": "Guardian. Thorns. Floop: heal this creature 3 HP."},
	"hexblade":       {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "+1 ATK per spell cast this fight. Floop: next 2 spells cost 1 less."},
	"harpy":          {"atk": 1, "hp": 1,
		"desc": "Swift. Floop: move to any empty friendly lane."},
	"thornguard":     {"atk": 1, "hp": 2, "floop_value": 1,
		"desc": "Thorns. On-death: deal 1 to all enemies. Floop: gain +3 Thorns this round."},
	"raven":          {"atk": 1, "hp": 1,
		"desc": "Ranged. Floop: look at the top 3 cards of your deck and reorder them."},
	"squire_captain": {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Summon. Floop: your token creatures get +2 ATK this round (Squire Captain only)."},
	"plague_rat":     {"atk": 1, "hp": 1,
		"desc": "Poison. On-death: deal 1 to opposing. Floop: deal 1 to opposing."},
	"torchbearer":    {"atk": 1, "hp": 1, "adj_buff_atk": 1,
		"desc": "Adjacent friendlies +2 ATK. Wither 1. Floop: adjacent friendlies gain Thorns 1 this round."},
	"gravedigger":    {"atk": 1, "hp": 1,
		"desc": "When a friendly dies: draw 1. Floop: return a random creature from your discard pile to your hand."},
	"bloodhound":     {"atk": 1, "hp": 1, "floop_value": 1, "on_enter_value": 1,
		"desc": "On-enter: deal 2 to opposing and draw 1. Floop: deal 2 to opposing. Slay: draw 1."},
	"scavenger":      {"atk": 1, "hp": 1, "on_enter_value": 3, "floop_value": 1,
		"desc": "On-enter: gain 8 gold. Floop: gain 3 gold."},
	"stone_wall":     {"atk": 0, "hp": 3,
		"desc": "Thorns. Can't attack. Reduces face damage from adjacent empty lanes by 1. Floop: adjacent friendlies gain Armored this round."},
	"mana_sprite":    {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Floop: gain 2 mana this turn."},
	"tallow_doll":    {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Gets +1/+1 for each other Tallow Doll you've played this fight. Floop: deal 2 to opposing."},

	# ─── Common spells ────────────────────────────────────────────────────
	"slash":          {"dmg_bonus": 2, "slay_draw": 1,
		"desc": "Deal 5 damage to a creature. Slay: draw 2."},
	"shield_wall":    {"dmg_bonus": 2,  # bumps the bandage value via resolver
		"desc": "Target friendly gets +6 HP and Thorns this round."},
	"war_cry":        {"dmg_bonus": 1,
		"desc": "All friendlies get +2 ATK and Swift this round."},
	"provision":      {"remove_keywords": ["exhaust"],
		"desc": "Draw 2 cards."},
	"patch_up":       {"dmg_bonus": 2, "extra_draw": 1,
		"desc": "Heal a friendly for 6 HP. If it was already at full HP, draw 2."},
	"flame_bolt":     {"dmg_bonus": 2,
		"desc": "Deal 5 damage to enemy face. Deal 7 instead if you've already cast a spell this turn."},
	"shove":          {"dmg_bonus": 1, "extra_mana": 1,  # "extra_mana" repurposed: extra ATK debuff
		"desc": "Deal 3 damage to an enemy creature and reduce its ATK by 2."},
	"gambit":         {"add_keywords": ["retain"],
		"desc": "Discard up to 3 cards, then draw that many. Retain."},
	"blood_tithe":    {"dmg_bonus": 2,
		"desc": "Deal 5 damage to enemy face. Take 2 damage yourself."},
	"reckless_charge": {"dmg_bonus": 2, "extra_draw": 1,
		"desc": "Deal 5 damage to a creature. Draw 2. Take 1 damage yourself."},
	"quick_shot":     {"dmg_bonus": 1, "extra_draw": 1,
		"desc": "Deal 2 damage to any target. Draw 2."},
	"scrap":          {"extra_mana": 1,
		"desc": "Discard 1 card. Gain 2 mana this turn."},
	"frost_bolt":     {"dmg_bonus": 2,
		"desc": "Target creature can't attack this round. Take 2 damage."},
	"adrenaline":     {"extra_mana": 1,
		"desc": "Gain 2 mana. Draw 1 card. Exhaust."},
	"hex":            {"dmg_bonus": 2,
		"desc": "Deal 4 damage to an enemy creature and remove all its keywords."},
	"ricochet":       {"ricochet_hits": 2,
		"desc": "Six times, deal 1 damage to a random enemy creature."},

	# ─── Uncommon creatures ───────────────────────────────────────────────
	"battle_drummer": {"atk": 1, "hp": 1, "adj_buff_atk": 1,
		"desc": "Adjacent friendlies +3 ATK. Floop: all friendlies get +1 ATK this combat."},
	"witch":          {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "On-enter: draw 1. Floop: gain 2 mana."},
	"duelist":        {"atk": 1, "hp": 1, "on_enter_value": 1,
		"desc": "Swift. On-enter: deal 3 to opposing. Floop: deal 2 to opposing and heal this creature 2 HP."},
	"griffin":        {"atk": 1, "hp": 1,
		"desc": "Swift. On-death: this creature returns to your hand (once per fight). Floop: this turn, can attack any opposing lane."},
	"revenant":       {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "On-death: this creature returns to play at 1 HP (once per fight). Floop: deal 2 to opposing."},
	"berserker":      {"atk": 2, "hp": 1,
		"desc": "Gains +1 ATK each round this attacks. Takes +1 damage from all sources. Floop: deal 2 to opposing, take 1 damage."},
	"mule":           {"atk": 1, "hp": 1,
		"desc": "On-enter: draw 1. Floop: discard a card, then draw 2."},
	"husk":           {"atk": 1, "hp": 1,
		"desc": "Gains +1/+1 (this combat) whenever any creature on either side dies. Floop: heal this creature 3 HP."},
	"basilisk":       {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Poison. Floop: deal 2 to opposing."},
	"necromancer":    {"atk": 1, "hp": 1, "on_death_atk": 1, "on_death_hp": 1,
		"floop_atk": 1, "floop_hp": 1,
		"desc": "On-death: summon a 3/3 token in this lane. Floop: destroy an adjacent friendly, then summon a 3/3 token in its lane."},
	"cleave_hound":   {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "When this attacks: also deals 2 damage to adjacent opposing creatures. Floop: +2 ATK this round."},
	"blood_pyre":     {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "On-death: gain +1 mana next turn. Floop: sacrifice this creature; adjacent friendlies get +3 ATK this combat."},
	"copycat":        {"atk": 1, "hp": 2,
		"desc": "On-enter: become a copy of a chosen friendly creature. Floop: use the opposing creature's floop instead."},
	"familiar":       {"atk": 1, "hp": 1,
		"desc": "On-enter: Discover a creature. Floop: that creature gains +2/+2 this fight."},
	"adaptable":      {"atk": 1, "hp": 1, "add_keywords": ["swift"],
		"desc": "Swift. On-enter: gain Swift, Piercing, Armored, or Thorns (you choose). Floop: +1 ATK this round."},
	"vengeance":      {"atk": 1, "hp": 1,
		"desc": "Gains +3 ATK (this combat) whenever you take face damage. Floop: deal 3 damage to enemy face."},
	"iron_bastion":   {"atk": 1, "hp": 2,
		"desc": "Armored. Enemy face damage is reduced by 1. Floop: all friendlies gain Armored this round."},
	"leyline_conduit": {"atk": 0, "hp": 1, "floop_value": 1,
		"desc": "Gain +1 mana at start of each of your turns. Floop: gain 3 mana this turn."},
	"the_glutton":    {"atk": 1, "hp": 1,
		"desc": "On-enter: destroy adjacent friendlies. Gain +3/+3 for each destroyed. Floop: +1 ATK this round."},
	"standard_bearer": {"atk": 1, "hp": 1, "floop_atk": 1, "floop_hp": 1,
		"desc": "The first 1-cost creature you play each turn summons a 2/2 token in an empty lane. Floop: summon a 2/2 in a random empty friendly lane."},
	"summoner":       {"atk": 1, "hp": 1, "floop_atk": 1, "floop_hp": 1,
		"desc": "Summon. Floop: summon a 2/2 token in a random empty friendly lane."},
	"paladin":        {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Last Stand. Adjacent friendlies +1 ATK. Floop: heal all your creatures for 3 HP."},
	"royal_guard":    {"atk": 1, "hp": 1,
		"desc": "Adjacent friendlies take -1 damage. Gains +2 ATK each time this is hit. Floop: redirect attacks against adjacent friendlies to this creature instead."},
	"ironclad_veteran": {"atk": 1, "hp": 1,
		"desc": "On-enter: gains +1 ATK for each card you've played this turn. Floop: your next 3 cards this turn cost 1 less."},
	"glass_knight":   {"atk": 1, "hp": 1,
		"desc": "Shield. Swift. Floop: +2 ATK this round."},
	"doppelganger":   {"atk": 1, "hp": 1,
		"desc": "On-enter: become a copy of the most recently dead creature. Floop: become a copy of the opposing creature until end of round."},

	# ─── Uncommon spells ──────────────────────────────────────────────────
	"smite_spell":    {"dmg_bonus": 3,
		"desc": "Deal 9 damage to a creature. Slay: gain 1 mana and draw 1. Exhaust."},
	"inspire":        {"dmg_bonus": 1,
		"desc": "All friendlies get +3 ATK and Piercing this round. Exhaust."},
	"ambush":         {"dmg_bonus": 1,
		"desc": "Deal 2 damage to all enemy creatures. Your Swift creatures get +2 ATK this round."},
	"reanimate":      {"dmg_bonus": 1,  # repurposed: revive stat bump
		"desc": "Summon the last creature to die as a 2/2 (keeps its keywords). Exhaust."},
	"charge_spell":   {"cost": -1,
		"desc": "Target friendly attacks every opposing lane this round."},
	"offering":       {"extra_mana": 1,
		"desc": "Sacrifice a friendly creature. Gain 3 mana. Exhaust."},
	"grave_pact":     {"cost": -1,
		"desc": "The next friendly creature that dies returns to your hand. Retain."},
	"fuel_the_pyre":  {"dmg_bonus": 2,
		"desc": "Sacrifice a friendly creature. Deal damage equal to its ATK + 2 to any target."},
	"venom_tip":      {"cost": -1,
		"desc": "Target friendly creature gains Poison this round. Exhaust."},
	"pillage":        {"dmg_bonus": 2, "slay_gold": 5,
		"desc": "Deal 5 damage to a creature. Slay: gain 15 gold."},
	"echo_spell":     {"cost": -1,
		"desc": "Copy the last spell you cast this turn. Exhaust."},
	"bloodletting":   {"extra_mana": 1,
		"desc": "Lose 1 HP. Gain 3 mana."},
	"turbo":          {"extra_mana": 1,
		"desc": "Gain 3 mana. Add a Curse to your discard pile."},
	"recycle":        {"extra_mana": 1,
		"desc": "Exhaust a card from hand. Gain mana equal to its cost + 1."},
	"dark_pact":      {"dmg_bonus": 1,
		"desc": "All friendlies get +2 ATK this combat. Take 2 face damage."},
	"war_chant":      {"extra_draw": 1,
		"desc": "Discard 2 cards. Draw 3 cards."},
	"grave_robbery":  {"cost": -1,
		"desc": "Return the last creature to die to your hand. Exhaust."},
	"soul_swap":      {"cost": -1,
		"desc": "Swap a creature's ATK and HP."},
	"lay_on_hands":   {"dmg_bonus": 2,
		"desc": "Heal a friendly to full HP and give it +4 max HP this combat."},
	"hoarfrost":      {"cost": -1,
		"desc": "Target friendly gains Shield. The opposing enemy can't attack this round."},
	"holy_smite":     {"cost": -1,
		"desc": "Deal damage to an enemy creature equal to its missing HP."},
	"overwhelming_force": {"dmg_bonus": 1,
		"desc": "All friendly creatures get +4 ATK this combat. Exhaust."},

	# ─── Rare creatures ───────────────────────────────────────────────────
	"dragon_hatchling": {"atk": 1, "hp": 1, "on_enter_value": 1, "floop_value": 1,
		"desc": "On-enter: deal 3 to all enemies. Wither 1. Floop: deal 2 to every creature on the board (both sides)."},
	"assassin":       {"atk": 1, "hp": 0, "floop_value": 1,
		"desc": "Swift. Piercing. Dies at end of round. Floop: destroy the opposing creature if its HP is 3 or less."},
	"hydra":          {"atk": 1, "hp": 1,
		"desc": "Attacks every opposing lane each round. Floop: gains +2 ATK for each enemy creature on the board."},
	"corpse_eater":   {"atk": 1, "hp": 1,
		"desc": "Gains +2 ATK whenever a friendly creature dies. Floop: destroy an adjacent friendly and gain its ATK and HP."},
	"vampire_lord":   {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Regenerate. Slay: heal you 2 HP and gain +2 ATK. Floop: deal 3 to opposing and heal this creature 3 HP."},
	"chaos_imp":      {"atk": 1, "hp": 1,
		"desc": "On-enter: cast a random spell at no mana cost (auto-targeted). Floop: discard the top card of your deck and deal damage equal to its cost +1 to a random enemy."},
	"warden_of_graves": {"atk": 1, "hp": 1,
		"desc": "Your friendly on-death effects trigger twice. Floop: deal damage equal to the number of creatures in your discard pile +2 to opposing."},
	"siege_golem":    {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Only attacks when its opposing lane is empty (face damage only). Floop: deal 4 damage to the opposing creature."},

	# ─── Rare spells ──────────────────────────────────────────────────────
	"earthquake":     {"value": 1,
		"desc": "Deal 4 damage to every creature on the board (both sides). Exhaust."},
	"kings_command":  {"dmg_bonus": 1,
		"desc": "All friendlies get +4 ATK this round and a permanent +2 HP. Exhaust."},
	"unholy_bargain": {"extra_draw": 1,
		"desc": "Draw 4 cards. Take 3 face damage. Exhaust."},
	"mass_grave":     {"dmg_bonus": 2,
		"desc": "Deal damage to every enemy creature equal to the number of cards in your discard pile + 2. Exhaust."},
	"cataclysm":      {"dmg_bonus": 2,
		"desc": "Deal damage to every enemy equal to your highest-ATK friendly's ATK + 2. Exhaust."},
	"apocalypse":     {"cost": -1,
		"desc": "Destroy every creature on the board. Take 1 face damage for each one that dies. Exhaust."},
	"banish":         {"cost": -1,
		"desc": "Remove an enemy creature from the fight. Its on-death does not trigger. Exhaust."},
	"time_snare":     {"cost": -1,
		"desc": "No enemy creature can attack this round. Exhaust."},
	"plague_bell":    {"dmg_bonus": 1,
		"desc": "Deal 2 damage to every creature on the board. If any died, cast this again. Exhaust."},

	# ─── 4-cost powerhouses ───────────────────────────────────────────────
	"riteforge":      {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Start of each round: all friendlies get +2 ATK this combat. Floop: gain 2 mana."},
	"warchief":       {"atk": 1, "hp": 1, "floop_atk": 1, "floop_hp": 1,
		"desc": "Start of each round: this creature's ATK becomes the number of friendly creatures on the board + 1. Floop: summon a 2/2 token in a random empty lane."},
	"doom_knight":    {"atk": 1, "hp": 1, "floop_value": 1,
		"desc": "Swift. Piercing. Floop: +3 ATK this round."},
	"inferno":        {"dmg_bonus": 1,
		"desc": "Deal 5 damage to all enemy creatures and 5 damage to enemy face. Exhaust."},

	# ─── Discover cards ───────────────────────────────────────────────────
	"lost_tome":      {"cost": -1,
		"desc": "Discover a common spell. Exhaust."},
	"scholar":        {"atk": 1, "hp": 1,
		"desc": "On-enter: Discover a spell."},
	"war_council":    {"cost": -1,
		"desc": "Discover any card. Exhaust."},
	"treasure_hunter": {"atk": 1, "hp": 1,
		"desc": "On-enter: Discover a rare card."},
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
	# curse gets added.
	return CURSE_IDS[randi() % CURSE_IDS.size()]


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
		if CARD_POOL[id].rarity == rarity:
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


static func roll_card_reward(act: int, is_elite: bool = false, is_boss: bool = false,
		count: int = 3) -> Array[String]:
	if is_boss:
		return _roll_from_rarity("rare", count)
	var weights: Array
	match act:
		1: weights = [65, 30, 5]
		2: weights = [55, 35, 10]
		_: weights = [45, 40, 15]
	if is_elite:
		weights = [0, 70, 30]
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
		var pool = get_pool_by_rarity(rarity)
		if pool.is_empty():
			continue
		var id = pool[randi() % pool.size()]
		if not picked.has(id):
			picked.append(id)
	return picked


static func _roll_from_rarity(rarity: String, count: int) -> Array[String]:
	var pool = get_pool_by_rarity(rarity)
	var picked: Array[String] = []
	var attempts := 0
	while picked.size() < count and attempts < 30:
		attempts += 1
		if pool.is_empty():
			break
		var id = pool[randi() % pool.size()]
		if not picked.has(id):
			picked.append(id)
	return picked
