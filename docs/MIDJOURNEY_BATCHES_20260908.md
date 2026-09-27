# MIDJOURNEY — COPY-PASTE BATCHES (2026-09-08)

Every card below was **re-verified at full resolution against its own rules text** before being
listed. §5 records the nine candidates that were **dropped** because replacing them would have
made the game worse — read that section, it is the point of this pass.

**16 images across 4 batches.** Each batch is one `--sref` sitting.

---

## 0. Do this once, before any batch

**Pin the anchor.** Every prompt below ends `--sref YOURCODE --sw 100`. That placeholder appears
26 times across this repo's docs and **has never once been replaced with a real code** — it is the
root cause of the 103 off-palette assets.

Run these four with **no** sref, pick the one whose light and finish you want to live with, then
use *its* code in every prompt below:

```
a grizzled line-sergeant roaring an order from behind a shield wall, dented plate, mud to the knee, one bare hand raised, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light --ar 8:5 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

```
a scarred camp dog mid-lunge out of the dark, teeth bared, firelight raking its flank, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light --ar 8:5 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

```
a battered iron anvil on a scorched stump, warm forge-light pooling on its horn, a single ember drifting up, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

```
a soldier flinching as an unseen blow lands, head turned away, the moment before he knows how bad it is, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light --ar 8:5 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

Then record the code in `tools/golden/art_style.json` **together with `--v 8.1`** — the sref and
the model version are one unit, and changing either starts a new set.

**Why `--ar 8:5` for cards and not 3:2:** the hand-card art aperture is **203×127 px** (measured,
`Card2D.gd:2673-2683`) = 1.598. A 3:2 master gets ~6% cropped off top and bottom under
`STRETCH_KEEP_ASPECT_COVERED`. 8:5 is 1.60 — **zero crop.** Icons stay `--ar 1:1`.

---

## BATCH A — the six armaments · `--ar 8:5` → `assets/spells/<id>.png`

**This batch overwrites nothing.** All six armaments currently borrow a *spell's action painting*
(`tower_shield` → `shield_wall`, `forked_spear` → `cataclysm`…), and none of the six files exists
yet. The loader tries the direct file **before** the alias (`CardArtAliases.gd:798-828`), so
dropping these in makes them win automatically — the spells keep their paintings. **Zero risk,
six cards fixed. Start here.**

The house rule for an armament: **the object, held, by a hand in frame** — it is a thing you are
given, not an action.

**`hooked_pike`** — *Hooked Pike · 1c · Bearer gets +3 ATK and Piercing*
```
a long infantry pike with a cruel iron side-hook below the point, held upright in a mailed fist, the hook notched and bright where it has been used, dark-fantasy war-gear held by its bearer, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`tower_shield`** — *Tower Shield · 1c · Bearer gets +5 HP and Armored*
```
a tall curved wooden tower shield planted in mud, a soldier's arm through the straps behind it, its face splintered and scarred with old impacts and repainted once already, dark-fantasy war-gear held by its bearer, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`forked_spear`** — *Forked Spear · 2c · Bearer also strikes adjacent enemies*
```
a heavy two-tined forked war spear held level across the frame, both prongs bloodied, a soldier's gloved hands gripping the haft wide apart, dark-fantasy war-gear held by its bearer, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`repeating_arbalest`** — *Repeating Arbalest · 2c · Bearer gains Last Stand and attacks twice*
```
a heavy repeating crossbow with a wooden magazine box above the stock and a crank windlass hanging from it, held braced against a soldier's hip, one bolt already seated, dark-fantasy war-gear held by its bearer, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`grave_bell`** — *Grave Bell · 1c · Bearer's On-Death effects trigger twice*
```
a small tarnished bronze grave bell on a leather cord, held out at arm's length in a bare hand, its clapper caught mid-swing so it is sounding a second time, dark-fantasy war-gear held by its bearer, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`witchbrand`** — *Witchbrand · 1c · After you cast a spell, bearer gets +1/+1 this fight*
```
a long iron branding iron with a crooked hex-mark head glowing dull orange from the coals, held up in a gloved fist, faint smoke coming off it, dark-fantasy war-gear held by its bearer, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH B — four relic icons · `--ar 1:1` → `assets/icons/relics/<id>.png`

All four are genuine subject failures **verified at full resolution.** Note two of the ids are
Slay-the-Spire leftovers and the **card name is the real subject** — draw the name, not the id.

**`thiefs_gloves`** — *Thief's Gloves* — currently **a pink floral folding fan.**
```
a pair of worn soft leather thief's gloves, fingertips cut away, laid crossed on a dark table beside a picked lock and a few loose coins, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, pink, fan, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`swift_boots`** — *Swift Boots · Swift creatures +1 ATK* — currently **a flame on a teal panel, no boots.**
```
a pair of light travel-worn riding boots, mud-caked and road-scuffed, one fallen on its side as if kicked off in a hurry, a spur still buckled to the heel, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`fusion_hammer`** — the card is **"CRACKED ANVIL"** *(+1 max Command · cannot forge at rest)* — currently **a gold cube.**
```
a heavy iron anvil with a deep crack running through its face, split clean across the horn, cold and unused with the forge behind it gone dark, one dead ember on the stump beneath, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centred, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, gold cube, gemstone, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`junk_slot`** — the card is **"OPEN GROUND"** *(4+ empty slots → +1 max Command)*.
**Correction: the subject is already right** — it *is* an empty field. It fails on craft: washed
out, no focal point, reads unfinished. Keep the idea, give it a subject to look at.
```
a wide empty stretch of churned battlefield ground at dusk, a single broken spear standing upright in the mud as a marker, deep cart ruts running away into mist, nobody there, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable focal point, bold visible brushstrokes, painterly illustration, strong tonal contrast, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, washed out, low contrast, foggy, empty sky, photograph, 3d render, cgi, realistic, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH C — five card paintings · `--ar 8:5` → overwrite the named file

**These five overwrite live art — run `tools/art_compare.py` before committing each one.**
Each note says how many cards the file serves, because the new painting must suit all of them.

**`assets/creatures/gravedigger.png`** — **serves 5 Dead cards** (Gravedigger, Ash Marker, Burial
Goods, Grave-Goods, Body-Snatcher). Currently a **cartoon garden gnome with a pointy hat.** Register
is *melancholy-comic* — funny about mortality, never horror, and never whimsy.
```
a stooped old army gravedigger resting on his spade at the edge of a fresh trench grave, caught mid-sentence talking to the dead man he is burying, a lantern hooked on the spade handle, grave-goods laid out on the turned earth beside him, his coat two sizes too big, grim-storybook dark-fantasy character, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, gnome, pointy hat, cute, chibi, whimsical, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/plague_bell.png`** — serves *Plague Bell* + the `grave_bell` armament until Batch A
lands. Currently **a purple cave with hands, no bell**, and pixel-identical to `mass_grave.png`.
```
a great cracked bronze plague bell being rung on a cart in a plague-struck war camp, the ringer hauling the rope with his weight, rows of shrouded bodies laid out behind him, dust shaken off the bell mouth, dark-fantasy spell effect with a body in the frame, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, close cropped composition filling the frame, dramatic firelit chiaroscuro with one bright accent, warm muted sepia and ember-orange palette --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, purple, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/torchbearer.png`** — **serves 2 Soldiers** (Torchbearer 0/3 *adjacent +1 ATK*;
Wall Tender 1/3 *heal adjacent 2*). Currently a **chibi child with huge blank eyes.** Register is
*human, worn, fond* — and this is the warm baseline the whole tonal system is measured against.
```
a young levy soldier holding a guttering pitch torch high to light the line beside him, face lit orange from below, jaw set, too big a coat and a strap mended with cord, glancing sideways at the man he is lighting for, grim-storybook dark-fantasy character, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, chibi, big eyes, cute, child, anime, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/creatures/stray_cat.png`** — serves exactly one card: **`familiar` = "Camp Follower"**,
a **Stray**, 1c 1/2, *On-Enter: Discover a creature, it costs 1 less.* Currently a **smiling
cartoon kitten.** Register is *sly, caught, fourth-wall* — **keep the eye contact and the camp
setting, lose the Saturday-morning rendering.**
```
a lean scarred camp cat crouched on a broken wall above a war camp, a stolen strip of salt meat in its jaws, one ear torn and healed crooked, caught looking straight at the viewer completely unrepentant, laundry lines and tent poles behind it, grim-storybook dark-fantasy character, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, close cropped composition filling the frame, strong readable silhouette, dramatic firelit chiaroscuro with one bright accent, warm muted sepia ochre and umber palette with ember-orange rim light, mud and kit of the same war on everything --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, kitten, cute, cartoon, big eyes, smiling, standing still, neutral pose, symmetrical, centered portrait, empty background, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`assets/spells/fuel_the_pyre.png`** — **serves 2 spells** (Fuel the Pyre; The Last Due — both
*sacrifice a friendly*). Currently a **green flame column**, which contradicts the card's own name.
```
two soldiers heaving a dead comrade onto a field pyre built from a broken cart, one of them losing his grip on the boots and the other giving him a look, the fire small and orange and just catching, dusk, dark-fantasy spell effect with bodies in the frame, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, close cropped composition filling the frame, dramatic firelit chiaroscuro with one bright accent, warm muted sepia and ember-orange palette --ar 8:5 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, green fire, green flame, magenta, acid green, photograph, 3d render, cgi, hyperrealistic, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## BATCH D — one HUD glyph · `--ar 1:1` → `assets/icons/map/hud_heart_painted.png`

Only **one** of the three HUD icons I originally listed is actually live. This one is — it is the
primary in `GameTheme.gd:251` and is inlined into event body text as `Event.GLYPH_HP` at 20px.
It is currently **a literal red glossy emoji heart.**

Keep it a **single bold silhouette** — `hud_gold_coin.png` proves a painted object survives 20px
when the shape is one clean form.

```
a hand-painted anatomical war-heart of deep crimson bound in a small gilt filigree cage, one bold clean silhouette, warm firelit sheen on the upper curve, stylized fantasy game icon, Darkest Dungeon and Slay the Spire style, bold brushstrokes, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop --ar 1:1 --v 8.1 --s 400 --sref YOURCODE --sw 100 --no cyan, teal, neon, saturated blue, magenta, acid green, emoji, glossy, cartoon, vector, photograph, 3d render, cgi, realistic, flat black background, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

---

## 5. DROPPED after verification — do NOT replace these

This is the part that matters. Nine candidates from earlier drafts were checked against their
own card data and full-resolution art, and **replacing them would have been a mistake.**

| candidate | why it stays |
|---|---|
| **`ember_stalker.png`** | The card's *name* is **"Powder Cart" (0/4, Doom 3, on-death: damage all enemies)**. The art is a **burning wagon spilling fire** — that is exactly right. I flagged it as "a cart, not a stalker" by reading the **id** instead of the card. |
| **`the_black_tide.png`** | Not a card at all — `the_black_tide` is an **encounter** (`EncounterDB.gd:672`). The file serves no card in the pool. Verify what, if anything, uses it before spending a generation on it. |
| **`venom_tip.png`** | Green **is** the concept — the card grants **Poison**. Same exemption as `hoarfrost`: when the colour is the mechanic, it is not palette drift. |
| **`hud_gold.png`** | The dollar sign is a **dead fallback**. `hud_gold_coin.png` exists, so it never loads — and `GameTheme.gd:253-261` documents that this was already fixed deliberately ("ONE MINT EVERYWHERE"). |
| **`hud_potion.png`** | Also a **dead fallback**; the live file is `hud_potion_painted.png`. If you want the potion glyph improved, that is the file — and it is a lower-grade defect than the emoji heart. |
| **`shield_wall.png`** · **`reposition.png`** | Subjects are correct; the defect is a cyan cast. **Grade, don't regenerate** — a grade keeps the drawing. |
| **`lancer.png`** | Nearly deleted in an earlier pass as "a tree on a hillside." At full resolution it is **a mounted lancer at the couch** and one of the best paintings in the set. It is entry one on the keep-list. |
| **`kindling_alt.png`** | The **deliberate no-art placeholder** (`Card2D.gd:1063`), with a standing waiver at `art_lint.py:201`. Being a copy of `kindling.png` is its function. |

**The pattern in every one of these: I read the filename instead of the card.** Ids in this repo
carry Slay-the-Spire and legacy names that no longer match what the card does — `fusion_hammer` is
"Cracked Anvil", `junk_slot` is "Open Ground", `ember_stalker` is "Powder Cart". **Always open the
card data before briefing the art.**

---

## 6. After the files land

1. Save at the exact path given, then run a headless `--import`.
2. **`python tools/art_compare.py <old> <new>`** for every Batch C file — it renders both at the
   true 203×127 aperture with the board crop and scrim, and raises objections (`LOST CONTRAST`,
   `LOST TONAL RANGE`, `DARKENED`). It never says ship it; your eye decides.
3. `python tools/art_lint.py --baseline` — new offenders fail. **Note it cannot score a grade or a
   register**, only palette and duplication.
4. `python tools/_art_sweep_20260908.py` rebuilds the verdict table.
5. Append the **exact prompt that shipped each file** to `docs/ART_BRIEFS.md`. That is what makes a
   card re-generatable in eighteen months.
