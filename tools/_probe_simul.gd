extends SceneTree
## Simultaneity probe — verifies whether SOLO combat's "simultaneous" clash is
## actually simultaneous, or whether the side that attacks FIRST (the player)
## kills without retaliation because the death nulls the defender's board slot
## synchronously (Card2D.destroyed -> _on_card_destroyed) before its own swing.
##
## Scenario A (mutual kill): player 3/2 vs enemy 3/2, same lane/front. True
##   simultaneous -> BOTH take 3 and die. Broken -> player kills first, enemy
##   slot nulled, enemy never swings, player survives at 2 HP taking 0.
## Scenario B (no kill, harness sanity): player 1/5 vs enemy 1/5. Both survive
##   and both take 1 -> proves retaliation DOES fire when no one dies.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_simul.gd

var RS: Node
var SS: Node
var US: Node
var combat: Node
var _started := false
var _done := false
var _p_dmg := 0
var _e_dmg := 0
var _c2d: GDScript = null   # Card2D script — set the defer_deaths static through it


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _run() -> void:
	print("[simul] start")
	RS = root.get_node_or_null("RunState")
	SS = root.get_node_or_null("SkirmishState")
	US = root.get_node_or_null("UserSettings")
	if RS == null:
		print("[simul] FATAL: RunState missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	var NM = root.get_node_or_null("NetMatch")
	if NM != null and NM.has_method("leave"):
		NM.leave()

	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"

	_c2d = load("res://scripts/Card2D.gd")   # runtime load — no parse-time global-class dep

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)

	# Wait for _ready to reach a player turn (poll past the headless prebake stall).
	var ok := false
	for _i in 40:
		await create_timer(0.1).timeout
		if not is_instance_valid(combat):
			break
		if combat.phase == combat.Phase.PLAYER_TURN:
			ok = true
			break
	if not ok:
		print("[simul] FATAL: never reached PLAYER_TURN (phase=%s)" % (str(combat.phase) if is_instance_valid(combat) else "freed"))
		_finish(1); return
	print("[simul] combat booted, phase=PLAYER_TURN")

	await _scenario("A mutual-kill 3/2 vs 3/2", 3, 2, 3, 2)
	await _scenario("B no-kill 1/5 vs 1/5", 1, 5, 1, 5)

	print("[simul] DONE")
	_finish(0)


func _scenario(label: String, patk: int, php: int, eatk: int, ehp: int) -> void:
	print("\n[simul] === %s ===" % label)
	_clear_board()
	_p_dmg = 0
	_e_dmg = 0
	var pcard = _seat(false, 0, patk, php)
	var ecard = _seat(true, 0, eatk, ehp)
	await process_frame
	pcard.damaged.connect(func(n): _p_dmg += n)
	ecard.damaged.connect(func(n): _e_dmg += n)
	print("[simul]   seated: player %d/%d  enemy %d/%d" % [
		pcard.current_atk, pcard.current_hp, ecard.current_atk, ecard.current_hp])

	# Mimic _do_combat's simultaneous front-row clash for lane 0: hold deaths for
	# the whole clash (Card2D.defer_deaths), player swings then enemy swings (the
	# exact order + flag _do_combat now uses), then flush the held deaths.
	var none4: Array[bool] = [false, false, false, false]
	_c2d.set("defer_deaths", true)
	await combat._resolve_column_attack(0, 0, false, none4)   # player attacks
	await combat._resolve_column_attack(0, 0, true, none4)    # enemy attacks
	_c2d.set("defer_deaths", false)
	combat._cleanup_dead()

	var p_alive: bool = is_instance_valid(pcard) and pcard.current_hp > 0
	var e_alive: bool = is_instance_valid(ecard) and ecard.current_hp > 0
	print("[simul]   RESULT: player took %d dmg (alive=%s) | enemy took %d dmg (alive=%s)" % [
		_p_dmg, str(p_alive), _e_dmg, str(e_alive)])
	if _e_dmg > 0 and _p_dmg == 0 and not e_alive:
		print("[simul]   >>> NON-SIMULTANEOUS: enemy died to the player's first strike and NEVER retaliated (player has de-facto Swift).")
	elif _p_dmg > 0 and _e_dmg > 0:
		print("[simul]   >>> SIMULTANEOUS: both sides dealt damage.")


func _clear_board() -> void:
	for row in [0, 1]:
		for is_enemy in [false, true]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(arr.size()):
				var c = arr[i]
				if c != null and is_instance_valid(c):
					arr[i] = null
					c.queue_free()


func _seat(is_enemy: bool, lane: int, atk: int, hp: int):
	var data := {
		"id": "probe_%s" % ("e" if is_enemy else "p"),
		"name": "Probe%s" % ("E" if is_enemy else "P"),
		"type": "creature", "cost": 1, "atk": atk, "hp": hp,
		"rarity": "common", "keywords": [], "desc": "",
	}
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = data.id
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data
	card.current_lane = lane
	card.current_row = 0
	combat._row_array(is_enemy, 0)[lane] = card
	var slot = combat._slot_array(is_enemy, 0)[lane]
	combat._slot_set_card(slot, card)
	card.current_hp = hp
	card.current_atk = atk
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card
