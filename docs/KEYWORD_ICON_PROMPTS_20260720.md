# Keyword icon prompts — Midjourney (2026-07-20)

Target format (must match the existing kit exactly):
`assets/icons/keywords/<id>.svg` — `viewBox="0 0 512 512"`, a **single** `<path fill="#fff">`.
The loader in `GameTheme._load_keyword_icons()` is an **allow-list**: a filename that
doesn't match an id renders no device at all, silently.

These render at roughly **16–18px** on card bottom margins, the Card2D status rail, and
battle-log chips. That is why every prompt says *no interior detail* and *must read
clearly at 16 pixels* — painted icons mush below ~20px, which is why the relic set was
already swapped from paintings to gilt silhouettes and why `INLINE_KEYWORD_STAMPS` is
still off.

## Step 0 — make the anchor first

Run ONE icon with no `--sref`, pick the result whose weight you like, then
`Ctrl/Cmd-click → Copy → sref` (or use `/describe`) to get its style code. Paste that
code over `YOURCODE` in every prompt below. Without a shared `--sref` a 26-icon set
drifts in stroke weight and mass and stops looking like one designer's work.

Anchor run (no sref):

```
flat solid white silhouette emblem of a riveted steel breastplate seen head-on, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline
```

## Step 1 — pipeline

1. Upscale before tracing (≥2048px; never trace a preview).
2. Vectorise — Midjourney `/vectorize`, Illustrator Image Trace, or Inkscape+Potrace.
3. Flatten to one path, `fill="#fff"`, `viewBox="0 0 512 512"`.
4. Drop in `assets/icons/keywords/`, run a headless `--import`.
5. Judge them **in game at real size**, not in the browser.

## Step 2 — the 26

Only the subject changes. Everything else is identical on purpose.

---

### armored
```
flat solid white silhouette emblem of a riveted steel breastplate seen head-on, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### swift
```
flat solid white silhouette emblem of a cavalry spur with a spiked rowel trailing two speed lines, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### thorns
```
flat solid white silhouette emblem of a closed ring of barbed bramble thorns, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### regenerate
```
flat solid white silhouette emblem of a fresh shoot growing out of a cut tree stump, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### summon
```
flat solid white silhouette emblem of a war horn with three solid sparks rising from its mouth, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### last_stand
```
flat solid white silhouette emblem of a soldier down on one knee planting a banner pole, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### piercing
```
flat solid white silhouette emblem of a spearhead punching clean through a split shield, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### sniper
```
flat solid white silhouette emblem of a heavy arbalest crossbow seen from the side with a bolt loaded, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### sacrifice
```
flat solid white silhouette emblem of a curved sacrificial dagger point-down over an altar stone, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### exhaust
```
flat solid white silhouette emblem of a burnt-out candle stub with one curl of smoke, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### retain
```
flat solid white silhouette emblem of a clenched gauntleted fist gripping the edge of a card, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### wither
```
flat solid white silhouette emblem of a snapped sword blade with the broken tip falling away, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### on_enter
```
flat solid white silhouette emblem of a heavy boot stamping down with three impact wedges beneath it, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### on_death
```
flat solid white silhouette emblem of a bare human skull seen from the front, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### adj_buff
```
flat solid white silhouette emblem of three linked shields in a row with the outer two raised higher, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### poison
```
flat solid white silhouette emblem of a single dripping serpent fang, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### shield
```
flat solid white silhouette emblem of a plain kite shield seen from the front, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### guardian
```
flat solid white silhouette emblem of a planted tower shield with three arrows stuck in it, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### structure
```
flat solid white silhouette emblem of a squat stone tower with crenellations, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### doom
```
flat solid white silhouette emblem of an hourglass with a skull inside the lower bulb, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### rampage
```
flat solid white silhouette emblem of an axe head with four tally notches cut into the haft, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### lifelink
```
flat solid white silhouette emblem of a chalice catching a falling drop from a blade tip, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### overrun
```
flat solid white silhouette emblem of a couched lance charging through an open empty gateway, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### formation
```
flat solid white silhouette emblem of three interlocked pikes standing upright in a row, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### frozen
```
flat solid white silhouette emblem of a jagged six-pointed ice crystal, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

### stunned
```
flat solid white silhouette emblem of a dented helmet with two spirals circling above it, pure white shape on pure black background, single unified silhouette, chunky bold forms, thick connected masses, no outline, no stroke, no gradient, no shading, no texture, no interior detail, maximum contrast, centered, fills the frame, medieval heraldic woodcut, game icon, must read clearly at 16 pixels --style raw --ar 1:1 --no text, letters, numbers, watermark, border, frame, 3d, perspective, drop shadow, grey, outline --sref YOURCODE --sw 100 --seed 1234
```

---

## Deliberate collision-avoidance

- `armored` is a **breastplate**, `shield` a **kite shield**, `guardian` a **tower
  shield** — three shield-ish concepts that must never blur at 16px.
- `rampage` uses **tally notches** rather than a beast: reads far better small and
  matches the game's ledger/tally motif.
- `exhaust` is a **candle stub**, matching the `CandleStub` painter in the event
  minigames.
- `on_death` (skull) vs `doom` (hourglass + skull) share a skull deliberately —
  doom is death *on a clock*.

## Not needed

`slay` and `adjacent` exist in `KeywordEffects.KEYWORDS` but are **not** in the icon
registry — they're glossary terms, not card devices. No art required.

## Licensing

The current set is game-icons.net (CC-BY 3.0), credited in `CREDITS.md`. Replacing all
26 retires that attribution — worth doing the whole set rather than a mix so there's
only one provenance story.
