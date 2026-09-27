# Onboarding & the coaching system — 2026-09-10

**Status: BUILT.** Gates: `tools/_probe_tutorial.tscn` (static, in `run_safe_probes`)
and `tools/_probe_tutorial_live.tscn` (empirical). Eyes:
`tools/_shot_tutorial_manual.tscn`, `tools/_shot_tutorial_tips.tscn`.
The operational summary lives in `CLAUDE.md` under "THE COACHING SYSTEM"; this
document is the **reasoning** — what the research said, what was decided, and
what was deliberately not built.

---

## 1. Why a tutorial at all — the one study that settles it

Andersen et al., *The Impact of Tutorials on Games of Varying Complexity*
(CHI 2012), tested 8 tutorial designs across 3 games with 45,000+ players.
Tutorials raised play time by up to **29% in the most complex game** and **did
not significantly help in the two simpler ones**.
<https://dl.acm.org/doi/10.1145/2207676.2207687>

Burning Meadow is unambiguously at the complex end: a 4×4 board, simultaneous
resolution, the muster delay, Command banking, overkill, 26 keywords, 6 tribes,
forge/relics/potions, and a branching map. This is the regime where tutorials
measurably pay.

**The "Slay the Spire proves you don't need one" argument does not transfer.**
There is no developer statement defending StS's minimalism as a design win; what
exists is a standing player complaint (the StS2 Steam forum carries a thread
titled "Game needs a tutorial"). The honest read is that it is a known weakness
its quality survives — and this game is *more* mechanically unusual with *less*
genre precedent to lean on, so it has less room to be terse.

**The counter-finding that shapes the whole design:** NN/g's tutorial study found
users who watched a front-loaded tutorial rated tasks as significantly *harder*
(4.92 vs 5.49, p=0.047) with no success benefit (91% vs 94%, n.s.). A tutorial
can manufacture the perception of complexity.
<https://www.nngroup.com/articles/mobile-tutorials/>

**Conclusion: teach, but teach in play, in small pieces, never front-loaded.**

---

## 2. The three faults of what was there

The teaching was six hand-rolled `_maybe_show_*` functions inside `Combat.gd`.
That shape had three faults and the player paid for all of them.

1. **THE COPY WAS UNREACHABLE.** A lesson living inside an `if` in a 25,000-line
   file cannot be listed, searched, or shown to a player who wants it back.
   *"How do I see that again?"* had no answer but "start a new profile".
2. **A FLAG WAS SPENT ONCE EVER**, per profile, with no way to un-spend one. The
   only control was a RESET button that wiped every flag at once.
3. **NOTHING COULD COUNT THEM.** Six lessons covered the first fight and nothing
   else in the game — no spell, no potion, no relic, no map, no shop, no camp —
   and the omission was invisible *because there was no list to compare against*.

Fault 3 is the argument for a registry. Everything else follows from it.

---

## 3. What was built

`scripts/data/TutorialDB.gd` — **22 lessons, one dictionary entry each, and
everything else derived.** Adding a lesson costs one entry plus one call site;
the seen flag, the OFF setting, the Field Manual row and the replay button all
follow. It references no autoload deliberately (it is a preloaded `RefCounted`;
see CLAUDE.md's parsecheck blind-spot rule).

### The skip

`UserSettings.coaching_mode`: **FULL / TIPS ONLY / OFF**.

Three settings rather than a checkbox, because the commonest state a returning
player is in is *"I know deckbuilders, I do not know THIS one"* and a boolean
cannot express it. **TIPS ONLY drops the guided walkthrough and keeps the
one-line rules peculiar to this game** — the muster, banking, overkill — which
are exactly the rules a genre veteran will otherwise mistake for bugs.

`TutorialCoach.should_teach(id)` is the single definition of "off" and every
teaching site asks it. A `KIND_STEP` additionally requires FULL.

Supporting devices:
- `SKIP TUTORIAL` on the panel — **named, not an X**. NN/g's onboarding component
  analysis asks for a highly visible skip; a bare `SKIP` or `X` does not say
  whether it drops the step or the walkthrough.
  <https://www.nngroup.com/articles/mobile-app-onboarding/>
- **Esc**, bound narrowly (only while a panel with a visible skip is up), because
  Esc is the pause menu on every screen the coach appears over. WCAG 2.1.1.
- **The recovery is named at the moment of the decision** — a note on step 1
  before, an info line after. A skip whose content is unrecoverable is not a
  skip, it is a trapdoor.

### The retrieval

**Per-lesson, never all-or-nothing.** The Game Accessibility Guidelines list
"allow all narrative and instructions to be replayed" as a standing requirement,
and NN/g's rule for dismissible help is that dismissal and *recall* matter
equally. <https://gameaccessibilityguidelines.com/full-list/>

HOW TO PLAY grew a **COACHING** tab beside the primer: every lesson printed in
full, ticked SEEN / NOT YET SEEN (a word, not a colour), each with SHOW AGAIN.
`make_how_to_play_overlay(open_tab)` takes 1 to land there directly, and Combat's
`?` panel has a **LESSONS** button that does so — the list was otherwise
reachable only from the main menu and the map, i.e. never at the moment a player
is actually confused. Settings keeps REPLAY ALL for the blunt version.

**The replay button is offered once per distinct underlying flag**, keyed off the
`legacy` field rather than a hand-listed set — which is why the three walkthrough
steps share one button. A walkthrough is one thing; you cannot have seen step 3
and not step 1.

### The coverage

6 lessons → 22.

| Where | Lessons |
|---|---|
| The guided fight | `walk_play` · `walk_commit` · `walk_lane` |
| In a fight | `muster` · `combat_model` · `intents` · `back_row` · `keywords` · `spells` · `banking` · `dismiss` · `piles` · `relics` · `potions` · `overkill` · `hero_hp` |
| On the road | `map_road` · `map_gate` |
| Between fights | `recruit_card` · `shop_trade` · `camp_choice` · `event_choice` |

**Every one fires the first time its subject is ON SCREEN, not on a fixed round.**
A tip that points at nothing is worse than no tip, because it is stamped seen the
moment it fires. The two clash-shaped lessons latch instead
(`_arm_overkill_lesson` / `_arm_hero_hit_lesson` set a bool inside the clash; the
round ladder cashes it in on the next player turn, with the board that produced
it still standing).

`recruit_card` is on the **Recruit** screen, not the post-fight spoils screen —
Recruit is the only place a card enters the deck, which is the mechanic a
deckbuilder lives on and the one nothing in the game had ever stated out loud.

---

## 4. Decisions taken against the obvious option

**No skip-prompt before the first fight.** It asks a question a first-timer
cannot answer, and it front-loads a decision — the exact thing NN/g's
front-loading finding penalises. Per-step skip dominates it: the player opts out
at the moment they *know* they don't need it.

**No confirmation dialog on skip.** NN/g reserves confirmations for serious or
irreversible actions and warns of the cry-wolf effect from routine ones. When an
action is reversible, the recall path replaces the confirmation — which is why
the skip and the Field Manual had to ship together.
<https://www.nngroup.com/articles/confirmation-dialog/>

**The guided fight stays at 3 steps.** Two independent product-tour datasets show
a completion cliff between 5 and 7 steps (Produktly: 1–2 steps → 73%; 3–5 → 38%;
6–8 → 25%; 9+ → 8%. Chameleon: 3-step 72% vs 7-step 16%). *This is SaaS data, not
game data* — the direction is consistent across both and coheres with Hodent's
cognitive ceiling, but do not quote the percentages as game figures. Hearthstone
independently cut its tutorial from 6 missions to 3 (Patch 27.6.0, Oct 2023)
while adding skip (24.6.0) and replay (25.4.0) — that is the strongest existence
proof for the shape shipped here.

**Cap concepts at ~3 per lesson.** Celia Hodent: "3 items to process at the same
time is THE MAXIMUM when in learning mode," against a working-memory baseline of
about 5±2 that shrinks for newcomers.
<https://celiahodent.com/gamers-brain-ux-onboarding/>

**Steps advance on the player's action, not a NEXT button.** NN/g's central
coach-mark finding: users cannot read an overlay and use the app at the same
time, so they must memorise, and short-term memory fades in ~20 seconds. The
scrim is `MOUSE_FILTER_IGNORE` so the punched hole stays live.
<https://www.nngroup.com/articles/mobile-instructional-overlay/>

---

## 5. Rules text is a design surface, not decoration

Two lessons were found to be teaching a rule the game does not have. Both were
caught by reading all 22 lessons *as a set* — each was defensible alone.

- `walk_lane` said the back row **"waits behind"** the front. That teaches a
  bench. The house rule is that the back row is play space and **both rows strike
  every round**; a player who believes otherwise wastes four of their eight
  slots.
- `intents` opened **"Front-row creatures protect the back row"** and then changed
  subject to forecast chips — the same bench implication, plus two rules in one
  line.

Both rewritten; a `back_row` lesson was added at the decision point (the first
time the front row fills, or the first body placed behind).

**The rule this establishes: audit rules text as a corpus, not per string.**
There are four places that state rules to the player — `HOW_TO_PLAY_PRIMER`,
`KeywordEffects.KEYWORDS`, `Combat.QUICK_HELP` / `MECHANICS_HELP`, and
`TutorialDB.LESSONS`. They were written by different passes at different times
and they drift.

---

## 6. Accessibility

- **Reduce Motion holds, it does not remove.** A coach mark is *informational* —
  it is the only thing on screen telling the player what to do. The pulse parks
  at its bright midpoint, the arrow stops bobbing, the dashes stop travelling;
  nothing is deleted.
- **No essential information by colour alone** (GAG). The glow is always paired
  with a punched hole, an arrow, or worded copy. The manual's SEEN state is a
  *word*, not a tick alone.
- **No timed auto-advance.** A step waits for the player (WCAG 2.2.1, XAG 116).
- **Known tension:** the one-line tip channel holds for 7 seconds and then
  releases, because it is shared with combat messaging. That is a timed
  dismissal of instructional text. The mitigation is the Field Manual — every
  tip is readable there forever — rather than a fix.
- Reading text ≥18px (COPY_STYLE §11); the panel's subordinate note is 15px, the
  caption register's floor.

---

## 7. Testing

**`tools/_probe_tutorial.gd` — static.** C1 reachability in *both* directions,
the copy contract, unresolved `{tokens}`, the legacy mapping, the seen/replay
round trip, and that OFF silences everything.

The reverse direction is the one that matters. `UserSettings.lesson_seen`
answers TRUE for an unknown id — deliberately, so nothing can loop forever on a
retired lesson — which means **a typo'd id at a call site reads as "already
taught", silently, forever, with no error anywhere**. Verified by mutation: a
one-character typo in Shop.gd's call site makes the gate fail. It also carries a
vacuity guard, because a regex that has stopped matching looks exactly like a
codebase with no mistakes in it.

**`tools/_probe_tutorial_live.gd` — empirical.** Static wiring is not
reachability (the C20 content-census lesson): these lessons are gated on
`_relic_chip_by_id`, `_potion_bar_root`, `_card_nodes`, `_gold_label` and named
node lookups being live, and "perfectly wired and still never opens" is a real
outcome. It boots a real fight (and real road screens) and requires each lesson's
text to actually reach the channel.

**Harness lessons worth keeping:**
- A **uniform failure across every case is almost always the oracle**, not the
  code. The first road-screen run failed both screens identically; the cause was
  a preceding phase leaving `coaching_mode` at OFF.
- **The settings overlay is not created per open** — it is a persistent child of
  the `UserSettings` autoload that `_open()`s and `_close()`s. A harness that
  cleans up by diffing the scene's children finds nothing and leaves it standing
  behind every later frame.
- **A new `class_name` is not in Godot's global class cache until an
  `--headless --import` pass.** It presents as "Identifier not declared" in every
  file that references it.

---

## 8. Not built, with reasons

- **Feature-locking the shell for run 1** (hide Ascension / Daily / Skirmish
  until the first run completes). Hearthstone does this and it is defensible —
  and the ascension stepper already isn't built below the first win — but it is a
  menu-structure change, not a tutorial one. Owner's call.
- **Teaching strategy.** Bycer's distinction: there is a difference between
  *"focus on hiding behind high cover"* and *"click here"*. A tutorial that tries
  to teach deck thinning or curve will fail, and this is the unfixable half of
  the Slay the Spire complaint. <https://game-wisdom.com/critical/onboarding>
- **A scripted fixed first run.** Bycer's roguelike-specific warning: a fixed
  tutorial run teaches that the game is handled the same way every time, which
  misfires the moment the map randomises. **Script the fight, not the run.**
- **Tribes and keystones** (6 tribes is far past the 3-item ceiling), veterancy
  rungs (the existing modals *are* the lesson), and the initiative choice (its
  own modal explains itself).

## 9. The standing question

Before writing any new lesson, ask Second Dinner's question first: **is this a
design fix wearing a tutorial's clothes?** They solved Marvel Snap's turn-1
dead-hand problem by giving Quicksilver "always appear in the opening hand"
rather than adding a mulligan, and new players stopped asking for the feature.
<https://mobilegamer.biz/second-dinner-reveals-the-secrets-of-marvel-snaps-onboarding-and-card-design/>
