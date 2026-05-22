# Music credits

All tracks are CC0 (Creative Commons Zero / Public Domain), sourced from
OpenGameArt.org. Attribution is not required but appreciated.

| File | Title | Artist | Original URL |
|------|-------|--------|--------------|
| main_menu.ogg | Tragic Ambient Main Menu | yd | https://opengameart.org/content/tragic-ambient-main-menu |
| map.ogg | Loopable Dungeon Ambience | Spring | https://opengameart.org/content/loopable-dungeon-ambience |
| combat.mp3 | Battle Theme A | cynicmusic | https://opengameart.org/content/battle-theme-a |
| combat_elite.mp3 | Fierce Battle! | remaxim | https://opengameart.org/content/fierce-battle |
| combat_boss.ogg | Battle RPG Theme (var) | CleytonRX | https://opengameart.org/content/boss-battle-theme |
| shop.mp3 | Medieval: Market Day (loop) | RandomMind | https://opengameart.org/content/medieval-market-day |
| rest.mp3 | Forest Ambience | Spring | https://opengameart.org/content/forest-ambience |
| event.ogg | Dark Cavern Ambient (loop) | remaxim | https://opengameart.org/content/dark-cavern-ambient |
| victory.mp3 | Victory Theme for RPG | cynicmusic | https://opengameart.org/content/victory-theme-for-rpg |
| defeat.wav | Sad Game Over | Emma_MA | https://opengameart.org/content/sad-game-over |

## Swapping tracks

To replace any track, drop a new `.ogg` / `.mp3` / `.wav` into this folder with
the same filename (the part before the extension is what `AudioBank.play_music()`
matches on). Loop seams matter — pick "seamlessly looping" tracks where you can.

## Format notes

Godot supports all three formats. OGG Vorbis is preferred for music (smaller
than WAV, no patent concerns unlike MP3). To convert with ffmpeg:

```
ffmpeg -i input.mp3 -c:a libvorbis -q:a 5 output.ogg
```
