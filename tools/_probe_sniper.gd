extends SceneTree
## Sniper keyword probe. Verifies that Sniper is a real keyword and that the
## ranged-phase resolver still fires after marking the creature's attack spent.
##
## Run: Godot_console.exe --headless --path "D:\Godot" --script res://tools/_probe_sniper.gd

var combat: Node
var CDB: Node
var EDB: Node
var KE: Node
var _started := false
var _done := false
var _pass := 0
var _fail := 0


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _ck(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[sniper]   PASS  %s" % label)
	else:
		_fail += 1
		print("[sniper]   FAIL  %s   %s" % [label, detail])


func _run() -> void:
	print("[sniper] start")
	var RS = root.get_node_or_null("RunState")
	var SS = root.get_node_or_null("SkirmishState")
	var US = root.get_node_or_null("UserSettings")
	CDB = root.get_node_or_null("CardDB")
	EDB = root.get_node_or_null("EncounterDB")
	KE = root.get_node_or_null("KeywordEffects")
	if RS == null or CDB == null or EDB == null or KE == null:
		print("[sniper] FATAL: autoloads missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	var NM = root.get_node_or_null("NetMatch")
	if NM != null and NM.has_method("leave"):
		NM.leave()

	_ck("KeywordEffects registers Sniper", KE.KEYWORDS.has("sniper"))
	_ck("Sniper icon source exists", ResourceLoader.exists("res://assets/icons/keywords/sniper.svg"))
	_ck("Hexblade carries Sniper keyword", CDB.get_card_data("hexblade").get("keywords", []).has("sniper"))
	_ck("Raven carries Sniper keyword", CDB.get_card_data("raven").get("keywords", []).has("sniper"))
	var glass: Dictionary = EDB.make_card_data({
		"name": "Glass Sniper", "atk": 2, "hp": 1, "kw": [], "sniper": true})
	_ck("enemy sniper flag converts into keyword", glass.get("keywords", []).has("sniper"))

	RS.start_new_run("raider", 0, 9090)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	var ok := false
	for _i in 40:
		await create_timer(0.1).timeout
		if not is_instance_valid(combat):
			break
		if combat.phase == combat.Phase.PLAYER_TURN:
			ok = true
			break
	if not ok:
		print("[sniper] FATAL: never reached PLAYER_TURN")
		_finish(1)
		return
	print("[sniper] combat booted")

	await _t_keyword_only_fires()
	await _t_chains_on_kill()

	print("[sniper] DONE: %d passed, %d failed" % [_pass, _fail])
	_finish(0 if _fail == 0 else 2)


func _clear() -> void:
	for row in [0, 1]:
		for is_enemy in [false, true]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(arr.size()):
				var c = arr[i]
				if c != null and is_instance_valid(c):
					arr[i] = null
					c.queue_free()
	combat.enemy_hp = 60
	combat.player_hp = 30


func _seat_data(data: Dictionary, is_enemy: bool, lane: int, row: int = 0):
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", "probe"))
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data
	card.current_lane = lane
	card.current_row = row
	combat._row_array(is_enemy, row)[lane] = card
	var slot = combat._slot_array(is_enemy, row)[lane]
	combat._slot_set_card(slot, card)
	card.current_hp = int(data.get("hp", 1))
	card.current_atk = int(data.get("atk", 0))
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	card.update_stat_display()
	return card


func _seat_plain(is_enemy: bool, lane: int, atk: int, hp: int,
		kws: Array = [], row: int = 0):
	return _seat_data({
		"id": "probe_%s_%d" % ["e" if is_enemy else "p", randi()],
		"name": "Probe",
		"type": "creature",
		"cost": 1,
		"atk": atk,
		"hp": hp,
		"rarity": "common",
		"keywords": kws,
		"desc": "",
	}, is_enemy, lane, row)


func _t_keyword_only_fires() -> void:
	print("\n[sniper] === keyword-only Sniper fires ===")
	_clear()
	var s = _seat_plain(false, 0, 1, 3, ["sniper"])
	var e = _seat_plain(true, 2, 0, 1)
	_ck("_is_sniper reads keyword, not only legacy flag", combat._is_sniper(s, false, 0))
	await combat._resolve_ranged_attacks(0)
	combat._cleanup_dead()
	_ck("ranged phase shot killed the lowest-HP enemy",
		not is_instance_valid(e) or e.current_hp <= 0,
		"enemy hp=%s" % (str(e.current_hp) if is_instance_valid(e) else "freed"))
	_ck("sniper spent its attack after firing", s.has_attacked_this_turn)


func _t_chains_on_kill() -> void:
	print("\n[sniper] === Sniper chains on kill ===")
	_clear()
	var _s = _seat_plain(false, 0, 1, 3, ["sniper"])
	var e1 = _seat_plain(true, 1, 0, 1)
	var e2 = _seat_plain(true, 3, 0, 1)
	await combat._resolve_ranged_attacks(0)
	combat._cleanup_dead()
	_ck("first 1-HP target died", not is_instance_valid(e1) or e1.current_hp <= 0)
	_ck("second 1-HP target died from the chain", not is_instance_valid(e2) or e2.current_hp <= 0)
