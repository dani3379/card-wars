# Faction-mapping worksheet — Successor Wars Phase 0 input
**Generated 2026-06-10** from the live `EncounterDB.ENCOUNTERS` (not from docs). This is build-order step 1 (`CONQUEST_REDESIGN.md` §15.3.1): every existing encounter tagged to a faction, plus the coverage matrix and gap list. Phase 0 consumes the **Faction** column verbatim as the new `"faction"` field.

**Corrected count:** the live dict holds **40** encounters — A1 **13** / A2 **13** / A3 **14** (24 combat / 8 elite / 8 boss). The roadmap's "41 (A3 15)" overcounts by one; fix when next touching §1.

Faction ids: `grasswake` (storm/overrun) · `last_wall` (stone/formation) · `owed` (rot/tithe) · `lanternhall` (frost-star/foresight) · `everflame` (fire/fuse).

## 1. The mapping

| id | act | type | name | faction | conf | evidence |
|---|---|---|---|---|---|---|
| goblin_scouts | 1 | combat | The First Cut | grasswake | high | all-Swift swarm, face chip — pure overrun |
| wolf_pack | 1 | combat | The Den Mother's Brood | grasswake | high | Swift pack, revenge passive |
| bandit_camp | 1 | combat | The Toll-Takers | grasswake | high | raiders, mana-steal, Swift + face damage |
| mushroom_grove | 1 | combat | The Spore-Cathedral | owed | med | Regenerate + on-death spore payoffs (death-as-deposit) |
| stone_sentinels | 1 | combat | The Tooth-Stones | last_wall | high | Armored/Thorns living stones |
| harpy_nest | 1 | combat | The Stooping Wings | grasswake | high | Swift/Ranged wind-flyers (storm soul) |
| boar_herd | 1 | combat | The Trampling Hour | grasswake | med | Swift/Piercing stampede |
| scarecrow_field | 1 | combat | The Field That Watches Back | owed | med | wither, deathly field, crow witch |
| powderkeg_run | 1 | combat | The Powderkeg Run | everflame | high | Doom Cinders — the Fuse, already live |
| orc_warband | 1 | elite | The Long Drumming | grasswake | high | Swift/Piercing warband |
| necromancer_tower | 1 | elite | Where the Dead Come Back | owed | high | skeletons, death-summons, double-on-death reactive |
| iron_warden | 1 | boss | The Iron Warden | last_wall | high | Armored siege + Trebuchet structure |
| dragon_lord | 1 | boss | The Wyrm-Father | everflame | med | drakes/wyrms — fire brood |
| cultist_enclave | 2 | combat | The Bleeding-Heart Cell | owed | high | on-death payoffs throughout + ON_PLAYER_SACRIFICE reactive |
| swamp_horror | 2 | combat | The Drowned Garden | owed | med | bog rot, Regenerate, drowned dead |
| mercenary_company | 2 | combat | The Coin-Sworn | last_wall | high | pike/armor line, Lieutenant + Standard Bearer buffs — proto-Formation |
| haunted_crypt | 2 | combat | The Crypt That Will Not Stay Shut | owed | high | undead + ON_PLAYER_SPELL reactive |
| fire_giants_forge | 2 | combat | The Forge That Eats | everflame | high | burn-all passive, fire giants |
| oathbroken_knights | 2 | combat | The Faithless Lances | last_wall | high | Armored knight wall |
| ash_hounds | 2 | combat | The Cinder-Hounds | everflame | high | cinder/ember pack + burn passive |
| carrion_choir | 2 | combat | The Carrion Choir | owed | med | carrion birds, on-death face chip |
| demon_vanguard | 2 | elite | The Threshold Choir | everflame | med | hellfire demons; anti-spell reactive |
| puppeteer | 2 | elite | The Puppeteer | lanternhall | med | keyword-copy marionettes — arcane mirror-craft |
| collector | 2 | boss | The Collector | lanternhall | low | hoarder-scholar soul; golems re-skin as animated exhibits (alt: last_wall) |
| hollow_king | 2 | boss | The Hollow King | owed | med | dead royalty — the dead still hold office |
| the_bellringer | 2 | boss | THE BELLRINGER | everflame | high | doom_bell passive — the Fuse boss |
| mirror_temple | 3 | combat | The Hall of Wrong Reflections | lanternhall | high | glass, reflections, keyword copies |
| elemental_nexus | 3 | combat | The Storm Made Flesh | grasswake | med | literally the storm; sprite rotation |
| executioners_block | 3 | combat | The Executioner's Block | last_wall | med | state apparatus of the dead empire (alt: owed) |
| dragons_lair | 3 | combat | Where the Old Drake Sleeps | everflame | high | lava drakes, hoard |
| pyre_cult | 3 | combat | The Pyre Cult | everflame | high | the fire-faith itself |
| withered_court | 3 | combat | The Withered Court | owed | high | dead court, wither, debuff dirges |
| killing_choir | 3 | combat | The Killing Choir | owed | low | funerary choir (alt: lanternhall — precision snipe passive) |
| archlich | 3 | elite | The Bone-Crowned | owed | high | phylactery, immortal passive |
| void_walker | 3 | elite | The One Who Walks Sideways | lanternhall | med | void/star horror — the Star half of frost-and-star |
| corrupted_shepherd | 3 | elite | The Shepherd Who Lost His Sheep | owed | high | maggot-lambs, rot |
| glass_menagerie | 3 | elite | The Glass Menagerie | lanternhall | high | glass snipers, reflections |
| the_devil | 3 | boss | THE DEVIL | everflame | high | hellfire cycle |
| the_crone | 3 | boss | THE CRONE | owed | high | Curse drip, cauldron, bones |
| the_black_tide | 3 | boss | THE BLACK TIDE | owed | med | the drowned dead as a flood |

## 2. Coverage matrix (combat / elite / boss per act)

| Faction | Act 1 | Act 2 | Act 3 | Total |
|---|---|---|---|---|
| grasswake | **5 / 1 / 0** | 0 / 0 / 0 | 1 / 0 / 0 | 7 |
| last_wall | 1 / 0 / 1 | 2 / 0 / 0 | 1 / 0 / 0 | 5 |
| owed | 2 / 1 / 0 | 4 / 0 / 1 | 3 / 2 / 2 | **15** |
| lanternhall | 0 / 0 / 0 | 0 / 1 / 1 | 1 / 2 / 0 | 5 |
| everflame | 1 / 0 / 1 | 2 / 1 / 1 | 2 / 0 / 1 | 8 |

Under conquest, "act N = one kingdom" needs roughly **4–6 combat holds + 1–2 elite strongholds** per faction per act-difficulty band. The 8 existing bosses **stop being act bosses** (rival lords take that slot — 5 new kits) and demote cleanly to **capital-stronghold / elite-plus** fights inside their faction's kingdom, which eases the elite gaps below.

## 3. Gap list (what must be authored or re-leveled)

Cheapest fill first: most encounters already ship **deck variants**, and an act-1 fight becomes an act-2 hold with stat/HP re-tuning + a variant deck — **re-level before authoring net-new**.

- **grasswake — ~5–6 needed.** Act 2: nothing exists (re-level wolf_pack / bandit_camp / harpy_nest variants, +1 new). Act 3: only elemental_nexus (re-level orc_warband, +1 new). No elite past act 1.
- **last_wall — ~5 needed.** Thin everywhere outside its act-2 pair; **zero elites in the game** (iron_warden demotes to its act-1 capital; author 1–2 stronghold elites; executioners_block re-levels well).
- **lanternhall — ~6–7 needed, front-load (worst-served, as specced).** Act 1: nothing. Act 2: one elite + a low-confidence boss. Needs ~3 act-1 holds, ~2 act-2, and its glass/void act-3 cluster re-dressed; also the faction genuinely short on creature bodies (~6–10 new, per spec §3-H).
- **everflame — ~3 needed.** Healthiest spread; add ~2 act-1 holds (powderkeg_run is alone) + 1 act-3 elite.
- **owed — 0–1 needed.** Deepest bench; at most one act-1 top-up. **Donor faction**: where another faction needs a body, raid Owed's surplus before writing new (e.g. killing_choir → lanternhall re-dress).

Net-new estimate after re-leveling: **~8–12 encounters** (vs. the spec's 13–17 guess) + the **5 rival-lord boss kits + 5 amalgam finales**, which are new regardless.

## 4. Next step
Phase 0 (`CONQUEST_REDESIGN.md` §9): add `"faction"` to each entry per the table above, extend `get_ids_for(act, type, faction := "")`, then Phase 1 rival selection. Low-confidence tags (collector, killing_choir, executioners_block) are re-taggable in one line later — don't block on them.
