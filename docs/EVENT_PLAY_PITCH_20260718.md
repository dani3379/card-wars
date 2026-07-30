# EVENT PLAY PITCH — "The Screen Plays the Scene" (2026-07-18)

**Status: L1 + L2 + L3 + XL BUILT + shot-verified (2026-07-18)** — the
Knucklebone Patch (§3.1, now a true tumble: faces turn mid-air, the real
face stamps at first impact, decaying hops), the Spinner (§3.2), the
Burning Inch (§3.3, CandleStub on every risk_loop), Drawing Lots (§3.4,
every roll_table resolves as a drawn slip), and the Shell Game (§3.6 —
shipped as **The Old Army Game**: `shell_game` engine + `old_army_game`
event; the coin rides its helmet so the shuffle is honest by construction,
and the dented helm never holds it). The `seen_texts` story thread ("the
old debt") now spans the pit, the spinner, and the paymaster's clerk.
Verify `tools/_shot_event_pass.tscn` (23 frames), `_probe_events`,
`_probe_audio_cues`. **Beyond the pitch (2026-07-18 quality passes), FOUR
skill games joined the table: `straw_game` — The Short Straw, misère Nim
against the dead watch (no roll anywhere; perfect opposition; only
winnable openings; the arithmetic is the game); `tray_game` — The Widow's
Tray, Kim's game over dead men's effects (self-paced study, removal baked
at cover, answered blind, honest reveal); `sack_game` — The Courier's
Satchel, the counting game (draw toward 13 with the remaining multiset
CHALKED ON A SLATE — informed push-your-luck); `race_game` — The Sappers'
Derby (posted odds, winner baked at post time, honest animated race; the
blue buffs the longshot's chances, never its price). L4 is BUILT: the Wet
Cards deal face-down and flip up in turn (the folio hover lean already
existed in `_make_frameless_choice`). Template C is BUILT and expanded into four data-driven ordinary-event compositions: Confrontation, Location, Bargain, and Ritual. Twenty-six live events are routed through them; choice geometry adapts to the visible count, selected choices survive as stamped result receipts, every routed painting has reviewed focal/zoom metadata, and hover focus gives the art stage a restrained response.**

## 1. Diagnosis — why 30 good events feel like one event

Shot evidence: `tools/_shot_event_main.png` (folio), `tools/_shot_event_dice.png`
(the "minigame").

The 2026-07-03 remake fixed the *design* (one concept per event, build/fight
payoffs) and the prose is the best writing in the game. But every event renders
through **one layout with one input verb**:

- Title top-left → prose paragraph → I/II/III ladder of text rows → WALK ON.
  Thirty times. The only thing that changes is the painting and the words.
- **The games are described, never played.** The Bone Pit's prose promises four
  dead legionaries casting knucklebones cut from their own hands; the dice
  screen delivers a headline ("The pot: 85 gold"), two more text rows, and a
  five-coin sprite cluster floating in the dark. "Cast the bones" is a
  sentence you click. No bones exist on screen.
- Every choice, gamble or not, resolves to the same result page: prose + stat
  ticks. The *outcome* of a knucklebone throw and the outcome of donating to a
  chirurgeon are visually identical.

The engines underneath (`dice_run`, `risk_loop`, `roll_table`,
`stranger_hand_pick`, appraisal) are solid and fully data-driven — text,
odds, and payouts all live in EventDB. **This is purely a presentation-layer
problem, which is the cheap kind.**

## 2. Principle — every interactive engine gets an INSTRUMENT

The war table doctrine, applied to events: an event is something that happens
**on the table, to objects, under your hands** — not a menu about that thing.
Each reusable engine gets one physical prop the mouse operates. The prose
stays exactly as written; the screen finally performs it.

Doctrine carry-overs that bind this work:
- **Bake then shade**: the engine resolves FIRST (existing RNG paths,
  untouched), then the prop animates the already-resolved outcome. No
  gameplay waits on theater (Petard-lob exception stays unique).
- Reduce Motion: props snap to end states via the kit verbs' self-gating;
  outcome information never lives only in motion.
- New painters go in `scripts/ui/painters/`; FX through `Motion.burst/ring`;
  SFX through `AudioBank` with `SFX_FALLBACKS` stand-ins.
- Mouse-only, gl_compatibility (no clip_children — bake alpha instead).

## 3. The instruments

### 3.1 FLAGSHIP — The Knucklebone Patch (`dice_run`, prop "bones")

The Bone Pit becomes a real tabletop game:

- Art dims to the picker scrim; a **leather casting patch** lays out
  center-right (new `CastPatch` painter: seeded dark leather, stitched
  border — WritLeaf wobble in hide tones).
- **Four knucklebone dice** rest at its edge (new `KnuckleboneDie` painter:
  seeded bone lozenge, ink pips, one face carries a skull). Painters, not
  sprites — same reasoning as WaxSeal.
- **The pot is a heap of real coins** on the patch (1 coin per ~5g, capped),
  under the gilt figure.
- **CAST** (click the bones or the existing text row — both stay): resolve
  the roll first, then the bones tumble across the patch — staggered arc
  tweens, rotation, squash bounces, `Motion.time(~0.55)` — and settle on
  faces that MATCH the outcome: clean pips on a win, skulls up on a bust.
- Win: coins fly INTO the heap (`Motion.burst` coin preset + `tick_number`),
  `grow_text` writes on. Bust: hard clack, the heap slides off into the dark
  toward the dead men's side, small `add_trauma`, bones scatter.
- **BANK — the pot itself is the button**: hover lifts the heap
  (`attach_rich_hover`: "Take {pot} gold"), click pockets the coins away to
  the stakes ledger (`pocket_away`). The text row remains as the accessible
  duplicate; both call `_on_dice_bank`.
- SFX: `bone_cast` / `bone_settle` / `coin_pour` cue names with fallbacks.

Zero data/odds/text changes — EventDB already parameterizes everything.
The engine is shared, so any future gamble event inherits the table for free.

### 3.2 The Spinner (`dice_run`, prop "coin") — same flagship pass

The Coin That Won't Land gets its coin ACTUALLY spinning: sinusoidal X-squash
(fake 3D), blur streak at speed. Each call plays an **almost-topples beat**
(lean, wobble — anticipation) before it rights itself (win, pot doubles with
coin_spark) or falls flat with a hard clack and a long shadow (bust). The
near-miss wobble is the drama the prose already sells ("It blurs, leans,
nearly topples —").

### 3.3 The Burning Inch (`risk_loop`)

Push-your-luck needs a visible fuse. A candle stub stands beside the choices;
every "verse" burns it visibly down (wax drips accumulate = risk made
physical). On the bust it gutters out (ash burst); on walking away the flame
stands steady. Pure ratchet display — odds stay in data. Smallest lift here.

### 3.4 Drawing Lots (`roll_table`)

Committed-mystery choices (force the crossing, the King's Measure) currently
jump straight to the result page. New beat: an upturned helmet holding folded
paper slips; the click draws ONE slip, it unfolds (scale + `write_on`) into
the outcome line. Sells "you committed, the road decides" in one image.
One shared prop, themed by event later if wanted.

### 3.5 Card pickers (`stranger_hand_pick`, appraisal, remove)

Already the most tactile screens (real Card2Ds). Small upgrade only: the Wet
Cards deal face-DOWN with damp warp (rotation jitter + stain modulate) and
flip on hover — the reveal becomes part of the pick.

### 3.6 STRETCH — a new bespoke minigame event: The Shell Game

Three overturned helmets on the patch, one prize; the shuffle plays out ON
SCREEN and watching the shuffle IS the game (extends the Rotting Carnival's
"reading the tell" thesis into motion). Honest speed: trackable at normal
attention, and one helmet always rings false (dented, the tell) for players
who lost the thread. New event + new engine — only after 3.1–3.4 prove out.

## 4. Break the single layout — three folio templates

- **A. Folio** (current): character/prose events. Keep; add choice-row hover
  lean (`hover_lift` family) so even the ladder feels physical.
- **B. Table close-up**: any interactive engine — art dims, camera push-in
  (kit verb exists), instrument center. 3.1–3.4 all live here.
- **C. Confrontation**: character meetings keep the figure in a clear right-hand
  field while compact REPLY writs share a bottom rail.
- **D. Location**: the centre remains a panoramic landscape; ROAD choices sit
  along a route line at the foot of the painting.
- **E. Bargain**: a ruled ledger/table field turns choices into TERMS contracts
  while the merchant or traded object remains visible beside it.
- **F. Ritual**: a ceremonial centre and arced VOW seals replace the document
  silhouette for supernatural transformations and sacrifices.

C-F are selected by `EventDB.presentation.layout`; the folio remains the safe
fallback and table/minigame engines keep their bespoke instruments. Result pages
retain the selected composition. Verify all four entry and result states with
`tools/_shot_event_layouts.tscn`.
## 5. Scope ladder & recommendation

| Tier | Work | Touches |
|------|------|---------|
| L1 ★ | Knucklebone Patch + Spinner (3.1, 3.2) + template B scaffold | 2 events now, every future gamble |
| L2 | Burning Inch (3.3) | choir + future risk_loops |
| L3 | Drawing Lots (3.4) | every roll_table event |
| L4 | Wet-cards flip + folio hover lean (3.5, 4A) | pickers + all 30 |
| XL | Shell Game (3.6) | new event |

**Recommended order: L1 first** — biggest gap between prose and screen,
engine already balanced, both gamble events become showpieces. Then L2+L4
(small), L3, and only then decide on XL.

## 6. Verification

- Extend `tools/_shot_event_pass.gd`: bones-settled-win, bones-settled-bust,
  banked-pocket, spinner-wobble, candle-ratchet states.
- `tools/_probe_events.gd` keeps gating effects headless (no data changes,
  so it should pass untouched — run it to prove that).
- Reduce Motion shot pass for the flagship (props snap, no orphan states).
