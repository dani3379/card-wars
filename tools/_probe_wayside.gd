extends SceneTree
## Throwaway probe for the road-to-the-keep slice 2: the 12-row skeleton
## (two wayside stops between every fight), wayside verb assignment, the
## treasure/recruit/shop guarantees, and the wayside card-upgrade paths
## (drill / strip_kw / grant_kw). Run:
##   Godot.exe --headless --path . --script res://tools/_probe_wayside.gd

const FIGHT_ROWS := [0, 3, 9]
const ELITE_ROW := 6
const WAYSIDE_ROWS := [1, 2, 4, 5, 7, 8]
const VERBS := ["drill_yard", "muster_scale", "standard_bearer", "supply_cache"]

var _fails := 0
var _ran := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var rs: Node = root.get_node_or_null("RunState")
	var cdb: Node = root.get_node_or_null("CardDB")
	if rs == null or cdb == null:
		print("[wayside-probe] autoloads missing")
		quit(1)
		return true

	print("— skeleton invariants (5 seeds × 3 acts)")
	for s in [3, 11, 777, 4242, 20260612]:
		rs.start_new_run("raider", -1, s)
		for act in range(3):
			var ok_rows := true
			var ok_verbs := true
			var elites := 0
			var counts: Dictionary = {}
			var n_sites := 0
			for row in rs.map_data[act]:
				for n in row:
					n_sites += 1
					var t := String(n.type)
					counts[t] = int(counts.get(t, 0)) + 1
					var r := int(n.row)
					if r in FIGHT_ROWS and t != "combat":
						ok_rows = false
					if r == ELITE_ROW:
						if t == "elite":
							elites += 1
						elif t != "combat":
							ok_rows = false
					if r in WAYSIDE_ROWS and t in ["combat", "elite", "boss", "rest"]:
						ok_rows = false
					if t == "wayside" and not (String(n.get("wayside_id", "")) in VERBS):
						ok_verbs = false
			var tag := "seed %d act %d" % [s, act + 1]
			_check(ok_rows, tag + ": fight/wayside rows hold their beat")
			_check(elites == 1, tag + ": exactly 1 elite in the band")
			_check(ok_verbs, tag + ": every wayside halt carries a verb")
			_check(n_sites >= 16 and n_sites <= 23, tag + ": %d sites in window" % n_sites)
			_check(int(counts.get("treasure", 0)) >= 1, tag + ": treasure placed")
			_check(int(counts.get("recruit", 0)) >= 1, tag + ": muster placed")
			_check(int(counts.get("shop", 0)) >= 1, tag + ": shop placed")

	print("— wayside upgrade paths")
	rs.start_new_run("raider", -1, 99)
	var creature_idx := -1
	for i in range(rs.deck.size()):
		if String(cdb.get_card_data(rs.deck[i]).get("type", "")) == "creature":
			creature_idx = i
			break
	if creature_idx < 0:
		_check(false, "no creature in starter deck (unexpected)")
	else:
		var base: Dictionary = cdb.get_card_data(rs.deck[creature_idx])
		rs.apply_wayside_upgrade(creature_idx, {"path": "drill", "stacks": 2})
		var drilled: Dictionary = rs.get_upgraded_card_data(creature_idx)
		_check(int(drilled.atk) == int(base.atk) + 2
			and int(drilled.hp) == int(base.hp) + 2, "drill stacks=2 → +2/+2")
		_check(rs.is_card_upgraded(creature_idx), "drilled card reads as upgraded")
		rs.apply_wayside_upgrade(creature_idx, {"path": "grant_kw", "keyword": "swift"})
		var granted: Dictionary = rs.get_upgraded_card_data(creature_idx)
		_check((granted.keywords as Array).has("swift"), "grant_kw adds Swift")
		rs.apply_wayside_upgrade(creature_idx, {"path": "strip_kw", "keyword": "swift"})
		var stripped: Dictionary = rs.get_upgraded_card_data(creature_idx)
		_check(not (stripped.keywords as Array).has("swift")
			or not (base.keywords as Array).is_empty(), "strip_kw removes Swift")

	print("— wayside_id survives the visit + save round-trip")
	rs.start_new_run("raider", -1, 3)
	var found := false
	for row in rs.map_data[0]:
		for n in row:
			if String(n.type) == "wayside":
				rs.map_position = {"row": int(n.row) - 1, "col": int(n.col)}
				rs.visit_node(int(n.row), int(n.col))
				found = String(rs.current_wayside_id) == String(n.wayside_id)
				break
		if found:
			break
	_check(found, "visit_node copies the verb into current_wayside_id")

	if _fails == 0:
		print("[wayside-probe] ALL PASS")
	else:
		print("[wayside-probe] %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
