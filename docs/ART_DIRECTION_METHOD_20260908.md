# HOW THIS IS ACTUALLY DONE — art direction method (2026-09-08)

Research companion to [`CARD_ART_FAMILIES_20260908.md`](CARD_ART_FAMILIES_20260908.md).
The question was *"read online how these things are done"* — how studios run one coherent
universe across many registers and many hands. Two industries have solved exactly this problem:
**trading-card games** (many artists, one world, thousands of cards) and the **cute-horror**
lineage (one world, two opposite tones). Both answers are structural, not stylistic.

---

## 1. The universal shape: three layers, not one style

Every studio that does this at scale uses the same three-layer stack:

| layer | what it is | scope |
|---|---|---|
| **World bible / style guide** | the locked constants — palette, materials, light, shape language, do's and don'ts | the whole set |
| **Per-asset brief** | what *this one* picture shows | one card |
| **Review against the guide** | the pass/fail gate before it ships | every asset |

An art bible typically holds **visual pillars, character sheets with scale charts, environment
intent, colour and material guides with shape language, explicit do's/don'ts, and UI intent** —
the point being to *"keep consistency in all the artistic elements"* and answer questions during
production without the director in the room.

**What matters for this project:** you already have layer 1 (the prompt tail + `art_lint.py`)
and layer 3 (the lint baseline). **What is missing is layer 2** — a real per-card brief. The
subject line in an MJ prompt is currently doing that job informally, which is why 45 creatures
came out standing still.

---

## 2. Magic: The Gathering — the deepest well, and directly transferable

MTG has run this problem for thirty years: **3,000+ commissioned illustrations a year, 100–200
in progress at any moment**, hundreds of artists, and each set still reads as one place.

Two artifacts do the work.

**The style guide** is an internal book of concept art defining a set's world, distributed to
artists *"to use as a guide when creating artwork"* so that all commissioned art *"will maintain
a consistent look."* This is your prompt tail plus your `--sref` anchor — same job.

**The art description** is the per-card brief, and this is the piece worth stealing outright.
The art director sends the artist a structured description with fixed fields:

> **Color · Location · Action · Focus · Mood**
> *(plus **Setting** and **Intent** when the world flavour matters)*

A real example reads: *"Color: Red creature. Location: Unimportant; perhaps craggy wasteland.
Action: Show a female goblin rigger leaping off of the base of a rusty bronze monument to attack
foes below. Focus: The goblin attacker. Mood: ..."*

Look at what that structure forces. **Action is a mandatory field** — you cannot fill in a form
that demands a verb with "a goblin, standing." **Focus is mandatory** — it forces the one-subject
thumbnail read. **Mood is separate from Color** — which is exactly the cute/terrifying axis
separated from the palette lock. The form is a machine for producing the five levers.

**The known failure mode, stated by MTG's own critics:** as brief and style-guide rigidity has
increased, the common complaint is that *all Magic art looks the same*. Over-lock and you trade
drift for monotony — which is precisely the disease diagnosed in
[`CARD_ART_LIFE_PASS_20260908.md`](CARD_ART_LIFE_PASS_20260908.md). Guard against it by varying
**Action** and **Focus** aggressively while keeping **Color/Setting/material** rigid. Vary the
verb, never the world.

---

## 3. Cult of the Lamb — how cute-and-terrifying is actually engineered

The clearest modern statement of your exact direction. Three findings, all from the team:

**① The base register must be the soft one.** Art director Julian Wilton: the juxtaposition works
because *"it makes the darker stuff feel a lot darker because the neutral stuff at the base is a
bit more happy and cute."* The horror reads as horror **because it is a deviation from a warm
baseline** — not because it is loud.

> **This slightly revises the families doc.** I put *Soldier — human, worn* as the anchor. Correct
> for silhouette, but the evidence says the emotional baseline should sit **warmer** than
> neutral. Push Soldiers toward the gallows-funny, fond end of human — mates, banter, a shared
> bad joke — not stoic grimness. If the base is already grim, the Warlocks have nothing to
> deviate *from* and the game flattens into one note. **The grimness should live in the
> situation, not in the baseline art.**

**② Cute is a permission structure.** Jay Armstrong: *"The strength of the cute art is that it
allows us to put horrendous things in the game without it ever feeling too horrible."* The
charm is what lets you go darker in *content* — which is the resolution of the tone rule
"grim/funny/heroic, not horror." You get to keep the grim subject matter precisely by *not*
drawing it grimly.

**③ Cuteness is an attachment mechanic, and attachment is stakes.** Making followers endearing
*"intensified the moral weight"* of sacrificing them. **This game already has the mechanics that
cash that in** — the Roll of the Fallen, Hold a Wake, veteran epithets, creatures that earn names
over three kills. Those systems are currently spending their emotional budget on *unhelmed
strangers you cannot see the faces of*. Make the cast endearing and the existing death systems
start working for free.

**④ Their one hard constraint: never shift toward realism.** A single stated rule held the whole
thing together. That is the same finding as the sweep's photoreal cluster — `war_drum`,
`warlords_standard`, `warm_knucklebone`, `coin_on_edge`, `fork_in_the_long_road` — and it means
those are not merely off-style, they are the one deviation this genre cannot absorb.

One caution on transfer: Cult of the Lamb could run loose because it was **two artists with one
irrepressible natural style** — *"whatever they draw is adorable, and there is nothing they can
do about it."* A diffusion model has no natural style, so it will drift to the mean of its
training data every single time. **Solo + AI therefore needs the MTG end of the spectrum**: the
brief has to supply what a human artist's hand would have supplied for free.

---

## 4. What to actually build here

**Convert the prompt tail into a brief template with locked and free fields.** This is layer 2,
it is the missing piece, and it is a text file.

```
CARD:     <id>            TRIBE: <tribe>
─────────────────────────────── LOCKED (never varies) ───────────────────────────────
SETTING:  the Successor Wars — the same road, the same bad month, mud and kit on everything
COLOR:    sepia / ochre / umber, ember-orange rim light, single firelit source
MEDIUM:   hand-painted, visible brushwork, bold ink linework.  NEVER toward realism.
FRAME:    fills the frame, close crop, one readable silhouette, one bright accent
─────────────────────────────── FREE (the whole job) ────────────────────────────────
INTENT:   <the tribe register clause — FAMILIES doc §6>
ACTION:   <a verb, mid-motion. mandatory. "standing" is not an answer.>
FOCUS:    <the one thing the eye lands on>
MOOD:     <the feeling — this is the cute/terrifying axis, NOT the palette>
WRONG:    <the one thing broken, worn, or asymmetric about it>
```

Worked example — `cinder_whelp`, a **Beast** with **Doom** (a countdown to detonation), which is
the recommended starting slice:

```
CARD:     cinder_whelp     TRIBE: beast (Doom)
INTENT:   endearing and clearly dangerous, expressive animal eyes
ACTION:   scrabbling happily toward the viewer, tail wagging, trailing sparks
FOCUS:    the pup's delighted face
MOOD:     adorable and unmistakably doomed — the fuse is the joke and the threat
WRONG:    one ear burnt off; the fuse on its back is visibly shorter than it should be
```

Read that back and notice it produced the collision **without a single word about style.** Mood
did the tonal work, Action did the life work, and the locked block kept it in the same world.
That is the whole method.

**The board test.** MTG's guide keeps a *plane* coherent; yours has to keep a **board** coherent —
eight cards visible at once, at 225×300. So add one review question the TCGs do not need:
*with six tribes side by side at card size, can you still tell it is one game?* If yes, the locks
are holding and you can push the registers further apart than feels comfortable.

---

## 5. The two failure modes, named

| | cause | symptom | your current position |
|---|---|---|---|
| **Drift** | layer 1 too weak | photoreal next to painterly, cyan next to sepia | ~103 cool-cast assets, a photoreal cluster |
| **Monotony** | layer 2 too weak | competent, on-model, inert | 45 of 112 creatures standing still |

**You have both at once**, which sounds contradictory and is not: the *style* fields drifted
while the *subject* fields were never specified at all. The tail was over-trusted to do a job it
cannot do — a style guide has never once told anyone what is happening in the picture.

---

## Sources

- [The Art of Magic: the Gathering — Muddy Colors](https://www.muddycolors.com/2016/02/the-art-of-magic-the-gathering/) · [MTG style guides explained](https://mtg.fandom.com/wiki/Style_guide) · [A peek into MTG's card style guides](https://outof.games/news/2483-in-the-frame-a-little-peek-into-magic-the-gatherings-card-style-guides/) · [How MTG creates card art](https://outof.games/news/2403-in-the-frame-how-magic-the-gathering-creates-card-art/)
- [MTG art descriptions, with real briefs](https://magic.wizards.com/en/news/making-magic/you-make-card-4-art-descriptions-2013-06-17) · [Ultimate Masters art descriptions](https://magic.wizards.com/en/news/feature/ultimate-masters-art-descriptions-2018-12-04) · [Why you think all Magic art looks the same](https://www.coolstuffinc.com/a/mikelinnemann-09062017-why-you-think-all-magic-art-looks-the-same)
- [Corralling the inherent cuteness of Cult of the Lamb — Game Developer](https://www.gamedeveloper.com/design/interview-corralling-the-inherent-cuteness-of-cult-of-the-lamb) · [Cult of the Lamb art director on making a sinister game cute — Inverse](https://www.inverse.com/gaming/cult-of-the-lamb-concept-art-interview-massive-monster/amp) · [Finding the balance between cute and horrifying — Dread Central](https://www.dreadcentral.com/horror-gaming/488375/finding-the-balance-between-cute-and-horrifying-cult-of-the-lamb-interview-with-james-pairmain-art-director/)
- [Game art bible: the AAA style guide studios actually use](https://nastyrodent.com/game-art-bible/) · [Style guides & art bible creation](https://www.menogcreative.com/style-guide-art-bible) · [Art direction in indie games](https://www.wayline.io/blog/cult-of-good-enough-indie-game-art)
