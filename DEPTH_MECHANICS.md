# Depth Mechanics Catalog — 60 levers across 55+ games

A survey of **specific** mechanics that generate gameplay *depth* (per the theory in
`DEPTH_NOTES`: depth = the count of *interesting/ambiguous decisions*, not rules-grit).
Each entry names the exact decision it forces and rates fit for **Burning Meadow**
(lane 4×4, **no front/back trade-off**, floop signature, fast ~2-3 round fights,
perfect-information preferred, mana 3 + bank ≤1, 4-card draw).

Fit key: **✓✓** top pick · **✓** good fit · **~** partial/with care · **✗** off-limits or wrong genre.

---

## A. Information & perfect-information puzzles
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 1 | Telegraphed enemy intents | Slay the Spire, Into the Breach | Plan an exact response to known incoming actions | ✓ have it — keep |
| 2 | Full deterministic preview | Into the Breach, Hoplite | Solve the whole turn like a chess puzzle | ✓ show next-round enemy placement |
| 3 | Scry / look-at-top / scout | StS (Scry), MtG, Loop Hero | Spend an action to *reduce future uncertainty* | ✓ have `look_top` — expand |
| 4 | Few units + open info | Into the Breach, Onitama | Depth from clarity, not chaos | ✓ design philosophy |

## B. Positioning & adjacency (spatial decisions)
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 5 | Displacement / push-pull | **Into the Breach**, Gwent | Reposition enemies so they hurt *each other* / leave a lane | ✓✓ push enemies **sideways** between lanes (no front/back) |
| 6 | Tableau adjacency combos | Wingspan, 7 Wonders, Hearthstone | Value depends on *who you sit next to* | ✓✓ promote `adj_buff` to a core engine |
| 7 | Lane-matchup / unit-across | **Inscryption**, Gwent rows | Read the opposing slot before you commit | ✓✓ "bonus vs empty lane / punished by Thorns" |
| 8 | Flanking / facing bonuses | XCOM, Gloomhaven, Invisible Inc | Angle of attack changes the math | ~ adds facing complexity |
| 9 | Zone of control / blocking | Chess, Advance Wars, Wesnoth | Deny squares the enemy wants | ~ lane-block possible |
| 10 | Area / territory control | Go, Blood Rage, Risk | Influence now vs overcommit | ✗ not BM |
| 11 | Capture-and-redeploy | **Shogi** | Killed pieces become *your* resource | ~ niche ("conscript a corpse") |
| 12 | Shared rotating movesets | **Onitama** | Your options are a depleting shared pool | ✗ |
| 13 | Go-wide / board cap | Hearthstone (7), Marvel Snap (4/loc) | Board space as a hard constraint → soft anti-snowball | ✓ 8-slot cap already bites |

## C. Tempo & timing (when things happen)
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 14 | The stack / priority / instants | **Magic: the Gathering** | Act *during the opponent's turn* — the deepest interaction lever in cards | ✓✓ a limited "reaction" card type (big, high-value) |
| 15 | Attack timers / counters | **Wildfrost**, auto-chess | Race the enemy's clock; reset it with a kill | ~ conflicts w/ simultaneous combat; use charge-up instead |
| 16 | Initiative / turn-order control | Gloomhaven, StS (Swift) | Choose *when* you act this round | ✓ have Swift — add **Slow** |
| 17 | Charge-up / wind-up | Darkest Dungeon, many bosses | Invest a turn now for a big hit later | ✓ light timing gamble |
| 18 | Delayed / fuse effects | Into the Breach, MtG (Suspend) | Telegraph a payoff, then protect it N rounds | ✓ planning depth |
| 19 | Cooldowns / ability windows | MOBAs (LoL/Dota) | Sequence limited ability uses | ~ floop is the per-turn version |
| 20 | Overwatch / held reactions | XCOM | Pre-commit to a conditional interrupt | ~ "set a reaction" (complex) |

## D. Resource tension & economy
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 21 | Energy/mana curve management | MtG, StS, Hearthstone | Affordability sequencing across the turn | ✓ inherent |
| 22 | Banking / ramp vs spend | **Marvel Snap** (ramp), Dominion | Invest in future tempo vs act now | ✓✓ deepen the ≤1 mana-bank into a real choice |
| 23 | Worker placement / spot denial | Agricola, Lords of Waterdeep | Take the spot *and* deny it to others | ✗ genre |
| 24 | Role selection (shared) | Puerto Rico, Race for the Galaxy | Pick a role everyone uses — but you first | ✗ genre |
| 25 | Rondel / action wheel | Concordia, Glory to Rome | Movement on a cycle has a cost | ✗ genre |
| 26 | Conversion / efficiency engines | Splendor, Factorio, Gizmos | Optimize input→output ratios | ~ relic engines |
| 27 | Diminishing returns / scaling cost | Civ, Splendor tiers | Soft cap that punishes over-investment | ✓ anti-snowball |
| 28 | Deck thinning / removal | Dominion, StS | Quality of the deck as a resource | ✓ have removal |
| 29 | HP / life as a resource | StS (blood), Inscryption | Spend the thing that keeps you alive for power | ✓ floop-costs-HP is on-brand |

## E. Risk / reward & push-your-luck
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 30 | Push-your-luck w/ bust | Can't Stop, Quacks, Balatro | Keep going or bank what you have | ✓ banking / overcommit |
| 31 | High-roll vs consistency build | Balatro, StS | Variance itself as a strategic axis | ✓ deckbuild axis |
| 32 | Overcommit punishment (sweeps) | Marvel Snap, MtG board-wipes | Don't dump your hand into the telegraphed wipe | ✓✓ telegraphed enemy AoE = placement + tempo depth + anti-snowball |
| 33 | Desperation / low-HP scaling | Berserk effects, last-stand | Risk as a lever ("stronger when bleeding") | ✓ comeback texture |
| 34 | Simultaneous blind reveal | 7 Wonders, Snap, RPS layers | Commit before you see → mind-game | ~ single-player limits bluff |

## F. Sequencing & combo (within a turn)
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 35 | Order-of-operations combos | StS, Balatro (joker order), HS | Sequence plays for maximum value | ✓ on-enter/floop ordering |
| 36 | "Nth action this turn" counters | StS combo cards, Snap on-reveal | Chain actions in the right count/order | ✓✓ you seed this (Hexblade) — make it an archetype |
| 37 | Cost-reducers / free-cast chains | StS, MtG (Storm) | Set up an explosive single turn | ✓ build payoff |
| 38 | Modal / "choose one" cards | **MtG charms**, HS Choose One, LoR | The card *is* a decision every time you play it | ✓✓ near-zero new systems, pure depth |
| 39 | Adaptive / conditional cards | Balatro, StS ("if you have X") | Value reads the current board state | ✓ situational reads |
| 40 | Retain / hold across turns | StS (Watcher Retain) | Save a card for the perfect moment | ✓ small lever |

## G. Active defense & interaction (counterplay)
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 41 | Block as an allocatable resource | **Slay the Spire** | How much to mitigate vs attack, *this turn* | ✓✓ your single biggest missing lever |
| 42 | Taunt / guard / forced target | Hearthstone Taunt, BM Guardian | Steer who eats the hit | ✓ have Guardian — lean in |
| 43 | Redirect / reflect | BM Royal Guard, Thorns | Turn defense into offense | ✓ expand |
| 44 | Counterspell / negation | MtG | Hold answers vs commit proactively | ~ needs reaction speed |
| 45 | Traps / set conditional responses | HS Secrets, Yu-Gi-Oh | Pre-place an "if enemy does X, then Y" | ✓ counterplay without full instant-speed |
| 46 | Combat tricks / bluff open mana | MtG | Threaten a response you may not hold | ~ single-player |

## H. Attrition, sacrifice & conversion
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 47 | Sacrifice for value | **Inscryption** (blood), MtG aristocrats | Spend a body to power something bigger | ✓ have sacrifice-via-effects |
| 48 | Overkill / trample / piercing payoff | MtG Trample, Inscryption scales | Make *excess* damage matter (→face/→draw) | ✓✓ you have Piercing — add payoffs |
| 49 | Graveyard / corpse recursion | Loop Hero, recursion decks | Reuse the dead | ✓ have Corpse Eater |
| 50 | Promotion / transform-in-place | Chess, StS+ upgrades, Pokémon | Invest to evolve a unit mid-fight | ✓ on-board transform |
| 51 | Trade evaluation | Chess, MtG combat | "Is this exchange good for me?" | ✓ core to combat |

## I. Build / synergy / meta-decisions
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 52 | Engine vs payoff timing | Dominion, Wingspan, Monster Train | Build the machine vs cash it in | ✓ run-level |
| 53 | Drafting + signal reading | MtG draft, 7 Wonders, Sushi Go | Read what's open, hate-pick | ~ reward is 1-of-3 |
| 54 | Mutually exclusive paths | Skill trees, MT dual-clan, StS | Opportunity cost — you can't have it all | ✓ relic/upgrade forks |
| 55 | Archetype enabler + payoff | StS relics, Hearthstone | Find/keep the keystone that makes the deck | ✓ have it |

## J. Anti-snowball & tension (keep the contest alive)
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 56 | Catch-up / rubber-band | Mario Kart, Civ (unhappiness) | Behind → tools to fight back → fights stay contested | ✓✓ the research's exact prescription for your snowball |
| 57 | Comeback meter when losing | Fighting games (low-HP super) | Reward the losing side with options | ✓ desperation cards |
| 58 | Board wipe / tempo reset | Hearthstone, MtG wraths | Reset a runaway board → swing decisions | ✓ telegraphed AoE both sides |
| 59 | Escalating pressure clock | Into the Breach grid, BM escalation | Forces action — punishes turtling | ✓ have escalation/reinforce |

## K. Constraint & denial (decisions from limits)
| # | Mechanic | Game(s) | The interesting decision | BM |
|---|---|---|---|---|
| 60 | Must-follow + trump | Hearts, Spades, The Crew | Constrained options = sharper decisions | ✗ trick-taking |
| 61 | Hand / option scarcity | Onitama, BM 4-card draw | Scarcity forces hard priorities | ✓ have it |
| 62 | Denial / removal targeting | MtG, drafting | Spend a resource to deny the opponent | ✓ spell targeting |

---

## Top picks for Burning Meadow (highest depth-per-effort, on-brand, constraint-safe)

Ranked by *interesting decisions added per unit of complexity/effort*, all respecting
"no front/back trade-off" and the fast-pace + perfect-info identity:

1. **Block as an allocatable resource (#41).** Your single biggest *missing* lever. A
   "Brace N" spell/floop that grants spendable temporary shield turns every enemy turn
   into a "how much do I mitigate?" puzzle — StS's entire depth engine.
2. **Modal "choose one" cards (#38).** Pure decisions baked into cards, almost no new
   system. Every play of the card is a fresh choice. Cheapest depth on the board.
3. **Adjacency + lane-matchup engines (#6, #7).** Depth on the positional axis you've
   *kept* (left-right + the unit across) — makes "where do I drop this" a real read.
4. **Combo counters / "Nth action" payoffs (#36).** You already seed it (Hexblade
   "+1 ATK per spell"). Make it an archetype → rewards within-turn sequencing.
5. **Telegraphed enemy AoE + overcommit punishment (#32).** Adds placement/tempo
   tension *and* is anti-snowball — don't dump your board into the coming sweep.
6. **Deepen floop with costs/targets (#29 + tapping).** Your signature mechanic, today
   a free toggle. Give floops a price (HP, exhaust, target choice) → real decisions.
7. **A light catch-up lever (#56).** The literature's direct fix for your 2-3-round
   snowball: behind on board → draw an extra / a board-wide last-stand. Keeps fights
   contested so the other levers get a turn to matter.
8. **Sideways displacement (#5).** Into-the-Breach positional depth — push/pull enemies
   *between lanes* (never front/back) so you can break up their adjacency or dodge a hit.
9. **Banking/ramp depth (#22)** and **Overkill/Piercing payoffs (#48).** Both cheap,
   both reuse systems you already have (mana-bank, Piercing keyword).

**The pattern:** every top pick adds *interesting decisions* (Meier/Burgun) without
adding *rules-grit* (Felder) — depth without complexity — and several double as
anti-snowball (the feedback-loop fix). That's the elegant path, not "more enemy HP."
