extends Node3D
## Card.gd — interaction, animation, keyword tracking.
##
## Cards load their data from CardDB via card_id. The mesh uses the
## card_front shader; this script sets the faction_color shader parameter
## from a small curated palette (so each card has a consistent ink tone)
## and lays out stat labels for the new card silhouette.

signal played
signal destroyed

@export var card_id: String = ""
@export var is_opponent: bool = false
@export var is_on_battlefield: bool = false

var card_data: Dictionary = {}
var current_hp := 0
var current_atk := 0
var current_lane: int = -1   # 0..3 once placed; -1 in hand
var has_attacked_this_turn: bool = false
var summoned_this_turn: bool = true   # for Charge logic

@onready var mesh: MeshInstance3D = $CardMesh
@onready var collision_area: Area3D = $Area3D
@onready var hover_glow: OmniLight3D = $HoverGlow

var _name_label: Label3D
var _atk_label: Label3D
var _hp_label: Label3D
var _cost_label: Label3D
var _desc_label: Label3D
var _keyword_label: Label3D
var _art_panel: MeshInstance3D

var _hand_target_position: Vector3
var _hand_target_rotation: Vector3
var _is_hovered := false
var _is_being_dragged := false
var _is_playing := false
var _drag_offset := Vector3.ZERO
var _active_tween: Tween = null
var _drag_velocity := Vector3.ZERO

const HOVER_LIFT := 0.20
const HOVER_LIFT_TIME := 0.14
const HOVER_DROP_TIME := 0.20
const HOVER_GLOW_ENERGY := 0.85
const PLAY_ARC_HEIGHT := 0.45
const PLAY_ARC_TIME := 0.55
const DRAG_SPRING_STIFFNESS := 60.0
const DRAG_SPRING_DAMPING := 14.0
const DRAG_HEIGHT := 0.20

# Card mesh is 0.42 x 0.014 x 0.60. Top face's UV (0..1) maps to local-space
# x∈[-0.21..0.21], z∈[-0.30..0.30]. Labels are positioned in local space.
const ART_SIZE := Vector2(0.32, 0.20)
const ART_POS := Vector3(0, 0.012, 0.05)

# Curated faction-color palette. Each card hashes to one of these — gives
# every card a consistent "ink tone" that matches the grimoire palette.
const FACTION_PALETTE: Array[Color] = [
	Color(0.55, 0.34, 0.10),  # ochre
	Color(0.42, 0.18, 0.20),  # rust red
	Color(0.20, 0.34, 0.20),  # moss
	Color(0.16, 0.32, 0.42),  # steel blue
	Color(0.32, 0.20, 0.42),  # violet
	Color(0.50, 0.32, 0.16),  # umber
	Color(0.18, 0.30, 0.32),  # verdigris
	Color(0.40, 0.16, 0.32),  # plum
]


func _ready() -> void:
	hover_glow.light_energy = 0.0
	collision_area.mouse_entered.connect(_on_mouse_entered)
	collision_area.mouse_exited.connect(_on_mouse_exited)
	collision_area.input_event.connect(_on_input_event)

	# Resolve card data from id if not set externally
	if card_data.is_empty() and card_id != "":
		card_data = CardDB.get_card_data(card_id)
	if card_data.size() > 0:
		current_hp = card_data.hp
		current_atk = card_data.atk

	_apply_card_visual()
	_create_art_panel()
	_create_stat_labels()


func has_keyword(kw: String) -> bool:
	if not card_data.has("keywords"):
		return false
	return card_data.keywords.has(kw)


func can_attack() -> bool:
	if has_attacked_this_turn:
		return false
	if summoned_this_turn and not has_keyword("charge"):
		return false
	return true


func _apply_card_visual() -> void:
	# Card front uses the card_front ShaderMaterial. We override its
	# faction_color from the palette using a stable per-card hash.
	var base_mat := mesh.get_active_material(0)
	if base_mat == null:
		return
	var mat := base_mat.duplicate() as ShaderMaterial
	if mat == null:
		return
	var idx := abs(card_id.hash()) % FACTION_PALETTE.size()
	var faction := FACTION_PALETTE[idx]
	# Opponent cards lean cooler/darker so they read as "the other side"
	if is_opponent:
		faction = faction.darkened(0.25).lerp(Color(0.20, 0.16, 0.22), 0.30)
	mat.set_shader_parameter("faction_color", faction)
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
		# Subtle dark vignetted swatch as placeholder
		var idx := abs(card_id.hash()) % FACTION_PALETTE.size()
		mat.albedo_color = FACTION_PALETTE[idx].darkened(0.55)
	quad.material = mat
	add_child(_art_panel)


func _create_stat_labels() -> void:
	if card_data.is_empty():
		return

	# Name sits in the faction band at the top of the card. The band runs
	# from z = -0.30 to z = -0.192 (UV.y 0 .. 0.18), so center the name at
	# roughly z = -0.245.
	_name_label = _make_label(card_data.name, 32,
		Vector3(0, 0.012, -0.245),
		Color(0.97, 0.93, 0.82), 6)
	_name_label.font_size = 32
	_name_label.outline_size = 6

	# Cost — small white numeral in a top-left dark badge area
	_cost_label = _make_label(str(card_data.cost), 60,
		Vector3(-0.165, 0.012, -0.245),
		Color(0.95, 0.92, 0.78), 12)

	# Description — small text under the art
	_desc_label = _make_label(card_data.get("desc", ""), 18,
		Vector3(0, 0.012, 0.18),
		Color(0.30, 0.22, 0.16), 0)
	if _desc_label:
		_desc_label.width = 380
		_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Keywords: short strip just under the name, on the parchment
	if card_data.has("keywords") and card_data.keywords.size() > 0:
		var kw_text := _format_keywords(card_data.keywords)
		_keyword_label = _make_label(kw_text, 16,
			Vector3(0, 0.012, -0.155),
			Color(0.55, 0.30, 0.10), 0)
		_keyword_label.outline_size = 0

	# Stats at the bottom — atk left, hp right, in their own ink color
	_atk_label = _make_label(str(current_atk), 56,
		Vector3(-0.155, 0.012, 0.245),
		Color(0.78, 0.20, 0.16), 10)
	_hp_label = _make_label(str(current_hp), 56,
		Vector3(0.155, 0.012, 0.245),
		Color(0.20, 0.55, 0.22), 10)


func _format_keywords(kws: Array) -> String:
	var display: Array[String] = []
	for k in kws:
		match k:
			"charge": display.append("Charge")
			"taunt": display.append("Taunt")
			"lifesteal": display.append("Lifesteal")
			"frenzy": display.append("Frenzy")
			"deathrattle_smite": display.append("Death: smite")
			"deathrattle_burn": display.append("Death: burn")
			"onplay_draw": display.append("Play: draw")
			"onplay_smite": display.append("Play: smite")
	return "  ".join(display)


func _make_label(text: String, size: int, pos: Vector3,
		color: Color, outline: int) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = size
	lbl.pixel_size = 0.001
	lbl.position = pos
	lbl.rotation = Vector3(-PI / 2, 0, 0)
	lbl.modulate = color
	lbl.outline_modulate = Color(0.04, 0.03, 0.05, 1)
	lbl.outline_size = outline
	lbl.no_depth_test = true
	add_child(lbl)
	return lbl


func update_stat_display() -> void:
	if _hp_label:
		_hp_label.text = str(max(current_hp, 0))
		if current_hp < card_data.hp:
			_hp_label.modulate = Color(1.0, 0.30, 0.25)
	if _atk_label:
		_atk_label.text = str(current_atk)
		if current_atk > card_data.atk:
			_atk_label.modulate = Color(1.0, 0.85, 0.30)


func _kill_active_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


func take_damage(amount: int) -> void:
	current_hp -= amount
	update_stat_display()
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
		Vector3(1.15, 0.7, 1.15), 0.06)
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


func _process(delta: float) -> void:
	if _is_playing or not _is_being_dragged:
		return
	_update_drag_spring(delta)


func _update_drag_spring(delta: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null: return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_dir = cam.project_ray_normal(mouse_pos)
	var plane = Plane(Vector3.UP, DRAG_HEIGHT)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null: return
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


func _on_mouse_entered() -> void:
	if _is_playing or _is_being_dragged: return
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
	if _is_being_dragged or _is_playing: return
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
			if event.pressed: _start_drag(position_3d)
			else: _end_drag()


func _start_drag(world_pos: Vector3) -> void:
	if _is_playing or is_on_battlefield or is_opponent: return
	_kill_active_tween()
	_is_being_dragged = true
	_is_hovered = false
	_drag_velocity = Vector3.ZERO
	_drag_offset = global_position - world_pos
	_drag_offset.y = 0
	scale = Vector3(1.10, 1.10, 1.10)
	hover_glow.light_energy = HOVER_GLOW_ENERGY


func _end_drag() -> void:
	if not _is_being_dragged: return
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
	_active_tween.tween_property(self, "scale", Vector3(1.20, 0.65, 1.20), 0.06)
	_active_tween.tween_property(self, "scale", Vector3.ONE, 0.20)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var rot_tween = create_tween()
	rot_tween.tween_property(self, "rotation", Vector3.ZERO, PLAY_ARC_TIME)
	_active_tween.finished.connect(func(): _is_playing = false)
