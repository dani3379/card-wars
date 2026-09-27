# THE BUG SWEEP — a method, not a hunt (2026-08-29)

Three rounds of ad-hoc hunting in skirmish produced 13 bugs, then 1, then 0. That
curve is the point: unguided reading finds the bugs it happens to walk past, and
then stops finding anything while plenty remain. This document replaces the hunt
with a **method** — a taxonomy of how bugs HIDE, because how a bug hides is what
decides the technique that finds it, and a technique applied exhaustively over an
inventory is the only thing that can report COVERAGE rather than anecdote.

Scale being swept: **110 scripts / 118,315 lines / 21 scenes**, plus the content
DBs (192 cards, ~135 relics, 55 encounters, 46 events, 26 keywords).

## The honest limits, stated first

"Every possible bug" is not achievable and claiming otherwise would make the rest
of this document untrustworthy. Out of reach, permanently:

- **Design and balance defects.** "The practice bot is too weak" is not a bug, it
  is a decision, and it is the owner's. This sweep reports them and stops.
- **True two-peer faults.** Everything here runs in ONE process. A bug that needs
  two real sockets, real latency, or a mid-match disconnect at a specific frame is
  outside it. `tools/_probe_skirmish_net.gd` already runs two processes for the
  TRANSPORT; extending that pattern to a full two-process MATCH is the one piece
  of missing infrastructure worth building, and it is listed as Pass 9.
- **Emergent multi-system interactions** beyond what a soak happens to produce.

Everything else is in scope, and each class below names its detection technique,
its inventory, and its stopping condition.

## The nine classes

### C1 — UNREACHABLE / ORPHANED
Content or code that can never run. Hides because *nothing errors* — a dead arm is
indistinguishable from a live one by reading it.
- **Technique:** cross-reference producer ↔ consumer tables mechanically.
- **Inventory:** every dispatch table vs its emitters (effect types, passives,
  spell ids, keyword handlers, event effect types, relic effect ids), every id
  referenced across DBs, every asset path.
- **Precedent:** the 2026-08-07 pass deleted SIX minigames that were dispatched,
  listed in `MODAL_EFFECTS`, and emitted by no event — 2,257 lines a player could
  never reach. Nothing caught that for months.
- **Stop when:** every table has a producer↔consumer diff with zero orphans on
  both sides, or an explicit waiver per entry.

### C2 — TWIN DIVERGENCE
The same rule implemented twice. Hides because each half is individually correct.
- **Technique:** enumerate the twins, then a PARITY probe that runs both and diffs.
- **Inventory:** host ↔ client (`NetPlayerState` ↔ `Combat`), solo ↔ net resolvers,
  live layout ↔ baked layout (`_build_chart_proto` ↔ `_build_baked_overlay_layout`),
  base card ↔ "+" card, campaign ↔ skirmish.
- **Precedent:** `NetPlayerState` restated seven relic magnitudes as literals that
  `Combat` read from RelicDB — equal today, silently divergent on any retune.
- **Stop when:** every named twin has a parity gate.

### C3 — GUARD ASYMMETRY
A predicate applied in one sibling and forgotten in another. Hides because the
guarded path works, so the feature "works" in testing.
- **Technique:** for each predicate, enumerate ALL sites of the sibling family and
  diff which carry it.
- **Inventory:** `vs_bot`, `_is_sealed()`, `_is_client()`/`_is_host()`,
  `is_instance_valid` after an `await`, null-guards on optional nodes.
- **Precedent:** THREE this session. `_on_card_played` lacked the `_is_sealed`
  branch its sibling `_toggle_discard_mark` had → Sealed Orders could not seat a
  creature. `_net_apply_remote_spell` lacked the `vs_bot` guards its sibling
  `_net_apply_remote_creature` had → the bot could never cast. `_net_on_peer_lost`
  set its latch in one branch and not the other.
- **Stop when:** each predicate has a sites-table with every member either guarded
  or waived in a comment.

### C4 — CONTRACT VIOLATION
Something exceeds or undershoots a *declared* limit. Hides because the limit is
declared in one file and violated in another, and nothing compares them.
- **Technique:** measure actual against declared.
- **Inventory:** text vs its box, font size vs the readability floor, wire arrays
  vs `NetProtocol` caps, hand/board/deck caps, COPY_STYLE word budgets.
- **Precedent:** eleven card faces clipped mid-sentence against `_fit_desc_to_box`'s
  own budget; nothing had ever measured it.
- **Stop when:** every declared constant with a runtime counterpart has a probe.

### C5 — STATE-MACHINE DEFECT
A state you cannot leave, a latch that does not reset, an await that outlives its
owner.
- **Technique:** soak for reachability; explicit exit-reachability per state.
- **Precedent:** Bo3-vs-bot waited forever on a rematch answer no peer could send.
- **Stop when:** every terminal/blocking state has a proven exit.

### C6 — PRESENTATION LIE
UI that asserts something untrue: a button label that misnames its consequence, a
count that contradicts its rows, a refusal with no feedback, a status colour that
means two things.
- **Technique:** render every screen and READ it; compare each label against the
  code that acts on the click.
- **Precedent:** `HOST (LAN)` rendered as a section heading; `READY` wore the same
  green the opponent plate uses for *status*; the draft ledger showed 5 relics and
  potions under a header reading "YOUR DECK 5 / 20".
- **Stop when:** all 21 scenes shot and read, in both their empty and populated
  states.

### C7 — RUNTIME FAULT
Null deref, index error, infinite loop, freed-node access.
- **Technique:** soak breadth with `SCRIPT ERROR` counted as failure, plus fuzzed
  inputs at every trust boundary.
- **Stop when:** every scene has a soak that drives it through real entry points
  with zero engine errors.

### C8 — PERSISTENCE & DETERMINISM
A save that does not restore what it saved; a seed that does not reproduce.
- **Technique:** round-trip diff (state → save → load → state) and same-seed
  double-run diff.
- **Known open lead:** broken daily determinism (`project_bug_hunt_20260824`).
- **Stop when:** every persisted field round-trips and every seeded system
  reproduces.

### C9 — TEXT ↔ BEHAVIOUR MISMATCH
The card says X, the resolver does Y. Hides from every mechanical technique above,
because both halves are internally valid — only *meaning* disagrees.
- **Technique:** partially automatable (extract claimed numbers/keywords from the
  desc and compare against the data fields and the resolver's constants); the
  remainder is reading, card by card.
- **Known trap:** `reference_keyword_text_lies` — substitutive vs additive wording
  cannot be caught by grep.
- **Stop when:** every draftable card's claimed numbers match its data, and every
  keyword named in prose is one the card actually carries.

## Results so far

**Pass 1 — C1, `tools/_probe_reachability.gd`.** The content layer is healthy: 25
on_enter types, 14 on_death, 20 on_play, 53 passives, 78 spell ids and 69 event
effect types ALL have handlers; no dangling card or relic id anywhere in HeroDB,
EncounterDB or EventDB. One real orphan — **`relic_sacrifice_pick` ("The Old
Forge")** — **now WIRED, not deleted**: the effect, its picker, its decline path,
its no-target reason, the `has_nonstarting_relic` gate and `old_forge.png` had all
shipped, and nothing emitted any of it. Unlike the six minigames cut on 2026-08-07
it had no live replacement, so deleting a working feature to satisfy a gate was the
wrong direction. The event now OWNS its painting (the plate had been borrowed by two
events with no owner at all); `the_powder_move` moved to `three_doors` per the art
ledger's own recommendation, and the ledger was updated. `WAIVED_ORPHANS` is empty
again. Rendering the picker for the first time immediately exposed a second defect
— see Pass 6. Two false positives caught before acting: `stranger_hand_pick`
(emitted from a top-level `auto_effect`, not `choices[].effects[]`) and `structure`
(stamped on by EncounterDB, not printed on a card) — both would have deleted live
content.

**Pass 6 — C6, partial.** Shop, Reward, GameOver and the newly-wired Old Forge
rendered and read. **The relic picker's rows were sized at 96px**, calibrated on a
two-line rules block; several relics wrap to three, so with two such relics the
SECOND one's description was scrolled out of sight and read as a relic with no text
beside one that had it. Raised to 128px, keeping the 440 cap. It had never been seen
because the whole feature was unreachable — the reachability fix is what made the
layout fix findable. Two other candidates were verified as NON-bugs: "PROVINCE 0"
(a harness artifact — `current_floor` increments on `visit_node`, and Reward always
follows one) and the hero/enemy name overlap (the set-piece "Kindler" is an authored
named antagonist, so only the rank-and-file Pyre Cult creatures overlap — a lore
call, left to the owner).

**Pass 2 — C3, `tools/_probe_guard_audit.gd`.** 1,204 functions scanned. No
unguarded `_remote_state` dereference survives; every net turn gate is either
sealed-aware or waived with a reason. One real bug found and fixed:
**`_net_show_order_choice` waited on `while picked[0] < 0` with no timeout, no
match-over term and no validity test**, while its literal twin
`_net_show_order_wait` had all three — so an opponent quitting during the toss left
the winner's coroutine dereferencing a freed Combat once a frame, forever. A
latch-shape heuristic was tried first and REMOVED at 6/6 false positives: a check
that is all noise trains people to ignore the gate.

**Pass 3 — C5/C7, `tools/_probe_campaign_walk.gd`.** The routing twins
(`MapView._scene_for_node_type` and MainMenu's resume table) agree on all 11 types,
every one of the 10 types the generator actually emits is routed by BOTH, and 36
sampled acts walk camp → boss over 648 node visits with every step routable. Two
harness traps hit on the way, both now written into the probe: assigning
`current_act_idx` instead of calling `advance_act()` (a recorded trap — it strands
`map_position` and every act after the first reads as one step long), and walking
without simulating victories, which never opens the keep's road because
`is_lord_gate_open()` wants `holds_broken_in_act`.

**Pass 7 — C8, `tools/_probe_persistence.gd`.** All 61 `CreatureInstance` fields
survive `to_snapshot → apply_snapshot`; the 15 the REPLICATION snapshot omits are
each waived with a reason (position and ownership are viewer-relative; the five ATK
components are FOLDED into the sync's `effective_atk` and replicating the parts
would double-count them). Seeds reproduce, and different seeds differ. The field
set is enumerated from `get_property_list()`, so a field added tomorrow is covered
the day it is declared — which is the point: `effect_immune` was "the ONE field of
60 missing" and was found by hand. One harness trap: `row` is clamped to [0,1], so
a naive "default + 17" reports a CLAMP as a loss — bounded fields need legal values.

**Pass 4/5 — C2+C9, `tools/_probe_upgrade_merge.gd`.** `RunState._apply_plus_upgrade`
consumes a FIXED key set and silently drops anything else, so a declared-but-unmerged
key makes the forged card promise a number it cannot produce — Counterorders shipped
exactly that (`order_bonus` declared, never merged, "+" advertised 9 damage and dealt
6). All 235 UPGRADES entries declare only consumable keys, and every one of the 235
forged cards differs from its base. The consumed set is extracted from the merge's
OWN source, so the gate cannot drift from the code it guards.

**Pass 8 — C9, `tools/_probe_card_truth.gd`.** All 77 authored magnitudes across
474 card faces (base and "+") are stated in their card's own text. The value of
this pass is mostly in what it PROVED UNWORKABLE, measured rather than assumed:
"every integer in a desc exists in the data" scored 156/474 because 78 custom
spells keep their magnitudes in the RESOLVER, and "a keyword named in prose must
be in `keywords[]`" scored 138/474 because a card that GRANTS a keyword names it
without carrying it ("All friendlies gain Swift" is a spell, not a Swift spell).
Both were dropped. Catching the real Hoarfrost shape — prose saying "stunned"
where the code applies frozen — needs the text compared against the RESOLVER, and
that is not statically derivable, so **half of C9 stays a reading job**. The check
that survives is the inverse: where a magnitude IS authored in data, the text must
state it — the Camp Follower shape, precise and with no noise floor. One house rule
had to be encoded: a keyword tick equal to its own default is deliberately NOT
printed ("more if a number is shown"), so `rampage: 1` is correct and only a tick
ABOVE the default is checked — which is the Overrun shape that did lie.

## Two classes added from the literature (2026-08-29)

The first nine classes came from generalising bugs found by hand. Reading the
published work on test design added two more that the nine genuinely did not
cover — and both map onto defects this repo has actually shipped.

### C10 — METAMORPHIC RELATIONS (`tools/_probe_metamorphic.gd`)
Pass 8 hit a wall with a name: the **oracle problem**. Asserting a clash resolved
"correctly" needs a source of truth for the right answer, and for an engine this
deep that source is the engine. So Pass 8 could only check magnitudes that happened
to be written down in data, and everything the resolvers COMPUTE stayed untestable.

Metamorphic testing is the standard answer: rather than compare one run to a known
output, compare a RELATION between two related runs. The relation can be judged true
or false without anyone knowing what either run should have produced. The four
canonical shapes are symmetry, permutation, monotonicity and idempotence; three have
a natural reading here and all three hold:

- **MR1 symmetry** — a board and its MIRROR resolve identically. Any side-biased
  branch makes the same position resolve differently depending on who holds it.
  Checked over three fixtures (mutual kill, Thorns/Piercing trade, Armored + back
  row), each with a **vacuity check**: the un-normalised views must DIFFER, or the
  mirror was a no-op and the pass meant nothing.
- **MR2 idempotence** — applying one board snapshot twice equals applying it once.
  The client applies snapshots continuously, so a non-idempotent apply drifts the
  watcher's board further from the host's on every sync.
- **MR3 monotonicity** — more attack never removes less HP (measured 3 → 4 → 6).

### C11 — TEMPORAL / INTERRUPTION (`tools/_probe_interruption.gd`)
Lewis et al.'s game-bug taxonomy splits failures into NON-TEMPORAL (wrong answer,
missing feature, constraint violation — what C1–C9 already cover) and **TEMPORAL**,
where the timing or ORDER of events is what makes the behaviour wrong: *invalid
state*, *interrupted event*, *action not performed*.

That split is not academic here. **Three of this session's bugs are one shape each**:
the toss modal dereferencing a Combat freed under it (interrupted event); Sealed
Orders refusing every card because the phase had no active player (action not
performed); the Bo3 drill waiting forever on an answer that could not arrive
(invalid state). The 2026-08-07 audit had already named an
"await-during-live-button" class and found three more.

So interrupt deliberately instead of waiting to be unlucky: fire a committed action
twice in one frame (the double-click, which is exactly the shape of the four latch
bugs fixed across MainMenu / Collection / Credits / MapView); free the scene while a
coroutine is parked mid-clash; deliver peer-loss at three different phases and
require a single clean teardown. All pass, with **zero engine errors** — including
the harsh one.

Sources: Lewis, Whitehead & Wardrip-Fruin, *What Went Wrong: A Taxonomy of Video
Game Bugs* (FDG 2010); the metamorphic-testing literature on the oracle problem.

### C6 upgraded — BOUNDARY-VALUE ANALYSIS (`tools/_probe_boundary_ui.gd`)
`_probe_textfit` walks every screen and reports zero — but it builds each one in a
MIDDLING state, and middling states are exactly where UI does not break. All three
screen defects found by eye this session were at an EXTREME: the draft ledger at
MAXIMUM content, the relic picker on the LONGEST STRINGS, `HOST (LAN)` in
ISOLATION. So drive each screen to its limits and re-run the same mechanical check
there — no new detection logic, the novelty is entirely in the STATE.

It immediately found a **second** defect in the relic picker: the 440px viewport
cap is 3.4 entries, so a heavy relic bag cut the fourth one straight through the
middle — its NAME at the bottom of the viewport with its rules text below the fold,
which reads as a relic with no description. That is the same defect the 128px row
height had just been raised to fix, returning at a different item count. The cap is
now a whole number of entries, so the list can only ever cut BETWEEN them.

**THREE MEASUREMENT TRAPS, all of which produced convincing false failures first**
(132 hits, then 24, then 2, then 0 — every reduction was a fix to the PROBE):
- Parenting screens under an intermediate `Control` makes full-rect anchors resolve
  against the wrong rect: a label reported 3,222px wide on a 1,600px canvas. Add
  scenes to the tree ROOT, as `_probe_textfit` does.
- `get_content_height()` and `get_string_size()` are LOCAL units; `get_global_rect()`
  is SCALED. Comparing them reports everything under a scaled parent as clipped —
  the GameOver deck strip renders at 0.36 and "content 65 > box 24" was precisely
  that ratio.
- Content inside a `ScrollContainer` is SUPPOSED to sit outside the canvas. Judge
  the nearest clipping ancestor, not the leaf, or every long list reads as broken.

### C12 — MUTATION TESTING (`tools/run_mutation_check.sh`)
Every other class tests the GAME. This one tests the TESTS, and it is the only
pass that can tell a gate that defends something from a gate that merely passes.
Nine mutants, each re-creating a bug actually fixed this session, are injected into
production code; the gate that should notice is required to FAIL. Files are
byte-copied and the restore is checksum-verified.

**It found two fake gates on its first run.** `_probe_net_soak` stayed green with
`_is_sealed()` forced to `false` — the mode silently degraded to Alternating,
creatures still reached the board, every assertion held, and the soak was proving
"cards can be played" rather than "Sealed Orders ran". And `_probe_boundary_ui`
could not see its own founding defect, because content inside a `ScrollContainer`
is exempted from the off-canvas rule. Both are fixed; the score is 9/9.

The honest limit: a mutation score measures the gates against the faults CHOSEN,
and these were chosen from known bugs. It proves those regressions cannot return
silently — not that the suite catches everything.

### C13 — FUZZING THE TRUST BOUNDARY (`tools/_probe_fuzz_wire.gd`)
Every pass before this fed the game well-formed input. The wire is the one place
it accepts data it did not create, and a peer is not obliged to be friendly.

**It found a remote abort vector.** Every intent handler read peer fields with a
bare `int(...)`, which THROWS on a Dictionary or Array — "Nonexistent 'int'
constructor" — and a thrown call aborts the function where it stands. A client
sending `{"t": "play_creature", "lane": {}}` stopped a host-side handler
half-finished. `NetProtocol` cannot prevent this: the envelope contract is about
SHAPE, and `{"lane": {}}` is perfectly well-shaped. So the coercion itself was made
total — `_wire_int` / `_wire_str`, applied to all 44 peer-supplied reads on both
the host and client sides. 65 hostile intents now land with zero engine errors.

Three harness lessons, all of which made the fuzz look successful while testing
nothing: a thrown coercion aborts the CALLER too (the loop stopped after one intent
and still reported PASS); some intents legitimately end the match, so the host must
be re-booted mid-fuzz; and unbiased generation put only one envelope in eight on
the path under test. Assert the SAMPLE SIZE, or a fuzz of six reads as a fuzz.

### C14 — CONTINUOUS INVARIANTS (`tools/_probe_invariants.gd`)
Every pass before this inspects a QUIESCENT state: the board before a clash, the
run after a verdict, a screen that has finished laying out. That is a real blind
spot — plenty of defects exist only in transit, and the game tidies up before any
end-state assertion looks. Those are exactly the states a player can click into.

So a set of always-true properties is asserted on EVERY FRAME of a driven match:
one body per slot, bodies agreeing with the slot holding them, no dead body
standing outside the deferred-death window, no freed node in the entity registry,
no id registered twice, Command never negative, the hand never over cap, no
duplicate uid in hand.

**It found a real defect on its first sound run.** `Combat.gd` never called
`unregister_entity` ANYWHERE — the only three calls in the codebase are client-side
or in two specific spell resolvers — so every creature that died on the host stayed
in `NetMatch.entities` for the rest of the match, pointing at a freed node. Stale
entries were present on 26,033 frames of a single match. No end-state check could
ever see it: the registry is cleared wholesale at `_enter_combat_local`, so it looks
clean the moment anything settles.

**THE FIRST RUN WAS A FALSE PASS, and the cause is worth remembering.** Naming
`Card2D` at parse time in a `--script` probe drags Card2D.gd into the compile that
happens BEFORE autoloads register; its own autoload references fail, the script does
not compile, and `card_2d.tscn` instantiates as a bare `PanelContainer`. The match
still runs — badly — and the audit reported ALL PASS over a build where no card had
its script. The tell was two error classes the soaks never produce ("Nonexistent
function 'reset_clash_pitch' in base 'GDScript'" and "Invalid assignment of property
'card_id' … on a base object of type 'PanelContainer'"). Load such classes at
RUNTIME. Same family as the `preload`-the-autoload trap already recorded in CLAUDE.md.

### C15 — RESOURCE LIFECYCLE (`tools/_probe_leaks.gd`)
Every other class asks whether the game computes the right answer. This one asks
whether it gives back what it takes. A leak never fails an assertion — the game
stays correct, it just gets heavier — and the only symptom is a session that
degrades the longer it runs, which is the shape of "it gets choppy after a while".

The honest measurement is a SLOPE, not a count: build and tear down the same scene
many times and see whether the object count keeps climbing. Legitimate caches fill
on the first cycles and stop, so a warm-up is discarded and only the tail is judged.

Result: **reward and skirmish combat are EXACTLY flat** (0.0 objects/cycle, 0
orphans) — which both proves the instrument works and clears two big scenes.
**The shop climbs ~23 objects per open and does not plateau over 14 cycles.** A
cache bounded by the ~130-card pool would have flattened well before that. Orphans
stay at zero throughout, so the retained objects are Resources/RefCounted, not lost
Nodes. **OPEN LEAD** — measured and reproducible, owner not yet identified; the
severity is low (a run visits few shops) but the growth is unbounded.

Three harness traps, each of which hung the probe outright rather than failing:
cycling `event.tscn` picks a RANDOM event and one with a modal auto-effect waits
forever for a click; these screens read `RunState` in `_ready` and stall without a
seeded run; and freeing the tree's `current_scene` leaves it in a state where the
next frame never completes. A probe that can hang needs a WATCHDOG — this one has
one, because a silent hang teaches nothing and hides its own failure.

### C16 - COMBINATORIAL COVERAGE (`tools/_probe_pairwise.gd`)

Every pass before this varies **one thing at a time**: the soak fixes a config and
varies the seed; the relic-parity gate walks the relic pool with everything else
held still. That is blind by construction to defects which exist only where two
features MEET - Sealed Orders plus a hand-size relic, a Best-of-3 plus the
going-second Coin, a board relic plus the bot's spell path.

The full cross product of {style, first, best_of, relic, potion} is 280 matches.
Most interaction faults involve just TWO factors, so the pass builds an **all-pairs
covering array**: 35 combinations in which every pair of values from every pair of
parameters appears at least once - 119 pairs, all covered, verified BEFORE the
matches run so the pass cannot claim coverage it does not have.

**Phase A** plays all 35 and watches structural invariants. It found nothing, which
is a weak result on its own - "nothing crashed" is a low bar, and a relic that
silently does nothing under one battle style passes every structural check ever
written, because a relic doing nothing is a perfectly valid board.

**Phase B is therefore the real pass**: a (relic x style) CELL MATRIX. Measure the
opening a relic is supposed to move - max Command, opening hand - once per cell,
and require the relic's DELTA FROM THE NO-RELIC BASELINE to be the same in both
styles. Nothing is hardcoded about what any relic ought to do; the relation is that
the two styles must agree, which survives any future retune. A vacuity guard
requires the matrix to observe at least one real effect first (4 relics move the
opening today) - a matrix in which nothing moved would satisfy the relation while
proving nothing.

### C17 - TWO PROCESSES, ONE SOCKET (`tools/run_two_process_match.sh`)

**The infrastructure gap this document has listed as Pass 9 since it was written.**
Every net probe in the suite runs host and client in ONE process, where the "wire"
is a function call and a Dictionary handed across is THE SAME OBJECT. Three classes
of defect are invisible under that arrangement:

1. **Serialisation.** In-process a payload never encodes. Over a socket it is
   encoded, sized, validated by NetProtocol and decoded again. The soak MEASURED
   the clash reel at 81 entries against a 256 cap - but measuring a number is not
   watching the envelope validate. An over-cap reel is not truncated, it is
   REJECTED WHOLE, and the watching peer's screen cuts to the outcome with no
   fight in between.
2. **Real ordering and timing.** Events arrive on their own frames, interleaved
   with the receiving peer's animation, rather than synchronously mid-call.
3. **The real handshake.** `is_connected_to_peer()` has three terms and every
   single-process probe sets all three by hand. Here they are earned.

The proof is a **cross-process digest diff**: each side writes what it believes the
match was - hero HP, board by entity id, rejections - and the driver diffs them.
Two processes that played the same match must agree about it; a desync is then a
difference nobody had to anticipate in advance.

Three harness defects had to be fixed before it measured anything, each worth
keeping:

- **The watcher must not be `current_scene`.** The real match path ends in
  `change_scene_to_file`, which frees the current scene - so the driver silently
  died the instant the match it was driving began. Reparenting does not fix it (as
  the main scene it is already on root); it has to hand the work to a second node
  living beside `current_scene`.
- **Stop on a SHARED clock.** Counting local turns made the peers stop at different
  moments, and whichever finished first tore the socket down, freezing the other
  mid-match - which then showed up as a "board desync" that was nothing but two
  snapshots of different instants.
- **A sealed stand-in is not a desync.** `_sealed_pending` holds local previews
  carrying `entity_id == -1` until the reveal. The first full run reported two of
  them as client-only bodies; they were legitimate. The digest now distinguishes a
  TRACKED stand-in from an ORPHANED one - an untracked `-1` body is a real defect,
  because the host addresses every net beat by entity id and could never reach it.

Verified non-vacuous by mutant: shrinking `MAX_ARRAY_ITEMS` 256 -> 4 makes the reel
overrun its envelope, and the gate catches it decisively - the host believing the
client is at 6 HP while the client believes it is at 30. Every other net gate stays
green through that mutant.

### C18 - THE SILENT REFUSAL (`tools/_probe_silent_refusal.gd`)

**The class that is correct code and a bug anyway.** Every other pass asks whether
the game does the right thing; this asks whether the player can TELL. A control
that declines an action and says nothing - no message, no sound, no recoil - is
behaving exactly as designed while the player looks at a dead button. There is no
state to assert against, which is why nothing else here catches one, and yet the
two worst skirmish bugs of this sweep were both this shape.

The technique is **feedback asymmetry**, deliberately not "find every bare return"
(that is nearly all false positives, and this session has already deleted three
checks for crying wolf). Consider only functions that demonstrably KNOW HOW TO
SPEAK - an input handler with at least one refusal that does tell the player. A
silent sibling branch in that same function is then an inconsistency worth
adjudicating, exactly as C3 reads a predicate applied in one sibling and forgotten
in another.

Two refinements were needed to get from 23 noisy hits to a real list: a branch that
CALLS something is not a silent refusal (a dispatch, or feedback the vocabulary had
not learned - `_cancel_targeting`, `_return_card_to_slot`, both of which visibly do
something); and waivers are keyed `function::guard-needle` so one cannot spread to
a different site sharing a variable name.

Found and fixed:

- **The same rule spoken on one input and silent on another.** Dragging a card in a
  sealed match answers "Orders are sealed - waiting for your opponent."; right-
  clicking that same card to mark it for discard returned in silence. Same rule,
  same card, two inputs - one explained itself, one read as a dead control. Both
  net branches now use the play gate's exact wording, because a player meeting one
  rule twice should hear one sentence.
- **The potion belt is never disabled**, so clicking a bottle mid-clash was a dead
  button - the same defect that function's own comment was added to fix, one guard
  higher up.
- **Sniper aim** explained itself in Sealed and snapped back mutely in Alternating.

Adjudicated and waived with reasons: re-entrancy and animation latches (a die
mid-tumble is not ignoring you - the tumble is the answer), branches unreachable
because their control is disabled, internal bounds/null guards, and a targeting
miss (which keeps the mode open, exactly as the spell path does). One waiver is a
**standing trap**: the combat belt draws whatever the slot holds without filtering
on `usable_in`, so the first `usable_in: "map"` potion added to PotionDB would
render a lit, clickable, completely dead slot.

### C19 - THE SUSPENDED-FUNCTION HAZARD (`tools/_probe_await_audit.gd`)

`await` suspends a function mid-body and lets the rest of the game run, so every
node reference it was holding may be GONE when it resumes. In Godot this does not
crash loudly: a freed-object read returns null and a null write silently ABORTS the
function, so the symptom is an animation that stops halfway with no error printed.
That is why the class survives - it produces missing beats, not stack traces.

There are 594 `await`s under `scripts/`, so it cannot be an eyeball pass. C11
EXERCISES a handful of interruption points dynamically, which proves those and says
nothing about the other five hundred; this is the exhaustive static complement. For
each function containing `await`, every node-typed local and parameter is tracked,
and a dereference after a suspension with no intervening validity check is reported.

Getting from 27 noisy hits to 8 real ones took two fixes to the PROBE, both worth
keeping because both are properties of the language rather than of this codebase:

- **A multi-line `await` is ONE statement.** Its arguments are evaluated BEFORE the
  suspension, so a mention on a continuation line is a pre-await use. Missing this
  reported `_ordered_strike` - which guards correctly on the very next line.
- **An `await` nested in a branch does not dominate code at a shallower indent.**
  `_sniper_fire`'s await sits in an `if` that returns immediately after, so the
  lines flagged "after" it are on a different path entirely. Dropping the await when
  the indent falls below it is deliberately conservative and costs some true
  positives; a gate with false positives gets ignored, one that reports only what it
  can prove gets acted on.

Fixed: **the coin toss on both peers**. `layer` is a child of the combat scene and
the toss is a multi-second suspension, so a peer dropping mid-toss frees the layer
(peer-loss arms a scene change two seconds out) and every line after the await
operates on a freed object - leaving the toss winner staring at a coin with no
choice buttons and no error anywhere. The abort ANSWER follows the convention an
earlier fix already established for the same function's wait loop. Also fixed: three
suspensions in `Event._play_coin_call`, where the author had already guarded `coin`
inside a tween callback - the risk was understood, just not covered where the tween
is created.

Waived with reasons, the recurring one being GUARD-BY-OWNER: code that validates the
container a node hangs off rather than the node itself. That is sound, and inferring
the ownership statically is not reliable enough to automate.

Verified non-vacuous by mutant: removing the coin-toss guard is caught.

### C20 - CONTENT NOBODY CAN REACH (`tools/_probe_content_census.gd`)

C1 answers a STATIC question - is this id dispatched, is this emitter wired - which
is how it caught six dead minigames. It cannot answer the EMPIRICAL one: content can
be perfectly wired and still never appear, because the roll that would produce it is
gated by an act, a rarity band, a deck predicate or a pool filter that never lets it
through. Authored content nobody sees is work paid for and never delivered, and it
is invisible to every other gate because nothing is broken.

So: roll the SHIPPED generators tens of thousands of times across every context they
take, and tally what actually comes out. Deliberately empirical - re-deriving each
roll's conditions in the probe would be re-implementing the generator, and a
re-implementation only ever tests itself.

Result after the corrections below: cards 193/193, relics 70/70 + 9/9 + 6/6,
encounters 48/48, potions 12/14 with both absentees PROVEN reachable.

**THREE OF ITS OWN BUGS ARE THE LESSON, and every one produced a confident, wrong
report** - which is precisely the failure mode a census must not have:

1. `roll_card_reward` and `roll_relic_reward` return an Array[String] SLATE, not one
   id. Read as a string, 12,000 rolls produced nothing and the pass announced that
   193 cards were unreachable. The summary line's roll COUNT is what exposed it, so
   the probe now refuses to report a "never appeared" list when its generator
   produced zero output - a vacuous census must say so, not accuse.
2. Encounter types are `combat`/`elite`/`boss`; an early draft queried `"normal"`.
   Because the ELIGIBLE set was built from the SAME wrong query, the census reported
   "all 18 eligible appeared" and PASSED. A check whose expectation and observation
   share a bug agrees with itself perfectly; only the count (18 against 55 authored
   lineups) gave it away.
3. Rolling relics with an empty `hero_id` - which no real run has - made
   `filter_pool_for_run` drop every `restricted_to` relic and report 32 reachable
   ones as dead. It now rolls per hero and unions, and excludes `retired`, which is
   an authorial decision rather than a defect.

**A GATE IS ONLY CORRECT IF IT CAN OPEN.** The two archetype potions never roll here
because `_roll_allowed` asks for a deck this probe does not have - but "deck-gated"
and "dead content" produce the identical observation, and assuming the benign reading
is exactly the mistake this class exists to prevent. So the pass builds the deck each
gate asks for and proves the potion becomes rollable (261 and 266 hits per 4,000).
The house rule is NO DEAD REWARDS, and it is only kept if the gated reward is
reachable by some real deck.

### C21 - CHAOS / FAULT INJECTION (`tools/run_chaos_save.sh`)

Mutation testing breaks the PROGRAM. Fuzzing feeds a hostile PAYLOAD. Neither
touches the third thing that fails in the real world and never fails in a test: the
machine underneath. A save truncated by a power cut mid-write, JSON whose numbers
arrived as strings, a file written by an older build with half its keys missing.

This is the class the player experiences as **"my run is gone"**, which is the worst
bug a roguelike can ship, and nothing here had ever pointed at it. C8 round-trips
WELL-FORMED saves and proves the fields survive; it never asks what happens when the
file is wrong.

Fourteen corruptions x three save files (run, meta, settings), plus backup recovery.
The contract, in order of how much it matters: never crash; never silently destroy a
good save; and fail HONESTLY - `load_run()` returning true on a file it could not
read is worse than returning false, because the game then proceeds on an empty run.

**Result: the save system is genuinely solid.** All 42 corruptions handled, the
backup fallback recovers the real save (gold 777, not a blank run), and with both
copies wrecked the loader reports failure rather than pretending. Verified
non-vacuous by mutant: removing the backup fallback in `RunState` makes the corrupt-
primary case load a BLANK run, and the gate names the consequence exactly
(`gold=0, expected 777`).

Safety: the pass writes garbage into `user://`, so the driver relocates APPDATA to a
temp dir first (GODOT_USER_HOME is a no-op on Windows) and the probe REFUSES to run
without that isolation rather than eat real saves.

**Three of its own bugs were harness bugs, and all three produced the same wrong
answer** - 14 of 14 corruptions reported as "left unusable state". A uniform failure
across every case is almost always a broken oracle rather than N distinct bugs:
the predicate named `player_hp` (the field is `hero_hp`); it compared a typed
`Array[String]` against `null`, which is an invalid operand that ABORTS the lambda
rather than returning false; and the lambdas were written inline inside a multi-line
argument list, where they parse unreliably - binding each to a local first fixed it.
A fourth was mine, not the code's: three `python replace` edits printed "ok" without
verifying they had matched anything, and none of them had.

### C22 - SPECIFICATION MINING (`tools/_probe_invariant_mining.gd`)

Every assertion in this suite is one a human wrote, so the suite can only check
properties someone already thought of. C14 is the clearest case: five hand-picked
properties watched every frame, blind to the hundreds nobody enumerated. That is the
ceiling of hand-authored testing, and Daikon-style dynamic invariant detection is
the published answer - run the program, record values, MINE the properties that
always held.

Two phases, because a mined invariant alone is worthless (everything observed once
is trivially "always" true):

- **LEARN** across one set of seeds and battle styles: bounds per field, and
  pairwise `<=` RELATIONS between fields, which are the ones with content.
- **TEST** against unseen seeds and the other style. A break is one of exactly two
  things and both want a human: an OVERFIT (the learn set was too narrow) or a real
  rule that phase 2 violated.

The report separates them, because lumping them together is what makes a mined-
invariant dump unreadable: a RANGE widening is the expected cost of a finite sample;
a RELATION breaking was a structural claim that turned out to be a coincidence.
Surviving relations are then ranked by INFORMATION - a relation is only interesting
when the two fields' observed ranges OVERLAP, since `hand_size <= player_hp` is
arithmetic (2..5 against 15..30), not a rule.

First run: 72 samples, 11 fields, 25 mined relations, 24 surviving unseen input,
8 of them informative. The standout is **`bodies_foe <= entities`** - every enemy
body must be in the entity registry - which is precisely the invariant whose
violation C14 caught earlier in this sweep (`Combat.gd` never called
`unregister_entity`). The miner rediscovered it from traces alone, with nobody
having told it that was a rule, which is the clearest evidence the technique carries
its weight.

### C23 - RELATIONAL DESIGN ANALYSIS (`tools/_probe_dominance.gd`)

Twenty-two classes and not one compares two pieces of content TO EACH OTHER. Every
gate asks "is this card well-formed / reachable / correctly merged"; none asks "is
this card worth playing GIVEN the one next to it". A strictly dominated card is dead
by a route no reachability census can see: it rolls, it appears in the slate, and
the player correctly never picks it. C20 counts it as reachable.

Two halves. **Dominance** uses the rarity curve as its oracle (a rarer card beating
a commoner one is the curve working; same-rarity dominance is a dead pick; a
commoner beating a rarer one is the curve INVERTED). **Every "+" forge must be
strictly better than its base** - which C2/C9 cannot see, because that pass proves
the delta keys are CONSUMED, never that the result improves.

**RESULT: ZERO defects. Both halves are clean, and both are verified non-vacuous by
mutant** (retyping War Boar to `dead` makes it dominate Grave Soldier; a `{"hp": -2}`
upgrade trips the strictly-worse gate).

**The real value of this pass is the record of how wrong it was first**, because
every false positive was a fact about the codebase worth writing down. It went
1,077 -> 12 -> 16 -> 3 -> 4 -> 0 across five corrections:

1. Comparing abilities by KEY made every spell comparable to every other spell -
   they all carry a `spell` key and 0/0 stats, so the cheapest appeared to dominate
   the whole pool. Abilities must match by PAYLOAD.
2. `armament` was missing from the ability list, so two armaments with completely
   different effects compared as though neither had one.
3. A forged bonus is driven from FOUR places, not one: a merged delta, an
   `is_upgraded` read in the resolver (`_apply_armament` grants hooked_pike +1 ATK,
   tower_shield +2 HP, grave_bell/witchbrand +1/+1, forked_spear +2 ATK,
   repeating_arbalest +2 HP), a local `is_plus` in a custom-spell resolver
   (`long_roll` pays 7/16 forged against 5/12 base entirely that way), and a
   resolver keyed on `spell.id` rather than the card id (Lock Shields resolves
   under "testudo", Countermarch under "baggage_train"). A check knowing only the
   first accuses the other three.
4. Extra keywords are not automatically upside: **Doom is a death timer**, so Live
   Coal (4/3 Swift + Doom 2) does not dominate Hired Blade (3/3 Swift) - it pays
   for its size.
5. **Tribe is not cosmetic.** Six tribes have payoff keystones, so a Dead 2/2 and a
   Beast 4/2 at the same cost are not substitutes.

### C24 - EMERGENT INTERACTION, OBJECTIVELY ORACLED (`tools/_probe_runaway.gd`)

Design and balance are out of reach, but "emergent" does not have to mean "a matter
of taste". Two things are bugs by any standard, need no balance judgement, and are
reachable only by actually playing: **runaway values** (a stat driven without bound
is an unbounded combo, whatever the design intent) and **non-termination** (a match
that cannot end is a softlock - the soak drives matches but stops at a turn cap and
never asks whether the fight was going to finish).

What separates it from every earlier soak is DECK DIVERSITY. The soak and the
pairwise pass hand both players the same twenty cards, so they can only ever produce
the interactions inside that fixed list. This rolls RANDOM legal decks from the whole
skirmish pool - 145 distinct cards across 10 matches - so cards that have never
shared a board get to meet, which is the entire point.

Result: clean. No runaway value, every match reached a verdict inside 40 rounds.

**Two lessons from its own construction, both about oracles:**

1. **A corpse below zero HP is legitimate mid-clash.** `Card2D.defer_deaths` holds
   dead bodies standing so a simultaneous trade resolves both ways before anything
   is swept. Sampling inside that window reported nine healthy matches as broken.
   `_probe_invariants` guards the same way.
2. **An "absurdly large number" ceiling is the WRONG oracle for unboundedness.**
   Forcing Command to accumulate every round only reached 18 before matches ended,
   so a ceiling of 25 stayed green while the resource was genuinely unbounded. The
   fix is to derive the bound from the CONTRACT - `_start_round` sets
   `player_mana = player_max_mana + banked` with banked capped at MAX_BANKED_MANA,
   so anything above that sum is a violation on the FIRST round it happens,
   whatever the absolute number. The mutant is now caught at Command 6.

### C25 - CHARACTERIZATION / GOLDEN MASTER (`tools/_probe_golden.gd`)

Every gate here encodes a property somebody chose. None answers the question that
actually matters when editing a 20,000-line combat file: **did this change alter
anything I did not intend?** Approval testing is the standard answer for exactly
this shape of codebase - no unit tests, one enormous module, a hundred behaviours
nobody wrote down. Record what the game DOES over fixed seeds, commit it
(`tools/golden/combat_digests.json`), and let any future diff be the alarm.
Re-record deliberately with `-- --bless`.

It certifies nothing about correctness. That is the trade: it costs nothing to
record and catches unintended change anywhere in the covered surface.

**It proved something no pass had checked: a whole MATCH is deterministic.**
`CombatOps` owns seeded gameplay randomness so a match is reproducible, and C8
covers run GENERATION only. Same seed, twice, both battle styles, and across
separate processes - identical digests every time. A divergence would have meant
some gameplay decision was reading unseeded global RNG.

**THE LESSON IS ABOUT COVERAGE, and it came from a mutant that ESCAPED.** Halving
`MAX_BANKED_MANA` changed no digest at all, because the driver spent its Command
every turn and nothing ever banked - the constant was never load-bearing in any
scenario. A card-stat mutant fired both scenarios immediately, so the digest was
sensitive; the corpus was simply narrow. Adding a FRUGAL scenario (deliberately
underspending so Command carries over, `mana=5/3`) made the banking mutant fire.
**A golden master only pins the behaviour its scenarios exercise, and a corpus with
narrow scenarios is worse than none, because it reads as coverage.**

### C26 - COVERAGE-GUIDED: what does the SUITE reach? (`tools/_probe_coverage.gd`)

Twenty-five classes all ask a question about the game. This one asks a question
about the suite: **which behaviours has any of it ever actually executed?**

That stopped being academic in C25, where a mutant halving MAX_BANKED_MANA escaped
the golden corpus - not because the digest was insensitive but because no scenario
ever banked, so the constant was never load-bearing in anything measured. Every gate
is vacuous over code it never runs, and nothing said which code that is. The
automated-playtesting literature converges on the same instrument: measure coverage,
then aim the testing at what is uncovered.

GDScript ships no line-coverage tool, so this measures BEHAVIOURAL coverage - which
for a card game is the more useful axis, since the dispatch surface IS the content.
It plays random decks and records what actually resolved, then diffs against what
the DBs define.

Measured over 14 random-deck matches: skirmish cards 114/153 (75%), spell effect
types 39/52 (75%), on-enter 15/21, on-death 8/10, keywords 19/22. Plus **29 further
spell effect types that are campaign-only and outside this driver's reach entirely.**

**READ THE SCOPE, and the probe says so itself.** This is the reach of ONE driver
over 14 matches, not of the whole suite: a card absent here may simply not have been
drawn, and `_probe_autorun` soaks campaign combat so some campaign-only resolvers
are likely covered there. The honest claim is a FLOOR, not a verdict - an effect
type no random-deck match ever triggered is surface the other gates have nothing to
say about. Overclaiming here ("nothing in the repository executes them") was the
first draft and was wrong.

**Its own bug was the denominator, for the third time in this sweep.** Building the
universe from the whole CARD_POOL counted hero-retinue `starter_*` customs -
`draftable: false`, in no skirmish deck - as blind spots of a skirmish driver,
reporting 48% where the scope-matched number is 75%. The encounter census made the
same class of mistake in the other direction. **A coverage number whose denominator
does not match what the driver can reach is not a measurement.**

The obvious next build is a campaign-side twin, which would make the 29 answerable.

## Two classes aimed at what the player SEES (2026-09-02)

Twenty-six classes and the great majority of them reason about STATE. But most of
what a player experiences is pixels, and two whole categories of pixel defect had
no gate at all. Both classes below come from the automated-GUI-testing literature
rather than from generalising a found bug, and both are deliberately RELATIONAL or
GEOMETRIC so that neither needs to know what a screen is supposed to say.

### C27 - CONFIGURATION-DIFFERENTIAL (`tools/_probe_settings_differential.gd`)

Every gate before this one runs the game in ONE configuration: the default. The
player can change it, and a setting that silently removes CONTENT is a defect they
meet immediately and cannot diagnose - they turned on an accessibility option and
a panel stopped existing. This is the variability-aware class from the
software-product-line testing literature, and its oracle is relational like C10's:
the settings in this game are declared presentation-only, so two configurations
must AGREE about what is legible once a screen has settled.

Each screen is built three times - baseline, Reduce Motion, screen-shake off - and
the diff is over the TEXT MULTISET PLUS ITS EFFECTIVE LEGIBILITY. Legibility is
the half that matters: a node left at `modulate.a = 0` by an entrance that never
ran is still in the tree, still `visible_in_tree`, and still reports its text.

**Result: 64 screen states x 3 configurations, all agree.** The Reduce Motion
contract holds across 160 hand-written gates. That is a negative result and it
only means something because the gate is mutation-verified: moving `write_on`'s
`visible_ratio = 0.0` to the wrong side of its own guard - the exact "hidden
pre-state never restored" shape - is caught on every event screen.

**Its own first bug was the oracle, and it was blind to the defect it was built
for.** `visible_ratio` was not in the fingerprint. The typewriter reveals prose by
tweening `visible_ratio` 0 -> 1 and returns early under Reduce Motion; a label
parked at 0 draws not one glyph and still reports its full `text` at full alpha.
**Legibility is not alpha alone.**

### C28 - OCCLUSION: TEXT THE PLAYER CANNOT READ (`tools/_probe_occlusion.gd`)

`_probe_textfit` checks text against its own box and the canvas edge; C6's
boundary probe drives screens to their extremes and re-asks the same question.
Both judge each control ALONE. Neither can see the defect where every control is
perfectly placed and one is drawn ON TOP OF another - the category the GUI-glitch
literature (OwlEyes / Nighthawk / AG3) leads with, and the one a player notices
instantly because a sentence is simply not there. It has happened here before: the
veterancy rung modals sat at canvas layer 0 under a HUD on 12, and CLAUDE.md
carries a layout budget in prose ("a 5th choice overlaps the description") that
nothing enforces.

Three geometric oracles: **A** a worded control buried under something opaque that
paints later (canvas layer, then z_index, then tree order - a CanvasLayer
overrides both); **B** two sentences sharing pixels; **C** an authored text box
reaching under an always-on HUD, which separates a screen that is BROKEN from one
that is merely ARMED for the next slightly-longer string.

**It found a live one** - see the log entry below.

**MEASURE THE INK, NOT THE BOX.** Three false positives in a row, each from
judging a rectangle instead of the glyphs inside it: a full-width centred boss
banner "overlapped" every HUD chip on its row; an autowrapping title was assumed
to fill its column when a short string paints one line and still obeys its
alignment; and a RichTextLabel was measured at `size.x` when `get_content_width()`
is the ink. A box-based version of this probe is a noise generator.

**A CEREMONY IS NOT AN OCCLUSION.** The boss-intro banner is a full-width plate
deliberately laid over the board, so a scan taken while it is still up reports the
lane numerals beneath it as buried. Wait the ceremony out; an overlay still there
afterwards is the finding.

**And its own worst bug: a filter deleted the evidence.** Oracle C measured the
HUD's extent from the same worded-control list the rest of the probe uses - which
drops anything under three characters. The label at the centre of the real bug
reads `11`. With that row missing, the ledger's band appeared to stop 10px above
the prose and the check concluded the two could never meet: it printed NOTHING
BURIED for a screen that had already been PHOTOGRAPHED with the HUD spliced into
the middle of a sentence. **A convenience filter on the sample is a filter on the
evidence.**

### Found by C28: the stakes ledger printed inside an event's prose

On the `character` event stage the description column is authored at
`Rect2(1000, 146, 520, 190)` while the stakes ledger is anchored TOP_RIGHT across
x 1370..1560 and is FOUR rows deep (y 40..176). The fourth row - the deck count -
hangs exactly level with the column's first line, so `the_siege_kitchen` rendered
as "...abandoned a field kitchen, but 11 [deck icon]", with a HUD readout sitting
mid-sentence where a reader takes it for part of the prose.

The arithmetic says how it happened: `40 + 3 rows x 34 = 142`, and the column's
prose used to start at 146. **The stage was authored against a THREE-row ledger,
and the fourth row was added later, in a different file, with nothing comparing
the two.** Both the choice page and the result page restate these rects
independently, so both were wrong and both needed the fix.

### C29 - INPUT REACHABILITY: can the player actually click it? (`tools/_probe_input_reach.gd`)

C18 covers a control that DECLINES without saying so. This is the class beneath
it: a control that never hears the click at all. The player's report is identical
and is the most common bug report in existence - "the button doesn't work" - but
nothing in the tree is wrong. The button is visible, enabled, correctly wired, and
its `pressed` never fires because something invisible stands in front of it.

Godot makes this easy to ship: `mouse_filter` defaults to STOP, so a transparent
full-screen overlay left in the tree swallows every click beneath it while drawing
nothing at all. No visual symptom to photograph, no error to log.

**The oracle is Godot's own picking rule**, re-implemented and run at each
control's own centre: order by (canvas layer, z_index, tree order), IGNORE is
transparent to input, STOP consumes it. If the winner is not the button or
something inside it, the button is dead. **466 clickable controls across 91 screen
states are all reachable** - including after the pile-viewer and glossary CLOSE
paths, which is the leak this was built to find.

**A MODAL IS ALLOWED TO EAT INPUT; A LEAKED CATCHER IS NOT**, and telling those
apart is the whole design. Judging naively reported seven dead controls in the
open pile viewer - END TURN, LOG, the gear - every one of them correct behaviour.
The distinction that works: a full-screen catcher which shares its canvas layer
with live interactive or worded content is doing its job; **a curtain standing
alone is a leak**. Mutation-verified both ways - a `_close_pile_viewer` that tears
down its contents but leaves the catcher is named directly, with all seven
controls it kills enumerated.

It also carries a **static guard for the `flat` contradiction** that produced the
two dead scrims below: `Button.flat = true` beside a coloured stylebox override.
`StyleBoxEmpty` is the legitimate pairing (30 of the 32 sites); a coloured box is
the bug. Source-level, so it covers every screen rather than only the ones a
harness drives.

A companion static sweep for two more self-cancelling pairs - a control set to
MOUSE_FILTER_IGNORE yet wired to a click signal, and `self_modulate` on a
Container (which draws nothing) - found **zero**, over 679 IGNORE assignments and
311 container declarations. Verified non-vacuous by loosening the signal list,
which fires 9 times, all of them legitimate `draw`/`resized` connects on
decorative painters.

### Found by C28, second pass: two modal scrims that never painted a pixel

Combat's pile viewer and glossary both build their full-screen backdrop as

```gdscript
var backdrop := Button.new()
backdrop.flat = true
var dim := StyleBoxFlat.new()
dim.bg_color = Color(0, 0, 0, 0.7)
backdrop.add_theme_stylebox_override("normal", dim)
```

Those two lines contradict each other. **A flat Button does not draw its stylebox
at all** - that is what `flat` means - so both dims were built, themed onto three
states, and never painted. Opening your discard pile mid-fight laid a grid of
cards over a *fully lit* battlefield, HUD and hand at full brightness, with the
viewer's title printed across the HUD's phase caption.

**Only pixels could find this.** The scrim node is present, reports
`visible = true`, and carries a 0.7-alpha stylebox, so every tree-walking check in
this repository agrees the screen is dimmed. `tools/_probe_modal_scrim.tscn`
samples board luminance with the modal shut and open: **the glossary measured 0%
darker.** After the fix the two measure 71% and 56% - exactly their declared
alphas. An occluder that does not paint is not an occluder, and the defect is
that it *fails* to occlude, which is why C28's geometric oracles cleared these
screens.

A whole-codebase scan for the same contradiction found 32 `flat = true` sites, and
**30 of them override with `StyleBoxEmpty`** - deliberately invisible, `flat`
merely redundant. Exactly the two scrims were real.

### Found by C28, second pass: the hover inspector, buried under the modal holding the card

`Card2D` parents its hover detail popup to a shared CanvasLayer, and the comment
there states the trade deliberately: layer 90, "above the HUD (12) and
frame-grade (40) but BELOW the modal pile / glossary viewers (100)".

That reasoning holds for a card on the board and stops holding the moment **a
layer-100 modal is itself full of cards** - and the pile viewer is a six-column
grid of real `Card2D` instances. `_on_mouse_entered` carries no `static_display`
guard, so those cards hover, lift, gild, and raise an inspector *ten layers
beneath the viewer that owns the card being pointed at*. The player asks what a
card in their discard pile does and gets a lift with no rules text.

Raised to 110. Above is the correct side: a modal's full-screen backdrop eats the
mouse, so while one is open the only card that CAN be hovered is a card inside it,
and a popup that exists at all belongs on top.

**The two defects hid each other.** With the scrim silently dead, the buried popup
was still legible wherever it happened to miss a card - so the layering fault
looked cosmetic and intermittent. Repairing the scrim is what would have made it a
black curtain over the inspector. **Two bugs in the same feature can each mask the
other's symptom; fixing one alone can look like causing the other.**

### Found while building C27: a driver that seated nothing

`_probe_textfit._audit_event` set `_event_id` after `add_child` and then called
`_show_event()` / `_build_event()` behind a `has_method` chain. **Neither method
exists on Event.gd**, so the chain fell through in silence and every iteration
scanned whatever `_pick_event()` had rolled. Asking for 14 distinct events
produced 9 distinct screens, none of them the one requested: the pool's per-event
text had never been measured, only the label said so. Fixed to
`_probe_boundary_ui`'s working recipe (`_clear_ui` -> seat -> `_build_ui`), plus a
self-check that fails if the event's own name is not on the screen it just built.
With the driver actually seating, all 46 rooms measure clean.

**A silent no-op is the worst failure mode a harness has**, because it reports
PASS in the voice of a test that ran. Any `has_method` fallback chain in a probe
is one rename away from becoming this.

## Execution order (yield ÷ cost, highest first)

| Pass | Class | Why here |
|---|---|---|
| 1 | C1 | Fully mechanical, whole codebase, minutes to run. Historically the highest-yield class in this repo. |
| 2 | C3 | Semi-mechanical; three hits this session already. |
| 3 | C7 + C5 | The campaign has **no soak at all** — the single largest untested surface in the project. |
| 4 | C2 | Needs a parity probe per twin; one exists, the rest do not. |
| 5 | C4 | Cheap once the declared constants are inventoried. |
| 6 | C6 | 21 scenes to shoot and read. |
| 7 | C8 | Save round-trip + seed reproduction. |
| 8 | C9 | Most expensive per bug; do it when the mechanical classes are exhausted. |
| 9 | C17 | **BUILT.** Two processes, one socket - the gap is closed. |
| 10 | C16 | All-pairs covering array; the (relic x style) matrix is the part with teeth. |
| 11 | C18 | Static, seconds to run, aimed straight at "looks like a bug to the player". |
| 12 | C19 | Static, exhaustive over 594 awaits; found a real peer-drop hazard. |
| 13 | C20 | Empirical content census; its own three bugs are the cautionary tale. |
| 14 | C21 | Corrupt-save chaos. Cheap, and aimed at the worst bug a roguelike ships. |
| 15 | C22 | Mines rules nobody wrote down; rediscovered a real one unaided. |
| 16 | C23 | Found nothing. Its false positives are the useful output - see above. |
| 17 | C24 | Random decks played to a verdict; contract-derived bounds, not ceilings. |
| 18 | C25 | Standing regression net. Proved match determinism; watch its coverage. |
| 19 | C26 | Measures the SUITE, not the game. Run it before trusting any green. |
| 20 | C28 | Geometric, seconds per screen, aimed at the defect a player sees first. Found a live one. |
| 21 | C27 | Three configurations per screen; the only gate that tests the options the player can actually change. |
| 22 | C29 | Godot's picking rule re-run over every clickable control. Clean, but it is the standing net under "the button doesn't work". |

## The rule for every pass

A finding is not a bug until it is **reproduced**, and a fix is not done until a
**gate fails without it**. Both halves cost real time and both are non-negotiable:
this session produced two convincing-looking failures that were harness artifacts
(`change_scene_to_file` is inert under `--script`; a probe that broke on
`_hand.size() > 0` measured a deal mid-flight), and one green parsecheck that was
a false pass (it runs as a SCENE, so autoload names resolve). Every one of those
would have become a "fix" for a bug that did not exist.

### C30 - ALIGNMENT: it fits, nothing covers it, and it is still wrong (`tools/_probe_alignment.gd`)

C28 asks whether something is painted over a control; C29 asks whether the click
reaches it; `_probe_textfit` and `_probe_boundary_ui` ask whether the content fits
its own box. All four judge a control against ITSELF. A control can pass every one
of them and still be the thing a player points at and calls wrong - it fits, it is
uncovered, it clicks, and it sits four pixels left of the column it belongs to.
Alignment is the largest category in the published GUI-defect taxonomies after
occlusion and truncation, and nothing here measured it.

**THE ORACLE PROBLEM.** "Off centre" judged one control at a time is a matter of
taste - a single rect cannot tell you what its author meant. It becomes objective
only RELATIONALLY: against the controls laid out beside it, and against what the
layout code itself declared. **81 screen states, 5,303 controls, 856 peer groups.**

- **A. THE ODD ONE OUT.** Five buttons share a centre to the pixel and the sixth
  does not. The column states its intent five times over; the sixth contradicts it.
- **B. THE NEAR MISS.** Two peers whose edges differ by 1-8px. Alignment is binary:
  zero is intent and forty is intent, three is a slip every time.
- **C. THE CONTRADICTED DECLARATION.** `CenterContainer`, and `BoxContainer` with
  `alignment = ALIGNMENT_CENTER`, are the layout system being told in words to
  centre something. A rendered result that is not centred is code disagreeing with
  pixels, no taste involved.
- **D. PROPORTION.** Cross-axis size mismatch among peers, plus sub-24px targets.
- **E. THE ONE-SIDED GUTTER.** An invisible spacer padding one end of a row whose
  content otherwise spans it.
- **F. INK, NOT RECTS.** Worded controls compared across the Button/Label divide by
  where the WORD lands, not where its box is.

**A GROUP DECLARES ITS OWN ALIGNMENT, AND ONLY THAT DECLARATION IS JUDGED** - the
correctness argument of the whole pass, and the first version got it wrong in both
directions. It judged CENTRE in a LEFT-FLUSH column and reported a deliberately
short chip row as "102px off centre" (in a left-flush column the centres differ
precisely BECAUSE the widths do). It judged EDGES in a CENTRED row and reported the
map HUD's purse - a 50px coin deliberately sharing the 40px row's mid-line - as a
5px near-miss on both top and bottom, those two deviations being equal, opposite,
and the signature of a correctly centred object. Both are the same mistake: asking
a question the layout never claimed an answer to. So the metric with the strongest
agreement wins and is the only one judged.

**EXCLUSIONS, each for a stated reason:** anything under a Card2D (a hand fan is
staggered on purpose), any ROTATED or SCALED control (its axis-aligned rect is not
the rect the layout produced - the menu title breathes on a looping 1.0->1.025
tween, and photographing it at 1.014 read as the game's own name sitting 4.2px left
of everything beneath it), and `top_level` controls.

**IT ALSO CHECKS A HELPER'S CONTRACT.** A shared builder that is wrong the SAME way
at every call site is invisible to a relational oracle - every rule it draws is
identically short, so nothing is the odd one out. `_make_ornament_row(width, ...)`
is gated directly: the width a caller passes must be the width it gets.

### Found by C30: five layout defects across the shell

1. **`_make_ornament_row` did not honour its own width.** Each half was sized
   `width * 0.45` with the separations and the diamond added ON TOP, which came out
   right for the centred glyphed row (0.9w + 34 = w at w=340) and was wrong at every
   other call site. **The dossier asked for 340 and drew 183** - twice, on the title
   screen. Its unglyphed branch also added a SECOND rect in the name of "rejoining
   the two halves", re-opening the exact 10px hole (the HBox separation sits between
   siblings) that the branch existed to close.
2. **The dossier's rules were 4px short of its own content box** - three independent
   numbers (388 / 22 / 340) that had already drifted. Now derived from one.
3. **`credits` printed 4px off the column rail.** `Button.flat = true` stops the box
   being DRAWN, not its margins being SPENT. Invisible to a rect oracle twice over:
   the offset lives INSIDE the rect, and a Button is never compared to a Label.
4. **LOAD GAME sat 26px off centre**, and every rect oracle passed it - the three
   plates agreed with each other perfectly, so there was no odd one out, and the
   thing they disagreed with (the centred title) is in another container. The cause
   was a 44px delete-button gutter reserved on the RIGHT only; on a fresh profile
   nothing ever fills it. Measured off the render: title ink centre 800.5, plate
   centre 773.5. Mirroring the gutter (and widening the column by the same 52 so the
   plates keep their width) puts the block back on the screen's axis.
5. **A muster panel's section rule stopped 62% of the way across it** - 658px of rule
   under a heading in a box 1066px wide, because it was sized to the panel's MINIMUM
   width and the panel stretches past it.

**MUTATION-VERIFIED, and one of the oracles was FAKE when first written.** The rect
oracle catches a 5px nudge of the map HUD's gold numeral, naming the control, the
axis and its peers. The gutter oracle catches the LOAD GAME defect at exactly the
26px measured off the render. **The ink oracle caught nothing** - written to catch
the `credits` slip, the fix was reverted and the gate stayed green, because it
demanded an "all but one agree" majority and that column legitimately has TWO rails
(the six action buttons stand 40px in, leaving a gutter for the hover flame to
ignite in). Restated without needing a majority at all - ink positions cluster into
RAILS, and the defect is a rail coming within the near-miss band of another rail
without joining it - it fires on the exact 4px.

### Found by C30, second pass: four screens leaning off their own axis

All four were found by RENDERING the screen and measuring ink, not by the gate —
see the honest limit below. Three are the same shape: **a header row centred as a
GROUP, so the TEXT inside it is off-centre by whatever stands beside it.**

6. **The Reward screen's headline sat 98px right of its own page.** `ceremony_row`
   is centred and holds [campaign standard][title stack], so centring the ROW
   pushed the TITLE right by the standard's whole width. The divider, both relic
   tiles and Continue all centre on 800; the line the player reads first centred
   on 897.5. Fixed with a mirroring spacer whose width is READ FROM the standard.
7. **The Collection title sat 70px left of the page it heads** — the title EXPANDs
   and centres inside whatever box it gets, and a 120px BACK button plus its
   separation was taken off the right end of that box. Same fix, mirrored.
8. **The Collection page itself leaned 20px right**, on `margin_left = 80` against
   `margin_right = 40`. Clearing the settings gear is a real constraint; paying
   for it out of one side is not. 60/60 clears the gear AND preserves the content
   width exactly (1600-80-40 and 1600-60-60 are both 1480), so the card grid keeps
   every column.
9. **The Shop's lower shelf was 400px wider than the one above it.** Only the
   HEIGHT had been re-cut when its tiles shrank; the width stayed at 1500 from the
   text-grown ones, so a shelf carrying 860px of content sat under a Cards shelf
   1100 wide and nearly full, jutting 200px further out at each end. Both are now
   1100 and share their edges.

**AND THE GATE HAD TO BE SHARPENED TWICE MORE, both times against its own fixes.**
Judging a card's INTERNALS reported the v9 writ's corner cost seal as 93.5px off
centre on every card in every grid — so the exclusion is now the INSIDE of a card,
not the card, which buys back the coverage that matters (cards on a shelf or a
draft slate are peers and must line up). And the one-sided-gutter oracle fired on
the Collection header this pass had just centred CORRECTLY: its premise is a single
block shoved off centre, but a row holding a centred title AND a corner BACK button
is a layout with ENDS whose ink is asymmetric on purpose. It now judges only rows
with exactly ONE ink-bearing child — re-verified by mutation afterwards, because
narrowing an oracle is how one goes inert.

### The cross-container axis oracle: TRIED, MEASURED, REJECTED (2026-09-03)

The honest limit below is not laziness — it was attacked directly and the attack
failed, which is worth recording so nobody spends the day again.

The idea was sound: a centre-composed screen has an anchor owing nothing to any
container — the CANVAS CENTRE — so a block off that axis is a finding. Six
successive narrowings were needed and each one was defeated by a case with
essentially identical measurements:

1. judging every off-axis block reported every panel of every two-column layout;
2. skipping blocks nested in an on-axis parent pardoned the founding defect,
   because a column counts as on-axis the moment its title spans it;
3. narrowing to a RANK (two or more blocks sharing width AND centre) killed the
   panel noise but was defeated by a container wrapping a single child, which
   has that child's exact ink and so reads as a rank of two;
4. filtering nesting chains out of ranks then surfaced the muster's hero roster —
   a genuine rank of five, deliberately off-axis as a left-hand panel;
5. requiring the rank to FILL an on-axis host separated those two... until
6. the supply cache, where a correctly centred tile holds an icon beside a text
   column, and that column's host-fill ratio is **0.849** against LOAD GAME's
   **0.845**.

Two cases, one correct and one a defect, differing by four thousandths on the
only axis available to measure them. The discriminating information is not in
the geometry; it is in what the designer meant. **The oracle was removed rather
than shipped** — a second oracle that catches what the one-sided-gutter check
already catches, plus a false positive, is a net loss.

Two things from the attempt were kept because they are correct independently:
`_ink_bounds` now skips bare `Control` wrappers (they never draw, and one used
as a full-rect wrapper was inflating its whole subtree's measured ink), and the
one-sided-gutter oracle is mutation-verified against the LOAD GAME defect twice.

**HONEST LIMIT.** Every oracle here is relational, so a screen that is
systematically wrong in a self-consistent way is invisible to it. Defect 4 was found
by RENDERING the screen and measuring ink columns in the PNG, then explained by
dumping the live tree; the gate was extended afterwards to hold the fix. A whole
composition on the wrong axis is still an eye-and-measurement job.

### C31 - THE DRAWING THAT DOESN'T BELONG (`tools/art_lint.py`)

C30 asks whether a control is in the right PLACE. This asks whether the picture
inside it belongs to the set it was drawn for. Same argument, different medium:
judged ALONE, "is this drawing bad" is taste and unanswerable; judged AGAINST
THE SET, it is measurable.

**THE OBVIOUS TOOL IS THE WRONG TOOL.** A no-reference quality model (BRISQUE,
NIQE) measures DISTORTION - blur, noise, compression, loss of natural-scene
statistics - and the IQA literature is explicit that this is a different thing
from aesthetics. A crisp, flat, ugly yellow triangle has no distortion at all,
so NIQE would rank this project's worst assets among its best. What the game-art
tooling literature actually does is palette/shape/border LINTING against the
set's own norms, which is what this is.

**THE RUBRIC IS THE OWNER'S OWN RECORDED VERDICTS**, not mine - every oracle
traces to a defect they already named in a previous session:

| Oracle | Encodes the verdict |
|---|---|
| A CYAN | "the ONE pervasive defect is saturated CYAN/TEAL in ~40 assets" |
| B OUTLIER | "photoreal stock images", "cartoon HUD icons" - both are distance from the family's colour statistics |
| C DUPLICATE | "plague_bell == mass_grave", "kindling_alt == kindling", "60 cards borrow another card's art" |
| D PIXELART | "grave_debt + a relic cluster are PIXEL-ART" inside a painterly set |
| E TONAL | the painters that read as "drawn by a five year old" |
| F PLACEHOLDER | "root-level assets/icons/*.png are the PRE-ART generic set"; "downloaded/ is a dumped folder" |
| G ATLAS | "the Sell a Card chip was a raw icon ATLAS, eight glyphs in a grid" |

**VALIDATED BY REDISCOVERY.** Run cold over 448 images it independently found
all three duplicates the hand audit had recorded (`kindling`/`kindling_alt`,
`mass_grave`/`plague_bell`, `recruiters_horn`/`war_horn`), plus a FOURTH nobody
had logged (`scouts_emblem`/`mimic_ring`), and ranked `vengeful_spirit` among
its worst cyan offenders - which the audit had separately called "cyan AND
high-impact". Reproducing a human pass is this tool's mutation test.

**THE CALIBRATION LESSON, and it cost two wrong oracles.** Oracle E first asked
"is it UNTEXTURED", which does not separate good drawings from bad ones at all:
CampaignStandard (crude) measures 8.07 local texture and CandleStub (good)
measures 8.04, because a flat shape's HARD EDGES generate exactly as much local
variance as a painting's soft shading. Switching to LUMINANCE levels was worse -
it flags a well-modelled monochrome wax seal (16) while passing a flat white
diamond (41). What separates them is the count of distinct TONES inside the
eroded interior:

    known-good   CandleStub 220 | CoinProp 130 | TrinketIcon 110 | BalanceScale 82
    known-bad    CampaignStandard 50 | WarPip 36 | TrayCloth 32 | StatGem 11 | StatCaret 1

A painted object carries a shading ramp; a crude one is a handful of fills whose
only variance is the seams between them. **Erode before measuring** - every
shape is antialiased, so its boundary always carries a gradient, and averaging
that in is what let the flat crown and the flat diamond through. 7 of 7 known-bad
and 5 of 5 known-good at the threshold; the only residual false positives are
assets that are deliberately flat (a parchment base layer) or monochrome (the
wax seal), and those carry waivers with reasons.

**Painters are linted too.** `tools/_shot_painter_audit.tscn` renders all 51
`scripts/ui/painters/` classes to a contact sheet AND to one TRANSPARENT PNG
each. Transparency is load-bearing: every measurement is taken over drawn pixels
only, so a painter shot against an opaque ground would measure the contrast with
its own background as "texture", which is exactly backwards.

**WHAT IT CANNOT DO.** It cannot tell you a drawing is ugly - nothing can, since
that is not a property of one image. Every finding is either a deviation from the
set the asset belongs to, or a rule the owner stated in words. A beautiful
painting that is the only cool-toned one in a warm set WILL be flagged, correctly,
as not belonging. It is a worklist, not a verdict.

### C31 follow-ups (2026-09-03)

**A BASELINE MAKES AN ALWAYS-RED TOOL RUNNABLE.** `art_lint.py` reports 103 cyan
findings, so it can never be pass/fail — and a tool that is always red is a tool
nobody runs. `--baseline` records the offender SET to
`tools/golden/art_baseline.json` (a set, not counts: counts let one asset be
fixed while another regresses and still read clean), passes on the known pile,
and fails only on a NEW offender. `--bless` re-records. Mutation-verified: a
copied cyan asset fires both the cyan and duplicate oracles.

**THE PAINTER LIST WAS 22 SUSPECTS AND IS NOW 16 FINDINGS.** Checked against call
sites: SEVEN are dead code (0 instantiations — and `StageTable` has no reference
anywhere at all, a seventh orphan beyond the six the 2026-07-21 cull left), and
two are size-correct (`BoneStraw` renders 16x76, `LastStandCandle` 44x68). All
nine waived with reasons. **Grep both forms when testing liveness** — `WaxBar`
and `SpentDispatch` are used as inline `preload(...).new()` with no named const,
so a const-name grep alone reports live painters as dead.

**AND ONE SILENT COVERAGE LOSS IN C30.** Its combat list named
`the_iron_warden`, which is not an encounter id (`iron_warden` is), so for weeks
it measured ONE encounter and reported nothing wrong. A missing id now FAILS
loudly. Combat is also driven into four states per encounter now (at rest, with
bodies on the board, pile viewer open, glossary open) rather than at rest only:
81 to 88 screen states, 5,318 to 6,644 controls.

### The painter craft pass: 22 suspects, ONE real (2026-09-03)

C31's tonal-poverty oracle flagged 22 painters. Every one was checked against
its call site and its own docstring before a line was changed, and the list
collapsed to **two borderline entries**:

- **7 were dead code** — zero instantiations (`StageTable` has no reference at
  all, a seventh orphan beyond the six the 2026-07-21 minigame cull left).
- **2 were size-correct** — `BoneStraw` renders 16x76; a straw that wide IS a
  line. `LastStandCandle` is a 44x68 badge.
- **13 were DOCUMENTED INTENT.** `WarPip` is flat for ACCESSIBILITY (its
  docstring: "a bold flat silhouette AND a saturated tint, so it reads instantly
  and stays legible to a colourblind eye"). `WaxBar` EXISTS because the flat
  StyleBoxFlat it replaced "read as flat UI". `SpentDispatch` replaced "four flat
  Panel strips that read as a gray wireframe". And `CastPatch` records that it
  was already reworked in a **2026-07-20 'looks drawn by a 5-year-old' pass** —
  the list had circled back onto work already done.

**Only `CampaignStandard` was a genuine miss**, and it was the one identified by
eye first: 50 tones at 142x104 on the Spoils screen, seen after every fight won.
Rebuilt with material — the cloth filled as fold bands with a sinusoidal ramp
(darkest at the lashing, where cloth turns from the light), the pole shaded as a
cylinder, a brass finial, and domed wax seals. **50 -> 138 tones**, into the band
of the painters that read as objects. Silhouette unchanged, so no layout moved.

Two build lessons, both caught by rendering rather than by the metric (which was
green at 124 while the drawing was still wrong): a fold band that STRADDLED the
swallow-tail notch drew neither half, leaving an undrawn column that photographed
as a hard seam down the cloth; and a second harmonic added to sharpen the creases
ALIASED against the band count — about five bands per cycle — and photographed as
corduroy. **A tonal count says a drawing has range, not that it is right.**

The waivers are phrased as NOT-A-LINT-FIX rather than "correct": if the owner
wants any of the thirteen richer, that is a design decision they should make, not
one a threshold should force.

### C32 - THE LAYOUT THAT ONLY WORKS AT 100% (`tools/_probe_uiscale.gd`)

Every layout gate in this document runs at ONE viewport: the 1600x900 project
canvas. The player can change that. `SettingsOverlay._add_ui_scale_row` offers
**UI Scale 60-100%**, which sets `Window.content_scale_factor`, and under
`canvas_items` stretch that DIVIDES the logical canvas - at 60% the UI lays
itself out on **2667x1500**, not 1600x900. Anything positioned from a constant
is therefore wrong at four of the five settings the player is offered, and
nothing could see it.

**THE ORACLE IS DIFFERENTIAL** (C27's idea applied to scale), which is what
makes it need no taste. It does not ask whether a screen SHOULD fill the canvas
- some are a small centred dialog and should not. It asks whether a screen
covers the SAME FRACTION of the canvas at every scale. A screen at 99% under
100% and 70% under 60% has something pinned to a constant, and the drop is the
measurement.

**Found immediately: the shell's decorative frame, on every screen with
atmosphere.** `GameTheme._make_decorative_frame` placed its corner brackets and
connecting rules at absolute coordinates read from `ProjectSettings`. An earlier
pass had already moved those off a hardcoded 1600x900 and onto the project
setting, with a comment warning the edges would otherwise "float inward when the
base resolution changes" - but **ProjectSettings is STATIC and the runtime canvas
is not**. Measured on the Spoils screen at 60%: the frame drew 1876x877 inside a
2667x1500 canvas, so the whole border sat in the top-left corner with the painted
background running out from under it on two sides. Rebuilt on ANCHORS - each
corner pinned to its own corner, each rule stretched between them - which is
correct at any scale or resolution with no resize handler to forget. Coverage at
60% went 70%x58% -> 99%x98%, and 100% is unchanged.

**MUTATION-VERIFIED, and the first mutant was too weak to prove anything.**
Shortening ONE connecting rule to a constant did not fire, because the oracle
measures the ink's BOUNDING BOX and three anchored corners still span the canvas.
That is a real sensitivity limit worth knowing: this gate catches a layout pinned
WHOLESALE, not one piece of it. Reproducing the original fault faithfully (all
pieces placed from constants) fires on nine screens across both 0.8 and 0.6.

### C27 was FLAKY on combat, and a flaky gate is worse than none (2026-09-03)

A full gate suite failed on `cfg_diff` with two divergences on
`combat:bandit_camp` under `reduce_motion` — "Trail Scout" and its rules line
present in one profile and not the other. Re-running with byte-identical code
gave **ALL AGREE**. That is the signature of a timing-sensitive assertion, not a
defect, and it had already cost one suite run and an investigation.

**The probe's own docstring documents this exact class**, from an earlier fix: an
Event deal was being fingerprinted mid-animation and "reported a phantom
3-string divergence on roughly one run in three". That fix raised `SETTLE_SEC`
to 1.6 — which repaired the Event case and left COMBAT, whose opening is
deliberately interleaved across several seconds (`Combat._ready` hands the frame
back between build stages, then deals a hand one card at a time). The alignment
gate waits 7s for the same screen; this one waited 1.6.

**A bigger constant only moves the boundary.** It now SETTLES UNTIL STABLE:
sample the fingerprint every 150ms past the old floor and accept it once two
consecutive samples agree, with a 12s cap and a reported count of any state that
never stabilised. That is deterministic whatever a screen's build costs, and it
is the same lesson CLAUDE.md already records for `_layout_hand` — **poll until
the count HOLDS**, never trust a clock.

The general rule, which cost two probes to learn: **a gate that samples an
animated screen on a fixed timer is measuring the machine, not the game.**


### C33 - THE RESOLVER NOBODY EVER RAN (`tools/_probe_resolver_sweep.gd`)

C26 measures what one random-deck skirmish driver reaches, and ends by naming the
hole it cannot cover itself:

> "32 further spell effect types are CAMPAIGN-ONLY and outside this driver's
> reach. `_probe_autorun` soaks campaign combat, so some are likely covered there
> — but no pass MEASURES that, so it is UNKNOWN rather than uncovered."

Measured 2026-09-19 that was **22 skirmish-unreached spell types plus 32
campaign-only ones** — up to 54 resolvers with no evidence of ever having
executed, behind a fully green suite. This pass does not measure that coverage,
it MANUFACTURES it: every spell in `CARD_POOL` is resolved once, on a real board,
in a real Combat scene. Result on the first clean run: **90/90 resolved, 0 skips,
0 runtime errors, 0 invariant hits** — the campaign-only half works.

**THE ORACLE IS NOT AN ASSERTION ABOUT THE EFFECT.** What *should*
`custom:apocalypse` do? Answering needs an oracle the engine itself is — the
problem that stopped the text-vs-data pass and produced C10 instead. So this pass
asserts only the two things checkable without a second implementation: (A) THE
GAME SAID NOTHING, and (B) THE BOARD SURVIVED (no freed node standing in a row,
no non-finite stat, no negative Command, no duplicate uid in hand — C14's idea
applied per effect).

**(A) CANNOT BE CHECKED FROM INSIDE THE PROBE, AND THAT IS THE WHOLE DESIGN.** A
GDScript runtime error does not raise, does not stop the game and does not change
the exit code. The mutant run proves it: with a fault injected into the
`frost_bolt` arm, the probe still printed `0 failures` and `PASS` while the game
was broken. Scoring therefore lives OUTSIDE, in
`tools/_score_resolver_sweep.sh` — **that script is the gate, not the probe.**

**ATTRIBUTION IS THE MECHANISM.** Godot's error output names a line in Combat.gd,
not the content that reached it, and an unattributable dump gets skimmed and then
ignored. Every resolution prints `[resolver] TRY <id> (<type>)` BEFORE the call,
so an error lands directly beneath its cause and the scorer walks the log in
order blaming each on the last TRY. Do not buffer or batch those prints.
Mutant-verified: the injected fault was reported as exactly one error, named to
`frost_bolt (custom:frost_bolt)`.

**TWO TRAPS IT COST, both the house classics.**

1. **A UNIFORM FAILURE IS A BROKEN ORACLE.** The first run reported 86 identical
   errors — one per spell, including trivial `strike (damage)`. That was the
   probe reading `deck_uid` off `CreatureInstance`; it lives on `Card2D`. Same
   tell as `run_chaos_save`'s 14-of-14 "unusable state".
2. **A FIXED LANE CAN BE LEGITIMATELY DENIED.** Seating every target at lane 0
   looked obviously fine. `summon_token`'s own header records why it is not —
   Salted Ground "must bind every enemy" summon — so resolving `salted_ground`
   salted the lane the probe kept reusing, and the four enemy-target spells
   sorting after it were reported unseatable against a game behaving exactly as
   specified. `_seat_anywhere` walks the slots instead, which is also robust to a
   set-piece's closed ground without restating either rule.

**VACUITY GUARD.** "Resolved 0 of 90, no errors" is a green light over an
untested surface. Every skip is printed with its reason and counted, and the pass
FAILS below `RESOLVE_FLOOR`. Read the tallies before believing the verdict.

### C33, phase B - THE CREATURE TRIGGERS (`tools/_probe_resolver_sweep.gd`)

C26's unreached list is not only spells: 8 on-enter types, 3 on-death types and a
long tail of on-play abilities were never fired by its driver either, and
`atk_hp_per_unspent_mana` is named by no tool in the suite. The gates that DO
touch these (`newcards`, `newslate`, `retinue_hooks`, `sexton`, `boardverbs`)
each assert a specific behaviour for a specific card — valuable, and not the same
thing as an exhaustive crash-and-invariant net over every authored trigger.

Phase B fires **every** card's `on_enter` / `on_death` / `on_play` through the
real dispatchers, on a board seeded with a friendly neighbour and an enemy
opposite so adjacency/copy/opposing arms get real material instead of silently
taking their empty-board branch. Totals: **161 resolutions** (90 spells + 28
on-enter + 22 on-death + 21 on-play), **0 runtime errors, 0 invariant hits, 0
skips**. Per-channel floors fail the pass if any channel fires almost nothing, so
a healthy spell total cannot paper over a dead channel.

**`floop` IS DELIBERATELY ABSENT.** It has no standalone resolver — floop effects
are resolved inline in the round flow, and `_resolve_on_play_ability` reads
`on_play` only (its `blood_sacrifice` arm is an on-play type that merely shares a
name with the floop concept). Firing floops here would mean re-implementing the
round, i.e. a second implementation of a rule this codebase has paid for twice.
Left out and said so, rather than shipped as a channel that looks covered.

Mutant-verified separately from phase A: a fault injected into the shared
`damage_opposing` arm was reported as exactly two errors, attributed to
`hedge_caster` and `brute` — every card that reaches that arm, which is more
useful than a single hit.

### C34 - THE FIXTURE THAT PINS A BALANCE NUMBER (`tools/_probe_fixture_pins.gd`)

**This gate tests the tests**, and it exists because one class has produced almost
every red line in this suite's history. The 2026-09-19 sweep of 95 gates found 8
failing checks across 4 probes and **all 8 had one cause**: a rebalance raised
costs and stats (`duelist` 2/2-3 -> 3/3-4, `the_glutton` hp 3->4, `sin_eater`
2/3 -> 3/4, `breaker` atk 2->3, `tallow_doll` 2/2 -> 3/3) and every probe had
pinned the OLD number. The mechanics were all correct. It is also #3 and #6 in
`reference_stale_probe_sweep`'s own frequency list.

The cost is not the red line — it is what a red line nobody believes does: it
trains everyone to skip the suite, and then a real regression lands in a harness
no one reads. **A gate that pins a balance number is a tax on rebalancing, not a
guard on design intent.**

**What is and is not a finding.** A literal is FINE when the fixture states its
own requirement — seat a synthetic 2/6 dummy, assert `hp == 6`, and no content
change can touch it. A literal is FRAGILE when the subject came from CONTENT
(`_seat_id("x")`, `get_card_data("x")`, `CARD_POOL["x"]`) and the assertion then
pins a stat to a bare integer.

**PROXIMITY, NOT PER-FUNCTION — and that was a defect first.** Scoping the
co-occurrence per function looked obviously right and flagged four assertions in
`_probe_newslate._run_test` that are the GOOD pattern: they assert on a
`summon_token(1, 1, ...)` the probe itself sized. That probe puts every test in
ONE monolithic function, so whole-function scope attributed `breaker` /
`sin_eater` / `ironclad_veteran` from unrelated tests a hundred lines away. A
14-line window is both more faithful (these are written seat-then-assert) and far
more precise: findings fell 50 -> 35 and the four false hits vanished. Second
defect the same run: a single assertion routinely compares both stats
("atk == 4 and hp == 5") and was reported twice, doubling the apparent count.

**It reports on the inventory and fails on the volatile.** 35 existing fragile
pins are legacy debt, and dropping 35 red lines would be the very thing this
class warns about — so that is a COUNT, the same stance C18 and
`_probe_card_rules_fit` take. It FAILS only on a pin naming a card in
`RECENTLY_MOVED`, i.e. one a rebalance has already churned. Mutant-verified:
restoring the old `duelist` literal produces exactly one failure, named to
`_t_condottiere()`. In `run_safe_probes` (static, seconds).

### C32 gains an ADDRESS, and three waivers earned by measurement (2026-09-19)

`uiscale` was RED on five drops. Two were the wholesale-pinned rects this class
was built for and are FIXED: `game_over` (a 1180px chronicle at ±590) and
`net_lobby`'s x-axis (flanking plates spanning ±745, which are what the oracle
measures on that screen — fixing only its centre column moved nothing, the
ink-bounding-box limit the gate's own header warns about). Both now scale through
**`GameTheme.canvas_scale(node)`**, one definition rather than a fifth hand-rolled
copy of `canvas / design`; MainMenu had already solved it inline, and five copies
of one rule is this codebase's documented worst pathology.

**THE GATE NOW NAMES THE NODE.** "y coverage falls 81% -> 68%" identifies a screen
and not a rect, so acting on a finding meant re-deriving the walk by hand — and it
made the WRONG diagnosis cheap: the residual on three screens was assumed to be
fixed-size content and nearly waived on nothing but that assumption. `_extremes()`
mirrors `_coverage`'s filters exactly and reports the top/bottom/left/right
contributor at both scales.

What it found is that the assumption was right and is now **measured**:

    screen      1.00                     0.60
    net_lobby   top=Panel @14  bot @739   top=Panel @14  bot @1039
    treasure    top=Panel @14  bot @857   top=Panel @14  bot @1157
    recruit     top=Panel @14  bot @746   top=Panel @14  bot @1046

The top edge is the SAME node at the SAME y at both scales — a pinned 14px margin.
The bottom edge moves **exactly +300** on all three, which is HALF the canvas
growth (900 -> 1500): the signature of content that is CENTRED with a size that
does not scale. So the containing rect already follows the canvas; the CONTENT
inside it does not — fonts, a 225x300 card wrapper, portrait wells.

Closing them means deciding whether a card, a portrait and a font grow with UI
Scale, which moves bake sizes and runs into COPY_STYLE §11's reading floors. That
is a DESIGN call, so they are WAIVED with the numbers above recorded in the waiver
itself, and the three candidate fixes named there. **A permanently red gate is
worse than a waived one** — that is the lesson this whole sweep started from.

Mutant-verified after waiving, because a gate made green by suppression is the
failure mode here: re-pinning the `game_over` panel fails the gate again and
prints `left=Panel @14  right=Label @1400 -> @1933`.
