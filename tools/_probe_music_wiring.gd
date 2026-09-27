extends SceneTree
## Music-wiring probe (2026-07-05). Every track name that appears as a string
## literal inside a play_music(...) or play_music_random([...]) call under
## scripts/ must resolve to a file at assets/audio/music/<name>.(ogg|mp3|wav).
## Catches the music edition of the "wired but silent" bug class: AudioBank
## no-ops gracefully on a missing file, so a typo'd pool entry or a deleted
## track just means that slot silently never plays.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_music_wiring.gd
## Grep for "ALL PASS" — don't trust the exit code alone (some probes segfault
## at teardown after passing, see _probe_shellpass).

const SCRIPTS_DIR := "res://scripts"
const MUSIC_DIR := "res://assets/audio/music/"

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	# track -> Array[String] of "file:line" call sites
	var sites: Dictionary = {}
	for path in _gd_files(SCRIPTS_DIR):
		_scan_file(path, sites)

	var names: Array = sites.keys()
	names.sort()
	var failures: Array = []
	for track in names:
		if _music_exists(track):
			print("[music] PASS  %-18s" % track)
		else:
			failures.append(track)
			print("[music] FAIL  %-18s -> no %s%s.(ogg|mp3|wav)  (called at %s)"
				% [track, MUSIC_DIR, track, ", ".join(sites[track])])

	if failures.is_empty():
		print("[music] ALL PASS (%d tracks resolve)" % names.size())
	else:
		print("[music] %d FAILURES: %s" % [failures.size(), ", ".join(failures)])
	quit(0 if failures.is_empty() else 1)
	return true


func _music_exists(track: String) -> bool:
	for ext in [".ogg", ".mp3", ".wav"]:
		var p: String = MUSIC_DIR + track + ext
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return true
	return false


func _scan_file(path: String, sites: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	# One pattern for all three call shapes; [^)]* crosses newlines, so split
	# pool arrays (a call wrapped to the next line) are still captured. Any
	# quoted string inside the args is a track name — play_music's only other
	# params are floats, and play_music_random takes an array of names.
	#
	# COVERAGE HANDOFF (2026-09-14). Combat's fight books moved out of inline
	# play_music_random([...]) calls into the static Combat._combat_music_book,
	# so nine names — combat_elite{,_b,_c} and combat_boss{,_b,_c,_d,_e,_act3} —
	# are no longer literals this scan can see. They are covered instead by
	# tools/_probe_music_layers.tscn, which ENUMERATES every fight in the game by
	# calling that function and resolves every track in every book through
	# AudioBank._resolve_music_path. That is strictly stronger than this scan: it
	# proves the names a real fight would ask for, including the per-rival-lord
	# boss branch a literal scan could only approximate. The twelve act-combat
	# names still appear here because the skirmish branch keeps them inline.
	#
	# play_music_theme (2026-09-14) is the exception and needs the skip below:
	# its FIRST argument is a theme KEY, not a track. Matching it without that
	# skip would report the key as a missing track and fail the gate; not
	# matching it at all would leave its pool unscanned, which is the coverage
	# hole that adding the function opened. Its sibling play_road_theme takes an
	# int and holds its pool in AudioBank.ROAD_BOOKS, a const this scanner
	# cannot see — that one is gated by tools/_probe_music_theme.tscn phase A.
	var re_call := RegEx.create_from_string("play_music(_random|_theme)?\\(([^)]*)\\)")
	var re_str := RegEx.create_from_string("\"([^\"]+)\"")
	for m in re_call.search_all(text):
		var line: int = text.count("\n", 0, m.get_start()) + 1
		var is_theme: bool = m.get_string(1) == "_theme"
		var first := true
		for s in re_str.search_all(m.get_string(2)):
			if is_theme and first:
				first = false
				continue  # the theme key, not a track name
			first = false
			var track: String = s.get_string(1)
			if not sites.has(track):
				sites[track] = []
			sites[track].append("%s:%d" % [path.trim_prefix("res://"), line])


func _gd_files(root: String) -> Array:
	var out: Array = []
	var dirs: Array = [root]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var e := da.get_next()
		while e != "":
			var full := d + "/" + e
			if da.current_is_dir():
				if not e.begins_with("."):
					dirs.append(full)
			elif e.ends_with(".gd"):
				out.append(full)
			e = da.get_next()
		da.list_dir_end()
	return out
