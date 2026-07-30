extends Node
## _shot_discard_mark.gd — renders the 2026-07-07 discard rework + draft relic
## slate to PNG (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_discard_mark.tscn
## Shots (tools/screenshot/_discard_*.png):
##   marked       two hand cards marked (ribbon + sink + dim)
##   cascade      mid-flight end-of-turn discard cascade
##   relic_slate  the skirmish draft's opening battle-relic stage

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

	RunState.start_new_run("raider")
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "bandit_camp"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	# Wait out the fight intro + round-1 deal before interacting.
	await get_tree().create_timer(6.0).timeout

	var hand: Array = _combat.get("_hand")
	if hand.size() >= 2:
		_combat.call("_on_card_dismiss_requested", hand[0])
		_combat.call("_on_card_dismiss_requested", hand[1])
	await get_tree().create_timer(0.6).timeout
	await _shoot("marked")

	if _combat.has_method("_on_end_turn"):
		_combat.call("_on_end_turn")
	await get_tree().create_timer(0.28).timeout
	await _shoot("cascade")
	await get_tree().create_timer(6.0).timeout
	_combat.queue_free()
	await get_tree().create_timer(0.5).timeout

	# The skirmish draft's battle-relic slate (practice-bot session, no socket).
	NetMatch.start_vs_bot(SkirmishState.MatchMode.DRAFT, 1)
	var draft = load("res://scenes/net_draft.tscn").instantiate()
	get_tree().root.add_child(draft)
	await get_tree().create_timer(1.2).timeout
	await _shoot("relic_slate")

	# Pick a relic → the battle-potion slate follows (relic + potion in the ledger).
	draft._on_relic_pick("deep_satchel")
	await get_tree().create_timer(0.9).timeout
	await _shoot("potion_slate")

	print("DISCARD_MARK_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_discard_%s.png" % tag)
	print("SAVED discard_", tag, " ", img.get_size())
