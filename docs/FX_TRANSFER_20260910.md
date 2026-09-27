# What makes the lightning bolt work, and porting it outside combat
**2026-09-10**

The owner's verdict on the spell-family pass was that the shock family — the
lightning bolt — was the one that came out cool, and that the others were still
behind it even after they had forms. This is the anatomy of why, followed by an
inventory of the animation surface OUTSIDE combat measured against it, and what
was rebuilt.

---

## 1. The bolt, dissected

`Combat._spawn_lightning_bolt` → `_lightning_stroke` → `_lightning_path` /
`_lightning_draw`. Ten decisions, in rough order of how much each contributes.

### 1.1 It has a FORM, and the form is specific to lightning

Not "a line in the shock family's colour". A **branching channel** built by
recursive midpoint displacement, where the displacement HALVES each level so the
crookedness is self-similar — big deviations carrying smaller ones. Five levels.

The counter-example is in the same file's history: five independent random bumps
on a straight line. That has crookedness at exactly one scale, and it reads as a
wiggly line rather than as a bolt.

**The general rule: particles are TEXTURE, not FORM. A family without a drawn
silhouette reads as coloured dots whatever the palette.**

### 1.2 The spread is a FRACTION of the run

34px of deviation on a 700px cast is 5%, which subdivides into a gentle wave.
Real lightning deviates 10–20% and stays ANGULAR. `run_len * 0.16`.

Any constant that should have been a ratio produces an effect that looks right at
one size and wrong at every other.

### 1.3 It BRANCHES

Forks are most of what separates lightning from a crooked line — one or two per
stroke, shorter, dimmer, dying sooner.

### 1.4 It is SEVERAL DISCHARGES, not one object

This is the single biggest one. A single path that fades is the documented
failure mode: **a motionless bright object reads as frozen however well it is
drawn.** Three strokes on offset cycles (0 / 0.048 / 0.096s), each re-rolling its
own path, middle one strongest because the return stroke is the bright one.

Real lightning is discharges separated far enough in time for the eye to resolve
them — which is *why* it appears to flicker.

### 1.5 It never holds still for one frame, but it stays ANCHORED

Per-frame interior jitter with the ENDPOINTS PINNED. The channel crawls; what
cast it and what it hit do not move.

### 1.6 It SNAPS ON, HOLDS, then dies

An earlier cut began fading on its spawn frame and photographed as a spider
thread — there was no instant at which the thing was ever at full strength. **The
hold IS the effect.** (Peak ink went 71 → 479 on that fix alone.)

### 1.7 The stroke is TEXTURED across its width

A `Line2D` has UNIFORM OPACITY ACROSS ITS WIDTH — a hard band with no soft edge
and no internal structure, which is why every line effect in this game used to
look like a line. **Stacking three does not fix it**; it makes a thicker hard band
with a dimmer hard band behind it. `Motion.beam_tex` paints the cross-section
instead (R = heat profile, A = opacity profile) and one line then does the whole
job in a single draw.

### 1.8 Value contrast: a white-hot core

A lone warm line on a warm table is camouflage. The core ramps toward white.

### 1.9 It LANDS somewhere

A strike-point bloom fires with the return stroke. A bolt that arrives with no
mark where it hits reads as passing through the board rather than hitting it.

### 1.10 Its aliveness is MATCHED TO ITS MATTER

The lesson that cost the most to learn: **aliveness is not one technique.**
Copying the bolt's random jitter onto a flame reads as buzzing. Lightning
FLICKERS; fire CHURNS; a crack PROPAGATES and must not flicker, because it is
damage, not a discharge.

---

## 2. What actually transfers

Three of those ten are about electricity and do not travel: midpoint
displacement, forks, flicker. **The other seven are a general recipe**, and the
tenth is the rule that stops the recipe being applied mechanically:

| # | transferable rule |
|---|---|
| 1 | A signature FORM, specific to the thing — not a tinted generic shape |
| 2 | Constants that describe geometry must be RATIOS of the run |
| 4 | Repetition separated in time; one object that fades reads as frozen |
| 5 | Alive in the interior, ANCHORED at the ends |
| 6 | Snap on, HOLD, then die — never fade from frame one |
| 7 | Texture the primitive; uniform opacity is the defect, stacking is not the fix |
| 8 | Value contrast decided against the GROUND |
| 9 | It has to land somewhere |
| 10 | Match the aliveness to the matter, or you are just borrowing a tic |

---

## 3. The non-combat surface, measured

**Correction, and it matters for where the tooling gap actually is.** An earlier
draft of this section claimed `tools/_fx_technique_audit.py` scans only four
combat files. It does not — it was widened to sweep every script under `scripts/`
and reads 158 effects, 0 flat-primitive findings. That claim was read off the
tool's *historical* comment rather than its code.

The gap that let everything below through is a different one, and narrower: the
sweep finds effects by **NAME SHAPE** (`_spawn_*`, `_play_*`, `_flash_*`,
`_pulse_*`, `_burst_*`, `_vfx_*`, `_fx_*`), and it flags a flat primitive only
when the name also matches its ENERGY vocabulary. **The map's entire animated
layer is immediate-mode `_draw_*` functions** — `_draw_committed_route`,
`_draw_glints`, `_draw_etna_plume` — which match neither filter. So it is not
that the tool could not see the file; it is that an always-on immediate-mode ink
layer is outside its model of what an effect looks like. See §7.

The per-screen numbers below still stand, and they explain what that cost.

Motion-verb usage per screen, whole game:

```
MainMenu    deal_in x6   hover_lift x6   claim_pop x2
Shop        deal_in x14  claim_pop x4    hover_lift x3  tick_number x2  burst x1
Rest        deal_in x18  hover_lift x6   claim_pop x3   forge_strike x1 burst x1
Reward      deal_in x13  hover_lift x3   claim_pop x3   rarity_reveal   punch
Wayside     deal_in x10  hover_lift x5   writ_amend x2  claim_pop x1
Event       deal_in x14  burst x6        write_on x4    ring x3  writ_amend x2
Treasure / Recruit / GameOver — the same three verbs, single digits
MapView · MapTerrain · Collection · Credits — ZERO
```

`deal_in` is fade-and-slide. `hover_lift` is scale 1.03. `claim_pop` is a scale
pop. **That is the entire vocabulary: transform tweens on alpha and scale.**

Which is the same diagnosis as the spell families, one level up:

> Particles are texture, not form.
> **Transform tweens are timing, not form.**

A screen where everything fades in and scales on hover has good *rhythm* and no
*moments*. Nothing on it has a shape.

### The map is where this costs the most

`MapPulseOverlay` is the one always-animating non-combat surface, and the player
crosses it ~90 times a run. All 33 of its draw calls were bare flat primitives —
`draw_arc`, `draw_circle`, `draw_line`, `draw_polyline`.

`draw_polyline` has the same uniform opacity `Line2D` does. So the committed
march was **four stacked flat polylines** (9px dark, 3.4 amber, 7px dark, 3.8
bright) — bit for bit the layering that did not fix the bolt.

(The plate itself — MapTerrain's 189 draw calls — is *correctly* flat. It is an
engraved chart, not an energy effect. The audit's own rule is to flag an ENERGY
effect built from a bare flat primitive, and that is the line followed here.)

---

## 4. What was built

### 4.1 The road is WRITTEN, not drawn

**Form:** a PEN STROKE. New `Motion.beam_tex("ink")` profile — and it is the
first kind in the beam kit that is not a GLOW. Every other kind is a thin hot
spine with a wide soft halo, because they are drawn on a dark table and have to
look like they are emitting. Ink is a dense body that has soaked into paper, so
the numbers invert: `core` 0.11→0.34 (a broad solid centre), `edge` 1.9→1.05 (a
slow falloff, which is FEATHERING along the paper fibres), `grain` 0.34 (the
strongest lengthwise variation of any kind, because that is nib pressure).

New `"nib"` taper: firm entry, full-pressure belly easing mid-travel, widest at
the terminal where the pen is still sitting. Deliberately not `"comet"`, which
starts from nothing — a written line does not; the pen touches down with weight.

**Aliveness: SETTING.** Lightning flickers, fire churns, a crack propagates — ink
sets. The stroke is split at a fixed distance behind the pen: ahead of the split
it is wet, behind it the ink has dried. Neither half animates; the SPLIT POINT
rides the nib, so the road visibly dries from the back as the column walks.

**Wet is DARKER than dry**, which is the opposite of the obvious cut and the way
ink actually behaves — a fresh stroke is a saturated pool and it lightens as it
sets. Building wet as the bright end put the halves in the wrong order and lost
the gloss, because on cream paper "glossy" cannot be a brighter body; it has to
be a small specular ON a dark mark. Hence a fourth stroke: a thin pale highlight
riding the last 58px, which also lands the contrast rule correctly once inverted
— **the darkest dark and the brightest bright, both at the nib.**

The unwalked remainder stays underneath as a RULED PLAN, and the hover preview is
a **dry-point ruling**: same pen, gloss off, pressure flat. A plan is scored, an
order is inked — previously the difference was brightness alone, the weakest
signal available.

### 4.2 The fired marks reach the ring engine

Commit, arrival and frontier-reveal were hand-rolled `draw_arc` circles replayed
from a timestamp every frame. They are `Motion.ring` one-shots now — eroded band,
hot front, and the reveal takes its nearest-first stagger as the `delay` opt, so
the draw loop stops knowing about it entirely.

The arrival fires **two** rings, fast over slow. Not redundancy: with a gradient
core that pairing is a timing device — the thin one is contact, the heavy one is
the weight arriving behind it. It is rule 9: the march now ENDS somewhere instead
of dissolving mid-stride into the scene fade.

**The breathing availability rings stay flat, deliberately.** They are not beats;
they are UI telegraphs that stand there permanently. The ring engine's own note
settles that case — a standing mark gets grit 0 and almost no hot core, at which
point it *is* a crisp arc. Same reasoning that leaves the combat forecast cross
flat.

### 4.3 The dispatch riders

A 3px `draw_line` with a 2.2px disc on the front, on every open road, forever.
Three things were wrong and only one was the technique:

- **It chorded across the curve.** Two points cannot follow a bend, so on every
  curved leg the runner cut the corner and left the road. Arc-sampled now.
- **It was a conveyor belt.** A linear phase with no gap means the runners never
  start and never stop, which reads as machinery. Rule 4: each leg now
  dispatches, holds empty for a beat, and dispatches again, eased off the mark
  and into the gate.
- **It was a flat band.** Textured comet, and the taper does a second job — a
  symmetrical streak has no direction, which is the one thing this effect exists
  to say.

### 4.4 Etna's plume

Three grey `draw_circle` discs at alpha 0.085, on the mountain the game is named
after. At that alpha it is not a subtle effect, it is an absent one.

**Form:** the engraved plume a cartographer would cut beside a smoking mountain —
lobed contours, the family the deckled coast and the terrain marks already use.
**Aliveness: CONVECTION AND SHEAR.** Lobes are born at the vent, rise, expand
fast-then-slow (a thermal stalls as it cools), roll — their wobble harmonics turn,
so the silhouette churns rather than merely translating — and bend downwind harder
with height as the column loses its own momentum. Offset phases, so several ages
are always present: rule 4 again.

MapTerrain's four static baked puffs were removed. The plate never animates, so
keeping them meant a moving plume passing behind a painted one.

### 4.5 The standard's lamplight

Three stacked `draw_circle`s at 0.038 / 0.055 / 0.07, under a comment that read
"stacked discs so the falloff stays soft". That is a hand-rolled gradient with
two visible steps in it, on the single brightest thing on the chart. One textured
pool now — `particle_tex` paints the falloff, so one draw replaces the stack.

**And it flickers on its own clock.** `sway` is the WIND, which is right for the
banner above it and wrong for a flame: a lamp does not breathe on a clean sine,
it gutters. Three harmonics at incommensurate rates never repeat. Rule 10 for one
extra line. The ring at the centre stays a crisp arc — it is not the glow, it is
the MARK saying where the army is standing.

---

## 4b. Second pass — "still not on the level of the lightning"

The owner's verdict on everything above was: better, but not there. It was right,
and the diagnosis is one sentence.

> **Everything in §4 had a form and a concept of aliveness, and then
> INTERPOLATED SMOOTHLY between two states.** The bolt is violent and
> DISCONTINUOUS. Smooth is pretty; discontinuous is alive.

Graded honestly against §2, the first pass had rules 1, 2, 7, 8, 9 and 10 —
and was missing **4 (repetition separated in time)**, **5 (alive in the
interior)** and **6 (snap, hold, die)** on every single surface. Those three are
the ones that cost the most.

**The road's line was a machine-perfect trace of the road.** The bolt's very
first decision, missed entirely: a bolt is not a path with a good profile, it is
a path IRREGULAR AT SEVERAL SCALES. `_hand_path` now displaces it — but this is
not `_lightning_path` copied over, and the difference is the craft. Lightning is
ANGULAR at five octaves because a discharge takes the crooked route; **a pen has
no corners at all.** So: three octaves, then two rounds of Chaikin corner-cutting,
which kills every corner and keeps the deviation. Same maths, opposite surface.
Amplitude is 1.4% of the leg — 2.6% was tried and the ink visibly *left* the road
and swung back, which beside a printed dashed road reads as a registration error
rather than as a hand.

**The pen writes in strokes, not one glide.** A single SINE ease across the leg
was the last pure interpolation. Three strokes now, each with its own
accelerate-and-settle, separated by a ~42ms rest — rule 4, translated rather than
copied (a hand lays a stroke, checks, lays the next). Measured, not eyeballed:
the harness samples progress every frame and prints `###..##########..##########`.

**Ink pools where a nib rests**, so each of those two hesitations leaves a blot —
the visible half of a beat that would otherwise only be felt.

**The nib trembles** — rule 5, correctly scoped. The bolt pins BOTH endpoints
because both of its ends are anchored; a pen has one dried end and one live end in
a hand, so the taper runs the other way: nothing moves at the back of the wet
window, full tremble at the tip. Laid ink must never crawl.

**The bleed was backwards.** Wet was 20px and dry 12. A nib lays a NARROW HEAVY
BEAD and the paper then drinks it, so the mark BLOOMS wider and paler as it sets.
Corrected, width and value now move together and in opposite directions across
the wet/dry split — twice the signal for no extra ink.

**Spatter and a flick.** A nib struck onto paper throws ink; a pen leaving the page
throws forward in a narrow cone. These are the only violent things on the chart,
and they are the snap the whole pass was missing — everything else eased, so the
march had no instant you could point at and call the start.

**A volcano does not exhale at a constant rate.** Evenly-spaced lobes were a
conveyor belt, the same defect as the riders. The slot is warped so each third of
the lobes squeezes into the front 44% of its share: three tight puffs with real
gaps. Each lobe also drifts on its own two-harmonic clock, so the mass churns
instead of running on rails. **And the vent flares on the puff phase**, not a
clock of its own — the difference between two things happening near each other and
one CAUSING the other, which is most of what separates an effect you watch from an
effect you notice. Ash specks ride faster than the smoke that carries them.

**The riders snap on.** A symmetric sine envelope fades a dispatch in as slowly as
it fades out, so there is no instant at which it happened. Lit inside the first 6%
of the run, decaying the rest of the way: what trails is a wake, not a fade.

## 4c. The closing seal, and the verdict curtain

**The seal was already the right shape and had no material in it.** Down fast,
EASE_IN so it stops dead because a stamp has no follow-through — form and snap
both present, and then nothing that wax actually does. Three things now:

- **IT SQUEEZES OUT.** Wax under a matrix flows sideways, so the seal is briefly
  wider than its rest size and settles back as the flow stops. The settle is slow
  and one-way on purpose: a bounce returns symmetrically and wax does not bounce.
- **THE PAPER TAKES IT.** A screen shake says the DESK was hit and says nothing
  about the sheet. Rule 9. The dent is drawn under the seal and never fades — it
  is the last permanent thing the run does.
- **IT COOLS.** A single specular crossing the wax and gone: it was liquid a
  moment ago and is not now. The same "setting" aliveness the road ink got, on a
  much shorter clock.

Plus **no fade-in**. It used to ramp alpha 0 → 1 across the descent, which is the
exact defect that cost the lightning two rebuilds — no instant at which the thing
was ever at full strength. A stamp is a physical object approaching the page; it
is opaque the whole way down. The rings at contact are in the WAX's colour rather
than the kit's white, because that is displaced material, not a flash — and the
impact frame is warm and low (0.30) rather than the kit's white-hot default,
which photographed the seal pale pink at the one instant it should read as a deep
red mass landing.

**The verdict curtain was one 58-particle burst** — everything spawned together
and died together, so the run's last beat was over before the page had been read.
Three waves now, and **the two verdicts are shaped differently in time**, which
was previously only colour and direction: a victory ARRIVES (loudest first,
thinning to drifting embers), ash SETTLES (starts thin and keeps coming, still
falling when the player looks away).

**A gate defect found on the way**, unrelated to the FX and worth more than any
of it: `tools/_probe_copy_lint.gd` called `String(key_value)`, and **Godot 4's
String has constructors for String / StringName / NodePath and nothing else**. So
`String(0)` raises "Nonexistent 'String' constructor" and ABORTS the function —
`COACH_MODE_LABELS` is keyed by the COACH_* ints, so that map had never been
linted at all, while the probe went on printing `PROBE PASS` because the abort
kills the scan and not the verdict. A gate reporting success on a scan it never
performed is precisely the FAKE GATE the method doc is about. Whether the runner
noticed depended on stdout/stderr buffering order, which is why it surfaced
intermittently. Fixed to `str()`; the scan count went 3089 → 3092, which is the
proof it now opens.

## 4d. Making the audit's liveness check mean something

`_fx_technique_audit.py` carried **6 standing `z` findings** — ENERGY effects that
spawn and dim, which is the defect §4b is entirely about. Read one at a time,
**five of the six were false positives, for two distinct and fixable reasons**,
and the noise was burying the one that was real.

**Cause 1 — DELEGATION.** `liveness()` reads a single function body, so an effect
that hands its work to a helper scores STATIC however alive the helper is.
`Card2D._flash_hit` delegates to `_flash_face_hit` and keeps a modulate tween
only as its fallback; `Wayside._spawn_result_seal` is one `Motion.ring` call,
i.e. the shader ring with its own animator inside. **`classify()` already carried
this exact lesson** three lines away ("a node handed a ShaderMaterial built
elsewhere is using the technique") and it had never been applied to the liveness
half.

**Cause 2 — A CONFIRMATION IS NOT AN EFFECT.** The ENERGY vocabulary contains
`pulse`, `flash`, `claim` and `seal`, which are exactly the words UI chrome uses.
`NetLobby._flash_pick`, `Event._pulse_crown_mark` and `Combat._pulse_log_tab` are
one object each: a scale-or-modulate pop on a node the function was HANDED,
saying "you picked this" or "there is something new here". They *correctly* have
no internal life — a selection tick that keeps moving is a distraction, and
`_pulse_log_tab` documents its own Reduce Motion branch for that reason. The
discriminator is **SPAWN vs DECORATE**: an effect brings something into
existence, a confirmation animates something already on screen.

Both exemptions are **printed with their reason**, never silently dropped — an
invisible exemption list is how a gate stops meaning anything.

**The one real finding was `Combat._play_face_damage_flash`**, and it was the
lightning's own defect wearing a much better shader. The 2026-09-09 rebuild fixed
its technique (an aspect-corrected vignette, zero at the centre by construction)
and left its ENVELOPE untouched: it began fading on its spawn frame, so there was
no instant at which it was ever at full strength. The bolt gained most of its
weight from a single 35 ms hold — peak ink 71 → 479 on that change alone.

It now **holds, then throbs**. The throb is the matched aliveness: a blood
vignette must not flicker (that is a discharge; this is a body being hit) but
neither should it merely dim — pain arrives, eases, and comes back once before it
goes. Both the hold and the throb scale with the blow, and a 1-damage chip gets
neither, because punctuation on a scratch reads as melodrama.

Audit after: **0 flat, 0 dead, 8 excused with reasons.**

## 4e. Credits — the fire the screen had already claimed

`_build_backdrop`'s own comment has always read *"the night camp — the same fire
the army rests by. The chronicler writes these names by its light."* There was no
light on the roll. The screen was a list of labels drifting over a painted camp
at one flat exposure, with no focal point and nothing alive on it — **the same
shape as `_play_face_damage_flash`, which described blood at the edges of vision
and shipped a uniform wash.** Twice now the intent was documented and unbuilt,
which is a smell worth looking for on its own: *read the comments as a spec and
check whether the code honours them.*

**Form:** a pool of firelight across the reading line, so a name is brightest
exactly where the eye already is. **Aliveness: guttering** — the three-harmonic
flicker the war table's standard lamp uses, incommensurate rates that never
repeat, because a campfire does not breathe on a clean sine.

**Additive, and here that is correct.** The ring engine measured `blend_add` and
rejected it — but that was for a mark that FADES, where folding alpha into the
colour means a fading additive ring stops adding anything. This pool never fades;
it is light falling on a page, which is the one thing `blend_add` models. It also
means the effect can only ever ADD contrast, so it cannot push a name under the
COPY_STYLE §11 floor — which a darkening vignette could, and `add_atmosphere` is
already spending one of those.

Two structural notes: `_process` used to switch itself off at the foot of the
roll on the grounds that there was "no animation left to drive", which stopped
being true (a hearth that goes out when the scrolling stops is worse than never
lighting it) — the scroll parks on a flag now. And Reduce Motion **holds the pool
steady rather than removing it**: the focal point is information about where to
read; only the guttering is decorative.

Verified by measurement, not eye — `tools/_shot_credits_fire.tscn` samples mean
luminance in three bands and requires the reading band to beat both ends:
`head=0.055 read=0.519 foot=0.408`, and the reading band moves 0.5187 → 0.5377
between two frames, which is the guttering proving it is running.

## 4f. Screens — the transition was one-sided

Every screen change ran three overlapping fades: an authored ink burn OUT, a flat
`color:a 1 → 0` on a pure-black rect IN, then `deal_in` per element. So it read as
*"a page burns away, and then a brightness happens"*. **The exit was craft and the
entrance was an alpha ramp**, which is the rule the card pass already settled —
*cards are dealt, not faded; alpha and scale are what objects never change* —
never applied one level up, to screens that are each a specific physical thing (a
chart on a war table, a chronicle page, a roll).

Three separate faults, in increasing order of interest:

- **A hue pop at the cut.** The exit settles on sepia ink; the entrance started
  from pure black, so the switch flicked colder for a frame.
- **An uncovered build.** `change_scene_to_file` swaps on the next idle frame, the
  incoming scene runs `_ready` — which is where every screen here assembles its
  entire UI in code — and only *after* that does its own deferred `fade_in` get
  to spawn a cover. The half-built screen was on display for the whole of its own
  construction, i.e. its most expensive frame.
- **No continuity of attention.** The exit converges on the thing the player
  clicked; the entrance began nowhere.

**One overlay now does both halves**: it covers, holds across the build, then
flips `invert` and runs `progress` back down to reveal — from the same point the
exit closed on, carried across the scene change on `GameTheme.transition_origin`.
At the flip it is opaque either way (every `f` sits below the threshold at
progress 1), so the hand-off has no seam *by construction* rather than by timing.

**The rejected first fix is worth recording**: holding the old cover while the new
scene's `fade_in` revealed underneath it. Two stacked overlays means the incoming
one is already part-revealed when the outgoing one frees, so the screen jumps from
covered to half-revealed in a single frame — and the obvious patch, fading the old
one out, *cannot work here*, because this shader writes `COLOR` outright and
`modulate` never reaches it.

`fade_in` stands down while a reveal is pending, and there is an unconditional
tree-owned backstop that frees the overlay whatever happens, because the failure
recorded in that function is this exact overlay never being freed — a black screen
that ate every click with no way out.

**The hold is load-aware, not a constant.** A fixed hold was the first version
and it is a guess dressed as a number: a warm scene is ready in a frame or two
and gets made to wait out the rest, while a cold one is still building when the
ink starts lifting — the exact defect the hold was added to fix, only narrower.
It now waits for the scene to have SWAPPED (a different instance, since
`change_scene_to_file` is deferred and `current_scene` still points at the old
one for a frame) and then two consecutive CALM frames. **A build hitch is a long
frame by definition, so "frames are short again" IS "the build is done"** — no
per-scene cooperation needed, which matters because every screen here builds
differently. Wall-clock between resumes rather than `delta`, because a stalled
frame's reported delta can be clamped and noticing the stall is the whole job.
Bounded at both ends: a floor so an instant swap does not flicker, a ceiling so a
bad frame budget degrades to the old fixed behaviour rather than a stuck cover.

**Gate: `tools/_probe_transition.tscn`** (in `run_ui_gates`, since it boots a
scene). It asserts the state machine rather than pixels — cover appears, wipe
claims the reveal, `fade_in` stands down instead of stacking, scene changes, the
hold lands inside its declared band, and **the cover always lifts**. Measured
headless: 0.091s, i.e. the floor, against the old fixed 0.16.

**Scope of that gate, stated:** it exercises the FAST path and both bounds. A
cold build is not simulated, so "the settle loop waits out a real hitch" is
argued from the mechanism, not demonstrated.

## 5. Five findings that cost real iterations

**A shader that writes `COLOR` ignores `modulate`** — already known; still true.

**1. `show_behind_parent`, not `z_index = -1`.** The first cut of the ink layer
drew perfectly, one layer too deep: the baked plate is an opaque sibling canvas
item at z 0, so anything at z -1 sorts below it and is never seen. The flag draws
a child before the parent's own `_draw` while keeping it in the parent's z band —
above the plate, below the overlay's furniture.

**2. The white-hot core rule INVERTS on a light ground.** `beam_material` now
takes a `core` colour (default white, so every existing call site is unchanged).
On the parchment chart the "hot" middle of a mark is its DARKEST, most saturated
part, because that is where the pigment pooled. The ring engine's own note had
flagged this ground — "would have been unusable on the shell's parchment" — one
effect early.

**3. Value is decided by the LOCAL ground, not the screen's.** This had to be
re-decided three times inside one pass. The road ink went dark (cream paper).
Etna's contour went pale (the dark eastern mountains). The plume's mass had to be
a MID value, because it crosses both — born on black rock, drifting out over open
paper — and a pale plume vanished the moment it cleared the range.

**4. Stacking translucent fills EMBOSSES the thing you were dissolving.** Fourteen
heavily-overlapping smoke lobes still photographed as a row of marbles. A point
near a lobe's centre is covered by more neighbours than a point on its rim, so
alpha accumulation manufactures a bright core at every centre. Same family as the
lightning stack: piling translucent copies of a shape does not blur it.
`draw_colored_polygon` has uniform opacity across its AREA exactly as `Line2D`
does across its width — the mass is a textured blob now. (It cannot be fixed by
handing UVs to the polygon: a rim-only polygon triangulates into fans that all
touch the rim, so the interpolated UV never reaches the texture's centre.)

**5. Overlapping fills merge; overlapping OUTLINES do not.** Drawing a closed
contour around every lobe kept every internal edge, so the eye counted circles.
An engraver draws the outline of the UNION — arcs and hollow C-shapes where one
billow passes in front of another. Each vertex is tested against its neighbours
and dropped if it lies inside one. Two traps in that: the neighbour window is
meaningless until `built` is SORTED BY PHASE (the array wraps, so "three along"
was sometimes the top of the column against something still in the vent), and the
occluder threshold must match the threshold that decided to draw the lobe at all
— set higher, the faint lobes at the top stopped occluding, their outlines closed
into rings, and the plume grew a chain of hard circles exactly where it was meant
to be dissolving.

**Method note, worth more than any of the above:** several iterations were spent
tuning a defect that was not mine. Pale hard-edged discs sat over Etna and did not
respond to any change; tinting my own layer bright red for one frame proved in
seconds that they were baked plate art. **When an effect stops responding to its
own parameters, prove ownership before tuning further.**

---

## 6. Verify

- `tools/_shot_map_ink.tscn` — 10 frames: the dry-point hover, two dispatch-rider
  frames a beat apart, the march at 30 / 68 / 100 % (shot by PROGRESS, not by
  clock — a timed sample measures the machine), the same road at the 1.10 zoom
  the game actually opens at, the staggered frontier reveal, and Etna twice a
  second apart. A plume that photographs identically twice is a decal.
- `tools/run_safe_probes.ps1` and `tools/run_ui_gates.ps1` both pass.

## 7. Not done

The surfaces below were inventoried and left alone. Each is the same defect;
none is on screen often enough to have outranked the map.

- **GameOver's verdict** — one particle burst, no form, and it is the run's last
  image.
- ~~Collection and Credits — zero animation of any kind.~~ **Both claims have
  since been checked and one was wrong.** Collection has `_illuminate`, a
  `Motion.foil_sweep` fired as each gallery tile hydrates — though note its file
  was edited outside this session partway through, so it is unclear whether the
  original reading was wrong or the file changed underneath it. **Credits was
  genuinely empty and is done — see §4e.**
- **`_fx_technique_audit.py`'s MODEL** (not its file list — see the correction in
  §3). It finds effects by name shape and judges a flat primitive only on names
  matching its ENERGY vocabulary. An always-animating immediate-mode `_draw_*`
  layer matches neither, which is why every finding in §3 had to be found by
  hand. Widening it is not a one-line change: sweeping all `_draw_*` would drag
  in MapTerrain's ~189 chart-engraving draws, which are *correctly* flat. The
  tool needs a notion of "runs every frame and varies with time", which it does
  not have today.
- Its 6 standing `z` findings (ENERGY effects that spawn and dim, i.e. no
  internal life — the same defect §4b is about) are unactioned:
  `Combat::_play_face_damage_flash` · `Combat::_pulse_log_tab` ·
  `Card2D::_flash_hit` · `Wayside::_spawn_result_seal` ·
  `Event::_pulse_crown_mark` · `NetLobby::_flash_pick`.
