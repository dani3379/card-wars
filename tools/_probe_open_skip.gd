extends SceneTree
## OPENING-SKIP probe (2026-07-26). Proves the fight's opening cinematics are
## dismissable, which is the whole point of _await_cinematic / _rushable_pause:
## the intro banner and the opening muster keep their full length for a fight
## you have never seen, and cost almost nothing on the hundredth.
##
## Runs the SAME cold entry twice — once untouched, once with `ui_accept` held
## from the moment the scene is instantiated — and reports time-to-playable for
## each. A working skip shows up as a large drop in pass 2 and NOTHING ELSE
## changing (same board, same hand, same round).
##
## Run WINDOWED (never --headless — the skip paths no-op there by design):
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       --script res://tools/_probe_open_skip.gd

const HERO := "pyromancer"
const ENC := "act1_fight1"
const RUN_SEED := 4242
const TIMEOUT_SEC := 30.0

var RS: Node
var EDB: Node
var US: Node
var SP: Node
var _started := false
var _done := false
var _enc_id := ENC


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SP = root.get_node_or_null("ScenePreload")
	if RS == null or EDB == null:
		print("[skip] FATAL autoloads missing")
		_finish()
		return
	if US != null:
		US.anim_speed = 1.0
		US.end_turn_warning = false
	if not EDB.ENCOUNTERS.has(_enc_id):
		for id in EDB.ENCOUNTERS.keys():
			var d: Dictionary = EDB.ENCOUNTERS[id]
			if int(d.get("act", 1)) == 1 \
					and String(d.get("type", "combat")) == "combat":
				_enc_id = String(id)
				break
	var waited := 0.0
	while SP != null and waited < 20.0:
		if bool(SP.is_warmup_complete()) and bool(SP.get("_prewarmed")):
			break
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(0.8).timeout

	var plain := await _entry(false)
	await create_timer(1.0).timeout
	var rushed := await _entry(true)

	print("[skip] ================ RESULT ================")
	print("[skip]   untouched  : playable at %8.1f ms" % plain.get("t2", -1.0))
	print("[skip]   held accept: playable at %8.1f ms" % rushed.get("t2", -1.0))
	var saved: float = plain.get("t2", 0.0) - rushed.get("t2", 0.0)
	print("[skip]   saved      : %8.1f ms" % saved)
	for k in ["round", "hand", "enemies"]:
		print("[skip]   %-10s : untouched=%s  rushed=%s  %s" % [
			k, str(plain.get(k, "?")), str(rushed.get(k, "?")),
			"OK" if plain.get(k, "?") == rushed.get(k, "?") else "*** DIFFERS ***"])
	var ok: bool = saved > 400.0 \
		and plain.get("round", 0) == rushed.get("round", 1) \
		and plain.get("enemies", 0) == rushed.get("enemies", 1)
	print("[skip] %s" % ("PASS — the opening is dismissable and lands identically"
		if ok else "FAIL — see above"))
	_finish()


func _entry(hold_accept: bool) -> Dictionary:
	RS.start_new_run(HERO, 0, RUN_SEED)
	RS.current_encounter_id = _enc_id
	RS.current_node_type = "combat"
	var scene = load("res://scenes/combat.tscn")
	await process_frame
	var t0 := Time.get_ticks_usec()
	var combat = scene.instantiate()
	root.add_child(combat)
	if hold_accept:
		# Held, not tapped: _rush_requested is level-triggered on purpose, and
		# the cinematic guard window ignores the first ~350 ms anyway.
		Input.action_press("ui_accept")
	var t2 := -1.0
	var deadline := t0 + int(TIMEOUT_SEC * 1_000_000.0)
	# "Playable" must mean SETTLED, not merely momentarily true: _start_round
	# hands the turn over while it is still dealing, and _run_opening_muster
	# takes it straight back (phase = RESOLVING). Sampling the first frame that
	# looks playable catches the fight mid-deal and reports a hand of one.
	# ...and the HAND SIZE must have stopped moving too. _start_round is called
	# without await, so the round-1 deal runs detached alongside the muster: cut
	# the muster short and the fight is "playable" while cards are still landing.
	var steady := 0
	var last_hand := -1
	while Time.get_ticks_usec() < deadline:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(combat):
			break
		var hand: int = combat._hand.size()
		if combat.phase == combat.Phase.PLAYER_TURN and hand > 0 \
				and hand == last_hand \
				and not bool(combat._opening_muster_pending):
			steady += 1
			if steady >= 12:
				t2 = float(Time.get_ticks_usec() - t0) / 1000.0
				break
		else:
			steady = 0
		last_hand = hand
	if hold_accept:
		Input.action_release("ui_accept")
	var res := {"t2": snappedf(t2, 0.1)}
	if is_instance_valid(combat):
		res["round"] = combat.round_number
		res["hand"] = combat._hand.size()
		var n := 0
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			for c in combat._row_array(true, row):
				if c != null and is_instance_valid(c):
					n += 1
		res["enemies"] = n
		combat.queue_free()
	print("[skip] %s -> playable %.1f ms (round %s, hand %s, enemies %s)" % [
		"HELD ui_accept" if hold_accept else "untouched      ",
		res.get("t2", -1.0), str(res.get("round", "?")),
		str(res.get("hand", "?")), str(res.get("enemies", "?"))])
	await process_frame
	return res


func _finish() -> void:
	_done = true
	quit()
