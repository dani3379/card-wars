# Relic Pool Structural Audit — 2026-07-16 (every live relic)

**What this is.** A per-relic structural audit of the live pool (all non-retired entries in
`scripts/data/RelicDB.gd`) against the bars established this week: the four permanence jobs
(in-fight engine / run memory / rule-bender / map-economy), visible moment + changed decision,
strictly positive + never-zero (boss tier exempt), the washed-draw rule (off-turn draw is dead
under refill-to-5), and the attrition rule (payoffs keyed to creature survival are suspect —
creatures die in 1–2 turns). Companion docs: RELIC_SLATE_PITCH_20260716.md (new designs),
CARD_POOL_REVIEW_20260714.md (protocol).

---

## Headline findings (pool-level)

1. **THE ENTIRE UTILITY TIER IS UNREACHABLE — 8 fully-implemented relics can never drop.**
   Every roll site calls `roll_relic_reward("combat")` or `("boss")` (verified: Reward.gd:45,
   Shop.gd:103, Treasure.gd:78, Event.gd ×4, MainMenu.gd war chest); nothing rolls "utility"
   and no event grants the ids by name. Merchant's License, Collector's Tome, Blacksmith's
   Hammer, Sutler's Marker, Whetstone, Olympian's Mark, Centaur Heart, Stardust Vial all have
   LIVE wired effects (Shop discount, Recruit picks, Rest reforge, elite-win upgrade…) that no
   player has ever seen. Fix options: (a) retag them "combat" with rarity weights, (b) give the
   Shop a dedicated tool shelf (thematic — the sutler sells kit), (c) make treasure roll mixed.
2. **A washed/mistimed trigger class** — same defect family the card review purged: payoffs that
   fire during the clash (off-turn) in a game whose hand refills to 5. Draws: swift_boots'
   rider, doom_herald, verse_of_you. "+X Command THIS TURN" granted during the clash:
   battle_scars, stalwarts_anvil (the Command should bank into the next turn to mean anything).
3. **Ungated zero-relics** — archetype payoffs offered to decks that can't use them (violates
   no-dead-rewards): briar_amulet (no Thorns), bone_ring (no on-death dmg), butchers_cleaver /
   bone_pile / reapers_scythe (no sacrifice sources), the_family (no token makers),
   bulwark_engine (no Armored), hourglass_of_ruin (no Doom). All fixable with a PotionDB
   `_roll_allowed`-style offer gate — the machinery precedent exists.
4. **The positional-+1 cluster is oversubscribed**: vanguard_banner, banner_of_unity,
   linked_banner, bridge_watcher, plus a bone_hourglass mode all say "small stats for standing
   in the right shape." The 07-08 pass already merged three INTO this cluster; the survivors
   still overlap. linked_banner is the merge candidate (into banner_of_unity).
5. **Two relics teach anti-play**: cavalry_sigil pays you to leave lanes EMPTY in a lane-combat
   game where open lanes eat face damage (and the Grasswake faction explicitly punishes empty
   lanes) — a paid trap. glass_cannon carries a negative rider (−1 HP flips attrition
   breakpoints) in the combat pool; downside trades belong at boss tier only.
6. **Zero tribe coverage** (known — the slate pitch fills it).

**Overall: ~60% of the pool passes clean.** The defects cluster into the five classes above
rather than universal rot — the 07-03/07-07/07-08 passes worked.

---

## Per-relic verdicts

### Starting tier (9)
| id | Effect | Verdict | Why |
|---|---|---|---|
| iron_buckler | 1st creature/fight gains Last Stand | KEEP | Moment (the save), value-per-life, mild sequencing decision |
| ember_crown | 1st spell/turn costs 0 | KEEP | Best in tier — fires every turn, real sequencing |
| couriers_bag | +1 draw turn 1 | RESHAPE | One quiet card once per fight; a signature should define a run |
| coin_purse | +10g/fight | RESHAPE | Gold trickle as a hero identity; no moment, no decision |
| worn_spellbook | +1 spell dmg | RESHAPE→slate | Duplicates design pitched (mid-turn draw survives wash) |
| scouts_emblem | Musters show 4 | KEEP | Map-layer job, real draft breadth |
| soul_lantern | 1st friendly death/round → +1 Command next turn | KEEP | Fires constantly (attrition), pays the trades, correct "next turn" timing |
| veterans_medal | 1-costs +1/+1 | KEEP | Accepted flat signpost at starting tier (prior ruling) |
| ember_censer | Doom detonations +1 | KEEP | Rides Doom's existing bang; tribe-defining for Kindler |

### Combat tier — clean keeps (44)
vanguards_cry (aimed opening moment) · banner_of_unity (placement puzzle) · echo_staff (flagship
rare engine) · piercing_crown (changes lethal math, overflow visible) · resonance_crystal
(engineer which keyword dies first — excellent) · mimic_ring (placement) · phoenix_heart
(rule-bender) · recruiters_horn (map decision) · rear_guard_charm (fires ON death, column play)
· phantom_veil (changes trades) · ice_cream/Miser's Coffer (flagship rule-bender) · deep_satchel
(rule-bender, felt every turn) · mummified_hand (sequencing) · sigil_of_hunger (attrition-native
sequencing) · pact_of_embers (makes expensive cards MORE valuable — helps the top-end problem) ·
toolbox (flagship rare, choice every fight) · bottled_talisman (consistency + acquisition
decision) · catapult_crew (rare engine, deployment) · flanking_banner (real placement puzzle,
not a trap — 3-of-4 is near-full) · war_drum (establishes state) · mana_drunkard/Forced March
(spend-exactly decision) · soul_ledger (run memory ✓) · inkpot_of_many (mid-turn copy, not
washed) · pen_nib (hand-ordering decision — leftmost is manipulable) · stygian_soul (sustain
workhorse) · pyre_stoker (play-count decision) · imp_generator (relic-as-engine, the compass
job) · blueprint (sequencing) · totem_pole (act pick) · death_card (flagship rule-bender) ·
warlords_standard (compounds across rounds — buffs whoever stands NOW, attrition-honest) ·
runebound_idol (engine on your own casts) · letters_patent (run memory flagship) ·
deserters_toll (discard decision flagship) · dregs (potion moment) · poisoned_rations
(reinforcement system payoff) · sellswords_retainer (hold-gold decision) · vultures_feast
(post-fight sustain; distinct from stygian_soul: friendly deaths vs enemy kills) · lantern
(quiet tempo workhorse — accepted) · vanguard_banner (accepted flat workhorse, prior ruling) ·
bridge_watcher (borderline: placement is real, Thorns procs are the moment) · bone_hourglass
(borderline rare: the pick is the decision, effects are quiet) · spell_tome (draft-shaping is
real — add a visible fire via the `_relic_fired` funnel on each discounted cast) ·
bloodstone_relic (KEEP, VERIFY the +1 ATK applies to the clash resolving when it triggers).

### Combat tier — keep + add offer gate (6)
briar_amulet/Man-Trap (needs Thorns) · bone_ring (needs on-death damage) · butchers_cleaver +
bone_pile + reapers_scythe (need sacrifice sources) · the_family (needs token makers) ·
bulwark_engine (needs Armored). Gate = PotionDB `_roll_allowed` precedent.

### Combat tier — reshape (8)
| id | Defect |
|---|---|
| swift_boots | Half invisible tax, half washed (the draw fires in the Swift pre-phase, refill eats it); Swift audit pending anyway |
| battle_scars | "+2 Command this turn" triggers on face damage taken in the CLASH — off-turn; make it bank into next turn |
| thiefs_gloves | Perfect-fight trigger too rare under simultaneous chip damage; grade continuously (≤N face damage) |
| bag_of_marbles | The named anti-pattern: a permanent that's a weak potion sip; no decision |
| linked_banner | 5th member of the positional-+1 cluster; merge into banner_of_unity |
| doom_herald | Detonation draw is washed (clash-time); pay in damage or next-turn Command instead |
| du_vu_doll | RESHAPED in slate (curse ammunition + gate) |
| wormwood | Permanent-ATK-on-damage mostly dies with the body (damaged ≈ about to die); re-key toward walls/Bastion or accept as rare lottery — FLAG |

### Combat tier — cut (5)
| id | Why |
|---|---|
| cavalry_sigil | Pays for EMPTY lanes in a lane game that punishes empty lanes (Overrun exists) — a paid trap teaching anti-play. Worst structural offender |
| glass_cannon | Negative rider in the combat pool; −1 HP flips attrition breakpoints; boss tier or bin |
| hexagonal_shield/Pavise | Zero in every fight without an enemy Sniper; encounter-lottery bought blind |
| last_breath | 1-base-HP constituency near zero; invisible |
| mana_pearl | 0-cost-spell constituency near zero; invisible |
| iron_legion | 60%-creatures threshold ≈ always true → invisible +1 HP behind a fake condition |

(That's 6 rows — iron_legion included.)

### Class-restricted (4)
raiders_oath KEEP (tempo, fires on your own play) · stalwarts_anvil RESHAPE-TIMING (first
friendly damaged = clash-time; "+1 Command this turn" lands off-turn — bank it) · acolytes_tome
KEEP (draw on your OWN cast — mid-turn, not washed; 32/75 spells exhaust) · pyromancers_scar
KEEP (which-spell-first is a real fight-opening decision).

### Utility tier (8) — ALL UNREACHABLE (headline #1); design verdicts once a drop path exists
merchants_license KEEP (routing toward shops) · collectors_tome KEEP · blacksmiths_hammer KEEP
(verified live: RunState:725/851 generic +1 on forge deltas) · scavengers_pouch/Sutler's Marker
KEEP (enables economic thinning) · whetstone KEEP · olympians_mark KEEP (routing: hunt Generals)
· stardust_vial KEEP · centaur_heart RESHAPE (one-shot that NEVER fires if acquired in act 2+ —
per-act payoff or act-1-only offer).

### Boss tier (18 live)
The +1-Command-with-downside template ×8 (cursed_key, hairshirt/coffee_dripper,
cracked_anvil/fusion_hammer, tarnished_crown/busted_crown, temperance_vow/sozu,
philosophers_stone, penitent's_collar/velvet_choker, mark_of_pain): **KEEP as a category** —
boss tier is the sanctioned downside home, and `roll_boss_relics` already guarantees ≥1
non-template warper per offer. philosophers_stone: note the stack with Ascension A4 (+1 ATK
Generals) — opt-in, acceptable.
Warpers: pandoras_box KEEP · snecko_eye KEEP (VERIFY "draw 6" wording vs refill-to-5 — should
read "refill to 6, costs randomized") · calling_bell KEEP · lichs_bargain KEEP · lean_mean KEEP
(best boss design — every subsequent draft decision echoes it) · glowing_hand KEEP ·
marathoners_sash KEEP · hourglass_of_ruin KEEP+GATE (Doom deck) · gravewardens_pact KEEP ·
**steady_banner RESHAPE** (+2 ATK per round survived on 1–2-round lifespans = washed upside
carrying a real downside; re-key to fight length or the Bastion tribe).

### Event tier (4) — souvenir exemption applies (never rolled, story-bound)
coin_landed KEEP (volume trickle, but it IS the coin story; watch economy) · warm_knucklebone
KEEP (lottery, but the dice are the story) · sin_eaters_crust KEEP (thinning incentive) ·
**verse_of_you RESHAPE** (death-draw is washed — keep the name, change the payoff; note
soul_lantern already owns Command-on-death).

### Also verify
drovers_whip — how often does the player actually MOVE a creature? If moves only come from
Reposition + rare effects, it's near-zero; gate on a mover in deck or broaden the trigger.

---

## Tally
~55 clean keeps · 7 keep-with-gate · 13 reshapes (2 already designed in the slate) · 6 cuts ·
8 unreachable (fix the drop path, then 7 keep / 1 reshape) · 4 verifies (bloodstone timing,
snecko wording, drovers_whip frequency, wormwood attrition fit).
