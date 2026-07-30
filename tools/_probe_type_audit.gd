extends SceneTree
## _probe_type_audit.gd — verifies the 2026-07-15 type system (ARRIVE/ENDURE/DIE).
## Asserts: every draftable creature is soldier/beast/dead/untyped(""); no
## engine/zealot tags remain; the 3 keystones exist with the right type + passive;
## the untyped splash pool is correct; type-reading effects target live types.
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_type_audit.gd

var _fails: Array[String] = []

func _process(_d: float) -> bool:
	var CDB = root.get_node_or_null("CardDB")
	if CDB == null:
		print("FATAL no CardDB"); quit(1); return true

	var LEGAL := ["soldier", "beast", "dead", "warlock", "bastion", "stray", ""]
	var TRIBES := ["soldier", "beast", "dead", "warlock", "bastion", "stray"]
	var by_type: Dictionary = {}
	for t in LEGAL:
		by_type[t] = []
	var ids: Array = CDB.CARD_POOL.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = CDB.CARD_POOL[id]
		var rar: String = String(d.get("rarity", ""))
		if rar == "enemy" or CDB.is_curse(id):
			continue
		if String(d.get("type", "")) != "creature":
			continue
		var ct: String = String(d.get("ctype", ""))
		_check(ct in LEGAL,
			"%s has illegal ctype '%s' (engine/zealot must be gone)" % [id, ct])
		by_type[ct].append(id)

	# Keystones present, typed, and carrying their passive.
	_check_card(CDB, "gravepact", "dead", "reap_on_ally_death")
	_check_card(CDB, "warden_sergeant", "soldier", "warden_line")
	_check_card(CDB, "bloodmoon_alpha", "beast", "beast_encore")
	_check_card(CDB, "coven_mother", "warlock", "coven_spell")
	_check_card(CDB, "siegewright", "bastion", "bastion_ramp")
	# Free Company Captain (id `kingpin`) — the 2026-07-24 Stray rework retired the
	# per_gold aura for DEFECTION (loot a keyword on a kill / free-redeploy).
	_check_card(CDB, "kingpin", "stray", "defection")

	# Retype spot-checks (the mis-filed death-carers now read Dead).
	for dead_id in ["gravedigger", "tallow_doll", "blood_pyre", "necromancer",
			"carrion_priest", "gravecaller", "warden_of_graves", "sin_eater",
			"kindling", "burning_martyr", "ember_stalker", "mourner"]:
		_check(String(CDB.CARD_POOL[dead_id].get("ctype", "")) == "dead",
			"%s should be ctype dead" % dead_id)
	# Formation walls + Stalwart's palisade fold into Soldier. (siege_golem moved
	# home to Bastion 2026-07-15 — it arms its FELLOW walls with Thorns now.)
	for sol_id in ["iron_bastion", "riteforge", "palisade"]:
		_check(String(CDB.CARD_POOL[sol_id].get("ctype", "")) == "soldier",
			"%s should be ctype soldier" % sol_id)
	# WARLOCK (spellcasters), BASTION (walls + siege), STRAY (masterless) — the three
	# tribes carved from the old untyped pool.
	for wl_id in ["witch", "emberwright", "ember_warden", "hexblade", "scholar",
			"cinder_acolyte", "leyline_conduit", "the_apothecary"]:
		_check(String(CDB.CARD_POOL[wl_id].get("ctype", "")) == "warlock",
			"%s should be ctype warlock" % wl_id)
	for bs_id in ["warding_stone", "ironhide_anvil",
			"bramble_stockade", "crystal_sentry", "trebuchet", "the_leveler",
			"siege_golem"]:
		_check(String(CDB.CARD_POOL[bs_id].get("ctype", "")) == "bastion",
			"%s should be ctype bastion" % bs_id)
	for st_id in ["assassin", "adaptable", "treasure_hunter", "scavenger",
			"copycat", "doppelganger", "familiar"]:
		_check(String(CDB.CARD_POOL[st_id].get("ctype", "")) == "stray",
			"%s should be ctype stray" % st_id)

	# Every type_buff / buff_ctype_keyword must target a LIVE tribe.
	for id in ids:
		var d: Dictionary = CDB.CARD_POOL[id]
		var tb = d.get("type_buff", null)
		if tb is Dictionary:
			_check(String(tb.get("ctype", "")) in TRIBES,
				"%s type_buff targets dead type '%s'" % [id, tb.get("ctype", "")])
		var oe = d.get("on_enter", null)
		if oe is Dictionary and String(oe.get("type", "")) == "buff_ctype_keyword":
			_check(String(oe.get("ctype", "")) in TRIBES,
				"%s buff_ctype_keyword targets dead type '%s'" % [id, oe.get("ctype", "")])

	print("=== TYPE TALLY ===")
	for t in LEGAL:
		var label: String = t.to_upper() if t != "" else "UNTYPED"
		print("  %-8s %d" % [label, (by_type[t] as Array).size()])
	if not (by_type[""] as Array).is_empty():
		print("  UNTYPED ids: %s" % ", ".join(by_type[""]))

	if _fails.is_empty():
		print("\nPASS — type system consistent (%d checks)." % _passed)
		quit(0)
	else:
		print("\nFAIL — %d problem(s):" % _fails.size())
		for f in _fails:
			print("  ✗ " + f)
		quit(1)
	return true

var _passed: int = 0
func _check(cond: bool, msg: String) -> void:
	if cond: _passed += 1
	else: _fails.append(msg)

func _check_card(CDB, id: String, want_ct: String, want_passive: String) -> void:
	if not CDB.CARD_POOL.has(id):
		_fails.append("keystone %s missing from CARD_POOL" % id); return
	var d: Dictionary = CDB.CARD_POOL[id]
	_check(String(d.get("ctype", "")) == want_ct, "%s ctype should be %s" % [id, want_ct])
	_check(String(d.get("passive", "")) == want_passive, "%s passive should be %s" % [id, want_passive])
	_check(CDB.UPGRADES.has(id), "%s missing an UPGRADES (+) entry" % id)
