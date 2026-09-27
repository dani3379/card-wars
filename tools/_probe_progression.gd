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
var _save_existed: Array[bool] = []


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _snapshot_saves() -> void:
	_save_existed.clear()
	_save_existed.resize(3)
	for i in range(3):
		var p := "user://run_%d.save" % i
		_save_existed[i] = FileAccess.file_exists(p)
		if _save_existed[i]:
			DirAccess.copy_absolute(p, p + ".progbak")


func _restore_saves() -> void:
	for i in range(3):
		var b := "user://run_%d.save.progbak" % i
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, "user://run_%d.save" % i)
			DirAccess.remove_absolute(b)


		elif i < _save_existed.size() and not _save_existed[i]:
			var p := "user://run_%d.save" % i
			if FileAccess.file_exists(p): DirAccess.remove_absolute(p)

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



func _unique_count(cards: Array) -> int:
	var seen: Dictionary = {}
	for cid in cards:
		seen[String(cid)] = true
	return seen.size()


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
	var active_slot_stash: int = RS.active_slot
	var doctrine_hero_id := ""

	# ── 1. Muster data integrity: every alt resolves ──
	for hid in HDB.HEROES:
		var hero: Dictionary = HDB.get_hero(hid)
		var alt_r := String(hero.get("relic_alt", ""))
		var default_deck: Array = hero.get("deck", [])
		var default_real := default_deck.size() == 10
		for cid in default_deck:
			if CDB.get_card_data(String(cid)).is_empty():
				default_real = false
		_check(default_real and _unique_count(default_deck) >= 9,
			"%s default deck = 10 real cards / at least 9 unique" % hid)

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
			_check(_unique_count(lst) >= 9,
				"%s deck_alt has at least 9 unique cards" % hid)
			if doctrine_hero_id == "" and alt_r != "":
				doctrine_hero_id = String(hid)
	_check(doctrine_hero_id != "", "at least one complete alternate doctrine exists")
	var scalar_cases := {
		"spur_forward": "atk_bonus", "close_ranks_order": "hp_bonus",
		"glass_savant": "spell_ping_bonus", "star_chart": "extra_reveal",
		"fuse_tender": "doom_atk_bonus", "touchpaper": "doom_tick",
	}
	for card_id in scalar_cases:
		var preview: Dictionary = RS.preview_plus_upgrade(CDB.get_card_data(card_id))
		var field: String = scalar_cases[card_id]
		_check(int(preview.get(field, 0)) > 0, "%s+ exposes %s" % [card_id, field])

	# ── 2. MetaState ledger queries (must not create rows) ──
	MS.hero_stats = {}
	_check(MS.hero_wins(doctrine_hero_id) == 0 and MS.hero_best_asc(doctrine_hero_id) == -1
		and MS.hero_stats.is_empty(),
		"ledger queries default to 0 / -1 without creating rows")
	MS.hero_stats[doctrine_hero_id] = {"wins": 1, "losses": 1, "best_asc": 0}
	_check(MS.hero_wins(doctrine_hero_id) == 1 and MS.hero_best_asc(doctrine_hero_id) == 0,
		"first win unlocks the bound doctrine")

	# ── 3. start_new_run pending overrides ──
	var doctrine_hero: Dictionary = HDB.get_hero(doctrine_hero_id)
	var alt_info: Dictionary = doctrine_hero.get("deck_alt", {})
	var alt_relic := String(doctrine_hero.get("relic_alt", ""))
	var default_relic := String(doctrine_hero.get("relic", ""))

	# (A banner card was appended to both expectations here from 2026-07-30 until
	# 2026-09-16: opening_deck_for used to add one authored levy card on top of
	# the hero's ten. With the banner system gone, an opener is the raw HeroDB
	# list again.)
	RS.pending_signature_relic = alt_relic
	RS.pending_deck_variant = "alt"
	RS.start_new_run(doctrine_hero_id, 0, 4242)
	var alt_deck: Array = (alt_info.get("deck", []) as Array).duplicate()
	var got_deck: Array = RS.deck.duplicate()
	alt_deck.sort()
	got_deck.sort()
	_check(got_deck == alt_deck, "first-win bound doctrine builds its alternate deck")
	_check(RS.relics.has(alt_relic),
		"first-win bound doctrine marches its alternate relic")
	_check(RS.pending_signature_relic == "" and RS.pending_deck_variant == "",
		"pendings consumed and cleared")
	_check(RS.current_deck_variant == "alt" and RS.current_signature_relic == alt_relic,
		"bound doctrine records both selections")
	RS.pending_deck_variant = "alt"
	RS.start_new_run(doctrine_hero_id, 0, 4242)
	var def_deck: Array = (doctrine_hero.get("deck", []) as Array).duplicate()
	var got2: Array = RS.deck.duplicate()
	def_deck.sort()
	got2.sort()
	_check(got2 == def_deck and RS.relics.has(default_relic),
		"before Ascension 4 one-axis doctrine requests fall back to Standard")
	MS.hero_stats[doctrine_hero_id]["wins"] = 2
	MS.hero_stats[doctrine_hero_id]["best_asc"] = 4
	RS.pending_deck_variant = "alt"
	RS.start_new_run(doctrine_hero_id, 0, 4242)
	var got3: Array = RS.deck.duplicate()
	got3.sort()
	_check(got3 == alt_deck and RS.relics.has(default_relic),
		"Ascension 4 permits alternate deck + default relic")
	_check(RS.current_deck_variant == "alt" and RS.current_signature_relic == default_relic,
		"mixed doctrine records independent selections")

	RS.active_slot = 2
	RS.save_run()
	var saved: Dictionary = RS._read_slot(2)
	_check(String(saved.get("current_deck_variant", "")) == "alt"
		and String(saved.get("current_signature_relic", "")) == default_relic,
		"save payload carries doctrine selections")
	RS.current_deck_variant = ""
	RS.current_signature_relic = ""
	RS.relics.clear()
	_check(RS.load_run(2), "doctrine save reloads")
	_check(RS.current_deck_variant == "alt" and RS.current_signature_relic == default_relic,
		"load restores doctrine selections")

	RS.pending_signature_relic = alt_relic
	RS.start_new_run(doctrine_hero_id, 0, 4242)
	var got4: Array = RS.deck.duplicate()
	got4.sort()
	_check(got4 == def_deck and RS.relics.has(alt_relic),
		"Ascension 4 permits default deck + alternate relic")


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

	# ── 5b. THE LADDER MOVED FORWARD (2026-07-30) ──
	# The choosing rung is now the FIRST one, and a second, tribe-shaped choice
	# took over the tenth. Both facts are asserted, because the whole point of the
	# change was that the old rung-3 choice fired too rarely to matter.
	_check(RS.veteran_school_kills() == RS.veteran_epithet_kills(),
		"the war school rides the epithet rung")
	_check(RS.veteran_doctrine_kills() > RS.veteran_school_kills(),
		"the doctrine sits above the school")
	_check(RS.veteran_doctrine_kills() == RS.VETERAN_DOCTRINE_KILLS,
		"the doctrine took over the threshold the school vacated")
	# Every tribe offers a pair, none of it overlapping the universal three, and
	# every keyword is one the project already vets as grantable.
	var schools: Array = []
	for s in cb.WAR_SCHOOLS:
		schools.append(String(s.kw))
	for ct in ["soldier", "beast", "dead", "warlock", "bastion", "stray"]:
		_check(cb.WAR_DOCTRINES.has(ct), "tribe '%s' has a doctrine pair" % ct)
		if not cb.WAR_DOCTRINES.has(ct):
			continue
		var pair: Array = cb.WAR_DOCTRINES[ct]
		_check(pair.size() == 2, "tribe '%s' offers exactly two" % ct)
		for d in pair:
			var kw := String(d.kw)
			_check(not (kw in schools),
				"'%s' doctrine '%s' does not repeat a war school" % [ct, kw])
			_check(kw in cb.DEFECTION_STEALABLE,
				"'%s' doctrine '%s' is a vetted persistent grant" % [ct, kw])
			_check(String(d.school) != "", "'%s' doctrine '%s' is named" % [ct, kw])
	# An untyped creature must still be offered something.
	_check(not cb._doctrines_for({}).is_empty(),
		"an untyped veteran falls back to the universal three")
	# A COLLAPSED PAIR MUST BACKFILL. Guardian is printed on several Soldiers and
	# Bastions, so those creatures reach the rung with one of their two options
	# already filtered out — and a one-tile "choice" is a fake decision. Asserted
	# on the source because the top-up happens inside the modal drain.
	var mmsrc := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	_check("if options.size() == 1:" in mmsrc,
		"a collapsed doctrine pair is topped up rather than shown as one tile")
	cb.free()

	# Drive the real rung on a real deck creature.
	RS.start_new_run("stalwart", 0, 4242)
	var di := _first_creature_index()
	var d_uid: int = RS.deck_uids[di]
	RS.creature_kills[d_uid] = RS.veteran_doctrine_kills()
	var cb2 = load("res://scenes/combat.tscn").instantiate()
	cb2._queue_doctrine_catchup()
	_check(cb2._doctrine_queue.has(d_uid), "catch-up queues the doctrine veteran")
	cb2._offer_doctrine()   # headless -> first option, no click needed
	_check(RS.has_upgrade_path(di, "doctrine"), "offer wrote the doctrine entry")
	var dfold: Dictionary = RS.get_upgraded_card_data(di)
	var want: Array = cb2._doctrines_for(CDB.get_card_data(RS.deck[di]))
	_check((dfold.get("keywords", []) as Array).has(String(want[0].kw)),
		"the doctrine keyword folded onto the card")
	cb2._queue_doctrine_catchup()
	_check(cb2._doctrine_queue.is_empty(), "a specialised veteran never re-queues")
	# A doctrine must not satisfy the school, or a card could skip a rung.
	_check(not RS.has_upgrade_path(di, "war_school"),
		"the doctrine entry does not answer for the war school")
	cb2.free()

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
	RS.active_slot = active_slot_stash
	_restore_saves()
	print("[progression] RESULT: %s — fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)
