# Relic Slate Pitch — 2026-07-16 (research + cold-designer round)

**What this is.** Web research on relic/permanent design in the reference games, then a cold
designer agent (no attachment to the pool) given the game's mechanical ground truth, the house
design bar, and the research — asked to pitch a slate. House annotations at the bottom.
This is a PITCH, not a build order — nothing here is implemented.

**Design compass this extends** (agreed in-session, 2026-07-16): relics are the run's ONLY
permanents (creatures die in 1–2 turns, hand flushes, board wipes). A relic earns its permanence
by (1) compounding across ROUNDS — the in-fight engine creatures can't survive to be,
(2) compounding across FIGHTS — run memory, (3) bending a RULE no card may print, or
(4) touching the MAP/economy. Bar per relic: a visible MOMENT + a changed DECISION.
"Cards are the army, relics are the war."

---

## Research findings (2026-07-16)

- **Slay the Spire 2 (EA 2026)** moved relics from *permanent reliability* to **situational
  power spikes** — including **durability relics that burn out temporarily after several
  activations per combat** (conservation decisions), and enemy mechanics (Corrosion/Pierce)
  that make relic value context-dependent instead of universal. Community verdict: more
  interesting, relics now shape runs more than the deck.
- **Wildfrost charms — the cautionary tale**: criticized as understated, illegible (no
  preview of interactions), and bought blind from randomized shops. Lesson: bold legible
  effects, offered as visible choices.
- **Balatro**: the trinket IS the build — players draft toward jokers; effect-first or
  flavor-first design both work if the identity is strong.
- **StS 1 (Mega Crit)**: thousands of ideas ruthlessly pruned; evidence (playtests/streams)
  trumps designer preference.

Sources: PixelNitro StS2 relics guide · Problem Machine Wildfrost essay ·
Game Developer "Road to the IGF" (Mega Crit) · Game Informer LocalThunk interview.

---

## The slate (18 pitches, cold designer round 1)

### A. Tribe relics (6) — the pool's biggest gap (six tribes shipped 2026-07-15, zero relic support)

Framing call: **bespoke per-tribe designs around each tribe's VERB** (endure / arrive / die /
spellcraft / hold / get paid), not a shared "+1 to X" template. Shared parts: an offer gate
(`requires_ctype_count`, PotionDB `_roll_allowed` precedent — 4+ for Soldier/Beast/Dead,
3+ for Warlock/Bastion/Stray) and a regimental-ribbon accent on the rail chip.

| id | Name | Tier | Text | Moment / Decision | Hook |
|---|---|---|---|---|---|
| `second_rank` | The Second Rank | combat·unc | When a front-row Soldier dies: the Soldier behind it steps forward. | The line refuses to break; you stack Soldier COLUMNS — back row becomes the relief rank; keeps Warden-Sergeant's full-front condition alive through deaths. | creature_death + move machinery |
| `slip_the_leash` | Slip the Leash | combat·unc | When a second Beast arrives on the same turn: the pack is loosed — both gain Swift this round. | Pack-howl callout; hold Beasts to double-drop — sequencing pressure. ⚠ Swift audit (card review #6) still open; land it first or ship rare. | creature_played + per-turn ctype counter |
| `sextons_spade` | The Sexton's Spade | combat·RARE | Once per fight, dig the grave: a friendly Dead creature of your choice dies. | Click the spade, pick the body — every sacrifice/death payoff detonates once, on your timing. ⚠ TENSION with the no-free-sacrifice rule — see annotations. Fallback text: "Once per fight: a friendly Dead creature with Doom detonates immediately." | new activatable-relic frame → `_trigger_player_sacrifice` |
| `familiars_quill` | The Familiar's Quill | combat·unc | When you play a Warlock: it scribes — your next spell this turn costs 1 less. | Quill flourish, discounted spell glows; pure sequencing (Warlock before spell), stacks with Coven Mother. | creature_played + this-turn discount (mummified_hand precedent) |
| `portcullis` | The Portcullis | combat·unc | Once per round, when you would take face damage while a Bastion stands: your highest-HP Bastion takes it instead. | "The wall holds." Defend the face by keeping a wall standing. ⚠ needs a living Bastion — honest only because Bastion is the survival tribe; first cut if walls die too fast. | hero_damaged intercept (phantom_veil precedent) |
| `head_money` | Head-Money | combat·unc | When a Stray kills an enemy creature: collect the bounty — gain gold equal to its Command cost. | Coin-burst off the corpse; you engineer WHO lands the kill; feeds Kingpin's gold aura + Sellsword threshold. | kill attribution (veterancy plumbing) |

### B. Run-memory relics (4) — the campaign-memory identity's trophy shelf

| id | Name | Tier | Text | Moment / Decision | Hook |
|---|---|---|---|---|---|
| `heads_on_pikes` | Heads on Pikes | combat·unc | Start of each fight: the highest-ATK enemy gets -1 ATK this fight per General broken this run (max -3). | Pike banner plants, biggest enemy wilts. A ROUTING relic — the war-road General trade gets a fourth reason to say yes. Keep the cap. | combat_start + Generals-broken counter (elite_won exists) |
| `dead_mens_wages` | Dead Men's Wages | combat·common | After each fight: gain 3 gold per name added to the Roll of the Fallen this fight. | The paymaster keeps the dead on the books (real historical grift). Pays you for the trades the attrition math forces anyway; funds gold builds. | combat_end + fallen-count delta |
| `drill_book` | The Drill Book | combat·RARE | Your creatures earn epithets at 2 kills instead of 3, and the war school opens at 7 kills instead of 10. | The game's best existing ceremonies arrive an act earlier; kill-stacking becomes a plan. Multiplies Letters Patent. | relic-aware threshold reads on creature_kills |
| `cerecloth` | The Cerecloth | combat·RARE | The first creature you play each fight is wrapped in the newest shroud on the Roll of the Fallen: it gains that soldier's printed keywords this fight. | Log names the dead: "Wears the shroud of Pikeman the Grim — Armored, Thorns." You engineer who dies LAST each fight. Pairs with Hold a Wake. | combat_start / first creature_played + RunState.fallen tail |

### C. StS2-style situational / durability experiments (3)

| id | Name | Tier | Text | Moment / Decision | Hook |
|---|---|---|---|---|---|
| `old_meg` | Old Meg | combat·RARE | Fire Old Meg: 4 damage to an enemy creature. 2 shots per fight — fire both and she cools through your next fight. | Named bombard with shot-pips; cross-FIGHT burnout (novel — only works where relics are the sole permanents). "Clear this hold comfortably, or save her for the General two rows up?" — a map-reading conservation call. | activatable frame + potion-style targeting; cooldown flag cleared at next combat_end |
| `forlorn_hope` | Forlorn Hope | combat·unc | Against Generals and the keep: the first creature you play enters Swift with +2 ATK this fight. | The storming-party banner rises where fights are hardest; dead weight in plain holds — a deliberate situational spike; makes General-hunting cheaper. | combat_start + is_elite/is_boss flags |
| `powder_horn` | Powder Horn | combat·unc | When you bank Command: add a measure of powder (max 3). Your next damage spell burns it all — +2 damage per measure. | Powder pips fill as you bank; bank-vs-spend gains a third answer: bank INTO the burst. | mana_banked hook (retired mana_tide rode it) + spell_damage |

### D. Reshapes (4) — worst invisible stat-taxes, same ids kept (2026-07-03 precedent)

| id | Name | Was | Now | Hook |
|---|---|---|---|---|
| `vanguard_banner` | Vanguard Banner | +1 ATK front row (invisible) | The first time you fill all 4 front lanes each fight: the banner is raised — front row +1 ATK this fight. A once-per-fight ceremony; placement goal. (Revives retired phalanx_stone as a moment.) | creature_played + per-fight flag |
| `veterans_medal` | Veteran's Medal | +1/+1 to 1-costs (invisible) | When a 1-cost friendly kills an enemy creature: it is decorated — +1/+1 this fight. Kill assignment onto the cheap troops; rhymes with veterancy. | kill attribution + cost check |
| `worn_spellbook` | Worn Spellbook | +1 spell damage (invisible) | When you cast a spell you have already cast this fight: the worn page tears — +2 damage and draw 1. Rewards DUPLICATES — a draft axis nothing else touches. Draw is mid-turn on your own cast → survives the refill-wash rule. | spell_played + per-fight cast registry |
| `du_vu_doll` | Maledetto Poppet | +1 ATK per Curse in deck (invisible) | When you draw a Curse: the poppet takes its sting and lashes out — 2 damage to a random enemy creature. Curses become AMMUNITION — re-values Cursed Key, Mark of Pain, the black-ledger openers. Gate offer on owning a curse/curse source. | intercept in the curse_on_draw sting funnel |

### E. Boss relic (1)

| id | Name | Text | Notes |
|---|---|---|---|
| `articles_of_war` | The Articles of War | Choose a tribe: its creatures cost 1 less. All other creatures cost 1 more. | Boss pick, non-template. Total tribal commitment (Balatro: the trinket IS the build); every hand-render shows the re-priced costs; sutler buy-back becomes the purge tool. Act-pick modal machinery exists (Totem Pole). |

### Agent's ship-first ranking

1. **Sexton's Spade** (activates ~8 existing death payoffs; forces the activatable-relic frame into existence) — pending the sacrifice-rule call
2. **Heads on Pikes** (the only routing relic anywhere; cheap to build)
3. **Maledetto Poppet reshape** (creates the curse-positive archetype from dead text)
4. **The Second Rank** (biggest tribe, fires ON death — the one thing attrition guarantees)
5. **Old Meg** (the durability experiment worth running; the answer generalizes)

### Agent's honesty flags

- No pitch requires a creature to survive N rounds — payoffs fire on entry, death, kill, fight
  boundaries, or the relic's own counters (Portcullis is the one standing-body exception, defended).
- New machinery needed once, used twice: an ACTIVATABLE relic frame (click, charge pips,
  potion-style targeting) for Sexton's Spade + Old Meg.

---

## WAVE 2 (2026-07-16 later) — pattern-mined from the genre's most-loved relics

Research round 2 targeted specific beloved designs (not philosophy): StS Dead Branch / Kunai /
Gremlin Horn community analyses, Monster Train artifacts, Hades duo-boon structure. Each pitch
below names its source pattern. All pre-filtered through the positivity + reason-to-exist bar;
none duplicate the pool or Wave 1.

| id | Name | Tier | Text | Pattern + notes |
|---|---|---|---|---|
| `burnt_dispatches` | The Burnt Dispatches | combat·unc | The first spell you Exhaust each turn: a random spell returns from your discard pile to your hand. | DEAD BRANCH (cost→generator). 32 exhaust spells, 1 payoff today. Mid-turn material — refill-proof. GATE: 2+ exhaust spells in deck. |
| `blood_wages` | Blood-Wages | combat·common | The first enemy your army fells each round: +1 Command next turn. | GREMLIN HORN (kill→momentum). Fires ~every round under attrition; "next turn" avoids the clash-time Command bug class. Mirror of soul_lantern. |
| `tally_stick` | The Tally-Stick | combat·unc | Each turn you play 3 or more cards: cut a notch — your creatures gain +1 ATK this round. | KUNAI (per-turn volume threshold). Play-time trigger on own turn; makes banking/cheap cards a volume plan. |
| `tithe_of_straw` | The Tithe of Straw | combat·RARE | When one of your Summon tokens dies: it counts as a sacrifice. | CORRUPTION+DEAD BRANCH (loop-completer). Fuses the token engine into the whole sacrifice shelf via `_trigger_player_sacrifice`. GATE: token source in deck. The slate's Dead Branch. |
| `outriders_report` | The Outrider's Report | combat·unc | The foe's next arrival is always revealed to you. | INFORMATION AS POWER (Informer/Wolf-Pits precedent — arrivals are hidden info). Strictly positive, never zero, decision-dense. |
| `witch_shot` | Witch-Shot | combat·unc | Your damage spells ignore Armored and Shield. | STS2 SITUATIONAL SPIKE + MT Cracked Helmet — and BM's conquest map lets you SEE the kingdom before drafting it. Borderline per the Forlorn Hope ruling (big in its window). |

House annotation: Blood-Wages + Tally-Stick + Burnt Dispatches also patch the audit's "commons
are invisible" complaint — all three are loud, frequent workhorses below rare.

### Wave 2 verdicts (operator asked "which actually make sense" — mechanics-checked vs live build)

**KEEP AS WRITTEN:** tally_stick (mid-turn trigger, clash-facing buff — nothing washes),
outriders_report (safest of the six; arrival-reveal machinery half-exists; solo-only — keep out
of NET_RELIC_POOL), witch_shot (window is real: Armored applies to spell damage and encounter
passives hand it out wholesale; Forlorn Hope borderline class).

**KEEP ONLY AMENDED:** burnt_dispatches — as written it is WASHED (returned card = draw-shaped;
persistent refill-to-5 neutralizes it, same verdict as all draw effects). Required rider:
"…returns from your discard **and costs 0 this turn**" — forced tempo the refill can't eat.

**CUT:** blood_wages — near-duplicate of soul_lantern (both triggers fire ~every round under
attrition → identical felt +1 Command/round; fails reason-to-exist, 07-08 merge precedent).
tithe_of_straw — collapses on timing: Cleaver is turn-scoped but token deaths are clash-time
(washed); Scythe needs on-enters tokens lack (dead); Bone Pile pays 1 ATK (negligible); and
routing clash deaths through _trigger_player_sacrifice would fire the ENCOUNTER's
ON_PLAYER_SACRIFICE punishment — a hidden negative rider. The loop it promises does not exist
in this game's plumbing.

**LESSON (third occurrence — now a checklist):** imported relic designs must be traced against
(a) the persistent-hand refill wash, (b) clash-time vs turn-scoped payoff timing, (c) enemy
reactive hooks, BEFORE pitching. StS translations fail on all three invisibly.

## Positivity filter (2026-07-16, operator directive: "relics have to be positive and actually have a reason to exist")

Two tests applied to all 18: (1) never hurts you / never sits at zero (boss tier exempt — the
downside-trade template is sanctioned there); (2) does a job the pool needs, stated in one line.

**CUT:** dead_mens_wages (gold trickle in theme paint — the 07-07 cut already banned these; changes
no decision). veterans_medal reshape (win-more on a body that dies same-round 63–74% of the time —
the ORIGINAL flat version stays; quiet draft-direction signposts are legitimate at starting tier).
vanguard_banner reshape (same invisible +1 behind a fill-the-front hoop that baits AoE — theater
around unchanged math; leave original or find a real payoff).

**FIXED to pass:**
- old_meg: 2 shots per fight, RECHARGES every fight — the cross-fight cooling was a punishment
  mechanic (StS2 durability burns out within the fight only). Conservation decision stays.
- portcullis: redirects only "if it would survive" — never feeds a 2-HP wall to a hit the face
  could shrug.
- cerecloth: floor added — "if it had no keywords, +1/+1 instead." Never blank.
- second_rank: step-forward resolves AFTER the clash; ships with the forced-move caveat (can pull
  a deliberately-backed Soldier forward) — acceptable for the one tribe that wants front.
- du_vu_doll/Poppet: offer-gated on owning a Curse or a curse source — zero without one.

**SURVIVORS (12):** heads_on_pikes (gate on 1+ General broken), powder_horn, familiars_quill,
head_money, drill_book, old_meg*, worn_spellbook reshape, du_vu_doll reshape*, portcullis*,
second_rank*, sextons_spade-FALLBACK (Doom detonate — the sacrifice version stays blocked pending
ruling), forlorn_hope (borderline: silent in plain holds; lives on being big in its window).

**HELD:** slip_the_leash (until the Swift audit, card review #6), articles_of_war (boss-tier
sanctioned downside; verify it can't brick a hero starter curve at the act-1 pick).

## House annotations (2026-07-16)

- **Sexton's Spade needs an operator ruling.** The no-free-sacrifice rule is a standing
  categorical ("sacrifice only via specific card effects, like StS"). The agent's argument —
  relics earn permanence by bending rules cards can't print — is the strongest case anyone's
  made for an exception (Dead-gated, once per fight, rare). The Doom-detonate fallback keeps
  ~80% of the moment with zero rule damage. DO NOT BUILD without the call.
- **Second Rank timing gotcha**: the step-forward must resolve AFTER the clash beat, not
  mid-resolution — a body arriving mid-simultaneous-combat raises "does it strike this round"
  questions. Cleanest: step forward at deaths-resolved, strike next round.
- **Slip the Leash**: hold until the Swift audit (card review item #6) lands.
- **Articles of War**: watch the interaction with Kindler's doom commons and hero starter
  decks (starters are mixed-tribe by design — the +1 tax hits every off-tribe starter; that's
  the point, but check it doesn't brick any hero's opening curve at the act-1 boss pick).
- **Offer gating** (`requires_ctype_count` etc.) is endorsed — no-dead-rewards rule, and it's
  the PotionDB precedent verbatim.
- The full adversarial review of the EXISTING pool (per CARD_POOL_REVIEW_20260714.md §protocol)
  is still the flagged next step — this pitch fills gaps; the review culls defects. Run both
  before building.
