# THE STRIKE — a unified design (2026-07-30)

Four-lens design pass (material/staging · motion/camera · FX/audio · systems/legibility)
on the single most-repeated beat in the game: one creature striking another.
Every claim below was re-verified against live code. **Nothing here is built.**

Read with: `docs/ANIMATION_COOL_PITCH_20260717.md` (★1–★13, and the ★3/★4 reverts,
which are the hard constraints), `docs/COMBAT_LEGIBILITY_20260728.md`,
`docs/RULE_FX_PASS_20260728.md`, `docs/ANIMATION_AUDIT_20260716.md`.

---

## 0. THE THESIS

> **A strike is a COLLISION that leaves a MARK.** Two pinned sheets lever off the
> war table and meet in the seam between the lines; the blow is written into the
> one strip of board that is empty enough to read it; and the mark stays on the
> table for the rest of the fight.

Three lenses arrived at the seam independently and for different reasons — it is
where the bodies must meet (motion), it is the only art-free receiving surface on
the board (FX), and it is where a wooden table takes a load (material). **The seam
is the design.** Everything else is what a heavy falling sheet can move.

---

## 1. WHY — the defects, all measured, all verified

| # | Defect | Evidence |
|---|---|---|
| 1 | **Nothing ever touches.** | The seam between opposing front cards is **42 px** (`_make_lane_slot`, token 200×150, `CLASH_GAP` 30, VBox sep 6). `play_attack_lunge` drives **26 px**. |
| 2 | **The blow decelerates into contact.** | `Card2D.gd:4413` — the drive is `TRANS_QUAD` / `EASE_OUT`. The strike is at its slowest when it lands. |
| 3 | **The hold does not hold.** | `await _short_pause()` suspends the *coroutine*; `_lunge_tween` keeps playing. The 186 ms "comprehension window" on a chip hit is 186 ms of the attacker sliding home over a number that finished rendering on frame one. |
| 4 | **There is no contact point anywhere in the code.** | `_spawn_impact_burst(_card_center(defender), …)` erupts from the middle of full-bleed art — the exact surface ★4's spatter died on. |
| 5 | **The wind-up is a monologue.** | 90 ms in which exactly one card moves 7 px. The defender is inert until *after* it has been hit. This is the mechanical source of the "damage from nowhere" read the whole legibility pass has been chasing from the other end. |
| 6 | **The lane dwell is undrawn.** | `LANE_DWELL` 300 / `LANE_DWELL_KILL` 520 ms per lane, in which nothing moves at all. 2.4–4.2 s per round of unspent screen time. |

---

## 2. THE EXPOSURE SHEET

`t = 0` at contact. Contact is at `LUNGE_APEX`, **180 → 195 ms** after the lunge
begins. All durations via `Motion.time()` — see §7 Rule 1.

### 2.1 WIND — t −195 → −85

| element | detail | class |
|---|---|---|
| Attacker levers up | −9 px back, roll **−0.05·s rad**, lateral **+8 px inboard** | DECOR (roll/lateral) |
| **Contact shadow separates** | slot's `ContactShadow` α −0.20…−0.35, scale ×1.06…1.12, offset 3 px | DECOR |
| **THE BRACE** *(t −155 → −85)* | **defender leans +4 px INTO the blow, roll +0.035 rad** | DECOR |
| Edge heat | attacker's leading 18 % lights (heavy only) — existing `Motion.flash_material` + 1 uniform | DECOR |
| **AUDIO: wind** | `strike_wind` @ −90 ms, `1.06 × phrase`, −17 dB (−21 foe) | INFO |

> **THE BRACE IS THE CENTREPIECE, AND IT COSTS ZERO MILLISECONDS.** It fills a
> window that already exists and does the one thing the beat has never done:
> identify *both* parties before the blow. It also makes a mutual trade and a
> one-sided blow look different from frame one. If exactly one thing ships from
> this document, ship the brace.

### 2.2 DRIVE — t −85 → 0

`LUNGE_STRIKE` 90 → **85 ms**, easing **QUAD-out → EXPO-out**, `SEAM_REACH` 26 → **24 px**
(capped so the leading edges never close past ~11 px).

EXPO-out front-loads the distance: the last 20 ms covers ~4 px, so **the card is
effectively stopped at the contact frame with no freeze at all.** That is a
perceived stop, available on every blow, for free — and it is why chip hits need
no hitstop (§2.4).

### 2.3 CONTACT — t = 0. The fused window: **≤4 channels, ≤2 numerals, 0 words.**

Fixed contents, fixed order:

1. **The thorns caltrop, FIRST.** Thorns fires *before* the blow in code
   (`Combat.gd:5960` vs `:5994`) and nothing on screen conveys it. A short reversed
   rubric from the defender's edge into the attacker, ~⅓ the overkill stroke's
   length. Ordering is the entire point: the defender bit first.
2. **The attacker at extension**, stopped by the EXPO curve.
3. **THE BITE** — `StrikeMark`, a seeded wedge laid *across* the seam.
   `length = clamp(26 + atk·5, 26, 74)`, `body = clamp(7 + atk·0.6, 7, 13)`, ±4° lean.
   Drawn on `LaneAftermath`'s **ground** instance (`draw_marks = false`, added
   *before* the lane rows) — so it is **drawn under the bodies at t 0 and REVEALED
   as they part.** Uncovered, not drawn: you don't watch a mark being made, you see
   it when the bodies separate. The heaviest blows have the longest reach → the most
   occlusion → the slowest reveal, which correlates for free.
4. **The impact spark, relocated to the real contact point** — `_strike_contact_point()`,
   where the attacker→defender segment crosses the **defender's rect boundary**
   (orientation-agnostic, so Guardian redirects and back-row reach are handled).
   Existing `impact` preset, retinted to the side hue with a **white-hot core**
   (the CONTRAST RULE — a lone warm burst is camouflage on a warm table).
5. **The numeral, emitted FROM the HP wax seal**, travelling ~34 px out along the
   blow axis — which post-separation puts it in the seam, on bare dark wood, so a
   3 px ink knockout replaces the 6 px cartoon outline. `font_stat`, board-parented.
6. **The seal punches on the same frame** it sheds the numeral. One frame, one event.
7. **Table dust** out of the gutter, thrown sideways along the seam, gravity down
   (ATK ≥ 2). **The only out-of-plane event in the impact frame** — everything else
   is flat.
8. **AUDIO: crack + body** (+ room on heavy blows *against you*).

Free channels running concurrently — a different modality is redundancy, not load:
audio, the seal's value change, the log row.

### 2.4 THE STOP — a real freeze, not a scheduler wait

Generalise `hold_lunge_apex`'s pattern (pause the running tween; one owner on
`position`, time simply stops) to `hold_strike_frame()`, called on **both** bodies.
**The world freezes** — both position tweens, both scale tweens, the lane dolly, the
spotlight. The one thing that keeps moving is the numeral: it is the payload.

| class | freeze | read beat | trauma |
|---|---|---|---|
| CHIP (< `HEAVY_HIT_DAMAGE`) | **0** | 70 | **0.00** |
| HEAVY (≥ 5) | 110 | 90 | 0.20 |
| LETHAL | 170 | 110 | 0.32 |
| LETHAL + overkill reaching a body | 170 | 110 | 0.42 |
| FIGHT-ENDING | 550 (`KILLING_BLOW_HOLD`, unchanged) | — | 0.85 |

**Chip stop is 0, and that is where this entire pass is funded from.** A freeze on
every blow is not a freeze — hitstop is a contrast device meaning *this one was
different*; universal micro-stop makes it a property of the engine, and then heavy
and lethal have nothing to be heavier than. Same argument that killed the uniform
0.34× slowdown.

**Shake is directional.** `add_trauma(amount, axis)` projects the noise into an
(along, perp) basis with `perp *= 0.30`. A clash rattles the table *along the lane*;
a spell or face hit stays isotropic — a free permanent distinction between "someone
got hit in a lane" and "something happened to the army."

**Board rotation** (closes the open C5 item): `SHAKE_MAX_ROT = 0.012 rad`, armed only
above trauma 0.45 — lethal and up. `_board_container` is a `PRESET_FULL_RECT` Control
at origin and `_hud_layer` is a CanvasLayer with a screen-space offset, so one
pivot correction serves both.

### 2.5 SEPARATION — t 0 → ~430

Recoil shove 45 ms (+15 px, scale 1.14/0.88, **squash along the blow axis only** —
paper does not get wider when hit), settle 190. Attacker settles home in 160 ms;
**its roll comes home in 200 ms.** That 40 ms lag *is* the follow-through — the angle
trailing the position makes the return read as recovery rather than rewind.

The defender never returns square: it keeps **+0.006…0.016 rad** of the blow, capped
at ±0.02 total. **Wear as GEOMETRY, not as pigment** — geometry survives on top of
arbitrary Midjourney art; pigment is what ★4 proved doesn't.

### 2.6 THE LEDGER — the lane dwell, currently empty

`LANE_DWELL` 300 → **`FOCUS_TRAVEL` 140 + `LANE_REST` 170**. The spotlight rect
*tweens* instead of cutting (`ClashLaneFocus.focus_lane` currently assigns
`_focus_rect` outright and tweens only `_strength`). Kill lanes get `FOCUS_HOLD` 200
first → 510 ≈ today's 520.

This converts 140 ms of forbidden-band stillness into travel, gives the eye a saccade
lead, and turns eight cuts into one sweep down the line. **~8 lines of code.**

Content, staggered ~40 ms, in a fixed reading order — *what the attacker gained → what
the field gained → what the ledger owes*:

- **Permanent stat grants** (Rampage, struck-growth, veterancy) land as a **seal
  re-press on the attacker — no float, no word.** The eye is already there. This
  deletes `"RAMPAGE +N"` from the word budget outright.
- **Veterancy's names** are genuinely ceremonial and rare; they earn the one word slot here.
- **Gold / heal / face payments TRAVEL** — the numeral leaves the body and flies to
  the plate it credits. Removes the worst eye-demand in the game, costs no time.
- Everything else → rail + log.

### 2.7 LETHAL, and the record

The bite is **replaced by a full-width vermilion CANCEL BAR** (200 × 11 px) across the
victim's near edge; the corpse burns beneath it (★1). The lethal numeral does **not**
travel — the seal it would leave is about to burn, so it stays and the bar strikes
*through* it. **The last number a body shows is cancelled with the body.**

Colour never carries this alone: a deuteranopic player reads **short nick vs
full-width bar**. Vermilion is reserved for death and is deliberately *not* partisan —
a death is the record's news, not a side's. (Collision caught in review: the foe's
ember at `(0.80,0.30,0.16)` sat ~0.03 from the rubric's vermilion, so an ordinary
enemy blow read as a cancellation. Foe ember moves to `(0.92,0.42,0.14)`.)

Residue is handed to a new `LaneAftermath.bites[]` (the `_battlefield_scars` pattern,
cap 6/lane) — **but only HEAVY and lethal blows leave one.** A cap alone is not the
safeguard: at 8–13 strikes a round a cap of 6 is blown in two rounds and the seam
becomes a smear. **The rung is the safeguard.** Deaths already leave evidence
(`_draw_scar`); strikes leaving none is the gap.

### 2.8 THE PINS — zero cost per strike, and they make everything else legible

Two brass tacks at each sheet's trailing corners, painted by the **slot** (extend
`StationMark`), revealed by `_slot_set_card` beside the contact shadow. Drawn once at
placement; **0 per strike.**

They are the fulcrum that makes every rotation read as physics instead of drift.
Without them a rotating card is a wobble; with them it is a sheet levering off the
table. Three free consequences: **hinge direction is a colourblind-safe side cue**
(yours pinned near, rearing up over the seam; theirs pinned far, rearing down),
the map screen already pins its chart with corner tacks so the idiom is the house's
own, and ★1's burn-death improves for nothing — a dying writ burns out from under its
own tacks, which stay on the empty table.

**The pins are a hard dependency of the centred-pivot roll (§3), not a nice-to-have.**

---

## 3. THE PIVOT — resolved

The material lens wanted `pivot_offset` on the trailing edge for a lever read. It is
written by six paths on the same node (`play_attack_lunge` :4400, the scale tween,
`play_hit_recoil` :4482, `_die` :4136, `_update_field_grab` :5414, `_start_drag` :5285)
and it is a **layout** property: changing it re-bases the transform and teleports the
node by up to half its size on that frame. `_die` fires *during* a lunge on every
mutual trade, so the collision is a common path, not an edge case.

**Resolution: keep the pivot centred.** Rotation about an off-centre point ≡ rotation
about centre + a translation, and the two-axis arc already bakes that translation in:

| component | wind | drive | return |
|---|---|---|---|
| longitudinal (toward foe) | −9 px, SINE-out | +24·s px, **EXPO-out** | BACK-out 160 |
| lateral (inboard) | +8 px, SINE-out | −6 px, SINE-in-out | BACK-out 180 |
| roll | −0.05·s rad, SINE-out | → +0.07·s rad, QUAD-out | BACK-out 200 |

Differing easings on the two translation axes bend the path — **no Bezier, no path
object.** At θ = 0.055 the leading edge travels ~30 px and the trailing ~22 px: a 27 %
differential across the sheet, which *is* the lever.

Lateral sign is `signf(1.5 - lane_idx)` — lanes i/ii step right, iii/iv step left, so
the front reads as a line collapsing inward on the seam rather than four independent
twitches. **The roll's sign flips by side** (yours rear up-from-below, theirs
down-from-above) — that is the geometric side cue, and it must not be applied with one
sign to both lines.

---

## 4. THE ARBITRATION — four slots

The blow's beat belongs to the causal chain, and that chain is **a single path through
space**: attacker → contact → defender → body behind. Everything off that line
(adjacent Man-Trap, a spawned token, plate heals, defection redeploys) is a
*consequence*, not part of the blow, and does not get the blow's frame.

| slot | window | contents |
|---|---|---|
| **0 — CONTACT** | 0–70 ms, fused | ≤4 animating actors inside one ~250 px fixation. Fixed order per §2.3. **No word.** |
| **1 — CARRY** | 55–230 ms, inside the hold | **At most ONE travelling mark**, and it must physically travel: the `RubricStroke`, the thorns caltrop, or the counter's tracer. Because it travels it is *one target with duration* — which is what legalises it inside the condemned band. |
| **2 — LEDGER** | the lane dwell | Everything off the causal path (§2.6). |
| **3 — RECORD** | async | Rail orb + chronicle row. Never competes for time. |

**Priority when two claims contend:** lethality → player agency (a rule the player
*bought* outranks one the encounter owns) → novelty (hasn't fired this fight) →
spatial economy (nearer receiver wins) → ties break toward the attacker.

**Hard debounce: one rule id may take a Slot-0/1 presentation once per lane pass.**
Repeats are Slot 2/3. This closes the "three lanes overkilling in one clash = a page
struck out" gap without a magic cap number. Identical marks in one clash stagger
~40 ms so N firings read as one escalating phrase.

### The caps, and why they're defensible

> **≤4 of the six contended channels may carry NEW propositional content in the 0–70 ms
> window. Within that: ≤1 word, ≤2 numerals.**

Multiple-object tracking caps at ~4 (Pylyshyn & Storm), subitizing at 3–4 (Piazza),
retention at ~4 (Cowan). Three independent literatures, one number.

> **CAP-D — THE ARITHMETIC LAW: the numerals a single strike prints must SUM to the
> attacker's `effective_atk()`.**

This already holds (`Card2D.take_damage:3608` caps the victim's numeral to life
actually lost, precisely so overkill's two numerals add up) and it is the best teaching
device in the build — the blocker economy is *derivable* from one firing. A designer
who wants a "RAW 9" beside a "−5" has broken it.

**ARMORED becomes arithmetic, not a word:** draw `-6`, rule through it with a 2 px
rubric tick as the reaction lands, print `-5`. Strictly better than a `BLOCKED N` chip
— it makes the reduction visible *as arithmetic*, preserves CAP-D, and costs nothing
from the word budget.

**The word budget (ONE, this order):** a negation the player would otherwise read as a
bug (`LAST STAND` / `HELD` / `SHIELD` / `TAKES IT`) → a ceremony (veterancy, Slot 2) →
nothing. **`OVERKILL` correctly has none** — its two numerals teach it, and they add up.

---

## 5. THE WEIGHT LADDER

| | 1 ATK | 3–4 | HEAVY ≥5 | LETHAL | OVERKILL | SHIELDED 0 |
|---|---|---|---|---|---|---|
| roll | ±0.02 | ±0.035 | ±0.055 | ±0.055 | — | ±0.055, **rebounds** |
| drive | ×1.0 | ×1.2 | ×1.6 | ×1.6 | — | ×1.6, short bounce |
| shadow separation | — | −0.20 α | −0.35 α | −0.35 α | — | −0.35 α |
| seam dust | **none** | 6 | 14 | 14 | — | 5, **no sparks** |
| bite | **none** | none | wedge | cancel bar | + rubric | none |
| freeze / trauma | 0 / 0 | 0 / 0 | 110 / 0.20 | 170 / 0.32 | 170 / 0.42 | 0 / 0 |
| audio layers | wind+crack | +body+tail | +room | +tear | | thud into cloth |
| persistent skew | +0.006 | +0.010 | +0.016 | n/a | +0.010 | **0** |

**At 1 ATK almost nothing happens.** A poke is a poke; the numeral carries it. The
whole vocabulary is *earned by size* — that is the anti-noise discipline the ★4 revert
demands, and it is why the ladder starts at zero rather than at a small version of the
big one.

**Shielded-zero inverts the actor.** The defender does not buckle at all — **the
attacker rebounds**, its own lever failing to straighten. Force with nowhere to go
returns to the striker. Materially exact, the same tween with an inverted sign, and it
distinguishes *blocked* from *missed* by **who moves**, not by colour.

---

## 6. AUDIO — one strike, one voice group, one owner

**Weight is LAYER COUNT, not a volume knob.** This is how AAA impact scales, and it is
*informational* — you can hear a heavy blow before you read it.

| layer | cue | fallback TODAY | t | pitch | dB | fires |
|---|---|---|---|---|---|---|
| wind | `strike_wind` | `card_discard` | −90 | `1.06 × phrase` | −17 | always |
| **crack** | `strike_crack` | **`card_play`** | 0 | `1.00 × phrase` | −2 | always |
| body | `strike_body` | `hit` | +8 | `body_pitch × phrase_half` | −5…−1 | atk ≥ 3 |
| tail | `strike_debris` | `card_draw` | +55 | `1.28 × phrase` | −20 | atk ≥ 3 |
| room | `strike_room` | `hit` | +70 | `~0.55 ×`, **no phrase** | −23 | atk ≥ 5 **and against you** |
| kill | `creature_death` | `death` | +35 | `0.88 × phrase` | 0 | lethal |

`body_pitch = clamp(1.18 − card_data.hp × 0.035, 0.62, 1.18)`. **The board becomes an
instrument tuned by what is standing on it** — blow #400 into a Trebuchet sounds
nothing like #399 into a Goblin. The phrase climbs fully on the transient, half on the
body, **not at all on the room** — you transpose the top, not the bottom, and a room
does not change pitch.

**The best substitution costs nothing:** `card_play` — the card-slap, the best transient
in the library, currently used only when you *play* a card — becomes the strike crack.
A writ hitting the table **is** the sound of this game.

**Side is carried by composition, not pitch**: the room layer plays only on blows
*against you*, and the foe's wind is 4 dB quieter. A pitch offset for side would overlap
the phrase's own range and turn two facts into one ambiguous one.

**Music: no duck on an ordinary blow, and none on a kill.** `duck_music` has a 0.7 s
release; at 8–13 strikes a round the ducks overlap continuously and you have quietly
turned the music off and added an artifact. Framing every event frames none. The
fight-ending blow keeps its −9 dB duck and remains the only strong duck in a clash.
**The real answer to "should a blow duck the music" is: no — fix the blow.** What makes
a hit read over a track is a fast transient and high-frequency content, not headroom.

**`play_sfx` needs a shuffle bag.** `streams[randi() % size]` with 2 clips is a 50 %
chance of immediate repeat — the most fatiguing possible arrangement. A per-cue bag that
refills on exhaust and never re-draws the last clip is ~10 lines and **improves every
cue in the game.** The precedent is already in the file: `play_music_random` excludes
the current track for exactly this reason; the idea just never reached `play_sfx`.
**Cheapest audio win in the repo. Build it first.**

### The ownership change (documented contract — needs sign-off)

CLAUDE.md currently splits strike audio: survivors sound in `Card2D._flash_hit`, kills
in Combat. That split has to go, because `_flash_hit` knows nothing about the blow's
size, the attacker, or the side — three of the four variation axes — and because
`take_damage` (`Card2D.gd:3646`) routes lethal to `_mark_mortally_struck()` and only the
`else` calls `_flash_hit()`, so **the killing blow gets no impact transient and is the
only strike that doesn't ride the clash phrase.**

- **Moves to Combat:** a new `_play_strike_audio()` at the impact beat (replacing the
  lone `creature_death` call at `Combat.gd:6016-6018`; `death_cue_played = true` stays
  exactly where it is), plus `_play_strike_windup()` at the lunge.
- **Stays in Card2D:** `_flash_hit`'s visual half unchanged; `_die`'s `death` cue for
  non-clash deaths; and `hit_creature` **gated on `strike_damage_active == false`**.
- **The gate is verified correct.** `strike_damage_active` is raised in exactly one
  place — `_deal_creature_strike_damage` (`Combat.gd:2013-2015`) around
  `defender.take_damage(amount)` — so the set it excludes is precisely the set Combat
  now owns. The ward redirect recurses *inside* that window, so it correctly stays
  silent in Card2D. Its semantics widen from "this is a strike, so `effect_immune`
  doesn't apply" to "Combat owns this damage end-to-end, semantics *and* audio."

> **Proposed CLAUDE.md replacement:** ONE STRIKE = ONE VOICE GROUP, ONE OWNER. The
> prohibition is on two *owners* sounding one event — not on one owner using several
> voices.

---

## 7. THE ACCESSIBILITY CONTRACT

**The classification test, answerable at the call site:** *if this element did not
render, could the player still answer a Tier-A fact from what remains at the end of the
lane dwell?* NO → informational (always plays). YES → decorative (gates off).

**Tier A (model-breaking if missed):** who swung · at whom (*not* inferable from
geometry — Guardian redirect and `ward_by` move the hit) · did it die · how much left
the defender's HP.

- **Reduce Motion.** Informational motion becomes **a state change of the same
  duration — never a deletion, never a shorter one.** The attacker snaps to extension
  and snaps home; a snap doesn't induce motion sickness, a 180 ms arc can. The bite
  renders complete and dried at t 0. The numeral appears and the seal punches
  immediately. **Timing is invariant** — Reduce Motion must never become a speed
  setting, or the player who needs the most reading time gets the least.
- **The freeze is INFORMATIONAL and keeps its duration under RM** — deliberately the
  opposite call from `hold_lunge_apex`, which gates itself because the verdict banner
  carries that information independently. Here the freeze *is* the comprehension
  window. **Write the difference down or someone will "fix" it.**
- **Shake off.** Shake carries exactly one proposition and is always redundant with the
  numeral. **If you can only tell a kill happened because the screen moved, it's broken.**
- **Colourblind.** Every distinction must survive `Image.adjust_bcs(1, 1, 0)`. Side is
  carried by *direction* and *hinge geometry*; damage vs heal by *sign*; ordinary vs
  lethal by *short nick vs full-width bar*. Gate at 1280×720 over **both** substrates —
  token art and the dark gutter. Use `adjust_bcs`, not a per-pixel loop (3.24 M
  `set_pixel` calls blows the probe budget by itself).
- **anim_speed = Instant (3×).** **Rule 1: every element must be built from
  `Motion.time()`** — one unscaled literal re-creates the documented seventeen-chips
  bug (chips lived a literal 1.06 s against a 0.063 s strike). **Rule 2: degrade by
  DELETING the optional, never by overlapping the mandatory** — at `anim_speed ≥ 2.0`
  Slot 1 collapses into Slot 0 and the mark renders complete-and-dried. Byte-identical
  to the Reduce Motion treatment: **one code path, two triggers.**
- **Log-only / screen reader.** Every Tier-A/B fact must be reconstructible from the
  log rows alone. Three gaps today, all pure text: the overkill spill has **no solo log
  row at all**; the ward redirect's strike row and its `TAKES IT` status **name
  different cards**; and the counter never says *why* (the muster-counter is the newest
  and most counterintuitive rule in the game). Plus: **side must be in words**, not only
  in rim tint — the log is exactly where a colourblind player goes when the board failed
  them.

---

## 8. NET PARITY

> **A client may compute WHERE. It may never compute WHETHER or HOW MUCH.**

**Host-authoritative (must be in the clash log):** attacker/defender by `entity_id`
(never by position) · `n` = HP actually removed · `ahp` = attacker HP after (carries
thorns/reflect/counter without a second event) · `ctr` (it changes *choreography* — no
position recoil on a still-lunging attacker) · **the receiver of any mark that
terminates on a body.**

**Local flourish:** particle counts, spark direction, shake magnitude, the spotlight,
costume *animation* (never costume *state*).

**The brace must ride the `{l}` lunge entry, not `{d}`** — the client learns the target
only at `{d}`, which is *after* contact. `_net_log_lunge` needs the defender eid or the
brace is solo-only and two clients see different choreography for the same blow.

**Ordering hazard:** `_net_fx_queue` lands with the trailing board sync, so a word
belonging to strike #2 can arrive after strike #7. **Anything on the fx-queue channel
is Slot-3 by definition on the client. Slot-0/1 elements must ride the clash log.**

**The seed is derived from the log index, not a local counter.**
`strike_seed = hash(attacker_eid, defender_eid, round_number, clash_log_index)` — the
log is replayed in order on both peers, so the index is derivable and the mark is
identical on both screens. Seeded, never random: replays match, shot harnesses
reproduce, and four independent axes guarantee no two blows in a run share a hand.

**Skirmish has no `_impact_hold`, no `_lane_dwell`, no `_round_beat`** (a beat suspends
the turn machine; a label does not). **Therefore Slot 2 must degrade to labels without
losing a Tier-A/B fact** — it can, by construction, since Slot 2 is only off-causal-path
content. Any design whose legibility depends on the dwell is solo-only and must say so.

---

## 9. THE BUDGET

Derived from the constants and reproducing the captures within ~5 %, so it can price a
proposal before it is built.

| | current | proposed | Δ |
|---|---|---|---|
| chip ×10 | 180 + 186 = 366 → **3660** | 195 + 0 + 70 = 265 → **2650** | **−1010** |
| heavy ×2 | 402 → 804 | 395 → 790 | −14 |
| lethal ×1 | 410 | 475 | +65 |
| **strike total** | **4874** | **3915** | **−959** |
| lane time (6 live columns) | 2020 (all stillness) | 2060 (700 travel + 1360 rest) | +40 |

**Net −919 ms per clash.** The worst-board round drops ~15.7 s → ~14.8 s **while heavy
and lethal blows get 47 % and 65 % more stopped time.** The pass is funded entirely out
of the chip hold, which was buying nothing.

**The ceiling, for anyone who wants more:** every 10 ms added per strike costs 130 ms
per round. A 100 ms flourish costs 1.3 s per round on a clash already 57 % past
Nielsen's 10 s threshold — and **the skip affordance is already spent** (hold
`ui_accept` → ÷5). You are not short of time. You are short of *concurrency*, and you
have 2.4–4.2 s per round of undrawn lane dwell sitting there.

**Tripwire:** if `_probe_clash_trace --mode=trace` reports the 16-body end-turn→playable
above **16.5 s**, the change is over budget however good it looks. **Judge by the
frame-gap list, not wall clock alone** — hiding work inside a synchronous block that
renders nothing improves neither.

### The forbidden band, restated

**100–500 ms is condemned for a GAP, not a duration.** Causality collapses past ~100 ms
(causal pairs average 66.9 ms apart, non-causal 164.7 — Straube & Chatterjee 2010); the
attentional blink means two attention-demanding targets 200–500 ms apart cannot both be
registered (Dux & Marois 2009). Simultaneously too slow to fuse and too fast to
separate.

> **Emptiness in 100–500 ms is forbidden. Occupancy is fine.** A continuous motion is
> one target with duration, not a second target.

And the trap, so nobody proposes the easy fix: **a uniform slowdown cannot solve this.**
÷3 moves 130 ms to 382 ms — out of the causality window and *deeper into the blink*.

---

## 10. COST, AND THE CUT ORDER

Per front-row strike: **−2 to −4 antialiased `Line2D`** (the melee tracer, the
documented-unbatched primitive) **+1 painter** (`draw_colored_polygon`, no AA) **+0–1
particles, +1–3 audio voices.** Node count goes **down** in the common case.

**The melee tracer is deleted** — three lenses independently. The lunge already owns the
swing; a bezier on the same frame is the same sentence twice. **One exception, and it is
real: the back-row attacker.** Centre-to-centre is ~348 px with an occupied friendly slot
in between; a 24 px drive from the back row reads as shoving your own ally in the back.
The rule as one number: **fire the tracer when centre-to-centre exceeds
`MELEE_SPAN_MAX = 260 px`** (front-to-front is 192, back-to-front ~348). No adjacency
logic, no row arithmetic, and it generalises to any future reach. Sniper, face strikes
and every spell bolt were never in scope.

**Cut order under budget:** StageLight lift → seam dust burst (downgrade to the residue:
*burst for the moment, scuff for the record*) → edge heat → shadow separation → the room
audio layer → residue cap 6 → 3.

**Never cut:** the brace · the bite · the crack transient · the numeral · the pins.

---

## 11. BUGS FOUND — ✅ ALL FIVE FIXED 2026-07-30

Verified against live code, independent of any animation work, and repaired in the
same session. Gates green afterwards: `_probe_parsecheck` · `_probe_overkill` (16) ·
`_probe_net_clash` · `_probe_anim_clock` (13) · `_probe_muster_delay` ·
`_probe_status_riders` (81) · `run_safe_probes` (parsecheck + copy_lint + event_art).

**A sixth, unrelated and pre-existing, was found by the compile gate and fixed:**
`Combat.gd:8502` held `bool(scar.ge|("is_enemy", true))` — a literal `|` where the `t`
of `.get(` belonged, in the `LaneAftermath` scar-spec builder. It was a **parse error,
so the entire game would not load.** Not introduced by this work (the file was
observed shifting under two reads during the pass). Worth knowing that a stray
character in a 30 k-line file costs the whole build and that only `_probe_parsecheck`
catches it — `--check-only` is documented to have passed a `Combat.gd` that could not
be `load()`ed.


1. **`_apply_creature_struck_growth` is passed the wrong number.** `Combat.gd:6022`
   passes `atk` (the raw post-mitigation blow), not `strike_damage`. The function
   early-returns on `strike_amount <= 0`, so it *intends* to gate on real damage — but a
   warded or shielded defender still arrives with `atk > 0`. **A Royal Guard behind a
   ward grows +1 ATK from a hit it never took**, and the numeral is on a different card.
2. **`anvil_spawn` has the same defect.** `Combat.gd:5792` gates only on `survived`,
   while its neighbour `reflect_strike` (`:5788`) correctly gates on `damage_taken > 0`.
   A warded Bramble Stockade splinters off a token from a hit it never absorbed.
3. **The client draws the pierce mark into empty space.** `CombatNet.gd:2099` admits it
   in its own comment: the host's log carries no spill target, so the client re-derives
   one, and `_pierce_body_behind` returns `null` for any **back-row victim** — falling
   back to `v + dir.normalized() * 156.0` while the host draws to the hero plate. Two
   peers, same blow, different mark. **Fix: one field (`pr` = receiver eid, −1 for the
   plate).**
4. **Screen shake double-counts every heavy blow.** `creature_hit_feedback`
   (`Combat.gd:24371`, called from `Card2D.take_damage`) and the explicit
   `screen_shake(6.0)` in `_creature_attacks_creature` both fire on one lethal — ~1.18
   trauma, clamped to 1.0, 18 px on a mid-round trade. The comment at `:24375` admits
   the layering. **The bug is not accumulation, it is double-counting a single event.**
   Fix: `Combat.strike_shake()` becomes the single owner; `creature_hit_feedback` guards
   on `strike_damage_active` (one line, no new state) so spell/Thorns/Doom damage keeps
   its own correctly-owned shake.
5. **`_die()` does not kill the lunge tween.** `Card2D.gd:4120-4137` sets
   `_idle_bob_enabled`, `mouse_filter`, `pivot_offset`, `z_index` — and touches no lunge
   tween. Harmless today *by luck*; the moment the lunge owns `rotation`, the death
   flourish's `rotation + randf_range(-0.5, 0.5)` (`:4195`) and the roll-home are two
   writers on one property. **`_die` fires during a lunge on every mutual trade.**
   `_lunge_hold_active` needs clearing there too, or `_combat_tween_active()` reports
   true against a corpse.

---

## 12. THE ROTATION CHANNEL — the ruling

Both the material and motion lenses need `rotation` on a battlefield token. Traced to
completion:

- `_arm_lean` has two call sites — `_start_drag` (`:5279`) and `_on_mouse_entered`
  (`:5045`), the latter **inside `if not is_on_battlefield:`**. `set_hand_target`
  (`:4301`) and `_hover_tween` (`:5078`, `:5129`) are hand-only.
- Every other writer is an **EXIT**: `_play_banish_exit`, `_animate_dismiss`,
  `_animate_card_to_discard`, `_net_despawn_creature`, and `_die`'s two flourishes.

**One live-token writer exists that neither agent found: `_play_landing_pop`**
(`Combat.gd:20313`) sets `card.rotation = randf_range(-0.07, 0.07)` on arrival and tweens
it to 0 (`:20332`).

**It cannot collide with the strike roll, and the reason is structural: the muster
delay.** A body that lands in round N has `ready_to_swing = false` and cannot initiate
until `_start_round` sweeps it in round N+1. Landing and striking are in different
rounds by construction.

**Two windows do overlap and need the guard:** a **Swift** body (`ignores_muster_delay()`)
played and swung in the same round, and any freshly-landed body that gets **braced** or
struck in that round's clash. Two tweens on one property both write it and fight.
**Guard: kill the landing tween before arming the strike roll** — the same one-liner
`_die` needs.

---

## 13. VERIFICATION

**Existing gates that must stay green:** `_probe_parsecheck.tscn` (the only real compile
gate — `--check-only` has shipped a `Combat.gd` that could not be `load()`ed) ·
`_probe_beat_spacing.tscn` (**this fails first, and correctly** — a new in-band constant
with no waiver fails; adding a beat means writing `kind` + `why`) · `_probe_anim_clock` ·
`_probe_overkill` · `_probe_status_riders` · `_probe_muster_delay` · `_probe_creature_fx` ·
`_probe_combat_telegraph` · `_probe_lane_focus` · the net probes · `_probe_coldentry
--mode=viamap`.

**New harnesses this change needs:**

1. **`_probe_strike_budget`** — stage ONE worst-case strike (piercing + rampage +
   lifesteal + defection into an armored, thorned, warded defender with a body behind and
   an armed counter) and assert inside one `_creature_attacks_creature`: callouts ≤1,
   Slot-0 numerals ≤2, animating Card2D nodes in 0–70 ms ≤4, and **CAP-D — the numerals
   sum to `effective_atk()`.**
2. **`_probe_strike_a11y`** — the same strike in four configurations (default /
   reduce_motion / shake off / anim_speed 3.0); every Tier-A fact retains ≥1 live carrier
   in each. Plus the unscaled-duration catcher: total lifetime at 3.0 ≤ 0.34× at 1.0.
3. **`_shot_strike_grey`** — greyscale gate at 1280×720 windowed via `adjust_bcs`,
   sampling separately **over token art and over the gutter**, measuring px² against the
   **750 px² revert floor** that killed ★3.
4. **Extend `_probe_net_clash`** — every Slot-0/1 element reconstructible from the log
   alone; **add the back-row-victim piercing case**, which today draws into empty space.
5. **Extend `_probe_beat_spacing`** — waivers with `kind` and `why` for every constant
   added. Non-negotiable; that file is the contract.

**Shoot it.** Every failure and miscalibration in ★1–★13 came out of a picture; none
came out of code review.

---

## 14. REJECTED — and why, so it isn't re-proposed

| rejected | why |
|---|---|
| **Ink spatter / stains on the token face** | ★4's revert. Nothing here marks the art — every mark lands in the seam. If anyone reads "material-correct spray" as "stain the card," that *is* the revert. |
| **Cracks drawn inside the wax seal** | ★3's arithmetic: 38 px seal − 18 px numeral ≈ **8 px of annulus**, and the seals are baked into the face texture — pixels, not paintable objects. The buckle survives because it is a **transform**, not a drawn line. |
| **Gilt flakes off the defender** | Verified: no gold leaf on a battlefield token. Its stat metal is deliberately dull bronze `(0.62, 0.50, 0.26)` — gilt is a *hand-card rarity affordance* (★2's whole argument: if everything glinted, a rare would look like a common). Inventing material is the ★4 failure. |
| **Paper fibre spray** | Same test — the art is full-bleed; there is no visible parchment to shed. The defender has no material to lose, so the spray is **pure physics** (light thrown by a collision) and makes no substrate claim. |
| **A blade arc / a bigger tracer** | The lunge already owns the swing; an arc is a weapon idiom in a record's voice, and adding volume to a generic effect makes it *more* generic. |
| **Tribe-coloured strikes** | A strike fires 8–13×/round vs a trigger's 1–2. Tribe-tinting every blow is colour salad, fights the gilt/ember side language, and steals meaning the trigger channel already owns. **The spray's colour is MATERIAL colour, not tribe colour.** |
| **Neighbouring cards nudged** | They sit in a `CenterContainer` inside an HBox — nudging means a second writer against the layout, and at 8–13 strikes a round the whole line jitters permanently. ★6's lockstep board shake is the physical answer, trauma-pooled so it can't compound. |
| **A per-strike board flash or a screen flash on kills** | Measured: **one point** of face damage produced +120 board redness and buried a death, its numeral and a PIERCING chip. The light channel is powerful *because* it is rare; 8–13 pumps a round is a strobe. |
| **A real `Camera2D`** | Buys true pan/zoom and costs layout, input hit-testing, and the `_card_center` → `_hud_layer` 1:1 mapping every combat FX depends on. A rendering-architecture project wearing a motion project's clothes. |
| **Parallax board/table** | The ground is painted *inside* `board_zone`. Separating it breaks ★6's lockstep contract to buy a few pixels of depth on a chart deliberately staged as a flat physical sheet. |
| **Springs for the strike** | Springs are for *interruption*. `LUNGE_APEX` being **derived** from the tween's phases is what makes the conductor's `await` agree with the animation — **a spring has no apex you can await.** |
| **A hand-keyed `AnimationPlayer`** | Zero scene-authored tracks by policy; every effect is diffable text. |
| **Universal micro-hitstop** | §2.4. A freeze on every blow is not a freeze. |
| **Ducking music per blow or per kill** | §6. Framing every event frames none. |
| **Wider random pitch jitter as the variation system** | It is what ships today and it is *why* blows read as samey-but-wobbly. Random within a narrow band reads as noise on one sound, not variety. |
| **Fusing the four lanes into one volley** | Perceptually more elegant; ruled against by the owner on 2026-07-28 after a five-agent audit, and every 07-29 fix is built on the serialized clash. |

---

## 15. CORRECTIONS TO THE RECORD

- **CLAUDE.md is RIGHT about battlefield tokens: they carry 38 px matte wax seals**
  (`_chart_seal(GameTheme.ATK_GOLD_SHIELD, token_metal, true)`, offsets 3..41, 18 px
  numerals — `Card2D.gd:919-946`). Two **stale comment blocks** immediately above
  (`:898-918`) describe a GemOrb design that the live code does not build, and they
  contradict each other. Delete them. The token is full-bleed art **and** wax seals —
  both true, and the distinction matters: no visible *parchment* (so nothing can be
  stained), but there **is** wax (so a wax chip knocked *off* a seal into the seam
  remains available, unlike a crack drawn *inside* one).
- **`POST_HIT_BEAT` / `HITSTOP_BEAT` are no longer the solo strike's beats.**
  `_impact_hold` replaced them on 2026-07-28. They survive mainly in `CombatNet`'s
  replay — which is precisely why the two presentations are drifting, and why the new
  stop must be a **function both paths call**, not a constant each reads.
