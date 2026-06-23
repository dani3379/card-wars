# Relic Icon Art Audit — Burning Meadow

Audited `assets/icons/relics/*.png` against the `RELICS` dictionary in
`scripts/data/RelicDB.gd`. Icon resolution is convention-based: `get_relic_icon(id)`
loads `assets/icons/relics/<id>.png` (PNG wins) else `<id>.svg` else returns `null`
(generic fallback). 54 of 122 PNGs were visually inspected (all 6 exact-dup groups,
every near-dup cluster, and both art-style families).

There are **two-and-a-half distinct art styles** in the folder, which is the
single biggest consistency problem:
- **Style A — "rim-light cutout"** (the large majority, the intended house look):
  a painted object with a bright molten-orange glow outline, floating on a dark
  cluttered/teal background, thin antique border. Hades/StS shop-icon feel.
- **Style B — "full painterly oil scene"** (a sizable minority): a full
  brush/oil illustration filling the frame, muted palette, **no glow cutout**,
  landscape-like. Reads as a different generator/era. These stick out badly when
  shown next to Style A in the HUD relic tray.
- **Outlier resolution**: `glass_cannon.png` is ~600×600 with a different
  pixel-art finish, vs the ~256px norm.

---

## Exact duplicate files

Byte-identical PNGs (same md5) used by two different relics. In every case the
second relic shows the WRONG painting (a picture of the first relic's subject).

| md5 (short) | Files (relics) | Problem |
|---|---|---|
| `0ec17f3e` | `collectors_tome.png` + `worn_spellbook.png` | Worn Spellbook shows the Collector's Tome (red layered book). Both books, so least jarring, but still identical. |
| `4336cbe4` | `coin_purse.png` + `scavengers_pouch.png` | Scavenger's Pouch shows the Coin Purse (red drawstring bag + coins). |
| `5f7fc0f0` | `couriers_bag.png` + `hexagonal_shield.png` | **Hexagonal Shield shows a leather courier's pack** — totally wrong subject (should be a shield). |
| `8490696e` | `sozu.png` + `war_drum.png` | **War Drum shows a flaming barrel/cauldron** (Sozu/Temperance art) — wrong subject (should be a drum). |
| `bdf29bda` | `mimic_ring.png` + `scouts_emblem.png` | Both show a sun/compass starburst emblem. Reasonable for Scout's Emblem, wrong for Mimic Ring (should be a ring). |
| `c5a4b508` | `banner_of_unity.png` + `soul_lantern.png` | **Banner of Unity shows a lantern** (Soul Lantern art) — wrong subject (should be a banner). |

**6 exact-dup pairs (12 files).** Fix: repaint the wrong-subject member of each
pair. Priority order by wrongness: `hexagonal_shield`, `war_drum`,
`banner_of_unity`, `mimic_ring`, `scavengers_pouch`, `worn_spellbook`.

---

## Missing icons

Relic ids present in `RelicDB.RELICS` with **no `.png` and no `.svg`** — they
render the `null` generic fallback in HUD/shop. Confirmed absent via Glob.

| relic id | name | tier |
|---|---|---|
| `ember_censer` | Ember Censer | starting |
| `coin_landed` | The Coin, Landed | event |
| `verse_of_you` | A Verse of You | event |
| `warm_knucklebone` | Warm Knucklebone | event |
| `sin_eaters_crust` | The Sin-Eater's Crust | event |
| `hourglass_of_ruin` | Hourglass of Ruin | boss |
| `berserkers_totem` | Berserker's Totem | combat |
| `crimson_chalice` | Crimson Chalice | combat |
| `warlords_standard` | Warlord's Standard | combat |
| `runebound_idol` | Runebound Idol | combat |
| `bulwark_engine` | Bulwark Engine | combat |
| `gravewardens_pact` | Gravewarden's Pact | boss |

**12 relics with no icon.** These are the newest content: the 4 event relics, the
8 "Wave 2" keyword-synergy relics (all defined at the bottom of RelicDB), plus the
`ember_censer` starting relic. The Wave-2 set was added without art.

---

## Orphaned icons

**None.** Every one of the 122 PNG basenames maps to a relic id in `RELICS`.
(Note: 54 legacy `.svg` silhouettes also exist; each has a matching relic id and is
shadowed by its PNG — none are orphaned, but they are dead weight where a PNG exists.)

---

## REPLACE — low quality / style-mismatch

Beyond the exact dupes above. "Style B" = full painterly oil, no rim-light glow —
the dominant inconsistency. "Subject mismatch" = the art doesn't depict what the
relic is.

| file | what's wrong | suggestion |
|---|---|---|
| `glass_cannon.png` | **Resolution + finish outlier**: ~600×600 detailed pixel-art lava crown vs the ~256px rim-light norm; also subject is a crown, not a "glass cannon". | Repaint as a fragile crystal/glass artifact in Style A at matching size. |
| `pyromaniac_ring.png` | **Subject mismatch**: a mossy stone block pierced by arrows (a stone-family icon), not a ring. | Repaint as a glowing ring/band. |
| `cursed_key.png` | **Subject mismatch**: a glowing stone maul/hammer, not a key. | Repaint as an ornate cursed key. |
| `war_horn.png` | **Subject mismatch**: an antique sea-chart/map, not a horn. | Repaint as a war horn. |
| `veterans_medal.png` | **Subject mismatch**: maroon dice on stone (reads as a dice/marbles icon), not a medal. | Repaint as a campaign medal/ribbon. |
| `champions_belt.png` | Style B (painterly) **and subject mismatch**: a horned war-helm on a post, not a belt. | Repaint as a champion's belt in Style A. |
| `marathoners_sash.png` | Style B oil painting **and subject mismatch**: gold coins on red cloth (reads as gold/coins), not a sash. | Repaint as a runner's sash in Style A. |
| `glowing_hand.png` | Style B: muted purple oil "eruption/hand" scene, no cutout. Vague subject. | Repaint as a glowing spell-hand in Style A. |
| `mana_tide.png` (War Chest) | Style B oil: blue hand in mist. Vague, and **near-dup of `glowing_hand`** (both blue hands rising). | Repaint to match name (a war chest) in Style A. |
| `mana_pearl.png` (Knife Up the Sleeve) | Style B oil: pearl in a shell. Subject doesn't match the "knife up the sleeve" name and clashes with Style A. | Repaint in Style A. |
| `skull_throne.png` | Style B: deliberately muted classical gallery oil of a skull altar — strongest tonal outlier. | Repaint in Style A glow look. |
| `pen_nib.png` | Style B near-photoreal render (glossy fountain pen). Clashes hard with painted Style A. | Repaint in Style A. |
| `soul_ledger.png` | Style B near-photoreal open book. Clashes with Style A. | Repaint in Style A. |
| `snecko_eye.png` (Basilisk Eye) | Style B oil dragon-eye, no cutout. | Repaint in Style A. |
| `bag_of_marbles.png` | Style B oil (pouch of glowing gems). Good subject, wrong style. | Re-render in Style A. |
| `reagent_pouch.png`, `pandoras_box.png`, `calling_bell.png`, `centaur_heart.png`, `corner_stone.png`, `flanking_banner.png`, `steady_banner.png` | Style B painterly outliers (no rim-light cutout). Subjects are fine; only the finish is off-house. | Re-render in Style A for tray consistency. |

---

## Near-duplicates (visually interchangeable, different relics)

Not byte-identical, but easy to confuse at HUD chip size.

- **Blue hand-in-mist pair**: `mana_tide.png` and `glowing_hand.png` — both a
  large hand rising from blue/teal mist, same Style-B finish. Nearly
  interchangeable.
- **Lantern cluster**: `lantern.png`, `stygian_soul.png`, and `soul_lantern.png`
  (which is also the `banner_of_unity` dupe) are all lanterns. `lantern` vs
  `stygian_soul` are different paintings of the same object — confusable.
- **Red closed-book cluster**: `collectors_tome.png`/`worn_spellbook.png` (red
  layered book) and `tome_of_many.png` (red tome, molten center) read as the same
  relic at small size; `spell_tome.png` and `tome_of_many.png` are also similar
  warm ornate spellbooks at the same 3/4 angle.
- **Red-gem-on-stone cluster**: `bloodstone_relic.png` (red gem set in stone),
  `veterans_medal.png` (maroon dice on stone), and `corner_stone.png`/
  `phalanx_stone.png` share the same carved-stone-block composition and palette —
  the gem/dice/stone group blurs together.
- **Crossed-weapon vs shield**: `iron_buckler.png` shows crossed axes (not a
  buckler); reads more like a generic weapon relic and can be confused with other
  warm crossed-metal icons.

---

## Summary counts

- **Total relics in RelicDB:** 137
- **Total PNG icons:** 122 (plus 54 legacy `.svg` fallbacks, all PNG-shadowed)
- **Missing icons (null fallback):** 12 relics
- **Orphaned icons:** 0
- **Exact-duplicate file groups:** 6 pairs (12 files); each has 1 wrong-subject member
- **REPLACE — low-quality / style-mismatch:** ~24 files
  (≈17 Style-B painterly outliers + ~7 subject-mismatched icons; some overlap)
- **Near-dup clusters:** 5 (blue hands, lanterns, red books, gem-on-stone, crossed weapons)
- **Worst issue:** Two incompatible art styles in one tray (rim-light cutout vs
  full painterly oil) — the painterly "Style B" relics (`pen_nib`, `soul_ledger`,
  `skull_throne`, `mana_*`, the boss-tier oils) break the consistent Hades-style
  look. Closely tied for worst: 6 exact-dup reused paintings showing the wrong
  subject (e.g. Hexagonal Shield = a bag, War Drum = a barrel, Banner of Unity = a
  lantern).
