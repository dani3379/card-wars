# Fight-Interest Backlog

Register of encounter-design improvements aimed at the #1 complaint — *fights feel
samey* (players ignore effects and just charge; depth never shows because fights
end fast). Generated 2026-06-23 by a 4-agent design pass (Act 1 / Act 2 / Act 3 /
marquee-fights+toolkit). The full specs live in the originating conversation; this
file is the **condensed, implementable register** so the work is resumable.

**Root cause the pass converged on:** a handful of passives are badly over-shared
(`forge_burn_all` ×6, `cultist_buff` ×3, `executioner_face` ×2, `wolf_pack_revenge`
×2, `hollow_king_snipe`/`void_exile` shared with bosses) and a few are mathematically
dead in a 2-4 round fight (`dragon_lair_periodic` only fired round 4). A passive the
player has already seen — or that never fires — is invisible, so the fight reads as
generic. The fix is **identity-per-fight**: each fight gets one loud, legible threat
that lands in rounds 1-3.

## Conventions
- Enemy decks are **inline creature dicts** (`{"name","atk","hp","kw",...}`), NOT
  CardDB ids. Passive/reactive handlers are **static funcs in
  `scripts/data/EncounterEffects.gd`** (Combat's `_dispatch_*` are thin forwarders);
  signature passives that need banners/shake live inline in `Combat.gd`.
- All player-facing copy follows `docs/COPY_STYLE.md` (Command not mana; keywords
  Capitalized; "fight" for the duration synonym; never edit KeywordEffects `display`).
- Pacing: a fight's identity must land in **rounds 1-3**. Round-4 escalation
  ("THE TIDE TURNS", see below) is the climax, not where the identity starts.

---

## STATUS LOG

- **2026-06-23 — DONE (landed + verified):**
  - **Fix #1 — reachable escalation for ALL combats** (`Combat.gd`): pulled the
    anti-stall tiers from 8/10/12 (never reached) into 4/6/7; decoupled the
    overloaded `ESCALATION_REINFORCE_ROUND` from the faction-wave cutoff
    (`WAVE_SCHEDULE_CUTOFF_ROUND = 8`), so authored waves still run 1-7; generic
    holds now commit reserves at round 4 with a telegraphed "THE TIDE TURNS" banner.
  - **De-dup batch — 8 new bespoke passives** (`EncounterEffects.gd` +
    `EncounterDB.gd`) replacing the worst duplicate/dead passives:
    `forge_heat` (fire_giants_forge), `pack_hunt` (ash_hounds),
    `pyre_spread` (pyre_cult), `dirge_swell` (carrion_choir),
    `court_wither` (withered_court), `flock_enrage` (corrupted_shepherd),
    `glass_refract` (glass_menagerie), `drake_breath` (dragons_lair).
  - **`void_walker` HP 38 → 28** (a "race the clock" elite that was too tanky to race).
  - Verified: headless parse clean; `_probe_balance` on the 9 changed fights (sane
    win rates, 0 script errors); `_probe_autorun` 50/50 fights, 0 softlocks, 0 crashes.

- **PENDING** — everything below. Priorities: **P1** = high impact / low risk,
  **P2** = high impact / needs care, **P3** = polish.

---

## ACT 1 (normal + elites) — teach the hooks while staying distinct

| id | Change | New passive behavior | Pri |
|---|---|---|---|
| `orc_warband` (elite) | Rewrite `orc_random_buff`: stop the un-interactable random +1 ATK. **Chieftain-sourced, front-row-targeted rally** — first elite teaches "Generals have a lever you must answer." | start-of-round: if a creature named "Chieftain" lives, front-row enemies +1 ATK (else "drum falls silent"). Self-contained rewrite of the existing handler. | **P1** |
| `bandit_camp` | Delete the invisible (twice-buggy) `bandit_mana_steal`; give a Cutpurse a **telegraphed `steal_command` ABILITY** (intent badge) — kill it before the badge fires. | new `_resolve_enemy_ability` arm: `_bonus_mana_next_turn -= value`. Teaches the intent system. | **P1** |
| `mushroom_grove` | Delete the phantom board-wide `mushroom_heal` (same feels-bad pattern already removed from scarecrow_field); add a **Heartcap** creature with a telegraphed `heal_all` ability so the heal has a target. | data-only (reuses existing `heal_all` ability). | **P1** |
| `goblin_scouts` | Move the R5 "all dart forward" script to **R2** so the all-Swift ambush lands in-window; optional `raid_open_lanes` (reuse `harpy_swift_face`). | script reorder; zero/near-zero code. | P2 |
| `harpy_nest` | Drop the duplicated `harpy_swift_face`; new **`stooping_dive`** — telegraphed snipe on highest-ATK creature (register in `_refresh_passive_threat_glow`). Distinct back-row-snipe identity. | start-of-round (R2+): 2 dmg to highest-ATK player creature; add to glow allow-list. | P2 |
| `boar_herd` | Add **`stampede_charge`** — rounds 1-2 enemies get Piercing +1 ATK then "the charge breaks." Front-loads the threat; rewards absorbing the alpha strike. | `has_encounter_passive_keyword` (piercing, R<=2) + start-of-round temp ATK R1/R2. | P2 |
| `wolf_pack` | Make `wolf_pack_revenge` LOUD (bump +1→+2 this-round, add info pulse + shake) so killing the buffer reads. | tweak existing arm. | P3 |
| `stone_sentinels` | `tooth_stone_grind` — from R2 grant Thorns to the whole front row (legible "don't trade chaff into this"). | start-of-round arm. | P3 |
| `powderkeg_run` | `powder_chain` — when a Doom Cinder detonates, neighbors +2 ATK this round (detonations feel dramatic). | on-enemy-death arm gated on `has_keyword("doom")`. | P3 |
| `necromancer_tower` (elite) | From R4, risen Skeletons enter with Swift (syncs the climb to the new round-4 escalation). | extend `necro_death_summon`. | P3 |

## ACT 2 (normal + elites) — escalate to two-threat fights

| id | Change | New passive behavior | Pri |
|---|---|---|---|
| `oathbroken_knights` | The slice's only passive-less stat-wall. Add **`oath_riposte`** — a player blow that fails to kill an armored enemy costs 1 face. Punishes chip, rewards precision. | new branch at the piercing-check site in `Combat.gd` (~2544); attack-resolution, not a dispatcher. | **P1** |
| `cultist_enclave` | Replace `cultist_buff` with **`martyr_pact`** — mark weakest cultist as "the Chosen"; its on-death fires twice. Makes kill-ORDER matter. | needs Combat field `_martyr_chosen` + double-fire via `KeywordEffects._run_on_death`. | P2 |
| `haunted_crypt` | De-dup `crypt_ghost` (shared w/ rival_acolyte + 2 amalgams). **`grave_glut`** — every 2nd enemy death erupts a 3/3 Swift Wraith + 2 face. Creates a "stop killing, race the door" fight. | Combat counter field `_grave_glut_count` + on-enemy-death arm. | P2 |
| `demon_vanguard` (elite) | `demon_spell_buff` is inert vs creature decks. **`threshold_muster`** — keep the spell-buff reactive AND summon an Armored Demon each round you cast no spell. | needs `_spell_cast_last_round` flag; start-of-round arm. | P2 |
| `mercenary_company` | Sharpen (don't replace) `merc_piercing`: add a Drill Sergeant so 3 adj-buffers make "kill the officers" unmissable. | data-only. | P3 |
| `swamp_horror` | Front-load a Bog Witch (`heal_all` on-enter) so "it heals back" reads R1; optional `swamp_regrowth` adjacency heal. | data-only (+ optional arm). | P3 |
| `puppeteer` (elite) | Make `puppet_keyword_copy` **targeted** (the puppet opposing your strongest) + telegraph; swap 2 vanilla Marionettes for keyworded bodies so the opening isn't dead. | replace arm + 2 deck swaps. | P3 |

## ACT 3 (normal + elites) — demand the full toolkit

| id | Change | New passive behavior | Pri |
|---|---|---|---|
| `executioners_block` | De-dup `executioner_face` (shared w/ glass_menagerie, now split). **Telegraph the axe**: glow the highest-ATK enemy with its incoming face damage; bump Executioner to 5/6 piercing+last_stand. | add `executioner_face` to `_refresh_passive_threat_glow` (mark ENEMY) + data. | **P1** |
| `elemental_nexus` | Re-order `nexus_rotation` so the scary beat (Thorns) is **R1**, not the dull +1 ATK. Opens with its best face. | swap cycle indices in the handler + the `has_encounter_passive_keyword` gate. | P2 |
| `mirror_temple` | Front-load 2 `copy_opposing_keywords` bodies + a Guardian wall so the "it wears your build" identity lands R1-2. | data-only (uses `guardian`). | P3 |
| `killing_choir` | Give the all-Ranged deck a single Guardian Hymn Bearer up front so "break the wall to silence the back" is the explicit task. | data-only. | P3 |
| `archlich` (elite) | Sharpen `archlich_immortal`: clearer desc naming the spell/effect out; Phylactery 8→6 (anti-stall); 2nd Lich Acolyte so the spell-economy puzzle lands R1. | data-only + desc. | P3 |

## MARQUEE FIGHTS (bosses / rival lords / amalgams) + REUSABLE TOOLKIT

The 5 amalgam finales reuse the same 4-5 generic passives → they feel interchangeable.
The fix is **one unique passive per throne**, drawn from a reusable toolkit. Bosses
`the_devil` / `the_crone` / `the_bellringer` and all 5 rival lords are already strong —
**leave them** (sharpening notes only).

### Toolkit (build once, reuse everywhere)
| passive | identity | hook | needs |
|---|---|---|---|
| `corpse_bloom` | enemies explode on death (opposing + behind) | on-enemy-death | Combat field `_encounter_passive_value` (phase-tunable) |
| `tithe_engine` | every Command you banked feeds a random enemy | start-of-round | promote `banked` carryover to field `_banked_last_round` |
| `phalanx_link` | front-row enemies SHARE incoming damage | damage-routing | guarded call `if _phalanx_absorb(...): return` — **care: touches damage path** |
| `entrenching` | a round with no spell → all enemies Armored next round +1 hardens | end-of-round | `_player_cast_spell_this_round` flag |
| `riptide_pull` | your front line is dragged a lane toward center | start-of-round | none (reuses retreat/slot helpers) |
| `summon_on_spell` (reactive) | each spell you cast raises an enemy body | ON_PLAYER_SPELL | none |
| `harvest_atk` (reactive) | any creature death → random enemy +1 ATK | ON_CREATURE_DEATH | none |
| `bleed_on_draw` (reactive) | each extra draw → 1 face + enemy heal | ON_PLAYER_DRAW | none |

### Boss redesigns (P2 — each needs the toolkit/phase plumbing above)
| id | Identity it gains |
|---|---|
| `iron_warden` | phase 2 `corpse_bloom` — the siege fires inward, dying guards become shrapnel |
| `dragon_lord` | `wyrm_breath` — a telegraphed inhale/exhale rhythm (2 to front row + 3 face every other round) instead of "Piercing, then bigger Piercing" |
| `collector` | `gallery_claim` — phase 2 STEALS your highest-ATK creature into a Caged Champion (use Combat's canonical removal helper, not queue_free) |
| `hollow_king` | `hollow_king_verdict` — phase 2 ALSO bleeds you per empty creature slot, so the wide board that beat phase 1 becomes the phase-2 liability |
| `the_black_tide` | `tide_drown_lanes` — flood pools in the BACK row; creatures in a fully-flooded column drown. Spatial, not number-creep |

### Amalgam finale identity pass (P2 — the headline once toolkit lands; each is a 1-3 line BOSS_PHASES swap)
| finale | unique passive |
|---|---|
| `amalgam_acolyte` | `corpse_bloom` (v3) — the room detonates on every death |
| `amalgam_raider` | `harvest_atk` reactive — gets faster the bloodier it gets |
| `amalgam_stalwart` | `phalanx_link` — can't focus-fire the shared-HP wall |
| `amalgam_pyromancer` | `bleed_on_draw` reactive — your card advantage bleeds you |
| `amalgam_kindler` | `tithe_engine` — hoarding Command feeds his fire |

---

## INTEGRATION CAVEATS (flagged by the agents — verify before applying)
- New per-fight Combat fields must be declared AND reset (in `_start_round` /
  combat setup, alongside `_escalation_banner_shown` / `_bandit_steal_fired_this_round`).
- `phalanx_link` and `oath_riposte` touch damage routing / attack resolution, not a
  clean dispatcher — single guarded call site each; test carefully.
- `gallery_claim` creature removal must route through the canonical death/removal
  helper so slot bookkeeping + on-death stay correct.
- `demon_spell_buff`: confirm where it fires today (reactive vs hook) before
  renaming the passive_id — keep that hook, add the round-engine passive alongside.
- A few agent specs also proposed CardDB/stat tweaks — out of scope for this register
  (encounter identity only); raise separately.
