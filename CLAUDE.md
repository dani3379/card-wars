# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Burning Meadow" — a lane combat roguelike deckbuilder built in Godot 4.6 (Forward+, 2D rendering). Inspired by Card Wars (combat) and Slay the Spire (roguelike structure). 4 lanes, simultaneous combat with Swift pre-phase, floop, sacrifice, spells. Game loop: main menu → 8-floor map → combat → card reward → repeat → boss → game over.

## Running the project

Open in Godot 4.3+ and press F5. Main scene is `scenes/main_menu.tscn`. No build step, no tests, no CLI tooling.

## Architecture

### Scene flow

`MainMenu → MapView → Combat → Reward → MapView → ... → Combat (boss) → GameOver`

Scene transitions use `get_tree().change_scene_to_file()`. Each scene is a `.tscn` in `scenes/` with a matching script in `scripts/scenes/`.

### Autoload singletons

- **RunState** (`scripts/state/RunState.gd`) — current run state: HP, deck, relics, floor, gold. `get_act()` returns 1-3 based on floor. `start_new_run()` resets everything.
- **MetaState** (`scripts/state/MetaState.gd`) — cross-run persistence: win/loss counts. Saved as JSON to `user://meta.save`.
- **CardDB** (`scripts/data/CardDB.gd`) — 95 unique cards: 9 starter + 83 draft pool (30 common, 29 uncommon, 24 rare) + enemy creatures. Card types: "creature" (ATK/HP/keywords) and "spell" (spell effect + targeting). `roll_card_reward(act, is_elite, is_boss)` for rarity-weighted picks.
- **RelicDB** (`scripts/data/RelicDB.gd`) — 36 relics across 3 tiers: starting (8), combat (23), utility (5). Each has hooks, effect ID, and value.
- **KeywordEffects** (`scripts/data/KeywordEffects.gd`) — 16 keywords from design doc. Dispatchers: `dispatch_on_enter`, `dispatch_on_death`, `dispatch_start_of_round`. Handles regenerate, wither, on-enter/on-death effects, summon tokens.

### Combat scene (`scripts/scenes/Combat.gd`)

The largest file (~900 lines). Core systems:
- **Round flow**: draw 5 → player plays creatures/spells, toggles floop, sacrifices → resolve floops → Swift phase → simultaneous combat → deaths/on-death → discard hand → enemy places 1-2 → new round. Round 1 is setup only (no combat).
- **Board**: `_player_field[4]` and `_enemy_field[4]`, indexed 0-3. PanelContainer slots in HBoxContainers.
- **Spells**: targeted spells enter `_targeting_spell` mode (click to resolve). Non-targeted resolve immediately. Exhaust pile separate from discard.
- **Sacrifice**: once per turn, free action. Triggers on-death. [S] key or HUD button.
- **Floop**: creatures with floop can toggle `will_floop`. Resolved before combat.
- **Keywords**: Armored (-1 dmg from creatures), Swift (pre-phase), Thorns (1 back), Piercing (excess kills → face), Last Stand (survive once at 1 HP), Ranged (random target), Regenerate/Wither (start of round).
- **Relic effects**: checked inline via `_has_relic()`. Major hooks: combat_start, turn_start, creature_played, hero_damaged, creature_death.
- **HUD**: built programmatically. Parchment-styled panels, screen shake via CanvasLayer offset.

### Card2D (`scripts/Card2D.gd`)

PanelContainer-based card. Supports creatures (ATK/HP display) and spells (SPELL label, no stats). Drag from hand above play threshold to play. Battlefield creatures show floop indicator. `take_damage()` handles Armored and Last Stand. `temp_atk_buff` for this-turn buffs.

### Card data schema

Creatures: `id, name, type:"creature", cost, atk, hp, rarity, keywords[], desc`. Optional: `on_enter{}, on_death{}, floop{}, adj_buff{atk,hp}, wither:int, passive:String, extra_damage:int`.

Spells: `id, name, type:"spell", cost, rarity, keywords[], desc, spell{type,value,...}, targeting:String`. Targeting: "enemy_creature", "friendly_creature", "any_creature", "any", "none".

### Adding content

- **New card**: add to `CardDB.CARD_POOL`. Include all fields per schema above.
- **New relic**: add to `RelicDB.RELICS`, implement effect check in Combat.gd.
- **New keyword**: add to `KeywordEffects.KEYWORDS`, implement in dispatchers, add to Card2D display.
- **New spell type**: add `spell.type` handler in Combat.gd `_resolve_spell()` or `_resolve_custom_spell()`.

## Key constants

- Player HP: 25, Mana: 3/turn fixed
- Hand draw: 5/turn, max hand: 10
- 8 floors per run. Acts: floors 1-3 = act 1, 4-6 = act 2, 7-8 = act 3
- Boss at floor 8, elites at floors 4 and 7
- Card rarities: "starter", "common", "uncommon", "rare"
- Enemy creatures: temporary ENEMY_POOL, replaced by EncounterDB in Phase 4

## Gotchas

- Combat.gd builds all HUD in code, not in the scene editor
- Spell targeting uses `_input()` override, not the card drag system
- `KeywordEffects` accesses `ctx._player_field` / `ctx._enemy_field` directly — Combat is always the ctx
- Enemy deck uses random pulls from ENEMY_POOL scaled by act (Phase 4 replaces with premade lineups)
- Token creatures have synthetic card_data created in `summon_token()`, not from CardDB
