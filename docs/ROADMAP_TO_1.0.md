# Burning Meadow — Roadmap to 1.0
**The master production plan.** Grounded in a full read-only audit of the live build (content, art, audio, systems, release, legal), 2026-06.
Companion doc: [`CONQUEST_REDESIGN.md`](CONQUEST_REDESIGN.md) — the "Successor Wars" redesign, treated here as one (large, optional) workstream.

---

## Status — live progress log

**As of this planning session:**
- ✅ **M0 (ship-hygiene) COMPLETE** — debug prints gated behind `DEBUG_PACING` (Combat.gd); CC-BY/license attributions fixed in the in-game Credits + `CREDITS.md`; non-PD **Beksiński** PD-claim removed; `scripts/_shot.gd` deleted; 3 blank cards fixed; `README.md` rewritten; CLAUDE.md counts corrected. All parse-checked clean. (Blockers **B1–B8** in §2 are done.)
- 🎨 **Open art follow-ups** (not blocking; fit the one-at-a-time PD/painterly pipeline): (1) visually confirm no card portrait is a non-PD work (Beksiński *credit* removed, *art* unverified); (2) give `plague_bell` its own painterly icon (currently borrows `mass_grave`'s); (3) replace corrupt `assets/creatures/pikeman.png` (masked by a `shieldbearer` alias).
- ⛔ **DECISION REQUIRED before any M1+ work** — the **Path A / B / C** fork (§0 + §6), plus meta-progression scope and platform targets. **Nothing past M0 should begin until the user picks a path.**
- 🧭 **Signal (2026-06-10):** unprompted, the user described wanting (a) routes where the map/terrain mechanically matters, (b) fighting **the lords you didn't pick** as bosses, (c) **card picking outside combat, Inscryption-style** — (b) and (c) are exactly CONQUEST Phases 1/3/4; (a) is now specced as **CONQUEST Phase 2.5 (terrain-weighted routes)** + Open Decisions #8 (free vs paid recruit) and #9 (terrain weight depth). The user is converging on the redesign vision — but the formal Path A/B/C pick has still not been made.
- 🛠️ **2026-06-10 session (verified by screenshot; committed in `5417d32`):** three combat-legibility fixes — battlefield stat orbs 38px with 18px white outlined numerals (`Card2D._build_compact_layout`), enemy intent badges 11px label → 15px dark pill (`Combat._update_intent_display`), relic chips: tier halo 0.55→0.30 + painted icons overscanned 16% to crop their baked canvas glow (`GameTheme.make_relic_chip`).
- 🗺️ **Strategy-map mockup v6 — REAL GEOGRAPHY (Sicily) + carved roads (PORTED LIVE — see next entry):** v5's A/B experiment proved **node count is the legibility dial** (38-site lattice = nonsense; **11–15 sites = campaign map** — validates CONQUEST Phase-2 act sizing with pixels; probe generates its own 8-row act, **game constants untouched**). v6 (user-directed, same session) swaps the procedural island for **real local geography**: hand-traced Sicily coastline (lon/lat → px), **Etna as the boss seat** (cone + glowing caldera + lava threads + smoke plume; keep at its foot; scorch = lava country), Strait of Messina + mainland sliver, Aeolian/Egadi isles, anchored massifs (north-coast chain carve-shielded so roads read as passes). **Roads are carved INTO the map** (incised groove: NW rim shadow / SE lit rim / dark channel / packed-earth floor / state tint riding in the cut). Antique-chart furniture per reference research (CK3 paper-map dev diaries, real chart conventions): **waterline rings** fading seaward, sparse wave ticks, harbour marks (Salt Haven / North Haven / The Old City), cartouche double-rule + finials, sea labels (The Upper/Middle Sea, The Narrow Strait, The Mainland), title "ACT I · THE BURNING ISLE". Node placement: march spine camp→Etna with min-spacing relaxation (46px) + island polygon clamp. **v6.1 detail pass** (research: Lehmann hachures + chart conventions): finer mesh (CELL 20), hachure slope strokes, tilled-field furrows along roads, ocean depth-banding + shoal stipple + water-only graticule, double-ruled coast, denser shadowed forests, lava-crack fissures, river tributaries, harbour town clusters. v5 procedural renderer preserved at `tools/screenshot/MapProto_v5_procedural.gd.bak`. Renders: `map_proto.png` (fresh) / `map_proto_midrun.png`; v4/v5 evidence chain kept. Probe overwrites save slot 0 (`run_N.save.bak_20260610` backups exist).

- ✅ **2026-06-10 (later session): Sicily map PORTED LIVE — explicit user go on this piece of the redesign.** The user approved v6 and directed the port ("porting the Sicily map into the live game"); **the act shrink ships with it** because the validated look requires 11–15 sites. This is a **partial, user-approved pull-forward of CONQUEST Phase 2 (act sizing) + §12 (territorial map)** — the formal Path A/B/C pick is *still* open for everything else. What landed (committed in `5417d32` on `feature/visual-polish-and-content`, with `SAVE_VERSION` bumped to 2 to retire pre-shrink saves and an act-3 render added to the probe): `scripts/scenes/MapTerrain.gd` (new base class — the full v6.1 Sicily plate: coast/massifs/Etna keep, carved roads, political layer, antique-chart furniture, per-act dressing); `scripts/scenes/MapView.gd` rewritten to extend it (site hover/click buttons + tooltips with encounter/mutator intel, node→scene flow, top HUD, deck viewer, meta-relic pickers, save checkpoint — old parchment chart preserved at `tools/screenshot/MapView_parchment.gd.bak`); `scenes/map.tscn` slimmed to script-only Control (no Background — the plate IS the background); `RunState.gd` map constants 15→**8 rows** (`BOSS_ROW 7`, `REST_ROW 6`, `NUM_PATHS 3`, `MIN_ELITE_ROW 3`) + **acceptance loop enforcing 11–15 sites/act** (deterministic per-act sub-seeds so attempt count doesn't shift later acts) + 3× path-merge bias (trunk-road look). **Verified by rendering the real scene** in three states via `tools/screenshot/_probe_map_live.gd` (fresh act-1 / 3 marches in / act-2): provinces counter ticks 0/13→3/13, claimed wash + pennants render, act 2 re-dresses (browner plate, The Collector boss) and resets the counter. Fix found by the probe: right HUD (potions/deck) was hardcoded at x=1640 — **off-canvas under `canvas_items` stretch (coordinate space = 1600×900 project viewport, not window pixels)**; now anchored off `size.x`. Renders: `map_live_fresh.png` / `map_live.png` / `map_live_act2.png`.

- ✨ **2026-06-10 (later): campaign-map polish pass** (verified by 5-state probe renders incl. a mid-march frame): (1) **animated overlay** (`MapView.MapPulseOverlay`) — breathing amber rings on reachable sites (crimson ring on the keep when the boss road opens), a **distinct army standard** (swallow-tail banner, ground ring, gentle sway) at the player's position replacing the old static pennant that was near-identical to conquered-site pennants, Etna ember drift, and a **0.55s commit march**: the standard walks the carved road to the chosen site before the scene fade. The 25k-primitive plate stays static; the overlay redraws ~a dozen primitives per frame. (2) **Parchment tooltips** (`MapTipButton` + `_build_map_tooltip`: gilt name line + dim body on dark ink) replacing the stock gray box on site/potion/deck buttons. (3) **Per-act cartouche subtitle** — THE FIRST / SECOND / LAST MARCH — so the three sieges of the keep read as three campaigns. (4) **Legend** now lists only site types present on the act, seated on a faint band. (5) Bugfix: treasure sites rendered an icon-less chip (`_node_icon` was missing the `tex_node_treasure` case). Remaining map ideas parked: per-act camp/keep anchor sweep (real fix for the same-keep problem, CONQUEST-adjacent), controller-friendly site intel (tooltips are hover-only).
- 🏰 **2026-06-10 (later): per-act campaign legs — the same-keep problem is fixed.** The war now sweeps the island one leg per act: **west landing → a keep in the northern passes (act 1) → down through the southern grain country (act 2) → up into the lava country at Etna's foot (act 3)**, with each act's camp pitched exactly where the last keep fell (`keep_lls` anchors in `MapTerrain._read_run_map`, keeps clamped 34px inland so the boss pin can't land in surf). The march spine is now a camp→keep **vector** (legs aren't pure west→east): sites advance along it, lanes fan perpendicular via `_perp_extent` (replaces `_island_y_span`), along-spine jitter scales with the row step so rows can't visually reorder on short legs. Two couplings found and fixed: **scorch was centered on `_boss_pos`** — under the sweep it would have burned a mid-island keep while Etna sat clean; now centered on `_etna_peak` (still grows 175→205→235 by act, so the burn spreads as you approach it). And **provinces now cap at ~240px** from the nearest site, so the political layer hugs the act's corridor and the rest of the island reads as wilds (`_draw_political` already skipped `-1` cells). Verified by 5-state renders: act 2's "YOUR CAMP" sits exactly on act 1's keep site; act 3 marches into the scorch. Etna is visible as looming geography in every act and only becomes the destination in the last.

> This doc + `CONQUEST_REDESIGN.md` + `COPY_STYLE.md` are the **live source of truth** — trust them over CLAUDE.md / git history, which have drifted before.

---

## 0. Executive summary

**The game is much closer to shippable than its own docs suggest.** The audit found a feature-complete, ship-shaped build: full front-end (hero select, daily, custom seed, ascension 0–5, 3-slot **versioned saves with mid-run resume**, comprehensive settings, collection, credits), broad high-craft content (154 cards, ~130 relics, 41 encounters, 41 events, 5 heroes, 13 potions, 22 mutators — **no stubs**), and an unusually complete **audio system** and **save system**.

The true blockers are small and mostly hygiene. The real distance to a *polished* 1.0 is **breadth and polish** — art coverage, audio breadth, onboarding, and legal compliance — plus, optionally, the **Successor Wars redesign** (a multi-week epic that is the game's differentiator but is **entirely unbuilt**, sitting at pre-Phase-0).

### The central strategic fork (decide this first)
Because the current build is nearly shippable on its existing Slay-the-Spire structure, you have a real choice the audit makes informed:

- **Path A — Ship 1.0 on the current structure, redesign later.** Fix blockers → polish breadth → onboarding → launch. The conquest redesign becomes a marquee **1.5 / 2.0 update**. *Lowest risk, fastest to market, validates the game and funds the redesign.*
- **Path B — Build the redesign into 1.0.** Don't launch until the conquest map ships. *Launches with the differentiated vision, but adds months and the full faction-balance cost up front.*
- **Path C — Hybrid.** Ship a **demo / Early Access** on the current structure now; build the redesign during EA with player feedback.

**Recommendation:** do **M0 (ship-hygiene) immediately regardless of path** — those fixes are required for any public build. Then pick A/B/C. My lean is **C, trending A**: the game is good *now*; the redesign is worth doing but shouldn't gate a first public showing.

---

## 1. Current-state snapshot (corrected, grounded)

> Multiple source docs are **stale** — CLAUDE.md, README.md, and ASSET_REFERENCE.md all undercount. Trust this table (from the live code) over them.

| Domain | Live count / state | Ship-readiness |
|---|---|---|
| **Cards** | 154 in `CARD_POOL` (~95 creature / ~57 spell) + 18 enemy-only; every id has a hand-crafted "+" UPGRADE | ~80% — strong; weak 20% is spell-cluster bloat + vanilla bodies |
| **Relics** | ~130 (9 starting / ~85 combat / 8 utility / ~21 boss); **zero orphaned** (all `_has_relic` sites resolve) | ~95% — strongest area |
| **Keywords** | 24 defined, 21 fully dispatched; `structure` is a stub; `slay`/`adjacent` are inline/doc | ~92% |
| **Encounters** | 41 (A1 13 / A2 13 / A3 15 → 25 combat / 8 elite / 8 boss); 7 multi-phase bosses; deck-variants for replay | High craft; **no faction tags / no rival-lord kits** |
| **Events** | 41 (9 state-gated, recurring NPC chains, multi-stage branching) | High craft, no stubs |
| **Heroes / Potions / Mutators** | 5 / 13 / 22 — all complete | Done (the 5 heroes *are* the redesign's claimant roster) |
| **Creature art** | 90 PNG portraits + ~210-entry alias map; only 3 true gaps | Effective coverage high; leans hard on aliasing |
| **Spell art** | 60 PNG (~98%); **no alias fallback** (new spells must ship art) | 1 gap (`plague_bell`) |
| **Event art** | 35 / 47 (~74%) via Midjourney pipeline | **Largest content-art gap** (~12 missing) |
| **Boss splashes** | 6 named of 16; 10 use generic `boss_act<N>.png` | Gap (10 named splashes) |
| **VFX** | **None as assets** — all code-driven (shake + CPUParticles) | Biggest *juice* gap |
| **Audio** | System ship-grade (crossfade, per-act pools, buses, sliders, focus-mute); 14 SFX (placeholder UI-pack), 16 music tracks | Plumbing done; **content/mix breadth** is the gap |
| **Systems** | Scene flow, hero select, ascension, daily/seed, 3-slot versioned saves+resume, settings, collection, mutators — **all done** | Feature-complete |
| **Onboarding** | 5 reactive in-combat tips; **no front-loaded How-to-Play / glossary** | Main UX hole |
| **Meta-progression** | runs/wins/losses/fastest + ascension unlock; **no card/relic/hero unlocks, no achievements** | Scope decision |
| **Platform/release** | minimal `project.godot`; **no icon, splash, logo, input map, export presets, Steam SDK** | Not started |
| **Legal/credits** | in-game Credits exists but has **CC-BY attribution gaps + a non-PD artist** | **Compliance blockers** |

---

## 2. Ship-blockers (must fix before ANY public build)
All are Small effort; several are *legal* and non-negotiable.

| # | Blocker | Fix | Effort | Source |
|---|---|---|---|---|
| B1 | **Debug `print` instrumentation in `Combat.gd`** (`[PACING]`/`[COMBAT]`, 6 sites + 2 vars: lines 136, 1016, 1285, 2105, 6214, 6232, 6365) — ungated, spams stdout every round/attack | delete or wrap in `const DEBUG_PACING := false` / `OS.is_debug_build()` | S | systems |
| B2 | **Uncredited CC-BY art = license violation** — painterly **spell icons (J.W. Bjerk / "eleazzaar", CC-BY 3.0)** ship with **no attribution anywhere** | add to in-game `Credits.gd` + `CREDITS.md` | S | legal |
| B3 | **CC-BY packs not in the in-game Credits screen** (the binding surface) — **game-icons.net** (Lorc/Delapouite/willdabeast/sbed) + **pbmojART** | add both to `Credits.gd` | S | legal |
| B4 | **Non-PD artist credited as public-domain** — **Beksiński** (d. 2005, copyrighted ~until 2075) listed among "PD masters" → copyright risk; other named artists need a PD check | remove/replace Beksiński art+credit; verify each PD claim | S–M | legal |
| B5 | **`scripts/_shot.gd`** temporary screenshot harness (self-labeled "remove before ship") | delete | S | systems |
| B6 | **3 cards render a blank rectangle** (`tallow_doll`, `the_glutton`, `plague_bell` — no art, no alias) + corrupt **`pikeman.png`** | source 3 PD arts + 1 replacement | S | art |
| B7 | **`README.md` describes the abandoned 3D prototype** (launch/GitHub embarrassment); `ASSET_REFERENCE.md` + CLAUDE.md counts stale | rewrite README; refresh/retire stale docs | S | legal/systems |
| B8 | **Font credit drift** — Credits lists "Pirata One"; build uses **Lilita One** (uncredited) | fix `Credits.gd` / `CREDITS.md` | S | legal |

**M0 = all of B1–B8.** A few days of work; unblocks any demo/EA/store build.

---

## 3. Workstreams to a polished 1.0
Each: current state → definition of done → gaps → effort. (These are the "1.0 without the redesign" body of work; the redesign is §3-H.)

### 3-A. Card & mechanics content
- **State:** 154 cards, ~130 relics (near-complete), 24 keywords (21 live).
- **DoD:** no duplicative dead-weight cards; every keyword either implemented or removed; counts documented.
- **Gaps:** consolidate/differentiate the **board-wipe cluster (6)** and **mass-ATK-buff cluster (~5)** and redundant face-burns; give ~8 vanilla commons a small rider; **decide `structure`** (implement for boss charge-triggers or cut); cut/fix strictly-worse `scrap`; reconcile legacy `ENEMY_POOL` (18) vs EncounterDB into one tuned enemy source.
- **Effort:** M.

### 3-B. Run content (encounters & events)
- **State:** 41 encounters (high craft), 41 events (well-gated). Strongest design area.
- **DoD:** balanced boss distribution per act; events all art-backed (see 3-C).
- **Gaps:** **Act-1 boss thinness** (2 vs 3 elsewhere) — add 1; otherwise solid for the *current* structure. (Faction/rival authoring lives in 3-H.)
- **Effort:** S (current structure).

### 3-C. Art
- **State:** creatures effectively covered (heavy aliasing), spells ~98%, **events 74%**, boss splashes 6/16, **no VFX assets**.
- **DoD:** zero blank-art cards; events ~100%; named splashes for marquee bosses/elites; a baseline impact/cast/death VFX set.
- **Gaps:** **12 event arts** (Midjourney) [M] · **10 named boss/elite splashes** (PD masters) [M–L] · promote ~5 high-frequency alias-only creatures to own portraits [M] · prune `assets/frames/` dev cruft + `painterly-*/__MACOSX/` junk [S] · **VFX asset library** — the single biggest *perceived-quality* win and directly addresses the "combat feels samey → presentation/legibility" note [L].
- **Sourcing standard:** card/creature/boss = **AAA public-domain masters** (Doré/Goya/Velázquez/Schongauer/Vrubel/Fuseli), one at a time, rename cards to fit great art; events = **Midjourney** at `assets/events/<key>.png`; icons = game-icons.net.
- **Effort:** M–L.

### 3-D. Audio
- **State:** system is ship-grade; **14 SFX (placeholder UI-pack)**, 16 music tracks (per-act/node), full mixer + sliders + focus-mute.
- **DoD:** thematic combat SFX; ~40 cue coverage; ≥2 variants for repeated-scene music; a loudness + ducking pass.
- **Gaps:** swap placeholder combat SFX (hit/death/spell) for thematic sources [M] · add the **one dangling cue** `upgrade_confirm` + ~10 missing UI/keyword cues (error, hover, potion, relic, summon, sacrifice, Doom-tick) [M] · 2nd music variant for shop/map/event/rest (single-track fatigue) [M] · **music ducking** under stingers + loudness-normalize [M] · re-encode the large WAV tracks + 10 MB `fire.wav` to OGG [S].
- **Effort:** M (per-faction music is in 3-H).

### 3-E. Systems & UX
- **State:** feature-complete; saves robust; only reactive tutorial.
- **DoD:** a new player can learn the board/rules without trial-and-error; meta scope decided.
- **Gaps:** **front-loaded How-to-Play + always-available keyword/board glossary** (the 4×4 board, lanes, front/back, Swift pre-phase, win condition) — host it on the Collection screen [M] · **meta-progression scope decision** — ship ascension-only, or add card/relic/hero unlocks + achievements to `MetaState` [S–L, scope call].
- **Effort:** M.

### 3-F. Platform & release engineering
- **State:** not started — minimal `project.godot`.
- **DoD:** branded, exportable, controller-capable build with a store presence.
- **Gaps:** **app icon + boot splash + game logo/wordmark** and wire into `project.godot` [M] · **`export_presets.cfg`** (Windows + Linux/Deck) [M] · **InputMap + controller support + key rebinding** (required for Steam Deck Verified / "Full Controller Support"; game is mouse-only today) [L] · **Steamworks** (GodotSteam) for achievements + **Steam Cloud mapping** of `user://*.save` + overlay [L] · age-rating/content-descriptor prep (horror/gore/sacrifice themes) [S, external].
- **Note:** mid-run save/resume already exists (3-slot versioned) — only *Cloud* mapping is missing.
- **Effort:** L.

### 3-G. Legal & docs housekeeping (beyond the M0 blockers)
- **DoD:** every shipped asset correctly attributed; a consolidated license file; docs reflect reality.
- **Gaps:** ship a **`THIRD_PARTY_LICENSES.txt`** bundling CC-BY/OFL/CC0 credits [S] · finish PD-artist verification [M] · refresh **CLAUDE.md** (Combat.gd is ~11.8k not 4.5k lines; alias map is `CardArtAliases.gd` not `GameTheme.gd:1068`; relic/keyword/card/encounter/event counts) [S].
- **Effort:** S–M.

### 3-H. The Successor Wars redesign (the optional epic)
Full spec in [`CONQUEST_REDESIGN.md`](CONQUEST_REDESIGN.md). **Status: pre-Phase-0 — nothing built.** The 5-hero roster exists; everything else (faction tags, rival-lord bosses, amalgam, conquest map, recruitment decoupling, the 2 new keywords) does not.
- **Code (per the spec's phases):** RunState fields + `faction` tag + `get_ids_for` filter; shortened faction-tagged act map; rival-as-boss + finale routing; decoupled rewards + Recruit node; new keywords `overrun`/`formation` + `tithe`/`foresight` helpers (note: **`foresight`/scry half-exists** — Lookout scry, `look_top`, `frozen_eye`, Hexblade spell-scaling — so it's consolidation, not from-scratch).
- **Content authoring (the bulk):** **~13–17 new "hold" encounters** to make every faction fill every act — front-loading **Lanternhall (the worst-served: 0 Act-1 holds, no boss, only anti-spell mirrors) and Everflame**; **5 rival-lord boss kits + 5 pre-authored amalgam finales (~10 boss-tier defs)**; **~6–10 new Lanternhall creatures** (the one faction genuinely short on bodies).
- **Art:** **5 faction visual identities** (banner/tokens/legend) + **5 rival-lord portraits** + amalgam splash + conquest-map art + 2 keyword icons.
- **Audio:** re-tag music **per-faction** (currently per-act) + 5 faction themes + 5 boss themes + finale.
- **Balance:** the **~20-cell matchup matrix** (each hero playable *and* a boss vs. any other) — the real multi-week cost the spec's own §11 flags.
- **Effort:** **XL** (weeks–months). Ship via the spec's **MVP cut** first.

---

## 4. Milestones & sequencing

| Milestone | Contents | Gate / "done when" | Rough size |
|---|---|---|---|
| **M0 — Ship hygiene** | All blockers B1–B8 (§2) | no debug spam, legal-clean, no blank cards, README real | days |
| **M1 — Polish the game you have** | 3-A content polish, 3-C events+splashes+VFX baseline, 3-D audio breadth+mix, 3-E onboarding/glossary, 3-G docs | a stranger can learn and finish a satisfying run on the current structure | 3–6 wks |
| **M2 — Platform & store readiness** | 3-F (icon/splash/logo, export presets, controller), Steam page, capsule, screenshots, trailer | a wishlist-able store page + a controllable, exportable build | 3–6 wks (parallel w/ M1) |
| **M3 — Redesign vertical slice** | `CONQUEST_REDESIGN` MVP: faction tags, rival selection, shortened faction acts, rival-as-boss, decoupled rewards + 1 recruit node, 5 boss kits, pre-authored amalgam, map reskin | one full run through the new loop, end to end | 4–8 wks |
| **M4 — Redesign content-complete** | ~13–17 holds, Lanternhall creatures, faction art identities, per-faction music, finale art | every faction fills every act with its own art+music | 6–12 wks |
| **M5 — Beta & balance** | matchup matrix, ascension/economy tuning, QA pass, achievements | tuned, bug-pruned, content-locked | 4–8 wks |
| **1.0 Launch** | marketing beat, demo, day-1 build | — | — |

**Path A (ship first):** M0 → M1 → M2 → **launch 1.0**; M3–M5 become the **2.0 "Successor Wars" update**.
**Path B (redesign in 1.0):** M0 → (M1 trimmed) → M3 → M4 → M2 → M5 → launch.
**Path C (EA):** M0 → M1-lite + M2 → **EA launch** → M3–M5 in public beta.

---

## 5. Risks & dependencies
- **Faction balance is the dominant cost** of the redesign (the ~20-cell matrix + each hero as deck *and* boss). Mitigation: most cards/encounters exist; tag and re-skin before authoring net-new. Lanternhall is the known content hole.
- **Art is the long pole** for both 1.0 polish (events, splashes, VFX) and the redesign (5 identities + 5 lords). PD-master sourcing is one-at-a-time and slow; budget accordingly.
- **`Combat.gd` (11.8k lines)** is a maintainability risk that *compounds* as the redesign piles on — consider extracting the spell-resolver / floop / HUD seams **before** M3, or accept the debt.
- **Doc drift** has already misled (counts off by 2–3×). Refresh CLAUDE.md early (M0/M1) so future work is grounded.
- **Controller + Steamworks** are large, somewhat independent tracks — start early if Steam Deck Verified / achievements matter at launch.

---

## 6. Decision queue (what we need from you)
**Strategic:**
1. **Path A / B / C** — ship 1.0 on the current structure first, or build the redesign in, or Early Access? *(Reshapes the whole timeline.)*
2. **Meta-progression scope** — ascension-only (ship as-is), or add unlocks + achievements?
3. **Platform targets** — Steam Deck Verified + controller + achievements at launch, or post-launch?

**From `CONQUEST_REDESIGN.md` §13 (only bite these when the redesign starts):** ending (true escape vs. eternal cycle); recruit currency (gold vs. renown); hold granularity; rival order (chosen vs. seeded); boss gate (N-holds vs. always-open-scaled); map shape v1 (reskin vs. territorial graph); lock faction names.

---

## 7. Immediate next actions (risk-free, start anytime)
1. **Do M0 now** — the blockers are all Small and several are legal. Biggest bang: B1 (delete debug prints), B2–B4+B8 (credits/license compliance), B6 (3 blank cards), B7 (README).
2. **Refresh CLAUDE.md** with the corrected inventory from §1 so every future task is grounded.
3. **Faction-mapping worksheet** (redesign Phase 0, pure data) — tag the 41 encounters; already ~80% mapped in the audit, just needs committing to the `faction` field.
4. **Pick the path (§6.1)** — everything downstream branches on it.

*Say the word and I'll convert any milestone into tracked tasks and start executing — M0 is the obvious first strike.*
