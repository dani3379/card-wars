# Creature Art Audit — Batch 1 (39 ids)

Scope: first half of `assets/creatures/`. Standard = AAA-tier PD-master painting
(Doré, Vrubel, Fuseli, Goya, Bosch, Bruegel…) — moody, painterly, high-craft.

**Key finding on the set's style:** the live `.png` art is NOT PD-master painting.
It is a single, internally-consistent AI/illustration house style — inked outlines
over warm painterly fantasy (Mignola / Darkest-Dungeon / modern-deckbuilder look).
As a *body of work it is competent and cohesive*, and most of it reads well at card
size. Judged strictly against "next to a Doré engraving," none of it is a Doré — but
flagging the whole set as REPLACE would be neither fair nor actionable. So REPLACE
below is reserved for genuine defects: a corrupted file, a low-res fragment, and the
pieces that break the house style by being overtly cartoon/chibi. Everything stylish-
but-not-a-master is parked in OK.

**Loader fact (verified in `CardArtAliases.try_load_creature_art`):** the `.png` is
loaded first; the `.jpg` only loads if the `.png` is missing or imports broken. So in
every id.jpg + id.png pair, **players see the `.png`** and the `.jpg` is a dormant
fallback. Several of those dormant `.jpg`s are actual PD masters (Doré, Vrubel,
Fuseli, von Stuck) that were superseded by the AI `.png`.

---

## Exact / format duplicates

Six ids ship both a `.png` and a `.jpg`. The `.png` is what renders. In all six the
`.jpg` is a genuine PD-master painting that was replaced by the AI `.png`. None are
*pixel* duplicates — they are redundant *format/source* pairs. Recommendation per row:

| id | live (.png) | dormant (.jpg) | keep | note |
|---|---|---|---|---|
| `e_devil_champ` | AI ram-demon, **CORRUPTED** (see REPLACE) | Franz von Stuck — *Lucifer* (clean, on-theme) | **keep the .jpg / re-derive .png** | the live .png is defective; the .jpg is both clean and a master |
| `chaos_imp` | cartoon Gengar-imp | Vrubel — *Demon Seated* | judgment call — see REPLACE | .png is off-style cartoon; Vrubel is the named standard but is a brooding nude, weak literal fit for "imp" |
| `corpse_eater` | gluttonous toad in bone-rubble (good fit) | Grünewald — *Temptation of St Anthony* (159 KB, framed altarpiece, multi-figure) | **keep .png; delete .jpg** | .png fits the card far better; the .jpg is a low-res framed crop |
| `doppelganger` | ghost-face over a crypt (good fit) | Fuseli — *The Nightmare* | **keep .png; archive .jpg** | both strong; .png is the better literal fit for "copy the dead" |
| `bloodsworn` | warpaint oath-taker over a fire (good fit) | Doré — *Lucifer / fallen angel* | **keep .png; archive .jpg** | both strong; .png fits "the oath" better |
| `archmage` | enthroned storm-wizard, zodiac ring (good fit) | Pyle/Rackham-style pen wizard at desk | **keep .png; delete .jpg** | .png is the stronger, on-theme piece |

Cleanup: the six `.jpg`s (+ their `.import` files) are dead weight on disk. Safe to
remove `corpse_eater.jpg` and `archmage.jpg` outright. Keep `e_devil_champ.jpg` until
the .png is fixed. The Vrubel/Fuseli/Doré `.jpg`s are worth *archiving* (not in
`assets/`) if you ever swap back toward a true-master look.

---

## REPLACE — low quality / off-style  (worst first)

| # | id | what's wrong | suggested fix / better source |
|---|---|---|---|
| 1 | `e_devil_champ` | **Corrupted file** — a block of rainbow/glitch noise is baked into the right edge of the .png. A hard defect, and it's an Act-3 boss ("Devil's Champion"), so it's highly visible. Worse, it's the alias target for `pit_fiend`, `infernal`, `tormentor`, `devils_champion` — the glitch shows on 5 cards. | Re-export/inpaint the .png to kill the noise band, OR fall back to the clean `e_devil_champ.jpg` (von Stuck *Lucifer*) which is on-theme. Fastest real fix. |
| 2 | `e_goblin` | **Low-res + bad crop + off-style.** ~600 KB vs ~2 MB for siblings; visibly soft/pixelated; it's a cropped pen-ink *fragment* of a bird/vulture-headed figure, not a finished piece. Clashes with the whole polished set. Also the alias target for `runt`, `spawn`, `kobold_hurler` — the weak art repeats on 4 cards. | New goblin in the house style (small, snarling, crude weapon). Tone reference: a Brueghel/Bosch grotesque if going master-route. High priority — it's an Act-1 staple. |
| 3 | `chaos_imp` (.png) | **Overtly cartoon / off-style.** A grinning Pokémon-Gengar-style imp; reads as a kids' mascot next to the rest. Most jarring style break in the player pool. Alias target for `imp`, `hellfire_imp`, `lesser_demon`, `siphon_imp` — repeats on 5 cards. | Repaint as a small chaotic spell-imp in the house ink style, OR restore the Vrubel `.jpg` if you want the master look (note Vrubel reads as "seated demon," not "imp"). |
| 4 | `duelist` | **Chibi proportions** (big-head/cute) — the most cartoonish *player* piece; breaks the otherwise grounded fencer read. Aliased by `glass_knight`, `lancer`, so the chibi repeats on 3 cards. | Repaint as a poised, normal-proportioned duelist mid-lunge. Lower severity than 1–3 (still competent, just off-register). |

Borderline (NOT replacing — listed for transparency, would only act in a master-purity
pass): `cinder_whelp` (jack-o'-lantern fire-blob, simple), `blood_pyre` (cute Groot-
on-fire chibi), `dragon_hatchling` (cute baby dragon). All three are *intentionally*
small/comic creatures and the art matches the card's tone, so they pass.

---

## POOR FIT — art doesn't match the card

| id | card concept | mismatch |
|---|---|---|
| `e_wind_harpy` | "Wind Harpy" — a harpy (classically a winged woman) | Art is a **storm owl**, not a harpy. Great image and reads as a wind/storm flyer, so it's a soft mismatch, not a defect. Note only. Also alias target for `storm_harpy`/`salt_harpy`/`chick`/`fledgling`. |
| `e_goblin` | "Goblin" — small crude humanoid | Reads as a **vulture/bird-man fragment**, not a goblin (also covered under REPLACE for quality). Double-flagged because the silhouette is wrong even apart from resolution. |

Everything else matches its card concept well. Strong literal fits worth noting:
`brute` (raging ogre razing a hall), `e_bone_knight`, `e_dark_priest`, `crow_witch`,
`corpse_eater` (.png), `doom_knight`, `e_drake`/`e_elder_dragon`, `e_headsman`.

---

## OK

archmage, assassin, bannerman, battle_drummer, berserker, blood_pyre, bloodhound,
bloodsworn, brute, cauldron, chorus_of_echoes, cinder_whelp, copycat, corpse_eater,
crow_witch, doom_knight, doppelganger, dragon_hatchling, e_archer, e_bog_lurker,
e_bone_knight, e_brute, e_collector_champ, e_cultist, e_dark_priest, e_drake,
e_elder_dragon, e_enforcer, e_fire_elemental, e_golem, e_headsman, e_scout,
e_warden_champ, ember_mystic
