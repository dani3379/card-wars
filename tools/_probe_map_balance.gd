extends SceneTree
## Throwaway balance probe: generate runs across seeds and count node types
## per act — verifies the fewer-fights / more-musters map-gen change without
## rendering. Run:
##   Godot.exe --headless --path . --script res://tools/_probe_map_balance.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null:
		print("[balance] RunState missing")
		quit(1)
		return true
	var totals: Dictionary = {}
	var acts := 0
	for s in [1, 7, 42, 1337, 20260611]:
		rs.start_new_run("raider", -1, s)
		for act in range(3):
			var counts: Dictionary = {}
			for row in rs.map_data[act]:
				for n in row:
					var t := String(n.type)
					counts[t] = int(counts.get(t, 0)) + 1
					totals[t] = int(totals.get(t, 0)) + 1
			acts += 1
			print("[balance] seed %d act %d: %s" % [s, act + 1, counts])
	print("[balance] totals over %d acts: %s" % [acts, totals])
	quit(0)
	return true
