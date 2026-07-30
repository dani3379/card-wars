extends Node
## _shot_emotes.gd — renders the emote system to PNG (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_emotes.tscn
## Shots (tools/screenshot/_emotes_*.png):
##   orb    round 1 as dealt — the speech orb by the player portrait, at rest
##   menu   the emote menu open (six canned lines stacked above the orb)
##   player a player emote bubble floating over the bottom-left portrait
##   both   player bubble + a foe bubble over the top-right enemy plate

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
	# Wait out the fight intro + round-1 turn banner before shooting.
	await get_tree().create_timer(6.0).timeout
	await _shoot("orb")

	# Open the emote menu.
	_combat.call("_open_emote_menu")
	await get_tree().create_timer(0.5).timeout
	await _shoot("menu")
	_combat.call("_close_emote_menu")
	await get_tree().create_timer(0.2).timeout

	# Player bubble (bottom-left portrait).
	_combat.call("_show_emote_bubble", false, "You will burn.")
	await get_tree().create_timer(0.45).timeout
	await _shoot("player")

	# Foe bubble too (top-right enemy plate) — both speakers at once.
	_combat.call("_show_emote_bubble", true, "Kneel.")
	await get_tree().create_timer(0.45).timeout
	await _shoot("both")

	print("EMOTE_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_emotes_%s.png" % tag)
	print("SAVED emotes_", tag, " ", img.get_size())
