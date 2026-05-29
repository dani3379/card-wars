# Music credits

Tracks are a mix of CC0 (Public Domain) and CC-BY 3.0, all sourced from
OpenGameArt.org. **CC-BY 3.0 tracks require attribution** — the credit lines
live in the in-game Credits screen (`scripts/scenes/Credits.gd`). Keep them if
you ship.

| File | Title | Artist | License | Original URL |
|------|-------|--------|---------|--------------|
| main_menu.ogg | Tragic Ambient Main Menu | yd | CC0 | https://opengameart.org/content/tragic-ambient-main-menu |
| map.ogg | Loopable Dungeon Ambience | Spring | CC0 | https://opengameart.org/content/loopable-dungeon-ambience |
| combat.mp3 | Battle Theme A (Act 1 pool) | cynicmusic | CC0 | https://opengameart.org/content/battle-theme-a |
| combat_act1_b.mp3 | Out Of Time (Act 1 pool) | Jonathan Shaw | CC-BY 3.0 | https://opengameart.org/content/out-of-time-rpg-orchestral-essentials-danger-music |
| combat_act2.mp3 | A Fight in the Fields (Act 2 pool) | Jonathan Shaw | CC-BY 3.0 | https://opengameart.org/content/a-fight-in-the-fields-rpg-orchestral-essentials-combat-music |
| combat_act2_b.mp3 | JRPG Epic Rock Battle Theme #1 (Act 2 pool) | HydroGene | CC0 | https://opengameart.org/content/jrpg-epic-rock-battle-theme-1 |
| combat_act3.ogg | The Tread of War (Act 3 pool) | Jonathan Shaw, Johan Brodd, cynicmusic | CC-BY 3.0 | https://opengameart.org/content/the-tread-of-war-jonathan-shaw-pixelsphere-jobromedia |
| combat_act3_b.wav | Boss Battle #6 Metal V1 (Act 3 pool) | nene | CC0 | https://opengameart.org/content/boss-battle-6-metal |
| combat_elite.mp3 | Fierce Battle! | remaxim | CC0 | https://opengameart.org/content/fierce-battle |
| combat_boss.ogg | Battle RPG Theme (var) | CleytonRX | CC0 | https://opengameart.org/content/boss-battle-theme |
| combat_boss_act3.wav | Boss Battle #2: Symphonic Metal (Act 3 boss) | nene | CC0 | https://opengameart.org/content/boss-battle-2-symphonic-metal |
| shop.mp3 | Medieval: Market Day (loop) | RandomMind | CC0 | https://opengameart.org/content/medieval-market-day |
| rest.ogg | Ambient Relaxing Loop | isaiah658 | CC0 | https://opengameart.org/content/ambient-relaxing-loop |
| event.ogg | Dark Cavern Ambient (loop) | remaxim | CC0 | https://opengameart.org/content/dark-cavern-ambient |
| victory.mp3 | Victory Theme for RPG | cynicmusic | CC0 | https://opengameart.org/content/victory-theme-for-rpg |
| defeat.mp3 | The Fallen | Jonathan Shaw | CC-BY 3.0 | https://opengameart.org/content/the-fallen-rpg-orchestral-essentials-defeated-music |

Normal combat fights pick at random from their act's pool, with the previously-played
track excluded so consecutive fights never start on the same song.

## Required attribution (CC-BY 3.0)

These credits must stay visible to players (currently in the in-game Credits screen):

- "A Fight in the Fields", "Out Of Time", and "The Fallen" — composed by Jonathan Shaw (www.jshaw.co.uk)
- "The Tread of War" — Jonathan Shaw (www.jshaw.co.uk), Johan Brodd (jobromedia), and cynicmusic (built on cynicmusic's "Battle Theme A")

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
