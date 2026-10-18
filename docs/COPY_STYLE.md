# Burning Meadow — In-Game Copy Style Guide

The single source of truth for **player-facing text**: card names/descriptions,
keyword tooltips, relic/encounter/hero text, event prose, and UI strings. The
goal is **legibility through consistency** — the same mechanic is always named
the same way, so players learn the vocabulary once and read fast.

> This guide governs *wording*. It never authorizes changing what a card does.

---

## 0. Golden rules (read first)

1. **Edit only the text a player reads.** Change the *values* of `name`,
   `desc`, `passive_desc`, event titles/body/choice text, and `.text = "..."`
   UI string assignments. **Never** touch: dict keys, `id`/`type` values,
   numbers that encode mechanics (`atk`, `hp`, `cost`, `value`, `wither`,
   thresholds), the contents of `keywords` arrays, `spell.type`, targeting
   strings, or any code/logic.
2. **Never change a mechanic.** If a card "deal 2 damage", it still deals 2.
   You may re-word *how it's described*, never *what it resolves to*. When in
   doubt, preserve meaning exactly and only fix phrasing.
3. **Do not change KeywordEffects `display` strings.** Card text is colorized by
   matching those exact display names (`KeywordEffects.colorize_keywords`).
   Changing a `display` value silently breaks gold-highlighting everywhere. You
   may refine a keyword's `desc` (the tooltip body); never its `display`.
4. **Surgical edits.** Stay inside the quotes of the string you're changing.
   Don't disturb commas, braces, or surrounding structure — a stray edit is a
   parse error that breaks the build.
5. **Shorter is better.** Card wells are small (text renders ~9–11px with smart
   word-wrap). Cut filler. Prefer the shortest phrasing that stays unambiguous.

---

## 1. Trigger labels

Use a **`Trigger: effect.`** shape — capitalized trigger, colon, one space,
then the effect as a sentence ending in a period.

| Use | When | Example |
| --- | --- | --- |
| `On-Enter:` | the card **has** the `on_enter` keyword chip | `On-Enter: deal 1 damage to the opposing creature.` |
| `On-Death:` | the card **has** the `on_death` keyword chip | `On-Death: deal 2 damage to the opposing lane.` |
| `When played:` | an immediate placement effect with **no** `on_enter` chip | `When played: heal this creature 2 HP.` |
| `Start of each round:` | recurring, top of round | `Start of each round: heal 1 HP.` |
| `End of each round:` | recurring, end of round | `End of each round: add 1 Curse to your discard pile.` |
| `When you <X>:` | reactive player trigger | `When you take face damage: your creatures get +1 ATK this round.` |
| `When a <X> dies:` | reactive death trigger | `When a friendly dies: draw 1.` |

- **`On-Enter` / `On-Death`** are the keyword display names — hyphenated, both
  words capitalized. Never `On-enter`, `on-death`, `On enter`, `Enters:`.
- **`On play` / `On-play` is not a keyword.** If it means a placement trigger,
  convert it: → `On-Enter:` (if the chip is present) or `When played:` (if not).
- Match the chip. A card that says `On-Enter:` must carry the `on_enter`
  keyword; if it doesn't, use `When played:` instead (or flag it in your report
  as a possible missing-keyword case — do **not** add the keyword yourself).

---

## 2. Damage, healing, and stats

- **Always include "damage."** Never `deal 1 to X`. Always `deal 1 damage to X`.
- **Healing:** `heal <target> N HP` — e.g. `heal this creature 2 HP`,
  `heal a friendly creature 4 HP`. Not "for 4 HP", not "restore".
- **Stat changes:** `+1 ATK`, `+1 HP`, `-1 ATK`, `+1/+1` (ATK/HP shorthand).
  Always a sign, always the stat in caps. Never "1 attack", "one ATK".
- **Numbers are digits**, always: `3`, `+2`, not "three", "two".

---

## 3. Target vocabulary (these words carry meaning — use the right one)

| Term | Meaning |
| --- | --- |
| `the opposing creature` | the enemy directly across (same column, front) |
| `the opposing lane` | the column directly across |
| `an enemy creature` | player **chooses** an enemy (targeted) |
| `a random enemy creature` | engine picks an enemy at random |
| `all enemy creatures` / `all enemies` | every enemy creature |
| `an adjacent enemy` / `adjacent enemies` | left/right neighbors |
| `enemy face` | the opponent's HP directly (`face damage`) |
| `a friendly creature` | player chooses one of yours |
| `adjacent friendlies` | your left/right neighbors (plural shorthand OK) |
| `all friendlies` | all your creatures |
| `this creature` | the card itself |

- **`opposing` ≠ `enemy`.** `opposing` = positionally across; `enemy` = anyone on
  their side. Keep whichever the mechanic actually means — do not swap them.
- **`friendly`** is an adjective (`a friendly creature`) or the plural noun
  `friendlies`. Don't use bare singular "a friendly".

---

## 4. Keywords are always Capitalized

So they read as named mechanics (and so `colorize_keywords` gilds them). The
canonical display names:

`Armored` · `Swift` · `Ranged` · `Thorns` · `Regenerate` · `Summon` ·
`Last Stand` · `Piercing` · `Sacrifice` · `Exhaust` · `Retain` · `Wither N` ·
`On-Enter` · `On-Death` · `Adj. Buff` · `Poison` · `Shield` · `Guardian` ·
`Structure` · `Slay`

- In running text too: `Your On-Enter damage effects deal +1 damage.` (not
  "on-enter"), `Swift creatures have +1 ATK.`
- `Wither N` shows the number: `Wither 1.`

---

## 5. Durations — distinct meanings, do not collapse

| Phrase | Meaning — **keep the right one** |
| --- | --- |
| `this turn` | only during the current player placement phase (mana, draw) |
| `this round` | until the end of the current combat round |
| `this fight` | the rest of the encounter |
| `this run` | the rest of the run (meta) |

- **Standardize the synonym:** `this combat` → `this fight`. `per combat` →
  `per fight`. Pick **`fight`** everywhere; retire "combat" from player text.
- Never swap `round` ⇄ `turn` ⇄ `fight` — they are mechanically different.

---

## 6. Command & cost

- **The per-turn resource is `Command` — capitalized, always.** Never `mana`,
  `energy`, or `action points` in player text (renamed 2026-06-11; the codebase
  still says `mana` in identifiers — `player_mana`, `gain_mana`, `boss_mana` —
  and those NEVER change). It is a mass noun: `gain 2 Command`, `+1 max
  Command`, `Not enough Command!`, `spend all your Command`.
- `costs 1 less` / `costs 0` — **no parentheses.** Convert `costs (1) less` →
  `costs 1 less`.
- `gain 1 Command` = permanent-ish; `gain 1 Command this turn` = expires.
  Preserve the qualifier exactly as written.
- Carryover is **banking**: `bank`, `unspent Command carries over`. The glossary
  entry is named "Banking" — keep that vocabulary, don't invent "reserve"/"save".
- **The elite-band fights are `Generals` in player text** — capitalized, always
  (renamed 2026-06-12; code identifiers still say `elite` — node types,
  `ELITE_ROW`, hook names — and those NEVER change). Map legend, tooltips, the
  combat intro banner, and relic descs all say General: `After you defeat a
  General: …`.

---

## 7. Punctuation, casing, length

- **End every desc with a period** — including keyword-only ones: `Armored.`,
  `Swift.`, `Poison.`.
- **Sentence case** for effect text. Capitalize only sentence starts, keyword
  names, and proper nouns (creature/relic names, "Curse", "Soldier", "Wraith").
- Join two effects with a period + space, not a semicolon, unless one clause
  depends on the other: `Deal 3 damage to a creature. Slay: draw 1.`
- **Keep it tight.** Aim for ≤ ~90 characters on cards; if a desc runs longer,
  look for filler to cut before accepting the wrap.

---

## 8. Names

- Card/relic/creature/event **names**: Title Case, no trailing punctuation.
- Don't rename things that are referenced elsewhere by name in player text
  (e.g. a relic that another card's desc names). If you rename, update every
  reference — or leave it and note it.

---

## 9. Worked examples (before → after)

```
"On-enter: deal 1 to enemy face."        → "On-Enter: deal 1 damage to enemy face."
"On play: heal this creature 2 HP."      → "When played: heal this creature 2 HP."
"Deal 2 to a random enemy creature."     → "Deal 2 damage to a random enemy creature."
"Adjacent friendlies +1 ATK. Wither 1."  → "Adjacent friendlies +1 ATK. Wither 1."   (already good)
"Your on-play effects trigger twice."    → "Your On-Enter effects trigger twice."
"...gets +2 ATK this combat."            → "...gets +2 ATK this fight."
"the next card... costs (1) less."       → "the next card... costs 1 less."
"Heal a friendly creature for 4 HP..."   → "Heal a friendly creature 4 HP..."
```

---

## 10. Event prose — the road register (2026-07-18 readability pass)

Events are read mid-run, between fights — write for a tired player, not a
literature seminar. Modelled on Failbetter's Fallen London writer guidelines.

- **Budgets:** event `desc` ≤ ~40 words; each choice flavor line ≤ ~20 words;
  result/roll/gamble texts ≤ ~60 words. Cut content before compressing syntax.
- **Name things plainly, then color them.** The first sentence of a desc says
  what the player is looking at. "Overhead hangs her swarm: homeless, furious"
  — never a riddle to decode ("a homeless roar"). No withheld referents.
- **Short active sentences, one idea each.** No triple-clause dash chains.
  Fragments are fine when they land a beat ("Tails.").
- **Direct speech over reported speech.** Let the NPCs talk.
- **Period vocabulary is seasoning, not an ingredient.** No unglossed archaic
  or trade words (skep, escalade, chirurgeon, chit, remount). If flavor needs
  one, explain it in the same breath — or use the plain word.
- **The label's first line is the action** — plain verb first. The two flavor
  lines under it may carry tone but never hide what happens; the mechanic
  `desc` line states the deal in this guide's vocabulary (§1–§7).
- **Tone stays multi-register** (grim / funny / eerie). Humor and horror come
  from incident and speech, not from vocabulary.
- **One shared world.** Canon anchors: the Old King (dead, unpaying — the
  Successor Wars' corpse), the Fourth Legion he never paid (the Bone Pit's
  dead, the clerk's strongbox IV, the Last Garrison's war), the spinner, the
  parish, {lord}/{kingdom} at war. Recognition beats stay sparse — one line,
  never a lore dump; `seen_texts` and blue options carry the cross-references.

---

## 11. Rendering — the readability contract (2026-07-20 research pass)

§0–§10 govern wording; this section governs how text is allowed to **land on
screen**. Grounded in the Game Accessibility Guidelines, Xbox Accessibility
Guidelines (XAG 101/104), BBC subtitle research, and desktop typography
practice. Our canvas is 1600×900 (`canvas_items` stretch): **1 canvas px = 1
real px at a 1600×900 window** — size for that worst case, not for your 4K
monitor. Industry floors: ~16px for desktop-distance play, ~28px at 1080p for
couch/10-foot play; lines over ~40 characters slow fast reading.

### The three registers (the 2026-07-06 law, restated)

- **Reading text** — prose, descs, tooltips, interactive labels, anything a
  player must read to make a decision: **≥ 18px**, prefer
  `GameTheme.MIN_LABEL_SIZE` over a literal.
- **Caption chips** — subordinate one-breath markers riding a bigger element
  (combat "NEXT ROUND", stage captions, pay ledgers, posted rules): **15–17px**,
  all-caps or short words, ≤ ~8 words. A caption that states **rules, odds, or
  live state is informational** — it may sit at 15–16, never below. The
  minigame legibility aids (ledgers, drills, round trackers) are this register:
  the honesty promise dies if the honest text is too small to read.
- **Fitted numerals** — numbers set inside drawn objects (wax seals, count
  badges, cost gems, Card2D's whole tuned system): free-sized; the object
  provides the legibility.

**Nothing worded renders below 14px, ever.** `tools/_probe_text_floor.gd`
(headless) fails on a sub-14 worded size override; a deliberate fitted-numeral
or glyph exception carries a `# textfloor: fitted` waiver on the same line.

### Line measure

- Body prose: **50–80 characters per line** (the event column runs ~60 — keep
  it there). Under ~35 the text churns; past ~90 the eye loses the return sweep.
- Fast-read text (combat captions, battle-log rows, one-beat callouts): aim
  **≤ ~40 characters** — one fixation group, no wrap.

### Leading and casing

- Multi-line prose keeps line spacing in the **130–150%** band (card faces run
  tighter by tuned exception — see the Card2D leading comment).
- **ALL-CAPS is for micro-labels and captions only.** Caps erase word shape;
  never set running prose in caps. Letterspace caps slightly; never
  letterspace lowercase.

### Contrast

- Reading text holds **≥ 4.5:1** against its ground (WCAG AA); display text
  ≥ 3:1. The house mechanics that guarantee it: `make_label`'s automatic 2px
  near-black outline under 22px, the adaptive event scrim, tooltip panels,
  the card-face dark-bronze keyword re-ink (`#7a4f10` on paper). Text over art
  always gets a scrim, plate, or outline — never bare.
- Color is never the only channel: pair every color cue with a word or shape.

### Hierarchy

Three tools, in this order: **size, contrast, position**. One voice per
register per screen — if two nearby sizes are doing the same job, merge them.
Don't invent a new size stop; pick the register and use its band.

---

## 12. UI chrome is exempt from the road register (2026-08-06 plain-language pass)

§10's road register governs **event prose and card/relic flavor only**. It had
leaked into UI chrome, where it cost the player information: *march*, *column*,
*host*, *roll*, *opener*, *company*, *warband*, *weight* and *rank* were all
doing noun-work in labels, and several were doing it for **two different
mechanics at once**.

**Screen titles, buttons, section headers, HUD captions, tooltips, empty states
and event choice ACTION labels use standard product language.** The rules:

- **Verb first; name the outcome.** `Choose a card to sell`, not `Lay one on
  the counter. He pays by weight.` A label states what it does.
- **No riddles and no withheld referents.** If a phrase needs the setting to
  decode, it is wrong. `TAKE THE FIELD` → `START RUN`.
- **A blocked state names the cause *and* the effect.** `Temperance Vow` →
  `No potions (Temperance Vow)`.
- **One term per concept, across every screen.** This is the rule the old copy
  broke hardest — "banner" meant both a faction choice and a creature's
  keyword; "order" meant both a set-piece objective and an enemy intent badge.
- **Proper nouns stay**: Burning Meadow, hero/relic/card/encounter names,
  `Command`, `General`, `Forge`, `Daily Run`, and every keyword display name.
  (**`Daily Run`, corrected 2026-09-10.** This section said `Daily March` and the
  DOC was the stale side: an audit of on-screen labels found every player-facing
  string already reads *Daily Run* — the button in both places it is built, the
  active-options chip, and the How-To-Play heading — while every surviving
  *Daily March* is a code comment or a probe's own `print`. The §12 rule is one
  term per concept **as the player meets it**, so the screens win.)
- **Settled vocabulary** (do not re-split these): the run is a **run**, not a
  march; the deck is a **deck**, not a company/warband/column; the upgrade
  action is **Forge** everywhere, including event choice labels; the per-fight
  modifier is a **Battle Rule**, not a mutator/omen; combat rows are **rows**,
  not ranks; the human opponent is the **opponent**, a board creature is the
  **enemy**.

Event `desc` prose, flavor lines, result text and the defeat refrains keep the
road register — only the choice's ACTION label is held to this section.

**Two structural traps to know before writing a label:**
`tools/_probe_copy_lint.gd`'s `_check_shouting` fails a LONE all-caps word of
3+ chars, so an ALL-CAPS label needs two capped words. And several UI strings
are asserted verbatim by probes in `tools/` — grep `scripts/` **and** `tools/`
before changing one, and update every site together.

---

## 13. What to report back

For your assigned file(s), return:
1. A count of strings changed.
2. The 5–10 most impactful before→after pairs.
3. Anything you could **not** safely normalize (e.g. a desc whose mechanic was
   ambiguous, a card whose text claims `On-Enter` but lacks the chip, a name
   collision) — flag it for a human/mechanical pass rather than guessing.
4. Confirmation you touched **only** player-facing string values.
