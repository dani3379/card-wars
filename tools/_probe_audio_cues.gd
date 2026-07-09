extends SceneTree
## Audio-cue wiring probe (2026-07-04). Every play_sfx("cue") literal call site
## under scripts/ must resolve to actual sound: the cue's own event dir under
## assets/audio/sfx/ — or its AudioBank.SFX_FALLBACKS alias — must contain at
## least one .ogg/.wav/.mp3. Catches the "wired but silent" class of bug: five
## combat/reward cues shipped as no-ops in 2026-07 because only the call sites
## existed. play_ambience cues are WARN-only (missing ambience no-ops by design
## — event rooms name loops before their assets exist, see Event.gd/README).
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_audio_cues.gd
## Grep for "ALL PASS" — don't trust the exit code alone (some probes segfault
## at teardown after passing, see _probe_shellpass).

const SCRIPTS_DIR := "res://scripts"
const SFX_DIR := "res://assets/audio/sfx/"

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var fallbacks: Dictionary = load("res://scripts/AudioBank.gd").SFX_FALLBACKS

	# cue -> Array[String] of "file:line" call sites
	var sfx_sites: Dictionary = {}
	var amb_sites: Dictionary = {}
	for path in _gd_files(SCRIPTS_DIR):
		_scan_file(path, sfx_sites, amb_sites)

	var failures: Array = []
	var pass_count := 0
	for cue in sfx_sites.keys():
		var primary_ok := _dir_has_audio(SFX_DIR + cue)
		var fb: String = String(fallbacks.get(cue, ""))
		var fb_ok := fb != "" and _dir_has_audio(SFX_DIR + fb)
		if primary_ok:
			pass_count += 1
			print("[audio] PASS  %-18s (own dir)" % cue)
		elif fb_ok:
			pass_count += 1
			print("[audio] PASS  %-18s (fallback -> %s)" % [cue, fb])
		else:
			failures.append(cue)
			print("[audio] FAIL  %-18s — no clips, no usable fallback. Call sites:" % cue)
			for site in sfx_sites[cue]:
				print("[audio]         %s" % site)

	for cue in amb_sites.keys():
		if not _dir_has_audio(SFX_DIR + cue):
			print("[audio] WARN  ambience '%s' has no clips (no-ops by design)" % cue)

	# Informational: event dirs with clips nothing references (candidates for
	# rewiring or removal — not an error, bespoke clips may predate their cue).
	var referenced := {}
	for cue in sfx_sites.keys():
		referenced[cue] = true
		var fb2: String = String(fallbacks.get(cue, ""))
		if fb2 != "":
			referenced[fb2] = true
	for cue in amb_sites.keys():
		referenced[cue] = true
	var dir := DirAccess.open(SFX_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if dir.current_is_dir() and not entry.begins_with(".") \
					and not referenced.has(entry) and _dir_has_audio(SFX_DIR + entry):
				print("[audio] INFO  dir '%s' has clips but no play_sfx caller" % entry)
			entry = dir.get_next()
		dir.list_dir_end()

	if failures.is_empty():
		print("[audio] ALL PASS (%d cues resolve)" % pass_count)
		quit()
	else:
		print("[audio] %d SILENT CUE(S): %s" % [failures.size(), ", ".join(failures)])
		quit(1)
	return true


func _scan_file(path: String, sfx_sites: Dictionary, amb_sites: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var re_sfx := RegEx.create_from_string("play_sfx\\(\\s*\"([A-Za-z0-9_]+)\"")
	var re_amb := RegEx.create_from_string("play_ambience\\(\\s*\"([A-Za-z0-9_]+)\"")
	var line_no := 0
	while not f.eof_reached():
		line_no += 1
		var line := f.get_line()
		# Drop trailing comments so a cue named in prose (e.g. the dedupe note in
		# Card2D) doesn't register as a call site. No '#' appears inside these
		# call strings, so a plain cut is safe.
		var hash_pos := line.find("#")
		if hash_pos != -1:
			line = line.substr(0, hash_pos)
		for m in re_sfx.search_all(line):
			var cue := m.get_string(1)
			if not sfx_sites.has(cue):
				sfx_sites[cue] = []
			sfx_sites[cue].append("%s:%d" % [path.trim_prefix("res://"), line_no])
		for m in re_amb.search_all(line):
			var cue := m.get_string(1)
			if not amb_sites.has(cue):
				amb_sites[cue] = []
			amb_sites[cue].append("%s:%d" % [path.trim_prefix("res://"), line_no])
	f.close()


func _gd_files(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := root + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _dir_has_audio(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var lower := entry.to_lower()
			if lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3"):
				dir.list_dir_end()
				return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false
