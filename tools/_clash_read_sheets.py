"""Contact sheets + zoom crops over the frames _shot_clash_read.gd captured.

    python tools/_clash_read_sheets.py

174 frames at ~63 ms is far too many to read one at a time, and a single frame
cannot answer a PACING question anyway. So: contact sheets to see the shape of
the clash, then named crops blown up 2x for the questions that turn on whether a
17 px chip is readable (corpse names, forecast chips, the ledger line).

Frames are 1920x1080 (the desktop applies 1.2x DPI scaling to the 1600x900
canvas), so every rect below is in FRAME pixels, not canvas pixels.
"""
import glob
import os
import re

from PIL import Image, ImageDraw

SRC = os.path.join(os.path.dirname(__file__), "screenshot", "clash_read")
OUT = SRC

# Board geometry, measured off plan_full.png.
BOARD = (330, 85, 1600, 900)          # the whole arena plate
ENEMY_ROWS = (330, 85, 1600, 490)     # enemy back + front
PLAYER_ROWS = (330, 490, 1600, 900)   # player front + back
CENTRE = (430, 330, 1520, 780)        # both inner ranks, where the clash happens


def frames():
    out = []
    for p in sorted(glob.glob(os.path.join(SRC, "f*ms.jpg"))):
        m = re.search(r"f(\d+)_(\d+)ms", os.path.basename(p))
        out.append((int(m.group(1)), int(m.group(2)), p))
    return out


def sheet(rows, cols, cell_w, items, name, crop=None):
    cell_h = int(cell_w * 1080 / 1920) if crop is None else \
        int(cell_w * (crop[3] - crop[1]) / (crop[2] - crop[0]))
    img = Image.new("RGB", (cols * cell_w, rows * (cell_h + 16)), (12, 10, 9))
    d = ImageDraw.Draw(img)
    for i, (idx, ms, path) in enumerate(items):
        if i >= rows * cols:
            break
        f = Image.open(path)
        if crop:
            f = f.crop(crop)
        f = f.resize((cell_w, cell_h), Image.LANCZOS)
        x = (i % cols) * cell_w
        y = (i // cols) * (cell_h + 16)
        img.paste(f, (x, y + 16))
        d.text((x + 4, y + 3), "f%03d  %d ms" % (idx, ms), fill=(255, 210, 120))
        d.rectangle([x, y + 16, x + cell_w - 1, y + cell_h + 15], outline=(70, 55, 45))
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


def crop_zoom(path, rect, name, zoom=2):
    f = Image.open(path).crop(rect)
    f = f.resize((f.width * zoom, f.height * zoom), Image.LANCZOS)
    f.save(os.path.join(OUT, name))
    print("wrote", name, f.size)


def main():
    fs = frames()
    print("%d frames, %d..%d ms" % (len(fs), fs[0][1], fs[-1][1]))

    # Overview: the whole clash at a glance, board only (the hand and the side
    # HUD are constant and would waste half of every cell).
    for i, lo in enumerate(range(0, len(fs), 30)):
        sheet(6, 5, 384, fs[lo:lo + 30], "sheet_%d.jpg" % i, crop=BOARD)

    # Named zooms for the taste questions.
    by_ms = {ms: p for _, ms, p in fs}

    def near(target):
        k = min(by_ms, key=lambda m: abs(m - target))
        return by_ms[k], k

    picks = [
        ("z_front_lane1", 1249, CENTRE),        # front rank, the no-kill column
        ("z_front_lane2_kill", 1892, CENTRE),   # front rank, the double-kill column
        ("z_face_lane3", 3155, CENTRE),         # the face strike
        ("z_back_rank_open", 3702, CENTRE),     # back-rank caption
        ("z_fallen_cap", 5402, CENTRE),         # THE FALLEN, before the flush
        ("z_flush_1", 5658, CENTRE),
        ("z_flush_2", 5854, CENTRE),
        ("z_flush_3", 6045, CENTRE),
        ("z_ledger", 6550, BOARD),              # the post-clash line
        ("z_ledger2", 6740, BOARD),
    ]
    for name, ms, rect in picks:
        p, real = near(ms)
        crop_zoom(p, rect, "%s_%dms.jpg" % (name, real))

    # Forecast detail — is OVERKILL printed, and can you tell the arrows apart?
    crop_zoom(os.path.join(SRC, "plan_full.png"),
              (960, 85, 1600, 900), "z_plan_lane23.png", 2)
    crop_zoom(os.path.join(SRC, "plan_full.png"),
              (330, 240, 1010, 780), "z_plan_lane01.png", 2)
    crop_zoom(os.path.join(SRC, "plan_enemy_only.png"),
              (330, 85, 1600, 900), "z_plan_enemy_only.png", 1)


if __name__ == "__main__":
    main()
