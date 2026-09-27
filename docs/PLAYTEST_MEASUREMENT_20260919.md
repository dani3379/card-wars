# Playing the game to find out what is wrong with it — 2026-09-19

**What this session did:** taught the pilot to build a deck, gave it a journal
that records every decision *and the options it was chosen over*, then read the
result. Everything below is measured. Where a number is about the BOT rather than
the GAME, it says so — that distinction is the whole methodology, and several of
this project's past conclusions have been the instrument reported as a property
of the design.

**Three tools are new and are the durable part:**

| file | what it answers |
|---|---|
| `tools/_probe_pilot.gd` (journal block) | every choice, with its full option set, flushed per record |
| `tools/analyse_journal.py` | forced turns · decidedness · lead changes · snowball · choice separation · HP economy · the ramp |
| `tools/_probe_route_census.tscn` | what one route through an act actually reaches, and what the rush skips |

---

## 0. THE HEADLINE: an act can be finished in 5 stops of 18

`RunState.get_available_nodes()` (`scripts/state/RunState.gd:1780-1791`) appends
the lord's keep to **every** step's options once two holds have fallen. The only
constraint is `boss_node.row > row` — there is no adjacency test. So from roughly
row 4 onward the keep is a legal march from wherever the army stands, and the
chip lights up on the chart (that list is the single source of truth for buttons,
road tint and the pulse overlay — its own comment says so).

**Measured** (`tools/_probe_route_census.tscn`, 40 generated acts, each walked
twice from the same map — once taking the keep the moment it appears, once
refusing it while any other stop remains):

```
                    in act   keep-first   road-first
  combat              8.72         1.93         4.20
  elite               3.00         0.07         1.80
  recruit             2.90         0.10         1.75
  wayside             6.15         1.08         3.17
  event               5.78         0.82         3.15
  rest                1.98         0.00         1.00     <- the act's only camp
  shop                1.73         0.00         0.80
  treasure            1.00         0.00         0.57
  arsenal             1.00         0.00         0.55

  stops taken, keep-first   5.0
  stops taken, road-first  18.0
  the act a rusher skips    72%
```

A rushing route reaches **no camp, no wagon, no reliquary, no arsenal, and one
recruit in ten acts.** This is not hypothetical: the pilot did it by accident.
On seed 606 it took the keep at row 8 of act 1 and row 5 of act 2, arrived in
**act 3 still holding the eleven-card starting deck**, and died there.

**Is it a bug?** The code is deliberate — `CONQUEST_REDESIGN.md` §15.1 #5 settled
on "keep visible from the start, locked until 2–3 holds broken", and that is what
ships. But the same decision line records the alternative as *"always-open but
**scaled** when rushed"*, and notes the scaling was **deferred to an ascension
modifier**. What is live is the freedom without the price: skipping seventy
percent of an act costs the player relics, cards, gold and the only guaranteed
heal, and costs them **no risk whatsoever**.

So it reads as a trap for a player who does not know, and a free skip for one who
does. Three ways out, cheapest first:

1. **Price it.** Ship the deferred half: scale the keep by how much of the act
   was left standing. The data for it already exists — `holds_broken_in_act` is
   right there, and `current_floor` says how far up the road the army is.
2. **Gate it by position** as well as by holds (`boss_node.row - row <= N`), so
   the keep opens when you are near it rather than from anywhere.
3. **Leave it and say so on the chart.** If storming early is meant to be a real
   strategic option, the tooltip has to state what it forfeits — at the moment
   nothing does, and the map gives no hint that the glowing keep four rows away
   is anything other than the next stop.

I have not changed game behaviour here. It is a design call, and the measurement
is the part that was missing.

---

## 1. THE MAP IS A CORRIDOR 74% OF THE TIME

Same probe, road-first walk, boss excluded from the count (*"carry on, or skip
the rest of the act"* is not a choice between stops):

```
  mean branch width   1.25
  width 1:   490 steps (68%)
  width 2:   160 steps (22%)
  width 3:    30 steps ( 4%)
  width 0:    40 steps ( 6%)   <- the boss step itself
  steps offering exactly ONE node: 74%
```

The act is generated 18 rows tall and up to 7 wide with three paths and a 3×
merge bias, and the plate draws all of it. What a run experiences is a single
file with an occasional fork. That is not automatically wrong — Inscryption's
cadence is deliberately narrow — but it is worth knowing that route strategy,
which the chart's whole presentation promises, is available at about one step in
four.

---

## 2. THE SCORER NEVER KNEW THAT BLOCKING SAVES THE HERO

`BoardEval.score_creature_at` priced a front-row body by the damage its own HP
absorbed (`min(foe_atk, my_hp) * W_HP * W_BLOCK`) and credited **nothing** for
the face damage the block denies. But `_clash_lane_pass` resolves *"opposing
front in this column, else opposing back, else FACE"* — an empty column is not a
column the hero is partly exposed in, it is one where the hero takes the whole
blow. Overkill spills into the body behind and stops; only Piercing reads on.

The consequence was already on record and had not been connected to a cause:
`docs/PILOT_DIFFICULTY_20260915.md` measured **93–96% of all damage the hero took
arriving through lanes the bot left open.** The bot was placing for trades it
could win rather than for the hero it was supposed to be keeping alive, because
keeping the hero alive scored zero.

Fixed, in three parts, each gated by a new check in `tools/_probe_board_eval.gd`
(21 → 25 checks):

- a body in a column denies the face, at `W_FACE * W_DENY`;
- **a chump is not a wall** — a blocker that dies to the blow has not closed the
  lane, it has moved one instalment back by a round, so it gets `DENIAL_DELAY`
  (0.12) of the credit and a surviving body gets all of it;
- **the back row reaches the face through a clear column**, which the back-row
  arm had never credited at all — it scored a flat +0.3 for a body the front arm
  would have paid `atk * W_FACE * OPEN_LANE` for. That is the same blind spot
  DEFECT 4 was written about, still in the same function.

**The gate caught me over-correcting, and the number is set by that.** At parity
with face damage, blocking swamped everything else: `tools/_probe_personas.gd`
found `curve` (the shipped vector) and `control` (the grinder) collapsing onto
the **same play on all three of its boards**. Two named playstyles becoming one
is the signal that a term has stopped being a preference and become a rule. Swept
against that gate, the divergence returns at 0.35 and is gone by 0.45 — so
`PT_DENY` sits at **0.35**, the most weight the correction can carry without the
default bot turning into the grinder. It is a named, learnable weight (`deny`,
the fourteenth), so `BotBrain.SAVE_VERSION` went 2 → 3.

---

## 3. THE BOT BUILT ITS DECK BY COIN-FLIP

Every offer screen was answered with `randi_range`: the muster, the wagon, the
forge, and — worst — the shop's **paid removal**, so a run could spend 60 gold
deleting its own rare. In a deckbuilder every other lever is downstream of the
deck, so this was not a small weakness; it meant the pilot was measuring the
difficulty of a deck nobody would ever build.

`BoardEval.draft_value()` is new and shares the file's currency (stat points), so
a draft value and a play score are commensurable. It reads standalone card power,
then applies the deck's own curve (a fifth copy of a cost band is worth less than
the first; a deck with nothing castable on rounds 1–2 loses the opening exchange
regardless of what it holds) and a deliberately small tribe-synergy term.

Policies now: **muster** takes the best card; the **forge** improves the best
card; the **removal** strikes the worst; the **wagon** buys by value per 100 gold
and holds its purse when nothing clears the bar; the **chart** routes on HP,
gold, deck size and node type instead of walking at random.

`--policy=random` keeps the old coin-flip behaviour **in the same binary**, so
the claim is testable rather than asserted. An A/B against a deleted version of a
file is an A/B against memory.

---

## 4. WHAT THE JOURNAL MEASURES, AND WHY THOSE FOUR

A log of actions cannot answer a design question. It says a card was drafted; it
cannot say the two it was drafted **over**, so a card taken forty times reads as
popular when it may have been the only thing ever offered. The journal records
every option with its score, flushed per record so a killed run still leaves its
evidence.

1. **Forced turns** — a turn with one legal play is a formality with a button on
   it. Split by round, because the Command ramp makes the early game where this
   bites.
2. **Decidedness** — the last round the board still DISAGREED with the eventual
   result, against how long the fight ran. A fight settled at round 2 and ending
   at round 12 spent 83% of itself performing a result already reached.
   **The measure has to be symmetric or it lies about half the fights.** The
   first version asked "the last round the player was ahead", which is the right
   question for a loss and nonsense for a win: a fight won from behind on board
   — by racing the face — scored as **100% already decided**. Three won fights
   came out that way before it was fixed.
3. **Lead changes** — how often the board advantage changes hands. Zero is a
   procession whoever wins. This is the standard excitement measure from sports
   analytics and it asks about the *contest* rather than the result.
4. **Choice separation** — the gap between the best play and the second best.
   Large means the card picks itself; near zero means the cards were
   interchangeable. Both are failures, in opposite directions, so the
   distribution matters more than the mean.

Plus the run-level pair: the **HP economy** (what a fight costs against what the
road repays) and the **ramp** (where Command stops being spendable).

---

## 5. WHAT THE MEASUREMENTS SAY SO FAR

### The 2026-09-15 difficulty document is out of date, and in the game's favour

That doc reported the pilot **ahead until round 1.4 of a 10.4-round fight** —
"the fight is decided by the opening deal, and everything after is a formality."
It predates the 2026-09-16 economy work (the hold ramp, the cost rescale,
`HOLD_LEAVES_A_PATH`). Re-measured over **103 fights**:

| | 09-15 doc | 09-19 |
|---|---|---|
| fights won | 64–67% | **85%** (88/103) |
| of the foe removed when it lost | 52% | 6–100%, median ~50% |
| damage taken behind a full wall | 4–7% | 17–18% |
| acts reached | 1–2 | 1–3 |

Two of those moved for different reasons and it matters which. The win rate is
partly the bot (it drafts now, and it blocks). **The "behind a full wall" figure
went UP**, 4–7% → 17–18%, and that is not a regression — it is what happens when
the bot stops leaving lanes open: the damage that remains is the damage blocking
was never going to stop, which is the class `COMBAT_SHAPE_PASS_20260727.md` is
about. It is now a sixth of all damage taken rather than a twentieth.

### Fights are decided around round 2 of 6.4

```
  LOST fights run 6.1 rounds, last in doubt at round 2.1 — 63% already decided
  WON  fights run 6.4 rounds, last in doubt at round 2.4 — 68% played out after
  mean lead changes per fight   0.57
  fights with ZERO lead changes 67/103 (65%)
```

So roughly **two-thirds of every fight is played after its result has stopped
being in question**, and two-thirds of fights never change hands at all. That is
much better than the 09-15 reading (87% wasted) and it is still the single
biggest claim on the player's time.

**Both measures are calibrated against the population mean, not against parity,
and they have to be.** The snowball table is why:

```
     round   gap in fights WON   gap in fights LOST
         1                -5.0                -15.7
         2                -8.5                -25.2
         3                -5.3                -31.6
         5                -2.9                -46.9
         8                -9.7                -52.6
```

**The player is behind on raw material in every fight, winning or losing.** The
hold's only cost for a body is `max_place`, a body count; the player pays Command
for each one. Winning and losing differ in the SIZE of the deficit — about −5
versus −16 on the very first exchange — not in its sign. Any measure keyed on
"who is ahead" therefore reports every won fight as a miracle and every lost one
as doomed from round 1, which is what the first draft of this analysis did.

It also means **"contest the board" is the wrong mental model for this game**:
the player wins by racing a deficit, not by taking the board. Worth deciding
whether that is intended, because nothing in the game says it.

### THE BINDING CONSTRAINT IS HP, AND IT IS A PLACEMENT PROBLEM

**This is the finding.** Over 103 fights and 15 completed runs:

```
  hero HP spent per fight      6.1
  hero HP recovered BETWEEN    1.0   (all sources: camps, potions, relics, events)
  NET drain per fight         +5.2
  => a 30 HP bar funds 5.8 fights. A full run is about 21.
```

The bot wins **85% of its fights** and has **never finished a run** in 15
attempts (acts reached: eleven 1s, seven 2s, one 3). Those two facts are not in
tension — it is not losing fights, it is running out of hero.

And the cause is structural, not a dial. An act's row skeleton is
`FIGHT_ROWS [0, 3, 9, 15]` + `ELITE_ROWS [6, 12]`, then `REST_ROW = 16`,
`BOSS_ROW = 17`. **All six of an act's road fights happen before its only camp,
and that camp is the stop immediately before the keep.** There is no mid-act
heal at all. Six fights at 6.1 HP is 37 HP against a 30 HP bar, so an act is
survivable only on potions, relic upkeep and event luck — and the one big heal
arrives after the danger it was needed for.

Three candidate fixes, none of them a global difficulty dial:

1. **Move or duplicate the camp.** A second rest band around row 8-9 (between
   the first elite and the third fight row) would put a heal where the budget
   actually runs out. Cheapest change with the largest effect.
2. **Pay the road in HP, not only in gold.** Waysides and events already touch
   the deck; almost nothing on the road repays hero HP, which is why the
   measured between-fight recovery is +1.0.
3. **Lower the per-fight bill.** The least attractive of the three: 6.1 HP a
   fight is not obviously wrong, and cutting it flattens the fights themselves.

**I got this wrong once before writing it down, and the error is instructive.**
The first version of this measure kept only non-negative between-fight gaps —
dropping every stop that COST hero HP (a curse's draw sting, an event toll, a
set-piece withdrawal) — and so measured the road's generosity while ignoring its
bills. It reported **+11.8 recovered against a 6.1 cost** and concluded attrition
was not binding. That conclusion was an artifact of a filter. A gap is a gap in
both directions.

### The Command ramp stops being spendable at round 7

```
   round  turns   pool  unspent  waste%  cards left  best-play cost
       1    103   1.04     0.10      9%        4.07            1.02
       3    101   3.04     0.05      2%        4.79            1.85
       5     83   5.01     0.29      6%        3.93            1.76
       6     61   6.00     0.56      9%        3.07            1.76
       7     44   6.00     1.27     21%        2.73            1.99
       8     24   6.00     1.21     20%        2.46            2.00
       9     11   6.00     2.09     35%        3.36            2.10
```

Command ramps 1→6 and caps; draw is a flat `HAND_DRAW_PER_TURN = 2`. Through
round 6 the pool is spent almost exactly (2–9% waste). From round 7 the hand has
emptied to 2.5 cards and **a fifth to a third of the Command has nothing to buy**.
Since the 2026-09-16 pass, unspent Command is simply lost unless the run holds
the Field Chest.

Rounds 7+ are ~20% of all turns played, so this is not a corner case — but note
it is also the part of the fight that is already decided (above). The two
findings point the same way: **the back half of a fight is where this game has
the least going on.**

### Round 1 is the only turn with no room in it

```
  turns with NO legal play         10   1.5%
  turns with exactly ONE play      18   2.8%
  turns with a real choice        623  95.7%

   round 1: 14.6% forced      round 3-6: 1.0-1.6% forced
```

95.7% of turns offer a real choice, which is healthy. The exception is round 1,
where Command is 1 against a pool whose median cost is 3 after the rescale — one
opening turn in seven has nothing playable at all. `ECONOMY_REDESIGN_20260916.md`
§3c already flagged this residual and judged the case for chasing it weak; this
is a second, independent measurement of the same thing, at 14.6%.

### Choices are real about half the time

```
  decisions with 2+ options     1172
  median gap to 2nd-best        1.35 stat points
  OBVIOUS (gap > 3.0)           24.9%   — the card picks itself
  TOSS-UP (gap < 0.5)           29.2%   — the cards are interchangeable
```

A quarter of decisions are already made for the player and another quarter do not
matter; the middle ~46% are the game. That is a reasonable distribution, and the
toss-up quarter is the more interesting half of the problem — it says a lot of
this pool's cards are substitutes for each other at the same cost.

### A symmetric attrition rule is not symmetric here

Three encounters (`forge_burn_all`, incl. `rival_kindler` phase 1) deal 1 damage
to **every creature on the board, both sides**, every round. That reads as even
and is not: `EncounterDB.get_reinforcement` is an **infinite** well — the hold
refills for free — while the player pays Command for every body. A rule that
taxes bodies equally taxes the finite side harder. `rival_kindler` was the single
worst encounter measured in the baseline: 13 rounds, 32 hero HP, lost at 1/19
foe HP remaining.

---

## 6. BUGS FOUND

**Game-side.**

- **`ERROR: Lambda capture at index 0 was freed`** — the documented class
  (`reference_deferred_lambda_node_capture`): the engine emits it while
  *marshalling* captures, so an `is_instance_valid()` inside cannot suppress it.
  Two live instances found and fixed:
  - **`Combat._show_battle_verdict`** — the victory stamp's gilt eruption and the
    gold count-up both captured their Label across a timer, and the march back to
    the chart frees the scene at 1.0–1.2 s while the count-up runs to 1.06 s. The
    visible symptom was a spoils counter that could freeze part-way, showing a
    number lower than the gold actually paid.
  - **`Motion.hover_lift`** — captured `tgt`, which on every offer tile in the
    game (Recruit's slate, the Shop's shelf, Reward's cards) is the painted
    wrapper under an invisible catcher, i.e. **a different node from the one that
    owns the connection**. A teardown that frees the wrapper with a queued
    `mouse_exited` still in flight resumes on a dead capture.
  - **Measured, fixed seed, identical 8 fights: 15 → 12 occurrences.** So both
    were real and neither was the main source. The remainder is still open; the
    enumerated candidates are `Combat.gd` 3069/3074/3128 (`walker`/`d_body`/
    `b_card`), 17245 (`captured`), 22794/22796 (`vnode`), 23455 (`hl`), 32473
    (`ts_c`), 35441/35457 (`rc`/`lord`), and `Card2D.gd:5147` (the death fallback
    timer). **Severity is bounded**: the engine passes `null` and the body still
    runs, and every one of these opens with a validity guard that then returns —
    so the cost is a dropped animation step and log noise, not a wrong game
    state. The identification technique is in the memory: add dummy captures
    ahead of the suspect and watch the reported index shift.

**Harness-side — four, and all four were corrupting the data.**

- **`_play_spell` / `_play_creature` called into a freed Combat.** A spell that
  kills the last enemy ends the fight inside the drag; `c.get(...)` then throws
  and aborts the function, leaving Combat's targeting `_input()` override armed
  so it eats the **next** click — which the pilot reports as a false `OCCLUDED`
  against whatever was under the cursor.
- **The picker tiles were unreadable.** A picker tile is a transparent catcher
  and the card it covers is neither its child nor its ancestor, so the forge and
  the paid removal were logging eleven tiles of `"?"` — a policy that could not
  read its own options, surviving *inside* the fix for exactly that problem. Now
  read off the handler's bound deck index, like the wagon reads its wares.
- **`no_play` was counting loop exits.** `_play_hand` loops until the scorer
  returns nothing, so the record fired once per turn unconditionally and the
  analyser reported "31.6% of turns had no legal play" about a bot spending its
  Command to zero.
- **`_in_hand` / `_regrab` threw on freed arguments.** GDScript validates a TYPED
  argument's class AT THE CALL and a freed object has none, so the guard inside
  could never run — the same hazard `_note_play`'s header documents, at two sites
  that had not been given the treatment.

---

## 7. WHAT I WOULD CHANGE, RANKED

1. **Put a heal where the act's HP budget actually runs out** (§5). Six fights
   before the only camp, at 6.1 HP a fight against a 30 HP bar. This is the
   reason a bot that wins 85% of its fights has never finished a run, and it is
   a placement problem rather than a difficulty dial.
2. **Price or position-gate the keep** (§0). 72% of an act is skippable for no
   risk; the design doc already chose the fix and deferred it.
3. **Decide what rounds 7+ are for** (§5). They are simultaneously the part of
   the fight that is already decided and the part where a fifth of the Command
   has nothing to buy.
4. **Look at the outlier encounters, not a global dial.** `The Pyre Cult`,
   `The Threshold Choir`, `THE ACOLYTE` and the symmetric-burn family
   (`forge_burn_all`) are the repeat offenders; a board-wide tax against an
   infinite reinforcement is structurally one-sided.
5. **Widen the chart or stop promising width** (§1). 74% of steps have one option.

## 8. WHAT THIS DOES NOT LICENSE

- Everything play-quality here is **one agent**. A property that survives the bot
  getting better is the game's; a property that moves is the bot's. The A/B arm
  (`--policy=random`) exists so that distinction can keep being tested. The HP
  bill of 6.1 a fight is the most agent-conditioned number in the document — a
  better player takes fewer hits. **The recovery half (+1.0 between fights) is
  much more nearly a property of the game**, because it is what the road offers
  and the pilot takes essentially all of it: recruit 97% of offers, elite 90%,
  treasure 100%, arsenal 100%.
- **The bot has still never won a run** (0 of 15). So the headline "a run needs
  ~21 fights and a 30 HP bar funds ~6" is an argument, not a demonstration. The
  demonstration would be a bot that finishes, and the cheapest route to it is
  probably §7 #1 rather than more bot work.
- **Act 3 is one fight of sample.** The act-2 win rate (67%, n=21) is worth
  something; the act-3 figure (0%, n=1) is worth nothing.
- **Acts were reached both ways.** The seed-606 act-2/3 arrivals in the first
  session were reached by the keep rush — an act-1 deck standing in act 3 — and
  are not an act-3 state. The later runs route properly; read those.
- The `--hurry` runs replace the human cursor model with teleports, which is
  strictly less faithful for input-pipeline bugs. They were used for the balance
  data on purpose; the input findings come from the human-motion runs.
- Set-pieces, the rival lords beyond two, and the whole skirmish shell remain
  untouched by the pilot.

---

## 9. HOW TO REPRODUCE

```bash
"/d/games/Godot_v4.6.2-stable_win64.exe" --headless --path "D:\Godot" res://tools/_probe_pilot.tscn -- --max-sec=1700 --max-nodes=600 --seed=909 --greedy --hurry
```
```bash
python tools/analyse_journal.py
```
```bash
"/d/games/Godot_v4.6.2-stable_win64.exe" --headless --path "D:\Godot" res://tools/_probe_route_census.tscn
```

Journals accumulate in `user://pilot_journal/`; the analyser reads all of them.
`--policy=random` runs the control arm. Gates touched this session:
`_probe_board_eval` (32 checks), `_probe_personas` (62), `_probe_bot_brain` (48),
`_probe_parsecheck` (128 scripts), `_probe_copy_lint` — all green.

---

## 10. WHAT THE GENRE DOES, AND WHAT IS ABNORMALLY LOW HERE

Everything above is internal. This section benchmarks the same measures against
published numbers from the two games this design names as models, so "6.1 HP a
fight" can be read against something.

### The two working models for attrition

| | fights per run | in-act heal nodes | heal per visit | act-boundary heal |
|---|---|---|---|---|
| **Slay the Spire** | ~16 | **12% of floors** + 1 guaranteed | 30% max HP | **full heal** after every boss |
| **Monster Train** | **8** | rare (events/artifacts only) | varies | none |
| **Burning Meadow** | **21** | **1 per act** (row 16) | to FULL | **none** |

StS runs 17 floors an act: floor 1 is a fixed easy combat, floor 9 treasure,
floor 15 a **guaranteed rest**, floor 16 the boss. The other floors roll
Normal 53% / Unknown 22% / **Rest 12%** / Elite 8% / Merchant 5%, and elites and
rests cannot appear below floor 6 or sit consecutively. That yields **~2.6 rest
sites an act**, one of which is guaranteed and the rest scattered through the
road. On top of that, **defeating an act boss heals to full** (75% of missing at
Ascension 5+) — and this is a genre convention rather than an StS quirk: damage
persisting between battles *while a boss kill fully heals for the next chapter*
is how the form is normally described.

Monster Train is the opposite solution to the same problem: the Pyre does not
regenerate at all, and the run is **eight battles long**. Scarce healing is
survivable because the run is short.

**We took Monster Train's healing density and StS's run length.** 21 fights is
the longest of the three; one heal node an act is the thinnest. That is the
structural anomaly, and it is not a difficulty dial — it is the shape of the run.

Note what is NOT wrong: **our camp is more generous per visit than StS's** (heal
to full below A2 vs 30% of max). The defect is frequency and placement, not
magnitude.

### Measured against those norms

| measure | Burning Meadow | benchmark | ratio |
|---|---|---|---|
| heal nodes, share of real (non-boss) nodes offered | **1.2%** (4 of 331) | StS 12% of floors | **10× low** |
| heal nodes actually reached | **2 in 15 runs** | StS ~2.6 per *act* | — |
| act-boundary heal | **none** | full heal (StS, genre) | absent |
| real choices per map step | **1.35**, 71% single-option | StS rooms have 1–3 exits | low |
| cards drawn per turn | **2** (persistent hand) | StS 5, Monster Train 5 | low, partly offset |
| fights per run | **21** | StS ~16, MT 8 | high |

`advance_act()` was checked directly: it resets counters and rolls the A3 curse,
and the only heal in it is gated behind the `centaur_heart` relic, act 2 only.
**We implemented StS's rest structure minus two of its three heal sources** — the
guaranteed pre-boss rest is there (our row 16 / boss row 17 is exactly StS's
floor 15 / floor 16), and both the scattered 12% and the act-boundary full heal
are missing.

### The prediction this makes, and it lands

30 HP bar ÷ 5.2 net drain a fight = **5.8 fights of funding**. The pilot logs
**81 act-1 fights over 15 runs = 5.4 fights a run** before dying. Predicted 5.8,
observed 5.4, against a design target of 7 road fights before the act's only
camp. The HP thesis in §5 is not just arithmetic that happens to be consistent —
it predicts where the runs actually end, to within half a fight.

### Honest gap in this comparison

No published figure for **HP lost per fight in StS** was found, so the
like-for-like "20.3% of the bar per fight" has no external counterpart. It can
only be *inferred* from StS's own design — if ~2.6 rests at 30% are meant to
cover ~9 fights an act, the implied bill is ~8.6% of the bar a fight against our
20.3% — and an inference from design intent is weaker evidence than the node
percentages above, which are documented. **The supply side of this section is
sourced; the demand side is ours alone.**

### What this changes about §7

It does not reorder the ranked list — #1 was already "put a heal where the act's
HP budget runs out". It supplies the missing justification: that change is not a
balance preference, it is **conforming to the genre's own solved problem**, and
there are two named ways to do it. Either add heal nodes toward StS's density
*and* restore the act-boundary heal, or cut the run toward Monster Train's
length. The current combination is the one shape neither model uses.

**Sources.** Slay the Spire map generation, room percentages and fixed floors:
`slaythespire.wiki.gg/wiki/Map_Generation`, `/wiki/Map_Locations`. Rest healing
30% and the pre-boss guarantee: `slaythespire.wiki.gg/wiki/Rest_Sites`.
Act-boundary full heal: Slay the Spire Wiki (Fandom), Health. Monster Train
battle count and Pyre persistence: `monster-train.fandom.com/wiki/Battle`,
`/wiki/Pyre`. Draw counts: `slaythespire.wiki.gg/wiki/Draw`,
`monstertrain2.miraheze.org/wiki/Combat`.

---

## 11. THE CARD REWARD, RESTORED (2026-09-20)

`Reward.gd` contained **no card-granting code at all** — no `add_card`, no
`roll_card_reward`. Fights paid gold, relics and potions and never a card, and
ordinary combats did not even open the screen: they marched straight back to the
chart. The only routes into a deck were dedicated `recruit` stops and the shop.

**Measured over 77 map stops / 8 runs, before the change:**

```
recruit stops   11 offered / 77 stops (14%)    1.75 per act on route
shop stops       3 offered / 77 stops ( 4%)    0.85 per act on route
deck growth     +1 to +2 per RUN, against a 10-card hero opener
                two of eight runs finished SMALLER than they started
```

A hero opens on **10** cards, not 11 — all five `HeroDB` decks are 10-card lists,
and every run's journal trajectory starts at 10. The pilot's own report string
says 11 and that number has been quoted into docs from there; it is wrong.

The ceiling for a complete three-act run, taking every offer, was about **18**
cards. Slay the Spire offers one after each of ~16 combats and finishes at 25-35.

### Why it was gone

Commit **`2e53313`, 2026-06-10 — "Successor Wars slice: recruit camps + fights
pay ground, not cards"**. It introduced the recruit nodes and deliberately moved
deck growth onto them: *"normal fights pay gold inline (base 30→40) and return
straight to the map — no card pick, no interstitial."* Restored from that
commit's own diff rather than rewritten, including the card-offer relic table
(Busted Crown 1 choice, Scout's Emblem 4, Stardust Vial +1 rare, Collector's
Tome picks 2).

**No compensation** (owner's call): gold stays at 65/90/85, so a fight is now
worth strictly more. The pre-2026-06-10 screen also paid **+20 gold to skip**;
that was left out, because re-adding a payout is the compensation this change was
told not to make. It is a one-line restore if the skip-for-tempo choice is wanted.

### Three defects it cost, all caught by the pilot rather than by eye

1. **The full card face instead of the compact one** → Continue landed at
   **y=996** on a 900-tall canvas. `Reward`'s `outer` is a plain VBox in a margin
   with **no scroll**, so overflow simply leaves the screen. Both the original
   code and `Recruit._build_slate` use the compact face for this reason.
2. **Every offer stacked at once.** A General's screen carries the card slate,
   two 304px relic tiles AND the forge; together they pushed Continue to
   **y=1158**, reported unreachable **70 times in one run**. They queue now —
   card, then relic, then forge — which the screen already supported, since it
   rebuilds after each pick.
3. **The buttons were labelled "Take" / "Take None".** `"TAKE"` is in the pilot's
   ADVANCE vocabulary, so the offer *and* the decline both read as "leave this
   screen" and it pressed whichever won tree order — the same trap Treasure's
   *"Take 3 Gold instead"* is documented for. **This one is the dangerous
   shape**: it broke nothing visible and silently made the bot decline about half
   the cards, so the first run after the fix looked fine and was measuring the
   wrong thing. They are **Pick / Skip** now, matching the original and Recruit.

### Result — and the HP claim did NOT survive the real sample

First reading was 9 fights and it flattered the change. **Re-measured properly
(2026-09-24, 54 fights / 12 runs, two seeds, clean journals):**

| | baseline 2026-09-19 | after |
|---|---|---|
| deck at end | 10-18, mostly 10-14 | **10-24** — several 17, 23, 24 |
| fights won | 85% | 78% |
| acts reached | 1-3 | 1-3 |
| HP spent per fight | 6.1 | **9.6** |
| HP recovered between | +1.0 | +1.9 |
| net drain | +5.2 | **+7.7** |
| a 30 HP bar funds | 5.8 fights | **3.9** |
| LOST fights, last in doubt | round 2.1 (63% wasted) | **round 5.4 (38% wasted)** |
| turns with a real choice | 95.7% | 96.4% |

**Deck growth is fixed** — that is the change working, and it is unambiguous.

**The fight quality improved too, and this is the best number here:** a fight the
player LOSES is now in doubt until round 5.4 of 8.2, where it used to be settled
by round 2.1. The share of a lost fight that is a formality fell **63% → 38%**.

**But the HP bill per fight ROSE, 6.1 → 9.6, and the run now funds FEWER fights.**
That is the opposite of the n=9 hint, and it is not yet explained. The leading
candidate is the **fight MIX rather than any fight's difficulty**: the 2026-09-19
map pass cut fights per run from a fixed 21 to 12-17, the pilot takes 90% of the
Generals it is offered, so Generals are now a larger share of a smaller
population. A single "HP per fight" average cannot separate that from a real
difficulty change.

**The journal could not answer it, which is the actionable part.** `fight_end`
now records `node_type`, and `analyse_journal.py` prints the HP bill split by
combat / elite / boss with each kind's share. The next run answers it; this one
cannot, and the number above should not be acted on until it does.

**The cost is pacing, and it is real.** Reward is now the most-visited screen in
the game, which is exactly what `2e53313` was avoiding. That is a feel judgement
a probe cannot make. If it drags, the lever is the screen's dwell, not the
reward — the card is what the fight is for.

---

## 12. THE FORECAST BRACKET WAS SITTING ON THE CARD'S OWN STAT SEALS (2026-09-24)

Owner report: *"the mana circle kind of clips through like the edge of the card
goes over it."* Confirmed at 8× zoom — the seal is **not** clipped; the lane
forecast's `StruckBracket` corner tick is drawn hard across it. The project's own
oracles put a number on it:

```
painting oracle: 3 chip/art collisions,  worst  8% covered
seal oracle:     6 chip/seal collisions, worst 13% of a seal covered
```

`Combat._add_forecast_bracket` inflates the token rect by
`FORECAST_BRACKET_OUTSET` and draws four corner ticks. The token's **bottom two
corners are exactly where the 38px ATK/HP wax seals sit** (`Card2D
._build_compact_layout`, inset 3px), so every bracketed card had its own stats
crossed out.

### Three defects, and the first two are the reusable lesson

1. **THE OUTSET AND THE ARM LENGTH WERE THE SAME DIAL.** `StruckBracket._draw`
   read `arm_x = size.x * reach`, and `size` is the *inflated* rect — so pushing
   the bracket outboard to clear the seals grew the arms by the same proportion
   and they reached straight back over them. Measured: sweeping the outset
   3 → 4 → 5 → 6 left the seal oracle pinned at 13%. **When a fix does nothing,
   check whether the thing you moved is scaled by the thing you moved it with.**
   The painter now takes `outset` and sizes its arms off the token.
2. **THE LETHAL DOUBLE-RULE REACHED 10.8px INBOARD.** `inb = thick * 2.0` put
   the second register rule well inside the token — squarely on the seals.
   `DOUBLE_RULE_GAP` is 1.0 thickness now; it still reads as a doubled mark and
   stays on the border the painter's own header says it belongs on.
3. **THE ORACLE WAS NON-DETERMINISTIC AND THAT MASKED EVERYTHING ELSE.** The
   seal oracle flickered between 0 and 2 collisions **on identical code**, so a
   geometry fix and a lucky draw were indistinguishable — I ran three sweeps
   before noticing. It took THREE causes, and finding them one at a time is the
   whole lesson:
   - the corner wobble ran ±1.3px in *both* directions, so a corner could wander
     onto the token. Biased OUTBOARD — same amount of hand, none on the card.
   - **the fixture itself varied.** `_shot_forecast` called
     `RunState.start_new_run("stalwart")` with no seed, so every run booted a
     different encounter and muster: the staged board came out with 8 bodies or
     7, and one lane read `2/8` on one run and `3/8` the next. A fixture that
     varies is not a fixture. Seeded.
   - **the marks were seeded off `get_instance_id()`**, which is new every
     session — so the same creature was struck with a different hand on every
     boot. `WaxSeal` has carried the opposite rule since the writ kit was built
     ("every bake of the same card matches"). Both forecast marks now key off
     the card id plus its slot.

   Only after all three is the reading stable: **0 / 0 over four consecutive
   runs.** The third one is a real visual bug in its own right, independent of
   any oracle — a card's mark should not change shape between sessions.

### Result

```
FORECAST_BRACKET_OUTSET  3.0 → 6.0
painting oracle  3 collisions / 8%  → 0 / 0   (stable over 3 runs)
seal oracle      6 collisions / 13% → 0 / 0   (stable over 3 runs)
```

`FORECAST_SEAL_GAP` stays at 9.0 — the wound seal did not need to move once the
bracket stopped growing its own arms.

**The mark was not redesigned.** It has a documented rejected-looks history; this
was a geometry collision with an oracle that scores it, and the target was the
score.

---

## 13. THE HP BILL IS NOT ONE POPULATION — A GENERAL COSTS 4× A HOLD (2026-09-24)

§11 reported the HP bill per fight rising 6.1 → 9.6 after the card reward and
flagged the fight MIX as the leading suspect, because a single average cannot
separate "fights got harder" from "there are proportionally more hard fights".
`fight_end` now records `node_type` and `analyse_journal.py` splits on it:

Final figures, **52 fights / 12 runs**:

```
  kind      fights   share   HP each   total HP   share of ALL damage
  elite         10     19%      20.9        209                   45%
  combat        33     63%       5.7        187                   40%
  boss           9     17%       8.0         72                   15%
```

**A General costs 20.9 hero HP — two thirds of a 30 HP bar, and 3.7× a plain
hold. Nineteen percent of fights account for forty-five percent of all damage
the hero takes.**

And they are what actually ends runs:

```
  kind      fights   fight%   run-ending deaths   death%
  elite         12      21%                   7      58%
  combat        35      62%                   3      25%
  boss           9      16%                   2      17%
```

And the win rate is a cliff, not a curve:

```
  kind      fights   won   win%
  combat        35    31    89%
  elite         12     5    42%
  boss           9     6    67%
```

**An agent that wins 89% of ordinary holds wins 42% of Generals.** A General is
close to a coin flip for a player who is otherwise comfortable.

**A fifth of the fights cause well over half the deaths.** And the mean hero HP
on *entering* a run-ending fight is **22.2 of 30** — so these runs are not being
ground down and finished off; they walk into a General at three-quarters health
and do not walk out. That is a spike, not attrition, and it is the clearest
answer yet to "why has the bot never finished a run".
That settles §11: the rise is composition, not difficulty. The 2026-09-19 map
pass cut fights per run from a fixed 21 to 12–17 and made the elite bands
bypassable; the pilot takes 90% of the Generals it is offered, so Generals are
now **a third of all fights** in a smaller population.

### What follows from it

- **The bot's routing is wrong, and this is the cheapest win available.**
  `_choose_stop` took a General whenever HP was at or above `ROUTE_ELITE_HP`
  (0.6). At 20.9 HP against a 30 HP bar, entering one at 60% HP (18) leaves
  nothing — so the threshold was not a safety margin, it was a coin toss, and
  every number above is conditioned on an agent that walked into them anyway.
  Changed to **0.85**, and the elite's route score dropped 4.0 → 2.5 so a
  General is no longer PREFERRED over a muster or a reliquary when both are
  offered. The 2026-09-19 map pass made the bands bypassable precisely so this
  is a choice; the policy was still answering it as if it were an ordinary stop.
  Being A/B'd against the same two seeds now.
- **There is a design tension here worth naming, and it is new.** The 2026-09-19
  pass made the elite bands BYPASSABLE, which is right — it turns a tax into a
  choice. But the fight behind the choice is a 42% coin flip costing two thirds
  of the hero bar. A player who learns that will simply always walk past, and
  the relic + forge a General pays is one of the run's main sources of power —
  so the reward economy quietly dries up for anyone who reads the odds. Either
  the spike comes down or the prize has to be worth a coin flip; right now the
  rational line is to decline, which is not usually what a designer wants from
  an optional challenge.

### The boss column is an ARTIFACT — do not read it

`1.0 HP per boss` is not a measurement of boss difficulty. Combat's victory block
heals **75% of missing HP** after every boss, and the pilot samples `hp_out`
every frame, so the last sample is taken AFTER the heal. The cost of the fight is
erased by the reward for winning it.

The honest measure is the hero's LOW-WATER MARK during a fight rather than its
exit HP — which is also more correct for every other fight, since any mid-fight
heal currently hides cost the same way. Not changed mid-measurement: seed 606 was
still running and a fix applied between seeds would have put two different
instruments in one table.

### The nerf, measured properly

`ELITE_HP_SCALE = 0.80` in `_scale_enemy_hp`, applied to the General's face only.
**One variable — the bot and the instrument are byte-identical between arms**,
and plain combats act as the control:

```
  kind             n   face  rounds    HP   win%
  combat  before  35   13.5     5.8   5.7    89%
  combat  after   30   14.2     6.3   5.8    87%   <- CONTROL: unchanged
  elite   before  12   18.1     7.8  20.9    42%
  elite   after   10   14.4     6.1  17.4    60%
  boss    before   9   18.8     8.4   8.0    67%
  boss    after    7   19.7     9.0  13.7    86%
```

**The control is the point.** Combat moved 89% → 87% and 5.7 → 5.8 HP, i.e. not
at all — which is what says the elite movement is the change rather than the
seeds. A General now runs **1.7 fewer rounds**, costs 3.5 less HP, and is won
**60%** of the time instead of 42%. It is still comfortably the hardest ordinary
fight, which was the intent: the goal was to stop it being a coin toss, not to
level it with a hold.

Acts reached went `[1,1,1,1,2,1,2,1,2,2,2,1]` → `[2,1,2,3,1,1,2,1]` — the first
act 3 in either arm. **Runs won is still 0**, so elites were not the only thing
standing between this bot and a finished run.

**THE PREVIOUS ATTEMPT AT THIS MEASUREMENT WAS VOID AND IS WORTH RECORDING AS
SUCH.** It changed the GAME (elite HP), the BOT (`ROUTE_ELITE_HP` 0.6 → 0.85)
and the INSTRUMENT (`hp_out` → `hp_low`) in one run, so combat reading 89% → 76%
and boss 67% → 50% could not be attributed to any of the three — two sections
above this document warns against exactly that, and I did it anyway in the next
step. The bot was reverted to its original policy and the run repeated.

---

## 14. ACT-AWARE ELITE SCALING + REACHABLE REMOVAL (2026-09-24)

Two changes, measured together over 10 seeds (42 runs after, 31 before):

```
                        BEFORE            AFTER
  act1 combat     89% win / 10% death   96% / 5%     <- intended control
  act1 elite      68% / 39%             72% / 28%
  act1 boss       63% / 32%             76% / 17%
  act2 combat     63% / 21%             70% / 35%
  act2 elite       0% (n=3)             20% (n=5)
  median fights/run        3                4
  runs reaching act 2   8/31 (26%)      19/42 (45%)
  deck at end           14.2             16.0
  % NEW CARDS            41%              50%
```

**The headline target is met: 50% new cards, up from 41%** — and runs reaching
act 2 nearly doubled, 26% → 45%. Deck size 14.2 → 16.0.

### Three caveats, and the first one is mine

1. **THE CONTROL MOVED, and the claim that it was a control was wrong.** Act-1
   combats went 89% → 96%. Nothing in the elite scale touches them — but the
   removal cap does, by way of the deck: a thinner deck wins ordinary fights
   more easily. Act-1 combat is a valid control for the ELITE change only.
   **For the removal change there is no within-run control**, because deck
   quality is upstream of everything. I asserted one existed when I ran this.
2. **The two arms are not the same seeds.** BEFORE is the earlier 606/909 data;
   AFTER is a fresh 12-seed sweep. Only two seeds overlap, so part of any
   movement is seed population rather than the change.
3. **The act-2 numbers are survivorship-shifted.** Before, 8 runs reached act 2
   and they were the strong ones; now 19 do, including marginal runs that would
   previously have died in act 1. Act-2 combat death rising 21% → 35% is at
   least partly a weaker population arriving, not act 2 getting harder.

### Still zero wins

`runs won` is 0 of 42. The earlier "1 win" in the BEFORE column is the
`hero_hp > 0` false positive §13 describes, now fixed — so the honest read is
that **no run has ever been completed**, before or after. Median fights/run is
4 against a 12-17 fight run: the changes moved the wall back, they did not
remove it. Act 2 remains where runs end.

### The 12-seed baseline, and what it reframed

Completing the sweep (12 seeds, 241 fights, 46 runs) makes the shape unmistakable
— and it is **not an elite problem, it is an ACT problem**:

```
  act/kind          n   win%  death%        act 1 -> act 2
  act1 combat     101    95%     5%         combat  95 -> 68   (-27)
  act1 elite       57    72%    28%         elite   72 -> 20   (-52)
  act1 boss        32    72%    22%         boss    72 -> 33   (-39)
  act2 combat      38    68%    37%
  act2 elite        5    20%    60%
  act2 boss         6    33%    67%

  median fights/run 4   deck 15.8   % NEW 49%   acts {1:25, 2:20, 3:1}
  RUNS WON 0 of 46
```

Act 1 is now well tuned — 95% on ordinary holds, 72% on both Generals and lords
is a real curve. **Every kind then drops 27-52 points at the act boundary,
together**, which is the signature of something that applies to every act-2
fight rather than to any one of them.

`ENEMY_BODY_HP_BY_ACT` is that something: **+1 HP on every enemy body**, against
a median authored enemy of 3 HP — a ~33% thickening of the entire hold, landing
on top of the face curve rising and against a deck that grows 12.4 -> 17.1 cards.
Changed `[0, 1, 2]` -> `[0, 0, 1]`: the curve keeps its shape and starts an act
later, so act 2 is a step rather than a wall.

**This one is measured properly.** The same 12 seeds, one variable, act 1
untouched as the control — which is the design the previous section had to be
caveated three ways for lacking. This 12-seed table is the baseline it is
measured against.

---

## 15. THE ACT-2 DIAL: TARGET HIT, RUN LENGTH UNMOVED (2026-09-24)

`ENEMY_BODY_HP_BY_ACT` `[0, 1, 2]` -> `[0, 0, 1]`. **Same 12 seeds, one
variable, act 1 as the control** — the design §14 had to be caveated for lacking.

```
  act/kind            BEFORE              AFTER
  act1 combat    n=101  95%w  5%d    n=106  95%w  5%d   <- CONTROL, identical
  act1 elite     n=57   72%w 28%d    n=39   74%w 26%d
  act1 boss      n=32   72%w 22%d    n=40   78%w 20%d
  act2 combat    n=38   68%w 37%d    n=45   76%w 22%d   <- the target
  act2 elite     n=5    20%w 60%d    n=13   38%w 69%d
  act2 boss      n=6    33%w 67%d    n=8    25%w 75%d

  HP cost:  act1 combat  3.6 -> 3.6      act2 combat 12.9 -> 11.5
            act1 elite  13.2 -> 11.6     act2 boss   23.3 -> 17.1
```

**The control is exact** — act-1 combat 95%/5% and 3.6 HP in both arms, over 100+
fights each. That is the experiment working, and it is what makes the rest
readable.

**The target moved:** act-2 plain combats 68% -> 76% win, death 37% -> 22%.

### And the run did not get any longer — which is the finding

```
  median fights/run   4 -> 4        deck 15.8 -> 15.5
  % NEW cards        49% -> 47%     RUNS WON  0 -> 0
  acts reached    {1:25, 2:20} -> {1:22, 2:24}
```

**Fixing ordinary act-2 combats does not extend runs, because runs do not end on
ordinary combats.** They end on the act-2 boss (25-33% win across both arms,
n=14 combined) and the act-2 General (38%). Everything else is noise around a
wall that did not move.

Two numbers say the act-2 economy is still not solvable:

- **a plain act-2 combat costs 11.5 hero HP against act 1's 3.6 — still 3.2x.**
  An act is 4-5 road fights, so ordinary combats alone bill ~50 HP against a 30
  HP bar with two camps;
- **mean hero HP entering a fatal fight is 21.0 of 30**, unchanged. Runs still
  die from a healthy position in a single fight, not by being ground down.

So the next lever is the act-2 BOSS specifically (a 45-point cliff from act 1's
78%, larger than the combat cliff just closed), not another global act-2 dial.
Recording the negative rather than stacking another change on top of it: the
dial did what it was aimed at and did not do what it was FOR.

## 16. THE WALL COMPOUNDED WITHOUT A CEILING — ONE PASSIVE, SEVEN ENCOUNTERS (2026-09-26)

§15 ended by naming the act-2 boss as the next lever. Chasing it produced a
better answer than "the act-2 boss is hard": **the fights on the floor are not
spread across the content, they are the seven encounters driven by one passive.**

### The signature

Per-encounter win rate over the 12-seed corpus (255 fights, `_before_wallcap`),
Generals and lords only, with every `formation_drill_tick` encounter marked:

```
  kind   act encounter                    n won  win%   hpIn  hpOut
  boss     1 THE ACOLYTE                 11  11  100%   23.2   15.4
  boss     1 THE PYROMANCER              14  10   71%   23.4   15.4
  boss     1 THE KINDLER                 10   7   70%   20.7    9.4
  boss     1 THE STALWART          <---   5   3   60%   23.2    8.8
  boss     2 THE ACOLYTE                  4   2   50%   17.0   12.0
  boss     2 THE STALWART          <---   3   0    0%   20.7  -13.7
  boss     2 THE PYROMANCER               1   0    0%   12.0   -2.0
  elite    1 The Reading Room              9   8   89%   25.4   18.4
  elite    1 Where the Dead Come Back      8   7   88%   24.5   18.2
  elite    1 The First Spark               7   6   86%   21.7   15.0
  elite    1 The Mausoleum                 4   3   75%   24.2   21.2
  elite    1 The Unfinished Wall    <---   6   2   33%   25.0   -4.2
  elite    2 The Unfinished Wall    <---   4   2   50%   18.0    0.8
  elite    2 The Testudo            <---   1   0    0%   20.0   -8.0
  elite    2 THE BURIED ARMY        <---   1   0    0%   32.0  -21.0
```

`The Unfinished Wall` at 33% is **the worst act-1 General in the game** — every
other act-1 General sits at 75-100%. Its four losses end at hero **-12, -12, -4,
-26** against a foe face still holding **1, 2, 6, 8**: those are routings, and
the player got within one point of the kill twice.

A single encounter that low is tuning. A whole family that low is a rule.

### The rule

`EncounterEffects.formation_drill_tick` gives **every enemy body with a
neighbour +1/+1, every round, forever.** Seven encounters carry it, in three
escalating tiers, and it is the Last Wall's whole identity:

| passive | rows | from round | encounters |
|---|---|---|---|
| `formation_muster` | front only | 3 | THE STALWART (act 1), The Unfinished Wall |
| `formation_drill` | both | 2 | The Testudo, THE STALWART/RAIDER ASCENDANT |
| `formation_lockstep` | both + Armored front | 2 | THE BURIED ARMY, STALWART phase 2 |

There was no cap. An eight-round fight against `formation_drill` hands a 4-body
line **+7/+7 each** — 56 stat points, for free, on top of an infinite
reinforcement drip. **That is not a hard fight, it is an unbounded one**, and it
is why the losses are routings rather than near misses: the wall wins by
outgrowing any answer, so the round the player fails to kill it is the round the
fight was already over.

`ENEMY_BODY_HP_BY_ACT` (§15) could never touch this. That dial adds a flat
constant at spawn; this is a per-round multiplier on the whole line.

### The fix

`FORMATION_MAX_STACKS = 3`, counted **per body** in a node meta:

```gdscript
var stacks: int = int(c.get_meta("formation_stacks", 0))
if stacks >= FORMATION_MAX_STACKS:
    topped_out = true
    continue
c.set_meta("formation_stacks", stacks + 1)
```

Three properties are deliberate:

1. **PER BODY, not per fight.** A creature arriving on round 6 still gets its own
   drill — it simply cannot exceed the same ceiling as the one that has stood
   since the muster. A per-fight counter would make late reinforcements arrive
   pre-capped, which reads as the passive breaking.
2. **A meta, not a `CreatureInstance` field.** This is within-fight state, and
   every field on that class has to be round-tripped by both snapshot formats
   (C8 enumerates them from `get_property_list()`). A fight does not survive a
   save, so a field would be pure cost.
3. **The ceiling is ANNOUNCED.** When every body is capped, `grew` stays false
   and the three existing announce arms all fall through — the wall would have
   stopped growing in silence, which is the silent-refusal class this codebase
   treats as a bug. A fourth arm says *"The wall is built — it grows no
   further."* The growth line has fired every round up to that point, so its
   bare absence would read as the effect breaking rather than as the wall being
   finished.

The wall still outpaces the player early (+3/+3 on a 4-body line is 24 stat
points by round 5), still ends taller than it started, and still means what its
name means. What changes is that **"you cannot win this" becomes "you have five
rounds"** — and a player can see the clock, because it is spoken.

### THE LADDER: some families can STEP instead of being dropped (2026-09-26)

§17's blanket drop is the fallback. The Wall's formation engine does not need it,
because **this family's three passive ids ARE its act scale** — EncounterDB says so
in its own words at `the_unfinished_wall`:

> *"Act 1 teaches it on four bodies in one row from round 3; act 2 moves it to both
> rows and a round earlier; act 3 adds the Armored grant."*

So a borrowed formation fight should not lose its rule and must not keep the wrong
rung. `EncounterDB.PASSIVE_ACT_LADDERS` + `get_passive_for` step it down one rung
per act travelled:

```
  STEPPED  The Testudo       authored a2 -> dealt a1   *formation_drill    -> *formation_muster
  STEPPED  THE BURIED ARMY   authored a3 -> dealt a2   *formation_lockstep -> *formation_drill
```

Both are measured disasters. `The Testudo` dealt at ACT 1 took a hero from **32 HP
to -13 in six rounds** — a one-act borrow is INSIDE `PASSIVE_TRAVEL_LIMIT`, so the
blanket drop could never have caught it, and it handed an act-1 board both rows
drilling from round 2 when the act-1 rung is front row only from round 3. Pooled
over every archived arm it is 29% win at 25.0 HP (n=7). `THE BURIED ARMY` at act 2
went 0 of 1 ending at hero -21.

**Downward only, and that asymmetry is a decision about evidence rather than about
symmetry.** Stepping a borrowed act-1 lineup UP to the act-3 rung is the honest
reading of "the rungs are the act scale" — act 3 offers 8 combats of which 5 are
act-1 fights, so it is too EASY by the same mechanism. It is not done, because act
3 is reached in 1 run of 47: raising difficulty on a path no measurement can see is
how you break something and find out months later.

### THE CAP CHANGED THE RULE, SO THE RULE HAD TO BE REWRITTEN

Nearly shipped wrong. `FORMATION_MAX_STACKS` makes the growth bounded, and all
**16** authored `passive_desc` strings still promised it forever — the ONBOARDING
§5 rule that rules text is a design surface, failing in the direction that costs
the player most: the entire value of the cap is that *"you cannot win this"*
becomes *"you have five rounds"*, and a clock nobody is told about is not a clock.
Every one now reads "...gains +1/+1, **up to three times each**", `PASSIVE_RUNG_DESC`
carries the canonical sentence per rung, and **phase G of the gate fails if any
authored desc carrying a ladder rung stops saying so.**

`_probe_copy_lint` caught the new dictionary immediately — *"PASSIVE_RUNG_DESC is a
container constant this probe never reads"* — which is `reference_copy_lint_flat_dict_hole`
working as designed. It is scanned now (`_scan_passive_rungs`, same register rules
and same 32-word passive budget as any `passive_desc`); `PASSIVE_ACT_LADDERS` holds
only passive IDs and is a genuine waiver.
### The gate

**`tools/_probe_formation_cap.tscn` — 39 checks.** `formation_drill_tick` is
STATIC and takes its ctx as an argument, so the whole rule runs on stubs with no
Combat scene and no board; that is also the standing check that it stays
ctx-parameterised. It is a SCENE rather than `--script` (unlike its cousins
`_probe_board_eval` / `_probe_personas`, whose whole point is that they name no
autoload) because `EncounterEffects` names `CardDB`, and a `preload` of it in a
`--script` probe is dragged into the pre-autoload compile and fails outright.

Six phases: the ceiling holds over a 12-round fight; a late arrival gets its own
full allowance while the veteran does not resume; a body with no neighbour never
drills (the drill is adjacency-gated); all three tiers cap while keeping their own
cadence and `lockstep` still grants Armored to bodies whose stats are already
capped; **every round of a formation fight says something**; and the whole line's
gain is bounded.

**Mutant-verified** by deleting the guard: 16 of 39 checks fail, and the failures
are the defect in plain numbers —

```
  a capped body is not re-displayed    updates grew 12 -> 13
  the veteran did not resume           atk=13 expected 5
  growth was announced 3 times         growth lines=12
  a full line's gain is bounded at 48  gained=192
```

**192 free stat points across one line in a 12-round fight, against 48 capped**,
and single bodies reaching +12/+12. Restore checksum-verified.

Two oracle lessons, both the house rule that the test is the likelier fault:
the first draft of the late-arrival phase placed the veteran ALONE, so adjacency
correctly refused to drill it and the phase read as the cap failing; and the
mutant refused to inject three times because the file is CRLF and the anchor was
built with `
` — `reference_crlf_python_edit_trap`, paid for again.
### A second finding the journal surfaced: the face tie is silent and one-sided

Both rows strike simultaneously, so both faces can reach 0 in the same clash.
`Combat._check_game_over` resolves it one way:

```gdscript
if player_hp <= 0:        # defeat
elif enemy_hp <= 0:       # victory
```

**Measured: 5 of 255 fights (2.0%) ended with both faces at or below 0**, and
three of the five are formation-family encounters — the long fights that end on a
knife edge:

```
  THE ACOLYTE          boss  act1   hero  -5   foe  0    16 rounds
  The Powderkeg Run    comb  act2   hero -12   foe -1    12 rounds
  The Unfinished Wall  elite act2   hero   0   foe  0     6 rounds
  THE BURIED ARMY      elite act3   hero  -2   foe -3     6 rounds
  The Testudo          elite act1   hero -12   foe -2     8 rounds
```

This is an **internal inconsistency, not obviously a bug**: the game has an
explicit rule that creature trades ARE mutual (`Card2D.defer_deaths` exists for
precisely that, so a simultaneous kill kills both bodies), and the face follows
the opposite rule. 2% of fights are decided by a precedence the player is never
told, and it always goes against them. Flagged rather than changed — game-ending
precedence is a design call, not a tuning one.

The instrument had the same fault and it is fixed: the pilot recorded `won` and
`died` as independent observations, so a mutual kill read as **both**, inflating
the win rate by 0.8pp (80.8% -> 78.8% on this corpus). The precedence now lives
in `analyse_journal._apply_verdict_precedence`, **not** in the recorder — which
is what lets it apply retroactively and uniformly to every archived arm instead
of becoming an instrument change in the middle of a measurement.

## 17. HALF THE FIGHTS IN THE GAME ARE AUTHORED FOR A DIFFERENT ACT (2026-09-26)

§16's per-encounter table had one entry that made no sense: **`Where the Old Drake
Sleeps` is an act-1 ORDINARY combat at 0% win, costing 30.5 hero HP** — against an
act-1 plain-combat average of 95% and 3.6 HP. An 8.5x bill, on the gentlest tier
in the game, killing from full.

It is not an act-1 encounter. It is authored **act 3**.

### The mechanism

`EncounterDB.get_kingdom_pool(act, type, faction)` tops a thin faction pool up
from neighbouring acts, `dist` 1 then 2. `tools/_probe_pool_borrow.tscn` runs the
real function over every faction x act x type and reports:

```
  pool entries offered              149
  BORROWED from another act          81  (54%)
  ...from TWO acts away              14
  borrowed AND carrying a passive    69
  two acts away AND a passive        11   <- the shape that cost 30 HP
```

**54% of every pool entry in this game is authored for a different act than the
slot it is dealt into.** The worst two:

```
  everflame  combat a1   5 entries, 4 borrowed, 2 from ACT 3
             ... incl. Where the Old Drake Sleeps *drake_breath, The Pyre Cult *pyre_spread
  owed       boss   a1   3 entries, ALL 3 borrowed, 2 from ACT 3
             ... incl. THE BLACK TIDE *tide_swell, THE CRONE *cauldron_brew
```

It runs **both ways**: `grasswake` act 3 offers 8 combats of which **5 are act-1
fights**, which makes act 3 too easy by the same mechanism that makes act 1 too
hard.

### What already scaled, and the one thing that did not

Combat knew about this. `Combat.gd:2101`, three lines above the defect:

> *"Successor Wars cross-act borrows: scale the fight to the map slot it actually
> landed in (kingdoms pull their faction's fights from other acts; demoted bosses
> fight at elite band)."*

Face HP goes through `get_face_hp(enc, t_act, t_type)`. The deck goes through
`build_enemy_deck(enc, t_act, ...)`. Both take the TARGET act. And then:

```gdscript
_encounter_passive = enc.get("passive_id", "")      # raw
```

**A standing rule is not a number, so it cannot be rescaled** — there is no
arithmetic that moves `drake_breath` down two tiers. It was the only thing read
off the authored entry, and it is the only thing that could not be fixed by the
scaling that was already there.

### The fix: a passive has a RANGE

`EncounterDB.PASSIVE_TRAVEL_LIMIT = 2` + `get_passive_for(enc_id, target_act)`,
a funnel beside `get_face_hp` and `build_enemy_deck` and taking the same target
act. A lineup dealt two or more acts BELOW where it was written fights without
its standing rule.

**The direction is asymmetric, and that is what makes a small fix correct.**
Borrowing DOWNWARD (an act-1 lineup at act 3) lands an easy rule on a strong
deck — harmless, and dropping it there would only make a soft fight softer.
Borrowing UPWARD two acts lands an act-3 rule on an act-1 deck, and that is what
the 30 HP was.

**What it does NOT do is shrink any pool.** The obvious alternative — stop
borrowing that far — trades a measured good for a measured good: CLAUDE.md's
2026-09-13 pass established that the larger pools are precisely why repetition is
*not* a problem here (every kingdom-act offers 4-8 distinct combats). The lineup
still appears, at correct stats, with its faction flavour intact. Only the rule
stays home.

`passive_desc` travels with the id in one dictionary, because the two must never
disagree: the edict banner is keyed off the id being non-empty, and a banner
posting a rule the fight does not have is worse than a fight with no rule.
`MapView`'s route tooltip reads the same funnel at the same target act, for the
same reason.

Measured, through the real pool:

```
  STOPPED  Where the Old Drake Slee  authored a3 -> dealt a1   *drake_breath
  STOPPED  The Hall of Wrong Reflec  authored a3 -> dealt a1   *mirror_instant_place
  STOPPED  The Pyre Cult             authored a3 -> dealt a1   *pyre_spread
  STOPPED  THE BLACK TIDE            authored a3 -> dealt a1   *tide_swell
  STOPPED  THE CRONE                 authored a3 -> dealt a1   *cauldron_brew
  stopped (borrowed UP >= 2 acts)    5 pool entries
  kept    (borrowed DOWN >= 2 acts)  6  — deliberate
```

Five entries, and they include both of the worst things in the corpus: the 0% /
30.5 HP act-1 combat, and THE BLACK TIDE, the hold CLAUDE.md §3b measured
deploying **26 bodies through round 11**.

### Deliberately NOT extended to boss phases, and the evidence for stopping

A boss is PHASED, so `get_passive_for` only removes its OPENING rule; its phase
rules still come from `get_boss_phases`. That is a real half-measure — and it is
unreachable. Over **108 recorded boss fights across five archived arms, every
single keep was a rival-LORD kit**:

```
  31x act1 THE ACOLYTE   25x act1 THE PYROMANCER   24x act1 THE KINDLER
  11x act1 THE STALWART   6x act2 THE ACOLYTE       6x act2 THE STALWART
   4x act2 THE PYROMANCER  1x act3 THE ACOLYTE
```

THE CRONE and THE BLACK TIDE have never been dealt as a keep at all — the keep
comes from the rival-lord table, not from the boss pool. Threading the limit
through `get_boss_phases` would be complexity paid for a path nothing reaches,
and `get_passive_for` already covers those two harmlessly if they ever are dealt.

### The root cause is content, and this is a mitigation

CLAUDE.md states it: **8 of the 15 faction x act elite slots are empty and five
combat pools hold a single authored fight.** Borrowing exists because the pools
are thin, and the travel limit makes borrowing fair rather than making it
unnecessary. Authoring one combat and one elite per empty faction/act slot would
remove the need entirely; nothing here is a substitute for that.

### Probe

`tools/_probe_pool_borrow.tscn` — reports, does not fail. How much a pool borrows
is a function of the authoring backlog, so a threshold would fail on the content
gap rather than on a defect, and a pinned list of affected entries would be
re-blessed with every new encounter and stop meaning anything. **The count is the
signal**, and it prints a NOTE if nothing is stopped at all, which is the tell
that the funnel came unwired.

## 18. THE CLASS, NAMED: AN UNBOUNDED RULE ON A MANDATORY TIER (2026-09-26)

§16 and §17 were found one fight at a time. Pooling **57 journals across 14
archived arms** (build-MIXED — valid for identifying outliers, never for measuring
a change) gives enough n per encounter to see what they have in common.

### The baseline first, because the outliers are only readable against it

```
  act1 PLAIN COMBATS, n >= 10             n  win%  die%  HPcost  rnds
    The Lamplighters                     68  100%    0%     0.4   4.7
    The Border Toll                      56  100%    0%     0.6   5.4
    The Sunken Road                      21  100%    0%     5.0   5.0
    The Spore-Cathedral                  11  100%    0%     6.6   5.3
    The Field That Watches Back          65   97%    0%     1.0   5.4
    The First Cut                        32   97%    0%     0.9   5.3
    The Signal Glass                     11   91%    0%     2.2   5.9
    The Powderkeg Run                    52   85%   15%     9.6   7.8
```

**An ordinary act-1 hold costs 0.4 to 9.6 hero HP.** That is the tier's price.

### The outliers, worst first

```
  act kind   encounter                        n  win%  die%  HPcost  rnds   cause
    2 elite  The Unfinished Wall             10   10%   90%    26.3   5.9   formation *
    2 boss   THE STALWART                     8   12%   88%    26.2   8.2   formation *
    2 combat The Tooth-Stones                11   18%   73%    24.9   6.7   sentinel_stone
    2 elite  The Glass Menagerie              5   20%   60%    18.8   5.4   -
    1 elite  The Testudo                      7   29%   71%    25.0   6.3   formation * + ladder *
    1 elite  The Unfinished Wall             20   30%   70%    27.8   6.5   formation *
    1 combat The Forge That Eats              9   33%   67%    23.1   9.1   forge_heat
    1 elite  The Threshold Choir             12   50%   33%    13.8   6.9   -
    1 boss   THE STALWART                    17   35%   59%    20.3   8.4   formation *
    1 combat The Tooth-Stones                 8   38%   50%    20.1   7.9   sentinel_stone
    2 combat The Powderkeg Run               12   42%   58%    21.2   9.7   -
                                                              (* fixed in §16/§17)
```

### The class

Every entry above the 50% line is one of two things, and the second is the same
shape as the first:

1. **`formation_drill_tick`** — +1/+1 per round, uncapped. §16.
2. **A per-round escalation on an ORDINARY `type: "combat"` encounter**, also
   uncapped:
   - **`sentinel_stone`** (The Tooth-Stones) — `c.current_atk += 1` across the
     whole enemy front row, every round from 2, forever. Eight rounds is +7 ATK on
     up to four bodies.
   - **`forge_heat`** (The Forge That Eats) — 1 damage to ALL your creatures, 2
     from round 3, **bypassing Armored**, for the whole fight. A 9.1-round fight
     is ~16 damage to every body you own.

**THE RULE THIS NAMES: a boss or a General may carry an unbounded clock; an
ordinary hold may not.** A keep is fought once and is chosen; a General can now be
walked past (the 2026-09-19 fight-count pass made elite bands bypassable). A plain
combat is **mandatory 3 times an act on the spine and 4-5 on a typical route**, and
the road returns ~3 HP per gap. A tier billing 20-25 HP per stop against a 30 HP
bar is not difficult, it is unsolvable, and it is unsolvable in a way no dial in
`Combat.gd` can reach — `ENEMY_HP_SCALE` and `ENEMY_BODY_HP_BY_ACT` add constants
at spawn, and what is wrong here is a slope.

### `sentinel_stone`'s own comment already records one pass at this

> *"Was 2 face on a pure clock, and the Tooth-Stones were the single worst offender
> in Act 1 — a five-hero simulation died here on 4 of 5 seeds. Deliberately
> strike_the_champion, NOT strike_the_line."*

That pass moved the **face** damage onto a creature and left the **uncapped ATK
ramp** standing. The fight is still the worst non-formation combat in the game, at
38% on act 1 and 18% on act 2. The measured lesson is that the ramp, not the
tremor, was carrying it.

### NOT CHANGED YET, AND DELIBERATELY

The arm measuring §16 + §17 is running. Landing a third change into it would
repeat the exact methodology error this session has already paid for once (and
repeated once more today — `get_passive_for` landed while seeds were in flight,
which is why that sweep was killed and restarted; the three clean wall-cap-only
seeds are archived at `_wallcap_only_3seed`).

Next single variable, in order of measured cost:

1. **Cap `sentinel_stone`'s dig-in** the way `formation_drill_tick` is now capped
   — same per-body meta, same announced ceiling. Two capped growers is the point
   at which the cap wants to be a shared helper rather than a second inline copy;
   `formation_drill_tick` should not be the only spelling of "this body has
   drilled N times."
2. **`forge_heat`** does not escalate past round 3, so a stack cap does not apply —
   its problem is magnitude x duration. It already has a step (1 -> 2 at round 3);
   the lever is that step, not a ceiling.

Neither is a guess about balance: both are the same measurement that found the
formation family, read off the same corpus, against a baseline from the same
corpus.

## 19. THE NUMBER THAT JUSTIFIES §16-§18 (2026-09-26)

Win rate finds fights that KILL you. It is blind to the other way a run dies: a
fight you WIN that bills three times its tier, met four times an act. Since the
run-length blocker is the HP economy, the ordering that actually answers "what
would I fix" is **total hero HP billed** — `n x cost`, not win rate.

`analyse_journal.py` §9 now prints both. Over the 12-seed corpus (2,135 hero HP
across 255 fights):

```
  cause                                      fights   HP    share of ALL HP spent
  formation, uncapped        (§16 FIXED)         22   568         26.6%
  unbounded on an ordinary hold (§18 NEXT)        7   169          7.9%
  borrowed 2 acts up         (§17 FIXED)         11   114          5.3%
  everything else                               215  1284         60.1%
```

**8.6% of the game's fights were spending 26.6% of every point of hero HP.** One
encounter — `The Unfinished Wall` — is 8.2% of the corpus's entire HP bill on its
own. Today's two fixes touch fights accounting for **31.9%** of it; §18's two
ordinary holds are another 7.9%.

That is the argument for having chased the mechanism rather than turning a global
dial. `ENEMY_HP_SCALE` and `ENEMY_BODY_HP_BY_ACT` spread a change across all 255
fights — including the 68 Lamplighters wins that cost 0.4 HP each and did not need
help. A third of the bill was concentrated in a thirteenth of the fights, and all
of it was one of two things: unbounded, or authored for a different act.

### The view also names a class win rate cannot see

```
    act kind    encounter                    n  win%   HP each   TOTAL  share
      1 combat  The Powderkeg Run            12  83.3%      10.0     120   5.6%
```

`The Powderkeg Run` **wins** 83% of the time and is the **second largest HP drain
in the game** — 2.9x its tier's cost, and it is the most common act-1 combat in the
corpus (52 appearances pooled across all arms). It would never appear on a
difficulty list. Ranked by drain it is second only to the worst General in the
game. No fix is proposed here, because "wins but bleeds" may be exactly what a
powderkeg fight should feel like — but it belongs on the list, and nothing in this
harness could see it until the ordering changed.

## 20. EVERY NUMBER IN THIS DOCUMENT IS ABOUT ONE HERO OF FIVE (2026-09-26)

Found by accident, and it is the most important methodological limit in the file.

Chasing why `The Long Drumming` (an act-1 General) had **never been met once** in
~700 fights turned up a whole missing kingdom:

```
  faction        authored   ever met
  grasswake            12          1
  everflame            11          7
  lanternhall           9          7
  last_wall             7          5
  owed                 17         12
```

Eleven of grasswake's twelve encounters have never been fought — including four
act-1 ROAD COMBATS (`The Den Mother's Brood`, `The Toll-Takers`, `The Stooping
Wings`, `The Trampling Hour`). That is not the act-3 gap that explains most of the
other misses. And grasswake is, per `_probe_pool_borrow`, the **best-authored
faction in the game** — the only act-1 combat pool that needs zero borrowing.

### The cause

```
  every BOSS met across 167 boss fights:
    59x THE ACOLYTE   41x THE PYROMANCER   35x THE KINDLER   32x THE STALWART
     0x THE RAIDER
```

`RunState._select_rivals` excludes the player's own lord from the rival pool. So
THE RAIDER being absent means the pilot is THE RAIDER — and it is, in every run
ever recorded:

**`marching_spurs`, the Raider's signature relic, is the first relic held in 236 of
236 runs.**

And the mechanism is worse than a bad choice — **the pilot never picks a hero at
all.** `_drive_main_menu` presses NEW RUN, then presses START RUN, and never
touches the roster; `MainMenu.gd:2292` initialises `_selected_hero =
HeroDB.HERO_ORDER[0]`, which is `"raider"`. So the instrument silently inherited a
GAME default and then measured it 236 times. THE RAIDER is grasswake's lord, so
grasswake is never the marched kingdom, so its column is dead content — to this
instrument.

(Noted in passing: the constant literally named `HeroDB.DEFAULT_HERO` is
`"stalwart"`, not the hero a player gets by default. The two serve different jobs —
one is the setup screen's initial selection, the other an invalid-id fallback — so
this is not a defect, but the naming will mislead the next person who greps for
"which hero do you start as".)

### What this does and does not invalidate

**Does not:** §16, §17 and §18 are mechanisms, established by reading the code and
by gates, not by win rates. 192 free stat points on one line in a 12-round fight is
indefensible for any hero; a rule authored two acts up is mis-scaled for any hero.
Those stand.

**Does:** every win rate, every HP cost, and the §19 share table are **Raider
numbers**. And there is a specific reason to think the Raider flavours them hard —
the Raider's kit is MOBILITY (relocate into Swift, the lightest retinue in the
game), and the fights that measured worst are the formation walls: Armored bodies
that grow HP every round. Swift and repositioning do nothing against a wall that
out-heals your damage. **The formation family may be the worst fights in the game,
or it may be the worst fights FOR A RAIDER, and this corpus cannot tell those
apart.** THE STALWART's own kit is adjacency and repair — the mirror of that
matchup.

This is the `Personas.gd` validity rule (2026-09-16) on an axis nobody applied it
to: *a difficulty conclusion is only ever true relative to the agent that produced
it.* Personas fixed the PLAYSTYLE axis and left the HERO axis pinned at one value.

### The fix, in two parts

1. **RECORD IT.** The journal writes `seed`, `policy`, `greedy`, `budget`,
   `coach` — and not the hero. That is why this went unnoticed for the entire
   session: nothing printed a hero name, so nothing looked wrong. A header field
   costs one line and would have made the hole visible on day one. **An
   uninstrumented constant is invisible in exactly the way a varied one is not.**
2. **VARY IT.** Rotate the hero per run (`HERO_ORDER[run_index % 5]`), which also
   unlocks the rival pool: with the Raider as a rival, grasswake's twelve
   encounters become reachable and four of the five hero decks get measured for the
   first time.

Until (2) lands, the honest statement of this document's scope is: **a Raider's
difficulty curve, measured well.**

## 21. THE RESULT: THE HP BILL FELL, THE RUN DID NOT GET LONGER (2026-09-26)

Same 12 seeds, one build, §16 + §17 together (both are the same class — an enemy
rule that is unbounded or authored for another act — bundled deliberately, and the
three clean wall-cap-only seeds are archived at `_wallcap_only_3seed`).

```
                                        BEFORE     AFTER
  runs finished                             47        48
  RUNS WON                               0/47      0/48
  fights won                             78.8%     77.0%
  median fights per run                      4         4
  mean deck at end                        15.5      15.0
  act1 / act2 / act3 reached           22/24/1   25/20/3
  total hero HP spent                     2135      2037

  formation family        n                 22        16
                       win%                27%       31%
                    HP each               25.8      20.2   (-22%)
       share of ALL HP spent              26.6%     15.9%   (-40%)

  borrowed 2 acts up      n                 11        11
                       win%                73%       64%
                    HP each               10.4       7.3   (-30%)
       share of ALL HP spent               5.3%      3.9%
```

**What the fixes did:** the targeted fights cost 22-30% less hero HP, and the
formation family's share of the run's entire HP bill fell from 26.6% to 15.9%.
Per-encounter: `The Unfinished Wall` 29.2 -> 21.3 HP, `The Testudo` (the ladder
case) 35.0 -> 24.2.

**What they did not do: the bot still won zero runs, and the median run is still
four fights.** Act-3 reach went 1 -> 3, which is the right direction and is n=3.

### FIRST, THE CONTROL — it appeared to move, and that was composition

```
  act1 combat win% (n)     95% (106)  ->  89% (108)      <- alarming
  act1 combat, COMPOSITION-MATCHED over the 11 encounters in BOTH arms:
      win%  98% -> 98%        HP each  3.2 -> 4.0        <- flat
```

The drop was entirely the MIX. `The Tooth-Stones` (0% in both arms, ~32 HP) went
n=1 -> 5, while `The Lamplighters` and `The Border Toll` (100%, ~0.4 HP) fell 25 ->
20 and 18 -> 9. The fights did not get harder; the route met harder ones.

**That is a real feedback path and it must be accounted for in every future arm of
this experiment**: the pilot's chart policy routes on HP, gold, deck and node type,
so a change that leaves the hero healthier changes WHERE IT WALKS. A per-tier win
rate is therefore not a fixed-composition measurement, and comparing tiers between
arms without matching the encounter mix will attribute a routing shift to a balance
change. Match on the encounter, or read the mechanism.

### SECOND, AND THIS IS THE BIGGER FINDING: 12 SEEDS CANNOT RESOLVE A TIER

The swings on encounters **none of these changes touch**:

```
  The First Spark             86% ->  33%   (7 -> 6 fights)    -53pp
  The Reading Room            89% ->  40%   (9 -> 5 fights)    -49pp
  The Threshold Choir          0% -> 100%   (2 -> 5 fights)   +100pp
  The Mausoleum               75% -> 100%   (4 -> 9 fights)    +25pp
  Where the Dead Come Back    88% ->  73%   (8 -> 11 fights)   -15pp
```

Against the binomial noise floor:

```
  n=5   1sd = 17.9pp      n=16   1sd = 11.5pp
  n=9   1sd = 10.0pp      n=46   1sd =  7.0pp
  n=11  1sd = 13.8pp      n=256  1sd =  2.6pp
```

**Untouched content swung by up to 100 points.** Every per-encounter and per-tier
win rate in this corpus is inside its own noise, and §15's tables — which read
act-2 elite "20% -> 38%" off n=5 and n=13 — were reporting variance. That reading
was wrong in method even where it happened to be right in direction.

Only three quantities here are outside the noise, and they are outside it because
they aggregate or because they are mechanical:

- **total hero HP spent** (2135 -> 2037), over 255/256 fights;
- **a family's share of all HP spent** (26.6% -> 15.9%), over 22/16 fights but
  measuring a continuous quantity rather than a coin flip;
- the **gate's** own numbers — 192 free stat points -> 48 over 12 rounds — which
  are arithmetic, not sampling.

**The lesson for this harness: measure the HP BILL, not the win rate.** HP cost is
continuous, accumulates per fight rather than per encounter, and is the quantity
the run-length problem is actually about. A win rate at these sample sizes is an
expensive way to read a random number, and the 77 minutes a 12-seed arm costs buys
about 2.6pp of resolution on the one aggregate figure it can support.

### THIRD: WHY THE RUN DID NOT GET LONGER

A 4.6% cut to the total HP bill is not going to move a median. The HP economy
(§13, §15) bills ~8.6 HP per fight against ~3.0 recovered per gap; removing 98 HP
across 48 runs is ~2 HP per run. **The formation fix was correctly aimed and far
too small to be the answer on its own**, which is the same shape as §15's negative
result: each individual mispriced fight is worth a couple of HP per run, and the
gap is tens.

§19 already says where the rest is: those two `sentinel_stone` / `forge_heat`
ordinary holds are another 7.9% of the bill, and 60% sits in "everything else" —
i.e. in the per-fight cost of ordinary combat, not in outliers. The outliers were
worth fixing (they were indefensible), and the remaining work is the ECONOMY rather
than the encounter table.

### AND THE SCOPE, RESTATED

Every number above is THE RAIDER (§20). The formation walls the cap targets are
the Raider's worst matchup in the game — Armored bodies that grow HP, against a kit
built on Swift and repositioning. A Stalwart arm may well report a different
ranking of the same content, and until the hero rotates, this is one hero's curve.

## 22. THE ROTATION, BUILT (2026-09-26)

§20's two-part fix, both halves live and verified end to end before any sweep was
spent on them.

### 1. RECORD IT — `_jr_ctx()`, so it lands on every record

The hero now rides the per-record context dictionary rather than only the header,
which is the right place for the same reason `_jr_ctx` exists at all: a decision is
worthless without the state it was made in, and "which kit was holding this deck"
is part of that state. One field, and it would have exposed this on day one.

### 2. VARY IT — `_pick_hero_for_run()`, before START RUN

The pilot now presses a roster tile. Four properties, each a decision:

- **DETERMINISTIC on the run index**, not random. A seed must still reproduce, and
  a random hero would make two arms of the same seed disagree about which kit they
  measured — the one thing a matched A/B cannot survive.
- **Resolved off `MainMenu._hero_cards`, then CLICKED** with the synthetic cursor.
  Calling `_focus_hero` directly would bypass the input pipeline this entire probe
  exists to exercise. Resolve from state, drive through the pipeline — what every
  other policy here does.
- **Ordered by `HeroDB.HERO_ORDER`** when the autoload is reachable, else by sorted
  key, so the rotation is reproducible either way.
- **A missing roster is LOGGED, not swallowed.** If the screen ever stops exposing
  `_hero_cards` the pilot prints *"roster not reachable — this run takes the
  screen's default"*, because the failure mode being repaired is precisely a silent
  reversion to one lord.

### Verified before spending 77 minutes on it

```
  lords played     raider x1, stalwart x1
  run 0: hero = raider    (117 records, marching_spurs held)
  run 1: hero = stalwart   (29 records)
```

**The press is not the oracle** — `_click_control` returning true says a click
landed, not that the lord changed. The check above reads `hero` off RunState, and
run 0 additionally carries `marching_spurs` (the Raider's signature relic) while
run 1 does not. Same split the muster uses, where a successful press proved nothing
and the DECK COUNT was the answer.

### Two report surfaces so this cannot go quiet again

- **The pilot's COVERAGE block** prints `lords played`, and prints `NONE PICKED —
  every run took the roster default` when the tally is empty. A single value there
  is now visibly a coverage hole rather than an invisible one.
- **`analyse_journal.py` §10 THE LORDS** reports per-lord fights, win rate, HP per
  fight, deepest act and final deck, then the **ENVELOPE** — because a wide HP
  spread means the content is a MATCHUP against particular kits rather than a
  difficulty level, and only a spread can tell those apart. It also lists the RIVAL
  LORDS MET, since a lord missing there is a KINGDOM missing (rotating the hero is
  what makes grasswake reachable at all: `_select_rivals` excludes your own lord).

  It distinguishes **two different failures in different words**: an archived arm
  with no `hero` field reports *"LORD NOT RECORDED"* and says it cannot prove which
  kit it was, while a CURRENT arm showing one lord reports that the rotation itself
  is broken. Telling a reader of a pre-2026-09-26 journal that it "was one lord"
  would be asserting something the file cannot see.

### Also corrected: "a hero opens on 11"

The pilot's report string said 11 in two places. Every `HeroDB` deck is a **10**-card
list, and CLAUDE.md already flagged that this wrong number had been quoted out of
this report string and into the docs. Fixed at the source.

### What this arm is, and what it is not

The five-hero arm is a **NEW BASELINE**, not a comparison against §21. Rotating the
hero changes what gets measured far more than any balance dial does, so nothing in
it is comparable to the Raider-only corpus. §18's two ordinary holds are
deliberately NOT in it, so they can be the next single variable against a baseline
that finally spans the roster.

Per-hero sample size will be ~9-10 runs at 12 seeds, which §21's noise floor says
is far too thin for a per-hero WIN RATE. Read the HP-per-fight column and the
envelope; that is what §21 concluded this harness can actually resolve.

## 23. THE HERO AXIS IS THE BIGGEST EFFECT IN THE GAME (2026-09-26, INTERIM n=3 seeds)

First three seeds of the five-hero arm. **Interim and thin — 2 to 5 fights per
(lord x tier) cell — so read the HP column and the spreads, never the win rates
(§21).** Recorded here because the effect size is not marginal.

```
  lord          runs  fights    win%  HP/fight  act max    deck
  kindler          3      20   80.0%       6.7        2    19.0
  raider           5      21   76.2%       8.6        2    16.0
  acolyte          4      11   63.6%       9.5        1    12.8
  stalwart         4       9   55.6%      18.1        1    11.5
  pyromancer       3       6   50.0%      15.5        1    12.3

  ENVELOPE across 5 lords:  HP/fight 6.7 - 18.1  (spread 11.4, i.e. 2.7x)
```

Broken out by tier:

```
  lord              combat            elite             boss
  acolyte        7f  0.9hp        3f 25.7hp        1f 22.0hp
  kindler       12f  3.5hp        4f 14.0hp        4f  9.0hp
  raider        13f  4.9hp        5f 18.6hp        3f  7.7hp
  stalwart       6f  7.2hp        3f 40.0hp               -
  pyromancer     4f  8.5hp        2f 29.5hp               -
```

**A General costs a Kindler 14 HP and a Stalwart 40.** An ordinary hold costs an
Acolyte 0.9 and a Pyromancer 8.5 — a **9x** spread on the tier the run meets most
often. §13's headline finding, "a General costs 4x a hold", is 4x for a Kindler and
**28x** for an Acolyte.

**This is larger than anything encounter tuning moved all session.** The formation
cap — a defect where one line gained 192 free stat points — shifted the TOTAL HP
bill by 4.6%. The gap between the cheapest and dearest kit is 2.7x on the same
content. If the goal is a run that can be finished, the kit is the lever and the
encounter table is a rounding error next to it.

### It also inverted my own prediction, which is the argument for the caveat

§20 predicted the Raider would be the WORST fit for the formation walls (Armored
bodies that grow HP, against a kit built on Swift and repositioning) and named THE
STALWART's adjacency-and-repair kit as the mirror. Measured: **the Raider is second
best and the Stalwart is worst.** The reasoning was plausible and wrong.

That is exactly why §20 was written as *"this corpus cannot tell those apart"*
rather than as a conclusion. A hypothesis about a matchup is cheap; the spread is
the evidence.

### And the coverage the rotation was for

```
  GRASSWAKE encounters met (was 1 of 12 across ~700 fights):
      7x The First Cut        3x The Long Drumming
      2x The Stooping Wings   2x THE RAIDER
  -> 4 of 12 distinct, in 67 fights on 3 seeds

  RIVAL LORDS MET:  2x PYROMANCER   2x THE RAIDER   2x ACOLYTE   2x STALWART
```

`The Long Drumming` is the act-1 General whose total absence started this whole
thread, and THE RAIDER now appears as a rival where it was 0 of 167 before. The
kingdom is reachable.

## 24. GENERALS ARE THE WALL, AND IT IS THE GAME — NOT A MATCHUP (2026-09-26)

Full five-hero arm: 12 seeds, 46 finished runs, 195 fights, every lord played.

### The tier table, and it is the whole answer

```
     act kind      encs  fights   win%   HP each
       1 combat      21      91  90.1%       4.3
       1 boss         5      20  85.0%       5.8
       1 elite       10      33  39.4%      22.7   <-- THE WALL
       2 combat      15      29  86.2%       4.9
       2 boss         4       4  50.0%      16.2
       2 elite        9      13  15.4%      23.8   <-- THE WALL
       3 elite        1       3  33.3%      16.3
```

**An ordinary hold costs 4.3 hero HP and is won 90% of the time. A General costs
22.7 and is LOST 60% of the time.** 5.3x the price at a quarter of the success. Act-1
bosses — which the whole session assumed were a problem — are 85% at 5.8 HP.
Ordinary combats in act 2 are 86% at 4.9. **Nothing else is broken.**

### And it survives every kit, which is what makes it a fact about the GAME

```
  lord         combat              elite               boss
  stalwart     22f  2.5hp 95%      13f 26.7hp 31%       3f 3.7hp 100%
  kindler      28f  2.6hp 93%       9f 16.8hp 44%       7f 5.0hp  86%
  raider       37f  4.0hp 92%      16f 18.6hp 44%       9f 9.2hp  89%
  pyromancer   16f  5.6hp 88%       7f 29.7hp  0%       1f 6.0hp 100%
  acolyte      19f  8.8hp 74%       4f 26.0hp 25%       4f 11.5hp 25%
```

Elite win rate across the roster: **0%, 25%, 31%, 44%, 44%.** Every lord loses
Generals, and every lord wins ordinary combats (74-95%) and act-1 bosses (86-100%).

That is the test the envelope was built for, and it is the published rule from
`reference_playtest_metrics_literature`: **a property that survives every agent is a
property of the game.** Generals being a wall is not a Raider problem, a Pyromancer
problem or a kit-coverage artifact. It is the tier.

### The per-lord spread is real but SECOND order

```
  lord          runs  fights    win%  HP/fight  med fights/run   acts reached
  kindler          5      44   81.8%       5.9        6          {2:5}
  raider          12      62   79.0%       8.5        6          {1:5, 2:6, 3:1}
  stalwart        10      38   73.7%      10.9        3          {1:8, 2:1, 3:1}
  pyromancer       9      24   62.5%      12.7        3          {1:8, 2:1}
  acolyte         10      27   59.3%      11.7        3          {1:9, 2:1}

  ENVELOPE: HP/fight 5.9 - 12.7 (2.2x)     win% 59% - 82%
```

Kindler is the only lord where EVERY finished run reaches act 2 (5 of 5). Kindler
and Raider run a median 6 fights; the other three run 3. **Acolyte pays 8.8 HP for
an ordinary hold against Stalwart's 2.5 — 3.5x on the tier a run meets most
often**, and is 25% on bosses where three lords are 86-100%.

So there are two problems and they are different sizes: **the General tier is
mispriced for everyone (first order), and Acolyte/Pyromancer are mispriced kits
(second order).** §23's interim reading, taken on 3 seeds, had the per-hero spread
as the headline — at 12 seeds the tier effect is the headline and the kit effect is
real but smaller. Recording that correction: an interim on a third of the data
ranked two findings in the wrong order.

### The drain table names the fight

```
    act kind    encounter                    n  win%   HP each   TOTAL  share
      1 elite   The Long Drumming             8  12.5%      35.1     281  15.4%
      1 elite   The First Spark               5  60.0%      25.4     127   7.0%
      1 combat  The Powderkeg Run            14  78.6%       8.0     112   6.2%
      2 elite   The Testudo                   3   0.0%      30.7      92   5.1%
      1 elite   The Threshold Choir           5  40.0%      18.0      90   4.9%
      1 elite   The Reading Room              4  50.0%      20.0      80   4.4%
      2 elite   The Unfinished Wall           2   0.0%      32.0      64   3.5%
```

**Seven of the top nine drains are Generals.** And the worst fight in the game is
`The Long Drumming` — **12.5% win, 35.1 HP each, 15.4% of every point of hero HP
spent** — which until this morning **had never been fought once**, because the
rotation did not exist and its kingdom was unreachable (§20).

That is the rotation's real payoff. It did not just widen coverage; the content it
unlocked turned out to be the single worst-balanced encounter in the game. `orc_warband`
read 0 of 6 on `_probe_encwin` earlier today and was FLAGGED RATHER THAN ACTED ON,
because that probe's fixed policy is a weak agent and its own banner warns about
reading its ceiling as a property. The evidence has now arrived from a five-hero
corpus: 8 fights, 12.5%, and the top of the drain table.

Note its passive is NOT the §18 defect class — `chieftain_rally` uses
`temp_atk_buff` (this round only, self-correcting) and is conditional on a killable
Chieftain, which is the correct shape. Its pressure is the DECK: every orc carries
Swift or Piercing, by its own authored comment.

### RUNS WON: still 0 of 46

### The next single variable

Not another encounter. **The General tier**, which is one dial rather than ten
encounters: `ELITE_HP_SCALE` and the act-aware elite scaling from §14, now that
there is finally a five-hero baseline to measure against and a tier-level number
(39.4% / 22.7 HP at act 1, 15.4% / 23.8 at act 2) to aim at. §18's
`sentinel_stone` / `forge_heat` holds stay on the list but they are ordinary
combats, and ordinary combats now measure 90% at 4.3 HP — that tier is not what is
ending runs.

## 25. THE GENERAL TIER WAS THE UNION OF TWO TIERS — AND THE BOT WON (2026-09-26)

**Two runs completed. The first wins in the entire recorded history of this
harness (0 in 236+ runs before today).** Both verified against the journal rather
than a flag:

```
  seed101 run 0  raider  act3  12 fights  28/28 HP  deck 29  gold 796  10 relics
     last fight: THE STALWART ASCENDANT  act3 boss  won  hero 28->27  foe 40->-6
  seed333 run 0  raider  act3  11 fights  24/24 HP  deck 33  gold 866  10 relics
     last fight: THE STALWART ASCENDANT  act3 boss  won  hero 24->24  foe 40-> 0
```

Both end on the act-3 finale with the hero at full HP and the foe's face at or
below zero. Checked explicitly because §10 of this document is a false VICTORY page
that was nearly reported as the bot's first win.

### THE DIAGNOSIS: FACE HP WAS THE WRONG LEVER, AND THE CODE RECOMMENDED IT

`_scale_enemy_hp`'s own header says *"HP is the fight's LENGTH, and length is what
kills here"*, and §14 turned `ELITE_HP_SCALE_BY_ACT` on that reasoning. Measured
across 12 seeds and five heroes, that premise is false for this tier:

```
  act kind      n  win%  faceHP  rounds  HPcost  HP/round
    1 combat   91   90%    11.2     6.8     4.3      0.63
    1 boss     20   85%    19.4     8.6     5.8      0.68
    1 elite    33   39%    13.9     7.2    22.7      3.15
    2 elite    13   15%    16.2     6.5    23.8      3.65
```

**A General has LESS face HP than a keep (13.9 vs 19.4) and the keep is won 85% of
the time.** Rounds are flat across every tier. The defect is a RATE — 3.15 hero HP
per round against a keep's 0.68 — and a face-HP dial cannot reach a rate. Turning it
would have been §15's mistake in a new costume.

The board traces name it exactly:

```
  round:        1     2     3     4     5     6     7     8     9
  BOSS theirs 27.4  37.4  36.9  37.8  44.7  46.9  39.9  33.2  26.1   peaks, then FALLS
       mine    1.3   5.5   9.1  11.1  12.2  16.5  20.1  18.8  19.9   climbs to 20
  ELITE theirs 1.4  16.1  18.8  28.2  37.1  41.2  40.6  41.7  40.9   climbs, never falls
        mine   0.9   5.3  10.1  10.8  11.5   9.8  10.6   8.9   4.7   flatlines at ~10
```

A keep OPENS with twenty times a General's board and is comfortably won, because
the player out-scales it and it eventually shrinks. A General opens at 1.4, puts
**+14.7 down in round 2 alone** (a plain hold puts +5.0), and is never cleared.

### THE CAUSE: A GENERAL TOOK THE BOSS'S DEPLOYMENT *AND* THE COMBAT'S ESCALATION

```gdscript
elif enc_type == "elite" or enc_type == "boss":   max_place = 2      # boss tier
var spike := surge_now or pt >= 1 or (enc_type != "boss" and round_number >= 4)
```

`_pursuit_tier()` returns 0 for anything that is not a plain combat and `surge_now`
is false at an elite, so `spike` reduced to `round_number >= 4`. **A keep is exempt;
a General was not.** From round 4:

```
  combat   max_place ~1.06, cap 3  -> ~1.06 bodies/round
  boss     max_place 2,     cap 2  ->   2   bodies/round
  elite    max_place 2,     cap 3  -> up to 3 (the escalation branch calls this
                                      function a second time in the same round)
```

**A General out-deployed a lord's keep by 50%.** And on top of that,
`ESCALATION_ELITE_BUFF_ROUND` gave every enemy body **+1 ATK every round from round
6, permanently, with no cap** — §16's shape again, but applied blanket across a
whole TIER rather than authored per encounter. A keep has no equivalent:
`ESCALATION_BOSS_STALL_ROUND` forces a PHASE, which is an authored beat.

That is not a hard fight. It is an unintended union of two tiers, and fixing it is
a bug fix rather than a tuning choice.

### THE CHANGE — one rule, two spellings of it

- `spike` reads `enc_type == "combat"` instead of `enc_type != "boss"`. One token,
  and it was the only term that ever reached an elite.
- `ESCALATION_ELITE_BUFF_MAX_STACKS = 2`, per body in a node meta (a late
  reinforcement gets its own allowance; C8 round-trips every `CreatureInstance`
  field and a fight does not survive a save), with the ceiling **ANNOUNCED** — the
  round-6 line had been firing every round, so its bare absence would read as the
  effect breaking.

### THE RESULT

```
                        BEFORE        AFTER
  RUNS WON                   0            2
  act1 / act2 / act3   30/14/2      26/14/6
  fights recorded          195          254     (+30%: runs last longer)
  fights won             73.8%        78.7%
  hero HP per fight       9.33         7.52     (-19%)
  mean deck               14.9         16.0

  tier                      BEFORE                    AFTER
  act1 combat   91f  90%  4.3hp 0.63/rd   98f  88%  4.3hp 0.66/rd   <- CONTROL
  act1 elite    33f  39% 22.7hp 3.15/rd   46f  72% 10.5hp 1.38/rd   <- TARGET
  act2 elite    13f  15% 23.8hp 3.65/rd   10f  40% 17.5hp 2.69/rd
  act1 boss     20f  85%  5.8hp 0.68/rd   31f  77%  8.7hp 1.02/rd
  act2 boss      4f  50% 16.2hp 2.17/rd   12f  50% 14.8hp 1.72/rd
  act2 combat   29f  86%  4.9hp 0.73/rd   41f  85%  6.2hp 0.92/rd
```

Composition-matched (the §21 discipline — a raw tier rate is not a
fixed-composition measurement):

```
  act1 combat (CONTROL)  88.8% -> 93.2%   HP  4.7 ->  2.7    did not degrade
  act1 elite  (TARGET)   49.3% -> 58.9%   HP 19.3 -> 12.5
```

**The matched target figure (+9.6pp win, -35% HP) is the honest one**; the raw
+33pp overstates it because the encounter mix within the tier shifted. The HP column
is the more reliable half either way (§21: continuous, accumulates per fight).

Every lord improved or held, and the envelope narrowed:

```
  lord         runs   fights    win%      HP/f    act3   deck    %new
  kindler      9->8   44->48   82->85  5.9->5.4   0->1  18->19  44->47%
  raider      14->16  62->81   79->83  8.5->6.8   1->2  17->18  43->45%
  stalwart    12->13  38->69   74->80 10.9->8.0   1->3  14->17  31->41%
  acolyte     10->12  27->34   59->68 11.7->8.4   0->0  13->13  22->24%
  pyromancer   9->8   24->22   62->64 12.7->11.9  0->0  13->12  22->18%

  ENVELOPE HP/fight  5.9-12.7  ->  5.4-11.9
```

### THE CARD SHARE, which was the owner's stated goal

```
  ALL RUNS        mean deck 14.9 -> 16.0     33% -> 37% new
  ACT-3 RUNS      mean deck 29.5 -> 27.0     66% -> 63% new   (n=2 -> n=6)
```

**A finished run is 63% new cards**, comfortably past the 40% the owner objected to,
and it is now reached six times instead of twice. The all-runs mean is still 37%
for exactly the reason the original diagnosis gave: it is a run-LENGTH statistic,
not a card-economy one. Median fights/run is still 3 — the tail moved, not the
middle.

### ONE THING I CANNOT EXPLAIN, FLAGGED RATHER THAN CHASED

Act-1 keeps read 85% -> 77%, and **composition-matched they read 83.3% -> 68.5% with
HP 6.2 -> 10.8.** My edit is provably boss-neutral: both the old
`enc_type != "boss"` and the new `enc_type == "combat"` are false at a keep, and the
ATK cap lives inside the `"elite"` match arm.

Two candidate explanations tested and REJECTED:

- **hero mix** — it did shift (stalwart 10% -> 26% of the tier), but per-lord the
  keep got harder for four of five lords, so it is not the mix;
- **arrival state** — the obvious story is "runs now fight Generals instead of
  walking past them, so they reach the keep spent". Measured the opposite: `hp_in`
  at the act-1 keep went **20.4 -> 23.0** and deck **14.2 -> 14.8**. The run arrives
  HEALTHIER.

At n=20 vs 31 the binomial 1sd is 8.0pp, so a 15pp move is 1.9sd — and §21 measured
untouched content in this harness swinging up to **100pp** between arms at these
sample sizes. The responsible reading is that this is inside the demonstrated noise.
**Recorded as an open question, not acted on**, because acting on a 1.9sd move in a
tier the change provably cannot reach is precisely the over-reading §21 exists to
prevent. If it survives the next arm at larger n, it is real.

### WHAT IS STILL THE WORST FIGHT

```
  act1 elite  The Long Drumming     5f  20%  30.4hp   8.0% of all hero HP
  act1 combat The Powderkeg Run    17f  71%   8.6hp   7.7%
  act2 boss   THE STALWART          5f  20%  25.6hp   6.7%
  act1 boss   THE STALWART          4f  25%  26.5hp   5.5%
```

`The Long Drumming` is still the top drain at 20% win and 30.4 HP — and it is NOT
this defect class: `chieftain_rally` uses `temp_atk_buff` (this round only,
self-correcting) and is conditional on a killable Chieftain, which is the correct
shape. Its pressure is its DECK, by its own authored comment: every orc carries
Swift or Piercing. That is the next thing to look at, and it is an authoring
question rather than a dial.

## 26. THE REFILL RATE WAS THE WHOLE THING (2026-09-26)

`ELITE_ARRIVALS_PER_ROUND = 1`. One constant, and it is the largest measured
improvement of the entire session.

```
                        BEFORE        AFTER
  RUNS WON                   1            2
  median fights/run          3            5
  fights won             76.3%        82.6%
  HP per fight            8.81         5.68     (-36%)
  mean deck               15.2         17.9
  runs finished             57           36      (fewer, because each lasts longer)
  act1/2/3             36/18/3      17/15/4      (act2+ reach 37% -> 53%)
```

Per tier:

```
  tier                      BEFORE                    AFTER
  act1 combat  123f  87%  5.3hp 6.6rd    96f  92%  3.6hp 6.4rd   <- CONTROL
  act1 elite    44f  50% 16.4hp 7.2rd    36f  86%  5.7hp 7.3rd   <- TARGET
  act2 elite    14f  57% 15.7hp 6.5rd    17f  76%  8.2hp 7.7rd
  act1 boss     27f  89%  9.7hp 9.3rd    32f  75%  6.6hp 8.7rd
  act2 boss      9f  33% 13.0hp 7.9rd     7f  57% 14.0hp 9.1rd
  act3 boss            (not reached)       4f 100%  2.0hp 7.5rd
```

**An act-1 General now costs 5.7 hero HP against 16.4, and is won 86% against 50%.**
Composition-matched over the 7 encounters present in both arms: **60.8% -> 89.0% win,
14.5 -> 4.0 HP.** That is a far larger move than the noise band this harness
demonstrated (§21, §25), and unlike §25 it is corroborated on every derived measure.

### The diagnosis it confirms

§25's deck nerfs did every mechanical thing intended and did not move the outcome,
because they were aimed at the wrong quantity. The traces named the right one: the
hold deployed ~2 bodies a round, the player cleared ~2 a round, so the enemy board
held at 32-44 indefinitely — and `_clash_lane_pass` only reaches the face through a
column with BOTH enemy rows empty. **The win condition was unreachable while the
drip kept pace.** It was not a hard fight, it was a stalemate the hero lost on the
clock.

This is the §3c asymmetry at its sharpest: the player pays Command per body and the
hold pays nothing, so "the same arrivals per round" is not a fair race.

The two grasswake Generals, which §25 could not move at all:

```
  The Long Drumming      BEFORE  12f   8% win  32.2hp  faceLeft 9.8
                         AFTER    7f  57% win  17.3hp  faceLeft 1.4
  The Horse-Lords' Toll  BEFORE   3f   0% win  25.7hp  faceLeft 8.7
                         AFTER    2f 100% win   2.0hp  faceLeft -1.0
```

`faceLeft` is the column that proves the mechanism: the player now finishes the foe
(1.4 and -1.0) where before it left 9-10 of a 14 HP face standing. Small n on both,
but the direction, the HP and the face damage all agree, and the tier agrees with
them.

### THE CONTROL MOVED, AND THE CAUSE IS MEASURED RATHER THAN ASSUMED

```
  act1 combat, composition-matched:  93.3% -> 95.8%   HP 3.6 -> 3.0
```

`ELITE_ARRIVALS_PER_ROUND` is only read when `enc_type == "elite"`, so a plain hold
cannot have changed. The cause is the feedback path §21 named:

```
  the state act-1 combats are met in:
    BEFORE  n=123  deck 10.8  relics 2.7
    AFTER   n= 96  deck 11.6  relics 3.0
```

Runs that survive a General go on to fight MORE act-1 combats with a bigger deck and
more relics, so the act-1 combat population shifts toward later, better-equipped
fights. That is a consequence of the change rather than a contamination of it — but
it is exactly why a raw tier rate must never be read as a fixed-composition
measurement here.

### Every lord improved, and the worst kit improved most

```
  lord         BEFORE win%/HP      AFTER win%/HP
  acolyte        59% / 13.9          81% /  7.9
  kindler        86% /  7.4          84% /  2.7
  pyromancer     67% / 10.2          69% /  6.0
  raider         80% /  8.0          87% /  4.6
  stalwart       80% /  7.6          83% /  6.2
```

Acolyte — the worst lord in every previous arm — gains 22 points and nearly halves
its HP bill. The HP envelope narrows from 7.4-13.9 to 2.7-7.9. **A fix that helps
the weakest kit most is the right shape**: it raises the floor rather than the
ceiling.

### Both victories verified, and act 3 has TWO boss fights

```
  seed222 run2 acolyte  THE PYROMANCER 34->-7  then  THE KINDLER ASCENDANT 40->-7  hero 24->16
  seed707 run0 raider   THE KINDLER    30->-4  then  THE ACOLYTE ASCENDANT 40->-9  hero 28->28
```

`act3 boss` reads 4 fights at 100% against 2 run victories, which looked like a
defect and is not: act 3 holds the rival lord's keep AND the ascendant finale. Two
runs x two fights. Checked because §10 of this document is a false VICTORY page.

### WHAT IS STILL OPEN

- **act-1 keeps drifted down again** (89% -> 75% raw, 93.7% -> 81.2% matched) while
  their HP cost FELL (9.7 -> 6.6, matched 8.1 -> 5.8). Win rate down and cost down
  together is the signature of composition, not difficulty — more runs now reach
  more keeps with more lords. Third arm running in this direction; still under the
  ~1.5sd band untouched tiers move by, and still not acted on.
- **act-3 elite is now the worst tier in the game**: 3f, 33% win, 19.0 HP. It is
  `THE BURIED ARMY` (a boss kit dealt at elite band, the documented elite-pool
  shortfall). n=3.
- **`ELITE_ARRIVALS_PER_ROUND = 1` makes a General's drip equal a plain hold's
  (~1.06).** What still separates them is the authored lineup, the passive, the
  reinforcement pool and a full opening formation — and at 86%/5.7hp against a
  hold's 92%/3.6hp that separation now looks THIN. If Generals should feel harder
  than this, the dial to try is 2 from a later round rather than a flat 2, which is
  the shape `hold_arrivals_for_round` already uses for the plain tier.

## 27. CLOSING THE ACT-1 KEEP "DRIFT" — IT WAS NOISE, AND POOLING PROVED IT (2026-09-26)

§25 and §26 both flagged act-1 keeps moving against changes that provably could not
reach them, and both declined to act. With four 5-hero arms on disk the question is
finally answerable, because the arms pool:

```
  arm                 n   win%     HP  hp_in   deck   lords at the keep
  5hero baseline     20    85%    5.8   20.4   14.2   raid7 kind6 acol4 stal2 pyro1
  general nerf       31    77%    8.7   23.0   14.8   raid11 stal8 kind6 acol3 pyro3
  grasswake decks    27    89%    9.7   23.7   14.8   raid10 stal7 kind6 pyro3 acol1
  elite arrivals=1   32    75%    6.6   22.2   15.6   raid11 stal8 acol6 pyro5 kind2
```

**85 -> 77 -> 89 -> 75.** It OSCILLATES; it does not drift. One sigma on a win rate
at n=30, p=0.82 is 7.0pp, so a 14pp total range across four samples is precisely
what a single population produces — a 4-sample range of ~2 sigma is the expectation,
not a signal.

**The tell was there all along and is worth naming as a rule: win rate and HP cost
moved in the SAME direction in two of the four arms** (77%/8.7 then 89%/9.7 — worse
win with worse cost, then better win with worse cost). A real difficulty change moves
them in OPPOSITE directions: harder means fewer wins AND a bigger bill. Movements
that are not anti-correlated are composition or sampling, not difficulty.

So: closed, no change made, and the three flags in §21/§25/§26 were correct to
report it and correct not to tune against it. **The cost of having chased it would
have been a dial turned against a random number, in a tier that was already the
healthiest boss band in the game.**

The lord mix also shifts substantially between arms (kindler 6 of 20 down to 2 of 32;
acolyte 4 -> 3 -> 1 -> 6) purely because deeper runs redistribute who reaches a keep.
At these sample sizes **the hero mix is itself composition**, which is a second
reason a per-tier rate is not a fixed-composition measurement here.

## 28. THE LATE RAMP: BUILT, MEASURED, REVERTED (2026-09-26)

§26 closed on a named tension: at `ELITE_ARRIVALS_PER_ROUND = 1` a General's refill
rate EQUALS a plain hold's, so the only things separating the tiers are the authored
lineup, the passive, the reinforcement pool and a full opening formation — 86%/5.7hp
against a hold's 92%/3.6hp. It also named the dial to try: **2 from a later round**,
the shape `hold_arrivals_for_round` already uses, rather than a return to a flat 2.

Built as `elite_arrivals_for_round(r, ramp_round)` — static and pure like
`command_for_round`, with the ramp round set to `ESCALATION_ELITE_BUFF_ROUND` (6) on
purpose so the General's commitment would be ONE legible beat (it already announces
"presses the attack" there) instead of two ramps a player could only infer. Curve
verified before spending the arm, Ascension A1 included:

```
  round          : 1 2 3 4 5 6 7 8 9 10 11 12
  GENERAL wants  : 1 1 1 1 1 2 2 2 2  2  2  2
  A1 (one early) : 1 1 1 1 2 2 2 2 2  2  2  2
```

### It was worse on every axis

```
                      flat 1    ramp 1->2@r6
  RUNS WON                 2            0
  median fights/run        5            4
  HP per fight          5.68         7.76   (+37%)
  fights won           82.6%        76.0%
  mean deck             17.9         16.9

  act1 elite      36f 86%  5.7hp  ->  54f 70% 10.9hp    (2.8 sigma)
  act2 elite      17f 76%  8.2hp  ->  14f 36% 14.7hp
  act3 boss        4f 100% 2.0hp  ->   never reached
  act1 combat     96f 92%  3.6hp  -> 107f 86%  5.0hp    <- control, -6pp (~1.5 sigma)
```

The control drifted 6pp, so discount for a generally worse arm — and act-1 Generals
still moved 2.8 sigma with their HP bill nearly DOUBLED, act-2 Generals collapsed,
and every run-level measure agrees in the same direction. The regression survives the
discount.

### WHY, AND IT IS THE FIGHT'S OWN LENGTH

**An act-1 General runs 7.2 rounds.** Round 6 is therefore not "late" — it is the
round the fight is DECIDED on. The player has finally assembled a board (§26's trace
shows the player's board climbing from round 5 onward) and is a clash away from
breaking through; doubling arrivals exactly there restores the stalemate that a flat 2
produced from the opening, at the one moment it costs everything.

And there is no round that escapes this. Later than ~8 and the ramp never fires in a
7.2-round fight, which is flat 1 with extra machinery. **The window between "late
enough not to decide the fight" and "early enough to happen at all" is empty.**

### The rule that falls out

**A General's tier separation cannot come from its refill rate at any reachable
round.** The player's win condition needs a column with both enemy rows empty, so
arrivals do not make the fight harder — past the player's clear rate they make it
UNWINNABLE, and the crossover is sharp rather than gradual. If Generals should feel
harder than 86%/5.7hp, the levers are the ones that do not touch board occupancy: the
authored lineup, the passive, the face, the opening formation's size.

Reverted to flat 1. **The revert restores a build that was already measured** — the
`_elite_arrivals` arm IS the measurement of the current state (2 runs won, median 5
fights, 5.68 HP/fight), so no confirming sweep is owed. Rejected arm kept at
`_REJECTED_elite_ramp_r6`, and the constant's own comment block now records the
negative so the dial is not re-tried.
