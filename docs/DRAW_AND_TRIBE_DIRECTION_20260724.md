# Draw Structure + Tribe Identity — converged design direction (2026-07-24)

**What this is.** The output of a two-round design bounce (Claude + an adversarial design agent)
on two questions the user raised: (1) is "refill hand to 5" the right structure? and (2) the six
tribes are "only technical" — how do we make them matter? Multipliers were explicitly dropped from
scope. This is a converged DIRECTION both parties endorse — not yet built. Sister docs:
`RELIC_SLATE_PITCH_20260724.md`, `RELIC_POOL_AUDIT_20260716.md`.

## THE DOCTRINE (the one line the whole thing collapses to)
> **The durable layer is a silent ledger; the board is the only thing allowed to be loud.**

Diagnosis behind it: *every current tribe keystone keys off live board state (warden = full front
row, bastion_ramp = per-round-on-board, kingpin = strays-on-board) — the one layer wiped every
fight.* So tribe identity evaporates on every board wipe and can never snowball. That is the root
cause of "tribes feel only technical." The fix is NOT to move identity off the board (that trades a
technical *tag* for a technical *counter* the player never sees). It is: **the CONDITION/COUNTER
accrues on a durable layer that survives the wipe (deck density, a fight-scoped counter, run
memory); the PAYOFF always climaxes on the lanes**, where the player is looking and where BM's whole
positional identity lives.

---

## PART A — the hand / draw structure

**Verdict: keep refill-to-5. Do not replace it.** Replacing it (e.g. "draw 2, keep, cycle") would
**invert the Command→cards bottleneck** the entire cost economy is tuned against — you'd be
Command-flush and card-starved, banking Command would be pointless, and every printed cost would
need re-tuning. It's a load-bearing wall, not a sacred cow.

The real problem is narrower: draw is a DEAD lever (you always end at 5, so card-advantage effects
"wash"). Three fixes, ranked:

1. **SELECTION is the backbone (the fix we were missing).** Re-point every washed "draw +1" design
   at **quality, not quantity** — scry / dig-for-a-tribe / bottom-a-dud. Same five cards at end of
   turn, *better* five. Cannot spiral (count unchanged), no dead-draw feel-bad (you remove duds
   rather than draw them). **Plumbing note (verified 2026-07-24):** this is NET-NEW — `_look_top_pick`
   only digs-and-draws-cheapest; a real scry / bottom-a-dud verb must be built on the (accessible)
   draw-pile array. Cheap, but do not assume it exists. This systemically resurrects the dead lever.
2. **Durable identity-reads (the bridge to tribes), keyed off deck density + run memory — NOT hand
   composition.** "While you hold 2+ Beasts" is a sandbag trap in a Dragons costume — it rewards
   *hoarding*, which is losing in a tempo/attrition game. Deck-density and run-memory can't be
   hoarded mid-fight, so they're the safe commit layer. **Hand-reads are allowed only when the
   trigger is the ACT OF PLAYING** ("when you play a Beast with another Beast to follow"), never the
   act of holding.
3. **On-turn action-granted draws only** ("when you do X on your turn, draw") — fires mid-turn,
   playable this turn, survives the wash. The game already does this well.

**Killed:** A1 "reward the leftmost held card" (sandbag tax — pays the Command-starved loser).
**Demoted:** A2 passive "board-state sets the refill number" (win-more when wide + anti-comeback
when wiped/on the dead muster round). Keep only its on-turn action-granted-draw half.

**Load-bearing caveat:** deck-density reads inherit the invisibility disease unless a persistent HUD
tell shows the state ("DEAD ASCENDANT" chip under the Command seal). Deck-density GATES the
condition; it must never BE the moment. See the open decision at the bottom.

---

## PART B — tribes: rhythm + cross-rarity arc + a signature MOMENT (no multipliers)

A tribe earns identity with (a) a **rhythm** it plays around, (b) **2–3 payoffs across rarities** so
drafting into it is an *arc*, and (c) a **signature MOMENT** that *accrues durable, climaxes on the
board*. Two structural moves: **commit via deck density / run memory** (not a fragile board
condition), and **visible on-screen identity** (each tribe has a CTYPE_COLOR; a Beast arrival, a
Dead detonation, a Warlock cast should LOOK like different verbs).

| Tribe | Axis (kept distinct) | Signature MOMENT (no multiplier) |
|---|---|---|
| **Soldier** | WIDTH × COUNT (dies to wipes) | **Volley** — first time the front row fills, every Soldier gains +1 ATK and Piercing for the clash (additive + keyword + timing). |
| **Bastion** | DURATION × TIME, **paid on being struck** (dies to burst) | **The wall bites back** — reflect *HP actually lost* when struck (Iron Rampart `reflect_strike` model); self-balancing, fires in a 2-round fight, no stall required. |
| **Beast** | ARRIVE / tempo | **Stampede** — 2+ Beasts arriving one turn resolve as one wave; the last hits a *creature* hard / aimed down a column. **Never the face on arrival** (that's the Beat-the-Retreat guard). |
| **Dead** | DIE / cycle bodies | **Second Wave** — friendly deaths bank souls on a fight-scoped grave counter; every 3rd, Wights claw up onto the board (spec below). |
| **Warlock** | SPELLCRAFT / spell volume | **Overload** — casting your 2nd spell in a turn makes the next spell that turn echo / hit a 2nd target once (on-turn, survives wash; fixes the glacial +1-ATK-per-spell keystone). |
| **Stray** | MOBILITY + LARCENY (gold spine dropped) | **Defection** — a Stray that kills loots a keyword off the corpse, or free-redeploys if nothing worth taking (spec below). |

**Soldier vs Bastion no longer collapse:** Soldier = many cheap bodies buffing each other, fears the
wipe; Bastion = few walls that convert being-hit into geometry damage, fears burst/Piercing. Their
*enemies differ* → two decks.

**Stray was the weakest — an anti-identity** ("no synergy" can't have a synergy moment) on a broken
spine (gold pays invisibly in the shop, is skirmish-denylisted, and "go solo" is a losing shape on
4×4). Rebuilt on **mobility + larceny**, which is clash-time, skirmish-safe, fills the near-empty
movement gap, and engages the untouched muster-delay space.

---

## PROOF-OF-CONCEPT BUILD 1 — Dead / Second Wave  (build FIRST)

**"The Sexton"** (rare keystone creature; pairs with the existing Sexton's Spade relic) · 4-cost
~3/4 Dead. **Playing it arms the grave for the rest of the fight, and the arming survives its own
death** (a wipe that kills The Sexton doesn't stop the engine — you commit by drafting + deploying
once, not by keeping a fragile body alive). While armed, every friendly death banks a soul on a
**fight-scoped grave counter** (persists across rounds, resets between fights); **every 3rd soul,
three 2/2 Wights (Dead, no keywords) claw up into empty back-row slots and the counter resets**.
Floor: if no empty slots, the wave instead grants +1/+1 to your Dead (or a random friendly). The
silent ledger accrues; the wave is the loud board climax.

**Checklist trace:** (a) grants *tokens to the board*, never cards → refill-wash immune. (b) deaths
bank during the clash; Wights arrive *after* clash resolution and obey the muster delay (form up,
swing next round) — no "this-turn buff" to evaporate. (c) **the two build flags:** increment the
soul via the ally-death passive listener (`_apply_ally_death_passives` / Gravepact hook), **never**
`_trigger_player_sacrifice` (or it trips an encounter's `ON_PLAYER_SACRIFICE` punishment as a hidden
rider); summon the Wights via `summon_token`'s clean path so they don't recursively re-fire
death/sacrifice reactives. positivity: only adds bodies, floored when full, no backfire. **anti-
pattern guard:** a 3-death threshold is the "per-fight counter that can't pay in 2–3 rounds" trap
*unless the drafter manufactures the deaths* — Dead does (sacrifice spine + aggressive trades), so
threshold-3 is reliably hit by its own drafter and a floor-of-value for anyone else. Counter must
persist within the fight. Why first: loudest legible moment, most existing machinery, cleanest proof
of the doctrine.

## PROOF-OF-CONCEPT BUILD 2 — Stray arc  (build SECOND — fixes the worst tribe)

- **COMMON "Deserter"** · 2-cost 3/2 Stray. *On-play: move one friendly to any empty slot, free
  (doesn't spend your move cap).* Optional → floors to a plain 3/2. Teaches the verb: Strays
  rearrange the line.
- **UNCOMMON "Sellsword Outrider"** · 3-cost 4/3 Stray. *Start of your turn: may move this to any
  empty slot free (ignores move cap); on move, +1 ATK this round.* The dancing flanker.
- **RARE keystone "Free Company Captain"** · 4-cost 4/4 Stray. **Defection: on killing an enemy
  creature, steal one of its keywords; if none worth taking, free-redeploy instead.** Tribe turn-on:
  *other friendly Strays also free-redeploy on kill* — drafting the Captain makes the whole Stray
  line mobile-on-kill.

**Checklist trace:** (a) no draw touched. (b) Defection fires on-kill in the clash; the stolen
keyword is a *persistent* grant (not a this-turn buff), so no off-turn evaporation. (c) triggers on
**enemy** death → never touches `ON_PLAYER_SACRIFICE`; keyword-steal is a read, not a re-route.
positivity: mobility always optional (never a forced bad move); larceny floored (steal-or-redeploy,
never zero); +1-on-move only adds. **THE load-bearing flag: every Stray move MUST preserve
`ready_to_swing`** — a reposition is not a re-muster; else the movement tribe gives itself perpetual
summoning sickness. (This is also the *first* mechanic to engage the untouched muster-delay space —
a second reason to exist.) **Playtest watch:** dodge-tanking (a Stray repositioning out of every
losing clash) — countered by snipers/AoE/full board, judged intended-strong; cap to once-per-round
or restrict the uncommon's self-move to its own row if it reads oppressive.

---

## THE ONE OPEN DECISION (scope call — user's)
Deck-density commitment needs a **persistent HUD "ascendant" tell** (e.g. a "DEAD ASCENDANT" chip
under the Command seal) or the player can't see their tribe payoff is active — density silently
gating a payoff is the invisibility disease relocated from the board to the decklist.
- **Option A (agent & Claude lean):** build the tell — one readout, reused by all six tribes;
  unlocks deck-density as a clean, hoard-proof commit layer for the whole system.
- **Option B (fallback):** don't build the tell → tribe *commitment* can't live on deck-density;
  fall back to **run-memory + the keystone creature's on-board presence** as the visible signal (The
  Sexton *being on the field* is itself the tell that Second Wave is armed). Narrower, but zero new
  HUD.

## Build order
1. **Dead / Second Wave** — proves the doctrine (accrue durable, climax on board), most machinery,
   loudest moment.
2. **Stray arc** — fixes the worst tribe on one load-bearing verb; opens the movement + muster gaps.
3. **SELECTION plumbing** — re-point washed "draw +1" effects at scry/dig/bottom (universal, A-only).
4. The other four tribe arcs (Part C), each on the same accrue-durable/climax-on-board pattern.
(Contingent on the open decision: the HUD tell, if Option A, before the density-gated turn-ons.)

---

# PART C — the other four tribe arcs (same standard as Dead/Stray)

**Three doctrine devices reused across all four** (each keeps identity off the wipe-able board):
- **The arming trick** (Sexton precedent): playing the RARE keystone arms a fight-scoped condition
  that **survives the keystone's own death** — you commit by drafting + deploying once, not by
  nursing a fragile body. (Used where the tribe needs a durable engine: Warlock, Bastion.)
- **The once-fired latch**: a MOMENT that fires the first time a board condition is met each fight;
  the "fired" flag is durable, so a later wipe can't un-fire the payoff. (Soldier's Volley.)
- **Deck-density commit turn-on**: `_deck_ctype_count(t) * 2 > _deck_data().size()` (helper is LIVE,
  RelicDB.gd:934). Wipe-proof, hoard-proof. **Requires the HUD "ascendant" tell (open decision,
  Option A).** Where the tell isn't built, the keystone's on-board presence is the fallback signal.

**Rework-vs-new principle (settled 2026-07-24, verified in code):** rework the existing keystone IN
PLACE *only where the old effect IS the evaporating board-keyed accumulator the doctrine retires* —
that's **Warlock (`coven_spell`, +ATK/spell on a dying body), Bastion (`bastion_ramp`, +ATK/round
while standing), and Stray (Kingpin's gold aura, the dropped spine)**. Where the old effect is already
fine — a repeatable per-round conditional (`warden_line`) or a present-tense arrival trigger
(`beast_encore`) — **KEEP it and add the new payoff as a second, differentiated rare** (Soldier
Volley, Beast Stampede). Net split: **3 in-place reworks + 3 additive new cards** (Sexton is also new;
Gravepact stays). See PART D for the exact per-spec migration list. Existing keystones per CLAUDE.md:
Warden-Sergeant (`warden_line`), Coven Mother (`coven_spell`), Siegewright (`bastion_ramp`),
Bloodmoon Alpha (`beast_encore`).

---

## SOLDIER — WIDTH × COUNT (endure; fears the wipe)
**Rhythm:** many cheap bodies that are worth more together than apart; the back row is a relief rank
that reforms the line through deaths. Scales with HOW MANY. Distinct from the oversubscribed
positional-+1 banners: it rewards **total count**, not "standing next to a friend."

- **COMMON "Rank-and-File"** · 1-cost 2/2 Soldier. *+1 ATK while you control 2+ other Soldiers.*
  Count-based, floors to a plain 2/2. Teaches: field the line wide.
- **UNCOMMON "Line Sergeant"** · 3-cost 3/4 Soldier. *When the Soldier in the lane in front of this
  dies, this advances into the gap (resolves after the clash — fights next round). While it holds a
  front lane, Soldiers in its row have Thorns.* The relief-rank durability + the back row as reserve.
- **RARE keystone "The Provost-Marshal"** (reworks Warden-Sergeant) · 4-cost 3/5 Soldier. **VOLLEY —
  the first time you fill all four front lanes each fight, every Soldier levels pikes: +1 ATK and
  Piercing for that clash.** Commit turn-on: *while your deck is majority Soldier, the front row also
  gains Armored for the fight.*

**Signature MOMENT:** the whole line fires as one, once, when the wall of pikes is first complete.
**Durable device:** the once-fired latch — the "Volley fired this fight" flag survives a later wipe,
so a collapse after firing doesn't erase that it happened. Deck-density carries the commit turn-on.
**Checklist:** (a) no draw. (b) Volley resolves DURING the clash it's declared for — correct, it's a
strike buff not a resource grant; the advance in Line Sergeant resolves after the clash (the Fill-the-
Breach timing rule — a body can't arrive mid-simultaneous-combat and swing that round). (c) no
death/sac re-route — Line Sergeant's advance is a MOVE on friendly death, not a sacrifice, so it must
NOT route through `_trigger_player_sacrifice` (ON_PLAYER_SACRIFICE backfire). **positivity:** every
piece only adds; a lone Rank-and-File is a clean 2/2. **Reason to exist:** gives Soldier a loud,
once-per-fight board climax that a wipe can't evaporate, and a legible reason to go wide.
**Playtest watch:** full-row Piercing is a big board-clear — once/fight caps it; verify the overflow-
to-face path isn't a burst-finisher (it obeys the normal Piercing rules, which already exist).

## WARLOCK — SPELLCRAFT / spell volume (fears running dry)
**Rhythm:** cast MANY spells per turn; the tribe is the caster line that turns spell flow into board
pressure. This is the tribe that most benefits from the SELECTION backbone (dig for spells).

- **COMMON "Acolyte"** · 2-cost 2/2 Warlock. *On-play: look at the top 2 cards of your deck; draw a
  spell if there is one, otherwise bottom one.* The SELECTION primitive as fuel — teaches spell flow.
- **UNCOMMON "Chantry Scribe"** · 3-cost 2/4 Warlock. *When you cast your 2nd spell in a turn, this
  scribes a glyph: deal 2 to the enemy across from it.* On-your-turn, board climax, rewards volume.
- **RARE keystone "The Magister"** (reworks Coven Mother) · 4-cost 3/4 Warlock. *Playing it opens the
  Ledger for the rest of the fight — it survives its own death.* **OVERLOAD — after you cast your 2nd
  spell each turn, your next spell that turn echoes (resolves a second time at a valid/auto target).**
  Commit turn-on: *while your deck is majority Warlock, Overload begins at your 1st spell each turn.*

**Signature MOMENT:** the doubled cast — your spell fires twice. **Durable device:** the arming trick
(the Ledger survives the Magister's death), so a wipe doesn't switch the caster identity off; deck-
density carries the turn-on. **Checklist:** (a) Acolyte's draw is a mid-turn dig on your OWN play →
survives the refill wash (the sanctioned exception); Overload re-CASTS, it doesn't hand you a card.
(b) Overload fires on your turn as you cast — never off-turn. (c) no death/sac routing. **positivity:**
never negative; Acolyte floors to a 2/2 with a free look; Overload only ever adds a second resolution.
**Reason to exist:** fixes the glacial "+1 ATK per spell" keystone by paying *within the turn* on the
board, and makes SELECTION matter most for the tribe built on spell flow. **Build flag:** route the
echo through the existing echo/`_auto_target_for` path so self-resolving spells re-target cleanly.

## BASTION — DURATION × TIME, PAID ON BEING STRUCK (fears burst / Piercing)
**Rhythm:** few big walls that convert being hit into damage through geometry — NOT ATK, and NOT
"survive to round 3" (that fights the fast-kill pacing). Every payoff fires the instant a blow lands.

- **COMMON "Gabion"** · 2-cost 1/6 Bastion. *When struck, reflect 2 to the attacker.* A cheap durable
  wall; teaches "hit me and bleed."
- **UNCOMMON "Redoubt Gun"** · 3-cost 2/6 Bastion. *When struck, reflect the HP it just lost to the
  attacker (reflect_strike). If that reflect kills the attacker, shove the enemy behind it back a
  rank.* Tanking converts to geometry damage — the siege turn.
- **RARE keystone "The Siege-Bastion"** (reworks Siegewright IN PLACE — retires `bastion_ramp`; keep
  the live 2/6 statline unless deliberately buffing, else update `_probe_interest_slate.gd:120-121`) ·
  2/6 Bastion. *Playing it
  fortifies the works for the rest of the fight — it survives its own death: all your Bastions reflect
  the HP they lose when struck.* Commit turn-on: *while your deck is majority Bastion, a reflect that
  kills its attacker also shoves the enemy column behind it back a rank (siege crash).*

**Signature MOMENT:** the wall bites back — the more you throw at it, the more it costs you.
**Durable device:** arming trick (fortify armed for the fight, survives death); the payoff itself is
paid ON being struck, so it never needs the body to *survive* — it fires on the way down.
**Checklist:** (a)/(b) no draw, no resource-timing — reflect resolves in the clash where the hit
lands, which is correct. (c) reflects damage to the ATTACKER; no friendly-death routing.
**positivity:** self-balancing for free — reflecting *HP actually lost* means a chip hit reflects
little and a haymaker reflects big; it can never be "free damage for existing." **Build flag (the one
backfire risk):** the shove-behind can CRASH against the field edge (both parties take crash damage
per `_flank_push`); make the siege shove **one-way** (enemy-only crash) or floor the Bastion's self-
damage, so a strictly-positive tribe moment can't hurt its owner. **Reason to exist:** gives the
survival tribe an identity that fires in a 2-round fight without bending the game toward stall.

## BEAST — ARRIVE / tempo (fears the empty hand)
**Rhythm:** flood on-enters; pay on arrival, over survival; drop the pack together. Beast's durable
layer is **deck-density itself** (no fight-scoped counter needed — the tribe lives in the present
arrival), so its commit turn-on IS its across-fight identity.

- **COMMON — REUSE the live `bloodhound`** (CardDB:118 — a Beast common that already does aggro-on-
  enter + a draw). Do NOT add a new "Bloodhound" (hard id/name collision, caught in verification); the
  existing card already teaches the arrive rhythm. (The on-enter lands at once even though the body
  musters — an on-enter is not a swing.)
- **UNCOMMON "Pack Leader"** · 3-cost 3/3 Beast. *On-enter: if another Beast arrived this turn, both
  this and that Beast deal 2 to the enemies across from them.* Teaches: drop Beasts together.
- **RARE keystone "The Dire Alpha"** (ADDITIVE — Bloodmoon Alpha / `beast_encore` is KEPT; encore is
  present-tense, not the evaporating shape, so this is a second Beast rare) · 4-cost 4/4 Beast.
  **STAMPEDE — when 2+ Beasts arrive on your turn, they charge as one wave: after their on-enters
  resolve, the last to land strikes the enemy CREATURE across from it (an aimed arrival strike — never
  the face; FIZZLE if that column is empty).** Commit turn-on: *while your deck is majority Beast,
  Stampede triggers at 1+ Beast — every Beast charges on arrival.*

**Signature MOMENT:** the herd crashes in and one breaks the line. **Durable device:** deck-density is
the whole durable layer (Beast is present-tense by nature; the turn-on is the across-fight commit).
**Checklist:** (a) no draw. (b) the arrival strike resolves on your turn as the wave lands — an aimed
CREATURE hit, so it does **not** touch the muster face-guard (this is the Beat-the-Retreat line we
already rejected: Beasts may not hit the face on arrival). (c) no death/sac routing. **positivity:**
Bloodhound floors to a 3/2 with a 2-damage arrival; Stampede only adds a strike. **Reason to exist:**
the ARRIVE tribe's signature was an invisible on-enter double (encore); Stampede makes the pack-drop a
loud, aimed board moment and gives "commit to Beast" an across-fight meaning via density.

---

## Coverage after Part C
All six tribes now have: a rhythm on a distinct axis · a common→uncommon→rare arc · one signature
MOMENT that accrues on a durable layer (latch / arming / density) and climaxes on the lanes · a
deck-density commit turn-on (solo-only — see PART D). No multipliers. **3 reworks in place
(Warlock/Bastion/Stray) + 3 additive new cards (Soldier/Beast/Dead).** Build order unchanged: **Dead →
Stray → SELECTION → the four above**, with the HUD tell slotted before the density turn-ons if Option
A is chosen.

---

# PART D — verification & completion (build-ready, 2026-07-24)

An independent code-grounded verification pass confirmed every load-bearing hook and closed the
open specs. Confirmed sound: `reflect_strike` reflects HP-actually-lost even on death
(Combat.gd:4712); `_apply_ally_death_passives` is the correct non-sacrifice death listener (:6497,
fires for the net client at :16732); `summon_token` (:11719) is recursion-clean; **every move site
already preserves `ready_to_swing`** (`_relocate_creature` :1734 never touches it — the Stray flag is
satisfied for free); `_deck_ctype_count` (RelicDB:934) is real but **solo-gated** (`_deck_data()` is
behind `RunState.run_active`).

## Net-parity homes (base MOMENT must fire in skirmish; density turn-ons are solo-only)
| Moment | Host-authoritative home | State |
|---|---|---|
| Soldier **Volley** (new) | `_apply_start_round_passives(is_enemy)` (already client-authoritative, `_net_sync_board` carries it, warden_line precedent) | `_volley_fired[2]` latch on Combat; +1 ATK+Piercing is a clash-only temp grant snapshotted pre-clash |
| Warlock **Overload** (rework) | re-resolve via `_net_resolve_spell`/`_net_resolve_custom_spell` (CombatNet:4410/4538, host-only) **with the Echo denylist applied** | Ledger-armed flag (survives Magister death) + per-side "spells cast this turn" counter (solo has `_spells_cast_this_turn` :9964) |
| Bastion **reflect** (rework) | new `if` branch after the `match` in `_apply_struck_passives` (:4704, already host-side + snapshots; `bulwark_lord` precedent :4731) | `_bastion_fortified[2]` flag (survives death); siege shove = **new one-way `_flank_push` variant** (vanilla :1907 crashes both) |
| Beast **Stampede** (new) | the on-enter site by `_maybe_beast_encore` (host CombatNet:2386; solo :7384/:8366) | per-side "Beasts arrived this turn" counter, reset each turn; fizzle if target column empty |
| Dead **Second Wave** (new) | increment in `_apply_ally_death_passives` (host-side for client :16732), **excluding tokens** (Gravepact `not is_token` guard) | `_grave_armed[2]` + `_grave_souls[2]` on Combat (survive Sexton death); `summon_token` ×3 host-side |
| Stray **Defection** (rework) | `_apply_combat_strike_riders` (:4738 — the on-kill funnel, host-side on every net strike path; already hosts Head-Money's stray-on-kill) | steal-keyword (persistent grant, `shield_on_slay` precedent :4804) or `_relocate_creature`; **do NOT copy Head-Money's `not _is_net()` guard :4753**, and **remove the keystone from the skirmish denylist** |

All six base moments have a real host-authoritative home → tribes play in skirmish. Only the
deck-density commit turn-ons are solo-only (documented, acceptable — skirmish balances via the
arsenal draft, and the HUD-tell decision is thereby solo-scoped).

## Migration list — the three in-place reworks only
- **Warlock (`coven_spell` → Overload):** replace handler Combat.gd:9987 + CombatNet:4506; rewrite
  `_probe_type_keystones.gd:158`; re-author the "coven hop" FX signature; if the passive string is
  renamed, update `_probe_type_audit.gd:38` + `_probe_creature_fx.gd:128`.
- **Bastion (`bastion_ramp` → Siege-Bastion):** remove the start-round ramp handler Combat.gd:6141,
  add the on-play arm flag + the `_apply_struck_passives` branch; rewrite `_probe_type_keystones.gd:167`;
  re-author the "bastion SIEGE" FX; keep the 2/6 statline or update `_probe_interest_slate.gd:120-121`.
- **Stray (Kingpin `type_buff per_gold` → Defection):** retire the `per_gold` branch in
  `_get_type_buff_atk`; rewrite `_probe_type_keystones.gd:179-192`; remove `kingpin` from the skirmish
  denylist; re-author the payday-aura FX → on-kill loot/redeploy.
- **Soldier + Beast: ZERO migration** (additive; `warden_line` and `beast_encore`/`_maybe_beast_encore`
  untouched; no probe changes).

## Corrections folded from verification
- `bloodhound` collision → REUSE the live card (Beast common); no new card.
- Overload → reuses the **Echo denylist** (can never double a self-harm/sacrifice spell). Locked.
- Bastion siege shove → **one-way (enemy-only crash)**, never self-crashes the wall.
- Stampede → **fizzle** on an empty target column, never falls to the face.
- Second Wave → token deaths do NOT bank souls; note the 3-spawner stack (Sexton + Gravepact +
  `gravewardens_pact`) as a playtest watch, not a bug.
- Soldier arc → REUSE `understudy` (relief rank) + existing count-scaling (`warchief`); the arc's only
  new card is the Volley rare. Rank-and-File / Line Sergeant dropped (duplicates).
- SELECTION backbone → net-new plumbing on the draw-pile array (`_look_top_pick` is dig-and-draw, not
  scry); cheap, but build it — Acolyte ships on `_look_top_pick` interim.

**Status: build-ready.** Every base moment verified to a host-authoritative home; migration bounded to
the three reworks where a genuinely-bad effect is retired; all prior rulings (face guard, no-free-
sacrifice, ready_to_swing, boss-only downside, no multipliers) hold.

---

# PART E — what shipped (2026-07-30)

**All six tribes now have their signature MOMENT on the board.** Dead (Second Wave) and Stray
(Defection) landed first; the remaining four landed together on 2026-07-30, gated by
`tools/_probe_tribe_moments.gd`.

**Built ADDITIVE, not as in-place reworks.** Part C called for replacing `coven_spell` and
`bastion_ramp`; the shipped build keeps all four existing keystones and adds four new RARES instead.
The reason is narrow and worth recording: those four cards work, are drafted today, and are covered
by `_probe_type_keystones` / `_probe_interest_slate` — replacing them would have churned verified
content for no player-visible gain, whereas ADDING the rare gives a committed tribe deck something
to draft toward and leaves the uncommon as the on-ramp. The doc's own rework-vs-new principle
(rework only where the old effect *is* the failing shape) is satisfied in spirit: the new rare is
the durable version and the old uncommon keeps being the cheap version.

| Tribe | New rare | Durable device | Host-authoritative home |
|---|---|---|---|
| Soldier | **The Pike Captain** (`volley`) | once-fired latch `_volley_fired[2]` | `_apply_start_round_passives` |
| Bastion | **The Siege-Bastion** (`arm_works`) | arming trick `_works_fortified[2]` | `_apply_struck_passives` |
| Warlock | **The Magister** (`arm_ledger`) | arming trick `_ledger_open[2]` | `_maybe_pay_ledger`, called from the solo cast site **and** CombatNet's host resolver |
| Beast | **The Dire Alpha** (`stampede`) | present-tense counter `_beasts_arrived_this_round[2]` | `_maybe_stampede`, beside `_maybe_beast_encore` at all three arrival sites |

**The three rules the probe enforces, because each is a way this could have shipped broken:**

- **The durable halves are NOT reset in `_start_round`.** That is the whole claim of the latch and
  the arming trick: a wipe must not un-fire a MOMENT. Only `_beasts_arrived_this_round` and the
  Ledger's once-per-round flag reset there.
- **Stampede can never reach the face.** An empty opposing column FIZZLES visibly ("NO QUARRY")
  rather than redirecting — Beasts hitting the face on their arrival round is the Beat-the-Retreat
  shape this project already rejected, and a keystone smuggling it back through a passive would be
  that rejected card with extra steps.
- **The Volley's Piercing is `temp_piercing`, a new erase order on `CreatureInstance`.** Without it
  the round-end cleanup would strip PRINTED Piercing off any Soldier the grant happened to land on —
  the Venom Tip bug, which this project has already shipped once.

**One divergence, stated rather than hidden.** Warlock OVERLOAD was specced as a re-CAST (the next
spell resolves twice). It shipped as THE LEDGER: the round's second working has every Warlock strike
whatever stands across from it. The re-cast needs the Echo denylist, the `_auto_target_for` fallback
and a recursion guard threaded through two resolvers and both net mirrors — materially riskier than
the moment is worth on its own. The four properties that made the spec good are all preserved: the
volume trigger, payment **inside the turn**, a **board** climax rather than a stat ledger, and
arming that survives the keystone's death. Only the doubling is deferred.

**Still not built from Part C:** the per-tribe common/uncommon arcs (the MOMENTS are the rares), the
deck-density commit turn-ons, the HUD "ascendant" tell (the open decision), and the SELECTION
backbone. The forge, not deck density, carries each new rare's turn-on — density is solo-only and
these had to fire in skirmish too.
