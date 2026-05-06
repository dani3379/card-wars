extends Node
## RelicDB.gd — 36 relics from design doc.
## Categories: starting (8), combat (23), utility (5).
## hooks: game events this relic responds to. Combat.gd checks these.

const RELICS: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTING RELICS (pick 1 of 3 from pool of 8)
	# ═══════════════════════════════════════════
	"iron_buckler": {"id": "iron_buckler", "name": "Iron Buckler", "tier": "starting",
		"desc": "First creature you play each fight gets +2 HP.",
		"hooks": ["creature_played"], "effect": "first_creature_hp", "value": 2},
	"ember_crown": {"id": "ember_crown", "name": "Ember Crown", "tier": "starting",
		"desc": "Your first spell each turn costs 0.",
		"hooks": ["spell_played"], "effect": "first_spell_free", "value": 0},
	"couriers_bag": {"id": "couriers_bag", "name": "Courier's Bag", "tier": "starting",
		"desc": "Draw 6 on turn 1 of each fight instead of 5.",
		"hooks": ["turn_start"], "effect": "extra_draw_turn1", "value": 1},
	"coin_purse": {"id": "coin_purse", "name": "Coin Purse", "tier": "starting",
		"desc": "Gain 10 extra gold per fight.",
		"hooks": ["combat_end"], "effect": "bonus_gold", "value": 10},
	"worn_spellbook": {"id": "worn_spellbook", "name": "Worn Spellbook", "tier": "starting",
		"desc": "Your damage spells deal +1 damage.",
		"hooks": ["spell_damage"], "effect": "spell_damage_bonus", "value": 1},
	"scouts_emblem": {"id": "scouts_emblem", "name": "Scout's Emblem", "tier": "starting",
		"desc": "Card rewards show 4 choices instead of 3.",
		"hooks": [], "effect": "extra_reward_choice", "value": 1},
	"soul_lantern": {"id": "soul_lantern", "name": "Soul Lantern", "tier": "starting",
		"desc": "First friendly death each round: +1 mana next turn.",
		"hooks": ["creature_death"], "effect": "mana_on_death", "value": 1},
	"veterans_medal": {"id": "veterans_medal", "name": "Veteran's Medal", "tier": "starting",
		"desc": "Your 1-cost creatures have +1/+1.",
		"hooks": ["creature_played"], "effect": "buff_cheap_creatures", "value": 1},

	# ═══════════════════════════════════════════
	#  COMBAT RELICS (23) — from elites, bosses, events, shops
	# ═══════════════════════════════════════════
	"war_drum": {"id": "war_drum", "name": "War Drum", "tier": "combat",
		"desc": "On-enter damage effects deal +1.",
		"hooks": ["on_enter_damage"], "effect": "on_enter_bonus", "value": 1},
	"banner_of_unity": {"id": "banner_of_unity", "name": "Banner of Unity", "tier": "combat",
		"desc": "Adjacency buffs give +1 extra.",
		"hooks": [], "effect": "adj_buff_bonus", "value": 1},
	"swift_boots": {"id": "swift_boots", "name": "Swift Boots", "tier": "combat",
		"desc": "Swift creatures have +1 ATK.",
		"hooks": [], "effect": "swift_atk_bonus", "value": 1},
	"fortress_stone": {"id": "fortress_stone", "name": "Fortress Stone", "tier": "combat",
		"desc": "Armored creatures take 2 less instead of 1.",
		"hooks": [], "effect": "armored_bonus", "value": 1},
	"briar_amulet": {"id": "briar_amulet", "name": "Briar Amulet", "tier": "combat",
		"desc": "Thorns deals 2 instead of 1.",
		"hooks": [], "effect": "thorns_bonus", "value": 1},
	"echo_staff": {"id": "echo_staff", "name": "Echo Staff", "tier": "combat",
		"desc": "Floop abilities trigger twice.",
		"hooks": ["floop"], "effect": "double_floop", "value": 0},
	"piercing_crown": {"id": "piercing_crown", "name": "Piercing Crown", "tier": "combat",
		"desc": "Piercing overflow damage +1.",
		"hooks": [], "effect": "piercing_bonus", "value": 1},
	"conscription_relic": {"id": "conscription_relic", "name": "Conscription", "tier": "combat",
		"desc": "Token creatures from Summon have +1 HP.",
		"hooks": ["summon_token"], "effect": "token_hp_bonus", "value": 1},
	"bone_ring": {"id": "bone_ring", "name": "Bone Ring", "tier": "combat",
		"desc": "On-death effects deal +1 damage.",
		"hooks": ["on_death_damage"], "effect": "on_death_bonus", "value": 1},
	"pyromaniac_ring": {"id": "pyromaniac_ring", "name": "Pyromaniac's Ring", "tier": "combat",
		"desc": "Spells that deal face damage deal +1.",
		"hooks": ["spell_face_damage"], "effect": "face_spell_bonus", "value": 1},
	"war_horn": {"id": "war_horn", "name": "War Horn", "tier": "combat",
		"desc": "Spells that buff ATK give +1 extra.",
		"hooks": ["spell_buff"], "effect": "spell_atk_buff_bonus", "value": 1},
	"battle_scars": {"id": "battle_scars", "name": "Battle Scars", "tier": "combat",
		"desc": "+1 mana on turn 1 only of each fight.",
		"hooks": ["turn_start"], "effect": "bonus_mana_turn1", "value": 1},
	"glass_cannon": {"id": "glass_cannon", "name": "Glass Cannon", "tier": "combat",
		"desc": "Your creatures have +1 ATK but -1 HP.",
		"hooks": ["creature_played"], "effect": "glass_cannon", "value": 0},
	"stone_skin": {"id": "stone_skin", "name": "Stone Skin", "tier": "combat",
		"desc": "Your creatures have +1 HP but -1 ATK.",
		"hooks": ["creature_played"], "effect": "stone_skin", "value": 0},
	"thiefs_gloves": {"id": "thiefs_gloves", "name": "Thief's Gloves", "tier": "combat",
		"desc": "Win taking 0 face damage: gain 5 gold.",
		"hooks": ["combat_end"], "effect": "gold_no_damage", "value": 5},
	"butchers_cleaver": {"id": "butchers_cleaver", "name": "Butcher's Cleaver", "tier": "combat",
		"desc": "Sacrifice a creature: next creature this turn +2 ATK for 2 turns.",
		"hooks": ["sacrifice"], "effect": "sacrifice_buff", "value": 2},
	"vultures_feast": {"id": "vultures_feast", "name": "Vulture's Feast", "tier": "combat",
		"desc": "After fight, heal 1 HP per friendly death, max 5.",
		"hooks": ["combat_end"], "effect": "heal_per_death", "value": 1},
	"gamblers_coin": {"id": "gamblers_coin", "name": "Gambler's Coin", "tier": "combat",
		"desc": "Start of fight: draw 1 extra OR 3 to random enemy.",
		"hooks": ["combat_start"], "effect": "gamblers_coin", "value": 0},
	"bone_pile": {"id": "bone_pile", "name": "Bone Pile", "tier": "combat",
		"desc": "Sacrifice: deal creature's ATK to opposing creature.",
		"hooks": ["sacrifice"], "effect": "sacrifice_damage", "value": 0},
	"resonance_crystal": {"id": "resonance_crystal", "name": "Resonance Crystal", "tier": "combat",
		"desc": "First keyword creature death: all allies gain that keyword.",
		"hooks": ["creature_death"], "effect": "resonance_crystal", "value": 0},
	"mimic_ring": {"id": "mimic_ring", "name": "Mimic Ring", "tier": "combat",
		"desc": "Played creature copies 1 keyword from adjacent ally.",
		"hooks": ["creature_played"], "effect": "mimic_ring", "value": 0},
	"scroll_of_greed": {"id": "scroll_of_greed", "name": "Scroll of Greed", "tier": "combat",
		"desc": "Non-normal draw: gain 1 gold per card.",
		"hooks": ["bonus_draw"], "effect": "gold_per_draw", "value": 1},
	"bloodstone_relic": {"id": "bloodstone_relic", "name": "Bloodstone", "tier": "combat",
		"desc": "When you take face damage, creatures +1 ATK this turn.",
		"hooks": ["hero_damaged"], "effect": "bloodstone_buff", "value": 1},

	# ═══════════════════════════════════════════
	#  UTILITY RELICS (5)
	# ═══════════════════════════════════════════
	"merchants_license": {"id": "merchants_license", "name": "Merchant's License", "tier": "utility",
		"desc": "Shop prices reduced by 25%.",
		"hooks": [], "effect": "shop_discount", "value": 25},
	"collectors_tome": {"id": "collectors_tome", "name": "Collector's Tome", "tier": "utility",
		"desc": "Pick 2 cards from reward instead of 1.",
		"hooks": [], "effect": "double_reward_pick", "value": 0},
	"blacksmiths_hammer": {"id": "blacksmiths_hammer", "name": "Blacksmith's Hammer", "tier": "utility",
		"desc": "Sharpen/Fortify give +3 instead of +2. Imbue offers 3 choices.",
		"hooks": [], "effect": "upgrade_bonus", "value": 0},
	"map_fragment": {"id": "map_fragment", "name": "Map Fragment", "tier": "utility",
		"desc": "See 2 extra nodes ahead on the map.",
		"hooks": [], "effect": "map_vision", "value": 2},
	"scavengers_pouch": {"id": "scavengers_pouch", "name": "Scavenger's Pouch", "tier": "utility",
		"desc": "Gain 20 gold when you remove a card.",
		"hooks": ["card_removed"], "effect": "gold_on_remove", "value": 20},
}


static func get_relic(id: String) -> Dictionary:
	if RELICS.has(id):
		return RELICS[id].duplicate(true)
	push_warning("RelicDB: unknown relic id '%s'" % id)
	return {}


static func get_relics_by_tier(tier: String) -> Array[String]:
	var result: Array[String] = []
	for id in RELICS.keys():
		if RELICS[id].tier == tier:
			result.append(id)
	return result


static func roll_starting_relics() -> Array[String]:
	var pool = get_relics_by_tier("starting")
	pool.shuffle()
	return pool.slice(0, 3)


static func roll_relic_reward(tier: String = "combat", exclude: Array[String] = []) -> Array[String]:
	var pool: Array[String] = []
	for id in get_relics_by_tier(tier):
		if not exclude.has(id):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))
