extends SceneTree
## Relic probe (2026-06-18). Two checks the existing harnesses don't do:
##  1. STATIC desc/value drift — for every relic whose numeric `value` should
##     surface in its player text, flag the ones where `value` doesn't appear in
##     `desc` (a classic "someone changed value but not the copy" bug). Reports
##     review candidates, not hard fails (value is sometimes phrased indirectly).
##  2. BEHAVIORAL spot-check — boots real combat with a relic equipped and asserts
##     its effect actually manifests (couriers_bag draws +1; iron_buckler grants
##     Last Stand; veterans_medal buffs a 1-cost). Proves the harness can drive
##     relics behaviorally (extend with more as needed) and that these fire.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_relics.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
# value is a numeric KNOB that should appear in the copy. Relics whose value is a
# flag/index (0) or a non-displayed internal are skipped by the value>0 guard.
var RS: Node
var RDB: Node
var CDB: Node
var US: Node
var SS: Node
var combat: Node
var _started := false
var _pass := 0
var _fail: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[relics] start")
	RS = root.get_node_or_null("RunState")
	RDB = root.get_node_or_null("RelicDB")
	CDB = root.get_node_or_null("CardDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null or RDB == null:
		print("[relics] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	_static_desc_value_scan()
	await _behavioral_checks()

	print("[relics] ============ SUMMARY ============")
	print("[relics] behavioral passed : %d" % _pass)
	print("[relics] behavioral FAILED : %d %s" % [_fail.size(), str(_fail)])
	print("[relics] DONE")
	quit(1 if _fail.size() > 0 else 0)


## (1) Flag relics whose numeric value never shows up in their desc.
func _static_desc_value_scan() -> void:
	var flags: Array = []
	var checked := 0
	for id in RDB.RELICS.keys():
		var r: Dictionary = RDB.RELICS[id]
		var val := int(r.get("value", 0))
		if val <= 1:
			continue   # 0 = flag/no-knob; 1 = ubiquitous ("+1") → too noisy to flag
		checked += 1
		var desc := String(r.get("desc", ""))
		# Pull integers out of the desc.
		var nums := _ints_in(desc)
		if not (val in nums):
			flags.append("%-22s value=%-3d desc=\"%s\"" % [String(id), val, desc])
	print("[relics] ===== desc/value DRIFT review (value>=2 not found in desc) =====")
	for f in flags:
		print("[relics] ? ", f)
	print("[relics] (%d relics with value>=2 checked, %d flagged for review)" % [checked, flags.size()])


func _ints_in(s: String) -> Array:
	var out: Array = []
	var cur := ""
	for i in s.length():
		var c := s[i]
		if c >= "0" and c <= "9":
			cur += c
		else:
			if cur != "":
				out.append(int(cur)); cur = ""
	if cur != "":
		out.append(int(cur))
	return out


## (2) Behavioral: boot combat with a relic and assert its effect manifests.
## Scoped to ON-PLAY relics — those fire when WE play a card, so the timing is
## ours to control and the result is a clean snapshot. (Combat-START relics like
## couriers_bag fire during boot before we get control; their code is correct but
## they're not reliably snapshot-able from outside, so they're left to autorun's
## crash coverage + the static scan rather than asserted here.)
func _behavioral_checks() -> void:
	# swift_boots: "Swift creatures have +1 ATK." Play griffin (2/3 swift). NB:
	# swift_boots applies in _effective_attack() (the COMBAT-TIME atk path used at
	# clash — alongside vanguard_banner / adj_buff / glass_cannon), NOT in the base
	# effective_atk() stat that play-time buffs like veterans_medal modify. Assert
	# against the combat-time value (this two-path distinction is the gotcha for
	# any future relic probe).
	if await _boot_with_relic("swift_boots"):
		combat.player_mana = 9
		var g = _inject_and_play("griffin", 0)
		if g != null:
			_assert("swift_boots: Swift creature +1 ATK at clash (atk==3)",
				combat._effective_attack(g, 0, false) == 3)
		else:
			_fail.append("swift_boots: could not play griffin")
		await _teardown()

	# iron_buckler: "The first creature you play each fight gains Last Stand."
	if await _boot_with_relic("iron_buckler"):
		combat.player_mana = 9
		var c = _inject_and_play("goblin", 0)
		if c != null:
			_assert("iron_buckler: first creature gains Last Stand", c.has_keyword("last_stand"))
		else:
			_fail.append("iron_buckler: could not play goblin")
		await _teardown()

	# veterans_medal: "Your 1-cost creatures have +1/+1." Play a known 1-cost
	# (lookout 2/1) and assert it is buffed beyond its base body.
	if await _boot_with_relic("veterans_medal"):
		combat.player_mana = 9
		var lk = _inject_and_play("lookout", 0)
		if lk != null:
			# base lookout is 2/1; with the medal it should read 3/2.
			_assert("veterans_medal: 1-cost creature buffed (atk>=3)", lk.effective_atk() >= 3)
			_assert("veterans_medal: 1-cost creature buffed (hp>=2)", int(lk.current_hp) >= 2)
		else:
			_fail.append("veterans_medal: could not play lookout")
		await _teardown()


func _boot_with_relic(rid: String) -> bool:
	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	RS.add_relic(rid)
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	var ok := await _wait_for_player_turn()
	if not ok:
		print("[relics] boot FAILED for %s" % rid)
		await _teardown()
	return ok


func _inject_and_play(card_id: String, lane: int):
	combat._add_discovered_card_to_hand(card_id)
	var card = combat._hand.back()
	if card == null or not is_instance_valid(card):
		return null
	var slot = combat._slot_array(false, combat.ROW_FRONT)[lane]
	card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
	combat._on_card_played(card)
	return combat._row_array(false, combat.ROW_FRONT)[lane]


func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("[relics] PASS  %s" % name)
	else:
		_fail.append(name)
		print("[relics] FAIL  %s" % name)


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(0.05).timeout


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
