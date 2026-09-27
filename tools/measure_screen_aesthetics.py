"""measure_screen_aesthetics.py — objective layout measures for a shell screen.

    python tools/measure_screen_aesthetics.py tools/screenshot/_runstart_setup_open.png
    python tools/measure_screen_aesthetics.py --sweep        # every shell shot we have

WHY THIS EXISTS. Every other gate in this harness judges a control against
ITSELF (does the text fit, is it covered, can the click reach it) or against the
controls BESIDE it (`_probe_alignment`, C30). None of them can see the fault that
made this file necessary: a screen where every control is individually correct and
the COMPOSITION answers a different question than the screen asks. That is not a
matter of taste — it is measurable, and the measures below are the published ones.

WHAT IT MEASURES, and the source for each:

  Ngo/Teo/Byrne (2003) BALANCE, EQUILIBRIUM, HOMOGENEITY, DENSITY.
      Fourteen computable measures of screen aesthetics. Altaboli & Lin (2011)
      then ran a controlled experiment over the three that carry the model and
      found BALANCE (p=.0009) and UNITY (p=.0001) significant while SEQUENCE was
      only marginal (p=.100) — so balance is the one worth gating.

  EDGE DENSITY + JPEG COMPRESSIBILITY as visual complexity.
      The two strongest computational predictors of human complexity ratings.
      Tuch et al. (2012) measured complexity driving first impressions at 17ms;
      Reinecke et al. (CHI 2013) modelled ~half the variance in appeal at 500ms
      from complexity + colourfulness. High complexity is the punished direction.

  COLOURFULNESS (Hasler & Susstrunk 2003, M3) — the metric Reinecke used.

  SQUINT PYRAMID. The practitioner standard (NN/g, LukeW) for reading visual
      hierarchy without detail: downsample hard, and whatever survives is what
      the player sees in the first fixation. Ranked per named region, this
      answers "is the loudest thing on the page the thing the page is for?"

OPTICAL WEIGHT is luminance above the page's OWN background floor (35th
percentile), not a flat threshold — these screens are painted, so a flat
threshold counts the wallpaper as ink and every measure comes out wrong.

REGIONS are optional. Without them you get page-level numbers; with them you get
the ranking that actually names the defect. Pass a JSON file of
{"label": [x0,y0,x1,y1], ...} in SHOT pixel coordinates via --regions.
"""
import sys, io, os, json, glob
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

SHELL_SHOTS = [
    ("_runstart_menu",        "main menu"),
    ("_runstart_setup_open",  "RUN SETUP"),
    ("_runstart_quick_march", "quick march"),
    ("_runstart_bonus_gloss", "starting bonus"),
    ("_aud_shop",             "shop"),
    ("_aud_reward",           "reward"),
    ("_aud_event",            "event"),
    ("_aud_rest",             "rest/camp"),
    ("_aud_game_over",        "game over"),
]
SHOT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "screenshot")


def weight_map(img):
    """Optical weight: luminance above the page's own resting tone."""
    a = np.asarray(img).astype(np.float64) / 255.0
    lum = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    return np.clip(lum - np.percentile(lum, 35), 0, None), lum, a


def page_measures(img):
    W, H = img.size
    wt, lum, a = weight_map(img)
    tot = wt.sum()
    ys, xs = np.mgrid[0:H, 0:W]
    cx, cy = (wt * xs).sum() / tot, (wt * ys).sum() / tot

    wl, wr = wt[:, :W // 2].sum(), wt[:, W // 2:].sum()
    wtp, wbt = wt[:H // 2, :].sum(), wt[H // 2:, :].sum()
    q = [wt[:H//2, :W//2].sum(), wt[:H//2, W//2:].sum(),
         wt[H//2:, :W//2].sum(), wt[H//2:, W//2:].sum()]

    g = np.asarray(Image.fromarray((lum * 255).astype(np.uint8))
                   .filter(ImageFilter.GaussianBlur(1.0))).astype(float)
    edge = (np.hypot(np.gradient(g, axis=1), np.gradient(g, axis=0)) > 12).mean()

    buf = io.BytesIO(); img.save(buf, "JPEG", quality=75)
    R, G, B = a[..., 0] * 255, a[..., 1] * 255, a[..., 2] * 255
    rg, yb = R - G, 0.5 * (R + G) - B
    cf = np.sqrt(rg.std()**2 + yb.std()**2) + 0.3 * np.sqrt(rg.mean()**2 + yb.mean()**2)

    return dict(
        W=W, H=H, wt=wt, cx=cx, cy=cy,
        equilibrium=1 - (abs(2*(cx-W/2)/W) + abs(2*(cy-H/2)/H)) / 2,
        balance_v=1 - abs(wl-wr)/max(wl, wr),
        balance_h=1 - abs(wtp-wbt)/max(wtp, wbt),
        left_pct=wl/tot*100, right_pct=wr/tot*100,
        quadrants=[x/tot*100 for x in q],
        density=(wt > 0.06).mean()*100,
        edge_density=edge*100,
        jpeg_kb=len(buf.getvalue())/1024,
        colourfulness=cf,
    )


def report(path, regions=None, write_squint=True):
    img = Image.open(path).convert("RGB")
    m = page_measures(img)
    W, H, wt = m["W"], m["H"], m["wt"]
    name = os.path.splitext(os.path.basename(path))[0]
    print(f"=== {name}  {W}x{H} ===")
    print(f"  centre of optical mass  x {m['cx']/W:.3f}  y {m['cy']/H:.3f} of the canvas")
    print(f"  Ngo equilibrium         {m['equilibrium']:.3f}   (1.0 = mass sits at centre)")
    print(f"  Ngo balance  vertical   {m['balance_v']:.3f}   "
          f"left {m['left_pct']:.1f}% | right {m['right_pct']:.1f}%")
    print(f"  Ngo balance  horizontal {m['balance_h']:.3f}")
    print(f"  quadrants TL/TR/BL/BR   " +
          " ".join(f"{q:5.1f}%" for q in m["quadrants"]) + "   (even = 25% each)")
    print(f"  density (ink coverage)  {m['density']:.2f}%")
    print(f"  edge density            {m['edge_density']:.2f}%   <- visual complexity")
    print(f"  JPEG-75                 {m['jpeg_kb']:.0f} KB")
    print(f"  colourfulness (H&S M3)  {m['colourfulness']:.1f}")

    c = wt[H//2-60:H//2+60, W//2-60:W//2+60]
    print(f"  first-fixation patch    {c.mean()/wt.mean():.2f}x page mean weight "
          f"(central fixation bias lands here before anything else)")

    if regions:
        total = wt.sum()
        sm = np.asarray(img.resize((W//24, H//24), Image.LANCZOS).convert("L")).astype(float)/255
        sm_w = np.clip(sm - np.percentile(sm, 35), 0, None)
        rows = []
        for label, (x0, y0, x1, y1) in regions.items():
            sub = wt[y0:y1, x0:x1]
            sq = sm_w[y0//24:max(y0//24+1, y1//24), x0//24:max(x0//24+1, x1//24)]
            rows.append((sub.sum()/total*100, sq.mean(), label,
                         (x1-x0)*(y1-y0)/(W*H)*100))
        print("\n  share of the page's total optical weight:")
        for share, sq, label, area in sorted(rows, reverse=True):
            print(f"    {share:6.2f}%  (area {area:5.2f}%)  {label}")
        print("\n  SQUINT SURVIVAL — what the player sees in the first fixation:")
        for share, sq, label, area in sorted(rows, key=lambda r: -r[1]):
            print(f"    {sq:.4f}  {label}")
        print("    ^ if the screen's own question is not at the top of this list,")
        print("      the composition is answering a different one.")

    if write_squint:
        for k, size in (("squint32", 32), ("squint64", 64)):
            small = img.resize((size, int(size*H/W)), Image.LANCZOS)
            out = os.path.join(SHOT_DIR, f"{name}_{k}.png")
            small.resize((W//2, H//2), Image.NEAREST).save(out)
        print(f"\n  squint renders -> {SHOT_DIR}")
    return m


def sweep():
    hdr = (f"{'screen':16s} {'bal-V':>6s} {'bal-H':>6s} {'equil':>6s} "
           f"{'dens%':>6s} {'edge%':>6s} {'colour':>7s}   TL/TR/BL/BR quadrant %")
    print(hdr); print("-"*len(hdr))
    vals = []
    for stem, label in SHELL_SHOTS:
        p = os.path.join(SHOT_DIR, stem + ".png")
        if not os.path.exists(p):
            print(f"{label:16s}  (no shot — run its _shot_*.tscn)"); continue
        m = page_measures(Image.open(p).convert("RGB"))
        vals.append((m["balance_v"], m["edge_density"], label))
        print(f"{label:16s} {m['balance_v']:6.3f} {m['balance_h']:6.3f} "
              f"{m['equilibrium']:6.3f} {m['density']:6.2f} {m['edge_density']:6.2f} "
              f"{m['colourfulness']:7.1f}   " +
              "".join(f"{q:6.1f}" for q in m["quadrants"]))
    if vals:
        bv = sorted(v[0] for v in vals); ed = sorted(v[1] for v in vals)
        print(f"\n  shell median balance-V {bv[len(bv)//2]:.3f} | "
              f"median edge density {ed[len(ed)//2]:.2f}%")
        print("  Judge a screen against the SHELL, not against 1.0 - an absolute")
        print("  target would fail screens whose asymmetry is the design.")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--sweep" in args:
        sweep()
    else:
        regions = None
        if "--regions" in args:
            i = args.index("--regions")
            with open(args[i + 1]) as fh:
                regions = json.load(fh)
            args = args[:i] + args[i + 2:]
        shot = next((a for a in args if a.endswith(".png")),
                    os.path.join(SHOT_DIR, "_runstart_setup_open.png"))
        report(shot, regions)
