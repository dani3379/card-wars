extends SceneTree
## _probe_fixture_pins.gd — CLASS C34: THE FIXTURE THAT PINS A BALANCE NUMBER.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_fixture_pins.gd
##
## THIS GATE TESTS THE TESTS, and it exists because one class has produced almost
## every red line in this suite's history. On 2026-09-19 a sweep of 95 gates found
## 8 failing checks across 4 probes; **all 8 had one cause** — a rebalance raised
## costs and stats (`duelist` 2/2-3 -> 3/3-4, `the_glutton` hp 3->4, `sin_eater`
## 2/3 -> 3/4, `breaker` atk 2->3, `tallow_doll` 2/2 -> 3/3) and every probe had
## pinned the OLD number as a literal. The mechanics were all correct. The same
## class is #3 and #6 in reference_stale_probe_sweep's own frequency list
## ("a design that MOVED, with the probe left behind"; "a card ID REUSED").
##
## The cost is not the red line, it is what a red line nobody believes does: it
## trains everyone to skip the suite, and then a real regression arrives into a
## harness no one reads. A gate that pins a balance number is a **tax on
## rebalancing**, not a guard on design intent.
##
## ── WHAT IS AND IS NOT A FINDING ─────────────────────────────────────────────
##
## A literal is FINE when the fixture states its own requirement — a probe that
## seats a synthetic 2/6 dummy and then asserts `hp == 6` is self-consistent and
## no content change can touch it. That is the shape the repo already recommends
## ("a fixture must state its own requirement").
##
## A literal is FRAGILE when the subject was pulled from CONTENT — `_seat_id("x")`,
## `get_card_data("x")`, `CARD_POOL["x"]` — and the assertion then pins a stat to a
## bare integer. The probe is asserting the designer's current balance pass.
##
## So the rule is a CO-OCCURRENCE: a content-sourced subject AND a pinned stat
## comparison, **within PROXIMITY_LINES of each other**.
##
## PROXIMITY, NOT PER-FUNCTION, and that distinction was a defect first. Scoping
## per function looked obviously right and flagged four assertions in
## `_probe_newslate._run_test` that are the GOOD pattern — they assert on a
## `summon_token(1, 1, ...)` the probe itself sized, which no content change can
## touch. That probe puts every test in ONE monolithic function, so whole-function
## scope attributed `breaker`/`sin_eater`/`ironclad_veteran` from unrelated tests
## a hundred lines away. These tests are written seat-then-assert within a few
## lines, so a window is both more faithful and far more precise.
##
## ── THE FIX THE FINDINGS WANT ────────────────────────────────────────────────
##
## Derive the expectation from the live data, so it moves with the content:
##     var base := CDB.CARD_POOL["duelist"]
##     var want := int(base["atk"]) + unspent      # the RELATION is the contract
## or assert the relation directly (flank blow = attacker ATK - armour). Neither
## can go stale, and both say what the test actually owns.
##
## ── REPORTS, DOES NOT FAIL (on the inventory) ────────────────────────────────
##
## The existing stock of pins is legacy debt and dropping 50 red lines on the
## suite would be the very thing this class warns about. So the inventory is a
## COUNT, and the count is the signal — the same stance `_probe_silent_refusal`
## and `_probe_card_rules_fit` take. What it DOES fail on is a pin naming one of
## the cards a rebalance has already moved through here (`RECENTLY_MOVED`), since
## those are proven to churn and are the ones that will red the suite next.

const TOOLS_DIR := "res://tools"

## How far above a pinned assertion its subject may have been seated. These probes
## are written seat-then-assert; 14 lines covers an await, a settle and a comment
## block without reaching into the next test. See the header on why this is a
## window rather than the whole function.
const PROXIMITY_LINES := 14

## Cards a documented rebalance has already moved, i.e. proven-volatile subjects.
## A pinned literal against one of these is not debt, it is a red line waiting for
## the next pass. Add to this list when a rebalance moves a card that probes name.
const RECENTLY_MOVED := {
	"duelist": true, "the_glutton": true, "sin_eater": true,
	"breaker": true, "tallow_doll": true, "ironclad_veteran": true,
}

## Pulling a subject out of CONTENT.
const CONTENT_SOURCES := [
	"_seat_id(", "get_card_data(", "CARD_POOL[", "CARD_POOL.get(",
	"_card(", "build_enemy_deck(",
]

## Live-stat comparisons against a bare integer. `\\d` only — a comparison against
## another expression is already derived and is exactly what we want people to write.
const PIN_PATTERNS := [
	"current_atk ==", "current_hp ==", "effective_atk() ==",
	"current_atk !=", "current_hp !=",
]

var _files := 0
var _funcs := 0
var _fragile: Array = []
var _hard_fails: Array = []
var _started := false


func _process(_d: float) -> bool:
	if _started:
		return true
	_started = true
	_run()
	return true


func _run() -> void:
	for path in _probe_files():
		_scan(path)
	_report()


func _probe_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(TOOLS_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n.ends_with(".gd") and n.begins_with("_probe_"):
			out.append("%s/%s" % [TOOLS_DIR, n])
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## Walk one probe FUNCTION AT A TIME. A probe file legitimately mixes synthetic
## fixtures and content-sourced ones, so file-level co-occurrence would flag
## nearly every good probe in the suite — the false-positive flood that makes a
## meta-gate worthless.
func _scan(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_files += 1
	var lines := f.get_as_text().split("\n")
	var fname := ""
	# (line, id) pairs, so a pin is matched only against subjects seated NEAR it.
	var subjects: Array = []
	for i in range(lines.size()):
		var raw := String(lines[i])
		var line := raw.strip_edges()
		if line.begins_with("func "):
			_funcs += 1
			fname = line.substr(5, maxi(0, line.find("(") - 5))
			subjects = []
			continue
		if line.begins_with("#"):
			continue
		for src in CONTENT_SOURCES:
			var at := line.find(src)
			if at < 0:
				continue
			var id := _quoted_after(line, at + src.length())
			if id != "":
				subjects.append([i, id])
		# ONE ENTRY PER LINE. A single assertion routinely compares both stats
		# ("atk == 4 and hp == 5"), and reporting it twice made the first run's
		# finding list read as double the real count.
		var pinned := false
		for p in PIN_PATTERNS:
			var at2 := line.find(p)
			if at2 >= 0 and _int_literal_follows(line, at2 + p.length()):
				pinned = true
				break
		if pinned and fname != "":
			_consider(path, fname, i + 1, line, _near(subjects, i))


## The first quoted token after an opening paren/bracket, i.e. the card id.
func _quoted_after(line: String, from: int) -> String:
	var a := line.find("\"", from)
	if a < 0:
		return ""
	var b := line.find("\"", a + 1)
	if b <= a:
		return ""
	return line.substr(a + 1, b - a - 1)


## Is the comparison's right-hand side a bare integer? A comparison against
## another expression is already derived, which is the whole point.
func _int_literal_follows(line: String, from: int) -> bool:
	var rest := line.substr(from, line.length() - from).strip_edges()
	if rest.is_empty():
		return false
	var digits := 0
	while digits < rest.length() and rest[digits] >= "0" and rest[digits] <= "9":
		digits += 1
	if digits == 0:
		return false
	# "== 4" and "== 4 and ..." are pins; "== 4th" is not a number we produced.
	var after := rest.substr(digits, rest.length() - digits)
	return after.is_empty() or after.begins_with(" ") or after.begins_with(")") \
		or after.begins_with(",")


## Subjects seated within PROXIMITY_LINES above this assertion.
func _near(subjects: Array, at: int) -> Array:
	var out: Array = []
	for s in subjects:
		var ln := int(s[0])
		if ln <= at and at - ln <= PROXIMITY_LINES:
			var id := String(s[1])
			if not out.has(id):
				out.append(id)
	return out


func _consider(path: String, fname: String, line_no: int, code: String,
		subjects: Array) -> void:
	if subjects.is_empty():
		return   # a synthetic fixture: the probe stated its own requirement
	var volatile: Array = []
	for s in subjects:
		if RECENTLY_MOVED.has(s):
			volatile.append(s)
	var entry := {
		"file": path.get_file(), "line": line_no, "func": fname,
		"subjects": subjects, "code": code, "volatile": volatile,
	}
	if volatile.is_empty():
		_fragile.append(entry)
	else:
		_hard_fails.append(entry)


func _report() -> void:
	print("[pins] C34 — fixtures pinning a balance number")
	print("[pins] scanned %d probe files, %d functions" % [_files, _funcs])
	print("")
	print("[pins] FRAGILE (legacy debt — count is the signal, not a failure): %d"
		% _fragile.size())
	for e in _fragile:
		print("[pins]   %s:%d  %s()  subjects=%s"
			% [e["file"], e["line"], e["func"], str(e["subjects"])])
		print("[pins]       %s" % e["code"])
	print("")
	print("[pins] PINNED TO A PROVEN-VOLATILE CARD (these fail): %d"
		% _hard_fails.size())
	for e in _hard_fails:
		print("[pins]   FAIL %s:%d  %s()  volatile=%s"
			% [e["file"], e["line"], e["func"], str(e["volatile"])])
		print("[pins]       %s" % e["code"])
		print("[pins]       fix: derive from the card's own data, or assert the"
			+ " relation — see this file's header")
	print("")
	# Vacuity: a scanner that matched nothing is not a clean suite, it is a broken
	# scanner. Same tell as the 0-of-90 resolver case and chaos_save's 14-of-14.
	if _files < 50 or _funcs < 200:
		print("[pins] FAIL vacuous — scanned %d files / %d functions; the scanner"
			% [_files, _funcs] + " did not read the suite")
		quit(1)
		return
	if _hard_fails.is_empty():
		print("[pins] PASS — no fixture pins a stat of a card known to churn")
		quit(0)
	else:
		print("[pins] FAIL — %d pin(s) on proven-volatile cards" % _hard_fails.size())
		quit(1)
