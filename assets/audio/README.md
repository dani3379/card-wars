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
| `hit`        | An attack lands on a creature |
| `hit_hero`   | The player or enemy hero takes damage |
| `death`      | A creature dies |
| `floop`      | A floop ability activates |
| `heal`       | A creature is healed |
| `coin`       | Gold gained or spent (shop, reward) |
| `victory`    | Combat won |
| `defeat`     | Combat lost / run ended |
| `turn_start` | Round banner appears |
| `button_click` | Any major button pressed |

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
