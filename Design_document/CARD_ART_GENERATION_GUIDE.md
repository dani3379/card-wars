# Burning Meadow — Card Art AI Generation Guide

> Complete, self-contained instructions for generating ALL card art using AI image generation (Civitai / Stable Diffusion / ComfyUI).
> Paste this entire document into a new chat session to begin production.

---

## WHAT THIS DOCUMENT IS

You are helping create card art for "Burning Meadow," a fantasy lane-combat roguelike deckbuilder built in Godot. The game has 77 creatures (59 player + 18 enemy) and 45 spells. About 48 creature portraits and all 45 spell illustrations already exist. **~29 creature portraits are missing and need to be generated.** Additionally, all existing art should eventually be regenerated for style consistency, but the missing pieces are the priority.

The art will be generated using **free AI image generation tools** — primarily Civitai's on-site generator, or locally via Stable Diffusion (SDXL/Pony/Illustrious checkpoints) with ComfyUI or A1111.

---

## PART 1: TECHNICAL SPECIFICATIONS — VERIFIED FROM GAME CODE

### How Art Actually Displays In-Game (exact numbers from Card2D.gd)

The game has THREE display contexts for card art. Your generated art must work in ALL of them:

**Context 1: Hand cards (v3/v5 frame layout)**
- Card size: 180x252 pixels, rendered at 0.8 scale = **144x202 actual pixels**
- Art window anchors: 0.093–0.907 x 0.237–0.603
- **Art window = 147x92 pixels** (a wide horizontal band)
- Frame PNG sits ON TOP of the art, masking the edges

**Context 2: Battlefield (compact layout)**
- Slot size: 140x145 pixels
- Art window anchors: 0.04–0.96 x 0.04–0.96
- **Art window = ~129x133 pixels** (nearly fills the card)
- Only corner stat badges overlay the art

**Context 3: Hand cards (v4 procedural frame layout)**
- Same 180x252 card, art anchors: 0.06–0.94 x 0.05–0.54
- **Art window = 158x124 pixels**

**THE CRITICAL IMPLICATION:** The art window is always roughly **130-160 pixels wide** on screen. Generating at 1024x1024 means you're creating an image that gets downscaled **7-8x**. Generating at 1500+ pixels (like some existing art) means **10-13x downscale**, which causes visible aliasing artifacts because mipmaps are currently disabled in the project.

### Display Pipeline (what Godot actually does with your image)

```
Your PNG/JPG file
  → Godot imports it (lossless, compress/mode=0, NO mipmaps)
  → Stored as uncompressed RGBA8 in GPU memory (Width × Height × 4 bytes)
  → TextureRect with STRETCH_KEEP_ASPECT_COVERED crops to fill the art window
  → clip_contents = true on the parent Control hides anything outside the window
```

Key facts from this pipeline:
- **STRETCH_KEEP_ASPECT_COVERED** means Godot will CROP your image to fill the window, not distort it. If your image is square (1:1) and the window is landscape (~1.6:1), Godot crops the top and bottom. The CENTER of your image is what survives.
- **No transparency needed.** The clip_contents flag handles masking. You do NOT need alpha channels, transparent backgrounds, or cutout shapes. Opaque images are correct.
- **GPU memory = raw pixels, not file size.** A 500KB PNG and a 3MB PNG at the same resolution cost IDENTICAL VRAM. A 1024x1024 RGBA8 image = 4 MB in GPU memory. With 100+ cards that's 400+ MB. Pre-resizing to 512x512 cuts this to 100 MB.

### Output Requirements (corrected for functional reality)

| Parameter | Value | Why |
|-----------|-------|-----|
| **Generate at** | 768x512 or 1024x768 | Match the art window's ~1.5:1 landscape aspect ratio BEFORE generating — not after. Avoids wasting half the image to cropping. If your generator only does square, use 768x768 minimum. |
| **Final delivery size** | **512x340 pixels** (or at most 512x512) | Pre-downscale before placing in project. Displaying a 1024px image at 147px with no mipmaps = aliasing. 512px source → 3.5x downscale is the sweet spot. |
| **Format** | PNG only | The game code tries `.png` first, falls back to `.jpg`. PNG is preferred. Godot imports both identically. |
| **Color space** | sRGB, no embedded ICC profile | Godot ignores ICC profiles and assumes sRGB. A Display-P3 or AdobeRGB profile will cause colors to display wrong with no error message. |
| **Strip metadata** | YES — mandatory | SD/ComfyUI embeds full prompts in PNG tEXt chunks. This ships with your game and is extractable. Run `exiftool -all= *.png` or use pngcrush before import. |
| **Naming** | `{card_id}.png` — EXACT match to CardDB.gd `id` field | The loader does `"res://assets/creatures/%s.png" % card_id`. If the filename doesn't match, the card gets a placeholder gradient. Case-sensitive on Linux export. |
| **Destination folder** | `assets/creatures/` for ALL creatures (player + enemy), `assets/spells/` for spells | Enemy creatures go in the SAME folder as player creatures, prefixed with `e_`. |

### VRAM Budget Reality Check

| Source resolution | VRAM per image | 100 images total | Verdict |
|-------------------|---------------|-------------------|---------|
| 1500x2000 (current worst case) | 11.4 MB | 1,140 MB | WAY too much |
| 1024x1024 | 4.0 MB | 400 MB | Borderline |
| 512x512 | 1.0 MB | 100 MB | Good |
| 512x340 (recommended) | 0.7 MB | 70 MB | Ideal |
| 300x400 (frame ref size) | 0.5 MB | 50 MB | Minimum viable |

Integrated GPUs (Intel/AMD iGPU) often have 512 MB–2 GB shared VRAM. Card art at 512x340 keeps the total budget reasonable even on low-end hardware.

### Things That Will Silently Go Wrong (AI art traps)

**1. SD generates vignettes you didn't ask for.**
Stable Diffusion tends to darken corners and edges in outputs regardless of prompt — it's a known artifact that SD practitioners routinely work around. When your card frame already adds a dark border, the combined effect makes the art window look like a dark rectangle at small sizes. **Fix:** Add `vignette, dark corners, border` to negative prompt AND post-process with a +10-15% brightness boost on the outer 15% of the image.

**2. Dark fantasy art becomes an unreadable black blob.**
At 147 pixels wide, a moody atmospheric portrait with 20-30% brightness becomes an indistinct dark smear. You CANNOT see detail at this size in dark images. **Fix:** Generate brighter than you think looks good at full size. Target 40-50% average brightness. Contrast between subject and background is more important than dark atmosphere. The card FRAME already provides the dark mood.

**3. Faces turn to mush below ~40px.**
If a face occupies only 25% of a 512px source, it's ~128px in the source but displays at ~35px on-card. Eyes become dark dots, mouths disappear, noses merge with cheeks. **Fix:** Face must occupy at least 30-40% of image width. CLOSE CROP. Head + shoulders only, not full body.

**4. SD/SDXL outputs are always opaque — this is FINE.**
Standard Stable Diffusion cannot generate real alpha transparency. The VAE outputs RGB only. This is not a problem for your game — `clip_contents` handles masking. DO NOT waste time trying to generate transparent backgrounds.

**5. Generating at 1:1 wastes half the image.**
Your art window is landscape (~1.6:1). If you generate at 1024x1024, STRETCH_KEEP_ASPECT_COVERED crops the top ~20% and bottom ~20% off. Your carefully prompted "face in the upper third" gets cropped away. **Fix:** Generate at landscape aspect ratio (768x512, 1024x640) so the full image is visible in the window.

**6. File lookup is case-sensitive on Linux.**
Your game might export to Linux. `shieldbearer.png` and `Shieldbearer.png` are different files. Always use all-lowercase filenames matching the card_id exactly.

**7. Style drift across generation sessions is severe.**
Research shows that without LoRA or locked settings, generating 30+ images produces noticeable inconsistency in color temperature, lighting direction, and detail level. Your existing art already shows this — mixed PNG/JPG, resolutions from 500px to 4700px, different visual styles. **Fix:** Generate ALL missing art in a SINGLE session with locked settings (same model, same LoRA weights, same CFG, same sampler, same prompt prefix).

---

## PART 2: THE VISUAL STYLE

### Target: Dark Fantasy Painterly — NOT Anime, NOT Photorealistic

Based on the existing art that works best in the game, the target style is:

**"Dark fantasy digital painting with warm firelight. Semi-realistic proportions, painterly brushwork visible, rich textures. Not anime (no huge eyes, no cel-shading). Not photorealistic (no pore-level detail). Think Darkest Dungeon's atmosphere meets Magic: The Gathering's painted portraits."**

### The 5 Style Rules (enforce in EVERY prompt)

**1. Warm color temperature — lit by firelight.**
Everything leans amber/golden. Even "cool" creatures have warm undertones. Blues are teal-shifted (toward `#0D7377` not pure blue). Purples are wine-shifted. The whole game feels "lit by firelight at dusk."

**2. Top-left lighting at 45 degrees. Always.**
- Bright highlight on upper-left of face/body
- Shadow on lower-right
- This is the single most important consistency rule. If one card has light from the right and another from the left, they look like different games.

**3. Three-quarter bust, slight low angle.**
- Head + shoulders + upper torso + weapon/hands visible
- Subject fills 70-80% of the frame vertically
- Face at upper third of image
- Body turned 20-30 degrees from center
- Camera slightly below eye level (10-15 degrees) — makes creatures imposing

**4. Abstract dark background — NEVER a detailed scene.**
- Dark gradient, atmospheric smoke, warm color wash
- Background contrasts the subject: warm creature = cooler dark background, cool creature = warm dark background
- Background should be 20-30% brightness. Blurred. No recognizable objects.
- Think "dramatic portrait studio lighting" not "creature in a forest"

**5. Bold readable shapes — passes the squint test.**
- Squint until it's a blob. Can you tell what creature it is from the outline alone?
- A dragon should have horns/wings in silhouette. A knight should have a helmet. A mage should have a staff/hat.
- If the shape reads as "generic person," redesign the pose/props.

### Why "Beautiful" AI Art Fails at Card Size (The Readability Problem)

AI image generators are trained on full-screen photos and concept art. They optimize for what looks impressive at 1080p — cinematic depth-of-field, atmospheric haze, intricate filigree, subtle color grading. **Every one of these properties is invisible or actively harmful at 147 pixels wide.**

This is the single biggest trap in AI card art generation. The AI says "look how gorgeous this is" and it IS gorgeous — at full resolution. On the card it's an indistinct dark smear.

**What survives at 147px (low-frequency information):**
- Large color masses (a bright red cloak reads; red stitching doesn't)
- Value separation between subject and background (light figure on dark bg, or vice versa)
- Overall silhouette shape (horns, wings, weapon angles)
- The position and brightness of the face (eyes as bright spots)
- One dominant color per creature

**What dies at 147px (high-frequency information):**
- Texture detail (scales, fabric weave, skin pores — all blur to flat color)
- Fine ornamentation (rune engravings, jewelry, buckles, filigree — invisible)
- Atmospheric effects (fog, smoke, dust motes, lens flares — become gray wash)
- Subtle color grading (teal-and-orange, split toning — becomes muddy)
- Intricate backgrounds (forests, cityscapes, interiors — becomes noise)
- Multiple light sources (rim light + fill + ambient — flattens to even illumination)

**Card art must read at card size — that's the only size players actually see it.** If the thumbnail doesn't read, the full-res version doesn't matter. This is the opposite of how AI generates — it builds detail outward, not readability inward.

**The Shadow Shapes Test — your most important quality gate:**
1. Open your generated image
2. In any image editor, desaturate it completely (grayscale)
3. Apply a heavy Gaussian blur (radius 10-15px on a 512px source)
4. You should see 2-3 distinct value shapes: a bright subject shape, a dark background shape, and maybe one accent shape (weapon, wings, magic glow)
5. If the blurred grayscale is a uniform gray blob — **reject the image**. No amount of detail will save it at card size.

This test simulates what the human eye sees at 147px. Color detail and texture are gone. Only value structure remains. If the value structure doesn't carry the composition, the card art fails.

**The Danger Words — prompts that produce beautiful, useless output:**

These words push SD toward cinematic full-screen aesthetics that collapse at card size. **Remove them from your prompts even if they seem like quality boosters:**

| REMOVE from prompts | Why it hurts at card size |
|---------------------|--------------------------|
| cinematic | Triggers wide framing, depth-of-field, atmospheric haze — all invisible at 147px |
| atmospheric | Adds fog/haze that reduces value contrast between subject and background |
| intricate details | Generates fine filigree, engravings, micro-texture that becomes noise at small display |
| hyperrealistic | Pushes toward photographic subtlety instead of bold painterly readability |
| ultra-detailed | More detail at high-res = more mud at low-res. Card art needs FEWER details, bolder |
| ethereal | Makes subjects translucent/faded — they vanish against dark backgrounds at 147px |
| moody lighting | Reduces overall brightness and contrast — produces the "dark blob" problem |
| dramatic shadows | Deep shadows eat the subject. Card frames already add darkness. |
| bokeh / depth of field | SD applies DoF to the subject edges, making the silhouette fuzzy — kills readability |
| ambient occlusion | Darkens contact points and crevices — at card size, makes everything muddy |

**ADD these readability-first modifiers instead:**

| ADD to prompts | Why it helps at card size |
|----------------|--------------------------|
| bold colors | Large flat-ish color masses that read at any size |
| strong silhouette | Forces clear subject outline against background |
| high value contrast | The subject and background have very different brightness — subject pops |
| simple background | Prevents background noise from competing with subject |
| centered composition | Subject in the center survives any crop mode |
| graphic, flat lighting | Reduces subtle gradients that turn to mud; keeps shapes readable |
| poster art | Trained on art designed for distance viewing — inherently thumbnail-friendly |
| bold shapes | Pushes SD toward large forms instead of intricate detail |

---

## PART 3: AI GENERATION SETUP

### Recommended Models on Civitai

For the dark fantasy painterly style, these SDXL checkpoint models are well-reviewed on Civitai:

| Model | Why | Notes |
|-------|-----|-------|
| **ZavyChromaXL** | Rich colors, dramatic fantasy art, sits between photorealism and stylization. ~5.0 stars, 1600+ reviews. | Best pick for dark fantasy card art. |
| **MegaFantasyArt** | Mega-merge built specifically for epic painterly fantasy art (1980s-90s fantasy illustration flavor). | New, directly relevant to card art. |
| **DreamShaper XL** | Strong painterly fantasy, good at dramatic lighting. Versatile. | Good alternative. |
| **Juggernaut XL** | Best all-rounder SDXL checkpoint. Semi-realistic with painterly quality. | Great faces. |

**LoRA to enhance style (optional):**

| LoRA | Effect |
|------|--------|
| **Painterly Fantasia** (search Civitai) | Digital painting style with visible brushwork. Trigger: `digital painting style, brushstrokes`. | 

Apply LoRAs at weight 0.5-0.8. Do NOT use MTG card-frame LoRAs — those generate the full card border, but you have your own frame system in Card2D.

### Generation Settings

| Parameter | Recommended Value | Why |
|-----------|-------------------|-----|
| **Steps** | 25 | Community sweet spot for SDXL. Below 20 is undercooked, above 30 gives diminishing returns. |
| **CFG Scale** | 5 | Safe default for SDXL. Go up to 7 max if the prompt isn't being followed. Above 7 causes harsh edges and overcooked textures. |
| **Sampler** | Euler a or DPM++ 2M Karras | Euler a is the community favorite for artistic work. DPM++ 2M is the consistent/safe option. |
| **Size** | **1152x768** (SDXL, landscape) | CRITICAL: Generate LANDSCAPE to match the card art window's ~1.5:1 aspect ratio. 768x512 is SD 1.5 era — too small for SDXL, causes degraded output. Do NOT generate square — you'll lose the top and bottom to cropping. |
| **Hires Fix** | ON: 1.5x, denoise 0.3, 15 steps | Available on Civitai's generator. Sharpens detail significantly. |
| **Seed** | Record seeds for every accepted result | So you can regenerate with tweaks, not from scratch. |
| **Batch count** | Generate 4 at a time, pick the best one | Accept rate is typically 1-in-4 for card art. |
| **DO NOT upscale beyond Hires Fix** | Skip further upscaling | You're displaying at 147px wide. Upscaling to 2048 then downscaling to 147 is wasted compute and adds VRAM cost. |

### Advanced: ControlNet Depth Maps for Forced Composition (optional but powerful)

If you're running locally (ComfyUI / A1111) and getting too many full-body or poorly-framed results, ControlNet with a depth map can force the composition:

**How it works:** You provide a simple grayscale depth map (white = close, black = far) alongside your prompt. SD generates art that follows this depth structure, guaranteeing the subject is large, centered, and properly framed regardless of what the prompt tries to do.

**Making a depth map for card art busts:**
1. Open any image editor. Create a 1152x768 canvas (matching your generation size).
2. Fill the entire canvas with black (= far away / background).
3. Paint a large white-to-light-gray oval in the upper-center, roughly where the head and shoulders should be. The oval should fill about 60-70% of the frame width.
4. The top of the oval (head) should be pure white (closest to camera). Shoulders fade to medium gray.
5. Save as PNG. Use this as your ControlNet depth input.

**Settings:** ControlNet weight 0.5-0.7 (too high = rigid/unnatural, too low = ignored). Use "depth" preprocessor type. Apply to every generation in your batch for guaranteed consistent framing.

**Why this solves the readability problem:** SD's tendency to generate tiny full-body figures or off-center compositions is overridden by the depth map. The subject WILL be large and centered because the depth map demands it.

### Post-Generation Pipeline (MANDATORY before import)

Every generated image must go through these steps before placing in `assets/creatures/`:

```
Step 1: PICK — choose best of 4 generations (face clear, silhouette strong, lighting correct)
Step 2: CROP — if generated square, center-crop to ~3:2 landscape (keep the face-centered region)
Step 3: BRIGHTNESS CHECK — open in any viewer, shrink to 150px wide. Can you see the subject?
         If it's a dark blob, increase brightness/contrast until the subject reads clearly.
Step 4: RESIZE — downscale to 512x340 using Lanczos filter (NOT nearest-neighbor, NOT bilinear)
         ImageMagick: magick convert input.png -filter Lanczos -resize 512x340^ -gravity center -extent 512x340 output.png
Step 5: STRIP METADATA — remove AI generation prompts from PNG chunks
         exiftool -all= output.png   OR   pngcrush -rem allb input.png output.png
Step 6: DEBANDING — add subtle noise to prevent color banding in dark gradients
         magick convert output.png -attenuate 0.02 +noise Gaussian final.png
Step 7: RENAME — save as {card_id}.png (lowercase, exact match to CardDB)
Step 8: PLACE — copy to assets/creatures/ (the game auto-imports on next Godot launch)
```

You can batch steps 4-6 for all images at once:
```bash
# Batch process all generated images in a folder
for f in raw_*.png; do
  id=$(echo "$f" | sed 's/raw_//;s/.png//')
  magick convert "$f" -filter Lanczos -resize 512x340^ -gravity center -extent 512x340 -attenuate 0.02 +noise Gaussian "assets/creatures/${id}.png"
done
exiftool -all= assets/creatures/*.png
```

---

## PART 4: PROMPT TEMPLATE

### Master Positive Prompt Template (copy this, fill in brackets)

```
[SUBJECT DESCRIPTION], [POSE/ACTION], close-up bust portrait,
face filling upper third of frame, head and shoulders filling the frame,
dark fantasy digital painting, warm lighting from upper left,
painterly brushwork, bold colors, strong silhouette,
dark studio, rim lighting, low key lighting,
fantasy card game illustration, high value contrast,
high contrast between subject and background,
large detailed face, expressive eyes visible, warm amber color temperature,
firelit, bold shapes, masterpiece, best quality
```

**FUNCTIONAL NOTES on this template:**
- "close-up bust portrait" and "head and shoulders filling the frame" — forces the face to be large enough to read at 147px display. Without this, SD generates full-body shots where the face is 30px and turns to mush. This works especially well combined with the landscape aspect ratio.
- "dark studio, rim lighting, low key lighting" — SD doesn't respond meaningfully to vague terms like "medium-dark background." These specific lighting terms produce clean subject-background separation: rim lighting creates a glowing edge that separates the subject, low key lighting gives selective illumination against dark. Much more reliable than trying to specify background brightness directly.
- "high value contrast" + "high contrast between subject and background" — at 147px, value separation is the ONLY way to distinguish subject from bg. Two phrases reinforce each other.
- "bold colors, strong silhouette, bold shapes" — pushes SD toward low-frequency readability (large color masses, clear outline) instead of high-frequency detail (intricate textures, filigree). These are the properties that survive at card size.
- "face filling upper third of frame" — with STRETCH_KEEP_ASPECT_COVERED, the center of the image is what survives cropping. Faces in the upper third stay visible.

⚠️ **WORDS DELIBERATELY EXCLUDED FROM THIS TEMPLATE** — do NOT add these back:
- ~~cinematic~~ → triggers wide framing and atmospheric haze, both invisible at 147px
- ~~atmospheric~~ → adds fog that reduces subject/background contrast
- ~~intricate details~~ / ~~ultra-detailed~~ → generates micro-detail that becomes noise at card size
- ~~hyperrealistic~~ → photographic subtlety is invisible at 147px; painterly boldness reads better
- ~~highly detailed~~ → replaced with "bold shapes" — we want FEWER details, BOLDER
- ~~dramatic shadows~~ → deep shadows eat the subject; the card frame already adds darkness

### Master Negative Prompt (use for ALL generations)

```
anime, 3d render, photorealistic, photograph,
text, watermark, signature, logo, card frame, card border,
bad anatomy, deformed, blurry, low quality, worst quality,
full body, wide shot, distant view, tiny figure
```

**FUNCTIONAL NOTES on negative prompt:**
- **Kept short on purpose.** Research on SDXL negative prompts (ECCV 2024) shows 5-10 targeted terms outperform long lists by ~25%. Bloated negative prompts flatten detail and introduce stiffness. Every term above is doing a specific job.
- "full body, wide shot, distant view, tiny figure" — prevents SD from generating the subject too small to read at card size. Note: negative prompts are a nudge, not a hard block. The positive prompt framing terms + landscape aspect ratio do most of the work.
- "card frame, card border" — SD sometimes generates art-within-a-frame if it recognizes "card game" in the positive prompt.
- "text, watermark, signature, logo" — SD may generate poster-style text artifacts. Essential since the positive prompt uses composition terms that overlap with poster art training data.

### Quality Tags by Platform

**For standard SDXL models (ZavyChromaXL, DreamShaper, Juggernaut, etc.):**
The `masterpiece, best quality` tags are already in the template above. Do NOT add `score_9, score_8_up` — those tags are trained into Pony Diffusion's dataset only and are meaningless noise to standard SDXL models.

**For Pony Diffusion ONLY, replace `masterpiece, best quality` with:**
```
score_9, score_8_up, score_7_up, rating_safe,
```

### ASPECT RATIO WARNING

**Generate at LANDSCAPE orientation (1152x768 for SDXL), NOT square.**

The art window in-game is ~1.6:1 landscape. If you generate square (1024x1024), Godot's STRETCH_KEEP_ASPECT_COVERED will crop ~20% off the top and bottom. Your "face in upper third" composition gets cut. Generating landscape means the FULL image appears in the card window.

---

## PART 5: CREATURE PORTRAITS — ALL 77 CARDS

### How to Read This List

Each entry has:
- **Card ID** (filename must match exactly)
- **Name** / rarity / stats / keywords
- **Has Art?** — YES means it exists (may want to regenerate later for consistency). **NO** means this is a priority.
- **Subject prompt** — the specific part to insert into the master template's [SUBJECT DESCRIPTION] and [POSE/ACTION] slots.
- **Tone** — what emotional register this creature hits (funny, grim, noble, horror, etc.)
- **Key silhouette elements** — what makes this creature recognizable at tiny card size.

---

### STARTER CREATURES (6 cards)

**1. goblin** — Goblin | Starter | 1/1 | No keywords
- Has Art? YES (woodcut style — should regenerate for consistency)
- Subject: `small green-skinned goblin, pointy ears, wicked grin, holding rusty dagger, ragged leather armor, hunched posture`
- Tone: Mischievous, funny, low-threat
- Silhouette: Pointy ears, small stature, hunched

**2. orc** — Orc | Starter | 2/2 | No keywords
- Has Art? YES (should regenerate)
- Subject: `muscular green orc warrior, tusked jaw, scarred face, wearing crude iron armor, holding heavy axe, battle-worn`
- Tone: Grim, brutish, soldier-grunt
- Silhouette: Broad shoulders, tusks, heavy weapon

**3. troll** — Troll | Starter | 2/3 | Floop: heal self
- Has Art? YES (should regenerate)
- Subject: `large troll, grey-green skin, long arms, hunched massive shoulders, regenerating wounds visible, mossy patches on skin, squinting small eyes`
- Tone: Grotesque but durable, darkly funny
- Silhouette: Oversized shoulders and arms, hunched

**4. sprite** — Sprite | Starter | 1/2 | Floop: buff adjacent ATK
- Has Art? YES (should regenerate)
- Subject: `tiny glowing fairy creature, translucent insect wings, warm golden glow emanating from body, hovering, mischievous expression, small pointed features`
- Tone: Light, magical, supportive
- Silhouette: Wings, glow, tiny proportions

**5. naga** — Naga | Starter | 3/4 | Floop: damage opposing
- Has Art? YES (should regenerate)
- Subject: `serpentine naga warrior, humanoid upper body with snake lower body, scaled skin in dark green and gold, holding trident, hooded cobra-like head crest, fierce expression`
- Tone: Exotic, dangerous, powerful
- Silhouette: Snake body, hood/crest, trident

**6. ratling** — Ratling | Starter | 2/2 | Wither, On-death, Floop
- Has Art? YES (should regenerate)
- Subject: `humanoid rat creature, mangy brown fur, clever beady eyes, wearing tattered cloak, holding poisoned blade, crouching sneaky posture, long naked tail`
- Tone: Sneaky, diseased, cunning
- Silhouette: Rat head, long tail, hunched crouch

---

### COMMON CREATURES (18 cards)

**7. ranger** — Ranger | Common | 2/4 | Floop: damage + heal
- Has Art? YES
- Subject: `hooded forest ranger, weathered face with sharp eyes, green-brown leather armor, longbow slung over shoulder, quiver visible, stubbled jaw, calm determination`
- Tone: Stoic, reliable, outdoorsman
- Silhouette: Hood, bow/quiver

**8. hound** — Hound | Common | 3/2 | Floop: random enemy damage
- Has Art? YES
- Subject: `large fierce war hound, dark brown fur, bared fangs, muscular build, scarred muzzle, leather war collar with metal studs, lunging forward aggressively`
- Tone: Aggressive, loyal, dangerous
- Silhouette: Canine shape, bared teeth, muscular

**9. shieldbearer** — Shieldbearer | Common | 1/5 | Armored, Floop: shield adjacent
- Has Art? **NO — GENERATE THIS**
- Subject: `heavily armored dwarf soldier, massive tower shield covering most of body, only eyes visible above shield rim, dented scratched iron armor, short stocky build, braced defensive stance`
- Tone: Stalwart, immovable, pure defense
- Silhouette: Huge shield dominating frame, small figure behind it

**10. pikeman** — Pikeman | Common | 2/3 | On-enter: damage, Floop: splash
- Has Art? **NO — GENERATE THIS**
- Subject: `disciplined soldier with long pike spear, simple iron helmet with nose guard, chainmail over leather, weathered face, standing at attention, pike extends upward out of frame`
- Tone: Professional, rank-and-file, disciplined
- Silhouette: Tall pike/spear extending up, helmet

**11. lookout** — Lookout | Common | 1/2 | On-enter: draw, Floop: scry
- Has Art? **NO — GENERATE THIS**
- Subject: `young scout perched high, wearing light leather armor, hand shading eyes looking into distance, spyglass hanging from belt, windswept hair, alert watchful expression`
- Tone: Youthful, alert, information-gatherer
- Silhouette: Hand-shade-eyes pose, light build

**12. militia** — Militia | Common | 1/3 | Retain, Floop: temp armored
- Has Art? **NO — GENERATE THIS**
- Subject: `common villager turned soldier, mismatched armor pieces over peasant clothes, determined but nervous expression, holding wooden shield and short sword, homemade helmet`
- Tone: Brave commoner, underdog, endearing
- Silhouette: Mismatched gear, wooden shield

**13. wolf_c** — Wolf | Common | 3/3 | On-death: damage, Floop: damage all
- Has Art? YES
- Subject: `large grey wolf, amber eyes glowing, fangs bared, thick winter fur, powerful stance, muscles tensed to pounce`
- Tone: Wild, pack predator, natural force
- Silhouette: Wolf head, raised hackles

**14. harpy** — Harpy | Common | 2/3 | Swift, Floop: relocate
- Has Art? YES
- Subject: `winged harpy, feathered arms serving as wings, taloned feet, wild windswept hair, fierce bird-like eyes, diving pose, iridescent dark feathers`
- Tone: Fast, unpredictable, aerial threat
- Silhouette: Wing-arms spread, talons

**15. thornguard** — Thornguard | Common | 1/4 | Thorns, On-death, Floop: buff thorns
- Has Art? YES
- Subject: `humanoid figure encased in living thorny vines, sharp thorns protruding from shoulders and arms, glowing green eyes behind vine mask, bark-like armor`
- Tone: Nature's revenge, painful to touch
- Silhouette: Thorns/spikes protruding everywhere

**16. raven** — Raven | Common | 2/2 | Ranged, Floop: reorder deck
- Has Art? **NO — GENERATE THIS**
- Subject: `large intelligent raven, glossy black feathers with purple sheen, piercing knowing eyes, perched on gnarled staff, one wing slightly spread, mystical aura around it`
- Tone: Mysterious, wise, ominous
- Silhouette: Bird shape, spread wing, staff perch

**17. squire_captain** — Squire Captain | Common | 2/3 | Summon, Floop: buff tokens
- Has Art? **NO — GENERATE THIS**
- Subject: `young officer in polished but worn armor, holding banner pole with tattered flag, commanding expression, short cape, clean-shaven determined face, rallying pose`
- Tone: Young leader, inspiring, growing into role
- Silhouette: Banner/flag, cape, upright posture

**18. sellsword** — Sellsword | Common | 3/3 | Wither, Floop: gain gold
- Has Art? **NO — GENERATE THIS**
- Subject: `scarred mercenary, cynical half-smile, worn but quality armor, coin pouch prominently displayed on belt, dual wielding short swords, eye patch over one eye`
- Tone: Mercenary, greedy, pragmatic
- Silhouette: Dual swords, coin pouch, eyepatch

**19. torchbearer** — Torchbearer | Common | 1/2 | Adj buff ATK, Wither, Floop
- Has Art? **NO — GENERATE THIS**
- Subject: `ragged figure holding a burning torch high overhead, fire illuminating face from below, wild eyes reflecting flames, tattered clothes, other hand dripping with something dark`
- Tone: Zealous, fire-obsessed, slightly unhinged
- Silhouette: Torch held high, dramatic uplighting

**20. gravedigger** — Gravedigger | Common | 1/3 | Passive: draw on death, Floop: raise dead
- Has Art? **NO — GENERATE THIS**
- Subject: `gaunt old man leaning on shovel, wide-brimmed hat casting shadow over face, lantern hanging from belt, dirt-stained clothes, knowing grin, cemetery fog behind`
- Tone: Creepy but practical, gallows humor
- Silhouette: Shovel, wide hat, lantern

**21. bloodhound** — Bloodhound | Common | 2/2 | On-enter: damage+draw, Floop: slay draw
- Has Art? **NO — GENERATE THIS**
- Subject: `lean hunting dog with elongated muzzle, bloodshot eyes, nose to ground tracking, reddish-brown short fur, wearing tracking collar with dangling tags, intense focused expression`
- Tone: Relentless tracker, useful, single-minded
- Silhouette: Long droopy ears, nose-down pose

**22. scavenger** — Scavenger | Common | 1/2 | On-enter: gold, Floop: gold
- Has Art? YES
- Subject: `hunched goblin-like scavenger, oversized backpack stuffed with junk, holding shiny trinket up to examine, greedy wide eyes, patched clothes, bags and pouches everywhere`
- Tone: Comic relief, treasure-obsessed
- Silhouette: Oversized backpack, hunched

**23. stone_wall** — Stone Wall | Common | 0/7 | Thorns, can't attack, Floop: shield adj
- Has Art? **NO — GENERATE THIS**
- Subject: `massive animated stone wall with face carved into it, ancient rune-covered blocks, moss growing in cracks, glowing eyes in the stonework, impenetrable and ancient`
- Tone: Immovable, ancient, protective
- Silhouette: Square/rectangular block shape, face in stone

**24. mana_sprite** — Mana Sprite | Common | 0/2 | Floop: gain mana
- Has Art? YES (JPG)
- Subject: `tiny floating blue-white spirit, crystalline translucent body, swirling mana energy orbiting around it, bright blue core, wispy ethereal trails, serene expression`
- Tone: Pure magic, helpful, fragile
- Silhouette: Small glowing orb with trails

---

### UNCOMMON CREATURES (18 cards)

**25. battle_drummer** — Battle Drummer | Uncommon | 1/4 | Adj +2 ATK, Floop: permanent buff
- Has Art? **NO — GENERATE THIS**
- Subject: `broad muscular orc holding massive war drum, drumsticks mid-strike, veins bulging on arms, tribal war paint on face, leather harness holding drum, mouth open in war cry`
- Tone: Inspiring fury, tribal, loud
- Silhouette: Large drum in front, drumsticks raised

**26. witch** — Witch | Uncommon | 2/3 | Floop: 3 damage any creature
- Has Art? YES (dark painterly — good style reference)
- Subject: `sinister witch, pale gaunt face, wild dark hair, glowing green magical energy around gnarled hands, dark robes, cackling expression, hunched over slightly`
- Tone: Sinister, powerful, slightly unhinged
- Silhouette: Wild hair, glowing hands, hunched

**27. duelist** — Duelist | Uncommon | 3/4 | On-enter: damage, Floop: drain
- Has Art? **NO — GENERATE THIS**
- Subject: `elegant fencer in a long dark coat, rapier held in en garde position, scarred handsome face, confident smirk, one hand behind back in fencing stance, feathered hat`
- Tone: Arrogant, skilled, dangerous elegance
- Silhouette: Rapier extended, fencing stance, feathered hat

**28. griffin** — Griffin | Uncommon | 3/3 | Swift, On-death: return to hand, Floop: challenge
- Has Art? YES
- Subject: `majestic griffin, eagle head with golden eyes, lion body with powerful haunches, wings spread wide, feathered mane, talons gripping rocky perch, regal bearing`
- Tone: Noble, fast, majestic
- Silhouette: Wings, eagle head, lion body

**29. bannerman** — Bannerman | Uncommon | 2/4 | Global ATK buff, Floop: buff HP
- Has Art? **NO — GENERATE THIS**
- Subject: `veteran standard bearer, large battle standard with burning meadow emblem, heavy plate armor dented from battle, grizzled bearded face, standing firm amidst chaos`
- Tone: Rallying presence, veteran leadership
- Silhouette: Large banner/standard above head

**30. berserker** — Berserker | Uncommon | 3/3 | Grows when attacking, Floop: damage+self-damage
- Has Art? YES
- Subject: `wild-eyed berserker, bare-chested with ritual scars, huge double-axe, foaming at mouth, bloodshot eyes, veins pulsing, charging forward, feral expression`
- Tone: Uncontrollable rage, terrifying, self-destructive
- Silhouette: Huge axe, bare-chested, wild hair

**31. mule** — Mule | Uncommon | 0/3 | On-enter: draw 2, Floop: filter draw
- Has Art? **NO — GENERATE THIS**
- Subject: `sturdy pack mule loaded with supplies, saddlebags overflowing with scrolls and equipment, patient tired eyes, standing stoically, harness and bridle, dusty road-worn`
- Tone: Humble, practical, surprisingly useful
- Silhouette: Animal with loaded packs

**32. sentinel** — Sentinel | Uncommon | 2/5 | Armored, Thorns, Floop: stun
- Has Art? YES
- Subject: `massive armored guardian, full plate armor covered in defensive spikes, tower shield with thorny emblem, glowing visor eyes, unmoving imposing stance`
- Tone: Impenetrable, punishing, elite defender
- Silhouette: Full plate + spikes + shield

**33. war_hound** — War Hound | Uncommon | 3/3 | Piercing, Floop: face damage
- Has Art? **NO — GENERATE THIS**
- Subject: `armored war dog, spiked collar and barding, heavier and more aggressive than regular hound, scars across muzzle, red eyes, chain partially attached, straining forward`
- Tone: Weaponized beast, relentless, piercing through
- Silhouette: Armored dog, spikes, chain

**34. necromancer** — Necromancer | Uncommon | 1/3 | On-death: summon, Floop: kill adj + summon
- Has Art? YES
- Subject: `robed necromancer, skull-topped staff, pale skin, dark circles under eyes, green necromantic energy swirling, skeletal hand emerging from shadow beside them`
- Tone: Dark magic, death-dealer, sinister but slightly theatrical
- Silhouette: Skull staff, robes, swirling energy

**35. bloodsworn** — Bloodsworn | Uncommon | 4/4 | Sacrifice to play, Floop: damage+self-damage
- Has Art? YES (JPG)
- Subject: `blood-oath warrior, ritual scarification on chest, crimson war paint, curved sacrificial blade, eyes burning with zealous devotion, blood dripping from self-inflicted wound`
- Tone: Fanatical devotion, power through pain
- Silhouette: Ritual scars, raised blade, blood

**36. blood_pyre** — Blood Pyre | Uncommon | 1/3 | On-death: mana, Floop: blood sacrifice
- Has Art? **NO — GENERATE THIS**
- Subject: `burning sacrificial pyre creature, humanoid shape made of flickering crimson flames and smoldering embers, dark smoke rising, ember-filled eye sockets, charred bone visible within fire`
- Tone: Self-sacrifice, fuel for others, burning purpose
- Silhouette: Humanoid flame shape, smoke rising

**37. copycat** — Copycat | Uncommon | 0/1 | On-enter: copy friendly, Floop: copy opposing floop
- Has Art? **NO — GENERATE THIS**
- Subject: `shapeshifting creature mid-transformation, features melting and reforming, one half showing original form (pale featureless face), other half mimicking another creature, mercury-like reflective skin`
- Tone: Uncanny, unsettling, adaptive
- Silhouette: Amorphous, mid-shift, unsettled form

**38. stray_cat** — Stray Cat | Uncommon | 1/1 | On-enter: look top 3, Floop: spawn token
- Has Art? **NO — GENERATE THIS**
- Subject: `scruffy alley cat with knowing eyes, sitting upright with tail curled, one ear torn, patchy fur, looking directly at viewer with unnervingly intelligent expression, slight smirk`
- Tone: Deceptively useful, street-smart, independent
- Silhouette: Cat sitting upright, torn ear

**39. mirror_knight** — Mirror Knight | Uncommon | 2/3 | On-enter: copy keywords, Floop: swap ATK
- Has Art? **NO — GENERATE THIS**
- Subject: `knight in reflective mirror-polished armor, shield that acts as perfect mirror showing distorted reflection, blank featureless helm reflecting surroundings, sword with mirrored blade`
- Tone: Enigmatic, adaptive, turns enemy strength against them
- Silhouette: Mirror-bright armor, reflective shield

**40. vengeful_spirit** — Vengeful Spirit | Uncommon | 0/1 | ATK per face damage, Floop: unleash
- Has Art? YES
- Subject: `translucent ghostly figure, rage-filled hollow eyes, ethereal tattered robes flowing upward like smoke, spectral chains, growing brighter and more defined as anger builds`
- Tone: Building rage, tragic, explosive potential
- Silhouette: Ghost shape, flowing upward, chains

**41. iron_bastion** — Iron Bastion | Uncommon | 1/7 | Armored, reduce face damage, Floop: armored all
- Has Art? YES
- Subject: `massive iron golem, riveted plates, fortress-like proportions, shield built into arm, glowing furnace visible through visor slits, immovable wide stance, steam venting`
- Tone: Industrial, unstoppable, fortress-made-mobile
- Silhouette: Massive rectangular frame, built-in shield

**42. leyline_conduit** — Leyline Conduit | Uncommon | 0/3 | Passive: +1 mana/turn, Floop: +2 mana
- Has Art? **NO — GENERATE THIS**
- Subject: `floating crystalline construct, geometric angular crystal formation, pulsing blue mana energy flowing through visible internal channels, arcane runes orbiting around it, blue-white glow`
- Tone: Pure magical utility, arcane, alien
- Silhouette: Geometric crystal, glowing, floating

---

### RARE CREATURES (17 cards)

**43. dragon_hatchling** — Dragon Hatchling | Rare | 4/5 | On-enter: AoE, Wither, Floop: damage all
- Has Art? YES
- Subject: `young dragon, dark blue-green scales, oversized wings for its body, sharp teeth in juvenile snarl, crouching low about to pounce, ember dripping from nostrils`
- Tone: Dangerous even young, growing threat
- Silhouette: Wings, dragon head, crouching

**44. royal_guard** — Royal Guard | Rare | 2/6 | Adj protection, grows when hit, Floop: redirect
- Has Art? YES
- Subject: `elite royal guard in ornate gold-trimmed plate armor, royal crest on breastplate, halberd held upright, stoic noble expression, cape, protecting stance`
- Tone: Duty, sacrifice, elite protector
- Silhouette: Halberd, ornate armor, cape

**45. assassin** — Assassin | Rare | 5/1 | Swift, Piercing, dies end of turn, Floop: execute
- Has Art? YES
- Subject: `masked assassin in dark leather, twin daggers dripping poison, only eyes visible above face wrap, lithe athletic build, caught mid-leap, shadowy blur effect`
- Tone: Lethal glass cannon, one perfect strike
- Silhouette: Twin daggers, mask, leaping pose

**46. hydra** — Hydra | Rare | 2/5 | Attacks all lanes, Floop: grow per enemies
- Has Art? YES
- Subject: `multi-headed hydra, four serpentine necks each with a fanged head, massive scaled body, each head facing a different direction, dark green and black scales`
- Tone: Overwhelming, multi-target menace
- Silhouette: Multiple heads on long necks

**47. summoner** — Summoner | Rare | 1/3 | Summon, Floop: summon random lane
- Has Art? **NO — GENERATE THIS**
- Subject: `robed summoner with outstretched hands, glowing summoning circle below, spectral creatures partially materializing around them, ornate ritual staff floating nearby, intense concentration`
- Tone: Master of minions, arcane power, never alone
- Silhouette: Outstretched hands, summoning circle glow, floating staff

**48. paladin** — Paladin | Rare | 3/5 | Last Stand, Adj ATK buff, Floop: heal all
- Has Art? YES (flaming knight — good quality but full-body, should be bust)
- Subject: `holy paladin, golden plate armor with sun emblem, blessed warhammer, healing light radiating from raised hand, stern righteous expression, divine halo glow`
- Tone: Righteous, protective, divine champion
- Silhouette: Warhammer, glowing hand, sun emblem

**49. corpse_eater** — Corpse Eater | Rare | 2/4 | Grows on ally death, Floop: devour adjacent
- Has Art? YES (JPG)
- Subject: `grotesque bloated creature, oversized maw full of teeth, pale sickly skin, growing larger and more distended, pieces of consumed creatures visible, drooling, hungry eyes`
- Tone: Horrifying, parasitic, growing threat
- Silhouette: Oversized mouth, bloated body

**50. ironclad_veteran** — Ironclad Veteran | Rare | 3/5 | On-enter: ATK per cards played, Floop: discount
- Has Art? **NO — GENERATE THIS**
- Subject: `grizzled veteran warrior in heavy battle-scarred plate armor, grey streaked beard, experienced calculating eyes, massive sword resting on shoulder, medals and trophies on belt`
- Tone: War-weary expertise, every battle makes him stronger
- Silhouette: Heavy plate, huge sword on shoulder, beard

**51. kindling** — Kindling | Rare | 0/1 | Floop: damage opposing
- Has Art? **NO — GENERATE THIS**
- Subject: `tiny smoldering stick figure creature made of burning twigs and leaves, small flickering flame for a head, ember eyes, fragile but persistent, leaving scorch marks`
- Tone: Humble but thematic, literally fuel for the burning meadow
- Silhouette: Stick figure, flame head, tiny

**52. doppelganger** — Doppelganger | Rare | 1/1 | On-enter: copy last dead, Floop: become copy
- Has Art? YES (JPG — Vrubel painting, should regenerate)
- Subject: `featureless humanoid with smooth grey skin, no face yet — surface rippling as it prepares to take a new form, ghostly afterimages of other creatures flickering around it`
- Tone: Identity theft, uncanny, threatening potential
- Silhouette: Featureless humanoid, rippling surface

**53. vampire_lord** — Vampire Lord | Rare | 3/5 | Regenerate, heals on kill, Floop: drain
- Has Art? YES
- Subject: `aristocratic vampire, pale porcelain skin, blood-red eyes, sharp fangs visible in cruel smile, high-collared cape, dark noble clothing, blood mist swirling around hands`
- Tone: Elegant horror, predatory nobility
- Silhouette: High collar/cape, sharp features, blood mist

**54. chaos_imp** — Chaos Imp | Rare | 2/2 | On-enter: random spell, Floop: mill damage
- Has Art? YES (JPG — Vrubel painting, should regenerate)
- Subject: `small manic demon, wild grinning face with too many teeth, tiny bat wings, crackling chaotic energy between hands, multiple conflicting spell effects around it, gleeful expression`
- Tone: Chaotic comedy, unpredictable, dangerously fun
- Silhouette: Bat wings, manic grin, chaotic energy

**55. warden_of_graves** — Warden of Graves | Rare | 2/4 | Double on-death, Floop: graveyard damage
- Has Art? YES (JPG)
- Subject: `towering skeletal figure in tattered ceremonial robes, lantern hanging from bone staff containing trapped green souls, hollow eye sockets with faint green glow, guardian of the dead`
- Tone: Deathly authority, the graveyard given form
- Silhouette: Bone staff, soul lantern, skeletal

**56. siege_golem** — Siege Golem | Rare | 5/6 | Only face damage, Floop: ranged damage
- Has Art? YES
- Subject: `enormous stone golem designed as siege weapon, boulder fists, fortress-wall proportions, catapult mechanism visible on shoulder, single glowing eye, cracks filled with lava`
- Tone: Weapon of war, city-breaker, unstoppable force
- Silhouette: Massive proportions, catapult shoulder

**57. war_titan** — War Titan | Rare (4-cost) | 6/8 | Armored, Floop: AoE damage
- Has Art? YES
- Subject: `colossal armored giant, ornate heavy plate covering massive frame, wielding giant mace, armored visor revealing only glowing eyes, ground cracking under weight`
- Tone: End-game power fantasy, overwhelming
- Silhouette: Huge frame, giant weapon

**58. archmage** — Archmage | Rare (4-cost) | 3/5 | On-enter: draw 2, Floop: targeted damage
- Has Art? YES (JPG)
- Subject: `ancient archmage, long white beard, ornate star-patterned robes, multiple floating spell tomes orbiting, crackling energy between outstretched fingers, wise stern expression`
- Tone: Peak magical power, scholarly authority
- Silhouette: Robes, floating books, beard, magic hands

**59. doom_knight** — Doom Knight | Rare (4-cost) | 5/6 | Swift, Piercing, Floop: self-buff
- Has Art? YES (tribal warrior style — should regenerate)
- Subject: `death knight in jet-black full plate, flaming greatsword, skull visor with hellfire eyes, dark cape flowing, mounted on spectral steed (visible in bust), aura of dread`
- Tone: Ultimate warrior, death incarnate
- Silhouette: Flaming sword, skull helm, dark plate

---

### ENEMY CREATURES (18 cards)

Enemy creatures should look visually distinct from player creatures. Use these modifiers in the prompt:
- Add `menacing, hostile, enemy creature, dark red accent lighting` to the base prompt
- Backgrounds lean slightly more red/crimson than player creature backgrounds
- Expressions are more aggressive/hostile

**60. e_goblin** — Goblin (Enemy) | Act 1 | 2/2
- Has Art? YES
- Subject: `hostile goblin raider, red war paint on face, crude spiked club, snarling expression, more aggressive than player goblin, tattered red cloth`

**61. e_scout** — Scout (Enemy) | Act 1 | 2/3
- Has Art? YES
- Subject: `enemy scout, dark leather armor, crossbow readied, calculating cold eyes, bandana covering lower face, crouching in shadows`

**62. e_brute** — Brute (Enemy) | Act 1 | 3/3
- Has Art? YES
- Subject: `massive hulking brute, oversized fists, scarred brutal face, crude spiked armor, chains wrapped around forearms, growling`

**63. e_archer** — Archer (Enemy) | Act 1 | 2/3 | On-enter: random player damage
- Has Art? **NO — GENERATE THIS**
- Subject: `enemy archer on elevated position, dark hooded cloak, recurve bow drawn and aimed at viewer, cold precise eyes, quiver of black-fletched arrows, hostile focused expression`
- Silhouette: Drawn bow aimed at viewer, hood

**64. e_golem** — Golem (Enemy) | Act 1 | 2/4 | Armored
- Has Art? YES
- Subject: `enemy stone golem, rough-hewn rock body, glowing red rune on chest, slow but unstoppable, crumbling edges, ancient and hostile`

**65. e_wind_harpy** — Wind Harpy (Enemy) | Act 1 | 3/2 | Swift
- Has Art? YES
- Subject: `hostile wind harpy, darker feathers than player harpy, shrieking face, razor talons extended, diving attack pose, wind vortex around wings`

**66. e_cultist** — Cultist (Enemy) | Act 2 | 3/3
- Has Art? YES
- Subject: `dark cultist in black hooded robes, ritual dagger, face hidden in shadow with only glowing eyes visible, occult symbols on robes, dark purple energy`

**67. e_dark_priest** — Dark Priest (Enemy) | Act 2 | 2/4 | Regenerate
- Has Art? YES
- Subject: `corrupt priest, tattered holy vestments turned dark, unholy book, wounds healing visibly, sickly green healing aura, corrupted righteous face`

**68. e_enforcer** — Enforcer (Enemy) | Act 2 | 4/3 | Swift
- Has Art? YES
- Subject: `armored enforcer, heavy executioner's blade, faceless iron mask, bulky frame, dark steel armor with bloodstains, menacing advancing stance`

**69. e_bog_lurker** — Bog Lurker (Enemy) | Act 2 | 2/5
- Has Art? YES
- Subject: `swamp creature emerging from murky water, covered in algae and muck, long clawed arms, amphibian eyes, partially submerged, dripping bog water`

**70. e_bone_knight** — Bone Knight (Enemy) | Act 2 | 3/4 | On-death: summon 2/2
- Has Art? **NO — GENERATE THIS**
- Subject: `skeletal knight in rusted ancient armor, wielding notched longsword, hollow eye sockets with blue soulfire, tattered cape, pieces of bone visible through armor gaps, commanding undead authority`
- Silhouette: Skeleton in armor, sword, tattered cape

**71. e_fire_elemental** — Fire Elemental (Enemy) | Act 3 | 4/3
- Has Art? **NO — GENERATE THIS**
- Subject: `raging fire elemental, humanoid shape made of living flame, molten rock core visible, heat distortion around it, white-hot eyes, flame tendrils reaching outward aggressively, charring ground beneath`
- Silhouette: Humanoid flame, reaching tendrils

**72. e_headsman** — Headsman (Enemy) | Act 3 | 4/4
- Has Art? YES
- Subject: `hooded executioner, massive axe, muscular bare arms, leather hood with only jaw visible, blood-stained apron, stoic efficient killer`

**73. e_drake** — Drake (Enemy) | Act 3 | 3/4 | Piercing
- Has Art? YES
- Subject: `smaller aggressive drake, wingless dragon-kin, rows of sharp teeth, armored scales, charging low to ground, spines along back, penetrating red eyes`

**74. e_elder_dragon** — Elder Dragon (Enemy) | Act 3 | 5/6 | Wither
- Has Art? YES
- Subject: `ancient dragon, enormous scaled head close-up filling frame, one massive eye dominating, centuries of scars and worn scales, withering breath visible as dark miasma`

**75. e_warden_champ** — Iron Champion (Boss) | Act 1 | 4/5 | Swift
- Has Art? **NO — GENERATE THIS**
- Subject: `champion of the iron warden, elite full plate armor with gold inlay, speed despite heavy armor, glowing blue visor, dual wielding enchanted blades, imposing boss presence, extra ornate and powerful`
- **Make this extra impressive — it's a boss creature.** Generate at higher detail.
- Silhouette: Dual blades, ornate heavy armor, boss-scale presence

**76. e_collector_champ** — Collector's Champion (Boss) | Act 2 | 4/5 | Armored
- Has Art? **NO — GENERATE THIS**
- Subject: `champion of the collector, covered in stolen trophies and relics, patchwork armor made from defeated foes' gear, multiple weapons strapped to body, unhinged collector's glee, armored in plunder`
- **Boss creature — make it imposing and visually rich.**
- Silhouette: Multiple trophies/weapons adorning body

**77. e_devil_champ** — Devil's Champion (Boss) | Act 3 | 5/6 | Last Stand
- Has Art? YES (JPG)
- Subject: `demonic champion, crimson skin, massive curved horns, burning eyes, infernal heavy armor with living flame details, giant flaming sword, wings partially visible, ultimate boss threat`
- Silhouette: Horns, burning sword, wings

---

## PART 6: SPELL ILLUSTRATIONS (45 cards)

All 45 spell illustrations already exist. They are abstract magical effects, NOT character portraits. If regenerating for consistency, follow these rules:

### Spell Art Composition Rules

Spell art depicts **the magical effect at peak energy** — not a caster, not a symbol.

**Shape language by spell type:**
- **Damage spells** → Sharp, angular, explosive. Radial burst, pointed rays, shattering. Hot colors: orange-red core, dark edges.
- **Heal spells** → Soft, rounded, rising. Gentle glow, orbs, halos. Cool-warm: green-white, gentle luminance.
- **Buff spells** → Geometric, ordered, enveloping. Rings, runes, shields. Gold shimmer, warm embrace.
- **Debuff/Dark spells** → Organic, irregular, descending. Drips, cracks, tendrils, smoke. Sickly purple-green, cold.
- **Utility spells** → Swirling, directional, arcane. Spirals, arrows, symbols. Teal-blue, mystical.

**One dominant color per spell** — at card size, the color IS the spell's identity.

### Spell Prompt Template

```
[EFFECT DESCRIPTION], magical energy effect, fantasy spell illustration,
dark background, dramatic lighting, high contrast, glowing energy,
painterly digital art, card game spell art, no character, no person,
abstract magical effect, masterpiece, best quality
```

### Complete Spell List (all have art — reference only)

| ID | Name | Type | Visual Direction |
|----|------|------|-----------------|
| strike | Strike | Damage 3 | Sharp blade slash, white-orange |
| fireball | Fireball | Face damage 2 | Classic fireball, orange-yellow core |
| slash | Slash | Damage 4 | Sword slash arc, steel-white |
| shield_wall | Shield Wall | Buff HP +3 | Golden shield barrier, protective |
| war_cry | War Cry | Buff all ATK | Gold shockwave, rallying energy |
| provision | Provision | Draw 2 | Swirling cards/scrolls, blue-gold |
| patch_up | Patch Up | Heal 3 | Green healing light, gentle glow |
| flame_bolt | Flame Bolt | Face damage 3 | Fire bolt projectile, orange streak |
| shove | Shove | Move + damage | Force push effect, blue-white |
| gambit | Gambit | Discard/draw | Swirling cards, chaotic gold-purple |
| blood_tithe | Blood Tithe | Face damage + self damage | Dark red energy extraction |
| reckless_charge | Reckless Charge | Damage + draw + self damage | Red charging energy, aggressive |
| quick_shot | Quick Shot | 1 damage any | Small precise arrow/bolt, quick |
| scrap | Scrap | Discard + mana | Dissolving card into blue mana |
| barricade | Barricade | Buff HP, can't attack | Stone wall forming, grey-gold |
| adrenaline | Adrenaline | Mana + draw, exhaust | Red-gold energy surge, intense |
| concentrate | Concentrate | Discard 2, gain 2 mana | Blue mana condensing, focused |
| smite_spell | Smite | 6 damage, exhaust | Holy lightning strike, white-gold |
| inspire | Inspire | All +2 ATK, exhaust | Golden aura spreading outward |
| ambush | Ambush | 2 to all enemies | Multiple arrows/blades raining down |
| second_wind | Second Wind | Full heal + ATK | Green-gold revival energy |
| reposition | Reposition | Swap lanes + buff | Arcane swap effect, teal arrows |
| lightning | Lightning | Creature + face damage | Lightning bolt, electric blue-white |
| offering | Offering | Sacrifice for mana, exhaust | Dark altar glow, red-to-blue |
| grave_pact | Grave Pact | Death protection, retain | Green necromantic seal, death ward |
| fuel_the_pyre | Fuel the Pyre | Sacrifice → ATK damage | Creature dissolving into fire aimed at target |
| battle_hymn | Battle Hymn | All +1 ATK permanent | Golden musical notes/waves |
| pillage | Pillage | Damage, gold if kill | Gold coins scattering from impact |
| echo_spell | Echo | Copy last spell, exhaust | Mirror/reflection effect, teal |
| bloodletting | Bloodletting | Lose HP, gain mana | Blood turning to blue mana drops |
| turbo | Turbo | Gain mana, add curse | Blue energy burst with dark tendril |
| recycle | Recycle | Exhaust card, gain mana | Card dissolving into mana spiral |
| earthquake | Earthquake | 3 to ALL, exhaust | Ground cracking, brown-orange shockwave |
| kings_command | King's Command | Massive buff, exhaust | Royal golden decree energy, crown |
| unholy_bargain | Unholy Bargain | Draw 3, take 3, exhaust | Dark deal, purple-red vortex |
| mass_grave | Mass Grave | Kill all friendly, face damage | Dark pit opening, red-black |
| dark_pact | Dark Pact | Buff all, self damage | Sinister eye/seal, purple-teal |
| war_chant | War Chant | Discard, gain mana | Tribal drum energy, amber waves |
| grave_robbery | Grave Robbery | Return dead creature, exhaust | Hand reaching from grave, green |
| cataclysm | Cataclysm | Strongest ATK hits all, exhaust | Massive destruction wave, orange-red |
| soul_swap | Soul Swap | Swap creature ATK/HP | Two-colored swirl (red↔green), yin-yang |
| apocalypse | Apocalypse | Kill ALL, face damage, exhaust | Total destruction, white-hot center |
| inferno | Inferno | 4 to all enemies + face, exhaust | Massive firestorm, white-orange-red |
| overwhelming_force | Overwhelming Force | All +3 ATK perm, exhaust | Golden power explosion, overwhelming |

---

## PART 7: BATCH PRODUCTION WORKFLOW

### Step-by-Step Process

**Phase 1: Style Lock (do this FIRST)**

1. Pick ONE checkpoint model and stick with it for ALL creatures.
2. Generate 3-4 test images using the goblin, paladin, and witch prompts.
3. Adjust your prompt template until all 3 look like they belong in the same game.
4. Record your exact settings (model, LoRAs, CFG, steps, sampler, negative prompt).
5. This is your "locked style." Don't change it mid-production.

**Phase 2: Generate Missing Creatures (29 cards)**

Priority order (most impactful first):
1. Boss enemies: e_warden_champ, e_collector_champ (these appear at act climaxes)
2. Common creatures that players see constantly: shieldbearer, pikeman, lookout, militia, raven, squire_captain, sellsword, torchbearer, gravedigger, bloodhound, stone_wall
3. Uncommon creatures: battle_drummer, duelist, bannerman, mule, war_hound, blood_pyre, copycat, stray_cat, mirror_knight, leyline_conduit
4. Rare creatures: summoner, ironclad_veteran, kindling
5. Enemy creatures: e_archer, e_bone_knight, e_fire_elemental

For each card:
1. Copy the master positive prompt template
2. Insert the subject description from this document
3. Apply the master negative prompt
4. Generate 4 variations
5. Pick the best one (clear face, good silhouette, correct framing)
6. If none are good, adjust the subject description and regenerate
7. Save as `{card_id}.png` at 1024x1024

**Phase 3: Post-Processing (MANDATORY — for each image)**

This is not optional polish — skipping these steps causes real in-game problems.

1. **Shadow Shapes Test (DO THIS FIRST — before any other processing)**
   - Open the raw generation in any editor
   - Desaturate to grayscale
   - Apply Gaussian blur at radius 10-15px (on 768px source)
   - You should see 2-3 distinct value zones: a bright subject, a dark background, maybe one accent (weapon glow, wings)
   - If the blurred grayscale is a uniform gray blob → **REJECT. Regenerate.** No post-processing saves a bad value structure.
   - ImageMagick one-liner to check: `magick convert input.png -colorspace Gray -blur 0x12 shadow_test.png`
   
2. **Crop** — if generated square, center-crop to ~3:2 landscape. Keep the region where the face is.

3. **Brightness check** — shrink to 150px wide in any viewer. Can you clearly see the subject against the background? If it's a dark smear, increase brightness until the subject pops. Target 40-50% average brightness. (The card frame provides the dark mood — the art itself should be READABLE.)

4. **Grayscale readability test** — convert to grayscale and view at 150px wide. The subject must still be identifiable WITHOUT color. At card size, the eye relies much more on value (light/dark) than on color to distinguish shapes. If the creature vanishes in grayscale, it will be hard to read on the card even in color.
   - `magick convert input.png -colorspace Gray -resize 150x grayscale_test.png`

5. **Color correct** — warm up if too cool. Target warm amber cast (~4000K). Add `+10 saturation` if it looks washed out. Bold, slightly oversaturated colors read better at card size than subtle, desaturated ones.

6. **Verify lighting** — highlight should be upper-left. If reversed, mirror horizontally: `magick convert in.png -flop out.png`

7. **Resize to 512x340** using Lanczos: `magick convert in.png -filter Lanczos -resize 512x340^ -gravity center -extent 512x340 out.png`. This prevents aliasing at display size and saves ~80% VRAM.

8. **Add noise for debanding**: `magick convert out.png -attenuate 0.02 +noise Gaussian final.png`. Dark gradient backgrounds WILL band without this.

9. **Strip metadata**: `exiftool -all= final.png`. Removes your prompts from shipping with the game.

10. **Rename** to `{card_id}.png` (lowercase, exact match).

11. **Final card-size test (the test that actually matters)** — open the 512x340 file, shrink your viewer to show it at ~150px wide. Check ALL of these:
   - Can you tell what creature this is from the **silhouette alone** (shape, not detail)?
   - Is the face recognizable (eyes visible as bright spots, expression readable)?
   - Does the subject **clearly separate** from the background in value (not just color)?
   - Is there ONE dominant color that identifies this creature?
   - Could you tell this card apart from the other 76 creatures at this size?
   - If ANY answer is no → **regenerate from scratch, don't try to save it in post**. A beautiful full-res image that fails at card size is useless.

**Phase 4: Consistency Pass (after all images generated)**

Thumbnail ALL creature art side by side at ~100px wide. Check:

- [ ] Same lighting direction on every portrait? (upper-left)
- [ ] Same approximate color temperature? (warm amber)
- [ ] Same level of detail / painterly quality?
- [ ] No anime-style outliers mixed with painterly ones?
- [ ] Backgrounds all similarly dark and non-distracting?
- [ ] Same approximate brightness level? (no dark blobs mixed with bright ones)
- [ ] All files at 512x340? (no 4000px outliers eating VRAM)
- [ ] All filenames lowercase and matching card_id?
- [ ] Metadata stripped from all files?

Regenerate any that don't match. A single inconsistent card is more noticeable than you think.

---

## PART 8: COMMON PROBLEMS & FIXES (Thematic + Functional)

### AI Generation Problems

| Problem | Fix |
|---------|-----|
| Hands look wrong | Add "hands hidden" or "hands behind back" to prompt. Or crop below hands. Card art is bust-only anyway. At 147px display, bad hands are invisible. |
| Too anime / cel-shaded | Strengthen negative prompt: add "anime, cel shading, flat colors, line art". Add "oil painting, realistic lighting" to positive. |
| Too photorealistic | Add "painting, illustrated, painterly brushwork" to positive. Add "photograph, photo, 3d render" to negative. |
| Background too detailed | Add "simple dark background, no background detail, dark atmospheric background" to positive. Add "detailed background, landscape, scenery" to negative. |
| Wrong lighting direction | Add "lighting from upper left, rim light from right" to positive. Or mirror the image horizontally in post (ImageMagick: `magick convert in.png -flop out.png`). |
| All creatures look same-face | Vary the species/race heavily. Specify unique facial features per creature. Use reference to real animals for beast-type creatures. |
| Colors too cool / blue | Add "warm amber lighting, golden hour, firelit, warm color temperature" to positive. Add "cold, blue tint, cool lighting" to negative. |
| Creature doesn't fill frame | Add "close-up portrait, filling the frame, tight crop" to positive. Add "full body, wide shot, distant" to negative. |
| Multiple characters appearing | Add "solo, single character, one creature" to positive. Add "multiple characters, crowd, group" to negative. |
| SD generates a card frame / border in the image | Add "card frame, card border, frame, border, ornate border" to negative prompt. This happens when "card game" is in the positive prompt. |

### The 7 Ways AI Art Looks "Beautiful" But Fails at Card Size

These are the specific failure modes where the AI produces impressive full-resolution images that are completely non-functional at 147px display. Learn to recognize these BEFORE accepting a generation.

| # | Failure Mode | What it looks like at full-res | What it looks like at 147px | How to prevent |
|---|-------------|-------------------------------|----------------------------|----------------|
| 1 | **The Cinematic Wasteland** | Wide establishing shot, creature small in a vast landscape, atmospheric depth | Gray-brown rectangle. Subject is 20px and invisible. | Never use "cinematic" or "wide shot". Force "close-up bust portrait, filling the frame". |
| 2 | **The Detail Trap** | Gorgeous intricate armor engravings, scale textures, fabric weave | Muddy noise. Brain can't parse 500 micro-details at 147px. Looks worse than flat color. | Use "bold shapes" not "intricate details". Card art needs 3-5 large shapes, not 500 small ones. |
| 3 | **The Atmosphere Fog** | Moody fog, volumetric light rays, dust motes, lens flare — very cinematic | Gray wash over everything. Subject and background merge. Zero value contrast. | Remove "atmospheric", "moody", "foggy" from prompts. Add "high value contrast, simple background". |
| 4 | **The Dark Hole** | Dramatic dark shadows, chiaroscuro, noir lighting — very artistic | Solid black rectangle. You can't see ANYTHING. The card frame adds its own darkness on top. | "Medium-dark background" not "dark". Target 40-50% avg brightness. Frame provides the mood. |
| 5 | **The Tonal Twin** | Subject and background are different colors but same brightness/value | At 147px, human eye relies on VALUE, not hue. Same-value subject and bg merge completely. | Check grayscale version. Subject must be 20-30% brighter than background in grayscale. |
| 6 | **The Miniature** | Full-body pose with detailed environment — a tiny perfect figure in a room | At card size the "figure" is 30px tall. Face is 8px. It's a stick figure. | "bust portrait", "head and shoulders only". Face must be 30-40% of image width. |
| 7 | **The Smooth Fade** | Soft gradients from subject into background, no hard edges, painterly blending | Silhouette dissolves. Can't tell where creature ends and background begins. No identifiable shape. | "Strong silhouette, high contrast edges". Subject outline should be a hard value break, not a gradient. |

**The universal fix:** After generating, ALWAYS shrink to 150px wide before judging. If it doesn't read at 150px, it won't read on the card. No exception.

### Functional / In-Game Problems

| Problem | Cause | Fix |
|---------|-------|-----|
| **Card art is a dark unreadable blob** | Image too dark (20-30% avg brightness). At 147px, dark = invisible. | Post-process: increase brightness +15-20%. Target 40-50% avg brightness. The frame provides dark mood. |
| **Face is blurry/mushy on card** | Face too small in source image. Below ~100px in source = unreadable at display size. | Generate closer crop. Face must be 30-40% of image width minimum. Head+shoulders only. |
| **Art looks different in Godot than in image viewer** | Embedded ICC color profile (Display-P3, AdobeRGB). Godot ignores profiles and reads raw values as sRGB. | Strip ICC profile: `exiftool -all= *.png` |
| **Art has shimmering/aliasing artifacts on card** | Source image too large (1500px+) displayed at 147px with no mipmaps. | Pre-resize to 512x340 with Lanczos filter before import. |
| **Card shows placeholder gradient instead of art** | Filename doesn't match card_id. `Shieldbearer.png` ≠ `shieldbearer.png`. | Use exact lowercase card_id. Check CardDB.gd for the `id` field. |
| **Dark gradient bands visible in backgrounds** | 8-bit color quantization + dark gradients + downscaling. | Add +2% Gaussian noise in post-processing. Breaks up banding. |
| **Art looks cropped wrong — face cut off** | Generated at 1:1 square, displayed in 1.6:1 landscape window. STRETCH_KEEP_ASPECT_COVERED crops top/bottom. | Generate at landscape ratio (768x512) so full image shows in window. |
| **Colors shifted between cards — some warm, some cool** | Generated in different sessions with different settings/models. | Lock model + LoRA + prompt prefix + sampler + CFG for ALL cards. One session. |
| **Game ships with AI prompts in metadata** | SD embeds prompts in PNG tEXt chunks. Extractable with ExifTool. | Strip before import: `exiftool -all= assets/creatures/*.png` |
| **Game takes too long to load / uses too much memory** | 100+ images at 1500x2000 = 1.1 GB VRAM just for card art. | Pre-resize all to 512x340. Total: ~70 MB VRAM. |
| **Image works in editor but breaks on export** | Case sensitivity. Windows ignores case, Linux doesn't. `e_Archer.png` fails on Linux. | All filenames lowercase. Match card_id exactly. |

---

## PART 9: SUMMARY — THE 29 MISSING CREATURE PORTRAITS

Quick reference list for the generation queue:

### Player Creatures Missing Art (24)

| # | Card ID | Name | Rarity | Key Visual |
|---|---------|------|--------|------------|
| 1 | shieldbearer | Shieldbearer | Common | Dwarf behind massive tower shield |
| 2 | pikeman | Pikeman | Common | Soldier with long pike, iron helmet |
| 3 | lookout | Lookout | Common | Young scout shading eyes, spyglass |
| 4 | militia | Militia | Common | Villager in mismatched armor |
| 5 | raven | Raven | Common | Large intelligent raven on staff |
| 6 | squire_captain | Squire Captain | Common | Young officer with battle banner |
| 7 | sellsword | Sellsword | Common | Scarred mercenary, dual swords, eyepatch |
| 8 | torchbearer | Torchbearer | Common | Zealot holding torch high, wild eyes |
| 9 | gravedigger | Gravedigger | Common | Gaunt man with shovel and lantern |
| 10 | bloodhound | Bloodhound | Common | Lean tracking dog, nose down |
| 11 | stone_wall | Stone Wall | Common | Animated stone wall with face |
| 12 | battle_drummer | Battle Drummer | Uncommon | Orc with massive war drum |
| 13 | duelist | Duelist | Uncommon | Elegant fencer, rapier, feathered hat |
| 14 | bannerman | Bannerman | Uncommon | Veteran with large battle standard |
| 15 | mule | Mule | Uncommon | Pack mule loaded with supplies |
| 16 | war_hound | War Hound | Uncommon | Armored war dog, spiked collar |
| 17 | blood_pyre | Blood Pyre | Uncommon | Humanoid shape of crimson flame |
| 18 | copycat | Copycat | Uncommon | Shapeshifter mid-transformation |
| 19 | stray_cat | Stray Cat | Uncommon | Scruffy alley cat, knowing eyes |
| 20 | mirror_knight | Mirror Knight | Uncommon | Knight in mirror-polished armor |
| 21 | leyline_conduit | Leyline Conduit | Uncommon | Floating crystal with blue mana channels |
| 22 | summoner | Summoner | Rare | Robed mage with summoning circle |
| 23 | ironclad_veteran | Ironclad Veteran | Rare | Grizzled warrior, massive sword on shoulder |
| 24 | kindling | Kindling | Rare | Tiny burning stick figure creature |

### Enemy Creatures Missing Art (5)

| # | Card ID | Name | Act | Key Visual |
|---|---------|------|-----|------------|
| 25 | e_archer | Archer | 1 | Hooded archer, bow aimed at viewer |
| 26 | e_bone_knight | Bone Knight | 2 | Skeleton in rusted armor, sword |
| 27 | e_fire_elemental | Fire Elemental | 3 | Humanoid living flame |
| 28 | e_warden_champ | Iron Champion (BOSS) | 1 | Elite dual-blade knight, ornate |
| 29 | e_collector_champ | Collector's Champion (BOSS) | 2 | Patchwork armor of stolen trophies |

---

## PART 10: EXAMPLE COMPLETE PROMPTS

Here are 3 ready-to-paste example prompts. **Generate at 1152x768 (SDXL landscape). Use ZavyChromaXL or similar SDXL checkpoint. Euler a sampler, 25 steps, CFG 5.**

### Example 1: Shieldbearer (Common defender)

**Size: 1152x768** | **Model: ZavyChromaXL** | **Save as: `shieldbearer.png`** | **Post-process to: 512x340**

**Positive:**
```
heavily armored dwarf soldier, massive tower shield covering most of body, only determined eyes visible above shield rim, dented scratched iron armor, short stocky build, braced defensive stance, close-up bust portrait, face filling upper third of frame, head and shoulders filling the frame, dark fantasy digital painting, warm lighting from upper left, painterly brushwork, bold colors, strong silhouette, dark studio, rim lighting, low key lighting, fantasy card game illustration, high value contrast, high contrast between subject and background, large detailed face, expressive eyes visible, warm amber color temperature, firelit, bold shapes, masterpiece, best quality
```

**Negative:**
```
anime, 3d render, photorealistic, photograph, text, watermark, signature, logo, card frame, card border, bad anatomy, deformed, blurry, low quality, worst quality, full body, wide shot, distant view, tiny figure
```

### Example 2: Iron Champion / e_warden_champ (Act 1 Boss)

**Size: 1152x768** | **Model: ZavyChromaXL** | **Save as: `e_warden_champ.png`** | **Post-process to: 512x340**

**Positive:**
```
champion of the iron warden, elite full plate armor with gold inlay, glowing blue visor, dual wielding enchanted blades, imposing boss presence, menacing hostile expression, dark red accent lighting, close-up bust portrait, face and upper body filling the frame, dark fantasy digital painting, warm lighting from upper left, painterly brushwork, bold colors, strong silhouette, dark studio, rim lighting, low key lighting, fantasy card game illustration, high value contrast, high contrast between subject and background, epic powerful, expressive eyes visible, warm amber color temperature, firelit, bold shapes, masterpiece, best quality
```

**Negative:**
```
anime, 3d render, photorealistic, photograph, text, watermark, signature, logo, card frame, card border, bad anatomy, deformed, blurry, low quality, worst quality, full body, wide shot, distant view, tiny figure, friendly, cute, gentle
```

### Example 3: Kindling (Rare tiny creature)

**Size: 1152x768** | **Model: ZavyChromaXL** | **Save as: `kindling.png`** | **Post-process to: 512x340**

**Positive:**
```
tiny smoldering stick figure creature made of burning twigs and leaves, small flickering flame for a head, bright ember eyes, fragile but persistent, leaving scorch marks, creature centered and filling most of the frame, close-up view, dark fantasy digital painting, warm lighting from upper left, painterly brushwork, bold colors, strong silhouette, dark studio, rim lighting, low key lighting, fantasy card game illustration, high value contrast, high contrast between bright fire creature and dark background, warm amber color temperature, glowing embers, firelit, bold shapes, masterpiece, best quality
```

**Negative:**
```
anime, 3d render, photorealistic, photograph, text, watermark, signature, logo, card frame, card border, bad anatomy, deformed, blurry, low quality, worst quality, human, person, full body, wide shot, tiny figure, distant
```

### WHY THESE EXAMPLES WORK FUNCTIONALLY

1. **1152x768 SDXL landscape** matches the ~1.5:1 art window → no surprise cropping, and generates at SDXL's native resolution range (~1 megapixel)
2. **"close-up bust portrait, face filling upper third"** → forces tight framing. Combined with landscape aspect ratio, this is the most reliable way to control SD composition (aspect ratio + framing terms together work better than either alone)
3. **"dark studio, rim lighting, low key lighting"** → specific lighting terms that produce clean subject-background separation. SD doesn't respond meaningfully to vague terms like "medium-dark background" — lighting keywords give you the dark mood AND readable contrast
4. **"high contrast between subject and background"** → at 147px, value separation is the ONLY way to distinguish subject from bg
5. **"card frame, card border"** in negative → prevents SD from generating a frame-within-a-frame
6. **"text, watermark, signature, logo"** in negative → prevents poster-style text artifacts that SD generates when it sees composition terms overlapping with poster training data
7. **Short negative prompt (under 20 terms)** → SDXL research shows 5-10 targeted negatives outperform long lists. Bloated negatives flatten detail and introduce stiffness

---

## CHECKLIST — Before Marking a Portrait as Done

### Thematic Quality (does it look right?)

- [ ] Subject fills 70-80% of frame
- [ ] Face/eyes are clear and expressive (or creature-appropriate equivalent)
- [ ] Face is at least 30-40% of image width (large enough to read at 147px)
- [ ] Lighting comes from upper-left at ~45 degrees
- [ ] Warm amber color temperature
- [ ] Background is darker than subject but NOT so dark the whole image is unreadable
- [ ] Passes squint test — silhouette is recognizable at 150px wide
- [ ] No text, watermarks, or AI artifacts in the image
- [ ] No extra limbs or severe anatomy issues (hands invisible or behind frame is fine)
- [ ] Style matches other portraits in the set

### Functional Requirements (will it work in-game?)

- [ ] File is 512x340 pixels (or 512x512 max) — NOT the raw 1024+ generation
- [ ] File format is PNG
- [ ] Filename is `{card_id}.png` — exact lowercase match to CardDB.gd `id` field
- [ ] File is in `assets/creatures/` folder
- [ ] PNG metadata has been stripped (no embedded prompts)
- [ ] No embedded ICC color profile (will display wrong in Godot)
- [ ] Image is OPAQUE — no transparency, no transparent background (not needed, clip_contents handles masking)
- [ ] Debanding noise applied (+2% Gaussian) for dark gradient backgrounds
- [ ] Generated at landscape aspect ratio (~3:2) so face isn't cropped by STRETCH_KEEP_ASPECT_COVERED
- [ ] Brightness test: at 150px display, subject is clearly visible (not a dark blob)
