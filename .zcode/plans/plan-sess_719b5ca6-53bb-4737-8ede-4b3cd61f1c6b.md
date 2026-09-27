# Visual pass: close the real gaps, don't re-polish the polished

## What exploration found (why this plan is shaped this way)

Every "obvious" visual target turned out already built, recently and well:
- **Combat juice**: floating damage numbers with overkill-honesty, magnitude-scaled shake, hitstop/killing-blow holds, lunge/brace/recoil tweens, bespoke burn-the-writ death animation, sacrifice ashing, low-HP dread vignette — all reduce-motion- and anim_speed-aware.
- **GameOver/Reward**: ink-dry reveal tweens, run-end flourishes, settlement plaques.
- **Scene transitions**: an ink-veil system exists (`GameTheme.fade_out_then_change_scene` + `fade_in` bookends, UV-continuous ink, double-transition guard) — used by 9 scenes.

The genuinely open visual items are: (a) scenes NOT on the veil list (Event.gd, Combat.gd, MainMenu.gd — likely hard cuts), (b) the roadmap's owed act-2/3 faction-map render verification, (c) stand-in event art (blocked on user's art pipeline), and (d) whatever a rendered-gallery audit catches that code reading can't.

## Steps

1. **Close the transition veil gaps** (small, safe, universally felt):
   - Audit all 25 `change_scene_to_file` call sites against veil users.
   - Wire any hard-cut exits (expected: Event → MapView, Combat → GameOver/Reward/Map, GameOver → MainMenu) through `fade_out_then_change_scene`, respecting `UserSettings.reduce_motion` and the existing double-transition guard.
2. **Rendered gallery audit**: run the existing windowed harnesses (`tools/_shot_map_states.tscn` and the existing menu/combat shot tools) to capture every screen as PNG; inspect each against the house language (parchment/ink/gilt, one accent per moment); write a short ranked list of the weakest visuals with evidence.
3. **Fix the worst 1–3 audit findings** within token budget. Every fix follows the house pattern: tween-based, `Motion.time`-scaled, reduce-motion gated, headless gated, no blocking of game logic.
4. **Pay the map render debt**: capture the owed act-2/3 faction-skinned chart states; fix any visual defect they expose.
5. **Verify**: headless parse-check on all touched scripts; copy-lint probe if any player-facing text changed; before/after re-renders; summary of what changed with file:line references.

## Out of scope
- New painted art (needs your Midjourney files; I wire/crop/verify when they land — `plague_bell` icon and event stand-ins stay flagged).
- Bot learning: `scripts/combat/BotBrain.gd` + `BoardSim.gd` + `Personas.gd` (dated today) already implement the learns-from-mistakes loop (regret-scaled nudges, challenger/champion acceptance). The banked web research covers wiring/persistence next steps whenever you want that thread resumed.

## Token discipline
No more than 1 agent for the whole implementation (only if needed for verification); everything else via direct reads/greps and existing harnesses.