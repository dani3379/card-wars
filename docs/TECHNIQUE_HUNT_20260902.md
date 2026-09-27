# The techniques we have never used once — a hunt by TECHNIQUE (2026-09-02)

> **STATUS: ALL THREE BUILT (2026-09-02)** — ▲1 the boil (§6), ▲2 the smear (§7),
> ▲3 the spring (§8). ▲3 closes **C3**, open since 2026-07-16.
>
> **▲2's own numbers in §2 were WRONG on two counts and are corrected in §7.**
> The window (t −55 → −22) was the slow tail of an EXPO-out drive, and the
> stretch (1.55×) was longer than the ground the body covers. Both were caught by
> building it. The pitch is left unedited above so the corrections are legible.

Eight prior passes hunted by **surface**: pick a screen, ask what beat is missing.
[`GAME_COOL_HUNT_20260804.md`](GAME_COOL_HUNT_20260804.md) §1 says out loud where
that ends up — *"asking 'what beat is missing' is the wrong question now — the
honest answer is almost none"* — and its §6 is the eighth consecutive list of
candidates killed by reading the display path first.

So this pass turns the axis ninety degrees. Not *which surface is silent*, but
**which low-level techniques does the 2D medium have that this game has never used
a single time?** A technique absent everywhere cannot be found by looking at any
one screen, because there is nothing on that screen to compare it against.

Answerable to the same two rules, which do more work here than anywhere:

> **★3 (SIZE).** An effect lands only where its material is visible at the size it
> is drawn. *Do the arithmetic before the painter.*
>
> **★4 (SUBSTANCE).** Obey the material. Inventing material is the failure mode.

Items numbered **▲** so they never collide with the pitch's ★, the card hunt's ✦,
the game hunt's ✱ or the menu hunt's ❖.

---

## 1. The technique ledger

Every row grepped out of shipped source, not remembered.

| Technique | Status | Evidence |
|---|---|---|
| Anticipation | **have** | `Motion.ANTICIPATE`; `forge_strike`/`writ_amend` wind-up |
| Squash & stretch | **have** | `writ_amend` squash snapped with no tween; lunge `Vector2(1-0.04s, 1+0.07s)` |
| Impact frames (white flash) | **have** | `Motion.impact_frame`, 2 frames, sized to the squashed rect |
| Hitstop | **have** | `_strike_stop` / `hold_strike_frame`, per-card |
| Screen shake | **have** | `GameTheme.add_trauma`, trauma-pooled |
| Particles | **have** | `Motion.burst`, 7 presets |
| Rings / shockwaves | **have** | `Motion.ring`, `shock_rings` (thin-fast + slow-heavy) |
| Specular / foil | **have** | `Motion.foil_sweep`, `_sweep_shader`, on a child rect |
| Dissolve / burn | **have** | `Motion.burn_away`, `burn_material` |
| Typewriter / stamp | **have** | `write_on`, `stamp_in` |
| Ken Burns | **have** | `Motion.ken_burns` |
| Cursor tilt / lean | **have** | `Card2D._process`, ±0.35 drag / ±0.10 hover |
| Camera push-in, desat drain | **have** | ★8 `_play_killing_blow_moment` |
| Card ShaderMaterial | **have** (doc stale) | `Card2D:4310` `_gilt_mat`, `:4418` `_flash_mat` — the 07-16 audit's *"Card2D has no ShaderMaterial at all"* is no longer true |
| **Boil (line animated on twos)** | **NEVER USED** | zero hits for boil / on-twos / variant-cycle in `scripts/` and in all 30 docs |
| **Smear frames** | **NEVER USED** | only `PipDie`'s static mid-tumble face; no velocity smear anywhere |
| **Springs / 2nd-order dynamics** | **NEVER USED** | 0 hits in `Motion.gd`. Diagnosed as C3 on 2026-07-16 and *still open* |
| Parallax (board) | **rejected** | STRIKE_DESIGN §14 — ground painted inside `board_zone`, breaks ★6 lockstep |
| Global slow-motion | **rejected** | `Combat.gd:4917` — `Engine.time_scale` fights the player's anim-speed dial |

Three techniques have never been used, and one of them has never been *mentioned*.

---

## 2. The slate

### ▲1 — THE INK NEVER BREATHES (boil)

**The observation.** Shoot the board and look at the chart furniture: four lane
boxes, the corner ticks, the gold front-line rule, the MUSTER chips. Every one is
drawn once and then frozen for the entire fight. The game's whole material claim
is *hand-inked parchment on a war table* — and a line that never moves is not
hand-inked. **It is printed.** That is the ★4 test failing in the one place the
material is most insisted upon.

**What other games do, and the low-level fact.** Hand-drawn media do not animate
line art at the frame rate; they animate it **on twos or threes** — 12 or 8 fps —
and the residual wobble between drawings is the entire reason the line reads as
having been made by a hand. Cuphead, Hollow Knight's ink, Paper Mario's paper,
Loop Hero and Inscryption's woodcut all trade on it. **A frozen line reads as
print; a boiling line reads as drawn.** The effect is famously invisible until
removed, which is exactly why eight surface passes walked past it.

**Why it has not been possible to just add.** CLAUDE.md is explicit: the map plate
is *frozen while on screen*, per-frame animation belongs in `MapPulseOverlay`, and
plate layers get **baked** into one texture. A boil recomputed per frame would
fight both. So build it the way the animation industry does, which happens to also
be the cheap way:

- **Three seeded variants, not per-frame noise.** Precompute 3 versions of the top
  ink layer only, at build time, into 3 point arrays. `_draw` switches between
  them. No per-frame math at all.
- **Cycle at 8 fps** (every ~7.5 frames at 60 Hz) in a **non-repeating order** —
  `1,2,3,2,1,3`. A plain `1,2,3` loop reads as a 3-frame flicker, which is the
  classic mistake.
- **Amplitude ±0.6 px** at 1×. Above ~1.2 px it stops being a hand and becomes a
  vibration. Below ~0.35 px it is eaten — though note `RubricStroke`'s own comment
  that 0.85 physical px resolves to a half-alpha smear under LINEAR filtering,
  which is precisely why sub-pixel offsets *do* render here.
- **Perturb the control points, not the item.** Offsetting the whole CanvasItem is
  a shake. Offset each vertex independently: `p + Vector2(n(i,v), n(i+37,v)) * 0.6`.
- **Where:** a new un-baked child CanvasItem above `PlateItem`'s ink block — never
  inside the bake.
- **Gating:** decorative. Reduce Motion holds variant 1 forever.

**Why it ranks first.** Screen time is the highest in the game — the board is up
for most of a session — the cost is three cached arrays and a modulo, and it is
the only item here that makes the game's *existing* art assert something it
currently does not.

### ▲2 — THE STRIKE HAS NO SMEAR

**The low-level fact.** In hand-drawn animation a fast move is not drawn sharp on
every frame; at peak velocity the artist draws a **smear** — one elongated,
low-contrast frame that occupies the whole path. Eyes read it as speed rather than
as a blurred mistake, and without it a fast move reads as *teleporting*. This is
the oldest trick in the medium and the game does not use it once.

**This codebase already knows the idea.** `PipDie` draws "a soft motion-smear
instead of a settled face" mid-tumble. It was invented for one die and never
generalised.

**Low level.** DRIVE runs t −85 → 0 (STRIKE_DESIGN §2.2) and the token covers
~40–60 px — about 5 frames at 60 Hz, which is exactly the window where sharp
frames read as a jump.

- Show the smear for **2 frames only**, t −55 → −22, and free it at contact.
- It is the attacker's **own already-baked texture** (CardTextureCache has it),
  scaled **1.55× along the travel axis and 0.88× across**, alpha **0.30**, drawn at
  the midpoint between last and current position.
- Cost: one Sprite2D reusing an existing texture. No new art, no shader.

**It survives §4's arbitration, and the doc supplies the argument itself.** The
smear carries **no new propositional content** and adds **no new actor** — it is
the same actor rendered with its velocity, which is the identical distinction that
lets the buckle survive as *"a **transform**, not a drawn line"*. It also ends at
t=0, so it never enters the fused CONTACT window, and Slot 1's single travelling
mark remains the `RubricStroke`. It is not the rejected blade arc: an arc invents a
weapon; a smear only draws the body that is already moving.

### ▲3 — SPRINGS, STILL OPEN AS C3 (and not what §14 rejected)

**Status.** `Motion.gd` has **zero** springs; 165 `create_tween` sites. The
2026-07-16 audit filed this as **#3 / C3** and recorded C3 as open. It still is.

**Read the two rulings together, because they do not conflict.** STRIKE_DESIGN §14
rejects *"Springs for the strike"* for a precise and correct reason — `LUNGE_APEX`
is **derived** from the tween's phases so the conductor's `await` agrees with the
animation, and **a spring has no apex you can await**. That argument is airtight
and it is about the strike. It says nothing about hand layout, which awaits
nothing.

**And hand layout is where the audit put it,** because it is the interruption case:
`set_hand_target`'s reflow tween is killed and restarted on every hover, drag and
relayout — the case tweens handle worst and springs handle natively. This project
has already paid for it once (the 07-12 hand alpha-strand fix).

**Low level** — t3ssel8r's second-order form, the one the audit named:

```
k1 = ζ/(π f)      k2 = 1/((2π f)²)      k3 = r·ζ/(2π f)
y  += dt·y'
y' += dt·(x + k3·x' − y − k1·y') / k2
```

- Hand reflow: **f ≈ 3.2 Hz, ζ ≈ 0.72, r = 0** → settles ~0.28 s with a small
  overshoot, and an interruption is *continuous* because the spring carries
  velocity as state.
- **Position channel only.** `Card2D._process` has ONE writer for `rotation` and
  the lean driver owns it while hovered/dragged; a spring must not become a second
  writer there.
- Additive: springs live beside the kit, they replace nothing.

### ▲4 — REACTIVE AMBIENT — pitched and then rejected by its own arithmetic

The board runs `AmbientEmbers` at a constant rate and a killing blow does not
disturb it. Vlambeer's rule is that everything reacts, and the fix is genuinely
free: on `add_trauma(t)`, for 180 ms scale the emitter's `initial_velocity` by
`1 + 2.2·t` and rotate `direction` away from the impact.

**Rejecting it anyway, on ★3.** Do the arithmetic before the painter: the embers
are sparse and live at the screen edges, and the moment they would react is the one
moment the player is looking at a hitstop, a shake, a spray and a numeral inside a
~250 px fixation. An effect nobody can be looking at is not an effect. Recorded so
it is not re-proposed.

---

## 3. REJECTED — so they are not re-proposed

| rejected | why |
|---|---|
| **Chromatic aberration / RGB split on the killing blow** | A **lens** artifact. This game has no lens — it is a table seen from above with ink on it, and §14 rejected a real `Camera2D` from the same family of reasoning. Adding a lens defect to a paper game is the ★4 failure exactly: inventing material that is not there. |
| **Motion blur** | Same objection, and ▲2 is the medium-correct answer to the same problem: hand-drawn work solves speed with a smear, not a convolution. |
| **Parallax board/table** | Already rejected, STRIKE_DESIGN §14. Re-affirmed: the ground is painted *inside* `board_zone`. |
| **Global `Engine.time_scale` slow-motion** | Already rejected in code with a stated reason (`Combat.gd:4917`): it is global and fights the player's anim-speed dial. The per-card `hold_strike_frame` is the right shape. |
| **Boiling the CARD faces too** | ★3. A hand card's rules text is 17–18 px on a fitted box; boiling type at that size is illegibility, not craft. Boil the **chart furniture**, which is rules-free line work. |

---

## 4. The standing backlog this pass did not touch

Surfaced because it is real work already specced by earlier passes, and none of it
appears in the commit log:

- **C4 / C5** from the 07-16 audit. C4 is now *partly* closed and the doc is stale —
  `Card2D` does carry materials (`_gilt_mat`, `_flash_mat`).
- **✱1–✱5** from the 08-04 game hunt (the foe's law outliving his army; the isle
  that never burns; the page that turns out; the relic cache; invisible claimed
  provinces). Each already carries a verification plan in that doc's §7.

---

## 5. Verification, if any of this is built

| item | harness | assertion |
|---|---|---|
| ▲1 | `_shot_combat_hud` ×2, 125 ms apart | the two frames must differ in the ink layer and **nowhere else**; Reduce Motion frames must be identical |
| ▲2 | `_shot_killing_blow`, +1 frame at t −38 | a smear present at −38 and gone at contact; `_probe_beat_spacing` unmoved |
| ▲3 | `_probe_anim_clock` | hand settles within 0.32 s from any interruption point; `rotation` still has one writer |

Shot harnesses must force `UserSettings.reduce_motion = false` — this machine's
saved settings have it ON.

---

## 6. ▲1 as built (2026-09-02)

**The kit primitive** is `Motion.boil_variant(elapsed)` and
`Motion.boil_offset(point_index, variant)` — deliberately in the kit rather than
inside one painter, so the next inked surface can adopt it in two lines.
`BOIL_FPS 8`, `BOIL_AMP 0.6`, `BOIL_ORDER [0,1,2,1,0,2]`. The offsets are a pure
function of (point, variant), so there is no per-frame math and no state to drift,
and **variant 0 is defined as the undisplaced drawing** — which is what lets
Reduce Motion render precisely the chart that shipped before the boil existed.

**The consumer** is `TablePlate`, whose own header used to end *"Drawn once;
static"*. What boils there is a MATERIAL judgement, not a perf one:

| boils | does not boil |
|---|---|
| the coast (both rules, displaced independently — two hand-drawn parallel lines never wobble in lockstep) | the burn scorch |
| the sea hatching | the cup ring stains |
| the march routes | the lane grid (outside this painter) |
| the site rings, the compass | |

**A spill is not draughtsmanship.** Nobody redrew the scorch or the stain, so
nothing about them should move — and they are the largest, softest shapes on the
plate, so boiling them would have been the most visible thing on the board, which
is exactly backwards. The lane grid is excluded on the same principle from the
other side: *the chart is hand-drawn, the grid is the printed rule of the board.*

**Measured.** 2.02 % of the plate changes between drawings, mean luma move 0.019,
peak 0.121; Reduce Motion 0.0000 %. Cold-entry A/B: **0 frame gaps over 100 ms
after playable** in both runs — the boil costs nothing measurable.

### The gate could not see its own load-bearing number

First version asserted only pixels, and a mutant making the displacement **ten
times too large PASSED** — 6 px of wobble moved luma by just 0.2253 against a 0.55
ceiling, because the chart's ink runs at alpha 0.055–0.16 and *faint ink displaced
hard is still a faint change*. Amplitude is the one quantity that separates a boil
from a vibration, and the pixel oracle was structurally blind to it.

Fixed by asserting `Motion`'s constants and offset function directly, where 10× is
unmissable. **A pixel oracle cannot judge a quantity it only sees through alpha
0.1** — that is the general lesson, and it applies to every faint-ink effect this
project might gate the same way. The pixel half still earns its place: it is what
proves the thing runs at all and that only a thin minority of the plate moves.

### Harness trap: `%g` is a silent compile failure

GDScript's `%` formatting does not support `%g`. In a `--script` probe that is a
loud parse error; in a **scene** harness it is a *compile* error that aborts
`_ready` before the first `print`, so the window simply hangs with **no output at
all** and no obvious cause. Diagnosed only by reading the `at: GDScript::reload
(...:59)` line numbers out of the captured log and noticing that every one of them
was a `%g`. Use `%.2f`.

---

## 7. ▲2 as built (2026-09-02)

`Card2D._play_strike_smear`, fired from `play_attack_lunge`. One `Sprite2D` reusing
the token's already-baked face; two frames; freed before contact. Gate
`tools/_probe_smear.tscn`, eyes `tools/_shot_smear.tscn`.

**Both of the pitch's numbers were wrong, and building it is what proved it.**

### The window was the slow tail

The pitch said t −55 → −22 before contact, lifted from STRIKE_DESIGN's generic
exposure sheet. But the drive is **EXPO-out over 90 ms**, which front-loads
distance *on purpose* (§2.2: the card is effectively stopped at the contact
frame). Solve it: by t −55 the body has covered `1 − 2^(−10·0.39)` ≈ **93 %** and
is coasting. A speed line there is drawn on a body that has already stopped.

Peak velocity is the **first two frames of the drive**, so that is where it fires.
**Read the easing before choosing the frame** — a window is only meaningful
against the curve that fills it.

### The stretch was longer than the distance travelled

1.55× was a guess. The arithmetic ★3 demands: a smear covers **body + travel**,
the travel is 7 px of pull-back plus 26·strength forward = **33 px against a
150 px token**, so the honest figure is `1 + 33/150` = **1.22**.

Shot at 1.55× and alpha 0.30, it read as a **doubled card** — and that is the
predictable result, not bad luck: *a ghost longer than the ground it covers has no
motion to explain it, so the eye files it as a second object.* Now derived per
blow by `_smear_stretch(travel, body)` (clamped 1.10–1.45) so a heavy strike,
which genuinely covers more ground, genuinely smears longer — and the gate derives
its expectation the same way instead of restating a constant. Alpha halved to
**0.16**: at 0.30 a full-art copy resolves *as a card*, and the whole technique
depends on it never resolving as an object.

**Honest ceiling:** 33 px of travel on a 150 px body cannot produce a legible
streak. What ▲2 delivers is weight and a trailing edge, not a Vlambeer speed line,
and the arithmetic says that is all it could ever have delivered.

### Three engine facts it cost

- **A `TextureRect` takes its minimum size from its texture.** The battlefield
  face is baked supersampled (432×332 behind a 200×150 token), so `size = size`
  was silently overridden and the ghost was placed and scaled against a box more
  than twice the body it was copying.
- **`top_level` does not save a Control child.** It detaches the canvas transform,
  but a Control is still LAID OUT by its parent — when the card's rect moved, the
  ghost re-anchored and rode along. Verified placing correctly at spawn
  (380, 311.54) and dragged to (392, 270.29) 12 ms later. A `Node2D` is laid out
  by nothing, so `top_level` on it means what it says. **For a world-space FX node
  parented to a moving Control, use a Node2D.**
- **A negative `z_index` on a top_level node sinks it under the world.** "Behind
  the body" and "behind the board" are the same place in a flat z=0 canvas: at −1
  the smear rendered nowhere at all, and only a screenshot caught it — every
  geometric assertion passed while nothing was on screen.

---

## 8. ▲3 as built (2026-09-02)

`Motion.Spring` (the kit primitive, t3ssel8r's second-order form) driving
`Card2D`'s hand reflow through `_arm_hand_spring` / `_tick_hand_spring`. Gate
`tools/_probe_spring.tscn`. **C3 is closed after seven weeks open.**

**POSITION ONLY, and that is the whole compatibility story.** `_process` is the
LEAN driver and `rotation` has exactly one writer at a time by construction (C1);
a spring on that channel would be a second writer during hover and drag, which is
the one thing that contract forbids. Rotation, scale and alpha stay on
`_hand_tween`. The two drivers now share the callback on different channels, and
the spring stands itself down the moment a hover or drag begins — which is exactly
when the lean takes over.

**Tuned from measurement, not taste.**

| | f | zeta | settles | tween it replaced | overshoot |
|---|---|---|---|---|---|
| reflow | 5.4 | 0.68 | 0.167 s | 0.17 s | 0.2 px |
| deal | 4.6 | 0.70 | 0.250 s | 0.24 s | 0.6 px |

The first guess (f 3.6 / zeta 0.78) measured **0.30 s — nearly twice the tween**,
and a hand that became continuous but slower would be a downgrade dressed as a
feature. Note that raising `f` alone barely moves it: the settle is governed by
the exponential tail, so the DAMPING had to come down. The residual sub-pixel
overshoot is deliberate and is the thing a tween cannot do.

### What the gate had to learn

- **The interruption assertion was wrong the first time.** It demanded velocity
  barely change across a retarget — but a stiff spring *should* accelerate hard
  when the target jumps 600 px behind it; demanding otherwise demands a mushy
  spring, not a continuous one. **Continuity is a property of POSITION**: the body
  keeps travelling the way it was for the frame the interruption lands on
  (measured: 16.08 px carried, exactly the pre-retarget velocity × dt) instead of
  restarting from rest the way a killed and rebuilt tween does.
- **The pace budget was 2× and passed a hand that had become measurably slower.**
  Tightened to 1.25×.
- **`k2_stable` is load-bearing, not decoration.** Removing it and feeding one
  250 ms frame — a gap this project really does ship during a cold board build —
  sends the card to **2.9 × 10¹⁰ px**. Clamping k2 up makes a long frame merely
  sluggish, which is the correct failure.
- **The regression that mattered was `_disarm_lean`.** It used to call
  `set_process(false)` unconditionally, and it fires on hover-exit and `_end_drag`
  — both of which can land mid-reflow. Mutating it back strands a card **220 px**
  from its slot for the rest of the fight. The gate simulates exactly that.

### It invalidated a proxy in another gate, and the fix was not to make it green

`_probe_card_play` asserted `is_processing() == false` three times as a stand-in
for "the lean driver is off". With two drivers sharing `_process`, that proxy
stopped holding — the node legitimately processes for ~0.17 s after any relayout.
The assertions were rewritten to test `_lean_active`, which is what they always
meant, and the frame-cost half they were also protecting was re-added explicitly
as **"every driver stands down once settled"**. Deleting that half to get a green
run would have thrown away the only real guarantee in the three checks.
