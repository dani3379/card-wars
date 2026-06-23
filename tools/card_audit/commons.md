# Common-Creature Balance Audit — "Burning Meadow"

Scope: **every `rarity == "common"` CREATURE** in `scripts/data/CardDB.gd` (24 of them). Spells are out of scope. Starters and hero-deck cores are *intentionally* modest — where a common doubles as a hero core (per `HeroDB.gd`) it is flagged and handled gently.

Budget standard: vanilla body (ATK+HP, no effect) = `cost*2+2` → 1c=4 · 2c=6 · 3c=8. A premium keyword/effect (Swift, Ranged, Poison, Piercing, Summon, draw, ramp, removal) buys **−2 to −3 body**; a minor effect **−1**. A card is "bad" only when a weak body is paired with a **weak/situational/anti-synergistic** effect — the body alone never condemns a card.

All effects below were read from the live resolvers (`Combat.gd` `_resolve_on_play_ability` ~line 1600+, the `passive ==` checks ~line 3100–4430, and `KeywordEffects.gd` dispatchers), not from card descs.

---

## Summary table — the weak ones, worst first

| id | verdict | one-line fix |
|---|---|---|
| `scavenger` | **UNPLAYABLE** | Drop gold-on-enter; make it a 1c 1/2 that draws when it dies (corpse-scavenger), or a Swift 2/1 raider-loot body. |
| `mana_sprite` (Errand Sprite) | **UNPLAYABLE** | Net-zero ramp. Make the Command gain **persist next turn** OR bump to gain 2 (real ritual ramp), keep 0/2 body. |
| `torchbearer` | **weak-for-cost** | Wither makes its own anchor rot. Drop Wither; make it a 1c 0/3 Formation banner (+1 ATK adj, *grows* instead of decays). |
| `tallow_doll` | **weak-for-cost** | Enabler with a dead floor. Give the first copy a body (1c 1/3) and make stacking summon a 1/1 Doll token so a lone copy still does something. |
| `stone_wall` | **bland** | Redundant with `warding_stone`. Differentiate: give it Structure-lite "blocks the whole column" or fold it into `warding_stone` and cut. |
| `cinder_pup` | fine (gentle) | Protected Kindler core; heuristic-flagged only. Leave, or +1 HP (2/2) if Kindler early game tests soft. |

Everything not in this table is judged **FINE** — listed explicitly at the bottom for coverage.

---

## 1. `scavenger` — UNPLAYABLE

- **Current:** cost 1 · 1/2 · keywords `[]` · *"On-Enter: gain 5 gold."*
- **Real effect:** `on_enter:gain_gold value:5` → `RunState.gain_gold(5)`. Purely economic; **zero board impact**. (`eff_report` pdelta +0.5 is a *lie* — it scores 5 gold as if it were a combat keyword.)
- **Verdict:** UNPLAYABLE in a deckbuilder where you draft for the *fight*, not for gold. 5 gold = one-tenth of a common in the shop. You spent a card, a draw, and a Command to put a 1/2 vanilla body on the board and gain less than a single combat tick of value. The "no dead rewards" pillar applies to cards too: a creature whose entire text is irrelevant the moment a real threat is across is a dead draw. Nobody mid-run keeps this.
- **Why it fails:** the gold is divorced from combat, the body is below a 1c vanilla (3 < 4), and there is no payoff loop (no "spend the gold *now*" verb in a fight). Textbook "enabler with no payoff," except it doesn't even enable anything inside the fight.
- **Redesign (pick one):**
  - **A — corpse-looter (Acolyte/Owed home):** cost 1 · **1/2** · keywords `[on_death]` · *"On-Death: gain 5 gold and draw 1."* Now it rewards the death-economy decks that already throw bodies away, turns into card advantage, and the gold becomes a bonus instead of the whole point. Reuses the existing `draw` on-death dispatch + `gain_gold`.
  - **B — raider loot (Raider home):** cost 1 · **2/1** · keywords `[swift]` · *"Swift. On-Enter: gain 3 gold."* A real aggressive body (Swift trades in the pre-phase) that *also* pays you. The gold shrinks to 3 because the body now carries the card. Fits Swift→Raider.

---

## 2. `mana_sprite` (Errand Sprite) — UNPLAYABLE

- **Current:** cost 1 · 1/2 · keywords `[]` · *"On-Enter: gain 1 Command this turn."*
- **Real effect:** `on_play:gain_mana value:1` → `player_mana += 1` (same turn only; no carryover stamp). You pay **1 Command** to play it and get **1 Command** back. **Net zero.** You have spent a card and a draw to place a 1/2 body for free — which is fine if a free 1/2 mattered, but it never does, and the "ramp" is a complete illusion.
- **Verdict:** UNPLAYABLE. This is the canonical fake-ramp trap. Real ramp must put you *ahead* on resource; this only breaks even, and in exchange you burned a card. The body (1/2, budget 4, has 3) is below curve on top of it.
- **Why it fails:** "enabler with no payoff" in its purest form — it enables nothing because the resource it returns is exactly the resource it cost. There is no turn where playing it advances your board *and* your Command. Compare the Acolyte's Pyre/ritual loop, which actually converts.
- **Redesign (pick one):**
  - **A — real ritual ramp:** cost 1 · **0/2** · keywords `[]` · *"On-Enter: gain 2 Command this turn."* Now it nets **+1** Command (you spent 1, get 2) — a genuine "play this, then play a 3-drop on turn 2" enabler. Drop ATK to 0 so it's a pure ramp body, not a beater; the +1 net is the premium and the 0-ATK pays for it. Acolyte/ritual home.
  - **B — banked ramp (cleaner):** cost 1 · **1/2** · keywords `[]` · *"On-Enter: gain 1 Command. It carries to next turn."* Stamp the gained Command so it survives the `MAX_BANKED_MANA` upkeep (the carryover machinery already exists). Net zero *this* turn but a Command in the bank = a real tempo bump on a future turn, and it keeps a small body. Either reading turns a dead card into a deckbuilding tool.

---

## 3. `torchbearer` — weak-for-cost (anti-synergy)

- **Current:** cost 1 · 1/3 · keywords `[adj_buff, wither]` · Wither 1 · *"Adjacent friendlies +1 ATK. Wither 1."* · `adj_buff:{atk:1,hp:0}`
- **Real effect:** grants +1 ATK to same-row/column neighbours (the `adj_buff` aura), AND **loses 1 ATK every round** (Wither, `KeywordEffects.dispatch_start_of_round`). It starts at 1 ATK, so after **one round it is a 0/3** — a do-nothing wall that still buffs, but its own offense is gone immediately.
- **Verdict:** weak-for-cost, and worse, **internally contradictory.** A static anthem-buffer wants to *stay on the board* for many rounds; Wither is the keyword for a card you want to *cash out fast* (Doom/sacrifice fodder). Bolting them together means the longer it does its job (anthem), the more it visibly rots, and the player feels punished for a card that's supposed to be a patient support piece. The `eff_report` "−0.5" discount for Wither (it scores Wither as *worth +2 body*, i.e. a drawback) is exactly backwards for a support unit — Wither is pure downside here.
- **Why it fails:** anti-synergy (anthem ↔ Wither pull in opposite directions); the body (1/3 = 4, on budget) carries an effect that *degrades itself*; and the +1 ATK aura is the weakest band of the adj-buff family (no HP, no keyword grant). It is a worse Battle Drummer (uncommon 1/3 +adj that doesn't rot).
- **Redesign:** cost 1 · **0/3** · keywords `[formation, adj_buff]` · `formation:1` · `adj_buff:{atk:1,hp:0}` · *"Formation. Adjacent friendlies get +1 ATK."* Drop Wither entirely (the anti-synergy). Make it a **0-ATK banner** that *grows* via Formation when flanked (the wall-banner role the Last Wall/Stalwart deck wants), so a support piece that lives long now gets *better*, not worse — the mechanically-correct inversion of the current design, and it leans the positional 4×4 pillar.

---

## 4. `tallow_doll` — weak-for-cost (enabler with a dead floor)

- **Current:** cost 1 · 1/2 · keywords `[]` · *"Gets +1/+1 for each other Tallow Doll you've played this fight."* · `passive:tallow_stacking`
- **Real effect:** on placement, `+= _tallow_dolls_played` to both ATK and HP (`Combat.gd:4406`). The **first** Doll you play gets +0 (a vanilla 1/2). The 2nd is 2/3, the 3rd 3/4, etc. — but **only if you've drawn and played the earlier copies first**, in order.
- **Verdict:** weak-for-cost as a single card. The floor is a 1/2 vanilla (body 3 < budget 4) that does *nothing* on its own, and the payoff requires drawing multiple copies of a *common* and sequencing them — a build-around with no support and a completely dead solo state. Drafted one at a time, it is almost always the worst card you could take.
- **Why it fails:** classic enabler-without-a-payoff and "no floor." A build-around common needs either (a) a way to find its copies, or (b) a baseline that isn't a dead draw. Tallow Doll has neither — a lone copy is strictly a 1c 1/2 vanilla, below curve.
- **Redesign:** cost 1 · **1/3** · keywords `[]` · *"On-Enter: if you've played another Tallow Doll this fight, summon a 1/1 Tallow Doll token. Gets +1/+1 for each other Doll played this fight."* Two changes: (1) bump the floor to 1/3 (on-budget body, survives a ping), and (2) the second copy onward **spawns a 1/1 token** (reuse `summon_token(1,1,...)`), so the engine *widens the board* as it stacks — a real go-wide payoff that uses the empty 4×4 lanes — instead of pouring everything into one fragile stat-stick. Now even a 2-Doll hand does something visible, and the build rewards commitment without bricking on a single draw.

---

## 5. `stone_wall` — bland (redundant)

- **Current:** cost 1 · 0/5 · keywords `[thorns]` · *"Thorns. Can't attack. Reduces face damage from adjacent empty lanes by 1."* · `passive:cannot_attack_wall`
- **Real effect:** a 5-HP body that cannot attack, deals 1 Thorns back to attackers, and (per `_wall_face_reduction`, `Combat.gd:3107`) shaves 1 face damage per adjacent empty lane. Functional defensively.
- **Verdict:** bland — not *bad*, but it is a strictly-worse twin of **`warding_stone`** (same cost 1, same 0/5 body, same wall passive, same Thorns) which **also has Guardian** (forces adjacent enemies to attack it). For 1 Command you would never pick Stone Wall over Warding Stone; they are the same card minus a keyword. Two near-identical commons is wasted design space, and the `eff_report` +3.5 "over-statted" reading is right that the raw 0/5+wall is strong — the problem is it's *duplicated*.
- **Why it fails:** it isn't underpowered, it's **redundant** — it fails the "every card earns its slot" bar. A draft that offers Stone Wall next to (or instead of) Warding Stone is offering a downgrade.
- **Redesign (pick one):**
  - **A — give it a distinct job (column blocker):** cost 1 · **0/5** · keywords `[thorns]` · *"Thorns. Can't attack. While this stands, the enemy directly across can't attack either."* A *lockdown* wall (pins one attacker via a `frost`-style "can't attack" flag on the opposing front, reusing the existing can't-attack state) vs. Warding Stone's *taunt* wall — now they pull in different directions and both deserve a slot.
  - **B — cut & merge:** delete `stone_wall`, keep `warding_stone` as the one common wall. Cleanest if no distinct identity is wanted; frees a draft slot for a new common with a real role.

---

## 6. `cinder_pup` — fine (handle gently — protected Kindler core)

- **Current:** cost 1 · 2/1 · keywords `[doom]` · Doom 2 · *"Doom 2. Bred to burn."*
- **Status:** `eff_report` flags it (pdelta **−1.5**, the worst-scoring common), because Doom is scored as a *−0.5 drawback* and the body is 3. **But this is a `HeroDB` Kindler starter-deck core (×2 in the deck).** Per the audit rules, hero cores are intentionally baseline-modest and not flagged.
- **Real effect:** Doom 2 → after 2 rounds it deals its ATK (2, +any buffs) to enemy face and dies (`KeywordEffects` doom detonation, pre-Overrun). It's a cheap 2-power fuse the Kindler deck *wants* to throw — a 2/1 that guarantees ≥2 to face is on-theme and the body is fine for a 1-drop bomb.
- **Verdict:** **fine — leave it.** The negative heuristic is an artifact of scoring Doom as a flat drawback; in the Kindler shell Doom is the *point*, not a tax. Only if Kindler's early game tests too soft, bump to **2/2** (so it survives one ping and reliably detonates) — a gentle +1 HP, no identity change. Do **not** strip Doom.

---

## FINE — judged playable, no change (coverage)

These commons sit at or near curve with effects that justify their bodies. Brief rationale each:

- **`hound`** (1c 1/2, On-Enter deal 2 to a random enemy) — a 1c that removes a 2-HP threat or chunks a bigger one *and* leaves a body. Strong tempo. Fine.
- **`bloodhound`** (1c 1/1, On-Enter deal 1 opposing + draw 1) — cantrip-creature; replaces itself and pokes. Fragile body is paid for by the draw. Fine.
- **`raven`** (1c 2/1, Ranged + snipe back 2) — Pyromancer core; reaches the protected back row turn one. Fine.
- **`hexblade`** (1c 1/3, Ranged + `atk_per_spell`) — Pyromancer core; scales with every spell cast (retroactive on enter, `Combat.gd:4393`). `eff_report` +3.0 confirms it's *strong* in its shell. Fine.
- **`lookout`** (1c 2/1, Swift + `vanguard_split`) — Raider core; placement choice (front = +1 ATK / back = draw 1). Fine.
- **`plague_rat`** (1c 1/1, Poison) — Poison is premium removal-on-a-stick; the 1/1 is the correct price for "kills anything it touches." Fine. (Could note: a 1c Poison body is a real combo piece with buffs — leave as the cheap entry point.)
- **`gravedigger`** (1c 1/2, draw on first ally death/round) — capped at **1 draw per round** (`_friendly_deaths_this_round == 1`, `Combat.gd:3142`), which keeps it honest in the Acolyte death-deck. A repeatable cantrip engine. Fine.
- **`ash_hound`** (1c 2/1, Rampage) — Kindler core; snowballs on kills. Fine.
- **`kindling`** (1c 1/2, Doom 2 + On-Death deal 2 face) — Kindler core; guaranteed 2-to-face fuse with a usable body. Fine.
- **`crystal_sentry`** (2c 2/2, Shield + grant adjacent Shield) — effectively two Shields across two bodies for 2 Command; Shield is premium. Fine.
- **`shieldbearer`** (2c 1/4, Armored) — durable early blocker; Armored on a 4-HP body eats small attackers for free. Fine.
- **`pikeman`** (2c 2/3, `shove_back` 2 — never a dead play, falls back to 2 damage) — solid tempo + the positional shove pillar. Fine.
- **`harpy`** (2c 2/2, Swift + `haul_front` 1) — Swift body that drags a hidden back-line support into the open. Uses position. Fine.
- **`thornguard`** (2c 1/4, Thorns + On-Death deal 1 to all enemies) — wall + a parting AoE; `eff_report` +1.0. Fine.
- **`squire_captain`** (2c 2/3, Summon → 1/1 adjacent) — 5 stats across two bodies + board width for 2 Command, on the empty-lane pillar. Fine.
- **`lancer`** (2c 2/3, Overrun 2) — Overrun fires when the enemy front lane across is empty (`KeywordEffects:213`), giving +2 ATK on an open lane; a real aggro/Grasswake payoff that reads the board. Fine.
- **`burning_martyr`** (2c 2/3, Doom 3 + On-Death deal 1 all enemies) — Kindler core; a slow fuse that also sweeps tokens on death. Fine.
- **`warding_stone`** (1c 0/5, Guardian + Thorns wall) — the *good* wall (taunt + thorns + face reduction); intentionally the strong one of the wall pair. Fine. (See `stone_wall` §5 for the redundancy note — the fix lives on Stone Wall, not here.)

---

### Cross-cutting notes for whoever implements
- The three UNPLAYABLE/weak ones (`scavenger`, `mana_sprite`, `torchbearer`) share one disease: **effects that don't touch the fight** (gold), **net-zero resource loops** (ramp that breaks even), and **self-defeating keyword pairings** (anthem + Wither). All three redesigns above re-aim the card at a real in-combat payoff and an existing hero home.
- `tallow_doll` and `stone_wall` are *coherent but under-supported / redundant* — they need a floor and a distinct identity, not a stat bump.
- Every redesign reuses machinery that already exists (`summon_token`, `formation`, `on_death:draw`/`gain_gold`, carryover-Command stamp, the can't-attack flag) — no new resolver types required except optionally Stone Wall's column-lock, which can ride the existing frost "can't attack this round" state.
- Don't touch `cinder_pup`'s Doom — it's a protected core and the negative heuristic is a scoring artifact.
