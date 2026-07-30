# Batch 2 — Soldiers tribe + boss regrade to the ink/graphic house look

Companion to the overhaul doc. Two independent sub-batches. Same `--sref` rule as Batch 1:
**replace `__ANCHOR__`** with your anchor image's URL, `--sw 100` (lower toward 60 if it
overpowers the subject). Save each result at the path in its heading, then headless `--import`.

---

## PART A — Soldiers tribe (8 cards, currently borrowing art)

For tight tribe cohesion, use **one anchor for this whole part** — ideally generate #1
(Warden‑Sergeant) first, upscale your favorite, and use *its* URL as `__ANCHOR__` for #2–#8 so
the whole tribe looks like one unit. Aspect `3:2` for all (spell #8 included).

### A1 — `assets/creatures/warden_sergeant.png`  *(Soldier keystone — do first, becomes the tribe anchor)*
```
a grizzled line-sergeant roaring orders from behind a full shield-wall, baton raised, dented plate, mud and banners, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa with loose painterly brushwork, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember-orange rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A2 — `assets/creatures/levy_rider.png`  *(Outrider — starter)*
```
a light hooded outrider scout leaning low over a lean fast horse, spear couched, galloping ahead of the column through dawn mist, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A3 — `assets/creatures/man_at_arms.png`
```
a seasoned man-at-arms in dented plate advancing at a quick march, pike leveled, worn tabard, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A4 — `assets/creatures/last_levy.png`
```
a lone desperate conscript planting his spear as a wall of shadow-soldiers closes in, grim resolve on his face, torn levy coat, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A5 — `assets/creatures/pike_square.png`
```
a bristling square of leveled pikes seen head-on, a hedgehog of steel points and grim helmeted faces packed shoulder to shoulder, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A6 — `assets/creatures/standard_bearer.png`
```
a mud-caked soldier raising a tattered regimental standard high overhead in a rallying cry, banner snapping against a bruised sky, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A7 — `assets/creatures/bastion_lord.png`
```
a towering lord planted behind an immense tower-shield, striking back at unseen attackers, dented heraldic plate, immovable stance, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

### A8 — `assets/spells/mentioned_dispatches.png`  *(SPELL)*
```
a courier reading a battlefield dispatch aloud by lamplight as a nearby soldier lunges to strike on command, motion and urgency, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, cartoon, cel shaded, flat vector, text, watermark, signature, frame, border, ui, caption
```

---

## PART B — Boss regrade to the ink/graphic house look

Bring the 5 fine‑oil **amalgam** finale bosses + the **Crone** into the bold ink/graphic look so
the boss gallery reads as one game (per the art-direction verdict: strong linework carries the
read at any size; one dominant warm hue + complementary accents). Aspect `3:4`.

**Anchor for Part B:** use one of your strong *ink* bosses as `__ANCHOR__` — upload
`boss_act1.png` or `boss_demon_vanguard.png` and use its URL. These share the ink‑BOSS tail
(note the extra `--no soft-focus oil painting`, which is what pulls them off the museum‑oil look).

### B1 — `assets/portraits/boss_amalgam_raider.png`
```
a monstrous amalgam of the fallen Raider warlord, a towering hooded figure fused with the torn banners and bones of his slain host, ember-gold eyes, a great cleaver raised, dark-fantasy boss portrait, one imposing figure filling the frame with a strong bold silhouette, hand-inked graphic illustration in the Darkest Dungeon style of Chris Bourassa, heavy confident ink linework, woodcut-influenced high contrast, painterly shading, one dominant warm hue with ember and complementary accents, firelit chiaroscuro, warm sepia and ember palette --ar 3:4 --v 8.1 --s 450 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, soft-focus oil painting, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### B2 — `assets/portraits/boss_amalgam_stalwart.png`
```
a monstrous amalgam of the fallen Stalwart lord, a colossal armored knight grown into his own shield-wall, a skull-and-iron torso wraith, dark-fantasy boss portrait, one imposing figure filling the frame with a strong bold silhouette, hand-inked graphic illustration in the Darkest Dungeon style of Chris Bourassa, heavy confident ink linework, woodcut-influenced high contrast, painterly shading, one dominant warm hue with ember and complementary accents, firelit chiaroscuro, warm sepia and ember palette --ar 3:4 --v 8.1 --s 450 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, soft-focus oil painting, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### B3 — `assets/portraits/boss_amalgam_acolyte.png`  *(also fixes the tiny distant figure)*
```
a monstrous amalgam of the fallen Acolyte lord, a hooded death-priest fused with the risen dead, censer smoke curling, ember-gold eyes, looming close and filling the frame, dark-fantasy boss portrait, one imposing figure with a strong bold silhouette, hand-inked graphic illustration in the Darkest Dungeon style of Chris Bourassa, heavy confident ink linework, woodcut-influenced high contrast, painterly shading, one dominant warm hue with ember and complementary accents, firelit chiaroscuro, warm sepia and ember palette --ar 3:4 --v 8.1 --s 450 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, soft-focus oil painting, distant tiny figure, wide landscape, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### B4 — `assets/portraits/boss_amalgam_pyromancer.png`
```
a monstrous amalgam of the fallen Pyromancer lord, a burning sorcerer-king wreathed in living fire, molten cracks across his flesh, an arcane fire-ring behind his head, dark-fantasy boss portrait, one imposing figure filling the frame with a strong bold silhouette, hand-inked graphic illustration in the Darkest Dungeon style of Chris Bourassa, heavy confident ink linework, woodcut-influenced high contrast, painterly shading, one dominant warm hue with ember and complementary accents, firelit chiaroscuro, warm sepia and ember palette --ar 3:4 --v 8.1 --s 450 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, soft-focus oil painting, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### B5 — `assets/portraits/boss_amalgam_kindler.png`
```
a monstrous amalgam of the fallen Kindler lord, an enthroned king crowned in burning coals, embers pouring from his robes, dark-fantasy boss portrait, one imposing figure filling the frame with a strong bold silhouette, hand-inked graphic illustration in the Darkest Dungeon style of Chris Bourassa, heavy confident ink linework, woodcut-influenced high contrast, painterly shading, one dominant warm hue with ember and complementary accents, firelit chiaroscuro, warm sepia and ember palette --ar 3:4 --v 8.1 --s 450 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, soft-focus oil painting, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

### B6 — `assets/portraits/boss_the_crone.png`
```
a towering hooded witch-crone stirring a great cauldron of ember-light, gnarled hands, ragged shawl, glowing eyes beneath the hood, dark-fantasy boss portrait, one imposing figure filling the frame with a strong bold silhouette, hand-inked graphic illustration in the Darkest Dungeon style of Chris Bourassa, heavy confident ink linework, woodcut-influenced high contrast, painterly shading, one dominant warm hue with ember and complementary accents, firelit chiaroscuro, warm sepia and ember palette --ar 3:4 --v 8.1 --s 450 --sref __ANCHOR__ --sw 100 --no cyan, teal, neon, saturated blue, soft-focus oil painting, photograph, 3d render, cgi, cartoon, text, watermark, signature, frame, border, ui, caption
```

---
After Part B, the whole boss gallery (act bosses + named bosses + amalgams + Crone) reads as
one hand. Remaining tribes to run next, same pattern: **Bastions, Beasts, Dead, Warlocks, Strays**
— subjects are in the overhaul doc's Tier 2.
