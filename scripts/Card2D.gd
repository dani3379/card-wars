extends PanelContainer
## Card2D.gd — 2D card with drag, hover, stat display.
## Supports creatures (ATK/HP) and spells (effect text). Floop toggle on battlefield.
## All animations removed for performance.

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
var will_floop: bool = false
var last_stand_used: bool = false
var is_token: bool = false
var temp_atk_buff: int = 0

var _name_label: Label
var _atk_label: Label
var _hp_label: Label
var _cost_label: Label
var _desc_label: Label
var _keyword_label: Label
var _type_label: Label
var _floop_indicator: Label

var _is_hovered := false
var _is_being_dragged := false
var _is_playing := false
var _drag_offset := Vector2.ZERO
var _hand_target_position := Vector2.ZERO
var _hand_target_rotation := 0.0

const CARD_SIZE := Vector2(140, 200)
const PLAY_THRESHOLD_Y := 0.45

const BG_PLAYER := Color(0.12, 0.10, 0.08, 0.95)
const BG_ENEMY := Color(0.15, 0.06, 0.06, 0.95)
const BG_SPELL := Color(0.08, 0.06, 0.14, 0.95)
const BORDER_NORMAL := Color(0.55, 0.40, 0.18)
const BORDER_HOVER := Color(0.90, 0.75, 0.35)
const BORDER_FLOOP := Color(0.30, 0.70, 0.95)
const ATK_COLOR := Color(1.0, 0.35, 0.25)
const HP_COLOR := Color(0.25, 0.85, 0.35)
const HP_DAMAGED := Color(1.0, 0.3, 0.3)
const ATK_BUFFED := Color(1.0, 0.8, 0.2)
const COST_COLOR := Color(0.4, 0.65, 1.0)
const KEYWORD_COLOR := Color(1.0, 0.85, 0.45)
const NAME_COLOR := Color(0.96, 0.92, 0.78)
const DESC_COLOR := Color(0.70, 0.66, 0.55)
const SPELL_TYPE_COLOR := Color(0.65, 0.50, 0.90)


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	if card_data.is_empty() and card_id != "":
		card_data = CardDB.get_card_data(card_id)
	if card_data.size() > 0:
		if is_creature():
			current_hp = card_data.hp
			current_atk = card_data.atk

	_build_style()
	_build_layout()


func is_creature() -> bool:
	return card_data.get("type", "creature") == "creature"


func is_spell() -> bool:
	return card_data.get("type", "") == "spell"


func has_keyword(kw: String) -> bool:
	if not card_data.has("keywords"):
		return false
	return card_data.keywords.has(kw)


func has_floop() -> bool:
	return card_data.has("floop")


func can_attack() -> bool:
	if has_attacked_this_turn:
		return false
	if will_floop:
		return false
	if card_data.get("passive", "") == "cannot_attack_wall":
		return false
	if card_data.get("passive", "") == "siege":
		return true
	return true


func effective_atk() -> int:
	return current_atk + temp_atk_buff


func _build_style() -> void:
	var style := StyleBoxFlat.new()
	if is_spell():
		style.bg_color = BG_SPELL
	elif is_opponent:
		style.bg_color = BG_ENEMY
	else:
		style.bg_color = BG_PLAYER
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

	# Type indicator for spells
	if is_spell():
		_type_label = _make_label("SPELL", 10, SPELL_TYPE_COLOR)
		_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(_type_label)

	# Keywords
	if card_data.has("keywords") and card_data.keywords.size() > 0:
		_keyword_label = _make_label(
			KeywordEffects.display_text_for(card_data.keywords),
			10, KEYWORD_COLOR)
		_keyword_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_keyword_label)

	# Art placeholder (creatures only)
	if is_creature():
		var art := ColorRect.new()
		art.custom_minimum_size = Vector2(0, 50)
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

	# Bottom row: ATK / HP for creatures, empty for spells
	if is_creature():
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

	# Floop indicator (hidden by default, shown when toggled on battlefield)
	_floop_indicator = _make_label("FLOOP", 12, BORDER_FLOOP)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.visible = false
	vbox.add_child(_floop_indicator)


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
		var display_atk = current_atk + temp_atk_buff
		_atk_label.text = str(display_atk)
		_atk_label.add_theme_color_override("font_color",
			ATK_BUFFED if display_atk > card_data.atk else ATK_COLOR)


func update_floop_display() -> void:
	if _floop_indicator:
		_floop_indicator.visible = will_floop
	_set_border_color(BORDER_FLOOP if will_floop else BORDER_NORMAL)


func toggle_floop() -> void:
	if not has_floop():
		return
	will_floop = not will_floop
	update_floop_display()


func take_damage(amount: int) -> void:
	if has_keyword("armored"):
		amount = maxi(1, amount - 1)
	if card_data.get("extra_damage", 0) > 0:
		amount += card_data.extra_damage
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
	update_stat_display()
	if current_hp <= 0:
		_die()


func take_damage_bypass_armor(amount: int) -> void:
	current_hp -= amount
	if current_hp <= 0 and has_keyword("last_stand") and not last_stand_used:
		current_hp = 1
		last_stand_used = true
	update_stat_display()
	if current_hp <= 0:
		_die()


func _die() -> void:
	destroyed.emit()
	queue_free()


func set_hand_target(pos: Vector2, rot: float) -> void:
	_hand_target_position = pos
	_hand_target_rotation = rot
	if not _is_hovered and not _is_being_dragged:
		position = _hand_target_position
		rotation = _hand_target_rotation
		scale = Vector2.ONE


func _on_mouse_entered() -> void:
	if _is_playing or _is_being_dragged:
		return
	_is_hovered = true
	_set_border_color(BORDER_HOVER)
	if not is_on_battlefield:
		z_index = 10


func _on_mouse_exited() -> void:
	if _is_being_dragged or _is_playing:
		return
	_is_hovered = false
	_set_border_color(BORDER_FLOOP if (is_on_battlefield and will_floop) else BORDER_NORMAL)
	if not is_on_battlefield:
		z_index = 0
		position = _hand_target_position
		rotation = _hand_target_rotation
		scale = Vector2.ONE


func _set_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


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
	_is_being_dragged = true
	_is_hovered = false
	_drag_offset = global_position - mouse_pos
	z_index = 20


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
		position = _hand_target_position
		rotation = _hand_target_rotation
		scale = Vector2.ONE


func fly_to_play_area(target_pos: Vector2) -> void:
	_is_playing = true
	global_position = target_pos
	rotation = 0.0
	scale = Vector2.ONE
	_is_playing = false
