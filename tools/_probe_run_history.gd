extends Node
## _probe_run_history.gd — the run-history reader against a hostile file.
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_run_history.tscn
##
## RunState has written user://runs.csv for months and until 2026-09-12 nothing
## read it. A reader is a new attack surface on a file that lives in user://,
## can be hand-edited, can be truncated by a crash mid-write, and — after this
## session's schema bump — can be sitting in an older shape than the code
## expects. The project already has a whole class for this (C21, run_chaos_save)
## whose founding observation is that a reader which trusts its input IS the
## bug, so the gate is written the same way: feed it wrong files, and require
## that it neither crashes NOR invents a run that did not happen.
##
## Runs as a SCENE, not --script: RunState is an autoload and the reader is a
## method on it.
##
## APPDATA ISOLATION IS MANDATORY — this probe writes garbage into user://.
## The runner must point APPDATA at a temp dir first (GODOT_USER_HOME is a
## no-op on Windows), and the probe refuses to run without evidence of it.

const PROBE_NAME := "run_history"

## The header as it stood BEFORE the 2026-09-12 bump. Rows written under it have
## no elapsed_seconds, no deck_cards and no relic_ids, and its relic COUNT is
## spelled `relics`. The reader must serve what such a row does carry and must
## report the rest as ABSENT — not as zero.
const LEGACY_HEADER := ("ended_at,result,hero,ascension,seed,act," +
	"floor,hp,max_hp,gold,fights_won,deck_size,relics,cause_of_death," +
	"rival_act1,rival_act2,rival_act3,finale_rival,holds_broken_run")

var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	if not _isolated():
		printerr("[%s] FATAL: APPDATA is not isolated — refusing to write "
			% PROBE_NAME + "garbage into the developer's real user:// data.")
		printerr("PROBE FAIL: %s" % PROBE_NAME)
		get_tree().quit(1)
		return
	_clean_logs()
	_test_missing_file()
	_test_current_schema_round_trip()
	_test_legacy_header()
	_test_malformed_rows()
	_test_no_header()
	_test_shelving_and_merge()
	_test_writer_columns()
	_clean_logs()

	print("[%s] %d checks" % [PROBE_NAME, _checks])
	if _fails.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for failure in _fails:
		printerr("[%s] FAIL: %s" % [PROBE_NAME, failure])
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, _fails.size()])
	get_tree().quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails.append(label)


## A real APPDATA would put user:// under the developer's roaming profile with
## their actual saves in it. The runner is expected to have moved it to a temp
## dir; refuse rather than guess.
func _isolated() -> bool:
	var dir := OS.get_user_data_dir().to_lower()
	if dir.contains("temp") or dir.contains("tmp"):
		return true
	# A CI box may legitimately have a clean profile. Accept one that has never
	# held a real run: no save slots and no existing run log.
	if FileAccess.file_exists("user://runs.csv"):
		return false
	for slot in range(3):
		if FileAccess.file_exists("user://run_%d.save" % slot):
			return false
	return true


func _clean_logs() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var doomed: Array[String] = []
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("runs") \
				and entry.ends_with(".csv"):
			doomed.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in doomed:
		dir.remove(name)


func _write_log(lines: Array) -> void:
	var f := FileAccess.open("user://runs.csv", FileAccess.WRITE)
	for line in lines:
		f.store_line(String(line))
	f.close()


# ─────────────────────────────────────────────────────────────────────────────

func _test_missing_file() -> void:
	print("— no log at all")
	_clean_logs()
	var rows := RunState.read_run_history()
	_check(rows.is_empty(), "no log file reads as zero runs, not an error")


func _test_current_schema_round_trip() -> void:
	print("— current schema")
	_clean_logs()
	_write_log([
		RunState._RUN_LOG_HEADER,
		"2026-09-11T09:15:00,victory,kindler,3,881,3,17,22,30,410,7,2731," +
		"24,ember;ember;ash_wight,2,cavalry_sigil;whetstone,," +
		"raider,acolyte,stalwart,pyromancer,6",
		"2026-09-10T21:04:33,defeat,raider,0,42,2,9,0,30,85,3,1580," +
		"16,strike;strike,1,bone_pile,The Pyre Cult," +
		"acolyte,stalwart,kindler,pyromancer,2",
	])
	var rows := RunState.read_run_history()
	_check(rows.size() == 2, "both well-formed rows read (got %d)" % rows.size())
	if rows.size() != 2:
		return
	# Newest first.
	_check(String(rows[0].get("ended_at", "")).begins_with("2026-09-11"),
		"rows are sorted newest first")
	var win: Dictionary = rows[0]
	var loss: Dictionary = rows[1]
	_check(String(win.get("result", "")) == "victory", "result reads back")
	_check(String(win.get("hero", "")) == "kindler", "hero reads back")
	_check(int(win.get("seed", -1)) == 881, "seed reads back")
	_check(int(win.get("elapsed_seconds", 0)) == 2731,
		"elapsed_seconds reads back (the new column)")
	_check(int(win.get("deck_size", 0)) == 24, "deck_size reads back")
	var deck: PackedStringArray = win.get("deck_cards", PackedStringArray())
	_check(deck.size() == 3 and String(deck[2]) == "ash_wight",
		"deck_cards reads back as a LIST, not a count")
	var rel: PackedStringArray = win.get("relic_ids", PackedStringArray())
	_check(rel.size() == 2 and String(rel[0]) == "cavalry_sigil",
		"relic_ids reads back as a list")
	_check(int(win.get("relic_count", -1)) == 2, "relic_count reads back")
	_check(String(win.get("cause_of_death", "")) == "",
		"an empty cause cell stays empty")
	_check(String(loss.get("cause_of_death", "")) == "The Pyre Cult",
		"cause_of_death reads back")
	var rivals: PackedStringArray = loss.get("rivals", PackedStringArray())
	_check(rivals.size() == 3, "the three rival columns collapse into a list")
	_check(RunState.run_history_has(win, "elapsed_seconds"),
		"a present column reports present")


func _test_legacy_header() -> void:
	print("— legacy header (pre-2026-09-12 schema)")
	_clean_logs()
	_write_log([
		LEGACY_HEADER,
		"2026-08-01T12:00:00,defeat,acolyte,2,777,2,11,0,30,120,4,19,5," +
		"The Bone Choir,raider,stalwart,kindler,pyromancer,3",
		"2026-07-30T08:30:00,victory,stalwart,1,555,3,17,14,30,300,7,21,6," +
		",kindler,raider,acolyte,pyromancer,7",
	])
	var rows := RunState.read_run_history()
	_check(rows.size() == 2, "legacy rows still read (got %d)" % rows.size())
	if rows.size() != 2:
		return
	var rec: Dictionary = rows[0]
	_check(String(rec.get("hero", "")) == "acolyte",
		"a column the legacy header DOES have reads correctly")
	_check(int(rec.get("gold", -1)) == 120, "legacy gold reads correctly")
	_check(String(rec.get("cause_of_death", "")) == "The Bone Choir",
		"legacy cause_of_death lands in the right column")
	# `relics` was the count column's old name.
	_check(int(rec.get("relic_count", -1)) == 5,
		"the renamed relic count is read under its old spelling too")
	_check(RunState.run_history_has(rec, "relic_count"),
		"the renamed count reports present under the CANONICAL key")
	# The three columns the bump added.
	_check(not RunState.run_history_has(rec, "elapsed_seconds"),
		"elapsed_seconds reports ABSENT on a legacy row")
	_check(int(rec.get("elapsed_seconds", -1)) == 0,
		"an absent elapsed_seconds defaults to 0, not to junk")
	var deck: PackedStringArray = rec.get("deck_cards", PackedStringArray())
	_check(deck.is_empty(), "deck_cards is empty on a legacy row")
	_check(not RunState.run_history_has(rec, "deck_cards"),
		"deck_cards reports ABSENT on a legacy row")


func _test_malformed_rows() -> void:
	print("— truncated, garbled and hostile rows")
	_clean_logs()
	_write_log([
		RunState._RUN_LOG_HEADER,
		# 1. Good row, to prove the file is still readable around the damage.
		"2026-09-09T10:00:00,victory,raider,0,10,3,17,20,30,200,7,1200," +
		"20,strike,1,whetstone,,acolyte,stalwart,kindler,pyromancer,5",
		# 2. Truncated mid-write — the row stops after six cells.
		"2026-09-08T10:00:00,defeat,raider,0,11,2",
		# 3. Truncated mid-CELL, which is what a killed process actually leaves.
		"2026-09-07T10:00:00,defeat,raid",
		# 4. Numbers that are not numbers.
		"2026-09-06T10:00:00,defeat,raider,many,banana,three,-,x,y,lots,z," +
		"soon,big,strike,two,whetstone,,acolyte,stalwart,kindler,pyro,none",
		# 5. Pure garbage with no run in it at all.
		"@@@@@@@@",
		# 6. Commas only.
		",,,,,,,,,,,,,,,,,,,,,",
		# 7. A row LONGER than the header.
		"2026-09-05T10:00:00,victory,stalwart,1,12,3,17,25,30,150,7,900," +
		"18,strike,0,,,acolyte,raider,kindler,pyromancer,4,EXTRA,MORE,STUFF",
		# 8. A blank line in the middle of the file.
		"",
	])
	var rows := RunState.read_run_history()

	# Nothing crashed getting here — that is the first assertion.
	_check(true, "reader survives a file of malformed rows without crashing")

	var by_seed: Dictionary = {}
	for r in rows:
		by_seed[int(r.get("seed", -1))] = r

	_check(by_seed.has(10), "the good row before the damage still reads")
	_check(by_seed.has(12), "the good row AFTER the damage still reads")
	_check(int(by_seed.get(12, {}).get("fights_won", -1)) == 7,
		"an over-long row reads correctly and drops its unnamed extras")

	# Rows 5 and 6 are not runs and must not become runs.
	for r in rows:
		var stamp := String(r.get("ended_at", ""))
		_check(stamp != "@@@@@@@@", "garbage line is not filed as a run")
		break
	var stamps: Array[String] = []
	for r in rows:
		stamps.append(String(r.get("ended_at", "")))
	_check(not stamps.has("@@@@@@@@"), "the garbage line produced no record")
	_check(not stamps.has(""), "the all-commas line produced no record")

	# The truncated rows: kept (they carry a real stamp and result) but the
	# columns that never arrived must read as ABSENT, never as zero.
	var trunc: Dictionary = {}
	for r in rows:
		if String(r.get("ended_at", "")) == "2026-09-08T10:00:00":
			trunc = r
	_check(not trunc.is_empty(), "a truncated row is still identified as a run")
	if not trunc.is_empty():
		_check(String(trunc.get("hero", "")) == "raider",
			"the cells a truncated row DID carry are read")
		_check(not RunState.run_history_has(trunc, "gold"),
			"a column the truncated row never reached reports ABSENT")
		_check(int(trunc.get("gold", -1)) == 0,
			"an absent number defaults to 0 rather than to junk")
		_check(not RunState.run_history_has(trunc, "fights_won"),
			"fights_won reports ABSENT on the truncated row")

	# The mid-cell truncation: "raid" is a partial hero id, and the row still
	# has a valid stamp, so it is a run — with almost nothing known about it.
	var half: Dictionary = {}
	for r in rows:
		if String(r.get("ended_at", "")) == "2026-09-07T10:00:00":
			half = r
	_check(not half.is_empty(), "a row cut inside a cell is still read")
	if not half.is_empty():
		_check(not RunState.run_history_has(half, "seed"),
			"the mid-cell row claims no seed")

	# The nonsense-numbers row: every numeric cell must report ABSENT, because
	# String.to_int() answers 0 for "banana" and a run that reads "0 gold" it
	# never had is invented data.
	var junk: Dictionary = {}
	for r in rows:
		if String(r.get("ended_at", "")) == "2026-09-06T10:00:00":
			junk = r
	_check(not junk.is_empty(), "the nonsense-numbers row is still a run")
	if not junk.is_empty():
		for key in ["ascension", "seed", "act", "floor", "hp", "max_hp",
				"gold", "fights_won", "elapsed_seconds", "deck_size"]:
			_check(not RunState.run_history_has(junk, String(key)),
				"unparseable '%s' reports ABSENT, not coerced to 0" % key)
			_check(int(junk.get(String(key), -1)) == 0,
				"unparseable '%s' defaults to 0" % key)
		_check(String(junk.get("hero", "")) == "raider",
			"the STRING cells of the nonsense row still read")


func _test_no_header() -> void:
	print("— a file that lost its header")
	_clean_logs()
	# Data rows with no header line. Guessing their column order against
	# today's header would file a run's numbers under the wrong names.
	_write_log([
		"2026-09-04T10:00:00,victory,raider,0,10,3,17,20,30,200,7",
		"2026-09-03T10:00:00,defeat,acolyte,1,11,2,9,0,30,50,3",
	])
	var rows := RunState.read_run_history()
	_check(rows.is_empty(),
		"an unlabelled file is skipped whole rather than guessed (got %d rows)"
			% rows.size())


func _test_shelving_and_merge() -> void:
	print("— header migration: shelving, and the shelf still being readable")
	_clean_logs()
	_write_log([
		LEGACY_HEADER,
		"2026-06-01T10:00:00,defeat,pyromancer,0,99,1,3,0,30,60,1,14,2," +
		"Roadside Levy,raider,acolyte,stalwart,kindler,1",
	])
	# A finished run under the new schema must shelve the old file, not mix.
	RunState.start_new_run("kindler", 0, 5150)
	RunState._append_run_log(false)

	var live := FileAccess.open("user://runs.csv", FileAccess.READ)
	var header := live.get_line()
	var first_row := live.get_line()
	live.close()
	_check(header == RunState._RUN_LOG_HEADER,
		"the live log carries the CURRENT header after migration")
	_check(first_row.split(",").size() == RunState._RUN_LOG_HEADER.split(",").size(),
		"the new row has exactly as many cells as the header has columns")
	_check(not first_row.contains("Roadside Levy"),
		"the old row was shelved, not appended under the new header")

	var shelved := 0
	var dir := DirAccess.open("user://")
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("runs_legacy_") and entry.ends_with(".csv"):
			shelved += 1
		entry = dir.get_next()
	dir.list_dir_end()
	_check(shelved == 1, "exactly one shelf file was created (got %d)" % shelved)

	# The reader merges the shelf back in, so a schema bump costs the columns
	# it added rather than the whole history.
	var rows := RunState.read_run_history()
	_check(rows.size() == 2,
		"the shelved run is still visible in history (got %d)" % rows.size())
	var found_old := false
	for r in rows:
		if String(r.get("cause_of_death", "")) == "Roadside Levy":
			found_old = true
			_check(not RunState.run_history_has(r, "elapsed_seconds"),
				"the shelved row honestly reports no elapsed time")
	_check(found_old, "the pre-bump run reads out of the shelf file")

	# Two shelvings inside one second must not collide. rename_absolute onto an
	# existing path fails on Windows, which would leave the stale file sitting
	# at runs.csv with new-schema rows appended under its old header.
	_write_log([LEGACY_HEADER,
		"2026-05-01T10:00:00,defeat,raider,0,7,1,2,0,30,20,0,12,1,x," +
		"acolyte,stalwart,kindler,pyromancer,0"])
	RunState._append_run_log(false)
	var live2 := FileAccess.open("user://runs.csv", FileAccess.READ)
	var header2 := live2.get_line()
	live2.close()
	_check(header2 == RunState._RUN_LOG_HEADER,
		"a second same-second shelving still leaves a current-header log")


func _test_writer_columns() -> void:
	print("— the writer's own row")
	_clean_logs()
	RunState.start_new_run("raider", 0, 4242)
	RunState.hero_hp = 0
	RunState.cause_of_death = "A Very, Comma-Full Name"
	RunState._append_run_log(false)
	var rows := RunState.read_run_history()
	_check(rows.size() == 1, "the writer's row reads back (got %d)" % rows.size())
	if rows.is_empty():
		return
	var rec: Dictionary = rows[0]
	_check(String(rec.get("result", "")) == "defeat",
		"a dead hero records as a defeat")
	_check(int(rec.get("seed", 0)) == 4242, "the seed round-trips")
	var deck: PackedStringArray = rec.get("deck_cards", PackedStringArray())
	_check(deck.size() == int(rec.get("deck_size", -1)) and deck.size() > 0,
		"deck_cards lists exactly as many ids as deck_size counts")
	_check(not String(rec.get("cause_of_death", "")).contains(","),
		"a comma in a cause name cannot break the row into extra columns")
	_check(String(rec.get("cause_of_death", "")).contains("Comma-Full"),
		"the sanitised cause is still readable")

	# The abandon path: end_run(false) with the hero ALIVE.
	_clean_logs()
	RunState.start_new_run("stalwart", 0, 313)
	RunState._append_run_log(false)
	var quit_rows := RunState.read_run_history()
	_check(quit_rows.size() == 1, "the abandoned row reads back")
	if not quit_rows.is_empty():
		_check(String(quit_rows[0].get("result", "")) == "abandoned",
			"a run ended with the hero alive records as ABANDONED, not defeat")
