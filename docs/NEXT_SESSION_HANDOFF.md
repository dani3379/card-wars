# Burning Meadow — continuation handoff (written 2026-06-18)

You are continuing an autonomous **playtest → find problems → fix → verify** loop on this Godot 4.6 deckbuilder. A prior session verified stability and landed balance/softlock fixes. Keep going.

## ⚡ HOW TO WORK — the user wants AGGRESSIVE token use
- **Bias hard to ACTION over deliberation.** Don't re-derive context that's already in memory/roadmap. Don't write long reasoning weighing options you won't take — pick the obvious one and go.
- **Parallelize everything.** Batch independent tool calls in ONE message. Launch slow probes with `run_in_background: true` and immediately keep working on something else — NEVER sit idle waiting for a probe (you get a completion notification).
- **Do many things per turn.** Make multiple edits, run multiple checks, cover multiple areas before reporting. Summarize at the end, not after every step.
- **Don't re-verify what's already verified** (see "Already done"). Don't re-audit clean systems.
- **Act on sensible defaults without asking.** The user has granted standing autonomy for polish/fixes/balance across the whole game. Only stop for genuinely design-defining calls (e.g. the floop decision below).
- **KEEP the verify loop — just run it fast.** Every code change → headless parse-check + a *targeted* re-probe (`--only=` the thing you changed). Never ship an unverified balance/logic change. Speed comes from parallelism and not over-thinking, NOT from skipping verification.
- Don't commit unless asked. Don't run anything that writes save slot 0 (see save-safety).

## Orient (skim, then go)
- Memory files (auto-loaded): `project_stability_harness.md` (the probe toolkit + everything verified so far — READ THIS), `project_card_balance_curve.md` (stat curve), `project_live_build_state.md`.
- `docs/ROADMAP_TO_1.0.md` status log — the **2026-06-18** entry is the latest state.

## Environment essentials
- Godot binary: `D:\games\Godot_v4.6.2-stable_win64.exe` (Bash: `"/d/games/Godot_v4.6.2-stable_win64.exe"`).
- Headless probe: `"/d/games/Godot_v4.6.2-stable_win64.exe" --headless --path "D:\Godot" --script res://tools/<probe>.gd`
- Parse-check: `... --headless --path "D:\Godot" --editor --quit-after 3 res://scenes/combat.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"` (empty = clean).
- **SAVE-SAFETY:** `RunState.start_new_run` does NOT write disk (safe to spam in probes). Do NOT call `visit_node`/`end_run` and do NOT run `tools/screenshot/_probe_map_live.*` — those write save slot 0 and clobber the user's run.
- **GDScript pitfall:** `var x := SomeFunc()` fails to parse when the func returns Variant (`max()`, `Dictionary.get`, `roll_*`). Use explicit `var x: Type = ...`.
- **Sub-agents' shell is INCONSISTENTLY DENIED** — only the main session reliably runs the Godot binary. Spawning agents to run probes mostly fails; use agents only for static analysis/proposals and run + certify all Godot yourself. (Don't waste turns on this.)
- Headless gotcha: `Combat._prebake_hand_textures()` early-returns headless (that's what lets probes drive real combat). UI scenes render fine headless for logic.

## The probe toolkit (all in `tools/`)
- `_probe_autorun.gd` — flood-bot auto-plays every encounter; crash/softlock sweep.
- `_probe_events.gd` — fires every non-modal event effect.
- `_probe_flow.gd` — drives every modal picker + shop/rest/wayside/recruit/reward/treasure under 5 RunState fixtures (incl. `one_card`/`all_curse`).
- `_probe_spells.gd` — resolves every targeted spell (builds targets, calls `_resolve_spell`; uses `EncounterDB.make_card_data` for synthetic enemies so they carry `id`).
- `_probe_balance.gd` — per-encounter win-rate × 5 heroes on bare starter decks. **SLICE it** (`-- --only=id,id` or `-- --prefix=amalgam_`); the full run times out (~595s) past ~26 encounters. **Read WITHIN-TIER relative comparisons** — the flood-bot is dumb and uses bare decks, so absolute boss/elite win-rates are a low floor; an encounter far easier than its same-tier peers is the real signal.
- `_probe_audit.gd` / `_probe_cardmap.gd` — content cross-ref / per-card ability dump.

Probe-authoring patterns that work: instantiate a scene WITHOUT adding to tree to skip `_ready` and call methods directly (logic-only); build synthetic enemies via `EncounterDB.make_card_data`; blocklist picker-opening cards/spells (they `await` input and stall headless).

## Already done & verified (DO NOT redo)
- **Crash-clean:** combat (50 fights), events (338 effects), modal flows (145 drivers), targeted spells (22) — all 0 crashes/softlocks.
- **No dead content:** every spell type/keyword/passive/relic id wired to a handler.
- **Balance fixes (re-probe-verified):** `amalgam_stalwart` 4/5→0/5, `hollow_king` 4/5→1/5, `void_walker` 5/5→3/5, `corrupted_shepherd` hardened (still 4/5 vs flood-bot but bot HP-on-win 15.8→11.5). 4 card nerfs (glass_knight/ember_stalker/cleave_hound/crystal_sentry).
- **7 softlock fixes** in Event.gd/Wayside.gd (empty-deck floor + empty-picker guard).

## Next tasks (priority order — just do them)
1. **Build a SMARTER auto-pilot for `_probe_balance`** (highest leverage). The current bot floods creatures, casts no targeted spells, never positions. A smarter player (cast targeted damage/buff spells via `_resolve_spell` + `_auto_target_for`, basic target priority, bank Command for big plays) turns the bare-deck floor into REAL difficulty curves. Then re-sweep all encounters and tune from real numbers.
2. **Re-check disruption fights with the smarter bot:** `corrupted_shepherd`, `void_walker`, `hollow_king`, `puppeteer` (4/5), `glass_menagerie` (4/5). The flood-bot under-reads disruption/death-punish fights — confirm/adjust.
3. **Modal-card combat coverage.** Autorun skips Discover/Copy cards (familiar, scholar, treasure_hunter, adaptable, copycat, doppelganger, lost_tome, war_council, chaos_imp). Extend a probe to auto-pick the first picker option so those resolvers get exercised.
4. **FLOOP — biggest combat-variety lever, but a DESIGN-DEFINING call: ask the user yes/no before building.** It's currently 100% absent and dead-coded: zero cards carry a `"floop"` field, `has_floop()` keys on it, and `will_floop` is never consumed in combat resolution — so the whole toggle UI/tutorial/`can_attack` branch can never fire. Restoring = a per-round resolution pass (fire `will_floop` creatures' ability via the existing `_resolve_on_play_ability`, reset `will_floop` each round) + a handful of draftable cards with a `floop` field. The toggle infra (`_on_floop_clicked`, `toggle_floop`) already exists.
5. **Commit** (ask first). NOTE: a large PRE-EXISTING uncommitted working tree sits underneath this session's work (~1480 lines in `Combat.gd` + the 2026-06-17 card rebalance) — surface it and let the user decide commit scope.
6. Low-priority roadmap art follow-ups: give `plague_bell` its own icon; visually confirm no non-PD card portrait.

## Discipline (fast but real)
After edits: parse-check + targeted re-probe. For balance, re-probe before/after and confirm movement toward peer range without overshoot. At the end of a work batch, update the `docs/ROADMAP_TO_1.0.md` status log + the relevant memory file.
