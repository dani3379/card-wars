# Audio assets

Drop CC0 / royalty-free audio files into the directories below and they will be
picked up by `AudioBank` automatically at startup. No code changes needed.

The game runs identically without audio files — `AudioBank` no-ops gracefully
when a sound is missing.

## Recommended sources

- [Kenney Audio Packs](https://kenney.nl/assets/category:Audio) — CC0, broad coverage, AAA-quality game SFX.
- [freesound.org](https://freesound.org) — filter by "Creative Commons 0" license.
- [OpenGameArt](https://opengameart.org/art-search?keys=&field_art_type_tid%5B%5D=13) — many CC0/CC-BY game audio packs.

Recommended format: **OGG Vorbis** (smaller than WAV, no licensing concerns
unlike MP3). 22 kHz mono is fine for SFX; 44.1 kHz stereo for music.

## SFX (`sfx/<event_name>/*.ogg`)

Each event lives in its own folder. Drop one or more variant files in; the game
picks one randomly per play (so 3 hit_*.ogg files give natural variation).

| Event folder | Triggered when |
|--------------|----------------|
| `card_play`  | Player plays a creature card |
| `spell_cast` | Player casts a spell |
| `card_draw`  | A card is drawn into hand |
| `card_discard` | End-of-turn discard sweep |
| `hit`        | Generic impact (today: the fallback for `hit_creature`) |
| `hit_creature` | An attack lands on a creature — *falls back to `hit`* |
| `hit_hero`   | The player or enemy hero takes damage |
| `death`      | A creature dies, non-clash paths (spells, poison ticks) |
| `creature_death` | The kill cue at a clash's moment of impact — *falls back to `death`* |
| `floop`      | A floop ability activates |
| `heal`       | A creature is healed |
| `coin`       | Gold gained or spent (shop, reward) |
| `victory`    | Combat won |
| `defeat`     | Combat lost / run ended |
| `turn_start` | Round banner appears |
| `button_click` | Any major button pressed |
| `relic_get`  | A relic enters the collection (metal-ringing clip) |
| `potion_use` | A potion is drunk, combat or map (bottle + bubble variants) |
| `upgrade_confirm` | A card is forged at a rest site (sword-unsheathe "shing", 2 variants) |
| `boss_intro` | Boss/General entrance banner (wants a war-horn/drum stinger) — *falls back to `turn_start`, pitched down* |
| `doom_tick`  | A Doom creature's countdown advances (dry wood-knock clip) |

**Fallbacks** (`AudioBank.SFX_FALLBACKS`): a cue whose own folder is missing or
empty plays its mapped stand-in instead, so no wired moment is ever silent.
Drop real clips into the cue's own folder and it takes over automatically —
no code change (call sites that pitch a stand-in down, like `boss_intro` and
`doom_tick`, check `has_own_sfx` and play a real clip straight).
`tools/_probe_audio_cues.gd` (headless) fails the build if any
`play_sfx` call site resolves to neither its own folder nor a fallback.

**Mix helpers**: `play_sfx(name, jitter, volume_db, pitch_base)` — `pitch_base`
below 1.0 deepens a cue (the low-HP heartbeat is `hit_hero` at ~0.55).
`AudioBank.duck_music(depth_db, hold)` dips the Music bus under a stinger
(victory/defeat/boss entrance use it) and restores the user's slider level.

**Current clip sources** (2026-07-04 fill): "RPG Sound Pack" by **artisticdude**
(OpenGameArt, CC0) — `potion_use/` bottle+bubble, `upgrade_confirm/`
sword-unsheathe ×2, `relic_get/` metal-ringing, `doom_tick/` wood-small,
`spell_cast/` magic1+spell added as variants. Picked by documented semantics,
**not yet auditioned in-game** — swap freely if any reads wrong. Still on
tuned fallbacks (want bespoke clips): `creature_death` (a death cry that isn't
a beast growl), `hit_creature` (meaty melee impact set), `boss_intro`
(war-horn/drum stinger).

Example layout:
```
assets/audio/sfx/
  hit/
    hit_01.ogg
    hit_02.ogg
    hit_03.ogg
  card_play/
    card_play.ogg
  victory/
    fanfare.ogg
```

## Ambience loops (`sfx/<loop_name>/*.ogg`, played via `play_ambience`)

Long looping textures, same folder scheme as SFX. One plays at a time and
crossfades on scene change; missing assets no-op gracefully. Event rooms name
their loop in the EVENTS dict (`"ambience": "<loop_name>"`).

| Loop name      | Used by |
|----------------|---------|
| `fire_crackle` | Rest site campfire; the Siege Kitchen event (file exists) |
| `river`        | The Crossing — awaiting file |
| `wind`         | The White Road — awaiting file |
| `choir`        | The Gravesong Choir — awaiting file |
| `carnival`     | The Rotting Carnival — awaiting file |

## Music (`music/<track_name>.ogg`)

One file per track. `AudioBank.play_music(name)` crossfades between tracks.
Music auto-loops.

| Track name        | Played in |
|-------------------|-----------|
| `main_menu`       | Title screen |
| `map`             | Map / overworld |
| `combat`          | Standard fight |
| `combat_elite`    | Elite fight |
| `combat_boss`     | Boss fight |
| `shop`            | Shop |
| `rest`            | Rest site |
| `event`           | Event / story node |
| `victory`         | Game-over win screen |
| `defeat`          | Game-over lose screen |

Example layout:
```
assets/audio/music/
  main_menu.ogg
  combat.ogg
  combat_boss.ogg
```

## Tuning

Volume sliders live in the in-game Settings overlay (Esc → Settings). Volumes
persist between sessions in `user://settings.save`. The audio buses (`Master`,
`Music`, `SFX`) are created in `UserSettings._setup_audio_buses()`.
