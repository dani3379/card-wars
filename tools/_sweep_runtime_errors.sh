#!/usr/bin/env bash
# "What did the GAME say while the driver played?"  A GDScript runtime error
# does not raise, does not stop the game and does not change the exit code --
# so a soak can report a clean win rate over a fight whose resolver aborted
# halfway.  run_pilot.ps1 applies this oracle to ONE driver; this applies it
# to the content-heavy soaks, which reach acts 2-3 the pilot never survives to.
GODOT="${GODOT_BIN:-D:/games/Godot_v4.6.2-stable_win64_console.exe}"
PROJ="D:/Godot"
OUT="${OUT:-/tmp/rterr}"; mkdir -p "$OUT"
export APPDATA="$OUT/userhome"; mkdir -p "$APPDATA"
name="$1"; shift
log="$OUT/$name.log"
timeout "${TMO:-3000}" "$GODOT" --headless --path "$PROJ" --script "res://tools/_probe_$name.gd" -- "$@" >"$log" 2>&1
echo "exit=$? log=$log lines=$(wc -l <"$log")"
echo "--- runtime errors the driver did not notice ---"
grep -nE "SCRIPT ERROR|Parse Error|Invalid (access|call|index|get|set|operands)|Cannot call|Null instance|out of bounds|Division By Zero|Condition .* is (true|false)" "$log" \
  | grep -v "^\s*$" | head -40
echo "--- distinct error signatures ---"
grep -oE "SCRIPT ERROR:.*|Invalid [a-z ]+ '[^']*'" "$log" | sed 's/[0-9]\+/N/g' | sort | uniq -c | sort -rn | head -20
