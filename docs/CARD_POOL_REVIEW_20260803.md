# Card Pool Review — 2026-08-03 (adversarial two-round AI review, second run)

**What this is.** The `docs/CARD_POOL_REVIEW_20260714.md` protocol re-run against the pool as it
stands today (236 draftable cards, up from 165). Two independent agents worked from a fresh
`tools/_probe_card_dump.gd` dump and the mechanical ground truth — **THE PROSECUTOR** (find the bad
cards) and **THE DESIGNER** (pitch new ones) — then each was turned on the other's work and forced
to HOLD or CONCEDE per point. The house reviewer (this file) fact-checked every load-bearing claim
against code before ruling, and **overrode both agents where they were wrong**.

**Status: nothing here is implemented.** The pool is untouched. This is a decision list.

**Verdict on the run:** the 2026-07-14 review scored the pool 6/10. The 2026-07-15 interest slate
and the passes since fixed most of what it found. What is left is a different and narrower set of
problems: **the pool has not absorbed its own newest rules.** The muster delay (2026-07-21) and the
overkill blocker economy (2026-07-28) are the two best mechanics in the game and **between them
they are read by four cards.**

---

## The headline finding

**`_mustered_this_round` has exactly one consumer in the entire codebase** — the Doom fuse at
`KeywordEffects.gd:357`. Zero of 236 cards read the muster window.

The muster delay is the rule Slay the Spire, Balatro and Hearthstone do not have. Today it only
**taxes**: it makes deployment worse and gives nothing back, so the optimal line is always "dump
whatever I can afford and eat the round." Both agents converged on this independently from
opposite directions, and it is the through-line of the whole review.

The same is true one rule over: the 2026-07-28 overkill pass rebuilt the entire blocker economy so
that killing blows spill into the body behind, and **three cards in 236 read that rule.**

---

## Part 1 — THE EXISTING POOL

### 1 clean cut

| id | what it is | why |
|---|---|---|
| **`hexwright`** | common creature, c2 2/4 | `"keywords": [], "desc": ""` — a literally blank common in the pool's most over-populated band (75 creatures at c2). The Designer offered no defence: *"this is the one entry where I think the Prosecutor should simply be allowed to swing."* |

### 9 reworks — keep the id, rebuild the card

Keeping the id is the cheap path: the art, the `UPGRADES` "+" entry and the draft slot are already
paid for. **House policy is buff-the-boring over nerf-the-fun**, so a rework beats a cut wherever
the shape is salvageable.

| id | the charge (verified) | the rework |
|---|---|---|
| **`grave_levy`** | *Strictly dominated.* `war_boar` and `grave_levy` are both common, both c2, both text "Charge.", both 2 HP — War Boar has **4 ATK**, Grave Soldier has **2**. The cleanest domination in the pool. | *"Charge. When a friendly creature dies, this gains +2 ATK this fight."* **This is the highest-value single fix in the review** — see S1 below: `charge` is the only keyword that beats the muster delay *and* reaches the face, it is printed on **2 cards**, and one of the two is dominated. |
| **`curtain_wall`** | Blank: `keywords: []`, `desc: ""`. But **c3 has only 3 common creatures** against c2's 75 — cutting spends the pool's scarcest slot to delete rather than fix. | *"Armored. Overkill and Piercing never carry past this creature."* Turns the pool's only blank c3 common into the card that reads the 2026-07-28 rule, and takes printed `armored` from 2 cards to 3. |
| **`quick_shot`** | Loses to a **cost-0 starter**: `spark` deals 2 for free; Quick Shot deals **1** for 1 Command and Exhausts. Its rider is `draw 1`, which refill-to-5 has killed. | *"Deal 1 damage to any target. If it dies, repeat this on the weakest enemy."* A finisher for the chip damage the pool already prints in bulk. The decision becomes *when*. |
| **`holy_smite`** | `maxi(3, missing)` — under the pacing model the reservoir is usually empty, so the **floor is the card**: 3 damage for 2 Command, when `strike` deals 3 for 1. | *"Deal damage to an enemy equal to twice its ATK."* Reads the one number always visible on the target. The only removal that gets better the scarier the threat — and blank against a wall. |
| **`concentrate`** (Immolate) | **Wrong rarity.** `ballista_bolt` is a **common** at the same cost dealing **5** to Immolate's 4, *and* it reaches the face by overflow rather than needing the kill flag. | Build the rare around *repeating* the face-jump lane to lane while it keeps killing — the only interesting half. |
| **`volunteer`** | **The card lies, and it is a literal bug.** `summon_token(atk, hp, lane, false, row, **{}**, name)` — the extras dict is empty, so the free body has **no keywords at all**. The printed Swift exists only on the mode nobody plays. | *"Swift. When discarded: this musters in your front row instead."* Pay the 2 for Swift and lane choice; throw it away and it arrives in a lane you didn't pick and must form up. Both printed numbers become true. |
| **`scatter_line`** | Same function body as `close_ranks`, same crash value, same rarity — at **+1 Command and +Exhaust**. Worse still: `close_ranks` pushes bodies *together* (a blocker crash damages **both**), scatter pushes them into walls (an edge crash damages **one**). | Re-price to 1 and print the column-opening as the point, not a side effect. |
| **`pay_wagon`** | A **rare** whose entire effect is `RunState.gain_gold` at combat end — nothing about it touches the fight. Dead before a boss. And it prints gold as a payoff on a tribe whose gold spine was **retired 2026-07-24**. | Keep the wager, move the stake onto the board. The shape (a visible thing you must physically protect) is one of the pool's best and the house already shipped it twice. |
| **`the_apothecary`** | Potions cap at 3 slots per *run*, drop at 40%, bosses pay none — the modal fight sees **zero** drinks, making it a 1/4 for 2 at uncommon. | Hang it on something the fight produces every round — spells cast, friendly deaths, Doom ticks. |

### 3 acquittals — where the Prosecutor was wrong

I am recording these because the protocol's whole value is that the critic is **not** auto-trusted.

- **`shove` — ACQUITTED.** The charge was "base shove deals nothing." `_flank_push` defaults
  direction to the nearest flank (`dir = -1 if lane <= 1 else 1`), so a body in **lane 0 or lane 3
  is pushed out of bounds and crashes for an unconditional 2** — and a blocked inner push deals
  **2 to the target AND 2 to the blocker**. On half the lanes it is an unblankable 2-damage spell.
- **`recycle` — ACQUITTED.** `_on_card_dismiss_requested` refuses curses by name (*"A curse cannot
  be discarded — it must be endured"*) while `_show_recycle_modal` snapshots the hand **unfiltered**.
  Recycle is the pool's **only unconditional curse-out**, and `wound` carries Retain, so it
  otherwise shrinks your working hand from 5 to 4 for a whole fight. *Real defect, conceded by the
  Designer:* all six curses cost 0 and Recycle draws `cost`, so **it pays you in inverse proportion
  to how much you wanted rid of the thing you fed it.** Fix the payoff, keep the card.
- **`lancer` — ACQUITTED, but the keyword is guilty.** The Prosecutor quoted the project's own
  2026-07-30 ruling that Overrun is "a FAKE choice." Verified verbatim — but it is scoped to a
  *10-kill veteran* where "+1 is noise," judged against `charge`. Lancer is **Overrun 2 on a 2-ATK
  body** — +100%. The real problem is that Overrun's condition is **enemy-controlled** (it fires
  only when the opposing front lane is empty), so it can be hoped for but never planned. `overrun`
  is on 4 cards **including a hero starter**. Fix the keyword's trigger; don't cut one common and
  leave the disease in a starting deck.

---

## Part 2 — THE NEW SLATE (10 cards)

The Designer pitched 12; the Prosecutor cut 5 and revised 5; the Designer withdrew 3 of its own
and replaced them. Final ruling below. **Naming: the new trigger prefix is `On-Muster:`** — the
Prosecutor overruled both of the Designer's proposals (`Mustered:` collides with five live
meanings; `Stood To:` is unglossed archaic vocabulary inventing a sixth). `On-Muster:` joins the
existing `On-Enter:`/`On-Death:` family and points at the word already printed on the token.

### Ship as pitched — 2

**1. Dead Man's Kit — 1 · armament · common**
> Bearer gets +2 ATK. When the bearer dies, return this to your hand.

Every existing armament says *don't equip the body that is about to trade* — `_after_armament`
exhausts unconditionally, so all six are latent 2-for-1s under a pacing model where bodies die in
1–2 rounds. This one says *that is the one*. It takes the type's worst case and makes it the
product. **Specify before shipping:** what happens when the bearer leaves play *without* dying —
`griffin`, `banish` and The Armourer's Night are all live verbs it is currently silent on.

**2. The Powder Gallery — 3 · creature · BASTION 1/6 · uncommon**
> On-Muster: deal damage to every enemy equal to the HP this is missing.

The best card in the review, and the one that justifies the whole template. **You volunteer a body
for a beating a round before you learn what it bought.** Nothing in 236 cards asks that. The
magnitude needs no new state — it is already drawn on the token's HP seal, so the number the player
reads is the number that lands. Your own healing turns it off, which is funny in the right register
and a genuine deckbuilding tension. *Rate check:* it must never beat `cinder_whelp` (guaranteed 3
to all enemies at the same cost) on expectation, or the wager is fake.

### Ship revised — 5

**3. The Stammerer — 1 · creature · WARLOCK 0/5 · common** *(restatted from 1/2)*
> On-Muster: deal 3 damage to the enemy across from this.

The template buys a round of survival, so ATK is the one stat that doesn't help — and a mustering
body can't initiate anyway, so it is unspendable on the round that matters. At 1/2 it collected its
payoff about a third of the time. The teaching rung of the class.

**4. The Colours — 2 · armament · uncommon** *(the player now picks the successor)*
> Bearer gets +3 HP and Guardian. When the bearer dies, another friendly takes this up.

As pitched, "another friendly takes this up" named no chooser — after the first placement the card
plays itself, which is the same charge filed against `lancer` and `pay_wagon`. With a player pick
at each hop it becomes a real running decision, and `_can_equip_armament` is already the
legal-target predicate so the picker gets its filter free. Guardian is a liability you are choosing:
it shortens each bearer's life, and the Colours walk down the line all fight.

**5. The Serjeant-Major — 2 · creature · SOLDIER 1/5 · uncommon** *(payoff lands in-fight)*
> When a friendly creature earns its name, it keeps +1/+1 for the rest of the run.

As pitched, the entire payoff landed *after* the fight — the same shape as `the_apothecary`, cut
above. The fix is already in the file eight lines from its own hook: the Letters Patent relic
promotes the live body on the spot and lets `get_upgraded_card_data` carry it forward. Copy that and
it gains a visible moment and keeps its permanent half for free.

**6. The Long Gun — 3 · creature · BASTION 4/4 · common** *(Piercing → Armored — not optional)*
> Sniper. Armored.

**The sharpest finding of the review, and it is a live issue, not just a pitch problem.**
`_strike_reaches_face` (`Combat.gd:5525`) is a **pure property of the attacker** —
`if attacker.has_keyword("piercing"): return true` — and never asks where the shot is aimed. The
sniper path passes it straight into `_apply_piercing_overflow`. So Sniper + Piercing on one body
means: aim **anywhere on the board**, kill a low-HP back-row target (which by definition has nothing
behind it), and send the remainder to the **face** — and snipers chain on their own kills. That is a
repeating face-damage engine that ignores the column blocker economy the 2026-07-28 pass was built
to create, at the rarity that is 65% of act-1 offers. The pitched counterplay ("it abandons its
lane") prices it backwards: abandoning the lane isn't the cost, it's the upgrade. Sniper alone is
the card; `armored` takes S3's giveaway number from 2 printings to 4.

**7. The Armourer's Night — 3 · spell · rare** *(priced against remaining health)*
> Remove a friendly creature from this fight. Its card keeps +2/+2 for the rest of the run. Exhaust.

Removal-not-death is correctly load-bearing — no On-Death, no Roll of the Fallen entry, nothing for
Gravepact or Corpse Eater to launder, so it can't be turned into a sacrifice engine. But as printed
the optimal line is **hold it until a body is doomed, then cash for free**, which collapses the
wrenching choice it was built for. Scale the permanent gain to the body's remaining health: full HP
pays the full +2/+2, a body at 1 HP pays a scratch. Then cashing a doomed creature is deliberately
the worst line.

### New, answering the structural charges — 3

**8. The Horns of the Fourth — 2 · creature · BEAST 2/2 · uncommon**
> Adjacent friendlies have Charge.

**This is S1 answered directly.** Its mirror already exists — `battle_drummer` (c2 common,
"Armored. Adjacent friendlies have Swift") — so the pool ships the *weaker* grant at common and the
stronger grant nowhere. Adjacency is three slots, so where the horns stand decides which lanes can
cash a card from hand into face damage the moment it lands. Rides the proven `drummer_swift`
pattern, and per the rider contract a derived-every-frame rider takes the rail orb only.

**9. The Pavise Line — 1 · creature · BASTION 0/4 · common**
> Adjacent friendlies have Armored.

**S3 proved by construction.** This is `royal_guard`'s *"Adjacent friendlies take 1 less damage"*
written in the keyword the game already owns — so it appears on the status rail, is legible to the
forecast, and is a shape the war school and the Standard Bearer wayside can actually speak about.
Armored is −1 **per hit**: enormous against a wide line of small attackers, near-worthless against
one big blow. You are pricing the enemy's *shape*, not their total.

**10. The Road Cut — 4 · spell · rare**
> The enemy places no creatures for two rounds. Exhaust.

The pool's **first spell above cost 3**, and the first card that pays you for banking. `wolf_pits`
is singled out by the Prosecutor as one of the pool's five best precisely because it prices the
*reinforcement clock* rather than the board — the pool has three cheap versions of that verb and no
top end. *Flagged risk:* its best window (an empty enemy board) is the window where you were already
winning. Wants playtesting for win-more.

### Cut from the slate — 5

- **The Citation** and **The Colonel of the Fourth** — three cards on the veterancy axis was
  over-correction, and the Colonel's promotion *does nothing for the fight you pay 4 Command in*
  (the mod stack folds at draw time). **Keep the c4 4/6 soldier body; it needs different text.**
- **The Field Officer** and **The General Levy** — withdrawn by the Designer itself. The Officer
  made the muster delay *cheaper* rather than making it *pay*; the Levy is a token flood the pool
  already has four of, in a category the house has rejected by name.
- **The Last Garrison** (c5 0/12, *"All damage to your hero is dealt to this creature instead"*) —
  **cut on a combo hole, and it is not fixable by wording.** `damage_player_hero(amount,
  from_effect := true)` is the single funnel, and every self-damage cost in the game routes through
  it: `blood_tithe` becomes *"Deal 4 to enemy face"* for 1 Command with no cost, `bloodsworn` is a
  4/4 Lifesteal with its price deleted, the whole 6-curse draw-sting pack stops biting, and
  **Ascension A3 stops being a rule.** A 0/12 doesn't buy three rounds; it buys twelve points of
  every drawback in the game. If a top-end wall is still wanted, it must be **bounded per round and
  creature-scoped.**

---

## Part 3 — What cards cannot fix

These outlived the crossfire and are worth more than any single card.

**S1 — the arrival economy is upside down.** `charge` is the **only** keyword that clears both
`ignores_muster_delay()` and `_can_reach_face`. It is printed on **2 cards**. The strictly weaker,
face-barred `swift` is on **14**. *Rebalancing those printings is worth more than any card in this
review* — and note S1 **cannot be answered by a top-end card at all**, because the Command buying an
expensive grant is the same Command buying the bodies, so any "make your arrivals fight" spell above
~2 cost is blank by construction.

*Correction to the charge as originally filed:* "two-thirds of the pool's printed ATK never takes an
initiated swing" overstates it — a mustering body **does** spend its ATK reactively
(`_defender_is_mustering` arms the counter, deliberately: *"'cannot attack' must not decay into
'cannot fight back'"*). What is genuinely zeroed is the narrower and better claim: **every keyword
contingent on an initiated attack** — `overrun`, `rampage`, `piercing`, `sniper`, cleave,
attacks-twice — on bodies that mostly never take one.

**S3 — "damage goes somewhere else" is written eight ways and keyworded three.** `guardian`(10),
`shield`(3), `armored`(2), then four cards spending their whole text re-inventing it in prose
(`interpose`, `bodyguard`, `column_ward`, `royal_guard`) plus `scapegoat`'s transfer. **None of the
four longhand ones can be granted** — the war school offers Armored/Swift/Thorns, the Standard
Bearer wayside moves a *keyword*, `adaptable` chooses one. So half the game's largest archetype is
invisible to every system built to reward it. The giveaway number: **`armored` is printed on 2 of
236 cards.** The real fix is one printed keyword meaning *"blows aimed elsewhere land here."*

**S4 — nine cards manipulate Command, against the owner's own first rule.** Most are the
`_add_discovered_card_to_hand` discount inherited from the engine (one decision, not four), and The
Coin is the sanctioned exception. But two are clean, deliberate violations: **`witch`** (common) —
*"Your first spell each turn costs 1 less"* — and **`mourner`** (starter) — *"On-Death: gain 1
Command next turn."* `duelist` inverts the rule's intent by paying you to under-spend.

**S5 — Stray has 18 members and one card reads the tag** (its own keystone). Bastion, the smallest
tribe at 14, has four times the tribal text. Stray's stated identity is MOBILITY + LARCENY and only
four of its eighteen members do either — the rest is a grab-bag wearing a tag. **A player who drafts
three Strays has drafted three unrelated cards.** Neither agent filled this hole; the slate contains
no Stray card at all. `pay_wagon`'s rework is the obvious place to start.

**A live interaction worth a look regardless of this review.** The Long Gun analysis applies to the
shipped build: `raven` (the one card that prints Sniper) plus the **Bodkin Points** relic already
reaches the face by aimed overflow. It is currently mild only because Raven is a 2/1 — but
`hexblade`'s **"+" upgrade adds Sniper** (`CardDB.gd:1204`), making a forged Hexblade a scaling
spell-deck sniper. Worth deciding whether aimed overflow *should* read to the face at all.

---

## Corrections to the agents (recorded so the protocol stays honest)

- **The 63–74% telemetry cannot carry a quantitative verdict.** `CardDB.gd:934` is quoted
  accurately, but it is **a comment citing a memo, not a measurement**; its header is dated
  **2026-07-20** and the muster delay shipped **2026-07-21**, so it was taken on a build where
  creatures could swing the round they were played; it is about *player* creatures and was used
  against *enemy* ones; and `ENEMY_HP_SCALE` has since gone 0.60 → **1.00** with
  `ENEMY_BODY_HP_BY_ACT` added, both of which make enemy bodies survive clashes. The *qualitative*
  lens ("while it stands" value is weak) is house doctrine and stands.
- **The discarded `record_kill` return at `Combat.gd:6080` is not a defect.** It was charged as
  "half the kill paths never check a rung." True, but the comment directly above it documents the
  choice: the wall-kill path deliberately defers to the `>=` catch-up sweep. *The `==` at 6209 is
  still a real gotcha* for any future card that grants several kills at once — it would fire no
  modal — but both cards that would have done so are cut.
- **"Sniper is a one-card subsystem" is half wrong.** One card *prints* it; `hexblade`'s "+"
  upgrade adds it, so two can *have* it.
- Every one of the 18 code line numbers the Designer cited was independently opened by the
  Prosecutor and found correct. Both agents' research was clean; every dispute above was a
  disagreement about design, not about facts.
