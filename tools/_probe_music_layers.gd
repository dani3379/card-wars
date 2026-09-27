extends Node
## VERTICAL LAYERING GATE (2026-09-14).
##
## The layered cue is the only music in the game whose correctness is invisible
## to every other check: it resolves, it loads, it plays, and it can still be
## completely wrong — a stem that does not loop silently kills the whole cue
## partway through, a layer stuck on removes the dynamics without erroring, and
## an intensity mapping that never leaves 1 just plays a normal track forever.
## None of that throws.
##
## Run: Godot.exe --headless --path "D:\Godot" res://tools/_probe_music_layers.tscn

const PROBE_NAME := "music_layers"
# Every registered cue is checked, not a hardcoded one: the registry is the thing
# that grows (act 2, act 3, bosses…), and a gate that only ever looked at act 1
# would go green while a newly added cue shipped with a dead stem.
const LAYER_COUNT_EXPECTED := 3  # bed / percussion / voices — the index contract
                                 # Combat._music_intensity drives by number.
# Stems must agree in length or the layers drift apart on loop — the one defect
# here that gets WORSE the longer the fight runs.
const LENGTH_TOLERANCE_S := 0.10

var _fails: Array[String] = []
var _checks := 0


func _ready() -> void:
	var bank := get_node_or_null("/root/AudioBank")
	if bank == null:
		_fail("AudioBank autoload not present — probe must run as a SCENE")
		_report()
		return
	var cues: Array = bank.LAYERED_CUES.keys()
	cues.sort()
	_checks += 1
	if cues.is_empty():
		_fail("LAYERED_CUES is empty — nothing is layered at all")
		_report()
		return
	for cue in cues:
		_phase_a_registry(bank, String(cue))
		await _phase_b_build_and_loop(bank, String(cue))
	# The runtime behaviour is one implementation shared by every cue, so it is
	# exercised once, on the first.
	await _phase_b_build_and_loop(bank, String(cues[0]))
	await _phase_c_layer_moves(bank)
	_phase_d_intensity_mapping()
	_phase_e_wiring(bank, cues)
	print("[%s] cues checked: %s" % [PROBE_NAME, ", ".join(cues)])
	_report()


## A. The registry resolves, and the availability check is honest in both
##    directions — it is the fallback switch, so a version that always says yes
##    would ship silent battles.
func _phase_a_registry(bank: Node, cue: String) -> void:
	for p in bank.LAYERED_CUES[cue]:
		_checks += 1
		if not ResourceLoader.exists(String(p)):
			_fail("[%s] stem missing: %s" % [cue, p])
	_checks += 1
	if bank.LAYERED_CUES[cue].size() != LAYER_COUNT_EXPECTED:
		_fail("[%s] has %d layers, the intensity mapping drives %d by index"
			% [cue, bank.LAYERED_CUES[cue].size(), LAYER_COUNT_EXPECTED])
	_checks += 1
	if not bank.layered_cue_available(cue):
		_fail("layered_cue_available('%s') is false with every stem present" % cue)
	# The cue key must be a real track name, because Combat derives it from
	# pool[0] — the flat fallback and the layered cue have to be the same piece.
	_checks += 1
	if bank._resolve_music_path(cue) == "":
		_fail("[%s] is not a real track name — Combat keys the cue off pool[0]" % cue)
	_checks += 1
	if bank.layered_cue_available("__no_such_cue__"):
		_fail("layered_cue_available said yes to a cue that does not exist")


## B. Build it for real and check the two things the ENGINE requires, which the
##    class docs do not state: every sub-stream must loop (mix() sets
##    active = false the moment none is playing, so one short stem ends the cue),
##    and the stems must be the same length.
func _phase_b_build_and_loop(bank: Node, cue: String) -> void:
	# stop first: play_layered_cue no-ops if this cue is already current, which
	# would silently make every cue after the first re-measure the first one.
	bank.stop_music(0.01)
	for i in 10:
		await get_tree().process_frame
	bank.play_layered_cue(cue, 0.05)
	for i in 240:
		await get_tree().process_frame
		if bank.music_layer_count() > 0:
			break
	_checks += 1
	var n: int = bank.music_layer_count()
	if n != bank.LAYERED_CUES[cue].size():
		_fail("[%s] built %d layers, registry lists %d" % [cue, n, bank.LAYERED_CUES[cue].size()])
		return
	var sync: AudioStreamSynchronized = bank._music_active.stream as AudioStreamSynchronized
	_checks += 1
	if sync == null:
		_fail("[%s] active stream is not an AudioStreamSynchronized" % cue)
		return
	var len0 := 0.0
	for i in n:
		var sub: AudioStream = sync.get_sync_stream(i)
		_checks += 1
		if sub == null:
			_fail("[%s] layer %d has no stream" % [cue, i])
			continue
		_checks += 1
		if ("loop" in sub) and not sub.loop:
			_fail("[%s] layer %d does not loop — mix() will stop the whole cue when it ends" % [cue, i])
		if i == 0:
			len0 = sub.get_length()
		else:
			_checks += 1
			if absf(sub.get_length() - len0) > LENGTH_TOLERANCE_S:
				_fail("[%s] layer %d is %.3fs, bed is %.3fs — layers will drift apart on loop"
					% [cue, i, sub.get_length(), len0])
	# The bed carries the cue; everything else must start silent or the
	# arrangement opens at full intensity and the escalation never reads.
	_checks += 1
	if not is_equal_approx(sync.get_sync_stream_volume(0), 0.0):
		_fail("[%s] bed did not open at 0 dB (got %.2f)" % [cue, sync.get_sync_stream_volume(0)])
	for i in range(1, n):
		_checks += 1
		if sync.get_sync_stream_volume(i) > bank.LAYER_OFF_DB + 0.01:
			_fail("[%s] layer %d opened audible (%.2f dB) — it should start off"
				% [cue, i, sync.get_sync_stream_volume(i)])
	print("[%s]   %-14s %d layers, all looping, %.1fs" % [PROBE_NAME, cue, n, len0])


## C. Raising a layer must actually move the resource volume, and it must move it
##    GRADUALLY — mix() applies the value per 128-frame chunk as a step, so an
##    assigned jump is a click. A re-assert of the same target must not restart
##    the fade, because _start_round asserts every round.
func _phase_c_layer_moves(bank: Node) -> void:
	var sync: AudioStreamSynchronized = bank._music_active.stream as AudioStreamSynchronized
	if sync == null:
		return
	var before: float = sync.get_sync_stream_volume(1)
	bank.set_music_layer(1, true, 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	var mid: float = sync.get_sync_stream_volume(1)
	_checks += 1
	if is_equal_approx(mid, before):
		_fail("raising layer 1 did not change its volume at all")
	_checks += 1
	if mid >= 0.0:
		_fail("layer 1 jumped straight to full (%.2f dB) — a snapped volume clicks" % mid)
	# Re-asserting the same target must be dropped.
	var t_before: float = sync.get_sync_stream_volume(1)
	bank.set_music_layer(1, true, 0.5)
	await get_tree().process_frame
	_checks += 1
	if sync.get_sync_stream_volume(1) < t_before:
		_fail("re-asserting an in-flight layer target restarted its fade (went backwards)")
	# Settle, then confirm it arrives at unity rather than parking short.
	for i in 90:
		await get_tree().process_frame
		if is_equal_approx(sync.get_sync_stream_volume(1), 0.0):
			break
	_checks += 1
	if not is_equal_approx(sync.get_sync_stream_volume(1), 0.0):
		_fail("layer 1 never reached 0 dB (stuck at %.2f)" % sync.get_sync_stream_volume(1))
	_checks += 1
	if not bank.music_layer_is_on(1):
		_fail("music_layer_is_on(1) is false after raising it")
	# And leaving the cue must drop the layer bookkeeping, or a stale tween goes
	# on writing volumes into a cached resource.
	bank.stop_music(0.05)
	for i in 30:
		await get_tree().process_frame
	_checks += 1
	if bank.music_layer_count() != 0:
		_fail("layer state survived stop_music — a stale tween can still write")


## D. The mapping itself. Instantiated bare (no tree): _music_intensity reads
##    five plain ints and nothing else, which is exactly why it was written that
##    way.
func _phase_d_intensity_mapping() -> void:
	var combat_script := load("res://scripts/scenes/Combat.gd")
	if combat_script == null:
		_fail("could not load Combat.gd")
		return
	var c = combat_script.new()
	c.player_max_hp = 30
	c.enemy_max_hp = 30
	var cases := [
		# round, hero_hp, foe_hp, expected, why
		[1, 30, 30, 0, "muster round is bed only"],
		[2, 30, 30, 1, "ordinary fighting adds percussion"],
		[5, 30, 30, 1, "a long healthy fight stays at 1"],
		[3,  8, 30, 2, "hero under pressure raises the voices"],
		[3, 30,  7, 2, "foe nearly dead raises the voices"],
		[1,  2,  2, 0, "the muster round outranks pressure"],
	]
	for case in cases:
		c.round_number = case[0]
		c.player_hp = case[1]
		c.enemy_hp = case[2]
		_checks += 1
		var got: int = c._music_intensity()
		if got != case[3]:
			_fail("intensity(round=%d hero=%d foe=%d) = %d, expected %d — %s"
				% [case[0], case[1], case[2], got, case[3], case[4]])
	c.free()
	print("[%s] intensity mapping: %d cases" % [PROBE_NAME, cases.size()])


## E. The mapping is worthless if nothing calls it, and a layered cue that is
##    never updated is just a quieter version of the flat track.
func _phase_e_wiring(bank: Node, cues: Array) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	_checks += 1
	if src == "":
		_fail("could not read Combat.gd")
		return
	for needle in ["_update_music_layers()", "play_layered_cue(", "layered_cue_available("]:
		_checks += 1
		if not src.contains(needle):
			_fail("Combat.gd no longer calls %s" % needle)
	# It must be asserted on the round ladder, not only at cue start.
	var idx := src.find("func _start_round()")
	_checks += 1
	if idx < 0 or not src.substr(idx, 900).contains("_update_music_layers()"):
		_fail("_start_round no longer refreshes the layers — intensity would freeze at its opening value")
	# EVERY FIGHT IN THE GAME MUST BE REACHABLE, BOTH DIRECTIONS.
	#
	# Combat keys the cue off the book's ANCHOR, so: an anchor with no registered
	# cue means that fight class silently plays flat, and a registered cue that is
	# no fight's anchor is dead content — it would pass every other check in this
	# file and never play once.
	#
	# The fights are ENUMERATED by calling Combat's own _combat_music_book rather
	# than scraping pool literals out of the source, which is why that function is
	# static and pure. Scraping could only ever approximate the boss branch, where
	# the track depends on the rival lord.
	var cs := load("res://scripts/scenes/Combat.gd")
	_checks += 1
	if cs == null:
		_fail("could not load Combat.gd to enumerate fights")
		return
	var rivals := ["rival_stalwart", "rival_raider", "rival_acolyte",
		"rival_pyromancer", "rival_kindler", "__not_a_rival__"]
	var fights: Array = []          # [label, node_type, act, encounter]
	for a in [1, 2, 3]:
		fights.append(["plain act %d" % a, "combat", a, ""])
		fights.append(["elite act %d" % a, "elite", a, ""])
	for r in rivals:
		fights.append(["boss act 2 / %s" % r, "boss", 2, r])
	fights.append(["boss act 3", "boss", 3, ""])

	var anchors := {}
	for f in fights:
		var book: Array = cs._combat_music_book(String(f[1]), int(f[2]), String(f[3]))
		_checks += 1
		if book.is_empty():
			_fail("%s produced an empty book — that fight would be silent" % f[0])
			continue
		var anchor := String(book[0])
		anchors[anchor] = true
		# Every name in every book must be a real track, layered or not.
		for t in book:
			_checks += 1
			if bank._resolve_music_path(String(t)) == "":
				_fail("%s names track '%s', which resolves to no file" % [f[0], t])
		_checks += 1
		if not bank.LAYERED_CUES.has(anchor):
			_fail("%s: anchor '%s' has no layered cue — that fight still plays flat"
				% [f[0], anchor])
	for cue in cues:
		_checks += 1
		if not anchors.has(String(cue)):
			_fail("cue '%s' is registered but is no fight's anchor — it can never play" % cue)
	print("[%s] fights enumerated: %d, distinct anchors: %d"
		% [PROBE_NAME, fights.size(), anchors.size()])


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
