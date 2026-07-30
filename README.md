# Burning Meadow

A lane-combat roguelike deckbuilder built in **Godot 4.6** (2D, GL Compatibility renderer). Inspired by *Card Wars* (combat) and *Slay the Spire* (roguelike structure).

Pick one of five claimants and march through three branching acts of the Successor Wars. Place creatures across a 4-lane, 2-row battlefield, cast spells, break rival Generals, recruit cards, and build a remembered warband for each act's keep.

## Running it

1. Install **Godot 4.6** or newer (standard build — no C#/Mono required) from https://godotengine.org
2. Launch Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** to play. Main scene: `scenes/main_menu.tscn`.

No build step, no external dependencies.

## At a glance

- **Board:** 4 lanes × 2 rows (front/back) per side — 8 slots each.
- **Heroes:** 5 playable, each a distinct archetype + signature relic.
- **Structure:** 3 acts, branching war roads with combat / General / keep / shop / rest / event / recruit / treasure stops.
- **Content:** 170+ cards, 130+ relics, 50+ encounters, dozens of events, potions, mutators, ascension rules, plus daily and custom-seed marches.
- **Saves:** 3 slots with mid-run resume.

## Combat in one breath

Refill your persistent hand to five → play creatures and spells by spending Command → mark unwanted cards for end-turn discard → choose creature abilities → resolve Swift → clash in every occupied lane → process deaths and enemy reinforcements → begin the next round. Combat happens in round 1; there is no consequence-free setup turn.

## Project layout

- `scenes/` — one `.tscn` per screen; most UI is built programmatically in code.
- `scripts/scenes/` — screen logic (Combat, MapView, Shop, Rest, Event, …).
- `scripts/data/` — content databases (CardDB, RelicDB, EncounterDB, HeroDB, KeywordEffects, …).
- `scripts/state/` — RunState, MetaState, and the save system.
- `assets/` — art (public-domain master card portraits, painterly spell icons, game-icons.net UI), fonts, audio.
- `tools/` — dev utilities (frame measurement, the screenshot probe).
- `docs/` — design & production documentation.

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — architecture overview & conventions.
- [`docs/COPY_STYLE.md`](docs/COPY_STYLE.md) — house style for all in-game text.
- [`docs/ROADMAP_TO_1.0.md`](docs/ROADMAP_TO_1.0.md) — the production plan to 1.0.
- [`docs/CONQUEST_REDESIGN.md`](docs/CONQUEST_REDESIGN.md) — the Successor Wars design specification and implementation history.
- [`CREDITS.md`](CREDITS.md) — asset attributions.

## Verification

Run the strict, save-isolated release checks from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_safe_probes.ps1 -GodotPath D:\games\Godot_v4.6.2-stable_win64_console.exe
```

The runner gives every probe a timeout, requires both exit code 0 and its success sentinel, rejects Godot parse/runtime errors, and redirects `user://` to a temporary test home. It does not touch production save slots.

## Credits & license

Art and audio combine public-domain paintings, CC0 assets, CC-BY 3.0 art, and CC-BY 3.0/4.0 music. See [`CREDITS.md`](CREDITS.md), [`THIRD_PARTY_LICENSES.txt`](THIRD_PARTY_LICENSES.txt), the music/SFX ledgers under `assets/audio/`, and the in-game Credits screen. Built on the Godot Engine (MIT).
