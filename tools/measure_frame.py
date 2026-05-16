"""Measure painted-region centers in the card frame texture.

WHY THIS EXISTS
---------------
Card2D's v3 layout (scripts/Card2D.gd, _build_full_layout_v3) positions every
text label (cost, name, type, description, ATK, HP, FLOOP) by anchoring it to
a single POINT_* Vector2 in the 300x400 frame reference space. Those points
must land on the painted-region centers (red orbs, banner dark interior,
gold divider scroll, parchment well). Eyeballing them from the texture is
unreliable — gold ornaments / glossy highlights / frame border tones all
trick the eye. Earlier attempts put POINT_NAME 20px above the real banner.

WHAT THIS DOES
--------------
Loads assets/frames/frame_creature_common.png (and the spell variant), then
for each named feature runs a color-predicate over the pixels and reports
the bbox center. Output ends with a copy-pasteable block of GDScript const
declarations ready to drop into Card2D.gd.

HOW TO USE
----------
1. Open a shell in the project root (D:/Godot).
2. Run:  python tools/measure_frame.py
3. Read the "Godot POINT_* constants" block at the bottom of the output.
4. Replace the matching POINT_* constants in scripts/Card2D.gd's v3 layout
   header block.
5. If a feature shows NOT FOUND or an obviously wrong bbox, tighten the
   color predicate in this file (the is_* functions) and re-run. Predicates
   are intentionally narrow so frame-border colors don't pollute the bbox.

WHEN TO RE-RUN
--------------
- Whenever assets/frames/frame_*.png art changes
- When a label looks "still not centered" after tweaking POINT_* by hand
- When adding a new painted region that needs a label on it

DEPENDENCIES: Python 3.8+, Pillow (PIL).
"""

from PIL import Image
import sys
from pathlib import Path

FRAME_PATHS = [
    "assets/frames/frame_creature_common.png",
    "assets/frames/frame_spell_common.png",
]


def find_bbox(img, predicate, search_rect=None):
    """Find tightest bbox of pixels matching predicate(r,g,b,a) inside search_rect."""
    w, h = img.size
    x0, y0, x1, y1 = search_rect if search_rect else (0, 0, w, h)
    min_x, min_y, max_x, max_y = w, h, -1, -1
    px = img.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if predicate(r, g, b, a):
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    if max_x < 0:
        return None
    return (min_x, min_y, max_x, max_y)


def center_of(bbox):
    if bbox is None:
        return None
    x0, y0, x1, y1 = bbox
    return ((x0 + x1) / 2.0, (y0 + y1) / 2.0)


def describe(name, bbox):
    if bbox is None:
        print(f"  {name:18s}  NOT FOUND")
        return None
    x0, y0, x1, y1 = bbox
    cx, cy = center_of(bbox)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    print(f"  {name:18s}  bbox=({x0:3d},{y0:3d})-({x1:3d},{y1:3d})  "
          f"size={w:3d}x{h:3d}  center=({cx:6.1f}, {cy:6.1f})")
    return (cx, cy)


# Predicates for the painted features. Cinzel — keep these tight enough to
# isolate each region but loose enough to handle JPEG-like color drift.

def is_bright_red(r, g, b, a):
    # Red orb glossy core (top cost orb): vivid R, low G, low B, opaque.
    return a > 200 and r > 150 and g < 90 and b < 90


def is_any_red_orb(r, g, b, a):
    # Bottom ATK orb is slightly darker than top, but still a saturated red.
    # The frame's brown wood border (~r=120,g=70,b=40) must be EXCLUDED — it
    # also has r > g, r > b. So require g and b both small AND r-g separation
    # large enough that warm browns don't qualify.
    return a > 200 and r > 130 and g < 75 and b < 75 and (r - g) > 70


def is_blue_orb(r, g, b, a):
    # Blue HP orb — B dominates, accept a range of shades from glossy to deep.
    return a > 200 and b > 100 and b > r + 30 and b > g - 10 and r < 130


def is_art_window_white(r, g, b, a):
    # Inner art panel: near-white. The frame's art rect is actually fully
    # transparent in the source (alpha=0 lets art behind show through), so
    # search for alpha=0 instead of white pixels.
    return a < 30


def is_parchment(r, g, b, a):
    # Tan/cream paper of the bottom well: warm yellow-brown.
    return a > 200 and 180 <= r <= 245 and 140 <= g <= 220 and 80 <= b <= 180 \
        and r > b + 20


def is_dark_banner_core(r, g, b, a):
    # Dark gray interior of the banner — but reject the very black frame
    # edge by requiring at least a faint gray (not pure black).
    return a > 200 and 20 <= r <= 100 and 20 <= g <= 100 and 20 <= b <= 100 \
        and max(r, g, b) - min(r, g, b) < 25


def is_gold_scroll(r, g, b, a):
    # Gold/brass color of the divider scroll graphic between art and well.
    return a > 200 and 170 <= r <= 240 and 130 <= g <= 200 and b < 130 \
        and r > b + 50


def measure(path):
    print(f"\n=== {path} ===")
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    print(f"  image size: {w}x{h}")

    # Cost orb: top-left quadrant, red pixels.
    cost_bbox = find_bbox(img, is_bright_red,
                          search_rect=(0, 0, w // 2, h // 4))
    cost_c = describe("cost_orb", cost_bbox)

    # Banner: top strip, dark pixels right of the cost orb. Cap the right
    # search edge to skip the gold curl-tail end-cap so its dark fringe
    # doesn't extend the bbox right.
    banner_x0 = (cost_bbox[2] + 5) if cost_bbox else w // 4
    banner_bbox = find_bbox(img, is_dark_banner_core,
                            search_rect=(banner_x0, 0, int(w * 0.92), h // 6))
    banner_c = describe("banner_dark", banner_bbox)

    # Art window: transparent rect in the middle (alpha=0).
    art_bbox = find_bbox(img, is_art_window_white,
                         search_rect=(0, h // 6, w, int(h * 0.65)))
    art_c = describe("art_window", art_bbox)

    # Divider scroll: just below the art, gold/brass band.
    scroll_y0 = art_bbox[3] - 2 if art_bbox else int(h * 0.60)
    scroll_y1 = scroll_y0 + 40
    scroll_bbox = find_bbox(img, is_gold_scroll,
                            search_rect=(int(w * 0.15), scroll_y0,
                                         int(w * 0.85), scroll_y1))
    scroll_c = describe("divider_scroll", scroll_bbox)

    # Parchment well: below the scroll.
    well_y0 = (scroll_bbox[3] + 2) if scroll_bbox else int(h * 0.66)
    well_bbox = find_bbox(img, is_parchment,
                          search_rect=(int(w * 0.10), well_y0,
                                       int(w * 0.90), int(h * 0.95)))
    well_c = describe("parchment_well", well_bbox)

    # ATK orb: bottom-left, red pixels in the bottom strip. Uses the looser
    # red predicate to catch the darker bottom orb.
    atk_bbox = find_bbox(img, is_any_red_orb,
                         search_rect=(0, int(h * 0.7), w // 2, h))
    atk_c = describe("atk_orb", atk_bbox)

    # HP orb: bottom-right, blue pixels in the bottom strip.
    hp_bbox = find_bbox(img, is_blue_orb,
                       search_rect=(w // 2, int(h * 0.7), w, h))
    hp_c = describe("hp_orb", hp_bbox)

    return {
        "cost": cost_c, "name": banner_c, "art": art_c,
        "type": scroll_c, "desc": well_c,
        "atk": atk_c, "hp": hp_c,
    }


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parent.parent
    results = {}
    for rel in FRAME_PATHS:
        path = project_root / rel
        if not path.exists():
            print(f"missing: {path}", file=sys.stderr)
            continue
        results[rel] = measure(str(path))

    # Print Godot-ready POINT_* constants from the creature frame's centers.
    print("\n=== Godot POINT_* constants (creature frame, 300x400 ref) ===")
    creature = results.get(FRAME_PATHS[0])
    if creature:
        mapping = [
            ("POINT_COST",  "cost"),
            ("POINT_NAME",  "name"),
            ("POINT_TYPE",  "type"),
            ("POINT_DESC",  "desc"),
            ("POINT_ATK",   "atk"),
            ("POINT_HP",    "hp"),
        ]
        for name, key in mapping:
            c = creature.get(key)
            if c is None:
                print(f"  {name}: NOT MEASURED")
            else:
                print(f"  const {name:14s} := Vector2({c[0]:6.1f}, {c[1]:6.1f})")
