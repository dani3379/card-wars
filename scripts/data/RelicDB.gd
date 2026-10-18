extends Node
## RelicDB.gd — relic catalog. Retired entries remain readable for old saves,
## but every live reward is drawn through the eligibility filters below.
## ~122 relics after the 2026-07-07 pool cut (14 dead/no-decision relics removed,
## 5 reshaped in place, 6 new system-payoff relics — see the dated section at the
## bottom of RELICS) on top of the 3-round design pass + Wave 2 keyword/build relics
## (StS + Hades + Monster Train + Balatro + Wildfrost + Cobalt Core + Inscryption + Backpack Hero + AtO imports).
##
## 2026-07-08 BALANCE PASS — the combat pool was rolled as a FLAT shuffle (every
## relic equally likely), so a run-warping engine and a niche trickle had the same
## odds — the root of the "some relics are way more disgusting than others" swing.
## Two fixes: (1) RELIC_RARITY now WEIGHTS the roll (common workhorses show often,
## rare engines rarely — the outliers are tamed by SCARCITY, not by shaving their
## numbers); (2) nine near-duplicate combat relics were merged into their
## best-in-class sibling (retired: true — kept for old saves/collection, never
## rolled). The two merged relics that also sat in skirmish's NET_RELIC_POOL
## (happy_flower, mana_tide) were dropped from that list too, for consistency.
##
## hooks: game events this relic responds to. Combat.gd checks these.
##
## Optional schema fields:
##   restricted_to: "<hero_id>"  — only offered to that hero (raider/stalwart/acolyte/pyromancer/kindler).
##   mana_cap_cost: int          — counts toward non-boss mana ceiling (+2 max). Boss-tier mana relics bypass.
##   downside: "<id>"            — pairs with boss "+1 max mana" trade.
##   retired: true               — kept for old saves/collection, not offered in new rewards.

const RELICS: Dictionary = {
	# ═══════════════════════════════════════════
	#  STARTING / SIGNATURE RELICS
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
		"desc": "When you cast a spell already cast this fight: draw 1. If it deals damage, it deals +2 damage.",
		"hooks": ["spell_played", "spell_damage"], "effect": "repeat_spellbook", "value": 2},
	"scouts_emblem": {"id": "scouts_emblem", "name": "Scout's Emblem", "tier": "starting",
		"desc": "Recruit camps show 4 choices instead of 3.",
		"hooks": [], "effect": "extra_reward_choice", "value": 1},
	# 2026-07-25: death still pays the bill, but it pays in BODIES rather than
	# Command — Command is a fixed resource and no relic should manufacture it.
	# The Acolyte's "spend cheap creatures freely" loop is unchanged in play; the
	# payout is now a body on the board, which also feeds the Dead tribe's
	# death-spine payoffs instead of sitting in a resource counter.
	"soul_lantern": {"id": "soul_lantern", "name": "Soul Lantern", "tier": "starting",
		"desc": "When the first friendly dies each round: a Shade rises in its lane (1/1).",
		"hooks": ["creature_death"], "effect": "shade_on_death", "value": 1},
	"veterans_medal": {"id": "veterans_medal", "name": "Veteran's Medal", "tier": "starting",
		"desc": "Your 1-cost creatures have +1/+1.",
		"hooks": ["creature_played"], "effect": "buff_cheap_creatures", "value": 1},
	"ember_censer": {"id": "ember_censer", "name": "Ember Censer", "tier": "starting",
		"desc": "When one of your Doom creatures detonates: it deals +1 damage.",
		"hooks": ["doom_detonate"], "effect": "doom_detonate_bonus", "value": 1},
	# Low-duplicate hero Doctrines (2026-07-28). New ids preserve legacy saves
	# and keep Skirmish's historical starter-relic semantics unchanged.
	"marching_spurs": {"id": "marching_spurs", "name": "Marching Spurs", "tier": "starting",
		"campaign_only": true, "restricted_to": "raider", "icon": "drovers_whip",
		"desc": "The first friendly you relocate each round gets +1 ATK and Swift this round.",
		"hooks": ["lane_changed"], "effect": "starter_first_relocate_swift", "value": 1},
	"rearward_horn": {"id": "rearward_horn", "name": "Rearward Horn", "tier": "starting",
		"campaign_only": true, "restricted_to": "raider", "icon": "war_horn",
		"desc": "The first creature you play in your back row each round gets +1 ATK and Swift this round.",
		"hooks": ["creature_played"], "effect": "starter_back_row_swift", "value": 1},
	"centurions_rule": {"id": "centurions_rule", "name": "Centurion's Rule", "tier": "starting",
		"campaign_only": true, "restricted_to": "stalwart", "icon": "iron_buckler",
		"desc": "The first friendly to survive a hit each round gains +1 HP this fight. One adjacent friendly does too.",
		"hooks": ["creature_damaged"], "effect": "starter_survive_adjacent_hp", "value": 1},
	"reserve_standard": {"id": "reserve_standard", "name": "Reserve Standard", "tier": "starting",
		"campaign_only": true, "restricted_to": "stalwart", "icon": "vanguard_banner",
		"desc": "The first creature you play directly behind a friendly each round gains Shield.",
		"hooks": ["creature_played"], "effect": "starter_back_rank_shield", "value": 1},
	# Reshaped 2026-07-28. This shipped with Soul Lantern's desc word for word, so
	# the Acolyte's signature/alternate pick was no choice at all. The pair now
	# reads: double the bequest (here) vs transfer the strength (Ledger Seal).
	"funeral_lantern": {"id": "funeral_lantern", "name": "Funeral Lantern", "tier": "starting",
		"campaign_only": true, "restricted_to": "acolyte", "icon": "soul_lantern",
		"desc": "When the first friendly dies each round: its On-Death effect fires a second time.",
		"hooks": ["creature_death"], "effect": "starter_double_first_bequest", "value": 1},
	"ledger_seal": {"id": "ledger_seal", "name": "Ledger Seal", "tier": "starting",
		"campaign_only": true, "restricted_to": "acolyte", "icon": "coin_purse",
		"desc": "When the first friendly dies each round: a surviving friendly in its column gains +1/+1 this fight.",
		"hooks": ["creature_death"], "effect": "starter_death_column_buff", "value": 1},
	"mirror_primer": {"id": "mirror_primer", "name": "Mirror Primer", "tier": "starting",
		"campaign_only": true, "restricted_to": "pyromancer", "icon": "worn_spellbook",
		"desc": "The first time you cast two differently named spells each round: draw 1.",
		"hooks": ["spell_played"], "effect": "starter_distinct_spell_draw", "value": 1},
	# Reshaped 2026-07-28, twice over. It shipped as "your first non-damage spell
	# each round costs 0" — Command manipulation (a standing no), and a strictly
	# narrower Ember Crown, which is an unrestricted starting relic the Pyromancer
	# can simply find, so her unlockable doctrine was worse than a common pickup.
	"cinder_crown": {"id": "cinder_crown", "name": "Cinder Crown", "tier": "starting",
		"campaign_only": true, "restricted_to": "pyromancer", "icon": "ember_crown",
		"desc": "The first damage spell you cast each round deals +1 damage.",
		"hooks": ["spell_played"], "effect": "starter_first_spell_damage", "value": 1},
	"chain_censer": {"id": "chain_censer", "name": "Chain Censer", "tier": "starting",
		"campaign_only": true, "restricted_to": "kindler", "icon": "ember_censer",
		"desc": "Your first Doom detonation each round reduces adjacent friendly Doom timers by 1.",
		"hooks": ["doom_detonate"], "effect": "starter_chain_doom", "value": 1},
	# The timer clause was dropped 2026-07-28: a first-win unlock must be strictly
	# positive, and pushing a fuse OUT fought the Kindler's other doctrine (Chain
	# Censer), which exists to pull fuses IN. The body is worth more instead.
	"war_bellows": {"id": "war_bellows", "name": "War Bellows", "tier": "starting",
		"campaign_only": true, "restricted_to": "kindler", "icon": "war_horn",
		"desc": "The first Doom creature you play each round gains +2/+2.",
		"hooks": ["creature_played"], "effect": "starter_doom_buff", "value": 2},

	# ═══════════════════════════════════════════
	#  COMBAT RELICS — Field rewards and shop stock
	# ═══════════════════════════════════════════
	# ── 2026-07-03 interest pass: six of the invisible "+1 to a subtype"
	# micro-modifiers below were reshaped into trigger-relics with a visible
	# moment (same ids — collections and saves stay valid). Balance rule:
	# reshape into situational/dramatic, don't tune numbers.
	"vanguards_cry": {"id": "vanguards_cry", "name": "Vanguard's Cry", "tier": "combat",
		"desc": "The first creature you play each fight deals 2 damage to the opposing creature.",
		"hooks": ["creature_played"], "effect": "war_cry_open", "value": 2},
	"banner_of_unity": {"id": "banner_of_unity", "name": "Banner of Unity", "tier": "combat",
		"desc": "When you play a creature between two friendlies: all three gain +1 ATK this fight.",
		"hooks": ["creature_played"], "effect": "flanked_rally", "value": 1},
	"swift_boots": {"id": "swift_boots", "name": "Swift Boots", "tier": "combat",
		"desc": "Swift creatures have +1 ATK. The first time your Swift creatures strike in a fight: draw a card.",
		"hooks": [], "effect": "swift_atk_bonus", "value": 1, "retired": true},
	"briar_amulet": {"id": "briar_amulet", "name": "Man-Trap", "tier": "combat",
		"desc": "When an enemy dies from your Thorns: adjacent enemies take 2 damage.",
		"hooks": [], "effect": "man_trap", "value": 2},
	"echo_staff": {"id": "echo_staff", "name": "Echo Staff", "tier": "combat",
		"desc": "Your On-Enter effects trigger twice.",
		"hooks": ["creature_played"], "effect": "double_floop", "value": 0},
	"piercing_crown": {"id": "piercing_crown", "name": "Bodkin Points", "tier": "combat",
		"desc": "Your creatures deal excess damage from killing blows as if they had Piercing.",
		"hooks": [], "effect": "always_overflow", "value": 0},
	"conscription_relic": {"id": "conscription_relic", "name": "Conscription", "tier": "combat",
		"desc": "Start of each fight: summon a 1/1 Conscript in your back row. Your Summon tokens enter with +1 HP.",
		"hooks": ["combat_start", "summon_token"], "effect": "token_hp_bonus", "value": 1,
		"retired": true},  # 2026-07-08 merged → imp_generator (recurring bodies) + the_family (token stat buff)
	"bone_ring": {"id": "bone_ring", "name": "Bone Ring", "tier": "combat",
		"desc": "Your On-Death damage effects deal +1 damage and 1 damage to enemy face.",
		"hooks": ["on_death_damage"], "effect": "on_death_bonus", "value": 1},
	"war_horn": {"id": "war_horn", "name": "War Horn", "tier": "combat",
		"desc": "After your first spell that grants ATK each fight, all your creatures gain +1 ATK this round.",
		"hooks": ["spell_buff"], "effect": "war_horn_rally", "value": 1,
		"retired": true},  # 2026-07-08 merged → bloodstone_relic (reactive one-round board ATK pump)
	"battle_scars": {"id": "battle_scars", "name": "Battle Scars", "tier": "combat",
		"desc": "The first time you take face damage each fight: gain 2 Command next turn.",
		"hooks": ["hero_damaged"], "effect": "battle_scars_mana", "value": 2},
	"glass_cannon": {"id": "glass_cannon", "name": "Glass Cannon", "tier": "combat",
		"desc": "Your creatures have +1 ATK but -1 HP.",
		"hooks": ["creature_played"], "effect": "glass_cannon", "value": 0, "retired": true},
	"thiefs_gloves": {"id": "thiefs_gloves", "name": "Thief's Gloves", "tier": "combat",
		"desc": "After a fight: if you took 1–5 face damage, gain 15 gold. If you took 0, start the next fight with +1 Command.",
		"hooks": ["combat_end"], "effect": "gold_no_damage", "value": 15},
	"butchers_cleaver": {"id": "butchers_cleaver", "name": "Butcher's Cleaver", "tier": "combat",
		"desc": "When you sacrifice a creature: the next creature you play this turn gets +2 ATK for 2 rounds.",
		"hooks": ["sacrifice"], "effect": "sacrifice_buff", "value": 2},
	"vultures_feast": {"id": "vultures_feast", "name": "Vulture's Feast", "tier": "combat",
		"desc": "After each fight: heal 1 HP per friendly death (max 5).",
		"hooks": ["combat_end"], "effect": "heal_per_death", "value": 1},
	"gamblers_coin": {"id": "gamblers_coin", "name": "Gambler's Coin", "tier": "combat",
		"desc": "Start of each fight: flip a coin. Heads: draw 1. Tails: deal 3 damage to a random enemy creature.",
		"hooks": ["combat_start"], "effect": "gamblers_coin", "value": 0,
		"retired": true},
	"bone_pile": {"id": "bone_pile", "name": "Bone Pile", "tier": "combat",
		"desc": "When you sacrifice a creature: deal its ATK as damage to the opposing creature.",
		"hooks": ["sacrifice"], "effect": "sacrifice_damage", "value": 0},
	"resonance_crystal": {"id": "resonance_crystal", "name": "Resonance Crystal", "tier": "combat",
		"desc": "The first time a friendly with a keyword dies each fight, all your other creatures gain that keyword.",
		"hooks": ["creature_death"], "effect": "resonance_crystal", "value": 0},
	"mimic_ring": {"id": "mimic_ring", "name": "Mimic Ring", "tier": "combat",
		"desc": "When you play a creature: it copies 1 keyword from an adjacent friendly creature.",
		"hooks": ["creature_played"], "effect": "mimic_ring", "value": 0},
	"bloodstone_relic": {"id": "bloodstone_relic", "name": "Bloodstone", "tier": "combat",
		"desc": "When you take face damage: your creatures get +1 ATK this round.",
		"hooks": ["hero_damaged"], "effect": "bloodstone_buff", "value": 1},
	"phoenix_heart": {"id": "phoenix_heart", "name": "Phoenix Heart", "tier": "combat",
		"desc": "Once per run: when you would die, revive at 1 HP instead.",
		"hooks": ["hero_damaged"], "effect": "phoenix_revive", "value": 1},
	# A map/reward-flow relic (no combat hook — spent at the Muster, see Recruit.gd),
	# but filed in the COMBAT pool because that is the only tier any drop path rolls
	# (Treasure / Shop / Reward / Event / War Chest all roll "combat"; "utility" is a
	# collection tag, not a reward pool). `value` is the reroll-charge count and the
	# single source of truth — RunState reads it on acquire; keep desc + value in sync.
	"recruiters_horn": {"id": "recruiters_horn", "name": "Recruiter's Horn", "tier": "combat",
		"desc": "Reroll the cards at a Recruit Camp. 3 uses per run.",
		"hooks": [], "effect": "muster_reroll", "value": 3},

	# ═══════════════════════════════════════════
	#  4x4 RELICS — designed around the front/back row redesign
	# ═══════════════════════════════════════════
	# 2026-07-16 reshape (same-id precedent): the last three invisible always-on
	# passives left standing became the pattern-mined Wave-2 designs — see
	# docs/RELIC_SLATE_PITCH_20260716.md. vanguard_banner (flat front ATK) →
	# The Tally-Stick; bridge_watcher (positional Thorns/HP) → Witch-Shot;
	# lantern (quiet turn-1 Command) → The Burnt Dispatches.
	"vanguard_banner": {"id": "vanguard_banner", "name": "Third Card Banner", "tier": "combat",
		"desc": "After you play your 3rd card each turn, your creatures gain +1 ATK this round.",
		"hooks": ["creature_played"], "effect": "tally_stick", "value": 1},
	"rear_guard_charm": {"id": "rear_guard_charm", "name": "Rear Guard Charm", "tier": "combat",
		"desc": "When a front-row friendly dies: the back-row creature in its column gets +1/+1 this fight.",
		"hooks": ["creature_death"], "effect": "rear_guard_inherit", "value": 1},
	"phantom_veil": {"id": "phantom_veil", "name": "Phantom Veil", "tier": "combat",
		"desc": "Once per round: the first friendly that would die survives at 1 HP.",
		"hooks": ["creature_death"], "effect": "phantom_veil", "value": 1},
	"hexagonal_shield": {"id": "hexagonal_shield", "name": "Sniper Shield", "tier": "combat",
		"desc": "When an enemy Sniper attacks your back row: deal 3 damage to that Sniper.",
		"hooks": [], "effect": "pavise", "value": 3, "retired": true},

	# ═══════════════════════════════════════════
	#  UTILITY RELICS (5)
	# ═══════════════════════════════════════════
	"merchants_license": {"id": "merchants_license", "name": "Merchant's License", "tier": "utility",
		"desc": "Shop items cost 25% less.",
		"hooks": [], "effect": "shop_discount", "value": 25},
	"collectors_tome": {"id": "collectors_tome", "name": "Collector's Tome", "tier": "utility",
		"desc": "Take 2 cards at each Recruit Camp instead of 1.",
		"hooks": [], "effect": "double_reward_pick", "value": 0},
	"blacksmiths_hammer": {"id": "blacksmiths_hammer", "name": "Blacksmith's Hammer", "tier": "utility",
		"desc": "Forge upgrades give +3 instead of +2.",
		"hooks": [], "effect": "upgrade_bonus", "value": 0},
	# The marker is credit with the wagon, and since 2026-09-16 the wagon CHARGES
	# for removal instead of paying for cards — so the marker discounts the fee.
	# `value` is a PERCENTAGE, matching merchants_license beside it rather than
	# the old multiplier; Shop._removal_fee reads it.
	"scavengers_pouch": {"id": "scavengers_pouch", "name": "Trader's Marker", "tier": "utility",
		"desc": "Removing a card at the shop costs half as much.",
		"hooks": [], "effect": "removal_discount", "value": 50},
	"whetstone": {"id": "whetstone", "name": "Whetstone", "tier": "utility",
		"desc": "Once per act at a rest site: forge 2 cards instead of 1.",
		"hooks": [], "effect": "whetstone_reforge", "value": 2},

	# ═══════════════════════════════════════════
	#  RETIRED BOSS BARGAINS — preserved for old saves, never offered
	# ═══════════════════════════════════════════
	"cursed_key": {"id": "cursed_key", "name": "Cursed Key", "tier": "boss",
		"desc": "+1 max Command. Gain a Curse after every fight.",
		"hooks": ["combat_end"], "effect": "boss_mana", "value": 1,
		"downside": "curse_on_reward", "retired": true},
	"coffee_dripper": {"id": "coffee_dripper", "name": "Hairshirt", "tier": "boss",
		"desc": "+1 max Command. Can't heal at rest sites.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_rest_heal", "retired": true},
	"fusion_hammer": {"id": "fusion_hammer", "name": "Cracked Anvil", "tier": "boss",
		"desc": "+1 max Command. Can't forge cards at rest sites.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_upgrade", "retired": true},
	"ectoplasm": {"id": "ectoplasm", "name": "Vow of Poverty", "tier": "boss",
		"desc": "+1 max Command. Can't gain gold.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_gold", "retired": true},
	"busted_crown": {"id": "busted_crown", "name": "Tarnished Crown", "tier": "boss",
		"desc": "+1 max Command. Recruit camps show 2 choices instead of 3.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "fewer_rewards", "retired": true},
	"sozu": {"id": "sozu", "name": "Temperance Vow", "tier": "boss",
		"desc": "+1 max Command. Can't gain potions.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "no_potions", "retired": true},
	"philosophers_stone": {"id": "philosophers_stone", "name": "Philosopher's Stone", "tier": "boss",
		"desc": "+1 max Command. All enemies get +1 ATK.",
		"hooks": ["combat_start"], "effect": "boss_mana", "value": 1,
		"downside": "enemy_atk_buff", "retired": true},
	"velvet_choker": {"id": "velvet_choker", "name": "Penitent's Collar", "tier": "boss",
		"desc": "+1 max Command. Can only play 5 cards per turn.",
		"hooks": [], "effect": "boss_mana", "value": 1,
		"downside": "play_limit", "retired": true},
	"mark_of_pain": {"id": "mark_of_pain", "name": "Mark of Pain", "tier": "boss",
		"desc": "+1 max Command. Start each fight with 2 Curses in your draw pile.",
		"hooks": ["combat_start"], "effect": "boss_mana", "value": 1,
		"downside": "start_curses", "retired": true},

	# ═══════════════════════════════════════════
	#  MANA RELICS (regular, found in shops/events/rewards)
	# ═══════════════════════════════════════════
	"lantern": {"id": "lantern", "name": "The Burnt Dispatches", "tier": "combat",
		"desc": "First spell you Exhaust each turn: return a random spell from discard. It costs 0 this turn.",
		"hooks": ["spell_exhausted"], "effect": "burnt_dispatches", "value": 0},  # 2026-07-16 reshape — see note above vanguard_banner
	"happy_flower": {"id": "happy_flower", "name": "Saint's Posy", "tier": "combat",
		"desc": "Every 3rd turn, gain 1 Command.",
		"hooks": ["turn_start"], "effect": "happy_flower", "value": 1,
		"retired": true},  # 2026-07-08 merged → lantern (Command trickle). Also dropped from skirmish NET_RELIC_POOL.
	# 2026-07-25: was Miser's Coffer (uncapped Command banking) — retired because
	# Command is a FIXED resource and banking is the clearest violation of that.
	# Replaced in place (the id is load-bearing: FOUNDATION_RELICS, the rarity
	# map and skirmish's NET_RELIC_POOL all name it). Creature sustain was an
	# entirely empty niche — every other heal in this file heals the HERO — and
	# it reads honestly under the attrition model, where one extra point of HP
	# is often the difference between trading and holding the line.
	"ice_cream": {"id": "ice_cream", "name": "Iron Rations", "tier": "combat",
		"desc": "At the start of each round, each of your damaged creatures heals 1.",
		"hooks": ["turn_start"], "effect": "rations_heal", "value": 1},
	# 2026-09-16: was "your hand refills to 6 cards each turn instead of 5". There
	# is no refill any more — the economy redesign replaced draw-to-N with a fixed
	# per-turn draw, and this relic became a flat ADDER on that draw. The old text
	# named a number the game had stopped using, which is worse than vague: a
	# player reading "refills to 6" plans a hand size the relic no longer sets.
	"deep_satchel": {"id": "deep_satchel", "name": "Deep Satchel", "tier": "combat",
		"desc": "Draw 1 extra card each turn.",
		"hooks": ["turn_start"], "effect": "hand_refill_bonus", "value": 1},

	# ═══════════════════════════════════════════════════════════════════════
	#  ROUND 3 REDESIGN PASS — new relics from StS + Hades + Monster Train +
	#  Balatro + Wildfrost + Cobalt Core + Inscryption + Backpack Hero + AtO.
	#  Effect IDs are semantic; Combat.gd handlers added per relic as they ship.
	# ═══════════════════════════════════════════════════════════════════════

	# ─── Cost manipulation ───
	"mummified_hand": {"id": "mummified_hand", "name": "Withered Saint's Hand", "tier": "combat",
		"desc": "When you cast a spell: a random creature card in your hand costs 0 this turn.",
		"hooks": ["spell_played"], "effect": "mummified_hand", "value": 0},
	"sigil_of_hunger": {"id": "sigil_of_hunger", "name": "Sigil of Hunger", "tier": "combat",
		"desc": "After a friendly dies: the next creature you play costs 1 less. Once per round.",
		"hooks": ["creature_death"], "effect": "sigil_of_hunger", "value": 1},
	"tricksters_glove": {"id": "tricksters_glove", "name": "Trickster's Glove", "tier": "combat",
		"desc": "While your hand has at least 4 cards, all cards in it cost 1 less.",
		"hooks": [], "effect": "tricksters_glove", "value": 1,
		"retired": true},
	"pact_of_embers": {"id": "pact_of_embers", "name": "Pact of Embers", "tier": "combat",
		"desc": "Start of each turn: the highest-cost card in your hand costs 0 this turn.",
		"hooks": ["turn_start"], "effect": "pact_of_embers", "value": 0},
	"mana_tide": {"id": "mana_tide", "name": "War Chest", "tier": "combat",
		"desc": "When you bank Command: the next creature you play costs 1 less.",
		"hooks": ["mana_banked"], "effect": "mana_tide", "value": 1,
		"retired": true},  # 2026-07-08 merged → sigil_of_hunger ("next creature costs 1 less"). Also dropped from skirmish NET_RELIC_POOL.
	"last_breath": {"id": "last_breath", "name": "Last Breath", "tier": "combat",
		"desc": "Creatures with 1 base HP cost 1 less.",
		"hooks": [], "effect": "last_breath_discount", "value": 1, "retired": true},

	# ─── Hand / draw manipulation ───
	"toolbox": {"id": "toolbox", "name": "Quartermaster's Chest", "tier": "combat",
		"desc": "Start of each fight: choose 1 of 3 cards to add to your hand.",
		"hooks": ["combat_start"], "effect": "toolbox", "value": 3},
	"bottled_talisman": {"id": "bottled_talisman", "name": "Bottled Talisman", "tier": "combat",
		"desc": "Start each fight with a chosen card in your hand.",
		"hooks": ["combat_start"], "effect": "bottled_talisman", "value": 0},

	# ─── 4x4 lane / positional ───
	"phalanx_stone": {"id": "phalanx_stone", "name": "Phalanx Stone", "tier": "combat",
		"desc": "While all 4 front-row slots are full, friendlies have +1 ATK.",
		"hooks": [], "effect": "phalanx_full_front", "value": 1,
		"retired": true},  # 2026-07-08 merged → vanguard_banner (conditional flat front ATK)
	"cavalry_sigil": {"id": "cavalry_sigil", "name": "Cavalry Sigil", "tier": "combat",
		"desc": "Gain +1 Command each turn for each empty edge lane.",
		"hooks": ["turn_start"], "effect": "empty_edge_mana", "value": 1,
		"mana_cap_cost": 1, "retired": true},
	"sentinel_pact": {"id": "sentinel_pact", "name": "Sentinel Pact", "tier": "combat",
		"desc": "Empty lanes count as friendlies for your Adj. Buff effects.",
		"hooks": [], "effect": "empty_lanes_as_adj", "value": 0,
		"retired": true},
	"catapult_crew": {"id": "catapult_crew", "name": "Catapult Crew", "tier": "combat",
		"desc": "Your back-row creatures have Sniper.",
		"hooks": [], "effect": "back_row_ranged", "value": 0},
	"bridge_watcher": {"id": "bridge_watcher", "name": "Witch-Shot", "tier": "combat",
		"desc": "Your damage spells ignore Armored and Shield.",
		"hooks": [], "effect": "witch_shot", "value": 0},  # 2026-07-16 reshape — see note above vanguard_banner
	"spotters_glass": {"id": "spotters_glass", "name": "Spotter's Glass", "tier": "combat",
		"desc": "When you play a creature in an empty column: friendlies in that column gain +1 ATK.",
		"hooks": ["creature_played"], "effect": "empty_column_atk", "value": 1,
		"retired": true},  # 2026-07-08 merged → banner_of_unity (per-placement ATK payoff)
	"flanking_banner": {"id": "flanking_banner", "name": "Flanking Banner", "tier": "combat",
		"desc": "End of each round: if 3 front-row slots are full, enemies in the empty column take 2 damage.",
		"hooks": ["round_end"], "effect": "flank_damage", "value": 2},

	# ─── Combat-start setups ───
	"bag_of_marbles": {"id": "bag_of_marbles", "name": "Bag of Marbles", "tier": "combat",
		"desc": "Start of each fight: deal 1 damage to all enemies.",
		"hooks": ["combat_start"], "effect": "marbles_aoe", "value": 1, "retired": true},
	"champions_belt": {"id": "champions_belt", "name": "Champion's Belt", "tier": "combat",
		"desc": "On turn 1 of each fight: friendlies have +1 ATK.",
		"hooks": ["combat_start"], "effect": "champions_belt", "value": 1,
		"retired": true},  # 2026-07-08 merged → vanguard_banner (flat front-row +1 ATK, always on)
	"war_drum": {"id": "war_drum", "name": "War Drum", "tier": "combat",
		"desc": "Start of each fight: play a random creature from your deck in lane 1.",
		"hooks": ["combat_start"], "effect": "war_drum_spawn", "value": 0},
	"witchs_brew": {"id": "witchs_brew", "name": "Witch's Brew", "tier": "combat",
		"desc": "Start of each fight: cast a random spell from your deck for free. Targets are chosen automatically.",
		"hooks": ["combat_start"], "effect": "witchs_brew", "value": 0,
		"retired": true},

	# ─── Conditional / Balatro-style scaling ───
	"spell_tome": {"id": "spell_tome", "name": "Spell Tome", "tier": "combat",
		"desc": "If 50%+ of your deck is spells: all spells cost 1 less.",
		"hooks": [], "effect": "spell_tome_discount", "value": 1},
	"iron_legion": {"id": "iron_legion", "name": "Iron Legion", "tier": "combat",
		"desc": "If 60%+ of your deck is creatures: friendlies have +1 HP.",
		"hooks": ["creature_played"], "effect": "iron_legion_buff", "value": 1, "retired": true},
	"tome_of_many": {"id": "tome_of_many", "name": "Tome of Many", "tier": "combat",
		"desc": "If your deck has 20+ cards: draw 2 extra per turn.",
		"hooks": ["turn_start"], "effect": "big_deck_draw", "value": 2,
		"retired": true},
	# 2026-07-25: was a spend-streak "+1 max Command this fight" — retired with the
	# rest of the Command-manufacturing relics. The name already meant "arrive
	# ready to fight", so it now answers the muster delay instead: granting Swift
	# reuses the existing keyword machinery whole, which matters because Swift is
	# ALSO the keyword barred from reaching the face on its arrival round — the
	# relic inherits that guard for free rather than opening a burst-finisher hole.
	"mana_drunkard": {"id": "mana_drunkard", "name": "Forced March", "tier": "combat",
		"desc": "The first creature you play each round gains Swift.",
		"hooks": ["creature_played"], "effect": "first_creature_swift", "value": 0},

	# ─── Sacrifice / death deepening ───
	"reapers_scythe": {"id": "reapers_scythe", "name": "Reaper's Scythe", "tier": "combat",
		"desc": "When you sacrifice a creature with an On-Enter effect, the next creature you play also triggers that effect.",
		"hooks": ["sacrifice"], "effect": "reapers_scythe", "value": 0},
	"du_vu_doll": {"id": "du_vu_doll", "name": "Maledetto Poppet", "tier": "combat",
		"desc": "When you draw a Curse: prevent its on-draw effect and deal 2 damage to a random enemy creature.",
		"hooks": ["card_drawn"], "effect": "curse_poppet", "value": 2},
	"soul_ledger": {"id": "soul_ledger", "name": "Soul Ledger", "tier": "combat",
		"desc": "Every 5th friendly death this run: summon a 4/4 token in a random empty lane.",
		"hooks": ["creature_death"], "effect": "soul_ledger", "value": 5},

	# ─── Spell deepening ───
	"reagent_pouch": {"id": "reagent_pouch", "name": "Reagent Pouch", "tier": "combat",
		"desc": "Your first spell each fight is Sharpened (+2 spell damage).",
		"hooks": ["spell_played"], "effect": "reagent_pouch", "value": 2,
		"retired": true},
	"inkpot_of_many": {"id": "inkpot_of_many", "name": "Inkpot of Many", "tier": "combat",
		"desc": "Every 5th spell you cast: add a random spell to your hand.",
		"hooks": ["spell_played"], "effect": "inkpot", "value": 5},
	"mana_pearl": {"id": "mana_pearl", "name": "Knife Up the Sleeve", "tier": "combat",
		"desc": "Your 0-cost spells deal +1 damage.",
		"hooks": ["spell_damage"], "effect": "zero_cost_spell_bonus", "value": 1, "retired": true},

	# ─── Build-around scaling ───
	"pen_nib": {"id": "pen_nib", "name": "Pen Nib", "tier": "combat",
		"desc": "Every 10th card you play: the leftmost creature in your hand becomes 6/6 and gains Piercing this fight.",
		"hooks": ["card_played"], "effect": "pen_nib", "value": 10},
	"wormwood": {"id": "wormwood", "name": "Wormwood", "tier": "combat",
		"desc": "When a friendly Bastion survives a hit: it gains +1 ATK this fight (max +5 per creature).",
		"hooks": ["creature_damaged"], "effect": "wormwood", "value": 5},

	# ─── Hades imports (boon/keepsake-flavored) ───
	"stygian_soul": {"id": "stygian_soul", "name": "Stygian Soul", "tier": "combat",
		"desc": "When an enemy dies: heal 1 HP. Max 5 per fight.",
		"hooks": ["enemy_death"], "effect": "heal_on_kill", "value": 5},
	"bone_hourglass": {"id": "bone_hourglass", "name": "Bone Hourglass", "tier": "combat",
		"desc": "At each act's start, choose: front row +1 ATK; back row +1 HP; or +1 max Command while both center lanes are full.",
		"hooks": ["act_start"], "effect": "bone_hourglass", "value": 0},

	# ─── Monster Train imports ───
	"pyre_stoker": {"id": "pyre_stoker", "name": "Pyre Stoker", "tier": "combat",
		"desc": "After you play at least 3 cards this turn, deal +1 face damage.",
		"hooks": ["face_damage_dealt"], "effect": "pyre_stoker", "value": 1},
	"imp_generator": {"id": "imp_generator", "name": "Imp Generator", "tier": "combat",
		"desc": "End of each round: summon a 1/1 Imp token in a random empty back-row lane.",
		"hooks": ["round_end"], "effect": "imp_generator", "value": 0},

	# ─── Balatro imports (conditional copy/scaling) ───
	"blueprint": {"id": "blueprint", "name": "Mason's Tracing", "tier": "combat",
		"desc": "Each creature you play copies the On-Enter effect of the previous creature you played this fight.",
		"hooks": ["creature_played"], "effect": "blueprint", "value": 0},
	"brainstorm": {"id": "brainstorm", "name": "Drillmaster's Whistle", "tier": "combat",
		"desc": "The first creature you play each round copies the keywords of the first creature you played this fight.",
		"hooks": ["creature_played"], "effect": "brainstorm", "value": 0,
		"retired": true},  # 2026-07-08 merged → mimic_ring (keyword copy onto a creature)
	"mime": {"id": "mime", "name": "Mummer's Mask", "tier": "combat",
		"desc": "End of each turn: play 1 chosen card from your hand for free.",
		"hooks": ["turn_end"], "effect": "mime", "value": 0,
		"retired": true},
	"the_family": {"id": "the_family", "name": "Sharpened Pitchforks", "tier": "combat",
		"desc": "Your 1/1 tokens are summoned as 2/1.",
		"hooks": [], "effect": "token_pitchforks", "value": 1},

	# ─── Wildfrost imports ───
	"junk_slot": {"id": "junk_slot", "name": "Open Ground", "tier": "combat",
		"desc": "If you have 4+ empty board slots: +1 max Command.",
		"hooks": [], "effect": "junk_slot_mana", "value": 1,
		"mana_cap_cost": 1, "retired": true},

	# ─── Inscryption imports ───
	"totem_pole": {"id": "totem_pole", "name": "Totem Pole", "tier": "combat",
		"desc": "Each act, choose Thorns, Swift, Regenerate, or Armored. All friendlies gain that keyword for the act.",
		"hooks": ["act_start"], "effect": "totem_pole", "value": 0},
	"death_card": {"id": "death_card", "name": "Death Card", "tier": "combat",
		"desc": "When a friendly dies, return it to your hand. It costs 1 more each time this happens.",
		"hooks": ["creature_death"], "effect": "death_card", "value": 1},

	# ─── Backpack Hero imports (4x4 adjacency variants) ───
	"linked_banner": {"id": "linked_banner", "name": "Linked Banner", "tier": "combat",
		"desc": "Friendlies with 2+ adjacent friendlies have +1 ATK and +1 HP.",
		"hooks": [], "effect": "linked_adj", "value": 1, "retired": true},
	"diagonal_crest": {"id": "diagonal_crest", "name": "Diagonal Crest", "tier": "combat",
		"desc": "Diagonal friendlies count as adjacent. Your Adj. Buff effects grant +1 extra HP.",
		"hooks": [], "effect": "diagonal_adj", "value": 1,
		"retired": true},
	"corner_stone": {"id": "corner_stone", "name": "Corner Stone", "tier": "combat",
		"desc": "Friendlies in lane 1 or lane 4 have Thorns 2.",
		"hooks": [], "effect": "corner_thorns", "value": 2,
		"retired": true},  # 2026-07-08 merged → bridge_watcher (positional Thorns granter)

	# ═══════════════════════════════════════════════════════════════════════
	#  CLASS-RESTRICTED COMBAT RELICS (4) — only offered to matching hero.
	#  Filter applied in filter_pool_for_run() via the restricted_to field.
	# ═══════════════════════════════════════════════════════════════════════
	"raiders_oath": {"id": "raiders_oath", "name": "Raider's Oath", "tier": "combat",
		"desc": "Raider only. When you play a creature with Swift: gain 1 Command this turn.",
		"hooks": ["creature_played"], "effect": "swift_mana", "value": 1,
		"restricted_to": "raider"},
	"stalwarts_anvil": {"id": "stalwarts_anvil", "name": "Stalwart's Anvil", "tier": "combat",
		"desc": "Stalwart only. The first time a friendly takes damage each round: gain 1 Command next turn.",
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
		"desc": "After you defeat a General: forge a random card in your deck for free.",
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
		"desc": "The first time a friendly dies each round: your next creature gets +1/+1 this fight.",
		"hooks": ["creature_death", "creature_played"], "effect": "fallen_verse", "value": 1},
	"warm_knucklebone": {"id": "warm_knucklebone", "name": "Warm Knucklebone", "tier": "event",
		"desc": "Start of each turn: 1 in 6 chance to gain 1 Command.",
		"hooks": ["turn_start"], "effect": "chance_bonus_mana", "value": 1},
	"sin_eaters_crust": {"id": "sin_eaters_crust", "name": "The Sin-Eater's Crust", "tier": "event",
		"desc": "Whenever a card leaves your deck: heal 3 HP.",
		"hooks": [], "effect": "heal_on_card_removed", "value": 3},

	# ═══════════════════════════════════════════════════════════════════════
	#  SET-PIECE TROPHIES (2026-07-20) — tier "event" so they never enter any
	#  roll pool; each is granted BY NAME on the field the moment its named
	#  action is carried (SetPieceDB `trophy`). One trophy per set-piece, so
	#  a player who never reroutes for a named action never sees one — which
	#  is the point: these are the reason to take the harder road.
	# ═══════════════════════════════════════════════════════════════════════
	"sunken_road_stone": {"id": "sunken_road_stone", "name": "The Sunken Road Stone", "tier": "event",
		"desc": "The first creature you play each round gains Armored.",
		"hooks": ["creature_played"], "effect": "first_played_armored", "value": 1},
	"paymasters_tally": {"id": "paymasters_tally", "name": "Paymaster's Coin", "tier": "event",
		"desc": "At the start of every fight: gain 12 gold.",
		"hooks": ["combat_start"], "effect": "gold_on_combat_start", "value": 12},
	"eagle_of_the_fourth": {"id": "eagle_of_the_fourth", "name": "The Eagle of the Fourth", "tier": "event",
		"desc": "The first friendly creature that dies each fight returns as a 1/1.",
		"hooks": ["creature_death"], "effect": "first_fallen_rises", "value": 1},

	# ═══════════════════════════════════════════════════════════════════════
	#  BOSS RELICS — Round 3 additions (9) — run-warping, no +1-mana template.
	#  These replace the "all boss relics are +1 mana with downside" monotony.
	# ═══════════════════════════════════════════════════════════════════════
	"pandoras_box": {"id": "pandoras_box", "name": "The Conjurer's Coffer", "tier": "boss",
		"desc": "Transform all starting creatures into random rares. If none remain, gain a random rare creature.",
		"hooks": [], "effect": "pandoras_box", "value": 0},
	# Campaign-retired, but STILL LIVE IN SKIRMISH — SkirmishState.NET_RELIC_POOL
	# is an explicit allow-list and does not consult `retired`, so this text is
	# read by a player on the arsenal stage and this roll decides real costs.
	#
	# 2026-09-16: the roll was 0-3, chosen against a curve where 86% of the pool
	# cost 2 or less. Under the rescaled 1-6 curve that same roll is not chaos,
	# it is a blanket discount — and its floor of 0 hands out free cards, which a
	# ramping resource cannot price at all ("cost N is first affordable on round
	# N" has no round for 0). 1-5 restores the relic's actual character: a mean
	# just under the pool's own, so it is a gamble with a small edge rather than
	# a sale. THE RANGE LIVES HERE because three sites roll it — Combat and
	# NetPlayerState twice — and a magnitude restated three times is the drift
	# this file's own header warns about.
	"snecko_eye": {"id": "snecko_eye", "name": "Basilisk Eye", "tier": "boss",
		"desc": "Draw 1 extra card each turn. At the start of each turn, every card's cost becomes a fresh roll of 1 to 5.",
		"hooks": ["turn_start"], "effect": "snecko_eye", "value": 1,
		"cost_lo": 1, "cost_hi": 5,
		"retired": true},
	"calling_bell": {"id": "calling_bell", "name": "Calling Bell", "tier": "boss",
		"desc": "Gain 3 boss relics. Add 3 Curses to your deck.",
		"hooks": [], "effect": "calling_bell", "value": 3, "retired": true},
	"runic_pyramid": {"id": "runic_pyramid", "name": "Runic Pyramid", "tier": "boss",
		"desc": "Keep your hand at the end of each turn.",
		"hooks": [], "effect": "no_end_turn_discard", "value": 0,
		"retired": true},
	"lichs_bargain": {"id": "lichs_bargain", "name": "Lich's Bargain", "tier": "boss",
		"desc": "Friendly On-Death effects trigger twice. After each fight, lose 1 HP per friendly death (max 3 HP).",
		"hooks": ["creature_death", "combat_end"], "effect": "lichs_bargain", "value": 2,
		"retired": true},
	"lean_mean": {"id": "lean_mean", "name": "Lean Company", "tier": "boss",
		"desc": "+1 max Command while your deck has 14 or fewer cards.",
		"hooks": [], "effect": "lean_mean", "value": 1},
	"glowing_hand": {"id": "glowing_hand", "name": "Glowing Hand", "tier": "boss",
		"desc": "Your damage spells deal +1 per spell already cast this fight (max +5).",
		"hooks": ["spell_damage"], "effect": "glowing_hand", "value": 5},
	# Campaign-retired, skirmish-live (see Basilisk Eye above).
	#
	# 2026-09-16: the old text sold a RAMP — "start each fight with 1 Command,
	# gain 2 per round" — which was the trade for +2 max back when everyone else
	# opened on a flat 3. The economy redesign made that ramp the baseline, so
	# two thirds of this card's printed downside evaporated and the remaining
	# sentence described the house rules rather than the relic. What the code
	# actually does is unchanged and still worth a boss slot: +2 to the ceiling,
	# and round 1 is held to its lone Command so the bonus starts paying on
	# round 2.
	"marathoners_sash": {"id": "marathoners_sash", "name": "Marathoner's Sash", "tier": "boss",
		"desc": "+2 max Command, but your first round is still a single Command.",
		"hooks": ["combat_start", "turn_start"], "effect": "marathoners_sash", "value": 2,
		"retired": true},
	"steady_banner": {"id": "steady_banner", "name": "Steady Banner", "tier": "boss",
		"desc": "Friendlies start turn 1 with -1 ATK. After each full round they survive, they gain +2 ATK for the fight.",
		"hooks": ["round_end", "creature_played"], "effect": "steady_banner", "value": 2,
		"retired": true},

	# ═══════════════════════════════════════════════════════════════════════
	#  WAVE 2 — keyword-synergy + build-defining relics (Doom / Rampage /
	#  Lifelink payoffs, plus board-buff / spell / armor / on-death engines).
	#  Implemented inline in Combat.gd at the noted hook points.
	# ═══════════════════════════════════════════════════════════════════════

	# ─── Doom synergy ───
	"doom_herald": {"id": "doom_herald", "name": "Doom Herald", "tier": "combat",
		"desc": "When one of your Doom creatures detonates: draw 1.",
		"hooks": ["doom_detonate"], "effect": "doom_detonate_draw", "value": 1,
		"retired": true},
	"hourglass_of_ruin": {"id": "hourglass_of_ruin", "name": "Hourglass of Ruin", "tier": "boss",
		"desc": "Your Doom creatures detonate 1 round sooner.",
		"hooks": ["creature_played"], "effect": "doom_accelerate", "value": 1},

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

	# ═══════════════════════════════════════════════════════════════════════
	#  2026-07-07 POOL CUT + FUN SLATE — 14 dead/no-decision relics removed
	#  (never-firing counters, invisible "+1 to a keyword" taxes, gold
	#  trickles), 5 reshaped in place (same ids — saves/collections stay
	#  valid), and these 6 added. Each one lights up a live system that had
	#  zero relic support: veterancy, discards, repositioning, potions,
	#  reinforcements, gold-in-combat.
	# ═══════════════════════════════════════════════════════════════════════
	"letters_patent": {"id": "letters_patent", "name": "Letters Patent", "tier": "combat",
		"desc": "When a friendly earns its epithet at 3 kills, it permanently gains +1/+1.",
		"hooks": ["creature_death"], "effect": "epithet_knight", "value": 1},
	"deserters_toll": {"id": "deserters_toll", "name": "Deserter's Toll", "tier": "combat",
		"desc": "The first card you discard each turn deals damage equal to its Command cost to a random enemy creature.",
		"hooks": ["turn_end"], "effect": "discard_toll", "value": 0},
	"drovers_whip": {"id": "drovers_whip", "name": "Drover's Whip", "tier": "combat",
		"desc": "When you move a creature: it gains +1 ATK this round.",
		"hooks": [], "effect": "move_atk", "value": 1},
	"dregs": {"id": "dregs", "name": "Dregs", "tier": "combat",
		"desc": "After you drink a potion in a fight: deal 2 damage to a random enemy creature.",
		"hooks": [], "effect": "potion_bottle", "value": 2},
	"poisoned_rations": {"id": "poisoned_rations", "name": "Poisoned Rations", "tier": "combat",
		"desc": "The first enemy reinforcement each fight dies when placed. Its On-Death effect still triggers.",
		"hooks": [], "effect": "reinforcement_dies", "value": 0},
	"sellswords_retainer": {"id": "sellswords_retainer", "name": "Sellsword's Retainer", "tier": "combat",
		"desc": "Fight start: with at least 150 gold, summon a 3/3 Sellsword in back. If it survives, lose 10 gold.",
		"hooks": ["combat_start", "combat_end"], "effect": "sellsword", "value": 150},

	# 2026-07-16 final structural slate. These are deliberately simple, positive
	# permanents: each either changes a recurring combat decision or makes the
	# campaign's existing memory / route systems matter. Offer eligibility is
	# centralized below so none can appear before it has a live constituency.
	"heads_on_pikes": {"id": "heads_on_pikes", "name": "Heads on Pikes", "tier": "combat",
		"desc": "Start of each fight: the highest-ATK enemy gets -1 ATK this fight for each General defeated this run (max -3).",
		"hooks": ["combat_start"], "effect": "general_fear", "value": 3},
	# 2026-09-16: was "Banking Command adds 1 powder charge". Carryover became a
	# RELIC that round (see field_chest), so this relic's trigger silently became
	# "only if you also hold that one" — a reward that does nothing on its own is
	# the dead-reward class, and it would have shipped invisible because nothing
	# here asserts that a hook has a live constituency. Re-keyed to the fact that
	# was doing the work anyway: ENDING a turn with Command still on the seal.
	# Same moment, same shape, no dependency — and it reads better besides, since
	# powder left in the horn is exactly what unspent Command is.
	"powder_horn": {"id": "powder_horn", "name": "Powder Horn", "tier": "combat",
		"desc": "Unspent Command at turn's end: gain 1 powder charge (max 3). Your next damage spell spends them, +2 damage each.",
		"hooks": ["turn_end", "spell_damage"], "effect": "powder_charges", "value": 2},
	# ── THE ONLY CARRYOVER IN THE GAME (2026-09-16) ──────────────────────────
	# Command does not bank by default any more. It is a per-round allowance:
	# what you do not spend is gone, which is what makes the ramp a real cost
	# curve rather than a savings account you can skip a turn to fill.
	#
	# This is the SECOND reversal on the same question and the reasoning is worth
	# keeping so it is not reversed a third time by accident. Miser's Coffer
	# (uncapped banking) was retired 2026-07-25 on the grounds that "Command is a
	# FIXED resource and banking is the clearest violation of that" — but the
	# UNIVERSAL 2-point bank was left standing, so the rule that retired the relic
	# was never applied to the rule itself. It is now: the default is zero, and
	# carryover is a thing you choose to hold a relic slot for.
	#
	# Capped by Combat.MAX_BANKED_MANA, which is deliberately still the authority
	# on HOW MUCH — this entry is the GATE. One number, two implementations
	# (Combat + NetPlayerState) plus the wire fingerprint read it, and a relic
	# `value` that could outrun it is how those three part company.
	"field_chest": {"id": "field_chest", "name": "The Field Chest", "tier": "combat",
		"desc": "Unspent Command carries into your next turn, up to 2.",
		"hooks": ["turn_start"], "effect": "command_carryover", "value": 2},
	"familiars_quill": {"id": "familiars_quill", "name": "The Familiar's Quill", "tier": "combat",
		"desc": "When you play a Warlock: your next spell this turn costs 1 less.",
		"hooks": ["creature_played"], "effect": "warlock_spell_discount", "value": 1},
	"head_money": {"id": "head_money", "name": "Head-Money", "tier": "combat",
		"desc": "When a Stray kills an enemy creature: gain gold equal to its printed Command cost (max 10 gold per fight).",
		"hooks": ["creature_kill"], "effect": "stray_bounty", "value": 10},
	"old_meg": {"id": "old_meg", "name": "Old Meg", "tier": "combat",
		"desc": "Once per round, a targeted damage spell also deals 2 to the other enemy in that column, or face if empty.",
		"hooks": ["spell_damage"], "effect": "column_bombard", "value": 2},
	"portcullis": {"id": "portcullis", "name": "The Portcullis", "tier": "combat",
		"desc": "Once per round, while a friendly Bastion is in play, prevent the first 2 face damage you would take.",
		"hooks": ["hero_damaged"], "effect": "bastion_face_guard", "value": 2},
	"second_rank": {"id": "second_rank", "name": "The Second Rank", "tier": "combat",
		"desc": "When you play a Soldier directly behind another Soldier: both gain +1/+1 this fight.",
		"hooks": ["creature_played"], "effect": "soldier_column_drill", "value": 1},
	"sextons_spade": {"id": "sextons_spade", "name": "The Sexton's Spade", "tier": "combat",
		"desc": "The first friendly Doom creature to detonate each fight detonates twice.",
		"hooks": ["doom_detonate"], "effect": "double_first_doom", "value": 1},
	"forlorn_hope": {"id": "forlorn_hope", "name": "Forlorn Hope", "tier": "combat",
		"desc": "Your first creature each fight gains +1 ATK. Against a General or lord, it gains +2 ATK and Swift this round.",
		"hooks": ["creature_played"], "effect": "storming_party", "value": 1},
	"cerecloth": {"id": "cerecloth", "name": "The Cerecloth", "tier": "combat",
		"desc": "Your first creature each fight copies the newest fallen creature's printed keywords. If none, it gains +1/+1.",
		"hooks": ["creature_played"], "effect": "wear_last_shroud", "value": 1},
	"drill_book": {"id": "drill_book", "name": "The Drill Book", "tier": "utility",
		"desc": "Your creatures earn their name and war school at 2 kills instead of 3, and their tribe doctrine at 7 instead of 10.",
		"hooks": [], "effect": "faster_veterancy", "value": 0},
	"articles_of_war": {"id": "articles_of_war", "name": "The Articles of War", "tier": "boss",
		"desc": "Choose a tribe. Its creatures cost 1 less (minimum 1).",
		"hooks": [], "effect": "tribe_discount", "value": 1},
}


# ═══════════════════════════════════════════════════════════════════════════
#  COMBAT-RELIC RARITY (2026-07-08) — weights the reward roll so the pool has a
#  power curve instead of a coin-flip. Reliable workhorses are common and show
#  often; archetype-definers are uncommon; run-warping / uncapped-snowball
#  engines are rare and surface only occasionally. Balance rule: an outlier is
#  tamed by making it RARE, not by shaving its numbers. Any id NOT listed here
#  weighs as "common" (so boss/utility/event pools, which have no entries here,
#  roll uniformly — identical to the old shuffle).
# ═══════════════════════════════════════════════════════════════════════════
const RELIC_RARITY: Dictionary = {
	# ── RARE: build-defining or uncapped snowball engines. Exciting to find,
	#    deliberately scarce so they no longer dominate the roll. ──
	"echo_staff": "rare",          # On-Enter effects trigger twice — universal doubler
	"catapult_crew": "rare",       # repeating back-row snipe = a free board-clear engine
	"warlords_standard": "rare",   # uncapped permanent front-row ATK ramp
	"wormwood": "rare",            # permanent ATK on every hit taken
	"runebound_idol": "rare",      # permanent +1/+1 on every spell cast
	"toolbox": "rare",             # choose 1 of 3 extra cards = card selection every fight
	"totem_pole": "rare",          # board-wide keyword for the whole act
	"phoenix_heart": "rare",       # once-per-run cheat-death
	"pen_nib": "rare",             # spawns a 6/6 Piercing on a card-count engine
	"bone_hourglass": "rare",      # flexible per-act board buff
	"old_meg": "rare", "sextons_spade": "rare", "cerecloth": "rare",

	# ── UNCOMMON: strong, archetype-defining, but not run-warping. ──
	"banner_of_unity": "uncommon", "linked_banner": "uncommon",
	"butchers_cleaver": "uncommon", "bone_pile": "uncommon", "reapers_scythe": "uncommon",
	"mimic_ring": "uncommon", "blueprint": "uncommon", "resonance_crystal": "uncommon",
	"ice_cream": "uncommon", "deep_satchel": "uncommon",
	"mummified_hand": "uncommon", "sigil_of_hunger": "uncommon", "pact_of_embers": "uncommon",
	"cavalry_sigil": "uncommon", "mana_drunkard": "uncommon",
	"soul_ledger": "uncommon", "inkpot_of_many": "uncommon", "imp_generator": "uncommon",
	"war_drum": "uncommon", "flanking_banner": "uncommon", "death_card": "uncommon",
	"vanguard_banner": "uncommon", "lantern": "uncommon",  # 2026-07-16 Wave-2 reshapes
	"bulwark_engine": "uncommon", "phantom_veil": "uncommon", "thiefs_gloves": "uncommon",
	"bridge_watcher": "uncommon", "swift_boots": "uncommon", "du_vu_doll": "uncommon",
	"sellswords_retainer": "uncommon", "bottled_talisman": "uncommon",
	"heads_on_pikes": "uncommon", "powder_horn": "uncommon",
	"field_chest": "uncommon",
	"familiars_quill": "uncommon", "head_money": "uncommon",
	"portcullis": "uncommon", "second_rank": "uncommon", "forlorn_hope": "uncommon",
	"drill_book": "rare",
}

# Draw weights for the rarity-tiered roll. The SHAPE (common ≫ uncommon > rare)
# is the balance lever, not the exact integers — tune here, one place.
const RARITY_WEIGHT: Dictionary = {"common": 6, "uncommon": 3, "rare": 1}


static func get_relic_rarity(id: String) -> String:
	return RELIC_RARITY.get(id, "common")


static var _icon_cache: Dictionary = {}
static var _painted_icon_cache: Dictionary = {}


static func clear_icon_cache() -> void:
	_icon_cache.clear()
	_painted_icon_cache.clear()


static func get_relic(id: String) -> Dictionary:
	if RELICS.has(id):
		return RELICS[id]
	push_warning("RelicDB: unknown relic id '%s'" % id)
	return {}


## STAND-IN ICONS — the relic half of AudioBank's SFX_FALLBACKS, and the same
## deal the event pool already makes with its `"art"` stand-ins: ship a near
## neighbour rather than a hole, and let the bespoke file win automatically the
## day it lands (a real `<id>.png`/`.svg` is checked FIRST in get_relic_icon, so
## dropping the art in is the whole install — no edit here required, and this
## entry can then just be deleted).
##
## These 25 relics had no art at all. That is not a crash — get_relic_icon
## returned null and GameTheme.gd's chip builder null-guards it — but it drew a
## ringed chip with an empty middle in the HUD rail, the Shop shelf and the
## Reward tile, which reads as a broken slot rather than a relic.
##
## Every pairing below is chosen for what the relic DOES, not merely for a word
## in its name, because a mismatched icon misinforms worse than a blank one:
## Chain Censer takes the censer, Cinder Crown the ember crown, the Familiar's
## Quill the pen nib, Marching Spurs the swift boots, the Second Rank the phalanx
## stone. Where two relics wanted the same picture the closer claim won and the
## other took its next-best (Head-Money the purse, Paymaster's Coin the coin).
const ICON_FALLBACKS: Dictionary = {
	"articles_of_war": "conscription_relic",   # a written code that levies a tribe
	"centurions_rule": "veterans_medal",       # the line that survives a hit hardens
	"cerecloth": "phantom_veil",               # a burial shroud, wearing the dead's traits
	"chain_censer": "ember_censer",            # literally a censer
	"cinder_crown": "ember_crown",             # literally an ember crown
	"drill_book": "blueprint",                 # a manual of instruction
	"eagle_of_the_fourth": "iron_legion",      # the Fourth's own standard
	"familiars_quill": "pen_nib",              # literally a quill
	# A BOX, NOT A PURSE. coin_purse was the first pick and it misinforms: gold
	# and Command are different currencies and this game keeps them apart, so a
	# purse on a Command relic says "money" to every player who reads an icon
	# before a line of text. The latched case is the honest near neighbour.
	"field_chest": "toolbox",                  # a latched case: what you did not spend, kept
	"forlorn_hope": "vanguards_cry",           # the first man over the wall
	"funeral_lantern": "soul_lantern",         # a lantern for the dead
	"head_money": "coin_purse",                # a bounty paid per head
	"heads_on_pikes": "mark_of_pain",          # a trophy that cows the enemy
	"ledger_seal": "soul_ledger",              # literally a ledger
	"marching_spurs": "swift_boots",           # movement into Swift
	"mirror_primer": "mimic_ring",             # doubling / echoing spells
	"old_meg": "catapult_crew",                # a named siege gun
	"paymasters_tally": "gamblers_coin",       # the paymaster's coin
	"portcullis": "bulwark_engine",            # a gate that stops what comes in
	"powder_horn": "war_horn",                 # a horn that carries a charge
	"rearward_horn": "rear_guard_charm",       # the back row's own device
	"reserve_standard": "steady_banner",       # a standard held in reserve
	"second_rank": "phalanx_stone",            # soldier behind soldier, in formation
	"sextons_spade": "gravewardens_pact",      # the gravedigger's office
	"sunken_road_stone": "corner_stone",       # a stone that armours the line
	"war_bellows": "pyre_stoker",              # bellows feeding a fire
}


# Returns the texture for a relic icon, or null if none is installed for that
# id. Stored in `assets/icons/relics/<id>.{png,svg}` — PNG wins so painted
# Hades/StS-style art transparently replaces the legacy SVG silhouettes.
# Both are convention-based so RelicDB entries don't need an explicit path.
# An explicit `"icon"` on the entry wins over the id; ICON_FALLBACKS above is
# the last resort, so bespoke art always beats a stand-in.
static func _resolve_icon_id(id: String) -> String:
	var icon_id := String(RELICS[id].get("icon", id)) if RELICS.has(id) else id
	if ResourceLoader.exists("res://assets/icons/relics/%s.png" % icon_id) \
			or ResourceLoader.exists("res://assets/icons/relics/%s.svg" % icon_id):
		return icon_id
	return String(ICON_FALLBACKS.get(icon_id, icon_id))


static func get_relic_icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var icon_id := _resolve_icon_id(id)
	var png_path := "res://assets/icons/relics/%s.png" % icon_id
	if ResourceLoader.exists(png_path):
		_icon_cache[id] = load(png_path) as Texture2D
		return _icon_cache[id]
	var svg_path := "res://assets/icons/relics/%s.svg" % icon_id
	if ResourceLoader.exists(svg_path):
		_icon_cache[id] = load(svg_path) as Texture2D
		return _icon_cache[id]
	_icon_cache[id] = null
	return _icon_cache[id]


# True when the relic has a painted PNG icon — used by frame builders to skip
# the gilt-tint they apply to monochrome SVG silhouettes (which would otherwise
# wreck a full-color painting).
static func is_painted_icon(id: String) -> bool:
	if not _painted_icon_cache.has(id):
		# Must resolve the SAME id get_relic_icon settled on, or a relic wearing a
		# painted stand-in would be treated as a monochrome silhouette and get the
		# gilt tint applied over full-colour art (the exact thing this flag exists
		# to prevent).
		var icon_id := _resolve_icon_id(id)
		_painted_icon_cache[id] = ResourceLoader.exists("res://assets/icons/relics/%s.png" % icon_id)
	return bool(_painted_icon_cache[id])


# Tier accent color for the relic frame's glow halo — at-a-glance rarity cue
# like WoW item quality. Boss relics shine purple, utility green, combat
# warm bronze, starting gold.
## Tier accents. These ride every relic chip — the shop shelf, the Collection
## tiles, the combat rail, the reward slate — so they have to be five distinct
## inks that still live in the sepia world.
##
## Three of the five already did (gilt / ember / verdigris) and two were
## leftover neon: utility read as a web-green and boss as a screen magenta,
## which made them the only digital colours on the shelf. Both are now muted
## into the family at the same value the event tier was already pulled to,
## keeping the hue that carries their identity — utility still reads green,
## boss still reads violet — without the saturation. (Audit 2026-07-21.)
const TIER_COLORS := {
	"starting": Color(1.00, 0.85, 0.45, 1.0),
	"combat":   Color(0.95, 0.55, 0.30, 1.0),
	"utility":  Color(0.62, 0.78, 0.50, 1.0),  # sage — kept clear of event verdigris
	"boss":     Color(0.74, 0.54, 0.86, 1.0),  # muted amethyst
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


const FOUNDATION_RELICS: Array[String] = [
	"vanguards_cry", "banner_of_unity", "piercing_crown", "phoenix_heart",
	"rear_guard_charm", "phantom_veil", "lantern", "ice_cream",
	"deep_satchel", "vanguard_banner", "forlorn_hope",
]


static func roll_foundation_relics(count: int = 1, relics_held: Array[String] = [],
		hero_id: String = "", rng: RandomNumberGenerator = null) -> Array[String]:
	var pool: Array[String] = filter_pool_for_run(FOUNDATION_RELICS, hero_id, relics_held)
	return weighted_sample(pool, mini(count, pool.size()), rng)


static func roll_field_relics(count: int = 3, relics_held: Array[String] = [],
		hero_id: String = "") -> Array[String]:
	var pool: Array[String] = filter_pool_for_run(
		get_relics_by_tier("combat"), hero_id, relics_held)
	var picks: Array[String] = []
	# The first relic after the signature teaches the baseline grammar before
	# the pool asks for a niche engine. General offers still have a second slot.
	if _non_signature_count(relics_held) == 0 and count > 0:
		picks = roll_foundation_relics(1, relics_held, hero_id)
	for id in picks:
		pool.erase(id)
	var rest: Array[String] = weighted_sample(pool, mini(count - picks.size(), pool.size()))
	picks.append_array(rest)
	return picks


static func roll_campaign_relics(count: int = 1, relics_held: Array[String] = [],
		hero_id: String = "") -> Array[String]:
	var pool: Array[String] = filter_pool_for_run(
		get_relics_by_tier("utility"), hero_id, relics_held)
	return weighted_sample(pool, mini(count, pool.size()))


# Backward-compatible entry point for old saves/events. New reward sources use
# the named Foundation / Field / Campaign methods so their contract is visible.
static func roll_relic_reward(tier: String = "combat", relics_held: Array[String] = [],
		hero_id: String = "", count: int = 3) -> Array[String]:
	if tier == "combat":
		return roll_field_relics(count, relics_held, hero_id)
	if tier == "utility":
		return roll_campaign_relics(count, relics_held, hero_id)
	var pool: Array[String] = filter_pool_for_run(get_relics_by_tier(tier), hero_id, relics_held)
	return weighted_sample(pool, mini(count, pool.size()))


# Rarity-weighted sample without replacement. Commons dominate the draw; rares
# surface occasionally (see RELIC_RARITY / RARITY_WEIGHT). Ids with no rarity
# entry weigh as common, so a pool with no rarity data behaves like a plain
# shuffle — keeping the boss/utility roll paths identical to before.
static func weighted_sample(pool: Array[String], k: int,
		rng: RandomNumberGenerator = null) -> Array[String]:
	var remaining: Array[String] = pool.duplicate()
	var picks: Array[String] = []
	while picks.size() < k and not remaining.is_empty():
		var total := 0
		for id in remaining:
			total += int(RARITY_WEIGHT.get(get_relic_rarity(id), 6))
		var roll := (rng.randi() if rng != null else randi()) % total
		var chosen := 0
		for i in remaining.size():
			roll -= int(RARITY_WEIGHT.get(get_relic_rarity(remaining[i]), 6))
			if roll < 0:
				chosen = i
				break
		picks.append(remaining[chosen])
		remaining.remove_at(chosen)
	return picks


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
#
# THE +2 WAS BUDGETED AGAINST A FLAT 3, and the 2026-09-16 ramp changed what it
# buys without touching a line here: on round 1 the player holds ONE Command, so
# a full +2 stack is a TRIPLED opening, where it used to be +67% on a number that
# never moved. Left at 2 on purpose — the cap still does its job (it bounds how
# much non-boss Command may be stacked) and ECONOMY_REDESIGN §5.12 sequences the
# balance cascade after the rescale is measured, so moving this in the same pass
# would make neither attributable. Re-read it when that pass runs; the relics it
# governs are all listed by `mana_cap_cost`.
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
# already owned, retired, wrong-hero restricted, over the mana cap, or structurally
# blank for the current run. This is the relic equivalent of PotionDB._roll_allowed.
static func filter_pool_for_run(pool: Array[String], hero_id: String, relics_held: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for id in pool:
		if not RELICS.has(id):
			continue
		if bool(RELICS[id].get("retired", false)):
			continue
		if relics_held.has(id):
			continue
		if is_restricted_to_other_hero(id, hero_id):
			continue
		if would_exceed_mana_cap(id, relics_held):
			continue
		if not _offer_allowed(id, relics_held):
			continue
		result.append(id)
	return result


static func _non_signature_count(relics_held: Array[String]) -> int:
	var count := 0
	for id in relics_held:
		if RELICS.has(id) and String(RELICS[id].get("tier", "")) in [
				"combat", "utility", "boss"]:
			count += 1
	return count


static func _deck_data() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if RunState == null or not RunState.run_active:
		return out
	# Eligibility must see the same folded cards Combat will draw. Permanent
	# grant_kw / war_school / forge mods can create the keyword or subtype that
	# makes a relic live; reading CardDB bases here falsely hid those offers.
	for i in range(RunState.deck.size()):
		var d: Dictionary = RunState.get_upgraded_card_data(i)
		if not d.is_empty():
			out.append(d)
	return out


static func _deck_ctype_count(ctype: String) -> int:
	var count := 0
	for d in _deck_data():
		if String(d.get("ctype", "")) == ctype:
			count += 1
	return count


static func _deck_has_keyword(keyword: String) -> bool:
	for d in _deck_data():
		if d.get("keywords", []).has(keyword):
			return true
	return false


static func _deck_has_spell() -> bool:
	for d in _deck_data():
		if String(d.get("type", "")) == "spell":
			return true
	return false


static func _deck_has_damage_spell() -> bool:
	const DAMAGE_TYPES := ["damage", "damage_face", "damage_all_enemies", "damage_all"]
	const DAMAGE_CUSTOMS := [
		"blood_tithe", "petard", "slow_match", "sappers_charge", "penance",
		"lightning", "mass_grave", "plague_bell", "last_rites", "pillage",
		"earthquake", "slash", "flame_bolt", "quick_shot", "ambush",
		"inferno", "immolate", "wildfire", "ricochet", "ballista_bolt",
		"cataclysm", "fuel_the_pyre", "rout", "holy_smite", "hex", "wolf_pits",
	]
	for d in _deck_data():
		if String(d.get("type", "")) != "spell":
			continue
		var spell: Dictionary = d.get("spell", {})
		if String(spell.get("type", "")) in DAMAGE_TYPES:
			return true
		if String(spell.get("type", "")) == "custom" \
				and String(spell.get("id", "")) in DAMAGE_CUSTOMS:
			return true
	return false


static func _deck_has_curse_or_source(relics_held: Array[String]) -> bool:
	if RunState != null:
		for id in RunState.deck:
			if CardDB.is_curse(String(id)):
				return true
	for id in relics_held:
		if not RELICS.has(id):
			continue
		if String(RELICS[id].get("downside", "")) in ["curse_on_reward", "start_curses"]:
			return true
	return false


static func _deck_has_sacrifice_source() -> bool:
	for d in _deck_data():
		if d.get("keywords", []).has("sacrifice"):
			return true
		if String(d.get("spell", {}).get("id", "")) in [
				"offering", "fuel_the_pyre", "dark_pact"]:
			return true
		if String(d.get("floop", {}).get("type", "")) == "blood_sacrifice":
			return true
	return false


static func _deck_has_on_death_damage() -> bool:
	for d in _deck_data():
		if String(d.get("on_death", {}).get("type", "")).begins_with("damage"):
			return true
	return false


static func _deck_has_token_source() -> bool:
	for d in _deck_data():
		if String(d.get("on_death", {}).get("type", "")) == "summon":
			return true
		if String(d.get("floop", {}).get("type", "")) in [
				"summon_random", "kill_adjacent_summon", "summon_token"]:
			return true
	return false


static func _offer_allowed(id: String, relics_held: Array[String]) -> bool:
	# Outside a live run (collection/probes), eligibility is informational only.
	if RunState == null or not RunState.run_active:
		return true
	match id:
		"heads_on_pikes":
			return RunState.generals_broken_run > 0
		"powder_horn", "old_meg":
			return _deck_has_damage_spell()
		"glowing_hand":
			return _deck_has_damage_spell()
		"familiars_quill":
			return _deck_ctype_count("warlock") > 0 and _deck_has_spell()
		"head_money":
			return _deck_ctype_count("stray") > 0
		"portcullis":
			return _deck_ctype_count("bastion") > 0
		"wormwood":
			return _deck_ctype_count("bastion") > 0
		"second_rank":
			return _deck_ctype_count("soldier") >= 2
		"sextons_spade", "hourglass_of_ruin":
			return _deck_has_keyword("doom")
		"cerecloth":
			return not RunState.fallen.is_empty()
		"drill_book":
			if RunState.get_act() < 3:
				return true
			for uid in RunState.creature_kills:
				if int(RunState.creature_kills[uid]) >= 2:
					return true
			return false
		"centaur_heart":
			return RunState.get_act() == 1
		"du_vu_doll":
			return _deck_has_curse_or_source(relics_held)
		"briar_amulet":
			return _deck_has_keyword("thorns")
		"bulwark_engine":
			return _deck_has_keyword("armored")
		"bone_ring":
			return _deck_has_on_death_damage()
		"butchers_cleaver", "bone_pile", "reapers_scythe":
			return _deck_has_sacrifice_source()
		"the_family":
			return _deck_has_token_source()
	return true
