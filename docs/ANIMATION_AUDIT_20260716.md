# Animation Audit — 2026-07-16

Full inventory of every animation mechanism in the build, checked against how
the reference titles (Balatro, Hearthstone, Slay the Spire) and the Godot
community structure this layer, with a phased restructure plan at the end.

**Status (2026-07-16, same day): R1 + R2 SHIPPED.** `scripts/ui/Motion.gd` is
the shared beat clock (Combat's pacing consts alias it; Card2D lunge / recoil /
hit-flash / slump / death / sacrifice tweens build from it through
`Motion.time()`, so the Instant setting now scales tween and pause together —
and `LUNGE_APEX` is *derived* as anticipation + strike, 0.09 → 0.13, impact
lands exactly at full extension). GameTheme carries the trauma shake service
(`set_shake_target` / `add_trauma` / `shake_impulse`); `Combat.screen_shake`
delegates into it with a sqrt magnitude map, and forge_strike + the treasure
coin fountain fire small shell impulses. Verified: `tools/_probe_anim_clock.gd`
(16 checks, ALL PASS), `_probe_flow` (145 drivers, 0 fails),
`_probe_skirmish_combat` ALL PASS, `_shot_setpieces` renders clean.
**R3 + R4 SHIPPED same day.** R3: `Motion.ANTICIPATE/PUNCH/SETTLE[_SLOW]/
EXIT[_SLOW]/LOOP` grammar tokens; new kit verbs `punch` (the juice_up impact,
keyed kill-before-restart; `claim_pop` now rides it) and `fade_exit` (wired
into Reward's three loser-fades); the informational-vs-decorative Reduce
Motion contract is written into CLAUDE.md's gotchas. R4: Event.gd is on the
kit (title `deal_in`, prose `write_on`, result seal `ring_pulse` — the ring
went public, was `_spawn_ring` — result cards/writs `deal_in`, grid hover via
`hover_lift`'s new `target`/`raise_z` params); `write_on` + `ken_burns`
promoted from Event into the kit; Recruit/NetDraft's twin `_animate_card_reveal`
merged into kit `card_reveal` (rarity shine + companion button, now Reduce
Motion-compliant — the twins never gated). Verified: parse-checks clean on
event/recruit/reward/net_draft, `_probe_events` 30 events / 338 effects clean,
`_probe_flow` 145 drivers 0 fails, `_probe_anim_clock` ALL PASS,
`_shot_anim_pass` grew event mid/settled states (typewriter caught mid-write,
ladder stagger in flight).

**R5 + R6 SHIPPED same day — the plan is COMPLETE (R7 stays deferred).**
R5: `Motion.burst(host, pos, preset, overrides)` is the one one-shot
CPUParticles2D factory — presets `ash` / `impact` / `spell` / `spark_fall` /
`coin` / `coin_spark` / `base` keep each site's historical numbers; Combat's
four burst helpers + `_spawn_family_particles`, the forge sparks, the
treasure fountain, Shop's coin chink, GameOver's verdict curtain, and Rest's
heal motes all ride it (ambient loopers stay bespoke). `Motion.ring` is the
one expanding-ring engine (Line2D — the most capable ancestor): `ring_pulse`
became its shell preset (fade-in beat, cubic swell), `Combat._spawn_vfx_ring`
its combat delegator (anim-speed-scaled, width tween, ovals), and CombatNet's
chip burst rides it — the three separate ring implementations are gone.
R6: the ~15 stateless kit verbs (deal_in … reroll_sweep, pulse_label)
extracted to `scripts/ui/Motion.gd` as statics behind same-name GameTheme
delegators (painters/CombatNet precedent; pocket_away + forge_strike
await-forward). The trauma shake service and ink-wipe transition stay on the
GameTheme autoload — they genuinely need a Node (_process / cached shader).
Verified: parse-checks clean (combat/event/recruit/reward/main_menu + the
four burst scenes), `_probe_anim_clock` 16/16, `_probe_flow` 145 drivers
0 fails, `_probe_events` 30/338 clean, `_probe_skirmish_combat` ALL PASS,
`_shot_anim_pass` + `_shot_setpieces` re-rendered and compared against
pre-change captures — visually unchanged (particle scatter differs only by
seed/capture timing). Feel-tune knobs live in GameTheme
(`SHAKE_MAX_OFFSET` / `SHAKE_DECAY` / `SHAKE_FREQ`).

**Verdict up front:** the game does NOT have an animation-quantity problem —
three prior passes (combat feel 07-04, shell motion kit 07-11, verdict FX
07-11) saturated the beats. What it has is an animation *system* problem in
five specific places: a half-plumbed speed setting, a legacy screen shake, one
screen (Event) still off the shared kit, an implicit-but-uncodified motion
grammar spread over ~137 call sites, and duplicated FX primitives (3 ring
implementations, ~7 hand-rolled particle bursts). All five are fixable without
touching how any animation *looks*.

---

## 1. Inventory — the five layers

Everything is procedural (`create_tween` + code-drawn geometry + one-shot
`CPUParticles2D`). There are **zero** scene-authored `AnimationPlayer` tracks.
178 `create_tween` sites across 19 files; ~137 explicit easing sites; 33
particle refs in 9 files.

| Layer | Home | Scale | What lives there |
|---|---|---|---|
| **Shared motion kit** | `GameTheme.gd` ~2537–2900 | ~10 verbs | `deal_in`, `hover_lift`, `claim_pop`, `pocket_away`, `tick_number`, `pulse_label`, `forge_strike`, `rarity_reveal`, `reroll_sweep`, `_spawn_ring`, ink-wipe scene transition (shader) |
| **Combat choreography** | `Combat.gd` (~70 funcs) | largest | clash sequencing (`_short_pause` conductor + `LUNGE_APEX`/`POST_HIT_BEAT`/`HITSTOP_BEAT`), screen shake/flash, spell VFX families (`_vfx_fire/shock/blight/blessing/earth/mind`), callouts, floating numbers, banners, encounter intro, verdict ceremony, drag ember trail, ambient FX |
| **Card self-animation** | `Card2D.gd` (~14 funcs) | per-card | lunge (anticipation→strike→settle), hit recoil + squash, mortal slump, last-stand flare, death burst, danger/threat pulses, idle bob on a **shared** battlefield visual timer, drag lift |
| **Net mirrors** | `CombatNet.gd` | 18 `anim_time` sites | clash replay FX, foe potion/relic reveals, chip pulses, discard fans |
| **Scene one-offs** | shell scenes | 1–19 tweens each | Event typewriter + Ken Burns art drift, MainMenu entrance cascade, MapPulseOverlay (frontier reveal, march dust), Rest campfire life, Treasure coin fountain |

Kit adoption (calls into `GameTheme.` motion verbs): Shop 30 · Rest 26 ·
MainMenu 22 · Reward 18 · Wayside 15 · Recruit 11 · Treasure 10 · GameOver 7 ·
NetDraft 1 · **Event 0** (19 local `create_tween` sites, its own ring at
~L2033, its own hover lift at ~L2201 — it predates the kit).

### The implicit house grammar (measured, not written down anywhere)

| Beat | Duration | Easing |
|---|---|---|
| Anticipation | 0.05 | SINE-out |
| Strike / punch | 0.08–0.12 | QUAD-out |
| Settle | 0.16–0.34 | **BACK-out** (the house signature) |
| Exit / fade-away | 0.30–0.46 | EASE_IN |
| Loops (bob, danger pulse) | 0.55–1.1 | SINE |
| Pacing constants | `LUNGE_APEX` 0.09 · `POST_HIT_BEAT` 0.06 · `HITSTOP_BEAT` 0.18 · heavy-hit gate 5 dmg | — |

This grammar is remarkably consistent — every screen already speaks it — but
it exists only as ~137 repeated magic-number pairs.

---

## 2. What is already done well — keep, and build on these

These match or exceed the published best practice; the restructure should
extend them, not replace them.

1. **All-procedural animation.** No AnimationPlayer assets to maintain, every
   effect is diffable text, seeded painters keep visuals deterministic. This
   is the right call for a programmatically-built UI and it plays to how this
   project verifies work (headless probes + windowed screenshots).
2. **Animation principles are genuinely applied**: anticipation → apex →
   settle on lunges, squash-&-stretch on strikes (scale kept on a separate
   tween so it can't perturb position timing), hitstop with *named* constants,
   weighted lunge depth via `_lunge_strength(atk)`, deliberate contrast
   (forge sparks FALL, combat embers RISE).
3. **Ownership discipline where it matters most**: Card2D keys its combat
   tweens (`_lunge_tween`/`_recoil_tween`/`_lunge_scale_tween`), kills before
   restart, and the idle bob explicitly *yields* `position.y` to combat tweens
   (`_combat_tween_active`). This is exactly the "one owner per property" rule
   the Godot community converged on.
4. **Perf-conscious structure**: one shared battlefield visual timer instead
   of N `_process` callbacks; `_combat_process_needed()` gates Combat's
   `_process`; map plate frozen with animation exiled to `MapPulseOverlay`.
5. **The funnel idiom** (log via `_log_event`, relic FX via `_relic_fired`,
   sacrifice via `_trigger_player_sacrifice`) — the codebase already knows
   that beats route through one function. The restructure below is mostly
   "apply the funnel idiom to motion itself."
6. **Accessibility plumbing exists**: `reduce_motion`, `anim_speed`,
   `particles`, `screen_shake` are real settings with 107 gate sites.
7. **Visual verification harnesses** (`_shot_anim_pass`, `_shot_setpieces`,
   `_shot_verdict_fx`, `_shot_battle_log`) — almost nobody has this; it is the
   project's single biggest strength for animation work and every restructure
   step below ends in one.

---

## 3. Findings

Severity: ▲ player-visible defect · ● structural debt · ○ polish.

### A1 ▲ The Animation Speed setting only speeds up half the system
`UserSettings.anim_time()` is used in exactly 3 files: UserSettings, Combat
(23 — mostly `_short_pause` and screen_flash), CombatNet (18). **Zero** uses
in Card2D or GameTheme. Consequence: at speed 3.0 ("Instant") the pacing
pauses collapse to one frame but every lunge still takes its full ~0.29s, the
death VFX still runs unscaled, banners hold unscaled — the conductor rushes
ahead of the orchestra and fast combat reads as overlapping mush instead of
fast. The comment on `play_attack_lunge` even documents the fragile coupling:
the tween's 0.05+0.08 apex must "land near" Combat's `LUNGE_APEX 0.09`, but
the two numbers live in different files and only one of them scales.

### A2 ● Screen shake is the one legacy-model piece left
`Combat.screen_shake` (L17959): fixed 0.3s, 8 random steps, linear decay.
Problems: (a) overlapping shakes create two tweens fighting over
`_hud_layer.offset` — consecutive kills stutter instead of compounding;
(b) magnitude doesn't compose (a 3rd kill during a shake should *add energy*,
not restart); (c) it's Combat-only — shell set-pieces (forge strike, treasure
burst, war-chest picks) have no impulse channel at all. The industry-standard
model since Eiserloh's GDC talk is **trauma**: `add_trauma(x)` accumulates,
shake amplitude = trauma², noise-driven offsets, linear decay. One small
service replaces all of this and any screen can use it.

### A3 ● Event.gd never joined the kit
19 local tween sites, zero kit calls, own ring spawner, own hover lift, own
fade-ins — all of which now have kit equivalents. It predates the 07-11 pass.
It works, but it's the screen where the grammar drifts first (its own
durations/easings) and any kit improvement (A1, A4 fixes) skips it.

### A4 ● Duplicated FX primitives
- **Rings ×3**: `GameTheme._spawn_ring` (StyleBox panel), `Combat._spawn_vfx_ring`
  (draw-based), Event's local ring.
- **Particle bursts ×~7**: `spawn_ash_burst`, `_spawn_impact_burst`,
  `spawn_spell_burst`, `_spawn_chip_burst` (Combat), `_spawn_death_burst`
  (Card2D), forge sparks (GameTheme), coin fountain (Treasure) — each
  hand-configures a `CPUParticles2D` from scratch (~20 lines each). The looks
  are deliberately different (keep them); the *setup boilerplate* is identical.
- **Card reveals ×2**: `Recruit._animate_card_reveal` vs
  `NetDraft._animate_card_reveal` — twins maintained separately.

### A5 ● The reduce-motion policy exists only in comments
Card2D already articulates the correct rule in two places: the threat overlay
stays visible under Reduce Motion "but hold it steady — the alpha oscillation
is the decorative part" (L3606), and "the idle breathing bob is purely
decorative — never start it" (L3762). That's exactly the WCAG 2.3.3 /
accessibility-guidelines split: **informational motion keeps a static
fallback, decorative motion is removed entirely.** But it's uncodified, so
application is uneven: the GameTheme kit gates *everything* (fine — it's all
decorative), lunge/recoil gate on nothing (defensible — they carry combat
information — but that's luck, not policy), and nobody can check a new call
site against a written contract.

### A6 ○ The grammar is implicit
~137 easing sites re-type the same four beat/easing pairs (§1 table). Nothing
enforces or names them, so drift is one PR away, and every new animation
re-derives "how long is a punch" from neighbors.

### A7 ○ Tween-ownership hygiene is proven but not packaged
The keyed kill-before-restart pattern lives only in Card2D. Known conflict
points elsewhere: `screen_shake` overlap (A2), `hover_lift` connects new
lambdas per call (double-wired if ever called twice on one button) and creates
enter/exit tweens without killing the sibling — fine at current call rates,
but the pattern is trap-shaped.

### A8 — Solo combat animates inline in the resolution coroutines (noted, not a defect)
Hearthstone and StS decouple resolution from presentation via an action/event
queue and replay it; this codebase already has that shape in **net** mode
(sealed clash replay, `_net_replay_fx`). Solo instead awaits FX inside
resolution. A full queue migration would be the textbook restructure — and is
**not recommended now**: enormous blast radius across ~20k lines of Combat for
zero player-visible change, unless replay/spectate/turbo-forward ever becomes
a feature. A1's shared-clock fix buys the practical benefit (speed control)
at 1% of the cost.

---

## 4. How the reference titles structure this (research digest)

- **Balatro**: one universal impulse verb — every object exposes
  `juice_up(amount, rot)` and *everything* juices through it; feel coherence
  comes from a tiny shared vocabulary, not per-site artistry. (Its cards also
  run soft-spring "wobble physics" toward layout targets — our idle bob +
  BACK-out settles are the same instinct.)
- **Hearthstone / StS**: resolution emits an ordered task/action list;
  presentation replays it with timing. Decouples rules speed from show speed.
  We have this in net mode only (see A8).
- **Godot community consensus**: tweens are for short disposable motion; give
  each animated property ONE owner; centralize repeated motion in a
  service/singleton so lifecycle (kill/restart/settings) is handled once —
  which is exactly what the GameTheme kit is; it just needs to finish the job
  (A1, A3, A4).
- **Camera shake**: trauma model (accumulate → amplitude = trauma² → noise
  offsets → linear decay), from Eiserloh's "Juicing Your Cameras With Math";
  also the model every modern shake addon implements.
- **Accessibility (WCAG 2.3.3 & game-a11y guidelines)**: split motion into
  informational (keep, with static fallback) vs decorative (remove under
  reduce-motion). Card2D's comments already discovered this independently.

Sources: Godot Tween docs; "Advanced Godot GlobalTweens Techniques" (Dre
Dyson); Balatro `juice_up` (Steamodded wiki, Mix and Jam / 80.lv recreations);
"Juice it or lose it" (Jonasson/Purho); "The Art of Screenshake" (Nijman);
"Math for Game Programmers: Juicing Your Cameras With Math" (Eiserloh); WCAG
2.3.3 Understanding doc; russmatney's juicy-notes compilation.

---

## 5. Restructure plan — phased, strengths-first

Design principle: **extend the funnel idiom to motion.** Don't import alien
workflows (no AnimationPlayer authoring, no external tooling); make the
already-good procedural kit the single vocabulary, verified the way this
project verifies everything (probes + shot harnesses). Ordered by
payoff-per-risk; each step is independently shippable.

### R1 — One clock (fixes A1) · small diff, biggest player-visible win
1. Move the beat constants (`LUNGE_APEX`, `POST_HIT_BEAT`, `HITSTOP_BEAT`,
   plus new `LUNGE_ANTICIPATION 0.05`, `LUNGE_STRIKE 0.08`, `SETTLE 0.16`)
   into one place both Combat and Card2D read (GameTheme or a tiny
   `scripts/ui/Motion.gd` — see R6).
2. `play_attack_lunge` / `play_hit_recoil` / death-beat tweens take durations
   from those constants **wrapped in `UserSettings.anim_time()`** — conductor
   and orchestra now share a clock, and `LUNGE_APEX` can no longer drift from
   the tween that must land on it.
3. Sweep Combat's combat-visible tween literals (banners, dismiss flights,
   spell VFX) through `anim_time()`. Shell/kit animations stay unscaled **by
   policy** (the setting is combat pacing) — write that one line down.
   - Verify: new `tools/_probe_anim_clock.gd` (headless): assert the derived
     apex == `LUNGE_APEX` at speeds 1.0 and 3.0; drive one scripted clash at
     3.0 and assert wall-time budget. Plus `_shot_anim_pass` unchanged at 1.0.

### R2 — Trauma shake service (fixes A2)
`Motion.add_trauma(amount)` on a tiny autoload (or GameTheme): trauma
accumulates and clamps at 1, amplitude = trauma², offsets from noise, linear
decay in one `_process` that sleeps at zero trauma. Combat's `screen_shake(x)`
becomes a delegator mapping old magnitudes → trauma (call sites untouched,
CombatNet precedent). Expose the same hook to shell screens: forge strike,
treasure burst, war-chest reveal get a *small* impulse each.
   - Verify: `_shot_setpieces` re-run; a scripted double-kill in
     `_probe_anim_clock` asserting no tween-conflict on the HUD layer offset
     (single owner now by construction).

### R3 — Codify the grammar (fixes A6, arms A5)
- Named tokens in the kit: `Motion.ANTICIPATE / PUNCH / SETTLE / EXIT / LOOP`
  (duration + trans + ease trios matching §1's table) and two combinators used
  everywhere: `Motion.punch(node, scale)` (the Balatro `juice_up` equivalent:
  QUAD-out punch + BACK-out settle on scale, keyed + kill-before-restart) and
  `Motion.fade_exit(node, dur)`.
- Write the **reduce-motion contract** into this doc's companion section in
  CLAUDE.md: *informational* (lunge, recoil, mortal slump, floating numbers,
  threat/danger overlays — always play; overlays hold steady) vs *decorative*
  (bob, ambient, entrances, bursts, reveals — gate off). New call sites must
  name their side.
- New animation code MUST use tokens; existing sites retrofit opportunistically
  (no big-bang rewrite — the values already match).

### R4 — Event.gd onto the kit (fixes A3)
Replace its local ring/hover/fade helpers with kit calls; keep the two
genuinely bespoke pieces (typewriter `visible_ratio` reveal, Ken Burns art
drift) and *promote* them into the kit — Recruit/NetDraft's twin
`_animate_card_reveal`s merge into a kit verb at the same time (A4's reveal
dupe). Gotcha from the 07-11 memory applies: redirect call sites only, never
blanket-rename local definitions.
   - Verify: `_probe_events` headless + a 2-state event shot added to
     `_shot_anim_pass`.

### R5 — Burst factory (fixes A4's boilerplate)
`Motion.burst(host, pos, preset, color_ramp)` with presets (ash / impact /
spark-fall / coin / chip) collapsing the ~7 hand-rolled `CPUParticles2D`
configs; each preset keeps its current numbers, so looks don't change. Rings:
keep GameTheme's StyleBox ring as the one implementation, delete Combat's and
Event's after redirecting.

### R6 — (Optional) extract `scripts/ui/Motion.gd`
GameTheme is ~3k lines of theme+motion+shaders. If R1–R5 grow the kit past
~600 lines, extract it to `scripts/ui/Motion.gd` with same-name GameTheme
delegators — the painters/CombatNet extraction precedent exactly. Pure
mechanics, zero behavior change; do it last so nothing else waits on it.

### R7 — Presentation queue: **deferred indefinitely** (A8)
Only reopen if solo replay/spectate/fast-forward becomes a roadmap feature.
The net-mode replay layer is the template if that day comes.

**Suggested order:** R1 → R2 (both small, both fix real defects) → R3 (paper +
tokens) → R4 → R5 → R6. R1+R2 together are roughly one session.

---

## 6. Coverage pass — what is animated, what ISN'T (2026-07-16, second pass)

§1–§5 audited the animation *system* (and R1–R6 fixed it). This section audits
*coverage*: which player-facing beats have motion at all, and how the ones that
exist measure against the reference titles. Different question, different
answers — the system is now good; the coverage has seven specific holes, and
two of them are on the most-repeated interaction in the game.

**Status (2026-07-16): C1 + C2 SHIPPED — holes #1, #2, #5 closed.**
C1 (the card lean): `Card2D._process` is a single damped rotation driver armed
only while a hand card is dragged or hovered. A DRAG leans into cursor velocity
(`LEAN_DRAG_PER_VEL` × px/sec, clamped ±`LEAN_DRAG_MAX` 0.35 rad); a HOVER tilts
toward the cursor's offset from centre (±`LEAN_HOVER_MAX` 0.10 rad) — which
subsumes the old "straighten to 0" hover beat. Damping is frame-rate-independent
exponential (`1 - exp(-rate·dt)`), so a mid-drag direction reversal is handled
natively with no tween to kill and restart. **`rotation` still has exactly one
writer**: the driver owns it while `_lean_active`, the tweens own it otherwise,
and the two windows are complementary by construction (`set_hand_target` only
tweens rotation when `not _is_hovered and not _is_being_dragged`; the hover-exit
tween carries rotation home from wherever the tilt left it — an interruption a
tween handles fine because it reads the live value). `_process` is `set_process(
false)` at `_ready` and self-disarms, so the hand/board/gallery/bake pipeline pay
nothing per frame. Decorative: Reduce Motion never arms it and the historical
straighten-tween is restored in that branch.
C2 (stat beats): `update_stat_display` is now the single funnel for stat change
feedback — an HP **gain** floats "+N HP" (`_spawn_hp_change_popup`) and either
seal punches (`_punch_seal` → `Motion.punch`) whenever its numeral changes, so
buffs, Regenerate ticks and keystone auras are finally visible on the board.
Losses are deliberately NOT floated: every path that lowers HP runs through
`take_damage` / `take_damage_bypass_armor`, which own the damage number.
`show_heal_number` correspondingly **dropped its float** (it kept its green body
wash) — both Combat call sites refresh the display first, so it was about to
double-report. Verified: `_probe_anim_clock` 27/27 (new C1/C2 section drives a
real Card2D), `_probe_flow` 145/0, `_probe_skirmish_combat`, `_probe_lifesteal`,
`_probe_type_keystones` (the HP-gain paths) all clean, `_probe_hand_dim` PASS,
`_shot_combat_hud` shows the hover tilt live with the resting fan unchanged.
**C3 (springs), C4 (card shaders), C5 (flip / chain pitch / shake rotation)
remain open.**

### 6.1 Beats that ARE animated (and hold up)

| Beat | Where | Verdict |
|---|---|---|
| Clash: lunge / recoil / squash / hitstop / weighted depth | Card2D + Combat | **Strong** — textbook, and now on one clock |
| Card play: hand → arc flight → wax press → slot ring + streak | `_play_landing_pop` | **Strong** — physical, well-sequenced |
| Death: slump, burst, fade | Card2D `_die` | Good (see 6.2 #4) |
| Hand deal-in from the deck pile | `_draw_card` + `set_hand_target` | Good |
| Hover lift + pop | Card2D `_on_mouse_entered` | Adequate (see 6.2 #2) |
| Floating combat numbers | `spawn_floating_number` | Good — back-eased pop, rise, fade |
| Screen shake, magnitude-scaled | trauma service | Strong (see 6.2 #8) |
| Shell screens: entrances, reveals, forge, reroll, claims | the Motion kit | **Strong** — 15 verbs, fully adopted |
| Net mirrors: clash replay, foe reveals, chip pulses | CombatNet | Good |

The §2 verdict stands: this is not a game that lacks animation.

### 6.2 The holes — ranked by payoff

**#1 ▲ The drag is rigid — no velocity lean.** `Card2D._start_drag` (L4164)
forces `rotation = 0.0` on grab, and `_update_drag` (L4179) pins the card's
centre to the cursor with **zero rotation for the entire drag**. Every
reference title leans the card into its drag velocity (Balatro, Hearthstone,
Marvel Snap, MTGA all do; it's the single most-cited card-feel technique in
the research). Dragging a card is the most-repeated interaction in the whole
game and it is currently the most inert thing on screen — the card is a decal
stuck to the pointer. **Fix is ~10 lines**: track cursor delta in
`_update_drag`, damp toward `clampf(vel.x * k, -0.35, 0.35)`, spring back to 0
on release. Highest feel-per-line in this document.

**#2 ● Hover is scale-only — no cursor-relative tilt.** We lift + scale;
Balatro additionally tilts the card toward the cursor and parallaxes its
layers, which is what makes its cards read as physical objects rather than
sprites. Same `_update_drag`-style damping, driven by cursor offset from card
centre while hovered.

**#3 ● Zero springs — the whole game is fixed-duration tweens.** 165
`create_tween` sites, no second-order dynamics anywhere. This matters most in
the hand: `set_hand_target`'s reflow tween gets killed and restarted on every
hover / drag / relayout, which is exactly the interruption case tweens handle
worst and springs handle natively (this project already ate one bug from it —
the 07-12 hand alpha-strand fix). A `Motion.Spring` helper (t3ssel8r's
f / zeta / r second-order formulation) applied to hand layout and card-follow
would make the hand feel settled instead of scheduled. Additive: springs live
alongside the kit, they don't replace it.

**#4 ● Card2D has no ShaderMaterial at all.** The project ships shaders
(GameTheme's ink-wipe, MapTerrain's paper multiply), so the capability is
proven — cards just never got any.

> **Scoping note (found while starting C4 — read before quoting "one shader").**
> A card is a TREE (painters, seals, labels), and the two propagation models
> differ: `modulate` is hierarchical, a `ShaderMaterial` is NOT. So a real
> whole-card flash is not a drop-in — it needs one of: `use_parent_material`
> on every child the layout builders create (invasive across ~4.6k lines and
> two layout paths), the card rendered through a SubViewport (a perf and
> layout change), or a silhouette overlay matching the deckled `WritLeaf`
> edge. Note the current modulate flash *does* reach every child — that's
> exactly why it was chosen. C4 is a design decision first, a shader second.

Three consequences:
- **Hit flash is a modulate tint** (`Color(base.r*1.8, base.g*0.5, base.b*0.45)`,
  Card2D L3090) — it *darkens green and blue* to fake red. The standard is a
  shader `mix()` toward white on a uniform: a true silhouette flash that reads
  at any card art, any tint.
- **Death has no dissolve** — burst + fade only. A noise dissolve with an edge
  glow is the genre-standard "unmade" read and would cost one shader.
- **Rares have no foil/shine in hand.** `rarity_reveal` exists but fires only
  on the Recruit/NetDraft slate; a rare sitting in your hand looks like a
  common. Balatro's 3s shimmer loop is the reference.

**#5 ○ The stat SEAL doesn't react (corrected — the first pass overstated this).**
~~Stat changes snap; board buffs are invisible.~~ **That was wrong.** The bare
setters at Card2D L121–126 have no hook, but the display path does:
`update_stat_display` (L2640) already spawns a floating `+N ATK` / `-N ATK`
popup via `_spawn_atk_change_popup`, sets a ▲/▼ `StatCaret` (the colour-blind
redundancy), and recolours the numeral — and Combat calls it at **144 sites**.
Heals have `show_heal_number` + a green body pulse. Buffs read fine.

The real, smaller residue:
- **The seal is inert.** The numeral is replaced; nothing punches. The floating
  text carries the information, but the card doesn't acknowledge it — the one
  place the house `Motion.punch` verb obviously belongs and isn't.
- **It rides a call convention, not the setter.** 144 manual
  `update_stat_display()` calls after mutation; a site that forgets one shows a
  stale number with no beat. Latent-bug shape, not a current defect (the
  comment at L2662 shows the convention is understood and maintained).

Lesson for this doc: L121–126 look like the whole story and aren't. Verify the
*display* path before calling a beat missing.

**#6 ○ No card flip.** `assets/ui/card_back.png` exists and net sealed-orders
render face-down cards — but reveals are texture swaps. Sealed-orders reveal,
Discover picks, and draws are all instant. The flip is the most iconic beat in
the medium and the game doesn't have one.

**#7 ✅ Audio doesn't escalate in chains — BUILT (C5, 2026-07-16).**
`AudioBank.play_sfx` takes `pitch_base` and the codebase already used it for
repitched stand-ins — but the clash cascade played every hit at the same pitch.
Balatro's rising C-D-E-F-G per card is *why* its chains feel like a build rather
than a list. Now: `Card2D._next_clash_pitch()` (static — the phrase belongs to
the CLASH, not to a card) steps `CLASH_PITCH_STEP` 0.045 per strike, capped at
`CLASH_PITCH_MAX` 0.28 (~+4 semitones); a 6-strike exchange ends at 1.225. It
rides the existing `_flash_hit` cue, so the "struck survivors sound via
Card2D, kills sound once via Combat" ownership contract is untouched. Combat
resets it once per round at `_dispatch_passive_start_of_round`; the cap means a
*missed* reset saturates rather than shrieking. Verify:
`tools/_probe_clash_pitch.gd` (4 checks — root note, climb, saturation, reset).

**#8 ○ Shake is translation-only — NOT the cheap add it looked like.**
Eiserloh's trauma model (which R2 implemented) includes a *rotational*
component; Balatro's large shake adds ±1°. `GameTheme.SHAKE_MAX_OFFSET` only
translates.

> **Scoping note (found while starting it).** The shake target is Combat's
> `_hud_layer` — a **CanvasLayer**, shaken via `offset`. Two problems rotation
> has to solve first: (a) a CanvasLayer rotates about its ORIGIN (0,0), so 1°
> throws the far corner of a 1600×900 canvas ~28px — to pivot on screen centre
> the offset must be driven as `pivot - pivot.rotated(r)`, not just set; and
> (b) the HUD layer is not the board, so rotating it alone would visibly shear
> the HUD *against* a still battlefield. Needs a decision about what the shake
> actually owns before any rotation lands. Left alone deliberately.

### 6.3 Research digest (second pass)

- **Balatro** (Crosley's feel guide; 80.lv Unity recreation): cards are never
  static — idle micro-motion, cursor tilt, foil parallax; hover 12px lift @
  1.05 scale, 0.15s ease-out; shake tiers 0.2s/2px → 0.5s/8px + ±1° rotation;
  digit rolling with 50ms stagger and a bouncy `cubic-bezier(0.34,1.56,0.64,1)`
  (≈ our BACK-out — same instinct, already in the grammar); rising pitch per
  card in a chain. The thesis worth stealing: *feedback is the product* — the
  juice isn't a layer on the game, it IS the game.
- **Springs / second-order dynamics** (t3ssel8r; toqoz.fyi; Heckel): the
  headline is interruption. "Procedural animation responds well to
  interruption, which is the spring's specialty; tweening has difficulty
  handling interruptions naturally." That is precisely our hand-reflow problem
  (#3).
- **Hitstop** (fighting-game practice): 3–5 frames at the impact frame; longer
  pause = heavier read. Our `HITSTOP_BEAT` 0.18 is ~11 frames — deliberately
  ceremonial, and correct for a card game, but worth knowing it's 2–3× the
  action-game figure.
- **Hit flash** (Godot practice; Saltmire FX, Juicee): shader `mix()` to white
  on a uniform is the standard; modulate is the fallback, not the target (#4).
- **Accessibility**: shake is the one effect that reliably triggers motion
  sickness — ours is already on its own dedicated setting, which is ahead of
  the field.

Sources: [Balatro: Juicy Feedback in a Poker Roguelike](https://blakecrosley.com/guides/design/balatro);
[Balatro's Card Movements & Shaders Recreated in Unity](https://80.lv/articles/balatro-s-card-movements-shaders-recreated-in-unity);
[Spring-based Animation](https://toqoz.fyi/springs.html);
[The physics behind spring animations](https://blog.maximeheckel.com/posts/the-physics-behind-spring-animations/);
[Juice in Game Design](https://www.bloodmooninteractive.com/articles/juice.html);
[Game feel on the web: squash, shake, and the art of juice](https://valdemird.com/blog/game-feel-on-the-web/);
[Saltmire FX](https://saltmire.itch.io/saltmire-fx/devlog/1577528/saltmire-fx-is-out-one-line-2d-sprite-shader-effects-for-godot-4);
[Juicee (Godot 4 game-feel lib)](https://github.com/Kelpekk/Juicee).

### 6.4 Suggested order (C-steps — coverage, where R-steps were structure)

- **C1 — Drag lean + hover tilt** (#1, #2). One damped-rotation helper in
  Card2D, used by both. Small diff, biggest feel win, touches the interaction
  the player performs most. **The clear first job.**
- **C2 — Seal punch on stat change** (#5, reduced scope after the correction).
  One `Motion.punch` on the seal inside `update_stat_display`. Polish, not the
  information fix the first pass claimed.
- **C3 — `Motion.Spring` + hand reflow** (#3). Structural; fixes an
  interruption class, not a look.
- **C4 — Card shaders** (#4): hit flash → dissolve → rare foil, in that order.
  Biggest visual ceiling raise; also the biggest new surface.
- **C5 — Flip, chain pitch, shake rotation** (#6, #7, #8). **Chain pitch is
  BUILT** (`_probe_clash_pitch`). The other two are NOT the small jobs this
  plan first implied — see the scoping notes on #8 (the shake target is a
  CanvasLayer that isn't the board) and #6 (needs a design pass on what flips
  and when). Flip and shake-rotation stay open pending a decision.

C1 is the one that earns its session. C2 rides along in minutes.

**Status (2026-07-16): C1 ✅ · C2 ✅ · C5-chain-pitch ✅ · C3 / C4 / C5-flip /
C5-shake-rotation OPEN.** The three open items are each a real project with a
decision at the front (springs touch hand reflow; shaders need a propagation
model; shake-rotation needs an owner) — none is a drop-in, and this doc
previously said otherwise.

---

## 7. Standing verification for this layer

- `tools/_probe_anim_clock.gd` (new, R1/R2) — beat-constant/apex agreement,
  Instant-speed wall-time budget, single-owner shake.
- `tools/_shot_anim_pass.tscn` / `_shot_setpieces.tscn` / `_shot_verdict_fx.tscn`
  — existing windowed harnesses; every R-step above must leave them visually
  unchanged at speed 1.0 (that's the point: structure changes, look doesn't).
- Shot harnesses must force `UserSettings.reduce_motion = false` (this
  machine's saved settings have it ON — known trap from the 07-11 pass).
