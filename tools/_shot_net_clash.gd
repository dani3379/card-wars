extends Node
## _shot_net_clash.gd — renders a MULTIPLAYER one-directional clash to a burst of PNGs
## so the attack animation can be inspected frame-by-frame (Cross-Blitz mutual trade).
##   Godot.exe --path "D:\Godot" res://tools/_shot_net_clash.tscn
## Stages tanky 1/12 creatures on BOTH sides in lanes 0-2 (they survive the trade, so
## any post-clash DRIFT out of the slot is visible), then fires _net_run_clash(0) (HOST
## strikes) and grabs frames across the whole clash. Outputs tools/screenshot/_netclash_*.png

var _combat: Node = null
var _shot_i: int = 0


func _tank(tag: String) -> Dictionary:
	return {
		"id": "shot_%s" % tag, "name": "Tank%s" % tag, "type": "creature",
		"cost": 1, "atk": 1, "hp": 12, "rarity": "common", "keywords": [], "desc": "",
	}


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# ── Fake a connected net host (no socket), same as _probe_skirmish_combat ──
	var SS := get_node("/root/SkirmishState")
	var NM := get_node("/root/NetMatch")
	var CDB := get_node("/root/CardDB")
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	_combat = load("res://scenes/combat.tscn").instantiate()
	_combat._net_first_player_override = 0
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	await get_tree().create_timer(0.6).timeout
	if _combat._hand.is_empty():
		_combat._net_begin_combat()
	# Let the opening turn settle (banner sweep etc.).
	await get_tree().create_timer(3.0).timeout

	# Advance into a round where clashes fire, and place REAL brutes (2/3) on both
	# sides — they survive the first trade (→1/3) and MUTUALLY DIE on the second, so
	# the capture shows trades, counters, and mutual-death beats like a real fight.
	_combat._net_turn_round = 2
	var eid := 60000
	for lane in [0, 1, 2]:
		_combat._net_spawn_creature(CDB.get_card_data("brute"), eid, lane, _combat.ROW_FRONT, false, false)
		eid += 1
		_combat._net_spawn_creature(CDB.get_card_data("brute"), eid, lane, _combat.ROW_FRONT, true, false)
		eid += 1
	# Match the reported screenshot's HP (player 18/30, foe 5/30) so the plate size
	# can be judged against it directly.
	_combat.player_hp = 18
	_combat.enemy_hp = 5
	_combat._update_hud()
	# Let the landing-pops settle so we start from clean rest positions.
	await get_tree().create_timer(1.2).timeout
	await _shoot()   # frame 00: at rest, pre-clash — HP plates visible here

	# CLASH 1 (both survive at 1/3): fast burst across the whole thing.
	_combat._net_run_clash(0)
	for _i in range(14):
		await get_tree().create_timer(0.05).timeout
		await _shoot()
	await get_tree().create_timer(0.8).timeout
	await _shoot()   # settled after clash 1

	# CLASH 2 (mutual death): fast burst so the kills + counters are visible.
	_combat._net_run_clash(0)
	for _i in range(16):
		await get_tree().create_timer(0.05).timeout
		await _shoot()
	await get_tree().create_timer(1.0).timeout
	await _shoot()   # settled after clash 2

	print("NET_CLASH_SHOTS_DONE")
	get_tree().quit()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_netclash_%02d.png" % _shot_i)
	_shot_i += 1
