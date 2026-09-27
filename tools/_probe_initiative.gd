extends Node
## _probe_initiative.gd — THE INITIATIVE, on a real board.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_initiative.tscn
##
## WHY THIS FILE EXISTS. `_offer_initiative` forces `_initiative = "field"` when
## headless (the house first-option convention), so EVERY existing test —
## autorun, runsim, every combat probe — has exercised exactly one of the two
## branches. `LET THEM COME` (`"form_up"`), which runs the opening muster before
## the player may act and then pays the Coin, had never executed at all.
##
## `_probe_runsim` cannot close this gap either: its pilot never banks Command
## and always takes the field, so it is structurally blind to both options. This
## probe is the only runtime evidence the feature has.
##
## The load-bearing invariant under test is the one the reserves exist to protect:
## the hold may answer the player's tempo with DEPTH, but it may never answer it
## by closing the board. Raising `starting_count` would have done the latter,
## because `_deal_opening_muster`'s fill_order appends every unused FRONT lane
## before it reaches the back row.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0


func _ready() -> void:
	# ── Scoping: who is even asked ───────────────────────────────────────────
	# A plain hold and a set-piece must fall straight through, leaving _initiative
	# "" so their opening is byte-identical to before the feature existed.
	var plain = await _boot("combat")
	await plain._offer_initiative()
	_check(plain._initiative == "",
		"an ordinary hold is never asked (initiative stayed '')")
	plain.queue_free()
	await get_tree().process_frame

	var sp = await _boot("combat")
	sp._sp_id = "probe_setpiece"
	await sp._offer_initiative()
	_check(sp._initiative == "",
		"a set-piece is never asked — its opening board is authored")
	sp._sp_id = ""
	sp.queue_free()
	await get_tree().process_frame

	# A General IS asked, and headless resolves it to the house first option.
	var elite = await _boot("elite")
	await elite._offer_initiative()
	_check(elite._initiative == "field",
		"a General is asked, and headless takes the field (first-option convention)")

	# ── THE FIELD PRICE is that the hold ANSWERS YOU ─────────────────────────
	# The price is NOT an extra body (that was the first version, and it was the
	# wrong price — this function reads no player board, so ceding the first move
	# cost nothing and LET THEM COME strictly dominated). It is that the opening is
	# dealt reactively: the hold aims at the player's strongest creature's column
	# instead of rolling a blind shape.
	# ONE sweep, three questions. Each census boots a whole combat scene, so the
	# seed list is kept short deliberately — this probe is re-run on every combat
	# change and a 24-boot version took over eight minutes.
	var seeds: Array = [1, 99, 4242, 20260730]
	var reactive_answered := 0
	var blind_answered := 0
	var worst := 0
	var lid_ok := true
	var mustered := 0
	for s in seeds:
		var r := await _muster_answering("field", s)
		var b := await _muster_answering("", s)
		mustered += int(r.total)
		if bool(r.opposed_best):
			reactive_answered += 1
		if bool(b.opposed_best):
			blind_answered += 1
		worst = maxi(worst, int(r.front))
		if int(r.front) >= 4:
			lid_ok = false

	_check(mustered > 0, "fixture: the hold mustered against a player board")
	# The observable signature of a reactive opening: it aims at the player's
	# strongest column every time, which a blind formation roll cannot do.
	_check(reactive_answered == seeds.size(),
		"TAKING THE FIELD IS ANSWERED: the hold met the player's strongest column on %d/%d seeds"
			% [reactive_answered, seeds.size()])
	# And the blind branch must NOT match that, or the two options are one option
	# and the choice is cosmetic again — which is the bug this rework fixed.
	_check(blind_answered < reactive_answered,
		"LETTING THEM COME stays blind — it answered on only %d/%d seeds"
			% [blind_answered, seeds.size()])
	# The lid invariant survives the rework: a hold may bring a wall, never a lid,
	# or the player's win condition is physically unreachable.
	_check(lid_ok,
		"the reactive opening never sealed all 4 front lanes (worst %d)" % worst)

	# ── FORM_UP actually runs, and pays exactly one Coin ─────────────────────
	# The branch that had never executed. _run_opening_muster is the enemy TAKING
	# A TURN, so it must leave a line on the board and consume the pending flag.
	var fu = await _boot("elite")
	fu._initiative = "form_up"
	_check(fu._opening_muster_pending,
		"fixture: the hold still owes its opening formation")
	var mana_before: int = int(fu.player_mana)
	await fu._run_opening_muster()
	_check(not fu._opening_muster_pending,
		"FORM_UP RAN: the opening muster was consumed")
	_check(_count_side(fu, true).total > 0,
		"FORM_UP RAN: the hold's line is on the board before the player may act (%d bodies)"
			% _count_side(fu, true).total)
	# The Coin is paid by _offer_initiative, not by _run_opening_muster — grant it
	# the way the feature does and assert the arithmetic.
	fu.player_mana += fu.INITIATIVE_COIN_COMMAND
	_check(fu.player_mana == mana_before + fu.INITIATIVE_COIN_COMMAND,
		"the Coin paid exactly %d Command (%d -> %d)"
			% [fu.INITIATIVE_COIN_COMMAND, mana_before, fu.player_mana])

	# THE COIN CANNOT COMPOUND. Combat.gd:3754 ASSIGNS `player_mana =
	# player_max_mana + banked` rather than adding, so a new round wipes the
	# bonus. Asserted rather than trusted, because if that ever became a `+=` the
	# Coin would silently ramp every round of a keep fight.
	var before_round: int = int(fu.player_mana)
	await fu._start_round()
	_check(fu.player_mana <= fu.player_max_mana + fu.MAX_BANKED_MANA,
		"a new round rebuilt Command from base + bank, so the Coin cannot compound (%d -> %d, ceiling %d)"
			% [before_round, fu.player_mana, fu.player_max_mana + fu.MAX_BANKED_MANA])
	fu.queue_free()
	await get_tree().process_frame

	# ── Both openings share ONE resolver and ONE seating routine ─────────────
	# The reactive and blind paths must not drift into placing bodies by different
	# rules. They are kept honest by both funnelling through `_resolve_opening_slots`
	# (the overflow order, the occupancy check and the deck ceiling) and then
	# `_seat_opening_line` (the pacing).
	#
	# THE SPLIT IS THE POINT, not an implementation detail (2026-09-17). Deciding
	# and seating used to be one function, which is why the round-1 telegraph could
	# not say where the hold would go — the answer did not exist until the bodies
	# landed. The blind opening is now resolved a round early and SHOWN; only the
	# reactive one resolves at deal time, because only it reads the player's board.
	var src := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	_check(src.count("await _seat_opening_line(") == 2,
		"both openings seat their line through the one shared routine")
	_check(src.count("_resolve_opening_slots(") == 3,
		"both openings resolve their slots through the one shared routine")
	# The blind path must be planned AHEAD of the deal, the reactive path must not
	# be — that asymmetry is the whole reason one can be telegraphed.
	_check("_build_blind_formation(" in src and not ("await _build_blind_formation" in src),
		"the blind formation is rolled at plan time, not mid-deal")
	_check(not ("_place_initiative_reserves" in src),
		"the retired reserve-body price left no dead code behind")
	elite.queue_free()

	print("[initiative] %s" % ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


## Boot a real combat scene staged as `node_type`, settled to round 1.
func _boot(node_type: String, seed_value: int = 4242):
	RunState.start_new_run("stalwart", 0, seed_value)
	RunState.current_node_type = node_type
	RunState.current_encounter_id = _find_encounter(node_type)
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame
	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum 0, which is
	# also the uninitialised default (documented trap).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	return combat


## Stand a player line up with ONE obviously-strongest body, run the opening
## muster under the given initiative, and report whether the hold seated anything
## opposite that body. That is the observable signature of a reactive opening:
## `_get_placement_priority_4x4("elite")` aims at the player's highest-ATK
## column, while the blind formation roll cannot know which column that is.
##
## Each census gets its own combat instance so one block's formation roll cannot
## contaminate the next.
func _muster_answering(initiative: String, seed_value: int) -> Dictionary:
	var c = await _boot("elite", seed_value)
	_clear_board(c)
	# Lane 2 is the threat; the others are token chaff so the board is not a
	# single body sitting alone (which any placement rule would trivially face).
	_put_player(c, 0, 1)
	_put_player(c, 1, 1)
	_put_player(c, 2, 9)
	c._initiative = initiative
	c._opening_muster_pending = true
	await c._enemy_place_creatures()
	var out := _count_side(c, true)
	out["opposed_best"] = c._row_array(true, c.ROW_FRONT)[2] != null
	c.queue_free()
	await get_tree().process_frame
	return out


func _put_player(combat, lane: int, atk: int) -> void:
	combat.summon_token(atk, 5, lane, false, combat.ROW_FRONT, {}, "Probe Body")


func _count_side(combat, is_enemy: bool) -> Dictionary:
	var front := 0
	var back := 0
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(is_enemy, combat.ROW_FRONT)[lane] != null:
			front += 1
		if combat._row_array(is_enemy, combat.ROW_BACK)[lane] != null:
			back += 1
	return {"front": front, "back": back, "total": front + back}


func _find_encounter(node_type: String) -> String:
	var want := "elite" if node_type == "elite" else "combat"
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == want:
			return String(id)
	return ""


## Fixture teardown, not a game event — bypasses _die() so no on_death chain
## from one block can contaminate the next block's census.
func _clear_board(combat) -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
