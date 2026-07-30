# Combat legibility pass — 2026-07-28

**Status: TIER 0 PARTIAL + TIER 1 CORE BUILT.** See §10 for exactly what shipped and what did
not. Diagnosis and plan from a five-agent audit (beat census, affordance inventory,
perceptual-limits research, comparable-games research, empirical frame capture). Every code
claim below was verified against the live tree, not against CLAUDE.md.

**Empirical baseline** (measured on a real 16-body clash via `tools/_probe_clash_trace.gd`,
`anim_speed 1.0`, before the fixes): end-turn → next player turn = **9317 ms**, 113 events,
**76 visible beats**, max frame gap 26.2 ms. There is no hitching — **this is a pacing problem,
not a performance problem.**

Sibling doc: [`COMBAT_SHAPE_PASS_20260727.md`](COMBAT_SHAPE_PASS_20260727.md) — its Tier 1
items 6/7/8 (break up `_start_round`, stagger the death flush, scale chip lifetimes) are BUILT.
Its **#9 "give the clash phase boundaries" and #10 "let stat-provenance survive into the clash"
are not**, and this doc supersedes both with a measured rationale.

---

## 1. The headline

**Every combat beat constant in the project sits inside the one timing band the perception
literature condemns.**

Two independent findings bracket it:

- **Perceived causality collapses past ~100 ms.** Event pairs judged *causal* averaged
  **66.9 ms** apart (SD 29.2); pairs judged *non-causal* averaged **164.7 ms** (SD 27.2).
  (Straube & Chatterjee, *Front. Hum. Neurosci.* 4:28, 2010.)
- **The attentional blink means two events 200–500 ms apart cannot both be registered** — the
  second is reliably missed; performance recovers past ~500 ms.
  (Dux & Marois, *Atten. Percept. Psychophys.* 71(8), 2009.)

Current constants — `DEATH_BEAT` 100 ms, `POST_HIT_BEAT` 130 ms, `COMBAT_PAUSE_SHORT` 150 ms,
`LUNGE_APEX` 180 ms, `ROUND_BEAT` 200 ms, `HITSTOP_BEAT` 260 ms — are **all six** in the dead
zone. Too slow to fuse into one perceived event, too fast to register as two.

**The reframe: the beats are not too fast. They are at a spacing that reads as neither
simultaneous nor sequential.** Only two targets are defensible — fuse into one genuinely
simultaneous beat (≤70 ms internal, then hold), or serialize into stages ~600–1000 ms apart.
The middle is the one place to avoid.

This also explains why the **"Deliberate" 0.34× speed added earlier today
([`SettingsOverlay.gd:1069`](../scripts/ui/SettingsOverlay.gd)) did not solve it**: dividing
every beat by 3 moves 130 ms to 382 ms — out of the causality window and *deeper into the
blink*. Uniform slowdown cannot fix a structural problem; it asks the player to read the same
unstructured burst for longer.

## 2. The measured load

Representative act-2 board (5 enemy bodies, 4 player bodies, 3 kills):

| Segment | Wall clock @1× | Discrete visual sub-events | Attention budget each |
|---|---|---|---|
| Clash | ~3.74 s | **110–160** | **~25–35 ms** |
| Round-open (`_start_round`) | 0.60 s of pacing | ~54 | **~11 ms** |
| Full commit → playable | **~5.3 s** (busy round 6.5–7.5 s) | | |

Required for two events to be separately registered: **≥500 ms**. We are over budget by
**15–20×**.

Supporting limits, all with primary sources:

| Constraint | Number | Our state |
|---|---|---|
| Strike → its own consequence | **≤70 ms** (same beat) | often split across a 130 ms beat |
| Two separately-registered events | **≥500 ms** | 100–260 ms |
| Concurrently animating actors | **≤4** (multiple-object-tracking limit) | up to **16** |
| Items countable at a glance | **3–4** (subitizing) | 16 |
| Impact hold, scaled by damage | **150–230 ms** (SF IV ships 9/11/13 frames by strength) | 130/260, two-valued |
| Dwell per location you want looked at | **250–350 ms** | ~30 ms |
| Facts retained after the clash | **~4** (Cowan) | everything else must live in a log |
| Total before a skip affordance is required | **≤10 s** (Nielsen) | ~5–7.5 s, OK |

## 3. Where it actually breaks

The round-open is **no longer** the worst offender — today's split fixed that. The three real
clusters:

1. **The strike impact frame** (`Combat.gd:5405–5509`). One mutual-trade kill fires **~20–24
   discrete visuals in a single frame**: forward tracer, defender counter-lunge, log row,
   thorns burst + chip + recoil damage on the *attacker*, defender damage float + seal punch +
   rail refresh + mortal slump, impact burst, kill SFX, **overkill spill onto a third card**
   (`:5488`), RAMPAGE/GOLD float — and then `_apply_mutual_retaliation` (`:5509` → `:5565`),
   which is **an entire second strike** with its own tracer, log row, damage, burst and kill
   cue. All of it before the 0.13–0.26 s beat.
2. **The first corpse of every death flush.** `_cleanup_dead_paced` (`:6944–6946`)
   deliberately gives **no beat before corpse #1**, so its full destruction chain (ash burst,
   rings, veteran streak, log row, shake, adjacency re-tally floats, `dispatch_on_death`,
   encounter hook, reactive passive, Rear-Guard grant, burn-away tween) shares a frame with
   the previous strike's tail. A 3-corpse flush is three of those chains inside 0.20 s.
3. **`_resolve_intents`** (`:3619`, `:14599–14655`). Zero pauses anywhere. On a 5-body line it
   can CHARGE, GUARD, RALLY, HEAL, ENRAGE **and summon a whole enemy body** (`:14651`) in one
   frame, then `await _do_combat()` begins on the next.

### Diagonal eye-demands — unfollowable by construction

- **Face damage**: the swing happens in a lane; the big "−N" and bar drain happen at the HP
  plaque in the **opposite screen corner** (foe top-right `:19345`, you bottom-left `:19511`).
  Same frame, no pause.
- **Overkill**: killing blow's number on the front body, spill number on the body **behind**
  it, same frame (`:5488`).
- **Mutual retaliation**: forward damage number in the enemy row, counter's damage number in
  the player row, same frame.
- **`strike_the_champion`** (`EncounterEffects.gd:141`): damage + flash + shake on a *player*
  body on the same frame as +1 ATK floats rising off four *enemy* bodies.
- **Every keyword chip also writes a battle-log row** in the top-left drawer — so any board
  event worth a chip simultaneously demands a glance at the opposite corner.

### Loose ends found in passing

- The **"ROUND N" banner (1.11 s) and the 0.08 s-staggered draws are not awaited**, so the
  tail of the round-open plays *after* `board_interactive = true` (`:3559`).
- **`_round_beat` returns synchronously when `_is_net()`** (`:8762`) — in skirmish the entire
  round-open collapses back onto one frame.

## 4. The silent list — what changes state with no honest signal

Ranked by damage to comprehension. These are **truth bugs, not pacing bugs**, and they are
cheap to fix independently of any pacing decision.

| # | Item | What the player sees | Rating |
|---|---|---|---|
| 1 | **Overkill absent from the forecast.** `:24497` appends `PIERCES N` only when `_forecast_has_piercing()`; `state["overkill"]` is computed at `:24570` and **discarded** for everyone else. | Pre-commit read says only "SLAIN". The entire 2026-07-28 blocker economy is invisible at decision time. | **INVISIBLE** |
| 2 | **The ATK seal lies whenever a stat relic is held.** `_effective_attack:6147` adds `swift_boots`/`glass_cannon`/`linked_banner`/`champions_belt`/`phalanx_stone`/`steady_banner` **outside** `Card2D.effective_atk()`. | The seal *and* the provenance line print a number the creature does not swing for. Only the forecast chip is honest. | **INVISIBLE / actively misleading** |
| 3 | **Bodyguard redirect** (`Card2D.take_damage:3194–3197`) — `ward_by.take_damage(...); return`. | You attack card A; card B silently loses HP. No chip, no log, no rail entry naming the Squire. | **INVISIBLE** |
| 4 | **Relic triggers**: only **40 of ~120** relic ids route through `_relic_fired`. Never routed: `phoenix_heart`, `reapers_scythe`, `butchers_cleaver`, `bone_pile`, `imp_generator`, `echo_staff`, +73 more. Under Reduce Motion the own-chip pulse is skipped entirely. | Two thirds of relic firings are invisible; under RM your own relics are audio-only. | **INVISIBLE (majority)** |
| 5 | **Reactive encounter passives** (`_dispatch_reactive:14855`) — only beat is a 10% scale punch on a corner plaque, which **returns early under Reduce Motion** (`Motion.gd:651`). `exile_card` deletes your top draw with **zero** feedback. | Nothing, or nothing at all. | **INVISIBLE** |
| 6 | **Encounter start-of-round / on-death passives** — no plaque pulse on these paths at all; `wolf_pack_revenge`, `pyre_spread`, `necro_death_summon`, `crypt_ghost`, `tide_*`, `orc_random_buff` carry nothing. | Stats change across the line with no cause named. | AMBIGUOUS→INVISIBLE |
| 7 | **Wall reduction** (`_get_wall_reduction:6885`, applied `:5648`) — if reduction ≥ ATK, **absolutely nothing happens on screen.** | A blow lands and does nothing, unexplained. | **INVISIBLE** |
| 8 | **Command gains** — `_pulse_mana_label` is called **only on spend**. | The seal numeral is just different next frame. | **INVISIBLE** |
| 9 | **`_show_info` has no queue** (`:26961`) — a second call in the same frame **overwrites the first unread**. 64 call sites. | Messages destroyed silently. | AMBIGUOUS |
| 10 | **Encounter-granted keywords** (`has_encounter_passive_keyword`) never written to `card_data.keywords` → no device, no rail orb. | Token looks identical to an unbuffed one. | AMBIGUOUS |
| 11 | **Escalation** (`:14908`) gives every enemy +1 ATK permanently, announced only by incidental floats. | Four simultaneous "+1 ATK", no caption, no reason. | AMBIGUOUS |

**Already adequate** (do not touch): overkill *at resolution* (chip + lance + real number),
adjacency/type_buff auras, Armored/Shield/Last Stand chips, Doom/Regenerate/Wither, the muster
delay's enemy-side handling.

### Reduce Motion is systematically mis-gated

Per the project's own doctrine, an animation is **informational** (carries game state — always
plays) or **decorative** (gated off). Three informational cues are currently gated as
decorative:

- `ClashLaneFocus` — the lane spotlight, i.e. *where to look*, returns early under RM
  (`Combat.gd:4607`).
- `_pulse_passive_plaque` — the only signal a reactive passive fired at all.
- The battle-log tab's new-line pulse (`:18982`) — under RM a new entry gives **zero**
  indication.

## 5. What shipped games actually do

Nine mechanisms surveyed; the load-bearing finding is that **every shipped game that has
"simultaneous" combat serializes it anyway.**

- **Marvel Snap** commits secretly but reveals **strictly one card at a time**, in play order,
  each with its own animation resolving fully before the next begins.
- **Hearthstone Battlegrounds** resolves one attack at a time, board-centre.
- **Into the Breach** draws the *resolved outcome* on the board before you commit — attack
  trail plus a red box on every tile that will be hit — and offers an **Attack Order** overlay
  (hold Alt/Tab) numbering the whole sequence.
- **Legends of Runeterra's Oracle's Eye** opens automatically when attackers are declared and
  shows the end-state including deaths — and **refuses to open when the outcome is random**, so
  it can never lie.
- **Subset's diagnosis was identical to ours**: playtesters "could just see all these damage
  indicators all over the map… we needed to make it very clear who was doing what." Their rule
  was *"sacrifice cool ideas for the sake of clarity every time"* — and they **cut weapons**
  whose patterns couldn't be parsed.
- **The speed trap is two-sided.** Battlegrounds' auto-accelerating combat produced "the board
  would pretty much just explode," "could barely follow with my eyes," and nausea reports —
  while experienced players simultaneously demanded 2×/4×. **Speed must be a player setting,
  never an engine ramp.** (Celeste's precedent: 6 discrete named steps, 50–100%.)

**Anti-pattern to avoid (Wildfrost):** never put two numbers on a unit that both plausibly mean
"when I act" — players conflate them.

### Player complaint vocabulary → which failure it names

- *"couldn't tell what happened" / "the board just explodes"* → **attention-direction** failure
- *"don't know what killed me"* → **log/summary** failure
- *"I'd have played differently"* → **forecast** failure

Worth asking testers which phrase they use; it points straight at the tier to fix.

## 6. The plan

### Tier 0 — Truth fixes (no pacing change, no design risk)

Independent of the sequencing decision. Fix §4 items 1–9 and the three RM mis-gates. Highest
value first: **#1 overkill in the forecast**, **#2 the lying ATK seal**, **#3 bodyguard
redirect**, **#4/#5 relic and reactive-passive signalling**, **#9 `_show_info` queue**.

### Tier 1 — The sequencing architecture

The consequential decision; see §7. Either serialize the clash into ≤4-actor stages, or fuse
each volley into one genuinely simultaneous beat. Both are defensible; the current middle is
not.

Shared sub-tasks whichever is chosen:

- **Fuse the impact frame.** Strike + its own damage number + death mark must land within
  ~70 ms — that is one beat, never split.
- **Move `_apply_mutual_retaliation` out of the impact frame**, or present the trade as one
  deliberate two-headed beat rather than two overlapping strikes.
- **Give the death flush a beat before corpse #1.**
- **Give `_resolve_intents` pacing** — it currently has none, and can summon a body.
- **Fix the diagonals**: float face damage at the *lane* first, then travel it to the plaque.
  Same for overkill spill (front body → body behind).
- **Scale hitstop by damage** (150–230 ms band) instead of the current two-valued 130/260.

### Tier 2 — The forecast (Into the Breach / Oracle's Eye)

`_refresh_lane_forecast` is already ~60% of this. Complete it: per-column resolved outcome
before commit — incoming damage on each body, death mark on anything that dies, **overkill
spill shown**. Adopt LoR's honesty rule: where the outcome is random, the forecast declines to
predict rather than guessing.

### Tier 3 — The post-clash summary

Cowan's ~4-fact retention limit means the rest belongs in a log. The battle log exists but is
**closed by default**. Add the round summary players of this genre keep asking for: what died,
what hit face, net totals.

### Tier 4 — Speed as a first-class setting

Keep the discrete named steps (already correct). Make "Deliberate" *restructure* rather than
merely divide — under the serialized model it should be the mode with the longest per-stage
dwell, not just slower tweens.

## 7. The decision — SERIALIZE (owner's ruling, 2026-07-28)

**Chosen: serialize by lane.** One column resolves at a time under a strengthened spotlight,
with a real eye-dwell before the spotlight moves. Scope approved: **Tier 0 + Tier 1**.

Implementation note that made this cheap: **`_do_combat` is already lane-ordered.** It runs
front row across lanes 0→3 (player strike then enemy strike per lane), then back row across
lanes 0→3. That is already eight sequential single-column visits — the serialization exists
structurally and was invisible only because no beat let the eye rest on a lane before the next
one fired. So Tier 1 does **not** reorder resolution (which would risk cleave / forked-spear /
adjacent-lane edge cases); it adds the dwell, strengthens the spotlight, and names the two
passes.

Rejected alternatives, for the record:

- **Serialize** (Marvel Snap / ITB discipline): one column resolves at a time under a
  strengthened spotlight, ~600–900 ms per lane. Clash grows to ~5–7 s. Maximum clarity;
  costs tempo, and the cost scales linearly with board size.
- **Fuse** (all four lanes strike as one perceived event, ≤70 ms internal, then one long
  hold): clash stays ~3 s or shrinks. Preserves the "simultaneous clash" fantasy that is the
  game's identity, and respects the ≤4-actors limit by making the volley **one** actor
  perceptually. Costs per-lane detail — the log and forecast must carry it instead.

A third option — **ship both, bound to the existing speed setting** (Deliberate = serialized,
Normal/Fast = fused) — is attractive on the accessibility evidence but roughly doubles the
implementation and test surface, and means two resolution presentations must stay in sync with
one resolution *engine* forever.

## 8. Verification

New probes required:
- A beat-spacing gate: fail if any two separately-registered combat events land 100–500 ms
  apart, or if more than 4 actors animate concurrently.
- Extend `tools/_probe_combat_telegraph.gd` to assert the forecast includes overkill.
- A truth probe asserting the ATK seal equals what the creature actually swings for.

Existing probes that must stay green: `_probe_overkill.tscn`, `_probe_muster_delay.tscn`,
`_probe_anim_clock.gd`, `_probe_creature_fx.gd`, `_probe_combat_telegraph.gd`.

## 10. What shipped (2026-07-28)

### Tier 1 — the serialized clash (BUILT)

- **`LANE_DWELL` 0.30 s / `LANE_DWELL_KILL` 0.52 s** + `_lane_dwell()`, `_clash_lane_pass()`,
  `_lane_will_strike()`, `_rank_will_strike()`, `_downed_count()` in `Combat.gd`. Each column's
  exchange now holds long enough to read before the spotlight moves. **Dwell is skipped on a
  column where nothing swings** — a pause on an empty lane is the same mistake as a caption
  naming an empty beat. Net and headless bail.
- **Rank captions** — `THE FRONT RANK` / `THE BACK RANK`, each gated on that rank actually
  having a striker. This is the prior doc's Tier 1 #9 ("give the clash phase boundaries").
- **`_impact_hold(damage, was_lethal)`** replaces the two-valued 130/260 ms split with the
  150–230 ms band, scaled by damage and capped (Sakurai's rule). Lethal blows always take the
  ceiling.
- **`DEATH_BEAT` 0.10 → 0.21** and **a lead-in beat before the first corpse.** Measured: corpses
  were falling every 116 ms, and corpse #1's destruction chain shared a frame with the last
  strike's tail.
- **`THE FALLEN` now fires BEFORE the flush**, off `_downed_count()`. The capture caught it
  appearing at t=7983 ms when the flush had begun at t=7284 ms — seven of eight bodies had
  already vanished before the screen said a word.
- **`ClashLaneFocus` reclassified INFORMATIONAL.** No longer bails under Reduce Motion (it snaps
  to full strength instead of ramping); surround ink 0.30 → 0.46 alpha, kept under 0.5 so
  unfocused lanes still read as context.

### Tier 0 — truth fixes (PARTIAL)

- **§4 #1 overkill in the forecast — FIXED.** `_forecast_creature_impact` now prints
  `OVERKILL N` (spill onto the body behind) as well as `PIERCES N`, gated on
  `_forecast_overkill_lands_behind()` so it never promises damage that goes nowhere. Wording
  matches the resolution-time callout verbatim.
- **§4 #9 `_show_info` clobber — FIXED.** Now a real queue (`_info_queue`, `INFO_QUEUE_MAX = 3`,
  newest wins on overflow, exact repeats collapsed) instead of same-frame callers destroying
  each other's messages.

### Tier 0 — the rest of the silent list (BUILT)

- **§4 #2 the lying ATK seal — FIXED**, the worst item in the backlog. The six relic terms moved
  onto `CreatureInstance.relic_atk_buff` (snapshot key `"relic_atk"`, legacy default 0, and on
  the erase list for `to_replication_snapshot` so board sync can't double-count a component it
  already sends folded). `Combat._relic_atk_for(card)` is the pure computation;
  `_effective_attack` refreshes it before reading, and `_refresh_adjacency_buffs` sweeps it so
  the seal is right **while the player is planning**, not only at the strike. The arithmetic is
  byte-for-byte what it was — no gameplay moved; the number is simply now visible where it is
  used. `_stat_provenance_text` names it (`+N relics`) instead of leaving it out of every
  bucket, which is why the decomposition used to fail to sum to its own header.
  - **Latent bug found doing this: `effective_atk()` did not floor at 0.** `steady_banner` can
    drive the total negative, and `take_damage(effective_atk())` is a real call shape in six
    places — so a negative total would have **healed its target**. Floored at the source now.
- **§4 #3 bodyguard redirect — FIXED.** The ward gets a `TAKES IT` chip (shield-blue, guardian
  device) which mirrors to the chronicle via `log_status`. Deliberately carries **no number**:
  the ward already prints its own damage numeral, and a raw-blow figure beside it would put two
  numbers for one hit on one body.
- **§4 #7 fully-absorbed blows — FIXED, but DORMANT.** A hit entirely eaten by a wall used to
  show *nothing*, indistinguishable from a dropped attack; it now says `WALL HOLDS`.
  **However — `_get_wall_reduction` is currently dead.** It counts only creatures whose passive
  is `cannot_attack_wall`, and **no card in CardDB carries that passive** (Iron Bastion, its last
  holder, became Honor Guard's `column_ward` on 2026-07-15). So the reduction is always 0 and
  the new callout cannot fire on any board that exists today. It is left in as a correct guard
  for whenever the passive returns.
  **Resolved 2026-07-29 — KEEP, but documented as unproduced.** Independently confirmed: three
  consumers (`Card2D.gd:754`, `Combat.gd:6533`, `Combat.gd:7518`), **zero producers** anywhere in
  `scripts/`. Kept because it is a coherent designed passive (can't attack + can't be sniped +
  lane-scoped face reduction), not orphaned debris, and because it is the only surviving arm
  guarding the **forecast/resolver parity contract** — deleting it deletes the only test of that
  contract. Unlike Runic Pyramid it advertises nothing to the player, so it is an unused hook
  rather than a broken promise. The standing risk is that an inert function can regress
  invisibly, which is an argument for keeping its probe coverage regardless.
- **§4 #8 Command gains — FIXED.** `_pulse_mana_label` gained an `is_gain` arm (default false,
  so all five existing spend call sites are untouched) and is now wired at the battlecry, Coin,
  Bloodletting, Raider's Oath and Warm Knucklebone sites.
- **§4 #11 escalation — FIXED.** The elite branch gives *every* enemy +1 ATK permanently and
  announced it with nothing but four simultaneous unexplained floats. Now names the cause.
- **§4 #4 relic triggers — DONE.** ⚠️ **CORRECTION.** An earlier pass of this doc reported "42
  report a beat, 88 do not". **That was wrong** — a regex bug in the audit script under-counted
  `_relic_fired` call sites. Ground truth, re-derived with a corrected extractor: **130 relics
  are checked in Combat.gd; 106 already reported a beat; 24 did not.** Relic signalling was
  never in the state the audit claimed.
  Of the real 24, **14 are continuous auras or standing rules where a firing pulse would be
  wrong** — `champions_belt`, `corner_stone`, `diagonal_crest`, `glass_cannon`, `linked_banner`,
  `phalanx_stone`, `piercing_crown` (all answered by `relic_atk_buff` above), plus
  `deep_satchel`, `catapult_crew`, `sentinel_pact`, `junk_slot`, `lean_mean`,
  `marathoners_sash`, `bone_hourglass` (flat max-Command and predicate relics).
  Of the remaining 10: **6 now wired** — `veterans_medal`, `iron_legion`, `totem_pole`,
  `hourglass_of_ruin`, `philosophers_stone`, `happy_flower` (periodic, so a real moment unlike
  the flat max-Command relics beside it) — plus Phoenix Heart and Butcher's Cleaver earlier.
  **3 deliberately left silent:** `articles_of_war` and `tricksters_glove` are cost reducers
  evaluated on every affordability refresh, so a pulse there would fire continuously; and
  `runic_pyramid` sits behind `if not PERSISTENT_HAND`, which is **dead code in the live build**.
- **Reduce Motion mis-gates — ALL THREE FIXED.** `ClashLaneFocus`, `_pulse_passive_plaque` and
  the battle-log tab pulse now light-and-cool instead of punching, so a Reduce Motion player
  stops receiving *zero* signal for a fired passive or a new log line.
- **§4 #4/#12 `column_ward` / `hp_floor` rail entry — already built**, verified live (it landed
  in the uncommitted status-riders pass *after* this doc's audit ran, which is why the audit
  listed it as missing). Gated by `_probe_status_riders` at 66 checks.

### Tier 3 — the summary (BUILT)

- **Corpses now name themselves as they fall**, side-tinted (gilt yours / ember theirs). The
  capture showed five bodies vanishing at `THE FALLEN` with nothing on screen naming any of
  them. Deliberately the NAME, not a cause: attribution would need a damage-source ledger the
  clash does not keep, and against a ~4-fact retention limit a longer string buys nothing.
- **`_post_clash_ledger()`** prints one line ("2 of ours down, 3 of theirs"). One sentence, no
  panel — a modal ledger every round would be a worse tax than the problem. Silent on a
  bloodless clash.

### Tier 4 — speed (BUILT)

New **"Clash Pause"** setting: `UserSettings.clash_dwell_scale`, steps
`[0.0, 0.6, 1.0, 1.5, 2.0]` → Off / Brief / Normal / Long / Study, with
`clash_dwell_time(base)`. Kept **separate from Animation Speed** because that scales every tween
in the game including menus, while this is specifically the "let me read the board" pause — a
player may want fast animations and long reading pauses, or the reverse. `_lane_dwell` composes
both, and `Off` skips the pause outright rather than awaiting a zero-length timer.

**Three real bugs found auditing the existing speed setting:**
1. The dropdown's `var selected := 1` fallback **displayed "Slow" while the stored value was
   something else** — and left it wrong forever, with nothing on screen able to reveal it. (The
   fallback wasn't even the default; 1.0 is index 2.)
2. **`load_settings` bypassed the clamp entirely.** The setter was the only guarded door and a
   save file walks straight past it — a negative `anim_speed` makes `anim_time()` return
   negative durations, i.e. **every tween in the game broken at once from one bad save.**
3. The step table lived only in the overlay, so model and UI could disagree by construction.

### Harness bug — FIXED, and far worse than first reported

`Card2D._combat_vfx_target()` resolves its VFX host via
`get_tree().current_scene.has_method("spawn_floating_number")`, but `root.add_child(combat)`
never sets `current_scene`, so it returned null and every Card2D-originated beat silently
no-opped: damage numbers, keyword chips, **and the chips' `log_status` chronicle rows**.

Not 2 harnesses — **24**, all now fixed with `get_tree().current_scene = <combat>`. Proven by a
new A/B harness `tools/_shot_vfx_host.gd`: the identical staged blow renders **0** floating
numbers with `current_scene` stale and **1** with it assigned; the before/after PNGs show the
same token at 3/5 (it *took* the damage either way) with the number present in only one.

**Deliberately not patched:** ~60 headless *rules* probes share the stale `current_scene`, but
it has no observable consequence there (Combat's resolvers never call `_combat_vfx_target`;
only Card2D's presentation helpers do). Patching them would add a Label + Tween + log row per
damage instance across `_probe_autorun`'s thousands of fights for zero assertion value.

### Verification status — FINAL (2026-07-29)

**Full-tree stability sweep, run to completion (~55 min):**
```
[conserve] fights: 56  checks: 473  FAILS: 0  softlocks: 0 []
[conserve] DONE (all green)
```
`_probe_fighttrace` across five encounter shapes — boss (`hollow_king`), General
(`rival_raider`), plain holds (`wolf_pack`, `borrowed_faces`), reactive passive
(`necromancer_tower`), plus `elemental_nexus` and `mercenary_company` — all completed with
**zero `SCRIPT ERROR` and zero `Invalid access`**. Only the project's usual teardown noise.

`_probe_combat_telegraph` finished at **51 pass / 0 fail** (37/2 at the start of this pass).

⚠️ **Harness gotcha:** run combat probes as `.tscn` where one exists. Under `--script` the
autoloads are not loaded, `Card2D.gd` then fails to compile ("Cannot infer the type of `od_bb`"
— `KeywordEffects.decorate_keywords` has no resolvable return type), and the run reports bogus
errors or aborts. Same false-positive class CLAUDE.md documents for `--check-only`.
`_probe_fighttrace` has no `.tscn` and is `--script`-only, so it emits this noise
intermittently — re-run before believing a failure.

### Verification status (earlier in the pass)

`_probe_parsecheck` **PASS (113 scripts)** — the real gate · `_probe_beat_spacing` **63 PASS**
(new) · `_probe_overkill` ALL PASS · `_probe_muster_delay` ALL PASS · `_probe_anim_clock` ALL
PASS · `_probe_creature_fx` ALL PASS · `_probe_status_riders` 66/0 · `_probe_copy_lint` PASS ·
`_probe_text_floor` ALL PASS.

**`tools/_probe_beat_spacing.gd` (§8) is BUILT.** It gates the 100–500 ms band with an
allow-list of **pinned values**, each carrying a written reason and a `kind` — `"fusion"` (in
the band *by design*, being the internal duration of ONE perceived event) or `"grandfathered"`
(inherited debt, printed as a debt list every run). Its teeth are the value pins and the
rejection of unknown constants, both demonstrated with a negative control: drifting a pin or
orphaning a waiver fails the probe. Current debt: `POST_HIT_BEAT` 130, `HITSTOP_BEAT` 260,
`COMBAT_PAUSE_SHORT` 150, `COMBAT_PAUSE_MEDIUM` 300.

`_probe_combat_telegraph` reports **46 pass / 2 FAIL** (was 37/2; the 9 new assertions gate the
OVERKILL forecast). The 2 failures — "Iron Bastion reduces an open face strike by one" and
"Virulence matches the live Shield interaction" — are **pre-existing and not caused by this
pass**: the first exercises `_forecast_face_strike`, a different function from the one edited;
the second has `overkill == 0` after its shield break, so the new branch cannot fire. Tracked
separately.

## 11. Still open — the backlog, in priority order

**1. Play a fight and feel it.** Nothing here has been judged by eye at full speed. The whole
pass is verified by probes, arithmetic and frame captures of the *old* build. The open questions
are all taste: is `LANE_DWELL` 0.30 s right, does a busy round now feel slow, does the corpse
naming read as informative or as clutter at five-at-once? **Do this before any further tuning** —
and judge it by the frame-gap list, never by time-to-playable alone (a change that hides work
inside a synchronous block improves neither).

**2. The remaining discrete-event relics. — DONE 2026-07-29.** Relics reporting a beat went
**47 → 108** of 133 ids checked in Combat.gd (63 `_relic_fired` sites added across 61 ids); 25
were judged aura and deliberately left silent. The rule that settled it, worth reusing: **a
blanket property of a card *class* is an aura; a payoff conditional on the *situation* is a
moment** — Veteran's Medal (every 1-cost) is an aura, Spotter's Glass (only into an empty
column) is a moment. Every beat is gated so it fires only when the effect actually landed, and
all `_forecast_*` / `_predicted_damage_against` checks stay silent — **a hover must never pulse
a chip.** Behaviour is unchanged: every edit is a bare `_relic_fired(...)` or a local bool
gating one.

Three oddities found in passing, all on `retired: true` relics, i.e. **no live defect**:
`runic_pyramid`'s only implementation sits inside `if not PERSISTENT_HAND:` and that const is
`true` (dead code, but it is a retired relic); `mark_of_pain` has a dead local reading `value`
(which is the +1 Command, not the curse count — the hardcoded `for _i in 2` correctly matches
the printed text); `cavalry_sigil` reports inside its column loop and can fire twice a round,
swallowed by the funnel's debounce. Retired relics stay visible in the Collection by design
(`RelicDB.gd:15`), so Runic Pyramid still advertises a rule the persistent hand abolished —
cosmetic, but it is a promise the game cannot keep.

**3. `has_encounter_passive_keyword` grants never reach `card_data.keywords`** (§4 #10).
**DONE 2026-07-29 — but NOT the way this entry proposed, and the reason matters more than the
fix.** Following `sentinel_stone` / `formation_drill` and appending the grant to
`card_data.keywords` would have corrupted four separate readers:

| Reader | What breaks |
|---|---|
| `_defection_steal_target` | `DEFECTION_STEALABLE` contains **both** `"thorns"` and `"piercing"` — the Free Company Captain would loot a *battlefield rule* off a dragon and keep it permanently. |
| `copy_last_dead` (Doppelganger) | copies a corpse's dict onto a player body — launders a field rule onto your side. |
| `_desert_enemy_to_player` | `card_data.duplicate(true)` walks the whole dict across to your banner. |
| Silence / strip / dispel | these *erase* from `keywords` — a strip would delete the ORB while the lookup went on returning true, printing a card that claims it doesn't pierce while it does. |

So the mirror rides its **own** `card_data["encounter_grants"]` key with exactly one reader
(Card2D's rail), refreshed by `Combat._refresh_encounter_keyword_grants()`. The rules path is
byte-identical — every strike site still calls `_has_encounter_passive_keyword`. Now visible:
`nexus_rotation`, `stampede_charge`, `merc_piercing` (verified going OFF as well as on),
`dragon_lord_piercing`, `dragon_lord_phase2`, `swamp_thorns`. Left lookup-only: `stone_armor`
(its arm is a tautology — true only for a card already printing Armored) and `harpy_swift_face`
(returns `false` unconditionally). The callout fires only on the **OFF→ON edge on a body already
standing**, latched per body per round, or a `swamp_thorns` opening would throw four chips over
the intro. `sentinel_stone` / `formation_drill` / `iron_warden_siege` were left alone —
they already leak into all four readers above, but that is long-standing shipped behaviour and
changing it is a rules change, not a signalling one. **Open question for a future pass.**

**4. `_summon_enemy_token` / `_summon_enemy_token_with_keyword` return `void`. — DONE
2026-07-29.** Both now return `Card2D`, or `null` on a full / closed / salted board. They read
the placed body back out of the board array rather than trusting the request — a body *can*
arrive and die inside `_place_enemy_card` (Poisoned Rations, a Wolf-Pit), and the array is the
only thing that knows. `EncounterEffects.announce_arrival(ctx, card, msg)` replaces
`(ctx, before, msg)`: a `SUMMONED` chip on the arriving body plus a chronicle row carrying that
body's own thumbnail and side tint. All 12 call sites converted; every before/after
`_all_enemy_creatures().size()` sample is gone. **11 `_show_info` captions removed** in favour
of on-body chips — which also buys back info-queue budget, since `necro_death_summon` fires once
per corpse and a three-kill clash used to spend a whole flush on it.

**5. Tier 2's own-line forecast. — DONE 2026-07-29.** `_refresh_lane_forecast` looped only
`_row_array(true, ...)`, so the player could see what would be done TO them but not what their
own line would do, except by hovering one card at a time. That is half a forecast: *"should I
trade here"* is a question about both columns at once. The predictor already handled friendly
attackers (the hover twin used it) — it was simply never asked. Now iterates
`[true, false]`, enemy first so the incoming threat is built before ours and the later chip
stacks clear.
**Watch the chip count in play.** This can double the overlay on a full board. They are
`quiet_text` chips, not animating actors, so they do not spend the ~4-concurrent-motion budget —
but if it reads as clutter, the intended next dial is narrowing to **decisive lanes only**
(kills / deaths), **not** reverting to enemy-only.

**6. Pay down the grandfathered beat debt. — MOSTLY DONE 2026-07-29.** Five further strike paths
were routed onto `_impact_hold` (the 150–230 ms damage-scaled band): the Swift-phase punctuation,
the face-strike cascade, the Hydra face swing, the Sniper face shot, and the Sniper body shot
that chains on a kill. **Every solo strike path now shares one hold function.**
The four constants still exist and `_probe_beat_spacing` still lists them as debt, because their
remaining users are (a) **CombatNet replay paths**, deliberately untouched — see item 10 — and
(b) two non-strike cascade pauses (the Hydra full-line sweep, the reinforce caption). Both are
arguably `fusion` beats and could be reclassified in the probe's waiver table rather than
retimed; that is a judgement call left for whoever next reads the debt list.

**7. Two pre-existing `_probe_combat_telegraph` failures — DONE 2026-07-29. Both were STALE
PROBE, not broken code.** Now **51 pass / 0 fail** (48 → 51 assertions: −1 stale, +4 new).

- *"Iron Bastion reduces an open face strike by one"* — the mechanic was cut. `iron_bastion` is
  now **"Honor Guard"** (c4 2/7 rare, `passive: "column_ward"`) from the 2026-07-15 interest
  slate, and `_get_wall_reduction` has only its `cannot_attack_wall` arm left. The forecast
  returning full damage was **correct**. Replaced with the contract it was actually guarding —
  forecast and resolver must apply the same wall reduction — exercised two-sided through the
  surviving arm (reduces within the lane, must not reduce three lanes away).
- *"Virulence matches the live Shield interaction"* — **the rule itself flipped and the probe
  kept the old answer.** The poison branch used to gate on `atk > 0`, so a blow a Shield
  swallowed whole still killed — while the comment two lines above claimed the opposite. It now
  gates on HP actually removed (`_apply_creature_strike_poison`), and the forecast already
  agrees. Rewritten as three checks, including a **positive control first** (without it, "no
  poison" would pass for free if `_virulence_active` were ignored outright) and a live
  cross-check through the two functions the real clash uses.

Method note worth keeping: the replacements were proved to have teeth by a **negative control** —
expectations temporarily inverted, both failed with real values printed, then reverted. Do this
whenever a probe assertion is rewritten; the failure mode of "fixing" a probe is weakening it
into something that cannot fail.

**8. `_shot_battle_log` stages status effects on enemy bodies that don't exist — DONE
2026-07-29.** The cause was the muster change, but not where this entry guessed: it is **TAKE
THE FIELD (2026-07-27)**. `_opening_muster_pending` is deliberately left standing through round
1 and consumed by `_enemy_place_creatures` inside `_post_combat_sequence`, so **the enemy line
arrives at the END of round 1** — the harness slept 6 s and staged into a board that is empty
*by design*. With the muster delay, the first board with live enemy bodies that may also fight
is **round 2**.

Fixed by replacing the sleep with `_await_state(min_round, want_enemies)` polling
`round_number` + `phase == PLAYER_TURN` + occupancy. Two flakiness sources also closed: a
windowed harness sits in the live desktop session with its window foregrounded, so **stray
keystrokes really do reach `Combat._input`** (previous frames had the FIELD CARD primer and an
"End Turn?" confirm covering the board) — now `end_turn_warning = false` and
`set_process_input(false)`. **The harness now fails loudly**, exiting 1 with
`BATTLE_LOG_SHOTS_INCOMPLETE` on no enemy bodies / <2 rails / <5 log rows / no hover preview.
Running green while rendering nothing was the defect; it can no longer do that. Result: 2–3
enemy bodies with live tinted rails, 9–11 log rows (was 4), 7–9 illustrated, hover preview
present, stable over two consecutive runs. Nit, not a bug: the Bowman row has no thumbnail —
that token has no art on disk.

**9. Pixel-level confirmation of the float-anchoring and hit-flash fixes. — DONE 2026-07-29.**
Both are now confirmed in sampled pixels by a purpose-built harness,
`tools/_shot_float_flash.gd`, which measures node geometry *and* real pixel values.

- **Damage-number anchoring — CONFIRMED.** Across the full 0.72 s rise the numeral never leaves
  its victim: at the old drift timestamp (t=454 ms) it sits **51 px below the token's top edge**
  and comes to rest 34 px inside it. Verified for the `big` (≥5 damage, 72 px) variant too.
  *Caveat:* by t=720 ms it is at ~25% alpha, so "ends on the token" is geometrically true but
  nearly invisible — the meaningful window is ~0–500 ms.
- **Hit-flash vs the wax seals — CONFIRMED, after two metrics lied.** Worth recording, because
  the near-miss is instructive: `max − min` *passed while the flash was not running at all* (the
  glyph's black outline pins `min` at 0), and `p90 − p10` **failed the shipping build** and would
  have been reported as a regression — wrong because the numeral is only a few percent of the
  label rect, so at peak `p10` is still bleached seal, not ink. The fix works by a **polarity
  flip**: white-on-dark at rest becomes dark-charcoal-on-bleached at peak, with the outline
  intact. The correct metric is "how far the ink sits from its background *in either
  direction*" — final legibility 0.70 (ATK) / 0.76 (HP) at peak against a 0.45 floor, with a
  paper-brightening control (0.59 → 0.94) giving the assertion teeth.

**Two more traps for whoever re-shoots the remaining 19 harnesses**, on top of the two in #8:
**the live desktop cursor still causes hover overlays** — `set_process_input(false)` does *not*
stop mouse hover, and a frame was ruined by a stray "HELD" targeting overlay, so park the cursor;
and **a staged blow that KILLS its victim** leaves a correctly-anchored numeral floating over an
empty lane, which looks exactly like the drift bug you are testing for.

Also fixed in passing: **`_shot_creature_fx` was hard-failing at exit 1** (`need >= 2 enemy
bodies` — the same empty-board trap as #8) and now renders its 13 frames; `_shot_phase_beats` was
shooting its `clash_commit` frame over an empty arena, contradicting its own comment.

**10. Skirmish parity — the NON-TIMING half is DONE 2026-07-29; the timing half stays solo.**

The distinction that makes this tractable: a **beat** suspends the turn machine, a **label** does
not. Everything in this pass that only draws something can cross into net safely; only the
pauses cannot.

Crossed over:
- **The lane spotlight.** `_focus_combat_lane` used to bail on `_is_net()` alongside the pacing
  beats, but it adds no time and suspends nothing, so none of that reasoning applied to it.
  CombatNet's clash calls `_resolve_column_attack` directly (`CombatNet.gd:1488-1495`), so
  removing the guard was a one-line change and the mark simply works there.
- **Corpse naming.** `_cleanup_dead_paced` still bails to the synchronous `_cleanup_dead()` in
  net, but now names the fallen first. Skirmish had exactly the same "five bodies vanished and
  nothing said who" problem, and a floating name is a label, not a beat.

Still solo-only, deliberately: `_round_beat`, `_lane_dwell`, the death-flush pacing and the
rank captions' timing. `_start_round`'s two net callers
(`CombatNet._sealed_open_orders_local`, `_net_local_turn_begin`) are plain `void` functions with
several callers each plus Combat-side delegators; pushing a coroutine through the hardest-to-
verify layer in the project for a cosmetic gain is still not worth it. **So the net round-open
does still land on one frame.** If that matters, it is its own project — and it should start by
making that chain async deliberately, not by sneaking an `await` into `_round_beat`.

Verified after the change: `_probe_skirmish_combat` ALL PASS · `_probe_sealed` ALL PASS ·
`_probe_turnorder` strict alternation, 0 back-to-back turns.

## 12. The visual critique (2026-07-29) — what shooting the clash actually found

The pass was probe-green and pixel-verified *per effect* before anyone looked at the clash **as a
whole**. Doing so found one catastrophic bug, two of this pass's own fixes only half-working, and
a set of pre-existing defects. Harnesses: `tools/_shot_clash_read.*` (staged 4v5, designed
outcome pattern, ~63 ms capture), `tools/_shot_clash_flush.*` (16-body mass grave),
`tools/_probe_lane_focus.*` (geometry + pixel proof).

### FIXED — the spotlight had never drawn a single pixel

`ClashLaneFocus` was a **0×0 Control for its entire existence**. `_ready` called
`set_anchors_preset(PRESET_FULL_RECT)`, which recomputes *offsets to preserve the current rect* —
and at `_ready` the node is already in the tree at 0×0, so it anchored itself to nothing. `_draw`
clamped its slabs against `size`, got `x1 <= x0`, and returned every frame. `_strength` still
tweened to 1.0 and reported healthy to every probe, which is why nothing caught it.

Measured before: unfocused board ratio **0.982** — byte-identical pixels focused vs not.
After `set_anchors_and_offsets_preset`: **0.486**. `tools/_probe_lane_focus` now gates it.

Two consequences worth internalising:
- **The serialized clash shipped with no attention-direction cue at all.** The only thing telling
  you which column was resolving was the lunge animation.
- **The 0.30 → 0.46 ink raise was made against a control that rendered nothing**, on the
  reasoning "at 30% the surround was suggestion, not direction" — an observation that could not
  have been true. The raise is **withdrawn**, not re-guessed: 0.46 measured as *over half the
  light removed*, a blackout rather than a spotlight. **This value now needs real eyes.**
- Same defect fixed in `EventLayoutStage.gd:60`. Prefer `set_anchors_and_offsets_preset` on
  principle — harmless when the node is already sized, fatal when it isn't.

### FIXED — two of this pass's own fixes were only half-live

- **The post-clash ledger was printing falsehoods.** `_enemy_deaths_this_round` was incremented
  only inside `if _is_net() and was_enemy:`, so it was permanently **0 in the campaign**. The
  "the line holds" branch was unreachable, and a clash that killed two of theirs printed
  *"2 of ours down, none of theirs"* with the foe's corpse chips still on screen. A summary that
  contradicts the board is worse than no summary. The counter now increments for both modes.
- **OVERKILL never reached the always-on chip.** `_forecast_creature_impact` appended the spill
  to `text` (hover) but `quiet_text` is rebuilt from scratch, and `_forecast_chip_text` reads
  `quiet_text` first — so Tier 0 #1 explained overkill on hover and was silent on the board
  forecast a player actually glances at. Now appended to both.

### FIXED — the clash outgrew its time budget

Measured end-turn → playable on a full 16-body board: **9317 ms → 15698 ms (+69%)**, past
Nielsen's 10 s, with **no skip affordance anywhere in Combat**.

**Hold `ui_accept` to rush** — `_short_pause` divides by `CLASH_RUSH_FACTOR` (5×) while held.
Deliberately a *held key*, not an engine ramp: Battlegrounds auto-accelerates and its players
report "the board would pretty much just explode." Holding means the player chooses per clash,
with the board in front of them, and releasing restores full pacing mid-beat. Polled rather than
wired through `_input`, which is owned by spell targeting.

### What works and should not be touched

- **The per-lane dwell is the part that landed.** Each column gets a genuine rest (front lane 1
  with 2 strikers, no kill: 1043 ms; lane 2 with 2 kills: 1317 ms); lanes do not blur; and
  `_lane_will_strike` correctly skips dead columns (the focus jumped 126 → 394 past an emptied
  lane).
- **Corpse naming was NOT the predicted problem.** At 4–5 simultaneous names it reads well —
  ember/gilt across four columns, same-column piles cleanly offset, peak 6 concurrent chips still
  legible because they are static text.
- Rank captions fire *before* their rank, and the empty-rank gate works.
- Overkill at resolution, `BLOCKED` chips, and the Standard Bearer's debuff caret all read well.

### Found by the critique — ALL SIX NOW ADDRESSED (2026-07-29)

1. ~~**The always-on forecast stacks labels at one anchor and the survivor LIES.**~~
   **MITIGATED 2026-07-29 — the lie is gone; the aggregation is still wanted.**
   Labels anchor at `_card_center(target)` but the loop runs per *attacker*: 9 created,
   **7 visually distinct**. One that vanished mattered — a 4 HP Outrider targeted by a 2 ATK and
   a 3 ATK body showed only **"TAKES 3 - 1 HP"**. True incoming was 5; it died that clash. That
   is the *"I'd have played differently"* failure verbatim, manufactured by the UI, and it
   **predates** the both-lines change (both attackers were enemies) — the change only made
   collisions likelier.
   Labels on the same (quantised) anchor now **stack upward** instead of burying each other
   (`_lane_forecast_anchors`), so no read is ever hidden and no number is ever under-reported.
   **AGGREGATION LANDED 2026-07-29.** `_forecast_group_by_target` sums the blows on each victim
   and `_add_lane_forecast_total` prints one chip — "TAKES 7 - 2 HP" or "SLAIN - TAKES 9" — while
   every arrow and ring still draws, because those say WHO is striking and the total cannot.
   **It refuses to aggregate where summing would be a guess.** Each `_predict_lane_strike` is
   computed independently against the victim's projected HP, so plain damage composes and can be
   added — but shields, Last Stand, rescues and death-followups are ORDER-DEPENDENT (a shield
   eats whichever blow lands first). For those victims the function returns nothing and the
   per-attacker labels stack instead: verbose, but every number on screen stays true. Replacing
   one honest-but-partial number with a confidently wrong total would have been a worse bug than
   the one being fixed.
   Superseded recommendation, kept for the reasoning: — one chip per body giving *total*
   incoming and the resulting outcome. Stacking makes the forecast honest; aggregation would
   make it concise, roughly halving the label count. Do that before narrowing to decisive lanes:
   narrowing alone would cut clutter while leaving several numbers where one belongs.
2. **Corpses standing at 0 HP for up to ~10 s. — MITIGATED (cosmetically, on purpose).** `Card2D.defer_deaths` holds for the whole clash by
   design (so a slain body still lands its scheduled blow) — but the clash is now 10.8 s on a
   full board, so the mass-grave frame is *fourteen cards reading 0 HP standing in ranks*. It
   reads as a bug and is a direct consequence of stretching the clash without revisiting the
   defer window.
   **Fixed cosmetically, NOT by flushing per rank.** Flushing between ranks would move when
   `on_death` / encounter hooks / reactive passives fire relative to the back rank's swings —
   a rules change smuggled in as a presentation fix. Instead `_mark_mortally_struck` (which
   already existed) was deepened from `0.42,0.38,0.36` at full alpha to `0.30,0.27,0.26` at
   0.78 alpha, so spent bodies visibly RECEDE from the line while remaining present — they
   must remain, they still owe retaliation. The duration itself is answered by the rush key.
3. **The rank caption covered the rank it named. — FIXED.** `_spawn_phase_pulse` sits at `vp.y * 0.245`,
   which is exactly the enemy back row — "THE BACK RANK" was drawn across the back-rank cards
   for ~1 s. Moved to `vp.y * 0.455`, the clash seam: the least-occupied band on the board and
   the right place for a line narrating where the two armies meet.
4. **The face-damage wash was enormous and effectively unscaled. — FIXED.** Full-screen ColorRect at
   `clamp(0.18 + dmg*0.045, 0.20, 0.42)` plus an 82–180 px border at up to 0.85 alpha. **One
   point** of damage measured +120 board redness at 76 ms, decaying over 330 ms — inside the band
   §1 condemns. It buried a death, its numeral and a PIERCING chip on the clash's first beat. The
   0.20 floor gave a 1-damage tickle ~48% of the loudest flash in the game.
   Now `clamp(0.07 + dmg*0.038, 0.09, 0.38)` with the decay cut 0.34 s -> 0.19 s. The wash is
   PUNCTUATION for the damage number, not information itself, so it must never mask the number
   it punctuates; the lower floor and steeper slope keep big hits reading big.
5. **`LANE_DWELL_KILL` measured imperceptible — but the measurement is CONFOUNDED.** 220 ms inside a ~1.0–1.3 s lane, confounded by
   striker count — a 1-striker kill lane (700 ms) is *shorter* than a 2-striker no-kill lane
   (1043 ms).
   **Do not act on this yet.** The shoot ran with `ClashLaneFocus` drawing nothing, so there
   was no persistent frame whose duration could be felt — the only cue was lunge animation,
   whose length is fixed. With the spotlight now actually rendering, a kill lane holds a
   *visible* mark 73% longer, which may well be perceptible. **Re-measure before tuning.**
6. **The ledger collided with the round banner. — FIXED.** (posted at 6484 ms with a 2.0 s hold; "ROUND N"
   pops at ~8.0 s in 70 px type) and renders over a card at arena centre.
   `_show_turn_banner` now calls `_clear_info_queue()` and blanks the label: the round has
   turned, so anything still queued belongs to the round that just ended.

## 13. A rules leak closed on the way past (2026-07-29)

Not a legibility bug, found while reading the corrupting-reader table in §11 #3.

**The player could loot a battlefield rule.** `DEFECTION_STEALABLE` lists `"armored"` (first, so
highest priority), `"thorns"` and `"piercing"` — exactly the keywords an encounter passive lends
its own line. Three passives write their grant straight into `card_data.keywords`, and
`_defection_steal_target` read that array. So a Free Company Captain could kill a body that was
only Armored because The Tooth-Stones said so, and keep it.

**SCOPE CORRECTION.** An earlier draft of this entry said the grant was "carried into every later
fight of the run". **That is wrong.** `CardDB.get_card_data` returns `.duplicate(true)` and
`RunState.get_upgraded_card_data` passes that fresh dict on, so every player `card_data` is
per-draw, and `_resolve_defection` writes only to `attacker.card_data.keywords` with no `RunState`
write anywhere. The leak is **fight-scoped**, not run-scoped. Still wrong, an order of magnitude
less bad.

**And the first fix did not work.** It checked only `_has_encounter_passive_keyword`, which
matches on `_encounter_passive` and has arms for the six *conditional* grants only —
`sentinel_stone`, `formation_lockstep` and `iron_warden_siege` fall through to `return false`.
The guard was therefore **inert for exactly the three passives its own comment named**. A good
reminder that a guard which compiles, passes every gate, and is confidently commented can still
do nothing at all.

**The working fix is provenance, not relocation.** Moving these writes onto the
`encounter_grants` mirror would have been a silent nerf: `Card2D.has_keyword` is the *only*
reader of Armored for damage, and four more `keywords`-only readers (the overkill arithmetic in
Combat and its CombatNet twin, `_forecast_card_has_keyword`) would have gone blind too — deleting
Armored from three boss phases while looking like a signalling fix. Instead the source is
recorded **alongside** the real write, via `FIELD_GRANT_KEY` / `_mark_field_granted` /
`_is_field_granted` in Combat (`sentinel_stone`) and the matching stamp in EncounterEffects
(`iron_warden_siege`, lockstep). The guard now checks provenance first and the conditional lookup
second, so it is correct whichever way a passive chooses to grant.

**Verification trap for anyone revisiting this:** `_probe_fighttrace` **cannot reach two of the
three sites.** `formation_lockstep` and `iron_warden_siege` both sit on `threshold: 0` FINAL boss
phases the trace bot never reaches (it stalled at 18–23 HP against `iron_warden` across four
heroes). A before/after trace there is *vacuously identical* and must never be reported as
evidence. Only `stone_sentinels` is reachable. Verify the other two with a staged probe in the
`_probe_combat_passives` style instead.

Still open: `copy_opposing_keywords` / `copy_last_dead` and `_desert_enemy_to_player` copy the
raw array and could be filtered against the same key. Lower priority — nothing escapes the fight.

## 14. Visual verification of the blind fixes (2026-07-29)

The five presentation fixes in §12 were made without eyes on them. Re-shot with
`tools/_shot_clash_read.tscn` (198 frames, ~63 ms apart, act-2 board, 4v5) and the frames read
back. **Confirmed working, with frame evidence:**

- **The spotlight renders and moves.** Dwell census shows it visiting lanes in order and holding
  1326 / 1069 / 1368 / 737 / 683 / 2272 ms. Visually the red surveyor bracket does most of the
  directing; the 0.30 ink is a supporting separation rather than the primary cue. **Recommendation
  after looking: keep 0.30.** The bracket carries the direction, and at 0.46 (unfocused board at
  0.486 of lit) the surround reads as a blackout rather than context.
- **Corpse naming reads well** — `f130`: "SQUIRE" and "FOOTMAN" in ember over the lanes they fell
  in, well spaced, fully legible. The predicted multi-name pile-up did *not* materialise.
- **The ledger is correct and legible** — `f130` prints *"2 of ours down, 3 of theirs."*, matching
  the board. Before the `_enemy_deaths_this_round` fix this sentence was **structurally
  impossible**; it could only ever have said "none of theirs".
- **`THE FALLEN` fires at `down=5`** — i.e. while the corpses are still standing, before the
  flush. That was the ordering bug.
- **The deepened corpse slump works** — dead bodies are unmistakably recessed from the living line
  (`f014`: 3/0 and 7/0 clearly spent).
- **The phase pulse now sits at the seam**, off the enemy back row.
- Peak concurrent floating numbers **3** (inside the ~4 object-tracking budget); callout chips
  peak at 5, marginally over.

### The face flash needed a second pass

After the wash rescale the board still measured **peak +129 redness with a ~406 ms decay**. Cause:
only the full-screen ColorRect had been rescaled — the **border Panel was untouched**, and its
floors were the real problem (`0.45` alpha and `80 px` minimum, so a ONE-POINT hit drew more than
half the maximum frame, over a `0.40 s` fade sitting across the next beat). Rescaled to
`clampf(0.16 + dmg*0.045, 0.20, 0.72)` / `clampf(38 + dmg*11, 46, 150)` / shadow 50→30 / decay
0.40→0.22. Re-measured: **peak 129 → 94, decay ~406 ms → ~168 ms** — out of the condemned band
while still reading as a real blow.

### `_probe_fighttrace` is NOT a regression oracle — do not treat it as one

`stone_sentinels` read WIN 6r/30 earlier and LOSS 8r later. It is **deterministic within a moment**
(three consecutive runs identical) but **drifts between invocations**, because these probes boot
real combat and write `user://` state. An A/B — reverting the face-flash values, re-running,
restoring — produced **the same LOSS either way**, proving the visual change was not responsible.
Use `_probe_combat_passives` / `_probe_field_grants` / `_probe_overkill` for behavioural
regression; use fighttrace only for "does a fight complete without script errors".

## 15. Adaptive pacing — spending the budget where the information is (2026-07-29)

Serializing bought legibility with time (+69%). The fix was not to shorten every beat but to stop
paying the same for every lane.

**Per-lane triage** (`_clash_lane_pass`). A lane that killed something, broke through to a face,
or landed a heavy blow is a separate event and keeps its full ≥300 ms dwell. A lane that only
chipped HP gets `LANE_DWELL_MINOR` (0.09 s) — deliberately *below* the causality window, so it
FUSES with its neighbour instead of claiming a registration slot. §1's two defensible modes are
not exclusive; they can be chosen per lane.

Measured on a 4v5 board:

| | before | after |
|---|---|---|
| kill lanes | 1326 / 1368 ms | 1423 / 1286 ms (kept) |
| ordinary lanes | 1069 / 737 ms | 496 / 710 ms |
| trivial lane | — | **241 ms** (fused) |
| `THE FALLEN` reached | 6139 ms | **5598 ms** |

The kill-to-trivial ratio went **1.24× → ~6×**, which also retires §12's "`LANE_DWELL_KILL` is
imperceptible" finding: it is now the loudest beat in the clash rather than a 220 ms difference.

**A mass grave is one event, not sixteen.** Adaptive dwell does nothing for a full board, because
when every column is lethal nothing is trivial. There the cost was the flush: **16 corpses at
~210 ms each = 3.4 s enumerating bodies nobody can count.** Subitizing tops out at 3–4; past that,
counting collapses however slowly you present them, so the sixteenth individually-paced corpse
buys no comprehension and costs a third of the clash. `FLUSH_BUDGET` (1.30 s) is now divided among
the corpses: a 2-body trade keeps its full readable beats, a wipe compresses toward one swept
event. **Full board 15.7 s → 12.9 s.**

**Naming is gated on SPREAD, not count.** Compressing the flush stacked the names — a measured
wipe put **14 concurrent name chips** on screen, 3.5× the object-tracking budget. First attempt
capped naming at a raw corpse count of 4, which was too blunt: an ordinary 5-body trade would have
lost its names. The real trigger is whether the flush is still spread enough to read one at a
time, so the gate is `death_beat >= DEATH_BEAT * NAME_SPREAD_FRACTION`. A 5-body clash still paces
at full `DEATH_BEAT` and keeps its names; a 12+ body wipe drops them and lets the ledger carry the
count (the chronicle keeps every name regardless).

Result: peak concurrent chips **14 → 2** on a wipe, **5** on a typical board, names intact where
they can be read.

## 9. Sources

Perception: Straube & Chatterjee 2010 (causality); Dux & Marois 2009 (attentional blink);
Cowan 2001 (working memory); Pylyshyn & Storm / Meyerhoff et al. 2017 (object tracking);
Piazza et al. 2012 (subitizing); Rayner 2009 (eye movements); Rensink et al. 1997 (change
blindness). Craft: Heer & Robertson 2007 (staged animated transitions — the architectural
citation); Sirlin on impact freeze; Sakurai Famitsu 490 (hitstop scaling); Lin et al. 2022
(impact feel); Sakamoto GDC 2015 (Hearthstone's board cap set by readability); Nielsen
response-time limits; Game Accessibility Guidelines (game speed).

**Explicitly NOT cited:** Swink's widely-repeated "240 ms = frustration" threshold could not be
verified against *Game Feel*. Do not use that number.

**Genuine literature gap:** there is no substantial craft writing on autobattler combat
legibility — no GDC talk, no postmortem. Player-forum complaint is abundant but is evidence the
problem is real, not evidence for any particular fix.
