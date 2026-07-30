# Burning Meadow — Art Audit & Midjourney Overhaul (2026‑07‑22)

An 8‑agent visual pass over **every** picture and symbol in the game, judged against the
game's current winning look. Below: what to replace and why, a tightened prompt
system for "the coolest feel," and **copy‑paste‑ready Midjourney prompts** (Midjourney
**v8.1**) for every replacement + every card that's currently borrowing someone else's art.

---

## TL;DR — the one finding that matters

The art is in far better shape than the old "placeholder" notes claim — most creatures,
spells, potions and portraits are genuinely on‑style. **The single pervasive defect is
saturated CYAN / TEAL**, which shows up in ~40 assets and is the only thing that reads as
"a different game" beside the warm sepia set. Kill the cyan and the library snaps together.

Second‑order issues: a few **exact duplicate files**, two **baked‑in decorative borders**,
one **pixel‑art** spell, a couple of **cartoon/asset‑store HUD icons** (the lemon coin with
the cyan diamond, the emoji heart), **~60 cards that render another card's painting** (no
bespoke art), and a **boss set split across two rendering styles** (ink‑comic vs fine‑oil).

---

## The style system ("the vibe"), tuned for v8.1

Keep the proven DNA — painterly **Slay the Spire / Darkest Dungeon**, warm **sepia + ember**,
warm painterly backdrop (never a black void), one bold readable subject. Two upgrades:

1. **Anchor to named painters** so a whole batch coheres and the quality ceiling rises
   (MJ best practice: lead with the subject, name the artist early, keep it under ~150 words).
   Anchor = **Chris Bourassa** (Darkest Dungeon art director) + **Craig Mullins** / **Piotr
   Jabłoński** loose painterly brush.
2. **Ban the cyan in the prompt itself.** Every tail below hard‑excludes `cyan, teal, neon,
   saturated blue` — this is the cheapest fix for the game's #1 defect. (Drop `saturated blue`
   from the `--no` list *only* for genuinely blue elements: frost, lightning, ice.)

### Cohesion workflow (do this or the set drifts)
Generate **one** hero image you love → copy its image URL / grab a **`--sref` code** →
append `--sref <code> --sw 100` to every other prompt in that batch. Keep `--v 8.1` and the
same `--s` across the batch. Fixed subject-first structure + one sref = a matched set.

### The five tails (paste after the subject line)

**CREATURE / ENEMY** — save as `assets/creatures/<id>.png` (3:2)
```
grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa with the loose painterly brushwork of Craig Mullins and Piotr Jablonski, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember-orange rim light, atmospheric warm-brown painterly backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**SPELL** — save as `assets/spells/<id>.png` (3:2)
```
dark-fantasy spell effect, a single clear iconic magical action, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, thick visible brushstrokes, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette, atmospheric warm-brown painterly backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**RELIC / POTION ICON** — save as `assets/icons/relics|potions/<id>.png` (1:1)
```
stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**PORTRAIT (hero / boss)** — save as `assets/portraits/<id>.png` (3:4)
```
dark-fantasy character portrait, single imposing figure filling the frame with a strong silhouette, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**EVENT / BACKGROUND SCENE** — save as `assets/events|backgrounds/<id>.png` (16:9)
```
grim-storybook dark-fantasy scene, an evocative cinematic moment on the war road, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette, atmospheric depth --ar 16:9 --v 8.1 --s 450 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

> Convention (unchanged): filename = card/relic/id. The PNG auto-wins over any `.svg`; drop it
> at the path, run a headless `--import`. No code change needed.

---

## TIER 1 — Worst offenders (fix these first)

These are the loudest style breaks and the broken/duplicate files. Each prompt below is the
**full string** — copy the whole block.

### Broken / duplicate / wrong-medium

**`plague_bell` (spell)** — currently a *pixel-identical copy* of `mass_grave` and shows no bell/plague. New art:
```
a great cracked bronze plague-bell tolling in a plague-struck war camp, sickly pale-green miasma pouring from its mouth over rows of shrouded bodies, a lone bell-ringer silhouette, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia palette with a sickly green accent --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`grave_debt` (spell)** — the only pixel-art frame in the game. New art:
```
a debtor's coffin sealed with a heavy iron chain and a blood-red wax debt-seal, spilled coins turning to grave-dirt, a ghostly ledger hand reaching from the lid, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`kindling_alt` (creature)** — byte-identical to `kindling`. It's used as an alt art, so give it a *different* pose instead of a copy:
```
a mischievous little ember-sprite curled asleep inside a heap of glowing coals, one eye cracking open, warm sparks drifting up into a dark woodland, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa with loose painterly brushwork, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

### Cartoon / cyan HUD & stat icons

- **`hud_gold_painted.png`** — lemon cartoon coin with a pure-cyan diamond. **No new art needed: it's redundant.** The correct aged coin (`hud_gold_coin.png`) is already live — just delete/stop shipping the painted one.
- **`hud_heart_painted.png`** — glossy emoji heart. Replace (1:1, RELIC/POTION tail):
```
a hand-painted anatomical war-heart of deep crimson wrapped in a little gold filigree cage, warm firelit sheen, stylized fantasy game icon, Darkest Dungeon and Slay the Spire style, bold brushstrokes, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
- **`atk_sword.png` / `cost_runestone.png`** — cool/cyan; retone to match the warm `hp_heart.png`. `atk_sword`:
```
a battle-worn broadsword blade catching warm forge-light, faint ember glow along the fuller, stylized fantasy game stat icon, Darkest Dungeon and Slay the Spire style, bold painterly brushstrokes, warm muted sepia and gilt palette, gentle amber rim glow, warm deep-brown painterly backdrop --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
`cost_runestone` (the "Command" resource stone):
```
a carved campaign command-stone, a worn river pebble incised with a single glowing rune of muster, warm ember light in the groove, stylized fantasy game stat icon, Darkest Dungeon and Slay the Spire style, bold painterly brushstrokes, warm muted sepia and gilt palette, gentle amber rim glow, warm deep-brown painterly backdrop --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

### Cyan-clash creatures (repaint or heavily re-tone)

**`vengeful_spirit` (HIGH IMPACT — revenant, vengeance & the_undying all borrow it)**:
```
a wrathful gaunt war-ghost rising from a battlefield, tattered grave-shroud and trailing spectral chains, a face twisted with rage, pale ember-gold fury gathering around it, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with pale ember-gold spectral light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`chorus_of_echoes`**:
```
a ghostly choir of overlapping translucent spirits singing in a ruined chapel, many mouths open, faint pale-gold sound-ripples in the air, candles guttering, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`copycat`** (a mimic that copies a keyword):
```
an unsettling shapeshifting mimic mid-copy, its clay-grey body half-molded into a stolen shape with a second face pushing through, warm candlelight raking across the wet surface, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`e_golem`** (neon cyan eyes, flat cel):
```
a massive rubble-and-iron war golem lit by ember cracks between its stones, dull amber eyes, standing in a ruined keep, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember-orange rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`leyline_conduit`** (saturated cyan crystals, no character — a Warlock caster):
```
a robed leyline-tender kneeling to tap a vein of glowing ember-orange crystal erupting from cracked earth, warm arcane light on their face, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with amber crystal glow, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`mana_sprite`** (cyan bug):
```
a tiny glowing ember-moth fey with translucent wings trailing warm sparks, hovering over a dark forest floor, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with ember-gold glow, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`the_black_tide`** (teal kraken vista — reframe as a subject):
```
a monstrous drowned kraken heaving up out of a black war-harbor at night, barnacled tentacles wrapping a sinking galley, lit by burning ship-fires, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single dominant subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette against deep shadow, atmospheric backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`raven`**:
```
a huge ragged war-raven perched on a broken helm atop a cairn, one eye catching firelight, feathers edged in warm rim light, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`torchbearer`** (chibi cartoon child — off style entirely):
```
a young levy torchbearer holding a guttering pitch-torch high, wide frightened eyes lit orange, mud-caked cloak, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, chibi, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

**`glass_knight`**, **`archmage`**, **`e_wind_harpy`**, **`vampire_lord`**, **`warden_of_graves`**, **`chaos_imp`**, **`crow_witch`**, **`gravedigger`**, **`harpy`**, **`doppelganger`**, **`necromancer`**, **`ironclad_veteran`**, **`ratling`** (cyan gem) — same treatment: keep the concept, re-tone to warm sepia/ember, drop the cyan. Use the **CREATURE tail** with a one-line subject; see the batch list in the Appendix.

### Off-vibe spells (repaint / re-tone)

- **`fuel_the_pyre`** — green fire for a *funeral pyre* is wrong. New art:
```
a soldier heaving a fallen comrade's body onto a roaring funeral pyre, sparks and warm orange flame swallowing the corpse, grim faces lit orange, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, green fire, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
- **`recycle`, `reposition`, `soul_swap`, `time_snare`, `shield_wall`, `ambush`, `banish`** — cyan-dominant. Re-tone to warm/ember (SPELL tail). `reposition` and `soul_swap` are also the *same* "two orbs" concept — differentiate them (reposition = two soldiers physically swapping lanes; soul_swap = two ghostly souls trading bodies).
- **`quick_shot`, `second_wind`** — all-green, no warmth; retone warm.
- **`mending_light`** — photoreal; repaint painterly (SPELL tail, holy-gold allowed).

### Portraits

**`boss_rival_pyromancer`** — currently a wide scene with a tiny figure; must be a single imposing boss:
```
an imposing rival pyromancer warlord filling the frame, black-scorched armor and a burning mane of fire, molten cracks across the breastplate, casting a gout of flame toward the viewer, dark-fantasy boss portrait, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa and Piotr Jablonski, dramatic firelit chiaroscuro, warm muted sepia and ember palette with ember rim light, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**`boss_hollow_king`** (cyan sky):
```
a gaunt crowned skeletal king enthroned in a hollow ruined hall, tattered royal robes, ember-gold eyes in the eye sockets, a broken scepter, dark-fantasy boss portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**`boss_collector`** (teal ground):
```
a towering hooded collector-lord, a void where its face should be lit by dozens of stolen soul-lanterns hung from its cloak, reaching out one long hand, dark-fantasy boss portrait, single imposing figure filling the frame, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa, dramatic firelit chiaroscuro, warm muted sepia palette with warm amber soul-lantern glow, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**`boss_amalgam_acolyte`** (tiny distant figure — reframe as a close boss):
```
a monstrous amalgam of the fallen Acolyte lord, a hooded death-priest fused with the bones of those it raised, ember-gold eyes, censer smoke curling, looming close and filling the frame, dark-fantasy boss portrait, hand-painted oil-and-ink in the Darkest Dungeon style of Chris Bourassa, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**Missing `hero_silhouette_kindler`** — complete the 5-hero silhouette set (match the others' Dark-Souls-bonfire framing):
```
a lone kindler hero seated at a campfire at night, cupping a small flame in both hands, warm firelight on a weathered face, full-body painterly silhouette illustration, Darkest Dungeon style of Chris Bourassa, dramatic firelit chiaroscuro, warm muted sepia and ember palette, dark atmospheric backdrop --ar 3:4 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

---

## TIER 2 — Missing bespoke card art (cards borrowing another card's painting)

**60 draftable cards currently render another card's painting** — so the same picture appears
on two cards in one run. None are *broken*, but each wants its own art. Below, each entry is a
**subject line**: paste it in front of the **CREATURE tail** (or **SPELL tail**) from the style
system above and you have a complete prompt. The six **tribe keystones**, three **starters**,
and the one **name collision** are given as full strings.

### Full strings — keystones, starters, collision

**`warden_sergeant` — Warden‑Sergeant** (Soldier keystone):
```
a grizzled line-sergeant roaring orders from behind a full shield-wall, baton raised, dented plate, mud and banners, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa with loose painterly brushwork, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember-orange rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`bloodmoon_alpha` — Bloodmoon Alpha** (Beast keystone):
```
a great scarred wolf-alpha howling under a blood-red moon, breath steaming, pack forming in the shadows behind, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and deep ember-red palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`gravepact` — Gravepact** (Dead keystone):
```
a robed grave-warlock sealing a blood pact over an open grave, one hand bleeding onto the dirt, pale wights beginning to claw their way up around it, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with sickly ember glow, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`coven_mother` — Coven Mother** (Warlock keystone):
```
a regal old coven-matron in tattered black robes, arms raised, warm hex-light pooling in the air around her clawed hands, candles guttering, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`siegewright` — War Fortress** (Bastion keystone):
```
a wheeled war-fortress bristling with overlapping shields and a great iron ram, tattered banners flying from its top, crewmen inside, grim-storybook dark-fantasy war-engine, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia ochre and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`kingpin` — Kingpin** (Stray keystone):
```
a fat crime-boss of the army baggage-train lounging on a throne of stolen loot, rings on every finger, counting a fistful of gold, two thug lieutenants in shadow, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and gilt palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`levy_rider` — Outrider** (starter):
```
a light hooded outrider scout leaning low over a lean fast horse, spear couched, galloping ahead of the column through dawn mist, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and ember palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`mourner` — Mourner** (starter):
```
a grieving hooded widow kneeling at a fresh war-grave, one candle guarded from the wind in her cupped hands, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia palette with a single warm candle glow, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`spark` — Spark** (starter spell):
```
a single struck flint-spark leaping bright across darkness to catch a fuse, one tiny brilliant ember, dark-fantasy spell effect, hand-painted in the Darkest Dungeon style of Chris Bourassa, loose painterly brushwork, bold ink linework, dramatic firelit chiaroscuro, warm muted sepia and ember-orange palette, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`adaptable` — rename "The Chameleon"** (⚠ its current name "Sellsword" collides with the real `sellsword` card):
```
a shrouded shapeshifting mercenary mid-change, gear flickering between shield, blade and cloak, a sly half-lit grin, grim-storybook dark-fantasy creature, hand-painted in the Darkest Dungeon style of Chris Bourassa, bold ink linework, thick visible brushstrokes, single centered subject, dramatic firelit chiaroscuro, warm muted sepia and umber palette with ember rim light, atmospheric warm-brown backdrop --ar 3:2 --v 8.1 --s 500 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, cel shaded, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

### Subject lines (prepend to the CREATURE / SPELL tail)

**Soldiers**
- `man_at_arms` — Man‑at‑Arms — a seasoned man-at-arms in dented plate advancing at a quick march, pike leveled
- `last_levy` — Last Levy — a lone desperate conscript planting his spear as a wall of shadow-soldiers closes in
- `pike_square` — Pike Square — a bristling square of leveled pikes seen head-on, a hedgehog of steel points and helmets
- `standard_bearer` — Standard Bearer — a mud-caked soldier raising a tattered regimental standard high in a rallying cry
- `bastion_lord` — Bastion Lord — a towering lord behind an immense tower-shield, striking back at attackers, immovable
- `mentioned_dispatches` — Mentioned in Dispatches *(SPELL)* — a courier reading a battlefield dispatch aloud as a soldier lunges to strike on command

**Bastions**
- `bramble_stockade` — Bramble Stockade — a wall of lashed thorn-branches and sharpened stakes, arrows stuck in the wood
- `crystal_sentry` — Crystal Sentry — a sentinel of smoky quartz raising a translucent faceted shield, faint warm inner glow
- `curtain_wall` — Curtain Wall — a sheer battlemented stone curtain-wall with an iron portcullis, looming close
- `ironhide_anvil` — Iron Rampart — a great iron-banded rampart gate dented from ramming, utterly unmoved
- `warding_stone` — Warding Stone — an ancient rune-carved menhir wrapped in black thorns, faint warm ward-glow
- `rolling_tower` — The Rolling Tower — a towering wooden siege-tower rolling forward on huge wheels, soldiers crowding the top
- `crew_mangonel` — Crew of the Mangonel — a mangonel crew winching back the throwing-arm, a shrouded body loaded in the sling
- `flanking_order` — Flanking Order *(SPELL)* — a hand sliding a carved wooden soldier sideways across a candlelit war-table into an open flank

**Beasts**
- `ash_hound` — Ash Hound — a lean hound made of drifting ash and embers mid-lunge, sparks trailing from its flanks
- `cinder_pup` — Cinder Pup — a small eager fire-pup with glowing cracks in its hide, a lit-fuse of a tail
- `cleave_hound` — Cleave Hound — a monstrous two-headed war-hound mid-lunge, both jaws wide in a sweeping bite
- `war_boar` — War Boar — a huge armored war-boar charging head-down, tusks lowered, churning mud
- `heartwood_elder` — Heartwood Elder — an ancient antlered stag-elder wreathed in autumn moss and bark, herd dim behind
- `rat_piper` — Rat Piper — a hooded piper playing a bone flute as a tide of rats pours from under his cloak

**Dead**
- `carrion_priest` — Carrion Priest — a hunched death-priest in rotted vestments swinging a smoking censer over a field of corpses
- `grave_goods` — Grave‑Goods — a warrior's grave-offering laid on fresh dirt: helm, sword and coins, faintly glowing
- `grave_levy` — Grave Levy — a shambling conscripted corpse-soldier jolting forward on a rusted spear, jaw slack
- `old_bones` — Old Bones — a battered old skeleton knight cracked and re-lashed with wire, refusing to fall apart
- `gravecaller` — Oathkeeper — an armored oath-knight kneeling with sword planted, pale ghosts of the fallen rising behind
- `grave_clutch` — Grave Clutch — a grasping hand of grave-dirt clutching a fresh mound, something huge stirring beneath
- `the_undying` — The Undying — a battered revenant calmly reassembling itself from its own scattered bones, over and over
- `pallbearers` — The Pallbearers — four hooded pallbearers shouldering a heavy war-coffin down a foggy road
- `muster_fallen` — Muster the Fallen *(SPELL)* — pale translucent shade-soldiers rising rank on rank from a dusk battlefield
- `salted_ground` — Salted Ground *(SPELL)* — a soldier scattering salt across scorched cursed earth where nothing will march

**Warlocks**
- `cinder_acolyte` — Cinder Acolyte — a young hooded fire-acolyte with ember-glowing eyes cupping a live spark
- `hexwright` — Hexwright — a gaunt hex-caster weaving a glowing curse-sigil between clawed fingers
- `emberwright` — Emberwright — a fire-mage pressing molten runes into the air, embers streaming from both palms
- `the_apothecary` — The Apothecary — a robed field-apothecary hunched among bubbling vials, dried herbs and a mortar

**Strays**
- `freelance` — Freelance — a rakish free-lance mercenary resting a couched lance on one shoulder, cocky half-grin
- `sword_on_credit` — Sword on Credit — a swaggering sellsword holding out an open palm for coin, sword still sheathed
- `understudy` — The Understudy — a young squire waiting just behind the front line, gripping a borrowed blade, ready to step up
- `scapegoat` — Scapegoat — a bound goat-masked figure roped to a stake, taking the blows meant for others
- `familiar` — Familiar — a witch's black cat with knowing raven-bright eyes perched among candle-lit spellbooks
- `pay_wagon` — The Pay‑Wagon — an iron-bound paymaster's strongbox wagon, gold glinting through the slats, wary guards near

**Unaligned spells**
- `sappers_charge` — Sapper's Charge — a sapper jamming a lit powder-charge under an enemy shield-line, fuse hissing
- `ballista_bolt` — Ballista Bolt — a massive ballista bolt punching clean through a shield and the man behind it
- `informer` — The Informer — a cloaked informer by lamplight pointing to a name on the enemy's muster-roll
- `crossed_orders` — Crossed Orders — two contradictory dispatch-scrolls crossing, enemy figures yanked sideways
- `gallows_writ` — The Gallows Writ — a wax-sealed death-warrant nailed to a gallows post above a doomed lane
- `long_roll` — The Long Roll — a drummer beating the long roll at dawn as weary soldiers straighten and rally
- `scatter_line` — Scatter the Line — a shockwave blast scattering a rank of soldiers sideways like dry leaves
- `wolf_pits` — Wolf‑Pits — sharpened stakes at the bottom of a camouflaged pit-trap, the dirt lid tipped ajar
- `grave_clutch` covered above

## TIER 3 — Relics & Events

### Events

Full strings for the true style‑breaks:

**`coin_on_edge`** (photoreal stock coin — total break):
```
a single worn old campaign coin spinning on its edge on a candlelit war-table, motion-blurred and about to topple, gamblers' shadows leaning in around it, grim-storybook dark-fantasy scene, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia and ember palette --ar 16:9 --v 8.1 --s 450 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```
**`hollow_lantern`** (worst cyan in the set):
```
a rusted iron lantern shaped like a skull hanging from a dead tree at a crossroads at night, a pale flame guttering inside the eye sockets, a lone traveler's silhouette on the road, grim-storybook dark-fantasy scene, hand-painted in the Darkest Dungeon style of Chris Bourassa, painterly brushwork and bold ink, firelit chiaroscuro, warm muted sepia palette with a small warm flame --ar 16:9 --v 8.1 --s 450 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, hyperrealistic, cartoon, text, words, watermark, signature, frame, border, ui, caption
```

**Pixel‑art cluster → repaint** (prepend to the EVENT/BACKGROUND tail):
- `beekeeper` — an old veiled beekeeper tending straw skep-hives at the edge of a war-camp, bees drifting in warm evening light
- `the_answering_well` — a mossy stone crossroads well, a pale face reflected in the black water, one lantern on the rim
- `the_weeping_orchard` — a fog-bound orchard of gnarled trees whose bark bears weeping human faces, dusk light
- `tollkeeper_bridge` — a hooded tollkeeper barring a narrow stone bridge over a dark river, lantern raised
- `three_doors` — three weathered free-standing doors in a dark forest clearing, one faintly glowing from within
- **Backgrounds** `combat_arena_act3` & `rest_campfire_act3` — same pixel‑art + cyan problem; regenerate off the BACKGROUND tail (a ruined cathedral arena / a campfire in cathedral ruins, warm ember, dark seat‑able foreground).

**Regrade warm (keep the scene, kill the cool):** `thrice_blessed_spring`, `gravesong_choir`,
`sin_eater`, `glass_familiar`, `drowned_bell` (also make it read as a *bell*), plus backgrounds
`combat_arena_act2` & `rest_campfire_act2` (warm the teal skies).

### Relics

29 relics read as a *different medium* from the warm painterly majority. Grouped by fix:

**Cluster 1 — Pixel‑art → repaint painterly** (RELIC tail): `resonance_crystal`, `thiefs_gloves`,
`bloodstone_relic`, `collectors_tome`, `conscription_relic`, `echo_staff`, `gamblers_coin`.

**Cluster 2 — Photoreal / 3D render on black void → repaint painterly** (RELIC tail): `pen_nib`,
`runebound_idol`, `war_drum`, `warlords_standard`, `scavengers_pouch`, `coin_landed`.

**Cluster 3 — Impressionist "gallery‑oil" scenes → recompose as ONE centered object** (RELIC tail):
the blue trio `mana_drunkard` / `mana_pearl` / `mana_tide`, plus `steady_banner`, `raiders_oath`,
`spotters_glass`, `reapers_scythe`, `marathoners_sash`.

**Cluster 4 — Wrong palette → regrade warm, keep the object:**
- purple/magenta: `runic_pyramid`, `stardust_vial`, `stygian_soul`, `snecko_eye`, `calling_bell`,
  `lichs_bargain`, `lean_mean`, `glowing_hand`
- toxic green: `witchs_brew`, `poisoned_rations`, `vanguards_cry`
- cyan/cold: `acolytes_tome`, `lantern`, `last_breath`, `fusion_hammer`, `brainstorm`

**Cluster 5 — Flat black void backdrop → repaint a warm deep‑brown backdrop, keep the object:**
`banner_of_unity`, `bulwark_engine`, `gravewardens_pact`, `hexagonal_shield`, `hourglass_of_ruin`,
`doom_herald`, `mime`, `mummified_hand`. *(The event‑relic vanitas trio `warm_knucklebone`,
`sin_eaters_crust`, `verse_of_you` share this black‑void look on purpose — leave them, or unify
the whole event‑relic set as one deliberate "still‑life" style.)*

**Cluster 6 — Two‑object / landscape / character‑art → recompose as a single trinket** (RELIC tail):
`bridge_watcher`, `junk_slot`, `merchants_license`, `sellswords_retainer`, `pyromancers_scar`.

**Low priority (cel‑shaded, on‑ember, just off‑brush):** `battle_scars`, `blacksmiths_hammer`,
`bone_ring`, `busted_crown` — fine to leave until last.

**Cleanup:** `recruiters_horn` is a **pixel‑identical duplicate of `war_horn`** — repaint one.
`swift_boots` has a baked‑in stone frame border and doesn't read as boots — repaint.

Full strings for the highest‑value relic replacements:

**`coin_landed` — The Coin, Landed** (event relic):
```
a single aged bronze campaign coin fallen flat on dark wood, showing the Old King's worn crowned profile catching warm lamplight, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and gilt palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`war_drum`**:
```
a battered goatskin war-drum with crossed worn drumsticks and frayed rope tension-cords, faint ember light on the skin, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`warlords_standard`**:
```
a warlord's tattered battle-standard furled on a broken spear-shaft, dented crest finial, wind-torn cloth, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`witchs_brew`** (drop the toxic green):
```
a small black iron cauldron of thick bubbling brew, warm ember coals glowing beneath it, a curl of steam, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, green glow, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```
**`resonance_crystal`** (drop the pixels + magenta):
```
a single humming amber crystal shard set in a worn iron mount, faint warm resonance rings in the air around it, stylized hand-painted fantasy game relic icon, Darkest Dungeon and Slay the Spire style, one bold readable object centered, bold visible brushstrokes, painterly illustration, warm muted sepia and amber palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture --ar 1:1 --v 8.1 --s 400 --no cyan, teal, neon, saturated blue, magenta, pixel art, photograph, 3d render, cgi, realistic, flat black background, empty void, flat vector, text, words, watermark, signature, frame, border, ui, caption
```

## Appendix

### A. Re‑tone batch — keep the concept, kill the cyan
These paintings are otherwise fine; they only need the cool cast pulled to warm sepia/ember.
Cheapest path: re‑run each through **img2img / a low‑`--sw` `--sref` of a warm card you like**,
or regenerate from the CREATURE/SPELL tail with the same subject. The `--no cyan, teal, neon,
saturated blue` in the tails does most of the work.

- **Creatures:** `archmage`, `glass_knight`, `e_wind_harpy`, `vampire_lord`, `warden_of_graves`,
  `crow_witch`, `gravedigger`, `harpy`, `doppelganger`, `necromancer`, `ironclad_veteran`,
  `ratling` (desaturate the cyan gem to amber), `chaos_imp` (also change medium — it's a flat
  classical-oil portrait; repaint painterly with atmosphere), `sprite` (drop the anime/green).
- **Spells:** `recycle`, `reposition`, `soul_swap`, `time_snare`, `shield_wall`, `ambush`,
  `banish`, `quick_shot`, `second_wind`, `slash`, `grave_pact`, `mending_light` (repaint
  painterly — it's photoreal). Differentiate `reposition` (soldiers physically swap lanes) from
  `soul_swap` (two souls trade bodies) so they stop looking identical.
- **Elements that may stay blue** (don't over‑correct): `frost_bolt`, `hoarfrost`, `lightning`.

### B. Cleanup actions (no art needed — just files/data)
- **Delete / stop shipping** `hud_gold_painted.png` (the cartoon cyan‑diamond coin; the good
  `hud_gold_coin.png` is already the live one).
- **Resolve the siege_kitchen pair** — VERIFIED 2026‑07‑22: the LIVE art is
  `the_siege_kitchen-character-stage-v2.png` (EventDB.gd `"art"` key points here — do NOT delete
  it). `the_siege_kitchen-finished-example.png` is a dev‑only reference used by shot tools. When
  bespoke art lands, save it as `the_siege_kitchen.png` and drop the `"art"` override so it
  resolves by id; only then retire the two hyphenated files.
- **Strip baked‑in text / borders / signatures on regen:** `pawnbrokers_window` ("Pawnbroker"
  sign), `the_chrysalis` (letterbox border), and faint signatures on `two_headed_calf`,
  `drowned_bell`, `fork_in_the_long_road`, `coin_on_edge`; creature borders on `e_bog_lurker`,
  `mule`, `wolf_c`.
- **Duplicates:** `kindling_alt` == `kindling` and `plague_bell` == `mass_grave` — both have new
  prompts in Tier 1.

### C. Rename proposals (optional — you invited these)
The naming is mostly strong, so this is short. Only the first is a real fix.

| id | current | proposed | why |
|---|---|---|---|
| `adaptable` | **Sellsword** | **The Chameleon** | collides with the real `sellsword` card + shares its art |
| `recycle` | Recycle | **Salvage Rites** | "recycle" is a modern word in a war‑road register |
| `turbo` | Turbo | **Double‑Time** / **Forced March** | same — "turbo" breaks the period voice |
| `concentrate` | Concentrate | **Take Aim** / **Steady** | reads truer to the effect and the setting |
| `coin` (spell) | Coin | **The Toll** / **Spinner's Luck** | plainer than the world's other coin flavor |

*(Everything else — Outrider, Warden‑Sergeant, Gravepact, Kingpin, Pallbearers, The Undying,
Wolf‑Pits, The Gallows Writ, Bramble Stockade, etc. — is already on‑voice. Leave them.)*

### D. Cohesion decisions (your call)
1. **Bosses split into two rendering families** — ink‑comic (`boss_act1/2/3`, named bosses) vs
   fine‑oil (all 5 `amalgam` + `the_crone`). Both look good; they just don't mix. Pick ONE as the
   house boss look and regrade the other family toward it (the fine‑oil set is the stronger,
   more "AAA" candidate).
2. **Act‑2 / Act‑3 backgrounds run cool** (`combat_arena_act2`, `rest_campfire_act2` teal skies;
   `combat_arena_act3`, `rest_campfire_act3` are pixel‑art + cyan). Regenerate the act‑3 pair off
   the EVENT/BACKGROUND tail and warm the act‑2 skies.
3. **`main_menu`** wall of fire is bright/busy behind the menu column — add a scrim/panel behind
   the buttons (code) rather than new art.

### E. Suggested batch order
1. Generate **one** definitive warm creature (e.g. re‑do `warden_sergeant`), lock its `--sref`.
2. Run all Tier 1 replacements with that `--sref --sw 100`.
3. Do the 60 Tier 2 cards in tribe batches (Soldiers, Bastions, Beasts, Dead, Warlocks, Strays),
   one `--sref` per tribe so each tribe reads as a family.
4. Relics/events last, grouped by the REPLACE clusters in Tier 3.
