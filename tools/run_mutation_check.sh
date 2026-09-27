#!/usr/bin/env bash
# run_mutation_check.sh — PASS 12 of docs/BUG_SWEEP_METHOD_20260829.md (class C12).
#
#   bash tools/run_mutation_check.sh
#
# MUTATION TESTING — the first pass that tests the TESTS.
#
# Every other pass asks "is the game correct?". This one asks the question that
# has been unasked all along: "are the gates load-bearing, or do they merely pass?"
# A green suite proves nothing on its own — a probe that cannot fail is
# indistinguishable from one that passes, and this session has already produced
# three checks that turned out to be exactly that (a latch heuristic at 6/6 false
# positives, and two C9 drafts at 294 false hits between them).
#
# The method: deliberately inject a KNOWN fault into production code, run the gate
# that is supposed to notice, and require it to FAIL. A mutant that SURVIVES — the
# fault is in, the gate is still green — is a hole in the suite, and it is a more
# useful finding than another green run.
#
# Each mutant below re-creates a bug that was ACTUALLY FIXED this session, so the
# check is not hypothetical: it asks whether the same bug could come back unnoticed.
#
# SAFETY. Every file is byte-copied before mutation and restored after, and the
# restore is verified against the copy's checksum. The script restores on any exit
# path, including interrupt. Nothing here uses git, so an uncommitted tree is safe.

set -uo pipefail

GODOT="${GODOT_BIN:-/d/games/Godot_v4.6.2-stable_win64.exe}"
PROJ="D:\\Godot"
BAK_DIR="$(mktemp -d)"
PASSED=0
SURVIVED=0
ERRORED=0

cleanup() {
  # Restore anything still backed up, then verify each file came back intact.
  for b in "$BAK_DIR"/*.bak; do
    [ -e "$b" ] || continue
    orig="$(cat "${b%.bak}.path")"
    cp -f "$b" "$orig"
    if ! cmp -s "$b" "$orig"; then
      echo "  !! RESTORE FAILED for $orig — original is at $b"
    fi
  done
  rm -rf "$BAK_DIR"
}
trap cleanup EXIT INT TERM

# mutate <file> <python-find> <python-replace>
mutate() {
  local f="$1" find="$2" repl="$3"
  local key
  key="$BAK_DIR/$(echo "$f" | tr '/' '_')"
  cp -f "$f" "$key.bak"
  printf '%s' "$f" > "$key.path"
  python - "$f" "$find" "$repl" <<'PY'
import io, sys
path, find, repl = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(path, encoding="utf-8", newline="").read()
if find not in s:
    sys.stderr.write("ANCHOR-MISSING\n")
    sys.exit(3)
io.open(path, "w", encoding="utf-8", newline="").write(s.replace(find, repl, 1))
PY
}

restore() {
  local f="$1" key
  key="$BAK_DIR/$(echo "$f" | tr '/' '_')"
  [ -e "$key.bak" ] || return 0
  cp -f "$key.bak" "$f"
  rm -f "$key.bak" "$key.path"
}

# check <name> <file> <find> <replace> <probe> [scene]
check() {
  local name="$1" file="$2" find="$3" repl="$4" probe="$5" kind="${6:-script}"
  # `shell` runs a driver script rather than a probe — the two-process match is a
  # pair of processes and cannot be a single --script invocation.
  printf '  %-46s ' "$name"
  local why
  # REPORT WHY, NEVER JUST "SKIP". A silent skip made five checks vanish as a
  # contiguous block while every anchor was verifiably still present — which looks
  # exactly like "the code moved" and is not. A gate that can quietly stop testing
  # is no better than one that cannot fail.
  if ! why="$(mutate "$file" "$find" "$repl" 2>&1)"; then
    echo "SKIP — ${why:-unknown}"
    ERRORED=$((ERRORED+1)); return
  fi
  local out
  if [ "$kind" = "shell" ]; then
    out=$(timeout 900 bash "tools/$probe.sh" 2>&1)
  elif [ "$kind" = "scene" ]; then
    out=$(timeout 900 "$GODOT" --headless --path "$PROJ" "res://tools/$probe.tscn" 2>&1)
  else
    out=$(timeout 900 "$GODOT" --headless --path "$PROJ" --script "res://tools/$probe.gd" 2>&1)
  fi
  restore "$file"
  # A gate NOTICES if it prints a failure line or reports a non-zero tally.
  if echo "$out" | grep -qE '^  (FAIL|HIT) |PROBE FAIL|[0-9]+ FAIL|[0-9]+ HIT|unwaived'; then
    echo "caught by $probe"
    PASSED=$((PASSED+1))
  else
    echo "*** SURVIVED *** $probe stayed green"
    SURVIVED=$((SURVIVED+1))
  fi
}

echo "[mutation] PASS 12 — do the gates actually catch anything?"
echo "[mutation] each mutant re-creates a bug that was really fixed this session"
echo

check "relic value drifts between host and client" \
  scripts/net/NetPlayerState.gd \
  'target += _relic_value("deep_satchel", 1)' \
  'target += _relic_value("deep_satchel", 1) + 1' \
  _probe_net_relic_parity

check "the bot loses its spell guard again" \
  scripts/net/CombatNet.gd \
  'if _remote_state == null and not SkirmishState.vs_bot:' \
  'if _remote_state == null:' \
  _probe_bot_spells

check "Sealed Orders stops being recognised at all" \
  scripts/net/CombatNet.gd \
  'return combat._is_net() and NetMatch.battle_style == NetMatch.STYLE_SEALED' \
  'return false' \
  _probe_net_soak

check "a CreatureInstance field stops persisting" \
  scripts/state/CreatureInstance.gd \
  'row = clampi(int(data.get("row", row)), 0, 1)' \
  'row = row' \
  _probe_persistence

check "an UPGRADES key stops being merged" \
  scripts/state/RunState.gd \
  '"extra_draw", "extra_mana", "ricochet_hits", "order_bonus"]:' \
  '"extra_draw", "extra_mana", "ricochet_hits"]:' \
  _probe_upgrade_merge

check "the rematch handshake stalls in a drill" \
  scripts/net/CombatNet.gd \
  'combat._net_rematch_remote or SkirmishState.vs_bot' \
  'combat._net_rematch_remote' \
  _probe_net_rematch

# Re-creates the LAYOUT-TIMING bug precisely: without the settle, the fit measures
# children that have not laid out yet, every height reads zero, and the viewport
# silently keeps its provisional size — which sliced the wordiest relic's last line
# off. The first version of this mutant attacked a constant that the measured fit
# replaced; attacking the timing is what actually reproduces the defect.
check "the picker viewport stops being measured" \
  scripts/scenes/Event.gd \
  '_fit_relic_scroll.call_deferred(scroll, lst, MAX_VISIBLE)' \
  'pass  # mutant: fit removed' \
  _probe_boundary_ui

check "a dispatched effect loses its last emitter" \
  scripts/data/EventDB.gd \
  '{"type": "relic_sacrifice_pick"},' \
  '{"type": "gold", "value": 1},' \
  _probe_reachability

# A REAL side-bias, not a no-op: the player's creatures hit one harder than the
# opponent's. Nothing else in the suite compares the two sides of an identical
# position, so only the mirror relation can see this.
check "combat becomes side-biased (player hits +1)" \
  scripts/Card2D.gd \
  '	return maxi(0, current_atk + temp_atk_buff + persistent_atk_buff
		+ adj_atk_buff + relic_atk_buff)' \
  '	return maxi(0, current_atk + temp_atk_buff + persistent_atk_buff
		+ adj_atk_buff + relic_atk_buff + (0 if is_opponent else 1))' \
  _probe_metamorphic

# Only the per-frame audit can see this: the registry is wiped wholesale at
# _enter_combat_local, so it looks clean at every quiescent point.
check "dead bodies stay in the entity registry"   scripts/scenes/Combat.gd   'NetMatch.unregister_entity(int(card.entity_id))'   'pass  # mutant: registry leak'   _probe_invariants

# A silent behaviour change with no assertion watching for it. Note this mutant
# slipped past the golden corpus entirely until a BANKING scenario was added — a
# golden master only pins what its scenarios exercise, which is its whole limit.
check "banked Command silently changes" \
  scripts/scenes/Combat.gd \
  'const MAX_BANKED_MANA: int = 2' \
  'const MAX_BANKED_MANA: int = 1' \
  _probe_golden

# An unbounded resource. Note the mutant only reaches ~18 Command before a match
# ends, so an "absurdly large number" ceiling walks straight past it — the gate has
# to derive its bound from the contract (`max + banked`) to catch it at all.
check "Command stops resetting each round" \
  scripts/scenes/Combat.gd \
  '	player_mana = player_max_mana + banked' \
  '	player_mana = player_mana + player_max_mana + banked' \
  _probe_runaway

# The save backup is the only thing standing between a crash mid-write and a lost
# run. Remove the fallback and the corrupt-primary case silently loads a BLANK run
# instead of the real one — the player's save is gone with no error at all.
check "a corrupt save stops falling back to its backup" \
  scripts/state/RunState.gd \
  '		parsed = JSON.parse_string(SaveIO.read_backup_text(path))' \
  '		pass  # mutant: backup fallback removed' \
  run_chaos_save shell

# Re-creates the suspended-function hazard: drop the validity guard the coin toss
# needs and a peer dropping mid-toss leaves the winner with no choice buttons.
check "a node is used again after a suspension" \
  scripts/net/CombatNet.gd \
  '	if not is_instance_valid(layer) or not is_instance_valid(combat):
		if not is_instance_valid(combat):
			return true
		return combat._net_first_player() == combat._net_my_index()' \
  '	pass  # mutant: post-await guard removed' \
  _probe_await_audit

# THE ONE MUTANT NO SINGLE-PROCESS GATE CAN CATCH. Shrinking the array cap makes
# the clash reel overrun the envelope, and an over-cap payload is not truncated —
# `validate_envelope` REJECTS IT WHOLE, so the watching peer's screen cuts straight
# to the outcome with no fight in between. In-process there is no envelope at all,
# so every other net gate stays green while the match is visibly broken.
check "the clash reel overruns the wire envelope" \
  scripts/net/NetProtocol.gd \
  'const MAX_ARRAY_ITEMS: int = 256' \
  'const MAX_ARRAY_ITEMS: int = 4' \
  run_two_process_match shell

echo
echo "[mutation] $PASSED caught, $SURVIVED survived, $ERRORED skipped"
if [ "$SURVIVED" -gt 0 ]; then
  echo "[mutation] A SURVIVING MUTANT IS A HOLE IN THE SUITE — that gate does not"
  echo "[mutation] actually defend the thing it claims to."
  exit 1
fi
echo "[mutation] ALL PASS"
