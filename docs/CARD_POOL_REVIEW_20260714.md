# Card Pool Design Review — 2026-07-14 (adversarial two-round AI review)

**What this is.** A cold review of all 165 draftable cards by an independent critic AI with no
attachment to the designs, followed by a rebuttal round where house-side code facts, sim telemetry,
and operator precedents were fired back, and the critic updated or held each position. Findings below
are marked by how they survived that crossfire.

**STATUS UPDATE 2026-07-15 — the interest slate implemented much of this menu** (18 cards replaced,
ids kept; verify `tools/_probe_interest_slate.gd`): #3 washed-draw purge (gravedigger→grow,
mourner→Command dues, lookout→scout), #4 wall cluster (differentiated instead of cut — max-hit cap /
reflect / heal / spawn / fortifier, all re-costed to c1-c2 and net-legal), #7 near-dupes (tallow_doll
→ betrayal curse; scavenger → on-death gold), #10 voltron package (Oathbound Squire bodyguard common
+ Honor Guard column-ward rare at c4), and the rare-slot statballs (the_leveler → front-line ram,
vampire_lord → Dead-feed). Still open: #1 rules-honesty micro-patch, #2 counter disclosure, #5
vocabulary unification, #6 Swift audit, #8 concentrate rarity, #9 the 2/3 re-costs.

**Snapshot caveat.** The pool was mid-edit by a concurrent content pass (affinities / Formation /
The Black Contract) when the dump was taken. In-flight vocabulary was noted but not scored.

---

## The protocol (repeatable — run this for relics, events, potions, encounters next)

1. **Dump the live data**, not the docs: `tools/_probe_card_dump.gd` (headless) prints every
   draftable card's rules text next to its machine data. Equivalent dumps are trivial for RelicDB /
   Event.gd / PotionDB / EncounterDB.
2. **Round 1 — cold critic.** Spawn a fresh agent with (a) the dump, (b) the game's *mechanical
   ground truth* (board shape, simultaneous counters, pacing telemetry, resource rules, rarity/cost
   conventions, the house design bar) — and none of the house's opinions. Demand: per-item ratings,
   top/bottom lists, cluster analysis, and ranked pool-level changes. Require claims specific enough
   to check.
3. **Fact-check round.** Verify every quantitative claim against the dump/code before rebutting
   (this round: the critic's "17 two-cost 2/3s" was actually 21; its soul_swap ruling was backwards).
4. **Round 2 — rebuttal.** Concede what the code confirms, rebut with context the critic lacked
   (hover glossary, mode-specific cards, operator precedents), and demand HOLD/CONCEDE per point,
   rating updates, and an implementation-ready action list.
5. **Synthesize with dissents.** The house reviewer annotates the final list — the critic is not
   auto-trusted (see the soul_swap correction below).

---

## Verdict

**Pool: 6/10** (critic's score; house concurs with the shape of the argument). The sacrifice
engine, the push-physics suite, and the run-memory cards (The Undying, Ironclad Veteran, Muster the
Fallen, Forgefire) are genuinely distinctive — better than most commercial deckbuilders at connecting
cards to a campaign. The weight is in the wrong places: wall clones, washed-draw riders, a 21-card
2-cost 2/3 glut, and the game's strongest keyword handed out as flavor.

## Settled findings (survived both rounds; quantities verified against the dump/code)

- **21 two-cost 2/3 creatures.** Half the pool's combat math is one body with different riders.
- **Top-end starvation: exactly 3 creatures above cost 3** (doom_knight c4, dragon_hatchling c4,
  the_leveler c5), no spell above 3 — and **exactly one card (Duelist) reads the bank-2 rule**.
  With banking, the effective ceiling is 5 Command and there is nothing to bank toward.
- **Washed draw is dead design** (house sims independently confirmed): gravedigger, mourner,
  lookout's back mode are built on an effect refill-to-5 neutralizes.
- **Counter-disclosure is inconsistent in code and text**: Hydra's text discloses it takes every
  counter; Charge! takes only 1 counter in code and says nothing; smite/time_snare/cataclysm are
  silent. Card-honesty class bug.
- **Swift is the strongest keyword under simultaneous counters** (kill-before-counter; playlog sims
  agree) and sits on ~12 cards plus two granters as if it were flavor.
- **Voltron/protect is the biggest archetype hole** (~4 real cards) in the one game whose campaign
  system (veterancy: 3/6/10 kills) makes raising a single creature the long game.
- **Poison is sub-critical** (5 cards, 1 payoff — the_apothecary starves in most decks).
- **Rare slot integrity**: concentrate / the_leveler / vampire_lord are efficiency statballs wearing
  the gold gem.
- **Exhaust on 32 of ~75 spells** — at that density its signaling value collapses (open question,
  not acted on).

## Points the critic conceded on rebuttal

- Plain-keyword commons (mule/lancer/ash_hound) are house-sanctioned (hover glossary + the
  Plague Rat "simple commons are a feature" precedent). Ratings raised; residual holds: Overrun's
  N-printing is inconsistent across cards, and mule has zero on-face identity.
- The Coin is the netplay going-second equalizer, not a draft roll — critique withdrawn.
- Pillage (aimed slay-gold) is a real decision; **scavenger held** — its slay trigger is unsteerable
  auto-combat, so the gold rider changes no decisions.
- ctype footer: principle held ("player-visible dead structure invites tribal drafts that don't
  work") but priority dropped pending the faction redesign that will read the stamps. Interim ask:
  consider muting the footer tag until readers ship.

---

## Final action list (critic's, ranked by leverage-per-effort) — with house annotations

**1. Rules-honesty micro-patch** — text-only, near-zero effort. HOUSE: endorse, with one correction.
   - gravecaller → "On-Enter: gains +1/+1 for each friendly that has fallen **this turn**."
     (round→turn; matches the operator-confirmed sacrifice-combo intent. HOUSE: verified — the round
     tally resets at player-phase start, so "turn" is the honest word.)
   - assassin → "Swift. On-Enter: destroys the opposing creature — front row first."
     (HOUSE: verified in code — `get_opposing_card` prefers front, falls through to back.)
   - basilisk → "Poison. Thorns. Any striker its Thorns wound dies."
     (HOUSE: verified — thorns BYPASS Armored by design; Shield blocks the recoil and therefore the
     venom. "Wound" is the honest verb. Armored is NOT the counterplay; Shield is.)
   - soul_swap — **CRITIC WRONG, corrected**: code already floors swapped HP at 1 (a swap can never
     kill). If anything, print "(never below 1 HP)". Do NOT print the critic's "a creature left at
     0 HP dies" — it contradicts the implementation.

**2. Counter-disclosure prints** — HOUSE: endorse the pattern; verify each card's code behavior
   BEFORE printing (Charge!'s take-1-counter is confirmed; smite/time_snare/cataclysm need the same
   check). Hydra's self-disclosing wording is the house template for all extra-strike cards.

**3. Washed-draw purge** — HOUSE: endorse direction; two caveats.
   - gravedigger → "When a friendly creature dies on your turn: this gains +1/+1."
   - mourner → "On-Death: your first card next turn costs 1 less." CAVEAT: Mourner is a STARTER in
     hero decks and Kindler's hero blurb ("Mourners refill your hand from the grave") references the
     current draw — hero copy must move with it; the in-flight `owed` affinity pass may also be
     building on Mourner. Coordinate before changing.
   - lookout back mode → scout information ("you see the foe's next arrival") instead of washed draw.

**4. Wall-cluster collapse** — CUT stone_wall, warding_stone, oathwall; merge into ironhide_anvil
   ("Guardian. When this is struck and survives: deal 1 to enemy face and heal your hero 1.").
   HOUSE: endorse; REQUIRES a deck save-scrub for cut ids (precedent: the 2026-07-07 relic-pool cut
   scrubbed unknown relic ids from saves — decks need the same treatment).

**5. Vocabulary unification** — one freeze word everywhere ("Stunned": frost_bolt, hoarfrost,
   overwhelming_force); Overrun prints N consistently or never. HOUSE: endorse, text-only.

**6. Swift audit** — doom_knight keeps Swift, drops Piercing (restores one-concept; Swift-rental was
   the 07-13 balance-pass identity); dragon_hatchling loses Swift, re-stat 4/6. HOUSE: endorse —
   consistent with the balance-pass lesson (cut the VALUE, not the stats; hatchling's sim lift was
   +9 even after stat taxes).

**7. Near-dupe cull** — CUT tallow_doll (grave_clutch/necromancer own the slot), CUT lost_tome
   (scholar is the same knob with a body); scavenger → "Swift. Slay: gains +1/+1 this fight."
   HOUSE: endorse cuts (same save-scrub caveat); scavenger change is a design call for the operator.

**8. Rare-slot integrity** — concentrate rare→uncommon now; flag the_leveler / vampire_lord for the
   next rare pass. HOUSE: endorse the rarity move (precedent: the 07-13 rarity pass moved 18).

**9. Re-cost five 2/3s to c3** (corpse_eater 3/4, revenant 3/4, griffin 3/3, ironclad_veteran 3/4,
   the_glutton 2/4) — thins the glut to 16, thickens the empty c3+ band. HOUSE: endorse as a batch
   to run through the cardpower sweep afterward — the sim exists for exactly this.

**10. Ship a voltron/veterancy package** (sketches below) — fills the confirmed biggest archetype
   hole; Honor Guard lands at c4 to feed the starved top end.

## Voltron sketches (critic's, for operator judgment — not built)

1. **Oathbound Squire** — common creature, c2 1/4, soldier.
   "On-Enter: bond to an adjacent friendly. Damage it would take hits this instead."
   (Redirect machinery exists: Guardian / Shieldmaiden interpose / Royal Guard.)
2. **Dub the Champion** — uncommon spell, c1.
   "A friendly creature gains +1/+1 this fight for each kill it has made this fight. Exhaust."
   (Kill tracking already exists for veterancy epithets.)
3. **Honor Guard** — rare creature, c4 2/7, soldier.
   "The friendly sharing its column can't drop below 1 HP while this lives."
   (New machinery: a persistent Last-Stand-like floor aura; bounded.)

---

## Appendix — full cold ratings (round 1, with round 2 updates applied)

Design quality, not power. 8+ = creates real decisions; ≤3 = redundant/decision-free/fights the
pacing model. Round-2 updates already folded in (ash_hound 3→5, lancer 3→5, mule 2→4, coin 4→6,
pillage 4→6, scavenger 4→5). Per-card one-line reasons are in the session transcript; regenerate by
re-running the protocol.

| Score | Cards |
|---|---|
| 9 | the_undying |
| 8 | adaptable, apocalypse, duelist, forgefire, glass_knight, hydra, informer, sappers_charge, slow_match, volunteer, warden_of_graves |
| 7 | assassin, ballista_bolt, basilisk, battle_drummer, blood_pyre, close_ranks, copycat, corpse_eater, doppelganger, earthquake, echo_spell, ember_stalker, fuel_the_pyre, grave_clutch, harpy, holy_smite, inspire, ironclad_veteran, kings_command, long_roll, mark_of_ash, mass_grave, muster_fallen, offering, paladin, patch_up, pikeman, plague_bell, pressed_man, riteforge, shove, sin_eater, the_glutton, trebuchet, war_cry, warchief, wolf_pits |
| 6 | adrenaline, ambush, banish, battle_hymn, berserker, bloodhound, bramble_stockade, burning_martyr, carrion_priest, cataclysm, charge_spell, cinder_whelp, coin, crystal_sentry, dark_pact, emberwright, flame_bolt, grave_pact, grave_robbery, griffin, hex, hoarfrost, hellfire_imp, hound, husk, kindling, leyline_conduit, necromancer, old_bones, petard, pillage, raven, reanimate, reckless_charge, revenant, ricochet, royal_guard, scatter_line, scholar, siege_golem, shieldmaiden, slash, standard_bearer, summoner, time_snare, treasure_hunter, turbo, vengeance, war_chant, war_council, witch |
| 5 | ash_hound, bastion_lord, blood_tithe, breaker, chaos_imp, cleave_hound, concentrate, doom_knight, dragon_hatchling, familiar, frost_bolt, gravecaller, hexblade, inferno, iron_bastion, lancer, lay_on_hands, levy_rider, lookout, lost_tome, naga, overwhelming_force, palisade, plague_rat, provision, quick_shot, rat_piper, recycle, scavenger, shield_wall, shieldbearer, skirmisher, smite_spell, soul_swap, tallow_doll, the_leveler, thornguard, torchbearer, unholy_bargain, vampire_lord, venom_tip |
| 4 | bloodsworn, brute, cinder_acolyte, ember_warden, gambit, goblin, heartwood_elder, ironhide_anvil, mending_light, mule, oathwall, sprite, squire_captain, strike, troll, warding_stone |
| 3 | cinder_pup, fireball, gravedigger, mourner, spark, stone_wall, the_apothecary |

## Next targets for the same loop

RelicDB (~135 relics — same critic setup, add the hook vocabulary as ground truth), Event.gd
(30 events), PotionDB (14), EncounterDB (55 lineups + passives — give the critic the pacing
telemetry and act structure). Each needs only a dump probe and the two-round prompt pattern above.
