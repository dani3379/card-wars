"""Pixel measurements over the _shot_clash_read frames.

    python tools/_clash_read_measure.py

Two questions the eye cannot answer honestly on its own:

  A. HOW STRONG, AND HOW LONG, IS THE FACE-DAMAGE WASH?  `_play_face_damage_flash`
     covers the WHOLE screen. "It looks red" is not a finding; "the hand cards
     lost 40% of their contrast for 330 ms over ONE point of damage" is. Sampled
     on the HAND (bottom strip), which is nowhere near the lane that was hit and
     therefore should not have been touched at all.

  B. DOES ClashLaneFocus ACTUALLY DARKEN THE UNFOCUSED LANES?  Measured the only
     way that cannot be fooled: take the SAME patch of board and compare it
     between a frame where its column is focused and one where it is not. A
     within-frame comparison would be comparing different card art.
"""
import glob
import os
import re

from PIL import Image

SRC = os.path.join(os.path.dirname(__file__), "screenshot", "clash_read")

# Lane centres in FRAME pixels (1920x1080). Sampled on the empty back-row slot
# of each column, which is inert board plate — no card art, no chips, no flash.
LANE_X = [478, 800, 1120, 1440]
EMPTY_BACK_Y = (720, 860)      # player back row band
EMPTY_FRONT_Y = (110, 270)     # enemy back row band
HAND = (430, 940, 1480, 1070)  # the hand fan, far from any lane


def frames():
    out = []
    for p in sorted(glob.glob(os.path.join(SRC, "f*ms.jpg"))):
        m = re.search(r"f(\d+)_(\d+)ms", os.path.basename(p))
        out.append((int(m.group(1)), int(m.group(2)), p))
    return out


def patch(img, box):
    c = img.crop(box)
    px = list(c.getdata())
    n = len(px)
    r = sum(p[0] for p in px) / n
    g = sum(p[1] for p in px) / n
    b = sum(p[2] for p in px) / n
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return r, g, b, lum


def main():
    fs = frames()
    imgs = {ms: Image.open(p).convert("RGB") for _, ms, p in fs}

    print("=== A. the face-damage wash, sampled on the HAND (never in the lane hit) ===")
    print("   ms |    R     G     B  |  lum  | redness R-(G+B)/2")
    for idx, ms, _ in fs[:14]:
        r, g, b, lum = patch(imgs[ms], HAND)
        print("%5d | %5.1f %5.1f %5.1f | %5.1f | %+6.1f" % (
            ms, r, g, b, lum, r - (g + b) / 2.0))

    print()
    print("=== B. ClashLaneFocus — same patch, focused vs unfocused frame ===")
    # From the trace: focus sits on lane 1 (cx=394) 525-1618 ms and on lane 2
    # (cx=662) 1618-2961 ms. Pick a settled frame inside each dwell.
    a_ms = min(imgs, key=lambda m: abs(m - 1249))   # focus = lane 1
    b_ms = min(imgs, key=lambda m: abs(m - 2661))   # focus = lane 2
    print("   frame A (%d ms): spotlight on LANE 1" % a_ms)
    print("   frame B (%d ms): spotlight on LANE 2" % b_ms)
    print("   lane | band        |  A lum |  B lum | B/A   (expect <1 where A is lit)")
    for li, lx in enumerate(LANE_X):
        for band_name, band in (("back(you)", EMPTY_BACK_Y), ("back(foe)", EMPTY_FRONT_Y)):
            box = (lx - 90, band[0], lx + 90, band[1])
            _, _, _, la = patch(imgs[a_ms], box)
            _, _, _, lb = patch(imgs[b_ms], box)
            print("   %4d | %-11s | %6.2f | %6.2f | %.3f" % (
                li, band_name, la, lb, (lb / la) if la > 0.01 else 0))

    print()
    print("=== B2. the spotlight over the WHOLE front-rank pass (lane-1 board plate) ===")
    box = (LANE_X[1] - 90, EMPTY_BACK_Y[0], LANE_X[1] + 90, EMPTY_BACK_Y[1])
    print("   lane-1 plate luminance across the clash (focus lane per the trace):")
    for idx, ms, _ in fs:
        if ms > 6200:
            break
        if idx % 3:
            continue
        _, _, _, l = patch(imgs[ms], box)
        bar = "#" * int(l * 1.6)
        print("   %5d ms  %5.2f  %s" % (ms, l, bar))


if __name__ == "__main__":
    main()
