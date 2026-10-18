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
		# Never fall back to opening the real file for WRITE: that truncates the
		# last good save before we know the replacement can be stored.
		push_warning("SaveIO: could not create %s; kept prior save" % tmp)
		return false
	f.store_string(text)
	var store_err := f.get_error()
	f.close()
	# VALIDATE the tmp before the destructive rotate. Without this, a truncated
	# write (disk full / IO error) still rotated the good file to .bak and promoted
	# the bad tmp — and the NEXT save then deleted that good .bak, so two bad writes
	# in a row destroyed both generations. If the tmp didn't land whole, abort and
	# leave the existing good file and its .bak exactly where they are: a failed
	# save is recoverable, a destroyed one is not.
	var want_bytes := text.to_utf8_buffer().size()
	var got_bytes := -1
	var vf := FileAccess.open(tmp, FileAccess.READ)
	if vf != null:
		got_bytes = int(vf.get_length())
		vf.close()
	if store_err != OK or got_bytes != want_bytes:
		push_warning("SaveIO: aborted write of %s (err=%d, %d/%d bytes) — kept prior save" \
			% [path, store_err, got_bytes, want_bytes])
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		return false
	# Rotate: current good file becomes .bak (Windows rename will not overwrite,
	# so clear the old .bak first), then promote the validated tmp.
	var bak := path + ".bak"
	var had_current := FileAccess.file_exists(path)
	if had_current:
		if FileAccess.file_exists(bak):
			var remove_err := DirAccess.remove_absolute(bak)
			if remove_err != OK:
				push_warning("SaveIO: could not clear backup for %s; kept prior save" % path)
				DirAccess.remove_absolute(tmp)
				return false
		var rotate_err := DirAccess.rename_absolute(path, bak)
		if rotate_err != OK:
			push_warning("SaveIO: could not rotate %s; kept prior save" % path)
			DirAccess.remove_absolute(tmp)
			return false
	var promote_err := DirAccess.rename_absolute(tmp, path)
	if promote_err == OK:
		return true
	push_warning("SaveIO: could not promote validated tmp for %s" % path)
	# Best-effort rollback. If it fails, the good generation still remains at
	# .bak and read_text() can recover it; never delete that backup here.
	if had_current and not FileAccess.file_exists(path) \
			and FileAccess.file_exists(bak):
		var restore_err := DirAccess.rename_absolute(bak, path)
		if restore_err != OK:
			push_warning("SaveIO: rollback failed for %s; backup retained" % path)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	return false


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
