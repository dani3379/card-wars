#!/usr/bin/env python3
"""art_lint.py - CLASS C31: THE DRAWING THAT DOESN'T BELONG.

    python tools/art_lint.py                  # lint every asset family
    python tools/art_lint.py --only cyan      # one oracle
    python tools/art_lint.py --dir assets/creatures
    python tools/art_lint.py --top 40         # worst N per oracle

WHY A LINTER AND NOT AN IMAGE-QUALITY METRIC
--------------------------------------------
The obvious tool is a no-reference quality model (BRISQUE, NIQE). It is the
WRONG tool and would actively mislead here. Those measure DISTORTION - blur,
noise, compression, loss of natural-scene statistics - and the literature is
explicit that this is a different thing from aesthetics ("Image Aesthetic
Quality is conceptually different from Image Quality Assessment, since IAQ
emphasises subjective aesthetic perception while IQA mainly targets
distortion-oriented evaluation"). A crisp, flat, ugly yellow triangle has no
distortion at all. NIQE would rate this project's worst assets among its best.

So this does what the game-art tooling literature actually does - palette,
shape and border LINTING against the set's own norms (the Pixel Art Lint
model: "automated tools enforce policies for catching unwanted changes to
palettes, shapes, alignment, borders", and "a histogram check on texture
batches at delivery catches a disproportionate share of integration
problems").

That is the same argument as `tools/_probe_alignment.gd` (C30): judged ALONE,
"is this drawing bad" is taste and unanswerable; judged AGAINST THE SET it was
drawn for, it is measurable.

THE RUBRIC IS THE OWNER'S OWN VERDICTS
--------------------------------------
Every oracle below traces to a defect the owner already named, so this encodes
their taste rather than mine. Sources are in the project memory
(project_art_audit_mj_overhaul_20260722, reference_placeholder_smell,
feedback_ui_aesthetic, feedback_art_sourcing):

  A CYAN      "the ONE pervasive defect is saturated CYAN/TEAL in ~40 assets"
              breaking the warm sepia+ember set. Named as THE #1 defect.
  B OUTLIER   "photoreal stock images", "cartoon HUD icons" - both are the same
              measurement: an asset far from its own family's colour statistics.
  C DUPLICATE "plague_bell == mass_grave (pixel-identical dup)",
              "kindling_alt == kindling", "recruiters_horn == war_horn",
              "60 draftable cards borrow another card's art".
  D PIXELART  "grave_debt + a relic cluster (bloodstone_relic etc.) are
              PIXEL-ART" inside a painterly set.
  E FLAT      the painters that read as "drawn by a 5 year old": a shape with no
              gradient, no texture and three colours. Also catches the "emoji
              register" icons (hud_heart_painted) and "cartoon lemon coin".
  F PLACEHOLD "root-level assets/icons/*.png are the PRE-ART generic set" and
              "assets/icons/downloaded/ is a dumped-download folder". Source
              level: which of those does live code still point at?
  G ATLAS     "the Shop's Sell a Card chip was downloaded/cards1.png - a raw
              icon ATLAS, eight unrelated glyphs in a grid" used as one icon.

WHAT THIS CANNOT DO, AND WILL NOT PRETEND TO
--------------------------------------------
It cannot tell you a drawing is UGLY. Nothing can - that is the oracle problem,
and the honest answer is that "ugly" is not a property of one image. Every
finding here is either (a) a deviation from the set the asset belongs to, or
(b) a rule the owner stated in words. A beautiful painting that is the only
cool-toned one in a warm set WILL be flagged, correctly, as not belonging; a
mediocre one that matches the set will not be flagged at all. Read it as a
worklist, not a verdict.
"""

import argparse
import hashlib
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

# ── Tunables. Each is a threshold on a measurement, not a taste call. ────────
ALPHA_ON = 32          # a pixel counts as drawn above this alpha
CYAN_LO, CYAN_HI = 150.0, 210.0   # degrees; the band the owner called out
CYAN_SAT = 0.30        # below this it is a grey, not a colour
CYAN_VAL = 0.14        # below this it is shadow, not a colour
CYAN_HIT = 0.055       # >5.5% of drawn pixels in that band = an intrusion
MAD_K = 3.5            # robust z-score past which an asset leaves its family
DHASH_NEAR = 5         # Hamming distance for "near-duplicate"
# TONAL POVERTY — the discriminator, calibrated against known cases.
#
# The first version of oracle E asked "is it untextured", and that turned out
# NOT to separate the good drawings from the bad ones. Measured on this repo's
# own painters, CampaignStandard (crude, flagged by eye) scores 8.07 local
# texture and CandleStub (good, flagged by eye) scores 8.04 — indistinguishable,
# because a flat shape's HARD EDGES generate exactly as much local variance as a
# painting's soft shading does.
#
# What does separate them is how many distinct tones live inside the shape:
#
#     known-good   CandleStub 220 · CoinProp 130 · TrinketIcon 110 · BalanceScale 82
#     known-bad    CampaignStandard 50 · WarPip 36 · TrayCloth 32 · StatGem 11 · StatCaret 1
#
# A painted object carries a shading ramp; a crude one is a handful of fills.
# The gap is wide and unambiguous, so the threshold sits in it.
TONAL_POOR = 64        # distinct interior colours below this = flat-fill drawing
FLAT_STD = 6.0         # near-zero local variance: flat even at its edges
BLOCKY_HIT = 0.86      # fraction of identical neighbours = upscaled pixel art
MIN_PIXELS = 256       # ignore anything smaller than 16x16

# The pre-art generic icon set, named in reference_placeholder_smell.
GENERIC_ICONS = {"book", "campfire", "crown", "diamond", "fire", "heart",
                 "shield", "skull", "sword"}

# KNOWN AND DELIBERATE — visible debt, not absolution (the house convention,
# as in _probe_occlusion / _probe_silent_refusal). Oracle E is calibrated to
# catch flat-fill DRAWINGS; these are assets that are correctly flat, and the
# reason is recorded so a future reader can disagree with it.
#
# Tested against a hand-labelled set, E gets 7 of 7 known-bad and 5 of 5
# known-good. Its only misses are these: a base layer with nothing to shade,
# and a monochrome object whose ramp lives in one hue.
FLAT_WAIVERS = {
    "ChroniclePage": "the parchment SHEET the chronicle is written on - a base "
                     "layer, and it renders well on the GameOver page",
    "ParchmentPlate": "the card interior's paper base; the ageing on top of it "
                      "is what carries the texture",
    "InkCartouche": "the card's name banner - document furniture, flat by design",
    "WaxSeal": "monochrome by design. Its ramp is entirely within one hue, so an "
               "RGB tonal count under-reads it; on screen it is well modelled",
    "TouchGlow": "a glow OVERLAY, not an object - it has no interior to shade",
    "EventChoiceDevice": "draws nothing without its state; the harness cannot "
                         "give it any, so it is unjudged rather than flat",
    # ── THE SIZE-BLINDNESS PAIR (2026-09-03) ──
    # Both were this oracle's TOP hits and both are correct as designed. They
    # were caught by checking the call site before touching the art, and they
    # are why the caveat below the painter list exists.
    "StatCaret": "renders at 12x11px (Card2D.gd ~3654) as the colour-blind "
                 "redundancy marker for a buffed stat. A flat triangle with a "
                 "dark halo is the RIGHT drawing at that size; a shading ramp "
                 "would be mush. The harness cell is 190px, which is the lie",
    "StatGem": "renders at 38px and TINTED (red for Doom), with drop shadows, a "
               "chiselled rim, a faceted body and a specular cluster. The "
               "harness drew it white at 190px, where the whole ramp collapses "
               "into one quantisation bin",
    # ── SIZE-CORRECT (2026-09-03, verified at the call site) ──
    "BoneStraw": "renders 16x76 (Event.gd ~5367). A straw that wide IS a line; "
                 "there is no interior to shade",
    "LastStandCandle": "renders 44x68 (Card2D.gd ~7282) as a badge on a card "
                       "face, well under the size where a ramp would read",
    # ── NOT INSTANTIATED ANYWHERE (2026-09-03) ──
    # Verified by grepping each preloading file for `<Const>.new()` AND for the
    # inline `preload(...).new()` form — the second is how WaxBar and
    # SpentDispatch are used, so a const-name grep alone under-reports. These
    # draw for nobody, so their tonal range is not a defect; they are dead code,
    # tracked separately for deletion.
    "DerbyBeetle": "orphaned by the 2026-07-21 minigame replacement; 0 call sites",
    "EffectsTray": "orphaned by the 2026-07-21 minigame replacement; 0 call sites",
    "TrayCloth": "orphaned by the 2026-07-21 minigame replacement; 0 call sites",
    "TrinketIcon": "orphaned by the 2026-07-21 minigame replacement; 0 call sites",
    "DrumHead": "orphaned by the 2026-07-21 minigame replacement; 0 call sites",
    "PolyBadge": "preloaded by StatGem.gd, never instantiated - and it throws "
                 "'Invalid polygon data, triangulation failed' when it IS drawn",
    "StageTable": "no reference anywhere in scripts/ at all - not even a preload",
    # ── DOCUMENTED INTENT (2026-09-03) ──
    # Each of these states, in its own docstring, what it is meant to be, and
    # flatness is part of that statement. CastPatch's says it was already
    # reworked in a 2026-07-20 "looks drawn by a 5-year-old" pass — this list had
    # circled back to work already done.
    #
    # These are waived as NOT-A-LINT-FIX, which is not the same as "correct":
    # if the owner wants any of them richer that is a design decision they should
    # make, not one a tonal threshold should force.
    "WarPip": "flat BY DESIGN and for accessibility — its docstring: 'a bold flat "
              "silhouette AND a saturated tint, so it reads instantly and stays "
              "legible to a colourblind eye'. Shading it undoes that",
    "CastPatch": "already reworked in the 2026-07-20 'looks drawn by a 5-year-old' "
                 "pass; draws as a receding plane with a taper and a lip",
    "WaxBar": "exists BECAUSE the flat StyleBoxFlat it replaced 'read as flat UI'; "
              "it is poured wax in a channel",
    "ChalkSlate": "a schoolroom slate — a writing surface is flat",
    "EmptyPlateSigil": "'dim gilt ink' on parchment, deliberately faint",
    "EventHelm": "a legionary kettle-helm with two authored postures",
    "FieldCell": "one square of the sappers' sand table, with raked/stepped states",
    "StationMark": "war-chart furniture on the combat board, and the owner's "
                   "standing instruction is that play-area frames stay subtle "
                   "rather than being dressed up",
    "TablePlate": "the war-table chart surface; same standing instruction",
    "ClosedGround": "an exclusion hatch on a closed lane — signage, not an object",
    "PaySack": "an authored satchel with flap, strap and stitching",
    "SpentDispatch": "anchors PRESET_FULL_RECT and derives all geometry from its "
                     "parent's size, so the harness draws almost nothing (11.9% "
                     "fill). Its docstring: it replaced 'four flat Panel strips "
                     "that read as a gray wireframe'",
    "WritLeaf": "the card's deckled paper SHEET — a base layer, same case as "
                "ParchmentPlate; the ageing drawn on top carries the texture",
}

# A duplicate that is SUPPOSED to be a duplicate. Keyed by file stem.
DUPE_WAIVERS = {
    "kindling_alt": "Card2D.gd ~1063 loads this as the deliberate fallback when "
                    "a card resolves no art of its own. Being a copy of "
                    "kindling.png is the point, not a defect.",
}

FAMILIES = ["assets/creatures", "assets/spells", "assets/events",
            "assets/portraits", "assets/icons/relics", "assets/icons/potions",
            "assets/icons/keywords", "assets/backgrounds",
            "tools/screenshot/painters"]


def load(path):
    """RGBA array + the drawn-pixel mask, or None if unreadable/tiny."""
    try:
        im = Image.open(path).convert("RGBA")
    except Exception:
        return None
    if im.width * im.height < MIN_PIXELS:
        return None
    # Cap the working size: every measurement here is statistical, and a
    # 2048px background costs 60x a 256px one for the same answer.
    if max(im.size) > 512:
        im = im.copy()
        im.thumbnail((512, 512), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    mask = a[:, :, 3] > ALPHA_ON
    if mask.sum() < 64:
        return None
    return a, mask


def to_hsv(rgb):
    r, g, b = rgb[:, :, 0] / 255.0, rgb[:, :, 1] / 255.0, rgb[:, :, 2] / 255.0
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    idx = nz & (mx == r)
    h[idx] = (60 * ((g - b)[idx] / d[idx])) % 360
    idx = nz & (mx == g)
    h[idx] = 60 * ((b - r)[idx] / d[idx]) + 120
    idx = nz & (mx == b)
    h[idx] = 60 * ((r - g)[idx] / d[idx]) + 240
    s = np.zeros_like(mx)
    s[mx > 1e-6] = d[mx > 1e-6] / mx[mx > 1e-6]
    return h, s, mx


def luma(rgb):
    return 0.2126 * rgb[:, :, 0] + 0.7152 * rgb[:, :, 1] + 0.0722 * rgb[:, :, 2]


def dhash(rgb, mask):
    g = luma(rgb).copy()
    g[~mask] = 0.0
    im = Image.fromarray(g.astype(np.uint8)).resize((9, 8), Image.LANCZOS)
    a = np.asarray(im).astype(np.int32)
    bits = (a[:, 1:] > a[:, :-1]).flatten()
    v = 0
    for b in bits:
        v = (v << 1) | int(b)
    return v


def popcount(x):
    return bin(x).count("1")


# ── the measurements ────────────────────────────────────────────────────────

def measure(path):
    got = load(path)
    if got is None:
        return None
    rgb, mask = got
    h, s, v = to_hsv(rgb)
    n = float(mask.sum())

    # A: the cyan/teal band, as a share of drawn pixels.
    cy = mask & (h >= CYAN_LO) & (h <= CYAN_HI) & (s >= CYAN_SAT) & (v >= CYAN_VAL)
    cyan = float(cy.sum()) / n

    # B: circular-mean hue (weighted by saturation, so greys do not vote),
    # plus mean saturation and value - the "colour moments" of the literature.
    w = np.where(mask, s, 0.0)
    wsum = float(w.sum()) + 1e-6
    hr = np.deg2rad(h)
    hx = float((np.cos(hr) * w).sum()) / wsum
    hy = float((np.sin(hr) * w).sum()) / wsum
    sat = float(s[mask].mean())
    val = float(v[mask].mean())

    # E: texture. Mean local standard deviation of luminance - a painting has
    # gradient everywhere, a flat polygon has none.
    #
    # MEASURED ON THE ERODED INTERIOR, which is the whole trick. Every shape is
    # drawn antialiased, so its BOUNDARY always carries a gradient; averaging
    # that in made a flat gold crown and a flat white diamond measure as
    # "textured" and slip through, while the oracle only caught shapes with no
    # edges at all. Eroding by 3px asks the question that was meant: is there
    # anything going on INSIDE the shape?
    L = luma(rgb)
    inner = ndimage.binary_erosion(mask, np.ones((7, 7), bool))
    if inner.sum() < 48:
        inner = mask          # a thin shape has no interior; judge what there is
    Lm = np.nan_to_num(np.where(mask, L, 0.0))
    mean3 = ndimage.uniform_filter(Lm, 3)
    sq3 = ndimage.uniform_filter(Lm ** 2, 3)
    var3 = np.clip(sq3 - mean3 ** 2, 0, None)
    local_std = float(np.sqrt(var3)[inner].mean())

    q = (rgb[:, :, :3] // 8).astype(np.int32)
    packed = q[:, :, 0] * 4096 + q[:, :, 1] * 64 + q[:, :, 2]
    colors = int(np.unique(packed[inner]).size)
    fill = float(mask.sum()) / float(mask.size)

    # D: blockiness - the share of horizontally-adjacent drawn pixels that are
    # EXACTLY equal. Upscaled pixel art is almost all flat runs.
    same = (packed[:, 1:] == packed[:, :-1]) & mask[:, 1:] & mask[:, :-1]
    denom = float((mask[:, 1:] & mask[:, :-1]).sum()) + 1e-6
    blocky = float(same.sum()) / denom

    # G: how many separate opaque islands? A raw atlas used as one icon is
    # several unrelated glyphs with transparent gutters between them.
    lab, nlab = ndimage.label(mask)
    if nlab > 1:
        sizes = ndimage.sum(mask, lab, range(1, nlab + 1))
        big = int((np.array(sizes) > n * 0.04).sum())
    else:
        big = 1

    return {
        "path": str(path), "cyan": cyan, "hx": hx, "hy": hy, "sat": sat,
        "val": val, "local_std": local_std, "colors": colors,
        "blocky": blocky, "islands": big, "px": int(n), "fill": fill,
        "dhash": dhash(rgb, mask),
        "sha": hashlib.sha256(Path(path).read_bytes()).hexdigest(),
    }


def gather(dirs):
    out = []
    for d in dirs:
        p = ROOT / d
        if not p.exists():
            continue
        for f in sorted(p.rglob("*")):
            if f.suffix.lower() not in (".png", ".jpg", ".jpeg"):
                continue
            if ".import" in f.name:
                continue
            # `_unused/` is the retired-art drawer. Linting it buries the live
            # findings under dead ones — the first run reported four of its top
            # twelve cyan hits from there.
            if "_unused" in f.parts:
                continue
            out.append(f)
    return out


def mad_scores(vals):
    """Robust z-scores. Median/MAD, not mean/stddev - one photoreal outlier
    drags a mean far enough to hide itself."""
    a = np.asarray(vals, dtype=np.float64)
    med = np.median(a)
    mad = np.median(np.abs(a - med))
    if mad < 1e-9:
        return np.zeros_like(a)
    return 0.6745 * (a - med) / mad


def rel(p):
    try:
        return str(Path(p).relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(p)


# ── the oracles ─────────────────────────────────────────────────────────────

def oracle_cyan(rows, top):
    hits = [r for r in rows if r["cyan"] >= CYAN_HIT]
    hits.sort(key=lambda r: -r["cyan"])
    print(f"\n== A. CYAN/TEAL INTRUSION ({len(hits)} of {len(rows)}) ==")
    print("   the owner's #1 recorded defect: a cool band inside a warm "
          "sepia+ember set.")
    for r in hits[:top]:
        print(f"   {r['cyan']*100:5.1f}%  {rel(r['path'])}")
    return len(hits)


def oracle_outlier(rows, top):
    fams = defaultdict(list)
    for r in rows:
        fams[str(Path(r["path"]).parent)].append(r)
    total = 0
    print("\n== B. PALETTE OUTLIER FROM ITS OWN FAMILY ==")
    print("   'photoreal stock' and 'cartoon icon' are the same measurement: "
          "far from the family's own colour statistics.")
    for fam, rs in sorted(fams.items()):
        if len(rs) < 8:
            continue          # too few to define a norm; not judged
        axes = {"hue-x": [r["hx"] for r in rs], "hue-y": [r["hy"] for r in rs],
                "sat": [r["sat"] for r in rs], "val": [r["val"] for r in rs]}
        z = {k: mad_scores(v) for k, v in axes.items()}
        scored = []
        for i, r in enumerate(rs):
            worst = max(abs(z[k][i]) for k in axes)
            axis = max(axes, key=lambda k: abs(z[k][i]))
            if worst >= MAD_K:
                scored.append((worst, axis, r))
        scored.sort(key=lambda t: -t[0])
        if not scored:
            continue
        total += len(scored)
        print(f"   -- {rel(fam)} ({len(rs)} assets, {len(scored)} outliers)")
        for worst, axis, r in scored[:top]:
            print(f"      z={worst:5.1f} on {axis:6s}  {rel(r['path'])}")
    return total


def oracle_duplicate(rows, top):
    by_sha = defaultdict(list)
    for r in rows:
        by_sha[r["sha"]].append(r)
    exact = [v for v in by_sha.values() if len(v) > 1
             and not any(Path(r["path"]).stem in DUPE_WAIVERS for r in v)]
    print(f"\n== C. DUPLICATE / BORROWED ART ==")
    print("   exact file duplicates, then perceptual near-duplicates.")
    for grp in exact[:top]:
        print("   EXACT  " + "  ==  ".join(rel(r["path"]) for r in grp))
    seen = {r["sha"] for grp in exact for r in grp}
    uniq = [r for r in rows if r["sha"] not in seen]
    near = []
    for i in range(len(uniq)):
        for j in range(i + 1, len(uniq)):
            d = popcount(uniq[i]["dhash"] ^ uniq[j]["dhash"])
            if d <= DHASH_NEAR:
                near.append((d, uniq[i], uniq[j]))
    near.sort(key=lambda t: t[0])
    for d, a, b in near[:top]:
        print(f"   NEAR({d})  {rel(a['path'])}  ~  {rel(b['path'])}")
    return len(exact) + len(near)


def oracle_pixelart(rows, top):
    hits = [r for r in rows if r["blocky"] >= BLOCKY_HIT and r["colors"] < 400]
    hits.sort(key=lambda r: -r["blocky"])
    print(f"\n== D. PIXEL-ART / UPSCALED INTRUSION ({len(hits)}) ==")
    print("   flat runs of identical neighbours: the signature of a small "
          "grid blown up inside a painterly set.")
    for r in hits[:top]:
        print(f"   blocky={r['blocky']*100:5.1f}%  colors={r['colors']:4d}  "
              f"{rel(r['path'])}")
    return len(hits)


def oracle_flat(rows, top):
    hits = [r for r in rows if r["colors"] < TONAL_POOR
            and Path(r["path"]).stem not in FLAT_WAIVERS]
    hits.sort(key=lambda r: r["colors"])
    print(f"\n== E. TONAL POVERTY ({len(hits)}) ==")
    print("   too few tones inside the shape to be a painted object: the "
          "'drawn by a five year old' look, and the emoji-register icon.")
    print(f"   ({len(FLAT_WAIVERS)} deliberately-flat asset(s) waived - see "
          "FLAT_WAIVERS for the reason on each.)")
    if any("screenshot/painters" in r["path"] for r in hits):
        print("   CAVEAT for painters: they are rendered into a uniform 190px "
              "harness cell, which is NOT their shipping size. CHECK THE CALL "
              "SITE before believing one - a 12px marker cannot have 64 tones "
              "and should not try. Two of this oracle's top hits were exactly "
              "that mistake.")
    for r in hits[:top]:
        # A near-empty cell is the harness not giving a painter its state, not
        # a verdict on the painter — say so rather than letting it rank first.
        note = "  <- draws almost nothing; needs state" if r["fill"] < 0.06 else ""
        print(f"   tones={r['colors']:3d}  texture={r['local_std']:5.2f}  "
              f"{rel(r['path'])}{note}")
    return len(hits)


def oracle_atlas(rows, top):
    hits = [r for r in rows if r["islands"] >= 4]
    hits.sort(key=lambda r: -r["islands"])
    print(f"\n== G. ATLAS USED AS ONE ICON ({len(hits)}) ==")
    print("   several unrelated glyphs with transparent gutters, shipped as a "
          "single chip.")
    for r in hits[:top]:
        print(f"   islands={r['islands']:3d}  {rel(r['path'])}")
    return len(hits)


def oracle_placeholder(top):
    """Source-level, and the only oracle that reads code rather than pixels:
    which live call sites still point at the pre-art generic icons or at the
    dumped-download folder?"""
    print("\n== F. PLACEHOLDER ART STILL REFERENCED ==")
    print("   root-level assets/icons/*.png is the PRE-ART generic set; "
          "assets/icons/downloaded/ is a dump.")
    hits = 0
    for gd in sorted((ROOT / "scripts").rglob("*.gd")):
        try:
            text = gd.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            # A COMMENT NAMING THE OLD PATH IS THE FIX, NOT THE BUG. Both of
            # this oracle's first false positives were comments explaining what
            # an asset used to be ("This was assets/icons/diamond.png — a
            # generic..."), i.e. the exact sites already repaired.
            if line.lstrip().startswith("#"):
                continue
            if "assets/icons/downloaded/" in line:
                hits += 1
                print(f"   DUMPED   {rel(gd)}:{i}  {line.strip()[:78]}")
                continue
            for name in GENERIC_ICONS:
                if f"assets/icons/{name}.png" in line:
                    hits += 1
                    print(f"   GENERIC  {rel(gd)}:{i}  {line.strip()[:78]}")
                    break
    if hits == 0:
        print("   none")
    return hits


ORACLES = {
    "cyan": oracle_cyan, "outlier": oracle_outlier, "duplicate": oracle_duplicate,
    "pixelart": oracle_pixelart, "flat": oracle_flat, "atlas": oracle_atlas,
}


BASELINE = "tools/golden/art_baseline.json"


def _offenders(rows):
    """The finding SET, keyed by asset path per oracle. A set, not a count:
    counts let one asset be fixed while another regresses and still read clean."""
    by_sha = defaultdict(list)
    for r in rows:
        if "screenshot" in Path(r["path"]).parts:
            continue
        by_sha[r["sha"]].append(r)
    dupes = []
    for v in by_sha.values():
        if len(v) > 1 and not any(Path(x["path"]).stem in DUPE_WAIVERS for x in v):
            dupes.append(" == ".join(sorted(rel(x["path"]) for x in v)))
    return {
        "cyan": sorted(rel(r["path"]) for r in rows if r["cyan"] >= CYAN_HIT),
        "duplicate": sorted(dupes),
        "flat": sorted(rel(r["path"]) for r in rows
                       if r["colors"] < TONAL_POOR
                       and Path(r["path"]).stem not in FLAT_WAIVERS),
        "pixelart": sorted(rel(r["path"]) for r in rows
                           if r["blocky"] >= BLOCKY_HIT and r["colors"] < 400),
    }


def do_baseline(rows, bless):
    """THE DEBT MAY SHRINK, NEVER GROW (the C25 golden-master pattern).

    This linter reports 103 cyan findings, so it can never be a pass/fail gate —
    and a tool that is always red is a tool nobody runs. Recording today's
    offender SET turns it into one that is green now and goes red only when a NEW
    offender appears, which is what makes it safe to wire into a runner while the
    existing pile is worked through at whatever pace suits.

    Re-record deliberately with `--bless` after a batch is genuinely fixed."""
    cur = _offenders(rows)
    bp = ROOT / BASELINE
    if bless or not bp.exists():
        bp.parent.mkdir(parents=True, exist_ok=True)
        bp.write_text(json.dumps(cur, indent=1, sort_keys=True) + "\n",
                      encoding="utf-8")
        n = sum(len(v) for v in cur.values())
        print(f"[art-lint] BLESSED {BASELINE} — {n} known offender(s) recorded")
        return 0
    old = json.loads(bp.read_text(encoding="utf-8"))
    new_hits = 0
    fixed = 0
    for oracle in sorted(cur):
        was = set(old.get(oracle, []))
        now = set(cur[oracle])
        added = sorted(now - was)
        gone = sorted(was - now)
        fixed += len(gone)
        for a in added:
            new_hits += 1
            print(f"  NEW  {oracle:9s} {a}")
        for g in gone:
            print(f"  fixed {oracle:9s} {g}")
    if new_hits == 0:
        print(f"[art-lint] NO NEW ART DEBT ({fixed} fixed since the baseline)")
        return 0
    print(f"[art-lint] {new_hits} NEW OFFENDER(S) — fix them, or re-record with "
          "--bless if they are deliberate")
    return 1


def write_worklist(rows, path):
    """Emit the findings as a ranked markdown worklist.

    The point is that it is REGENERABLE: the art moves, this is re-run, and the
    list is current. A worklist pasted into a doc by hand goes stale the first
    time somebody fixes something, which is what happened to the July audit's
    asset list."""
    sev = sorted((r for r in rows if r["cyan"] >= CYAN_HIT),
                 key=lambda r: -r["cyan"])
    by_sha = defaultdict(list)
    for r in rows:
        # Painter renders are DIAGNOSTIC OUTPUT, not shipping art. Two of them
        # matching means two painters drew the same blank in the harness, which
        # is a fact about the harness and has no place on an art worklist.
        if "screenshot" in Path(r["path"]).parts:
            continue
        by_sha[r["sha"]].append(r)
    dupes = [v for v in by_sha.values() if len(v) > 1
             and not any(Path(x["path"]).stem in DUPE_WAIVERS for x in v)]
    flat = sorted((r for r in rows if r["colors"] < TONAL_POOR
                   and Path(r["path"]).stem not in FLAT_WAIVERS),
                  key=lambda r: r["colors"])

    L = []
    L.append("# Art worklist — generated, do not hand-edit")
    L.append("")
    L.append("Regenerate with `python tools/art_lint.py "
             "--markdown docs/ART_WORKLIST.md`.")
    L.append("")
    L.append("Ranked by the measurements in `tools/art_lint.py` (CLASS C31). "
             "Read its module docstring first: this is a WORKLIST, not a "
             "verdict, and it cannot tell you a drawing is ugly — only that it "
             "does not match the set it belongs to.")
    L.append("")

    L.append("## 1. Shared / duplicate art")
    L.append("")
    L.append("Two or more live entries rendering the same bitmap. The cheapest "
             "fix is often to RENAME the card to fit the art it already has, "
             "rather than commission more.")
    L.append("")
    if not dupes:
        L.append("_None._")
    for grp in dupes:
        L.append("- " + "  ==  ".join("`%s`" % rel(r["path"]) for r in grp))
    L.append("")

    L.append("## 2. Cyan / teal intrusion")
    L.append("")
    L.append(f"{len(sev)} of {len(rows)} measured images carry a saturated "
             "cyan/teal band, against a warm sepia+ember set. This is the "
             "defect the 2026-07-22 audit called the single pervasive one, and "
             "`docs/MIDJOURNEY_ART_OVERHAUL_20260722.md` already holds the "
             "style tails that exclude it (`--no cyan, teal, neon, saturated "
             "blue`). Percentages are the share of drawn pixels in the band.")
    L.append("")
    L.append("| % cyan | asset |")
    L.append("|---:|---|")
    for r in sev:
        L.append(f"| {r['cyan']*100:.0f}% | `{rel(r['path'])}` |")
    L.append("")

    L.append("## 3. Tonal poverty")
    L.append("")
    L.append("Too few distinct tones inside the shape to read as a painted "
             "object. **Check the call site before acting** — a 12px marker "
             "cannot have 64 tones and should not try; two of this oracle's "
             "top hits were exactly that mistake and are now waived.")
    L.append("")
    L.append("| tones | asset |")
    L.append("|---:|---|")
    for r in flat:
        L.append(f"| {r['colors']} | `{rel(r['path'])}` |")
    L.append("")

    Path(path).write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"[art-lint] wrote {path} "
          f"({len(dupes)} dupes, {len(sev)} cyan, {len(flat)} flat)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", action="append", default=None)
    ap.add_argument("--only", action="append", default=None)
    ap.add_argument("--top", type=int, default=25)
    ap.add_argument("--markdown", default=None,
                    help="write a ranked worklist to this path and exit")
    ap.add_argument("--baseline", action="store_true",
                    help="compare against the recorded offender set; fail on NEW ones")
    ap.add_argument("--bless", action="store_true",
                    help="re-record the baseline as current")
    args = ap.parse_args()

    dirs = args.dir if args.dir else FAMILIES
    files = gather(dirs)
    print(f"[art-lint] CLASS C31 - the drawing that doesn't belong")
    print(f"[art-lint] {len(files)} image(s) across {len(dirs)} family folder(s)")

    rows = []
    for f in files:
        m = measure(f)
        if m is not None:
            rows.append(m)
    print(f"[art-lint] {len(rows)} measured "
          f"({len(files) - len(rows)} skipped: unreadable or under 16x16)")

    if args.markdown:
        write_worklist(rows, args.markdown)
        return 0

    if args.baseline or args.bless:
        return do_baseline(rows, args.bless)

    which = args.only if args.only else list(ORACLES)
    total = 0
    for k in which:
        if k not in ORACLES:
            print(f"[art-lint] unknown oracle {k!r}; have {list(ORACLES)}")
            return 2
        total += ORACLES[k](rows, args.top)
    if not args.only or "placeholder" in (args.only or []):
        total += oracle_placeholder(args.top)

    print(f"\n[art-lint] {total} finding(s). This is a WORKLIST, not a verdict "
          "- see the module docstring on what it cannot do.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
