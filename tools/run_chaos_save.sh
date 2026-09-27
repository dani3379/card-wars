#!/usr/bin/env bash
# run_chaos_save.sh — driver for PASS 21 (class C21, chaos / fault injection).
#
#   bash tools/run_chaos_save.sh
#
# The probe writes deliberate garbage into `user://`, so it must never run against
# the developer's real saves. GODOT_USER_HOME is a NO-OP on Windows, so the only
# reliable way to relocate `user://` here is to move APPDATA — see the project
# memory note on probe user-data isolation.
set -uo pipefail
GODOT="${GODOT_BIN:-/d/games/Godot_v4.6.2-stable_win64.exe}"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM
export APPDATA="$(cygpath -w "$SANDBOX" 2>/dev/null || echo "$SANDBOX")"
export BM_CHAOS_OK=1
timeout 600 "$GODOT" --headless --path "D:\Godot" --script res://tools/_probe_chaos_save.gd
rc=$?
echo "[chaos] sandbox was: $SANDBOX (removed)"
exit $rc
