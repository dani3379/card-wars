extends SceneTree
## In-combat gate for SET-PIECE HOLDS. The sibling probe (_probe_setpiece.gd)
## proves the DATA and the MAP; this one boots the real combat scene on each
## authored scenario and proves the ENGINE.
##
##   Godot.exe --headless --path . --script res://tools/_probe_setpiece_fight.gd
##
## Every set-piece gets two baseline passes.
##
## PASS 1 — "the passive commander, on an armoured hero". The commander plays
## NOTHING and simply ends every turn. To test the CLOCK rather than the clash,
## the hero is given a deep HP pool first: a 30 HP hero who fields no creatures
## is dead by round 3-4 (measured — that is exactly what the first draft of
## this probe accidentally proved), and a scenario that kills you before the
## deadline never exercises the deadline at all. With the pool deep enough to
## reach the clock, each objective kind has ONE correct outcome:
##   hold_rounds -> CARRIED at the deadline (surviving IS the whole order)
##   slay_marked -> WITHDRAWN (a passive commander cannot break the Bearer)
##   protect     -> WITHDRAWN (an unscreened cart does not last five rounds)
##   break_face  -> WITHDRAWN (a passive commander deals no face damage)
##   clear_board -> WITHDRAWN (the finite opening company remains standing)
##
## PASS 2 — "the board audit". Inspect the seated opening before a single round
## resolves, then hold for several rounds under live reinforcement pressure and
## confirm the twisted rule never leaks. Closed ground is the only rule in the
## game enforced by a GATE rather than a hook, so it is the only one that can
## be broken by a placement path nobody remembered to check.
## Objective kinds that are pure data hooks get a THIRD, surgical pass: deliver
## the exact face-damage threshold or canonically destroy the finite board, then
## prove the live round-end evaluator carries the field and grants its trophy.
##
##
## What this catches that a data probe cannot: an objective that never
## evaluates, a deadline off by one, a withdrawal that kills, an authored body
## that lands in the wrong slot or at the wrong statline, a marked/warded body
## the engine loses track of, and any arrival path that ignores closed ground.

const TICK := 0.1
const TURN_WAIT_TICKS := 80
const MAX_ROUNDS := 14

var RS: Node
var US: Node
var SS: Node
var NM: Node
var SPDB: Node
var combat: Node

var _fails := 0
var _started := false
var _done := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	SPDB = root.get_node_or_null("SetPieceDB")
	if RS == null or SPDB == null:
		print("[setpiece-fight] FATAL: autoloads missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()

	var ids: Array = []
	for id in SPDB.SET_PIECES:
		ids.append(String(id))
	ids.sort()
	print("[setpiece-fight] %d scenarios to fight" % ids.size())

	for sp_id in ids:
		await _pass_one_passive(sp_id)
		await _pass_two_board(sp_id)

		await _pass_three_objective(sp_id)
	print("")
	if _fails == 0:
		print("[setpiece-fight] ALL PASS")
		_finish(0)
	else:
		print("[setpiece-fight] %d FAIL" % _fails)
		_finish(1)


func _pass_one_passive(sp_id: String) -> void:
	var sp: Dictionary = SPDB.get_set_piece(sp_id)
	var kind: String = String(sp.get("objective", {}).get("kind", ""))
	var deadline: int = int(sp.get("objective", {}).get("rounds", 0))
	var trophy: String = String(sp.get("trophy", {}).get("relic", ""))
	print("-- %s : pass 1 (passive commander, objective=%s, deadline=%d)"
		% [sp_id, kind, deadline])
	if not await _boot(sp_id, 400):
		_check(false, "%s: reached a player turn" % sp_id)
		await _teardown()
		return
	var hp_before: int = int(combat.player_hp)
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER \
			and rounds < MAX_ROUNDS:
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_for_player_turn():
			break
	_check(is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER,
		"%s: the fight RESOLVES (%d rounds)" % [sp_id, rounds])
	if not is_instance_valid(combat):
		await _teardown()
		return
	_check(int(combat.player_hp) > 0,
		"%s: the hero reached the clock alive (%d HP)" % [sp_id, int(combat.player_hp)])
	_check(bool(combat._sp_resolved), "%s: the objective was evaluated" % sp_id)
	# The deadline must bite ON its round, not a round late — an off-by-one here
	# is invisible in play and makes every printed clock a lie.
	if deadline > 0:
		_check(int(combat.round_number) <= deadline,
			"%s: resolved by round %d (deadline %d)"
				% [sp_id, int(combat.round_number), deadline])
	var carried: bool = RS.setpieces_carried.has(sp_id)
	match kind:
		"hold_rounds":
			_check(carried, "%s: CARRIED — surviving to the deadline is the order" % sp_id)
			_check(int(combat.round_number) == deadline,
				"%s: carried ON the deadline round, not before" % sp_id)
			if trophy != "":
				_check(RS.has_relic(trophy),
					"%s: the trophy `%s` was granted on the field" % [sp_id, trophy])
		"slay_marked":
			_check(not bool(combat._sp_mark_broken),
				"%s: the marked body survives a passive commander" % sp_id)
			_check(not carried, "%s: WITHDRAWN — the order was not kept" % sp_id)
			if trophy != "":
				_check(not RS.has_relic(trophy), "%s: no trophy for a withdrawal" % sp_id)
		"protect":
			_check(bool(combat._sp_ward_lost), "%s: the unscreened ward is lost" % sp_id)
			_check(not carried, "%s: WITHDRAWN — the order was not kept" % sp_id)
			if trophy != "":
				_check(not RS.has_relic(trophy), "%s: no trophy for a withdrawal" % sp_id)
		"break_face":
			var need: int = int(sp.get("objective", {}).get("value", 1))
			_check(int(combat._sp_face_damage_done) < need,
				"%s: passive play does not meet the face-damage order" % sp_id)
			_check(not carried, "%s: WITHDRAWN - the order was not kept" % sp_id)
			if trophy != "":
				_check(not RS.has_relic(trophy), "%s: no trophy for a withdrawal" % sp_id)
		"clear_board":
			_check(not combat._all_enemy_creatures().is_empty(),
				"%s: the opening company survives passive play" % sp_id)
			_check(not carried, "%s: WITHDRAWN - the order was not kept" % sp_id)
			if trophy != "":
				_check(not RS.has_relic(trophy), "%s: no trophy for a withdrawal" % sp_id)
	# THE TOLL, and THE PROMISE that comes with it.
	if not carried:
		var toll: int = int(sp.get("toll", 0))
		_check(hp_before - int(combat.player_hp) >= toll,
			"%s: the withdrawal cost at least the printed toll (%d -> %d, toll %d)"
				% [sp_id, hp_before, int(combat.player_hp), toll])
	_check(int(combat.player_hp) >= 1,
		"%s: failing a named action NEVER ends the run (%d HP)"
			% [sp_id, int(combat.player_hp)])
	_check(int(RS.hero_hp) >= 1,
		"%s: the RunState hero survives (%d HP)" % [sp_id, int(RS.hero_hp)])
	await _teardown()


func _pass_two_board(sp_id: String) -> void:
	print("-- %s : pass 2 (authored board + closed ground)" % sp_id)
	if not await _boot(sp_id):
		_check(false, "%s: reached a player turn (pass 2)" % sp_id)
		await _teardown()
		return
	var closed: Array = SPDB.closed_lanes(sp_id)

	# The authored opening is seated exactly where it was written, before a clash.
	for side in ["enemy", "player"]:
		var is_enemy: bool = side == "enemy"
		for entry in SPDB.build_opening(sp_id, side):
			var row: int = int(entry.row)
			var lane: int = int(entry.lane)
			var seated = combat._row_array(is_enemy, row)[lane]
			_check(seated != null and is_instance_valid(seated),
				"%s: %s body seated at r%d l%d" % [sp_id, side, row, lane])
			if seated != null and is_instance_valid(seated):
				var want: String = String(entry.data.get("name", ""))
				_check(String(seated.card_data.get("name", "")) == want,
					"%s: r%d l%d is `%s`" % [sp_id, row, lane, want])
				# No relic or token rider may have inflated an authored body —
				# a scenario whose cart quietly gained +1/+1 is a scenario that
				# no longer means what its brief said.
				var want_hp: int = int(entry.data.get("hp", 0))
				# Enemy bodies take the campaign's ordinary +0/+1/+2 act
				# thickening on arrival; player-side scenario bodies stay exact.
				if is_enemy and not combat._is_fortification(seated) \
						and not seated.has_keyword("structure"):
					var act_i: int = clampi(int(RS.current_act_idx), 0,
						combat.ENEMY_BODY_HP_BY_ACT.size() - 1)
					want_hp += int(combat.ENEMY_BODY_HP_BY_ACT[act_i])
				_check(int(seated.current_hp) == want_hp,
					"%s: `%s` seated at its live authored HP (%d)" % [sp_id, want, want_hp])

	# The marked / warded bodies are known to the engine.
	var kind: String = String(SPDB.get_set_piece(sp_id).get("objective", {}).get("kind", ""))
	if kind == "slay_marked":
		_check(combat._sp_marked != null and is_instance_valid(combat._sp_marked),
			"%s: the engine is holding the marked body" % sp_id)
	if kind == "protect":
		_check(combat._sp_ward != null and is_instance_valid(combat._sp_ward),
			"%s: the engine is holding the warded body" % sp_id)

	# The standing-order plaque exists and prints a live clock.
	_check(combat._sp_plaque != null and is_instance_valid(combat._sp_plaque),
		"%s: the standing-order plaque is built" % sp_id)
	_check(String(combat._sp_progress_text()) != "",
		"%s: the plaque prints a live readout (`%s`)"
			% [sp_id, String(combat._sp_progress_text())])

	# NO REINFORCEMENTS, under two live end-turn beats. Checking the deck count
	# catches the exact regression this data depends on: an empty-looking board
	# that quietly consumes its sealed deck through the ordinary dealer.
	var no_reinforce: bool = bool(SPDB.get_set_piece(sp_id).get(
		"rules", {}).get("no_reinforce", false))
	if no_reinforce:
		var deck_before: int = int(combat._enemy_deck.size())
		var standing_before: int = int(combat._all_enemy_creatures().size())
		var no_reserve_rounds := 0
		while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER \
				and no_reserve_rounds < 2:
			combat._end_turn_confirmed = true
			if combat.phase == combat.Phase.PLAYER_TURN:
				combat._on_end_turn()
			no_reserve_rounds += 1
			if not await _wait_for_player_turn():
				break
		_check(int(combat._enemy_deck.size()) == deck_before,
			"%s: no-reinforce leaves the sealed deck untouched for %d rounds"
				% [sp_id, no_reserve_rounds])
		_check(int(combat._all_enemy_creatures().size()) == standing_before,
			"%s: no reserve body enters for %d rounds" % [sp_id, no_reserve_rounds])

	# CLOSED GROUND, under pressure. Reinforcements arrive every round and the
	# escalation beat commits reserves — if any arrival path ignores the gate,
	# several rounds of that will find it.
	if not closed.is_empty():
		var breached := false
		var rounds := 0
		while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER \
				and rounds < 6:
			for row in [0, 1]:
				for lane in closed:
					if combat._row_array(true, row)[int(lane)] != null:
						breached = true
					if combat._row_array(false, row)[int(lane)] != null:
						breached = true
			combat._end_turn_confirmed = true
			if combat.phase == combat.Phase.PLAYER_TURN:
				combat._on_end_turn()
			rounds += 1
			if not await _wait_for_player_turn():
				break
		_check(not breached,
			"%s: closed ground %s held for %d rounds of arrivals"
				% [sp_id, str(closed), rounds])
		# And the player's own drop is refused too — the rule is symmetric or
		# it is not a rule.
		if is_instance_valid(combat):
			for lane in closed:
				_check(combat._sp_lane_closed(int(lane)),
					"%s: lane %s reads as closed to the player" % [sp_id, str(lane)])
	await _teardown()


func _boot(sp_id: String, hp_pool: int = 0) -> bool:
	var sp: Dictionary = SPDB.get_set_piece(sp_id)
	RS.start_new_run("raider", 0, 4242)
	# An optional deep HP pool so a pass can reach the CLOCK instead of dying to
	# the clash on round 3. Set before the scene boots — Combat snapshots
	# RunState.hero_hp / hero_max_hp in _setup_fight_state.
	if hp_pool > 0:
		RS.hero_max_hp = hp_pool
		RS.hero_hp = hp_pool
	# Enter the scenario the way visit_node would, without walking a map: a
	# set-piece is a combat node wearing a setpiece_id.
	RS.current_setpiece_id = sp_id
	RS.current_encounter_id = ""
	RS.current_node_type = "combat"
	RS.current_mutator_id = ""
	RS.current_act_idx = clampi(int(sp.get("act", 1)) - 1, 0, 2)
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	return await _wait_for_player_turn()


func _pass_three_objective(sp_id: String) -> void:
	var sp: Dictionary = SPDB.get_set_piece(sp_id)
	var objective: Dictionary = sp.get("objective", {})
	var kind: String = String(objective.get("kind", ""))
	if kind not in ["break_face", "clear_board"]:
		return
	print("-- %s : pass 3 (complete the %s objective)" % [sp_id, kind])
	if not await _boot(sp_id, 200):
		_check(false, "%s: reached a player turn (pass 3)" % sp_id)
		await _teardown()
		return
	var trophy: String = String(sp.get("trophy", {}).get("relic", ""))

	match kind:
		"break_face":
			var need: int = int(objective.get("value", 1))
			var landed: int = int(combat.damage_enemy_hero(need))
			_check(landed >= need,
				"%s: the printed %d face damage actually lands" % [sp_id, need])
			_check(int(combat._sp_face_damage_done) >= need,
				"%s: the live objective tallies dealt damage" % sp_id)
		"clear_board":
			var opening: Array = combat._all_enemy_creatures().duplicate()
			_check(not opening.is_empty(),
				"%s: the completion pass starts with an enemy board" % sp_id)
			for enemy in opening:
				if enemy != null and is_instance_valid(enemy):
					combat._force_destroy_creature(enemy)
			await create_timer(0.15).timeout
			_check(combat._all_enemy_creatures().is_empty(),
				"%s: canonical deaths leave the board empty" % sp_id)

	# Objectives are promised at ROUND END. Call the same evaluator the real
	# post-clash sequence calls; do not reach into _sp_award directly.
	combat._sp_round_end_check()
	await create_timer(0.05).timeout
	_check(bool(combat._sp_resolved),
		"%s: the round-end objective resolves" % sp_id)
	_check(RS.setpieces_carried.has(sp_id),
		"%s: completing the order carries the named field" % sp_id)
	if trophy != "":
		_check(RS.has_relic(trophy),
			"%s: carried field grants event trophy `%s`" % [sp_id, trophy])
	_check(is_instance_valid(combat) and combat.phase == combat.Phase.GAME_OVER,
		"%s: carried field hands off to the ordinary victory path" % sp_id)
	await _teardown()


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN \
				and int(combat.round_number) >= 1 \
				and combat._end_turn_btn != null \
				and is_instance_valid(combat._end_turn_btn):
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(0.15).timeout


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	_done = true
	quit(code)
