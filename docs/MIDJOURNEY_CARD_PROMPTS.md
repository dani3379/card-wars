# Midjourney prompts — card art gaps

Generated 2026-07-07 from the card-art audit (duplicates + misfits). House style
derived from the existing 768×512 creature/spell paintings: bold ink outlines,
textured painterly shading, muted sepia/olive palette with ember or teal glow,
single centered subject, grim-whimsical register.

**Workflow:** generate → upscale → save as `assets/creatures/<card_id>.png` or
`assets/spells/<card_id>.png` (ids below — note Powder Cart = `ember_stalker`,
Twinblade = `breaker`, Cowardice = `craven`) → headless `--import` → re-run the
audit contact sheet. The bespoke file auto-wins over the alias; no code change.

Shared tail:
`dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border`

---

## Creatures → assets/creatures/

### palisade.png — Palisade (Guardian wall)
```
a defensive wall of sharpened timber stakes lashed with rope and planted in churned mud, arrows and a broken spear stuck in the wood, a tattered banner snagged on one point, stubborn and immovable, ember campfire glow from behind, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### lancer.png — Lancer (Overrun 2)
```
a knight at full gallop couching a long war lance, horse and rider leaning into the charge, dust and splinters trailing behind, unstoppable forward momentum, pennon streaming from the lance tip, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with ember glow, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### glass_knight.png — Glass Knight (Shield, Swift)
```
an elegant knight whose armor and body are translucent blown glass, candlelight refracting through the chest in amber and teal, a thin crystal sword raised, beautiful and one blow from shattering, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with glowing glass highlights, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### husk.png — Husk (Guardian; On-Death: summon 2/2)
```
a hollow lumbering creature of dried bark and empty chitin plates, a small glowing creature curled asleep inside its cracked-open chest cavity, the shell protective and patient, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with a warm inner glow, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### basilisk.png — Basilisk (Poison; poisonous Thorns)
```
a single crowned serpent coiled on cracked stone, baleful glowing yellow eyes, venom-slick spines bristling along its back, withered grass and a petrified bird at its coils, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with sickly green glow, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### plague_rat.png — Plague Rat (Poison)
```
a gaunt rat with matted fur and weeping green-glowing sores, standing in a puddle of miasma, tail wrapped around a gnawed bone, sickly and contagious, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with toxic green accents, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### ember_stalker.png — Powder Cart (Doom 3; detonates other Doom on death)
```
a rickety wooden cart overloaded with black powder kegs and coiled fuse, one fuse already lit and sputtering sparks, parked far too close to a campfire, ropes straining, imminent catastrophe played straight, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with ember-orange sparks, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### breaker.png — Twinblade (attacks twice)
```
a wiry scarred warrior mid-spin dual-wielding two curved blades, both swords leaving twin motion arcs of steel, low fighting stance, ragged war-torn clothes, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with ember glow, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### burning_martyr.png — Burning Martyr (Doom 3; On-Death: 1 dmg to all enemies)
```
a serene robed figure standing calmly ablaze with arms open, beatific expression untouched by the flames consuming the robes, a ring of scorched earth spreading outward, terrible and gentle at once, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with ember-orange fire, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### ember_warden.png — Ember Warden (gains ATK when enemy face takes effect damage)
```
an armored keeper carrying an iron brazier of glowing coals on a chain, embers drifting into the seams of the armor and lodging there like growing veins of fire, watchful stance, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with ember-orange glow, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### the_leveler.png — The Leveler (Piercing; On-Enter: 3 dmg to all enemies)
```
a colossal iron wrecking construct mid-swing, a stone rampart collapsing flat in a shockwave ring around it, dust and masonry hanging in the air, everything at one height when it finishes, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with ember glow through dust, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### shieldmaiden.png — Shieldmaiden (Guardian; On-Death: adjacent gain Shield)
```
a stern braided warrior woman planting a great round shield that covers her whole side, smaller soldiers sheltering in its shadow behind her, battered armor and steady eyes, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette with warm highlights, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### skirmisher.png — Headhunter (Swift; Slay: draw 1) — optional, e_headsman borrow also works
```
a lean bounty hunter running low and fast with a hooked short blade, a belt of trophy tokens and tally-notched leather, hungry focused eyes under a ragged hood, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia and olive palette, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

## Spells → assets/spells/

### coin.png — The Coin (gain 1 Command)
```
a single silver coin flipping in mid-air above an open gauntleted palm, a bright arc of golden light tracing its spin, motion frozen at the peak, small and decisive, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with brilliant gold gleam, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### slow_match.png — Slow Match (damage grows each turn it waits)
```
a long slow-burning fuse cord coiled in careful loops across a dark floor, a single patient ember creeping along it, each loop marking time, a powder charge waiting in the shadows at the far end, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with one ember-orange point of light, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### petard.png — The Petard (6 dmg to a RANDOM creature, either side)
```
an iron bell-shaped powder bomb tumbling end over end through the air with its fuse whipping wildly, soldiers on both sides of a battlefield ducking, nobody sure where it lands, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with ember sparks, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

## Curse sigils (branded pack — same family, distinct marks)
Base Curse keeps the green octagon; Wound keeps its flesh painting. These four
get sibling sigils: same dark murk ground, one glowing seal each, own color.

### craven.png — Cowardice (playable dud)
```
a glowing sigil of a cowering kneeling figure inside a shrinking ring, pale sickly yellow light on dark murky ground, the mark trembling at its edges, arcane curse seal, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, moody dark background --ar 3:2 --no text, letters, watermark, frame, border
```

### deserters_mark.png — Deserter's Mark (drawn: lose 1 Command)
```
a branding-iron mark burned into dark cloth, a rune of a broken spear beneath an upside-down banner, ashen grey and raw red scorch, thin smoke still rising from the brand, arcane curse seal, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, moody dark background --ar 3:2 --no text, letters, watermark, frame, border
```

### war_debt.png — War-Debt (drawn: lose 2 gold)
```
a blood-red wax ledger seal pressed over dark parchment, chain links embossed around a rune of an open hand, gold coins dissolving into smoke at its edges, arcane curse seal, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, moody dark background --ar 3:2 --no text, letters, watermark, frame, border
```

### grave_debt.png — Grave-Debt (drawn: take 1 damage)
```
a bone-white glowing sigil hovering over freshly turned grave earth, a coffin-shaped rune slowly sinking into the soil, cold pale light, worms of mist, arcane curse seal, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, moody dark background --ar 3:2 --no text, letters, watermark, frame, border
```

## Bonus — low-priority shares worth splitting eventually

### mark_of_ash.png — Mark of Ash (Doom 2, detonation deals NO damage — currently shares Hex's red ring)
```
a grey ring sigil of cold crumbling ash hovering in the air, the circle flaking apart and drifting down as soot, a smothered flame dying at its center, quiet and heatless, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, moody dark background --ar 3:2 --no text, letters, watermark, frame, border
```

### hellfire_imp.png — Hellfire Imp (Swift, Doom 2 — currently the purple Chaos Imp)
```
a small gleeful imp made of cracking coal and open flame seams, grinning with too many teeth, tiny bat wings smoking at the edges, hopping mid-cackle, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with hellfire orange, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```

### tallow_doll.png — Tallow Doll (On-Death: summon 1/1 — currently shares Changeling)
```
a small crude doll sculpted from melting tallow wax, a burning wick sprouting from its head, features sagging and dripping into a fresh puddle that is forming a second smaller doll, dark storybook fantasy illustration, bold ink outlines, textured painterly shading, muted sepia palette with candle glow, moody dark background, grim-whimsical dark fantasy game art --ar 3:2 --no text, letters, watermark, frame, border
```
