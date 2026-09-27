# The game is deaf to itself — a hunt by SENSE (2026-09-02)

Nine passes have now hunted this game and **every one of them was about pixels.**
Eight went by SURFACE (*what beat is missing on this screen*) and one by TECHNIQUE
([`TECHNIQUE_HUNT_20260902.md`](TECHNIQUE_HUNT_20260902.md) — *what medium
primitive have we never used*). The eye is extremely well served. Nobody has ever
asked the same question about the ear.

Ask it and the answer is immediate and uncomfortable:

> **Every visual system in this game reacts to the fight. The score does not.**

The portraits scorch off the HP ratio (★7). The table takes scars that hold for
the fight. The killing blow drains colour out of the world (★8). At the danger
line a red vignette starts breathing and a heartbeat engages
(`Combat._low_hp_active`). And behind all of it, the music plays exactly the same
at 30/30 as it does at 3/30 — chosen once on scene entry and never consulted
again.

Items numbered **▼** so they never collide with the pitch's ★, the card hunt's ✦,
the game hunt's ✱, the menu hunt's ❖ or the technique hunt's ▲.

Every claim below is grepped out of shipped source or listed off the asset tree.

---

## 1. The sense ledger

| Property | Status | Evidence |
|---|---|---|
| Music picked per screen/act/boss | **have** | `Combat:1259-1290`, per-rival leitmotifs |
| No back-to-back repeat | **have** | `play_music_random` erases `_current_music_track` from the pool |
| Resume-where-you-left-off | **have** | `play_music` remembers each track's position |
| Stinger ducking | **have** | `duck_music(-9.0)` at the verdict, ★8, boss entrance |
| SFX variation | **have** | shuffle bag (`_sfx_bag`) + pitch jitter |
| Per-screen ambience bed | **partial** | `play_ambience` wired at 2 sites; **1 of 6 authored beds has an asset** |
| Low-HP audio | **partial** | a heartbeat SFX — but the SCORE is unchanged |
| **Music reacting to fight state** | **NEVER** | `play_music` is called on entry only; the Music bus carries volume and nothing else |
| **Stereo placement** | **NEVER** | every player is a non-positional `AudioStreamPlayer`; zero hits for pan anywhere |
| **Room tone on the board** | **NEVER** | `play_ambience` is called by Event and Rest only — never by Combat |

Two buses exist (`Music`, `SFX`) and `AudioServer` is used for **volume only** —
no effect is ever added to either.

---

## 2. The slate

### ▼1 — THE SCORE NEVER LEARNS WHAT HAPPENED

**The observation.** `Combat` already owns a fully-built dread state with
hysteresis: `_low_hp_active` engages a breathing vignette and a heartbeat at the
danger line and clears the moment HP recovers (`_stop_low_hp_dread`). Every
channel the player has is told the fight is going badly **except the loudest one
in the room.**

**Why this is the cheapest large win available.** It needs **no new audio**. The
49-track library stays exactly as it is; what changes is how the track is
*filtered*. Muffling music under tension is the standard move in the medium
precisely because it is free — the same cue, heard through a wall.

**Low level.**

- Add one `AudioEffectLowPassFilter` to the **Music** bus at boot, parked at
  `cutoff_hz = 20500` — above hearing, so it is inaudible until used and costs
  nothing to leave installed.
- On dread engaging: tween `cutoff_hz` **20500 → 900** over **0.9 s**. On
  recovery: back over **1.4 s** — relief should not snap; dread arriving faster
  than it leaves is the whole shape of the feeling.
- **Do NOT also drop the dB, and this is the important constraint.** `duck_music`
  already owns bus volume as a relative offset that stingers add to and remove;
  a second writer on the same channel would fight it exactly the way two writers
  on `rotation` would. **The filter is a free channel — use it and leave volume
  alone.**
- Ride `_low_hp_active` rather than inventing a trigger, and the hysteresis, the
  clear-on-heal and the "kill it before the defeat sting" ordering
  (`Combat:17710`) all come for free.

**Cost:** ~30 lines and one bus effect. **Verify:** a probe can read
`AudioServer.get_bus_effect(...)`'s cutoff directly, so this is assertable without
listening to anything.

### ▼2 — A FOUR-LANE BATTLE IS MONO

**The observation.** The whole design of this combat is that there are FOUR
LANES side by side, and the player's eye is asked to track which one is resolving
— that is what the spotlight pan and the rank captions are for. Every sound those
lanes make comes out of the dead centre of the screen.

**Do the arithmetic first (★3).** The board spans roughly x 273 → 1300 on the
1600 canvas, so the four lane centres sit near **400 / 657 / 914 / 1171** — that
is **−0.50 / −0.18 / +0.14 / +0.46** of half-width from centre. That is a real
spread, clearly audible on headphones, and it is exactly the information the
player is already being asked to track visually.

**Low level, and the honest cost.** `AudioStreamPlayer` cannot pan; this needs
`AudioStreamPlayer2D` for the affected cues. The project has rejected a real
`Camera2D` (STRIKE_DESIGN §14), but that is not required — with no camera, a 2D
player is heard against the viewport's default listener, which is what we want on
a flat canvas.

**Scope it to the CLASH and nothing else.** Strike, death, and the impact — the
sounds that belong to a place on the board. A panned button click or a panned
shop chime would be a bug, not a feature: UI does not live in the world. That
distinction is the same one ▲1 drew between the hand-inked chart and the printed
lane grid.

**Verdict:** real, and the most invasive item here. Worth doing after ▼1.

### ▼3 — THE BOARD HAS NO ROOM TONE

`play_ambience` is a working system: it crossfades a looping bed and no-ops
gracefully when the asset is missing. It is called by **Event** and **Rest**, and
never by **Combat** — the screen the player spends most of a 40-minute run on.

**And 1 of 6 authored beds actually has an asset.** `assets/audio/sfx/fire_crackle`
exists (so the campfire genuinely crackles); `river`, `carnival`, `wind`, `bees`
and `choir` are asked for by EventDB and silently resolve to nothing. That half is
content, not code — but it means the system is being judged on one sound.

A single wind-and-distant-crows bed under the board, at the `-6 dB` this API
already defaults to, would put the war table outdoors for the price of one file.

### ▼4 — THE FREEZE IS SILENT ABOUT BEING A FREEZE

`hold_strike_frame` pauses the tweens on both bodies — a real freeze (§2.4), not a
scheduler wait — and the audio plays straight through it, unaware. Zero hits for
audio or pitch inside that function.

The cheap version is one line at the same site: dip the **SFX** bus by ~2 dB for
the hold and restore on release, so the world goes quiet as well as still. Ranked
last because it is the smallest of the four and rides code that shipped three days
ago; it should not be built until that has settled.

---

## 3. REJECTED — so they are not re-proposed

| rejected | why |
|---|---|
| **A no-repeat shuffle bag for music** | Already built, and better than proposed: `play_music_random` erases the current track from the pool, so two consecutive fights cannot open on the same song. |
| **Reverb on the SFX bus** | ★4. A reverb is a claim about a ROOM, and this game has no room — it is a table under open sky, and the arenas are painted outdoor scenes. Adding a tail would invent a space the art denies. ▼3 is the material-correct answer to the same impulse: put the board OUTDOORS, don't put it indoors. |
| **Ducking music per strike or per kill** | Already rejected, STRIKE_DESIGN §6: framing every event frames none. Re-affirmed — ▼1 is deliberately tied to a state that changes rarely, not to a beat that fires 8–13× a round. |
| **A third bus for combat SFX** | Nothing yet needs to address the clash separately from UI sound; ▼2 wants per-SOUND placement, which a bus cannot give. Revisit only if ▼4 grows. |

---

## 4. Verification

| item | harness | assertion |
|---|---|---|
| ▼1 | new `_probe_music_dread` (headless) | cutoff is inaudible at full HP, ≤1 kHz within 1 s of crossing the danger line, and back above 20 kHz within 2 s of healing past it; `duck_music`'s dB offset unchanged throughout |
| ▼2 | `_probe_audio_cues` + a new pan check | a lane-0 strike and a lane-3 strike must produce different pan values, and every UI cue must produce none |
| ▼3 | `_probe_audio_cues` | Combat requests a bed, and the bed resolves to a real file |
| ▼4 | `_probe_anim_clock` | the SFX bus returns to its resting dB after every hold, including an interrupted one |
