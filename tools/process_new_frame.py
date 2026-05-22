"""Process a Midjourney-generated card frame for use in the game.

Takes a raw Midjourney output (card on a ~magenta/pink background) and:
  1. Identifies the background color by sampling corners
  2. Replaces background pixels with transparency (flood-fill style)
  3. Crops to the card bounding box
  4. Resizes to 300x400 (matches Card2D's FRAME_REF_SIZE)
  5. Saves to assets/frames/<output_name>.png

Usage:
    python tools/process_new_frame.py <source.png> <output_name>

Example:
    python tools/process_new_frame.py staging/_new_frame_a.png frame_v5_a
"""

import sys
from pathlib import Path
from PIL import Image


TARGET_W, TARGET_H = 300, 400
CHROMA_TOLERANCE = 95  # max color distance to treat as background (bumped from 55 — was leaving pink fringes)
ALPHA_FEATHER = 30     # pixels at edge get partial alpha for smoother edges


def color_distance(c1, c2):
    return (
        abs(c1[0] - c2[0]) +
        abs(c1[1] - c2[1]) +
        abs(c1[2] - c2[2])
    )


def detect_background_color(img):
    # Sample 4 corner regions, return median-ish color
    w, h = img.size
    samples = []
    for cx, cy in [(20, 20), (w - 20, 20), (20, h - 20), (w - 20, h - 20)]:
        for dx in range(-5, 6, 2):
            for dy in range(-5, 6, 2):
                samples.append(img.getpixel((cx + dx, cy + dy)))
    # Median per channel
    rs = sorted(s[0] for s in samples)
    gs = sorted(s[1] for s in samples)
    bs = sorted(s[2] for s in samples)
    return (rs[len(rs)//2], gs[len(gs)//2], bs[len(bs)//2])


def find_card_bbox(img, bg_color):
    # Scan from each edge to find first non-background pixel
    w, h = img.size
    pixels = img.load()

    def is_bg(x, y):
        return color_distance(pixels[x, y][:3], bg_color) <= CHROMA_TOLERANCE

    # Find left edge
    left = 0
    for x in range(w):
        col_non_bg = sum(1 for y in range(0, h, 5) if not is_bg(x, y))
        if col_non_bg > h // 50:  # at least a few non-bg pixels in this column
            left = x
            break

    # Find right edge
    right = w - 1
    for x in range(w - 1, -1, -1):
        col_non_bg = sum(1 for y in range(0, h, 5) if not is_bg(x, y))
        if col_non_bg > h // 50:
            right = x
            break

    # Find top edge
    top = 0
    for y in range(h):
        row_non_bg = sum(1 for x in range(0, w, 5) if not is_bg(x, y))
        if row_non_bg > w // 50:
            top = y
            break

    # Find bottom edge
    bottom = h - 1
    for y in range(h - 1, -1, -1):
        row_non_bg = sum(1 for x in range(0, w, 5) if not is_bg(x, y))
        if row_non_bg > w // 50:
            bottom = y
            break

    return (left, top, right + 1, bottom + 1)


def chroma_key(img, bg_color):
    """Replace background-colored pixels with transparency."""
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            dist = color_distance((r, g, b), bg_color)
            if dist <= CHROMA_TOLERANCE:
                pixels[x, y] = (r, g, b, 0)
            elif dist <= CHROMA_TOLERANCE + ALPHA_FEATHER:
                # Soft edge — partial transparency
                feather_alpha = int(255 * (dist - CHROMA_TOLERANCE) / ALPHA_FEATHER)
                pixels[x, y] = (r, g, b, feather_alpha)
    return img


def knockout_art_window(img):
    """Knock out the art window interior by detecting the painted border.

    Strategy: the art window has a painted (slightly different shade) border
    enclosing the dark interior. We find the cream banner first to get the
    bottom edge of the art window, then knock out a rectangle from a small
    margin off the card edges down to just above the banner.
    """
    pixels = img.load()
    w, h = img.size

    def is_cream(rgba):
        r, g, b, a = rgba
        return a > 200 and r > 200 and g > 180 and b < 200 and r > b + 20

    # Find topmost cream pixel — that's the banner top edge
    banner_top = None
    for y in range(int(h * 0.3), int(h * 0.75)):
        cream_count = 0
        for x in range(int(w * 0.2), int(w * 0.8)):
            if is_cream(pixels[x, y]):
                cream_count += 1
        if cream_count > 10:
            banner_top = y
            break

    if banner_top is None:
        print("  WARNING: No banner found — guessing art window area")
        banner_top = int(h * 0.55)

    # Art window: from margin at top down to ~8px above banner top
    # Side margins: ~7% of width
    margin_x = int(w * 0.075)
    margin_top = int(h * 0.06)
    art_x0 = margin_x
    art_x1 = w - margin_x
    art_y0 = margin_top
    art_y1 = banner_top - 8

    print(f"  Banner top detected at y={banner_top}")
    print(f"  Knocking out art window: ({art_x0},{art_y0})-({art_x1},{art_y1})")

    # Only knock out pixels that are actually dark (preserves the painted border)
    def is_dark(rgba):
        r, g, b, a = rgba
        return a > 200 and r < 110 and g < 110 and b < 130

    knocked = 0
    for y in range(art_y0, art_y1 + 1):
        for x in range(art_x0, art_x1 + 1):
            if is_dark(pixels[x, y]):
                r, g, b, a = pixels[x, y]
                pixels[x, y] = (r, g, b, 0)
                knocked += 1

    print(f"  Knocked out {knocked} pixels")
    return img


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    src_path = Path(sys.argv[1])
    out_name = sys.argv[2]

    if not src_path.exists():
        print(f"ERROR: Source file not found: {src_path}")
        sys.exit(1)

    print(f"Loading {src_path}...")
    img = Image.open(src_path).convert("RGB")
    print(f"  Source size: {img.size}")

    bg = detect_background_color(img)
    print(f"  Detected background color: RGB{bg}")

    print("  Finding card bounding box...")
    bbox = find_card_bbox(img, bg)
    print(f"  Card bbox: {bbox}  (size: {bbox[2]-bbox[0]} x {bbox[3]-bbox[1]})")

    print("  Cropping to card...")
    card = img.crop(bbox)

    print(f"  Resizing to {TARGET_W}x{TARGET_H}...")
    card = card.resize((TARGET_W, TARGET_H), Image.LANCZOS)

    print("  Chroma keying background...")
    card = chroma_key(card, bg)

    # Skip art window knockout — handled in Card2D layout by placing art
    # ON TOP of the frame within the art_clip region.

    out_path = Path("assets/frames") / f"{out_name}.png"
    print(f"  Saving to {out_path}...")
    card.save(out_path)

    # Print suggested POINT_* values based on visual inspection assumptions
    print()
    print("=" * 60)
    print("SUGGESTED POINT_* values (in 300x400 ref space)")
    print("These are estimates — refine by inspecting the saved PNG.")
    print("=" * 60)
    print("const POINT_COST    := Vector2(35.0, 35.0)    # top-left orb")
    print("const POINT_NAME    := Vector2(150.0, 245.0)  # cream banner ribbon")
    print("const POINT_TYPE    := Vector2(150.0, 265.0)  # below banner")
    print("const POINT_DESC    := Vector2(150.0, 335.0)  # text well center")
    print("const POINT_ATK     := Vector2(30.0, 380.0)   # bottom-left orb")
    print("const POINT_HP      := Vector2(270.0, 380.0)  # bottom-right orb")
    print("const POINT_FLOOP   := Vector2(150.0, 390.0)  # bottom strip")
    print()
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
