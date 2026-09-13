#!/usr/bin/env python3
"""_line_hunt.py — every ANIMATED HAIRLINE in the game, and who draws it.

    python tools/_line_hunt.py            # suspects only
    python tools/_line_hunt.py --all      # every hit, including the exempt

WHY THIS EXISTS. `_circle_hunt.py` finds flat CIRCLES. This is the same defect
in its other shape, and the bigger population: a thin line standing in for
light. The root cause is a language fact, not a taste call —

    A LINE HAS UNIFORM OPACITY ACROSS ITS WIDTH.

`Line2D`, `draw_line` and `draw_polyline` all paint every pixel across the
stroke at the same alpha, so a stroke has two hard edges and a flat interior no
matter what colour it is. Light does not do that: it has a hot core and falls
off. That is why stacking four polylines never produced a glow, and why the
committed march road on the map read as four flat ribbons until it was given a
real texture. The fix is always the same — a TEXTURED stroke (R channel heat,
A channel opacity) via `Motion.beam_line`, or a filled shape with a gradient.

WHAT COUNTS AS A SUSPECT. A thin line is not automatically wrong. The war-chart
is an engraving and its roads, rivers and graticule are lines BY INTENT; a card
keyline is a printed rule; a table edge is an edge. The defect is a thin stroke
that MOVES, because movement is what claims it is energy rather than ink. So a
hit needs all three:

  · a draw_line / draw_polyline / draw_dashed_line / untextured Line2D
  · a THIN width (<= WIDE_ENOUGH), since a fat stroke reads as a shape
  · an ANIMATION DRIVER in its arguments or its enclosing function name

The third term is what keeps this honest. Without it the tool reports 478 hits,
almost all of them engraving, and a report nobody can act on is the same as no
report — that is exactly how the rarity halo survived every earlier sweep.

READ THE CONTINUATION LINES. A call split across lines puts its width and colour
on the NEXT line. `_circle_hunt` lost a real finding to precisely this (the
event stage's attention echo, a flat 3px wire ring, pulsing), so every call here
is reassembled across its parentheses before it is judged.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A stroke this wide or wider reads as a SHAPE, and a shape is allowed to be
# flat — a bar, a plate edge, a wax rule. The defect is specifically hairlines.
WIDE_ENOUGH = 5.0

# Tokens that say "this value changes every frame". A line whose width, colour,
# alpha or endpoints are driven by one of these is claiming to be alive.
DRIVERS = re.compile(
    r"\b(pulse|phase|sway|glow|flash|throb|shimmer|flicker|blink|breathe"
    r"|beat|wave|anim|spark|ember|shine|travel|sweep|progress|_t\b|alive"
    r"|elapsed|time|ticks|delta|lerp|sin\(|cos\()", re.I)

# Function names that declare the drawing IS an effect, whatever its arguments
# look like. A hairline inside `_draw_glow` is a wire pretending to be light.
FX_FUNC = re.compile(
    r"func\s+_?(draw_)?\w*(fx|flash|pulse|glow|spark|beam|burst|trail|ray"
    r"|bolt|wave|halo|aura|shine|ember|echo|comet|streak|blaze|flare)\w*",
    re.I)

# Files whose lines are ENGRAVING or FURNITURE, not effects. Being on this list
# is a claim a reader can check: the chart is a drawn map, the card is a printed
# document, the props are objects on a table.
EXEMPT = {
    # The war-chart is an engraving: roads, rivers, graticule, coastline,
    # terrain marks, the compass rose. Lines are the medium here.
    "MapTerrain.gd", "MapHexProto.gd",
    # Card furniture: keylines, rules, cartouche edges, plate-marks, plate
    # plates, tally strokes. A printed document is made of rules.
    "WritLeaf.gd", "InkCartouche.gd", "ParchmentPlate.gd", "WaxSeal.gd",
    "StatGem.gd", "StatCaret.gd", "TallyMarks.gd", "PolyBadge.gd",
    "WritDetailDiamond.gd", "EmptyPlateSigil.gd", "ArmoredEdge.gd",
    "WaxBar.gd", "TablePlate.gd", "CampaignStandard.gd", "ActVictoryStrip.gd",
    # Minigame props and stage dressing: dice pips, scale beams, slates, the
    # drumhead's lacing, keg hoops, chalk.
    "BalanceScale.gd", "CoinProp.gd", "KnuckleboneDie.gd", "PipDie.gd",
    "FortuneWheel.gd", "StrongboxDial.gd", "PowderKeg.gd", "DrumHead.gd",
    "DerbyBeetle.gd", "CastPatch.gd", "EventHelm.gd", "WarPip.gd",
    "TrinketIcon.gd", "PaySack.gd", "PayToken.gd", "CacheChest.gd",
    "BoneStraw.gd", "CandleStub.gd", "TallySlate.gd", "ChalkSlate.gd",
    "PaperSlip.gd", "RubricStroke.gd", "StageTable.gd", "FieldCell.gd",
    "TrayCloth.gd", "EffectsTray.gd", "SpentDispatch.gd", "StationMark.gd",
}

CALLS = ("draw_line(", "draw_polyline(", "draw_dashed_line(",
         "draw_multiline(")


def _reassemble(lines, i):
    """Return the full text of a call starting on line i, across its parens."""
    buf = lines[i]
    depth = buf.count("(") - buf.count(")")
    j = i
    while depth > 0 and j + 1 < len(lines) and j - i < 6:
        j += 1
        buf += " " + lines[j].strip()
        depth += lines[j].count("(") - lines[j].count(")")
    return buf


def _width_of(call: str) -> tuple[float, bool]:
    """The stroke width argument, and whether it is TAPERED.

    Defaulting to WIDE is deliberate: an unreadable width must not manufacture
    a finding. A tool that guesses toward the alarming answer stops being
    believed the first time someone checks one — and this one nearly did.

    SCANNING FOR A NUMBER CANNOT WORK, and two different false reads proved it:
    a `0.05` lerp weight inside an ENDPOINT expression, then a `0.35` from
    inside a `Color(...)` NESTED in a colour expression (`tint.lerp(Color(..),
    0.35 * t)`). The width is an argument POSITION, so split the argument list
    at top-level commas and read position 3.

    Returns (width, tapered). `tapered` is true when the width argument is an
    EXPRESSION rather than a literal — `(4.6 - 1.6 * g)` inside a loop is a
    hand-rolled falloff across stacked passes, which is the mitigation for this
    very defect, not an instance of it.
    """
    inner = call[call.find("(") + 1:]
    args, depth, buf = [], 0, ""
    for ch in inner:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        if ch == "," and depth == 0:
            args.append(buf.strip())
            buf = ""
            continue
        buf += ch
    if buf.strip():
        args.append(buf.strip())
    if len(args) < 4:
        return (99.0, False)
    w = args[3]
    if re.fullmatch(r"\d+\.?\d*", w):
        return (float(w), False)
    # An arithmetic expression means the width VARIES across the passes that
    # draw it — a taper. A bare identifier means we simply cannot tell, and an
    # unreadable width must never manufacture a finding.
    if re.search(r"[-+*/]", w):
        m = re.search(r"(\d+\.?\d*)", w)
        return (float(m.group(1)) if m else 99.0, True)
    return (99.0, False)


def scan(path: Path):
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    lines = src.splitlines()

    # Map each line to its enclosing func, so an effect-named function can
    # convict a call whose own arguments look inert.
    owner = [""] * (len(lines) + 1)
    cur = ""
    for i, ln in enumerate(lines):
        m = re.match(r"\s*(func\s+\w+)", ln)
        if m:
            cur = m.group(1)
        owner[i] = cur

    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("#"):
            continue
        if not any(c in ln for c in CALLS):
            continue
        call = _reassemble(lines, i)
        w, tapered = _width_of(call)
        if w >= WIDE_ENOUGH or tapered:
            continue
        driven = bool(DRIVERS.search(call))
        fx_named = bool(FX_FUNC.match(owner[i].replace("func ", "func ")))
        if not (driven or fx_named):
            continue
        why = "driven arg" if driven else "fx-named func"
        yield (i + 1, "ANIMATED HAIRLINE",
               f"[{why}, w={w:g}] {owner[i]} :: {s[:70]}")

    # An UNTEXTURED Line2D is the node-shaped spelling of the same thing. With a
    # texture it is a beam; without one it is a wire, however it is tweened.
    #
    # WIDTH DOES NOT EXCUSE A Line2D, and the first cut wrongly thought it did.
    # The `WIDE_ENOUGH` test above is right for `draw_line`, where a fat stroke
    # really is being used as a bar or a rule — but a Line2D at width 7 is not a
    # shape, it is a WIDER WIRE, and wider is worse: uniform opacity across 7px
    # is a flat ribbon with two hard edges, which is precisely what made the
    # map's committed march read as four stacked ribbons. Applying the draw_line
    # threshold here hid the skirmish spell arrow (width 7.0, gradient, bezier)
    # through every run of this tool while it reported the game clean.
    #
    # A GRADIENT IS NOT A TEXTURE EITHER. It ramps colour ALONG the run and does
    # nothing across the width, so it cannot produce a core — and on a beam
    # material it is not even read.
    for m in re.finditer(r"(\w+)\s*(?::=|=)\s*Line2D\.new\(\)", src):
        name = m.group(1)
        tail = src[m.end():m.end() + 1400]
        if re.search(rf"{re.escape(name)}\s*\.texture\s*=", tail):
            continue
        why = "never gets a .texture — uniform opacity across width"
        if re.search(rf"{re.escape(name)}\s*\.gradient\s*=", tail):
            why += " (its Gradient ramps ALONG the run, not across it)"
        yield (src[:m.start()].count("\n") + 1, "UNTEXTURED LINE2D",
               f"`{name}` {why}")


def main() -> int:
    show_all = "--all" in sys.argv
    suspects: list[tuple[str, int, str, str]] = []
    exempted = 0
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        hits = list(scan(p))
        if not hits:
            continue
        if p.name in EXEMPT and not show_all:
            exempted += len(hits)
            continue
        for (n, kind, snip) in hits:
            suspects.append((str(p.relative_to(ROOT)), n, kind, snip))

    print("=" * 78)
    print("LINE HUNT — animated hairlines across the WHOLE game")
    print("=" * 78)
    by_file: dict[str, list] = {}
    for f, n, kind, snip in suspects:
        by_file.setdefault(f, []).append((n, kind, snip))
    for f in sorted(by_file):
        print(f"\n{f}")
        for n, kind, snip in by_file[f]:
            print(f"   {n:6d}  {kind:18s} {snip}")
    print()
    print("-" * 78)
    print(f"{len(suspects)} suspect(s) in {len(by_file)} file(s); "
          f"{exempted} hit(s) exempted as ENGRAVING or FURNITURE (see EXEMPT)")
    print("-" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
