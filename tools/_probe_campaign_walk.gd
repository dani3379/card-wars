extends SceneTree
## _probe_campaign_walk.gd — PASS 3 of docs/BUG_SWEEP_METHOD_20260829.md (C5 + C7).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_campaign_walk.gd
##
## `_probe_autorun` soaks COMBAT across all 56 encounters. Nothing soaks the RUN —
## the map itself, the routing from a node to its screen, and the invariant that a
## generated act can actually be walked from camp to keep. Those are different
## failure modes: a combat bug loses a fight, a routing bug loses the RUN.
##
## THE TWIN THIS EXISTS FOR. `MapView._scene_for_node_type` has a sibling in
## `MainMenu` (the resume-a-saved-run path), and MapView's own comment records that
## they have diverged before with exactly the consequence you would expect —
## "reliquary" was routed in one and not the other, so resuming onto a Reliquary
## dead-stopped. The comment asks the next person to remember; this asserts it.
##
## Three things are checked, cheapest first:
##   A. The two routing tables cover the SAME node types.
##   B. Every node type the generator actually EMITS is routed by both — a type
##      the tables have never heard of is a dead stop the moment it is generated.
##   C. Every generated act is WALKABLE: camp to boss, every step routable, with
##      RunState surviving each visit.

const MAPVIEW := "res://scripts/scenes/MapView.gd"
const MAINMENU := "res://scripts/scenes/MainMenu.gd"
const SEEDS := 40          # acts are reseeded until accepted, so sample widely

var RS: Node
var _started := false
var _done := false
var _fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


## Pull the node-type string literals out of a `match ntype:` style routing block.
## Both tables are plain `match` blocks over string literals, so this is exact —
## and reading SOURCE is the point: the whole bug class is one table being edited
## and the other not.
func _routed_types(path: String, anchor: String, span: int) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var lines := f.get_as_text().split("\n")
	f.close()
	var out := {}
	var start := -1
	for i in lines.size():
		if String(lines[i]).contains(anchor):
			start = i
			break
	if start < 0:
		return {}
	var lit := RegEx.create_from_string('"([a-z_]+)"')
	for i in range(start, mini(start + span, lines.size())):
		var line: String = lines[i]
		if not line.contains("_SCENE"):
			continue                       # only the routing arms, not prose
		for m in lit.search_all(line):
			out[m.get_string(1)] = true
	return out


func _run() -> void:
	print("[walk] PASS 3 — campaign structure\n")
	RS = root.get_node_or_null("RunState")
	if RS == null:
		print("[walk] FATAL: RunState missing"); _done = true; quit(1); return

	# ── A. the two routing tables ─────────────────────────────────────────
	print("[walk] --- A: the routing twins ---")
	var mv := _routed_types(MAPVIEW, "func _scene_for_node_type", 20)
	var mm := _routed_types(MAINMENU, "var target := MAP_SCENE", 20)
	print("        MapView routes  : %s" % str(mv.keys()))
	print("        MainMenu routes : %s" % str(mm.keys()))
	_check(not mv.is_empty(), "MapView's routing table was found")
	_check(not mm.is_empty(), "MainMenu's resume routing table was found")
	var only_mv: Array = []
	var only_mm: Array = []
	for k in mv:
		if not mm.has(k):
			only_mv.append(k)
	for k in mm:
		if not mv.has(k):
			only_mm.append(k)
	_check(only_mv.is_empty(),
		"no node type is routed on the map but NOT on resume %s" % str(only_mv))
	_check(only_mm.is_empty(),
		"no node type is routed on resume but NOT on the map %s" % str(only_mm))

	# ── B. every type the generator emits is routed ───────────────────────
	print("\n[walk] --- B: generated node types vs the tables ---")
	# ADVANCE VIA THE REAL API. Assigning `current_act_idx` directly is a recorded
	# probe trap (project_overwhelm_audit_20260726): it leaves `map_position` on the
	# previous act's coordinates and skips every reset `advance_act()` performs, so
	# the next act reads as one step long. The first cut of this file did exactly
	# that and produced "never reached the boss in 1 steps" for acts 1 and 2.
	var seen_types := {}
	var acts_built := 0
	for s in SEEDS:
		RS.start_new_run("stalwart", 0, 90210 + s * 7717)
		for act in 3:
			if act > 0:
				RS.advance_act()
			var m: Array = RS.get_current_act_map()
			if m.is_empty():
				continue
			acts_built += 1
			for row in m:
				for nd in row:
					if nd is Dictionary:
						var t := String((nd as Dictionary).get("type", ""))
						if t != "":
							seen_types[t] = true
	print("        %d acts sampled; types emitted: %s" % [acts_built, str(seen_types.keys())])
	_check(acts_built > 0, "the generator produced acts to sample")
	var unrouted_mv: Array = []
	var unrouted_mm: Array = []
	for t in seen_types:
		if t == "camp":
			continue          # the start marker is never travelled to
		if not mv.has(t):
			unrouted_mv.append(t)
		if not mm.has(t):
			unrouted_mm.append(t)
	_check(unrouted_mv.is_empty(),
		"every generated node type has a MAP route %s" % str(unrouted_mv))
	_check(unrouted_mm.is_empty(),
		"every generated node type has a RESUME route %s" % str(unrouted_mm))

	# ── C. every act is walkable camp → boss ──────────────────────────────
	print("\n[walk] --- C: walkability ---")
	var walked := 0
	var stuck: Array = []
	var visits := 0
	# THE KEEP'S ROAD ONLY OPENS ONCE HOLDS HAVE FALLEN — `is_lord_gate_open()`
	# wants `holds_broken_in_act >= HOLDS_TO_OPEN_LORD`, and a walk that never
	# FIGHTS never opens it. That is not a softlock in the game (the generator's
	# acceptance loop guarantees every route carries enough fights, and the code
	# says so); it is the harness failing to simulate a victory. Count a hold as
	# broken on every combat/elite entered, which is what winning one does.
	for s in 12:
		RS.start_new_run("raider", 0, 5150 + s * 104729)
		for act in 3:
			if act > 0:
				RS.advance_act()
			if RS.get_current_act_map().is_empty():
				continue
			var guard := 0
			var reached_boss := false
			while guard < 60:
				guard += 1
				var avail: Array = RS.get_available_nodes()
				if avail.is_empty():
					break
				var pick = avail[0]
				var r := int(pick.get("row", -1))
				var c := int(pick.get("col", -1))
				if r < 0 or c < 0:
					break
				RS.visit_node(r, c)
				visits += 1
				var nt := String(RS.current_node_type)
				if nt != "" and nt != "camp" and not mv.has(nt):
					stuck.append("act %d seed %d: node type '%s' has no route"
						% [act, s, nt])
				if nt in ["combat", "elite"]:
					RS.holds_broken_in_act += 1     # the fight was won
				if nt == "boss":
					reached_boss = true
					break
			if reached_boss:
				walked += 1
			else:
				stuck.append("act %d seed %d: stalled after %d steps at row %d (gate %s)"
					% [act, s, guard, int(RS.map_position.get("row", -1)),
						"open" if RS.is_lord_gate_open() else "shut"])
	print("        walked %d acts to the boss over %d node visits" % [walked, visits])
	_check(visits > 0, "the walk actually visited nodes")
	_check(stuck.is_empty(), "every sampled act walks camp → boss with every step routable")
	for s2 in stuck.slice(0, 10):
		print("          %s" % s2)

	print("\n[walk] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
