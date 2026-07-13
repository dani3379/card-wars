# Map Board Art Spec — Midjourney asset plan for the hex war-board

*(2026-07-11. Companion to the `MapHexProto.gd` prototype. This is the
"ceiling-breaker" tier identified in the reference study: procedural vectors
are maxed; the remaining gap vs Banner Saga / Curious Expedition 2 /
Inscryption is authored painted surfaces.)*

## 1. The look we are buying

The board keeps its physical fiction — discrete beveled tiles on a carved
plinth on the war table, pewter site pieces, amber = reachable, crimson =
General. What changes: **tile faces become windows into oil-painted terrain
materials**, and **the three landmarks become painted illustrations**. The
finished screen should read as a hand-painted wooden campaign game
photographed under candlelight.

Why this works where "paint the whole map" would not: the run layout is
procedural (per-seed causeway), so a single painted map is impossible — but
because our tiles are *supposed* to be discrete pieces, we never need
edge-matched terrain transitions (the hard problem CE2 solves with authored
transition sets). Each tile clips its face from anywhere inside a seamless
material painting. Seams are diegetic: they're the tile borders.

## 2. Asset manifest (12 images, one MJ session)

### A. Terrain materials — 7 seamless squares, 2048×2048

Authored **neutral-warm**; the engine multiplies act staging, value falloff,
and per-tile jitter on top, so one set serves all three acts.

Copy-paste prompts (one per file; `--tile` needs a model version that
supports it — add `--v 6.1` if the default rejects it). `--no` blocks the
usual texture-prompt failures: horizons, vignettes, stray objects.

`terrain_meadow.png`
> flat top-down view of dry golden meadow grass, sun-bleached late-summer stalks, a few tiny faded wildflowers, seamless repeating ground texture, hand-painted thick oil paint, visible impasto brushstrokes, muted warm sepia-toned palette, dark fantasy board game terrain material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no objects, animals, figures, buildings, roads, border, frame, vignette, text, watermark, sky, horizon

`terrain_field.png`
> flat top-down view of ploughed farmland, parallel furrow rows of dark turned soil with dry wheat stubble, seamless repeating ground texture, hand-painted thick oil paint, visible impasto brushstrokes, muted warm sepia-toned palette, dark fantasy board game terrain material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no objects, animals, figures, buildings, roads, border, frame, vignette, text, watermark, sky, horizon

`terrain_woods.png`
> flat top-down view of a dark pine forest floor, deep green moss, fallen brown needles, thin roots and small ferns, seamless repeating ground texture, hand-painted thick oil paint, visible impasto brushstrokes, muted warm palette with deep greens, dark fantasy board game terrain material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no trees seen from the side, objects, animals, figures, border, frame, vignette, text, watermark, sky, horizon

`terrain_hill.png`
> flat top-down view of rocky highland ground, weathered grey-brown stone slabs, scree pebbles, patches of pale lichen, seamless repeating ground texture, hand-painted thick oil paint, visible impasto brushstrokes, muted warm sepia-toned palette, dark fantasy board game terrain material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no objects, animals, figures, buildings, border, frame, vignette, text, watermark, sky, horizon

`terrain_ash.png`
> flat top-down view of a grey volcanic ash field, fine drifting ash, scattered bone-white flecks and small charcoal fragments, seamless repeating ground texture, hand-painted thick oil paint, visible impasto brushstrokes, muted grey-sepia palette, dark fantasy board game terrain material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no objects, bones, skulls, figures, buildings, border, frame, vignette, text, watermark, sky, horizon

`terrain_char.png`
> flat top-down view of charred black scorched earth, burnt cracked crust with faint dull ember glow deep in the cracks, seamless repeating ground texture, hand-painted thick oil paint, visible impasto brushstrokes, near-black palette with dim orange ember accents, dark fantasy board game terrain material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no flames, fire, smoke, objects, figures, border, frame, vignette, text, watermark, sky, horizon

`terrain_water.png`
> flat top-down view of dark still river water, deep teal-black surface with subtle painted ripple patterns, seamless repeating water texture, hand-painted thick oil paint, visible impasto brushstrokes, muted dark palette, dark fantasy board game material, even diffuse lighting, edge-to-edge detail, full frame --tile --ar 1:1 --no reflections of sky, boats, fish, objects, shore, rocks, border, frame, vignette, text, watermark, horizon

### B. Landmarks — 3-4 isolated illustrations, ~1024 tall

Copy-paste prompts. Light comes from the upper left (matches the tile
bevel lighting); solid white ground for clean keying.

`landmark_etna.png`
> hand-painted video game asset of a small erupting volcano with stepped black basalt tiers, glowing orange lava veins running down its flanks, a thin dark ash plume drifting to the upper left, a few floating embers, thick oil paint, visible brushstrokes, dark fantasy, muted warm palette, soft warm light from the upper left, three-quarter top-down view, single object centered, isolated on a plain solid white background --ar 4:5 --no scenery, ground plane, landscape, clouds, text, watermark, frame, border

`landmark_keep.png`
> hand-painted video game asset of a squat medieval fortress gatehouse, two crenellated dark stone towers, a closed iron portcullis over the gate, one crimson swallowtail banner, tiny warm lamplit arrow-slit windows, thick oil paint, visible brushstrokes, dark fantasy, muted warm palette, soft warm light from the upper left, three-quarter top-down view, single building centered, isolated on a plain solid white background --ar 4:5 --no scenery, ground plane, landscape, people, text, watermark, frame, border

`landmark_camp.png`
> hand-painted video game asset of a small medieval war camp, one large command tent flying a small amber swallowtail pennant, two smaller soldier tents, a few wooden palisade stakes, a tiny cookfire, one supply barrel, thick oil paint, visible brushstrokes, dark fantasy, muted warm palette, soft warm light from the upper left, three-quarter top-down view, compact cluster centered, isolated on a plain solid white background --ar 5:4 --no scenery, ground plane, landscape, people, horses, text, watermark, frame, border

`landmark_standee.png` *(optional)*
> hand-painted video game asset of a pewter miniature game piece, a cloaked banner-knight holding a spear with a small amber swallowtail pennant, standing on a round pewter base, painted metal with worn edges, thick oil paint, visible brushstrokes, dark fantasy, muted warm palette, soft warm light from the upper left, single miniature centered, isolated on a plain solid white background --ar 4:5 --no scenery, ground plane, base terrain, text, watermark, frame, border

White background → alpha via chroma/luminance key at import (see §4).
The current vector versions stay as fallbacks and as the sketch-fog forms.

### C. Table — 1 image, 2048×1152

`table_oak.png`
> vast dark aged oak war table surface seen from directly above, wide old planks with visible wood grain and a few dark knots, near-black warm brown wood, a soft warm candlelight glow rising from the lower left corner, thick oil paint, visible brushstrokes, edge-to-edge, full frame --ar 16:9 --no objects, papers, maps, candles, hands, cups, text, watermark, border, vignette

Replaces the procedural planks; the knot/grain/prop drawing stays on top.

**Not in v1:** painted site-device icons (the forged vector devices are
legible and stylistically consistent; revisit only if the painted terrain
makes them feel thin) and painted sketch-fog paper (we already own
`assets/backgrounds/map_parchment.jpg` — fogged tiles clip from it).

## 3. File conventions

Drop into `assets/map_board/` with the names above. **PNG-wins**: the
engine checks for each file at load and falls back to the current
procedural painter when absent — art can land one file at a time, in any
order, and the board upgrades piecewise (same convention as event art and
card art).

## 4. Engine integration (all in the tile painter — one seam)

1. Loader: `_tex_for_biome(biome) -> Texture2D` (null → procedural fill).
   Preload via the ScenePreload pattern at port time.
2. Tile face: `draw_colored_polygon(corners, tint, uvs, tex)` — UVs map the
   hex corners into a seeded sub-rect (`_h(key)` offset, hex ≈ 20% of the
   painting, wrap allowed because the material is seamless). `tint` =
   act-staging tint × value falloff × jitter — every existing system
   survives as a multiplier over the texture.
3. Micro-decor: drop the flat marks the paintings replace (grass ticks,
   furrow lines, ash flecks); KEEP the standing props (pines, peaks, dead
   trees, haystacks) — they give the diorama read over the painted ground.
4. Landmarks: `draw_texture_rect` at the existing anchors + the existing
   cast shadows; the glow layer's crater/window blooms already sit on those
   anchors. Alpha key: white-bg keying script at import (one-time; write it
   when the first asset lands).
5. Water: painted face + existing recess/foam/glint/shimmer on top.
6. Sketch fog: clip `map_parchment.jpg` into fogged faces; ink work
   unchanged. Zero new assets.

## 5. Order of work + risk control

1. Generate `terrain_meadow` + `terrain_char` first (the two extremes),
   wire the loader, shoot the contact sheet (`tools/_shot_hex_proto.tscn`)
   — this proves texel density, palette fit, and the tint math before the
   other ten images are spent.
2. Then the remaining terrains, then landmarks, then the table.
3. Style drift → generate everything in one session with the shared
   suffixes; reroll outliers; judge only in-engine (the harness makes each
   check a 90-second loop).
4. Palette clash → assets are neutral-warm by construction; the engine
   owns final color. If an asset fights the register anyway, desaturate at
   import rather than re-prompting.
