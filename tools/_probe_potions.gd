extends SceneTree
## Headless probe: potion pool integrity + archetype roll gating.
##   Godot.exe --headless --path . --script res://tools/_probe_potions.gd
var fails := 0


func check(name: String, ok: bool) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rs: Node = root.get_node("/root/RunState")
	var pdb: Node = root.get_node("/root/PotionDB")
	var cdb: Node = root.get_node("/root/CardDB")
	rs.start_new_run("raider")

	# 1. Every potion entry is complete + has an icon on disk.
	var ids: Array = pdb.all_ids()
	check("pool has 14 potions (got %d)" % ids.size(), ids.size() == 14)
	var complete := true
	var icons := true
	for id in ids:
		var d: Dictionary = pdb.get_potion(id)
		if String(d.get("desc", "")) == "" or String(d.get("effect", "")) == "":
			complete = false
		if not (ResourceLoader.exists("res://assets/icons/potions/%s.png" % id)
				or ResourceLoader.exists("res://assets/icons/potions/%s.svg" % id)):
			print("  missing icon: ", id)
			icons = false
	check("all entries have desc+effect", complete)
	check("all potions have an icon file", icons)

	# 2. Starter deck (no doom, no curses): gated potions never roll.
	var saw := {}
	for _i in 400:
		saw[pdb.roll_random_potion()] = true
	check("doomsday gated OFF for doomless deck", not saw.has("doomsday_draught"))
	check("nip gated OFF for clean deck", not saw.has("grave_diggers_nip"))
	check("healing still rolls", saw.has("healing"))
	check("sapper's charge rolls", saw.has("bottled_fury"))

	# 3. Add a Doom creature -> doomsday unlocks.
	var doom_id := ""
	for cid in cdb.CARD_POOL.keys():
		if "doom" in cdb.get_card_data(cid).get("keywords", []):
			doom_id = cid
			break
	check("found a doom card in CardDB (%s)" % doom_id, doom_id != "")
	rs.deck.append(doom_id)
	saw = {}
	for _i in 400:
		saw[pdb.roll_random_potion()] = true
	check("doomsday rolls WITH doom card", saw.has("doomsday_draught"))
	check("nip still gated (1 curse, needs 2)", not saw.has("grave_diggers_nip"))

	# 4. Two curses -> nip unlocks.
	rs.deck.append("curse")
	rs.deck.append("wound")
	saw = {}
	for _i in 400:
		saw[pdb.roll_random_potion()] = true
	check("nip rolls WITH 2 curses", saw.has("grave_diggers_nip"))

	# 5. Pity counter exists and holds a value.
	rs.potion_drop_misses = 3
	check("potion_drop_misses field live", rs.get("potion_drop_misses") == 3)

	print("RESULT: %s (%d fails)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	quit(1 if fails > 0 else 0)
