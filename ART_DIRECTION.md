# Burning Meadow — Art Direction Bible

> What every element should LOOK like, not just that it exists.
> A creative brief an artist (or you) can follow.

---

## OVERALL VISUAL IDENTITY

### The Core Idea: "Nature on Fire"

Every visual in the game should feel like it belongs to a world where meadows are
burning — warm light, charred edges, embers rising. Beautiful and ominous at the
same time. The game is NOT horror, NOT pure grimdark — it spans comedy, grim, and
horror registers. A goblin should look mischievous and funny. A necromancer should
look sinister but slightly ridiculous. A dragon should be genuinely terrifying.

### The 7 Cohesion Rules

These rules apply to EVERY visual element — cards, UI, backgrounds, icons, effects:

**1. Warm color temperature everywhere.**
Everything leans amber/golden (~4000K in photographic terms). Even "cool" elements
have warm undertones: blues are teal-shifted (toward `#0D7377` not pure `#0000FF`),
purples are wine-shifted (toward `#6D28D9` not `#8B00FF`). The whole game feels
"lit by firelight."

**2. Top-left lighting at 45 degrees. Always.**
All art, icons, UI, and effects use the same light source — upper-left at 45 degrees:
- Highlights on upper-left surfaces
- Shadows on lower-right surfaces
- Drop shadows fall down-right
- Bevels are lighter on top-left edge, darker on bottom-right
If one card has light from the right and another from the left, they look like
different games. This is the single most important cohesion rule.

**3. Three textures only.**
Every surface in the game is one of these three materials:
- **Parchment grain** — light surfaces: card text areas, map, tooltips, light panels
- **Wood grain** — dark surfaces: UI panels, buttons, card frame underlayer
- **Metal patina** — accents: frame borders, stat badges, button borders, trim
No glass, no crystal, no smooth plastic. Just parchment, wood, and fire-darkened metal.

**4. Value hierarchy — dark behind, bright in front.**
- Backgrounds: 15-35% brightness (dark, recedes)
- UI panels, card bodies: 30-60% brightness (midground)
- Card art, text, active elements: 60-100% brightness (foreground)
- Gold highlights, fire effects, selected states: 80-100% (accent)
Never let backgrounds get brighter than midground, or midground brighter than foreground.

**5. Shared border formula.**
All bordered elements — cards, panels, buttons, popups — use the same proportional
treatment: 2px border + 1px inner bevel. Color varies, thickness ratio stays identical.

**6. The "vine-flame" motif.**
Wherever organic ornamentation appears (corner brackets, dividers, flourishes), it
combines plant shapes with flame tips — leaves that become flames at their points,
branches that glow at their ends. This IS the visual identity of "Burning Meadow."
Appears on:
- Frame corner ornaments (higher rarity = more elaborate)
- Panel dividers (horizontal vine with ember points)
- Victory/defeat/transition screens
- Loading screens

**7. Same animation curves everywhere.**
- Entrance: Ease Out Cubic (fast start, gentle settle) — 0.2-0.3s
- Exit: Ease In Cubic (gentle start, fast disappear) — 0.15-0.2s
- Emphasis (pulse, glow): Ease In Out Sine (smooth oscillation) — 0.4-0.8s loop
- Impact (damage, hit): Linear, sharp, no easing — 0.1-0.15s

---

## MASTER COLOR PALETTE

### Core Colors (use these exact hex codes)

**Background / UI Dark Tones:**
| Role | Hex | Where |
|------|-----|-------|
| Deepest background | `#1A110A` | Behind everything |
| Primary panel | `#2B1D0E` | Main UI panels |
| Secondary panel | `#3D2B1A` | Lighter panels, popups |
| Parchment light | `#E8D5B5` | Card text areas, tooltips |
| Parchment aged | `#C4A882` | Worn/older parchment |

**Action / Accent Colors:**
| Role | Hex | Where |
|------|-----|-------|
| Primary gold | `#D4AF37` | Buttons, highlights, rewards, selected states |
| Fire orange | `#FF8C00` | Damage, fire effects, urgency |
| Blood red | `#B01919` | HP, damage taken, danger |
| Heal green | `#4ADE80` | Healing, positive effects |
| Mana blue | `#2563EB` | Mana cost, spells, magic |
| Shadow purple | `#6D28D9` | Debuffs, curses, dark magic |
| Teal accent | `#0D7377` | Rare items, mystery, magical highlights |

**Rarity Colors (for gems/indicators):**
| Rarity | Hex | Association |
|--------|-----|-------------|
| Common | `#9CA3AF` | Silver-grey |
| Uncommon | `#22C55E` | Emerald green |
| Rare | `#3B82F6` | Royal blue |

**Floating Text Colors:**
| Type | Hex |
|------|-----|
| Damage dealt | `#FF4444` |
| Healing | `#44DD44` |
| Blocked/armored | `#AAAAAA` |
| Piercing/face damage | `#FF2200` |
| Buff/ATK gain | `#FFD700` |
| Poison/wither | `#9944CC` |
| Mana gain | `#4488FF` |

**Spell School Colors:**
| School | Hex | Visual Treatment |
|--------|-----|------------------|
| Damage/Fire | `#EF4444` | Hot, bright, radiating |
| Heal/Nature | `#86EFAC` | Gentle, glowing, rising |
| Buff/Enhance | `#FBBF24` | Warm, sparkle, enveloping |
| Debuff/Curse | `#7C3AED` | Cold, dripping, descending |
| Shield/Armor | `#94A3B8` | Solid, crystalline, static |

---

## 1. CARD FRAMES — What They Should Look Like

### Material: Weathered Bronze + Charred Wood

The frame should evoke **fire-darkened bronze with a wood underlayer** — not
pristine gold, not raw stone. Metal that has been through fire, with visible heat
patina. Think copper that has oxidized to dark teal-green at the edges, with warm
amber highlights where light catches the raised portions.

**Why this material:**
- Pure stone (Hearthstone) = dungeon-crawler, not meadow
- Clean metal filigree (LoR) = high-fantasy nobility, too refined for goblins
- Flat colored borders (StS) = functional but no material presence
- Clean minimal (Balatro) = poker abstraction, not creature combat
- Charred bronze + wood = matches "burning meadow" identity perfectly

**Border thickness (at 180x252 card render):**
- Sides: 8-10px
- Top: 10-12px
- Bottom: 14-16px (thicker to anchor the card visually and house stat badges)

The bottom being ~2x the sides follows the MtG/LoR convention — prevents the card
looking top-heavy and gives stat badges a solid seat.

### Rarity Progression — Material Upgrades, Not Just Color Swaps

Each rarity should feel like a fundamentally better material:

**Common — Dark Iron, Matte**
- Frame: `#3A3A3A` base, no shine, no ornamentation
- Surface: Rough, slightly pitted iron texture. Functional, not decorative.
- Corners: Plain, maybe a single rivet at each corner
- Gem: Dull white-grey `#C8C8C8`
- Mood: "A soldier's tool, not a treasure"

**Uncommon — Aged Bronze**
- Frame: `#5C4A32` base with thin copper wire inlay along the inner edge
- Surface: Smooth but patinated bronze. Some verdigris (teal-green oxidation spots)
- Corners: Small leaf-scroll corner brackets in copper
- Gem: Pale green `#4ADE80`
- Accent highlights: `#8B6914` on raised surfaces
- Mood: "Something with history, found in an old chest"

**Rare — Polished Bronze with Gold Leaf**
- Frame: `#7A5C2E` base with actual gold leaf trim `#D4AF37` on outer and inner edges
- Surface: Polished, reflective — the bronze catches light
- Corners: Elaborate vine-flame corner ornaments (the signature motif)
- Gem: Sapphire blue `#3B82F6`
- Ornamentation: Embossed vine-flame pattern running along the top edge
- Mood: "Clearly valuable, you won something good"

**Curse — Blackened Bone/Charcoal**
- Frame: `#1A1A1A` near-black, cracked texture
- Surface: Charred, ashen. Hairline cracks visible. No shine.
- Corners: Cracked, broken — opposite of rarity progression
- Gem: Sickly violet `#A855F7`
- Accent: `#2D1B2E` dark purple in the cracks
- Mood: "This card is wrong, it shouldn't be in your deck"

**Key details that make frames feel premium:**
- A subtle **inner bevel** (1px lighter stripe along the inner frame edge) makes
  the frame read as 3D — this is the cheapest possible way to add depth
- A **dark inner shadow** (3-4px soft shadow inward from frame into art window)
  makes the portrait appear recessed, like a painting set into a frame
- Corner ornaments increasing in complexity with rarity communicates value
  through detail, not just color

### Art Window Shape

The opening where creature/spell art shows through. Should have:
- Slightly rounded corners (4-6px radius) — NOT hard rectangular (feels digital),
  NOT circular/oval (too Hearthstone)
- A 3-4px **dark inner shadow** at all edges of the art window, so the art looks
  recessed behind the frame
- Aspect ratio roughly 4:3 landscape (wider than tall) — at 180x252 card size,
  about 140x100px visible. This gives creatures horizontal breathing room.

---

## 2. CARD ART STYLE — Anime-Dark Fantasy Hybrid

### Recommended Style: "Expressive Anime-Adjacent"

Think **Disgaea meets Darkest Dungeon's lighting**, or **Persona 5's UI energy
with dark fantasy creatures**. Not pure anime, not pure western painterly — a
hybrid that can handle ALL tonal registers:

- Yu-Gi-Oh and Jujutsu Kaisen prove anime handles horror-to-comedy range naturally
- Chainsaw Man proves anime can be both silly and grotesque simultaneously
- Disgaea proves anime fantasy can have funny goblins AND menacing bosses

### Specific Visual Characteristics

**Linework:**
- Bold outlines: 2-3px at card resolution
- Black or very dark brown `#1A110A` lines (not grey, not colored)
- Clean, confident strokes — not sketchy, not hyper-detailed
- Thicker lines on outer silhouette, thinner on internal details

**Coloring:**
- Cel-shaded base (flat color areas) with a painterly shadow pass
- Flat colors provide readability at small card sizes
- Shadows have texture and depth (not just darker flat areas)
- 2-3 value steps per color (highlight, midtone, shadow)

**Character expression:**
- **Eyes are the focal point of every portrait.** This is the #1 thing anime does
  that other styles don't — eyes convey personality instantly even at 140x100px
- Comedy creatures (goblins, imps): Wide grins, squinted scheming eyes, one
  eyebrow raised, exaggerated features
- Grim creatures (orcs, trolls, berserkers): Scarred, battle-worn, tired but
  dangerous eyes, tight-lipped
- Horror creatures (naga, undead, wraiths): Glowing or blank eyes, unnatural
  proportions, uncanny valley expressions
- Noble creatures (paladins, rangers, guards): Determined gaze, slight upward
  tilt, dramatic rim lighting
- Boss creatures (dragons, hydras, titans): Extreme close-up, eye fills 30%+ of
  art space, overwhelming presence

**Color temperature by tone:**
- Funny/lighthearted creatures: Warm, saturated palette (bright oranges, yellows,
  warm greens)
- Grim/serious creatures: Desaturated, muted tones (steel greys, dusty browns,
  muted reds)
- Horror creatures: Cold palette with one hot accent (pale blue-greens with a
  single glowing red eye, etc.)

---

## 3. CREATURE PORTRAIT COMPOSITION

### Framing: Three-Quarter Bust with Personality

**Camera angle:**
Slight low angle (10-15 degrees below eye level). Makes creatures look more
imposing. Fills the frame better. NOT dead-on eye level (too flat). NOT extreme
low angle (looks silly for small creatures).

**Subject placement:**
- **Three-quarter bust**: head, shoulders, upper torso, one or both hands/weapons visible
- Subject fills **70-80% of the frame** vertically
- Face centered at the **upper third** of the art window (rule of thirds)
- Eyes at approximately **30% from the top**
- Asymmetric pose: body turned 20-30 degrees from center for dynamism
- Weapons/items visible in the lower portion

**Background treatment:**
- Abstract gradient, atmospheric smoke, or soft color wash
- NEVER detailed environments — they compete with the subject at card size
- Color should **contrast** the subject: warm creature = cool background,
  cool creature = warm background
- Background is 20-30% of the visible frame (mostly around shoulders/edges)
- Soft/blurred — subject sharp, background out of focus

**Lighting:**
- Top-left 45 degrees (matching the universal game lighting)
- Bright highlight on upper-left of face
- Shadow under chin and on the right side
- Optional: rim light on the shadow side (thin bright edge) to separate subject
  from background

**The Silhouette Test:**
Squint at the portrait until it's a blob. Can you tell what creature it is from
the outline alone? A dragon should have horns/wings in silhouette. A knight should
have a helmet shape. A mage should have a hat or staff. If two creatures have the
same silhouette, redesign one. The eye perceives outlines first.

---

## 4. SPELL ART COMPOSITION

### Principle: The Moment of Impact, Not a Still Life

Spell art depicts **the magical effect itself** at peak energy — not a character
casting it, not a static symbol.

**By spell type:**

**Damage spells (Strike, Fireball, Inferno, etc.):**
- Radial burst from center, energy expanding outward
- Sharp, angular shapes — explosions, slashes, pointed rays
- Color dominance: orange-red hot core (`#EF4444` to `#FF8C00`), dark edges
- High contrast: bright white/yellow center fading to deep red/black
- Movement direction: expanding outward, aggressive

**Heal spells (Second Wind, Patch Up, Provision, etc.):**
- Soft upward radiance, glowing center
- Rounded, gentle shapes — orbs, halos, waves of light
- Color: green-white (`#86EFAC`), gentle luminance, soft edges
- Low contrast: everything is gentle, nothing is harsh
- Movement direction: rising upward, peaceful

**Buff spells (War Cry, Inspire, Battle Hymn, etc.):**
- Enveloping glow around a silhouette or symbol
- Geometric, ordered shapes — rings, runes, shields
- Color: gold shimmer `#FBBF24`, warm and embracing
- Medium contrast: clear but not aggressive
- Movement direction: wrapping inward, protective

**Debuff/dark spells (Dark Pact, Grave Pact, Unholy Bargain, etc.):**
- Dripping/descending dark tendrils, creeping corruption
- Irregular, organic shapes — drips, cracks, tendrils, smoke
- Color: sickly purple-green `#7C3AED` to `#2D1B2E`, cold and unsettling
- Movement direction: descending, creeping downward

**Utility spells (Reposition, Shove, Recycle, etc.):**
- Swirling arcane symbols, motion lines, directional arrows
- Color: teal-blue `#0D7377`, mystical
- Movement direction: circular/spiral, suggesting rearrangement

**Key readability rules:**
- **One dominant color per spell** — at card size, the color IS the spell's identity
- High value contrast — bright center + dark edges (or vice versa)
- **Silhouette test**: squint. Can you tell damage from heal from the shape alone?
  Damage = sharp. Heal = soft. Buff = geometric. Debuff = organic.

---

## 5. STAT BADGES (Cost, ATK, HP)

### What They Should Look and Feel Like

Stat badges should look like **polished gemstone settings** — small jewel-like orbs
that sit ON TOP of the card frame, not inside it. Like Hearthstone's mana crystal
and stat icons that straddle the frame edge, visually "above" the card surface.

**Visual layers (bottom to top):**
1. **Drop shadow** — 2px downward, `#000000` at 50% opacity. Lifts the badge off
   the card surface. This is what makes it feel like a separate object.
2. **Gradient fill** — bright at top, darker at bottom. Simulates a light source
   from above (a polished orb catching light).
3. **Top-half highlight** — white at 15-20% opacity over the upper half. Gives a
   glossy, wet-looking sheen.
4. **Specular dot** — small bright white circle near upper-left. The "glass
   highlight" trick. Makes it look polished/reflective.
5. **Numeral** — bold, high contrast against the fill, with its own 2px black
   outline. Must be the most readable thing on the card.
6. **Border ring** — 1-2px darker outline around the entire badge shape.

**Per-badge specifics:**

**Mana Cost (upper-left corner):**
- Shape: Hexagonal crystal (already implemented)
- Fill color: Deep sapphire blue `#2563EB`, gradient lighter at top
- Size: 28-32px diameter at card render scale
- Numeral: White `#FFFFFF`, Cinzel Black (wght 800)
- The most important number on the card — must read at 60% zoom when hand is fanned

**ATK (lower-left):**
- Shape: Shield/heater shape (already implemented)
- Fill color: Warm gold `#D4AF37`, gradient lighter at top
- Gold is near-universal for attack across AAA card games
- Numeral: White `#FFFFFF` with 2px black outline

**HP (lower-right):**
- Shape: Blood drop (already implemented)
- Fill color: Deep crimson `#B01919`, gradient lighter at top
- Red is universal for health
- Numeral: White `#FFFFFF` with 2px black outline
- When damaged below max: number turns brighter red and badge gets subtle cracks

**Rarity Gem (bottom-center):**
- Shape: Diamond/rhombus
- Size: 10-14px — smaller than stat badges
- Color matches rarity tier (see palette above)
- A subtle inner glow at higher rarities

---

## 6. NAME BANNER

### What It Should Look Like

A **tapered ribbon/pennant** shape that overlaps the art window slightly (sits ON
the boundary between art and frame, straddling both). This overlap creates depth —
the banner feels like a physical object laid over the card.

**Material:** Dark painted wood or lacquered leather, NOT paper/parchment (that's
for the text area below).

**Color:** Very dark brown `#2B1D0E` interior with a slight warm gradient (lighter
at center, darker at edges). Gold `#D4AF37` edge trim — a 1px bright line along
the top and bottom edges of the ribbon.

**Shape:** Tapered — wider at center, narrowing to points or pennant-cut ends that
extend 4-6px beyond the card frame edges. This "breaking the frame" effect makes
the banner feel like a real object.

**Text:** Cinzel SemiBold, warm cream `#F5E6C8`, ALL CAPS. 1px dark outline
`#2B1D0E` at 80% opacity. The banner's dark background provides contrast, so the
outline is subtle.

---

## 7. DESCRIPTION WELL (Rules Text Area)

### What It Should Look Like

The lower portion of the card where ability text lives. Should look like a
**parchment inlay** set into the card's wood/bronze frame.

**Material:** Aged parchment `#E8D5B5` with subtle grain texture. NOT white (too
clinical). NOT dark (text becomes unreadable). The slightly yellowed/tea-stained
tone feels warm and old-world.

**Text:** Dark brown `#3D2B1A` on the parchment. Nunito Regular for body. Keywords
in bold + gold `#D4AF37` (the MtG/Hearthstone convention — gold keywords pop on
parchment). 9-11pt equivalent.

**CRITICAL RULE:** Dark text on light background. ALWAYS. Light text on dark
backgrounds is measurably harder to read for anything longer than 5 words. Card
descriptions break this threshold constantly.

**Borders:** The description well has a subtle recessed shadow at the top edge
(where it meets the divider/type line) — making it feel like parchment pressed
down into the card body.

---

## 8. CARD BACK DESIGN

### What It Should Look Like

**Principle:** Rotationally symmetrical (flip upside down, looks identical) so
card orientation gives no information. Central branded element. Pattern fill.

**Layout (from center outward):**

1. **Center (40% of card area):** The game's sigil — a burning meadow motif. Tall
   grass or flowers with flame tips, inside a circular border. Gold `#D4AF37` on
   dark brown `#2B1D0E`. This IS the game's logo/identity mark.

2. **Inner ring:** Geometric interlace pattern — Celtic knot or vine-flame repeat
   in gold on dark brown. 15-20px wide band. Dense but not busy.

3. **Middle field:** Darker fill `#1A110A` with a subtle repeating grass-flame
   pattern at 10-15% opacity. Visible only on close inspection — provides texture
   without competing with the center.

4. **Outer border:** Bronze frame matching the card front border material and
   thickness (8-10px). Same fire-darkened bronze patina.

**Texture:** Subtle leather/cloth grain over the entire back. Card backs that feel
like a material (leather, tooled metal) read as higher quality than flat color.

**Color:** Overall darker than the card front. The card back is the "closed" state —
somber, contained, waiting to be revealed.

---

## 9. UI PANELS AND BUTTONS

### Panel Material: Campaign Table

Panels should feel like a **field commander's campaign table** — dark wood surfaces
with parchment documents pinned to them, brass rivets at corners. Safe but
utilitarian. Not a polished throne room, not a grimy dungeon.

**Main panels:**
- Dark wood texture `#2B1D0E` to `#3D2B1A` gradient (lighter at top — top-lit)
- 2px darker border + 1px bright inner bevel on all edges
- 4-6px drop shadow (downward, 30% opacity black) — the single cheapest way to
  make flat UI feel layered and professional
- Brass corner brackets (small right-angle metal pieces at corners)
- Content area inside uses parchment `#E8D5B5` for text readability

**Tooltip panels:**
- Smaller, darker variant of main panel
- Pointed arrow/tail directed at the element being explained
- Tight padding — tooltips should feel compact and informational

### Button Design

**Material:** Raised dark wood with gold text. Should feel like pressing a wooden
button on a mechanical device.

**Default state:**
- Dark wood fill (`#3D2B1A`)
- Gold text `#D4AF37`
- Subtle 1px lighter stripe at top edge (top-lit bevel)
- 2px border slightly darker than fill

**Hover state:**
- Warm gold border glow (`#D4AF37` at 40% opacity, 2px outward glow)
- Fill brightens +10%
- Cursor changes to hand/pointer
- Scale to 1.05-1.10 (subtle but noticeable)

**Pressed state:**
- Fill darkens -15%
- Top highlight disappears (the bevel inverts — now darker at top)
- Content shifts down 1px (feels "pushed in")
- Scale returns to 1.0

**Disabled state:**
- Desaturated -40%
- Opacity reduced to 70%
- No hover response

**Button shapes:** Rectangular with 4px rounded corners. NOT circular (reads
mobile/casual), NOT hard rectangles (reads corporate), NOT ornate shapes (too busy
when you have many buttons).

**End Turn button specifically:** The most-pressed button in the game. Should be
50% larger than other buttons, prominently placed (bottom-center or bottom-right
of combat screen). Green/gold `#D4AF37` when active, pulsing gently when the player
has no more actions. Grey `#5C5C5C` and smaller when disabled (enemy turn).

---

## 10. SCENE BACKGROUNDS — Mood and Palette Per Scene

### Universal Background Rules
- 40-60% darker and 20-30% less saturated than foreground elements
- Card games use subdued backgrounds because cards ARE the visual focus
- No fine detail that competes with cards or UI at play distance
- Soft/blurred edges, sharp detail only at vanishing points or focal points

### Combat Arena
- **Palette:** Dark warm browns `#2B1D0E`, deep reds `#4A1A1A`, flickering
  orange-amber light suggesting torchlight or a burning field in the distance
- **Composition:** Horizontal plane (lanes go left-to-right). Ground visible,
  sky/ceiling dark. Like fighting in a burning field at dusk.
- **Key element:** Subtle ember particles drifting upward from the bottom — slow,
  sparse (5-10 alive at once), `#FF8C00` at 30% opacity, 3-5 second lifetime.
  This sells the "burning meadow" theme constantly during combat.
- **Brightness:** 25-35% of foreground
- **Feel:** Tense, warm, intimate

### Shop
- **Palette:** Warm amber `#8B6914`, deep wood tones `#3D2B1A`, golden lamplight
- **Composition:** Merchant stall or table in the foreground (blurred). Shelves with
  indistinct items in the background. A warm point-light source from a lantern.
- **Key element:** The warm light. Everything is amber-tinted. This is the "safe
  commerce" scene — warm but transactional.
- **Brightness:** 35-45% of foreground
- **Feel:** Cozy but mercenary — safety has a price

### Rest Site
- **Palette:** Cool blue-greens `#0D4444` for the night, one warm orange focal
  point (campfire `#FF8C00`)
- **Composition:** Night scene. Forest clearing. Campfire in center casting long
  shadows. Stars visible above. The ONLY scene with a cool dominant palette — the
  fire provides warmth in an otherwise cold world.
- **Key element:** The campfire glow. Strong warm-vs-cool contrast. The fire is
  the emotional anchor — rest and safety.
- **Brightness:** 20-30% of foreground (darkest scene — campfire is the contrast)
- **Feel:** Peaceful, contemplative, the one genuine safe moment

### Map Screen
- **Palette:** Aged parchment base `#E8D5B5`, sepia ink `#5C4A32`
- **Composition:** Top-down map on parchment. Paths as ink lines.
- **Brightness:** 70-80% (the lightest scene — inverted from the norm)
- **Act progression (parchment shifts):**
  - Act 1: Clean parchment `#E8D5B5`, green ink accents (meadow, open field)
  - Act 2: Tea-stained `#D4B896`, brown-red ink (deeper, darker territory)
  - Act 3: Scorched `#C4A070`, burnt edges creeping inward, dark red/black ink
- **Decorative:** Compass rose in corner, architectural doodles at edges (trees
  for Act 1, ruins for Act 2, flames for Act 3)
- **Feel:** Strategic, overseeing, like planning at a war table

### Main Menu
- **Palette:** THE signature image — golden grass, orange fire on the horizon,
  dark sky above
- **Composition:** Landscape. Meadow stretching toward a burning horizon. Parallax
  layers: foreground grass, midground fire, background sky.
- **Key element:** Animated fire/glow on the horizon. Grass swaying subtly.
- **Brightness:** 40-50%
- **Feel:** Beautiful and ominous simultaneously — "the world is on fire, and
  it's gorgeous"

### Event Screen
- **Palette:** Cool-neutral (mystery). Variable by event type but generally
  desaturated teal-blue `#0D7377` with warm accents
- **Composition:** Central vignette with event illustration. Dark frame around it.
- **Brightness:** 30-40%
- **Feel:** Uncertain, story-moment, "what will happen?"

### Game Over (Victory)
- **Palette:** Gold and warm white. Bright, triumphant.
- **Composition:** Open sky, golden light breaking through. Uplifting.
- **Brightness:** 50-60% (brightest scene besides map)
- **Feel:** Relief, accomplishment, warmth

### Game Over (Defeat)
- **Palette:** Desaturated, cold. Already have `triumph_of_death.jpg`.
- **Composition:** Dark, low horizon, oppressive sky.
- **Brightness:** 15-25% (darkest)
- **Feel:** Somber, heavy, "the fire consumed everything"

### Collection / Deck Viewer
- **Palette:** Dark warm wood `#2B1D0E`. Neutral.
- **Composition:** Dark wood surface or bookshelf background. Nothing distracting.
  The cards displayed ARE the visual content.
- **Brightness:** 20-30%
- **Feel:** Studious, organized, a quiet space to review your collection

---

## 11. ICON DESIGN — What Makes Icons Work at Small Sizes

### The Three Rules

**1. Silhouette-first.**
Every icon must pass the "squint test" — rendered as a solid black shape on white,
is it recognizable? If two icons have the same silhouette, redesign one. The eye
perceives outlines before ANYTHING else.

**2. Maximum detail by size:**
- At 16x16: Silhouette only + 1 internal detail (a line or a dot)
- At 24x24: Silhouette + 2-3 internal details
- At 32x32: Silhouette + full internal detail, still clear shapes
- Never put detail that requires 48px into a 24px icon

**3. Maximum 3 colors per icon:**
Background/container + primary fill + accent detail. More colors = more noise
at small sizes.

### Consistency Rules
- Same line weight across ALL icons: 2px at 32x32 scale
- Same perspective: flat/front-facing, NOT isometric
- Same padding: 2px minimum from edge of bounding box
- Same corner treatment: sharp corners for combat/danger icons, slightly rounded
  for utility/peaceful icons

---

## 12. RELIC ICONS — "Objects from a Burning World"

### What 36 Relic Icons Should Look Like

Every relic is a **small artifact found in the smoldering remains** — each one a
small story. They are permanent run modifiers so they need to feel weighty.

**Shared visual rules (what makes them feel like one set):**
- Every relic sits on the same dark circular or rounded-square background vignette
  (`#1A110A` to `#2B1D0E` gradient)
- All use the same lighting direction (top-left 45 degrees)
- All use the same outline weight (2px)
- A subtle warm rim light on every relic (as if lit by the same fire source)
- This warm firelight tint unifies the set even when shapes/colors vary wildly

**Shape language by tier:**

**Starting relics (8) — Simple, Round, Natural:**
Objects a traveler would carry. Humble, worn, old-looking.
- Shapes: Coins, simple rings, pouches, feathers, small stones, leather straps
- Colors: Muted earth tones (`#8B7355`, `#6B5B3F`, `#9CA3AF`)
- Detail level: Minimal — 2-3 internal details max. Readable as "a thing you
  found on the road"
- Examples: Iron Buckler = small round shield shape. Courier's Bag = leather pouch.
  Coin Purse = tied coin bag. Scout's Emblem = simple heraldic badge.

**Combat relics (23) — Angular, Metallic, Weapon-adjacent:**
Objects found in battle or taken from defeated foes. Sharp, metallic, sometimes
menacing.
- Shapes: Blades, shield fragments, horns, claws, skull pieces, war implements
- Colors: Metallic `#94A3B8` steel + one strong accent (blood red `#B01919`,
  fire orange `#FF8C00`, bone white `#E8D5B5`)
- Detail level: Medium — 3-4 internal details. Clearly an artifact of violence.
- Examples: War Drum = round drum with sticks. Piercing Crown = spiked circlet.
  Ritual Dagger = curved ceremonial blade. Blood Chalice = goblet with red interior.

**Utility relics (5) — Geometric, Magical, Ornate:**
Magical or precious objects. Visually "worth more" than other relics.
- Shapes: Crystals, ornate keys, hourglasses, glowing orbs, enchanted books
- Colors: Jewel tones — teal `#0D7377`, purple `#6D28D9`, gold `#D4AF37`
- Detail level: Highest — 4-5 internal details, inner glow effects
- Examples: Lucky Coin = golden coin with arcane symbol (glowing). Map Fragment =
  torn parchment with glowing lines.

---

## 13. KEYWORD ICONS ON CARDS

### Visual Language for Each Keyword

| Keyword | Icon Shape | Color Accent | Why This Shape |
|---------|-----------|-------------|----------------|
| Armored | Shield/chevron | Steel `#94A3B8` | Universal "defense" symbol |
| Swift | Lightning bolt or wing | Electric blue `#4488FF` | Speed, pre-emptive action |
| Thorns | Crossed thorns/spikes | Deep green `#166534` | Literal thorns, reactive damage |
| Piercing | Arrow through target | Red-orange `#FF4444` | Penetration, excess damage |
| Last Stand | Broken shield with glow | Gold `#FFD700` | Surviving at the brink |
| Ranged | Bow and arrow | Light blue `#60A5FA` | Distant targeting |
| Regenerate | Heart with swirl | Green `#4ADE80` | Healing over time |
| Wither | Cracked heart / skull drip | Purple `#7C3AED` | Decay, reduction |
| On Enter | Door/gateway | Teal `#0D7377` | Arriving, triggering |
| On Death | Skull | Red `#B01919` | Death trigger |
| Floop | Circular arrow / flip | Orange `#FF8C00` | Activation, flip action |
| Sacrifice | Altar/dagger | Dark red `#7F1D1D` | Ritual, voluntary death |
| Exhaust | Fire/ash | Grey `#6B7280` | Burned, consumed, one-use |
| Retain | Lock/hand grip | Gold `#D4AF37` | Kept, not discarded |
| Summon | Portal/rising figure | Teal `#0D7377` | Calling forth |
| Adj Buff | Linked arrows | Gold `#FBBF24` | Connection, adjacency |

---

## 14. MAP NODE ICONS

### What Each Should Look Like

| Node | Shape | Color When Available | Feel |
|------|-------|---------------------|------|
| Combat | Crossed swords | Warm red-brown `#8B4513` | Challenge, standard threat |
| Elite | Horned skull | Orange `#FF8C00`, larger than normal nodes | Dangerous, rewarding |
| Boss | Dragon head | Molten gold `#D4AF37`, largest node, extra ornament ring | Epic, climactic |
| Rest | Campfire | Cool blue-green `#0D7377` with warm center dot | Safe, calming |
| Shop | Merchant bag or coin | Amber-gold `#8B6914` | Commerce, opportunity |
| Event | Dice or question mark | Teal `#0D7377` | Mystery, could be anything |

**Node states (visual treatment):**
- **Locked:** Greyed out `#5C5C5C`, 50% opacity, no glow. Flat, dead.
- **Available:** Full color, gold border glow pulsing (0.8s sine wave between
  `#D4AF37` 20% and 60% opacity). The glow is the "click me" signal.
- **Visited:** Muted color (-30% saturation), small checkmark overlay, no glow.
  "Been there, done that."
- **Current:** Extra bright, pulsing scale (1.0 to 1.05, 1.2s loop), strongest glow.
  "You are here."

---

## 15. VISUAL EFFECTS — How Every Effect Should Look

### Attack Sequence (The Full Anatomy)

A satisfying attack has 5 phases, each with specific visual cues. Total: ~0.8-1.0s.

**Phase 1 — Anticipation (0.0-0.15s):**
- Attacking card lifts Y -8 to -12px, scales to 1.05
- Subtle shadow/glow appears beneath it
- Easing: Ease-Out Quad

**Phase 2 — Lunge (0.15-0.35s):**
- Card accelerates toward target along a slight parabolic arc (NOT straight line)
- A short-lived streak trail follows (white, fading over 0.1s)
- Easing: Ease-In Cubic (starts slow, accelerates into impact — critical for weight)

**Phase 3 — Impact (0.35s, instantaneous ~0.05s):**
- **Hitstop/freeze:** Everything pauses for 2-4 frames (50-67ms). Light attacks:
  50ms. Lethal: 80-100ms. This is where the hit "registers" in the player's brain.
- **Screen shake:** Fires with hitstop. Small hit: 3-5px, 100ms. Big hit: 8-15px,
  150-200ms. Decay: multiply amplitude by 0.85-0.90 each frame.
- **Impact flash:** White overlay on defender for 1-2 frames (16-33ms)
- **Particles:** 8-15 particles burst from collision point, 180-degree spread away
  from attacker. Physical: grey-brown chips. Magical: colored sparks.
- **Sound:** Meaty thud fires on THIS exact frame

**Phase 4 — Recoil (0.35-0.7s):**
- Attacker bounces back to origin via Ease-Out Back (slight overshoot, then settle)
- Defender takes 4-8px knockback, returns via Ease-Out Elastic (small wobble)
- Damage numbers pop up on defender

**Phase 5 — Settle (0.7-1.0s):**
- All cards return to rest. Lingering particles fade. HP numbers update.

### Damage Numbers

**Appearance:**
- Cinzel Black (wght 800), 20-24pt, white on red for damage
- 2-3px black outline. Mandatory — without it, numbers vanish on busy backgrounds.
- 1px drop shadow (downward, 50% opacity)

**Animation curve (the key to "feeling right"):**
1. Spawn at impact point, scale 0.0
2. **Pop-in (0.0-0.1s):** Scale 0.0 to 1.3 (overshoot). `TRANS_BACK, EASE_OUT`.
   This pop is what makes damage feel PUNCHY.
3. **Settle (0.1-0.2s):** Scale 1.3 to 1.0. `TRANS_QUAD, EASE_OUT`.
4. **Float (0.2-0.8s):** Drift upward 30-50px. `TRANS_QUAD, EASE_OUT` (decelerating
   float — fast then slow). Alpha fades 1.0 to 0.0 starting at 0.4s.
5. **Total lifetime: 0.8-1.0s**

Add small random X offset (-15 to +15px) so stacked numbers don't overlap.
Random rotation (-5 to +5 degrees) for organic feel.

**Critical hits:** Scale overshoot 1.8 instead of 1.3, 50% larger font, brief
screen shake (3px, 80ms), 4-6 star/spark particles around the number.

### Creature Death

Standard death (~0.7-0.8s):
1. **Hit reaction:** Card shakes 4px amplitude, 0.15s
2. **Desaturation:** Colors drain over 0.2s (modulate toward grey)
3. **Dissolve:** Fades from bottom-up over 0.3s
4. **Ash particles:** 10-15 grey `#888888` particles rise slowly (15-35px/s),
   slight horizontal wander, 0.8-1.2s lifetime, shrinking over time
5. **Ghost frame:** 20% opacity afterimage lingers 0.2s then fades

Sacrifice death (~0.6-0.7s):
1. **Dark pulse:** Expanding ring of dark red `#7F1D1D` from creature, radius 0
   to 80px over 0.15s, fading
2. **Blood particles:** 8-12 dark red `#8B0000` droplets spray upward, arc down
   with gravity
3. **Card sinks downward** (opposite of normal — pulled DOWN, not drifting up)
4. **Dark wisps:** 2-3 purple-smoke particles linger at position for 0.5s

Boss/elite death:
- Same as standard but: stronger shake (10px, 200ms), white flash (100ms),
  2x particle count, deeper boom sound, and a 150-200ms hitstop BEFORE the
  dissolve begins (ceremonial weight)

### Particle Color Reference

| Effect | Particle Color Gradient | Shape | Count | Speed | Lifetime |
|--------|------------------------|-------|-------|-------|----------|
| Physical hit | `#FF6600` > `#FF2200` > `#331100` | Soft circle 4-8px | 10-20 | 80-150px/s | 0.3-0.6s |
| Healing | `#44FF88` > `#88FFAA` (fading) | Soft circle 2-5px | 8-15 | 30-60px/s up | 0.6-1.0s |
| Buff/gold | `#FFD700` > `#FFAA00` + white twinkles | Circle + cross 2-4px | 12-18 | 40-80px/s up | 0.5-0.8s |
| Debuff/poison | `#9944CC` > `#662288` > `#332244` | Elongated drip 2-3px | 8-12 | 20-40px/s down | 0.5-0.7s |
| Death/ash | `#888888` > `#444444` (fading) | Soft circle 3-6px | 15-25 | 15-35px/s up | 0.8-1.2s |
| Sacrifice | `#8B0000` > `#440000` + `#221122` smoke | Circle 2-4px + large smoke 8-12px | 10-15 + 3-5 smoke | 60-100px/s | 0.4-0.6s |
| Spell cast | Varies by school | Circle 3-5px | 15-20 | 50-100px/s radial | 0.4-0.7s |
| Ambient embers | `#FF8C00` at 30% opacity | Soft circle 3-5px | 5-10 always alive | 10-20px/s up | 3-5s |

### Screen Effects

| Effect | What | When |
|--------|------|------|
| Screen shake | CanvasLayer offset, random X/Y, exponential decay | Every attack hit, scaled by damage |
| Hitstop | Engine freeze 50-200ms | Lethal blows, boss abilities |
| White flash | White ColorRect at 15-25% opacity, 1-2 frames | Big spell impacts |
| Red vignette | Dark red gradient from screen edges, 20% opacity, 0.2s fade | Player hero takes damage |
| Dim overlay | Black at 5-10% opacity | During enemy turn (you can't act) |
| Warm tint | Orange at 5% opacity | During combat resolution (fire/action) |

---

## 16. AUDIO — How Everything Should Sound

### The Audio Texture Palette

Every sound has a material "soul." For Burning Meadow — parchment, wood, fire:

**Card draw:** Paper "shff." Stiff parchment being pulled. 0.1-0.15s. Pitch varies
+/- 5% per draw to avoid robotic repetition. Dry, no reverb.

**Card play (creature):** Wooden "thunk." Three layers:
- Bass thump (60-150Hz) for weight
- Paper slap (1-4kHz) for snap
- Subtle wood reverb tail
Duration: 0.2-0.3s. Should feel like slapping a card onto a wooden table.

**Card play (spell):** Magical "whoosh." Two layers:
- Wind/air sweep (shaped white noise)
- Brief pitched tone matching the spell's element — low rumble for dark spells,
  high chime for light spells
Duration: 0.3-0.5s.

**Melee attack:** Meaty impact. Three layers:
- Bass thud (60-120Hz) for body
- Crunch/crack (2-6kHz) for transient
- Slight metallic ring for armored targets
3-4 variants, pitch-varied to prevent repetition.

**Creature death:** Crumble/shatter. Ceramic break (mid freq) + debris scatter
(high freq rattle, 0.3s) + subtle low reverb boom. For sacrifice: add a wet,
visceral squelch.

**Healing:** Gentle rising chime. Warm bell tone. Musical interval: perfect fifth
or major third (these sound "resolving" and "positive"). 0.3-0.5s with reverb.

**Buff applied:** Shimmery ascending tone. Small wind chime + sparkle. 0.2-0.3s.
Gold/positive feeling.

**Debuff applied:** Descending low tone. Dark, slightly distorted. Opposite of
healing — unsettling. 0.2-0.3s.

**Gold gain:** Coin clink. Bright, metallic, brief. Deeply satisfying.

**UI button click:** Soft wood or stone tap. Not plastic, not glass. 0.05-0.1s.

**End turn:** A decisive sound — a bell toll, a wooden stamp, or a fire flare
(matching the burning meadow theme). 0.3-0.5s.

### Music Per Scene

| Scene | Style | Tempo | Key Instruments |
|-------|-------|-------|-----------------|
| Main Menu | Orchestral ambient, bittersweet | Slow (60-70 BPM) | Strings, gentle brass, distant choir |
| Map | Light adventure | Moderate (80-90 BPM) | Acoustic guitar, flute, soft percussion |
| Combat (normal) | Tension, driving | Medium (90-110 BPM) | Drums, low strings, brass hits |
| Combat (elite) | Intensified combat | Faster (100-120 BPM) | Heavier drums, aggressive strings |
| Combat (boss) | Epic, dramatic | Variable | Full orchestra, choir, war drums |
| Shop | Tavern, relaxed | Slow-moderate (70-85 BPM) | Lute/guitar, fiddle, warm bass |
| Rest | Campfire calm | Very slow (50-65 BPM) | Solo guitar, nature ambience, gentle harp |
| Event | Mysterious | Slow (55-70 BPM) | Woodwinds, soft bells, sparse texture |

All loops: 2-4 minutes, seamless loop point. Format: OGG Vorbis for Godot.

### Volume Mixing
- UI sounds: -12 to -18dB relative to max
- Impact/combat sounds: -6 to -12dB
- Music: -18 to -24dB (stays underneath everything)
- Critical/lethal hits: +3 to +6dB above normal hits (emphasis punch)

---

## 17. TYPOGRAPHY EFFECTS ON CARDS

### How Text Should Be Rendered

**Card name (on banner):**
- Cinzel SemiBold, ALL CAPS
- Color: warm cream `#F5E6C8`
- 1px outline `#2B1D0E` at 80% opacity (subtle, banner provides contrast)
- No glow, no shadow beyond the outline

**Stat numbers (on badges):**
- Cinzel Black (wght 800)
- Color: white `#FFFFFF`
- 2px black outline at 90% opacity — HEAVY outline because badges sit on
  varied-color surfaces
- 1px drop shadow downward, black 50%

**Body text (in description well):**
- Nunito Regular
- Color: dark brown `#3D2B1A` on parchment
- No outline (parchment provides clean high contrast)
- Keywords: gold `#D4AF37` + bold (embolden 0.7)
- This is the MtG/Hearthstone convention and it works because gold pops on
  cream parchment

**Floating damage numbers:**
- Cinzel Black, 20-24pt
- Damage: `#FF4444` red
- Heal: `#44DD44` green
- 2-3px black outline (mandatory — floats over busy backgrounds)
- 1px drop shadow

**Phase banners ("Round 3", "Your Turn"):**
- Cinzel SemiBold, 48-64px, ALL CAPS
- Player turn: gold `#FFD700`
- Enemy turn: dark red `#CC2222`
- Semi-transparent dark banner bar behind text (black 60%, 80px tall)

---

## 18. HAND OF CARDS — How They Fan and Move

### Card Fan Layout
- Cards overlap by 30-50% of card width
- Slight arc: 2-4 degrees rotation per card from center
- Center card is straight (0 degrees), left cards rotate slightly clockwise,
  right cards rotate counter-clockwise
- Total arc spread: 15-30 degrees depending on hand size
- When a card is removed: remaining cards re-fan smoothly over 0.2s

### Card Hover
- Scale factor: 1.15-1.25 (not more — too much zoom disorients)
- Hovered card rises 20-30px above the fan
- Transition: 0.12-0.15s (fast enough to feel responsive, slow enough to not jar)
- Easing: `TRANS_QUAD, EASE_OUT`
- Neighboring cards shift 10-15px outward to make room
- Z-index: hovered card renders above all others

### Card Draw Animation
- Card slides from deck position to hand slot over 0.3-0.4s
- Easing: `TRANS_CUBIC, EASE_OUT` (fast departure, gentle arrival)
- Brief white streak trail during travel (fading over 0.1s)
- Optional: card starts face-down, flips at midpoint (scale X 1.0 > 0.0 > swap
  texture > 0.0 > 1.0, 0.15s each half)

### Card Play Animation
- Card travels from hand to target lane along a slight upward arc (apex 30-50px
  above the straight-line path)
- Duration: 0.25-0.35s
- Easing: `TRANS_BACK, EASE_OUT` (slight overshoot at destination, then settle)
- On arrival: brief "slam" — scale to 1.1 for 0.05s then back to 1.0. Micro
  screen shake (2px, 50ms). Wooden thunk sound.

### Card Discard
- Card slides toward discard pile with a slight spin (15-30 degree rotation)
- Scale down to 0.7 during travel
- Easing: `TRANS_QUAD, EASE_IN` (accelerates away — "tossed")
- Opacity fades in last 0.1s

---

## 19. CHEAPEST-TO-IMPLEMENT, HIGHEST-IMPACT IMPROVEMENTS

Ranked by effort vs. payoff. Do these first.

### Tier 1 — Almost Free, Massive Payoff

1. **Hover feedback on everything clickable** (2-3 hours): Scale to 1.05 on hover,
   return on exit. Single tween. Makes the entire UI feel alive instantly.

2. **Damage numbers** (3-4 hours): Floating labels with pop-in/float/fade curve.
   Reusable for damage, heal, gold, block.

3. **Screen shake on hits** (1-2 hours): Already have CanvasLayer offset. Wire
   amplitude to damage amount.

4. **Hitstop on lethal blows** (1 hour): Pause 50-80ms before death animation.
   `Engine.time_scale = 0.0` for the duration.

5. **Battlefield embers** (2-3 hours): 5-10 persistent slow-drifting ember
   particles across combat field. Orange glow, 3-5s lifetime. Sells the theme.

### Tier 2 — Moderate Effort, Strong Payoff

6. **Creature death particles** (3-4 hours): Grey circles drifting up. 10-15
   particles, 0.8s lifetime. CPUParticles2D.

7. **Phase banners** (3-4 hours): Sliding text for round start, combat phase.
   Makes game flow legible.

8. **Card play arc animation** (3-4 hours): Tween along parabolic arc with thunk
   on arrival. Currently cards just appear.

9. **HP flash on change** (1-2 hours): Brief white (heal) or red (damage) flash on
   the number for 0.15s.

### Tier 3 — More Effort, Professional Polish

10. **Sound design pass** (6-10 hours): Even placeholder sounds for draw/play/hit/
    death/turn transforms the experience. Freesound.org CC0 filter.

11. **Card fan arc in hand** (4-6 hours): Curved layout with rotation per card.

12. **Impact particles per attack** (4-6 hours): Colored bursts at collision point.

13. **Idle breathing on cards** (1 hour): Tiny 0.5-1% scale pulse, 2-3s sine wave.
    Cards feel alive.

---

## PRODUCTION CHECKLIST — For Every New Asset

Before finalizing any visual asset, check these boxes:

- [ ] Top-left lighting at 45 degrees
- [ ] Warm color temperature (amber bias)
- [ ] Bold outlines (2-3px at card resolution) for character art
- [ ] Eyes are readable and expressive (for creature portraits)
- [ ] One clear focal point per image
- [ ] Passes silhouette test (recognizable as solid black shape)
- [ ] 70-80% frame fill for portraits
- [ ] Color-coded by function (damage=red, heal=green, buff=gold, debuff=purple)
- [ ] Texture consistent with parchment/wood/metal vocabulary
- [ ] No flat untextured surfaces
- [ ] Works at the smallest size it'll be displayed (card in hand, icon in HUD)
