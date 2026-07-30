# THE RULE-FIRING LAYER — research pass, 2026-07-28

**Status: PHASES 0a / 0b / 2 BUILT + VERIFIED. Rest is plan.**

| phase | state |
|---|---|
| **0a** numeral honesty | **BUILT** — `Card2D.take_damage` + `take_damage_bypass_armor` both print life actually LOST; raw blow still drives the shake |
| **0b** particle silhouettes | **BUILT + SHOT** — `Motion.particle_tex()` bakes fleck/spark/disc/ink; every preset carries one; `scale_amount` divided by texture size so nothing changed size |
| **2** the rubric | **BUILT** — `scripts/ui/painters/RubricStroke.gd`; `_play_pierce_lance` deleted; client mirror rewired in `CombatNet._net_replay_pierce` |
| — | audio: dead `"error"` cue → `"refused"` with a fallback (see §14) |
| **4a** SHIELD costume | **BUILT + SHOT** — a wax seal straddling the art/scrim boundary; breaks when the shield pops. Retires its own chip via `_spawn_keyword_chip(..., costumed := true)` |
| **4b** LAST STAND costume | **WITHDRAWN — see §7.1.** Kept its chip |
| **bugs** | **FIXED** — Trebuchet targeting, the Swift forecast lie + phantom lunge, the highlight over closed ground, the silent refusal cue |
| 1, 3, 5, 6, 7 | not built |

### §7.1 — the Last Stand candle: a negative result

Specced as "reuse `CandleStub`, zero new art". **It does not survive contact and was
withdrawn after one shot.** `CandleStub` is an event-stage prop: it draws its brass
dish, drip beads and flame halo *well outside* its own rect — measured at roughly
4× the requested width. At a 26×42 token slot the halo alone was wider than the
200×150 token and the whole prop hung off the card. Shrinking the rect does not
help, because the glow scales with it: a total footprint small enough to sit on a
token leaves a ~4px candle body, far below the legibility floor.

**The general lesson, worth more than the costume:** "reuse an existing painter,
zero new art" is only free when the painter was drawn for a comparable SIZE. A
prop authored for a full-screen event stage is not a token ornament, and its
overdraw beyond its own rect is invisible until you shoot it.

Last Stand still wants a costume — the mechanic is the single most
"why didn't it die?" moment in the game — but it needs one authored at token
scale. A candle is still the right IMAGE; it needs its own small painter.

### §7.2 — `clip_contents` is not a reliable way to halve a painter

The seal's first break drew two `clip_contents` halves flying apart. Unclipped —
which is what happened — each "half" draws a WHOLE seal, and two whole seals
20px apart are indistinguishable from one intact seal. **The shot of the break
looked identical to the shot of the intact seal**, which is exactly the class of
failure that is invisible without a before/after pair. Same family as the
documented `clip_children` inertness on gl_compatibility. The shipped break uses
no clipping: the wax bulges, a bright fracture line flashes, the blob distorts and
fades, and fragments burst through `Motion.burst`.

### §7.3 — placement notes that only the shots could settle

- On the ART the 52px seal read as **a glossy blue pill on the creature's face** —
  the "jelly button" failure `WaxSeal`'s own header says its 2026-07-19 rework
  existed to kill. Cause: a light, saturated blue. Wax is dark and matte and earns
  its highlight from one ridge.
- Moved onto the scrim at stat-seal size, it read as **a third stat orb** — an
  empty blue circle in a row with ATK and HP.
- What works is **straddling** the art/scrim boundary at 48px (larger than the
  38px stat seals) and off-axis. A seal is not a circle in a row of circles; it is
  pressed across an edge, at its own size, off everyone else's alignment.

Harness: `tools/_shot_rule_layer.tscn` (windowed) — writes `_shot_rubric.png`,
`_shot_rubric_grey.png`, `_shot_ptex.png` and prints a greyscale contrast table.
**Two traps it cost a run each to learn:** the capture is the project's
**1600×900 stretch canvas, not the OS window** (lay the grid out to that box, and
scale design coords by `img.width / viewport.width` before sampling, or the
sampler reads empty margin and reports 0.000 against a plainly visible mark); and
desaturate with the native `Image.adjust_bcs(1, 1, 0)` — a per-pixel GDScript
loop is 3.24M `set_pixel` calls and blows a two-minute budget by itself.

Four-agent pass (code audit / genre craft research / Godot feasibility / art
direction), then a two-way cross-examination between the art director and the
craft researcher. This document is the resolved output, with every contested
call ruled on and every load-bearing number verified against code.

The prompt: *"attacks a lot of effects and words like overkill and such look very
basic now — like they are a white line from a place to another or simply one word
on screen."*

---

## 0. VERIFIED BUG — fix this before any visual work

`Card2D.take_damage` ends with `_spawn_damage_number(amount)` (Card2D.gd:3244),
where `amount` is post-mitigation but **never capped to the victim's remaining
HP**. `_apply_piercing_overflow` then computes `excess = abs(victim.current_hp)`
and deals it to the body behind, which prints its own numeral.

A 6-ATK attacker killing a 2-HP blocker and carrying 4 therefore renders:

| element | shows |
|---|---|
| victim's numeral | **−6** (raw) |
| body behind | **−4** |
| **total on screen** | **10, from a 6-ATK attacker** |

Harmless before 2026-07-28 (excess vanished silently); a live legibility defect
since OVERKILL shipped, because the excess is now real AND printed twice.

**Fix:** cap the victim's floating numeral to damage actually absorbed
(`mini(amount, hp_before)`). The sum then reads 2 + 4 = 6 and the rule becomes
derivable from a single firing. Do NOT cap `current_hp` or the excess
computation — only the number shown.

This decides a design call downstream: the no-word treatment for OVERKILL
depends on the numerals teaching the rule, and they currently teach a false one.

---

## 1. DIAGNOSIS

**The callout chip is the only object in the game that isn't made of anything.**

Every other element declares a substance. `WritLeaf` exists specifically because
"a mathematically perfect corner is the one thing real cut paper never has."
`WaxSeal` has a lit ridge and a shaded ridge and forbids an interior sheen.
`LaneAftermath` draws oiled leather with a brass tack.

`spawn_keyword_callout` (Combat.gd:22755) builds a `StyleBoxFlat` with a perfect
7px corner radius, a uniform-width uniform-alpha border with no light side, and a
soft drop shadow. That is injection-moulded plastic — a mobile-game toast. And it
is the most-fired visual in the build, so **the game's single most-repeated image
is its only material-less one.**

**The palette proves it independently.** The chip colours are brighter, more
saturated versions of the exact colours GameTheme's own comments reject by name:

| chip | value | the palette comment |
|---|---|---|
| `wither` (0.80, 0.58, 0.90) | lavender V0.90 | SPELL_PURPLE: desaturated "so it no longer reads as glossy digital UI against parchment" |
| `armored` (0.62, 0.80, 1.00) | sky V1.00 | MANA_BLUE: "dropped the digital-cornflower sat/value" |
| `poison` (0.58, 0.93, 0.34) | acid green | HEALTH_GREEN: "was electric #40D959; muted to a herbal sage" |

The callout layer did not drift from the palette. **It never joined it.**

**The line.** `_play_pierce_lance` (Combat.gd:23779) is a 2-point `Line2D`,
width 5, `Color(1.0, 0.96, 0.72)`, round caps, fading in 0.18–0.20s (unscaled by
anim_speed, so it desyncs from its own chip at other speeds). Three failures:

1. **Constant width is a tool mark, not a phenomenon.** Nothing physical has
   uniform width, so the brain files it under *annotation*.
2. **A straight line between two objects is the universal convention for
   RELATION** (UML, node graphs, tethers), not for FORCE. Drawn perfectly it
   would still say "A is associated with B."
3. **It starts at the wrong end.** Overkill's fiction is force exiting the
   victim's back. Attacker-origin makes it a *reach*; victim-origin makes it a
   *consequence*. Both researchers reached this independently.

**And the deepest problem is not rendering at all.** Twelve mechanics
(THORNS/ARMORED/SHIELD/LAST STAND/POISON/WITHER/REGENERATE/SWIFT/GUARDIAN/
SACRIFICE/EXHAUST/PIERCING) arrive as the same shape, same size, same font, same
rise-and-fade, differing only in hue and a word. That is a **legend**, not an
**event** — twelve channels at identical volume against a ~4-fact retention
budget. **It is a quantity problem wearing a rendering costume, and no amount of
drawing any one of them better can fix it.**

Reachability audit: of 27 keywords, only 10 ever produce a callout and only 5
produce anything beyond a floating label. `_CALLOUT_STYLE`'s `swift` and
`guardian` entries are dead (no call site); `armored` and `last_stand` are
shadowed by Card2D's hardcoded colours; `shield` has two different colours
depending on code path. `"OVERKILL"` is not in `_play_keyword_pulse_for`'s
`strong` prefix list, so plain overkill gets no ring — only Piercing does.

---

## 2. THE SYSTEM — a rule firing is an amendment to the record

The world has two physical objects, and both are documents: the **writ** (a card
is a soldier's commission) and the **war table** (a chart inked on scorched
wood). When something happens the plain text didn't cover, somebody writes it
down. Three registers, routed by one question answerable at any call site:

> **Did the world change → STRIKE. Was a ruling made → STAMP. Did a clock tick → MARGIN.**

- **STRIKE** — rubric, red ink, laid by a chronicler's nib. A killed creature is
  a line of text crossed out. OVERKILL and PIERCING live here.
- **STAMP** — an inked cachet pressed on the record by an authority. *(Superseded
  in §4 by the costume layer — see §7.)*
- **MARGIN** — a tally the table keeps, that STAYS. Poison, Wither. Explicitly
  NOT event-class.

Three silhouettes, **distinguishable before colour** — which is what makes the
system survive deuteranopia on a red/brown table, the worst-case hue pairing.

**A fourth register is missing and should be added: REFUSAL.** Every stamp in the
table is "I absorbed something"; none is "you may not." This build is full of
refusals with no channel at all — the muster delay, Swift denied the face on its
arrival round, `closed_lanes`, unplayable curses gated in `_on_card_played`,
inert structures. The project has already learned this lesson once and written it
down (closed lanes wear the `ClosedGround` hatch because "a refusal the player
can't see reads as a drag bug") but never generalised it.

**Structural move:** strikes and stamps stop parenting to `_hud_layer` and become
children of `_board_container`, like `LaneAftermath` — table space, inheriting
the ★6 lockstep shake contract for free. *Nothing that matters in this game
floats above the table.*

---

## 3. THE HOUSE VALUE LAW (generalised from the contrast rule)

> **Every mark in this layer carries both extremes of the value range: a
> white-hot core inside an ink-black knockout.**

The existing white-hot-core rule is correct **for the wood table**. But many
effects land on or near **light parchment**, where a cream core is *lower*
contrast than the substrate. Core + knockout reads on both. This is not a
compromise with the material — gilt-leaf-with-an-ink-keyline is literally how
illuminated manuscripts are built, and `WritLeaf` already draws its edge toast
and ink contour along the same path for the same reason.

**The test that would have caught both prior reverts, and costs nothing:**
greyscale every candidate frame, at windowed resolution, over both substrates.
If it disappears in greyscale it will disappear on the table AND for a
colourblind player, and no amount of material honesty will save it.

---

## 4. OVERKILL — beat sheet

**Geometry (measured from code).** Column stack `150·6·150·6·30·6·150·6·150` =
654px; tokens 200×150 in `SLOT_W 204`; gutter 16. Victim centre → body behind =
156px. Stroke, victim's near edge through the far edge of the body behind =
`75+6+150` = **231px**. At 11px wide ≈ **2,540px² of mark** (the reverted seal
crack had an 8px annulus).

```
    ░▓█████▓░   ← 1.5px iron-gall knockout   (0.09, 0.05, 0.03, 0.75)
     ▓█████▓    ← 11px vermilion body        (0.77, 0.25, 0.16)
      █████     ← 4px ivory wet core         (0.99, 0.97, 0.90)
```

| t (ms) | element | material | class |
|---|---|---|---|
| 0 | existing impact: lunge apex, `_flash_face_hit`, spark, `creature_death`, `screen_shake(6)` | — | INFO |
| 0 | `ClashLaneFocus.focus_pair(victim_rect, behind_rect)` — surround inks down to the two involved bodies | ink slabs over the chart | INFO |
| 0 | **bodies freeze ~60ms, the nib runs anyway** — the mark is the only moving thing in a stopped world | — | INFO |
| 0 | grade micro-drain `u_sat −0.15`, `u_bright −0.06` over 60ms. FX sit on layer 12, grade on layer 10, so **the board drains and the stroke does not** | full-frame grade | DECOR (self-gates) |
| 0–55 | **nib drag phase 1** — head travels 81px through the victim. Chisel wedge ~35°, **low-frequency** ±1.5px seeded wobble (1–2 periods over the length; per-vertex noise reads as aliasing, not as a hand). `LINE_JOINT_ROUND` | vermilion / ivory / iron-gall | INFO |
| 55 | **the crossing** — head clears the victim's silhouette. Second body's `_flash_face_hit` fires here from `take_damage`; already built, and it is that body's share of the fused event | — | INFO |
| 55 | second audio cue, lower and wetter than the strike | — | INFO |
| 55–70 | **nib drag phase 2** — 150px through the body behind, terminating in a **blunt heel**: squared, slightly heavier, the pen lifted. It ENDS | — | INFO |
| 70 | **receiver beat** — recoil 8–14px with overshoot, instant numeral, ~30ms micro-hitstop | — | INFO |
| 70–230 | **THE HOLD** (rides `_impact_hold` 0.23, no new time). Ink dries: shoulders darken and wick outward. **Core narrows to 1px OVER TOKEN ART ONLY and holds ≥3px ACROSS THE GUTTER** — see §5 | ink drying into fibre | INFO |
| 230–440 | **payoff shot** — the corpse burns beneath the stroke (`DEATH_BEAT` + `_play_burn_death`). The struck-out line stays on the record while the entry it cancelled burns away underneath. Costs nothing; it is ordering | — | — |
| 440–960 | grade recovers, `clear_focus()`, stroke fades EASE_IN ~0.42s during `LANE_DWELL_KILL` | — | — |

**Reduce Motion (INFORMATIONAL):** drag skipped; stroke renders complete and
*dried* at t=0, holding the identical window. `focus_pair` snaps to full
strength. Grade drain self-gates to nothing (`_grade_mat` is null under Reduce
Motion). Freeze and flicks gated off.

**Implementation:** three `Line2D`s (knockout/body/core), **`antialiased = false`**
— documented unbatched when antialiased and unreliable on translucent lines, and
the shoulders are translucent by design. A procedurally baked brush texture
(64×16 strip, soft alpha falloff with seeded fibre notches, baked once at boot)
feathers better and cheaper. `texture_mode = TILE`, `width_curve` for taper.
Painter `scripts/ui/painters/RubricStroke.gd`, seeded on
`hash(attacker_eid, victim_eid, round)`; per-segment alpha jitter
`base_a * (0.7 + rng.randf() * 0.6)` — WritLeaf's own recipe for uneven bite.
**Not a flipbook** — length and angle vary per strike (Guardian redirects make it
diagonal), so nothing can be pre-baked per instance.

### Rejected alternatives, with reasons

- **Blade ARC** — `play_attack_lunge` already owns the swing, so a second arc on
  the same frame is the same sentence twice; an arc is a WEAPON idiom in a game
  whose voice is a RECORD; it must bulge into a 16px gutter fighting the vertical
  column read; and fatally, **an arc's shape says "a sweep that ENDED" while
  overkill's news is CONTINUATION.** Continuation is a fourth shape category
  (beyond travel/impact/connection) whose law is the opposite of an arc's: it
  must be unterminated and must not curve back.
- **Ink SPRAY** — this is documented revert #2 wearing a hat. Spray needs a
  receiving surface; the token is full-bleed art with no visible parchment and
  the table beneath it is occluded by the token.
- **The victim's writ TEARING** — contradicts ★1's burn; tear-then-burn is two
  death statements colliding inside 200ms; and a tear is a statement about the
  VICTIM when overkill's information is about the man behind.
- **Occlusion depth (ribbon behind the victim)** — a physical-force idiom. A
  rubric strike-through is a mark ON the record and has no depth to fake.

---

## 5. THE NAMED REVERT RISK (and its fix)

**Candidate: the 4px → 1px ivory core narrowing during the hold.**

The stroke crosses three substrates: token art (variable), the 16px gutter (dark
wood), token art again. A **bright** carrier reads on dark wood; a **dark**
carrier reads on light paper and **disappears on dark wood**. The hold converts
the mark from bright-carried to dark-carried over 170ms — so the segment that
loses its carrier is **the gutter segment**, which is *the only part of the
stroke that means "it carried."* On-token segments read as "this card was
struck"; the bridge between them is the entire semantic payload.

Compounding arithmetic:
- **1px is sub-pixel on common panels.** Canvas is 1600×900 with `canvas_items`
  stretch; at 1366×768 the scale is 0.853 → **0.85 physical px**, at 1280×720 →
  0.8px. With LINEAR filtering that resolves to half-alpha smeared over two
  pixels. It does not narrow — it *dissolves*.
- **Area vs the documented revert:** the reverted seal crack was ~750px². The
  ivory core STARTS at ~924px² and ENDS at ~231px² — roughly **one quarter of the
  area already reverted for being unreadable.** The 2,540px² figure is the whole
  stroke including the warm body, and warm-on-warm is exactly what the camouflage
  law says does not count.
- **The chemistry runs the other way.** Iron gall ink goes down pale and
  **darkens as it oxidises** — recipes included a fugitive dye so the scribe
  could see the line before the gall struck. "The ink dries" should mean contrast
  *increases*.
- **It is invisible to the harness.** Perfect at t=60 (the frame an early capture
  gets), gone by 440ms (a late one, and the project has a documented 1.4s SHOT
  SETTLE TRAP). There is no capture time that catches the failure. That is the
  exact profile of both prior reverts: correct in a still, wrong in motion,
  unfalsifiable by the existing gate.

**FIX — cheaper than the spec and more materially honest:** make the core width
curve **per-segment, not global**. Ink wicks into fibre and has nothing to wick
into over a gap, so a stroke crossing a void stays wet and bright longer. Narrow
to 1px over the tokens; **hold ≥3px across the gutter.** The drying survives, and
the brightest part of the mark lands on the part that means something.

**Lower-risk watch items:** the dry-split hairlines at piercing's far end (least-
watched end of a 650px stroke — but the plate charring carries that moment
regardless); the seeded wobble (**this one works** — vernier acuity is sub-pixel,
so ±1.5px over 231px is comfortably perceptible *provided* it is low-frequency).

---

## 6. PIERCING

Same nib, same ink, same 70ms — a palette swap to gilt was **rejected on
correctness grounds**: `_apply_piercing_overflow` is literally one function with
a `reach_face` bool, so two materials would teach two unrelated rules where the
mechanics are nested. Four differences, each carrying information:

1. **No terminus on the board.** Clears the enemy back row and runs to the hero
   plate: `192 + 156 + 75 ≈ 423px` of board plus HUD reach ≈ **600–700px**,
   against overkill's 231. Nearly triple.
2. **Pressure inverts.** Overkill tapers to a heel; piercing **widens** across
   the second body. One reversed `width_curve`.
3. **The last ~15% goes dry**, splitting into two hairlines with fibre between —
   a stroke that outran its own ink, which is precisely the mechanic.
4. **The terminus flares gilt and chars the plate** via ★7's `BURN_CODE` at
   `consume = 0`. The only body-blow in the game that scorches the enemy's panel
   mid-fight — an ABSOLUTE glanceability cue where length is only comparative.
   **This should be the loudest beat in the effect** (its own hitstop, its own
   cue), with the dry split as approach texture rather than the differentiator
   carrying the meaning.

You write in ink and you gild the initial: the gold is on the thing that was
reached, not on the pen.

---

## 7. THE COSTUME LAYER — the real answer

From Legends of Runeterra's Overwhelm and Hearthstone's Divine Shield: **a
keyword should be a material property visible on the card BEFORE it fires**, so
triggering is a *change to a familiar object* rather than the spawn of an
unfamiliar one. A costume costs **zero at fire time** and teaches the keyword
before it ever fires.

| layer | lives | costs at fire time |
|---|---|---|
| **COSTUME** — persistent, on the body | always | **zero** |
| **REACTION** — a change to the costume, ≤70ms | on fire | one small beat |
| **STRIKE** — the rubric, board space | overkill / piercing only | one mark |

**Vehicle constraint (measured):** the status rail roundel is 30px with a 6px
inset = an **18px glyph**, below the project's documented ~20px mush floor. The
rail is an *inventory you hover* (it has tooltips and `MOUSE_FILTER_PASS`), not a
costume you read across the board — a finding in itself. A costume must break the
**silhouette**, change a **large contiguous area** (the 200×45 scrim, the 184×138
art field), or alter an object **≥38px** (the wax seals).

| keyword | COSTUME | REACTION | verdict |
|---|---|---|---|
| **SHIELD** | a **wax seal over the face**, 56px, off-centre, existing `WaxSeal`, new seed — the document is sealed shut | the seal **breaks in half, halves fall** | ★3's premise finally correct: 56px, 100% visible, **no numeral on it** — we break the whole blob rather than draw an 8px fissure inside a 38px stat seal. **Reverses a revert.** |
| **LAST STAND** | an **unlit candle stub**, top-right — `CandleStub.gd` already exists (used by the Burning Inch) | the candle **gutters and goes out** | zero new art |
| **ARMORED** | **riveted bronze edge strips**, 6×150px both long sides, 4 seeded rivets each (~2×900px² on the silhouette) | strip **rings** — 40ms ivory flash + one rivet spark. Stripped = it flakes off | Divine Shield in our material |
| **THORNS** | **caltrop fringe** along the bottom edge, breaking silhouette ~8px over 200px | one caltrop **snaps off** and flies at the attacker — also the counter-stroke's origin | + a 60–70px reversed rubric stroke |
| **PIERCING** | a **bodkin point** protruding 14px from the leading edge | §6 | the only directional costume, for the only directional keyword |
| **GUARDIAN** | a **pavise** leaning against the token's inner edge, facing the lane it guards | incoming stroke arrives and **hooks one lane over** | a shape only Guardian ever makes |
| **REGENERATE** | **fresh growth** — seeded leaves along the bottom edge, **+1 per round regenerated** | one leaf unfurls | a costume that accumulates, which is the mechanic |
| **POISON** | MARGIN: running tally on `LaneAftermath`'s tacked leather chit (30–46px, above floor; the pip idiom already ships for salted-lane expiry) | a tick is added. **It stays** | strictly better attribution than a 400ms chip |
| **WITHER** | same chit | a **stroke through** the previous tick — the tally visibly shrinks | |
| **SACRIFICE** | none (a property of cards, not bodies) | vermilion **cancel-diagonal**, half length, TL→BR because the cause was not a blow | existing ash burst rides it |
| **ARMORED (extra)** | — | draw the incoming numeral, then **strike it out** with a 2px rubric tick as the reaction lands | the reduction is the news and is currently invisible |

**The 104px cachet stamp from the first draft is CUT** — it covers 69% of token
height, over the art the player uses to identify the creature. That is the same
reasoning that killed the reverted spatter, applied to a new proposal.

**Costume reactions are the correct flipbook application:** fixed geometry, fixed
size, fired hundreds of times per run. Bake 10–14 frames each from the painter
that already draws the static state, via SubViewport — `CardTextureCache`'s
existing technique. Zero external art.

---

## 8. DELETIONS — contested, decide before building

**Confirmed:**
- **REGENERATE** — `update_stat_display` already floats +N HP and punches the
  seal; the rail carries the roundel. A start-of-round +1 spawning an event-class
  object on up to 8 bodies is the largest single soup contributor. Genuinely
  duplicated coverage.
- **EXHAUST** — the card leaves; the destination is the news, and ★10 already
  punches the pile.
- **POISON / WITHER** — not deleted, *demoted to MARGIN*. A persistent mark is
  strictly better attribution than a 400ms chip, because attribution is a
  question asked *after* the number moves.

**Disputed — SWIFT.** "A phase, not a reaction" is right as far as it goes, but
Swift now carries three things: the pre-phase, the muster-delay exception, and
**a guarded refusal** (a Swift body may not reach the face on its arrival round,
`_creature_hits_face`). That refusal is the textbook case of "a ruling the player
could otherwise mistake for a bug" — they play Swift, expect the burst finish,
get nothing, and no channel says why. The fix is not a Swift chip; it is the
**REFUSAL register** (§2).

**The weakest sentence in the case for deletion:** *"nothing is lost because the
spawner logs to the chronicle before it spawns."* That conflates **accountability**
(what happened, retrievable) with **attribution** (why did this number change, at
the moment it changed). A drawer the player must open is not late — it is a
different interaction mode. "It's in the log" is the argument every game makes
right before shipping an illegible mechanic.

**Counter-model worth weighing:** Blizzard scales intensity by a card's "Big
Dealness" — a **volume ladder, not a cull**. Hearthstone's lowest-stakes triggers
are *shown*, just small: a portrait pulse, a quiet sound, the number. Note what
survives at the bottom of that ladder — **the sound**, because audio costs
nothing to keep and adds no screen clutter. Attenuation is the general
instrument; deletion is right only where coverage is genuinely duplicated.

---

## 9. THE WORD

Survives only where a mechanic is a ruling a player could otherwise mistake for a
bug. After §7 the costumes answer three of the four visually (the Armored strip
rings, the Shield seal breaks, the Last Stand candle goes out) — so the honest
final count is **one candidate, PIERCING**, on probation pending shots.

**Rejected: tracking blowout**, on arithmetic. "ARMORED" at 20px Kreon caps ≈
12.4px/char × 7 = 87px + 2px tracking × 6 = **99px**; at +40% tracking each gap
grows 8px → **147px** against a **118px** plaque. Overflows by 25%. It also
requires floating free in HUD space, which is the thing being removed. (And
per-character animation has exactly one supported path — a `RichTextEffect`
subclass; none exists in the project. Rejecting blowout means none is needed.)

**Rejected: scale overshoot**, on material. Overshoot is elastic — rubber, spring
steel, cartoon. A platen is iron on a lever: it descends, bites, lifts, and the
impression is a *static deformation of paper*. There is no rebound in the
artifact. Worse, overshoot-from-1.6× is an arrival from Z-space, and this game
has a fixed cabinet-projection camera. Nothing in Burning Meadow flies at the
lens.

**Adopted: letterpress impression**, two `draw_string` calls — (1) the word in
near-black at **+1px offset** (*ink squeeze*, the real artifact where pigment is
forced to the edge of the bite), (2) ivory on top, (3) a **1.5% vertical squash
over 40ms** releasing over 60ms. That is the plate's weight, and it is the whole
difference between "type bit the page" and "a label appeared."

**Setting:** `font_display` (Kreon Bold) at 20px, ALL CAPS, +2px tracking.
*(Note: CLAUDE.md's Cinzel/Alegreya note is STALE — the live roster in
`GameTheme._load_assets()` is Kreon and Inter.)* Not `font_title_black`, which is
`font_stat`, the numeral cut chosen for HUD readouts; a posted ruling is signage.

**Vehicle:** the token's own **118 × 45px dark scrim window** between the ATK and
HP seals (`ColorRect` at `anchor_top 0.70`, Card2D.gd:865; seals are 38px at the
bottom corners, 200 − 41 − 41 = 118). **Verified no collision** — the status rail
is top-right.

**Budget is ~7 characters, not 9.** At ~14–15px per character including tracking:
118/14.5 ≈ 8.1 with zero padding, ~7.6 with 4px padding each side. SHIELD (6) and
ARMORED (7) fit; GUARDIAN and OVERKILL (8) are at or past the ceiling;
**"LAST STAND" (10) does not fit at any padding** — and it is the mechanic that
most reads as a bug. Options: two lines at 15–17px (above the caption floor, and
period-correct for a letterpress impression), or accept that the seal re-press IS
Last Stand's statement. COPY_STYLE §0.3 forbids changing keyword `display`
strings and §4 fixes `Last Stand` as canonical, so a shortened verb is a
human-signed copy decision, not an implementation one.

**Teaching, in-voice:** the **first time overkill fires in a save**, the mark
lands and the margin takes a **gloss in a smaller hand** — literally the medieval
apparatus for "here is what this mark means." Fires once ever, costs one text
draw, and converts induction into instruction. Every reference game teaches its
keywords at first encounter; none relies on the player inducing a rule from
spectacle.

---

## 10. PACING — the law for this layer

Both prior positions collapsed into one synthesis. The project law encodes two
mechanisms with different scopes: **causal binding** (<100ms, governs whether
elements fuse into one event) and the **attentional blink** (200–500ms, governs
whether a second *discrete attention-demanding target* is missed). A continuous
motion is not a second target; it is one target with duration. The project
already runs this — `LANE_DWELL 0.30` / `LANE_DWELL_KILL 0.52` are serialization
gaps occupied by a spotlight holding.

The 160ms serialization originally proposed is **withdrawn**: in a game where
players have been trained by genuine vsync-bound hitches to read a stall as a
dropped frame, a 160ms gap after a kill reads as *the game hiccuped*. But the
separation it wanted already exists in the spec — **the stroke's head leaves the
victim's silhouette at 55ms.** The second body's news arrives late *by travel,
not by scheduling*.

> **The timing law for this layer:** *Elements of one rule fire as a single event
> fused under 70ms and sequenced by a mark that TRAVELS rather than by a wait;
> distinct rules serialize at ≥600ms on the existing lane dwell; nothing in this
> layer ever schedules a gap in the 100–500ms band.*

**The constraint is emptiness, not duration** — which is what legalises the
spec's own 170ms hold.

---

## 11. OPEN GAPS

**Parallel firing is unaddressed, and it is where soup actually comes from.**
Cutting twelve channels to seven addresses *how many kinds* of thing fire. It
does not address *how many of the same thing* fire at once — and this is a
four-lane simultaneous-combat game where STRIKE is the register most likely to
fire in parallel. Three lanes overkilling in one clash = three 231px strokes,
each holding 170ms, across a ~900px board. That is a page struck out.
**Fix:** lane-ordered stagger ~40ms apart (inside the binding window, so it reads
as one escalating sentence rather than a smear) plus a hard cap beyond N.

**Audio is absent from the whole plan, and the no-word call makes it
load-bearing.** With the word and number gone, the only signal that a distinct
rule fired is a silent mark. The register system has a free audio counterpart:
STRIKE = a nib scratch / wet drag (overkill's crossing gets a second lower cue;
piercing's runs dry) · STAMP = a single dry thunk (Armored and Shield one
semitone apart, matching their shape tell) · MARGIN = a dry tick, quiet, no
shake. That upgrades "three silhouettes distinguishable before colour" to
**"three registers distinguishable before you look."** Rising pitch across a
chain makes multiple firings read as one phrase.

**The receiver is still the quietest element in an effect that is about it.** The
direction rejects the writ-tear because "overkill's information is about the man
behind" — then gives the man behind the existing flash and nothing else, while
the victim gets the origin, the crossing, the flicks and a 210ms burn. §4 adds
recoil + instant numeral + micro-hitstop; verify by freezing at t=230 and asking
someone which card the effect is about. If they point at the victim, it is
telling the wrong story.

**The forward nib flicks are the reverted spatter at reduced count.** They land
in the 16px gutter or on full-bleed art — the same surface argument that killed
spray. Either cut them, or land them **back onto the stroke** as it dries
(thickening it irregularly at the crossing), where their surface is the mark
itself. That is also truer to a nib, which sheds where it changes pressure.

---

## 12. BUILD ORDER

Each phase independently shippable and revertible. Every phase gets shots —
this project's history says nothing here is findable by reading code.

| Phase | Change | Touches | Risk |
|---|---|---|---|
| **0a** | **Cap the victim's damage numeral** (§0) | `Card2D.take_damage:3244` | none — fixes a live bug |
| **0b** | **Give `Motion.burst` presets a `texture`.** Every particle in the game is an untextured square | `Motion.burst` / `BURST_PRESETS` | none — one funnel, ~40 sites |
| **1** | **Subtraction** — route regenerate/exhaust out; demote poison/wither to the chit. Draws nothing; predicted to beat Phase 2 on visible improvement | `_CALLOUT_STYLE`, `spawn_keyword_callout_kw` | one commit to revert; **needs a decision** |
| **2** | **`RubricStroke.gd`** + rewire `_apply_piercing_overflow`'s inline FX block; delete `_play_pierce_lance`; parent to `_board_container` | `_apply_piercing_overflow:4968`, `CombatNet:2096` mirror | contained |
| **3** | **The surround** — `ClashLaneFocus.focus_pair()` (~15 lines) + grade micro-drain on lethal. Pairs with the existing hitstop, which currently stops the world in full colour | `ClashLaneFocus`, `_grade_mat` | low |
| **4** | **Costumes** in payoff order: Shield, Last Stand (both reuse existing painters), Armored, Thorns, Guardian, Regenerate, Piercing. Each retires its callout as it lands | `_build_compact_layout`; one painter each | per-keyword |
| **5** | **Audio registers** (§11) | existing SFX plumbing | low |
| **6** | Flipbook bake for costume reactions, only if shots show the live painters stuttering | SubViewport bake at boot | — |
| **7** | The word, if still needed — deliberately last, because Phases 1–4 may make it unnecessary | | |

**Do NOT do the spotlight as a screen dim.** `ClashLaneFocus` already exists,
was raised 0.30 → 0.46 on 2026-07-28 for exactly this problem, and its comment
states why it draws ink slabs instead of tinting: *"Four slabs leave the active
column untouched instead of tinting the cards inside it."* There is now a second
reason — modulating a token fights the `flash_material` and `burn_material`
shaders living on that same CanvasItem. The increment is `focus_pair()`, keeping
two card rects lit inside the already-inked surround.

### Harness — `tools/_shot_rule_layer.tscn`

Two documented traps to pre-empt:
1. Force `reduce_motion = false` — this machine ships it ON.
2. Set `get_tree().current_scene = _combat`, or `Card2D._combat_vfx_target()`
   fails to resolve and **the shots render no damage numbers at all** (which
   `_shot_creature_fx` and `_shot_battle_log` never have — only
   `_probe_clash_trace` sets it).

Plus the §3 greyscale test at 1280×720 windowed, sampled separately for the
on-token segments and the gutter segment.

---

## 13.5 THE FOURTH REGISTER — REFUSAL (audit done, not built)

A follow-up audit of every gate that refuses a player action. The headline
correction to §2's guess: almost nothing resolves to the battle log. Instead
**~14 refusals share ONE channel — `Combat._show_info` — and that channel also
carries GOOD news** ("★ Mutator bonus: +25 gold" and "Not enough Command!" are
the same object, same colour, same place, same duration). There is no refusal
register because there is no refusal *channel*, only a narration slot that
refusals borrow. A further ~9 refusals have no channel at all, and 3 have one
that states the opposite of the truth.

**The register, if built: THE CLERK'S HATCH.** A bounded field of regular
parallel ruling — cold, dry, bone, laid with a straightedge, against STRIKE's
warm wet vermilion laid by hand. Distinguishable from strike/stamp/margin with
all hue removed (one long stroke / one compact press / n discrete pips / a ruled
field). **This is not an invention — the project already built it, named it,
survived a revert with it, and scoped it to exactly one rule:** `ClosedGround`,
whose own comment records that v1 was a near-black ellipse that read as a *hole*,
and whose colour-blind argument is "the read is TEXTURE and EDGE, never hue."
Bone is likewise already the house colour for this meaning — `Card2D`'s
`mustering` rail entry picks it deliberately, "cold bone — a body waiting, not a
body harmed."

**Preventive, not reactive, and the argument is decisive:** the most
bug-suspicious refusals *have no click to attach to*. The muster delay and the
Swift-face rule are not "you may not press that" but "the thing you already did
will not do what you expect." There is nothing to react to. *A refusal you see
before you act is a rule you learned; a refusal you see after is an error
message. This build has fourteen error messages and one rule.*

**Named revert risk: a full-token hatch flash.** A 200×150 token is 30,000px² —
**12× the entire overkill stroke, 40× the reverted seal crack** — landing on the
art the player uses to identify the creature, and invisible to the harness for
the same reason the ivory-core narrowing was. The hatch may occupy the scrim
window, the cost seal, or the ground; **never** a full-area flash over art.

### Verified bugs found during that audit (all independent of any visual work)

1. **The forecast promises face damage the Rush rule refuses — and the lunge
   plays anyway.** `_forecast_column_strike` has no Rush guard, so a Swift body
   played into an empty column forecasts "FOE HP −4 · 26 LEFT"; `_creature_hits_face`
   then returns 0. Worse, `_resolve_swift_attack` plays `play_attack_lunge()` and
   awaits `LUNGE_APEX` *before* calling the guard — so the creature performs a
   full attack animation into an empty lane and deals nothing, after the UI
   promised a number. `_creature_hits_face`'s own comment says it returns early
   "so it reads as *held the line*, not a phantom swing"; the caller defeats it.
   The refusal voice already exists in that layer (`_predict_lane_strike`'s
   "BLOCKED — NO STRIKE") and has exactly one user.
2. **The Trebuchet cannot be targeted by the spells meant to break it.** It ships
   `attackable: true` with `passive_desc` "Break the Trebuchet to stop it", and
   `_target_contract_available` / `_clicked_target_from` both filter on the new
   `is_inert_structure()` — but `_try_resolve_target`'s main single-target scan
   still filters the raw `has_keyword("structure")`. So potions break it and
   spells silently decline, and if it is the only enemy standing the player
   enters targeting mode with nothing clickable.
3. **The gold drop-highlight draws ON TOP of the `ClosedGround` hatch.**
   `_make_lane_slot` adds `ClosedGround` before the `Highlight` ColorRect, and
   `_nearest_player_slot` filters neither closed nor occupied slots — so a drag
   over closed ground lights it as a valid drop target and then refuses. The one
   refusal the project got right is being overwritten by the drag code it was
   built to explain.

Also worth its own line: **the muster delay — the newest, most counterintuitive,
highest-frequency rule in the game — is written down in NONE of the three places
the game explains itself** (`HOW_TO_PLAY_PRIMER`, `MECHANICS_HELP`, and
`_maybe_show_combat_model_tutorial`, the last of which fires on the player's
first ever End Turn, the exact moment the rule bites). Adding it there is pure
copy and is the highest value-per-line change in this document.

---

## 14. UNRELATED REGRESSION FOUND

`project.godot:56` in the working tree has
**FIXED 2026-07-28:** `AudioBank.play_sfx("error")` at the discard-cap refusal
was the ONLY sound any refusal in the game played, and it had neither an
`assets/audio/sfx/error/` dir nor an `SFX_FALLBACKS` alias — so it was silent,
and `tools/_probe_audio_cues.gd` was **failing on this branch**. Renamed to
`"refused"` with a `button_click` stand-in until a real dry scrape lands.

**STILL OPEN:** `project.godot:56` in the working tree has
`textures/canvas_textures/default_texture_filter=2` (was **3**). Value 2 is the
documented cause of the 2026-06-25 "why is the game suddenly pixelly?" bug —
invisible windowed at 1600×900, visible only in fullscreen where `canvas_items`
upscales. Several techniques here assume linear filtering. **Revert before
committing.**

---

Related: [[project_animation_cool_pitch_20260717]] (the material thesis and the
visibility rule), [[project_creature_fx_pass_20260717]] (the contrast rule and
the funnel-per-channel pattern this layer should mirror),
[[project_blocker_economy_20260728]] (the overkill rule itself),
`docs/ANIMATION_AUDIT_20260716.md`.
