# What would make the game look cooler — a hunt (2026-08-04)

Game-wide, minus one gesture: the card play was overhauled and separately hunted
the day before ([`CARD_PLAY_COOL_HUNT_20260803.md`](CARD_PLAY_COOL_HUNT_20260803.md)),
so hand → drag → drop → press is out of scope here. Everything else is in: the
clash, the enemy, the chart, the shell, the bookends.

Written in the register of, and answerable to,
[`ANIMATION_COOL_PITCH_20260717.md`](ANIMATION_COOL_PITCH_20260717.md) — its §1
thesis (*obey the material*) and the two rules its reverts bought:

> **★3 (SIZE).** An effect lands only where its material is visible at the size
> it is drawn. 38 px seal − 18 px numeral ≈ 8 px of wax. *Do the arithmetic
> before the painter.*
>
> **★4 (SUBSTANCE).** A battlefield token is full-bleed ART. Size was fine
> (200×150); there was no parchment on it to stain.

Every item below states its pixels, measured from the real layout constants, and
names the material it lands on. Items numbered **✱** so they never collide with
the pitch's ★ slate or the card hunt's ✦.

Everything here was found in a screenshot of the running game or in an
arithmetic check against shipped constants. Frames shot for this pass:
`_shot_shell_screens` (8), `_shot_combat_hud` (4), `_shot_killing_blow` (3),
`_shot_map_states` (6).

---

## 1. Thesis: the animation layer is saturated. The RECORD layer is empty.

Three prior passes closed the beat map, and they closed it well. Death burns.
The portrait chars. The killing blow drains the world. The General's army
presents. The deck peels a leaf off a stack of sealed dispatches. The march
walks the road. Deaths already leave scars on the table for the rest of the
fight; kills already scratch tallies down a card's left margin. **Asking "what
beat is missing" is the wrong question now — the honest answer is almost none.**

What this game has instead is a different, larger hole, and it is visible in one
comparison. Put the two run-end frames side by side:

| | what it is | verdict |
|---|---|---|
| `_shell_gameover.png` | a deckled parchment sheet, ruled ledger bands, a crimson wax seal pressed at the corner bearing **MARCH XXIV** in Roman numerals | the best still frame in the build |
| `_shot_killblow_victory_stamp.png` | the word VICTORY in 92 px gold, a 32 px gold number, and a chamfered info plaque, floating over a board that was just swept blank | the most-repeated ceremony in the game |

Both are "the fight is over." One is a **document that got sealed**. The other is
a **label**. And the second happens ~21 times per run against the first's once.

That is the pattern everywhere I looked. This game is a *record* — writs, a
chart, a chronicle, sealed orders and broken ones — and it is superb at
rendering a record's *objects*. What it almost never does is let the record
**change**. Specifically:

- The isle is called *The Burning Isle*. The chart for Act III is
  indistinguishable from Act I (§✱2 — with the arithmetic showing why it must
  be).
- Three provinces are claimed and the sheet says so in a text line. The
  claimed-site glow moves the paper by **3 parts in 255** (§B3).
- The foe's law is posted on a plaque all fight, and when his army is broken it
  is still posted (§✱1, §B1).
- The page chars away on every scene exit and the next page opens with no
  entrance at all in Combat, Event, Collection and MainMenu (§✱3, §B2).

| Generic today | What the material says it should be |
|---|---|
| The fight ends and the foe's standing EDICT is still in force under the word VICTORY | the chronicler **strikes the line out** — the painter is written, named `RubricStroke`, and already preloaded in Combat.gd |
| The chart is byte-identical in tone from Act I to Act III | the war **eats the map** — which is exactly what the copy of the chart on the war table already does |
| A claimed province is an amber disc at α 0.055 | the site is **struck and held**; ink goes down and stays down |
| The world chars away, then the next scene is simply there | the ink **recedes off the new page** — same shader, run backwards |
| The relic cache is a dialog box on a painted forest | the road's stops all have **props**; there are 30 painters in the kit and this stop uses none |

**The pitch: stop adding beats. Start letting the document accumulate.** A beat
is over in 300 ms; a mark is on the page for the rest of the run, and it is what
a player screenshots.

---

## 2. The slate, ranked by (material truth × screen time) ÷ cost

### ✱1 — The foe's law outlives his army

**Generic today.** `_show_battle_verdict(true)` puts a 92 px gilt word at
`(vp.x·0.5, vp.y·0.36)`, a 32 px counting gold numeral 62 px under it, and a
chamfered detail plaque 126 px under that. Two oval `_spawn_vfx_ring`s and a
`spawn_spell_burst` fire at +0.18. That is the whole ceremony, and it is text.

Meanwhile `_dim_war_furniture()` — the ★13 sweep, written specifically so the
climax does not play over stale promises — fades the INCOMING chip, the wave
chip, the reserves chip, the End Turn button, every intent chevron and every
lane danger sigil. It does **not** touch `_passive_banner`. So the one piece of
war furniture that survives the sweep is **the enemy's standing law**, sitting
dead centre under the title, still declaring what happens "when one of your
creatures dies" to an army that no longer exists. ★13 swept six stale forecasts
and left the loudest one standing (§B1).

**What the material says.** The plaque is not a HUD widget in this fiction — it
is *the foe's law, posted*. The build already speaks this language fluently on
the piles: the draw pile wears a real `Card2D.WaxSeal` ("your orders, still
sealed") and the discard wears `SpentDispatch` ("the deck's seal BROKEN in two
over a crack of paper"). Orders here are sealed dispatches, and a spent one is
visibly spent.

And the mark for a struck line is *already written*.
`scripts/ui/painters/RubricStroke.gd`, first line of its own docstring:

> THE RUBRIC — the mark a chronicler makes when a line of the record is struck out.

It is used today only for overkill's exit wound. Its literal stated meaning has
never been used for its literal case.

**The arithmetic (this is the ★3 test, and it passes by 32×).** From
`Combat._build_hud`'s plaque build and `_apply_standing_rule`:

| | value | source |
|---|---|---|
| rule label font | 18 pt (the reading floor) | `_make_text_label("", 18, …)` |
| label measure | `min(rule_w + 2, 620)` px | `_apply_standing_rule` |
| plaque content margins | L 12 · R 12 · T 4 · B 5 | `threat_bg.content_margin_*` |
| **plaque width, max** | **644 px** | 620 + 24 |
| plaque height, 1 line | ≈ 33 px | 18 pt line box + 9 |
| plaque height, 2 lines | ≈ 57 px | measured in `_combat_hud_r2.png` |

A stroke run across 644 px is **32× the project's own ~20 px mush floor** and
**74× ★3's dead 8.7 px annulus**. There is no size question here at all.

**Material verdict: the strongest item on this page.** ★4's test is the one that
matters and it passes cleanly: the plaque is `Color(0.10, 0.062, 0.046, 0.92)` —
a flat dark ink board with an oxblood keyline and high-contrast ivory type. It is
the *opposite* of the full-bleed painting that killed the ink spatter: a uniform
dark field whose entire job is carrying written words. And RubricStroke is
already built three-banded (iron-gall knockout / vermilion body / gilt core)
precisely so it reads on dark wood *and* on light parchment — the house
contrast rule, already solved in the painter.

**Coverage, measured.** `EncounterDB` carries **98 non-empty `passive_desc`
entries against 7 empty** — the plaque is posted in ~93 % of fights. It is not a
boss-only flourish.

**Where it hooks.**
- `Combat._dim_war_furniture()` — the existing GAME_OVER funnel; add the plaque
  to it, and branch on the verdict rather than fading it flat.
- `Combat._passive_banner` / `_passive_rule_label` — the node; `_apply_standing_rule`
  is documented as the ONE writer, so the stroke must not touch text or measure.
- `Combat.RubricStroke` — already `preload`ed at `Combat.gd:31`.
- `Combat._show_battle_verdict(won)` — the beat's owner; the stroke should land
  ~0.10 s *before* the word so the law is broken and *then* named.

**The asymmetry is free and correct.** On DEFEAT the edict is not struck. The
law stood. Nothing to build — just don't fire it in that branch.

**Cost.** Small. One call in an existing funnel, one stroke node, one delay.
No new painter, no shader, no new state.

**Verify.** `tools/_shot_killing_blow.tscn` already shoots the stamp frame — add
one frame at stamp − 0.10 s (the stroke landing) and one defeat frame proving
the law survives. This item was found *in that harness's own output*, which is
the third time ★13's lesson has repeated: budget the shot before the build.

---

### ✱2 — The isle never burns, and the numbers say it can't

**Generic today.** `MapTerrain._assign_moisture_biomes`:

```
var scorch_r: float = [0.0, 175.0, 205.0, 235.0][_act]
var scorched := _seed_pts[i2].distance_to(_etna_peak) < scorch_r
```

A scorched cell then lerps the parchment 34 % toward `Color(0.340, 0.235, 0.165)`
— the strongest biome tint in the file (forest 16 %, rock 16 %, hills 10 %). The
system is real and the tint is strong. The *placement* is the problem.

**The arithmetic.** War-table mode, plate = the 1600×900 canvas rect
(`_plate_item.size = size`, full-rect):

| | position | source |
|---|---|---|
| Etna | `(0.905w, 0.315h)` = **(1448.0, 283.5)** | `MapTerrain.gd:913` |
| keep | `(0.80w, 0.535h)` = **(1280.0, 481.5)** | `MapTerrain.gd:907` |
| camp | `(0.075w, 0.535h)` = (120.0, 481.5) | `MapTerrain.gd:906` |
| lane pitch | `0.100h` = 90 px | `MapTerrain.gd:914` |

**|Etna − keep| = √(168² + 198²) = 259.7 px.**
**Act III's scorch radius is 235 px.**

> **In the last act of the campaign, the burn stops 24.7 px short of the gate the
> whole act is marching to.**

It is worse than that for the road itself. The march corridor is the band around
`cy = 481.5`, `x ∈ [272, 1280]`; its nearest point to Etna *is* the keep, so no
point on the spine is inside the scorch in any act. The nearest off-spine stop is
a top-lane site in the last plain rows — row 16 lands at `x = 272 + (16/17)·1008
= 1220.6`; at col 0 (`y = 211.5`) that is **238.5 px** from Etna, at col 1
(`y = 301.5`) **251.8 px**. Both outside 235.

**Nothing the player ever marches through is scorched, in any act.** The
campaign's stated visual arc — the isle burning outward from the mountain — plays
out entirely in a wedge of coast past the keep that the road never enters, and
grows there from r 175 → 235 (+34 % radius) across three acts. That is why
`_shot_a1_full.png` and `_shot_a3_full.png` are, at a glance, the same picture.

Two more things suppress what little is there, both on exactly the cells the eye
lands on. In `_paint_simple_backdrop`, immediately after the biome tint:

```
if _road_d[i2] < 110.0:                 # settled road-country
    col = col.lerp(Color(0.790, 0.690, 0.500), (1.0 - _road_d[i2]/110.0) * 0.30)
...
var lift2 := (1.0 - smoothstep(0.0, 0.50, d2)) * 0.15   # the lamplight pool
```

Up to 30 % toward pale packed earth within 110 px of the road, plus up to 15 %
toward `(1.0, 0.94, 0.74)` in the lamplight pool. Both *partially undo* the burn
on the corridor — which would be fine if the burn ever reached the corridor.

**The build already knows the right answer, one file over.** `TablePlate` — the
copy of this same chart inked onto the war table Combat is fought on — burns by
act: `for i in range(7 + act * 3)` → **10 blots at Act I, 16 at Act III**,
scattered along the clash band and the sheet edges, at α 0.09–0.20 near-black.
*The reproduction burns and the original does not.*

**Material verdict: yes, and it is the item with the most to gain.** No ★3
question (this is a full-plate wash), no ★4 question (parchment is the one
substrate in the game that *is* built to take a stain — `ParchmentPlate`'s
foxing, the sheet's own age-stains, `_draw_scar`'s ash all rely on it). It is
also the game's title rendered on the game's second-most-viewed screen.

**Where it hooks.**
- `MapTerrain._assign_moisture_biomes` — the radius table. The honest fix is not
  a bigger disc: it is to make the burn follow **the road already walked**, which
  the plate already computes as `_road_d[i2]`. The war eats the map along the
  march, not out of a corner.
- `MapTerrain._paint_simple_backdrop` — the biome tint arm and the two lifts
  above; scorched cells must be exempted from the road-country lift or the two
  cancel.
- `MapTerrain._draw_etna` — the ash skirt (`7 × α 0.032` discs at r 86 → 22) is
  the existing idiom to grow.
- `RunState` already carries everything the burn could key off:
  `holds_broken_in_act`, `generals_broken_run`, `current_act_idx`, and per-node
  `visited`.

**The bigger prize, stated but not costed here.** The scorch is currently a
*state* baked at act generation — the player never watches anything burn.
`MapPulseOverlay` is a live layer over a frozen plate and already owns
`play_frontier_reveal`, `march_along` and an arrival ring; a "the ground you took
is now scorched country" beat on the return from a won fight would be the first
time the chart ever *records* in front of the player. That is a second item, not
this one.

**Cost.** Medium. The radius/keying change is small; the tint-vs-lift interaction
and the burn's shape need a photograph, not a commit.

**Verify.** `tools/_shot_map_states.tscn` already renders `a1_full` / `a2_full` /
`a3_full`. The gate is trivially statable and currently fails: **an Act III frame
must be distinguishable from an Act I frame by someone who is not told which is
which.** (Fix the harness's stale zoom first — see §B5.)

---

### ✱3 — The page turns out, and the next page is simply there

**Generic today, and this is the highest screen-time item on the page.**

`GameTheme.fade_out_then_change_scene` is the signature transition and it is
genuinely good: a near-black **sepia** `ColorRect(0.043, 0.031, 0.024)` under a
three-octave noise shader, ink pouring from an origin the caller can aim (MapView
passes the committed site's own screen position), with a thin charring ember rim
at the frontier. **53 call sites.**

`GameTheme.fade_in` is:

```
overlay.color = Color(0, 0, 0, 1)
tw.tween_property(overlay, "color:a", 0.0, duration)
```

A pure-black alpha fade. **9 call sites.**

Two separate defects fall out of that pair, both certain from control flow:

**(a) The colour steps at the seam.** The exit ends on `#0B0806`; the entrance
starts on `#000000`. Every scene change in the game goes ink-sepia → *pure
black* → up. Δ = **(+11, +8, +6) of 255**. Small, and it is the exact kind of
step the eye reads as a frame glitch rather than as a page turning.

**(b) 44 of 53 transitions have no entrance at all.** The nine `fade_in` callers
are Credits, GameOver, MapView, Recruit, Rest, Reward, Shop, Treasure, Wayside.
The scenes with **zero**:

| scene | entries per run (approx) |
|---|---|
| **Combat** | ~21 |
| **Event** | ~18 |
| Collection | on demand |
| MainMenu | the game's first frame |

So the single most common transition in the game — map → fight — reads: the
standard marches to the site, ink pours in from that exact point and chars the
world away over 0.34 s… and then Combat is **just there, at full brightness,
mid-build.**

That last clause is the part that makes this more than tidiness. `Combat._ready`
is *deliberately* interleaved (`_build_board` → ambient/grade → `await _build_hud`
→ `_init_decks`), with frames handed back between stages, because as one block it
was ~340 ms in which not one frame rendered. The interleave is correct. But it
means **the player watches the arena assemble in stages, against no cover** —
and the cover was dropped one frame earlier, on purpose, by a function that only
nine scenes call.

**What the material says.** The wipe's own comment says it: *"the world chars
away, then the next page opens."* Half of that sentence is unimplemented. Ink
does not vanish; it recedes, or it dries. The entrance is the same shader run
from 1 → 0, from the same origin, in the same sepia.

**The arithmetic.** Full-screen, 1600×900 canvas. No size question exists. The
one number that matters is latency, and it is **zero**: the overlay is
`MOUSE_FILTER_IGNORE` today and must stay so, so a fast player loses nothing, and
the ~340 ms of staged build is *already happening* — a 0.30 s recede is free
cover over work in flight, not added time. `tools/_probe_coldentry.gd`
(`--mode=viamap`) measures time-to-playable and per-frame gaps and would be
unchanged; that is the gate.

**Material verdict: yes — highest screen time in the document, and the cheapest
real item on it.** It is also the one place where a purely cosmetic change
improves a *measured* problem (the visible staged build) without touching the
code that causes it.

**Where it hooks.** `GameTheme.fade_in` (the shader + sepia + `progress` 1→0),
`GameTheme.fade_out_then_change_scene` (stash the origin it used so the entrance
can recede toward the same corner — one autoload field, cleared on read), and
four `_ready` bodies that must start calling it: `Combat`, `Event`, `Collection`,
`MainMenu`.

**The one thing to get right.** Combat's entrance must not gate on the build
finishing, or it becomes a load screen. Fire it in `_ready` before the first
build stage and let it run on wall time; if the build is slower than the recede
on a cold cache, the player sees the last stage land — which is still strictly
better than seeing all of them.

**Cost.** Small. One rewritten function, one stashed Vector2, four call sites.

**Verify.** `tools/_shot_inkwipe.tscn` already freezes the wipe at progress 0.25 /
0.55 / 0.85 over the menu — point it at the recede as well, and add a Combat
entrance frame at ~40 % (the board visible through thinning ink). Re-run
`_probe_coldentry --mode=viamap` and assert time-to-playable is unmoved.

---

### ✱4 — The relic cache has no cache

**Generic today.** `Treasure.gd` is 348 lines and `_shell_treasure.png` shows why
that is the finding rather than the excuse: a 1600×900 screen holding a title, a
one-line caption, a ruled subheader, **one 340 px tile**, an "— or —", and a text
link. Roughly 88 % of the frame is unlit painted forest.

**What the material says.** Every other decision on this road is staged as an
object. The event pool alone ships ~30 physical painters — `CastPatch`,
`EventHelm`, `PaySack`, `CoinProp`, `StrongboxDial`, `BalanceScale`,
`MerelsBoard`, `TallySlate` — and the same pass wrote **`StageTable.gd`, the
shared piece of camp-table wood every minigame was supposed to be played on**.
That file is dead code (§B4).

A Relic Cache is, by its own name, a **thing dug out of the ground**. The road's
one stop whose entire noun is a physical object renders it as a dialog. And the
strongbox that would carry it is already drawn, in `StrongboxDial`, for an event
that literally pays the Fourth Legion what the King never did.

**The arithmetic.** The tile is `SPOIL_TILE_W = 340` wide carrying a
`SPOIL_ICON_PX = 160` chip. A prop staged at the same scale gets 300–500 px of
canvas — 15–25× the mush floor, in the same band the event props already prove
readable (`CastPatch` runs 540×360). No ★3 question.

**Material verdict: yes, but it is a screen-time item ranked honestly.** Treasure
is entered ~2–3× per run against Combat's ~21. It is here because the cost is
low, the material claim is unambiguous, and the props are *already written and
already gated by `_shot_event_pass`*.

**Where it hooks.** `Treasure._build_ui` (the outer VBox), reusing
`scripts/ui/painters/` rather than adding one. `Treasure._pick_relic` /
`_leave` are the two outcomes — the lid opens on one, the gold is counted out on
the other.

**Cost.** Medium — it is a staging job, not a mechanism. Do not build a new
painter for it; if the existing kit cannot dress it, that is the answer.

**Verify.** A new `_shot_treasure` pair (cache closed / claimed) or two frames
appended to `_shot_shell_screens`.

---

### ✱5 — Every claimed province is invisible (see §B3 for the numbers)

Listed here as well as in the bug section because the fix is a flourish, not just
a correction. `_draw_claimed_glow` composites amber onto parchment at a delta of
**3 parts in 255**; on the chart, three claimed provinces and thirty look the
same.

**What the material says.** A chart records a claim by being **marked** — a
struck site, a re-inked road, a bivouac chit, a province tinted to the company's
dye. Two of those exist already and are nearly invisible; the third
(`_draw_claimed_bivouac`) reads as a small dark chit at map scale; the fourth
(political dyes) exists only behind `SIMPLE_BACKDROP = false`, i.e. in the
renderer the game does not ship.

**Material verdict: yes, and it is the cheapest way to make the chart accumulate
without touching ✱2's biome system.** These are the same claim from two
directions — the burn is what the *war* did to the land, the claim marks are what
*you* did. ✱2 is the better story; this is the cheaper half.

**Where it hooks.** `MapTerrain._draw_claimed_glow` (alpha and colour — it needs a
value change, not just an alpha bump: at α 0.055 an amber that is already close
to the parchment's own hue cannot separate at any alpha that stays subtle), and
`_draw_sites` / `_draw_claimed_bivouac` for the token treatment.

**Cost.** Trivial to correct, small to make good.

**Verify.** `_shot_map_states`' `a1_mid` frame, which is exactly the mid-run
state this governs — it currently shows three claimed sites and no evidence.

---

## 3. Order, and what depends on what

```
✱3 the ink recedes    — independent; fixes a defect; the cheapest real item
✱1 the law is struck  — independent; needs the ★13 sweep extended first (B1)
✱4 the claimed marks  — independent; the cheap half of ✱2's story
✱2 the isle burns     — independent; needs a photograph, not a commit
✱5 the cache          — independent; a staging job on an existing painter kit
```

**Suggested:** ✱3 (fixes two defects, largest screen time, smallest diff) → ✱1
(the real item) → §B3/✱4 (a correction that pays like a feature) → ✱2 (budget a
shot session) → ✱5 last.

Note the shape: **not one of these adds a particle, a ring, a shake or a
banner.** The pitch's §4 verdict stands verbatim — *"adding volume to generic
effects makes them more generic, not cooler."* ✱1 and ✱4 *replace* wrong
behaviour, ✱3 *implements the missing half* of an existing device, ✱2 *relocates*
a system that already works.

---

## 4. REJECTED — and why, which is the point of writing them down

### R1 — Anything drawn inside a relic chip
The tempting version: the relic chip cracks / wears / tarnishes as the run goes
on. `make_relic_chip` is called at **40 px** (combat HUD rail), **46–58 px**
(GameOver ledger, sized by hoard) and **160 px** (Reward/Treasure spoil tiles),
and the icon fills it edge to edge behind a `rim` of 2–3 px and a
`radius = size × 0.14` frame. At the two sizes that appear most, the whole
available margin is **2–3 px of rim** — a quarter of ★3's dead 8.7 px annulus.
Only the 160 px spoil tile has room, and a mark that exists only on the screen
where you *acquire* the relic is not a wear mark. **Rejected on ★3, with room to
spare in the wrong direction.**

### R2 — Re-materialising the shell's tiles as parchment
I very nearly pitched this off the Reward/Treasure frames ("these read as UI
cards, not documents"). It is wrong twice. First, `make_panel_style` does not
return a `StyleBoxFlat` — it returns `ChartPanelStyle` with a **chamfer**
(`7.0 + corner × 1.5`) and corner tacks, so the shell is already cut-corner chart
furniture, not a rounded-rect UI. Second, the contrast is *load-bearing*: on the
Shop frame the cards for sale are parchment writs and the relics are dark
plaques, and that is how you tell at a glance which is which. Making them the
same material would cost information to buy consistency. **Rejected on both
counts.**

### R3 — A fire/ember emitter over the Rest screen's painted campfire
The Rest art is a painted night camp whose brightest object is a fire. Adding
particles over it is the archetypal generic-juice move, and it fails ★4 in the
ink-spatter direction: the painting already contains the fire at full baked
contrast, so any emitter either disappears into it or fights it. (The screen does
already carry ambient motes.) **Rejected.**

### R4 — Making the combat board's inked chart louder
`TablePlate` draws its coast, march routes, site rings, compass and cup stains at
α **0.055–0.16**, which is why the board reads as flat brown in a still. Raising
it is exactly the mistake `CastPatch`'s own law names — *the table stays quieter
than the props* — and the board is where 8 full-bleed painted tokens have to be
legible at once. The board is also not unlit: `_fld_stage_glow` (additive radial
pool) and `_fld_edge_feather` (top/bottom falloff at α 0.72) are both already
there. **Rejected; I had this on the list until I read the ground builder.**

### R5 — An "ACT II" title card on the map
The act announcement already happens, one screen earlier and better: Reward's
boss branch prints `THE SECOND MARCH / KEEP TAKEN` and renders `ActVictoryStrip`,
which inks the conquered route from camp to the lord's seal. A second
announcement on the map would restate it 400 ms later. **Rejected — and this is
the display-path lesson repeating for the eighth time in this doc series: check
the neighbouring screen before calling a moment missing.**

### R6 — More on the verdict beyond ✱1
The verdict already fires a scrim, an oversized stamp with a BACK-out strike, a
spell burst, two oval rings, a shake, a counting gold figure, a detail plaque, a
full-frame desaturation drain, a music duck, a board push-in and the killer held
at full extension. ✱1 is not an addition to that list — it **strikes out an
element that is already on screen and should not be**. Nothing else belongs here.

---

## 5. Bugs found, not missing flourishes

**B1 ▲ The enemy's standing law survives its army.** `_dim_war_furniture()` was
written for exactly this class of defect and sweeps six things at GAME_OVER
(`_incoming_dmg_chip`, `_wave_chip`, `_reserves_chip`, `_end_turn_btn`, intent
metas + threat flags, `_clear_lane_forecast()`). `_passive_banner` is not among
them, so the foe's rule — the largest text object on the board, dead centre — is
still posted under the verdict in the ~93 % of fights that post one. Certain from
control flow; visible in `_shot_killblow_victory_stamp.png`. Fixed by ✱1, which
is why ✱1 ranks first.

**B2 ▲ The scene transition is half a transition, and the two halves are
different colours.** `fade_out_then_change_scene` (53 sites) chars away to sepia
`#0B0806` behind a noise shader; `fade_in` (9 sites) is a plain alpha fade from
pure `#000000`. **Combat, Event, Collection and MainMenu call neither** — they
have no entrance at all, so 44 of 53 transitions end on ink and then hard-cut to
a fully lit scene. In Combat's case that cut lands on a *deliberately staged*
`_ready`, so the player watches the arena build. See ✱3.

**B3 ▲ The claimed-province glow is arithmetically invisible.**
`MapTerrain._draw_claimed_glow` draws `PLAYER_AMBER = (0.85, 0.64, 0.26)` at
α 0.055 (r 36) and α 0.045 (r 64) over `land = (0.752, 0.642, 0.452)`. Composited:

| | ΔR | ΔG | ΔB | of 255 |
|---|---|---|---|---|
| inner disc alone | +0.0054 | −0.0001 | −0.0106 | **(+1, 0, −3)** |
| both, at the centre (α_eff 0.098) | +0.0096 | −0.0002 | −0.0188 | **(+2, 0, −5)** |

Amber over warm parchment is nearly hue-neutral, so almost all of the (already
negligible) delta lands in blue. And the whole thing is drawn *under* the live
`blend_mul` paper-fibre pass and the screen-fixed vignette. Sub-JND on any
display. Confirmed by eye in `_shot_a1_mid.png`, which shows three claimed sites
and no glow. **This needs a value change, not an alpha bump.**

**B4 ● `scripts/ui/painters/StageTable.gd` is dead code.** Zero references
anywhere in `scripts/` or `tools/`. Its own docstring says *"Games add it FIRST
(via `Event._stage_table`) so every patch, prop and caption draws over it"* —
`Event._stage_table` does not exist, and all sixteen `CastPatch.new()` sites in
Event.gd add the patch straight to the root. It landed in the `c70109e`
working-tree checkpoint and was never wired. Either wire it (it is the material
link between the event stage, the war table and the chart) or delete it; leaving
a 100-line painter whose comment describes behaviour the game does not have is
how the next hunt loses an afternoon. *Same class as the `InkSpatter.gd.uid` /
`SealCrack.gd.uid` orphans the card hunt logged as B5.*

**B5 ○ The map shot harness gates a state the game no longer opens in.**
`tools/_shot_map_states.gd:31` shoots the "open" frame at
`_set_view(1.15, …)`. `MapView._ready` opens at **1.10**, and the comment right
above it (`MapView.gd:99–105`) records that *"the next pick, 1.15, clipped the
keep plaque mid-word at the east screen edge whenever the pan clamped west."*
`_shot_a1_open.png` shows exactly that: **THE PASS GATE / THE PYROMANC**, cut off.
The harness is photographing the rejected zoom. Harmless to the game, corrosive
to the method — this project's whole verification story is that the shot is the
one tool that finds real defects, and a stale shot quietly stops being evidence.
One-line fix.

---

## 6. Already built — the list that saves the next hunt

Everything below I had on a candidate list and struck after reading the display
path. This is the eighth consecutive pass in which that step killed more items
than it kept; assume it will again.

| Nearly pitched | Where it already lives |
|---|---|
| "Screen headlines should be letterpressed, not faded in" | `GameTheme.make_screen_title` calls `Motion.stamp_in` on the word — **every** screen title in the game already presses, with an ink bloom |
| "The shell is a rounded-rect UI" | `make_panel_style` returns `ChartPanelStyle` — chamfered, corner-tacked chart furniture |
| "The war table is flat and unlit" | `_fld_stage_glow` (additive radial pool) + `_fld_edge_feather` (α 0.72 top/bottom falloff) + wood grain + paper fibre + `TablePlate`'s inked chart |
| "Deaths should leave something on the table" | `LaneAftermath._draw_scar` — ash stain + snapped gear, seeded, capped at `MAX_BATTLEFIELD_SCARS`, held for the whole fight |
| "A veteran card should show its service" | `TallyMarks`, scratched down the writ's left margin, from `card_data.veteran_kills` |
| "The deck should read as a stack of orders" | draw pile wears a real `Card2D.WaxSeal`; discard wears `SpentDispatch` (a seal broken in two over a crack of paper); ★10 peels a leaf off it on every draw |
| "The combat table should burn as the campaign deepens" | `TablePlate`: `range(7 + act * 3)` — 10 blots at Act I, 16 at Act III |
| "There should be an act-transition ceremony" | Reward's boss branch: `THE Nth MARCH / KEEP TAKEN` + `ActVictoryStrip` inking the conquered route |
| "The hero portraits never react" | ★7 `_refresh_portrait_char` — both portraits scorch off the HP ratio, driven from `_update_hud` |
| "The fight's end has no weight" | ★8 `_play_killing_blow_moment` — desaturation drain, board push-in 1.015, music duck, killer held at full extension |
| "A General's arrival is just a banner" | ★9 — breath (u_sat 0.72), the name stamps at 1.42×, then `_play_army_rollcall` seats the lord last with dust and a deep thud |
| "Nothing marches on the map" | ★12 `MapPulseOverlay.march_along` — footfall dust, commit ripple, arrival ring, Reduce Motion snap |
| "The verdict plays over stale forecasts" | ★13 `_dim_war_furniture` — six of the seven, see B1 for the seventh |

---

## 7. Verification

Every item names its harness above. The standing gates this pass would touch:

| item | harness | assertion |
|---|---|---|
| ✱1 | `_shot_killing_blow.tscn` | +1 frame at stamp − 0.10 s (the stroke landing); +1 defeat frame proving the law survives |
| ✱2 | `_shot_map_states.tscn` | an Act III frame must be distinguishable from an Act I frame by someone not told which is which |
| ✱3 | `_shot_inkwipe.tscn` + `_probe_coldentry --mode=viamap` | the recede at 40 %; time-to-playable **unmoved** |
| ✱4 | new `_shot_treasure` pair, or +2 frames on `_shot_shell_screens` | — |
| ✱5 / B3 | `_shot_map_states.tscn` `a1_mid` | three claimed sites must be countable without the text line |
| B5 | `_shot_map_states.gd:31` | shoot 1.10, the zoom the game opens at |

Shot harnesses must force `UserSettings.reduce_motion = false` — this machine's
saved settings have it ON.

**The method note, restated because this pass is another argument for it:** the
arithmetic in §2 ruled ✱2 *in* by proving a system cannot work (235 < 259.7) and
ruled R1 *out* by proving a canvas is too small — but the reason I looked at
either was a screenshot. ✱1 came out of `_shot_killing_blow`'s own stamp frame,
the same way ★13 did. B3 came out of `_shot_a1_mid`. B5 came out of comparing a
shot to the comment above the code that made it. **Budget the shot before the
build.**
