# Making the Animations Cool — a pitch (2026-07-17)

Third pass over the animation layer, and a different question from the first
two. [`ANIMATION_AUDIT_20260716.md`](ANIMATION_AUDIT_20260716.md) §1–§5 asked
*is the system sound?* (yes, after R1–R6). §6 asked *does every beat have
motion?* (yes, after C1/C2/C5-pitch, with three items still open). This asks
the thing neither answered:

> **Why doesn't it look expensive?**

Not "is anything missing" — the beats are saturated. The honest answer is that
the motion is **generic where the art is specific.** Everything on screen is
parchment, wax, ink and gilt; almost every effect is a glowing orange particle
that could be from any fantasy game. That gap — not a missing tween — is the
whole ceiling.

---

## 1. The thesis: obey the material

This game's identity is that it's a **document**. Cards are illuminated writs
on aged parchment with pressed wax seals. The map is a chart pinned to a war
table. The transition is an ink wipe. That's Inscryption-grade diegesis and
it's *already built* — in the painters, not in the motion.

The build already knows this in a few places, and those are the best beats in
the game:

| Already material-true | Why it lands |
|---|---|
| The **wax press** landing (`play_wax_press`) | a card doesn't "appear," it's STAMPED onto the board |
| Forge sparks **fall**, combat embers **rise** | different materials, deliberate contrast (audit §2) |
| The **ink-wipe** scene transition | the page turns; no crossfade |
| The **drag ember trail** | the writ smoulders as you carry it |
| The **war-table** map, sheet pinned by tacks | the chart is an object, not a UI |

And the places it doesn't — every one of them the *default* choice, not a
designed one:

| Generic today | What the material says it should be |
|---|---|
| Death = orange burst + fade | the writ **burns** — the game is called *Burning Meadow* |
| Hit = red `modulate` tint | ink **spatters and stains** the page |
| Low HP = the numeral turns red | the **wax seal cracks** |
| Rare in hand = looks like a common | **gilt catches the light** as the card tilts |
| Reveal = texture swap | the writ **turns over** |

**The pitch: every effect must be answerable to "what is this thing made of?"**
That single rule is what separates Balatro/Inscryption from asset-flip juice,
and it costs nothing extra — a dissolve is not more expensive than a fade, it's
just *chosen*.

> **The thesis has a limit, learned by breaking it twice (2026-07-17).** An
> effect only lands where its material is **VISIBLE AT THE SIZE IT'S DRAWN**.
> This is the single best predictor of which items on this page shipped:
>
> | | material visible? | outcome |
> |---|---|---|
> | ★1 burn | yes — the sheet's whole silhouette IS the paper | ✅ |
> | ★2 gilt | yes — the hand card shows frame, leaf, gem | ✅ |
> | ★4 flash | n/a — the whole face flashes, no material needed | ✅ |
> | ★3 crack | **no** — 38px seal − 18px numeral = ~8px of wax | ❌ |
> | ★4 spatter | **no** — a token is full-bleed ART; the paper is on hand cards, which never take damage | ❌ |
>
> Both failures were invisible to parse checks and code review, and both were
> **predictable from the geometry and the art** before a line was written. Ask
> "where is the paper, and how many pixels of it are there?" first.

---

## 2. The unlock — bake, then effect

The audit's §6.2 #4 scoping note is the gate on all of this: `modulate` is
hierarchical, `ShaderMaterial` is not, so shading a live card means threading
`use_parent_material` through two layout builders across ~4.6k lines. That's
why the flash is still a tint.

**Verified today: we don't have to.** The bake pipeline already exists and
battlefield tokens already ride it —

- `CardTextureCache.get_battlefield_texture(card_data)` returns the token's
  whole body as ONE texture; `_build_compact_layout` mounts it and lays the
  live stat seals over it.
- `compact_static_bake` is an existing "the entire token is one baked image"
  mode, baked through a SubViewport (`_bake_battlefield`).
- Hand cards do the same via `live_baked_mode` + `_build_baked_overlay_layout`
  (one `TextureRect` + live numerals).

So for any **whole-card** effect — dissolve, flip, foil sweep — the move is:
**snapshot the card to its baked texture, run the shader on that one
`TextureRect`, and let the live overlay ride or fade.** One CanvasItem, one
material, no hierarchy problem, no propagation surgery. For **death** it's
free of consequences by definition: the card is leaving, so nothing needs to
stay interactive.

This turns C4 from "invasive refactor" into "a shader on an existing
TextureRect." It is the difference between this plan being a month and a week.

---

## 3. The slate

Ordered by cool-per-cost. Each is independent.

### ★1 — The writ burns (death dissolve) — ✅ BUILT 2026-07-17
**Shipped.** `Motion.BURN_CODE` / `burn_material()` / `burn_away()` +
`Card2D._play_burn_death()`. The §2 unlock held: the burn is one shader on the
token's baked face, no propagation surgery. Player writs burn gilt, the foe's
oxblood (the side language the log rims already speak). The ink (numerals,
seals, badges) fades ahead of the frontier — siblings of the face, so they
can't ride the shader. Heat lifts the sheet ~14px; no spin, no shrink — paper
doesn't recoil. `_die` falls back to the historical flourish when there's no
baked face (hand cards, uncached tokens, headless), so a death ALWAYS resolves.
Verify: `tools/_shot_card_burn.tscn` (stages + a real `_die` caught mid-burn).

**Three things the shots caught that the code review would not have:**
1. **The card burned away to a black slab.** Card2D is a `PanelContainer` and
   paints its own panel *behind* the face; `discard` revealed the backing board,
   not the battlefield. `_play_burn_death` now strips the panel to a
   `StyleBoxEmpty`. A parse check is blind to this — only the picture showed it.
2. **The tween's last third was dead air.** The field's real range is ~0.1–0.9
   (the noise term averages ~0.5, it doesn't span 0–1), so sweeping `t` to 1.30
   consumed the sheet by `burn ≈ 0.72`. Recalibrated to `burn * 1.10 - 0.12`.
3. **A bake landing mid-death would strand a corpse.** The burn tween lives on
   the face, and `_on_battlefield_texture_ready` frees `_compact_root` — so a
   late bake took the `queue_free` with it. Guarded with a `_dead` bail plus a
   timer that frees regardless of the face surviving.

---

#### (original pitch, for reference)
**The signature.** Replace burst-and-fade with a noise dissolve that eats the
parchment from the wound side, carrying a **glowing ember edge** — paper
catching, not a sprite fading. The existing ash burst stays and finally reads
as *what the card became*. Player and enemy deaths can differ by ember colour
(gilt vs oxblood).
- **How**: dissolve shader (noise threshold + edge glow) on the baked token
  texture; drive `threshold` 0→1 with a tween on the existing `_die` beat;
  bias the noise UV from the killing blow's direction.
- **Why it's the best one**: it's the most-repeated dramatic moment in the
  game, it's *the game's title*, and today it's the most generic thing on
  screen.
- Ref: layered noise at 2–3 scales reads organic (Godot shader practice).

### ★2 — Gilt catches the light — ✅ BUILT 2026-07-17
`Motion.GILT_CODE` / `gilt_material()` + `Card2D._apply_gilt_foil()` /
`_sweep_gilt()`. A rare's leaf now catches a raking light as the card tilts:
rare = full strength, uncommon = half, **commons no-op** (the shine must stay
information — if everything glinted a rare would look like a common again,
which is the defect it exists to fix; same reasoning as `rarity_reveal`).
Driven off C1's lean driver — the one place per frame that already knows how
the card is moving — so the foil costs **no `_process` of its own**, and gold
leaf correctly does NOT shimmer on its own: it catches light only when you move
the card. Verify: `tools/_shot_card_gilt.tscn`.

**Two things the shots caught:**
1. **The mask washed the parchment.** `smoothstep(0.10, 0.32, warm)` scored the
   page ~0.5 (parchment is warm too, `r-b ≈ 0.21`) so the whole rules box went
   near-white and a rare read merely *bright*, not gilded. Leaf is far warmer
   (~0.57) but **darker** than the page (lum ~0.70 vs ~0.85) — so the
   discriminator is a **band-pass**: warmth floor + brightness **ceiling**.
   Gold is never near-white.
2. **The harness measured the fallback.** `_build_baked_overlay_layout` only
   runs on a `CardTextureCache.has()` HIT; unbaked cards fall to the live
   `chart_proto` renderer, which is a TREE of painters and can't be shaded at
   all. The first run reported 0/3 until the harness baked first. **Consequence
   for the game: the foil rides the baked path only** — which is the normal
   path for hand cards (that's what `live_baked_mode` + the ScenePreload prewarm
   are for), but a bake miss means no foil, silently.

### ★3 — The wax seal cracks — ❌ TRIED AND REVERTED 2026-07-17
Built it (a `SealCrack` painter over the baked seal, two rungs off
`current_hp / card_data.hp`, driven from `update_stat_display`), shot it at 3×,
and **it doesn't work at this size.** Reverted; the code is gone.

**The geometry kills it, and it's checkable up front — I should have done the
arithmetic before the painter.** A battlefield seal is **38px** and carries an
**18px numeral** dead centre, which leaves roughly an **8px annulus of visible
wax**. A fissure long enough to read as a crack spends most of its length
*behind the digit*; confined to the annulus it's an 8px stub. At 3× zoom the
"split" rung read as a single stray hook, and the "hairline" rung was invisible.
It looks like a render smudge, not cracked wax.

This is the same rule the project already wrote down: painted icons mush below
~20px (why `KeywordEffects.INLINE_KEYWORD_STAMPS` is off). **Anything drawn
inside a battlefield seal is subject to it.**

Worth reopening ONLY if the crack stops being an overlay: bake it into the
seal at damaged state (`CardTextureCache` would need an HP-rung cache key —
plausible, but no longer "cheap: a painter change"), or find the read somewhere
with room. The idea is still good; the canvas is too small.

### ★4 — Ink shock (the hit) — ✅ FLASH BUILT 2026-07-17 · spatter still open
**Flash shipped.** `Motion.FLASH_CODE` / `flash_material()` +
`Card2D._flash_face_hit()`. The struck sheet now mixes toward hot white on the
baked face — a real flash. The old `modulate` tint *could not* do this:
modulate multiplies, so its only route to "red" was darkening green and blue
(`base.g * 0.5, base.b * 0.45`), which is why a struck card went muddy instead
of hot. The live numerals deliberately don't flash: paper catches the light,
writing doesn't. Falls back to the historical tint with no baked face.
Death wins the material — `_play_burn_death` kills the flash tween before
`burn_away` re-mounts the face.
- Peak is **0.75, not 0.85**: at 0.85 a bright card went ghost-white and read
  as a render error rather than a blow (caught in `_shot_burn_seals_zoom`).
- **The ink spatter: ❌ TRIED AND REVERTED 2026-07-17.** Built it (an
  `InkSpatter` painter over the baked face, seeded clusters accumulating to a
  cap of 4, hung under the numerals), and it **does not read**. Tokens with 1,
  3 and 4 stains were indistinguishable. Raising alpha 0.34 → 0.62 and adding
  a wet rim barely moved it.

  **The cause is NOT size** (the token face is 200×150 — the ★3 arithmetic
  passes fine). **It's material: a battlefield token is full-bleed ART, not
  paper.** There is no visible parchment on it to stain — the paper is on hand
  cards, which never take damage. Against a dense, high-contrast painting, a
  small dark blot is camouflage. Making it read means going garish, at which
  point it stops being blood soaking into a page and becomes paint splattered
  on the art — fighting the painting the player uses to recognise the card.

### ★5 — The writ turns (flip) — ◐ HALF BUILT 2026-07-17
`Motion.flip_out` / `flip_in` exist (X-only squeeze — a turning card
foreshortens, it doesn't shrink; BACK-out on the opening half). **`flip_out` is
wired: the sealed-orders reveal's face-down ghosts now turn edge-on** instead of
being `queue_free`d out of existence, which is what "reveals are texture swaps"
meant in practice. Opt-in via `_sealed_clear_pending_local(flip)` — every other
caller (rejection, teardown, closed orders phase) is an error/bookkeeping path
where a flourish would dress up a failure as a reveal.

**The card's half is deliberately NOT wired, and this is the interesting part.**
`_net_spawn_creature` → `_play_landing_pop` → `play_wax_press` already owns the
seated card's `scale` outright (and defers a frame for the slot's
CenterContainer, so it would clobber a flip regardless). Wiring `flip_in` there
would be **two writers on one property** — the exact rule this codebase is built
on. And the press is the *better* beat: "an order is STAMPED onto the board" is
the house's own material language; a flip is generic. So the reveal's turn-over
lives in the ghost.

To finish it properly, the landing-pop-vs-flip ownership has to be settled
first — probably a `_play_landing_pop` variant that IS the flip's second half
(open, then press), not a second animation stacked on it. That's a real design
call about what seating a card looks like, not a wiring job.
- Verify: `tools/_probe_sealed.gd` ALL PASS, `_probe_skirmish_combat` ALL PASS,
  `_probe_relay` ALL PASS.

### ★6 — The table takes the blow — ✅ BUILT 2026-07-17 (rotation still open)
**This turned out to be a defect, not a taste question.** `Combat.screen_shake`
shook **`_hud_layer` alone** — so every kill jittered the floating numbers and
the banners while the battlefield, the cards, and *the thing actually being
hit* sat perfectly still. That is why the shake read as weak: it never moved
the struck object. (`_board_container`'s own comment still read "Board
container (no effects)".)

Now `screen_shake` drives **`_board_container` AND `_hud_layer` off one trauma
reservoir, in lockstep** (`GameTheme.set_shake_targets`). Both must move by the
same offset: the impact bursts, rings and damage numbers live on `_hud_layer`
but are spawned at *board* positions, so shaking only the board would tear them
off the cards they belong to. The hand deliberately does **not** shake — it's
in your hands, not on the table.

- Verify: `tools/_probe_anim_clock.gd` grew 7 checks — lockstep offsets, the
  `position`-vs-`offset` split (Control vs CanvasLayer), idempotence on the
  same set, exact restore of **both** rest values, co-target clearing, and a
  freed co-target releasing safely.
- **Still open — rotation.** Now that the shake owns the board, a rotational
  component is finally *meaningful* (it would rock the table rather than shear
  the HUD against a still field). Left undone deliberately: it needs the
  pivot-on-centre treatment (`offset = pivot - pivot.rotated(r)`, since both
  a CanvasLayer and a Control rotate about their origin), and the two layers
  would have to agree on a pivot in different coordinate spaces. Worth doing;
  not a one-liner.
- Also still open: the lethal **push-in** (board scale +1–2%) — the closest
  thing a 2D canvas has to a camera punch. The board being a real shake target
  is the prerequisite, and it now is.

---

## 4. Order, and what depends on what

```
§2 unlock (bake-and-effect)  ─┬─→ ★1 burn      (the signature)
                              ├─→ ★2 gilt      (needs C1 tilt — already built)
                              └─→ ★4 ink shock
★3 wax cracks   — independent, no shader, cheapest real win
★5 flip         — independent
★6 table shake  — independent; needs the owner decision first
```

**Suggested**: prove the §2 unlock on ★1 (one shader, one TextureRect, biggest
payoff). If that lands, ★2 and ★4 are the same technique again and go fast.
★3 can happen any time and is the cheapest thing on this page.

**Status 2026-07-17 — the slate is worked through.**
★1 ✅ · ★2 ✅ · ★4 flash ✅ · ★6 ✅ (rotation + push-in open) · ★5 ◐ half
(ghost turns; the card's half is blocked on the wax-press owning `scale`) ·
★3 ❌ reverted (no wax visible at 38px) · ★4 spatter ❌ reverted (no paper
visible on a token).

**Score: 4 shipped, 1 half, 2 reverted — and the two reverts were the most
useful results on the page**, because they're what produced the visibility rule
in §1. Nothing here was found by reading code: every failure and every
miscalibration came out of a screenshot. **The §2 unlock is proven three
times**: every shipped effect is one shader on a baked TextureRect, exactly as
predicted, and none needed propagation surgery. The bake-then-shade dodge is
the real finding of this document.

**Three rules earned the hard way, for anything on this page:**
1. **Strip the panel.** Card2D is a `PanelContainer` painting its own panel
   behind the face — any shader that `discard`s or reveals will show a black
   slab without a `StyleBoxEmpty` override.
2. **Do the size arithmetic before the painter.** 38px seal − 18px numeral =
   ~8px of wax. ★3 died on that and nothing in a parse check or a code review
   would have said so — only a 3× shot did.
3. **Two different bakes, two different TextureRects.** Battlefield tokens use
   `CardTextureCache.get_battlefield_texture` → `_compact_face` (★1 burn, ★4
   flash). Hand cards use `get_texture` → `_baked_face` (★2 foil). Both only
   exist on a cache HIT; a miss silently falls back to the live `chart_proto`
   painter tree, which **cannot be shaded at all**. Any new card shader must
   say which bake it rides, and any harness must bake before it measures.

**Explicitly NOT here**: more particles, more screen shake, more rings. The
audit's §2 verdict stands — quantity was never the problem, and adding volume
to generic effects makes them *more* generic, not cooler.

---

## 5. Verification

Same as every pass: `_shot_anim_pass` / `_shot_setpieces` re-rendered and
eyeballed; a new `_shot_card_death.tscn` for ★1 catching the dissolve mid-burn
(the whole point is the frame *between* alive and gone). Shot harnesses must
force `reduce_motion = false` — this machine's saved settings have it ON.

Every item above is decorative by the reduce-motion contract EXCEPT ★3 (the
crack is information — it must have a static fallback, not be gated off).

---

## 5b. The SECOND slate (★7–★12) — added 2026-07-17 after ★1–★6

The first slate was scoped to **cards**, and the spell plan to **spells**. That
left the rest of the screen unexamined. These are the beats nobody has looked at
yet, ranked. ★7 is the standout and is nearly free.

### ★7 — The hero portrait takes the war — ✅ BUILT 2026-07-17
Shipped exactly as pitched, and the estimate held: **one existing shader, one
TextureRect, one uniform off an HP ratio.** `Combat._refresh_portrait_char`,
driven from `_update_hud` (the funnel every HP change already routes through —
so nothing can forget to char; the lesson from `update_stat_display`'s 144
hand-written call sites). Both panels scorch; healing recedes the char.
Verify: `tools/_shot_portrait_char.tscn` (full / half / low / dying).

**Two things worth keeping:**
1. **`consume = 0` — the shader grew a mode.** ★1 discards burnt pixels because
   a card is *leaving* and a hole is the point. A permanent HUD panel must
   **char in place**: burnt pixels go to soot and the surface stays. A hole in
   the HUD would read as a bug — the same instinct as ★1's black slab, caught
   before it shipped this time. `consume` defaults to 1.0, so ★1 is untouched.
2. **The curve had to be calibrated against shots, not theory.** The first cut
   (0 → 0.34) showed **nothing until ~10% HP** — the 30%-HP frame was
   indistinguishable from full, which is useless for a glanceable read. The
   burn field's real range puts the char band at the panel's very bottom edge.
   Because `consume = 0` makes a hole impossible, the range can be pushed far
   harder than a card's: now **0.20 (faintest singe at 66%) → 0.55 (deep soot
   at 0)**. Same class of miscalibration as ★1's dead-air burn curve — and
   again, only the picture showed it.

#### (original pitch)
**The best remaining idea in the game.** Both hero portraits are a single
`TextureRect` (verified: `Combat._resolve_player_portrait` → the `img` rect at
~L15730). Today they are **static paintings with a number under them** — the
hero never reacts to anything that happens. In every AAA card game the hero
portrait *is* the stakes; here it's wallpaper.

Material says: it's a **painted panel pinned to the war table**. So it should
**scorch and char as HP falls.**

- **How: reuse `Motion.BURN_CODE`, held.** The burn shader already takes a
  `burn` uniform 0→1. ★1 runs it to completion to consume a card. Hold it at
  0.12 at half HP, 0.30 at quarter HP, and the portrait's edges singe and char
  while the face survives — the ember frontier creeps inward as the hero dies.
  **One existing shader, one TextureRect, one uniform driven by an HP ratio.**
- **Why it's the standout**: material-true, *informational* (glanceable HP
  across the table, no numeral), and it costs almost nothing because the shader
  and the target both already exist and the §2 unlock already covers it.
- Passes the visibility rule by a mile: the portrait is ~200×280 of *painting*.
  Compare ★3, which died on 8px of wax.
- Reversible: healing lowers `burn` and the char recedes. **The foe's portrait
  chars too** — you can see how close the enemy is to breaking without reading
  their number.

### ★8 — The killing blow — ✅ BUILT 2026-07-17
Shipped, and cheaper than pitched: **the desat needed no new shader at all.**
The cinematic colour grade (`_grade_mat`, a whole-frame `hint_screen_texture`
pass) already carries a `u_sat` uniform — the moment is a tween on it. Fourth
consecutive confirmation of the recurring lesson: *check the display path
before building the effect* — the pitch assumed a desat shader had to be
written; the display layer already owned one.

`Combat._play_killing_blow_moment(won)`, fired from `_check_game_over` (both
branches) and both CombatNet verdict sites: instant music duck, `screen_shake
(10)`, colour drains to sat 0.22 in 0.24s. **Victory floods the colour back in
step with the VICTORY stamp landing** (recovery starts at +0.50, banner
strikes ~+0.63 — the world regains its colour AS the verdict hits the page,
shot-verified). Defeat recovers only to 0.55 so the DEFEAT ink reads
blood-red over a world that stays drained into the fade (the grade layer tones
the HUD too — full drain turned the verdict word grey).

The killer is **held at full extension** through the stop:
`Card2D.hold_lunge_apex(extra)` PAUSES the running lunge tweens and resumes
them after — one owner on `position`, time just stops for it (the codebase's
own rule, applied to time instead of a second writer). Two contract points:
- `_combat_tween_active()` treats a held lunge as live — a paused tween
  reports `is_running() == false` and the idle bob would otherwise reclaim
  `position.y` mid-hold and drag the frozen killer back to its rest bob.
- Strike sites (`_creature_hits_face`, `_creature_attacks_creature`) check
  `phase == GAME_OVER` after damage lands and swap the ordinary kill beat for
  `KILLING_BLOW_HOLD` (0.55, on the Motion clock — ~3× HITSTOP_BEAT,
  deliberately a different event class, not a longer copy).

Reduce Motion: the grade layer is never built under it, so the drain
self-gates; the hold gates explicitly; the duck + shake remain.
- Verify: `_probe_anim_clock` grew 8 ★8 checks (pause/resume/one-owner/
  bob-yield/no-op/RM/settle-home); `tools/_shot_killing_blow.tscn` shoots the
  staged defeat drain + the REAL `_debug_auto_win` path mid-drain and at the
  stamp.
- Still open from ★6: shake rotation, and the lethal push-in (board scale
  +1–2%) — the desat moment is the natural place to add the push-in later.

### ★9 — The General arrives — ✅ BUILT 2026-07-17
Reused ★8's moment grammar pointed at an entrance, in `_show_encounter_intro`
+ `_play_army_rollcall`:
- **The world holds its breath**: u_sat drains to 0.72 for the banner's
  length. Shot-calibrated — 0.60 + a brightness cut muted the banner NAME
  (the grade tones the HUD, the ★8 lesson re-confirmed); saturation-only and
  gentle, because the dim ColorRect already owns the darkness.
- **The name STAMPS**: non-quick intros fall IN oversized (1.42×, QUAD
  EASE_IN) and the table takes the hit at the land. Quick / Reduce Motion
  keep the gentle rise.
- **The army PRESENTS**: after the banner lifts (colour flooding back), each
  rank presses in sequence with a muffled thud, and the LORD (biggest body —
  kits lead with their namesake) seats last: down-press squash, flat dust
  ring + debris along the table, the heavy shake, the deep card_play thud.
  This REPLACED the old "entrance slam", which fired at placement time —
  before the banner was even up, a shake attached to nothing.
Verify: `tools/_shot_general_intro.tscn` (elite orc_warband, brackets stamp /
hold / roll-call, plus the ★10 peel + Muster's rise).

### ★10 — The deck is a stack of writs — ✅ BUILT 2026-07-17
A draw now takes a sheet OFF A STACK: the top leaf peels up-and-toward the
hand (the drawn card continues that motion) while the pile recoils under the
pull (`_play_deck_peel_vfx`, wired into `_draw_card`); discard landings and
the reshuffle punch the writ-stack Controls themselves, not just their count
badges (`_deck_pile_art` / `_discard_pile_art`). Bonus correctness: the
deal-in origin now derives from the LIVE pile (`_deck_pile_origin`) instead
of the historical hardcoded `(100, 311)`, so it can't drift from the chip.

### ★11 — The intent chip is a threat — ✅ BUILT (small) 2026-07-17
**The pitch was wrong and the fix shrank.** ~~The chip is static.~~ It already
carries a full escalating read: a three-tier colour ramp (amber → warm-red →
hot-red) **and** a swords→skull glyph swap at lethal
(`_refresh_incoming_damage_chip`). The information was never missing.

What *was* missing is a beat at the **crossing**. The chip changes state
silently, and the instant the threat becomes a death sentence is the one moment
the player has to notice it. Now `Motion.punch` fires on a real transition into
lethal (`was != "lethal" and was != ""` — the first paint doesn't punch; a chip
that punches while fading in is noise).

Correct by the reduce-motion contract: the colour and the skull are the
information and keep carrying it when gated; the punch is decorative emphasis
on top.

**Third time today the pitch overstated a gap** (after ★3's premise and ★4's
spatter, and finding #5 in the audit before them). The pattern is consistent:
**this codebase's information layer is in better shape than a read of the state
variables suggests — always check the display path before calling a beat
missing.**

### ★12 — The march — ✅ WAS ALREADY BUILT (found 2026-07-17)
**The sixth display-path confirmation, and the largest**: the entire item
exists and is wired — `MapPulseOverlay.march_along` walks the standard along
the road curve with footfall dust, a commit ripple, an arrival ring, and a
Reduce Motion snap, awaited by `MapView._on_node_pressed` before the scene
fade. It shipped with the war-table pass; only this doc was stale. Nothing
was changed.

### ★13 — The war ends (sweep the stale forecasts) — ✅ BUILT 2026-07-17
**Found in ★8's own verification shot, not by reading code** — the verdict
stamped down over STALE PROMISES: the INCOMING chip still shouting ✕4, the
wave chip promising "1 NEXT ROUND", enemy intent chevrons telegraphing swings
that will never come, per-slot "HP -N" danger sigils, and a lit CLASH button
under the ceremony. `_dim_war_furniture()` fades all of it at GAME_OVER
(chips + End Turn via `fade_exit`, threat flags via `set_threat_flagged`,
intent metas hidden, `_clear_lane_forecast()`), so the climax plays on a
settled stage. **SOLO-ONLY** — the net rematch reuses the scene in place and
an alpha-0 chip would come back invisible in game 2. Dead information may be
hidden under Reduce Motion by definition.

**Order:** ★7 (free, standout, informational) → ★8 (the climax) → ★11 (pure
information) → ★9 → ★10 → ★12.

---

## 5c. The hunt (2026-07-17, after ★8/S5/★13) — what's left, ranked

The combat screen's beat map is now saturated: death, hit, lethal crossing,
the climax, aftermath, portraits, shake. What remains, by cool-per-cost:

1. ~~**★9 The General arrives**~~ — ✅ BUILT 2026-07-17 (see §5b: breath +
   stamp + roll-call; the old placement-time slam retired into the lord's
   seat).
2. ~~**The lethal push-in**~~ — ✅ BUILT 2026-07-17: board scale 1.015 inside
   `_play_killing_blow_moment`; eases back with the victory flood, stays
   leaned in on solo defeat, and ALWAYS eases back in net (Bo3 reuses the
   scene — game 2 must not open zoomed).
3. ~~**S6 signatures**~~ — ✅ BUILT 2026-07-17, all 18 + Muster the Fallen's
   rise-from-the-pile (19th, resolver-owned: wisps from the discard pile,
   bodies standing as they arrive — see the spell plan's S6 section).
4. ~~**★10 the deck is a stack of writs**~~ — ✅ BUILT 2026-07-17 (§5b).
5. ~~**★12 the march**~~ — ✅ WAS ALREADY BUILT (see §5b — the sixth
   display-path confirmation; only this list was stale).
6. ✅ **Board state-change beats** (added + built 2026-07-17, found by
   hunting resolver `queue_free` calls): **Turncoat's desertion WALKS** —
   the old token itself arcs across the table still in enemy colours and
   dons your banner on arrival (body exists in the arrays immediately at
   alpha 0; the walk is presentation bridging the swap; Whisper-Widow's
   steal shares the path). **Banish TEARS its target out** — the real token
   spirals small into a contracting pale ring (`_play_banish_exit` +
   `_detach_token_for_fx`: state arrays already cleared, the node is a pure
   visual for its last 0.3s). **Grave Robbery / Reanimate show their pile**
   — the reshuffle streak discard→deck ahead of the draw; Muster's wisp
   pile→slot ahead of the revived body.
7. **The decision items** (not drop-ins, don't start them casually):
   C3 springs for hand reflow (165 tweens, one kill/restart bug already),
   ★5's second half (landing-pop-vs-flip ownership), ★6 shake rotation
   (pivot-on-centre across two coordinate spaces).

**Method note, carried from every pass this week: the only tool that has ever
found a real defect in this layer is a screenshot of the running game.** ★13
came out of ★8's verification frame. Budget the shot before the build.

---

## 6. Sources

[Balatro: Juicy Feedback](https://blakecrosley.com/guides/design/balatro) ·
[Balatro card movement/shaders in Unity](https://80.lv/articles/balatro-s-card-movements-shaders-recreated-in-unity) ·
[Saltmire FX (Godot 4 one-line sprite shaders — dissolve/hit-flash reference)](https://saltmire.itch.io/saltmire-fx/devlog/1577528/saltmire-fx-is-out-one-line-2d-sprite-shader-effects-for-godot-4) ·
[Godot dissolve + particle shader guide](https://dredyson.com/how-to-control-godot-gpu-particle-shader-custom-parameters-with-curved-particle-life-duration-a-complete-beginners-step-by-step-guide-to-instance_custom-uniforms-and-dissolve-effects-in-godot-4/) ·
[Juicee (Godot 4 game-feel lib)](https://github.com/Kelpekk/Juicee) ·
[Juice in Game Design](https://www.bloodmooninteractive.com/articles/juice.html)
