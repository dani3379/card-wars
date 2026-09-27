extends Node
## _probe_route_census.gd — WHAT DOES ONE ROUTE THROUGH AN ACT ACTUALLY OFFER?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_route_census.tscn
##
## RUNS AS A SCENE, not `--script`, because it reaches RunState and the generator
## through the tree and autoloads only resolve in a scene context. The first
## version of this file was a `SceneTree` script that tried to `set_script` a
## SceneTree-derived script onto a plain Node — the node never got a `_ready`,
## nothing ever called `quit()`, and the probe hung until it was killed. That is
## the documented "probe hangs forever" trap and it cost one wasted run.
##
## `_probe_campaign_walk` (C5/C7) proves every act is WALKABLE and every node type
## is ROUTED. `_probe_content_census` (C20) proves every card and encounter can be
## ROLLED. Neither answers the question a player is actually asking on the chart:
## on the road I am about to walk, how much of this act will I see?
##
## An act CONTAINS far more than a route TOUCHES. A 7-wide act with 24-36 sites is
## walked one column per row, so a wagon three lanes away is, to that run, content
## that does not exist. TWO NUMBERS PER TYPE, and the gap is the finding:
##   · IN ACT   — how many exist anywhere in the generated act.
##   · ON ROUTE — how many one walk from camp to keep actually reached.
##
## It also reports BRANCH WIDTH, because "how many stops did I choose between" is
## the whole of map interest: a row offering one node is a corridor with a map
## painted on it, and a run made of those has no route strategy in it at all.
##
## AND IT MEASURES THE RUSH. `RunState.get_available_nodes` appends the lord node
## to EVERY step once two holds have fallen, with no adjacency test — so the keep
## is a legal march from wherever the army stands. Whether that is a shortcut or
## a trap is a design question; how much of the act it skips is a measurement,
## and this is it.

const SAMPLES := 40
const GUARD := 80


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var rs: Node = get_node_or_null("/root/RunState")
	if rs == null:
		print("[route-census] RunState missing")
		get_tree().quit(1)
		return

	var in_act: Dictionary = {}
	var on_route: Dictionary = {}
	var on_route_full: Dictionary = {}
	var widths: Array = []
	var stops_rush: Array = []
	var stops_full: Array = []
	var acts := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260919

	for s in SAMPLES:
		# TWO WALKS PER ACT, from the same generated map: one that takes the keep
		# the moment it is offered, one that refuses it until the road runs out.
		# Same map both times, so the difference is the ROUTE and nothing else.
		for rush in [true, false]:
			rs.call("start_new_run", "raider", 424242 + s)
			var amap: Variant = rs.call("get_current_act_map")
			if not (amap is Dictionary) and not (amap is Array):
				continue
			if rush:
				acts += 1
				for row in _rows_of(amap):
					for nd in row:
						var t := String((nd as Dictionary).get("type", ""))
						in_act[t] = int(in_act.get(t, 0)) + 1
			var taken := 0
			for _g in GUARD:
				var avail: Array = rs.call("get_available_nodes")
				if avail.is_empty():
					break
				if not rush:
					# MEASURED ON THE ROAD-FIRST WALK, not the rush: the rush is
					# five stops long, so widths gathered there describe the
					# shortcut rather than the act. And the boss is excluded from
					# the count — "carry on, or skip the rest of the act" is not
					# a route choice between stops, it is a choice about whether
					# to have a route at all, and counting it makes a corridor
					# read as a fork.
					var real := 0
					for n in avail:
						if String((n as Dictionary).get("type", "")) != "boss":
							real += 1
					widths.append(real)
				var pick: Dictionary = _pick(avail, rng, rush)
				var t2 := String(pick.get("type", ""))
				if rush:
					on_route[t2] = int(on_route.get(t2, 0)) + 1
				else:
					on_route_full[t2] = int(on_route_full.get(t2, 0)) + 1
				rs.call("visit_node", int(pick.get("row", 0)), int(pick.get("col", 0)))
				# THE WALK MUST WIN ITS FIGHTS OR THE GATE NEVER OPENS, and the
				# first version of this probe did not — so it measured a map in
				# which the keep is permanently locked, reported the rush as
				# costing nothing, and was wrong in the most flattering possible
				# direction. `Combat` increments this on every combat/elite
				# victory; a walk that only visits nodes never does.
				if t2 == "combat" or t2 == "elite":
					rs.set("holds_broken_in_act",
						int(rs.get("holds_broken_in_act")) + 1)
				taken += 1
				if t2 == "boss":
					break
			if rush:
				stops_rush.append(taken)
			else:
				stops_full.append(taken)

	print("")
	print("[route-census] %d acts generated, each walked twice" % acts)
	print("")
	print("  %-12s %10s %12s %12s" % [
		"node type", "in act", "rush route", "full route"])
	var keys: Array = in_act.keys()
	keys.sort()
	for k in keys:
		print("  %-12s %10.2f %12.2f %12.2f" % [
			k, float(in_act[k]) / float(maxi(acts, 1)),
			float(int(on_route.get(k, 0))) / float(maxi(acts, 1)),
			float(int(on_route_full.get(k, 0))) / float(maxi(acts, 1))])
	print("")
	print("  Per ACT, averaged. 'in act' is what the generator laid down; the two")
	print("  route columns are what ONE walk reached — taking the keep as soon as")
	print("  it is offered, versus refusing it while any other stop remains.")

	if not stops_rush.is_empty():
		var mr := _mean(stops_rush)
		var mf := _mean(stops_full)
		print("")
		print("  THE RUSH")
		print("    stops taken, keep-first   %.1f" % mr)
		print("    stops taken, road-first   %.1f" % mf)
		print("    the act a rusher skips    %.0f%%" % [
			100.0 * (1.0 - mr / maxf(mf, 1.0))])

	if not widths.is_empty():
		var one := 0
		var hist: Dictionary = {}
		for w in widths:
			hist[w] = int(hist.get(w, 0)) + 1
			if int(w) <= 1:
				one += 1
		print("")
		print("  BRANCH WIDTH — stops the chart offered at each step")
		print("    mean             %.2f" % _mean(widths))
		print("    steps with ONE   %d of %d (%.0f%%) — no decision at all" % [
			one, widths.size(), 100.0 * float(one) / float(widths.size())])
		var wk: Array = hist.keys()
		wk.sort()
		for w in wk:
			print("    width %d: %5d steps (%2.0f%%)" % [
				int(w), int(hist[w]),
				100.0 * float(int(hist[w])) / float(widths.size())])
	print("")
	print("[route-census] done")
	get_tree().quit(0)


## Keep-first takes the boss the instant it appears; road-first refuses it while
## anything else is on offer, which is the only way to see the whole act.
func _pick(avail: Array, rng: RandomNumberGenerator, rush: bool) -> Dictionary:
	var others: Array = []
	var boss: Dictionary = {}
	for n in avail:
		if String((n as Dictionary).get("type", "")) == "boss":
			boss = n
		else:
			others.append(n)
	if rush and not boss.is_empty():
		return boss
	if others.is_empty():
		return boss if not boss.is_empty() else avail[0]
	return others[rng.randi_range(0, others.size() - 1)]


func _rows_of(amap: Variant) -> Array:
	if amap is Array:
		return amap
	if amap is Dictionary:
		var r: Variant = (amap as Dictionary).get("rows", [])
		return r if r is Array else []
	return []


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())
