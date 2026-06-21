# Burning Meadow — New-Player Clarity Audit

**Date:** 2026-06-21
**Method:** 10 parallel code-grounded audits, one per "surface" of the moment-to-moment
experience (combat round-flow, enemy intents, card readability, keyword teaching, HUD/resource,
combat result feedback, spell targeting/floop, map navigation, onboarding/first-run, player-facing copy).
**Question each agent answered:** *Can a relatively new player always tell what is happening right now —
and if not, what reframe or simplification fixes it?*

This audit is a **discovery pass** — no code was changed. Every finding cites `file:line`.

---

## ✅ IMPLEMENTATION LOG — Priority 1 shipped & verified (2026-06-21)

The discovery pass above was followed by an implementation sprint (file-disjoint agents + a
hand-driven `Combat.gd` lane). **All of Priority 1 is now in the working tree and verified.**

**Verification:** headless auto-play harness `_probe_autorun` ran the full encounter table —
**50 fights × 5 heroes, 0 softlocks, 0 SCRIPT ERRORs**. Combat, a card spread (live v9 layout),
and the map were rendered to PNG (windowed) and pixel-inspected.

| # | Quick win | What shipped | Verified |
|---|-----------|--------------|----------|
| 1 | On-card keyword reminders | `_chart_kw_reminder_bbcode` now wired into `_build_chart_proto`, with a vertical-room budget + a `· · ·` footnote. **Fix found in visual pass:** the skip-logic suppressed reminders whenever the desc merely *named* a keyword ("Shield. Swift."), leaving bare-keyword cards silent — now skips only when the desc *explains* it ("Keyword — …"). | ✅ rendered |
| 2 | Default-attack telegraph | Plain attackers show a font-independent red down-chevron (`_make_attack_fang`, Polygon2D). Suppressed when the louder "⚔ N" threat badge is up → exactly one swing signal per enemy. | ✅ rendered |
| 3 | Narrate combat phases | `FIGHT` → per-beat captions (swift / clash / fallen) plumbed through `_do_combat` / `_post_combat_sequence`, each guarded so it never names an empty phase. | ✅ autorun |
| 4 | Persistent targeting prompt | Spell targeting sets `_info_label` directly (no auto-clear), names the spell, and says right-click cancels. `_show_info` self-stomp guarded with a token. | ✅ autorun |
| 5 | Curated first fight | First-ever run (`MetaState.total_runs == 0`) forces `goblin_scouts` (gentlest Act-1, no passive/mutator); RNG byte-identical for all later runs. | ✅ code |
| 6 | Distinct wayside glyphs | Per-verb ink glyphs on the chart (anvil / scales / banner / chest) via `MapTerrain._draw_wayside_glyph`; legend prints each verb + name. | ✅ rendered |
| 7 | Command tooltip + banking pips | Player Command seal is now hoverable (teaches resource + refill + banking); gilt carryover pips on the plinth shelf show how much will bank, refreshed on every HUD tick. | ✅ rendered |
| 8 | Mechanic-before-flavor copy | Card descs lead with the trigger (`On-Enter:` etc.) + keyword gloss; flavor trails. | ✅ rendered |
| 9 | Show the Exhaust pile | Third diegetic stack appears once anything is exhausted. | ✅ autorun |
| 10 | Vestigial floop UI | Stubbed on both card paths. | ✅ code |

Plus map-legibility wins (objective line now **"HOLDS BROKEN n/2 · OPEN THE LORD'S ROAD"**, "SHOP · spend
gold" / "RECRUIT · free draft" qualifiers, a labelled "YOU ARE HERE" marker, colour-blind reachability
chevron/padlock cues, open-zoom dropped so place-names read) and the 8 redesign keyword icons registered
in `GameTheme` (were silently icon-less).

**⚠️ Flagged, not authored by this sprint:** `CardDB.gd` also carries 4 *mechanical* changes (troll →
Regenerate hp3→4; riteforge cost 4→2 / hp 6→4; standard_bearer hp 4→3; troll's upgrade delta). These were
already in the working tree at session start (an in-progress balance pass), are internally consistent, and
pass autorun — **left intact, surfaced here for the owner to confirm or revert.**

**Not yet done:** Priority 2 (always-on full-line telegraph, scrolling combat log, labelled effect callouts,
first-run coach-marks) and below — see the sections that follow.

---

## The core thesis (read this first)

The known playtest failure is *"players ignore effects and just charge in."* This audit found the
**structural reason**: the game's entire "depth-on-demand" layer is real and accurate, but it is **gated
behind hover, one-shot toasts, and an opt-in manual** — exactly the affordances a charging newcomer
never uses. The mechanics are fine. The *surfacing* is the bug.

Five cross-cutting themes explain almost every individual finding:

| # | Meta-theme | What it looks like in practice |
|---|-----------|--------------------------------|
| **A** | **Everything important is hover-gated, but new players don't hover.** | The combat telegraph (who-hits-whom + kill prediction), the full card rules panel, keyword icon tooltips, relic tooltips, map node tooltips, the banking explanation — all require a hover the charging player never performs. |
| **B** | **Effects fire silently — no cause→effect narration.** | On-enter, on-death, encounter passives, reactive passives, stat buffs/debuffs and relic procs mutate the board with no labeled callout. There is **no combat log** to reconstruct a busy simultaneous step. The board changes; the player can't attribute it. |
| **C** | **Phases and round structure aren't signposted.** | "FIGHT" is one flat label covering five sub-phases. "Round 1 · Deploy your line" implies a safe setup turn that doesn't exist. Simultaneous combat is taught once as text, then contradicted by a sequential-looking animation. |
| **D** | **The first session has no on-ramp for the core verbs.** | Drag-to-play, what Command is, and spell targeting are taught *nowhere* in context. The first fight is randomly shuffled and can carry a mutator. "How To Play" is the 9th menu button and a wall of text. |
| **E** | **Finished clarity features sit unwired or under-used.** | `_chart_kw_reminder_bbcode` (on-card keyword reminders) exists but is **never called**. `_spawn_atk_change_popup` / `show_heal_number` exist but most stat/heal sources skip them. The intent system renders **nothing** for the most common case (a plain attack). |

**The single highest-leverage move** is a direction, not one edit: take the most critical reads — keyword
meaning, "this enemy will hit you," "this effect just fired," "Command/banking" — and promote them from
*hover/one-shot* to *always-on or first-time-auto-shown*.

---

## Confirmed factual correction: Round 1 is NOT setup-only

Two audits flagged a contradiction; it is now resolved by reading the code:

- `_on_end_turn()` (Combat.gd:1561) **always** `await _do_combat()`; `_do_combat()` (Combat.gd:2091) has
  **no round-1 guard** — full Swift + simultaneous combat runs every turn.
- The code header (Combat.gd:5) is **correct**: *"Combat happens every round (no setup-only round)."*
- The comment at Combat.gd:1304 ("Round 1 is setup-only"), the HUD sub-label "Round 1 · Deploy your line"
  (Combat.gd:11800), and CLAUDE.md ("Round 1 is setup only (no combat)") are **stale/misleading**.
- **Player impact:** if the enemy opens in a front formation (opening formations are live), ending turn 1
  clashes immediately and the player takes face damage they were told was a free "deploy" turn.

**Fix:** pin down the intended behavior, then make copy match. Recommended copy (since combat *does* run):
"Round 1 · Set your line — they strike when you end the turn." Update the stale comment and CLAUDE.md.

---

## PRIORITY 1 — Quick wins (High impact · Small effort)

These are the do-first list: each is a small, low-risk change with outsized clarity payoff.

1. **Wire the on-card keyword reminder line.** `_KW_REMINDER` + `_chart_kw_reminder_bbcode` already exist
   (Card2D.gd:3365, 3383) — plain one-liners like *"Poison — anything it wounds dies."* — written
   specifically because "new players read+drag, they don't hover the glyphs." Nothing calls it. Append its
   output to the desc RichTextLabel in `_build_chart_proto` (~Card2D.gd:3769), guarded for vertical room.
   *Flagged independently by the card-readability and keyword agents. Near-free; biggest single win.*

2. **Give the default ATK intent a visible marker.** `_update_intent_display` early-returns for ATK
   (Combat.gd:7152), and `_assign_intents` makes ATK the default (Combat.gd:7120) — and *zero* CardDB
   creatures define an intent, so **most enemies telegraph nothing**. Add a small persistent "will swing"
   chevron / crossed-swords mini-glyph on every attacking enemy (`current_intent` ATK/CHARGE/ENRAGE and
   `can_attack()`). Completeness fix for the whole threat system.

3. **Narrate the combat phases through the existing `_phase_label`.** Today "FIGHT" (Combat.gd:11822)
   covers swift → clash → deaths → discard → enemy-reinforce → passives. Set short captions at the points
   the loop already passes through (`_do_combat` 2112/2123/2139, `_post_combat_sequence` 3127):
   "SWIFT STRIKES → CLASH → THE FALLEN → ENEMY REINFORCES." No new system; just `.text` assignments.

4. **Make the targeting prompt persistent and informative.** "Click a target..." is routed through the
   auto-clearing `_show_info` (Combat.gd:4410) and vanishes after 2s while targeting stays armed. Set the
   label directly for the duration and name the spell + legal target + cancel: *"Fireball — choose an enemy
   creature · right-click to cancel."* Clear it in resolve/cancel.

5. **Curate the first fight + teach the core verb.** `_assign_encounters` shuffles the pool (RunState.gd:1361)
   and rolls a 35% mutator on every node incl. the first (RunState.gd:1376). For `MetaState.total_runs == 0`,
   force the Act-1 row-0 node to a gentle hand-picked encounter and suppress its mutator. **Add a
   `place_tutorial_seen` coach tip** ("Drag a creature from your hand onto a lane to deploy it") — the single
   most fundamental action is taught nowhere. Clear it at `_first_creature_played` (Combat.gd:2794).

6. **Distinct glyphs for the four wayside verbs.** GameTheme:278 maps *all* waysides to one horned-helm
   glyph and `_node_icon` (MapTerrain:2526) returns it for every `"wayside"`, so Drill Yard / Scales /
   Standard-Bearer / Supply Cache are pixel-identical on the chart — breaking the stated route-planning
   contract. Branch `_node_icon` on `nd.wayside_id` (anvil / scales / banner / chest) and expand the legend.

7. **Command seal: hover tooltip + always-on banking visualization.** The seal shows only `current / max`
   (Combat.gd:11787) with a cryptic `(+N)` only on over-cap; banking is taught once by a 6s toast and never
   again. Add a hover tooltip ("Command — your turn resource; up to 2 unspent carries over") and render
   bankable pips under the seal (fill as unspent ≤2 accrues; grey the 3rd to signal "this one is lost").
   On the end-turn confirm, state the real number: "You'll bank 2 Command. 1 will be lost."

8. **Card faces: mechanic before flavor; gloss opaque keyword names.** Beginner/showcase cards open with
   flavor or a bare unexplained keyword, e.g. `cinder_pup` = *"Doom 2. Bred to burn…"* (CardDB.gd:409),
   `doom_knight` = *"Swift. Piercing. Overrun."* (CardDB.gd:390). For the showcase block, spend the well on
   a one-clause gloss of the new keyword; move flavor to hover. (Copy-only; respects COPY_STYLE; does **not**
   touch `KeywordEffects.display`.)

9. **Show the Exhaust pile.** `_exhaust_pile` is real state (Combat.gd:92) but `_build_piles_diegetic`
   (Combat.gd:10946) only builds DECK and DISCARD — exhausted cards appear *deleted*. Add a third stack/
   counter wired to the existing `_show_pile_viewer`.

10. **Remove or hard-gate the vestigial floop UI.** Floop is dead code (migrated to `on_play`; no card
    carries a `floop` key; `will_floop` is read by zero combat logic). Yet `update_floop_display`
    (Card2D.gd:5276) still builds a pulsing cyan "CLICK · FLOOP" badge + border tint + tutorial, and a
    stray data key would surface a prominent non-functional button. Delete/stub the path, or hard-gate it so
    it can never render in single-player. Also removes a top jargon source for newcomers.

---

## PRIORITY 2 — High value, larger effort

11. **Always-on enemy telegraph for the whole line during planning.** The accurate per-strike read
    (`_predict_lane_strike`, Combat.gd:12625) is hover-only and, in solo play, only previews the *player's*
    attacks. During the planning phase, proactively draw faint arrows for every enemy strike (brightening
    the hovered one). Resolves most of meta-theme A and findings #2 in one pass.

12. **Lightweight combat log.** There is **no log of any kind** (confirmed). In a simultaneous step where
    several creatures trade, die, and trigger on-deaths, floats overlap and vanish in <1s with no recovery.
    Add a collapsible corner `RichTextLabel`; push one terse, color-coded line per event from existing
    chokepoints (`take_damage`, `_die`, `damage_player_hero`, the dispatchers, relic procs). Highest-leverage
    "what just happened" fix because it works regardless of pacing.

13. **Labeled callouts for on-enter / on-death / passive effects.** `_run_on_enter` (KeywordEffects.gd:272)
    and `_run_on_death` (KeywordEffects.gd:418) resolve silently; `EncounterEffects.gd` has ~25 state
    mutations and **one** feedback line (EncounterEffects.gd:391). Spawn an `ON-ENTER`/`ON-DEATH` chip at the
    *source* via the existing `_spawn_keyword_chip` with a short beat before resolution; give each passive a
    one-line callout naming the passive (e.g. "Spellbreaker bleeds you for casting — 2"). This is the direct
    antidote to "players ignore effects."

14. **First-run just-in-time coaching system.** Replace reliance on the transient, self-stomping `_info_label`
    (Combat.gd:13305) with a small pinned coach-mark widget for the primary loop: place → Command →
    end-turn/simultaneous → targeting, gated to the first session via `MetaState.total_runs` + `UserSettings`
    flags (infra already exists). Promote/auto-surface "How To Play" on first launch only.

15. **Map: open inside the dress crossfade; add a real "you are here."** The map auto-opens at 1.45
    (MapView.gd:86), *above* `DRESS_ZOOM_HI = 1.30`, so all place-names/terrain/keep labels are faded to
    zero unless the player wheels out (which they have no reason to do). Open at ~1.15–1.25 or keep the keep/
    region plaque un-gated. Separately, the player's position is only a swaying banner with no label and is
    easily confused with conquered pennants — add a distinct "YOU ARE HERE" cue.

16. **Route every stat change through a floating popup.** Buffs/debuffs/relic procs (Royal Guard, Vampire
    Lord, Vengeance, escalation +ATK, on-death `debuff_all_player_atk`, play-time relics like
    `veterans_medal`) only nudge the orb numeral. `_spawn_atk_change_popup` (Card2D.gd:5563) and
    `show_heal_number` (Card2D.gd:5586) already exist — wire them everywhere; fan board-wide debuffs across
    all affected creatures so the swing reads as one event.

17. **Persistent mutator/passive HUD chip.** The mutator (★) and passive descriptions appear *only* in the
    intro banner, which tweens away (Combat.gd:13221/13190). Add a small persistent HUD chip (hover-expand to
    full text) so rule-changers like "all enemies have Thorns" stay readable all fight.

---

## PRIORITY 3 — Polish (mostly Small effort, lower individual impact)

- **Stat numerals on hand cards are small/low-contrast** (15px on a textured wax seal, Card2D.gd:3807).
  Bump to ~18–19px, deepen the seal's pressed face, adopt the verified white-fill/5px-outline treatment.
- **Creature-vs-spell is never stated in words** — it's read-by-omission (3 seals vs 1). Put "SPELL" on the
  spell footer (Card2D.gd:3863).
- **Normalize trigger vocabulary** — "On-Enter:" vs "When played:" are the same moment with two names
  (CardDB.gd:15 vs :47). Pick one player-facing label.
- **Upgraded "+" cards barely read as upgraded** — only a " +" name suffix that can be ellipsized away
  (Card2D.gd:3677). Add a glance cue (gem/metal tint or boosted-stat color).
- **Standardize the rest-screen verb** — Upgrade / Forge / Reforge are three words for one action
  (Rest.gd:262/478/288). Settle on **Forge** (+ "Forge Two" for Whetstone).
- **Disabled-action labels name the cause, not the effect** — "Blocked by Hairshirt." (Rest.gd:233).
  Lead with the rule: "Can't heal at camp (Hairshirt)."
- **No gold counter in combat** — gold is earned (RunState.gain_gold) but never shown on the combat HUD.
- **Reachability is color-only** (amber vs ink, MapTerrain:2221) — add a non-color cue (chevron / footstep /
  lock glyph) for colorblind safety.
- **Add the 4 missing keyword SVGs** (rampage/lifelink/overrun/formation — names already in the allow-list,
  GameTheme.gd:1295) so they get a card-face device instead of cryptic 3-letter chips; note the
  structure/slay/adjacent glossary entries that have no on-card counterpart.
- **Distinct creature-hit / creature-death SFX in the cascade** — the attack loop plays no audio of its own;
  a kill is audibly the same as nothing.
- **Targeting polish** — anchor the arrow origin to the cast card (Combat.gd:12266 hardcodes screen-bottom),
  swap to a crosshair cursor while aiming, give "any/face" spells a visible hero hit-zone (the magic 0.15
  band, Combat.gd:5253), and surface "Command refunded" on the silent cancel paths.
- **`_show_info` self-stomps** — its 2s timer clears unconditionally (Combat.gd:13305), so a second message
  wipes the first early. Mirror the tutorial-tip guard or queue messages.
- **"C O M M A N D" letterspacing** (Combat.gd:10922) hurts the most important label's legibility — drop to
  normal tracking or fold the meaning into a tooltip.
- **Deck-empty reshuffle is invisible** — when DECK hits 0 it silently reshuffles discard; flash a
  "shuffles in" hint.
- **Glossary discoverability in combat** — the "?" orb (Combat.gd:11562) is a bare disc; nudge it the first
  time an unfamiliar keyword resolves.
- **Keyword icon rail caps at 3** with no overflow mark (Card2D.gd:3320) — show "+N" when exceeded.

---

## Per-surface detail (full findings)

### 1. Combat round-flow
- **"FIGHT" is one opaque label over five sub-phases** → phase captions via `_phase_label` (see P1 #3).
- **"Round 1 · Deploy your line" implies a setup turn that doesn't exist** → see factual correction above.
- **Simultaneous combat taught once, contradicted by sequential-looking cascade** → re-flash "BOTH SIDES
  STRIKE" per fight; label trades as "TRADE" in the hover prediction (Combat.gd:12580).
- **Vanilla fights start with zero framing** (intro gated to boss/elite/passive, Combat.gd:534) → always
  show the cheap `quick` name flash.
- **Enemy non-attack intents resolve silently** (`_resolve_intents`, Combat.gd:7211) → brief float per
  resolution ("GUARD!", "RALLY!").
- **No post-combat outcome summary** → one-line net result after `_cleanup_dead` (Combat.gd:2139).
- **`_info_label` sits dead-center over the clash** (Combat.gd:10092) → move to a reserved strip; back tips
  with a faint panel.
- **Hand model drift** — live is draw-to-5 with kept cards (`PERSISTENT_HAND`, Combat.gd:52), but
  CLAUDE.md says "draw 4"; teach it in round 1.

### 2. Enemy intents & threat telegraphing
- **Default ATK shows nothing; most enemies never telegraph** → P1 #2.
- **Hover telegraph is the only per-lane read and is undiscovered** → P2 #11 + tutorial mention of hover.
- **`ABILITY` intent is a generic word** — devour/steal/curse/raise/heal all render as "ABILITY"
  (Combat.gd:7156) → map `ability.type` to a verb + icon.
- **Intents computed once at round start, never refresh** (Combat.gd:1337) → refresh display from
  `_update_hud` like the INCOMING chip already does.
- **INCOMING chip under-warns** — ignores Piercing overflow into blocked lanes and pending CHARGE/ENRAGE
  buffs (Combat.gd:8253, 10258) → fold both in; over-warn rather than under-warn.
- **NEXT WAVE telegraph only covers faction schedules** (Combat.gd:3299) → extend to generic/escalation/
  pursuit drip so every reinforcing fight says so.
- **Passive/mutator threats explained once then gone** → P2 #17.
- **Per-creature danger glow is hardcoded to one boss** (`hollow_king`, Combat.gd:8309) → generalize to any
  passive with a predictable target.

### 3. Card-at-a-glance readability
- **Keyword devices have no words; the reminder system is unwired** → P1 #1.
- **Stat numerals small/low-contrast on textured seals** → P3.
- **Creature-vs-spell never stated in words** → P3.
- **Inconsistent trigger vocabulary** → P3.
- **Upgraded cards barely read as upgraded** → P3.
- **Flavor interleaved with rules in one ink block** inflates reading load and forces 10px shrink
  (Card2D.gd:3758) → separate or de-emphasize flavor.
- **Three stat color languages across surfaces** — red = ATK on hover but = damaged-HP on tokens
  (Card2D.gd:6533 vs GameTheme.gd:470) → one HP color, one ATK color everywhere; reserve a separate signal
  for deltas.
- **The rich glossary is hover-only** → auto-show the detail panel once per unique card per run.

### 4. Keyword teaching & clarity
- **Coverage check:** all 26 keywords are in all three glossaries (main-menu, map HUD, in-combat "?"), but
  **rampage/lifelink/overrun/formation have no SVG** (card-face shows only the word / a 3-letter token chip),
  and **structure/slay/adjacent** are glossary terms with no on-card counterpart. `floop.svg` is registered
  but has no glossary entry (inverse mismatch).
- **Unwired on-card reminder** → P1 #1. **Four icon-less keywords** → P3 (add SVGs).
- **Icon-only roundels have no name and no tooltip on the live layout** (Card2D.gd:3319; the tooltip path at
  2247 is the superseded v3 layout) → rely on the printed reminder; optionally add tooltips.
- **In-combat glossary trigger is a tiny "?"** → first-fight nudge.
- **First-encounter keyword teaching** — effects float a label that *confirms* but doesn't *teach* → expand
  the first trigger of each keyword per run into a brief labeled tooltip-card (track via a "keywords_seen" set).

### 5. HUD & resource clarity
- **Banking never visualized; over-cap `(+N)` cryptic; taught once** → P1 #7.
- **Exhaust pile absent** → P1 #9.
- **"C O M M A N D" letterspacing**, **relic hover may be eaten by an IGNORE container** (Combat.gd:11655),
  **no gold in combat**, **deck-empty reshuffle invisible**, **end-turn button undersells the clash**,
  **potion "click to use" is silent** → P3.
- *Already strong:* HP medallion (numerals + drain bar + dread vignette + face-flash), Command spend pulse,
  affordability dimming, INCOMING chip, clickable pile viewers.

### 6. Combat result feedback ("what just happened")
- **On-enter/on-death fire with no "what & why"** → P2 #13.
- **Encounter/reactive passives are invisible** (1 feedback line in EncounterEffects.gd) → P2 #13.
- **No combat log** → P2 #12.
- **Face damage from non-combat sources has the flash but not the cause** (Combat.gd:5804) → add a
  `source_label` under the HP number ("Doom!", "Spellbreaker").
- **On-enter resolves the same frame the card lands** (Combat.gd:4258) → insert a landing beat.
- **No creature-hit/death SFX in the cascade**, **silent stat changes**, **coalesced deaths unreadable**,
  **silent regenerate/wither ticks**, **`_show_info` overwrite** → P3 / P2 #16.
- *Already strong:* per-hit floating numbers, magnitude-scaled shake, the face-damage moment, death bursts,
  combat-keyword chips (SHIELD/BLOCKED/LAST STAND/POISON/THORNS/PIERCED/DOOM/RAMPAGE).

### 7. Spell targeting & floop
- **Targeting prompt evaporates after 2s** → P1 #4.
- **Valid targets not highlighted, invalid not dimmed** (rules live only in `_try_resolve_target`,
  Combat.gd:5212) → highlight legal set on entry; dim the rest.
- **Clicking an invalid target/empty space does nothing** (silent fall-through, Combat.gd:5200) → flash a
  reason.
- **Floop is fully vestigial** → P1 #10.
- **Right-click-cancel never communicated; no targeting tutorial; arrow origin wrong; "any/face" hot-zone
  invisible; extra cancel paths silent; no cursor change** → P3.
- *Already strong:* the gold targeting arrow + live damage/heal/LETHAL prediction over valid targets.

### 8. Map & navigation
- **Four wayside verbs share one glyph** → P1 #6.
- **Opens in march dress, hiding place-names; no "you are here" label** → P2 #15.
- **Reachability is color-only** → P3.
- **Node meaning lives only in tooltips; How-to-Play omits the map** → add a "READING THE CHART" primer block.
- **Recruit vs Shop easy to confuse** → bake "free draft" / "spend gold" into the legend.
- **Mutator ★ and pursuit pennant unexplained** → add to legend.
- **"PROVINCES CLAIMED X/Y" counts all nodes**, diluting the real "break N holds" gate → retitle or recount.
- *Already strong:* the always-on legend (MapTerrain:2452), genuinely plain-language tooltips, the always-on
  objective banner, clear amber reachability.

### 9. Onboarding & first-run
- **The cliff:** the first combat turn with no instruction on the core verb (drag-to-play). The first fight
  is random and possibly mutated. Command is never taught in context. "How To Play" is buried (9th button)
  and a wall of text. → P1 #5, P2 #14.
- **Hero select sells flavor, teaches no mechanics; map gives no "what do I click"; spell targeting untaught;
  the "?" orb isn't self-evident** → P2 #14 / P3.
- *Already strong infra:* `UserSettings` one-time-flag pattern, `MetaState.total_runs` (first-session
  detection, currently unused by onboarding), the five existing just-in-time tips (the right idea, wrong
  channel + missing the primary loop).

### 10. Player-facing copy
- **"Floop" surfaced raw as a core verb** (Card2D.gd:1499, Combat.gd:5520) → P1 #10 removes most of it; gloss
  the rest.
- **Card descs open with flavor / bare keywords** → P1 #8.
- **Opaque keyword names have no gloss on the card face** → P1 #8 (desc edit, not `display`).
- **Disabled-action labels name the source not the rule** → P3.
- **Forge/Upgrade/Reforge inconsistency** → P3.
- **Push-your-luck consequences written as riddles** ("the dregs," "the trick clicks", Event.gd:2170/2385) →
  state the loop plainly in the *choice* line; keep flavor in the body.
- **Command `(+N)` shown with no label** → P1 #7.
- **"Vanguard" styled like a keyword but isn't one** (CardDB.gd:55) → lowercase to a plain descriptor.
- **Curse cards undersell their real cost** ("Does nothing" omits "clogs your hand") → restate.
- *Positive pattern to propagate:* the waysides' "flavor headline + always-present plain payload line"
  (Wayside.gd:483) is the model the rest of the game should follow.

---

## What's already good (the baseline)

The game is **not** a blank slate on clarity — these systems are solid and should be *extended*, not rebuilt:

- A full **26-keyword glossary** reachable from three surfaces (main menu, map HUD, in-combat "?" + Tab/?).
- A **hover detail panel** on every card (hand *and* enemy) that spells out keywords and triggers accurately.
- An **enemy intent + INCOMING-damage** system with color escalation and live updates as you block.
- An accurate **hover combat telegraph** (arrow + "-N"/"DIES"/"LETHAL" prediction).
- A strong **HP feedback stack** (drain bar, dread vignette, crimson face-flash, magnitude-scaled shake).
- A genuinely good **map legend + plain-language tooltips + always-on objective banner**.
- The **just-in-time tip pattern** (one-time, persisted via `UserSettings`) — the right model, just applied
  to secondary mechanics instead of the primary loop.

The work ahead is overwhelmingly **surfacing and wiring**, not inventing.
