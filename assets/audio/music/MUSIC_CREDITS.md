# Music credits

Tracks are a mix of CC0 (Public Domain), CC-BY 3.0, and CC-BY 4.0, sourced
from OpenGameArt.org, free-stock-music.com (Alexander Nakarada mirrors), and
scottbuckley.com.au. **CC-BY tracks require attribution** — the credit lines
live in the in-game Credits screen (`scripts/scenes/Credits.gd`). Keep them if
you ship.

2026-07-18 quality pass: the 11 weakest pre-expansion OGA tracks (chiptune
battle themes, MIDI-metal WAVs, generic ambience loops) were replaced with
Scott Buckley cinematic orchestral + one Nakarada battle track, all CC-BY 4.0.
The library is now Buckley/Nakarada/RandomMind/Pablo/Shaw only.

2026-09-14 re-master pass: the whole library was measured (EBU R128) and
levelled. It spanned **13.9 LU** (-22.1 to -8.1 LUFS) with up to **8.6 LU of
that inside a single random pool** — the event pool held both `event` (-18.1)
and `event_b` (-9.5), so two visits to the same screen could differ by roughly
a doubling of loudness. Six tracks were also mastered above 0 dBTP and clipped
on decode. Every file was re-encoded to **OGG Vorbis q5** with a **static gain**
to -16 LUFS and a -1.5 dBTP ceiling. Static gain, not `loudnorm`'s dynamic
mode, deliberately: dynamic mode reshapes the program and would flatten the
wide tracks, and `combat_boss_d`'s 18.2 LU of range is the point of it.

Result: spread **13.9 -> 0.53 LU**, clipping **6 -> 0** tracks, size
**446 -> 215 MB**. Every track now sits between -16.50 and -15.97 LUFS, worst
true peak -1.50 dBTP, and every one of the 17 random pools is inside 0.5 LU.
Total cost in loudness range across 49 tracks: mean **-0.04 LU**.
OGG also removes the loop problem — MP3 carries encoder delay and end padding
with no standard way to record them, so a looped MP3 inserts a short silence at
the seam; Vorbis defines its own start and end and the padding is trimmed on
decode. Re-run or re-target with `tools/remaster_music.sh [target_LUFS] [out_dir]`
(writes to a side folder; it never overwrites this one). See
`docs/MUSIC_SYSTEM_AUDIT_20260914.md`.

A track that is quiet AND peaky cannot be raised by static gain — the peak hits
the ceiling before the average reaches target. Four were in that state (`map_b`,
`event`, `map_act3`, `map_e`) and were re-done from the ORIGINAL masters with a
look-ahead limiter ahead of the gain, costing **2.2-4.2 dB of peak reduction**
and at most **0.5 LU of loudness range** (`map_b` 4.10 -> 4.00, `event`
12.80 -> 12.30) — the limiter is catching transients, not squashing programme.
A further seven tracks (`combat_act1_d`, `defeat`, `event_c`, `event_wry`,
`rest_b`, `rest_c`, `rest_d`) needed the same treatment for a subtler reason:
the script had computed their headroom from the SOURCE true peak and never
re-measured, and Vorbis overshoots true peak slightly, so they encoded above
the ceiling. It now measures the encoded output and engages the limiter if it
overshot. That cost 0.0-1.1 dB of peak reduction and took the library to
**0.53 LU**. The script does all of this automatically, only for tracks that
need it, and flags any needing more than 5 dB as wanting replacement rather
than processing.

| File | Title | Artist | License | Original URL |
|------|-------|--------|---------|--------------|
| main_menu.ogg | Balefire (menu pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/balefire/ |
| map.ogg | Legionnaire, 2022 Remaster (map pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/legionnaire-2022/ |
| combat.ogg | The Great Battle (Act 1 pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-the-great-battle.html |
| combat_act1_b.ogg | The Vikings (Act 1 pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-the-vikings.html |
| combat_act2.ogg | Monomyth – The Endurance (Act 2 pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/the-endurance/ |
| combat_act2_b.ogg | Uprising (Act 2 pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/uprising/ |
| combat_act3.ogg | Monomyth – The Fury (Act 3 pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/the-fury/ |
| combat_act3_b.ogg | Goliath (Act 3 pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/goliath/ |
| combat_elite.ogg | March of Midnight (elite pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/march-of-midnight/ |
| combat_boss.ogg | Juggernaut (boss pool, acts 1–2) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/juggernaut/ |
| combat_boss_act3.ogg | Terminus (Act 3 boss) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/terminus/ |
| shop.ogg | Medieval: Market Day (loop) | RandomMind | CC0 | https://opengameart.org/content/medieval-market-day |
| rest.ogg | Echoes of Home (rest pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/echoes-of-home/ |
| event.ogg | The Old Ones (event pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/the-old-ones/ |
| victory.ogg | Born of the Sky (victory) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/born-of-the-sky/ |
| defeat.ogg | Unraveling (defeat) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/unraveling/ |
| combat_act1_c.ogg | Medieval: Battle (Act 1 pool) | RandomMind | CC0 | https://opengameart.org/content/medieval-battle |
| combat_act1_d.ogg | Battle of the Creek (Act 1 pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-battle-of-the-creek.html |
| combat_act2_c.ogg | Heroic Demise (Act 2 pool) | Matthew Pablo | CC-BY 3.0 | https://opengameart.org/content/heroic-demise-updated-version |
| combat_act2_d.ogg | Valhalla (Act 2 pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-valhalla.html |
| combat_act3_c.ogg | Medieval Metal (Act 3 pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-medieval-metal.html |
| combat_act3_d.ogg | Simulacra (Act 3 pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/simulacra/ |
| combat_elite_b.ogg | Prepare for War (elite pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-prepare-for-war.html |
| combat_elite_c.ogg | Eyes in the Void (elite pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/eyes-in-the-void/ |
| combat_boss_b.ogg | Song of the Forge (boss pool, acts 1–2) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/song-of-the-forge/ |
| combat_boss_c.ogg | Vanguard (boss pool, acts 1–2) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/vanguard/ |
| map_b.ogg | Medieval: Exploration (map pool) | RandomMind | CC0 | https://opengameart.org/content/medieval-exploration |
| map_c.ogg | Medieval Loop One (map pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-medieval-loop-one.html |
| map_d.ogg | Medieval Chateau (map pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-medieval-chateau.html |
| rest_b.ogg | Medieval: The Old Tower Inn (rest pool) | RandomMind | CC0 | https://opengameart.org/content/medieval-the-old-tower-inn |
| rest_c.ogg | Medieval: The Bard's Tale (rest pool) | RandomMind | CC0 | https://opengameart.org/content/medieval-the-bards-tale |
| shop_b.ogg | Medieval: Minstrel Dance (shop pool) | RandomMind | CC0 | https://opengameart.org/content/medieval-minstrel-dance |
| shop_c.ogg | Tavern Tales (shop pool) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-tavern-tales.html |
| event_b.ogg | The Dark Amulet (event pool) | Matthew Pablo | CC-BY 3.0 | https://opengameart.org/content/the-dark-amulet-dark-mage-theme |
| event_c.ogg | Penumbra (event pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/penumbra/ |
| main_menu_b.ogg | Memories of Stone (menu pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/memories-of-stone/ |
| main_menu_c.ogg | A Dragon's Lullaby, 2023 Remaster (menu pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/a-dragons-lullaby-2023/ |
| map_e.ogg | Adventure (map pool, act 1) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-adventure.html |
| map_act2.ogg | Sunguard (map anchor, act 2) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-sunguard.html |
| map_act3.ogg | Monomyth – The Encounter (map anchor, act 3) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/the-encounter/ |
| combat_boss_d.ogg | Hour of the Witch (the Pyromancer's keep) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/hour-of-the-witch/ |
| combat_boss_e.ogg | The Summoning (the Acolyte's keep) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/the-summoning/ |
| net_lobby.ogg | Jade (skirmish muster pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/jade/ |
| net_lobby_b.ogg | Pathfinder (skirmish muster pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/pathfinder/ |
| credits.ogg | With These Hands (credits) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/with-these-hands/ |
| event_dread.ogg | Incantation (event pool, bone/ember moods) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/incantation/ |
| event_wry.ogg | Magic Tavern (event pool, gilt/verdigris moods) | Alexander Nakarada | CC-BY 4.0 | https://www.free-stock-music.com/alexander-nakarada-magic-tavern.html |
| victory_boss.ogg | Hyperion (victory pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/hyperion/ |
| rest_d.ogg | Amberlight (rest pool) | Scott Buckley | CC-BY 4.0 | https://www.scottbuckley.com.au/library/amberlight/ |

Every screen now picks at random from a pool, with the previously-played track
excluded so the same song never plays twice in a row: map ×3 per act (each act
has its own anchor), combat ×4 per act, elite ×3, boss = one fixed leitmotif
per rival lord (+ a ×3 book for non-rival strongholds; act 3 keeps its fixed
heavyweight), rest ×4, event ×2–3 mood-matched (bone/ember = dread book,
gilt/verdigris = wry book), shop ×3, menu ×3, skirmish muster ×3, dedicated
credits + victory ×2. `AudioBank.play_music` also remembers each track's
playback position and resumes there when the track re-enters rotation, so
intros don't wear out.

Scott Buckley attribution format: "'Track' by Scott Buckley — released under
CC-BY 4.0. www.scottbuckley.com.au". Nakarada: "Track by Alexander Nakarada
(CreatorChords) — creatorchords.com, CC-BY 4.0". Matthew Pablo: credit with
matthewpablo.com per http://www.matthewpablo.com/services.

## Required attribution (CC-BY 3.0)

These credits must stay visible to players (currently in the in-game Credits screen):

- "Heroic Demise" and "The Dark Amulet" — composed by Matthew Pablo (matthewpablo.com)

## Swapping tracks

To replace any track, drop a new `.ogg` / `.mp3` / `.wav` into this folder with
the same filename (the part before the extension is what `AudioBank.play_music()`
matches on). Loop seams matter — pick "seamlessly looping" tracks where you can.

## Format notes

**The library is OGG Vorbis** as of 2026-09-14 and new tracks should be too.
`AudioBank._resolve_music_path` tries `.ogg` before `.wav` before `.mp3`, so an
`.ogg` dropped beside an old `.mp3` of the same name silently wins — which is
convenient for auditioning and a trap if you forget the loser is still there.
Avoid MP3 for anything that loops (encoder delay + padding, see above). To
convert a single file with ffmpeg:

```
ffmpeg -i input.mp3 -c:a libvorbis -q:a 5 output.ogg
```
