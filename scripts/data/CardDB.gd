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
	"goblin": {"id": "goblin", "name": "Goblin", "type": "creature", "cost": 1, "atk": 1, "hp": 1,
		"rarity": "starter", "keywords": [], "desc": ""},
	"orc": {"id": "orc", "name": "Orc", "type": "creature", "cost": 2, "atk": 2, "hp": 2,
		"rarity": "starter", "keywords": [], "desc": ""},
	"troll": {"id": "troll", "name": "Troll", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "starter", "keywords": ["floop"], "desc": "Floop: heal self 2.",
		"floop": {"type": "heal_self", "value": 2}},
	"sprite": {"id": "sprite", "name": "Sprite", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "starter", "keywords": ["floop"], "desc": "Floop: adjacent creatures +1 ATK this turn.",
		"floop": {"type": "buff_adjacent_atk", "value": 1}},
	"naga": {"id": "naga", "name": "Naga", "type": "creature", "cost": 3, "atk": 3, "hp": 4,
		"rarity": "starter", "keywords": ["floop"], "desc": "Floop: deal 2 to opposing creature.",
		"floop": {"type": "damage_opposing", "value": 2}},
	"ratling": {"id": "ratling", "name": "Ratling", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "starter", "keywords": ["wither", "floop"], "wither": 1, "desc": "Wither 1. Floop: +1 ATK permanent.",
		"floop": {"type": "grow_atk", "value": 1}},
	"strike": {"id": "strike", "name": "Strike", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 3 to target creature.",
		"spell": {"type": "damage", "value": 3}, "targeting": "any_creature"},
	"fireball": {"id": "fireball", "name": "Fireball", "type": "spell", "cost": 1,
		"rarity": "starter", "keywords": [], "desc": "Deal 2 to enemy face.",
		"spell": {"type": "damage_face", "value": 2}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  COMMON CREATURES (17) — All have Floop
	# ═══════════════════════════════════════════
	"ranger": {"id": "ranger", "name": "Ranger", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "common", "keywords": ["floop"], "desc": "Floop: deal 1 to opposing, heal self 1.",
		"floop": {"type": "damage_opposing_heal", "value": 1, "heal": 1}},
	"hound": {"id": "hound", "name": "Hound", "type": "creature", "cost": 1, "atk": 3, "hp": 2,
		"rarity": "common", "keywords": ["floop"], "desc": "Floop: deal 2 to random enemy creature.",
		"floop": {"type": "damage_any", "value": 2}},
	"shieldbearer": {"id": "shieldbearer", "name": "Shieldbearer", "type": "creature", "cost": 2, "atk": 1, "hp": 5,
		"rarity": "common", "keywords": ["armored", "floop"], "desc": "Armored. Floop: adj friendlies -1 dmg this round.",
		"floop": {"type": "shield_adjacent", "value": 1}},
	"pikeman": {"id": "pikeman", "name": "Pikeman", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: 1 to opposing. Floop: 1 to opposing + adj enemy lanes.",
		"on_enter": {"type": "damage_opposing", "value": 1},
		"floop": {"type": "damage_opposing_splash", "value": 1}},
	"lookout": {"id": "lookout", "name": "Lookout", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: draw 1. Floop: scry (top card, keep or bottom).",
		"on_enter": {"type": "draw", "value": 1},
		"floop": {"type": "scry", "value": 1}},
	"militia": {"id": "militia", "name": "Militia", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["retain", "floop"], "desc": "Retain. Floop: gain Armored until next round.",
		"floop": {"type": "temp_armored", "value": 1}},
	"wolf_c": {"id": "wolf_c", "name": "Wolf", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["on_death", "floop"], "desc": "On-death: 2 to opposing. Floop: 1 to ALL enemy creatures.",
		"on_death": {"type": "damage_opposing_lane", "value": 2},
		"floop": {"type": "damage_all_enemies", "value": 1}},
	"harpy": {"id": "harpy", "name": "Harpy", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["swift", "floop"], "desc": "Swift. Floop: move to any empty friendly lane.",
		"floop": {"type": "relocate"}},
	"thornguard": {"id": "thornguard", "name": "Thornguard", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "common", "keywords": ["thorns", "on_death", "floop"], "desc": "Thorns. On-death: 1 to ALL enemies. Floop: +2 Thorns this round.",
		"on_death": {"type": "damage_all_enemies", "value": 1},
		"floop": {"type": "buff_thorns", "value": 2}},
	"raven": {"id": "raven", "name": "Raven", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["ranged", "floop"], "desc": "Ranged. Floop: look at top 3 cards, reorder.",
		"floop": {"type": "reorder_deck", "value": 3}},
	"squire_captain": {"id": "squire_captain", "name": "Squire Captain", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "common", "keywords": ["summon", "floop"], "desc": "Summon. Floop: all tokens +1 ATK this turn.",
		"floop": {"type": "buff_tokens_atk", "value": 1}},
	"sellsword": {"id": "sellsword", "name": "Sellsword", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "common", "keywords": ["wither", "floop"], "wither": 1, "desc": "Wither 1. Floop: gain 3 gold.",
		"floop": {"type": "gain_gold", "value": 3}},
	"torchbearer": {"id": "torchbearer", "name": "Torchbearer", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["adj_buff", "wither", "floop"], "wither": 1, "desc": "Adj +1 ATK. Wither 1. Floop: adj friendlies gain Thorns 1 this round.",
		"adj_buff": {"atk": 1, "hp": 0},
		"floop": {"type": "grant_thorns_adjacent", "value": 1}},
	"gravedigger": {"id": "gravedigger", "name": "Gravedigger", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "common", "keywords": ["floop"], "desc": "Passive: draw on ally death. Floop: return random creature from discard to hand.",
		"passive": "draw_on_ally_death",
		"floop": {"type": "raise_dead"}},
	"bloodhound": {"id": "bloodhound", "name": "Bloodhound", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: 1 to opposing + draw 1. Floop: deal 1 to opposing, draw 1 if kill.",
		"on_enter": {"type": "damage_opposing_draw", "value": 1},
		"floop": {"type": "slay_draw", "value": 1}},
	"scavenger": {"id": "scavenger", "name": "Scavenger", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"rarity": "common", "keywords": ["on_enter", "floop"], "desc": "On-enter: gain 5 gold. Floop: gain 2 gold.",
		"on_enter": {"type": "gain_gold", "value": 5},
		"floop": {"type": "gain_gold", "value": 2}},
	"stone_wall": {"id": "stone_wall", "name": "Stone Wall", "type": "creature", "cost": 2, "atk": 0, "hp": 6,
		"rarity": "common", "keywords": ["floop"], "desc": "Can't attack. Adj empty -1 face dmg. Floop: adj friendlies heal 1.",
		"passive": "cannot_attack_wall",
		"floop": {"type": "heal_adjacent", "value": 1}},
	"mana_sprite": {"id": "mana_sprite", "name": "Mana Sprite", "type": "creature", "cost": 1, "atk": 0, "hp": 2,
		"rarity": "common", "keywords": ["floop"], "desc": "Floop: gain 1 mana this turn.",
		"floop": {"type": "gain_mana", "value": 1}},

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
	"adrenaline": {"id": "adrenaline", "name": "Adrenaline", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": ["exhaust"], "desc": "Gain 1 mana. Draw 2 cards. Exhaust.",
		"spell": {"type": "custom", "id": "adrenaline"}, "targeting": "none"},
	"concentrate": {"id": "concentrate", "name": "Concentrate", "type": "spell", "cost": 0,
		"rarity": "common", "keywords": [], "desc": "Discard 2 cards. Gain 2 mana.",
		"spell": {"type": "custom", "id": "concentrate"}, "targeting": "none"},

	# ═══════════════════════════════════════════
	#  UNCOMMON CREATURES (17) — All have Floop
	# ═══════════════════════════════════════════
	"battle_drummer": {"id": "battle_drummer", "name": "Battle Drummer", "type": "creature", "cost": 2, "atk": 1, "hp": 4,
		"rarity": "uncommon", "keywords": ["adj_buff", "floop"], "desc": "Adj +2 ATK. Floop: all friendlies +1 ATK permanently.",
		"adj_buff": {"atk": 2, "hp": 0},
		"floop": {"type": "buff_all_atk_permanent", "value": 1}},
	"witch": {"id": "witch", "name": "Witch", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "Floop: deal 3 to any creature.",
		"floop": {"type": "damage_any", "value": 3}},
	"duelist": {"id": "duelist", "name": "Duelist", "type": "creature", "cost": 2, "atk": 3, "hp": 4,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: 2 to opposing. +1 dmg taken. Floop: deal 2 to opposing, heal 2 if kill.",
		"on_enter": {"type": "damage_opposing", "value": 2}, "extra_damage": 1,
		"floop": {"type": "drain", "value": 2}},
	"griffin": {"id": "griffin", "name": "Griffin", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["swift", "on_death", "floop"], "desc": "Swift. On-death: return to hand (once). Floop: attack any lane this round.",
		"on_death": {"type": "return_to_hand_once"},
		"floop": {"type": "challenge"}},
	"bannerman": {"id": "bannerman", "name": "Bannerman", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "All friendly +1 ATK (lost on death). Floop: target friendly +2 HP permanent.",
		"passive": "global_atk_buff",
		"floop": {"type": "buff_target_hp", "value": 2}},
	"berserker": {"id": "berserker", "name": "Berserker", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "+1 ATK/round attacking. +1 dmg taken. Floop: deal 2 to opposing, take 1 self-dmg.",
		"passive": "grow_on_attack", "extra_damage": 1,
		"floop": {"type": "damage_self_opposing", "value": 2, "self_damage": 1}},
	"mule": {"id": "mule", "name": "Mule", "type": "creature", "cost": 1, "atk": 0, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: draw 2. Floop: discard 1, draw 1.",
		"on_enter": {"type": "draw", "value": 2},
		"floop": {"type": "filter_draw"}},
	"sentinel": {"id": "sentinel", "name": "Sentinel", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "uncommon", "keywords": ["armored", "thorns", "floop"], "desc": "Armored. Thorns. Floop: opposing creature can't attack this round.",
		"floop": {"type": "stun_opposing"}},
	"war_hound": {"id": "war_hound", "name": "War Hound", "type": "creature", "cost": 2, "atk": 3, "hp": 3,
		"rarity": "uncommon", "keywords": ["piercing", "floop"], "desc": "Piercing. Floop: deal 1 to enemy face.",
		"floop": {"type": "damage_face", "value": 1}},
	"necromancer": {"id": "necromancer", "name": "Necromancer", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death", "floop"], "desc": "On-death: summon 2/2. Floop: kill adj, summon 2/2.",
		"on_death": {"type": "summon", "atk": 2, "hp": 2},
		"floop": {"type": "kill_adjacent_summon", "atk": 2, "hp": 2}},
	"bloodsworn": {"id": "bloodsworn", "name": "Bloodsworn", "type": "creature", "cost": 2, "atk": 4, "hp": 4,
		"rarity": "uncommon", "keywords": ["sacrifice", "floop"], "desc": "Sacrifice to play. Floop: deal 2 to opposing, lose 1 HP.",
		"floop": {"type": "damage_self_opposing", "value": 2, "self_damage": 1}},
	"blood_pyre": {"id": "blood_pyre", "name": "Blood Pyre", "type": "creature", "cost": 1, "atk": 1, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_death", "floop"], "desc": "On-death: +1 mana next turn. Floop: sacrifice self, adj +2 ATK permanent.",
		"on_death": {"type": "bonus_mana", "value": 1},
		"floop": {"type": "blood_sacrifice", "value": 2}},
	"copycat": {"id": "copycat", "name": "Copycat", "type": "creature", "cost": 2, "atk": 0, "hp": 1,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: copy friendly. Floop: use opposing creature's floop instead.",
		"on_enter": {"type": "copy_friendly"},
		"floop": {"type": "copy_opposing_floop"}},
	"stray_cat": {"id": "stray_cat", "name": "Stray Cat", "type": "creature", "cost": 0, "atk": 1, "hp": 1,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: look at top 3, pick 1. Floop: add 1/1 token to hand.",
		"on_enter": {"type": "look_top", "value": 3},
		"floop": {"type": "spawn_token_hand", "atk": 1, "hp": 1}},
	"mirror_knight": {"id": "mirror_knight", "name": "Mirror Knight", "type": "creature", "cost": 2, "atk": 2, "hp": 3,
		"rarity": "uncommon", "keywords": ["on_enter", "floop"], "desc": "On-enter: copy opposing keywords. Floop: swap ATK with opposing until end of round.",
		"on_enter": {"type": "copy_opposing_keywords"},
		"floop": {"type": "swap_atk"}},
	"vengeful_spirit": {"id": "vengeful_spirit", "name": "Vengeful Spirit", "type": "creature", "cost": 1, "atk": 0, "hp": 1,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "+1 ATK per face dmg taken. Floop: deal this creature's ATK to opposing.",
		"passive": "atk_per_face_damage",
		"floop": {"type": "unleash_atk"}},
	"iron_bastion": {"id": "iron_bastion", "name": "Iron Bastion", "type": "creature", "cost": 3, "atk": 1, "hp": 7,
		"rarity": "uncommon", "keywords": ["armored", "floop"], "desc": "Armored. Face dmg -1. Floop: all friendlies gain Armored this round.",
		"passive": "reduce_face_damage",
		"floop": {"type": "grant_armored_all"}},
	"leyline_conduit": {"id": "leyline_conduit", "name": "Leyline Conduit", "type": "creature", "cost": 2, "atk": 0, "hp": 3,
		"rarity": "uncommon", "keywords": ["floop"], "desc": "Passive: +1 mana at start of each turn. Floop: gain 2 mana this turn.",
		"passive": "mana_per_turn",
		"floop": {"type": "gain_mana", "value": 2}},

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
	"bloodletting": {"id": "bloodletting", "name": "Bloodletting", "type": "spell", "cost": 0,
		"rarity": "uncommon", "keywords": [], "desc": "Lose 2 HP. Gain 2 mana.",
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
	"dragon_hatchling": {"id": "dragon_hatchling", "name": "Dragon Hatchling", "type": "creature", "cost": 3, "atk": 4, "hp": 5,
		"rarity": "rare", "keywords": ["on_enter", "wither", "floop"], "wither": 1, "desc": "On-enter: 2 to ALL enemies. Wither 1. Floop: 1 to ALL creatures (both sides).",
		"on_enter": {"type": "damage_all_enemies", "value": 2},
		"floop": {"type": "damage_all", "value": 1}},
	"royal_guard": {"id": "royal_guard", "name": "Royal Guard", "type": "creature", "cost": 3, "atk": 2, "hp": 6,
		"rarity": "rare", "keywords": ["floop"], "desc": "Adj -1 dmg. +1 ATK when hit. Floop: redirect adj attacks to this creature.",
		"passive": "royal_guard",
		"floop": {"type": "redirect_adjacent"}},
	"assassin": {"id": "assassin", "name": "Assassin", "type": "creature", "cost": 2, "atk": 5, "hp": 1,
		"rarity": "rare", "keywords": ["swift", "piercing", "floop"], "desc": "Swift. Piercing. Dies end of turn. Floop: destroy opposing with HP <= 2.",
		"passive": "dies_end_of_turn",
		"floop": {"type": "execute", "value": 2}},
	"hydra": {"id": "hydra", "name": "Hydra", "type": "creature", "cost": 3, "atk": 2, "hp": 5,
		"rarity": "rare", "keywords": ["floop"], "desc": "Attacks ALL lanes. Floop: +1 ATK per enemy creature on board.",
		"passive": "attacks_all_lanes",
		"floop": {"type": "grow_per_enemies"}},
	"summoner": {"id": "summoner", "name": "Summoner", "type": "creature", "cost": 2, "atk": 1, "hp": 3,
		"rarity": "rare", "keywords": ["summon", "floop"], "desc": "Summon. Floop: summon 1/1 random lane.",
		"floop": {"type": "summon_random", "atk": 1, "hp": 1}},
	"paladin": {"id": "paladin", "name": "Paladin", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["last_stand", "adj_buff", "floop"], "desc": "Last Stand. Adj +1 ATK. Floop: heal all friendlies 2.",
		"adj_buff": {"atk": 1, "hp": 0},
		"floop": {"type": "heal_all_friendly", "value": 2}},
	"corpse_eater": {"id": "corpse_eater", "name": "Corpse Eater", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": ["floop"], "desc": "+1 ATK on ally death. Floop: destroy adj friendly, gain its ATK and HP.",
		"passive": "grow_on_ally_death",
		"floop": {"type": "devour_adjacent"}},
	"ironclad_veteran": {"id": "ironclad_veteran", "name": "Ironclad Veteran", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["on_enter", "floop"], "desc": "On-enter: +1 ATK/card played. Floop: next card this turn costs 1 less.",
		"on_enter": {"type": "atk_per_cards_played"},
		"floop": {"type": "discount_next", "value": 1}},
	"kindling": {"id": "kindling", "name": "Kindling", "type": "creature", "cost": 0, "atk": 0, "hp": 1,
		"rarity": "rare", "keywords": ["floop"], "desc": "Floop: deal 1 to opposing creature.",
		"floop": {"type": "damage_opposing", "value": 1}},
	"doppelganger": {"id": "doppelganger", "name": "Doppelganger", "type": "creature", "cost": 3, "atk": 1, "hp": 1,
		"rarity": "rare", "keywords": ["on_enter", "floop"], "desc": "On-enter: copy last dead. Floop: become copy of opposing until end of round.",
		"on_enter": {"type": "copy_last_dead"},
		"floop": {"type": "become_copy"}},
	"vampire_lord": {"id": "vampire_lord", "name": "Vampire Lord", "type": "creature", "cost": 3, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["regenerate", "floop"], "desc": "Regenerate. On kill: heal 2 + ATK. Floop: drain 2 (deal 2, heal self 2).",
		"passive": "vampire_lord",
		"floop": {"type": "drain", "value": 2}},
	"chaos_imp": {"id": "chaos_imp", "name": "Chaos Imp", "type": "creature", "cost": 1, "atk": 2, "hp": 2,
		"rarity": "rare", "keywords": ["on_enter", "floop"], "desc": "On-enter: random spell free. Floop: mill top card, deal its cost to random enemy.",
		"on_enter": {"type": "cast_random_spell"},
		"floop": {"type": "discard_top_damage"}},
	"warden_of_graves": {"id": "warden_of_graves", "name": "Warden of Graves", "type": "creature", "cost": 2, "atk": 2, "hp": 4,
		"rarity": "rare", "keywords": ["floop"], "desc": "Double on-death. Floop: 1 dmg per creature in discard pile to opposing.",
		"passive": "double_on_death",
		"floop": {"type": "graveyard_damage"}},
	"siege_golem": {"id": "siege_golem", "name": "Siege Golem", "type": "creature", "cost": 3, "atk": 5, "hp": 6,
		"rarity": "rare", "keywords": ["floop"], "desc": "Empty opposing only. Face dmg only. Floop: deal 3 to opposing creature.",
		"passive": "siege",
		"floop": {"type": "damage_opposing", "value": 3}},

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

	# ═══════════════════════════════════════════
	#  4-COST POWERHOUSES (require mana banking)
	# ═══════════════════════════════════════════
	"war_titan": {"id": "war_titan", "name": "War Titan", "type": "creature", "cost": 4, "atk": 6, "hp": 8,
		"rarity": "rare", "keywords": ["armored", "floop"], "desc": "Armored. Floop: deal 2 to ALL enemy creatures.",
		"floop": {"type": "damage_all_enemies", "value": 2}},
	"archmage": {"id": "archmage", "name": "Archmage", "type": "creature", "cost": 4, "atk": 3, "hp": 5,
		"rarity": "rare", "keywords": ["floop"], "desc": "On enter: draw 2. Floop: deal 3 to any enemy creature.",
		"on_enter": {"type": "draw", "value": 2},
		"floop": {"type": "damage_opposing", "value": 3}},
	"doom_knight": {"id": "doom_knight", "name": "Doom Knight", "type": "creature", "cost": 4, "atk": 5, "hp": 6,
		"rarity": "rare", "keywords": ["piercing", "swift", "floop"], "desc": "Swift. Piercing. Floop: +2 ATK this turn.",
		"floop": {"type": "self_buff_atk", "value": 2}},
	"inferno": {"id": "inferno", "name": "Inferno", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "Deal 4 to ALL enemy creatures and 4 to enemy face. Exhaust.",
		"spell": {"type": "custom", "id": "inferno"}, "targeting": "none"},
	"overwhelming_force": {"id": "overwhelming_force", "name": "Overwhelming Force", "type": "spell", "cost": 4,
		"rarity": "rare", "keywords": ["exhaust"], "desc": "All friendly creatures +3 ATK permanently. Exhaust.",
		"spell": {"type": "custom", "id": "overwhelming_force"}, "targeting": "none"},

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
	"goblin", "goblin", "goblin", "goblin",
	"orc", "orc", "orc", "orc",
	"sprite",
	"troll",
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
