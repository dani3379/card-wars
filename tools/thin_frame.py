"""Thin card-frame borders using a 9-slice approach.

Slices the frame into 9 regions: 4 corners (preserved at full resolution),
4 edges (scaled thinner inward), and a center (passed through). Reassembles
at the original image size with thinner borders.

Usage:
    python tools/thin_frame.py                       # all creature + spell frames
    python tools/thin_frame.py assets/frames/frame_creature_common.png  # one file
    python tools/thin_frame.py --ratio 0.55           # custom shrink (default 0.6)

The script writes *_thin.png next to each input.

Requires: Pillow (pip install Pillow).
"""

from PIL import Image
import sys
from pathlib import Path


# ── Border measurements (from pixel analysis of 928x1232 frame) ──────────
# The border structure (outside-in): dark outer ~30px, decorative red/gold
# band ~100px, inner parchment fringe ~25px, then the content area.
# Total border: ~155px left, ~157px top, ~153px right, ~146px bottom.
#
# Corner ornaments (gold notch shapes) extend roughly 200px in from each
# corner in both axes. We size the corner patches to capture these fully.

# 9-slice boundaries as fractions of image size.
# These define where the corner patches end and the tileable edge strips begin.
# Chosen so corners capture the ornamental notch shapes completely.

# Corner patch size: large enough to hold the full corner ornament
CORNER_FRAC_X = 0.22   # ~204px of 928 — covers corner gold notch + some edge
CORNER_FRAC_Y = 0.17   # ~209px of 1232

# Border extent: how deep the border goes from each edge before hitting content
BORDER_LEFT   = 155     # px where parchment starts from left
BORDER_RIGHT  = 153     # px where parchment starts from right
BORDER_TOP    = 157     # px where parchment starts from top
BORDER_BOTTOM = 146     # px where parchment starts from bottom


def nine_slice_thin(img: Image.Image, ratio: float = 0.6) -> Image.Image:
    """Thin the border of a card frame image using 9-slice scaling.

    Args:
        img:   RGBA frame image (e.g. 928x1232).
        ratio: How much to shrink border thickness (0.5 = half, 0.7 = 30% thinner).

    Returns:
        New RGBA image, same size as input, with thinner borders.
    """
    w, h = img.size

    # Slice coordinates
    cx = int(w * CORNER_FRAC_X)       # corner patch width
    cy = int(h * CORNER_FRAC_Y)       # corner patch height
    right_x = w - cx                   # right corner starts here

    # After thinning, borders become:
    new_border_l = int(BORDER_LEFT * ratio)
    new_border_r = int(BORDER_RIGHT * ratio)
    new_border_t = int(BORDER_TOP * ratio)
    new_border_b = int(BORDER_BOTTOM * ratio)

    # The corners get scaled to new_border size while preserving aspect
    new_cx = int(cx * ratio)
    new_cy = int(cy * ratio)

    # ── Extract the 9 patches ──
    # Corners
    tl = img.crop((0,        0,        cx,   cy))
    tr = img.crop((right_x,  0,        w,    cy))
    bl = img.crop((0,        h - cy,   cx,   h))
    br = img.crop((right_x,  h - cy,   w,    h))

    # Edges (strips between corners)
    top_edge    = img.crop((cx, 0,        right_x, cy))
    bottom_edge = img.crop((cx, h - cy,   right_x, h))
    left_edge   = img.crop((0,  cy,       cx,      h - cy))
    right_edge  = img.crop((right_x, cy,  w,       h - cy))

    # Center
    center = img.crop((cx, cy, right_x, h - cy))

    # ── Scale the patches ──
    # Corners: scale uniformly by ratio
    tl_s = tl.resize((new_cx, new_cy), Image.LANCZOS)
    tr_s = tr.resize((new_cx, new_cy), Image.LANCZOS)
    bl_s = bl.resize((new_cx, new_cy), Image.LANCZOS)
    br_s = br.resize((new_cx, new_cy), Image.LANCZOS)

    # Edge widths in the new layout
    new_center_w = w - 2 * new_cx
    new_center_h = h - 2 * new_cy

    # Edges: scale to new thickness (perpendicular to edge) but stretch
    # to fill the new center span (parallel to edge).
    top_s    = top_edge.resize((new_center_w, new_cy), Image.LANCZOS)
    bottom_s = bottom_edge.resize((new_center_w, new_cy), Image.LANCZOS)
    left_s   = left_edge.resize((new_cx, new_center_h), Image.LANCZOS)
    right_s  = right_edge.resize((new_cx, new_center_h), Image.LANCZOS)

    # Center: scale to fill remaining area
    center_s = center.resize((new_center_w, new_center_h), Image.LANCZOS)

    # ── Reassemble ──
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    # Corners
    out.paste(tl_s, (0, 0))
    out.paste(tr_s, (w - new_cx, 0))
    out.paste(bl_s, (0, h - new_cy))
    out.paste(br_s, (w - new_cx, h - new_cy))

    # Edges
    out.paste(top_s,    (new_cx, 0))
    out.paste(bottom_s, (new_cx, h - new_cy))
    out.paste(left_s,   (0, new_cy))
    out.paste(right_s,  (w - new_cx, new_cy))

    # Center
    out.paste(center_s, (new_cx, new_cy))

    return out


DEFAULT_FRAMES = [
    "assets/frames/frame_creature_common.png",
    "assets/frames/frame_creature_uncommon.png",
    "assets/frames/frame_creature_rare.png",
    "assets/frames/frame_creature_starter.png",
    "assets/frames/frame_spell_common.png",
    "assets/frames/frame_spell_uncommon.png",
    "assets/frames/frame_spell_rare.png",
    "assets/frames/frame_spell_starter.png",
    "assets/frames/frame_curse.png",
]


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Thin card-frame borders (9-slice)")
    parser.add_argument("files", nargs="*",
                        help="Frame PNG paths (default: all creature+spell frames)")
    parser.add_argument("--ratio", type=float, default=0.6,
                        help="Border shrink ratio, 0-1 (default 0.6 = 40%% thinner)")
    parser.add_argument("--suffix", default="_thin",
                        help="Output filename suffix (default: _thin)")
    parser.add_argument("--replace", action="store_true",
                        help="Overwrite originals instead of writing *_thin.png")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent.parent
    files = args.files if args.files else DEFAULT_FRAMES

    for rel in files:
        path = project_root / rel
        if not path.exists():
            print(f"  SKIP (missing): {path}")
            continue

        img = Image.open(str(path)).convert("RGBA")
        print(f"  {rel}: {img.size[0]}x{img.size[1]}, ratio={args.ratio}")

        result = nine_slice_thin(img, ratio=args.ratio)

        if args.replace:
            out_path = path
        else:
            out_path = path.with_stem(path.stem + args.suffix)

        result.save(str(out_path), "PNG")
        print(f"    -> {out_path.name}")

    print("\nDone. Run `python tools/measure_frame.py` on the new frames to get"
          " updated POINT_* constants for Card2D.gd.")


if __name__ == "__main__":
    main()
