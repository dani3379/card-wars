# Creature Types — Design Spec (ARRIVE / ENDURE / DIE)

**Status:** IMPLEMENTED & verified 2026-07-15. Product of a two-round adversarial AI
design review (2026-07-14), built the next day. **EXPANDED to SIX tribes 2026-07-15** at user request (they wanted a tribe-richer game — this
knowingly trades the thin-draft payoff-density the review argued for). The 22-card untyped pool
was carved into three new tribes, each with a keystone, so Soldier/Beast/Dead didn't shrink:
- **WARLOCK** (9) — the fire-and-hex casters (witch, hexblade, scholar, ember-mages, apothecary,
  leyline). Keystone **Coven Mother** (`coven_spell`): every spell you cast grows your Warlocks +1
  ATK for the fight. Spellcraft promoted from effect-archetype to a tribe (Pyromancer's home).
- **BASTION** (7) — walls + siege (ironhide_anvil, bramble_stockade, warding_stone, trebuchet, the_leveler, siegewright…).
  Keystone **War Fortress** (`bastion_ramp`): each round it stands, your Bastions ramp +1 ATK — a
  wall-pile becomes a slow siege. Revives Engine, but with a payoff that makes walls *act*.
- **STRAY** (8) — the masterless: assassins, sellswords, treasure-hunters, scavengers,
  shapeshifters. Keystone **Free Company Captain** (id kept as `kingpin` for save/art
  stability) — REWORKED AGAIN 2026-07-24: the tribe was rebuilt on MOBILITY + LARCENY and
  the whole gold spine retired (the 2026-07-15 `type_buff {ctype: "stray", per_gold: 75}`
  aura reached outside the fight into the shop, and was dead weight in skirmish where
  there is no gold economy). The Captain now carries `defection`: when it kills an enemy
  creature it loots one of that corpse's keywords as a persistent grant — see
  `Combat.DEFECTION_STEALABLE` — or free-redeploys when there's nothing worth taking, so
  the moment is never zero. Turn-on: while a Captain stands, every other friendly Stray
  free-redeploys on a kill. Wired in `_stray_defection_active` / `_resolve_defection`,
  called from `_apply_combat_strike_riders` host-side with no `_is_net` guard — larceny is
  skirmish-safe, and the board snapshot carries the stolen keyword to the client. The
  redeploy goes through `_relocate_creature`, which leaves `ready_to_swing` alone (a
  reposition is not a re-muster). **No pool card carries `per_gold` any more** — the
  branch in `_get_type_buff_atk` is gone with it.

Final distribution: Soldier 27 / Beast 27 / Dead 24 / Warlock 9 / Bastion 9 / Stray 8, ~0 untyped.
(The names were chosen over generic Mage/Construct/Outlaw to match the SOLDIER/BEAST/DEAD register.) Verified by `tools/_probe_type_audit.gd` (141 static checks) +
`tools/_probe_type_keystones.gd` (13 runtime checks — all three keystones fire in the
authoritative engine), plus a clean headless compile and green `_probe_stolen_slate` /
`_probe_skirmish_combat`. User steer: **Stalwart is now the Soldier hero** (deck leans
palisade + levy). Note two doc-vs-code corrections found during the build: Siege Golem
grants **Thorns** (not Armored), and `standard_bearer` was **not** a no-op (it already
buffs summoned tokens) — its rework was dropped.

---

## 1. The problem

Every draftable creature already carries a `ctype` (`soldier / beast / dead /
engine / zealot`) printed as a letterpress footer tag, **but only two cards
mechanically read a type** (Warchief's Soldier ATK aura, Siege Golem's Engine→Thorns
grant). Types are inert flavor. Worse, the buckets are incoherent:

- **Beast (28)** and **Soldier (28)** are dumping grounds ("fair bodies").
- **Engine (16)** is a *stat profile* (0-atk high-HP), not a play pattern.
- **Zealot (17)** is really three unrelated things (death-cultists, spell-casters, doom-martyrs).
- **Dead (9)** is the smallest bucket — yet a **~20-card death theme is scattered
  across Soldier/Engine/Zealot** (gravedigger is a Soldier, tallow_doll/blood_pyre
  are Engines, necromancer/carrion_priest/gravecaller/warden_of_graves are Zealots).

The death theme is the most mechanically-supported thread in the pool **and the only
one that gets stronger in this game's fast-death combat** (creatures die in 1–2 turns).
The engine hooks already exist: `_apply_ally_death_passives`, `_trigger_player_sacrifice`
→ `ON_PLAYER_SACRIFICE`, `double_on_death`, Doom counters, the Roll of the Fallen.

## 2. The model — a creature's life-cycle is the tribe

Three types, each keyed to a distinct **moment in a creature's life**. This triad is
*derived from the triggers already in the pool*, not imposed on it — a player feels
each in one sentence.

| Type | Moment | Identity | Reads | Hero |
|------|--------|----------|-------|------|
| **BEAST** | **ARRIVE** | Banks value the instant it lands; doesn't fear death. Aggro/tempo. | on-enter reach (damage/snipe/pull/cast/devour), on-attack | Raider |
| **SOLDIER** | **ENDURE** | Pays you for surviving & standing together. The wide, defensive line. | shields, grow-when-hit, formation/adjacency, last stand, slay-rewards | Stalwart |
| **DEAD** | **DIE** | Death is profit — recur, profit from friendly deaths, fuel each other. The **spine** (~20). | friendly-death triggers, on-death, sacrifice, Doom | Acolyte |

> "Beasts do something the moment they hit the table; Soldiers pay you for keeping
> them alive; Dead pay you for losing them."

**Two archetypes ride on top as effects/keywords — cross-cutting, NOT types.** A card
has one type (or none) *and* may feed an archetype through its effect text:

- **DOOM** (keyword) — creatures on a death-timer. Feeds **DEAD**: they die on schedule
  and trigger death payoffs. (Kindler's fantasy: "everything burns on a timer.")
- **SPELLCRAFT** ("whenever you cast a spell…" effects) — the burn/caster axis, carried
  by effect triggers, not a tribe. (Pyromancer's fantasy: "the spells do the work.")

**UNTYPED NEUTRAL** — cards whose only synergy is an archetype (spell-casters) or none
(pure walls, shapeshifters). No footer tag → splashable goodstuff. This is simultaneously
(a) the honest low-decision curve-filler a thin draft needs, and (b) the fix for
"a stone wall tagged Soldier reads wrong." **A tag now means "I feed a tribe"; no tag
means "splash me anywhere."**

### Why this shape (and not 5, and not more)

A run drafts ~15–25 cards and realistically commits to **one or two** identities.
Five tribes → each is touched by 3–4 cards/run, below the "great at 4+" threshold, so
anthem commons would be dead 80% of the time (violates the house rule *boring = a card
with no decision*). **Three lifecycle tribes + Doom (Dead's keyword) + Spellcraft
(an effect axis) = the right number.** Engine and Zealot are dissolved: they had no
native mechanical identity and diluted a thin draft.

**Validation: the hero fantasies already name these exact axes** — aggro (Raider),
outlast (Stalwart), death (Acolyte), doom-timer (Kindler), spells (Pyromancer). The type
system doesn't add a new fantasy; it makes the ones already printed on the hero cards
mechanically true. (Caveat: current *starter cards* skew Beast, so each hero's tribe is
signalled by fantasy + a couple signature starters, with the real payoff coming from
drafting — consistent with "legible turn 1, committed via draft.")

## 3. Keystones carry payoff; commons stay standalone-good

In a thin draft, **do not** put anthems on commons. Every tribal common must be a fine
card on its own (a good cheap Beast; a Dead that profits when *it* dies), so an off-tribe
pick is never a regret. **2–3 keystones per tribe** (uncommon/rare) deliver the "great at
4+" spike and are where commitment lives.

### New keystones (3 cards + 1 rework)

1. **Gravepact** — c2, 2/4, **Dead**, uncommon.
   *"Whenever a friendly creature dies, summon a 1/1 Wight in your back row (once per round)."*
   Every trade becomes a fresh body — banks instantly, snowballs *because* combat is fast,
   back-row summon keeps it protected, once-per-round kills sac-loops. Plugs directly into
   the existing `_apply_ally_death_passives` funnel. **The card that makes you draft the
   whole death package.**

2. **Warden-Sergeant** — c3, 2/5, **Soldier**, rare.
   *"Formation. While your front row is full, your Soldiers have Armored and Thorns."*
   Full line → the wall grows teeth. Trigger state is built in **one** turn, not three, so
   it pays inside the combat window; it's defensive, so the wide line survives to matter.
   State-derived like Warchief's aura (net-safe via `_get_type_buff_atk`-style recompute).

3. **Bloodmoon Alpha** — c3, 2/4, **Beast**, rare.
   *"Your Beasts' On-Enter effects trigger twice."*
   Doubles goblin's face / naga's poke / dragon's AoE / chaos_imp's spell. Banks per play,
   one concept, the reason to go wide-Beast. (The pool is already ~15 on-enter beasts, so
   this lands with almost no rework.)

4. **Rework `standard_bearer`** (c2 2/3, currently does *nothing* despite the name) → a real
   Soldier formation payoff, e.g. *"Your other Soldiers in this row get +1 ATK"* (adjacency
   aura via the existing `type_buff`/`adj_atk_buff` path).

Existing cards that *already* read death or line — just consolidate them under the new
types, no new code: gravedigger (friendly dies→draw), carrion_priest (friendly dies→drain),
warden_of_graves (on-deaths trigger twice), gravecaller (+1/+1 per fallen), Warchief
(Soldier +1 ATK aura), the_glutton (devour your own Beasts).

## 4. Retype table

Clear cases are decisive; **⚑ = designer judgment call** (safe to flip).

### Dissolve ENGINE (16)
| Card | → | Reason |
|------|---|--------|
| blood_pyre | **Dead** | sacrifice payload |
| tallow_doll | **Dead** | on-death summon |
| ember_stalker (Powder Cart) | **Dead** | Doom on-death AoE + detonate |
| iron_bastion | **Soldier** | Formation wall — holds the line |
| riteforge | **Soldier** | Formation, buffs the whole line (a Soldier payoff!) |
| leyline_conduit | **Soldier** ⚑ | Formation wall (also spell-relevant) |
| siege_golem | **Soldier** | attacker; its "buff other Engines" → "buff other Soldiers" |
| the_leveler | **Soldier** ⚑ | c5 6/6 bomb — anchors a line (or leave untyped as goodstuff) |
| palisade, ironhide_anvil, warding_stone, bramble_stockade | **Untyped** | pure walls, no formation → splashable |
| crystal_sentry, trebuchet | **Untyped** | utility (shield-spreader / face artillery) |

**Wall rule:** walls carrying `formation` → Soldier; pure guardian/thorns walls → Untyped.
Avoids the "boring Soldier wall-pile."

### Dissolve ZEALOT (17)
| Card | → | Reason |
|------|---|--------|
| necromancer, carrion_priest, gravecaller (Oathkeeper), warden_of_graves, mourner, sin_eater | **Dead** | necromancy / friendly-death / curse-debt |
| kindling, burning_martyr | **Dead** | Doom on-death (keep Doom keyword) |
| summoner | **Dead** ⚑ | raises bodies each round |
| bloodsworn | **Dead** ⚑ | blood-cult lifesteal grind (or Soldier-endure) |
| rat_piper | **Beast** | summons a Rat — makes beasts |
| witch, emberwright, ember_warden, hexblade, scholar, cinder_acolyte | **Untyped** | spell/heal-payoff casters — feed the **Spellcraft** archetype, not a tribe |

### Move OUT of BEAST (not beasts)
| Card | → | Reason |
|------|---|--------|
| copycat (Changeling), doppelganger, familiar | **Untyped** | shapeshifters / arcane — synergize with nothing tribal |

### Move OUT of SOLDIER
| Card | → | Reason |
|------|---|--------|
| gravedigger | **Dead** | "friendly dies → draw" is a death payoff |

**Resulting distribution (≈98 creatures):** Dead ~23 (spine, widest — correct), Soldier
~31, Beast ~26, Untyped ~17. Healthy: three ~25–30 tribes + a splashable neutral pool.

## 5. Cuts — for redundancy, NOT for "vanilla"

The review's first instinct ("purge ~9 French-vanilla bodies") was **wrong** — the pool
has almost no true vanilla (naga/sprite/goblin/adaptable/duelist all carry triggers). Cut
for **sameness**, and respect the **starter contract**:

- The on-enter-poke cluster — goblin (1 face), brute (1 opposing), naga (2 opposing),
  bloodhound (1 opposing + draw) — overlaps. **But goblin/brute/naga are load-bearing hero
  starters** (Raider/Stalwart/Acolyte), so only **`bloodhound`** (pure common) is freely
  cuttable, or differentiate it instead. Net: **at most 1 cut.**
- Keyword-bodies (troll, plague_rat, basilisk, mule, levy_rider, pressed_man) are the honest
  curve-filler — **keep all.**

**Scope honesty:** the license to "destroy half the cards" turned out to be unnecessary.
The pool already plays to these three patterns; it just needs to start *reading* `ctype`.
This is a retag + wiring pass (~40 tag edits, 3 new cards, 1 rework, ≤1 cut), not a teardown.

## 6. Implementation checklist

1. **CardDB.gd** — update `ctype` per §4; remove the field entirely for Untyped cards.
   Add the 3 keystones to `CARD_POOL` + `UPGRADES`; set `"art"` stand-ins.
2. **Card2D.gd** — `_build_chart_proto` footer must render **no tag** when `ctype == ""`
   (today every card has one; the empty case is new). Verify with a windowed shot.
3. **Combat.gd string reads of the dying types** — `censer_light` reads `"zealot"`
   (Combat:~1818) and the zealot-lifelink spell reads a zealot bench (Combat:~7209). Migrate
   both to **`"dead"`** (cult→Dead). Rework `siege_golem`'s on-enter (Engines→Soldiers).
   Wire Gravepact into `_apply_ally_death_passives`; Warden-Sergeant + reworked
   standard_bearer via the state-derived `type_buff`/`adj_atk_buff` path.
4. **Net parity** — type auras are already state-derived (net-safe). Gravepact's death-summon
   must fire host-side like other on-death passives (mirror the necromancer/warden pattern in
   `CombatNet`). Bloodmoon Alpha's "on-enter twice" is host-side on-enter (net-safe by construction).
5. **Doom** — confirm Doom deaths route through the same friendly-death funnel so they feed
   Gravepact / carrion_priest / gravedigger.
6. **Probes** — extend `tools/_probe_type_audit.gd` with asserts (every creature is one of
   {soldier,beast,dead,""}; no engine/zealot tags remain; each keystone reads a type). Re-run
   `_probe_stolen_slate`, `_probe_balance`, and a headless parse-check.

## 7. Open judgment calls for the user

- **⚑ walls**: formation walls → Soldier, pure walls → Untyped (as specced) — or push *all*
  walls Untyped to keep Soldier lean?
- **⚑ Dead size**: bloodsworn/summoner/the_leveler flagged — flip any to trim Dead from ~23 → ~20.
- **Stalwart**: currently a Beast-heavy "endure" deck (troll/naga/palisade). Give it retyped
  Soldier starters so the wall hero reads as the Soldier tribe, or leave the ENDURE fantasy
  shared across Beast(regen)+Soldier(wall)?
- **Spellcraft**: leave as an effect-only archetype (recommended), or eventually give the
  caster shell one untyped keystone ("when you cast a spell, all your creatures +X")?
