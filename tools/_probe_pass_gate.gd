extends SceneTree
## Focused data + live-engine probe for the Stalwart capital siege.
##
##   Godot.exe --headless --path . --script res://tools/_probe_pass_gate.gd

const TICK := 0.1
const WAIT_TICKS := 100

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
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
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if RS == null or EDB == null:
		print("[pass-gate] FATAL: RunState or EncounterDB autoload missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()

	print("-- A. capital-siege data")
	var siege: Dictionary = EDB.get_siege("rival_stalwart")
	_check(not siege.is_empty(), "Stalwart declares a capital siege")
	_check(String(siege.get("brief", "")).contains("both gate sections"),
		"map brief explains the two-section objective")
	_check(EDB.get_siege_face_hp("rival_stalwart", 1, "boss") == 18,
		"gate replaces face durability (23 -> 18 before global scaling)")
	for act in range(1, 4):
		var gates: Array = EDB.build_siege_fortifications("rival_stalwart", act)
		var lanes: Array[int] = []
		for entry in gates:
			lanes.append(int(entry.get("lane", -1)))
			var data: Dictionary = entry.get("data", {})
			_check(bool(data.get("fortification", false)),
				"act %d gate is flagged as terrain" % act)
			_check(int(data.get("hp", 0)) == [4, 5, 6][act - 1],
				"act %d gate uses the %d HP rail" % [act, [4, 5, 6][act - 1]])
			_check(data.get("keywords", []).has("armored"),
				"act %d gate keeps printed Armored" % act)
		lanes.sort()
		_check(gates.size() == 2 and lanes == [1, 2],
			"act %d seats two inner-lane gate sections" % act)

	print("-- B. live combat routing and breach")
	if not await _boot():
		_check(false, "combat reaches the first player turn")
		_finish(1)
		return
	_check(bool(combat._siege_active) and not bool(combat._siege_breached),
		"fight opens in protected siege phase")
	var shot_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_path = arg.substr("--shot=".length())
	if shot_path != "":
		await create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		var shot: Image = root.get_texture().get_image()
		var shot_err := shot.save_png(shot_path)
		_check(shot_err == OK, "windowed siege screenshot saved")
		if shot_err == OK:
			print("[pass-gate] screenshot: ", shot_path)

	_check(String(combat._encounter_passive) == "",
		"formation is dormant while the gate stands")
	_check(combat._siege_plaque != null and is_instance_valid(combat._siege_plaque),
		"standing-order plaque is built")
	_check(String(combat._siege_plaque_order.text) == "BREACH THE GATE",
		"standing order names the immediate job")
	var living: Array[Control] = combat._living_siege_gates()
	_check(living.size() == 2, "both gate sections are live")
	var left = _gate("left")
	var right = _gate("right")
	_check(left != null and right != null, "left and right gate identities resolve")
	if left == null or right == null:
		_finish(1)
		return
	_check(not left.can_attack() and not right.can_attack(),
		"fortifications never advertise or make attacks")
	_check(int(left.adj_atk_buff) == 0 and int(right.adj_atk_buff) == 0,
		"soldier auras do not buff fortifications")
	right.take_damage(999)
	await process_frame
	_check(int(right.current_hp) == 1 and combat._living_siege_gates().size() == 2,
		"raw kill-convention damage becomes 3 and cannot delete a gate")

	var boss_hp_before := int(combat.enemy_hp)
	var left_hp_before := int(left.current_hp)
	var landed := int(combat.damage_enemy_hero(2, true, 0))
	_check(int(combat.enemy_hp) == boss_hp_before,
		"face damage cannot reach the Stalwart before breach")
	_check(int(left.current_hp) == left_hp_before - 1 and int(right.current_hp) == 1,
		"lane 1 routes into the left Armored section")
	_check(landed == 1, "damage return reports gate HP actually removed")

	var deaths_before := int(combat._enemy_deaths_this_fight)
	_check(combat._deal_siege_removal_damage(left),
		"unconditional removal converts to fixed siege damage")
	await process_frame
	_check(combat._living_siege_gates().size() == 1 and not combat._siege_breached,
		"one broken section does not expose the boss")
	_check(int(combat._enemy_deaths_this_fight) == deaths_before,
		"broken masonry does not count as a creature death")

	var hp_before_breach := int(combat.enemy_hp)
	var breach_landed := int(combat.damage_enemy_hero(4, false, 3))
	await process_frame
	_check(bool(combat._siege_breached) and combat._living_siege_gates().is_empty(),
		"right-lane force breaks the last section and opens the gate")
	_check(int(combat.enemy_hp) == hp_before_breach - 2,
		"only post-gate overflow reaches the Stalwart")
	_check(breach_landed == 3, "Armored absorbs one point across gate plus overflow")
	_check(String(combat._encounter_passive) == "formation_muster",
		"breach activates the existing Stalwart formation")
	_check(String(combat._siege_plaque_order.text) == "THE GATE IS OPEN",
		"standing order visibly advances after breach")
	var gate_scars := 0
	for scar in combat._battlefield_scars:
		if String(scar.get("kind", "")) == "gate":
			gate_scars += 1
	_check(gate_scars == 2, "both broken sections leave persistent rubble")
	var open_hp := int(combat.enemy_hp)
	combat.damage_enemy_hero(3, true, 0)
	_check(int(combat.enemy_hp) == open_hp - 3,
		"ordinary face damage reaches the boss after breach")

	if _fails == 0:
		print("[pass-gate] ALL PASS")
		_finish(0)
	else:
		print("[pass-gate] %d FAIL" % _fails)
		_finish(1)


func _gate(side: String):
	for gate in combat._siege_gates:
		if is_instance_valid(gate) and gate.current_hp > 0 \
				and String(gate.card_data.get("siege_side", "")) == side:
			return gate
	return null


func _boot() -> bool:
	RS.start_new_run("raider", 0, 4242)
	RS.current_setpiece_id = ""
	RS.current_encounter_id = "rival_stalwart"
	RS.current_node_type = "boss"
	RS.current_mutator_id = ""
	RS.current_act_idx = 0
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	var waited := 0
	while waited < WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.PLAYER_TURN \
				and combat._siege_plaque != null \
				and combat._living_siege_gates().size() == 2:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	_done = true
	quit(code)
