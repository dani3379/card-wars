extends SceneTree
## What the player ACTUALLY reads on an enemy body, and how many bodies can
## land in one round. The earlier count of `kw` alone was the wrong metric:
## on_enter / on_death / adj_buff / passive / wither / doom all render as rider
## marks too, and none of them live in `kw`.
##
##   Godot.exe --headless --path . --script res://tools/_probe_enemy_load.gd

var _started := false
var _done := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _riders(e: Dictionary) -> int:
	var n: int = (e.get("kw", []) as Array).size()
	for key in ["on_enter", "on_death", "on_play", "adj_buff", "type_buff", "passive"]:
		if e.has(key):
			n += 1
	if e.has("wither"):
		n += 1
	return n


func _run() -> void:
	var EDB = root.get_node_or_null("EncounterDB")
	if EDB == null:
		print("FATAL")
		_done = true
		quit(1)
		return

	var hist := {}
	var worst: Array = []
	var total := 0
	var sum := 0
	var per_act := {1: [0, 0], 2: [0, 0], 3: [0, 0]}
	for eid in EDB.ENCOUNTERS.keys():
		var enc: Dictionary = EDB.ENCOUNTERS[eid]
		var act := int(enc.get("act", 1))
		var pools: Array = []
		pools.append(enc.get("deck", []))
		if enc.has("reinforcement"):
			pools.append([enc["reinforcement"]])
		for pool in pools:
			for e in pool:
				if not (e is Dictionary):
					continue
				var n := _riders(e)
				total += 1
				sum += n
				hist[n] = int(hist.get(n, 0)) + 1
				if per_act.has(act):
					per_act[act][0] += 1
					per_act[act][1] += n
				if n >= 3:
					var kws: Array = e.get("kw", [])
					var extra: Array[String] = []
					for key in ["on_enter", "on_death", "on_play", "adj_buff",
							"type_buff", "passive", "wither"]:
						if e.has(key):
							extra.append(key)
					worst.append("%s / %s  = %d  kw%s + %s" % [
						eid, String(e.get("name", "?")), n, str(kws), str(extra)])

	print("=== RIDERS PER ENEMY BODY (kw + on_enter/on_death/adj_buff/passive/...) ===")
	var ks := hist.keys()
	ks.sort()
	for k in ks:
		print("  %d rider(s): %4d bodies  %5.1f%%" % [
			k, hist[k], 100.0 * float(hist[k]) / maxf(1.0, float(total))])
	print("  bodies: %d   mean riders: %.2f" % [total, float(sum) / maxf(1.0, float(total))])
	for a in [1, 2, 3]:
		var c: int = per_act[a][0]
		print("  act %d: %.2f riders each (%d bodies)" % [
			a, float(per_act[a][1]) / maxf(1.0, float(c)), c])
	print("")
	print("=== BODIES CARRYING 3+ RIDERS: %d (%.1f%%) ===" % [
		worst.size(), 100.0 * float(worst.size()) / maxf(1.0, float(total))])
	worst.sort()
	for i in range(mini(28, worst.size())):
		print("  " + String(worst[i]))
	if worst.size() > 28:
		print("  ... and %d more" % (worst.size() - 28))
	_done = true
	quit(0)
