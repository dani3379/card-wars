# THE ART PLAN — final (2026-09-08, rev 3)

Rev 3 after three independent review passes, every load-bearing claim re-verified against the
repo. **Rev 1 and rev 2 were both mis-scoped, in opposite directions.** The correction log is §1
and it is the most useful part of this document.

Evidence: [`ART_REPLACEMENT_SWEEP_20260908.md`](ART_REPLACEMENT_SWEEP_20260908.md) ·
[`CARD_ART_LIFE_PASS_20260908.md`](CARD_ART_LIFE_PASS_20260908.md) ·
[`CARD_ART_FAMILIES_20260908.md`](CARD_ART_FAMILIES_20260908.md) ·
[`ART_DIRECTION_METHOD_20260908.md`](ART_DIRECTION_METHOD_20260908.md) ·
[`MIDJOURNEY_BATCH4_MISSING_ART_20260908.md`](MIDJOURNEY_BATCH4_MISSING_ART_20260908.md)

---

## 0. THE ROOT CAUSE — found in rev 3, and it explains everything

Every prompt doc in this repo says **`--sref YOURCODE`**. It appears **26 times and has never once
been replaced with a real code.** The single mechanism the whole cohesion strategy depends on has
never been engaged.

And there is a second, undetected drift axis. The prompt corpus is split across model versions:

| | prompts |
|---|---:|
| `--v 6.1` (`MIDJOURNEY_PROMPTS`, `ICON_REPLACEMENTS`) | 134 |
| `--v 8.1` (everything from 2026-07-22 on) | 126 |
| **no version pinned at all** (`ART_PROMPTS`, `CARD_PROMPTS`, `EVENT_PROMPTS`) | 69 |

**The same `--sref` code renders differently across model versions**, so even a pinned code would
have drifted. This is why 103 assets are off-palette. It is not a taste failure or a prompt-writing
failure — **it is an unset variable**, and it is cheap to fix.

---

## 1. Correction log

**Rev 1 errors** (kept because the pattern matters): "25 relics have no icon" — false, `RelicDB.gd:785
ICON_FALLBACKS` resolves all 154, **zero render blank**; "delete `kindling_alt`" — it is the
deliberate no-art placeholder with a standing waiver at `art_lint.py:201`; the "3 duplicates" are
live distinct cards needing new art at full price; the Doom slice put 5 `dead`-tribe cards in a
register the same document calls *melancholy-comic*; four of my "nine standing soldiers"
(`sentinel`, `militia`, `mirror_knight`, `hall_watcher`) **are not cards at all**, and
`thornguard` is a beast.

**Rev 2 errors, found in rev 3:**

**① My art-sharing numbers were wrong — I resolved alias-first, the loader resolves file-first.**
`CardArtAliases.try_load_creature_art:798-828` tries `assets/creatures/<id>.png` **first** and only
falls back to `ALIASES`. Correct figures:

| | rev 2 said | actually |
|---|---:|---:|
| distinct art files | 146 | **173** |
| cards sharing art | 178 | **141** |
| files serving >1 card | 64 | **54** |
| **files spanning >1 tribe** | 15 | **11** |

My headline example was false: **`torchbearer.png` is not cross-tribe.** The cause is **31 stale
aliases** — cards that now own their own painting but still carry a dead `ALIASES` entry. Deleting
those 31 lines is a five-minute edit that makes the data honest.

**② The colour grade is 21 files, not 103 — a 5× overstatement.** Banding the 103 cyan findings
against my own hand verdicts:

| band | n | I marked KEEP |
|---|---:|---:|
| **A >50%** | 30 | **0 (0%)** |
| B 25–50% | 33 | 10 (30%) |
| C 12–25% | 23 | 9 (39%) |
| **D <12%** | 17 | **9 (53%)** |

Above 50% the metric and my eye agree **perfectly**. Below 12% the metric is **worse than a coin
flip**. `CYAN_HIT = 0.055` (`art_lint.py:88`) is a *worklist* threshold and was never a *fix*
threshold. Nine of band A are already verdict R1 (regenerate, don't grade). **Grade scope = 21.**

**③ The regeneration bill is ~150 assets, not "dozens" — an understatement in the other
direction.** 37 live R1 + 135 live R2, minus the 21 that grade away. At a rate derived from this
repo's own git history (art lands in bursts of 40–80; 39% keep rate; ~12–20 min per shipped
asset), that is **30–50 hours of focused work — 4–6 bursts, 2–4 months of calendar.** Say the real
number out loud: a 150-asset job planned as a 40-asset job is the one abandoned at 60.

**④ Cyan is only half the defect.** `art_lint` measures 150–210° only. The sweep's own R2 reasons
include **magenta/purple ×14 and acid-green ×11**. Key the fix on *distance from the sepia+ember
palette*, not on cyan — same code, wider band.

---

## 2. What I would actually do

### First, four hours that unblock everything

1. **Pin the anchor.** Generate ~6 images at the locked tail with **no** sref, pick the one whose
   light you want to live with, and record its code in a new `tools/golden/art_style.json` —
   `{sref, sw, model, ar, tail, no}` — with the six anchor images committed to `docs/art_anchor/`.
   **The sref code and the model version are ONE unit**; changing either starts a new set.
   *This is the highest-value hour in the entire plan and it produces no art.*
2. **Delete the 31 stale aliases.** Makes every count in every doc honest.
3. **Answer the sharing question for 11 files.** Not 64 — eleven. Four dissolve into a one-line
   alias edit; the rest are a real but small decision: split, or accept a neutral register.
4. **Wire `art_lint.py --baseline` into `run_safe_probes.ps1`.** It is in **neither runner** today.
   It is pure Python and seconds long. An unrun gate is not a gate.

### Then, in order

| # | job | size | why here |
|---|---|---|---|
| 1 | **The 21-file grade** | half a day | Deterministic, reversible, no generation. A visible palette win *before* committing to a 30-hour bill. |
| 2 | **HUD three + `mustering`/`exhaust`** | hours | `hud_gold` is a **dollar sign**, `hud_heart_painted` a **literal emoji**. And `mustering.svg` is `exhaust.svg` inverted at the 18px the rail draws them — **a gameplay legibility bug**, not an art issue. Highest screen-seconds per unit effort in the document. |
| 3 | **The 8 wrong-subject R1s** | 8 files | The only defect class that actively lies to the player about a rule. |
| 4 | **The 6 armaments** | 6 files | All six borrow *action* paintings (`tower_shield`→`shield_wall`, `forked_spear`→`cataclysm`…). An armament is a held object; these are the cheapest correct block in the queue. |
| 5 | **Warlock, one burst** | 15 cards | Blandest tribe, biggest tonal gain per card, and it proves the cute/terror thesis. |
| 6 | **Soldier, two bursts** | ~25 files | Largest block. De-helm; unlocks the death systems. |
| 7 | Remaining R1/R2 by tribe, one burst each | ~100 | |
| 8 | Deletions — **excluding `kindling_alt`** | 1,711 files | Your go-ahead. |

**Batch by register, never by worklist rank**, 25–40 per sitting. Below 15 you cannot see cohesion;
above 50 the back half gets waved through — your own 544-image day produced the drift this plan
exists to fix.

**Dropped:** the Doom slice as proof-of-thesis (it contradicts the register system), and
`_probe_relic_art` (it would gate an impossible condition).

---

## 3. The spell answer — 38% of the pool, previously unaddressed

> **A spell card is a picture of a person it is happening to, one beat after it started. The
> caster is never in the frame; the effect is never alone in it.**

Putting a body in every spell frame **restores all four body-based life levers** to 93 cards that
otherwise get none. And the caster prohibition is a rules point, not a taste one: this game has no
wizards — Command is a budget of *orders* and the player is a commander.

**Register:** decided per card by *which body*, readable from the card's own text — your side →
soldier; enemy → soldier in enemy dress (which starts building the missing enemy visual class);
the death spine → dead; unmaking/debt → warlock; taking/knowing → stray; ground and works →
bastion. **The spell block is the only place all six registers appear in one set** — a player meets
a tribe's tone on a spell before they own a card of it.

**Two aperture facts that only apply to spells:** they **never** reach the battlefield (verified —
every `compact_mode` writer builds creature data), so they are exempt from the board crop and the
0.55 scrim. **Spell art is the only art in this game that is safe at the bottom edge.** But 50 of
93 are targeted, and a targeted spell is held at **~329×428 for the whole targeting window** — so a
spell painting must survive both 203px *and* being stared at. That is the concrete reason "a
fireball with nobody in it" fails here.

**Brief masters at 1.60, not 1.50** — the hand aperture is 203×127 and `KEEP_ASPECT_COVERED` crops
~6% off a 3:2 master.

---

## 4. Build these four things

Nothing here is art; all of it is what keeps the art from drifting again.

- **`tools/golden/art_style.json`** — the anchor: sref + model + tail + the `--no` list. Its
  absence is the root cause in §0.
- **`tools/golden/art_keep.json`** — the **keep-list**. Any asset confirmed by eye at 203×127 is
  exempt from every linter worklist until deliberately removed. `lancer.png` is entry one, because
  a prior pass nearly deleted it for being *good*. This is what makes that unrepeatable.
- **`tools/art_compare.py`** — the comparison gate. Old vs new, side by side, at **the true 203×127
  hand crop**, plus the board crop with the scrim composited, a 2× detail view, a hue histogram,
  and one-directional auto-objections (`LOST CONTRAST`, `LOST TONAL RANGE`, `DARKENED`). It never
  says "ship it" — it raises objections and your eye decides. **Rule: nothing overwrites an
  incumbent without passing through it.**
- **`docs/ART_BRIEFS.md`** — one 5-field brief per card, with **the exact final prompt appended to
  the block that shipped it.** This is what makes a card re-generatable in eighteen months.

**Session ritual:** at the top of every art session, regenerate one already-shipped card from its
recorded prompt and diff it through `art_compare.py`. If the model has moved under you, you find
out in 90 seconds on a card you can throw away — not 30 assets into a batch.

**One technical note for the grade:** hue-rotate the cool band toward ochre **and restore luma
afterward**. Rec.709 luma of saturated cyan is ~0.79 vs ~0.57 for ochre at the same HSV value, so a
naive rotation *darkens* every region it touches (measured −6.3% on `ambush.png`). That is how a
grade turns a glowing effect into a dim brown smear. Use DESAT instead of ROTATE where the cool is
semantically required (`frost_bolt`, `mana_tide`) or where warming it would collide with an
existing warm accent (`glass_knight`). **And note the grade cannot be scored by `art_lint`** — every
approach, including the ones that visibly ruin the picture, drives cyan% to 0. The gate must be
visual.

---

## 5. The two decisions that are yours

**① The 11 cross-tribe files.** Split them, or accept that a shared file sits at a neutral
register. Four dissolve with an alias edit; the rest is a real call.

**② The portrait family — and it is not a coin flip.** The oil family *is* the boss set
(`boss_amalgam_*`, `boss_rival_*`, `boss_the_crone`) plus `hero_portrait_kindler`. Choosing ink
means redrawing ~11 bosses; choosing oil means 4 hero portraits + 7 ink bosses. Different bills,
different risk — bosses are seen once per run at peak drama, heroes on every muster screen.

---

## 6. Do not

**Do not fix flatness with atmosphere.** Fog, embers, god-rays and grade are already on every card.
Over-atmosphered, under-acted — add behaviour.

**Do not price a `--sref` regeneration as a colour grade.** A grade preserves the drawing;
`--sref` makes a different picture needing a selection and a review.

**Do not treat the linter's worklist threshold as a fix threshold.** Band D is 53% false positives.
