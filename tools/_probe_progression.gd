extends SceneTree
## Headless checks for the 2026-07-04 progression additions:
##   1. War school (veterancy rung 3) — VETERAN_SCHOOL_KILLS, the war_school
##      mod fold, Combat's catch-up sweep + headless auto-pick offer path.
##   2. Hold a Wake (Rest) — Roll-of-the-Fallen dedupe, folded-vs-printed
##      shade stats, the next_combat_gift_creature hand-off.
##   3. Cross-run muster unlocks — HeroDB relic_alt/deck_alt data integrity,
##      MetaState ledger queries, start_new_run pending overrides.
##
## The Wake commit fades to the map scene (same as the flow probe's rest
## driver) and register_rest_visit writes a save — slot saves are snapshotted
## and restored around the run, shellpass-style.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_progression.gd

var _fails := 0
var _ran := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _snapshot_saves() -> void:
	for i in range(3):
		var p := "user://run_%d.save" % i
		if FileAccess.file_exists(p):
			DirAccess.copy_absolute(p, p + ".progbak")


func _restore_saves() -> void:
	for i in range(3):
		var b := "user://run_%d.save.progbak" % i
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, "user://run_%d.save" % i)
			DirAccess.remove_absolute(b)


func _settle(frames: int = 3) -> void:
	for _i in range(frames):
		await process_frame


func _first_creature_index() -> int:
	var RS = root.get_node("RunState")
	var CDB = root.get_node("CardDB")
	for i in range(RS.deck.size()):
		if CDB.get_card_data(RS.deck[i]).get("type", "") == "creature":
			return i
	return -1


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	print("[progression] start")
	var RS = root.get_node_or_null("RunState")
	var CDB = root.get_node_or_null("CardDB")
	var RDB = root.get_node_or_null("RelicDB")
	var HDB = root.get_node_or_null("HeroDB")
	var MS = root.get_node_or_null("MetaState")
	if RS == null or CDB == null or RDB == null or HDB == null or MS == null:
		print("[progression] FATAL: autoloads missing")
		quit(1)
		return
	_snapshot_saves()
	var meta_stash: Dictionary = MS.hero_stats.duplicate(true)

	# ── 1. Muster data integrity: every alt resolves ──
	for hid in HDB.HEROES:
		var hero: Dictionary = HDB.get_hero(hid)
		var alt_r := String(hero.get("relic_alt", ""))
		if alt_r != "":
			var rd: Dictionary = RDB.get_relic(alt_r)
			_check(not rd.is_empty() and String(rd.get("tier", "")) == "starting",
				"%s relic_alt '%s' is a real starting relic" % [hid, alt_r])
		var alt_d: Dictionary = hero.get("deck_alt", {})
		if not alt_d.is_empty():
			var lst: Array = alt_d.get("deck", [])
			var all_real := lst.size() == 10
			for cid in lst:
				if CDB.get_card_data(String(cid)).is_empty():
					all_real = false
					print("        (unknown card id: %s)" % cid)
			_check(all_real, "%s deck_alt '%s' = 10 real cards" % [hid, alt_d.get("name", "?")])

	# ── 2. MetaState ledger queries (must not create rows) ──
	MS.hero_stats = {}
	_check(MS.hero_wins("raider") == 0 and MS.hero_best_asc("raider") == -1
		and MS.hero_stats.is_empty(),
		"ledger queries default to 0 / -1 without creating rows")
	MS.hero_stats = {"stalwart": {"wins": 2, "losses": 1, "best_asc": 4}}
	_check(MS.hero_wins("stalwart") == 2 and MS.hero_best_asc("stalwart") == 4,
		"ledger queries read the row")

	# ── 3. start_new_run pending overrides ──
	RS.pending_signature_relic = "coin_purse"
	RS.pending_deck_variant = "alt"
	RS.start_new_run("stalwart", 0, 4242)
	var alt_deck: Array = HDB.get_hero("stalwart").deck_alt.deck.duplicate()
	var got_deck: Array = RS.deck.duplicate()
	alt_deck.sort()
	got_deck.sort()
	_check(got_deck == alt_deck, "alt deck built (The Old Legion)")
	_check(RS.relics.size() > 0 and RS.relics[0] == "coin_purse",
		"alt signature relic marched (coin_purse)")
	_check(RS.pending_signature_relic == "" and RS.pending_deck_variant == "",
		"pendings consumed and cleared")
	RS.start_new_run("stalwart", 0, 4242)
	var def_deck: Array = HDB.get_hero("stalwart").deck.duplicate()
	var got2: Array = RS.deck.duplicate()
	def_deck.sort()
	got2.sort()
	_check(got2 == def_deck and RS.relics[0] == "iron_buckler",
		"no pendings -> default deck + signature relic")

	# ── 4. war_school fold (RunState layer) ──
	var ci := _first_creature_index()
	RS.apply_wayside_upgrade(ci, {"path": "war_school", "keyword": "thorns"})
	var folded: Dictionary = RS.get_upgraded_card_data(ci)
	_check((folded.get("keywords", []) as Array).has("thorns")
		and RS.has_upgrade_path(ci, "war_school"),
		"war_school entry folds its keyword")

	# ── 5. Combat catch-up + headless auto-pick offer ──
	RS.start_new_run("raider", 0, 777)
	var gi := _first_creature_index()
	var g_uid: int = RS.deck_uids[gi]
	var base_atk: int = int(CDB.get_card_data(RS.deck[gi]).get("atk", 0))
	RS.creature_kills[g_uid] = 10
	var cb = load("res://scenes/combat.tscn").instantiate()
	cb._queue_war_school_catchup()
	_check(cb._war_school_queue.has(g_uid), "catch-up queues the 10-kill veteran")
	cb._offer_war_school()   # headless -> synchronous first-school auto-pick
	_check(RS.has_upgrade_path(gi, "war_school"), "offer wrote the war_school entry")
	var vfold: Dictionary = RS.get_upgraded_card_data(gi)
	_check((vfold.get("keywords", []) as Array).has("armored"),
		"headless auto-pick granted the first school (Armored)")
	_check(int(vfold.get("atk", 0)) == base_atk + 1,
		"6-kill +1/+1 still folds under the school")
	cb._queue_war_school_catchup()
	_check(cb._war_school_queue.is_empty(), "schooled veteran never re-queued")

	# Honorary case: a veteran already carrying all three schools.
	var bi := -1
	for i in range(RS.deck.size()):
		if i != gi and CDB.get_card_data(RS.deck[i]).get("type", "") == "creature":
			bi = i
			break
	if bi >= 0:
		for kw in ["armored", "swift", "thorns"]:
			RS.apply_wayside_upgrade(bi, {"path": "grant_kw", "keyword": kw})
		RS.creature_kills[RS.deck_uids[bi]] = 10
		cb._queue_war_school_catchup()
		cb._offer_war_school()
		_check(RS.has_upgrade_path(bi, "war_school"),
			"all-three-schools veteran takes the honorary rank (no crash)")
	cb.free()

	# ── 6. Hold a Wake ──
	RS.start_new_run("acolyte", 0, 888)
	var w_uid: int = RS.deck_uids[0]
	var w_id: String = RS.deck[0]
	var w_data: Dictionary = RS.get_upgraded_card_data(0)
	RS.record_fall(w_uid, w_id, "Ratling the Grim", "The Bone Pit", 3)
	RS.record_fall(w_uid, w_id, "Ratling Thrice-Scarred", "The Keep", 5)
	RS.record_fall(-77, "goblin", "Goblin the Lost", "A White Field", 2)
	var rest = load("res://scenes/rest.tscn").instantiate()
	root.add_child(rest)
	await _settle()
	var cands: Array = rest._wake_candidates()
	_check(cands.size() == 2, "roll dedupes by soldier (2 tiles from 3 falls)")
	if cands.size() == 2:
		_check(String(cands[0].entry.get("name", "")) == "Ratling Thrice-Scarred",
			"dedupe keeps the last (most decorated) name")
		_check(int(cands[0].atk) == int(w_data.get("atk", -1))
			and int(cands[0].hp) == int(w_data.get("hp", -1)),
			"marching soldier's shade uses folded stats")
		var gob: Dictionary = CDB.get_card_data("goblin")
		_check(int(cands[1].atk) == int(gob.get("atk", -1))
			and int(cands[1].hp) == int(gob.get("hp", -1)),
			"mustered-out soldier's shade uses printed stats")
		rest._do_wake(cands[1])
		var gift: Dictionary = RS.next_combat_gift_creature
		_check(String(gift.get("name", "")) == "Shade of Goblin the Lost"
			and int(gift.get("atk", -1)) == int(gob.get("atk", -2)),
			"wake queues the shade for the next fight")
	rest.queue_free()
	await _settle()

	# ── wrap ──
	MS.hero_stats = meta_stash
	_restore_saves()
	print("[progression] RESULT: %s — fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
