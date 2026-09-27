extends Node
## _probe_fight_count.gd — HOW MANY FIGHTS IS A RUN, AND HOW MUCH OF THAT IS A CHOICE?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_fight_count.tscn
##
## RUNS AS A SCENE (autoloads only resolve in a scene context) — the documented
## trap that cost `_probe_route_census` a hung run.
##
## `_probe_route_census` answers what one route REACHES. This answers a narrower
## question that the 2026-09-19 genre benchmark made urgent: the act skeleton
## promises 7 fights a route (4 FIGHT_ROWS + 2 ELITE_ROWS + boss), which is 21 a
## run against Slay the Spire's ~16 and Monster Train's 8 — but a SKELETON COUNT
## IS NOT A ROUTE COUNT. Elite bands are dodgeable when the band is ≥2 lanes
## wide, so the real figure is a RANGE, and the width of that range IS the
## "how much do I want to fight?" decision StS gets from its elite hunt.
##
## Three numbers per act, and the third is the design question:
##   · MIN  — the fewest fights any root→rest route can reach the keep with.
##   · MAX  — the most a greedy route can take.
##   · SPAN — MAX - MIN. A span of 0 means the chart offers no choice at all
##            about how much combat the run contains, whatever else it offers.
##
## Reported per act and summed over a 3-act run, because the player experiences
## the run total and the generator only ever reasons about one act.

const SAMPLES := 60
const ACTS := 3


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var rs: Node = get_node_or_null("/root/RunState")
	var edb: Node = get_node_or_null("/root/EncounterDB")
	var mdb: Node = get_node_or_null("/root/MutatorDB")
	var hdb: Node = get_node_or_null("/root/HeroDB")
	var ms: Node = get_node_or_null("/root/MetaState")
	var spd: Node = get_node_or_null("/root/SetPieceDB")
	if rs == null or edb == null:
		push_error("FIGHTCOUNT: autoloads missing")
		get_tree().quit(1)
		return

	var per_act: Array[Array] = [[], [], []]
	var run_min: Array[int] = []
	var run_max: Array[int] = []
	var spans_zero: int = 0
	var spans_total: int = 0

	for s in range(SAMPLES):
		var gen := CampaignMapGenerator.new(rs, edb, mdb, hdb, ms, spd)
		var rng := RandomNumberGenerator.new()
		rng.seed = 90000 + s * 131
		var rmin: int = 0
		var rmax: int = 0
		for act in range(1, ACTS + 1):
			var flat: Array = gen.generate_act(act, rng)
			var lo: int = _min_fights(flat)
			var hi: int = _max_fights(flat)
			# +1 for the keep: it is on every route and min_fights_to_rest
			# deliberately stops at the rest row.
			lo += 1
			hi += 1
			per_act[act - 1].append([lo, hi])
			rmin += lo
			rmax += hi
			spans_total += 1
			if hi - lo == 0:
				spans_zero += 1
		run_min.append(rmin)
		run_max.append(rmax)

	print("=== FIGHT COUNT CENSUS — %d runs, %d acts each ===" % [SAMPLES, ACTS])
	print("")
	print("  act   min fights   max fights   span (the choice)")
	for a in range(ACTS):
		var los: Array[int] = []
		var his: Array[int] = []
		for pair in per_act[a]:
			los.append(int(pair[0]))
			his.append(int(pair[1]))
		print("    %d      %4.2f         %4.2f         %4.2f" % [
			a + 1, _mean(los), _mean(his), _mean(his) - _mean(los)])
	print("")
	print("  WHOLE RUN   min %4.1f   max %4.1f   span %4.1f" % [
		_mean(run_min), _mean(run_max), _mean(run_max) - _mean(run_min)])
	print("  acts where the route count is FORCED (span 0): %d/%d (%d%%)" % [
		spans_zero, spans_total, int(round(100.0 * spans_zero / maxf(1, spans_total)))])
	print("")
	print("  benchmark: Slay the Spire ~16 fights/run, Monster Train 8")
	get_tree().quit(0)


## Fewest combat/elite nodes on any root -> rest-row route.
func _min_fights(flat: Array) -> int:
	return _walk(flat, true)


## Most combat/elite nodes on any root -> rest-row route.
func _max_fights(flat: Array) -> int:
	return _walk(flat, false)


func _walk(flat: Array, want_min: bool) -> int:
	if flat.is_empty() or (flat[0] as Array).is_empty():
		return 0
	var memo: Dictionary = {}
	var best: int = 999 if want_min else -1
	for start in (flat[0] as Array):
		var v: int = _from(flat, 0, int(start.col), memo, want_min)
		best = mini(best, v) if want_min else maxi(best, v)
	return maxi(best, 0)


func _from(flat: Array, row: int, col: int, memo: Dictionary, want_min: bool) -> int:
	var node: Dictionary = _find(flat[row], col)
	if node.is_empty():
		return 999 if want_min else -1
	var key: int = row * 100 + col
	if memo.has(key):
		return int(memo[key])
	var t: String = String(node.get("type", ""))
	var own: int = 1 if (t == "combat" or t == "elite") else 0
	var rest_row: int = CampaignMapGenerator.REST_ROW
	if row >= rest_row - 1:
		memo[key] = own
		return own
	var conns: Array = node.get("connections", [])
	if conns.is_empty():
		memo[key] = own
		return own
	var best: int = 999 if want_min else -1
	for c in conns:
		var v: int = _from(flat, row + 1, int(c), memo, want_min)
		if v >= 999 and want_min:
			continue
		best = mini(best, v) if want_min else maxi(best, v)
	if best >= 999 or best < 0:
		best = 0
	var total: int = own + best
	memo[key] = total
	return total


func _find(row_nodes: Array, col: int) -> Dictionary:
	for node in row_nodes:
		if int(node.get("col", -1)) == col:
			return node
	return {}


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t: float = 0.0
	for v in a:
		t += float(v)
	return t / a.size()
