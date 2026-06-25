# Burning Meadow — Accessibility & New-Player Readability Audit

**Date:** 2026-06-24
**Method:** 10 parallel code-grounded agents, one per surface (animation/motion, accessibility-feature
plumbing, card visual readability, combat feedback, onboarding, keyword teaching, combat HUD, map &
run-structure, genre benchmark, cognitive-load/difficulty). Each answered: *can a new player tell what is
happening — and is the game playable by someone who can't see/use it the "default" way?*
**Builds on** `docs/CLARITY_AUDIT.md` (2026-06-21). Discovery pass — **no code changed.** Every finding cites `file:line`.

---

## ✅ IMPLEMENTATION STATUS — TIER 0 + TIER 1 SHIPPED (2026-06-25)

All of **Tier 0 (0.1–0.5)** and **Tier 1 (1.1–1.9)** are implemented on branch
`feature/visual-polish-and-content` (uncommitted). Decisions used: reduce-motion = **kill
decorative/oscillating motion, keep informational** (recoil/floats/flash); colorblind = **stat/float
MVP first**. Verified: headless parse-check clean (Combat/Card2D/GameTheme/UserSettings + all touched
scene scripts), `_probe_autorun` **50/50 fights, 0 softlocks, 0 crashes**, and real-render PNG
pixel-inspection of the gold counter, white seal numerals, the new structure device, and the ▲/▼ ATK
caret (buff + debuff).

- **0.1 colorblind** — `GameTheme.cb_color()` added (reads `UserSettings.colorblind_mode` live; deut/protan rotate green→blue, trit blue→teal); `spawn_floating_number` routes every combat float through it (heal-green vs damage-red now separable) and the ATK caret colour too. Card seals were already bronze/oxblood/navy (CVD-OK). Remaining: HP-bar fills + a live-repaint of already-built board cards on mid-combat toggle.
- **0.2 reduce_motion** — gated the looping/decorative tweens: threat pulse, idle bob, danger-overlay pulse, floop pulse (Card2D); low-HP dread + Command-seal lamp flicker (Combat); Rest campfire glow. Informational motion kept. *MainMenu title shimmer left untouched (user's uncommitted MainMenu.gd).*
- **0.3 anim_speed** — wired the dead `anim_time()` into `screen_flash` + the floating-number tween (pacing via `_short_pause` already scaled). Most other tweens still run at base duration by design.
- **0.4 particles** — `if not UserSettings.particles: return` guards on `spawn_ash_burst` / `spawn_spell_burst` / `_spawn_family_particles` (all bursts funnel through these; covers death bursts).
- **0.5 shape redundancy** — drawn `StatCaret` (▲ gold buff / ▼ red debuff) on the ATK seal via `update_stat_display`. **Cost +/- tick deferred** — no discounted-cost display exists on the face to annotate.
- **1.1 gold counter** — diegetic coin + numeral under the piles, refreshed/flashed in `_update_hud` from `RunState.gold` (campaign only).
- **1.2 HP/ATK inversion** — `_wd_build` `WAX_ATK`→bronze, `WAX_HP`→oxblood (was red=ATK/green=HP); inspector now matches the board.
- **1.3 numerals** — hand seal numerals → pure-white / opaque-black outline (6) / shadow / 19px; WaxSeal sunk face deepened 0.20→0.32.
- **1.4 keyword tooltips** — keyword IDs threaded into `_kw_stamp_row`; roundels set `MOUSE_FILTER_PASS` + `tooltip_text = KeywordEffects.tooltip_for(id)`.
- **1.5** dead Floop glossary row deleted. **1.6** distinct `hit_creature`/`creature_death` SFX wired into the clash — **silent until CC0 clips land** (no audio assets exist project-wide yet). **1.7** copy fixes (Enlist — free / Can't buy potions (Temperance Vow) / Thin your deck / Take Gold Only / real "COMMAND" tracking via FontVariation). **1.8** `structure.svg` device added + registered, dead `floop` registration removed, imported. **1.9** map open-zoom 1.20→1.15 + "THE KEEP" boss legend entry (+ crimson boss SITE_STYLE).

**Not started:** Tier 2 (always-on telegraph, combat log, silent-passive callouts), Tier 3 (onboarding), Tier 4 (keyboard/controller), Tier 5 (Assist Mode — needs owner decision). The §3 decisions for those still stand.

---

## 0. Read this first — the two headlines

**Headline A — Two advertised accessibility settings are FAKE (exposed in the menu, wired to nothing).**
This is the single most important finding and the most embarrassing to ship:
- **`colorblind_mode` has ZERO consumers project-wide.** `UserSettings.set_colorblind_mode` saves + emits
  `colorblind_changed` (`UserSettings.gd:345`), but a whole-project grep finds the string only in the two
  settings files. No palette is remapped anywhere. The Off/Deuteranopia/Protanopia/Tritanopia dropdown
  (`SettingsOverlay.gd:774`) changes nothing on screen.
- **`reduce_motion` only force-disables shake + particles** (`UserSettings.gd:351`). It has **0 consumers in
  `Combat.gd` and `Card2D.gd`** — the looping threat pulse, idle creature bob, `screen_flash` wipes, death
  spins, and ~95 card tweens all still play. Two agents found this independently.
- **`UserSettings.anim_time()` is dead code** — defined (`UserSettings.gd:387`), called nowhere. The
  Animation-Speed setting only scales `_short_pause` gaps, not the actual tweens, so "Fast/Instant" doesn't
  speed card/combat animation.
- **`particles` only toggles the menu `AmbientMotes` node** (`UserSettings.gd:301`); every in-combat burst
  ignores it.

A player who turns these on trusts them and gets no relief — worse than not offering them. **Fix these before
anything else.** The good news: the settings *scaffold* (`SettingsOverlay.gd`) is genuinely strong; this is
wiring, not new UI.

**Headline B — The game is effectively mouse-ONLY.** No keyboard menu/board navigation, no controller, and
spell targeting *requires* a mouse (`Combat.gd` targeting reads `InputEventMouseButton` only). 30
`Control.FOCUS_NONE` assignments, **zero** `grab_focus`, **zero** joypad handling. This blocks keyboard-only,
switch, and Steam Deck / controller users from playing past the menu. Bigger lift; flagged as its own workstream.

The rest of the moment-to-moment thesis from the prior audit still holds: **"players ignore effects and just
charge in" because depth is hover/one-shot-gated.** The antidotes (always-on telegraph, a combat log, labeled
effect callouts) remain the highest-leverage gameplay-clarity work and are still unbuilt.

---

## 1. IMPORTANT CORRECTIONS — already shipped since the 2026-06-21 audit (do NOT redo)

Multiple agents verified these against live code. The prior audit / CLAUDE.md list them as TODO; they're done:

- **The "4 missing keyword SVGs" (rampage/lifelink/overrun/formation) EXIST** in `assets/icons/keywords/` and
  are registered (`GameTheme.gd:1328`). The only genuine device gap is **`structure`**. (slay/adjacent are
  rules-vocabulary, correctly glossary-only.) `floop.svg` is registered but vestigial — dead registration.
- **On-enter / on-death CALLOUTS were built** (`spawn_trigger_callout`, `KeywordEffects.gd:115/153`). So P2 #13
  is half-done — only the **~25 `EncounterEffects` passive/reactive mutations** are still silent.
- **Card P3 items shipped:** "+N" keyword overflow on hand cards (`Card2D.gd:3366`), the "SPELL" footer
  (`:3978`), 18px stat numerals, forged-card gilt cues. There is **no cryptic 3-letter chip** on the live face
  (icon-less keywords are skipped).
- **Map:** opens at zoom **1.20** now (not 1.45), inside the dress band; "YOU ARE HERE" plate + ground-ring
  exist; legend has SHOP/RECRUIT qualifiers, General label, mutator-★/pursuit-pennant primer, 4 distinct
  wayside glyphs.
- **Rest:** verb unified to **"Forge"/"Forge Two"**; disabled labels already lead with the rule ("Can't heal at
  camp (Hairshirt)").
- **Event:** choice renderer already shows headline → **gold mechanical outcome line** → dim flavor.
- **HUD:** encounter *passives* DO get a persistent edict banner (`Combat.gd:11217`); `_info_label` has a token
  guard (it does not blindly self-stomp). Exhaust pile, Command bank pips, Command hover tooltip all shipped.

---

## 2. Prioritized roadmap

Impact/Effort per item. "★" = multiple agents independently converged on it.

### TIER 0 — Settings that lie (accessibility correctness — do first)
| # | Fix | Where | I/E |
|---|-----|-------|-----|
| 0.1 ★ | **Make `colorblind_mode` real.** Add a `GameTheme.cb_color(role)` indirection that critical colors route through; subscribe GameTheme to `colorblind_changed`; minimum-viable = remap the red/green stat & cost pair. | `GameTheme.gd`; `UserSettings.gd:345` | H/H |
| 0.2 ★ | **Make `reduce_motion` real.** Gate the looping threat pulse (`Card2D.gd:6137`), idle bob (`Card2D.gd:6163`), `screen_flash` (`Combat.gd:12471`), death spin, intro overshoot, and oscillating/rotational tweens. Policy: kill decorative motion, keep snappy informational motion (recoil/floats/flash). | `Card2D.gd`, `Combat.gd` | H/M |
| 0.3 | **Wire `anim_speed` into tweens** (use the dead `anim_time()`), or document that it's pacing-only. | `Combat.gd`, `Card2D.gd` | M/M |
| 0.4 | **Guard the 4 combat particle emitters** on `UserSettings.particles` (`spawn_spell_burst` 13599, `_spawn_family_particles` 13631, `spawn_ash_burst` 13113, death burst). | `Combat.gd` | M/L |
| 0.5 ★ | **Non-color redundancy** for color-only cues: a `▲`/`▼` caret on buffed/debuffed ATK seals; a `+`/`−` tick on discounted/surcharged cost. Shape, not words — respects the no-card-text rule. | `Card2D.gd:5352`, `:6248` | H/M |

### TIER 1 — Cheap, unambiguous wins (no design decision needed)
| # | Fix | Where | I/E |
|---|-----|-------|-----|
| 1.1 | **Gold counter in combat** (confirmed entirely absent). Top-left, flash on change, refresh from `_update_hud`. | `Combat.gd:12372` | H/L |
| 1.2 ★ | **Fix the HP/ATK color INVERSION** between the board and the hover panel. Hand/token seals use red=HP, bronze=ATK; the hover inspector `_wd_build` uses red=ATK, green=HP. Unify to the board family (HP=oxblood, ATK=bronze, Cost=navy) everywhere. | `Card2D.gd:6616` | H/L |
| 1.3 | **Hand-card numerals → the verified token recipe** (pure white / opaque-black outline / shadow / 19px) + deepen the wax seal's sunk face. Hand stats are the lowest-contrast read today. | `Card2D.gd:3855`, `:3141` | H/L |
| 1.4 ★ | **Hover tooltips on the live card keyword roundels** — they're currently mute (the only tooltip path is dead v3 code). Pass keyword IDs into `_kw_stamp_row`, set `MOUSE_FILTER_STOP` + `tooltip_text = KeywordEffects.tooltip_for(id)`. | `Card2D.gd:3323/3717` | H/L |
| 1.5 | **Delete the dead "Floop" row** from the in-combat glossary — it actively teaches a mechanic that does nothing. | `Combat.gd:12020` | M/L |
| 1.6 ★ | **Distinct creature-hit vs creature-death SFX** in the clash cascade (today a kill sounds like nothing). | `Combat.gd:2592` | H/L |
| 1.7 | **Copy fixes:** Recruit button "Enlist — free" (`Recruit.gd:176`); Shop "Can't buy potions (Temperance Vow)" + removal "Thin your deck" (`Shop.gd:173/185`); Treasure "Take Gold Only" (`Treasure.gd:81`); replace the spaced `"C O M M A N D"` with real tracking (`Combat.gd:11437`). | various | M/L |
| 1.8 | **Add `structure.svg`** keyword device + remove the dead `floop` registration. | `GameTheme.gd:1328` | M/L |
| 1.9 | **Map open-zoom 1.20 → 1.15** so kingdom/place-names aren't stuck at 50% alpha on arrival; add a **"THE KEEP"** boss entry to the legend. | `MapView.gd:91`, `MapTerrain.gd:2516` | M/L |

### TIER 2 — The big combat-legibility systems (the core "players charge in" fix)
| # | Fix | Where | I/E |
|---|-----|-------|-----|
| 2.1 ★ | **Always-on, board-wide enemy telegraph during planning** (Into-the-Breach model — the #1 benchmark pick). The accurate predictor `_predict_lane_strike` (`Combat.gd:13379`) is hover-only/single-creature today. Draw faint arrows + DIES/-N/LETHAL chips for *every* enemy strike; brighten the hovered one; fold in Piercing overflow + CHARGE/ENRAGE. Simultaneous combat makes this *easier* than in sequential games (deterministic at lock-in). | `Combat.gd:13304` | H/M-H |
| 2.2 ★ | **Lightweight scrolling combat log** — there is none. Collapsible corner `RichTextLabel`, one terse color-coded line per event, pushed from the already-central chokepoints (`_creature_attacks_creature` 2559, `_creature_hits_face` 2638, `damage_player_hero` 6071, the dispatchers). The only "what happened" channel that survives overlap. | new widget | H/M |
| 2.3 ★ | **Labeled callouts for the ~25 silent `EncounterEffects` passives/reactives** (nexus +ATK board buff, executioner face damage, spellbreaker bleed, etc.). One `_passive_callout` helper routed through the existing chip system; convert the 6 ad-hoc `_show_info` lines to it. The literal antidote to "players ignore effects." | `EncounterEffects.gd` | VH/M |
| 2.4 | **Route every silent stat change through the existing floats** (`_spawn_atk_change_popup`, `show_heal_number`): Royal Guard, Vampire Lord, Vengeance, escalation +ATK, on-death `debuff_all_player_atk`, `veterans_medal`. Fan board-wide swings as ONE event (named banner + synchronized per-creature floats). | ~12 sites in `Combat.gd` | H/L-M |
| 2.5 | **Default-attack number parity** (StS): promote the per-lane "this column takes N" to always-on, loud, equal to the non-ATK intent pills; **refresh intent badges from `_update_hud`** (today `_assign_intents` runs once/round and badges go stale). | `Combat.gd:7389/12405` | M-H/M |
| 2.6 | **Persistent mutator / faction-engine HUD chip** (passives have the edict; mutators only flash in the intro banner that tweens away). Always-on icon+tag, hover-expand. | `Combat.gd:11217` zone | H/M |
| 2.7 | **Motion that teaches:** an enemy-strike **anticipation windup** (0.18s pull-back + intent brighten before the thrust) so "*they're hitting you*" reads before the blow, and a collective **CLASH** beat so simultaneity is felt, not just captioned. | `Card2D.gd:5876`, `Combat.gd:2253` | H/M |
| 2.8 | **Post-combat one-line summary** (net deaths each side + face dealt/taken); **face-damage source label** ("Doom!", "Trebuchet") under the HP number. | `Combat.gd:2274/6071` | M/L |

### TIER 3 — Onboarding & teaching
| # | Fix | Where | I/E |
|---|-----|-------|-----|
| 3.1 ★ | **First-run coach-mark widget** (a small *pinned* panel, NOT the centered `_info_label`) teaching the 4 primary verbs once, gated to `MetaState.total_runs == 0` + new `UserSettings` flags: **deploy** (clear at `_play_creature` 4422) → **Command** → **spell targeting** (arm at 4631) → **end-turn = both sides strike**. Full sequence/trigger/flag spec in the onboarding agent's report. | `Combat.gd` | H/M |
| 3.2 | **Force a safe (siege/back-row) opening formation on run 0's first fight** so ending turn 1 doesn't punish the "set your line" turn. | `Combat.gd:1271` | H/L |
| 3.3 ★ | **First-time-this-run keyword TEACH:** the first time a keyword resolves, expand it into a brief *labeled* tooltip-card (name + the authored `KEYWORDS[k].desc`), not just the 1-word confirm chip. Track via a per-run `keywords_seen` set; hook the dispatch chokepoints. | `KeywordEffects.gd:99/123`, `Combat.gd:12511` | H/M |
| 3.4 | **Auto-surface How-To-Play once** on first launch (`MetaState.total_runs==0`); add a **one-line mechanical tag per hero** in the detail pane (the data already exists in `HeroDB.FACTIONS.engine_line`). | `MainMenu.gd:54/903` | M/L |
| 3.5 | **Make the in-combat "?" glossary discoverable** (nudge it on first un-taught keyword); group its 26 rows by bucket + a positional micro-diagram. | `Combat.gd:12037/12165` | M/L-M |
| 3.6 | **Move the simultaneous-combat tip earlier** — to round-1 setup of the first fight, not after the first End Turn. | `Combat.gd:5827` | H/L |

### TIER 4 — Keyboard/controller + remaining visual polish
| # | Fix | Where | I/E |
|---|-----|-------|-----|
| 4.1 ★ | **Keyboard / controller support** (phased): stop forcing `FOCUS_NONE` + add `grab_focus` per screen (cheap, unblocks Tab/Enter menus); define input actions; add a keyboard spell-targeting fallback (cycle valid targets, confirm). | menus + `Combat.gd:5440` | H/H |
| 4.2 | **Legible/dyslexia font option** (swap `GameTheme.font_card_body`/HUD to Atkinson Hyperlegible or OpenDyslexic — one centralized swap); optional independent card-body text size. | `GameTheme.gd` | H/M |
| 4.3 | **Creature-vs-spell visual distinction:** cool frame/mat tint + a pennant-tail cartouche variant for spells + promote the SPELL footer to a type-line. | `Card2D.gd:3536/3978`, `InkCartouche` | H/M |
| 4.4 | **Upgraded-card glance cue on the rarity gem** (a concentric gilt halo when forged — survives name ellipsis, never occluded). | `Card2D.gd:3652` | M/L |
| 4.5 | **Token keyword rail "+N" overflow** (hand cards have it; tokens silently drop a 4th keyword). | `Card2D.gd:1531` | M/L |
| 4.6 | **Move `_info_label` to a reserved transient strip** off the board center (and give tutorial tips a distinct sub-region). | `Combat.gd:10534` | M/L-M |
| 4.7 | **END TURN affordance:** real edged button, label the consequence ("END TURN ▸ CLASH"), threat-tint when incoming damage is lethal. | `Combat.gd:12149` | M-H/L |
| 4.8 | **Audio cue distinctness** for low-vision: ensure hit/death/hero-damage/lethal are sonically distinct CC0 clips. | `AudioBank.gd` / assets | M/L-M |

### TIER 5 — Design-level (needs an owner decision before building)
| # | Proposal | Where | Note |
|---|----------|-------|------|
| 5.1 ★ | **Assist Mode** (opt-in, Celeste/StS-style; locked at run-start, "Assist" sigil on HUD). Levers = single constants: +starting HP 25→32 (`Combat.gd:812`), no Act-1 mutators (`RunState.gd:1414`), gentler `ESCALATION_REINFORCE_ROUND` 4→6 (`Combat.gd:90`). Do **not** touch Command/draw/banking. | new Settings section | Converts bounce-offs into retained players at zero cost to others. **Recommend building.** |
| 5.2 | **Keyword sequencing:** extend the run-0 mutator-free band to the first *two* fights; lower Act-1 *combat* mutator density 35%→~20%; reconsider `goblin_scouts`' round-5 all-Swift "ambush" gotcha. | `RunState.gd:1411`, `EncounterDB.gd:458` | Data-only; genuine cognitive-load reduction, not dumbing-down. |
| 5.3 | **Stalwart starter-deck legibility** — Royal Guard's protective aura + grow-when-hit are invisible on the board (prose-only, no keyword). Surface via a keyword device, or swap one copy for a self-evident body. | `HeroDB.gd:34`, `CardDB.gd:308` | Stalwart is `DEFAULT_HERO` — the beginner's default deck. |
| 5.4 | **Scripted gated tutorial fight?** — Recommendation: **NO.** Coach-marks on the already-curated first fight are the genre-correct, lower-scope, higher-fidelity choice (StS/Inscryption model; Hearthstone's scripted tutorial is the F2P outlier). | — | Decided unless owner disagrees. |

---

## 3. Decisions needed from the owner

1. **Assist Mode (5.1)** — build it? (recommend yes; all levers already exist as constants.)
2. **Always-on telegraph (2.1)** — default-on for everyone, or behind the existing `combat_telegraph` toggle / at lower intensity so veterans aren't swamped?
3. **Reduce-Motion policy (0.2)** — kill only decorative/oscillating motion (recommended) or go fully static (instant snaps, no recoil)?
4. **Keyword sequencing / Act-1 mutator density (5.2)** — OK to change encounter/mutator data? ⚠️ a pre-existing uncommitted CardDB balance pass (troll/riteforge/standard_bearer) already sits in the tree — confirm/segregate before touching content.
5. **Keyboard/controller (4.1)** — in scope for this initiative, or a separate workstream?

---

## 4. Verification debt (when implementing)
Per the project's discipline: every code change → headless parse-check + targeted re-probe (`_probe_autorun`
50×5 for combat-touching changes), and render the real node to PNG + pixel-inspect for any layout/visual
change (per the "verify UI bugs visually" rule). The always-on telegraph (per-frame multi-predict) and the
on-enter landing beat (await-chain) especially want an autorun pass. Sub-agents can't run Godot reliably —
certify all Godot in the main session.

*No code was changed in this audit. All line numbers are reads at HEAD on `feature/visual-polish-and-content`.*
