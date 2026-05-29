#!/usr/bin/env python3
"""Relic balance audit using mana-EV scoring + dominance + reference cross-check.

Methodology:
1. Each relic hand-tagged with structured fields (effect family, magnitude,
   trigger frequency, universality, drawback).
2. Convert effects into "mana-equivalent value per fight" using a fixed
   conversion table grounded in actual game economy:
     - 1 mana = 1 mana
     - 1 card drawn = 1.5 mana
     - 1 ATK permanent = 1 mana (1 creature) or 4 mana (board-wide)
     - 1 HP healed = 0.4 mana
     - 1 dmg dealt = 0.8 mana
     - 1 cost reduction = 1 mana
     - 1 keyword granted = 1.5 mana
     - 1 gold = 0.04 mana (50g shop card ≈ 2 mana EV)
     - summon X/Y token = 0.8X + 0.4Y mana
3. Score = (mana_per_trigger * triggers_per_fight * universality) - drawback_cost
4. Tier baselines:
     - starting: expect 4-7 mana/fight, well-balanced ~5
     - combat (no drawback): expect 6-10 mana/fight, ~7-8
     - utility: out-of-combat, scored separately
     - boss (with downside): expect 10-15 mana/fight NET
5. Flag any relic with score > 1.4x its tier baseline as OVERTUNED.
6. Dominance: cluster by effect family; flag intra-family overlaps.
7. Combo detection: hand-listed multiplicative pairs.
8. Reference cross-check: import flags for StS/Hades/Inscryption equivalents
   and what their downside / tier is in the source game.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional

# ─── Conversion table ─────────────────────────────────────────────────────
MANA_PER_DRAW    = 1.5
MANA_PER_HP      = 0.4
MANA_PER_DMG     = 0.8
MANA_PER_GOLD    = 0.04
MANA_PER_ATK_1   = 1.0    # single-creature perm ATK
MANA_PER_ATK_ALL = 4.0    # board-wide (4 creatures)
MANA_PER_KW      = 1.5    # single keyword grant
MANA_PER_COST_RED = 1.0
MANA_PER_TOKEN_HP = 0.4
MANA_PER_TOKEN_ATK = 0.8

# Per-fight typicals (4-round avg fight)
ROUNDS_PER_FIGHT = 4
TURNS_PER_FIGHT = 4
SPELLS_PER_FIGHT = 2.5
CREATURES_PLAYED_PER_FIGHT = 5
DEATHS_PER_FIGHT = 3
FRIENDLY_DEATHS_PER_FIGHT = 1.5
FACE_HITS_PER_FIGHT = 2

# Tier baselines (expected EV per fight)
TIER_BASELINE = {
    "starting": 5.0,
    "combat":   7.5,
    "utility": 6.0,   # out-of-combat value averaged
    "boss":   12.0,
}
OVERTUNED_RATIO = 1.4  # >1.4x baseline = flagged


@dataclass
class Relic:
    id: str
    name: str
    tier: str       # starting / combat / utility / boss
    family: str     # tag for pool clustering: atk_buff, draw, mana, death, sacrifice, etc.
    ev: float       # mana-equivalent value per fight (gross upside)
    universality: float  # 0.0-1.0; how often the effect applies in arbitrary decks
    drawback: float = 0.0  # mana-equivalent cost subtracted from EV
    scaling: str = "linear"  # one_shot / linear / unbounded / conditional
    archetype: str = "any"  # any / spell / creature / sac / swarm / death / aggro
    sts_ref: Optional[str] = None  # known import — note source tier/cost
    combo_keys: list = field(default_factory=list)  # tags for combo detection
    notes: str = ""

    @property
    def score(self) -> float:
        return self.ev * self.universality - self.drawback

    @property
    def baseline(self) -> float:
        return TIER_BASELINE[self.tier]

    @property
    def ratio(self) -> float:
        return self.score / self.baseline if self.baseline else 0


# ─── RELIC CATALOG (all 122 hand-tagged) ──────────────────────────────────
# Notes on tagging philosophy:
# - universality: 1.0 = applies in every deck (e.g. +ATK to all creatures);
#                 0.7 = applies in most builds; 0.4 = archetype-specific;
#                 0.2 = niche / requires setup.
# - ev: estimated mana-equivalent value per 4-round fight if you have the relic.
# - drawback: mana-equivalent cost subtracted (curses, healing loss, etc.)
# - "unbounded" scaling auto-flags; we don't try to model it precisely.

R = []  # list of Relic

# ═══════════════ STARTING (8) ═══════════════
R += [
    # Last Stand once on first creature — saves ~3 dmg, value ~3 mana
    Relic("iron_buckler", "Iron Buckler", "starting", "defensive",
        ev=3.0, universality=1.0, scaling="one_shot",
        notes="One Last Stand save per fight, on first creature only"),

    # First spell free per TURN — 4 turns × ~1.5 avg spell cost = 6 mana
    Relic("ember_crown", "Ember Crown", "starting", "spell_cost",
        ev=6.0, universality=0.7, archetype="spell",
        notes="Strong but needs spells in hand to trigger"),

    # +1 draw turn 1 = 1.5 mana value, one-shot
    Relic("couriers_bag", "Courier's Bag", "starting", "draw",
        ev=1.5, universality=1.0, scaling="one_shot"),

    # +10 gold per fight × ~15 fights = 150g = ~3 cards worth of EV per RUN.
    # Per-fight: 10g × 0.04 = 0.4 mana. Per-run cumulative: much more.
    Relic("coin_purse", "Coin Purse", "starting", "gold",
        ev=2.0, universality=1.0,
        notes="Quiet snowball; run-level value much higher than per-fight"),

    # +1 dmg to damage spells: 2 dmg spells/fight × 0.8 = 1.6 mana
    Relic("worn_spellbook", "Worn Spellbook", "starting", "spell_dmg",
        ev=3.5, universality=0.6, archetype="spell"),

    # 4 reward choices instead of 3 — pure deck-shaping snowball
    # Hard to score per-fight; flagging as run-warping at starting tier
    Relic("scouts_emblem", "Scout's Emblem", "starting", "reward",
        ev=8.0, universality=1.0,
        notes="33% better deck quality across 15+ rewards — snowball multiplier"),

    # First friendly death/round → +1 mana next turn. ~2 triggers/fight = 2 mana
    Relic("soul_lantern", "Soul Lantern", "starting", "death_mana",
        ev=3.0, universality=0.5, archetype="death"),

    # 1-cost creatures +1/+1. Starter deck has 4 Goblins (1/2 → 2/3).
    # Doubling ATK on chaff = massive
    Relic("veterans_medal", "Veteran's Medal", "starting", "atk_buff",
        ev=7.0, universality=1.0,
        notes="Doubles ATK on starter Goblins; obscenely strong"),
]

# ═══════════════ COMBAT (most relics) ═══════════════
R += [
    # On-enter damage +1: ~2 on-enter creatures × 1 = 2 mana
    Relic("vanguards_cry", "Vanguard's Cry", "combat", "kw_bonus",
        ev=3.0, universality=0.5, archetype="creature"),

    # Adj buffs +1 ATK: niche, only adj_buff creatures
    Relic("banner_of_unity", "Banner of Unity", "combat", "adj_bonus",
        ev=3.0, universality=0.3, archetype="adj"),

    # Swift creatures +1 ATK: 1-2 swift creatures × +1 ATK = ~3 mana
    Relic("swift_boots", "Swift Boots", "combat", "kw_bonus",
        ev=4.0, universality=0.5, archetype="swift"),

    # Armored -2 instead of -1: doubles armored's effective HP. ~3 armored creatures
    Relic("fortress_stone", "Fortress Stone", "combat", "kw_bonus",
        ev=7.0, universality=0.4, archetype="armored",
        notes="Doubles armored damage reduction"),

    # Thorns 2 instead of 1: doubles thorns
    Relic("briar_amulet", "Briar Amulet", "combat", "kw_bonus",
        ev=6.0, universality=0.4, archetype="thorns"),

    # Echo Staff — doubles ALL floops. ~3 floops/fight × ~2 mana = 6 mana doubled
    Relic("echo_staff", "Echo Staff", "combat", "floop",
        ev=14.0, universality=0.9, scaling="unbounded",
        notes="UNIVERSAL floop doubler, no cost"),

    # Piercing +1 overflow: niche, ~2 mana
    Relic("piercing_crown", "Piercing Crown", "combat", "kw_bonus",
        ev=3.0, universality=0.3, archetype="piercing"),

    # Summon tokens +1 HP: niche
    Relic("conscription_relic", "Conscription", "combat", "kw_bonus",
        ev=3.0, universality=0.3, archetype="swarm"),

    # On-death damage +1: 2 on-death creatures × 1
    Relic("bone_ring", "Bone Ring", "combat", "kw_bonus",
        ev=3.0, universality=0.4, archetype="death"),

    # Face-damage spells +1: ~2 face spells/fight
    Relic("pyromaniac_ring", "Pyromaniac's Ring", "combat", "spell_dmg",
        ev=3.0, universality=0.5, archetype="spell"),

    # ATK-buff spells +1: niche
    Relic("war_horn", "War Horn", "combat", "spell_buff",
        ev=2.5, universality=0.3, archetype="buff"),

    # First face dmg/fight: +2 mana = 2 mana value, ~always triggers
    Relic("battle_scars", "Battle Scars", "combat", "mana",
        ev=4.0, universality=0.9, scaling="one_shot"),

    # +1/-1: real tradeoff. NET ~0 mana (offsetting), but small tempo gain
    Relic("glass_cannon", "Glass Cannon", "combat", "stat_swap",
        ev=2.0, universality=1.0, drawback=1.5,
        notes="Real tradeoff — well-designed"),

    # -1/+1: real tradeoff, opposite
    Relic("stone_skin", "Stone Skin", "combat", "stat_swap",
        ev=2.0, universality=1.0, drawback=1.5,
        notes="Real tradeoff — well-designed"),

    # Win 0 face damage: +5g. ~50% rate = 2.5g avg = tiny
    Relic("thiefs_gloves", "Thief's Gloves", "combat", "gold",
        ev=0.5, universality=0.5, scaling="conditional"),

    # Sacrifice → next creature +2 ATK 2 rounds: ~3 sacs × 2*2 = 12 dmg = 8 mana
    Relic("butchers_cleaver", "Butcher's Cleaver", "combat", "sacrifice",
        ev=8.0, universality=0.4, archetype="sac"),

    # Heal 1 per death, max 5: ~3-5 deaths/fight = 3-5 HP = 2 mana
    Relic("vultures_feast", "Vulture's Feast", "combat", "heal",
        ev=2.5, universality=0.7,
        notes="Universal but capped"),

    # Coin flip: 50% +1 draw or 50% 3 dmg. ~0.75 + 1.2 = ~2 mana
    Relic("gamblers_coin", "Gambler's Coin", "combat", "rng",
        ev=2.0, universality=1.0, scaling="one_shot"),

    # Sacrifice → deal ATK to opposing: ~3 sacs × 2 ATK = 6 dmg = 5 mana
    Relic("bone_pile", "Bone Pile", "combat", "sacrifice",
        ev=6.0, universality=0.4, archetype="sac"),

    # First keyword death → spread to all. ENORMOUS scaling
    Relic("resonance_crystal", "Resonance Crystal", "combat", "keyword_spread",
        ev=15.0, universality=0.7, scaling="unbounded",
        combo_keys=["keyword_spread"],
        notes="Spread ANY keyword to entire board, fight-long"),

    # Played creature copies adj keyword. Universal +1 keyword/creature played
    Relic("mimic_ring", "Mimic Ring", "combat", "keyword_grant",
        ev=8.0, universality=0.7,
        notes="Every creature gets +1 keyword for free"),

    # +1g per bonus draw: tiny
    Relic("scroll_of_greed", "Scroll of Greed", "combat", "gold",
        ev=1.0, universality=0.4),

    # Take face dmg → creatures +1 ATK that round. ~2 triggers × 4 creatures = 8 dmg = 6 mana
    Relic("bloodstone_relic", "Bloodstone", "combat", "atk_buff",
        ev=6.0, universality=0.8),

    # Phoenix Heart — once/run revive. Saves a run. Value comp. to a whole fight
    Relic("phoenix_heart", "Phoenix Heart", "combat", "revive",
        ev=18.0, universality=1.0, scaling="one_shot",
        sts_ref="Lizard Tail (BOSS tier in StS)",
        notes="Saves a full run; should be boss tier with drawback"),

    # Front row +1 ATK: most creatures go front. ~4 creatures × 1 = 4 mana
    Relic("vanguard_banner", "Vanguard Banner", "combat", "atk_buff",
        ev=5.0, universality=0.9,
        notes="Universal +1 ATK with thin condition"),

    # Front dies → back gets +1/+1: niche, back-row scaling
    Relic("rear_guard_charm", "Rear Guard Charm", "combat", "death_buff",
        ev=4.0, universality=0.4, archetype="back"),

    # Phantom Veil — first death/round survives at 1. 4 rounds × ~3 mana save
    Relic("phantom_veil", "Phantom Veil", "combat", "save",
        ev=12.0, universality=0.9,
        notes="Per-round revive is massive in long fights"),

    # Ranged immune to back row: nullifies enemy mechanic
    Relic("hexagonal_shield", "Hexagonal Shield", "combat", "immunity",
        ev=4.0, universality=0.5,
        notes="Total denial of a specific enemy mechanic"),

    # 4×4 positional
    Relic("vanguards_cry_4x4", "Vanguard's Cry (placeholder)", "combat", "kw_bonus",
        ev=0, universality=0, notes="not real"),
]

# Patch — remove placeholder
R = [r for r in R if r.id != "vanguards_cry_4x4"]

# ═══════════════ UTILITY (8) ═══════════════
R += [
    # 25% shop discount: ~50g saved per shop × 3 shops = 150g = 6 mana EV/run
    Relic("merchants_license", "Merchant's License", "utility", "economy",
        ev=6.0, universality=1.0,
        notes="Strong but utility-tier-appropriate"),

    # Pick 2 cards from reward: +100% deck shaping
    Relic("collectors_tome", "Collector's Tome", "utility", "reward",
        ev=15.0, universality=1.0,
        notes="DOUBLE deck shaping per reward — game-warping"),

    # Sharpen/Fortify +3 instead +2: +50% upgrade value
    Relic("blacksmiths_hammer", "Blacksmith's Hammer", "utility", "upgrade",
        ev=6.0, universality=1.0,
        notes="Universal +50% to all upgrades"),

    # 20g per card removed: pays for itself
    Relic("scavengers_pouch", "Scavenger's Pouch", "utility", "economy",
        ev=4.0, universality=0.8),

    # Reforge 2 cards once per act: 3 upgrades/run extra
    Relic("whetstone", "Whetstone", "utility", "upgrade",
        ev=5.0, universality=1.0),

    # After elite: upgrade random card
    Relic("olympians_mark", "Olympian's Mark", "utility", "upgrade",
        ev=4.0, universality=1.0,
        notes="~5 elites/run = 5 free upgrades"),

    # Act 2 start: +5 HP, full heal — one-shot
    Relic("centaur_heart", "Centaur Heart", "utility", "hp",
        ev=4.0, universality=1.0, scaling="one_shot"),

    # Card rewards include 1 boss-rarity option
    Relic("stardust_vial", "Stardust Vial", "utility", "reward",
        ev=12.0, universality=1.0,
        notes="Boss cards on EVERY reward — warps rarity"),
]

# ═══════════════ BOSS (originals — +1 mana with downside) ═══════════════
# +1 max mana ≈ 4 mana/fight EV (extra mana each turn × 4 turns)
R += [
    # +1 mana, +1 curse per reward = ~15 curses/run = heavy ongoing drag
    Relic("cursed_key", "Cursed Key", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=10.0,
        sts_ref="StS: same name, same effect"),

    # +1 mana, no rest heal
    Relic("coffee_dripper", "Coffee Dripper", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=8.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, no card upgrades
    Relic("fusion_hammer", "Fusion Hammer", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=8.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, no gold
    Relic("ectoplasm", "Ectoplasm", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=10.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, 1 reward choice
    Relic("busted_crown", "Busted Crown", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=9.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, no potions
    Relic("sozu", "Sozu", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=6.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, enemies +1 ATK
    Relic("philosophers_stone", "Philosopher's Stone", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=7.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, max 5 cards/turn
    Relic("velvet_choker", "Velvet Choker", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=5.0,
        sts_ref="StS: same name, +1 energy"),

    # +1 mana, 2 curses combat start. Curses lock 2/4 hand slots
    Relic("mark_of_pain", "Mark of Pain", "boss", "mana_dwn",
        ev=16.0, universality=1.0, drawback=8.0,
        sts_ref="StS: same name, +1 energy"),
]

# ═══════════════ MANA RELICS (non-boss) ═══════════════
R += [
    # +1 mana on turn 1: 1 mana, one-shot
    Relic("lantern", "Lantern", "combat", "mana",
        ev=1.5, universality=1.0, scaling="one_shot",
        sts_ref="StS: +1 energy turn 1"),

    # Every 3 turns +1 mana: ~1 trigger/fight = 1 mana
    Relic("happy_flower", "Happy Flower", "combat", "mana",
        ev=1.5, universality=1.0,
        sts_ref="StS: same name"),

    # Ice Cream: unbounded mana banking
    Relic("ice_cream", "Ice Cream", "combat", "mana",
        ev=8.0, universality=0.8, scaling="unbounded",
        sts_ref="StS: same name, well-known broken",
        notes="Removes the core mana-banking constraint"),

    # No plays → +1 mana next turn. Niche
    Relic("art_of_war", "Art of War", "combat", "mana",
        ev=2.0, universality=0.4, archetype="control"),

    # Every 3 shuffles +2 mana: 1 trigger per long fight
    Relic("sundial", "Sundial", "combat", "mana",
        ev=2.0, universality=0.5,
        sts_ref="StS: same name"),
]

# ═══════════════ COST MANIPULATION ═══════════════
R += [
    # Spell cast → random creature 0 cost. ~2 spells × ~2 mana saved = 4 mana
    Relic("mummified_hand", "Mummified Hand", "combat", "cost_red",
        ev=6.0, universality=0.7,
        sts_ref="StS: same name, +1 energy ratio appropriate",
        notes="Universal in any deck with spells"),

    # Death → next creature -1 cost, 1/round. 4 rounds × 1 = 4 mana
    Relic("sigil_of_hunger", "Sigil of Hunger", "combat", "cost_red",
        ev=5.0, universality=0.6, archetype="death"),

    # Hand ≥4 → all cards -1. 4-card hand is default at start; usually true
    Relic("tricksters_glove", "Trickster's Glove", "combat", "cost_red",
        ev=10.0, universality=0.9, scaling="conditional",
        notes="Condition almost always true → effectively -1 to everything"),

    # Turn start: highest-cost card 0. ~2 mana/turn × 4 = 8 mana
    Relic("pact_of_embers", "Pact of Embers", "combat", "cost_red",
        ev=12.0, universality=1.0,
        notes="Free expensive card every turn, no condition"),

    # Bank mana → next creature -1. Niche
    Relic("mana_tide", "Mana Tide", "combat", "cost_red",
        ev=3.0, universality=0.4),

    # 1-HP creatures cost 1 less: niche
    Relic("last_breath", "Last Breath", "combat", "cost_red",
        ev=2.0, universality=0.3, archetype="frail"),
]

# ═══════════════ HAND/DRAW ═══════════════
R += [
    # See top card: information advantage, ~2 mana value
    Relic("frozen_eye", "Frozen Eye", "combat", "info",
        ev=3.0, universality=1.0,
        sts_ref="StS: same name"),

    # Combat start: choose 1 of 3 curated cards. ~3 mana value
    Relic("toolbox", "Toolbox", "combat", "draw",
        ev=4.0, universality=1.0, scaling="one_shot",
        sts_ref="StS: same name"),

    # Always start with chosen card: ~3-5 mana value
    Relic("bottled_talisman", "Bottled Talisman", "combat", "draw",
        ev=4.5, universality=0.8, scaling="one_shot",
        sts_ref="StS: Bottled Flame/Lightning/Tornado, 3 variants"),

    # First draw is cheapest. ~1 mana value
    Relic("looking_glass", "Looking Glass", "combat", "draw",
        ev=2.5, universality=1.0),
]

# ═══════════════ 4x4 LANE / POSITIONAL ═══════════════
R += [
    # All 4 front full → +1 ATK. Conditional but achievable
    Relic("phalanx_stone", "Phalanx Stone", "combat", "atk_buff",
        ev=5.0, universality=0.5, scaling="conditional"),

    # Empty edge lanes: +1 mana each. Up to +2/turn!
    Relic("cavalry_sigil", "Cavalry Sigil", "combat", "mana",
        ev=8.0, universality=0.6,
        notes="Up to +2 mana/turn from leaving edges empty"),

    # Empty lanes count as adj. Niche
    Relic("sentinel_pact", "Sentinel Pact", "combat", "adj_bonus",
        ev=3.0, universality=0.4),

    # Back row gets Ranged. ENORMOUS — entire back row of shooters
    Relic("catapult_crew", "Catapult Crew", "combat", "kw_grant",
        ev=10.0, universality=0.8,
        notes="Universal Ranged on whole back row"),

    # Center 2&3: Thorns 2 + 1 HP. Conditional but achievable
    Relic("bridge_watcher", "Bridge Watcher", "combat", "lane_buff",
        ev=5.0, universality=0.6),

    # Empty column → friendlies in column +1 ATK. Stackable, per-play
    Relic("spotters_glass", "Spotter's Glass", "combat", "atk_buff",
        ev=6.0, universality=0.6),

    # 3/4 front full → enemy in empty col takes 2/round
    Relic("flanking_banner", "Flanking Banner", "combat", "dmg",
        ev=4.0, universality=0.4, scaling="conditional"),
]

# ═══════════════ COMBAT-START ═══════════════
R += [
    # Start: 1 dmg to all enemies. ~2 mana value vs swarm
    Relic("bag_of_marbles", "Bag of Marbles", "combat", "combat_start",
        ev=2.0, universality=0.6, scaling="one_shot",
        sts_ref="StS: same name"),

    # Turn 1: friendlies +1 ATK. ~3 mana
    Relic("champions_belt", "Champion's Belt", "combat", "combat_start",
        ev=3.0, universality=0.9, scaling="one_shot"),

    # War Drum: free random friendly. ~3-5 mana value depending on roll
    Relic("war_drum", "War Drum", "combat", "combat_start",
        ev=5.0, universality=1.0, scaling="one_shot",
        notes="Free creature every fight — Astrolabe-tier"),

    # Free random spell. ~3-6 mana depending on roll
    Relic("witchs_brew", "Witch's Brew", "combat", "combat_start",
        ev=6.0, universality=1.0, scaling="one_shot",
        notes="Free spell every fight; Apocalypse roll wins the fight"),
]

# ═══════════════ CONDITIONAL SCALING ═══════════════
R += [
    # 50%+ spells → spells cost 1 less. Universal in spell deck
    Relic("spell_tome", "Spell Tome", "combat", "cost_red",
        ev=10.0, universality=0.5, archetype="spell",
        notes="Spell decks get -1 to ALL spells, very strong"),

    # 60%+ creatures → friendlies +1 HP. Universal in creature deck
    Relic("iron_legion", "Iron Legion", "combat", "hp_buff",
        ev=5.0, universality=0.6, archetype="creature"),

    # 20+ cards → draw +2 per turn. Easy threshold, massive draw
    Relic("tome_of_many", "Tome of Many", "combat", "draw",
        ev=12.0, universality=0.8,
        notes="+2 draw/turn at trivial deck-size threshold"),

    # 2 turns all-mana → +1 max mana fight. Modest ramp
    Relic("mana_drunkard", "Mana Drunkard", "combat", "mana",
        ev=3.5, universality=0.7),
]

# ═══════════════ SACRIFICE / DEATH ═══════════════
R += [
    # 5 deaths in 1 round → +2 max mana. Niche but explosive
    Relic("skull_throne", "Skull Throne", "combat", "mana",
        ev=4.0, universality=0.3, archetype="sac"),

    # Sac creature with floop → next gets it. Niche
    Relic("reapers_scythe", "Reaper's Scythe", "combat", "sacrifice",
        ev=4.0, universality=0.3, archetype="sac"),

    # +1 ATK per Curse. Scales with curse count
    Relic("du_vu_doll", "Du-Vu Doll", "combat", "atk_buff",
        ev=6.0, universality=0.3, archetype="curse",
        sts_ref="StS: same name, well-known build-around"),

    # Every 5th friendly death → 4/4 token. Very strong slow trigger
    Relic("soul_ledger", "Soul Ledger", "combat", "summon",
        ev=7.0, universality=0.5, archetype="death",
        notes="Free 4/4 every ~2 fights; persistent counter scales"),
]

# ═══════════════ SPELL DEEPENING ═══════════════
R += [
    # First spell each combat is Sharpened (+2 dmg)
    Relic("reagent_pouch", "Reagent Pouch", "combat", "spell_dmg",
        ev=2.0, universality=0.7, scaling="one_shot", archetype="spell"),

    # Every 5th spell: copy random spell to hand
    Relic("inkpot_of_many", "Inkpot of Many", "combat", "spell_copy",
        ev=4.0, universality=0.5, archetype="spell"),

    # 0-cost spells +3 dmg. Niche to 0-cost spells
    Relic("mana_pearl", "Mana Pearl", "combat", "spell_dmg",
        ev=4.0, universality=0.4, archetype="spell"),
]

# ═══════════════ BUILD-AROUND ═══════════════
R += [
    # Every 10th card → pick creature → 6/6 Piercing. Scales hard
    Relic("pen_nib", "Pen Nib", "combat", "buff",
        ev=8.0, universality=0.6,
        notes="6/6 Piercing per ~2.5 fights; obscene"),

    # Damaged → +1 ATK perm, max +5/creature. Unbounded-ish
    Relic("wormwood", "Wormwood", "combat", "atk_buff",
        ev=8.0, universality=0.8, scaling="unbounded",
        notes="Per-creature +5 ATK if they survive"),
]

# ═══════════════ HADES ═══════════════
R += [
    # Enemy dies → heal 1, max 5/combat. Universal heal
    Relic("stygian_soul", "Stygian Soul", "combat", "heal",
        ev=2.5, universality=0.9,
        notes="Quiet but ubiquitous heal"),

    # Each act, pick: front+1 ATK / back+1 HP / center mana. Major shape
    Relic("bone_hourglass", "Bone Hourglass", "combat", "buff",
        ev=6.0, universality=1.0,
        notes="Player-picked → always optimal"),
]

# ═══════════════ MONSTER TRAIN ═══════════════
R += [
    # Face dmg +1 if 3+ cards played. Easy condition
    Relic("pyre_stoker", "Pyre Stoker", "combat", "dmg_bonus",
        ev=3.0, universality=0.7),

    # Friendly attacked → 1 dmg back. Stacks with Thorns
    Relic("spike_driver", "Spike Driver", "combat", "thorns",
        ev=6.0, universality=0.9,
        notes="Universal — every attack on a friendly costs the enemy 1"),

    # Round end: 1/1 in back row. Free body every round
    Relic("imp_generator", "Imp Generator", "combat", "summon",
        ev=8.0, universality=0.9,
        notes="Free 1/1 every round; 4 free creatures per fight"),
]

# ═══════════════ BALATRO ═══════════════
R += [
    # Next creature copies on-enter of previous
    Relic("blueprint", "Blueprint", "combat", "copy",
        ev=5.0, universality=0.5, archetype="on_enter"),

    # Each round: first creature copies kw of fight's first
    Relic("brainstorm", "Brainstorm", "combat", "kw_grant",
        ev=6.0, universality=0.6),

    # End turn: chosen card triggers floop without cost
    Relic("mime", "Mime", "combat", "floop",
        ev=8.0, universality=0.8,
        combo_keys=["floop"],
        notes="Free floop/turn × 4 turns"),

    # 3+ same id → +1 ATK. Niche tribal
    Relic("the_family", "The Family", "combat", "tribal",
        ev=3.0, universality=0.3, archetype="tribal"),
]

# ═══════════════ WILDFROST ═══════════════
R += [
    # First creature each combat applies Wither 1 on attack
    Relic("frost_spike", "Frost Spike", "combat", "kw_bonus",
        ev=3.0, universality=0.6, scaling="one_shot"),

    # 4+ empty slots → +1 max mana. Easy early, tightens late
    Relic("junk_slot", "Junk Slot", "combat", "mana",
        ev=4.0, universality=0.7, scaling="conditional"),
]

# ═══════════════ COBALT CORE ═══════════════
R += [
    # End turn: pending. At 5: random rare to hand
    Relic("hourglass_sigil", "Hourglass Sigil", "combat", "rare_gen",
        ev=5.0, universality=1.0,
        notes="Free rare every ~5 turns = once per long fight"),
]

# ═══════════════ INSCRYPTION ═══════════════
R += [
    # Each act, pick keyword for all friendlies. Game-warping
    Relic("totem_pole", "Totem Pole", "combat", "kw_grant",
        ev=18.0, universality=1.0,
        notes="ALL friendlies get a keyword for an entire act"),

    # Friendlies that die go to hand, +1 cost per return
    Relic("death_card", "Death Card", "combat", "revive",
        ev=15.0, universality=0.7, scaling="unbounded",
        notes="Recursion — creatures never really die"),
]

# ═══════════════ BACKPACK HERO ═══════════════
R += [
    # 2+ adj friendlies → +1/+1. Easy to maintain
    Relic("linked_banner", "Linked Banner", "combat", "adj_bonus",
        ev=5.0, universality=0.8),

    # Diagonals count + adj +1 HP. Adj decks
    Relic("diagonal_crest", "Diagonal Crest", "combat", "adj_bonus",
        ev=4.0, universality=0.4, archetype="adj"),

    # Lane 1 or 4: Thorns 2. Always-on Thorns on edges
    Relic("corner_stone", "Corner Stone", "combat", "kw_grant",
        ev=4.0, universality=0.7),
]

# ═══════════════ CLASS-RESTRICTED ═══════════════
R += [
    # Raider: Swift play → +1 mana that turn
    Relic("raiders_oath", "Raider's Oath", "combat", "mana",
        ev=6.0, universality=0.9, archetype="raider",
        notes="Easy to spam; +1 mana/Swift play uncapped"),

    # Stalwart: First damage/turn → +1 mana
    Relic("stalwarts_anvil", "Stalwart's Anvil", "combat", "mana",
        ev=4.0, universality=0.9, archetype="stalwart"),

    # Acolyte: Exhaust spell → draw 1
    Relic("acolytes_tome", "Acolyte's Tome", "combat", "draw",
        ev=4.0, universality=0.7, archetype="acolyte"),

    # Pyromancer: First spell each combat doubled
    Relic("pyromancers_scar", "Pyromancer's Scar", "combat", "spell_copy",
        ev=4.0, universality=0.8, archetype="pyromancer",
        scaling="one_shot"),
]

# ═══════════════ BOSS — Round 3 (run-warping, no +1-mana template) ═══════════════
R += [
    # Pandora's Box — transform starting creatures to RANDOM RARES
    Relic("pandoras_box", "Pandora's Box", "boss", "deck_warp",
        ev=20.0, universality=1.0, drawback=0.0, scaling="one_shot",
        sts_ref="StS: transforms strikes/defends into COMMON cards",
        notes="OUR version goes common→rare; StS goes starter→common"),

    # Snecko Eye — draw 6, costs randomized 0-3
    Relic("snecko_eye", "Snecko Eye", "boss", "draw",
        ev=15.0, universality=1.0, drawback=2.0,
        sts_ref="StS: same name, applies Confusion (random cost) — balanced",
        notes="Our random 0-3 averages LOWER than baseline → pure upside"),

    # Calling Bell — 3 boss relics + 3 curses
    Relic("calling_bell", "Calling Bell", "boss", "loot",
        ev=30.0, universality=1.0, drawback=10.0,
        sts_ref="StS: 1 common + 1 boss + 1 rare relic, +1 curse",
        notes="3 BOSS relics is 3x the StS payout; curses far cheaper"),

    # Runic Pyramid — no end-turn discard
    Relic("runic_pyramid", "Runic Pyramid", "boss", "hand_persist",
        ev=18.0, universality=1.0,
        sts_ref="StS: same name — well-known broken",
        notes="Removes core hand economy constraint"),

    # Lich's Bargain — on-death triggers twice, -1 HP per death (max 3)
    Relic("lichs_bargain", "Lich's Bargain", "boss", "death_double",
        ev=15.0, universality=0.6, drawback=3.0, archetype="death",
        notes="3 HP for doubling death triggers; trivial cost"),

    # Lean Mean — +1 mana while deck ≤14
    Relic("lean_mean", "Lean Mean", "boss", "mana",
        ev=12.0, universality=0.6, scaling="conditional",
        notes="Conditional but achievable by removing cards"),

    # Glowing Hand — damage spells +1/spell cast this combat, max +5
    Relic("glowing_hand", "Glowing Hand", "boss", "spell_dmg",
        ev=8.0, universality=0.6, archetype="spell"),

    # Marathoner's Sash — +2 max mana, +2 ramp/round
    Relic("marathoners_sash", "Marathoner's Sash", "boss", "mana",
        ev=20.0, universality=1.0, drawback=2.0,
        notes="+2 max AND +2 ramp = absurd late game"),

    # Steady Banner — survive round → +2 ATK perm, turn 1 -1 ATK
    Relic("steady_banner", "Steady Banner", "boss", "atk_buff",
        ev=14.0, universality=0.9, drawback=2.0, scaling="unbounded",
        notes="Unbounded scaling on tanky creatures"),
]


# ─── Sanity check: did we cover all 122 RelicDB ids? ──────────────────────
import re, sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
DB = (ROOT / "scripts/data/RelicDB.gd").read_text(encoding="utf-8")
db_ids = set(re.findall(r'"id":\s*"([a-z_]+)"', DB))
tagged_ids = {r.id for r in R}
missing = db_ids - tagged_ids
extras  = tagged_ids - db_ids

if missing:
    print(f"WARNING: {len(missing)} relics in RelicDB but NOT TAGGED:")
    for m in sorted(missing): print(f"  - {m}")
if extras:
    print(f"WARNING: {len(extras)} tagged relics NOT in RelicDB:")
    for e in sorted(extras): print(f"  - {e}")
print(f"Coverage: {len(tagged_ids)}/{len(db_ids)} tagged ({len(tagged_ids)/max(len(db_ids),1)*100:.0f}%)\n")


# ─── ANALYSIS ─────────────────────────────────────────────────────────────

def rank_by_overtune():
    """Sort by ratio descending; show how much over baseline each is."""
    print("═" * 75)
    print("  OVERTUNED RELICS — sorted by EV-to-tier-baseline ratio")
    print("═" * 75)
    print(f"  {'RELIC':<28} {'TIER':<10} {'EV':>5}  {'×UNIV':>5}  {'-DRAW':>5}  {'SCORE':>6} {'RATIO':>6}")
    print("─" * 75)
    sorted_r = sorted(R, key=lambda r: r.ratio, reverse=True)
    for r in sorted_r:
        flag = ""
        if r.ratio >= OVERTUNED_RATIO: flag = "  ★ OVERTUNED"
        if r.scaling == "unbounded": flag += " ∞"
        print(f"  {r.name[:27]:<28} {r.tier:<10} {r.ev:>5.1f}  {r.universality:>5.2f}  "
              f"{r.drawback:>5.1f}  {r.score:>6.1f} {r.ratio:>5.2f}x{flag}")


def cluster_dominance():
    """Group by effect family; flag intra-family overlaps."""
    print()
    print("═" * 75)
    print("  POOL CLUSTERING — relics by effect family")
    print("═" * 75)
    by_family = {}
    for r in R:
        by_family.setdefault(r.family, []).append(r)
    for fam, lst in sorted(by_family.items(), key=lambda x: -len(x[1])):
        if len(lst) < 2: continue
        print(f"\n  Family: {fam}  ({len(lst)} relics)")
        for r in sorted(lst, key=lambda r: r.score, reverse=True):
            print(f"    {r.name[:30]:<32} score {r.score:>5.1f} ({r.tier})")


def combo_alerts():
    """Hand-curated combo multipliers."""
    print()
    print("═" * 75)
    print("  COMBO ALERTS — pairs whose combined effect >> sum")
    print("═" * 75)
    combos = [
        ("echo_staff", "mime", "Free floop × doubled = 2 free triggers/turn"),
        ("phoenix_heart", "bloodstone_relic", "Death-buff stacking + revive"),
        ("death_card", "bone_pile", "Infinite sacrifice loop"),
        ("death_card", "lichs_bargain", "Death triggers 4x via doubled+recursion"),
        ("resonance_crystal", "frost_spike", "Spread Wither to entire board"),
        ("pact_of_embers", "ice_cream", "Free top-cost card + unlimited banking"),
        ("tricksters_glove", "snecko_eye", "Cards cost -1 from already-randomized 0-3"),
        ("calling_bell", "any boss combo", "3 boss relics = 3 of these problems"),
        ("mummified_hand", "pyromancers_scar", "First spell doubles → 2 free creatures"),
        ("catapult_crew", "wormwood", "4 ranged creatures scaling to +5 ATK each"),
        ("catapult_crew", "briar_amulet", "4 ranged thorns-2 back-row shooters"),
        ("totem_pole", "anything", "Universal keyword + base effect"),
        ("steady_banner", "iron_legion", "Tanky creatures ramp ATK uncapped"),
        ("collectors_tome", "stardust_vial", "2 picks, one always boss-rarity"),
        ("scouts_emblem", "collectors_tome", "Pick 2 of 4 — see 8 cards per pair of rewards"),
    ]
    for a, b, note in combos:
        ra = next((r for r in R if r.id == a), None)
        rb = next((r for r in R if r.id == b), None)
        if ra and (rb or b.startswith("any")):
            label_b = rb.name if rb else b
            print(f"  {ra.name} + {label_b}: {note}")


def reference_audit():
    """For relics flagged as imports, show the source-game tier/effect."""
    print()
    print("═" * 75)
    print("  REFERENCE CROSS-CHECK — relics imported from other games")
    print("═" * 75)
    for r in R:
        if not r.sts_ref: continue
        warn = "★" if r.ratio > 1.4 else " "
        print(f"  {warn} {r.name[:30]:<30} ({r.tier:<8}) — {r.sts_ref}")


def unbounded_flag():
    print()
    print("═" * 75)
    print("  UNBOUNDED SCALING — relics with no upper cap")
    print("═" * 75)
    for r in R:
        if r.scaling == "unbounded":
            print(f"  {r.name[:30]:<32} ({r.tier:<8}) score {r.score:>5.1f}")


def final_priority():
    """Output a prioritized nerf list."""
    print()
    print("═" * 75)
    print("  FINAL NERF PRIORITY — sorted by (ratio × tier weight)")
    print("═" * 75)
    print("  Tier weight: starting=1.5, combat=1.0, utility=1.2, boss=0.7")
    print("  (downweight boss because they're SUPPOSED to be strong)")
    print("─" * 75)
    weights = {"starting": 1.5, "combat": 1.0, "utility": 1.2, "boss": 0.7}
    scored = sorted(R, key=lambda r: r.ratio * weights[r.tier], reverse=True)
    for i, r in enumerate(scored[:30]):
        prio = r.ratio * weights[r.tier]
        flag = ""
        if r.scaling == "unbounded": flag = " ∞"
        if r.drawback == 0 and r.score > r.baseline * 1.5: flag += " NO_DRAWBACK"
        print(f"  #{i+1:<2} {r.name[:28]:<29} {r.tier:<10} "
              f"score {r.score:>5.1f}  ratio {r.ratio:.2f}x  priority {prio:.2f}{flag}")


rank_by_overtune()
cluster_dominance()
combo_alerts()
reference_audit()
unbounded_flag()
final_priority()
