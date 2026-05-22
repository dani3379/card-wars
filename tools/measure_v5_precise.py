"""Precise pixel measurement of v5 frame zones.

Scans the frame for:
  - Card body bbox (where alpha > 0)
  - Painted outer edge / inner card body boundary
  - Cream banner top, bottom, center
  - Top art window border (between cost-orb-area and banner)
  - Bottom text well border

Prints both:
  1. Raw pixel coords (in the 300x400 frame ref space)
  2. Suggested POINT_* and anchor values for Card2D.gd
"""

import sys
from PIL import Image
from pathlib import Path


def main():
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/frames/frame_v5_b.png")
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    pixels = img.load()
    print(f"Frame: {path}  Size: {w}x{h}")

    # 1. Card body bbox (where alpha > 0)
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] > 30:
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    print(f"\nCard body bbox: ({min_x},{min_y})-({max_x},{max_y})")
    print(f"  Inset from edges: left={min_x}, top={min_y}, right={w-max_x}, bottom={h-max_y}")

    # 2. Cream banner — find top edge and bottom edge of cream pixels
    def is_cream(p):
        r, g, b, a = p
        return a > 200 and r > 190 and g > 170 and b < 200 and r > b + 25

    cream_pixels_by_row = {}
    for y in range(h):
        count = 0
        for x in range(w):
            if is_cream(pixels[x, y]):
                count += 1
        if count > 5:
            cream_pixels_by_row[y] = count

    if cream_pixels_by_row:
        banner_rows = sorted(cream_pixels_by_row.keys())
        # Find rows where banner is dense (not isolated gold trim pixels)
        dense_rows = [y for y, c in cream_pixels_by_row.items() if c > 30]
        if dense_rows:
            banner_top = min(dense_rows)
            banner_bottom = max(dense_rows)
            banner_center = (banner_top + banner_bottom) / 2
            print(f"\nBanner cream area:")
            print(f"  Top: y={banner_top}")
            print(f"  Bottom: y={banner_bottom}")
            print(f"  Center: y={banner_center:.1f}")
            print(f"  Height: {banner_bottom - banner_top + 1}px")

    # 3. Art window — dark interior in upper portion, bordered by painted edge
    # Find the rectangle of dark pixels in upper half
    def is_card_interior(p):
        r, g, b, a = p
        # Charcoal/dark navy interior of the card (NOT the outer painted edge)
        return a > 200 and 30 < r < 100 and 30 < g < 100 and 35 < b < 120

    dark_in_top = {}
    for y in range(int(h * 0.4)):
        for x in range(w):
            if is_card_interior(pixels[x, y]):
                dark_in_top.setdefault(y, []).append(x)

    # Art window y-range: from where dark pixels start to ~10px above banner top
    if dark_in_top:
        art_y_start = min(dark_in_top.keys())
        # Get x-range from middle row
        mid_y = (art_y_start + banner_top) // 2
        if mid_y in dark_in_top:
            xs = dark_in_top[mid_y]
            art_x_left = min(xs)
            art_x_right = max(xs)
            art_y_end = banner_top - 10  # 10px gap above banner
            print(f"\nArt window approximate inner rect:")
            print(f"  ({art_x_left}, {art_y_start}) - ({art_x_right}, {art_y_end})")
            print(f"  Width: {art_x_right - art_x_left}px  Height: {art_y_end - art_y_start}px")

    # 4. Text well in lower portion
    dark_in_bottom = {}
    text_zone_start = int(banner_bottom + 10) if banner_bottom else int(h * 0.65)
    for y in range(text_zone_start, h):
        for x in range(w):
            if is_card_interior(pixels[x, y]):
                dark_in_bottom.setdefault(y, []).append(x)

    if dark_in_bottom:
        tw_y_start = min(dark_in_bottom.keys())
        tw_y_end = max(dark_in_bottom.keys())
        mid_y = (tw_y_start + tw_y_end) // 2
        if mid_y in dark_in_bottom:
            xs = dark_in_bottom[mid_y]
            tw_x_left = min(xs)
            tw_x_right = max(xs)
            tw_x_center = (tw_x_left + tw_x_right) / 2
            tw_y_center = (tw_y_start + tw_y_end) / 2
            print(f"\nText well approximate inner rect:")
            print(f"  ({tw_x_left}, {tw_y_start}) - ({tw_x_right}, {tw_y_end})")
            print(f"  Width: {tw_x_right - tw_x_left}px  Height: {tw_y_end - tw_y_start}px")
            print(f"  Center: ({tw_x_center:.1f}, {tw_y_center:.1f})")

    print()
    print("=" * 60)
    print("Computed Card2D.gd values")
    print("=" * 60)
    print()
    print("# POINT_* constants (300x400 ref space):")
    print(f"const POINT_COST    := Vector2(35.0, {art_y_start + 10:.1f})    # top-left of art window")
    print(f"const POINT_NAME    := Vector2(150.0, {banner_center:.1f})   # banner center")
    print(f"const POINT_TYPE    := Vector2(150.0, {banner_bottom + 8:.1f})   # below banner")
    print(f"const POINT_DESC    := Vector2({tw_x_center:.1f}, {tw_y_center:.1f})   # text well center")
    print(f"const POINT_ATK     := Vector2(30.0, {tw_y_end - 5:.1f})    # bottom-left")
    print(f"const POINT_HP      := Vector2(270.0, {tw_y_end - 5:.1f})   # bottom-right")
    print(f"const POINT_FLOOP   := Vector2(150.0, {h - 8:.1f})    # between bottom orbs")
    print()
    print("# art_clip anchors (in _build_full_layout_v3):")
    print(f"art_clip.anchor_left   = {art_x_left/w:.3f}")
    print(f"art_clip.anchor_right  = {art_x_right/w:.3f}")
    print(f"art_clip.anchor_top    = {art_y_start/h:.3f}")
    print(f"art_clip.anchor_bottom = {art_y_end/h:.3f}")


if __name__ == "__main__":
    main()
