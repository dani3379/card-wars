extends SceneTree
## Shell-language probe (2026-08-05 — docs/MENU_COOL_HUNT_20260805.md).
##
## The menu pass gave the shell ONE interaction language. Nothing in the build
## prevents it drifting back, and every part of it is the kind of thing a
## refactor drops silently: an `arm_ui_hover` call removed from a funnel makes
## the entire game go quiet on hover again, and NO existing gate would notice —
## the game still compiles, still runs, still passes every probe.
##
## That silence is exactly the state this pass found: MainMenu, SettingsOverlay,
## Collection and Credits held ZERO play_sfx call sites between them, and not
## one of the 40 `mouse_entered` handlers in scripts/ made a sound. It took a
## deliberate hunt to notice. This probe is so it never takes one again.
##
## Source-scanning rather than runtime, following _probe_text_floor and
## _probe_audio_cues: these are call-site contracts, and a call site either
## exists or it does not.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_shell_language.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

const PROBE_NAME := "shell_language"

## The shell's four cues. Every one must have BOTH a UI_CUE_MIX entry (its
## levels) and a literal play_sfx arm in play_ui (what the audio gate can see).
## A kind present in the mix but missing its arm silently plays nothing.
const UI_KINDS := ["hover", "select", "back", "commit"]

## The game-wide button funnels. Hover is armed inside these, which is the only
## reason every screen in the game has a voice — including screens nobody has
## touched since. Drop a call and that whole family of buttons goes quiet.
##
## `make_primary_button` was added to this list after the probe's own
## verification pass: the first mutation test aimed at `make_back_button`
## actually landed on `make_primary_button`'s tail (both end
## `arm_ui_hover(btn)` / `return btn`, and they are adjacent in the file), the
## probe correctly stayed green, and it took reading the diff to see that the
## TEST was wrong rather than the check. The gap it exposed was real though —
## the third funnel was unguarded.
const HOVER_FUNNELS := ["make_themed_button", "make_back_button",
	"make_primary_button"]

## Screens that held zero interaction cues before this pass. Each must still
## carry at least one — the exact regression that started the whole hunt.
const VOICED_SHELL := [
	"res://scripts/scenes/MainMenu.gd",
	"res://scripts/ui/SettingsOverlay.gd",
	"res://scripts/scenes/Collection.gd",
	"res://scripts/scenes/Credits.gd",
	"res://scripts/scenes/NetLobby.gd",
]
const VOICE_MARKERS := ["arm_ui_press", "_arm_shell_button", "play_ui", "arm_ui_hover"]

## Screens whose FORWARD move is the way on and must wear the primary plate.
## Asserted by helper, not by label text, so re-wording a button is free.
const PRIMARY_SITES := [
	"res://scripts/scenes/Reward.gd",     # "Continue" — ~21x a run
	"res://scripts/scenes/Shop.gd",       # "Leave the Wagon"
	"res://scripts/scenes/Wayside.gd",    # the result-screen "Continue"
]

## The sage that was the project's cold-ink tell in three places at once (the
## muster, Recruit, the map). Combat's "verdant" ATMOSPHERE is a near neighbour
## at (0.64, 0.72, 0.60) and is legitimate — a green arena may be green — so the
## check is for this exact triple, in scene/ui scripts only.
const SAGE_INK := "Color(0.64, 0.74, 0.60)"
const SAGE_SCAN_DIRS := ["res://scripts/scenes", "res://scripts/ui"]


func _init() -> void:
	var fails: Array[String] = []
	var checks := 0

	# ── 1. the four cues are wired end to end ─────────────────────────────
	var audio := _read("res://scripts/AudioBank.gd")
	if audio == "":
		fails.append("cannot read AudioBank.gd")
	else:
		for kind in UI_KINDS:
			checks += 1
			if not audio.contains('"%s": {"db"' % kind):
				fails.append("UI_CUE_MIX has no entry for \"%s\"" % kind)
			checks += 1
			if not audio.contains('play_sfx("ui_%s"' % kind):
				fails.append(("play_ui has no literal play_sfx(\"ui_%s\") arm — "
					+ "a runtime-built name is invisible to _probe_audio_cues "
					+ "and to grep") % kind)

	# ── 2. hover is still armed in BOTH game-wide funnels ─────────────────
	var theme := _read("res://scripts/GameTheme.gd")
	if theme == "":
		fails.append("cannot read GameTheme.gd")
	else:
		checks += 1
		if not theme.contains("func arm_ui_hover("):
			fails.append("GameTheme.arm_ui_hover is gone — the shell's hover voice")
		checks += 1
		if not theme.contains("func arm_ui_press("):
			fails.append("GameTheme.arm_ui_press is gone — screens opt into press cues with it")
		checks += 1
		if not theme.contains("func make_primary_button("):
			fails.append("GameTheme.make_primary_button is gone — the forward-move plate")
		for fn in HOVER_FUNNELS:
			checks += 1
			var body := _func_body(theme, "func %s(" % fn)
			if body == "":
				fails.append("GameTheme.%s not found" % fn)
			elif not body.contains("arm_ui_hover("):
				fails.append(("GameTheme.%s no longer calls arm_ui_hover — "
					+ "dropping it silences hover across the WHOLE game, and "
					+ "nothing else in the build would notice") % fn)

	# ── 3. no shell screen has gone silent again ──────────────────────────
	for path in VOICED_SHELL:
		checks += 1
		var src := _read(path)
		if src == "":
			fails.append("cannot read %s" % path)
			continue
		var voiced := false
		for marker in VOICE_MARKERS:
			if src.contains(marker):
				voiced = true
				break
		if not voiced:
			fails.append(("%s plays nothing on interaction — this is the exact "
				+ "state the 2026-08-05 hunt found the whole shell in") % path)

	# ── 4. the forward move is still plated where the run passes most ─────
	for path in PRIMARY_SITES:
		checks += 1
		var src := _read(path)
		if src == "":
			fails.append("cannot read %s" % path)
			continue
		if not src.contains("make_primary_button("):
			fails.append(("%s has no make_primary_button call — its way ON has "
				+ "reverted to the frameless retreat treatment") % path)

	# ── 5. the cold-ink sage has not come back ────────────────────────────
	var sage_hits: Array[String] = []
	for dir_path in SAGE_SCAN_DIRS:
		_scan_for(dir_path, SAGE_INK, sage_hits)
	checks += 1
	for hit in sage_hits:
		fails.append(("%s — the sage ink %s is back. `g >= r` is the project's "
			+ "cold-ink tell; it was live in THREE places at once (the muster, "
			+ "Recruit, the map) because the 2026-08-03 fix was made per SCREEN "
			+ "when the defect belonged to the LINE.") % [hit, SAGE_INK])

	print("[shell] ran %d checks" % checks)
	if fails.is_empty():
		print("[shell] ALL PASS — the shell keeps one interaction language")
		quit(0)
		return
	for f in fails:
		printerr("[shell] FAIL: %s" % f)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, fails.size()])
	quit(1)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


## Everything from `header` to the next line that starts a new top-level func.
## Crude on purpose: it only has to answer "does this function still call X",
## and a brace-accurate parser would be more code than the check is worth.
func _func_body(src: String, header: String) -> String:
	var start := src.find(header)
	if start < 0:
		return ""
	var rest := src.substr(start + header.length())
	var end := rest.find("\nfunc ")
	if end < 0:
		return rest
	return rest.substr(0, end)


func _scan_for(root: String, needle: String, hits: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				_scan_for(path, needle, hits)
			elif entry.ends_with(".gd"):
				var src := _read(path)
				var line_no := 1
				for line in src.split("\n"):
					if line.contains(needle):
						hits.append("%s:%d" % [path, line_no])
					line_no += 1
		entry = dir.get_next()
	dir.list_dir_end()
