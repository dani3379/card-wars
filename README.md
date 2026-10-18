# Burning Meadow

A 2D lane-combat roguelike deckbuilder built with **Godot 4.6 and GDScript**. Build a deck over a branching campaign, place creatures across four lanes with front and back rows, and combine spells, activated abilities, keywords, and relic effects.

This repository is a curated development snapshot from the October 2026 project archive. It demonstrates game systems and tools; it is not a finished commercial release or a claim that every game mode has passed release testing.

## Game systems present

- A three-act branching campaign with hero selection, encounters, rewards, shops, rest stops, recruitment, and events.
- Seeded run generation, daily/custom-seed options, card upgrades, relics, potions, and progression.
- Simultaneous lane combat with front/back rows, spells, creature keywords, activated abilities, and encounter-specific rules.
- Save slots and recovery/versioning support, player settings, collection/help screens, audio, and in-game credits.
- A separate Skirmish implementation with host-authoritative networking and draft/constructed/quick/sealed flows.

Skirmish source is included, but no public relay is configured by this snapshot. Multiplayer transport, two-player interaction, balancing, and a complete campaign playthrough were not validated during this publication pass.

## Run locally

1. Install the standard **Godot 4.6.2 stable** editor from the [official release](https://github.com/godotengine/godot-builds/releases/tag/4.6.2-stable). The engine is not bundled in this repository.
2. Import `project.godot` in Godot and let the initial asset import finish.
3. Press **F5** to run the main scene, `scenes/main_menu.tscn`.

The project uses the GL Compatibility renderer and a 1600×900 stretched canvas. The asset set is sizeable, so the first import takes longer than subsequent opens. Godot stores player data through `user://`; personal saves and settings from the recovered archive are not included.

For a headless import using your own verified engine:

```text
godot --headless --path . --editor --import --quit
```

## Technical map

| Area | Main location |
|---|---|
| Screen and campaign flow | `scenes/`, `scripts/scenes/` |
| Combat orchestration | `scripts/scenes/Combat.gd` |
| Deterministic combat helpers | `scripts/combat/CombatOps.gd` |
| Runtime creature snapshots | `scripts/state/CreatureInstance.gd` |
| Run state and save handling | `scripts/state/` |
| Card/relic/encounter registries | `scripts/data/` |
| Network messages and match state | `scripts/net/` |
| Recovered regression probes | `tools/` |

`Combat.gd` remains a large controller. Extracted helper/state modules and probes are useful examples of system boundaries; they do not imply that the entire game has been refactored or exhaustively tested.

## Verification

The publication checks use an engine binary compared against the official Godot release. Saves and settings are isolated from the player's normal data. [Validation notes](docs/PUBLICATION_VALIDATION.md) record the exact checks and their outcomes.

Two focused contract probes can be run after import:

```text
godot --headless --path . --script res://tools/_probe_combat_ops.gd
godot --headless --path . --script res://tools/_probe_creature_instance.gd
```

The included PowerShell `tools/run_safe_probes.ps1` runs a larger selected set with timeouts and isolated Windows `APPDATA`. It requires an installed engine passed through `-GodotPath` or `GODOT_BIN`. Refer to the validation notes before interpreting any probe as evidence of game-wide readiness.

## Credits and publication scope

Keep [CREDITS.md](CREDITS.md), [third-party notices](THIRD_PARTY_LICENSES.txt), the per-track/per-pack ledgers, and the in-game Credits screen with distributions. Third-party art, icons, fonts, sound, and music retain their own notices.

The snapshot excludes engine executables, transfer/history/save backups, external-game references, source asset ZIPs, generated import caches, and local credentials. Its original-code license and some per-image provenance records remain unresolved; no blanket license or authorship claim has been invented. See [PROVENANCE.md](PROVENANCE.md).

Design and planning documents in `docs/` are development records. Their dates, counts, and plans can differ from what is implemented in this snapshot.
