"""Frame compositor for Burning Meadow card frames.

Builds painterly engraved-bronze + gold-trim card frames at 2x resolution (300x400)
for crisp downscaling in Godot. Uses Pillow + numpy. No external assets required
except the local parchment background, which is sampled as raw material for the
description well and name banner.

Rarity dials a banner color + gold-glow intensity. Type (creature vs spell) dials
the silhouette and stat-chip presence. Outputs to D:/Godot/assets/frames/.
"""

from __future__ import annotations
import math
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageOps


# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #

OUT_DIR   = Path("D:/Godot/assets/frames")
WORK_DIR  = Path("D:/Godot/_frame_work")
PARCH_SRC = Path("D:/Godot/assets/backgrounds/map_parchment.jpg")

# Bake at 2x for crisp downscaling.
SCALE   = 2
CARD_W  = 150 * SCALE
CARD_H  = 200 * SCALE

# Rarity → (banner_rgb, trim_glow_rgb, trim_glow_strength)
RARITY = {
    "starter":  ((78,  55,  35),  (140, 100,  50), 0.0),
    "common":   ((90,  90,  95),  (180, 180, 185), 0.15),
    "uncommon": ((40,  70, 130),  (130, 170, 220), 0.30),
    "rare":     ((180, 140,  40), (255, 220, 120), 0.55),
}


# --------------------------------------------------------------------------- #
# Procedural texture generators
# --------------------------------------------------------------------------- #

def _fractal_noise(w: int, h: int, octaves: int = 5, seed: int = 0) -> np.ndarray:
    """Multi-octave value noise in [0, 1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for oct_i in range(octaves):
        scale = 2 ** oct_i
        nh = max(2, h // (16 // (2 ** min(oct_i, 3))))
        nw = max(2, w // (16 // (2 ** min(oct_i, 3))))
        coarse = rng.random((nh, nw), dtype=np.float32)
        layer = np.array(
            Image.fromarray((coarse * 255).astype(np.uint8))
            .resize((w, h), Image.BICUBIC)
        ).astype(np.float32) / 255.0
        out += layer * amp
        total += amp
        amp *= 0.5
    out = out / total
    return out


def bronze_texture(w: int, h: int, seed: int = 7) -> Image.Image:
    """Dark engraved bronze plate — high contrast, cross-hatch engraving feel."""
    # Three noise layers: large patches + medium grain + fine engraving lines
    n_large = _fractal_noise(w, h, octaves=3, seed=seed)
    n_med   = _fractal_noise(w, h, octaves=6, seed=seed + 1)
    # Fine cross-hatch — small high-frequency noise stretched diagonally
    n_fine  = _fractal_noise(w, h, octaves=7, seed=seed + 2)

    # Combine: large patches set base value, medium adds texture, fine adds engraving
    val = (0.35
           + (n_large - 0.5) * 0.55
           + (n_med   - 0.5) * 0.30
           + (n_fine  - 0.5) * 0.18)
    val = np.clip(val, 0.02, 0.92)

    # Apply a slight vignette gradient (darker on edges = depth)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = w / 2.0, h / 2.0
    radial = np.hypot((xx - cx) / cx, (yy - cy) / cy)
    val = val * (1.05 - radial * 0.10)
    val = np.clip(val, 0.02, 1.0)

    # Dark bronze palette: deep umber with warm highlights
    r = (np.clip(val * 1.40, 0, 1) * 150 + 8).astype(np.uint8)
    g = (np.clip(val * 1.10, 0, 1) *  92 + 5).astype(np.uint8)
    b = (np.clip(val * 0.70, 0, 1) *  48 + 3).astype(np.uint8)
    rgb = np.stack([r, g, b], axis=-1)
    return Image.fromarray(rgb, "RGB")


def gold_texture(w: int, h: int, seed: int = 31) -> Image.Image:
    """Polished but slightly weathered gold leaf."""
    n1 = _fractal_noise(w, h, octaves=4, seed=seed)
    n2 = _fractal_noise(w, h, octaves=6, seed=seed + 1)
    val = 0.55 + (n1 - 0.5) * 0.40 + (n2 - 0.5) * 0.18
    val = np.clip(val, 0.10, 1.0)
    r = (np.clip(val * 1.10, 0, 1) * 235 + 20).astype(np.uint8)
    g = (np.clip(val * 0.92, 0, 1) * 185 + 15).astype(np.uint8)
    b = (np.clip(val * 0.50, 0, 1) *  90 +  8).astype(np.uint8)
    rgb = np.stack([r, g, b], axis=-1)
    return Image.fromarray(rgb, "RGB")


def parchment_sample(w: int, h: int) -> Image.Image:
    """Crop a usable patch from the local parchment background and warm it."""
    src = Image.open(PARCH_SRC).convert("RGB")
    # Take a clean center patch
    sw, sh = src.size
    px = (sw - w) // 2
    py = (sh - h) // 2
    patch = src.crop((px, py, px + w, py + h))
    # Warm/darken slightly so dark serif text is legible
    arr = np.asarray(patch).astype(np.float32) / 255.0
    arr[..., 0] = np.clip(arr[..., 0] * 0.95 + 0.04, 0, 1)
    arr[..., 1] = np.clip(arr[..., 1] * 0.86 + 0.02, 0, 1)
    arr[..., 2] = np.clip(arr[..., 2] * 0.72,         0, 1)
    arr = (arr * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


# --------------------------------------------------------------------------- #
# Shape primitives
# --------------------------------------------------------------------------- #

def rounded_rect_mask(w: int, h: int, radius: int, inset: int = 0) -> Image.Image:
    """Single-channel L-mode mask of a rounded rect."""
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(
        [inset, inset, w - 1 - inset, h - 1 - inset],
        radius=radius,
        fill=255,
    )
    return m


def bevel_mask(mask: Image.Image, depth: int, light_dir: tuple[float, float] = (-1, -1)) -> Image.Image:
    """Convert a binary mask into a bevel highlight/shadow gradient (RGBA).

    Returns RGBA where white pixels are highlights and black pixels are shadows,
    with alpha proportional to the bevel strength. Composite with a multiply
    or overlay on top of the material texture.
    """
    # Distance transform via successive shrinking
    inner = mask
    h_acc = np.zeros(mask.size[::-1], dtype=np.float32)
    s_acc = np.zeros_like(h_acc)
    for i in range(depth):
        shrunk = inner.filter(ImageFilter.MinFilter(3))
        edge   = ImageChops.subtract(inner, shrunk)
        edge_a = np.asarray(edge, dtype=np.float32) / 255.0
        # Highlight on the lit side, shadow on opposite, fade with depth
        falloff = 1.0 - (i / depth)
        # We can't trivially decompose orientation from MinFilter, so we apply
        # a directional gradient post-hoc using a Sobel-like trick on the
        # original mask.
        inner = shrunk
    # Now do an orientation pass: blur the mask, then take its gradient.
    blurred = mask.filter(ImageFilter.GaussianBlur(radius=depth))
    arr = np.asarray(blurred, dtype=np.float32) / 255.0
    gy, gx = np.gradient(arr)
    # Project gradient onto light direction (light_dir points TOWARDS light)
    lx, ly = light_dir
    norm = math.hypot(lx, ly) or 1.0
    lx /= norm; ly /= norm
    proj = gx * lx + gy * ly
    # Highlight = positive projection, shadow = negative projection
    hi = np.clip(proj, 0, None)
    sh = np.clip(-proj, 0, None)
    # Restrict bevel to a band along the inside edge of the mask
    edge_band = arr * (1.0 - arr)  # peaks at boundary
    edge_band = edge_band / max(edge_band.max(), 1e-6)
    strength = np.power(edge_band, 0.7)
    hi *= strength * 6.0
    sh *= strength * 6.0
    hi = np.clip(hi, 0, 1)
    sh = np.clip(sh, 0, 1)

    rgba = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.uint8)
    # Highlights as white
    rgba[..., 0] = (hi * 255).astype(np.uint8)
    rgba[..., 1] = (hi * 255).astype(np.uint8)
    rgba[..., 2] = (hi * 255).astype(np.uint8)
    # Subtract shadow contribution by darkening alpha-weighted
    alpha = np.maximum(hi, sh) * 220
    rgba[..., 3] = alpha.astype(np.uint8)
    # Where shadow > highlight, paint black
    shadow_dominant = sh > hi
    rgba[..., 0][shadow_dominant] = 0
    rgba[..., 1][shadow_dominant] = 0
    rgba[..., 2][shadow_dominant] = 0
    return Image.fromarray(rgba, "RGBA")


def drop_shadow(img: Image.Image, offset: tuple[int, int] = (0, 4),
                blur: float = 4.0, opacity: float = 0.55) -> Image.Image:
    """Soft drop shadow under an RGBA image."""
    w, h = img.size
    alpha = img.split()[-1]
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh_arr = np.zeros((h, w, 4), dtype=np.uint8)
    sh_arr[..., 3] = (np.asarray(alpha) * opacity).astype(np.uint8)
    shadow = Image.fromarray(sh_arr, "RGBA")
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=blur))

    canvas = Image.new("RGBA", (w + abs(offset[0]) + int(blur) * 2,
                                h + abs(offset[1]) + int(blur) * 2), (0, 0, 0, 0))
    pad = int(blur)
    canvas.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    canvas.alpha_composite(img,    (pad, pad))
    return canvas


def filled(material: Image.Image, mask: Image.Image) -> Image.Image:
    """Apply mask as alpha to a material RGB image, return RGBA."""
    rgba = material.convert("RGBA")
    rgba.putalpha(mask)
    return rgba


# --------------------------------------------------------------------------- #
# Frame composition
# --------------------------------------------------------------------------- #

def compose_frame(card_type: str, rarity: str) -> Image.Image:
    """Build one card frame. card_type ∈ {creature, spell, curse}.

    The frame includes: outer bronze plate, gold inner trim, art window cutout,
    name banner, type strip, description well, cost orb socket, stat chip
    sockets (creatures only). Card2D draws the text and stats on top.
    """
    W, H = CARD_W, CARD_H
    is_spell = (card_type == "spell")
    is_curse = (card_type == "curse")

    # Layout (in baked pixel coords)
    OUTER_R     = 22 * SCALE // 2 * 2       # corner radius outer frame
    BRONZE_W    = 9  * SCALE                # bronze plate thickness
    GOLD_W      = 3  * SCALE                # gold trim thickness
    BANNER_TOP  = int(H * 0.07)
    BANNER_BOT  = int(H * 0.21)
    ART_TOP     = int(H * 0.22)
    ART_BOT     = int(H * 0.62)
    TYPESTRIP_T = ART_BOT + 1
    TYPESTRIP_B = TYPESTRIP_T + int(H * 0.07)
    DESC_TOP    = TYPESTRIP_B + 1
    DESC_BOT    = int(H * 0.92)
    SIDE_PAD    = int(W * 0.07)

    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # --- Layer 1: outer rounded-rect bronze plate ----------------------------
    outer_mask = rounded_rect_mask(W, H, radius=OUTER_R)
    bronze = bronze_texture(W, H, seed=11 if not is_curse else 91)
    if is_curse:
        # Desaturate + purple shift for curse
        arr = np.asarray(bronze).astype(np.float32)
        gray = arr.mean(axis=-1, keepdims=True)
        arr = gray * 0.6 + np.array([45, 25, 55]) * 0.4
        bronze = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    plate = filled(bronze, outer_mask)

    # Outer bevel
    bev = bevel_mask(outer_mask, depth=int(BRONZE_W * 1.2), light_dir=(-1, -1.4))
    plate.alpha_composite(bev)
    canvas.alpha_composite(plate)

    # --- Layer 2: gold inner trim (just inside the bronze plate) -------------
    gold_inset = BRONZE_W
    gold_outer = rounded_rect_mask(W, H, radius=max(8, OUTER_R - gold_inset), inset=gold_inset)
    gold_inner = rounded_rect_mask(W, H, radius=max(6, OUTER_R - gold_inset - GOLD_W),
                                   inset=gold_inset + GOLD_W)
    gold_band = ImageChops.subtract(gold_outer, gold_inner)
    gold = gold_texture(W, H, seed=53)
    if is_curse:
        # Curse trim is dark purple-tarnished, not gold
        arr = np.asarray(gold).astype(np.float32)
        gray = arr.mean(axis=-1, keepdims=True)
        arr = gray * 0.4 + np.array([90, 60, 110]) * 0.6
        gold = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    trim = filled(gold, gold_band)
    trim_bev = bevel_mask(gold_band, depth=GOLD_W, light_dir=(-1, -1))
    trim.alpha_composite(trim_bev)

    # Rare/uncommon: add warm glow around the gold trim
    _, glow_rgb, glow_strength = RARITY.get(rarity, RARITY["common"])
    if glow_strength > 0.05:
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.rounded_rectangle(
            [gold_inset, gold_inset, W - 1 - gold_inset, H - 1 - gold_inset],
            radius=max(8, OUTER_R - gold_inset),
            outline=glow_rgb + (int(255 * glow_strength),),
            width=GOLD_W + 1,
        )
        glow = glow.filter(ImageFilter.GaussianBlur(radius=6 * SCALE))
        canvas.alpha_composite(glow)
    canvas.alpha_composite(trim)

    # --- Layer 3: cut the art window (transparent hole) ---------------------
    art_left  = SIDE_PAD
    art_right = W - SIDE_PAD
    art_mask  = Image.new("L", (W, H), 0)
    ad = ImageDraw.Draw(art_mask)
    if is_spell:
        # Spell art window is arched (rounded top, narrower body)
        ad.rounded_rectangle(
            [art_left, ART_TOP, art_right, ART_BOT],
            radius=int(W * 0.18),
            fill=255,
        )
    else:
        ad.rounded_rectangle(
            [art_left, ART_TOP, art_right, ART_BOT],
            radius=int(W * 0.04),
            fill=255,
        )
    # Soften the cut so the art bleeds into the frame instead of hard-edge
    art_mask_soft = art_mask.filter(ImageFilter.GaussianBlur(radius=1.5 * SCALE))
    # Inner shadow around the art window — paint a dark ring just inside the
    # cut so the window reads as recessed beneath the frame. Done BEFORE the
    # alpha subtraction so the shadow stays opaque on the frame body.
    inner_sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    isd = ImageDraw.Draw(inner_sh)
    if is_spell:
        isd.rounded_rectangle(
            [art_left, ART_TOP, art_right, ART_BOT],
            radius=int(W * 0.18),
            outline=(0, 0, 0, 220),
            width=4 * SCALE,
        )
    else:
        isd.rounded_rectangle(
            [art_left, ART_TOP, art_right, ART_BOT],
            radius=int(W * 0.04),
            outline=(0, 0, 0, 220),
            width=4 * SCALE,
        )
    inner_sh = inner_sh.filter(ImageFilter.GaussianBlur(radius=3 * SCALE))
    # Constrain shadow to the OUTSIDE of the art window (subtract art_mask)
    sh_r, sh_g, sh_b, sh_a = inner_sh.split()
    sh_a_arr = np.asarray(sh_a, dtype=np.float32) / 255.0
    am_arr = np.asarray(art_mask, dtype=np.float32) / 255.0
    sh_a_arr = sh_a_arr * (1.0 - am_arr)
    inner_sh = Image.merge("RGBA", (sh_r, sh_g, sh_b,
                                    Image.fromarray((sh_a_arr * 255).astype(np.uint8))))
    canvas.alpha_composite(inner_sh)
    # Gold rim around the art window
    rim_w = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rid = ImageDraw.Draw(rim_w)
    if is_spell:
        rid.rounded_rectangle(
            [art_left, ART_TOP, art_right, ART_BOT],
            radius=int(W * 0.18),
            outline=(170, 130, 55, 210),
            width=max(2, SCALE),
        )
    else:
        rid.rounded_rectangle(
            [art_left, ART_TOP, art_right, ART_BOT],
            radius=int(W * 0.04),
            outline=(170, 130, 55, 210),
            width=max(2, SCALE),
        )
    canvas.alpha_composite(rim_w)
    # Subtract art window from canvas alpha so the creature art shows through
    r, g, b, a = canvas.split()
    a_arr = np.asarray(a, dtype=np.float32) / 255.0
    m_arr = np.asarray(art_mask_soft, dtype=np.float32) / 255.0
    a_arr = np.clip(a_arr - m_arr, 0, 1)
    canvas = Image.merge("RGBA", (r, g, b, Image.fromarray((a_arr * 255).astype(np.uint8))))

    # --- Layer 4: description well (parchment inset) ------------------------
    desc_w = W - 2 * SIDE_PAD
    desc_h = DESC_BOT - DESC_TOP
    desc_mask = rounded_rect_mask(desc_w, desc_h, radius=int(W * 0.04))
    parch = parchment_sample(desc_w, desc_h)
    # Inner shadow vignette
    vig = np.zeros((desc_h, desc_w), dtype=np.float32)
    yy, xx = np.mgrid[0:desc_h, 0:desc_w]
    edge_dist = np.minimum.reduce([xx, yy, desc_w - 1 - xx, desc_h - 1 - yy]).astype(np.float32)
    vig = np.clip(1.0 - edge_dist / (8 * SCALE), 0, 1)
    parch_arr = np.asarray(parch).astype(np.float32)
    parch_arr = parch_arr * (1.0 - vig[..., None] * 0.4)
    parch = Image.fromarray(np.clip(parch_arr, 0, 255).astype(np.uint8), "RGB")
    desc_panel = filled(parch, desc_mask)
    canvas.alpha_composite(desc_panel, (SIDE_PAD, DESC_TOP))

    # Thin gold rim around description well
    rim = Image.new("RGBA", (desc_w, desc_h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.rounded_rectangle(
        [0, 0, desc_w - 1, desc_h - 1],
        radius=int(W * 0.04),
        outline=(170, 130, 55, 195),
        width=max(1, SCALE),
    )
    canvas.alpha_composite(rim, (SIDE_PAD, DESC_TOP))

    # --- Layer 5: type / keyword strip — parchment band ----------------------
    strip_h = TYPESTRIP_B - TYPESTRIP_T
    strip_w = W - 2 * SIDE_PAD
    strip_mask = rounded_rect_mask(strip_w, strip_h, radius=int(strip_h * 0.45))
    strip_parch = parchment_sample(strip_w, strip_h)
    # Darken slightly + warm-shift so it reads distinct from the larger desc well
    arr = np.asarray(strip_parch).astype(np.float32)
    arr = arr * 0.78
    strip_parch = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    strip_panel = filled(strip_parch, strip_mask)
    # Inset shadow at the top edge (lit from above gives the recessed feel)
    sh_arr = np.zeros((strip_h, strip_w, 4), dtype=np.uint8)
    sh_arr[:max(1, strip_h // 3), :, 3] = 130
    sh_img = Image.fromarray(sh_arr, "RGBA")
    sh_img = sh_img.filter(ImageFilter.GaussianBlur(radius=2 * SCALE))
    sh_img.putalpha(ImageChops.multiply(sh_img.split()[-1], strip_mask))
    strip_panel.alpha_composite(sh_img)
    canvas.alpha_composite(strip_panel, (SIDE_PAD, TYPESTRIP_T))
    # Thin gold rim
    rim2 = Image.new("RGBA", (strip_w, strip_h), (0, 0, 0, 0))
    rd2 = ImageDraw.Draw(rim2)
    rd2.rounded_rectangle(
        [0, 0, strip_w - 1, strip_h - 1],
        radius=int(strip_h * 0.45),
        outline=(170, 130, 55, 195),
        width=max(1, SCALE),
    )
    canvas.alpha_composite(rim2, (SIDE_PAD, TYPESTRIP_T))

    # NOTE: corner ornaments and side filigree removed — ornaments require
    # hand-curated source assets we don't have; clean bronze + gold trim +
    # parchment is the working design.

    # --- Layer 6: name banner (Weathered painted ribbon) -------------------
    banner_color, _, _ = RARITY.get(rarity, RARITY["common"])
    if is_curse:
        banner_color = (40, 20, 50)
    banner_h = BANNER_BOT - BANNER_TOP
    banner_w = int(W * 0.92)
    banner_x = (W - banner_w) // 2
    banner = _draw_banner(banner_w, banner_h, banner_color)
    banner_shadow = drop_shadow(banner, offset=(0, 2 * SCALE), blur=3 * SCALE, opacity=0.5)
    bs_w, bs_h = banner_shadow.size
    canvas.alpha_composite(banner_shadow,
                           (banner_x - (bs_w - banner_w) // 2,
                            BANNER_TOP - (bs_h - banner_h) // 2))

    # --- Layer 7: cost orb socket (top-left, protrudes) --------------------
    if not is_curse or True:
        orb_d = int(W * 0.22)
        orb_x = int(W * 0.05) - int(orb_d * 0.15)
        orb_y = int(H * 0.02) - int(orb_d * 0.10)
        orb = _draw_cost_orb(orb_d, rarity=rarity, is_curse=is_curse)
        canvas.alpha_composite(orb, (orb_x, orb_y))

    # --- Layer 8: stat chip sockets (creatures only) -----------------------
    if card_type == "creature":
        chip_d = int(W * 0.17)  # smaller, less collision with corner ornaments
        chip_y = H - int(chip_d * 0.95)
        atk_chip = _draw_stat_chip(chip_d, color=(140, 35, 30), label_color=(255, 240, 220))
        hp_chip  = _draw_stat_chip(chip_d, color=(50, 80, 145), label_color=(220, 235, 255))
        canvas.alpha_composite(atk_chip, (int(W * 0.025), chip_y - int(chip_d * 0.6)))
        canvas.alpha_composite(hp_chip,
                               (W - chip_d - int(W * 0.025) - int(W * 0.035),
                                chip_y - int(chip_d * 0.6)))

    return canvas


def _draw_banner(w: int, h: int, color: tuple[int, int, int]) -> Image.Image:
    """Painted ribbon banner with proper sweeping tails and a parchment-grained body."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    body_top = int(h * 0.18)
    body_bot = int(h * 0.82)
    tail_w   = int(w * 0.09)
    body_l   = tail_w
    body_r   = w - tail_w

    # --- Tails first (behind body so the body shadow can sit on top) -------
    darker = tuple(max(0, c - 50) for c in color) + (255,)
    td = ImageDraw.Draw(img)
    # Left tail: notched ribbon end
    tail_l_pts = [
        (0,                    int(h * 0.30)),
        (tail_w + 4,           body_top),
        (tail_w + 4,           body_bot),
        (0,                    int(h * 0.70)),
        (int(tail_w * 0.45),   int(h * 0.50)),
    ]
    td.polygon(tail_l_pts, fill=darker)
    # Right tail
    tail_r_pts = [
        (w - 1,                          int(h * 0.30)),
        (w - tail_w - 5,                 body_top),
        (w - tail_w - 5,                 body_bot),
        (w - 1,                          int(h * 0.70)),
        (w - 1 - int(tail_w * 0.45),     int(h * 0.50)),
    ]
    td.polygon(tail_r_pts, fill=darker)

    # --- Body — colored fill + parchment-style grain ----------------------
    body_mask = Image.new("L", (w, h), 0)
    bd = ImageDraw.Draw(body_mask)
    bd.rounded_rectangle(
        [body_l, body_top, body_r, body_bot],
        radius=int(h * 0.18),
        fill=255,
    )
    body_rgba = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bdf = ImageDraw.Draw(body_rgba)
    bdf.rounded_rectangle(
        [body_l, body_top, body_r, body_bot],
        radius=int(h * 0.18),
        fill=color + (255,),
    )
    # Painterly grain on body
    noise = (_fractal_noise(w, h, octaves=5, seed=29) * 255).astype(np.uint8)
    n_arr = np.zeros((h, w, 4), dtype=np.uint8)
    n_arr[..., 0] = noise; n_arr[..., 1] = noise; n_arr[..., 2] = noise
    n_arr[..., 3] = 70
    n_rgba = Image.fromarray(n_arr, "RGBA")
    n_rgba.putalpha(ImageChops.multiply(n_rgba.split()[-1], body_mask))
    body_rgba.alpha_composite(n_rgba)
    # Top highlight
    hi = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hi)
    hd.rounded_rectangle(
        [body_l + 2, body_top + 2, body_r - 2, int(h * 0.45)],
        radius=int(h * 0.10),
        fill=(255, 255, 255, 55),
    )
    hi = hi.filter(ImageFilter.GaussianBlur(radius=2.5))
    body_rgba.alpha_composite(hi)
    # Bottom inner shadow
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.rounded_rectangle(
        [body_l + 2, int(h * 0.60), body_r - 2, body_bot - 2],
        radius=int(h * 0.10),
        fill=(0, 0, 0, 70),
    )
    sh = sh.filter(ImageFilter.GaussianBlur(radius=2.5))
    body_rgba.alpha_composite(sh)
    img.alpha_composite(body_rgba)

    # --- Gold rim on the body and tails -----------------------------------
    rd = ImageDraw.Draw(img)
    rd.rounded_rectangle(
        [body_l, body_top, body_r, body_bot],
        radius=int(h * 0.18),
        outline=(210, 170, 85, 255),
        width=max(2, SCALE),
    )
    rd.polygon(tail_l_pts, outline=(190, 150, 75, 255), width=max(1, SCALE))
    rd.polygon(tail_r_pts, outline=(190, 150, 75, 255), width=max(1, SCALE))
    return img


def _real_ornament(path: Path, size: int, gold_color: tuple[int, int, int],
                   crop_box: tuple[float, float, float, float] | None = None,
                   ) -> Image.Image:
    """Load a public-domain ornament PNG and recolor it to fit our gold tone.

    crop_box: optional (l, t, r, b) in normalized [0, 1] coords — crop the source
    BEFORE resizing. Useful when only one quadrant of the source asset works.

    Pipeline: load -> optional crop -> auto-detect light-on-dark vs dark-on-light
    -> luminance to alpha -> fill with vertical gold gradient -> drop shadow.
    """
    src = Image.open(path).convert("RGBA")
    if crop_box is not None:
        sw, sh = src.size
        l, t, r, b = crop_box
        src = src.crop((int(sw * l), int(sh * t), int(sw * r), int(sh * b)))
    src.thumbnail((size, size), Image.LANCZOS)
    w, h = src.size

    src_a = np.asarray(src.split()[-1])
    lum = np.asarray(src.convert("L"), dtype=np.float32)

    # Asset can encode the ornament in three ways:
    #   (a) RGB carries it, alpha is uniform 255 (typical raster scan)
    #   (b) Alpha carries it, RGB is mostly uniform (transparent PNG)
    #   (c) Both carry it (RGBA with engraved colors)
    # Use alpha standard-deviation as the test: meaningful variation -> alpha.
    if src_a.std() > 30:
        ink = src_a.astype(np.float32)
    else:
        # Detect background polarity from corner luminance
        corners = [lum[0, 0], lum[0, -1], lum[-1, 0], lum[-1, -1]]
        bg_is_dark = (sum(corners) / 4.0) < 80
        if bg_is_dark:
            ink = lum * 1.05
        else:
            ink = (255 - lum) * 1.3

    ink = np.clip(ink, 0, 255).astype(np.uint8)
    alpha = Image.fromarray(ink, "L")

    # Build a gold gradient fill of the same size
    grad = np.zeros((h, w, 3), dtype=np.uint8)
    for y in range(h):
        t = y / max(h - 1, 1)
        # Lit top, deeper bottom — single light direction (upper-left)
        r = int(gold_color[0] * (1.15 - t * 0.35))
        g = int(gold_color[1] * (1.10 - t * 0.30))
        b = int(gold_color[2] * (1.05 - t * 0.25))
        grad[y, :] = (max(0, min(255, r)),
                      max(0, min(255, g)),
                      max(0, min(255, b)))
    grad_img = Image.fromarray(grad, "RGB").convert("RGBA")
    grad_img.putalpha(alpha)

    # Drop shadow under the ornament for "attached to bronze" feel
    out = drop_shadow(grad_img, offset=(0, 2 * SCALE), blur=2 * SCALE, opacity=0.55)
    return out


def _draw_corner_ornament(size: int, gold_color=(195, 155, 70), seed: int = 1) -> Image.Image:
    """Procedural cartouche corner ornament — gold scrollwork that sits on the
    outer frame corners. Designed for the top-left position; rotate/flip for
    other corners."""
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Outer scroll arc
    arc_color = gold_color + (245,)
    line_w = max(2, s // 14)
    # Main C-curve from upper-right toward lower-left
    d.arc([int(s * 0.08), int(s * 0.08), int(s * 1.10), int(s * 1.10)],
          start=180, end=270, fill=arc_color, width=line_w)
    # Inner counter-curve (smaller, opposite direction)
    d.arc([int(s * 0.32), int(s * 0.32), int(s * 0.92), int(s * 0.92)],
          start=190, end=275, fill=arc_color, width=max(1, line_w - 1))
    # Small terminal curl at the end
    d.arc([int(s * 0.06), int(s * 0.30), int(s * 0.36), int(s * 0.60)],
          start=90, end=360, fill=arc_color, width=max(1, line_w - 1))
    # Dot in the curl
    cx, cy = int(s * 0.21), int(s * 0.45)
    dr = max(1, s // 22)
    d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=gold_color + (255,))
    # Leafy flourish — small triangular leaves
    for k, (lx, ly, ang) in enumerate([
        (int(s * 0.55), int(s * 0.18), 0),
        (int(s * 0.78), int(s * 0.40), 90),
    ]):
        leaf = [
            (lx,                      ly),
            (lx + int(s * 0.07),      ly + int(s * 0.04)),
            (lx + int(s * 0.04),      ly + int(s * 0.10)),
            (lx - int(s * 0.02),      ly + int(s * 0.06)),
        ]
        d.polygon(leaf, fill=gold_color + (235,))

    # Soft inner glow to make it look applied to the frame
    glow = img.filter(ImageFilter.GaussianBlur(radius=max(1, s // 50)))
    out = Image.alpha_composite(glow, img)
    return out


def _draw_filigree_strip(w: int, h: int, gold_color=(190, 150, 65),
                         repeats: int = 6) -> Image.Image:
    """Horizontal repeating filigree pattern for trim along straight edges."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cell = max(8, w // repeats)
    for i in range(0, w + cell, cell):
        cx = i + cell // 2
        cy = h // 2
        r = int(min(cell, h) * 0.35)
        # diamond
        d.polygon([
            (cx, cy - r),
            (cx + r, cy),
            (cx, cy + r),
            (cx - r, cy),
        ], outline=gold_color + (220,), width=1)
        # tiny dot center
        d.ellipse([cx - 1, cy - 1, cx + 1, cy + 1], fill=gold_color + (240,))
    return img


def _draw_cost_orb(d: int, rarity: str = "common", is_curse: bool = False) -> Image.Image:
    """Glowing gem cost orb with bronze socket bezel."""
    pad = int(d * 0.18)
    size = d + pad * 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Halo
    halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse([pad // 3, pad // 3, size - pad // 3, size - pad // 3],
               fill=(220, 90, 60, 90) if not is_curse else (140, 60, 180, 110))
    halo = halo.filter(ImageFilter.GaussianBlur(radius=pad * 0.9))
    img.alpha_composite(halo)
    # Bronze socket bezel
    bd = ImageDraw.Draw(img)
    bezel_color = (95, 65, 35, 255) if not is_curse else (60, 35, 75, 255)
    bd.ellipse([pad - 2, pad - 2, size - pad + 2, size - pad + 2],
               fill=bezel_color)
    # Inner gold ring
    gd = ImageDraw.Draw(img)
    gd.ellipse([pad + int(d * 0.04), pad + int(d * 0.04),
                size - pad - int(d * 0.04), size - pad - int(d * 0.04)],
               fill=(180, 140, 60, 255))
    # Gem core — radial gradient
    cx, cy = size // 2, size // 2
    rr = int(d * 0.42)
    gem_mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(gem_mask)
    md.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)
    # Radial gradient: dark crimson edge → bright orange center
    yy, xx = np.mgrid[0:size, 0:size]
    rd2 = np.hypot(xx - cx, yy - cy) / max(rr, 1)
    rd2 = np.clip(rd2, 0, 1)
    if is_curse:
        r_ch = (np.clip(1.4 - rd2 * 1.2, 0, 1) * 200 + 30).astype(np.uint8)
        g_ch = (np.clip(1.1 - rd2 * 1.5, 0, 1) *  60 + 10).astype(np.uint8)
        b_ch = (np.clip(1.5 - rd2 * 0.9, 0, 1) * 220 + 30).astype(np.uint8)
    else:
        r_ch = (np.clip(1.4 - rd2 * 0.8, 0, 1) * 240 + 15).astype(np.uint8)
        g_ch = (np.clip(1.1 - rd2 * 1.4, 0, 1) * 165 +  8).astype(np.uint8)
        b_ch = (np.clip(0.6 - rd2 * 1.1, 0, 1) *  60 +  4).astype(np.uint8)
    gem_rgb = np.stack([r_ch, g_ch, b_ch], axis=-1)
    gem_img = Image.fromarray(gem_rgb, "RGB").convert("RGBA")
    gem_img.putalpha(gem_mask)
    img.alpha_composite(gem_img)
    # Specular highlight
    sp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    spd = ImageDraw.Draw(sp)
    sp_r = int(rr * 0.35)
    sp_x = cx - int(rr * 0.35); sp_y = cy - int(rr * 0.40)
    spd.ellipse([sp_x - sp_r, sp_y - sp_r, sp_x + sp_r, sp_y + sp_r],
                fill=(255, 250, 220, 180))
    sp = sp.filter(ImageFilter.GaussianBlur(radius=2 * SCALE))
    img.alpha_composite(sp)
    return img


def _draw_stat_chip(d: int, color: tuple[int, int, int],
                    label_color: tuple[int, int, int]) -> Image.Image:
    """Wildfrost-style oversized stat chip — circle with bevel + gold rim."""
    size = int(d * 1.15)
    pad = (size - d) // 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Drop shadow
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.ellipse([pad, pad + 2, size - pad, size - pad + 2], fill=(0, 0, 0, 130))
    sh = sh.filter(ImageFilter.GaussianBlur(radius=3 * SCALE))
    img.alpha_composite(sh)
    # Outer gold rim
    od = ImageDraw.Draw(img)
    od.ellipse([pad - 1, pad - 1, size - pad + 1, size - pad + 1],
               fill=(190, 150, 70, 255))
    # Inner colored core
    inner_pad = pad + 2
    cd = ImageDraw.Draw(img)
    cd.ellipse([inner_pad, inner_pad, size - inner_pad, size - inner_pad],
               fill=color + (255,))
    # Radial darken at edges (sphere shading)
    cx = size // 2
    rr = (size - inner_pad * 2) // 2
    yy, xx = np.mgrid[0:size, 0:size]
    dist = np.hypot(xx - cx, yy - cx) / max(rr, 1)
    mask_arr = np.clip(dist, 0, 1)
    shade = (mask_arr * 90).astype(np.uint8)
    shade_rgba = np.zeros((size, size, 4), dtype=np.uint8)
    shade_rgba[..., 3] = shade
    shade_img = Image.fromarray(shade_rgba, "RGBA")
    inner_mask = Image.new("L", (size, size), 0)
    imd = ImageDraw.Draw(inner_mask)
    imd.ellipse([inner_pad, inner_pad, size - inner_pad, size - inner_pad], fill=255)
    shade_img.putalpha(ImageChops.multiply(shade_img.split()[-1], inner_mask))
    img.alpha_composite(shade_img)
    # Specular highlight
    sp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    spd = ImageDraw.Draw(sp)
    sp_r = int(rr * 0.45)
    sp_x = cx - int(rr * 0.30); sp_y = cx - int(rr * 0.35)
    spd.ellipse([sp_x - sp_r, sp_y - sp_r // 2, sp_x + sp_r, sp_y + sp_r // 2],
                fill=(255, 255, 255, 110))
    sp = sp.filter(ImageFilter.GaussianBlur(radius=2 * SCALE))
    img.alpha_composite(sp)
    return img


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #

def write_frame(card_type: str, rarity: str, name: str) -> Path:
    img = compose_frame(card_type, rarity)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / f"{name}.png"
    img.save(out_path, "PNG", optimize=True)
    return out_path


VARIANTS = [
    ("creature", "starter",  "frame_creature_starter"),
    ("creature", "common",   "frame_creature_common"),
    ("creature", "uncommon", "frame_creature_uncommon"),
    ("creature", "rare",     "frame_creature_rare"),
    ("spell",    "starter",  "frame_spell_starter"),
    ("spell",    "common",   "frame_spell_common"),
    ("spell",    "uncommon", "frame_spell_uncommon"),
    ("spell",    "rare",     "frame_spell_rare"),
    ("curse",    "common",   "frame_curse"),
]


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    if target == "all":
        for ct, ra, nm in VARIANTS:
            p = write_frame(ct, ra, nm)
            print(p)
    elif target == "proto":
        p = write_frame("creature", "common", "_proto_creature_common")
        print(p)
    else:
        # target = name like creature_common
        for ct, ra, nm in VARIANTS:
            if nm.endswith(target):
                p = write_frame(ct, ra, nm)
                print(p)
                break
        else:
            print(f"unknown target: {target}", file=sys.stderr)
            sys.exit(2)
