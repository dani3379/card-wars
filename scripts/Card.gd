extends Node3D
## Card.gd — interaction handling with clean state machine.
##
## Game-feel additions vs. original:
##  • Spring-damped drag so the card has a touch of weight without flicker.
##  • Landing squash on play (flatten on impact, recover with elastic).
##  • Beefier hit reaction (positional + rotational + scale, parallel tracks).
##  • Anticipation pop on death.
##
## Things deliberately NOT included (they fought each other in earlier rev):
##  • Mouse-aim hover tilt
##  • Velocity-driven tilt during drag
##  • Idle breathing on hand cards
## These can be added back one at a time AFTER the base feels right.

signal played
signal destroyed

@export var card_id: String = "default"
@export var is_opponent: bool = false
@export var is_on_battlefield: bool = false

var card_data: Dictionary = {}
var current_hp := 0
var current_atk := 0

@onready var mesh: MeshInstance3D = $CardMesh
@onready var collision_area: Area3D = $Area3D
@onready var hover_glow: OmniLight3D = $HoverGlow

var _name_label: Label3D
var _atk_label: Label3D
var _hp_label: Label3D
var _cost_label: Label3D
var _desc_label: Label3D
var _art_panel: MeshInstance3D

var _hand_target_position: Vector3
var _hand_target_rotation: Vector3
var _is_hovered := false
var _is_being_dragged := false
var _is_playing := false
var _drag_offset := Vector3.ZERO
var _active_tween: Tween = null

# Spring-drag state
var _drag_velocity := Vector3.ZERO

const HOVER_LIFT := 0.18
const HOVER_LIFT_TIME := 0.15
const HOVER_DROP_TIME := 0.22
const HOVER_GLOW_ENERGY := 0.7
const PLAY_ARC_HEIGHT := 0.4
const PLAY_ARC_TIME := 0.55

# Spring tuning. Tight, slightly underdamped — feels like the card is
# attached to the cursor by a short rubber band, not a suspension bridge.
const DRAG_SPRING_STIFFNESS := 60.0
const DRAG_SPRING_DAMPING := 14.0
const DRAG_HEIGHT := 0.18

const ART_SIZE := Vector2(0.30, 0.22)
const ART_POS := Vector3(0, 0.006, 0.04)


func _ready() -> void:
	hover_glow.light_energy = 0.0
	collision_area.mouse_entered.connect(_on_mouse_entered)
	collision_area.mouse_exited.connect(_on_mouse_exited)
	collision_area.input_event.connect(_on_input_event)

	if card_data.size() > 0:
		current_hp = card_data.hp
		current_atk = card_data.atk

	_apply_card_visual()
	_create_art_panel()
	_create_stat_labels()


func _apply_card_visual() -> void:
	var base_mat = mesh.get_active_material(0)
	if base_mat == null:
		return
	var mat = base_mat.duplicate()

	if mat is StandardMaterial3D:
		var h = float(abs(card_id.hash()) % 360) / 360.0
		var sat = 0.40 if is_opponent else 0.50
		var val = 0.35 if is_opponent else 0.60
		mat.albedo_color = Color.from_hsv(h, sat, val)
	elif mat is ShaderMaterial:
		var h = float(abs(card_id.hash()) % 360) / 360.0
		var sat = 0.50 if is_opponent else 0.55
		var val = 0.55 if is_opponent else 1.0
		mat.set_shader_parameter("albedo", Color.from_hsv(h, sat, val))

	mesh.set_surface_override_material(0, mat)


func _create_art_panel() -> void:
	_art_panel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = ART_SIZE
	_art_panel.mesh = quad
	_art_panel.position = ART_POS
	_art_panel.rotation = Vector3(-PI / 2, 0, 0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	var art_path := "res://textures/cards/%s.png" % card_id
	if ResourceLoader.exists(art_path):
		mat.albedo_texture = load(art_path)
		mat.albedo_color = Color.WHITE
	else:
		var h = float(abs(card_id.hash()) % 360) / 360.0
		mat.albedo_color = Color.from_hsv(h, 0.45, 0.30)

	quad.material = mat
	add_child(_art_panel)


func refresh_art() -> void:
	if _art_panel:
		_art_panel.queue_free()
	_create_art_panel()


func _create_stat_labels() -> void:
	if card_data.size() == 0:
		return

	_name_label = Label3D.new()
	_name_label.text = card_data.name
	_name_label.font_size = 48
	_name_label.pixel_size = 0.001
	_name_label.position = Vector3(0, 0.005, -0.20)
	_name_label.rotation = Vector3(-PI / 2, 0, 0)
	_name_label.modulate = Color.WHITE
	_name_label.outline_modulate = Color.BLACK
	_name_label.outline_size = 12
	_name_label.no_depth_test = true
	add_child(_name_label)

	_desc_label = Label3D.new()
	_desc_label.text = card_data.desc
	_desc_label.font_size = 22
	_desc_label.pixel_size = 0.001
	_desc_label.position = Vector3(0, 0.005, -0.12)
	_desc_label.rotation = Vector3(-PI / 2, 0, 0)
	_desc_label.modulate = Color(0.75, 0.70, 0.55)
	_desc_label.outline_modulate = Color.BLACK
	_desc_label.outline_size = 5
	_desc_label.no_depth_test = true
	add_child(_desc_label)

	_atk_label = Label3D.new()
	_atk_label.text = str(current_atk)
	_atk_label.font_size = 64
	_atk_label.pixel_size = 0.001
	_atk_label.position = Vector3(-0.13, 0.005, 0.21)
	_atk_label.rotation = Vector3(-PI / 2, 0, 0)
	_atk_label.modulate = Color(1.0, 0.35, 0.25)
	_atk_label.outline_modulate = Color.BLACK
	_atk_label.outline_size = 14
	_atk_label.no_depth_test = true
	add_child(_atk_label)

	_hp_label = Label3D.new()
	_hp_label.text = str(current_hp)
	_hp_label.font_size = 64
	_hp_label.pixel_size = 0.001
	_hp_label.position = Vector3(0.13, 0.005, 0.21)
	_hp_label.rotation = Vector3(-PI / 2, 0, 0)
	_hp_label.modulate = Color(0.25, 0.85, 0.35)
	_hp_label.outline_modulate = Color.BLACK
	_hp_label.outline_size = 14
	_hp_label.no_depth_test = true
	add_child(_hp_label)

	_cost_label = Label3D.new()
	_cost_label.text = str(card_data.cost)
	_cost_label.font_size = 52
	_cost_label.pixel_size = 0.001
	_cost_label.position = Vector3(0.14, 0.005, -0.22)
	_cost_label.rotation = Vector3(-PI / 2, 0, 0)
	_cost_label.modulate = Color(0.4, 0.6, 1.0)
	_cost_label.outline_modulate = Color.BLACK
	_cost_label.outline_size = 12
	_cost_label.no_depth_test = true
	add_child(_cost_label)


func _kill_active_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


func take_damage(amount: int) -> void:
	current_hp -= amount
	if _hp_label:
		_hp_label.text = str(max(current_hp, 0))
		if current_hp < card_data.hp:
			_hp_label.modulate = Color(1.0, 0.3, 0.3)

	var orig_pos = position
	var orig_rot = rotation
	var hit_tween = create_tween().set_parallel()
	hit_tween.tween_property(self, "position",
		orig_pos + Vector3((randf() - 0.5) * 0.04, 0.04, (randf() - 0.5) * 0.04),
		0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(self, "rotation",
		orig_rot + Vector3(0, 0, (randf() - 0.5) * 0.4),
		0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(self, "scale",
		Vector3(1.15, 0.7, 1.15),
		0.06)
	hit_tween.chain().tween_property(self, "position", orig_pos,
		0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	hit_tween.parallel().tween_property(self, "rotation", orig_rot,
		0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	hit_tween.parallel().tween_property(self, "scale", Vector3.ONE,
		0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if current_hp <= 0:
		_die()


func _die() -> void:
	destroyed.emit()
	_kill_active_tween()
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.25, 1.25, 1.25), 0.08)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "position:y", position.y + 0.05, 0.08)
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "position:y", position.y + 0.25, 0.35)
	tween.tween_callback(queue_free)


# Per-frame: ONLY the spring drag runs in process. Everything else is
# handled by tweens, which means no two systems write to the same
# property in the same frame.
func _process(delta: float) -> void:
	if _is_playing or not _is_being_dragged:
		return
	_update_drag_spring(delta)


func _update_drag_spring(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_dir = cam.project_ray_normal(mouse_pos)
	var plane = Plane(Vector3.UP, DRAG_HEIGHT)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return
	var target = hit + _drag_offset
	target.y = DRAG_HEIGHT

	var to_target = target - global_position
	var force = to_target * DRAG_SPRING_STIFFNESS - _drag_velocity * DRAG_SPRING_DAMPING
	_drag_velocity += force * delta
	if _drag_velocity.length() > 15.0:
		_drag_velocity = _drag_velocity.normalized() * 15.0
	global_position += _drag_velocity * delta
	global_position.y = DRAG_HEIGHT


func set_hand_target(pos: Vector3, rot: Vector3) -> void:
	_hand_target_position = pos
	_hand_target_rotation = rot
	if not _is_hovered and not _is_being_dragged:
		_animate_to_hand_position()


func _animate_to_hand_position() -> void:
	_kill_active_tween()
	_active_tween = create_tween().set_parallel()
	_active_tween.tween_property(self, "position", _hand_target_position,
		HOVER_DROP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "rotation", _hand_target_rotation,
		HOVER_DROP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "scale", Vector3.ONE, HOVER_DROP_TIME)


# CRITICAL: bail when dragging. Otherwise the dragged card's collision
# area keeps re-entering under the cursor and triggers a hover-tween
# that fights the spring, causing the flicker bug.
func _on_mouse_entered() -> void:
	if _is_playing or _is_being_dragged:
		return
	_is_hovered = true
	if is_on_battlefield:
		_active_tween = create_tween()
		_active_tween.tween_property(hover_glow, "light_energy",
			HOVER_GLOW_ENERGY * 0.5, 0.15)
		return
	_kill_active_tween()
	var lifted_pos = _hand_target_position + Vector3(0, HOVER_LIFT * 0.7, -0.05)
	var leveled_rot = Vector3(deg_to_rad(-6), _hand_target_rotation.y * 0.3, 0)
	_active_tween = create_tween().set_parallel()
	_active_tween.tween_property(self, "position", lifted_pos,
		HOVER_LIFT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_active_tween.tween_property(self, "rotation", leveled_rot,
		HOVER_LIFT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "scale", Vector3(1.15, 1.15, 1.15),
		HOVER_LIFT_TIME)
	_active_tween.tween_property(hover_glow, "light_energy", HOVER_GLOW_ENERGY,
		HOVER_LIFT_TIME)


func _on_mouse_exited() -> void:
	if _is_being_dragged or _is_playing:
		return
	_is_hovered = false
	if is_on_battlefield:
		_active_tween = create_tween()
		_active_tween.tween_property(hover_glow, "light_energy", 0.0, 0.2)
		return
	_kill_active_tween()
	_active_tween = create_tween().set_parallel()
	_active_tween.tween_property(self, "position", _hand_target_position,
		HOVER_DROP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "rotation", _hand_target_rotation,
		HOVER_DROP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "scale", Vector3.ONE, HOVER_DROP_TIME)
	_active_tween.tween_property(hover_glow, "light_energy", 0.0, HOVER_DROP_TIME)


func _on_input_event(_camera: Node, event: InputEvent, position_3d: Vector3,
		_normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(position_3d)
			else:
				_end_drag()


func _start_drag(world_pos: Vector3) -> void:
	if _is_playing or is_on_battlefield or is_opponent:
		return
	_kill_active_tween()
	_is_being_dragged = true
	_is_hovered = false  # Force-clear so mouse_exited later doesn't no-op wrong
	_drag_velocity = Vector3.ZERO
	_drag_offset = global_position - world_pos
	_drag_offset.y = 0
	scale = Vector3(1.10, 1.10, 1.10)
	hover_glow.light_energy = HOVER_GLOW_ENERGY


func _end_drag() -> void:
	if not _is_being_dragged:
		return
	_is_being_dragged = false
	_drag_velocity = Vector3.ZERO
	if global_position.z < 1.5:
		played.emit()
	else:
		_animate_to_hand_position()


func fly_to_play_area(target_pos: Vector3) -> void:
	_kill_active_tween()
	_is_playing = true
	hover_glow.light_energy = 0.0
	scale = Vector3.ONE
	var mid = (global_position + target_pos) * 0.5 + Vector3(0, PLAY_ARC_HEIGHT, 0)

	_active_tween = create_tween()
	_active_tween.tween_property(self, "global_position", mid,
		PLAY_ARC_TIME * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_active_tween.tween_property(self, "global_position", target_pos,
		PLAY_ARC_TIME * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Landing squash, then elastic recovery
	_active_tween.tween_property(self, "scale", Vector3(1.20, 0.65, 1.20), 0.06)
	_active_tween.tween_property(self, "scale", Vector3.ONE, 0.20)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var rot_tween = create_tween()
	rot_tween.tween_property(self, "rotation", Vector3.ZERO, PLAY_ARC_TIME)
	_active_tween.finished.connect(func(): _is_playing = false)
