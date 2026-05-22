# Burning Meadow — Complete Card Game Asset Reference

> Every visual, audio, and UI asset a lane-combat roguelike deckbuilder needs,
> with current inventory status and what's missing.

---

## Current Project Stats

| Metric | Count |
|--------|-------|
| Creature cards (player) | 59 |
| Creature cards (enemy-only) | 18 |
| Spell cards | 45 |
| **Total unique cards** | **122** |
| Relics | 36 |
| Keywords | 16 |
| Scenes | 10 (menu, map, combat, shop, rest, event, reward, game over, collection, card_2d) |
| Acts | 3 |
| Encounters | 26 |

---

## 1. CARD ANATOMY — Every Element on a Single Card

A professional card is 12-18 layered visual elements composited together. Here is every one:

### 1.1 Card Frame / Border
**What:** The outer edge and structural skeleton of the card. Everything else sits on top of or inside it.
**How AAA does it:** Hearthstone uses 3D-rendered stone/metal frames. Slay the Spire uses flat colored frames per rarity. Legends of Runeterra has ornate painted metalwork. MtG Arena uses layered PNGs with parallax.
**Size:** Source art at 600x840 minimum (2x your 300x400 render size). 1000x1400 for future-proofing.
**Regions the frame must define:**
- Art window cutout (where creature/spell illustration goes)
- Name banner area (horizontal ribbon, top third)
- Type line strip (thin band below art or on divider)
- Description well (parchment/text body area, lower half)
- Cost badge seat (upper-left corner, overlapping frame edge)
- ATK badge seat (lower-left, creatures only)
- HP badge seat (lower-right, creatures only)
- Rarity indicator position (bottom-center gem, or frame tint)
- Keyword icon strip area (between art and description, or along bottom)

**YOUR STATUS:** 9 frame PNGs at `assets/frames/` — creature (starter/common/uncommon/rare) + spell (starter/common/uncommon/rare) + curse. Also have a procedural v4 frame (PolyBadge system) that draws everything in code.

### 1.2 Art Window / Portrait Area
**What:** The illustration opening where creature or spell art is displayed. Masked by the frame's transparent region or a clipping shader.
**Size:** Depends on frame design. Typically 60-70% of card width, 35-45% of card height. At 300x400 that's roughly 180-210 x 140-180 px visible.
**Aspect ratio:** Landscape-ish (4:3 or 5:4) for the visible window even though the card itself is portrait. This gives creature art breathing room.
**Masking:** Frame PNG has a transparent cutout, or a shader clips art to a shape (oval, rounded rect, irregular). Rounded/organic shapes feel more premium than hard rectangles.

### 1.3 Name Banner / Title Ribbon
**What:** Horizontal band holding the card name. Often a painted ribbon or scroll shape that overlaps the frame and art window for depth.
**Design:** Dark interior for text contrast. Gold/metallic trim on edges. Slightly transparent or with a vignette fade at the sides. Tapered or pennant-shaped ends feel more fantasy than flat rectangles.
**Typography:** Display serif font, all-caps or title-case. 10-14pt equivalent at render size. Must be legible when cards are fanned in hand (roughly 60% zoom).
**YOUR STATUS:** Cinzel SemiBold (wght 600). V4/v5 layout draws banner procedurally.

### 1.4 Mana Cost Badge
**What:** Upper-left corner badge showing the card's mana cost. The single most important at-a-glance number.
**Shape options:** Hexagonal crystal (Hearthstone), circle (Slay the Spire, LoR), diamond, runestone, orb.
**Size:** 28-40px diameter at card render scale. Must read clearly when hand is fanned.
**Design layers (top to bottom):**
1. Drop shadow (lifts badge off frame)
2. Gradient fill (bright top, darker bottom = "lit from above")
3. Top-half highlight (white 15-20% opacity = glossy sheen)
4. Specular dot (small bright circle near top-left = glass highlight)
5. Numeral (bold, high contrast against fill, with its own thin shadow)
6. Border ring (1-2px darker outline around the shape)

**Color:** Blue is near-universal for mana cost (Hearthstone blue crystal, LoR blue gem, MtG blue generic). Purple and teal also work.
**YOUR STATUS:** Procedural PolyBadge (hex shape) with painted `cost_runestone.png` overlay. Blue fill, Cinzel Black numeral.

### 1.5 Attack Stat Badge
**What:** Bottom-left. Creature-only. Shows ATK value.
**Shape:** Sword/weapon silhouette (Hearthstone), shield shape, circle, angular plate.
**Color:** Yellow/gold is nearly universal for attack across all AAA card games.
**Design:** Same layered approach as mana badge (shadow, gradient, highlight, spec, numeral, border).
**YOUR STATUS:** Shield-shaped PolyBadge, yellow fill, `atk_sword.png` overlay.

### 1.6 Health / HP Stat Badge
**What:** Bottom-right. Creature-only. Shows HP value.
**Shape:** Blood drop (Hearthstone), heart, circle, rounded plate.
**Color:** Red is universal for health.
**Damage state:** When HP is reduced below max, the number turns a warning color (orange or deeper red) and/or the badge gets a cracked/damaged overlay.
**YOUR STATUS:** Drop-shaped PolyBadge, red fill, reuses HUD heart.

### 1.7 Rarity Indicator
**What:** Visual signal for card rarity. Two approaches:
- **Gem approach** (Hearthstone): Small gemstone at bottom-center of portrait. White=common, blue=uncommon, purple=rare, gold=legendary.
- **Frame tint approach** (Slay the Spire): Entire frame changes color by rarity. Grey=common, blue=uncommon, gold=rare.
- **Both** is even better — gem + subtle frame color shift.

**Size:** 10-16px for a gem. Full frame for tint approach.
**YOUR STATUS:** Diamond-shaped PolyBadge rarity gem + separate frame PNGs per rarity (color-distinct).

### 1.8 Type Line
**What:** Text showing card type — "Creature", "Spell". Could include subtypes if you add them later (Beast, Undead, Dragon...).
**Position:** Just below art window, on the divider between art and description well.
**Typography:** Smaller than name (8-10pt), often italic or lighter weight. All-caps or small-caps.
**YOUR STATUS:** Label in Card2D layout. Shows "CREATURE" or "SPELL".

### 1.9 Description / Rules Text Well
**What:** The text area for card abilities, effects, keyword descriptions.
**Background:** Light-colored parchment or scroll texture. CRITICAL: dark text on light background. Light text on dark is significantly harder to read for anything beyond 5 words.
**Typography:** Sans-serif body font at 9-11pt. Keywords bold and/or color-tinted. Use RichTextLabel/BBCode for inline bold, color, and icons.
**Line spacing:** 1.5x minimum for legibility at small card sizes.
**YOUR STATUS:** Nunito Regular with embolden for body. BBCode for bold keywords.

### 1.10 Keyword Icon Strip
**What:** Small icons representing card keywords (Armored, Swift, Thorns...). Displayed as a horizontal row.
**Position:** Between art and description, or along top/bottom edge of description well.
**Size:** 16x16 to 20x20 on-card. 24x24 to 32x32 in tooltips.
**Design:** Must read as silhouettes at small sizes. Bold shapes, not detailed illustrations.
**YOUR STATUS:** 16 keyword SVG icons at `assets/icons/keywords/`. COMPLETE.

### 1.11 Card Back
**What:** Reverse side shown for face-down cards (draw pile, hidden cards).
**Elements:** Game logo/emblem centered. Decorative repeating pattern. Must be identical for ALL cards (no information leak).
**Use cases in your game:** Draw pile visual, any face-down mechanics you add later.
**Variants:** Cosmetic unlockable card backs are a common progression reward.
**YOUR STATUS:** NOT IMPLEMENTED. Need at minimum 1 card back design.

### 1.12 Upgrade Indicator
**What:** Visual cue that a card has been upgraded. Slay the Spire adds a green border tint + star icon.
**Options for your 3 upgrade paths:**
- Sharpen: Small sword/blade icon on frame edge, or orange/red tint accent
- Fortify: Small shield icon, or blue/grey tint accent
- Imbue: Small rune/magic icon, or purple/arcane tint accent
- Or: 1 generic "upgraded" star/plus badge regardless of path
**YOUR STATUS:** Upgrade system exists in code but no visual indicator on cards.

### 1.13 Floop Indicator
**What:** Visual showing a creature can or will floop. Toggle state.
**Current:** Text/icon on battlefield cards.
**Ideal:** Animated glow, swirl, or pulsing icon overlay when floop is toggled on.
**YOUR STATUS:** Basic indicator exists. Could be enhanced.

### 1.14 Spell Type Indicator
**What:** For spell cards — visual at the top (where creature has ATK/HP) indicating it's a spell. Could be a "SPELL" label, a different frame shape, a spell school icon, etc.
**Hearthstone approach:** Spell cards have no attack/health, the frame shape itself is different.
**YOUR STATUS:** "SPELL" label + different frame PNGs for spell rarity.

---

## 2. CARD FRAME VARIANTS — Full Inventory Needed

### Minimum Set (what you have)
| Frame | Creature | Spell |
|-------|----------|-------|
| Starter | frame_creature_starter.png | frame_spell_starter.png |
| Common | frame_creature_common.png | frame_spell_common.png |
| Uncommon | frame_creature_uncommon.png | frame_spell_uncommon.png |
| Rare | frame_creature_rare.png | frame_spell_rare.png |
| Curse | frame_curse.png | — |
| **Subtotal** | **5** | **4** |

### Recommended Additions
| Frame Type | Count | Purpose |
|------------|-------|---------|
| Upgraded creature (generic or x3 paths) | 1-3 | Visual for Sharpen/Fortify/Imbue upgraded creatures |
| Upgraded spell (generic or x3 paths) | 1-3 | Visual for upgraded spells |
| Enemy creature frame | 1 | Distinct red/dark border so enemy cards are instantly recognizable |
| Token creature frame | 1 | Simpler frame for summoned tokens (not real cards) |
| Boss/legendary frame | 1 | Extra-ornate for boss encounters |
| **Addition subtotal** | **5-9** | |

### Total Frame Budget
- **Current:** 9
- **Recommended:** 14-18
- **AAA standard:** 25-40+

---

## 3. CARD ART — Portraits and Illustrations

### 3.1 Creature Portraits

**Needed:** 77 unique (59 player + 18 enemy creatures)
**Have:** 48 files (40 PNG + 8 JPG) at `assets/creatures/`
**Gap:** ~29 creatures still need art

**Resolution:** Source at 512x512 minimum. 1024x1024 recommended. Gets downsampled to ~180x160 in the art window.
**Format:** PNG (transparency for irregular masking) or JPG (rectangular, clipped by frame).
**Style guidance for your game:**
- You mentioned anime-like would work. Anime/JRPG style is great for this genre — vibrant, clean, character-focused.
- Alternatives: painterly fantasy (Slay the Spire), stylized cartoon (Card Wars), dark illustrated (Inscryption), pixel art (retro aesthetic).
- Whatever style you pick, ALL creature art must use the same style. Mixing painterly classical art with anime will look incoherent.
- Consistent lighting direction across all portraits (top-left is standard).
- Consistent color temperature (warm fantasy vs cool dark — pick one palette).
- Bust/portrait crops (head + shoulders + weapon) work better than full-body at card scale.

**Composition tips:**
- Subject should fill 70-80% of the frame
- Eyes near the upper third (draws attention)
- Simple, non-distracting backgrounds (gradient, smoke, color wash)
- High contrast between subject and background so the creature pops in the small art window

### 3.2 Spell Illustrations

**Needed:** 45 unique
**Have:** 45 files at `assets/spells/` (plus ~100 painterly color variants in `painterly-1/`)
**Gap:** Numerically covered, but check if every spell ID has a matching file

**Style:** Spell art depicts the magical effect (fire, shield, dark energy) rather than a character. Abstract energy effects, magical circles, elemental bursts all work.
**Approach options:**
- Unique illustration per spell (AAA — expensive)
- Base effect type with color/intensity variants (what your painterly-1 folder does — smart for indie)
- Icon-style simplified illustrations (less immersive but very readable at card size)

### 3.3 Art Production Pipeline
- Commission or generate at high resolution (1024x1024+)
- Crop to art window aspect ratio
- Color-correct for consistency across the set
- Export as PNG or JPG per your import settings
- Name file to match card ID (e.g., `ranger.png` for card ID "ranger")
- Add to `assets/creatures/` or `assets/spells/`

---

## 4. UI ELEMENTS — Complete Inventory

### 4.1 Buttons

| Button Type | States Needed | Notes |
|-------------|---------------|-------|
| **End Turn** (primary CTA) | Normal, Hover, Pressed, Disabled, Pulsing | Largest button in combat. Green/gold when active, grey when disabled. Gently pulses when player has no actions left. |
| **Confirm / OK** | Normal, Hover, Pressed | For dialogs, reward selection. |
| **Cancel / Back** | Normal, Hover, Pressed | Subdued color (grey/brown). |
| **Shop Buy** | Normal, Hover, Pressed, Disabled (can't afford) | Shows price. Gold accent. |
| **Sacrifice [S]** | Normal, Hover, Pressed, Disabled (already used) | Dark/red themed. |
| **Floop toggle** | On state, Off state, Hover | Two-state toggle on battlefield creatures. |
| **Map node** | Locked, Available, Visited, Current | Color per node type + state overlays. |
| **Settings gear** | Normal, Hover, Pressed | Small icon button. |
| **Close / X** | Normal, Hover, Pressed | Panel dismiss. |
| **Arrow (scroll)** | Normal, Hover, Pressed | For card browsing. |
| **Total** | ~10 base types x 3-5 states | **~35-50 button sprites**, or procedural with style overrides |

### 4.2 Panels and Windows

| Panel Type | Usage | Notes |
|------------|-------|-------|
| **Modal window** | Shop, reward pick, event choices, settings, deck viewer | NinePatch texture. Parchment/dark wood feel. Needs close button. |
| **Tooltip popup** | Keyword explanations, card hover detail | Small, with arrow/tail pointing at source. Dark or parchment. |
| **Notification banner** | "Round 3", "Enemy Turn", "Swift Phase" | Slides in from top/side, holds, slides out. Gold/dark. |
| **Confirmation dialog** | "Are you sure?" for card removal, purchases | Small modal with Yes/No. |
| **Card detail popup** | Enlarged card on hover/click | Just a scaled-up card + keyword explanations below. |
| **Health bar track** | Player HP, enemy HP | Horizontal bar: dark track + red fill + text overlay. |
| **Total** | 5-7 distinct panel NinePatches | |

**YOUR STATUS:** Have Kenney Fantasy UI Borders + Kenney Borders packs. Currently building HUD procedurally in code.

### 4.3 HUD (Heads-Up Display) — Combat Screen

| Element | Icon/Asset | Status |
|---------|-----------|--------|
| Player HP (heart + number) | `hud_heart_painted.png` | DONE |
| Gold counter (coin + number) | `hud_gold_painted.png` | DONE |
| Potion slots (bottle + count) | `hud_potion_painted.png` | DONE |
| Relic display (relic icon) | `hud_relic.png` | DONE |
| Deck counter (card stack + count) | `hud_deck.png` | DONE |
| Mana display (crystals or number) | — | NEEDED: filled + empty mana crystal icons, or just numeric |
| Discard pile (face-up stack + count) | — | NEEDED |
| Exhaust pile (fire/X icon + count) | — | NEEDED |
| Enemy HP display | — | NEEDED: reuse heart icon + bar, or distinct enemy format |
| Encounter name + passive label | — | Text only currently, could use a banner/frame |
| Round counter | — | NEEDED if not just text |

### 4.4 Scrollbars

| Part | Notes |
|------|-------|
| Track (vertical) | NinePatch, dark/subtle |
| Thumb (normal + hover + pressed) | 3 states, lighter color |
| Arrow buttons (up/down) | Optional, 2 sprites |
| **Total** | 5-7 sprites |

**Needed for:** Collection viewer (95+ cards), deck viewer, shop scroll, event text overflow.

---

## 5. COMBAT BATTLEFIELD — Lane System Assets

### 5.1 Lane Slots

| Asset | Description | Count |
|-------|-------------|-------|
| **Empty slot (player)** | Dashed outline or subtle glow showing where a card can be placed. | 1 texture, tiled x4 lanes |
| **Empty slot (enemy)** | Same but enemy-colored (red tint?) | 1 texture |
| **Valid drop target** | Bright highlight (green glow, golden border) when dragging a card over a valid lane | 1 overlay |
| **Invalid drop target** | Red tint or X overlay when lane is occupied/invalid | 1 overlay |
| **Selected/active slot** | Highlight for the currently acting creature during combat resolution | 1 overlay |
| **Lane divider** | Vertical line or decorative separator between lanes | 1 texture |
| **Battlefield center divider** | Horizontal separator between player and enemy rows | 1 texture (could be ornate) |
| **Total** | ~7 lane-related textures | |

### 5.2 Targeting System

| Asset | Description |
|-------|-------------|
| **Targeting line/arrow** | Curved line from spell source to mouse cursor. Tileable arrow texture along a Line2D or similar. Red/gold color. |
| **Arrow head** | Pointed tip at the target end. |
| **Target reticle** | Circular indicator on hovered target. Pulsing/rotating. |
| **Valid target glow** | Green highlight ring around creatures that can be targeted. |
| **Invalid target dim** | Grey overlay or red X on untargetable creatures. |
| **Total** | 4-5 targeting sprites/textures |

### 5.3 Floating Combat Text

No sprite assets needed — these are font-rendered Labels with tween animations:

| Text Type | Color | Font | Animation |
|-----------|-------|------|-----------|
| Damage dealt | Red | Cinzel Black 18-24pt | Float up + fade out, 0.5-0.8s |
| Heal amount | Green | Cinzel Black 18-24pt | Float up + fade out |
| Buff applied | Gold/yellow | Cinzel SemiBold 14pt | Float up + fade out |
| Debuff applied | Purple | Cinzel SemiBold 14pt | Float up + fade out |
| Gold gained | Gold | Cinzel SemiBold 14pt | Float toward gold counter |
| "BLOCKED" / "ARMORED" | Grey/silver | Cinzel SemiBold 12pt | Brief flash + fade |
| "LAST STAND" | Gold | Cinzel Bold 14pt | Flash + pulse + fade |
| "PIERCING" | Orange/red | Cinzel Bold 12pt | Arrow trail toward enemy hero |

### 5.4 Player / Enemy Hero Area

| Element | Description |
|---------|-------------|
| **Player portrait/icon** | Small avatar (64x64 to 96x96). Could be a generic hero, a class icon, or the game logo. |
| **Enemy portrait** | Per-encounter portrait. Could reuse the encounter's signature creature art. |
| **HP bar** | Horizontal: dark track + red fill. Text overlay "15/25". Needs to be readable at a glance. |
| **HP bar flash** | Brief red flash/pulse on the bar when damage is taken. |
| **Shield/armor overlay** | If a creature or hero gains armor — secondary indicator on HP bar. |

---

## 6. MAP SCREEN — Node-Based Branching Map

### 6.1 Node Icons

| Node Type | Current Asset | Status |
|-----------|--------------|--------|
| Normal combat | `node_combat.png` | DONE |
| Elite combat | `node_elite.png` | DONE |
| Boss | `node_boss.png` | DONE |
| Rest / campfire | `node_rest.png` | DONE |
| Shop / merchant | `node_shop.png` | DONE |
| Event / unknown | `node_event.png` | DONE |
| Treasure / reward | — | CONSIDER ADDING |
| Mystery / unknown | — | CONSIDER ADDING (question mark) |

**Icon size:** 32x32 to 48x48 at map render scale.
**States per icon (3 minimum):**
- Locked/unavailable: dimmed, greyed, lower opacity
- Available/reachable: bright, gold border, possibly pulsing
- Visited/completed: checkmark overlay or distinct color (green tint)
- Current position: extra-bright, pulsing glow, larger scale

### 6.2 Connection Lines

| Element | Description |
|---------|-------------|
| **Path line** | Line2D connecting nodes. 2-4px width, anti-aliased. |
| **Unvisited path** | Dim/grey dashed line. |
| **Available path** | Bright/gold, possibly glowing or thicker. |
| **Visited path** | Solid, slightly dimmed. Colored to show completion. |
| **Path animation** | Optional: dotted line that "flows" toward available nodes. |

### 6.3 Map Background

| Variant | Current | Status |
|---------|---------|--------|
| Act 1 map | `map_parchment.jpg` | DONE (shared) |
| Act 2 map | — | RECOMMENDED: different parchment tone or terrain |
| Act 3 map | — | RECOMMENDED: darker/more dramatic parchment |

Different map backgrounds per act immediately communicates progression. Even a color grade shift (warm Act 1, cool Act 2, dark Act 3) on the same texture helps.

### 6.4 Act Transition

| Element | Description |
|---------|-------------|
| **Act title card** | Full-screen or large banner: "Act II" with dramatic typography. Dark background. |
| **Boss intro screen** | Boss art + name + flavor text before boss combat. Optional but very impactful. |
| **Transition animation** | Fade-to-black, scroll wipe, or map "zoom" into the next act's territory. |

---

## 7. SCENE BACKGROUNDS — Every Screen Needs One

| Scene | Current Asset | Status | Notes |
|-------|--------------|--------|-------|
| Main Menu | `main_menu.jpg` | DONE | Needs game logo overlay |
| Map (Act 1) | `map_parchment.jpg` | DONE | |
| Map (Act 2) | — | MISSING | Different tone recommended |
| Map (Act 3) | — | MISSING | Darker/dramatic recommended |
| Combat (normal) | `combat_arena.jpg` | DONE | Dark, doesn't compete with cards |
| Combat (elite) | — | OPTIONAL | Slightly different, more ominous |
| Combat (boss) | — | OPTIONAL | Dramatic, unique per boss ideal |
| Shop | `shop_tavern.jpg` | DONE | |
| Rest Site | `rest_campfire.jpg` | DONE | |
| Event | `event_forest.jpg` | DONE | |
| Reward | — | MISSING | Victory/triumph theme, or reuse combat BG |
| Game Over (defeat) | `triumph_of_death.jpg` | DONE | |
| Game Over (victory) | — | MISSING | Bright/triumphant theme |
| Collection / Deck Viewer | — | MISSING | Neutral: dark wood, bookshelf, or dark gradient |
| Settings overlay | — | N/A | Semi-transparent dark overlay, no art needed |

**Resolution:** 1920x1080 minimum. JPG is fine (no transparency needed). 200-500KB per image.
**Design rule:** Backgrounds must be dark and desaturated enough to not compete with foreground cards and UI. Card games use subdued backgrounds because cards are the visual focus.

**Total backgrounds:**
- Current: 7
- Recommended additions: 4-6 (victory, collection, per-act map variants)
- AAA: 15-20+ (per-act combat, per-boss arenas, seasonal variants)

---

## 8. ICONS AND SYMBOLS — Complete Catalog

### 8.1 Keyword Icons (on-card)

All 16 done at `assets/icons/keywords/`:
armored, swift, thorns, piercing, last_stand, ranged, regenerate, wither,
on_enter, on_death, floop, sacrifice, exhaust, retain, adj_buff, summon

### 8.2 HUD Icons

| Icon | File | Status |
|------|------|--------|
| Heart (HP) | `hud_heart_painted.png` | DONE |
| Gold coin | `hud_gold_painted.png` | DONE |
| Potion bottle | `hud_potion_painted.png` | DONE |
| Relic | `hud_relic.png` | DONE |
| Draw pile / deck | `hud_deck.png` | DONE |
| Discard pile | — | MISSING |
| Exhaust pile | — | MISSING |
| Mana crystal (filled) | — | MISSING |
| Mana crystal (empty) | — | MISSING |

### 8.3 Relic Icons — MAJOR GAP

**Needed:** 36 unique relic icons (one per relic in RelicDB)
**Have:** 0 individual relic icons
**Size:** 32x32 to 48x48 for inventory display. 64x64 for detail popup.
**Style:** Must be consistent across all 36 — all painted, all pixel art, or all line-art.

**Relics needing icons (by tier):**

Starting (8):
Iron Buckler, Ember Crown, Courier's Bag, Coin Purse, Worn Spellbook,
Scout's Emblem, Soul Lantern, Veteran's Medal

Combat (23):
War Drum, Banner of Unity, Swift Boots, Fortress Stone, Briar Amulet,
Echo Staff, Piercing Crown, Conscription, Ritual Dagger, Bone Pile,
Blood Chalice, Gladiator's Belt, Harvester's Scythe, Runic Compass,
Frost Sigil, Phoenix Feather, Ironwood Shield, Battle Standard,
Executioner's Hood, Storm Caller, Shadow Cloak, Berserker's Totem,
Dragon Scale

Utility (5):
Merchant's Charm, Healing Salve, Map Fragment, Lucky Coin, Survival Kit

**Tip:** Relic icons at game-icons.net (CC-BY 3.0, 4000+ icons) can cover most of these thematically. Search for: buckler, crown, bag, purse, spellbook, emblem, lantern, medal, drum, banner, boots, stone, amulet, staff, etc.

### 8.4 Upgrade Path Icons

| Path | Icon Description | Status |
|------|-----------------|--------|
| Sharpen | Whetstone, blade, sparks | MISSING |
| Fortify | Shield, stone wall, anvil | MISSING |
| Imbue | Magic rune, glowing crystal, arcane circle | MISSING |

Displayed at rest sites during upgrade selection. 48x48 to 64x64.

### 8.5 Card Stat Overlay Icons

| Icon | File | Status |
|------|------|--------|
| Cost (mana runestone) | `cost_runestone.png` | DONE |
| ATK (sword) | `atk_sword.png` | DONE |
| HP (heart) | reuses HUD heart | DONE |

### 8.6 Miscellaneous Icons

| Icon | Purpose | Status |
|------|---------|--------|
| Sacrifice mode indicator | Shows sacrifice is active/available | Have `sacrifice.svg` keyword icon |
| Gold coin (small, for shop prices) | Inline with price text | Could reuse `hud_gold_painted.png` scaled down |
| Potion (small, for shop) | Inline potion display | Reuse `hud_potion_painted.png` |
| Lock icon | Locked/unavailable content | Have Kenney `locked.png` |
| Checkmark | Completed/selected | Have Kenney `checkmark.png` |
| Settings gear | Settings button | Have Kenney `gear.png` |

---

## 9. VISUAL EFFECTS / PARTICLES

### 9.1 Combat Effects (Priority Order)

| Effect | What It Looks Like | Implementation | Priority |
|--------|-------------------|----------------|----------|
| **Card draw** | Card slides from deck position to hand with slight arc | Tween: position + rotation + scale | HIGH |
| **Card play** | Card moves from hand to battlefield slot. Brief scale-up "pop" on arrival | Tween: position + scale overshoot | HIGH |
| **Attack hit** | White flash on damaged creature (0.05s). Screen shake (0.1-0.3s, 2-5px). Damage number floats up. | Modulate flash + CanvasLayer offset + Label tween | HIGH |
| **Creature death** | Fade to transparent + optional particle burst (grey/red specks) | Tween: modulate alpha + CPUParticles2D | HIGH |
| **Spell cast** | Glow/particle effect at target. Color matches spell element. | CPUParticles2D or AnimatedSprite | MEDIUM |
| **Heal** | Green particles floating upward from healed creature | CPUParticles2D: green, upward velocity | MEDIUM |
| **Buff applied** | Gold sparkle around creature. Brief upward arrow icon. | CPUParticles2D: gold + icon flash | MEDIUM |
| **Debuff applied** | Purple/dark particles. Brief downward arrow icon. | CPUParticles2D: purple + icon flash | MEDIUM |
| **Floop activation** | Swirl/spin effect on flooping creature. Colored ring. | Tween: rotation + ring shader/sprite | MEDIUM |
| **Sacrifice** | Dark particles rising. Red flash on creature. | CPUParticles2D: dark red, upward | MEDIUM |
| **Round start banner** | "Round 3" text slides in, holds, slides out | Label + tween: slide from top | MEDIUM |
| **Swift phase** | Speed lines or blur on swift creature | Shader: motion blur, or sprite overlay | LOW |
| **Piercing overflow** | Trail from dead creature to enemy hero | Line2D + particle trail | LOW |
| **Last Stand trigger** | Gold shield flash when surviving at 1 HP | Sprite flash + particles | LOW |
| **Thorns retaliation** | Small spike particles bouncing back | CPUParticles2D: directional | LOW |

### 9.2 Screen-Level Effects

| Effect | Description | Implementation |
|--------|-------------|----------------|
| **Screen shake** | Random (x,y) offset on CanvasLayer, 0.1-0.3s, ease-out | Already implemented |
| **Damage vignette** | Brief red overlay on edges when player hero takes damage | ColorRect with alpha tween |
| **Victory flash** | Screen brightens, golden particles | Modulate + CPUParticles2D |
| **Phase transition dim** | Brief darkening between player turn and combat resolution | ColorRect fade 0.15s |

### 9.3 Particle Textures Needed

| Texture | Size | Description |
|---------|------|-------------|
| Soft circle | 8x8 to 16x16 | Basic round particle for general effects |
| Spark/diamond | 8x8 | Sharp bright particle for impacts |
| Smoke puff | 16x16 to 32x32 | Soft cloud for death, sacrifice |
| Star/cross | 8x8 to 12x12 | For buff sparkles, heal glow |
| Drop/drip | 8x16 | For blood/damage splatter |
| **Total** | 5 base textures | White versions, tinted by particle system |

**Note:** Use CPUParticles2D (not GPUParticles2D) for GL Compatibility renderer safety. Your commit history shows GL Compatibility shader issues.

---

## 10. AUDIO — Complete Sound Design

### 10.1 Card Interaction Sounds

| Sound | Variants | Description |
|-------|----------|-------------|
| Card draw | 2-3 | Soft paper slide. Pitch-vary to avoid repetition. |
| Card play (creature) | 2-3 | Heavier thump. Card hitting table. |
| Card play (spell) | 2-3 | Magical whoosh + lighter card sound. |
| Card hover | 1 | Very subtle paper rustle or UI tick. |
| Card return to hand | 1 | Soft slide. |
| Deck shuffle | 1-2 | Riffle at round start. |
| **Subtotal** | ~10-13 | |

### 10.2 Combat Sounds

| Sound | Variants | Description |
|-------|----------|-------------|
| Melee attack hit | 3-4 | Sword clash, impact. Vary pitch per use. |
| Spell damage (fire) | 2-3 | Fire whoosh/burst. |
| Spell damage (generic) | 2-3 | Magic impact. |
| Creature death | 2-3 | Crumble/dissolve/groan. |
| Heal | 1-2 | Gentle chime, warm tone. |
| Buff applied | 1-2 | Ascending sparkle. |
| Debuff applied | 1-2 | Descending dark tone. |
| Floop trigger | 1-2 | Mystical warble. |
| Sacrifice | 1-2 | Dark, visceral. Blade + rumble. |
| Thorns retaliation | 1 | Quick spike/sting. |
| Hero damage | 2-3 | Heavy impact. Matches screen shake. |
| **Subtotal** | ~20-27 | |

### 10.3 UI Sounds

| Sound | Variants | Description |
|-------|----------|-------------|
| Button click | 1 | Crisp, satisfying. |
| Button hover | 1 | Subtle tick. |
| Panel open | 1 | Paper unfurl or slide. |
| Panel close | 1 | Soft close. |
| Gold gain | 1-2 | Coin clink. Multiple for big amounts. |
| Potion use | 1 | Cork pop + gulp. |
| Relic acquire | 1 | Mystical chime + weight. |
| Card reward picked | 1 | Satisfying "chosen" confirmation. |
| Error / invalid action | 1 | Soft buzz or denied. |
| End turn press | 1 | Decisive bell or thump. |
| Card upgrade | 1-3 | Anvil (Sharpen), grind (Fortify), charge (Imbue). |
| Map node select | 1 | Click/tap. |
| **Subtotal** | ~13-17 | |

### 10.4 Background Music

| Scene | Type | Loop? | Duration |
|-------|------|-------|----------|
| Main Menu | Orchestral/ambient theme | Yes | 2-4 min |
| Map exploration | Light adventure ambient | Yes | 2-3 min |
| Combat (normal) | Tension/action | Yes | 2-3 min |
| Combat (elite) | Intensified, more dramatic | Yes | 2-3 min |
| Combat (boss) | Epic, heavy | Yes | 3-4 min |
| Shop | Tavern, relaxed | Yes | 2-3 min |
| Rest site | Campfire calm, nature sounds | Yes | 2-3 min |
| Event | Mysterious, uncertain | Yes | 2-3 min |
| **Subtotal** | 8 looping tracks | | |

### 10.5 Music Stingers (one-shot)

| Stinger | Duration | Description |
|---------|----------|-------------|
| Victory | 5-10 sec | Triumphant fanfare. |
| Defeat | 5-10 sec | Somber, dark. |
| Act transition | 3-5 sec | Dramatic reveal. |
| Relic found | 2-3 sec | Discovery chime. |
| **Subtotal** | 4 stingers | |

### 10.6 Ambient Layers (optional, mixed over music)

| Scene | Sounds |
|-------|--------|
| Combat | Distant thunder, crowd murmur |
| Shop | Market chatter, coins, fireplace |
| Rest | Crickets, owl, campfire crackle, wind |
| Map | Wind, distant wolves, leaves |

**Audio format:** OGG Vorbis for Godot (natively supported, smaller than WAV). 44.1kHz/16-bit minimum.
**Total audio assets: ~55-75 sounds + 8 music tracks + 4 stingers**

---

## 11. FONTS AND TYPOGRAPHY

### Font Stack (Current — Already Strong)

| Role | Font | Weight | Size | Notes |
|------|------|--------|------|-------|
| Card name | Cinzel Variable | SemiBold (600) | 10-14pt | All-caps. Classical look. spacing_bottom: -3 |
| Card stats (ATK/HP/Cost) | Cinzel Variable | Black (800) + embolden 0.5 | 12-16pt | Chunkiest text on card |
| Card type line | Cinzel Variable | Regular-SemiBold | 8-10pt | "CREATURE" / "SPELL" |
| Card body / description | Nunito | Regular + embolden 0.35 | 9-11pt | Readability priority |
| Keyword bold | Nunito | embolden 0.7 | 9-11pt | BBCode [b] tags |
| UI headers | Cinzel / Pirata One | SemiBold-Bold | 14-24pt | Scene titles, panel headers |
| UI body | Nunito | Regular | 10-14pt | Tooltips, descriptions |
| Damage numbers | Cinzel | Black (800) | 18-28pt | With outline/shadow |
| HUD counters | Cinzel | Bold | 12-16pt | HP, gold, mana numbers |

**Font file inventory:**
- `Cinzel-Variable.ttf` — IN USE (primary display)
- `CinzelDecorative-Regular.ttf` — available (ornamental variant)
- `CinzelDecorative-Bold.ttf` — available (ornamental variant)
- `Nunito-Regular.ttf` — IN USE (body text)
- `PirataOne-Regular.ttf` — available (pirate/fantasy decorative)

**Verdict:** Font stack is COMPLETE. 2 families (Cinzel + Nunito) is ideal for a card game.

---

## 12. MISCELLANEOUS — Everything Else

### 12.1 Loading / Splash Screen
- **Boot splash:** Game logo on dark background. 1920x1080 PNG. Godot has built-in boot splash support.
- **Scene transition:** Brief fade-to-black between scenes. Dark screen with optional spinner/tip text.
- **Game logo:** Needed for splash, main menu, card backs. Professional logo design.

### 12.2 Cursors
| Cursor | Description | Size | Status |
|--------|-------------|------|--------|
| Default arrow | Standard or themed fantasy arrow | 32x32 | Using system default |
| Hover / hand | When hovering interactive elements | 32x32 | MISSING |
| Targeting crosshair | During spell targeting mode | 32x32 | MISSING |
| Grab / drag | When dragging cards | 32x32 | MISSING |
| **Total** | 3-4 cursor sprites | | |

Set via `Input.set_custom_mouse_cursor()` in Godot.

### 12.3 Deck / Discard / Exhaust Pile Visuals
| Pile | Visual | Status |
|------|--------|--------|
| Draw pile | Stack of face-down cards. Shows count. Clickable. | Have `hud_deck.png` |
| Discard pile | Stack of face-up cards. Shows count. Click to browse. | MISSING icon |
| Exhaust pile | Burned/consumed pile. Shows count. Click to browse. | MISSING icon |

### 12.4 Game Logo
- Needed for: main menu title, splash screen, card back center, window title bar icon
- Style: Fantasy/medieval lettering for "Burning Meadow"
- Format: PNG with transparency. Multiple sizes (512x512 logo, 128x128 icon, 32x32 favicon)

### 12.5 Run Summary / Stats Screen
Shown on victory or defeat:
- Enemies defeated count
- Cards played count
- Relics collected
- Gold earned total
- Floors cleared
- Run duration
- Could reuse existing panel NinePatch + text layout

### 12.6 Card Removal / Transform Visuals
- At shops (card removal for 50g): card dissolves, shatters, or burns away
- At rest (card upgrade): card glows, transforms, reveals upgraded version
- Visual feedback for permanent deck changes is very satisfying

---

## MASTER ASSET CHECKLIST — Summary

### DONE (have assets)

| Category | Count | Quality |
|----------|-------|---------|
| Card frames (creature + spell + curse) | 9 | Good |
| Creature portraits | ~48 | Mixed (JPG + PNG, varied styles) |
| Spell illustrations | ~45 + painterly variants | Good coverage |
| Keyword SVG icons | 16 | Complete |
| HUD painted icons (heart, gold, potion, relic, deck) | 5 | Good |
| Map node icons | 6 | Good |
| Scene backgrounds | 7 | Good |
| Card stat overlay icons (cost, atk) | 2 | Good |
| Fonts | 2 families, 5 files | Complete |
| UI panel/border packs (Kenney x2) | 2 packs | Good |
| General game icons (Kenney) | 1 pack (~100 icons) | Good utility |
| Card template reference | 2 packs | Reference only |
| Procedural card layout (PolyBadge v4) | In code | Working |

### MISSING — Prioritized

| Category | Count Needed | Priority | Difficulty |
|----------|-------------|----------|------------|
| **Relic icons** | 36 | HIGH | Medium (game-icons.net can cover most) |
| **Audio SFX** | 55-75 sounds | HIGH | Medium (freesound.org, Kenney audio) |
| **Background music** | 8 tracks + 4 stingers | HIGH | Hard (commission or CC music) |
| **Card back design** | 1 minimum | HIGH | Easy (logo + pattern) |
| **Missing creature art** | ~29 portraits | HIGH | Hard (must match existing style) |
| **Discard pile icon** | 1 | MEDIUM | Easy |
| **Exhaust pile icon** | 1 | MEDIUM | Easy |
| **Mana crystal icons (filled + empty)** | 2 | MEDIUM | Easy |
| **Upgrade path icons (Sharpen/Fortify/Imbue)** | 3 | MEDIUM | Easy |
| **Victory background** | 1 | MEDIUM | Easy |
| **Collection viewer background** | 1 | MEDIUM | Easy |
| **Per-act map backgrounds** | 2 | MEDIUM | Easy |
| **Upgrade indicator on cards** | 1-3 overlays | MEDIUM | Easy |
| **Game logo** | 1 (multiple sizes) | MEDIUM | Medium |
| **Cursor sprites** | 3-4 | LOW | Easy |
| **Particle base textures** | 5 | LOW | Easy (can be procedural) |
| **Enemy card frame variant** | 1 | LOW | Easy |
| **Token card frame** | 1 | LOW | Easy |
| **Boss arena backgrounds** | 1-3 | LOW | Medium |
| **Card foil/premium shaders** | 1-3 | LOW | Medium |

### NUMBERS SUMMARY

| | Done | Missing | Total Needed |
|---|------|---------|-------------|
| Visual assets (sprites, textures, icons) | ~120 | ~90 | ~210 |
| Audio assets (SFX + music) | 0 | ~70 | ~70 |
| **Grand total** | **~120** | **~160** | **~280** |
| **Completion** | **~43%** | | |

---

## FREE / AFFORDABLE ASSET SOURCES

### Art (Card Portraits, Backgrounds)
- **Public-domain masters** via Wikimedia Commons, rawpixel, Met Museum Open Access — matches your existing Dore/Vrubel approach
- **OpenGameArt.org** — CC0/CC-BY art packs, character portraits, backgrounds
- **itch.io asset packs** — fantasy character portraits ($3-20), background art ($5-15)
- **Unsplash / Pexels** — free photos for background textures (edit/paint over)

### Icons
- **game-icons.net** — 4000+ CC-BY 3.0 game icons. Covers almost every relic concept.
- **Kenney.nl** — CC0, already in your project. Game icons, UI elements.
- **Noun Project** — Huge icon library, free with attribution.

### UI Kits
- **Kenney Fantasy UI Borders** — already in project
- **itch.io** — Fantasy UI packs ($5-15), card game templates ($5-20)

### Audio
- **Freesound.org** — CC0 filter for commercial-safe SFX
- **Kenney audio packs** — CC0 UI sounds, impacts, RPG sounds
- **Sonniss GDC Audio Bundle** — released annually, royalty-free
- **Pixabay Music** — royalty-free background music
- **Kevin MacLeod (Incompetech)** — CC-BY fantasy/orchestral tracks

### Fonts
- **Google Fonts** — already using Cinzel + Nunito (both OFL). Complete.
