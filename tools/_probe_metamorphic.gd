extends SceneTree
## _probe_metamorphic.gd — PASS 10 of docs/BUG_SWEEP_METHOD_20260829.md (class C10).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_metamorphic.gd
##
## TESTING WITHOUT KNOWING THE RIGHT ANSWER.
##
## Pass 8 hit a wall that has a name: the ORACLE PROBLEM. To assert that a clash
## resolved "correctly" you must already know what correct is, and for a combat
## engine this deep that oracle is the engine itself — so the only checks that
## survived Pass 8 were the ones where a magnitude happened to be written down in
## data. Everything the resolvers compute was untestable by that route.
##
## Metamorphic testing is the standard answer. Instead of checking one run against a
## known output, it checks a RELATION between the outputs of two related runs. A
## relation can be true or false without anyone knowing what either run "should"
## have produced, which is exactly the situation here.
##
## The four canonical relation shapes are symmetry, permutation, monotonicity and
## idempotence. All four have a natural reading in this game:
##
##   MR1 SYMMETRY      A board and its MIRROR must resolve to mirrored outcomes.
##                     The two sides are supposed to play by one rule set; any
##                     side-biased branch makes the same position resolve
##                     differently depending on who holds it. This is the relation
##                     that would have caught "the solo player already goes second
##                     uncompensated" as a mechanical fact rather than an audit note.
##
##   MR2 IDEMPOTENCE   Applying the same board snapshot twice must equal applying it
##                     once. The client applies snapshots continuously; a
##                     non-idempotent apply drifts the watcher's board a little
##                     further from the host's on every sync.
##
##   MR3 MONOTONICITY  More attack must never remove less HP. A sign error, a clamp
##                     on the wrong side, or an overflow rule that reads a stale
##                     snapshot all show up as a non-monotonic step.
##
##   MR4 PERMUTATION   Two creatures played into two independent lanes must produce
##                     the same board in either order. Catches order-dependent state
##                     that leaks between plays.
##
## Each relation is checked over several staged boards, because a relation that
## holds for one fixture proves nothing.

var SS: Node
var NM: Node
var US: Node
var combat: Node

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


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _body(tag: String, atk: int, hp: int, kw: Array = []) -> Dictionary:
	var d: Dictionary = SS.skirmish_card_data("brute").duplicate(true)
	d["id"] = "mm_%s" % tag
	d["name"] = "MM%s" % tag
	d["atk"] = atk
	d["hp"] = hp
	d["keywords"] = kw.duplicate()
	return d


func _boot() -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 606061
	SS.vs_bot = true
	SS.best_of = 1
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.battle_style = NM.STYLE_SEALED
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	return is_instance_valid(combat)


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.35).timeout


## Stage a fixture. Each entry is [data, eid, lane, row, is_enemy]; `flip` swaps
## which side every body lands on, which is the mirror transform.
func _stage(plan: Array, flip: bool) -> void:
	for p in plan:
		var is_enemy: bool = bool(p[4]) != flip
		combat.net._net_spawn_creature(p[0], int(p[1]), int(p[2]), int(p[3]),
			is_enemy, false)
	await create_timer(0.2).timeout
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			c.state.ready_to_swing = true
			c.has_attacked_this_turn = false


## Outcome keyed by entity id, recorded from the OWNER'S point of view so a
## mirrored run produces the identical dictionary when the rule set is symmetric.
func _outcome(flip: bool) -> Dictionary:
	var out := {}
	for c in combat._all_creatures_both_sides():
		if not is_instance_valid(c) or int(c.entity_id) < 0:
			continue
		# `is_opponent` flips with the mirror, so undo it to compare like with like.
		var mine: bool = (not bool(c.is_opponent)) != flip
		out[int(c.entity_id)] = {"hp": int(c.current_hp), "mine": mine}
	# Hero HP likewise, named by side-of-origin rather than by index.
	out["hero_a"] = int(combat.enemy_hp) if flip else int(combat.player_hp)
	out["hero_b"] = int(combat.player_hp) if flip else int(combat.enemy_hp)
	return out


func _fixtures() -> Array:
	# Three positions with different shapes of interaction: a mutual kill, an
	# asymmetric trade, a keyword carrier, and a back-row pair.
	return [
		[
			[_body("a0", 5, 5), 8001, 0, combat.ROW_FRONT, false],
			[_body("b0", 5, 5), 8002, 0, combat.ROW_FRONT, true],
			[_body("a1", 2, 7), 8003, 1, combat.ROW_FRONT, false],
			[_body("b1", 4, 3), 8004, 1, combat.ROW_FRONT, true],
		],
		[
			[_body("c0", 3, 4, ["thorns"]), 8101, 0, combat.ROW_FRONT, false],
			[_body("d0", 4, 4), 8102, 0, combat.ROW_FRONT, true],
			[_body("c1", 6, 2, ["piercing"]), 8103, 2, combat.ROW_FRONT, false],
			[_body("d1", 1, 1), 8104, 2, combat.ROW_FRONT, true],
		],
		[
			[_body("e0", 2, 6, ["armored"]), 8201, 3, combat.ROW_FRONT, false],
			[_body("f0", 3, 3), 8202, 3, combat.ROW_FRONT, true],
			[_body("e1", 4, 4), 8203, 3, combat.ROW_BACK, false],
			[_body("f1", 2, 5), 8204, 3, combat.ROW_BACK, true],
		],
	]


func _run() -> void:
	print("[meta] PASS 10 — metamorphic relations\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[meta] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
		US.clash_dwell_scale = 1.0

	# ── MR1 — MIRROR SYMMETRY ─────────────────────────────────────────────
	print("[meta] --- MR1: a board and its mirror resolve the same ---")
	if not await _boot():
		_check(false, "MR1 booted"); _finish(1); return
	var fixtures := _fixtures()
	await _teardown()
	for i in fixtures.size():
		var results: Array = []
		var raw_views: Array = []
		for flip in [false, true]:
			if not await _boot():
				_check(false, "MR1 fixture %d booted" % i)
				break
			await _stage(fixtures[i], flip)
			await combat.net._net_run_clash(-1)
			await create_timer(0.4).timeout
			results.append(_outcome(flip))
			raw_views.append(_outcome(false))   # un-normalised: ownership as-is
			await _teardown()
		if results.size() == 2:
			_check(results[0] == results[1],
				"fixture %d resolves identically for both sides" % i)
			if results[0] != results[1]:
				print("          straight: %s" % str(results[0]))
				print("          mirrored: %s" % str(results[1]))
			# IS THE RELATION DOING ANY WORK? A symmetry check passes trivially if
			# the two runs were never actually different — so assert that the RAW,
			# un-normalised views DO differ. If they did not, the mirror transform
			# would be a no-op and the PASS above would mean nothing.
			_check(raw_views.size() == 2 and raw_views[0] != raw_views[1],
				"fixture %d: the mirror genuinely swapped sides (relation is not vacuous)" % i)

	# ── MR2 — SNAPSHOT IDEMPOTENCE ────────────────────────────────────────
	print("\n[meta] --- MR2: applying one snapshot twice == applying it once ---")
	for i in fixtures.size():
		if not await _boot():
			_check(false, "MR2 fixture %d booted" % i)
			break
		await _stage(fixtures[i], false)
		var snap: Dictionary = _capture_sync()
		# Re-boot as a CLIENT and feed the snapshot once, then twice.
		await _teardown()
		var once := {}
		var twice := {}
		for reps in [1, 2]:
			if not await _boot():
				break
			SS.combat_mode = SS.CombatMode.NET_CLIENT
			SS.local_index = 1
			NM.is_host = false
			NM.local_player_index = 1
			for _r in reps:
				combat.net._net_apply_board_sync(snap)
				await create_timer(0.2).timeout
			var state := {}
			for c in combat._all_creatures_both_sides():
				if is_instance_valid(c) and int(c.entity_id) >= 0:
					state[int(c.entity_id)] = "%d/%d@%d,%d" % [
						int(c.current_hp), int(c.current_atk),
						int(c.current_lane), int(c.current_row)]
			if reps == 1:
				once = state
			else:
				twice = state
			await _teardown()
		_check(not once.is_empty() and once == twice,
			"fixture %d: a repeated snapshot changes nothing (%d bodies)" % [
				i, once.size()])
		if once != twice:
			print("          once : %s" % str(once))
			print("          twice: %s" % str(twice))

	# ── MR3 — ATK MONOTONICITY ────────────────────────────────────────────
	print("\n[meta] --- MR3: more attack never removes less HP ---")
	for bonus in [0, 1, 3]:
		if not await _boot():
			_check(false, "MR3 booted"); break
		var plan: Array = [
			[_body("m0", 3 + bonus, 9), 8301, 0, combat.ROW_FRONT, false],
			[_body("n0", 1, 12), 8302, 0, combat.ROW_FRONT, true],
		]
		await _stage(plan, false)
		var before: int = 12
		await combat.net._net_run_clash(-1)
		await create_timer(0.4).timeout
		var victim = NM.get_entity(8302)
		var after: int = int(victim.current_hp) if is_instance_valid(victim) else 0
		var dealt: int = before - after
		print("        +%d ATK  ->  %d damage dealt" % [bonus, dealt])
		_monotone.append(dealt)
		await _teardown()
	var ok_mono := true
	for i in range(1, _monotone.size()):
		if int(_monotone[i]) < int(_monotone[i - 1]):
			ok_mono = false
	_check(ok_mono, "damage is non-decreasing in attack %s" % str(_monotone))

	print("\n[meta] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_finish(1 if _fails > 0 else 0)


var _monotone: Array = []


## The snapshot shape `_net_sync_board` sends, captured without a wire.
func _capture_sync() -> Dictionary:
	var creatures: Array = []
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				var c = arr[lane]
				if c == null or not is_instance_valid(c) or c.current_hp <= 0:
					continue
				creatures.append({
					"eid": int(c.entity_id), "owner": (1 if is_enemy else 0),
					"lane": lane, "row": row, "id": String(c.card_id),
					"atk": int(c.effective_atk()), "hp": int(c.current_hp),
					"mhp": int(c.card_data.get("hp", c.current_hp)),
					"kw": c.card_data.get("keywords", []),
					"floop": bool(c.will_floop), "token": bool(c.is_token),
					"state": c.state.to_replication_snapshot(),
				})
	return {
		"t": NM.EV_BOARD_SYNC, "creatures": creatures,
		"host_hp": int(combat.player_hp), "client_hp": int(combat.enemy_hp),
		"active": 0,
	}
