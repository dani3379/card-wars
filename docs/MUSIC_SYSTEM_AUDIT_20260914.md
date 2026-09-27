# The music: why it sounds weird, and what to do about it

**2026-09-14.** Measured, not guessed. Every number below came from running
`ffmpeg loudnorm` (EBU R128) over all 49 shipped tracks and from rendering the
game's own crossfade law onto real assets and metering the result. The scan
output is reproducible with `tools/remaster_music.sh` and the fade claim is
gated by `tools/_probe_music_fade.tscn`.

**One thing this document cannot do: listen.** Everything in §1 is a measurable
defect and I am confident about it. Everything in §3 is a design argument, and
where it is a taste call I have said so rather than dressed it as a finding.

---

## 0. The short version

The tracks are not the problem. Scott Buckley and Nakarada are good and the
library is well curated. Three things sit *between* those tracks and the player:

| | Defect | Status |
|---|---|---|
| 1 | Every music transition drops out by **21 dB** in its middle. ~108 times a run. | **FIXED** |
| 2 | The library spans **13.9 LU**, with up to **8.6 LU of that inside a single random pool**. Six tracks clip. | **FIXED** — re-mastered to **0.53 LU**, adopted |
| 3 | The system is built to **never let a theme repeat**, so no tune is ever learned, and every screen change pays defect 1. | **FIXED** |

Plus the thing that was never a defect, only an absence: act 1's fights now play
a **layered cue whose arrangement answers the board** (§Step 6, prototype).

Defect 1 is most of "sounds weird." Defect 3 is all of "players get sick of the
songs" — and it is caused by the feature that was added to prevent it.

---

## 1. The measured defects

### 1.1 The crossfade had a hole in it (FIXED)

`AudioBank._start_music_stream` faded tracks with two parallel tweens:

```gdscript
tw.tween_property(incoming, "volume_db", 0.0, fade_seconds)          # -40 -> 0
tw.tween_property(outgoing, "volume_db", FADE_QUIET_DB, fade_seconds) #  0 -> -40
```

That interpolates **linearly in decibels**, which is *exponential in amplitude*.
At the midpoint both tracks sit at −20 dB — a tenth of amplitude each. Two
tenths do not make a whole. The sum lands far below either endpoint.

Rendered on the real assets (`map.mp3` → `combat.mp3`, the shipped 1.0 s fade,
RMS metered every 100 ms):

```
steady state           -13.2 dBFS
old law, mid-fade      -34.4 dBFS     <-- a 21 dB hole
equal-power, mid-fade  -19.6 dBFS     <-- and that residue is the material,
                                          not the fade (combat.mp3 is
                                          genuinely quieter here)
```

The music audibly vanishes and climbs back, on **every screen change**. The act
skeleton is 18 rows, so a route makes ~18 stops per act, and each stop costs two
transitions (map → node, node → map; Reward plays no music of its own and rides
the combat track). That is **~108 dropouts per run**, every run. It is the
single loudest wrong note in the game and it has nothing to do with the
compositions.

The fix is the standard constant-power law — amplitude in `sin(t·π/2)`, out
`cos(t·π/2)`, so `in² + out² = 1` at every point. The conversion order is the
whole trick: **the law is defined on amplitude and the player takes decibels**,
so the sine has to be computed first and converted after. Running the curve on
`volume_db` directly is the bug, and it is also what every Godot fade tutorial
shows you, which is why it will come back if nobody gates it.

Also fixed in the same place: two crossfades could overlap, leaving one tween
driving a player the other had just started, with a trailing `stop()` callback
that killed live music. One tracked tween now, killed on entry.

Gate: `tools/_probe_music_fade.tscn` — drives `_crossfade_step` across t=0..1 on
the real players and requires the summed power to stay flat within 0.5 dB
(below the ~1 dB just-noticeable difference). Currently 0.000 dB over 99
samples. It also asserts `_fade_gain_db(0.0)` is finite, because
`linear_to_db(0.0)` is `-inf` and a non-finite `volume_db` write silently aborts
the function it is in.

### 1.2 The library is not levelled, and the spread is *inside* the pools

Integrated loudness, all 49 tracks: **−22.1 to −8.1 LUFS, a 13.9 LU range.**

That would be survivable if the loud tracks and the quiet tracks lived on
different screens. They do not — `play_music_random` draws from pools, and the
spread is worst *within* pools:

| Pool | Spread | Quietest → loudest |
|---|---|---|
| Event (bone/ember, and default) | **8.6 LU** | `event` (−18.1) → `event_b` (−9.5) |
| Map, act 1 | **7.9 LU** | `map_b` (−22.1) → `map` (−14.2) |
| Combat, act 3 | **5.5 LU** | `combat_act3` (−15.9) → `combat_act3_c` (−10.4) |
| Map, act 3 | **5.3 LU** | `map_act3` (−17.9) → `map_d` (−12.6) |
| Combat, act 1 | **5.0 LU** | `combat_act1_d` (−15.7) → `combat` (−10.7) |
| Shop | **5.0 LU** | `shop_c` (−13.1) → `shop` (−8.1) |
| Skirmish combat (12-track book) | **5.5 LU** | as act 3 |

~8 LU is roughly a doubling of perceived loudness. Two event screens in a row
can differ by that much, at random, with nothing in the mix compensating —
because nothing in the mix *measures*. This reads to a player as "the audio is
inconsistent" long before they could name it as loudness.

(The pools that are tight — MainMenu 0.3 LU, Boss 0.7, Elite 0.8 — are tight by
accident: they happen to be all-Buckley, and he masters consistently.)

### 1.3 Six tracks clip, and nothing was watching the ceiling

True peak above 0 dBFS, so they distort on decode before the mixer sees them:

```
event_b        +0.84 dBTP
combat_act2_c  +0.80
shop_c         +0.59
combat_act2_d  +0.23
combat_act3_c  +0.15
shop           +0.14
```

Worse, `UserSettings._setup_audio_buses` built Master / Music / SFX at runtime
with **no effects on any of them**. Music plus up to 12 concurrent SFX voices
summed with no ceiling at all, and a clash fires 8–13 cues a round. The overflow
hard-clips at the driver — audible as a crackle or a brief tearing on exactly
the loudest, busiest moments, the ones meant to feel best.

**FIXED** this pass: an `AudioEffectHardLimiter` on Master at −0.5 dB ceiling.
It is transparent until the signal actually reaches the ceiling, so it changes
nothing on an ordinary frame. It is a safety net, not a loudness stage —
`pre_gain_db` stays 0, and a track that rides it constantly should be
re-mastered, not leaned on.

### 1.4 Dynamics are all over the place

Loudness range (LRA) says how much a track breathes:

- **Brick-walled, LRA < 5** (no dynamics left): `shop` 1.0, `map_c` 1.8,
  `combat_act1_c` 4.0, `map_b` 4.1, `event_b` 4.4, `rest_b` 4.5.
- **Very wide, LRA > 14** (quiet passages will disappear under SFX):
  `victory` 19.2, `combat_boss_d` 18.2, `map_act3` 16.9, `victory_boss` 15.2,
  `combat_boss_e` 14.6, `credits` 14.2.

`shop` at LRA 1.0 is a flat wall of sound; `combat_boss_d` at 18.2 has passages
that will be buried by a single card-play cue. These are in the same game at the
same slider setting.

### 1.5 Format

All 49 files are **320 kbps MP3, 44.1 kHz — 446 MB**.

- **MP3 cannot loop seamlessly.** The encoder adds delay at the head and padding
  at the tail, and the format defines no standard way to record how much, so a
  looped MP3 inserts a short silence at the seam. The files are not even
  consistent: `map.mp3` carries a LAME gapless header, `combat.mp3` carries
  none at all. OGG Vorbis defines its start and end precisely and the padding is
  trimmed on decode — it removes the question instead of managing it.
  `MUSIC_CREDITS.md` already recommends OGG. Nobody did the conversion.
- `combat_act2_c` and `event_b` carry **embedded JPEG cover art** that is decoded
  and thrown away.
- 320 kbps is far past transparency for background music under gameplay. OGG q5
  lands the library at **215 MB** (measured, all 49 files) — less than half.

This one is real but rank it last: tracks run 2–7 minutes and most screens are
left before a loop comes round, so the seam fires far less often than the
transition does.

---

## 2. What the craft actually is, below the slogans

The useful distinction is not "who composed it" but **what unit of music the
engine plays**. There are exactly two ways to make music respond, and every
middleware (Wwise, FMOD, Elias) is an implementation of one or both.

### 2.1 Horizontal re-sequencing — changing *what* plays, in time

Music is cut into segments with defined entry and exit points, and the engine
splices at musically legal moments. The low-level details that make it work and
their absence is exactly what "sounds like a media player" means:

- **A cue is not a piece.** A piece is intro → build → climax → resolution. A
  cue is `intro segment` + `loop body with no destination` + `outro/stinger`.
  The loop body is deliberately *harmonically static* — a vamp, a pedal, an
  ostinato that does not resolve — because a passage that is going somewhere
  cannot be repeated without promising something it won't deliver.
- **Transitions land on musical boundaries, not on frame boundaries.** Next
  beat, next bar, or end-of-segment. A change that lands on the downbeat reads
  as intentional; the identical change landing 300 ms into a bar reads as a
  glitch. This is the single biggest "professional vs amateur" tell in game
  music, and it is a scheduling problem, not a composition problem.
- **Re-entry point is a decision, not a default.** Three options: from the start,
  from the same playhead position as the outgoing track, or from where this
  track was last left. Each is right in different places and picking wrong is
  audible.
- **Stingers cover the seam.** A short transitional hit played *over* the splice
  masks the join and makes it read as punctuation.

### 2.2 Vertical re-mixing — changing *what plays at once*

The same bar of music, with instrument layers muted and unmuted. Percussion in
when the fight escalates, strings out when the board empties. Because every
layer is the same bar of the same piece, there is no transition to get wrong —
you are only changing the *arrangement*.

This is the technique that solves fatigue, and the reason is worth stating
plainly: **a listener fatigues on an unchanging signal, not on a familiar one.**
Repetition is how music is learned and remembered at all. Margulis's work on
repetition finds the exposure effect raises liking *then* reverses — the reversal
comes from literal, unvaried repetition. A theme you have heard fifty times but
never twice in the same clothes does not trigger it; it becomes *the game's
theme*.

### 2.3 The mix techniques

- **Sidechain ducking.** A compressor on the music bus whose detector listens to
  the SFX bus. Music steps back automatically the instant an impact lands and
  returns after it. This is how AAA gets impacts to read without turning the
  music down permanently.
- **Frequency carving.** The game's SFX vocabulary — paper, wood, wax, metal —
  lives around 1–4 kHz. A 2–3 dB dip there in the *music* bus buys every card
  cue clarity without any level change a player could notice.
- **One loudness target, one ceiling**, applied to the assets, not the mixer.
- **Silence is a device.** Constant music guarantees fatigue because it removes
  the contrast that makes music mean anything. Minecraft, Journey and Hollow
  Knight all use long silences deliberately. The road is where a player spends
  the most cumulative time making the least intense decisions — it is exactly
  where silence is affordable, and the fight music hits harder for it.

### 2.4 Godot 4.6 already ships this

The project is on 4.6 and **Godot 4.3 added the whole interactive-music layer
natively** — no middleware, no licence:

- **`AudioStreamInteractive`** — clips plus a transition table. Per-transition:
  `from_time` (`IMMEDIATE` / `NEXT_BEAT` / `NEXT_BAR` / `END`), `to_time`
  (`START` / `SAME_POSITION` / `PREVIOUS_POSITION`), `fade_mode`
  (`DISABLED` / `FADE_IN` / `FADE_OUT` / `FADE_CROSS` / `FADE_AUTOMATIC`),
  fade length **in beats**, and an optional filler clip for stingers. BPM and
  beat count are set per-file in the Import tab. Runtime switching is
  `get_stream_playback().switch_to_clip_by_name(&"name")`.
- **`AudioStreamSynchronized`** — vertical layering; N streams in lockstep with
  per-layer volume driven from script.
- **`AudioStreamPlaylist`** — sequential/shuffled playback with fade.

They nest: `AudioStreamSynchronized` inside `AudioStreamInteractive` gives
layered cues with beat-matched transitions between them, which is functionally
what Wwise does.

---

## 3. What to do, in order of payoff per hour

### Step 1 — the two fixes already landed

Equal-power crossfade + master limiter. Free, no assets touched, no design
decision. This alone removes the worst artefact.

### Step 2 — level the library — **ADOPTED 2026-09-14**

`assets/audio/music/` now holds **49 OGG Vorbis files and no MP3s.** The MP3s and
their `.import` sidecars are deleted from the working tree and still present at
`HEAD`, so `git checkout -- assets/audio/music/` reverts the whole swap.

Verified after the swap, not just before it: all 49 decode clean with durations
matching the originals to within a second; all 49 `load()` as
`AudioStreamOggVorbis` with `loop` available (197.3 min of music); and the real
async path — threaded load → `_start_music_stream` → crossfade — was driven
end-to-end on four tracks plus `play_road_theme(2)`, which resolved to
`map_act2` and played. Gates: `music_wiring` 42/42, `audio_cues` 34/34,
`music_theme` 52, `music_fade` 102.


`tools/remaster_music.sh [target_LUFS] [out_dir]` measures each track, applies a
**static gain** and encodes OGG Vorbis into a **side folder**. It never touches
`assets/audio/music`.

Static gain is chosen deliberately over `loudnorm`'s dynamic mode: dynamic mode
reshapes the program and would flatten the wide tracks, and `combat_boss_d`'s
18 LU of range is the point of `combat_boss_d`. Where a static gain would breach
the −1.5 dBTP ceiling the gain is *reduced* instead — a hair quieter beats
squashed.

Default target is −16 LUFS, near the library's current median, so the existing
SFX levels stay balanced. **The win here is consistency, not loudness** — do not
read −16 as a recommendation about how loud the game should be.

**Measured result**, after two passes (the second is §"the bug the verification
scan found", below — the first pass left seven tracks over the ceiling):

```
library spread     13.9 LU  ->   0.53 LU
range          -22.1..-8.1  ->  -16.50..-15.97 LUFS
tracks clipping          6  ->   0
above -1.5 dBTP          -  ->   0   (worst now -1.50)
size                446 MB  ->   215 MB
LRA cost                 -  ->   mean -0.04 LU, worst -0.50
```

Every pool — all 17 — now lands inside **0.5 LU**, against 8.6 LU at the worst
before:

| Pool | Before | After |
|---|---|---|
| Event | 8.6 LU | **0.15** |
| Map act 1 | 7.9 LU | **0.01** |
| Combat act 3 | 5.5 LU | **0.44** |
| Combat act 1 | 5.0 LU | **0.03** |
| Shop | 5.0 LU | **0.01** |
| Victory | 4.8 LU | **0.01** |

**Where static gain hits its limit** — a track that is quiet *and* peaky cannot
be raised by gain alone, because the peak reaches the ceiling before the average
reaches the target. Four tracks were in that state, and on the first pass the
script backed their gain **off**, so three ended up *quieter* than they started:

```
map_b      -22.1 -> -19.9   (wanted +6.1 dB of gain, could only take +2.1)
event      -18.1 -> -18.5
map_act3   -17.9 -> -18.4
map_e      -16.7 -> -18.2   (true peak was -0.05 dBTP; it could only go down)
```

### The limiting pass — **DONE 2026-09-14**

Those four were re-done **from the original masters recovered out of `HEAD`**,
not from the OGGs — re-encoding the already-encoded files would have stacked a
second generation of lossy loss on top. A look-ahead limiter (`alimiter`, `asc`
on) sits *ahead* of the gain, and the script converges on the target:

```
                I(in)    gain   I(out)  TP(out)   dLRA   peak reduction
event          -18.10   +2.54   -16.16   -1.61    -0.5      3.0 dB
map_act3       -17.89   +1.89   -16.24   -1.50    -0.1      2.4 dB
map_b          -22.05   +6.05   -16.05   -1.73    -0.1      4.2 dB
map_e          -16.73   +0.73   -16.04   -1.57    -0.1      2.2 dB
```

**`dLRA` is the column that matters.** 2.2–4.2 dB of peak reduction cost at most
**0.5 LU** of loudness range, and 0.1 LU on three of the four — the limiter is
catching transients, not squashing programme. That is the difference between
mastering and damage, and it is measurable rather than a matter of opinion.

**A second oracle that turned out not to be one, recorded so nobody re-runs it
and panics.** Crest factor (peak − RMS) on the four moved −4.10 / −2.52 / −2.16 /
−2.25 dB, which looks alarming until you notice those are *exactly* the peak
reductions. They have to be: the gain raises RMS by the full amount while peak
rises by (gain − reduction), so crest falls by the reduction by construction. It
restates the input, it does not check it. The number that actually answers the
question is the **absolute** crest — these tracks land at **16.0–17.6 dB**, where
commercial masters typically sit at 8–12 dB, so they remain far more dynamic than
most released music. LRA stays the independent signal because it measures how
loudness is distributed over musical time rather than peak-to-average at a point.
(The measurement itself needed one fix: `astats` prints at info level, so
`ffmpeg -v error` silently suppresses it and every track reads 0.00 — a uniform
result across all cases is almost always a broken oracle. Untouched tracks now
read exactly +0.00, which is what validates it.)

Result:

| | before | gain only | + limiting |
|---|---|---|---|
| Library spread | 13.9 LU | 3.98 LU | **0.53 LU** |
| Map act 1 pool | 7.9 LU | 3.90 LU | **0.01 LU** |
| Event pool | 8.6 LU | 2.52 LU | **0.15 LU** |
| Combat act 1 pool | 5.0 LU | 0.37 LU | **0.03 LU** |
| Shop pool | 5.0 LU | 0.01 LU | **0.01 LU** |
| Worst pool remaining | — | — | **0.47 LU** (combat act 3) |
| Tracks clipping | 6 | 0 | **0** |
| Tracks above −1.5 dBTP | — | 7 | **0** |

Every track in the game now sits between **−16.50 and −15.97 LUFS**, worst true
peak **−1.50 dBTP**, and the whole exercise cost a mean of **−0.04 LU** of
loudness range across 49 tracks (worst single track −0.50).

**The limiting is now part of the tool**, applied only to tracks that need it and
reported per-file, with the gain-only path still reachable via `MAX_LIMIT_DB=0`.
A track needing more than 5 dB is flagged as wanting *replacement* rather than
processing — that threshold is a judgement, but an explicit one.

Reproducibility was checked rather than assumed: re-running the tool over the
same four originals produces files whose **decoded PCM is bit-identical** to what
shipped. (The container bytes differ — Ogg bitstream serial numbers are
randomised per encode — so compare PCM, never file hashes.)

One method note worth keeping: `alimiter`'s `level` option defaults to **true**,
which auto-normalises the output back to 0 dB and would silently discard the
gain staging entirely. It must be `level=false`. And it measures *sample* peaks,
so its threshold sits at −2.0 dB to leave room for inter-sample true peak — the
script verifies by measuring the output's true peak rather than trusting the
setting.

### The bug the verification scan found in the script itself

The whole-library re-scan reported **seven tracks above the −1.5 dBTP ceiling**
(−1.42 to −0.97): `combat_act1_d`, `defeat`, `event_c`, `event_wry`, `rest_b`,
`rest_c`, `rest_d`. Six of the seven carried the note *"gain reduced to hold
−1.5 dBTP"* — they were the tracks the arithmetic was supposedly protecting.

Cause: the gain-only path computed headroom from the **input's** true peak and
never re-checked the result. `in_tp + gain` does land under the ceiling — *before
encoding*. Vorbis overshoots true peak slightly, and nothing measured afterwards.
The limiter path never had this bug because it iterates on the **measured
output**; the transparent path was trusting a prediction.

Fixed by making the gain-only path measure too: if the encoded output overshoots,
it restores the full target gain (which had been backed off to respect a ceiling
it was failing to hold anyway) and engages the limiter. Re-done from originals:

```
                 I(in)    gain   I(out)  TP(out)   dLRA   peak reduction
combat_act1_d   -15.74   -0.26   -16.06   -1.52    +0.0      0.4 dB
defeat          -16.49   +0.49   -16.04   -1.68    -0.1      1.1 dB
event_c         -15.41   -0.59   -16.05   -1.56    +0.0      0.0 dB
event_wry       -15.06   -0.94   -16.04   -1.54    -0.1      0.5 dB
rest_b          -17.40   +1.40   -16.04   -1.51    +0.0      0.5 dB
rest_c          -17.60   +1.60   -16.00   -1.85    +0.0      0.8 dB
rest_d          -16.13   +0.13   -16.03   -1.66    +0.0      0.8 dB
```

Nearly free — 0.0–1.1 dB of peak reduction and essentially no LRA cost — and all
seven now reach the target instead of being held short of it. That second fix is
what took the library from 0.95 LU to **0.53 LU**. **The lesson is the general
one: a prediction is not a measurement, and the path that felt safest to leave
unverified was the one that was wrong.**

Adoption needed no code change — `AudioBank._resolve_music_path` already tried
`.ogg` before `.mp3`. **Note the trap that creates:** an `.ogg` dropped beside an
`.mp3` of the same name silently wins, which is handy for auditioning and a
liability if you forget the loser is still on disk. `MUSIC_CREDITS.md` is updated
(filenames, the re-master note, and the residue below).

### Step 3 — stop the anti-repetition machine — **BUILT 2026-09-14**

This is the counterintuitive one, and it is the most important design change
here.

`play_music_random` **excludes the currently-playing track** from the pool. The
comment at `MapView.gd:65` says this is "so the road never drones on one loop."
The consequence is that returning to the map **guarantees a different track,
every single time**, and a run returns to the map after every node — 15+ times
per act.

So: no map theme is ever heard twice in a row, ever. Nobody can hum a Burning
Meadow tune, because no tune is ever established. And each of those forced
changes pays a transition. The feature added to prevent fatigue is what prevents
attachment.

The fix is the opposite of the instinct: **fewer tracks, heard more often, with
variation inside them.**

**What was built:**

- **`AudioBank.play_music_theme(key, pool)`** — draws once per key and holds.
  Key namespaces are load-bearing: `clear_music_themes()` (called from
  `RunState.start_new_run`) drops only `run:*`, so run-scoped themes re-roll each
  march while anything else survives the whole session.
- **One road theme per act, fixed for the run.** `AudioBank.play_road_theme(act)`
  over the `ROAD_BOOKS` const; `MapView` calls it instead of re-rolling. Act 2
  sounding *like act 2* is worth more than act 2 sounding like three things.
- **Variety moved to the axis where it costs nothing** — between runs, not
  between visits. A roguelike is played fifty times; inside one run the road
  theme is the thing you march to.
- **Wayside holds the road.** It used to crossfade into the *event* book for a
  ~20-second decision and back again — two transitions on the commonest
  non-combat stop, for a screen the fiction says you never left the march to
  reach. It now asks for the same road theme, which resolves to what is already
  playing, so `play_music` no-ops and the music simply continues. Arriving cold
  still starts it. **Events keep their own book precisely so that they, by
  contrast, land.**
- **The menu is session-stable** (key `menu`, no `run:` prefix). It was rotating
  three ways every time you backed out of a run; a game's front screen is its
  face.
- **Combat, elite, boss, event, shop and rest still rotate**, untouched — a
  fight or an event is a discrete thing with its own frame, and novelty is
  welcome there.

Measured effect on transition count: waysides are ~6 stops an act, at 2
transitions each, so this removes **~36 crossfades a run** on top of making the
remaining ones mean something.

**Gate: `tools/_probe_music_theme.tscn`** (52 checks) — the hold, the namespace
split, that it genuinely re-rolls between runs (60 trials), that `MapView` and
`Wayside` reach the road through the *same* call, and that `play_music` still
no-ops on the track already playing, since the wayside hold depends entirely on
that early return. Mutant-verified in both halves: reverting `MapView` to
`play_music_random` fires the two source checks, and making
`play_music_theme` re-roll every call fires the hold check.

It also owns a coverage hole it created: `ROAD_BOOKS` is a **const**, so
`_probe_music_wiring.gd`'s literal scan cannot see those track names — phase A
resolves all nine through `AudioBank._resolve_music_path`. `_probe_music_wiring`
itself was taught to match `play_music_theme(` while **skipping its first string
argument**, which is a key and not a track.

**Not built — `play_music("")` silence on quiet node types.** Still the right
idea (constant music removes the contrast that makes music mean anything), but
it is the one item here a player could mistake for broken audio, and it wants an
ear rather than an argument.

### Step 4 — the entry point problem

`_start_music_stream` resumes each track at its saved playhead
(`_music_positions`). The comment says this stops intros wearing out, and it
does — but the cost is that you now enter a *cinematic* piece at an arbitrary
moment: mid-swell, mid-cadence, or three bars from a climax that has no reason
to be happening. These are trailer-shaped pieces with dramatic arcs, and their
arcs no longer line up with anything.

Two options, and I would take the first:

1. **Cut loop bodies.** For each of the ~10 tracks that actually matter, find the
   60–90 s harmonically static section, cut it at bar lines, and loop *that*;
   the material before it becomes an intro segment played once on entry. This is
   what turns a piece into a cue and it is the highest-craft, highest-cost item
   on this list.
2. **Resume at the nearest bar**, not the exact sample. Needs BPM per track;
   crude but cheap.

### Step 5 — sidechain ducking (taste call, numbers ready)

A compressor on Music with `sidechain = &"SFX"` makes the music step back under
every impact instead of only under ceremonies. `duck_music` has exactly six call
sites, all in `Combat.gd`, and all of them are ceremonies — the killing blow,
defeat, victory, the boss entrance (×2) and a set-piece withdrawal. Nothing
ducks for an ordinary strike, so the whole clash competes with a full-level
orchestral mix. Suggested start: threshold −12 dB, ratio 4:1, `attack_us` 20,
`release_ms` 250.

The threshold matters: the hover cue sits at −17 dB and **must not** trigger it,
or the music pumps on mouse movement. −12 dB clears hover (−17) and catches
card-play (−7) and combat impacts.

I have not wired this, because whether music should breathe under card sounds is
a decision about how the game feels and I cannot hear the result. Say the word
and it is ten lines.

### Step 6 — vertical layering — **BUILT, EVERY SOLO FIGHT, 2026-09-14**

Every fight in the campaign — plain, General, and keep — plays **one cue whose
arrangement answers the board**, instead of a cue drawn at random. Ten layered
cues, 30 stems.

Combat keys the cue off the book's **anchor** (`book[0]`), so the layered cue and
the flat fallback are always the same piece of music and a missing stem set is
inaudible as a change of plan rather than a different song.

| fight | anchor | length | voices under bed | full | flat | Δ | climb |
|---|---|---|---|---|---|---|---|
| act 1 | `combat` (Nakarada, *The Great Battle*) | 197.8 s | 3.6 dB | −16.04 | −16.03 | 0.01 | 1.26 |
| act 2 | `combat_act2` (Buckley, *The Endurance*) | 253.0 s | 6.2 | −16.14 | −16.07 | 0.07 | 1.12 |
| act 3 | `combat_act3` (Buckley, *The Fury*) | 425.9 s | 9.3 | −16.58 | −16.50 | 0.08 | 1.00 |
| Generals | `combat_elite` (*March of Midnight*) | 164.8 s | 9.7 | −16.14 | −16.07 | 0.07 | 0.77 |
| the Everflame | `combat_boss` (*Juggernaut*) | 222.1 s | 7.6 | −16.13 | −16.06 | 0.07 | 1.08 |
| the Last Wall | `combat_boss_b` (*Song of the Forge*) | 205.9 s | **1.9** | −16.19 | −16.09 | 0.10 | **2.88** |
| the Grasswake | `combat_boss_c` (*Vanguard*) | 234.6 s | 10.6 | −16.15 | −16.08 | 0.07 | 1.78 |
| the Lanternhall | `combat_boss_d` (*Hour of the Witch*) | 217.1 s | 6.8 | −16.12 | −16.06 | 0.06 | **3.05** |
| the Owed | `combat_boss_e` (*The Summoning*) | 205.4 s | 10.8 | −16.14 | −16.07 | 0.07 | 0.39 |
| act 3 keep | `combat_boss_act3` (*Terminus*) | 263.4 s | 7.0 | −16.16 | −16.08 | 0.08 | 0.89 |

**Two cues need an ear on their muster round.** `combat_boss_b` and
`combat_boss_d` climb 2.88 and 3.05 LU from bed to full, against 0.4–1.8 for
everything else — on those two the choir carries the piece (the Last Wall's
voices sit only 1.9 dB under its bed), so the bed-only state is audibly *quiet*
rather than audibly *sparse*. On a keep that may be exactly right — a hushed
opening that crashes in on round 2 is a real device — but it is a judgement
someone should make deliberately. The build tool now prints a NOTE past 2 LU so
it cannot be inherited by accident.

**The target is the flat track's own loudness, not a global −16.** Getting this
wrong is instructive: targeting −16 flat made act 3's layered cue 0.42 LU louder
than the track it stands in for *and* pushed its full arrangement to −1.13 dBTP,
over the library's −1.5 ceiling — because `combat_act3` is itself one of the
quieter tracks at −16.50. Matching the flat track fixes both at once. The build
tool now measures the flat track and uses that as its target.

Intensity climb is 1.26 / 1.12 / 1.00 LU across the three — textural, not a
volume ramp, consistently.

**The stems were manufactured**, not commissioned: Demucs (htdemucs) separating
each act's original master recovered from `HEAD` — never the re-mastered OGG,
which would stack a lossy generation. Reproducible via
**`tools/build_music_layers.sh <demucs_stem_dir> <name> [flat_track]`**.

**The pop-trained 4-stem model does not map onto orchestral music.** Its stems
are drums / bass / other / vocals, and on the act-1 track:

```
other    -12.13 LUFS    the bulk — strings and brass
vocals   -15.72         choir; a real and useful layer, not a mistake
drums    -23.56         percussion
bass     -31.71         19.6 dB under the bed — no bass-guitar-shaped source to find
```

So what ships is a **three-layer** arrangement, not the textbook four: `bass` is
foundation you would never want *absent*, not a layer you would ever want to
toggle, so it is folded into the bed rather than given a slot that does nothing.
(On a 30-second excerpt `bass` measured −49 LUFS and looked completely empty —
the excerpt was a quiet passage. **Measure the whole track before concluding a
stem is dead.**)

The `vocals` stem is the one that decides whether a track can be layered at all,
and it varies: voices sit 3.6 dB under the bed on act 1, 6.2 on act 2, 9.3 on
act 3. All three are usable. The build tool prints that gap and **warns past
25 dB** — a track with no choir would ship a three-layer cue with a dead index 2,
and the right answer there is to leave it unregistered so Combat falls back.

**Levels: one uniform gain, never per-stem normalisation.** Normalising each
layer separately would rebalance the piece — the arrangement is the thing being
preserved. The tool measures the full arrangement, derives one gain, applies it
to all three, then re-measures the sum and compares it against the flat track.
That last comparison is the real check, and it also catches the stems failing to
reconstruct: act 1's summed stems came to −10.86 LUFS against the original
master's −10.73, i.e. within 0.13 LU.

**The intensity mapping** (`Combat._music_intensity`) is deliberately small:

| | condition | arrangement |
|---|---|---|
| 0 | round 1 — the muster, nobody swings | bed only |
| 1 | ordinary fighting | bed + percussion |
| 2 | hero under 40%, or foe under 35% | bed + percussion + voices |

Asserted from `_start_round`, so it re-reads every round. `set_music_layer` drops
a call asking for the level a layer is already heading to, which is what makes a
per-round assertion free. **The escalation is textural, not a volume ramp** —
bed to full is only **+1.24 LU**. What a player notices is percussion arriving,
not the music getting louder; an intensity system that just rides the fader reads
as a bug in the mix.

**The engine contract, read out of the source** (`modules/interactive_music/
audio_stream_synchronized.cpp`) because the class reference does not state it:

- `mix()` re-reads `stream->audio_stream_volume_db[i]` **every mix call**, so
  `set_sync_stream_volume` works live. This is the fact the whole feature rests
  on and it is documented nowhere.
- …but it applies per `MIX_BUFFER_SIZE` (128 frames, ~2.7 ms) as a **step**. A
  snapped volume is a click. Layers must be tweened — `set_music_layer` is the
  only writer and it tweens.
- `start(pos)` starts every sub-playback at the same position; that is the sync
  guarantee. Never drive layers with N separate `AudioStreamPlayer`s — they drift.
- `AudioStreamSynchronized` has **no `loop` property**, and `mix()` ends with
  `if (!any_active) active = false;` — so a single non-looping stem kills the
  whole cue partway through a fight. Looping is set per layer in
  `_start_music_stream`.

**Graceful degradation is the shipping condition.** `layered_cue_available()`
returns false if *any* stem is missing and Combat falls back to the flat pool — a
partial arrangement is worse than the flat track, because a missing percussion
stem does not error, it just quietly plays a battle theme with no drums.

**One funnel for all fight music.** `Combat._combat_music_book(node_type, act,
encounter_id)` is a **static, pure** function returning the ordered book, and
`_play_combat_music` is the single place that tries the layered cue and falls
back. That shape is not tidiness: elite and boss fights spent a whole pass
playing flat precisely because the layered attempt was wired into one arm of a
`match` and forgotten in the others, and nothing could see it. Purity is what
lets the gate enumerate every fight in the game.

**Gate: `tools/_probe_music_layers.tscn`** (298 checks) — it walks **every**
registered cue, not a hardcoded one, because the registry is the thing that
grows. Per cue: stems resolve, layer count matches the index contract the
intensity mapping drives by, the key is a real track name, availability is honest
in both directions, every stem loops, stem lengths agree (they drift apart on
loop otherwise), the bed opens at 0 dB and the rest silent. Then once: raising a
layer moves the volume *gradually*, re-asserting an in-flight target doesn't
restart the fade, layer state dies with `stop_music`, and the six intensity cases.

Finally it **enumerates all 13 fights** by calling `_combat_music_book` — three
acts × {plain, General}, plus every rival lord's keep and the act-3 keep — and
cross-checks both directions: every anchor must have a cue (or that fight
silently plays flat) and every registered cue must be some fight's anchor (or it
is dead content that can never play). Every track in every book is resolved
through `AudioBank._resolve_music_path`.

Mutant-verified on seven faults: non-looping stems, snapped (un-tweened) volume,
an intensity mapping that ignores the muster round, an act losing its cue, a cue
registered under a key no fight asks for, a book naming a track that does not
exist, and one rival lord's keep losing its cue.

**Coverage handoff worth knowing.** Moving the books into
`_combat_music_book` took nine names — `combat_elite{,_b,_c}` and
`combat_boss{,_b,_c,_d,_e,_act3}` — out of the literal `play_music_random([...])`
calls that `_probe_music_wiring.gd` scans for, and its count dropped 42 → 33.
Those nine are now covered by this probe's enumeration instead, which is strictly
stronger: it resolves the names a real fight would actually ask for, including
the per-rival-lord boss branch a literal scan could only approximate. The
handoff is noted in the wiring probe's own header so the coverage map stays
honest. (The twelve act-combat names still appear there because the skirmish
branch keeps them inline.)

Two bugs it caught during the build, both invisible otherwise:

1. `music_layer_count()` read the **player's stream**, but
   `AudioStreamPlayer.stop()` does not clear `stream` — so after `stop_music` it
   went on reporting three drivable layers over silence, and Combat guards on
   exactly that value. `_active_layered_stream()` now treats `_layer_targets` as
   the authority.
2. A `var sub := stream.get_sync_stream(i)` inside an `if stream is
   AudioStreamSynchronized` block is a **hard parse error** — an `is` check does
   not narrow the type for `:=` inference. It took the AudioBank autoload down
   entirely, and the symptom surfaced as an unrelated-looking `RunState.gd` parse
   error during `--import`.

### Background: the technique, and how to get stems you don't have

This is where "cool across the whole game" actually lives, and the obstacle is
that you have finished stereo masters, not stems.

**You can manufacture them.** Demucs (Meta's hybrid transformer source
separation, open source) splits a finished stereo track into drums / bass /
other. Run it on *one* act-1 combat track and you have three layers of music
that is already in the game, in key with itself by construction, with no
transition to get wrong. Then:

- Muster round (no clash): harmonic layer only — sparse, waiting.
- Round 2+: bass enters.
- Hero below 40% HP, or a General on the board: drums enter, full arrangement.
- Boss phase 2: everything, plus the top layer of the *boss* track over it.

One track that never repeats itself because it is *responding*. Wire it with
`AudioStreamSynchronized` and drive layer volumes from the existing round
ladder in `_start_round`.

Two honest caveats: separation artefacts are audible on solo'd stems (mostly
smeared reverb and cymbal bleed), so it works best when layers are added *to* a
bed rather than played alone — which is how you'd use them anyway. And the CC-BY
licences permit derivative works with attribution, but check the attribution
line still names the original correctly.

This also speaks directly to the standing complaint recorded as "combat feels
samey — presentation and stakes, not mechanics." Music that knows the fight is
going badly is presentation and stakes.

---

## 4. What I would do first

1. ~~Step 1~~ — done. Verify by ear that transitions no longer dip.
2. ~~Step 3~~ — done. Play two runs and check the act themes differ *between*
   them and hold *within* them, and that a wayside no longer restarts the music.
3. ~~Step 2~~ — adopted, limiting included. Library is at **0.53 LU**.
   `git checkout -- assets/audio/music/` reverts the whole swap.
4. ~~Step 6~~ — built on **every solo fight**: 3 acts × {plain, General} plus all
   six keeps. Ten cues, 30 stems, 118 MB.

**What to listen for**, in priority order:

- **`combat_boss_b` and `combat_boss_d` muster rounds.** They climb 2.88 and
  3.05 LU, so their bed-only state is genuinely quiet. Decide whether that reads
  as a hushed opening or as broken audio. Everything else is 0.4–1.8 LU.
- **Separation artefacts in the bed-only state.** Demucs leaves smeared reverb
  tails and cymbal bleed; they hide under a full arrangement and may not under a
  thin one. **`combat_boss_e` (10.8 dB) and `combat_boss_c` (10.6 dB)** have the
  widest voices-under-bed gaps, so their beds are the most exposed.
- Whether percussion entering at the top of round 2 reads as intentional.

If any single cue does not hold up, remove its entry from
`AudioBank.LAYERED_CUES` and that fight falls back to its flat book
automatically — no code change. Deleting `assets/audio/music/layers/` reverts
the whole feature the same way.

**Not layered: skirmish.** `_is_net()` keeps its 12-track rotation, deliberately
— that pool exists so each game of a Bo3 gets a fresh song, and pinning it to one
layered anchor would trade that variety away. Worth revisiting only if the
campaign layering proves itself.

Steps 4 and 5 can wait.

One consequence of Step 3 worth watching by ear: with the road theme now
repeating, the resume-position behaviour (§Step 4) matters more than it did.
Re-entering the same track at its saved playhead across 18 visits means the act's
theme progresses linearly over the act, which is either elegant or disorienting
depending on where the cuts land, and only listening will say which.

---

## Sources

- [Godot `AudioStreamInteractive`](https://docs.godotengine.org/en/stable/classes/class_audiostreaminteractive.html) ·
  [`AudioStreamPlaybackInteractive`](https://docs.godotengine.org/en/stable/classes/class_audiostreamplaybackinteractive.html) ·
  [`AudioEffectCompressor` (sidechain)](https://docs.godotengine.org/en/stable/classes/class_audioeffectcompressor.html) ·
  [`AudioEffectHardLimiter`](https://docs.godotengine.org/en/stable/classes/class_audioeffecthardlimiter.html)
- [The new music features in Godot 4.3 explained — Blips](https://blog.blips.fm/articles/the-new-music-features-in-godot-43-explained)
- [Vertical Remixing](https://www.oreilly.com/library/view/writing-interactive-music/9780133563528/ch09.html) and
  [Horizontal Resequencing](https://www.oreilly.com/library/view/writing-interactive-music/9780133563528/ch08.html),
  *Writing Interactive Music for Video Games* (Michael Sweet)
- [Vertical layering vs horizontal resequencing — The Game Audio Co](https://www.thegameaudioco.com/making-your-game-s-music-more-dynamic-vertical-layering-vs-horizontal-resequencing)
- [Elizabeth Hellmuth Margulis, *On Repeat*](https://global.oup.com/academic/product/on-repeat-9780199990825) ·
  [summary](https://www.themarginalian.org/2014/09/18/on-repeat-margulis/)
- [Gapless looping MP3 tracks — compuphase](https://www.compuphase.com/mp3/mp3loops.htm) ·
  [Gapless playback](https://en.wikipedia.org/wiki/Gapless_playback)
- [Loudness in game audio — Designing Sound](https://designingsound.org/2013/02/28/loudness-in-game-audio/) ·
  [EBU R 128](https://en.wikipedia.org/wiki/EBU_R_128)
- [Demucs](https://github.com/facebookresearch/demucs)
- [The rogue-likes making death an audio delight — GameGrooves](https://gamegrooves.com/gazette/rogue-likes)
