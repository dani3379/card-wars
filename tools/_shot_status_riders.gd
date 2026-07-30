extends Node
## _shot_status_riders.gd — eyes on the ROUND-SCOPED RIDERS (2026-07-28).
## Windowed, editor closed:
##   Godot.exe --path "D:\Godot" res://tools/_shot_status_riders.tscn
##
## The headless probe proves each rider produces a rail entry with a real
## texture. It CANNOT prove the result is legible: four orbs on a 104×136 token
## can collide with the stat seals, overflow the rail cap, or land as four
## identical smudges. This shoots the real board so those are visible.
##
##   riders   one player body per rider, statuses raised, rail rendered
##   callout  War Cry cast for real — the whole line flashes SWIFT at once
##
## Outputs tools/screenshot/_riders_*.png

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
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat
	await get_tree().create_timer(6.0).timeout

	# Four player bodies, one rider each, left to right. Front row so nothing
	# occludes the rail's top-right corner.
	for lane in range(4):
		_combat.call("summon_token", 3, 5, lane, false, 0, {}, "Pikeman")
	await get_tree().create_timer(0.5).timeout

	var mine: Array = _combat.call("_all_player_creatures")
	print("player tokens on board: ", mine.size())
	# Stand them up first: an unformed body wears the muster mark, which would
	# take a rail seat and confuse what is being looked at here.
	for c in mine:
		c.state.ready_to_swing = true
	if mine.size() >= 1:
		mine[0].state.war_cry_swift = true
	if mine.size() >= 2:
		mine[1].state.charges_this_turn = true
	if mine.size() >= 3:
		mine[2].state.battle_order_second_strike = true
		mine[2].state.redirecting = true          # two riders side by side
	if mine.size() >= 4:
		mine[3].state.hp_floor = true
		mine[3].state.effect_immune = true
		mine[3].state.challenge_any_lane = true   # three, to test the rail cap
	# No update_stat_display on purpose — the _process signature poll must catch
	# these, exactly as a mid-fight grant from a resolver would arrive.
	await get_tree().create_timer(0.8).timeout
	for c in mine:
		print("  lane %d rail orbs: %d  sig: %s" % [int(c.current_lane),
			(c.get("_status_orbs") as Array).size(), String(c.call("_status_signature"))])
	await _shoot("riders")

	# The moment of change. Cast War Cry for real so the callout funnel, the log
	# line and the rail orb all fire from the same beat on live bodies.
	for c in mine:
		c.state.war_cry_swift = false
	await _combat.call("_resolve_custom_spell", "war_cry", null, -1,
		CardDB.get_card_data("war_cry"), 0, null)
	await get_tree().create_timer(0.35).timeout
	print("active callouts: ", (_combat.get("_active_callouts") as Array).size())
	await _shoot("callout")

	print("RIDER_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_riders_%s.png" % tag)
	print("SAVED riders_", tag, " ", img.get_size())
