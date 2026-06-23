# Event Art Audit — `assets/events/`

Audited 2026-06-22. Visually inspected all 33 in-scope event PNGs and cross-referenced each against its `EVENTS` entry in `scripts/scenes/Event.gd`.

**Loader behavior (verified):** `Event._load_event_image()` (Event.gd:536) tries `assets/events/<event_id>.png` FIRST, then falls back to the `"art"` field. So a bespoke `<id>.png` always wins; an `"art"` stand-in only renders when no bespoke file exists.

**Overall craft:** the pool is strong. The dominant style is a smooth painterly / inked-comic look (StS-adjacent). A **minority subset is rendered in PIXEL ART** (beekeeper_again, beekeeper_returns, drowned_bell, marked_one, mirror_twin) — these are individually good but clash stylistically with the painterly majority and with the PD-master card art. The single most serious defect is a baked-in garbled watermark on `dark_altar.png`.

---

## Duplicates / stand-ins

| id | status | detail |
|---|---|---|
| `fork_in_the_long_road` | **EXACT DUPLICATE** | Byte-identical to `assets/backgrounds/event_forest.png` (both md5 `175256f4362b0c26d3231256a03ab4fe`). It is a reused area background, not bespoke event art. **Needs a bespoke image** (a literal two-road fork — one smelling of woodsmoke, one of iron). Low urgency: the forest-fork reads OK for the premise, but it's the only event using a recycled background. |
| `the_crossing` | stand-in now SUPERSEDED | Has `"art": "tollkeeper_bridge"` (Event.gd:2300) but a **bespoke `the_crossing.png` now exists** (md5 `87f9e1a1…`, distinct) and overrides it. The bespoke art is good (3 men on a black-timber bridge over a brown river). The `"art"` field is now dead code — no art action needed. |
| `the_chrysalis` | stand-in now SUPERSEDED | Has `"art": "hollow_lantern"` (Event.gd:3484) but a **bespoke `the_chrysalis.png` now exists** (md5 `c0bf7eae…`, distinct) and overrides it. Bespoke art is a perfect fit (cocoons on a fence). The `"art"` field is now dead code — no art action needed. |
| beekeeper trilogy | 3 DISTINCT images | `beekeeper` / `beekeeper_again` / `beekeeper_returns` are three different files (md5s `254edda8` / `3e43dbec` / `8f7567e4`). NOT duplicates. Caveat: `beekeeper` is painterly, the other two are pixel-art — the trilogy is not stylistically consistent within itself. |

**Files in scope that have NO bespoke PNG (only `.import` stubs) — MISSING ART:**
- `blacksmith_offer` — `.import` stub only, no `.png`. (No `blacksmith_offer` entry exists in the current `EVENTS` dict either — likely cut/legacy.)
- `burning_cradle` — `.import` stub only, no `.png`. (No entry in `EVENTS`.)
- `mysterious_shrine` — `.import` stub only, no `.png`. (No entry in `EVENTS`.)
- These three import stubs point at images that don't exist; the events themselves aren't wired up, so nothing renders them today. Either author art + an event, or delete the orphan `.import` stubs.

**Orphaned art (PNG exists, no event uses it):**
- `gambler.png` — a fine painterly dice/cards/coins-on-a-table image, but there is **no `gambler` event** in `EVENTS`. The only `gambler` matches in code are an unrelated dialogue string and the `gamblers_coin` relic. The bone-pit/coin-on-edge gambling events use their own art. This image is unused — repurpose it (it would suit a gambling event) or remove it.

---

## REPLACE — low quality / off-tone (worst first)

| id | what's wrong | suggested better direction |
|---|---|---|
| `dark_altar` | **Worst offender.** A garbled fake title banner reading **"KIRY THE STIRE"** (a mangled "Slay the Spire") is baked into the top-left corner — an AI text artifact AND an off-brand reference shipping in the build. Also the image is a glowing **purple sword in an anvil/stone**, which does not match the premise at all. | Premise = "a slab of black stone… every groove running downhill to one drain," a hungry sacrificial altar. Render exactly that: a sweating black blood-altar with a central drain, grooves, dark/red lighting. No text, no sword. This one should be regenerated regardless of fit because of the watermark. |
| `coin_on_edge` | Off-premise + reads generic. Premise is "a silver coin spins on its edge in the path." The image is a **top-down brown dirt pit/arena with a wooden sign** — no coin, no spinning, no path. Looks like a generic excavation/pit and could be confused with `the_bone_pit`. | Show the actual hook: a single silver coin spinning upright on its edge in a worn road groove, motion blur / glint, a small "CALL IT" sign. Keep the warm palette. |
| `butcher` | Lowest apparent resolution in the set — renders notably smaller/softer than its neighbors, with muddy detail. Tone is right (a meat-hung cavern with a stone block) but craft is below the pool average and there's no butcher figure. | Re-render larger/sharper: a burly butcher at a chopping block, cleaver, meat hooks, warm gore-lit cavern. Match the resolution of `fattened_sin_eater`. |

---

## POOR FIT — art doesn't match the event

| id | event premise | mismatch |
|---|---|---|
| `strangers_hand` ("The Wet Cards") | "A stranger deals **wet cards** face-up onto a **flat stone**, and looks up only once." | Image is a grey **hand bursting out from behind a red door** amid skulls/candles. No cards, no stone, no dealer. Atmospheric and well-painted, but it illustrates a different event entirely. Re-key it to a card-dealing-on-a-stone scene, or reassign this image to a "grasping hand / door" event. |
| `two_headed_calf` | "A **calf with two heads stands in the road**. One head asleep, the other watches you." | Image is a dead/sleeping quadruped **carcass laid out inside a candle ring under a red sigil** — reads as a ritual sacrifice, and you cannot make out two heads or a living, standing calf. The "watching, alive, in the road" beat is lost. Re-render a living two-headed calf standing on a road. |
| `woodcutter` | "He has chopped the **same tree** for thirty years… 'Swing for me.'" Interaction is a man, an axe, a stubborn tree. | Image is a beautiful **giant glowing tree** with a tiny woodpile/bench — **no woodcutter, no axe, no chopping**. The huge-tree idea half-lands ("the tree hasn't gotten smaller"), but the human + the action are absent, so the scene doesn't read as the event. Add the woodcutter and axe at the trunk. |
| `hollow_lantern` | "A **paper lantern** hangs in midair… a **moth** the size of your palm thumps against the paper." | Image is a **metal horned-skull lantern** glowing in a blue cavern. Beautiful and high-craft, but it's the wrong object (skull, not paper) and there's no moth. Borderline — it still reads as "ominous floating lantern," so it's serviceable, but a paper-lantern-with-moth would match the writing. (Lower priority than the three above.) |

---

## OK

beekeeper, beekeeper_again, beekeeper_returns, blood_fountain, drowned_bell, fattened_sin_eater, glass_familiar, gravesong_choir, hermit, marked_one, mirror_twin, old_forge, pawnbrokers_window, rotting_carnival, sin_eater, the_answering_well, the_bone_pit, the_chrysalis, the_crossing, the_weeping_orchard, three_doors, thrice_blessed_spring, tollkeeper_bridge, tooth_witch

**Standouts (excellent fit + craft):** fattened_sin_eater, rotting_carnival, glass_familiar, the_bone_pit, three_doors, the_weeping_orchard, blood_fountain, pawnbrokers_window, tollkeeper_bridge, the_answering_well, the_chrysalis, the_crossing.

**OK-but-noted:**
- The 5 pixel-art entries (beekeeper_again, beekeeper_returns, drowned_bell, marked_one, mirror_twin) are good in isolation but stylistically clash with the painterly majority and the card art. If a unified look matters for 1.0, consider re-rendering these in the painterly style. All 5 are thematically accurate, so this is polish, not a defect.
- `tooth_witch` fits loosely (skull/bone collector vibe rather than a clear tooth-puller in a chair) but is acceptable.
- `the_answering_well` has faint garbled lettering on the arch — subtle/illegible, not worth a re-render.
