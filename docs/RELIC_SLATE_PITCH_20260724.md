# Relic ("Artefact") Slate — 2026-07-24 (4-agent research round + synthesis)

**What this is.** Four cold agents were given the game's mechanical ground truth, the design
compass, the two hard bars, and the three-defect checklist, then sent to read the genre heavily and
pitch relics — good ones to add and bad ones to avoid. This doc is the SYNTHESIS: de-duplicated,
ranked, with each pitch attributed to its source agent. Companion to
`RELIC_SLATE_PITCH_20260716.md` (prior round) and `RELIC_POOL_AUDIT_20260716.md` (the existing
pool). **This is a pitch, not a build order — nothing here is implemented.**

Full agent reports: `scratchpad/out_1_deckbuilder_canon.md` (StS/MT/Balatro/Wildfrost patterns),
`out_2_broad_genre_economy.md` (Hades/Isaac/MtG/Dominion → map & run-memory), `out_3_bm_native.md`
(muster-delay + geometry + tribes), `out_4_antipatterns.md` (the bad taxonomy).

Bars every pitch below passed: **strictly positive** (never hurts / never zero — gate or floor the
frequently-zero ones; downside only at boss tier) + **a reason to exist** (a named pool gap), traced
through the 3-defect checklist ((a) refill wash, (b) clash-time vs turn-scoped, (c) enemy reactive).

---

## THE HEADLINE FINDING — the muster-delay space is wide open, and it's a trap in the obvious spot

Three of four agents independently converged on the **muster delay** (summoning sickness) as the
single biggest untouched design space — the pool has ZERO relics that speak to the game's newest
rule. They ALSO independently converged on the trap inside it:

> **The obvious pitch — "creatures deal +N ATK the round they arrive" — is DEAD ON ARRIVAL.** A
> mustering creature can't swing that round (only Swift can, and Swift can't hit the face), so the
> buff keys on an attack that never happens. Every agent flagged this ("Charging Horn" / "The
> Green Regiment" / A11 Muster-Delay No-Op). Do not build the naive version.

The honest ways to touch the rule (all pass the bars):
- **Reward the SURVIVING window with defense, not stats** → Entrenching Tools (Armored while forming up).
- **Re-time the buff onto the FIRST REAL SWING** → The Ready Line (+2 on the first post-muster strike).
- **Punish the ENEMY's muster window** (it's symmetric) → The Sortie (+2 vs enemies still forming up).
- **Grant a GATED subset the override, face-guarded** → Grave Reveille (summons) / Fix Bayonets
  (front-lane) / Blooded (veterans) / Serjeant's Bugle (first per round). Ship at most 2 of these —
  the universal "everyone ignores muster" version is an off-switch, rejected (see BAD B1).

---

## TIER 1 — the strongest picks (my synthesis ranking, de-duped)

| # | Name | Tier·Rar | Text (as read) | Job / gap it fills | Source |
|---|------|----------|----------------|--------------------|--------|
| 1 | **Entrenching Tools** | combat·common | While a creature is still forming up (its muster round), it has Armored. | #3 rule-bend. The CORRECT muster payoff: damage reduction so raw troops live to their first swing. Fires every arrival, no gate. Makes the new rule feel good, at common where the pool is thin. | 3 |
| 2 | **The Sutler's Tally** | combat·unc | Every 3rd card you sell the sutler: forge one card free, on the spot. | #4 economy. Turns thinning into a Dominion thin-and-grow engine; rescues the philosophy stranded on the unreachable Sutler's Marker. No gate (curses always sellable). | 2 |
| 3 | **The Ready Line** | combat·unc | A creature's first swing after mustering in lands with +2 ATK — the buff waits with it through the muster round. | #3/#1. The offensive muster answer; converts "deploy early = wasted round" into "deploy early = heavier first swing." Hooks `ready_to_swing`. | 4 |
| 4 | **The Captured Colours** | combat·rare | Break a General, seize one keyword they carried (Armored/Swift/Thorns/Piercing); one of your creatures learns it permanently this run. | #2 run-memory + General-hunt routing. Makes the signature war-road hunt pay in permanent army identity; rides the existing `grant_kw` plumbing. | 2 |
| 5 | **The Oathbreaker's Brand** | **boss** | Next 3 fights your opener enters at −1 HP; forever after, your opener enters +2/+2 and Armored. | #3/#2. A genuinely NEW boss shape — all 8 current boss relics are the same static "+1 Command w/ downside" template; this is a Hades-Chaos downside that EXPIRES into pure upside. | 2 |
| 6 | **Enfilade** | combat·unc | When your creature kills the enemy across from it, it fires down the lane: deal its ATK to the enemy in the rank behind. | #1/#3 geometry. The "collapse a column" tool the pool lacks (Bodkin overflows to face; this clears the back rank). Loud, kill-triggered, ungated. | 3 |
| 7 | **The Sortie** | combat·unc | Your creatures deal +2 when they strike an enemy that hasn't yet formed up. | #3. The only "punish the fresh enemy" tool; reads the muster flag on enemy reinforcements. Symmetric-rule payoff nothing else touches. | 3 |
| 8 | **The Serjeant's Cane** | combat·unc | Once/turn, march a creature to an adjacent empty lane free; it strikes +2 ATK this round. | #3 movement (the emptiest gap — Drover's Whip is nearly alone). A per-turn positional micro-game; also single-handedly makes Drover's Whip live. *(Merges the near-identical Wheel-Lock / The Goad.)* | 3·1·4 |

---

## TIER 2 — strong, differentiated fills by gap

**Muster-delay (pick ≤2 of the "instant-muster" grants; they overlap):**
- **Grave Reveille** (combat·unc, gate: token/summon source) — summoned/risen bodies skip muster.
  Fixes the summon engine's biggest tempo leak + fills the thin Dead-tribe shelf. Best-flavoured of
  the grants ("the dead don't drill"). [3]
- **Fix Bayonets** (combat·unc) — a creature played into an empty FRONT lane forms up instantly
  (face-guarded). Fuses muster + geometry: puts a real cost/benefit on front-vs-back placement. [3]
- **Beat to Quarters** (combat·unc) — on the muster round, your not-yet-formed creatures each chip 1
  to the enemy across. Makes the silent round-1 deploy DO something; rewards going wide. [3]

**Geometry (changes what geometry MEANS — not another positional +1):**
- **The Ram** (combat·unc, Bastion, gate: 1+ Bastion) — a Bastion's strike shoves the enemy back a
  rank; a blocked shove crashes both for 2. Weaponizes the `_flank_push` crash physics (zero relic
  support today) + gives low-ATK walls an offensive identity through geometry. [3]
- **The Redoubt** (combat·unc) — once/round, the first hit your back row takes is soaked by the
  front-liner in that column. Redefines the back row from "queue space" to a defended artillery park;
  natural partner to Catapult Crew / snipers. [3]
- **Chain-Shot** (combat·unc, gate: Piercing source) — Piercing overflow that kills cascades on down
  the column. The Piercing *amplifier* the pool lacks (it only has the granter, Bodkin Points).
  *(Overlaps Enfilade's column-collapse job — ship one, probably Enfilade as it's ungated.)* [1]
- **The Fougasse** (combat·unc, Doom, gate: Doom) — a Doom detonation also hits the enemy behind the
  target. Makes Doom a column weapon; Ember Censer's +1 flows to both ranks. [3]

**Run-memory / Roll of the Fallen (thin trophy shelf):**
- **The Cairn of Names** (combat·rare) — your first creature each fight gets +0/+1 per 3 names on the
  Roll (always ≥+0/+1). Floored + incremental so it pays from fight one (fixes the "scale-too-slow"
  trap); creates real tension with Hold a Wake. *Preferred over* **The Muster-Roll** (agent 1: a 2/2
  Revenant per 5 names, gate 5+) which is bolder but needs a gate and can snowball; pick per taste. [4·1]
- **The Colour Party** (combat·unc) — first creature each fight is named for the newest fallen; at 10
  names it enters Armored, at 20 Last Stand. Pays run memory in *survivability keywords*, not
  win-more stats. [2]
- **The Regimental Bounty** (combat·unc) — each veterancy promotion (3/6/10 kills) pays 25g or a free
  card. Wires the veterancy ladder into the economy (both thin shelves); capped by real promotions so
  it can't runaway. [2]

**Tribe payoffs (bespoke per verb — the 07-16 slate left Beast/Stray/Warlock/Bastion gaps):**
- **The Rising Howl** (combat·unc, gate: 3+ Beast) — each Beast arrival banks a howl (max 5); your
  next Beast to arrive gets +1/+1 per howl. Beast is the ONLY tribe with zero relics; this is the
  bespoke ARRIVE engine (the +1/+1 lands on a body that also fires its ARRIVE at once — muster-clean). [1]
- **Blood Spoor** (combat·unc, Beast, gate) — your Beasts' random-target on-enters become AIMED. Adds
  a decision to every Beast drop without touching numbers; multiplies Bloodmoon Alpha. [3]
- **The Free Lance** (combat·unc, gate: 3+ Stray) — Strays with NO adjacent friendly get +2 ATK and
  Swift. The ISOLATION axis — the exact opposite of the oversubscribed CLUSTERING banners, and dead-on
  for the masterless fantasy. [1]
- **Fill the Breach** (combat·unc, Soldier, gate: 2+ Soldier) — when a front Soldier falls, the
  Soldier behind steps forward (resolves after the clash → fights next round; NOT routed through
  sacrifice). The relief-rank idea Second Rank was pitched as before it shipped as a stat buff. [3]
- **The Coven's Word** (combat·rare, Warlock, gate: 2+ Warlock & a spell) — with 2+ Warlocks standing,
  your first spell each turn casts twice. A board-presence spellcraft engine distinct from Echo
  Staff/Inkpot/Glowing Hand. [3]

**Sacrifice / conversion (spine has ATK/damage/on-enter payoffs but no tempo one):**
- **The Rendering-Vat** (combat·unc) — when you sacrifice a creature, bank its Command cost for next
  turn (max 3). The conversion loop cards can't print (fixed-cost rule). Only LISTENS to the sacrifice
  hook — never creates one, so no ON_PLAYER_SACRIFICE backfire. [1]

**Map / economy (thinnest shelf — all avoid gold-trickle; each changes routing/spending):**
- **The Recruiting Sergeant** (combat·rare) — Prayer Wheel: +1 card on every plain-hold reward slate
  (NOT Generals/boss); PASS the slate for 15g. Turns ordinary fights into synergy hunts. [2]
- **The War-Chest Seal** (combat·unc) — Maw Bank done right: bank silver each fight you skip a shop
  (max 5 bars); first shop breaks the seal into a half-price spree, then it's spent. Imports the
  discipline TENSION without the "never shop" anti-play. [2]
- **The Poacher's Chart** (combat·unc, solo-only) — reveal every site two rows deep + red-pennant the
  hidden Generals. Pure information-as-power for the war-road route choice. *(Merges agent 1's
  near-identical Pathfinder's Chalk.)* [2·1]
- **The Vedette** (starting/combat·common) — at fight start, the enemy's next reinforcement is
  previewed on the lane it'll muster into. The scouting relic the "enemy is a real opponent" premise
  asks for; the anti-Runic-Dome (adds legibility). [4]
- **The Press-Gang Warrant** (combat·unc) — the cheapest card at each Muster/recruit is a free enlist;
  PASS for 12g. Makes a recruit node a destination. [2]
- **The Occupation Levy** (combat·unc) — sutler prices drop 5% + 1 extra stock per claimed site this
  act (max −20% / +3). The conquest/claimed-map layer has zero relic support. [2]
- **The Field Still** (combat·unc) — +1 potion slot; brew a random potion for 25g at rest/Arsenal.
  Fixes both potion supply RNG and the empty potion-synergy shelf. [2]

**Potion / durability / defensive engine:**
- **The Sutler's Alembic** (combat·unc, soft gate) — first potion each fight resolves twice. Rewards
  HOLDING your best potion for the boss; re-values every drop. [1]
- **Blooded Steel** (combat·unc) — each time a creature survives a clash it keeps +1 ATK (stacking).
  The attrition-HONEST reshape of the win-more buff: pays the ~30% that LIVE (walls, back row,
  Bastions), not the striker that trades. Also the reshape target for boss Steady Banner. [4]
- **The Chirurgeon's Kit** (combat·rare, activatable) — 3 charges/fight (recharge each fight); spend
  one at turn start to heal a friendly 4. The defensive durability relic (Old Meg is the offensive
  one); needs the activatable-relic frame the 07-16 slate already flagged. [1]
- **The Culverin** (combat·unc) — once/fight, the first time you field 3 creatures in a turn, the
  front row volleys 2 to every enemy across. A timing/conservation spike distinct from Old Meg. [1]

**Blooded (combat·rare, gate: a 3+-kill creature)** — veterans (epithet-bearers) form up instantly.
The muster ∩ veterancy fusion ("the professional doesn't need drilling; the levy does"). Strong but
it's a 4th instant-muster grant — ship only if you didn't already take Grave Reveille + Fix Bayonets. [3]

---

## THE BAD LIST — tempting relics that would be a MISTAKE (consolidated taxonomy)

Every archetype below sounds good and fails a specific bar. The BM example is written to be
tempting — these are the pitches to recognize and reject.

| # | Anti-pattern | Tempting BM pitch that falls in | Fails |
|---|-------------|--------------------------------|-------|
| B1 | **Muster-Delay No-Op** | "Charging Horn — +2 ATK the round a creature arrives" | Arrivals can't swing that round → keys on a phantom attack. The obvious wrong reach for the open gap. |
| B2 | **Universal muster off-switch** | "Standing Orders — all your creatures ignore the muster delay" | Deletes the rule the whole game just adopted; a mode toggle, not a relic. Reason-to-exist. |
| B3 | **Break the face guard** | "Beat the Retreat — Swift MAY hit the face on arrival" | Unpicks the anti-burst guard; makes cheap Swift a combo finisher. Corrosive to the format even at boss tier. |
| B4 | **Same-round win-more buff** | "Bloodlust Banner — +2 ATK permanently when a creature strikes" | 63–74% of deaths are same-round trades → the "permanent" buff dies one clash later. Loudest when it matters least. (Fixed → Blooded Steel.) |
| B5 | **Refill-washed draw** | "Rally Standard — when a friendly dies, draw a card" | Deaths are off-turn (clash); the draw evaporates at refill-to-5. Card advantage as a headline is dead in BM (Tome of Many already retired). |
| B6 | **Clash-time Command grant** | "War-Fury Idol — kill an enemy, +1 Command this turn" | Kills land in the clash, after your turn closed → the Command is voided. Must bank into NEXT turn (Soul Lantern timing). |
| B7 | **Encounter lottery** | "Countersign Seal — reflect the first enemy spell each fight" | Zero against the many lineups that don't cast; bought blind. (Fixed → The Mantlet, with a floor.) |
| B8 | **Hidden downside rider (non-boss)** | "Reaver's Oath — all creatures +2 ATK, no gold from victories" | Negative rider in the combat pool; the cost is illegible (three empty shops later). Downside trades are BOSS-tier only. |
| B9 | **Illegibility bomb** | "Fog-of-War Cowl — lose enemy tells, draw +1" | Strips the legibility the "real opponent" design is built on (Runic Dome) AND the draw is refill-washed. Invert it instead (→ The Vedette). |
| B10 | **Invisible stat tax** | "Drillfield Charm — your Soldiers have +1 HP" | No moment, no changed decision, doesn't even reach the keystone's job. The exact shape three passes were spent purging. |
| B11 | **Anti-play bribe** | "Hermit's Charm — a creature with no neighbours has +3 ATK" | Pays you to spread thin / leave lanes empty in a lane game that punishes gaps. Cavalry Sigil in a costume. |
| B12 | **Enemy-reactive backfire** | "Gravedigger's Pact — start of fight, sacrifice weakest to draw 2" | Routes a friendly sacrifice through shared machinery → silently trips the encounter's ON_PLAYER_SACRIFICE; forces self-harm; manufactures a free sacrifice the game forbids. |
| B13 | **Scale-too-slow engine** | "Ledger of Ash — every 10th run-death, +1/+1 to a creature" | 10-death cadence outruns a 7-fight run; fires ~0–3× and zero if picked late. (Fixed → Cairn of Names, floored + incremental.) |
| B14 | **Dominated clone** | "Twin Banner — flanked creature + neighbours +1 ATK/fight" | The 6th of the oversubscribed banner cluster (Unity/Vanguard/Linked/Flanking/Bridge). Reason-to-exist. |
| B15 | **Ceramic Fish (bloat-for-gold)** | "gold every time a card is added to your deck" | Rewards deck BLOAT — backwards for BM's thinning economy; teaches "grab everything." |
| B16 | **Literal Maw Bank** | "gold per node until you EVER shop, then it dies" | Optimal line is "never shop" — but shops build your army. Keep the tension, make them spend (→ War-Chest Seal). |
| B17 | **Mana rock** | "cheap relic: +1 Command per turn" | Bends the tightest, most-protected rule (fixed Command) at the wrong tier. Sanctioned Command relics are rule-benders with a moment (Miser's Coffer), not rocks. |
| B18 | **Transformation SET** | "collect 3 relics of a type → transform" | BM offers relics ~one at a time from small pools; a 3-set is a draft-lottery, dead until RNG completes it, no moment. Grant the payoff from ONE gated relic instead (Captured Colours does this). |
| B19 | **Uncapped stacking / proc-chain** | "+X permanently every fight/kill, forever" | Dead early (fights too short), win-more snowball by act 3 (the Steady Banner casualty). Always CAP it. |
| B20 | **Reward-with-difficulty rider** | "extra card reward, but enemies get +X" | Drags a negative rider into a clean reward relic. Guardrail rewards by SCOPE (normal fights only), never by combat downside. |

Cross-cutting lesson (from all four): the muster-delay hook "let X ignore it" is a trap in two
directions — too broad (B2) erases the rule, face-unguarded (B3) breaks the format; the safe zone is
a *gated, face-guarded subset*. And any muster-window payoff must be damage REDUCTION (Entrenching
Tools), never stats (B4/B10) — the creature can't act the round it's buffed.

---

## Convergences, tensions, and a suggested build order

**Where agents agreed (high confidence):**
- Muster delay is THE gap, and "+ATK on arrival" is the trap (all but the economy agent).
- The economy's thinning philosophy wants a reachable engine (Sutler's Tally) — the utility tier is
  still unreachable per the 07-16 audit, so tag economy relics `combat`.
- The boss tier needs a non-template shape (Oathbreaker's Brand).
- Cap every run-scaling relic; floor every frequently-zero one.

**Real tensions to resolve before building:**
- **Instant-muster grants overlap** (Serjeant's Bugle / Fix Bayonets / Grave Reveille / Blooded).
  Ship ≤2, on different constituencies (recommend Grave Reveille + Fix Bayonets).
- **Column-collapse overlap** (Enfilade vs Chain-Shot) — ship one (Enfilade, ungated).
- **Movement trio** (Serjeant's Cane / Wheel-Lock / The Goad) — one relic, merged above.
- **Map-reveal duo** (Poacher's Chart / Pathfinder's Chalk) — one relic.
- **Run-memory opener buffs** (Cairn of Names / Colour Party / Blooded / the 07-16 Cerecloth) all key
  on "first creature each fight" — don't ship all; they'd compete for the same slot.

**Machinery this round would need built once, reused often:**
- The **activatable-relic frame** (click + charge pips + targeting) — Chirurgeon's Kit, and the
  already-pending Old Meg / Sexton's Spade. This is the biggest unbuilt dependency.
- An **offer-gate helper** on `_roll_allowed` precedent for the tribe/keyword/token gates (several
  pitches assume `_deck_ctype_count` / `_deck_has_keyword` / `_deck_has_token_source`).

**Suggested first five to build** (cheap, high-impact, no new frame needed):
1. Entrenching Tools (common, no gate, makes the new rule feel good)
2. The Sutler's Tally (rescues the thinning philosophy)
3. Enfilade (the column tool, loud and ungated)
4. The Oathbreaker's Brand (the new boss shape)
5. The Captured Colours (the General-hunt payoff, rides existing `grant_kw`)

Then the muster pair (Grave Reveille + Fix Bayonets), the movement relic (Serjeant's Cane), and one
run-memory opener (Cairn of Names).
