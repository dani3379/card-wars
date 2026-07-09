extends SceneTree
## Probe for the 2026-07-03 "aggressive improvements" sweep: branded curses,
## rule-ladder ascension, victory bundle, act-2 encounters, daily omen, ledger,
## and the relic interest pass. Data + state layer only (autorun covers combat).
## Snapshots run_*.save AND meta.save first — several checks mutate MetaState.
##   Godot.exe --headless --path . --script res://tools/_probe_sweep2.gd

var _fails := 0
var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _snapshot() -> void:
	for p in ["user://meta.save", "user://run_0.save", "user://run_1.save", "user://run_2.save"]:
		if FileAccess.file_exists(p):
			DirAccess.copy_absolute(p, p + ".sweep2bak")


func _restore() -> void:
	for p in ["user://meta.save", "user://run_0.save", "user://run_1.save", "user://run_2.save"]:
		var b: String = p + ".sweep2bak"
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, p)
			DirAccess.remove_absolute(b)


func _settle(frames: int = 3) -> void:
	for _i in range(frames):
		await process_frame


func _run() -> void:
	_snapshot()
	# Autoloads fetched at runtime — a --script SceneTree compiles BEFORE the
	# autoloads register, so bare CardDB/EncounterDB/... names won't resolve.
	var RS: Node = root.get_node_or_null("RunState")
	var MS: Node = root.get_node_or_null("MetaState")
	var CDB: Node = root.get_node_or_null("CardDB")
	var EDB: Node = root.get_node_or_null("EncounterDB")
	var MDB: Node = root.get_node_or_null("MutatorDB")
	var RDB: Node = root.get_node_or_null("RelicDB")

	# ── Curse pack data ──
	print("[sweep2] curse pack ...")
	_check(CDB.CURSE_IDS.size() == 6, "6 curse ids registered")
	for cid in CDB.CURSE_IDS:
		var d: Dictionary = CDB.get_card_data(cid)
		_check(not d.is_empty() and d.get("type", "") == "spell",
			"curse '%s' has valid card data" % cid)
	_check(bool(CDB.get_card_data("craven").get("curse_playable", false)),
		"craven is flagged playable")
	_check(CDB.get_card_data("war_debt").has("curse_on_draw"), "war_debt has a draw sting")
	var rolled_ok := true
	for _i in range(50):
		if not CDB.is_curse(CDB.random_curse_id()):
			rolled_ok = false
	_check(rolled_ok, "random_curse_id stays inside the pack (50 rolls)")
	_check(CardArtAliases.try_load_spell_art("deserters_mark") != null,
		"branded curse art resolves via spell alias")

	# ── Ascension rule ladder ──
	print("[sweep2] ascension ...")
	_check(RS.ASCENSION_RULES.size() == 6, "6 rule tiers (0..5)")
	MS.unlocked_ascension = 5   # meta.save is snapshotted; restored at exit
	RS.start_new_run("raider", 3, 4242)
	_check(RS.current_ascension == 3, "A3 run started at A3")
	_check(RS.deck.has("war_debt"), "A3: act 1 opens with a War-Debt in deck")
	var deck_n: int = RS.deck.size()
	RS.advance_act()
	_check(RS.deck.size() == deck_n + 1 and RS.deck.count("war_debt") >= 2,
		"A3: advance_act adds another War-Debt")
	RS.start_new_run("raider", 0, 4243)
	_check(not RS.deck.has("war_debt"), "A0: no War-Debt")

	# ── Act-2 encounters ──
	print("[sweep2] act-2 encounters ...")
	for eid in ["outriders_hour", "grass_that_hunts", "borrowed_faces",
			"signal_glass", "horse_lords_toll"]:
		var enc: Dictionary = EDB.get_encounter(eid)
		_check(not enc.is_empty() and int(enc.get("act", 0)) == 2,
			"encounter '%s' registered in act 2" % eid)
		var deck: Array = EDB.build_enemy_deck(eid, 2)
		_check(deck.size() >= 5, "  deck builds (%d cards)" % deck.size())
		_check(not EDB.get_reinforcement(eid, 2).is_empty(), "  reinforcement present")
		_check(EDB.get_face_hp(eid, 2,
			String(enc.get("type", "combat"))) > 0, "  face hp > 0")

	# ── Daily omen + ledger ──
	print("[sweep2] daily + ledger ...")
	var omen: String = RS.daily_mutator_id_for_today()
	_check(MDB.exists(omen), "daily omen '%s' exists in MutatorDB" % omen)
	MS.record_daily_start("stalwart")
	var today: Dictionary = MS.todays_daily()
	_check(String(today.get("result", "")) == "marching", "daily record stamped 'marching'")
	RS.start_new_run("stalwart", 0, 4244)
	RS.is_daily_run = true
	RS.hero_hp = 0
	MS.record_defeat()
	_check(String(MS.todays_daily().get("result", "")) == "lost", "daily defeat recorded")
	var hs: Dictionary = MS.hero_stats.get("stalwart", {})
	_check(int(hs.get("losses", 0)) >= 1, "hero ledger counts the loss")
	# Victory side: unlock callout flag + per-hero win + fastest baseline.
	RS.start_new_run("acolyte", 0, 4245)
	RS.current_floor = 30
	MS.unlocked_ascension = 0
	MS.fastest_victory_floors = -1
	MS.record_victory()
	_check(MS.last_victory_unlocked_tier == 1, "victory unlock flag set (A1)")
	_check(not MS.last_victory_was_fastest, "first win is a baseline, not a record")
	RS.current_floor = 20
	MS.record_victory()
	_check(MS.last_victory_was_fastest, "faster win flagged as record")
	_check(int(MS.hero_stats.get("acolyte", {}).get("wins", 0)) == 2, "hero ledger counts wins")
	# MetaState save/load roundtrip keeps the new fields.
	MS.save()
	MS.hero_stats = {}
	MS.daily_record = {}
	MS.load_save()
	_check(int(MS.hero_stats.get("acolyte", {}).get("wins", 0)) == 2, "ledger survives save/load")
	_check(not MS.todays_daily().is_empty(), "daily record survives save/load")

	# ── Relic pass data sanity ──
	print("[sweep2] reshaped relics ...")
	for rid in ["vanguards_cry", "banner_of_unity", "swift_boots",
			"conscription_relic", "bone_ring", "war_horn", "thiefs_gloves"]:
		var r: Dictionary = RDB.get_relic(rid)
		_check(not r.is_empty() and String(r.get("desc", "")) != "", "relic '%s' intact" % rid)

	# ── GameOver victory screen with the new callouts ──
	print("[sweep2] game over victory screen ...")
	RS.start_new_run("raider", 0, 4246)
	RS.hero_hp = 10           # victory path reads hero_hp > 0
	RS.creature_kills = {0: 4, 1: 3}
	RS.fallen = [{"uid": 2, "name": "Goblin", "enc": "the probe", "act": 1}]
	MS.last_victory_unlocked_tier = 2
	MS.last_victory_was_fastest = true
	var go = load("res://scenes/game_over.tscn").instantiate()
	root.add_child(go)
	await _settle(6)
	_check(go.get_node_or_null("SeedChip") != null, "seed chip present")
	_check(go.get_node_or_null("RunSummaryPanel") != null, "summary panel built (honors path)")
	go.queue_free()
	await _settle()

	# ── Rest heal target (A2 short rations) ──
	print("[sweep2] rest short rations ...")
	MS.unlocked_ascension = 5
	RS.start_new_run("stalwart", 2, 4247)
	RS.hero_hp = 5
	var rest = load("res://scenes/rest.tscn").instantiate()
	root.add_child(rest)
	await _settle()
	var target: int = rest._rest_heal_target()
	_check(target == 5 + int(ceil((RS.hero_max_hp - 5) * 0.6)),
		"A2 heal target = 60%% of missing (got %d)" % target)
	RS.start_new_run("stalwart", 0, 4248)
	RS.hero_hp = 5
	_check(rest._rest_heal_target() == RS.hero_max_hp, "A0 heal target = full")
	rest.queue_free()
	await _settle()

	_restore()
	# Reload the restored meta from disk so the session doesn't carry probe stats.
	MS.load_save()
	print("[sweep2] saves restored")
	if _fails == 0:
		print("[sweep2-probe] ALL PASS")
	else:
		print("[sweep2-probe] FAILS: %d" % _fails)
	quit(_fails)
