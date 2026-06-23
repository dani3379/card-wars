# Spell Art Audit — `assets/spells/`

Audited all 62 PNGs by direct visual inspection, cross-referenced against `scripts/data/CardDB.gd` for thematic fit.

**Overall craft note:** the spell art is markedly *off the project's stated standard*. The card/event art is PD-master oil painting (Doré/Vrubel/Goya). The spell art is almost entirely **stylized digital / AI "energy effect" pieces** — cel-shaded swirls, glowing orbs, and radial bursts. Individually most are competent and on-theme; the *systemic* defect is that ~third of them collapse into a handful of interchangeable "swirling energy" templates that a player cannot tell apart at hand-card size. Only a few (`war_council`, `lost_tome`, `time_snare`, `venom_tip`, `apocalypse`, `gambit`) actually reach the painterly bar set by the rest of the game.

**Orphan assets (no CardDB entry — verify before spending art budget):** `barricade`, `lightning`, `second_wind`. These ids are not referenced in CardDB.gd; they may be renamed/retired cards. `adrenaline.png` is the live art for the card *named* "Second Wind" (id `adrenaline`), so `second_wind.png` is a likely-dead duplicate-purpose file.

**Display-name vs file-id traps used in fit judgments:** `scrap`="Cinders", `adrenaline`="Second Wind", `turbo`="Frenzy", `recycle`="Salvage", `concentrate`="Immolate", `battle_hymn`="Wildfire", `mending_light`="Censer Light".

---

## Exact / near duplicates

### Exact (byte-identical) — must fix
| files | note |
|---|---|
| `mass_grave.png` == `plague_bell.png` | Confirmed identical (md5 `f871e76d…`, same 1,720,881 bytes). Art = purple necrotic burst with grasping dead hands from the earth. **Fits `mass_grave` perfectly — keep it there.** Give `plague_bell` its own art: a literal cracked/tolling **plague bell** (a great-bell swinging, rats/miasma at its foot), which also reads as its "ring → AoE → recast" loop. Doré's bell-tower etchings or a Bruegel plague scene are on-brand subjects. |

### Near-duplicate / visually interchangeable clusters
These aren't byte-identical, but at card scale a player can't distinguish them. Each cluster should be diversified (different focal subject, not just a hue swap).

1. **"Concentric swirl / radial burst" family — the worst offender (11 images).** All are the same centered spiral-or-explosion of energy with only the hue changed:
   `war_cry` (red swirl), `war_chant` (gold swirl), `shove` (brown rock swirl), `echo_spell` (purple swirl), `adrenaline` (red swirl), `turbo` (red core-burst), `scrap` (orange burst), `overwhelming_force` (gold burst), `inspire` (gold spiky burst), `battle_hymn` (gold fire-rings), and partly `inferno` (orange burst). Several of these are *buffs the player must read instantly* (war_cry vs inspire vs overwhelming_force vs king's_command). They are currently a wall of identical orange/red swirls. **Highest-value diversification target.**
2. **"Warm light through clouds" (holy/heal) family (5 images):** `holy_smite`, `smite_spell`, `lay_on_hands`, `mending_light`, `patch_up` — all golden god-rays/bursts in cloud. `holy_smite` (light pillar on a sigil) and `patch_up` (tight glow) are the strongest; `smite_spell` and `lay_on_hands` are near-interchangeable golden explosions.
3. **Fire-orb + ice-orb pair (2 images):** `soul_swap` and `reposition` are the *same idea* — a blue orb and a fiery orb exchanging. `soul_swap` (yin-yang swap) is the better read; `reposition` (move a creature) should get a distinct image (e.g. a chess-piece/figure relocating on a board).
4. **Burning scroll/document (2 images, + 2 cousins):** `unholy_bargain` and `provision` are both flaming scrolls. `recycle` (burning book) and `lost_tome` (a tome) are adjacent. See POOR FIT for `provision`.
5. **Blue arcane disc (2 images):** `concentrate` and `banish` both center a glowing blue rune-ring/portal; `shield_wall` and `curse` are adjacent blue/green hex-tablets (those two read fine on their own).

---

## REPLACE — low quality / off-style
Ranked worst-first.

| id | what's wrong (specific) | suggested better subject / PD master |
|---|---|---|
| `charge_spell` | **Worst in set.** 362 KB — ~3× smaller than every other file (next smallest is 1.1 MB). Renders as a low-detail letterboxed crop: red rock spires on teal sky with a large empty/black lower band. Looks broken/placeholder, not a finished card. Does not read as "Charge!" (a creature striking every lane) at all. | A cavalry/infantry charge in motion. Doré's battle plates, or Géricault/Meissonier charge paintings (all PD). Must be a full-frame painterly piece. |
| `concentrate` ("Immolate") | Hard thematic mismatch *and* low craft: spell is named **Immolate** and deals fire damage, but art is a cold **blue arcane rune circle**. Wrong element entirely; also near-dupes `banish`. | A figure/target engulfed in flame; "immolation" pyre. Any of the existing strong fire pieces' quality level (cf. `inferno`). |
| `provision` | Burning, disintegrating scroll. Spell **summons a 1/1 Soldier** — art shows destruction of a document, the opposite read. Also near-identical to `unholy_bargain`. | A soldier/recruit stepping forward from a muster line; a quartermaster handing out arms; a fresh banner planted. |
| `offering` | Off-theme: spell **sacrifices your own creature** for Command, but art is a serene blue floating soul-crystal with no death/blood/altar cue (reads as a mana gem; also echoes `frost_bolt`'s crystal). | A sacrificial altar / a body laid on an offering stone / a knife over a victim. Goya's darker plates, or a Bosch detail. |
| `shove` | Generic brown concentric dust-swirl — one of the interchangeable-vortex family, and the weakest of them. Doesn't read as a directed *shove/knockback* (it's radial, not directional). | A figure being knocked/thrown back; a shield-bash; a directional shockwave. |
| `adrenaline` ("Second Wind") | Generic red heart-shaped energy vortex; another swirl-family clone. Low specificity for "gain Command + draw / second wind." | A runner catching breath / a surge of breath/light into a figure / a bellows reviving embers. |
| `turbo` ("Frenzy") | Generic red molten core-burst; interchangeable with `overwhelming_force`/`scrap`. No "frenzy" read. | A berserker mid-rage; a frothing charge. Fuseli's wild-eyed figures (PD). |
| `echo_spell` | Purple concentric ripple — same swirl template, just purple. Loose "echo = ripple" read but indistinct in hand. | A spell visibly *duplicating* — a mirrored/doubled cast, two identical bolts, a hall-of-mirrors motif. |
| `scrap` ("Cinders") | Competent but generic orange fire-explosion; reads like a small `inferno`. Theme ("discard for Command / cinders") is dying coals, not a blast. | A heap of glowing embers/cinders; a card curling to ash. |
| `ambush` | Green crystal-shard burst. Doesn't convey *ambush* (no surprise/stealth/trap cue); also shares the green-shard look with `quick_shot`. | A trap springing / figures lunging from cover / a hidden volley. Doré's forest-ambush etchings (PD). |

---

## POOR FIT — art doesn't match the spell
(Subset of the above where the *mismatch* is the primary defect, plus borderline cases worth noting. The first three are also in REPLACE.)

| id | spell effect | mismatch |
|---|---|---|
| `concentrate` ("Immolate") | Deal 4 *fire* damage; if it dies, 4 to face | Cold blue arcane circle — wrong element. |
| `provision` | Summon a 1/1 Soldier | Burning scroll — shows destruction, not summoning a soldier. |
| `offering` | Sacrifice a friendly creature, gain 2 Command | Calm blue soul-crystal — no sacrifice/altar/death cue. |
| `hoarfrost` *(borderline — keep)* | Friendly gains Shield; opposing enemy can't attack | Art is a frost-encrusted armored *warrior figure* — reads as a frozen creature/portrait more than a spell effect. Thematically frost+defense is fine; flagged only because it reads like a creature card, not a spell. Craft is good. |
| `recycle` ("Salvage") *(borderline — keep)* | Exhaust a card, gain Command = its cost | Burning book — leans "destroy" over "salvage value," and overlaps `lost_tome`. Acceptable but not ideal. |

---

## OK
Solid fit and acceptable-to-good craft; no action needed:

`strike`, `fireball`, `flame_bolt`, `frost_bolt`, `inferno`, `lightning`, `holy_smite`, `patch_up`, `blood_tithe`, `bloodletting`, `dark_pact`, `unholy_bargain`, `fuel_the_pyre`, `mass_grave`, `reanimate`, `grave_robbery`, `grave_pact`, `soul_swap`, `banish`, `time_snare`, `hex`, `curse`, `venom_tip`, `wound`, `earthquake`, `cataclysm`, `apocalypse`, `ricochet`, `quick_shot`, `slash`, `reckless_charge`, `pillage`, `gambit`, `kings_command`, `shield_wall`, `lost_tome`, `war_council`, `mending_light`, `smite_spell`, `lay_on_hands`, `battle_hymn`, `inspire`, `overwhelming_force`, `war_cry`, `war_chant`, `reposition`, `barricade`*, `second_wind`*, `lightning`*

> *`barricade`, `second_wind`, `lightning` are listed OK on craft/fit but are **orphan assets** (no CardDB entry) — confirm they're still used before relying on them. `war_cry`/`war_chant`/`reposition`/`smite_spell`/`lay_on_hands` are "OK" individually but are flagged above as **near-duplicate cluster members**: if you only fix duplicates and not single-image quality, prioritize breaking up those clusters over replacing them outright.

### Standouts (closest to the game's PD-master bar — use as the quality target)
`war_council` (warriors round a torchlit war-table — genuinely painterly), `lost_tome`, `time_snare` (antique watch in blue flame), `apocalypse` (black-sun eclipse over a burning city), `venom_tip`, `gambit` (cards + dice in a gold vortex), `shield_wall`.
