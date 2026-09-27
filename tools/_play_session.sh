#!/usr/bin/env bash
# Drive several pilot runs and keep each report. The pilot is the only harness
# that holds the mouse, so it must run ALONE -- CPU contention perturbs Fitts
# timing and manufactures findings that are about the machine, not the game.
OUT="${OUT:-/tmp/play}"; mkdir -p "$OUT"
for seed in "$@"; do
  echo "=== pilot seed $seed ==="
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_pilot.ps1 \
    -GodotPath "D:/games/Godot_v4.6.2-stable_win64_console.exe" \
    -Seconds 420 -Seed "$seed" -Windowed >"$OUT/run_$seed.console" 2>&1
  cp tools/_pilot_run.log "$OUT/pilot_$seed.log" 2>/dev/null
  grep -E "PILOT:" "$OUT/run_$seed.console" | tail -1
done
echo "logs in $OUT"
