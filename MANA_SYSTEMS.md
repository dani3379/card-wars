# Card-Game Resource ("Mana") Systems — Complete Catalog

Every resource model used in card games, organized by **where the resource comes from /
what you pay with**, plus the **cross-cutting axes** that combine with any model. Named
examples for each. Built from existing research (cited) + the systems those taxonomies miss.

**Prior research this builds on:**
- [Rempton Games — "A Re-Source of Pride"](https://remptongames.com/2017/07/20/a-re-source-of-pride-designing-resource-systems-in-collectible-games/) — design blog, 5 categories (Mana / Energy / Tributing / Flexible Pitch / Automatic Ramp).
- [arXiv — "A Taxonomy of Collectible Card Games from a Game-Playing AI Perspective"](https://arxiv.org/html/2410.06299v1) — academic, 4 categories (Incremental Mana / Resource Cards / Discard-Based / No Resource).
- [critpoints — "How Magic's Mana System Divides its Design Space"](https://critpoints.net/2023/05/10/how-magics-mana-system-divides-its-design-space/), [Game & Tech Focus — TCG Resource System](https://gameandtechfocus.com/tcg-resource-system/), [Otto Suwen — Resource Systems in TCGs](https://medium.com/@ottosuwennft/resource-systems-in-tcgs-6d87d4397a4d), and forum threads ([BGG LCG](https://boardgamegeek.com/thread/1608046/lcg-alternative-resource-systems), [MTGSalvation](https://www.mtgsalvation.com/forums/magic-fundamentals/magic-general/785789-the-tcgs-ccgs-that-have-a-better-resource-system)).

Both published taxonomies are correct but coarse — they fold "fixed pool," "split/dual,"
"economy," "action-point," "time/cooldown," and "pay-with-life/board" into other buckets or
omit them. The full picture is below.

---

## PRIMARY MODELS — what you pay with

### A. Dedicated resource cards *in your deck*
You draw/play cards whose job is to make resource.
- **A1 — Lands / power, tapped, color-gated** *(the "Mana System")* — dedicated cards you play 1/turn, tap to produce typed mana that's consumed. **MtG, Hex, Spellweaver, Eternal (power), WoW TCG.** ⚠ flood/screw variance.
- **A2 — Separate resource pile/deck** — resource lives in its own stack you flip from, so it can't flood/screw your draws. **Eikonics (flip 1/turn), the common "10-card mana deck" homebrew, Lord of the Rings LCG (resource tokens per hero).**
- **A3 — Resource attached to units** *(the "Energy System")* — units play free; you attach 1 energy/turn to them, type-gated, and it's **lost when the unit dies.** **Pokémon TCG.** ⚠ snowbally (losing a powered unit loses the investment).

### B. *Any* card can become a resource (cards-as-resources)
- **B1 — Pitch / face-down / burn** — spend a card from hand as fuel instead of playing it. **Duel Masters (any card face-down, 1/turn), Flesh and Blood (pitch for 1/2/3 by card), Mythgard (burn any card for a "gem").** Kills flood/screw; adds "which card do I sacrifice as fuel?" decisions; ⚠ reduces card-to-card variety (every card is also generic fuel).

### C. Automatic pool that GROWS each turn (incremental / ramp)
- **C1 — +1 per turn to a cap, refilled** — **Hearthstone (→10), Elder Scrolls Legends, Shadowverse, Duelyst, Stormbound, PvZ Heroes, Legends of Runeterra.** Early scarcity → curve decisions; late = abundance.
- **C2 — = turn number** — energy literally equals the turn count. **Marvel Snap (1→6 over 6 turns), Legends of Code & Magic.**
- **C3 — + banked carryover** — unspent resource saves for later (a sub-mode of C1/C2). **LoR "spell mana" (bank up to 3).**
- **C4 — + borrow-from-future** — gain extra now, locked next turn. **Hearthstone Overload (Shaman).**
- **C5 — + board-generated mana** — extra resource from things on the board. **Duelyst mana springs/tiles, Faeria (gather + land-based faeria).**

### D. Automatic pool that is FIXED each turn (no ramp)
- **D1 — Fixed N/turn, use-it-or-lose-it** — same pool every turn, refilled, no growth. **Slay the Spire (3 energy), Griftlands, *Burning Meadow (current: 3 +1 bank).*** Snappy, no curve; ⚠ if cards are cheap → "play everything" (no scarcity).
- **D2 — Fixed N/turn with carryover/banking** — as D1 but you can save. Rare; some roguelike deckbuilders.

### E. Real-time / continuously regenerating
- **E1 — Resource refills over real time** (not per-turn). **Clash Royale (elixir), most lane-pusher "card" mobile games.** Tempo = when, not whether.

### F. NO quantity resource — gated by *plays/actions* instead
- **F1 — One play/summon per turn** — the hard cap is the number of deploys. **Yu-Gi-Oh (1 Normal Summon/turn), Gwent (~1 card/turn).**
- **F2 — Action points / "clicks"** — a small budget of *actions* spent on anything (play, draw, attack). **Android: Netrunner (3–4 clicks/turn), Flesh and Blood (action points in combat).**
- **F3 — Faction/house gate per turn** — each turn pick ONE faction; you may only play/use cards of that faction. **KeyForge (choose 1 of 3 houses/turn).** The "resource" is the house choice.
- **F4 — Card advantage as the whole economy** — no pool; your scarce thing is *cards over the match.* **Gwent (limited hand across 3 rounds; spending cards efficiently is the game).**

### G. Pay with your own game state (creatures / corpses / life / cards)
- **G1 — Tribute / sacrifice your creatures** — cost is *bodies.* **Yu-Gi-Oh (tribute), Inscryption (Blood — sacrifice creatures), MtG (sacrifice costs, Convoke = tap creatures for mana).**
- **G2 — Corpses / deaths as resource** — spend things that have died. **Inscryption (Bones), MtG (Delve/Escape from graveyard).**
- **G3 — Life as resource** — pay HP to play. **MtG (Phyrexian mana, pain-lands, "pay X life"), blood-mage designs.**
- **G4 — Discard as cost** — pitch cards from hand as a cost (distinct from B1: here it's an extra cost on top of mana). **Various (madness, discard-to-activate).**

### H. Accumulated flexible currency (economy)
- **H1 — Bankable credits spent on anything** — a money pool you grow and spend freely. **Android: Netrunner (credits).**
- **H2 — Cards generate buying power** — play cards to make "money," buy more cards. **Deckbuilders: Dominion (Treasure→coins), Star Realms (trade), Ascension (runes), Slay-the-Spire-adjacent shops.**
- **H3 — Gold income + interest** — economy with savings incentives. **Autobattlers: TFT, Hearthstone Battlegrounds, Storybook Brawl.**
- **H4 — Shop gold + in-combat cooldowns** — split economic/combat resource. **The Bazaar.**

### I. Time / cooldown as the resource
- **I1 — Per-unit attack/charge counters** — units act every N turns; you manipulate the timers. **Wildfrost (Counter), auto-chess attack timers.**
- **I2 — Item cooldowns** — each card/item fires on its own cooldown. **The Bazaar (combat).**

### J. No cost at all — a different constraint entirely
- **J1 — Every card free; constraint is leveling/other** — no resource; cards *level up* as you play them, and the limit is how many plays/turn. **SolForge (2 plays/turn, cards level).**

---

## CROSS-CUTTING AXES — these combine with any primary model

1. **Growth profile:** ramping (C), fixed (D), real-time (E), or none (F/G/H). *The single biggest feel lever.*
2. **Banked vs use-it-or-lose-it:** unspent carries over (LoR spell mana, banking variants) vs evaporates (most). Banking enables "save for a big turn."
3. **Single vs SPLIT / dual resources** — two parallel currencies for different actions:
   - **Shadowverse** — Play Points (play cards) **+** Evolution Points (evolve).
   - **Netrunner** — Clicks (actions) **+** Credits (money).
   - **Flesh and Blood** — Pitch (resource) **+** Action Points.
   - **Inscryption** — Blood (sacrifice) **+** Bones (deaths).
   - **LoR** — Unit mana **+** banked Spell mana.
   - **MtG** — generic amount **+** colored requirement.
4. **Quantity vs TYPE/affinity gate** — a "what kind" requirement layered on "how much":
   - **Consumed color** (MtG — colored mana is spent), vs
   - **Threshold / not consumed** (Hex, Eternal "influence" — you must *have* the color, but it isn't spent), vs
   - **Type-locked attach** (Pokémon energy types), vs **class/deckbuild identity** (Hearthstone).
5. **Self-driven vs opponent-driven** — your pool set by *your* plays vs by the opponent's. **Lord of the Rings TCG (Twilight pool is largely dictated by the opponent's plays)** — rare shared/contested resource.
6. **Manipulation layer** — bolt-ons that exist in many systems: ramp/acceleration (rituals, mana rocks), cost reduction, refund/untap, borrow (Overload), conversion.

---

## The honest summary of the design space

There are really only a handful of *root* questions, and every game is a point in this space:
1. **Does resource come from your deck (A/B), an automatic clock (C/D/E), your board/life (G), or nothing-but-actions (F)?**
2. **Does it grow, stay flat, or not exist?**
3. **One pool or two?**
4. **Is there a type gate on top of the amount?**
5. **Does unspent resource bank or vanish?**

Published taxonomies (Rempton's 5, arXiv's 4) only really cover question 1's top branches. The
fuller catalog above is questions 1–5 crossed.

---

## Relevance to Burning Meadow (the "you play your whole hand" problem)

BM today is **D1 — fixed pool, use-it-or-lose-it (3 mana), no type gate, single pool** — the
*least* scarce model, which is exactly why a cheap-card hand gets fully dumped. The models that
specifically create a "you can't/shouldn't play everything" decision:
- **F1 (one deploy/turn)** — caps *plays*, not mana. The most direct fix; Yu-Gi-Oh lineage.
- **C (ramp)** — early scarcity forces curve decisions (Hearthstone/Snap), at the cost of copying that feel.
- **G1 (sacrifice-to-play)** — the board self-limits and every play has a body cost; **Inscryption is the creature-roguelike precedent** and the most thematically on-brand for a sacrifice-flavored game.
- **B1 (pitch)** — playing a card costs another card, so the hand drains itself; strong "which do I spend as fuel" decisions.
- **Split/dual (axis 3)** — give creatures one currency and spells/abilities another so they compete.

The ones that *don't* fix it: staying on D1, or any model where cheap cards + ample pool let you
empty your hand.
