extends Node
## _shot_phase_beats.gd — visual check for the 2026-07-20 phase-VFX cut
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_phase_beats.tscn
##
## No harness covered the combat sub-phase announcements, which is how the
## clash beat ended up announcing itself TWICE (commit VFX + phase sweep) with
## nobody noticing. Shoots each beat at its peak so the question "does this
## still read, now that the streak sweeps and the midline flash are gone?" is
## answered by pixels instead of by intuition:
##   clash_commit  ~0.12s after _play_clash_commit_vfx  (ring + lane streaks +
##                 end-turn punch; NO screen-wide colour bar across the board)
##   clash_title   the CLASH title card alone — the beat it now owns solo
##   fallen        THE FALLEN title card + its surviving ring
##   reinforce     ENEMY REINFORCES title card + its surviving ring
##   rest          everything expired; board back at rest (no stuck Line2D)
## Outputs tools/screenshot/_phase_*.png
##
## ── STAGE ON ROUND NUMBER, NEVER ON A SLEEP (2026-07-29) ─────────────────────
## This used to sleep 6 s and assert in a comment that "bodies are on the board
## from the encounter's opening wave". Since TAKE THE FIELD (2026-07-27) that is
## false: `_opening_muster_pending` is consumed by `_enemy_place_creatures`
## inside `_post_combat_sequence`, so the hold arrives at the END of round 1 and
## every one of these frames was being shot over an EMPTY arena — which is
## exactly the thing clash_commit exists to check, since its lane streaks only
## fire on OCCUPIED lanes. Now it plays into round 2 and asserts occupancy.

const STATE_TIMEOUT := 60.0
const POLL := 0.2

var _combat: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	# A windowed harness sits in the live desktop session with its window
	# foregrounded, so stray keystrokes really do reach Combat._input.
	if UserSettings != null:
		UserSettings.end_turn_warning = false

	RunState.start_new_run("raider")
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	# The harness drives every beat by direct call; raw input off keeps the
	# glossary primer from opening over a frame.
	_combat.set_process_input(false)

	# Play into round 2 — the first board that actually has an enemy line on it
	# (see header). Then let the "ROUND 2" banner clear: it is 70px type across
	# the middle of the arena and would bury the beat being photographed.
	if not await _await_state(1, false, "round 1 player turn"):
		return
	_combat.call("_on_end_turn")
	if not await _await_state(2, true, "round 2 player turn with a live hold"):
		return
	await get_tree().create_timer(1.8).timeout
	print("[phase] staged at round %d — enemy bodies=%d  your bodies=%d" % [
		int(_combat.get("round_number")),
		(_combat.call("_all_enemy_creatures") as Array).size(),
		(_combat.call("_all_player_creatures") as Array).size()])

	# The commit beat, caught mid-flight. Bodies really are on the board now, so
	# the occupied-lane streaks actually fire.
	_combat.call("_play_clash_commit_vfx")
	await get_tree().create_timer(0.12).timeout
	await _shoot("clash_commit")
	await get_tree().create_timer(0.9).timeout

	# Each phase title card at its hold. _set_phase_caption only pulses on a
	# CHANGE, so park on a neutral caption between beats.
	for beat in [
		{"cap": "CLASH", "tag": "clash_title"},
		{"cap": "THE FALLEN", "tag": "fallen"},
		{"cap": "ENEMY REINFORCES", "tag": "reinforce"},
	]:
		_combat.call("_set_phase_caption", "")
		await get_tree().process_frame
		_combat.call("_set_phase_caption", String(beat["cap"]))
		await get_tree().create_timer(0.30).timeout
		await _shoot(String(beat["tag"]))
		await get_tree().create_timer(0.9).timeout

	# Everything must expire cleanly — a stuck Line2D or a midline left at full
	# alpha would show here.
	_combat.call("_set_phase_caption", "")
	await get_tree().create_timer(1.2).timeout
	await _shoot("rest")

	print("PHASE_SHOTS_DONE")
	get_tree().quit()


## Poll until the fight really is at `min_round`, back in the player's hands, and
## (when `want_enemies`) actually has an enemy line standing.
func _await_state(min_round: int, want_enemies: bool, what: String) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if _combat == null or not is_instance_valid(_combat):
			print("[phase] ABORT — combat scene gone while waiting for ", what)
			get_tree().quit(1)
			return false
		var rn: int = int(_combat.get("round_number"))
		if rn >= min_round \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN \
				and (not want_enemies
					or (_combat.call("_all_enemy_creatures") as Array).size() > 0):
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[phase] ABORT — timed out waiting for ", what,
		"  (round=", _combat.get("round_number"), " phase=", _combat.get("phase"),
		" enemies=", (_combat.call("_all_enemy_creatures") as Array).size(), ")")
	get_tree().quit(1)
	return false


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_phase_%s.png" % tag)
	print("SAVED phase_", tag, " ", img.get_size())
