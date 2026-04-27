extends Node3D
## PlayArea.gd — Label3D HUD (zero full-screen Control nodes), camera orbit, AI.
## Now wired into MoodDirector for atmosphere progression, plus screen shake,
## screen flash, and freeze-frame on combat events.

@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var mood_director: Node = $MoodDirector

const CARD_SCENE = preload("res://scenes/card.tscn")

# ── Card databases ──
var CARD_DB := {
	"scarecrow_lord": { "name": "Scarecrow Lord", "atk": 2, "hp": 3, "cost": 1, "desc": "A wicked sentinel" },
	"bone_queen":     { "name": "Bone Queen",     "atk": 2, "hp": 4, "cost": 2, "desc": "Risen from the crypt" },
	"iron_titan":     { "name": "Iron Titan",     "atk": 3, "hp": 5, "cost": 3, "desc": "Relentless war machine" },
	"blood_pharaoh":  { "name": "Blood Pharaoh",  "atk": 3, "hp": 5, "cost": 3, "desc": "Ancient and vampiric" },
	"void_king":      { "name": "Void King",      "atk": 4, "hp": 6, "cost": 4, "desc": "The final darkness" },
	"frost_monarch":  { "name": "Frost Monarch",  "atk": 4, "hp": 7, "cost": 5, "desc": "The long winter crowned" },
}
var ENEMY_DB := {
	"shadow_imp":     { "name": "Shadow Imp",     "atk": 3, "hp": 2, "cost": 1, "desc": "Swift and vicious" },
	"stone_golem":    { "name": "Stone Golem",    "atk": 2, "hp": 5, "cost": 2, "desc": "Unyielding" },
	"cursed_wraith":  { "name": "Cursed Wraith",  "atk": 4, "hp": 3, "cost": 3, "desc": "Feeds on fear" },
	"hellfire_drake": { "name": "Hellfire Drake",  "atk": 5, "hp": 4, "cost": 4, "desc": "Burns all" },
}

# ── Camera ──
var _cam_pivot := Vector3(0.0, 0.0, 0.3)
var _cam_distance := 4.2
var _cam_angle_x := -45.0
var _cam_angle_y := 0.0
var _cam_target_distance := 4.2
var _cam_target_angle_x := -45.0
var _cam_target_angle_y := 0.0
var _cam_orbiting := false
var _cam_panning := false
var _cam_last_mouse := Vector2.ZERO
const CAM_ZOOM_MIN := 2.0
const CAM_ZOOM_MAX := 7.0
const CAM_PITCH_MIN := -80.0
const CAM_PITCH_MAX := -20.0
const CAM_ORBIT_SENSITIVITY := 0.3
const CAM_ZOOM_STEP := 0.2
const CAM_SMOOTH_SPEED := 8.0

# ── Game state ──
enum Phase { PLAYER_TURN, ENEMY_TURN, COMBAT, GAME_OVER }
var phase := Phase.PLAYER_TURN
var turn_number := 0
var player_hp := 20
var player_max_hp := 20
var player_mana := 0
var player_max_mana := 0
var enemy_hp := 20
var enemy_max_hp := 20
var enemy_mana := 0

# ── Hand + battlefield ──
var _hand: Array[Node3D] = []
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]
const MAX_HAND_SIZE := 7
const HAND_CENTER := Vector3(0.0, 0.06, 2.2)
const HAND_CARD_SPACING := 0.46
const HAND_CARD_TILT_X := -0.35
const LANE_X := [-1.35, -0.45, 0.45, 1.35]
const PLAYER_ZONE_Z := 0.6
const ENEMY_ZONE_Z := -0.6

# ── Decks ──
var _player_deck: Array[String] = []
var _enemy_deck: Array[String] = []

# ── HUD (Label3D nodes) ──
var _hud_anchor: Node3D
var _hp_label: Label3D
var _enemy_hp_label: Label3D
var _mana_label: Label3D
var _turn_label: Label3D
var _phase_label: Label3D
var _info_label: Label3D

# ── End turn button (the ONLY Control node — tiny, not full-screen) ──
var _end_turn_btn: Button

# ── Sun ──
const SUN_BASE_ENERGY := 1.0
const SUN_BREATHE_AMOUNT := 0.06
var _sun_seed := 0.0

# ── Field props ──
var _field_props: Array[Node3D] = []

# ── Game-feel hooks (shake / flash / freeze) ──
var _shake_amount: float = 0.0
var _shake_decay: float = 7.0
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect

# ── Lane preview: lights up the lane under the card you're dragging ──
var _lane_meshes: Array = []
var _lane_base_colors: Array = []
var _lane_highlighted_idx: int = -1


func _ready() -> void:
	get_viewport().physics_object_picking = true
	print("PICKING NOW: ", get_viewport().physics_object_picking)
	_sun_seed = randf() * 100.0
	_build_hud_3d()
	_build_end_turn_button()
	_build_flash_layer()
	_cache_lane_meshes()
	_build_field_decorations()
	_init_decks()
	_start_player_turn()
	_update_camera_transform()
	_update_mood_target()


# Cache references to the four lane meshes so we can tint them while
# dragging without crawling the scene tree every frame.
func _cache_lane_meshes() -> void:
	var lanes_node = get_node_or_null("Lanes")
	if lanes_node == null:
		return
	for i in range(1, 5):
		var lane = lanes_node.get_node_or_null("Lane%d" % i) as MeshInstance3D
		if lane == null:
			continue
		_lane_meshes.append(lane)
		# Duplicate the material so per-lane tinting doesn't bleed across.
		var src = lane.get_active_material(0)
		if src:
			var unique = src.duplicate()
			lane.set_surface_override_material(0, unique)
			if unique is StandardMaterial3D:
				_lane_base_colors.append(unique.albedo_color)
			else:
				_lane_base_colors.append(Color.WHITE)
		else:
			_lane_base_colors.append(Color.WHITE)


func _init_decks() -> void:
	for id in CARD_DB.keys():
		for i in 3:
			_player_deck.append(id)
	_player_deck.shuffle()
	for id in ENEMY_DB.keys():
		for i in 3:
			_enemy_deck.append(id)
	_enemy_deck.shuffle()


func _start_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	turn_number += 1
	player_max_mana = mini(turn_number + 4, 10)
	player_mana = player_max_mana
	var draw_count = 4 if turn_number == 1 else 1
	for i in draw_count:
		if _hand.size() < MAX_HAND_SIZE and _player_deck.size() > 0:
			_draw_card(_player_deck.pop_front())
	_end_turn_btn.disabled = false
	_update_hud()
	_update_mood_target()


func _start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	enemy_mana = mini(turn_number + 4, 10)
	_end_turn_btn.disabled = true
	_update_hud()
	get_tree().create_timer(0.8).timeout.connect(_enemy_ai)


func _enemy_ai() -> void:
	if phase != Phase.ENEMY_TURN:
		return
	for lane_idx in range(4):
		if _enemy_field[lane_idx] != null:
			continue
		if _enemy_deck.size() == 0:
			break
		var card_id = _enemy_deck.pop_front()
		var data = ENEMY_DB[card_id]
		if data.cost <= enemy_mana:
			enemy_mana -= data.cost
			_place_lane_card(card_id, lane_idx, true)
	_update_hud()
	get_tree().create_timer(0.6).timeout.connect(_do_combat)


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

	if any_kill or hero_damage_to_player > 0:
		await freeze_frame(0.06)

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


func _check_game_over() -> void:
	if player_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "DEFEAT"
		_phase_label.modulate = Color(0.9, 0.2, 0.2)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "VICTORY!"
		_phase_label.modulate = Color(0.2, 0.9, 0.3)


func _place_lane_card(card_id: String, lane_idx: int, is_opponent: bool) -> void:
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.is_opponent = is_opponent
	card.is_on_battlefield = true
	var db = ENEMY_DB if is_opponent else CARD_DB
	card.card_data = db[card_id]
	add_child(card)
	if is_opponent:
		_enemy_field[lane_idx] = card
	else:
		_player_field[lane_idx] = card
	var z = ENEMY_ZONE_Z if is_opponent else PLAYER_ZONE_Z
	card.global_position = Vector3(LANE_X[lane_idx], 0.01, z)
	if is_opponent:
		card.rotation = Vector3(0, PI + (randf() - 0.5) * 0.08, 0)
	else:
		card.rotation = Vector3(0, (randf() - 0.5) * 0.08, 0)
	card.destroyed.connect(_on_card_destroyed.bind(card))


func _on_card_destroyed(card: Node3D) -> void:
	for i in range(4):
		if _player_field[i] == card:
			_player_field[i] = null
		if _enemy_field[i] == card:
			_enemy_field[i] = null


# ── Camera ──
func _process(delta: float) -> void:
	_smooth_camera(delta)
	_apply_sun_breathe()
	_animate_props()
	_animate_field_cards()
	_camera_idle_drift(delta)
	_update_lane_preview()


# Cards on the battlefield bob and pulse subtly even when nothing is
# happening. The whole point: when the player stops touching the mouse,
# the screen should not freeze. Different phase per lane so they don't
# move in lockstep — that would read as scripted, not alive.
func _animate_field_cards() -> void:
	var time = Time.get_ticks_msec() * 0.001
	for i in range(4):
		var p = _player_field[i]
		if p != null and not p._is_being_dragged and not p._is_playing:
			var s = float(i) * 1.3
			p.position.y = 0.01 + sin(time * 1.4 + s) * 0.005
		var e = _enemy_field[i]
		if e != null and not e._is_playing:
			var s = float(i) * 1.3 + 2.1
			e.position.y = 0.01 + sin(time * 1.4 + s) * 0.005


# Tiny camera drift — the scene is never perfectly still. About 1cm of
# oscillation, far below conscious perception, but the brain notices the
# absence of motion. With this on, the screen "breathes." Without it, the
# screen has the dead-still quality of a screensaver.
var _drift_t: float = 0.0
func _camera_idle_drift(delta: float) -> void:
	_drift_t += delta
	# Two sine layers at different frequencies so the path isn't periodic.
	# Amplitude 1.5–2cm — visible but well below "is the camera broken?"
	var off = Vector3(
		sin(_drift_t * 0.41) * 0.015 + sin(_drift_t * 0.13) * 0.008,
		sin(_drift_t * 0.27) * 0.006,
		sin(_drift_t * 0.33) * 0.015 + sin(_drift_t * 0.17) * 0.008
	)
	# Position is overwritten by _update_camera_transform each frame, so
	# we just add directly — accumulation isn't an issue.
	camera.position += off


# While a hand card is being dragged, find which lane it's hovering over
# and brighten that lane's albedo. When the drag ends or no card is held,
# reset all lanes to their base color.
func _update_lane_preview() -> void:
	var dragging_card: Node3D = null
	for c in _hand:
		if c.has_method("_kill_active_tween") and c.get("_is_being_dragged") == true:
			dragging_card = c
			break

	var target_idx := -1
	if dragging_card and dragging_card.global_position.z < 1.5:
		target_idx = _nearest_lane_index(dragging_card.global_position)
		# Only highlight if the lane is empty
		if _player_field[target_idx] != null:
			target_idx = -1

	if target_idx == _lane_highlighted_idx:
		return

	# Reset previous lane
	if _lane_highlighted_idx >= 0 and _lane_highlighted_idx < _lane_meshes.size():
		var prev = _lane_meshes[_lane_highlighted_idx]
		var prev_mat = prev.get_active_material(0)
		if prev_mat is StandardMaterial3D:
			prev_mat.albedo_color = _lane_base_colors[_lane_highlighted_idx]
			prev_mat.emission_enabled = false
	# Highlight new lane
	if target_idx >= 0 and target_idx < _lane_meshes.size():
		var cur = _lane_meshes[target_idx]
		var cur_mat = cur.get_active_material(0)
		if cur_mat is StandardMaterial3D:
			cur_mat.albedo_color = _lane_base_colors[target_idx].lightened(0.25)
			cur_mat.emission_enabled = true
			cur_mat.emission = _lane_base_colors[target_idx]
			cur_mat.emission_energy_multiplier = 0.4
	_lane_highlighted_idx = target_idx


func _smooth_camera(delta: float) -> void:
	var t = clampf(delta * CAM_SMOOTH_SPEED, 0, 1)
	_cam_angle_x = lerp(_cam_angle_x, _cam_target_angle_x, t)
	_cam_angle_y = lerp(_cam_angle_y, _cam_target_angle_y, t)
	_cam_distance = lerp(_cam_distance, _cam_target_distance, t)
	_update_camera_transform()
	if _shake_amount > 0.001:
		var jitter = Vector3(
			randf() - 0.5, randf() - 0.5, randf() - 0.5
		) * _shake_amount * 0.06
		camera.position += jitter
		_shake_amount = lerp(_shake_amount, 0.0,
			clampf(delta * _shake_decay, 0, 1))


func _update_camera_transform() -> void:
	var pitch_rad = deg_to_rad(_cam_angle_x)
	var yaw_rad = deg_to_rad(_cam_angle_y)
	var offset = Vector3(
		sin(yaw_rad) * cos(pitch_rad) * _cam_distance,
		-sin(pitch_rad) * _cam_distance,
		cos(yaw_rad) * cos(pitch_rad) * _cam_distance
	)
	camera.position = _cam_pivot + offset
	camera.look_at(_cam_pivot, Vector3.UP)


func _apply_sun_breathe() -> void:
	var time = Time.get_ticks_msec() * 0.001
	var pulse = (sin(time * 0.40 + _sun_seed) * 0.6 + sin(time * 0.13 + _sun_seed * 1.7) * 0.4) * 0.5
	sun.light_energy = SUN_BASE_ENERGY + pulse * SUN_BREATHE_AMOUNT


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cam_orbiting = event.pressed
			_cam_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_cam_panning = event.pressed
			_cam_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_target_distance = clampf(_cam_target_distance - CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_target_distance = clampf(_cam_target_distance + CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)

	if event is InputEventMouseMotion:
		if _cam_orbiting:
			var delta_mouse = event.position - _cam_last_mouse
			_cam_target_angle_y -= delta_mouse.x * CAM_ORBIT_SENSITIVITY
			_cam_target_angle_x -= delta_mouse.y * CAM_ORBIT_SENSITIVITY
			_cam_target_angle_x = clampf(_cam_target_angle_x, CAM_PITCH_MIN, CAM_PITCH_MAX)
			_cam_last_mouse = event.position
		elif _cam_panning:
			var delta_mouse = event.position - _cam_last_mouse
			_cam_pivot += camera.global_transform.basis * Vector3(-delta_mouse.x * 0.003, delta_mouse.y * 0.003, 0)
			_cam_pivot.x = clampf(_cam_pivot.x, -3.0, 3.0)
			_cam_pivot.z = clampf(_cam_pivot.z, -2.0, 3.0)
			_cam_last_mouse = event.position

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_HOME:
			_cam_target_angle_x = -45.0
			_cam_target_angle_y = 0.0
			_cam_target_distance = 4.2
			_cam_pivot = Vector3(0, 0, 0.3)
		elif event.keycode == KEY_E or event.keycode == KEY_ENTER:
			_on_end_turn()


# ── Hand management ──
func _draw_card(card_id: String) -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.card_data = CARD_DB[card_id]
	add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))
	_arrange_hand()


func _arrange_hand() -> void:
	var n = _hand.size()
	if n == 0:
		return
	var total_width = (n - 1) * HAND_CARD_SPACING
	var start_x = HAND_CENTER.x - total_width * 0.5
	for i in n:
		var card = _hand[i]
		var x = start_x + i * HAND_CARD_SPACING
		var arc_t = 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5) * 2.0
		var arc_y = -abs(arc_t) * 0.015
		var fan_angle = arc_t * 0.08
		card.set_hand_target(
			Vector3(x, HAND_CENTER.y + arc_y, HAND_CENTER.z),
			Vector3(HAND_CARD_TILT_X, fan_angle, 0)
		)


func _on_card_played(card: Node3D) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	var cost = card.card_data.cost
	if player_mana < cost:
		_show_info("Not enough mana!")
		return
	var lane_idx = _nearest_lane_index(card.global_position)
	if _player_field[lane_idx] != null:
		_show_info("Lane occupied!")
		return
	player_mana -= cost
	_hand.erase(card)
	_player_field[lane_idx] = card
	card.is_on_battlefield = true
	var play_pos = Vector3(LANE_X[lane_idx], 0.01, PLAYER_ZONE_Z)
	card.fly_to_play_area(play_pos)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	_arrange_hand()
	_update_hud()


func _show_info(msg: String) -> void:
	_info_label.text = msg
	_info_label.modulate = Color(1, 0.6, 0.3)
	get_tree().create_timer(1.5).timeout.connect(func(): _info_label.text = "")


func _nearest_lane_index(world_pos: Vector3) -> int:
	var best_idx := 0
	var best_dist := INF
	for i in range(4):
		var d = abs(world_pos.x - LANE_X[i])
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


# ── 3D HUD (Label3D — no Control nodes blocking input) ──
func _build_hud_3d() -> void:
	_phase_label = _make_hud_label(Vector3(0, 2.8, -1.8), "YOUR TURN", 48, Color(1, 0.9, 0.4))
	_enemy_hp_label = _make_hud_label(Vector3(0, 2.8, -2.2), "Enemy ♥ 20/20", 32, Color(0.9, 0.4, 0.4))
	_hp_label = _make_hud_label(Vector3(-1.2, 0.15, 2.8), "♥ 20/20", 40, Color(0.9, 0.3, 0.3))
	_mana_label = _make_hud_label(Vector3(0, 0.15, 2.8), "◆ 5/5", 40, Color(0.4, 0.65, 1.0))
	_turn_label = _make_hud_label(Vector3(1.2, 0.15, 2.8), "Turn 1", 32, Color(0.6, 0.6, 0.6))
	_info_label = _make_hud_label(Vector3(0, 1.5, 0), "", 48, Color(1, 0.6, 0.3))


func _make_hud_label(pos: Vector3, text: String, size: int, color: Color) -> Label3D:
	var lbl = Label3D.new()
	lbl.text = text
	lbl.font_size = size
	lbl.pixel_size = 0.003
	lbl.position = pos
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = color
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.outline_size = 8
	lbl.fixed_size = true
	lbl.render_priority = 10
	add_child(lbl)
	return lbl


# ── End Turn button — the ONLY Control node, added directly, no full-rect parent ──
func _build_end_turn_button() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_end_turn_btn = Button.new()
	_end_turn_btn.text = "END TURN  [E]"
	_end_turn_btn.position = Vector2(20, 20)
	_end_turn_btn.custom_minimum_size = Vector2(130, 36)
	_end_turn_btn.pressed.connect(_on_end_turn)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.42, 0.18, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_end_turn_btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = Color(0.18, 0.55, 0.22, 0.95)
	_end_turn_btn.add_theme_stylebox_override("hover", hover)
	_end_turn_btn.add_theme_font_size_override("font_size", 13)
	_end_turn_btn.add_theme_color_override("font_color", Color.WHITE)

	layer.add_child(_end_turn_btn)


func _update_hud() -> void:
	_hp_label.text = "♥ %d/%d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "Enemy ♥ %d/%d" % [enemy_hp, enemy_max_hp]
	_mana_label.text = "◆ %d/%d" % [player_mana, player_max_mana]
	_turn_label.text = "Turn %d" % turn_number

	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "YOUR TURN"
			_phase_label.modulate = Color(1, 0.9, 0.4)
		Phase.ENEMY_TURN:
			_phase_label.text = "ENEMY TURN"
			_phase_label.modulate = Color(0.9, 0.4, 0.4)
		Phase.COMBAT:
			_phase_label.text = "COMBAT"
			_phase_label.modulate = Color(1, 0.5, 0.2)
		Phase.GAME_OVER:
			pass


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	_start_enemy_turn()


# ── Game-feel hooks ──
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


# ── Field decorations ──
func _build_field_decorations() -> void:
	var pillars = [Vector3(-2.15,0,-1.65), Vector3(2.15,0,-1.65), Vector3(-2.15,0,1.65), Vector3(2.15,0,1.65)]
	for pos in pillars:
		_make_pillar(pos)
	_make_rock(Vector3(-2.6, 0, 0.3), 0.12, Color(0.38, 0.35, 0.32))
	_make_rock(Vector3(2.5, 0, 0.1), 0.10, Color(0.35, 0.33, 0.30))
	_make_rock(Vector3(-0.3, 0, -2.0), 0.09, Color(0.37, 0.34, 0.31))
	_make_crystal(Vector3(-2.3, 0, 0.9), 0.06, Color(0.3, 0.7, 0.9))
	_make_crystal(Vector3(2.4, 0, -1.0), 0.05, Color(0.8, 0.3, 0.6))
	_make_mushroom(Vector3(-2.5, 0, -1.2), Color(0.85, 0.25, 0.2))
	_make_mushroom(Vector3(2.6, 0, 0.8), Color(0.3, 0.6, 0.85))
	_make_deck_pile(Vector3(2.5, 0, 2.0), Color(0.25, 0.35, 0.55), "Player\nDeck")
	_make_deck_pile(Vector3(2.5, 0, -1.4), Color(0.55, 0.2, 0.2), "Enemy\nDeck")


func _make_pillar(pos: Vector3) -> void:
	var pillar = Node3D.new()
	pillar.position = pos
	add_child(pillar)
	var base_mesh = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(0.18, 0.35, 0.18)
	var bmat = StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	bmat.albedo_color = Color(0.45, 0.38, 0.30)
	bm.material = bmat
	base_mesh.mesh = bm
	base_mesh.position = Vector3(0, 0.175, 0)
	pillar.add_child(base_mesh)
	var cap_mesh = MeshInstance3D.new()
	var cm = BoxMesh.new()
	cm.size = Vector3(0.22, 0.04, 0.22)
	var cmat = StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	cmat.albedo_color = Color(0.55, 0.45, 0.32)
	cm.material = cmat
	cap_mesh.mesh = cm
	cap_mesh.position = Vector3(0, 0.37, 0)
	pillar.add_child(cap_mesh)
	var flame = MeshInstance3D.new()
	var fm = SphereMesh.new()
	fm.radius = 0.06
	fm.height = 0.12
	var fmat = StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.6, 0.1)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.5, 0.15)
	fmat.emission_energy_multiplier = 1.0
	fm.material = fmat
	flame.mesh = fm
	flame.position = Vector3(0, 0.44, 0)
	flame.set_meta("base_y", 0.44)
	flame.set_meta("seed", randf() * 10.0)
	pillar.add_child(flame)
	_field_props.append(flame)
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = 0.35
	light.omni_range = 1.5
	light.position = Vector3(0, 0.44, 0)
	pillar.add_child(light)


func _make_rock(pos: Vector3, radius: float, color: Color) -> void:
	var rock = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 1.4
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	sm.material = mat
	rock.mesh = sm
	rock.position = pos + Vector3(0, radius * 0.4, 0)
	add_child(rock)


func _make_crystal(pos: Vector3, radius: float, color: Color) -> void:
	var shard = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = radius * 5.0
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.6
	cm.material = mat
	shard.mesh = cm
	shard.position = pos + Vector3(0, radius * 2.5, 0)
	add_child(shard)


func _make_mushroom(pos: Vector3, cap_color: Color) -> void:
	var shroom = Node3D.new()
	shroom.position = pos
	add_child(shroom)
	var stem = MeshInstance3D.new()
	var sm = CylinderMesh.new()
	sm.top_radius = 0.02
	sm.bottom_radius = 0.03
	sm.height = 0.12
	var smat = StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	smat.albedo_color = Color(0.9, 0.88, 0.78)
	sm.material = smat
	stem.mesh = sm
	stem.position = Vector3(0, 0.06, 0)
	shroom.add_child(stem)
	var cap = MeshInstance3D.new()
	var capm = SphereMesh.new()
	capm.radius = 0.055
	capm.height = 0.05
	var cmat = StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	cmat.albedo_color = cap_color
	capm.material = cmat
	cap.mesh = capm
	cap.position = Vector3(0, 0.13, 0)
	shroom.add_child(cap)


func _make_deck_pile(pos: Vector3, color: Color, label_text: String) -> void:
	var pile = Node3D.new()
	pile.position = pos
	add_child(pile)
	for i in range(4):
		var slab = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(0.24, 0.008, 0.34)
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.albedo_color = color.darkened(i * 0.08)
		bm.material = mat
		slab.mesh = bm
		slab.position = Vector3((randf()-0.5)*0.01, 0.004+i*0.009, (randf()-0.5)*0.01)
		pile.add_child(slab)
	var lbl = Label3D.new()
	lbl.text = label_text
	lbl.font_size = 22
	lbl.pixel_size = 0.002
	lbl.position = Vector3(0, 0.05, 0)
	lbl.rotation = Vector3(-PI/2, 0, 0)
	lbl.modulate = Color(1,1,1,0.6)
	lbl.outline_modulate = Color(0,0,0,0.4)
	lbl.outline_size = 6
	pile.add_child(lbl)


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
		var pillar = flame.get_parent()
		for child in pillar.get_children():
			if child is OmniLight3D:
				child.light_energy = energy_base * (1.0 + sin(time * 6.0 + s) * 0.1)
				child.omni_range = range_base
