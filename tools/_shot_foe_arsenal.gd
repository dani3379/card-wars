extends Node
## _shot_foe_arsenal.gd — renders the skirmish FOE'S ARSENAL rail + its HS-style
## beats to PNGs for visual inspection:
##   Godot.exe --path "D:\Godot" res://tools/_shot_foe_arsenal.tscn
## Fakes a connected net host (no socket, same recipe as _shot_net_clash), gives
## BOTH slots a drafted battle relic + potion, then captures:
##   frame 00            — at rest: foe rail (relic + potion chips) under the foe seal
##   frames 01..14       — the foe-potion drink reveal (chip drain + center bloom)
##   frames 15..22       — the foe relic trigger pulse (HS trinket flash + name float)
##   frames 23..30       — our own relic chip pulse (left rail)
## Outputs tools/screenshot/_foearsenal_*.png

var _combat: Node = null
var _shot_i: int = 0


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
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	# Drafted battle picks: ours (left rail + belt) and the FOE's (new right rail).
	SS.slots[0].relics = ["lantern"]
	SS.slots[0].potions = ["healing"]
	SS.slots[1].relics = ["gravewardens_pact"]
	SS.slots[1].potions = ["inferno_vial"]
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

	await _shoot()   # frame 00: at rest — FOE'S ARSENAL rail under the foe seal

	# The foe drinks: rail chip drains, bottle blooms center with name plate.
	_combat._net_show_foe_potion_fx("inferno_vial")
	for _i in range(14):
		await get_tree().create_timer(0.13).timeout
		await _shoot()

	# The foe's relic triggers: HS trinket pulse + name float on the foe rail.
	_combat._pulse_relic_chip("gravewardens_pact", true)
	for _i in range(8):
		await get_tree().create_timer(0.08).timeout
		await _shoot()

	# Our own relic fires: pulse on the left relic grid.
	_combat._relic_fired("lantern")
	for _i in range(8):
		await get_tree().create_timer(0.08).timeout
		await _shoot()

	print("FOE_ARSENAL_SHOTS_DONE")
	get_tree().quit()


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_foearsenal_%02d.png" % _shot_i)
	_shot_i += 1
