# Reward distribution pass — 2026-07-29

**Status: AUDITED. §8 items 1–3 BUILT (see §11); items 4–7 still specced.** Four-agent audit (run
census / outside practice / event pool / durable power). Every structural claim below was re-verified
against code by hand; claims that remain estimates are marked. Two claims the agents made were WRONG
and are corrected in §7 — read that before acting.

The complaint: *a run hands the player too many flat stat increases; it should be more fun.*

---

## 1. The measurement

A route walks **18 stops per act = 54 per run**, of which **21 are fights** (constant by construction;
only the General mix varies). That yields **≈43.5 payoff screens per run** and **≈122 discrete payoffs**.

Census (map generator ported to Python, 3000 accepted acts; EventDB 46 events / 144 choices / 214
effects and CardDB's 222 `UPGRADES` parsed programmatically):

| bucket | sources | per run | share |
|---|--:|--:|--:|
| **A · FLAT STAT** — a number that changes no decision | 16 | 34.1 | **28.0 %** |
| **B · RESOURCE** — gold/potions | 11 | 46.0 | **37.7 %** |
| **C · NEW OPTION** — a card, a slot, an action | 7 | 14.6 | 12.0 % |
| **D · RULE CHANGE** — rewrites a beat of the game | 12 | 23.3 | 19.1 % |
| **E · SHAPING** — thin / transform / de-curse | 5 | 3.8 | **3.1 %** |

**65.7 % of everything received is a number. 31.1 % changes what you can do. Shaping is 3.1 %.**

The four most-repeated payoffs are **38 % of all payoffs and all four are numbers**: post-fight gold
(21×/run), the 3-kill epithet (~10×, *est*), the mutator gold bonus (8.2×), the potion drop (7.5×, *est*).

## 2. Calibration against the genre

| game | flat-scalar share of permanent rewards | how the bump is made a decision |
|---|--:|---|
| Slay the Spire | **<10 %** | priced in build currency (Bonfire Spirits: a *rare card* for +10 max HP) |
| Cobalt Core | ~0 % | no permanent scalar layer at all |
| Hades / Inscryption / Griftlands / Into the Breach | ~20 % | directed, priced, or slot-capped |
| Monster Train / Balatro / Wildfrost | ~25–30 % | slot scarcity; irreversible commitment |
| Dead Cells / Backpack Battles | ~40 % | scroll colour = build declaration; spatial adjacency |
| **Burning Meadow** | **65.7 %** | — |

We are 25 points past the worst-case end of the genre. Note the top of the table is not ascetic — StS
still *has* a max-HP reward; it just never gives it away.

Sourcing caveat: the per-game shares are analyst/community inference. No first-party statement from
Mega Crit, LocalThunk or Motion Twin on that intent was found. There is also **no published
"meaningful decision every N minutes" rule** — only shipped cadences.

## 3. The actual diagnosis — it is PLUMBING, not content

The content is largely good. What is broken is the layer that *delivers* it. Four independent
mechanisms each demote interesting content that already exists and is already wired:

**(a) The casino cannot pay anything but coins.** 19 gamble events carry **40 % of all event branches**,
and **55 of their 60 branches pay only gold or HP**. Cause: `Event.gd` makes **26 hardcoded
`gain_gold()` calls**; 15 of 17 minigame resolvers physically have no other wire. Two general payout
arms already exist and work — `win_effects` (read at exactly one place, `Event.gd:5230`) and
`bank_relic`/`bank_relic_at` (read at exactly one place, `Event.gd:4733`) — and each is used once.
`EventDB.gd:480` spends the one general-purpose arm on `gold 55, heal 5`.
*Strip the gamble events out and the other 27 events run ~60 % option-changing.* The pool is fine.

**(b) Relic rarity weighting inverts the pool's own intent.** By composition the live pool (111 relics)
is healthy — 30.6 % RULE CHANGE. But `RELIC_RARITY` was built to tame outliers by scarcity, and the
outliers *are* the rule-changers, while every unlisted trickle falls through to default weight 6. On an
actual draw: rule-change **30.6 % → 23.2 %**, conditional-number **41.4 % → 55.2 %**.
`FOUNDATION_RELICS` — the guaranteed first relic of every run, the one that should declare an identity —
is 52.5 % conditional number and 15 % flat.

**(c) An entire relic tier is unreachable.** `roll_campaign_relics()` (`RelicDB.gd:862`) is the only
thing that rolls the **utility** tier. Its sole caller is `roll_relic_reward(tier)`, and the only two
call sites in the codebase (`Event.gd:2458`, `Event.gd:3886`) both pass `"boss"`. Nothing passes
`"utility"`. **`blacksmiths_hammer`, `olympians_mark`, `centaur_heart`, `stardust_vial` and `drill_book`
are implemented, gated, iconed and unobtainable.** `drill_book` is the only relic that touches
veterancy, and is tagged `"rare"` — plainly meant to be drawn.

**(d) The forge is a number machine.** Across 186 hand-crafted `UPGRADES`: pure-flat 62 (33.3 %) +
number-bump 75 (40.3 %) = **73.7 % flat. Only 6 cards in the whole pool gain a keyword on their "+".**
The forge fires ~8.9×/run across five screens, so it is one of the loudest repeat offenders.

## 4. Six "+" descriptions promise a keyword the delta never grants — FIXED, see §11

Verified by comparing each base card's `keywords` against its `UPGRADES` desc; none of these deltas
carried `add_keywords`, so the forged card did not do what its own text said:

| card | base keywords | "+" desc claims | the lie |
|---|---|---|---|
| `hexblade` | *(none)* | "Sniper." | **Sniper** |
| `warding_stone` | guardian, on_enter | "Guardian. Thorns." | **Thorns** |
| `plague_rat` | poison | "Poison. Lifesteal." | **Lifesteal** |
| `torchbearer` | adj_buff | "Formation." | **Formation** |
| `bramble_stockade` | thorns | "Guardian. Thorns." | **Guardian** |
| `vengeance` | *(none)* | "Overrun." | **Overrun** |

`torchbearer` was briefly ruled a false positive on the theory that `adj_buff` renders as "Formation".
It does not: `adj_buff` displays **"Adj. Buff"**, and `formation` is a SEPARATE keyword with a
different effect (start of round: +1/+1 this fight if a friendly stands beside it). Always check
`KeywordEffects.KEYWORDS[kw].display` before ruling a desc correct — several display names differ
from their id, and `lifelink` likewise displays as "Lifesteal".

## 5. Veterancy — the only choice sits at the rung that barely fires

Rung 1 (3 kills) = a cosmetic epithet. Rung 2 (6) = flat +1/+1. Rung 3 (10, war school) is the only
decision in the ladder. Kills record **only** on a real deck creature's own strike — spells, On-Death,
Thorns, Doom and tokens count for nothing. *Estimate* (no kill telemetry exists; of 32k playlogs only
one has 4+ fights): ~4–5 qualifying kills/fight × 21 fights ≈ 90–105 kills spread over ~12 creature
uids → **rung 3 fires 0–3 times per run, late or never**. And `drill_book`, the relic that would pull
it forward, is in the unreachable tier.

## 6. Target distribution

| bucket | now | target | direction |
|---|--:|--:|---|
| A · FLAT STAT | 28.0 % | **10 %** | keep it, but price it — never give it away |
| B · RESOURCE | 37.7 % | **28 %** | gold accrues ~34×/run and converts at only ~3.3 shops |
| C · NEW OPTION | 12.0 % | **20 %** | |
| D · RULE CHANGE | 19.1 % | **30 %** | mostly a weighting fix; the content exists |
| E · SHAPING | 3.1 % | **12 %** | the most under-served bucket in the game |

## 7. Two audit claims that are WRONG — do not act on them

1. **"15 relics manufacture or discount Command, violating the fixed-Command rule."** No. The house
   rule bans *cards* that manipulate Command (no X-cost, no cost reduction, no HP-for-Command).
   CLAUDE.md states Command "starts at 3/turn; **can grow via relics**." Relic Command grants are
   sanctioned and long-standing.
2. **"13 spells whose forge is `{cost:-1}` use the exact lever the house rules ban."** No. CLAUDE.md
   specifies the *default* forge fallback as "+1/+1 creature or **-1 cost spell**". A -1-cost forge
   delta is the sanctioned design. It is still **boring**, which is a fair design critique and is
   counted in the 73.7 % — but it is not a rule violation and must not be reported as one.

Related correction of framing: the census called it a defect that `Reward.gd` is skipped by normal
fights (11.6 of 21). It is deliberate — `Combat.gd:15718` reads *"Normal holds pay out inline and march
straight back to the map — no card pick, no interstitial screen. Pace is the point."* **Do not restore
a reward screen to every fight.** The inline payout needs to stop being a bare number; the pacing
decision stands.

## 8. Work order

Ranked by (share of the problem fixed) ÷ (risk + effort). 1–3 are plumbing and carry almost no design risk.

1. **Wire the casino to the prize table.** Copy the `straw_game` `win_effects` arm into the other
   minigame resolvers; add `bank_relic`/`bank_relic_at` to the four push-your-luck games
   (`crown_game`, `deal_game`, `field_game`, `sack_game`), which currently have escalating pots and no
   terminal prize. A config arm, not a new engine. **Fixes ~40 % of event branches.**
2. **Free the utility tier** — retag those 5 relics `"combat"`, or give `roll_campaign_relics` a real
   caller. Pure recovery, zero design work, +5 relics including the veterancy relic.
3. **Invert the relic weighting** — stop scarcity-taxing the rule-changers; recut `FOUNDATION_RELICS`
   so the guaranteed opener declares an identity instead of paying a conditional number.
4. **Adopt a forge contract** — *a "+" may raise numbers but never __only__ numbers.* Tribe-appropriate
   keyword as the default delta. Gate with a probe that also fails the five lying descs in §4.
5. **Re-order veterancy** — war school to rung 1 (3 kills), +1/+1 to rung 2, a second chosen mod at 10.
   Moves the ladder's only decision to the rung that actually fires.
6. **Reweight potions** — 43 % flat, and `healing` alone is ~19 % of every roll. Drop its weight 3→2 and
   convert the three flattest.
7. **Schedule reward TYPE across the row skeleton** (the Hades technique: aim a target ratio rather than
   rolling each door independently). Cheap here because the 18-row skeleton is already fixed — this is
   what makes §6 a guarantee instead of a hope.

## 9. Techniques to draw on (from the outside-practice pass)

Direct it (which card?) · cap it (slot scarcity) · price it in build currency · push-your-luck ·
shared wallet · rider/covenant · convert the stat into a verb · make the scalar a build declaration ·
1-of-3 with a real SKIP · gate it behind a build condition · non-linear stacking · spatial visibility
(free on a 4×4 board: "+1/+1 while in the front row") · steepen the curve so scalars can't keep up ·
author identity up front and let rewards tune it · reserve the scalar for the archetype payoff.

**Bycer's slate rule**: never put a major and a minor upgrade in the same 1-of-N — the answer is
pre-determined, so the choice is fake. Worth auditing every 1-of-3 slate against.

## 10. The model already in the repo

`WritDB.gd` (war chest, 2026-07-28) has **zero flat-stat entries and zero lump-sum gold**, and states
the law outright: *"Economy as a standing RULE, never a lump sum."* It is organised as four role axes.
That pass solved this problem for the run's opening tile and was never applied to the road.
Copy it outward. (Note CLAUDE.md still describes the retired pre-WritDB pool.)

---

## 11. BUILT — 2026-07-29

### Forge honesty (6 cards)
Six `UPGRADES` deltas named a keyword in their desc that they never granted; `decorate_keywords`
gilds keyword words in rules text and hangs the hover glossary on them, so each was a live glossary
link to an effect the card did not have. In every case the BASE desc omits the keyword and the "+"
desc adds it — the text was the intent, the data was the bug. Added the missing `add_keywords`:

| card | keyword now granted |
|---|---|
| `hexblade` | `sniper` |
| `warding_stone` | `thorns` |
| `plague_rat` | `lifelink` (displays "Lifesteal") |
| `torchbearer` | `formation` |
| `bramble_stockade` | `guardian` |
| `vengeance` | `overrun` |

Note `sniper` also has a legacy `card_data.sniper` bool, but `Combat._is_sniper` checks
`has_keyword("sniper")` FIRST and the flag is explicitly the old-save path — the keyword alone is
correct. `torchbearer` was briefly ruled a false positive on the theory that its base `adj_buff`
renders as "Formation"; it does not — `adj_buff` displays "Adj. Buff" and `formation` is a separate
keyword with a different effect. It was a real defect.

### The Reliquary now draws the campaign tier
`roll_campaign_relics()` is the only thing that rolls tier `utility`. Its sole caller is
`roll_relic_reward(tier)`, whose only two call sites both pass `"boss"` — so the tier was unreachable
and five implemented relics were stranded. The four reachable ones are granted BY NAME from
`WritDB.gd` (war chest), which is what disguised the gap.
[`Treasure.gd`](../scripts/scenes/Treasure.gd) now rolls the campaign tier when
`current_node_type == "reliquary"`, falling through to the field pool when the small tier runs dry.
This un-strands `blacksmiths_hammer`, `olympians_mark`, `centaur_heart`, `stardust_vial` and
**`drill_book`** — the only relic that touches veterancy, which directly eases §5.

### Six casino games retired, keys retained
Owner's call: cut the games where a player cannot tell what is happening. Retired **morra**
(`the_old_game`), **three men's morris** (`the_sentrys_board`), **quoits** (`the_gibbet_green`),
**liars' dice** (`the_provost_marshal`), **1-D Lights Out** (`the_signal_line`), and **`cut_game`**
(`widows_tray`) — the last on redundancy, not legibility: it and `deal_game` are the same high-card
game twice.

KEPT the three that are hard-but-legible — the Short Straw (Nim), the Quartermaster's Scale, the
Strongbox (Mastermind). You know what you are DOING in all three; they are hard to master, not hard
to parse. That is a different problem from morra.

**Event KEYS were retained and only the game/prose swapped**, per the 2026-07-21 precedent — the
`seen_texts` web is dense (`the_bone_pit` is referenced by 5 other events, `the_short_straw` by 3)
and deleting keys would tear the shared-world threads. The minigame ENGINES in `Event.gd` are left
orphaned-but-harmless rather than ripped out, same as the `DrumHead`/`PowderKeg` painters; a data-only
change cannot break a compile.

Each replacement is a road event paying options or shaping, one concept each:

| event | new concept | pays |
|---|---|---|
| `widows_tray` "The Widow's Keeping" | a dead soldier's kit | `grant_keyword_pick` armored / swift; blue `add_card_id` standard_bearer |
| `the_provost_marshal` "The Dead Marshal" | he strikes names off the roll | `remove_choice_all_copies`; blue curse removal; `add_card_id` pikeman |
| `the_old_game` "The Old Game" | the dead still run their drill | `grant_keyword_pick` thorns; blue `veteran_swap`; `upgrade_choice` |
| `the_gibbet_green` "Gallows Green" | crows trade, and they choose | `transform_choice` 1; blue 2; the Hanged Man gift (now free — the 10g toll is gone) |
| `the_signal_line` "The Signal Line" | the beacon chain answers | `add_card_id` lookout; `copy_card`; blue Beacon Watch gift |
| `the_sentrys_board` "The Sentry's Post" | a man to stand a post nobody relieved | `sacrifice_pick` reward `relic`; blue `add_card_id` revenant; starter removal |

This deploys all THREE handlers the audit found built-but-never-called: `remove_choice_all_copies`,
`sacrifice_pick` (its `"relic"` arm trades a creature for a relic — a real decision), and it more
than doubles `add_card_id` usage, which before this pass appeared exactly ONCE in the whole 46-event
pool (`old_bones`).

Every flat-stat consolation branch in the six ("Heal 4/6 HP", "Take 10/12 gold", "Gain 3 max HP") was
deleted rather than rehomed.

### Verification
`tools/run_safe_probes.ps1` → parsecheck / copy_lint / event_art **ALL PASS**.
`_probe_events` walks 46 events, fires 394 effects, checks 100 gates, no `SCRIPT ERROR` / `Invalid`;
all six rewritten events walk clean. Copy lint initially FAILED the new Marshal desc on unglossed
"provost" and "muster" (COPY_STYLE §10) — reworded to "dead marshal" / "roll-call".

### Not yet done
§8 items 4–7: the casino payout plumbing for the SURVIVING games (`win_effects` / `bank_relic`
generalisation), the forge contract, the relic reweighting, and type-scheduled rows.
