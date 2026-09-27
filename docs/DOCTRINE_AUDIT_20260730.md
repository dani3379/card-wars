# WAR_DOCTRINES audit — 2026-07-30 rung-3 veterancy table

Audit of `Combat.WAR_DOCTRINES` (`scripts/scenes/Combat.gd`), the 10-kill veterancy
reward: a deck creature permanently gains ONE chosen keyword from its own tribe's pair.
Shipped 2026-07-30, never playtested.

| tribe | option A | option B |
|---|---|---|
| soldier | formation | guardian |
| beast | charge | overrun |
| dead | last_stand | lifelink |
| warlock | piercing | poison |
| bastion | regenerate | guardian |
| stray | sniper | rampage |

## Findings so far

---

## Q1 — Is `sniper` safe to grant to an arbitrary creature?

**Severity: BROKEN (as presented) / NEEDS PLAYTEST (as balance).**

### The mechanic, verified

- `scripts/scenes/Combat.gd:5126` — `_resolve_column_attack` returns early on
  `_is_sniper(attacker, is_enemy, row)`. **The sniper does not swing in the clash at
  all.** Same guard mirrored in `_lane_will_strike` (`Combat.gd:5083`), so the lane
  isn't even given a dwell beat.
- `Combat.gd:6660` — the ranged phase only runs bodies that pass `_is_sniper`.
- `Combat.gd:6681` — `_is_sniper` is `card.has_keyword("sniper")`, so the doctrine
  grant (which appends to `card_data.keywords`, `Combat.gd:15998`) **is** live wiring.
  The grant functions; the problem is what it does.
- `Combat.gd:6865-6867` — only the OPENING shot obeys a Take-Aim mark; every later
  shot is `_sniper_pick_lowest`, i.e. the lowest-HP living enemy anywhere on the
  board, front row preferred on ties (`Combat.gd:6820-6833`).
- `Combat.gd:6869-6882` — **face damage only when `target == null`**, i.e. only when
  the ENTIRE enemy board is empty, and only on shot 0.

### Is it a nerf on a body that is already trading well? Yes, in two concrete ways.

1. **It cannot finish the body that is hitting it.** A high-ATK front-line Stray
   currently kills the enemy standing opposite; after the grant it shoots the
   weakest thing on the board instead, and the body opposite keeps chewing on it
   every round, untouched. Take Aim mitigates this — the mark persists round to
   round (`Combat.gd:6694-6696`) — but it is a manual drag the player must redo
   **every fight**, and it only steers shot 0.
2. **It stops pushing face damage.** This is the clean, common downgrade. A normal
   attacker with an empty opposing column hits the hero. A sniper in that exact
   position redirects into whatever chaff is standing in some other lane
   (`Combat.gd:6866-6867` runs before the face branch can ever be reached). In a
   race — the situation a big Stray veteran is usually in — the grant silently
   converts reach damage into overkill on a 1-HP token.

Counterweight: the kill-chain (up to 8 shots, `Combat.gd:6859`) with ATK recomputed
per shot is genuinely strong on a wide, softened board, and overkill still carries
(`_apply_piercing_overflow`, `Combat.gd:6914`). Against a wide chaff line it is a
big upgrade; against one fat threat or an open lane it is a downgrade. That is a
real decision — but only if the player can see it.

### Would the player understand? No.

`scripts/data/KeywordEffects.gd:14` is the ONLY text shown — `_doctrine_overlay`
prints the keyword's `desc` verbatim (`Combat.gd:16058-16063`):

> "After the clash, attacks a chosen enemy. Drag it onto a target; otherwise it
> attacks the weakest. It attacks again after each kill."

"**After** the clash" reads as *in addition to* the clash. Nothing in that string
says the body forfeits its column attack, and nothing says it can no longer reach
the face. A player picking THE CHOSEN MARK for their 8-ATK veteran is being shown
text that describes a strictly-additive keyword and handed a substitutive one.

### Recommendation

1. **Fix the copy first** (this is the actual bug, and it is cheap):
   `"Does not fight its column. After the clash it strikes a chosen enemy instead —
   drag it onto a target, else it strikes the weakest — and strikes again after
   each kill."` This also fixes the printed keyword everywhere else it appears, not
   just the doctrine modal.
2. Consider letting a sniper whose aimed quarry is dead **and** whose opposing
   column is empty carry to the face on shot 0 (a one-line reorder at
   `Combat.gd:6866`) — the current rule makes the marksman worse at the one thing
   a marksman should be good at.
3. Do not remove it from the Stray pair; once worded honestly it is the most
   interesting doctrine in the table.

---

## Q2 — Is any other doctrine a trap or a no-op?

### The gate that saves most of the table (and breaks one tribe)

There is exactly ONE `record_kill` call site in the whole project:
`Combat.gd:6034`, inside `_apply_combat_strike_riders`, guarded by
`defender_was_killed and not attacker_is_enemy and not attacker.is_token and
attacker.deck_uid >= 0`. **A creature banks a kill only by personally landing a
killing blow with a strike.** Thorns, reflect_strike, on-death bursts, Doom
detonations and spell damage credit nobody.

Consequence: the "blank on a 0-ATK wall" family of worries is mostly impossible —
a 0-ATK body can never reach 10 kills, so `lifelink`, `piercing`, `poison` and
`rampage` can never be offered to a body that deals no damage. Good accident.

**But the same gate breaks the Bastion tribe outright. Severity: BROKEN (unreachable
reward).** Bastion is the walls tribe, and most of the printed pool has `atk: 0`:
`warding_stone` 0/3 (`CardDB.gd:175`), `ironhide_anvil` 0/3 (`CardDB.gd:213`),
`bramble_stockade` 0/3 (`CardDB.gd:222`), `trebuchet` 0/6 (`CardDB.gd:829`),
`rolling_tower` 0/7 (`CardDB.gd:1003`), `marker_stone` 0/4 (`CardDB.gd:83`). These
bodies cannot bank a single kill, so **the pair that is best on them
(regenerate / guardian — both purely defensive) is the pair they can never earn**,
while the bodies that *can* earn it are the rare ATK-bearing Bastions for whom two
defensive keywords are the least useful thing on the table. The tribe's reward is
inverted relative to the tribe's identity.
Recommendation: either give Bastion an offensive option (`thorns` is taken by the
war school; `piercing` or `formation` would fit siegeworks), or credit a kill from
`reflect_strike` / Thorns damage so walls can actually become veterans — the second
is the better fix and would also make Iron Rampart's whole design pay off.

### Persistence checked

The `doctrine` mod path folds in `RunState._apply_upgrade` (`RunState.gd:1034`,
beside `war_school` at :1025), so the grant survives the fight and the save. Not a
no-op. Both bare grants that need a value field default correctly:
`formation` reads `card_data.get("formation", 1)` (`KeywordEffects.gd:405`) and
`rampage` reads `card_data.get("rampage", 1)` (`Combat.gd:5982`), so a keyword
appended with no companion number still ticks at 1. That was the likeliest silent
no-op in the table and it is clean.

### Per-option verdicts (bodies that CAN qualify)

| # | doctrine | verdict | evidence |
|---|---|---|---|
| 1 | soldier `formation` | **FINE** | `KeywordEffects.gd:401-410`. +1/+1 banked per round while a friendly stands in the SAME ROW, adjacent column (narrower than the project's usual adjacency — no column-mate). Blank only if you park it alone in a row, which is player-controlled. |
| 2 | soldier `guardian` | **NEEDS PLAYTEST** | `Combat.gd:6626-6632`. Never blank, but it is a hidden *cost*: your 10-kill veteran now eats up to three neighbours' blows, and the modal text never says so. |
| 3 | beast `charge` | **FINE** | `Card2D.gd:711-713`. Bypasses the muster delay and may reach the face on arrival. Unconditional, always worth something. |
| 4 | beast `overrun` | **NEEDS PLAYTEST (near-trap)** | `KeywordEffects.gd:383-390`. +1 ATK *this round* and only while the opposing FRONT lane of its column is empty. A beast that banked 10 kills is a front-line brawler with a body re-seated opposite it every round, so the condition is usually false — and on the rounds it IS true the beast is already swinging at the face, where +1 is noise. Temp buff, cleared in upkeep. |
| 5 | dead `last_stand` | **FINE** | Unconditional single-use save. |
| 6 | dead `lifelink` | **FINE, with a blank window** | `Combat.gd:5970` — gated on `player_hp < player_max_hp`. Heals the HERO, not the creature, and does literally nothing while you are at full HP. Situational rather than dead; the printed desc is honest. |
| 7 | warlock `piercing` | **FINE** | Needs a kill to overflow; a 10-kill veteran kills by definition. |
| 8 | warlock `poison` | **FINE (arguably too good — see Q5)** | `KeywordEffects.gd:22` — anything it damages dies regardless of HP. |
| 9 | bastion `regenerate` | **FINE but tiny** | `KeywordEffects.gd:315-317`, 1 HP/round capped at max. Never blank; rarely decisive. |
| 10 | bastion `guardian` | **see Q3** | Frequently already printed on Bastions, collapsing the rung to one tile. |
| 11 | stray `sniper` | **see Q1** | Substitutive, not additive. |
| 12 | stray `rampage` | **FINE** | `Combat.gd:5981-5987`, fires in the same function that banks the kill — a body that earned this rung is a repeat killer by construction, so the payoff is guaranteed. |

**Answer to "is any of the 12 strictly useless on a plausible pool creature":**
after the kill gate, only two come close — `overrun` (blank on exactly the
front-line beast that earns it) and `lifelink` (blank at full HP). Neither is a
hard zero. The real NO-DEAD-REWARDS violation is structural, not per-keyword: the
Bastion pair is unreachable by most of the Bastion pool.

 the soldier and bastion pair a problem?

**Severity: FINE as a duplicate. NEEDS PLAYTEST for one side effect.**

### What guardian actually does here

`Combat.gd:6626-6632` — the defender-substitution hook: when a blow is aimed at a
body, the game walks `_adjacent_creatures(defender_is_enemy, row, lane_idx)` and if
any living neighbour `has_keyword("guardian")`, **that neighbour is struck
instead**. It is a redirect-onto-me, not MTG's "attackers must be blocked". Note
"adjacent" in this project is row ±1 *plus* the column-mate, so a guardian covers
up to three neighbours, not two — the printed text
(`KeywordEffects.gd:24`, "Enemies to its left and right must attack this creature")
under-describes it and is also worded from the wrong side (nothing is compelled;
the blow is rerouted).

### Is the duplicate a problem? No.

It is the same keyword id and the same single implementation, so there is no
divergence risk. The design note at `Combat.gd:15887-15890` pre-justifies it, and
the justification holds: the pairs are still distinct *as pairs*
(formation/guardian = grow-or-shelter; regenerate/guardian = endure-or-shelter).
Six tribes × 2 slots over a 14-entry `DEFECTION_STEALABLE` list (`Combat.gd:6071`)
means one repeat is unavoidable, and guardian is the right one to repeat — it is
the only listed keyword that is purely about protecting *other* bodies.

### The real problem in this pair is not the duplicate — it is redundancy with the
### printed pool.

Guardian is the single most commonly PRINTED keyword across exactly these two
tribes: `palisade` (0/4 soldier starter, prints Guardian, `CardDB.gd:59`),
`warding_stone` (0/3 bastion, `CardDB.gd:175`), `ironhide_anvil` / Iron Rampart
(0/3 bastion, `CardDB.gd:213`), and `bramble_stockade` **gains** guardian from its
"+" forge (`CardDB.gd:1226`). `_offer_doctrine` filters options the card already
carries (`Combat.gd:15973-15977`), so for any of those the rung silently collapses
to a **one-button modal** — a screen that says "Choose the Bastion doctrine" and
offers exactly one thing. That is not a crash and not a dead reward, but it is a
fake choice presented as a real one.

### Recommendation

1. Keep the duplicate.
2. Fix `KeywordEffects.gd:24` to describe the actual rule: *"Blows aimed at
   adjacent friendlies hit this instead."*
3. When `options.size() == 1`, either re-title the modal ("THE ONLY LESSON LEFT")
   or backfill the empty slot from `WAR_SCHOOLS` minus the card's existing
   keywords, so the rung never renders as a single tile.

---

### Bonus (found in passing, same area)

`Combat.gd:5126` returns **before** the `attacks_all_lanes` / `charges_this_turn`
branch at `Combat.gd:5137`. Granting sniper to a body that has, or is given, the
all-lanes strike silently switches that strike off. No pool Stray has that passive
today, but the Charge! meta-rider (`state.charges_this_turn`) is available to any
body — a sniper veteran cannot benefit from it.

---

## Q4 — Stacking

### The headline: SWIFT SILENTLY EATS SNIPER. Severity: BROKEN.

`_resolve_swift_attack` (`Combat.gd:5221-5252`) has **no `_is_sniper` guard**. The
sequence for a body carrying both:

1. Swift pre-phase: `_is_swift_attacker(card)` passes (`Combat.gd:6638-6640` —
   printed swift, `state.war_cry_swift`, or `state.drummer_swift`), so the body
   makes an ordinary COLUMN attack and `has_attacked_this_turn = true`
   (`Combat.gd:5250` — set unconditionally, before the reach check at :5251).
2. Clash: `_resolve_column_attack` returns at the `has_attacked_this_turn` guard
   (`Combat.gd:5116`).
3. Ranged phase: `_resolve_ranged_attacks` skips it at
   `if card.has_attacked_this_turn ... continue` (`Combat.gd:6662`).

**The snipe never fires.** And this is not an exotic pairing — it is the two rungs
of the same ladder on the same card: the war school at 3 kills offers
Armored/**Swift**/Thorns, and the Stray doctrine at 10 kills offers **Sniper**. A
player who took Swift for their aggressive Stray at kill 3 and THE CHOSEN MARK at
kill 10 has bought a 100% dead reward, with no message and no visible difference.

The same collision reaches beyond the doctrine table:
- A Battle Drummer beside any sniper (`state.drummer_swift`) **switches that
  sniper off** for the round, including printed-Sniper pool cards and every body
  the `catapult_crew` relic makes a sniper (`Combat.gd:6685`).
- War Cry, which grants Swift to the whole line, disables every friendly sniper
  the round it is played.
- The Cerecloth relic can copy both `swift` and `sniper` off one corpse
  (`Combat.gd:10603-10605`).

Recommendation: add `if _is_sniper(card, is_enemy, row): return` at the top of
`_resolve_swift_attack` (sniper wins — it is the rarer, more specific rule), OR
exclude sniper from `_is_swift_attacker`. Either way `tools/_probe_progression.gd`
should gain a case asserting a swift+sniper body fires exactly one shot, in the
ranged phase. This is the one item in this audit I would fix before any playtest,
because it makes the playtest data on the Stray pair meaningless.

### The worst realistic stack

One card can legitimately carry: printed keywords + `plus` forge + veteran +1/+1
at 6 kills + war school + doctrine + `drill` stacks + a transferred `grant_kw`
banner, all folded by `RunState._apply_upgrade`.

**Worst realistic (and genuinely degenerate): a Warlock with Swift (war school) +
Poison (doctrine).** Swift strikes in the pre-phase, before the enemy clash
(`Combat.gd:5221`); Poison kills anything it damages regardless of HP
(`KeywordEffects.gd:22`). The result is a **free, uncounterable kill every single
round, taken before the enemy is allowed to swing** — the victim is dead before
the clash, so the veteran takes no return damage. Stack drill passes and Armored
under it and the body is also hard to remove. This deletes the General/boss
answer-card problem entirely: fat HP is irrelevant to poison, and going first is
irrelevant when you strike in the pre-phase.
Verdict: **degenerate, but only mildly doctrine's fault** — Swift-plus-Poison would
be broken on any printed card; the doctrine rung is what makes it *assemblable on
demand* from a single veteran with no draft luck.

**Worst realistic in the Stray line:** `free_lance` (stray, cost 2, 2/3,
`CardDB.gd:85`) → +1/+1 at 6 kills → drill stacks → `plus` forge → ~5/6, war
school Armored, doctrine Rampage, banner Piercing. With a Free Company Captain on
board its `defection` also loots a keyword off every corpse it kills, so the
rampage chain writes its own upgrades. Strong, but it needs a long run and two
specific waysides — I would call this a fair top-end, not degenerate.

Everything else stacks additively and boringly. The doctrine is one keyword on one
card; the ceiling problems in this list belong to `defection` and to Poison, not to
the table.

---

## Q5 — Are the pairs genuinely a choice?

| tribe | verdict | why |
|---|---|---|
| soldier | **LEANS HARD to formation. NEEDS PLAYTEST.** | Formation banks +1/+1 *every round* (`KeywordEffects.gd:401-410`) and a 10-kill veteran is by definition a body that survives rounds — note the code's own comment at :399-400 says formation "never actually snowballs" because creatures die too fast, which is exactly the assumption a veteran breaks. Guardian by contrast *shortens* the veteran's life by pulling its neighbours' blows onto it. Real, but lopsided. |
| beast | **FAKE CHOICE.** | Charge is unconditional, permanent, and adds a whole round of attacking per deployment; overrun is +1 ATK, temporary, and only when the lane across is empty. There is no board state where a player who understands both picks overrun. |
| dead | **GENUINE. FINE.** | last_stand (keep the body) vs lifelink (convert its damage into hero HP) answer different problems and swap places depending on run HP. The best pair in the table. |
| warlock | **GENUINE. FINE.** | Poison deletes fat single threats; piercing converts overkill into face damage and wins races. Mild lean to poison because Generals/bosses are the hard problem, but both have a board state that wants them. |
| bastion | **WEAK, and often not a choice at all.** | Regenerate is 1 HP/round; guardian is the tribe's identity — and guardian is already PRINTED on most Bastions, so the modal frequently renders one tile (Q3). Compounded by the tribe barely being able to reach the rung (Q2). |
| stray | **CURRENTLY A TRAP CHOICE.** | Rampage is unconditional compounding on a proven killer. Sniper is a rules rewrite that is often a downgrade, is described by text implying the opposite (Q1), and is a hard no-op if the card took Swift at rung 1 (Q4). Once the copy is fixed and swift+sniper is resolved, this becomes a real choice — a wide-chaff answer vs a scaling threat. |

**Two of six are genuine (dead, warlock), two lean hard (soldier, bastion), one is
fake (beast), one is currently a trap (stray).**

---

## Priority order

1. **BROKEN** — swift eats sniper (`Combat.gd:5221`); fix before playtesting the
   Stray pair. Also fixes Battle Drummer / War Cry / Catapult Crew silently
   disabling snipers.
2. **BROKEN** — Bastion cannot reach its own rung (0-ATK pool vs the kill gate at
   `Combat.gd:6034`). Credit kills from `reflect_strike`/Thorns, or give Bastion an
   offensive option.
3. **BROKEN (copy)** — `sniper` and `guardian` descs in `KeywordEffects.gd:14,24`
   both misdescribe the rule the player is buying.
4. **NEEDS PLAYTEST** — beast pair is a fake choice; replace `overrun` or make it
   worth taking.
5. **NEEDS PLAYTEST** — one-tile doctrine modal when the veteran already prints the
   other option.
6. **FINE** — the `doctrine` fold, the bare-keyword value defaults, the
   guardian duplication, and the dead/warlock pairs. No action.
