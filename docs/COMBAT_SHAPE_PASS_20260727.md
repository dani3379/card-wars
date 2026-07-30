# COMBAT SHAPE PASS — 2026-07-27

**Status: TIER 0 BUILT + TIER 1 items 6/7/8 BUILT (2026-07-27). TIERS 2–5 SPECCED, NOT
BUILT.** See §4 for what landed and what it cost. Everything still marked *(not built)* is
a build spec for whoever picks this up next.

**Two probes on this branch are ALREADY RED, independent of this pass** — both proven by
snapshot-and-hand-revert to an identical result:
- `_probe_sealed` — fails from "combat runs in the SEALED battle style" onward.
- `_probe_deck_conservation` — **`fights: 56 · FAILS: 55124 · softlocks: 56`, every single
  encounter hitting `max_rounds`.** Byte-identical before and after Tier 1. Fights are not
  terminating inside the probe's round budget; the muster delay (2026-07-21) lengthening
  every fight is the obvious suspect. **Do not use this probe as a gate until it is fixed,
  and do not read a Tier 1 regression into it.**

Produced by a four-agent audit (combat simultaneity · uncounterable damage + external
research · cost curve & tempo · enemy-as-visible-player). **Every load-bearing claim
below was independently re-verified against the code before being written down** — the
agents were wrong often enough that unverified claims were dropped. Line numbers were
accurate on 2026-07-27; re-grep before trusting one.

---

## 1 · What the owner asked for, and what it actually turned out to be

| The ask | What it really is |
|---|---|
| "too much happens at the same time" | Two frames carry ~40 events each. Not a volume problem — a **batching** problem. |
| "remove uncounterable damage" | 9 true cases, not 29. The worst offender **advertises a counter it refuses**. |
| "reduce plays per turn" | Plays are 2.7–3.0 and **flat from R1 to R6**. The problem is the *sameness*, not the count. |
| "increase card prices, 1-mana is too good" | Confirmed hard by data. A rarity floor fixes it and revives a dead mechanic. |
| "give the player a coin for going second" | **The player already goes second in every fight**, uncompensated. |
| "the enemy gets a coin too if second" | The enemy has no Command. Its coin must be paid in **bodies**. |
| "something to decide who is first" | Already exists in multiplayer. Lift it. |
| "reduce enemy keywords drastically" | **Impossible literally** — max 2, avg 0.93, 8 distinct keywords in the whole game. The real defect is *invisible* riders. |
| "enemy drags cards from hand like a player" | A port. Solo already flies the real card, from the wrong origin. |

---

## 2 · Owner decisions on record

- **The Coin is sanctioned in the campaign.** It grants Command, which crosses the
  standing `feedback_no_mana_manipulation` rule ("Command is FIXED"). The owner's ruling,
  verbatim: *"its fine since its compensation."* Treat the Coin as the explicit sanctioned
  exception; this does **not** reopen cost-reduction cards generally.
- **Scope of the toss was not pinned.** Default to **Generals and keeps only** (the
  audit's recommendation — keeps it ceremony rather than a 21-fights-a-run tax). Easy to
  widen later; confirm before widening.
- **Full alternating turns in solo: RECOMMENDED AGAINST** (see §7). Not rejected by the
  owner, but the toss + Coins delivers the stated feature without it.

---

## 3 · Verified findings

### 3.1 Pacing — the batching problem

- **`_start_round` spans `Combat.gd:3054-3427` and contains ZERO `await`s** (verified by
  script). ~40 state changes land on one frame: Regenerate/Wither/Doom ticks across all 16
  bodies, Doom detonations, Iron Rations heals, `warden_line` granting Armored+Thorns to a
  whole tribe, `bastion_ramp`, Summoner tokens, Trebuchet face damage, the encounter
  passive (which can itself deal face damage + buff + summon), Warlord's Standard, mutator
  tick, boss phase check, encounter script, 8 intent badges rewritten, ~12 relic branches.
  **Then control returns to the player.** This is the single largest contributor.
- **Deaths are deferred through the clash then flushed synchronously.** `Card2D.defer_deaths`
  is set for the Swift phase and the clash; `_cleanup_dead()` walks all 16 slots with no
  `await`, running the full 15-step `_on_card_destroyed` chain per corpse. Player sees 13
  strikes at 0.19 s each, then the entire consequence in one frame. The engine already
  knows: `_note_death` tracks `_deaths_this_frame` to coalesce the shake.
- **Feedback outlives its beat ~5×.** Keyword chip lifetime is 1.06 s (0.95 s rise + 0.40 s
  fade delayed 0.66) against a 0.19 s strike. **These are literal constants, not
  `Motion.time()`** — so they do not scale with `anim_speed`. At "Instant" (3.0×) a strike
  is 0.063 s and ~17 strikes' worth of chips are live at once. Chip de-overlap only works
  inside a 92×70 px window; floats get none.
- **Every explanatory aid is off during the clash.** Lane forecast, hover telegraph, stat
  provenance and threat outlines all gate on `phase == Phase.PLAYER_TURN and
  Card2D.board_interactive` — both flipped off at commit. The battle log drawer defaults
  **closed** (`_battle_log_open := false`). During the clash the player has floats, chips,
  and a self-clobbering caption.
- Only **one** 0.15 s pause exists in the whole of `_do_combat`.

### 3.2 Uncounterable damage

- **`structure` is invulnerable by definition** — `KeywordEffects.gd:25`:
  `"Can't be attacked or targeted by spells."` The Altar / Cauldron / Trebuchet display a
  live `CHARGE n/max` badge counting toward a face-damage overflow while being
  untouchable. **This is a fake affordance** and is the worst pattern in the inventory.
- **Structures don't even block.** `Combat.gd:~4527` treats a back-row structure as an
  empty column — the comment says so — so attackers walk past it into the player's face.
- **The fix already exists under another name.** `fortification` (`Combat.gd:15595`) is
  attackable, blocks its lane, never swings, and fires a break hook — shipped as the
  Stalwart's gate sections with `_siege_redirect_face_damage`, `_siege_check_breach` and a
  live objective plaque. The engines are simply on the wrong flag.
- **All 14 `damage_player_hero()` calls in `EncounterEffects.gd` omit the second argument**,
  so they default to `from_effect = true` (`Combat.gd:12040`). Shieldmaiden's interpose
  fires only `if not from_effect` (`Combat.gd:12061`). **The one card built to answer face
  damage is switched off against exactly the damage players resent most.**

**The researched principle** (sources in §8): players accept damage they cannot prevent
provided they own at least one of — **the trigger** (my action started it), **the target**
(my positioning chose who ate it), **the clock** (my play changed when it lands), or **the
source** (a thing on the board I could have destroyed). All 9 Class-A cases own none of the
four. Damage that offers none is a *tax*; and it is resented in exact proportion to how
loudly the game advertises a counter it does not honour.

### 3.3 Economy

203 draftable cards (curses + `coin` excluded):

```
cost 0 : 11   6%      mean printed cost 1.70
cost 1 : 72  38%      median 2
cost 2 : 77  41%      spells: 78 total, 18 at cost 0 + 43 at cost 1 = 78% cost <= 1
cost 3 : 24  13%
cost 4 :  5          only SIX cards in the entire game cost 4+
cost 5 :  1
```

Simulated plays/turn (persistent hand, refill-to-5, Command 3, bank <= 2):

| deck | plays/turn | unspent Cmd | turns with leftover |
|---|---|---|---|
| raider opener | 2.72 | 0.28 | 28% |
| acolyte / kindler opener | **3.00** | **0.00** | **0%** |
| cheap-drafted mid-run | 2.88 | 0.12 | 12% |

**Flat across the fight** (R1 2.91 → R6 2.69). With 44% of the pool at <= 1 Command,
3 Command always buys exactly 3 actions — there is no tempo arc. **Banking is dead**
(fires on 12% of turns) despite `MAX_BANKED_MANA`, a tutorial, and net mirroring.

Refill is NOT the throttle: 5→4 costs only −4% plays; 5→3 empties the hand on 54% of turns.
**Cost is the only lever that both reduces plays and creates an arc.**

### 3.4 Turn order — the player already goes second

- `Combat._ready` **awaits `_run_opening_muster()` at `Combat.gd:1186`, before the player
  may act.** The comment at `:1182-1184` states the intent: *"BEFORE the player can act, so
  round 1 is planned against a real board."* `_run_opening_muster`'s own docstring
  (`:2897`) calls the muster *"the enemy TAKING A TURN."*
- `_opening_muster_pending` (declared `:7698`, set `:2892`) is consumed inside
  `_enemy_place_creatures` (`:7723-7724`), which is reachable from **two** sites: the
  round-1 top, and `_post_combat_sequence` (`:7220`). The comment at `:7209` notes the
  second path *"never reaches here"* only because the first always fires.
  **Skipping the opening muster makes the hold form up at end of round 1 = going first.**
- **Safe by construction, and the code already argues it** (`:2884-2891`): the muster delay
  refuses every body that arrived this round, and `_creature_hits_face` separately bars
  arriving Swift from the face. An empty enemy board on round 1 grants no free face damage.
- **The Coin's solo resolver arm ALREADY EXISTS** — `Combat.gd:10240-10243`:
  `"coin": player_mana += 1`, commented *"Solo never grants it, but keep a resolver arm so
  it's never a dead card if a future effect hands it over."* It is already in `CHAOS_DENY`
  (`:2262`) so Chaos Imp can't roll it.
- Card definition: `CardDB.gd:938` — 0-cost spell, starter rarity, "Gain 1 Command this turn."
- Net toss to lift: `_net_show_order_choice` (`CombatNet.gd:374-451`) and
  `_net_play_coin_toss` (`:457`), spinning a `CoinProp` via `face_t`.
- **The enemy has no economy at all** — no `enemy_mana`, no `_enemy_hand`. Every
  `ENEMY_POOL` entry is `cost: 0` and `EncounterDB` deck entries carry no cost field.
  Its only resource is `max_place`.

### 3.5 Enemy legibility

- Across **all 646–653 enemy creature entries**: max **2** printed keywords, average
  **0.93**, **zero** with 3+. The enemy uses **8 distinct keywords in the entire game**
  (`swift` 225, `armored` 110, `piercing` 91, `thorns` 66, `regenerate` 48, `last_stand` 44,
  `doom` 12, `structure` 3). Four words are 82% of all usage. **There is nothing to cut.**
- **118 of 653 entries carry an `on_death` dict. ZERO list `"on_death"` in `kw`.**
  `EncounterDB.make_card_data:201` builds `keywords` from `kw` alone while copying
  `on_death` into a separate key — so the rail's on-death orb is **structurally incapable**
  of firing for an enemy. 18% of enemy bodies have a death trigger with no mark, no device,
  no rail entry. (Example: the act-2 Standard Bearer debuffs your whole line's ATK on death.)
- **`_has_encounter_passive_keyword` grants Piercing/Thorns/Armored by lookup at strike
  time without ever writing to `card_data.keywords`** — six passives do this
  (`dragon_lord_piercing`, `swamp_thorns`, `merc_piercing`, `stone_armor`, `nexus_rotation`,
  `stampede_charge`), so those grants can never reach the rail. `merc_piercing` is
  conditional on *live* ATK, so it appears when a neighbour lands and vanishes when that
  neighbour dies. Two passives in the same file already do it correctly by appending to
  `card_data.keywords` (`sentinel_stone`, `formation_drill` lockstep) — follow those.
- **All ATK modifiers collapse into one integer.** `Card2D.effective_atk()` sums
  `current_atk + temp_atk_buff + persistent_atk_buff + adj_atk_buff`. The decomposition
  exists (`_stat_provenance_text`) but is **hover-only and phase-gated** — unavailable
  during the clash.
- **Worked example (act-2 `mercenary_company`):** a Recruit printed **"2/3, Armored"**
  stands at **5–6 ATK** from three overlapping `adj_buff` auras and has silently gained
  **Piercing** because that total crossed 4. Printed: one keyword. Actual: two keywords —
  one invisible and *emergent* — plus four fused ATK sources.
- Status rail caps at 5 orbs and truncates silently; "mustering" competes for a slot.
  **Do not raise the cap** — that argues for replacing orbs, not adding them.

### 3.6 Enemy hand presentation

- **Skirmish already has the fan**: `_net_build_opp_hand_ui` (`CombatNet.gd:3759`),
  `_net_refresh_opp_hand` (`:3808`), `_net_make_card_back` (`:3848`). Face-down overlapping
  backs, 46×64, right-anchored at roughly x 1106–1350 / y 0–96 on the 1600×900 canvas —
  **a slot that is empty in solo**. Auto-tightening spacing, ±0.085 rad rotation about
  bottom-centre, labelled with the foe's lord name, hidden at count 0.
- **Count only, never faces.** `EV_HAND_COUNT` carries `{n, mana, maxmana}`; no identities
  cross the wire. The comment at `CombatNet.gd:229-230` claiming "open-hand / face-up" is
  **stale drift** — fix it while you're in there.
- **Solo is already 60% there.** `_place_enemy_card(data, lane, row, arc_in)` has an arc
  mode, and `_play_landing_pop` (`Combat.gd:17551`) flies the **real Card2D** (better than
  net's ghost TextureRect — no mismatch possible). Its only defect is the **origin**:
  `Vector2(slot_center.x ± 60, -170.0)` at `:7914` — cards fall out of the sky.
- `_update_reserves_chip` (`:7483`) already describes itself as *"solo's answer to
  skirmish's opponent-hand fan"*.
- **Information ruling — follow the existing precedent, don't invent one.** The standing
  rule (`feedback_enemy_is_real_opponent`) hides *arrivals*. A face-down fan leaks nothing
  new, because reserve depth is **already public** via the RESERVES chip and wave counts
  via the REINFORCEMENTS chip. So: **backs only, count only, name the holder, never faces**
  — and the fan **replaces** the RESERVES chip (a net reduction in HUD instruments).
  - Two guard rails: fan by **total reserve depth**, never by next-wave size (that would
    become an arrival preview); and draw back-to-front, pulling the flying card from the
    fan's *visual centre*, so no back's position maps to a deck index (`_enemy_deck` is
    ordered and vanguards sit at the front).

---

## 4 · Build order

### Tier 0 — defects — ✅ **BUILT 2026-07-27**

All five verified against live code before editing, then re-verified after. Parse-clean on
all five touched files; `_probe_muster_delay` 23/23; `_probe_cardhonesty` no mismatches;
`_probe_combat_telegraph` 37 pass / 2 fail — and **those 2 failures were confirmed
pre-existing** by reverting the edits and re-running to an identical result (*"Iron Bastion
reduces an open face strike by one"* and *"Virulence matches the live Shield interaction"* —
both still open, both outside this pass's blast radius, worth a look on their own).

1. ✅ **`war_cry` cost 0 → 2** (`CardDB.gd:193`). Swift is the documented exception to the
   muster delay, so a free card switched the delay off for every body just played.
   **Owner picked the reprice over the rule change**, which also lands it where Tier 3 §16
   was already sending it. Its `UPGRADES` delta is `dmg_bonus`, not `cost`, so no leak.
   It IS live in skirmish (`NET_SPELL_CUSTOMS` is an allow-list, not a denylist) — correct,
   since CombatNet routes its round starts through the same `_start_round`.
   - ⚠️ **The spec missed this and the next person must not:** `war_cry_swift` is a
     **shared flag**. The **Forlorn Hope** relic sets the same variable (`Combat.gd:~8814`)
     to grant Swift to the creature you just played, and it is cleared in end-of-round
     cleanup (`Combat.gd:~12002`). So the tempting "granted Swift no longer bypasses the
     muster delay" fix would turn that relic's headline clause into a **literal no-op** —
     granted on arrival, cleared before it could ever swing. Closing the rule itself
     requires **splitting the flag** (War Cry gets its own; Forlorn Hope keeps a bypassing
     one), which costs a `CreatureInstance` field + save/snapshot round-trip + a probe arm.
     That option is still open and unbuilt.
2. ✅ **The invisible on-death riders** (`Card2D._add_trigger_effect_entries`). Adds a rail
   mark when `card_data` has a non-empty `on_death` and `"on_death"` is not already in
   `keywords`, so the two paths can never double-stamp. Marks now carry an optional own
   `desc` — enemy `card_data.desc` is `""`, so a mark that can land on an enemy must bring
   its own text or the hover reads blank. The function's block comment used to assert
   on_death is deliberately absent because the keyword loop covers it; that is true for
   **player** cards only, and the corrected comment now explains why enemies fall through.
3. ✅ **CHARGE / GUARD intents now refresh.** Both arms in `_resolve_intents` call
   `update_stat_display()`, matching RALLY / HEAL / ENRAGE which already did.
4. ✅ **`_show_info` clobber** (`sentinel_stone`). Both effects still fire; from round 3
   they now report in **one** sentence instead of writing the same label twice in a frame.
   `dispatch_passive_start_of_round` is not a coroutine, so merging was the only fix
   available without changing its signature — the house pattern the spore/choke passive
   already uses.
5. ✅ **Stale comment** at `CombatNet.gd:~229` corrected — `EV_HAND_COUNT` carries
   `{n, mana, maxmana}`; no identities have ever crossed the wire.

### Tier 1 — pacing (the "too much at once" fix) — **6, 7, 8 BUILT 2026-07-27**

6. ~~**Break up `_start_round`.**~~ **BUILT.** `_start_round` is now a coroutine that pauses
   at three visible-group boundaries via `_round_beat()` (`ROUND_BEAT = 0.12`, anim-speed
   scaled): after the body ticks (regen / wither / doom + detonations / rations), after the
   standing rules (tribe keystones, Summoner, Trebuchet, the encounter passive), and after
   the fight-level beats (mutator, boss phase, scripted events) — so the intents the player
   plans against arrive on their own frame.
   **`_round_beat` returns SYNCHRONOUSLY when `_is_net()` or headless**, so `_start_round`
   never suspends there. That is deliberate: its two net callers
   (`CombatNet._sealed_open_orders_local`, `_net_local_turn_begin`) are plain `void`
   functions with several callers each plus Combat-side delegators, and pushing a coroutine
   through the net turn machine for a cosmetic gain is not worth the risk. **Both net call
   sites carry a comment saying so — do not add an unconditional await inside
   `_start_round`** without making that whole chain async.
   The two SOLO call sites (`_ready`, `_post_combat_sequence`) now `await`.
7. ~~**Stagger the death flush.**~~ **BUILT** — via a paced *twin*, not by changing
   `_cleanup_dead`, which has **~48 call sites** across Combat and CombatNet (many in
   non-async paths) and must stay synchronous. `_cleanup_dead_paced()` walks the board
   killing one corpse at a time with `DEATH_BEAT = 0.10` between them, then calls plain
   `_cleanup_dead()` to sweep anything that died *as a result* (an on_death that killed a
   neighbour) — cheap, idempotent, and it preserves the invariant that no 0-HP body
   survives the call. **No beat before the first corpse**, so a one-death clash is
   unchanged. Used by exactly the three flushes inside `_do_combat`; bails to the plain
   function in net/headless.
8. ~~**Make chip/float lifetimes scale.**~~ **BUILT (chips only — floats were already
   correct).** `spawn_floating_number` already used `UserSettings.anim_time(...)`; only
   `spawn_keyword_callout`'s four durations were literal. Now on `Motion.time()`.
9. **Give the clash phase boundaries.** Nine sub-phases run with only five captioned and
   one 0.15 s pause total. *(not built)*
10. *(Consider)* Let the stat-provenance readout survive into the clash — it is gated off
    precisely when the numbers move.

### Tier 2 — the toss + both Coins (the owner's headline feature)

11. Lift `_net_play_coin_toss` (`CombatNet.gd:457`) into a **shared** helper so solo and
    net do not fork.
12. Before round 1 on **Generals and keeps**, offer the choice:
    - **TAKE THE FIELD** — defer `_opening_muster_pending`; player deploys into an empty
      field; the hold musters at end of round 1 **with its Coin: `starting_count + 1`** in
      `_deal_opening_muster` (`Combat.gd:~2947-2957`).
    - **LET THEM COMMIT** — today's behaviour, **plus** `_draw_card("coin")` for the player.
13. Headless/probe bail to today's path (`DisplayServer.get_name() == "headless"`), matching
    `CombatNet.gd:265-266`.
14. Check the Coin does not collide with `HAND_REFILL_TARGET` at `MAX_HAND_SIZE`.

### Tier 3 — the reprice — **PARTIALLY BUILT 2026-07-27 (27 cards)**

**Owner steer that overrode the blanket floor**, verbatim: *"dont make every single card a
2 cost+ but the majority should be or if its 1 cost it should be obviously weaker."* So the
uncommon floor was **deliberately NOT applied wholesale** — 22 uncommons and 3 rares remain
at cost 1 on purpose. A real 1-cost tier survives; it just has to read as weak.

**Curve now: `0:6 · 1:77 · 2:94 · 3:25 · 4:5 · 5:1`, mean 1.75, and 60.1% of the pool sits
at 2+** (was 46.6% at <=1; now 39.9%). Majority-at-2+ achieved without flattening.

Built:
- **Zero-cost purge (10)** — `provision` `shove` `gambit` `blood_tithe` `quick_shot`
  `frost_bolt` `adrenaline` `soul_swap` 0->1; `offering` `dark_pact` 0->2. (`war_cry` had
  already gone 0->2 in Tier 0.) `spark` stays 0 — starter rarity, exempt by contract.
  None of the ten had a cost-reducing UPGRADES entry, so nothing leaked back out.
- **Worst individual mis-prices (11)** 1->2 — `petard` `concentrate` `sword_on_credit`
  `pressed_man` `banish` `holy_smite` `mass_grave` `plague_bell` `scavenger` `grave_levy`
  `chaos_imp`. Note this incidentally CLOSED the `holy_smite` leak: its `cost:-1` upgrade
  used to make the "+" free and now lands at 1.
- **"Obviously weaker" pass on the 1-cost tier (6)** — the interesting-design half, using
  `tools/_probe_curve.gd`'s stat-budget flags rather than taste. One concept per card:
  `plague_rat` lost Lifesteal (keeps Poison, its name-concept); `warding_stone` lost Thorns
  (keeps Guardian + its Bastion on-enter); `torchbearer` lost Formation (keeps the adj_buff
  it is named for); `bramble_stockade` lost Guardian (keeps Thorns + the 2026-07-15
  `anvil_spawn` interest); `hexblade` lost Sniper (keeps the spell-scaling passive);
  `vengeance` lost Overrun (keeps `vengeance_growth`).
  **Result: every one dropped from over=+2/+3 to over=+1** — level with the ordinary
  baseline one-drops (`gravedigger`, `mule`, `ironhide_anvil`) — and nothing at cost 1
  exceeds +1 any more. `_probe_cardhonesty` reports zero mismatches after the desc rewrites.

- **THE OPENING DECKS (all 10) — the owner identified this as the main problem, and the
  audit had flagged it as the blind spot the starter contract shields.** Measured before
  the fix: **two decks were 10/10 at cost 1** (Grass Levies, The Second Funeral), Acolyte
  was 9/10, both Kindler decks 8/10. With Command 3, a deck of all 1-costs means the player
  makes the same three plays every turn forever, with no sequencing decision — and it is
  the FIRST thing a new player experiences.
  Fixed by changing the **ratio of cards each hero already runs**, never by introducing a
  new card, so identity is untouched and the STARTER CONTRACT still holds (verified: every
  id in every deck is starter-rarity, plus Kindler's four sanctioned doom commons).
  Raider −1 goblin +1 brute · Grass Levies −1 goblin −1 strike +2 brute · Stalwart
  −1 levy_rider +1 troll (also a better thematic fit — it is a Raider card in a wall deck) ·
  Acolyte −2 goblin +2 brute (goblin was generic filler; ratlings + mourners are the
  identity) · Second Funeral −2 goblin +2 brute · Mirror Line −1 spark +1 troll (still 3
  sparks vs the base deck's 2, so "more sparks than steel" holds) · Kindler −1 ash_hound
  +1 burning_martyr · Powder Cart −1 kindling +1 burning_martyr.

  | deck | before | after |
  |---|---|---|
  | Raider | 1.40 · 7/10 | **1.50 · 6/10** |
  | Grass Levies | **1.00 · 10/10** | **1.20 · 8/10** |
  | Stalwart | 1.40 · 7/10 | **1.50 · 6/10** |
  | Old Legion | 1.60 · 6/10 | unchanged (already the best curve) |
  | Acolyte | 1.10 · 9/10 | **1.30 · 7/10** |
  | Second Funeral | **1.00 · 10/10** | **1.20 · 8/10** |
  | Pyromancer | 1.30 · 6/10 | unchanged (best of the mains) |
  | Mirror Line | 1.00 · 7/10 | **1.20 · 6/10** |
  | Kindler | 1.20 · 8/10 | **1.30 · 7/10** |
  | Powder Cart | 1.20 · 8/10 | **1.30 · 7/10** |

  **No deck is flat any more** — every one now carries at least three cards at 2+. All ten
  are still exactly 10 cards.

Still unbuilt from this tier: the remaining floor candidates (deliberately deferred — see
the steer above), `flame_bolt`'s re-conception, the Discover -2 -> -1 change, the shop
`SELL_PER_COST` adjustment, `marathoners_sash`'s round-1 ramp, and the cost-discount relic
pass (`tricksters_glove` first — it can still revert the whole reprice for its owner).

### Tier 3 — the reprice (original spec)

15. **Rarity floor**: common >= 1, uncommon >= 2, rare >= 2, **starters exempt** (the
    STARTER CONTRACT is working correctly — fast opener, weightier drafted deck).
    Moves **43 cards**: mean 1.70 → 1.94, plays 2.88 → 2.34 (−19%), banking 12% → **44%**.
16. **The zero-cost purge first** (highest felt effect per edit): `war_cry`, `provision`,
    `quick_shot`, `frost_bolt`, `gambit`, `blood_tithe`, `shove`, `soul_swap`, `adrenaline`,
    plus `dark_pact` / `offering` (0 → 2 — "free + a sacrifice-trigger web" is not a cost).
17. Then the 30 uncommons, then the 4 rares (`concentrate`, `long_roll`, `muster_fallen`,
    `unholy_bargain`).
18. **Worst individual mis-prices** beyond the floor: `petard` (5 dmg + 2 splash for 1 —
    doing `ballista_bolt`'s job at half price), `concentrate` (4 + 4 face for 1, at rare),
    `sword_on_credit` (3/5 for 1), `pressed_man` (3/3 for 1), `banish`, `holy_smite`,
    `grave_levy` (2/2 **Charge** for 1 — Charge reaches the face on arrival), `scavenger`.
19. **Prefer re-conception over re-pricing** where a card is only good because it is cheap.
    Example: keep `flame_bolt` at 1 but make its payoff **board-conditional** rather than
    sequence-conditional, per the design note already written above `fireball`.

### Tier 4 — uncounterable damage

20. **Promote the charge-engines from `structure` to attackable.** Lower-risk first pass:
    add `attackable: true` and gate only the targeting/attack filters on it — **do NOT swap
    the keyword**, because the tick handlers look objects up **by name** through
    `_all_structures()` and would silently break.
21. **Flip `from_effect` to `false`** for passive damage that is physically a body hitting
    you (tremor, trebuchet, choir, axe, `pyre_spread`). Leave fate as fate (curse-lash, hex,
    Doom). Removes no damage; gives Shieldmaiden and Portcullis a job.
22. **Give the flat-clock passives a body** (`devil_cycle`, `iron_warden_siege`,
    `sentinel_stone`, `court_wither`) using the `doom_bell` pattern — a real creature with a
    visible fuse you can kill.
23. **`void_exile` must at minimum SHOW the card it deletes** (6 encounters, currently
    silent) — invisible loss is the purest black box.
24. **`forge_heat`**: drop `take_damage_bypass_armor`, make it front-row-only. Positioning
    becomes the counter and Armored gets its job back; precedent already exists in
    `_mutator_round_start_tick`'s front-row burn.
25. **Retire `bandit_mana_steal`** — contradicts the fixed-Command doctrine, one encounter.

### Tier 5 — the enemy hand

26. Add `Motion.flip_reveal(wrapper, on_half)` — lift the flip from `Event.gd:~3581-3606`
    and refactor `_play_wet_deal` to use it.
27. **Promote the fan out of `CombatNet` into `Combat`**, leaving same-name delegators
    behind (the inverse of the 2026-07-14 restructure, and correct here because **solo must
    not depend on the net layer**). Contract: state on `Combat`, delegator per function.
28. Drive the fan from `_enemy_deck.size()` in solo; **retire `_reserves_chip`**.
29. **Re-origin the arc**: pass the fan's global centre instead of `(slot.x ± 60, -170)`.
    One line, immediately visible.
30. Face-down back overlay + flip at t=0.10 (overlaps the existing 0.34 s flight).
31. **Re-anchor `_reveal_cast_card` to the fan** and shorten its hold 0.95 → ~0.55 s.
    This is a **−1.2 s subtraction** on a 3-body act-2 muster while being *more* legible —
    the fan work costs only ~0.05 s/body, so pacing improves overall.
32. Close the client asymmetry: today only the host sees the foe's card fly
    (`_net_apply_remote_creature`); the client gets pop-in via `EV_BOARD_SYNC`.

---

## 5 · Traps

- **`_place_enemy_card` must stay synchronous.** It calls `_play_landing_pop` *without*
  awaiting, deliberately (`:7906-7908`) — the card is already seated so combat logic never
  waits on the flight. There are **16 call sites**, several inside non-async static
  dispatchers in `KeywordEffects` / `EncounterEffects`. Making it a coroutine breaks them
  silently. **Seat synchronously, fly fire-and-forget.** Solo's order is safer than net's
  (which awaits before seating); if unifying, unify on solo's.
- **Only 3 of 16 `_place_enemy_card` sites pass `arc_in = true`.** Encode **provenance**,
  not a new call site: bodies from the hold's reserves fly from the fan; bodies *conjured*
  on the field (lich, wraiths, Cinders, tokens, boss transitions) keep the drop-in. A
  summoned body was never in anyone's hand.
- **Cost-discount relics are an unacknowledged second source of spam** and would revert the
  whole reprice. `_effective_cost` stacks 13 modifiers; **`tricksters_glove` (hand >= 4 →
  every card −1)** single-handedly returns a 2-centred pool to 1-centred for its owner. The
  "Command is FIXED" rule is honoured on cards and quietly broken on relics.
- **`CardDB.UPGRADES` leaks the reprice back out.** 15 entries reduce cost by 1, and **nine
  of them are 1-cost cards whose "+" makes them FREE**. After the floor, re-check each;
  prefer swapping `cost:-1` deltas for a stat/value bump.
- **Discover discounts by 2** (`_add_discovered_card_to_hand`) — hands out free cards in a
  2-centred pool. Change to −1.
- **The sutler's buy-back is cost-keyed** (`SELL_BASE 10` + `SELL_PER_COST 8`): repricing up
  raises what he pays for the cards you want to dump. Consider `SELL_PER_COST = 6`.
- **`marathoners_sash`** ramps round 1 to `player_mana = 1` — in a 2-centred pool turn 1
  buys **nothing**. Give it 2 on round 1.
- **Do not also cut the refill target.** Sim says +1% of a play for a permanently smaller
  choice set; the persistent hand is the game's best texture and the reprice makes it
  *more* meaningful.
- **`_muster_rushed`** must gate the flip/lift, or a rushing player freezes a card mid-turn.
- **Chaos Imp's roll pool is `cost <= 1`** — the reprice shrinks it ~60 → ~35. Intended, but
  verify it does not feel repetitive.
- **The acolyte and kindler openers are the spammiest decks in the game** (9–10 cards at
  cost 1, 3.00 plays/turn, 0.00 unspent forever) and are **exempt from every fix above** by
  the starter contract. One 2-drop each would give them an arc without touching the contract.

---

## 5b · The measurement path — `tools/_probe_runsim.gd` (BUILT 2026-07-27)

**Why it exists.** `_probe_balance` calls `start_new_run` **per fight**, so every
encounter is measured at full HP with a bare 10-card starter deck, no relics, no
upgrades and no accumulated damage. Its own header calls that a FLOOR. It is the right
tool for spotting one overtuned encounter and the WRONG tool for "did my balance change
help?", because nothing it measures resembles the state a player is actually in — which
is why ~60 content edits could land this session with no way to check them.

`_probe_runsim.gd` carries a run FORWARD the way the campaign does:
- **ONE `start_new_run` per run.** HP persists between fights (Combat writes
  `RunState.hero_hp` back at `:14089`). This is the single biggest realism gap it closes.
- The real act skeleton: **7 fights per act** — 4 holds, 2 Generals, 1 boss.
- `current_act_idx` set per act, so act-2/3 kits fight at full strength.
- **The deck grows** — a reward after every fight from the live
  `CardDB.roll_card_reward` tables for that act/tier (takes the priciest offer as a
  stand-in for drafting for impact; MODAL_BLOCKLIST ids are never drafted, or the deck
  fills with cards the bot refuses to cast).
- **Relics accumulate** on Generals and bosses via `RelicDB.roll_relic_reward`.
- A camp heal before the keep, like `REST_ROW`.
- Reports: runs won, avg fights survived (21 = a full run), final deck size, and
  **deaths by act**.

`--runs=N --hero=X --asc=N`. Writes RunState — back up `user://run_0.save`.

**It is still a FLOOR** (the bot never banks Command, never repositions, never plays a
modal card) — so read DELTAS before/after a change, never absolutes.

### Two traps this cost, both worth knowing

1. **`phase == Phase.PLAYER_TURN` is NOT a readiness test.** `PLAYER_TURN` is enum value
   **0** and the member's default, so it reads true on the first tick — before
   `_build_hud` has run. The first version of this probe therefore assigned
   `_end_turn_btn.disabled` on `null` every round. Gate on **`round_number >= 1`**, which
   only becomes true inside `_start_round`, strictly after the HUD exists. This has now
   bitten twice (also in `_probe_boss_phase_plaque`). **`_probe_balance` and
   `_probe_autorun` both still carry the unguarded version** — latent, worth fixing.
2. **`_play_creature(card, cost)` is not the drop handler.** It takes two args and
   assumes the card is already positioned. The bot must set
   `card.global_position` over an empty SLOT NODE (`_slot_array`, not `_row_array`) and
   call `_on_card_played(card)`. Calling `_play_creature` directly made the first bot
   field nothing and lose every fight in two rounds.

## 6 · Verification

Run in this order; treat **deltas, not absolutes**:

`_probe_curve` (its budget table gives a card moving 1→2 a *higher* stat ceiling, so
existing flags may clear — that is intended) · `_probe_cardhonesty` · `_probe_card_randomness`
· `_probe_cardpower` (**saturated** — detects only |lift| > 5) · `_probe_balance --draft` ·
`_probe_autorun` (**clobbers `run_0.save` — back it up**) · `_probe_vsbot` and
`_probe_skirmish_combat` for the net side · `_probe_muster_delay` (23 checks) and
`_probe_combat_telegraph` (37 checks — **was previously blinded by the muster delay**; if
you change what the enemy shows on arrival, confirm it still has teeth) · `_probe_creature_fx`
· `_shot_battle_log.tscn` for the rail work · `_probe_copy_lint` + `_probe_text_floor` after
any desc rewrite.

**Standing caveat:** probes never set `current_act_idx`, so all historical balance numbers
read ~2× too easy (`project_overwhelm_audit_20260726`). Fix that before trusting a
before/after.

A read-only stats dump used to produce §3.3 and §3.5 lives at
`tools/_probe_combat_shape.gd` — re-run it after the reprice to confirm the curve moved.

---

## 7 · Recommended AGAINST: full alternating turns in solo

Porting `STYLE_ALTERNATING` into the campaign is not a port, it is a new game mode:

- **~330 authored enemy entries need Command costs** (55 encounters × ~6 bodies, all
  `cost: 0` today, plus `ENEMY_POOL`, reinforcements, and every set-piece `opening`).
- **`EncounterDB`'s identity dissolves.** Its lineups are *ordered scripts* with fight
  passives, `REACTIVE_PASSIVES`, faction wave schedules, pursuit outriders and boss phase
  forcing — all deployment scheduling. Under a Command economy the hold stops being an
  authored fight and becomes a bot with a deck, which is what skirmish already is.
- `_do_combat` would have to become one-directional; `_net_run_clash` is `_is_host()`-gated
  throughout and lives in CombatNet.
- **The intent system (58 references) loses its meaning** — intents telegraph what the
  enemy does *in the shared clash*.
- The muster delay was tuned against the simultaneous clash (21W/35L → 19W/37L over 56
  fights). Alternation changes what a round of delay costs each side.

**The toss + both Coins (§4 Tier 2) delivers everything the owner asked for in words on the
structure that already exists.** If the alternating campaign is genuinely wanted later, the
right vehicle is a run modifier / ascension rule or a separate "Duel" mode over
`SkirmishBot` — not a rewrite of the campaign engine.

---

## 8 · Sources for the counterplay principle (§3.2)

- Random Seed Games — *Solving "Feels Bad" Moments in Tabletop Game Design*
  (<https://randomseedgames.com/blog/2025/11/25/solving-feels-bad-moments-in-tabletop-game-design>).
  *"Power is fun. Surprise can be fun. But helplessness never is."*
- The Law of Game Design — *What is counterplay?*
  (<https://lawofgamedesign.com/2014/01/31/theory-what-is-counterplay/>) — counterplay
  includes **mitigation** and **prediction**, not just negation.
- Jeremiah Franczyk — *Perfect Information*
  (<https://jeremiahgames.com/2019/03/04/perfect-information-the-killer-feature-of-slay-the-spire-and-into-the-breach/>)
  — telegraphs shift failure from *I guessed wrong* to *my strategy was wrong*.
- Philipp Stenger — *Creating counterplay in a turn-based environment*
  (<https://philippstenger.com/research/creating-counterplay-in-a-turn-based-environment/>)
  — telegraph via **mandatory setup**, not text. An object with a charge counter IS the
  setup turn.
- Game Developer — *How Subset Games designed Into the Breach*
  (<https://www.gamedeveloper.com/design/video-how-subset-games-designed-i-into-the-breach-i->).
- **Wildfrost** is the closest model to this architecture: every unit acts on a visible
  countdown that is not merely readable but **pushable**. That is the upgrade over Slay the
  Spire's intents — StS lets you plan around the number, Wildfrost lets you change it.
