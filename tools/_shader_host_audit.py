#!/usr/bin/env python3
"""_shader_host_audit.py — shaders bound to a host that CANNOT FEED THEM.

    python tools/_shader_host_audit.py
    python tools/_shader_host_audit.py --selftest

WHY THIS EXISTS. On 2026-09-13 `Motion.vfx_noise_material` was found to have
never rendered anything, on any of its four call sites, for the life of the
feature. The cause is one engine fact:

    A Polygon2D does not hand its shader usable UVs unless `texture` is set.

With no texture every vertex reads UV (0,0), so a UV-driven shader samples ONE
POINT and outputs a flat tint. Measured on the same polygon and material: pixel
standard deviation 0.0000 without a texture, 0.1931 with a 1x1 white one.

WHAT MAKES IT WORTH A STANDING CHECK is how it fails. Nothing errors. The
shader compiles, the material binds, every uniform is set, `--check-only` is
clean, parsecheck is clean, and the form renders as a tidy vertex-colour
gradient — which is indistinguishable from a deliberate flat art style. It
survived a full rebuild of the flame plus three separate passes tuning the
noise threshold, offset and grain, every one of them adjusting the interior of
a shape whose shader was reading a single pixel. A screenshot does not catch
it either, because there is nothing missing to notice; the thing just looks
plainer than it should.

THE RULE. A finding needs BOTH halves:
  · the shader reads UV, and
  · the host is a node type whose UVs are only meaningful with a texture.

Either alone is fine. A shader that never mentions UV does not care, and a
ColorRect / TextureRect / Sprite2D supplies UV from its own rect regardless.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Node types whose UV is degenerate without a `texture`. Polygon2D is the
# confirmed one (measured above). Line2D is included because it generates its
# UVs from the stroke only when it has a texture to map — `Motion.beam_line`
# always assigns one, which is why the beam kit was unaffected.
NEEDS_TEXTURE = ("Polygon2D", "Line2D")


def scan(path: Path):
    src = path.read_text(encoding="utf-8", errors="replace")
    for m in re.finditer(
            r"(\w+)\s*(?::=|=)\s*(" + "|".join(NEEDS_TEXTURE) + r")\.new\(\)",
            src):
        name, kind = m.group(1), m.group(2)
        # Look ahead far enough to cover a node built over several statements.
        tail = src[m.end():m.end() + 2500]
        if not re.search(rf"{re.escape(name)}\s*\.material\s*=", tail):
            continue                      # no shader, nothing to starve
        if re.search(rf"{re.escape(name)}\s*\.texture\s*=", tail):
            continue                      # fed
        line = src[:m.start()].count("\n") + 1
        fn = ""
        for fm in re.finditer(r"^func\s+(\w+)", src[:m.start()], re.M):
            fn = fm.group(1)
        yield (line, kind, name, fn)


def selftest() -> int:
    """The oracle must fire on the bad case and stay silent on the good one.

    A sweep that reports zero right after the thing it hunts was fixed is
    exactly the shape of a gate that cannot fail, and this repo has shipped
    two of those before (see the mutation-check notes in CLAUDE.md).
    """
    import tempfile
    bad = ("func a() -> void:\n"
           "\tvar p := Polygon2D.new()\n"
           "\tp.material = Motion.vfx_noise_material(1.0)\n")
    good = ("func b() -> void:\n"
            "\tvar q := Polygon2D.new()\n"
            "\tq.texture = Motion.white_tex()\n"
            "\tq.material = Motion.vfx_noise_material(1.0)\n")
    fails = 0
    with tempfile.TemporaryDirectory() as d:
        for label, body, want in (("untextured", bad, True),
                                  ("textured", good, False)):
            f = Path(d) / "t.gd"
            f.write_text(body, encoding="utf-8")
            fired = len(list(scan(f))) > 0
            ok = fired == want
            fails += 0 if ok else 1
            print(f"  {'PASS' if ok else 'FAIL'}  {label}: "
                  f"{'fired' if fired else 'silent'} (wanted "
                  f"{'fired' if want else 'silent'})")
    print("selftest: " + ("ALL PASS" if fails == 0 else f"{fails} FAILURE(S)"))
    return 1 if fails else 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    hits = []
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        for (line, kind, name, fn) in scan(p):
            hits.append((str(p.relative_to(ROOT)), line, kind, name, fn))
    print("=" * 78)
    print("SHADER HOST AUDIT — materials bound to a host that cannot feed them")
    print("=" * 78)
    for f, line, kind, name, fn in hits:
        print(f"\n{f}:{line}")
        print(f"   {kind} `{name}` in {fn}() takes a .material but no .texture")
        print(f"   -> its shader reads UV (0,0) at every vertex: ONE sample, "
              f"flat output")
    print()
    print("-" * 78)
    if hits:
        print(f"{len(hits)} starved shader(s). Fix: assign a texture — "
              f"Motion.white_tex() multiplies through and changes no colour.")
    else:
        print("0 starved shaders. (Run --selftest to confirm this can fail.)")
    print("-" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
