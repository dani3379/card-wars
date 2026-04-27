# Card Wars — Phase 2 prototype

This is the foundation scene: a tilted 3D table, a real candle with a real point light, drifting embers, dust motes lit by the candle, and a hand of three cards you can hover, drag, and play.

## How to run it

1. Install Godot 4.3 or later from https://godotengine.org (free, no account needed)
2. Open Godot, click "Import" and select this folder's `project.godot`
3. Press F5 (Run). The first run asks you to set a main scene — `play_area.tscn` is already set in `project.godot` so it should just go.

## What you should feel when it runs

- Camera idles with subtle drift, follows your mouse a bit. The scene feels like a head, not a viewport.
- The candle flame flickers, casts warm orange light on the table.
- Cards in your hand breathe slightly out of phase. Hover one — it lifts toward you and tilts to face you, with a soft warm glow underneath.
- Click and drag a card. Pull it toward the center of the table and release. It arcs forward, flips face-down, lands with a small scale pop.
- Embers drift up from the candle. Dust motes drift through the warm light.

If any of those feels wrong, tweak the constants at the top of `Card.gd` and `PlayArea.gd`. Those constants are the "feel" — `HOVER_LIFT`, `HOVER_LIFT_TIME`, `BREATH_AMPLITUDE`, `CAMERA_DRIFT_AMPLITUDE`, `CANDLE_FLICKER_AMOUNT`. Tune them obsessively until it feels right.

## Free assets to grab next

The prototype currently uses placeholder colors. To make it look like the grimoire scene we mocked up, you need:

**Wood texture for the table** (highest priority — placeholder flat brown reads as plastic):
- Poly Haven: https://polyhaven.com/textures/wood — search "dark wood planks", grab the 2K albedo + normal map
- Drop the files into `textures/` and uncomment the texture lines in `play_area.tscn`

**Candle model** (current candle is a cylinder, fine for prototype, swap for real model later):
- Sketchfab, filter by CC0 license, search "candle"
- Or model one yourself in Blender — 30 minutes, two cylinders and a cone

**Card art textures** (the SVG cards we built):
- Render each card SVG to a 512x768 PNG
- Drop into `textures/cards/` named `<card_id>.png` (e.g. `deaths_head_moth.png`)
- The Card script auto-loads them by `card_id`

**SFX** for hover, play, draw, candle crackle:
- Freesound.org, filter by CC0
- Search "paper rustle", "card flip", "candle crackle"
- Add an AudioStreamPlayer3D node to Card.tscn and play on hover/play events

**Font** for card text and HUD:
- Google Fonts: Cormorant Garamond, EB Garamond, or IM Fell English
- Drop the .ttf into `fonts/`, set as default theme font

## What's next (phases from earlier)

- Phase 3: card system from config files (currently hardcoded in PlayArea._ready)
- Phase 4: opponent across the table, intent display, basic combat resolution
- Phase 5: polish loop — particles on play resolve, screen shake, hit flashes, audio

## Architecture notes

- `PlayArea.gd` is the orchestrator. It owns the hand, spawns cards, manages camera/lighting/global state.
- `Card.gd` owns its own animation state. The "feel" lives in its constants.
- `Atmosphere.gd` owns ambient particles. All particle config is procedural so you can tweak parameters without poking the editor.
- Scenes (`.tscn`) are the visual layout; scripts (`.gd`) are behavior. This separation matches Godot's idiom — keep visual changes in the editor, keep logic in code.

## Performance notes

- All particles use GPUParticles3D — GPU-driven, near-zero CPU cost
- Card meshes are simple boxes (12 triangles each). Hand of 5 cards = 60 triangles.
- Hover glow uses real OmniLight3D — Forward+ renderer handles dozens of lights cheaply
- Shadow casting on the candle's point light is enabled but with low resolution to stay fast
- Tested target: 60fps on a 5-year-old laptop. If it stutters, drop `msaa_3d` to 0 in project.godot.
