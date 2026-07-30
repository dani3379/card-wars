# Set-Piece Holds — the named actions of the war (2026-07-20)

**Status: BUILT and gated.** Three scenarios ship, one per act. Verify with
`tools/_probe_setpiece.gd` (data + map placement) and
`tools/_probe_setpiece_fight.gd` (boots the real combat scene per scenario).

---

## 1. What this is

A **set-piece** is an authored scenario fought on the ordinary combat engine:

- an **opening board** someone placed on purpose, on both sides,
- exactly **ONE twisted rule** (the *ground*),
- an **objective that is not "kill the face"**, carrying a **deadline**.

The model is Thronebreaker's puzzle battles — the single most-praised element
of a 30-hour game built on one combat system, described by reviewers as
solving chess problems. The house translation is **"your deck + one twisted
rule + a clock."** A handed deck is deliberately *not* used: bypassing the
build is the standard complaint about the form, and the whole point of a
roguelike deckbuilder is that the deck you made is the tool you brought.

## 2. Why this, and not another mechanic

This was chosen against the project's own standing rulings, most of which
forbid the obvious alternatives:

- `combat-feels-samey` rules the complaint is a **presentation / legibility /
  stakes** problem and says explicitly *do not enumerate mechanics*. A
  set-piece attacks samey through **stakes** — the sanctioned lever.
- The **2026-07-20 positioning audit** killed four consecutive rounds of
  positional-mechanic pitches, and recorded the real diagnosis: normal holds
  are **under-constrained**. The player can usually afford to answer
  everything (83.7% of measured snapshots), so there is nothing to triage and
  placement collapses to "plug the hole in front of the biggest threat" (74%).
- That audit also retired its own under-constraint *theory* as unproven for
  normal fights — correctly, since those snowball in 2-3 rounds by design.

A set-piece threads that needle. It is **over-constrained by construction**
(authored board, closed ground, a clock), so it delivers the Into-the-Breach
cold-reading pressure **in a container that cannot leak into the main curve**.
Nothing about ordinary holds changes. No new combat mechanic is added to the
general game. The scarcity lives in an opt-in room.

It is also the cheapest large win available: `EncounterDB` already proved
data-driven lineups, `MutatorDB` proved per-fight rules, `wayside_id` proved
"a node type carrying a bespoke verb", and the event pool has already shipped
15+ bespoke set-pieces (the minigames). Every muscle this needs is trained.

## 3. Architecture — the one decision that mattered

**A set-piece is not a new map node type. It is a `combat` node wearing a
`setpiece_id`.** Same precedent as `wayside_id` and `mutator_id`.

That single choice means node routing, save/load, the medallion pipeline,
music selection, gold rewards, the conquest tally (`holds_broken_in_act`),
and the victory scene handoff all keep working with **zero** changes. It is
also right in the fiction: a named action *is* a hold — it just happens to be
one people wrote down afterwards.

| Layer | File | What it owns |
|---|---|---|
| Data | `scripts/data/SetPieceDB.gd` | scenarios, schema, queries |
| Engine | `scripts/scenes/Combat.gd` (set-piece section) | objectives, clock, rules, resolution |
| Brief | `Combat._sp_show_despatch` | the read-and-dismiss scenario page |
| Readout | `Combat._sp_build_plaque` / `_sp_progress_text` | the live standing order |
| Placement | `CampaignMapGenerator._place_set_piece` | one per act, on a routable row |
| Ground mark | `scripts/ui/painters/ClosedGround.gd` | the exclusion hatch |
| Trophies | `RelicDB` tier `"event"` ×3 | the reason to reroute |

## 4. The five objective kinds

All live in `Combat._sp_evaluate_objective`, all read live state, all safe to
call repeatedly:

| kind | won when | lost when |
|---|---|---|
| `hold_rounds` | you are alive at the end of round N | (only ordinary death) |
| `slay_marked` | the marked body falls | the clock runs out |
| `protect` | the warded body lives to round N | the ward falls |
| `break_face` | N face damage dealt by round X | the clock runs out |
| `clear_board` | no enemy creature stands at a round's end | the clock runs out |

Every kind answers two questions on the plaque — *how am I doing* and *how
long have I got* — because those are the only two the player is asking.

## 5. Failure is not death

**When the clock runs out the army WITHDRAWS.** The toll is paid in HP, the
trophy is forfeit, the march continues. Dying the ordinary way (HP 0) still
ends the run, through the ordinary path.

This is deliberate and it is the reason set-pieces are allowed to be hard.
An authored puzzle that ends a 40-minute run on a whiff is a feel-bad; the
Into-the-Breach lesson is that a good run is built from modest losses taken
in the right place. The toll is **clamped below lethal** in
`Combat._sp_withdraw` and **stated on the map tooltip** before the player can
commit — a price accepted, never a trap sprung.

## 6. The three shipped scenarios

**The Sunken Road** (act 1, `hold_rounds` 5) — *The banks are too steep to
climb. Only the two centre lanes can be held, by either side.* The teaching
set-piece: it takes the player's single most reliable habit (spread out, plug
holes) and removes the room to do it. Trophy: **The Sunken Road Stone** — the
first creature you field each round gains Armored.

**The Pay Column** (act 2, `protect` 5) — *The Paymaster's Cart cannot attack
and cannot be healed.* The whole board becomes a screening problem. No
bespoke AI was needed: the enemy dealer already prefers occupied player
columns, so it comes for the cart on its own. Trophy: **The Paymaster's
Tally** — 12 gold at the start of every fight.

**The Standard of the Fourth** (act 3, `slay_marked` 6) — *While the Bearer
stands, every other enemy that falls returns at the end of the round.* The
priority-target puzzle: every kill that isn't the Bearer is a wasted swing.
The Bearer is FRONT row on purpose — a back-row Bearer would be unkillable
for a deck with no reach, and an authored scenario must never be unwinnable
on a draft the player couldn't have known to make. Trophy: **The Eagle of the
Fourth** — the first friendly body that falls each fight gets back up.

All three anchor on the shared canon (COPY_STYLE §10): the Old King, and the
Fourth Legion he never paid.

## 7. Map placement

`_place_set_piece` rides exactly the war-road trade, because that trade is
proven:

- a **plain fight row only** (3 / 9 / 15) — never the landing row 0, never an
  elite band (which already spends the route budget on a General);
- a row **at least 2 lanes wide**, so the named action can always be routed
  around. It must be a choice read off the chart, never an ambush;
- **never the war road's own row**, so the act's two optional spikes stay two
  separate decisions instead of one loaded corner of the map;
- **no mutator** on top of its own ground — one twisted rule at a time, the
  same restraint the boss branch already practices;
- **never in the first campaign's act 1** — a closed board with a deadline is
  a bad first impression of "what a fight is."

If no row qualifies, the act simply gets none. These are named **ground**,
and named ground does not move somewhere else to be convenient.

## 8. Gotchas earned during the build

- **`EncounterDB.make_card_data` is a strict whitelist.** A key not named
  there is silently dropped. The `sp_mark` / `sp_ward` flags are therefore
  re-stamped in `SetPieceDB.build_opening` *after* the call, not authored into
  it. This is the same trap that once shipped The Old King's Body un-immune
  while still looking correct in the data.
- **Never read back the slot you asked for.** `_place_enemy_card` may
  redirect an arrival (salt, closed ground, an occupied seat). The marked body
  is found by scanning `_all_enemy_creatures()` for its card_data flag after
  the whole opening is seated. Reading the requested slot could lose the mark
  and make the objective unwinnable.
- **Authored bodies are seated by hand, not through `summon_token`.**
  `summon_token` layers Conscription / Sharpened Pitchforks / Standard Bearer
  riders onto everything it makes. A scenario whose warded cart quietly gains
  +1/+1 no longer means what its brief said. The fight probe asserts every
  opening body is seated at exactly its printed HP.
- **There are TWO ways to carry a named action**, and both must pay: meet the
  order, or simply break the foe outright before the clock runs down. The
  award is split into `_sp_award()` and called from *both* the objective path
  and `_check_game_over`'s ordinary victory branch. The first draft paid only
  the first, so a player fast enough to burn the face down won the fight and
  silently lost the trophy — the worst possible lesson.
- **A dead commander carries nothing.** `_sp_round_end_check` returns early on
  `player_hp <= 0`, or an objective ticking over on the same round the clash
  killed you would stamp "THE FIELD IS CARRIED" over a defeat screen.
- **A gate needs a visible mark.** Closed ground is the only rule in the game
  enforced by refusing a drop rather than by a hook. A refusal the player
  cannot see reads as a bug in the drag code, so closed lanes wear the
  `ClosedGround` exclusion hatch instead of a station mark.
- **Probe design lesson:** the first draft of the fight probe used a passive
  commander on a 30 HP hero. It died on round 3-4 every time and never reached
  a single deadline — it was measuring the clash, not the clock. The pass now
  boots with a deep HP pool so the deadline is what gets tested.

## 9. Where this could go next

Nothing below is built.

- **More scenarios.** The engine supports five objective kinds; only three are
  exercised. `break_face` (storm the gate before the relief column arrives)
  and `clear_board` (clear the ambush) are unused and cost data only.
- **More `rules` switches.** `closed_lanes`, `revive_while_mark` and
  `no_reinforce` are declared; only the first two are wired. Each new switch
  needs its gate at *every* arrival path, not just the obvious one.
- **A set-piece as an act's climax.** The boss branch deliberately refuses
  mutators; a named action before the keep would be the natural place to test
  whether the run's build does the specific thing the act has been teaching.
- **The other two survivors of the 2026-07-20 research pass**, both still
  unbuilt and both independent of this: *Two Banners* (a Monster-Train-2 dual
  pool — hero + a sworn tribe at run setup, 30 openings for a weighting
  change) and *the dead as currency* (the Roll of the Fallen is the run's
  most reliably generated resource and is currently read six times and spent
  once).
