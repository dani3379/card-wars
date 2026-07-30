extends SceneTree
## Focused capital-siege data audit plus a live exact-history finale boot.
##
## Godot.exe --headless --path . --script res://tools/_probe_capitals_history.gd

const TICK := 0.1
const WAIT_TICKS := 120

var RS: Node
var EDB: Node
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
	if RS == null or EDB == null:
		print("[capitals-history] FATAL: required autoload missing")
		_finish(1)
		return
	var settings := root.get_node_or_null("UserSettings")
	if settings != null:
		settings.anim_speed = 3.0
		settings.end_turn_warning = false
	var skirmish := root.get_node_or_null("SkirmishState")
	if skirmish != null:
		skirmish.combat_mode = skirmish.CombatMode.SOLO
	var net_match := root.get_node_or_null("NetMatch")
	if net_match != null and net_match.has_method("leave"):
		net_match.leave()

	print("-- A. five distinct capital sieges")
	var specs := {
		"rival_stalwart": {"count": 2, "keyword": "armored",
			"order": "BREACH THE GATE"},
		"rival_raider": {"count": 3, "keyword": "",
			"order": "CUT THE STANDARDS"},
		"rival_acolyte": {"count": 2, "keyword": "last_stand",
			"order": "BREAK THE SEALS"},
		"rival_pyromancer": {"count": 3, "keyword": "thorns",
			"order": "SHATTER THE MIRRORS"},
		"rival_kindler": {"count": 2, "keyword": "doom",
			"order": "DOUSE THE BRAZIERS"},
	}
	var siege_ids := {}
	var orders := {}
	for encounter_id in specs:
		var spec: Dictionary = specs[encounter_id]
		var siege: Dictionary = EDB.get_siege(encounter_id)
		_check(not siege.is_empty(), "%s declares a siege" % encounter_id)
		_check(String(siege.get("order", "")) == String(spec.order),
			"%s posts its own standing order" % encounter_id)
		_check(not siege_ids.has(String(siege.get("id", ""))),
			"%s uses a unique siege id" % encounter_id)
		_check(not orders.has(String(siege.get("order", ""))),
			"%s uses a unique objective line" % encounter_id)
		siege_ids[String(siege.get("id", ""))] = true
		orders[String(siege.get("order", ""))] = true
		_check(EDB.get_siege_face_hp(encounter_id, 1, "boss")
				< EDB.get_face_hp(encounter_id, 1, "boss"),
			"%s trades face HP for capital defenses" % encounter_id)
		for act in range(1, 4):
			var bodies: Array = EDB.build_siege_fortifications(
				encounter_id, act)
			_check(bodies.size() == int(spec.count),
				"%s act %d builds %d objectives" % [
					encounter_id, act, int(spec.count)])
			var lanes := {}
			for entry in bodies:
				var data: Dictionary = entry.get("data", {})
				lanes[int(entry.get("lane", -1))] = true
				_check(bool(data.get("fortification", false)),
					"%s objective is terrain, not a creature" % encounter_id)
				var keyword := String(spec.keyword)
				if keyword != "":
					_check(data.get("keywords", []).has(keyword),
						"%s keeps its %s rule" % [encounter_id, keyword])
				if encounter_id == "rival_kindler":
					_check(int(data.get("doom", -1)) == 2
							and int(data.get("doom_damage", -1)) == 3,
						"Kindler brazier carries a live Doom 2 / 3-damage fuse")
			_check(lanes.size() == bodies.size(),
				"%s act %d objectives occupy distinct lanes" % [
					encounter_id, act])

	print("-- B. exact conquest history")
	var history: Array = ["kindler", "raider", "stalwart"]
	var phases: Array = EDB.get_boss_phases("amalgam_acolyte", history)
	_check(phases.size() == 3, "complete history builds three throne phases")
	var expected_passives := ["doom_bell", "throne_husks", "formation_drill"]
	var expected_thresholds := [27, 14, 0]
	for i in range(mini(3, phases.size())):
		_check(String(phases[i].get("source_rival", "")) == String(history[i]),
			"phase %d remembers defeated rival %s" % [i + 1, history[i]])
		_check(String(phases[i].get("passive_id", ""))
				== String(expected_passives[i]),
			"phase %d uses that rival's portable rule" % (i + 1))
		_check(int(phases[i].get("threshold", -1)) == int(expected_thresholds[i]),
			"phase %d keeps the authored health rail" % (i + 1))
	var reordered: Array = EDB.get_boss_phases(
		"amalgam_acolyte", ["stalwart", "kindler", "raider"])
	_check(reordered.size() == 3
			and String(reordered[0].get("source_rival", "")) == "stalwart"
			and String(reordered[1].get("source_rival", "")) == "kindler",
		"changing conquest order changes the finale order")
	var legacy: Array = EDB.get_boss_phases("amalgam_acolyte")
	_check(legacy.size() == 3
			and not legacy[0].has("source_rival"),
		"incomplete legacy history keeps the pre-authored fallback")

	print("-- C. live finale setup")
	RS.start_new_run("pyromancer", 0, 99173)
	RS.rival_lords.assign(["kindler", "raider", "stalwart"])
	RS.finale_rival = "acolyte"
	RS.act_faction.assign(["everflame", "grasswake", "last_wall"])
	RS.current_act_idx = 2
	RS.current_node_type = "boss"
	RS.current_encounter_id = "amalgam_acolyte"
	RS.current_mutator_id = ""
	RS.current_setpiece_id = ""
	RS.finale_stage = 1
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	var waited := 0
	while waited < WAIT_TICKS:
		if not is_instance_valid(combat):
			break
		if combat.phase == combat.Phase.PLAYER_TURN:
			break
		await create_timer(TICK).timeout
		waited += 1
	_check(is_instance_valid(combat)
			and combat.phase == combat.Phase.PLAYER_TURN,
		"finale reaches the first player turn")
	if is_instance_valid(combat):
		_check(String(combat._encounter_passive) == "doom_bell",
			"live finale opens with the first defeated rival's rule")
		_check(combat._boss_phases.size() == 3
				and String(combat._boss_phases[0].get(
					"source_rival", "")) == "kindler",
			"live Combat receives ordered history phases")
		_check(String(combat._encounter_preamble).contains("Kindler")
				and String(combat._encounter_preamble).contains("Raider")
				and String(combat._encounter_preamble).contains("Stalwart"),
			"intro names the exact three defeated rivals")

	if _fails == 0:
		print("[capitals-history] ALL PASS")
		_finish(0)
	else:
		print("[capitals-history] %d FAIL" % _fails)
		_finish(1)


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	_done = true
	quit(code)
