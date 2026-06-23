# Art Audit — Master Summary (2026-06-22)

Six agents visually inspected every image in `assets/creatures` (91), `assets/spells`
(62), `assets/events` (33), `assets/portraits` (19), `assets/backgrounds`, and
`assets/icons/relics` (122), cross-referenced against CardDB / EncounterDB / Event.gd /
RelicDB and the `CardArtAliases` reuse map. Per-category detail in the sibling files
(`creatures_1.md`, `creatures_2.md`, `spells.md`, `events.md`,
`portraits_backgrounds.md`, `relic_icons.md`).

Key framing: heavy art **reuse via `CardArtAliases`** (e.g. ~14 ids → `hound`) is BY
DESIGN, not a bug. The findings below are genuine defects, true duplicates, dead files,
and quality/fit misses.

---

## A. VISIBLE DEFECTS — fix first (shipping in the build right now)

| # | file | defect |
|---|---|---|
| 1 | `events/dark_altar.png` | Garbled fake watermark **"KIRY THE STIRE"** (a mangled *Slay the Spire*) baked into the corner — an off-brand AI text artifact in a shipped asset. Also wrong subject (sword-in-stone, not a blood-altar). **Regenerate.** |
| 2 | `creatures/e_devil_champ.png` | Corrupted rainbow/glitch band baked into the file, on an **Act-3 boss**, and it propagates to ~5 aliased ids (pit_fiend/infernal/tormentor/devils_champion). Clean von Stuck *Lucifer* `.jpg` already sits beside it as a fallback. |
| 3 | relic icons: wrong-subject dupes | `hexagonal_shield`=a courier bag, `war_drum`=a flaming barrel, `banner_of_unity`=a lantern. The icon shows a different relic's art entirely. |

## B. EXACT DUPLICATE FILES (two different game entities, byte-identical art)

- `creatures/kindling.png` == `kindling_alt.png` → delete `_alt` (nothing needs it).
- `spells/mass_grave.png` == `plague_bell.png` → keep on mass_grave; plague_bell needs its own bell art.
- `events/fork_in_the_long_road.png` == `backgrounds/event_forest.png` → recycled background; needs bespoke fork art.
- **6 relic-icon pairs** (md5-identical): collectors_tome/worn_spellbook, coin_purse/scavengers_pouch, couriers_bag/hexagonal_shield, sozu/war_drum, mimic_ring/scouts_emblem, banner_of_unity/soul_lantern — in each the *second* shows the wrong subject (see A#3).

## C. DEAD / ORPHAN FILES (never loaded — safe to delete)

Loaders prefer `.png`, so these never render:
- **Creature `.jpg` fallbacks:** archmage, bloodsworn, chaos_imp, corpse_eater, doppelganger, mana_sprite, warden_of_graves (+ keep `e_devil_champ.jpg` until its png is fixed). Several are real PD masters (von Stuck/Vrubel/Fuseli/Böcklin) worth *archiving outside* `assets/` if a master-look swap is ever wanted.
- **Portrait/background `.jpg`s:** main_menu, rest_campfire, event_forest, shop_tavern, map_parchment, player_knight (Dürer — off-shape for a portrait slot).
- **Orphan PNGs / stubs:** `events/gambler.png` (no gambler event), `.import` stubs `blacksmith_offer`/`burning_cradle`/`mysterious_shrine` (no event, no png), spell ids `barricade`/`lightning`/`second_wind` (no CardDB entry — verify first).
- **54 legacy `.svg` relic icons** shadowed by PNGs (dead weight).

## D. REPLACE — low quality / off-style (needs new art)

**Creatures (worst-first):** `hydra` (AI lizardman char-sheet on gray studio bg, →5 aliased cards), `e_goblin` (low-res bird-man fragment, →4 cards), `chaos_imp` (cartoon Gengar, →5), `duelist` (chibi, →3), `scholar`, `hall_watcher` (reads as a building), `kindling`, `torchbearer`.

**Spells — systemic:** the spell set is digital "energy effect" art, off the game's PD-master bar. ~11 buffs collapse into one interchangeable orange/red **swirl/burst** template (war_cry/war_chant/inspire/overwhelming_force/turbo/scrap/adrenaline/echo_spell/shove…) — a player can't tell them apart in hand. Worst single file: `charge_spell` (362 KB, broken-looking letterbox crop). Wrong element/subject: `concentrate`="Immolate" is a *blue* circle, `provision` (summon a soldier) is a burning scroll, `offering` (sacrifice) is a calm soul-gem.

**Events:** `coin_on_edge` (dirt pit, no coin), `butcher` (low-res). Poor fit: `strangers_hand`, `two_headed_calf`, `woodcutter`, `hollow_lantern`. 5 pixel-art entries (beekeeper_again, beekeeper_returns, drowned_bell, marked_one, mirror_twin) clash with the painterly majority.

**Portraits:** `player_knight.png` — off-style anime/comic, **and it's the loaded in-combat hero avatar**; `boss_the_crone.png` — a crowned skeleton king, not a crone (miscommunicates the fight; also a 3rd near-identical lich face).

**Relic icons:** two incompatible styles share the HUD tray — "rim-light cutout" (house look) vs ~17 "full painterly oil" outliers (pen_nib, soul_ledger, skull_throne, mana_tide/pearl, glowing_hand, snecko_eye, several banners…). Plus ~7 subject mismatches: cursed_key=hammer, war_horn=map, pyromaniac_ring=stone, veterans_medal=dice, champions_belt=helm, marathoners_sash=coins, glass_cannon=600px crown.

## E. CONTENT GAPS (no art exists)

- **Kindler hero has NO portrait and NO silhouette** — only 4 of 5 heroes are painted. Biggest single gap (degrades to a placeholder crest / ghosted rectangle).
- **12 relics have no icon** (null fallback): the 4 event relics, the 8 "Wave-2" synergy relics, and `ember_censer`.
- Named rival-lord / amalgam bosses share the generic per-act splash (no `boss_<id>.png`).

## F. SAMEYNESS (by design, but variants would help most)

Alias bases carrying an outsized share of the roster: `hound` (~14 ids), `royal_guard`
(~15), `e_archer` (~13), `witch` (~10), plus siege_golem/e_brute/naga. A few extra
variants here would cut the visual repetition a player actually notices.

---

### Suggested order of operations
1. **A** (3 visible defects) — regenerate dark_altar, fix/restore e_devil_champ, repaint the 3 wrong-subject relic icons.
2. **E** (Kindler portrait+silhouette, the 12 missing relic icons) — fills holes the player hits.
3. **B** (give plague_bell / fork / the 6 relic dupes their own art).
4. **C** (mechanical cleanup — delete orphans; quick disk + clarity win, no art needed).
5. **D / F** (quality + variety pass — largest, art-sourcing-bound, do one at a time).
