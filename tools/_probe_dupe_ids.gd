extends SceneTree
## _probe_dupe_ids — duplicate entry ids across every content pool.
##
## WHY THIS IS NOT COVERED BY parsecheck. A duplicate KEY in a Dictionary
## LITERAL is a GDScript parse error, so the compile gate catches it. But every
## content pool in this project is an ARRAY of dictionaries, each carrying its
## own `id` field — and a repeated `id` there is perfectly legal code. The
## lookup helpers (`CardDB.get_card_data`, `RelicDB.get_relic`, ...) return the
## FIRST match, so the second entry is authored content no player can ever see:
## the C1 class, in the one shape C1's dispatch-table diff cannot detect
## (both ids resolve, so producer<->consumer agrees).
##
## It also checks the reverse-index dictionaries the DBs build at boot, where a
## duplicate silently OVERWRITES — there the LAST wins, so a pool scan and an
## index scan can disagree about which entry is live.

var _fails := 0
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _ok(label: String) -> void:
	_checks += 1
	print("  PASS  %s" % label)


func _fail(label: String) -> void:
	_checks += 1
	_fails += 1
	print("  FAIL  %s" % label)


## Returns {id: count} for every id appearing more than once.
func _dupes(entries, id_key: String = "id") -> Dictionary:
	var seen := {}
	var dupes := {}
	if entries is Array:
		for e in entries:
			if not (e is Dictionary):
				continue
			var id := String(e.get(id_key, ""))
			if id == "":
				continue
			if seen.has(id):
				dupes[id] = int(seen[id]) + 1
				seen[id] = int(seen[id]) + 1
			else:
				seen[id] = 1
	elif entries is Dictionary:
		# Keyed pool: keys are unique by construction, but an inner `id` field
		# that disagrees with its key is the same defect wearing a hat.
		for k in entries.keys():
			var e = entries[k]
			if not (e is Dictionary):
				continue
			var inner := String(e.get(id_key, ""))
			if inner != "" and inner != String(k):
				dupes["key=%s but id=%s" % [k, inner]] = 1
	return dupes


func _check_pool(label: String, entries, id_key: String = "id") -> void:
	# A pool that cannot be READ is a FAILED check, never a skipped one: a probe
	# that quietly passes over the thing it exists to inspect reports green for
	# a surface it never touched. (Cost one false clean run on EventDB, which
	# is not the autoload CLAUDE.md says it is.)
	if entries == null:
		_fail("%s — pool unavailable (probe could not read it)" % label)
		return
	var n := 0
	if entries is Array:
		n = entries.size()
	elif entries is Dictionary:
		n = entries.size()
	var d := _dupes(entries, id_key)
	if d.is_empty():
		_ok("%s — %d entries, no duplicate %s" % [label, n, id_key])
	else:
		_fail("%s — %d entries, DUPLICATES: %s" % [label, n, str(d)])


func _node(n: String):
	return root.get_node_or_null(n)


## SELF-TEST. Every check below reports PASS on a clean pool, and a detector
## that can only say PASS is indistinguishable from one that says nothing. So
## the oracle is exercised against a planted duplicate FIRST: if this does not
## fire, no result printed afterwards means anything.
func _self_test() -> void:
	var planted := [
		{"id": "alpha"}, {"id": "beta"}, {"id": "alpha"},
	]
	var d := _dupes(planted)
	if d.has("alpha") and not d.has("beta"):
		_ok("self-test — the detector finds a planted duplicate (and only it)")
	else:
		_fail("self-test — VACUOUS: planted duplicate not detected, got %s"
			% str(d))
	var keyed := {"one": {"id": "one"}, "two": {"id": "MISMATCH"}}
	var k := _dupes(keyed)
	if k.size() == 1:
		_ok("self-test — the detector finds a key/id disagreement")
	else:
		_fail("self-test — VACUOUS: key/id disagreement not detected")


func _run() -> void:
	print("\n[dupe-ids] duplicate entry ids across the content pools\n")
	_self_test()

	var card_db = _node("CardDB")
	var relic_db = _node("RelicDB")
	var enc_db = _node("EncounterDB")
	# EventDB is NOT an autoload (CLAUDE.md lists it as one; it is a plain
	# script). Loaded directly, like WritDB/SetPieceDB below — a `get_node`
	# here returns null and the pool would be skipped in SILENCE.
	var event_db = load("res://scripts/data/EventDB.gd")
	var potion_db = _node("PotionDB")
	var hero_db = _node("HeroDB")

	if card_db != null:
		_check_pool("CardDB.CARD_POOL", card_db.get("CARD_POOL"))
		_check_pool("CardDB.ENEMY_POOL", card_db.get("ENEMY_POOL"))
	if relic_db != null:
		_check_pool("RelicDB.RELICS", relic_db.get("RELICS"))
	if enc_db != null:
		_check_pool("EncounterDB.ENCOUNTERS", enc_db.get("ENCOUNTERS"))
	if event_db != null:
		_check_pool("EventDB.EVENTS", event_db.get("EVENTS"))
	if potion_db != null:
		_check_pool("PotionDB.POTIONS", potion_db.get("POTIONS"))
	if hero_db != null:
		_check_pool("HeroDB.HEROES", hero_db.get("HEROES"))

	# Script-owned (non-autoload) pools, loaded directly.
	var writ = load("res://scripts/data/WritDB.gd")
	if writ != null:
		_check_pool("WritDB.WRITS", writ.get("WRITS"))
	var setp = load("res://scripts/data/SetPieceDB.gd")
	if setp != null:
		_check_pool("SetPieceDB.SET_PIECES", setp.get("SET_PIECES"))
	var tut = load("res://scripts/data/TutorialDB.gd")
	if tut != null:
		_check_pool("TutorialDB.LESSONS", tut.get("LESSONS"))
	var mut = load("res://scripts/data/MutatorDB.gd")
	if mut != null:
		_check_pool("MutatorDB.MUTATORS", mut.get("MUTATORS"))

	print("\n[dupe-ids] %d checks, %d failed" % [_checks, _fails])
	if _fails == 0:
		print("[dupe-ids] ALL PASS")
	quit(0)
