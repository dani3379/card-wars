#!/usr/bin/env bash
# Batch probe sweep. Scores RED only on a per-check FAIL line or a real
# SCRIPT ERROR / Parse Error -- never on the absence of a guessed sentinel
# (see reference_stale_probe_sweep: that mistake reported 16/18 gates red
# against a suite that was 18/18 green).
GODOT="${GODOT_BIN:-D:/games/Godot_v4.6.2-stable_win64_console.exe}"
PROJ="D:/Godot"
OUT="${SWEEP_OUT:-/tmp/sweep}"
TMO="${SWEEP_TIMEOUT:-150}"
mkdir -p "$OUT"
export APPDATA="$OUT/userhome"; mkdir -p "$APPDATA"

for name in "$@"; do
  log="$OUT/$name.log"
  if [ -f "$PROJ/tools/_probe_$name.tscn" ]; then
    target="res://tools/_probe_$name.tscn"; mode=scene
  else
    target="res://tools/_probe_$name.gd"; mode=script
  fi
  if [ "$mode" = scene ]; then
    timeout "$TMO" "$GODOT" --headless --path "$PROJ" "$target" >"$log" 2>&1
  else
    timeout "$TMO" "$GODOT" --headless --path "$PROJ" --script "$target" >"$log" 2>&1
  fi
  rc=$?
  # SCORING LIVES IN EXACTLY ONE PLACE — _score_probe_logs.sh.
  #
  # This script used to carry its own copy of the rule, and the two drifted the
  # moment one was fixed: the scorer learned that `FAILED : 0 []` is a PASS while
  # this file still scored it RED, so the same `modal` log read green from one
  # tool and red from the other in the same session. That is the duplicate-rule
  # pathology this codebase has paid for repeatedly (NetPlayerState restating
  # relic magnitudes; SkirmishBot's scorer beside BoardEval) — equal on the day
  # it is written, and one fix away from disagreeing silently.
  #
  # Timeout is the one verdict the scorer cannot reach, because it is a property
  # of the RUN and not of the log, so it stays here.
  if [ $rc -eq 124 ]; then
    echo "TIMEOUT $name"
  else
    bash "$(dirname "$0")/_score_probe_logs.sh" "$log"
  fi
done
