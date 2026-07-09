class_name SaveIO
## Crash-safe save-file IO. Every persistent file in the game (meta.save,
## run_N.save, settings.save, decks.json) used to be written with a direct
## FileAccess.WRITE, which TRUNCATES the file the moment it opens — a crash,
## power cut, or force-kill between truncate and flush leaves a zero-byte
## file, and the next boot silently loads defaults and then OVERWRITES the
## wreck with them (observed in the wild: meta.save found zeroed 2026-07-06,
## restored by hand from a stray backup).
##
## write_text: write to <path>.tmp first, then rotate the last good file to
## <path>.bak and move the tmp into place — the real file is never open in
## a truncated state, and one good generation always survives on disk.
## read_text: read <path>, falling back to <path>.bak when the main file is
## missing or empty. Callers that parse (JSON) should fall back themselves
## on parse failure via read_backup_text.


static func write_text(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		# Can't even create the tmp (dir missing / locked): degrade to the old
		# direct write rather than losing the save entirely.
		f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(text)
		f.close()
		return true
	f.store_string(text)
	f.close()
	# Rotate: current good file becomes .bak (Windows rename won't overwrite,
	# so clear the old .bak first), then the tmp becomes the file.
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	var err := DirAccess.rename_absolute(tmp, path)
	return err == OK


static func read_text(path: String) -> String:
	var txt := _read_raw(path)
	if txt != "":
		return txt
	return _read_raw(path + ".bak")


## The .bak generation only — for callers whose main read PARSED wrong
## (read_text can't judge JSON validity, only emptiness).
static func read_backup_text(path: String) -> String:
	return _read_raw(path + ".bak")


static func _read_raw(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt
