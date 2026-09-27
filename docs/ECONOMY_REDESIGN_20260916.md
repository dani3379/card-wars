# The Economy Redesign — Command ramp, fixed draw, rescaled curve (2026-09-16)

> **PHASES 3, 4 AND 5 ARE BUILT (2026-09-16).** The interim state the banner
> below warns about is OVER — the cost rescale has landed, so the pool now spans
> the ramp instead of piling under it. What went in:
>
> - **The cost rescale** (§2.2). Derived by `tools/_probe_cost_rescale.gd`,
>   reviewed, then applied — **173 of 236 entries moved**. Draftable curve is now
>   exactly on target: `1:30 2:49 3:49 4:35 5:24 6:10` (15/25/25/18/12/5%).
>   The tool's `--verify` mode is a STANDING GATE, not a one-shot: it asserts
>   every hero opener can act on round 1 and that no tier is empty or swallowing
>   the pool. See §2.3 for the method and the two things it got wrong first.
> - **The forge floor** — `_apply_plus_upgrade` floored cost at 0, and sixteen
>   forges carry `cost: -1`, so every cost-1 spell forged to FREE. Floor is 1
>   now (the house rule Discover already used), and the three cards whose ONLY
>   delta was that discount got real upgrades — they had become "+"s that
>   advertised a bonus they did not carry.
> - **Relics**: Deep Satchel, Basilisk Eye and Marathoner's Sash all still
>   described the old economy in player-facing text, and all three are live in
>   skirmish via `NET_RELIC_POOL` (an explicit allow-list that does not consult
>   `retired`). Basilisk Eye's cost roll moved 0-3 → 1-5 and now lives in
>   RelicDB, because three sites rolled it.
> - **Shop** `SELL_PER_COST` 8 → 4 (§5.5), **BotBrain** `SAVE_VERSION` 1 → 2 to
>   discard vectors trained on the old economy, **SkirmishBot**'s deck filter
>   (it excluded everything over cost 4, which silently removed the top two
>   tiers), and **BoardEval**'s flat Command weight, now scarcity-scaled.
> - **The ramp is finally TAUGHT** — a `command_ramp` lesson plus a Command-seal
>   tooltip that names next round's figure. Nothing explained the single rule
>   the whole cost curve rests on.
>
> Green: `parsecheck` · `cost_rescale` · `upgrade_merge` · `dominance` ·
> `content_census` (0 unreachable) · `card_rules_fit` (459 faces, none clipped) ·
> `net_relic_parity` · `invariants` · `runaway` · `hand_dim` · `dismiss` ·
> `tutorial` · `copy_lint` · `board_eval` · `bot_brain`.
>
> **§2.1'S GATING QUESTION IS ANSWERED — the top of the curve is live content.**
> 65 autorun fights after the rescale: **mean 7.72 rounds, median 7, min 4, max
> 15**, with **82% reaching round 6+** and 94% reaching round 5+. So the 6-cost
> tier is reachable in the large majority of fights, not only in lost ones, and
> `COMMAND_RAMP_CAP` stays at 6. Fights did not shorten under the rescale either
> (Phase 1 measured 7.96 / median 8 — this is inside noise).
>
> Won fights ran 7.38 rounds against lost fights' 7.84 — nearly the same length.
> **Do not cross-read that against `PILOT_DIFFICULTY_20260915.md`'s "won ~4,
> lost 9-14"**: that is a different instrument with a different driver, and
> comparing across the two is the mistake this file keeps warning about.
>
> **Win rate went 33% → 25%. IT WAS REAL, and §3c explains why.** The guess
> written here first — that it was probably the driver, which played greedily in
> hand order with no curve awareness — was tested and **refuted**: fixing that
> pilot to scan descending-by-cost reproduced the deficit almost exactly, and the
> new `unspent` column showed **0.00 Command left over at rounds 2-5**. The
> player was spending its whole turn and still losing the board.
>
> The cause is structural: **only the player pays Command**, so a +58% price rise
> is a unilateral nerf (§3c). §3a's guess that `OPENING_MUSTER_RAMP_RELIEF` would
> want to go back to 0 was exactly backwards — the hold needed SLOWING, not
> speeding. Done in §3c; plain-combat win rate **8/30 → 16/30** on the same seed.
>
> **§3c's FIRST published numbers were void and have been replaced** — the driver
> had a second fault (it played round 1 out of a one-card hand, because the deal
> is staggered on timers while `phase` already reads PLAYER_TURN). Re-measured on
> the settled driver the tuning held and got stronger, and the "round 1 is a dead
> turn" finding was **retracted**: it was the instrument. See §3c.
>
> **`_probe_golden` re-blessed LAST**, per §7, after the above was measured.
> Note while doing it: **`tools/golden/` is UNTRACKED** — not gitignored, just
> never `git add`ed. A golden master that is not in version control cannot be a
> regression net for anyone but the machine that wrote it; a fresh checkout has
> no baseline and the alarm can never fire. Worth fixing, and not fixed here
> because adding files to the repo is the owner's call.
>
> **Still deliberately NOT done: §5.12's balance cascade.** Hero HP,
> `ENEMY_HP_SCALE` and `ENEMY_BODY_HP_BY_ACT` are denominated against the old
> card sizes and must not move until this is measured — moving both at once
> makes neither attributable. Famine (§5.7) is flagged in place for the same
> reason: its `value: 1` was a fifth off the hand and is now HALF the draw.

> **PHASE 1 IS BUILT (2026-09-16).** Ramp + fixed draw + the net mirror are in.
> `parsecheck` · `copy_lint` · `event_art` · `tutorial` · `net_relic_parity` ·
> `net_authority` · `dismiss` all green. **§2.1's gating measurement came back
> GOOD: 24 autorun fights, mean 7.96 rounds, median 8, min 5, max 14** — so the
> ramp's top IS reachable in an ordinary fight and the 6-cost tier is not
> stillborn. No crashes or softlocks.
>
> **THE INTERIM STATE IS DELIBERATELY BAD AND SHOULD NOT BE JUDGED YET.** Two of
> three dials are in. Round 1 grants 1 Command while 86% of the pool still costs
> ≥2, so the opening hand is nearly all unplayable — that is the *cost rescale*
> (Phase 3) missing, not a defect. Do not tune anything off a playtest until
> Phase 3 lands.
>
> Not yet run: `_probe_golden` (digests WILL differ — bless last, per §7),
> `_probe_skirmish_combat`, `_probe_runaway`, `_probe_bot_*`.

> **PHASE 2 IS BUILT (2026-09-16).** §3's "the enemy must ramp too" is in:
> `Combat.hold_arrivals_for_round()` (the hold's per-round body budget now ramps
> the way its opponent's Command does) and `OPENING_MUSTER_RAMP_RELIEF` (one body
> off every round-1 formation). Measured before/after with a purpose-built
> instrument — **§3a**. `parsecheck` green.
>
> **It also found a defect it deliberately did NOT fix — §3b: twelve encounters
> summon bodies through a passive that spends none of the hold's budget**, so
> THE HOLD'S HAND has never actually been "across every source" as its own header
> claims. Left for a separate, separately-measured pass.

**STATUS: PLANNED, IN PROGRESS.** Owner's decisions, taken 2026-09-16:

| dial | before | after |
|---|---|---|
| Command | **3 flat**, banks ≤2 | **1 on round 1, +1 per round** (Hearthstone) |
| Draw | persistent hand, **refill to 5** | persistent hand, **draw 2/turn, no refill** |
| Cost curve | 0–5, 47% of cards ≤1, one card at 5 | **rescaled to span 1–6** |
| Hold's deployment | **flat 2/round from round 1** | **ramps 1 → 2, opening −1 body** (§3) |

Three dials, one system. They are not independently tunable and must land together —
the reasoning for that is §1.

---

## 1 · Why all three, and why the current mix is incoherent

Researched 2026-09-16. Every shipped card game of this shape sits in one of **two**
coherent packages, and Burning Meadow is currently the only thing mixing them:

| game | resource | hand | draw/turn |
|---|---|---|---|
| Slay the Spire | 3, flat | **discarded every turn** | **5** |
| Hearthstone | 1→10 ramp | persistent | **1** |
| Marvel Snap | 1→6 ramp | persistent | **1** (opens on 3) |
| Legends of Runeterra | 0→10 ramp | persistent | **1** |
| **Card Wars** (our stated combat model) | stockpiles to 10 | persistent | **1** |
| **Burning Meadow (today)** | **3, flat** | **persistent** | **refill to 5** |

**The law: a ramping resource pairs with a persistent hand and a low fixed draw. A
flat resource pairs with a fresh hand and a high draw.**

The pairing is mechanical, not conventional. If the resource ramps, expensive cards
need somewhere to *wait* — the persistent hand is the waiting room, and a low draw
suffices because you can only afford 1–2 plays a turn anyway. **The hand thickens
while you are poor and empties once you are rich, and that accumulation IS the arc.**
If the resource is flat there is nothing to wait for (a card you cannot afford now you
cannot afford later), so holding is pointless, and the game bins the hand and deals a
big fresh one, making each turn a self-contained puzzle.

Burning Meadow took its combat from Card Wars (persistent hand, draw 1, stockpiling
mana) and its economy from Slay the Spire (flat 3), then added refill-to-N, which
belongs to neither. **The persistent hand has nothing to wait for, and the refill stops
it accumulating even if it did.** That is the flatness — it is structural, not tuning.

### 1.1 Why refill-to-N is the load-bearing defect

Refill-to-5 is *self-correcting*: you play 3 cards, you draw exactly 3 back. Three
consequences, all measured:

- **Throughput is pinned** at ~2.9 plays/turn regardless of what Command says. So
  **ramping Command against refill-to-N does almost nothing** — the hand hands back
  exactly what you spent and no more.
- **Draw is dead as a payoff.** A draw effect only means you refill less next turn.
  (CLAUDE.md has said so for months; this is the cause.)
- **The discard-mark verb is free**, which is the only reason `MAX_DISCARD_MARKS`
  needed to exist — see §5.9.

### 1.2 Measured baseline (do not re-derive)

- Cost curve, live count over 254 pool entries:
  `0:26 (10%) · 1:93 (37%) · 2:99 (39%) · 3:26 (10%) · 4:9 (3.5%) · 5:1 (0.4%) · 6+:0`
  — **47% cumulative at ≤1, 86% at ≤2, one card at the top, nothing above 5.**
- Plays/turn 2.72–3.00; **Command left unspent 0.02–0.40 per turn** (three separate
  instruments agree). The turn is spent essentially perfectly.
- Banking fires on **12% of turns** despite a cap of 2, a tutorial and net mirroring.
- `docs/COMBAT_SHAPE_PASS_20260727.md` §3.3 concluded independently: **"Cost is the
  only lever that both reduces plays and creates an arc."**

---

## 2 · The new numbers

```
COMMAND_START           = 1     # round 1
COMMAND_RAMP_PER_ROUND  = 1
COMMAND_RAMP_CAP        = 6
HAND_DRAW_PER_TURN      = 2     # fixed; no refill-to-N
OPENING_HAND            = 5     # unchanged
MAX_BANKED_MANA         = 2     # UNCHANGED FOR NOW — see §6.1
```

Command by round: `1 · 2 · 3 · 4 · 5 · 6 · 6 · 6 …`

### 2.1 THE RISK THAT DECIDES WHETHER THIS WORKS

Measured 2026-09-15/16 (`docs/PILOT_DIFFICULTY_20260915.md`, 26 fights, two seeds):

- **Fights WON ran ~4 rounds.** Fights LOST ran 9–14. Mean 6.9–7.7.
- Point of no return: **ahead until round 1.4 of a 10.4-round fight.**

**A four-round fight only ever reaches Command 4.** Taken literally, that makes every
5- and 6-cost card in the rescaled pool reachable *only in fights already lost* — a
whole card tier that appears exclusively in defeats.

**The counter-argument, and it is a prediction rather than a measurement:** at 1
Command on round 1 both sides deploy far more slowly than at a flat 3, so fights should
*lengthen on their own* toward the 6–8 rounds the ramp needs. That is the single most
important thing to measure after Phase 1, and it is why Phase 1 ships alone.

**If fights do NOT lengthen past ~5 rounds, the curve tops at 5 and `COMMAND_RAMP_CAP`
drops to 5.** Do not author the 6-cost tier until the round-length number is in.

### 2.2 The cost mapping rule

**Cost N is first affordable on round N.** That is the whole legibility contract and
the reason a rescale is worth its cost. Target shape:

| cost | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| target share | 15% | 25% | 25% | 18% | 12% | 5% |

A flat "+1 to everything" is **not** the rescale — it preserves the glut (93 cards
would pile at 2, 99 at 3). The 192 entries currently at cost 1–2 must be **spread by
power**, which needs a per-card judgement over stats and keywords. Do this with the
existing power machinery (`tools/_probe_cardpower.gd`, `tools/card_audit/`), not by
hand, or it is 254 arbitrary decisions. **Derived, then reviewed** — the derivation is
the draft, not the answer.

### 2.3 · BUILT — how it was actually derived, and what the derivation got wrong

`tools/_probe_cost_rescale.gd`. Not a from-scratch re-derivation: the current costs
were themselves tuned against `_probe_curve`'s budget line, so re-deriving from that
line mostly hands them back, and would fight several hundred deliberate decisions to
do it. **What is wrong with the pool is COMPRESSION, not ordering** — 93 cards share
cost 1 and 99 share cost 2, so the designer's relative judgements are intact and
merely stacked on top of each other.

So each card is ranked by `power + 2.0 × old_cost` and the ranking is cut at the
target quotas. The old price is kept as a strong PRIOR (2.0 = the budget line's own
slope, two body-points per Command) rather than an absolute gate.

**Four things the first drafts got wrong, each caught by a check rather than by eye:**

1. **A strict band mapping starved eight of the ten hero openers.** With 83% of the
   pool at old 1–2, hitting the target shape forces *every* old-2 card to cost 3+ —
   and openers are built from exactly that population. Fixed by making the old cost
   a prior, by giving **starters their own curve** (they are not a sample of
   anything, they are a designed opening hand), and finally by enforcing the
   constraint outright: `_relieve_starved_openers` marks a deck's weakest starter
   down to 1 and **prints every override**. Left to fall out of the distribution,
   the starved opener moved between heroes on *every* tweak to the power model —
   which is the signal that a constraint was being treated as an outcome.
2. **The denominator was wrong.** §2.2's shape describes what a player is OFFERED,
   and `roll_card_reward` never offers a starter. Measuring over a denominator
   including 39 undraftable cards drags the curve down and hides how expensive the
   real offers became — the C26 mistake.
3. **A third of the pool was ranked by a constant.** 78 of 87 spells carry
   `spell: {type: "custom"}`; the effect lives in a Combat.gd resolver and *nothing
   in the data says what it does*. Keying off `spell.type` scored them all
   identically, which sorted them **alphabetically** inside their cost band. Power
   is now read out of the printed rules text — the only machine-readable statement
   of what a card does, and the contract the player prices it by.
4. **Three model faults, all general rather than per-card:** `exhaust` was treated
   as repeatable (one-shot bombs priced as though castable every round); a
   *symmetric* board wipe was scored as pure upside (No Quarter, which destroys
   your own line too, came out the strongest card in the game); and keyword value
   was flat, so three cheap keywords on a small body out-priced a 6/6 — a 3/2 Swift
   was being sold at a bomb's price. Keyword worth now rides the body it sits on.

**The cross-check is `tools/_cardpower_ranking.txt`** — a *measured* lift over a
fixed gauntlet for 120 of these cards, which knows nothing about stat lines because
it played the games. **Read its confound before reading its number:** that probe
stacks four copies into a ten-card deck under the *old* flat-3, so cheap cards get
an engine and expensive ones clog the draw. That bias runs along COST, the exact
axis a rescale moves. The probe therefore reports the sim-vs-old-cost rank
correlation (−0.24, real but modest) and a **within-band** agreement figure that
holds cost still — the same cancel-the-nuisance-variable move as the duplicate
pairing in `reference_ai_variant_measurement`. Raw agreement 50%, within-band 50%;
the residual disagreements are the review queue and are listed by the tool.

---

## 3 · The enemy must ramp too

Owner's call, and it is load-bearing rather than thematic. The solo enemy **has no
economy at all** — no `enemy_mana`, no `_enemy_hand`; every `ENEMY_POOL` entry is
`cost: 0` and EncounterDB deck entries carry no cost field
(`COMBAT_SHAPE_PASS_20260727.md:155`). **Its only resource is `max_place`.**

So the enemy already ramps — in *bodies*, via the escalation ladder
(`Combat.gd:187-190`: double-place from round 4, elite +1 ATK/round from 6,
reinforcements +1/+1 from 7). That ladder is tuned against a player doing ~3 plays a
turn. **At 1 Command on round 1 the player does one**, so without a matching change the
enemy simply out-deploys the player from the opening and the measured
"decided by round 1.4" problem gets worse.

**`max_place` and the opening muster must start smaller and ramp in lockstep with
Command.** This is not optional and it is not a later phase.

### 3a · BUILT, and measured before/after (2026-09-16)

Two changes, both in `Combat.gd`, both named dials rather than re-picked literals:

- **`hold_arrivals_for_round(r)`** — static and pure, for the same reason
  `command_for_round()` is: the budget is read by the placement, the telegraph and
  the opening, and three restatements of one curve is how they drift. Replaces the
  flat `ENEMY_ARRIVALS_PER_ROUND`. Gives `1 · 1 · 2 · 2 · 2 …`, and
  `HOLD_ARRIVALS_SURGE_BONUS` (+1) replaces the old second flat ceiling
  `ENEMY_ARRIVALS_SURGE`, so a licensed spike keeps its exact old meaning without
  handing a round-2 surge the round-6 allowance.
- **`OPENING_MUSTER_RAMP_RELIEF = 1`** — one body off every round-1 formation,
  floors kept (an elite never opens on one body; act-3 keeps its full wall).

**The old behaviour is restored in full by round 3** — base 2, spike 3, exactly as
before. Only the opening and rounds 1–2 move. That is deliberate: §4 says the
snowball is the larger problem, so this pass must not make the late game harder.

#### The instrument
Win rate cannot see this. `_probe_autorun` is ~77% deck-insensitive and loses every
elite and boss regardless of balance, so a tempo change reads as nothing — measured
here, overall win rate moved 33% → 33%. So the measurement is **bodies on board at
the top of each player turn**, plain combats only, 30 encounters, same seed both
arms. The A/B was run by setting the two new dials to their off values
(`HOLD_ARRIVALS_START = 2`, `RELIEF = 0`), which reproduces the previous behaviour
exactly — no file juggling, no stash.

| round | Command | player | enemy BEFORE | enemy AFTER | gap BEFORE | gap AFTER |
|---|---|---|---|---|---|---|
| 2 | 2.3 | 0.50 | 2.47 | **1.73** | **+2.03** | **+1.23** |
| 3 | 3.4 | 1.47 | 3.30 | **2.30** | +1.83 | **+0.83** |
| 4 | 4.5 | 2.03 | 3.97 | **3.14** | +2.27 | **+1.10** |
| 5 | 5.3 | 2.68 | 3.83 | 3.14 | +1.86 | **+0.46** |
| 6 | 6.4 | 3.35 | 3.84 | 3.00 | +1.04 | **−0.35** |
| 7 | 6.4 | 3.32 | 3.62 | 3.45 | +0.38 | +0.14 |
| 8 | 6.3 | 3.33 | 3.93 | 3.80 | +0.93 | +0.47 |

**Round 2 is the line that matters** — `PILOT_DIFFICULTY_20260915.md` measured the
fight decided by round 1.4, and the player was meeting the hold's formation
**0.43 against 2.47**, a 5.7:1 deficit at precisely that moment.

**The second-order effect is the real prize and was not designed for:** the
PLAYER's own body count rises (round 5 `1.97 → 2.68`, round 6 `2.80 → 3.35`)
without a single player-side change. Fewer enemy bodies means the player's
creatures survive their clashes, so the board compounds instead of being traded
off every round. Parity now arrives around round 6.

#### Read this before retuning
The residual `+1.23` at round 2 is **mostly the missing cost rescale, not the
hold**: 86% of the pool still costs ≥2 against 1 Command, so the player's 0.50 is
a hand they cannot play, exactly as the banner at the top of this file warns.
**`OPENING_MUSTER_RAMP_RELIEF` is the dial to re-read once Phase 3 lands** — a
rescaled curve changes what one Command buys, which is the whole quantity it
compensates for. It may well want to go back to 0.

### 3c · BUILT — the hold re-slowed after the cost rescale (2026-09-16)

§3a's closing note said `OPENING_MUSTER_RAMP_RELIEF` was "the dial to re-read once
Phase 3 lands, and may well want to go back to 0." **It wanted the opposite, and the
reason is that this economy is ASYMMETRIC.** The player pays Command for bodies; the
hold pays nothing — every `ENEMY_POOL` entry is `cost: 0` and its only resource is
`max_place`, denominated in *bodies*. So raising mean card cost 1.76 → 2.79 (+58%)
was a **unilateral nerf**: the player fields far fewer bodies for the same Command
while the hold's budget is untouched, because nothing about it is priced in Command.
Phase 2 matched the two curves against the OLD pool; Phase 3 moved the pool out from
under it.

#### The instrument had to be fixed TWICE, and the second fault outlived the first report
**Fault 1 — scan order.** The pilot scanned the hand in DEAL ORDER. Under the old
curve, where 86% of cards cost ≤2, that cost nothing. Under a 1–6 curve it decides
the turn — spend 2 on the first card met, then fail to afford the 4-drop behind it.
Both drivers now scan **descending by cost** (biggest affordable first, then top up),
which is the greedy that maximises Command SPENT. That target is chosen deliberately:
this probe measures BODY COUNT, and cheapest-first would maximise exactly its own
metric.

A new **`unspent` column** is the oracle for the pilot rather than the game — body
count alone cannot separate "the hold out-deploys the player" from "the pilot could
not spend its turn."

**Fault 2 — THE PILOT WAS PLAYING A ONE-CARD HAND ON ROUND 1**, and the `unspent`
column is what exposed it, one report too late. `Combat._start_round` STAGGERS the
deal: only the first card is drawn inline, and every one after it lands on a
`get_tree().create_timer(0.08 * i).timeout.connect(draw_one)`. That stagger has **no
headless branch, no reduce_motion branch, and is not scaled by `anim_speed`** — while
`phase == PLAYER_TURN` is already true. Both drivers started playing the instant
input was accepted, so on round 1 they saw ONE of five dealt cards; if it cost 2+ at
Command 1 the pass played nothing and returned.

Round 2 onward hid it completely, because the hand is PERSISTENT: it carries unplayed
stock forward and is never down to the single inline draw again. So the fault lived
exactly where the measurement was most load-bearing and nowhere else.

The fix is `_settle_hand()` in both drivers — poll until `_hand.size()` HOLDS, with a
bounded budget. Stability polling rather than a computed deal window, because
`draw_count` is decided by the ramp plus four relics plus two mutators, and restating
that arithmetic in a probe is the duplicate-rule pathology this codebase has already
paid for twice. **Measured effect: round-1 unspent Command 0.90 → 0.27, and round-1
deployment roughly doubled (0.30 → 0.60 bodies).**

**THE LESSON IS THE ONE THIS HARNESS KEEPS TEACHING: `phase == PLAYER_TURN` IS NOT
"THE TURN IS READY".** It is the same class as the `round_number >= 1` guard both
drivers already carry in `_wait_for_player_turn` (enum 0 is also the default, so a
half-built scene reports ready) and the same class as `reference_settle_until_stable`
— a readiness flag answers about the FLAG, never about the state the flag implies.
Every one of these has cost a false report; none was catchable by a state assertion,
because the state was legitimate at the instant it was read.

#### The change
- **`OPENING_MUSTER_COMBAT_RELIEF = 2`** — a second body off a PLAIN hold's opening.
  Split from `OPENING_MUSTER_RAMP_RELIEF` rather than raising it, because this probe
  samples plain combats only *by design* (elites and bosses carry authored kits). One
  dial across all three types would be tuned on evidence that by construction cannot
  see two of them — and at 2 it drops an act-1/act-2 **keep to a one-body opening**,
  which nothing in this measurement would have reported.
- **`HOLD_ARRIVALS_RAMP_EVERY` 2 → 3** — the drip reaches its old flat 2/round at
  round 4 instead of round 3. The CAP is untouched, so a long fight still escalates
  to exactly the pressure it always had; only the slope into it moved.

#### Measured, same seed (4242), `--relics=0`, RE-RUN on the settled driver
The table below **replaces** the one first published here. Those figures were taken
before Fault 2 was found and are void; the conclusion they supported survived the
re-measurement unchanged, and got stronger.

| round | gap before | gap after | player before → after | enemy before → after |
|---|---|---|---|---|
| 2 | +2.03 | **+0.77** | 0.60 → 0.60 | 2.63 → **1.37** |
| 3 | +2.33 | **+0.83** | 0.97 → **1.20** | 3.30 → **2.03** |
| 4 | +3.00 | **+1.17** | 0.90 → **1.40** | 3.90 → **2.57** |
| 5 | +3.24 | **+1.45** | 0.86 → **1.38** | 4.10 → **2.83** |
| 6 | +2.48 | **+1.55** | 1.48 → **1.62** | 3.96 → **3.17** |
| 7 | +1.68 | +1.65 | 1.84 → 1.75 | 3.53 → 3.40 |

Plain-combat win rate over the same 30 encounters: **8/30 → 16/30**. Rounds 7–8 are
small and the survivor sets differ between arms (n drops to 19–25), so read rounds
2–6 and treat the tail as directional only.

**The qualitative signal is stronger than the gap numbers.** Before, the player's
board *declined* across the fight — 0.60 · 0.97 · 0.90 · 0.86 — it could never hold
ground it took. After, it *climbs*: 0.60 · 1.20 · 1.40 · 1.38 · 1.62, with **no
player-side change of any kind**. That is the compounding §3a saw: fewer enemy bodies
means the player's creatures survive their clashes and are still standing next round.

#### The residual, stated plainly — and one retraction
**RETRACTED: "round 1 is a dead turn, 0.90 of 1.0 Command unspent."** That was Fault
2 in this document's own instrument, not a property of the game. On the settled
driver round 1 leaves **0.27** unspent and deploys **0.60** bodies — identical in both
arms, as it must be, since round-1 deployment is player-side and no hold dial can
touch it.

A residual remains and is worth naming honestly: 0.27 of 1.0 is still ~27% of the
opening turn's Command left on the table, because a mid-run deck is mostly *drafted*
pool cards and the rescaled pool's median is 3, so some five-card hands genuinely hold
nothing castable for 1. That is a far smaller claim than the one it replaces, and it
is well inside what a real deck ought to cost you. `_probe_cost_rescale --verify`
cannot see it either way: it gates the pure ten-card hero opener, not a deck carrying
16 drafted cards. **If it is ever pursued, the lever is the draftable curve's cost-1
share (currently 15%), not the hold — but the case for pursuing it is now weak.**

### 3b · BUILT — the passive summon spends nothing (2026-09-16)

> **STATUS: fixed in two halves, and gated by `tools/_probe_hold_budget.gd`.** The
> first half (below, as originally written) covers START-of-round passives. It was
> built and it works. The second half is that the same argument is **false for the
> end-of-round dispatcher**, which this section's own reasoning got wrong — see
> *§3b-ii* after the original text. Neither half was visible to any existing probe,
> which is why the gate came with the fix.

`_enemy_arrivals_this_round` is incremented at **exactly one site**, inside
`_enemy_place_creatures`. But bodies also arrive from **encounter passives**, which
call `_summon_enemy_token` / `_summon_enemy_token_with_keyword` /
`_place_enemy_card` directly. **Twelve encounters do this** — `bandit_camp`,
`haunted_crypt`, `necromancer_tower`, `the_bellringer`, `the_crone`,
`the_black_tide`, the four rival/amalgam kits and the hero-mirror fights.

So THE HOLD'S HAND — whose own header says "Bodies the enemy may commit in ONE
round, **across every source**" — has never covered every source. It predates this
work and was survivable at a flat 3 Command; under a ramp it is the difference
between a fight and a flood. `bandit_camp` summons 1/round from round 2 and 2/round
from round 4 on top of the drip, and it is **the only act-1 plain combat that loses
in the soak** (14 rounds, against 10W/1L for the rest of act 1).

**The fix is NOT a clamp.** A passive that announces a banner and then summons
nothing because the drip already spent the budget is the silent-refusal class
`_probe_silent_refusal` exists for. The right shape is the reverse: the passive is
the hold's signature and always fires, but it **spends** the budget, so the drip
later in the same round yields to it. The ordering already supports this for free —
`_start_round` resets the counter, *then* dispatches passives; the drip runs at end
of round.

Deliberately **not** bundled into this pass: it changes twelve encounters, and
moving it in the same commit as §3a would make both unattributable — the discipline
§8 is built on. It wants its own pass and its own before/after.

#### 3b-ii · The half this section got wrong, and the gate that found it

The paragraph above says the ordering "already supports this for free — `_start_round`
resets the counter, *then* dispatches passives; the drip runs at end of round." **That
is true of the start-of-round dispatcher and false of the end-of-round one.**
`_dispatch_passive_end_of_round` fires from `_post_combat_sequence` *after*
`_enemy_place_creatures` has already spent, so its `_spend_hold_hand()` landed on a
counter `_start_round` was about to zero: the spend happened, and had no consequence
anywhere. Three fights leaked past their ceiling on that alone — **the_bellringer,
the_crone, the_black_tide**, every one of them an end-of-round summoner.

**The fix carries the DEBT instead of wiping it.** `_start_round` now does
`_enemy_arrivals_this_round = maxi(0, _enemy_arrivals_this_round - _hold_round_cap)`,
where `_hold_round_cap` is the ceiling the round that just ended actually ran under
(surge included), **recorded by `_enemy_place_creatures` rather than recomputed** —
the spike condition is decided there out of state `_start_round` would otherwise have
to restate, and a second spelling of one rule is how two copies drift. This is not a
new rule; it is the stated one applied to a summon that arrives after the drip has
gone. There is no "later this round" left to yield in, so the drip yields *next*
round. The signature still always fires.

**Measured (`_probe_hold_budget --verbose`, bodies committed through round 11):**

| encounter | before | after |
|---|---|---|
| the_black_tide | **26** (over its own 25 allowance) | **18** |
| the_bellringer | 15 | 15 |
| the_crone | 17 | 17 |
| bandit_camp | 21 | 21 |

So it corrected **exactly the one encounter that was violating the contract** and left
the others untouched — their end-of-round summons never pushed past the ceiling, so
they never incurred a debt. Note the correction overshoots a clamp (26 → 18, not
26 → 25): the Black Tide summons every round end, so its drip stays suppressed. That
is the design as stated — the signature is what the hold spends its hand on.

**Win rate cannot see any of this and must not be used to judge it**: every act-3
boss scores 0% in `_probe_encwin` with or without the change, which is the
documented deck-insensitivity of these drivers, not a verdict on the fight.

#### The gate, and what it is NOT

`tools/_probe_hold_budget.gd` drives six summoning encounters and counts arrivals
**independently of the counter** — by diffing live enemy instance ids — because
asserting `_enemy_arrivals_this_round <= cap` would be satisfied perfectly by a
counter that is never incremented, which is the original bug exactly.

Three things it cost to get right, each a wrong answer first:
1. **The bound is CUMULATIVE, not per-round.** A per-round ceiling flags every
   end-of-round summoner, because the debt mechanism explicitly permits a transient
   overshoot. Asserting per-round was testing a property nothing ever promised.
2. **The formation is exempt wherever it lands.** Headless auto-takes the field, and
   TAKE THE FIELD is the line whose opening is dealt *reactively* — so at a General
   or a keep the authored formation arrives at the **end of round 1** and reads as
   three or four reinforcements against a round-1 hand of one. The exemption is keyed
   off the game's own `_opening_muster_pending`, not off "before the first turn".
3. **The 8-slot board is a second ceiling and a real confound.** With only the front
   row cleared each window, a full board fizzled summons, arrivals fell to zero, and
   the original defect escaped to a single failing check. The gate now clears the
   whole enemy line — not a play policy, the experiment holding the confound still.

**Mutant-verified in both directions**: disabling the passive spend (the original
defect) and wiping the debt (the second half) each produce 5 failing checks with a
margin that widens as the fight runs. **Known slack, stated so nobody reads it as
tighter than it is:** the allowance adds `HOLD_ARRIVALS_SURGE_BONUS` for every window,
because the spike condition lives inside `_enemy_place_creatures`. It is a flood
detector, not a ledger — a leak well under one body per round would hide inside that
term. The printed `slack` column shows how close each fight actually ran.

### 3d · THE HOLD MAY NOT BRING A LID (2026-09-16)

**The rule the codebase already stated, enforced on round 1 only.** `_clash_lane_pass`
resolves *"opposing front in this column, else opposing back, else face"* — so the
player's win condition is reachable ONLY through a column with BOTH rows empty.
`_deal_opening_muster` has capped itself at `open_lane_cap` since 2026-07-27 for
exactly this reason ("The hold may bring a wall; it may not bring a lid"), and
**the reinforcement drip never inherited it**: its slot list ends *"Always fall
through: any open front slot, then any open back slot."* `open_lane_cap` appears
nowhere outside the opening.

**Why it surfaced now, and it is §5.12's premise being false.** §5.12 assumed "if
the pool is rescaled upward, bodies get bigger". Measured against HEAD, the
rescale moved **cost only**: mean ATK `1.55 → 1.55`, mean HP `2.34 → 2.34`, mean
cost `1.51 → 2.40` (+59%). Bodies did not get bigger — **the same bodies got more
expensive**, so the player fields fewer of them and clears the enemy line more
slowly. Saturation that was previously rare became the normal end state.

**Measured** (`_probe_encwin`, plain combats, act-correct drafted decks, n=135):
**49% of losses end with 7–8 of 8 enemy slots filled and the enemy face still at
69% HP.** Act-2 `ash_hounds` lost at `ehp=16/16` — eight rounds without landing a
single point of face damage. That is not a hard fight, it is a sealed one, and it
is the mechanism behind the `bandit_camp` "board, not budget" note in §3b.

**The fix** is `HOLD_LEAVES_A_PATH` + `_hold_would_seal_board()`, consulted by all
three enemy slot-choosers (`_find_empty_enemy_slot`, `_pick_empty_for_summon`, and
the drip's placement loop). Three properties worth keeping:
- **It is "do not take the LAST clear column", not a body cap.** It binds only
  while a clear column still exists, so a board already sealed by closed ground or
  a scripted opening is left alone and the hold can never be frozen out of a state
  it did not create. Max enemy occupancy becomes 6 of 8; the 7th body reseats or
  fizzles exactly where it already fizzled at 8.
- **Checked live at the placement site, not while building `slot_priority`.** That
  list is built once and consumed as bodies land, so a build-time test reads a
  stale board and lets the second body of a wave close the column the first left.
- **It binds the HOLD only.** A player sealing their own board denies nothing.
- **SET-PIECES ARE EXEMPT**, and that is a rule about what the rule is *for*. A
  set-piece's win condition is its OBJECTIVE, not the face — of
  `_sp_evaluate_objective`'s five kinds only `break_face` wants a path to the face
  at all. Closed ground also narrows the usable columns, so the "last clear
  column" test bites immediately and quietly disarms the scenario. Caught by
  `_probe_setpiece_fight`: it broke `the_pay_column`, whose whole point is that an
  **unscreened ward dies and the army withdraws** — with the hold forbidden the
  seat opposite it the ward survived and the authored failure path could no longer
  happen. An authored scenario prints its own rules; a general fairness floor must
  not overwrite them.

It is also, in the catch-up-mechanic literature's terms, a **diminishing-returns**
anti-snowball rule rather than a comeback bonus: it caps how much board advantage
can convert into "the fight is over but grinds for nine more rounds" (§4).

**Measured effect: losses with a saturated board go 46% → 0%, and every remaining
loss sits at exactly `ebodies=6` — the cap the rule predicts, observed. IT DOES
NOT MOVE THE WIN RATE, and that is the finding.** Matched arms, plain combats:
baseline n=180 **65%**, lid-on n=59 **66%**; enemy HP remaining at a loss is
**71% in both**. An earlier read of "84% vs 67%" was taken at n=32 and was
small-sample noise that regressed as the sample grew — **do not quote it.**

So **saturation was a SYMPTOM, not a cause.** The player was already losing; the
board filled up as a consequence, and unsealing it did not convert into wins or
even into getting measurably further through the enemy's HP. Keep the rule anyway,
on correctness rather than balance grounds: it enforces an invariant the engine
already states, and it removes the genuinely unwinnable-by-construction case
(`ash_hounds` at `ehp=16/16`, eight rounds without a point of face damage) where
the player cannot see why nothing is working. **It is a legibility and
floor-of-fairness fix, not a difficulty lever — do not count it as one.**

### 3e · ELITES ARE A DIFFERENT PROBLEM, and the numbers say so

Same instrument, `--type=elite`: **16% win rate, and 0% of those losses are
saturated** (enemy face at 70%). So elites are not sealed boards — they are lost
on raw power. **Do not reach for the lid rule there; it is not the lever.**

**The agent was checked FIRST, and it is not the explanation.** The obvious
objection is that `encwin`'s FIXED policy drinks no potions ("no potions, no
discards, no Command banking") while a real player reaches an elite with three —
so an elite nerf derived from that bot would be derived from the instrument, the
validity rule `Personas.gd` exists to enforce. Tested rather than assumed:

| arm | n | win rate |
|---|---|---|
| fixed policy (no potions) | 72 | **19%** |
| `--persona=curve` (drinks) | 59 | **20%** |

**A potion-drinking agent does not rescue elites.** ~19–20% is therefore a
property of the fights, not of the bot's abstinence, and it is the real blocker on
finishing a run — a route carries several elites plus a keep. The remaining agent
gaps (targeted potions need the `_auto_target_for` seam the spell path already
has; no discards; one-ply placement) are worth closing, but they are no longer a
reason to withhold an elite retune. **This is the measurement §5.12 was waiting
for, and the direction is now known: the rescale cut player throughput while
elite HP and `ENEMY_BODY_HP_BY_ACT` stayed denominated against the old economy.**

### 3f · THE ITEM AUDIT (2026-09-16) — `tools/_probe_item_sense.tscn`

A report pass over RelicDB/PotionDB asking whether items still MEAN what they say
after the ramp. Most of §5.6 has since been conformed; what it actually found:

**RULED FINE, having been checked rather than assumed:**
- Draw relics' text is conformed (`deep_satchel` / `snecko_eye` / `tome_of_many`
  all read as flat adders, which is what they now are).
- **`marathoners_sash` is NOT the free +2 §5.6 predicted.** Its `player_mana = 1`
  round-1 clamp still fires, so the trade is real — merely *halved* (it used to
  cost 4 Command on round 1, now 2), and its printed text stays true. §5.6's
  "the downside evaporates" is too strong; correct it rather than act on it.
- **0 map-only potions**, so `_probe_silent_refusal`'s standing "dead bottle in
  the belt" trap is not currently live.
- The two NUMBER-MISMATCH hits (`scouts_emblem`, `lichs_bargain`) are heuristic
  false positives — a delta named against an absolute, and a magnitude spelled as
  the word "twice". The check is noisy by construction; read it, don't gate it.

**THE ONE THAT DOES NOT MAKE SENSE — the empty-board Command relics.** Both are
keyed off an EMPTY board, so they pay maximally on round 1 and taper as the board
fills: exactly inverted against a resource that starts at 1 and grows.

| relic | round-1 grant | against base 1 |
|---|---|---|
| `cavalry_sigil` | +2 (both edge columns clear) | **+200%** |
| `junk_slot` | +1 (8 empty slots ≥ 4) | +100% |
| both | **+3** | **4 Command on round 1** |

A flat +1 was a constant +33% against a flat 3 forever; under the ramp the same
+1 is **+100% on round 1 and +17% at the cap**. So these relics silently break the
"cost N is first affordable on round N" contract the entire cost rescale rests on
— on round 1, of all rounds. **Not changed here**, because the shape of the fix is
an owner's design call, not a measurement: the candidate is a ramp-aware ceiling
("a relic may at most double your Command this round", i.e. bonus ≤ base), which
keeps each relic's identity and scales itself, versus re-pricing the two grants.

**Also noted, deliberately not acted on:** `NET_RELIC_POOL` deals **five relics
flagged `retired`** (`last_breath`, `cavalry_sigil`, `snecko_eye`,
`marathoners_sash`, `tome_of_many`). That is defensible — `retired` governs
CAMPAIGN reward rolls and the skirmish pool is a separate curated allow-list — but
it is load-bearing in a way worth knowing before touching it: `arsenal_relic_max()`
IS `NET_RELIC_POOL.size()`, so removing entries lowers the lobby's ARSENAL ceiling
and moves the lap rule with it.

---

## 4 · What this does NOT fix

Stated plainly so nobody expects it to. **"Ahead until round 1.4 of 10.4 rounds" means
the board is decided in the first two rounds and then grinds for nine more.** That is a
snowball-resolution problem. No Command curve reaches back into round 2, so **the
comeback complaint is not addressed by this work** and remains open. On the evidence it
is the larger of the two problems.

---

## 5 · EVERY SITE THAT CHANGES

### 5.1 Core constants — `scripts/scenes/Combat.gd`
| line | symbol | change |
|---|---|---|
| 129 | `MAX_BANKED_MANA` | unchanged (2) — §6.1 |
| 130 | `HAND_DRAW_PER_TURN` | 4 → **2**, and becomes LIVE (it is currently dead under `PERSISTENT_HAND`) |
| 131 | `MAX_HAND_SIZE` | unchanged (10) |
| 138 | `PERSISTENT_HAND` | stays `true`; **its meaning changes** — persistent + fixed draw, no longer draw-to-N. Update the const header, it documents the old A/B. |
| 143 | `HAND_REFILL_TARGET` | **retired as a per-turn target**; retained only as the opening-hand size |
| 160 | `MAX_DISCARD_MARKS` | see §5.9 |
| new | `COMMAND_START` / `COMMAND_RAMP_PER_ROUND` / `COMMAND_RAMP_CAP` | added |

### 5.2 The two `_start_round` blocks
- **Command block, `Combat.gd:4034-4100`.** `player_max_mana = _ctx_max_mana() + …`
  gains the ramp term. `_ctx_max_mana()` (`:1183`) is the solo/net fork and is where the
  base comes from. Ten conditional relic arms sit in this block and all stay.
- **Draw block, `Combat.gd:4138-4168`.** Replace the draw-to-N branch
  (`draw_count = maxi(0, target - _hand.size())`) with a fixed `HAND_DRAW_PER_TURN`.
  **Keep the "always deal at least one" guarantee** — under a fixed draw it is
  redundant, but `_refill_draws_this_turn` (`:709`) is read by Scroll of Greed and the
  `ON_PLAYER_DRAW` reactive as a "free refill ceiling" and must stay coherent.

### 5.3 `scripts/state/RunState.gd`
`base_max_mana = 3` at **:200** (declaration), **:398** (`start_new_run` reset),
**:2373** (save-load default, `int(data.get("base_max_mana", 3))` — legacy saves).
`get_max_mana()` at **:1702** returns `base + RelicDB.get_boss_mana_bonus(relics)`.
**The ramp belongs in Combat, not here** — this is the per-run base, not the per-round value.

### 5.4 Net parity — the highest-risk surface
The client's Command is modelled **host-side** by a second implementation. If it does
not mirror the ramp exactly, one player's Command pool silently diverges — the exact
pathology `_probe_net_relic_parity` was built for.
- `scripts/net/NetPlayerState.gd` — `MAX_BANKED_MANA` **:10**, `base_max_mana`
  **:24/:73-74/:106**, **`begin_turn` :127-130** (must learn the round number — it
  currently has no concept of one).
- `scripts/net/SkirmishState.gd` — `BASE_MAX_MANA` **:453**, `base_max_mana` **:323**.
- `scripts/net/NetMatch.gd` — config envelope **:347** (`base_max_mana`), **:362**
  (`max_banked_mana`). Mirrors defaults in its own initializers because it registers
  **before** SkirmishState in autoload order.
- `scripts/net/CombatNet.gd` — 20 refs; bot banking **:1235/:3696**, `_bot_refill_hand`,
  `combat.player_max_mana` **:200**, HUD sync **:4122**.
- `NetPlayerState.effective_cost` — mirrors `_effective_cost`; rescale-sensitive.

### 5.5 Cost data
- `scripts/data/CardDB.gd` — **254 `cost` fields** in `CARD_POOL`.
- `CardDB.UPGRADES` — ~190 entries; several are `cost` deltas (spell "+" forges are
  routinely −1 cost). **A −1 on a rescaled card is a different discount** than on the
  original. Gate: `tools/_probe_upgrade_merge.gd`.
- ~~`scripts/scenes/Shop.gd:28` — **`SELL_PER_COST = 8`**~~. **SUPERSEDED, and the
  whole knob is gone (2026-09-16, owner's call).** The rescale answer here was 8 → 4,
  and it shipped; then the underlying mechanic was questioned and did not survive the
  question. **The sutler no longer buys cards — the shop CHARGES `REMOVE_FEE` 60,
  flat, one per visit.**

  Two reasons, and the second is the one the cost rescale made unignorable:

  1. Thinning is the strongest thing you can do to a deck in this genre, and here
     it was not merely free, it was **income**. Nothing else on the road pays you
     for improving.
  2. **The rate was BACKWARDS.** Keyed to Command cost, it paid LEAST for exactly
     the cards a player wants gone — cost-1 starter chaff at 14 gold — and MOST for
     the cost-6 bombs nobody dumps, at 34. The card you most want to strike was the
     one he valued least. That inversion is not a tuning error; it is what pricing
     removal by card power does, and §2.2's rescale *widened* it by stretching the
     cost axis from 1–2 to 1–6.

  A flat fee has no inversion to fix. NOT escalating (StS's 75/+25): the
  one-per-visit cap × a route's ~4 shops already bounds it at 4 strikes a run, and
  an escalator would need a persisted counter to do what the cap does for free.

  **The faucet that pays for it** — the fight bases in Combat's victory block went
  **40/60/55 → 50/70/65**, ~+210 gold over a full 21-fight route against the ~84
  gold of sale income removed. Net +126 to a player who never thins; roughly
  break-even for one who thins twice. **Deliberately not full compensation** — a
  fee the run always affords is a fee that decides nothing.

  Downstream in the same pass: `scavengers_pouch` (Trader's Marker) `sell_double`
  value 2 → **`removal_discount` value 50** (a percentage, matching
  `merchants_license` beside it); `WritDB`'s Paymaster's Ledger writ and both coin
  pacts reworded; `road_rule_worth("scavengers_pouch")` **re-derived** to the same
  1.00 forge rather than inheriting it (halving 3 typical strikes saves ~90 gold =
  one forge — and note the Bond pact's delta IS that number, so it is the first
  thing to re-read if the fee moves). Gates green: `shop_sell_progressive` (26) ·
  `shellpass` · `relic_slate` (40) · `terms` (both pact halves still mean 1.25) ·
  `flow` (145 drivers, 0 invariant fails) · `text_floor` · `run_safe_probes`.

  **The counter that still buys asks for your BEST** (owner's follow-up, same day).
  The Pawnbroker's Window pulled at **uniform random**, which on a mostly-starter
  deck meant she bought your chaff — the same free-thin defect in a different hat,
  and not a decision. She now ranks the deck by rarity (0/10/20/30) **plus 12 for
  any forge** — more than one rarity step, because the rule names rarity and forging
  as equal claims, and a card you chose to forge is your best *by revealed
  preference* — and shows the top 3 best-first, each refusal cooling the figure 15%.
  The price gained a matching +20 for a forged card, or she would hunt your best
  work and pay base-card money for it.

  **`pawn_buyback` 60 → 90 in the same edit, and this is the reusable part.** That
  flat 60 was tuned against an *average random pull* (~35–45 gold). Changing what
  the mechanic SELECTS silently repriced it: against a rare at 115 the round trip
  became a money pump — sell high, redeem cheap, keep the difference and a free
  forge. 90 is the road's own unit (one forge = two potions ≈ 90 gold). **When you
  change what a mechanic selects, re-check every price that was tuned against the
  old selection.**

  Gate: `_probe_flow._drive_appraisal` — *"nothing eligible outranks what she
  named"*, asserted against the deck rather than a named card so it survives a
  retune, plus no re-offer and no climbing offer. The `rich` fixture had to gain a
  rare, an uncommon and a forge first: on an all-starter opener every card ties and
  the assertion passed against a random roll. Mutant-verified (sort → shuffle = 4
  invariant failures).

  **Left alone:** `Wayside._sell_price` still holds the old paid shape, but
  `muster_scale` has been unreachable since 2026-07-02.

### 5.6 Relics
- **`deep_satchel`** (+1 refill *target*) and **`snecko_eye`** (sets target to 6) both
  edit a target that will no longer exist → **rework to flat +N draw**. `Combat.gd:4145-4150`.
- **`marathoners_sash`** forces `player_mana = 1` on round 1 (`:4095-4096`) as its ramp
  trade — that is now the *baseline*, so the relic's downside evaporates. Rework.
- **`mana_tide`** (War Chest) pays off banking — survives only as long as §6.1 does.
- **`battle_scars`** (+2 Command next turn) is a far bigger swing at round 1–2 than at 3.
- Conditional max-Command arms in the `_start_round` block: `cavalry_sigil`,
  `junk_slot`, `lean_mean`, `bone_hourglass`, `happy_flower`, `warm_knucklebone`.
  All still work; **all are proportionally much stronger early** under a ramp.
- **Nine boss relics** grant "+1 max Command" with a downside — these now shift the
  entire curve up one round. Re-check against `mana_cap_cost` (`RelicDB.gd:23`), the
  "+2 max" non-boss ceiling, which was budgeted against a flat 3.

### 5.7 Mutators
`_mutator_max_mana_increase` (fine) and **`_mutator_hand_draw_reduce`** (`:4159-4160`)
— reduces a *target*; must become a draw reduction.

### 5.8 AI and simulation
- **`scripts/combat/BoardEval.gd`** — `command` is weighted a flat **2.0**. Under a ramp
  a Command is worth far more at round 1 than at round 6; a flat weight is now wrong.
- `scripts/combat/BoardSim.gd`, `scripts/combat/BotBrain.gd` — the learned weight vector
  was trained against the flat economy. **`user://bot_brain.json` should be invalidated**,
  or the champion carries pre-rescale weights into a different game.
- `SkirmishBot.build_deck` / `decide_turn` — cost-aware.

### 5.9 The discard marks
`MAX_DISCARD_MARKS = 2` exists **only because refill-to-N made marking free** — the
const's own header says so (`:152-158`: "refill-to-5 returned exactly one card per card
shed"). Under a fixed draw a marked card is a **real, permanent loss of tempo**, which
is a genuine cost. **The cap can probably be lifted entirely.** Deferred to Phase 4 —
it needs the new throughput measured first.

### 5.10 Copy, tutorial, HUD
- `TutorialDB.gd` — `banking` (**:180-184**, "Carry up to 2 unused Command"), and the
  lane lesson (**:91**) which names the Command seal. **A new lesson is required for the
  ramp** — a resource that grows is the single most important rule a new player must
  learn, and nothing currently teaches it. One `TutorialDB` entry + one `_teach_tip`
  call site; everything else derives.
- **The HUD Command seal should telegraph next round's value.** Hearthstone draws the
  empty crystal for exactly this reason; without it the ramp is invisible until it
  happens.
- `docs/COPY_STYLE.md` §6 governs all resource wording.

### 5.11 The Initiative
`Combat._initiative` GO FIRST grants +1 Command (the Coin) at Generals and keeps. At a
flat 3 that was +33%; **at round-1 Command 1 it is +100%.** Needs a re-look —
`tools/_probe_initiative.tscn` (9 Command refs).

### 5.12 Balance cascade (Phase 5, not before)
If the pool is rescaled upward, bodies get bigger, and hero HP 30 / `ENEMY_HP_SCALE` /
`ENEMY_BODY_HP_BY_ACT` are all denominated against the *old* sizes.
**Do not touch these until the rescale is in and measured** — moving both at once makes
the result unattributable.

---

## 6 · Deferred, deliberately

### 6.1 Banking — DEFERRED IN PHASE 1, **BUILT 2026-09-16** (owner's call)
Under a strict ramp, banking is redundant (next round is bigger anyway) and it **breaks
the legibility contract** — with banking, round 2 can be 2+2 = 4 Command, so "cost N is
playable on round N" stops being true. Hearthstone, Snap and LoR all have no banking.

It was nevertheless **unchanged in Phase 1**, because removing it takes `mana_tide`, the
`banking` tutorial lesson, `run_mutation_check.sh`'s mutant and a fistful of probes with
it — and Phase 1's whole value is that **only the three dials move**, so the measurement
is attributable. First follow-up after the Phase 1 numbers land.

**The follow-up landed, and the shape is a GATE rather than a deletion:** `_bank_cap()`
returns 0 unless the run holds `Combat.BANK_RELIC` (`field_chest` — The Field Chest,
uncommon combat relic), in which case it returns `MAX_BANKED_MANA`, still 2. So the
default is the no-banking rule this section argued for, and carryover survives as
something a player spends a relic slot to get — which is the only form in which it does
not silently break the cost contract, because the player opted into it.

**Note the history, since this is the second reversal on one question.** Miser's Coffer
(uncapped banking) was retired 2026-07-25 on the grounds that "Command is a FIXED
resource and banking is the clearest violation of that" — and the universal 2-point bank
was left standing beside the note that retired it. The rule that killed the relic was
never applied to the rule. Anyone re-opening this should be arguing about the GATE, not
re-discovering the argument.

**The amount stays on `MAX_BANKED_MANA`, not on the relic's `value`.** Three things read
that number — `Combat`, `NetPlayerState` (the host's model of the client) and the wire
compatibility fingerprint — and a relic value allowed to outrun it is exactly how the
first two came apart over relic magnitudes once already. Two funnels only: `_bank_cap()`
for the run and the static `bank_cap_for(held)` for the practice bot.

**What it cost on the way past, and the transferable lesson:** `powder_horn` triggered on
*banking*, so its condition silently became "…and you also hold the other relic" — a live
uncommon that does nothing on its own, i.e. the dead-reward class, arriving invisibly
because nothing in this codebase gates a relic hook against a live constituency. Re-keyed
to ENDING a turn with unspent Command: same moment, no dependency, and truer to the name.
`mana_tide` needed no such treatment — it is already `retired`, and its arm stays only so
an old save folds.

Downstream in the same pass: the bank pips build EMPTY without the relic; the Command
hover text says "spend it or lose it" instead of promising a bank the run does not have;
the `banking` lesson states the default first and reads its number from `_bank_cap()`
rather than the constant (a lesson is stamped seen the moment it fires, so printing the
constant would teach the amount to a run with no carryover at all).

Gates: **`tools/_probe_command_bank.tscn`** (8 checks — both directions of the rule, the
cap, and a source shape asserting nobody has restated the constant at a call site;
mutant-verified, ungating `_bank_cap` fails 2). `run_mutation_check.sh`'s
`MAX_BANKED_MANA` mutant is preserved because **`_probe_golden`'s frugal scenario now
arms the relic on purpose** — without that, the one scenario in the corpus that banks
would have stopped banking and the mutant would have gone back to escaping.

### 6.2 The 6-cost tier
Not authored until §2.1's round-length measurement says it is reachable.

---

## 7 · Gates that will go red, and which are expected

**Expected — re-bless or re-baseline:**
- `tools/_probe_golden.gd` — every digest changes. Deliberate re-record: `-- --bless`.
  **Do this LAST**, after the phase is stable, or it pins a half-finished economy.
- `tools/_probe_invariant_mining.gd` — mined numeric *ranges* shift (expected). A broken
  **relation** is not expected and is a real finding.
- `tools/run_mutation_check.sh` — mutates `MAX_BANKED_MANA: int = 2` (**:187-188**) and
  the `player_mana = player_max_mana + banked` line (**:196-197**). Both texts change;
  the mutants must be re-keyed or the mutation check silently stops testing anything.

**Must stay green:**
- `tools/_probe_parsecheck.tscn` — the compile gate, after every script edit.
- `tools/_probe_net_relic_parity.gd` — the whole point of §5.4.
- `tools/_probe_invariants.gd` / `_probe_runaway.gd` — the Command bound is
  `player_max_mana + MAX_BANKED_MANA`, a contract that still holds under a ramp.
- `tools/_probe_upgrade_merge.gd` — cost deltas.
- `tools/_probe_dismiss.gd` · `_probe_hand_dim.gd` — draw and affordability.
- `_probe_bot_brain` · `_probe_board_eval` · `_probe_sim_fidelity` — §5.8.
- `_probe_card_rules_fit` · `copy_lint` · `text_floor` — if any desc changes.

**Heaviest Command/draw consumers, in reference order:** `_probe_skirmish_combat` (13),
`_probe_newcards` (11), `_probe_runaway` (11), `_probe_initiative` (9),
`_probe_card_play` (7).

---

## 8 · Phase order

1. **The three dials only** — ramp + draw 2 + net mirror. No cost changes, no relic
   reworks beyond what outright breaks. Then **measure rounds-per-fight** (§2.1). This
   is the gate on everything below it.
2. **Enemy `max_place` ramp** (§3) — required before any balance reading is meaningful.
3. **The cost rescale** (§2.2) — derived from card power, then reviewed.
4. **Relics, mutators, discard cap, AI weights** (§5.6–5.9).
5. **Balance cascade** (§5.12) and the new tutorial lesson.
6. **Re-bless golden. Full `run_safe_probes` + `run_ui_gates`.**
