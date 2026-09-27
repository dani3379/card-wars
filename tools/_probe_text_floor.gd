extends SceneTree
## Text-floor probe (2026-07-20 — COPY_STYLE.md §11, the readability contract).
##
## The readability floor is enforced structurally in GameTheme.make_label /
## make_themed_button (MIN_LABEL_SIZE 18), but raw
## add_theme_font_size_override sites bypass it — and every new content slate
## has re-introduced sub-floor text that way (the 2026-07-18 minigame ledgers
## shipped at 11-13px). This probe is the drift gate: it scans every .gd
## under res://scripts/ for a literal font-size override BELOW 14 — the hard
## floor under which no worded text may render (COPY_STYLE §11).
##
## A deliberate exception (a numeral fitted inside a drawn object, a glyph
## marker) carries the waiver comment on the same line:
##     lbl.add_theme_font_size_override("font_size", 13)  # textfloor: fitted
##
## File exemptions (documented in COPY_STYLE §11):
##   - scripts/Card2D.gd — the card face is its own tuned system (the
##     3-register law names it); its sub-14 sites are seals/legacy indicators.
##   - scripts/state/PerformanceOverlay.gd — dev tool, not player-facing.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_text_floor.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

const HARD_FLOOR := 14
const WAIVER := "textfloor: fitted"
## Label builders that DO NOT clamp to GameTheme.MIN_LABEL_SIZE. A literal size
## passed to one of these renders at exactly that size, so a sub-floor argument
## is a real violation — but it arrives at add_theme_font_size_override as a
## VARIABLE, which the literal-only regex below can never see.
##
## Found 2026-07-31: Combat.gd makes ZERO GameTheme.make_label calls (it uses the
## private clone below), and GameOver.gd does the same. Both shipped 13px worded
## text past this gate. The clamped helpers are deliberately NOT listed — a
## sub-floor argument to MainMenu._make_display_label is inert, not a violation.
const UNCLAMPED_LABEL_HELPERS := {
	"res://scripts/scenes/Combat.gd": ["_make_text_label"],
	"res://scripts/scenes/GameOver.gd": ["_make_summary_label"],
	"res://scripts/scenes/Collection.gd": ["_ghost_label"],
}

const EXEMPT_FILES := [
	"res://scripts/Card2D.gd",
	"res://scripts/state/PerformanceOverlay.gd",
]

var _fails := 0
var _scanned := 0


func _process(_delta: float) -> bool:
	var re := RegEx.new()
	# Catches font_size / normal_font_size / bold_font_size / italics_font_size
	# literal overrides. Variable-fed sizes can't be caught statically — the
	# drift pattern this gate exists for is the literal.
	re.compile("add_theme_font_size_override\\(\\s*\"[a-z_]*font_size\"\\s*,\\s*(\\d+)\\s*\\)")
	_scan_dir("res://scripts", re)
	_check_reading_contract()
	print("[text_floor] scanned %d .gd files" % _scanned)
	if _fails == 0:
		print("[text_floor] ALL PASS — no worded text below %dpx" % HARD_FLOOR)
	else:
		print("[text_floor] %d FAIL(s) — sub-%d font override without a '%s' waiver"
			% [_fails, HARD_FLOOR, WAIVER])
	return true


func _scan_dir(path: String, re: RegEx) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		print("[text_floor] FATAL: cannot open ", path)
		_fails += 1
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(full, re)
		elif entry.ends_with(".gd"):
			if full in EXEMPT_FILES:
				print("[text_floor] SKIP  ", full, " (documented exemption)")
			else:
				_scan_file(full, re)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, re: RegEx) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_scanned += 1
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		_scan_helper_call(path, line, line_no)
		var m := re.search(line)
		if m == null:
			continue
		var size := int(m.get_string(1))
		if size >= HARD_FLOOR:
			continue
		if line.contains(WAIVER):
			continue
		_fails += 1
		print("[text_floor] FAIL  %s:%d  size %d  — %s"
			% [path, line_no, size, line.strip_edges()])


func _check_reading_contract() -> void:
	# Static literal scanning cannot infer helper clamps or the separately tuned
	# card renderer. Assert those high-risk reading surfaces directly.
	_require_source_count("res://scripts/GameTheme.gd",
		"const MIN_LABEL_SIZE := 18", 1,
		"GameTheme global reading floor is not 18px")
	_require_source_count("res://scripts/scenes/MainMenu.gd",
		"maxi(size, GameTheme.MIN_LABEL_SIZE)", 1,
		"Main-menu helper no longer clamps reading text to the global floor")
	_require_source_count("res://scripts/Card2D.gd",
		"var dsz := 18", 1,
		"Live card rules text is not fixed at 18px")
	_require_source_count("res://scripts/Card2D.gd",
		"var od_sz := 18", 1,
		"Baked card rules text is not fixed at 18px")
	_require_source_count("res://scripts/Card2D.gd",
		"if cur <= 18:", 1,
		"Card overflow fitter can shrink rules below 18px")


func _require_source_count(path: String, needle: String, expected: int,
		message: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var actual := text.count(needle)
	if actual == expected:
		return
	_fails += 1
	print("[text_floor] FAIL  %s — %s (expected %d, found %d)"
		% [path, message, expected, actual])

## Scan of unclamped-helper call sites. Arguments are split at paren DEPTH 1, not
## by regex: a regex for ", <int>," also matches integers inside nested calls, and
## `_make_summary_label(_roman(maxi(MetaState.total_runs, 1)), 30, ...)` duly
## reported "size 1" when the real size is 30. Depth-aware splitting is barely
## more code and has no such failure.
func _scan_helper_call(path: String, line: String, line_no: int) -> void:
	var helpers: Array = UNCLAMPED_LABEL_HELPERS.get(path, [])
	if helpers.is_empty() or line.contains("func ") or line.contains(WAIVER):
		return
	for helper in helpers:
		for arg in _top_level_args(line, String(helper)):
			var trimmed: String = String(arg).strip_edges()
			if not trimmed.is_valid_int():
				continue
			var size := int(trimmed)
			if size >= HARD_FLOOR:
				continue
			_fails += 1
			print("[text_floor] FAIL  %s:%d  size %d (unclamped helper)  — %s"
				% [path, line_no, size, line.strip_edges()])


## Arguments of `helper(...)` that sit at the call's own paren depth. A call that
## continues onto the next line simply yields the arguments present so far.
func _top_level_args(line: String, helper: String) -> Array:
	var out: Array = []
	var idx := line.find(helper + "(")
	if idx < 0:
		return out
	var depth := 1
	var arg := ""
	for i in range(idx + helper.length() + 1, line.length()):
		var ch := line[i]
		if ch == "(" or ch == "[":
			depth += 1
		elif ch == ")" or ch == "]":
			depth -= 1
			if depth == 0:
				out.append(arg)
				return out
		if depth == 1 and ch == ",":
			out.append(arg)
			arg = ""
		else:
			arg += ch
	out.append(arg)
	return out
