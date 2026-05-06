extends PanelContainer
## Card2D.gd — 2D card with drag, hover, and stat display.
## Replaces the old 3D Card.gd. Works as a hand card and a battlefield card.

signal played
signal destroyed

@export var card_id: String = ""
@export var is_opponent: bool = false
@export var is_on_battlefield: bool = false

var card_data: Dictionary = {}
var current_hp := 0
var current_atk := 0
var current_lane: int = -1
var has_attacked_this_turn: bool = false
var summoned_this_turn: bool = true

# Labels
var _name_label: Label
var _atk_label: Label
var _hp_label: Label
var _cost_label: Label
var _desc_label: Label
var _keyword_label: Label

# Drag state
var _is_hovered := false
var _is_being_dragged := false
var _is_playing := false
var _drag_offset := Vector2.ZERO
var _hand_target_position := Vector2.ZERO
var _hand_target_rotation := 0.0
var _active_tween: Tween = null

const CARD_SIZE := Vector2(140, 200)
const HOVER_SCALE := 1.15
const HOVER_LIFT := 30.0
const HOVER_TIME := 0.12
const PLAY_THRESHOLD_Y := 0.45

# Colors
const BG_PLAYER := Color(0.12, 0.10, 0.08, 0.95)
const BG_ENEMY := Color(0.15, 0.06, 0.06, 0.95)
const BORDER_NORMAL := Color(0.55, 0.40, 0.18)
const BORDER_HOVER := Color(0.90, 0.75, 0.35)
const ATK_COLOR := Color(1.0, 0.35, 0.25)
const HP_COLOR := Color(0.25, 0.85, 0.35)
const HP_DAMAGED := Color(1.0, 0.3, 0.3)
const ATK_BUFFED := Color(1.0, 0.8, 0.2)
const COST_COLOR := Color(0.4, 0.65, 1.0)
const KEYWORD_COLOR := Color(1.0, 0.85, 0.45)
const NAME_COLOR := Color(0.96, 0.92, 0.78)
const DESC_COLOR := Color(0.70, 0.66, 0.55)


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if card_data.is_empty() and card_id != "":
		card_data = CardDB.get_card_data(card_id)
	if card_data.size() > 0:
		current_hp = card_data.hp
		current_atk = card_data.atk

	_build_style()
	_build_layout()


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


func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_ENEMY if is_opponent else BG_PLAYER
	style.border_color = BORDER_NORMAL
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)


func _build_layout() -> void:
	if card_data.is_empty():
		return

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	# Top row: cost + name
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	_cost_label = _make_label(str(card_data.cost), 18, COST_COLOR)
	_cost_label.custom_minimum_size.x = 22
	top_row.add_child(_cost_label)

	_name_label = _make_label(card_data.name, 14, NAME_COLOR)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	top_row.add_child(_name_label)

	# Keywords
	if card_data.has("keywords") and card_data.keywords.size() > 0:
		_keyword_label = _make_label(
			KeywordEffects.display_text_for(card_data.keywords),
			10, KEYWORD_COLOR)
		_keyword_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_keyword_label)

	# Art placeholder
	var art := ColorRect.new()
	art.custom_minimum_size = Vector2(0, 60)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h = float(abs(card_id.hash()) % 360) / 360.0
	var sat = 0.35 if is_opponent else 0.45
	var val = 0.25 if is_opponent else 0.35
	art.color = Color.from_hsv(h, sat, val)
	vbox.add_child(art)

	# Description
	_desc_label = _make_label(card_data.get("desc", ""), 10, DESC_COLOR)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_desc_label)

	# Bottom row: ATK / HP
	var bot_row := HBoxContainer.new()
	bot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bot_row)

	_atk_label = _make_label(str(current_atk), 22, ATK_COLOR)
	_atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_atk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(_atk_label)

	var sep := Label.new()
	sep.text = "/"
	sep.add_theme_font_size_override("font_size", 18)
	sep.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_row.add_child(sep)

	_hp_label = _make_label(str(current_hp), 22, HP_COLOR)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_row.add_child(_hp_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func update_stat_display() -> void:
	if _hp_label:
		_hp_label.text = str(max(current_hp, 0))
		_hp_label.add_theme_color_override("font_color",
			HP_DAMAGED if current_hp < card_data.hp else HP_COLOR)
	if _atk_label:
		_atk_label.text = str(current_atk)
		_atk_label.add_theme_color_override("font_color",
			ATK_BUFFED if current_atk > card_data.atk else ATK_COLOR)


func take_damage(amount: int) -> void:
	current_hp -= amount
	update_stat_display()
	# Hit shake
	var orig_pos = position
	var tw = create_tween()
	tw.tween_property(self, "position",
		orig_pos + Vector2((randf() - 0.5) * 8, (randf() - 0.5) * 8), 0.05)
	tw.tween_property(self, "position", orig_pos, 0.15)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if current_hp <= 0:
		_die()


func _die() -> void:
	destroyed.emit()
	_kill_active_tween()
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2(0.8, 0.8), 0.3)
	tw.tween_callback(queue_free)


func _kill_active_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


# -- Hand positioning --

func set_hand_target(pos: Vector2, rot: float) -> void:
	_hand_target_position = pos
	_hand_target_rotation = rot
	if not _is_hovered and not _is_being_dragged:
		_animate_to_hand_position()


func _animate_to_hand_position() -> void:
	_kill_active_tween()
	_active_tween = create_tween().set_parallel()
	_active_tween.tween_property(self, "position", _hand_target_position, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "rotation", _hand_target_rotation, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_active_tween.tween_property(self, "scale", Vector2.ONE, 0.2)


# -- Hover --

func _on_mouse_entered() -> void:
	if _is_playing or _is_being_dragged:
		return
	_is_hovered = true
	if is_on_battlefield:
		_set_border_color(BORDER_HOVER)
		return
	_kill_active_tween()
	var lifted_pos = _hand_target_position + Vector2(0, -HOVER_LIFT)
	_active_tween = create_tween().set_parallel()
	_active_tween.tween_property(self, "position", lifted_pos, HOVER_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_active_tween.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_TIME)
	_active_tween.tween_property(self, "rotation", 0.0, HOVER_TIME)
	z_index = 10
	_set_border_color(BORDER_HOVER)


func _on_mouse_exited() -> void:
	if _is_being_dragged or _is_playing:
		return
	_is_hovered = false
	if is_on_battlefield:
		_set_border_color(BORDER_NORMAL)
		return
	z_index = 0
	_set_border_color(BORDER_NORMAL)
	_animate_to_hand_position()


func _set_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s = style.duplicate() as StyleBoxFlat
		s.border_color = color
		add_theme_stylebox_override("panel", s)


# -- Drag --

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.global_position)
			else:
				_end_drag()
	elif event is InputEventMouseMotion and _is_being_dragged:
		_update_drag(event.global_position)


func _start_drag(mouse_pos: Vector2) -> void:
	if _is_playing or is_on_battlefield or is_opponent:
		return
	_kill_active_tween()
	_is_being_dragged = true
	_is_hovered = false
	_drag_offset = global_position - mouse_pos
	z_index = 20
	scale = Vector2(1.08, 1.08)


func _update_drag(mouse_pos: Vector2) -> void:
	global_position = mouse_pos + _drag_offset


func _end_drag() -> void:
	if not _is_being_dragged:
		return
	_is_being_dragged = false
	z_index = 0
	var viewport_h = get_viewport_rect().size.y
	if global_position.y < viewport_h * PLAY_THRESHOLD_Y:
		played.emit()
	else:
		_animate_to_hand_position()


func fly_to_play_area(target_pos: Vector2) -> void:
	_kill_active_tween()
	_is_playing = true
	scale = Vector2.ONE
	_active_tween = create_tween()
	_active_tween.tween_property(self, "global_position", target_pos, 0.35)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_active_tween.tween_property(self, "rotation", 0.0, 0.35)
	_active_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.06)
	_active_tween.tween_property(self, "scale", Vector2.ONE, 0.15)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_active_tween.finished.connect(func(): _is_playing = false)
