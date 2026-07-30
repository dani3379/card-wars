extends SceneTree
## _probe_square.gd — direct check that Pike Square's closed-formation bonus
## actually reaches the board (2026-07-20). Written because the shell ladder
## scored a 10x pike_square deck identically before and after the +2 ATK rework,
## which is exactly what a NON-FIRING passive looks like. Grades the mechanic,
## not the power:
##   lone square      -> no Thorns, no ATK bonus
##   square + neighbour -> Thorns AND +2 ATK on BOTH (each is the other's mate)
##   neighbour removed  -> both riders drop again (state-derived, not sticky)
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_square.gd

var combat: Node = null
var _fails: int = 0
# SceneTree scripts do not get autoload globals by name — fetch them off root.
var RS: Node
var CDB: Node


func _init() -> void:
	call_deferred("_go")


func _ok(label: String, cond: bool) -> void:
	print("[square] %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fails += 1


func _go() -> void:
	await process_frame
	RS = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	RS.start_new_run("raider")
	RS.current_node_type = "combat"
	RS.current_encounter_id = "bandit_camp"
	await process_frame

	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	for _i in range(40):
		await process_frame

	var data: Dictionary = CDB.CARD_POOL["pike_square"].duplicate(true)
	var base_atk: int = int(data.get("atk", 0))

	# Lone square in lane 1, front row.
	var a = combat._spawn_player_body(data.duplicate(true), 1, combat.ROW_FRONT,
		int(data.atk), int(data.hp))
	await process_frame
	combat._refresh_adjacency_buffs()
	await process_frame
	_ok("lone square has no Thorns", not a.state.square_thorns)
	_ok("lone square has no ATK bonus (%d == %d)" % [a.effective_atk(), base_atk],
		a.effective_atk() == base_atk)

	# Close the square: a neighbour in lane 2.
	var b = combat._spawn_player_body(data.duplicate(true), 2, combat.ROW_FRONT,
		int(data.atk), int(data.hp))
	await process_frame
	combat._refresh_adjacency_buffs()
	await process_frame
	_ok("closed square gains Thorns", a.state.square_thorns)
	_ok("closed square gains +%d ATK (%d)" % [combat.SQUARE_CLOSED_ATK, a.effective_atk()],
		a.effective_atk() == base_atk + combat.SQUARE_CLOSED_ATK)
	_ok("its mate is also closed (mutual)", b.state.square_thorns)
	_ok("mate also gains the ATK (%d)" % b.effective_atk(),
		b.effective_atk() == base_atk + combat.SQUARE_CLOSED_ATK)

	# Break the square — both riders must drop, not linger.
	combat._player_field[2] = null
	if is_instance_valid(b):
		b.queue_free()
	await process_frame
	combat._refresh_adjacency_buffs()
	await process_frame
	_ok("broken square drops Thorns", not a.state.square_thorns)
	_ok("broken square drops the ATK (%d == %d)" % [a.effective_atk(), base_atk],
		a.effective_atk() == base_atk)

	print("[square] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	quit()
