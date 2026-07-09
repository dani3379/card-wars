# Midjourney prompts — missing / improvable event art

Generated 2026-07-07 from the live 30-event pool. House style derived by
contact-sheeting the 33 existing paintings (dark storybook illustration, heavy
ink, mood-keyed palette). Existing art is 1456×816 = Midjourney native 16:9.

**Workflow:** generate → upscale → save as `assets/events/<event_id>.png` →
run a headless `--import` → `tools/_probe_event_pass.gd` + contact-sheet to
verify. The bespoke file auto-wins over the `"art"` stand-in key the moment it
exists; no code change needed.

**Not on this list (art already final):** the_bee_wife, the_burned_apiary,
the_red_tithe, the_chrysalis, the_glass_familiar (painting-first events — the
painting was the brief), the_crossing, and the rest of the pool with own art.

Shared style tail on every prompt:
`dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark`

Mood → palette key: bone = cold bone-white/ash-grey/night blue · ember =
ember orange/charred black/firelight · gilt = amber lamplight/honey gold/umber
· verdigris = oxidised green/cold teal/waxy candlelight.

---

## Tier 1 — stand-in actively wrong (do these first)

### the_turncoat_general.png (ember)
```
a proud general waiting alone at a roadside at dusk, his fine uniform with every insignia freshly unpicked leaving dark outlines and hanging threads, sheathed sword held out flat across both palms, the distant campfires of two armies on opposite horizons behind him, smouldering palette of ember orange and charred black, warm firelight against gathering dark, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_free_company.png (gilt)
```
a company of veteran mercenaries at a cold roadside camp regarding the viewer with professional disinterest, scarred faces and mismatched well-kept armor, a recruiter in front holding open a thick leather muster-book, furled banners, low grey sky, warm gilded palette of amber lamplight and honey gold over deep umber shadow, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_kings_measure.png (bone)
```
a royal surveyor in faded ceremonial livery standing on a dead moonlit road, holding up a long cold measuring chain toward the viewer as if to measure them, a huge wax-sealed ledger chained to his belt, milestones stretching into the dark, cold bone-white and ash-grey palette with deep night blue, pale moonlight, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_scapegoat.png (verdigris)
```
a calm goat tethered to an ancient boundary stone at the edge of a village, dozens of small paper collars tied around its neck and back, the goat gazing at the viewer with unsettling professional patience, a nervous village priest in the background, sickly verdigris palette of oxidised green and cold teal, waxy candlelight, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_chirurgeon.png (verdigris)
```
an enemy field-hospital tent with rows of neatly made empty cots, a gaunt chirurgeon in a leather apron sharpening surgical instruments by lantern light, bone saws and forceps hung in immaculate rows, his expression a little too eager, sickly verdigris palette of oxidised green and cold teal, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_wedding_at_the_ford.png (ember)
```
a country wedding held at a shallow river ford between two half-burned villages, garlands and ribbons strung over scorched timber, villagers dancing a sword-dance around a bonfire, a fiddler playing, firelight on the water, smouldering palette of ember orange and charred black with warm celebratory firelight, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_last_garrison.png (bone)
```
five skeletal soldiers in antique rusted armor holding formal watch on the wall of a crumbling border fort, spears shouldered in perfect drill order, a rotted banner overhead, cold moon over empty hills, cold bone-white and ash-grey palette with deep night blues, pale moonlight, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_bell_of_names.png (ember)
```
a traveling bell foundry working at night, molten bronze pouring from a crucible into a great bell mould, unreadable names cast into the glowing rim, heaps of dented battle-scrap armor waiting to be melted down, sparks rising, smouldering palette of ember orange and charred black, furnace light against darkness, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

## Tier 2 — stand-in passable, bespoke still better

### the_siege_kitchen.png (ember)
```
an army field kitchen abandoned mid-retreat but still cooking, cooks ladling stew from an enormous steaming cauldron, a patient ragged queue of deserters, farmers, two scouts and one large brown bear waiting in line together, trampled camp mud, smouldering palette of ember orange and charred black, warm cookfire light, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_lame_master.png (ember) — NOTE: the master is a woman (canon since the re-point)
```
an old woman master-at-arms with grey hair and a stiff knee drilling a row of battered scarecrows in a dusty training yard at dusk, practice sword raised in a perfect low guard, straw and dented helmets scattered, smouldering palette of ember orange and charred black, late warm light, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_ladder_merchant.png (gilt)
```
a merchant's cart stacked high with siege ladders parked in an open meadow exactly halfway between two distant opposing armies, a cheerful salesman slapping a ladder rung mid-pitch, the tents and banners of both hosts small on opposite horizons, warm gilded palette of amber and honey gold over deep umber shadow, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_remount_fair.png (ember)
```
a horse fair behind the war lines at dusk, traders dealing remounts and mules by torchlight, rows of picket lines, strange cages covered with blankets at the back, one blanket bulging the wrong way, smouldering palette of ember orange and charred black, torchlight and dust, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_reliquary_cart.png (gilt)
```
a tiny chapel built onto a wagon, saints' bones displayed in candlelit glass reliquaries, a friar opening an enormous ledger of miracles, a brass coin slot worn smooth by pilgrims' hands, incense smoke, warm gilded palette of amber lamplight and honey gold over deep umber shadow, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_drowned_ferry.png (verdigris)
```
a still lake flooding what should be a meadow, fence posts and a road vanishing under glassy water, three ferrymen waiting at three rotted landings with three very different boats, low mist, sickly verdigris palette of oxidised green and cold teal, drowned light, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_ninth_milestone.png (bone)
```
an ancient carved milestone beside a mountain road, the roadside verge buried a century deep in abandoned armor, weapons, chests and heirlooms half-swallowed by earth, the road climbing toward a distant keep, cold bone-white and ash-grey palette with deep night blues, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### the_war_poet.png (gilt)
```
a poet seated on a hillside at a safe professional distance from a battle burning in the valley below, writing in a ledger by lamplight, pen mid-stroke, the distant fire reflected in his spectacles, warm gilded palette of amber lamplight and honey gold over deep umber shadow, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

## Improvements — own art exists but is off

### coin_on_edge.png (gilt) — current art is the pool's only photorealistic outlier
```
a single silver coin spinning impossibly upright in a deep groove it has worn into a packed dirt road, faint motion blur, a small blank wooden sign staked beside it, dark forest pressing in around the road, warm gilded palette of amber and honey gold over deep umber shadow, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```

### strangers_hand.png (verdigris) — current art shows the CUT "hand at a red door" concept; the live event is The Wet Cards
```
a hooded stranger crouched at a flat river stone dealing swollen water-stained playing cards face-up, each card glistening wet, the stranger looking up at the viewer once, riverbank gloom, sickly verdigris palette of oxidised green and cold teal, waxy light, dark fantasy storybook illustration, heavy ink linework, textured gouache painting, grim medieval fairytale --ar 16:9 --no text, letters, watermark
```
