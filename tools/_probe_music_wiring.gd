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
	# One pattern for both call shapes; [^)]* crosses newlines, so split
	# pool arrays (a call wrapped to the next line) are still captured. Any
	# quoted string inside the args is a track name — play_music's only other
	# params are floats, and play_music_random takes an array of names.
	var re_call := RegEx.create_from_string("play_music(?:_random)?\\(([^)]*)\\)")
	var re_str := RegEx.create_from_string("\"([^\"]+)\"")
	for m in re_call.search_all(text):
		var line: int = text.count("\n", 0, m.get_start()) + 1
		for s in re_str.search_all(m.get_string(1)):
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
