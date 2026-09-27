#!/usr/bin/env bash
# run_two_process_match.sh — PASS 17 of docs/BUG_SWEEP_METHOD_20260829.md (class C17).
#
#   bash tools/run_two_process_match.sh
#
# Launches TWO real Godot processes that play a skirmish against each other over a
# real ENet socket on loopback, then DIFFS what each side believes the match was.
#
# This is the pass the method doc has listed as the standing infrastructure gap.
# See the header of tools/_probe_two_process.gd for why one process cannot stand in
# for two: in-process, the "wire" is a function call and a payload is never encoded,
# never sized, never validated, and never delivered late or out of order.
#
# Both battle styles are run, because they are two different turn machines and the
# ALTERNATING one is the only one where the peers strictly take turns over the wire.

set -uo pipefail

GODOT="${GODOT_BIN:-/d/games/Godot_v4.6.2-stable_win64.exe}"
PROJ="D:\\Godot"
WORK="$(mktemp -d)"
FAILED=0

cleanup() {
  # Never leave a headless Godot holding the port.
  kill $(jobs -p) 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

run_style() {
  local style="$1" name="$2"
  echo
  echo "[2p] ===== $name ====="
  local hout="$WORK/host_$style.json" cout="$WORK/client_$style.json"
  local hlog="$WORK/host_$style.log" clog="$WORK/client_$style.log"
  rm -f "$hout" "$cout"

  BM_ROLE=host   BM_OUT="$hout" BM_STYLE="$style" \
    timeout 180 "$GODOT" --headless --path "$PROJ" res://tools/_probe_two_process.tscn \
    > "$hlog" 2>&1 &
  local hpid=$!
  BM_ROLE=client BM_OUT="$cout" BM_STYLE="$style" \
    timeout 180 "$GODOT" --headless --path "$PROJ" res://tools/_probe_two_process.tscn \
    > "$clog" 2>&1 &
  local cpid=$!

  wait $hpid; local hrc=$?
  wait $cpid; local crc=$?

  grep -hE '^  (PASS|FAIL)  ' "$hlog" "$clog" | sed 's/^/  /'

  # A process that dies before writing its digest is itself the finding, so say so
  # rather than letting the diff report a confusing empty-vs-full mismatch.
  if [ ! -s "$hout" ] || [ ! -s "$cout" ]; then
    echo "  FAIL  a peer never wrote its digest (host rc=$hrc client rc=$crc)"
    echo "  ---- host tail ----";   tail -n 14 "$hlog" | sed 's/^/    /'
    echo "  ---- client tail ----"; tail -n 14 "$clog" | sed 's/^/    /'
    FAILED=$((FAILED+1)); return
  fi

  python - "$hout" "$cout" "$name" <<'PY'
import json, sys
h = json.load(open(sys.argv[1])); c = json.load(open(sys.argv[2])); name = sys.argv[3]
bad = 0
def check(ok, label):
    global bad
    print("  %s  %s" % ("PASS" if ok else "FAIL", label))
    if not ok: bad += 1

# THE CROSS-PROCESS DIFF. Two processes that played the same match must agree
# about it. Hero HP is the sharpest term: the host owns it and the client is told,
# so a divergence means an authoritative number did not survive the wire.
check(h.get("player_hp") == c.get("enemy_hp") and h.get("enemy_hp") == c.get("player_hp"),
      "%s: both peers agree on both heroes' HP (host %s/%s vs client %s/%s)" % (
      name, h.get("player_hp"), h.get("enemy_hp"), c.get("player_hp"), c.get("enemy_hp")))

# The board compared by ENTITY ID, the one identity both peers share.
# Sealed stand-ins (entity_id -1) are LOCAL PREVIEWS with no network identity and
# are excluded — comparing them would report a desync on every sealed run purely
# for having sampled one peer mid-orders. They are not ignored, though: the orphan
# check below is the sharper question about exactly those bodies.
def real(d): return set(x for x in (d.get("board") or []) if not x.startswith("-1:"))
hb, cb = real(h), real(c)
if hb != cb:
    for x in sorted(hb - cb): print("      only on host:   %s" % x)
    for x in sorted(cb - hb): print("      only on client: %s" % x)
check(hb == cb, "%s: both peers hold an identical board by entity id (%d bodies)" % (
      name, len(hb)))

# An UNREGISTERED body that nothing is tracking as pending is an orphan: the host
# addresses every net beat by entity id, so a -1 body no longer in `_sealed_pending`
# can never be flashed, buffed, killed or swept by anything the host says.
for side in (h, c):
    for o in (side.get("orphans") or []):
        print("      orphan on %s: %s" % (side.get("role"), o))
check(not h.get("orphans") and not c.get("orphans"),
      "%s: no unregistered body is orphaned on either board" % name)

check(not h.get("rejections") and not c.get("rejections"),
      "%s: no protocol rejection on either peer" % name)
check(h.get("turns", 0) >= 2 and c.get("turns", 0) >= 2,
      "%s: both peers took real turns (host %s, client %s)" % (
      name, h.get("turns"), c.get("turns")))
# VACUITY GUARD: an empty board on both sides would satisfy the diff above while
# proving nothing happened at all.
check(len(hb) > 0, "%s: the match actually put bodies on the board" % name)
sys.exit(1 if bad else 0)
PY
  [ $? -ne 0 ] && FAILED=$((FAILED+1))
}

echo "[2p] PASS 17 — two processes, one real socket, one real match"

run_style 0 "ALTERNATING"
run_style 1 "SEALED ORDERS"

echo
if [ "$FAILED" -gt 0 ]; then
  echo "[2p] $FAILED style(s) FAILED"
  exit 1
fi
echo "[2p] ALL PASS"
