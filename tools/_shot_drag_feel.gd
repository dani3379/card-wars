extends Node
## _shot_drag_feel.gd — the drag's physical juice, photographed (2026-09-17).
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_drag_feel.tscn
##
## WINDOWED ONLY — it photographs pixels. Writes tools/screenshot/_dragfeel_*.png.
##
## It boots the REAL combat scene and drives a REAL hand card through Card2D's
## own drag entry points, which is not gold-plating: both effects under test are
## functions of the card's VIEWPORT POSITION (the lamp throw) and its VELOCITY
## (the shadow's follow-through, the smear train). A synthetic stage would have
## to restate both, and a harness that restates the thing it measures agrees
## with itself — the mistake this codebase has paid for repeatedly.
##
## Frames:
##   lamp_left / lamp_mid / lamp_right   one card held still at three board
##       positions. THE SHADOW MUST THROW DIFFERENTLY IN EACH. Held still on
##       purpose so the lag term is zero and the lamp is the only variable.
##   smear      mid fast drag — the multiples train
##   lag        fast drag — shadow separated from the card
##   rest       the same card back in the hand, not lifted (the negative frame)
##
## Every frame also writes a 3x NEAREST zoom on the card, because a 14px shadow
## offset against a 20px one is not decidable at 1600x900.

const OUT := "res://tools/screenshot/_dragfeel_%s.png"

var _combat: Node = null
var _card: Control = null
var _focus := Vector2.ZERO


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[dragfeel] WATCHDOG fired")
		get_tree().quit(1))
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	if UserSettings != null:
		UserSettings.reduce_motion = false
		UserSettings.anim_speed = 1.0

	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	# HOUSE TRAP (from _shot_verdict_fx): Card2D._combat_vfx_target() resolves
	# the VFX host through get_tree().current_scene, so add_child alone leaves
	# every effect pointing at this harness and silently no-oping.
	get_tree().current_scene = _combat
	await get_tree().create_timer(6.0).timeout

	var hand: Array = _combat.get("_hand")
	if hand == null or hand.is_empty():
		print("[dragfeel] FAIL: no hand to drag")
		get_tree().quit(1)
		return
	_card = hand[0]

	# ── The lamp. Held STILL at three positions; only the x changes. ────────
	for spec in [["lamp_left", 430.0], ["lamp_mid", 800.0], ["lamp_right", 1180.0]]:
		await _hold_at(Vector2(float(spec[1]), 430.0))
		await _shoot(String(spec[0]))
	_release()

	# ── The smear + the lag. One fast sweep, shot mid-travel. ───────────────
	await _drag_sweep(Vector2(380.0, 700.0), Vector2(1240.0, 360.0), 2400.0,
		0.62, "smear")
	_release()
	await _drag_sweep(Vector2(1240.0, 700.0), Vector2(420.0, 340.0), 2900.0,
		0.55, "lag")
	_release()

	# ── The negative frame: not lifted, so nothing should be doing anything.
	await get_tree().create_timer(0.6).timeout
	_focus = _card.global_position + _card.size * _card.scale * 0.5
	await _shoot("rest")

	print("DRAG_FEEL_SHOTS_DONE")
	get_tree().quit()


## Put the card in a held state at `centre` and let it settle so the velocity
## damps to zero — the lamp frames must not carry any follow-through.
func _hold_at(centre: Vector2) -> void:
	_card.call("_start_drag", centre)
	for _i in range(14):
		_card.call("_update_drag", centre)
		await get_tree().process_frame
	_focus = centre


func _release() -> void:
	# Straight back to the hand: `_end_drag` would try to PLAY the card from a
	# board-height release and take the scene with it.
	if _card != null and is_instance_valid(_card):
		_card.set("_is_being_dragged", false)
		_card.call("_disarm_lean")


## Drive a real drag from a to b at a true px/second rate against the wall
## clock, and shoot at `at` (0..1) of the way along.
func _drag_sweep(a: Vector2, b: Vector2, speed: float, at: float,
		tag: String) -> void:
	_card.call("_start_drag", a)
	var span: float = a.distance_to(b)
	var travelled := 0.0
	var last := Time.get_ticks_msec()
	var shot := false
	while travelled < span:
		var now := Time.get_ticks_msec()
		var dt: float = float(now - last) / 1000.0
		last = now
		travelled = minf(travelled + speed * dt, span)
		var p: Vector2 = a.lerp(b, travelled / maxf(span, 1.0))
		_card.call("_update_drag", p)
		await get_tree().process_frame
		if not shot and travelled / maxf(span, 1.0) >= at:
			shot = true
			_focus = p
			await _shoot(tag)


func _shoot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT % tag)
	var win := Vector2(620.0, 520.0)
	var r := Rect2(_focus - win * 0.5, win)
	var canvas := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	r = r.intersection(canvas)
	if r.size.x >= 8.0 and r.size.y >= 8.0:
		var crop: Image = img.get_region(Rect2i(r))
		crop.resize(crop.get_width() * 3, crop.get_height() * 3,
			Image.INTERPOLATE_NEAREST)
		crop.save_png(OUT % (tag + "_zoom"))
	# MEASURED, not eyeballed. A 14px shadow offset against a 20px one is not a
	# judgement a person can make from a screenshot, and the whole claim of the
	# lamp is that this number CHANGES with the card's position — so the number
	# is the oracle and the picture is the sanity check.
	var box = _card.get("_lift_shadow_box")
	var off := "none"
	if box != null:
		off = str((box as StyleBoxFlat).shadow_offset)
	var ghosts := 0
	var host := _card.get_parent()
	if host != null:
		for ch in host.get_children():
			if ch is Sprite2D:
				ghosts += 1
	var vel: Vector2 = _card.get("_motion_vel")
	print("[dragfeel] shot %-10s focus=%-22s shadow_offset=%-18s ghosts=%d  speed=%.0f"
		% [tag, str(_focus), off, ghosts, vel.length()])
