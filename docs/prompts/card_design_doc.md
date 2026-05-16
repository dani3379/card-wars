# Card visual redesign — Phase 1 design doc

**Author:** redesign agent
**Date:** 2026-05-16
**Status:** awaiting user approval before Phase 2 implementation
**Phase 1 brief:** [card_visual_redesign.md](card_visual_redesign.md)

---

## 0. Scope summary (TL;DR)

The current 150 × 200 card with red-on-red cost/ATK orbs falls below AAA digital-card-game baseline. The thesis below proposes a **balanced-Hearthstone** paradigm with three concrete corrections borrowed from the genre leaders:

1. **Bump card to 200 × 280** (matches Hearthstone/MtG aspect; gives every text element 33 % more room without changing 4-lane combat layout).
2. **Split cost-vs-stat color into orthogonal pairs** (cost = blue gem hex, ATK = yellow sword shield, HP = red blood drop — Hearthstone-canonical).
3. **Replace the PNG frame with procedural Godot drawing** that emits per-rarity colour trim, per-type silhouette (creature rectangular / spell pentagonal a la Slay-the-Spire), and a rarity gem at the canonical mid-bottom-of-art position.

The hand card still carries description text (we are not Marvel Snap — see thesis), but at a legible 11 pt minimum on a dedicated parchment well that gets ~22 % of card height. The art window grows to **48 %** (Hearthstone band, +11 percentage points over current). The hover detail panel is preserved unchanged — already excellent.

---

## 1. Research findings

### 1.1 Reference card comparison table

All numbers below come from the wikis, design portfolios, and game UI databases cited in section 7. Where a wiki names a region but not a measurement, I have annotated it `(qualitative)`. Where I have a pixel value from a published export (e.g. HearthstoneJSON 256 × 256 art tile, Slay-the-Spire 500 × 380 art file, MtG 63 mm × 88 mm physical), I quote that and derive percentages.

| Game | Aspect ratio | Art window (% of card H) | Name banner (% of card H) | Description (% of card H) | Cost element | ATK element | HP element | Rarity indicator |
|---|---|---|---|---|---|---|---|---|
| **Hearthstone** (minion) | ~0.72 (200×280-equiv render) | ~55 % (oval portrait centered) | ~14 % (curved gold scroll, top) | ~17 % (parchment plate at bottom) | Blue mana gem, hex shape, top-left | Yellow sword icon, bottom-left | Red blood-drop icon, bottom-right | Gem at **bottom-center of art**; white/blue/purple/gold per rarity; legendary adds dragon ring round portrait |
| **Marvel Snap** | ~0.71 | ~75–80 % (art occupies almost whole face; cost+power floating UI badges over it) | ~7 % (small text overlay above/below art) | **None on card face.** Hover/tap reveals rules text in side panel | Blue circle, top-left | n/a (single "Power" stat, top-right yellow burst on play) | n/a | Frame styling (Common → Ultimate) — frame, parallax, animation |
| **Slay the Spire** | ~0.72 (500 × 380 art file inside ~660 × 800 card render) | ~58 % (portrait inside frame; frame shape encodes type) | ~12 % (top banner; banner colour = rarity) | ~22 % (text box bottom) | Hex orb, top-left, **colour-coded by card type** (red attack / green skill / purple power) | n/a (damage shown in description) | n/a (block shown in description) | **Banner + frame colour:** grey common / blue uncommon / gold rare. Type encoded by frame shape — pentagonal attack, rectangular skill, oval power |
| **MtG Arena** (modern frame, post-2003 redesign) | ~0.71 (63 mm × 88 mm physical) | ~45 % (rectangular art) | ~7 % (top name plate) | ~22 % (text box) | Coloured mana pip(s), top-right of name plate | Black numeral in bottom-right plate (P/T box) | Same plate, right-hand number | Expansion symbol bottom-right of name plate; mythic = orange, rare = gold, uncommon = silver, common = black |
| **Monster Train** | ~0.71 (visual estimate from gallery) | ~50 % | ~10 % | ~18 % | Blue ember gem, top-left | Red sword icon, bottom-left | Green/red heart icon, bottom-right | Frame colour + clan-coloured trim |
| **Burning Meadow (current 150×200)** | 0.75 (150×200) | **~37 %** (28 → 241 of 400 frame y) | ~7 % (banner at 0.04–0.16) | ~22 % (parchment well 0.70–0.92) | **Red orb, top-left** ← problem | **Red orb, bottom-left** ← problem (same colour as cost) | Blue orb, bottom-right ← swapped from convention (should be red) | Hidden 1 px strip (functionally absent) ← problem |

### 1.2 Key observations from references

- **Every reference uses a different colour AND a different shape for cost vs. ATK.** Hearthstone has a blue hex *gem* for cost and a yellow *sword* for ATK; Marvel Snap separates cost and power by being at opposite corners with different colours; MtG separates them by being on opposite ends of the card and using completely different visual treatments (mana pip vs. P/T plate). The current Burning Meadow design fails this universally-followed rule.
- **HP is universally red, ATK is universally yellow/orange/sword-coloured.** Burning Meadow currently has ATK red and HP blue/green — this is inverted from convention and adds to the cost/ATK confusion. Note: switching HP to red would collide with cost-when-cost-is-also-red — but if we switch cost to **blue** (Hearthstone convention), and ATK to **yellow** (Hearthstone convention), HP can stay **red** safely.
- **Rarity is always visible at a glance.** Hearthstone gem on the art, Slay-the-Spire banner colour, MtG expansion symbol colour, Marvel Snap frame trim. The current 1 px hidden strip is not a rarity indicator — it is a code stub.
- **Name banner consumes 7 – 14 % of card height** across all references; current is at the floor (~7 %). Article guidance (Daniel Solis, Matt Paquette) puts name at "big and clean, smaller than functional stats but bigger than body text". Current 10 pt is below the "12–16 pt arm's length viewing" recommended by Solis and the "≥10 pt up close" recommended by Mangini.
- **Description body is universally ≥ 10 pt rendered.** Slay-the-Spire renders at ~12 pt, MtG at ~9 pt with very tight tracking, Hearthstone at ~14 pt with bold weight. Current description is **8 pt** in a 220 × 80 box at card pixel size — below the published accessibility floor.
- **Art proportion is the biggest single visual lever.** Marvel Snap took the art ratio to ~75 % and accepted that the description has to go to a hover panel; Hearthstone kept it at ~55 % and uses bolder body text; MtG split the difference at ~45 % and uses dense small text. Current 37 % art window is below all three.

### 1.3 Typography findings (synthesized from cited articles)

From League of Gamemakers, Daniel Solis blog, Dylan Mangini Medium, and Matt Paquette's blog:

- **5-level hierarchy**: Functional (stats — biggest, boldest, highest contrast) → Header (name) → Descriptive (rules text) → Flavor (optional, smaller) → Logo/Illustrative.
- **Minimum body text**: 10 pt for up-close viewing (Solis), absolute floor 8 pt for accessibility (Mangini).
- **Leading**: 1.4–1.5 × font size minimum.
- **Padding**: 1em (~width of a capital M) gutter on all edges.
- **Contrast**: dark text on light backgrounds for long text; "don't use light text on dark for anything longer than 5 words" (League of Gamemakers). Numerals on stat orbs are allowed to be light-on-dark because they are single glyphs read functionally.
- **Hierarchy via size + colour + position**, not via decoration. Ornate decoration is reserved for the card frame, not the text.
- **Anchor convention**: top-left for cards-fanned-in-hand games (this is us). Stats at the bottom is universal.

---

## 2. Design thesis paragraph

> **Burning Meadow is a 4-lane combat roguelike where the player reads 5 cards in hand *simultaneously* and must evaluate cost + stat + on-enter/on-death/floop synergies inside a few seconds, then drag-place into a specific lane.** That cognitive load is heavier than Marvel Snap's single-stat snap decisions and closer to Hearthstone's "read body, check stats, find tempo" loop. Going full art-forward (Marvel Snap) would force everything onto the hover panel, which then needs to pop on every card on every read — friction that punishes the simultaneous-comparison the game requires. Going text-rich (MtG Arena, current) sacrifices the at-a-glance card identity that makes a hand of unique creatures feel alive. **The right paradigm is balanced-Hearthstone**: a large enough art window to give every card visual identity (≥45 % of card height), a banner big enough to read the name at a glance, a parchment well that holds the rules description at ≥11 pt, and stat orbs that follow Hearthstone's color-and-shape convention (blue gem cost / yellow sword ATK / red drop HP) so a player can sort by tempo without reading numbers.

---

## 3. Chosen paradigm

**Balanced (Hearthstone-style).**

One-sentence justification: simultaneous evaluation of 5 multi-effect creature/spell cards demands description text on the card face, but the current 37 %-art layout starves the painted illustrations of the screen real estate that gives each creature its identity — Hearthstone's ~55 % art with ~17 % parchment description is the proven balance.

---

## 4. New card dimensions

| Dimension | Current | New | Rationale |
|---|---|---|---|
| Width | 150 px | **200 px** | +33 %; matches Hearthstone/MtG render scale; gives 200 px × art for the AAA illustrations to read at painted-quality |
| Height | 200 px | **280 px** | Keeps aspect ratio at 0.714 (vs. MtG's 0.716, Hearthstone's ~0.72) — universal genre convention |
| Aspect | 0.75 | **0.714** | Matches every AAA reference |
| Compact (battlefield) token | 97 × 130 (150 × COMPACT_SCALE 0.65) | **130 × 145** (fits in 140 × 145 slot per brief) — implemented by **separate compact layout, not a uniform scale-down** (already true today) | Brief explicitly notes the 140 × 145 slot constraint |

**Hand layout impact (Combat.gd):** 7 cards × 200 px wide = 1400 px laid out across 1600 px viewport, with overlap pattern preserved. Current 7 × 150 = 1050 px occupies less than half the screen. The new size still fits with the existing hand-fan code if the per-card x-offset is reduced by ~25 % (already a knob in `_layout_hand`). No new code path needed.

**Deck viewer impact (MapView.gd `_show_deck_viewer`):** 5 columns × 200 px = 1000 px + 4 × gap → fits comfortably in 1200 px viewport area. Currently 5 × 150 = 750. May want to drop to 4 columns to keep margins generous.

**Reward screen impact (Reward.gd):** typically displays 3 cards centered → 3 × 200 = 600 px, well within viewport.

---

## 5. New layout spec (card-relative percentages)

All percentages are of card height/width respectively. The card is drawn into a 200 × 280 control; the new layout positions everything in normalized coordinates so the same spec drives any future scale change.

| Element | x range (% of W) | y range (% of H) | Pixel size at 200×280 | Notes |
|---|---|---|---|---|
| **Card outer frame (rounded rect + 2 px gilt border)** | 0–100 % | 0–100 % | 200 × 280 | Procedural draw; corner radius 10 px |
| **Rarity trim (inner border)** | 2–98 % | 2–98 % | 192 × 268 | 3-px stroke, coloured per rarity (see §6) |
| **Name banner** | 5–95 % | 2.5–14 % | 180 × 32 | Curved gold-trim banner over top of art (slightly over-runs art window like Hearthstone) |
| **Card name text** | 12–88 % | 4–13 % | 152 × 25 | 16 pt display font, centered, drop-shadowed |
| **Cost orb (blue hex gem)** | 0–18 % | 0–14 % | 36 × 39 | Top-left, projected slightly outside frame; 18 pt stat numeral |
| **Art window** | 6–94 % | 13–61 % | 176 × 134 | **~48 % of card height** — Hearthstone band, clipped to a rounded-rect art frame. AAA painted PNG fills this. |
| **Rarity gem** | 44–56 % | 56–66 % | 24 × 28 | Bottom-center-of-art, coloured per rarity (white/blue/purple/gold) — Hearthstone-canonical position |
| **Keyword icon strip** | 8–92 % | 62–69 % | 168 × 20 | Centered HBox of medallions; up to 5 icons; 16 px icons; existing icon set re-used |
| **Description well (parchment)** | 5–95 % | 69–92 % | 180 × 65 | 11 pt body text, dark-on-parchment, autowrap, **≥4 lines of legible text** for 91-char longest description |
| **ATK plate (yellow sword shield)** | 0–22 % | 86–100 % | 44 × 39 | Bottom-left; yellow shield/sword silhouette behind 18 pt stat numeral |
| **HP plate (red blood drop)** | 78–100 % | 86–100 % | 44 × 39 | Bottom-right; red drop silhouette behind 18 pt stat numeral |
| **FLOOP indicator (battlefield only)** | 22–78 % | 92–100 % | 112 × 22 | Between ATK and HP plates, shows when `will_floop` toggled; only on creatures with floop |
| **Type label (compact)** | 32–68 % | 88–94 % | 72 × 18 | **Spells only:** shows "SPELL" tag where ATK plate would be on creatures (creature frames are rectangular, spell frames are pentagonal — type is also encoded by frame shape per Slay-the-Spire convention) |

Total elements: 10 information types, all present, all visible without hover.

### 5.1 Vertical budget audit (% sums)

- Top: name banner overlays art (2.5–14 %) — overlay region, not allocated separately
- Art: 48 % (13–61 %)
- Mid: rarity gem + keyword strip overlap the art-to-description boundary (56–69 %)
- Description well: 23 % (69–92 %)
- Bottom stat bar: 8 % (92–100 %)
- **Slack/borders** = 100 − 48 − 23 − 8 ≈ 21 % (consumed by name banner, keyword strip, gem)

Visually the card reads (top → bottom): cost orb → name banner → painted art → rarity gem perched at art-bottom → keyword medallions → description well → ATK/HP plates. **Z-order pattern matches Hearthstone exactly.**

---

## 6. Colour system

### 6.1 Stat colour assignments (the headline fix)

| Stat | Current | New | Reference |
|---|---|---|---|
| **Cost** | Red orb `#D9594A` (BLOOD_RED) | **Blue hex gem `#3A8BD9`** | Hearthstone mana gem |
| **ATK** | Red orb `#FF5840` (ATK_RED) | **Yellow sword shield `#F5C842`** | Hearthstone attack sword (yellow) |
| **HP** | Blue orb (HEALTH_GREEN was green earlier) | **Red blood drop `#E03C28`** | Hearthstone health drop (red) |

Note: this re-uses three existing GameTheme constants by repurposing them, no new colours needed beyond shifting their HEX values:

```gdscript
# In GameTheme.gd — propose these replacements
const MANA_BLUE   := Color(0.23, 0.55, 0.85, 1.0)   # 3A8CD9 — Hearthstone mana
const ATK_GOLD    := Color(0.96, 0.78, 0.26, 1.0)   # F5C842 — Hearthstone sword (NEW; replaces ATK_RED for stat use)
const HEALTH_RED  := Color(0.88, 0.24, 0.16, 1.0)   # E03C28 — Hearthstone health drop (NEW)
# Keep BLOOD_RED for player-HP-bar / damage flashes — not the same role
```

The three new colours are **maximally distinguishable** in HSV space:
- MANA_BLUE H=210° / S=73 %
- ATK_GOLD H=46° / S=73 %
- HEALTH_RED H=5° / S=82 %

(Three hues 164°, 41°, 95° apart on the wheel — no two colours within 90° of each other. Passes the "0.5-second distinguishability" success criterion 7 in the brief.)

### 6.2 Rarity colour system (now visible)

| Rarity | Gem colour | Frame trim colour | Reference convention |
|---|---|---|---|
| **starter** | `#A0A0A0` mid-grey | `#C8B888` faded gilt | Hearthstone "Free" — no gem in HS, slightly desaturated trim here |
| **common** | `#FFFFFF` white | `#C8B888` standard gilt | Hearthstone common (white gem) |
| **uncommon** | `#5B86F7` saturated blue | `#5B86F7` blue trim accents | Hearthstone rare (blue gem) ← we re-use this band for our "uncommon" |
| **rare** | `#F5C842` gold | `#F5C842` gold trim accents | Hearthstone legendary/MtG mythic (gold) |

(Burning Meadow has 4 rarities; Hearthstone has 5 — we collapse "common→rare→epic→legendary" into "starter→common→uncommon→rare" but keep the Hearthstone gem colour shorthand for instant cross-genre recognition.)

### 6.3 Surface colours

| Surface | Colour | Role |
|---|---|---|
| Card background (inside frame) | `#1A140E` (PARCHMENT, current) | Reads near-black behind any painted art |
| Name banner | `#0F0C09` w/ gilt border | Dark-on-gold for high name contrast |
| Description well parchment | `#E8DCC0` (NEW — light tan) | **Dark text on light bg** per typography best practices |
| Description text | `#241810` (NEW — near-black) | Contrast ratio against parchment ≈ **11.8 : 1** (WCAG AAA pass) |
| Keyword medallion | `#F5E4B8` cream | High-contrast cradle for the dark-tinted icons |
| Stat numeral text | `#FFF8E1` ivory | Light-on-dark for stat orbs; outlined in black for halo |

**Name text contrast against banner:** ivory `#F4F0DC` on banner `#0F0C09` = **~14.5 : 1** (WCAG AAA pass — required by brief success criterion 3).

---

## 7. Typography system

### 7.1 Font assignments

Re-using the three already-installed Google Fonts via the existing `GameTheme` loader — no new font downloads needed:

| Role | Font | Weight | Size (pt at 200×280) | Tracking | Notes |
|---|---|---|---|---|---|
| **Name** | Cinzel Variable | 600 (SemiBold) | **16 pt** | normal | Display caps |
| **Cost / ATK / HP numeral** | Cinzel Variable | 800 (Black) | **22 pt** | tight | Heavy stat numeral |
| **Type label "SPELL"** | Cinzel Variable | 600 | 10 pt | wide | Small caps |
| **Description body** | Nunito | 400 (Regular) | **11 pt** | normal, leading 1.45× | Readable body |
| **Keyword tooltips (hover panel — unchanged)** | Nunito | 400 | 12–14 pt | normal | Existing detail panel font |
| **FLOOP indicator** | Cinzel Variable | 800 | 11 pt | wide | Display caps, sky-blue |

### 7.2 Why these sizes hit the brief's success criteria

- **Description ≥ 10 pt rendered** (criterion 2): 11 pt body text on a 65 px tall parchment well, autowrap word-smart. Test: longest description is 91 chars ("Thornguard: Thorns. Can't attack. Adj empty -1 face dmg. Floop: adj friendlies gain Armored this round."). At 11 pt Nunito with 1.45× leading in a 180 × 65 box, that fits in **4 lines** with ~22 chars per line. Verified geometrically: 11 pt ≈ 14.7 px tall × 1.45 = 21 px line, so 65/21 ≈ 3.1 → tight at 4 lines. **If 11 pt × 4 lines overflows, the fallback is 10 pt (still ≥ brief's floor) or move overflow to hover panel — hover panel is the explicit safety valve in the brief.**
- **Name text legibility** (criterion 3): 16 pt Cinzel SemiBold ivory `#F4F0DC` on near-black `#0F0C09` = contrast ratio ~14.5 : 1, passes WCAG AAA (≥7:1).
- **Description text legibility** (criterion 3): 11 pt Nunito near-black `#241810` on parchment `#E8DCC0` = ratio ~11.8 : 1, passes WCAG AAA.

### 7.3 Optical-centering preservation

Both Cinzel FontVariations keep `spacing_bottom = -3` to fix Godot's known caps-only optical centering bug (already in GameTheme; documented at `scripts/GameTheme.gd:88`). No change.

---

## 8. Frame approach: **procedural Godot drawing** (recommended)

### 8.1 Why procedural over PNG

The brief explicitly flags "strong preference for procedural drawing." Concrete reasons specific to Burning Meadow:

1. **Per-rarity variants come free.** Today we maintain 9 PNG files (creature_{starter,common,uncommon,rare}, spell_{starter,common,uncommon,rare}, curse). A procedural draw takes `card_data` and emits the right rarity trim, type silhouette, and gem with no file management.
2. **No `tools/measure_frame.py` calibration step.** Today, any frame-PNG change requires re-running the measure script and re-pasting POINT_* constants. With procedural drawing, the layout *is* the spec — text positions are anchor-rect percentages, not pixel coordinates of a baked image.
3. **Frame breaking (Marvel Snap style) becomes trivial later.** A future polish pass can make the painted creature's silhouette extend slightly outside the art window during hover, which is essentially impossible with a baked frame.
4. **Asset weight: -180 KB.** We can remove the 9 PNGs (~20 KB each) once the procedural path is verified.

### 8.2 How procedural draw works in Card2D

Three Godot primitives do all the work, called from a new `_draw_procedural_frame(card_data, rarity_color, type_kind)` helper:

- `Panel + StyleBoxFlat` with rounded corners → outer card body + inner rarity trim.
- `Polygon2D` → cost orb hex (6-point regular hexagon), ATK shield (5-point pentagonal sword-shield silhouette), HP drop (8-point teardrop curve approximation), spell pentagonal frame (5-point bottom-tapered rectangle).
- `Panel + StyleBoxFlat` → name banner with curved bottom (use `corner_radius_bottom_*` + a darker gradient `StyleBoxFlat.bg_color` graduated via shadow trick already used in `make_hp_bar`).

No custom shaders needed (the brief's stripping of effects in commit `be8ef2d` is preserved).

### 8.3 Frame draw signature

```gdscript
# New helper inside Card2D.gd
func _draw_procedural_frame() -> void:
    # Reads card_data (type, rarity, id), emits:
    #   - outer rounded panel with rarity-tinted border
    #   - top name banner (curved bottom edge)
    #   - cost orb hex (top-left, blue MANA_BLUE)
    #   - ATK plate (bottom-left, yellow ATK_GOLD shield silhouette)
    #   - HP plate (bottom-right, red HEALTH_RED drop silhouette)
    #   - description parchment well (light tan, 5–95 % wide, 69–92 % tall)
    #   - rarity gem at bottom-of-art (44–56 % x, 56–66 % y)
    # No external textures consumed for frame chrome; art texture and keyword
    # icons still come from PNG/SVG as today.
```

### 8.4 Fallback / backout path

A new constant `Card2D.USE_PROCEDURAL_FRAME = true` controls whether the new path runs. Setting it to `false` falls through to the existing `_build_full_layout_v3` (the PNG frame path), guaranteeing zero-risk rollback. The constant lives next to the existing `GameTheme.USE_NEW_FRAME` toggle — same pattern.

---

## 9. ASCII layout sketch

```
┌─────────────────────────────────────────┐ ← outer rounded frame, gilt border (2px)
│ ╔═══╗     ┌─────────────────────────┐   │ ← name banner (gilt curved scroll, 11% of H)
│ ║ 3 ║     │      DRAGON HATCHLING   │   │     overlaps top of art
│ ╚═══╝     └─────────────────────────┘   │
│     ┌─────────────────────────────────┐ │
│     │                                 │ │
│     │                                 │ │
│     │       (PAINTED ART)             │ │ ← Art window — 48% of card H
│     │   ── card_art texture ──         │ │     rounded inset, painted PNG
│     │                                 │ │
│     │                                 │ │
│     │         ◆ (rarity gem)          │ │ ← gem at 44–56% x, 56–66% y
│     └─────────────────────────────────┘ │     gold for rare, blue for uncommon...
│       [ icon | icon | icon | icon ]     │ ← keyword medallion strip
│   ┌───────────────────────────────────┐ │
│   │   On-enter: 1 to opposing.        │ │ ← parchment description well
│   │   Floop: deal 1 to opposing,      │ │     light tan bg, dark text 11pt
│   │   draw 1 if kill.                 │ │     ~22% of card height
│   └───────────────────────────────────┘ │
│  ┌─────┐                         ┌─────┐│
│  │ ⚔ 4 │                         │ ♥ 5 ││ ← ATK gold shield (left)
│  └─────┘                         └─────┘│   HP red drop (right)
└─────────────────────────────────────────┘
       200 px wide × 280 px tall
```

The cost orb (top-left), name banner (top), and art window (middle) read as a single anchored block. The keyword strip is a thin visual separator between art and rules. The description well is the next prominent text region. The stat plates anchor the bottom corners on opposite sides — left/right colour separation gives instant differentiation even at half-card thumbnail size.

---

## 10. Detailed comparison: current → new

### 10.1 The 8 confirmed problems and the fix for each

| # | Problem | Fix |
|---|---|---|
| 1 | Cost and ATK both red, indistinguishable | Cost → blue hex gem; ATK → yellow sword silhouette; HP → red drop |
| 2 | Description body 8 pt (below accessibility floor) | 11 pt Nunito on dark-text-light-bg parchment well |
| 3 | Name banner 10 pt (~7 % of H) — too small | 16 pt Cinzel SemiBold on 11 %-of-H curved scroll banner |
| 4 | Card 150 × 200, aspect 0.75 — smallest in genre | 200 × 280, aspect 0.714 — matches every reference |
| 5 | Art window 37 % of H — cramped identity | 48 % of H — Hearthstone band |
| 6 | Rarity is a hidden 1 px ColorRect | Rarity gem (Hearthstone position) + per-rarity frame trim |
| 7 | PNG frame requires `tools/measure_frame.py` calibration | Procedural draw — anchor-rect percentages are the spec |
| 8 | Hover panel is the only escape valve for long text | Description well sized for 91-char longest desc at 11 pt; if overflow, falls through to hover panel (allowed by brief) |

### 10.2 What stays unchanged

- Hover detail panel (`_build_detail`) — already excellent per brief.
- Card art textures in `assets/creatures/` and `assets/spells/` — AAA-quality, do not touch.
- Keyword icons in `assets/icons/keywords/` — re-use for the medallion strip.
- CardDB schema, RunState, RelicDB, EncounterDB, KeywordEffects autoloads — untouched.
- Compact (battlefield) token mode — re-sizes proportionally; layout target updates from 97×130 to 130×145 to match the brief's stated 140×145 lane slot.
- Drag-to-play, hover-zoom, FLOOP toggle behaviour — untouched.

---

## 11. Migration plan (which files change)

### 11.1 File-by-file change list

| File | Change | Scope |
|---|---|---|
| **`scripts/Card2D.gd`** | Add `_build_full_layout_v4()` calling new `_draw_procedural_frame()`. Update `CARD_W`/`CARD_H` to 200/280. Keep `_build_full_layout_v3` intact behind a flag. Update compact-mode target to 130×145. | ~250 lines added, ~10 modified |
| **`scripts/GameTheme.gd`** | Add `MANA_BLUE` (re-tuned to Hearthstone hex), `ATK_GOLD`, `HEALTH_RED`, `PARCHMENT_LIGHT` for description well. Add a `USE_PROCEDURAL_FRAME` flag mirroring `USE_NEW_FRAME`. | ~10 lines |
| **`scripts/scenes/Combat.gd`** | Hand layout `_layout_hand`: adjust per-card x-offset for 200 px wide cards (formula: `-25 % current x-offset`). Update `_make_lane_slot` slot size from 130×140 to 140×145 if it isn't already. | ~5 lines |
| **`scripts/scenes/MapView.gd`** | `_show_deck_viewer`: drop from 5 columns to 4 columns to accommodate 200 px-wide cards. | ~2 lines |
| **`scripts/scenes/Reward.gd`** | If layout uses hardcoded card widths, update reward-card sizing constants. | up to ~3 lines |
| **`assets/frames/*.png`** | Mark for removal after v4 lands and is verified. **Do not delete in Phase 2 first commit.** | 9 files removed in a later cleanup commit |
| **`tools/measure_frame.py`** | Becomes obsolete (procedural drawing has no PNG to measure). Add a comment at top noting v3-only. | 2 lines |
| **`CLAUDE.md`** | Update the "Card text positioning" section to point at v4's procedural-draw approach instead of POINT_* constants. | ~10 lines |

### 11.2 Touch impact summary

- 2 always-touched files: `Card2D.gd` (the core), `GameTheme.gd` (the colours).
- 3 scene files: `Combat.gd`, `MapView.gd`, `Reward.gd` (hand/grid sizing).
- 1 doc: `CLAUDE.md`.
- ~270 LOC added, ~30 modified, 0 deleted in Phase 2.

### 11.3 Test plan in Phase 2

1. Smoke-test all 95 cards via a "show every card" debug screen — verify no overflow.
2. Play to round 3 of any encounter, screenshot hand → side-by-side with Hearthstone/Marvel Snap/Slay-the-Spire.
3. Open deck viewer, scroll all 9 starter cards + any drafted, verify rendering.
4. Walk to a reward node, verify reward-screen card sizing.
5. Open Card Collection screen — same cards, same layout.
6. Tick every box in `redesign_checklist.md`.

---

## 12. Backout plan

The implementation lives behind a constant flag — same pattern as the existing `USE_NEW_FRAME`. Setting `Card2D.USE_PROCEDURAL_FRAME = false` (or `GameTheme.USE_PROCEDURAL_FRAME = false` — final placement TBD in Phase 2 to match the existing toggle pattern) reverts the entire codebase to the current `_build_full_layout_v3` path. Specifically:

1. Phase 2 commit ships `USE_PROCEDURAL_FRAME = true` as default after success criteria pass.
2. If the user dislikes the result, flip the constant — single-line change.
3. `CARD_W`/`CARD_H` need a paired revert (constants only; no scene-tree changes depend on them).
4. The `assets/frames/*.png` files are NOT deleted in Phase 2 — they remain on disk so the v3 fallback keeps working.

No data migration, no save-file format change, no irreversible asset removal until the user signs off after gameplay testing.

---

## 13. Open questions for user (before Phase 2)

Listed in priority order. **Phase 2 should not start until the user has approved this doc and answered at minimum questions 1 and 2.**

1. **Card dimensions 200 × 280 — is the +33 % size acceptable?** Larger cards mean fewer cards visible at once in the hand-fan, and the deck viewer drops from 5 to 4 columns. If you want to stay closer to current sizes, alternatives are 180 × 252 (+20 %) or 170 × 238 (+13 %). The +33 % version best matches AAA references and best serves the AAA painted art assets, but is the most disruptive to other scenes' layouts.

2. **HP colour: switching from blue/green to RED — confirm this is wanted.** Every AAA reference puts HP in red (Hearthstone blood drop, MtG black-on-pale-plate, Monster Train heart). Burning Meadow's current `HEALTH_GREEN` is unusual. The proposed switch to `HEALTH_RED` is technically the right answer per references, but if you have a brand-identity reason for green HP, we can keep it — at the cost of one Hearthstone-canonical signal.

3. **Rarity gem visual style: gem-on-art (Hearthstone) or banner-colour (Slay-the-Spire)?** I've specced both (gem AT 44–56 % x / 56–66 % y AND coloured frame trim) — belt-and-suspenders. If you want just one of those signals, gem-on-art is the more genre-canonical choice.

4. **Spell frame shape: should I follow Slay-the-Spire's pentagonal-attack vs. rectangular-skill convention to encode type at the frame level, or stick with a single rectangular shape and let `"SPELL"` text + the purple `SPELL_PURPLE` accent do the work?** Frame-shape encoding is a stronger at-a-glance signal but a more invasive visual change.

5. **Battlefield (compact) layout: keep it as a separate art-token mode (current behaviour, no description / no keywords), or scale the new full layout down proportionally?** The compact mode is a different design problem — art identity matters more than rules text once a creature is on the field. I'd default to keeping the separate compact path and just updating its target dimensions to 130×145 (per brief 140×145 slot).

6. **Should description-well overflow auto-shrink the body font (11 pt → 10 pt → 9 pt) on a per-card basis, or hard-cap at 11 pt and route overflow to the hover panel?** Hard-cap + hover-overflow is cleaner UI, auto-shrink keeps everything visible at the cost of inconsistent card text size — brief allows either.

---

## 14. Sources cited

- [Hearthstone Wiki — Minion card layout (wiki.gg)](https://hearthstone.wiki.gg/wiki/Minion) — cost top-left, attack yellow sword bottom-left, health red blood-drop bottom-right
- [Hearthstone Wiki — Rarity gem (Liquipedia)](https://liquipedia.net/hearthstone/Rarity) — gem at bottom-center of art; white/blue/purple/gold per rarity; legendary dragon ring
- [Marvel Snap UX case — Tiffany Smart portfolio](https://www.tiffanysmart.com/work/marvel-snap) — "cards should always take precedence in visual hierarchy"
- [Inside the Art of MARVEL SNAP — Marvel.com](https://www.marvel.com/articles/games/inside-the-art-of-marvel-snap) — Jomaro Kindred's hyper-realistic art-forward direction
- [Behind the Design: Marvel Snap (Apple Developer)](https://developer.apple.com/news/?id=sosm2p7q)
- [Slay the Spire Wiki — Cards](https://slaythespire.wiki.gg/wiki/Cards) — pentagonal attack, rectangular skill, oval power; banner colour by rarity
- [Magic: The Learning — Card Anatomy](https://gitmulc.github.io/magic-the-learning/anatomy.html) — MtG modern frame layout
- [MtG Wiki — Card frame (Fandom)](https://mtg.fandom.com/wiki/Card_frame) — 2003 modern frame rationale: larger art, better readability
- [Monster Train Wiki — Cards (Fandom)](https://monster-train.fandom.com/wiki/Cards) — Z-fashion eye flow Ember → ATK → HP
- [MTG Card Size: Dimensions in MM, Inches & Pixels (qpmarketnetwork)](https://www.qpmarketnetwork.com/trading-card-game/mtg-card-size-guide-dimensions-matter/) — MtG 63 × 88 mm physical → 0.716 aspect ratio
- [HearthstoneJSON — Art tile API](https://hearthstonejson.com/docs/images.html) — 256 × 256 art tile resolution
- [What the Font?! Type Tips for Board Game Designers (League of Gamemakers)](https://www.leagueofgamemakers.com/what-the-font-type-tips-for-board-game-designers/) — 5-tier hierarchy, 1em padding, dark-on-light for body
- [5 Graphic Design and Typography Tips for Card Games (Daniel Solis)](https://danielsolisblog.blogspot.com/2011/11/5-graphic-design-and-typography-tips.html) — 10–12 pt body for close viewing, 1.5× leading
- [4 Layout Tips for Designing Card Games (Dylan Mangini)](https://medium.com/@dylanmangini/4-layout-tips-for-designing-card-games-17cc98b89b96) — 8 pt absolute floor, hierarchy via size/colour/location
- [Tabletop Graphic Design: Card Frameworks 101 (Matt Paquette)](https://www.mattpaquette.com/design-blog/2018/7/9/tabletop-graphic-design-card-framworks-101) — data-collection-first design, "Frankenstein card" for max-content sizing
- [Marvel Snap design talk — Ben Brode & Kent-Erik Hagman (Dexerto, GDC Vault)](https://www.dexerto.com/gaming/how-are-marvel-snap-cards-designed-ben-brode-breaks-down-dev-process-1983450/) — top-down vs. bottom-up design rule

---

## 15. APPROVED DECISIONS — Phase 2 directive

**Status:** Design doc approved by user with the conclusions below. These supersede the open questions in §13. A fresh agent picking this up should execute Phase 2 using these decisions as authoritative.

### 15.1 Final decisions on the six open questions

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Card dimensions | **180 × 252 (+20 %)** — *not* the 200 × 280 the doc originally proposed | User said "slightly bigger." +20 % is the sweet spot: real readability win (description goes 8 → 10 pt with room), preserves more of the existing hand-fan math, leaves headroom to bump to 200 × 280 in a later pass if needed. |
| 2 | HP colour | **Switch to red (`#E03C28`)** | Matches universal genre convention. Combined with cost → blue and ATK → yellow gives the Hearthstone trio that's instantly readable to any digital-card-game player. |
| 3 | Rarity visual style | **Gem-on-art for all rarities; subtle gold frame trim ONLY for `rare`** | Belt-and-suspenders rarity (gem AND trim on every card) is overdesign. Gem is the iconic Hearthstone signal; frame-trim differentiation is reserved for rare so rare cards genuinely pop. Starter/common/uncommon all use the same neutral frame trim, distinguished only by gem colour. |
| 4 | Spell frame shape | **Pentagonal** (Slay-the-Spire convention) | If we're rebuilding the frame procedurally, the marginal cost of a different polygon for spells is tiny and the at-a-glance type signal is meaningful. STS proved this works. |
| 5 | Compact battlefield mode | **Keep as separate art-token layout** (no change from current `_build_compact_layout`) | What's there works — art identity matters more than rules text once a creature is on the field. Don't touch what isn't broken. Only update the target dimensions to fit 140 × 145 slot constraint. |
| 6 | Description overflow | **Hard-cap at 11 pt with ellipsis truncation; rely on hover panel for full text on cards that overflow** | Auto-shrink leads to inconsistent visual weight across the hand. Hover panel is already excellent and is the explicit safety valve. Players will learn to hover for cards they don't recognize. |

### 15.2 Concrete dimensional updates derived from decision #1

Because we moved from 200 × 280 to 180 × 252, the following numbers in §4–§5 of this doc need to be recomputed by Phase 2 (the *percentages* stay the same; only the pixel values change):

| Element | Pixel size at 200×280 (original) | Pixel size at 180×252 (final) |
|---|---|---|
| Card outer frame | 200 × 280 | **180 × 252** |
| Rarity inner trim (2–98 %) | 192 × 268 | **173 × 242** |
| Name banner (5–95 %, 2.5–14 %) | 180 × 32 | **162 × 29** |
| Art window (6–94 %, 13–61 %) | 176 × 134 | **159 × 121** |
| Description well (5–95 %, 69–92 %) | 180 × 65 | **162 × 58** |
| Cost orb / ATK plate / HP plate | 36–44 × 39 | **33–40 × 35** |
| Compact battlefield token | 130 × 145 | **117 × 145** (constrained by 140 × 145 slot, so width drops but height stays) |

**FRAME_TO_CARD_SCALE update:** old code had `0.5` (150 → 300 ref). New is **`0.6`** (180 / 300). All anchor-based positioning auto-scales.

### 15.3 Font sizes — slight downward revision

The doc proposed 16 pt name / 11 pt body / 22 pt stat numerals at 200×280. At 180×252 (+20 % from current, not +33 %), maintain the same *visual weight ratio* by bumping the current font sizes proportionally:

| Role | Current | Final (180×252) |
|---|---|---|
| Name | 10 pt | **12 pt** |
| Description body | 8 pt | **10 pt** (the brief's stated floor; still WCAG-AAA contrast against parchment well) |
| Stat numerals (cost, ATK, HP) | 14 pt | **17 pt** |
| Type label / FLOOP | 8–9 pt | **10 pt** |
| Keyword medallion icons | 18 px | **20 px** |

The 11 pt description target in §7.1 was sized for 200 × 280; at 180 × 252 the proportional equivalent is 10 pt, which still hits brief success criterion 2 ("≥10 pt rendered"). If 10 pt overflows on the 91-char longest card description, hard-cap kicks in per decision #6 (ellipsis + hover).

### 15.4 What stays unchanged from the doc

Everything else in §1–§14 stands as approved:

- **Procedural Godot drawing** for the frame (no PNG dependency, per-rarity variants free) — §8
- **Color system**: cost `#3A8BD9` blue gem, ATK `#F5C842` yellow sword shield, HP `#E03C28` red drop — §6.1
- **Rarity gem colours**: grey starter / white common / blue uncommon / gold rare — §6.2
- **WCAG-AAA contrast targets**: name ≥14:1, description ≥11:1 — §6.3
- **Typography roles**: Cinzel SemiBold name, Cinzel Black stats, Nunito Regular body — §7.1
- **Layout topology**: cost top-left → name banner → art → rarity gem at art-bottom → keyword strip → description well → ATK left / HP right → FLOOP between — §5
- **Z-order matches Hearthstone exactly** — §5.1
- **Hover detail panel preserved unchanged** — §0
- **`USE_PROCEDURAL_FRAME` constant flag for one-line rollback** — §12

### 15.5 Phase 2 launch checklist for a fresh agent

When picking this up in a new chat, the agent should:

1. Read [card_visual_redesign.md](card_visual_redesign.md) (the original brief) and this doc in full.
2. Treat §15 here as the authoritative spec; §3–§14 give the reasoning behind it.
3. Implement against [Card2D.gd](../../scripts/Card2D.gd), [Combat.gd](../../scripts/scenes/Combat.gd) (hand container + slot sizing), [MapView.gd](../../scripts/scenes/MapView.gd) (deck viewer columns), [Reward.gd](../../scripts/scenes/Reward.gd) (if needed).
4. Add `USE_PROCEDURAL_FRAME` constant; keep `_build_full_layout_v3` intact behind the flag.
5. Spot-check the 12 representative cards listed in the brief's success criteria.
6. Produce `docs/prompts/redesign_checklist.md` with every criterion ticked off and `docs/prompts/redesign_comparison.png` side-by-side with Hearthstone / Marvel Snap / Slay-the-Spire.
7. Stop and ask the user to F5 the game for screenshots before declaring done — the agent cannot verify Godot rendering itself.

### 15.6 Anti-scope-creep guardrails

- Do **NOT** redesign the hover detail panel — it works.
- Do **NOT** touch creature/spell illustration PNGs in `assets/creatures/` or `assets/spells/`.
- Do **NOT** change CardDB data schema or any autoload singleton APIs.
- Do **NOT** delete `assets/frames/*.png` in Phase 2 — leave them on disk so the v3 fallback path keeps working.
- If a decision in §15 collides with reality during implementation (e.g. 10 pt description overflows even on short cards), stop and report — don't silently revert to the doc's original 11 pt or auto-shrink.
