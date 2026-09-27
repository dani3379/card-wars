#!/usr/bin/env bash
# Re-score probe logs WITHOUT re-running them.
# Case-SENSITIVE FAIL only: lowercase prose ("failing", "fails on judgement
# calls") is the trap that made a green suite read 16/18 red twice before.
for log in "$@"; do
  name=$(basename "$log" .log)
  clean=$(grep -viE "leaked|RID allocation|resources still in use|ObjectDB instances" "$log")
  # Real failure: uppercase FAIL/FAILED, not a zero tally, not inside prose.
  #
  # THE ZERO-TALLY EXCLUSION IS ANCHORED AT END-OF-LINE, deliberately. The first
  # version wrote the trailing context as `(\s|$)`, and `$` inside an alternation
  # group is not an anchor -- so `[modal] FAILED           : []` (an EMPTY failure
  # list, i.e. a PASS) scored RED. That is the same false-positive family that has
  # now bitten this sweep three times; each spelling of a tally has to be matched
  # exactly, so they are enumerated rather than guessed at.
  # The tally forms actually emitted by this suite, all verified against real
  # logs: `FAILED : 0` · `FAILED : []` · `FAILED : 0 []` · `FAILED: 0` · `fails=0`.
  # A nonzero count is NOT excluded even when followed by an empty list, because
  # those two disagreeing is itself worth a look.
  fails=$(printf '%s\n' "$clean" | grep -E "\bFAIL(ED)?\b" \
    | grep -vE "FAIL(ED)?[[:space:]]*[:=][[:space:]]*0?[[:space:]]*(\[ *\])?[[:space:]]*$" \
    | grep -vE "fails?=0|0 FAIL|NO FAIL|FAIL(ED)?[[:space:]]*:?[[:space:]]*none")
  errs=$(printf '%s\n' "$clean" | grep -E "^\s*(SCRIPT ERROR|Parse Error)")
  if [ -n "$errs" ]; then
    echo "ERROR $name :: $(printf '%s' "$errs" | head -1 | cut -c1-150)"
  elif [ -n "$fails" ]; then
    echo "RED   $name ($(printf '%s\n' "$fails" | wc -l)) :: $(printf '%s' "$fails" | head -1 | cut -c1-150)"
  else
    echo "green $name"
  fi
done
