extends Node3D
## PlayArea_patches.gd — NOT a complete file. This shows the surgical
## additions/replacements to make in your existing scripts/PlayArea.gd to
## wire MoodDirector into game flow and add screen shake / flash / freeze.
##
## Read top to bottom, find the matching section in your real PlayArea.gd,
## and apply the changes. Each change is isolated with a clear marker.


# ============================================================
# CHANGE 1 — At the top of the script with the other onreadys,
# add a reference to MoodDirector. Place a MoodDirector node as a
# child of PlayArea in play_area.tscn and name it "MoodDirector".
# ============================================================
@onready var mood_director: Node = $MoodDirector


# ============================================================
# CHANGE 2 — New member variables for game-feel hooks.
# Add anywhere in the variable section (e.g. after _field_props).
# ============================================================
var _shake_amount: float = 0.0
var _shake_decay: float = 7.0
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect


# ============================================================
# CHANGE 3 — In _ready(), call _build_flash_layer() before _start_player_turn().
# Also call _update_mood_target() once at the end of setup.
# ============================================================
func _ready() -> void:
	get_viewport().physics_object_picking = true
	_sun_seed = randf() * 100.0
	_build_hud_3d()
	_build_end_turn_button()
	_build_flash_layer()                    # NEW
	_build_field_decorations()
	_init_decks()
	_start_player_turn()
	_update_camera_transform()
	_update_mood_target()                   # NEW


# ============================================================
# CHANGE 4 — Three new helper methods. Add them anywhere in the script.
# ============================================================
func _build_flash_layer() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 5
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_layer.add_child(_flash_rect)


func screen_shake(amount: float) -> void:
	_shake_amount = max(_shake_amount, amount)


func screen_flash(color: Color, duration: float) -> void:
	_flash_rect.color = color
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color",
		Color(color.r, color.g, color.b, 0.0), duration)


func freeze_frame(duration: float) -> void:
	Engine.time_scale = 0.0
	# 4th arg ignore_time_scale=true — without it the timer stalls forever
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _update_mood_target() -> void:
	if mood_director:
		var t = mood_director.compute_target(
			turn_number, player_hp, enemy_hp, player_max_hp)
		mood_director.set_target_mood(t)


# ============================================================
# CHANGE 5 — REPLACE _smooth_camera. The only addition is the
# shake jitter applied AFTER _update_camera_transform sets position.
# ============================================================
func _smooth_camera(delta: float) -> void:
	var t = clampf(delta * CAM_SMOOTH_SPEED, 0, 1)
	_cam_angle_x = lerp(_cam_angle_x, _cam_target_angle_x, t)
	_cam_angle_y = lerp(_cam_angle_y, _cam_target_angle_y, t)
	_cam_distance = lerp(_cam_distance, _cam_target_distance, t)
	_update_camera_transform()
	# NEW: shake jitter on top of the smoothed transform
	if _shake_amount > 0.001:
		var jitter = Vector3(
			randf() - 0.5, randf() - 0.5, randf() - 0.5
		) * _shake_amount * 0.06
		camera.position += jitter
		_shake_amount = lerp(_shake_amount, 0.0,
			clampf(delta * _shake_decay, 0, 1))


# ============================================================
# CHANGE 6 — REPLACE _do_combat. Adds shake on every hit, a screen
# flash + bigger shake when YOU take damage, freeze-frame on impact,
# stress bump to the mood director, and a mood target update.
# ============================================================
func _do_combat() -> void:
	phase = Phase.COMBAT
	_update_hud()

	var any_kill := false
	var hero_damage_to_player := 0
	var hero_damage_to_enemy := 0

	for lane_idx in range(4):
		var p = _player_field[lane_idx]
		var e = _enemy_field[lane_idx]
		if p != null and e != null:
			e.take_damage(p.card_data.atk)
			p.take_damage(e.card_data.atk)
			screen_shake(0.3)
			if e.current_hp <= 0:
				_enemy_field[lane_idx] = null
				any_kill = true
			if p.current_hp <= 0:
				_player_field[lane_idx] = null
				any_kill = true
		elif p != null:
			enemy_hp -= p.card_data.atk
			hero_damage_to_enemy += p.card_data.atk
			screen_shake(0.5)
		elif e != null:
			player_hp -= e.card_data.atk
			hero_damage_to_player += e.card_data.atk
			screen_shake(0.8)
			screen_flash(Color(0.7, 0.05, 0.05, 0.45), 0.35)

	# Punctuate impact with a brief freeze-frame on big events
	if any_kill or hero_damage_to_player > 0:
		await freeze_frame(0.06)

	# Hero damage permanently nudges the world toward burning
	if mood_director:
		if hero_damage_to_player > 0:
			mood_director.add_stress(0.18)
		if hero_damage_to_enemy > 0:
			mood_director.add_stress(0.10)

	_update_hud()
	_update_mood_target()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		get_tree().create_timer(0.5).timeout.connect(_start_player_turn)


# ============================================================
# CHANGE 7 — At the END of _start_player_turn (after _update_hud),
# add one line:
# ============================================================
#	_update_mood_target()


# ============================================================
# CHANGE 8 — REPLACE _animate_props. Same flame flicker as before,
# but now the brazier OmniLights ramp from soft (mood=0) to roaring
# (mood=1), and the flame meshes scale up too.
# ============================================================
func _animate_props() -> void:
	var time = Time.get_ticks_msec() * 0.001
	var m: float = mood_director.mood if mood_director else 0.0
	var size_boost = lerpf(0.7, 1.4, m)
	var energy_base = lerpf(0.25, 1.8, m)
	var range_base = lerpf(1.2, 3.2, m)

	for flame in _field_props:
		if not flame.has_meta("base_y"):
			continue
		var base_y: float = flame.get_meta("base_y")
		var s: float = flame.get_meta("seed")
		flame.position.y = base_y + sin(time * 3.0 + s) * 0.012
		var flicker = 1.0 + sin(time * 7.0 + s * 2.0) * 0.1
		var v_flicker = 1.0 + sin(time * 5.0 + s) * 0.15
		flame.scale = Vector3(
			flicker * size_boost,
			v_flicker * size_boost,
			flicker * size_boost
		)
		# Ramp the sibling OmniLight inside the same pillar
		var pillar = flame.get_parent()
		for child in pillar.get_children():
			if child is OmniLight3D:
				child.light_energy = energy_base * (1.0 + sin(time * 6.0 + s) * 0.1)
				child.omni_range = range_base


# ============================================================
# OPTIONAL — _make_pillar. Tint the flame mesh albedo with mood too,
# so flames go from yellow-orange to deep red. Replace the `fmat`
# block. Or leave as-is; the rim and glow do most of the work.
# ============================================================
#	var fmat = StandardMaterial3D.new()
#	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
#	fmat.albedo_color = Color(1.0, 0.6, 0.1)
#	fmat.emission_enabled = true
#	fmat.emission = Color(1.0, 0.5, 0.15)
#	fmat.emission_energy_multiplier = 2.5
#	fm.material = fmat
