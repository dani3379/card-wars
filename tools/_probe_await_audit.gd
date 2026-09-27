extends SceneTree
## _probe_await_audit.gd — PASS 19 of docs/BUG_SWEEP_METHOD_20260829.md (class C19).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_await_audit.gd
##
## THE SUSPENDED-FUNCTION HAZARD — use-after-free across an `await`.
##
## GDScript's `await` suspends a function mid-body and lets the rest of the game run.
## Every node reference the function was holding is a reference to something that may
## be GONE when it resumes: a creature can die, a card can be discarded, a screen can
## change, a peer can drop. Touching one after the resume is a use-after-free, and in
## Godot it does not crash loudly — a freed-object property read returns null and
## then **a null write silently ABORTS the whole function**, so the visible symptom
## is an animation that stops halfway with no error printed. That is why this class
## survives: it produces missing beats, not stack traces.
##
## There are 594 `await`s under `scripts/`, so this cannot be an eyeball pass. Nothing
## in the suite enumerates them: `_probe_interruption` (C11) EXERCISES a handful of
## interruption points dynamically, which proves those specific ones and says nothing
## about the other five hundred. This is the exhaustive static complement.
##
## THE RULE: for each function containing `await`, take every local node-typed
## variable and parameter; if it is DEREFERENCED after an `await` with no
## `is_instance_valid` / null check on that same variable in between, report it.
##
## FALSE-POSITIVE CONTROL is most of the work here, because a noisy static gate gets
## ignored (this session has already deleted three checks for crying wolf):
##   · only variables that are demonstrably nodes — a declared Node/Control/Card2D
##     type, or assigned from instantiate()/new()/get_node()/a known node-returning
##     helper. An untyped `var x = 3` is not a use-after-free candidate.
##   · a guard ANYWHERE between the await and the use clears it, including a guard
##     on an enclosing `if` and an early `return`.
##   · `await` on something derived from the variable itself (`await x.play()`) is
##     not a hazard for x at that point — x was alive when the call was made.
##   · self/member variables are excluded. They are a real hazard too, but they are
##     everywhere and the signal-to-noise is far worse; locals are where the
##     mechanical answer is unambiguous.
##
## Report, not hard failure: whether a given node can actually die during a given
## await is a judgement call. The COUNT is the signal and WAIVERS record the calls.

const NODE_TYPES := ["Node", "Control", "Card2D", "Button", "Label", "Panel",
	"PanelContainer", "TextureRect", "ColorRect", "VBoxContainer", "HBoxContainer",
	"CanvasLayer", "Sprite2D", "Line2D", "RichTextLabel", "ScrollContainer",
	"CenterContainer", "MarginContainer", "GridContainer", "TextureButton",
	"AnimatedSprite2D", "CPUParticles2D", "Timer", "Node2D"]

## Right-hand sides that produce a node.
const NODE_SOURCES := ["instantiate()", ".new()", "get_node(", "get_node_or_null(",
	"find_child(", "get_parent()", "get_child(", "duplicate()"]

## Adjudicated 2026-08-31: not a hazard. Keyed `function::variable`.
##
## The recurring reason is GUARD-BY-OWNER: the code validates the container the
## node hangs off rather than the node itself. That is sound — a live parent means
## a live child — and inferring the ownership statically is not reliable enough to
## automate, so these are adjudicated by hand instead of guessed at.
## ── THE DEFERRED-BAKED-RULES FAMILY (adjudicated 2026-09-20) ────────────────
##
## Seven of the entries below are ONE shape, which is why they are adjudicated
## together: a picker/preview hydrator instantiates a Card2D, parents it to a
## wrapper, awaits `RenderingServer.frame_post_draw`, and then calls
## `card_node.complete_deferred_baked_rules()`. Every one of them re-checks its
## OWNER after the suspension before touching the leaf —
## `_event_ui_build_is_current(build_gen, wrapper)` in Event, `picker_alive` in
## MainMenu/Rest, `still_here` in Rest/Reward — so a live owner means a live
## child. All seven were read line by line; none is missing the guard, which is
## the thing that made them worth checking as a family rather than singly.
##
## They are waived rather than left to accumulate because this gate's contract
## is that THE COUNT IS THE SIGNAL. Eight unadjudicated hits sitting in the
## report permanently is how the next REAL one arrives already camouflaged.
const WAIVERS := {
	"_run_shell_shuffle::pw":
		"guarded by owner — `_shell_root` is validated after the same await",
	"_sp_show_despatch::scrim":
		"awaits a button press on a modal; if the scene died the press never comes",
	"_sp_show_despatch::holder":
		"awaits a button press on a modal; if the scene died the press never comes",
	"show_deck_picker::btn":
		"guarded by owner — `is_instance_valid(layer)` is re-checked after both "
		+ "awaits, and every `picker_buttons` entry hangs off that layer",
	"_hydrate_staged_card::card_node":
		"guarded by owner — `_event_ui_build_is_current(build_gen, wrapper)`",
	"_drain_card_grid::card_node":
		"guarded by owner — `_event_ui_build_is_current(build_gen, grid)`",
	"_refresh_pick_tile::card_node":
		"guarded by owner — `_event_ui_build_is_current(build_gen, tile)` plus "
		+ "an identity re-check that the tile is still `_last_pick_tile`",
	"_hydrate_stranger_hand_cards::card_node":
		"guarded by owner — `_event_ui_build_is_current(build_gen, wrapper)`",
	"_hydrate_blessing_card_group::card_node":
		"guarded by owner — `picker_alive` is re-checked after every await",
	"_hydrate_forge_card_group::card_node":
		"guarded by owner — `picker_alive` is re-checked after every await",
	"_hydrate_forge_preview_pair::card_node":
		"guarded by owner — `still_here` is re-checked after every await",
	"_show_forge_confirm::card_node":
		"guarded by owner — `still_here` is re-checked after every await",
	"_show_forge_confirm::dim":
		"the scrim IS the owner here: `still_here` is checked first and the "
		+ "queue_free only runs on the branch that found the screen alive",
	"_show_forged_card::wrapper":
		"guarded by owner — `preview_alive` checks `is_instance_valid(dim)` and "
		+ "the wrapper is a child of that scrim",
}

var _started := false
var _done := false
var _hits: Array = []
var _funcs_with_await := 0
var _vars_tracked := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _indent_of(line: String) -> int:
	var n := 0
	for i in line.length():
		if line[i] == "\t":
			n += 1
		else:
			break
	return n


func _functions(src: String) -> Array:
	var out: Array = []
	var lines := src.split("\n")
	var cur := {}
	for i in lines.size():
		var ln: String = lines[i]
		if ln.begins_with("func ") or ln.begins_with("static func "):
			if not cur.is_empty():
				out.append(cur)
			var head := ln.substr(ln.find("func ") + 5)
			cur = {"name": head.split("(")[0].strip_edges(), "sig": ln, "lines": []}
		elif not cur.is_empty():
			cur["lines"].append({"n": i + 1, "t": ln})
	if not cur.is_empty():
		out.append(cur)
	return out


## Node-typed parameters from the signature, e.g. `func f(card: Control, n: int)`.
func _node_params(sig: String) -> Array:
	var out: Array = []
	var open := sig.find("(")
	var close := sig.rfind(")")
	if open < 0 or close <= open:
		return out
	for part in sig.substr(open + 1, close - open - 1).split(","):
		var p := String(part).strip_edges()
		if p.find(":") < 0:
			continue
		var nm := p.split(":")[0].strip_edges()
		var ty := p.split(":")[1].split("=")[0].strip_edges()
		if ty in NODE_TYPES:
			out.append(nm)
	return out


## Node-typed locals declared in the body.
func _node_locals(lines: Array) -> Dictionary:
	var out := {}
	var decl := RegEx.new()
	decl.compile("^\\s*var\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(:\\s*([A-Za-z0-9_]+))?\\s*[:=]")
	for e in lines:
		var t: String = e["t"]
		var m := decl.search(t)
		if m == null:
			continue
		var name := m.get_string(1)
		var ty := m.get_string(3)
		var is_node := ty in NODE_TYPES
		if not is_node:
			for src in NODE_SOURCES:
				if t.find(src) >= 0:
					is_node = true
					break
		if is_node:
			out[name] = int(e["n"])
	return out


## Is `v` guarded on this line? Any validity or null test counts.
func _guards(line: String, v: String) -> bool:
	for pat in ["is_instance_valid(%s)" % v, "%s == null" % v, "%s != null" % v,
			"not %s" % v, "%s and " % v, "%s != null and" % v]:
		if line.find(pat) >= 0:
			return true
	# `if not is_instance_valid(x) ... return` and friends all contain the call.
	return false


## Does this line dereference `v` — read a property or call a method on it?
func _derefs(line: String, v: String) -> bool:
	var re := RegEx.new()
	re.compile("(^|[^A-Za-z0-9_.])" + v + "\\s*\\.")
	return re.search(line) != null


func _scan(f: Dictionary, path: String) -> void:
	var lines: Array = f["lines"]
	var has_await := false
	for e in lines:
		if String(e["t"]).find("await ") >= 0:
			has_await = true
			break
	if not has_await:
		return
	_funcs_with_await += 1

	var candidates := _node_locals(lines)
	for p in _node_params(String(f["sig"])):
		candidates[p] = 0
	if candidates.is_empty():
		return
	_vars_tracked += candidates.size()

	for v in candidates:
		var decl_line: int = int(candidates[v])
		var awaited_at := -1
		var await_indent := 0
		var open_parens := 0          # >0 while a multi-line statement is still open
		var guarded_since := false
		var loop_var := ""
		var loop_names := ""
		for e in lines:
			var t: String = e["t"]
			var n: int = int(e["n"])
			if n < decl_line:
				continue
			# A MULTI-LINE `await` IS ONE STATEMENT. Its argument list is evaluated
			# BEFORE the suspension, so a mention of the variable on a continuation
			# line is a pre-await use, not a post-resume one. Missing this reported
			# `_ordered_strike` — which guards correctly with `is_instance_valid`
			# on the very next line — as a hazard.
			var was_open := open_parens > 0
			open_parens += t.count("(") - t.count(")")
			if open_parens < 0:
				open_parens = 0
			if was_open:
				continue
			# CONTROL FLOW. An `await` nested inside a branch does not necessarily
			# run before code at a shallower indent — that code may be reached by a
			# path that skipped the await entirely, or after the branch `return`ed.
			# `_sniper_fire` was flagged exactly this way: its await sits in an
			# `if` that returns immediately after. Dropping the await when the
			# indent falls below it is deliberately conservative and costs some
			# true positives; a gate with false positives gets ignored, and one
			# that reports only what it can prove gets acted on.
			if awaited_at > 0 and _indent_of(t) < await_indent \
					and t.strip_edges() != "":
				awaited_at = -1
				guarded_since = false
			# Re-assignment gives a fresh, live reference — the clock restarts.
			var reassign := RegEx.new()
			reassign.compile("^\\s*(var\\s+)?" + v + "\\s*=[^=]")
			if reassign.search(t) != null:
				awaited_at = -1
				guarded_since = false
				continue
			if t.find("await ") >= 0:
				# `await v.something()` proves v was alive at the call; the hazard
				# starts only for uses AFTER the resume, which the next lines cover.
				awaited_at = n
				await_indent = _indent_of(t)
				guarded_since = false
				continue
			# GUARD-BY-LOOP: `for c in [title, subtitle, row]:` followed by a
			# validity test on `c` guards every name in that list. `Rest.gd`
			# validates all three of its layout nodes this way, and reading only
			# for `is_instance_valid(title)` reported a correctly-guarded function
			# as a hazard twice.
			var loop := RegEx.new()
			loop.compile("for\\s+([A-Za-z_][A-Za-z0-9_]*)\\s+in\\s+\\[([^\\]]*)\\]")
			var lm := loop.search(t)
			if lm != null and (", " + lm.get_string(2) + ",").find(v) >= 0:
				loop_var = lm.get_string(1)
				loop_names = lm.get_string(2)
			if loop_var != "" and _guards(t, loop_var) \
					and (loop_names + ",").find(v) >= 0:
				guarded_since = true
				continue
			if _guards(t, v):
				guarded_since = true
				continue
			if awaited_at > 0 and not guarded_since and _derefs(t, v):
				var key := "%s::%s" % [String(f["name"]), v]
				if not WAIVERS.has(key):
					_hits.append({"file": path, "func": f["name"], "var": v,
						"await_line": awaited_at, "use_line": n,
						"code": t.strip_edges()})
				# One report per variable per function is enough to act on.
				break


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var nm := d.get_next()
	while nm != "":
		if d.current_is_dir():
			if not nm.begins_with("."):
				_walk(dir.path_join(nm), out)
		elif nm.ends_with(".gd"):
			out.append(dir.path_join(nm))
		nm = d.get_next()
	d.list_dir_end()


func _run() -> void:
	print("[await] PASS 19 — node references used after a suspension\n")
	var files: Array = []
	_walk("res://scripts", files)
	files.sort()
	for path in files:
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			continue
		var src := fa.get_as_text()
		fa.close()
		for f in _functions(src):
			_scan(f, path)

	print("[await] %d functions contain an await; %d node-typed locals/params tracked"
		% [_funcs_with_await, _vars_tracked])
	print("[await] %d unguarded use(s) after a suspension\n" % _hits.size())
	var by_file := {}
	for h in _hits:
		by_file.get_or_add(h["file"], []).append(h)
	for fpath in by_file:
		print("  %s" % String(fpath).replace("res://", ""))
		for h in by_file[fpath]:
			# `  HIT  ` prefix so run_mutation_check.sh can tell a report-only pass
			# that FOUND something from one that did not — without it, injecting a
			# fault here would look identical to a clean run.
			print("  HIT  await L%-6d use L%-6d %s(): `%s` — %s" % [
				h["await_line"], h["use_line"], h["func"], h["var"],
				String(h["code"]).substr(0, 74)])
	print("\n[await] report only. A hit is a hazard, not proof: the node may be one "
		+ "the await\n[await] cannot outlive. Adjudicate each — guard it, or waive it "
		+ "with the reason.")
	_done = true
	quit(0)
