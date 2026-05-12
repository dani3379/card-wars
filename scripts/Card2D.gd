extends PanelContainer
## Card2D.gd — 150x200 card with ornate frame overlay.
## Layers: card art → ornate frame → name banner + divider → content.

signal played
signal destroyed
signal floop_clicked

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
var has_flooped_this_turn: bool = false
var last_stand_used: bool = false
var is_token: bool = false
var temp_atk_buff: int = 0

var _name_label: Label
var _atk_label: Label
var _hp_label: Label
var _cost_label: Label
var _desc_label: Label
var _type_label: Label
var _floop_indicator: Label
var _rarity_strip: ColorRect
var _art_rect: Control
var _cost_badge: Panel
var _frame_tex: TextureRect
var _atk_badge: HBoxContainer
var _hp_badge: HBoxContainer
var _default_border_color: Color

var _is_hovered := false
var _is_being_dragged := false
var _is_playing := false
var _drag_offset := Vector2.ZERO
var _hand_target_position := Vector2.ZERO
var _hand_target_rotation := 0.0

const CARD_W := 150
const CARD_H := 200
const CARD_SIZE := Vector2(CARD_W, CARD_H)
const PLAY_THRESHOLD_Y := 0.45


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	if has_attacked_this_turn: return false
	if will_floop: return false
	if has_flooped_this_turn: return false
	if card_data.get("passive", "") == "cannot_attack_wall": return false
	if card_data.get("passive", "") == "siege": return true
	return true

func effective_atk() -> int:
	return current_atk + temp_atk_buff


# ═══════════════════════════════════════════
#  CARD BACKGROUND
# ═══════════════════════════════════════════

func _build_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = Color(0, 0, 0, 0)
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.shadow_color = Color(0, 0, 0, 0.7)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", s)
	_default_border_color = Color(0, 0, 0, 0)


# ═══════════════════════════════════════════
#  LAYOUT — layered: art → frame → banner → content
# ═══════════════════════════════════════════

func _find_card_art() -> Texture2D:
	var cid = card_data.get("id", "")
	var name_id = card_data.get("name", "").to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = null
	if is_spell():
		art = GameTheme.try_load_spell_art(cid)
		if art == null:
			art = GameTheme.try_load_spell_art(name_id)
	if art == null:
		art = GameTheme.try_load_creature_art(cid)
	if art == null and name_id != "":
		art = GameTheme.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = GameTheme.try_load_creature_art("e_" + name_id)
	return art


func _build_layout() -> void:
	if card_data.is_empty():
		return

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Layer 1: Card art clipped inside frame window ──
	var card_art: Texture2D = _find_card_art()
	if card_art:
		var art_clip := Control.new()
		art_clip.clip_contents = true
		art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.anchor_left = 0.06
		art_clip.anchor_right = 0.94
		art_clip.anchor_top = 0.05
		art_clip.anchor_bottom = 0.54
		root.add_child(art_clip)
		_art_rect = art_clip

		var art_tex := TextureRect.new()
		art_tex.texture = card_art
		art_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tex.anchor_bottom = 1.5
		art_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_clip.add_child(art_tex)
	else:
		var placeholder := ColorRect.new()
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hue = float(abs(card_id.hash()) % 360) / 360.0
		placeholder.color = Color.from_hsv(hue, 0.45 if not is_opponent else 0.30, 0.35 if not is_opponent else 0.22)
		placeholder.anchor_left = 0.06
		placeholder.anchor_right = 0.94
		placeholder.anchor_top = 0.05
		placeholder.anchor_bottom = 0.54
		root.add_child(placeholder)
		_art_rect = placeholder

	# ── Layer 2: Ornate frame overlay ──
	if GameTheme.tex_card_frame_ornate:
		_frame_tex = TextureRect.new()
		_frame_tex.texture = GameTheme.tex_card_frame_ornate
		_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_spell():
			_frame_tex.self_modulate = Color(0.85, 0.78, 1.0)
		elif is_opponent:
			_frame_tex.self_modulate = Color(1.0, 0.82, 0.78)
		root.add_child(_frame_tex)

	# ── Layer 3: Name banner (top, over art) ──
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_left = 0.06
	banner.anchor_right = 0.94
	banner.anchor_top = 0.04
	banner.anchor_bottom = 0.16
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.06, 0.05, 0.04, 0.88)
	bs.border_color = Color(0.65, 0.50, 0.25, 0.8)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(3)
	bs.content_margin_left = 2
	bs.content_margin_right = 4
	bs.content_margin_top = 0
	bs.content_margin_bottom = 0
	banner.add_theme_stylebox_override("panel", bs)
	root.add_child(banner)

	var banner_row := HBoxContainer.new()
	banner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.add_theme_constant_override("separation", 3)
	banner.add_child(banner_row)

	_cost_badge = _make_circle_badge(GameTheme.MANA_BLUE, 18)
	banner_row.add_child(_cost_badge)
	_cost_label = _make_badge_label(str(card_data.cost), 11)
	_cost_badge.add_child(_cost_label)

	_name_label = Label.new()
	_name_label.text = card_data.name
	if GameTheme.font_display:
		_name_label.add_theme_font_override("font", GameTheme.font_display)
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", GameTheme.IVORY)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("outline_size", 2)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.add_child(_name_label)

	# ── Gold divider at art-text boundary ──
	var divider := ColorRect.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.anchor_left = 0.07
	divider.anchor_right = 0.93
	divider.anchor_top = 0.555
	divider.anchor_bottom = 0.565
	divider.color = Color(GameTheme.GILT.r, GameTheme.GILT.g, GameTheme.GILT.b, 0.6)
	root.add_child(divider)

	# ── Layer 4: Content in stone area ──
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	content.anchor_left = 0.07
	content.anchor_right = 0.93
	content.anchor_top = 0.57
	content.anchor_bottom = 0.97
	root.add_child(content)

	_rarity_strip = ColorRect.new()
	_rarity_strip.custom_minimum_size = Vector2(0, 2)
	_rarity_strip.color = GameTheme.rarity_color(card_data.get("rarity", "common"))
	_rarity_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_rarity_strip)

	if is_spell():
		_type_label = Label.new()
		_type_label.text = "SPELL"
		if GameTheme.font_display:
			_type_label.add_theme_font_override("font", GameTheme.font_display)
		_type_label.add_theme_font_size_override("font_size", 9)
		_type_label.add_theme_color_override("font_color", GameTheme.SPELL_PURPLE)
		_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_type_label.custom_minimum_size = Vector2(0, 10)
		_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(_type_label)

	_desc_label = Label.new()
	_desc_label.text = card_data.get("desc", "")
	if GameTheme.font_body:
		_desc_label.add_theme_font_override("font", GameTheme.font_body)
	_desc_label.add_theme_font_size_override("font_size", 9)
	_desc_label.add_theme_color_override("font_color", GameTheme.DESC_DIM)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.clip_text = true
	_desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_desc_label)

	_floop_indicator = Label.new()
	_floop_indicator.text = "FLOOP"
	if GameTheme.font_display:
		_floop_indicator.add_theme_font_override("font", GameTheme.font_display)
	_floop_indicator.add_theme_font_size_override("font_size", 9)
	_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
	_floop_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floop_indicator.custom_minimum_size = Vector2(0, 10)
	_floop_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floop_indicator.visible = false
	content.add_child(_floop_indicator)

	if is_creature():
		var footer := HBoxContainer.new()
		footer.custom_minimum_size = Vector2(0, 20)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(footer)

		_atk_badge = GameTheme.make_icon_stat(
			GameTheme.tex_icon_sword, str(current_atk),
			GameTheme.ATK_RED, 15)
		footer.add_child(_atk_badge)
		_atk_label = _atk_badge.get_child(1) as Label

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_child(spacer)

		_hp_badge = GameTheme.make_icon_stat(
			GameTheme.tex_icon_heart, str(current_hp),
			GameTheme.HEALTH_GREEN, 15)
		footer.add_child(_hp_badge)
		_hp_label = _hp_badge.get_child(1) as Label
	else:
		var spell_foot := Label.new()
		spell_foot.text = "— SPELL —"
		if GameTheme.font_display:
			spell_foot.add_theme_font_override("font", GameTheme.font_display)
		spell_foot.add_theme_font_size_override("font_size", 9)
		spell_foot.add_theme_color_override("font_color", GameTheme.SPELL_PURPLE)
		spell_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spell_foot.custom_minimum_size = Vector2(0, 14)
		spell_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(spell_foot)


# ── Layout helpers ──

func _make_circle_badge(color: Color, sz: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(sz, sz)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.lightened(0.3)
	s.border_color.a = 0.4
	var r := int(sz * 0.5)
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	p.add_theme_stylebox_override("panel", s)
	return p


func _make_badge_label(text: String, font_sz: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	if GameTheme.font_body:
		lbl.add_theme_font_override("font", GameTheme.font_body)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ═══════════════════════════════════════════
#  STAT UPDATES
# ═══════════════════════════════════════════

func update_stat_display() -> void:
	if _hp_label:
		_hp_label.text = str(max(current_hp, 0))
		if current_hp < card_data.hp:
			_hp_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
		else:
			_hp_label.add_theme_color_override("font_color", Color.WHITE)
	if _atk_label:
		var display_atk = current_atk + temp_atk_buff
		_atk_label.text = str(display_atk)
		if display_atk > card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.ATK_BUFFED)
		elif display_atk < card_data.atk:
			_atk_label.add_theme_color_override("font_color", GameTheme.HP_DAMAGED)
		else:
			_atk_label.add_theme_color_override("font_color", Color.WHITE)


func update_floop_display() -> void:
	if _floop_indicator:
		if will_floop:
			_floop_indicator.text = "FLOOP"
			_floop_indicator.add_theme_color_override("font_color", GameTheme.FLOOP_BLUE)
			_floop_indicator.visible = true
		elif is_on_battlefield and has_floop() and not is_opponent:
			_floop_indicator.text = "click: floop"
			_floop_indicator.visible = true
			_floop_indicator.add_theme_color_override("font_color", Color(0.6, 0.5, 0.3, 0.7))
		else:
			_floop_indicator.visible = false
	if will_floop:
		_set_border_color(GameTheme.FLOOP_BLUE)
		if _art_rect:
			_art_rect.modulate = Color(0.6, 0.7, 1.0, 0.9)
	elif is_on_battlefield and has_floop() and not is_opponent:
		_set_border_color(Color(0.5, 0.4, 0.2, 0.6))
		if _art_rect:
			_art_rect.modulate = Color.WHITE
	else:
		_set_border_color(_get_default_frame_tint())
		if _art_rect:
			_art_rect.modulate = Color.WHITE


func toggle_floop() -> void:
	if not has_floop():
		return
	will_floop = not will_floop
	update_floop_display()


# ═══════════════════════════════════════════
#  DAMAGE
# ═══════════════════════════════════════════

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


# ═══════════════════════════════════════════
#  HAND POSITIONING + HOVER
# ═══════════════════════════════════════════

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
	_set_border_color(GameTheme.GILT_BRIGHT)
	if not is_on_battlefield:
		z_index = 10
		pivot_offset = Vector2(size.x * 0.5, size.y)
		scale = Vector2(1.15, 1.15)


func _on_mouse_exited() -> void:
	if _is_being_dragged or _is_playing:
		return
	_is_hovered = false
	if is_on_battlefield and will_floop:
		_set_border_color(GameTheme.FLOOP_BLUE)
	elif is_on_battlefield and has_floop() and not is_opponent:
		_set_border_color(Color(0.5, 0.4, 0.2, 0.6))
	else:
		_set_border_color(_get_default_frame_tint())
	if not is_on_battlefield:
		z_index = 0
		scale = Vector2.ONE
		pivot_offset = Vector2.ZERO


func _get_default_frame_tint() -> Color:
	return _default_border_color


func _set_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


# ═══════════════════════════════════════════
#  DRAG TO PLAY
# ═══════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_on_battlefield and not is_opponent and has_floop():
					floop_clicked.emit()
				else:
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
		scale = Vector2.ONE
		rotation = 0.0
		if get_parent() is Container:
			get_parent().queue_sort()


func fly_to_play_area(target_pos: Vector2) -> void:
	_is_playing = true
	global_position = target_pos
	rotation = 0.0
	scale = Vector2.ONE
	_is_playing = false
