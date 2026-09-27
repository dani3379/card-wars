extends Node
## _shot_setpiece.gd — renders the SET-PIECE presentation to PNG for visual
## audit (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_setpiece.tscn
##
## The house rule is that UI bugs are verified by rendering the real node and
## looking at pixels ([[verify-ui-visually]]) — a set-piece ships THREE new
## pieces of presentation and none of them can be trusted from source alone:
##   despatch_<id>  the read-and-dismiss scenario brief (title / ground / order
##                  / stakes), caught while it is still on screen
##   board_<id>     the authored opening board + the standing-order plaque, and
##                  for The Sunken Road the ClosedGround exclusion hatch on
##                  lanes 0 and 3 (does the trench read as shut ground, or as
##                  a dark sticker on the table?)
##   clock_<id>     the same board after two rounds, so the live clock on the
##                  plaque can be checked against the round it claims
##
## Outputs tools/screenshot/_setpiece_*.png

const SHOOT_IDS := ["the_sunken_road", "the_pay_column", "the_standard_of_the_fourth"]

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

	for sp_id in SHOOT_IDS:
		await _shoot_scenario(sp_id)

	print("SETPIECE_SHOTS_DONE")
	get_tree().quit()


func _shoot_scenario(sp_id: String) -> void:
	var sp: Dictionary = SetPieceDB.get_set_piece(sp_id)
	RunState.start_new_run("raider")
	# A deep pool so the board survives long enough to shoot the clock.
	RunState.hero_max_hp = 200
	RunState.hero_hp = 200
	RunState.current_setpiece_id = sp_id
	RunState.current_encounter_id = ""
	RunState.current_node_type = "combat"
	RunState.current_mutator_id = ""
	RunState.current_act_idx = clampi(int(sp.get("act", 1)) - 1, 0, 2)
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = _combat

	# The despatch waits on a button press, so it is still up after the boot
	# settles — that is exactly the frame worth looking at.
	await get_tree().create_timer(4.0).timeout
	await _shoot("despatch_%s" % sp_id)

	# Dismiss it the way a player would: press the button the brief is awaiting.
	_press_take_the_field()
	await get_tree().create_timer(2.5).timeout
	await _shoot("board_%s" % sp_id)

	# Two rounds on, so the plaque's clock has visibly moved.
	for _i in 2:
		if is_instance_valid(_combat) and _combat.phase == _combat.Phase.PLAYER_TURN:
			_combat._end_turn_confirmed = true
			_combat._on_end_turn()
		await get_tree().create_timer(4.0).timeout
	await _shoot("clock_%s" % sp_id)

	if is_instance_valid(_combat):
		_combat.queue_free()
	_combat = null
	await get_tree().create_timer(0.4).timeout


## Find and press the despatch's start button. Walks the HUD layer rather than
## caching a reference, so this harness never needs the brief to expose one just
## for testing. Matches the NODE NAME, not the label: this used to hunt for text
## beginning "TAKE", the copy became "START THE FIGHT", and the harness then
## pressed nothing at all while still reporting success.
func _press_take_the_field() -> void:
	var layer = _combat.get("_hud_layer")
	if layer == null or not is_instance_valid(layer):
		return
	var btn := _find_button(layer)
	if btn == null:
		push_warning("_shot_setpiece: despatch start button not found — "
			+ "did SetPieceStartBtn get renamed?")
		return
	btn.emit_signal("pressed")


func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and String(child.name) == "SetPieceStartBtn":
			return child
		var found := _find_button(child)
		if found != null:
			return found
	return null


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_setpiece_%s.png" % tag)
	print("SAVED setpiece_", tag, " ", img.get_size())
