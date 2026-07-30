extends Node
## _shot_combat_hud.gd — renders the combat screen to PNG for the HUD
## style-unification audit (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_combat_hud.tscn
## Reproduces the reported screen: borrowed_faces (lanternhall faction →
## wave chip + standing edict + relics + gold + potions). Shots:
##   r1        round 1 as dealt (RELICS/POTIONS strips at rest)
##   r1_relic  hovering a relic chip (pop + rich tooltip)
##   r1_potion hovering a potion slot (pop + rich tooltip)
##   r2        after ending the turn once (INCOMING chip has live intents)
## Outputs tools/screenshot/_combat_hud_*.png

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
	RunState.gold = 138
	RunState.add_relic("whetstone")
	RunState.add_relic("war_horn")
	RunState.add_relic("pen_nib")            # counter relic → live badge on chip
	RunState.add_relic("merchants_license")  # utility tier → green halo
	RunState.add_potion("healing")
	RunState.add_potion("bottled_fury")      # targeted → "pick a target" tip tag
	RunState.add_potion("insight_tonic")
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
	# Wait out the quick fight intro + round-1 turn banner before shooting.
	await get_tree().create_timer(6.0).timeout
	await _shoot("r1")

	# Simulated hovers: emit the chips' own mouse signals so the rich-hover
	# path (pop tween + tooltip spawn/position) runs exactly as in play.
	var relic_panel: GridContainer = _combat.get("_relic_panel")
	if relic_panel != null and relic_panel.get_child_count() >= 2:
		var chip := relic_panel.get_child(1) as Control
		chip.emit_signal("mouse_entered")
		await get_tree().create_timer(0.5).timeout
		await _shoot("r1_relic")
		chip.emit_signal("mouse_exited")
		await get_tree().create_timer(0.3).timeout

	var potion_bar: Control = _combat.get("_potion_bar_root")
	if potion_bar != null and potion_bar.get_child_count() >= 1:
		var slot := potion_bar.get_child(0) as Control
		slot.emit_signal("mouse_entered")
		await get_tree().create_timer(0.5).timeout
		await _shoot("r1_potion")
		slot.emit_signal("mouse_exited")
		await get_tree().create_timer(0.3).timeout

	# End the turn once → enemy places + intents arm → INCOMING chip lives.
	if _combat.has_method("_on_end_turn"):
		_combat.call("_on_end_turn")
	await get_tree().create_timer(7.0).timeout
	await _shoot("r2")

	print("COMBAT_HUD_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_combat_hud_%s.png" % tag)
	print("SAVED combat_hud_", tag, " ", img.get_size())
