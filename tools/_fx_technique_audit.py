#!/usr/bin/env python3
"""_fx_technique_audit.py — which TECHNIQUE does each visual effect use?

    python tools/_fx_technique_audit.py

The ring rebuild (2026-09-09) started from an impression — "the circles look
ugly" — and the impression was right, but impressions do not scale to a 40-effect
surface and they mis-fire: the drag trail and the targeting arrow LOOK like flat
Line2D code at a glance and are in fact already gradient-and-taper builds.

So this classifies every effect by the primitives its body actually contains, and
scores the ones whose technique is below what the situation calls for. It is a
STATIC read of the source — it cannot see whether an effect looks good, only
which tools it reached for. That is the point: "reached for a flat primitive" is
a fact, and it is the fact that predicted every real defect in the ring pass.

Technique vocabulary (the realtime-VFX standard set, as applicable to 2D canvas):
  SHADER    a ShaderMaterial — erosion/dissolve, distortion, procedural falloff
  GRADIENT  a Gradient ramp along a line, or a width_curve taper
  PARTICLE  CPUParticles2D, directly or via Motion.burst
  LAYERED   a glow pass under a core pass (the cheap, effective bloom)
  TWEEN     transform/modulate animation only
  FLAT      a bare primitive at one uniform colour with hard edges  <-- the smell

FLAT alone is not a defect: a 2px rule under a heading is meant to be flat. It is
a defect when the thing is an ENERGY event — an impact, a blast, a burn, a cast.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# WHOLE-GAME SWEEP (widened 2026-09-10). This scanned FOUR files for months —
# Combat, Card2D, Motion, CombatNet — because that is where combat effects live.
# But the game is 17 screens plus ~50 painters, and "are there still ugly
# effects" is a whole-game question. A tool that cannot see Event, Shop, MapView
# or Reward cannot answer it, and a clean report from it meant nothing about
# them. Widening it immediately turned up a hand-rolled cos/sin Line2D ring in
# Combat itself that the narrow function-name filter had walked straight past.
SOURCES = [
    ("scripts/ui/Motion.gd", r"^static func ([a-z_]+)\("),
]

# Every other script is swept by NAME SHAPE: any function that spawns, plays,
# flashes or bursts something is an effect wherever it lives.
GENERIC = (r"^func (_?(?:spawn|play|flash|burst|pulse|trigger|vfx|fx)_[a-z_]+"
           r"|_[a-z_]*(?:_vfx|_fx|_burst|_flash|_pulse)\b[a-z_]*)\(")
SKIP_DIRS = {"tools", "card_redesign_v6"}

# Functions in Motion.gd that are layout/utility rather than effects.
NOT_AN_EFFECT = {
    "time", "boil_variant", "boil_offset", "turn_face", "particle_tex",
    "gilt_material", "flash_material", "burn_material", "write_on",
    "tick_number", "deal_in", "hover_lift", "fade_exit", "pocket_away",
    "flip_out", "flip_in", "press", "ken_burns", "punch", "claim_pop",
    "pulse_label", "stamp_in", "card_reveal", "reroll_sweep",
}

# An effect whose name says it is an ENERGY EVENT. These are the ones where a
# flat primitive is a real finding rather than a deliberate rule or chrome.
ENERGY = re.compile(
    r"burst|impact|strike|flash|blast|ring|wave|bolt|lightning|burn|death|"
    r"cast|spell|smear|flare|pulse|claim|seal|peel|drink|commit|trigger")


def liveness(body: str) -> str:
    """Does the effect have INTERNAL LIFE, or does it spawn and dim?

    The second lesson of the lightning rebuild, after "texture the line". A
    single path that fades is the documented failure mode: a motionless bright
    object reads as FROZEN however well it is drawn. The bolt only came alive
    once it became several strokes on offset cycles with per-frame jitter.

    So this asks a different question from `classify`. An effect can be a
    beautifully textured shader and still be dead on screen.

      LIVE    something drives it over time beyond a uniform fade — a per-frame
              method, staggered re-spawns, a loop, or particles (which carry
              their own motion).
      BEAT    it at least has an ENVELOPE: a hold before the decay, or stages.
              Not alive, but it lands rather than merely appearing.
      STATIC  it spawns and dims. The candidate class.
    """
    if re.search(r"tween_method|set_loops|_process\(|create_timer\([^)]*\)"
                 r"\.timeout\.connect", body):
        return "LIVE"
    if ("CPUParticles2D" in body or "Motion.burst" in body
            or re.search(r"\bburst\(", body) or "_spawn_family_particles" in body):
        return "LIVE"
    if "tween_interval" in body or body.count("tween_property") >= 3 \
            or ".chain()" in body:
        return "BEAT"
    if "tween_property" in body or "create_tween" in body:
        return "STATIC"
    return "-"


# Effects whose real work happens somewhere ELSE. `liveness` reads one function
# body, so an effect that hands the job to a helper scores STATIC however alive
# the helper is — `Card2D._flash_hit` delegates to `_flash_face_hit` and only
# keeps a modulate tween as its fallback, and `Wayside._spawn_result_seal` is
# one `Motion.ring` call, which is the shader ring with its own animator inside.
#
# This is the SAME lesson `classify` already carries three lines down ("a node
# handed a ShaderMaterial built elsewhere is using the technique") and it was
# never applied to the liveness half. Two of the six standing `z` findings were
# this and nothing else.
DELEGATES = re.compile(
    r"Motion\.(ring|ring_pulse|burst|shock_rings|forge_strike|writ_amend|"
    r"foil_sweep|impact_frame|burn_away|beam_line)\(|"
    r"_flash_face_hit\(|_spawn_vfx_ring\(|_play_trigger_fx\(")

# A CONFIRMATION IS NOT AN EFFECT, and this is the other four.
#
# The ENERGY vocabulary contains `pulse`, `flash`, `claim` and `seal` — which
# are exactly the words UI chrome uses. `NetLobby._flash_pick`,
# `Event._pulse_crown_mark` and `Combat._pulse_log_tab` are all the same object:
# a scale-or-modulate pop on a node the function was HANDED, saying "you picked
# this" or "there is something new here". They correctly have no internal life,
# because a selection tick that keeps moving is a distraction — `_pulse_log_tab`
# even documents its own Reduce Motion branch for that reason.
#
# The discriminator is SPAWN vs DECORATE: an effect brings something into
# existence, a confirmation animates something already on screen. So a body that
# never constructs a node and only touches scale/modulate is chrome, and a
# liveness finding against it is noise that buries the real ones.
_SPAWNS = re.compile(r"\.new\(\)|add_child\(|" + DELEGATES.pattern)
_DECORATES = re.compile(r'tween_property\(\s*[A-Za-z_][A-Za-z0-9_.]*\s*,\s*"'
                        r'(scale|modulate|rotation|position)')


def is_confirmation(body: str) -> bool:
    """Animates something that already exists, and creates nothing."""
    return bool(_DECORATES.search(body)) and not _SPAWNS.search(body)


def classify(body: str) -> set:
    t = set()
    # `.material =` counts: a node handed a ShaderMaterial built elsewhere is
    # using the technique just as much as one that news it up inline.
    if ("ShaderMaterial" in body or "_material(" in body or "shader" in body
            or re.search(r"\.material\s*=", body)):
        t.add("SHADER")
    if "Gradient.new()" in body or "width_curve" in body or "Curve.new()" in body:
        t.add("GRADIENT")
    if "CPUParticles2D" in body or "Motion.burst" in body or re.search(
            r"\bburst\(", body) or "_spawn_family_particles" in body:
        t.add("PARTICLE")
    # A glow pass under a core pass. Counting `Line2D.new()` finds the version
    # written out twice; `for layer in` finds the version written as a loop over
    # a width/colour/z stack, which is the same idiom and reads as ONE
    # constructor. Missing that scored the rebuilt lightning as bare-flat.
    if (("glow" in body and "core" in body)
            or body.count("Line2D.new()") >= 2
            or re.search(r"for layer in", body)):
        t.add("LAYERED")
    # Delegating to something already classified counts as using its technique.
    if re.search(r"Motion\.ring|_spawn_vfx_ring|_trigger_fx_ring|ring_pulse|"
                 r"shock_rings|_spawn_vfx_streak|impact_frame|foil_sweep", body):
        t.add("SHADER")
    flat_line = ("Line2D.new()" in body
                 and "Gradient.new()" not in body
                 and "width_curve" not in body)
    flat_rect = (("ColorRect.new()" in body or "draw_rect(" in body
                  or "draw_circle(" in body or "Polygon2D.new()" in body)
                 and "ShaderMaterial" not in body and "Gradient" not in body)
    if flat_line or flat_rect:
        t.add("FLAT")
    if not t and ("create_tween" in body or "tween_property" in body):
        t.add("TWEEN")
    return t


def bodies(path: Path, pattern: str):
    src = path.read_text(encoding="utf-8", errors="replace").splitlines()
    rx = re.compile(pattern)
    out = []
    i = 0
    while i < len(src):
        m = rx.match(src[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        j = i + 1
        while j < len(src) and not re.match(r"^(func |static func |#|##)", src[j]):
            j += 1
        out.append((name, "\n".join(src[i:j])))
        i = j
    return out


def main() -> int:
    targets = list(SOURCES)
    named = {rel for rel, _ in SOURCES}
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        if rel in named or any(d in p.parts for d in SKIP_DIRS):
            continue
        targets.append((rel, GENERIC))

    rows = []
    for rel, pattern in targets:
        p = ROOT / rel
        if not p.exists():
            print(f"MISSING {rel}")
            continue
        for name, body in bodies(p, pattern):
            if name in NOT_AN_EFFECT:
                continue
            tech = classify(body)
            live = liveness(body)
            # Why a STATIC reading is not a finding, when it is not one. Kept as
            # a REASON rather than a boolean so the report can say which of the
            # two it was — a silent exemption list is how a gate stops meaning
            # anything.
            excuse = ""
            if live == "STATIC":
                if DELEGATES.search(body):
                    excuse = "delegates"
                elif is_confirmation(body):
                    excuse = "confirmation"
            rows.append((rel.split("/")[-1], name, tech, live, excuse))

    rows.sort(key=lambda r: (("FLAT" in r[2]) is False,
                             not (r[3] == "STATIC" and not r[4]),
                             r[0], r[1]))
    skip = {(f, name): excuse for f, name, _t, _l, excuse in rows if excuse}
    excused = sorted(skip.items())

    print("=" * 78)
    print("FX TECHNIQUE AUDIT")
    print("=" * 78)
    findings = []
    dead = []
    for f, name, tech, live, _excuse in rows:
        mark = " "
        energy = bool(ENERGY.search(name))
        if "FLAT" in tech:
            # FLAT is only a finding when nothing better is layered with it.
            bare = not (tech & {"SHADER", "GRADIENT", "PARTICLE", "LAYERED"})
            if energy and bare:
                mark = "!"
                findings.append((f, name))
            elif energy:
                mark = "~"
        if live == "STATIC" and energy and not skip.get((f, name)):
            dead.append((f, name))
            if mark == " ":
                mark = "z"
        print(f" {mark} {f:16s} {name:34s} {live:7s} "
              f"{'+'.join(sorted(tech)) or '-'}")

    print()
    print("-" * 78)
    print(f"{len(rows)} effects scanned")
    print(f"  !  {len(findings):2d} ENERGY effect(s) built from a BARE FLAT primitive")
    print(f"  z  {len(dead):2d} ENERGY effect(s) that SPAWN AND DIM (no internal life)")
    print("-" * 78)
    for f, name in findings:
        print(f"  ! {f}::{name}")
    for f, name in dead:
        print(f"  z {f}::{name}")
    # PRINTED, NOT HIDDEN. These are STATIC energy effects that are not findings,
    # and the reason has to be visible or the exemption is indistinguishable from
    # the tool failing to look.
    if excused:
        print()
        print(f"  ~  {len(excused)} excused (see liveness notes):")
        for (f, name), why in excused:
            print(f"  ~ {f}::{name}  [{why}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
