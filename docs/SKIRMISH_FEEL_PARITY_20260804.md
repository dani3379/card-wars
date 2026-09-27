# SKIRMISH FEEL PARITY — 2026-08-04

**Status: BUILT.** Gates: `tools/_probe_net_clash_beats.gd` (new — the host's beats AND
the whole reel a client would receive), `tools/_probe_net_client_replay.gd` (new — the
watcher's half actually executed), `tools/_probe_beat_spacing.tscn` (contract inverted),
`tools/_probe_net_clash.gd`, `tools/_probe_net_repos_client.gd` (un-poisoned),
`tools/_shot_net_clash.tscn` (eyes).

The two probes are deliberately separate. `_net_replay_fallen` and
`_net_replay_trigger_fx` are reachable ONLY from a real second peer, so short of a
two-process match they had never run once — and every way they break (a member that
moved, a wrong channel key, an anchor read after the despawn loop) is a runtime error
on somebody else's machine that a compile gate cannot see. `_probe_net_client_replay`
boots a CLIENT and hands it a hand-built reel plus a snapshot carrying both trigger
channels, so the watcher's paths are exercised on every run.

## The complaint

> "make the multiplayer game feel like the single player since a lot of the effects
> are just not there"

It was accurate, and the biggest single cause was not a missing effect but a missing
**structure**: the campaign clash had spent two passes (2026-07-28 legibility,
2026-07-29 attention budget) learning to resolve ONE COLUMN AT A TIME under a
spotlight, with named ranks, a dwell spent where the information is, a paced corpse
flush that says who fell, and a one-line ledger. Online Skirmish — the same
creatures, on the same board, through the same resolvers — did all of that on
adjacent frames as one undifferentiated burst, **on both machines**.

## What changed

### 1. The clash is the same clash (the big one)

`_net_run_clash` used to call `_resolve_column_attack` twice per column inline.
It now routes through **`Combat._clash_lane_pass`** — the campaign's serialized unit —
which gained a `side_filter` argument precisely so the one-directional net pass could
be the *same code* rather than a parallel copy. With it come, unchanged:

- the ClashLaneFocus spotlight (already worked host-side since 2026-07-29),
- `THE FRONT RANK` / `THE BACK RANK` / `THE FALLEN` captions,
- the significance dwell (MINOR fuses a chip-damage lane with its neighbour; NORMAL
  and KILL earn a real registration slot),
- `await _cleanup_dead_paced()` — corpses fall on beats, each naming itself,
- the 3+-fallen mass-grave punctuation,
- `_post_clash_ledger()`.

`_lane_dwell` / `_lane_dwell_minor` / `_cleanup_dead_paced` no longer bail on
`_is_net()`. **The reason the old bail did not survive scrutiny:** it read "the turn
machine's clocks are not ours to stretch", but nothing in the net layer is on a clock —
there is no turn timer anywhere in `NetMatch`, the host is authoritative, and the
client replays a shipped log. A longer clash costs a longer clash and nothing else.

`_round_beat` **keeps** its net bail, for a genuinely structural reason: `_start_round`
is called from CombatNet's plain `void` turn-machine entry points and must not become
a coroutine there. The two bails are no longer symmetric and the probe now says so.

### 2. The watcher gets the same clash, on its own clock

The client never runs a resolver, so the clash log is its only channel. Three entry
kinds were added:

| entry | meaning |
| --- | --- |
| `{fo: lane, fe: bool}` | put the spotlight on this column (`fo: -1` = take it off) |
| `{dw: kind}` | this column earned a MINOR / NORMAL / KILL slot |
| `{fal: true}` | the host's corpse flush runs here |

**The pacing crosses as a DECISION, never as seconds.** Each peer runs its own
`_focus_combat_lane` and `_run_lane_dwell`, so the Clash Pause dial and Animation
Speed pacing the clash are the *reader's* own settings. Shipping a float would have
quietly handed one player's reading speed to the other, which is the one thing that
dial exists to prevent.

`fe` is written from the host's board and INVERTED on replay — the log only ever flows
host → client, so the boards are exact mirrors and one flip is the whole transform.
Lane index needs no transform (the board mirrors front-to-back, not left-to-right).

`{fal}` cannot be a death list: the client's corpses are swept by the trailing board
snapshot, not by `try_die`. Instead `_net_replay_fallen` names its own mortally-struck
bodies against the same `_death_flush_beat` budget. Those beats are load-bearing twice
— they make the names readable one at a time, AND they hold the snapshot back (it sits
in `_net_event_backlog` while `_net_replay_active` is on), so the corpses sweep *after*
their names have been read.

**Captions now ride ONE funnel.** `_set_phase_caption` reports to the clash log itself.
They used to be mirrored by hand-placed `_net_log_caption` calls beside a few of the
sites, which is exactly why the client's phase line went blank through the ranks, the
fallen and the Arbalest while the host narrated them: every caption added since had to
remember to add its twin, and none did.

### 3. Creature-trigger FX reach the client

`dispatch_on_enter` / `dispatch_on_death` / `_resolve_on_play_ability` fire on the HOST
ONLY, so a skirmish client watched a battlecry as three HP numbers quietly changing —
no ring off the body, no tracer to what it hit, no grace wave over what it buffed.

`_play_trigger_fx` now enqueues `{eid, trig: channel}` on the fx queue, and
`_net_replay_trigger_fx` replays it. Only the eid and the channel cross the wire; the
effect dict comes back out of the local node's own `card_data`, so a battlecry cannot
describe itself differently on the two machines.

Split into two passes around the board reconcile, because the channels anchor
oppositely: **"death" runs BEFORE the despawn loop** (its FX radiate out of a seat that
is about to be empty), **"enter"/"play" AFTER the reconcile** (a creature that arrived
in this very snapshot has to exist to announce from).

### 4. Smaller gaps, same shape

- **Your own potion had no beat.** `_net_show_potion_reveal` is the beat you watch your
  OPPONENT drink; your own quaff emptied a belt slot and moved a number. `_net_drink_beat`
  now plays `_play_potion_drink_fx` + the chronicle quaff line for the drinker on both
  branches. (Deliberately NOT `tonic_vigor` — the host already fires it for the drinker's
  side in `_net_apply_host_potion`; doing it here would double it and desync the client.)
- **Mirrored keyword chips had no device.** The replay looked the icon up for exactly one
  label (`"LAST STAND"`) by string-matching it, so every other keyword chip came out on
  the client as bare text. The alias now rides the fx entry.
- **The foe's creatures were never readable.** Skirmish already holds the foe's SPELLS
  center-screen under "OPPONENT CASTS"; their creatures got a 420 ms fly-by at 132px,
  too small and too brief to read a battlecry off. A rules-bearing body now gets
  `_reveal_cast_card(..., "OPPONENT PLAYS")` — reusing solo `_announce_enemy_muster`'s
  two decisions (`_card_has_hidden_rules` filter, click-through overlay) rather than
  inventing new ones.
- **The planning overlay floated over the fight.** Solo drops the lane forecast at the
  instant it flips to RESOLVING; the skirmish commit never did, so a net clash had
  `DIES` / `TAKES 1 - 8 HP` chips over the bodies actually dying — the forecast
  contradicting the board. Both net commit paths now call `_clear_threat_flags()`.
- **Every skirmish was fought on the act-1 meadow.** `_combat_visual_act()` returned a
  hard 1. It now draws from the shared match seed (`1 + |seed| % 3`) — from the SEED and
  not a local roll, because the ground is a thing two players describe to each other,
  and a Bo3 keeps one ground for the series.

## 5. The animation pass

The clash above is *pacing*. A second sweep over the animations themselves found
four more, and the first is the largest single visual divergence in the game.

### The client played the RETIRED death

`Card2D._die()` prefers `_play_burn_death()` — ★1, "the writ burns", the parchment
eaten upward behind an ember frontier — and falls back to a shrink-spin-fade only
when it cannot run. `_net_despawn_creature` **hand-rolled that fallback**, verbatim.
So the writ burned on the host's screen and shrank on the client's: two players in
one match watching different deaths, in the game whose whole identity is paper and
ink. The copy also skipped `_spawn_death_burst()` and never killed the clash tweens,
which are still writing `position` on a body that died mid-lunge (most do).

The fix is a split, not a call: `_die()` is *death* — it emits `destroyed`, which runs
on-death dispatch and the encounter/ally hooks, and **a client must never resolve any
of that**. So the visual half became `Card2D.play_death_flourish()` (setup, death
burst, sacrifice rise, burn, fallback) and the two paths share it. `_die` keeps the
emit and the cue; the client calls the flourish alone. One copy of the animation.

### Banish told the client it was a death

Solo's `_play_banish_exit` is authored as explicitly *not* a death — "no ash, no
On-Death" — the token spirals small into a contracting pale ring. The client played an
**ash burst** and a fade. Ash is this game's word for death, so the client was told the
wrong thing about the removal it was watching. Now routed through the authored exit
(safe here: the row arrays are already cleared, which is its stated precondition).

### The Command pulse lost its beat

Every solo play site passes `MANA_SPEND_BEAT`, which pushes the RESOURCE half a beat
behind the CARD so the eye separates "that left my hand" from "that cost me one".
**All three skirmish play sites** passed the `0.0` default — so a skirmish play was
exactly the four-events-on-one-frame mush that offset was introduced to fix.

### The skirmish writ rose from the wrong point

`_spawn_spell_cast_ghost` positions the raised writ around a **centre**; both solo call
sites pass `global_position + size * 0.5`. Both skirmish sites passed the raw origin,
so the writ rose from half a card up-and-left of the sheet the player had just let go
of.

### Checked and already correct

Play flights (host through `_play_creature`'s arc, client through
`_client_animate_own_play`, unified 2026-08-03) · the deal-in (the client's hand goes
through the same `_draw_card`, deck peel included) · the idle bob (armed by
`play_wax_press` at the end of every landing pop, both sides) · strike lunge / recoil /
brace (replayed from the reel) · face damage (`_play_face_strike_vfx`,
`_play_face_damage_flash`, shake, punch, floats) · the killing-blow world-stop.

## Probe bugs found on the way (all pre-existing)

Worth recording because two of them had been masking real state for a while.

1. **`_probe_net_repos_client` was booting SOLO.** It set `_connected` and
   `remote_present` but not `_compatibility_confirmed` — the third term of
   `is_connected_to_peer()` — so `_is_net()` was false throughout and every assertion
   was measuring `_on_field_move_dropped`'s *campaign* arm. It also asserted a retired
   contract (the client "snaps back home" and waits for the host; it has predicted the
   move locally for some time), so it was permanently red for a reason none of its
   labels named. Both fixed. `_shot_net_clash` had the identical SOLO trap.
2. **`_probe_round_open` was self-poisoning.** It saved and restored six tutorial flags
   but called `reset_tutorials()`, which also clears `first_battle_tutorial_complete` —
   the GATE on the muster tip. So it passed once on a profile that had finished the
   walkthrough and failed on every run after its own first, and the failure looked
   exactly like a ladder regression. It now stands the walkthrough down explicitly and
   restores the gate with everything else.
3. **`_probe_beat_spacing` pinned the rule this pass changed.** Correct behaviour for
   that probe — it forced the change to be argued rather than drifted in. The assertion
   is now inverted and split: `_round_beat` must still bail in net (structural),
   `_lane_dwell` must NOT, and the net clash must go through the shared paced unit and
   log its pacing as a kind.

## Not done, and why

- **`_round_beat` in net.** Same reasoning as ever: making `_start_round` a coroutine on
  the skirmish turn machine is a real risk for a purely cosmetic gain. The round-open
  groups still land together in skirmish.
- **An encounter intro banner for skirmish.** Skirmish has its own opener (the coin toss
  ceremony) and no encounter to name. Adding one would be a new feature, not parity.

---

# SECOND PASS — THE STRIKE CONTRACT (same day)

**Status: BUILT.** Gates: `_probe_net_clash_beats` (+4 checks), `_probe_net_client_replay`
(+15 checks), plus the unchanged set above. Eyes: `_shot_net_client_death` (its reel was
updated to the current wire format — a reel written without `p` photographs the fallback,
not the shipping path).

The pass above closed the *structural* gap: the watcher now gets the same paced,
serialized, spotlit clash. It did not close the **strike** gap, because three combats
commits landed AFTER it and none of them crossed the wire:

| shipped | reached the client? |
| --- | --- |
| `hold_strike_frame` — the real hitstop (2026-07-31) | no |
| `_strike_stop` / `_strike_read` — weight-class pacing | no |
| `_strike_contact_point` — the blow lands on an EDGE | no |
| the ranged tracer (tighter, colder) | no |

## 1. The blow's weight class now crosses

`_net_log_hit` gained `p` (pre-mitigation size) and `rng` (a shot, not a swing). This is
the load-bearing one: the host weighs a strike's punctuation, tracer width and spark
spray off `atk`, while `n` is only what survived Armored, a Shield or an HP floor. **A
heavy swing a Shield ate whole is still a heavy swing** — the client, working from `n`,
ran a different weight class for the same blow. Both fields are optional, so the ten
incidental sites (cleave splash, overflow spill, hydra, stampede, the ledger) keep
passing nothing and fall back to `n`, which is the right answer for a rider that has no
weight of its own.

## 2. The watcher gets the hitstop

`_net_strike_punctuation` is the new shared funnel and it runs the host's own
`_strike_stop` / `_strike_read` against the **local** `Motion.time` and anim_speed — the
same "the decision crosses, the clock belongs to the reader" rule the lane dwell follows.
The freeze goes on BOTH bodies for the reason it does host-side: on the attacker alone it
reads as a stutter, on the defender alone as a hitch.

Measured divergence it closes (client → host): chip **130 → 70 ms**, heavy **260 → 200**,
lethal **260 → 280** — and the freeze itself, which the client simply did not have.

## 3. A trade is ONE beat, not two

Host-side the forward blow and the Cross-Blitz counter both resolve inside
`_creature_attacks_creature` and a SINGLE weighted hold punctuates the exchange. The
client replayed the two logged halves as independently-punctuated strikes: it paid the
hold twice and pushed the counter's tracer a whole beat behind the blow that provoked it.
`_net_replay_clash` now looks ahead one entry — a `{d}` followed by a `{d, ctr}` is
replayed dry and the forward blow's weight buys the one hold. **The mutual trade is the
default in the alternating style, not an edge case.**

## 4. ★8 — the blow that ended it

The host declares the match over inside `damage_enemy_hero`
(`_check_game_over → _net_host_check_match_over`), so its winning blow freezes the killer
at full extension exactly as solo does. The client has no such path: it learns the verdict
from `EV_MATCH_OVER`, which sits in `_net_event_backlog` until the whole reel has finished
— so **the biggest single moment in a match went by as an ordinary chip hit** and the
world-stop arrived seconds later with the banner. `_net_replay_face_hit` now claims the
hold at the blow (`_net_killing_blow_held`, one game per Combat scene, so no reset).

Deliberately the HOLD only. The ceremony (`_play_killing_blow_moment`: the music duck, the
colour drain, the heavy shake) still rides the backlogged `EV_MATCH_OVER` through
`_net_show_result` — the one place that knows a DRAW from a win and owns the Bo3 tally.

## 5. The closing ledger reached nobody

`_post_clash_ledger` reads `_friendly_deaths_this_round` / `_enemy_deaths_this_round`, and
those are only ever incremented by a resolver — which a client does not run. So the
watcher's clash **ended with nothing summing it up**, on every clash of every match.

It is now the same one-funnel shape as `_set_phase_caption`: `_post_clash_ledger` logs
`{led: [ours, theirs]}` itself rather than being mirrored from beside its call site, which
is exactly how the phase captions went blank for a month. **The COUNTS cross, never the
sentence** — the pair is swapped on replay (`_clash_ledger_line` is shared so the wording
cannot drift), because shipping the finished string would have told the player who just
lost four bodies that their line held. Same class of mistake `fe` avoids by inverting
rather than re-deriving.

## 6. Two bugs found on the way (both hit solo too)

- **The counter was the fourth strike path and it was left behind.** The 2026-07-31 commit
  moved "all three strike paths (clash, Swift, sniper)" onto the contact point;
  `_apply_mutual_retaliation` sprayed from `_card_center(attacker)` — the middle of the
  painting, the exact surface ★4's spatter was reverted for touching. **Solo pays for this
  too**: a mustering defender counters in the campaign clash.
- **A blow fully eaten by a wall was invisible in half the cases.** The `WALL HOLDS` beat
  exists precisely because a blunted hit is otherwise indistinguishable from a dropped
  attack — but it was a bare `spawn_keyword_callout`, so in skirmish it fired on the
  defending player's screen and the ATTACKING player (the one whose swing had just
  evaporated, and so the one who most needs the explanation) saw the original nothing. And
  the mirrored branch — a host creature blunted by the CLIENT's wall — had no callout at
  all, on either screen. Both now go through `spawn_keyword_callout_kw` (new `wall_holds`
  style, shield-blue with the protective family), which re-broadcasts by eid.

## 7. A keyword chip fires WHERE IT HAPPENED

Every callout the host raises — POISON, THORNS, REFLECT, THE WORKS, SPLINTER, LAST
STAND, a deathrattle's label — went on the fx **queue**, which ships with the trailing
board snapshot. The clash log is deliberately sent *ahead* of that snapshot. So on the
client the entire clash played through with **no chips at all**, and then every chip in
it arrived at once, in a batch, over a settled board: the host saw a reason beside each
blow, the watcher saw a pile of words afterwards.

Mid-clash a chip now rides the reel (`{kw}`) at the position it fired, and falls back to
the queue everywhere else — a battlecry during the play phase has no reel to ride. The
two channels are exclusive by one `if` (`_net_queue_fx_chip`), so a chip can never draw
twice, and both render through the shared `_net_render_fx_chip`.

## 8. The keystone waves were host-only

`_trigger_fx_grace_wave` takes **points**, and points describe the host's board, which
is the client's mirror. So every keystone payoff wave in the game fired on one screen:
the warden's HOLD glint, the Pike Captain's VOLLEY, the War Fortress SIEGE ramp, a
`type_buff` aura announcing its beneficiaries, the Coven hop, the Magister's Ledger.

Worse: `_apply_start_round_passives` is **host-authoritative** (`if not _is_client()`),
so the client never runs those sites at all and could not have drawn its own. It received
the resulting ATK numbers in the trailing snapshot with no cause shown for them.

What made it hard to see: the CHIP beside the wave already crossed
(`spawn_trigger_callout` carries an entity id), so the watcher got the WORD — HOLD,
VOLLEY — with no wave under it. **Half a beat reads as a quieter beat, not a missing
one.** The Ledger was the exception and was worse: its banner passed no eid at all, so
that one was fully invisible to the watcher.

`Combat.grace_wave_over(cards, col)` is the funnel. It takes **cards, not points** — the
entity id is the part that survives the wire, and the receiving peer rebuilds the centres
off its own board. Sorted left-to-right on both peers, which is safe because the board
mirrors front-to-back and never left-to-right. All six sites converted; the one remaining
direct `_trigger_fx_grace_wave` call is inside `_play_trigger_fx`, which already crosses
on its own `trig` channel. Gated by four source checks so a new site cannot regress to
the local-only call.

## 9. The gate that asks the actual question — `tools/_probe_net_mirror.gd`

Every other net probe checks ONE side. Nothing had ever put a host clash and its client
replay side by side and diffed them, which is the only way to answer the question the
complaint really asked. This runs both in one process over one fight: boots a HOST, runs
a real `_net_run_clash`, records its screen and the exact reel it shipped; tears down,
re-boots as a CLIENT with the **mirrored** board and the same entity ids; replays that
reel; applies the trailing snapshot; diffs.

What it asserts:

- **The board ends identical, body for body, by entity id — and on the mirrored side.**
  No tolerance. A body on different HP means the two players watched different fights.
- **The caption sequence is identical.**
- **The ledger is MIRRORED, not copied.**
- **The watcher holds its corpses through the reel and sweeps them with the snapshot** —
  the deferred-deaths feel, which the first cut of this probe mistook for a mismatch.
- **Every CLASS of beat has a channel** (`l · d · p · dt · fo · dw · fal · cap · kw ·
  led`). A missing kind is a whole category of effect the second player cannot see,
  which is the exact shape of the original complaint.

**A raw `_visible_beat_seq` ratio was tried first and rejected**, and the reason is worth
keeping: the two paths are instrumented unevenly. The client's replay calls
`Combat.spawn_floating_number` directly (which bumps the counter on its first line) while
the host's numerals go through `Card2D._spawn_damage_number`, which returns early when it
cannot resolve a VFX host. It reads ~400% at perfect parity. The counts are printed as
information and deliberately not asserted.

## 10. The four surfaces either side of the clash

Audited last, because the clash is where the complaint pointed. Each of these is a
one-sided **ceremony**, and the difference between a ceremony playing and not playing is
invisible to a state assertion — both ways end on the same board. That is the same
failure shape as the client death that hand-rolled `_die`'s fallback: the watcher
silently takes the bookkeeping path where the host takes the authored one.

**The coin toss — FIXED.** The toss WINNER got the Old King's coin spun on its edge over
a dimmed board; the loser got one info line and up to ninety seconds of a static board
while somebody else decided how the match opens. The very first thing a skirmish does was
the least mutual thing in it. `_net_show_order_wait` gives the loser the same ceremony —
and it is genuinely the SAME COIN, because `CoinProp` is seeded off `SkirmishState.rng_seed`,
which both peers already share, so the two machines draw identical wear and faces. The
verdict then lands as a beat ("They go first." / "They go second — you hold The Coin.")
instead of as a silent state change. The old wait loop is kept verbatim, 90 s timeout and
raw-flip fallback included.

**Emotes — ALREADY CORRECT, no change.** The index crosses and each machine renders line
`#idx` from the SPEAKER'S lord table (both peers know both lobby picks), so the words
match by construction. The sender hears their own line brighter and higher-pitched than
the receiver does, which is deliberate — your voice versus theirs. `_show_emote_bubble`
frees the previous bubble per side, so a spamming peer cannot stack them.

**The Bo3 interstitial — FIXED.** Both peers already ran it symmetrically, so
player-to-player parity held. What did not hold is parity with the rest of the game: a
game inside a series was **the one fight-ending with no ceremony at all** — a 24px caption
swap and a sting, exactly the "decisive beat presented as a label" that
`_show_battle_verdict` was built to replace. Every solo fight gets the banner, and so does
the series' last game; games 1 and 2 of a Bo3 got nothing. Now takes the world-stop and
the banner (carrying the running score as its detail line), guarded on a real winner
because a DRAW is neither of the two words the banner can say. The hold went 2.2 s → 2.8 s:
the banner alone holds 1.7 and fades over 0.4, so the old wait advanced the scene into its
own fade.

**The sealed reveal — TWO FIXES.** `_sealed_clear_pending_local`'s own header says the
flip "belongs to the REVEAL only" — and the reveal was the one caller that never passed
it. The host played ★5's authored turn-over (the face-down backs going edge-on so the real
cards open out of them); the watcher's ghosts simply blinked out. One argument. Second,
`_net_sync_board()` sat *after* the spawn loop, so the host watched the orders **stamp
down one at a time in initiative order** — the mode's signature moment — while the watcher
got a single snapshot with every card on one frame. Syncing per order gives the client the
same paced arrival through the path it already has (`_net_apply_board_sync` →
`_net_spawn_creature` → `_play_landing_pop` → the wax press). Deliberately **not** a new
reveal-order message: the snapshot stays the client's single authoritative source, which
is what keeps this cheap in risk, and a sealed round commits at most eight orders.

## 11. The exhaustive animation sweep — and the one rule that came out of it

Every animation entry point in `Card2D` (`play_*` / `hold_*` / `_spawn_*`) and `Combat`
(`_play_*` / `spawn_*` / `_show_*`) was enumerated and classified. Three buckets:

**Local by nature, correctly untouched** — modals and pickers (discover, scry, reorder,
recycle, discard, keyword choice, glossary, pile viewer, primer), own-hand and own-pile
beats (deck peel, reshuffle streak, discard landing, return-to-hand; the foe's hand is
hidden by design and only the discard COUNT crosses), per-peer HUD (`_show_info`,
`_show_turn_banner`, `_spawn_phase_pulse`, `_punch_label`, `screen_shake`,
`_show_targeting_arrow`), and the solo-only encounter furniture (`_show_encounter_intro`,
`_play_army_rollcall`, `_play_faction_wave_vfx`, `_spawn_siege_fortifications`,
`_spawn_encounter_structures`, `_show_opening_muster_forecast`).

**Already crossing** — the whole strike chain, deaths and banishes, arrivals and the wax
press, tracers and impact bursts, face strikes and flashes, spell delivery, potions,
relic chips, keyword and trigger callouts, `_play_trigger_fx`, the killing-blow moment,
the verdict banner, `_play_creature_death_vfx`, `_play_clash_commit_vfx`,
`_show_lifelink_heal`, `_play_slot_claim_vfx`.

**Found host-only and fixed** — the tribe keystone SIGNATURES. All three run in
host-authoritative resolvers the client never executes, and all three had already shipped
their CHIP while keeping their ANIMATION local:

| signature | was | now |
| --- | --- | --- |
| Dire Alpha's charge (`_maybe_stampede`) | ring host-only | `ring_over` |
| Alpha's howl (`_maybe_beast_encore`) | ring host-only | `ring_over` |
| Gravepact reap (`_apply_ally_death_passives`) | wisp host-only | `wisp_between_slots` |
| Coven Mother's pulse | ring host-only | `ring_over` |

**THE RULE, which is the durable part:** *a visual anchored on a POSITION cannot cross
the wire.* Positions describe the host's board and the client's is the mirror. Every
net-reachable beat must be raised through a funnel that ships **identity** instead — an
entity id (`ring_over`, `grace_wave_over`) or a slot coordinate plus a side
(`wisp_between_slots`, which is slot-anchored at BOTH ends precisely because the corpse is
swept by the same snapshot that carries the fx, so an eid origin would resolve to null
exactly when it was wanted).

And the reason all of this survived two earlier passes: **the chip crossed and the
animation didn't.** The watcher read HOLD, VOLLEY, STAMPEDE, ENCORE, REAP with nothing
erupting underneath. Half a beat reads as a quieter beat, not a missing one. Gated in
`_probe_net_mirror` phase E, which fails if any of those resolvers goes back to a direct
`_trigger_fx_ring` / `_spawn_vfx_streak` call.

## 12. Review pass — bugs found in the work itself

**THE RESULT OUTRAN ITS CAUSE (pre-existing, the worst of them).**
`_net_host_check_match_over` is reached *synchronously* from `damage_enemy_hero` →
`_check_game_over`, i.e. from inside the clash — while the reel holding the killing blow
is still unsent (it does not ship until the clash ends). So on any host-side killing
blow the watcher received `EV_MATCH_OVER` first, showed the verdict banner over a settled
board, and only **then** got the reel and replayed the fight that produced it. Fixed by
flushing the reel before sending the verdict; the client's existing backlog then holds
`EV_MATCH_OVER` behind the replay, so the blow lands, claims its ★8 hold, and the
ceremony follows it. Recording is deliberately left off afterwards — the remainder is
post-lethal, the trailing sync still reconciles the board.

**Two chips still bypassed the router.** `_apply_piercing_overflow` and `_net_fx_text`
appended to `_net_fx_queue` directly, so PIERCING and every mirrored stat float
(`+2/+2` tonic vigor, the Gravepact bequests, the type_buff aura) still batched onto the
trailing snapshot while every other chip had moved into the reel. Both now route through
`_net_queue_fx_chip`. Gated: the probe scans both files for stray `_net_fx_queue.append`
and allows exactly two — the `{trig}` entry (whose two-pass anchoring around the board
reconcile belongs to the snapshot, not the reel) and the router's own else-branch.

**A solo visual was restyled under cover of a parity fix.** The first cut of `ring_over`
promoted the Coven Mother's pulse from its single soft ring to `_trigger_fx_ring`'s
doubled white-hot device. The howl and the charge already called `_trigger_fx_ring` and
were untouched; the Mother's was the odd one out and got louder for no reason anyone
asked for. `ring_over` now takes `plain` and that site keeps its original look. **A
mirroring change must not restyle solo on its way past.**

**A node deref I introduced.** `_maybe_pay_ledger`'s `struck` array used to hold POINTS
(immune to a body being freed) and now holds the bodies; the LEDGER banner dereferenced
`struck[0]` with no validity check, and `_card_center` carries no guard of its own.
Guarded.

**The ordering fix had a hole one phase later.** A Swift striker can reach the face, and
`damage_enemy_hero` declares the match over synchronously from inside the Swift pass — so
the flush ships the Swift reel ahead of the verdict correctly, and then
`_net_clash_recording = true` was re-armed unconditionally after that segment, recording
the now-moot main pass and shipping it *after* the verdict. Straight back into the
inversion, just one phase later. The re-arm is now guarded on `not _net_match_over`.

**The sealed reveal kept stamping a decided fight.** Reveal spawns run with
`run_on_enter = true`, so a battlecry chain can end the match part-way through. The
function's own tail acknowledges that ("an on-enter chain ended it") — but only *after*
the loop had seated every remaining order. The watcher read the verdict and went on
receiving fresh bodies behind it. Latent while one trailing snapshot hid it; plainly
visible once the reveal started syncing per order. Both loops now break on
`_net_match_over`.

**Two more orphaned comments, same cause as the first.** Inserting branches and
functions ahead of existing ones stranded `_trigger_fx_ring`'s doc four functions away
and left the keystone-WAVE rationale sitting above the RING branch with the wave branch
undocumented. Worth naming as a pattern: in this codebase the comment carries the
reasoning, so an insertion that separates one from its subject loses the reasoning even
though nothing breaks.

**Checked and NOT a bug (recorded so it is not re-litigated):** chips anchored on a token
summoned mid-clash. Moving chips onto the reel looked like it should strand them — the
client learns a token's id only from the trailing snapshot. It does not, because
`summon_token` never assigns an entity id: ids are issued *inside* `_net_sync_board`, in
the same loop that ships the body. So the invariant holds — **`eid >= 0` implies the
client has seen it** — and a fresh token's chips were already dropped by the `eid >= 0`
guard under both routings.

Also verified clean, each of which *looked* like a bug: the fx queue is duplicated into
the payload and cleared by `_net_sync_board`, so the reveal's eight syncs cannot repeat a
chip; the round-open waves cannot double-draw on the client, because every
`_apply_start_round_passives` caller is host-guarded; `vs_bot` pins the toss winner to the
local player, so `_net_show_order_wait` can never strand a practice match; and the wire is
`var_to_bytes`, not JSON, so no int survives as a float.

**A known edge, deliberately left.** If `EV_ORDER_PICK` arrives before the client reaches
the toss block (fast pick, slow boot), the override is already set and *neither* ceremony
plays. Pre-existing, and the obvious fix — run the loser's ceremony unconditionally —
would break the harnesses, which pre-set `_net_first_player_override` precisely to skip
the toss. Not worth trading a probe contract for an edge case.

**`_trigger_fx_ring`'s doc comment was orphaned** four functions away from it by the
`ring_over` / `wisp_between_slots` insertions, leaving the wisp wearing a ring's
rationale. Moved back. Cosmetic, but the comments here are load-bearing.

**The probe caught my own comment.** The ordering check first matched the string
`EV_MATCH_OVER` and found it in the rationale comment *above* the fix, so it failed on
correct code. Matched on the call now — the same trap `_probe_net_client_replay` already
records for `_play_burn_death`. Worth restating: **a source probe that greps for a word
rather than a CALL will keep finding prose.**

## 13. Robustness pass — degrade, don't crash

A separate sweep over the net layer's wire handling. The architecture already hardens the
direction that matters — the HOST validates every client intent, with bounds checks and
`_net_reject_remote` (41 sites), and `IN_ORDER_PICK` is a model of it: single-settle,
toss-winner check, `settled in [0, 1]`. The **client's** side of the wire was thinner. The
host is authoritative and therefore trusted, so none of this is a security control; it is
the difference between a peer's bug degrading and a peer's bug taking you down with it.

- **`_net_spawn_creature` never bounds-checked its seat.** Two of its three production
  callers validate before arriving (`_sealed_reveal`, `_net_apply_remote_creature`), but
  `_net_apply_board_sync` reads lane/row straight out of the snapshot and does not — so a
  host that shipped an out-of-range seat crashed the client on `_row_array(...)[lane]`
  instead of dropping one body. Guarded at the chokepoint, which covers every future
  caller. Safe to return null: no production caller reads the result.
- **`EV_ORDER_PICK` and `EV_ORDERS_PHASE` took side indices raw.** Neither is an opaque
  flag: they become `_net_first_player()` / `_net_initiative`, which feed
  `1 - attacking_side` into `_doubled_hour[...]` and `[initiative, 1 - initiative]` into
  the sealed reveal, where `_net_cards_played[side]` is size 2. Out of range is a negative
  array index on the watcher, not a wrong turn order. Both clamped, matching the host-side
  twin that already did.
- **`EV_DRAW` looped a raw wire count.** `draw_one` reshuffles the discard when the deck
  runs dry, so a bad `n` does not terminate early — it spins. Bounded by `MAX_HAND_SIZE`.

Checked and already correct: `_sealed_load_spell_state` validates its side before
subscripting; `_sealed_show_ghost`, `_net_apply_remote_creature` and `_sealed_reveal` all
bounds-check lane/row; `_net_show_foe_emote` range-checks its index;
`fade_out_then_change_scene` guards a freed host, which makes the peer-lost teardown
timers safe despite capturing the combat node.

## 14. Sweeps that came back clean

Recorded because "we looked and it was fine" is worth as much as a fix, and each of these
looked like a defect from the outside:

- **All 40 round/turn-scoped latches are reset.** Two appeared unreset only because they
  are cleared by whole-array assignment (`= [0, 0]`), and several more because the reset
  lives in CombatNet rather than Combat. The `_this_fight` latches are *correctly* never
  reset — a fight is a scene instance, and `change_scene_to_file` gives every rematch a
  fresh one. `_volley_fired` / `_works_fortified` / `_ledger_open` are the documented
  durable arming devices and must stay unreset.
- **The remaining position-anchored FX are out of reach or already crossing.** The
  `_spell_fx_*` family runs *on the client* through `_play_spell_cast_vfx`, so it anchors
  on the client's own nodes by construction. `_grave_wave_fx` is slot-anchored and would
  be trivially mirrorable — but `sextons_spade` is not in `NET_RELIC_POOL`, so the Second
  Wave is campaign-only and there is no gap to close. `_play_faction_wave_vfx` is likewise
  encounter-driven and solo-only, and the pile streaks describe the caster's own piles.
- **`_probe_events`: 430 effects, 100 gates, no errors.** (Its own summary line contains
  the words "SCRIPT ERROR" as an instruction to the reader, which reads as a failure to a
  naive grep. It is not one.)

**A limitation worth stating:** `_probe_net_mirror` phase E pins three named funnels and
three named resolvers. It cannot catch a *new* keystone added at a fourth site with a
local-only wave. The router check (§12) is the general one; the phase-E list is not.

## Not done, and why

- **`_check_game_over` does not fire on `damage_player_hero`, in solo either.** So the ★8
  hold has never fired on a *defeat* blow — only on a victory one. That is a real solo
  finding, but moving when defeat is detected is a control-flow change, not a parity one,
  and it belongs to whoever owns the defeat sequence.
- **`_round_beat` in net.** Unchanged, same structural reason as above.
