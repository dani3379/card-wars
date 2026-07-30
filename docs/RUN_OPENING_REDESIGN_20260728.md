# The Run Opening — Redesign

**2026-07-28. SPECCED; Phases 0 and 1 BUILT (Phase 2, the banner, is NOT built).** Six-agent pass (online research · war-chest economics · hero/flow audit · two opposing designs · adversarial critique · codebase feasibility red-team). Every claim below was verified against the live tree or measured from a rendered frame; where the critique and the red-team disagreed, the red-team's `file:line` reading wins and the disagreement is recorded.

The complaint that started it: **the options at the start of a run are not comparable at all.**

---

## 1. What was actually wrong

### 1.1 The war chest deals in four currencies at once

One real dealt slate, captured from `tools/_shot_runstart.tscn`:

| Tile | Unit |
|---|---|
| The Vivandière's Crate | 2 random potions |
| The Black Ledger *(RISKY)* | a Boss relic + 2 Curses |
| The Iron Ration | +7 max HP |
| The Paymaster's Advance | 75 gold |

Four options, four unrelated units, and **not one of them changes how you play**. There is no shared axis, so the "decision" is really a trivia question about this game's internal exchange rates. Griftlands ships the identical shape — item / money / cards / graft — and its community collapsed it to "just take the money or the graft."

### 1.2 The labels are backwards

- **`black_ledger` is flagged RISKY and is the always-take.** 15 of the 21 boss relics carry `retired: true` and are filtered at `RelicDB.gd:910`; the live boss pool is **6 relics, every one strictly positive**. There is no devil in the bargain.
- **`hollow_levy` (remove 2 chosen cards) is also flagged RISKY**, despite deck-thinning being among the strongest effects in the genre.
- **Curses cost far more than the copy admits.** A drawn curse is unplayable (`Combat.gd:8753`) *and* exempt from discard-marking (`Combat.gd:11723`), so under `HAND_REFILL_TARGET = 5` with `PERSISTENT_HAND` it **permanently occupies a hand slot for the rest of the fight** — −20% throughput each, compounding. Two curses can mean fighting an act on a 3-card working hand. This is invisible at the moment of choosing.

### 1.3 One tile strictly dominates another in the same pool

`relic` draws from the hardcoded 11-entry `FOUNDATION_RELICS` (`RelicDB.gd:778`), expected shop value **107.5g**. `gold` pays **75g** that cannot be spent until map row 4, on a route that hits only ~1–1.5 shops per act. Same pool, one is simply better.

### 1.4 Blind hero-dependent swings

- **Conjurer's Coffer** (a live boss relic, so a `black_ledger` roll) transforms starter-rarity creatures into random rares: **9 bodies for Raider, 1 for Kindler.**
- **`transform2`** rolls same-rarity, which is a step-up for four heroes and a **pure lateral coin-flip for Kindler** (his opener is all common-rarity).
- **`butchers_kindness`** (+2 ATK, Wither 1) on Stalwart's 0-ATK Palisade builds a body that **kills itself**.
- **`lantern`** needs an exhausted spell; only Pyromancer's `spark` qualifies. Inert for 4 of 5 heroes, with no `_offer_allowed` gate — a 7.5% dead roll.

### 1.5 The heroes are not comparable either

| Hero | ATK mass | Face reach in the opener | Bodies / spells |
|---|---|---|---|
| Raider | 19 | 1 | 9 / 1 |
| Acolyte | 14 | 0 | 8 / 2 |
| Kindler | 14 | ~23 potential | 8 / 2 |
| Stalwart | 11 | 0 | 8 / 2 |
| **Pyromancer** | **9** | **0** | **4 / 6** |

**Pyromancer is a trap pick.** Four creatures in ten cards on a 4×2 board, and neither `strike` nor `spark` can target the face — both are `targeting: "any_creature"` (`CardDB.gd:38`, `:67`). Its entire clock against a lord is 3 Trolls and a Naga.

**Three hero pitches are factually false**, and all three lie on a live mechanical axis:
- Raider: *"Outriders and Ratlings attack before the main clash"* — **Ratlings have no Swift.**
- Stalwart: *"A defensive Soldier deck"* — only **4 of 10** are `ctype: soldier`; Troll and Naga are `beast`, and tribe drives seasons, keystones and `type_buff`.
- Kindler: *"Rampage creatures grow stronger"* — the deck has **exactly one** Rampage card.

**8 of Kindler's 10 cards are pool commons with no `draftable: false`**, so a Recruit slate can offer him a third Cinder Pup *as a reward*.

### 1.6 The flow asks before it tells

`start_new_run` rolls the season (`RunState.gd:422`) and the three rival lords (`:421`) — then `MainMenu.gd:2059` shows the war chest, which prints the season line. **The information arrives one screen after the decision it should inform.** The rival lords are never shown at all.

Also live: no BACK on the chest (a one-way door once the map and PlayLog session exist); the chest roll uses global `shuffle()`/`randi()` so **Daily March players get different gifts on the same seed**; `MARCH AGAIN` silently discards unlocked `relic_alt`/`deck_alt`; the ascension stepper is gated behind `unlocked_ascension` and **never renders on a fresh profile**; `DECK_MINI_SCALE := 0.36` renders card rules text at ~5px against a documented 18px floor; and `_focus_hero` is bound to `mouse_entered`, firing un-awaited un-batched `CardTextureCache.bake()` calls that serialize on a global mutex at ~2 frames each — sweeping the roster queues 25–40 bakes.

---

## 2. What the genre does about it

- **Slay the Spire 2 hit this exact complaint and rebuilt Neow so every option is the same noun — a relic.** "150 gold" ships as Golden Pearl; "+11 max HP" as Nutritious Oyster. Three offered, **no skip**.
- **Slay the Spire 1 instead slots the pools by role**: a deck-shaper, a body-and-purse, a priced two-part trade, and the boss-relic swap. The player never compares gold to HP — they pick *which axis of the run to move*.
- **STS2 mirrors the priced option against its free twin** and excludes the pair from co-occurring, so the price reads as an exchange rate.
- **Monster Train / Balatro / Hades** avoid the comparison entirely: the opening is an identity (clan pair / deck / god = shape × rarity = magnitude), and difficulty lives on a **separate** axis.
- The counter-case is real: Sirlin argues incomparability *is* the skill ("valuation"), Sid Meier's failure list names the **uninformed** choice rather than the incomparable one, and Burgun notes a run-*opening* screen has no board state to couple to and so goes flat by construction.

**The synthesis taken here:** the failure is not that the options differ in kind — it's that they differ in kind *without naming the axis*, and that the labels lie about the ranking.

---

## 3. The design — THE MUSTER

One screen. `MAIN MENU → THE MUSTER → map`, with **BACK live until commit**.

The screen separates the two things the old flow conflated: **the Banner gives direction, the Writ gives power.**

### 3.1 Layout (1600×900; all x derived from `size.x`)

| Region | Content |
|---|---|
| **Left — THE HOST** | 5 hero rows: portrait, name, tagline, corrected pitch |
| **Centre — THE ROLL** | the live opener at **0.62 scale (~140×186)**, rebuilt on hero *or* banner change so the banner's card visibly marches in; hover floats the full live-baked Card2D (the shipped `_show_log_preview` mechanic) |
| **Right — THE BANNER** | 6 tribe chips, one line each, identical shape |
| **Bottom band — THE WRIT** | 4 tiles in fixed roles I–IV, dealt seeded |
| **Footer** | ascension stepper (**always rendered**), DAILY MARCH, seed, TAKE THE FIELD — and the season/rival line, printed **before** commit |

### 3.2 THE BANNER — direction (6 chips)

Choosing a banner does exactly three things, **none of which touch map generation**:

1. Sets `season_tribes[0]`, feeding the `+2` affinity already wired at `Recruit.gd:135`. Zero new code.
2. Leaves `season_tribes[1]` a seeded roll, printed on the footer before commit. *The player declares one tribe; the war deals the other.*
3. Adds **one** authored starter-rarity card to the opener. Deck **10 → 11**, identical for all six, `draftable: false`.

| Banner | Card | Line |
|---|---|---|
| Soldier — The Colours | Line Marker · 1c 1/3 Soldier, Guardian | "Soldiers answer first." |
| Beast — The Hunt | Loose Horse · 1c 2/1 Beast, Swift | "Beasts answer first." |
| Dead — The Roll | Ash Marker · 1c 1/2 Dead, On-Death: 1 to enemy face | "The Dead answer first." |
| Warlock — The Coven | Hedge Caster · 2c 2/2 Warlock, On-Enter: 1 to opposing | "Warlocks answer first." |
| Bastion — The Works | Marker Stone · 1c 0/4 Bastion, Thorns | "Bastions answer first." |
| Stray — The Contract | Free Lance · 2c 2/3 Stray, On-Enter: gain 10 gold | "Strays answer first." |

This is deliberately weaker than a full doctrine. **At minute one, before a single fight, direction should steer *offers*, not rules.**

*Why tribes:* verified against the card data, **no hero owns a tribe** — every opener is Beast-heavy by accident of the starter pool (Raider 7 Beast/2 Soldier, Stalwart 4/4, Acolyte 6 Beast/2 Dead, Pyromancer 4 Beast/6 spells, Kindler 3 Beast/5 Dead). The hero axis is a *verb* axis; the six-tribe axis is unclaimed and already wired. Crossing them gives 5 × 6 = 30 legible runs from 11 authored entries.

### 3.3 THE WRIT — power (4 fixed slots, seeded from `run_seed`)

**The slot is the comparability fix.** No parity seal and no "worth 120g" stamp — that promise is unkeepable (*The Colours* is worth ~0 to a 4-creature Pyromancer deck and enormous to Raider's seven 1-drops), and one detected lie poisons every other claim on the screen. The honest framing: these are not equal, they are **different**, and the slot names the axis.

- **I · THE ROLL** — deck surgery. Whetstone Cart (forge 2 chosen) / Provost's Broom (remove 3) / Muster Tent (enlist 1 of 5 uncommons) / Old Drill Book (2 chosen creatures each permanently gain a chosen Armored, Swift or Thorns).
- **II · THE ARSENAL** — **choose 1 of 3** from `roll_foundation_relics(3, …)`. *Player choice is what kills the dead-relic problem* — a Stalwart simply doesn't pick the spell-Exhaust relic — which is stronger and cheaper than a liveness gate.
- **III · THE PURSE** — economy as a **rule, never a lump sum**. Paymaster's Ledger (+12 gold after each won fight, ≈252g/run paid along the road where it is spendable) / Sutler's Bond (shop cards −25g, sutler pays double) / Vivandière's Contract (4 potion slots, drop chance +20pp) / Iron Ration Writ (+6 max HP, camps heal +10).
- **IV · THE PACT** — dealt last, **always −6 max HP**, always the escalated twin of the tile standing in **I or III**. Broom 3 → Broom 5. Ledger +12 → +22. Whetstone 2 → 4. Sutler −25 → −45. *One currency, one number, forever.*

**Permanent bans on the opening: no Curses, no boss relics.** Curses because the cost is invisible and unrecoverable; boss relics because a 6-entry all-positive pool is a handout wearing a warning label, and it is the widest-variance object in the game.

**SKIP is cut** — audited as never correct, so it is a trap that taxes only new players.

**Open question, carried to playtest:** the Pact is the same shape the critique used to kill an earlier draft ("one of the escalations is always mathematically correct"). Narrowing it to the *quantitative* slots I and III genuinely helps — "pay 6 max HP to roughly double a number" is comparable in a way "pay 6 max HP for a better board rule" is not — but some doublings will still outrank others. Measure before trusting.

### 3.4 Disposition of the 11 old entries

| Entry | Disposition |
|---|---|
| `gold` (75g lump) | **cut** — the "doesn't change how you play" failure in its purest form |
| `max_hp` | **absorbed** into Iron Ration Writ (III) |
| `potions` | **absorbed** into Vivandière's Contract (III) |
| `relic` | **becomes** THE ARSENAL, now 1-of-3 instead of blind |
| `upgrade` / `transform2` / `recruit` | **become** THE ROLL, with Remount floored at uncommon |
| `black_ledger` | **cut** — a lie |
| `widows_coin` | **cut**; its shape survives as the −6 max HP Pact |
| `hollow_levy` | **cut**; Provost's Broom is the honest version without the Curse |
| `butchers_kindness` | **moved** to the `drill_yard` wayside, which can filter 0-ATK creatures out of the offer |

---

## 4. What was rejected, and why

**No per-doctrine map generation.** The first draft priced each direction with a road change ("no treasure sites", "at most one shop per act"). Verified against `CampaignMapGenerator.gd`:

- The critique's fear that overrides would break the **24–36-site acceptance loop is unfounded** — `n` counts lattice nodes produced by `_generate_paths` *before* any type is assigned (`:80-87`), so type pools cannot move it.
- But the **guarantees run after the pools and ignore them**: `_force_one(grid, 7, "treasure")` (`:327`) is unconditional and would re-stamp a treasure regardless; row 10's recruit is forced at `:312` *and* hardcoded in `_normalize_musters`' list `if r in [4, 10]` (`:369`).
- **`generate_act` runs 60 attempts and then returns the last one anyway (`:95`)** — the acceptance loop **fails open**, so a bad bias ships a degenerate act with no error.
- "No treasure sites" would delete the act's one guaranteed relic-bearing stop — 3 relics across a run — which is not a price but a broken run. Meanwhile "at most one shop per act" costs nothing, because the shop guarantee is **map-wide, not per-route** (`:329`) and a zero-shop route already ships today.

Direction is therefore expressed through the Recruit affinity that is **already wired**, and the road is not touched.

**No `"warchest"` relic tier with ~28 bespoke entries.** `RelicDB` already carries 43 retired ids; content authored once and seen once per run is the worst ratio in the file. (The tier *would* have been safe — every pool builder is an allow-list keyed by literal tier name, so a new tier cannot leak — but three display sites are also allow-lists and would silently mis-render it: `Collection.RELIC_TIERS`, `GameTheme.RELIC_TIER_TAGS`, `RelicDB.TIER_COLORS`.)

**No "hasn't moved since last round" board rule.** `CreatureInstance` has no stationary field, and slot writes are not funneled: `_relocate_creature` has 16 in-file callers plus 3 in `CombatNet.gd` and 1 in `KeywordEffects.gd`, but **direct `current_row`/`current_lane` stamps live outside it** at `Combat.gd:2058, 2096, 2398, 2712, 6154, 8075, 8999`. That is a 13-site cross-cutting refactor before the rule can even be written honestly.

**No 12-card opener with two forced doctrine cards.** 2× a tuned 1-drop is better than a random 2 of the hero's existing ten — a gift dressed as a cost, and it inverts the starter contract. One card, 10 → 11.

**Not deleting `_roll_season`.** Half survives: the player declares one tribe, the war deals the second. Full deletion trades discovery for control at no gain.

---

## 5. Build sequence

Each phase leaves the game shippable.

### Phase 0 — hygiene (no design change) · **BUILT 2026-07-28**

| Defect | Fix |
|---|---|
| `_probe_wayside` red on every seed | stale `treasure >= 2` assertion split into Reliquary + Arsenal (landed first, alone, so later map diffs stay legible) |
| 3 false hero pitches | rewritten against the actual decks |
| Kindler's commons draftable | `"draftable": false` on `cinder_pup`, `kindling`, `ash_hound`, `burning_martyr` |
| Ascension stepper invisible at tier 0 | always render; explain the zero; default to **last-played**, clamped to unlocked |
| 0.36 deck strip (~5px text) | `DECK_MINI_SCALE → 0.58`, plus the layout work it forced (below) |
| `mouse_entered` bake storm | one batched `bake_many(deck, validity)` in `_warm_deck_strip`; `validity` cancels when focus moves off the hero |
| Chest roll unseeded | local `RandomNumberGenerator` seeded from `run_seed` |
| MARCH AGAIN drops alts | RunState records the variants the run used; `rematch_request` carries them |
| Locked-variant dossier lines | deleted, not dimmed |
| `_make_hero_card` (~90 lines) | dead code, deleted |

**The deck strip forced a layout pass, which is the honest cost of legibility here.** A readable strip is ~890px wide for six uniques against ~1036px of inner pane, so the old horizontal band (deck *beside* relic) pushed the relic column off the right edge, and the added height pushed **TAKE THE FIELD under the fold** — the one control that must never be the thing clipped. Four changes paid for it:

- the deck/relic band became a **VBox** (relic stacks under the strip and gets the full width);
- the portrait well went **236×310 → 236×210** — note the inner `TextureRect` carried its own `custom_minimum_size` of 234×308 and silently overrode the frame, so both had to move;
- the tier-0 ascension line was cut to one line;
- the subscreen grew **850 → 872** in a 900-tall canvas.

Verified by re-rendering `tools/_shot_runstart.tscn` (new this pass — 10 frames covering the menu, three focused lords, an ascension state, four dealt war-chest slates and a card picker). **Judge this screen from those frames, not from the code** — every one of the four problems above was invisible in the source and obvious in the pixels.

### Phase 1 — the writ model · **BUILT 2026-07-28**

Shipped: `scripts/data/WritDB.gd` (new autoload) holding the four slot pools, the pact table and the slot furniture; `MainMenu._roll_blessings` now returns `WritDB.roll_slate(rng)` off a `run_seed`-derived stream; `_pick_blessing` resolves `forge / remove / remount / enlist / enlist2 / arsenal / purse / purse2`; `_apply_blessing` and both SKIP handlers deleted; a new `_show_writ_relic_picker` renders THE ARSENAL's 1-of-3; `_writ_forge_step` carries a `taken` list so a forge-2 cannot re-offer the card it just sharpened; the Remount roll now steps UP a rarity (floored at uncommon) instead of rolling laterally.

Tile furniture: each choice prints its slot rule (`I · THE ROLL — your deck`) above the name, the pact's price chip reads `− 6 MAX HP` and now sits **against** the name (the headline was `EXPAND_FILL`, which shoved the old RISKY chip to the far edge of a 760px column where it floated orphaned mid-screen), and the tiles grew 84 → 112px with an 18px gap because three lines at 84 made each slot label collide with the clause above it.

Gates: **`tools/_probe_muster.gd`** (data — all four slots dealt on 40 seeds, the pact's twin is always on screen, the roll is reproducible, no curse/boss/event relic reachable, every effect id has a resolver arm) and **`tools/_probe_writ_resolve.gd`** (wiring — drives every writ and pact against a live run for all 5 heroes: candidate sets are non-empty, the pact bills exactly 6 max HP and can never kill). `_probe_copy_lint` extended with `_scan_writs`.

**Copy trap, learned the hard way:** the lint's `OPAQUE_TERMS` list bans `writ`, `muster`, `sutler`, `remount`, `provost`, `reliquary`, `levy`, `tithe` and more from player-facing text. The first draft of every name in this file tripped it. Entry **ids** are exempt (only `COPY_KEYS` fields are scanned), so ids kept the original vocabulary while names did not — which is why `provosts_broom` is displayed as "The Discharge Papers".

**Still open from the spec:** the one-screen merge itself (hero + writ on a single screen with BACK live until commit) and the season/rival preview. The chest is still its own screen after the hero commit; deferring the commit needs the pending-picks refactor described below, not a second `start_new_run` call.

### Phase 1b — one screen · **BUILT 2026-07-30**

Merge the chest into setup; season/rivals previewed before commit by extracting their sub-seed maths into pure statics.

**Commit is deferred** — the screen operates on a pending-picks dict and calls `start_new_run` at the final button, reusing the existing `pending_signature_relic` / `pending_deck_variant` pattern (`RunState.gd:325-326`). Do **not** re-call `start_new_run` to back out: with `seed_override == 0` it silently re-rolls the seed (`:420`), opens a second PlayLog session (`:426`), and clears the texture cache (`:423`), discarding the ScenePreload warm.

New `tools/_probe_muster.gd`: every slot deals a non-empty tile for all 5 heroes × 3 seeds; no writ path can reach `random_curse_id()` or `roll_boss_relics`; the Pact's twin is present on screen; the previewed season string equals the post-commit `RunState.season_line()`; the same seed yields the same four tiles.

### Phase 2 — the banner · **BUILT 2026-07-30**


6 tribe chips; `season_tribes[0]` assignment; 6 new starter cards + `UPGRADES` entries; deck 10 → 11; **`spark` retargeted `any_creature` → `any`**, which gives Pyromancer 4 points of face reach for zero new content and un-traps the hero in one line.

`_probe_muster` extends: each banner card is starter-rarity and `draftable: false`; every opener is exactly 11; every hero × banner opener has ≥5 creatures and ≥2 face reach. Re-run `_probe_type_audit`, `_probe_creature_fx`, `_probe_deck_conservation`, `_probe_autorun`.

---

## 6. Traps for whoever builds this

- **Option copy must live in a DB dictionary, not inline in `MainMenu.gd`.** `_probe_copy_lint` loads DB dictionaries only — copy authored inline is size-gated by `_probe_text_floor` but **not wording-gated**. Inline copy silently escapes the "mana"/"elite"/`(s)` lint.
- **`weighted_sample` (`RelicDB.gd:837`) uses global `randi()`.** Seeding the chest is not complete until the relic pick is routed through the local rng too.
- **`MAX_POTIONS` is a `const` (`RunState.gd:25`)** read in ~14 places including layout maths (`MapView.gd:562,565`). The Vivandière's Contract needs `const` → `var` plus save/load; net freezes its own count via `_net_potion_slots`, so skirmish is safe.
- **A run-scoped field does not inherit skirmish immunity.** Relics get it free because `_has_relic` short-circuits on `_is_net()` (`Combat.gd:12431`). Any new run-scoped read needs its own gate — route them through **one** helper with `if _is_net(): return false` inside, the `_load_pay_wagon` pattern (`:2554`). Ad-hoc per-hook guards will rot.
- **A forge-2 must exclude its first pick before re-slating**, or `_blessing_upgrade_candidates()` (`MainMenu.gd:2897`) re-offers the card just forged.
- `_show_blessing_card_picker` / `_show_blessing_offer_picker` are already count-agnostic, and `_blessing_transform_step` / `_blessing_remove_step` are already parameterized by count — 1-of-5 and remove-3 are call-site arguments, not rewrites. Both pickers bake un-awaited and inherit the storm fix.
- **`tools/_probe_menu.gd:53-60`** sweeps `_focus_hero` over every hero then drives `_begin_run_with("raider")` and asserts the blessing screen builds. A deferred-commit refactor must keep it green.
- Per existing memory: `_probe_autorun`'s balance corpus is suspect because probes never set `current_act_idx`. Don't read old win-rate numbers as a baseline for this work.
- **`tools/_probe_type_audit.gd` is red for an unrelated reason** (found during this pass, deliberately not fixed here): line 40 asserts `kingpin` has no passive, but `CardDB.gd:443` now gives it `"passive": "defection"` from in-progress Stray work, and CLAUDE.md still documents the older gold-aura version. Whoever owns that rework should reconcile card, probe and doc. Don't mistake it for run-opening breakage.
- **Do not `git stash` to test a hypothesis in this repo.** The working tree routinely carries very large uncommitted changes across ~100 files; a stash whose restore is interrupted (a probe timeout, say) silently reverts files to a months-old HEAD. Read the HEAD version with `git show HEAD:<path>` instead.

---

## 7. What actually shipped, and the four things that were still wrong (2026-07-30)

Phases 1b and 2 are complete. `MainMenu._show_muster` is the single screen (host · column ·
banner · four terms · footer), `BannerDB.gd` holds the six declarations, and
`RunState.opening_deck_for` appends the banner card so every opener is 11.

The finishing pass found four defects that the build itself could not see, all now fixed and all
now gated:

1. **The writ RESOLUTION rolls were unseeded.** `_roll_blessings` dealt the four tiles off a
   `run_seed` stream, and then Enlist shuffled with `Array.shuffle()`, Remount picked with
   `randi()`, and THE ARSENAL called `roll_foundation_relics` without passing an rng. Two players
   on the same Daily March seed therefore saw the same four tiles and different consequences —
   the reproducibility was cosmetic. All three now route through `MainMenu._writ_rng()`.
2. **MARCH AGAIN dropped the banner.** `rematch_request` carried the doctrine pair (fixed in
   Phase 0) but not the declaration, so a rematch silently marched under the default colours. It
   is the third field with the same failure mode; the fix is the same shape.
3. **The screen's own copy escaped the wording lint** — exactly the trap §6 warns about. It said
   "sign one **Writ**" over a lint that bans the word, and it named the CENTRE band *THE ROLL*
   while slot I is also *THE ROLL* (one screen, one name, two meanings). All of the chrome moved
   into `WritDB.MUSTER_COPY`, the lint now scans it (and `BannerDB.BANNERS`, previously unscanned),
   and the screen reads **ORDER OF MARCH** / **THE COLUMN** / **THE TERMS**.
4. **`_probe_progression` had been red since the banner landed** — three assertions compared
   `RunState.deck` against the raw `HeroDB` list, which is now 10 + 1. Fixed by deriving the
   expected opener from `BannerDB`, so a change of default banner cannot re-break it.

`tools/_probe_muster.gd` grew the gates for all four, plus the Phase 2 contract (every banner card
is starter-rarity, `draftable: false`, carries its own banner's tribe, and has a `+` entry; every
hero × banner × doctrine opener is exactly 11 with ≥5 creatures and ≥2 sources of face reach) and a
drift gate comparing `preview_season_tribes` / `preview_rival_deal` against a committed run — the
preview duplicates the committing code by design, and a drifted preview is a lie printed on the one
screen that promises nothing is final yet.
