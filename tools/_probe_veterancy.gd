extends SceneTree
## Campaign-memory probe (docs/CAMPAIGN_MEMORY.md): kill tallies, the epithet
## at 3 kills, the veteran +1/+1 at 6, the Roll of the Fallen, the data fold in
## get_upgraded_card_data, and the save/load round-trip (uses an empty save
## slot when one exists; otherwise backs up and restores slot 2's file bytes).
## Run:
##   Godot.exe --headless --path . --script res://tools/_probe_veterancy.gd

var _fails := 0
var _ran := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var rs: Node = root.get_node_or_null("RunState")
	var cdb: Node = root.get_node_or_null("CardDB")
	if rs == null or cdb == null:
		print("  FAIL  RunState/CardDB autoload missing")
		quit(1)
		return true

	print("[veterancy] fresh run, hero raider")
	rs.start_new_run("raider")
	_check(rs.creature_kills.is_empty(), "new run starts with a blank service record")
	_check(rs.fallen.is_empty(), "new run starts with an empty Roll of the Fallen")

	# Pick a creature and a spell from the live deck.
	var c_idx := -1
	var s_idx := -1
	for i in rs.deck.size():
		var d: Dictionary = cdb.get_card_data(rs.deck[i])
		if c_idx < 0 and String(d.get("type", "")) == "creature":
			c_idx = i
		if s_idx < 0 and String(d.get("type", "")) == "spell":
			s_idx = i
	_check(c_idx >= 0, "starter deck contains a creature to test on")
	var uid: int = rs.deck_uids[c_idx]
	var base: Dictionary = cdb.get_card_data(rs.deck[c_idx])
	var base_name := String(base.get("name", ""))
	var base_atk := int(base.get("atk", 0))
	var base_hp := int(base.get("hp", 0))

	# в”Ђв”Ђ kill accumulation + fold below the epithet threshold в”Ђв”Ђ
	_check(rs.record_kill(uid) == 1 and rs.record_kill(uid) == 2, "record_kill accumulates")
	_check(rs.get_kills(uid) == 2, "get_kills reads the tally")
	_check(rs.record_kill(-1) == 0 and rs.get_kills(-1) == 0, "uid -1 (tokens) is never tallied")
	var d2: Dictionary = rs.get_upgraded_card_data(c_idx)
	_check(int(d2.get("veteran_kills", 0)) == 2, "fold carries veteran_kills at 2 kills")
	_check(String(d2.get("name", "")) == base_name, "no epithet below 3 kills")
	_check(int(d2.get("atk", -1)) == base_atk and int(d2.get("hp", -1)) == base_hp,
		"no stat bonus below 6 kills")

	# в”Ђв”Ђ epithet at 3 в”Ђв”Ђ
	rs.record_kill(uid)
	var d3: Dictionary = rs.get_upgraded_card_data(c_idx)
	var epithet: String = rs.veteran_epithet(uid)
	_check(String(d3.get("name", "")) == base_name + " " + epithet,
		"3 kills earns the epithet (%s)" % epithet)
	_check(rs.veteran_epithet(uid) == epithet, "epithet is deterministic per uid")
	_check(int(d3.get("atk", -1)) == base_atk, "epithet alone adds no stats")

	# в”Ђв”Ђ veteran rank at 6 в”Ђв”Ђ
	for _i in 3:
		rs.record_kill(uid)
	var d6: Dictionary = rs.get_upgraded_card_data(c_idx)
	_check(int(d6.get("atk", -1)) == base_atk + 1 and int(d6.get("hp", -1)) == base_hp + 1,
		"6 kills grants +1/+1")
	_check(String(d6.get("name", "")).ends_with(epithet), "veteran keeps the earned name")

	# в”Ђв”Ђ forged veteran name order: "Name the Epithet +" в”Ђв”Ђ
	rs.upgrade_card(c_idx, "plus")
	var df: Dictionary = rs.get_upgraded_card_data(c_idx)
	_check(String(df.get("name", "")) == base_name + " " + epithet + " +",
		"forged veteran reads 'Name epithet +' (got: %s)" % df.get("name", ""))

	# в”Ђв”Ђ spells never veteran (defensive: kills on a spell uid stay cosmetic-free) в”Ђв”Ђ
	if s_idx >= 0:
		var sp_uid: int = rs.deck_uids[s_idx]
		rs.record_kill(sp_uid)
		rs.record_kill(sp_uid)
		rs.record_kill(sp_uid)
		var ds: Dictionary = rs.get_upgraded_card_data(s_idx)
		_check(not ds.has("veteran_kills") \
			and String(ds.get("name", "")) == String(cdb.get_card_data(rs.deck[s_idx]).get("name", "")),
			"spell cards never fold veterancy")

	# в”Ђв”Ђ the Roll of the Fallen в”Ђв”Ђ
	rs.record_fall(uid, rs.deck[c_idx], String(d6.get("name", "")), "The Pass Gate", 3)
	_check(rs.fallen.size() == 1, "record_fall writes the Roll")
	var f0: Dictionary = rs.fallen[0]
	_check(String(f0.get("enc", "")) == "The Pass Gate" and int(f0.get("uid", -1)) == uid \
		and String(f0.get("name", "")).ends_with(epithet),
		"the fall carries name-as-worn, place, and uid")

	# в”Ђв”Ђ save/load round-trip (stringified dict keys must restore as int uids) в”Ђв”Ђ
	var slot := -1
	for s in rs.SAVE_SLOTS:
		if not rs.has_save(s):
			slot = s
			break
	var backup: PackedByteArray = PackedByteArray()
	var backed_slot := -1
	if slot < 0:
		# All slots occupied: back up slot 2's bytes and restore after.
		slot = rs.SAVE_SLOTS - 1
		backed_slot = slot
		var bf := FileAccess.open(rs._save_path_for_slot(slot), FileAccess.READ)
		if bf != null:
			backup = bf.get_buffer(bf.get_length())
			bf.close()
	rs.active_slot = slot
	rs.save_run()
	var kills_before: int = rs.get_kills(uid)
	var falls_before: int = rs.fallen.size()
	rs.creature_kills = {}
	rs.fallen = []
	var loaded: bool = rs.load_run(slot)
	_check(loaded, "save/load round-trip loads")
	_check(rs.get_kills(uid) == kills_before,
		"creature_kills survives the trip with int uids (%d)" % rs.get_kills(uid))
	_check(rs.fallen.size() == falls_before \
		and String(rs.fallen[0].get("enc", "")) == "The Pass Gate",
		"the Roll of the Fallen survives the trip")
	# Clean up: remove the probe's save (or restore the backed-up bytes).
	var path: String = rs._save_path_for_slot(slot)
	if backed_slot >= 0 and backup.size() > 0:
		var wf := FileAccess.open(path, FileAccess.WRITE)
		wf.store_buffer(backup)
		wf.close()
	else:
		DirAccess.remove_absolute(path)
	rs.active_slot = -1
	rs.run_active = false

	# в”Ђв”Ђ a fresh run clears the ledgers в”Ђв”Ђ
	rs.start_new_run("raider")
	_check(rs.creature_kills.is_empty() and rs.fallen.is_empty(),
		"the next march starts with fresh ledgers")

	print("[veterancy] DONE: %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	quit(1 if _fails > 0 else 0)
	return true
