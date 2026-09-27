#!/usr/bin/env bash
# Attribute Godot's UNATTRIBUTED runtime errors to the effect that caused them.
#
# A GDScript error names a line in Combat.gd, not the content that reached it, so
# a bare error dump cannot be acted on and gets skimmed. _probe_resolver_sweep
# prints "[resolver] TRY <id> ..." before every resolution; this walks the log IN
# ORDER and blames each error on the last TRY seen. The ordering is the mechanism.
#
# Usage: bash tools/_score_resolver_sweep.sh /tmp/resolver.log
set -u
log="${1:?usage: _score_resolver_sweep.sh <log>}"

awk '
  /^\[resolver\] TRY / { cur = $3 " " $4; next }
  # Godot runtime faults. Deliberately NOT matching the word "fail" in any case:
  # probe prose contains it, and that false-positive class has twice reported a
  # green suite as mostly red.
  /SCRIPT ERROR|Parse Error|Invalid access|Invalid call|Invalid index|Invalid get|Invalid set|Invalid operands|Cannot call|Null instance|out of bounds|Division By Zero|Trying to assign/ {
    who = (cur == "" ? "<before any TRY>" : cur)
    line = $0
    sub(/^[ \t]+/, "", line)
    print who "\t" line
  }
' "$log" | sort | uniq -c | sort -rn > /tmp/resolver_attributed.txt

n=$(wc -l < /tmp/resolver_attributed.txt)
echo "=== runtime errors attributed to a specific effect: $n distinct ==="
if [ "$n" -gt 0 ]; then
  cat /tmp/resolver_attributed.txt
else
  echo "  (none)"
fi

echo
echo "=== probe-side tallies (read these before believing the verdict) ==="
grep -E "^\[resolver\] (resolved|skipped|invariant hits|inventory|[0-9]+ failures|PASS|FAIL)" "$log"
echo
echo "=== invariant hits ==="
grep -E "^\[resolver\] INVARIANT" "$log" || echo "  (none)"
echo
echo "=== effects that were SKIPPED (untested surface, not a pass) ==="
grep -E "^\[resolver\]   SKIP" "$log" || echo "  (none)"
