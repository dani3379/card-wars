# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Burning Meadow" — a grimoire-themed lane combat roguelike deckbuilder built in Godot 4.6 (Forward+ renderer). Currently a 2.5D prototype (3D cards on a tilted table). The game loop: main menu → linear 8-floor map → combat → card reward → repeat → boss → game over.

## Running the project

Open in Godot 4.3+ and press F5. Main scene is `scenes/main_menu.tscn` (set in `project.godot`). No build step, no tests, no CLI tooling — everything runs inside the Godot editor.

## Architecture

### Scene flow

`MainMenu → MapView → Combat → Reward → MapView → ... → Combat (boss) → GameOver`

Scene transitions use `get_tree().change_scene_to_file()`. Each scene is a `.tscn` in `scenes/` with a matching script in `scripts/scenes/`.

### Autoload singletons (persist across scene changes)

- **RunState** (`scripts/state/RunState.gd`) — current run's mutable state: HP, deck, relics, floor, gold. Cleared on `start_new_run()`. Also defines the fixed lane identities (Forge/Grove/Void/Tide) and the floor→node-type mapping.
- **MetaState** (`scripts/state/MetaState.gd`) — cross-run persistence: win/loss counts, unlocked cards/relics. Saved as JSON to `user://meta.save`.
- **CardDB** (`scripts/data/CardDB.gd`) — all card definitions as const dictionaries. Split into `PLAYER_POOL` and `ENEMY_POOL`. `STARTER_DECK` defines the 10-card starting deck. `roll_card_reward()` handles tier-weighted random picks.
- **RelicDB** (`scripts/data/RelicDB.gd`) — relic definitions with hook names (`turn_start`, `hero_damaged`, etc.) and a `value` field. Combat.gd checks `_has_relic()` and applies effects inline.
- **KeywordEffects** (`scripts/data/KeywordEffects.gd`) — central dispatch for keyword on-play and on-death effects. Combat calls `dispatch_on_play`/`dispatch_on_death`; all keyword logic lives here.

### Combat scene (`scripts/scenes/Combat.gd`)

The largest file. Owns:
- Turn flow: `_start_player_turn()` → player drags cards → `_on_end_turn()` → `_start_enemy_turn()` → `_enemy_ai()` → `_do_combat()` → loop
- 4-lane board: `_player_field[4]` and `_enemy_field[4]`, indexed 0-3 left-to-right
- Lane effects applied in `_effective_attack()` and `_apply_lane_damage()`
- Relic effects checked inline via `_has_relic()` at various hook points
- Full HUD built programmatically (no .tscn UI nodes) — parchment-styled panels
- Tabletop camera: RMB orbit, scroll zoom, MMB pan

### Card scene (`scripts/Card.gd`)

Each card is a Node3D with: mesh, area3d for picking, hover glow light, Label3D stats. Handles its own drag/hover/play animation via tweens and a spring-physics drag system. Emits `played` and `destroyed` signals consumed by Combat.

### Keywords currently implemented

`charge`, `taunt`, `lifesteal`, `frenzy`, `deathrattle_smite`, `deathrattle_burn`, `onplay_draw`, `onplay_smite`. To add a keyword: add to `KeywordEffects.KEYWORDS`, implement the hook in `_run_on_play`/`_run_on_death`, add the string to card definitions in CardDB.

### Adding content

- **New card**: add entry to `CardDB.PLAYER_POOL` or `ENEMY_POOL`. Code reads dynamically.
- **New relic**: add entry to `RelicDB.RELICS`, then add effect logic in Combat.gd where the hook fires.
- **New keyword**: add to `KeywordEffects.KEYWORDS`, implement dispatch, update `Card._format_keywords()` for display.

## Key constants

- Player HP: 25, Mana: 3/turn (both in RunState/Combat)
- Hand draw: 5/turn, max hand: 8
- 8 floors per run, boss at floor 8, elites at floors 4 and 7
- Card tiers: 1 (common), 2 (uncommon), 3 (rare)
- Lane positions: `LANE_X = [-1.35, -0.45, 0.45, 1.35]`

## Gotchas

- The README describes an older "Phase 2 prototype" with `PlayArea.gd` as orchestrator; the current codebase has moved past that to `Combat.gd`. `play_area.tscn` is orphaned.
- Autoloads in `project.godot` reference UIDs, not paths. The KeywordEffects autoload uses a `res://` path — inconsistent but functional.
- Combat.gd builds all HUD elements in code (`_build_hud`, `_build_end_turn_button`, etc.) rather than in the scene file. UI changes require editing GDScript, not the scene editor.
- Card costs in CardDB don't match mana budget well — tier-2/3 cards cost 3-6 mana but base mana is 3, making expensive cards unplayable without the Chronograph relic.
