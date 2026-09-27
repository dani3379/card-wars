#!/usr/bin/env python3
"""analyse_journal.py — read the pilot's decision journal and say what it means.

    python tools/analyse_journal.py                     # all journals on disk
    python tools/analyse_journal.py --dir <path>        # a specific directory
    python tools/analyse_journal.py --since 20260919    # only today's files
    python tools/analyse_journal.py --json out.json     # machine-readable too

WHY THIS IS NOT JUST A SUMMARY OF THE LOG
-----------------------------------------
`_probe_pilot.gd` already prints what happened: fights won, rounds, damage. That
answers "is the bot winning". It cannot answer the question the owner actually
asked, which is whether the GAME is any good — and the difference is that a
question about quality is a question about the decisions a player was offered,
not about the outcomes they reached.

So the journal records every option that was on the table, and this reads the
options rather than the outcomes. Four measures, each chosen because it fails
loudly when the game is boring in a specific, nameable way:

  1. FORCED TURNS.  A turn with one legal play is not a decision, it is a
     formality with a button on it. The rate of those is the cheapest possible
     measure of whether the Command ramp and the cost curve leave any room to
     think early. Directly comparable across balance changes.

  2. DECIDEDNESS / WASTED ROUNDS.  From each fight's per-round board trace: the
     last round the board still DISAGREED with the eventual result, against how
     long the fight ran. A fight settled at round 2 and ending at round 12 spent
     83% of itself performing an outcome already reached. This is the exact
     complaint the difficulty doc opens with, expressed per encounter so the
     outliers name themselves. It is deliberately SYMMETRIC — see
     `decidedness()` for why the obvious one-sided version misreports every
     fight won from behind.

  3. LEAD CHANGES.  How many times the board advantage changes hands. Zero lead
     changes is a procession regardless of who wins. This is the standard
     excitement measure from sports analytics, and it is the right instrument
     here because it asks about the CONTEST rather than the result. Measured
     against the per-round POPULATION MEAN rather than against parity — see
     `board_baseline`, because in this game the player is behind on raw material
     in almost every fight and a parity test therefore finds no contests at all.

  4. CHOICE REGRET / SEPARATION.  The gap between the best-scored play and the
     second-best. When that gap is large the "decision" was obvious; when it is
     near zero the cards were interchangeable. Both extremes are bad design and
     they are bad in opposite directions, so the distribution matters more than
     the mean.

A NOTE ON WHAT THE NUMBERS ARE ABOUT
------------------------------------
Everything here is measured from ONE agent. A property that holds across agent
strengths is a property of the game; a property that moves when the bot improves
was about the bot. This script reports the agent's own competence markers
(unspent Command, top-play rate, deck growth) beside every quality measure, so a
reader can tell which kind of claim they are looking at. Nothing below is a
verdict on the game on its own.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from collections import Counter, defaultdict

DEFAULT_DIR = os.path.join(
    os.environ.get("APPDATA", ""),
    "Godot", "app_userdata", "Burning Meadow", "pilot_journal")


# ── reading ──────────────────────────────────────────────────────────────

def load(paths):
    """Every record, in file order. A truncated last line is EXPECTED and
    skipped: the writer flushes per record precisely so a killed run still
    leaves its evidence, and the price of that is a possible partial tail."""
    recs, bad = [], 0
    for p in paths:
        with open(p, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    bad += 1
                    continue
                r["_file"] = os.path.basename(p)
                _apply_verdict_precedence(r)
                recs.append(r)
    return recs, bad


def _apply_verdict_precedence(r):
    """THE GAME DECIDES A TIE, NOT THE INSTRUMENT.

    Both rows strike simultaneously, so both faces can reach 0 in one clash.
    `Combat._check_game_over` resolves that one way —

        if player_hp <= 0: ...defeat...
        elif enemy_hp <= 0: ...victory...

    — so a mutual kill is a DEFEAT. The pilot records `won` and `died` as two
    INDEPENDENT observations on purpose (the foe's face fell / ours did), which
    is what lets the precedence be applied here, retroactively and uniformly
    across every archived arm, instead of being baked into the recorder and
    silently splitting a before/after comparison in half.

    Measured on the 12-seed corpus: 2 of 255 fights, worth 0.8pp of win rate,
    and it pointed the wrong way — an instrument that flatters is the half of
    an oracle fault that survives review.
    """
    if r.get("kind") == "fight_end" and r.get("won") and r.get("died"):
        r["won"] = False
        r["mutual_kill"] = True
    return r


def find_journals(d, since):
    if not os.path.isdir(d):
        return []
    out = []
    for name in sorted(os.listdir(d)):
        if not name.endswith(".jsonl"):
            continue
        if since and since not in name:
            # names are seed<N>_<unixtime>.jsonl; --since matches loosely so a
            # caller can pass a seed or a timestamp prefix without two flags.
            continue
        out.append(os.path.join(d, name))
    return out


def by(recs, kind):
    return [r for r in recs if r.get("kind") == kind]


def tag_arms(recs):
    """Stamp every record with the POLICY its file was run under.

    The header carries it; the records do not, and an A/B whose two arms are
    indistinguishable once loaded is not an A/B. Done by file rather than by
    seed because the same seed is deliberately run in both arms — that pairing
    is the whole design, and keying on the seed would merge the pair it exists
    to compare."""
    arm_of = {}
    for r in recs:
        if r.get("kind") == "header":
            arm_of[r["_file"]] = r.get("policy", "value")
    for r in recs:
        r["_arm"] = arm_of.get(r["_file"], "value")
    return sorted(set(arm_of.values()))


def report_ab(recs, arms):
    if len(arms) < 2:
        return
    section("0. A/B — the draft policy, against the coin-flip it replaced")
    print("  Same seeds, same budget, same combat scorer. The ONLY difference is")
    print("  how the muster, the wagon, the pickers and the chart are answered.")
    print(f"    {'':<22}" + "".join(f"{a:>14}" for a in arms))
    rows = []
    for a in arms:
        sub = [r for r in recs if r.get("_arm") == a]
        f = [x for x in by(sub, "fight_end") if x.get("rounds", 0) > 0]
        runs = by(sub, "run_end")
        commits = by(sub, "commit")
        decks = [len(r.get("final_deck") or []) for r in runs]
        rows.append({
            "fights": len(f),
            "won%": pct(sum(1 for x in f if x.get("won")), len(f)),
            "rounds": statistics.mean([x.get("rounds", 0) for x in f]) if f else 0,
            "runs": len(runs),
            "act reached": max([r.get("act_reached", 0) for r in runs] or [0]),
            "deck at end": statistics.mean(decks) if decks else 0,
            "recruits": len(by(sub, "recruit")),
            "purchases": len([s for s in by(sub, "shop")
                              if s.get("taken", "<none>") != "<none>"]),
            "unspent/turn": (statistics.mean([c.get("unspent", 0) for c in commits])
                             if commits else 0),
        })
    for k in rows[0]:
        line = f"    {k:<22}"
        for r in rows:
            v = r[k]
            line += f"{v:>14.2f}" if isinstance(v, float) else f"{v:>14}"
        print(line)
    print()
    print("  READ THE `fights` ROW FIRST. The budget is wall-clock, so an arm")
    print("  that played more fights had a faster run, not necessarily a better")
    print("  one — and a win rate over 12 fights has a standard error near 14")
    print("  points. Treat a gap under ~15 points as unresolved.")


def pct(n, d):
    return 100.0 * n / d if d else 0.0


def fmt_pct(n, d):
    return f"{pct(n, d):5.1f}%" if d else "    --"


# ── the measures ─────────────────────────────────────────────────────────

def board_baseline(fights):
    """Mean board gap per round across every traced fight.

    THE PLAYER IS BEHIND ON MATERIAL IN ALMOST EVERY FIGHT, WINNING OR LOSING,
    and that is a structural fact rather than a result. The hold's only cost for
    a body is `max_place`, a body count; the player pays Command for every one.
    Measured over 65 fights: the gap in fights the pilot WON runs -5.3, -8.6,
    -4.8, -3.2 across rounds 1-4, and in fights it LOST, -14.5, -24.6, -28.1,
    -31.3. Winning and losing differ in the SIZE of the deficit, not its sign.

    So any measure keyed on "who is ahead" is asking a question the player almost
    never gets a yes to, and will report every won fight as a miracle and every
    lost one as doomed from round 1. The fix is the one this project already
    applies to the pilot's own card-swing ledger — subtract the population mean
    and compare cards (here, positions) to each other rather than to zero.
    """
    per_round = defaultdict(list)
    for f in fights:
        for e in f.get("trace") or []:
            per_round[e.get("r", 0)].append(e.get("mine", 0) - e.get("theirs", 0))
    return {r: statistics.mean(v) for r, v in per_round.items() if v}


def rel_gap(entry, baseline):
    r = entry.get("r", 0)
    return (entry.get("mine", 0) - entry.get("theirs", 0)) - baseline.get(r, 0.0)


def decidedness(fight, baseline=None):
    """(last round still in doubt, rounds, fraction played after that).

    THE MEASURE HAS TO BE SYMMETRIC OR IT LIES ABOUT HALF THE FIGHTS. The first
    version asked "the last round the player was AHEAD", which is the right
    question for a loss and nonsense for a win — a fight won from in front
    scored `last_ahead == rounds` (0% wasted) while a fight won from behind on
    board, by racing the face, scored `last_ahead == 0` and was reported as
    **100% already decided**. Three won fights came out at 100% that way.

    So: the last round the board DISAGREED with the eventual result. For a loss
    that is the last round the player led; for a win, the last round they
    trailed. After it, the fight only confirmed what it had already become.

    Ties count as agreeing with a win and disagreeing with a loss, which is the
    conservative reading in both directions — round 1 is the muster, where both
    lines are forming and neither has swung.
    """
    trace = fight.get("trace") or []
    if not trace:
        return None
    base = baseline or {}
    won = bool(fight.get("won"))
    last_doubt = 0
    for e in trace:
        gap = rel_gap(e, base)
        in_doubt = (gap < 0) if won else (gap >= 0)
        if in_doubt:
            last_doubt = e.get("r", 0)
    rounds = max(fight.get("rounds", 0), 1)
    return last_doubt, rounds, max(0.0, 1.0 - last_doubt / rounds)


def lead_changes(fight, baseline=None):
    """How many times the board advantage flips across the fight.

    Measured against the per-round POPULATION MEAN, not against parity — see
    `board_baseline`. Against parity this counted almost nothing, because the
    player is behind on raw material in nearly every fight and the sign
    therefore never changes: it reported 42% of fights as processions when what
    it had found was a constant offset.

    Round 1 is the muster and is skipped: both boards are mid-deployment, so its
    sign is an artifact of deal order rather than a contest."""
    base = baseline or {}
    trace = [e for e in (fight.get("trace") or []) if e.get("r", 0) > 1]
    if len(trace) < 2:
        return 0
    signs = []
    for e in trace:
        d = rel_gap(e, base)
        signs.append(0 if abs(d) < 1e-9 else (1 if d > 0 else -1))
    signs = [s for s in signs if s != 0]
    return sum(1 for a, b in zip(signs, signs[1:]) if a != b)


def separation(play):
    """best score minus second-best, for one decision. None when there was only
    one option — that is a FORCED turn and belongs in the other counter."""
    opts = play.get("options") or []
    if len(opts) < 2:
        return None
    return opts[0]["score"] - opts[1]["score"]


# ── report sections ──────────────────────────────────────────────────────

def section(title):
    print()
    print(title)
    print("-" * len(title))


def report_coverage(recs, files, bad):
    heads = by(recs, "header")
    section("WHAT THIS IS BUILT FROM")
    print(f"  journals        {len(files)} file(s), {len(recs)} records"
          + (f", {bad} unparsable line(s)" if bad else ""))
    seeds = sorted({h.get("seed") for h in heads})
    print(f"  seeds           {seeds}")
    greedy = {h.get("greedy") for h in heads}
    print(f"  greedy          {greedy}  (False mixes exploration into every"
          " play — see PILOT_GREED)")
    runs = by(recs, "run_end")
    print(f"  runs finished   {len(runs)}")
    fights = by(recs, "fight_end")
    real = [f for f in fights if f.get("rounds", 0) > 0]
    print(f"  fights recorded {len(real)}")
    return real, runs


def report_agent(recs, fights):
    """The bot's own competence. Printed FIRST and deliberately: every quality
    measure below is conditional on this, and a reader who skips it will read a
    statement about the pilot as a statement about the game."""
    section("THE AGENT — read this before any claim about the game")
    commits = by(recs, "commit")
    if commits:
        unspent = statistics.mean(c.get("unspent", 0) for c in commits)
        print(f"  command unspent {unspent:.2f} per turn over {len(commits)}"
              " commits  (near 0 = the turn is being spent)")
        per_round = defaultdict(list)
        for c in commits:
            per_round[c.get("round", 0)].append(c.get("unspent", 0))
        line = "  by round      "
        for r in sorted(per_round)[:8]:
            line += f"  r{r}:{statistics.mean(per_round[r]):.2f}"
        print(line)
    plays = by(recs, "play")
    if plays:
        top = sum(1 for p in plays if p.get("taken_rank", 0) == 0)
        print(f"  top-scored play taken {fmt_pct(top, len(plays))} of"
              f" {len(plays)} plays  (the rest is deliberate exploration)")
    runs = by(recs, "run_end")
    if runs:
        sizes = [len(r.get("final_deck") or []) for r in runs]
        acts = [r.get("act_reached", 0) for r in runs]
        wins = sum(1 for r in runs if r.get("victory"))
        print(f"  deck at end     {sizes}  (a hero opens on 11)")
        print(f"  act reached     {acts}")
        print(f"  RUNS WON        {wins} of {len(runs)}")
    if fights:
        won = sum(1 for f in fights if f.get("won"))
        print(f"  fights won      {fmt_pct(won, len(fights))}"
              f"  ({won}/{len(fights)})")


def report_forced(recs):
    section("1. FORCED TURNS — how often is there anything to decide?")
    # ONE RECORD PER TURN, NOT PER PLAY. The second card played in a turn always
    # has fewer options than the first — Command has been spent and the card is
    # gone — so counting every play would measure the shape of a turn's tail and
    # report it as a property of the game. The decision that matters is the one
    # taken with the whole hand and the whole Command pool available.
    plays = [p for p in by(recs, "play") if p.get("nth_this_turn", 0) == 0]
    nothing = by(recs, "no_play")
    if not plays and not nothing:
        print("  no play records.")
        return
    one = sum(1 for p in plays if len(p.get("options") or []) == 1)
    many = len(plays) - one
    total = len(plays) + len(nothing)
    print(f"  turns with NO legal play      {len(nothing):5d} "
          f"{fmt_pct(len(nothing), total)}")
    print(f"  turns with exactly ONE play   {one:5d} {fmt_pct(one, total)}")
    print(f"  turns with a real choice      {many:5d} {fmt_pct(many, total)}")
    print()
    print("  A turn with 0 or 1 options is a formality. Split by round, because")
    print("  the Command ramp means the early game is where this bites:")
    per_round = defaultdict(lambda: [0, 0])
    for p in plays:
        r = p.get("round", 0)
        per_round[r][0] += 1
        if len(p.get("options") or []) <= 1:
            per_round[r][1] += 1
    for n in nothing:
        r = n.get("round", 0)
        per_round[r][0] += 1
        per_round[r][1] += 1
    print(f"    {'round':>6} {'decisions':>10} {'forced':>8} {'forced%':>9}")
    for r in sorted(per_round):
        if r > 9:
            break
        tot, forced = per_round[r]
        print(f"    {r:>6} {tot:>10} {forced:>8} {fmt_pct(forced, tot):>9}")


def report_decidedness(fights):
    section("2. DECIDEDNESS — how much of a fight happens after it is over?")
    base = board_baseline(fights)
    rows = []
    for f in fights:
        d = decidedness(f, base)
        if d is None:
            continue
        last, rounds, wasted = d
        rows.append((f.get("name", "?"), f.get("fight_act", 0),
                     bool(f.get("won")), last, rounds, wasted))
    if not rows:
        print("  no fights with a board trace.")
        return
    lost = [r for r in rows if not r[2]]
    won = [r for r in rows if r[2]]
    print(f"  fights traced   {len(rows)}   won {len(won)}  lost {len(lost)}")
    if won:
        print(f"  WON  fights run {statistics.mean(r[4] for r in won):.1f}"
              " rounds")
    if lost:
        print(f"  LOST fights run {statistics.mean(r[4] for r in lost):.1f}"
              " rounds, last in doubt at round"
              f" {statistics.mean(r[3] for r in lost):.1f}"
              f" — {statistics.mean(r[5] for r in lost) * 100:.0f}% of the fight"
              " was already decided")
    if won:
        print(f"  WON  fights: last in doubt at round"
              f" {statistics.mean(r[3] for r in won):.1f}"
              f" — {statistics.mean(r[5] for r in won) * 100:.0f}% played out"
              " after the result stopped being in question")
    # BY ACT, because a difficulty curve is the thing a roguelike is actually
    # tuning and a single win rate hides it completely. Read the `n` column:
    # act 3 is reached rarely, so its rate is the least trustworthy number here.
    per_act = defaultdict(lambda: [0, 0, 0.0])
    for name, act, w, last, rounds, wasted in rows:
        per_act[act][0] += 1
        per_act[act][1] += 1 if w else 0
        per_act[act][2] += rounds
    print()
    print(f"  {'act':>5} {'fights':>7} {'won':>5} {'win%':>7} {'rounds':>8}")
    for a in sorted(per_act):
        n, w, rd = per_act[a]
        print(f"  {a:>5} {n:>7} {w:>5} {pct(w, n):>6.0f}% {rd / n:>8.1f}")
    print()
    print("  Per encounter, worst first. A high wasted% with a low round count")
    print("  is a rout; a high wasted% with a high round count is the shape the")
    print("  owner is complaining about — slow, unclear and unrecoverable.")
    agg = defaultdict(list)
    for name, act, w, last, rounds, wasted in rows:
        agg[(act, name)].append((w, rounds, wasted))
    out = []
    for (act, name), vs in agg.items():
        n = len(vs)
        out.append((statistics.mean(v[2] for v in vs), act, name, n,
                    sum(1 for v in vs if v[0]),
                    statistics.mean(v[1] for v in vs)))
    out.sort(reverse=True)
    print(f"    {'act':>3} {'encounter':<30} {'n':>3} {'won':>4} "
          f"{'rounds':>7} {'wasted':>7}")
    for wasted, act, name, n, won_n, rounds in out[:18]:
        print(f"    {act:>3} {name[:30]:<30} {n:>3} {won_n:>4} "
              f"{rounds:>7.1f} {wasted * 100:>6.0f}%")


def report_lead_changes(fights):
    section("3. LEAD CHANGES — was it ever a contest?")
    base = board_baseline(fights)
    rows = [(lead_changes(f, base), f) for f in fights if (f.get("trace") or [])]
    if not rows:
        print("  no traces.")
        return
    changes = [c for c, _ in rows]
    zero = sum(1 for c in changes if c == 0)
    print(f"  mean lead changes per fight   {statistics.mean(changes):.2f}")
    print(f"  fights with ZERO lead changes {zero}/{len(rows)}"
          f" ({pct(zero, len(rows)):.0f}%)  — a procession, whoever won")
    won_c = [c for c, f in rows if f.get("won")]
    lost_c = [c for c, f in rows if not f.get("won")]
    if won_c:
        print(f"  ...in fights WON              {statistics.mean(won_c):.2f}")
    if lost_c:
        print(f"  ...in fights LOST             {statistics.mean(lost_c):.2f}")
    print()
    print("  A deckbuilder's fights are not supposed to be coin-flips, so a low")
    print("  number here is not automatically a fault — but zero across the")
    print("  board means the opening deal decides everything and the rest is")
    print("  animation.")


def report_snowball(fights):
    section("3b. THE SNOWBALL — does the board run away, and which way?")
    # Board gap (mine - theirs) by round, over every traced fight. The pilot's
    # card ledger already reports a single figure for this ("the board drifts
    # -6.5 per round against the player REGARDLESS of the card played"); this is
    # the same quantity as a CURVE, which is what separates "the player starts
    # behind and stays there" from "the player starts level and is ground down".
    # Those two want opposite fixes and a single number cannot tell them apart.
    won_by_round, lost_by_round = defaultdict(list), defaultdict(list)
    for f in fights:
        tgt = won_by_round if f.get("won") else lost_by_round
        for e in f.get("trace") or []:
            tgt[e.get("r", 0)].append(e.get("mine", 0) - e.get("theirs", 0))
    if not won_by_round and not lost_by_round:
        print("  no traces.")
        return
    print("  Board strength gap, mine minus theirs (ATK+HP over standing bodies).")
    print("  Round 1 is the muster: both lines deploy and neither swings.")
    print(f"    {'round':>6} {'n won':>6} {'gap won':>9} {'n lost':>7} {'gap lost':>9}")
    rounds = sorted(set(won_by_round) | set(lost_by_round))
    for r in rounds:
        if r > 12:
            break
        w, l = won_by_round.get(r, []), lost_by_round.get(r, [])
        ws = f"{statistics.mean(w):+.1f}" if w else "--"
        ls = f"{statistics.mean(l):+.1f}" if l else "--"
        print(f"    {r:>6} {len(w):>6} {ws:>9} {len(l):>7} {ls:>9}")
    print()
    print("  If the LOST column starts negative, fights are decided by the deal.")
    print("  If it starts level and falls, they are decided by attrition — and")
    print("  the hold refills from an infinite reinforcement while the player")
    print("  pays Command for every body, so attrition is not a symmetric race.")


def report_separation(recs):
    section("4. CHOICE SEPARATION — obvious, or interchangeable?")
    plays = by(recs, "play")
    seps = [s for s in (separation(p) for p in plays) if s is not None]
    if not seps:
        print("  no multi-option decisions.")
        return
    seps.sort()
    q = statistics.quantiles(seps, n=4) if len(seps) > 3 else [0, 0, 0]
    obvious = sum(1 for s in seps if s > 3.0)
    tossup = sum(1 for s in seps if s < 0.5)
    print(f"  decisions with 2+ options     {len(seps)}")
    print(f"  median gap to 2nd-best        {statistics.median(seps):.2f}"
          " stat points")
    print(f"  quartiles                     {q[0]:.2f} / {q[1]:.2f} / {q[2]:.2f}")
    print(f"  OBVIOUS (gap > 3.0)           {fmt_pct(obvious, len(seps))}"
          "  — the card picks itself")
    print(f"  TOSS-UP (gap < 0.5)           {fmt_pct(tossup, len(seps))}"
          "  — the cards are interchangeable")
    print()
    print("  Both extremes are failures and they fail in opposite directions.")
    print("  A healthy distribution has mass in the middle: a choice that")
    print("  matters and is not already made for you.")


def report_content(recs, fights):
    section("5. CONTENT — what actually gets seen, taken and played")
    plays = by(recs, "play")
    played = Counter()
    offered_in_hand = Counter()
    for p in plays:
        played[p.get("taken", "?")] += 1
        for o in p.get("options") or []:
            offered_in_hand[o["card"]["id"]] += 1
    print(f"  distinct cards PLAYED         {len(played)}")
    print(f"  distinct cards CONSIDERED     {len(offered_in_hand)}")
    never = [cid for cid, n in offered_in_hand.items() if cid not in played]
    if never:
        print(f"  considered but NEVER played   {len(never)}: "
              + ", ".join(sorted(never)[:12]))

    drafts = by(recs, "recruit")
    if drafts:
        taken = Counter(d.get("taken", "?") for d in drafts)
        seen = Counter()
        for d in drafts:
            for c in d.get("offered") or []:
                seen[c.get("id", "?")] += 1
        print()
        print(f"  musters                       {len(drafts)}")
        print("  DRAFT RATE — taken / offered. A card offered often and never")
        print("  taken is either weak or unreadable; both are worth knowing.")
        rows = [(pct(taken.get(c, 0), n), c, taken.get(c, 0), n)
                for c, n in seen.items() if n >= 2]
        rows.sort(reverse=True)
        print(f"    {'card':<26} {'taken':>6} {'seen':>6} {'rate':>7}")
        for rate, c, t, n in rows[:10]:
            print(f"    {c[:26]:<26} {t:>6} {n:>6} {rate:>6.0f}%")
        if len(rows) > 10:
            print("    ...")
            for rate, c, t, n in rows[-6:]:
                print(f"    {c[:26]:<26} {t:>6} {n:>6} {rate:>6.0f}%")

    routes = by(recs, "route")
    if routes:
        print()
        offered = Counter()
        chosen = Counter()
        forced = 0
        for r in routes:
            if r.get("forced"):
                forced += 1
            for o in r.get("offered") or []:
                offered[o.get("type", "?")] += 1
            chosen[r.get("taken", "?")] += 1
        print(f"  map stops                     {len(routes)}"
              f"   ({fmt_pct(forced, len(routes))} had no branch at all)")
        print(f"    {'node type':<14} {'offered':>8} {'taken':>7} {'rate':>7}")
        for t in sorted(offered, key=lambda k: -offered[k]):
            print(f"    {t:<14} {offered[t]:>8} {chosen.get(t, 0):>7} "
                  f"{pct(chosen.get(t, 0), offered[t]):>6.0f}%")

    shops = by(recs, "shop")
    if shops:
        bought = [s for s in shops if s.get("taken", "<none>") != "<none>"]
        print()
        # PER DECISION, not per screen: `_drive_shop` is re-entered while
        # anything on the shelf is still affordable, so one wagon produces
        # several records. Counting screens here would under-report buying by
        # the number of things bought at each one.
        print(f"  wagon decisions               {len(shops)},"
              f" purchases {len(bought)}")
        kinds = Counter(s.get("taken_kind", "?") for s in bought)
        if kinds:
            print(f"    bought: {dict(kinds)}")


def report_damage(fights):
    section("6. WHERE THE HERO'S HP GOES")
    lost = [f for f in fights if f.get("died")]
    if not lost:
        print("  no deaths recorded.")
        return
    rows = []
    for f in lost:
        fin = max(f.get("foe_in", 1), 1)
        fout = max(f.get("foe_out", 0), 0)
        rows.append((100.0 * (fin - fout) / fin, f.get("name", "?"),
                     f.get("fight_act", 0), f.get("rounds", 0), fout, fin,
                     f.get("hp_in"), f.get("node_type") or "?"))
    rows.sort()
    print("  The fights that ended a run, least-removed first. A death at 10%")
    print("  removed is a fight that was never winnable; at 90% it is tuning.")
    print("  `entered` is the hero's HP walking IN — a run of low numbers there")
    print("  means the run was lost before this fight, and the encounter named")
    print("  is the undertaker rather than the cause.")
    print(f"    {'act':>3} {'encounter':<28} {'kind':<7} {'entered':>8}"
          f" {'removed':>8} {'rounds':>7}")
    for removed, name, act, rounds, fout, fin, entered, kind in rows[:14]:
        ent = f"{entered}" if entered is not None else "--"
        print(f"    {act:>3} {name[:28]:<28} {kind[:7]:<7} {ent:>8}"
              f" {removed:>7.0f}% {rounds:>7}")
    entries = [r[6] for r in rows if r[6] is not None]
    if entries:
        print()
        print(f"  mean hero HP on entering a run-ending fight: "
              f"{statistics.mean(entries):.1f}")


def report_attrition(recs, fights):
    section("6b. THE RUN'S HP ECONOMY — is the attrition solvable at all?")
    # A roguelike run is an HP budget problem before it is anything else. Every
    # fight bills the hero; camps, potions, relics and the post-boss heal pay it
    # back. If the bill per fight times the fights per run exceeds what the road
    # can repay, the run is not lost to any one encounter — it is lost to
    # arithmetic, and no single fight will ever look like the culprit.
    #
    # Both halves are measured from the same stream: the COST is hp_in - hp_out
    # within a fight, and the REPAYMENT is the hp_in of the next fight minus the
    # hp_out of the last, which captures every source at once without needing to
    # know what any of them were.
    seq = sorted(fights, key=lambda f: f.get("seq", 0))
    costs, heals = [], []
    prev = None
    for f in seq:
        if f.get("rounds", 0) <= 0:
            continue
        # THE LOW-WATER MARK WHERE IT EXISTS. `hp_out` is the hero's HP when the
        # fight ENDED, which for a boss is after Combat's 75%-of-missing victory
        # heal — so the cost of the fight is erased by the reward for winning
        # it, and bosses read ~1 HP. Any mid-fight heal hides cost the same way.
        # Falls back to hp_out for journals written before hp_low existed.
        low = f.get("hp_low", f.get("hp_out", 0))
        cost = f.get("hp_in", 0) - low
        if cost >= 0:
            costs.append(cost)
        if prev is not None and f.get("run") == prev.get("run") \
                and f.get("hp_in", 0) > 0 and prev.get("hp_out", 0) > 0:
            # NEGATIVE GAPS COUNT. The first version kept only `gain >= 0`,
            # which drops every stop that COST hero HP — a curse's draw sting,
            # an event that takes a toll, a set-piece withdrawal — and so
            # measured the road's generosity while ignoring its bills. It
            # reported +11.8 recovered per gap against a 6.1 cost and concluded
            # attrition was not binding; that conclusion was an artifact of the
            # filter. A gap is a gap in both directions.
            heals.append(f.get("hp_in", 0) - prev.get("hp_out", 0))
        prev = f
    if not costs:
        print("  no fights with HP recorded.")
        return
    cost = statistics.mean(costs)
    heal = statistics.mean(heals) if heals else 0.0
    print(f"  fights measured              {len(costs)}")
    print(f"  hero HP spent per fight      {cost:.1f}")
    print(f"  hero HP recovered BETWEEN    {heal:.1f}"
          f"   (over {len(heals)} gaps — camps, potions, relics, boss heal)")
    net = cost - heal
    print(f"  NET drain per fight          {net:+.1f}")
    # BY KIND, because the bill is not one population. A rising "HP per fight"
    # can be a change in the MIX — more Generals, fewer plain holds — rather
    # than any fight getting harder, and the headline alone cannot tell them
    # apart. Blank for journals written before `node_type` was recorded.
    by_kind = defaultdict(list)
    for f in seq:
        if f.get("rounds", 0) <= 0:
            continue
        k = f.get("node_type") or "?"
        c = f.get("hp_in", 0) - f.get("hp_low", f.get("hp_out", 0))
        if c >= 0:
            by_kind[k].append(c)
    if set(by_kind) - {"?"}:
        print(f"    {'kind':<10} {'fights':>7} {'share':>7} {'HP each':>9}")
        total_n = sum(len(v) for v in by_kind.values())
        for k in sorted(by_kind, key=lambda x: -len(by_kind[x])):
            v = by_kind[k]
            print(f"    {k:<10} {len(v):>7} {pct(len(v), total_n):>6.0f}% "
                  f"{statistics.mean(v):>9.1f}")
    # A route is 7 combats per act plus the keep; three acts is ~21-24 fights.
    if net > 0:
        print(f"  => a 30 HP bar funds {30.0 / net:.1f} fights before something")
        print("     else has to pay. A full run is about 21.")
    else:
        print("  => the road repays more than the fights cost; attrition is not")
        print("     the binding constraint on this run.")
    print()
    print("  THIS IS AGENT-CONDITIONED and the cost half especially so — a better")
    print("  player takes fewer hits. The RECOVERY half is much more nearly a")
    print("  property of the game: it is what the road offers, and the pilot")
    print("  takes almost all of it.")


def report_economy(recs):
    section("7. THE RAMP — does the Command curve stay spendable?")
    commits = by(recs, "commit")
    plays = by(recs, "play")
    per_round_cost = defaultdict(list)
    for p in plays:
        opts = p.get("options") or []
        if opts:
            per_round_cost[p.get("round", 0)].append(opts[0]["cost"])
    if not commits:
        print("  no commit records.")
        return
    agg = defaultdict(lambda: {"un": [], "mx": [], "hand": []})
    for c in commits:
        a = agg[c.get("round", 0)]
        a["un"].append(c.get("unspent", 0))
        a["mx"].append(c.get("max_command", 0))
        a["hand"].append(c.get("hand_left", 0))
    print("  Command is a RAMP (1 on round 1, +1/round, cap 6) while draw is a")
    print("  FLAT 2 per turn. Those two curves diverge by construction, so the")
    print("  question is where the pool stops being spendable: unspent Command")
    print("  late is a resource with nothing to buy.")
    print(f"    {'round':>6} {'turns':>6} {'pool':>6} {'unspent':>8} {'waste%':>7}"
          f" {'cards left':>11} {'best-play cost':>15}")
    for r in sorted(agg):
        if r > 11:
            break
        a = agg[r]
        mx = statistics.mean(a["mx"]) if a["mx"] else 0
        un = statistics.mean(a["un"])
        cost = per_round_cost.get(r)
        cs = f"{statistics.mean(cost):.2f}" if cost else "--"
        print(f"    {r:>6} {len(a['un']):>6} {mx:>6.2f} {un:>8.2f} "
              f"{pct(un, mx):>6.0f}% {statistics.mean(a['hand']):>11.2f} {cs:>15}")


def report_outliers(fights):
    """WHICH FIGHTS ARE MISPRICED FOR THEIR TIER.

    Every other section here reads the run or the turn. This one reads the
    ENCOUNTER, and it is the section that found the two content defects of
    2026-09-26 (docs/PLAYTEST_MEASUREMENT_20260919.md §16-§18).

    THE BASELINE IS PRINTED FIRST AND THAT IS THE WHOLE METHOD. "The Tooth-Stones
    costs 20 hero HP" means nothing on its own; "an ordinary act-1 hold costs 0.4
    to 9.6 and this one costs 20" is a finding. A win rate compared against a
    number somebody remembers is how a tuning pass talks itself into a change.

    Grouped by (act, node_type) because those are the tiers the game itself
    prices: a keep is fought once and is chosen, a General can be walked past
    since the 2026-09-19 fight-count pass, and a plain combat is MANDATORY three
    times an act on the spine. The same HP bill means three different things
    across those.

    MIN_N exists because this table invites exactly one mistake — reading a 0%
    off n=1 as a broken encounter. Rows under the floor are counted, not ranked.
    """
    MIN_N = 5
    agg = {}
    for f in fights:
        key = (int(f.get("fight_act") or 0), str(f.get("node_type") or "?"),
               str(f.get("name") or "?"))
        a = agg.setdefault(key, {"n": 0, "won": 0, "died": 0, "hp": 0.0, "rd": 0.0})
        a["n"] += 1
        if f.get("won"):
            a["won"] += 1
        if f.get("died"):
            a["died"] += 1
        a["hp"] += float(f.get("hp_in") or 0) - float(f.get("hp_out") or 0)
        a["rd"] += float(f.get("rounds") or 0)

    section("9. MISPRICED FIGHTS — each encounter against its own TIER")
    print("  A fight is not hard or easy in the abstract, it is hard or easy for")
    print("  the tier it sits on. Tier medians first, then every encounter that")
    print("  sits furthest below its own tier's win rate.")
    print("")

    tiers = {}
    for (act, kind, _enc), a in agg.items():
        t = tiers.setdefault((act, kind), {"n": 0, "won": 0, "hp": 0.0, "encs": 0})
        t["n"] += a["n"]
        t["won"] += a["won"]
        t["hp"] += a["hp"]
        t["encs"] += 1
    print("     act kind      encs  fights   win%   HP each")
    for (act, kind) in sorted(tiers.keys()):
        t = tiers[(act, kind)]
        print("     %3d %-8s %5d %7d %6s %9.1f" % (
            act, kind, t["encs"], t["n"], fmt_pct(t["won"], t["n"]),
            t["hp"] / max(t["n"], 1)))

    rows = []
    thin = 0
    for (act, kind, enc), a in agg.items():
        if a["n"] < MIN_N:
            thin += 1
            continue
        t = tiers[(act, kind)]
        tier_wr = t["won"] / max(t["n"], 1)
        wr = a["won"] / a["n"]
        rows.append((wr - tier_wr, act, kind, enc, a, tier_wr))
    rows.sort()

    print("")
    print("  Only encounters BELOW their tier are listed — padding the list with a")
    print("  tier's best fights is how a 'worst first' table stops being read.")
    print("  `vs tier` is this encounter minus its tier's rate: a 40% boss and a")
    print("  40% road fight are not the same problem. `HPx` is its HP cost as a")
    print("  multiple of its tier's.")
    print("")
    print("    act kind    encounter                    n  win%  die%  vs tier   HPx  rnds")
    below = [r for r in rows if r[0] < -0.005]
    for delta, act, kind, enc, a, tier_wr in below[:14]:
        t = tiers[(act, kind)]
        tier_hp = t["hp"] / max(t["n"], 1)
        hp_each = a["hp"] / a["n"]
        mult = (hp_each / tier_hp) if tier_hp > 0.05 else 0.0
        print("    %3d %-7s %-26s %4d %4s %5s   %+5.0f%% %5.1fx %5.1f" % (
            act, kind, enc[:26], a["n"], fmt_pct(a["won"], a["n"]),
            fmt_pct(a["died"], a["n"]), 100.0 * delta, mult,
            a["rd"] / a["n"]))
    if not below:
        print("    (none — every encounter with n >= %d is at or above its tier)" % MIN_N)
    print("")
    print("    %d of %d ranked pairs sit below their tier." % (len(below), len(rows)))
    if thin:
        print("    (%d encounter/tier pairs under n=%d are not ranked — a 0%% read off"
              % (thin, MIN_N))
        print("     one fight is the single easiest way to misread this table.)")
    # WHERE THE HP ACTUALLY GOES, which is not the same list.
    #
    # The table above ranks by WIN RATE, so it only ever finds fights that kill
    # you. It is blind to the other way a run dies: a fight you WIN that bills
    # three times its tier, met four times an act. The §13 finding was that a
    # General costs 4x a hold — but there are far more holds, and the run-length
    # blocker is the HP economy rather than any single fight.
    #
    # So this ranks by TOTAL hero HP billed across the corpus (n x cost), which is
    # the only ordering that answers "what would I fix to make runs longer".
    total = sorted(agg.items(), key=lambda kv: -kv[1]["hp"])
    grand = sum(a["hp"] for _k, a in agg.items()) or 1.0
    print("")
    print("  TOTAL HP BILLED, by encounter. Ranked by n x cost rather than by win")
    print("  rate, because a fight you WIN at 3x your tier, met four times an act,")
    print("  drains a run harder than a rare disaster you only meet once.")
    print("")
    print("    act kind    encounter                    n  win%   HP each   TOTAL  share")
    run_share = 0.0
    for (act, kind, enc), a in total[:14]:
        share = 100.0 * a["hp"] / grand
        run_share += share
        print("    %3d %-7s %-26s %4d %5s %9.1f %7.0f %5.1f%%" % (
            act, kind, enc[:26], a["n"], fmt_pct(a["won"], a["n"]),
            a["hp"] / a["n"], a["hp"], share))
    print("")
    print("    those %d encounters are %.0f%% of every point of hero HP spent" % (
        min(14, len(total)), run_share))

def report_by_hero(recs, fights):
    """WHICH LORD WAS THIS, AND DOES THE ANSWER CHANGE THE VERDICT?

    Until 2026-09-26 the pilot never touched the roster, so 236 consecutive runs
    were `HeroDB.HERO_ORDER[0]` — the Raider — and nothing printed a hero name, so
    the corpus read like a statement about the game (§20). This section exists so
    that can never be true again silently: with one lord it says so in as many
    words, and with five it reports the ENVELOPE.

    That is the `Personas.gd` rule on the axis nobody applied it to: a difficulty
    conclusion is only ever true relative to the agent that produced it, and the
    HERO is part of the agent. A fight that is brutal for a Raider (mobility, Swift)
    and fair for a Stalwart (adjacency, repair) is a MATCHUP, not a difficulty — and
    only a spread across lords can tell those apart.

    HP cost is reported beside win rate and is the figure to trust: §21 measured the
    binomial floor at these sample sizes (1sd = 18pp at n=5) and found untouched
    content swinging 100 points between arms. HP is continuous and accumulates per
    fight, so it resolves where a win rate cannot.
    """
    hero_of_run = {}
    for r in recs:
        h = r.get("hero")
        if h:
            hero_of_run[(r.get("_file"), r.get("run"))] = str(h)

    section("10. THE LORDS — is this a property of the game or of one kit?")
    runs = by(recs, "run_end")
    seen = sorted({hero_of_run.get((r.get("_file"), r.get("run")), "?") for r in runs})
    if len(seen) <= 1:
        who = seen[0] if seen else "?"
        # TWO DIFFERENT PROBLEMS, and they need different words. An archived arm
        # from before 2026-09-26 has no `hero` field at all, so the honest report
        # is "not recorded" — telling a reader it was one lord would be asserting
        # something this file cannot see. A CURRENT arm showing one lord is the
        # rotation having failed, which is a live defect.
        if who == "?":
            print("  LORD NOT RECORDED in these journals.")
            print("")
            print("  Written before 2026-09-26, when the pilot began recording and")
            print("  rotating the hero. Every run in this corpus was almost certainly")
            print("  HeroDB.HERO_ORDER[0] (the Raider) — that is what 236 consecutive")
            print("  runs turned out to be — but this file cannot prove it, so treat")
            print("  the whole report as ONE UNKNOWN KIT. See PLAYTEST_MEASUREMENT")
            print("  _20260919.md §20.")
        else:
            print("  ONE LORD ONLY: %s" % who)
            print("")
            print("  The hero IS recorded, so the rotation ran and produced one lord.")
            print("  On a multi-run arm that is a DEFECT in the rotation, not a")
            print("  property of the game — check the roster is reachable on the run")
            print("  setup screen (the pilot logs 'roster not reachable' when it is")
            print("  not). Until then every number here is about that one kit.")
        return

    agg = {}
    for f in fights:
        h = hero_of_run.get((f.get("_file"), f.get("run")))
        if not h:
            continue
        a = agg.setdefault(h, {"n": 0, "won": 0, "hp": 0.0, "runs": set(),
                               "acts": [], "decks": []})
        a["n"] += 1
        if f.get("won"):
            a["won"] += 1
        a["hp"] += float(f.get("hp_in") or 0) - float(f.get("hp_out") or 0)
        a["runs"].add((f.get("_file"), f.get("run")))
    for r in runs:
        h = hero_of_run.get((r.get("_file"), r.get("run")))
        if not h or h not in agg:
            continue
        agg[h]["acts"].append(int(r.get("act_reached") or 0))
        if r.get("final_deck"):
            agg[h]["decks"].append(len(r["final_deck"]))

    print("  %-12s %5s %7s %7s %9s %8s %7s" % (
        "lord", "runs", "fights", "win%", "HP/fight", "act max", "deck"))
    for h in sorted(agg):
        a = agg[h]
        acts = a["acts"] or [0]
        decks = a["decks"] or [0]
        print("  %-12s %5d %7d %7s %9.1f %8d %7.1f" % (
            h, len(a["runs"]), a["n"], fmt_pct(a["won"], a["n"]),
            a["hp"] / max(a["n"], 1), max(acts),
            sum(decks) / max(len(decks), 1)))

    hps = [a["hp"] / max(a["n"], 1) for a in agg.values()]
    wrs = [a["won"] / max(a["n"], 1) for a in agg.values()]
    print("")
    print("  ENVELOPE across %d lords:  HP/fight %.1f - %.1f (spread %.1f)" % (
        len(agg), min(hps), max(hps), max(hps) - min(hps)))
    print("                            win%%      %.0f%% - %.0f%%" % (
        100 * min(wrs), 100 * max(wrs)))
    print("  A wide HP spread means the content is a MATCHUP against particular")
    print("  kits rather than a difficulty level. Read the spread, not the mean.")

    # And the coverage question the rotation was FOR: a lord you play is a lord
    # `RunState._select_rivals` can no longer deal you as a rival, so rotating the
    # hero is what makes every kingdom reachable. Report the rivals actually met.
    lords_met = Counter()
    for f in fights:
        if f.get("node_type") == "boss":
            lords_met[str(f.get("name"))] += 1
    print("")
    print("  RIVAL LORDS MET (the keep). A lord missing here is a KINGDOM missing:")
    for nm, c in lords_met.most_common():
        print("    %4dx %s" % (c, nm))
    if not lords_met:
        print("    none — no keep was reached")

def main():
    # PS 5.1 hands a native exe the system ANSI codepage, which turns every
    # em-dash in this report into a replacement character. Same trap the pilot's
    # own runner documents for Get-Content, seen from the writing side.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--since", default="")
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    files = find_journals(args.dir, args.since)
    if not files:
        print(f"no journals in {args.dir}", file=sys.stderr)
        return 1
    recs, bad = load(files)

    print("=" * 72)
    print("  THE PILOT'S DECISION JOURNAL — what the game offered, and what")
    print("  was chosen. Outcomes are the easy half; the options are the data.")
    print("=" * 72)

    arms = tag_arms(recs)
    fights, runs = report_coverage(recs, files, bad)
    report_ab(recs, arms)
    report_agent(recs, fights)
    report_forced(recs)
    report_decidedness(fights)
    report_lead_changes(fights)
    report_snowball(fights)
    report_separation(recs)
    report_content(recs, fights)
    report_damage(fights)
    report_attrition(recs, fights)
    report_economy(recs)
    report_outliers(fights)
    report_by_hero(recs, fights)

    if args.json:
        blob = {
            "files": [os.path.basename(f) for f in files],
            "records": len(recs),
            "fights": fights,
            "runs": runs,
        }
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(blob, fh, indent=1)
        print(f"\nwrote {args.json}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
