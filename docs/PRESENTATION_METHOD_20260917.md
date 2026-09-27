# HOW TO PRESENT THE GAME — the evidence, the instrument, and RUN SETUP measured

**2026-09-17.** A research pass: what the design-science literature actually
supports about proportion, position and composition, an instrument that applies
it (`tools/measure_screen_aesthetics.py`), and the first screen put through it.

The short version, before any of the detail: **the composition of RUN SETUP
answers a different question than the screen asks.** The screen asks *which
hero?* The visual system answers *look at this painting, and at these ten cards
you did not choose.* That is not an opinion — 60.0% of the page's optical weight
is carried by two blocks that hold no decision, and the block that holds the
entire decision is the faintest thing on the page, fainter than the BACK button.

---

## §1 THE RESEARCH, AND WHAT SURVIVES CONTACT WITH EVIDENCE

### 1.1 The first impression is formed in 17ms and it does not get revisited

Tuch et al. (2012, *IJHCS*) showed 119 real screenshots at 50 / 500 / 1000ms and
found visual complexity and prototypicality already driving aesthetic ratings at
**50ms**; a second study shortened exposure to 17 / 33 / 50ms and the effect of
complexity **still held at 17ms**. Reinecke et al. (CHI 2013) took 548
participants over 450 sites and built computational models of complexity and
colourfulness that explain **roughly half the variance** in appeal ratings given
after 500ms of exposure.

Two consequences, and the second is the load-bearing one:

- The frame is judged before anything on it is read. Every detail pass is
  spending effort below the resolution at which the verdict was already reached.
- **Complexity is the punished direction, and it is asymmetric.** Reinecke found
  an inverted-U with strong linear tendency — simpler pages were only *slightly*
  less preferred, complex pages were heavily penalised. There is no symmetric
  risk here. Erring simple is nearly free; erring busy is not.

And the reason to care at all: the **aesthetic-usability effect** (Kurosu &
Kashimura 1995 over 26 ATM layouts, replicated by Tractinsky 1997 with tighter
controls and a *stronger* correlation) — perceived beauty predicts perceived
ease of use better than actual ease of use does. Composition is not decoration
on top of the design; it is the channel through which the design is judged.

### 1.2 Of the fourteen computable measures, TWO predict anything

Ngo, Teo & Byrne (2003, *Information Sciences*) give fourteen formulas —
balance, equilibrium, symmetry, sequence, cohesion, unity, proportion,
simplicity, density, regularity, economy, homogeneity, rhythm, order.

Do not implement fourteen. Altaboli & Lin (2011) ran the controlled experiment
on the three the model leans on and got: **balance p = .0009, unity p = .0001,
sequence only marginal at p = .100.** So the gate-worthy measure is BALANCE, and
the design-worthy principle beside it is UNITY (do elements look like they
belong to one page).

Balance is cheap to compute and has no taste in it, which is exactly why it is
worth having: it is the one composition property that can fail a build.

### 1.3 Proportion: the golden ratio is not supported — a closed ratio SET is

This matters because "use φ" is the single most repeated piece of layout advice
and the evidence for it is bad. Preference studies from Fechner onward are
equivocal; Stanford rectangle-preference work found no consistent φ preference;
Korean subjects preferred √2 (1:1.414), which is a straight contradiction of the
Western result. A 2024 review found no convincing evidence linking φ to
idealised proportion at all.

What *is* defensible is the shape of Ngo's PROPORTION measure: it does not
reward φ, it rewards being **close to any member of a small set** — 1:1, 1:√2
(1.414), 1:φ (1.618), 1:√3 (1.732), 1:2. The value is in the set being CLOSED
and reused, not in which ratio is in it. Same underlying claim as the 8pt
spacing grid that Material, iOS, Carbon, Fluent and Bootstrap all converged on:
consistency of interval is the thing doing the work, and any sane interval will
do.

**Practical rule for this codebase: pick a ratio set and a spacing step, and
never deviate. Do not chase φ.**

### 1.4 Attention: the centre gets the first look, MEANING gets every look after

Two separate findings that combine into one layout rule.

- **Central fixation bias.** When a screen appears, the first saccade goes to
  the middle of it more or less regardless of content, strongest on the earliest
  fixations and decaying to an asymptote only after 1000–2000ms. It persists
  irrespective of where the stimulus sits on the display.
- **Meaning beats salience.** Henderson & Hayes (*Nature Human Behaviour* 2017)
  built "meaning maps" directly comparable to saliency maps. Both predict
  attention — but when salience is statistically controlled, **meaning still
  accounts for significant variance; when meaning is controlled, salience adds
  nothing further.** This holds across tasks including aesthetic judgement.

So: a big bright decorative object buys you exactly one fixation, the centre of
the screen is where that fixation lands whether you planned it or not, and from
the second fixation onward the eye goes where the *significance* is. Salience
without meaning is a loan repaid within a second.

### 1.5 Decoration actively costs you; signalling actively pays — the strongest pair

This is the most directly applicable literature in the whole pass, and the two
halves point in opposite directions.

- **Coherence principle / seductive details.** Interesting-but-irrelevant
  material *reduces* comprehension. A 2020 meta-analysis in *Educational
  Psychology Review* found a significant seductive-detail effect: small-to-medium
  on retention and **medium on transfer** (transfer being "could you then act on
  it", which is precisely what a character-select screen is for). An EEG +
  eye-tracking study found task-irrelevant decorative pictures measurably raise
  cognitive load during text processing.
- **Signalling / cueing principle.** Cues that guide attention to the relevant
  element — highlighting, a rule, a plate, colour-coding, an arrow — pay:
  a meta-analysis of 103 studies (N = 12,201) reports **retention g+ = 0.53
  [0.42, 0.64]** and **transfer g+ = 0.33 [0.22, 0.43]**, with cognitive load
  significantly reduced.

**The rule: cut decoration that competes with the decision; add signal that
points at it.** Both moves are supported, and they are the same move.

Note the careful boundary: this does NOT say "remove the art". It says art that
competes for the same attention as the decision costs you. Art that *is* the
decision, or that sits where nothing is competing, does not.

### 1.6 Measure (line length)

Bringhurst's 45–75 characters per line for a single column, optimum around 66.
Baymard measured the failure mode directly: product copy wider than **80 CPL was
skipped 41% more often** than copy in the 60–70 band. Long lines do not read
badly — they do not get read.

### 1.7 Proximity dominates

Of the Gestalt grouping principles, proximity is the dominant one and can
override the others. Spacing is therefore not cosmetic: the gaps *are* the
information architecture, and a gap that contradicts the grouping will beat a
border, a colour or a heading that asserts it.

---

## §2 THE INSTRUMENT

`tools/measure_screen_aesthetics.py` (Python, no Godot needed — runs on any PNG
the `_shot_*` tools already produce).

```bash
python tools/measure_screen_aesthetics.py --sweep
python tools/measure_screen_aesthetics.py tools/screenshot/_runstart_setup_open.png --regions regions.json
```

It reports Ngo balance / equilibrium / homogeneity / density, edge density and
JPEG-75 size as visual complexity, Hasler & Süsstrunk M3 colourfulness, the
first-fixation patch weight, and — given a regions file — the **squint survival
ranking**, which is the one that names defects.

Two design decisions inside it worth keeping:

- **Optical weight is luminance above the page's OWN background floor** (35th
  percentile), never a flat threshold. These screens are painted; a flat
  threshold counts the wallpaper as ink and every measure downstream is wrong.
- **`--sweep` prints the shell median and says to judge against it, not against
  1.0.** An absolute balance target would fail the event screen, whose asymmetry
  is the design. The finding is always "this screen is an outlier among its own
  siblings", never "this screen is not perfectly symmetric".

---

## §3 RUN SETUP, MEASURED

Shot: `tools/screenshot/_runstart_setup_open.png`, 1920×1080.

### 3.1 The squint test — what the player sees in the first fixation

Mean optical weight after a 24× downsample, per region, ranked:

| rank | region | squint survival | share of page weight |
|---|---|---|---|
| 1 | **deck strip (10 art tiles)** | 0.1960 | **28.27%** |
| 2 | **hero portrait** | 0.1782 | **31.71%** |
| 3 | title "RUN SETUP" | 0.0985 | 1.05% |
| 4 | START RUN (primary action) | 0.0912 | 4.66% |
| 5 | BACK | 0.0601 | 0.17% |
| 6 | run controls (asc/daily/seed) | 0.0533 | 2.18% |
| 7 | roster "THE HEROES" | 0.0489 | 13.28% |
| 8 | **dossier (name + relic + how he fights)** | **0.0421** | 9.88% |
| 9 | deck strip caption | 0.0365 | 1.07% |

Read rows 1–2 against row 8. **The two heaviest objects on the page are the two
that carry no decision, and the block that carries the whole decision is the
faintest content on the page — below BACK, below the seed field.**

- Decoration (portrait + deck strip): **60.0%** of total optical weight.
- Decision (roster + dossier): **23.2%**.
- Primary action: **4.7%**.

### 3.2 Balance

```
Ngo balance, vertical axis : 0.633   (left 61.2% | right 38.8%)
quadrant TL/TR/BL/BR       : 32.5%  13.2%  28.7%  25.5%
```

The shell median is **0.878**. Only the event screen (0.362, asymmetric by
design — the art is one-sided on purpose) scores lower. The top-right quadrant
holds 13.2% against the top-left's 32.5%: the page is pictures on the left and
text on the right, and pictures weigh more.

### 3.3 Complexity

```
edge density : 9.90%    shell median 4.57%
density      : 26.65%
JPEG-75      : 216 KB
```

**RUN SETUP is the most visually complex screen in the shell — 2.2× the shell
median edge density, and the highest of the nine measured.** Per §1.1 that is
the punished direction, and it is the screen a returning player sees before
every single run.

### 3.4 Dead space

Largest empty rectangles, in shot pixels:

| rect | size | % of canvas |
|---|---|---|
| x 1440–1900, y 440–680 | 460×240 | **5.32%** |
| x 1260–1900, y 260–360 | 640×100 | 3.09% |
| x 1140–1900, y 140–220 | 760×80 | 2.93% |
| x 660–1920, y 820–860 | 1260×40 | 2.43% |

All four sit in the right column — under and beside the dossier. Per
[[reference_dead_space_vs_negative_space]] this is fault (1), a hole under the
content: the dossier stops two-fifths of the way down its column. The prose is
capped at `MUSTER_PROSE_W` 660 while the column is ~830 wide, so the emptiness
is inside the block, not margin around it.

### 3.5 Measure

The hero pitch is font size **16** in a **660px** box. Measured:

```
88 chars  "Relocate the line, turn fresh angles into Swift attacks, and strike harder once you have"
76 chars  "The first friendly you relocate each round gets +1 ATK and Swift this round."
```

88 CPL is past Bringhurst's 75 and past Baymard's 80-char skip threshold. The
longest run of type on the page is the one sentence that explains the hero.

### 3.6 The centre

Centre of mass sits at **x 0.455, y 0.560** of the canvas. The first-fixation
patch carries 2.00× the page's mean weight — but what is *at* (960, 540) is the
portrait's lower-right corner, roughly 28px inside its own frame: background
armour and skulls, not the face, and not the decision. The eye's guaranteed
first landing is spent on the least meaningful part of the heaviest object.

---

## §4 THE DIAGNOSIS — three inversions, in order of cost

**1. The portrait is a seductive detail in the strict technical sense.** It is
the single heaviest object on the page (31.7%) and it carries **no information
the player does not already have**: the roster row they just clicked shows the
same face, and the name is printed twice within 400px. It is interesting,
irrelevant to the decision, and competing directly with the decision for
attention. §1.5 is exactly about this.

**2. The deck strip is 28.3% of the page's weight for content that is not a
choice on this screen.** Ten art tiles at high contrast. Note this is not a case
for reverting it — the strip *replaced* seven baked card faces that rendered
their rules text at 11.2px, and it is strictly better information at a third of
the ink. The fault is not the strip, it is that the strip now out-weighs
everything the screen is for.

**3. The dossier is last, and it is the only thing that differentiates the
choice.** "Marching Spurs · The first friendly you relocate each round gets +1
ATK and Swift this round" plus the three HOW HE FIGHTS lines — that IS the
decision. It is set at 16px dim on bare canvas with no plate, no rule, no
contrast, and it measures as the faintest content on the page.

**All three are the same fault:** weight is allocated by how much *area a thing
occupies* rather than by how much *the decision depends on it*.

---

## §5 WHAT TO CHANGE, ranked by measured effect

Each of these is checkable — re-run `--sweep` and the region report after.

**A. Shrink the portrait, and give the recovered weight to the dossier.**
The largest single lever: it fixes balance (0.633 → target ≥ 0.85, the shell
median), complexity (removes the largest high-edge block), and the weight
inversion, in one move. The stronger version is to delete the standalone
portrait entirely and let the *selected roster row* grow — the roster tiles
already carry the face, so the information is not lost, and the page becomes two
columns (choose | know) instead of three (choose | look | know). Note the house
rule in [[feedback_ui_aesthetic]]: left-aligned columns are for pages with
side-anchored art; a lone document element must be centred. A two-column
choose/know page satisfies both.

**B. Signal the dossier.** Per §1.5 the payoff here is the largest in the
literature (g+ ≈ 0.53 retention / 0.33 transfer). The relic rule and HOW HE
FIGHTS should be the strongest text on the right half — a plate behind them
(`scripts/ui/Sheen.gd`'s `plinth`/`inset` are the house kit), the relic rule at
reading size, the three phrases at dossier weight rather than caption weight.

**C. Demote the deck strip, do not remove it.** Reduce its optical weight so it
reads as a footer: it is reference, not a decision. Target is that it stops
appearing in the top two of the squint ranking.

**D. Fix the measure and the weight in one edit.** Pitch **16px → 18px** and
`MUSTER_PROSE_W` **660 → 560**. At 16px/660 the line is 88 CPL; at 18px/560 it
lands at **≈66 CPL — Bringhurst's optimum** — *and* the block gains the contrast
it needs for (B). Two faults, one change.

**E. Put meaning at the centre.** The first fixation is going to (800, 450) in
design space no matter what is placed there (§1.4). Today that is a picture's
corner. After (A) it should be the hero's name and rule.

**F. Close the hole, do not pad around it.** The 460×240 dead rect is *inside*
the dossier column. It closes by the dossier having more to say (which (B) does)
or by the column narrowing so the space becomes margin — never by adding
spacers, per [[reference_dead_space_vs_negative_space]].

---

## §5A WHAT WAS ACTUALLY BUILT (2026-09-17), AND WHAT IT MOVED

Four changes shipped. Compile gate green, screens re-rendered and re-measured.

| change | before | after |
|---|---|---|
| hero pitch | 16px / 660px measure | **18px / 560px** |
| pitch line 1 | **88 CPL** | **74 CPL** (inside Bringhurst's band) |
| signature relic rule | 15px | **17px** (64 CPL) |
| HOW HE FIGHTS lines | 16px | 17px |
| portrait plate | 352px wide | **316px** (−19% area), still top-aligned |

Page-level, measured on the rendered frames:

| measure | before | after |
|---|---|---|
| Ngo balance-V | 0.633 | **0.683** |
| Ngo balance-H | 0.843 | 0.803 |
| left-half ink share | 61.2% | **59.4%** |
| decoration share | 60.0% | **55.4%** |
| edge density | 9.90% | **9.71%** |
| ink density | 26.65% | 25.49% |

**Render-to-render noise was measured at 0.0008 balance points** (two renders of
an identical build), so every delta above is real and not sampling. Note
balance-H moved the *wrong* way by 0.04: that is the cost of a smaller plate
putting less ink in the top half, and it was accepted as the price of the
vertical gain. Attribution caveat: the retained "before" PNG turned out to
already contain the type edits, so the split between the type pass and the
portrait pass is reconstructed from the chain rather than from a designed A/B.
The endpoints are measured; do not quote an intermediate as a controlled result.

**THE HONEST HEADLINE: the readability is fixed and the COMPOSITION IS NOT.**
The dossier is still **#9 of 9** in the squint ranking, decoration still holds
55.4% against the decision's 23.8%, and balance-V is still 0.686 against a shell
median of 0.878. Type size cannot fix a composition problem — that is the
finding, not a failure of the pass. What remains is structural and needs a
decision this pass deliberately did not take unilaterally (see §5C below).

### Negative result: THE PLINTH DOES NOT WORK BEHIND A TEXT COLUMN

Worth recording because the reasoning was sound and the result was not. §1.5 says
signalling is the best-evidenced move available, so the decision block was given
a `Sheen.plinth` ground — no border, no fill, no boundary, therefore not a
violation of the 2026-09-15 "a section is A COLUMN OF TYPE, not a box" ruling.

Measured at strength 0.16: dossier mean optical weight 0.0443 → 0.0490, squint
rank unchanged. Cosmetic. Raised to 0.32: plainly visible and plainly wrong — a
warm blob in open canvas right of "Relocate allies", attached to nothing,
reading as a lens flare. **The fault is the tool, not the tuning**, so no third
strength would have helped: `Sheen.plinth` centres an ellipse on its target's
RECT, and this column's rect is ~780×564 around content that is left-flush and
~560×420, so the pool centred itself in the empty bottom-right and lit the HOLE.
A tall left-flush column of prose has no standing point for a pool to find.
Reverted; the code carries a DO-NOT-RE-ADD comment with the measurements.

### Negative result: CENTRING THE PORTRAIT VERTICALLY IS WORSE

Also built, measured and reverted. The argument was the dead-space rule — the
plate is ~145px shorter than the band the roster sets, and top-alignment puts
all that slack under it in one lump. Centring cost **balance-H 0.843 → 0.661**
(top/bottom ink 45.7/54.3 → 39.8/60.2), because centring the heaviest object on
the page is just moving it down. And structurally it was worse: the three
columns in that band — roster, plate, dossier — **share a top edge**, and
centred, the portrait began 71px below the lord's own name beside it and read as
floating. The dead-space rule is about content pinned to the top of a tall rect
with *nothing below it*; here the deck rail sits directly below, so that gap
separates two bands rather than hanging under one.

**The general lesson from both reverts: balance was a DIAGNOSTIC, not a target.**
0.633 said the composition was picture-left / type-right. It did not licence
bolting a light source onto the page, or sliding the portrait down, until the
number moved. Both of those moved a number and made the screen worse. The
changes that survived are all subtractive or in-place.

### §5D THE STRUCTURAL PASS — the rail joins the hero (2026-09-17, same day)

The type pass fixed readability and left the composition alone, so a second pass
took the structure. **One `add_child` carried most of it:** `_hero_deck_rail`
moved from `menu` (its own full-width band under all three columns) into
`column` (the hero's own section), turning roster | portrait | dossier | rail
into **roster | character sheet**, where the sheet is face, rules and army in
one object. `MUSTER_OPENER_STRIP_W` 1548 → 1100 (the column's width) and
`MUSTER_HOST_ROW_H` 108 → 124 followed.

The justification is §1.5's spatial-contiguity finding, which is the largest
effect in this survey (**g = 0.63**, 58 comparisons, n = 2,426): the deck's own
caption used to sit flush left *under the roster*, roughly a thousand pixels
from the lord whose deck it describes, while the roster it was adjacent to has
nothing to do with it.

| measure | original | final |
|---|---|---|
| Ngo balance-V | 0.633 | **0.727** |
| Ngo balance-H | 0.843 | **0.952** |
| Ngo equilibrium | 0.895 | **0.942** |
| edge density | 9.90% | **7.69%** |
| ink density | 26.65% | 21.13% |
| decoration : decision | **2.59 : 1** | **1.34 : 1** |
| deck rail squint weight | 0.1958 | **0.1273** |
| pitch line | 88 CPL | 74 CPL |

The deck rail is no longer the loudest thing on the page, balance-V closed most
of the gap to the shell median (0.880), and complexity — the axis with the
asymmetric penalty — fell 22%. **Still unfixed: the dossier is last in the
squint ranking.** Sparse type over a large area cannot out-weigh a painting, and
this pass found no honest way to change that without either shrinking the
portrait past what a character select should, or adding an element (which §5A's
plinth result rules out).

**Two calibration failures worth recording, both the same mistake.** Filling the
band the rail's departure left behind was tried at two rows of five tiles
(+205px on ~70px of real headroom — the second row clipped and the footer went
off-canvas) and at `MUSTER_HOST_ROW_H` 140 then 130 (both still overflowed).
**The empty band measured ~160px but only ~70px of it was free**; the rest was
the footer's own separation, which is structure, not slack. Measure the
headroom, do not measure the hole.

**And a harness note that cost a wrong conclusion:** one render of the 124 build
came back with START RUN entirely absent, and the pixel probe "confirming" it
was reading background embers. It was a shot race — the capture caught a
mid-build frame. Re-rendering showed the button present at peak weight 0.857.
Re-render before believing a control has vanished.

### §5E THE FINE PASS — why the dossier read flat, and a correction to §5D

§5D said the dossier being last in the squint ranking was a ceiling. Two more
measurements found it was not a ceiling, it was two ordinary defects — and then
a third finding said the metric was the wrong one to be chasing anyway.

**FAULT 1 — THE TYPE SCALE HAD COLLAPSED.** Published guidance puts the
perceptible step between adjacent hierarchy levels at roughly **20–25%**. The
dossier ran **34 / 20 / 18 / 17 / 15**, whose adjacent steps are 41% / 10% / 6%
/ 12%. So it advertised five levels and delivered **two**: the name, and
everything else. 17 and 18 differ by 6% and simply read as the same size — that
is noise wearing the costume of hierarchy. Replaced with a real three-level
scale, `MUSTER_TYPE_CAPTION 15 / MUSTER_TYPE_READ 18 / MUSTER_TYPE_NAME 22` plus
the 34 name: steps of **1.20 / 1.22 / 1.55**. Past three levels the literature
says switch channels rather than push size, which this screen already does
(GILT_BRIGHT on the relic name, letter-spaced caps on captions).

**FAULT 2 — THE SPACING RATIO WAS INVERTED.** Gestalt proximity is read
*relatively*: the gap between groups must be visibly larger than the gap inside
them, or everything clusters with everything and the grouping vanishes. The
dossier's outermost between-group container (`pane`) separated at **4** while
`prose` — a box of things that belong together — separated at **10**. Between
was smaller than within. Now a single scale: `MUSTER_SEP_LINE 2` within a line,
`MUSTER_SEP_INBLOCK 4` within a block, `MUSTER_SEP_BLOCK 18` between blocks, with
the hero's name and win/loss record boxed together at 0 so the record reads as a
subtitle rather than as a fourth section.

| measure | original | now |
|---|---|---|
| dossier share of page ink | 9.88% | **17.70%** |
| Ngo balance-H | 0.843 | **0.982** |
| Ngo equilibrium | 0.895 | 0.938 |
| perceptible type levels in the dossier | 2 (of 5 nominal) | **4 (of 4)** |
| between:within spacing ratio | 0.4 : 1 (inverted) | **4.5 : 1** |

**AND THE CORRECTION, which matters more than the fix.** The dossier's squint
weight barely moved — 0.0421 → 0.0439 — while its share of the page's ink nearly
doubled. That is not a failure; it is the metric answering a question I should
not have been asking it. **The squint test asks "what draws the eye FIRST", and
a block of body copy legitimately loses that to a painting in any well-designed
layout** — a magazine spread would score the same way and be correct. Squint
weight is ink per unit *area*, so a reading block can only win it by ceasing to
be a reading block.

Use the squint ranking to judge what should GRAB — the primary action, the
headline, the hero image, and to catch decoration out-shouting all three (which
is what it correctly caught here at 60% decoration). Judge a reading block by
measure, scale, grouping and contrast instead, all of which are separately
measurable and all of which were genuinely broken. §5D's "unfixed ceiling" was
an artefact of applying one oracle past its range.

### §5C THE ONE CHANGE NOT MADE, AND WHY IT IS THE OWNER'S CALL

The deck strip holds **29.1%** of the page's optical weight — it is now the
single heaviest object on the screen, above the portrait — for ten art tiles
that are not a choice on this screen. Demoting it is the largest remaining
lever, and it was **deliberately not taken**, because `_make_opener_art_strip`
carries an explicit authored intent that says the opposite:

> "The card art is the only thing on this screen that says what the run will
> FEEL like; it should be the biggest thing on it."

That intent was written without the measurement, and the measurement now
disagrees with it. That is a design decision, not a defect, so it is surfaced
rather than overridden. The options, cheapest first: strengthen the tiles' edge
burn (`Sheen.vignette`, currently 0.40 — darkens the tile edges, costs no size),
narrow the strip, or move it behind VIEW FULL DECK, which is already one click
away. Any of the three should take the strip out of the top two of the squint
ranking; only the last would fix the ranking outright.

---

## §5B THE STARTING BONUS, MEASURED (2026-09-18) — and the one thing balance cannot see

The owner's note was *"it's still quite empty"* about the STARTING BONUS after a
material pass on its writ tiles. This section is the follow-through, because the
measurement disagreed with three plausible diagnoses in a row before landing.

### 5B.1 What the numbers said

```
                 bal-H   density   quadrants TL/TR/BL/BR
starting bonus   0.141   42.98%     6.4   5.9  44.2  43.4
shell range      0.43-1.00  14-36%   nothing else past ~38% in one cell
```

Two outliers against its own siblings, and the regional dump names the cause:
the four writs carry **82.07% of the page's optical weight in one horizontal
band**, and that band's centre sat **117px BELOW the canvas midline**. Title,
lead, gloss and BACK together came to **3.21%**. "Empty" was not a hole in the
layout — it was a page with exactly one object on it, parked off-centre.

### 5B.2 FOUR SWEEPS, THREE OF THEM NEGATIVE — and the negatives are the content

Every lever was swept on real captures and graded by the same instrument that
found the defect. Only the last one worked.

| lever | range | bal-H | verdict |
|---|---|---|---|
| hero plate height | 158 → 360px | 0.142 → **0.056** | WORSE. Growing the header pushes the row further down; equilibrium 0.875 → 0.738. |
| writ tile height | 172 → 290px | 0.142 → 0.158 | inert, and density 43% → 46% — the punished direction. |
| table layer alpha | 1.0 → 0.12 | 0.142 → 0.172 | the background was never the problem. |
| **block translation** | 0 → 120px | 0.142 → **0.838** | the lever. |

The three failures share a mechanism worth stating once: **the column is
vertically centred, so anything that grows it pushes its heavy band further from
the middle.** Growth cannot fix a placement problem.

**A taller rect is NOT a substitute for translation**, which is the obvious thing
to reach for. `_center_menu_for_subscreen`'s own height dial swept 640 → 880
reached only bal-H 0.242, because once the rect exceeds the content the
`_muster_slack` spacers stop being pinned and EXPAND: the block spread apart
(footer 769 → 889) instead of moving. Translation and expansion are different
operations and only one of them fixes this.

### 5B.3 THE FINDING THAT MATTERS MOST: balance is necessary and NOT sufficient

Pushing the column's 113px of slack below the writ row scored **bal-H 0.997,
quadrants 25.5/24.6/25.1/24.8** — a near-perfect page by the one measure with
strong empirical support — **and opened a 200px void between the gloss and
BACK.** Both statements describe the same frame.

The reason is mechanical: **Ngo balance counts the table's dim wash as mass.** On
a painted ground, a region can be optically heavy and visually empty at the same
time, so a composition can satisfy balance BY parking content away from its own
background.

So this pass added a second oracle beside it, and it is deliberately crude:
**the tallest EMPTY spacer inside the column** (`_shot_bonus._dump_layout`).
Space around a composed block is margin; space inside it is a hole. A frame only
counts if it scores on one without failing the other:

```
rect  lift   bal-H   tallest empty spacer
712    76    0.864   76px   <- HOLE
660    76    0.745   41px
600    76    0.629    1px
600   105    0.980    1px   <- shipped
600   120    0.762    1px
```

### 5B.4 What shipped

`BONUS_PAGE_H = 600` (just under the column's 599px content height, so the
spacers pin at ~1px and the block is content-tight) and
`BONUS_BLOCK_LIFT = 105`. The height that lift spends was freed by moving the
lead line into the lord's own strip — it is a sentence about him, and as its own
centred band it cost a row plus two gaps.

```
                 before      after
bal-H            0.141       0.980
equilibrium      0.872       0.985
mass centre y    0.621       0.510
quadrants        6.4/5.9/44.2/43.4    25.7/24.8/24.9/24.6
tallest gap      94px        34px
```

### 5B.5 Two measurement traps this cost, both general

1. **OVERLAPPING REGIONS MAKE SHARES MEANINGLESS.** The table rect contains all
   four writs, so it reported 96.69% of the page's weight and read as one
   decorative layer swamping the screen. It was measuring the writs. The alpha
   sweep is what caught it — taking the layer to 12% left the region at 95.94%,
   which no single-cause story survives. Regions must be DISJOINT.
2. **A SWEEP MUST NOT OVERWRITE THE SETTLED SCREEN'S REGION LIST.** It did, so
   `_bonus_full.png` was being graded against rects from whatever frame the
   sweep ended on — which put the title at canvas y=10 when the container had it
   at 36. Two wrong conclusions came from that before `_dump_layout` was added
   and the container was simply asked.

**And the standing lesson underneath both: print what the container DID.** Two
guesses about why the block would not translate were both wrong; one dump of
rect + per-child position/size/flags settled it in a single run and revealed the
113px of slack that was the actual subject.

## §6 THE HOUSE PATTERN — this is a screen problem, not a style problem

```
screen            bal-V  bal-H  equil  dens%  edge%  colour   TL/TR/BL/BR quadrant %
main menu         0.878  0.796  0.994  15.22   4.57    22.3    23.2  21.2  23.6  32.1
RUN SETUP         0.633  0.843  0.895  26.65   9.90    28.4    32.5  13.2  28.7  25.5
quick march       0.577  0.914  0.919  16.48   6.76    27.9    32.9  19.3  30.5  17.2
starting bonus    0.974  0.145  0.874  42.89   7.17    22.4     6.6   6.1  44.1  43.3
shop              0.921  0.432  0.892  33.78   6.56    31.9    31.5  38.4  16.5  13.7
reward            0.769  0.870  0.959  14.00   3.84    25.1    34.4  19.1  22.2  24.4
event             0.362  0.998  0.909  30.14   2.46    13.4    14.6  35.4  12.0  38.0
rest/camp         0.986  0.855  0.971  28.72   4.24    20.0    21.3  24.8  28.4  25.5
game over         0.949  0.741  0.985  35.93   3.83    18.4    20.6  21.9  28.1  29.4
```

**RUN SETUP and quick march are the two worst-balanced screens in the shell**
(0.633, 0.577) and they are the same layout — roster | portrait | dossier. The
rest of the shell sits at 0.88–0.99. Whatever is wrong is local to this pattern,
which is good news: it is one fix, not a restyle.

Two other things the sweep surfaces, both for later and neither part of this
pass:

- **Starting bonus: bal-H 0.145** — 87.4% of its weight is in the bottom half.
  It is otherwise the best-composed screen in the flow (bal-V 0.974, one title,
  one question, four parallel tiles) and the fix is the same class as (F): the
  bottom quarter is a hole, not a margin.
- **Shop: bal-H 0.432**, 70% of weight in the top half.

---

## §7 WHAT THIS PASS SAYS NOT TO DO

- **Do not reach for the golden ratio.** §1.3. Pick a closed ratio set and a
  spacing step and hold to them; which set is nearly irrelevant.
- **Do not fix balance by adding things to the light side.** That raises
  complexity, which is the axis with the asymmetric penalty (§1.1). Remove from
  the heavy side.
- **Do not treat "it feels empty" as a layout problem before checking which
  fault it is** — hole under the content vs. flat surfaces
  ([[reference_dead_space_vs_negative_space]]).
- **Do not use position or scale to signal state inside a laid-out group.** The
  channel rule from [[feedback_informational_offset_vs_structure]] — light,
  colour, saturation or an outline first; geometry only well under the layout's
  own amplitude.
- **Do not gate on an absolute balance figure.** Judge against the shell median;
  some screens are asymmetric on purpose.

---

## SOURCES

- Tuch, Presslaber, Stöcklin, Opwis & Bargas-Avila (2012). *The role of visual
  complexity and prototypicality regarding first impression of websites.*
  IJHCS 70(11). https://doi.org/10.1016/j.ijhcs.2012.06.003
- Reinecke, Yeh, Miratrix, Mardiko, Zhao, Liu & Gajos (2013). *Predicting users'
  first impressions of website aesthetics with a quantification of perceived
  visual complexity and colorfulness.* CHI 2013.
  https://doi.org/10.1145/2470654.2481281
- Ngo, Teo & Byrne (2003). *Modelling interface aesthetics.* Information
  Sciences 152. Formulas: http://www.mi.sanu.ac.rs/vismath/ngo/
- Altaboli & Lin (2011). *Investigating Effects of Screen Layout Elements on
  Interface and Screen Design Aesthetics.* Adv. in HCI 2011:659758.
  https://doi.org/10.1155/2011/659758
- Kurosu & Kashimura (1995); Tractinsky (1997). Aesthetic–usability effect.
  Summary: https://www.nngroup.com/articles/aesthetic-usability-effect/
- Henderson & Hayes (2017). *Meaning-based guidance of attention in scenes as
  revealed by meaning maps.* Nature Human Behaviour 1.
  https://doi.org/10.1038/s41562-017-0208-0
- Tatler (2007); Bindemann (2010). Central fixation bias.
  https://jov.arvojournals.org/article.aspx?articleid=2122066
- Sundararajan & Adesope (2020). *Keep it Coherent: A Meta-Analysis of the
  Seductive Details Effect.* Educational Psychology Review.
  https://doi.org/10.1007/s10648-020-09522-4
- Schneider, Beege, Nebel & Rey (2018) / Alpizar et al. (2020). Signalling
  meta-analyses. https://doi.org/10.1007/s11423-020-09748-7
- Bringhurst, *The Elements of Typographic Style*, 45–75 CPL. Baymard on the
  80-CPL skip effect: https://baymard.com/blog/line-length-readability
- Golden-ratio evidence review: https://eusci.org.uk/2020/07/29/myth-busting-the-golden-ratio/
- Squint test as practice: https://www.nngroup.com/videos/squint-test/ ·
  https://www.lukew.com/ff/entry.asp?2013=
- Gestalt proximity dominance: https://www.nngroup.com/articles/gestalt-proximity/
- Palmer, Gardner & Wickens (2008). *Aesthetic issues in spatial composition:
  effects of position and direction on framing single objects.* Spatial Vision
  21(5). Centre bias: preference peaks at the frame centre and falls
  monotonically and symmetrically with distance.
  https://pubmed.ncbi.nlm.nih.gov/18534113/
- Sammartino & Palmer (2012). *Aesthetic issues in spatial composition: effects
  of vertical position and perspective on framing single objects.* JEP:HPP.
  Preferences unify under "the object's AFFORDANCE SPACE centred in the frame" —
  which is why a table's surface may legitimately run away below the paperwork.
  https://pubmed.ncbi.nlm.nih.gov/22428674/
- NOTE ON A COMMON MIS-CITATION: "Lin (2004) found whitespace improves
  comprehension by 20%" is not what that paper says — Lin has stated it "has
  nothing to do with whitespace". The defensible result is narrower: readers are
  SLOWER with margins but understand more, and prefer them.
  https://www.linkedin.com/pulse/lin-2004-did-discover-margins-white-space-increase-20-carl-myhill
