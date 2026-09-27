#!/usr/bin/env bash
# THE DIFFICULTY ENVELOPE ACROSS AGENTS OF DIFFERING SKILL.
#
# Method, and why it is a roster rather than one number:
#
#   "Monte-Carlo Tree Search for Simulation-based Strategy Analysis"
#   (arXiv:1908.01423) reports of Cardonomicon that "regardless of agent
#   strength, the player going second has a win rate substantially less than
#   50%", while noting that "win rates do increase for the agent going second if
#   they are more skilled". The usable rule: a balance property that holds across
#   EVERY agent strength is a property of the GAME; one that moves with agent
#   strength is a property of the AGENT.
#
#   "Predicting Game Engagement and Difficulty Using AI Players"
#   (arXiv:2107.12061) adds that PEAK agent performance predicts human difficulty
#   better than the mean -- so read the best persona per fight, not the average of
#   the roster.
#
# Personas.gd already provides both axes: `curve`/`aggro`/`control`/`trader` differ
# in PREFERENCE (weight vectors) and `novice` differs in SKILL ONLY (it shares
# curve's vector and adds blunder_rate). That is exactly the design the papers
# want, and the reason `curve` must never be "improved" -- it is the control arm.
#
# Usage: bash tools/_persona_envelope.sh [samples] [type]
GODOT="${GODOT_BIN:-D:/games/Godot_v4.6.2-stable_win64_console.exe}"
PROJ="D:/Godot"
OUT="${OUT:-/tmp/envelope}"; mkdir -p "$OUT"
export APPDATA="$OUT/userhome"; mkdir -p "$APPDATA"
SAMPLES="${1:-3}"
TYPE="${2:-combat}"

# The FIXED historical policy first, as a baseline: omitting --persona keeps the
# old numbers byte-comparable, which is the only way to tell a roster difference
# from a harness difference.
for p in "" curve novice aggro control trader; do
  tag="${p:-fixed}"
  log="$OUT/$tag.log"
  args="--samples=$SAMPLES --type=$TYPE --maxrounds=30"
  [ -n "$p" ] && args="$args --persona=$p"
  echo "=== persona=$tag ($args) ==="
  timeout 5400 "$GODOT" --headless --path "$PROJ" \
    --script res://tools/_probe_encwin.gd -- $args >"$log" 2>&1
  # The pooled line encwin prints at the end, plus any runtime error the driver
  # did not notice (a GDScript error neither raises nor changes the exit code).
  grep -E "^\[encwin\] TOTALS" "$log" | tail -1
  errs=$(grep -cE "SCRIPT ERROR" "$log")
  echo "    runtime errors in log: $errs"
done
echo "logs in $OUT"
