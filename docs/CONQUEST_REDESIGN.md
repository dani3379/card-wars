# Burning Meadow — The Successor Wars
### Conquest map, rival-hero bosses, faction redesign & decoupled recruitment
**Status:** design locked in principle, execution not started. This is the working spec.
**Author:** design session, 2026-06. **Scope:** large redesign — phased, with a shippable MVP.

---

## 0. The one-paragraph pitch
You pick one of five heroes. The other four are rival lords, each ruling a kingdom built on a different primal element and a different *answer to a world that won't stop burning*. Across three acts you march on **three** of them — your choice which, and which holds inside their kingdom you bother to break — and topple each rival as that act's boss. The **one rival you never invade** is waiting on the throne at the end: an **amalgam**, empowered by the three kingdoms you burned, fought in three phases that channel the rivals you beat. Card acquisition is pulled *out* of combat — fights pay gold, relics, and ground; you grow your deck deliberately at **recruit** stops. The result fixes "it takes forever to reach the boss," makes every fight a *distinct* faction with its own engine, and turns the whole run into a series of real choices.

---

## 1. Problems this solves (why we're doing it)
| Problem (from playtest/observation) | How this fixes it |
|---|---|
| "It takes forever to get to the boss." | Acts shrink to a handful of holds; you can **skip** holds and rush the rival lord. Pace is a player dial, not a fixed 15-row march. |
| Fights feel **samey**; players ignore effects and just charge. | Each act is a different **faction with its own engine** (Overrun / Formation / Tithe / Foresight / Fuse). Every kingdom plays like a different game. |
| Bosses are anonymous. | Bosses are the **heroes you didn't pick** — personal, archetype-driven, and different every run. |
| Forced card-after-every-fight bloats the deck. | Card acquisition is **decoupled** into deliberate recruitment → leaner, intentional decks → snappier runs. |
| Low agency / linear feel. | You choose **which rival each act**, **which holds** to break, and **when** to challenge the lord. |

**Design constraints (do not break these):**
- Keep the three-act power-scaling backbone (it's how difficulty is tuned).
- Keep the Slay-the-Spire deckbuilder DNA — the *curated draft* moment must survive, just relocated.
- Don't open an economy exploit (no grinding fights for infinite rewards; nodes stay one-shot and finite).
- Reuse the existing map/encounter/combat engine where possible; rewrite only what must change.

---

## 2. Narrative frame (no metaphysics)
The **Burning Meadow** is the smoldering heartland of a fallen empire — one great crown that once bound five peoples together. The crown is empty now, the meadow is on fire, and everyone with an army has made a claim. It's the oldest story there is: **a war of successors.** No cosmic debt, no bargain with the dark — just five rival lords and one throne.

You are one claimant. The other four are your rivals. You burn a road to the throne over the ones in your way; the last one standing inherits everything you fed the fire. (Whether winning frees you or simply makes you the next thing on the throne is **Open Decision #1** — see §11.)

**Tone stays multi-register:** grim folk-tale bass line, gallows humor and warmth on top. The setting *image* keeps fire (the meadow burns, the title stands); the *factions* spread across the elements so fire is one colour among five.

---

## 3. The five factions
History is the **soul** underneath — blended so none is a 1:1 costume of a real civilization — and each faction has **its own engine** (the thing that makes its kingdom play differently). Fire is reduced to a single faction.

| Hero (existing) | Faction *(working name)* | Element | Soul (blended inspiration, never the literal name) | **Their own thing (engine)** |
|---|---|---|---|---|
| Raider | **The Grasswake** | **Storm** | horse-lords of the grass-sea + longship raiders; a people who *are* weather, not a nation | **Overrun** — the empty lane is their highway; cheap Swift units hit harder the less is in their way and bleed you for not walling up |
| Stalwart | **The Last Wall** | **Stone** | the empire that refused to die + the shield-wall + the buried clay army; permanence as religion | **Formation** — creatures grow stronger the longer they stand and lend strength sideways; the clock is their weapon |
| Acolyte | **The Owed** | **Rot** | a tomb-kingdom of embalmers where the dead still hold office; debts paid in funerals | **The Tithe** — deaths are *deposits*; bank the fallen, then cash them out (recursion, reanimation, payoffs that scale with the body count) |
| Pyromancer | **The Lanternhall** | **Frost & Star** | cold scholar-magi & star-readers from a library that outlived its city; magic as mathematics | **Foresight** — few creatures, endless spells; see/lock the turn before it happens; every spell sharpens the next |
| Kindler | **The Everflame** | **Fire** | a doomsday fire-faith that believes the world must burn to be reborn | **The Fuse** — nothing pays now, everything pays *later, bigger*; Doom countdowns + creatures spent as fuel |

**Why the two former "fire" factions no longer collide:** the Lanternhall trades the torch for frost and starlight (fire is one early lesson, not their soul) — cold controlling intellect vs. the Everflame's wild zeal. **Ice against fire.**

Each faction's engine is buildable from cards/keywords that **already exist** (see §8), so the factions are reskins-with-teeth of the current hero archetypes, not from-scratch content.

---

## 4. The campaign loop
```
Pick hero (1 of 5)
  → rivals = the other 4
  → pick 3 of the 4 as act bosses (Open Decision #4: player-chosen vs seeded order)
  → spared 4th = the finale amalgam

Act 1 = Rival A's kingdom  → break holds (your choice) → Rival A boss
Act 2 = Rival B's kingdom  → break holds → Rival B boss
Act 3 = Rival C's kingdom  → break holds → Rival C boss
Finale = the throne → Rival D, amalgam, 3 phases channeling A/B/C
```
- **Agency dials:** which rival each act (macro), which holds to break inside a kingdom (micro), when to challenge the lord (rush vs. prepare).
- **Pacing dial:** you need only break *enough* holds to open the lord (e.g. ≥N); skip the rest to rush him under-prepared.
- **Replayability:** hero × which 3 rivals × order × which one's the finale = a different campaign every run. The 5th hero (Kindler) is exactly what makes "spare one for the finale" arithmetic work — with 4 you'd face everyone.

---

## 5. Card-acquisition decoupling
**Today:** `Combat.gd` → `REWARD_SCENE ("res://scenes/reward.tscn")` → `Reward.gd` offers a 1-of-3 card pick (plus relic/skip-for-gold) → map.

**After:**
- **Fights pay ground, not cards** — gold, the occasional relic, healing, and *progress* (a broken hold). The post-combat screen keeps relic/gold but **drops the card pick**.
- **Cards come from Recruit stops** — a new node type (and/or a returnable stronghold) offering a **curated, paid 1-of-3 draft.** The draft *moment* (the core deckbuilder pleasure) is preserved — it's just a deliberate spend now, not an automatic drip.
- **Net effect:** leaner, intentional decks; you decide your power-growth pace; deck bloat (a big part of the "forever" feeling) disappears.

**Currency** is **Open Decision #2**: plain gold (simplest, reuses Shop economy) or a new **renown/influence** you earn by conquering (more 4X texture, more to balance).

---

## 6. The amalgam finale (resolving "some combination of them")
The throne-sitter is the **one rival you never invaded**, fought as a single boss in **three phases**, each phase channeling one of the rivals you actually beat this run. A Grasswake player who toppled the Last Wall → the Owed → the Lanternhall faces a finale that **walls up, then tithes its dead, then freezes** — under the fourth lord's own banner.
- It's literally "a combination of them," it's *your* combination, it's **one contained climax** (not a grindy boss-rush), and it's never the same twice.
- Beats the alternatives we rejected: a **gauntlet** re-introduces "takes forever" at the finish; a **3v1 on one lane board** is spectacular but brutal to balance.
- **MVP** uses pre-authored phases per finale-rival ("the throne has absorbed three kingdoms"); **full version** assembles the three phases from the *actual* rivals you defeated.

---

## 7. Faction → encounter mapping (content audit)
The existing `EncounterDB.ENCOUNTERS` (26 fights across 3 acts, each `{name, act, type, hp, passive_id, passive_desc, deck, reinforcement}`) is largely re-taggable rather than rewritten:
- **Step 1:** add a `faction` field to every encounter (`grasswake|last_wall|owed|lanternhall|everflame`).
- **Step 2:** map existing fights onto factions by theme — the Pyre/Doom encounters → Everflame; sacrifice/undead → Owed; wall/armor → Last Wall; swarm/aggro → Grasswake; spell/control → Lanternhall.
- **Step 3:** fill gaps — every faction needs enough holds to populate an act (~5–8). Where a faction is thin, author new encounters reusing the shared card pool dressed in that faction's element.
- **Step 4:** the **rival lord bosses** — five new boss kits in `EncounterDB.BOSS_PHASES`, one per hero, each a scaled version of that hero's deck (`HeroDB.HEROES[id].deck`) + a signature passive that screams the faction's engine.

A faction-mapping worksheet (which of the 26 lands where, and the gap list) is the **first concrete deliverable of Phase 5** below.

---

## 8. Signature faction keywords (the engines, specced)
Three already exist and ship today; two are new. Phase these in — the MVP can lean on what exists.

| Engine | Keyword | Status | Mechanic sketch |
|---|---|---|---|
| Overrun (Grasswake) | `overrun` | **new** | When this attacks a lane with no front-row defender, it deals +X and a rider effect (draw / face burn). Punishes empty lanes. |
| Formation (Last Wall) | `formation` | **new** | At start of round, if this has an adjacent friendly, both gain +0/+1 (or +1 ATK). Rewards holding a line; pairs with existing `adj_buff`, `guardian`, `thorns`, `armored`. |
| The Tithe (Owed) | reuse `sacrifice` + `on_death` + a new `tithe` counter | **partly new** | A run/fight tally of friendly deaths that powers payoffs (reanimate, scaling buffs). Builds on the live sacrifice/on-death engine. |
| Foresight (Lanternhall) | reuse spell-scaling + new `scry`/`foresight` | **partly new** | Look at / reorder the top of your deck; spells get cheaper/stronger per spell cast (the existing Hexblade pattern, formalized). Frost = `can't attack` / `-ATK` lockdown. |
| The Fuse (Everflame) | reuse `doom` + `rampage` + `lifelink` | **exists** | Already live (the Kindler set). Formalize "Fuse" as the umbrella flavor; no new keyword strictly required for MVP. |

New keywords follow the standard path: add to `KeywordEffects.KEYWORDS`, implement in the dispatchers, add to `Card2D` display, and write `docs/COPY_STYLE.md`-compliant text.

---

## 9. EXECUTION PLAN (phased, file-by-file)
Each phase is independently shippable/testable. **Parse-check** (`--headless --editor ... combat.tscn`) and **render-verify** (the screenshot probe) after each, per house workflow.

### Phase 0 — Scaffolding & data model (no behavior change yet)
- **`HeroDB.gd`**: no schema change; it already holds the 5 heroes + decks. Confirm `HERO_ORDER` for the rival pool.
- **`RunState.gd`**: add run-state fields:
  - `var rival_lords: Array[String] = []` — the 3 act bosses (hero ids), index = act.
  - `var finale_rival: String = ""` — the spared 4th.
  - `var act_faction: Array[String] = []` — faction id per act (derived from `rival_lords`).
  - `var holds_broken_in_act: int = 0` — pacing gate for opening the lord.
  - Bump `SAVE_VERSION` (§10) and add these to `save_run()` / `load_run()`.
- **`EncounterDB.gd`**: add a `"faction"` key to every entry; extend `get_ids_for(act, type)` → `get_ids_for(act, type, faction := "")` (back-compatible default).

### Phase 1 — Rival selection at run start
- **`RunState.start_new_run(hero_id, …)`**: after the hero is set, build the rival pool = `HERO_ORDER` minus `current_hero_id`; shuffle with `run_seed`; first 3 → `rival_lords`, 4th → `finale_rival`; derive `act_faction`. (Open Decision #4 — if player-chosen order, defer assignment to act start instead.)

### Phase 2 — Shrink & faction-tag the act map (MVP map = reskinned existing engine)
This is the **minimal-rewrite** path: keep the proven `map_data` model (acts → rows → node dicts) and generator, but shrink and retheme.
- **`RunState.gd` map constants**: introduce per-kingdom sizing — e.g. `MAP_HEIGHT` 15 → ~8, `REST_ROW`/`BOSS_ROW` adjusted, `NUM_PATHS` tuned for a tight kingdom. (Directly attacks "takes forever.")
- **`_assign_encounters(grid, act, rng)`**: pull from `EncounterDB.get_ids_for(act, "combat", act_faction[act])` (and `"elite"`) so every hold in the kingdom is that faction. The boss node's `encounter_id` = the rival lord boss for `rival_lords[act]`.
- **`_pick_room_type` / `_assign_node_types`**: retheme node types as **holds** (combat = "garrison", elite = "stronghold"), keep shop/rest/event/treasure as kingdom locations. Add the new **recruit** type here (§Phase 4).
- **Pacing gate**: gate the boss node so it opens after `holds_broken_in_act >= N` (or always-open but scaled if rushed — Open Decision #5). Increment `holds_broken_in_act` in `visit_node` when a garrison/stronghold is cleared.

### Phase 2.5 — Terrain-weighted routes ("the map should matter") — addendum 2026-06-10
User direction: route choice should have mechanical weight, not just length. The Sicily proto (`scripts/scenes/MapProto.gd`) already computes everything needed per cell/edge — biome, elevation, river crossings — so terrain tags can be *derived*, not hand-authored.
- **Tag each road edge** with the dominant terrain it crosses: `meadow / woods / pass / ash` (+ `bridge` flag where a road crosses a river). In the MVP (no territorial map yet) assign tags at map-gen per row band instead — same field, cheaper source: add `terrain: String` to the node dict next to `mutator_id`.
- **Tags weight what you meet.** Encounter roll gains a terrain bias (`get_ids_for(act, type, faction)` keeps working; add an optional `terrain_bias` that re-weights the shuffled pool): woods → ambush kits (Swift/Ranged), pass → elite-lean + Armored, ash (boss approach) → Doom/burn kits, meadow → lighter fights + supply events. `bridge` edges roll a crossing event (toll, ambush, washed-out detour).
- **Tags flavour what you gain.** Recruit/draft pools and event tables lean by terrain (woods → beasts/rangers, ash → fire, meadow → soldiery). Keep it a *weighting*, not new content tiers — the faction × terrain matrix must stay small.
- **The payoff**: the coast road is long but gentle; the mountain pass is short but elite-hard; the ash approach is always brutal. Geography becomes the difficulty/reward dial the player reads at a glance — which is exactly what makes the §12 territorial graph worth building (multiple routes only matter if routes differ).
- **Cost**: one string field per node/edge + a re-weight hook in `_assign_encounters` + event-table filter. No save-schema pain beyond the version bump already planned in §10.

### Phase 3 — Rival-as-boss wiring & the finale
- **`EncounterDB.BOSS_PHASES`**: author 5 rival-lord boss kits (one per hero) + the finale amalgam(s).
- **`RunState.advance_act()` / `is_final_boss()`**: after the act-3 boss falls, route to the **finale** instead of victory. Either (a) append a 4th single-node "throne" map, or (b) trigger the finale scene directly. The finale encounter = `amalgam_<finale_rival>`, its phases seeded by `rival_lords` (the three you beat).
- **`Combat.gd`**: the boss/phase system already supports multi-phase via `BOSS_PHASES`; the amalgam reuses it. Pass the "fallen three" so phases can be themed (full version) or use pre-authored phases (MVP).

### Phase 4 — Decouple recruitment from combat
- **`Combat.gd`**: on victory, stop routing card rewards. Grant gold/relic inline or via a slimmed reward screen, then return to map. (`REWARD_SCENE` constant stays but its card path is bypassed for normal fights.)
- **`Reward.gd`**: strip/curate the card-pick UI (`_pick_card`) out of the post-combat flow; keep `_pick_relic` / gold / `_skip_for_gold` / `_go_to_map`. Repurpose as a light "spoils" screen.
- **New `recruit.tscn` + `scripts/scenes/Recruit.gd`** (or extend `Shop.gd`'s card-buy UI): a curated **1-of-3 paid draft**. Add a `"recruit"` node type to the map (1–2 per kingdom) and route it like Shop in the scene-flow.
- **Economy pass**: bump combat gold (`roll_gold_reward`) to offset the lost free card; price recruitment so deck-growth pace lands where we want (slightly leaner than today).

### Phase 5 — Faction content
- **Faction-mapping worksheet**: tag all 26 existing encounters; produce the gap list.
- **Author gap encounters** per faction (shared card pool, dressed in the element).
- **Author the 5 rival-lord boss kits** + finale phases.
- **Implement the new keywords** `overrun`, `formation`, and the `tithe`/`foresight` helpers (KeywordEffects + dispatchers + Card2D display + COPY_STYLE-compliant text). Everflame's Fuse reuses live Doom/Rampage/Lifelink.

### Phase 6 — Presentation & narrative
- **`MapView.gd`**: faction-skin the chart — the act banner becomes the **rival lord's banner** (`_build_act_banner` / `_add_boss_banner`), holds get faction-coloured tokens (`_draw_token` / `_icon_tex`), the legend reflects kingdom locations (`_build_legend_strip`). MVP keeps the vertical-scroll chart; the **territorial-graph** map is the §12 stretch.
- **Hero-pick screen**: show "your rivals" / stakes. **Boss intros & barks**: one or two lines each, threaded so the story *shows up* in play (per `COPY_STYLE.md`).

### Phase 7 — Balance & playtest
- Tune the **matchup matrix** (each hero playable AND as a boss vs. any of the other 4 — ~20 cells).
- Tune **boss scaling** by act (a rival faced in act 1 is weaker than the same rival in act 3).
- Tune the **economy** (gold ⇄ recruitment) and the **hold-count gate**.
- Tune the **finale**.

---

## 10. Save / migration
- The `map_data` node schema and `RunState` fields change → **bump `SAVE_VERSION`** (currently `1`).
- In-progress saves from the old structure are incompatible. Acceptable for a roguelike: on version mismatch, invalidate the in-progress slot with a one-line notice (don't attempt a structural migration). Meta progress (`MetaState` win/loss) is unaffected.

---

## 11. Risks & open questions
- **Matchup balance is the real cost.** 5 heroes, each must work as a deck *and* a boss vs. any of 4 others. The map/flow code is the easy part; faction content + balance is the work. Mitigation: a lot already exists in EncounterDB; tag don't rewrite.
- **Boss scaling.** Variable route length means the rival lord must scale to "how prepared are you," or rushing is intentional hard-mode. Decide the scaling curve in Phase 7.
- **Economy.** Decoupling moves a major power source (cards) behind a spend; mis-tune and players arrive at the boss under/over-powered. Tune recruit pricing + combat gold together.
- **Scope.** This is weeks, not days. Ship the **MVP cut** (§below) first; treat the territorial-graph map, player-chosen rival order, procedural finale phases, and the two new keywords as fast-follows.

---

## 12. MVP cut vs. full vision
**MVP (proves the loop on existing code):**
1. `faction` tag on encounters + `get_ids_for` filter (Phase 0).
2. Rival selection at run start, seeded order (Phase 1).
3. Shortened, faction-tagged acts on the existing map engine; rival-as-boss (Phases 2–3).
4. Decoupled rewards: combat → gold/relic; 1 recruit node/act with a curated paid draft (Phase 4).
5. Five rival-lord boss kits + a pre-authored 3-phase amalgam finale (Phases 3, 5).
6. Light MapView faction-skin + boss intros (Phase 6).

**Fast-follows (the full vision):**
- The **territorial-graph** map (boss visible from the start, multiple routes, "open" feel) replacing the vertical scroll.
- **Player-chosen** rival order each act (the macro agency dial).
- **Procedural** amalgam — phases assembled from the actual three you beat.
- The two **new keywords** (`overrun`, `formation`) and the `tithe`/`foresight` formalizations.
- A new **renown** currency for recruitment (if we go beyond gold).

---

## 13. Open decisions (need your call before/while building)
1. **The ending:** a true escape (a mountaintop to chase) **or** the eternal cycle (winning makes you the next thing on the throne — darker, very roguelike)?
2. **Recruit currency:** plain **gold**, or a new **renown** earned by conquering?
3. **Hold granularity:** every hold = one fight (snappy), or do **capital** holds become 2-fight mini-sieges?
4. **Rival order:** **player-chosen** each act, or **seeded** at run start?
5. **Boss gate:** lord opens only after **N holds broken** (forces some preparation), or **always open** but **scaled** when rushed (max freedom)?
6. **Map shape for v1:** reskin the **existing vertical map** (MVP, fast) or jump straight to the **territorial graph** (bigger, "open" feel)?
7. **Faction names:** lock the working names (Grasswake / Last Wall / Owed / Lanternhall / Everflame) or keep iterating?
8. **Recruit cost model (Inscryption question):** free 1-of-3 pick at recruit nodes (Inscryption-style — the node itself is the cost, you spent a map move) or a **paid draft** (gold/renown, ties into #2)? Free keeps deck growth map-paced; paid couples it to the fight economy.
9. **Terrain weight depth (Phase 2.5):** flavour-only (encounter/event re-weighting) or full stat modifiers (e.g. ash fights start you at -2 HP, pass fights give enemies +1 ATK)? Flavour-only is safer for balance; modifiers make the map *loudly* matter.

---

## 14. First three concrete steps when we say "go"
1. **Faction-mapping worksheet** — tag all 26 EncounterDB fights to factions; produce the gap list (pure data, no risk).
2. **Phase 0–1 scaffolding** — add the RunState fields + `faction` tag + rival selection; parse-check.
3. **Render a mockup** — a faction-skinned, shortened act map through the screenshot probe, so you react to real pixels before we commit the live flow.

*(These map cleanly onto the harness task system; say the word and I'll convert the phases into tracked tasks.)*

---

## 15. Pre-build pass (2026-06-10) — PATH B PICKED; recommended calls & authoring rules
**The user picked Path B: this redesign ships in 1.0** (sequence M0 ✓ → trimmed M1 → M3 → M4 → M2 → M5 → launch). The calls below were *recommended* in-session; **build has not started — get the user's go / adjustments on these, then execute §15.3.** (Ending #1 and rival order #4 are the most taste-driven — confirm those two especially.)

### 15.1 Recommended §13 calls (proposed, not yet confirmed)
1. **Ending:** the eternal cycle — winning makes you the next thing on the throne; hold "true escape" as a hidden ascension capstone later (the StS act-4 move).
2.+8. **Recruit: free 1-of-3** (Inscryption model — the node visit is the cost). A *paid* draft would collide with Shop, which already sells cards for gold: Shop = paid broad stock, Recruit = free curated faction draft. **No new currency** for MVP.
3. **Holds: one fight each**; the rival lord is the only multi-phase siege (fights end round 2–3 — a 2-fight siege would just read as two fights).
4. **Rival order: player-chosen at each act transition** (one small UI screen; the slice may run seeded until it exists).
5. **Boss gate:** keep **visible from the start** (the Sicily plate already shows it), **locked until 2–3 holds broken**. "Always-open but scaled" deferred to an ascension modifier.
6. **Map: the live Sicily plate IS the territorial map** — provinces become kingdoms, the per-act leg flies the army standard to the chosen rival's seat, the keep plaque takes the rival's name, the political wash takes their colour. No new map engine; what remains is faction-skinning.
7. **Names: lock** Grasswake / Last Wall / Owed / Lanternhall / Everflame.
9. **Terrain: flavour-only** weighting for 1.0 (encounter/event/recruit pools by meadow/woods/pass/ash); stat modifiers later as an ascension layer.

### 15.2 Authoring rules from live-build findings (the spec above predates these)
- **Engines must fire by round 2 in normal holds.** Live normal fights last 2–3 rounds and snowball; Formation/Tithe/Fuse as written would never show themselves. In normal holds: Formation pairs arrive pre-formed (opening formations are live), Tithe enemies enter with corpses already banked, Fuse dooms run 1–2. True slow-burn versions only for strongholds and rival lords.
- **Per-faction reinforcement wave schedules** replace the uniform 1/round drip (the last structural samey-ness lever): Grasswake floods early then runs dry; Last Wall trickles forever, every body tough; the Owed re-raise from their own dead; Lanternhall barely reinforces (casts instead); Everflame escalates as dooms tick down.
- **Legibility is half the faction work** (playtest finding: samey-ness is presentation — players ignore effects and charge). Per-faction combat mood presets (mood system is per-act today), a visible Tithe corpse-counter, Overrun empty-lane warning glow, the quick-intro banner naming the faction engine.
- **The bill is smaller than spec'd:** 41 encounters exist (not 26), ~80% pre-mappable; the Everflame engine is fully live (Kindler Doom/Rampage/Lifelink); scry half-exists; act sizing + the territorial map already shipped. Rival-lord portraits: redress existing hero art before commissioning. Net-new work concentrates in Lanternhall content, 5 boss kits + amalgams, `overrun`/`formation`, and the matchup matrix.

### 15.3 Amended build order (replaces §14 sequencing)
1. ~~**Faction worksheet**~~ **DONE 2026-06-10 → [`FACTION_WORKSHEET.md`](FACTION_WORKSHEET.md)** — all **40** live encounters tagged (the "41" count was off by one: A1 13 / A2 13 / A3 14), coverage matrix + gap list included. Net-new estimate drops to ~8–12 encounters after re-leveling existing fights via their deck variants; Owed is the donor faction, Lanternhall still the front-load.
2. **Phase 0–1 scaffolding** — RunState fields, `faction` tag, `get_ids_for` filter, rival selection; **SAVE_VERSION 2→3**.
3. **One-matchup vertical slice** — invade **the Last Wall** in act 1 (wall/armor is the best-stocked theme), seeded order, one free recruit node, one pre-authored amalgam: a full run end-to-end **before** authoring the ~13–17 gap encounters.
4. **Telemetry day one** — extend `user://runs.csv` (`RunState._append_run_log`) with rival/faction columns in Phase 1; every dev run feeds the matchup matrix (the project's dominant cost).
5. **No Combat.gd pre-refactor** — Phases 0–2 barely touch it; extract the reward-flow seam only when Phase 4 actually hurts.
