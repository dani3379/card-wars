# Handoff — the pilot, BoardEval, and "make the bot play the whole game"

**Date:** 2026-09-15. Self-contained; everything below was verified in-session
unless explicitly marked otherwise.

## THE GOAL (owner, stated at the end of the session)

> "ideally i want to be able to run the entire game with this bot cuz i think it
> was too difficult"

So the bot is wanted as **two things at once**: an input-pipeline bug finder
(what it was built as) and a **difficulty instrument** (can a competent player
actually finish a run?). Read the "Is the game too hard?" section before drawing
any conclusion from it — as of today it cannot answer that question yet, and the
reason is specific.

---

## 1. WHAT WAS WRONG, AND WHAT WAS FIXED

### P0 — the pilot was declining every reward in the game

`deck at death [11, 11]` over 16 runs. **A hero opens on ELEVEN cards**, so the
pilot had never accepted a single one. It played every run on its starting deck,
which is why every long soak reported `acts seen [1]`.

The direct cause was `"SKIP"` sitting in the pilot's `ADVANCE` vocabulary at
score 100 (Recruit's only Button is `make_back_button("Skip")`). **A longer word
list was the wrong fix** — every offer screen was losing to a *differently
worded* advance:

| screen | the button that was winning |
|---|---|
| Recruit | `"Skip"` |
| Reward | `"Continue"` |
| Treasure | `"Take 3 Gold instead"` — contains ADVANCE's own `TAKE` |
| Shop | `"Leave the Wagon"` |
| Wayside | `"Continue"` |
| Event | `"WALK ON —"` — matched **nothing**, won on tree order (added last) |

Half are built with anonymous lambdas, so there is no handler to key on. What
they share is the SCREEN. Fix: `OFFER_SCREENS` + a bounded `OFFER_PATIENCE` (6
ticks), during which ADVANCE drops below every real offer, then returns so the
pilot always leaves. `DECLINE` is tested **before** `ADVANCE` (Treasure), and is
symmetric — last while something is takeable, the way out once nothing is.

### Three offers no score could ever reach

1. **A Recruit tile is not a Button.** It is a `Card2D` with `gui_input`
   connected to `_on_recruit_card_input`, invisible to `_all_buttons`. Found by
   HANDLER now (`_wired_controls`), the same idiom as `_map_button_for`.
2. **A descendant hit is not always a hit.** A press on a *Button's* child still
   fires its `pressed` (the event walks up); a press on a child of a
   `gui_input`-wired control does NOT — the child consumes it. Verified with a
   hit-map: the `y=0.70` band of a recruit writ is a child. Fixed with
   `_aim(..., exact)` + `_aim_exact`. **And `_click_control` returning true is
   not the oracle** — `_drive_recruit` counts the DECK.
3. **Rest's three banners are identical unworded click-catchers**
   (`make_choice_banner` puts the words in a SIBLING subtree), so the pilot took
   whichever was last in tree order. `_catcher_label` reads the parent — **for
   identification only**, never for scoring.

### P1 — combat competence

Curve-out (evaluator-driven, below), threat-aware placement, and **the first test
in this harness that drinks a potion** (nothing had ever pressed a bottle on a
live board — the belt's known `usable_in` trap lives exactly there).

### Five bugs found by actually running it — four in the pilot

1. `_find_grab` engine-verifies a grab point and `_play_creature` **threw it
   away**, re-deriving from `_grab_point`, which consults nothing. In a full fan
   that lands under the next card, so the press grabbed the neighbour and the
   intended card was reported as `SILENT_REFUSAL` against a game that correctly
   said nothing. Fix carries the **local fraction** (the hover-lift makes a
   screen point stale).
2. **A control inside a `ScrollContainer` is SCROLLED, not off-canvas.** Reward's
   forge row puts a card at x=1644 on a 1600 canvas. `_probe_boundary_ui` has
   carried that exemption since C12; the pilot did not. It now turns the WHEEL.
3. **`_drive_map` never answered modals.** `MapView._ready` opens an option
   picker for any of three relics (Articles of War / Totem Pole / Bone Hourglass)
   on **CanvasLayer 1000**; the pilot logged 24 "covered by modal" blocks and
   reported `STUCK`. Surfaced the first time a drafted relic paid out.
4. **A picker is modal and neither mechanism could see it** — the fourth spelling
   of "a modal is not a layer number". `_capture_present` must EXCLUDE
   `current_scene` (every scene root is a full-rect STOP Control), and **Event's
   picker blocks via the Event ROOT**. Meanwhile a picker tile is a transparent
   catcher over a card, so it reads UNWORDED (20) and loses to the choice buttons
   underneath (50) — *the pilot preferred a button it could not reach over the
   only ones it could*. Recognised by handler now (`PICKER_METHODS`, seven across
   Event/Rest/Reward/Wayside/Shop), answered before anything else on the tick.
5. **`_modal_button` asked the wrong question** (fixed last, see §4 — this is the
   one that is NOT yet verified in a long windowed run).

---

## 2. `scripts/combat/BoardEval.gd` — ONE SCORER, TWO SIDES

Owner asked for this directly ("calculate every single possible play and assign
it a number value"), chose the **shared file WITH SkirmishBot re-pointed at it**,
and said it "needs serious retuning".

`SkirmishBot` (practice opponent) and `tools/_probe_pilot.gd` (input pilot) ask
the same question from opposite sides of the board. **`mine_is_enemy` is a
PARAMETER**, not an assumption baked into a copy — two implementations of one
judgement is the pathology this repo already paid for once (`NetPlayerState`
restating relic magnitudes as literals instead of reading RelicDB).

### The four defects the move exposed (rules, not weights)

1. **NO CONCEPT OF LETHAL** — `damage_face` scored `value * 1.0`, identically at
   30 foe HP and at 3, so the bot could hold exact lethal and play a 2/2.
2. **OVERKILL WAS FREE** — a 6-damage spell scored the same on a 2/1 as on a 2/6.
3. **IT PREDATED THE MUSTER DELAY** (2026-07-21) — credited `atk * 0.8` of
   "unblocked pressure" and `+2.0` for "we can kill it" to a body that does not
   swing in the clash ending the round it arrived in.
4. **`score -= 2.0  # back row: no immediate combat`** — not this game. BOTH rows
   strike every round; the flat penalty punished exactly the play the back row is
   for.

Weights were also unitless across branches (1.0/0.6/1.2/1.3/0.9/0.6) — orderable
*within* a branch, meaningless *between*. **One currency now:** ATK is the unit,
HP 0.75 (it only defends), card 2.0, Command 2.0, face 1.6 (the only resource
that wins).

### Three contracts that matter

- **`known` is returned, not folded into the score.** The bot HOLDS a spell it
  cannot evaluate; the pilot CASTS it anyway (an unscored spell is an unexercised
  resolver — 52 effect types vs the dozen modelled). Same scorer, opposite
  correct answers.
- **`occ_override`** — `decide_turn` picks several plays in one pass and returns
  INTENTS; nothing is applied yet, so a live occupancy read puts every creature
  the bot plays into the same lane.
- **It names NO autoload.** It is `preload`ed by a `--script` probe, where a bare
  `CardDB` is a hard compile error while parsecheck stays green. Everything
  arrives as an argument — which is also what lets its gate run on stubs with no
  Combat scene.

### Exploration is deliberate

The pilot takes the best play **75%** of the time (`PILOT_GREED`) and otherwise
samples the top 3 weighted. A pure argmax plays one line forever and would delete
the coverage the pilot exists for (the `_probe_runaway` C24 insight). `--greedy`
disables exploration for comparison.

---

## 3. VERIFICATION STATE

**Passing:**
- `tools/_probe_board_eval.gd` — **18/18**, one check per claim above, runs on
  stubs in ~1s.
- `run_safe_probes.ps1` — parsecheck (114 scripts) / copy_lint / event_art /
  tutorial, **ALL PASS**. Needs `-GodotPath "D:\games\Godot_v4.6.2-stable_win64.exe"`.
- `_probe_bot_spells.gd` — ALL PASS. `_probe_net_soak.gd` — ALL PASS.
- Pilot **`command unspent` 0.40 → 0.00** per turn (the curve-out is exact).
- Windowed 660s pre-evaluator: **no findings, no game-side script errors**,
  `offers taken 9`, `deck at death [15, 12]` (was a flat `[11, 11]`).

**A NEGATIVE RESULT WORTH KEEPING:** A/B-ing the scorer through `_probe_net_soak`
was **inconclusive** — both versions end a game at 4-5 HP, because that soak's
driver holds a drafted `NET_RELIC_POOL` arsenal (+2 Command, +2 cards) against
the bot's flat 3 Command and board-only `BOT_RELIC_POOL`. **It measures the relic
gap, not play quality.** Do not reach for it to evaluate bot strength.

---

## 4. THE OPEN ITEM — DO THIS FIRST

**`_modal_button` was rewritten at the very end of the session and has only had a
90-second headless smoke test.** It compiles and reports no findings, but the bug
it fixes is **windowed-only**. Re-run and confirm the stall is gone:

```bash
powershell -File "D:\Godot\tools\run_pilot.ps1" -Windowed -Seconds 660 -MaxNodes 300 -Seed 771
```

**The bug:** `_modal_button` took the **global** highest-paint-key button and then
tested whether *that* button was modal. THE INITIATIVE's scrim is `z_index = 200`
on the **HUD layer (12)** — deliberately, since a plain child of Combat draws
beneath the HUD — while **the hand sits on layer 20**. Any hand-layer button
outranked it, so the test was applied to the wrong button and the modal became
invisible. Symptom: `TURN_TIMEOUT` at `{"round": 0, "phase": 0, "captured": true,
"unanswered_modal": "none"}` — **5 occurrences × 60s = ~300s of a 660s budget**.
Only at a General or a keep (the only fights with an initiative), and only
windowed (headless auto-picks the first option).

Fix: rank ALL candidates by paint order, return the top one that actually
QUALIFIES as modal. **Success = `TURN_TIMEOUT` absent and `cards played` back
above ~110 per 660s** (it was 120 before, 57 during the stall).

---

## 5. "IS THE GAME TOO HARD?" — NOT ANSWERABLE YET, AND WHY

`acts seen` is **still `[1]`** in every run. The pilot reaches ~2-3 fights and
dies in act 1. **Do not read that as a balance finding yet.** Three reasons:

1. Until today the scorer had **four outright defects** (§2). Nothing has yet
   measured the fixed version over a full run.
2. The pilot only started **taking rewards at all** today — every prior data
   point was a starting deck.
3. `command unspent` is **0.00/turn**, so resource waste is already ruled out;
   whatever is losing fights is card choice, targeting, or blocking — or genuine
   difficulty. Those are not yet separable.

There is also a standing house rule: `reference_autorun_cannot_measure_decks` —
`_probe_autorun` has sat near 34% win rate for months, and a mediocre bot losing
says nothing about a human.

### To actually answer it, in order

1. **Confirm §4**, then run 3× 660s windowed and record `acts seen`,
   `deck at death`, `runs ended`, `fights entered`.
2. **Add `--act=N`** to decouple coverage from play quality. Verified feasible:
   `start_new_run` generates **all three act maps** into `map_data` up front, and
   `RunState.advance_act()` (line ~1943) is already a clean per-act reset. ~15
   lines, deterministic. This gets acts 2-3 *screens* covered immediately — note
   it gives an act-3 map with an act-1 deck, which is NOT a real act-3 state, so
   it complements rather than replaces a surviving bot.
3. **Only then** treat repeated act-1 deaths as a difficulty signal, and measure
   it as a WIN RATE over N seeded runs with `--greedy` (no exploration noise).

### Remaining levers on bot strength, roughly by value

- **Blocking/trading quality** — `score_creature` values a block as
  `min(foe_atk, my_hp) * PT_HP`; it does not yet reason about OVERKILL carrying
  through to the body behind (universal since 2026-07-28), nor about which lane
  the enemy will actually attack.
- **Relics and potions are unmodelled.** The pilot drinks only under 40% HP and
  the scorer ignores relic effects entirely.
- **The 40 unmodelled spell types** (`known: false`) — the pilot casts them at a
  flat `UNKNOWN_SPELL_SCORE = 2.0`, which is fine for coverage and bad for play.
- **`SKIRMISH` is still DENY-listed** — the whole multiplayer shell (lobby,
  deckbuilder, arsenal stage) has never had a synthetic click on it.

---

## 6. TRAPS ALREADY PAID FOR — DO NOT RE-LEARN

- `Input.parse_input_event` is a **no-op headless**. Only
  `get_tree().root.push_input(ev, true)` works; coords must be canvas-local (the
  headless window boots 64×64 and rejects resize).
- **`change_scene_to_file` is INERT under `--script`** — it returns OK and leaves
  `current_scene` null. A driver must not BE `current_scene`; hand the work to a
  node parented to root, **deferred**.
- This project treats **"variable type inferred from a Variant value" as a build
  error**. Use explicit `: Variant`, never `:=`, on anything returning Variant.
- **Suspect the oracle first.** Every soak finding this session that looked like
  a game bug was the pilot's. The `_probe_board_eval` back-row test also failed
  first because *the test* was wrong (empty enemy board — nothing to shelter
  from, so an open front lane genuinely IS better).
- `run_safe_probes.ps1` / `run_pilot.ps1` need
  `-GodotPath "D:\games\Godot_v4.6.2-stable_win64.exe"` (not on PATH).

---

## 7. FILES TOUCHED

| file | state |
|---|---|
| `scripts/combat/BoardEval.gd` | **NEW** (production) |
| `scripts/net/SkirmishBot.gd` | modified — re-pointed; 6 orphaned helpers deleted (327 → 222 lines) |
| `tools/_probe_pilot.gd` | heavily modified (untracked, as it already was) |
| `tools/_probe_board_eval.gd` | **NEW** (gate) |
| `CLAUDE.md` | pilot section + new BoardEval section |
| memory | `project_input_pilot_20260915`, `project_board_eval_20260915` (new), `MEMORY.md` |

**Nothing is committed.** `git status` will show `CLAUDE.md` and
`scripts/net/SkirmishBot.gd` modified, plus the two new files.
