# MIDJOURNEY — THE COMPLETE PROMPT PACK (2026-09-08)

**160 copy-paste prompts covering the entire live R1+R2 queue**, grouped into batches so each
one is a single `--sref` sitting. Companion to
[`ART_PLAN_FINAL_20260908.md`](ART_PLAN_FINAL_20260908.md) (the why) and
[`MIDJOURNEY_BATCHES_20260908.md`](MIDJOURNEY_BATCHES_20260908.md) (the 16 hand-verified
priority images + the six additive armaments, which are **not repeated here**).

## Read this first

**Every subject below was written from the card's own NAME and RULES TEXT, never from the
filename.** That matters more here than anywhere: this repo's art ids are legacy and routinely
lie about what the card is.

| file id | the card actually is |
|---|---|
| `lightning.png` | **"Sling Stone"** — 0c, deal 2. A rock, not lightning. |
| `fusion_hammer` | **"Cracked Anvil"** — an anvil, not a hammer |
| `junk_slot` | **"Open Ground"** — an empty field, and the old art was already right |
| `mana_tide` | **"War Chest"** · `mana_pearl` → **"Knife Up the Sleeve"** · `mana_drunkard` → **"Forced March"** |
| `coffee_dripper` | **"Hairshirt"** · `ectoplasm` → **"Vow of Poverty"** · `sozu` → **"Temperance Vow"** |
| `snecko_eye` | **"Basilisk Eye"** · `mime` → **"Mummer's Mask"** · `velvet_choker` → **"Penitent's Collar"** |
| `archmage.png` | serves **four Warlocks** — Glass Cutter, Coven Mother, The Apothecary, The Magister |
| `cinder_whelp` | **"Grinning Blaze"** 5/4 Doom 2 · `hellfire_imp` → **"Live Coal"** 4/3 Swift Doom 2 |

**The player-facing relic names have already been de-Slay-the-Spire'd.** Only the ids are stale —
so an earlier note in this session claiming the *names* needed renaming was wrong. Nothing to do.

**Where a file serves several cards the header says so**, because the painting has to suit all of
them — `gravedigger.png` carries five Dead cards, `archmage.png` four Warlocks.

## Before you paste anything

1. **Pin the anchor.** Every prompt ends `--sref YOURCODE --sw 100`. That placeholder appears 26
   times across this repo and has never been replaced with a real code — it is the root cause of
   the palette drift. Generate the four anchor images in
   [`MIDJOURNEY_BATCHES_20260908.md`](MIDJOURNEY_BATCHES_20260908.md) §0 with **no** sref, pick
   one, and use its code everywhere below. Record it in `tools/golden/art_style.json`
   **together with `--v 8.1`** — sref and model version are one unit.
2. **Aspect ratios are deliberate.** Cards `--ar 8:5` (the hand aperture is 203×127 = 1.598, so
   8:5 crops nothing; a 3:2 master loses ~6%). Icons `1:1`, events/backgrounds `16:9`,
   portraits `3:4`.
3. **One batch per sitting, 25–40 images.** Below 15 you cannot see cohesion; above 50 the back
   half gets waved through.
4. **Run `tools/art_compare.py` before overwriting any incumbent.** Roughly a third of this queue
   is a cyan REGRADE, not a subject failure — for those the existing drawing may well beat a
   fresh generation, and the subject lines below deliberately restate the existing composition so
   you can compare like with like.

## What is NOT in this pack, on purpose

- **The six armaments** — in the companion doc. They are purely additive (no file exists yet, and
  the loader prefers a direct file over an alias), so they overwrite nothing. Do them first.
- **The 11 keyword devices + `shop.svg` + the d20** — these draw at 18px and the status rail
  **tints them**, which needs a flat single-path SVG. Midjourney is the wrong tool; take them from
  game-icons.net.
- **`hud_gold.png`, `hud_potion.png`, `atk_sword.png`, the 4 root silhouettes, `node_event.png`** —
  dead fallbacks or unconsumed loads. Nothing renders them. Delete, don't redraw.
- **`ember_stalker`, `the_black_tide`, `venom_tip`, `lancer`, `kindling_alt`** — verified as
  correct or not-a-card. See `MIDJOURNEY_BATCHES_20260908.md` §5.

## After each file lands

`--import` → `python tools/art_compare.py <old> <new>` → `python tools/art_lint.py --baseline` →
`python tools/_art_sweep_20260908.py` → append the exact shipped prompt to `docs/ART_BRIEFS.md`.

---

## BATCH — CREATURES · WARLOCK  (4)

**`assets/creatures/archmage.png`** — serves 4 cards: Glass Cutter, Coven Mother, The Apothecary, The Magister

```
a coven matron at a trestle table of candle-stubs and cut paper, mid-gesture with both hands, her fingers one joint too long and bending the wrong way, three hooded apprentices behind her copying the gesture exactly, none of them blinking, quietly wrong and unsettlingly calm, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/crow_witch.png`** — serves 1 card: Hexwright

```
a hexwright crouched over a scratched sigil in the mud, drawing it with a bird's leg-bone, her head turned too far around on her neck to look back at you, crows on the fence behind her all facing the same wrong way, quietly wrong, unsettling calm, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/ember_mystic.png`** — serves 2 cards: Fuse Tender, Emberwright

```
a fuse-tender kneeling among powder kegs, calmly threading a lit match-cord between her fingers, her face lit from below and entirely untroubled by the sparks, one hand with too many knuckles, quietly wrong, unsettling calm, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/leyline_conduit.png`** — serves 1 card: The Witch-Post

```
a tall witch-post of lashed timber standing in a field, hung with rags and finger-bones, a robed figure pressed against it with both palms and their cheek, eyes shut and smiling slightly, the grass around the post lying flat in a ring, quietly wrong, unsettling calm, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — CREATURES · DEAD  (9)

**`assets/creatures/corpse_eater.png`** — serves 3 cards: Corpse Eater, Gravepact, Grave Clutch

```
a gaunt battlefield scavenger squatting over a dead man's kit, chewing, looking up as if interrupted at supper, a wight already half risen out of the mud behind him that he has not noticed, melancholy and faintly absurd, dignity slipping, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/doom_knight.png`** — serves 1 card: Doom Knight

```
a burning armoured knight still walking forward with a lit fuse trailing from a cracked breastplate, sword out, entirely composed about it, melancholy and faintly absurd, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/e_bone_knight.png`** — serves 3 cards: Old Bones, Grave Soldier, Bone Knight

```
a skeleton soldier reassembling itself mid-stride, holding its own detached arm in its other hand and about to socket it back, helmet on backwards, still marching, melancholy and faintly absurd, dignity slipping, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/gravedigger.png`** — serves 5 cards: Ash Marker, Burial Goods, Gravedigger, Grave-Goods, Body-Snatcher

```
a stooped old army gravedigger resting on his spade at the lip of a fresh trench grave, caught mid-sentence talking to the man he is burying, a lantern hooked on the spade handle, grave-goods laid out on the turned earth, his coat two sizes too big, melancholy and faintly absurd, dignity slipping, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/kindling.png`** — serves 1 card: Kindling

```
a small cheerful bundle of firewood soldiers' kindling with a face in the grain, grinning up at the viewer, a lit fuse standing out of the top of it and already half burnt down, warm and unmistakably doomed, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/necromancer.png`** — serves 1 card: Necromancer

```
a mud-caked levy conscriptor hauling two dead men upright by their collars, one under each arm, straining like a man carrying too much firewood, the corpses' boots dragging, melancholy and faintly absurd, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/risen_lich.png`** — serves 1 card: Carrion Priest

```
a carrion priest standing over the fallen with a censer, shielding a wounded soldier with his own body while reading the rites aloud from a sodden book, melancholy and faintly absurd, dignity slipping, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/summoner.png`** — serves 1 card: The Levymaster

```
a levymaster with a muster roll shouting names down into an open grave pit, and hands coming up out of it to answer, exasperated rather than frightened, melancholy and faintly absurd, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/vengeful_spirit.png`** — serves 2 cards: Vengeance, The Undying

```
a wrathful gaunt war-ghost hauling itself up out of the churned ground, tattered grave-shroud and trailing chains, a face twisted with grievance rather than menace, pale ember-gold fury gathering around it, melancholy and faintly absurd, never horror, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — CREATURES · BEAST  (9)

**`assets/creatures/cinder_whelp.png`** — serves 1 card: Grinning Blaze

```
a grinning blaze of a creature, a squat happy thing made of burning coals with a wide delighted face, bounding toward the viewer, a lit fuse standing out of its back already half burnt down, adorable and unmistakably doomed, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/basilisk.png`** — serves 1 card: Basilisk

```
a heavy thorn-backed bog toad the size of a dog, blinking slowly at the viewer with enormous wet eyes while something small dies quietly beside it, endearing and clearly dangerous, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/chaos_imp.png`** — serves 1 card: Chaos Imp

```
a scruffy pot-bellied imp mid-scramble across a war camp with a stolen lit firework in both arms, delighted, ears back, absolutely going to regret this, endearing and clearly dangerous, expressive animal eyes, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/e_bog_lurker.png`** — serves 2 cards: War Boar, Bog Lurker

```
a huge scarred war boar erupting out of reeds at a charge, mud sheeting off its shoulders, tiny bright eye fixed on the viewer, endearing and clearly dangerous, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/harpy.png`** — serves 1 card: Snatch-Hawk

```
a snatch-hawk stooping into frame with a soldier's helmet already in its talons, wings cocked, head turned to look right at the viewer mid-theft, endearing and clearly dangerous, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/hellfire_imp.png`** — serves 1 card: Live Coal

```
a live coal of a creature, a small round grinning ember-beast sprinting on stubby legs, trailing sparks, cheerful and moving far too fast, a fuse burnt almost to its back, adorable and unmistakably doomed, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/plague_rat.png`** — serves 1 card: Ditch Adder

```
a lean ditch adder coiled on a dead man's pack, jaw open mid-strike, one bright eye catching the firelight, endearing and clearly dangerous, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/raven.png`** — serves 1 card: Gallows Crow

```
a big ragged gallows crow perched on a broken pike, head cocked, one eye locked on the viewer, a soldier's ring already in its beak, endearing and clearly dangerous, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/sprite.png`** — serves 1 card: Gamecock

```
a battered gamecock mid-flap on a camp fence, spurs out, crowing at the whole army, absurdly self-important, endearing and clearly dangerous, expressive animal eyes, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — CREATURES · STRAY  (5)

**`assets/creatures/assassin.png`** — serves 1 card: Assassin

```
a hooded knifeman already withdrawing the blade, stepping backwards out of frame with his eyes on the viewer and a finger to his lips, the body not yet fallen behind him, sly, caught in the act, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/copycat.png`** — serves 1 card: Changeling

```
a changeling caught halfway between two faces, one side a stranger's and one side yours, straightening its own collar in a scrap of mirror and grinning at the viewer, sly, caught in the act, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/doppelganger.png`** — serves 1 card: Dead Man's Face

```
a shabby mercenary pulling a dead man's face on like a hood, one eye already changed and looking straight at the viewer, entirely unembarrassed, sly, caught in the act, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/stray_cat.png`** — serves 1 card: Camp Follower

```
a lean scarred camp cat crouched on a broken wall above a war camp, a stolen strip of salt meat in its jaws, one ear torn and healed crooked, caught looking straight at the viewer completely unrepentant, laundry lines and tent poles behind it, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/treasure_hunter.png`** — serves 1 card: The Looter

```
a looter halfway out of a collapsed strongroom with an armful of somebody else's silver, one boot still on the ladder, meeting the viewer's eye with a shrug, sly, caught in the act, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — CREATURES · SOLDIER  (2)

**`assets/creatures/glass_knight.png`** — serves 1 card: The Bravo

```
a lean duellist in a fine ruined doublet, sword already extended and shield splintering off his arm in the same instant, grinning at his own bad luck, unhelmed, weary human face, gallows humour, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/torchbearer.png`** — serves 2 cards: Wall Tender, Torchbearer

```
a young levy soldier holding a guttering pitch torch high to light the line beside him, face lit orange from below, jaw set, too big a coat and a strap mended with cord, glancing sideways at the man he is lighting for, unhelmed, weary human face, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — CREATURES · BASTION  (2)

**`assets/creatures/stone_sentinel.png`** — serves 1 card: Cornerstone

```
a colossal cornerstone block of a wall-golem hunkered down at a corner of the works, arms folded over the parapet, one small pikeman leaning on its knee eating bread for scale, immense and deadpan, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/the_leveler.png`** — serves 1 card: The Leveler

```
an enormous siege ram-golem shoving an entire enemy line backwards with one flat hand, expressionless, a crewman clinging to its shoulder harness for scale, immense and deadpan, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — CREATURES · BEAST+STRAY  (1)

**`assets/creatures/mule.png`** — serves 3 cards: Mule, The Pay-Wagon, Scapegoat

```
a stubborn army mule loaded far past sense with strongboxes, kettles and rolled banners, planted with all four feet, giving the viewer a flat unimpressed stare, endearing and clearly dangerous, expressive animal eyes, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — SPELLS  (31)

**`assets/spells/ambush.png`** — serves 3 cards: Ambush, Wolf-Pits, Salted Ground

```
a levy scout dropping into a concealed pit of sharpened stakes, arms flung up, the brush lid still swinging away above him, two more pits just visible in the grass beyond, the quarter-second before he knows how bad it is, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/banish.png`** — serves 2 cards: Banish, Death Sentence

```
an enemy soldier being erased mid-stride, his trailing leg and pack already gone to nothing, his face only now registering it, the men either side of him not yet turning, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/concentrate.png`** — serves 1 card: Burn Through

```
a gunner sighting down a long barrel and burning a hole clean through a shield, the wood charring outward in a ring, a second man behind it beginning to flinch, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/craven.png`** — serves 1 card: Faint Heart

```
a soldier who has stopped, weapon lowered, staring at nothing while the line moves past him on both sides, one hand loose at his side, faint heart, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/curse.png`** — serves 1 card: Curse

```
a soldier's own hand nailed to a written charge-sheet on a post, the paper stamped and sealed, his face turned away, a thing that cannot be undone, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/dark_pact.png`** — serves 1 card: Thin the Ranks

```
an officer thinning his own ranks, gripping one levy by the shoulder and pushing him out of the line while the men either side straighten and grow taller, two people and one bad decision between them, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/earthquake.png`** — serves 1 card: Earthquake

```
both battle lines thrown off their feet as the ground splits between them, men falling backwards in either direction, a spear dropping through the crack, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/echo_spell.png`** — serves 1 card: Echo

```
a soldier flinching from a blow that has already landed once, the same wound opening a second time on the same shoulder, his face caught between the two, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/frost_bolt.png`** — serves 1 card: Stopped Cold

```
an enemy pikeman stopped cold mid-charge, rimed white from boots to gorget, one arm still raised, breath frozen in front of his open mouth, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/fuel_the_pyre.png`** — serves 2 cards: The Last Due, Fuel the Pyre

```
two soldiers heaving a dead comrade onto a field pyre built from a broken cart, one of them losing his grip on the boots and the other giving him a look, the fire small and orange and just catching, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/grave_debt.png`** — serves 1 card: Grave-Debt

```
a debtor's coffin sealed with a heavy iron chain and a blood-red wax debt-seal, a clerk's hand pressing the seal down, spilled coins already turning to grave dirt, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/grave_robbery.png`** — serves 2 cards: Read the Will, Grave Robbery

```
a soldier hauling a body up out of a shallow grave by the wrists, boots braced on the lip, another man holding the lantern and looking anywhere else, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/hex.png`** — serves 2 cards: Witchbrand, Hex

```
an enemy soldier bringing his shield up and the shield coming up empty, the arm doing the whole motion while the straps close on nothing, his mouth open on the start of a word, his outline one shade less certain than the mud behind him, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/hoarfrost.png`** — serves 1 card: Hoarfrost

```
a soldier braced behind a shield rimed thick with hoarfrost, ice sheeting off the boss where a blow just struck it, the enemy opposite frozen mid-swing, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/lightning.png`** — serves 1 card: Sling Stone

```
a sling stone leaving the pouch at full whip, blurred with speed, and across the frame an enemy already snapping his head sideways from the hit, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/lost_tome.png`** — serves 3 cards: Watch Glass, Torn Pages, The Long Roll

```
a soldier holding a cracked watch-glass up to the light and reading something in it he did not want to know, torn pages pinned under his elbow, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/mass_grave.png`** — serves 1 card: Mass Grave

```
a long trench grave being filled in, a line of soldiers passing shovels down it, the count of the dead chalked on a board propped at the near end, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/plague_bell.png`** — serves 2 cards: Grave Bell, Plague Bell

```
a great cracked bronze plague bell being rung on a cart in a plague-struck war camp, the ringer hauling the rope with his whole weight, rows of shrouded bodies laid out behind him, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/quick_shot.png`** — serves 1 card: Quick Shot

```
a crossbowman already lowering the bow, bolt gone, watching down-range with his jaw set, and at the frame's far edge an enemy going down, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/reanimate.png`** — serves 2 cards: Press the Dead, Raise the Fallen

```
a dead enemy soldier getting back up wearing your colours, sash newly knotted over the wound that killed him, blinking, while a sergeant looks him over and shrugs, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/recycle.png`** — serves 1 card: Salvage

```
a quartermaster breaking up a smashed wagon for parts across a trestle, handing good timber back over his shoulder to a soldier who is already carrying too much, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/reposition.png`** — serves 3 cards: Repeating Arbalest, Ballista Bolt, Flanking Order

```
a sergeant hauling one of his own men bodily across the line into a better lane, boots skidding in the mud, both of them shouting at once, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/ricochet.png`** — serves 1 card: Crossfire

```
a sling stone glancing off a helmet and away into a second man behind him, both heads snapping in the same direction, the first not yet realising he is unhurt, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/second_wind.png`** — serves 1 card: Scatter the Line

```
an enemy line scattering outward from the centre, men shoved toward both edges of the field, one crashing hard into the flank of another, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/shield_wall.png`** — serves 2 cards: Tower Shield, Lock Shields

```
a front rank locking shields in one motion, the boards coming together edge to edge with a visible jolt, faces set behind the rim, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/soul_swap.png`** — serves 2 cards: Soul Swap, Crossed Orders

```
two enemy soldiers stumbling as they are made to trade places mid-line, each looking at the other in disbelief, their kit already swapped, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/time_snare.png`** — serves 1 card: The Doubled Hour

```
a soldier striking the same blow twice in the same instant, two overlapping arms and one victim taking both, the doubled hour, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/turbo.png`** — serves 2 cards: Touchpaper, Frenzy

```
a soldier holding a lit touchpaper to a comrade's powder charge and both of them grinning at what is about to happen, faces lit orange, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/venom_tip.png`** — serves 2 cards: Hooked Pike, Venom Tip

```
a soldier drawing a blade slowly through a shallow pot of something dark and thick, watching it coat the edge, entirely businesslike, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/e_golem.png`** — serves 1 card: Ruin Guard

```
a squat armoured ruin-guard planted in a breach, shield braced, taking a blow it saw coming and not moving an inch, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/e_wind_harpy.png`** — serves 1 card: Storm Owl

```
a storm owl coming in out of the dark ahead of everything else, wings wide, already past the line before anyone has turned, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — RELIC ICONS  (55)

**`assets/icons/relics/acolytes_tome.png`**

```
a thick clasped acolyte's tome lying open, one page half torn out and curling to ash at the edge, a fresh page turning by itself beneath it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/banner_of_unity.png`**

```
three small campaign banners lashed to one shared crosspole, their cords knotted together in the centre so none can fall alone, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/blacksmiths_hammer.png`**

```
a heavy smith's cross-pein hammer resting head-down on a scarred anvil face, sparks still dying on the metal beneath it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/bone_ring.png`**

```
a plain finger-ring carved from a knuckle bone, resting on a folded death-roll, hairline cracks running through it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/briar_amulet.png`**

```
an iron man-trap sprung shut on a bed of dead briars, its teeth locked, a torn scrap of cloth still caught in the jaws, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/busted_crown.png`**

```
a tarnished iron circlet with two points snapped off, sitting crooked on a stack of unread muster papers, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/calling_bell.png`**

```
a heavy black hand-bell with a knotted rope, three curse-marks branded into its shoulder, mid-swing and sounding, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/coffee_dripper.png`**

```
a coarse woven hairshirt hung on a nail, the weave visibly harsh, a knotted cord belt beneath it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/coin_landed.png`**

```
a single worn pay-token coin come to rest flat in bloodied mud, crowned profile up, the ground churned around it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/conscription_relic.png`**

```
a nailed-up conscription notice thick with wax seals and inked names, a quill and a press-gang's cudgel laid across it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/doom_herald.png`**

```
a herald's blackened trumpet with a short lit fuse threaded through the bell, the cord already half burnt, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/drovers_whip.png`**

```
a coiled leather drover's whip with a worn bone handle, laid across a wagon board, its lash still moving, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/echo_staff.png`**

```
a knotted wooden staff standing upright, its own shadow cast twice on the wall behind it at slightly different angles, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/ectoplasm.png`**

```
an empty wooden begging bowl turned upside down on a bare board, a single coin left untouched beside it, a vow of poverty, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/fusion_hammer.png`**

```
a heavy iron anvil with a deep crack split clean across its face, cold and unused, the forge behind it gone dark, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/gamblers_coin.png`**

```
a worn coin caught spinning on its edge on a plank table, half heads and half tails in the blur, a soldier's hand withdrawn, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/glowing_hand.png`**

```
a bare hand held open with a growing ember-light kindling in the palm, brighter at the fingertips than the centre, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/gravewardens_pact.png`**

```
a signed and sealed grave-warden's pact pinned to a shovel blade driven into turned earth, three small handprints in the mud below it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/happy_flower.png`**

```
a small posy of dried wildflowers tied with a saint's ribbon, laid on a folded soldier's coat, one bloom still holding colour, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/hexagonal_shield.png`**

```
a hexagonal iron pavise shield with three crossbow bolts driven into it and stopped, one still quivering, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/junk_slot.png`**

```
a wide empty stretch of churned battlefield ground at dusk, one broken spear standing upright as a marker, deep cart ruts running away into mist, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/lantern.png`**

```
a soldier's dispatch satchel spilling half-burnt orders, the edges charred, one page still legible and lifting on the heat, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/last_breath.png`**

```
a single spent candle stub guttering on a windowsill, the wick going over, one last curl of smoke, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/lean_mean.png`**

```
a lean company's cook-pot scraped clean and turned over on a cold fire, one spoon left across it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/lichs_bargain.png`**

```
a bargain written in two hands on a single sheet, a bloody thumbprint at the foot of it, a bone stylus laid across the page, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/linked_banner.png`**

```
two campaign banners with their poles chained together at the base, standing braced against each other in the wind, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/mana_drunkard.png`**

```
a pair of marching boots with the soles worn clean through, still laced, road dust to the knee, set down mid-stride, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/mana_pearl.png`**

```
a slim knife slid up a coat sleeve, only the grip showing past the cuff, a hand holding the sleeve closed over it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/mana_tide.png`**

```
a strapped iron war chest standing open, coin and paid warrants heaped inside, a quartermaster's tally-stick across the lid, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/mark_of_pain.png`**

```
a brand burned into the back of a hand, still raw, a cursed sigil, the branding iron cooling beside it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/mime.png`**

```
a painted mummer's half-mask of cracked leather, smiling on one side and blank on the other, hung on a tent cord, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/mimic_ring.png`**

```
a plain iron ring on a board that is casting the wrong shadow, the shadow of a different ring entirely, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/pen_nib.png`**

```
a heavy brass pen nib driven point-first into a signed muster roll like a dagger, ink pooling under it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/phantom_veil.png`**

```
a torn grey funeral veil caught on a spear point, hanging almost weightless, the shape of a face still held in the cloth, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/piercing_crown.png`**

```
a fistful of narrow bodkin arrowheads bundled with cord, their points needle-fine, one already bent from use, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/reapers_scythe.png`**

```
a worn field scythe leaning against a stook of cut grain, its edge freshly whetted and catching the last light, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/recruiters_horn.png`**

```
a recruiter's brass horn with three notches cut into the rim, resting on a rolled enlistment list, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/resonance_crystal.png`**

```
a struck tuning-crystal of smoky amber on a stand, ringing visibly, fine dust jumping on the board around it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/runebound_idol.png`**

```
a squat stone idol bound in cord and inked with fresh runes, one rune still wet where it was just added, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/runic_pyramid.png`**

```
a small stone pyramid paperweight holding a hand of dealt cards flat on a table so they cannot be swept away, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/scavengers_pouch.png`**

```
a trader's brass marker stamped with a sutler's sigil, tied to a heavy coin pouch, both laid on a ledger, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/sentinel_pact.png`**

```
a sworn pact stone set upright in an empty guard post, the ground around it worn by boots that are no longer there, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/snecko_eye.png`**

```
a great slit-pupilled basilisk eye set in a bronze mount, its pupil visibly widening, six cards fanned beneath it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/soul_lantern.png`**

```
a pierced-tin grave lantern with a small pale flame standing up straight inside it, casting a figure-shaped shadow, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/sozu.png`**

```
an upturned drinking horn with its stopper driven home and bound with cord, a temperance vow, no drop spilled, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/stardust_vial.png`**

```
a stoppered glass vial of fine glittering road-dust held up against firelight, the grains catching like sparks, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/steady_banner.png`**

```
a plain campaign banner on a deep-set pole, its cloth heavy and still, sandbags packed hard around the base, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/stygian_soul.png`**

```
a ferryman's toll coin resting on a closed eyelid, black water beading on the skin around it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/swift_boots.png`**

```
a pair of light travel-worn riding boots, mud-caked and road-scuffed, one fallen on its side as if kicked off in a hurry, a spur still buckled to the heel, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/thiefs_gloves.png`**

```
a pair of worn soft leather thief's gloves, fingertips cut away, laid crossed on a dark table beside a picked lock and a few loose coins, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/vanguards_cry.png`**

```
a vanguard's dented war-horn still at a shout's angle, breath-fogged at the mouthpiece, a torn pennant knotted to it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/velvet_choker.png`**

```
a penitent's iron collar, hinged open on a stone bench, its inner face worn smooth by a neck, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/war_drum.png`**

```
a battered side drum on its sling, both sticks fallen across the head, the skin still visibly trembling, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/warlords_standard.png`**

```
a warlord's heavy standard driven butt-first into a scorched field, its cloth stiff with old smoke, ranks of pike-shadows behind it, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/relics/warm_knucklebone.png`**

```
a single yellowed knucklebone die resting in a bare palm, worn smooth and warm from handling, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — EVENTS  (17)

**`assets/events/beekeeper.png`**

```
an old army beekeeper working smoking skeps at the roadside at dusk, veil pushed back off a weathered face, bees thick in the warm air, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/blood_fountain.png`**

```
a cracked stone fountain ring in a ruined square running dark red, a soldier crouched at the rim with a cupped hand, torchlight, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/butcher.png`**

```
an army butcher at a hanging rack under a canvas awning, cleaver mid-stroke, carcasses swinging, lit by one hot lamp, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/coin_on_edge.png`**

```
a silver coin spinning upright on its edge in the packed dirt of the road, soldiers' boots halted in a ring around it, low warm evening light raking across the ground, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/dark_altar.png`**

```
a rough stone altar in a cave mouth, dark stains worn into the channel, guttering candles set along the edge, one kneeling figure, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/fork_in_the_long_road.png`**

```
a fork in a rutted campaign road under a heavy sky, a leaning waymarker cross hung with rags, deep cart tracks going both ways, strong warm tonal contrast, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/glass_familiar.png`**

```
a small glass-bodied familiar animal sitting on a windowsill in a ruined cell, firelight refracting through it onto the wall, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/gravesong_choir.png`**

```
four hooded singers standing around an open grave in a field at dusk, mouths open on the same note, lantern light under their chins, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/hermit.png`**

```
a hermit's wagon parked off the road with a small fire outside it, pots hung from the axle, one figure seated with a blanket over his shoulders, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/hollow_lantern.png`**

```
a great iron carrying-lantern with a hollow skull for its housing, hung from a bent pole at a crossroads, a warm flame burning steadily inside the eye sockets, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/mirror_twin.png`**

```
a soldier standing at the edge of a still black pool at night, and his reflection standing at a slightly different angle, torch in the wrong hand, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/sin_eater.png`**

```
a hooded sin-eater eating funeral bread from a plate laid on a shrouded body in a crypt, candles set around the bier, chewing slowly, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/the_answering_well.png`**

```
a stone well in a dead orchard with a warm light rising out of the shaft, a soldier leaning over the lip listening, rope and bucket abandoned, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/the_chrysalis.png`**

```
large pale cocoons hanging thick from the rafters of an abandoned barn, one split open and empty, warm light coming through the boards, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/the_siege_kitchen-character-stage-v2.png`**

```
an abandoned field kitchen still working, cooks stirring vast iron cauldrons over trench fires, ladles and trestles, soldiers queueing out of frame, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/the_weeping_orchard.png`**

```
an orchard of bare black trees running with sap like tears, warm lantern light below, fallen fruit rotting in the grass, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/events/thrice_blessed_spring.png`**

```
a low stone spring-head in a hollow, water welling up clear and warm-lit, three faded blessing ribbons tied to the rock above it, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — PORTRAITS  (14)

**`assets/portraits/boss_act2.png`**

```
a gaunt crowned skeletal king enthroned in a hollow ruined hall, tattered royal robes, ember-gold eyes in the sockets, a broken sceptre across his knees, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/boss_collector.png`**

```
a towering hooded collector-lord, a void where its face should be, lit by dozens of stolen soul-lanterns hung from its cloak, reaching out one long hand, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/boss_demon_vanguard.png`**

```
a horned vanguard champion in scorched black plate filling the frame, a great notched blade held point-down, molten cracks across the breastplate, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/boss_hollow_king.png`**

```
a hollow crowned king slumped forward on a throne of stacked shields, crown fused to bare bone, one gauntlet hanging open, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/boss_iron_warden.png`**

```
an iron warden in siege plate blocking a breach, visor down, a red hand-mark struck across the chest, tower shield braced, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/boss_rival_pyromancer.png`**

```
a rival pyromancer warlord filling the frame, black-scorched armour and a burning mane of fire, casting a gout of flame toward the viewer, molten cracks across the breastplate, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/enemy_commander.png`**

```
a grim enemy field commander seen close and frontal, dented dark plate over a red-brown campaign cloak, visor raised on a hard weathered face, a marshal's baton held across the chest, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_portrait_acolyte.png`**

```
a hooded death-priest hero, censer smoke curling around a calm lined face, one hand raised in a blessing over the fallen, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_portrait_kindler.png`**

```
a kindler hero cupping a small living flame in both bare hands, face lit warm from below, soot-marked and steady, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_portrait_pyromancer.png`**

```
a hooded pyromancer hero, hood back and face lit hard from below by the fire cupped in one hand, soot-marked cheekbones, a burn-scarred jaw, weathered adult features, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_portrait_stalwart.png`**

```
a stalwart hero in dented campaign plate, shield up and set, unhelmed, a broad weathered face with a broken nose, jaw set, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_silhouette_raider.png`**

```
a lone raider hero seated at a night campfire, cloak drawn round, blade across the knees, warm firelight and deep shadow, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_silhouette_stalwart.png`**

```
a lone stalwart hero seated at a night campfire, shield propped beside him, helm off on the ground, warm firelight and deep shadow, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/portraits/hero_silhouette_kindler.png`**

```
a lone kindler hero seated at a night campfire cupping a small flame in both hands, warm firelight on a weathered face, deep shadow behind, dark-fantasy character portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light --ar 3:4 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — POTIONS, HUD & STAT GLYPHS  (8)

**`assets/icons/potions/aegis_brew.png`**

```
a stout corked flask of thick amber glass with a small iron shield-boss set into the stopper, warm firelit sheen on the shoulder of the bottle, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/potions/chain_flask.png`**

```
a squat bottle wrapped in fine iron chain, the links warm with reflected forge-light, cork driven home, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/potions/insight_tonic.png`**

```
a slim bottle of dark amber tonic with a single bright ember suspended still in the middle of the liquid, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/potions/mana_surge.png`**

```
a heavy bottle of deep gold liquid boiling hard against the glass, warm light spilling from the neck, cork straining, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/map/hud_heart_painted.png`**

```
a hand-painted anatomical war-heart of deep crimson bound in a small gilt filigree cage, one bold clean silhouette, warm firelit sheen on the upper curve, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/map/hud_potion_painted.png`**

```
a single stubby corked campaign flask of thick green-brown glass, one bold clean silhouette, a leather cord at the neck, warm firelit sheen, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/map/hud_relic.png`**

```
a heavy campaign signet on a worn leather thong, one bold clean silhouette, warm gold catching a low light, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/icons/stats/cost_runestone.png`**

```
a carved campaign command-stone, a worn river pebble incised with a single rune of muster, warm ember light standing in the cut groove, stylized hand-painted fantasy game icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH — BACKGROUNDS  (3)

**`assets/backgrounds/combat_arena_act2.png`**

```
a high mountain pass battlefield at dusk, broken standing stones and scree, warm ochre rock and deep umber shadow, ember light along the ridgeline, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/backgrounds/rest_campfire_act2.png`**

```
a night camp pitched among mountain rocks, one good fire, tents and stacked arms, warm firelight pooling on stone, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/backgrounds/rest_campfire_act3.png`**

```
a night camp inside a burnt ruin, fire built in a broken doorway, tents against fallen columns, warm firelight on scorched masonry, grim-storybook dark-fantasy scene on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
