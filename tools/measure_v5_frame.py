"""Measure the painted region centers in a v5 frame.

Scans for:
  - Cream/tan banner ribbon (high R, high G, lowish B)
  - Dark art window interior (top large dark region)
  - Dark text well interior (bottom dark region)

Outputs POINT_* values for Card2D.gd in 300x400 reference space.

Usage:
    python tools/measure_v5_frame.py assets/frames/frame_v5_a.png
"""

import sys
from PIL import Image
from pathlib import Path


def is_cream(rgba):
    r, g, b, a = rgba
    return a > 200 and r > 200 and g > 180 and b < 200 and r > b + 20


def is_dark_interior(rgba):
    r, g, b, a = rgba
    # Dark grey/charcoal/navy interior
    return a > 200 and r < 90 and g < 90 and b < 110


def find_bbox(img, predicate, search_rect=None):
    w, h = img.size
    pixels = img.load()
    if search_rect is None:
        x0, y0, x1, y1 = 0, 0, w, h
    else:
        x0, y0, x1, y1 = search_rect

    min_x, min_y = w, h
    max_x, max_y = -1, -1
    count = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            if predicate(pixels[x, y]):
                count += 1
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    if count == 0:
        return None
    return (min_x, min_y, max_x, max_y, count)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    path = Path(sys.argv[1])
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    print(f"Frame: {path}  Size: {w}x{h}")

    # Banner: cream pixels anywhere in middle band
    banner = find_bbox(img, is_cream, (0, int(h * 0.3), w, int(h * 0.75)))
    if banner:
        bx0, by0, bx1, by1, bc = banner
        bcx, bcy = (bx0 + bx1) / 2, (by0 + by1) / 2
        print(f"  Banner bbox: ({bx0},{by0})-({bx1},{by1})  center=({bcx:.1f},{bcy:.1f})  pixels={bc}")
    else:
        print("  Banner: NOT FOUND")
        bcx, bcy = 150, 245

    # Art window: dark interior in top half
    art = find_bbox(img, is_dark_interior, (0, 0, w, int(h * 0.5)))
    if art:
        ax0, ay0, ax1, ay1, ac = art
        print(f"  Art window bbox: ({ax0},{ay0})-({ax1},{ay1})  center=({(ax0+ax1)/2:.1f},{(ay0+ay1)/2:.1f})")
    else:
        print("  Art window: NOT FOUND")

    # Text well: dark interior in bottom portion (below banner)
    text_top = int(bcy + 25) if banner else int(h * 0.65)
    text = find_bbox(img, is_dark_interior, (0, text_top, w, h))
    if text:
        tx0, ty0, tx1, ty1, tc = text
        tcx, tcy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
        print(f"  Text well bbox: ({tx0},{ty0})-({tx1},{ty1})  center=({tcx:.1f},{tcy:.1f})")
    else:
        print("  Text well: NOT FOUND")
        tcx, tcy = 150, 335

    print()
    print("=" * 60)
    print("Godot POINT_* constants (300x400 ref space)")
    print("=" * 60)
    print(f"const POINT_COST    := Vector2(35.0, 35.0)         # top-left orb (sits on art window corner)")
    print(f"const POINT_NAME    := Vector2({bcx:.1f}, {bcy:.1f})       # banner ribbon center")
    print(f"const POINT_TYPE    := Vector2({bcx:.1f}, {bcy+20:.1f})       # type line below banner")
    print(f"const POINT_DESC    := Vector2({tcx:.1f}, {tcy:.1f})       # text well center")
    print(f"const POINT_ATK     := Vector2(30.0, 380.0)        # bottom-left orb")
    print(f"const POINT_HP      := Vector2(270.0, 380.0)       # bottom-right orb")
    print(f"const POINT_FLOOP   := Vector2(150.0, 390.0)       # bottom strip")


if __name__ == "__main__":
    main()
