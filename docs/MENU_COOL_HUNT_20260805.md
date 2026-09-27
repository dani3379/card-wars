# What would make the MENUS cooler — a hunt (2026-08-05)

> **STATUS: ❖1–❖9 BUILT the same day.** The diagnosis below is unchanged; the
> "what shipped" ledger is at §5.

Scope: the shell — every screen that is not the board, the chart or an event.
Ordered the way a player meets them: **what they see FIRST, then what they see
MOST.** Sibling to [`GAME_COOL_HUNT_20260804.md`](GAME_COOL_HUNT_20260804.md)
(the war) and [`CARD_PLAY_COOL_HUNT_20260803.md`](CARD_PLAY_COOL_HUNT_20260803.md)
(the hand), and answerable to the same rules:

> **★3 (SIZE).** An effect lands only where its material is visible at the size
> it is drawn.
>
> **★4 (SUBSTANCE).** Obey the material.

Items numbered **❖** so they never collide with the pitch's ★, the game hunt's ✱
or the card hunt's ✦.

Every claim below was measured against a render shot for this pass
(`_shot_runstart` 26 frames, `_shot_menus_audit` 10 frames) or grepped out of the
shipped source. File:line refs are live.

---

## 0. The exposure ladder

| # | Screen | When | Frequency |
|---|---|---|---|
| 1 | **Title screen** (`MainMenu._rebuild_menu`) | first thing ever seen | **every launch, forever** |
| 2 | **CHOOSE YOUR HERO** (`_show_quick_march`) | first run only | once per profile |
| 3 | **THE MUSTER I–IV** (`_show_muster_step`) | every run start | ~once per 40 min |
| 4 | **Settings** (`SettingsOverlay`) | launch (audio/res) + every pause | **most-opened overlay** |
| 5 | **How to Play** | first session | once, but it is the teaching surface |
| 6 | Collection · Credits · Load · Skirmish lobby | long tail | rare |

Rows 1 and 4 are where a fix pays compound interest. Row 2 is where a refund
decision gets made.

---

## 1. Thesis: the shell is a beautiful SILENT DIAGRAM of a game about objects

Two things are true at once and they explain almost every finding below.

**The art direction is already excellent.** The title screen is a burning
meadow with a knight in silhouette, a warm left column in the Hades/StS grammar,
a gilt ornament, a ruled CURRENT RUN dossier. THE MUSTER's step I prints eleven
real card faces at readable size. Nobody needs to repaint this.

**But the shell is a picture of an interface, not an interface.** It does not
make a sound, it does not move under the cursor, it does not use the game's own
physical kit, and it does not change no matter what the player does. Three
grep results carry the whole argument:

```
scripts/scenes/MainMenu.gd        play_sfx call sites: 0
scripts/ui/SettingsOverlay.gd     play_sfx call sites: 0
mouse_entered sites in scripts/:  40    ... that play a sound: 0
```

The first screen of the game is silent when you touch it. So is the settings
overlay, the collection, and the credits. **There is no hover cue anywhere in
this build.** The entire SFX library is 19 directories and exactly ONE of them
is a UI cue (`button_click`) — which is simultaneously doing stand-in duty for
six unrelated gameplay cues (`doom_tick`, `bone_settle`, `candle_out`,
`sniper_aim`, `refused`, `AudioBank.gd:33–56`).

Meanwhile the combat layer has hitstop, a shuffle bag for strike SFX, a spotlight
pan, a mass-grave beat and a killing-blow world-drain. **The gap between how the
war feels and how the menu in front of it feels is the single largest quality
delta in the build.**

| Generic today | What the material says it should be |
|---|---|
| Every button is silent, in a game whose combat has a per-strike shuffle bag | paper, wax, ember — a **60 ms** tick under the cursor |
| THE TERMS is four dark rectangles | four **writs**, and the accepted one takes a **wax seal** |
| HOW TO PLAY teaches "drag a CARD onto a SLOT" with an octagon reading `CARD` | the game has a live `Card2D` and a bake pipeline — **show the card** |
| 24 marches in, the meadow is the same JPEG | the isle is called *Burning*; the record should be **on the page** |
| BACK and TAKE THE FIELD are the same ivory text at the same size | one of them is the **only** thing the screen wants you to do |

---

## 2. The slate, ranked by (impact × screen time) ÷ cost

### ❖1 — The shell makes no sound. Four cues fix every screen at once.

**Measured.** `MainMenu.gd` contains exactly one AudioBank call and it is
`play_music_random` at line 126. `SettingsOverlay.gd`, `Collection.gd` and
`Credits.gd` contain zero. Forty `mouse_entered` handlers exist across
`scripts/` and not one of them plays anything.

**What the research says.** UI microinteraction audio should be **50–500 ms**,
immediate, and above all **non-fatiguing** — these sounds repeat thousands of
times per session, and the Nielsen Norman finding is that interface audio must
be brief or it disrupts the interaction it is confirming
([SFX Engine](https://sfxengine.com/blog/best-practices-for-game-ui-sounds),
[Audiokinetic](https://blog.audiokinetic.com/approaching-ui-audio-ui-design-perspective-2/)).
This is the cheapest juice in games and this build has none of it.

**The house shape.** Four cues, in the game's own materials — not a UI beep:

| cue | material | length | where |
|---|---|---|---|
| `ui_hover` | dry paper tick / a single ember pop, −14 dB | ~60 ms | every shell button's `mouse_entered` |
| `ui_select` | a card being set down on wood | ~120 ms | any pick that does not advance |
| `ui_back` | paper drawn back, softer + pitched down | ~120 ms | BACK / CLOSE / cancel |
| `ui_commit` | **a wax seal pressed** | ~300 ms | NEW MARCH · TAKE THE FIELD · APPLY |

**Why it is cheap.** `_make_menu_button` (`MainMenu.gd:571`) and
`_make_secondary_action` (`MainMenu.gd:652`) are already the two funnels every
shell button in the game passes through, and `_on_menu_btn_hover`
(`MainMenu.gd:709`) is already bound to `mouse_entered`/`focus_entered` on all
of them. Four `play_sfx` lines inside those two functions and the whole shell —
title, muster, load, settings nav — gains audio in one edit. Follow the house
convention and pass jitter (`play_sfx(name, 0.05)`) so the hover tick never
fatigues; `SFX_FALLBACKS` entries let all four ship before the real clips land.

`ui_commit` is the one that should be a genuine *stamp*: NEW MARCH and TAKE THE
FIELD are the two moments the player commits 40 minutes, and they currently
sound exactly like nothing.

---

### ❖2 — The primary action never looks like a button. The hierarchy device is dead code.

**Measured.** `_make_menu_button(text, _bg, font_size, height)` — the second
parameter is named `_bg` and its own header comment says it *"is retained for
call-site compatibility but no longer drives a fill"* (`MainMenu.gd:571`). But
`_rebuild_menu` still passes a distinct colour per item — `Color(0.32,0.26,0.14)`
for CONTINUE, `Color(0.18,0.36,0.18)` for NEW MARCH, `Color(0.26,0.16,0.14)` for
QUIT — under a comment that states *"visual hierarchy comes from per-button
COLOR, not size."* **That hierarchy does not exist.** In the render, all eight
title-screen items are identical ivory at 22 px. CONTINUE and QUIT have the same
weight.

It repeats on every subscreen. On THE MUSTER, `BACK` and `THE BANNER` are the
same ivory text at the same size in the same row; same for `BACK` / `ORDERS`,
`BACK` / `SEE YOUR COMPANY`, and — worst — `APPLY` (plated) sitting beside
`RESUME` (bare label) in the settings overlay, where RESUME is the most-pressed
control on the screen and the only unstyled one (§❖7).

**The fix is one missing sibling.** `_make_secondary_action` already exists and
is explicitly *"one quiet, persistent document-tab frame: subordinate to TAKE
THE FIELD"*. There is no primary counterpart. Add `_make_primary_action`: the
document tab in warm parchment with the **flame lit at rest** rather than on
hover, so the forward move is the one thing on the screen already burning. Then
either delete the dead `_bg` argument or let CONTINUE/NEW MARCH actually use it.

---

### ❖3 — No hover scale, no press state at all

**Measured.** `_on_menu_btn_hover` (`MainMenu.gd:709`) tweens exactly three
things over 0.18 s: label colour → gilt, flame alpha → 1, row x → +12. There is
no scale. And `_make_menu_button` assigns `StyleBoxEmpty` to **all five** states
including `pressed` — so **a click produces no visual change whatsoever.** The
button is identical the instant before and the instant after the press that
starts your run.

The genre-standard shape is hover **1.05×** → press **0.95×** → release
**1.0×**, with transitions in the **100–300 ms** band and input never blocked
during them ([StraySpark](https://www.strayspark.studio/blog/game-ui-ux-design-principles)).
0.18 s is already in band; the missing halves are the scale and the press.

Note the house constraint: `Motion.punch` already exists as the keyed
kill-before-restart impact verb, and hover lift is **decorative** — it must gate
on Reduce Motion, which the kit verbs do for themselves.

---

### ❖4 — THE TERMS is a screen about writs, drawn as four rectangles

**Measured** from `_runstart_step3_terms.png`. Four flat slabs on a 1600-wide
canvas, the leftmost starting at x 38 and the rightmost ending at ~1880 — they
touch **both** screen edges. The accepted one is marked by the word `CHOSEN` in
11 px gilt in its top-right corner. Content occupies a ~200 px band of a 900 px
screen; the remaining ~55 % is scrimmed-to-black background art.

**What the material says.** This screen's own copy calls them *terms*, dealt
from *`WritDB`*, in a game whose card faces are literally called
*illuminated writs*. `scripts/ui/painters/` holds thirty painters — `WritLeaf`
(seeded deckled sheet), `InkCartouche` (swallowtail banner), `WaxSeal`,
`ParchmentPlate`, `TallyMarks` — and **this screen uses none of them.**

The accepted term should not say `CHOSEN`. It should take a **wax seal**, in the
one place in the shell where a seal is the literally correct object. `WaxSeal` is
already a preloaded const in `Card2D`, already draws a seeded irregular blob, and
is already the game's visual verb for *this is now binding*. ★3 passes
comfortably: the tile is ~430 px wide against a 38 px seal.

Same treatment, same painters, retires the "four dark rectangles" reading on
step III and shrinks the dead band at the same time.

---

### ❖5 — HOW TO PLAY teaches a card game without showing a card

**Measured** from `_menus_how_to_play.png`. Step 1 reads *"Drag an affordable
creature from your hand onto a glowing slot"* and illustrates it with two
octagons containing the words `CARD` and `SLOT`. Step 3 uses three more reading
`BACK`, `FRONT`, `FOE`. About 200 px at the foot of the panel is empty.

This is the one screen in the build whose entire job is teaching, and it teaches
with abstract schematics in a game that owns a live `Card2D` renderer, a batched
bake pipeline (`CardTextureCache.bake_many`) and 4×4 slot art. The material for
an honest diagram is already loaded in memory.

Cheapest honest version: bake one real starter creature and drop it on a real
slot plate. Better version: let step 1 *animate* the drag once on a loop — a
teaching screen for a drag verb that never shows the drag is the definition of a
diagram standing in for the thing.

(The 2026-08-03 pass already found `_htp_device_plate` at 11 px here and lifted
it to 14 — the floor was the symptom; the schematic is the cause.)

---

### ❖6 — CHOOSE YOUR HERO gives the hero a third of the pane

**Measured** from `_runstart_quick_march.png`. The right pane
("HOW THIS HERO FIGHTS") is ~1250 × 570. Its content — portrait, name, two
lines, a PLAYSTYLE row — ends at roughly y 560, leaving **~450 px × 900 px of
empty panel** under it, the largest single void in the shell. The portrait
itself is a ~280 × 510 slab.

This is the screen that sells the run. In every surveyed game the chosen
character is the screen: Hades gives Zagreus the full right half, Slay the Spire
gives the Ironclad a full-bleed portrait, Darkest Dungeon's roster art is
enormous. Here the art the project commissioned is a narrow strip with a large
dark rectangle beneath it.

Two fixes, both cheap: let the portrait take the pane's real height (the
2026-08-03 pass already made `_hero_detail` the `EXPAND_FILL` child *precisely*
so the portrait could absorb surplus — it is being given ~0 of it here), and move
`RECOMMENDED FIRST HERO` off the far top-right corner onto the **roster row it
recommends**, where a first-time player is actually looking.

---

### ❖7 — Settings: the most-pressed control is the only unstyled one

**Measured** from `_menus_settings.png`. The footer is `APPLY` (plated,
chamfered, gilt-ruled) beside `RESUME` (a bare text label, no plate, no rule),
with `MAIN MENU` and `QUIT GAME` plated on the row beneath and aligned to
neither. RESUME is what closes this overlay — the action taken every single time
it is opened — and it reads as a caption that has come unstuck.

Give it the primary treatment from §❖2 and put the four controls on one honest
grid: `RESUME` (primary) · `APPLY` · then the destructive pair set apart.

Second, smaller: the overlay is ~30 gold-on-dark rows with the four section
headers as the only structure, and the dropdowns still carry a plain caret
rather than the kit's gilt diamond. It is legible and it is dense — but it is the
one shell screen with no material on it at all.

---

### ❖8 — 24 marches in, the meadow has not burned

**Measured.** `GameTheme.add_atmosphere(self, "main_menu")` loads a single
static `assets/backgrounds/main_menu.png`. There is exactly one. The only thing
on the title screen that responds to a player's history is a 17 px grey line:
`Marches 24 · Victories 0 · Defeats 24`.

**What the research says.** Altering the main menu *"will be immediately noticed
by the player"* and is a staple device for signalling progression and stakes
([Fuwanovel — Multiple Title Screens](https://forums.fuwanovel.moe/blogs/entry/4131-multiple-title-screens-%E2%80%93-an-anatomy-of-visual-novels/)).
It is also the exact thesis of the game hunt one day earlier: *stop adding
beats, start letting the document accumulate.*

**What the material says.** The isle is called the Burning Isle. The game is a
*record* — writs, a chronicle, a chart the war eats. Three graded options,
cheapest first:

1. **The embers count.** `_add_menu_embers` already runs a live emitter. Scale
   its count/heat off `MetaState.total_victories` — the meadow burns hotter the
   further you have gone. Zero new art.
2. **The knight wears your colours.** The silhouette is a fixed element; tint
   its banner from the last-used `BannerDB` tribe. One modulate.
3. **A seal per lord felled.** Five rival lords; a `WaxSeal` pressed into the
   column's lower ornament for each one broken. The painter exists, the record
   exists, and it is the thing a player screenshots.

None of these is a new system — all three read the `MetaState` ledger the title
screen is *already* printing as a grey text line.

---

### ❖9 — The subscreen scrim spends the best art in the game to seat 200 px of text

**Measured.** `_center_menu_for_subscreen` calls `_set_subscreen_scrim(true)`,
which re-textures `MenuScrim` from a left-edge gradient to a full-rect vertical
wash. This was a **correct** 2026-08-03 fix — before it, THE PACT tile was being
read against open fire. But the consequence on the render is that THE TERMS,
step I and HOW TO PLAY all present a large near-black field with a thin band of
content in it.

The fix is not to weaken the scrim; it is to stop needing full-rect coverage.
Where §❖4 and §❖6 fill the middle of the canvas with material, the wash can
retreat to the band that actually carries text and let the fire back into the
frame. Worth stating plainly so the next pass does not "fix" the scrim and
re-break the readability the last one bought.

---

## 3. Recommended order

| | item | cost | screen time |
|---|---|---|---|
| 1 | **❖1** four UI cues in two funnels | **hours** | every screen, every session |
| 2 | **❖2 + ❖3** primary action treatment + hover/press | hours | every screen |
| 3 | **❖7** settings footer | ~1 h | most-opened overlay |
| 4 | **❖8.1** embers read the ledger | ~1 h | every launch |
| 5 | **❖6** give the hero the pane | half a day | the sell screen |
| 6 | **❖4** seal the accepted writ | half a day | every run start |
| 7 | **❖5** teach with a real card | day | first session |
| 8 | **❖8.2/8.3 + ❖9** colours, seals, scrim retreat | day+ | every launch |

Rows 1–4 are a single sitting and they are where the delta between "a nice
static menu" and "this game is expensive" actually lives.

---

## 4. Gates

Nothing here changes gameplay state, but the shell has real gates and this pass
must clear them:

```
Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" res://tools/_probe_parsecheck.tscn
```

plus `tools/run_safe_probes.ps1`, `_probe_text_floor`, `_probe_muster`,
`_probe_menu`, `_probe_terms`, `_probe_menu_motion`, `_probe_settings_exit`, and
`_probe_audio_cues` (headless — **it fails if any `play_sfx` call site resolves
to silence**, so the four new cues need `SFX_FALLBACKS` entries the moment they
are wired). Eyes: `_shot_runstart`, `_shot_menus_audit`.

And the standing lesson from the 2026-08-03 pass, which an adversarial audit
caught out on 3 of its 8 claims: **re-measure each claim against the render, not
against the intent.**

---

## 5. What shipped (2026-08-05, same day)

Every item verified against a re-render, not against the intent.

### ❖1 — the shell has a voice

`AudioBank.UI_CUE_MIX` + `AudioBank.play_ui(kind)`: four cues — `ui_hover`
(a dry paper tick, −17 dB, wide jitter) · `ui_select` (a card set on wood) ·
`ui_back` (the same paper drawn back, pitched to 0.88 so retreat and advance
are distinguishable with the screen unread) · `ui_commit` (a wax seal pressed).
All four carry `SFX_FALLBACKS` aliases, so they are audible now and a real clip
auto-wins the moment `assets/audio/sfx/<name>/` lands.

**Hover is armed inside `GameTheme.make_themed_button` / `make_back_button`** —
the two game-wide funnels — because it is collision-free by construction:
nothing in the repo played anything on hover. **Press is NOT armed there,
deliberately**: ~20 call sites already play their own cue on a button press
(Reward's forge pick, MapView's march, Combat's initiative, the event minigame
props), and arming the funnel would layer a second sound under every one of
them. `GameTheme.arm_ui_press(btn, cue)` is the explicit opt-in, now called from
SettingsOverlay, Collection, Credits and NetLobby — the four files that held
zero `play_sfx` between them. In MainMenu the same job is done by
`_arm_shell_button`, which also carries the scale.

> **One gate finding worth keeping.** The funnel was first written as
> `play_sfx("ui_" + kind, …)`. `tools/_probe_audio_cues.gd` scans for
> `play_sfx("<literal>")` and reported the entire shell as **one silent cue
> named `ui_`** — and a grep for `ui_commit` would have found no call site at
> all. It is now four literal calls in a `match`. Same house lesson as the
> relic `effect` strings: *a name assembled at runtime is a name nothing can
> verify.*

### ❖2 — the forward move is plated and already burning

`MainMenu._make_primary_action` — the missing sibling of
`_make_secondary_action`. Warm parchment tab, gilt rule, and **the flame lit at
rest** (`TAKE_FIELD_FLAME_REST = 0.82`); hover brightens it rather than igniting
it, so the forward move is the one thing on the screen already alight. Applied
to every muster step's forward nav via `_build_muster_nav`, to Quick March's
SEE YOUR COMPANY (which built its own row and so had inherited nothing), and
TAKE THE FIELD's two flames now rest lit as well.

Two layout faults this surfaced, both fixed: the primary carried `EXPAND_FILL`
(harmless on a frameless word, a **900 px bar** once the plate was visible) —
now measured to `NAV_PRIMARY_W = 340` and centred on the canvas by a spacer pair
plus a dummy mirroring BACK; and `_make_menu_button` hands *every* button
`EXPAND_FILL`, so BACK's cell took a third of the row and pushed the plate
~140 px right of centre — BACK is now `SHRINK_BEGIN`.

The stale "visual hierarchy comes from per-button COLOR" comment in
`_rebuild_menu` is replaced with an account of what the three live channels
actually are, and a warning not to trust the dead `_bg` argument.

### ❖3 — hover and press

`_arm_shell_button(btn, cue, hover_scale)`: hover 1.035 → press ×0.955 → release,
at 0.14 / 0.06 / 0.10 s. Only on buttons ≥ 40 px (a 1.04 lift on a 17 px word is
a wobble, not a lift). Gates on Reduce Motion — the scale is decorative; **the
audio does not**, because a player who turns motion off has not asked for
silence. `pivot_offset` is re-read at press time, not at build time: these
buttons are laid out by a VBox that has not run when the helper is called, so a
pivot captured there is always `Vector2.ZERO` and the grow reads as a lurch.

### ❖4 — the accepted term is sealed

`WaxSeal` replaces the word CHOSEN, pressed down under a 0.16 s stamp — and only
on the *transition* into chosen, so a deal refresh does not re-stamp a term
accepted seconds ago. **The seal bears a device**, which the first render proved
necessary: `WaxSeal` draws an impression (a sunk dark face) because on a card
that recess holds the stat numeral, and pressed empty it read as a washer. It
now carries the slot's own Roman numeral, and THE PACT — which deliberately has
no numeral — takes the house diamond. Square by necessity (`TERM_SEAL = 30`):
`WaxSeal` works off `min(size.x, size.y)`, so the original 34×26 host drew a
26 px seal floating in a 34 px box.

### ❖5 — the tutorial teaches the object, not its name

`GameTheme._htp_writ_mini` + `_htp_open_slot_mini` replace the octagons reading
`CARD` and `SLOT`, built from the card's own painters (`WritLeaf`,
`ParchmentPlate`, `WaxSeal`) and the board's own (`EmptyPlateSigil`).

**★3 was failed once on the way in and the arithmetic is why:** the first cut
was 44×62 with a 34×24 art mount — 53 % of the leaf's area was one dark
rectangle, and it rendered as a black box on a white box with no card grammar
left. At 56×78 the six things that identify a card across a table all survive:
cost seal high-left in Command blue, dark art band, gilt fillet, two written
lines, two wax stat seals at the feet. The name cartouche and the rules text do
not survive and are not attempted.

### ❖6 — the hero gets the pane

Portrait 230 → **400 wide** inside a real plate with a faction-tinted fillet.
The copy column gets narrower and therefore taller, closing the void from the
other side. `RECOMMENDED FIRST HERO` **moved** (not copied) out of the pane's
far corner onto the roster row as `START HERE`, where the advice is in front of
the player before the click. The remaining space under the traits is filled with
the **signature relic** — icon, name and rule — because the void's honest
occupant is the other half of what picking a lord hands you, and the screen was
pitching only the deck.

### ❖7 — settings footer

`RESUME` was a frameless `make_back_button` standing beside a plated `APPLY` —
the most-pressed control on the overlay and the only unstyled thing on it.
(`make_back_button` is frameless by design and right everywhere else; what
breaks is standing it next to a plaque of the same size.) Now ordered the way
this game orders every pair — subordinate first, forward move last and warmest,
the same grammar as `_build_muster_nav` — with the destructive row pushed from
6 px to 14 px so it reads as a different class of action rather than as one
four-button cluster with an accidental line break.

### ❖8 — the meadow burns with your record

`_add_menu_embers` reads `MetaState.total_runs` through a soft
`sqrt(marches/40)` curve: count 40 → 96, velocity and peak heat rising with it,
so a deep profile gets a hotter fire rather than just a denser field of
identical motes. **Keyed to marches, not victories** — a player 30 defeats deep
has spent the most time on this screen and earned the most changed version of
it; keying to wins shows the least to whoever has seen it most.

`_build_campaign_record` replaces the lone grey stats line: `TallyMarks` in
fives for marches, a `WaxSeal` per victory (capped at five), **with the sentence
kept underneath** at the same size and colour — the marks are what you feel, the
words are what you read, and a record legible only by counting scratches is a
worse record.

> `TallyMarks` gained `pitch` and `ink_color`, both defaulted, because the
> painter's rust-brown was mixed for a card's **parchment** margin and all but
> vanished on the menu's warm-black, and its 5 px strokes read as a smudge at
> footer scale. Card2D passes neither, so its record is byte-identical. This is
> the "obey the material" trap in miniature: a painter is tuned to the ground it
> was written for.

### ❖9 — the scrim's gradient ran the wrong way, and only measuring showed it

Deferred twice on the grounds that it needed measurement rather than an eyeball.
Measured (PIL, sampling `_runstart_menu.png` — whose right half is unscrimmed
art) it turned out not to be a "retreat the scrim" problem at all:

| art band | luminance |
|---|---|
| upper sky | p90 **0.047** — nearly black already |
| fire wall (y 450–800, the MIDDLE) | p90 **0.203**, max 0.433 |
| lower meadow | p90 **0.066** — nearly black already |

The bright band is the **middle**. The ramp was 0.56 at the top → 0.78 at the
bottom, on the stated reasoning that the bottom is "where the fire is" — so it
put its heaviest wash over some of the darkest art in the frame, its lightest
over the darkest, and left the actual fire wall on ~0.68. It was spending the
painting everywhere except where spending it bought anything.

Re-weighted to the middle (0.42 · 0.62 · **0.74** · 0.52). This is a legibility
**improvement**, not a trade:

| band | old α | old contrast | new α | new contrast |
|---|---|---|---|---|
| sky | 0.56 | 12.6:1 | 0.42 | 10.8:1 |
| fire wall | 0.68 | **4.6:1** | 0.74 | **5.2:1** |
| meadow | 0.78 | 12.9:1 | 0.52 | 10.4:1 |

Re-measured on the shipped frame, the background bands read p90 0.035 / 0.079 /
0.027 — 10.6:1, 7.0:1, 11.8:1 for ivory ink. The knight and the fire are visible
again through the bottom half of every subscreen, and the worst-case contrast
went up.

**If you change these, re-sample the art.** The whole reason the ramp was
backwards is that the fire *looks* brightest at the foot of the composition and
*measures* brightest in the middle.

### Second round — the screens the hunt hadn't rendered

The slate above was written from the frames I had. Four more screens were shot
and read afterwards; two carried faults worse than anything in the original
slate.

**LOAD GAME was three flat colour rectangles.** `_make_slot_row` gave each slot
a saturated FILL — olive `(0.32,0.26,0.14)` for a waiting run, dull red for a
damaged one, warm charcoal for empty — so three list rows read as three
unrelated widgets, and the olive one was **the single brightest object on the
screen**, out-shouting its own title. Flat colour fills are also the one thing
the house style rules out outright.

The kit had already solved this and said so in as many words —
`make_themed_button`: *"the caller's `bg` becomes the accent keyline, so a
button that MEANS something survives as ink while the button stops reading as a
generic UI rectangle."* Every slot is now the house dark doc-tile with the state
in the **keyline and the title ink**: gold = a run waiting · ember = a run this
build cannot read · red = about to be replaced · bronze = empty. The delete X
was a red fill at chamfer 8 against the row's 5 (a loose badge floating off the
list) and now matches its row. BACK was out-dented by exactly the 28px flame
slot — same structural fault and same fix as `_build_muster_nav`'s BACK.

**TAKE THE FIELD became the odd one out — a fault this pass introduced.** Giving
steps I–III a plated primary meant the walk taught one shape three times and
then changed it on the one press that matters. It keeps everything that made it
the climax (27px against the tabs' 19, two flames instead of one, its own
underline) and now sits on the same plate at 470px, so the four steps read as
one escalating gesture. Both `_make_begin_button` call sites and the
`next_control` branch of `_build_muster_nav` gained the same centring.

**Step IV's chosen-term tile was the muster's largest remaining void** — a
full-width `EXPAND_FILL` slab, ~1400 of its 1840px empty, with the road preview
below it as a centred paragraph on bare canvas with no plate at all. They are
the same question asked twice ("what did I agree to" / "what am I walking
into"), so they are now one row of two panes: CHOSEN TERM beside THE ROAD AHEAD.
The width goes to content instead of margin, the road preview gains the plate it
never had, and the band below shrinks by the height the paragraph occupied.

### The lobby, and a stale-frame trap worth naming

I read `_menus_net_lobby.png`, wrote a critique of a screen that "leads with two
large dead panels", and was **entirely wrong**: the frame was dated **2026-07-18**
and `_shot_menus_audit` does not shoot that state at all. The lobby had already
been restructured to lead with what works, and the divider strings I was reading
(`FACE A FRIEND`, `OR DRILL SOLO`) do not exist in the source — which is what
caught it.

The trap is specifically the **prefix collision**: an orphan sharing the
`_menus_*` naming of a live harness sits in the same directory looking like part
of the fresh batch. Two more of the same class existed (`_runstart_setup_*` ×4,
`_runstart_step3_advanced|asc5` — states the runstart harness renamed to `step4`
and left behind). All seven removed; they are gitignored harness output and
regenerable. **Check a frame's mtime against the run you just did.**

On the *real* lobby (`_shot_more_menus`, which does shoot it), two genuine
finds: `GREEN` was `Color(0.55,0.78,0.70)` — a light saturated **teal**, the
single cold element on an all-ember screen and the exact `b >= r` cyan tell the
project logs as its #1 art defect. It is a real status channel (10 call sites:
host / ready / connected), so it was warmed rather than deleted — `g` stays high
or it stops meaning *go*, `b` drops well under `r`. Its sibling `AZURE` had
already been remapped to gilt for the same reason; this one was missed. And
`JOIN` was a frameless `make_back_button` standing between two filled LineEdits
— the only boxless thing in its row, reading as a caption after the port number.
Plated. (Same fault as the settings RESUME: frameless is right until it stands
beside a plate.)

### Fourth round — "then the most": the in-run shell

The exposure ladder at §0 says the title screen is seen most, and that is true
per *launch*. Per *hour*, it is not close: a run passes REWARD after every
fight — ~21 times — against the title screen's once. So the forward move on the
in-run shell matters more than anything on the menu column, and all three of
them were frameless `make_back_button`s:

| screen | control | was | now |
|---|---|---|---|
| Reward | "Continue" | frameless — **the most-repeated press in the game outside combat** | primary plate |
| Shop | "Leave the Wagon" | frameless (worded as a departure; it is the only way on) | primary plate |
| Wayside (result) | "Continue" | frameless | primary plate |

`GameTheme.make_primary_button` is the funnel — the counterpart
`make_back_button` never had, whose own header notes it was also serving "light
primary confirms". Deliberately **without** MainMenu's flame: the igniting flame
is the title screen's motif for a menu column, and a second grammar in the run
would read as an unrelated device.

**The first cut of this was too broad, and the render caught it.** Converting
Wayside's shared `_add_leave_button` wholesale made "Leave it buried" — the
DECLINE standing beside three live offers on the supply cache — the loudest
control on a screen whose entire point is the offers above it. The helper now
takes an explicit `primary: bool`, because what the button MEANS is the caller's
to declare and is not inferable from its label: five call sites are declines
(frameless, `ui_back`), two are result-screen forward moves (plated,
`ui_commit`). Treasure's "Take N Gold instead" and Recruit's "Turn Them Away"
were already correctly secondary and were left alone.

**The `button_click` audit** promised at the end of round one. Of the 23 sites,
most are gameplay beats (minigame props, the map march, Combat's initiative) and
were left alone — they are not menu presses and have their own audio design.
Three were shell and were converted: Reward's forge pick (`select`), Reward's
next-lord pick (`commit` — it sets the route for the rest of the act), and
Combat's chronicle drawer, which is UI furniture and now audibly opens and
closes (`select` / `back`). Each one freed from `button_click`, which is also
the `SFX_FALLBACKS` stand-in for six unrelated gameplay cues — so the battle log
had been sounding exactly like a doom tick.

**Noted, not fixed (out of a menu pass's scope):** one of the two relics dealt
in an earlier Reward roll had a strongly cyan icon, and the Wayside forest
backdrop is a saturated night blue — both painted assets, not layout, and the
project's #1 recorded art defect. Separately, a vanilla creature (Curtain Wall,
1/7 Bastion) prints an *empty* ruled text box in the shop, which reads as
missing data rather than as "this card has no rules"; that is a Card2D layout
question affecting every screen that shows cards, so it wants its own decision
rather than a unilateral change here.

### Fifth round — the sweep finished, and one bug found per-LINE not per-screen

Every remaining shell screen rendered and read: Rest, Treasure, Recruit, Game
Over, Collection, muster step II, Credits, and the real skirmish lobby.

**Four need nothing.** *Rest* is the best-composed screen in the build (left
command column, living campfire on the right — the Hades grammar, executed).
*Game Over* is the best still frame, exactly as the sibling hunt said: a deckled
chronicle page, ruled ledger bands, and a crimson wax seal reading **SEALED
XXIV**. Its MARCH AGAIN is a red-ruled bracket rather than the warm plate this
pass introduced elsewhere, and that is **correct** — the page is dark ink on
light parchment, so a gilt-on-dark tab would be foreign to its material. *Muster
step II* and *Collection* are both in good shape.

**The one real find was a colour, and it is instructive that it took a sweep.**
`RunState.season_line()` renders in **three** places — the muster's ORDERS pane,
Recruit, and the map overlay — and all three carried `Color(0.64, 0.74, 0.60)`,
a sage green: `g >= r`, the project's cold-ink tell. The 2026-08-03 pass warmed
the muster's copy and called it *"one of the last two live instances in the
opening"* — which was true, and was the trap: the fix was made **per screen**
when the defect belonged to the **line**. On Recruit that sage was the one cool
element over an open-flame backdrop; on the chart it sat directly under a
kingdom line already at 0.86/0.82/0.70, so the pair read as two unrelated
captions. Both warmed to the muster's value.

(`Combat.gd`'s `"verdant"` at a near-identical value is an *atmosphere fill*,
not ink — a green arena is allowed to be green. Left alone.)

**Also noted, not fixed:** the Relic Cache is still "a dialog box on a painted
forest" — the sibling hunt's §✱ item, and true: the road's stops have props and
this one uses none of the kit's thirty painters. That is a build, not a polish.

### Sixth round — the Relic Cache gets a prop, and the compile gate gets fixed

**`scripts/ui/painters/CacheChest.gd`** (new). The Relic Cache was the one
roadside stop staging nothing — every sibling has a prop (the knucklebone patch,
the sappers' kegs, the quartermaster's scale, the Fourth's strongbox) and the
stop whose entire copy is *"Relic Uncovered"* showed a dialog tile on painted
grass. Both 2026-08 hunts logged it; this closes it.

An iron-banded strongbox, **sunk** rather than standing: spoil banked against its
foot and over it, the box cut off at the earth line, the lid thrown back. One
light top-left (the `WaxSeal` convention) so the mouth's far wall is lit and its
near lip occludes — the inversion that makes a hole read as depth rather than as
a black rectangle. `open_t` drives lift, foreshortening, mouth depth and the
find's glow together, so the reveal is one property tween; Reduce Motion gets the
box already open, because the state has to land.

Three render passes, each correcting something the previous one got wrong, all
measured off the frame rather than guessed:

1. **560×300 was too small.** Behind a ~390px tile the box showed ~85px either
   side and nothing above — two tan slivers, not a container. A prop something
   sits *in* must be plainly bigger than the thing: 860×440, staged 520 tall so
   the lid clears the tile's top edge.
2. **The oak was pale cardboard.** At 0.36 luminance it out-lit the night forest,
   and one flat fill over 860×440 has no material in it. Darkened to 0.258, with
   a four-step darkening wash down the front face and plank seams drawn as a
   *pair* of lines (dark gap + lit arris) so they read as boards, not pinstripes.
3. **The lid's inner face became the biggest, flattest shape on the prop.** A lid
   thrown fully back is seen almost edge-on, so it is now a narrow band
   (squash 0.42 → 0.26) with its underside in its own shadow (`OAK_DK`, lifted
   only by the find's glow) and a bright arris along the top edge, which is what
   actually reads at this size.

**Finished in a fourth and fifth pass**, both driven by a 3× NearestNeighbor
crop of the flank rather than by the full frame:

4. **The ironwork was the missing tell, and it had to go where the prop is
   VISIBLE.** The relic tile covers the box's middle ~390px of 860, so anything
   drawn centre-front is drawn for nobody. Bands widened, **rivets** added on
   the flanks only (one detail says "banded iron" faster than any amount of
   shading), plus corner brackets wrapping each front edge — without them the
   horizontals just float on the wood — and sparse full-height grain hairlines,
   skipped entirely across the hidden middle.
5. **The find's glow was banding.** Three stacked ellipses at α 0.20 over a
   near-black mouth left every rim plainly visible, so the light read as a
   smudge with hard edges. Seven steps at α 0.085 with constant-ratio radii, so
   no two rims coincide and each is under the banding threshold. Same rule the
   map plate learned: *organic must stay smooth.*

The crop after: lid arris, lit far wall of the mouth, corner bracket, riveted
bands, plank seams and spoil all read individually at pixel level.

**And the compile gate was lying.** Mid-build, parsecheck failed on `Event.gd` —
a file this session never touched, whose only diff was three copy strings. Three
consecutive runs on an identical tree gave **PASS · PASS · FAIL**, naming a
*different* file each time. See `tools/_probe_parsecheck.gd`'s new header for the
full account: `reload(true)` over ~117 scripts momentarily invalidates the class
type another script reads an autoload member through, so whoever is swept while
the graph is torn fails to infer `var rm := UserSettings.reduce_motion`. It is
the `--check-only` autoload false positive reaching the scene-based gate.

Fixed with a post-sweep retry — failures are collected as suspects and re-tried
once the graph is whole. A real compile error is deterministic and fails both
times, **verified by planting a genuine syntax+semantic error and confirming the
gate still fails on it**. Recovered scripts are printed, so a flaky run stays
visible rather than silently smoothed. Five consecutive clean runs after.

### Gates run

`_probe_parsecheck` (116 scripts) · `_probe_audio_cues` (34 cues resolve) ·
`_probe_text_floor` · `_probe_copy_lint` · `_probe_muster` · `_probe_menu` ·
`_probe_terms` — all pass. Eyes: `_shot_runstart` (26) + `_shot_menus_audit`
(10), re-read after each stage.

---

## Sources

- [Best Practices for Game UI Sounds — SFX Engine](https://sfxengine.com/blog/best-practices-for-game-ui-sounds)
- [Approaching UI Audio from a UI Design Perspective — Audiokinetic](https://blog.audiokinetic.com/approaching-ui-audio-ui-design-perspective-2/)
- [Game UI/UX Design Principles: HUD, Menus, and Feedback Systems That Work — StraySpark](https://www.strayspark.studio/blog/game-ui-ux-design-principles)
- [The four horsemen of game UI design — Corporation Pop](https://corporationpop.co.uk/thoughts/game-ui-design)
- [Beyond the HUD: The Power of Diegetic Interfaces — Wayline](https://www.wayline.io/blog/diegetic-interfaces-game-design)
- [Multiple Title Screens – An Anatomy Of Visual Novels — Fuwanovel](https://forums.fuwanovel.moe/blogs/entry/4131-multiple-title-screens-%E2%80%93-an-anatomy-of-visual-novels/)
- [10 of the best title screens and main menus in video games — Rice Digital](https://ricedigital.co.uk/10-of-the-best-title-screens/)
- [My 10 Favorite Main Menus in Gaming — The Game Campaign](https://thegamecampaign.wordpress.com/2025/07/04/my-10-favorite-main-menus-in-gaming/)
