# Batch 1 runner — the 13 must-fix images (paste top to bottom)

Turnkey companion to `MIDJOURNEY_ART_OVERHAUL_20260722.md`. These are the loudest style
breaks (pixel-art, photoreal, duplicates, worst cyan). Do them first.

## Step 0 — lock the look (`--sref`)
Pick ONE of these two anchors so the whole batch coheres:

- **Recommended — anchor to art you already shipped:** upload one of your best warm cards to
  Midjourney and use its image URL as the anchor: `riteforge.png`, `whisper_king.png`,
  `sentinel.png`, or `stalwarts_anvil.png`. New art will match the pieces already in the game.
- **Or** generate the Warden‑Sergeant prompt (in the main doc) fresh, upscale your favorite, and
  use *its* URL.

Get the anchor's image URL, then in every prompt below **replace `__ANCHOR__`** with that URL.
(`--sw 100` is the style weight; lower it toward 60 if the anchor overpowers the subject.)

> Save each result at the path in its heading, then run a headless `--import`. PNG auto-wins.

---

### 1 — `assets/spells/plague_bell.png`  *(kills the mass_grave duplicate)*
```
a great cracked bronze plague-bell tolling in a plague-struck war camp, sickly pale-green miasma pouring from its mouth over rows of shrouded bodies, a lone bell-ringer silhouette, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia palette with a sickly green accent --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 2 — `assets/spells/grave_debt.png`  *(kills the pixel-art frame)*
```
a debtor's coffin sealed with a heavy iron chain and a blood-red wax debt-seal, spilled coins turning to grave-dirt, a ghostly ledger hand reaching from the lid, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, pixel art, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 3 — `assets/creatures/kindling_alt.png`  *(stop being a copy of kindling)*
```
a mischievous little ember-sprite curled asleep inside a heap of glowing coals, one eye cracking open, warm sparks drifting up into a dark woodland, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 4 — `assets/icons/map/hud_heart_painted.png`  *(kills the emoji heart)*
```
a hand-painted anatomical war-heart of deep crimson wrapped in a little gold filigree cage, warm firelit sheen, stylized fantasy game icon, Darkest Dungeon and Slay the Spire style, bold brushstrokes, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop --ar 1:1 --v 8.1 --s 400 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 5 — `assets/creatures/vengeful_spirit.png`  *(HIGH IMPACT — 3 other cards borrow it)*
```
a wrathful gaunt war-ghost rising from a battlefield, tattered grave-shroud and trailing spectral chains, a face twisted with rage, pale ember-gold fury gathering around it, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with pale ember-gold spectral light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 6 — `assets/creatures/e_golem.png`
```
a massive rubble-and-iron war golem lit by ember cracks between its stones, dull amber eyes, standing in a ruined keep, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember-orange rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 7 — `assets/creatures/leyline_conduit.png`
```
a robed leyline-tender kneeling to tap a vein of glowing ember-orange crystal erupting from cracked earth, warm arcane light on their face, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with amber crystal glow, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 8 — `assets/creatures/mana_sprite.png`
```
a tiny glowing ember-moth fey with translucent wings trailing warm sparks, hovering over a dark forest floor, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with ember-gold glow, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 9 — `assets/creatures/the_black_tide.png`
```
a monstrous drowned kraken heaving up out of a black war-harbor at night, barnacled tentacles wrapping a sinking galley, lit by burning ship-fires, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single dominant subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette against deep shadow, atmospheric backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 10 — `assets/creatures/torchbearer.png`  *(kills the chibi cartoon)*
```
a young levy torchbearer holding a guttering pitch-torch high, wide frightened eyes lit orange, mud-caked cloak, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, chibi, cartoon, photograph, 3d render, cgi, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### 11 — `assets/portraits/boss_rival_pyromancer.png`  *(make it an actual boss)*
```
an imposing rival pyromancer warlord filling the frame, black-scorched armor and a burning mane of fire, molten cracks across the breastplate, casting a gout of flame toward the viewer, dark-fantasy boss portrait, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia and ember palette with ember rim light, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### 12 — `assets/portraits/boss_hollow_king.png`
```
a gaunt crowned skeletal king enthroned in a hollow ruined hall, tattered royal robes, ember-gold eyes in the sockets, a broken scepter, dark-fantasy boss portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### 13 — `assets/portraits/boss_collector.png`
```
a towering hooded collector-lord, a void where its face should be lit by dozens of stolen soul-lanterns hung from its cloak, reaching out one long hand, dark-fantasy boss portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa, dramatic firelit chiaroscuro, warm muted sepia palette with warm amber soul-lantern glow, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

---
When these 13 land, the two biggest eyesores (the pixel-art/photoreal breaks and the worst
cyan) are gone. Next batches, in order: the Tier‑2 tribe sets (60 cards), then the relic
REPLACE clusters, then events — all in the main overhaul doc.
