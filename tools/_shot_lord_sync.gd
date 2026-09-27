extends Node
## _shot_lord_sync.gd — renders the MP lord-pick system to PNG (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_lord_sync.tscn
## Shots (tools/screenshot/_lordsync_*.png):
##   lobby   the net lobby ready panel with the MARCH AS picker (raider picked,
##           foe pick shown as Kindler in the "Their lord" readout)
##   plates  net combat as host: OWN lord (raider) on the bottom-left plate, the
##           OPPONENT'S lord (kindler) on the top-right plate + lord-titled marquee
##   menu    the emote menu open — six lines in the RAIDER voice
##   bubbles both emote bubbles at once: raider line (you) + kindler line (foe)

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

	var SS := get_node("/root/SkirmishState")
	var NM := get_node("/root/NetMatch")

	# ── Shot 1: the lobby's ready panel with the lord picker ──
	var lobby: Node = load("res://scenes/net_lobby.tscn").instantiate()
	get_tree().root.add_child(lobby)
	await get_tree().create_timer(0.8).timeout
	# Fake a hosted room with a connected friend so the ready panel shows.
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.remote_hero = "kindler"
	lobby.call("_on_hero_chosen", "raider")
	lobby.get("_connect_panel").visible = false
	lobby.call("_show_ready_panel")
	await get_tree().create_timer(0.5).timeout
	await _shoot("lobby")
	# Practice panel carries the same picker (no opponent readout).
	lobby.get("_ready_panel").visible = false
	lobby.call("_on_vs_bot_pressed")
	await get_tree().create_timer(0.4).timeout
	await _shoot("vsbot")
	lobby.queue_free()
	await get_tree().process_frame

	# ── Fake a connected net host (no socket), same as _shot_net_clash ──
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	SS.slots[0].hero_id = "raider"    # what begin_session seats from the lobby picks
	SS.slots[1].hero_id = "kindler"
	# ALL THREE net terms before the combat boot. The lobby block above armed
	# _connected + remote_present only; without the third, Combat._ready boots
	# SOLO and the plate shows a campaign face instead of the synced lord.
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
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
	await get_tree().create_timer(3.0).timeout
	await _shoot("plates")

	# ── Emote menu in the RAIDER voice ──
	_combat.call("_open_emote_menu")
	await get_tree().create_timer(0.4).timeout
	await _shoot("menu")
	_combat.call("_close_emote_menu")
	await get_tree().create_timer(0.2).timeout

	# ── Both bubbles at once, each in its lord's voice ──
	_combat.call("_player_emote", 5)        # raider threat: "You can't outrun me."
	_combat.call("_net_show_foe_emote", 3)  # kindler wow:   "BOOM. Beautiful."
	await get_tree().create_timer(0.45).timeout
	await _shoot("bubbles")

	print("LORD_SYNC_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_lordsync_%s.png" % tag)
	print("SAVED lordsync_", tag, " ", img.get_size())
