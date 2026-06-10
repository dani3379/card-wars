# Burning Meadow — Lore Bible

**Status:** Live canon as of the first lore pass (Direction C). This document is
**dev-facing**. The *game* never states any of this outright — it only ever
implies. The bible knows; the game whispers. If you are writing new events,
cards, relics, encounters, or UI copy, everything here is binding.

> One law above all: **the game implies, it never explains.** The moment a line
> on screen tells the player what the meadow *is*, the spell breaks. Ambiguity is
> the product.

---

## 1. The one-line hook (Steam short description == main-menu epigraph)

These are the **same words**, on purpose — a buyer and a new player are converted
by the same sentence. It currently ships as the main-menu epigraph
(`MainMenu.gd`, in `_rebuild_menu`):

> *You lit the first flame so long ago you've forgotten it was you. The road
> remembers. Everything on it is already expecting you — they always are.*

If you change the epigraph, change the store description to match, and vice versa.

---

## 2. The spine — 5 canonical facts everything obeys

1. **The meadow makes effigies of you. Each run is a new effigy walking the same
   road toward the source.** This is why the roguelike death/restart loop exists
   in-fiction (the "Hades trick" — death is diegetic, not a reset).
2. **You lit the first flame, long ago, and you don't remember doing it.** The
   fire is yours; the guilt is structural, never stated.
3. **Something beneath the meadow is hungry, and the flame feeds it.** It is
   never named, never shown, never explained — only fed. This is the engine
   under the give-something / take-something economy, and it is the same act as
   the sacrifice mechanic at a larger scale.
4. **Everything on the road already knows you're coming, because you've come
   before.** This is the source of the voice — the dread that is also a little
   funny ("they always are").
5. **The grief is that nothing here can finish.** Not the road, not the
   mourning, not you. Deploy grief as a *recurring note*, never as the whole
   song — over-used, it curdles into mope.

### The braid (how the three candidate directions resolved)

The room weighed three "what is the fire" directions and **braided** them rather
than picking one:

- **C — the fire is yours / effigies (THE SPINE, load-bearing).** Only C makes
  the restart loop mean something for free.
- **B — a hungry thing beneath the meadow (THE MACHINE, ambient only).** Powers
  the sacrifice economy. **Never** promote it to the world's stated thesis and
  **never** give it a name — a named god is solvable lore; an unnamed thing you
  feed is dread.
- **A — grief that won't finish (THE GRACE NOTE).** The emotional color, used
  sparingly.

---

## 3. Hard constraints (the hills the room died on)

- **No proper nouns for the unnameable.** "The meadow," "the first flame," "the
  road," "the thing beneath" stay common nouns. The instant the fire becomes
  "the Eschaton-Brand," a player can wiki it, and a nameable thing is a solvable
  thing. Named NPCs/bosses are fine (The Crone, The Collector); the *cosmology*
  is not.
- **The mystery is never explained on screen.** No exposition dump, no codex
  that resolves it. A curious player who hovers everything and wins should come
  away with *more questions than answers*. If anyone can finish a run and write a
  clean paragraph explaining what the meadow is, we over-wrote.
- **Bosses are an anthology, not a plot.** They may *resonate* (see the emergent
  ordering below) but no line may connect them. **Bright line:** no preamble may
  reference another boss, a prior/next trial, an order, a depth, or a
  "first/last." Each preamble must be fully legible to a player who has seen no
  other boss. If you can shuffle the preambles and none break, it passes.
- **Tone is multi-register: horror + funny + grim.** The dry, grieving wit is the
  asset. Protect the comedy; do not sand it off in the name of Theme.
- **Word budgets are hard caps.** Hero stakes: one line. Death refrains: three,
  total. Boss preamble: ~three sentences. Epigraph: three sentences. If a beat
  "needs" more, the beat is wrong, not the limit.

### Emergent boss ordering (allowed — it's curation, not text)

The bosses are *placed* so the threat spirals inward across the acts. This is
felt through placement only; **never** narrated:

- **Act 1 — points outward:** The Iron Warden, The Wyrm-Father. Things that guard
  a road.
- **Act 2 — points inward:** The Collector, The Hollow King. Things that want
  something *from you*.
- **Act 3 — wears your face:** The Hall of Wrong Reflections, The One Who Walks
  Sideways, and the three judgments — THE DEVIL, THE CRONE, THE BLACK TIDE.

---

## 4. What shipped in the first lore pass

All data/string driven; no fragile layout work; no new persistence systems.

| Surface | Where | Notes |
|---|---|---|
| **Menu epigraph** | `MainMenu.gd` `_rebuild_menu()` | The hook; == Steam description. |
| **Diegetic death refrains** | `GameOver.gd` `DEATH_REFRAINS` | 3 lines, rotated by `MetaState.total_defeats`. **Hard cap 3.** |
| **Per-hero stakes** | `HeroDB.gd` `lore` field + `MainMenu.gd` `_make_hero_tile` | One line each, dim violet, between tagline and desc. |
| **Boss preambles** | `EncounterDB.gd` `preamble` field + `Combat.gd` `_show_encounter_intro` | Renders above the mechanical passive in the boss/elite intro banner; hold time scales with length. |

### The hero stakes (why THIS effigy walks toward the fire)

- **Raider** — *You don't outlive the road; you outrun it.* (He lit it first and ran; the arsonist always comes back.)
- **Stalwart** — *Everything here ends eventually. You intend to be the exception.* (He watched the line break and refuses to.)
- **Acolyte** — *Something underneath is always owed. You pay in others.* (She understands the theology and means to audit the debt.)
- **Pyromancer** — *You started this with fire. You see no reason to stop now.* (Unrepentant about the match.)

### The death refrains (rotate by defeat count, cap 3)

1. *The meadow makes another of you. It always has spares.*
2. *You stop here. The road doesn't.*
3. *That's one more walk that didn't reach the fire. There will be others.*

Each sits above the existing `Felled by <encounter name>` line.

### The boss preambles

Three were vetted by the writers' room; four were written to the bright-line
spec during implementation. All are standalone "cards of ill omen."

- **The Iron Warden** *(authored)* — It was built to hold a wall that no longer stands. No one has told it the siege is over, and it would not believe you. Every death you hand it only loads it again.
- **The Wyrm-Father** *(room-vetted)* — Something old coils across the road and calls it a nest. It has guarded this way longer than the meadow has burned. It does not know your name, and it does not need to.
- **The Collector** *(room-vetted)* — It keeps things. Faces, mostly — the ones the road wears out. It has been saving a place for yours, and it is patient about filling it.
- **The Hollow King** *(room-vetted)* — There is an eye here that decides what gets to continue. It has looked at you before and found you wanting. It is willing to look again.
- **THE DEVIL** *(authored)* — It deals fairly — that is the worst of it. Everything it offers, it takes back with interest, and you put your mark to the page a long walk ago. It is only here to collect.
- **THE CRONE** *(authored)* — She was old when the meadow was green. She has watched a great many of you climb this road, and she has never once been wrong about the ending. The kettle is already warm.
- **THE BLACK TIDE** *(authored)* — It is not water, though it rises like water. It has been climbing toward this place one drowned thing at a time, since long before you. It is patient about the rest of you.

---

## 5. The stop list (do NOT build)

- **An accreting / discovery codex.** Needs new persistence + per-creature
  discovery hooks = multi-day. Out. (The events already *are* an interactive
  codex.)
- **100% card-flavor coverage.** Flavoring all 152 cards is a writing project in
  disguise. If card flavor happens, it's a *narrow* subset (loop tokens, hero
  signature cards, boss enemy cards) in the hover detail popup — never the
  pixel-measured card face.
- **A 4th death line / any counter past 3.** Cap is 3, by design.
- **Any cross-boss connective text.** See the bright line in §3.
- **A proper noun for the unnameable.** See §3.
- **An animated / multi-screen intro cutscene.** The intro is one static line
  (the epigraph) or it's scope creep.
- **Per-death "Hades-style" reactive dialogue.** No voiced cast, no walk-back,
  no relationship system to attach it to — it's a content treadmill with no
  payoff here.

---

## 6. Acceptance test (did the lore actually land?)

Judge against the first 90 seconds, not a lore wiki:

- **Buyer test:** the Steam description and the menu epigraph are the *same
  words*; a cold visitor feels recognition, not mismatch.
- **New-player test:** a player who reads nothing optional still absorbs the
  premise (you are a thing the meadow keeps re-casting) from the epigraph + the
  first death screen alone. The mandatory surfaces carry it; the optional ones
  (hero lines, future card flavor) are reward for attention, never load-bearing.
- **Restraint test:** a player who hovers everything and wins comes away with
  *more questions than answers* and zero proper nouns for the unnameable.

---

## 7. Fast-follow backlog (vetted-to-spec, not yet built)

- **Remaining boss/elite preambles** — the `preamble` field is optional; voice
  the remaining elites (e.g. The One Who Walks Sideways) when copy is ready.
- **Narrow card flavor** — loop tokens (effigy/ash), hero signature cards, and
  act-boss enemy-only cards, shown in the hover detail popup
  (`Card2D._build_detail`), never the card face.
- **Act-keyed death refrains** — optionally key the 3 refrains off
  `RunState.get_act()` instead of defeat count, so they read as *progress* (where
  you fell) rather than shuffle. Still capped at 3.
