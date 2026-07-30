# Screen audit — 2026-07-21

An objective pass over 17 shipping screens, rendered fresh from the current
branch (`feature/visual-polish-and-content`) and inspected as pixels, not as
code. Every finding below was seen in a rendered frame.

**Harnesses used** (windowed, editor closed):
`_shot_shell_screens` · `_shot_menus_audit` · `_shot_menu` · `_shot_more_menus`
· `_shot_combat_hud` · `_shot_map_states` · `_shot_event_all`

**Scoring.** Five axes, 1–10 each, then an overall that is a judgement call and
not an average. The axes:

| Axis | Question |
|---|---|
| Composition | Does the content occupy the frame deliberately? |
| Legibility | Can everything be read at couch distance? |
| Palette | Does it stay inside the sepia / gilt / ember world? |
| Clarity | Does the player know what is being asked of them? |
| Polish | Craft level — does it read as a shipped commercial game? |

A screen scoring 8+ overall needs no work before ship. 6–7 has a specific,
bounded fix. Below 6 has something a reviewer would notice in a trailer.

---

## Scores at a glance

| Screen | Comp | Leg | Pal | Clar | Pol | **Overall** |
|---|---|---|---|---|---|---|
| Settings overlay | 9 | 9 | 9 | 9 | 9 | **9** |
| How to Play | 9 | 8 | 9 | 9 | 9 | **9** |
| Main menu (title) | 9 | 9 | 9 | 8 | 9 | **9** |
| Game Over (chronicle) | 9 | 7 | 9 | 9 | 9 | **8** |
| Event — prose | 8 | 9 | 9 | 9 | 9 | **8** |
| Shop | 8 | 8 | 9 | 8 | 8 | **8** |
| Collection | 8 | 8 | 8 | 8 | 8 | **8** |
| Recruit | 7 | 7 | 9 | 8 | 8 | **8** |
| Event — gamble stage | 7 | 9 | 9 | 8 | 9 | **8** |
| Rest | 7 | 9 | 9 | 9 | 8 | **8** |
| Run setup | 8 | 6 | 9 | 8 | 8 | **7** |
| Treasure | 7 | 9 | 9 | 9 | 7 | **7** |
| Wayside | 7 | 9 | 9 | 7 | 8 | **7** |
| Reward | 6 | 8 | 7 | 8 | 7 | **7** |
| Map (war table) | 6 | 5 | 9 | 7 | 8 | **7** |
| Combat HUD | 6 | 7 | 8 | 8 | 8 | **7** |
| Credits | 9 | 9 | 9 | 9 | 9 | **9** |
| Net arsenal | 6 | 8 | 8 | 9 | 8 | **7** |
| Skirmish lobby | 8 | 8 | 4 | 8 | 7 | **6** |
| Net draft | 7 | 7 | 5 | 8 | 6 | **6** |
| Net quick battle | 6 | 2 | 7 | 7 | 6 | **5** |

Nothing is broken. The spread between 6 and 9 is almost entirely **composition
and a handful of off-palette accents**, not craft — the material kit, the
typography, and the art direction are consistent and good across all 17.

---

## Cross-cutting findings

These are worth more than any single-screen note, because each one is a single
fix that lifts several screens at once.

### 1. Vertical composition — smaller than it first looked (Rest, Wayside)

**Corrected after measuring.** The first pass through these screenshots read
five screens (Reward, Treasure, Recruit, Wayside, Rest) as top-heavy with a dead
bottom third. Measuring the actual content bounds against the frame showed that
was wrong for three of them: Recruit's block runs y≈200–873 in a 1080 frame
(≈180px above, ≈187px below — centered), and Treasure and Reward are centered
too. They *read* top-heavy because a small title sits above a large tile block,
which puts the visual mass high — but that is a weighting impression, not a
misalignment, and "fixing" it would have pushed correctly-centered layouts off
centre.

Two screens were genuinely off:

- **Rest** pinned its command column at fixed offsets sized for the worst case
  (four banners); the common camp shows two, leaving the column hugging the
  upper-left above ~350px of empty frame. FIXED — the column now centers on its
  real measured height, and a four-banner camp stays where it was.
- **Wayside** centered its tiles correctly but anchored the walk-away line to
  the bottom-LEFT corner, diagonally across the screen from the choices it
  dismisses. Every sibling stop (Shop's "Leave the Wagon", Recruit's "Turn Them
  Away", Treasure's "Take gold instead") centers it under the content. FIXED —
  it now seats beneath the tile stack.

**Method note worth keeping:** an eyeballed "this looks unbalanced" is a
hypothesis, not a finding. Measure the content bounds before moving a layout.

### 2. Off-palette accents (Skirmish lobby, Reward)

The whole game is sepia, gilt, ember, bone, and verdigris. Three elements break
that world:

- **Skirmish lobby: `HOST (LAN)` renders bright green and `JOIN` renders bright
  blue.** Against the near-black lobby these are the only saturated cool colors
  on the screen and they read as unstyled default UI — the exact "Godot
  template" tell the project is otherwise very careful about. This is the single
  most visible palette defect in the build.
- **Reward: the flag glyph left of the title is cyan/steel blue** on a
  blood-and-ash background. It looks like a placeholder icon.

**Fix:** route these through the house inks. `HOST` wants gilt (it is the
affirmative action) and `JOIN` wants gilt-on-hover like every other frameless
text button; the reward flag wants the ember or bone tint the rest of that
screen uses.

### 3. Micro-scaled card thumbnails print rules text nobody can read

Two screens render real `Card2D` nodes at roughly 0.37 scale as decorative
strips: the **run-setup deck preview** and the **Game Over muster row**. At that
scale the body text lands near 5px. It is not "small" — it is texture.

This does not violate the readability contract (`_probe_text_floor` passes
clean, and `Card2D.gd` is a documented exemption), so no probe will ever catch
it. But a player sees six cards covered in unreadable grey noise.

**Fix:** give the strip a thumbnail mode — art, name, cost, and stats only, with
the rules box suppressed below some scale threshold. The information a deck
strip actually carries is *what's in the deck*, and the rules text isn't doing
that job at this size. Hovering can float the full card, which both screens are
already structured to support.

### 4. Zero-states read like bugs

`PROVINCE 0` in the Reward title, `Provinces reached: 0` on Game Over, and
`0 / 33 provinces` on the map banner all render a bare zero where a player
expects a count. Some of this is harness state (a fresh run genuinely has zero),
so **verify these in real play before changing anything** — but the map banner
is real, and it stacks two different progress metrics in one line
(`Break 2 more holds to open the keep road · 0 / 33 provinces`), which asks the
player to track two clocks at once in a space sized for one.

---

## Per-screen notes

### Settings overlay — 9

The best screen in the build. Two balanced columns, real switch affordances,
detected-GPU line, accessibility grouped as its own block. Dense without being
crowded.

*Only note:* the GAMEPLAY column ends well above the DISPLAY column, so the
panel's bottom edge is visibly asymmetric. Cosmetic; low priority.

### How to Play — 9

Two-column book with a genuine keyword glossary carrying real device icons. Copy
is accurate to current rules — the Swift entry already states the muster-delay
Rush restriction, which means it was maintained, not left to rot.

*Only note:* both columns scroll and the scroll affordance is a nearly invisible
hairline. The left column visibly cuts mid-sentence ("Marked cards are"), which
is the one place a player might think the text is broken rather than scrollable.
A slightly more present scroll rail, or a fade-out at the cut, closes it.

### Main menu — 9

Left column against the center-right warrior splash, exactly the composition the
project settled on. The CURRENT RUN panel with dotted leader lines is a
genuinely nice piece of furniture.

*Notes:* the menu reads `NEW RUN`, but `CLAUDE.md` documents this item as
`NEW MARCH` — one of the two has drifted and it's worth deciding which. And
`credits` sits in lowercase grey beneath a column of gilt caps; it's deliberate
de-emphasis but it's the only lowercase item on the screen.

### Game Over — 8

The charred chronicle page is the most *authored* screen in the game. The run
summary, relic row, Named Veterans / Roll of the Fallen columns, and the
`CLOSED XXII` wax seal all land.

*Note:* the muster row is cross-cutting finding #3 — six thumbnails of
unreadable rules text. Also `THE MUSTER (10 cards)` labels a row of 6 visible
cards; the `×2` badges do explain it, but the header and the row disagree at a
glance.

### Event (prose) — 8

Widow's Tray: verdigris mood tint on the title, drop-cap opening, roman numerals
for ordinary choices and a verdigris diamond for the blue option so the special
choice is never a numeral. The adaptive scrim keeps body text legible over very
dark art. This system is in good shape.

*Note:* `WALK ON` is bottom-right while the choice column is left — a long
diagonal for a frequent action.

### Shop — 8

Clear three-band structure (cards / relics & services / dismiss), prices read
cleanly, the buy-back tile is a genuinely good idea.

*Notes:* the relic and service tiles are ~300×200 holding an ~80px icon, so they
read mostly empty next to the dense card row above them. The Buy-Back tile's
icon is a grid of miniature card backs, which reads as a contact sheet rather
than a shop service and is visibly less finished than the painted relic icons
beside it. Relics price at 90g here while `CLAUDE.md` documents 100g — worth
confirming which is current.

### Collection — 8

Tabs, section counts, and a clean card grid at a size where the cards are
actually readable. The right comparison here is a real card game's collection
screen, and it holds up.

*Notes:* the busy tavern background shows through the grid gaps and competes
with the cards; a heavier scrim behind the grid would let the cards own the
screen. The scrollbar is nearly invisible on a screen whose entire purpose is
scrolling.

### Recruit — 8

Verified settled (the first pass caught it mid-animation; a 4s-settle re-shoot
confirmed the layout is clean and the pale rings were the uncommon
`rarity_reveal` shine in flight, not an artifact).

*Notes:* the role labels (`LOCAL BANNER` / `FIELD ANSWER` / `SELLSWORD`) are the
only thing explaining *why* these three cards are the offer, and they render at
15px in low-contrast grey — below the 16–17 caption band the project uses
everywhere else. They should be the second thing you read, and right now they're
the last. Plus the dead bottom band (#1).

### Event (gamble stage) — 8

The knucklebone patch is a real prop on a real receding plane with the pot
numeral on the cloth. The stagecraft ambition here is well above the genre norm.

*Note:* the patch runs off the right edge of the frame, and the left column has
a ~550px vertical gap between the pot title and the description. The stage split
is intentional; the gap inside the left column isn't.

### Rest — 8

The campfire art is the best background in the game and the left command column
is the accepted composition for a living scene.

*Note:* the two option cards end at y≈680, leaving the lower-left quadrant
empty. With only two verbs available (the third, Hold a Wake, needs fallen) the
column looks short rather than composed. Consider centering the column
vertically against the fire so a two-verb camp still reads deliberate.

### Run setup — 7

Genuinely dense and genuinely good: hero list, portrait, tagline, tribe tags,
strategy line, deck, relic, locked-unlock hints, and campaign record all coexist
without collision.

*Notes:* the deck strip is cross-cutting finding #3, and it's worse here than on
Game Over because this is the screen where a player is actually trying to
*evaluate* a deck. Separately, `DAILY RUN: OFF` is plain text on a screen one
click away from a Settings overlay full of proper switch affordances — the same
control, styled two different ways.

### Treasure — 7

Clean and atmospheric; the "or take 80 gold instead" fork is stated plainly.

*Note:* one relic tile at ~430×380 holding a ~140px icon and two lines of text,
floating above ~280px of empty frame. The screen has one decision and gives it a
lot of room without giving it any weight. A larger icon, or a tighter tile,
would make the single relic feel like a find rather than a placeholder.

### Wayside — 7

Three clear options with effects stated in one line each.

*Note:* the drop-cap initials render `C`, `F`, `B` — pulled from each option's
first word. As a letterform device it's handsome; as information it's noise,
because a player reads `C / F / B` and looks for a meaning that isn't there
(they aren't hotkeys, and they aren't an ordering). The events screen solved
this correctly with roman numerals plus a diamond for blue options. Matching
that convention here would make the whole game's choice grammar consistent.

### Reward — 7

*Notes:* the cyan flag glyph (#2). Content occupies a band from y≈200 to y≈790
with large voids above and below (#1). And the two relic tiles are flat dark
panels — on a screen whose entire job is "you beat a General, here is your
prize," the presentation is quieter than the Treasure screen's single relic.
This is the reward moment; it should be the loudest of the three relic screens
and it's currently the softest.

### Map (war table) — 7

The staged-parchment plate, generated coastline, engraved terrain marks, and
lamplight band are excellent, and the whole thing is on-palette.

*Notes, and this screen has the most of them:*
- **The act cartouche overlaps live nodes.** In the act-1 open state it covers a
  cache node and part of a fight node in the top-left. A HUD panel sitting on
  top of clickable content is the one thing here that is a genuine defect rather
  than a taste call.
- **Tooltips clip at the right edge.** `THE PASS GATE / THE PYROMANC…` is cut
  off mid-word by the viewport. Tooltips near the right edge need to flip to the
  left of the cursor.
- **Site labels are ~11px engraved caps** (`RELIQUARY`, `DRILL YARD`,
  `GENERAL`). They're drawn as part of the plate rather than as UI labels, so
  the text-floor probe can't see them — but they are the screen's primary
  wayfinding and they are the smallest worded text in the game.
- **The lattice hugs the top and right**, leaving roughly the lower-left third
  of the sheet as blank parchment with a long empty road from camp. The
  generator's node placement and the sheet's shape aren't currently negotiating.

### Combat HUD — 7

Rich and readable: forecast chips, incoming/reinforcement rail, log tab, relic
and potion rails, foe portrait with HP.

*Notes:*
- **The encounter passive text is laid across the enemy board.** "When a
  friendly creature dies: the enemy draws and places a creature immediately."
  renders at y≈120 in dim grey *inside* the board rect, overlapping lane I's
  card and running across the empty lanes. It's important information printed on
  top of the play space in the lowest-contrast ink on the screen. It wants to be
  a chip in the top rail or next to the encounter name, not a caption over the
  battlefield.
- The hand is clipped by the bottom edge — roughly the lower 40% of each hand
  card is off-frame. Hover-lift presumably reveals them, but at rest the player's
  own hand is the least legible element on the screen.
- The `5 / 3` Command orb is ambiguous on sight: current-over-base is a
  reasonable reading, but so is "5 of 3," which is nonsense. A player shouldn't
  have to derive it.
- The relic rail wraps 3-over-2, which reads as a broken grid rather than a
  rail. Five in a row, or a scrolling strip, would read as inventory.

### Skirmish lobby — 6

Structurally the best-composed multiplayer screen — a proper triptych with your
banner left, the empty challenger seat right, and the match actions centered.
The empty-seat treatment ("The seat stands empty") is a nice touch.

*Notes:* the green `HOST (LAN)` and blue `JOIN` (#2) are what drops this to a 6.
Everything else on this screen is in-world; those two are not, and they sit dead
center. Secondarily, the five thumbnails under YOUR BANNER render at ~50px and
are unidentifiable.

### Credits — 9

Centered chronicle roll on parchment, sectioned and attributed. Correctly
centered rather than left-aligned (a lone document element).

### Net arsenal — 7

The 1-of-3 relic/potion slate with a pip row tracking progress through the five
picks is a clean piece of design. *Note:* content ends at y≈830 with 250px of
dead frame below (#1), and the underlying draft screen's ghosted title sits
directly above "ARM YOUR WARBAND", so two titles compete at the top.

### Net draft — 6

*Notes:* the YOUR WARBAND list rows render each card's **art bleeding across the
row as a background strip** behind the name — blue, teal, and red streaks that
read as a rendering bug rather than a design. The screen also has **no
background art at all** (pure black where every other screen carries a scene),
and the CHOOSE buttons are boxed with an olive-green tint — both off house style
and off palette.

### Net quick battle — 5

The lowest score in the audit, and the reason is one thing: **20 cards rendered
at ~110px with full rules text.** This is not a decorative strip like Game Over's
— this is the screen where the player evaluates a random warband and decides
whether to reroll, and the entire information payload is unreadable. The card
grid is doing the opposite of its job.

Secondary: the last row (2 cards) centers under full rows above it, and the
three actions read `Random` / `REROLL` / `READY` — three different casings in
one row, with READY tinted green.

---

## What was fixed in this pass (2026-07-21)

All verified by re-rendering the affected screens; `_probe_text_floor`,
`_probe_textfit` (224 screens, 0 hits) and `_probe_creature_fx` all pass.

1. **Card thumbnail mode** (`Card2D.thumb_mode`, gated by
   `GameTheme.THUMB_TEXT_CUTOFF = 0.55`). Deck strips at ≤0.55 scale no longer
   print ~5px rules text; the card's own painting runs on through the rules well
   instead, so the thumbnail reads as full-art. Wired into the shared
   `make_card_thumb` funnel (all four skirmish modes), plus Game Over's muster
   row and the run-setup deck strip. **Both** layout paths are gated — the baked
   overlay AND the live writ layout, because a cold `CardTextureCache` sends a
   deck strip down the live path, which is exactly what a freshly opened
   run-setup screen does.
   - *Two wrong turns worth recording.* Blanking the well outright was tried
     first and looked broken — a large empty cream panel reads as missing
     content. Then cover-cropping the art centred it, which repeated the slice
     the baked art window above already shows and read as a duplication bug on
     any distinctive silhouette. The fix that works is bottom-anchoring the
     crop so the two windows show different parts of one painting.
   - **SUPERSEDED (2026-07-24).** The bottom-anchor crop still read as a
     duplicated image — a landscape painting has nothing left to show below the
     top art window, so the second crop re-scales and re-shows the same picture,
     and the name banner between the two framed windows only sharpens the "same
     thing twice" read. It was reported in-game as "the pictures are glitched."
     `thumb_mode` and `_fill_thumb_panel_with_art` are **removed**; every
     thumbnail now keeps its crisp *vector* rules text at any scale. Verified by
     render at 0.36/0.46/0.6 that even the wordiest cards (Sapper's Charge,
     The Pallbearers, Gravepact) stay legible via `_fit_desc_to_box`, and a deck
     the player is reading is better served by visible rules than by full-art.
     The "~5px grey noise" premise of finding #3 was overstated — the shrink-to-
     fit body text is small but reads as writing, and shows what each card does.
2. **Off-palette accents.** The skirmish lobby's green `HOST (LAN)` and blue
   `JOIN` became verdigris and gilt; the same web-green/web-blue tiles were
   replaced with ash-brown (secondary) and ember (commit) across Draft, Quick,
   Constructed and Sealed, and their labels put in one casing.
3. **Rest** centers its command column on the column's real measured height.
4. **Wayside** seats its walk-away line under the tile stack instead of in the
   bottom-left corner.
5. **Combat's standing-rule plaque** dims to 0.55 rather than 0.30 when the foe
   fills their back row. Yielding to the token is right; at 0.30 the fight's
   only posted rule became invisible.
6. **Map tooltips** clamp into the viewport, fixing the mid-word clipping on
   right-hand stops when the chart is zoomed.
7. **Net draft ledger** knocks its art band back so the card names stay the
   hero of the row; **Recruit** role labels moved to the 16px caption band.

## Second pass — parallel agents (2026-07-21, same day)

Four agents worked disjoint file sets; findings and fixes folded in here. A
companion sweep report lives at
[`PALETTE_READABILITY_SWEEP_20260721.md`](PALETTE_READABILITY_SWEEP_20260721.md).

8. **Combat HUD.** The hand's clipping turned out to be a *maintained* design
   (`PEEK` was deliberately raised from 76 to 92 so the fold stops below the
   rules box, with `Card2D`'s `-96` hover lift tracking it) — but `arc_drop` was
   being added on top of `PEEK`, so the outer cards of a wide fan sank a further
   18px and lost the bottom of their own name cartouche. Re-based so `PEEK`
   describes the deepest card. The Command seal now presses the spendable count
   alone: `player_max_mana` is an *income*, not a cap (unspent Command banks), so
   a slash was asserting a containment that doesn't exist — which is exactly why
   `5 / 3` read as nonsense. The relic rail derives its column count from the
   hoard instead of hardcoding 3, so five relics are one row of five, and 12
   relics now render *larger* than before rather than smaller.
9. **Reward / Treasure / Shop.** One root cause: `make_relic_card` sizes its
   icon from the *box*, so at every size these screens use the tile was 22–32%
   air — which is what read as "flat panel" and "placeholder floating in a
   tile". All three now size the painting first and close the box onto it.
   Reward's icon +40%, Shop's +61%, and Treasure's tile got *smaller* while its
   icon got bigger. Narrative weight now matches presentation weight.
10. **Collection / How to Play.** The card grid sits on its own ink plate so the
    painted room stops competing with the cards, and both How-to-Play columns
    gained a visible rail plus a fade at the cut, so text visibly runs under the
    panel instead of stopping dead mid-sentence.
11. **`RelicDB.TIER_COLORS`.** Three of five tiers were already in-palette
    (gilt / ember / verdigris) and two were leftover neon — utility a web-green,
    boss a screen magenta. Both muted into the family, hue kept so utility still
    reads green and boss still reads violet. This rides every relic chip in the
    game, so it was the single widest-reaching palette fix.
12. **13 further sweep hits** in Rest, Event, MapView, NetLobby, NetDeckBuilder
    and NetConstructed — the forge lighting up green at its own gilt-accented
    hero moment, heal flashes re-introducing the electric green `HEALTH_GREEN`
    exists to retune away, and reading text at 14–15px in the Hold a Wake
    picker, the morris drill, the tali payout table and the race lane chips.

### What the parallel pass taught

- **The first pass's palette fix was incomplete in a way screenshots couldn't
  show.** Three more olive-green commit tiles were live in `Combat.gd` — on the
  scry / tutor / discover overlays, i.e. *more* frequently seen than the lobby
  buttons that did get fixed. A source sweep found in minutes what a
  screenshot pass structurally could not.
- **Settings scored 9/9 on legibility from a rendered frame and every row name
  on it is 15px**, including `Color Blind Mode`. It looks fine at 1080p and is
  sub-floor at the 1600×900 canvas §11 sizes for. `_probe_text_floor` should
  grow a warning band for worded text at 14–17 outside the caption register.
- **`MainMenu._make_menu_button` takes a `_bg: Color` it discards.** Eight call
  sites pass elaborate greens and blues that never reach a pixel — which is why
  the main menu scored 9 on palette while looking like the worst offender in the
  codebase. Harmless today, a trap for whoever rethemes that screen.
- **The Settings bottom-edge asymmetry is already optimal.** Enumerating every
  group-preserving two-column partition shows the shipped arrangement has the
  minimum imbalance (82px; the next best is 142). Fixing it would require
  splitting a section across columns or stretching row spacing — both worse.

## Deliberately left alone after investigation

- **Wayside's `C / F / B` drop-caps.** Flagged as arbitrary-looking, but the
  code shows the author already handled the obvious failure (it strips leading
  articles so three "A …" options don't all print "A"). Switching to the event
  screens' roman numerals is a design opinion, not a defect fix — worth raising,
  not worth changing unilaterally.
- **The map's act cartouche.** It grazes the top-lane *labels*, but the lane
  pitch carries a comment explaining the tuning it already does to clear the
  cartouche and the legend band; moving `cy` to buy a few pixels at the top
  risks the bottom lane. Under zoom/pan any fixed HUD will overlap plate content
  — that is inherent, not a bug.
- **The skirmish screens' black backdrop.** Real (every campaign screen carries
  painted art), but choosing art is a direction call, not a cleanup.
- **The map's "big empty region".** Softened after checking acts 2 and 3: the
  coastline is a hull over the actual node field, so it does hug the lattice,
  and the space below the road reads as unexplored island rather than as a
  layout void. Act 3 in particular composes well. What's actually true is
  narrower — the generator leans on the middle lanes on the left of the sheet
  and the outer lanes on the right, so the silhouette is driven by its widest
  point. That's a generator-distribution nicety, not a defect.

## Open copy question for the user

The set-piece node prints **`NAMED ACTION`** on the chart. This is deliberate
and documented (`MapTerrain._site_label_text`): a set-piece must never read as a
plain FIGHT, and its own name was judged too long for the token, so the token
carries the category and the tooltip carries the name.

The concern is that "NAMED ACTION" is the *designer's* word for the feature — it
appears throughout the code comments as the internal name — and to a player it
is abstract jargon that says nothing about what is there. COPY_STYLE §10's road
register asks for plain words before coloured ones.

There is a concrete alternative: the three scenarios are **The Sunken Road**,
**The Pay Column**, and **The Standard of the Fourth**. The first two fit a
token as `SUNKEN ROAD` / `PAY COLUMN`; the third needs a short form
(`THE STANDARD`). A `short_name` field on the SetPieceDB entry would let the
chart name the action instead of its category. Left unchanged because it is a
copy decision under your governance doc, not a defect.

## Recommended order of work

1. **Recolor `HOST` / `JOIN` in the skirmish lobby, and the reward flag glyph.**
   Minutes of work, removes the only "unfinished" tell in the build.
2. **Move the combat encounter-passive line off the board** into the top rail.
   Correctness of presentation, not taste.
3. **Clamp map tooltips to the viewport and move the act cartouche clear of the
   node field.** Both are genuine defects on the screen players see most.
4. **Center the content block on Reward / Treasure / Recruit / Wayside / Rest.**
   One layout change, five screens lifted.
5. **Thumbnail mode for micro-scaled `Card2D`** (run setup, Game Over).
6. **Lift the map's site labels** out of the plate bake into real labels at a
   readable size, or enlarge the engraved type.
7. Smaller: recruit role labels to the caption band; wayside drop-caps to roman
   numerals; `DAILY RUN` to a real switch; shop service-tile density; collection
   scrim and scrollbar.

## Things deliberately *not* flagged

- **Frameless text buttons** (`Continue`, `Leave the Wagon`, `BACK`,
  `Turn Them Away`) are the established house style, chosen explicitly over
  boxed buttons. They are not inconsistency.
- **Dim inks on sub-headers and footnotes** are deliberate hierarchy, verified
  legible in earlier contrast passes.
- **Card face type sizes** are their own tuned system and a documented probe
  exemption. Finding #3 is about *scale of the whole card*, not about the card's
  internal type.
