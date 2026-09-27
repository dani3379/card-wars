# The gesture of playing a card — a hunt (2026-08-03)

Scope is one gesture and nothing else: **the card sitting in hand → hover → grab →
drag → drop → refusal or commitment → flight → landing → seated as a token**, plus
the spell variant (raised, held, then burnt or piled) and the Command that pays for
it. It is the most-repeated interaction in the game by an order of magnitude, so
frequency is near-maximal for everything below and does no discriminating at all.
**Material truth and cost do all the ranking.**

Written in the register of, and answerable to,
[`ANIMATION_COOL_PITCH_20260717.md`](ANIMATION_COOL_PITCH_20260717.md) — especially
its §1 thesis (*obey the material*) and the two rules the ★3 and ★4 reverts bought:

> **★3's rule (SIZE).** An effect only lands where its material is visible at the
> size it is drawn. A battlefield seal is 38 px carrying an 18 px numeral — about
> 8 px of wax. *Do the arithmetic before the painter.*
>
> **★4's rule (SUBSTANCE).** A battlefield token is full-bleed ART. There is no
> parchment on it to stain. Size was fine (200×150); the material wasn't there.

Every item below states its pixels and names its material. Items numbered **✦** so
they never collide with the pitch's ★ slate.

**A pass landed on this gesture the same day this was written** (travel-derived arc,
grab settle, refusal recoil, three release endings, pivot preservation, the press
through `Motion.ring`, gated by `tools/_probe_card_play.gd` + `_shot_card_play.tscn`).
The obvious gaps are closed. What follows is what is still **default** rather than
designed — and two things that are outright **wrong**, one of them introduced by that
very pass.

---

## 1. Thesis: the hand knows what it is made of; the table and the seal do not

The gesture already speaks the material in the player's half. A hand card is a
`WritLeaf` sheet with a deckled edge and `ParchmentPlate` ageing; it lifts on hover
with a real elevation shadow, tilts toward the cursor, its gilt rakes as it moves,
it smoulders a ribbon while you carry it, and it is STAMPED onto the board with a
wax press. That is the best-realised gesture in the build.

Then the moment it leaves your fingers, the material stops.

- **The table stops being a lit surface.** The card crosses it for up to 380 ms
  casting nothing, while the shadow it is *supposed* to cast is already lying in the
  destination square with nothing above it.
- **The wax stops being wax.** Paying Command — the thing every single play does —
  moves a *numeral* 25 % bigger and flashes it blue. The 96 px navy seal the numeral
  is pressed into does not move a pixel.
- **The sound describes the wrong event.** `card_play` fires when the sheet leaves
  the hand. The stamp it sounds like lands 136–396 ms later, in silence.
- **The one card state that is purely a wash goes cold.** An unaffordable writ is
  covered in `Color(0.40, 0.42, 0.49, 0.42)` — blue-grey. Every other surface in the
  game is warm; the shader that finds gold leaf measures parchment at `r−b ≈ 0.21`
  and this wash is `r−b = −0.09`. It is the one place a document turns into a
  greyed-out UI control.

| Generic today | What the material says it should be |
|---|---|
| Paying Command = a numeral punches +25 % and flashes blue | the **seal is struck again** — the wax dips, the impression rings off its rim, the new count is pressed in |
| The flight casts no shadow; the destination's shadow is lit before the card arrives | one overhead lamp: a body high above the table casts a **wide faint pool** that **tightens and darkens** as it comes down |
| One `card_play` thud, at the release | **paper leaves the sheaf** at the release; **the seal bites the board** at the press |
| Unaffordable = a cool grey-blue disabled wash | parchment **out of the lamplight** goes dark and *browner*, never bluer |
| Hand→board = the sheet is deleted and a token is built in its place | the same order, **folded down** into a field slip |
| An exhausted spell burns at 70×97 px | paper **lifts and curls toward the flame** — the most permanent act in the game should be the biggest sheet on screen |

---

## 2. The slate, ranked

### ✦1 — The Command seal is never struck

**Generic today.** `_pulse_mana_label` floats a `-N`, scale-punches `_mana_label`
(`Motion.PUNCH` out, `Motion.SETTLE` home) and washes its font colour blue for
0.32 s. That is a competent HUD-counter beat, and it is a HUD-counter beat: it treats
Command as a number in a box.

**What it actually is.** `_build_command_seal_post` builds a physical instrument: a
`Card2D.WaxSeal` in `GameTheme.COST_BLUE_GEM`, 96 px across, mounted on an ink
plinth, under a warm lamp aura, with carryover pips on the shelf and a 37 px cream
numeral **pressed into the wax**. Everything about that object says *impression*.
Spending Command should re-strike it.

**The arithmetic** (this is the ★3 test and it passes with room to spare). Visible
wax = seal radius − (numeral cap half-height + outline), with Cinzel Black's cap at
≈ 0.70 em — a method that reproduces ★3's published ≈ 8 px on the first row, which is
how you know it is the right method:

| | seal Ø | numeral | outline | visible wax, radius |
|---|---|---|---|---|
| ★3's dead canvas (battlefield) | 38 px | 18 px | 4 px | **≈ 8.7 px** |
| hand card cost seal at the fan's rest scale | 40 px | 13 px | 2.9 px | ≈ 12.6 px — *see R1* |
| **the Command seal** | **96 px** | 37 px | 6 px | **≈ 29 px** |

3.3× ★3's canvas, at a fixed HUD scale that never shrinks. And the loudest half of
the beat — the impression ring — radiates *off the 48 px rim* into the 168 px aura
box, so it is not drawn inside the wax at all and the ★3 rule does not even apply to
it. `Card2D._spawn_press_ring` is the exact device, already written, already on
`Motion.ring`.

**Material verdict: the strongest item on this page.** The object is wax, the verb
is pressing, the device exists, and it fires on literally every play.

**Where it hooks.** `Combat._pulse_mana_label` is already the funnel (already
delay-capable via `MANA_SPEND_BEAT`, already branches gain/spend). It needs a stored
reference to the seal, which `_build_command_seal_post` does not currently keep —
only `_mana_seal_post` (the hover target) and `_mana_label`.

**The one structural catch, stated so nobody discovers it in the tween.** `seal` and
`lbl` are *siblings* under `post`. Squashing `seal.scale` alone would dip the wax out
from under a stationary numeral. It needs one `MOUSE_FILTER_IGNORE` wrapper Control
holding seal + numeral, pivoted on the seal centre — and the caption, the pips and
the aura must stay OUT of it (the bank is a shelf, not the seal; the lamp does not
move when the seal is struck). `post` keeps `MOUSE_FILTER_STOP` and the tooltip is
untouched.

**Parity gap to fix in the same pass.** The opponent's mirror seal
(`_net_opp_mana_label`) never routes through `_pulse_mana_label` at all —
`CombatNet._net_set_opp_mana` calls `_set_seal_readout` and stops. The foe's Command
silently ticks today, and if the strike lands only in the player funnel the two sides
stop describing the same object.

**Cost.** Small. One wrapper, one keyed squash tween, one `Motion.ring` call, one
guard so a two-cast turn re-strikes rather than stacking.

---

### ✦2 — The flight has no depth, and its shadow arrives before it does

**Generic today.** `_place_card_in_slot` calls `_slot_set_card`, which sets the
slot's `ContactShadow.visible = true`. *Then* it calls `_play_landing_pop`, which
sets `card.modulate.a = 0`, waits a frame, detaches the card onto `_hud_layer`, and
flies it in over `lerpf(ARC_MIN_TIME, ARC_MAX_TIME, reach)` = **0.12–0.38 s**. The
flight removes the card with a bare `remove_child`, not through `_slot_take_card`,
so nothing ever hides the shadow.

Net effect, on every arced arrival on both sides: **a 184×48 px dark ellipse pops
into an empty square and lies there with nothing above it for up to 0.38 s**, then a
card lands on top of it. Effective centre alpha is 0.62 (gradient) × 0.9 (modulate)
= **0.56**. That is not subtle; it is the second-most-visible thing in the slot.

**What the material says.** The arena is a scorched chart on a war table under an
overhead lamp — every contact shadow in `_make_lane_slot` is bottom-centred and
symmetric, i.e. the light is *directly above*. Under an overhead lamp a body high
above the surface casts a **wide, faint, soft** pool; as it descends the pool
**tightens and darkens** onto its feet. That is a scale-and-alpha tween on a node
that already exists, with no offset maths and no new geometry.

**The arithmetic.** The arc already computes `reach ∈ [0, 1]` and `duration`. Start
the shadow at `scale ≈ 1.5`, `alpha ≈ 0.22` and tween both to rest over exactly
`duration`, landing on `PRESS_CONTACT`. At `reach = 0.1` (a drop right on the slot)
the spread should barely open — the same graceful degradation the apex already has,
from the same number. Under Reduce Motion and headless `with_arc` already bails, so
the shadow simply appears as today; nothing new to gate.

**Material verdict: yes, and it fixes a defect on the way.** Note carefully what is
*not* being proposed — see **R2**: a shadow that follows the card across the table is
the ★4 failure in a new dress. This one lands in a slot, where the shipped game
already proves a shadow reads.

**Where it hooks.** `Combat._slot_set_card` (the premature light), `_play_landing_pop`'s
arc branch (owns `reach` and `duration`), `_pulse_lane_slot` (already tweens
`ContactShadow.modulate.a`, so the ownership question is already half-answered — one
writer, and the landing bump must chain off the descent rather than fight it).

**Cost.** Small.

---

### ✦3 — The play cue fires when the card leaves your hand; the stamp lands silent

**This is a regression, and it is the same pass's own doing.** Before 2026-08-03 the
player's own play ran with `with_arc = false`: `_play_landing_pop` waited one frame
and pressed. Cue-to-stamp was ~16 ms — fused, correct, unremarkable. Switching the
arc on (rightly — see the comment at `_play_creature`) stretched that gap by a factor
of eight to twenty-four and nobody moved the sound.

**The measured order of events in `_play_creature`, at speed 1.0:**

| t | event | sound |
|---|---|---|
| 0 | card leaves `_hand_container` | **`card_play`** — the thud |
| +0.09 | `MANA_SPEND_BEAT` → the `-N` floats off the Command seal | — |
| +0.016 … +0.396 | the arc | — |
| **+0.136 … +0.396** | **`play_wax_press`** — squash 1.12/0.86, the impression ring, the ground ring, the dust streak, the lane wash | **silence** |

`play_wax_press`'s own comment, written the same day, calls the arrival *"the loudest
beat of the gesture"* and deepens the squash to match. It has no sound. Meanwhile the
one cue in the sequence is a thud that plays while the card is still in the air.

This is not primarily a forbidden-band complaint — [`STRIKE_DESIGN`](STRIKE_DESIGN_20260730.md)
§9 is explicit that *occupancy is fine*, and the flight is occupancy. The complaint is
material: **the sound describes the wrong event.** `card_play` is a card meeting a
table. Nothing meets the table at t = 0; a sheet leaves a sheaf.

**What the material says.** Two cues, cheap and already aliasable:
- **the release** — dry paper off the top of a sheaf; `paper_draw` already exists in
  `SFX_FALLBACKS` (→ `card_draw`), softened and slightly detuned.
- **the bite** — `card_play`, moved to `Card2D.play_wax_press`, which is the shared
  funnel every landing on both sides already routes through.

**Where it hooks, and the ownership contract it needs.** Moving the cue into
`play_wax_press` means removing it from `_play_creature` (~L10777) and from CombatNet's
seven `card_play` sites (670, 886, 2769, 2783, 2821, 3083, 3241 — two of which are
deliberately repitched foe/bot variants and would need the pitch carried onto the
press) or it will double. This is the same shape as the existing clash-audio contract —
*"struck survivors sound via `Card2D._flash_hit`, kills sound ONCE via Combat"* — and
it should be written down in CLAUDE.md the same way, because the next placement path
will otherwise add an eighth.

**Cost.** Small to medium: the tween work is trivial, the ownership sweep is six call
sites and a documented rule.

---

### ✦4 — The one cool wash on a warm document

**Generic today.** `Card2D.set_affordable(false)` sets
`modulate = Color(0.60, 0.62, 0.70)` and shows a `ColorRect` veil at
`Color(0.40, 0.42, 0.49, 0.42)`. Both are blue-grey. It is the textbook
disabled-control treatment and it works — that is not in dispute; the desaturation is
what makes an unplayable card unmistakable, and the header explains correctly why
darkening alone failed.

**The material problem, in the project's own numbers.** `Motion.GILT_CODE`'s comment
records the measurement: parchment is warm, `r−b ≈ 0.21`; `WritLeaf.paper` is
`(0.871, 0.812, 0.694)`, `r−b = +0.177`. The veil is `r−b = −0.09` and the modulate
is `r−b = −0.10`. **The unaffordable wash is the only surface in the card's whole
material kit whose hue order is inverted.** Nothing on this table is blue except the
Command wax — which is precisely the resource you have *not* got, so the one blue
thing in the fiction is being used to mean two different things at once.

Parchment out of the lamplight does not go blue. It goes dark and browner.

**The arithmetic.** Full-face wash over 225×300, rendering at 162×216 at the fan's
rest scale of 0.72. No size question exists here, and no ★4 question either: the wash
covers the whole sheet uniformly rather than trying to be a small mark on a busy
painting.

**Material verdict: yes — and it is the cheapest item on the page.** Two colour
constants. It also retires one instance of the pervasive cool-cast the 2026-07-22 art
audit named as the build's **#1 visual defect**.

**Where it hooks.** `Card2D.set_affordable` / `_ensure_unplayable_veil`.

**The honest caveat, and why this needs a shot rather than a commit.** Desaturation
is the load-bearing property, and a *warm* wash desaturates less than a neutral one —
mixing toward a low-chroma brown (the table's own `Color(0.04, 0.02, 0.012)` burn,
lifted) flattens vivid art nearly as well as blue-grey does, but "nearly" has to be
photographed against the worst case (Inferno's flames, which the header names as the
card that broke the darken-only version). Budget the shot; the arithmetic cannot
settle this one.

---

### ✦5 — The writ is swapped for a token. It should be folded into one.

**Generic today.** `set_compact_mode(true)` tears down a 225×300 portrait writ and
builds a 200×150 landscape token in a single frame, **off-tree**, in the middle of the
gesture. The code already knows this is a problem — the comment calls it "a HARD CUT"
and adds `_start_compact_morph`, a hot flash on `_compact_root`'s `modulate`, so the
token does not blink in from nothing. That is the right instinct applied to one half:
the *token* gets a beat; the *sheet* the player was holding just ceases.

**What the material says.** It is the same order. A campaign writ carried to the table
is **folded down** into a field slip — which is a real account of a real visual
discontinuity, namely that the two objects have different aspect ratios. Today the
game teleports between them and hopes the flash covers it.

**The arithmetic.** The ghost is the hand face at the drop point: 225×300 at
`DRAG_SCALE` 0.85 = **191×255 px** — 1.6× the area of a battlefield token, which is
the largest canvas any card effect in this game has ever been given. Unmissable.
There is no size question here at all. It wants to be *fast*
(≈ 0.10 s, `Motion.flip_out`'s duration) because at the release point — anywhere above
`PLAY_THRESHOLD_Y` = 0.82 — it can briefly overlap the player's back row; folding
about its own centre collapses it to a vertical line and clears.

**This is ★5's blocked half, and here is the unblocking.** The pitch parked the card's
flip because *"`play_wax_press` already owns the seated card's `scale`"*, and there is
now a second owner too: `_start_compact_morph`'s comment records that
`Container.fit_child_in_rect` **resets a child Control's scale and rotation to
identity on every sort** — measured, not assumed — which is why the morph rides
`modulate` and nothing else. Both objections are about *who owns scale on a live
node*. A free ghost on `_hud_layer` owns its own scale and contests nothing. The
precedents are already in the file: `_spawn_spell_cast_ghost` and
`CombatNet._client_animate_own_play` both build exactly this node from
`CardTextureCache.get_texture(card_data)`.

**Material verdict: yes, with the caveat that it is the only item here that adds a
node to the hottest path in the game.** It must be weakref'd, self-freeing on a real
timer (never `tw.finished` — a card can die inside its own flight; `_play_landing_pop`
already documents this trap), and it must bail on a bake miss the way the spell ghost
does.

**Where it hooks.** `Combat._play_creature`, at the line that already captures
`play_start_global` — the ghost wants the same point, for the same reason.

**Cost.** Medium. Highest risk-per-line on the page; also the only item that closes a
named gap in the pitch's own slate.

---

### ✦6 — The exhaust burns at thumbnail size

**Generic today.** `_dispose_spell_cast_ghost("burn")` runs `Motion.burn_away` on the
raised writ — correct material, correct verb, ★1's own rule applied to spells, and the
right call. But the writ has already been tweened to `scale 0.44` of a 160×220 rect,
so the burn is drawn on **70×97 px**.

**The arithmetic.** ★1's reference canvas is the battlefield face at 200×150 =
30 000 px². The exhaust ghost is 6 800 px² — **23 %**. The bands that carry the read
scale with height; `BURN_CODE`'s field falls 0.62 per unit UV.y, so a band of `b`
field units is `b / 0.62` of the sheet's height:

| | sheet height | char band (`smoothstep(0, 0.10)`) | ember band (`smoothstep(0, 0.045)`) |
|---|---|---|---|
| battlefield death (the reference) | 150 px | ~24 px | ~11 px |
| exhaust ghost as shipped | 97 px | ~16 px | **~7 px** |
| exhaust ghost grown to 1.0 | 220 px | ~35 px | ~16 px |

**Be honest about which half of this argument is load-bearing.** 7 px of ember is
thin but not dead — the size case alone is marginal and would not justify a build.
What does justify it is the second measurement and the material: the finest noise
octave (`vnoise(p * 41.0)`) has a period of 1/41 UV = **1.7 px** at 70 px wide, so the
fibre tear that makes the frontier read as *paper catching* rather than *a wipe* is
already below the mush floor — and this is the game's title verb performed on its most
permanent act, playing out at 23 % of the canvas a routine creature death gets.

**What the material says.** Paper does not burn at a constant size. It **lifts and
curls toward the flame**. A card that never comes back should be the biggest sheet on
screen for 0.4 s, not the smallest.

**Material verdict: yes, and it is nearly free** — one extra parallel scale tween on a
node that is already inside a tween.

**Where it hooks.** `Combat._dispose_spell_cast_ghost`, the `"burn"` arm.

**Cost.** Trivial. Verify with a new `_shot_card_play` frame catching the burn at
`burn ≈ 0.5` — ★1's own history says the burn curve's calibration is only ever settled
by a photograph.

---

### ✦7 — The refusal is silent, and it does not say what refused

**Generic today.** `_refuse_play` is a good funnel (seventeen sites, one beat,
correctly classed as informational so it survives Reduce Motion) and
`play_return_to_hand`'s head-shake is well-sized — 0.12 rad of kick peaking at
`0.12 × 0.833 = 0.0999 rad ≈ 5.7°`, deliberately between the fan's 12° span and the
drag lean's 20° clamp. That part is done.

Two things are not.

**(a) It makes no sound at all.** The only `"refused"` cue in the codebase is at
`_on_card_dismiss_requested` (over-marking discards, `Combat.gd` ~L14013). Every play
refusal — wrong phase, no Command, occupied slot, closed ground, a Curse, no legal
target — is mute. `SFX_FALLBACKS` already carries `"refused" → "button_click"` with a
comment insisting it must never be a sting, because *a refusal is not an impact*. The
alias exists and the funnel exists; they have simply never been introduced.

**(b) The card shakes, but the thing that said no is elsewhere.** Every refusal looks
identical, and the commonest one by far — *not enough Command* — is a statement about
the seal, not about the card. Once ✦1 exists, its negative is free and obvious: the
Command seal takes a **failed press** — it dips and does **not** ring, and does not
re-stamp. One instrument, two beats, the same verb succeeding and failing.

**Material verdict: yes, and (b) is the cheapest good idea here — but only after ✦1.**

**Where it hooks.** `Combat._refuse_play` (the funnel; the cue belongs there so the
eighteenth site inherits it), plus a shortfall arm on ✦1's press.

**Cost.** Trivial once ✦1 lands. Do not build (b) first — a failed press with no
successful press to contrast against is just a twitch.

---

## 3. Order, and what depends on what

```
✦1 the seal is struck  ──→ ✦7b the seal refuses   (the negative of ✦1; do not invert)
✦2 the flight's shadow  — independent; also fixes a live defect
✦3 the cue at the bite  — independent; needs an audio-ownership rule written down
✦4 the cold wash        — independent; two constants + one shot
✦5 the writ folds       — independent; the only item that adds a node
✦6 the exhaust grows    — independent; one tween
```

**Suggested:** ✦4 (minutes) → ✦2 (fixes a bug) → ✦3 (fixes a bug) → ✦1 (the real
item) → ✦7 → ✦6 → ✦5 last, because it is the only one that can strand a node in the
gesture the whole game runs through.

---

## 4. REJECTED — and why, which is the point of writing them down

### R1 — Anything drawn inside the HAND card's cost seal
The tempting version: the cost seal cracks / bleeds / dims when you cannot pay it.
The baked-overlay cost slot is a 56 px box (`offset_left −9 … offset_right 47`)
carrying an 18 px `_make_stat_number` with a 4 px outline. The hand's rest scale is
0.72 → the seal renders at **40 px** with **≈ 12.6 px** of visible wax; the drag scale
0.85 → 48 px and ≈ 15 px.

So it is **1.4–1.7× ★3's dead canvas** — better than the 8.7 px that killed the seal
crack, and not enough. This is still a 40–48 px seal, and the project already wrote
down that painted marks mush below ~20 px (why `KeywordEffects.INLINE_KEYWORD_STAMPS`
is off) — 12.6 px of annulus is inside that condemned band, and half of any mark's
length still runs behind the digit. The hover pose (1.15 → 64 px) is the only one with
real room, and a beat that exists only while hovering is not a play-gesture beat.

**Verdict: not provably dead, and the burden of proof is on whoever wants it.** ★3's
whole lesson is that this exact judgement call is settled by a 3× screenshot taken
*before* the painter, not by a plausible margin.

### R2 — A travelling shadow that follows the card across the table
**Fails ★4, in a new dress.** The board is `TablePlate`: a chart inked onto a scorched
table, with burn painted at `Color(0.04, 0.02, 0.012)`. A soft black ellipse crossing
that surface is a dark blot on a dark, high-contrast painting — camouflage, exactly
like the ink spatter. Making it read means going opaque, at which point a hole is
sliding across the war chart. ✦2 works precisely because it does **not** do this: it
lands in a lane slot, where the shipped `ContactShadow` already proves a shadow reads,
and it moves in scale and alpha rather than travelling.

### R3 — A true two-sided flip on the play (★5's original shape)
**Still blocked, now for two reasons instead of one.** The pitch's objection stands —
`play_wax_press` owns the seated card's `scale` — and 2026-08-03 added a second:
`Container.fit_child_in_rect` resets a child Control's `scale` and `rotation` to
identity on every sort, which is why `_start_compact_morph` rides `modulate` and
nothing else. Both halves of a real flip want to own scale on a live, container-parented
node. ✦5 is the honest substitute and does not pretend to be the flip.

### R4 — A stain, signature or counter-seal on the hand card's paper on refusal
This is the ★4 inversion everyone reaches for — *"the token had no paper, but the hand
card does!"* — and it does not survive measurement. The hand card at rest renders
162×216, and the sheet is nearly fully occupied: art plate, `InkCartouche` name banner,
a rules box 182 px wide in card space, three seals, keyword stamps in the bottom
margin. The only true bare parchment is the margins and the rules well, and the
resting fan **crops the card at the screen fold just above the rules box** by design
(`_layout_hand`'s `PEEK 92` is tuned to exactly that). So a paper mark would have to
live in a ~15 px margin, on the third of the card that is off-screen at rest. Rejected
— but recorded, because this *is* the one place a paper beat could live if someone
finds a reason big enough to justify moving the fold.

### R5 — Rarity gilt participating in the commit
`_apply_gilt_foil` is hand-only and swept only by the lean driver, so a rare's leaf
catches light on hover and drag and then stops. That is correct and should stay. The
shine is information about a **pull** (`rarity_reveal`'s reasoning, and the pitch's
★2: *"if everything glinted a rare would look like a common again"*). A play is not a
pull. Making a rare's play louder than a common's is win-more, which this project has
a standing rule against.

### R6 — Anything else on the landing
The landing already fires **seven devices inside 70 ms**: the press squash, the
impression ring, the ground ring, the dust streak, the lane wash, the station flash
and the contact-shadow bump. The pitch's §4 verdict applies verbatim — *"adding volume
to generic effects makes them more generic, not cooler."* Note that ✦2 and ✦3 are not
exceptions: ✦2 **replaces** a wrong behaviour on an existing node and ✦3 **moves** an
existing cue. Neither adds a device.

---

## 5. Bugs found, not missing flourishes

These are defects, not taste. The first two are certain from control flow alone — no
screenshot needed to establish that they happen, only to judge how badly they read.

**B1 ▲ The shadow arrives before the body.** `_place_card_in_slot` → `_slot_set_card`
sets `ContactShadow.visible = true` on the commit frame; `_play_landing_pop` then
flies the card for 0.12–0.38 s and removes it from the cell with a bare `remove_child`
rather than `_slot_take_card`, so nothing hides it. A 184×48 px ellipse at effective
alpha 0.56 lies in an empty square with nothing above it, every arced arrival, both
sides. Pre-existing for dealt enemy creatures; **multiplied across every player
creature play by the 2026-08-03 `with_arc = true` switch.** Fixed for free by ✦2.

**B2 ▲ The play cue leads the stamp by 136–396 ms.** See ✦3's table. Also a
2026-08-03 side effect: `with_arc = false` put the press ~16 ms after the cue, and
nothing moved when the arc came back on.

**B3 ● Every play refusal is silent.** `_refuse_play` plays no cue; the game's only
`"refused"` sound guards discard marking. See ✦7a.

**B4 ○ The gilt sweep is never returned to rest.** `_disarm_lean` stops calling
`_sweep_gilt` but never zeroes it, so the `tilt` uniform keeps the last drag value.
At the ±0.35 rad clamp, `pos = 0.5 + 0.35 × 1.7 = 1.095` against a `band` range of
`[0, 1.35]` — the rake parks in a corner instead of crossing the sheet. A rare or
uncommon that you picked up and put down sits in the fan mis-lit until the next hover
re-arms the driver. One line in `_disarm_lean`.

**B5 ○ Two reverted painters left `.uid` orphans.**
`scripts/ui/painters/InkSpatter.gd.uid` and `SealCrack.gd.uid` survive the ★3/★4
reverts with no `.gd` beside them. Repo litter, harmless, trivially removable.

**B6 ● (restated, already known) `_play_armament` still carries two un-funnelled
refusals.** `tools/_probe_card_play.gd`'s header documents this as a standing failure:
both are defensive duplicates of gates `_on_card_played` already funnels, so no player
reaches them today — but they return the card on the plain reflow tween, which is what
a refusal looked like before the funnel existed. One-line fix each.

---

## 6. Verification

`tools/_probe_card_play.tscn` gates correctness (round trip, bookkeeping, refusal,
the clock, one rotation writer) and `tools/_shot_card_play.tscn` gates the read — 13
numbered frames, mid-flight waits expressed as fractions of the measured arc so
retuning moves the frames instead of invalidating them. Both already exist. Frames to
add, one per item:

| item | frame |
|---|---|
| ✦1 | the Command seal at the bite, and 100 ms later at rest |
| ✦2 | the destination slot at 30 % of the arc — the pool wide and faint with the card still in the air |
| ✦3 | none (audio) — verify by ear, and by `tools/_probe_audio_cues.gd` after the ownership sweep |
| ✦4 | one affordable and one unaffordable card side by side, on the worst-case art |
| ✦5 | the fold at ~50 %, with the token already clear of it |
| ✦6 | the exhaust at `burn ≈ 0.5` |
| ✦7 | the failed press, beside ✦1's successful one |

Shot harnesses must force `UserSettings.reduce_motion = false` — this machine's saved
settings have it ON, and `_play_landing_pop` additionally bails its whole arc under
Reduce Motion *and* under headless, so a headless capture photographs a gesture that
never happened.

**The method note from every pass this week still holds, and this document is an
argument for it:** the arithmetic above rules items *out* cheaply and reliably, but it
has never once ruled an item *in*. Only a screenshot has done that. Budget the shot
before the build.
