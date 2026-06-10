# Card-Game Draw / Hand-Refill Systems — Complete Catalog

The companion to `MANA_SYSTEMS.md`: every way games hand you cards each turn, organized by
**how your hand refills**, plus the cross-cutting axes. Named examples throughout. Built from
existing research (cited) + the systems those taxonomies miss.

**Prior research this builds on:**
- [Erik Twice — "A comparison of draw systems in customizable card games"](https://eriktwice.com/en/2019/02/12/a-comparison-of-draw-systems-in-customizable-card-games/) — the canonical taxonomy (draw 1-2 / draw-as-played / draw-up-to-handsize / draw-as-resource / draw-as-action). The draw equivalent of Rempton's mana piece.
- [Flaregate — "Roguelike Deckbuilder Tropes"](https://www.flaregatenetwork.com/blog/roguelike-deckbuilder-tropes-1) & [Gunslingers Revenge — Roguelike Deckbuilder Mechanics](https://www.gunslingersrevenge.com/posts/deckbuilders/roguelike-deckbuilder-mechanics-explained.html) — the fresh-hand (Dominion) vs persistent-hand (MtG) divide.
- [CVGS — "What Slay the Spire Gets Right" about card draws](https://criticalvideogamestudies.com/exploring-card-draws-what-slay-the-spire-gets-right/) — the key insight that in fresh-hand games, drawing buys *this-turn tempo*, not long-term card advantage.
- Hand-size limits: [MtG Wiki](https://mtg.fandom.com/wiki/Hand_size), [Yugipedia](https://yugipedia.com/wiki/Hand_size_limit), [TV Tropes — Hand Limit](https://tvtropes.org/pmwiki/pmwiki.php/Main/HandLimit).

---

## PRIMARY MODELS — how your hand refills each turn

### A. Trickle: draw a fixed 1–2/turn, **hand persists**  *(the TCG standard)*
You draw a small fixed number each turn and **keep what you don't play**, accumulating options.
**MtG, Hearthstone, Pokémon TCG, Yu-Gi-Oh, Legends of Runeterra, Marvel Snap, VS System.**
- Card advantage is a *long-term* resource (more cards = more total plays over the game).
- The decision is **hold vs. deploy / when to spend** each card.
- ⚠ Erik Twice's critique: a game is often "decided by the ~12 cards you see," so cards must be versatile.

### B. Refill **up to hand size at end of turn**, hand persists  *(top up what you spent)*
You keep your held cards and draw back up to N at end of turn — so you replace what you used but
don't flush what you held. **KeyForge, Middle-earth CCG, Doomtown, Rage.** (Erik Twice #3)
- Easy access to cards with a ceiling; ⚠ tends to make cards cheap, needs other limiters.

### C. Fresh hand each turn: **discard leftovers, draw N at start**  *(the roguelike-deckbuilder standard)*
At turn start you draw a full hand of N; at turn end you **discard whatever you didn't play**;
when the draw pile empties, the discard reshuffles in. **Slay the Spire (5), Monster Train (5),
Dominion (5), most roguelike deckbuilders, *Burning Meadow (4).***
- Promotes **rapid deck cycling** (you see your whole deck fast — good for a build-a-deck genre).
- **Crucial consequence (CVGS):** because the hand resets, **drawing more only buys *this-turn*
  tempo, not long-term card advantage** — you can't bank the extra cards, you dump them. This is
  why "just draw more" doesn't add hand-management depth in this model; it adds *this-turn* burst.

### D. Draw **as cards are played** (play one → draw one)
The hand stays full because playing refills it. **Vampire: The Eternal Struggle** (play a card,
draw a card); **Clash Royale** (play one, the next of your 8-card deck cycles in — real-time).
(Erik Twice #2) ⚠ makes cards cheap; constant refill can flatten scarcity.

### E. Draw **as an action** (drawing competes with everything else)
Drawing a card costs one of your limited actions, same as any other play. **Android: Netrunner**
(spend a click to draw). (Erik Twice #5, which he calls the best — *self-balancing*: you only draw
when it's worth more than the other thing you'd do with that action.)

### F. Draw **as a resource** (pay to draw)
Spend money / life / honor to draw extra. **Legend of the Five Rings LCG, Star Wars CCG (Decipher).**
(Erik Twice #4) ⚠ feedback-loop risk; added complexity.

### G. Draw-and-choose / filtered draw (see more than you keep)
A decision baked into the draw itself: **draw 2 keep 1**, scry-then-draw, or **choose which pile**
— **Inscryption** (each turn draw from your creature deck *or* the squirrel/resource deck). Adds a
draw-time choice and smooths variance.

### H. Conditional / position-based draw
Your draw count depends on board state / position / a chosen plot. **A Game of Thrones LCG** (plot
decks set draw/economy each round); various LCGs where moving/position changes draw.

### I. Finite pool, **no reshuffle** — card advantage *is* the game
You get a starting hand and a few cards per round from a deck that **never reshuffles**; running
out means you stop drawing. **Gwent** (≈25-card deck, ~16 seen across 3 rounds). Every card spent
is gone forever, so *card economy* is the central resource.

---

## CROSS-CUTTING AXES — combine with any model

1. **Persistent hand vs. fresh-each-turn** — *the load-bearing divide.* Persistent (A/B/D) = you
   hold and bank options, draw = long-term advantage, "when do I spend this" is a decision.
   Fresh (C) = use-it-or-lose-it, draw = this-turn tempo only, you dump the hand.
2. **Hand-size cap + overdraw rule:** discard down to cap (MtG 7, Yu-Gi-Oh 6), **burn** the overdraw
   (Hearthstone 10 — gone forever), **stop drawing** at cap (Marvel Snap 7), or no cap.
3. **Deck cycling:** reshuffle the discard (deckbuilders — see your deck fast) vs. **no reshuffle /
   deck-out = loss** (MtG mill, Pokémon, and Gwent's finite pool).
4. **Mulligan / opening hand:** London mulligan (MtG), replace-any (Hearthstone), redraw (LoR/Snap)
   — start-of-game variance smoothing.
5. **Draw acceleration / filtering:** cantrips (cards that replace themselves), tutors (search deck
   for a specific card), scry/look-at-top (filter), cycle/discard-to-draw (pitch for a fresh card).

---

## The honest summary of the design space

Two root questions decide almost everything:
1. **Does your hand persist (you hold unplayed cards) or refresh (you discard and redraw)?**
2. **How do new cards arrive — a fixed trickle (A), a top-up (B/C), tied to playing (D), bought
   with an action/resource (E/F), or a finite no-reshuffle pool (I)?**
Everything else (hand cap, overdraw rule, cycling, mulligan, filtering) is a modifier on those two.

---

## Relevance to Burning Meadow

BM is **model C** — fresh hand of 4, discard the leftovers, reshuffle. That's the roguelike-
deckbuilder default, and the CVGS insight is exactly your situation: **in a fresh-hand game, drawing
is only this-turn tempo, and a cheap-card hand just gets dumped.** So "draw more" *cannot* fix the
flat turn by itself — you'd dump more.

The levers that actually change the decision:
- **Switch to a persistent hand (model A or B)** — draw a trickle (or top up to a small cap) and
  *keep what you don't play*. This is the single change that converts "dump the hand" into "hold the
  right creature for the right turn," and it pairs naturally with the deploy-cap / sacrifice economy
  from `MANA_SYSTEMS.md` (cap *what you can play*, persist *what you hold*).
- If you keep model C, then the only honest draw levers are **draw-and-choose (G)** for a draw-time
  decision, and **smaller hands** so the dump is at least a *small* set you pick from.

Note the pairing: a **deploy cap** (you can only play 1–2 creatures/turn) is nearly pointless on a
fresh-hand-discard model (you'd lose the cards you couldn't play), but it's *excellent* on a
persistent hand (you hold them for next turn). **The draw model and the play/cost model have to be
chosen together** — that's the whole point of having both this catalog and the mana one.
