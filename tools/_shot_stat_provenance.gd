extends Node
## _shot_stat_provenance.gd — verifies the hover stat-provenance caption
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_stat_provenance.tscn
##
## Fields tokens carrying each buff bucket (this-fight / adjacency-free timed /
## this-round / damaged HP), drives the caption both directly and through the
## real _process hover path (mouse warp), and prints the rendered text.
##
## Outputs tools/screenshot/_stat_prov_*.png

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
	# Wait out the fight intro + round-1 banner.
	await get_tree().create_timer(6.0).timeout

	# ── Field the test line ──
	_combat.call("summon_token", 3, 5, 0, false, 0, {}, "Pikeman")
	_combat.call("summon_token", 2, 4, 1, false, 0, {}, "Bowman")
	_combat.call("summon_token", 4, 6, 2, false, 0, {}, "Vanilla")
	await get_tree().process_frame
	var front: Array = _combat.call("_row_array", false, 0)
	var pike: Control = front[0]
	var bow: Control = front[1]
	var plain: Control = front[2]

	# Pikeman: every ATK bucket at once + damaged HP.
	pike.current_atk += 1                      # +1 this fight
	pike.persistent_atk_buff = 2               # +2 for 3 rounds (timed)
	pike.persistent_atk_buff_rounds = 3
	pike.temp_atk_buff = 1                     # +1 this round
	pike.current_hp -= 2                       # HP 3 of 5
	pike.update_stat_display()
	# Bowman: debuffed for the fight, full HP.
	bow.current_atk -= 1                       # -1 this fight
	bow.update_stat_display()
	await get_tree().process_frame

	# ── Direct formatter checks ──
	print("pike text: '", _combat.call("_stat_provenance_text", pike), "'")
	print("bow  text: '", _combat.call("_stat_provenance_text", bow), "'")
	print("plain text: '", _combat.call("_stat_provenance_text", plain), "'  (must be empty)")

	# ── Direct caption placement (buffed + vanilla → shown / hidden) ──
	_combat.call("_update_stat_provenance", pike)
	var lbl: Label = _combat.get("_telegraph_stat_line")
	print("pike caption visible: ", lbl.visible, "  at: ", lbl.position, "  text: '", lbl.text, "'")
	await _shoot("pike_direct")
	_combat.call("_update_stat_provenance", plain)
	print("vanilla caption visible: ", lbl.visible, "  (must be false)")

	# ── Real hover path: warp the mouse onto the Bowman and let _process drive ──
	var center: Vector2 = bow.global_position + bow.size * bow.scale * 0.5
	Input.warp_mouse(center)
	await get_tree().create_timer(0.5).timeout
	print("hover-path caption visible: ", lbl.visible, "  text: '", lbl.text, "'")
	await _shoot("bow_hover")

	print("STAT_PROV_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_stat_prov_%s.png" % tag)
	print("SAVED stat_prov_", tag, " ", img.get_size())
