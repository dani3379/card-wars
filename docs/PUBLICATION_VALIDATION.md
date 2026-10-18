# Publication verification

Verified on 18 October 2026, using Godot **4.6.2.stable.official.71f334935** on Windows.

## Engine authenticity

The official [Godot 4.6.2 release](https://github.com/godotengine/godot-builds/releases/tag/4.6.2-stable) Windows ZIP was downloaded for comparison. Its SHA-256 matched GitHub's release-asset digest, and its SHA-512 matched the vendor's `SHA512-SUMS.txt`. Both archived Windows executables matched their official ZIP members by SHA-256 before any execution. The engine and downloaded verification files are not part of this repository.

## Checks completed

All engine processes were hidden/headless. `APPDATA`, `LOCALAPPDATA`, and temporary directories were redirected to a task-specific review directory so normal player saves/settings were not used.

| Check | Result |
|---|---|
| Headless editor asset import | Exit 0, no reported engine/script errors |
| `tools/_probe_combat_ops.gd` | 8 contract checks passed: seeded choices, shuffle/IDs, hero/side routing, capped healing |
| `tools/_probe_creature_instance.gd` | 9 contract checks passed: snapshot version, state round-trip, replication ownership |
| `tools/_probe_parsecheck.tscn` | 129 production scripts checked; PASS; no engine/script errors |

The corresponding commands, after setting the isolated environment, were:

```text
Godot_v4.6.2-stable_win64_console.exe --headless --path <project> --editor --import --quit
Godot_v4.6.2-stable_win64_console.exe --headless --path <project> --script res://tools/_probe_combat_ops.gd
Godot_v4.6.2-stable_win64_console.exe --headless --path <project> --script res://tools/_probe_creature_instance.gd
Godot_v4.6.2-stable_win64_console.exe --headless --path <project> res://tools/_probe_parsecheck.tscn
```

These are the selected executed probes, not a claim that the entire `run_safe_probes.ps1` suite or every other historical tool was run.

## Static resource and notice checks

The pre-import scan covered 8,011 literal `res://` uses and 2,644 local UID definitions. It found no missing required literal scene/preload/project resource, no path-case mismatches, and no unresolved UID use. Dynamic path expressions were outside that check's resolution scope. A missing `enemy_general.png` is an explicit optional lookup with an existing `enemy_commander.png` fallback.

All 49 music filenames in `MUSIC_CREDITS.md` were present. The main credits, consolidated notices, and audio ledgers were retained. The two old painterly-pack README references were absent in the recovered source and are explicitly disclosed in `PROVENANCE.md` rather than described as bundled files.

The 150 compared runtime source/scene/resource files remained byte-identical to the recovered original; preparation did not change gameplay. Godot's generated import cache is ignored by Git.

## What these checks do not establish

No complete playthrough, windowed visual review, export/package test, two-player session, relay service, performance benchmark, or balance review was performed. Contract probes and parsing establish the checked behavior only. Source/asset ownership and redistribution permissions are a separate unresolved provenance task.
