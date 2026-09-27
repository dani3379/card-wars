extends SceneTree
## _probe_guard_audit.gd — PASS 2 of docs/BUG_SWEEP_METHOD_20260829.md (class C3).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_guard_audit.gd
##
## GUARD ASYMMETRY: a predicate applied in one sibling and forgotten in another.
## This class hides because the guarded path works, so the feature "works" in every
## test that happens to take it. THREE of this session's bugs were exactly this, and
## each one generalises into a mechanical rule:
##
##   A. `_remote_state` DEREFERENCED WITHOUT A vs_bot GUARD.
##      `_net_init_remote_authority` returns false the moment `vs_bot` is set, so
##      `_remote_state` is null in every practice match. `_net_apply_remote_spell`
##      dereferenced it unguarded where its sibling `_net_apply_remote_creature`
##      guarded every call — so the bot could never cast a spell, while being
##      charged Command for the attempt.
##
##   B. A TURN GATE WITH NO SEALED BRANCH.
##      Sealed Orders sets `_net_active_index = -1` on purpose (both sides commit at
##      once, nobody holds the turn). `_on_card_played` refused every card because of
##      it, where its sibling `_toggle_discard_mark` carried the `_is_sealed` branch
##      — the whole battle style could not seat a creature.
##
##   C. A LATCH SET IN ONE BRANCH AND NOT ITS TWIN.
##      `_net_on_peer_lost` claimed `_net_peer_lost_handled` on its post-match path
##      and not its mid-match path, so a second delivery armed a second teardown.
##
## Waivers carry the reason a site is legitimately unguarded. As with Pass 1, an
## entry is DEBT made visible, not an absolution.

## func name -> why it may touch _remote_state without naming vs_bot.
const WAIVED_REMOTE_STATE: Dictionary = {
	"_net_init_remote_authority":
		"it is the constructor — it returns early on vs_bot before assigning",
	"_net_remote_field_card_left":
		"null-checked on entry (`_remote_state == null` → return)",
	"_net_process_intent":
		"the potion arm null-checks inline; only a real client sends IN_USE_POTION, "
		+ "and the practice bot never drinks (BOT_RELIC_POOL ships no potions)",
	"_net_apply_private_state":
		"client-side only (`if not combat._is_client(): return`) — a client always "
		+ "has a real host, so there is no drill case",
}

## func name -> why a turn gate there needs no sealed branch.
const WAIVED_TURN_GATE: Dictionary = {
	"_net_field_move_dropped":
		"reposition is refused wholesale in sealed (board_interactive stays false, "
		+ "and the intent arm rejects `move_not_allowed_in_sealed`)",
	"_net_sniper_aim_dropped":
		"aiming is refused wholesale in sealed with its own message",
	"_net_sniper_aim_clear":
		"the clear half of the same refusal",
	"_net_on_done_placing":
		"routes to `_sealed_on_button()` on its first line, before the gate",
	"_combat_process_needed":
		"a repaint predicate, not a rule — the worst case is an idle frame",
	"_update_combat_telegraph":
		"a repaint predicate, not a rule. In sealed it reads `opp_turn` true during "
		+ "your own orders phase (active index is -1, which != your index), and that "
		+ "happens to be the wanted behaviour — the forecast IS useful while you plan "
		+ "— so the outcome is right even though the reasoning is incidental",
	"_net_set_local_active":
		"sets HUD state from an already-decided active index; decides nothing",
	"_player_turn_caption":
		"already sealed-aware via its own `_is_sealed()` branch above the gate",
}

var _started := false
var _done := false
var _fails := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## Split a GDScript file into {name, body[], start_line}. Nested funcs do not exist
## in GDScript, so a line beginning `func ` is unambiguous.
func _functions_in(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var lines := f.get_as_text().split("\n")
	f.close()
	var out: Array = []
	var cur: Dictionary = {}
	for i in lines.size():
		var line: String = lines[i]
		if line.begins_with("func ") or line.begins_with("static func "):
			if not cur.is_empty():
				out.append(cur)
			var nm := line.substr(line.find("func ") + 5)
			nm = nm.substr(0, maxi(nm.find("("), 0))
			cur = {"name": nm.strip_edges(), "body": [], "line": i + 1, "file": path}
		elif not cur.is_empty():
			cur.body.append(line)
	if not cur.is_empty():
		out.append(cur)
	return out


func _joined(fn: Dictionary) -> String:
	return "\n".join(PackedStringArray(fn.body))


func _emit(title: String, hits: Array, waivers: Dictionary) -> void:
	var live: Array = []
	var waived: Array = []
	for h in hits:
		var nm := String((h as Dictionary).name)
		if waivers.has(nm):
			waived.append(h)
		else:
			live.append(h)
	if live.is_empty():
		print("  OK    %s — none%s" % [title,
			("  [%d waived]" % waived.size()) if not waived.is_empty() else ""])
	else:
		_fails += 1
		print("  FAIL  %s — %d unwaived" % [title, live.size()])
		for h in live:
			print("          %s:%d  %s()" % [
				String(h.file).get_file(), int(h.line), String(h.name)])
	for w in waived:
		print("          waived: %s()  — %s" % [
			String(w.name), String(waivers[String(w.name)])])


func _run() -> void:
	print("[guards] PASS 2 — guard asymmetry\n")
	var files := [
		"res://scripts/net/CombatNet.gd",
		"res://scripts/scenes/Combat.gd",
		"res://scripts/net/NetMatch.gd",
		"res://scripts/net/SkirmishState.gd",
	]
	var funcs: Array = []
	for p in files:
		funcs.append_array(_functions_in(p))
	print("[guards] %d functions across %d files\n" % [funcs.size(), files.size()])

	# ── A. _remote_state dereferenced with no vs_bot guard ────────────────
	#
	# TWO TIERS, because a null CHECK and a correct null PATH are different things
	# and only the first is mechanically visible. `_net_apply_remote_spell` DID
	# null-check — it checked and then `return`ed, which in a drill silently killed
	# the bot's entire spell half. Meanwhile `_net_caster_draw` null-checks and
	# falls back to an event, which is right. So:
	#   TIER 1 (FAIL)  — dereferenced with no null check and no vs_bot guard: a
	#                    crash waiting for a practice match.
	#   TIER 2 (NOTE)  — null-checked but vs_bot-blind: not a crash, but the null
	#                    path is a BEHAVIOUR decision nobody has stated. Read it.
	print("[guards] --- A: _remote_state without a vs_bot guard ---")
	var a_hits: Array = []
	var a_notes: Array = []
	for fn in funcs:
		var body := _joined(fn)
		if not body.contains("_remote_state."):
			continue
		if body.contains("vs_bot"):
			continue
		if body.contains("_remote_state != null") or body.contains("_remote_state == null"):
			a_notes.append(fn)
		else:
			a_hits.append(fn)
	_emit("functions dereferencing _remote_state UNCHECKED and vs_bot-blind",
		a_hits, WAIVED_REMOTE_STATE)
	if not a_notes.is_empty():
		print("  NOTE  %d null-checked but vs_bot-blind (the null path is a decision):"
			% a_notes.size())
		for h in a_notes:
			print("          %s:%d  %s()" % [
				String(h.file).get_file(), int(h.line), String(h.name)])

	# ── B. turn gate with no sealed branch ────────────────────────────────
	print("\n[guards] --- B: net turn gate with no _is_sealed branch ---")
	var b_hits: Array = []
	for fn in funcs:
		var body := _joined(fn)
		var gates: bool = body.contains("_net_active_index != NetMatch.local_player_index") \
			or body.contains("_net_active_index != _net_my_index()") \
			or body.contains("_net_active_index == NetMatch.local_player_index") \
			or body.contains("_net_active_index == _net_my_index()")
		if not gates:
			continue
		if body.contains("_is_sealed") or body.contains("_sorcery_active"):
			continue
		b_hits.append(fn)
	_emit("functions gating on the net turn index with no sealed branch",
		b_hits, WAIVED_TURN_GATE)

	# ── C. await, then touch a node, with no revalidation anywhere after ──
	#
	# A "single-assignment latch in a multi-exit function" heuristic was tried here
	# first and REMOVED: all six of its hits were false (`death_card_handled` is a
	# local; `_on_card_will_die` sets two DIFFERENT latches on two branches). A check
	# that is 100% noise trains people to ignore the gate, which is worse than no
	# check — so it was replaced by a rule for a trap this project has actually been
	# bitten by three times (`project_bug_audit_20260807`, "await-during-live-button"):
	# a coroutine suspends, the scene or the node it captured is freed while it is
	# parked, and it resumes holding a dangling reference.
	#
	# The rule: a function that AWAITS and then dereferences something, with no
	# revalidation ANYWHERE after that await. Advisory, and sorted by how much work
	# happens after the suspend, because that is where the risk concentrates.
	#
	# IT FOUND ONE REAL BUG and that is the bar it has to clear: `_net_show_order_choice`
	# waited on `while picked[0] < 0` with no timeout, no match-over term and no
	# validity test, while its literal twin `_net_show_order_wait` had all three — so
	# an opponent quitting during the toss left the winner's coroutine dereferencing a
	# freed Combat once a frame, forever.
	#
	# KNOWN IMPRECISION, so nobody reads the tail as a bug list: this counts from the
	# FIRST await to the end of the function regardless of branching, so a function
	# that awaits-and-returns on one path scores every line of the OTHER paths
	# (`_net_play_spell` is the clearest example — its first await is followed
	# immediately by `return`). Treat the ranking as "where to look", never as "what
	# is broken", and confirm by reading before changing anything.
	print("\n[guards] --- C: await with no revalidation after it (advisory) ---")
	var c_hits: Array = []
	for fn in funcs:
		var body_lines: Array = fn.body
		var first_await := -1
		for i in body_lines.size():
			if String(body_lines[i]).contains("await "):
				first_await = i
				break
		if first_await < 0:
			continue
		var after: Array = body_lines.slice(first_await + 1)
		if after.is_empty():
			continue
		var tail := "\n".join(PackedStringArray(after))
		# "Revalidated" means ANY of this project's re-entry idioms, not just the
		# node test: a coroutine that resumes and asks `_net_match_over` /
		# `phase` / `_net_replay_active` has checked that it is still relevant,
		# which is the same protection by a different name. Counting only
		# `is_instance_valid` reported 55 functions, most of them correct — and a
		# list nobody can act on is a list nobody reads.
		if tail.contains("is_instance_valid") or tail.contains("is_queued_for_deletion") \
				or tail.contains("_net_match_over") or tail.contains("phase ==") \
				or tail.contains("phase !=") or tail.contains("_net_replay_active") \
				or tail.contains("== null") or tail.contains("!= null"):
			continue
		# Only care if the tail actually TOUCHES something afterwards.
		if not (tail.contains(".") or tail.contains("_")):
			continue
		c_hits.append({"name": fn.name, "file": fn.file, "line": fn.line,
			"tail": after.size()})
	c_hits.sort_custom(func(a, b): return int(a.tail) > int(b.tail))
	if c_hits.is_empty():
		print("  OK    none")
	else:
		print("  NOTE  %d coroutine(s) resume and touch state without revalidating"
			% c_hits.size())
		print("        (top 12 by lines executed after the suspend)")
		for i in mini(12, c_hits.size()):
			var h: Dictionary = c_hits[i]
			print("          %-4d lines after await   %s:%d  %s()" % [
				int(h.tail), String(h.file).get_file(), int(h.line), String(h.name)])

	print("\n[guards] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
