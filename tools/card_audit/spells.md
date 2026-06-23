# Spell Audit & Redesign Dossier — *Burning Meadow*

**Scope:** all ~55 draftable spells (CardDB `"type":"spell"`, excluding the two un-playable curses `curse`/`wound`). Each was read against its **resolver** in `Combat.gd` (`_resolve_custom_spell`, line 4649) — not the auto-analyzer, which scores every custom spell as value 0 because the real magnitude lives in the resolver.

**Method:** I read every spell's `desc`, its resolver branch, and its `"+"` UPGRADES delta. Balance anchor used throughout:
- **1-cost damage benchmark:** deal 3 single-target or deal 3 face (`strike`, `fireball`, `flame_bolt`). So "deal 2 to one creature for 1 Command, no upside" is below rate.
- **0-cost spells** must either be low-impact, carry a real cost (HP/Curse/discard), or be a cantrip (replaces itself by drawing).
- Removal / board-clear / draw / ramp justify more Command.
- The design brief: the **4×4 board is under-used** — reward push/pull, back-row reach, and lane AoE over "deal N to one target." Don't ship enablers with no payoff.

> **Important framing:** This is a roguelike *draft* pool, not a constructed ladder. The bar for "cut it" is **"would a player ever pick this over the other two cards on a reward screen, in some deck?"** Several spells below are individually mediocre but are genuine *archetype payoffs* (discard, sacrifice, spell-count). Those I flag as "narrow, keep" rather than "cut." The genuinely **unpickable** ones are the small list at the very top.

---

## Summary table (worst → best; FINE cards listed but not detailed)

| id | cost | verdict | one-line fix |
|---|---|---|---|
| `dark_pact` | 1 | **UNPLAYABLE** | strictly worse `overwhelming_force` *and* `war_cry`; you pay HP to under-buff. Re-home as a 0-cost "this fight" ramp-buff or cut. |
| `quick_shot` | 0 | **weak (redundant)** | deal-1 cantrip is near-zero impact; make it a back-row snipe (Ranged-flavored: hits a random **back-row** enemy, draw 1). |
| `soul_swap` | 0 | **weak / trap** | swing tool with no guard rails — usually helps the enemy. Make it target **enemy only** (turn a 5/1 into a 1/5) or friendly-only combo. |
| `blood_tithe` | 0 | **weak-for-cost** | strictly worse than `flame_bolt`/`fireball` once you've cast one spell; you pay 2 HP for 3 face. Drop self-damage or raise to 4 face. |
| `bloodletting` | 0 | **redundant** | one of three near-identical "pay to ramp" 0-drops; differentiate (see ramp cluster) — make it the *burst* one (lose 2 HP, gain 3). |
| `frost_bolt` | 0 | **weak** | single-lane "can't attack" is marginal vs simultaneous combat; widen to also **shove** the frozen creature back, or freeze its whole row's front. |
| `shove` | 0 | weak-for-effect | underused position tool; lean in — actually **push to back row** (it only debuffs ATK today, doesn't move anything). |
| `holy_smite` | 1 | situational/redundant | execute that needs pre-damage; fold into the removal suite — let it hit for missing HP **or** 3, whichever is higher. |
| `turbo` | 0 | trap-ish | adds a permanent Curse for 2 Command — almost never correct. Make the Curse temporary (exhausts at end of fight) or raise payoff. |
| `lay_on_hands` | 1 | weak | overheal + max-HP on one body rarely matters in fast fights; bundle a cleanse or give the target Regenerate. |
| `patch_up` | 1 | weak (heal) | full-HP draw rider is a hoop; merge the heal-line so it always cantrips a little. |
| `mending_light` | 1 | weak (heal) | Lifelink+1 ATK on one creature is low tempo; make it grant Lifelink to **a lane** or heal you for the creature's ATK. |
| `shield_wall` | 1 | borderline | +4 HP & Thorns one round is fine but forgettable; let Thorns persist the fight or hit a lane. |
| `provision` | 0 | borderline | 1/1 token for a card+Exhaust is thin; base should be 2/1, or place it Guarding. |
| `pillage` | 1 | fine (econ) | gold-on-slay is a clean econ Strike; keep. |
| `war_cry` | 1 | fine | +1 ATK & Swift board-wide is a real combat trick; keep. |
| `gambit` | 0 | fine (filter) | free dig; keep. |
| `recycle` / `scrap` | 0 | fine (filter/ramp) | keep; minor overlap, see filter cluster. |
| `slash` / `concentrate(Immolate)` / `smite_spell` | 1/1/2 | fine | clean removal ladder; keep (see removal cluster — differentiate `slash` vs `pillage`). |
| `flame_bolt` / `fireball` / `strike` | 1 | fine (benchmarks) | the on-rate anchors; keep. |
| `reckless_charge` | 1 | fine | Strike + draw at 1 HP cost; keep. |
| `hex` | 1 | fine (tech) | 2 dmg + strip keywords is real removal-tech; keep. |
| `ambush` | 1 | fine | 1-to-all + Swift-synergy; keep (Raider). |
| `inspire` / `overwhelming_force` / `kings_command` / `battle_hymn` | 2/3/2/2 | fine | the anthem ladder; keep (minor overlap, see anthem cluster). |
| `inferno` / `earthquake` / `cataclysm` / `mass_grave` / `plague_bell` / `apocalypse` / `wildfire` | 4/2/3/1/1/3/2 | fine | the AoE/board-clear suite; keep. |
| `banish` / `time_snare` | 2/2 | fine | premium answers; keep. |
| `unholy_bargain` | 0 | fine | premium draw at HP cost; keep. |
| `charge_spell` | 1 | fine (combo) | spread a fat attacker across lanes; keep. |
| `war_chant` | 0 | fine (payoff) | discard→bodies payoff; keep. |
| `offering` / `fuel_the_pyre` | 0/1 | fine (sac payoff) | the sacrifice outlets; keep. |
| `grave_pact` / `grave_robbery` / `reanimate` | 1/1/1 | fine (recursion) | death-matters payoffs; keep (see recursion cluster — partial overlap). |
| `venom_tip` / `censer_light` | 1/1 | fine (keyword grant) | Poison / Lifelink enablers; keep. |
| `echo_spell` | 1 | fine (combo) | spell-matters payoff; keep. |
| `lost_tome` / `war_council` | 1/2 | fine (discover) | tutors; keep. |
| `hoarfrost` | 1 | fine | Shield + freeze opposing; keep. |

---

# TOP TIER: the cards nobody would play (fix or cut)

### 1. `dark_pact` — **UNPLAYABLE (redundant + actively bad)**
- **Cost 1 · targeting none.** Desc: *"All friendlies get +1 ATK this fight. Take 2 face damage."*
- **Resolver (4710):** `for c in _all_player_creatures(): c.current_atk += 1` (a real *this-fight* permanent buff via `current_atk`), then `damage_player_hero(2)`.
- **Verdict: UNPLAYABLE.** It is **strictly dominated** twice over:
  - `overwhelming_force` (cost 3) gives **+3 ATK this fight** with no HP cost. At 1/3 the buff for 1 Command that's defensible — *except* you also **pay 2 of your 25 HP**, and the buff only applies to creatures **already on board** (no future creatures, since it edits `current_atk` in place). Against an empty/thin board it does almost nothing.
  - `war_cry` (cost 1) gives **+1 ATK this round AND Swift** board-wide for the *same* Command and **no HP cost**. Swift (trade up before they hit) is worth more in a single combat than a permanent +1 that you bled for.
- **Why it's a trap:** the only thing `dark_pact` has over `war_cry` is "this fight" instead of "this round," but it pays 2 HP and drops Swift to get there. In a game where normal fights end in 2–3 rounds (per the pacing note), "this fight" rarely outvalues Swift even once.
- **Redesign — make it the *aggressive ramp* card it wants to be:**
  > **Dark Pact** — Cost **0** · none · *"Take 2 damage. Your creatures get +1 ATK this fight."*
  At 0 Command the HP becomes the real cost and it stops competing with `war_cry`. `+` → **+2 ATK this fight** (the existing `dmg_bonus:1` already does this). This makes it a genuine glass-cannon enabler instead of a worse anthem.
  - *Alt (positional, on-brief):* keep cost 1 but reach the back line — *"Take 2 damage. Deal 4 damage split among the enemy back row."* — turns the self-harm into reach the board otherwise lacks.

### 2. `quick_shot` — **weak (negligible impact + redundant with the cantrip suite)**
- **Cost 0 · targeting any.** Desc: *"Deal 1 damage to any target. Draw 1."*
- **Resolver (4870):** 1 damage to target (or face if none), then draw 1. `+` → deal 2, draw 2.
- **Verdict: weak/redundant.** It's a free cantrip, so it's never *dead* — but 1 damage is below the noise floor (most creatures are ≥2 HP; 1 to face is a rounding error). It competes with `scrap`, `adrenaline`, `gambit`, `recycle` for the "free, draws/filters" slot and loses to all of them on impact. A free "draw 1, ping 1" is a deck-thinner, not a play.
- **Redesign — give it the back-row reach the board is missing (Ranged identity, Pyromancer/back-line home):**
  > **Quick Shot** — Cost **0** · none · *"Deal 2 damage to a random enemy back-row creature (or enemy face if the back row is empty). Draw 1."*
  Now it's a Ranged-flavored cantrip that punishes the enemy's protected back line — something *no other 0-cost does* — while staying a thinner. `+` → 3 damage, draw 1.

### 3. `soul_swap` — **weak / trap (no guard rails)**
- **Cost 0 · targeting any_creature.** Desc: *"Swap a creature's ATK and HP."*
- **Resolver (4766):** reads `effective_atk()`, writes `current_hp = old_atk`, `current_atk = old_hp` (buff layers stripped on write-back).
- **Verdict: trap.** On *your own* creatures it's a niche combo (turn a 5/1 glass cannon into a 1/5 wall, or vice-versa). On *enemies* it's usually a **gift** — most threats are higher-HP-than-ATK (e.g. a 1/4 wall becomes a 4/1 attacker that now murders you). The card invites the wrong play and most of the time the "correct" use is "don't." A 0-cost that's a downgrade more often than not is a non-pick.
- **Redesign — pick a lane and commit. Best as enemy-facing soft-removal:**
  > **Soul Swap** — Cost **0** · enemy_creature · *"An enemy creature swaps its ATK and HP. (Turn a wall into a glass jaw.)"*
  Restricting to enemies makes it a *defanging* tool: a 1/6 Guardian becomes a 6/1 you can trivially trade with, and a 5/2 attacker becomes a 2/5 that hits like wet paper. That's a real, readable answer at 0 Command. `+` → cost 0, also deal 2 to that creature after the swap.

### 4. `blood_tithe` — **weak-for-cost (dominated face burn)**
- **Cost 0 · none.** Desc: *"Deal 3 damage to enemy face. Take 2 damage yourself."*
- **Resolver (4669):** `damage_enemy_hero(3 …)`, `damage_player_hero(2)`.
- **Verdict: weak.** 3 face for 2 of your own HP is a *net –? race tool*. Compare `fireball` (1 Command, 3 face, no self-damage) and `flame_bolt` (1 Command, **5** face if you've cast a spell, no self-damage). `blood_tithe` saves you 1 Command but costs 2 HP — in a deck doing 25-HP-race math that's a bad trade, and it doesn't even ping creatures.
- **Redesign — make the 0-cost actually worth the blood:**
  > **Blood Tithe** — Cost **0** · none · *"Deal 4 damage to enemy face. Take 1 damage yourself."*
  4-for-1-HP-at-0-Command is a real aggro accelerant (and pairs with the Pyre/`vengeance` self-damage payoffs). `+` (`dmg_bonus:2`) → 6 face. *Alt:* keep 3 face but make the self-damage feed something — *"...Take 2 damage. Your creatures get +1 ATK this round."*

### 5. Ramp cluster — `bloodletting` / `turbo` / *(plus `scrap`/`adrenaline`)* — **redundant 0-cost ramp**
Four spells all answer "spend a free card to get Command now." They badly overlap:

| id | does | net |
|---|---|---|
| `bloodletting` (0) | lose 1 HP → **+2** Command | +2 Command, –1 HP |
| `turbo` (0) | **+2** Command, add a **permanent Curse** to discard | +2 Command, –1 future draw forever |
| `scrap` (0) | discard 1 card → **+1** Command | +1 Command, –1 card |
| `adrenaline` (0, Exhaust) | **+1** Command, **draw 1**, Exhaust | net 0 cards, +1 Command, one-shot |

- `adrenaline` (net-neutral on cards, +1 Command, exhausts away so it doesn't clog later) is the clean one — **fine, keep.**
- `bloodletting` is the highest burst (+2) but the others creep on it.
- **`turbo` is a trap:** +2 Command for a *permanent* Curse is almost never worth it — the Curse is a dead draw for the rest of the run, far outweighing one turn of +2 Command. (`+` makes it +3 Command, still a hard sell.)
- **Redesign — differentiate the lane:**
  - **`bloodletting`** → the **burst** option: *"Lose 2 HP. Gain 3 Command."* (`+`: lose 2, gain 4.) Pays more HP for the biggest single-turn spike — the explicit "I'm comboing off RIGHT NOW" button. Distinct from scrap's card-cost ramp.
  - **`turbo`** → make the Curse **temporary**: *"Gain 2 Command. Add a Cinder to your hand (a 0-cost Curse that Exhausts at end of fight)."* — so the downside is *this fight only*, turning a trap into a fair burst. (Requires a temp-curse token; if that's too much plumbing, instead: *"Gain 2 Command. Discard a card."* — pay a card you have, not a card forever.)
  - **`scrap`** stays the **filter-ramp** (pitch a dead card for Command) — fine, but see filter cluster.

### 6. `frost_bolt` — **weak (marginal in simultaneous combat)**
- **Cost 0 · any_creature.** Desc: *"Target creature can't attack this round."*
- **Resolver (5022):** sets `target.state.is_frozen = true`, spawns a FROZEN chip; `+` also deals 2.
- **Verdict: weak.** Freezing **one** creature for **one** round, in a system where both rows attack every turn and fights are short, is low-leverage — it answers a single attacker for a single tick and then it's gone. `time_snare` (cost 2) freezes the **whole** enemy board for the same one round and is a premium card; `frost_bolt` is its 0-cost shadow but the single-target version rarely changes a combat's outcome. The `+` (deal 2) helps but at that point you'd rather `shove`.
- **Redesign — make the freeze pull double duty on position:**
  > **Frost Bolt** — Cost **0** · enemy_creature · *"An enemy creature can't attack this round, then is pushed to its back row (if there's room)."*
  Now it's a tempo+position tool: freeze the front threat *and* shove it out of the front line so your attacker connects with face/back. That's a 0-cost that actually exploits the 4×4 board. `+` → also deal 2.

---

# SECOND TIER: weak-but-not-unplayable (worth a redesign)

### 7. `shove` — **weak-for-effect (mis-named position tool)**
- **Cost 0 · enemy_creature.** Desc: *"Deal 2 damage to an enemy creature and reduce its ATK by 1."*
- **Resolver (4679):** 2 damage + `current_atk -= 1` (floored at 0). `+` → 3 dmg, –2 ATK.
- **Verdict: weak / mislabeled.** The card is called **Shove** and the keyword glossary has a real "push to back row" verb (`pikeman`/`harpy` use it), yet this spell doesn't *move* anything — it's just a tiny 2-dmg-plus-ATK-debuff. As soft-removal it's fine-ish at 0 Command, but it's a missed opportunity and reads confusingly (nothing gets shoved).
- **Redesign — make Shove actually shove (deliver on the name + the board pillar):**
  > **Shove** — Cost **0** · enemy_creature · *"Push an enemy creature to its back row. If it can't move, deal 3 damage to it. Either way, –1 ATK this round."*
  Pushing the enemy's front-line blocker into the back opens a lane for your attacker to hit face — exactly the under-used positional play. (Mirror of the upgraded `pikeman` On-Enter.) `+` → –2 ATK / 4 damage.

### 8. `holy_smite` — **situational / overlaps the removal suite**
- **Cost 1 · enemy_creature.** Desc: *"Deal damage to an enemy creature equal to its missing HP."*
- **Resolver (5029):** `take_damage(missing_hp)` where missing = `card_data.hp - current_hp`.
- **Verdict: situational.** It's an **execute** — zero value on a full-HP creature, only good after something already chipped the target. In a draft pool that already has plenty of removal (`strike`, `slash`, `concentrate`, `smite_spell`, `pillage`, `hex`), a removal spell that **requires setup to do anything** is an enabler-without-reliable-payoff. Great in a Poison/`thornguard`/chip deck, dead otherwise.
- **Redesign — give it a floor so it's never a brick:**
  > **Holy Smite** — Cost **1** · enemy_creature · *"Deal damage to an enemy creature equal to its missing HP, or 3 — whichever is higher."*
  Now it's a Strike that becomes a *guaranteed kill* on anything you've softened — a finisher with a floor, not a conditional brick. (`+` already drops cost to 0, which is a fine alternative upgrade.)

### 9. `lay_on_hands` — **weak (heal rarely matters in fast fights)**
- **Cost 1 · friendly_creature.** Desc: *"Heal a friendly creature to full HP and give it +2 max HP this fight."*
- **Resolver (4995):** `card_data.hp += 2`, `current_hp = card_data.hp` (full heal + permanent-this-fight +2 max). `+` → +4 max.
- **Verdict: weak.** Creature healing is a low-priority effect in a 2–3-round race — you usually want the Command on a body or removal. Topping up one creature to full + a small buffer doesn't swing tempo. It shines only on a key wall/Guardian, which is narrow.
- **Redesign — make it protective tech, not just numbers:**
  > **Lay on Hands** — Cost **1** · friendly_creature · *"Heal a friendly creature to full HP. It gains **Regenerate** this fight."*
  Regenerate (heals at start of round) turns it into a *sustained* anchor for your wall/Guardian — a reason to draft it for a defensive shell rather than a one-tick top-up. `+` → also +2 max HP.

### 10. `mending_light` (card "Censer Light") — **weak (low-tempo single grant)** + ⚠️ resolver/desc mismatch
- **Cost 1 · friendly_creature.** Desc: *"A friendly creature gains Lifelink and +1 ATK this fight."*
- **Resolver (5000):** ⚠️ **The `mending_light` branch does NOT match the desc.** It runs `player_hp += 5` and heals **all** your creatures +2. The Lifelink grant is in the **`censer_light`** branch (4970) — which *is* the id this card's `spell.id` points to (`"id":"censer_light"`). So the live behavior is the censer_light one (grant Lifelink + ATK to one creature). The `mending_light` branch is **dead code** reachable by no card (no spell has `id:"mending_light"`).
- **Verdict: weak.** Granting Lifelink + 1 ATK to a single creature for a card is low tempo — Lifelink only pays off if that creature keeps attacking and surviving, which a fresh grant doesn't guarantee. It's an enabler whose payoff (incidental healing) is small and slow.
- **Redesign — make the heal happen *now* and scale with commitment:**
  > **Censer Light** — Cost **1** · friendly_creature · *"A friendly creature gains Lifelink this fight. Heal yourself for its ATK."*
  Immediate payoff (heal = the creature's ATK, so it's strong on your biggest body) **plus** the ongoing Lifelink — a real sustain card instead of a hope. `+` → also +2 ATK. *(Also: delete or repurpose the orphaned `mending_light` resolver branch — flagged as a separate cleanup task.)*

### 11. `patch_up` — **weak (heal with a hoop)**
- **Cost 1 · friendly_creature.** Desc: *"Heal a friendly creature 4 HP. If it was already at full HP, draw 1."*
- **Resolver (4854):** heal 4 capped to max; draw 1 **only if** it was already full. `+` → heal 6, draw 2.
- **Verdict: weak.** Same fast-fight heal problem as `lay_on_hands`, plus the cantrip is gated behind "target a full-HP creature" — i.e. you only draw when the heal *did nothing*. That's a feel-bad: the two halves never both pay off.
- **Redesign — let it always do a little of both:**
  > **Patch Up** — Cost **1** · friendly_creature · *"Heal a friendly creature 4 HP. Draw 1."*
  An unconditional heal-cantrip is a clean, always-fine include (no hoop), and a 1-Command "heal + replace itself" is appropriately modest. `+` → heal 6, draw 2 (already supported via `dmg_bonus`/`extra_draw`).

### 12. `shield_wall` — **borderline (forgettable defensive trick)**
- **Cost 1 · friendly_creature.** Desc: *"Target friendly gets +4 HP and Thorns this round."*
- **Resolver (4839):** `current_hp += 4`, `card_data.hp += 4` (note: this is **permanent** max-HP, not just "this round" — the desc undersells it), plus `shield_wall_thorns` meta for the round. `+` → +6 HP.
- **Verdict: borderline.** A 1-Command +4 max-HP (it persists!) with one round of Thorns is *okay* but unexciting — you rarely want it over removal or a body. The Thorns being one-round-only is the weak part.
- **Redesign — pick a clearer identity (combat trick that punishes attackers):**
  > **Shield Wall** — Cost **1** · friendly_creature · *"Target friendly gets +4 HP and **Thorns** (rest of fight)."*
  Persistent Thorns on a wall makes it a real deterrent vs. multi-attackers, not a one-round blip. `+` → +6 HP. *Alt (lane, on-brief):* *"Friendlies in target's lane get +3 HP and Thorns this round."*

### 13. `provision` — **borderline (thin token for a card)**
- **Cost 0 · Exhaust.** Desc: *"Summon a 1/1 Soldier in an empty lane. Exhaust."*
- **Resolver (4688):** `_summon_one_soldier(1, 1)`. `+` removes Exhaust (body stays 1/1).
- **Verdict: borderline.** A 1/1 for a whole card (that then Exhausts) is thin — a 1/1 trades down into almost everything and the card is gone. It's playable as Standard-Bearer/`squire_captain`/sacrifice fodder, but on its own it's barely worth the slot. Note the `+` removing Exhaust is a *weird* upgrade — it lets you replay it, but a replayable 1/1 generator is still low-impact.
- **Redesign — make the body matter or the placement matter:**
  > **Provision** — Cost **0** · none · *"Summon a **2/1** Soldier in an empty lane. Exhaust."*
  A 2/1 actually threatens a trade and is real sacrifice/Overrun fodder. `+` → 2/2 (and keep Exhaust, or drop it — either is fine once the body is real). *Alt:* keep 1/1 but summon it with **Guardian** so it's a 0-cost speed bump that protects a lane.

---

# CLUSTERS (redundancy — read together)

The pool has several families of near-duplicates. None are *individually* broken (except where flagged above), but a draft pool benefits from each member having a distinct reason to pick it. Differentiate or thin:

### Removal ladder (single-target creature damage) — mostly healthy, one true overlap
`strike` (1, deal 3) → `slash` (1, deal 3 + Slay-draw) → `concentrate`/Immolate (1, deal 4, on-kill 4 face) → `pillage` (1, deal 3 + Slay-10g) → `smite_spell` (2, deal 6 + Slay mana/draw, Exhaust).
- This is a **good ladder** — each adds a rider (draw / burn / gold / ramp). **Keep all.**
- The one soft overlap: **`slash` vs `pillage`** are both "deal 3 + a Slay rider." `slash`→draw, `pillage`→gold. That's fine and intentional (combat value vs econ). No change needed; just noting they're the closest pair.
- `reckless_charge` (1, deal 3 + draw 1 + take 1) and `quick_shot`/`shove` also live in this space at the low end — `reckless_charge` is **fine** (Strike+cantrip at a tiny HP cost). `quick_shot`/`shove` are the two I redesigned above to stop being feeble single-target chip.

### Anthem ladder (board-wide ATK buff) — healthy, watch the overlap
`war_cry` (1, +1 ATK & Swift, this round) · `inspire` (2, +2 ATK & Piercing, this round, Exhaust) · `kings_command` (2, +3 ATK this round + perm +1 HP, Exhaust) · `battle_hymn`/Wildfire **(wait — `battle_hymn` id maps to the `battle_hymn` resolver = +1/+1 to all, NOT the Wildfire burn; the *card named* "Wildfire" is `battle_hymn`'s sibling… see note)** · `overwhelming_force` (3, +3 ATK this fight) · `dark_pact` (redesigned above).
- ⚠️ **Naming trap for future-you:** the card **"Wildfire"** has `id:"battle_hymn"` but `spell.id:"wildfire"` → it runs the **`wildfire`** resolver (AoE burn). There is *also* a `battle_hymn` resolver branch (+1 ATK/+1 HP to all friendlies) that **no card reaches** — another orphan, like `mending_light`. So the "anthem" list is really: `war_cry` / `inspire` / `kings_command` / `overwhelming_force`, and they ladder cleanly by cost (round-buff → fight-buff). **Keep all four**; only `dark_pact` was the broken member.
- Distinctness is good here (Swift vs Piercing vs +HP vs this-fight). No cuts.

### AoE / board-clear suite — healthy, no cuts
`ricochet` (1, 4×1 random) · `earthquake` (2, 3 to **all** both sides, Exhaust) · `wildfire` (2, 2-to-all + face-per-creature, Exhaust) · `cataclysm` (3, =your-top-ATK to all enemies) · `inferno` (4, 4-to-all + 4 face) · `plague_bell` (1, 1-to-all repeating) · `mass_grave` (1, =discard-pile-size to all) · `apocalypse` (3, destroy everything, Exhaust).
- Wide spread of costs and conditions (cheap chip → scaling → nuke). The two 1-cost scalers (`mass_grave`, `plague_bell`) reward different builds (discard pile / wide-board). **Keep all.** `ricochet` at 1 for 4 chip-damage is the floor and is fine as the cheap option.

### Filter / dig 0-drops — minor overlap, fine
`gambit` (discard up to 3, draw that many — free rummage) · `recycle`/Salvage (exhaust a hand card → Command = its cost) · `scrap`/Cinders (discard 1 → +1 Command).
- `gambit` digs (card-neutral), `recycle`/`scrap` convert dead cards to Command. `recycle` (any-cost, exhausts so it clears clog) slightly outclasses `scrap` (discard-1, +1), but `scrap` is cheaper to think about and feeds discard-matters. **Keep; optional:** give `scrap` a tiny rider so it's not just a worse `recycle` — e.g. *"...if you discarded a Curse, draw 1."*

### Recursion / death-matters — minor overlap, fine
`reanimate` (1, summon last-dead as 1/1 token, Exhaust) · `grave_robbery` (1, return last-dead **creature to hand**, Exhaust) · `grave_pact` (1, next dying friendly returns to hand, Retain) · `offering`/`fuel_the_pyre` (sacrifice outlets) · `war_chant` (discard→Soldiers).
- `reanimate` (token now, on board) vs `grave_robbery` (full card back, replay later) are *different enough* (immediate body vs deferred value). **Keep both.** This is the "death-matters" archetype's payoff suite — exactly the kind of narrow-but-intentional cards to preserve.

---

# FINE — listed for completeness (read, judged on-rate, no change)

**Benchmarks / clean removal:** `strike`, `fireball`, `flame_bolt`, `slash`, `concentrate`(Immolate), `smite_spell`, `pillage`, `reckless_charge`, `hex`.
**Combat tricks / anthems:** `war_cry`, `ambush`, `inspire`, `overwhelming_force`, `kings_command`, `charge_spell`.
**AoE / clears:** `ricochet`, `earthquake`, `wildfire`, `cataclysm`, `inferno`, `plague_bell`, `mass_grave`, `apocalypse`.
**Answers / tech:** `banish`, `time_snare`, `hoarfrost`.
**Value / draw:** `unholy_bargain`, `gambit`, `recycle`, `scrap`, `adrenaline`, `lost_tome`, `war_council`.
**Archetype payoffs (narrow but intentional):** `war_chant`, `offering`, `fuel_the_pyre`, `grave_pact`, `grave_robbery`, `reanimate`, `venom_tip`, `censer_light`(post-fix), `echo_spell`.

> Note: `adrenaline` and `echo_spell` and `unholy_bargain` are all fine *as-is* — they have real costs/payoffs (Exhaust, requires a prior spell, HP). I did not redesign them.

---

# Bugs / cleanup spotted while reading (not balance, but flag for the team)

1. **Orphaned resolver branches.** Two `match` arms in `_resolve_custom_spell` are reachable by **no card**:
   - `mending_light` (5000) — the card "Censer Light" uses `spell.id:"censer_light"`, not `mending_light`. The `mending_light` branch (heal self 5 + all creatures +2) is dead code.
   - `battle_hymn` (4826, +1 ATK/+1 HP to all friendlies) — the card "Wildfire" uses `spell.id:"wildfire"`. No card has `spell.id:"battle_hymn"`. Dead code.
   - Also present but unreferenced by any draftable spell: `second_wind` (4692), `lightning` (4697), `barricade` (4928). Confirm these aren't enemy/relic-only before removing.
2. **`shield_wall` desc undersells it** — the resolver adds **permanent** max HP (`card_data.hp += 4`), but the desc says "+4 HP … this round." Either the HP should be temp, or the desc should drop "this round" for the HP clause. (My redesign assumes the +HP is meant to stick.)
3. **`provision` `+` is an odd upgrade** — removing Exhaust to allow replaying a 1/1 is low-value; consider bumping the body instead (covered in the redesign).
