# Card visual redesign — agent brief

Paste this into a fresh Agent session (`general-purpose`, model: opus). The agent has full write access and may download CC0/public-domain assets.

---

## Mission

The current playing cards in [scripts/Card2D.gd](../../scripts/Card2D.gd) feel amateurish next to AAA digital card games. Your job is to make them objectively comparable in visual quality to the genre leaders: **Hearthstone, Marvel Snap, Slay the Spire, MtG Arena, Monster Train**. You have permission to redesign anything that isn't tied to gameplay logic — frame texture, layout, typography, color system, stat presentation, even card dimensions. You may download free/CC0 assets if existing ones are inadequate.

This is not a tweaking pass. It is a "ship-quality" pass. Treat the current card as a draft and ask: *if I put this card next to a Hearthstone card in a screenshot comparison, would a player rate them comparable?* If no, change what is needed.

## Game context

**Burning Meadow** — a Godot 4.6 lane combat roguelike deckbuilder (4 lanes, simultaneous combat, floop/sacrifice/spells). Read [CLAUDE.md](../../CLAUDE.md) for the design overview and [scripts/Card2D.gd](../../scripts/Card2D.gd) for the current card implementation. Cards must communicate:

1. **Cost** (mana, top-left orb area in current frame)
2. **Name** (banner near top)
3. **Card art** (the painted creature/spell illustration — DO NOT touch these PNGs in `assets/creatures/` or `assets/spells/`; they are AAA-quality and final)
4. **Type indicator** (creature vs. spell — currently distinguished by frame shape)
5. **Keywords** (icon medallions, see `KeywordEffects.tooltip_for()` for the list)
6. **Description** (rules text, e.g., "deal 2 to opposing creature")
7. **ATK** (creatures only, bottom-left orb)
8. **HP** (creatures only, bottom-right orb)
9. **Rarity** (starter/common/uncommon/rare — currently a hidden strip; should be visually present)
10. **Floop affordance** (some creatures have a tap ability — currently a label, may need a better treatment)

The hover detail panel ([Card2D.gd:1110](../../scripts/Card2D.gd:1110)) shows full text on mouseover — already good, do not redesign unless layout demands it.

## Known problems to objectively fix

Confirmed by user observation against reference games:

1. **Cost orb and ATK orb are both red.** They are visually indistinguishable except by corner position. Every comparable game uses different color + shape for cost vs. ATK (Hearthstone: blue gem vs. yellow sword shield; Marvel Snap: blue gem vs. yellow burst; MtG: colored mana symbols vs. P/T plate).
2. **Description text is 8pt on a small parchment well.** Genre standard for body text on a card is 10pt minimum (board game design guidance: never below 8pt for accessibility; 10–12pt for arm's-length reading).
3. **Name is 10pt on a dark banner.** Most genre cards use 14–18% of card height for the name; current implementation is closer to 7%.
4. **Card is 150×200 (0.75 aspect).** Smallest in the genre — Hearthstone, Marvel Snap, MtG Arena are all ~200×280. User has already approved going to 180×240 or larger if it helps.
5. **Frame allocates ~37% of height to art.** Hearthstone gives ~55%, Marvel Snap ~75%. The cramped art window contributes to poor card identity at a glance.

## Research phase (mandatory, do NOT skip)

Before designing, collect concrete reference data. Use WebFetch/WebSearch to gather:

1. **Reference card screenshots** for each of: Hearthstone (minion card), Marvel Snap (any card), Slay the Spire (attack and skill cards), MtG Arena (creature card), Monster Train (unit card). Save observations to a scratch file.
2. For each reference, record (with approximate measurements where possible):
   - Aspect ratio
   - Art window as % of card height
   - Name banner as % of card height
   - Description area as % of card height
   - Cost shape, color, position
   - ATK shape, color, position (if applicable)
   - HP shape, color, position (if applicable)
   - Where rarity is shown
3. **Read at least two of these design-perspective sources** for typography and hierarchy:
   - [What the Font?! Type Tips for Board Game Designers](https://www.leagueofgamemakers.com/what-the-font-type-tips-for-board-game-designers/)
   - [5 Graphic Design and Typography Tips for your Card Game](https://danielsolisblog.blogspot.com/2011/11/5-graphic-design-and-typography-tips.html)
   - [4 Layout Tips for Designing Card Games](https://medium.com/@dylanmangini/4-layout-tips-for-designing-card-games-17cc98b89b96)
   - [Tabletop Graphic Design: Game Cards 101](https://www.mattpaquette.com/design-blog/2018/7/9/tabletop-graphic-design-card-framworks-101)
4. **Conclude the research with a one-paragraph design thesis** stating: *what paradigm we should adopt* (art-forward Marvel-Snap style, text-rich Slay-the-Spire style, or balanced Hearthstone style) and *why it fits Burning Meadow*.

## Hard requirements (do not break)

- The autoload singletons (`RunState`, `CardDB`, `RelicDB`, `KeywordEffects`, `EncounterDB`) must keep working unchanged.
- The card data schema in CardDB cannot change.
- All 9 information types above must still be present (cost, name, art, type, keywords, description, ATK, HP, rarity). Hover panel is allowed to absorb description if hand card is art-forward.
- Compact battlefield mode (`set_compact_mode`) must still produce a token that fits in a 140×145 slot (or you must update `_make_lane_slot` in [Combat.gd:2991](../../scripts/scenes/Combat.gd:2991) accordingly).
- Game must still run with F5 in Godot — no scene tree refactors that break instancing.

## Objective success criteria (measure, don't guess)

Write these to a `redesign_checklist.md` in `docs/prompts/` before claiming completion:

1. **Cost vs ATK distinguishable in 0.5s.** Place a screenshot of your redesign next to a Hearthstone screenshot. Can you tell which icon is cost and which is ATK without reading the numbers? They must differ in *both* color *and* shape, not just position.
2. **Description body text ≥10pt rendered.** Or, if you've gone art-forward and removed description from the hand card, that's also acceptable.
3. **Name text legibility.** Set a contrast ratio target ≥7:1 for name text against its background (WCAG AAA). Measure with any contrast checker. Use this for description body too.
4. **Art window proportion target ≥45% of card height** for a hand card (Hearthstone band). Or ≥65% if going art-forward.
5. **Side-by-side screenshot in `docs/prompts/redesign_comparison.png`.** Mount your new card next to Hearthstone, Marvel Snap, and Slay the Spire cards at matched render heights. The new card should not look obviously worse than any of the three. You will need to take a screenshot in Godot and composite — ask the user to F5 the game and screenshot if you cannot drive Godot directly.
6. **Rarity must be visible at a glance.** Color-coded frame trim, gem, or banner — not a hidden strip. A player should be able to sort a deck by rarity from the hand display alone.
7. **All 95 cards (`CardDB.CARD_POOL`) render without text overflow or clipping.** Spot check at least 12 cards covering: long names (e.g. "Dragon Hatchling"), long descriptions (any 3+ effect card), all four rarities, both spell and creature types, cards with 3+ keywords.

## Asset sourcing rules

You may download free/CC0/public-domain assets if existing ones are inadequate. Strict rules:

- **Allowed sources:** OpenGameArt.org, Kenney.nl, itch.io free assets, game-icons.net (CC-BY 3.0), Vecteezy free tier, public-domain fine-art repositories (WikiArt CC0, Wikimedia Commons).
- **Banned:** anything requiring attribution payment, Adobe Stock paid, GraphicRiver paid, ArtStation marketplace.
- **Quality bar (per user's standing instruction):** for any new illustration/painting asset, only AAA-tier masters in the public domain (Doré, Vrubel, Fuseli, Beksiński estate where licensed, etc.). For UI elements (frames, orbs, icons), Kenney/game-icons style is fine.
- **Process for each asset:**
   1. State what you want, why existing one is insufficient, where you plan to source it.
   2. Check Content-Length before downloading. If >2MB binary or PSD/XCF/ZIP, find an alternative or ask the user.
   3. Download to `assets/` with a clear name and add a credit line to `CREDITS.md`.
   4. One asset at a time. Verify it renders correctly before grabbing the next.
- **Frame template:** the current frame is `assets/frames/frame_creature_common.png` and variants. If you redesign it, either commission a new PNG from a free CC0 source, generate one procedurally with Godot drawing code (best — no asset dependency), or modify the existing one. **Strong preference for procedural drawing** — gives perfect rarity variants and per-card customization with zero asset weight.

## Implementation phases

### Phase 1 — Design doc (no code yet)

Output `docs/prompts/card_design_doc.md` containing:
- Research findings table (the reference comparison)
- Design thesis paragraph
- Chosen paradigm (art-forward / text-rich / balanced) with reasoning
- New card dimensions + aspect ratio
- New layout spec: where each of the 10 information elements goes, sized in card-relative percentages (not pixels)
- New color system for cost/ATK/HP (with hex values and rationale referencing reference games)
- New typography system: which font (download if needed from Google Fonts), at what sizes for each role
- Frame approach: procedural draw vs. PNG vs. modified existing
- Sketch (ASCII art or a Mermaid diagram is fine) showing element positions
- Migration plan from current layout → new layout, listing every file that changes
- Backout plan if the user dislikes it (keep current code path behind a `USE_NEW_FRAME` style flag if structurally possible)

**STOP HERE and present the design doc to the user before writing any code.** If they approve, proceed. If they want changes, iterate on the doc only.

### Phase 2 — Implementation

Once design is approved:
1. Implement the new layout in [Card2D.gd](../../scripts/Card2D.gd). Preserve the existing `_build_full_layout_v3` function and add a `_build_full_layout_v4` (or your name); flip via a constant flag.
2. Update [Combat.gd](../../scripts/scenes/Combat.gd) hand container sizing if card dimensions change.
3. Update [MapView.gd](../../scripts/scenes/MapView.gd) `_show_deck_viewer` if card dimensions change.
4. Update [Reward.gd](../../scripts/scenes/Reward.gd) layout if card dimensions change.
5. If you went procedural for the frame: implement frame drawing in a new helper (e.g. `_draw_procedural_frame`) on Card2D, accepting card rarity, type, and faction (player vs enemy) to color the variant. This sidesteps PNG-asset work entirely and gives you free rarity variants.

### Phase 3 — Verification

1. Ask the user to F5 the game and screenshot the hand from a combat scene, the deck viewer (map screen → View Deck), and a reward screen. Or, if Godot can be invoked headless, do it yourself.
2. Mount the screenshots next to Hearthstone/Marvel Snap/Slay-the-Spire references in `docs/prompts/redesign_comparison.png`.
3. Re-check every objective success criterion. Tick them off in `redesign_checklist.md`.
4. If any criterion fails, iterate on Phase 2 and re-verify. Do not declare done until all are checked.

## Anti-patterns to avoid

- **Don't change font sizes without re-running [tools/measure_frame.py](../../tools/measure_frame.py)** if you keep the PNG frame. The POINT_* constants in Card2D are tied to specific pixel regions of `frame_creature_common.png`. Changing one without the other breaks alignment.
- **Don't write a README or PR description until the user asks.** The brief is the spec.
- **Don't pile on emojis or decorative Unicode** in card text — they read fine on web but render inconsistently in Godot's text renderer at small sizes.
- **Don't introduce backwards-compatibility shims for stale config.** If you change the card size constant, you can change every dependent value too.
- **Don't fall into "Hearthstone clone" — if Hearthstone made bad choices for our game, make different ones.** Burning Meadow is a roguelike deckbuilder with simultaneous combat. The cards may need different prominence rules than a 1v1 ladder game.

## Deliverables

When complete:
- `docs/prompts/card_design_doc.md` (Phase 1 output)
- `docs/prompts/redesign_checklist.md` (Phase 3 verification with all boxes ticked)
- `docs/prompts/redesign_comparison.png` (side-by-side reference screenshot)
- Modified [Card2D.gd](../../scripts/Card2D.gd), [Combat.gd](../../scripts/scenes/Combat.gd), [MapView.gd](../../scripts/scenes/MapView.gd), [Reward.gd](../../scripts/scenes/Reward.gd) as needed
- New procedural frame draw code (preferred) or new PNG frame assets
- `CREDITS.md` updated if any external assets were added
- A short summary (≤200 words) of what changed, with one before/after comparison call-out, in the final message

If you hit any blocker that can't be resolved without product input (e.g., "the user wants art-forward but the hover panel doesn't make sense in that paradigm"), stop and ask. Do not assume.
