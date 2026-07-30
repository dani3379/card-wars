# Music: the complete plan to 100% AAA (2026-07-18)

The costed roadmap from today's library (37 licensed tracks, ~1.9 h, all
Buckley/Nakarada/RandomMind/Pablo after the 07-18 AAA pass) to a soundtrack
that ships at AAA standard. **Chosen direction (user, 07-18): the identity
core is CREATED WITH AI** — the licensed library stays as the proven-quality
bed, and AI generation replaces the commissioning budget. §5 is the AI
production spec; §8 is the ready-to-run prompt book.

**Cost TL;DR**

| Route | Gets you | Cost |
|---|---|---|
| A. Download-all (CC) | Full coverage, pro production, zero identity | **$0** (attribution only) |
| A+. Download-all (premium packs) | Same + lower recognizability | **~$100–300** one-time |
| **D. AI-generated identity core (CHOSEN)** | Main theme + 5 lord leitmotifs + full bespoke coverage, stems via separation | **~$10–60** (1–2 months of a generator subscription) |
| B. Human commission (fallback if AI quality disappoints) | Same scope, guaranteed craft | ~$3k–12k hybrid / $15k–40k full |

Phases 1–4 are free groundwork that pays off regardless of route. Phase 5 is
the AI production plan. Phases are ordered by audible-improvement-per-dollar.

---

## 0. Where we are (inventory, post 07-18 pass)

37 files, ~260 MB MP3 320kbps, ~1.9 h. Every slot pooled ×2–4 with
position-resume and last-track exclusion. Sources: Scott Buckley (19),
Alexander Nakarada (9), RandomMind (6), Matthew Pablo (2). Full table:
`assets/audio/music/MUSIC_CREDITS.md`. Verification gate:
`tools/_probe_music_wiring.gd`.

Genre yardsticks: Slay the Spire ~55 min · Darkest Dungeon ~1 h ·
Inscryption ~1.5 h · **us ~1.9 h** · Hades ~2.5 h · Skyrim ~3.5 h.
Count is NOT the gap. The gaps: identity, interactivity, coverage corners,
technical delivery.

---

## 1. Phase 1 — Coverage completion (download, $0)

+13 licensed tracks → ~50 total (Skyrim-count). Candidates below are real,
confirmed-available CC-BY 4.0 tracks from the two proven sources (same
download pipeline: 429-retry pacing, Referer for free-stock-music, magic-byte
check, delete no old files — these are all NEW slot names).

| # | New slot | Purpose | Candidate (source) |
|---|---|---|---|
| 1 | `map_act2` | Act 2 map anchor — campaign darkens | Sunguard (Nakarada, epic celtic) |
| 2 | `map_act3` | Act 3 map anchor — the march on the keep | The Encounter (Buckley, menacing drive) |
| 3 | `combat_boss_d` | 4th boss rotation / lord assignment | Hour of the Witch (Buckley) |
| 4 | `combat_boss_e` | 5th boss rotation / lord assignment | The Summoning (Buckley, gothic choral) |
| 5 | `net_lobby` | Skirmish muster identity (own, not borrowed) | Honour Among Thieves (Buckley, folk-rock tavern) |
| 6 | `net_lobby_b` | Skirmish pool depth | Pathfinder (Buckley, bold heroic) |
| 7 | `credits` | Dedicated credits track (classic AAA beat) | With These Hands (Buckley, warm reflective) |
| 8 | `event_dread` | Event mood split: bone/ember events | Incantation (Buckley, eerie) |
| 9 | `event_wry` | Event mood split: gilt/verdigris events | Magic Tavern (Nakarada, playful celtic) |
| 10 | `main_menu_c` | Menu pool depth (first-impression screen) | A Dragon's Lullaby 2023 (Buckley, dark somber) |
| 11 | `victory_boss` | Act-clear/lord-fall victory variant | Hyperion (Buckley, triumphant fanfare) |
| 12 | `map_e` | Map pool depth for act 1 | Adventure (Nakarada) |
| 13 | `rest_d` | Rest pool depth | Amberlight (Buckley, soft nostalgic) |

Code touches: per-act map pool branch in MapView (`map`/`map_b`… →
per-act arrays), NetLobby/Net* pool swap, Credits.gd play call, Event.gd
mood→pool mapping (read the event's `mood` field), GameOver boss-victory
branch. All small pool-literal edits; the probe scans them automatically.

Per-lord boss assignment (no new code concept): EncounterDB's 5 rival-lord
kits each get a FIXED track from the 5-deep boss book (Juggernaut, Song of
the Forge, Vanguard, Hour of the Witch, The Summoning) chosen to match the
lord's kit personality — a leitmotif-lite that costs nothing. Amalgam
finales keep Terminus.

Premium-pack alternative (route A+): replace the most-recognizable CC
anchors (Legionnaire, Balefire — both heavily used across YouTube/indie
games) with marketplace exclusive-ish packs: Unity Asset Store / itch.io /
Fab orchestral-medieval packs run $15–60 for 10–30 tracks; 3–5 packs ≈
**$100–300** covers the whole soundtrack with rarer material. Optional.

## 2. Phase 2 — Technical delivery pass ($0 + one ffmpeg install)

The biggest *audible* jump per effort on this list. Blocked only on
`winget install ffmpeg`.

1. **Gapless loops**: MP3 carries encoder padding — every loop wrap has a
   micro-gap. Re-encode the full library to OGG Vorbis q5–6 (`ffmpeg -i in.mp3
   -c:a libvorbis -q:a 5 out.ogg`), delete the MP3s + sidecars (resolve order
   prefers .ogg — no code changes), re-import. For true seam-free loops on the
   short loopers (map/rest/shop), trim silence at head/tail first
   (`silenceremove`) and set loop points in the Godot import options.
2. **Loudness normalization**: two-pass `loudnorm` to −16 LUFS integrated /
   −1 dBTP across all 50 files so no track jumps out of the mix. Print a
   before/after LUFS table into `MUSIC_CREDITS.md`.
3. **Size**: ~260 MB → ~100 MB. Ship hygiene.
4. **Verification**: extend `_probe_music_wiring.gd` (or add
   `_probe_music_mastering.gd`) to fail if any music file is MP3/WAV or
   missing; keep the resolve-order gotcha documented.

## 3. Phase 3 — Musical punctuation: the stinger set (~$0–1,200)

Short cues (2–8 s) that mark beats music currently ignores. AudioBank
already has the delivery mechanism (`duck_music` + `play_sfx`); several call
sites are repitched stand-ins waiting for real clips (`SFX_FALLBACKS`).

| Cue | Moment | Source option |
|---|---|---|
| boss_horn | Lord fight intro (stand-in exists) | Free: Sonniss GDC bundles (commercial-OK) |
| general_down | A General dies |〃 |
| war_school | The 10-kill school modal opens | 〃 |
| wake_rite | Hold a Wake resolves | 〃 |
| lord_fall | Boss victory beat (pre-Reward) | 〃 |
| omen_sting | Daily March omen reveal | 〃 |
| relic_major | Boss-relic / Reliquary pickup | 〃 |
| act_turn | Act transition on the map | 〃 |

Free route: Sonniss GDC packs + existing orchestration = $0 but curation
time. Commissioned route: stingers run **$50–150 each** from the same
composer as Phase 5 (batch them into that contract — matched palette,
~$400–1,200 for all 8, often discounted inside a larger scope).

## 4. Phase 4 — Interactive music system (code, $0 now; stems later)

AAA music *reacts*. Current state is already above indie baseline
(crossfade, position-resume, ducking). The ladder, cheap→deep:

1. **Silence design ($0, now)**: map/rest screens occasionally hold
   ambience-only (wind, camp crackle via `play_ambience`) for one visit —
   music re-entry lands harder. One roll in the screen's music call.
2. **Pseudo-intensity ($0, now)**: combat LPF/volume dip on the Music bus
   during the player-planning phase, opening up at the clash commit
   (Balatro/DOOM-lite, works on stereo files — an AudioEffectLowPassFilter
   tween, no stems needed). Danger states (lethal on board, hero <25% HP)
   lift the cap.
3. **Boss phase step ($0, now)**: lord HP <50% → `duck_music` beat +
   crossfade to the track's saved position with +1 dB and the LPF fully
   open; reads as a phase change without new audio.
4. **True vertical layering (needs stems → Phase 5)**: 2–3 stem beds for
   combat (rhythm / full / climax) crossfaded by board state. Only worth
   doing with commissioned stems; stock tracks don't ship them.

## 5. Phase 5 — The identity core, CREATED WITH AI (the chosen route)

The same scope a $15k commission would buy, produced by generating many
candidates and keeping the best. What AI does well in 2026: full-produced
cinematic/folk tracks, consistent style palettes, stem separation. What it
does poorly: strict melodic discipline across tracks (the leitmotif problem
— mitigated below), clean endings/loops (fixed in post), and taste (that's
the curation loop).

### 5a. Scope (unchanged from the commission spec)

| Deliverable | Minutes | Slot names |
|---|---|---|
| Main theme (menu arrangement) | 2–3 | `main_menu` (replaces Balefire) |
| Map arrangement of theme ×3 acts | 4–6 | `map`, `map_act2`, `map_act3` |
| 5 rival-lord leitmotifs | 8–10 | `boss_stalwart/raider/acolyte/pyromancer/kindler` |
| Finale — theme + spared-lord motif collision | 3–4 | `combat_boss_act3` (replaces Terminus) |
| Victory/defeat theme arrangements | 2 | `victory`, `defeat` |
| Combat bed ×3 acts (stem-split for Phase 4.4) | 9–12 | `combat`, `combat_act2`, `combat_act3` |
| Stinger set (8 cues, trimmed from takes) | ~1 | Phase 3 list |
| **Total** | **~29–38 min kept** (expect 10–20× that generated) | |

### 5b. Tools & cost (state of the art verified 2026-07-18)

| Tool | Fit | Cost |
|---|---|---|
| **Suno v5.5** (primary) | The quality leader (tops the blind-test ELO boards). Everything the plan needs in one place: WAV export, 12-stem separation, **MIDI export**, **Studio** (DAW-like workspace for intensity variations), **Upload Audio** (6–120 s recordings as melodic seeds — see 5c), Covers with a Source Audio Weight dial. Paid tiers explicitly grant commercial game/Steam rights. | ~$10/mo Pro, ~$30/mo Premier |
| **ElevenLabs Music** (secondary) | Built on licensed/royalty-free training data from day one — the cleanest provenance story if that ever matters. Also the pick for stingers/SFX-adjacent cues. | ~$11–22/mo |
| Stable Audio (niche) | Purpose-built for royalty-clear **seamless instrumental loops** — worth a look for map/rest/shop beds specifically. | ~$12/mo |
| AIVA (niche) | MIDI-first orchestral scoring — real editable arrangements if a take is 90% right. | ~€15–49/mo |
| ⚠️ **Udio** | Best licensing position (settled with Universal, Warner, Merlin, Kobalt) **but ALL downloads including stems are disabled since 2025-10-29** while its licensed platform is rebuilt — currently unusable for shipping game audio. Re-check status before considering. | — |

Realistic total: **$10–60** — one or two months of Suno + optionally one
secondary. The real cost is curation hours: community consensus for a full
adaptive indie soundtrack is **~1 focused week** (half a day mapping slots —
§0 already did it — 1–2 days generating, 1 day trim/master, 1–3 days engine
wiring, which is my job).

### 5c. The leitmotif problem and its workaround (upgraded)

AI generators won't naturally restate one melody across 12 tracks. The
state-of-the-art workaround, coolest option first:

0. **Hum it yourself.** Suno's Upload Audio takes a 6–120 s recording made
   right in the app. Hum or whistle an 8-bar melody → that recording IS the
   seed for every arrangement. Two huge wins: the melody is **human-composed
   (a real, enforceable copyright kernel** — materially improves 5d), and
   the theme is guaranteed hummable because you hummed it. Takes zero
   musical training — a phone-quality voice memo is enough.
1. If humming feels wrong: generate the theme from the §8 A1 prompt — many
   takes until one melody sticks. That take becomes the SEED; archive its
   generation ID.
2. Every arrangement (map acts, victory, defeat, credits, finale) is a
   **Cover of the seed** — set **Source Audio Weight 0.6–0.8** so the
   melodic hook survives re-orchestration. Acceptance bar: you can hum the
   theme over it.
3. Lord leitmotifs are INDEPENDENT melodies — fresh prompts (§8 block B),
   one distinctive instrumental voice each. (Coolest version: hum five
   two-note-contrast motifs too — wall/gallop/bell/clock/fuse.)
4. The finale is a cover of the seed at **weight 0.3–0.4** prompted toward
   the spared lord's palette — the weight dial is exactly the "how far can
   it stray" control. If it won't converge, ship finale = main theme in war
   dress (still correct).
5. **Intensity variations for Phase 4.4 come from Suno Studio**, not
   guesswork: keep a combat bed, then generate calm/intense variations of
   the SAME track in-style and export stems — this is the documented
   adaptive-layer workflow (base → variations → stems → engine crossfades).

### 5d. Rights, disclosure, honesty (read before shipping)

- **Commercial use**: granted by Suno/Udio paid tiers per their ToS —
  re-verify the current ToS at generation time; label-lawsuit settlements
  have been reshaping these terms since 2024–25.
- **Copyright**: pure AI output has no copyright protection in the US (no
  human authorship) — you can ship it, but can't stop someone re-using it.
  The curation/editing/loop work builds a thin human-authorship layer; the
  game as a whole stays protected either way.
- **Steam requires AI-content disclosure** on the store page (since 2024).
  One honest sentence: "Portions of the soundtrack were AI-generated and
  human-curated." The Credits screen should say the same (replacing the
  per-artist CC lines for whichever tracks AI replaces — CC attribution
  stays for every licensed track that remains).
- **Sound-alike risk**: never prompt with living-artist or franchise names
  (no "like Hans Zimmer", no "Elden Ring style"). The §8 prompts describe
  instruments and moods only.
- **The hummed-seed bonus (5c.0)**: a melody you composed by humming is
  human-authored and copyrightable; AI arrangements built on it inherit a
  protectable core. This is the single cheapest way to strengthen the
  rights position — prefer it over a pure-prompt seed.
- Export **WAV** (paid tiers offer it), archive every kept take's prompt +
  seed + generation ID in MUSIC_CREDITS.md — that's the provenance ledger.

### 5e. Division of labor

- **Claude (me)**: the prompt book (§8), file wrangling, loop-editing and
  −16 LUFS mastering via ffmpeg (Phase 2 toolchain), OGG conversion, slot
  wiring + pool code, credits/disclosure text, probes. I cannot listen —
  I never judge a take.
- **You**: the account + subscription (I don't create accounts or handle
  payment), running generations from the prompt book, and the audition
  shortlist (mark keeps; 2–3 candidates per slot is enough for me to wire
  in whichever you settle on).

### 5f. Fallback

If after ~2 sessions the orchestral quality doesn't clear the Buckley bar
(the honest test: shuffle a kept take into the existing boss pool — if it's
identifiable as the weak track, it isn't AAA), fall back to route B: human
commission of ONLY the theme + 5 leitmotifs (~15 min, $3k–12k established-
indie tier; SoundBetter/AirGigs; Nakarada takes commissions and would blend
with the bed). Everything in Phases 1–4 still applies unchanged.

---

## 6. Milestones & verification

- **M-A (free, ~1 session)**: Phase 1 downloads + pool edits. Gate:
  `_probe_music_wiring.gd` all-pass at ~50 names; Credits/MUSIC_CREDITS
  updated.
- **M-B (ffmpeg, ~1 session)**: Phase 2 re-encode + normalize + Phase 4.1–4.3
  code. Gate: mastering probe (no mp3/wav, LUFS table printed); manual
  loop-seam listen on map/rest/shop. Do BEFORE M-C — the same toolchain
  masters the AI takes.
- **M-C (AI theme session)**: user subscribes (Suno Pro ~$10). Step 0
  (best): hum the 8-bar theme into Upload Audio — that's the seed. Then §8
  block A (theme hunt/refinement) + block B (lord leitmotifs). Claude wires
  the keeps: loop-edit → normalize → slot names → per-lord boss lookup in
  Combat's music block → credits/disclosure text.
- **M-D (AI coverage session)**: §8 blocks C–E (arrangements, combat beds
  + stem split for Phase 4.4, stingers). Quality gate per 5f's shuffle
  test; fall back to route B only if it fails twice.
- Ship check: audition matrix (menu → setup → map ×3 acts → fight/elite/
  lord ×5 → rest/shop/event/wayside → finale → GameOver both ways →
  skirmish lobby + net fight) with music volume at default over one full run.

## 7. Decision log

- 2026-07-18: plan written; commissioning quoted $3k–40k.
- 2026-07-18 (same day): **user chose route D — create the identity core
  with AI** (~$10–60). §5 rewritten as the AI production spec; §8 prompt
  book added. Human commission demoted to fallback (§5f).

---

## 8. The prompt book (ready to run)

House palette — open every prompt with this spine so the whole score speaks
one voice, then add the slot's character. All instrumental; wordless choir
allowed. Never name artists, games, or films.

> **SPINE (style field):** dark medieval orchestral folk, low strings, war
> drums, solemn wordless choir, nyckelharpa, natural stone-hall reverb,
> minor key
>
> **EXCLUDES (standing, every generation):** no vocals, no synthesizers,
> no EDM elements, no electric guitar, no modern drums
>
> **LYRICS FIELD:** `[Instrumental]` always; add structural metatags to
> shape arrangement (e.g. `[Solo cello intro]` `[Full orchestra]`
> `[Choir enters]` `[Quiet outro]`).

Prompt-craft rules (community-tested on v5.5): **6–8 style tags** is the
sweet spot — under 4 reads generic, past 10 the model ignores the tail, so
when a slot prompt below pushes past budget, drop SPINE colors before slot
character. Always state BPM. For loopers add: "seamless loop, no intro, no
outro, loopable" (then loop-edit in post anyway).

### Block A — the main theme hunt (do first; everything hangs on it)

**A1 · Main theme / menu.** SPINE + "solemn main-title theme built on ONE
simple hummable 8-bar melody, stated first by a lone cello, restated by
choir and full orchestra, slow build, dignified grief, a war remembered,
ends unresolved. 90–100 BPM." — Generate 10–20; keep the one whose melody
you can hum the next morning. That take is **THE SEED**; archive its
generation ID. Everything in block C covers it.

### Block B — five lord leitmotifs (fresh melodies, one voice each)

**B1 · The Stalwart — Lord of the Last Wall (Formation).** SPINE + "an
immovable fortress march, massive low brass pedal tones, shield-wall snare
in lockstep, granite and patience, slow, no haste, the wall does not move.
70 BPM." → `boss_stalwart`

**B2 · The Raider — Lord of the Grasswake (Overrun).** SPINE + "galloping
war music, driving open-string fiddle ostinato, thundering toms, wind
through grass, hunger and speed, always accelerating, never resting.
150 BPM." → `boss_raider`

**B3 · The Acolyte — Lord of the Owed (the Tithe).** SPINE + "a funeral
procession as accounting, tolling bell on every bar, low male chant, dry
pizzicato like a clerk's pen ticking a ledger, patient and inevitable —
every death is a deposit. 60 BPM." → `boss_acolyte`

**B4 · The Pyromancer — Lord of the Lanternhall (Foresight).** SPINE + "cold
calculated fire, glassy string harmonics, a chess-clock ostinato, slow
controlled build from a single flicker to a roaring blaze that never loses
control, intelligence more frightening than fury. 110 BPM." → `boss_pyromancer`

**B5 · The Kindler — Lord of the Everflame (the Fuse).** SPINE + "a lit
fuse, ticking accelerating ostinato, crackling percussion, pressure that
only ever rises, unstable joy, ends in eruption. Starts 90 BPM, finishes
140." → `boss_kindler`

### Block C — theme arrangements (COVER the seed, don't re-prompt)

- **C1 `map`** — cover of SEED: "quiet campaign-chart arrangement, solo
  nyckelharpa carries the melody over soft drone, distant drums, lamplight."
- **C2 `map_act2`** — cover: "the march darkens, add low brass and choir,
  the melody now a burden."
- **C3 `map_act3`** — cover: "full war orchestration, the melody as a
  battle standard, drums forward, ash in the air."
- **C4 `victory`** — cover: "short triumphant resolution of the melody,
  bright brass, one minute, ends CONCLUSIVELY."
- **C5 `defeat`** — cover: "the melody broken and slow, solo cello and
  cold strings, grief, unresolved."
- **C6 `credits`** — cover: "warm full statement, every section of the
  orchestra takes the melody once, farewell."
- **C7 `combat_boss_act3` (finale)** — cover of SEED prompted toward the
  spared lord's block-B palette (five variants possible; if runtime lookup
  of the spared lord is wired, generate all five as `finale_<lord>`).

### Block D — combat beds (fresh; stem-split after keeping)

- **D1 `combat` (act 1)**: SPINE + "skirmish on open ground, driving but
  light, fiddle and drums forward, room to breathe. 120 BPM."
- **D2 `combat_act2`**: SPINE + "pitched battle, full orchestra, choir
  enters at the midpoint, heavier every minute. 130 BPM."
- **D3 `combat_act3`**: SPINE + "the last field, relentless war engine,
  massed drums and brass, choir at full cry, apocalyptic but human.
  140 BPM." — After keeping each: open in Suno Studio, generate a CALM and
  an INTENSE variation of the same track in-style, export stems (drums /
  strings-brass / choir) → Phase 4.4 layers. This is the documented
  adaptive-layer workflow; stem-split alone is the fallback.

### Block E — punctuation (generate long, trim to 2–8 s in post; ElevenLabs
Music is the strong alternative for these short cues, and Suno's MIDI
export lets a cue be re-voiced cleanly if a take is almost right)

E1 boss_horn: "a single massive war horn call, two notes, dread." ·
E2 general_down: "one triumphant brass hit with drum flourish." ·
E3 war_school: "a drilled snare figure and fife, one bar." · E4 wake_rite:
"one bowed lament phrase, solo." · E5 lord_fall: "full-stop orchestral hit,
then silence, then one soft choir breath." · E6 omen_sting: "a cold
shimmer and a low bell." · E7 relic_major: "a reverent brass swell, two
seconds." · E8 act_turn: "a page of the war turning — drum roll into one
horn note."

### Iteration rules

1. 5–10 takes per slot minimum; keep 2–3 candidates, final pick after a
   day's rest (ear fatigue lies).
2. A keep must survive the **shuffle test** (§5f) against the licensed bed.
3. Loopers (map/rest/combat beds): prompt "no intro, no outro" anyway —
   then loop-edit in post regardless (Phase 2 toolchain).
4. Log every keep in MUSIC_CREDITS.md: slot, tool, model version,
   generation ID, prompt used, edit chain.
