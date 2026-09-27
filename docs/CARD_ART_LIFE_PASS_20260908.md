# CARD ART — THE LIFE PASS (2026-09-08)

Not a defect list. [`ART_REPLACEMENT_SWEEP_20260908.md`](ART_REPLACEMENT_SWEEP_20260908.md) is
the defect list, and it answers *"what is broken."* This answers a different and better
question: **why is the pool competent and still lifeless, and what makes it cooler and more
endearing.**

---

## 0. First, a correction to the sweep

The sweep told you to replace `stray_cat`, `sprite`, `torchbearer`, `chaos_imp`, `hellfire_imp`,
`gravedigger` as "cute — tone breaks." **That was the wrong call, and it was wrong in an
instructive way.**

I sorted the pool by *pose* and the result is uncomfortable: **almost every card that makes eye
contact with the player is one of the cards I told you to delete.** The glutton caught mid-meal
looking up at you, the goblin sitting and staring, the stray cat, the gravedigger leaning on his
shovel. Those are the only cards in the game that know you exist.

So the diagnosis inverts. The endearing quality you're asking for is *already in the pool* — it
is just concentrated in six cards, and executed in the wrong idiom. `stray_cat` is not bad
because it is endearing. It is bad because it is a **Saturday-morning kitten** instead of a
**war-camp cat with a stolen sausage and one torn ear**. Same warmth, different century.

And this is in the game's DNA, not a deviation from it: CLAUDE.md's first line says *inspired by
Card Wars* — an Adventure Time card game — and the tone memory says **grim/funny/heroic, NOT
horror**. Funny is two-thirds of that sentence and there is currently no funny anywhere in 167
creature paintings. The set drifted toward Darkest Dungeon and left the "Card Wars" half behind.

**Keep the charm. Fix the register.**

---

## 1. The census — what the creature pool actually is

Sorting all 112 creature paintings by what the body is *doing*:

| | share | what it looks like |
|---|---|---|
| **Standing at rest** | ~45 | a helmed or hooded figure, frontal, arms down, weapon held vertical |
| **Caught mid-verb** | ~28 | a limb in motion, a mouth open, something happening |
| **Object / no agent** | ~22 | a wall, a chest, a pyre, a landscape |
| **Face-in-a-blob** | ~10 | the grinning fire/ghost sprites |
| **Looks at the player** | **~12** | and half of those are the six "cute" cards |

**The largest single group in your game is "an armoured man standing still, facing forward,
with his face covered."** Line up `sentinel`, `militia`, `mirror_knight`, `hall_watcher`,
`pikeman`, `shieldbearer`, `ironclad_veteran`, `palisade`, `iron_bastion` and they are the same
card nine times. Each one is well painted. Together they are a catalogue.

That is what "no life" is. Not bad art — **inventory photography of a cast that never does
anything.**

---

## 2. The cause is one line in your own prompt tail

```
... single centered subject ... atmospheric warm-brown painterly backdrop
```

That phrase is in every creature prompt in `MIDJOURNEY_ART_OVERHAUL_20260722.md`, and it is a
recipe for a **mugshot**: one thing, centred, in fog. It optimises for *atmosphere*, and
atmosphere is not life. Add `--s 500` (high stylisation, which pushes toward mood) and a warm
brown backdrop on all 167, and you get a set that is tonally perfect and dramatically flat.

The compounding problem: **`--ar 3:2` is a landscape frame and you are filling it with a
vertical standing man.** That is why so many cards have dead space either side, filled with
brown haze. The frame is asking for a moment; the prompt is giving it a portrait.

---

## 3. The five levers — in order of how much life they buy

### ① Caught mid-verb, never standing
The single highest-value change. Every creature should be interrupted in the middle of doing the
thing its rules text describes. Not *a pikeman* — **a pikeman bracing as something big arrives.**
Not *a shieldbearer* — **a shieldbearer taking a hit he expected.**

Compare your own best and worst on the same idea: `riteforge` (mid-hammer-strike, sparks
flying off the anvil) versus `shieldbearer` (a shield, presented). Same tribe, same palette,
same painter. One is alive.

Prompt words that do this: *mid-swing · bracing · lunging · recoiling · caught mid- · just as ·
the instant that · about to*.

### ② Let them look at you
~12 of 112 make eye contact. It is the cheapest intimacy in illustration and you are barely
using it. It should be **rare and deliberate** — not every card, or it becomes wallpaper — but
it is what makes a card a *character* rather than a unit.

Best used on: strays, beasts, the funny ones, and any card whose rules text is sly
(`the_informer`, `pressed_man`, `sellsword`, `kingpin`).

### ③ Take the helmets off
You cannot love a bucket. A visored helm is a **face delete**, and roughly half your soldiers
wear one. Keep the helm for the *enemy* — a faceless enemy is genuinely good design, it makes
them a force rather than people — and **unhelm the player's own tribe.** That asymmetry does
double duty: it reads instantly on the board *and* it makes your side the one you care about.

This is the fix with the best ratio of "cards changed" to "life gained": it is ~20 repaints and
it converts the largest, dullest group in the pool.

### ④ One asymmetry, one broken thing
Appeal in character design comes from **shape language and silhouette** — round reads friendly
and approachable, sharp reads dangerous — and a design that is too even reads as generic.
Your standing soldiers are bilaterally symmetrical, which is the most inert shape a body has.

Give every creature **one thing wrong with it**: a bent helm, one bare foot, a splinted arm, a
notched blade, a shield that has been repainted twice. It costs one clause in a prompt and it is
the whole difference between *a soldier* and *this soldier*.

### ⑤ Show the aftermath, not the pose
A second story element in frame — what they just did, or what is about to happen to them. The
glutton works because there is a pile of bones. `scholar` works because there is gold on the
table and his hands are *in* it. Give the picture a before and an after and it stops being a
portrait.

---

## 4. What "cool" specifically means at 203×127

**Measured (rev 2), because rev 1 asserted an aperture it never checked.** The painting is never
shown at 225×300 — that is the whole leaf. The hand-card art clip is `offset 11 / -11 / 11 / 138`
on a 225×300 control = **203×127**. The battlefield token is ~184×138, and it carries a
**0.55-alpha black scrim over its bottom 30%** (`Card2D.gd:1084-1093`). Masters are 1.50, the hand
aperture is 1.60 and the board 1.33, both `STRETCH_KEEP_ASPECT_COVERED` — so the same master is
cropped two different ways.

**Consequence for lever ⑤ below:** aftermath is floor-level by definition, so a pile of bones or
spilled gold lands in the band the board scrim darkens and the board crop trims. **Put the story in
the upper two-thirds.**

Two further rules:

**One silhouette, one hot accent.** The cards that read at thumbnail size — `warchief`,
`berserker`, `wolf_c`, `vampire_lord` — have a bold readable shape plus exactly one bright
note. The ones that don't (`concentrate`, `turbo`, `ricochet`, `brute`) are all-over texture
with no shape at all. Players read shapes before details.

**Push the camera in.** Most of your art is at medium distance. The cards with life are close.
Half the frame should be the subject. `--ar 3:2` plus a distant figure equals a small brown
picture of nothing much.

---

> **SUPERSEDED IN PART (same day):** the owner's direction is *one universe, six registers* —
> cute and terrifying deliberately coexisting, sorted by tribe. See
> [`CARD_ART_FAMILIES_20260908.md`](CARD_ART_FAMILIES_20260908.md), which extends the table
> below from silhouette into tonal register and supplies the per-tribe prompt clauses. §0's
> correction stands and that doc explains *why* it was wrong: the cute cards are Beasts and
> Strays, which is where cute belongs.

## 5. Casting notes — give the six tribes six silhouettes

Right now the tribes are told apart by a letterpress footer, not by looking. They should be
readable across the board at a glance. There are 40 Soldiers and 32 Beasts — this is where the
sameness is worst and where a shape rule pays most.

| tribe | n | shape language | the direction |
|---|---:|---|---|
| **Soldier** | 40 | broad, horizontal, overlapping | never alone — a shoulder or a spear-butt of the man beside him in frame. They are a *line*, and the line is their rule. **Faces visible.** |
| **Beast** | 32 | diagonal, low, asymmetric | always in motion and always *arriving* — leaping into frame, half out of it. Never a standing animal portrait. |
| **Dead** | 33 | vertical, drooping, tattered | the moment *after*. Something is falling, sagging, or coming apart mid-frame. Grief and slapstick both live here. |
| **Warlock** | 15 | tall, thin, one bright point | the hands do the work — always mid-gesture, the light source in the palm, the face lit from below by their own spell. |
| **Bastion** | 16 | square, heavy, immovable | the hardest tribe to make live because they are walls. **Give the wall a garrison** — a face at an arrow-slit, hands over the parapet. A wall with someone behind it is a character; a wall is a wall. |
| **Stray** | 18 | irregular, off-centre, cropped | the tribe that looks at you. Sly, caught, half-turned, mid-theft. **This is where the humour belongs** and where `stray_cat` should have landed. |

---

## 6. The revised tail

Replace the creature tail in the MJ docs with this. Changes are marked.

```
[SUBJECT, caught mid-action, with one thing broken or worn wrong], grim-storybook dark-fantasy character, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light --ar 3:2 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

- **removed** `single centered subject` — the mugshot instruction
- **removed** `atmospheric warm-brown painterly backdrop` — the fog that ate the compositions
- **added** `close cropped composition filling the frame` and `strong readable silhouette`
- **added** `one bright accent` — the thumbnail-legibility rule
- **added to `--no`**: `standing still, neutral pose, symmetrical, centered portrait, empty background` — the four words that were producing the catalogue
- **`--s 500` → `--s 400`** — less stylisation drift, more of your subject clause surviving

Keep `--sref` discipline from
[`MIDJOURNEY_BATCH4_MISSING_ART_20260908.md`](MIDJOURNEY_BATCH4_MISSING_ART_20260908.md) §1 —
the tail sets the *look*, `--sref` keeps the batch from drifting apart.

---

## 7. Where to start — 30 cards buys most of it

Do not repaint 167. The pool has a long tail nobody looks at twice; the sameness is concentrated.

1. **The identical standing soldiers.** Unhelm them, put them mid-verb, and the single dullest
   block in the game is gone.
   > **CORRECTED (rev 2): this list was built from the ASSET DIRECTORY, not the card database.**
   > `sentinel`, `militia`, `mirror_knight` and `hall_watcher` are **art file stems with no
   > `CARD_POOL` entry**, and `thornguard` is `ctype: beast`. The real roster is 38 soldiers
   > served by ~25 files — so the job is *cheaper in files* and *more dangerous*: repainting
   > `militia.png` changes `volunteer`, `pressed_man`, `last_levy` and `man_at_arms` at once, and
   > four soldiers with one face is still not four characters. Do the art-sharing pass first —
   > [`ART_PLAN_FINAL_20260908.md`](ART_PLAN_FINAL_20260908.md) §2.
2. **The six "cute" cards, re-registered not deleted** — `stray_cat`, `gravedigger`, `sprite`,
   `torchbearer`, `hellfire_imp`, `chaos_imp`. Keep the eye contact and the warmth; lose the
   chibi proportions and the pastel. This is where the game gets a personality.
3. **The 16 Bastions** — give every wall a garrison.
4. **The five weakest reads** — `concentrate`, `turbo`, `ricochet`, `treasure_hunter`,
   `junk_slot`: all texture, no shape.

That is ~35 cards. It will do more for how the game *feels* than the other 130 combined.

---

## 8. The one thing to not do

Do not fix this with more atmosphere. The instinct when art feels flat is to add fog, embers,
god-rays and grade — and this set already has all four on every card, which is precisely why
everything reads the same. **The pool is over-atmosphered and under-acted.** Every lever above
adds *behaviour*, not effects.
