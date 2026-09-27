# Is the game too hard? — what the pilot measured, 2026-09-15

**Short answer: the bot cannot win, it is NOT losing to unfair damage, and the
losses have one shape — a fight that does not end by about round 5 is already
lost and takes another nine rounds to say so.**

This is the first time the question has been answerable. The instrument is new:
`tools/_probe_pilot.gd` now samples the hero's HP every frame of every fight and
attributes each drop to the beat that caused it, using only state the game already
exposes (`player_hp`, `phase`, `_phase_caption`, the live board arrays). No hooks,
no edits to `Combat.gd`.

```bash
"/d/games/Godot_v4.6.2-stable_win64.exe" --headless --path "D:\Godot" res://tools/_probe_pilot.tscn -- --max-sec=1150 --max-nodes=400 --seed=606
```

## The measurements

Two clean headless runs, seeds 909 and 606, **26 fights, 7 complete runs**:

| | seed 909 | seed 606 |
|---|---|---|
| fights won | 8/12 (67%) | 9/14 (64%) |
| rounds per fight | 6.9 | 7.7 |
| hero damage taken | 122 | 190 |
| …while RESOLVING (the clash) | 78% | 83% |
| …on the player's own turn | 22% | 17% |
| …**behind a FULL front line** | **7%** | **4%** |
| Command left unspent per turn | 0.02 | 0.07 |
| acts reached | 1–2 | 1–2 |

### 1. The difficulty is NOT uncounterable damage

**Only 4–7% of all damage landed while the player had a full front line.** The
other 93–96% arrived through lanes the bot left open. Whatever is killing it, it
is not the class `docs/COMBAT_SHAPE_PASS_20260727.md` was written about. At acts
1–2 the board is answerable; the bot simply fails to answer it.

Resource use is also ruled out: **Command unspent is 0.02–0.07 per turn** over 189
commits. The turn is being spent essentially perfectly.

### 2. The losses have exactly one shape: long fights

This is the finding. Across both runs, without exception:

- **Fights it WON ran ~4 rounds.**
- **Every fight it LOST ran 9–14 rounds.**

A fight that goes long is not a close fight — it is a lost one that has not
finished. On the losing fights it had removed **52% of the foe on average**, and
had spent 9–14 rounds doing it.

```
act 2  The Powderkeg Run         35% removed (11/17 HP left),  9 rounds
act 2  The Bleeding-Heart Cell   50% removed ( 8/16 HP left), 13 rounds
act 1  THE ACOLYTE               11% removed (16/18 HP left), 14 rounds
act 1  The Field That Watches…   80% removed ( 2/10 HP left), 14 rounds
act 1  The Unfinished Wall       82% removed ( 3/17 HP left),  9 rounds
```

Two of those are near-misses (80%, 82%) — ordinary tuning. Two are not:
**The Powderkeg Run took 57 hero HP in a single 9-round fight** (more than a full
hero bar) while giving up only a third of itself, and **THE ACOLYTE survived 14
rounds having lost 11% of its HP.** Those two are not close fights; they are
fights the bot could never have won, and it spent a third of its run finding out.

### 3. Where the damage actually comes from

Per-beat, seed 606 (190 HP total):

```
SWIFT STRIKES     69  (36%)
BACK ROW ATTACKS  56  (29%)
FRONT ROW ATTACKS 41  (22%)
ENEMY REINFORCES  15  ( 8%)
ENEMY DEPLOYMENT   6  ( 3%)
THE FALLEN         3  ( 2%)
```

**Swift is the single largest source of damage to the hero**, ahead of the entire
front-row clash.

**Two separate claims here, and only the first is measured — do not merge them:**

1. **MEASURED.** 69 HP landed *during the Swift pre-phase*, i.e. Swift creatures
   striking the hero's face directly in lanes that had no blocker at pre-phase
   time. That is 36% of all damage taken, from one keyword.
2. **STRUCTURAL, NOT MEASURED.** Separately, the Swift phase sweeps its dead
   before the main clash, and the main clash reads **live** occupancy (that was
   deliberate — see the blocker-economy pass of 2026-07-28, where a stale snapshot
   let a dead blocker go on denying a column). So a Swift attacker that kills a
   blocker also **empties that lane for every other attacker in it that round**.
   That damage is attributed to FRONT/BACK ROW ATTACKS, not to Swift, so the 69
   above does **not** include it and the effect's real size is unknown. Measuring
   it needs a per-lane before/after, which this ledger does not yet do.

## THE MEASUREMENT THAT SETTLES IT (2026-09-16, clean tree, seed 606)

Earlier I *inferred* "decided by round 5" from fight length. It is now measured
directly: each round, board strength (ATK+HP over standing bodies) is sampled for
both sides, and for every lost fight the report prints **the last round the pilot
was still ahead**.

```
POINT OF NO RETURN — last round the pilot was ahead on board:
  mean: ahead until round 1.4, fight ran 10.4 rounds  (87% of the fight already lost)
    The First Spark            ahead to r1 of 9
    THE ACOLYTE                ahead to r0 of 7
    The Pyre Cult              ahead to r5 of 15
    THE STALWART               ahead to r0 of 8
    The Field That Watches Bac ahead to r1 of 13
```

**Round 1 is the muster round — both lines deploy and neither swings.** So
"ahead until round 1.4" means the board is lost *on the first exchange*, and in
two of five fights the pilot was **never ahead at all**. Then the game takes
another eight to thirteen rounds to say so.

This relocates the problem. It is not attrition, not card choice mid-fight, and
not wasted resource (`command unspent 0.00` over 107 commits). **The fight is
decided by the opening deal, and everything after is a formality.**

Outcomes are bimodal, with nothing in between: fights it wins take ~4 rounds
(The Spore-Cathedral: 2 wins, 4.5 rounds); fights it loses take ~10.

**Still bot-limited, and the number that proves it:** `recruits 2` across 5 runs.
The pilot buys from shops (8 purchases) but almost never takes a drafted card, so
`deck at death` was `[14, 11, 12, 10, 11]` — one run *finished smaller than the
11-card opener*. Deck quality is therefore still a pilot artifact, and the
opening-deal finding should be re-confirmed once recruit-taking works.

## Candidate toxic mechanics (leads, ranked — each needs confirming)

1. **No catch-up, and no concession.** The enemy's reinforcement is an *infinite*
   backup creature (`EncounterDB.get_reinforcement`) and escalates at
   `ESCALATION_REINFORCE_ROUND`; the player's deck only gets more tired. Once
   behind, there is no mechanism that can turn a fight around — yet the fight
   continues for another 5–10 rounds. **The outcome is decided around round 5 and
   the game does not admit it until round 14.** This is the least fun shape a
   difficulty problem can take: slow, unclear, and unrecoverable.
2. **Swift double-dips** (above). Suspect it is over-costed in the player's favour
   and over-delivered in the enemy's.
3. **Specific outliers, not curve problems:** `The Powderkeg Run` (act 2) and
   `THE ACOLYTE` (act 1 rival) are far outside the distribution of every other
   encounter measured. Look at these two before touching any global dial.

## What this does NOT license you to conclude

- **Acts 2–3 are barely measured and act 3 not at all** (`acts seen [1, 2]`).
  Nothing here says anything about the late game, the rival lords beyond the two
  seen, or any set-piece.
- **A mediocre bot losing is not proof a human loses** — the standing house rule
  (`reference_autorun_cannot_measure_decks`). The bot's remaining known weaknesses
  are listed in `docs/PILOT_HANDOFF_20260915.md` §5: blocking/trading quality
  ignores overkill carry-through, relics are unmodelled by the scorer, and 40
  spell types score a flat `UNKNOWN_SPELL_SCORE = 2.0`.
- The per-beat split uses `_phase_caption`, which is a **label**, not a
  transaction log; the reliable split is the `phase` enum (RESOLVING vs
  PLAYER_TURN). Treat the beat table as a strong hint, not an audit. **The first
  version of this classified by caption alone and reported `0%` clash damage
  across 8 fights** — a broken oracle, not a result, because the caption is
  cleared before the hero's damage number resolves.

## The cheapest next steps, in order

1. **Make the bot close fights faster** rather than survive longer — `BoardEval`
   already scores lethal, but nothing values *tempo* (killing the blocker that
   is stalling a lane). If win rate rises and the long-fight pattern stays, the
   mechanic is confirmed rather than a bot artifact.
2. **`--act=N`** (≈15 lines, noted feasible in the handoff: `start_new_run`
   already generates all three act maps and `RunState.advance_act()` is a clean
   per-act reset) to get acts 2–3 *screens* covered without needing a bot that
   survives.
3. Re-run this document's two seeds after any balance change; the table above is
   the baseline.
