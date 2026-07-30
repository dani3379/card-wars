extends SceneTree
## Clash-phrase probe (C5 of docs/ANIMATION_AUDIT_20260716.md §6).
##
## Strike audio climbs through a round's exchange (Card2D._next_clash_pitch) and
## Combat resets it at the top of each round. Four things must hold: the clash
## opens on the root note, the pitch climbs strike over strike, it SATURATES at
## the cap (a long exchange must not shriek — and a missed reset must saturate
## rather than run away), and the reset returns the phrase to the root.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_clash_pitch.gd
## Grep for "ALL PASS" — don't trust the exit code alone.
##
## GOTCHA: Card2D is loaded at RUNTIME (_process), never referenced at compile
## time — Card2D.gd touches the CardDB autoload, and under --script the probe's
## dependencies compile BEFORE autoloads exist. Same trap the campaign-memory
## preload notes describe.

var _ran := false
var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[clash_pitch] PASS  ", label)
	else:
		_fails += 1
		print("[clash_pitch] FAIL  ", label, ("  — " + detail) if detail != "" else "")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var C = load("res://scripts/Card2D.gd")
	if C == null:
		print("[clash_pitch] FAIL  could not load Card2D.gd")
		print("1 FAIL(S)")
		quit(1)
		return true

	# 1. The clash opens on the root note.
	C.reset_clash_pitch()
	var first: float = C._next_clash_pitch()
	_check("clash opens at the root note", is_equal_approx(first, 1.0),
		"got %f, expected 1.0" % first)

	# 2. It climbs, strike over strike.
	var prev := first
	var climbing := true
	for i in range(5):
		var p: float = C._next_clash_pitch()
		if p <= prev:
			climbing = false
		prev = p
	_check("pitch climbs across the exchange", climbing,
		"1.0 → %.3f over 6 strikes" % prev)
	print("[clash_pitch]       (6-strike exchange ends at %.3f)" % prev)

	# 3. It saturates — a 40-strike round, or a missed reset, must not shriek.
	for i in range(40):
		C._next_clash_pitch()
	var capped: float = C._next_clash_pitch()
	var ceiling: float = 1.0 + C.CLASH_PITCH_MAX
	_check("pitch saturates at the cap", capped <= ceiling + 0.0001,
		"got %f, cap %f" % [capped, ceiling])

	# 4. The round boundary returns the phrase to the root.
	C.reset_clash_pitch()
	var after: float = C._next_clash_pitch()
	_check("reset returns the phrase to the root", is_equal_approx(after, 1.0),
		"got %f, expected 1.0" % after)

	print("")
	print("ALL PASS" if _fails == 0 else "%d FAIL(S)" % _fails)
	quit(1 if _fails > 0 else 0)
	return true
