extends Node
## _probe_lane_focus.gd — is the clash lane spotlight actually ON SCREEN?
##
##   Godot_v4.6.2-stable_win64_console.exe --path "D:\Godot" \
##       res://tools/_probe_lane_focus.tscn
##
## WHY THIS EXISTS. `tools/_shot_clash_read.gd` traced a live clash and found
## `ClashLaneFocus._strength == 1.00` with a valid one-column `_focus_rect` for
## the whole front-rank pass — and then measured the rendered frames and found
## the board plate outside that column changed luminance by 0.0-3%. The 2026-07-28
## legibility pass raised that ink from 0.30 to 0.46 alpha, which should darken
## an unfocused patch by ~45%.
##
## A number that a node reports and a number that reaches the framebuffer are
## different claims, so this measures BOTH: the node's own geometry, and real
## pixels sampled from the viewport with the focus off and then on.
##
## Note ClashLaneFocus._draw() clamps its slabs against `size`, so a control with
## size == (0, 0) computes x1 <= x0 and RETURNS — drawing nothing while still
## reporting a full-strength focus. That is the specific failure this checks for.

const STATE_TIMEOUT := 60.0
const POLL := 0.2
const SHOT_DIR := "res://tools/screenshot/clash_read"

var _combat: Node = null
var _fail := 0


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func():
		print("[lf] WATCHDOG"); get_tree().quit(1))
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	UserSettings.end_turn_warning = false
	if UserSettings.has_method("mark_combat_model_tutorial_seen"):
		UserSettings.mark_combat_model_tutorial_seen()

	RunState.start_new_run("stalwart")
	RunState.current_act_idx = 1
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "oathbroken_knights"
	await get_tree().process_frame
	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	_combat.set_process_input(false)
	Input.warp_mouse(Vector2(4, 4))
	await get_tree().process_frame
	get_viewport().gui_disable_input = true

	if not await _await_round(1):
		return
	# A board with bodies on it, so the sample patches sit on real content.
	for lane in range(4):
		_combat.call("summon_token", 2, 5, lane, false, 0, {}, "Pikeman", [])
	_combat.call("_on_end_turn")
	if not await _await_round(2):
		return
	await get_tree().create_timer(2.2).timeout

	var f = _combat.get("_clash_lane_focus")
	if f == null or not is_instance_valid(f):
		print("[lf] FAIL — there is no _clash_lane_focus node at all")
		get_tree().quit(1)
		return
	var parent: Control = f.get_parent()
	print("[lf] node          : %s  (%s)" % [f.name, f.get_class()])
	print("[lf] visible=%s  modulate=%s  z_index=%d" % [
		str(f.visible), str(f.modulate), int(f.z_index)])
	print("[lf] size          : %s" % str(f.size))
	print("[lf] global_rect   : %s" % str(f.get_global_rect()))
	print("[lf] anchors       : L=%.2f T=%.2f R=%.2f B=%.2f" % [
		f.anchor_left, f.anchor_top, f.anchor_right, f.anchor_bottom])
	print("[lf] offsets       : L=%.1f T=%.1f R=%.1f B=%.1f" % [
		f.offset_left, f.offset_top, f.offset_right, f.offset_bottom])
	print("[lf] parent        : %s (%s) size=%s rect=%s" % [
		parent.name, parent.get_class(), str(parent.size),
		str(parent.get_global_rect())])

	# THE DECISIVE CHECK. _draw clamps every slab against `size`; at size 0 the
	# clamp collapses the rect and the function returns having drawn nothing,
	# while _strength happily reads 1.0 to any probe that asks.
	var zero_sized: bool = f.size.x <= 1.0 or f.size.y <= 1.0
	print("[lf] %s  the spotlight control has a real rect to draw into" % (
		"FAIL " if zero_sized else "pass "))
	if zero_sized:
		_fail += 1

	# ── pixels: focus OFF, then focus ON lane 1 ──────────────────────────────
	f.call("clear_focus")
	await get_tree().create_timer(0.4).timeout
	var before := await _shoot_and_sample("lanefocus_off")
	_combat.call("_focus_combat_lane", 1, false)
	await get_tree().create_timer(0.4).timeout
	print("[lf] after _focus_combat_lane(1): _strength=%.2f  _focus_rect=%s" % [
		float(f.get("_strength")), str(f.get("_focus_rect"))])
	var after := await _shoot_and_sample("lanefocus_on")

	print("[lf] band                 |   off |    on | ratio")
	var worst := 1.0
	for k in before.keys():
		var r: float = float(after[k]) / maxf(float(before[k]), 0.01)
		print("[lf] %-20s | %5.1f | %5.1f | %.3f" % [k, before[k], after[k], r])
		if not String(k).begins_with("lane1"):
			worst = minf(worst, r)
	# 0.46 ink over the plate should land the unfocused columns near 0.55.
	print("[lf] darkest unfocused ratio: %.3f (expect <= 0.75 for a 0.46 alpha ink)" % worst)
	if worst > 0.90:
		print("[lf] FAIL  the surround ink does not reach the framebuffer at all")
		_fail += 1
	elif worst > 0.75:
		print("[lf] FAIL  the surround ink is far weaker on screen than 0.46 alpha implies")
		_fail += 1
	else:
		print("[lf] pass  the surround ink measurably darkens the unfocused board")

	print("[lf] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


func _shoot_and_sample(tag: String) -> Dictionary:
	Input.warp_mouse(Vector2(4, 4))
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("%s/_%s.png" % [SHOT_DIR, tag])
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var ratio: float = float(img.get_width()) / maxf(vis.x, 1.0)
	var out := {}
	# Lane centres + row bands in CANVAS coords, scaled by the DPI ratio.
	var lane_x := [398.0, 666.0, 933.0, 1200.0]
	var bands := {"enemyfront": [250.0, 390.0], "youfront": [425.0, 575.0]}
	for i in range(4):
		for bk in bands.keys():
			var b: Array = bands[bk]
			var box := Rect2(Vector2(lane_x[i] - 70.0, b[0]),
				Vector2(140.0, b[1] - b[0]))
			out["lane%d_%s" % [i, bk]] = _lum(img, box, ratio)
	return out


func _lum(img: Image, rect: Rect2, ratio: float) -> float:
	var x0 := clampi(int(rect.position.x * ratio), 0, img.get_width() - 1)
	var y0 := clampi(int(rect.position.y * ratio), 0, img.get_height() - 1)
	var x1 := clampi(int(rect.end.x * ratio), x0 + 1, img.get_width())
	var y1 := clampi(int(rect.end.y * ratio), y0 + 1, img.get_height())
	var s := 0.0
	var n := 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			s += img.get_pixel(x, y).get_luminance()
			n += 1
	return (s / maxi(n, 1)) * 255.0


func _await_round(n: int) -> bool:
	var waited := 0.0
	while waited < STATE_TIMEOUT:
		if int(_combat.get("round_number")) >= n \
				and _combat.get("phase") == _combat.Phase.PLAYER_TURN:
			return true
		await get_tree().create_timer(POLL).timeout
		waited += POLL
	print("[lf] ABORT — timed out waiting for round ", n)
	get_tree().quit(1)
	return false
