extends Node
## _shot_vfx_host.gd — PROOF of the shot-harness blindness bug and its fix
## (2026-07-29). Windowed, editor closed:
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_shot_vfx_host.tscn
##
## THE BUG (documented in docs/COMBAT_LEGIBILITY_20260728.md §"Harness bug found
## in passing"): Card2D._combat_vfx_target() resolves its VFX host through
##
##     get_tree().current_scene.has_method("spawn_floating_number")
##
## Every shot harness in tools/ boots combat with `root.add_child(combat)`, which
## does NOT touch SceneTree.current_scene — that still points at the harness Node,
## which has no such method. So _combat_vfx_target() returns null and EVERY
## Card2D-originated presentation beat is silently dropped:
##
##     _spawn_damage_number()  -> no floating "-N"
##     _spawn_keyword_chip()   -> no ARMORED / SHIELD / LAST STAND chip
##                             -> and no log_status() chronicle row either
##     creature_hit_feedback() -> no magnitude screen shake
##
## Nothing errors. The frames just quietly lack the numbers, and every reference
## PNG shot by _shot_battle_log / _shot_creature_fx / the rest has been wrong.
##
## This harness runs the SAME staged blow twice — once with current_scene left
## stale (the historical harness shape), once with it assigned — and reports the
## count of live floating numbers on Combat's HUD layer for each. BEFORE must be
## 0 and AFTER must be > 0, or the fix has regressed.
##
## Floating numbers are Labels parented to Combat's _hud_layer at z_index 200
## (spawn_floating_number stamps that); every other Label parked there is HUD
## furniture, so the z-index is the honest discriminator. Same rule the
## _probe_clash_trace observer uses.
##
## Outputs tools/screenshot/_vfxhost_before.png and _vfxhost_after.png.

const ENC := "borrowed_faces"
const FLOAT_Z := 200

var _fail := 0


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		print("[vfxhost] WATCHDOG fired — never finished")
		get_tree().quit(1))

	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# This machine's saved settings have Reduce Motion ON; force the shipping feel
	# so the A/B measures the fix and not an accessibility fallback.
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.particles = true
	UserSettings.screen_shake = true

	var before := await _run_pass(false, "before")
	var after := await _run_pass(true, "after")

	print("")
	print("[vfxhost] ============ RESULT ============")
	print("[vfxhost]   current_scene STALE (historical harness) : %d floating number(s)" % before)
	print("[vfxhost]   current_scene = combat  (the fix)        : %d floating number(s)" % after)
	_check(before == 0,
		"the unfixed harness shape renders NO damage numbers (reproduces the bug)")
	_check(after > 0,
		"assigning get_tree().current_scene = combat makes damage numbers render")
	print("[vfxhost] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	print("[vfxhost] DONE")
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail += 1
	print("[vfxhost] %s  %s" % ["PASS" if ok else "FAIL", what])


## One full boot → staged blow → sample → screenshot → teardown.
## `fix` decides whether SceneTree.current_scene is pointed at Combat.
func _run_pass(fix: bool, tag: String) -> int:
	print("")
	print("[vfxhost] --- pass '%s' (current_scene %s) ---" % [
		tag, "= combat" if fix else "left pointing at the harness"])

	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = ENC
	await get_tree().process_frame

	var combat: Node = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(combat)
	if fix:
		get_tree().current_scene = combat

	if not await _wait_for_player_turn(combat, 60.0):
		print("[vfxhost] FAIL — pass '%s' never reached the player's turn" % tag)
		_fail += 1
		_teardown(combat)
		return -1

	# Stand one body and hit it. take_damage() is the exact call site that routes
	# through _combat_vfx_target(), and staging it directly keeps the measurement
	# free of clash timing (a real clash's numbers live 900 ms and the sample
	# would race them).
	combat.call("summon_token", 3, 9, 1, false, 0, {}, "Pikeman")
	await get_tree().process_frame
	var victim = combat.call("_row_array", false, 0)[1]
	if victim == null or not is_instance_valid(victim):
		print("[vfxhost] FAIL — pass '%s' could not muster a body to strike" % tag)
		_fail += 1
		_teardown(combat)
		return -1
	victim.call("take_damage", 4)
	# Two more staged blows on the enemy line so the frame is not a lone numeral.
	for e in combat.call("_all_enemy_creatures"):
		if e != null and is_instance_valid(e):
			e.call("take_damage", 3)
	await get_tree().create_timer(0.16).timeout

	var n := _count_floats(combat)
	print("[vfxhost] pass '%s': live floating numbers on the HUD layer = %d" % [tag, n])
	for txt in _float_texts(combat):
		print("[vfxhost]     float: \"%s\"" % txt)
	await _shoot(tag)
	_teardown(combat)
	await get_tree().create_timer(0.4).timeout
	return n


func _teardown(combat: Node) -> void:
	if combat != null and is_instance_valid(combat):
		# Removing the node also clears SceneTree.current_scene when it was the
		# current scene (SceneTree::node_removed), so the next pass starts clean.
		combat.get_parent().remove_child(combat)
		combat.queue_free()


func _wait_for_player_turn(combat: Node, limit: float) -> bool:
	var waited := 0.0
	while waited < limit:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if not is_instance_valid(combat):
			return false
		# HOUSE TRAP: phase == PLAYER_TURN is enum 0 — the default — so it reads
		# true before the fight has begun. Gate on round_number >= 1.
		if int(combat.round_number) >= 1 and int(combat.phase) == 0:
			return true
	return false


func _hud_floats(combat: Node) -> Array:
	var out: Array = []
	var hud = combat.get("_hud_layer")
	if hud == null or not is_instance_valid(hud):
		return out
	for ch in hud.get_children():
		if ch is Label and int(ch.z_index) == FLOAT_Z:
			out.append(ch)
	return out


func _count_floats(combat: Node) -> int:
	return _hud_floats(combat).size()


func _float_texts(combat: Node) -> Array:
	var out: Array = []
	for l in _hud_floats(combat):
		out.append(String(l.text))
	return out


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var p := "res://tools/screenshot/_vfxhost_%s.png" % tag
	img.save_png(p)
	print("[vfxhost] SAVED %s  %s" % [p.get_file(), str(img.get_size())])
