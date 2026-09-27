# Art worklist — generated, do not hand-edit

Regenerate with `python tools/art_lint.py --markdown docs/ART_WORKLIST.md`.

Ranked by the measurements in `tools/art_lint.py` (CLASS C31). Read its module docstring first: this is a WORKLIST, not a verdict, and it cannot tell you a drawing is ugly — only that it does not match the set it belongs to.

## 1. Shared / duplicate art

Two or more live entries rendering the same bitmap. The cheapest fix is often to RENAME the card to fit the art it already has, rather than commission more.

- `assets/spells/mass_grave.png`  ==  `assets/spells/plague_bell.png`
- `assets/icons/relics/recruiters_horn.png`  ==  `assets/icons/relics/war_horn.png`

## 2. Cyan / teal intrusion

103 of 448 measured images carry a saturated cyan/teal band, against a warm sepia+ember set. This is the defect the 2026-07-22 audit called the single pervasive one, and `docs/MIDJOURNEY_ART_OVERHAUL_20260722.md` already holds the style tails that exclude it (`--no cyan, teal, neon, saturated blue`). Percentages are the share of drawn pixels in the band.

| % cyan | asset |
|---:|---|
| 95% | `assets/spells/ambush.png` |
| 87% | `assets/events/hollow_lantern.png` |
| 86% | `assets/spells/banish.png` |
| 85% | `assets/creatures/the_black_tide.png` |
| 82% | `assets/creatures/vengeful_spirit.png` |
| 80% | `assets/icons/relics/mana_tide.png` |
| 77% | `assets/spells/lightning.png` |
| 77% | `assets/spells/recycle.png` |
| 75% | `assets/creatures/crow_witch.png` |
| 70% | `assets/spells/fuel_the_pyre.png` |
| 67% | `assets/icons/relics/mana_drunkard.png` |
| 67% | `assets/events/sin_eater.png` |
| 64% | `assets/spells/time_snare.png` |
| 64% | `assets/creatures/glass_knight.png` |
| 61% | `assets/icons/relics/lantern.png` |
| 61% | `assets/events/gravesong_choir.png` |
| 60% | `assets/creatures/assassin.png` |
| 60% | `assets/creatures/chorus_of_echoes.png` |
| 56% | `assets/spells/hex.png` |
| 56% | `assets/spells/lost_tome.png` |
| 56% | `assets/events/hermit.png` |
| 55% | `assets/icons/relics/swift_boots.png` |
| 54% | `assets/spells/shield_wall.png` |
| 54% | `assets/backgrounds/rest_campfire_act2.png` |
| 54% | `assets/events/blood_fountain.png` |
| 53% | `assets/creatures/mana_sprite.png` |
| 53% | `assets/events/the_answering_well.png` |
| 51% | `assets/icons/relics/mana_pearl.png` |
| 51% | `assets/spells/hoarfrost.png` |
| 50% | `assets/events/the_weeping_orchard.png` |
| 49% | `assets/events/thrice_blessed_spring.png` |
| 48% | `assets/creatures/doppelganger.png` |
| 48% | `assets/events/woodcutter.png` |
| 47% | `assets/icons/relics/mimic_ring.png` |
| 46% | `assets/backgrounds/combat_arena_act2.png` |
| 45% | `assets/icons/relics/last_breath.png` |
| 43% | `assets/icons/relics/echo_staff.png` |
| 43% | `assets/icons/relics/phantom_veil.png` |
| 42% | `assets/backgrounds/rest_campfire_act3.png` |
| 42% | `assets/creatures/copycat.png` |
| 40% | `assets/portraits/hero_portrait_acolyte.png` |
| 39% | `assets/portraits/boss_hollow_king.png` |
| 37% | `assets/events/tollkeeper_bridge.png` |
| 37% | `assets/creatures/necromancer.png` |
| 36% | `assets/spells/soul_swap.png` |
| 36% | `assets/portraits/boss_collector.png` |
| 34% | `assets/icons/relics/mark_of_pain.png` |
| 34% | `assets/creatures/cinder_whelp.png` |
| 33% | `assets/spells/mark_of_ash.png` |
| 32% | `assets/spells/grave_pact.png` |
| 32% | `assets/spells/slash.png` |
| 31% | `assets/spells/frost_bolt.png` |
| 31% | `assets/spells/grave_debt.png` |
| 30% | `assets/spells/ricochet.png` |
| 30% | `assets/creatures/stone_sentinel.png` |
| 30% | `assets/spells/war_debt.png` |
| 29% | `assets/icons/relics/thiefs_gloves.png` |
| 28% | `assets/backgrounds/event_forest.png` |
| 27% | `assets/creatures/warden_of_graves.png` |
| 26% | `assets/spells/reposition.png` |
| 26% | `assets/portraits/boss_dragon_lord.png` |
| 26% | `assets/backgrounds/rest_campfire.png` |
| 25% | `assets/creatures/harpy.png` |
| 25% | `assets/spells/second_wind.png` |
| 24% | `assets/creatures/whisper_king.png` |
| 24% | `assets/spells/reanimate.png` |
| 21% | `assets/events/tooth_witch.png` |
| 21% | `assets/creatures/e_wind_harpy.png` |
| 18% | `assets/icons/relics/glowing_hand.png` |
| 18% | `assets/events/dark_altar.png` |
| 18% | `assets/events/the_crossing.png` |
| 18% | `assets/spells/craven.png` |
| 17% | `assets/creatures/leyline_conduit.png` |
| 16% | `assets/creatures/husk.png` |
| 15% | `assets/spells/mending_light.png` |
| 15% | `assets/events/two_headed_calf.png` |
| 15% | `assets/creatures/wolf_c.png` |
| 15% | `assets/icons/relics/acolytes_tome.png` |
| 14% | `assets/icons/potions/chain_flask.png` |
| 14% | `assets/creatures/cauldron.png` |
| 13% | `assets/creatures/mirror_knight.png` |
| 13% | `assets/events/the_chrysalis.png` |
| 13% | `assets/icons/potions/aegis_brew.png` |
| 13% | `assets/creatures/archmage.png` |
| 13% | `assets/spells/venom_tip.png` |
| 12% | `assets/icons/relics/raiders_oath.png` |
| 12% | `assets/spells/unholy_bargain.png` |
| 12% | `assets/spells/curse.png` |
| 12% | `assets/creatures/gravedigger.png` |
| 11% | `assets/creatures/risen_lich.png` |
| 11% | `assets/icons/potions/mana_surge.png` |
| 10% | `assets/creatures/ember_mystic.png` |
| 10% | `assets/backgrounds/collection_library.png` |
| 9% | `assets/creatures/vampire_lord.png` |
| 9% | `assets/portraits/hero_portrait_raider.png` |
| 9% | `assets/creatures/e_elder_dragon.png` |
| 9% | `assets/icons/relics/fusion_hammer.png` |
| 8% | `assets/events/glass_familiar.png` |
| 7% | `assets/spells/cataclysm.png` |
| 7% | `assets/creatures/e_golem.png` |
| 7% | `assets/events/pawnbrokers_window.png` |
| 6% | `assets/events/three_doors.png` |
| 6% | `assets/events/drowned_bell.png` |

## 3. Tonal poverty

Too few distinct tones inside the shape to read as a painted object. **Check the call site before acting** — a 12px marker cannot have 64 tones and should not try; two of this oracle's top hits were exactly that mistake and are now waived.

| tones | asset |
|---:|---|
| 56 | `tools/screenshot/painters/TallySlate.png` |
| 57 | `tools/screenshot/painters/ArmoredEdge.png` |

