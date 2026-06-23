# Skirmish Deck-Interest Backlog

Register of improvements to make the **decks and cards players GET** in online Skirmish
more interesting. Generated 2026-06-23 by a 5-agent design pass (pool/denylist · draft ·
quick+sealed · archetype-system+constructed · new-modes). Full code snippets live in the
originating conversation; this is the condensed, implementable register.

## Root cause (why MP decks feel bland today)
1. **Every mode rolls uniform-random from one flat list** (`SkirmishState.skirmish_legal_pool()`).
   `NetDraft._roll_triplet`, `NetQuick._regenerate_deck`, `NetSealed._regenerate_pool` — all
   uniform. No rarity weighting (a rare is ~19% noise, never an event), no archetype/synergy
   seeding (no theme to chase), no curve control (a deck can be all 2-drops or spell-flooded).
2. **The pool is a narrowed subset.** `SKIRMISH_DENYLIST` + the net-playable-spell gate strip
   out Discover, draw engines, tutors, gold, and ~24 unported custom spells — so the most
   build-around cards are simply absent in MP.
3. **No archetype identity** anywhere — nothing groups cards into themes, so you can't draft
   or build "a poison deck"; you get goodstuff soup.

## Hard constraints (any implementation must hold)
- **Determinism:** host & client generate IDENTICAL pools/triplets from the shared seed
  (`NetMatch.match_seed`; per-side decks use an index salt). No negotiation. Every roll routes
  through a seeded `_rng`; all source arrays sorted before use. (Interactive shared-pool modes
  sync an ordered event log instead — see Rotisserie.)
- **Net-playability:** spells must resolve over the wire; creatures always work. v1 relic-free.
- Keep the deck-handoff contract (`{"t":"finished","cards":[…]}` → peer stores → host
  `launch_combat()`) and the host `cfg`-broadcast pattern.
- COPY_STYLE for any player text (Command not mana; keywords Capitalized).

---

## STATUS LOG
- **2026-06-23** — design pass complete (this doc). Nothing implemented yet.

---

## P0 — THE KEYSTONE: shared archetype system (build first; everything consumes it)

**New file `scripts/net/SkirmishArchetypes.gd`** — `class_name SkirmishArchetypes extends RefCounted`,
all `static`, no RNG/state (pure over `CardDB`), so host/client/headless share one source of truth.

**8 archetypes, each backed by ≥6 legal cards** (verified against the legal pool):

| tag | name | thesis | key members (real ids) |
|---|---|---|---|
| `swarm` | Massed Ranks | flood cheap bodies/tokens, buff the board | squire_captain, gravecaller, mule, summoner, standard_bearer, torchbearer, battle_drummer, paladin, overwhelming_force, kings_command |
| `poison` | Withering | trade up — poison kills anything it scratches | plague_rat, basilisk, the_apothecary, carrion_priest, corpse_eater, husk |
| `spells` | Spellcraft | cast a lot; casters scale per spell | hexblade, emberwright, leyline_conduit, chaos_imp, witch, mana_sprite + the damage/buff spells |
| `wall` | The Shieldwall | armor/guardian stall, win late | shieldbearer, warding_stone, stone_wall, husk, iron_bastion, crystal_sentry, shieldmaiden, royal_guard, siege_golem, hydra |
| `death` | The Reckoning | your dead are the fuel | necromancer, gravecaller, revenant, blood_pyre, thornguard, corpse_eater, warden_of_graves, the_glutton, vampire_lord + offering/fuel_the_pyre |
| `ranged` | Sharpshooters | snipe back line / soft targets | raven, hexblade, witch, skirmisher, cinder_acolyte, emberwright, harpy |
| `pressure` | The Charge | swift/overrun/rampage — race them | lookout, duelist, glass_knight, assassin, ash_hound, ember_stalker, lancer, breaker, hellfire_imp, vengeance, berserker |
| `doom` | The Pyre | bombs on a fuse → face + nova | cinder_pup, kindling, burning_martyr, hellfire_imp, cinder_whelp, doom_knight, ember_warden |

Micro-tags (synergy hints only, <6 cards): `sustain` (lifelink), `ramp` (Command).
Membership is a **data rule** per archetype (`kw` / `passive` / `field` / `spell_id` / `spell_type` / `ids`),
matched OR. **API the modes call:** `archetypes_of(id)`, `pool_for(tag, legal=[])`,
`deck_archetype_breakdown(ids)`, `deck_identity(ids)`, `deck_curve(ids)`, `synergy_hints(ids)`,
`themed_deck(tag,rng)`, `structured_pool(tags,…,rng)`, `draft_lean_pick(triplet,deck)`.
Thin wrappers on `SkirmishState` (`archetype_pool`/`archetype_list`/`display_name_for`) give a
graceful fallback to today's behavior if the file is absent.
**Corrections flagged:** `cinder_acolyte` is lifelink+ranged (NOT poison); `echo_spell`, `venom_tip`,
`ricochet` are net-DENIED so they can't anchor `spells`.

---

## P1 — Pool widening (un-thin the pool; mostly free)

The single highest-ROI batch. In `Combat._net_resolve_custom_spell` add a resolver arm + add the
id to `SkirmishState.NET_SPELL_CUSTOMS` (the `_probe_skirmish` parity check enforces both).

- **Port 8 board/face-only spells — NO new infra, ~40 lines total, roughly DOUBLES the legal spell pool:**
  `ricochet`, `holy_smite`, `banish`, `time_snare`, `charge_spell`, `venom_tip`, `frost_bolt`, `hoarfrost`.
  (They only touch nodes / the caster's enemy face; nothing private.) `venom_tip` makes Poison a real archetype.
- **Add `_net_owner_draw(is_enemy_owner,n)`** (~15 lines, reuses the existing EV_DRAW wire) and route
  `draw_on_ally_death` / `damage_opposing_draw` through it → **frees `gravedigger` + `bloodhound`** from
  the denylist (the best draw-engine creatures; glue for go-wide/aristocrats).
- **Port `adrenaline` + `bloodletting`** (trivial, use the proven `_net_caster_gain_mana`) → un-thins Ramp.
- Later: discard-count field → revive `mass_grave`; a remote-hand-pick round-trip → `war_chant`/`gambit`/`scrap`/`recycle`;
  per-owner last-dead → reanimator spells; Discover is the hardest, defer.
- **Curation hygiene:** audit `mule`/`witch`/`mana_sprite`/`leyline_conduit` — their gain/discount may
  resolve host-only; fix routing per-owner or deny honestly.

**Archetype buildability today:** Poison = the only UNbuildable archetype (2 bodies, 0 payoff, gated enabler).
Swarm & Ramp are payoff-complete but enabler-thinned by exclusions. Everything else is playable→strong
(spells, wall, doom, death, pressure are strong).

---

## P1 — Per-mode upgrades (each consumes the keystone; deterministic)

### Draft (`NetDraft._roll_triplet`) — give it a power arc + a theme to chase
- **Rarity cadence:** guaranteed rare feature-slot on picks 5/10/15/20, uncommon on 3/8/13/18; other
  slots use banded weights (commons early → payoff-dense late). Telegraph it ("RARE PICK") with
  `GameTheme.rarity_color`.
- **Archetype lean:** bias offers toward tags already in `SkirmishState.local_slot().deck` (deterministic,
  identical per side), capped (+2.2) with recency weighting so pivots stay possible.
- **Curve + spell-flood guards:** soft-downweight an over-stuffed cost bucket (>55%); suppress spells past 8.
- Optional: exclude the 8 vanilla starters from offers; a pick-1 "archetype banner" to declare a direction.

### Quick (`NetQuick._regenerate_deck`) — coherent decks, not soup
- Seed-pick 1–2 archetypes; build to a **curve template** `[3,8,6,2,1]` (cost 0/1/2/3/4+), drawing ~60%
  from the leaned pools + 40% glue (`SkirmishArchetypes.themed_deck`). Keep the max-2-copies cap.
- **Surface the theme name** in the header. Optional host "stock warband" picker via an extra `cfg` key.

### Sealed (`NetSealed._regenerate_pool`) — structured opening with direction
- Slot the 30-card open: ~4 rares + 8 uncommons (rarity floors) + a **two-archetype core** (so synergy
  pieces co-occur) + curve-filled glue; enforce a spell floor/ceiling (4–9) so every pool is buildable
  (`SkirmishArchetypes.structured_pool`). Surface the lean ("leaning Pyre or Wall").

### Constructed (`NetConstructed`) — make building a themed deck fun, not a spreadsheet
- **Archetype filter chips** (browse the pool by theme), **live deck "identity" readout**
  (`deck_identity` → "Leaning: Withering ×7"), **curve histogram** (`deck_curve`), **synergy hints**
  (`synergy_hints` → "Hexblade scales per spell — you're light on spells"), and a **"Fill Theme"** button
  that finishes a coherent deck. All pure reads of the keystone; nothing new on the wire.

---

## P2 — New acquisition modes (a mode = a new scene + one MODE_DEFS entry)

### #1 (recommended) — ROTISSERIE: shared-pool snake draft
The genuinely interactive draft the current private-stream Draft lacks: one face-up shared board
(deterministic from seed), players alternate taking one card each, a taken card is gone for both →
real signal-reading & hate-drafting. **Net protocol:** host serializes; client picks are `take_req`s
the host confirms with an authoritative `take{pick,by,card}`; board is never sent (only the ordered
take log; `pick == log.size()` is the ordering invariant). Snake order (default) for fairness. Full
scene skeleton in the conversation. Medium build, highest skill/replay payoff.

### #2 — SPOTLIGHT: themed draft (cheap)
= NetDraft with the triplet source swapped: each pick offers cards from one rolled archetype, so you
build a coherent deck by construction. Host toggle Focused (tight) vs Kaleidoscope (flexible). Trivial
net (independent streams + `cfg`).

### #3 — HIGHLANDER: singleton from themed packs (cheapest)
= NetSealed with copy-cap 1 and the 30-card pool dealt as ~5 themed packs. Singleton inverts the value
curve (flexible/reach cards spike; can't tunnel one archetype). Trivial net (= NetSealed).

---

## RECOMMENDED BUILD ORDER
1. **P0 `SkirmishArchetypes.gd`** + the `SkirmishState` wrapper/fallback. (Foundation; zero risk — nothing
   references it until wired. Verify every member id exists in CardDB; parse-check.)
2. **P1 pool ports** (8 free spells + `_net_owner_draw` → free gravedigger/bloodhound; adrenaline/bloodletting).
   Run `tools/_probe_skirmish.gd` / `_probe_skirmish_combat.gd` to verify parity + over-wire resolution.
3. **P1 Constructed UX** (highest "building is fun" win, pure reads) → **Quick** themed → **Sealed** structured
   → **Draft** cadence+lean (one mode at a time; each is one call-site swap + helpers).
4. **P2 Rotisserie** (the marquee new mode), then Spotlight + Highlander (cheap riders on the system).

Verify after each step: headless parse, then `_probe_skirmish*` for net resolution. Skirmish combat is
mode-agnostic — none of this touches the combat layer except the P1 spell ports.
