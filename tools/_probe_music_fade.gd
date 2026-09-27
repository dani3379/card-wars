extends Node
## MUSIC CROSSFADE GATE (2026-09-14) — the seam, not the songs.
##
## Runs as a SCENE so the AudioBank autoload exists, then drives AudioBank's own
## _crossfade_step across t = 0..1 and reads volume_db back off the two real
## music players. Asserts the constant-power law:
##
##     amp_in² + amp_out² == 1   at every t
##
## which is what keeps the SUM flat while one track replaces another. The law
## this replaced interpolated volume_db LINEARLY, putting both tracks at -20 dB
## (a tenth of amplitude each) at the midpoint — measured on the shipped assets
## as a 21 dB hole in the middle of every transition.
##
## Why a gate and not a one-off measurement: the failure is INAUDIBLE AS A BUG.
## It does not crackle or error; the music just briefly ducks, which reads as
## "the soundtrack is a bit odd" rather than as a defect with a line number. It
## survived in the codebase for months for exactly that reason, and the obvious
## "fix" — tweening volume_db, which is what every Godot fade example does — is
## the bug. Anyone rewriting this fade will reach for tween_property again.
##
## Run: Godot.exe --headless --path "D:\Godot" res://tools/_probe_music_fade.tscn

const PROBE_NAME := "music_fade"
# Constant-power sum, in dB. Anything outside this is an audible level change
# mid-transition; 0.5 dB is below the ~1 dB just-noticeable difference.
const SUM_TOLERANCE_DB := 0.5
# The floor AudioBank clamps to. The two ENDS of the fade legitimately sit at
# the floor (the other track is at full and masks them), so they are exempt from
# the sum check — only the body of the fade must hold power.
const FLOOR_DB := -60.0

var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	var bank := get_node_or_null("/root/AudioBank")
	if bank == null:
		_fail("AudioBank autoload not present — probe must run as a SCENE")
		_report()
		return

	_check_law(bank)
	_check_floor_is_finite(bank)
	_check_single_tween_field(bank)
	_report()


## The core assertion: sweep t and require the summed power to stay flat.
func _check_law(bank: Node) -> void:
	var a: AudioStreamPlayer = bank.get("_music_a")
	var b: AudioStreamPlayer = bank.get("_music_b")
	if a == null or b == null:
		_fail("music players not built (_music_a/_music_b null)")
		return

	# BOTH legs must go through the real function, so the outgoing player has to
	# be genuinely PLAYING — _crossfade_step skips a stopped one (there is
	# nothing to fade out). A generator stream is playable with no file IO and
	# no decode, which keeps this probe cheap enough to sit in a pre-commit set.
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	b.stream = gen
	b.play()
	if not b.playing:
		_fail("outgoing player would not start — cannot exercise the fade-out leg")
		return

	var worst := 0.0
	var worst_t := 0.0
	var sampled := 0
	for i in 101:
		var t := float(i) / 100.0
		bank._crossfade_step(t, a, b)
		var amp_in: float = db_to_linear(a.volume_db)
		var amp_out: float = db_to_linear(b.volume_db)
		# The two ENDS legitimately sit on the clamp floor — there the other
		# track is at full level and masks it, so power is not required to hold.
		if a.volume_db <= FLOOR_DB + 0.01 or b.volume_db <= FLOOR_DB + 0.01:
			continue
		var sum_db: float = 10.0 * log(amp_in * amp_in + amp_out * amp_out) / log(10.0)
		sampled += 1
		_checks += 1
		if absf(sum_db) > absf(worst):
			worst = sum_db
			worst_t = t
	b.stop()
	b.stream = null
	if sampled < 50:
		_fail("only %d of 101 fade samples were above the floor — law untested" % sampled)
		return
	if absf(worst) > SUM_TOLERANCE_DB:
		_fail("crossfade is not constant-power: worst sum %.2f dB at t=%.2f (tol %.2f)"
			% [worst, worst_t, SUM_TOLERANCE_DB])
	else:
		print("[%s] constant-power holds: worst deviation %.3f dB at t=%.2f over %d samples"
			% [PROBE_NAME, worst, worst_t, sampled])


## linear_to_db(0.0) is -inf and a -inf write to volume_db is rejected by the
## engine, which would silently abort the fade step mid-function. The clamp is
## the only thing standing between t=0 and that.
func _check_floor_is_finite(bank: Node) -> void:
	_checks += 1
	var v: float = bank._fade_gain_db(0.0)
	if not is_finite(v):
		_fail("_fade_gain_db(0.0) returned %s — a non-finite volume_db write aborts the step" % v)
	_checks += 1
	if not is_equal_approx(bank._fade_gain_db(1.0), 0.0):
		_fail("_fade_gain_db(1.0) should be 0 dB (unity), got %f" % bank._fade_gain_db(1.0))


## Two tweens writing the same two volume_db properties is the other half of the
## bug: the loser goes on driving a player the winner just started, and its
## trailing stop() callback kills live music. One tracked tween, always.
func _check_single_tween_field(bank: Node) -> void:
	_checks += 1
	if not ("_music_tween" in bank):
		_fail("AudioBank has no _music_tween field — overlapping fades cannot be cancelled")


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
