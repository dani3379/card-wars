#!/usr/bin/env python3
"""Aggregate several pilot runs into one reading.

WHY THIS IS NOT JUST A MEAN -- the finding that motivated the whole script.

  "Predicting Game Engagement and Difficulty Using AI Players" (arXiv:2107.12061)
  reports that an AI agent's *peak* performance correlates with human difficulty
  better than its *average*, and recommends inspecting "repeated best AI agent
  runs" when typical gameplay metrics prove insufficient.

That is not an abstract nicety here: CLAUDE.md already records two wrong balance
readings produced by exactly the failure the paper describes -- every act-3 boss
scoring 0% either side of a real change, and `bandit_camp` reading 13% before AND
after a face-HP cut that demonstrably worked. Both are an agent's *mean* sitting
at its own ceiling and being reported as a property of the fight. So every metric
here is printed as MEAN and BEST, and the spread between them is itself a signal:
when best >> mean the mean is measuring the agent, not the game.

Second source, for what to collect at all: Slay the Spire's developers (Mega Crit,
Game Developer interview) name PICK RATE as their single most important metric --
"cards chosen infrequently become basically not a card in our game" -- alongside
win-rate correlation and per-enemy average damage. Pick rate is the one this
harness cannot yet report; see the note at the end of the output.

Usage: python tools/_aggregate_play.py /tmp/play/pilot_*.log
"""
import re
import sys
import statistics as st

# label -> (regex capturing one number, human unit)
SCALARS = {
    "clicks":           r"clicks\s+(\d+)",
    "drags":            r"drags\s+(\d+)",
    "cards played":     r"cards played\s+(\d+)",
    "fights entered":   r"fights entered\s+(\d+)",
    "rounds reached":   r"rounds reached\s+(\d+)",
    "map stops taken":  r"map stops taken\s+(\d+)",
    "runs ended":       r"runs ended\s+(\d+)",
    "silent refusals":  r"silent refusals\s+(\d+)",
    "overlays opened":  r"overlays opened\s+(\d+)",
    "offers taken":     r"offers taken\s+(\d+)",
    "potions drunk":    r"potions drunk\s+(\d+)",
    "command unspent":  r"command unspent\s+([\d.]+)",
    "hero dmg taken":   r"hero damage taken\s+(\d+)",
    # DASH-AGNOSTIC. The pilot writes a real em-dash here; ASCII-ising this file
    # for a cp1252 console silently broke both patterns, and a regex that stops
    # matching reports a missing metric rather than an error -- the same
    # fail-quiet shape as a mistyped dictionary key.
    "fights won %":     r"WHY IT DIES.{1,4} \d+ fights, \d+ won \((\d+)%\)",
    "rounds per fight": r"WHY IT DIES.{1,4} \d+ fights, \d+ won \(\d+%\), ([\d.]+) rounds",
    "findings":         r"FINDINGS: (\d+) distinct",
}


def parse(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    out = {"_path": path}
    for label, pat in SCALARS.items():
        m = re.search(pat, txt)
        if m:
            out[label] = float(m.group(1))
    m = re.search(r"acts seen\s+\[([^\]]*)\]", txt)
    out["acts seen (max)"] = max(
        [float(x) for x in re.findall(r"\d+", m.group(1))] or [0]) if m else 0
    m = re.search(r"deck at death\s+\[([^\]]*)\]", txt)
    out["deck at death (max)"] = max(
        [float(x) for x in re.findall(r"\d+", m.group(1))] or [0]) if m else 0
    # Per-encounter losses: "act N  NAME  P% removed (a/b HP left), R rounds"
    out["_losses"] = re.findall(
        r"act (\d+)\s+(.+?)\s+(\d+)% removed \((\d+)/(\d+) HP left\), (\d+) rounds",
        txt)
    out["_screens"] = re.search(r"screens visited\s+(.+)", txt)
    # THE SNOWBALL, in the pilot's own words: "the board drifts -8.4 per round
    # against the player REGARDLESS of the card played". A per-round board delta
    # that is independent of the play is a structural property of the fight, not a
    # card-quality signal -- which is exactly the kind of agent-independent figure
    # arXiv:1908.01423 says is safe to read as a property of the GAME.
    m = re.search(r"board drifts (-?[\d.]+) per round", txt)
    if m:
        out["board drift/round"] = float(m.group(1))
    # "NAME  11 HP over 1 fight(s), won 1, 14.0 rounds" -- Mega Crit track
    # per-enemy average damage taken for the same purpose.
    out["_worst"] = re.findall(
        r"^\s+(.+?)\s+(\d+) HP over (\d+) fight\(s\), won (\d+), ([\d.]+) rounds",
        txt, re.M)
    return out


def main(paths):
    runs = [parse(p) for p in paths]
    runs = [r for r in runs if len(r) > 4]
    if not runs:
        print("no parseable pilot logs")
        return 1
    print("=" * 78)
    print("AGGREGATE OVER %d PILOT RUN(S)" % len(runs))
    print("MEAN and BEST are both printed deliberately -- arXiv:2107.12061 finds")
    print("peak agent performance predicts human difficulty better than the mean,")
    print("and a wide mean/best gap means the mean is measuring the AGENT.")
    print("=" * 78)
    print("%-20s %8s %8s %8s %8s" % ("metric", "mean", "best", "worst", "spread"))
    keys = [k for k in list(SCALARS) + ["acts seen (max)", "deck at death (max)",
                                        "board drift/round"]
            if any(k in r for r in runs)]
    for k in keys:
        vals = [r[k] for r in runs if k in r]
        if not vals:
            continue
        # "best" is high-is-good for every metric here EXCEPT these:
        low_is_good = k in ("silent refusals", "findings", "command unspent",
                            "hero dmg taken", "board drift/round")
        best = min(vals) if low_is_good else max(vals)
        worst = max(vals) if low_is_good else min(vals)
        print("%-20s %8.2f %8.2f %8.2f %8.2f"
              % (k, st.mean(vals), best, worst, max(vals) - min(vals)))

    print()
    print("--- WHERE IT DIED (per-encounter, pooled) ---")
    pooled = {}
    for r in runs:
        for act, name, pct, hp, mhp, rounds in r["_losses"]:
            key = (act, name.strip())
            pooled.setdefault(key, []).append(
                (float(pct), float(hp), float(mhp), float(rounds)))
    if not pooled:
        print("  (no recorded losses -- the pilot won or ran out of clock)")
    for (act, name), rows in sorted(pooled.items()):
        pct = st.mean(r[0] for r in rows)
        rounds = st.mean(r[3] for r in rows)
        print("  act %s  %-28s lost %dx  foe %.0f%% removed, %.1f rounds"
              % (act, name, len(rows), pct, rounds))

    print()
    print("--- COSTLIEST ENCOUNTERS (hero HP taken, pooled) ---")
    print("    Mega Crit track average damage taken per enemy for this purpose.")
    worst = {}
    for r in runs:
        for name, hp, fights, won, rounds in r.get("_worst", []):
            e = worst.setdefault(name.strip(), [0.0, 0, 0, 0.0])
            e[0] += float(hp)          # a TOTAL across that run's fights
            e[1] += int(fights)
            e[2] += int(won)
            # `rounds` in the log is ALREADY per-fight (the pilot divides by n at
            # the print site), so re-dividing it here understated every entry.
            # Re-weight by fights to pool runs correctly.
            e[3] += float(rounds) * int(fights)
    if not worst:
        print("    (none recorded)")
    for name, (hp, fights, won, rounds_w) in sorted(
            worst.items(), key=lambda kv: -kv[1][0] / max(1, kv[1][1])):
        print("    %-28s %5.1f HP/fight over %d fight(s), won %d, %.1f rounds/fight"
              % (name, hp / max(1, fights), fights, won,
                 rounds_w / max(1, fights)))

    print()
    print("--- WHAT THIS HARNESS STILL CANNOT SAY, AND WHY IT IS NOT A LOG LINE ---")
    print("  PICK RATE is Mega Crit's most important balance metric ('cards chosen")
    print("  infrequently become basically not a card in our game'). It is NOT")
    print("  measurable here, and adding a log line would make that worse rather")
    print("  than better: `_drive_recruit` chooses with")
    print("      ready[_rng.randi_range(0, ready.size() - 1)]")
    print("  i.e. UNIFORMLY AT RANDOM. A pick rate harvested from that agent is")
    print("  1/N for every card BY CONSTRUCTION -- arithmetic wearing the costume")
    print("  of a preference. The real gap is that no agent in this harness DRAFTS")
    print("  by value: BoardEval and the personas score plays on a board, and")
    print("  nothing scores an OFFER. Pick rate becomes meaningful the day a")
    print("  drafting policy exists, and not one line sooner.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
