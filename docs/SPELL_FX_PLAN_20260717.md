# Spell FX — the complete plan (2026-07-17)

Goal: spells that look AAA. Companion to
[`ANIMATION_COOL_PITCH_20260717.md`](ANIMATION_COOL_PITCH_20260717.md) (whose
material thesis and bake-then-shade unlock apply here too) and
[`ANIMATION_AUDIT_20260716.md`](ANIMATION_AUDIT_20260716.md) (the Motion clock,
grammar and FX funnels this builds on).

Audited with `tools/_probe_spell_fx_audit.gd` (new — scrapes `SPELL_FAMILIES`
out of Combat.gd so it can't drift from the live map, and walks
`CardDB.CARD_POOL`). **Re-run it after any spell is added: it fails loudly on
untagged spells and dead tags.**

---

## 1. What the data says

| | |
|---|---|
| Spells in the pool | **78** |
| Tagged into a family | 45 — mind 14 · blight 10 · earth 7 · blessing 6 · fire 6 · shock 2 |
| **Untagged → generic colour puff** | **33 (42%)** |
| **Dead family tags** (id not in CARD_POOL) | **6** — `lightning`, `bloodletting`, `second_wind`, `reposition`, `barricade`, `scrap` |

Two thirds of the *shock* family is a lie: it has 2 live members because
`lightning` was one of the 6 dead ids.

## 2. Why it doesn't look AAA (the structural problem, not the art)

`_play_spell_cast_vfx` does exactly one thing: **one burst, at one point, once.**

```
pos = target ? target.center : screen_centre
family = SPELL_FAMILIES[card_id]  ?: legacy colour burst
_vfx_<family>(pos)  →  _spawn_spell_impact_ring(pos)  →  play_sfx("spell_cast")
```

That produces the same shape of event for every spell in the game. Consequences,
straight out of the audit:

1. **Multi-target spells fire ONCE.** `Inferno`, `Mass Grave`, `Rout`, `Close
   Ranks`, `Scatter the Line`, `Ambush`, `Wildfire` are all `scope: ALL ENEMIES`
   — four bodies get hit and the screen shows a single puff at
   `(0.5w, 0.35h)`, a point where nothing exists. **This is the single biggest
   "not AAA" tell in the game**, and it's what the user means by *"a lot of
   things need more than one."*
2. **Nothing travels.** Every spell resolves where it lands, instantly. There is
   no cast, no flight, no arrival — so a Flame Bolt to the face and a Rout of
   the whole line are the same event with different colours.
3. **Nothing is left behind.** `Salted Ground`, `Wolf-Pits`, `Hoarfrost`,
   `Mark of Ash`, `Slow Match`, `Plague Bell` all *persist* as mechanics and
   vanish as visuals.
4. **42% have no flavour at all** — a generic coloured puff keyed off
   `spell.type`, and since 73 of 78 spells are `spell.type: "custom"`, that
   fallback can't even distinguish them. `Strike` and `Spark` (the two starters,
   the most-cast spells in the game) are in this bucket.

## 3. The fix: a spell is a SEQUENCE, not a burst

The grammar every AAA card game uses — and the thing this codebase is one funnel
away from:

```
CAST      the writ discharges at the hand card      (who did this)
DELIVERY  something crosses the board               (bolt / lob / sweep / none)
IMPACT    per TARGET, staggered                     (what it did — N of these)
AFTERMATH what the board keeps                      (scorch / frost / stain)
```

Only IMPACT exists today, and only ever once.

**The unlock: the shape is already in the data.** Every spell already carries
`targeting` and (for untargeted board spells) `scope` — printed on the card face
as its contract. That's a delivery spec we're not reading:

| data | delivery | impact |
|---|---|---|
| `targeting: enemy_creature` / `any_creature` / `friendly_creature` | single bolt, caster → target | 1 |
| `scope: ENEMY FACE` | bolt, caster → enemy portrait | 1, on the face |
| `scope: ALL ENEMIES` | sweep across the enemy line | **N, staggered 60ms** |
| `scope: ALL CREATURES` | expanding wave from the midline | **N, staggered from centre outward** |
| `scope: YOUR ARMY` / `YOUR FRONT LINE` | rise from your line | **N, staggered** |
| `scope: YOUR DEAD` | rise from the discard pile | 1 → per raised body |
| `scope: ENEMY BACK ROW` | arc OVER the front line | N |
| `targeting: lane` / `friendly_lane` | a bar down one column | N in lane |
| `targeting: two_enemies` / `friendly_then_enemy` | **two bolts in sequence** | 2 |
| `targeting: none`, no scope | at the caster / the pile | 1 |

**So coverage is derivable, not hand-authored.** `family` says what it's *made
of*; `scope`/`targeting` says what *shape* it is. 6 families × ~10 delivery
shapes covers all 78 by construction — then ~8 signature spells get bespoke
work on top. That is the only way "make the list complete" is affordable.

### The staggered impact is the money beat
Balatro's whole scoring feel is sequential activation: each card pops in turn
with a rising note. We already have the rising note — **C5's clash pitch
(`Card2D._next_clash_pitch`) is exactly this mechanism** and currently only
strikes use it. An `Inferno` that hits four bodies left-to-right at 60ms with
four rising notes is a different game from one puff at a dead point.

---

## 4. The complete assignment (all 78)

`†` = currently untagged (33). `‡` = signature, wants bespoke work beyond the
grammar. Delivery is derived from the spell's own `scope`/`targeting`.

### FIRE — rising ember cone, warm flash, scorch aftermath
| id | name | delivery | beats |
|---|---|---|---|
| `fireball` | Fireball | bolt → face | 1 |
| `flame_bolt` | Flame Bolt | bolt → face | 1 |
| `inferno` ‡ | Inferno | sweep, enemy line | **N staggered + rising pitch** |
| `fuel_the_pyre` | Fuel the Pyre | at friendly (consumes it) | 1 + sacrifice ash |
| `petard` ‡ | The Petard | lob → arc → blast | 1 + shockwave |
| `sappers_charge` ‡ | Sapper's Charge | bolt + **push physics** | 1 + crash per body |
| `mark_of_ash` † | Mark of Ash | bolt → target | 1 + **ash brand aftermath** |
| `slow_match` † ‡ | Slow Match | at target | 1 + **burning fuse that persists** |
| `slash` † | Breach Bomb | lob → blast | 1 |
| `forgefire` † | Forgefire | at your line | N + forge sparks (reuse `forge_strike`) |

### SHOCK — white-blue bolt, hard flash, brief hitstop
| id | name | delivery | beats |
|---|---|---|---|
| `holy_smite` | Holy Smite | bolt from above | 1 |
| `time_snare` ‡ | The Doubled Hour | **freeze the board**, YOUR ARMY | N + time-stop tint |
| `spark` † | Spark | bolt → target | 1 |
| `strike` † ‡ | Strike | bolt → target | 1 — **the most-cast spell in the game and it has no FX** |
| `quick_shot` † | Quick Shot | bolt → any | 1 |
| `hex` † | Hex | bolt → enemy | 1 + mark |
| ~~`lightning`~~ | **DEAD TAG — remove** | | |

### BLIGHT — purple drift, magenta core, stain aftermath
| id | name | delivery | beats |
|---|---|---|---|
| `dark_pact` | Dark Pact | at friendly | 1 + toll |
| `mass_grave` ‡ | Mass Grave | sweep, enemy line | **N staggered** |
| `apocalypse` ‡ | Apocalypse | wave from midline, ALL CREATURES | **N from centre outward** |
| `curse` | Curse | at the card | 1 |
| `unholy_bargain` ‡ | The Black Contract | at caster | 1 + **the bill comes due** (2nd beat at end of turn) |
| `blood_tithe` | Blood Tithe | bolt → face | 1 |
| `grave_robbery` | Grave Robbery | from the pile | 1 |
| `offering` | Offering | at friendly | 1 + sacrifice ash |
| `lay_on_hands` | Unclean Blessing | rise, YOUR ARMY | N staggered |
| `grave_pact` | Last Rites | at any | 1 |
| `plague_bell` † ‡ | Plague Bell | **ring outward, ALL CREATURES** | N + **lingering pall** |
| `venom_tip` † | Venom Tip | at friendly | 1 + venom aftermath |
| `salted_ground` † ‡ | Salted Ground | bar down a lane | N + **persistent salted lane** |
| `wolf_pits` † ‡ | Wolf-Pits | bar down a lane | **hidden until sprung** |
| `reanimate` † | Reanimate | rise from the pile | 1 |
| `muster_fallen` † ‡ | Muster the Fallen | rise, YOUR DEAD | **N staggered** |
| `grave_debt` † | Grave-Debt (curse) | draw sting | 1 |
| `war_debt` † | War-Debt (curse) | draw sting | 1 |
| `wound` † | Wound (curse) | draw sting | 1 |
| ~~`bloodletting`~~ | **DEAD TAG — remove** | | |

### BLESSING — golden rise, soft warm flash
| id | name | delivery | beats |
|---|---|---|---|
| `patch_up` | Field Surgery | at friendly | 1 |
| `mending_light` | Censer Light | rise, YOUR DEAD | N staggered |
| `battle_hymn` | Wildfire | sweep, ALL ENEMIES | **N staggered** |
| `war_cry` | War Cry | rise, YOUR ARMY | **N staggered** |
| `shield_wall` | Testudo | rise, YOUR FRONT LINE | **N staggered** |
| `kings_command` ‡ | King's Command | rise, YOUR ARMY | **N + a banner beat** (it's a rare) |
| `hoarfrost` † ‡ | Hoarfrost | at friendly | 1 + **frost aftermath** |
| `frost_bolt` † | Frost Bolt | bolt → enemy | 1 + frost |
| ~~`second_wind`~~ | **DEAD TAG — remove** | | |

### EARTH — brown dust, Y-shake, debris
| id | name | delivery | beats |
|---|---|---|---|
| `earthquake` ‡ | Earthquake | **both front lines shake back** | N both sides |
| `shove` | Shove | push + crash | 1 + crash |
| `cataclysm` | Cataclysm | at friendly | 1 |
| `overwhelming_force` ‡ | Rout | sweep, ALL ENEMIES | **N staggered** |
| `ballista_bolt` | Ballista Bolt | bolt → enemy | 1 + crash |
| `scatter_line` ‡ | Scatter the Line | sweep + push | **N + crash each** |
| `close_ranks` | Close Ranks | sweep, ALL ENEMIES | N |
| `gallows_writ` † ‡ | The Gallows Writ | bar down a lane | N (it's a rare) |
| `flanking_order` † | Flanking Order | bar down a friendly lane | N |
| ~~`reposition`~~ ~~`barricade`~~ | **DEAD TAGS — remove** | | |

### MIND — pale cool sweep, target outline pulse
| id | name | delivery | beats |
|---|---|---|---|
| `concentrate` | Immolate | at any | 1 |
| `adrenaline` | Countermarch | at friendly | 1 |
| `inspire` | Turncoat | **enemy → yours** | 1 + side-flip tint |
| `gambit` | Gambit | at caster | 1 |
| `echo_spell` ‡ | Echo | **replays the last spell** — should replay its FX too | 1 + the echoed spell's own beats |
| `banish` | Banish | at enemy | 1 + removal |
| `soul_swap` ‡ | Soul Swap | **two bolts, swap** | 2 |
| `provision` | Provision | at the pile | 1 |
| `turbo` | Frenzy | at friendly | 1 |
| `recycle` | Salvage | at the pile | 1 |
| `ambush` ‡ | Ambush | sweep, ALL ENEMIES | **N staggered** |
| `war_chant` | War Chant | at caster | 1 |
| `ricochet` ‡ | Crossfire | **arc OVER the front line**, ENEMY BACK ROW | N + hops |
| `reckless_charge` | Penance | at any | 1 |
| `crossed_orders` † ‡ | Crossed Orders | **two bolts** (two_enemies) | **2 sequential** |
| `mentioned_dispatches` † ‡ | Mentioned in Dispatches | **friendly THEN enemy** | **2 sequential** |
| `informer` † | The Informer | at caster | 1 |
| `long_roll` † | The Long Roll | at your line | N |
| `lost_tome` † | Lost Tome | at the pile | 1 |
| `war_council` † | War Council | at caster | 1 |
| `charge_spell` † | Charge! | at friendly | 1 |
| `smite_spell` † ‡ | Rain of Blows | at friendly | **N repeated blows** |
| `pillage` † | Pillage | at enemy | 1 + coin |
| `coin` † | The Coin | at caster | 1 + coin |
| `craven` † | Cowardice (curse) | at the card | 1 |
| `deserters_mark` † | Deserter's Mark (curse) | draw sting | 1 |
| ~~`scrap`~~ | **DEAD TAG — remove** | | |

---

## 5. Order of work

**S1 — Kill the lies — ✅ DONE 2026-07-17.** All 6 dead tags deleted; all 33
untagged spells tagged. **78/78 now carry a family**, and
`_probe_spell_fx_audit.gd` is a GATE: it fails (exit 1) on an untagged spell or
a dead tag. Both invariants were **negative-tested** — a canary dead id and a
dropped real tag each made it fail, because a gate that can't fail is theatre.
Add it to the regression set.

Post-S1 distribution: **mind 24 · blight 22 · fire 10 · earth 9 · shock 7 ·
blessing 6**. Two notes on the assignment as built, which differ from §4 above:
- **All curses → blight** (`craven`, `deserters_mark`, `grave_debt`, `war_debt`,
  `wound`), matching `curse` itself. The branded 6-card pack should read as one
  thing; §4 had scattered them into mind.
- **Frost → shock, provisionally** (`frost_bolt`, `hoarfrost`). §4 filed them
  under blessing, which is wrong — blessing is *golden*, and frost is not a
  blessing. A white-blue bolt reads as cold well enough for now, but **FROST
  wants its own family**; a 7th means a 7th `_vfx_*`, which is S4 work, not S1.

The lopsidedness is real and worth reading as design signal: **mind + blight are
46 of 78 spells.** Those two families are carrying half the pool, so they're
where the sequence work (S2/S3) will show up most — and where "every spell in
this family looks the same" will bite first.

**S2 — The sequence funnel — ✅ DONE 2026-07-17.** `_play_spell_cast_vfx` is now
`cast cue → impact(×N, staggered)`. `_spell_fx_impact_points(card_data, target)`
derives the target list from the spell's own `scope`/`targeting`;
`_spell_fx_impact(pos, family, type, node)` is the per-target unit and is
*exactly* what the whole spell used to be — so nothing looks worse on day one,
and **every multi-target spell now lands on every body instead of one dead
point.** Verify: `tools/_probe_spell_sequence.gd` (11 checks).

Decisions worth knowing:
- **Returns POSITIONS, not nodes.** The FX fires *before* resolution, so every
  body is still alive at derivation time — but may be dead when a staggered
  impact lands. A position can't go invalid, and an impact landing where the
  victim *was* is exactly right.
- **`ALL CREATURES` radiates from the midline; everything else sweeps
  left-to-right.** A board-wide spell shouldn't read as a line-sweep.
- **Impacts are scheduled, not awaited** — resolution must never wait on
  presentation.
- Empty board yields nothing: no phantom puff (probed).

**S3 — Staggered impacts + rising pitch — ✅ DONE with S2** (they're the same
edit: you can't stagger what you don't have a list of). Stagger
`SPELL_IMPACT_STAGGER` 0.06, shrinking as the target count grows so a sweep
stays inside `SPELL_SWEEP_MAX` 0.40 and can't outrun the resolution behind it.
Each successive impact sounds a step higher (`SPELL_PITCH_STEP` 0.05, capped
0.26) at −6 dB under the cast cue — the clash-phrase mechanism, applied to
spells. A 4-body Inferno now *builds*.

**S4 — Delivery — ✅ DONE 2026-07-17 (bolt shipped; lob/bar/arc still open).**
Spells now **travel**. `_spell_fx_deliver(to, family)` flies a bolt from
`_spell_caster_origin()` (the hand — that's where the writ was; the card node is
already freed by FX time, so a fixed origin is the honest answer) to each
target, and the impact lands `SPELL_TRAVEL` 0.09 later. That gap IS the feature:
zero restores the old "resolves where it lands" feel.

- **Reused `_play_attack_tracer` rather than inventing a projectile** — it's the
  board's established "a thing travelled from here to there" language, it bows,
  and it already degrades to a streak under Reduce Motion. It grew one additive
  optional param, `col_override`, so each bolt flies in its **family's** colour
  instead of the side default; every historical call site omits it and is
  unchanged.
- **When a bolt is honest (`_spell_fx_wants_bolt`, probed).** A bolt is *aimed*:
  single targets and sweeps ≤4 get one. **`ALL CREATURES` never does** — nothing
  is aimed at anyone in an Apocalypse, the wave *is* the delivery. Past 4
  targets bolts stop reading as delivery and start reading as spaghetti.
- Each body's throw→land pair stays intact across a sweep (bolt at `i*step`,
  impact at `i*step + travel`).
- Verified in `_shot_spell_fx`: Inferno throws orange bolts to each body with
  the first already impacting and the third not yet thrown; Frost Bolt is caught
  **in flight** in cold blue. Still open: lob (Petard), bar-down-a-lane (Gallows
  Writ, Salted Ground), arc-over-the-front (Crossfire).

**S5 — Aftermath — ✅ DONE 2026-07-17 (4 of 6; 2 were already covered).**
First move was the recurring lesson (check the display path): **Mark of Ash
already persists visibly** — its Doom brand rides the live doom badge +
counter — and **Hoarfrost's freeze** already sits on the struck card's status
rail. Neither needed anything. Plague Bell resolves instantly (the repeat-loop
is one cast); nothing persists mechanically, so nothing was built — a
"lingering pall" would be decoration divorced from state.

What WAS missing, and is now built (`scripts/ui/painters/LaneAftermath.gd` +
`Combat._refresh_lane_aftermath()`, refreshed at every state-change site):
- **Salted Ground** — bone-salt stipple strewn over the blocked enemy column
  (salt is WHITE — the blight family colours the cast, not the ground), plus
  a quartermaster's tag at the column's foot carrying one bone pip per round
  left.
- **The Gallows Writ** (adopted into S5 — same persistence gap) — blood-ink
  wash + hand-torn border down the condemned column, noose-on-a-tag at its
  foot.
- **Wolf-Pits** — one covered pit per waiting charge, just in front of the
  enemy line: black mouth, FRESH-CUT pale branch lattice, stake tip. Solo-only
  (matches the spring gate).
- **Slow Match** — the writ IS a slow match: a burning cord creeps across the
  hand card's top margin, one glowing knot per banked point (`Card2D.
  set_fuse_glow`, called from the `_start_round` charge site). The exact
  number stays with the targeting hover (card-honesty rule).

**Three shot-verified placement lessons** (the code was "right" every time —
only the pictures caught these):
1. The top of the enemy back row is COVERED by the encounter banner — nothing
   informational may live there.
2. The clash rule + furrow are painted by LATE siblings — anything an earlier
   layer draws at their height is painted over. Hence TWO instances of the one
   painter: ground washes under the rows, tags/pits on a marks layer added
   after the beam (geometry keeps it out of every card footprint).
3. Earth-tone pits on a wood table are camouflage (the ink-spatter lesson
   again); a glyph at the seam needs its own dark canvas — the tag IS the ★3
   lesson inverted: when there's no material to read at drawn size, ADD the
   material.

Verify: `tools/_shot_lane_aftermath.tscn` (full frame + 2× board/hand crops —
crops are PROPORTIONAL, the OS hands the window 1920×1080 against the asked
1600×900).

**S6 — Signatures + the remaining deliveries — ✅ DONE 2026-07-17 (18 ids).**
`SPELL_SIGNATURES` (Combat.gd, next to SPELL_FAMILIES) is the allow-list;
`_spell_fx_signature` is the dispatch, called from `_play_spell_cast_vfx`
right after the cast cue. Two contract classes:
- **OWNERS** (return true — the grammar is skipped for their cast): Strike,
  The Petard + Breach Bomb (lob), Crossfire, The Gallows Writ, Salted Ground,
  Flanking Order, Wolf-Pits, Crossed Orders, Mentioned in Dispatches,
  Soul Swap, Rain of Blows, The Doubled Hour, Echo.
- **ADD-ONS** (return false — the sweep/bolt machinery still runs on top):
  Inferno, Apocalypse, Earthquake, King's Command.

What each got (all shot-verified except where noted):
- **Strike** — STEEL, not weather: bolt, then two crossed blade-streaks +
  spark spray + hard flash (`_spell_fx_blade_cross`). The shock family's
  lightning stays in the sky.
- **The Petard / Breach Bomb** — the LOB (`_spell_fx_lob`, `SPELL_LOB`,
  `SPELL_LOB_TRAVEL 0.34`): a lit shell arcs from the hand and falls onto the
  target; blast = family impact + shockwave ring + shake + a DEEPENED boom
  (pitch 0.70). **`_resolve_spell` holds resolution for the flight**
  (`_spell_fx_lob_active` gate: windowed + motion on only) so the damage
  numbers pop WITH the blast — the one place resolution waits on delivery.
- **Crossfire** — every shot comes from BOTH wings at once, converging on
  each back-row body, staggered with the climbing phrase. Plus the S6 bug
  fix: `ENEMY BACK ROW` used to share the ALL ENEMIES branch, so Crossfire
  showed impacts on front-row bodies it never touches (probed now).
- **Lane bars** (`_spell_fx_lane_bar`) — Salted Ground: bone-white wash +
  falling salt grains (salt is WHITE, the family purple stays on the cast
  puff); Gallows Writ: blood-crimson wash + falling stroke + a mark on every
  body standing in the column (earth-brown would camouflage on the wood).
  The wash is informational (WHICH lane) and plays under Reduce Motion; the
  stroke is decoration and gates.
- **Wolf-Pits** — two spadefuls of earth fly up from the pit line, one per
  pit (not shot-verified; same burst primitive as everything else).
- **Crossed Orders / Soul Swap** — twin bolts CROSS (the tracer bows, so
  A→B + B→A make a lens). Soul Swap's lens runs between the card's own two
  stat seals — the swap read at the exact spots the numbers live.
- **Mentioned in Dispatches** — the order arrives (bolt hand→soldier + gilt
  pulse); the strike itself already animates via `_ordered_strike` — adding
  more would double the blow.
- **Rain of Blows** — one-TWO rhythm on the target, second beat bigger and a
  step higher (`_spell_fx_double_beat`).
- **The Doubled Hour** — the bell strikes TWICE: two board-wide rings a beat
  apart (second at pitch 1.18), cold wash, pale mark per soldier. OWNS the
  cast because the generic shock family would drop lightning on your own
  line, which reads as damage.
- **Echo** — pre-beat only (two fading rings at the hand); **the copied
  spell then replays its OWN full sequence** — the inner `_resolve_spell`
  fires `_play_spell_cast_vfx` again with the echoed card, signatures
  included. (The replay was already free by construction — the display-path
  lesson again; the plumbing of lane+primary through the call made it exact.)
- **Inferno** (add-on) — `_spell_fx_ground_fire`: a fire WALL rolls along the
  ground under the enemy line with the sweep, then one last beat carries to
  the enemy face (the card burns face too; the body sweep can't show that).
- **Apocalypse** (add-on) — the sky goes OUT: `_spell_fx_grade_dip` rides the
  ★8 u_sat grade (dip 0.35, hold, restore to values captured before the dip),
  purple flash, then the radiate crosses a drained world. The shot is the
  money frame of the pass.
- **Earthquake** (add-on) — `_spell_fx_fissure`: a jagged crack (dark core on
  a broad pale under-glow — the camouflage lesson) tears across the midline,
  dust bursts along it, heaviest non-verdict shake (14). CLAMPED to the war
  table's width — full-viewport rode over the INCOMING/forecast chips
  (shot-caught, the only placement defect of the pass).
- **King's Command** (add-on) — a gilt standard + trailing echo bar sweep
  across your army ahead of the grammar's per-body rises (the echo bar exists
  because a lone thin bar reads as a UI artifact in a still).

Wiring: `_play_spell_cast_vfx` grew optional `target_lane`/`primary` params
(defaults keep every CombatNet mirror + harness call site unchanged), fed
from `_resolve_spell` — which is also what makes Echo's replay exact.
Net note: mirrors call with what they have; a foe's Petard lob plays but
their damage numbers may land a beat early (mirror timing is CombatNet's own
— accepted cosmetic).

Probes: `_probe_spell_sequence` grew to 22 checks — ENEMY BACK ROW derivation
(3) + the S1-style liveness gates: every SPELL_SIGNATURES id is a live spell
in CARD_POOL, every SPELL_LOB id is a signature, every signature is
family-tagged. Shots: `_shot_spell_fx.tscn` grew 9 signature frames
(`_shot_sig_*.png`).

**Verify (all BUILT):**
- `tools/_probe_spell_fx_audit.gd` — the coverage GATE. Fails on an untagged
  spell or a dead tag; both invariants negative-tested.
- `tools/_probe_spell_sequence.gd` — 16 checks on the derivation and the bolt
  rule (counts, sweep ordering, radiate ordering, target-overrides-scope, empty
  board, spaghetti guard, caster origin on-screen).
- `tools/_shot_spell_fx.tscn` — boots a real fight and photographs a sweep
  mid-flight, a radiate, and a single bolt in flight.

Per the cool pitch: **the shot is the only thing that has ever caught a defect
in this layer** — parse checks were green through every one of them.

---

## 6. Status (2026-07-17)

**S1 ✅ · S2 ✅ · S3 ✅ · S4 ✅ (bolt + lob + crossfire) · S5 ✅ aftermath ·
S6 ✅ signatures (18 ids). The plan is COMPLETE.**

Muster the Fallen's rise landed later the same day (the 19th signature,
RESOLVER-owned because only the resolver knows the seats: the discard pile
takes a hit, then per shade a pale wisp flies pile→slot and the body stands
as it arrives, staggered 0.12; solo+windowed+motion only, and the generic
puff still carries the cast everywhere else).

**FROST became the 7th family the same day** — S1 filed cold under shock as
a stand-in, but a lightning bolt for a frost spell is a material lie.
`_vfx_frost` = crystal shatter (bright shards fly out and DROP) + big soft
flakes that hang and drift + a delayed second ring (rime spreading — cold
creeps, it doesn't strike); tracer colour icier/greener (0.58, 0.90, 0.94)
so the bolt never reads as another lightning spell. `frost_bolt` +
`hoarfrost` retagged; shock back to its honest 5. The audit gate's hardcoded
family list CAUGHT the new family (by design — that's the reminder that a
family needs its `_vfx_*`, a colour, and a ring-oval decision); "frost" is
acknowledged there now.

Still open beyond the plan: a real arc-over delivery if a future spell wants
a mortar volley distinct from the lob.

What a spell does now, versus that morning:

| | before | now |
|---|---|---|
| coverage | 45/78 tagged, 6 dead tags | **78/78, gated** |
| a 4-body sweep | ONE puff at a coordinate where nothing stands | **one impact per body, swept L→R** |
| a board-wide spell | one puff at screen centre | **radiates from the midline** |
| audio | one flat cue | **cast + a phrase that climbs per body** |
| travel | none — resolved where it landed | **a bolt in the family's colour, 0.09 ahead of its impact** |

| the 18 marquee spells | same event as everything else | **bespoke: lobs, lane bars, crossfire, blade steel, the sky going out, the table cracking, the bell striking twice** |

Nothing left in this plan — see the open candidates under Status above.
