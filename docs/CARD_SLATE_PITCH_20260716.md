# Card Slate Pitch — 2026-07-16 (v2, revised after user review)

**Status: ideas only. Nothing here is built.** Companion to `RELIC_SLATE_PITCH_20260716.md`.

How this was made: five parallel designer passes (board geometry / time & wagers / enemy-as-material / run-scale stakes / toys & comedy), each briefed on the design bar and swept against the live pool. 25 pitches → curated slate. **v2 changes after user review (same day):**

- **Sword on Credit** re-statted: 1 Command, 3/5, bill of 2 — at 4/3 he died before the bill ever came due; now desertion is a realistic outcome.
- **Crew of the Mangonel** reworked — the original (throw a living ally for its HP) failed the math: a living body deals its ATK every round anyway, so only walls threw for profit, and walls are for holding. New version hurls the *already dead*.
- **The King's Shilling CUT** — verdict: a lone arrival-interceptor is telegraphed the way a one-secret Hearthstone class is; with no class of its kind there's no mind game. The arrival-steal line is dead.
- **Mentioned in Dispatches** simplified to an ordered strike — the creature genuinely makes the kill, so veterancy credit is honest and needs no forged-credit special case.
- **Floop does not exist** (folded into `on_play` battlecries; CLAUDE.md drifted) — every floop verb in v1 converted to On-Enter. Sleeper Agent (bench) is parked: its identity was floop-dependent.
- **NEW: The Sideways War** — a 6-card lateral-movement package with printed payoffs, per user request for movement that actually matters.

Costs/stats are suggestions — shape first, numbers at build time.

---

## The Slate (10)

### 1. Sword on Credit — 1 · creature · STRAY 3/5 · uncommon
> At the start of your next turn: pay 2 Command or it deserts to the foe's line. The dead owe nothing.

**The moment:** a cheap, sturdy hireling the round you need a body — and one full turn to decide whether payday comes. At 3/5 he survives the first clash most fights, so the bill is real: 2 of your 3 Command, or a 3/5 crosses over and swings at your face. The murder-plot escape (feed him to a lethal trade — the dead owe nothing) still exists but takes engineering now, which is what makes it a story.
**Hook:** Command banking, `_desert_enemy_to_player` mirror (player→enemy direction), Black Contract's start-of-turn-bill precedent, Stray flavor.
**Tuning note:** drop to 3/4 if defections swing fights too hard.

### 2. Crew of the Mangonel — 3 · creature · BASTION 1/4 · rare (REWORKED)
> When an adjacent friendly dies, the crew hurls the body down its lane: the enemy there takes the fallen's printed HP — the foe's face, if the lane is open.

**The moment:** your funerals become artillery. The bodies were dying anyway (two-thirds die the round they land) — now every adjacent death is a ranged shot, *aimed by where the ally falls*: the lane is the trajectory. Decisions: where the crew stands (adjacency is its catchment), death sequencing, and arranging which lane your doomed creatures hold. Enemy counter is legible: kill the crew first.
**Hook:** ally-death dispatch (`_apply_ally_death_passives`), Doom timing, Scapegoat-overload, Grave Clutch, Gallows Writ (a condemned lane becomes an ammunition dump). Corpses over the walls is period-true siege warfare — grim and funny at once.
**Why the rework:** the v1 living-ally throw taxed a body that would have dealt its damage anyway. This version taxes nothing — it converts attrition you were already paying into aimed removal.

### 3. The Pay-Wagon — 2 · creature · STRAY 0/6 · rare
> On-Enter: load up to 20 gold aboard. If it stands when the fight ends, unload it half again heavier. If it dies, the foe plunders it.

**The moment:** your treasury becomes a body on the board — a self-inflicted escort mission. How much do you load, which lane hides it, and do you spend a blocker's round protecting a cart? "They shot my pay-wagon" is a story the player tells for the rest of the run.
**Hook:** gold as a wagered stake (loaded gold should leave the purse Kingpin counts — a cute anti-synergy), sniper/AoE/push threats, Petard-precedent honest gambling.

### 4. The Pallbearers — 2 · creature · DEAD 1/2 · uncommon
> On-Enter: carry one name from the Roll of the Fallen to rest — gain its printed ATK and HP. The name leaves the Roll.

**The moment:** the Roll is currently a resource that only grows — this makes it *spendable*. Bury your fallen Honor Guard into a 3/9 body right now, or keep the name for Muster the Fallen, the camp wake, and the `{fallen}`-gated events? Burying your six-kill veteran "the Grim" to win a General fight is the funeral that wins the battle.
**Hook:** Roll of the Fallen (first card that consumes it), on_enter, Dead tribe. Floor: empty Roll → enters as a plain 1/2 (first fight only, in practice).

### 5. The Gallows Writ — 2 · spell · target lane · rare · Exhaust
> Condemn a lane. At the end of next round, every creature standing in it dies. Exhaust.

**The moment:** Doom for a PLACE — a posted execution date the whole board plays around, except enemy reinforcements march obliviously into the condemned ground. Bait, feed cheap bodies, or deliberately stand your Dead-tribe engines under the noose to harvest their on-deaths at the toll.
**Hook:** lane targeting via `_targeting_spell`, enemy reinforcement placement, on_death dispatch; use the 99+ kill convention so wards don't blank the noose.

### 6. Salted Ground — 1 · spell · target lane · uncommon
> Salt a lane: no enemy may arrive there for 2 rounds.

**The moment:** shapes WHERE the enemy army goes instead of what it is — close one road and the march files into the road you left open, which happens to be dug with Wolf-Pits. Herding is a brand-new verb. Also an honest panic button: salt the lane over your one-HP engine piece.
**Hook:** enemy placement AI (`_place_enemy_card` already takes a lane), reinforcement flow, trap/artillery synergy.

### 7. Body-Snatcher — 2 · creature · DEAD 1/3 · uncommon
> The first enemy to die in this lane rises on your side, in this lane's back row.

**The moment:** suddenly WHERE enemies die matters as much as whether. Steer your strikes and pushes to drop their biggest body in the snatcher's parish. Once-only, and the snatcher must live to collect — the foe's counter-decision (kill the ghoul or starve it) is real.
**Hook:** on_death dispatch, Dead tribe, the removal/push suite as a steering wheel. Robs THEIR graves — the existing graveyard suite only touches yours.

### 8. Scapegoat — 1 · creature · BEAST 0/4 · uncommon
> On-Enter: every wound on a friendly creature passes to this. It can die of them.

**The moment:** one Command tops up your Last Stand veteran mid-fight — then you watch the goat absorb seven wounds, stagger, and drop dead on arrival, which was possibly your plan. A heal with a body, a face, and a funeral.
**Hook:** on_enter, live-HP transfer, Last Stand reset, death economy. Feeds the reworked Mangonel beautifully (an overloaded goat is a heavy shot).

### 9. The Understudy — 2 · creature · STRAY 1/3 · uncommon
> When the friendly ahead of this dies, it steps into the dead one's place and gains its ATK this fight.

**The moment:** he stands in the back row visibly waiting for the man in front of him to die — and in this game, that man will. Park him behind Glass Knight and inherit 4 ATK the same round; behind anything Doomed and the succession has a scheduled date.
**Hook:** ally-death hooks, back-row-as-queue identity, Doom timing; adjacency auras recompute on the advance.

### 10. Mentioned in Dispatches — 1 · spell · common (REWORKED)
> Order a friendly creature to strike now: it deals its ATK to an enemy creature.

**The moment:** an out-of-phase strike — finish a wounded body before the clash resolves, or aim your 9-tally veteran so the tenth notch lands and the war-school modal opens mid-boss-fight. Kill credit is honest: the creature genuinely makes the kill, so veterancy ticks itself with no engine special case.
**Hook:** `effective_atk()`, veterancy kill-counts, the plain damage-spell chassis. UI: two-click targeting (friendly, then enemy) — same small lift as Crossed Orders below.

---

## The Sideways War (6) — lateral movement that matters

Movement matters when it has a **printed payoff on the move** (Lancer, Tower, Flanking Order), when it **rewrites the enemy's line** (Crossed Orders, Hook-and-Chain), or when **lanes carry stakes** — which the rest of the slate supplies (Gallows Writ, Body-Snatcher, Salted Ground, the Mangonel's lane-aimed corpse shots). The payoff bodies also retroactively give teeth to the existing movers (Reposition, Countermarch, Litter-Bearers).

### 11. The Drill-Serjeant — 2 · creature · SOLDIER 1/4 · uncommon
> On-Enter: your creatures wheel one lane to the right. The last lane wraps around to the first.

**The moment:** one bellowed order and the whole formation shunts sideways — the Thorns wall slides into the dragon's lane, the bleeding champion rotates out of the fire, and your far-right anchor teleports to the far-left flank. As an On-Enter it's a timing decision: he's a body AND a formation order, played at the exact round the wheel wins.
**Hook:** on_enter, lane-matchup core combat, `_refresh_adjacency_buffs` (columns shift intact). Triggers every "when this changes lanes" payoff below.

### 12. Crossed Orders — 1 · spell · uncommon
> Two enemy creatures trade places.

**The moment:** the simplest text in the package and the deepest play — drag their aura carrier away from its flock, put the 1-HP survivor in front of your killer, swap the brute onto the Wolf-Pits lane's mouth. One Command, never dead, pure chess.
**Hook:** enemy board manipulation; two-click targeting (small engine lift, shared with Mentioned in Dispatches).

### 13. Wheeling Lancer — 2 · creature · STRAY 2/3 · uncommon
> Whenever this changes lanes, it strikes the enemy now facing it.

**The moment:** the movement package's payoff keystone — every swap, wheel, and flanking order aimed at him becomes a free strike. A deck built around him turns repositioning from bookkeeping into removal, and his placement each round is a question: where does he ride NEXT?
**Hook:** "changed lanes" trigger (new, cheap — fires from any reposition path), Stray opportunist flavor.

### 14. The Rolling Tower — 3 · creature · BASTION 0/7 · rare
> Whenever this changes lanes, the enemy facing its new lane takes 3.

**The moment:** a siege tower on rollers — a wall you steer down the front line, grinding 3 damage into each new lane it enters. With the Drill-Serjeant's wheel or a swap, you're driving a slow, horrible vehicle across the battlefield. The foe must choose: burn it down or keep conceding the lane it rolls into.
**Hook:** the same "changed lanes" trigger, Bastion wall identity with an active job (the wall cycle holds ground; this one *takes* it).

### 15. Flanking Order — 1 · spell · common
> Move a friendly one lane sideways. If its new lane is unguarded, it strikes the foe's face at once.

**The moment:** the gap-hunter — teaches the player to read the enemy line for open roads. Cheap repositioning that CASHES when aimed right, and it makes the enemy's empty lanes (normally dead space) into targets you maneuver toward.
**Hook:** friendly reposition path, face damage, Wheeling Lancer (move him with it and he strikes even in guarded lanes — the package clicks together).

### 16. Hook-and-Chain — 2 · creature · BASTION 1/4 · uncommon
> On-Enter: drag an enemy from an adjacent lane into this one's lane.

**The moment:** the fisherman — deploy him and reel their wall aside so their soft caster stands exposed to your line, or drag the wounded brute in front of your executioner. It's enemy lateral movement WITHOUT the crash physics (no re-tread of the push slate — this is a placement rewrite, not a shove).
**Hook:** on_enter, enemy board manipulation, feeds Gallows Writ / Body-Snatcher lane stakes.

---

## The Bench (strong cuts — one line each)

- **The False Parley** — 2 spell, rare, Exhaust: no enemy strikes this round; their survivors strike twice next round. The loudest bill in the game.
- **Take Them Alive** — 1 spell: seize an enemy at ≤3 HP as a captive — no on-death fires, nobody gets the kill credit, 12g ransom at fight's end.
- **Forged Orders** — 1 spell: the foe's next creature arrives in a lane of your choosing. Placement-shaping like Salted Ground (not a steal — the steal line is dead per verdict).
- **Sworn on the Dead** — 1 spell, rare, Exhaust: slay 3 foes within 2 rounds → +4 max HP; break the oath → take a Wound.
- **Dead Man's Boots** — 1 spell: will a friendly's ATK; when it dies this fight, the nearest friendly inherits it. Lost the inheritance slot to The Understudy.
- **Dead Ox** — 1 spell: raise a 0/4 Dead Ox in an empty ENEMY front slot; fights for the foe but never strikes. Wonderful, confusing.
- **Straw King** — 2, Bastion 0/4: end of each round it stands, the foe's face takes 3.
- **Live Shell** — 3 spell (ticking): 7 damage; costs 1 less per turn held; past 0 it bursts in hand for 5 to your hero. Discard-exempt.
- **Litter-Bearers** — 2, Soldier 1/4, On-Enter: two friendly creatures trade places. Movement-package enabler; build if the package lands.
- **Sidelong Jack** — 2, Stray 3/2: strikes into an adjacent lane of your choice each round (victim never retaliates).
- **Night-Soil Man** — 2, Stray 2/2, Doom 2: deploys into an empty enemy back slot, strikes from behind. Needs the enemy-slot-occupancy primitive.
- **Sleeper Agent** — PARKED: its wait-for-the-moment identity was floop-dependent; needs a new trigger to exist.
- ~~**The King's Shilling**~~ — CUT by verdict: lone arrival-interceptor = telegraphed one-secret problem.

---

## Curation notes

1. **The arrivals stream stays underexploited but the STEAL line is dead** (user verdict: a single card of its kind is telegraphed, like a one-secret Hearthstone class). What survives is placement-shaping — Salted Ground (slate), Forged Orders (bench) — which is honest and visible, no hidden-trap problem.
2. **Floop does not exist.** The toggle mechanic was folded into `on_play` battlecries; CLAUDE.md still documents it (drift — worth a docs pass). All pitched verbs here use On-Enter or persistent triggers.
3. **One new primitive for the movement package:** a "this creature changed lanes" trigger (Wheeling Lancer, Rolling Tower) — one dispatch call in each reposition path. The enemy-slot-occupancy primitive (Night-Soil Man) remains bench-gated.
4. **Two-click targeting** (pick friendly, then enemy) is needed by Mentioned in Dispatches and Crossed Orders — one shared UI lift.
5. **Design-bar compliance:** the reworked Mangonel converts attrition already being paid — it taxes nothing living and respects the no-free-sacrifice rule (nothing is killed by the player; it fires on deaths that happen). No draw-N anywhere; every card is a where/when/whether decision; payoffs land within 1–2 rounds, on a death, or at the fight's final bell.
6. **Net:** solo-first throughout. Denylist candidates: Salted Ground, Forged Orders (arrival hooks), Pay-Wagon/Pallbearers (gold/Roll precedent).
7. **Tribe coverage gap: Warlock still gets nothing.** The movement package feeds Soldier/Stray/Bastion. If this becomes a build slate, commission one spellcraft-flavored piece (e.g. a Warlock whose spells fire from whatever lane it occupies, tying it into the movement theme).
