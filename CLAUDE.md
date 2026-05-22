# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Burning Meadow" — a lane combat roguelike deckbuilder built in Godot 4.6 (gl_compatibility renderer, 2D). Inspired by Card Wars (combat) and Slay the Spire (roguelike structure). 4 lanes × 2 rows per side (front/back), simultaneous combat with Swift pre-phase, floop, sacrifice, spells. 3 acts with branching maps, shop/rest/event nodes, premade encounter lineups with fight passives.

## Running the project

Open in Godot 4.6+ and press F5. Main scene is `scenes/main_menu.tscn`. No build step, no tests, no CLI tooling.

For headless parse-checks during development: `Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" --editor --quit-after 5 res://scenes/combat.tscn` — opens combat.tscn in the headless editor, which force-compiles Combat.gd and Card2D.gd. Any parse errors print to stderr.

## Architecture

### Scene flow

`MainMenu → (StartingRelicPick) → MapView → Combat/Shop/Rest/Event → Reward → MapView → ... → Combat (boss) → GameOver`

Scene transitions use `get_tree().change_scene_to_file()`. Each scene is a `.tscn` in `scenes/` with a matching script in `scripts/scenes/`. Starting relic selection runs from MainMenu before the first map appears, building UI programmatically over the menu background.

### Autoload singletons

- **RunState** (`scripts/state/RunState.gd`) — current run state: HP, deck, relics, gold, potions, map data, card upgrades, `phoenix_heart_consumed`. `get_act()` returns 1-3. `start_new_run(starting_relic_id := "")` resets and generates map; grants the chosen starting relic. `get_current_act_map()` / `get_available_nodes()` / `visit_node()` for map navigation. Card upgrades tracked per deck index via `deck_uid`: `upgrade_card(uid, path, keyword)`, `get_upgraded_card_data(uid)`.
- **MetaState** (`scripts/state/MetaState.gd`) — cross-run persistence: win/loss counts. Saved as JSON to `user://meta.save`.
- **CardDB** (`scripts/data/CardDB.gd`) — 152 total card entries: ~104 draftable (starter + common + uncommon + rare) + 18 enemy-only + tokens/curses. Card types: "creature" (ATK/HP/keywords) and "spell" (spell effect + targeting). `roll_card_reward(act, is_elite, is_boss)` for rarity-weighted picks.
- **RelicDB** (`scripts/data/RelicDB.gd`) — 56 relics across tiers (starting, combat, utility, including 4x4-specific relics like Vanguard Banner / Rear Guard Charm). Each has hooks, effect ID, and value.
- **KeywordEffects** (`scripts/data/KeywordEffects.gd`) — 16 keywords from design doc. Dispatchers: `dispatch_on_enter`, `dispatch_on_death`, `dispatch_start_of_round`. On-enter types include: damage_opposing, damage_random_player, damage_all_enemies, draw, gain_gold, damage_face, debuff_opposing_atk, discard_random, copy_friendly, copy_opposing_keywords, copy_last_dead, look_top, cast_random_spell. On-death types: damage_opposing_lane, damage_all_enemies, summon, bonus_mana, damage_face, debuff_all_player_atk, damage_adjacent.
- **EncounterDB** (`scripts/data/EncounterDB.gd`) — 26 premade fight lineups across 3 acts. Each encounter has ordered creature deck, reinforcement, HP, and optional fight passive. `REACTIVE_PASSIVES` dictionary defines per-encounter reactive triggers (e.g. `necromancer_tower` doubles enemy on_death via `_dispatch_reactive("ON_CREATURE_DEATH", ...)`). `build_enemy_deck(id)` returns Array[Dictionary] of card data. `get_reinforcement(id)` for infinite backup creature.
- **AudioBank** (`scripts/AudioBank.gd`) — central SFX/music dispatcher: `play_sfx(name)`, `play_music(name)`. Used throughout combat for hit/death/victory cues.
- **CardTextureCache** (`scripts/CardTextureCache.gd`) — preloads card frames/art textures to avoid per-card disk reads.
- **GameTheme** (`scripts/GameTheme.gd`) — fonts, colors, panel styles, and the enemy-name→art-alias map (`scripts/GameTheme.gd:1068`).

### Combat scene (`scripts/scenes/Combat.gd`)

Largest file (~4,500 lines). Core systems:
- **Round flow**: draw 4 → player plays creatures/spells, toggles floop, sacrifices, banks ≤1 mana → resolve floops → Swift phase → simultaneous combat (both rows attack each turn; front attacks first and is attacked first — back row is queue space, not a separate combat tier) → deaths/on-death → discard hand → enemy places creatures (escalates at `ESCALATION_REINFORCE_ROUND`) → passives → new round. Round 1 is setup only (no combat).
- **Board (4×4)**: `_player_field[4]` and `_player_back[4]`, mirrored `_enemy_field[4]` / `_enemy_back[4]`. `_row_array(is_enemy, row)` is the canonical accessor; `ROW_FRONT = 0`, `ROW_BACK = 1`. `_all_creatures_both_sides()` iterates everything.
- **Enemy deck**: `Array[Dictionary]` of card data, loaded from EncounterDB or built from legacy random pool. `_place_enemy_card(data, lane)` creates Card2D from card data dict directly.
- **Spells**: targeted spells enter `_targeting_spell` mode (click to resolve). Non-targeted resolve immediately. Exhaust pile separate from discard. `_last_spell_played_this_turn` enables Echo. `_auto_target_for(card_data)` picks a sensible target for self-resolving spells (used by Chaos Imp / Echo / Reposition fallback).
- **Sacrifice**: once per turn, free action. Triggers on-death. [S] key or HUD button. Arms `_butchers_cleaver_armed` if Butcher's Cleaver is held.
- **Floop**: creatures with floop can toggle `will_floop`. Types include damage_any, summon_random, kill_adjacent_summon, steal_atk, heal_all_friendly, summon_token, redirect_adjacent, copy_opposing_floop, swap_atk, become_copy, drain, etc.
- **Keywords**: Armored (-1 dmg), Swift (pre-phase), Thorns (1 back), Piercing (excess → face), Last Stand (survive once at 1 HP), Ranged (random target, prefers back row), Regenerate/Wither (start of round). Royal Guard passive grants adjacent-friendly -1 dmg and gains +1 ATK when hit (in addition to its redirect floop).
- **Encounter passives**: `_dispatch_passive_start_of_round()`, `_dispatch_passive_end_of_round()`, `_dispatch_encounter_on_enemy_death()`, `_dispatch_encounter_on_player_death()`, `_dispatch_encounter_on_enter()`. `_has_encounter_passive_keyword(card, kw)` grants piercing/thorns/armored to enemy creatures based on encounter passive ID.
- **Reactive passives**: `_dispatch_reactive(trigger, source_card, lane_idx)` fires per encounter's `REACTIVE_PASSIVES` entry. Triggers: ON_PLAYER_SPELL, ON_PLAYER_SACRIFICE, ON_PLAYER_FLOOP, ON_PLAYER_SUMMON, ON_CREATURE_DEATH, ON_PLAYER_DRAW.
- **Relic effects**: checked inline via `_has_relic()`. Major hooks: combat_start, turn_start, creature_played, hero_damaged, creature_death, sacrifice, bonus_draw, combat_end.
- **HUD**: built programmatically. Shows encounter name and passive description. Parchment-styled panels, screen shake via CanvasLayer offset.

### Map system

RunState generates a branching map per act: 15 rows tall × up to 7 columns wide. `BOSS_ROW = 14` (last row); elites/rest unlock at `MIN_ELITE_ROW = 5`; combat-only floor for early rows. Connections link each node to 1-3 nodes in the next row. MapView renders nodes as color-coded buttons with Line2D connections, highlights available nodes with gold borders.

### Card upgrade system

Three upgrade paths applied at rest sites:
- **Sharpen**: +2 ATK (creature) or +2 spell damage (spell)
- **Fortify**: +2 HP (creature) or -1 mana cost (spell)
- **Imbue**: add keyword from [piercing, swift, thorns, regenerate] (creature) or Retain/Double+Exhaust (spell)

Upgrades tracked in `RunState.card_upgrades` keyed by `deck_uid`. `get_upgraded_card_data(uid)` returns modified card data. **Upgrades are applied at draw time in Combat** via the `deck_uid → card_data` lookup — drawing a card looks up its uid and uses the upgraded data dict.

### Card2D (`scripts/Card2D.gd`)

PanelContainer-based card (~4,000 lines, includes pixel-measured frame layout). Supports creatures (ATK/HP display) and spells (SPELL label, no stats). Drag from hand above play threshold to play. Battlefield creatures show floop indicator. `take_damage()` handles Armored and Last Stand. `temp_atk_buff` for this-turn buffs; `persistent_atk_buff` + `persistent_atk_buff_rounds` for multi-round buffs (Butcher's Cleaver). `effective_atk()` is the canonical "what's my real ATK right now" — always prefer it over raw `current_atk + temp_atk_buff` reads.

### Card data schema

Creatures: `id, name, type:"creature", cost, atk, hp, rarity, keywords[], desc`. Optional: `on_enter{}, on_death{}, floop{}, adj_buff{atk,hp}, wither:int, passive:String, extra_damage:int`.

Spells: `id, name, type:"spell", cost, rarity, keywords[], desc, spell{type,value,...}, targeting:String`. Targeting: "enemy_creature", "friendly_creature", "any_creature", "any", "none".

### Adding content

- **New card**: add to `CardDB.CARD_POOL`. Include all fields per schema above.
- **New relic**: add to `RelicDB.RELICS`, implement effect check in Combat.gd.
- **New keyword**: add to `KeywordEffects.KEYWORDS`, implement in dispatchers, add to Card2D display.
- **New spell type**: add `spell.type` handler in Combat.gd `_resolve_spell()` or `_resolve_custom_spell()`.
- **New encounter**: add to `EncounterDB.ENCOUNTERS` with name, act, type, hp, passive_id, passive_desc, deck, reinforcement. Add passive handler to Combat.gd if passive_id is non-empty. Optional reactive passive: add to `REACTIVE_PASSIVES` and handler case in `_dispatch_reactive`.
- **New event**: add to `Event.gd` EVENTS dictionary with name, desc, choices with effects.

## Key constants

- Player HP: 25
- Mana: starts at 3/turn (`base_max_mana`); can grow via relics. Up to 1 banked carryover by default (Ice Cream relic uncaps banking).
- Hand draw: 4/turn (HAND_DRAW_PER_TURN), max hand: 10
- 3 acts. Map: 15 rows × ≤7 columns. Boss at row 14, elites/rest start row 5.
- Lanes: 4 per row × 2 rows per side (front/back) = 8 slots per side.
- Card rarities: "starter", "common", "uncommon", "rare", "enemy"
- Shop prices: common 50g, uncommon 75g, rare 120g, relic 100g, potion 40g, removal 50g
- Potion heals 8 HP, max 3 potions

## Gotchas

- Combat.gd builds all HUD in code, not in the scene editor
- Spell targeting uses `_input()` override, not the card drag system
- `KeywordEffects` accesses combat state via the ctx (Combat instance) directly — Combat is always the ctx
- Enemy deck is `Array[Dictionary]` (card data dicts from EncounterDB), not card IDs. Legacy fallback builds random dicts from CardDB
- Token creatures have synthetic card_data created in `summon_token()`, not from CardDB
- MapView, Shop, Rest, Event, and the starting-relic-pick screen all build UI programmatically; their `.tscn` files only have Background + script
- `current_atk + temp_atk_buff` should never be read directly — always go through `card.effective_atk()` so `persistent_atk_buff` (Butcher's Cleaver) is included
- Reactive `double_on_death` re-runs the dying enemy's on_death effect directly via `KeywordEffects._run_on_death(...)` to avoid recursion through `dispatch_on_death → _dispatch_reactive`
- `_short_pause(duration)` is a real timer-based pause (uses `create_timer().timeout`) — the parameter is honored, not ignored

## Card text positioning (Card2D v3 layout)

Text on cards (cost, name, type, description, ATK, HP, FLOOP) is positioned by **pixel-measured POINT_* constants** in [scripts/Card2D.gd](scripts/Card2D.gd), each pointing at the center of a painted region in the 300×400 source frame texture.

**To tune or re-derive these positions, run:**

```
python tools/measure_frame.py
```

It scans `assets/frames/frame_creature_common.png` pixel-by-pixel — looking for the red orb's bright-red core, the banner's dark-gray interior, the gold divider scroll, the tan parchment well, etc. — and prints a copy-pasteable block of `POINT_* := Vector2(...)` constants with the bbox center of each region. Replace the matching constants in `Card2D._build_full_layout_v3`'s header.

**Eyeballing positions does not work.** Earlier attempts had `POINT_NAME` 20px above the actual painted banner because the banner's gold trim above the dark interior visually fooled the measurement. The script reads pixel values directly, so it can't be fooled the same way.

**Layout uses point-anchored centering, not anchor rects.** The helper `_center_at_point(label, point, size)` anchors a label to a single point with symmetric `offset_left/right/top/bottom = ±size/2`. This avoids two Godot quirks: (1) `Label.vertical_alignment = CENTER` misaligns when the rect is smaller than the font's line box; (2) asymmetric anchor rects make `horizontal_alignment = CENTER` compute the visual midpoint inconsistently. POINT_* is "where the center goes," SIZE_* is "how much room the label gets" — keep SIZE_* generous (≥36px tall) so Godot's centering works.

**Font setup** lives in [scripts/GameTheme.gd](scripts/GameTheme.gd) `_load_assets()`. Three fonts:
- `font_display` — Cinzel Variable wrapped in FontVariation with `wght: 600` (SemiBold) for names, type, FLOOP
- `font_stat` — same Cinzel but `wght: 800` (Black) for cost / ATK / HP numerals — matches AAA card-game stat-orb conventions (Hearthstone, MtG Arena)
- `font_body` — Nunito Regular for descriptions

Both Cinzel variations set `spacing_bottom = -3` to optically center caps-only text (caps don't use descender space, so geometric center renders ~1.5px high). If text still looks high, increase the negative value; if low, push toward 0.
