extends Node
## RelicDB.gd — relic catalog.
## Tiers: starting (9), combat (~85, includes 4 class-restricted), utility (8), boss (21).
## Total 130 relics after the 3-round design pass + Wave 2 keyword/build relics
## (StS + Hades + Monster Train + Balatro + Wildfrost + Cobalt Core + Inscryption + Backpack Hero + AtO imports).
## hooks: game events this relic responds to. Combat.gd checks these.
##
## Optional schema fields:
##   restricted_to: "<hero_id>"  — only offered to that hero (raider/stalwart/acolyte/pyromancer).
##   mana_cap_cost: int          — counts toward non-boss mana ceiling (+2 max). Boss-tier mana relics bypass.
##   downside: "<id>"            — pairs with boss "+1 max mana" trade.

const RELICS: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTING RELICS (pick 1 of 3 from pool of 8)
	# ═══════════════════════════════════════════
	"iron_buckler": {"id": "iron_buckler", "name": "Iron Buckler", "tier": "starting",
		"desc": "The first creature you play each fight gains Last Stand.",
		"hooks": ["creature_played"], "effect": "first_creature_last_stand", "value": 0},
	"ember_crown": {"id": "ember_crown", "name": "Ember Crown", "tier": "starting",
		"desc": "Your first spell each turn costs 0.",
		"hooks": ["spell_played"], "effect": "first_spell_free", "value": 0},
	"couriers_bag": {"id": "couriers_bag", "name": "Courier's Bag", "tier": "starting",
		"desc": "On turn 1 of each fight, draw 1 extra card.",
		"hooks": ["turn_start"], "effect": "extra_draw_turn1", "value": 1},
	"coin_purse": {"id": "coin_purse", "name": "Coin Purse", "tier": "starting",
		"desc": "Gain 10 extra gold per fight.",
		"hooks": ["combat_end"], "effect": "bonus_gold", "value": 10},
	"worn_spellbook": {"id": "worn_spellbook", "name": "Worn Spellbook", "tier": "starting",
		"desc": "Your damage spells deal +1 damage.",
		"hooks": ["spell_damage"], "effect": "spell_damage_bonus", "value": 1},
	"scouts_emblem": {"id": "scouts_emblem", "name": "Scout's Emblem", "tier": "starting",
		"desc": "Recruit camps show 4 choices instead of 3.",
		"hooks": [], "effect": "extra_reward_choice", "value": 1},
	"soul_lantern": {"id": "soul_lantern", "name": "Soul Lantern", "tier": "starting",
		"desc": "When the first friendly dies each round: gain 1 Command next turn.",
		"hooks": ["creature_death"], "effect": "mana_on_death", "value": 1},
	"veterans_medal": {"id": "veterans_medal", "name": "Veteran's Medal", "tier": "starting",
		"desc": "Your 1-cost creatures have +1/+1.",
		"hooks": ["creature_played"], "effect": "buff_cheap_creatures", "value": 1},
	"ember_censer": {"id": "ember_censer", "name": "Ember Censer", "tier": "starting",
		"desc": "When one of your Doom creatures detonates: it deals +1 damage.",
		"hooks": ["doom_detonate"], "effect": "doom_detonate_bonus", "value": 1},

	# ═══════════════════════════════════════════
	#  COMBAT RELICS (23) — from elites, bosses, events, shops
	# ═══════════════════════════════════════════
	"vanguards_cry": {"id": "vanguards_cry", "name": "Vanguard's Cry", "tier": "combat",
		"desc": "Your On-Enter damage effects deal +1 damage.",
		"hooks": ["on_enter_damage"], "effect": "on_enter_bonus", "value": 1},
	"banner_of_unity": {"id": "banner_of_unity", "name": "Banner of Unity", "tier": "combat",
		"desc": "Your Adj. Buff effects grant +1 extra ATK.",
		"hooks": [], "effect": "adj_buff_bonus", "value": 1},
	"swift_boots": {"id": "swift_boots", "name": "Swift Boots", "tier": "combat",
		"desc": "Swift creatures have +1 ATK.",
		"hooks": [], "effect": "swift_atk_bonus", "value": 1},
	"fortress_stone": {"id": "fortress_stone", "name": "Fortress Stone", "tier": "combat",
		"desc": "Your Armored creatures take 2 less damage instead of 1.",
		"hooks": [], "effect": "armored_bonus", "value": 1},
	"briar_amulet": {"id": "briar_amulet", "name": "Briar Amulet", "tier": "combat",
		"desc": "Your Thorns deals 2 damage instead of 1.",
		"hooks": [], "effect": "thorns_bonus", "value": 1},
	"echo_staff": {"id": "echo_staff", "name": "Echo Staff", "tier": "combat",
		"desc": "Your On-Enter effects trigger twice.",
		"hooks": ["creature_played"], "effect": "double_floop", "value": 0},
	"piercing_crown": {"id": "piercing_crown", "name": "Piercing Crown", "tier": "combat",
		"desc": "Your Piercing overflow damage deals +1 extra damage.",
		"hooks": [], "effect": "piercing_bonus", "value": 1},
	"conscription_relic": {"id": "conscription_relic", "name": "Conscription", "tier": "combat",
		"desc": "Your Summon tokens enter with +1 HP.",
		"hooks": ["summon_token"], "effect": "token_hp_bonus", "value": 1},
	"bone_ring": {"id": "bone_ring", "name": "Bone Ring", "tier": "combat",
		"desc": "Your On-Death damage effects deal +1 damage.",
		"hooks": ["on_death_damage"], "effect": "on_death_bonus", "value": 1},
	"pyromaniac_ring": {"id": "pyromaniac_ring", "name": "Pyromaniac's Ring", "tier": "combat",
		"desc": "Your face-damage spells deal +1 extra damage.",
		"hooks": ["spell_face_damage"], "effect": "face_spell_bonus", "value": 1},
	"war_horn": {"id": "war_horn", "name": "War Horn", "tier": "combat",
		"desc": "Your ATK-buff spells grant +1 extra ATK.",
		"hooks": ["spell_buff"], "effect": "spell_atk_buff_bonus", "value": 1},
	"battle_scars": {"id": "battle_scars", "name": "Battle Scars", "tier": "combat",
		"desc": "The first time you take face damage each fight: gain 2 Command this turn.",
		"hooks": ["hero_damaged"], "effect": "battle_scars_mana", "value": 2},
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
		"desc": "When you sacrifice a creature: the next creature you play this turn gets +2 ATK for 2 rounds.",
		"hooks": ["sacrifice"], "effect": "sacrifice_buff", "value": 2},
	"vultures_feast": {"id": "vultures_feast", "name": "Vulture's Feast", "tier": "combat",
		"desc": "After each fight: heal 1 HP per friendly death (max 5).",
		"hooks": ["combat_end"], "effect": "heal_per_death", "value": 1},
	"gamblers_coin": {"id": "gamblers_coin", "name": "Gambler's Coin", "tier": "combat",
		"desc": "Start of fight: flip a coin. Heads: draw 1 extra card. Tails: deal 3 damage to a random enemy.",
		"hooks": ["combat_start"], "effect": "gamblers_coin", "value": 0},
	"bone_pile": {"id": "bone_pile", "name": "Bone Pile", "tier": "combat",
		"desc": "When you sacrifice a creature: deal damage equal to its ATK to the opposing creature.",
		"hooks": ["sacrifice"], "effect": "sacrifice_damage", "value": 0},
	"resonance_crystal": {"id": "resonance_crystal", "name": "Resonance Crystal", "tier": "combat",
		"desc": "The first time a friendly with a keyword dies each fight: all your other creatures gain that keyword.",
		"hooks": ["creature_death"], "effect": "resonance_crystal", "value": 0},
	"mimic_ring": {"id": "mimic_ring", "name": "Mimic Ring", "tier": "combat",
		"desc": "When you play a creature: it copies 1 keyword from an adjacent friendly creature.",
		"hooks": ["creature_played"], "effect": "mimic_ring", "value": 0},
	"scroll_of_greed": {"id": "scroll_of_greed", "name": "Scroll of Greed", "tier": "combat",
		"desc": "Each card drawn beyond your normal turn draw: gain 1 gold.",
		"hooks": ["bonus_draw"], "effect": "gold_per_draw", "value": 1},
	"bloodstone_relic": {"id": "bloodstone_relic", "name": "Bloodstone", "tier": "combat",
		"desc": "When you take face damage: your creatures get +1 ATK this round.",
		"hooks": ["hero_damaged"], "effect": "bloodstone_buff", "value": 1},
	"phoenix_heart": {"id": "phoenix_heart", "name": "Phoenix Heart", "tier": "combat",
		"desc": "Once per run: when you would die, revive at 1 HP instead.",
		"hooks": ["hero_damaged"], "effect": "phoenix_revive", "value": 1},

	# ═══════════════════════════════════════════
	#  4x4 RELICS — designed around the front/back row redesign
	# ═══════════════════════════════════════════
	"vanguard_banner": {"id": "vanguard_banner", "name": "Vanguard Banner", "tier": "combat",
		"desc": "Your front-row creatures have +1 ATK.",
		"hooks": [], "effect": "front_row_atk", "value": 1},
	"rear_guard_charm": {"id": "rear_guard_charm", "name": "Rear Guard Charm", "tier": "combat",
		"desc": "When a front-row friendly dies: the back-row creature in its column gets +1/+1 this fight.",
		"hooks": ["creature_death"], "effect": "rear_guard_inherit", "value": 1},
	"phantom_veil": {"id": "phantom_veil", "name": "Phantom Veil", "tier": "combat",
		"desc": "Once per round: the first friendly that would die survives at 1 HP.",
		"hooks": ["creature_death"], "effect": "phantom_veil", "value": 1},
	"hexagonal_shield": {"id": "hexagonal_shield", "name": "Hexagonal Shield", "tier": "combat",
		"desc": "Enemy Ranged attacks can't target your back row.",
		"hooks": [], "effect": "back_ranged_immune", "value": 0},

	# ═══════════════════════════════════════════
	#  UTILITY RELICS (5)
	# ═══════════════════════════════════════════
	"merchants_license": {"id": "merchants_license", "name": "Merchant's License", "tier": "utility",
		"desc": "Shop prices reduced by 25%.",
		"hooks": [], "effect": "shop_discount", "value": 25},
	"collectors_tome": {"id": "collectors_tome", "name": "Collector's Tome", "tier": "utility",
		"desc": "Enlist 2 cards at recruit camps instead of 1.",
		"hooks": [], "effect": "double_reward_pick", "value": 0},
	"blacksmiths_hammer": {"id": "blacksmiths_hammer", "name": "Blacksmith's Hammer", "tier": "utility",
		"desc": "Sharpen/Fortify give +3 instead of +2. Imbue offers 3 choices.",
		"hooks": [], "effect": "upgrade_bonus", "value": 0},
	"scavengers_pouch": {"id": "scavengers_pouch", "name": "Scavenger's Pouch", "tier": "utility",
		"desc": "Gain 20 gold when you remove a card.",
		"hooks": ["card_removed"], "effect": "gold_on_remove", "value": 20},
	"whetstone": {"id": "whetstone", "name": "Whetstone", "tier": "utility",
		"desc": "Once per act, Reforge at a rest site: upgrade 2 cards instead of 1.",
		"hooks": [], "effect": "whetstone_reforge", "value": 2},

	# ═══════════════════════════════════════════
	#  BOSS RELICS (pick 1 of 3 after boss kill, all +1 max mana with downside)
	# ═══════════════════════════════════════════
	"cursed_key": {"id": "cursed_key", "name": "Cursed Key", "tier": "boss",
		"desc": "+1 max Command. Gain a Curse after every fight.",
		"hooks": ["combat_end"], "effect": "boss_mana", "value": 1,
		"downside": "curse_on_reward"},
	"coffee_dripper": {"id": "coffee_dripper", "name": "Coffee Dripper", "tier": "boss",
		"desc": "+1 max Command. Can't heal at rest sites.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_rest_heal"},
	"fusion_hammer": {"id": "fusion_hammer", "name": "Fusion Hammer", "tier": "boss",
		"desc": "+1 max Command. Can't upgrade cards at rest sites.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_upgrade"},
	"ectoplasm": {"id": "ectoplasm", "name": "Ectoplasm", "tier": "boss",
		"desc": "+1 max Command. Can't gain gold.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_gold"},
	"busted_crown": {"id": "busted_crown", "name": "Busted Crown", "tier": "boss",
		"desc": "+1 max Command. Recruit camps show 1 choice instead of 3.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "fewer_rewards"},
	"sozu": {"id": "sozu", "name": "Sozu", "tier": "boss",
		"desc": "+1 max Command. Can't gain potions.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_potions"},
	"philosophers_stone": {"id": "philosophers_stone", "name": "Philosopher's Stone", "tier": "boss",
		"desc": "+1 max Command. All enemies get +1 ATK.",
		"hooks": ["combat_start"], "effect": "boss_mana", "value": 1,
		"downside": "enemy_atk_buff"},
	"velvet_choker": {"id": "velvet_choker", "name": "Velvet Choker", "tier": "boss",
		"desc": "+1 max Command. Can only play 5 cards per turn.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "play_limit"},
	"mark_of_pain": {"id": "mark_of_pain", "name": "Mark of Pain", "tier": "boss",
		"desc": "+1 max Command. Start each fight with 2 Curses in your draw pile.",
		"hooks": ["combat_start"], "effect": "boss_mana", "value": 1,
		"downside": "start_curses"},

	# ═══════════════════════════════════════════
	#  MANA RELICS (regular, found in shops/events/rewards)
	# ═══════════════════════════════════════════
	"lantern": {"id": "lantern", "name": "Lantern", "tier": "combat",
		"desc": "On turn 1 of each fight, gain 1 bonus Command.",
		"hooks": ["turn_start"], "effect": "bonus_mana_turn1", "value": 1,
		"mana_cap_cost": 1},
	"happy_flower": {"id": "happy_flower", "name": "Happy Flower", "tier": "combat",
		"desc": "Every 3 turns, gain 1 bonus Command.",
		"hooks": ["turn_start"], "effect": "happy_flower", "value": 1},
	"ice_cream": {"id": "ice_cream", "name": "Ice Cream", "tier": "combat",
		"desc": "Unspent Command carries over fully between turns (no cap).",
		"hooks": [], "effect": "full_mana_bank", "value": 0},
	"art_of_war": {"id": "art_of_war", "name": "Art of War", "tier": "combat",
		"desc": "If you play no cards this turn, gain 1 extra Command next turn.",
		"hooks": ["turn_end"], "effect": "art_of_war", "value": 1},
	"sundial": {"id": "sundial", "name": "Sundial", "tier": "combat",
		"desc": "Every 3 deck shuffles, gain 2 Command.",
		"hooks": ["deck_shuffle"], "effect": "sundial", "value": 2},

	# ═══════════════════════════════════════════════════════════════════════
	#  ROUND 3 REDESIGN PASS — new relics from StS + Hades + Monster Train +
	#  Balatro + Wildfrost + Cobalt Core + Inscryption + Backpack Hero + AtO.
	#  Effect IDs are semantic; Combat.gd handlers added per relic as they ship.
	# ═══════════════════════════════════════════════════════════════════════

	# ─── Cost manipulation ───
	"mummified_hand": {"id": "mummified_hand", "name": "Mummified Hand", "tier": "combat",
		"desc": "When you cast a spell: a random creature in your hand costs 0 this turn.",
		"hooks": ["spell_played"], "effect": "mummified_hand", "value": 0},
	"sigil_of_hunger": {"id": "sigil_of_hunger", "name": "Sigil of Hunger", "tier": "combat",
		"desc": "After a friendly dies: the next creature you play costs 1 less. Once per round.",
		"hooks": ["creature_death"], "effect": "sigil_of_hunger", "value": 1},
	"tricksters_glove": {"id": "tricksters_glove", "name": "Trickster's Glove", "tier": "combat",
		"desc": "While you hold 4+ cards, all cards in hand cost 1 less.",
		"hooks": [], "effect": "tricksters_glove", "value": 1},
	"pact_of_embers": {"id": "pact_of_embers", "name": "Pact of Embers", "tier": "combat",
		"desc": "At turn start: the highest-cost card in hand costs 0 this turn.",
		"hooks": ["turn_start"], "effect": "pact_of_embers", "value": 0},
	"mana_tide": {"id": "mana_tide", "name": "War Chest", "tier": "combat",
		"desc": "After you bank Command: the next creature you play costs 1 less.",
		"hooks": ["mana_banked"], "effect": "mana_tide", "value": 1},
	"last_breath": {"id": "last_breath", "name": "Last Breath", "tier": "combat",
		"desc": "Creatures with 1 base HP cost 1 less.",
		"hooks": [], "effect": "last_breath_discount", "value": 1},

	# ─── Hand / draw manipulation ───
	"frozen_eye": {"id": "frozen_eye", "name": "Frozen Eye", "tier": "combat",
		"desc": "See the top card of your draw pile.",
		"hooks": [], "effect": "frozen_eye", "value": 0},
	"toolbox": {"id": "toolbox", "name": "Toolbox", "tier": "combat",
		"desc": "Start of each fight: choose 1 of 3 extra cards to add to your hand.",
		"hooks": ["combat_start"], "effect": "toolbox", "value": 3},
	"bottled_talisman": {"id": "bottled_talisman", "name": "Bottled Talisman", "tier": "combat",
		"desc": "Choose a card in your deck. Always start each fight with it in your hand.",
		"hooks": ["combat_start"], "effect": "bottled_talisman", "value": 0},
	"looking_glass": {"id": "looking_glass", "name": "Looking Glass", "tier": "combat",
		"desc": "First card drawn each turn is the cheapest card in your draw pile.",
		"hooks": ["turn_start"], "effect": "looking_glass", "value": 0},

	# ─── 4x4 lane / positional ───
	"phalanx_stone": {"id": "phalanx_stone", "name": "Phalanx Stone", "tier": "combat",
		"desc": "If all 4 front lanes are full: friendlies have +1 ATK.",
		"hooks": [], "effect": "phalanx_full_front", "value": 1},
	"cavalry_sigil": {"id": "cavalry_sigil", "name": "Cavalry Sigil", "tier": "combat",
		"desc": "Empty edge lanes (1 & 4): +1 Command per turn each.",
		"hooks": ["turn_start"], "effect": "empty_edge_mana", "value": 1,
		"mana_cap_cost": 1},
	"sentinel_pact": {"id": "sentinel_pact", "name": "Sentinel Pact", "tier": "combat",
		"desc": "Empty lanes count as friendlies for your Adj. Buff effects.",
		"hooks": [], "effect": "empty_lanes_as_adj", "value": 0},
	"catapult_crew": {"id": "catapult_crew", "name": "Catapult Crew", "tier": "combat",
		"desc": "Your back-row creatures gain Ranged.",
		"hooks": [], "effect": "back_row_ranged", "value": 0},
	"bridge_watcher": {"id": "bridge_watcher", "name": "Bridge Watcher", "tier": "combat",
		"desc": "Center-lane friendlies (2 & 3) have Thorns 2 and +1 HP.",
		"hooks": [], "effect": "center_lane_buff", "value": 1},
	"spotters_glass": {"id": "spotters_glass", "name": "Spotter's Glass", "tier": "combat",
		"desc": "When you place a creature in an empty column: +1 ATK to friendlies in that column.",
		"hooks": ["creature_played"], "effect": "empty_column_atk", "value": 1},
	"flanking_banner": {"id": "flanking_banner", "name": "Flanking Banner", "tier": "combat",
		"desc": "When 3 of 4 front lanes are full: enemies in the empty column take 2 at end of round.",
		"hooks": ["round_end"], "effect": "flank_damage", "value": 2},

	# ─── Combat-start setups ───
	"bag_of_marbles": {"id": "bag_of_marbles", "name": "Bag of Marbles", "tier": "combat",
		"desc": "Start of fight: deal 1 damage to all enemies.",
		"hooks": ["combat_start"], "effect": "marbles_aoe", "value": 1},
	"champions_belt": {"id": "champions_belt", "name": "Champion's Belt", "tier": "combat",
		"desc": "On turn 1 of each fight: friendlies have +1 ATK.",
		"hooks": ["combat_start"], "effect": "champions_belt", "value": 1},
	"war_drum": {"id": "war_drum", "name": "War Drum", "tier": "combat",
		"desc": "Start of fight: a random friendly creature from your deck enters lane 1.",
		"hooks": ["combat_start"], "effect": "war_drum_spawn", "value": 0},
	"witchs_brew": {"id": "witchs_brew", "name": "Witch's Brew", "tier": "combat",
		"desc": "Start of fight: cast a random spell from your deck at no cost. Auto-targeted.",
		"hooks": ["combat_start"], "effect": "witchs_brew", "value": 0},

	# ─── Conditional / Balatro-style scaling ───
	"spell_tome": {"id": "spell_tome", "name": "Spell Tome", "tier": "combat",
		"desc": "If 50%+ of your deck is spells: all spells cost 1 less.",
		"hooks": [], "effect": "spell_tome_discount", "value": 1},
	"iron_legion": {"id": "iron_legion", "name": "Iron Legion", "tier": "combat",
		"desc": "If 60%+ of your deck is creatures: friendlies have +1 HP.",
		"hooks": ["creature_played"], "effect": "iron_legion_buff", "value": 1},
	"tome_of_many": {"id": "tome_of_many", "name": "Tome of Many", "tier": "combat",
		"desc": "If your deck has 20+ cards: draw 2 extra per turn.",
		"hooks": ["turn_start"], "effect": "big_deck_draw", "value": 2},
	"mana_drunkard": {"id": "mana_drunkard", "name": "Forced March", "tier": "combat",
		"desc": "If you spend all your Command 2 turns in a row: +1 max Command this fight.",
		"hooks": ["turn_end"], "effect": "mana_drunkard", "value": 1},

	# ─── Sacrifice / death deepening ───
	"skull_throne": {"id": "skull_throne", "name": "Skull Throne", "tier": "combat",
		"desc": "When 5 friendlies die in one round: +2 max Command this fight.",
		"hooks": ["creature_death"], "effect": "skull_throne", "value": 2},
	"reapers_scythe": {"id": "reapers_scythe", "name": "Reaper's Scythe", "tier": "combat",
		"desc": "When you sacrifice a creature with an On-Enter effect: the next creature you play also triggers it.",
		"hooks": ["sacrifice"], "effect": "reapers_scythe", "value": 0},
	"du_vu_doll": {"id": "du_vu_doll", "name": "Du-Vu Doll", "tier": "combat",
		"desc": "+1 ATK to all friendlies for each Curse in your deck.",
		"hooks": ["creature_played"], "effect": "du_vu_doll", "value": 1},
	"soul_ledger": {"id": "soul_ledger", "name": "Soul Ledger", "tier": "combat",
		"desc": "Every 5th friendly death (across all fights): summon a 4/4 token in a random empty lane.",
		"hooks": ["creature_death"], "effect": "soul_ledger", "value": 5},

	# ─── Spell deepening ───
	"reagent_pouch": {"id": "reagent_pouch", "name": "Reagent Pouch", "tier": "combat",
		"desc": "Your first spell each fight is Sharpened (+2 spell damage).",
		"hooks": ["spell_played"], "effect": "reagent_pouch", "value": 2},
	"inkpot_of_many": {"id": "inkpot_of_many", "name": "Inkpot of Many", "tier": "combat",
		"desc": "Every 5th spell cast: choose a random spell to copy into your hand.",
		"hooks": ["spell_played"], "effect": "inkpot", "value": 5},
	"mana_pearl": {"id": "mana_pearl", "name": "Knife Up the Sleeve", "tier": "combat",
		"desc": "Spells that cost 0 deal +3 damage.",
		"hooks": ["spell_damage"], "effect": "zero_cost_spell_bonus", "value": 3},

	# ─── Build-around scaling ───
	"pen_nib": {"id": "pen_nib", "name": "Pen Nib", "tier": "combat",
		"desc": "Every 10th card played: choose a creature in your deck. It becomes 6/6 Piercing this fight.",
		"hooks": ["card_played"], "effect": "pen_nib", "value": 10},
	"wormwood": {"id": "wormwood", "name": "Wormwood", "tier": "combat",
		"desc": "When a friendly takes damage: it gains +1 ATK permanently (max +5 per creature per fight).",
		"hooks": ["creature_damaged"], "effect": "wormwood", "value": 5},

	# ─── Hades imports (boon/keepsake-flavored) ───
	"stygian_soul": {"id": "stygian_soul", "name": "Stygian Soul", "tier": "combat",
		"desc": "When an enemy dies: heal 1 HP. Max 5 per fight.",
		"hooks": ["enemy_death"], "effect": "heal_on_kill", "value": 5},
	"bone_hourglass": {"id": "bone_hourglass", "name": "Bone Hourglass", "tier": "combat",
		"desc": "Each act, pick: +1 ATK in front row / +1 HP in back row / +1 max Command when center lanes are full.",
		"hooks": ["act_start"], "effect": "bone_hourglass", "value": 0},

	# ─── Monster Train imports ───
	"pyre_stoker": {"id": "pyre_stoker", "name": "Pyre Stoker", "tier": "combat",
		"desc": "Face damage you deal is +1 if you played 3+ cards this turn.",
		"hooks": ["face_damage_dealt"], "effect": "pyre_stoker", "value": 1},
	"spike_driver": {"id": "spike_driver", "name": "Spike Driver", "tier": "combat",
		"desc": "When a friendly is attacked: deal 1 damage back. Stacks with Thorns.",
		"hooks": ["creature_damaged"], "effect": "spike_driver", "value": 1},
	"imp_generator": {"id": "imp_generator", "name": "Imp Generator", "tier": "combat",
		"desc": "End of each round: summon a 1/1 Imp token in a random empty back-row lane.",
		"hooks": ["round_end"], "effect": "imp_generator", "value": 0},

	# ─── Balatro imports (conditional copy/scaling) ───
	"blueprint": {"id": "blueprint", "name": "Blueprint", "tier": "combat",
		"desc": "The next creature you play copies the On-Enter effect of the previous creature you played this fight.",
		"hooks": ["creature_played"], "effect": "blueprint", "value": 0},
	"brainstorm": {"id": "brainstorm", "name": "Brainstorm", "tier": "combat",
		"desc": "Each round, the first creature you play copies the keywords of the first creature you played this fight.",
		"hooks": ["creature_played"], "effect": "brainstorm", "value": 0},
	"mime": {"id": "mime", "name": "Mime", "tier": "combat",
		"desc": "At end of turn, one chosen card in hand is played for free, triggering its On-Enter effect.",
		"hooks": ["turn_end"], "effect": "mime", "value": 0},
	"the_family": {"id": "the_family", "name": "The Family", "tier": "combat",
		"desc": "If you have 3+ creatures with the same id on the field: those creatures have +1 ATK.",
		"hooks": [], "effect": "tribal_atk", "value": 1},

	# ─── Wildfrost imports ───
	"frost_spike": {"id": "frost_spike", "name": "Frost Spike", "tier": "combat",
		"desc": "The first creature you play each fight applies Wither 1 when it attacks.",
		"hooks": ["creature_played"], "effect": "frost_spike", "value": 1},
	"junk_slot": {"id": "junk_slot", "name": "Junk Slot", "tier": "combat",
		"desc": "If you have 4+ empty board slots: +1 max Command.",
		"hooks": [], "effect": "junk_slot_mana", "value": 1,
		"mana_cap_cost": 1},

	# ─── Cobalt Core imports ───
	"hourglass_sigil": {"id": "hourglass_sigil", "name": "Hourglass Sigil", "tier": "combat",
		"desc": "End of turn: gain a Pending counter. At 5 Pending: gain a random rare card to hand.",
		"hooks": ["turn_end"], "effect": "hourglass_sigil", "value": 5},

	# ─── Inscryption imports ───
	"totem_pole": {"id": "totem_pole", "name": "Totem Pole", "tier": "combat",
		"desc": "Each act, pick a keyword (Thorns / Swift / Regenerate / Armored). All friendlies have it this act.",
		"hooks": ["act_start"], "effect": "totem_pole", "value": 0},
	"death_card": {"id": "death_card", "name": "Death Card", "tier": "combat",
		"desc": "Friendlies that die this fight go to your hand instead of discard. Each costs +1 more every time it returns this fight.",
		"hooks": ["creature_death"], "effect": "death_card", "value": 1},

	# ─── Backpack Hero imports (4x4 adjacency variants) ───
	"linked_banner": {"id": "linked_banner", "name": "Linked Banner", "tier": "combat",
		"desc": "Friendlies with 2+ adjacent friendlies have +1 ATK and +1 HP.",
		"hooks": [], "effect": "linked_adj", "value": 1},
	"diagonal_crest": {"id": "diagonal_crest", "name": "Diagonal Crest", "tier": "combat",
		"desc": "Diagonal friendlies count as adjacent. Your Adj. Buff effects grant +1 extra HP.",
		"hooks": [], "effect": "diagonal_adj", "value": 1},
	"corner_stone": {"id": "corner_stone", "name": "Corner Stone", "tier": "combat",
		"desc": "Friendlies in lane 1 or lane 4 have Thorns 2.",
		"hooks": [], "effect": "corner_thorns", "value": 2},

	# ═══════════════════════════════════════════════════════════════════════
	#  CLASS-RESTRICTED COMBAT RELICS (4) — only offered to matching hero.
	#  Filter applied in filter_pool_for_run() via the restricted_to field.
	# ═══════════════════════════════════════════════════════════════════════
	"raiders_oath": {"id": "raiders_oath", "name": "Raider's Oath", "tier": "combat",
		"desc": "Raider only. When you play a creature with Swift: gain 1 Command this turn.",
		"hooks": ["creature_played"], "effect": "swift_mana", "value": 1,
		"restricted_to": "raider"},
	"stalwarts_anvil": {"id": "stalwarts_anvil", "name": "Stalwart's Anvil", "tier": "combat",
		"desc": "Stalwart only. The first time a friendly takes damage each turn: gain 1 Command this turn.",
		"hooks": ["creature_damaged"], "effect": "first_hit_mana", "value": 1,
		"restricted_to": "stalwart", "mana_cap_cost": 1},
	"acolytes_tome": {"id": "acolytes_tome", "name": "Acolyte's Tome", "tier": "combat",
		"desc": "Acolyte only. When you exhaust a spell: draw 1 card.",
		"hooks": ["spell_exhausted"], "effect": "exhaust_draw", "value": 1,
		"restricted_to": "acolyte"},
	"pyromancers_scar": {"id": "pyromancers_scar", "name": "Pyromancer's Scar", "tier": "combat",
		"desc": "Pyromancer only. Your first spell each fight is Doubled (cast twice on the same target).",
		"hooks": ["spell_played"], "effect": "first_spell_double", "value": 0,
		"restricted_to": "pyromancer"},

	# ═══════════════════════════════════════════════════════════════════════
	#  UTILITY RELICS — Round 3 additions (3) — hook into map / reward flow.
	# ═══════════════════════════════════════════════════════════════════════
	"olympians_mark": {"id": "olympians_mark", "name": "Olympian's Mark", "tier": "utility",
		"desc": "After you defeat a General: upgrade a random card in your deck for free.",
		"hooks": ["elite_won"], "effect": "post_elite_upgrade", "value": 1},
	"centaur_heart": {"id": "centaur_heart", "name": "Centaur Heart", "tier": "utility",
		"desc": "When you reach Act 2: gain +5 max HP and heal to full.",
		"hooks": ["act_start"], "effect": "centaur_heart", "value": 5},
	"stardust_vial": {"id": "stardust_vial", "name": "Stardust Vial", "tier": "utility",
		"desc": "Recruit camps also offer 1 rare card.",
		"hooks": [], "effect": "stardust_vial", "value": 1},

	# ═══════════════════════════════════════════════════════════════════════
	#  EVENT RELICS — never rolled (tier "event" is in no reward pool); each
	#  is granted by name from its event and carries that event's story.
	# ═══════════════════════════════════════════════════════════════════════
	"coin_landed": {"id": "coin_landed", "name": "The Coin, Landed", "tier": "event",
		"desc": "Whenever a creature dies: gain 2 gold.",
		"hooks": ["creature_death"], "effect": "gold_on_death", "value": 2},
	"verse_of_you": {"id": "verse_of_you", "name": "A Verse of You", "tier": "event",
		"desc": "When a friendly creature dies: draw 1 card. Once per round.",
		"hooks": ["creature_death"], "effect": "draw_on_friendly_death", "value": 1},
	"warm_knucklebone": {"id": "warm_knucklebone", "name": "Warm Knucklebone", "tier": "event",
		"desc": "At the start of each turn: 1 in 6 odds to gain 1 Command.",
		"hooks": ["turn_start"], "effect": "chance_bonus_mana", "value": 1},
	"sin_eaters_crust": {"id": "sin_eaters_crust", "name": "The Sin-Eater's Crust", "tier": "event",
		"desc": "Whenever a card leaves your deck: heal 3 HP.",
		"hooks": [], "effect": "heal_on_card_removed", "value": 3},

	# ═══════════════════════════════════════════════════════════════════════
	#  BOSS RELICS — Round 3 additions (9) — run-warping, no +1-mana template.
	#  These replace the "all boss relics are +1 mana with downside" monotony.
	# ═══════════════════════════════════════════════════════════════════════
	"pandoras_box": {"id": "pandoras_box", "name": "Pandora's Box", "tier": "boss",
		"desc": "Transform all your starting creatures into random rare creatures.",
		"hooks": [], "effect": "pandoras_box", "value": 0},
	"snecko_eye": {"id": "snecko_eye", "name": "Snecko Eye", "tier": "boss",
		"desc": "Draw 6 cards instead of 4. Every card in hand has its cost randomized 0-3 each turn.",
		"hooks": ["turn_start"], "effect": "snecko_eye", "value": 6},
	"calling_bell": {"id": "calling_bell", "name": "Calling Bell", "tier": "boss",
		"desc": "Gain 3 boss relics. Add 3 Curses to your deck.",
		"hooks": [], "effect": "calling_bell", "value": 3},
	"runic_pyramid": {"id": "runic_pyramid", "name": "Runic Pyramid", "tier": "boss",
		"desc": "You no longer discard your hand at end of turn.",
		"hooks": [], "effect": "no_end_turn_discard", "value": 0},
	"lichs_bargain": {"id": "lichs_bargain", "name": "Lich's Bargain", "tier": "boss",
		"desc": "Friendlies trigger On-Death effects twice. After each fight: lose 1 HP per friendly death (max 3).",
		"hooks": ["creature_death", "combat_end"], "effect": "lichs_bargain", "value": 2},
	"lean_mean": {"id": "lean_mean", "name": "Lean Mean", "tier": "boss",
		"desc": "+1 max Command while your deck has 14 or fewer cards.",
		"hooks": [], "effect": "lean_mean", "value": 1},
	"glowing_hand": {"id": "glowing_hand", "name": "Glowing Hand", "tier": "boss",
		"desc": "Your damage spells deal +1 per spell already cast this fight (max +5).",
		"hooks": ["spell_damage"], "effect": "glowing_hand", "value": 5},
	"marathoners_sash": {"id": "marathoners_sash", "name": "Marathoner's Sash", "tier": "boss",
		"desc": "+2 max Command. Start each fight with 1 Command; gain 2 Command per round (capped at max).",
		"hooks": ["combat_start", "turn_start"], "effect": "marathoners_sash", "value": 2},
	"steady_banner": {"id": "steady_banner", "name": "Steady Banner", "tier": "boss",
		"desc": "Friendlies that survive a full round on the field gain +2 ATK permanently. Friendlies have -1 ATK on turn 1.",
		"hooks": ["round_end", "creature_played"], "effect": "steady_banner", "value": 2},

	# ═══════════════════════════════════════════════════════════════════════
	#  WAVE 2 — keyword-synergy + build-defining relics (Doom / Rampage /
	#  Lifelink payoffs, plus board-buff / spell / armor / on-death engines).
	#  Implemented inline in Combat.gd at the noted hook points.
	# ═══════════════════════════════════════════════════════════════════════

	# ─── Doom synergy ───
	"doom_herald": {"id": "doom_herald", "name": "Doom Herald", "tier": "combat",
		"desc": "When one of your Doom creatures detonates: draw 1.",
		"hooks": ["doom_detonate"], "effect": "doom_detonate_draw", "value": 1},
	"hourglass_of_ruin": {"id": "hourglass_of_ruin", "name": "Hourglass of Ruin", "tier": "boss",
		"desc": "Your Doom creatures detonate 1 round sooner.",
		"hooks": ["creature_played"], "effect": "doom_accelerate", "value": 1},

	# ─── Rampage synergy ───
	"berserkers_totem": {"id": "berserkers_totem", "name": "Berserker's Totem", "tier": "combat",
		"desc": "Your Rampage triggers grant +1 extra ATK.",
		"hooks": [], "effect": "rampage_bonus", "value": 1},

	# ─── Lifelink synergy ───
	"crimson_chalice": {"id": "crimson_chalice", "name": "Crimson Chalice", "tier": "combat",
		"desc": "Your Lifelink heals +1 extra HP.",
		"hooks": [], "effect": "lifelink_bonus", "value": 1},

	# ─── Board-wide buff engine ───
	"warlords_standard": {"id": "warlords_standard", "name": "Warlord's Standard", "tier": "combat",
		"desc": "Start of each round after the first: your front-row creatures gain +1 ATK permanently.",
		"hooks": ["round_start"], "effect": "front_row_ramp", "value": 1},

	# ─── Spell-matters engine ───
	"runebound_idol": {"id": "runebound_idol", "name": "Runebound Idol", "tier": "combat",
		"desc": "When you cast a spell: a random friendly creature gains +1/+1 permanently.",
		"hooks": ["spell_played"], "effect": "spell_buffs_creature", "value": 1},

	# ─── Armor engine ───
	"bulwark_engine": {"id": "bulwark_engine", "name": "Bulwark Engine", "tier": "combat",
		"desc": "Start of each round: your Armored creatures gain +1 HP.",
		"hooks": ["round_start"], "effect": "armored_ramp", "value": 1},

	# ─── On-death reincarnation engine ───
	"gravewardens_pact": {"id": "gravewardens_pact", "name": "Gravewarden's Pact", "tier": "boss",
		"desc": "The first 3 friendlies that die each fight are reborn as 1/1 Imps in their lane.",
		"hooks": ["creature_death"], "effect": "rebirth_imps", "value": 3},
}


static func get_relic(id: String) -> Dictionary:
	if RELICS.has(id):
		return RELICS[id]
	push_warning("RelicDB: unknown relic id '%s'" % id)
	return {}


# Returns the texture for a relic icon, or null if none is installed for that
# id. Stored in `assets/icons/relics/<id>.{png,svg}` — PNG wins so painted
# Hades/StS-style art transparently replaces the legacy SVG silhouettes.
# Both are convention-based so RelicDB entries don't need an explicit path.
static func get_relic_icon(id: String) -> Texture2D:
	var png_path := "res://assets/icons/relics/%s.png" % id
	if ResourceLoader.exists(png_path):
		return load(png_path) as Texture2D
	var svg_path := "res://assets/icons/relics/%s.svg" % id
	if ResourceLoader.exists(svg_path):
		return load(svg_path) as Texture2D
	return null


# True when the relic has a painted PNG icon — used by frame builders to skip
# the gilt-tint they apply to monochrome SVG silhouettes (which would otherwise
# wreck a full-color painting).
static func is_painted_icon(id: String) -> bool:
	return ResourceLoader.exists("res://assets/icons/relics/%s.png" % id)


# Tier accent color for the relic frame's glow halo — at-a-glance rarity cue
# like WoW item quality. Boss relics shine purple, utility green, combat
# warm bronze, starting gold.
const TIER_COLORS := {
	"starting": Color(1.00, 0.85, 0.45, 1.0),
	"combat":   Color(0.95, 0.55, 0.30, 1.0),
	"utility":  Color(0.55, 0.90, 0.50, 1.0),
	"boss":     Color(0.85, 0.45, 1.00, 1.0),
	"event":    Color(0.47, 0.83, 0.75, 1.0),  # verdigris — the "blue option" ink
}

static func get_tier_color(id: String) -> Color:
	if not RELICS.has(id):
		return TIER_COLORS["starting"]
	var tier: String = RELICS[id].get("tier", "starting")
	return TIER_COLORS.get(tier, TIER_COLORS["starting"])


static func get_relics_by_tier(tier: String) -> Array[String]:
	var result: Array[String] = []
	for id in RELICS.keys():
		if RELICS[id].tier == tier:
			result.append(id)
	return result


static func roll_relic_reward(tier: String = "combat", relics_held: Array[String] = [], hero_id: String = "") -> Array[String]:
	var pool: Array[String] = filter_pool_for_run(get_relics_by_tier(tier), hero_id, relics_held)
	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))


static func roll_boss_relics(relics_held: Array[String] = [], hero_id: String = "") -> Array[String]:
	var pool: Array[String] = filter_pool_for_run(get_relics_by_tier("boss"), hero_id, relics_held)
	pool.shuffle()
	return pool.slice(0, mini(3, pool.size()))


static func get_boss_mana_bonus(relics_held: Array[String]) -> int:
	var bonus := 0
	for id in relics_held:
		if RELICS.has(id) and RELICS[id].get("effect", "") == "boss_mana":
			bonus += RELICS[id].get("value", 1)
	return bonus


static func has_downside(relics_held: Array[String], downside: String) -> bool:
	for id in relics_held:
		if RELICS.has(id) and RELICS[id].get("downside", "") == downside:
			return true
	return false


# Sum of mana_cap_cost across held non-boss relics. Capped at 2 by the reward filter.
# Boss-tier mana relics don't count here — they're tracked via get_boss_mana_bonus.
static func get_mana_cap_credit(relics_held: Array[String]) -> int:
	var credit := 0
	for id in relics_held:
		if not RELICS.has(id):
			continue
		var entry: Dictionary = RELICS[id]
		if entry.get("tier", "") == "boss":
			continue
		credit += int(entry.get("mana_cap_cost", 0))
	return credit


# True if acquiring this relic would exceed the +2 non-boss mana cap.
static func would_exceed_mana_cap(relic_id: String, relics_held: Array[String]) -> bool:
	if not RELICS.has(relic_id):
		return false
	var entry: Dictionary = RELICS[relic_id]
	if entry.get("tier", "") == "boss":
		return false
	var cost := int(entry.get("mana_cap_cost", 0))
	if cost == 0:
		return false
	return get_mana_cap_credit(relics_held) + cost > 2


# True if this relic is hero-restricted to a hero other than the current one.
static func is_restricted_to_other_hero(relic_id: String, hero_id: String) -> bool:
	if not RELICS.has(relic_id):
		return false
	var restriction: String = RELICS[relic_id].get("restricted_to", "")
	if restriction == "":
		return false
	return restriction != hero_id


# Central reward-pool filter. Strips relics the player can't have right now:
# already owned, wrong-hero restricted, or would push past the mana cap.
static func filter_pool_for_run(pool: Array[String], hero_id: String, relics_held: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for id in pool:
		if relics_held.has(id):
			continue
		if is_restricted_to_other_hero(id, hero_id):
			continue
		if would_exceed_mana_cap(id, relics_held):
			continue
		result.append(id)
	return result
