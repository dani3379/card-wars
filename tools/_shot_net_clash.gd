extends Node
## _shot_net_clash.gd — LOOK AT THE SKIRMISH CLASH.
##   Godot.exe --path "D:\Godot" res://tools/_shot_net_clash.tscn
##
## `_probe_net_clash_beats` proves the skirmish clash now RAISES the campaign's
## captions, moves the spotlight, paces its corpse flush and ships all of it to the
## watching peer. It cannot answer the question that actually decides whether the two
## modes feel like one game: does it READ. This is the eyes half.
##
## Windowed by necessity — the beats being photographed (`_lane_dwell`,
## `_cleanup_dead_paced`) return immediately headless, so a headless capture would
## photograph the burst this pass removed.
##
## The board is fixed so the outcome pattern is known before the shutter opens:
##   lane 0 front  mutual kill      (two corpses in one column — earns the KILL dwell)
##   lane 1 front  neither dies     (the control lane — is its MINOR dwell distinct?)
##   lane 2 front  the foe's body dies alone
##   lane 3 back   a back-rank pair, so THE BACK RANK is a named beat WITH content
## Three corpses, which also trips the mass-grave punctuation.
##
## HOUSE TRAPS, both of which this file has been caught by:
##   * All THREE terms of is_connected_to_peer() must be set — `_connected`,
##     `remote_present` AND `_compatibility_confirmed` — or Combat boots SOLO and the
##     harness silently photographs the campaign clash instead of the skirmish one.
##   * `get_tree().current_scene` must point at the combat scene: Card2D's VFX host
##     resolves through it, so `add_child()` alone leaves every damage number,
##     keyword chip and log row silently no-opping.

const SHOT_DIR := "res://tools/screenshot/net_clash"

var _combat: Node = null
var _shot_i: int = 0


func _body(tag: String, atk: int, hp: int) -> Dictionary:
	var base: Dictionary = CardDB.get_card_data("brute").duplicate(true)
	base["id"] = "shot_%s" % tag
	base["name"] = tag
	base["atk"] = atk
	base["hp"] = hp
	return base


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[nsc] WATCHDOG — never finished")
		get_tree().quit(1))
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# SHIP SETTINGS, not this machine's — photographing the Reduce Motion fallback
	# would answer a different question than the one asked.
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.clash_dwell_scale = 1.0
	UserSettings.particles = true
	UserSettings.screen_shake = true
	UserSettings.end_turn_warning = false

	# ── Fake a connected net host (no socket) ──
	var SS := get_node("/root/SkirmishState")
	var NM := get_node("/root/NetMatch")
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 24680
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true   # the third term — see the header
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	_combat = load("res://scenes/combat.tscn").instantiate()
	_combat._net_first_player_override = 0
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	await get_tree().process_frame
	get_viewport().gui_disable_input = true
	Input.warp_mouse(Vector2(4, 4))
	await get_tree().create_timer(0.6).timeout
	if _combat._hand.is_empty():
		_combat._net_begin_combat()
	for _i in 12:
		await get_tree().create_timer(0.3).timeout
		if _combat._hand.size() > 0:
			break
	await get_tree().create_timer(2.0).timeout   # let the opening banner clear
	print("[nsc] booted: is_net=%s active=%d" % [
		str(_combat._is_net()), _combat._net_active_index])
	if not _combat._is_net():
		print("[nsc] ABORT — booted SOLO; the connection terms did not take")
		get_tree().quit(1)
		return

	_combat._net_turn_round = 2
	_stage()
	_combat.player_hp = 18
	_combat.enemy_hp = 22
	_combat._update_hud()
	await get_tree().create_timer(1.4).timeout   # landing pops settle
	await _shoot_png("00_staged")

	print("[nsc] clash begins")
	# The real commit drops the planning overlay before the lines meet; this harness
	# calls the resolver directly, so do what _net_on_done_placing would have done —
	# otherwise the shot photographs forecast chips the shipping flow has cleared.
	_combat._clear_threat_flags()
	_combat.phase = _combat.Phase.RESOLVING
	_combat._net_run_clash(-1)
	await _capture(11.0)

	print("[nsc] frames written: %d -> %s" % [_shot_i, SHOT_DIR])
	print("[nsc] NET_CLASH_SHOTS_DONE")
	get_tree().quit()


func _stage() -> void:
	_combat._net_spawn_creature(_body("Ours-A", 5, 1), 6001, 0, _combat.ROW_FRONT, false, false)
	_combat._net_spawn_creature(_body("Ours-B", 1, 9), 6002, 1, _combat.ROW_FRONT, false, false)
	_combat._net_spawn_creature(_body("Ours-C", 6, 9), 6003, 2, _combat.ROW_FRONT, false, false)
	_combat._net_spawn_creature(_body("Ours-D", 4, 4), 6004, 3, _combat.ROW_BACK, false, false)
	_combat._net_spawn_creature(_body("Theirs-A", 5, 1), 7001, 0, _combat.ROW_FRONT, true, false)
	_combat._net_spawn_creature(_body("Theirs-B", 1, 9), 7002, 1, _combat.ROW_FRONT, true, false)
	_combat._net_spawn_creature(_body("Theirs-C", 1, 2), 7003, 2, _combat.ROW_FRONT, true, false)
	_combat._net_spawn_creature(_body("Theirs-D", 2, 2), 7004, 3, _combat.ROW_BACK, true, false)
	# The muster delay holds every arrival for the round it landed in; stand them up
	# so this is a photograph of a clash, not of eight bodies forming up.
	for c in _combat._all_creatures_both_sides():
		c.state.ready_to_swing = true
		c.has_attacked_this_turn = false


func _capture(seconds: float) -> void:
	var t := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t) < int(seconds * 1000.0):
		Input.warp_mouse(Vector2(4, 4))
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - t
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s/f%03d_%05dms.jpg" % [SHOT_DIR, _shot_i, ms], 0.92)
		_shot_i += 1
		await get_tree().create_timer(0.11).timeout


func _shoot_png(tag: String) -> void:
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
