extends SceneTree
## Logic probe — Successor Wars Phase 0–1 scaffolding (no rendering).
## Asserts: rival deal validity/determinism for all 5 heroes, faction tags +
## get_ids_for filter counts vs FACTION_WORKSHEET, save/load roundtrip of the
## new fields, v2-save retirement, and the runs.csv schema migration.
## Backs up and restores save slot 2 + runs.csv so no real state is harmed.
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_conquest_scaffold.gd

var _fails: int = 0
# Autoload singletons fetched at runtime: bare identifiers (RunState etc.)
# don't compile in --script mode because the boot script is compiled before
# autoload globals register.
var RS: Node
var HDB: Node
var EDB: Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


var _ran: bool = false


# Work happens on the first process tick, not _initialize: in --script mode
# the autoload singletons are added to the root only after _initialize runs.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	print("[conquest-probe] start")
	RS = root.get_node_or_null("RunState")
	HDB = root.get_node_or_null("HeroDB")
	EDB = root.get_node_or_null("EncounterDB")
	if RS == null or HDB == null or EDB == null:
		print("[conquest-probe] FATAL: autoloads not found under root")
		quit(1)
		return true

	# ── backups (slot 2 save + telemetry file) ──
	var slot_path := "user://run_2.save"
	var csv_path := "user://runs.csv"
	var slot_backup: PackedByteArray = []
	var had_slot := FileAccess.file_exists(slot_path)
	if had_slot:
		slot_backup = FileAccess.get_file_as_bytes(slot_path)
	var csv_backup: PackedByteArray = []
	var had_csv := FileAccess.file_exists(csv_path)
	if had_csv:
		csv_backup = FileAccess.get_file_as_bytes(csv_path)

	_test_faction_data()
	_test_rival_deal()
	_test_encounter_filter()
	_test_kingdom_pools()
	_test_act_scaling()
	_test_map_wiring()
	_test_boss_gate()
	_test_recruit_nodes()
	_test_save_roundtrip()
	_test_v2_retirement()
	_test_telemetry_migration()

	# ── restore ──
	if had_slot:
		var f := FileAccess.open(slot_path, FileAccess.WRITE)
		f.store_buffer(slot_backup)
		f.close()
	else:
		if FileAccess.file_exists(slot_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path))
	if had_csv:
		var g := FileAccess.open(csv_path, FileAccess.WRITE)
		g.store_buffer(csv_backup)
		g.close()
	else:
		if FileAccess.file_exists(csv_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(csv_path))

	if _fails == 0:
		print("[conquest-probe] ALL PASS")
	else:
		print("[conquest-probe] %d FAILURES" % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _test_faction_data() -> void:
	print("— faction data")
	_check(HDB.FACTIONS.size() == 5, "5 factions defined")
	for hid in HDB.HERO_ORDER:
		var fid: String = HDB.get_faction(hid)
		_check(HDB.FACTIONS.has(fid), "hero %s has a real faction (%s)" % [hid, fid])
		_check(HDB.faction_lord(fid) == hid, "faction_lord roundtrip for %s" % fid)


func _test_rival_deal() -> void:
	print("— rival deal")
	for hid in HDB.HERO_ORDER:
		RS.start_new_run(hid, 0, 777)
		var ok: bool = RS.rival_lords.size() == 3 and RS.finale_rival != ""
		var seen: Dictionary = {}
		for r in RS.rival_lords:
			seen[r] = true
			if r == hid or not HDB.has_hero(r):
				ok = false
		if RS.finale_rival == hid or seen.has(RS.finale_rival):
			ok = false
		seen[RS.finale_rival] = true
		if seen.size() != 4:
			ok = false
		for i in 3:
			if RS.act_faction[i] != HDB.get_faction(RS.rival_lords[i]):
				ok = false
		_check(ok, "deal valid for hero %s (rivals=%s finale=%s)"
			% [hid, str(RS.rival_lords), RS.finale_rival])
	# determinism: same hero + seed twice → identical deal
	RS.start_new_run("raider", 0, 424242)
	var first: Array = RS.rival_lords.duplicate()
	var first_finale: String = String(RS.finale_rival)
	RS.start_new_run("raider", 0, 424242)
	_check(RS.rival_lords == first and RS.finale_rival == first_finale,
		"deal deterministic for fixed seed")
	RS.start_new_run("raider", 0, 424243)
	_check(RS.rival_lords != first or RS.finale_rival != first_finale,
		"deal changes with seed (sanity)")


func _test_encounter_filter() -> void:
	print("— encounter faction filter (counts from FACTION_WORKSHEET table)")
	# every encounter carries a known faction id
	var untagged := 0
	for id in EDB.ENCOUNTERS:
		var fid: String = String(EDB.ENCOUNTERS[id].get("faction", ""))
		if not HDB.FACTIONS.has(fid):
			untagged += 1
			print("    untagged/bad: ", id, " -> '", fid, "'")
	_check(untagged == 0, "all encounters tagged with real factions")
	# Legacy roster stays 40; rival kits (rival_*) land on top of it.
	var legacy_count: int = 0
	var rival_kits: int = 0
	for id in EDB.ENCOUNTERS:
		if String(id).begins_with("rival_"):
			rival_kits += 1
		else:
			legacy_count += 1
	_check(legacy_count == 40, "legacy encounter count is 40 (+%d rival kits)" % rival_kits)
	_check(not EDB.get_ids_for(1, "boss").has("rival_stalwart"),
		"rival kits excluded from random pools")
	var cases := [
		[1, "combat", "", 9], [1, "elite", "", 2], [1, "boss", "", 2],
		[2, "combat", "", 8], [2, "elite", "", 2], [2, "boss", "", 3],
		[3, "combat", "", 7], [3, "elite", "", 4], [3, "boss", "", 3],
		[1, "combat", "grasswake", 5], [1, "combat", "owed", 2],
		[1, "combat", "last_wall", 1], [1, "combat", "everflame", 1],
		[1, "combat", "lanternhall", 0],
		[2, "combat", "owed", 4], [2, "combat", "last_wall", 2],
		[3, "elite", "owed", 2], [3, "elite", "lanternhall", 2],
		[2, "boss", "owed", 1], [3, "boss", "everflame", 1],
	]
	for c in cases:
		var got: int = EDB.get_ids_for(c[0], c[1], c[2]).size()
		_check(got == c[3], "get_ids_for(%d, %s, '%s') == %d (got %d)"
			% [c[0], c[1], c[2], c[3], got])


func _test_kingdom_pools() -> void:
	print("— kingdom pools (cross-act borrow + boss demotion)")
	var lw_combat: Array = EDB.get_kingdom_pool(1, "combat", "last_wall")
	var pure: bool = lw_combat.size() == 4
	for id in lw_combat:
		if String(EDB.ENCOUNTERS[id].get("faction", "")) != "last_wall":
			pure = false
	_check(pure, "act-1 last_wall combat pool: 4 ids, faction-pure (%s)" % str(lw_combat))
	var lw_elite: Array = EDB.get_kingdom_pool(1, "elite", "last_wall")
	_check(lw_elite.has("iron_warden"), "iron_warden demotes into last_wall elite pool")
	var has_rival: bool = false
	for id in lw_elite:
		if String(id).begins_with("rival_"):
			has_rival = true
	_check(not has_rival, "rival kits never demote to elites")
	var gw_combat: Array = EDB.get_kingdom_pool(1, "combat", "grasswake")
	_check(gw_combat.size() == 5, "act-1 grasswake combat pool stays own-act (5)")
	var lh_combat: Array = EDB.get_kingdom_pool(1, "combat", "lanternhall")
	_check(lh_combat.has("mirror_temple") and lh_combat.size() > 1,
		"thin lanternhall pool borrows + tops up, stays playable (%d ids)" % lh_combat.size())


func _test_act_scaling() -> void:
	print("— cross-act scaling")
	_check(EDB.get_face_hp("mercenary_company", 2) == 15,
		"same-act face HP untouched")
	var down: int = EDB.get_face_hp("mercenary_company", 1)
	_check(down >= 9 and down <= 11, "A2 combat pulled to act 1 lands in band (got %d)" % down)
	var elite_demote: int = EDB.get_face_hp("iron_warden", 1, "elite")
	_check(elite_demote >= 17 and elite_demote <= 20,
		"boss demoted to act-1 elite lands in elite band (got %d)" % elite_demote)
	var up: int = EDB.get_face_hp("rival_stalwart", 3, "boss")
	_check(up >= 33 and up <= 38, "rival lord scaled to act 3 lands in boss band (got %d)" % up)
	var deck: Array = EDB.build_enemy_deck("mercenary_company", 1)
	var ok: bool = not deck.is_empty()
	for cd in deck:
		match String(cd.get("name", "")):
			"Recruit":
				if int(cd.atk) != 1 or int(cd.hp) != 2:
					ok = false
			"Pikeman":
				if int(cd.atk) != 1 or int(cd.hp) != 3:
					ok = false
	_check(ok, "deck bodies scale -1/-1 with ATK/HP floors on act-1 pull")
	var same: Array = EDB.build_enemy_deck("mercenary_company", 2)
	var untouched: bool = true
	for cd in same:
		if String(cd.get("name", "")) == "Recruit" and (int(cd.atk) != 2 or int(cd.hp) != 3):
			untouched = false
	_check(untouched, "same-act deck untouched")


func _test_map_wiring() -> void:
	print("— map wiring (faction-pure kingdoms, rival boss)")
	# Find a raider run whose ACT-1 rival is the Stalwart (the slice matchup).
	var found_seed: int = -1
	for s in range(1, 400):
		RS.start_new_run("raider", 0, s)
		if RS.rival_lords[0] == "stalwart":
			found_seed = s
			break
	_check(found_seed > 0, "found a seed with act-1 rival = stalwart (seed %d)" % found_seed)
	if found_seed < 0:
		return
	var act_map: Array = RS.map_data[0]
	var boss_id: String = ""
	var combat_pure: bool = true
	var combat_seen: int = 0
	for row in act_map:
		for node in row:
			var t: String = String(node.type)
			var eid: String = String(node.get("encounter_id", ""))
			if t == "boss":
				boss_id = eid
			elif t == "combat":
				combat_seen += 1
				if eid == "" or String(EDB.ENCOUNTERS.get(eid, {}).get("faction", "")) != "last_wall":
					combat_pure = false
	_check(boss_id == "rival_stalwart", "act-1 keep is THE STALWART (got '%s')" % boss_id)
	_check(combat_seen > 0 and combat_pure, "all %d act-1 holds are last_wall fights" % combat_seen)
	# Every act's keep resolves to SOME boss (kits or stand-ins).
	var all_bosses_ok: bool = true
	for a in range(3):
		var found: String = ""
		for row in RS.map_data[a]:
			for node in row:
				if String(node.type) == "boss":
					found = String(node.get("encounter_id", ""))
		if found == "" or not EDB.ENCOUNTERS.has(found):
			all_bosses_ok = false
	_check(all_bosses_ok, "every act's keep has a real boss (kit or stand-in)")


func _test_boss_gate() -> void:
	print("— boss gate (keep locked until %d holds)" % RS.HOLDS_TO_OPEN_LORD)
	# Generation guarantee: the worst route a player can walk still carries
	# enough fights to open the gate — across acts, heroes, and seeds.
	var guarantee_ok: bool = true
	for s in [19, 5, 77, 123, 4242]:
		RS.start_new_run("raider" if s % 2 == 1 else "kindler", 0, s)
		for a in range(3):
			if RS._min_fights_to_rest(RS.map_data[a]) < RS.HOLDS_TO_OPEN_LORD:
				guarantee_ok = false
	_check(guarantee_ok, "worst route carries >= %d fights (5 seeds x 3 acts)"
		% RS.HOLDS_TO_OPEN_LORD)
	# The availability filter: park at a rest-row site; with 0 holds the keep
	# road is withheld, at the gate it opens.
	RS.start_new_run("raider", 0, 19)
	var rest_node: Dictionary = {}
	for row in RS.map_data[0]:
		for node in row:
			if String(node.type) == "rest":
				rest_node = node
	_check(not rest_node.is_empty(), "act has a rest-row site to park on")
	RS.map_position = {"row": int(rest_node.row), "col": int(rest_node.col)}
	RS.holds_broken_in_act = 0
	_check(RS.get_available_nodes().is_empty(),
		"keep road shut at 0 holds (nothing offered from the rest row)")
	RS.holds_broken_in_act = RS.HOLDS_TO_OPEN_LORD
	var has_boss: bool = false
	for n in RS.get_available_nodes():
		if String(n.type) == "boss":
			has_boss = true
	_check(has_boss, "keep road opens at %d holds" % RS.HOLDS_TO_OPEN_LORD)
	# Legacy runs (no rival deal) keep the always-open keep.
	RS.holds_broken_in_act = 0
	RS.rival_lords.clear()
	var legacy_open: bool = false
	for n in RS.get_available_nodes():
		if String(n.type) == "boss":
			legacy_open = true
	_check(legacy_open, "legacy run (no rival deal) keeps the keep open")


func _test_recruit_nodes() -> void:
	print("— recruit camps")
	var counts_ok: bool = true
	var gate_ok: bool = true
	var total: int = 0
	for s in [19, 5, 77, 123, 4242, 31337]:
		RS.start_new_run("raider", 0, s)
		for a in range(3):
			var recruits: int = 0
			for row in RS.map_data[a]:
				for node in row:
					if String(node.type) == "recruit":
						recruits += 1
			if recruits < 1 or recruits > 2:
				counts_ok = false
			if RS._min_fights_to_rest(RS.map_data[a]) < RS.HOLDS_TO_OPEN_LORD:
				gate_ok = false
			total += recruits
	_check(counts_ok, "every act carries 1-2 recruit camps (%d across 18 acts)" % total)
	_check(gate_ok, "fight-count guarantee survives recruit conversion")
	# The muster draft itself (script-level, no UI).
	var rec = load("res://scripts/scenes/Recruit.gd").new()
	RS.start_new_run("raider", 0, 19)   # act 1 = the Last Wall kingdom
	var offer: Array = rec._roll_offer()
	_check(offer.size() == 3, "muster offers 3 banners (got %d)" % offer.size())
	var armored_s: int = rec._affinity(
		{"keywords": ["armored"], "type": "creature", "cost": 2}, "last_wall")
	var swift_s: int = rec._affinity(
		{"keywords": ["swift"], "type": "creature", "cost": 2}, "last_wall")
	_check(armored_s > swift_s, "last_wall affinity prefers armored over swift")
	rec.free()


func _test_save_roundtrip() -> void:
	print("— save/load roundtrip (scratch slot 2)")
	RS.start_new_run("acolyte", 0, 99001)
	RS.active_slot = 2
	RS.holds_broken_in_act = 2
	var rivals: Array = RS.rival_lords.duplicate()
	var finale: String = String(RS.finale_rival)
	var factions: Array = RS.act_faction.duplicate()
	RS.save_run()
	# clobber in-memory state, then load back (clear() keeps the typed
	# arrays' element type — assigning [] through a Variant base would not)
	RS.rival_lords.clear()
	RS.finale_rival = ""
	RS.act_faction.clear()
	RS.holds_broken_in_act = 0
	var loaded: bool = RS.load_run(2)
	_check(loaded, "load_run(2) succeeds on v3 save")
	_check(RS.rival_lords == rivals, "rival_lords survive roundtrip")
	_check(RS.finale_rival == finale, "finale_rival survives roundtrip")
	_check(RS.act_faction == factions, "act_faction survives roundtrip")
	_check(RS.holds_broken_in_act == 2, "holds_broken_in_act survives roundtrip")


func _test_v2_retirement() -> void:
	print("— v2 save retirement")
	# Forge a v2-stamped save into slot 2; the strict version check must
	# treat it as an empty slot.
	var f := FileAccess.open("user://run_2.save", FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "hero_hp": 10}))
	f.close()
	_check(not RS.load_run(2), "v2 save refuses to load")
	_check(not RS.get_slot_summary(2).get("has_save", true),
		"v2 save reads as empty slot in summary")


func _test_telemetry_migration() -> void:
	print("— runs.csv schema migration")
	var csv_path := "user://runs.csv"
	# Plant an old-schema file.
	var f := FileAccess.open(csv_path, FileAccess.WRITE)
	f.store_line("ended_at,result,hero,ascension,seed,act,floor,hp," +
		"max_hp,gold,fights_won,deck_size,relics,cause_of_death")
	f.store_line("2026-01-01T00:00:00,defeat,raider,0,1,1,3,0,25,50,2,12,3,test")
	f.close()
	# Use a real run state, then append a log row directly (NOT end_run —
	# end_run would write MetaState).
	RS.start_new_run("kindler", 0, 5150)
	RS.holds_broken_in_act = 1
	RS._append_run_log(false)
	var first_line := ""
	var row_count := 0
	var rf := FileAccess.open(csv_path, FileAccess.READ)
	var last_line := ""
	while not rf.eof_reached():
		var line := rf.get_line()
		if line == "":
			continue
		if first_line == "":
			first_line = line
		last_line = line
		row_count += 1
	rf.close()
	_check(first_line == RS._RUN_LOG_HEADER, "fresh file carries new header")
	_check(row_count == 2, "old rows shelved, not mixed (1 header + 1 row)")
	_check(last_line.split(",").size() == 19, "new row has 19 columns")
	_check(last_line.ends_with(",%s,1" % RS.finale_rival)
		and last_line.contains(",kindler,"), "rival/finale/holds columns populated")
	# Clean the shelf file the migration created.
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("runs_legacy_") and name.ends_with(".csv"):
				dir.remove(name)
			name = dir.get_next()
		dir.list_dir_end()
