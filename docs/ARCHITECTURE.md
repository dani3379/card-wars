# Architecture boundaries

This is the implementation map for refactors. Gameplay behavior remains owned by
the existing scene controllers, but state, deterministic operations, static data,
generation, and draw-only components have explicit homes.

## Dependency direction

`scene controller -> domain/data object -> serializable state`

- Scene scripts may coordinate Nodes, signals, animation, audio, and transitions.
- Domain helpers may receive a scene as an explicit context, but must not discover
  it through the scene tree or store UI nodes in serializable state.
- Data files contain definitions only. They do not build controls or mutate a run.
- Draw-only controls may read display values, but do not decide combat outcomes.

## Current boundaries

- `scripts/state/CreatureInstance.gd` is the authoritative per-creature runtime
  model. It contains no Node, Resource, RID, Callable, or scene reference.
  `to_snapshot()` is the full versioned contract; `to_replication_snapshot()`
  excludes viewer-relative identity and already-folded attack components.
- `scripts/Card2D.gd` adapts `CreatureInstance` to input, signals, and rendering.
  Its old alternate full-card renderers are retired. Reusable draw-only pieces live
  under `scripts/ui/painters/`, including `PolyBadge.gd` and `StatGem.gd`.
- `scripts/combat/CombatOps.gd` owns combat-affecting random choices and explicit
  side routing. Solo seeds derive from run/encounter/floor; network seeds derive
  from the match and series game. Cosmetic shake, tilt, and emote variation may use
  Godot's global random helpers because they cannot change authoritative state.
- `scripts/net/CombatNet.gd` owns online orchestration while `Combat.gd` retains
  compatibility delegators and shared state. Board sync carries typed creature
  runtime snapshots with legacy freeze/stun/shield keys during migration.
- `scripts/data/EventDB.gd` owns event definitions. `scripts/scenes/Event.gd` owns
  gates, effect execution, controls, and presentation.
- `scripts/campaign/CampaignMapGenerator.gd` owns deterministic topology and map
  content assignment. `RunState.gd` owns persisted map data, navigation, and small
  diagnostic facades used by invariant probes.

## Refactor rules

1. Characterize behavior with a focused probe before moving high-branching code.
2. Keep save/network payloads versioned and Variant-only.
3. Route gameplay randomness through `CombatOps`; never add a global `randi()` or
   `randf()` call that can alter stats, targets, drops, placement, or generated IDs.
4. Add gameplay creature flags to `CreatureInstance`, not Node metadata. Metadata
   remains acceptable for presentation-owned references and animation dimensions.
5. Put new static event definitions in `EventDB` and map-generation rules in
   `CampaignMapGenerator`; scene scripts consume them through stable facades.
6. Preserve local ownership/view transforms at network boundaries. Do not blindly
   apply host-relative lane, side, or folded attack state on a client.

## Verification

- Run the strict save-isolated release gate (parse, copy, and event-art probes):
  `powershell -ExecutionPolicy Bypass -File tools/run_safe_probes.ps1 -GodotPath <path-to-Godot-console.exe>`
  The runner requires exit code 0 plus a probe sentinel, rejects Godot errors,
  enforces a timeout, and redirects `user://` to a temporary test home.
- Parse the largest dependency surface:
  `Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" --editor --quit-after 5 res://scenes/combat.tscn`
- Typed state: `tools/_probe_creature_instance.gd`
- Determinism and side routing: `tools/_probe_combat_ops.gd`
- Map generation: `tools/_probe_map_longer.gd`
- Event definitions/effects: `tools/_probe_events.gd`
- Combat content and network parity: `tools/_probe_lane_slate.gd`,
  `tools/_probe_type_keystones.gd`, and `tools/_probe_net_effect_audit.gd`
- Resource/cache contract: `tools/_probe_perf_pass.gd`
