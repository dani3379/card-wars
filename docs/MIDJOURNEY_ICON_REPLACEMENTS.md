# Midjourney prompts — replace the silhouette icons + duplicate cards (v2, 2026-07-08)

Replaces relic/potion silhouettes and duplicate/placeholder cards with bespoke
**hand-painted** art. v2 rewrites the style tail: the v1 "oil-painted museum
artifact study" + `--style raw` combo rendered as photoreal product shots on a
dead black void. This version pushes a painterly game-icon look (Slay the Spire /
Darkest Dungeon), a warm painterly backdrop instead of flat black, and hard
`--no photograph, 3d render, realistic`.

## Workflow (png-wins convention — no code change)

Generate → upscale → save PNG at the path (relics `assets/icons/relics/<id>.png`,
potions `assets/icons/potions/<id>.png`, cards `assets/creatures/<id>.png` or
`assets/spells/<id>.png`). The PNG auto-wins over the `.svg`; run a headless
`--import`. **Set cohesion:** generate one relic, then `--sref <its URL>` on the
rest so the tray matches.

## Shared tails (paste after each subject)

- **RELIC / POTION tail**
  `stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption`
- **CARD (creature) tail**
  `grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption`
- **CURSE SIGIL tail**
  `arcane glowing curse sigil, grim storybook dark-fantasy illustration, bold ink linework, painterly shading, atmospheric dark background --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, realistic, text, words, watermark, frame, border`

---

# RELICS → assets/icons/relics/

## Starting relics (seen every run — do first)

**iron_buckler — Iron Buckler**
```
a small battered round iron buckler shield with a raised central boss, deep dents and one defiant fresh gouge, worn leather grip, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**ember_crown — Ember Crown**
```
a blackened iron crown with glowing ember coals set where the jewels should be, thin wisps of smoke rising from the points, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**couriers_bag — Courier's Bag**
```
a worn leather courier's satchel with a broken red wax seal and a rolled dispatch poking from the flap, brass buckles, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**coin_purse — Coin Purse**
```
a fat drawstring leather coin purse tipped over, a few gold coins spilling from its mouth, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**worn_spellbook — Worn Spellbook**
```
a cracked leather grimoire with a snapped clasp lying open, faint glowing red script bleeding across the exposed page, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**scouts_emblem — Scout's Emblem**
```
a tarnished brass reconnaissance badge stamped with a watchful eye above crossed arrows, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**soul_lantern — Soul Lantern**
```
an iron lantern holding a pale captive blue soul-flame, faint face-like wisps drifting inside the glass, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**veterans_medal — Veteran's Medal**
```
a battered bronze campaign medal shaped like a worn-smooth star hung on a faded ribbon, an old dent across one arm, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**ember_censer — Ember Censer**
```
a swinging bronze thurible censer on chains pouring glowing embers and smoke, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```

## Combat relics

**briar_amulet — Man-Trap**
```
a rusted iron toothed man-trap sprung shut, a thorny briar vine coiled through its jaws, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**piercing_crown — Bodkin Points**
```
a tight cluster of long slender bodkin arrowheads bound at the base, needle-sharp, one tip darkened with blood, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**war_horn — War Horn**
```
a great curved bronze-banded war horn on a worn leather baldric, the mouthpiece polished from use, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**glass_cannon — Glass Cannon**
```
a delicate blown-glass field cannon, a bright ember charge glowing inside the fragile transparent barrel, one hairline crack spidering the glass, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**butchers_cleaver — Butcher's Cleaver**
```
a heavy notched butcher's cleaver buried in a scarred wooden chopping block, blade nicked and dark with dried blood, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**bone_pile — Bone Pile**
```
a heaped pile of bleached bones and a cracked skull, a single rib jutting upward, dust settling, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**phoenix_heart — Phoenix Heart**
```
a glowing ember-orange heart wreathed in small licking flames, cupped in a nest of grey ash, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**vanguard_banner — Vanguard Banner**
```
a proud forward-leaning war banner on a spear shaft, the pennant snapping forward as if charging, a gilded spearhead finial, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**rear_guard_charm — Rear Guard Charm**
```
a small protective bronze charm of two crossed shields on a knotted leather cord, worn and rearward-facing, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**champions_belt — Champion's Belt**
```
a heavy studded champion's prize belt with a great engraved buckle bearing a laurel-and-sword medallion, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**iron_legion — Iron Legion**
```
a stacked wall of interlocking iron legionary shields forming one bristling block, spear tips showing between them, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**phalanx_stone — Phalanx Stone**
```
a carved grey standing stone incised with a relief of a rank of interlocked spears, moss in the grooves, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**catapult_crew — Catapult Crew**
```
a small loaded torsion onager catapult, its throwing arm cranked back with a heavy stone in the sling, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**bridge_watcher — Bridge Watcher**
```
a lone squat stone watchtower guarding the mouth of a narrow bridge, a single lantern lit in its window, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**linked_banner — Linked Banner**
```
a row of small pennants linked along one taut cord strung between two planted spears, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**du_vu_doll — Maledetto Poppet**
```
a small crude cursed poppet doll bound in black thread with iron pins, a single rusted nail driven through its chest, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**inkpot_of_many — Inkpot of Many**
```
an ornate brass inkpot bristling with many quills, dark ink welling up and overflowing down the sides, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**the_family — Sharpened Pitchforks**
```
a bundle of sharpened farm pitchforks and billhooks lashed together upright, crude peasant-levy weapons, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**junk_slot — Open Ground**
```
a bare patch of trampled open muster-ground with a single planted marker stake and a coil of rope, faint haze, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**deep_satchel — Deep Satchel**
```
a deep bulging campaign satchel overstuffed with rolled papers and cards, the flap straining and barely buckled, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**letters_patent — Letters Patent**
```
a rolled vellum charter tied with gold ribbon, a great pendant red wax seal hanging from it, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**deserters_toll — Deserter's Toll**
```
a small iron toll-bell hung over a discarded soldier's dented helmet and a snapped sword, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**drovers_whip — Drover's Whip**
```
a coiled braided leather drover's whip with a worn bone handle, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**dregs — Dregs**
```
an empty broken green glass potion bottle, the last dark dregs pooling at the jagged neck, a hairline of green glow, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**poisoned_rations — Poisoned Rations**
```
a mouldy ration of hardtack and salted meat on a tin plate, a faint green miasma curling up, a single fly, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**sellswords_retainer — Sellsword's Retainer**
```
a mercenary's scarred gloved hand clutching a heavy coin-fat purse and the wire-wrapped hilt of a sheathed sword, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```

## Utility relics

**merchants_license — Merchant's License**
```
a stamped guild trade-license scroll bearing an official red seal, a small brass balance scale resting on it, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**whetstone — Whetstone**
```
a well-used rectangular sharpening whetstone with a blade drawn across it throwing a spray of sparks, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**centaur_heart — Centaur Heart**
```
a large glowing crimson beating heart bound in leather straps and bronze bands, vigorous and warm, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```

## Boss relics

**cursed_key — Cursed Key**
```
an ornate blackened skeleton key wreathed in faint sickly green curse-light, its teeth shaped like tiny screaming faces, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**coffee_dripper — Hairshirt** *(art must be a hairshirt, NOT a coffee item)*
```
a coarse grey woven horsehair penitent's shirt hung on an iron hook, prickly and shapeless, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**ectoplasm — Vow of Poverty**
```
an empty upturned wooden begging bowl beside a knotted cord belt of a mendicant, one moth, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**sozu — Temperance Vow**
```
an overturned empty glass potion flask sealed shut with a wax temperance cross over the stopper, a dry cork beside it, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**philosophers_stone — Philosopher's Stone**
```
a glowing crimson alchemical stone resting on a small pedestal, veins of molten gold threading its surface, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**velvet_choker — Penitent's Collar**
```
a tight iron penitent's collar lined with worn dark velvet, a small lock set at the throat, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**pandoras_box — The Conjurer's Coffer**
```
an ornate locked coffer cracked open, swirling arcane smoke and half-formed shifting shapes pouring out of the gap, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```

## Command relics

**happy_flower — Saint's Posy** *(a posy of flowers, not a skull)*
```
a small posy of dried wildflowers bound with a faded saint's ribbon, a faint holy glow around the petals, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**ice_cream — Miser's Coffer** *(a strongbox, NOT ice cream)*
```
a heavy iron-bound miser's strongbox coffer with its lid ajar, glinting hoarded gold coins packed to the brim, stylized hand-painted fantasy game relic icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```

---

# POTIONS → assets/icons/potions/

Keep each bottle's interior color matching the in-game tint (paint it in — the
PNG is used untinted).

**healing — Healing Potion** (deep red)
```
a rounded glass vial of glowing deep-red healing elixir with a cork stopper and warm inner light, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**bottled_fury — Sapper's Charge** (orange)
```
a squat thick glass flask packed with coarse orange blasting powder and a short lit fuse trailing sparks, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**mana_surge — Rallying Horn** (blue)
```
a horn-shaped blue glass flask with swirling electric-blue energy coiling inside, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia palette with a cool blue glow, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**inferno_vial — Inferno Vial** (red-orange)
```
a tall glass vial of churning molten orange-red fire with flames licking up against the stopper, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**insight_tonic — Insight Tonic** (violet)
```
a violet glass tonic bottle of swirling starry lilac liquid with a single glowing eye of light suspended inside, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, muted sepia palette with a violet glow, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**phoenix_brew — Phoenix Brew** (amber-gold)
```
an amber-gold glass flask holding a tiny reborn ember-bird taking wing inside with sparks rising, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**war_paint — War Paint** (blood red)
```
a wide clay jar of thick blood-red war paint with a bristle brush smeared across the rim, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**vampiric_draught — Vampiric Draught** (crimson)
```
a dark crimson glass draught bottle filled with thick blood, slow drips running down the outside of the glass, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**chain_flask — Chain-Lightning Flask** (icy blue)
```
a pale icy-blue glass flask crackling with forked white lightning arcing between its walls, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, muted sepia palette with an icy-blue glow, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**doomsday_draught — Doomsday Draught** (red-black)
```
a red-black glass draught bottle with a tiny ticking doom-clock skull suspended in the molten liquid, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**aegis_brew — Aegis Brew** (light blue)
```
a pale sky-blue glass flask with a shimmering hexagonal shield-barrier glowing inside it, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, muted sepia palette with a soft blue glow, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**conscript_brew — Conscription Brew** (wheat tan)
```
a wheat-tan glass flask with tiny armored recruit figures forming out of the swirling sediment inside, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**butchers_dram — Butcher's Dram** (red)
```
a small red glass dram bottle with a carved bone-handle stopper and a smear of blood across the shoulder, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, warm muted sepia and ember palette, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```
**grave_diggers_nip — Grave-Digger's Nip** (mossy green)
```
a mossy green glass nip bottle of murky grave-dirt tonic with a tiny gravedigger's shovel tied to its neck, stylized hand-painted fantasy potion icon, Slay the Spire and Darkest Dungeon art style, bold visible brushstrokes, painterly illustration, muted sepia palette with a mossy-green glow, gentle amber rim glow, warm deep-brown painterly backdrop with soft texture, clear bold readable shape --ar 1:1 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, flat black background, empty void, text, words, watermark, signature, frame, border, UI, caption
```

---

# CARDS → assets/creatures/ and assets/spells/

**warchief.png — Warchief [rare]**
```
a towering scarred warchief roaring with head thrown back, raising a massive banner-topped war-axe overhead, war-paint and bone trophies, ragged ranks massing behind in the haze, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**riteforge.png — Riteforge [rare]**
```
a molten forge-golem smith hammering a glowing blade on the anvil built into its own chest, sparks flying, ritual runes cooling on its iron hide, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**vengeful_spirit.png — Revenant [uncommon]**
```
a gaunt armored revenant dragging itself up from a battlefield grave, a torn banner still gripped in one skeletal hand, cold vengeful light in the eye-sockets, spectral chill, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**corpse_eater.png — The Glutton [uncommon]**
```
a bloated hunched ghoul feasting greedily hunched over a heap of the fallen, distended belly, gore-slick grinning mouth, ribs of the eaten scattered around, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**e_dark_priest.png — Sin-Eater [uncommon]**
```
a hooded sin-eater solemnly eating a funeral meal laid out on the chest of a shrouded corpse, guttering candles, a single coin on each eye of the dead, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**naga.png — Hexblade [common]**
```
a serpentine hexblade warrior whose lower body is a coiled scaled snake, raising a rune-etched curved sword wreathed in cold hex-light, hooded and hissing, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**e_devil_champ.png — Devil's Champion**
```
a towering ram-horned armored devil champion wreathed in lava and drifting embers, an immense menacing final-boss silhouette, molten cracks glowing through black plate, grim storybook dark-fantasy illustration, bold ink linework, loose painterly brushwork, muted sepia-and-olive palette with ember accents, atmospheric shadowy background, hand-painted card game art --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, cgi, hyperrealistic, realistic, text, words, watermark, signature, frame, border, UI, caption
```
**deserters_mark.png — Deserter's Mark** (a sigil, not a person)
```
a branding-iron sigil of a broken spear beneath an upside-down banner, glowing raw pale-red on scorched dark cloth, thin smoke still rising, arcane glowing curse sigil, grim storybook dark-fantasy illustration, bold ink linework, painterly shading, atmospheric dark background --ar 3:2 --v 6.1 --stylize 350 --no photograph, 3d render, realistic, text, words, watermark, frame, border
```

---

# Keyword devices → LEAVE AS SILHOUETTES (recommendation unchanged)

The 23 keyword icons print at ~24px on the card margin — flat monochrome devices
read far better there than any painting. If you insist, keep them as flat gilt
emblems, not scenes:
```
<SUBJECT e.g. a plated pauldron / a winged sandal / a barbed thorn ring>, flat solid gold heraldic emblem silhouette, centered single clean shape, no shading, game-icons.net style device, transparent background --ar 1:1 --no photograph, 3d render, gradient, scene, text, words
```
