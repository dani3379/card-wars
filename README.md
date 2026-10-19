# Burning Meadow

A **Godot 4.6 / GDScript card-game prototype** combining tactical lane battles with a branching roguelike campaign. Build a deck, position creatures across four lanes with front and back rows, and combine spells, creature effects, keywords, and relics.

The code offers concrete examples of turn-based gameplay rules, seeded campaign generation, persistent game state, and multiplayer message handling—the kinds of systems involved in custom card-game and strategy-game prototypes. This repository is a curated October 2026 development snapshot. The checks below verify selected contracts and script loading; full campaign and multiplayer acceptance testing remain outstanding.

## Game systems present

- A three-act branching campaign with hero selection, encounters, rewards, shops, rest stops, recruitment, and events.
- Seeded run generation, daily/custom-seed options, card upgrades, relics, potions, and progression.
- Phased lane battles with Swift attacks, front/back rows, spells, triggered creature effects, and encounter-specific rules.
- Three save slots with schema/version checks and backup-file handling, plus player settings, collection/help screens, audio, and in-game credits.
- A separate Skirmish implementation with host-authoritative networking and draft/constructed/quick/sealed flows.

Campaign battles and the Sealed Skirmish battle style resolve lane attacks in sequence while deferring deaths so eligible creatures can trade blows. Swift resolves in an earlier phase. Alternating Skirmish uses the active side's attack pass with defender counterstrikes. The term “simultaneous combat” in older design notes refers to mutual-trade resolution within those specific passes.

The bundled default relay address is empty; a relay requires separate configuration. The publication checks did not exercise multiplayer transport, a two-player session, balance, or a complete campaign playthrough.

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
| Seeded campaign maps | `scripts/campaign/CampaignMapGenerator.gd` |
| Deterministic combat helpers | `scripts/combat/CombatOps.gd` |
| Runtime creature snapshots | `scripts/state/CreatureInstance.gd` |
| Run state and save handling | `scripts/state/RunState.gd`, `scripts/state/SaveIO.gd` |
| Card/relic/encounter registries | `scripts/data/` |
| Network messages and match state | `scripts/net/` |
| Recovered regression probes | `tools/` |

`Combat.gd` remains a large controller. Extracted helper/state modules and probes are useful examples of system boundaries; they do not imply that the entire game has been refactored or exhaustively tested.

## Verification

The recorded checks were run on **18 October 2026** with Godot **4.6.2 stable** compared against the official release. They completed asset import, checked 129 production scripts, and passed eight combat-helper checks plus nine creature-state snapshot checks. Saves and settings were isolated from the player's normal data. [Validation notes](docs/PUBLICATION_VALIDATION.md) record the commands, evidence, and limits.

Two focused contract probes can be run after import:

```text
godot --headless --path . --script res://tools/_probe_combat_ops.gd
godot --headless --path . --script res://tools/_probe_creature_instance.gd
```

The included PowerShell `tools/run_safe_probes.ps1` runs a larger selected set with timeouts and isolated Windows `APPDATA`. It requires an installed engine passed through `-GodotPath` or `GODOT_BIN`. Refer to the validation notes before interpreting any probe as evidence of game-wide readiness.

## Credits and publication scope

Keep [CREDITS.md](CREDITS.md), [third-party notices](THIRD_PARTY_LICENSES.txt), the per-track/per-pack ledgers, and the in-game Credits screen with distributions. Third-party art, icons, fonts, sound, and music retain their own notices.

The snapshot excludes engine executables, transfer/history/save backups, external-game references, source asset ZIPs, generated import caches, and local credentials. Its original-code license and some per-image provenance records remain unresolved; no blanket license or authorship claim has been invented. See [PROVENANCE.md](PROVENANCE.md).

Inherited contributor notes in `AGENTS.md` and design documents in `docs/` are development records. Their dates, counts, and plans can differ from what is implemented in this snapshot.
