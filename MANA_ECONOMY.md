# Burning Meadow — Mana Economy & "Play More Per Turn" Analysis

A self-contained briefing document. Everything another chat needs to evaluate / propose changes to our mana system, without needing the rest of the codebase.

---

## 1. Game context (the minimum)

**Burning Meadow** — lane combat roguelike deckbuilder in Godot 4.6. Inspired by Card Wars (combat) + Slay the Spire (run structure).

- **Board:** 4 lanes × 2 rows per side (player & enemy). 8 slots each side.
- **Combat:** simultaneous (both sides attack on the same beat; dying creatures still swing).
- **Round flow:** draw 4 → play creatures/spells/floops → end turn → both sides resolve combat → enemy places new creatures → next round.
- **Player HP:** 25. **Hand size:** 10 max. **Draw:** 4 per turn.
- **Run length:** 3 acts, ~15 floors each, branching map (StS-style).

The "mana / play more per turn" question is the topic of this document.

---

## 2. Mana system rules

| Setting | Value |
|---|---|
| Starting max mana | **3** |
| Per-turn refill | Refills to max each turn |
| Max mana cap (with relics) | **~6** (Battle Scars +1 turn 1, Velvet Choker +1 base) |
| Banking | Up to **1 unspent mana** carries to next turn (default) |
| Banking with Ice Cream relic | Unlimited (uncapped) |
| Round 1 | Setup only — no combat, but mana is full |

So a typical fight curve looks like:
- Round 1: 3 mana, set up the board
- Round 2: 3 mana (+1 banked = 4), small spell + creature
- Round 3-5: 3 mana per turn unless relic-boosted
- Mid-late fight: ~4 mana with banking, no growth

**Hard ceiling:** ~4-5 mana per turn most of the run, ~6 with the right relics.

---

## 3. All cards that touch mana (10 cards)

### Creatures with mana abilities

| Card | Cost | Stats | Effect |
|---|---|---|---|
| **Mana Sprite** | 1 | 1/3 | Floop: gain 1 mana this turn |
| **Witch** | 2 | 1/3 | On-enter: draw 1. Floop: gain 1 mana this turn |
| **Leyline Conduit** | 2 | 0/3 | **Passive: +1 mana at start of each turn**. Floop: gain 2 mana this turn |

### Spells with mana abilities

| Card | Cost | Effect | Downside |
|---|---|---|---|
| **Adrenaline** | 0 (exhaust) | +1 mana + draw 1 | Exhausts |
| **Scrap** | 0 | Discard 1 card from hand → +1 mana | Lose a card |
| **Concentrate** | 0 | Discard 2 → +2 mana | Lose 2 cards |
| **Bloodletting** | 0 | -2 face HP → +2 mana | Permanent HP cost |
| **Turbo** | 0 | +2 mana, adds a Curse to discard pile | Curse drawn later, dead card |
| **Recycle** | 1 | Exhaust highest-cost hand card → gain mana = its cost | Lose your best card |
| **Offering** | 0 (exhaust) | Sacrifice a friendly creature → +2 mana | Sacrifice a body |

---

## 4. Cost reduction cards (just 1)

| Card | Cost | Effect |
|---|---|---|
| **Ironclad Veteran** | 3, 2/4 creature | Floop: next card this turn costs 1 less |

That's the entire list.

---

## 5. Card draw / hand cycling (10 cards)

| Card | Cost | Effect |
|---|---|---|
| **Provision** | 0 (exhaust) | Draw 2 |
| **Quick Shot** | 0 | Deal 1 to any + draw 1 |
| **Gambit** | 0 | Discard up to 3, draw same |
| **War Chant** | 0 | Discard 2, draw 2 |
| **Unholy Bargain** | 0 (exhaust) | Draw 3, take 3 face damage |
| **Lookout** | 1, 1/3 | On-enter: draw 1. Floop: scry 1 |
| **Mule** | 1, 0/3 | On-enter: draw 2. Floop: discard 1, draw 1 |
| **Bloodhound** | 1, 2/3 | On-enter: damage opposing + draw 1 |
| **Stray Cat** | 0, 0/1 | On-enter: look at top 3, draw cheapest |
| **Archmage** | 4, 3/5 | On-enter: draw 2 |
| **Witch** (also above) | 2, 1/3 | On-enter: draw 1 + mana floop |

---

## 6. Discover cards (just added)

| Card | Cost | Effect |
|---|---|---|
| **Lost Tome** | 1 spell, exhaust | Discover a common spell (pick 1 of 3) |
| **Scholar** | 2, 1/3 creature | On-enter: Discover a spell |
| **War Council** | 2 spell, exhaust | Discover any card |
| **Treasure Hunter** | 3, 2/3 creature | On-enter: Discover a rare card |

---

## 7. Relics that touch mana / cards-played

| Relic | Tier | Effect |
|---|---|---|
| **Battle Scars** | combat | +1 mana on turn 1 only of each fight |
| **Ice Cream** | combat | Unspent mana carries over fully (uncapped) |
| **Art of War** | combat | If you play no cards this turn, gain 1 extra mana next turn |
| **Velvet Choker** | boss | +1 max mana, but cap of 5 cards played per turn |

---

## 8. Spell synergy mechanics already in place

- **Combo** trigger (Flame Bolt): "Deal 3 face. Combo: deal 5 if you've already cast a spell this turn."
- **Slay** trigger (Slash, Smite): "If this spell kills the target, draw a card / gain mana."
- **Echo** (rare spell, 2c exhaust): copies last spell played this turn (effectively a free follow-up).
- **Spell counter:** `_spells_cast_this_turn` increments AFTER each spell resolves (used for Combo).
- **`_cards_played_this_turn`** counter — used by Velvet Choker (cap) and Art of War (was-zero check).
- **`_first_spell_this_turn`** flag — used by Ember Crown relic.

---

## 9. Problem statement

**Burning Meadow has lots of burst, almost no compounding.**

What we have:
- 10 mana-burst cards — but **8 of 10 have downsides** (discard, HP loss, sacrifice, curses, exhaust). They're temporary tempo plays, not investments.
- 1 permanent in-fight ramp creature (Leyline Conduit) — single point of failure with only 3 HP.
- 1 cost-reduction effect (Ironclad Veteran's floop) — single-card single-turn.
- 1-mana banking cap — too small to plan ahead.
- No "Power" pattern (StS Demon Form / HS Sorcerer's Apprentice) — no card that stays on the field and makes EVERY future turn cheaper or more.

What this means in play:
- Early game: drop a creature, maybe a cheap spell. Burn an Adrenaline for tempo.
- Mid game: 3-4 mana per turn, **no compounding** — every turn is roughly the same as the last.
- Late game: still ~4-5 mana, no payoff for surviving long fights, no "engine" turns.

Compare to other fixed-mana games:
| Game | How it solves "play more later" |
|---|---|
| Slay the Spire | **Power cards** (Demon Form, Inflame) stay in play and scale each turn |
| Hearthstone | **Mana ramp** (Wild Growth = permanent +1 next turn) + **cost reducers in play** (Sorcerer's Apprentice) |
| MTG | **Mana dorks** (Llanowar Elves = permanent +1 mana while alive) |
| Marvel Snap | **Wave** (all cards cost 1 this turn) + **Electro** (+1 energy, max 1 card) |
| LoR | **Spell-mana banking** up to 3, **champion levelups** that transform mid-fight |

We have none of these patterns at scale.

---

## 10. Proposed changes — existing cards

Each is a small targeted edit to fix the most glaring issue:

### 10.1 Mana Sprite — move mana from floop → on_enter
**Current:** 1c 1/3, floop: gain 1 mana this turn.
**Problem:** The floop only fires the turn AFTER it's played, so the mana arrives a turn late. You spend 1 mana to get 1 mana later — never advantage, only break-even.
**Change:** Move "+1 mana this turn" to **on-enter**. Now it's a Hearthstone-Innervate-with-a-body: spend 1 to play, get 1 back immediately, plus a 1/3 stays on board.

### 10.2 Concentrate — discard 1 (not 2) for +2 mana
**Current:** 0c, discard 2 → +2 mana.
**Problem:** Strictly worse than Scrap (0c, discard 1 → +1 mana) — same ratio, more pain.
**Change:** Discard **1** → +2 mana. Now it's an actual advantage card (lose 1 card, gain 2 mana).

### 10.3 Bloodletting — -1 HP (not -2) for +2 mana
**Current:** 0c, -2 face HP → +2 mana.
**Problem:** Across a 15-floor act, paying 2 HP per use compounds. Hearthstone Innervate is FREE.
**Change:** **-1 HP → +2 mana**. Still has a cost; not punitive.

### 10.4 Turbo — Curse exhausts at end of fight
**Current:** 0c, +2 mana + adds permanent Curse to draw pile.
**Problem:** Curse is permanent in this run's deck — every future fight has a dead card.
**Change:** Curse goes to discard pile, but is **automatically exhausted at end of the fight**. Pay one-fight tax, not run-long.

### 10.5 Leyline Conduit — bump HP to 4
**Current:** 2c 0/3, passive +1 mana/turn.
**Problem:** Our only permanent ramp dies to a single 3-ATK creature attack.
**Change:** **2c 0/4**. Survives a single front-line trade. Still kill-able by anything bigger.

### 10.6 Ironclad Veteran's floop — affects next 2 cards
**Current:** Floop: next card this turn costs 1 less.
**Problem:** Single-card reduction. Doesn't enable chain plays.
**Change:** Floop: **next 2 cards** this turn cost 1 less. Now you can chain a spell+creature combo for real tempo.

### 10.7 Banking cap — raise default to 2
**Current:** Max 1 mana carries over (Ice Cream relic makes it unlimited).
**Problem:** 1 mana isn't enough to plan a big turn. Compare LoR's 3.
**Change:** Default cap **2**. Ice Cream still uncaps further.

---

## 11. Structural gap — what one new card would fix

Even with the 7 fixes above, we still have NO "**Power**" pattern — a card that stays on the field and ramps EVERY future turn.

### Proposed new card (one card, not ten)

**Riteforge** — 2-cost spell, exhaust, **targeting "self"** (creates a board-resident effect).
- "Stays on the field as a Power. At start of each round, gain +1 mana this turn."
- Counts as a creature for targeting purposes (so enemies can attack & kill it).
- Stats: 0/3. Cannot attack. No floop.

Why this card:
- Mirrors StS Demon Form (permanent value/turn) and HS Wild Growth (permanent mana ramp).
- It IS killable — enemy creatures can chip it down, just like StS Powers can be ended by specific enemy attacks.
- 2-cost is the canonical "Power" investment cost (Inflame, Footwork in StS).
- Single card, not a new tier — slots cleanly into Rare.

---

## 12. What to ask the receiving chat

If you're forwarding this to evaluate the proposal, the key questions are:

1. Do the 7 existing-card edits address the actual problem (compounding mana economy) without breaking other cards?
2. Is Riteforge the right new card, or is there a better "Power"-pattern card design for our 4×4 board?
3. Should banking cap go to 2, or higher (3 like LoR)?
4. Are there other Burning Meadow cards (relics, encounters) this analysis missed that affect the mana picture?

---

## 13. Reference — file paths in the codebase

For anyone implementing changes:

- **Cards**: `scripts/data/CardDB.gd` (single source of truth, `CARD_POOL` dict)
- **Relics**: `scripts/data/RelicDB.gd` (`RELICS` dict)
- **Custom spell handlers**: `scripts/scenes/Combat.gd` → `_resolve_custom_spell()` (search for `match spell_id:`)
- **Mana variables**: `Combat.gd` — `player_mana`, `player_max_mana`, `MAX_BANKED_MANA` constant, `_bonus_mana_next_turn`
- **Banking logic**: `Combat.gd` → `_start_round()`, look for `bank_cap`
- **Floop dispatchers**: `Combat.gd` → `_resolve_floop_ability()`, `match floop_data.type:`
- **On-enter dispatchers**: `scripts/data/KeywordEffects.gd` → `_run_on_enter()`, `match effect.get("type", ""):`
