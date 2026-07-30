# Design Research — Cards, Relics, Combat Structure (2026-07-18)

**Status: research + audit + pitch. Nothing here is built.** Successor to
`CARD_SLATE_PITCH_20260716.md` / `RELIC_SLATE_PITCH_20260716.md` (both of which have
since been LARGELY BUILT — the interest slate and the relic survivors are live in
CardDB/RelicDB, so this doc deliberately reaches past them).

How this was made: full read of the live CARD_POOL (~190 entries) and RELICS (~135),
the intent machinery in Combat.gd (`_assign_intents` / `_resolve_intents` /
`_enemy_place_creatures`), and a web-research pass over the genre's best-documented
designers: Mega Crit (StS 1 GDC + StS 2 EA reception), Eric Dodds (Hearthstone GDC),
Mark Rosewater (New World Order / lenticular design), LocalThunk (Balatro interviews),
Subset Games (Into the Breach postmortem), Wildfrost criticism, Duelyst positional
theory, Monster Train positioning, Inscryption's jam postmortem.

---

## 1. Research digest — ten findings, each with the BM translation

1. **Hearthstone's first-read rule** (Dodds, GDC 2014): if a first-time reader doesn't
   immediately understand the card, change it. Best cards have the highest
   *depth-to-complexity ratio* — depth lives in the interactions, not the text.
   → BM translation: card bodies should get SHORTER as the board grammar gets richer.
   Keyword reminder text belongs in the hover glossary, not the printed line.

2. **Rosewater's New World Order**: complexity is capped at COMMON, because commons are
   most of what a new player sees. Rares may be intricate; commons must be readable at
   a glance. **Lenticular design**: the best commons look simple and play deep
   (the depth is positional/temporal, not textual).
   → BM's 2026-07-16 vanilla commons were exactly this move. The missing rung is the
   *conditional-keyword common* — one keyword, one visible condition, all depth in
   placement (see slate §5C).

3. **StS intents** (universally cited as the genre's masterstroke): telegraphing enemy
   action converts combat from guesswork into informed counterplay. The depth isn't the
   telegraph itself — it's that the PLAYER'S toolkit can answer what's telegraphed.
   → BM has the telegraph half (9 intent verbs, cycles, anti-repetition, badges) and
   **zero cards that read it**. The loop is open on the player side. Biggest single
   finding of this pass — see §4-C1 and slate §5A.

4. **Into the Breach postmortem** (Subset, GDC 2019): perfect information + varied
   objectives. "When goals vary beyond *kill the enemies*, you get interesting choices"
   — protecting buildings, surviving, blocking spawns, all competing.
   → BM stole ItB's push physics but not its OBJECTIVES. Every BM fight has one goal:
   the enemy face. §4-C2 pitches secondary objectives through the mutator system.

5. **Wildfrost, the cautionary tale** (reviews + community postmortems): the counter/
   timer system creates WHEN-depth, but the game is criticized for binary outcomes
   (barely-won ≈ stomped), hidden information (unexplained interactions), and
   difficulty-by-stat-inflation with low player agency.
   → BM already dodged the traps (ascension = rules not HP; intents visible; potion/HP
   carry makes fight margins matter). Do NOT import the counter system wholesale — its
   WHEN-depth can be had through the intent language instead (CHARGE already is a
   2-round attack; that's a Wildfrost counter wearing BM clothes).

6. **Balatro** (LocalThunk): the trinket IS the build — a great permanent has an
   identity strong enough to draft toward. Trial-and-error over theory.
   → BM's relic rarity tiers already encode this ("an outlier is tamed by scarcity").
   The test for new rares in both pools: *would a player reroute the map for it?*

7. **StS 2 (EA 2026)**: fewer energy relics — power must come from card synergy;
   relics moved toward *situational spikes* and in-fight durability/conservation
   decisions; **enchantments** permanently modify cards mid-run.
   → BM's mod stack (drill/banner/forge/war-school folding per deck_uid) is already
   ahead of StS2's enchantment curve. The unexplored StS2 axis is **conservation**:
   BM has no activatable, chargeable, or exhaustible relic — every relic is a passive
   trigger. §6 revisits the activatable frame.

8. **Duelyst positional theory** ("The Language of Duelyst"): position matters when it
   *denies the opponent options for free* and when card effects read position.
   Positions must be UNEQUAL for placement to be a decision.
   → BM's four lanes are geometrically identical; only adjacency counts and edge
   crashes differentiate them. Everything that made the movement package good came
   from making lanes carry stakes (writ, salt, snatcher). §4-C3 continues that line.

9. **Monster Train positioning**: depth from *intra-stack order* — morsels feed the
   unit in front, blockers shield the units behind. The stack is a little machine.
   → BM's column (front/back pair) is the analogous unit and already has bodyguard/
   column-ward/understudy verbs. The missing verb is FEEDING the column-mate (§5C).

10. **Inscryption** (jam postmortem): drama comes from *visible power shifts* — one
    card should swing how the whole fight is approached; and unopposed lanes hitting
    face makes every empty lane a live threat gradient.
    → BM has the lane gradient. The drama lesson endorses loud, rule-bending rares
    over incremental value (the house "no boring cards" rule, confirmed from outside).

---

## 2. Card pool audit against that bar

**What's already right** (worth saying — the pool is in genuinely good shape after the
07-13/07-15/07-16 passes): one-concept-per-card is house law; six tribes each with a
keystone and a verb; vanilla commons restore the NWO floor; the curse pack is branded
and legible; rarity now tracks build-warp, not stat size; movement/lane-stakes package
gives geometry teeth; the starter contract keeps drafted cards strictly better than
openers. Most of what the research preaches, the pool already practices.

**Findings:**

- **F1 — Common-slot text creep (first-read rule).** A handful of commons carry
  compound or reminder-laden bodies: `raven` (Sniper explainer + on-enter snipe),
  `hexblade` (Sniper explainer + per-spell ramp), `lookout` (dual front/back mode),
  `hex` (two-mode damage), `holy_smite` (missing-HP math + floor + slay rider).
  These are fine CARDS in the wrong RARITY dress or carrying glossary text the hover
  already owns. Fix is copy/rarity, not mechanics: strip printed Sniper reminder text
  (the keyword hover exists), and consider uncommon for dual-mode bodies.

- **F2 — No intent counterplay (the open loop).** The enemy telegraph vocabulary
  (ATK/ABILITY/CHARGE/GUARD/RALLY/HEAL/RETREAT/ENRAGE) is built, rendered, and
  tutorialized — and not one player card, relic, or keyword interacts with it.
  Intents are currently pure information, never a lever. Slate §5A closes the loop.

- **F3 — Armaments are a six-card stub.** A whole card type (with its own targeting,
  icon language, and Exhaust rule) got one slate and stopped. No tribe ties, no death
  interaction — in the game ABOUT attrition, equipment that dies with its bearer and
  is gone forever is a design vacuum. §5B proposes the heirloom rule.

- **F4 — The lenticular rung is missing.** Between the six vanillas and the
  specialists there's room for conditional-keyword commons: one keyword, one visible
  board condition, zero extra state. These are the cards that make placement feel
  smart in act 1 without adding text anywhere else.

- **F5 — Spell pool damage-density.** ~15 spells are "N damage + rider" variations.
  The recent slates already pivoted to verbs (move/salt/condemn/read); hold that line —
  every future damage spell should need a positional or temporal clause to justify
  itself (Slow Match and Petard pass; a new "deal 4" does not).

- **F6 — Trap is a lone class.** `wolf_pits` is the only groundwork; the house rule
  ("no lone secret cards — build a class of them") was applied to kill the King's
  Shilling but Wolf-Pits sits alone anyway. Either build the class (§5D) or accept it
  as the exception it currently is.

---

## 3. Relic pool audit

**What's already right:** rarity-weighted rolls with the scarcity-not-shaving doctrine;
the positivity filter; visible-moment reshapes of every invisible stat-tax; offer
gating (no dead rewards); retirement discipline keeping old saves honest. This matches
or exceeds what the research describes in StS/Balatro practice.

**Findings:**

- **R1 — No relic-to-relic interaction.** Hades' duo-boons are the genre's proof that
  permanents combining EXPLICITLY (not just incidentally) creates draft stories.
  BM relics only ever stack incidentally. One pilot "regimental pair" would test the
  shape cheaply (§6.1).

- **R2 — The activatable frame never landed.** Old Meg was pitched as a fired bombard
  (2 shots, click to aim) and shipped as a passive trigger. Every one of ~135 relics
  is a passive. A CLICKED relic is agency the pool structurally lacks, and the frame
  (click + charge pips + potion-style targeting) was already specced in the 07-16
  pitch. StS2's conservation axis (in-fight durability only — the positivity filter
  bans cross-fight burnout) rides the same frame (§6.2).

- **R3 — Boss tier is thin.** Live boss relics: `pandoras_box`, `lean_mean`,
  `glowing_hand`, `hourglass_of_ruin`, `gravewardens_pact`, `articles_of_war` — six,
  with 3 offered per boss and 2 boss picks per run. Repetition within a handful of
  runs is guaranteed. Two more non-template boss relics would fix the roll (§6.3).

---

## 4. Combat structure — assessment and directions

**The structure as built:** simultaneous clash every round (front strikes first, both
rows swing, lethal doesn't deny retaliation), 4 identical lanes × 2 rows, enemy deals
1-2 bodies per round from an ordered encounter deck after the clash, escalation at R4,
intents assigned each round. Command 3 + bank 2; persistent hand refilling to 5.

**Judgment: the skeleton is sound — don't touch resolution.** The simultaneous
mutual-trade model is the game's identity: it makes trades computable, which makes the
game a PLANNING game (the ItB family), and the attrition pacing ("design for value per
card-life") is a real, differentiated stance. The 07-07 diagnosis ("samey = presentation,
not mechanics") has been answered by a year of legibility passes. What remains are three
structural under-exploitations, in priority order:

- **C1 — The intent language is underfed and unanswered** (cheap, highest leverage).
  Two halves:
  (a) *Feed it:* ~20 encounter creatures carry non-trivial cycles; the plain-ATK body
  is still the overwhelming default, so most fights telegraph nothing but "everything
  swings." Target: every act-2+ encounter fields at least one cycling creature; every
  General/lord kit uses CHARGE or RALLY at least once (the rival-lord kits mostly do —
  push it down into elite bands and late holds). This is EncounterDB data entry, not
  engine work — the anti-repetition and resolution code already handles every verb.
  (b) *Answer it:* ship the §5A counterplay cards WITH the same pass, so reading the
  badge becomes a skill the deck can express. StS research is unambiguous that this
  loop — telegraph, read, answer — is where combat depth compounds.

### C1 implementation spec — "how do intents even work in an army game?" (added 2026-07-18)

The Cross Blitz question, answered by research: **Cross Blitz has no intent system.**
It is a true two-player card game — the enemy captain plays cards from a deck on its
own turn, units auto-strike down their columns on the Blitz commit — and its only
"telegraph" is the player memorizing enemy decklists plus reading the board. A
reviewer's standing complaint (enemy spells flash on-screen with no way to re-read
them) is the cost of that model. So Cross Blitz is the structural sibling, but NOT the
teacher here — StS's lesson has to be TRANSLATED, not copied, because in BM (as in
Cross Blitz) the enemy is an army plus a deck, not a monolith with one action per turn.

The translation: a monolith telegraphs its one action; an army telegraphs on **three
channels**, and BM already owns two of them mechanically.

**Channel 1 — per-creature action badges (BUILT, underfed).** The StS intent mapped
onto each body: `_assign_intents` + the badge pipeline already handle
ATK/ABILITY/CHARGE/GUARD/RALLY/HEAL/RETREAT/ENRAGE with cycles and anti-repetition.
The remaining work is EncounterDB data entry plus a NOISE BUDGET rule: **one or two
"pattern" creatures per fight, everything else stays plain ATK.** If every body wears
a badge, none of them read — StS fights work the same way (one Gremlin Nob among
fodder). Design cycles as 2–4 beat loops where the dangerous beat is visible one round
early (that's what CHARGE already is: a Wildfrost counter wearing BM clothes). Every
badge needs a hover glossary line like keywords have — the Cross Blitz spell-flash
complaint is the anti-pattern, and the battle log already covers the after-the-fact
half.

**Channel 2 — the arrivals queue (the army-game intent StS never needed).** In StS
the monolith's NEXT ACTION is the future; in BM the future is mostly WHO ARRIVES NEXT.
BM's enemy deck is an ordered, pre-authored list — the game is sitting on perfect
information it never shows. Wildfrost's visible spawn queue and Monster Train's wave
preview are the genre precedents. Proposal: a **muster road** strip beside the foe's
board — the next arrival shown face-up, the two after it as card-backs, so the player
plans lanes against what's marching in. One design collision to resolve first:
Lookout's back-row mode, The Informer, and the pitched outriders_report all SELL
arrival-reveals — if the HUD gives the next face away free, Lookout is dead text
(no-dead-cards law). Resolution options, in preference order: (a) HUD shows next
arrival face-up; Lookout's back mode reveals one step DEEPER (the two after) and
Informer keeps its strike-from-the-muster half, which is the real payload anyway;
(b) HUD shows only card-backs (count), reveals stay card-owned — weaker, but zero
rework. Take (a): the depth win is bigger than the rewrite cost of one common.

**Channel 3 — fight-level clocks (half-built).** The army-scale equivalent of "the
boss will attack for 40": telegraph the SCHEDULE. `_next_wave_count()` and the
escalation round are deterministic — show next round's arrival count as pips on the
muster road ("●● two march in next round"), and pre-announce the escalation beat one
round early (the Everflame surge and OUTRIDERS banners currently fire AT the beat;
an intent fires BEFORE it). This is cheap — the data already exists at assign time.

Build order within C1: Channel 3 pips (trivial) → Channel 1 EncounterDB feed with the
noise budget → Channel 2 muster road + the Lookout/Informer rework → then the §5A
Counterplay Pack, which needs Channel 1 density to never be dead.

**AMENDMENT (2026-07-18, operator framing: "we are playing essentially real opponents
with some weird things").** The solo enemy is an OPPONENT, not a scripted monster —
that framing redraws the line between what's readable and what's hidden:

- **Intents are BODY LANGUAGE, not announcements.** A real opponent never tells you
  his plan, but his ARMY is physically visible — a brute rearing up (CHARGE), a line
  bracing (GUARD), a drummer raising sticks (RALLY) are things you'd SEE on a field.
  Channel 1 survives intact under the opponent fiction as long as every badge maps to
  a body doing something watchable, never to mind-reading. (Fighting-game wind-up
  logic; ItB's burrowing/aiming Vek.) The noise budget stands.
- **Channel 2 FLIPS: arrivals stay hidden by default — resolution (b), not (a).**
  The muster road as free HUD info would read the opponent's hand, which breaks the
  frame. Instead the reveals stay CARD-OWNED: Lookout / The Informer / the
  outriders_report relic become an **information economy** — scouting as a draftable
  resource. No reference game has intel as a draft axis; under the opponent frame
  it's not a compromise, it's a differentiator. Lookout needs no rework.
- **Channel 3 survives diegetically: dust on the road.** Pre-announcing next round's
  wave size isn't hand-reading — approaching riders raise dust you can see. One
  ambient tell (dust cloud + hoofbeats + a count pip) the round BEFORE outrider/
  surge/escalation beats; the existing banners keep firing AT the beat.
- The §5A Counterplay Pack survives unchanged — its cards punish visible wind-ups,
  which is reading the line, not the mind.

- **C2 — One goal per fight, forever** (medium cost, high texture). ItB's lesson:
  vary the objective, not the resolution. BM's delivery vehicle already exists — the
  mutator system fills every fight and pays gold. Add a class of **objective mutators**
  that put a second, OPTIONAL prize in the fight with a visible deadline:
  · *The Standard* — the third enemy arrival carries the hold's colours (a marked 0/4
    bearer in the back row). Break it before round 5: bonus spoils. It heals the
    front line 1/round while it stands — killing it is tempo AND treasure.
  · *The Stores* — a marked structure occupies an enemy back slot; razing it by R4
    pays a potion. The foe guards it (their placement priority shifts to its column —
    readable, exploitable).
  · *Take the Bridge* — hold both center front lanes simultaneously at any round's
    end: the gate objective ticks double this fight.
  Optional prizes with deadlines create the ItB triage feeling (press the objective
  or play safe?) with zero change to core resolution, and they make holds feel
  different WITHOUT new enemies. Solo-only; skirmish untouched.

- **C3 — Identical lanes** (experimental, gated). Duelyst: placement is a decision
  only where positions differ. The movement package made lanes carry TEMPORARY stakes
  (writ/salt); the biome mesh could make some fights open with a PRINTED stake — one
  terrain chip on one lane (a ford: crashes there deal +1; a hedgerow: that lane's
  back row is Sniper-proof; high ground: +1 ATK to whoever holds the front slot).
  One chip, one lane, act-2+, shown on the map tooltip so routing can read it.
  Run it as a mutator-class experiment first (opt-in content, easy to cull) — NOT a
  universal board feature. Risk: stacks reading burden onto the busiest screen.

- **Considered and rejected:** Wildfrost-style per-creature attack counters (forks the
  game's identity; the research shows the failure modes and CHARGE already covers the
  wind-up beat); player-side attack-order or hold/strike toggles (re-adds the cut
  floop-era fiddle; the out-of-phase beat already exists as Mentioned in Dispatches);
  initiative stats (invisible-modifier class, banned by house rule).

---

## 5. The slate — 13 cards

Costs/stats are suggestions; shape first. All solo-first; net denylist noted where it
matters. None duplicate the live pool or the 07-16 bench.

### A. The Counterplay Pack (3) — ships WITH the C1 intent pass, not before

1. **Cold Water** — 1 · spell · common
   > Douse an enemy creature's plan: its intent becomes plain ATK. If it was
   > CHARGING, the shock deals 4 damage.
   *The moment:* the RALLY drummer swings instead of buffing; the charging brute
   fumbles the big one. First card that makes the badge a target.
   *Hook:* `state.current_intent` write + `_update_intent_display`; CHARGE check.

2. **Called Shot** — 1 · spell · common
   > Deal 4 damage to an enemy creature that is not showing plain ATK.
   *The moment:* the intent badge becomes a bullseye — teaches badge-reading by
   paying for it. Never dead late (ABILITY cyclers are everywhere in acts 2-3);
   act-1 scarcity is the draft signal.
   *Hook:* pure damage spell chassis + intent gate. Gate the OFFER on act ≥ 1's
   elite bands if act-1 cycles stay rare (no-dead-rewards rule).

3. **The Grudge-Keeper** — 2 · creature · SOLDIER 2/4 · uncommon
   > When the enemy opposing this shows a non-ATK intent: this gains +2 ATK this round.
   *The moment:* park him across from the healer and he punishes every prayer. A
   body that makes the player WANT the foe's clever turns.
   *Hook:* read opposing `current_intent` at intent-assign time; buff via temp_atk.

### B. Heirloom Armaments (3) — the armament type grows up; equipment that survives its bearer

4. **Dead Man's Boots** — 1 · armament · common
   > Bearer gets +1 ATK. When the bearer dies: the boots pass to the nearest
   > friendly, one size heavier — the bonus grows +1 each time.
   *The moment:* by round 4 someone is wearing +3 boots with three funerals in them.
   Attrition-proof equipment — the deaths the game guarantees become the ramp.
   *Hook:* on_death pass via nearest-friendly search; armament re-attach machinery.

5. **The Colours** — 2 · armament · uncommon
   > Bearer gets +0/+2. While the bearer stands, friendlies in its row get +1 ATK.
   > When the bearer falls, so do the Colours — for the rest of the fight, no one may
   > carry them again.
   *The moment:* the whole line fights better under the flag — and protecting the
   bearer becomes the fight's sub-plot. Loud when it works, loud when it falls.
   *Hook:* row-scope aura (warchief `type_buff` precedent, row-keyed); no pass-on —
   deliberately mortal, the anti-Boots.

6. **The King's Own Blade** — 2 · armament · rare
   > Bearer gets +2 ATK. Slay: the blade remembers — its bonus grows +1, permanently,
   > for the rest of the run.
   *The moment:* veterancy for an OBJECT — the blade outlives every hand that swings
   it and comes back next fight heavier. Run-memory in the equipment slot; pairs with
   the Roll, the wake, Letters Patent.
   *Hook:* mod-stack entry keyed to the armament card's deck_uid (the upgrade
   plumbing already folds per-uid state); kill attribution exists via veterancy.
   Skirmish-denylist (run memory).

### C. Lenticular Commons (3) — one keyword, one visible condition, NWO-clean

7. **Pike Square** — 2 · creature · SOLDIER 1/4 · common
   > Thorns while a friendly stands beside it.
   *The moment:* eight words. The depth is entirely WHERE — keep the square closed
   or the pikes drop. Formation-adjacent without the counter bookkeeping.
   *Hook:* conditional keyword via the `_refresh_adjacency_buffs` sweep (column-ward
   precedent — state-derived, recomputes on every move/death).

8. **Grave-Goods** — 1 · creature · DEAD 0/1 · common
   > On-Death: the friendly in front of this gains +2/+2 this fight.
   *The moment:* Monster Train's morsel, translated — the back row becomes a larder.
   Dies to anything, including the clash you planned around; feeds Gravepact,
   the Mangonel, the whole death economy at one Command.
   *Hook:* on_death + column-mate lookup; nothing new.

9. **Hedge-Wizard** — 2 · creature · WARLOCK 1/3 · common
   > Your spells that strike the enemy opposing this deal +2 damage.
   *The moment:* the Warlock tribe finally gets a POSITIONAL identity — he stands
   where the artillery should land, and moving him re-aims your whole hand. Fills
   the movement package's flagged Warlock gap with the tribe's own verb.
   *Hook:* spell-damage resolver check (opposing-lane match); movement synergy free.

### D. Groundworks (2) — Wolf-Pits gets its class (house rule: no lone secrets)

10. **Caltrops** — 1 · spell · common
    > Scatter caltrops: the next 2 enemies to arrive lose 2 ATK this fight as they land.
    *The moment:* Wolf-Pits' pacifist sibling — the arrivals stream stays a target,
    but this one blunts instead of bleeds. Together they make "prepare the ground"
    a draftable plan instead of a curiosity.
    *Hook:* the wolf_pits arrival-hook verbatim, debuff payload. Denylist with it.

11. **Stake-Line** — 1 · spell · uncommon · lane-targeted
    > Drive stakes into a lane: the first enemy to arrive there takes 4 damage and
    > is stunned for the round.
    *The moment:* aimed groundwork — read the placement priority (elites hunt your
    strongest column) and stake the road they'll take. The lane-target UI exists
    (writ/salt); this is the trap that rewards placement-AI literacy.
    *Hook:* `_lane_is_salted` sibling flag + arrival hook; lane targeting built.

### E. Identity Rares (2) — Balatro test: would you reroute the map for it?

12. **The Meadow Burns** — 2 · spell · rare · Exhaust
    > Set the meadow alight. For the rest of the fight, every front-row creature —
    > yours and theirs — takes 1 damage at the start of each round.
    *The moment:* the title card. A symmetric rule-bend the player builds to exploit
    (Armored shrugs it, Bastions hold the back, Dead want the deaths, the foe's
    1-HP arrivals cook on landing). Loud, thematic, and a genuine deck-question at
    draft time.
    *Hook:* start-of-round global tick + the existing burn/ember FX language;
    encounter passives already prove the per-round-tick shape.

13. **The Great Work** — 3 · spell · rare · Exhaust
    > Recite the fight's every incantation: cast a copy of each OTHER spell you've
    > cast this fight, in order, auto-targeted.
    *The moment:* the Warlock finisher — the whole fight's spellbook replayed as one
    apocalyptic turn. Coven Mother/Emberwright/Hexblade builds get their crescendo;
    the auto-target keeps it honest (you aim the ORIGINAL casts, the Work echoes).
    *Hook:* per-fight cast registry (worn_spellbook precedent) + `_auto_target_for`
    (Chaos Imp/Echo precedent). Cap the replay at ~6 casts for sanity. Denylist.

---

## 6. Relic addendum — 4 pitches

1. **The Fife & The Drum** (pilot regimental pair, both combat·uncommon):
   *The Fife* — "Your first creature each turn enters with +1 ATK this round."
   *The Drum* — "Your first creature each round to kill an enemy: your other
   creatures gain +1 ATK this round." Each honest alone; hold BOTH and the pair
   awakens: "**The Column Sings** — while you hold Fife and Drum, both trigger twice."
   The second half is offered gilded (Hades duo-boon presentation) when you hold the
   first. One pair to test whether relic-sets earn a place; the offer plumbing is a
   one-line pool bias.

2. **The Last Argument** (combat·rare, THE ACTIVATABLE) — "Fire the bombard: 4 damage
   to an enemy creature. Two shots per fight." Click to aim, potion-style targeting,
   shot pips on the rail chip, both shots back every fight (positivity filter clean).
   Old Meg's original soul, revived to force the activatable frame into existence —
   the frame is the point; the second activatable is then free.

3. **The Old King's Coin** (boss) — "+1 max Command. Each act's first shop: one relic
   is bought with BLOOD (6 max HP) instead of gold." Boss-tier sanctioned trade that
   touches the ECONOMY axis no other boss relic uses; the Old-Debt shared-world
   canon does the flavor work for free.

4. **The Muster-Roll** (boss) — "Choose a tribe. Every recruit slate always offers at
   least one creature of that tribe, and they cost 25% less at shops." The draft-
   direction boss relic — Articles of War prices the ARMY, this prices the ROAD.
   Non-template, changes every subsequent reward screen visibly.

---

## 7. Recommended order

1. **C1(a)+(b)** — the intent feed (EncounterDB data) + Counterplay Pack (§5A).
   One coherent build: the telegraph finally gets an answer. Highest depth-per-effort
   in this document.
2. **§5C lenticular commons + §5D groundworks** — five small cards, no new systems,
   all on existing hooks; they thicken act-1 draft texture where NWO wants it thin
   in TEXT but rich in PLAY.
3. **C2 objective mutators** — three mutator entries + marked-body machinery; the
   biggest "fights feel different" payoff without touching resolution.
4. **§5B heirloom armaments + §6.2 The Last Argument** — two small frames (armament
   pass-on, activatable relic) each paid for twice over by the designs riding them.
5. **§5E identity rares + §6 remaining relics** — the loud tops of the pools.
6. **C3 lane-terrain experiment** — last, behind a mutator, with a kill switch.

---

## Sources

- GDC Vault — "Slay the Spire: Metrics Driven Design and Balance" (Mega Crit)
- Game Developer — "Road to the IGF: Mega Crit Games' Slay the Spire"
- GDC Vault — "Hearthstone: 10 Bits of Design Wisdom" (Eric Dodds)
- Game Developer — "'Iterate fast' and other design lessons learned from Hearthstone"
- magic.wizards.com — "Lenticular Design" (Mark Rosewater); MTG Wiki — "New World Order"
- Game Informer / TouchArcade / PlayDayOne — LocalThunk Balatro interviews
- GDC Vault + AWS slides — "Into the Breach Design Postmortem" (Subset Games)
- Game Developer — "Reimagining failure in strategy game design in Into the Breach"
- Wildfrost reception: PixelDie review, Steam community difficulty threads, Dexerto
- turn1mystic — "The Language of Duelyst (Positional Advantage)"
- Game Developer — "How a game jam on 'sacrifices' became Inscryption"
- Slay the Spire 2 EA coverage: Punished Backlog, StratGG, dlcompare (2026)
- StS Wiki — "Intent"; Spire Codex — "Understanding Encounters and Enemy Patterns"
