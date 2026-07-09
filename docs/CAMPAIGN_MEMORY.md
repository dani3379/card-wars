# Campaign Memory — the run remembers your army

**Concept.** The war-table fiction says your deck is an army on campaign — but the build
treats every creature as anonymous paper. This system makes the campaign *remember*:
creatures accrue deeds, earn names, and the run keeps a ledger of its dead. Solo only
(skirmish decks are per-match; RunState is untouched by net play).

## Rules (v1 vertical slice)

**Veterancy** — every combat kill landed by a real deck creature (deck_uid ≥ 0, not a
token, not an enemy) is tallied against its uid for the rest of the run.
- Kill 1+ — **tally scratches** appear on the writ itself (rust ink, groups of five,
  left margin under the cost seal). The card the player holds IS the service record.
- Kill 3 — the creature earns an **epithet**: "Pikeman *the Grim*". Deterministic per
  uid (hash into a fixed table), so it never rerolls across save/load. In-fight moment:
  a BLOODED trigger callout.
- Kill 6 — **veteran rank**: permanent +1/+1, folded into the card like any other mod.
  In-fight moment: VETERAN +1/+1 callout and the live instance is buffed immediately.

**The Roll of the Fallen** — every time a real deck creature dies in a fight, the run
logs a fall: name (with epithet as worn at death), encounter, act, round. Creatures
return next fight as always — the Roll is the ledger of *falls*, not removal; a
much-bloodied veteran can fall twice and both falls are history.
- The **Game Over screen** closes the run with the Roll (last falls) and the run's
  **named veterans** (top killers with their epithets and tallies).
- The **Gravesong Choir** event sings your actual dead: `{fallen}` in event text
  resolves to the most recent fall's name ("the nameless" when the Roll is empty).

## Decisions & rationale
- **Kills, not damage** — one legible number, already tracked at one chokepoint
  (`_apply_combat_strike_riders`, which sees every combat path incl. Swift / ranged /
  Hydra / Doubled Hour). Spell kills don't count: the *creature* earns its tallies.
- **Thresholds 3 / 6** — a 3-kill creature is a story already (fights last 2–3 rounds);
  6 combat kills by one body is a run-defining career and earns a modest +1/+1, not a
  build-around payoff. No further ranks in v1.
- **Epithet is derived, not stored** — uid-hash into a fixed table; saves stay small
  and legacy saves need no migration (missing dicts default empty).
- **Fold lives in `get_upgraded_card_data`** — every existing consumer (Combat draw,
  deck viewers, Rest, Wayside, Shop, events) inherits tallies/epithet/+1/+1 for free.
- **Tokens and net games excluded** — tokens have no identity (uid −1); skirmish has
  its own deck state and different stakes.

## Implementation map
- `RunState.gd` — `creature_kills: Dictionary` (uid→int), `fallen: Array` (dicts),
  `record_kill(uid)→int`, `record_fall(entry)`, `veteran_epithet(uid)`, fold in
  `get_upgraded_card_data` (adds `veteran_kills` key; epithet at ≥3; +1/+1 at ≥6),
  reset in `start_new_run`, save/load keys `creature_kills` / `fallen` (int-keyed
  dict restored like `card_upgrades`).
- `Combat.gd` — kill hook in `_apply_combat_strike_riders`; milestone callouts;
  fall hook in `_on_friendly_death`.
- `Card2D.gd` — tally scratch painter on the chart layout when
  `card_data.veteran_kills > 0` (display cap, then a numeral).
- `GameOver.gd` — Roll of the Fallen + named-veterans section.
- `Event.gd` — `{fallen}` token; Gravesong Choir uses it.
- Probe: `tools/_probe_veterancy.gd`.

## Follow-ups (not in v1)
- More events that recognize the Roll (the Bone Pit rattling your own dead; a wayside
  "bury the fallen" verb). — cheap, land with event passes.
- The Chronicle (meta screen reading `runs.csv` as written history) can quote a run's
  greatest veteran and worst massacre once this ledger exists.
- Enemy-side memory (a rival taunting the hero who killed him before) belongs to the
  Chronicle workstream, not here.
