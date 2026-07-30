extends SceneTree
## _probe_tribe_moments.gd — gates the four Part C tribe MOMENTS (2026-07-30).
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_tribe_moments.gd
##
## Dead (Second Wave) and Stray (Defection) shipped first and have their own
## probes. This covers the remaining four from
## docs/DRAW_AND_TRIBE_DIRECTION_20260724.md Part C:
##
##   Soldier  VOLLEY        — once-fired latch, +1 ATK and Piercing for one clash
##   Bastion  THE WORKS     — arming trick, reflect the HP actually lost
##   Warlock  THE LEDGER    — arming trick, the round's 2nd spell pays on the board
##   Beast    STAMPEDE      — present-tense counter, an aimed arrival strike
##
## The assertions are written against the three failure modes the doc names, not
## against the happy path:
##   * a MOMENT that a board wipe can un-fire  -> the durable state is not reset
##                                                 by _start_round
##   * a MOMENT that needs its keystone alive   -> the flag lives on Combat
##   * a Beast reaching the FACE on arrival     -> Stampede fizzles on an empty
##                                                 column, it never redirects

var _fails: Array[String] = []
var _ran := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails.append(label)
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var CDB: Node = root.get_node_or_null("CardDB")
	var CI := load("res://scripts/state/CreatureInstance.gd")
	if CDB == null:
		print("[tribe-moments] autoloads missing")
		quit(1)
		return true
	var combat = load("res://scenes/combat.tscn").instantiate()

	print("— the four keystones exist, are rare, and carry their engine")
	var want := {
		"pike_captain": {"ctype": "soldier", "passive": "volley", "enter": ""},
		"siege_bastion": {"ctype": "bastion", "passive": "", "enter": "arm_works"},
		"the_magister": {"ctype": "warlock", "passive": "", "enter": "arm_ledger"},
		"dire_alpha": {"ctype": "beast", "passive": "stampede", "enter": ""},
	}
	for cid in want:
		var spec: Dictionary = want[cid]
		var cd: Dictionary = CDB.get_card_data(String(cid))
		_check(not cd.is_empty(), "%s exists in CardDB" % cid)
		if cd.is_empty():
			continue
		_check(String(cd.get("rarity", "")) == "rare", "%s is rare" % cid)
		_check(String(cd.get("ctype", "")) == String(spec.ctype),
			"%s is a %s" % [cid, spec.ctype])
		_check(String(cd.get("type", "")) == "creature", "%s is a creature" % cid)
		if String(spec.passive) != "":
			_check(String(cd.get("passive", "")) == String(spec.passive),
				"%s carries the '%s' passive" % [cid, spec.passive])
		if String(spec.enter) != "":
			_check(String(cd.get("on_enter", {}).get("type", "")) == String(spec.enter),
				"%s arms via the '%s' on-enter" % [cid, spec.enter])
			_check("on_enter" in Array(cd.get("keywords", [])),
				"%s prints the On-Enter device" % cid)
		_check(CDB.UPGRADES.has(cid), "%s has a hand-crafted '+' entry" % cid)
		# Every keystone is draftable — a tribe you cannot draft toward is not a
		# tribe, which is the whole complaint Part C answers.
		_check(cd.get("draftable", true) == true, "%s is draftable" % cid)

	print("— the durable state lives on Combat, not on the keystone")
	for field in ["_volley_fired", "_works_fortified", "_ledger_open",
			"_beasts_arrived_this_round", "_ledger_paid_this_round"]:
		var v = combat.get(field)
		_check(v != null and (v as Array).size() == 2,
			"%s is a per-side pair on Combat" % field)

	print("— a wipe cannot un-fire a MOMENT (the durable halves survive a round)")
	# _start_round is the shared solo+skirmish round-open chokepoint. The ROUND
	# halves must reset there; the FIGHT halves must not, or the tribe's identity
	# switches off every round and the arming trick is decorative.
	var src := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	var round_open := src.split("func _start_round()")
	_check(round_open.size() >= 2, "_start_round is present")
	if round_open.size() >= 2:
		var body: String = round_open[1].split("\nfunc ")[0]
		_check("_beasts_arrived_this_round = [0, 0]" in body,
			"the Beast counter resets each round")
		_check("_ledger_paid_this_round = [false, false]" in body,
			"the Ledger's once-per-round flag resets each round")
		for durable in ["_volley_fired", "_works_fortified", "_ledger_open"]:
			_check(not ("%s = [" % durable) in body,
				"%s is NOT reset at round open (survives a wipe)" % durable)

	print("— the arming trick survives the keystone's own death")
	# Both arms write ctx._<flag>[side] from KeywordEffects, i.e. onto Combat, and
	# neither reads the arming body again afterwards.
	var ke := FileAccess.get_file_as_string("res://scripts/data/KeywordEffects.gd")
	_check('"arm_works":' in ke, "arm_works is dispatched")
	_check('"arm_ledger":' in ke, "arm_ledger is dispatched")
	_check("ctx._works_fortified[works_side]" in ke,
		"arm_works writes the Combat-side flag")
	_check("ctx._ledger_open[ledger_side]" in ke,
		"arm_ledger writes the Combat-side flag")

	print("— Stampede can never reach the face on an arrival round")
	var st := src.split("func _maybe_stampede")
	_check(st.size() >= 2, "_maybe_stampede exists")
	if st.size() >= 2:
		var sbody: String = st[1].split("\nfunc ")[0]
		_check("get_opposing_card" in sbody,
			"Stampede aims at the opposing CREATURE")
		_check("NO QUARRY" in sbody,
			"an empty column fizzles visibly instead of redirecting")
		for face in ["damage_enemy_hero", "damage_player_hero", "_hurt_opposing_hero"]:
			_check(not (face in sbody),
				"Stampede never calls %s" % face)

	print("— Stampede is wired at every authoritative arrival site")
	# Three sites: solo enemy, solo player, net host. Missing one is a silent
	# asymmetry — the precedent is _maybe_beast_encore, so count against it.
	var net := FileAccess.get_file_as_string("res://scripts/net/CombatNet.gd")
	_check(src.count("_maybe_stampede(card, ") == src.count("_maybe_beast_encore(card, "),
		"solo: Stampede is called wherever the encore is")
	_check("combat._maybe_stampede(card, is_enemy_side)" in net,
		"net host: Stampede is called on the peer's arrivals")

	print("— THE WORKS reflects HP ACTUALLY LOST and never double-pays")
	var wk := src.split("# THE WORKS (arm_works)")
	_check(wk.size() >= 2, "the Works branch is present in _apply_struck_passives")
	if wk.size() >= 2:
		var wbody: String = wk[1].split("\nfunc ")[0]
		_check("take_damage_bypass_armor(damage_taken)" in wbody,
			"the reflect is the damage the wall actually took")
		_check('!= "reflect_strike"' in wbody,
			"Iron Rampart is excluded so one blow is not paid for twice")
		_check(not ("survived" in wbody.split("if damage_taken > 0")[0].right(200)),
			"the works bite on the way down, not only on survival")

	print("— the Volley's Piercing grant respects the printed-keyword erase order")
	# The Venom Tip bug: a round-scoped grant that strips a PRINTED keyword at
	# round end. temp_piercing is the erase order, so it must exist and be cleaned.
	var inst = CI.new()
	_check("temp_piercing" in inst.to_snapshot(),
		"temp_piercing rides the CreatureInstance snapshot")
	inst.temp_piercing = true
	inst.tick_end_of_round()
	_check(not inst.temp_piercing, "tick_end_of_round clears temp_piercing")
	_check("if card.state.temp_piercing:" in src,
		"round-end cleanup erases only GRANTED Piercing")
	var vol := src.split("# The Pike Captain (volley)")
	if vol.size() >= 2:
		# Bounded at the NEXT passive's comment, not at the next func: the War
		# Fortress block sits directly below in the same function and does use
		# persistent_atk_buff, so a func-wide slice reads its neighbour's code.
		var vbody: String = vol[1].split("# War Fortress")[0]
		_check("state.temp_piercing = true" in vbody,
			"the Volley marks its grant as round-scoped")
		_check("_volley_fired[vol_side] = true" in vbody,
			"the Volley latches so it fires once per fight")
		_check("temp_atk_buff" in vbody and not ("persistent_atk_buff" in vbody),
			"the Volley's +1 ATK is for the clash, not the fight")

	print("— the Ledger pays in skirmish too")
	_check("combat._maybe_pay_ledger(caster_is_enemy" in net,
		"the net host pays the Ledger for the caster's side")
	_check("_maybe_pay_ledger(false, _spells_cast_this_turn)" in src,
		"solo pays the Ledger off the pre-increment count")

	combat.free()
	if _fails.is_empty():
		print("[tribe-moments] ALL PASS")
		quit(0)
	else:
		print("[tribe-moments] FAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("  x ", f)
		quit(1)
	return true
