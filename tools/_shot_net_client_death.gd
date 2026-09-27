extends Node
## _shot_net_client_death.gd — WATCH A CREATURE DIE ON THE SKIRMISH CLIENT.
##   Godot.exe --path "D:\Godot" res://tools/_shot_net_client_death.tscn
##
## The client's despawn is the one death animation nobody can see without two
## machines, and until 2026-08-04 it hand-rolled a shrink-spin-fade — a verbatim
## copy of `_die`'s FALLBACK, i.e. the exact beat `_play_burn_death` was written to
## replace. So the writ burned on the host's screen and shrank on the client's.
## It now routes through `Card2D.play_death_flourish`, the visual half of `_die`.
##
## `_probe_net_client_replay` proves that path executes. Only a windowed capture
## proves it BURNS: the burn is a shader on the compact face, and a shader that
## fails to compile renders the sheet untouched with no error anyone would notice.
##
## Drives the real client entry points — `_net_replay_clash` with a host reel, then
## `_net_apply_board_sync` with the two dead bodies absent — so what is photographed
## is the shipping path, not a hand-called animation.
##
## HOUSE TRAPS: all THREE terms of is_connected_to_peer() (or Combat boots SOLO), and
## `get_tree().current_scene` must point at combat (Card2D resolves its VFX host
## through it, so every burst and chip silently no-ops otherwise).

const SHOT_DIR := "res://tools/screenshot/net_client_death"

var _combat: Node = null
var _shot_i: int = 0


func _body(tag: String, hp: int) -> Dictionary:
	var base: Dictionary = CardDB.get_card_data("brute").duplicate(true)
	base["id"] = "shot_%s" % tag
	base["name"] = tag
	base["atk"] = 3
	base["hp"] = hp
	return base


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func():
		print("[ncd] WATCHDOG — never finished")
		get_tree().quit(1))
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.clash_dwell_scale = 1.0
	UserSettings.particles = true
	UserSettings.end_turn_warning = false

	var SS := get_node("/root/SkirmishState")
	var NM := get_node("/root/NetMatch")
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_CLIENT
	SS.local_index = 1
	SS.rng_seed = 1357
	NM.is_host = false
	NM.local_player_index = 1
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true   # the third term — or Combat boots SOLO
	NM.entities.clear()
	NM._next_entity_id = 1

	_combat = load("res://scenes/combat.tscn").instantiate()
	# Pre-settle the opener or `_net_begin_combat` opens the coin-toss modal and
	# holds it (windowed has no headless auto-resolve), scrimming the board this
	# harness exists to photograph.
	_combat._net_first_player_override = 1
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
	await get_tree().create_timer(1.6).timeout
	print("[ncd] booted: is_net=%s client=%s" % [
		str(_combat._is_net()), str(_combat._is_client())])
	if not _combat._is_client():
		print("[ncd] ABORT — booted SOLO; the connection terms did not take")
		get_tree().quit(1)
		return

	_combat._net_spawn_creature(_body("Ours", 4), 8001, 0, _combat.ROW_FRONT, false, false)
	_combat._net_spawn_creature(_body("OursB", 4), 8002, 1, _combat.ROW_FRONT, false, false)
	_combat._net_spawn_creature(_body("Theirs", 4), 9001, 0, _combat.ROW_FRONT, true, false)
	_combat._net_spawn_creature(_body("TheirsB", 4), 9002, 1, _combat.ROW_FRONT, true, false)
	await get_tree().create_timer(1.4).timeout
	await _shoot_png("00_staged")

	# The host's reel: one of ours and one of theirs struck to 0, then the flush.
	print("[ncd] replaying the host reel")
	_combat._net_replay_clash({"strikes": [
		{"cap": "FRONT ROW ATTACKS"},
		{"fo": 0, "fe": true},
		{"l": 9001, "dt": 8001, "latk": 4},
		# `p` is the blow's PRE-mitigation weight (2026-08-04). It is what the client
		# now weighs the hitstop, the tracer and the spark spray by, so a reel written
		# without it photographs the fallback rather than the shipping path.
		{"d": 8001, "hp": 0, "n": 4, "p": 4, "a": 9001, "o": 0, "ahp": 4},
		{"dw": 2},
		{"fo": 1, "fe": false},
		{"l": 8002, "dt": 9002, "latk": 4},
		{"d": 9002, "hp": 0, "n": 4, "p": 4, "a": 8002, "o": 1, "ahp": 4},
		{"dw": 2},
		{"cap": "THE FALLEN"},
		{"fal": true},
		{"fo": -1},
		# The closing ledger, swapped on read: the host wrote it from ITS board.
		{"led": [1, 1]},
	], "atk": 0, "banner": true})
	await _capture(4.5)

	# The trailing snapshot sweeps the corpses — this is the beat under test.
	print("[ncd] trailing snapshot (the corpses go)")
	_combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": 8002, "owner": 1, "lane": 1, "row": _combat.ROW_FRONT,
				"id": "shot_OursB", "atk": 3, "hp": 4, "mhp": 4, "kw": [],
				"floop": false, "token": false},
			{"eid": 9001, "owner": 0, "lane": 0, "row": _combat.ROW_FRONT,
				"id": "shot_Theirs", "atk": 3, "hp": 4, "mhp": 4, "kw": [],
				"floop": false, "token": false},
		],
		"host_hp": _combat.enemy_hp, "client_hp": _combat.player_hp, "active": 1,
	})
	await _capture(3.0)

	print("[ncd] frames written: %d -> %s" % [_shot_i, SHOT_DIR])
	print("[ncd] NET_CLIENT_DEATH_DONE")
	get_tree().quit()


func _capture(seconds: float) -> void:
	var t := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t) < int(seconds * 1000.0):
		Input.warp_mouse(Vector2(4, 4))
		await RenderingServer.frame_post_draw
		var ms := Time.get_ticks_msec() - t
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s/f%03d_%05dms.jpg" % [SHOT_DIR, _shot_i, ms], 0.92)
		_shot_i += 1
		await get_tree().create_timer(0.09).timeout


func _shoot_png(tag: String) -> void:
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, tag])
