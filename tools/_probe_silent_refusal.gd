extends SceneTree
## _probe_silent_refusal.gd — PASS 18 of docs/BUG_SWEEP_METHOD_20260829.md (class C18).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_silent_refusal.gd
##
## THE SILENT REFUSAL — the defect class that is correct code and a bug anyway.
##
## Every pass before this one asks whether the game does the right thing. This one
## asks whether the player can TELL. When a control declines an action and says
## nothing — no message, no sound, no recoil — the game is behaving exactly as
## designed and the player is looking at a dead button. There is no state to assert
## against, which is why nothing in the suite has caught one; and yet the two worst
## skirmish bugs this session were both this exact shape:
##
##   · Sealed Orders refused every creature with the hand still lifted and
##     draggable, so the refusal read as a broken drop rather than a rule.
##   · `_use_combat_potion` answered a sealed-phase click with a bare `return` —
##     a button that visibly did nothing at all.
##
## THE TECHNIQUE IS FEEDBACK ASYMMETRY, and it is deliberately not "find every bare
## return". A blanket scan of early returns is nearly all false positives (most
## guards are internal and unreachable by a click), and this session has already
## deleted three checks for crying wolf. Instead: consider only functions that
## demonstrably KNOW HOW TO SPEAK — an input handler containing at least one
## refusal that does tell the player. Such a function has established that its
## refusals are player-visible events. A sibling branch in the SAME function that
## refuses in silence is then an inconsistency the author can adjudicate, in the
## same way `_probe_guard_audit` reads a predicate applied in one sibling and
## forgotten in another.
##
## Output is a REPORT, not a hard failure: whether a given branch is reachable by a
## click is a judgement call, and a gate that fails on judgement calls gets ignored.
## The COUNT is the signal, and the waiver list below records the ones adjudicated.

## Calls that constitute telling the player something happened.
const SPEAKS := [
	"_refuse_play", "_show_info", "show_info", "_flash", "play_sfx",
	"spawn_keyword_callout", "_log_event", "log_status", "_toast", "_show_notice",
	"screen_shake", "add_trauma", "_strike_command_seal", "_pulse", "_bounce",
	"play_return_to_hand", "_shake", "_deny", "_set_phase_caption", "_win_flourish",
	"_bust_feedback", "_show_message", "_notice", "_cancel_potion_targeting",
	"_clear_targeting", "_hint", "_warn",
]

## Names that mark a function as reachable by a click, drag or keypress.
const INPUT_HINTS := [
	"_on_", "_pressed", "_clicked", "_gui_input", "_toggled", "_use_", "_try_",
	"_play_card", "_confirm", "_select", "_pick", "_buy", "_sell", "_forge",
	"_toggle_", "_drop", "_drag",
]

## Adjudicated 2026-08-31: a silent branch matching one of these is CORRECT and is
## not re-reported. Keyed `function::needle-from-the-guard` so a waiver cannot
## silently spread to a different call site that happens to share a variable name.
## An entry is visible debt, not absolution — each records WHY it is not a defect.
const WAIVERS := {
	# RE-ENTRANCY LATCHES. The second call is the same action; the first already
	# answered it, and speaking twice would double the feedback.
	"_net_on_peer_lost::_net_peer_lost_handled": "latch — already handled once",
	"_on_save_deck::_local_finished": "latch — the deck is already committed",
	"_on_node_pressed::_marching": "latch — a march is already under way",
	# UNREACHABLE BY A CLICK. The control that would trigger these is disabled, or
	# the event is consumed upstream.
	"_on_node_pressed::not ok": "the button for an unavailable site is disabled",
	"_on_end_turn::phase != Phase.PLAYER_TURN":
		"the end-turn button is disabled at every phase transition (8 sites)",
	"_on_card_dismiss_requested::_targeting_spell != null":
		"Combat._input consumes right-click to cancel targeting first",
	# INTERNAL GUARDS, not player-facing refusals: bounds, null, wrong-collection.
	"_use_combat_potion::index >= belt.size()": "bounds guard, not a refusal",
	"_try_resolve_potion_target::_targeting_potion_idx < 0": "internal state guard",
	"_on_card_dismiss_requested::not _hand.has(card)":
		"battlefield card, not a hand card — nothing was refused",
	"_on_field_step::_field_root == null": "internal null guard",
	# A MISS IS NOT A REFUSAL. Clicking empty space while targeting keeps the mode
	# open, and the prompt in the info label is still on screen saying so. The
	# spell path does exactly the same on a miss, so this is house behaviour.
	"_try_resolve_potion_target::target == null":
		"a miss keeps targeting open — same as the spell path",
	# ANIMATION LATCHES. A minigame prop mid-tumble is not ignoring the click; the
	# animation the player is watching IS the answer, and a refusal message over a
	# rolling die would be noise.
	"_on_dice_roll::_dice_busy": "the bones are still tumbling — the roll is the answer",
	"_on_sack_draw::_sack_busy": "a chit is still being drawn",
	"_on_field_step::_field_busy": "the step is still resolving",
	"_on_crown_cast::_cap_busy": "the dice are still cast",
	# UNREACHABLE TODAY, AND A TRAP IF THAT CHANGES. PotionDB currently defines no
	# `usable_in: "map"` potion, so this guard cannot fire — but the combat belt
	# draws whatever the slot holds WITHOUT filtering on `usable_in`, so the first
	# map-only potion added would render a lit, clickable, completely dead slot.
	# Filter the bar when that day comes; do not just delete this line.
	"_use_combat_potion::usable_in": "no map-only potion exists yet (see note)",
}

var _started := false
var _done := false
var _hits: Array = []
var _scanned := 0
var _speaking := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _looks_like_input(fname: String) -> bool:
	for h in INPUT_HINTS:
		if fname.findn(h) >= 0:
			return true
	return false


func _speaks(line: String) -> bool:
	for s in SPEAKS:
		if line.find(s) >= 0:
			return true
	return false


## Does the branch BODY (everything after its opening `if`) invoke anything? The
## guard line itself is skipped — `if not _hand.has(card):` is a test, not an act.
func _branch_calls_something(block: String) -> bool:
	var call_re := RegEx.new()
	call_re.compile("[A-Za-z_][A-Za-z0-9_.]*\\s*\\(")
	var seen_guard := false
	for raw in block.split("\n"):
		var s := raw.strip_edges()
		if not seen_guard:
			if s.begins_with("if ") or s.begins_with("elif "):
				seen_guard = true
			continue
		if s == "" or s.begins_with("#"):
			continue
		if s.begins_with("return"):
			continue
		if call_re.search(s) != null:
			return true
	return false


func _waived(fname: String, block: String) -> String:
	for w in WAIVERS:
		var parts: PackedStringArray = String(w).split("::")
		if parts.size() != 2:
			continue
		if parts[0] == fname and block.find(parts[1]) >= 0:
			return WAIVERS[w]
	return ""


func _indent_of(line: String) -> int:
	var n := 0
	for i in line.length():
		if line[i] == "\t":
			n += 1
		else:
			break
	return n


## Split a file into (name, start_line, lines[]) per function.
func _functions(src: String) -> Array:
	var out: Array = []
	var lines := src.split("\n")
	var cur_name := ""
	var cur_start := 0
	var cur: Array = []
	for i in lines.size():
		var ln: String = lines[i]
		if ln.begins_with("func ") or ln.begins_with("static func "):
			if cur_name != "":
				out.append({"name": cur_name, "start": cur_start, "lines": cur})
			var head := ln.substr(ln.find("func ") + 5)
			cur_name = head.split("(")[0].strip_edges()
			cur_start = i + 1
			cur = []
		elif cur_name != "":
			cur.append({"n": i + 1, "t": ln})
	if cur_name != "":
		out.append({"name": cur_name, "start": cur_start, "lines": cur})
	return out


## Within one function, find every guarded `return` and decide whether the branch
## it belongs to says anything to the player.
##
## A branch is the run of lines from its `if` down to (and including) the return,
## at an indent deeper than the `if`. Reading the whole branch — not just the line
## before the return — is what stops a multi-line refusal from being misread as a
## silent one.
func _scan_function(f: Dictionary, path: String) -> void:
	var lines: Array = f["lines"]
	var guarded: Array = []       # {line, block_text}
	var spoke_somewhere := false
	for i in lines.size():
		var t: String = lines[i]["t"]
		var stripped := t.strip_edges()
		if not (stripped == "return" or stripped.begins_with("return\t")
				or stripped.begins_with("return #")):
			continue
		var ind := _indent_of(t)
		if ind <= 1:
			continue                 # top-level return: the function's normal end
		# Walk back to the `if` that opens this branch.
		var block := ""
		var j := i
		while j >= 0:
			var lt: String = lines[j]["t"]
			block = lt + "\n" + block
			if _indent_of(lt) < ind and lt.strip_edges().begins_with("if "):
				break
			if _indent_of(lt) < ind - 1:
				break
			j -= 1
		if _speaks(block):
			spoke_somewhere = true
			continue
		# A BRANCH THAT CALLS SOMETHING IS NOT A SILENT REFUSAL. The first version
		# of this rule flagged any guarded return, which swept in two shapes that
		# are not refusals at all: a DISPATCH (`if _is_net(): _net_on_done_placing()
		# return` — the turn was taken, just elsewhere) and a refusal whose feedback
		# is a call this list had not learned yet (`_cancel_targeting`,
		# `_return_card_to_slot` — the targeting visibly ends, the card visibly
		# snaps back). Both are the game DOING something, which is the opposite of
		# the defect. Require the branch body to be inert: a guard, then `return`.
		if _branch_calls_something(block):
			continue
		guarded.append({"line": lines[i]["n"], "block": block})
	# THE ASYMMETRY RULE. Only report a silent branch in a function that has
	# already proved its refusals are things the player hears about.
	if not spoke_somewhere:
		return
	_speaking += 1
	for g in guarded:
		var why := _waived(String(f["name"]), g["block"])
		if why != "":
			continue
		var head := ""
		for raw in String(g["block"]).split("\n"):
			var s := raw.strip_edges()
			if s.begins_with("if "):
				head = s
				break
		_hits.append({"file": path, "line": g["line"], "func": f["name"],
			"guard": head})


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(dir.path_join(name), out)
		elif name.ends_with(".gd"):
			out.append(dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()


func _run() -> void:
	print("[silent] PASS 18 — refusals the player cannot see\n")
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
			if not _looks_like_input(String(f["name"])):
				continue
			_scanned += 1
			_scan_function(f, path)

	print("[silent] scanned %d input-shaped functions; %d of them speak on refusal"
		% [_scanned, _speaking])
	print("[silent] %d silent sibling branch(es)\n" % _hits.size())
	var by_file := {}
	for h in _hits:
		by_file.get_or_add(h["file"], []).append(h)
	for fpath in by_file:
		print("  %s" % String(fpath).replace("res://", ""))
		for h in by_file[fpath]:
			print("     %5d  %s()   %s" % [h["line"], h["func"],
				String(h["guard"]).substr(0, 92)])
	print("\n[silent] report only — reachability by a click is a judgement call, and "
		+ "a gate that\n[silent] fails on judgement calls gets ignored. The COUNT is "
		+ "the signal; adjudicate\n[silent] each one and either fix it or waive it "
		+ "with its reason.")
	_done = true
	quit(0)
