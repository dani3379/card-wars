extends Node
## MUSIC THEME POLICY GATE (2026-09-14).
##
## The road's music is now a THEME — drawn once per run and HELD — rather than a
## re-roll on every visit. That change is invisible in a screenshot and silent
## when it breaks: someone "fixing" MapView back to play_music_random would
## restore the original defect (a guaranteed track change on all ~18 chart
## returns an act, so no theme is ever learned) and nothing would error.
##
## Run: Godot.exe --headless --path "D:\Godot" res://tools/_probe_music_theme.tscn
##
## COVERAGE NOTE — this probe also owns something `_probe_music_wiring.gd`
## structurally cannot see. That probe scans for string literals inside
## play_music(...) / play_music_random([...]) call sites; the road books now live
## in `AudioBank.ROAD_BOOKS`, a const, so a bad track name in there would be
## invisible to it. Phase A below resolves every ROAD_BOOKS entry through
## AudioBank's own _resolve_music_path, which is stronger than the static scan
## because it is the function the game actually calls.

const PROBE_NAME := "music_theme"
# Fake names so the selection tests never touch the disk: _resolve_music_path
# returns "" for these and play_music early-returns, while _themes is written
# first — so the policy is exercised with no 8 MB decode.
const FAKE_POOL := ["__probe_a", "__probe_b", "__probe_c"]
# Re-roll trial count. With a 3-entry pool, P(all 60 identical) = 3·(1/3)^60,
# i.e. not a flake risk. Anything smaller starts to be one.
const REROLL_TRIALS := 60

var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	var bank := get_node_or_null("/root/AudioBank")
	if bank == null:
		_fail("AudioBank autoload not present — probe must run as a SCENE")
		_report()
		return
	_phase_a_books_resolve(bank)
	_phase_b_theme_is_held(bank)
	_phase_c_clear_is_scoped(bank)
	_phase_d_reroll_between_runs(bank)
	_phase_e_road_has_one_definition()
	_phase_f_play_music_noops(bank)
	_report()


## A. Every road book entry must resolve to a real file.
func _phase_a_books_resolve(bank: Node) -> void:
	var books: Dictionary = bank.ROAD_BOOKS
	for act in [1, 2, 3]:
		_checks += 1
		if not books.has(act):
			_fail("ROAD_BOOKS has no act %d — play_road_theme would index a missing key" % act)
			continue
		var pool: Array = books[act]
		if pool.is_empty():
			_fail("ROAD_BOOKS[%d] is empty — the chart would be silent all act" % act)
			continue
		for name in pool:
			_checks += 1
			if bank._resolve_music_path(String(name)) == "":
				_fail("ROAD_BOOKS[%d] names '%s', which resolves to no file" % [act, name])


## B. The whole point: the same key returns the same track, every time.
func _phase_b_theme_is_held(bank: Node) -> void:
	bank._themes.erase("run:probe")
	bank.play_music_theme("run:probe", FAKE_POOL)
	var first: String = bank.current_music_theme("run:probe")
	_checks += 1
	if first == "":
		_fail("play_music_theme did not record a pick")
		return
	for i in 30:
		bank.play_music_theme("run:probe", FAKE_POOL)
		_checks += 1
		if bank.current_music_theme("run:probe") != first:
			_fail("theme changed on visit %d (%s -> %s) — it is not being held"
				% [i + 2, first, bank.current_music_theme("run:probe")])
			return
	print("[%s] theme held across 31 visits (%s)" % [PROBE_NAME, first])


## C. clear_music_themes must drop run themes and SPARE everything else — that
## namespace split is the only thing keeping the menu stable across a session.
func _phase_c_clear_is_scoped(bank: Node) -> void:
	bank.play_music_theme("run:probe", FAKE_POOL)
	bank.play_music_theme("probe_session", FAKE_POOL)
	var session_pick: String = bank.current_music_theme("probe_session")
	bank.clear_music_themes()
	_checks += 1
	if bank.current_music_theme("run:probe") != "":
		_fail("clear_music_themes left a run: theme behind — runs would share a road")
	_checks += 1
	if bank.current_music_theme("probe_session") != session_pick:
		_fail("clear_music_themes wiped a non-run theme — the menu would re-roll per march")


## D. …but it must genuinely re-roll, or "held" has quietly become "frozen" and
## every run of the game sounds identical.
func _phase_d_reroll_between_runs(bank: Node) -> void:
	var seen := {}
	for i in REROLL_TRIALS:
		bank.clear_music_themes()
		bank.play_music_theme("run:probe", FAKE_POOL)
		seen[bank.current_music_theme("run:probe")] = true
	_checks += 1
	if seen.size() < 2:
		_fail("theme never re-rolled across %d runs (always %s) — variety is gone"
			% [REROLL_TRIALS, seen.keys()])
	else:
		print("[%s] re-rolls between runs: %d of %d pool entries seen in %d trials"
			% [PROBE_NAME, seen.size(), FAKE_POOL.size(), REROLL_TRIALS])
	bank._themes.erase("run:probe")
	bank._themes.erase("probe_session")


## E. MapView and Wayside must reach the road through the SAME call, or the stop
## stops holding the march's music and the two transitions come back.
func _phase_e_road_has_one_definition() -> void:
	for path in ["res://scripts/scenes/MapView.gd", "res://scripts/scenes/Wayside.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_checks += 1
		if src == "":
			_fail("could not read %s" % path)
			continue
		if not src.contains("play_road_theme("):
			_fail("%s no longer calls play_road_theme — the road theme is not shared" % path)
		_checks += 1
		if src.contains("play_music_random([\"map"):
			_fail("%s re-rolls a map pool again — that is the defect this replaced" % path)


## F. The hold only works because play_music early-returns on the track already
## playing. Without it, a wayside asking for the road theme would still pay a
## crossfade — the transition would be back with none of the change visible.
func _phase_f_play_music_noops(bank: Node) -> void:
	var before_track: String = bank._current_music_track
	var before_active = bank._music_active
	bank._current_music_track = "map"
	bank.play_music("map")
	_checks += 1
	if bank._music_active != before_active:
		_fail("play_music swapped players for the track already playing — the no-op is gone")
	_checks += 1
	if bank._current_music_track != "map":
		_fail("play_music mutated _current_music_track on a same-track call")
	bank._current_music_track = before_track


func _fail(msg: String) -> void:
	_fails.append(msg)


func _report() -> void:
	for f in _fails:
		print("[%s] FAIL: %s" % [PROBE_NAME, f])
	if _fails.is_empty():
		print("[%s] ALL PASS (%d checks)" % [PROBE_NAME, _checks])
	else:
		print("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, _fails.size()])
	get_tree().quit(1 if _fails.size() > 0 else 0)
