#!/usr/bin/env python3
"""_circle_hunt.py — every FLAT CIRCLE in the whole game, and who draws it.

    python tools/_circle_hunt.py            # suspects only
    python tools/_circle_hunt.py --all      # every hit, including the exempt

WHY THIS EXISTS. The FX technique audit (_fx_technique_audit.py) only ever
scanned four files — Combat, Card2D, Motion, CombatNet — because that is where
combat effects live. But the game is 17 screens and ~50 painters, and the
complaint "there are still ugly circles" is a whole-GAME complaint. A tool that
cannot see the map, the event stage or the shop cannot answer it.

WHAT COUNTS AS A SUSPECT. A flat circle is not automatically wrong: a rivet, a
coin, a wax seal and a compass rose are all round objects and SHOULD be drawn as
filled shapes. The defect is the same one the ring engine had — a HAIRLINE
OUTLINE standing in for something that is supposed to read as light, focus or
energy. So this flags:

  · draw_arc(..., 0, TAU, ...) with a thin width      -> a wireframe circle
  · a Line2D built from a cos/sin point loop          -> the old ring idiom
  · draw_circle used as a GLOW (alpha < 0.5)          -> a flat disc as light

and it EXEMPTS, by file, the places where drawn circles are the diegesis rather
than an effect: the map's engraved chart, the minigame props, the card furniture.
Those are objects on a table, not effects — see the note beside EXEMPT.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Files whose circles are DRAWN OBJECTS, not effects. Being on this list is a
# claim that the round things there are props (coins, rivets, seals, pan bowls,
# compass roses), and it is a claim a reader can check.
EXEMPT = {
    # The war-chart is an engraving. Its arcs are terrain marks, coastline
    # rings, the compass and the fleet — a map, drawn as a map.
    "MapTerrain.gd", "MapHexProto.gd", "MapPulseOverlay.gd",
    # Minigame props: coins, dice, scale pans, drums, wheels, kegs.
    "BalanceScale.gd", "CoinProp.gd", "KnuckleboneDie.gd", "PipDie.gd",
    "FortuneWheel.gd", "StrongboxDial.gd", "PowderKeg.gd", "DrumHead.gd",
    "DerbyBeetle.gd", "CastPatch.gd", "EventHelm.gd", "WarPip.gd",
    "TrinketIcon.gd", "PaySack.gd", "PayToken.gd", "CacheChest.gd",
    "BoneStraw.gd", "CandleStub.gd", "TallySlate.gd", "ChalkSlate.gd",
    # Card furniture: wax seals, gems, plate-marks, rivets.
    "WaxSeal.gd", "StatGem.gd", "ArmoredEdge.gd", "WritDetailDiamond.gd",
    "PolyBadge.gd", "InkCartouche.gd", "ParchmentPlate.gd", "WritLeaf.gd",
    "StatCaret.gd", "TallyMarks.gd", "EmptyPlateSigil.gd", "WaxBar.gd",
    "CampaignStandard.gd", "ActVictoryStrip.gd", "TablePlate.gd",
    "SpentDispatch.gd", "PaperSlip.gd", "RubricStroke.gd", "StageTable.gd",
    "FieldCell.gd", "TrayCloth.gd", "EffectsTray.gd", "LastStandCandle.gd",
    # What remains here is props and one deliberate build: the ritual seal is
    # chalk drawn ON the stage floor (spokes, ink under a lighter rule), the
    # 58px half-round is an architectural rule, and the attention echo is now a
    # FOUR-PASS soft band whose first pass is legitimately thin. The echo was a
    # real hairline wire and was FIXED, not exempted — check that before adding
    # anything else to this file under cover of the exemption.
    "EventLayoutStage.gd",
}

FULL_ARC = re.compile(r"draw_arc\(([^;]*?)\)", re.S)
DRAW_CIRCLE = re.compile(r"draw_circle\(([^;]*?)\)", re.S)


def scan(path: Path):
    """Yield (line_no, kind, snippet) for each suspect circle in one file."""
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    lines = src.splitlines()

    for i, ln in enumerate(lines, 1):
        s = ln.strip()
        if s.startswith("#"):
            continue

        # A full circle drawn as an ARC. `0, TAU` is the tell; a partial arc is
        # a highlight or a bezel and is a legitimate drawing.
        #
        # READ THE CONTINUATION LINES. A draw_arc split across two lines put its
        # width on the NEXT line, so the width test silently fell back to "wide"
        # and the call was never flagged — that is how EventLayoutStage's
        # attention echo (a flat 3px wire ring, pulsing, an effect by any
        # reading) survived every sweep while the tool reported the game clean.
        # A FULL circle only: `0, TAU`. A PI->TAU arc is a half-round, which
        # is an architectural rule or a bezel, not a ring — flagging those
        # buried the real finding in noise.
        if ("draw_arc(" in ln and "TAU" in ln
                and re.search(r"[,(]\s*0(?:\.0)?\s*,\s*TAU", ln)):
            tail = " ".join(lines[i - 1:i + 2])
            nums = re.findall(r"(\d+\.?\d*)", tail.split("TAU", 1)[1])
            width = float(nums[1]) if len(nums) > 1 else 99.0
            if width <= 3.0:
                yield (i, "WIREFRAME ARC", s[:96])

        # A flat disc used as a GLOW rather than as an object: low alpha.
        if "draw_circle(" in ln:
            m = re.search(r"0\.(\d+)\s*\)", ln)
            if m and float("0." + m.group(1)) < 0.5:
                yield (i, "FLAT GLOW DISC", s[:96])

    # A THIRD SPELLING, found the hard way (2026-09-10): `draw_polyline` fed
    # from a cos/sin loop is a flat hairline circle too, and it matched neither
    # of the searches below — which is how the rarity halo kept circling cards in
    # the card-choice screens long after combat was clean.
    for m in re.finditer(r"draw_polyline\(", src):
        head = src[max(0, m.start() - 700):m.start()]
        if re.search(r"cos\(\s*a\s*\)", head) and "TAU" in head:
            yield (src[:m.start()].count("\n") + 1, "POLYLINE RING",
                   "draw_polyline fed from a cos/sin point loop")

    # The old ring idiom: a Line2D fed from a cos/sin loop.
    for m in re.finditer(r"Line2D\.new\(\)", src):
        tail = src[m.end():m.end() + 900]
        if re.search(r"cos\(\s*a\s*\)|Vector2\(cos\(", tail) and "TAU" in tail:
            yield (src[:m.start()].count("\n") + 1, "LINE2D RING",
                   "Line2D built from a cos/sin point loop")

    # THE RING IN DISGUISE. A StyleBoxFlat with a TRANSPARENT background, a fat
    # border and a huge corner radius is a hard-edged wireframe circle spelled a
    # different way — it matches neither of the searches above, which is exactly
    # how one survived in Wayside long after combat was clean. The transparent
    # background is the tell: the same shape FILLED is a legitimate object (a
    # keyword device stamp, a stat orb), so only the hollow ones are flagged.
    for m in re.finditer(r"StyleBoxFlat\.new\(\)", src):
        blk = src[m.end():m.end() + 700]
        radius = re.search(r"set_corner_radius_all\((\d+)\)", blk)
        border = re.search(r"set_border_width_all\((\d+)\)", blk)
        hollow = re.search(r"bg_color\s*=\s*Color\([^)]*,\s*0(?:\.0+)?\s*\)", blk)
        if radius and border and hollow and int(radius.group(1)) >= 40 \
                and int(border.group(1)) >= 2:
            yield (src[:m.start()].count("\n") + 1, "STYLEBOX RING",
                   "hollow Panel + fat border + corner_radius = a wire circle")


def main() -> int:
    show_all = "--all" in sys.argv
    roots = [ROOT / "scripts"]
    suspects: list[tuple[str, int, str, str]] = []
    exempted = 0
    for r in roots:
        for p in sorted(r.rglob("*.gd")):
            hits = list(scan(p))
            if not hits:
                continue
            if p.name in EXEMPT and not show_all:
                exempted += len(hits)
                continue
            for (n, kind, snip) in hits:
                suspects.append((str(p.relative_to(ROOT)), n, kind, snip))

    print("=" * 78)
    print("CIRCLE HUNT — flat circles across the WHOLE game")
    print("=" * 78)
    by_file: dict[str, list] = {}
    for f, n, kind, snip in suspects:
        by_file.setdefault(f, []).append((n, kind, snip))
    for f in sorted(by_file):
        print(f"\n{f}")
        for n, kind, snip in by_file[f]:
            print(f"   {n:6d}  {kind:15s} {snip}")
    print()
    print("-" * 78)
    print(f"{len(suspects)} suspect(s) in {len(by_file)} file(s); "
          f"{exempted} hit(s) exempted as drawn OBJECTS (see EXEMPT)")
    print("-" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
