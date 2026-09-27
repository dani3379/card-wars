#!/usr/bin/env python3
"""Read the difficulty ENVELOPE across agents, not one agent's win rate.

METHOD, and the rule it exists to apply:

  "Monte-Carlo Tree Search for Simulation-based Strategy Analysis"
  (arXiv:1908.01423) reports of Cardonomicon that "regardless of agent strength,
  the player going second has a win rate substantially less than 50%", while
  noting "win rates do increase for the agent going second if they are more
  skilled". The usable rule:

      A property that holds across EVERY agent is a property of the GAME.
      A property that moves with agent strength is a property of the AGENT.

  "Predicting Game Engagement and Difficulty Using AI Players"
  (arXiv:2107.12061) adds that PEAK agent performance tracks human difficulty
  better than the mean -- so an encounter's difficulty is read from the BEST arm
  that fought it, not from the roster average.

So the two columns that matter per encounter are:
  * BEST  -- the most favourable arm. Per 2107.12061 this is the difficulty
             estimate. If even the best arm loses, the fight is hard for reasons
             no agent skill explains.
  * SPREAD across arms -- how much the outcome depends on WHO is playing. A wide
             spread means the encounter is testing the agent; a zero spread on a
             loss means it is testing the game.

`curve` vs `novice` is the cleanest skill contrast in the roster: Personas.gd
gives novice curve's OWN weight vector and differs only by blunder_rate, so any
gap between them is skill and not preference.

Usage: python tools/_analyse_envelope.py /tmp/envelope
"""
import os
import re
import sys
import statistics as st

ARMS = ["fixed", "curve", "novice", "aggro", "control", "trader"]


def parse_arm(path):
    """enc -> (wins, n); plus the arm's pooled TOTALS line if present."""
    per = {}
    totals = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"\[encwin\] ENC tag=\S*\s+(\S+)\s+act=(\d+)\s+(\S+)\s+"
                     r"n=(\d+) W=(\d+) L=(\d+) stuck=(\d+)", line)
        if m:
            enc, act, typ, n, w, l, stuck = m.groups()
            per[enc] = {"act": int(act), "n": int(n), "w": int(w),
                        "l": int(l), "stuck": int(stuck)}
        m2 = re.search(r"TOTALS W=(\d+) L=(\d+) stuck=(\d+)\s+overall wr=([\d.]+)%",
                       line)
        if m2:
            totals = {"w": int(m2.group(1)), "l": int(m2.group(2)),
                      "stuck": int(m2.group(3)), "wr": float(m2.group(4))}
    return per, totals


def main(d):
    arms = {}
    for a in ARMS:
        p = os.path.join(d, a + ".log")
        if os.path.exists(p):
            arms[a] = parse_arm(p)
    if not arms:
        print("no arm logs in %s" % d)
        return 1

    print("=" * 76)
    print("DIFFICULTY ENVELOPE -- %d of %d arms present" % (len(arms), len(ARMS)))
    print("=" * 76)
    print("%-10s %6s %6s %6s %7s" % ("arm", "W", "L", "stuck", "wr%"))
    for a, (per, tot) in arms.items():
        if tot:
            print("%-10s %6d %6d %6d %6.1f%%"
                  % (a, tot["w"], tot["l"], tot["stuck"], tot["wr"]))
        else:
            w = sum(v["w"] for v in per.values())
            l = sum(v["l"] for v in per.values())
            n = max(1, w + l)
            print("%-10s %6d %6d %6s %6.1f%%  (partial -- arm still running)"
                  % (a, w, l, "-", 100.0 * w / n))

    # THE ENVELOPE'S OWN WIDTH, with significance. If even the EXTREMES of the
    # roster cannot be separated, then no per-encounter claim from this run can be
    # either -- which is the single most useful thing this section can tell you,
    # because it converts "the numbers look different" into "the instrument needs
    # n=X". Reported before any per-encounter table for exactly that reason.
    fin = {a: t for a, (p, t) in arms.items() if t}
    if len(fin) >= 2:
        lo = min(fin, key=lambda a: fin[a]["wr"])
        hi = max(fin, key=lambda a: fin[a]["wr"])
        n_lo = fin[lo]["w"] + fin[lo]["l"]
        n_hi = fin[hi]["w"] + fin[hi]["l"]
        p_lo, p_hi = fin[lo]["wr"] / 100.0, fin[hi]["wr"] / 100.0
        sed = ((p_lo * (1 - p_lo) / max(n_lo, 1))
               + (p_hi * (1 - p_hi) / max(n_hi, 1))) ** 0.5
        gap = p_hi - p_lo
        z = gap / sed if sed > 0 else 0.0
        print()
        print("ENVELOPE WIDTH (the extremes of the roster):")
        print("  %s %.1f%% (n=%d)  ..  %s %.1f%% (n=%d)   spread %.1fpp"
              % (lo, fin[lo]["wr"], n_lo, hi, fin[hi]["wr"], n_hi, 100 * gap))
        print("  SE of difference %.1fpp, z = %.2f -> %s"
              % (100 * sed, z, "SIGNIFICANT" if abs(z) >= 1.96 else
                 "NOT significant even at the extremes"))
        if abs(z) < 1.96 and gap > 0:
            print("  n=%d per arm would be needed. Until then this roster reports"
                  % int(2 * (1.96 ** 2) * 0.25 / (gap ** 2)))
            print("  an ORDERING at best, never a rate difference.")

    # THE SKILL CONTRAST. Only meaningful if both arms finished.
    if "curve" in arms and "novice" in arms:
        c, nv = arms["curve"][1], arms["novice"][1]
        if c and nv:
            print()
            print("SKILL AXIS (same weight vector, novice adds blunder_rate):")
            n_c = c["w"] + c["l"]
            n_n = nv["w"] + nv["l"]
            pc, pn = c["wr"] / 100.0, nv["wr"] / 100.0
            sed = ((pc * (1 - pc) / max(n_c, 1))
                   + (pn * (1 - pn) / max(n_n, 1))) ** 0.5
            gap = pc - pn
            z = (gap / sed) if sed > 0 else 0.0
            print("  curve %.1f%% (n=%d)  vs  novice %.1f%% (n=%d)   gap %+.1fpp"
                  % (c["wr"], n_c, nv["wr"], n_n, 100 * gap))
            # A GAP WITHOUT ITS UNCERTAINTY IS NOT A RESULT. At n=30/arm this suite
            # cannot resolve ~7pp: SE of the difference is ~11pp, so z<2 and the
            # 95% interval spans zero. Reporting the bare gap is how a noise
            # reading becomes a balance decision.
            print("  SE of difference %.1fpp, z = %.2f, 95%% CI %+.1f..%+.1fpp -> %s"
                  % (100 * sed, z, 100 * (gap - 1.96 * sed),
                     100 * (gap + 1.96 * sed),
                     "SIGNIFICANT" if abs(z) >= 1.96 else "NOT significant"))
            if abs(z) < 1.96:
                need = int(2 * (1.96 ** 2) * 0.25 / (gap ** 2)) if gap else 0
                if need:
                    print("  to resolve a gap this size you would need ~n=%d per arm"
                          % need)
            print("  A gap here is SKILL. A near-zero gap means this content does")
            print("  not discriminate on execution, so its win rate is telling you")
            print("  about the CONTENT and not about how well it is played.")

    # Per-encounter, across arms.
    encs = sorted({e for per, _ in arms.values() for e in per})
    if len(arms) >= 2:
        print()
        print("PER-ENCOUNTER (BEST arm is the difficulty estimate, per 2107.12061)")
        print("%-26s %3s %6s %6s %7s  %s"
              % ("encounter", "act", "best", "worst", "spread", "arms lost to"))
        rows = []
        for e in encs:
            rates, lost = [], []
            for a, (per, _) in arms.items():
                v = per.get(e)
                if not v or v["n"] == 0:
                    continue
                r = 100.0 * v["w"] / v["n"]
                rates.append(r)
                if v["w"] == 0:
                    lost.append(a)
            if len(rates) < 2:
                continue
            rows.append((e, max(rates), min(rates), max(rates) - min(rates), lost,
                         next(per[e]["act"] for _, (per, _) in arms.items()
                              if e in per)))
        # Hardest first: lowest BEST, then widest spread.
        rows.sort(key=lambda r: (r[1], -r[3]))
        for e, best, worst, spread, lost, act in rows:
            note = ",".join(lost) if lost else "-"
            print("%-26s %3d %5.0f%% %5.0f%% %6.0fpp  %s"
                  % (e[:26], act, best, worst, spread, note))
        print()
        # ── THE MULTIPLE-COMPARISONS GUARD ───────────────────────────────────
        # This section is where the whole pass can mislead, and it did: read at
        # TWO arms it named six encounters as content problems, when six is BELOW
        # what chance alone produces.
        #
        # With samples=1 each arm is one Bernoulli trial, so if an encounter's
        # true win rate were 50%, P(all k arms lose) = 0.5^k. Over `len(rows)`
        # encounters the EXPECTED number of all-arm losses is len(rows) * 0.5^k:
        #     k=2 -> 0.250 each, ~7.5 of 30      (indistinguishable from noise)
        #     k=3 -> 0.125 each, ~3.8 of 30
        #     k=6 -> 0.016 each, ~0.5 of 30      (a real signal)
        # So the list is only worth printing once the FULL roster has run, and the
        # expectation is printed beside it so the reader can weigh it.
        zero = [r for r in rows if r[1] == 0.0]
        k = len(arms)
        expected = len(rows) * (0.5 ** k)
        print("all-arm losses: %d observed, ~%.1f expected by chance"
              % (len(zero), expected))
        print("  (k=%d arm(s); P(all lose | true p=0.5) = %.3f each, over %d"
              % (k, 0.5 ** k, len(rows)) + " encounters)")
        if k < len(ARMS):
            print("  ROSTER INCOMPLETE (%d of %d arms) -- NOT naming encounters."
                  % (k, len(ARMS)))
            print("  At this arm count chance alone yields ~%.1f of these, so the"
                  % expected)
            print("  list would be a multiple-comparisons artifact, not a finding.")
        elif not zero:
            print("  No encounter was lost by every arm.")
        elif len(zero) <= expected:
            print("  %d observed vs ~%.1f expected: NOT above chance. Treat as a"
                  % (len(zero), expected))
            print("  shortlist to re-measure at higher samples, not as a result.")
            for e, _, _, _, _, act in zero:
                print("    act %d  %s" % (act, e))
        else:
            print("  LOST BY EVERY ARM and ABOVE chance -- no agent skill in this")
            print("  roster wins these, so the cause is the CONTENT:")
            for e, _, _, _, _, act in zero:
                print("    act %d  %s" % (act, e))
    else:
        print()
        print("Only %d arm(s) present -- the envelope needs at least 2 to say"
              % len(arms))
        print("anything. A single arm's rate is the single-policy mistake the")
        print("roster exists to fix.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/tmp/envelope"))
