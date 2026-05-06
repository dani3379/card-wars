# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Burning Meadow" — a lane combat roguelike deckbuilder built in Godot 4.6 (Forward+, 2D rendering). Inspired by Card Wars (combat) and Slay the Spire (roguelike structure). 4 lanes, simultaneous combat with Swift pre-phase, floop, sacrifice, spells. 3 acts with branching maps, shop/rest/event nodes, premade encounter lineups with fight passives.

## Running the project

Open in Godot 4.3+ and press F5. Main scene is `scenes/main_menu.tscn`. No build step, no tests, no CLI tooling.

## Architecture

### Scene flow

`MainMenu → MapView → Combat/Shop/Rest/Event → Reward → MapView → ... → Combat (boss) → GameOver`

Scene transitions use `get_tree().change_scene_to_file()`. Each scene is a `.tscn` in `scenes/` with a matching script in `scripts/scenes/`.

### Autoload singletons

- **RunState** (`scripts/state/RunState.gd`) — current run state: HP, deck, relics, gold, potions, map data, card upgrades. `get_act()` returns 1-3. `start_new_run()` resets and generates map. `get_current_act_map()` / `get_available_nodes()` / `visit_node()` for map navigation. Card upgrades tracked per deck index: `upgrade_card(idx, path, keyword)`, `get_upgraded_card_data(idx)`.
- **MetaState** (`scripts/state/MetaState.gd`) — cross-run persistence: win/loss counts. Saved as JSON to `user://meta.save`.
- **CardDB** (`scripts/data/CardDB.gd`) — 95 unique cards: 9 starter + 83 draft pool (30 common, 29 uncommon, 24 rare) + enemy creatures + curse card. Card types: "creature" (ATK/HP/keywords) and "spell" (spell effect + targeting). `roll_card_reward(act, is_elite, is_boss)` for rarity-weighted picks.
- **RelicDB** (`scripts/data/RelicDB.gd`) — 36 relics across 3 tiers: starting (8), combat (23), utility (5). Each has hooks, effect ID, and value.
- **KeywordEffects** (`scripts/data/KeywordEffects.gd`) — 16 keywords from design doc. Dispatchers: `dispatch_on_enter`, `dispatch_on_death`, `dispatch_start_of_round`. On-enter types: damage_opposing, damage_random_player, damage_all_enemies, draw, gain_gold, damage_face, debuff_opposing_atk, discard_random. On-death types: damage_opposing_lane, damage_all_enemies, summon, bonus_mana, damage_face, debuff_all_player_atk, damage_adjacent.
- **EncounterDB** (`scripts/data/EncounterDB.gd`) — 26 premade fight lineups across 3 acts. Each encounter has ordered creature deck, reinforcement, HP, and optional fight passive. `build_enemy_deck(id)` returns Array[Dictionary] of card data. `get_reinforcement(id)` for infinite backup creature.

### Combat scene (`scripts/scenes/Combat.gd`)

The largest file (~1950 lines). Core systems:
- **Round flow**: draw 5 → player plays creatures/spells, toggles floop, sacrifices → resolve floops → Swift phase → simultaneous combat → deaths/on-death → discard hand → enemy places 1-2 → passives → new round. Round 1 is setup only (no combat).
- **Board**: `_player_field[4]` and `_enemy_field[4]`, indexed 0-3. PanelContainer slots in HBoxContainers.
- **Enemy deck**: `Array[Dictionary]` of card data, loaded from EncounterDB or built from legacy random pool. `_place_enemy_card(data, lane)` creates Card2D from card data dict directly.
- **Spells**: targeted spells enter `_targeting_spell` mode (click to resolve). Non-targeted resolve immediately. Exhaust pile separate from discard.
- **Sacrifice**: once per turn, free action. Triggers on-death. [S] key or HUD button.
- **Floop**: creatures with floop can toggle `will_floop`. Types: damage_any, summon_random, kill_adjacent_summon, steal_atk, heal_all_friendly, summon_token.
- **Keywords**: Armored (-1 dmg), Swift (pre-phase), Thorns (1 back), Piercing (excess → face), Last Stand (survive once at 1 HP), Ranged (random target), Regenerate/Wither (start of round).
- **Encounter passives**: `_dispatch_passive_start_of_round()`, `_dispatch_passive_end_of_round()`, `_dispatch_encounter_on_enemy_death()`, `_dispatch_encounter_on_player_death()`, `_dispatch_encounter_on_enter()`. `_has_encounter_passive_keyword(card, kw)` grants piercing/thorns/armored to enemy creatures based on encounter passive ID.
- **Relic effects**: checked inline via `_has_relic()`. Major hooks: combat_start, turn_start, creature_played, hero_damaged, creature_death.
- **HUD**: built programmatically. Shows encounter name and passive description. Parchment-styled panels, screen shake via CanvasLayer offset.

### Map system

RunState generates a branching map per act: 8 rows with 1-3 nodes each. Row templates define node types (combat/elite/boss/rest/shop/event). Connections link each node to 1-2 nodes in the next row. MapView renders nodes as color-coded buttons with Line2D connections, highlights available nodes with gold borders.

### Card upgrade system

Three upgrade paths applied at rest sites:
- **Sharpen**: +2 ATK (creature) or +2 spell damage (spell)
- **Fortify**: +2 HP (creature) or -1 mana cost (spell)
- **Imbue**: add keyword from [piercing, swift, thorns, regenerate] (creature) or Retain/Double+Exhaust (spell)

Upgrades tracked in `RunState.card_upgrades` keyed by deck index. `get_upgraded_card_data(idx)` returns modified card data.

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
- **New encounter**: add to `EncounterDB.ENCOUNTERS` with name, act, type, hp, passive_id, passive_desc, deck, reinforcement. Add passive handler to Combat.gd if passive_id is non-empty.
- **New event**: add to `Event.gd` EVENTS dictionary with name, desc, choices with effects.

## Key constants

- Player HP: 25, Mana: 3/turn fixed
- Hand draw: 5/turn, max hand: 10
- 3 acts, 8 rows per act. Acts: 1, 2, 3
- Boss at row 8, elites at rows 4 and 7
- Card rarities: "starter", "common", "uncommon", "rare"
- Shop prices: common 50g, uncommon 75g, rare 120g, relic 100g, potion 40g, removal 50g
- Potion heals 8 HP, max 3 potions

## Gotchas

- Combat.gd builds all HUD in code, not in the scene editor
- Spell targeting uses `_input()` override, not the card drag system
- `KeywordEffects` accesses `ctx._player_field` / `ctx._enemy_field` directly — Combat is always the ctx
- Enemy deck is `Array[Dictionary]` (card data dicts from EncounterDB), not card IDs. Legacy fallback builds random dicts from CardDB
- Token creatures have synthetic card_data created in `summon_token()`, not from CardDB
- MapView, Shop, Rest, Event all build UI programmatically; their .tscn files only have Background + script
- Card upgrades are tracked per deck index but not yet applied during combat card draw (draw pile uses card IDs)
