extends Node
## _shot_initiative.gd — renders THE INITIATIVE modal to PNG (windowed, editor
## closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_initiative.tscn
##
## WHY: the modal shipped 2026-07-30 and has NEVER BEEN LOOKED AT. It is the only
## screen in the game that stops the player before they may touch a card, its two
## tiles carry the longest body copy of any modal in Combat.gd, and the house rule
## is that UI is judged from pixels, not from source (the run-opening pass found
## four defects that were invisible in the code and obvious in the render).
##
## What to check in the output:
##   * both tiles fully readable at 330x186 — the copy is ~2 lines longer than the
##     war-school tiles this scaffold was borrowed from, so overflow is the risk
##   * the two accents read as DIFFERENT choices (gilt = act, blue = wait)
##   * the title/subtitle do not collide with the tile row
##   * nothing is clipped off the 1600x900 canvas
##
## Outputs tools/screenshot/_initiative_*.png

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

	# A General, because that is one of the only two fight kinds that asks.
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "elite"
	RunState.current_encounter_id = _find_elite()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP (from _shot_combat_hud): Card2D._combat_vfx_target() resolves the
	# VFX host via get_tree().current_scene, so add_child alone leaves every
	# floating number and keyword chip silently no-oping.
	get_tree().current_scene = _combat
	await get_tree().create_timer(6.0).timeout

	# Build the overlay directly rather than going through _offer_initiative:
	# that function auto-picks headlessly and would return before anything is on
	# screen, and here we specifically want the un-clicked modal held still.
	_combat._initiative_overlay()
	await get_tree().create_timer(1.2).timeout
	await _shoot("modal")

	# A second frame after a settle, to catch anything that animates in late —
	# the screen-audit pass found tiles that only overflowed once their entrance
	# tween finished.
	await get_tree().create_timer(1.4).timeout
	await _shoot("modal_settled")

	get_tree().quit(0)


func _find_elite() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "elite":
			return String(id)
	return ""


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_initiative_%s.png" % tag)
	print("SAVED initiative_", tag, " ", img.get_size())
