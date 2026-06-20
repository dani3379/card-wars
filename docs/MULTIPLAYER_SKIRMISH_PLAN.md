# Burning Meadow — Online Multiplayer (Skirmish + Draft) Technical Plan

> **Status:** Phases 0–1 BUILT & parse-verified (lobby + draft). **Phase 2 + the
> creature slice of Phase 3 BUILT & parse-verified 2026-06-16** — the full chain
> Menu → Lobby → Draft → networked Combat compiles and is wired end to end.
> Combat model: **full alternating (Hearthstone-style)** — see §2.
>
> **v1 combat architecture as built (refines §12-13): HOST-AUTHORITATIVE with
> FULL BOARD-SNAPSHOT SYNC.** Draw + Command are local per side (each player
> draws their own deck on their own turn via the existing `_start_round`, with
> relic/mutator/encounter branches inert in net). Placement, on-enter/on-death,
> and the attack clash run ONLY on the host; after every mutation the host pushes
> a complete board snapshot (`EV_BOARD_SYNC`) and the client reconciles by
> `entity_id` (= the card's deck uid for drafted creatures; host-issued ≥1,000,000
> for tokens). The client never resolves combat — it sends intents, renders
> snapshots. This collapses the §9 fine-grained event set into one reconcile
> channel for v1; the other `EV_*` stay reserved for a later per-strike replay.
>
> **BUILT (v1 scope):**
> - **CREATURES** — place (client intent → host seats on its enemy side, runs
>   on-enter) → clash → on-death → match-over on a hero ≤0 → return to menu.
> - **CLASH** — Swift pre-pass + main column strike + active-side Ranged, all
>   reusing the campaign resolvers (`_resolve_swift_attack` / `_resolve_column_attack`
>   / `_resolve_ranged_attacks(side_filter)`), so Armored / Thorns / Piercing /
>   Last Stand / Lifelink / Rampage / on-death come free.
> - **SPELLS** — both players' spells resolve on the host through one
>   perspective-aware resolver (`_net_resolve_spell`, caster 0=host/1=client).
>   Targeted spells carry perspective in the target `entity_id`; face/AoE flip on
>   `caster_is_enemy`. Supported set gated at play time (`NET_SPELL_TYPES` +
>   `NET_SPELL_CUSTOMS`): damage / damage_face / damage_all_enemies / damage_all /
>   buff_atk / buff_hp / heal / buff_all_atk + lightning / shove / second_wind.
>   Unsupported spells are refused with a message (never a silent fizzle).
>
> - **POLISH** — the client animates each board snapshot (hit-recoil + floating
>   damage/heal numbers on stat deltas, ash-burst on deaths, screen-shake +
>   number on face damage), so combat reads as a clash even though the client
>   never runs the resolver. Opponent hand size shows in the "Opponent's turn"
>   line (`EV_HAND_COUNT`). Mid-match disconnect (`peer_left` / `host_closed`)
>   ends cleanly and returns both peers to the menu (plan §15).
>
> All Combat.gd net code is `_is_net()`-guarded; **solo campaign is untouched**
> (the only shared-signature change is `_resolve_ranged_attacks(side_filter=-1)`,
> whose default reproduces the old both-sides behavior). **DEFERRED:** combat-time
> floop toggles and battlefield reposition (both cleanly gated OFF in net — board
> interactivity stays off; hand plays + spell targeting still work; floop is
> largely superseded by on-play, which IS netted), exotic spells
> (pile/draw/discover — already denylisted in draft), a dedicated opponent
> hand-count widget (only the turn-line readout exists), and per-strike clash
> replay (§13.2 strategy B — the coarse snapshot animation is the v1).
>
> **VERIFIED HEADLESS 2026-06-16** (all three layers; see §16 items 6–8):
> the logic probe, a fake-peer COMBAT harness that boots the real combat scene
> as NET_HOST and drives a full turn cycle with scripted client intents (turn
> open + local draw, host creature play + on-enter + entity_id registration, the
> attack clash, turn passing, client creature/spell intents, match-over) AND
> reboots it as NET_CLIENT to verify the board-snapshot reconcile (owner→side
> mapping, HP perspective, spawn/update/despawn), and a two-process ENet
> TRANSPORT smoke test over loopback (host/join, ready handshake, match-seed
> propagation, client→host intent + host→client event round-trips — the same
> @rpc path Tailscale uses). All green. The only thing still unexercised is a
> live human-played match WITH rendering (visual/animation feel, the draft/lobby
> UI clicks) — the code under it is verified; that pass is the designer's to run.
>
> **v1 RULES TUNING 2026-06-16** (fairness pass, all in `Combat.gd`, all probe-covered):
> (1) **Turn-1 is place-only** — the opener can't attack into an empty board for
> free face damage; `_net_run_attack` skips the strike pass when `_net_turn_round == 1`
> and the ATTACK button reads "END TURN" that turn. The second player gets the
> first contested attack on turn 2. (2) **Going-second compensation** — the client
> (always the second turn) has its opening hand PRE-DEALT at match start
> (`_net_begin_combat`) at `HAND_REFILL_TARGET + 1` (= 6) so it's visible/plannable
> during the host's turn 1 AND carries the extra card; a `_net_skip_draw_this_round`
> flag makes its first `_start_round` keep that hand instead of topping it up.
> (3) **Rematch / stay-connected** — match-over shows a REMATCH / LEAVE TO MENU
> overlay instead of auto-dropping to the menu; both sides pressing REMATCH has the
> host re-`launch_combat()` with the SAME drafted decks. `NetMatch._enter_combat_local`
> now calls `SkirmishState.refresh_heroes()` + clears the entity registry every
> launch (no-op on first fight, full reset on rematch). New wire verbs `IN_REMATCH`
> / `EV_REMATCH`; `_net_on_peer_lost` handles a post-match leave too.
>
> Last updated 2026-06-16.
>
> **Audience:** an engineer or AI agent who has *not* seen this conversation. This
> doc is meant to be self-contained: it describes the existing single-player
> architecture it builds on, the target design, and a phased build order with
> file-level changes. Read §0 first.

---

## 0. How to use this document

The goal feature: a standalone **online 1-v-1 mode** where two friends each
**draft a 20-card deck (pick 1 of 3, twenty times)** and then **fight each other**
across the internet, primarily so the designer can playtest cards against a live
opponent.

This is **not** networked campaign co-op. It does **not** touch the 3-act roguelike,
the map, relics-as-meta-progression, or `RunState` as the run container. It is a
**separate mode** off the main menu. Keeping it isolated is the single most
important scoping decision — see §4.

Build order is in §17. If you are starting cold, do **Phase 0** (transport +
handshake) before writing any card logic. Networking surprises, not game logic,
are what blow up the schedule.

Terminology note: the player-facing turn resource is called **Command**, but
**every code identifier still says `mana`** (`player_mana`, `base_max_mana`,
`gain_mana`, etc.). This doc uses `mana` when naming code and "Command" when
describing UI text. (See `docs/COPY_STYLE.md`.)

---

## 1. The existing single-player architecture (what we build on)

Established by reading the live code. Trust this over older docs.

### 1.1 Scene flow & launch
- Scenes are `.tscn` in `scenes/`, scripts in `scripts/scenes/`. Transitions use
  `get_tree().change_scene_to_file()`.
- `scripts/scenes/MainMenu.gd` starts a run via `RunState.start_new_run(hero_id, ascension, seed)`
  then routes to a blessing pick → map → combat.
- **Combat** (`scenes/combat.tscn` + `scripts/scenes/Combat.gd`) reads everything
  it needs from the `RunState` autoload in `_ready()` (`Combat.gd:359`): hero HP,
  the encounter id, the deck. There is **no constructor argument passing** — the
  scene self-configures from singletons. This matters: to launch a skirmish fight
  we will inject state into the autoload layer (or a new one) before
  `change_scene_to_file`, exactly like the campaign does.

### 1.2 Autoload singletons (all single-player today)
- **`RunState`** (`scripts/state/RunState.gd`) — the *one* player's run: `hero_hp`,
  `hero_max_hp`, `deck: Array[String]` (card ids), `deck_uids: Array[int]`,
  `card_upgrades: Dictionary` (uid → ordered mod stack), `relics: Array[String]`,
  `base_max_mana: int = 3`, `get_max_mana()`, plus map/act state. `get_upgraded_card_data(deck_index)`
  folds the mod stack into a card-data dict.
- **`CardDB`** — `get_card_data(id) -> Dictionary`, rarity pools, `roll_card_reward(...)`.
  Card-data schema is in §7.4.
- **`HeroDB`** — 4 heroes, each a 10-card starter `deck` + signature `relic`.
- **`KeywordEffects`** — keyword dispatchers. **Critical fact for reuse:** every
  dispatcher takes the Combat instance as `ctx` and calls back into it
  (`dispatch_on_enter(card, lane, is_enemy, ctx)`, `dispatch_on_death`,
  `dispatch_start_of_round`). "Combat is always the ctx." So **any combat scene
  that implements the same method surface can reuse KeywordEffects unchanged.**
- `EncounterDB`, `RelicDB`, `AudioBank`, `CardTextureCache`, `GameTheme`,
  `MetaState`, `UserSettings`, `PotionDB`.

### 1.3 Combat.gd — the engine (~11,800 lines)
Key facts that determine the multiplayer design:

**Board model (already symmetric):**
```
var _player_field: Array = [null, null, null, null]   # front row, our side
var _player_back:  Array = [null, null, null, null]   # back row, our side
var _enemy_field:  Array = [null, null, null, null]   # front row, their side
var _enemy_back:   Array = [null, null, null, null]   # back row, their side
```
- `_row_array(is_enemy: bool, row: int) -> Array` is the canonical accessor.
  `ROW_FRONT = 0`, `ROW_BACK = 1`, `LANES_PER_ROW = 4`.
- Every resolution function threads an `is_enemy: bool`. **The combat math does not
  care whether "enemy" is an AI or a human** — this is why PvP is tractable.

**Phase / round state machine:**
```
enum Phase { PLAYER_TURN, RESOLVING, GAME_OVER }
var phase := Phase.PLAYER_TURN
var round_number := 0
```
- `_start_round()` (`Combat.gd:1061`): `round_number += 1`, resets per-turn flags,
  computes `player_max_mana` (from `RunState.get_max_mana()` + relics/mutators —
  all relic/mutator branches are guarded), banks ≤2 mana, draws to a hand target
  (`PERSISTENT_HAND = true`, `HAND_REFILL_TARGET = 5`), sets `phase = PLAYER_TURN`,
  enables the board and the End Turn button.
- Player acts (drag cards, toggle floops, reposition). Resource is `player_mana`.
- `_on_end_turn()` (`Combat.gd:1324`): sets `phase = RESOLVING`, disables board,
  fires `_resolve_intents()` (enemy non-attack intents), then `await _do_combat()`.
- `_do_combat()` (`Combat.gd:1830`): **simultaneous** — Swift pre-phase, then both
  sides attack per lane (front row then back row), then ranged, then deaths. Heavy
  use of `await _short_pause(...)` for pacing. Ends in `_post_combat_sequence()`.
- The AI opponent is driven by `_enemy_place_creatures()` (`Combat.gd:3186`),
  `_assign_intents()` (`6709`), `_resolve_intents()` (`6806`) — all reading
  `EncounterDB`/`_enemy_deck`. **These three are the seam we replace for PvP.**

**The play path (the "intent" funnel):**
- Cards in hand emit `played` → `_on_card_played(card)` (`Combat.gd:3706`) → cost
  check via `_effective_cost(card)` against `player_mana` → `_play_spell` or
  `_play_creature`.
- `_play_creature(card, cost)` (`3763`) reads the **drop position** via
  `_nearest_player_slot(card.global_position + card.size*0.5)` to pick `{lane, row}`.
  **For networking this must be refactored** so the lane/row can come from an RPC
  argument, not only the mouse. See §12.3.
- Spells use a separate targeting mode via `_input()` (`4795`) →
  `_try_resolve_target()` → `_resolve_spell` / `_resolve_custom_spell`.

**Card creation from a data dict:** `_place_enemy_card(data, lane, row)`
(`Combat.gd:3304`) instantiates `CARD_SCENE`, assigns `card.card_data = data`,
seats it in `_row_array(true,row)[lane]`, dispatches on-enter. The player side has
the analogous path inside `_play_creature`. Both are the model for "materialize a
card the remote player committed."

### 1.4 Card2D — the unit (`scripts/Card2D.gd`, ~5,400 lines)
- `PanelContainer` carrying both UI and gameplay state inline. Key fields:
  `card_id: String`, `deck_uid: int = -1`, `card_data: Dictionary`,
  `current_atk`, `current_hp`, `current_lane`, `current_row`, `is_opponent`,
  `is_on_battlefield`, `compact_mode`, `will_floop`, `temp_atk_buff`,
  `persistent_atk_buff(+_rounds)`, `doom_counter`, and
  `state: CreatureInstance` (a `RefCounted` with `stunned`, `is_frozen`,
  `has_shield`, plus migrating flags).
- `effective_atk()` is the canonical "real ATK now" — always use it.
- **There is no stable network id today.** Cards are referenced by node ref and by
  `(_row_array, lane)`. We add an `entity_id` — see §8.

---

## 2. THE design decision: combat model (read first)

The user wants classic **alternating turns** ("player 1 plays, then player 2,
then player 1"), like Hearthstone/MTGA, rather than the secret-plan/simultaneous-
reveal model. There are two ways to honor that, and **this choice is foundational —
it changes a large fraction of the build.**

> **DECISION (2026-06-16): the user chose FULL ALTERNATING (Hearthstone-style)** —
> the second option below. On your turn you place AND your creatures attack the
> opponent's board/face, then pass; there is **no** end-of-round simultaneous
> clash. Therefore §12.4 and §13 (written around the simultaneous-clash default)
> are SUPERSEDED by §13.5 (full-alternating round loop & resolver). Everything
> else in the doc — transport, entity ids, draft, intents/events, deck injection,
> Phase 2 plumbing — is model-agnostic and stands as written.

### Option A (NOT chosen): **Alternating placement + simultaneous clash**
Per round:
1. Both players draw and gain Command (automatic, no input).
2. **Player A's placement turn:** A plays creatures/spells, repositions, toggles
   floops — spending Command — then presses **Done**.
3. **Player B's placement turn:** same, then presses **Done**.
4. **The clash:** the host runs the existing simultaneous `_do_combat()` over both
   boards. Both clients watch the same resolution.
5. Next round. (Alternate who places first each round to blunt second-mover
   advantage — see the caveat below.)

**Why this is the default:**
- It **reuses `_do_combat()` and all combat resolution wholesale** — the single
  biggest code asset. Lowest risk, fastest to a playable build, which is the
  user's actual goal ("test things out").
- It **preserves Burning Meadow's identity** — the simultaneous lane clash, Swift
  phase, lane-by-lane trade cascade are the core of the game.
- It still delivers the requested "A plays, then B plays" turn feel.

**Caveat (must be addressed):** whoever places *second* sees the opponent's full
board before committing — a real information advantage. Mitigations, pick one:
- (a) **Alternate the first-placer each round** (cheap, partial fix). *Recommended for v1.*
- (b) **Hide placements until both are Done** (re-introduces a reveal; more UI work).
- For a playtest tool, (a) is fine. Flag it to the designer.

### Alternative model: **Full alternating combat (true Hearthstone)**
On your turn you place *and* your creatures attack the opponent's board/face, then
pass. There is no end-of-round simultaneous clash.
- **Cost:** `_do_combat()`'s simultaneous structure does **not** apply. You must
  write a new "active side attacks the passive side" resolver. The *per-creature*
  pieces are reusable (`_resolve_column_attack`/`_resolve_swift_attack`/
  `_creature_attacks_creature`/`_creature_hits_face`/`_apply_thorns`/
  `_apply_piercing_overflow` at `Combat.gd:1886–2413`), but the orchestration is new.
- **When to choose it:** only if the designer specifically wants asymmetric
  attacker/defender turns. It is a meaningfully larger build.

> **If the designer prefers the full-alternating model, the only sections that
> change are §12.4 (round loop) and §13 (resolution driver). Everything else —
> transport, entity ids, draft, message vocabulary shape, lobby — is identical.**

The rest of this document assumes the **chosen model** unless noted.

---

## 3. Architecture overview

### 3.1 Host-authoritative, "clients are remote controllers"
This is how Hearthstone, MTGA, and the standard turn-based pattern work, and it
fits this game perfectly because the simultaneous clash already runs entirely on
one machine.

- **One peer is the host (server + player).** The host runs the *real* Combat
  engine. It is the single source of truth.
- **The client sends intents** ("play hand card 3 to lane 2 front", "toggle floop
  on entity 17", "done"). It never computes game state.
- **The host validates** each intent against authoritative state, applies it, and
  **broadcasts authoritative events** describing what happened. The client renders
  those events.
- **Determinism is NOT required across machines** — only the host computes, so RNG
  (Ranged targeting, Chaos Imp, etc.) happens once on the host and the results
  travel in the event stream. This removes the hardest class of multiplayer bugs.

### 3.2 The three combat modes
Introduce one enum that the combat scene branches on:
```
enum CombatMode { SOLO, NET_HOST, NET_CLIENT }
```
- `SOLO` → today's behavior, untouched.
- `NET_HOST` → AI opponent replaced by the remote player's committed plays;
  resolution runs locally; events are broadcast.
- `NET_CLIENT` → no local game logic; consume the host's event stream and render
  using the same animation helpers.

### 3.3 The big simplification
Run skirmish **relic-free and mutator-free in v1.** Nearly every branch in
`Combat.gd` that couples to single-player meta is guarded by `_has_relic(id)` or
`has_mutator()`. If the skirmish player's relic set is empty and no mutator is set,
**all of that code is inert without being touched.** This collapses ~half of
Combat.gd's complexity for free. Relics/curses can be added back later, deliberately,
once the core loop is proven.

---

## 4. What is reused vs. new (and why isolation matters)

| Concern | Decision |
|---|---|
| Board model, `_row_array`, lanes/rows | **Reuse** as-is |
| `_do_combat` + all attack/keyword/death resolution | **Reuse** as-is (chosen model) |
| `KeywordEffects` dispatchers (ctx-based) | **Reuse** — works for any ctx with the right method surface |
| `Card2D` unit + animations | **Reuse**; add `entity_id` |
| Spell resolvers (`_resolve_spell`, `_resolve_custom_spell`) | **Reuse**; in scope per §13.3 |
| AI opponent (`_enemy_place_creatures`, `_assign_intents`, `_resolve_intents`) | **Replace** with remote-input source |
| Deck source (`RunState.deck`/uids/upgrades) | **Replace** with drafted skirmish deck injection |
| Relics, mutators, encounter passives, boss phases, intents UI | **Disabled** in v1 (inert) |
| `RunState` as the run container | **Not used**; new `SkirmishState` autoload |

**Isolation rule:** do not refactor the 11,800-line `Combat.gd` into a "pure
engine" up front — that risks breaking the shipping single-player game. Instead add
**seams**: a mode enum, an opponent-input indirection, and a deck-injection hook.
Touch existing functions surgically and only where the table above says "replace."

---

## 5. Transport & connectivity

### 5.1 Engine layer
Use Godot 4's built-in high-level multiplayer:
- `ENetMultiplayerPeer` for host/join (UDP). Turn-based card payloads are tiny.
- `@rpc` annotations for messaging. By default only the multiplayer authority
  (the host, peer id 1) can run authoritative RPCs; we lean on this for turn
  enforcement (see §9).
- We do **not** use `MultiplayerSynchronizer`/`MultiplayerSpawner` scene
  replication — the state is bespoke and better serialized explicitly.

### 5.2 "Online with a friend" — the NAT problem
Raw ENet needs the host reachable. Options, in recommended order for this project:
1. **ENet + a VPN overlay (Tailscale / ZeroTier / Hamachi)** — the friend joins a
   virtual LAN and connects to the host's overlay IP. **Zero port-forwarding, zero
   relay code.** Write pure LAN code; it "just works" over the internet. *Use this
   for v1.* The lobby just takes an IP + port.
2. **Manual port-forward** — host forwards one UDP port. Brittle; don't rely on it.
3. **Steam networking (GodotSteam)** — handles NAT via Steam relay, lobby invites.
   The right answer for a public release; out of scope for the playtest tool.
4. **WebRTC + a signaling server** — most work; only if browser builds matter.

Document the Tailscale path in the lobby UI ("enter your friend's Tailscale IP").

### 5.3 Default port
Pick a fixed default UDP port (e.g. `7717`) shown in the lobby, overridable.

---

## 6. New files & autoloads

### 6.1 New autoload: `NetMatch` (`scripts/net/NetMatch.gd`)
The networking + match brain. Add to Project Settings → Autoload as `NetMatch`.
Responsibilities:
- Owns the `ENetMultiplayerPeer`, host/join, peer lifecycle, disconnect signals.
- Holds `is_host: bool`, `local_player_index: int` (0 or 1), `peer_ids`.
- Holds the **entity registry** (§8) — host-side authority for `entity_id` issuance.
- Hosts all `@rpc` functions for lobby, draft, and combat messaging, OR delegates
  to scene scripts via signals. **Recommendation:** keep transport + connection +
  the *message router* in `NetMatch`; let scenes register handlers. Concretely,
  `NetMatch` emits Godot signals like `combat_intent_received(intent: Dictionary)`
  and `combat_event_received(event: Dictionary)` that the combat scene connects to.
  This keeps RPC plumbing in one place and game logic in the scenes.

### 6.2 New autoload: `SkirmishState` (`scripts/net/SkirmishState.gd`)
The skirmish equivalent of `RunState` — what the combat scene reads in `_ready()`
when `CombatMode != SOLO`. Holds, **for each of the two players**:
- `deck: Array[String]` (drafted card ids), `deck_uids: Array[int]`,
  `card_upgrades: Dictionary` (empty in v1 — no upgrades in draft),
  `hero_hp`, `hero_max_hp` (e.g. fixed 25 each), `relics: Array` (empty in v1),
  `base_max_mana` (3).
Plus match-level: `local_index`, `combat_mode`, `rng_seed` (host-chosen; sent to
client so any *cosmetic* client-side rng can match — gameplay rng stays host-only).

> Note: `Combat.gd` currently reads the *single* `RunState`. The cleanest seam is a
> tiny indirection (§12.2): a `_ctx_*` accessor layer that returns either
> `RunState`'s values (SOLO) or the correct `SkirmishState` player slot (NET).

### 6.3 New scenes/scripts
- `scenes/net_lobby.tscn` + `scripts/scenes/NetLobby.gd` — host/join UI, connection
  status, "start draft" when both present.
- `scenes/net_draft.tscn` + `scripts/scenes/NetDraft.gd` — the 1-of-3 ×20 draft.
- Reuse `scenes/combat.tscn` for the fight (with the mode seam), **or** a thin
  `scenes/skirmish_combat.tscn` that instances the same script. Prefer reusing
  `combat.tscn` to inherit all the HUD/board build code.
- A main-menu entry point ("Skirmish (Online)") in `MainMenu.gd`.

---

## 7. Core data structures

### 7.1 Entity registry (host-authoritative)
Every creature/token that exists on the board across both sides gets a unique,
monotonic `entity_id: int`, issued by the host. Stored in `NetMatch`:
```
var _next_entity_id: int = 1
var entities: Dictionary = {}   # entity_id -> Card2D (local node)
func issue_entity_id() -> int   # host only
```
The id is the cross-wire handle: host events reference `entity_id`; each client
maps `entity_id -> its local Card2D`. See §8 for assignment rules.

### 7.2 Player slot (in `SkirmishState`)
```
class PlayerSlot:
    var deck: Array[String]
    var deck_uids: Array[int]
    var hero_hp: int
    var hero_max_hp: int
    # piles are owned by the combat scene at runtime, not here
```
Index 0 = host's player, index 1 = client's player, by convention.

### 7.3 Network message envelope
All gameplay messages are plain `Dictionary` payloads (Godot RPC serializes these
natively). Use a `"t"` (type) field + a versioned `"v"`:
```
{ "v": 1, "t": "play_creature", "hand_uid": 1043, "lane": 2, "row": 0 }
```
Keep payloads to JSON-safe primitives (int/float/String/bool/Array/Dictionary).
**Never send `Card2D` nodes or `Object`s.** Card identity crosses the wire as
`card_id` (String) + `entity_id`/`hand_uid` (int).

### 7.4 Card-data schema (for reference; from `CardDB`)
- Creature: `{id, name, type:"creature", cost, atk, hp, rarity, keywords[], desc,
  on_enter{}?, on_death{}?, floop{}?, adj_buff{atk,hp}?, wither:int?, passive:String?,
  extra_damage:int?}`
- Spell: `{id, name, type:"spell", cost, rarity, keywords[], desc,
  spell{type,value,...}, targeting:String}` where targeting ∈
  `enemy_creature|friendly_creature|any_creature|any|none`.

The wire never sends full card-data; both clients have `CardDB` locally and look up
by `card_id`. Only **drafted deck lists** (arrays of `card_id`) and **runtime
deltas** (entity_id + stat changes) cross the wire.

---

## 8. The entity-ID system (the key engine change)

Today a board creature is identified by node ref + `(_row_array, lane)`. For
networking, both machines must agree on "which creature." Add a stable id.

### 8.1 Add to `Card2D`
```
var entity_id: int = -1   # network handle; -1 in SOLO mode
```

### 8.2 Assignment rules (host issues, client receives)
- **Host** assigns `entity_id = NetMatch.issue_entity_id()` at every creation point:
  - player creature played (`_play_creature`),
  - opponent creature materialized from a remote intent (new path, §12.3),
  - tokens/summons (`summon_token`, `_summon_enemy_token`, etc.),
  - any card pulled to hand that can enter the board (assign on enter, not on draw,
    to keep ids tied to board presence — simplest: assign when the Card2D is seated
    in a lane).
- On every creation, host registers `NetMatch.entities[entity_id] = card` and emits
  a `card_entered` event (§9.2) carrying the id.
- **Client** does not invent ids. When it receives `card_entered`, it instantiates
  the Card2D, sets `entity_id`, and registers it in its local `entities` map.

### 8.3 Hand cards
Hand cards use `deck_uid` (already exists) as their handle while in hand — the
client's "play this card" intent references the **hand card's uid**, not an
entity_id (which only exists once on the board). On the host, resolving the intent
seats the card and *then* assigns an entity_id. Keep the two id spaces distinct:
`deck_uid` = identity within a deck; `entity_id` = identity on the board.

---

## 9. Message vocabulary (the full RPC contract)

Two directions. All are routed through `NetMatch` (§6.1). Use reliable, ordered
delivery (the default `@rpc("any_peer", "call_remote", "reliable")` with explicit
channels if needed). Combat is turn-based, so ordering > latency.

### 9.1 Client → Host: INTENTS (validated, may be rejected)
The active client requests an action. The host validates against authoritative
state and either applies+broadcasts or returns a rejection.

| `t` | payload | meaning |
|---|---|---|
| `play_creature` | `{hand_uid, lane, row}` | seat a creature from hand |
| `play_spell` | `{hand_uid, target_entity_id?, target_lane?, target_row?}` | cast a spell (target optional per its `targeting`) |
| `toggle_floop` | `{entity_id}` | arm/disarm floop on a board creature |
| `reposition` | `{entity_id, lane, row}` | move a board creature to an empty slot (if your game allows it) |
| `done_placing` | `{}` | end this player's placement turn |

Validation the host MUST do (never trust the client):
- it is this player's turn (placement phase, correct active index);
- the card is actually in that player's hand (uid present);
- `player_mana >= _effective_cost`;
- target slot empty / target legal for the spell's `targeting`.
On failure → `reject` event back to the requester (§9.2) and no state change.

### 9.2 Host → Clients: EVENTS (authoritative; clients render)
The Hearthstone protocol calls these `CREATE_GAME` / `FULL_ENTITY` / `TAG_CHANGE`.
Our set:

| `t` | payload | client action |
|---|---|---|
| `match_begin` | `{rng_seed, p0_hp, p1_hp, your_index}` | build the board, set HP |
| `round_begin` | `{round_number, active_index, p0_mana, p1_mana}` | start a round; show whose placement turn |
| `hand_set` | `{cards:[{hand_uid, card_id}], for_index}` | tell a player its own new hand (redacted; §14) |
| `hand_count` | `{count, for_index}` | tell the *other* player the opponent's hand size only |
| `card_entered` | `{entity_id, card_id, owner_index, lane, row, atk, hp, keywords[]}` | instantiate + seat a Card2D |
| `tag_change` | `{entity_id, field, value}` | mutate a stat/flag (hp, atk, stunned, has_shield, doom_counter, will_floop, …) — the workhorse |
| `creature_moved` | `{entity_id, lane, row}` | reposition animation |
| `creature_died` | `{entity_id}` | death animation + remove from board/maps |
| `mana_change` | `{for_index, value}` | update a Command pool |
| `hero_damage` | `{for_index, amount, new_hp}` | face damage + HP bar |
| `clash_log` | `{events:[…ordered combat events…]}` | replay the simultaneous clash (§13.2) |
| `turn_passed` | `{by_index, next_active_index}` | a player finished placing |
| `match_over` | `{winner_index, reason}` | end screen |
| `reject` | `{for_index, reason}` | the requester's last intent was illegal (re-enable input) |
| `ping`/`pong` | `{t_ms}` | liveness + RTT (optional) |

**Granularity choice (important):** you can broadcast fine-grained `tag_change`
events for *every* state mutation during placement (Hearthstone-style), or send
coarser snapshots. **Recommendation:** during *placement* use fine-grained events
(`card_entered`, `tag_change`, `mana_change`) so the opponent watches plays land in
real time; for the *clash* use a single `clash_log` the client replays (§13.2).

### 9.3 RPC authority pattern (Godot specifics)
- Intents: client calls a `@rpc("any_peer")` function that **executes on the host
  only** — i.e. client does `rpc_id(1, "_net_intent", payload)`; the body runs on
  peer 1 (host) and checks `multiplayer.get_remote_sender_id()` to know who asked.
- Events: host calls `@rpc("authority", "call_remote")` to push to clients, or
  `rpc()` to all; the host also applies the same change locally (call the local
  handler directly, don't round-trip to itself).
- Wrap everything in `NetMatch` so scenes never touch `multiplayer` directly.

---

## 10. Lobby & connection flow

Scene: `net_lobby.tscn` / `NetLobby.gd`.

1. Main menu → "Skirmish (Online)" → lobby.
2. UI: **Host** button, and **Join** (IP field + port, default `7717`).
3. **Host path:** `NetMatch.host(port)` creates `ENetMultiplayerPeer.create_server(port, 1)`
   (1 client slot), sets `multiplayer.multiplayer_peer`. `is_host = true`,
   `local_player_index = 0`. Wait for `peer_connected`.
4. **Join path:** `NetMatch.join(ip, port)` → `create_client(ip, port)`.
   `is_host = false`, `local_player_index = 1`. On `connected_to_server`, show
   "connected, waiting for host to start."
5. When both present, host shows **Start Draft**. Pressing it: host picks
   `rng_seed = randi()`, calls an RPC `begin_draft(rng_seed)` to the client, then
   both `change_scene_to_file("res://scenes/net_draft.tscn")`.
6. Handle `peer_disconnected` / `connection_failed` / `server_disconnected` at every
   stage → bounce to lobby with an error toast.

**Phase-0 milestone:** before any draft/combat, prove a peer can host, a peer can
join over Tailscale, and a trivial RPC round-trips (e.g. a chat line or a "ready"
toggle). Do not proceed until this is solid.

---

## 11. Draft mode (1-of-3 ×20)

Scene: `net_draft.tscn` / `NetDraft.gd`. This is the easy part — keep it simple.

### 11.1 Model (recommended): independent simultaneous drafting
Each player drafts their **own** 20-card deck from their **own** stream of
triplets. Players draft in parallel; no pack-passing. This avoids
shared-state contention and is plenty for a playtest.

- Determinism: the host sends `rng_seed`. Each player's triplet stream is generated
  from a per-player seeded RNG (`seed = rng_seed ^ player_index_salt`). Both
  machines can generate the **same** sequence of triplets for a given player, so
  you only need to send **pick indices** over the wire, not card lists — though
  sending the chosen `card_id` outright is simpler and fine (20 small messages).
- Triplet source: draw 3 distinct `card_id`s from `CardDB`'s draftable pool. Decide
  the rarity weighting — simplest v1: uniform over a curated "skirmish-legal" pool
  (exclude enemy-only, tokens, curses; `CardDB.is_upgradeable` filters curses).
  Optionally bias by rarity like `roll_card_reward`. Document the exact pool.

### 11.2 Flow
1. `NetDraft._ready()` seeds RNG from `SkirmishState.rng_seed` + local index.
2. Show 3 cards. On click, append `card_id` to the local draft; tell the peer
   `draft_pick {index, card_id}` (so each side can show "opponent has picked N/20").
3. Repeat until each player has 20. A player who finishes waits on a "waiting for
   opponent" screen.
4. When **both** reach 20: write each deck into `SkirmishState` player slots
   (`deck` + freshly issued `deck_uids` via a local counter), set
   `combat_mode = NET_HOST/NET_CLIENT`, and `change_scene_to_file("res://scenes/combat.tscn")`.
5. Host confirms both decks are known to *it* (the host must know both decks to be
   authoritative — so the client sends its full 20-card list to the host at draft
   end via `submit_deck {cards:[card_id…]}`). The host stores both in
   `SkirmishState`; the client only needs its own deck locally (the host will drive
   the opponent board via events).

### 11.3 Deck size / HP knobs
- 20-card deck (per request), starting HP 25 each (reuse the single-player value),
  `base_max_mana = 3`. All easily tunable in `SkirmishState`.

---

## 12. Skirmish combat — integrating into Combat.gd

This is Phases 2–3 and ~80% of the effort. The strategy: **add seams, don't fork.**

### 12.1 Mode seam
Add to `Combat.gd`:
```
var combat_mode := CombatMode.SOLO   # set before scene load (read from SkirmishState in _ready)
func _is_net() -> bool: return combat_mode != CombatMode.SOLO
func _is_host() -> bool: return combat_mode == CombatMode.NET_HOST
```
In `_ready()` (`Combat.gd:359`), early: read `SkirmishState.combat_mode` and set
`combat_mode`. When `_is_net()`, **skip** the single-player setup that doesn't apply:
encounter intro, mutator init, boss phases, music-by-node-type (or keep a generic
track), `_apply_gamblers_coin`/`_apply_marked_one_gift`/`_apply_combat_start_relics`
(all relic-gated → already inert, but skip explicitly for clarity).

### 12.2 Context indirection (deck + HP source)
`Combat.gd` reads `RunState` directly in `_setup_fight_state()` (`600`) and
`_init_decks()` (`936`). Add a thin accessor layer used by those two functions:
```
func _ctx_hero_hp() -> int:        return _net_my_slot().hero_hp if _is_net() else RunState.hero_hp
func _ctx_deck() -> Array:         return _net_my_slot().deck    if _is_net() else RunState.deck
func _ctx_deck_uids() -> Array:    ...
func _ctx_max_mana() -> int:       return _net_my_slot().base_max_mana if _is_net() else RunState.get_max_mana()
func _ctx_card_data(uid, id):      # SOLO → RunState.get_upgraded_card_data; NET → plain CardDB (no upgrades v1)
```
`_net_my_slot()` returns the local player's `SkirmishState` slot. The **opponent's**
deck/board is never drawn locally on the client — it arrives via `card_entered`
events. On the **host**, the opponent side is driven by the remote player's intents
(§12.3), and the opponent's draw pile lives on the host (host owns both decks).

Refactor only the handful of `RunState.` reads in `_setup_fight_state`,
`_init_decks`, and the `player_max_mana` computation in `_start_round` to go through
`_ctx_*`. Leave every relic/mutator read alone (inert in net mode).

### 12.3 Refactor the play path to accept intents (not just the mouse)
Today `_play_creature` derives lane/row from the drop position. Split it:
```
# UI path (local player drag): compute slot, then call the core.
func _play_creature(card, cost):
    var drop = _nearest_player_slot(card.global_position + card.size*0.5)
    _apply_play_creature(card, cost, drop.lane, drop.row, /*owner*/ _local_side())

# Core path: no mouse. Callable by UI OR by a net intent.
func _apply_play_creature(card, cost, lane, row, is_enemy_side): ...
```
- In **NET_HOST**, when the host's *own* player plays, it runs the UI path, applies
  locally, AND emits `card_entered` (+ `mana_change`) to the client.
- In **NET_HOST**, when the **client's** intent arrives (`play_creature`), the host:
  validates → materializes the card on the **enemy side** (the path
  `_place_enemy_card`-style but issuing an entity_id and running on-enter) →
  emits `card_entered` (owner_index = client) + `mana_change` to both.
- In **NET_CLIENT**, the local player's drag does **not** apply anything locally;
  it sends a `play_creature` intent and waits. The resulting `card_entered` (with
  `owner_index == me`) is what actually seats the card on screen. (Optimistic local
  placement is a later nicety; v1 = wait for the echo. Card-game latency tolerance
  is high, so this is acceptable.)

Do the same split for spells (`_play_spell` → `_apply_play_spell`), floop toggles
(`_on_floop_clicked` → intent), reposition, and `_on_end_turn` → `done_placing`.

### 12.4 The round loop (chosen model: alternating placement + simultaneous clash)
Replace the solo "`_start_round` → player turn → `_on_end_turn` → `_do_combat`" with
a host-driven sequence. **All sequencing logic lives on the host;** the client just
reacts to events.

Host round loop (pseudocode):
```
func _net_round():
    round_number += 1
    _net_draw_and_mana_for_both()          # draw to target, compute mana; emit hand_set/hand_count/mana_change/round_begin
    var first := round_number % 2           # alternate first placer
    await _net_placement_turn(first)        # active player places; resolves on 'done_placing' intent (or local Done)
    await _net_placement_turn(1 - first)
    await _net_clash()                       # run _do_combat(); capture clash_log; broadcast
    if _net_check_match_over(): emit match_over; return
    _net_round()                             # or loop
```
- `_net_placement_turn(active_index)`: set `phase = PLAYER_TURN` *only if the active
  player is local*; enable that player's board/Done button; the inactive player's UI
  is read-only ("Opponent is placing…"). The turn ends when the active player's
  `done_placing` arrives (host) / local Done is pressed (host's own turn).
- Command/banking: reuse the `_start_round` mana logic per player via `_ctx_max_mana`.
- The client implements the **mirror**: it never runs `_net_round`; it renders
  `round_begin` (enables its board iff `active_index == me`), `hand_set`,
  `card_entered`, `tag_change`, `clash_log`, etc.

> **Full-alternating alternative (if chosen):** replace `_net_clash` with
> per-turn attacks — after a player finishes placing, that player's creatures
> attack, driven by the reusable per-creature resolvers; no end-of-round clash.

### 12.5 Launching the scene
`NetDraft` sets `SkirmishState` and calls `change_scene_to_file("res://scenes/combat.tscn")`
on both peers (host triggers via an RPC so both transition together). `Combat._ready`
reads `SkirmishState`, sets `combat_mode`, and the host kicks off `match_begin` →
`_net_round()` after the board is built and `_prebake_hand_textures()` completes.

---

## 13. Combat resolution reuse

### 13.1 The clash runs on the host, unchanged
On `_net_clash`, the host calls the existing `await _do_combat()`. Because both
sides' boards are real Card2D nodes on the host (player side = host's creatures,
enemy side = the materialized client creatures), `_do_combat` "just works":
Swift phase, simultaneous lane attacks, ranged, deaths, `KeywordEffects` dispatch,
on-death effects — all already implemented and ctx-driven.

### 13.2 Getting the clash onto the client's screen
Two strategies; build (A) first, upgrade to (B) if it feels flat.

**(A) Snapshot + coarse animation (v1).** After `_do_combat`, the host diffs the
board and sends a `clash_log` that is really a result set: list of `tag_change`
(final hp/atk), `creature_died`, `hero_damage`. The client applies them with a
generic "clash" animation (flash + shake). Simple, robust, ugly-ish.

**(B) Recorded event log replay (nicer).** Instrument the host's resolution to
append a typed event to a buffer as each thing happens (attacker entity_id hits
defender entity_id for N, X dies, face takes M). Ship the ordered buffer as
`clash_log.events`. The client replays it through the *same* animation helpers
(`_creature_attacks_creature`, `_creature_hits_face`, death pops) with the same
`_short_pause` pacing, so both screens show the identical lane-by-lane cascade.
This requires adding ~one `_log_event(...)` call at each strike/death site in the
resolver (the sites are already centralized: `_creature_attacks_creature` 2144,
`_creature_hits_face` 2224, `_apply_thorns` 2381, `_cleanup_dead`/`_on_friendly_death`).

### 13.3 Card-support scope for v1 (de-risk by subsetting)
You do **not** need every one of the 154 cards working day one. Define a
**skirmish-legal pool** and grow it:
- **v1:** creatures with on-enter/on-death/floop that resolve *locally on the host*
  (most do — they go through `KeywordEffects` + `_resolve_on_play_ability`). All
  basic keywords (Armored, Swift, Thorns, Piercing, Ranged, Last Stand, Regenerate,
  Wither, etc.) come free with `_do_combat`. **Exclude** cards whose effects assume
  single-player context (relic synergies, deck-wide effects keyed to `RunState`).
- **Spells:** include simple targeted/AoE damage/buff spells first. Each spell that
  reads custom fields (`dmg_bonus`, `ricochet_hits`, etc.) is fine because resolution
  is host-side; the only requirement is that targeting crosses the wire as
  `target_entity_id` (board) or none. Defer spells that manipulate the draw pile/
  discard/exhaust in ways the client must mirror until the pile-sync story is built.
- **Tokens/summons:** supported — they create Card2D from synthetic data on the host
  and emit `card_entered`.
- Maintain an explicit allowlist in `SkirmishState` and have the draft only offer
  legal cards. This makes "add card X to multiplayer" a deliberate, testable step.

### 13.4 The KeywordEffects ctx surface (investigation task)
`KeywordEffects` calls many methods on `ctx` (the Combat instance). Since we
**reuse the Combat instance** as ctx on the host, this is satisfied for free. But
if a future refactor extracts a separate engine, you must enumerate that surface
first. Action item: `grep "ctx\." scripts/data/KeywordEffects.gd` and record the
method list as the engine interface contract. (Not needed for the reuse approach,
but document it.)

---

### 13.5 Full-alternating model (CHOSEN — supersedes §12.4 / §13.1-13.2)

Per the §2 decision. There is **one active player** at a time; no simultaneous
clash. The host drives the whole sequence; the client renders via events.

**A turn (active player = the one whose turn it is):**
1. **Upkeep:** active player draws to `HAND_REFILL_TARGET` and gains Command
   (`_ctx_max_mana()` + banked, reusing the `_start_round` mana math). Host emits
   `hand_set`(active, own cards) / `hand_count`(other) / `mana_change` /
   `round_begin`(active_index).
2. **Action sub-phase:** active player plays creatures/spells, repositions,
   toggles floops — spending Command. Client sends intents; host validates &
   applies; host emits `card_entered` / `tag_change` / `mana_change`. The inactive
   player's UI is read-only ("Opponent's turn").
3. **Attack sub-phase:** active presses **ATTACK** (the End-Turn button's
   skirmish role). The active player's creatures attack the *opposing* side, one
   direction only. **Reuse the existing per-creature resolver**: iterate front row
   then back row, lane order, calling `_resolve_column_attack(lane, row,
   is_enemy=active_is_enemy, opponent_front_empty)` — the same function `_do_combat`
   uses, but driven for the **active side only**. Ranged via `_resolve_ranged_attacks`
   filtered to the active side; Thorns/Piercing/Cleave/Last Stand/on-death all come
   free because they live inside that resolver. Host records the ordered strikes
   into a `clash_log` (see §13.2 strategy B) and broadcasts it; client replays.
4. **Cleanup:** `_cleanup_dead`, on-death effects, end-of-turn ticks; pass to the
   other player (`turn_passed`). Check `match_over` (a hero ≤ 0 HP).

**Summoning sickness (design detail to confirm; v1 default = NONE):** Burning
Meadow has no sickness in single-player, so v1 lets a creature attack the turn
it's placed. **Swift** loses its pre-phase meaning here; v1 treats it as "attacks
first within the active side's order" (front-row Swift before other front row).
Flag for the designer if they want sickness instead.

**Banking / Command:** unchanged per-player (each player banks ≤2 going into their
own next turn).

**Host turn loop (pseudocode):**
```
func _net_turn(active_index):
    _net_upkeep(active_index)                 # draw + mana, emit events
    await _net_action_subphase(active_index)  # ends on this player's ATTACK/Done intent
    await _net_attack_subphase(active_index)  # active side attacks; clash_log
    if _net_check_match_over(): emit match_over; return
    _net_turn(1 - active_index)
```
First active player: host (index 0) on turn 1, or coin-flip; alternate thereafter.
The client never runs `_net_turn` — it renders the event stream and enables its
board only while `round_begin.active_index == local_index`.

---

## 14. Hidden information & anti-cheat

- The host knows both hands and both decks (it's authoritative). To prevent the
  client from seeing the opponent's hand, **redact per-recipient**: send the
  client `hand_set` only for *its own* cards, and `hand_count` (a number) for the
  opponent's hand. Hearthstone does exactly this ("a dispatcher holds back/changes
  packets per player").
- Because all validation is host-side, a hacked client cannot make illegal plays —
  worst case it can read its own hand early (already allowed) or DoS the host
  (acceptable for a play-with-a-friend tool).
- **v1 posture:** the host is a player, not a neutral server, so a cheating *host*
  is possible. For a friends-only playtest this is fine. A competitive release
  would need a dedicated authoritative server — out of scope.

---

## 15. Disconnection, timeouts, desync

- **Disconnect:** `NetMatch` listens for `peer_disconnected` / `server_disconnected`.
  On loss mid-match, show "opponent disconnected," offer return-to-menu. v1 has no
  reconnect/resume — keep it simple.
- **Turn timeout (optional):** a placement turn timer to prevent a stalled
  opponent hanging the match; on expiry the host auto-`done_placing` for that player.
- **Desync guard:** since only the host computes, the client can't truly desync — it
  can only fail to render an event. Add a cheap integrity check: host includes a
  `state_hash` (hash of both HPs + sorted board `entity_id:atk:hp`) in `round_begin`;
  client logs a warning if its computed hash differs. Useful during development.

---

## 16. Testing strategy

1. **Two instances, one machine:** run the Godot editor + an exported build (or two
   exported builds) locally; host on `127.0.0.1`, join on `127.0.0.1`. Fastest loop.
   (Godot can also launch multiple debug instances: Debug → Run Multiple Instances.)
2. **Tailscale, two machines:** the real "online with a friend" test.
3. **Fake-peer harness (optional but valuable):** a headless script that connects as
   the client and replays scripted intents, so the host's resolution can be probed
   without a human. Mirrors the existing `_probe_*` test pattern in this codebase.
4. **Card-coverage probe:** a script that drafts a fixed pair of decks (bypass the
   pick UI via a seed) and runs N rounds, asserting no errors — run after adding
   each batch of cards to the skirmish-legal pool.
5. Headless parse-check after each change:
   `Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" --editor --quit-after 5 res://scenes/combat.tscn`
6. **Logic probe (BUILT): `tools/_probe_skirmish.gd`** — no rendering / no sockets;
   verifies the skirmish-legal pool (size / determinism / denylist / curses), that
   denylist + `NET_SPELL_CUSTOMS` ids are real CardDB cards (catches typos — it
   already caught two dead spell ids), the deterministic uid scheme, the mode
   flags, the **owner→side perspective map** (the bug-prone bit), `_ctx_*`
   deck/HP/mana routing, and the spell-support gate. Run:
   `Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish.gd`
7. **Combat engine harness (BUILT): `tools/_probe_skirmish_combat.gd`** — the
   fake-peer harness §16.3 asked for, no sockets. Boots the REAL `combat.tscn` as
   NET_HOST (forcing the net flags so `_ready` takes the net path) and drives a
   full turn cycle with scripted client intents: turn open + local draw, host
   creature play (on-enter + `entity_id==deck_uid` registration + board sync), the
   attack clash (Swift/column/Ranged/cleanup), turn passing, a client creature
   intent seated on the enemy side, a client spell resolved on the host, and
   match-over → GAME_OVER. Then it reboots as NET_CLIENT and feeds crafted
   snapshots to verify the reconcile path (owner→side, HP perspective,
   spawn/update/despawn). **Headless gotcha it documents:** `_ready` ends on
   `await _prebake_hand_textures()`, whose bake awaits `RenderingServer.frame_post_draw`
   — which never fires under the dummy renderer, so `_ready` parks there forever
   headless. The harness calls `_net_begin_combat()` directly to bypass the
   cosmetic stall (a real windowed game emits `frame_post_draw` and prebake
   finishes in ~6 frames). Run:
   `Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish_combat.gd`
8. **Transport smoke test (BUILT): `tools/_probe_skirmish_net.gd`** — two headless
   processes over a real ENet loopback connection (the same @rpc path Tailscale
   uses), coordinated by `SKIRM_ROLE=host|client`. Verifies host/join, peer
   signals, the ready handshake RPC, match-start seed propagation, a client→host
   INTENT, and a host→client EVENT, asserting payload fields survive the wire.
   Run both (host first):
   `$env:SKIRM_ROLE='host'; Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish_net.gd`
   `$env:SKIRM_ROLE='client'; Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish_net.gd`

---

## 17. Phased build order (do these in order)

Each phase ends in something runnable. Don't start a phase before the prior one is
solid.

### Phase 0 — Transport & handshake (no game logic)
- Create `NetMatch` autoload: host/join via `ENetMultiplayerPeer`, peer signals,
  `is_host`/`local_player_index`.
- `net_lobby.tscn` with Host / Join(IP,port) and a connection-status label.
- One trivial round-trip RPC (e.g. a "ready" toggle both peers see).
- Main-menu "Skirmish (Online)" button → lobby.
- **Acceptance:** two machines connect over Tailscale; the ready toggle syncs;
  disconnect is detected and returns to lobby.

### Phase 1 — Draft
- `SkirmishState` autoload with player slots + `rng_seed`.
- `net_draft.tscn`: seeded triplets from the skirmish-legal pool, 1-of-3 ×20,
  `draft_pick` sync + opponent progress, "waiting for opponent."
- Client `submit_deck` to host at finish; both decks land in `SkirmishState`.
- **Acceptance:** both players independently draft 20; both decks are present on the
  host; both transition to a placeholder combat scene together.

### Phase 2 — Combat plumbing (the hard part)
- Add `combat_mode` seam + `_ctx_*` indirection; route `_setup_fight_state`/
  `_init_decks`/`_start_round` mana through it.
- Add `entity_id` to `Card2D`; host-issue at every creation site; entity registry
  in `NetMatch`.
- Split the play path: `_play_creature` → `_apply_play_creature(...)`; same for
  spell/floop/reposition/end-turn. Wire UI→intent on the client, intent→apply on
  the host.
- Implement the message router in `NetMatch` (§9) with redaction (§14).
- **Acceptance:** host and client can each place creatures during their placement
  turn and both screens show the same board (no clash yet).

### Phase 3 — The clash & round loop
- Host `_net_round()` loop: draw/mana for both, alternating placement turns,
  `_net_clash()` calling `_do_combat()`.
- Clash replay strategy (A) snapshot first; then (B) event-log replay.
- `match_over` on a hero reaching 0 HP.
- **Acceptance:** a full multi-round skirmish plays start-to-finish over Tailscale,
  both screens consistent, winner declared.

### Phase 4 — Card coverage & polish
- Expand the skirmish-legal pool batch by batch, with the coverage probe (§16.4)
  after each batch.
- Spells with targeting over the wire; tokens/summons; floops.
- Hand redaction polish, opponent-hand count display, turn timer, reconnect-to-menu.
- **Acceptance:** the curated competitive pool plays cleanly; no single-player
  regressions (run the solo game through a full act).

### Phase 5 — (Optional) reach
- Steam networking for NAT-free public play; rematch button; spectator; ranked.

---

## 18. Risks & open questions

1. **Combat-model fork (§2)** — confirm "alternating placement + simultaneous clash"
   vs full-alternating with the designer before Phase 3. Everything else is
   model-agnostic.
2. **`RunState` coupling depth** — the `_ctx_*` plan assumes only a handful of
   `RunState` reads matter once relics/mutators are inert. Verify by grepping
   `RunState\.` inside `Combat.gd` and confirming each hit is either (a) relic/
   mutator-gated, (b) map/act-only (skip in net), or (c) covered by a `_ctx_*`
   accessor. Budget time for stragglers.
3. **Pile sync for advanced spells** — draw/discard/exhaust manipulation needs the
   client to mirror pile state for *its own* deck. v1 sidesteps this by scoping such
   spells out (§13.3); revisit when adding them.
4. **Optimistic input** — v1 waits for the host echo before showing the local
   player's own play. If it feels laggy on real internet, add client-side optimistic
   placement with rollback on `reject`. Likely unnecessary for turn-based.
5. **Animation parity** — clash replay (B) requires log instrumentation at the
   strike/death sites; budget for it. (A) is the safe fallback.
6. **Cheating host** — acceptable for friends-only; note it.

---

## 19. Appendix — file-by-file change list

**New files**
- `scripts/net/NetMatch.gd` (autoload) — transport, peers, entity registry, RPC router.
- `scripts/net/SkirmishState.gd` (autoload) — per-player decks/HP/mode/seed.
- `scripts/scenes/NetLobby.gd` + `scenes/net_lobby.tscn`.
- `scripts/scenes/NetDraft.gd` + `scenes/net_draft.tscn`.
- (optional) `scenes/skirmish_combat.tscn` if not reusing `combat.tscn`.

**Modified files**
- `project.godot` — register `NetMatch`, `SkirmishState` autoloads.
- `scripts/scenes/MainMenu.gd` — add "Skirmish (Online)" entry → lobby.
- `scripts/Card2D.gd` — add `var entity_id: int = -1`.
- `scripts/scenes/Combat.gd` — the bulk:
  - add `CombatMode` enum + `combat_mode` + `_is_net/_is_host` helpers;
  - read `SkirmishState` in `_ready()`; branch out solo-only setup;
  - `_ctx_*` accessors; route `_setup_fight_state` / `_init_decks` / `_start_round`
    mana through them;
  - split `_play_creature`/`_play_spell`/`_on_floop_clicked`/reposition/`_on_end_turn`
    into UI + `_apply_*` core; wire intents;
  - host-issue `entity_id` at all creation sites; register in `NetMatch`;
  - `_net_round()` / `_net_placement_turn()` / `_net_clash()` for the net round loop;
  - clash event logging for replay (strategy B).

**Unchanged but depended-on:** `KeywordEffects.gd` (works as ctx consumer),
`CardDB.gd`, `Card2D` animation helpers, `_do_combat` and all resolution functions.

---

## 20. One-paragraph summary for a cold reader

Build a standalone online 1-v-1 "Skirmish" mode, separate from the campaign. Two
players connect (ENet over Tailscale), each drafts a 20-card deck (1-of-3 ×20), then
fight. Use a **host-authoritative** model: the host runs the existing `Combat.gd`
engine; the client sends **intents** and renders **events** keyed by stable
per-creature **entity ids**. Reuse the simultaneous-clash combat wholesale by making
the round **alternating in placement** (A places, then B), then resolving the clash
on the host via the untouched `_do_combat()`. Make skirmish **relic-free and
mutator-free** so half of `Combat.gd` goes inert without edits; inject decks/HP via a
new `SkirmishState` autoload through a thin `_ctx_*` accessor layer; replace the AI
opponent (`_enemy_place_creatures`/`_assign_intents`/`_resolve_intents`) with the
remote player's committed plays. Phase the work: transport → draft → combat plumbing
→ clash → card coverage. Confirm the combat-model fork (§2) before Phase 3.
