# Burning Meadow — Combat Redesign

*A structural redesign of the per-fight loop, grounded in the live code (not the stale docs/git). Synthesised from a seven-track design pass. Every change is expressible as a **keyword or a small data-driven dispatch case** — no bespoke multi-branch resolvers.*

---

## 0. The thesis

The game is not broken — **one subsystem is.** The meta layer (seeded map, reward rolls, Discover, pre-fight mutators) is good *input* randomness and orthogonal node types. The shallowness is concentrated entirely in the **per-fight loop**, which violates 5 of the 6 depth properties:

1. **Orthogonality** — ~70 of 104 draftable cards are magnitude-variants of ~11 verbs; the `UPGRADES` dict is 99% "+1/+1 or +value."
2. **No dominant strategy** — the whole hand is discarded each turn (`_discard_hand` @ Combat.gd:4435), mana is abundant, the enemy drips 1 creature/round → **"dump your whole hand every turn" is always correct.**
3. **Scarce resource + readable outcome** — mana resets with ~9 ramp sources; the hand evaporates; combat **auto-resolves** with `board_interactive=false` (`_do_combat` @ :1661) — the player presses End Turn and *watches*.
4. **Input vs output randomness** — combat is full of output randomness (Ranged random target, random effect targets, hound/ricochet/chaos imp).
5. **State-dependent value** — `_resolve_column_attack` (:1717) is column-locked 1v1; the 4×4 is four isolated duels → no emergence.
6. **Snowball** — escalation fires round 8/12 but fights end in 2–3 rounds; every growth passive is uncapped positive feedback; no catch-up.

### "Floop" deflated: it's just an effect

Earlier passes kept calling FLOOP a "signature mechanic." It isn't — it's just **an effect that fires once per turn.** And in the live build it doesn't even toggle: no card carries a `"floop"` data key, so the toggle machinery (`will_floop` @ Card2D.gd:974, `toggle_floop()`, `can_attack()`'s skip @ :1255) is dead code, and every ability just fires as an `on_play` battlecry the instant a creature lands (Combat.gd:3146-3149).

So the only real question is **when an effect triggers** — and "fire on placement" is the *least* interesting option. The better default is **end of turn, after combat** (§1.3): the effect becomes recurring, survival-gated, and reacts to the board combat just left behind. No mythology, no reviving dead code — just a better trigger.

### North star (every change aligns to this)

> Hand **persists** (cards become a managed resource) · mana is **scarce** (you can't do everything each turn) · effects are **aimed/deterministic**, never random · creature value **depends on board configuration** · the board has **anti-snowball/catch-up** · identity stays: **lanes, simultaneous combat, sacrifice.**

### The acceptance test

Play a fight lazily (let everything attack) vs. as thoughtfully as you can (time the right effect, aim the right finisher, place for configuration). **Today they win about equally — that equality is the shallowness, measured.** Every change below is chosen so "thoughtful" reliably and increasingly beats "lazy."

---

## PART I — THE KEYSTONE: economy + effect timing

*Fixes properties 2 and 3. Do this first — nothing else matters until "dump everything" stops being correct.*

### 1.1 Hand persistence (discard-to-N, not full persist)

Full persistence (the Runic Pyramid rule) would just trade "dump everything" for "hoard a perfect 10-card hand." A **capped carryover** gives persistence its benefit (an unaffordable card is still there next turn) without a stockpile, and keeps Runic Pyramid meaningfully better than baseline.

- New constant **`MAX_HAND_SIZE_EOT = 5`** (distinct from the existing hard cap `MAX_HAND_SIZE = 10`).
- End of turn: **retain the whole hand if ≤ 5.** If larger (mid-turn draws pushed it up), the player **picks which 5 to keep**; the rest discard. `retain` and Runic Pyramid bypass exactly as today.
- **Draw changes from fixed +4 to draw-to-a-hand-size.** New constant **`HAND_TARGET_SIZE = 5`**. Each turn: `draw_count = maxi(0, HAND_TARGET_SIZE - _hand.size())` then keep the existing relic/mutator `+=` extras. Holding a card now costs you a draw → retention is a real opportunity cost (this is the half that makes persistence *honest*; without it, hands strictly accumulate and hoarding dominates).

Net feel: ~5 cards seen, ~2–3 affordable, 2–3 carry over, 2–3 drawn fresh — a churning, persistent hand where this turn's unplayed Frost Bolt is next turn's answer.

**`_discard_hand` change (Combat.gd:4435)** — only the *card-disposal* half changes; the per-turn creature-state reset loop (:4447-4456) **runs every turn unchanged**:

```gdscript
const MAX_HAND_SIZE_EOT: int = 5

func _discard_hand() -> void:    # becomes async; call site already awaits via _post_combat_sequence
    var keep_all: bool = _has_relic("runic_pyramid")
    var to_keep: Array[Control] = []
    var trimmable: Array[Control] = []
    for card in _hand:
        if keep_all or card.has_keyword("retain"):
            to_keep.append(card)
        else:
            trimmable.append(card)
    var slots_left: int = maxi(0, MAX_HAND_SIZE_EOT - to_keep.size())
    if trimmable.size() <= slots_left:
        to_keep.append_array(trimmable)             # whole hand fits — no prompt
    else:
        var chosen: Array[Control] = await _await_discard_selection(trimmable, slots_left)
        for card in trimmable:
            if card in chosen: to_keep.append(card)
            else:
                _player_discard_pile.append(_pile_entry(card.card_id, card.deck_uid))
                _animate_card_to_discard(card)
    _hand = to_keep
    # ── UNCHANGED per-turn reset (temp_atk_buff, has_attacked_this_turn, metas) ──
    for c in _all_creatures_both_sides():
        c.temp_atk_buff = 0
        c.has_attacked_this_turn = false
        c.has_flooped_this_turn = false
        c.set_meta("war_cry_swift", false); c.set_meta("shield_wall_thorns", false); c.set_meta("inspire_piercing", false)
        c.update_stat_display()
```

`_await_discard_selection` is a thin clone of the existing modal-pick pattern (`_pick_friendly_creature` @ :5074). In the common case (hand ≤ 5) it never runs — **no extra click on a normal turn.**

### 1.2 Mana scarcity

`_start_round` (:1042-1096) is a 50-line *wall* of +mana clauses; on top of base 3 there are ~12 relic/mutator max-mana sources and 6 ramp spells, most bypassing the existing `mana_cap_cost` brake (which only governs 3 relics today).

- **`base_max_mana = 3` stays flat — no per-act growth.** Against a ~5-card hand, flat 3 = ~2 cards/turn = "leave something undone." Let deck + relics be the only ramp, and cap those hard.
- **Banking cap drops 2 → 1.** Change `MAX_BANKED_MANA = 2` → `1` (Combat.gd:15). Banking stays a small smoothing lever (mana_tide/art_of_war still reward it); it can't fund a burst dump. Ice Cream's uncap stays its identity.
- **Bring every max-mana relic under the existing cap** by tagging it `mana_cap_cost: 1` (or `2`): marathoners_sash, lean_mean, junk_slot, cavalry_sigil, mana_drunkard, bone_hourglass, leyline_conduit. `would_exceed_mana_cap` (RelicDB.gd:566) then makes a hard **+2 non-boss ceiling** real (run max = base 3 + 2 non-boss + 1 boss = **6**, and only by spending relic slots). **Data tags only — no new code.**
- **Cut/cap the ramp spells** (a card may *smooth* a turn, never *profit* into a bigger one):

| Card | Change | Why |
|---|---|---|
| `scrap`, `turbo` | **Cut from draft pool** | 0-cost net-positive-mana = pure ramp |
| `bloodletting` | +2 → **+1 mana** | becomes a real HP-for-tempo trade |
| `recycle` | cap refund at spent cost **−1** | a filter, never a profit |
| `adrenaline` | keep (net-zero mana + draw, Exhaust) | card flow, not ramp |
| `offering` | keep (sacrifice is a real board cost) | ties to sacrifice identity |

All single-number edits in CardDB + the matching resolver lines.

### 1.3 Effect timing: fire end-of-turn (after combat), not on placement

This used to read "revive the floop toggle." Dropped — it was over-engineered. A creature's effect is just **an effect with a trigger**, and the most interesting trigger isn't "when played," it's **end of turn, after combat resolves** (if the creature is still alive).

Why end-of-turn beats on-play:
- **Recurring + survival-gated.** It fires every round the creature lives, so *keeping it alive* matters — placement and protection become the decision (and PART III's positional system deepens exactly that). On-play fires once, then the body is vanilla.
- **It reads the post-combat board.** Resolving *after* the swing means the effect interacts with what just happened — "deal 2 to the weakest survivor," "heal your survivors," "+1/+1 if an enemy died this round." On-play fires into a board that hasn't developed yet.
- **It creates a clock both sides play around.** "If this lives, X happens" → the enemy wants it dead first, you want it protected. Kill-priority is one of the genre's best decision generators, and it's free here.

What this **removes** (good): the interactive "floop window" earlier drafts proposed is **cut entirely** — it was the riskiest part of the plan (an extra click every combat, a drag on pacing, reviving dead code). Effects auto-resolve at end of turn through a hook that **already exists** — `_dispatch_passive_end_of_round()` (Combat.gd:6257). Implementation: route the (formerly-on-play) ability dict to fire there if the creature is alive, instead of at placement (Combat.gd:3146).

Honest caveat: this does **not** make the combat swing itself interactive — you still press End Turn and watch it resolve. That's fine. For a lane deckbuilder, auto-resolving combat is *correct* (it keeps fights fast); the decisions live in **what you commit, where you place it, what you aim pre-combat, and the end-of-turn payoff clock** — not in a mid-combat toggle. Forcing an in-combat decision was over-applying "depth"; the genre doesn't need it.

Two triggers, that's all: **`on_enter`** for effects that genuinely want immediate timing (a removal ping, a pre-combat buff), and **`end_of_round`** for everything that's more interesting as a recurring payoff. Targeted end-of-round effects resolve **deterministically by default** (weakest/strongest — readable, fast) so they stay fire-and-forget, not a post-combat ceremony.

**Keystone implementation footprint:** hand + mana are constants/data tags/one-line edits; effect-retiming is one dispatch reroute (placement → the existing end-of-round hook). No new interactive window, no new bespoke resolver, no dead-code revival.

---

## PART II — THE VOCABULARY: an orthogonal keyword set

*Fixes property 1's foundation. Each keyword is ONE distinct verb, one sentence, implementable as a simple dispatch case. The goal: most cards become "stats + 1–2 keywords" with NO bespoke code.*

Today's 21 entries aren't 21 mechanics. **Mitigation is triple-counted** (armored/shield/last_stand), **round-drift is double-counted** (regenerate/wither), **back-line reach is double-counted** (ranged/piercing — and ranged is *random*), and three entries aren't keywords at all (`slay` is doc-text, `adjacent` is a glossary word, `adj_buff.hp` is dead code at Combat.gd:2408).

### The master keyword set

Reconciled across the vocabulary and positional tracks. **Most reuse mechanics already in the engine** (noted), so they cost ~zero new infrastructure.

| Keyword | Rules text (one line) | Axis | Source / impl |
|---|---|---|---|
| **Armored N** | Takes N less damage from each attack (min 1). | mitigation | exists (Card2D:4256); read N from value. Absorbs shield's role via magnitude. |
| **Last Stand** | First lethal hit leaves it at 1 HP. Once per fight. | survive-once | exists. The one mitigation kept *separate* — qualitatively (anti-burst), not a magnitude of Armored. |
| **Swift** | Attacks in the pre-combat phase, before untapped enemies respond. | timing | exists, unchanged. Pillar. |
| **Thorns N** | Deals N back to each creature that attacks it. | reactive | exists; parameterize N (relics already grant Thorns 2). |
| **Pierce** | On a kill, excess carries to the creature behind, then to the hero. | overflow | exists (`piercing`), deterministic. Absorbs ranged's back-line role. (= the "Overkill" idea.) |
| **Venom N** | Damaging a creature adds N venom; it dies once venom ≥ its current HP. | removal | replaces instant-kill poison with a **counter** (one int + one compare). Makes board state over turns matter. |
| **Guardian** | Adjacent enemies must attack this instead of their normal target. | positional | exists, deterministic, underused → promote. North-star model keyword. |
| **Bulwark N** | Adjacent friendlies take N less damage (min 1) while this is in play. | positional (def.) | **NEW**, but reuses the Royal-Guard adjacency reduction (Combat.gd:1898). Worthless alone, great in a cluster. |
| **Rally N** *(dir)* | Adjacent friendlies get +N ATK. `dir:"sides"` (lateral) or `dir:"front"` (same-column partner). | positional (off.) | = today's `adj_buff` ATK, made **directional** (Combat.gd:2402). Place the buffer *behind* who you want buffed. |
| **Flank N** | +N ATK while an enemy stands directly opposite (same column, either row). | positional | **NEW** — the workhorse. ATK depends on the column you choose to contest. ~7 lines in `_effective_attack` (:2120). |
| **Reach** | Attacks an enemy diagonally (lane ±1, your pick); else straight ahead. | positional | **NEW** — breaks the column lock; lets you gang two attackers on one column. ~12 lines in `_resolve_column_attack`. |
| **Growth N** | Start of round, ATK changes by N (negative = wither). | drift | **merges regenerate+wither** into one signed tick (dispatch_start_of_round). |
| **Regen N** | Heals N HP at start of round, up to max. | drift | optional separate HP-tick knob. |
| **Frostbite** | Target can't attack next round. | disruption | the status behind frost/stun spells & the Bind effect. |
| **Battle Cry** *(on_enter)* | Triggers its on-enter effect when placed. | tempo | today's `on_enter`, renamed; shrink `_run_on_enter` to deterministic/aimed cases. |
| **Reap** *(on_death)* | Triggers its on-death effect when it dies. | death-payoff | today's `on_death`, renamed; shrink to deterministic/aimed cases. |
| **Summon** | When placed, summons a 1/1 token in an adjacent empty lane (your choice). | board-dev | exists; make the lane **aimed/deterministic** (drop `shuffle()` @ KeywordEffects:387). |
| **Slay: {effect}** | When this kills its target, do {effect}. | trigger | promote from doc-text to a real `slay:{}` data field (drives pillage/vampire_lord etc.). |
| **Exhaust** | After it resolves, leaves the fight (not to discard). | economy | exists. More relevant under persistent hand. |
| **Retain** | Stays in hand at end of turn. | economy | exists. A real tempo lever once the hand persists. |
| **Sacrifice / Devour N** | Cost: destroy one of your own creatures (you choose); Devour N scales the effect by the eaten body. | economy/cost | exists via `_trigger_player_sacrifice`; unify the sacrifice cluster behind it. |
| **Structure** | Can't attack/be attacked/be targeted. (Enemy/boss board-objects only — never drafted.) | (non-draftable) | exists, load-bearing in ~10 checks. |

**Cut:** `shield` (→ Armored N magnitude, or a 1-line `has_shield` rider), `ranged` (random → cut; reach role → Pierce; if kept, **deterministic** highest-ATK target), `slay`-as-chip and `adjacent` (dead), `adj_buff.hp` (dead).

Decisions to lock when implementing: (a) whether **Rally** subsumes a separate Flank or they coexist (recommended: coexist — Rally is a friendly aura, Flank is a self-buff-vs-opposite); (b) keep **Regen** separate from **Growth** or fold to one signed stat-and-HP tick. Both are cheap either way.

`KEYWORDS` dict entries (display + desc) are drop-in for KeywordEffects.gd:5; N-valued keywords read `card_data.get("armored", 1)` etc., reusing the existing `wither`-value pattern.

---

## PART III — THE BOARD: positional emergence + aimed effects

*Fixes properties 5 and 4. The 4×4 finally earns its keep, and the dice come out of combat.*

### 3.1 Why columns being isolated kills emergence

`_resolve_column_attack` (:1717) reads only the attacker's own `lane_idx`: it hits the opposing front in that column, else the back, else face. A creature in lane 2 *cannot look at* lane 1 or 3. So a 3/4 trades identically anywhere — **its value is invariant under placement**, and there's nothing to solve when you drop a card. The cross-column riders that exist (adj_buff blob, cleave +1, piercing-down-column, guardian) are thin and auto-resolved.

### 3.2 The fix: three composing positional verbs (all from PART II)

- **Flank N** — `_effective_attack` (:2120) adds N when an enemy stands opposite. A Flank creature in an empty column is vanilla; opposite an enemy it spikes → *which column you contest* is now a decision. Applies to both sides (intrinsic), so place it before the `if not is_enemy` relic branch.
- **Reach** — a branch in `_resolve_column_attack` before the straight-ahead block: attack an enemy front in lane ±1 (chosen at placement, stored as `reach_dir` meta), else fall through to vanilla. A Reach unit in lane 0 threatens one column (edges weak); in lane 1–2, two columns (center strong). Lets you **gang two attackers on one enemy** or slip a trade you couldn't reach straight. `_creature_attacks_creature` is called with the *target's* lane, so piercing/thorns/cleave resolve correctly with no deeper plumbing.
- **Directional Rally** — `_get_adj_buff_atk` (:2402) reads `adj_buff.dir`: default `"sides"` (today's lateral behavior, back-compatible) or `"front"` (buffs the same-column partner in the other row). Turns "drop the bannerman near the blob" into "**put the buffer behind the creature you want buffed**" — and gives the back row a placement puzzle without a front/back power tradeoff.

All three are additive diffs at the three existing chokepoints (ATK calc, target pick, adjacency sum). No new combat phase.

**Lazy vs thoughtful (one board):** Enemy front: Ogre 1/6 (lane 1), Archer 4/1 (lane 2). Your hand: Glaive Thrower (Reach 3/2), Duelist (Flank 2, 2/3), File Leader (Rally front +2, 1/4).
- *Lazy:* Duelist→empty lane 0 (Flank dead, 2/3), Glaive→corner, File Leader→nothing useful. Archer lives, deletes a creature next turn.
- *Thoughtful:* Duelist→lane 1 opposite the Ogre (Flank live → 4/3); Glaive→lane 3, Reach left at the Archer (3 dmg kills the 1-HP Archer without standing in front of it); File Leader→behind the Duelist (→6/3). The threat is dead on arrival and your contested unit swings for 6. **Same cards, same enemy, vastly better outcome — purely from placement.**

### 3.3 Randomness → agency (strict double-win)

The discriminator is mechanical: **does the `randi()` fire before or after the player commits this turn?** Before → input randomness, keep. After → output randomness, fix.

**Player-controlled effects → player-aimed** (reuse the existing aim system — `_targeting_spell`/`_try_resolve_target`, and pickers `_pick_adjacent_friendly`/`_pick_empty_lane`):
- **Hound** (`damage_any`, random) → aim the 2 ("deal 2 to **an** enemy"). It's your cheap precision finisher.
- **Ricochet** (4× random, `targeting:"none"`) → aim the first shot (`targeting:"enemy_creature"`), then chain **deterministically to next-lowest-HP** (keeps the "bounce that finishes the wounded" flavor, removes the dice).
- **Fuel the Pyre** splash → **highest-ATK** enemy (or a click).
- **Chaos Imp / Witch's Brew / Echo** → keep the random *spell roll* (that's the chaos), but **let you aim it** when it's targeted (feed the rolled spell into `_targeting_spell` instead of `_auto_target_for`). "I don't know what I'll cast, but I get to point it."
- **`raise_dead`** → pick which corpse returns (reuse the discover/picker overlay).
- **Player summon/revive placement** → `_pick_empty_lane` at play time; deterministic leftmost-empty for automatic round-tick relic summons.

**Enemy/neutral effects → deterministic, readable** (so the player can plan against them; `_highest_atk_*` helpers already exist at :6759/:6770, add `_lowest_hp_*` 6-line copies):
- Enemy **Ranged** → lowest-HP back, else lowest-HP front, else face ("they finish your wounded").
- Archer `damage_random_player` → **lowest-HP** player creature. `discard_random` → **highest-cost** card. Enemy `copy_friendly` → **highest-ATK**. Enemy devour → **higher-ATK** adjacent. relocate/retreat → **leftmost** empty. Enemy summon lanes → **leftmost-empty** (also fixes `_do_summon`'s on-death `shuffle()` for both sides — nobody "decides" at death, so determinism just makes it readable).
- `_buff_random_enemy_atk` → buff **highest-ATK** (player learns to kill the buffed one first).

**Keep (genuine input randomness):** Snecko Eye's cost re-roll (fires at draw/turn-start, *before* you act), the draw-pile shuffle, relic "which card" offers, Gambler's Coin (resolves at fight start — only its "random enemy" tail → highest-ATK). All identities are preserved; the change is purely *who decides where it lands*. Aiming **is** the power-fantasy.

---

## PART IV — THE OPPONENT: anti-snowball + enemy threat

*Fixes property 6, and makes the new player decisions matter by giving them something to answer.*

### 4.1 Why fights are decided by the opening

(1) `_check_escalation` (:6045) does nothing for normal combat before round **12**, and the double-place gate `ESCALATION_REINFORCE_ROUND = 8` — but fights end at round **2–3**, so escalation is **dead code** in the normal path. (2) `_enemy_place_creatures` (:2605) drips **1/round** (2 only ~33% of rounds, never rounds 1–2) onto 8 slots while the player floods turn 1; the starting board can open with as few as **1** enemy creature. (3) Every growth passive is **uncapped positive feedback** — `riteforge_ramp` (:1007) is board-wide permanent +ATK re-applied every round with no ceiling; `grow_on_attack` (:1703), `grow_on_ally_death` (:2475), `grow_on_any_death` (:7652) likewise. Nothing punishes a runaway board or helps a flooded one.

### 4.2 Four anti-snowball levers

- **A — Front-load enemy presence.** Starting count floor 1 → **2** (`_place_starting_board` :873, base `[3,3,4]`), so the player never gets a free uncontested turn. Highest leverage — it hits the root.
- **B — Response-based reinforcement** (the core rule). Replace the random `max_place` with a **board-deficit rule**: `deficit = player_board - enemy_board`; place 3 if deficit ≥ 3, 2 if ≥ 1, else 1. It's a **rubber band toward parity, not toward an enemy lead** — the enemy only pushes while *behind*, drops to 1/round at parity, so it catches up but can't run away. This subsumes and lets you **delete** the round-8 double-place block (:2510) and the random placement coin-flip (:2614).
- **C — Cap the growth passives** (per-fight ceilings via a meta counter at each grow site): grow_on_attack +5, grow_on_ally_death +6, grow_on_any_death +5/+5, riteforge +5 board-wide (capped on the *source* Riteforge so two still stack two caps). A fight lasts ~3 rounds, so +5 is still a strong payoff — the cap binds **only** in the already-won runaway case.
- **D — Underdog's Rally** (catch-up that isn't a freebie): once per fight, only while HP ≤ 40% **and** behind on board, give all friendlies +1 ATK *this round* and draw 1. Doubly-gated + one-shot + temp buff → buys one turn to rebuild, can't flip the snowball the other way.

### 4.3 Enemy threat = telegraphed, column-anchored intents

The intent system already exists and is **already deterministic** (`_assign_intents` :5728 walks a fixed `intents` cycle; resolved at end of turn via `_resolve_intents` :5804 — i.e. shown ~a full turn ahead). It's just under-used. Give enemies a small vocabulary of **positional, telegraphed threats** that interact with the player's placement and end-of-turn effects:

| Intent | Badge (telegraph) | Resolution | The puzzle |
|---|---|---|---|
| **SMITE** | `⚔ Lane n: 5` | 5 dmg to player column n (front/back/face) | wall lane n, kill the caster, or eat 5 |
| **MUSTER** | `MUSTER L n` | summon into named **leftmost-empty** lane next round | pre-occupy lane n to deny it |
| **BREACH** | `BREACH L n` | next round gains Pierce + targets emptiest column | wall the lane before it resolves |
| **OVERRUN** | `OVERRUN` | front row +1 ATK **this round only** | trade now or chump-block |

Each is one `match` case, same complexity as existing CHARGE/GUARD. Make MUSTER/SUMMON lanes **leftmost-empty** (not `randi()` @ :5845) so the target is always pre-readable. Plus reactive anti-flood passives like **`shield_on_summon`** (when the player summons, enemy front row gains Armored this round — reuses the `temp_armored` meta + its cleanup at :6087): directly taxes the turn-1 flood, teaching the player to *sequence* summons rather than dump.

---

## PART V — THE CONTENT: card pool, upgrades, effect catalog, relics

*Fixes property 1 fully, and rebuilds the content on the new vocabulary. Slowest track — do it last, but it's what makes everything feel distinct.*

### 5.1 Collapse the card pool (104 → ~58)

~70 of 104 draftable cards are magnitude/rider variants of 11 verbs. The worst clusters (with real ids):

- **Aimed creature damage (~20):** strike/slash/fireball/flame_bolt/blood_tithe/reckless_charge/quick_shot/shove/smite_spell/pillage/hex/holy_smite/banish + on-enter creatures.
- **Team +ATK (9):** war_cry/inspire/dark_pact/kings_command/overwhelming_force/battle_hymn + adj_buff bodies.
- **Free ramp (9), raw draw (7), enemy sweep (8), stun (4), sacrifice-payoff (4), copy/Discover (4 rarity hats).**

Collapse to **~34 creatures + 24 spells**, each a distinct verb. The test for every kept card: ***"what can ONLY this card do?"*** Crucially:
- **Damage spells → ONE flexible aimed-damage card + a few with an *orthogonal rider*** (execute / strip / remove / convert). No two cards share "deal N to a creature" as their whole identity.
- **The economy shift does load-bearing cutting:** persistent hand kills the raw-draw cluster (keep only `provision`); scarce mana kills the free-ramp cluster (keep only `leyline_conduit`, a *killable body*). These aren't trims — they're cards built for an economy we're deleting.
- **Every kept spell becomes a data dict** (`spell:{type, value, slay:{…}}`), so the 40-case `_resolve_custom_spell` block (Combat.gd:3402-3847) shrinks to ~15 generic handlers — directly satisfying the no-bespoke-code constraint.

### 5.2 Rebuild the upgrade philosophy

**Old:** `+` = bigger number. **New:** `+` adds a **VERB, OPTION, TARGETING MODE, CLAUSE, or removes a restriction** — never a flat stat. The two correct entries today are the template (`adaptable+`→Swift, `gambit+`→Retain). **Delete the +1/+1 fallback** in `get_plus_upgrade` (a flat fallback re-creates the anti-pattern; a missing entry is now a content bug). Examples:

```gdscript
"strike":  {"add_clause": "second_target", "desc": "Deal 4 to a creature. +: also deal 4 to a second creature."},
"fireball":{"add_targeting": "any",        "desc": "Deal 3 to face — or split it between face and one creature."},
"harpy":   {"add_keywords": ["ranged"],    "desc": "Swift. Ranged."},
"frost_bolt":{"add_targeting":"all_enemies","desc": "No enemy creature can attack next round."},
"war_cry": {"add_clause": "grant_swift",   "desc": "All friendlies +2 ATK and Swift this round."},
"patch_up":{"remove_condition": "if_full", "desc": "Heal 4 and draw a card (no longer needs full HP)."},
```

`_apply_plus_upgrade` (RunState.gd) needs generic keys the data-driven handlers read: `add_keywords` (exists), `add_clause`, `add_targeting`, `remove_condition`, `token_keywords`.

### 5.3 The effect catalog (10 orthogonal verbs)

These are just **effects** — each a distinct verb, triggered either `on_enter` (immediate) or, better, `end_of_round` (recurring, after combat — §1.3). The dispatcher shrinks from ~50 cases (43 dead) to **10 live verbs**, spanning all six axes; targets resolve **deterministically by default**, with click-to-aim reserved for a few high-impact ones:

| # | Name | Verb | Target | Axis |
|---|---|---|---|---|
| 1 | **Strike** | deal N to one enemy | click any enemy | damage (single) |
| 2 | **Volley** | deal N to opposing column + flanks | auto (deterministic) | damage (spread) |
| 3 | **Rally** | +X/+X to an ally this round | click adjacent friendly | buff |
| 4 | **Bulwark** | give an ally Shield | click adjacent friendly | buff (def.) |
| 5 | **Reposition** | move to an empty lane in row | click empty lane | move |
| 6 | **Conscript** | summon a token in a chosen lane | click empty slot | summon |
| 7 | **Devour** | eat an adjacent ally → gain its ATK+HP | click adjacent friendly | sacrifice |
| 8 | **Empower** | die → +X ATK permanent to an ally | click adjacent friendly | sacrifice |
| 9 | **Disarm** | steal X ATK from the opposing creature | auto (column) | disruption |
| 10 | **Bind** | opposing creature can't attack next combat | auto (column) | disruption |

`_resolve_effect_ability` is a trimmed sibling of `_resolve_on_play_ability`: it reads the effect dict and fires from `_dispatch_passive_end_of_round()` (Combat.gd:6257) for end-of-round effects, or on placement for `on_enter` ones. Echo Staff and Reaper's Scythe re-point onto this dispatch.

> **Latent bug found in scope:** the current `devour_adjacent` path (Combat.gd:1552) deals 999 without calling `_trigger_player_sacrifice`, so Bone Pile / Butcher's Cleaver / `ON_PLAYER_SACRIFICE` silently miss it. Worth a standalone patch regardless.

### 5.4 Relics: cut the "+1" tax, keep the build-definers

~30 combat relics are flat "+1 to an existing effect" — under scarce mana they matter even less. **Merge** the keyword-+1 relics (swift_boots/fortress_stone/briar_amulet/piercing_crown) into one **Keystone Sigil** ("each act, choose a keyword to *double*", reusing the totem_pole act-pick UI), and the spell-+1 relics (worn_spellbook/pyromaniac_ring/war_horn) into one **Arcane Focus** (first spell/turn, bonus scales with board state). **Cut** on_enter/on_death/token-HP +1s.

**Template for what to keep/build** (the rubric — runic_pyramid, blueprint, death_card, snecko_eye, mime already fit): *a build-defining relic changes a RULE or opens a STRATEGY, not a number; its payoff scales with how you build; it creates a new decision loop; it's still one simple hook; it has a natural ceiling/tax (anti-snowball).* **Litmus:** if you can express it by editing a number in a formula, cut/merge it; if it requires changing a branch in the turn/combat flow, keep it.

New relics tuned to the new economy (each one simple hook): **Patient Hand** (a card held a full round costs 1 less + buffs — rewards persistent hand), **Hoarder's Lantern** (end a turn with mana → next creature lands shielded — rewards scarce-mana restraint), **Surgeon's Glove** (a *clean* 0-HP kill draws a card — rewards aimed play), **Vanguard Banner** redesigned (front row can't be dropped below 1 by back-row enemies + hardens with Thorns — a rule, not a stat), **Phalanx Link** (a front creature and the one behind share keywords — column combo), **Gravewright Seal** (first sacrifice each turn returns to hand — sacrifice recursion).

---

## PART VI — Sequencing

Implement in this order; each stage is playable and the earlier stages dominate the value.

1. **Keystone (PART I).** Persistent hand (discard-to-5, draw-to-5) + scarce mana (flat 3, bank 1, cap the ramp) + retime effects to end-of-turn (§1.3 — no in-combat toggle). *This alone kills "dump everything."* Nothing else matters until this lands.
2. **Aim the randomness (3.3).** Cheap, isolated, strictly better. Mostly one-line targeting swaps reusing existing helpers.
3. **Anti-snowball + enemy threat (PART IV).** Front-load + deficit reinforcement + growth caps + telegraphed column intents — so the new decisions have something to answer.
4. **Positional emergence (3.2).** Flank + Reach + directional Rally — three additive diffs at existing chokepoints; makes the 4×4 a placement puzzle.
5. **Vocabulary cleanup (PART II)** then **content rebuild (PART V):** collapse the pool, rebuild upgrades to add verbs, the 10-verb floop catalog, cut/merge relics. Slowest, last — it's what makes the surviving content feel distinct.

**Acceptance, restated:** at each stage, re-run the lazy-vs-thoughtful test. When "thoughtful" reliably beats "lazy" — aiming the finisher, committing the creature whose end-of-turn payoff matters, placing for Flank/Reach, answering the telegraphed SMITE — you have depth. And lanes, simultaneous combat, and sacrifice are all still 100% yours.

---

*This document supersedes the stale DESIGN_DOCUMENT.txt and the combat sections of CLAUDE.md for redesign purposes. Line refs are to the live build on `feature/visual-polish-and-content`; re-verify before editing, as the files drift.*
