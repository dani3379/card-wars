# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Burning Meadow" — a lane combat roguelike deckbuilder built in Godot 4.6 (gl_compatibility renderer, 2D). Inspired by Card Wars (combat) and Slay the Spire (roguelike structure). 4 lanes × 2 rows per side (front/back), simultaneous combat with Swift pre-phase, floop, spells. 3 acts with branching maps, shop/rest/event nodes, premade encounter lineups with fight passives.

## Project status & planning docs

Production planning is underway. **The live source of truth is in `docs/` — trust it over this file or git history, which have drifted before:**
- [`docs/ROADMAP_TO_1.0.md`](docs/ROADMAP_TO_1.0.md) — master production plan: current-state inventory, ship-blockers, all workstreams, milestones (M0–M5), and a live status log at the top. **Start here to continue.**
- [`docs/CONQUEST_REDESIGN.md`](docs/CONQUEST_REDESIGN.md) — the planned "Successor Wars" faction/conquest redesign (fully specced, not yet built).
- [`docs/COPY_STYLE.md`](docs/COPY_STYLE.md) — house style for all player-facing text.

M0 ship-hygiene is **complete**; **no work past M0 should begin until the user picks a path (A / B / C) — see the roadmap's status log and §6.**

## Running the project

Open in Godot 4.6+ and press F5. Main scene is `scenes/main_menu.tscn`. No build step, no tests, no CLI tooling.

For headless parse-checks during development: `Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" --editor --quit-after 5 res://scenes/combat.tscn` — opens combat.tscn in the headless editor, which force-compiles Combat.gd and Card2D.gd. Any parse errors print to stderr.

## Architecture

### Scene flow

`MainMenu → (StartingRelicPick) → MapView → Combat/Shop/Rest/Event → Reward → MapView → ... → Combat (boss) → GameOver`

Scene transitions use `get_tree().change_scene_to_file()`. Each scene is a `.tscn` in `scenes/` with a matching script in `scripts/scenes/`. Starting relic selection runs from MainMenu before the first map appears, building UI programmatically over the menu background.

### Autoload singletons

- **RunState** (`scripts/state/RunState.gd`) — current run state: HP, deck, relics, gold, potions, map data, card upgrades, `phoenix_heart_consumed`. `get_act()` returns 1-3. `start_new_run(hero_id := "")` resets, builds the deck from `HeroDB`, adds the hero's signature relic, and generates the map. `get_current_act_map()` / `get_available_nodes()` / `visit_node()` for map navigation. Card upgrades tracked per deck index via `deck_uid`: `upgrade_card(uid, path, keyword)`, `get_upgraded_card_data(uid)`.
- **HeroDB** (`scripts/data/HeroDB.gd`) — 4 playable heroes (Raider/Stalwart/Acolyte/Pyromancer). Each entry has `deck` (10-card list of CardDB ids) and `relic` (id of a `tier:"starting"` RelicDB entry). Picked at the start of every run from MainMenu — replaces the old "pick 1 of 3 starting relics" screen.
- **MetaState** (`scripts/state/MetaState.gd`) — cross-run persistence: win/loss counts. Saved as JSON to `user://meta.save`.
- **CardDB** (`scripts/data/CardDB.gd`) — 154 total card entries: ~104 draftable (starter + common + uncommon + rare) + 18 enemy-only + tokens/curses. Card types: "creature" (ATK/HP/keywords) and "spell" (spell effect + targeting). `roll_card_reward(act, is_elite, is_boss)` for rarity-weighted picks.
- **RelicDB** (`scripts/data/RelicDB.gd`) — ~130 relics across tiers (starting, combat, utility, including 4x4-specific relics like Vanguard Banner / Rear Guard Charm). Each has hooks, effect ID, and value.
- **KeywordEffects** (`scripts/data/KeywordEffects.gd`) — 24 keywords. Dispatchers: `dispatch_on_enter`, `dispatch_on_death`, `dispatch_start_of_round`. On-enter types include: damage_opposing, damage_random_player, damage_all_enemies, draw, gain_gold, damage_face, debuff_opposing_atk, discard_random, copy_friendly, copy_opposing_keywords, copy_last_dead, look_top, cast_random_spell. On-death types: damage_opposing_lane, damage_all_enemies, summon, bonus_mana, damage_face, debuff_all_player_atk, damage_adjacent.
- **EncounterDB** (`scripts/data/EncounterDB.gd`) — 41 premade fight lineups across 3 acts. Each encounter has ordered creature deck, reinforcement, HP, and optional fight passive. `REACTIVE_PASSIVES` dictionary defines per-encounter reactive triggers (e.g. `necromancer_tower` doubles enemy on_death via `_dispatch_reactive("ON_CREATURE_DEATH", ...)`). `build_enemy_deck(id)` returns Array[Dictionary] of card data. `get_reinforcement(id)` for infinite backup creature.
- **AudioBank** (`scripts/AudioBank.gd`) — central SFX/music dispatcher: `play_sfx(name)`, `play_music(name)`. Used throughout combat for hit/death/victory cues.
- **CardTextureCache** (`scripts/CardTextureCache.gd`) — preloads card frames/art textures to avoid per-card disk reads.
- **GameTheme** (`scripts/GameTheme.gd`) — fonts, colors, panel styles, and the enemy-name→art-alias map (now `scripts/data/CardArtAliases.gd`).

### Combat scene (`scripts/scenes/Combat.gd`)

Largest file (~11,800 lines). Core systems:
- **Round flow**: draw 4 → player plays creatures/spells, toggles floop, banks ≤2 mana → resolve floops → Swift phase → simultaneous combat (both rows attack each turn; front attacks first and is attacked first — back row is queue space, not a separate combat tier) → deaths/on-death → discard hand → enemy places creatures (escalates at `ESCALATION_REINFORCE_ROUND`) → passives → new round. Round 1 is setup only (no combat).
- **Board (4×4)**: `_player_field[4]` and `_player_back[4]`, mirrored `_enemy_field[4]` / `_enemy_back[4]`. `_row_array(is_enemy, row)` is the canonical accessor; `ROW_FRONT = 0`, `ROW_BACK = 1`. `_all_creatures_both_sides()` iterates everything.
- **Enemy deck**: `Array[Dictionary]` of card data, loaded from EncounterDB or built from legacy random pool. `_place_enemy_card(data, lane)` creates Card2D from card data dict directly.
- **Spells**: targeted spells enter `_targeting_spell` mode (click to resolve). Non-targeted resolve immediately. Exhaust pile separate from discard. `_last_spell_played_this_turn` enables Echo. `_auto_target_for(card_data)` picks a sensible target for self-resolving spells (used by Chaos Imp / Echo / Reposition fallback).
- **Sacrifice**: NOT a free player action. The player cannot kill their own creatures on command. Sacrifice only happens via specific card effects: the `blood_sacrifice` floop ability, the Offering / Fuel the Pyre spells (target-friendly sacrifice via 999 damage), and any future card with the "sacrifice" keyword as its play cost. All three paths route through `_trigger_player_sacrifice(victim)` so Bone Pile, Butcher's Cleaver, Reaper's Scythe, and the `ON_PLAYER_SACRIFICE` reactive fire uniformly. Same model as Slay the Spire.
- **Floop**: creatures with floop can toggle `will_floop`. Types include damage_any, summon_random, kill_adjacent_summon, steal_atk, heal_all_friendly, summon_token, redirect_adjacent, copy_opposing_floop, swap_atk, become_copy, drain, blood_sacrifice, etc.
- **Keywords**: Armored (-1 dmg), Swift (pre-phase), Thorns (1 back), Piercing (excess → face), Last Stand (survive once at 1 HP), Ranged (random target, prefers back row), Regenerate/Wither (start of round). Royal Guard passive grants adjacent-friendly -1 dmg and gains +1 ATK when hit (in addition to its redirect floop).
- **Encounter passives**: `_dispatch_passive_start_of_round()`, `_dispatch_passive_end_of_round()`, `_dispatch_encounter_on_enemy_death()`, `_dispatch_encounter_on_player_death()`, `_dispatch_encounter_on_enter()`. `_has_encounter_passive_keyword(card, kw)` grants piercing/thorns/armored to enemy creatures based on encounter passive ID.
- **Reactive passives**: `_dispatch_reactive(trigger, source_card, lane_idx)` fires per encounter's `REACTIVE_PASSIVES` entry. Triggers: ON_PLAYER_SPELL, ON_PLAYER_SACRIFICE, ON_PLAYER_FLOOP, ON_PLAYER_SUMMON, ON_CREATURE_DEATH, ON_PLAYER_DRAW.
- **Relic effects**: checked inline via `_has_relic()`. Major hooks: combat_start, turn_start, creature_played, hero_damaged, creature_death, sacrifice, bonus_draw, combat_end.
- **HUD**: built programmatically. Shows encounter name and passive description. Parchment-styled panels, screen shake via CanvasLayer offset.

### Map system

RunState generates a branching map per act: 8 rows tall × up to 7 columns wide, 3 paths with a 3× merge bias (trunk road + branches). `BOSS_ROW = 7` (last row), `REST_ROW = 6`; elites/rest unlock at `MIN_ELITE_ROW = 3`; combat-only floor for early rows. An acceptance loop in `_generate_act_map` reseeds until the act has 11–15 sites — the count where the map reads as a campaign over terrain rather than a lattice.

The map screen is two layers: **MapTerrain** (`scripts/scenes/MapTerrain.gd`) draws the static campaign plate — hand-traced Sicily coastline, carved-groove roads, political province layer (capped ~240px from sites; farther land wears the run's rival-realm dyes — nearest-keep zones from `KEEP_LLS`, gold once their act is won), antique-chart furniture, per-act dressing. The campaign sweeps the island one leg per act — west landing → a keep in the northern passes → the southern grain country → Etna's foot — with each act's camp pitched where the last keep fell (`keep_lls` in `_read_run_map`; march spine is a camp→keep vector with lanes fanning perpendicular). Scorch is centered on `_etna_peak` (not the act's keep) and grows per act. **MapView** (`scripts/scenes/MapView.gd`) extends it with the game layer: invisible hover/click buttons over the painted site chips (tooltips carry encounter + mutator intel), node → scene flow, top HUD, deck viewer, per-act meta-relic pickers, and the return-to-map save checkpoint. `scenes/map_proto.tscn` renders MapTerrain alone (sandbox). HUD positions must derive from `size.x` — the stretch canvas is the 1600×900 project viewport, and hardcoded window-pixel x coordinates land off-canvas. The chart zooms/pans (wheel + drag; opens auto-focused on the army standard). Perf structure: the plate paints on `PlateItem` (child canvas item — every `_draw_*` plate function takes a target CanvasItem `tgt`; zoom/pan only move the item's transform), offscreen `bake_mode` clones collapse it to one 2× texture (geography per act, full plate per open), and `RunState.map_plate_cache` carries mesh + geo texture across opens within an act. The plate is frozen while on screen: per-frame animation belongs in `MapPulseOverlay`; new plate layers go in `PlateItem._draw`'s ink block (they bake in automatically). Gotcha: a zero-size Control is culled when its transform isn't identity — `_plate_item.size` must stay the real plate rect.

### Card upgrade system

Slay-the-Spire-style **"+" upgrades**: every draftable card has one hand-crafted upgraded version. Rest sites offer the "Forge +" action — the player picks a card, sees a before/after preview, and confirms. No path picking, no random rolls.

- Per-card upgrade deltas live in `CardDB.UPGRADES` (atk/hp/cost/value/keywords/sub-effect bumps, plus optional desc override). `CardDB.get_plus_upgrade(id)` returns the delta; `CardDB.is_upgradeable(id)` filters out curses.
- The upgrade is applied by `RunState._apply_upgrade` via the `"plus"` path → `_apply_plus_upgrade(data)` merges the delta into the card data and stamps `is_upgraded: true`.
- Custom-spell resolvers in `Combat.gd` read `dmg_bonus`, `slay_draw`, `extra_draw`, `extra_mana`, `ricochet_hits`, etc. from the merged card_data, so + versions actually hit harder / draw more / give more mana.
- A handful of creature passives (Royal Guard, Corpse Eater, Vengeance, Vampire Lord, Riteforge, Warchief) read `card_data.is_upgraded` directly and bump their tick value.
- Event-driven specialty upgrades — `butcher` (Butcher event), `mirror_twin` (Mirror event), `fortify_neg` (Debuff Starters event) — keep their dedicated paths in `_apply_upgrade` since they're story-coupled, not generic.

Upgrades are tracked in `RunState.card_upgrades` keyed by `deck_uid`. `get_upgraded_card_data(uid)` returns the modified data. **Upgrades are applied at draw time in Combat** via the `deck_uid → card_data` lookup — drawing a card looks up its uid and uses the upgraded data dict.

The Whetstone relic upgrades the "Reforge" rest banner to forge **two** cards instead of one (once per act).

### Card2D (`scripts/Card2D.gd`)

PanelContainer-based card (~5,400 lines, includes pixel-measured frame layout). Supports creatures (ATK/HP display) and spells (SPELL label, no stats). Drag from hand above play threshold to play. Battlefield creatures show floop indicator. `take_damage()` handles Armored and Last Stand. `temp_atk_buff` for this-turn buffs; `persistent_atk_buff` + `persistent_atk_buff_rounds` for multi-round buffs (Butcher's Cleaver). `effective_atk()` is the canonical "what's my real ATK right now" — always prefer it over raw `current_atk + temp_atk_buff` reads.

### Card data schema

Creatures: `id, name, type:"creature", cost, atk, hp, rarity, keywords[], desc`. Optional: `on_enter{}, on_death{}, floop{}, adj_buff{atk,hp}, wither:int, passive:String, extra_damage:int`.

Spells: `id, name, type:"spell", cost, rarity, keywords[], desc, spell{type,value,...}, targeting:String`. Targeting: "enemy_creature", "friendly_creature", "any_creature", "any", "none".

### Adding content

- **New card**: add to `CardDB.CARD_POOL` (include all fields per schema above) AND add a `CardDB.UPGRADES` entry for its "+" version. Missing UPGRADES entries get a default fallback (+1/+1 creature or -1 cost spell) so they still upgrade cleanly, but hand-crafted entries feel better.
- **New relic**: add to `RelicDB.RELICS`, implement effect check in Combat.gd.
- **New keyword**: add to `KeywordEffects.KEYWORDS`, implement in dispatchers, add to Card2D display.
- **New spell type**: add `spell.type` handler in Combat.gd `_resolve_spell()` or `_resolve_custom_spell()`. If you add a custom damage spell, declare `dmg_bonus` in its UPGRADES entry and add `+ plus_dmg` to the damage line in the resolver.
- **New encounter**: add to `EncounterDB.ENCOUNTERS` with name, act, type, hp, passive_id, passive_desc, deck, reinforcement. Add passive handler to Combat.gd if passive_id is non-empty. Optional reactive passive: add to `REACTIVE_PASSIVES` and handler case in `_dispatch_reactive`.
- **New event**: add to `Event.gd` EVENTS dictionary with name, desc, choices with effects.

## Key constants

- Player HP: 25
- Mana: starts at 3/turn (`base_max_mana`); can grow via relics. Up to 2 banked carryover by default (`MAX_BANKED_MANA`; Ice Cream relic uncaps banking).
- Hand draw: 4/turn (HAND_DRAW_PER_TURN), max hand: 10
- 3 acts. Map: 8 rows × ≤7 columns, 11–15 sites per act. Boss at row 7, elites/rest start row 3.
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
- MapView, Shop, Rest, Event, and the starting-relic-pick screen all build UI programmatically; their `.tscn` files only have Background + script (map.tscn has no Background at all — the MapTerrain plate is the background)
- `current_atk + temp_atk_buff` should never be read directly — always go through `card.effective_atk()` so `persistent_atk_buff` (Butcher's Cleaver) is included
- Reactive `double_on_death` re-runs the dying enemy's on_death effect directly via `KeywordEffects._run_on_death(...)` to avoid recursion through `dispatch_on_death → _dispatch_reactive`
- `_short_pause(duration)` is a real timer-based pause (uses `create_timer().timeout`) — the parameter is honored, not ignored

## Card layout (Card2D)

**The LIVE hand-card layout is `_build_chart_proto()` (v9 "illuminated writ", 2026-06-11)** — the card IS the campaign's aged parchment with the document furniture printed on it. The sheet itself is `WritLeaf` (seeded deckled silhouette — the contour ink and edge toast are drawn along the SAME wobbled path, so the organic edge never separates from its shading); interior ageing is the seeded `ParchmentPlate` painter (washes/foxing/fibers, clipped 3px inset). Furniture: per-rarity metal double rules over an ink keyline (bronze/silver/gold/pewter; curse = bone on murk-stained paper), art mounted big as an ink-matted gilt-filleted plate with metal plate-mark squares on its corners (nothing is ever pinned over the painting), the name on an `InkCartouche` — a swallowtail metal-edged banner — in gilt Cinzel (auto-shrinks long names), a faceted rarity gem set in an ink mount top-center, rules text written straight on the page in **Alegreya** (`GameTheme.font_card_body`, wght 500/760, scoped to cards only — HUD/menus keep Nunito) inside a hairline ink box with metal corner ticks (keyword gold is re-inked `#7a4f10` there — the tooltip gold `#e8b547` washes out on paper), keyword devices ink-stamped in the bottom margin, and stats as pressed wax seals (`WaxSeal` class — seeded irregular blob per card+stat). Battlefield tokens are `_build_compact_layout` in the same material kit (38px wax seals via the shared `_chart_seal`, 18px outlined numerals). **Geometry gotcha: the Card2D control is natively 225×300 — absolute offsets are real pixels; only `_center_at_point` maps the 300×400 design space** (where v6/v3 numbers like `(150, 213)` live). Cost/ATK/HP keep the historical 56px corner boxes so `_build_baked_overlay_layout` numerals land on them. A/B harnesses live in `tools/card_redesign_v6/` (`render_v7.tscn` = current, `render_cards.tscn` = v6/v3). Everything below describes the SUPERSEDED v3 painted-frame layout, kept for reference:

### Card text positioning (v3 layout — superseded)

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
