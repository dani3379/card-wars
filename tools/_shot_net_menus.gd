extends Node
## _shot_net_menus.gd — renders every multiplayer menu screen to PNG for a
## quality audit (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_net_menus.tscn
## Outputs tools/screenshot/_net_<name>.png
##
## States:
##   lobby          — net_lobby fresh (connect panel)
##   lobby_bot      — practice-vs-bot sub-panel open
##   lobby_ready    — connected host view (lord pick + mode/format/style + ready)
##   arsenal        — the shared arsenal overlay (first relic slate)
##   draft          — card-triplet stage with a few picks in the ledger
##   quick          — quick battle deck preview
##   constructed    — constructed pool + deck columns
##   sealed         — sealed pool + deck columns

var _scene: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame

	# ── Lobby: fresh ──
	_scene = load("res://scenes/net_lobby.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(3.2).timeout
	await _snap("lobby")

	# ── Lobby: practice panel ──
	_scene.call("_on_vs_bot_pressed")
	await get_tree().create_timer(0.8).timeout
	await _snap("lobby_bot")
	_scene.call("_on_vs_bot_back")
	await get_tree().process_frame

	# ── Lobby: connected host view (mirror the real relay flow: room created →
	# connect panel folds away → peer joins with a picked lord + READY). ──
	NetMatch.is_host = true
	_scene.call("_on_room_created", "KM7Q2R")
	await get_tree().process_frame
	NetMatch.remote_present = true
	NetMatch.remote_hero = "stalwart"
	NetMatch.remote_ready = true
	_scene.call("_on_peer_joined", 2)
	await get_tree().create_timer(0.8).timeout
	await _snap("lobby_ready")

	# ── Lobby: watchword copied (click the docket, catch the caption flip) ──
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_scene.call("_on_code_chit_input", click, _scene.get("_code_plate"))
	await get_tree().create_timer(0.25).timeout
	await _snap("lobby_copied")
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── Draft (vs bot): arsenal overlay, then triplet + ledger ──
	NetMatch.start_vs_bot(SkirmishState.MatchMode.DRAFT, 1)
	_scene = load("res://scenes/net_draft.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(3.2).timeout
	await _snap("arsenal")
	# Take one relic + one potion, pass the rest, then land in the card stage.
	# The arsenal deal is seeded per-session, so picks must come OFF THE TABLE
	# (a hardcoded id only matches the slate by luck). The first take's chip
	# flight to the pip rail is snapped mid-dive, and the detached chip's live
	# position is printed as the honest check (the pixels fade as it dives).
	_scene.call("_on_ars_pick", _ars_first_offer(), true)
	await get_tree().create_timer(0.26).timeout
	var lay: CanvasLayer = _scene.get("_ars_layer")
	var fly_seen := false
	if lay != null:
		for c in lay.get_children():
			if c is Control and (c as Control).top_level:
				fly_seen = true
				print("FLYCHIP pos=", (c as Control).global_position,
					" alpha=", snappedf(c.modulate.a, 0.01))
	if not fly_seen:
		print("FLYCHIP MISSING — pick flight never took off")
	await _snap("arsenal_fly")
	await get_tree().create_timer(0.2).timeout
	_scene.call("_on_ars_pick", "", true)
	_scene.call("_on_ars_pick", "", true)
	_scene.call("_on_ars_pick", _ars_first_offer(), false)
	# The second potion is a real take too — the FINAL take holds the overlay
	# open for its flight (_ars_close_after_flight); prove that path closes.
	_scene.call("_on_ars_pick", _ars_first_offer(), false)
	await get_tree().create_timer(1.0).timeout
	for id in ["spark", "pikeman", "pikeman", "harpy", "bloodsworn"]:
		_scene.call("_on_pick", id)
	await get_tree().create_timer(1.2).timeout
	await _snap("draft")
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── Quick battle (vs bot) ──
	NetMatch.start_vs_bot(SkirmishState.MatchMode.QUICK, 1)
	_scene = load("res://scenes/net_quick.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.0).timeout
	_scene.call("_end_arsenal")
	await get_tree().create_timer(1.6).timeout
	await _snap("quick")
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── Constructed (vs bot) ──
	NetMatch.start_vs_bot(SkirmishState.MatchMode.CONSTRUCTED, 1)
	_scene = load("res://scenes/net_constructed.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.0).timeout
	_scene.call("_end_arsenal")
	# Put a few cards in the deck so both columns render.
	for id in ["spark", "spark", "pikeman", "harpy"]:
		_scene.call("_on_add", id)
	await get_tree().create_timer(2.2).timeout
	await _snap("constructed")
	_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── Sealed (vs bot) ──
	NetMatch.start_vs_bot(SkirmishState.MatchMode.SEALED, 1)
	_scene = load("res://scenes/net_sealed.tscn").instantiate()
	get_tree().root.add_child(_scene)
	await get_tree().create_timer(1.0).timeout
	_scene.call("_end_arsenal")
	await get_tree().create_timer(2.2).timeout
	await _snap("sealed")
	_scene.queue_free()
	await get_tree().process_frame

	print("NET_MENUS_DONE")
	get_tree().quit()


## First live offering on the arsenal table (skips tiles queued for deletion).
func _ars_first_offer() -> String:
	var row: HBoxContainer = _scene.get("_ars_row")
	if row == null:
		return ""
	for c in row.get_children():
		if not c.is_queued_for_deletion() and c.has_meta("ars_id"):
			return String(c.get_meta("ars_id"))
	return ""


func _snap(state: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_net_%s.png" % state)
	print("SAVED ", state, " ", img.get_size())
