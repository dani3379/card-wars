# ART REPLACEMENT SWEEP — 2026-09-08

**Every shipped picture in the game, looked at, with a recorded call.** 598 rows in
[`docs/art_sweep_20260908.csv`](art_sweep_20260908.csv) — one per file, none skipped. The
merge script is [`tools/_art_sweep_20260908.py`](../tools/_art_sweep_20260908.py); re-run it
after any art change and the table rebuilds.

| verdict | n | meaning |
|---|---|---|
| **R1** | 39 | replace — wrong subject, or breaks the set on sight |
| **R2** | 149 | regrade or reshoot — subject is right, the palette/register is not |
| **D** | 117 | delete — dead file, duplicate, or dev leftover |
| **K** | 293 | keep |

Method: contact sheets per family (~24 images a sheet) viewed in full, cross-read against
`tools/art_lint.py` metrics and a liveness grep of `scripts/` + `scenes/`. **Every "wrong
subject" call was then re-checked at full resolution, and six of them were wrong** — see
§7. A thumbnail is enough to judge palette; it is not enough to judge subject.

---

## 1. The seven findings that matter more than any single drawing

> **CORRECTED 2026-09-08 (rev 2): this finding is WRONG as written. Zero relics render blank.**
> `RelicDB.gd:785` holds `ICON_FALLBACKS` (25 entries) and `_resolve_icon_id` (`:820-841`) falls
> through it; 10 of the 25 also carry an explicit `"icon"` field. All 154 relics resolve to a real
> file — `portcullis` → `bulwark_engine`, `old_meg` → `catapult_crew`, `war_bellows` → `war_horn`.
> This is **placeholder sharing, not absence**, and it is the same class as everything else in
> this document rather than the top-priority job. The proposed `_probe_relic_art` gate is dropped:
> it would gate a condition that cannot occur. I checked ids against filenames and never read the
> resolver. See [`ART_PLAN_FINAL_20260908.md`](ART_PLAN_FINAL_20260908.md) §1.

**① 25 relics have no icon of their own** (they borrow another relic's). `RelicDB` has
154 entries; `assets/icons/relics/` has 129 painted files and every SVG is a duplicate of a
PNG, so these 25 ride a fallback:

> articles_of_war · centurions_rule · cerecloth · chain_censer · cinder_crown · drill_book ·
> eagle_of_the_fourth · familiars_quill · forlorn_hope · funeral_lantern · head_money ·
> heads_on_pikes · ledger_seal · marching_spurs · mirror_primer · old_meg · paymasters_tally ·
> portcullis · powder_horn · rearward_horn · reserve_standard · second_rank · sextons_spade ·
> sunken_road_stone · war_bellows

This is the single highest-value art job in the project: 25 drawings that turn blank slots
into relics. `tools/_probe_card_art.tscn` reports 0 artless *cards* — nothing does the same
for relics. **Worth a gate**, on the model of that probe.

**② The Command glyph is cyan — in event text only. (CORRECTED 2026-09-08.)**
`assets/icons/stats/cost_runestone.png` is a neon-glowing blue-cyan runestone. An earlier draft
of this document said it prints on every card; **that was wrong.** `GameTheme` loads it as
`tex_stat_cost` and loads `atk_sword.png` as `tex_stat_atk`, but **neither variable has a single
consumer anywhere in `scripts/`** — the v9 writ draws its stats with the `WaxSeal` painter and
`_cost_label`. The runestone's only live use is `Event.GLYPH_COMMAND`, an inline `[img=20]` in
event body text; `atk_sword.png` is fully dead.

So: still worth replacing (event prose is where the game explains itself, and the glyph is the
one cool note in a warm page), but it is a **small** fix, not the biggest one. `hp_heart.png` is
on style and stays. `atk_sword.png` and the two dead `tex_stat_*` loads can simply go.

**③ The portraits ship in two incompatible house looks, and they sit side by side.**
Flat ink-comic: `boss_act1/2/3`, `boss_collector`, `boss_demon_vanguard`, `boss_dragon_lord`,
`boss_hollow_king`, `boss_iron_warden`, and hero portraits acolyte/pyromancer/raider/stalwart.
Fine-oil: all five `boss_amalgam_*`, all five `boss_rival_*`, `boss_the_crone`, and
`hero_portrait_kindler`. The hero split is the damaging one — those five faces are drawn on
**one screen, in a row**, at muster. Four are flat ink and Kindler is an oil painting.
The 2026-07-22 audit flagged this and asked the owner to pick a family; it is still unpicked.
**This is a decision, not a task** — see §8.

**④ `hero_silhouette_kindler.png` does not exist.** Four of five heroes have a camp
silhouette; `portraits/hero_silhouette_%s.png` is a format string, so Kindler loads nothing.

**⑤ 1,711 image files ship with zero references — about 288 MB.**

| files | tree | note |
|---:|---|---|
| 769 | `assets/icons/kenney_board-game-icons/` | whole kit, never referenced |
| 531 | `assets/_unused/` | 188 MB |
| 283 | `assets/ui/kenney_borders/` | duplicate of the fantasy-ui kit, of which 1 file is used |
| 54 | `assets/icons/relics/_unused/` | 83 MB |
| 29 | `assets/frames/` | the superseded v3 frame set — the live card is drawn by painters |
| 15 | `assets/icons/downloaded/` | clip-art coins, emoji hearts, **a copyright-symbol coin** |
| 30 | `assets/ui/` card-template / fantasy_gui / frame_kit / AI test exports | 14 of 15 root `ui/` files dead; only `card_back.png` lives |

Plus 6 dead `.jpg` twins of live `.png`s (`event_forest`, `main_menu`, `rest_campfire`,
`shop_tavern`, `player_knight`, `e_devil_champ`) — every loader names `.png` explicitly, so
the `.jpg`s are the old photoreal versions the painterly ones replaced. `player_knight.jpg`
is a Dürer engraving; `e_devil_champ.jpg` is a fine-art nude.

**⑥ Three exact duplicates and one dev filename shipped as art.**
`spells/mass_grave.png` == `spells/plague_bell.png` (and neither has a bell in it);
`relics/recruiters_horn.png` == `relics/war_horn.png`; `creatures/kindling.png` ==
`creatures/kindling_alt.png`.
> **CORRECTED (rev 2): none of these is a deletion.** All are live distinct entries needing a
> *second picture* at full price — and **`kindling_alt.png` must never be deleted**: it is the
> deliberate no-art placeholder loaded by name at `Card2D.gd:1063` / `CardTextureCache.gd:253`,
> with a standing waiver at `art_lint.py:201`. `war_horn.png` alone serves five relics via
> `ICON_FALLBACKS`.

And `EventDB` wires
`"art": "the_siege_kitchen-character-stage-v2"` — a generator export filename used as the art
id, with an unreferenced second export beside it.

**⑦ Check the credits screen against reality.** `Credits.gd` bills "ART — CARDS & PORTRAITS"
to "Public-domain masters: Gustave Doré, Mikhail Vrubel, Henry Fuseli, Goya, Bruegel, Bosch".
The `.godot/imported/` cache carries Midjourney export filenames
(`dani3379_a_stamped_guild_trade-license_scroll_bearing_an_offi_<uuid>_2.png` →
`merchants_license.png`), and `feedback_art_sourcing` records the PD-master pass as an
abandoned exploration. The icon/font/music credits are correct and complete —
game-icons.net's **CC BY 3.0 requires attribution and it is properly given**. It is only the
cards-and-portraits line that looks stale. Worth one look before ship.

---

## 2. R1 — replace (39)

### Wrong subject (the card says one thing, the picture says another)
| file | what is actually in frame |
|---|---|
| `relics/thiefs_gloves.png` | a **pink floral folding fan** |
| `relics/swift_boots.png` | a flame-spirit on a teal panel — no boots |
| `relics/fusion_hammer.png` | a gold nugget/cube — no hammer |
| `relics/junk_slot.png` | an empty misty field with a small post — reads unfinished |
| `spells/fuel_the_pyre.png` | a **green** flame column, for a card named *pyre* |
| `spells/plague_bell.png` | a purple cave — no bell; also the exact dup of `mass_grave` |
| `creatures/ember_stalker.png` | a burning wagon |
| `creatures/the_black_tide.png` | a green seascape, no body to fight |

### Tone breaks — cute in a war game
`creatures/stray_cat.png` (a smiling cartoon kitten), `creatures/sprite.png` and
`creatures/torchbearer.png` (chibi children with huge eyes), `creatures/chaos_imp.png`
(a pink many-eyed fluffball on cream), `creatures/hellfire_imp.png`,
`creatures/gravedigger.png`, `creatures/mana_sprite.png`.
Per `feedback_burning_meadow_tone` the register is grim/funny/heroic — these are none of the
three, and the kitten is the loudest miss in the pool.

### Worst cyan (the owner's #1 defect, at its extreme)
`spells/ambush.png` **95%** · `events/hollow_lantern.png` **86%** · `spells/banish.png` **86%** ·
`creatures/vengeful_spirit.png` **82%** (high-traffic: revenant / vengeance / the_undying all
alias to it) · `relics/mana_tide.png` **80%** · `potions/mana_surge.png` (z=25, the biggest
single-family outlier in the game — a neon-blue glow bottle beside twelve warm painted ones).

### Photoreal product shots on black, in a painted family
`relics/coin_landed.png` · `relics/war_drum.png` · `relics/warlords_standard.png` ·
`relics/warm_knucklebone.png` · `events/coin_on_edge.png` ·
`events/fork_in_the_long_road.png` (washed out, no ink left).

### Baked-in defects
`spells/echo_spell.png` — black letterbox bars baked top and bottom (also `events/the_chrysalis.png`, R2).
`creatures/e_bog_lurker.png`, `creatures/mule.png`, `relics/reapers_scythe.png` — a border
painted into the bitmap, inside a card that draws its own frame.

### HUD icons in the wrong register
`icons/map/hud_gold.png` is a **dollar sign**. `icons/map/hud_heart_painted.png` is a **literal
emoji heart**. `icons/map/hud_potion.png` is a **modern chemistry flask**.
(`hud_gold_painted.png` — the cartoon lemon coin with a cyan diamond — is already unreferenced;
delete it.)

### Keyword devices that are UI, not devices
`charge.svg` is a bare **→**. `overrun.svg` is a bare **»** — and reads as charge's twin.
`mustering.svg` is **the same hourglass as `exhaust.svg`**, inverted: two different rules
wearing one glyph at the 18px the rail draws them.

---

## 3. R2 — regrade, don't redraw (149)

The subject is right; the colour or register is not. Most of these do not need a new
generation at all — a **grade pass** (pull the cool cast toward the warm set, raise contrast)
recovers them at a fraction of the cost.

- **Cyan/teal cast (the bulk):** 103 files carry a measurable cool band. Beyond the R1s:
  `spells/lightning · recycle · time_snare · shield_wall · hex · lost_tome`,
  `creatures/glass_knight · chorus_of_echoes · crow_witch · copycat · archmage · assassin ·
  e_golem · leyline_conduit`, `relics/acolytes_tome · lantern · mana_drunkard · mana_pearl ·
  echo_staff · last_breath · phantom_veil · mark_of_pain`, `events/gravesong_choir · sin_eater ·
  blood_fountain · the_answering_well · thrice_blessed_spring`,
  `backgrounds/combat_arena_act2 · rest_campfire_act2 · rest_campfire_act3`,
  `potions/aegis_brew · chain_flask`.
- **One deliberate exception:** `spells/hoarfrost.png` is a frost-caked soldier. **Frost earns
  its cool cast** — this is the one cool asset that should stay cool. Waive it, don't grade it.
- **Magenta/purple outliers:** `relics/conscription_relic · resonance_crystal · runic_pyramid ·
  lichs_bargain · stygian_soul · steady_banner · lean_mean · snecko_eye`,
  `spells/dark_pact · mass_grave · grave_robbery`, `creatures/summoner · raven · cauldron ·
  doom_knight · the_leveler`, `portraits/boss_act2 · boss_demon_vanguard`.
- **Flat black grounds** while the family paints its grounds: `relics/hexagonal_shield ·
  runebound_idol · scavengers_pouch · gravewardens_pact · banner_of_unity · doom_herald`.
- **Register breaks:** `relics/stardust_vial` (a galaxy in a bottle — sci-fi),
  `potions/insight_tonic` (same), `relics/mime` / `velvet_choker` / `happy_flower` /
  `coffee_dripper` (cheerful or modern), `keywords/sniper.svg` (a modern optics reticle),
  `keywords/thorns.svg` (**barbed wire** — 19th century), `keywords/regenerate.svg` (a medical
  cross), `keywords/poison.svg` (an emoji sad face), `keywords/retain.svg` (a question mark),
  `keywords/adj_buff.svg` + `on_enter.svg` (infographic figures-and-arrows),
  `game-icons/shop.svg` (**a modern shopfront with an awning** — the sutler is a tent),
  `game-icons/dice-twenty-faces-twenty.svg` (a d20 — tabletop-RPG register).
- **Pre-art generic set still loaded:** `icons/sword.png`, `heart.png`, `diamond.png`,
  `fire.png` are flat white silhouettes wired into `GameTheme` and `Rest`/`MainMenu`.

### A naming thread worth pulling separately
A cluster of relics still wear **Slay the Spire's names**: `snecko_eye`, `sozu`, `du_vu_doll`,
`mummified_hand`, `happy_flower`, `ice_cream`, `fusion_hammer`, `velvet_choker`, `toolbox`,
`pandoras_box`, `philosophers_stone`, `runic_pyramid`, `coffee_dripper`, `marathoners_sash`,
`olympians_mark`. Several of the "wrong subject" R1s are downstream of this — the artist drew
the *name*, and the name was never the game's. Renaming is cheaper than redrawing and is a
copy job, not an art job. Not in scope here; flagged.

---

## 4. D — delete (117 rows in-table, 1,711 files with the dead trees)

Nothing here is referenced by `scripts/` or `scenes/`. **Not deleted — this needs the owner's
say-so.** The in-table 117 are `assets/frames/` (29), the redundant relic SVGs (47), the dead
`assets/ui/` kit (14), `assets/icons/downloaded/` (15), 5 unused root icons, the 6 `.jpg`
twins, and `hud_gold_painted.png`.

---

## 5. How to actually replace them — what the research says

**Midjourney remains the right tool for the card art, and `--sref` is the fix for the whole
cyan problem.** `--sref` pins palette, light and finish — not subject — with strength set by
`--sw` (0–1000, default 100). Two or three references held together are more stable than one,
because a pair averages toward a house look instead of one image's quirks. That is exactly the
failure mode here: 103 assets drifted cool because each was generated alone.
`--oref` (Omni Reference) is **V7-only and did not carry into V8.1**, so a workflow built on it
must stay on V7; V8's `--cref` is the character-consistency path. Practical consequence: one
`--sref` code + `--no cyan, teal, neon, saturated blue` locked across a batch is worth more
than any per-image prompt tuning, and it is what §3's 149 regrades should be run under.

**FLUX 2 Pro** is the credible alternative for painterly/cinematic output, and **Scenario**
trains a custom style model from your own reference art and batch-generates on it — the
strongest option if the goal is to make the *existing* good assets the style anchor rather
than adopting a new look.

**For the icon families, game-icons.net is still the right source** — 4,180 CC BY 3.0 SVGs
drawn as solid silhouettes on a square tile, specifically designed to stay readable small,
which is what the 18px keyword rail needs. The project already uses it and **already credits
it correctly**. Only 17 of the 4,180 are vendored, so the fixes in §2 (charge, overrun,
mustering, sniper, thorns, shop) are a download away, not a drawing job. For painted relic
icons there are CC0 hand-painted RPG icon packs on itch.io (Ravenmore's Fantasy Icon Pack,
the Ultimate Fantasy RPG pack, Shikashi's 607-icon set) — useful for the 25 missing relics if
you would rather not generate them.

**One craft note that applies to all of it:** players read shapes before details, and a strong
silhouette is what makes a subject recognisable at small size; limited palettes exist for
readability, not mood. That is the argument for both fixes at once — the warm-sepia lock and
the silhouette-first icon set are the same decision.

---

## 6. Suggested order

1. **The 25 missing relic icons** — absence beats quality; prompts now written in
   [`MIDJOURNEY_BATCH4_MISSING_ART_20260908.md`](MIDJOURNEY_BATCH4_MISSING_ART_20260908.md).
   Add a probe like `_probe_card_art`.
2. **`hero_silhouette_kindler.png`** — one missing file on a five-across screen.
3. **The 39 R1s**, cheapest first: the 3 duplicates and 3 baked-in borders are near-free, and
   **33 of the 39 already have a prompt written** in the existing MJ docs.
4. **Pick the portrait house look** (§8), then bring the minority family across.
5. **One `--sref` grade pass** over the 149 R2s.
6. `cost_runestone.png` (event text only) + delete `atk_sword.png` and the two dead
   `tex_stat_*` loads.
7. **Delete the dead trees** (~288 MB) — needs your go-ahead.

---

## 7. What this pass got wrong, recorded so the next one doesn't

Six "wrong subject" calls made from contact sheets did not survive full-resolution re-check:

| file | thumbnail read | full-res truth |
|---|---|---|
| `creatures/lancer.png` | "a tree on a hillside" | a mounted lancer at the couch — **strong, keep** |
| `creatures/stone_sentinel.png` | "a rock formation" | a rock colossus IS there; the defect is pastel lavender |
| `creatures/doppelganger.png` | "a cave and two eyes" | a pale twin with lit eyes; the defect is cyan |
| `creatures/hatchling_brood.png` | "a pink blob" | egg + brood are there, but muddy |
| `creatures/crow_witch.png` | "no creature" | witch + crows are legible; the defect is 75% cyan |
| `relics/glowing_hand.png` | "a magenta cloud" | a raised fist IS there; the defect is the cast |
| `spells/hoarfrost.png` | "a blue golem, not frost" | a frost-caked soldier — the concept **earns** the cool cast |

**The rule: a thumbnail is sufficient evidence for palette and register, and insufficient
evidence for subject.** Dark, low-contrast, on-style art is exactly what a 250px cell
flattens — which means the contact-sheet method is biased *against* the moodiest work in the
set, the work most likely to be right. Always re-check a subject claim at full size.

---

## 8. The one thing that needs the owner, not an agent

**Which portrait family is the house look — flat ink-comic, or fine oil?** Eleven files are
oil, twelve are ink, and they meet on the muster screen. Every other item in this document is
a task; this one is a taste call, and picking it wrong wastes whichever family gets redrawn.
The 2026-07-22 audit asked the same question and it is still open — which is why it is called
out here rather than assumed.
