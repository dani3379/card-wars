# SFX Credits

All sound effects in `assets/audio/sfx/` are sourced from Kenney's free CC0
(Creative Commons Zero) audio packs and re-used here under the same licence.

- **Source**: [Kenney Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds)
- **Mirror used for download**: [Calinou/kenney-interface-sounds](https://github.com/Calinou/kenney-interface-sounds)
- **Licence**: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)

Crediting Kenney isn't required by the licence, but it's appreciated — they
release packs like this so small studios and solo devs have decent audio to
work with from day one.

## Mapping

| Event folder    | Kenney source file(s) used                |
|-----------------|-------------------------------------------|
| button_click    | click_001.wav, click_003.wav              |
| card_play       | drop_002.wav, drop_003.wav                |
| card_draw       | pluck_001.wav, scratch_002.wav            |
| card_discard    | scratch_003.wav                           |
| coin            | glass_001.wav, glass_002.wav              |
| turn_start      | confirmation_002.wav                      |
| victory         | confirmation_003.wav                      |
| defeat          | error_007.wav                             |
| spell_cast      | select_003.wav, select_005.wav            |
| hit             | bong_001.wav, close_001.wav               |
| hit_hero        | glass_005.wav                             |
| death           | close_003.wav                             |
| floop           | toggle_001.wav, toggle_002.wav            |
| heal            | pluck_002.wav                             |

These are placeholder picks from a UI/interface pack — fine for shipping, but
the combat-y sounds (hit, hit_hero, death, spell_cast) would benefit from more
thematic replacements (Kenney's RPG Audio or Impact Sounds packs, or
OpenGameArt fantasy SFX). Drop new variants into the existing event folders
and they'll be picked up automatically by AudioBank.

## Ambience loops (separate from one-shot SFX)

`fire_crackle/` — looping campfire ambience played on the rest screen via
`AudioBank.play_ambience("fire_crackle")`. AudioBank routes it through the SFX
bus, so the SFX volume slider attenuates it (players reach for that knob
when they want a crackle quieter, not the music slider).

- **Source**: [Fireplace Sound Loop by PagDev (OpenGameArt)](https://opengameart.org/content/fireplace-sound-loop)
- **File**: `fire.wav` (10.3 MB) — Godot's WAV importer will compress on import.
- **Licence**: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) — credit not required but appreciated.
