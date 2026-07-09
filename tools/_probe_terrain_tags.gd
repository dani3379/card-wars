extends SceneTree
## Throwaway probe: the war-table coast is generated around the node field —
## verify _derive_terrain_tags still deals varied ground (woods/pass/ash, not
## wall-to-wall meadow) over that landmass, across seeds and acts. Headless:
## build_map() is synchronous; the bake chain is never started (bake_mode is
## non-empty). NOTE: --script files compile before autoloads register, so
## RunState is fetched from the tree, never referenced by identifier.
##   Godot.exe --headless --path . --script res://tools/_probe_terrain_tags.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null:
		print("[terrain] RunState missing")
		quit(1)
		return true
	var fails := 0
	for seed_v in [3, 11, 908]:
		rs.start_new_run("raider", -1, seed_v)
		for act in range(1, 4):
			# NOT added to the tree: _ready would schedule a SECOND build_map
			# next frame (against a different act after advance_act below).
			var map: Control = (load("res://scripts/scenes/MapTerrain.gd")
				as GDScript).new()
			map.set("bake_mode", "probe")   # build only, no bake chain
			map.size = Vector2(1600, 900)
			map.call("build_map")
			var counts: Dictionary = {}
			var bridges := 0
			for row in rs.get_current_act_map():
				for nd in row:
					var t := String(nd.get("terrain", ""))
					counts[t] = int(counts.get(t, 0)) + 1
					if bool(nd.get("bridge", false)):
						bridges += 1
			print("[terrain] seed %d act %d: %s bridges=%d" % [
				seed_v, act, counts, bridges])
			if counts.size() < 2:
				print("  FAIL  single-ground act (all %s)" % str(counts.keys()))
				fails += 1
			if counts.has(""):
				print("  FAIL  untagged nodes remain")
				fails += 1
			map.free()
			rs.map_plate_cache.clear()
			if act < 3:
				rs.advance_act()
	print("[terrain-probe] %s" % ("ALL PASS" if fails == 0 else
		"%d FAILURES" % fails))
	quit()
	return true
