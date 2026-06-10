# Burning Meadow

A lane-combat roguelike deckbuilder built in **Godot 4.6** (2D, GL Compatibility renderer). Inspired by *Card Wars* (combat) and *Slay the Spire* (roguelike structure).

Pick one of five heroes and fight through three branching acts — placing creatures across a 4-lane, 2-row battlefield, casting spells, and resolving simultaneous combat each round — toward each act's boss. Draft cards, collect relics, manage your deck, and survive.

## Running it

1. Install **Godot 4.6** or newer (standard build — no C#/Mono required) from https://godotengine.org
2. Launch Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** to play. Main scene: `scenes/main_menu.tscn`.

No build step, no external dependencies.

## At a glance

- **Board:** 4 lanes × 2 rows (front/back) per side — 8 slots each.
- **Heroes:** 5 playable, each a distinct archetype + signature relic.
- **Structure:** 3 acts, branching maps with combat / elite / boss / shop / rest / event / treasure nodes.
- **Content:** 150+ cards, 130+ relics, 40+ encounters, 40+ events, potions, mutators, ascension difficulty tiers, plus daily & custom-seed runs.
- **Saves:** 3 slots with mid-run resume.

## Combat in one breath

Draw 4 → play creatures/spells and spend mana (bank up to 2) → toggle *floop* abilities → Swift pre-phase → simultaneous combat (both rows attack; front strikes and is struck first) → deaths & on-death effects → enemy reinforces → next round. Round 1 is setup only.

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
- [`docs/CONQUEST_REDESIGN.md`](docs/CONQUEST_REDESIGN.md) — the planned "Successor Wars" faction/conquest redesign.
- [`CREDITS.md`](CREDITS.md) — asset attributions.

## Credits & license

Art and audio combine public-domain master paintings, CC0 assets (Kenney, OpenGameArt), and CC-BY 3.0 assets (game-icons.net, pbmojART, and J. W. Bjerk's *Painterly Spell Icons*) — see [`CREDITS.md`](CREDITS.md) and the in-game Credits screen. Built on the Godot Engine (MIT).
