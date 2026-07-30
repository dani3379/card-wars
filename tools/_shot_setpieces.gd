extends Node
## _shot_setpieces.gd — visual check for the 2026-07-11 set-piece animations
## (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_setpieces.tscn
## Drives and shoots each set-piece mid-flight:
##   treasure_burst   coin fountain + gold count-up (~0.35s after open)
##   map_reveal       frontier reveal rings blooming on the open chart
##   potion_drink     solo bottle beat mid-arc, then the splash
##   forge_strike     the Rest forge: white-hot flash + falling anvil sparks
## Outputs tools/screenshot/_setpiece_*.png


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# Force full motion for the shots regardless of this machine's saved
	# settings (direct var writes — no set_* call, so nothing saves to disk).
	UserSettings.reduce_motion = false
	UserSettings.particles = true
	UserSettings.anim_speed = 1.0

	RunState.start_new_run("raider", 0, 4242)
	RunState.gold = 120
	await get_tree().process_frame

	# ── 1 · Treasure: coin fountain + ticking gold line ──
	var tr = load("res://scenes/treasure.tscn").instantiate()
	get_tree().root.add_child(tr)
	await get_tree().create_timer(0.35).timeout
	print("gold label at 0.35s: '", _find_gold_label_text(tr), "'")
	await _shoot("treasure_burst")
	await get_tree().create_timer(0.9).timeout
	await _shoot("treasure_settled")
	tr.queue_free()
	await get_tree().process_frame

	# ── 2 · Map: frontier reveal (lead-in 0.55 + 0.14/site stagger) ──
	var mp = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(mp)
	# Let the open settle, then re-arm the reveal deterministically so the
	# shot catches the rings mid-bloom (the natural on-open call races the
	# plate bake, so its timing varies run to run).
	await get_tree().create_timer(1.6).timeout
	var ov = mp.get("_overlay")
	if ov != null:
		ov.call("play_frontier_reveal", 0.05)
	await get_tree().create_timer(0.30).timeout
	await _shoot("map_reveal")
	await get_tree().create_timer(1.2).timeout
	await _shoot("map_settled")
	mp.queue_free()
	await get_tree().process_frame

	# ── 3 · Combat: solo potion drink beat ──
	RunState.add_potion("healing")
	RunState.hero_hp = 18   # wounded, so the heal number shows
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	var cb = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(cb)
	# HOUSE TRAP: Card2D._combat_vfx_target() resolves the VFX host via
	# get_tree().current_scene.has_method("spawn_floating_number"). add_child()
	# alone leaves current_scene pointing at THIS harness, so every damage
	# number, keyword chip and log_status row silently no-ops.
	get_tree().current_scene = cb
	await get_tree().create_timer(6.0).timeout   # fight intro + round banner
	cb.call("_use_combat_potion", 0)
	await get_tree().create_timer(0.15).timeout
	await _shoot("potion_drink")
	await get_tree().create_timer(0.25).timeout
	await _shoot("potion_splash")
	cb.queue_free()
	await get_tree().process_frame

	# ── 4 · Rest: the forge strike (LAST — _do_upgrade exits to the map) ──
	RunState.current_node_type = "rest"
	var rs = load("res://scenes/rest.tscn").instantiate()
	get_tree().root.add_child(rs)
	await get_tree().create_timer(0.8).timeout
	rs.set("_selected_card_index", 0)
	rs.call("_show_confirm_upgrade", 0)
	await get_tree().create_timer(0.5).timeout
	var fp: Node = rs.find_child("ForgedPreview", true, false)
	print("reduce_motion: ", UserSettings.reduce_motion,
		"  ForgedPreview found: ", fp != null,
		"  rect: ", (fp as Control).get_global_rect() if fp is Control else "-")
	var cr: Node = null
	for ch in rs.get_children():
		if ch is HBoxContainer:
			cr = ch
	if cr != null:
		print("compare row rect: ", (cr as Control).get_global_rect(),
			"  children: ", cr.get_child_count())
		for ch in cr.get_children():
			if ch is Control:
				print("   child ", ch.name, " rect ", ch.get_global_rect())
	rs.call("_do_upgrade", "plus")   # fires forge_strike, then leaves for the map
	await get_tree().create_timer(0.08).timeout
	await _shoot("forge_flash")
	await get_tree().create_timer(0.28).timeout
	await _shoot("forge_sparks")

	print("SETPIECE_SHOTS_DONE")
	get_tree().quit()


func _find_gold_label_text(root: Node) -> String:
	for n in root.get_children():
		if n is Label and String((n as Label).text).contains("gold"):
			return (n as Label).text
		var deep := _find_gold_label_text(n)
		if deep != "":
			return deep
	return ""


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_setpiece_%s.png" % tag)
	print("SAVED setpiece_", tag, " ", img.get_size())
