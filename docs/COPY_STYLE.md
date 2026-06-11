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

## 10. What to report back

For your assigned file(s), return:
1. A count of strings changed.
2. The 5–10 most impactful before→after pairs.
3. Anything you could **not** safely normalize (e.g. a desc whose mechanic was
   ambiguous, a card whose text claims `On-Enter` but lacks the chip, a name
   collision) — flag it for a human/mechanical pass rather than guessing.
4. Confirmation you touched **only** player-facing string values.
