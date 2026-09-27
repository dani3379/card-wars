extends SceneTree
## _probe_leaks.gd — PASS 15 of docs/BUG_SWEEP_METHOD_20260829.md (class C15).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_leaks.gd
##
## RESOURCE LIFECYCLE, not logic. Every class so far asks whether the game computes
## the right answer; this one asks whether it gives back what it takes. A leak never
## fails an assertion — the game stays correct, it just gets heavier, and the only
## symptom is a session that degrades the longer it runs. Which is the shape of
## complaint a player reports as "it gets choppy after a while", and no correctness
## probe in this suite can see it.
##
## The signal has been in front of me all session: nearly every probe run ends with
## "ObjectDB instances leaked at exit". That message alone proves little (a clean
## shutdown of an autoload-heavy project reports some), so the honest measurement is
## not an absolute count but a SLOPE: build and tear down the same scene many times
## and see whether the object count keeps climbing.
##
## THE WARM-UP IS LOAD-BEARING. Legitimate caches — CardTextureCache's baked faces,
## ScenePreload's pinned scenes, the font atlases — fill on the first cycles and then
## stop. Counting from cycle 0 measures those and calls a cache a leak. So the first
## cycles are discarded and only the tail's slope is judged.
##
## Orphan nodes are the sharper instrument: `Performance.OBJECT_ORPHAN_NODE_COUNT`
## counts nodes that exist but are in no tree, which is exactly what a forgotten
## `queue_free` or a dangling registry reference produces.

const WARMUP := 2
const MEASURED := 5
## Objects per cycle that may accumulate without being called a leak. Not zero:
## a few Variants and RefCounted helpers legitimately outlive one cycle, and the
## engine's own deferred cleanup runs on its own schedule.
const SLOPE_TOLERANCE := 120.0

var SS: Node
var NM: Node
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
		_watchdog()
		_run()
	return _done


## A probe that hangs teaches nothing and hides its own failure. Cap the run.
func _watchdog() -> void:
	await create_timer(600.0).timeout
	if not _done:
		print("[leaks] WATCHDOG — the run never finished; last stage above")
		_done = true
		quit(1)


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


## Let every deferred free actually happen before counting.
func _settle() -> void:
	for _i in 6:
		await process_frame
	await create_timer(0.25).timeout
	for _i in 6:
		await process_frame


## Least-squares slope of a series, in units per cycle.
func _slope(series: Array) -> float:
	var n := series.size()
	if n < 2:
		return 0.0
	var sx := 0.0
	var sy := 0.0
	var sxy := 0.0
	var sxx := 0.0
	for i in n:
		var x := float(i)
		var y := float(series[i])
		sx += x; sy += y; sxy += x * y; sxx += x * x
	var denom := (n * sxx - sx * sx)
	if absf(denom) < 0.0001:
		return 0.0
	return (n * sxy - sx * sy) / denom


## Build a scene, hold it a moment, tear it down. One full lifecycle.
func _cycle_scene(path: String) -> void:
	# Seed a live run: these screens read RunState in `_ready` and stall without
	# one. And do NOT assign `current_scene` — freeing the tree's current scene
	# leaves it in a state where the next frame never completes, which hung this
	# probe on its very first cycle. `_probe_textfit` cycles screens the same way
	# and has never hung.
	RS.start_new_run("stalwart", 0, 4242)
	RS.run_active = true
	RS.gold = 400
	var node = load(path).instantiate()
	root.add_child(node)
	for _i in 8:
		await process_frame
	node.free()
	await _settle()


## A skirmish combat, booted and torn down the way a real match ends.
func _cycle_combat() -> void:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 4242
	SS.vs_bot = true
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.entities.clear()
	NM._next_entity_id = 1
	var c = load("res://scenes/combat.tscn").instantiate()
	c._net_first_player_override = 0
	root.add_child(c)
	await create_timer(0.5).timeout
	if is_instance_valid(c) and c._hand.is_empty():
		c._net_begin_combat()
	await create_timer(1.0).timeout
	if is_instance_valid(c):
		c.free()
	await _settle()


func _measure(label: String, cycle: Callable, warm: int = WARMUP,
		measured: int = MEASURED) -> void:
	print("\n[leaks] --- %s ---" % label)
	for w in warm:
		await cycle.call()
	var objs: Array = []
	var orph: Array = []
	for m in measured:
		await cycle.call()
		objs.append(_objects())
		orph.append(_orphans())
	print("        objects: %s" % str(objs))
	print("        orphans: %s" % str(orph))
	var obj_slope := _slope(objs)
	var orph_slope := _slope(orph)
	print("        slope: %+.1f objects/cycle, %+.1f orphans/cycle" % [
		obj_slope, orph_slope])
	# A FLAT SERIES AND A CLIMBING ONE ARE DIFFERENT FINDINGS, so do not let one
	# loose threshold call both "pass". Reward and combat sit at EXACTLY 0.0/cycle
	# — that is what a scene which gives everything back looks like, and it proves
	# the measurement works. The shop climbs ~23/cycle and, over 14 cycles, never
	# plateaus; a cache bounded by the card pool would have flattened. So it is
	# reported as an accumulation even while it is under the hard threshold.
	if obj_slope > 2.0:
		print("        NOTE  %s accumulates %+.1f objects per cycle and did not "
			% [label, obj_slope] + "plateau — all non-Node (orphans flat), so it is "
			+ "retained Resources/RefCounted rather than lost nodes.")
	_check(obj_slope <= SLOPE_TOLERANCE,
		"%s: object count stays under the hard leak threshold (%+.1f/cycle)" % [
			label, obj_slope])
	# Orphans are the sharp signal — a node alive and in no tree is a forgotten
	# free or a dangling reference, and there is no cache that legitimately does it.
	_check(orph_slope <= 8.0,
		"%s: orphan nodes are not accumulating (%+.1f/cycle)" % [label, orph_slope])


func _run() -> void:
	print("[leaks] PASS 15 — does the game give back what it takes?\n")
	RS = root.get_node_or_null("RunState")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	var US := root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[leaks] FATAL: autoloads missing"); _done = true; quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
	print("[leaks] baseline: %d objects, %d orphans" % [_objects(), _orphans()])

	# NOT the event scene. `Event._ready` picks a RANDOM event, and one carrying a
	# modal auto-effect (The Wet Cards' picker) opens and waits for a click — the
	# cycle never returns and the probe hangs. Scenes measured here must settle on
	# their own without input.
	# THE SHOP NEEDS A LONGER RUN THAN THE OTHERS, and the reason is the point of
	# the warm-up note above: its stock is RANDOM, so each open bakes card faces the
	# texture cache has not seen and the count climbs while that cache fills. A cache
	# bounded by the card pool PLATEAUS; a real leak does not. Five cycles could not
	# tell those apart (+27/cycle, perfectly linear), so it gets enough cycles to show
	# its shape.
	await _measure("shop scene", _cycle_scene.bind("res://scenes/shop.tscn"), 3, 14)
	await _measure("reward scene", _cycle_scene.bind("res://scenes/reward.tscn"))
	await _measure("skirmish combat", _cycle_combat)

	print("\n[leaks] final: %d objects, %d orphans" % [_objects(), _orphans()])
	print("[leaks] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_done = true
	quit(1 if _fails > 0 else 0)
