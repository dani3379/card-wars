# Creature Art Audit — Batch 2

Scope: second half of `assets/creatures/` (the 51 ids assigned). Standard = AAA-tier public-domain master painting mood (Doré / Vrubel / Fuseli / Goya / Bosch / Böcklin), moody and painterly. Defects = low-res / blurry / cartoonish / generic AI-character-sheet / thematically wrong art.

Overall this batch is **strong** — the dominant house style (warm inked-illustration with a woodcut border) is consistent and high-craft across the great majority. Only one true off-style render, plus two redundant format pairs and a cluster of small/low-res files that are acceptable-but-soft.

---

## Exact / format duplicates

| files | verdict | keep / delete |
|---|---|---|
| `kindling.png` + `kindling_alt.png` | **Byte-identical** (md5 `7b4b0c93ca96ba21da2d763ffaf2df7a` on both, 302,858 B each). Confirmed. | Keep `kindling.png`; **delete `kindling_alt.png`** (+ its `.import`). Nothing references `_alt` that a single file wouldn't serve. |
| `mana_sprite.png` + `mana_sprite.jpg` | **Redundant format pair, and DIFFERENT images.** The `.png` is a glowing forest sprite-bug (on-theme for "Errand Sprite"); the `.jpg` is a portrait-orientation snarling green goblin/troll face — wrong subject, wrong aspect, lower quality. The loader (`CardArtAliases.try_load_creature_art`) prefers `.png`, so the `.jpg` never displays. | Keep `.png`; **delete `mana_sprite.jpg`** (+ `.import`). Dead file. |
| `warden_of_graves.png` + `warden_of_graves.jpg` | **Redundant format pair.** `.png` is the bespoke skull-masked grave-warden (on-theme) and is what loads. The `.jpg` is actually a genuine PD master — Böcklin's *Self-Portrait with Death Playing the Fiddle* (1872) — high quality but a portrait self-portrait that fits the card far worse than the png, and it's never shown. | Keep `.png`; **delete `warden_of_graves.jpg`** (+ `.import`). Quality orphan, but dead and off-concept. |

Note: `mana_sprite` (line 24) and `sellsword` (line 90) and `stone_wall` (line 25) and `ironclad_veteran` (line 26) each have an ALIAS entry pointing elsewhere **and** a dedicated direct file — the direct `.png` always wins, so those aliases are dead/misleading but are not art-quality bugs.

---

## REPLACE — low quality / off-style (worst first)

| id | what's wrong (specific) | suggested better subject / PD master |
|---|---|---|
| **hydra** | **Worst offender.** Not house-style at all: a single bipedal lizardman/dragonborn **character-concept render on a flat gray studio background with a crude red scribble** behind it — classic low-effort AI character sheet. Also thematically wrong: "Hydra" (3/6, should read as a many-headed serpent) shows one lizard-man. Low file size (828 KB) confirms low detail. Worse: `basilisk`, `spore_beast`, `mycelium`, `hydra_spawn`, `void_maw` all ALIAS here, so the bad art propagates to ~5 more creatures. Ironically the in-batch `naga.png` is a beautiful serpent that is exactly what a hydra should look like. | A coiled multi-headed sea-serpent in the inked-illustration house style; or a PD master — Gustave Doré's hydra/Lernaean engravings, or a Böcklin sea-monster. |
| **scholar** | Low-res, murky dungeon interior of a hooded figure at a chest/altar with rising smoke. Reads as an **environment/loot scene, not a "Scholar"** (2/3 learned figure). Subject is ambiguous and the file is small/soft. Both a quality and a fit problem. | A robed sage/reader at a lectern with tomes and candlelight — Rembrandt's *Philosopher in Meditation* / *Scholar* mood, or a Doré study figure. |
| **kindling** (= `kindling_alt`) | Small (302 KB), low-res, and **cartoonish** — a cute smiling flaming jack-o'-lantern ember creature. Below the PD-master bar; the cutesy face is the weakest tonal fit in the batch. It's a 1-cost token, so low stakes, but it stands out as slop next to its neighbors. | A small painterly ember-elemental / will-o'-the-wisp; Vrubel-style flame study. (Low priority — token.) |
| **torchbearer** | Same small/low-res, slightly-cartoonish child-with-torch token as `kindling`. Acceptable but the softest of the "human" cards. Aliased by `kindler`, `burning_martyr`, `cinder`, `pyre_tender`, so it recurs. | A painterly lone figure bearing a torch in dark woods, more rendered/less chibi — Goya nocturne mood. (Low priority.) |

---

## POOR FIT — art doesn't match the card

| id | card concept | mismatch |
|---|---|---|
| **hall_watcher** | Name implies a **guardian/sentinel figure** keeping a hall. | Image is a wide, low-res **burning-cathedral-of-smoke architecture scene** with no clear creature subject — reads as a location, not a watcher. |
| **hydra** | Many-headed serpent (3/6). | Shows a **single bipedal lizard-man**, not a hydra. (Also the top REPLACE entry above — quality + fit both fail.) |
| **scholar** | A learned figure (2/3). | Murky dungeon **loot/altar scene**; no recognizable scholar. (Also a REPLACE entry.) |

(Borderline, NOT flagged as poor fit: `trebuchet`, `stone_sentinel`, `the_black_tide`, `whisper_king`, `the_crone`, `risen_lich`, `treasure_hunter` — these are matte-painting-soft and/or low-res relative to the inked house style, but each is thematically on-target. They are acceptable; only flag for replacement if doing a polish sweep. `trebuchet`/`stone_sentinel`/`the_black_tide` are the softest, least-house-style of these.)

---

## OK

goblin, gravedigger, griffin, harpy, hatchling_brood, hound, iron_bastion, ironclad_veteran, leyline_conduit, lookout, mana_sprite (png), militia, mirror_knight, mule, naga, necromancer, paladin, pikeman, ranger, ratling, raven, risen_lich, royal_guard, scavenger, sellsword, sentinel, shieldbearer, siege_golem, sprite, squire_captain, stone_sentinel, stone_wall, stray_cat, summoner, the_black_tide, the_crone, thornguard, treasure_hunter, trebuchet, troll, vampire_lord, vengeful_spirit, warden_of_graves (png), whisper_king, witch, wolf_c

---

### Repetition note (not a per-file bug — by design, but worth flagging)

A handful of base portraits carry an outsized share of the roster via `CardArtAliases.ALIASES`, which can make the game look samey in a run that leans on those archetypes:

- **`hound`** — ~14+ ids alias here (wolf, dire_wolf, alpha, pup, cub, camp_mutt, cinder_pup, ash_hound, pack_wolf, alpha_wolf, den_mother, bloodhound, cleave_hound, wake_hound). The single snarling-spiked-collar dog is reused the most heavily in the whole set.
- **`royal_guard`** — ~15 ids (captain, bandit_captain, standard_bearer, banner-bearer, hall-watcher, centurion, eagle-bearer, hymn_bearer, forge_guardian, ice_elemental, void_guard, temple_guardian, display_case, shieldmaiden, …).
- **`e_archer`** (out of batch, but noted): ~13 archer ids. **`witch`**: ~10 (banshee, hexer, geomancer, pyromancer, swamp_hag, conductor, maestro, ash_master, …). **`siege_golem`**, **`e_brute`**, **`naga`**, **`e_bone_knight`**, **`e_cultist`** are similarly stretched.

The art quality of these bases is good, so the reuse is "carried" — but if budget allows, a few extra hound/guard/archer variants would most reduce the visual repetition the player actually sees.
