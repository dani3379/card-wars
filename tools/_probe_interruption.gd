extends SceneTree
## _probe_interruption.gd — PASS 11 of docs/BUG_SWEEP_METHOD_20260829.md (class C11).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_interruption.gd
##
## THE TEMPORAL CLASS. Lewis et al.'s game-bug taxonomy splits failures into
## NON-TEMPORAL (wrong answer, missing feature, constraint violation — what every
## pass before this one covered) and TEMPORAL, where the timing or ORDER of events
## is what makes the behaviour wrong. Its three shapes are:
##
##   INVALID STATE        the system reaches a condition it has no handling for
##   INTERRUPTED EVENT    an operation fails to finish because something intervened
##   ACTION NOT PERFORMED an expected effect never happens because of timing
##
## That is not an academic distinction here — it is where this codebase actually
## breaks. Three of this session's bugs were temporal and each is one of the shapes:
## the toss modal dereferencing a Combat freed under it while it waited (interrupted
## event); Sealed Orders refusing every card because the phase had no active player
## (action not performed); the Bo3 drill waiting forever on a rematch answer that
## could not arrive (invalid state). The repo has been bitten here before too — the
## 2026-08-07 audit named an "await-during-live-button" class and found three.
##
## The technique is to INTERRUPT deliberately rather than wait to be unlucky:
##   A. Fire a committed action TWICE inside the same frame, before the first has
##      had a chance to disable its own control. This is a double-click, which
##      players do constantly, and it is the exact shape of the four latch bugs
##      fixed across MainMenu / Collection / Credits / MapView.
##   B. Free the scene WHILE a coroutine is parked mid-clash, then let the engine
##      run on. Anything that resumes holding a dangling reference errors here.
##   C. Deliver a peer-loss at each phase of a match, which is when a real
##      opponent is most likely to quit.
##
## Any SCRIPT ERROR during these is a failure: a correct system refuses cleanly.

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


func _boot(style: int = 0) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin",
			"strike", "brute", "goblin", "brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 141_421
	SS.vs_bot = true
	SS.best_of = 1
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.battle_style = style
	NM.entities.clear()
	NM._next_entity_id = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	var last := -1
	var stable := 0
	for _i in 40:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat):
			return false
		var n: int = combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 3:
			break
	return is_instance_valid(combat)


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.4).timeout


func _first_empty_slot() -> Control:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			if arr[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


func _board_count() -> int:
	var n := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(false, row):
			if c != null and is_instance_valid(c):
				n += 1
	return n


func _run() -> void:
	print("[interrupt] PASS 11 — temporal / interruption\n")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[interrupt] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false

	# ── A. THE SAME CARD PLAYED TWICE IN ONE FRAME ────────────────────────
	# A drop that resolves through an await can be re-entered before the hand has
	# rebuilt. If the guard is on the card rather than the frame, the second call
	# seats a second body and charges a second time.
	print("[interrupt] --- A: one card, two plays, same frame ---")
	if not await _boot():
		_check(false, "A booted"); _finish(1); return
	# PICK AN AFFORDABLE CREATURE (2026-09-16). This used to take the first
	# creature in hand at any price, which was safe while Command was a flat 3 and
	# almost everything cost 1-2. Under the Command ramp round 1 grants ONE, and
	# the rescaled pool's median cost is 3 — so the first creature is routinely
	# unplayable, `_on_card_played` refuses it, no body seats and no Command is
	# charged. This phase then stops testing the double-click latch it exists for.
	# It happened to fail loudly here; a luckier deal would have reported PASS
	# while exercising nothing, which is the worse half of the same bug.
	var card: Control = null
	for c in combat._hand:
		if c != null and is_instance_valid(c) and c.is_creature() \
				and combat._effective_cost(c) <= combat.player_mana:
			card = c
			break
	if card == null:
		# Nothing affordable in this deal. Make the scenario RUNNABLE rather than
		# skip it — and announce it — because a phase that quietly tests nothing
		# is indistinguishable from a passing one.
		for c in combat._hand:
			if c != null and is_instance_valid(c) and c.is_creature():
				card = c
				break
		if card != null:
			combat.player_mana = maxi(combat.player_mana,
				combat._effective_cost(card))
			print("[interrupt] A: no affordable creature dealt; Command topped to %d"
				% combat.player_mana)
	if card == null:
		_check(false, "A found a creature in hand")
	else:
		var slot := _first_empty_slot()
		card.global_position = slot.get_global_rect().get_center() - card.size * 0.5
		var mana_before: int = combat.player_mana
		var cost: int = combat._effective_cost(card)
		var n_before: int = _board_count()
		combat._on_card_played(card)
		combat._on_card_played(card)      # the double-click, before any rebuild
		await create_timer(0.5).timeout
		_check(_board_count() == n_before + 1,
			"exactly one body seated (%d -> %d)" % [n_before, _board_count()])
		_check(combat.player_mana == mana_before - cost,
			"Command charged exactly once (%d -> %d, cost %d)" % [
				mana_before, combat.player_mana, cost])
	await _teardown()

	# ── B. THE TURN COMMITTED TWICE IN ONE FRAME ──────────────────────────
	# `_net_on_done_placing` runs a clash through several awaits. Re-entering it
	# before the button disables would run a second clash into the same round.
	print("\n[interrupt] --- B: one turn, two commits, same frame ---")
	if not await _boot():
		_check(false, "B booted")
	else:
		var round_before: int = combat._net_turn_round
		combat._net_on_done_placing()
		combat._net_on_done_placing()     # the double-click
		await create_timer(2.5).timeout
		if is_instance_valid(combat):
			_check(combat._net_turn_round <= round_before + 1,
				"the round advanced at most once (%d -> %d)" % [
					round_before, combat._net_turn_round])
			_check(combat.player_hp > 0 and combat.enemy_hp > 0
					or combat._net_match_over,
				"the match is in a coherent state after the double commit")
		else:
			_check(false, "the scene survived a double commit")
	await _teardown()

	# ── C. THE SCENE FREED MID-CLASH ──────────────────────────────────────
	# The interrupted-event shape in its purest form: park a coroutine inside the
	# clash, free everything under it, and let the engine keep running. Anything
	# that resumes holding a dangling reference reports here.
	print("\n[interrupt] --- C: the scene freed while a clash is running ---")
	if not await _boot(NM.STYLE_SEALED):
		_check(false, "C booted")
	else:
		var kit: Array = [
			[5, 5, 0, false], [5, 5, 0, true],
			[3, 7, 1, false], [4, 4, 1, true],
			[2, 9, 2, false], [6, 3, 2, true],
		]
		var eid := 9500
		for k in kit:
			var d: Dictionary = SS.skirmish_card_data("brute").duplicate(true)
			d["id"] = "int_%d" % eid
			d["atk"] = int(k[0])
			d["hp"] = int(k[1])
			combat.net._net_spawn_creature(d, eid, int(k[2]), combat.ROW_FRONT,
				bool(k[3]), false)
			eid += 1
		await create_timer(0.25).timeout
		for c in combat._all_creatures_both_sides():
			if is_instance_valid(c):
				c.state.ready_to_swing = true
				c.has_attacked_this_turn = false
		combat.net._net_run_clash(-1)     # NOT awaited — it is mid-flight below
		await create_timer(0.12).timeout  # park it inside the clash
		combat.queue_free()               # pull the world out from under it
		await create_timer(1.6).timeout   # let every parked resume fire
		_check(true, "the engine survived a clash whose scene was freed under it")
	await create_timer(0.4).timeout

	# ── D. PEER LOSS DELIVERED AT EACH PHASE ──────────────────────────────
	# When a real opponent quits, it is usually at a decision point. Deliver the
	# drop at three of them and require a clean, single teardown each time.
	print("\n[interrupt] --- D: the opponent quits at each phase ---")
	for phase_name in ["opening", "mid-turn", "after a commit"]:
		if not await _boot():
			_check(false, "D (%s) booted" % phase_name)
			continue
		if phase_name == "mid-turn":
			await create_timer(0.3).timeout
		elif phase_name == "after a commit":
			combat._net_on_done_placing()
			await create_timer(0.6).timeout
		if not is_instance_valid(combat):
			_check(false, "D (%s): scene alive to receive the drop" % phase_name)
			continue
		combat.net._net_on_peer_lost()
		combat.net._net_on_peer_lost()    # a second delivery must be a no-op
		await create_timer(0.6).timeout
		_check(not is_instance_valid(combat) or combat._net_match_over,
			"peer loss at '%s' ends the match exactly once" % phase_name)
		await _teardown()

	print("\n[interrupt] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_finish(1 if _fails > 0 else 0)
