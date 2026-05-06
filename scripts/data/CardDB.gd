extends Node
## CardDB.gd — all card definitions: 9 starter + 83 draft pool + enemy creatures.
##
## Card schema:
##   id, name, type ("creature"/"spell"), cost, rarity ("starter"/"common"/"uncommon"/"rare"/"enemy")
##   Creature: atk, hp, keywords, desc, and optional: on_enter, on_death, floop, adj_buff, wither, passive
##   Spell: keywords, desc, spell {type, value, ...}, targeting ("enemy_creature"/"friendly_creature"/"any_creature"/"any"/"none")

const CARD_POOL: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTER CARDS (9 unique, 12-card deck)
	# ═══════════════════════════════════════════
	"footman": {"id": "footman", "name": "Footman", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": [], "desc": "A reliable soldier."},
	"squire": {"id": "squire", "name": "Squire", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": [], "desc": "Eager but fragile."},
	"knight": {"id": "knight", "name": "Knight", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "starter", "keywords": [], "desc": "Stalwart and true."},
	"conscript": {"id": "conscript", "name": "Conscript", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "starter", "keywords": ["wither"], "wither": 1, "desc": "Wither 1. Fades fast."},
	"strike": {"id": "strike", "name": "Strike", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 3 to target creature.",
		"spell": {"type": "damage", "value": 3}, "targeting": "any_creature"},
	"fireball": {"id": "fireball", "name": "Fireball", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 2 to enemy face.",
		"spell": {"type": "damage_face", "value": 2}, "targeting": "none"},
	"bolster": {"id": "bolster", "name": "Bolster", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Target creature +2 ATK this turn.",
		"spell": {"type": "buff_atk", "value": 2, "permanent": false}, "targeting": "friendly_creature"},
	"mend": {"id": "mend", "name": "Mend", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Heal 2 from target creature.",
		"spell": {"type": "heal", "value": 2}, "targeting": "friendly_creature"},
	"rally": {"id": "rally", "name": "Rally", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Draw 2 cards.",
		"spell": {"type": "draw", "value": 2}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  COMMON CREATURES (17)
	# ═══════════════════════════════════════════
	"ranger": {"id": "ranger", "name": "Ranger", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": [], "desc": "Solid stats, no tricks."},
	"hound": {"id": "hound", "name": "Hound", "type": "creature", "cost": 1, "atk": 3, "hp": 2,
		"rarity": "common", "keywords": [], "desc": "Hits hard, dies fast."},
	"shieldbearer": {"id": "shieldbearer", "name": "Shieldbearer", "type": "creature", "cost": 2, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": ["armored"], "desc": "Armored. A walking wall."},
	"pikeman": {"id": "pikeman", "name": "Pikeman", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-enter: deal 1 to opposing creature.",
		"on_enter": {"type": "damage_opposing", "value": 1}},
	"lookout": {"id": "lookout", "name": "Lookout", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-enter: draw 1 card.",
		"on_enter": {"type": "draw", "value": 1}},
	"militia": {"id": "militia", "name": "Militia", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["retain"], "desc": "Retain. Always ready."},
	"wolf_c": {"id": "wolf_c", "name": "Wolf", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["on_death"], "desc": "On-death: deal 2 to opposing lane.",
		"on_death": {"type": "damage_opposing_lane", "value": 2}},
	"harpy": {"id": "harpy", "name": "Harpy", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["swift"], "desc": "Swift. Strikes first."},
	"thornguard": {"id": "thornguard", "name": "Thornguard", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "common", "keywords": ["thorns", "on_death"], "desc": "Thorns. On-death: 1 to ALL enemy creatures.",
		"on_death": {"type": "damage_all_enemies", "value": 1}},
	"raven": {"id": "raven", "name": "Raven", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["ranged"], "desc": "Ranged. Attacks random enemy creature."},
	"squire_captain": {"id": "squire_captain", "name": "Squire Captain", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["summon"], "desc": "Summon: 1/1 in adjacent lane."},
	"sellsword": {"id": "sellsword", "name": "Sellsword", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["wither"], "wither": 1, "desc": "Wither 1. Strong start, fades."},
	"torchbearer": {"id": "torchbearer", "name": "Torchbearer", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["adj_buff", "wither"], "wither": 1, "desc": "Adj +1 ATK. Wither 1.",
		"adj_buff": {"atk": 1, "hp": 0}},
	"gravedigger": {"id": "gravedigger", "name": "Gravedigger", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": [], "desc": "First friendly death each round: draw 1.",
		"passive": "draw_on_ally_death"},
	"bloodhound": {"id": "bloodhound", "name": "Bloodhound", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-enter: 1 to opposing creature, draw 1.",
		"on_enter": {"type": "damage_opposing_draw", "value": 1}},
	"scavenger": {"id": "scavenger", "name": "Scavenger", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["on_enter"], "desc": "On-enter: gain 5 gold.",
		"on_enter": {"type": "gain_gold", "value": 5}},
	"stone_wall": {"id": "stone_wall", "name": "Stone Wall", "type": "creature", "cost": 2, "atk": 0, "hp": 6,
		"rarity": "common", "keywords": [], "desc": "Cannot attack. Adj empty lanes -1 face dmg.",
		"passive": "cannot_attack_wall"},

	# ═══════════════════════════════════════════
	#  COMMON SPELLS (13)
	# ═══════════════════════════════════════════
	"slash": {"id": "slash", "name": "Slash", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 4 to target creature.",
		"spell": {"type": "damage", "value": 4}, "targeting": "any_creature"},
	"shield_wall": {"id": "shield_wall", "name": "Shield Wall", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Target creature +0/+3.",
		"spell": {"type": "buff_hp", "value": 3}, "targeting": "friendly_creature"},
	"war_cry": {"id": "war_cry", "name": "War Cry", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "All your creatures +1 ATK this turn.",
		"spell": {"type": "buff_all_atk", "value": 1, "permanent": false}, "targeting": "none"},
	"provision": {"id": "provision", "name": "Provision", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Draw 2 cards.",
		"spell": {"type": "draw", "value": 2}, "targeting": "none"},
	"patch_up": {"id": "patch_up", "name": "Patch Up", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Remove 3 damage from target creature.",
		"spell": {"type": "heal", "value": 3}, "targeting": "friendly_creature"},
	"flame_bolt": {"id": "flame_bolt", "name": "Flame Bolt", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 3 to enemy face.",
		"spell": {"type": "damage_face", "value": 3}, "targeting": "none"},
	"shove": {"id": "shove", "name": "Shove", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Move enemy creature to random lane. Deal 1.",
		"spell": {"type": "custom", "id": "shove"}, "targeting": "enemy_creature"},
	"gambit": {"id": "gambit", "name": "Gambit", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Discard up to 3, draw that many.",
		"spell": {"type": "custom", "id": "gambit"}, "targeting": "none"},
	"blood_tithe": {"id": "blood_tithe", "name": "Blood Tithe", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 2 to enemy face. Take 1 damage.",
		"spell": {"type": "custom", "id": "blood_tithe"}, "targeting": "none"},
	"reckless_charge": {"id": "reckless_charge", "name": "Reckless Charge", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Deal 3 to creature. Draw 1. Take 1 damage.",
		"spell": {"type": "custom", "id": "reckless_charge"}, "targeting": "any_creature"},
	"quick_shot": {"id": "quick_shot", "name": "Quick Shot", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Deal 1 to any target.",
		"spell": {"type": "damage", "value": 1}, "targeting": "any"},
	"scrap": {"id": "scrap", "name": "Scrap", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Discard 1 card. Gain 1 mana this turn.",
		"spell": {"type": "custom", "id": "scrap"}, "targeting": "none"},
	"barricade": {"id": "barricade", "name": "Barricade", "type": "spell", "cost": 1,
		"rarity": "common", "keywords": [], "desc": "Creature +0/+3, can't attack. Absorbs lane face damage.",
		"spell": {"type": "custom", "id": "barricade"}, "targeting": "friendly_creature"},

	# ═══════════════════════════════════════════
	#  UNCOMMON CREATURES (17)
	# ═══════════════════════════════════════════
	"battle_drummer": {"id": "battle_drummer", "name": "Battle Drummer", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["adj_buff"], "desc": "Adj +2 ATK.",
		"adj_buff": {"atk": 2, "hp": 0}},
	"witch": {"id": "witch", "name": "Witch", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "Floop: deal 3 to any creature.",
		"floop": {"type": "damage_any", "value": 3}},
	"duelist": {"id": "duelist", "name": "Duelist", "type": "creature", "cost": 2, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-enter: 2 to opposing creature. Takes +1 dmg.",
		"on_enter": {"type": "damage_opposing", "value": 2}, "extra_damage": 1},
	"griffin": {"id": "griffin", "name": "Griffin", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift", "on_death"], "desc": "Swift. On-death: return to hand (once).",
		"on_death": {"type": "return_to_hand_once"}},
	"bannerman": {"id": "bannerman", "name": "Bannerman", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": [], "desc": "All friendly creatures +1 ATK. Lost on death.",
		"passive": "global_atk_buff"},
	"berserker": {"id": "berserker", "name": "Berserker", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": [], "desc": "+1 ATK each round it attacks. Takes +1 dmg.",
		"passive": "grow_on_attack", "extra_damage": 1},
	"mule": {"id": "mule", "name": "Mule", "type": "creature", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-enter: draw 2 cards.",
		"on_enter": {"type": "draw", "value": 2}},
	"sentinel": {"id": "sentinel", "name": "Sentinel", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": ["armored", "thorns"], "desc": "Armored. Thorns."},
	"war_hound": {"id": "war_hound", "name": "War Hound", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["piercing"], "desc": "Piercing. Excess kill damage hits face."},
	"necromancer": {"id": "necromancer", "name": "Necromancer", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death", "floop"], "desc": "On-death: summon 2/2 here. Floop: kill adj, summon 2/2.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2},
		"floop": {"type": "kill_adjacent_summon", "atk": 2, "hp": 2}},
	"bloodsworn": {"id": "bloodsworn", "name": "Bloodsworn", "type": "creature", "cost": 2, "atk": 4, "hp": 4,
		"rarity": "uncommon", "keywords": ["sacrifice"], "desc": "Sacrifice: kill a friendly creature to play."},
	"blood_pyre": {"id": "blood_pyre", "name": "Blood Pyre", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death"], "desc": "On-death: +1 mana next turn.",
		"on_death": {"type": "bonus_mana", "value": 1}},
	"copycat": {"id": "copycat", "name": "Copycat", "type": "creature", "cost": 2, "atk": 0, "hp": 1,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-enter: copy any friendly creature.",
		"on_enter": {"type": "copy_friendly"}},
	"stray_cat": {"id": "stray_cat", "name": "Stray Cat", "type": "creature", "cost": 0, "atk": 1, "hp": 1,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-enter: look at top 3, pick 1.",
		"on_enter": {"type": "look_top", "value": 3}},
	"mirror_knight": {"id": "mirror_knight", "name": "Mirror Knight", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter"], "desc": "On-enter: copy opposing creature's keywords.",
		"on_enter": {"type": "copy_opposing_keywords"}},
	"vengeful_spirit": {"id": "vengeful_spirit", "name": "Vengeful Spirit", "type": "creature", "cost": 1, "atk": 0, "hp": 1,
		"rarity": "uncommon", "keywords": [], "desc": "+1 ATK per face damage taken this fight.",
		"passive": "atk_per_face_damage"},
	"iron_bastion": {"id": "iron_bastion", "name": "Iron Bastion", "type": "creature", "cost": 3, "atk": 1, "hp": 7,
		"rarity": "uncommon", "keywords": ["armored"], "desc": "Armored. All face damage to player -1 while alive.",
		"passive": "reduce_face_damage"},

	# ═══════════════════════════════════════════
	#  UNCOMMON SPELLS (12)
	# ═══════════════════════════════════════════
	"smite_spell": {"id": "smite_spell", "name": "Smite", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Deal 6 to target creature. Exhaust.",
		"spell": {"type": "damage", "value": 6}, "targeting": "any_creature"},
	"inspire": {"id": "inspire", "name": "Inspire", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "All creatures +2 ATK this turn. Exhaust.",
		"spell": {"type": "buff_all_atk", "value": 2, "permanent": false}, "targeting": "none"},
	"ambush": {"id": "ambush", "name": "Ambush", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 2 to all enemy creatures.",
		"spell": {"type": "damage_all_enemies", "value": 2}, "targeting": "none"},
	"second_wind": {"id": "second_wind", "name": "Second Wind", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Remove all damage from creature. +1 ATK permanent.",
		"spell": {"type": "custom", "id": "second_wind"}, "targeting": "friendly_creature"},
	"reposition": {"id": "reposition", "name": "Reposition", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Swap two creatures' lanes. Both +1 ATK this turn.",
		"spell": {"type": "custom", "id": "reposition"}, "targeting": "none"},
	"lightning": {"id": "lightning", "name": "Lightning", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 2 to creature and 2 face damage.",
		"spell": {"type": "custom", "id": "lightning"}, "targeting": "any_creature"},
	"offering": {"id": "offering", "name": "Offering", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Sacrifice a creature. Gain 2 mana. Exhaust.",
		"spell": {"type": "custom", "id": "offering"}, "targeting": "friendly_creature"},
	"grave_pact": {"id": "grave_pact", "name": "Grave Pact", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": ["retain"], "desc": "Next friendly death returns to hand. Retain.",
		"spell": {"type": "custom", "id": "grave_pact"}, "targeting": "none"},
	"fuel_the_pyre": {"id": "fuel_the_pyre", "name": "Fuel the Pyre", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Sacrifice a creature. Deal its ATK to any target.",
		"spell": {"type": "custom", "id": "fuel_the_pyre"}, "targeting": "friendly_creature"},
	"battle_hymn": {"id": "battle_hymn", "name": "Battle Hymn", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "All creatures +1 ATK permanently.",
		"spell": {"type": "buff_all_atk", "value": 1, "permanent": true}, "targeting": "none"},
	"pillage": {"id": "pillage", "name": "Pillage", "type": "spell", "cost": 1,
		"rarity": "uncommon", "keywords": [], "desc": "Deal 3 to creature. If it dies, gain 10 gold.",
		"spell": {"type": "custom", "id": "pillage"}, "targeting": "any_creature"},
	"echo_spell": {"id": "echo_spell", "name": "Echo", "type": "spell", "cost": 2,
		"rarity": "uncommon", "keywords": ["exhaust"], "desc": "Copy last spell this turn. Exhaust.",
		"spell": {"type": "custom", "id": "echo_spell"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  RARE CREATURES (14)
	# ═══════════════════════════════════════════
	"dragon_hatchling": {"id": "dragon_hatchling", "name": "Dragon Hatchling", "type": "creature", "cost": 3, "atk": 4, "hp": 5,
		"rarity": "rare", "keywords": ["on_enter", "wither"], "wither": 1, "desc": "On-enter: 2 to ALL enemies. Wither 1.",
		"on_enter": {"type": "damage_all_enemies", "value": 2}},
	"royal_guard": {"id": "royal_guard", "name": "Royal Guard", "type": "creature", "cost": 3, "atk": 2, "hp": 6,
		"rarity": "rare", "keywords": [], "desc": "Adj creatures take -1 dmg. Gains +1 ATK when hit.",
		"passive": "royal_guard"},
	"assassin": {"id": "assassin", "name": "Assassin", "type": "creature", "cost": 2, "atk": 5, "hp": 1,
		"rarity": "rare", "keywords": ["swift", "piercing"], "desc": "Swift. Piercing. Dies at end of your turn.",
		"passive": "dies_end_of_turn"},
	"hydra": {"id": "hydra", "name": "Hydra", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "rare", "keywords": [], "desc": "Attacks ALL enemy lanes. Takes 1 from each.",
		"passive": "attacks_all_lanes"},
	"summoner": {"id": "summoner", "name": "Summoner", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "rare", "keywords": ["summon", "floop"], "desc": "Summon. Floop: summon 1/1 random lane.",
		"floop": {"type": "summon_random", "atk": 1, "hp": 1}},
	"paladin": {"id": "paladin", "name": "Paladin", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["last_stand", "adj_buff"], "desc": "Last Stand. Adj +1 ATK.",
		"adj_buff": {"atk": 1, "hp": 0}},
	"corpse_eater": {"id": "corpse_eater", "name": "Corpse Eater", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": [], "desc": "+1 ATK whenever a friendly creature dies.",
		"passive": "grow_on_ally_death"},
	"ironclad_veteran": {"id": "ironclad_veteran", "name": "Ironclad Veteran", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["on_enter"], "desc": "+1 ATK per card played this turn before it.",
		"on_enter": {"type": "atk_per_cards_played"}},
	"kindling": {"id": "kindling", "name": "Kindling", "type": "creature", "cost": 0, "atk": 0, "hp": 1,
		"rarity": "rare", "keywords": [], "desc": "No abilities. Sacrifice fodder."},
	"doppelganger": {"id": "doppelganger", "name": "Doppelganger", "type": "creature", "cost": 3, "atk": 1, "hp": 1,
		"rarity": "rare", "keywords": ["on_enter"], "desc": "On-enter: copy last creature that died this fight.",
		"on_enter": {"type": "copy_last_dead"}},
	"vampire_lord": {"id": "vampire_lord", "name": "Vampire Lord", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["regenerate"], "desc": "Regenerate. On kill: heal 2 player HP, +1 ATK.",
		"passive": "vampire_lord"},
	"chaos_imp": {"id": "chaos_imp", "name": "Chaos Imp", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "rare", "keywords": ["on_enter"], "desc": "On-enter: cast random spell from deck free.",
		"on_enter": {"type": "cast_random_spell"}},
	"warden_of_graves": {"id": "warden_of_graves", "name": "Warden of Graves", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": [], "desc": "All your on-death effects trigger twice.",
		"passive": "double_on_death"},
	"siege_golem": {"id": "siege_golem", "name": "Siege Golem", "type": "creature", "cost": 3, "atk": 5, "hp": 6,
		"rarity": "rare", "keywords": [], "desc": "Only in empty opposing lane. Deals face dmg only.",
		"passive": "siege"},

	# ═══════════════════════════════════════════
	#  RARE SPELLS (10)
	# ═══════════════════════════════════════════
	"earthquake": {"id": "earthquake", "name": "Earthquake", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 3 to ALL creatures. Exhaust.",
		"spell": {"type": "damage_all", "value": 3}, "targeting": "none"},
	"kings_command": {"id": "kings_command", "name": "King's Command", "type": "spell", "cost": 2,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "All creatures +3 ATK this turn, +0/+1 perm. Exhaust.",
		"spell": {"type": "custom", "id": "kings_command"}, "targeting": "none"},
	"unholy_bargain": {"id": "unholy_bargain", "name": "Unholy Bargain", "type": "spell", "cost": 0,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Draw 3 cards. Take 3 face damage. Exhaust.",
		"spell": {"type": "custom", "id": "unholy_bargain"}, "targeting": "none"},
	"mass_grave": {"id": "mass_grave", "name": "Mass Grave", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Kill ALL friendly creatures. 3 face dmg each. Exhaust.",
		"spell": {"type": "custom", "id": "mass_grave"}, "targeting": "none"},
	"dark_pact": {"id": "dark_pact", "name": "Dark Pact", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": [], "desc": "All creatures +1 ATK permanent. Take 2 face damage.",
		"spell": {"type": "custom", "id": "dark_pact"}, "targeting": "none"},
	"war_chant": {"id": "war_chant", "name": "War Chant", "type": "spell", "cost": 0,
		"rarity": "rare", "keywords": [], "desc": "Discard 2 cards. Gain 1 mana this turn.",
		"spell": {"type": "custom", "id": "war_chant"}, "targeting": "none"},
	"grave_robbery": {"id": "grave_robbery", "name": "Grave Robbery", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Return last dead creature to hand. Exhaust.",
		"spell": {"type": "custom", "id": "grave_robbery"}, "targeting": "none"},
	"cataclysm": {"id": "cataclysm", "name": "Cataclysm", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal highest-ATK creature's ATK to ALL enemies. Exhaust.",
		"spell": {"type": "custom", "id": "cataclysm"}, "targeting": "none"},
	"soul_swap": {"id": "soul_swap", "name": "Soul Swap", "type": "spell", "cost": 1,
		"rarity": "rare", "keywords": [], "desc": "Swap target creature's ATK and HP.",
		"spell": {"type": "custom", "id": "soul_swap"}, "targeting": "any_creature"},
	"apocalypse": {"id": "apocalypse", "name": "Apocalypse", "type": "spell", "cost": 3,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Kill ALL creatures. 1 face dmg each. Exhaust.",
		"spell": {"type": "custom", "id": "apocalypse"}, "targeting": "none"},

	# Curse (added by events)
	"curse": {"id": "curse", "name": "Curse", "type": "spell", "cost": 0,
		"rarity": "starter", "keywords": [], "desc": "Does nothing. Wastes a draw.",
		"spell": {"type": "none"}, "targeting": "none"},
}


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
	"footman", "footman", "footman",
	"squire", "squire",
	"knight",
	"conscript",
	"strike", "fireball", "bolster", "mend", "rally",
]


static func get_card_data(id: String) -> Dictionary:
	if CARD_POOL.has(id):
		return CARD_POOL[id].duplicate(true)
	if ENEMY_POOL.has(id):
		return ENEMY_POOL[id].duplicate(true)
	push_warning("CardDB: unknown card id '%s'" % id)
	return {}


static func is_spell(id: String) -> bool:
	var data = get_card_data(id)
	return data.get("type", "") == "spell"


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


static func roll_card_reward(act: int, is_elite: bool = false, is_boss: bool = false) -> Array[String]:
	if is_boss:
		return _roll_from_rarity("rare", 3)
	var weights: Array
	match act:
		1: weights = [70, 25, 5]
		2: weights = [50, 35, 15]
		_: weights = [35, 35, 30]
	if is_elite:
		weights = [0, weights[0] + weights[1], weights[2]]
	var picked: Array[String] = []
	var attempts := 0
	while picked.size() < 3 and attempts < 50:
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
