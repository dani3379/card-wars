# Burning Meadow — Comparative Board & Market Analysis

A practical study of how lane/card-battler **boards** shape play, and how the
games that use them did **commercially relative to budget and visuals**. Written
to inform Burning Meadow's 4-lane × 2-row (front/back) simultaneous-combat board.

> Sales/budget figures are public estimates (SteamSpy, AppMagic, press). Exact
> dev budgets are almost never disclosed; team size + funding are used as proxies
> and flagged as such. Data current to mid-2026.

---

## 0. Executive summary — the five throughlines

1. **Single-player roguelike deckbuilders are the durable, budget-efficient hit.**
   Slay the Spire (2 devs), Inscryption (~solo), Monster Train (small studio) each
   cleared 1M+ on tiny budgets and *stay* sold. Live PvP card games (Gwent, LoR,
   Duelyst, even Marvel Snap now declining) cost far more and churn. Burning Meadow
   is correctly in the cheap-and-durable lane.

2. **Board complexity does not sell — and can sink you.** The most tactically rich
   board in this set (Duelyst's 9×5 chess grid) is the one that *died*. The two
   best-sellers with any board (Inscryption's 4 slots, Monster Train's 3 floors)
   are aggressively legible. Slay the Spire has *no* creature board at all.

3. **Your board's closest twin is a cautionary tale.** Banners of Ruin uses almost
   exactly Burning Meadow's layout (front/back × lanes, push-to-lane). Critics:
   *"gorgeous hand-drawn artwork… but replayability hampered by weak card variety,
   most cards bad."* ~6.5/10, 79% Steam. **The board is necessary, not sufficient —
   card design is the moat.**

4. **Visuals: legibility > fidelity, and atmosphere > both.** Slay the Spire's plain
   art outsold prettier, shallower games by an order of magnitude. Inscryption proves
   *presentation/mood* (not polygon count) is the real differentiator. Wildfrost
   shows charming + readable + tight = a solid hit. Pretty-but-shallow (Banners,
   arguably Duelyst) underperforms.

5. **Front/back is a proven, readable depth lever — and Burning Meadow has chosen
   to mostly skip it.** Wildfrost (rotate to tank/heal) and Monster Train (front
   unit eats the hit) both make front/back a core decision. Burning Meadow's design
   note says "back row is play space, not a tactical axis." That's a legitimate
   simplification, but it means the back four slots must earn their existence some
   *other* way or the board reads as "wide Hearthstone with dead space" (§4).

---

## 1. How to read a board — the eight axes

Every board below is judged on the same practical axes. These are the levers that
actually matter when you're the one building and balancing it:

| Axis | The question it answers |
|---|---|
| **Drop-target UX** | How many slots? How precise must a drag be? Mobile-friendly? |
| **Combat legibility** | Can the player *predict* who hits whom before committing? |
| **Decision density** | How many meaningful choices does one placement create? |
| **AI authorability** | How hard is a competent enemy to write? |
| **Balance & snowball** | Does the geometry create runaway leaders / board-flood? |
| **Content scalability** | How many distinct mechanics can hang off positions? |
| **Screen real estate** | Does it fit on screen (esp. mobile) and stay readable? |
| **Comeback texture** | Can a losing player claw back from board state? |

Burning Meadow's board has **8 player slots + 8 enemy slots = 16 on-field cards**
plus a hand — the *highest slot count* of any single-screen game here except
Duelyst. That puts **screen real estate** and **drop-target UX** at the top of its
risk list (and is exactly why the drag/snap behaviour had to be fixed, and why the
field cards became compact landscape tokens).

---

## 2. Board archetypes, game by game

### A. No creature board — "you vs a line of enemies"
**Slay the Spire, Griftlands.** The player has *no* units; 1–4 enemies stand in a
row. All "positioning" is just target selection.

- **Solves:** Maximum legibility — enemies telegraph exact intents; every number is
  visible. Zero placement UX. Trivial to balance (no board-flood). Tiny art surface.
- **Creates:** No spatial strategy at all; depth must come 100% from card/relic
  interactions and enemy intent puzzles. Combat can feel "samey" visually.
- **BM relevance:** This is the genre's gold standard for *clarity*. The lesson for
  a board game like BM: every lane/row you add is depth you must *pay for* in UX and
  balance. StS proves you can be a mega-hit with none of it.

### B. Single shared minion row — adjacency only
**Hearthstone.** Up to 7 minions in one row; you freely choose attack targets
(Taunt forces). Position only matters for adjacency effects & battlecry targeting.

- **Solves:** Flexible, low-friction placement (one row, slot order is the only
  choice). Free-targeting keeps offense expressive. Huge mechanical space from
  adjacency without a grid.
- **Creates:** Positional depth is shallow/optional; "board flood" + go-wide
  snowballs need constant AoE counters to tame; free-targeting weakens any
  "frontline tank" fantasy.
- **BM relevance:** BM's *back* row behaves a lot like Hearthstone's single row
  (a queue with adjacency), while the *front* row adds the lane-matchup layer HS
  lacks. Watch the same snowball pressure: 4-wide × 2 rows can flood fast → AoE and
  board caps matter.

### C. Direct-opposing lanes, one row — "the card across from you"
**Inscryption (Act 1), Card Wars (Adventure Time).** 4 lanes; your creature fights
the enemy directly across its lane (or hits face/structure if empty).

- **Solves:** *Perfect* legibility — the matchup is literally eye-line. Drag UX is
  clean (4 fat targets). Cheap to author AI (place to block the scariest lane).
  Card Wars layered "buildings" behind creatures for a light front/back flavour and
  the "floop" tap-ability BM inherits.
- **Creates:** Limited slots cap simultaneous complexity (intentional in Inscryption).
  Pure lane-vs-lane can feel deterministic; needs sacrifice economies / piercing /
  swaps to stay spicy.
- **BM relevance:** BM's **front row IS this archetype** plus a back-row queue. The
  direct-opposing read is BM's biggest legibility asset — protect it. Note Card
  Wars (BM's stated inspiration) was a premium licensed mobile game and was
  **delisted in 2019** — the design is great, but tying to a license is a lifecycle
  risk BM avoids by being original IP.

### D. Front/back lanes — **Burning Meadow's archetype**
**Wildfrost, Banners of Ruin.** 2 rows × N lanes/side. Front units are hit first;
back units are protected and rotate forward.

- **Wildfrost's solution:** Front/back is a *living resource*. You rotate a near-dead
  damage dealer to the back, push a fresh tank forward, and pull wounded companions
  *off the board* to heal and recycle. Attack **counters** (each unit fires every N
  turns) replace simultaneous chaos with a readable clock. Result: deep, legible,
  hit (~Very Positive, 500k–1M owners).
- **Banners of Ruin's problem:** Same skeleton as BM (front/back × 3 lanes, *push
  enemies into inactive lanes* to delay them) and *gorgeous* art — but thin, mostly
  weak card pool made the tactics collapse into a few lines. ~6.5/10, replayability
  complaints. **The board was fine; the cards weren't.**
- **Creates (both):** The richest single-screen positional fantasy at low slot
  count — but the most demanding on **drop-target UX** (8 distinct slots/side; drags
  must snap forgivingly — see BM's drag fix) and on **card variety** to justify the
  extra row.
- **BM relevance:** This is you. Two explicit forks:
  - **Wildfrost path:** make front/back a real lever (tanking, rotation, pull-to-hand
    recycle, ranged-hits-back). High ceiling, proven.
  - **BM's chosen path:** "back row is play space, not a tactical axis." Simpler and
    more legible, but it puts the entire burden on **card variety + lane matchups +
    adjacency** (the Banners warning). If the back row never changes a decision,
    consider shrinking to 4×1 + a small reserve, or add *one* cheap front/back lever
    (e.g. front-only Taunt pull, back-only Ranged) so the eight slots pay rent.

### E. Vertical floors — spatial *and* a tower-defense clock
**Monster Train.** 3 stacked floors + a Pyre to protect. Enemies enter at the
bottom and **climb one floor per turn**; on each floor the front unit is hit first;
your units strike back after the enemy. Reaching the Pyre = lose.

- **Solves:** Fuses deckbuilder with tower-defense legibility — you can *see* the
  threat advancing and plan two turns out. Floor capacity is a clean spatial
  resource. Front/back order per floor is a crisp micro-decision. Multi-class deck
  fusion gives enormous build variety on a tiny board. Critical & commercial smash
  (1.5M+; sequel 95% Overwhelmingly Positive).
- **Creates:** Higher rules overhead (capacity, ascension timing, per-floor effects);
  more to teach than a flat lane board.
- **BM relevance:** Monster Train is the **best argument that a structured board can
  out-sell a flat one** — *if* the structure adds a legible clock and resource. BM's
  simultaneous combat lacks Monster Train's "watch it climb" telegraph; the Swift
  pre-phase + front-first ordering is BM's substitute. Consider stealing the
  *intent telegraph* idea: show next-round enemy placement/attacks so the board
  reads forward, not just this instant.

### F. Zone / location control — no attacking, totals decide
**Marvel Snap (3 locations × 4 slots), Gwent (2–3 point rows).** You drop cards into
zones; **power totals / row effects** decide, not creature-vs-creature attacks.

- **Solves:** Ultra-fast (Snap: ~3-min games), bluff-rich (the Snap stake mechanic),
  endlessly variable via location/row effects. No combat-targeting UI at all —
  beautiful for mobile. Snap monetized enormously ($200M+; 22M+ downloads).
- **Creates:** Almost no creature *combat* fantasy; outcomes are arithmetic + RNG
  locations; "feel-bad" variance. Gwent shows the failure mode: row novelty +
  constant drastic reworks (Homecoming) + power creep churned the base into a
  *financial disappointment* now community-run.
- **BM relevance:** Mostly a counterexample — BM *is* a combat game, so don't drift
  toward "totals." But steal two ideas: (1) **per-lane/zone modifiers** (Snap's
  locations, Gwent's row effects) are a cheap, high-variety content lever BM could
  hang on its 4 lanes; (2) Snap's "you only get 4 slots per zone" cap is a clean
  anti-flood rule.

### G. Full tactical grid — chess with cards
**Duelyst (9×5), Faeria (hex).** Units occupy and *move across* squares; range,
flanking, and board control are everything.

- **Solves:** The deepest positional skill ceiling in the genre; acclaimed by those
  who played it; stunning pixel art (Duelyst).
- **Creates:** The whole cautionary tale. Movement + range + a 45-square board is a
  steep teach, a heavy UI, hard AI, and a hardcore-only audience. Duelyst
  (Kickstarter $137k + Bandai Namco backing, *critical darling*) fell **below 100
  concurrent players** and **shut down in 2020** (later open-sourced). Quality and
  even funding did not save a too-complex board with thin onboarding.
- **BM relevance:** The ceiling you should *not* chase. BM's "back row is a queue,
  not a movement plane" instinct is the right anti-Duelyst guardrail. More board ≠
  more players.

---

## 3. Commercial & visual scorecard

| Game | Board | Team / funding (proxy) | Visual approach | Outcome | ROI read |
|---|---|---|---|---|---|
| **Slay the Spire** | None (enemy line) | 2 devs, self-funded | Plain, functional 2D | 1.5M by 2019 → many millions; **StS2: 5M+, $108M Steam month 1** | **Best ROI in the genre.** Mechanics-first, art-last. |
| **Inscryption** | 4 lanes, opposing | ~Solo + Devolver | Low-fi but *masterful mood/horror* | **1.46M+**, GOTY noms | Atmosphere, not fidelity, as the differentiator. |
| **Monster Train** | 3 floors + Pyre | Small studio (Shiny Shoe) | Clean, mid-budget stylized | **1.5M+**; sequel 95% OP | Structured board *can* win if legible. |
| **Wildfrost** | 2 rows/side | Small (Deadpan/Gaziter) + Chucklefish | Charming, very readable | ~60k & ~$1M wk1; **500k–1M owners**, ~$5.6M est. | Charm + clarity + tight loop = solid hit. |
| **Marvel Snap** | 3 zones × 4 | Big VC (**$100M** Series B, NetEase) | Slick, premium UI/VFX | **$200M+**, 22M+ DLs; **Y2 −40% YoY** | Huge, but expensive live-service; now cooling. |
| **Banners of Ruin** | front/back × 3 | Small (Montebearo/Goblinz) | **Gorgeous** hand-drawn | 79% Steam, ~6.5/10 | **Pretty ≠ deep.** Weak cards capped it. |
| **Gwent** | 2–3 point rows | AAA (CD Projekt) | High-end, premium | "Financial disappointment," sunset → community-run | Row novelty + churn + reworks lost the base. |
| **Legends of Runeterra** | No lanes (block pairing) | AAA (Riot) | Top-tier production | Cost **> revenue**; 2024 scale-back + layoffs | Even great combat + Riot money lost on F2P PvP. *Pivoted to a single-player roguelike (Path of Champions) — its bright spot.* |
| **Duelyst** | 9×5 grid | KS $137k + Bandai Namco | Acclaimed pixel art | **<100 CCU, shut down 2020** | Deep board + great art still failed on complexity/onboarding. |
| **Card Wars (AT)** | 4 lanes + buildings | Licensed mobile (Cartoon Network) | Brand-styled | Popular, **delisted 2019** | Great design; license = lifecycle risk. |

**What the scorecard says about budget & visuals:**

- **Visual spend is weakly correlated with success; clarity and mood are strongly
  correlated.** The cheapest-looking games (StS, Inscryption) are the most
  profitable per dollar. The prettiest mid-budget one in BM's exact genre (Banners)
  underperformed because the *cards*, not the pixels, were thin.
- **Money cannot buy a sustainable live card game.** Riot (LoR) and CD Projekt
  (Gwent) both bled on premium PvP CCGs. Second Dinner's $100M+ made Marvel Snap
  huge but it's already −40% YoY — that's a treadmill BM should not want.
- **The single-player roguelike framing is the safe, high-ROI harbour** — and
  notably the direction LoR *retreated to* when PvP economics failed. BM is already
  there.

---

## 4. What this means for Burning Meadow (concrete)

**Your board's real risks, ranked:**

1. **The back row must earn its rent (Banners warning + your own design note).**
   You've declared back row = play space, not a tactical axis. Then the danger is
   16 on-field cards where half the slots never change a decision. Pick one:
   - *Cheapest:* keep 4×2 but guarantee the back row matters via **adjacency buffs,
     Ranged (hits back row / attacks from back), and lane-matchup keywords** so
     placement is always a real choice (this is the Hearthstone-adjacency + Inscryption-lane
     blend you're already part-way to).
   - *Boldest:* add **one** Wildfrost-style front/back lever (front-only Taunt pull,
     pull-wounded-to-hand recycle, back-row can't-be-hit-until-front-clears) and you
     instantly get Wildfrost's proven depth.
   - *Leanest:* if neither, consider 4×1 + a 2-slot reserve — fewer slots, less
     screen clutter, same fantasy.

2. **Screen real estate / readability (you have the most slots here bar Duelyst).**
   16 field cards + hand is a lot. The compact landscape tokens and the drag-snap
   fix were necessary, not optional. Keep auditing: can a new player tell, at a
   glance, which front unit fights which? Direct-opposing front lanes (archetype C)
   are your legibility lifeline — never muddy them.

3. **Simultaneous combat hurts the forward-telegraph that sells Monster Train &
   Wildfrost.** Those games let you *see the hit coming* (climbing enemies / attack
   counters). BM resolves both sides at once. Mitigate by **telegraphing next-round
   enemy placement + the incoming-damage chip you already have**, so the board reads
   *forward*, not just "now."

4. **Cards, not the board, are the moat (the universal lesson).** StS, Inscryption,
   Monster Train won on interaction depth; Banners lost on card thinness with a
   near-identical board. Spend your marginal hour on card variety/keyword combos,
   not on more board geometry.

**Visual/budget posture:** You are correctly in the cheap-durable lane. Match
Inscryption's lesson — invest in **mood, frame craft, and readability** (which you
already obsess over) rather than fidelity, and never let art polish outrun card
depth (Banners). The board doesn't need to be bigger or prettier; it needs every
slot to mean something and every matchup to read instantly.

---

## 5. Sources

- Wildfrost sales/board: [GameSensor](https://gamesensor.info/news/wildfrost_sales_first_week),
  [SteamSpy](https://steamspy.com/app/1811990),
  [Steam-Revenue-Calculator](https://steam-revenue-calculator.com/app/1811990/wildfrost),
  [Wildfrost Wiki – Attack Order](https://steamcommunity.com/app/1811990/discussions/0/3826413850808726540/),
  [Beginners guide](https://gameplay.tips/guides/wildfrost-beginners-guide.html)
- Monster Train: [TechRaptor (MT2 500k)](https://techraptor.net/gaming/news/monster-train-2-sales-500k-first-dlc),
  [PCGamesN roadmap](https://www.pcgamesn.com/monster-train-2/roadmap-updates-dlc),
  [Wikipedia](https://en.wikipedia.org/wiki/Monster_Train),
  [Monster Train Wiki – Battle](https://monster-train.fandom.com/wiki/Battle)
- Inscryption: [PCGamesN (1M)](https://www.pcgamesn.com/inscryption/sales),
  [TechRaptor](https://techraptor.net/gaming/news/inscryption-sales-shuffle-past-one-million),
  [Wikipedia](https://en.wikipedia.org/wiki/Inscryption)
- Marvel Snap: [Game World Observer ($116M Y1)](https://gameworldobserver.com/2023/10/18/marvel-snap-mobile-revenue-116-million-first-year-appmagic),
  [PocketGamer.biz ($275M, 2yr)](https://www.pocketgamer.biz/marvel-snap-surpasses-275-million-as-it-celebrates-second-anniversary/),
  [Hollywood Reporter ($100M Series B)](https://www.hollywoodreporter.com/business/business-news/marvel-snap-second-dinner-investment-griffin-1235782058-1235782058/),
  [Wikipedia](https://en.wikipedia.org/wiki/Marvel_Snap)
- Banners of Ruin: [Steam](https://store.steampowered.com/app/1075740/Banners_of_Ruin/),
  [OpenCritic](https://opencritic.com/game/11788/banners-of-ruin/reviews),
  [Steambase reviews](https://steambase.io/games/banners-of-ruin/reviews)
- Card Wars: [Adventure Time Wiki](https://adventuretime.fandom.com/wiki/Card_Wars_(game)),
  [Cult of Mac review](https://www.cultofmac.com/reviews/card-wars-adventure-time-absolutely-can-floop-pig-review)
- Duelyst: [Wikipedia](https://en.wikipedia.org/wiki/Duelyst),
  [PC Gamer (shutdown)](https://www.pcgamer.com/duelyst-to-shut-down-servers-forever/),
  [Kotaku](https://kotaku.com/gorgeous-tactical-rpg-duelyst-is-shutting-down-next-mon-1841219586)
- Slay the Spire: [PCGamesN (1.5M)](https://www.pcgamesn.com/slay-the-spire/slay-the-spire-sales),
  [TweakTown (StS2 3M)](https://www.tweaktown.com/news/110465/slay-the-spire-2-is-a-big-hit-with-3-million-copies-sold-in-just-a-week/index.html),
  [Wikipedia](https://en.wikipedia.org/wiki/Slay_the_Spire),
  [Mega Crit](https://www.megacrit.com/about/)
- Gwent: [Wikipedia](https://en.wikipedia.org/wiki/Gwent:_The_Witcher_Card_Game),
  [GamesHub (Gwentfinity)](https://www.gameshub.com/news/features/gwent-end-of-an-era-gwentfinity-and-beyond-2631981/),
  [gamepressure (financial disappointment)](https://www.gamepressure.com/newsroom/gwent-a-financial-disappointment-kotaku-reports/z186c)
- Legends of Runeterra: [Dot Esports (scaled back)](https://dotesports.com/lor/news/legends-of-runeterra-to-be-drastically-scaled-back-due-to-financial-shortcomings),
  [Mastering Runeterra (profitability)](https://masteringruneterra.com/does-legends-of-runeterra-make-a-profit/)

---

## 6. Prior art — does this analysis already exist?

**Short answer: the two halves exist separately and are well-trodden; the specific
combination this document makes — board topology *practical implications* across
these lane/front-back games, cross-referenced with their *commercial performance
vs budget and visuals* — was not found as a single published piece.** The board-
design literature and the market literature live apart; nobody (that surfaced) joins
"this board shape creates these problems" with "and here's how its games did
financially relative to their art/budget." Read the best of each half before
treating any conclusion here as original:

**Board / spatial design (exists, good):**
- **[Game Developer — "Spatiality in Game Design"](https://www.gamedeveloper.com/design/spatiality-in-game-design)**
  — the closest existing *comparative* board analysis. Explicitly contrasts Gwent
  (rows 3→2, "space as scarce resource"), Hearthstone (1 row, no movement),
  Minion Masters (continuous space), Artifact (row identity), MtG, Prismata. **No
  commercial tie.** Best single read on the design half.
- **[Problem Machine — "Wildfrost" (2023)](https://problemmachine.wordpress.com/2023/05/03/wildfrost/)**
  — design essay dissecting Wildfrost's "pair of three-tile lanes" board vs Monster
  Train / Slay the Spire / Hearthstone. Single-game focus.
- **Ben Brode / Second Dinner talks** (AIAS Game Maker's Notebook) — Marvel Snap's
  board philosophy: a "grocery cart" of Clash Royale + Backgammon + Smash Up.
- **[Medium — "Designing a TCG: Frontline vs. Backline"](https://medium.com/@Heathrileyo/designing-a-tcg-game-board-layout-frontline-vs-backline-and-strategic-choice-8eb3effff7d1)**
  — a dev-blog tips essay on one author's own TCG (only names Pokemon); thin.

**Commercial / market (exists, solid):**
- **[Game World Observer / Chris Zukowski + VG Insights](https://gameworldobserver.com/2022/04/22/roguelike-deckbuilders-beat-all-indie-genres-on-steam-in-terms-of-sales-but-only-99-such-titles-released-since-2019)**
  — the canonical datapoint: roguelike deckbuilders have the **highest median sales
  of any indie genre** on Steam, yet only ~99 releases (2019–22). No board, no
  budget/visual angle.
- **[Tavrox — "Deckbuilding: Market Analysis"](https://tavrox.medium.com/deckbuilding-market-analysis-for-lovecrafting-345a5f96dd26)**
  — an indie dev's market study of the deckbuilder space.
- **Roguelike-games market reports** ([MarketIntelo](https://marketintelo.com/report/roguelike-games-market),
  Verified Market Research) — genre size forecasts (~$3.8B 2025 → ~$9–10B by 2033–34);
  generic and partly paywalled.
- **[GDC Vault — "Slay the Spire: Metrics Driven Design and Balance"](https://www.gdcvault.com/play/1025731/-Slay-the-Spire-Metrics)**
  — balance methodology, not board comparison.

**The "cheap budget + simple visuals = success" thesis** is asserted qualitatively
in many places (e.g. [Wikipedia's roguelike-deckbuilder entry](https://en.wikipedia.org/wiki/Roguelike_deck-building_game):
the genre "doesn't require a large amount of artistic assets"), but is nowhere tied
back to board geometry. That join is what §2–§4 above contribute.
