extends Node
## _shot_field_proto.gd — renders the four field-ground prototype styles to PNG
## for rating (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_field_proto.tscn
## For each Combat.FieldStyle 0-3: instantiates combat on borrowed_faces and
## shoots the round-1 board ("empty") plus a populated both-sides board ("full")
## so every ground is judged under real card load.
## Outputs tools/screenshot/_field_proto_<style>_{empty,full}.png

const STYLE_NAMES := ["war_table", "meadow", "obsidian", "battle_plan"]


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# Untyped on purpose: static-var access through a loaded script object is
	# dynamic — a typed `Resource` var fails to parse on the property set.
	var combat_script = load("res://scripts/scenes/Combat.gd")
	for style in range(STYLE_NAMES.size()):
		RunState.start_new_run("raider")
		RunState.gold = 138
		RunState.add_potion("healing")
		RunState.current_node_type = "combat"
		RunState.current_encounter_id = "borrowed_faces"
		await get_tree().process_frame
		combat_script.field_style_override = style
		var combat: Node = load("res://scenes/combat.tscn").instantiate()
		get_tree().root.add_child(combat)
		# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
		# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
		# alone leaves current_scene pointing at THIS harness, so every damage
		# number, keyword chip and log_status row silently no-ops.
		get_tree().current_scene = combat
		# Wait out the fight intro + round-1 banner before shooting.
		await get_tree().create_timer(6.0).timeout
		await _shoot("%s_empty" % STYLE_NAMES[style])
		# Populate both sides so the ground is judged under real load.
		combat.summon_token(2, 3, 0, false, 0)
		combat.summon_token(1, 2, 1, false, 0)
		combat.summon_token(3, 2, 2, false, 1)
		combat.summon_token(2, 2, 3, false, 0)
		combat.summon_token(2, 4, 1, true, 1)
		combat.summon_token(1, 1, 3, true, 0)
		await get_tree().create_timer(1.2).timeout
		await _shoot("%s_full" % STYLE_NAMES[style])
		combat.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	combat_script.field_style_override = -1
	print("FIELD_PROTO_SHOTS_DONE")
	get_tree().quit()


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_field_proto_%s.png" % tag)
	print("SAVED field_proto_", tag, " ", img.get_size())
