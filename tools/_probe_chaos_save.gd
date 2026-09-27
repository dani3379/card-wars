extends SceneTree
## _probe_chaos_save.gd — PASS 21 of docs/BUG_SWEEP_METHOD_20260829.md (class C21).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_chaos_save.gd
##
## CHAOS / FAULT INJECTION — the ENVIRONMENT fails, not the code.
##
## Mutation testing (C12) breaks the PROGRAM to see whether the gates notice.
## Fuzzing (C13) feeds a hostile PAYLOAD across the one trust boundary. Neither
## touches the third thing that fails in the real world and never fails in a test:
## the machine underneath. A save file truncated by a power cut mid-write, a JSON
## file whose numbers arrived as strings, a save written by an older build with
## half the keys missing, a disk that will not accept a write at all.
##
## This is the class the player experiences as "MY RUN IS GONE", which is the worst
## bug a roguelike can ship, and nothing in this suite has ever pointed at it.
## `_probe_persistence` (C8) round-trips WELL-FORMED saves and proves the fields
## survive; it never asks what happens when the file is wrong.
##
## THE CONTRACT BEING TESTED, in order of how much it matters:
##   1. NEVER CRASH. A corrupt file is a bad day, not a stack trace.
##   2. NEVER SILENTLY DESTROY A GOOD SAVE. If the primary is unreadable and a
##      backup exists, the backup must be used — that is the entire reason
##      SaveIO keeps one.
##   3. FAIL HONESTLY. `load_run()` returning true on a file it could not read is
##      worse than returning false: the game proceeds on an empty run.
##
## SAFETY: this pass writes garbage into `user://`, so it runs against an ISOLATED
## user directory. On Windows `GODOT_USER_HOME` is a no-op (see the memory note) —
## the driver sets APPDATA. If the isolation is not in place the probe REFUSES to
## run rather than eat the developer's real saves.

var RS: Node
var MS: Node
var US: Node
var _started := false
var _done := false
var _fails := 0
var _crashes: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


## Every way a save file goes wrong in the wild.
func _corruptions(good: String) -> Array:
	var half := good.substr(0, maxi(1, good.length() / 2))
	return [
		{"name": "truncated mid-write (power cut)", "text": half},
		{"name": "empty file", "text": ""},
		{"name": "whitespace only", "text": "   \n\t "},
		{"name": "not JSON at all", "text": "<<<not json>>>"},
		{"name": "valid JSON, wrong shape (array)", "text": "[1,2,3]"},
		{"name": "valid JSON, wrong shape (scalar)", "text": "42"},
		{"name": "JSON null", "text": "null"},
		{"name": "empty object (every key missing)", "text": "{}"},
		{"name": "numbers arrived as strings",
			"text": good.replace(": 3", ": \"3\"").replace(": 0", ": \"0\"")},
		{"name": "nulls where values were",
			"text": good.replace(": 3", ": null").replace(": 0", ": null")},
		{"name": "deeply nested garbage",
			"text": "{\"deck\": {\"deck\": {\"deck\": [[[[1]]]]}}}"},
		{"name": "trailing garbage after valid JSON", "text": good + "}}}garbage"},
		{"name": "NaN / Inf smuggled in",
			"text": good.replace(": 3", ": 1e999")},
		{"name": "unicode / control bytes",
			"text": good.substr(0, maxi(1, good.length() / 3)) + "\u0000\uffff\u202e"},
	]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Drive one loader against every corruption and require it to survive each.
func _torture(label: String, path: String, seed_good: Callable,
		loader: Callable, sane: Callable, diag = null) -> void:
	print("\n[chaos] --- %s (%s) ---" % [label, path])
	seed_good.call()
	var good := _read(path)
	if good.strip_edges() == "":
		_check(false, "%s: could not produce a good save to corrupt" % label)
		return
	_check(true, "%s: baseline save written (%d bytes)" % [label, good.length()])

	var survived := 0
	var cases := _corruptions(good)
	for c in cases:
		_write(path, String(c["text"]))
		# Remove any backup so this measures the PRIMARY path. The backup is
		# tested separately below — mixing them would let a healthy backup hide a
		# loader that cannot cope with a bad primary.
		_rm(path + ".bak")
		var ok = loader.call()
		# The bar is: it returned, and the object it left behind is still sane
		# enough to keep playing with. A loader that returns while leaving
		# nonsense in RunState has not really survived.
		if not sane.call():
			_fails += 1
			_crashes.append("%s / %s: loader returned but left unusable state"
				% [label, c["name"]])
			print("  FAIL  %-42s left unusable state  [%s]" % [String(c["name"]),
				(diag.call() if diag != null else "")])
		else:
			survived += 1
			print("  ok    %-42s handled (returned %s)" % [String(c["name"]), str(ok)])
	_check(survived == cases.size(),
		"%s: survived all %d corruptions" % [label, cases.size()])


func _run() -> void:
	print("[chaos] PASS 21 — the environment fails: corrupt saves, absent files\n")
	RS = root.get_node_or_null("RunState")
	MS = root.get_node_or_null("MetaState")
	US = root.get_node_or_null("UserSettings")
	if RS == null or MS == null or US == null:
		print("[chaos] FATAL: state autoloads missing"); _done = true; quit(1); return

	# REFUSE TO EAT REAL SAVES. `user://` must be a throwaway directory.
	var real := ProjectSettings.globalize_path("user://")
	if OS.get_environment("BM_CHAOS_OK") != "1":
		print("[chaos] REFUSING to run: this pass writes garbage into user://")
		print("[chaos]   user:// currently resolves to: %s" % real)
		print("[chaos]   Run it through tools/run_chaos_save.sh, which points")
		print("[chaos]   APPDATA at a temp dir first (GODOT_USER_HOME is a no-op")
		print("[chaos]   on Windows), or set BM_CHAOS_OK=1 if you are certain.")
		_done = true
		quit(2)
		return
	print("[chaos] user:// -> %s\n" % real)

	# ── RUN SAVE ────────────────────────────────────────────────────────────
	# The real path is slot-based (`user://run_<slot>.save`); `user://run.save` is
	# only the LEGACY path kept for migration. And `save_run` refuses to write at
	# all unless a slot has been claimed — a probe that calls `start_new_run`
	# without going through the menu's slot picker gets a push_warning and no file.
	# BIND EVERY LAMBDA TO A LOCAL FIRST. A multi-line lambda written inline as a
	# call argument parses unreliably here: the run-save predicate below silently
	# swallowed its own body, returned nothing, and made all 14 corruptions read as
	# "unusable state" — 14 bugs that did not exist. A uniform failure across every
	# case is almost always a broken oracle, and the fix is to stop nesting lambdas
	# inside a multi-line argument list.
	var seed_run := func():
		RS.start_new_run("stalwart", 0, 31337)
		RS.run_active = true
		RS.active_slot = 0          # save_run refuses to write without a claimed slot
		RS.gold = 250
		RS.save_run()
	var load_run := func(): return RS.load_run(0)
	# Sane = the loader left something still playable. NOT `deck != null`: `deck` is
	# a typed Array[String] and comparing a typed Array to null is an invalid
	# operand, which aborts the predicate rather than returning false.
	var sane_run := func():
		return RS.deck.size() >= 0 and RS.hero_hp >= 0 and RS.gold >= 0 \
			and RS.hero_max_hp > 0 and RS.current_act_idx >= 0
	var diag_run := func():
		return "deck=%d hp=%d/%d gold=%d act=%d" % [RS.deck.size(), RS.hero_hp,
			RS.hero_max_hp, RS.gold, RS.current_act_idx]
	# The real path is slot-based (`user://run_<slot>.save`); `user://run.save` is
	# only the LEGACY path kept for migration.
	_torture("run save", "user://run_0.save", seed_run, load_run, sane_run, diag_run)

	# ── META SAVE ───────────────────────────────────────────────────────────
	var seed_meta := func():
		MS.total_runs = 5
		MS.total_victories = 3
		MS.total_defeats = 2
		MS.save()
	var load_meta := func():
		MS.load_save()
		return true
	var sane_meta := func():
		return MS.total_runs >= 0 and MS.total_victories >= 0 \
			and MS.total_defeats >= 0 and MS.unlocked_ascension >= 0
	_torture("meta save", "user://meta.save", seed_meta, load_meta, sane_meta)

	# ── SETTINGS ────────────────────────────────────────────────────────────
	var seed_set := func():
		US.anim_speed = 1.0
		US.save()
	var load_set := func():
		US.load_settings()
		return true
	# A corrupt settings file must never leave the game unplayable: a zero or
	# negative anim_speed would freeze every tween in the project.
	var sane_set := func(): return US.anim_speed > 0.0
	_torture("settings", "user://settings.save", seed_set, load_set, sane_set)

	await _backup_recovery()

	print("\n[chaos] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	for c in _crashes:
		print("        %s" % c)
	_done = true
	quit(1 if _fails > 0 else 0)


## THE BACKUP IS THE WHOLE POINT OF SaveIO KEEPING ONE. If a corrupt primary does
## not fall through to a good backup, the backup is decoration and a single bad
## write loses the run — which is the exact failure this class exists to catch.
func _backup_recovery() -> void:
	print("\n[chaos] --- backup recovery ---")
	RS.start_new_run("stalwart", 0, 31337)
	RS.run_active = true
	RS.active_slot = 0
	RS.gold = 777
	RS.save_run()
	var primary := "user://run_0.save"
	var good := _read(primary)
	# Write the good copy where SaveIO looks for its backup, then wreck the primary.
	_write(primary + ".bak", good)
	_write(primary, "{ truncated")
	RS.gold = 0
	var loaded = RS.load_run(0)
	_check(bool(loaded), "a corrupt primary still loads (via the backup)")
	_check(int(RS.gold) == 777,
		"and it recovered the REAL save, not a blank one (gold=%d, expected 777)"
			% int(RS.gold))
	# And the harder half: with BOTH copies wrecked, the loader must say NO rather
	# than report success over an empty run.
	_write(primary, "{ truncated")
	_write(primary + ".bak", "also truncated {")
	var loaded2 = RS.load_run(0)
	_check(not bool(loaded2),
		"with primary AND backup corrupt, load_run() reports failure honestly")
