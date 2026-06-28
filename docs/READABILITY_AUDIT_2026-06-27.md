# Readability & Simplification Audit — 2026-06-27

**STATUS:** Wave 1 (font + contrast) ✅. **Wave 2 (AGGRESSIVE re-pass) ✅ DONE** — Wave 1's
+1–2px bumps were too timid for the 1920×1080 canvas (user: "still too small"), so a 2nd
4-agent audit raised the bar to "couch-legible on 1080p" and pushed explanatory text to
16–22px across ALL screens. Landed this pass (19 files, parse-clean):
- **Shared:** `FONT_BODY 15→16`, `FONT_SUBHEADER 19→20`, `FONT_HEADER 26→28`;
  `make_choice_banner` body 15→17 / title 22→24; `make_relic_card` name→18 / desc 14→16 /
  tile height 150→172 (Shop/Reward/Treasure call sites updated to match). Also
  `project.godot` now sets `window/dpi/allow_hidpi=true` so HiDPI displays stop
  rendering the whole canvas at low-res (a root cause of "everything looks small").
- **Cards:** rules-text ramp 13/12/11 → **17/16/15**, shrink floor **10→14**, art plate
  trimmed 6px to grow the rules box (live `_build_chart_proto` AND baked
  `_build_baked_overlay_layout` paths kept in lock-step); spell footer 12→14;
  **deleted the cryptic RMP/OVR/FRM/LL battlefield text chips** (redundant — all four now
  have SVG icons in the rail).
- **Combat HUD:** every per-turn caption 13→16–18 (INCOMING/NEXT WAVE/NEXT ROUND/COMMAND/
  DECK·DISCARD·EXHAUST/YOU·FOE), `_turn_label` 15→18, intent badge 17→18.
- **Map:** drawn-label floor 13→15, legend/primer/plaque/kingdom/act-line/provinces all
  +2–6px **with real `draw_string_outline` outlines** (were bare); **YOU ARE HERE** plate
  enlarged; **cut 3 unreadable harbour-town labels**.
- **Menu:** hero portraits **un-dimmed** (0.70→0.88 idle) + **box re-aspected 168×210→168×223
  to kill the ~13px face-crop**; run-stats/relic/tagline/how-to-play all bumped.
- **Nodes:** Event outcome 19→22 + flavor 19→17 (fixed the payoff-vs-flavor inversion);
  Wayside/Shop/Collection/GameOver/Settings/all-4-Net status lines bumped.

**Also landed (simplification, beyond the pure font sweep):**
- **How-to-Play overlay dedup DONE** — extracted to `GameTheme.make_how_to_play_overlay()`;
  both `MainMenu._show_how_to_play` and `MapView._show_how_to_play` now call the single
  shared builder and the two duplicate implementations were deleted (the big line drop in
  MapView/MainMenu). Primer copy can no longer drift between the two screens.
- **Combat fight-intro banner trimmed** — General (non-boss) intros no longer stack the
  preamble or a redundant "see the posted edict" line; the rule is shown in the intro only
  when there's no permanent EDICT banner. Bosses still get the full preamble. Cuts the
  routine-fight text wall.
- **End Turn button = raised plate** — the primary per-turn action was frameless gilt text
  that dissolved into the dark board; it now has a real warm-ink plate + gilt rim + shadow,
  24pt Cinzel, pointing-hand cursor. The loudest control on the screen.

**Fake-settings** → verified NOT fake (Color Blind via `GameTheme.cb_color`, Animation Speed
via `_short_pause`). All uncommitted, re-verified parse-clean (combat/main_menu/map/event/shop
opened headless in `--editor`, autoloads present); pending user **visual** verification on a
clean restart — no in-shell rendering/screenshots are possible in the dev shell.

### Deferred-refactor follow-up — 2026-06-28 (DONE, separate commit)

The three "maintainability, not legibility" refactors were done as a behavior-
preserving pass (user chose "safe dedup" for the subjective one). All three are
**no visual change by construction** (identical node trees / inherited-identical
values), so they don't need the visual-verification gate above:
- **Shop tile-type unify** — extracted `GameTheme.make_tile_skeleton` (the empty
  Button + centered inset VBox shared by `make_relic_card` and Shop's
  `_make_service_slot`). Each tile keeps its own styleboxes/content, so
  Reward/Treasure relic tiles are pixel-identical; only the construction is shared.
- **Net deck-builder base class** — new `scripts/scenes/NetDeckBuilder.gd` owns the
  shared palette/scene-constants/sync-flags + the byte-identical `_build_pool_thumb`;
  all four modes (`NetQuick/Constructed/Sealed/Draft`) now `extends` it. Verified:
  parse-clean, `_probe_skirmish`/`_probe_vsbot` pass, and `_probe_netbase` confirms
  all four resolve their inherited members at runtime.
- **Event safe dedup** — extracted `Event._build_event_screen` (the clear→art→title→
  desc→bottom-choices scaffold shared verbatim by the dice / risk-loop / appraisal
  screens). The distinct *interactions* stay bespoke — only the scaffold is shared.
  Verified parse-clean, `_probe_events` clean (33 events / 362 effects / 0 errors),
  and `_probe_eventscaffold` confirms the helper's node tree.
- **Event mini-game full consolidation** = still HELD (forcing the distinct dice /
  risk / picker / appraisal interactions into one layout would flatten variety; not
  a blind sweep — needs visual sign-off).

---
### Wave 1 original notes (superseded by Wave 2 above)

Four parallel agents audited every screen (combat / map+menu / node screens /
cards+meta+multiplayer). This is the consolidated, prioritized plan.

## The one pattern behind everything

The **numbers are loud, the words that explain them are whispers.** Across every
screen the big numerals (HP 40px, Command 37px) are fine, but the **labels,
captions, descriptions, legends, and instructions** — the text that tells the
player what things mean and what to do — are systematically **10–13px and
low-contrast**. That's "the text is too small to see."

Biggest leverage = a few **shared helpers** that bake small text into many screens.

---

## WAVE 1 — cross-cutting + worst offenders (font size + contrast; low risk)

### Shared helpers (fix many screens at once)
- `GameTheme.make_relic_card` desc **12 → 14** (`GameTheme.gd:~1201`) — fixes relic
  rules text on Shop, Reward, Treasure simultaneously.
- `GameTheme.make_choice_banner` desc **13 → 15** + raise disabled-reason contrast
  (`GameTheme.gd:~813/815`) — fixes Rest/Reward banner text + all "why is this locked" lines.

### Cards (`Card2D.gd`)
- Rules-text shrink floor **10 → 12** (`_fit_desc_to_box`, `:~3527`) — the #1 card complaint.
- Spell footer ("TARGET ENEMY"/"EXHAUST") **10 → 12** (`:~4104`).
- Battlefield keyword chips **10 → 12** (`:~1658`); replace cryptic RMP/OVR/FRM later.

### Combat HUD (`Combat.gd`) — the screen the user screenshotted
- `_turn_label` (running "what to do now" line) **12 → 15** + brighter color + outline (`:~11230`).
- Caption cluster **10–11 → 13**: INCOMING (`:10644`), NEXT WAVE (`:3606`), NEXT ROUND
  (`:3653`), COMMAND (`:11454`), pile DECK/DISCARD/EXHAUST (`:11912`, drop letter-spacing),
  YOU/FOE (`:9842`); raise their alpha toward 1.0.
- Enemy intent badge **15 → 17** (`:7458`) so the telegraph reads across the board.
- Posted edict **14 → 15** (`:11258`).

### Map (`MapTerrain.gd` / `MapView.gd`)
- Screen-fixed `_draw_ui` text + **add dark outline** (currently none): legend **12 → 15**
  (`MapTerrain.gd:2592`), reading-primer **11 → 14** (`:2600`), provinces tally **12 → 16**
  (`:2502`), act sub-line **12 → 15** (`:2495`).
- Plate: "YOU ARE HERE" **10 → 13** (`:2433`), keep plaque **10 → 13** (`:2392`),
  kingdom names **13 → 15** + alpha→0.9 (`:1759`), floor all place `_labels` at 13.
- Map tooltip: name **15 → 16**, body **13 → 14** (`MapView.gd:879/890`).

### Menu / hero-select (`MainMenu.gd`)
- Run stats **13 → 15** (`:241`), hero relic desc **11 → 13** (`:947`).
- How-to-Play primer + glossary descriptions **13 → 15** (`MapView.gd:820/846`,
  `MainMenu.gd:1247/1276`).

### Node screens (`Shop.gd` etc.)
- Shop service tiles (potion/removal) **12 → 15** (`Shop.gd:252`) + simplify the text.
- Shop card buy-buttons **13 → 15** (`:125/199`).
- Event outcome ("what you get") line **17 → 19** (`Event.gd:494`) — currently smaller than flavor.

### Meta / multiplayer
- NetConstructed SAVE/LOAD/DEL **12 → 14** + wider (`:184/191/196`).
- Settings GPU readout **12 → 14** brighter (`SettingsOverlay.gd:819`).
- Collection effect text **13 → 14** (`:287`).

---

## WAVE 2 — simplification / restructure (needs sign-off; subjective + visual)

- **Combat fight-intro banner**: trim from up to 7 stacked labels → name + one
  mechanical line (the edict is already posted permanently). (`Combat.gd:~13982-14098`)
- **Map declutter**: cut/demote the 10px decorative geography (harbour/strait/sea/scale-bar
  labels nobody can read) and spend the space on the functional legend/cartouche.
- **Shop**: unify the two tile types (relic-card vs service-slot) and group the 4 categories.
- **Event engine sprawl**: ~8 different mini-game shells — consolidate onto one consistent
  choice-screen layout (biggest "hard to understand" win, biggest effort).
- **Two FAKE settings** (Color Blind Mode, Animation Speed) are unplumbed — hide or label
  "(coming soon)". (`SettingsOverlay.gd:955/899`)
- **De-duplicate**: two How-to-Play overlays (MapView + MainMenu); three+ deck-builder
  scenes (NetQuick/Constructed/Sealed) — extract shared builders so fixes land once.

## Implementer notes
- Card-text sizes must be changed in BOTH `_build_chart_proto` (live) and
  `_build_baked_overlay_layout` (baked) or the two paths diverge. The shrink FLOOR is
  shared in `_fit_desc_to_box`, so the floor is one edit.
- Several containers are fixed-height (Event choice 118px, relic tiles 120px, Shop tile
  150px) — font bumps there may need a matching container bump to avoid clipping.
- No windowed rendering / screenshots possible in the dev shell — every visual change
  needs the user to verify on a clean restart.
