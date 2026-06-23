# Art Audit — Portraits & Backgrounds

Scope: `assets/portraits/` and `assets/backgrounds/`. Visual inspection of every file + code cross-reference (`scripts/` + `scenes/*.tscn`). Date: 2026-06-22.

**Headline:** The art set is in very good shape. Almost every PNG is a high-quality, on-tone stylized illustration (graphic-novel / painterly dark-fantasy — consistent house look). The problems are not craft; they're (1) six orphaned `.jpg` originals the game never loads, (2) one off-style file that IS loaded (`player_knight.png`), (3) the missing Kindler hero, and (4) two name/art and integration mismatches.

---

## Format duplicates (.jpg vs .png)

The game loads **`.png` everywhere** — confirmed in every `.tscn` (`scenes/*.tscn` ext_resource lines) and every `.gd` path. In all 5 background pairs and the player pair, the `.jpg` and `.png` are **different images** (not re-encodes), and in every case the `.jpg` is an off-tone stock photo / unrelated master and the `.png` is the polished illustration that's actually used.

| Pair | Identical content? | Code loads | Keep | Drop (orphan) | Notes |
|---|---|---|---|---|---|
| `main_menu` | No — totally different | `.png` (`main_menu.tscn`, `recruit.tscn`, `GameTheme` mood key) | **`.png`** | `.jpg` | PNG = lone warrior before a wall of fire in a meadow (on-theme). JPG = night photo of burning reeds. |
| `rest_campfire` | No | `.png` (`rest.tscn`, `Rest.gd` act-1 + fallback) | **`.png`** | `.jpg` | PNG = painted camp (tent, log, fireflies). JPG = photo of two **modern people in camp chairs** — anachronistic, off-tone. |
| `event_forest` | No | `.png` (`event.tscn`, `treasure.tscn`, `wayside.tscn`) | **`.png`** | `.jpg` | PNG = illustrated forked-path signpost scene (matches set). JPG = misty-forest photograph. |
| `shop_tavern` | No | `.png` (`shop.tscn`) | **`.png`** | `.jpg` | PNG = hooded merchant at a cluttered counter (perfect StS shop). JPG = near-black wine-cellar photo, barely legible. |
| `player_knight` | No | `.png` (`Combat.gd:10740`, `Rest.gd` silhouette fallback) | see note | `.jpg` | **Special case — see REPLACE.** PNG = modern anime/comic torch-warrior (off-style). JPG = Dürer's *Knight, Death and the Devil* (genuine PD master, but content/format don't fit a portrait slot and it's unused). |

**Action:** all 6 `.jpg` files (`main_menu`, `rest_campfire`, `event_forest`, `shop_tavern`, `map_parchment`, `player_knight`) are orphaned and safe to delete. `map_parchment.jpg` has no `.png` twin but is also unused (see Orphaned).

---

## Missing / gaps

- **Kindler hero — NO portrait and NO silhouette.** The game has 5 heroes (Raider/Stalwart/Acolyte/Pyromancer/**Kindler**) but only 4 of each art file exist. Both loaders build their path from the hero id (`hero_portrait_%s.png` in `MainMenu.gd:802`, `hero_silhouette_%s.png` in `Rest.gd:50`), so Kindler resolves to non-existent `hero_portrait_kindler.png` / `hero_silhouette_kindler.png`. It degrades gracefully (MainMenu draws a "portrait to come" crest plate; Rest falls back to `player_knight.png` at 0.45 alpha), **but Kindler is the only hero with no real face.** This is the single biggest content gap. Needs: `hero_portrait_kindler.png` + `hero_silhouette_kindler.png` in the existing style (ember/flame theme to match the Everflame faction).
- **No bespoke boss splash for the rival-lord / amalgam finales.** `Combat.gd` (10516) looks up `boss_<encounter_id>.png`, then falls back to `boss_act<N>.png`. Encounters THE STALWART/RAIDER/ACOLYTE/PYROMANCER/KINDLER (act 1), THE WYRM-FATHER, THE BELLRINGER (act 2), THE DEVIL, THE BLACK TIDE, and all five *ASCENDANT* amalgams (act 3) have **no** `boss_<id>.png`, so they all show the generic per-act splash. Not broken (fallback is intended), but these named lords currently share faces. Lower priority than Kindler.
- No `combat_arena_act1.png` — **intentional**, not a gap: Act 1 combat uses `combat_battlefield.png` (the `combat.tscn` default); acts 2/3 override via the `Combat.gd` BG dict.

---

## REPLACE — low quality / off-style (worst first)

| # | File | What's wrong | Suggested direction |
|---|---|---|---|
| 1 | `portraits/player_knight.png` | **Off-style and it's the one that's loaded.** Modern anime/manga-comic illustration of a young torch-bearing warrior — flat cel shading, bright accents. Clashes with the painterly graphic-novel look of every other portrait/background; reads as clip-art next to the bosses. Used as the in-combat hero avatar (`Combat.gd:10740`) and the Rest silhouette fallback. | Repaint in the house style (textured graphic-novel, muted dark palette, ember accents) to match `hero_portrait_*`. The orphaned `player_knight.jpg` (Dürer) is the right *tone* but wrong shape/usage — don't just swap to it; commission/generate a matching painted knight. |
| 2 | `portraits/boss_the_crone.png` | **Name/art mismatch.** "The Crone" implies an old woman / hag / witch; the art is a crowned **skeletal king holding a glowing book** — male, regal, not a crone. Also a 3rd near-identical skeleton-king (see redundancy note). The encounter is a curse-brewing witch (crone_drip/crone_lash/crone_doom passives), so the face actively miscommunicates the fight. | Replace with a genuine crone/hag: hunched old woman, cauldron/curse motif, bone fetishes — distinct from the lich kings. Craft of the current image is fine; it's just the wrong subject. |
| 3 | `backgrounds/map_parchment.jpg` | Not off-tone, but **generic and not a master**: a plain papyrus/parchment texture (procedurally-flat weave). Only flagged because it's the one non-illustration in the set. **It is also unused** (see Orphaned), so impact is zero unless someone wires it back in. | If ever needed as a real map ground, use an aged-vellum scan with foxing/edge wear; otherwise delete. |

Everything else is on-style and sharp. No blurry or low-res offenders found among the PNGs (act-3 / demon_vanguard / dragon-head splashes are notably high-res; act-1/2 splashes are a touch lower-res but still crisp and intentional comic-line style).

### Thematic redundancy (not a REPLACE, but note)
Three portraits are all "**crowned skeleton king**" and read as near-duplicates at a glance: `boss_act2.png` (lich w/ orb), `boss_hollow_king.png` (skeleton on bone throne), and `boss_the_crone.png` (skeleton w/ book). Since `boss_act2` is the per-act *fallback*, an act-2 boss that lacks its own splash (e.g. THE BELLRINGER) will look just like The Hollow King. Fixing the_crone (#2 above) removes one of the three; giving the act-2 fallback a non-skeleton subject would help further.

---

## Orphaned (unused) files

No `.gd` or `.tscn` in the live game references these. Safe to remove.

- `backgrounds/main_menu.jpg`
- `backgrounds/rest_campfire.jpg`
- `backgrounds/event_forest.jpg`
- `backgrounds/shop_tavern.jpg`
- `backgrounds/map_parchment.jpg` — only referenced in `ASSET_REFERENCE.md`, `DESIGN_DOCUMENT.txt`, and `_frame_work/scripts/frame_compose.py` (a build-time card-frame tool). MapTerrain paints its parchment **procedurally**, so the live map never loads this file.
- `portraits/player_knight.jpg` — the Dürer engraving; the game loads `player_knight.png` instead.

(Each also has a paired `.import` file that should go with it.)

---

## OK

`backgrounds/`: combat_battlefield.png, combat_arena_act2.png, combat_arena_act3.png, collection_library.png, game_over.png, main_menu.png, rest_campfire.png, rest_campfire_act2.png, rest_campfire_act3.png, event_forest.png, shop_tavern.png.

`portraits/`: boss_act1.png, boss_act2.png, boss_act3.png, boss_collector.png, boss_demon_vanguard.png, boss_dragon_lord.png, boss_hollow_king.png, boss_iron_warden.png, enemy_commander.png, hero_portrait_raider.png, hero_portrait_stalwart.png, hero_portrait_acolyte.png, hero_portrait_pyromancer.png, hero_silhouette_raider.png, hero_silhouette_stalwart.png, hero_silhouette_acolyte.png, hero_silhouette_pyromancer.png.

### Minor integration note (art is fine, code expectation isn't)
The four `hero_silhouette_*.png` are **fully-painted seated-at-campfire scenes with solid dark backgrounds**, not transparent cut-out silhouettes. `Rest.gd:226` draws a hero-specific silhouette at **alpha 0.85** (the comment at 221-224 assumes a future "transparent background, side-on" PNG). At 0.85 over the campfire background, these will ghost as a dark rectangle rather than blend. Two fixes possible, neither urgent: (a) give the silhouettes transparent backgrounds, or (b) lower the alpha / composite them as their own framed vignette. Not a quality problem with the paintings themselves.
