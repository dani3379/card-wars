# Premium-Tier Creature Audit — Burning Meadow

Scope: every **uncommon** and **rare** `type:"creature"` in `CardDB.CARD_POOL`. Goal: find cards that are UNPLAYABLE, weak-for-cost, or **BLAND** (an uncommon/rare that plays like a vanilla common — rarity is supposed to buy you a premium, exciting card), and propose concrete redesigns that fit the curve and a design pillar.

Curve reference (vanilla body, no effect) = `cost*2+2`: 1=4 · 2=6 · 3=8 · 4=10 · 5=12. Uncommon/rare MAY run +1 over. Effects discount the body: minor ≈ −1, premium (Swift/Ranged/Poison/Piercing/Summon/draw/ramp/removal) ≈ −2 to −3.

All verdicts below were checked against the **real resolvers** in `Combat.gd` / `KeywordEffects.gd`, not just the heuristic `eff_report.txt`. Counts: 34 uncommon creatures, 16 rare creatures audited.

---

## Summary table — worst first

| id | rarity | cost/atk/hp | verdict | one-line fix |
|---|---|---|---|---|
| `warchief` | rare | 4 · 0/6 | **UNPLAYABLE** | Make it the engine, not the body: a real cost-3 lord whose ATK = friendlies AND that buffs the team; give it Formation so it survives. |
| `witch` | uncommon | 2 · 2/3 | **BLAND** (vanilla) | Stop being a worse Errand Sprite. Turn it into a spell-payoff body: ranged ping + a discover/refund. |
| `mule` | uncommon | 1 · 1/3 | **BLAND / weak** | A 1/3 "next card −1" is a common-tier filler. Make it a true cost-cheat engine (token + carryover discount) or fold its job into a relic. |
| `blood_pyre` | uncommon | 1 · 1/3 | weak-for-cost | One-shot +2 ATK to two neighbors that kills itself = a worse Sprite for the same job. Make the sacrifice pay the deck, not one round. |
| `summoner` | uncommon | 2 · 1/3 | **BLAND** (Summon-only) | A keyword-only twin of the common Squire Captain. Differentiate: summon on a *clock* or summon something with a body. |
| `battle_drummer` | uncommon | 2 · 1/3 | weak / fragile | A 1/3 anthem dies to any ping and the buff evaporates. Give the buff Formation-style permanence or armor the drummer. |
| `revenant` | uncommon | 2 · 2/3 | borderline-bland | "Reborn once at 1 HP" on a vanilla body is quiet. Make the second life *do* something (enter buffed, or a deathrattle on the resurrection). |
| `royal_guard` | uncommon | 3 · 2/5 | fine, slightly dull | Keep — but the aura+grow is real. Consider promoting clarity (currently reads as vanilla on the card). |
| `leyline_conduit` | uncommon | 2 · 0/4 | fine (niche) | Keep. Ramp engine; 0-ATK is the intended fragility tax. |
| everything else | — | — | **fine / strong** | See per-card notes; several uncommons (duelist, griffin, scholar, glass_knight, the_glutton) are over-curve and good. |

The four headline blands you flagged are all confirmed. `warchief` is the only truly *unplayable* card in the premium tiers. Three rares to keep an eye on for being **over**-statted (not a focus, noted at the end): `assassin`, `corpse_eater`, `the_leveler`.

---

# RARES

## 1. `warchief` — **UNPLAYABLE** ★ headline fix

- **Now:** cost 4, 0/6, no keywords. *"Start of each round: this creature's ATK becomes the number of friendly creatures on the board."* (`passive: warchief_aura`)
- **Resolver truth** (`Combat.gd:1334` start-of-round, `:4398` on-enter): `current_atk` is **set** (not added) to `_all_player_creatures().size()`, counting itself. Upgrade adds +1 to that number. It enters as a 0/6 and does **nothing** the turn you play it except on round-start recompute.
- **Verdict: UNPLAYABLE.** This is the worst card in the file (`pdelta −2.5`, the only −2.5). For **4 Command** — a cost that requires mana-banking — you get a 0/6 that:
  - Deals **zero** the turn it lands (start-of-round only).
  - Needs a *wide* board to have any ATK, but a wide board is exactly when you *don't* need one more vanilla beater — and going wide is the hard part the Warchief does nothing to help.
  - With a typical 3-creature board it's a 4-Command **3/6 that can't attack the turn you play it**. A common 2-cost Pikeman (2/3 + shove) outperforms it on tempo. The fantasy ("warlord who gets stronger with his army") never fires because it's a follower, not a leader.
- **Redesign — make it the LEADER, not another body.** Drop to cost 3 (it should be castable without banking) and give it a real aura so a wide board is rewarding *and* it helps you get there:

  > **Warchief** — cost **3**, **2/6**, keyword **Formation**.
  > *"Formation. Start of each round, this gains +1 ATK for each other friendly creature. Other friendlies have +1 ATK while this lives."*
  >
  > - Enters as a usable **2/6 wall** that grows; Formation (`+1/+1 if a friendly stands beside it`) means it thickens and survives to keep commanding — fits the **Last Wall / Stalwart** Formation home.
  > - The **team +1 ATK aura** makes a go-wide board snowball *through* the Warchief, delivering the "warlord" payoff the current card promises but can't pay.
  > - Body+aura math: a 2/6 with a team buff at cost 3 is premium-rare appropriate (compare `riteforge` 2 · 0/5 ramp at cost 2-rare). The self-grow is the cherry.
  > - **+ upgrade:** aura becomes +1/+1 (was +1 ATK), or self-grow counts the Warchief too.

  This turns the headline dud into a genuine board-anchor finisher and gives Stalwart's Formation deck a marquee rare.

## 2. `riteforge` — **fine** (good rare)
- cost 2, 0/5, Formation, `riteforge_ramp`: every round all friendlies get +1 ATK permanent (+2 upgraded). 0-ATK is the deliberate "it's an engine, not a beater" tax. Strong, distinct, has a clear home. Keep.

## 3. `hydra` — **fine / strong**
- cost 3, 3/6, `attacks_all_lanes` (resolver `:2229` → `_resolve_hydra_attack`, takes thorns back from each). A 3/6 that hits all four opposing lanes is a premium board-clear engine. `pdelta +2.5` but the all-lane attack also eats thorns/retaliation, so the body tax is earned. Keep.

## 4. `corpse_eater` — **fine** (note: over-statted)
- cost 2, 2/3, Piercing + `grow_on_ally_death` (+1 ATK per friendly death). `pdelta +2.5`. A 2/3 Piercing that snowballs in a sacrifice deck is great and on-theme. Slightly hot for a 2-drop but Piercing wants a board to point at; acceptable. **Watch** for over-performance in Acolyte sac decks; if it dominates, trim to grow capped or 2/2 base.

## 5. `doppelganger` — **fine**
- cost 3, 3/4, `copy_last_dead`. A 3/4 floor with copy upside is a fair rare. Fine.

## 6. `vampire_lord` — **fine / strong**
- cost 3, 3/4, Regenerate + Slay heal 2/+1 ATK (resolver `:2538`). Sustain + snowball, premium and distinct. Keep.

## 7. `warden_of_graves` — **fine / strong**
- cost 2, 2/4, `double_on_death` (all your On-Death triggers fire twice). A build-around payoff at a fair body. Excellent rare. Keep.

## 8. `siege_golem` — **fine** (niche)
- cost 3, 3/5, `siege`: only deals (face) damage through an **empty** opposing column (`:2234`); blocked entirely if anything stands opposite. A 3/5 body for 3 is fine even when blocked; the face-rush upside is real vs thin boards. Keep — it's a deliberate situational wall-breaker.

## 9. `dragon_hatchling` — **fine / strong**
- cost 4, 4/5, Swift + On-Enter deal 2 to all enemies. `pdelta +2.5`, premium and exciting — exactly what a rare should feel like. Keep.

## 10. `doom_knight` — **fine / strong**
- cost 4, 5/4, Piercing + Swift + Doom 2. A glass-cannon bomb finisher; reads premium. Keep.

## 11. `the_leveler` — **fine** (note: over-statted)
- cost 5, 6/6, Piercing + On-Enter deal 3 to all. `pdelta +3.5`. It's a 5-drop top-end haymaker so a big number is intended, but 6/6 + Piercing + a 3-damage board-wipe is a lot of rate. **Watch**: if 5-drops feel auto-include, trim to 5/6 or On-Enter 2. Not a focus; leaving as-is.

## 12. `cinder_whelp` — **fine / strong**
- cost 3, 5/4, Doom 2 + On-Death deal 3 to all. Pyre payoff, premium. Keep.

## 13. `treasure_hunter` — **fine**
- cost 3, 2/4, On-Enter Discover a **rare**. Jackpot value on a real body. Fine.

## 14. `assassin` — **fine** (note: over-statted / fragile)
- cost 2, 5/1, Swift + `dies_end_of_turn` (`:3214`, takes 999 at end of round) + On-Enter execute (destroy opposing creature with ≤2 HP). `pdelta +3.5`. It's a one-round Swift assassinate — huge burst but evaporates, so the rate is balanced by impermanence. Keep; the body number looks scary but the self-death pays for it.

---

# UNCOMMON CREATURES

## 15. `witch` — **BLAND** (vanilla uncommon) ★ headline fix
- **Now:** cost 2, 2/3, no keywords, *"On-Enter: gain 1 Command."* (`on_play: gain_mana 1`)
- **Resolver truth:** identical effect to the **common** `mana_sprite` (Errand Sprite, 1 · 1/2, "gain 1 Command"), just on a slightly bigger body for +1 cost. The mana is refunded immediately, so this is effectively a **vanilla 2/3 for 2** (`pdelta −1.0`) — a French-vanilla common wearing an uncommon frame. Nothing about it says "premium."
- **Verdict: BLAND.** Rarity failure. A 2/3 with a self-refunding mana ping is the textbook "uncommon that feels like a vanilla common."
- **Redesign — lean into the spell-matters / arcane identity:**

  > **Witch** — cost 2, **1/4**, keyword **Ranged**.
  > *"Ranged. On-Enter: gain 1 Command. The first spell you cast each turn costs 1 less."*
  >
  > - Now it's a genuine **spell engine** body (Pyromancer/back-line **Ranged** home), not a one-shot ramp. The recurring spell discount gives a reason to keep it alive — a real board presence with ongoing payoff.
  > - 1/4 Ranged survives in the back row to keep discounting; the On-Enter Command still smooths the turn you drop it.
  > - Body math: 1/4 = body 5 for cost 2, then Ranged (−2) + recurring discount (−1) ≈ a premium uncommon at the curve. Exciting and distinct from Errand Sprite.
  > - Alt (simpler) version if you want to avoid a per-turn discount: *"On-Enter: gain 1 Command and Discover a spell"* on a 2/3 — turns the dead ramp into card selection. Either reads as a premium.

## 16. `mule` — **BLAND / weak** ★ headline fix
- **Now:** cost 1, 1/3, no keywords, *"On-Enter: the next card you play this turn costs 1 less."* (`on_play: discount_next 1`)
- **Resolver truth** (`_card_cost_discount`, `:4096`/`:4157`): sets a 1-charge, this-turn-only −1 discount on your next non-zero-cost card. So a 1-Command 1/3 that hands back 1 Command on your *next* play = roughly mana-neutral with a vanilla 1/3 body left over. The body is a 1/3 (body 5, `pdelta +0.0`) but the "effect" is nearly free *and* nearly worthless — it's a wash that doesn't even reliably net tempo (if your next card already fits your mana, the discount does nothing).
- **Verdict: BLAND / weak-for-cost.** A cost-cheat that doesn't actually cheat on cost. Feels like common filler at best. The fantasy ("a mule that carries your load") never lands because one −1 charge is invisible.
- **Redesign — make it a real cost-cheat engine you build around:**

  > **Mule** — cost 1, **1/3**, no keywords.
  > *"On-Enter: summon a 0/1 Pack token in an empty lane. The next two cards you play this turn cost 1 less."*
  >
  > - Two discount charges (was one) is a felt tempo swing — enough to actually *enable* a double-spell or a banked-mana 4-drop turn. That's the build-around payoff an uncommon owes.
  > - The 0/1 Pack token gives immediate board width (chump/Guardian-bait/`grow_on_*` fuel) so it's not a wash even when the discount is wasted.
  > - Stays cheap and low-stat — its job is enabling, but now the enabling is **visible and stackable**.
  > - **+ upgrade:** discount the next *three* cards, or the token is a 1/1.
  > - Alt direction if you'd rather it be a body: cost 1, **0/4**, *"Banked Command is not lost at end of turn while this lives"* (an Ice-Cream-on-a-stick) — a control/ramp engine. Pick whichever fits the deck list better.

## 17. `blood_pyre` — **weak-for-cost** ★ headline fix
- **Now:** cost 1, 1/3, no keywords, *"On-Enter: sacrifice this creature. Adjacent friendlies get +2 ATK this fight."* (`on_play: blood_sacrifice 2`)
- **Resolver truth** (`:2114`): buffs same-row neighbors at lanes ±1 by +2 ATK (permanent this fight), then `_trigger_player_sacrifice(self)` + `take_damage(999)`. So it's a one-card +2/+2-spread-across-two-neighbors that consumes itself and a card. Compare the **starter** `sprite` (1 · 1/2, "+1 ATK to adjacent this **round**") — Blood Pyre is permanent and +2, but it **dies**, so net board is −1 creature. The starter Sprite stays.
- **Verdict: weak-for-cost / borderline-bland.** It's a slightly-better-Sprite that pays its body as the cost, for an uncommon slot. The *only* premium thing about it is that it's a free sacrifice trigger (Bone Pile / Soul Lantern / `ON_PLAYER_SACRIFICE`), which is real in Acolyte — but as a standalone card it's a feel-bad. `eff_report pdelta +0.0` confirms a vanilla-grade body with a self-eating effect.
- **Redesign — make the sacrifice pay the *deck*, not one combat round:**

  > **Blood Pyre** — cost 1, **2/2**, no keywords.
  > *"On-Enter: sacrifice this creature. Adjacent friendlies gain +2 ATK this fight, and you draw a card."*
  >
  > - Adding **draw 1** turns it from "I traded a card+body for a temp buff" into a genuine *sacrifice-engine* card: it cantrips, so it replaces itself, AND it's still a sacrifice trigger for Bone Pile / Soul Lantern. That's the premium an Acolyte build wants.
  > - 2/2 (was 1/3) so if you ever *don't* want to pop it on-enter… it still pops on-enter (it's mandatory), but the bigger ATK means the +2 buff source feels meatier and it threatens for 2 the instant before it goes.
  > - Body+effect math: cost-1, sacrifices itself for (spread +2 ATK **+ draw**) is a fair uncommon — the draw is what lifts it above the starter Sprite.
  > - **+ upgrade:** +3 ATK to neighbors (already the existing `blood_pyre` +), keep the draw.
  > - Keep it 1-cost — it's deliberately deck-glue for `owed`/Acolyte; the draw makes it premium-grade glue instead of a tax.

## 18. `summoner` — **BLAND** (keyword-twin of a common)
- **Now:** cost 2, 1/3, Summon, *"Summon."* (keyword-only)
- **Resolver truth:** Summon = on-play, summon a 1/1 in an adjacent empty lane (`KeywordEffects:110`). This is **mechanically identical** to the **common** `squire_captain` (2 · 2/3, "Summon.") except with a *worse* body (1/3 vs 2/3). An uncommon that is a strictly-worse-bodied copy of a common is a rarity failure. `pdelta +0.0`.
- **Verdict: BLAND.** Two cards, same keyword, and the uncommon is the weaker one. There's no reason to draft this over the common.
- **Redesign — give Summon a premium twist (a clock or a real body):**

  > **Summoner** — cost 2, **1/3**, keyword **Summon**.
  > *"Summon. At the start of each round, summon a 1/1 token in an empty lane."*
  >
  > - Now it's a **recurring** token engine (a Hearthstone-"Imp Gang Boss"/ "Summoning Portal" feel), not a one-shot — that's the build-around an uncommon should be, and it feeds go-wide / `grow_on_*` / sacrifice payoffs every turn.
  > - Body stays fragile (1/3) so killing it matters — the enemy is taxed to shut the engine off, which is exactly the tension you want from a premium summon card.
  > - Distinct from common Squire Captain (one token, bigger body) — they now occupy different roles.
  > - **+ upgrade:** tokens are 1/2, or summons two on the turn it enters.

## 19. `battle_drummer` — **weak / fragile**
- **Now:** cost 2, 1/3, Adj. Buff, *"Adjacent friendlies +2 ATK."* (`adj_buff {atk:2}`)
- **Resolver truth:** aura grants +2 ATK to live left/right neighbors while it lives; vanishes the instant it dies. A **1/3** anthem dies to literally any 1-damage ping or a single attack, taking the whole +4 swing with it. `pdelta −0.5`.
- **Verdict: weak-for-cost / fragile.** The effect (+2 ATK to two neighbors) is genuinely strong *in the abstract* — it's the survivability that's the problem. As printed it's a glass anthem that the enemy removes for free, so it rarely banks more than one round of value. Borderline bland because the "premium" is theoretical.
- **Redesign — protect the engine so the aura is reliable:**

  > **Battle Drummer** — cost 2, **1/4**, keywords **Armored** + **Adj. Buff**.
  > *"Armored. Adjacent friendlies have +2 ATK."*
  >
  > - **Armored** (−1 to each hit, min 1) on a 4-HP body means it actually *survives* a round of pressure, so the +2 anthem reliably pays — turning a feel-bad glass card into a real backbone for go-wide decks.
  > - Body math: 1/4 = body 5, Armored (−1) + a +2 two-neighbor anthem (−2 to −3) → fair premium uncommon at cost 2.
  > - Back-row placement + Armored makes it a protected anchor — uses the 4×4 board (you want it behind the line). On-pillar.
  > - **+ upgrade:** +3 ATK aura (existing `battle_drummer` +), keep Armored.

## 20. `revenant` — **borderline-bland**
- **Now:** cost 2, 2/3, On-Death, *"On-Death: this creature returns to play at 1 HP (once per fight)."* (`on_death: reborn`)
- **Resolver truth:** `reborn` returns it to its lane at 1 HP once per fight. So you get a 2/3 that effectively has ~5 effective HP spread across two lives — but the second life is a 2/**1** that any ping kills, and it does nothing special on return. `pdelta +0.0`.
- **Verdict: borderline-bland.** It's basically Last Stand with extra steps, on a vanilla body, for an uncommon. Not bad, but not exciting — it reads as "a 2/3 that's slightly stickier," which is common-tier feel.
- **Redesign — make the resurrection *do* something so it's a payoff, not just durability:**

  > **Revenant** — cost 2, **2/3**, On-Death.
  > *"On-Death: this creature returns to play with +1 ATK and deals 1 damage to all enemies (once per fight)."*
  >
  > - The rebirth now **triggers a payoff** (a small AoE + comes back angrier as a 3/1), so dying is something you *want* to engineer — pairs with sacrifice/ping decks and with `warden_of_graves` (double On-Death = it returns twice / double AoE). That's a premium build-around.
  > - Keeps the "dies and comes back" fantasy but gives the second life teeth.
  > - **+ upgrade:** returns with +2 ATK / 2 AoE, or returns at full HP.

## 21. `royal_guard` — **fine** (slightly dull, optional clarity bump)
- cost 3, 2/5, `royal_guard`: adjacent friendlies take −1 dmg (`_has_adjacent_royal_guard`, `:2495`) AND it gains +1 ATK each time it's hit (`:2529`). Two real effects on a tanky body — that's a legit defensive uncommon and it's in Stalwart's starting deck. `pdelta +0.5`. **Keep.** Minor note: on the *card* it reads almost vanilla (no keyword chips); the effects are good but quiet. Not a redesign target — just flagging that its premium-ness is invisible until you read the text.

## 22. `leyline_conduit` — **fine** (niche ramp)
- cost 2, 0/4, On-Enter +1 Command + `mana_per_turn` (+1 max Command per turn while alive, `:1410`). A dedicated ramp engine; the 0 ATK is the intended fragility/opportunity tax. `pdelta −0.5` is fine because permanent ramp is premium. **Keep.**

## 23. `the_glutton` — **fine / strong**
- cost 2, 2/3, Overrun + `glutton_devour` (On-Enter: destroy adjacent friendlies, +2/+2 each — and their On-Death fires, `KeywordEffects:455`). A high-skill tempo/payoff card (Marvel Snap Carnage). `pdelta +1.5`. Premium and distinct. **Keep.**

## 24. `husk` — **fine / strong**
- cost 2, 1/5, Guardian + `grow_on_any_death` (+1/+1 per friendly death, `:10162`). A snowballing Guardian wall in a sacrifice/attrition deck. `pdelta +3.0` — strong but the body is slow and needs a death engine. **Keep.**

## 25. `iron_bastion` — **fine / strong**
- cost 3, 1/7, Armored + Formation + `reduce_face_damage` (−1 to all face damage, `:3110`). A premium control linchpin; in Stalwart's deck. `pdelta +3.5`. **Keep.**

## 26. `shieldmaiden` — **fine**
- cost 2, 1/4, Guardian + Formation. Two defensive keywords on a fair body; grows with Formation if flanked. Clean uncommon. **Keep.**

## 27. `standard_bearer` — **fine**
- cost 2, 2/3, `standard_bearer_summon` (first 1-cost creature each turn summons a 1/1, `:4419`). A go-wide payoff engine. **Keep.**

## 28. `the_apothecary` — **fine**
- cost 2, 1/4, `plague_doctor` (each enemy death → 1 to enemy face, `:10106`). A poison/attrition reach payoff. **Keep.**

## 29. `emberwright` — **fine / strong**
- cost 2, 2/3, Ranged + `ember_per_spell` (each spell → 1 to face, `:5260`). Spell-matters reach on a back-line body (Pyromancer home). `pdelta +2.0`. **Keep.**

## 30. `cleave_hound` — **fine**
- cost 2, 2/3, `cleave` (on attack, also 1 to adjacent opposing). A wide-damage attacker that uses the board. **Keep.**

## 31. `necromancer` — **fine**
- cost 2, 1/3, On-Death summon a 2/2 (`:188`). A sticky value body. `pdelta −1.0` heuristically, but a 2/2 token on death is genuinely premium (it replaces the body), so the low stats are correct. **Keep.**

## 32. `basilisk` — **fine / strong**
- cost 2, 1/4, Poison. A tanky removal-on-a-stick (anything it touches dies). Premium keyword, fair body. **Keep.**

## 33. `duelist` — **fine / strong** (over-curve, good)
- cost 2, 2/3, Swift + On-Enter deal 2 to opposing. `pdelta +2.5`. Premium tempo. **Keep.**

## 34. `griffin` — **fine / strong** (over-curve, good)
- cost 2, 2/3, Swift + On-Death return-to-hand once. `pdelta +2.0`. Recurring Swift threat — excellent. **Keep.**

## 35. `scholar` — **fine / strong**
- cost 2, 2/3, Ranged + On-Enter Discover a spell. `pdelta +2.0`. Tempo + value. **Keep.**

## 36. `glass_knight` — **fine / strong**
- cost 2, 3/1, Shield + Swift. A burst glass-cannon; Shield buys it one hit. `pdelta +1.5`. **Keep.**

## 37. `paladin` — **fine / strong**
- cost 3, 3/4, Last Stand + Adj. Buff (+1 ATK). Sticky anthem. `pdelta +2.0`. **Keep.**

## 38. `ironclad_veteran` — **fine**
- cost 3, 3/4, On-Enter +1 ATK per card played this turn. A combo-turn payoff. **Keep.**

## 39. `adaptable` (Sellsword) — **fine / strong**
- cost 2, 3/3, On-Enter choose Swift/Piercing/Armored/Thorns (`choose_keyword`, `KeywordEffects:450`). Flexible premium body. `pdelta +1.5`. **Keep.**

## 40. `vengeance` — **fine / strong**
- cost 1, 1/3, Overrun + `vengeance_growth` (+2 ATK whenever you take face damage). A snowball that punishes the enemy for racing you. `pdelta +2.5`. **Keep.**

## 41. `chaos_imp` — **fine**
- cost 1, 1/2, On-Enter cast a random spell free (auto-targeted). High-variance value gamble. **Keep.**

## 42. `familiar` — **fine**
- cost 1, 1/2, On-Enter Discover a creature, + a buff-the-pick floop. Cheap selection on a body. **Keep.**

## 43. `copycat` (Changeling) — **fine** (niche)
- cost 1, 0/1, On-Enter copy a chosen friendly (`copy_friendly`, `:396`). `pdelta −1.5` because the 0/1 body is intentional — it *becomes* the copy. A combo/value enabler (copy your best creature). Niche but legitimately premium when it works. **Keep** — the low body is the cost of the effect, not a flaw.

## 44. `berserker` — **fine** (over-curve)
- cost 2, 3/3, `grow_on_attack` (+1 ATK each round it attacks) + takes +1 dmg from all. `pdelta +2.0`. A snowball-with-a-downside; the extra-damage taken is a real lever. **Keep.**

---

# PYRE SET (Kindler) — uncommons

## 45. `hellfire_imp` — **fine**
- cost 2, 3/2, Swift + Doom 2. A fast bomb that swings before it bursts. `pdelta +0.5`. On-theme premium. **Keep.**

## 46. `ember_stalker` — **fine / strong**
- cost 3, 3/3, Swift + Rampage 2. Snowball killer. `pdelta +1.0`. **Keep.**

## 47. `bloodsworn` — **fine**
- cost 2, 3/3, Lifelink. A clean aggressive body with sustain. `pdelta +1.0`. **Keep.**

## 48. `cinder_acolyte` — **fine**
- cost 2, 2/3, Ranged + Lifelink. Back-line sustain. `pdelta +1.5`. **Keep.**

## 49. `ember_warden` — **fine**
- cost 2, 1/4, `feeds_on_doom` (+2 ATK each time one of your creatures detonates, `:2413`). A Doom payoff body. `pdelta +0.5`. **Keep.**

---

# Cross-cutting findings

1. **The rarity-failure pattern is "common effect on a slightly-bigger body."** All four headline blands (`witch`, `mule`, `blood_pyre`, `summoner`) are uncommons whose effect already exists, often better, on a **common** (`witch`≈`mana_sprite`, `summoner`≈`squire_captain`, `blood_pyre`≈starter `sprite`). The fix in every case is to give the uncommon a *recurring* or *build-around* version of the effect, not a one-shot. That's the single rule that separates a premium card from filler here.

2. **`warchief` is the only genuinely unplayable card in the premium tiers** and the highest-value fix. It promises a marquee "warlord" fantasy and delivers a 0/6 that can't attack the turn you bank 4 Command for it. The redesign (cost-3 Formation lord with a team aura) also fills a real gap: **Stalwart's Formation deck has no rare finisher.**

3. **Fragility, not effect strength, breaks `battle_drummer`.** Its +2 anthem is strong; a 1/3 body just can't carry it. Armoring the engine is a recurring lever (`royal_guard`, `iron_bastion`, `husk` all survive *because* they're tanky) and `battle_drummer` should join them.

4. **A few rares are over-statted** (`assassin` 5/1, `corpse_eater` snowball, `the_leveler` 6/6+wipe). None are *broken* — each has a real downside (impermanence, needs a death engine, 5-cost) — but they're the cards to watch if premium picks start feeling auto-include. Not redesigned here; flagged only.

5. **Pillar adherence in the redesigns:** Witch → Ranged (Pyromancer/back-line home); Warchief & Battle Drummer → Formation/Armored back-line (4×4 board, Last Wall home); Mule & Summoner → token generation feeding go-wide/sacrifice payoffs; Blood Pyre → sacrifice-engine with a draw payoff (Acolyte home). None add a do-nothing enabler — every redesign carries its own payoff.
