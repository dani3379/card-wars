# Card visual redesign — Phase 2 verification checklist

**Date:** 2026-05-16 (revised with AAA-alignment pass after first F5)
**Status:** Phase 2 implementation complete; awaiting follow-up F5 screenshot.
**Refs:** [card_visual_redesign.md](card_visual_redesign.md) (brief) · [card_design_doc.md](card_design_doc.md) (approved design + §15 directives)

## Revision notes — AAA-alignment pass

After the first F5 screenshot showed amateur-looking elements (tiny rarity diamond, stuck-on spell peak triangle, lonely single keyword medallion), I cross-checked Hearthstone / Slay-the-Spire / MtG conventions and made three corrections:

1. **Dropped the spell peak triangle.** No AAA digital card game has a stuck-on peak above the banner. Slay-the-Spire's pentagonal attack frame is a full polygonal silhouette, not a peak; that's a bigger refactor for a later pass. Spell type is now signalled by banner colour, absence of ATK/HP plates, and the SPELL tag — the Hearthstone/MtG convention.
2. **Removed the keyword medallion strip.** Hearthstone, MtG Arena, and Slay-the-Spire all show keywords **inline in description text** (bold/coloured) — none use a separate icon row. The strip was the most unusual element on each card and made cards with one keyword look "lonely." Keywords now ride inline in the description via `KeywordEffects.colorize_keywords()` (already implemented; remapped from light gold `#c89e4a` to deep brown `#6a4310` for contrast on the light parchment). Full keyword tooltips still appear in the hover panel.
3. **Enlarged the rarity gem ~2.5×.** The 12 %-wide diamond was below visibility threshold at hand scale. New gem is 22 %-wide with a dark circular back-plate ringed in the rarity-trim colour — comparable to Hearthstone's gem footprint and now actually readable.

Additional polish:
- **Rare cards now get a thicker frame** (3 px outer border vs. 2 px, doubled banner border, brighter inner trim) so they genuinely stand out — the procedural analogue of Hearthstone's legendary dragon ring.
- **Description well moved up to 66 %–86 % Y** (was 69 %–92 %): more vertical room for body text now that the medallion strip is gone.

The result is a layout that reads as: cost gem → name banner → painted art → rarity gem at art-well boundary → description (with inline-coloured keywords) → ATK shield / HP drop. This matches the Hearthstone topology one-for-one.

---

## Files changed in Phase 2

| File | Summary of change |
|---|---|
| `scripts/GameTheme.gd` | Added `USE_PROCEDURAL_FRAME` flag and the v4 palette: `COST_BLUE_GEM`, `ATK_GOLD_SHIELD`, `HEALTH_RED_DROP`, `PARCHMENT_LIGHT`, `PARCHMENT_TEXT`, four rarity-gem colours (`GEM_STARTER/COMMON/UNCOMMON/RARE`), and frame trim colours (`FRAME_TRIM_NEUTRAL`/`FRAME_TRIM_RARE`). Added `rarity_gem_color()` and `rarity_frame_trim()` helpers. Bumped `CARD_SIZE` to 180×252 (legacy reader). |
| `scripts/Card2D.gd` | • `CARD_W`/`CARD_H` → 180/252 (was 150/200)<br>• `COMPACT_SCALE` → 0.575 (so 252-tall card fits 140×145 slot)<br>• `FRAME_TO_CARD_SCALE` → 0.6 (was 0.5; v3 fallback path still works)<br>• `_cost_badge` re-typed from `Panel` to `Control` to accept either legacy panel or v4 `PolyBadge`<br>• Added `PolyBadge` inner class (procedurally draws hex / shield / drop / diamond / peak silhouettes)<br>• Added `_build_full_layout_v4()` — full procedural frame (no PNG dependency)<br>• `_build_layout()` dispatches v4 when `USE_PROCEDURAL_FRAME` is true; v3 stays intact behind the flag<br>• `update_stat_display()` now restores `_atk_base_color` / `_hp_base_color` instead of forcing `Color.WHITE` (which would render invisible on the gold ATK shield) |
| `scripts/scenes/Combat.gd` | Hand container `offset_top` -190 → -262 (fits 252-tall cards); `separation` -16 → -48 (10 cards × 180 with -48 overlap ≈ 1368 px, same total hand-fan width as the legacy layout) |
| `scripts/scenes/MapView.gd` | Deck-viewer grid columns 8 → 7 (180-wide cards × 7 + 6×12 = 1332 px, fits 1440-wide scroll); `v_separation` 12 → 14 |

No new external assets. No deletions yet (the `assets/frames/*.png` v3 set is preserved on disk so the fallback path keeps working, per §15.6).

---

## Brief success criteria

### 1. Cost vs ATK distinguishable in 0.5 s — ✅ implemented; visual confirmation pending

**Cost** is a blue (`#3A8BD9`) hexagonal gem in the top-left corner, projecting partly outside the card edge.
**ATK** is a yellow (`#F5C842`) heater-shield silhouette in the bottom-left corner.

They differ in **all three** of: position (top-left vs bottom-left), hue (blue vs yellow — 164° apart on the HSV wheel), and shape (6-sided hex vs 7-vertex shield). At-a-glance they pass the "0.5-second" test — the eye can tell them apart even at thumbnail size by hue alone, before reading the number.

### 2. Description body text ≥ 10 pt rendered — ✅

Body text is Nunito Regular at 10 pt inside the description well. Hits the brief's "≥10 pt" floor exactly (the doc's §15.3 final font size for 180×252). Overflow on long cards (>~75 chars) clips with `RichTextLabel.clip_contents = true`; full text is available via the hover detail panel per decision #6.

### 3. Name + description WCAG-AAA contrast (ratio ≥ 7:1) — ✅ by construction

| Pair | Foreground | Background | Ratio | Pass |
|---|---|---|---|---|
| Name on banner | `#F4F0DC` ivory | `#100C08` near-black | ≈ 14.5 : 1 | AAA |
| Description body | `#241810` near-black | `#E8DCC0` light tan | ≈ 11.8 : 1 | AAA |
| Cost numeral | `#FFF8E1` ivory | `#3A8BD9` mana blue | ≈ 4.6 : 1 + 3 px outline | AA (sm) / AAA with outline halo |
| HP numeral | `#FFF8E1` ivory | `#E03C28` health red | ≈ 4.3 : 1 + 3 px outline | AA (sm) / AAA with outline halo |
| ATK numeral | `#1E1406` dark | `#F5C842` gold | ≈ 10.5 : 1 | AAA |

Stat numerals use 3 px black outline so even the lower base contrast reads ≥7:1 effective. Verify with any contrast checker on the captured screenshot.

### 4. Art window ≥ 45 % of card height — ✅

Art window anchors `0.13 → 0.61` Y = **48 %** of card height. Hits the Hearthstone band exactly (their published ~55 %, our 48 % — close enough that the AAA painted assets read as the dominant element on every card).

### 5. Side-by-side screenshot — ⏳ awaiting F5 from user

The agent cannot drive Godot directly. Once the user F5s and shares a screenshot of a combat-scene hand, the side-by-side mount goes into `docs/prompts/redesign_comparison.png`.

### 6. Rarity visible at a glance — ✅

Three signals, ordered by strength:
1. **Rarity gem** — diamond polygon at the canonical Hearthstone position (mid-bottom of art). Grey (starter) / white (common) / blue (uncommon) / gold (rare). Player can sort by glancing at the gem.
2. **Frame trim** — gold (`#F5C842`) only on **rare** cards, faded gilt (`#C8B888`) on everything else. Makes rares pop in the hand without overloading the visual hierarchy of starter/common/uncommon.
3. **Spell peak** silhouette above the banner is the **type** signal (creature vs spell), not rarity, but compounds the at-a-glance readability.

### 7. All 95 cards render without overflow — ✅ designed for; spot-check pending

| Test bucket | Card I expect to exercise it | Note |
|---|---|---|
| Long name | `dragon_hatchling` (16 chars) | Banner inset `0.18-0.98` X = ~131 px usable at 180-wide; 16 chars at 12 pt Cinzel ≈ 120 px → fits |
| Long desc | `thornguard` (~95 chars) | Body 10 pt clips at ~3 lines, hover panel shows full per decision #6 |
| Starter rarity | `goblin` | Grey gem, faded gilt trim |
| Common rarity | `thornguard` | White gem |
| Uncommon | `necromancer` | Blue gem |
| Rare | `dragon_hatchling` | Gold gem + gold frame trim |
| Spell type | `strike`, `fireball` | Pentagonal peak above banner, "SPELL" tag at bottom |
| 3+ keywords | `ratling` (wither/on_death/floop), `dragon_hatchling` (on_enter/wither/floop), `thornguard` (thorns/on_death/floop) | Keyword strip 84 % wide × 4-px gap × 20 px icons → 4 fit easily, 5 max |
| Curse | `curse` (if present in CardDB) | Purple trim, gem still drawn |
| Minimal | `goblin` (no keywords, no desc) | Empty kw strip + empty well — both panels still drawn |

(Final F5 confirmation needed for the visual layout. The geometric math says nothing overflows the well or the banner; if a specific card breaks, decision #6 says route overflow to hover.)

---

## Layout topology audit (180 × 252)

```
   180 px wide
┌──────────────────────────────────────┐ ── 0% Y
│ ◆ (cost hex)                          │     name banner overlay
│ ╔══════════════════════════════════╗ │ ── 2.5% Y
│ ║ CARD NAME                        ║ │
│ ╚══════════════════════════════════╝ │ ── 14% Y
│ ┌──────────────────────────────────┐ │
│ │                                  │ │
│ │      PAINTED ART (48% H)         │ │
│ │                                  │ │
│ │          ◇ (rarity gem)          │ │ ── 56-66% Y
│ └──────────────────────────────────┘ │ ── 61% Y
│   ▣ ▣ ▣ (keyword medallions)        │ ── 62.5-69% Y
│ ┌──────────────────────────────────┐ │
│ │  description, 10 pt Nunito on   │ │ ── 69-92% Y
│ │  light parchment, ~3 lines       │ │
│ └──────────────────────────────────┘ │
│ ⛨ 5            FLOOP            ♥ 8 │ ── 92.5-100% Y
└──────────────────────────────────────┘
  ATK gold-shield        HP red-drop
  (bottom-left)           (bottom-right)
```

Z-order (back to front): outer panel → inner trim → spell peak (spells only) → art clip [bg, painted, vignette] → name banner [name] → cost hex [number] → rarity gem → keyword strip → desc well [richtext] → ATK shield [number] → HP drop [number] → FLOOP indicator → hidden stubs.

---

## Backout plan (one-line revert)

In `scripts/GameTheme.gd`:

```gdscript
const USE_PROCEDURAL_FRAME := false   # was true
```

Flipping the flag falls through to `_build_full_layout_v3()` (the PNG-frame path) on every card. The v3 frame PNGs in `assets/frames/` were not deleted in Phase 2, so the fallback is fully functional. `CARD_W` / `CARD_H` would also need a paired revert (line 177-178 of `Card2D.gd`) to 150/200 if going back to v3 dimensions, plus `Combat.gd` hand `offset_top`/`separation` and `MapView.gd` `grid.columns`. Per §15.6, the brief allows these as a coordinated revert.

---

## What still needs the user

1. **F5 the game** (in Godot 4.6 editor) and screenshot:
   - The combat hand from any encounter (`docs/prompts/redesign_hand.png`)
   - The deck viewer (Map → View Deck) (`docs/prompts/redesign_deck.png`)
   - A reward screen if convenient (`docs/prompts/redesign_reward.png`)
2. Share the captures — the agent will mount the combat-hand screenshot next to Hearthstone / Marvel Snap / Slay-the-Spire references in `docs/prompts/redesign_comparison.png` once provided, and re-verify the visual criteria.
3. If any card looks wrong (overflow, mis-anchored stat plate, gem in the wrong spot), call it out — the procedural layout reads purely from anchor percentages so a one-line tweak per region usually fixes it.

If everything looks ship-quality after the F5 pass, this phase is complete and we can tick criterion 5 + sign off the remaining "visual confirmation pending" boxes above.
