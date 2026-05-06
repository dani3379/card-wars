extends Control
## Combat.gd — single-fight combat, now fully 2D.
## Reads enemy composition from RunState, resolves fight, returns to map
## on victory or to game-over on defeat.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"

# -- Combat state --
enum Phase { PLAYER_TURN, ENEMY_TURN, COMBAT, GAME_OVER }
var phase := Phase.PLAYER_TURN
var turn_number := 0

# -- Mana / draw --
const BASE_MAX_MANA: int = 3
const HAND_DRAW_PER_TURN: int = 5

# -- Hero stats --
var player_hp: int
var player_max_hp: int
var player_mana: int = 0
var player_max_mana: int = 0
var enemy_hp: int
var enemy_max_hp: int
var enemy_mana: int = 0

# -- Decks --
var _player_draw_pile: Array[String] = []
var _player_discard_pile: Array[String] = []
var _enemy_deck: Array[String] = []

# -- Hand and field --
var _hand: Array[Control] = []
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]
const MAX_HAND_SIZE := 8

# -- Board UI nodes --
var _board_bg: ColorRect
var _lane_panels: Array[PanelContainer] = []
var _player_slots: Array[Control] = []
var _enemy_slots: Array[Control] = []
var _hand_container: HBoxContainer
var _midline: ColorRect

# -- HUD --
var _hud_layer: CanvasLayer
var _phase_label: Label
var _player_hp_label: Label
var _enemy_hp_label: Label
var _mana_label: Label
var _turn_label: Label
var _info_label: Label
var _floor_label: Label
var _end_turn_btn: Button
var _relic_panel: HBoxContainer

# -- Game feel --
var _shake_amount: float = 0.0
var _shake_layer: CanvasLayer
var _shake_container: Control
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect

# -- Relic state --
var _vampires_fang_used_this_turn: bool = false

# -- Colors --
const PARCHMENT_BG := Color(0.10, 0.075, 0.060, 0.92)
const PARCHMENT_BORDER := Color(0.55, 0.40, 0.18, 1.0)
const GILT := Color(0.78, 0.62, 0.28, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const BOARD_BG := Color(0.06, 0.05, 0.04, 1.0)
const LANE_BORDER := Color(0.30, 0.22, 0.12, 0.8)


func _ready() -> void:
	_setup_fight_state()
	_build_board()
	_build_hud()
	_build_flash_layer()
	_init_decks()
	_apply_combat_start_relics()
	_start_player_turn()


func _setup_fight_state() -> void:
	player_max_hp = RunState.hero_max_hp
	player_hp = RunState.hero_hp
	var node_type = RunState.node_type_for_floor(RunState.current_floor)
	var floor_num = RunState.current_floor
	match node_type:
		"combat":
			enemy_max_hp = 10 + floor_num * 2
			_build_enemy_deck_normal(floor_num)
		"elite":
			enemy_max_hp = 16 + floor_num * 2
			_build_enemy_deck_elite(floor_num)
		"boss":
			enemy_max_hp = 35
			_build_enemy_deck_boss()
	enemy_hp = enemy_max_hp


func _build_enemy_deck_normal(floor_num: int) -> void:
	for i in range(8):
		var tier = 1 if (floor_num < 3 or randi() % 3 != 0) else 2
		_enemy_deck.append(CardDB.random_enemy_card_at_tier(tier))
	_enemy_deck.shuffle()


func _build_enemy_deck_elite(floor_num: int) -> void:
	for i in range(10):
		var tier = 2 if randi() % 3 != 0 else 3
		var id = CardDB.random_enemy_card_at_tier(tier)
		if id == "":
			id = CardDB.random_enemy_card_at_tier(2)
		_enemy_deck.append(id)
	_enemy_deck.shuffle()


func _build_enemy_deck_boss() -> void:
	_enemy_deck = ["the_first_flame"]
	for i in range(10):
		_enemy_deck.append(CardDB.random_enemy_card_at_tier(2))
	_enemy_deck.shuffle()


func _init_decks() -> void:
	_player_draw_pile.clear()
	_player_discard_pile.clear()
	for id in RunState.deck:
		_player_draw_pile.append(id)
	_player_draw_pile.shuffle()


# =====================================================================
#  BOARD LAYOUT — 2D grid with 4 lanes, enemy row on top, player on bottom
# =====================================================================

func _build_board() -> void:
	# Shake container wraps everything so screen shake moves the whole scene
	_shake_layer = CanvasLayer.new()
	_shake_layer.layer = 0
	add_child(_shake_layer)
	_shake_container = Control.new()
	_shake_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shake_layer.add_child(_shake_container)

	# Background
	_board_bg = ColorRect.new()
	_board_bg.color = BOARD_BG
	_board_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shake_container.add_child(_board_bg)

	# Main vertical layout: enemy row | midline | player row | hand
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.anchor_top = 0.08
	main_vbox.anchor_bottom = 1.0
	main_vbox.anchor_left = 0.1
	main_vbox.anchor_right = 0.9
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shake_container.add_child(main_vbox)

	# Enemy label
	var enemy_label := Label.new()
	enemy_label.text = "— ENEMY SIDE —"
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_label.add_theme_font_size_override("font_size", 12)
	enemy_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.6))
	enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(enemy_label)

	# Enemy row
	var enemy_row := HBoxContainer.new()
	enemy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_row.add_theme_constant_override("separation", 8)
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(enemy_row)

	# Midline separator
	_midline = ColorRect.new()
	_midline.custom_minimum_size = Vector2(0, 3)
	_midline.color = GILT
	_midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_midline)

	# Player label
	var player_label := Label.new()
	player_label.text = "— YOUR SIDE —"
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.add_theme_font_size_override("font_size", 12)
	player_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.4, 0.6))
	player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(player_label)

	# Player row
	var player_row := HBoxContainer.new()
	player_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_row.add_theme_constant_override("separation", 8)
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	player_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(player_row)

	# Build 4 lane columns (enemy slot + player slot)
	for i in range(4):
		# Enemy slot
		var e_slot := _make_lane_slot(true, i)
		enemy_row.add_child(e_slot)
		_enemy_slots.append(e_slot)
		# Player slot
		var p_slot := _make_lane_slot(false, i)
		player_row.add_child(p_slot)
		_player_slots.append(p_slot)

	# Hand area at the very bottom
	_hand_container = HBoxContainer.new()
	_hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_container.add_theme_constant_override("separation", -20)
	_hand_container.custom_minimum_size = Vector2(0, 215)
	_hand_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_hand_container)


func _make_lane_slot(is_enemy: bool, lane_idx: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(150, 0)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.6)
	style.border_color = LANE_BORDER
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)

	# Lane number label
	var lbl := Label.new()
	lbl.text = "Lane %d" % (lane_idx + 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.35, 0.28, 0.4))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)

	return slot


# =====================================================================
#  HUD
# =====================================================================

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 12
	add_child(_hud_layer)

	# Top-center banner
	var top := _make_panel(Vector2(0.5, 0.0), Vector2(-160, 10), Vector2(320, 68))
	_hud_layer.add_child(top)
	_floor_label = _make_text_label("Floor %d / %d" %
		[RunState.current_floor, RunState.FLOOR_COUNT], 14, GILT)
	_floor_label.position = Vector2(0, 6)
	_floor_label.size = Vector2(320, 20)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_floor_label)
	_phase_label = _make_text_label("YOUR TURN", 24, IVORY)
	_phase_label.position = Vector2(0, 28)
	_phase_label.size = Vector2(320, 34)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_phase_label)

	# Enemy HP
	var enemy_panel := _make_panel(Vector2(0.5, 0.0), Vector2(-90, 84), Vector2(180, 32))
	_hud_layer.add_child(enemy_panel)
	_enemy_hp_label = _make_text_label("Enemy  %d / %d" % [enemy_hp, enemy_max_hp],
		15, Color(0.95, 0.55, 0.40))
	_enemy_hp_label.position = Vector2(0, 5)
	_enemy_hp_label.size = Vector2(180, 22)
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_panel.add_child(_enemy_hp_label)

	# Bottom-left: HP
	var hp_panel := _make_panel(Vector2(0.0, 1.0), Vector2(16, -72), Vector2(150, 56))
	_hud_layer.add_child(hp_panel)
	var hp_caption := _make_text_label("HEALTH", 10, GILT)
	hp_caption.position = Vector2(10, 4)
	hp_caption.size = Vector2(130, 14)
	hp_panel.add_child(hp_caption)
	_player_hp_label = _make_text_label("%d / %d" % [player_hp, player_max_hp],
		22, Color(0.95, 0.42, 0.42))
	_player_hp_label.position = Vector2(10, 20)
	_player_hp_label.size = Vector2(130, 30)
	_player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_panel.add_child(_player_hp_label)

	# Bottom-left: Mana
	var mana_panel := _make_panel(Vector2(0.0, 1.0), Vector2(176, -72), Vector2(150, 56))
	_hud_layer.add_child(mana_panel)
	var mana_caption := _make_text_label("MANA", 10, GILT)
	mana_caption.position = Vector2(10, 4)
	mana_caption.size = Vector2(130, 14)
	mana_panel.add_child(mana_caption)
	_mana_label = _make_text_label("%d / %d" % [player_mana, player_max_mana],
		22, Color(0.55, 0.78, 1.00))
	_mana_label.position = Vector2(10, 20)
	_mana_label.size = Vector2(130, 30)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_panel.add_child(_mana_label)

	# Turn counter
	var turn_panel := _make_panel(Vector2(1.0, 1.0), Vector2(-140, -72), Vector2(120, 30))
	_hud_layer.add_child(turn_panel)
	_turn_label = _make_text_label("Turn 1", 13, GILT)
	_turn_label.position = Vector2(0, 5)
	_turn_label.size = Vector2(120, 20)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_panel.add_child(_turn_label)

	# End turn button
	_build_end_turn_button()

	# Center info toast
	_info_label = _make_text_label("", 22, Color(1, 0.78, 0.40))
	_info_label.set_anchors_preset(Control.PRESET_CENTER)
	_info_label.position = Vector2(-200, -30)
	_info_label.size = Vector2(400, 60)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_info_label.add_theme_constant_override("outline_size", 6)
	_hud_layer.add_child(_info_label)

	# Relic strip
	_build_relic_display()


func _make_panel(anchor: Vector2, offset: Vector2, sz: Vector2) -> Panel:
	var panel := Panel.new()
	panel.anchor_left = anchor.x
	panel.anchor_right = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_bottom = anchor.y
	panel.offset_left = offset.x
	panel.offset_top = offset.y
	panel.offset_right = offset.x + sz.x
	panel.offset_bottom = offset.y + sz.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PARCHMENT_BG
	style.border_color = PARCHMENT_BORDER
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_text_label(text: String, sz: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _build_end_turn_button() -> void:
	var btn := Button.new()
	btn.text = "END TURN  [E]"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -170
	btn.offset_top = -42
	btn.offset_right = -16
	btn.offset_bottom = -10
	btn.pressed.connect(_on_end_turn)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.10, 0.05, 0.92)
	normal.border_color = GILT
	normal.border_width_top = 2
	normal.border_width_bottom = 2
	normal.border_width_left = 2
	normal.border_width_right = 2
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.18, 0.06, 0.98)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.06, 0.03, 0.98)
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.10, 0.07, 0.05, 0.55)
	disabled.border_color = Color(0.40, 0.30, 0.15, 0.55)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", IVORY)
	btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.78))
	btn.add_theme_color_override("font_disabled_color", Color(0.7, 0.65, 0.55, 0.6))
	btn.add_theme_font_size_override("font_size", 14)
	_end_turn_btn = btn
	_hud_layer.add_child(btn)


func _build_relic_display() -> void:
	_relic_panel = HBoxContainer.new()
	_relic_panel.anchor_left = 0.0
	_relic_panel.anchor_top = 0.0
	_relic_panel.offset_left = 16
	_relic_panel.offset_top = 16
	_relic_panel.offset_right = 400
	_relic_panel.offset_bottom = 42
	_relic_panel.add_theme_constant_override("separation", 6)
	_relic_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_relic_panel)
	_refresh_relic_display()


func _refresh_relic_display() -> void:
	for child in _relic_panel.get_children():
		child.queue_free()
	for relic_id in RunState.relics:
		var relic = RelicDB.get_relic(relic_id)
		if relic.is_empty():
			continue
		var chip := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.075, 0.060, 0.85)
		style.border_color = PARCHMENT_BORDER
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_width_left = 1
		style.border_width_right = 1
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", style)
		chip.tooltip_text = relic.desc
		var lbl := Label.new()
		lbl.text = relic.name
		lbl.add_theme_color_override("font_color", GILT)
		lbl.add_theme_font_size_override("font_size", 11)
		chip.add_child(lbl)
		_relic_panel.add_child(chip)


func _update_hud() -> void:
	_player_hp_label.text = "%d / %d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "Enemy  %d / %d" % [enemy_hp, enemy_max_hp]
	_mana_label.text = "%d / %d" % [player_mana, player_max_mana]
	_turn_label.text = "Turn %d" % turn_number
	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "YOUR TURN"
			_phase_label.add_theme_color_override("font_color", IVORY)
		Phase.ENEMY_TURN:
			_phase_label.text = "ENEMY TURN"
			_phase_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.40))
		Phase.COMBAT:
			_phase_label.text = "COMBAT"
			_phase_label.add_theme_color_override("font_color", Color(1.00, 0.60, 0.25))
		Phase.GAME_OVER:
			pass


# =====================================================================
#  RELICS
# =====================================================================

func _has_relic(id: String) -> bool:
	return RunState.has_relic(id)


func _apply_combat_start_relics() -> void:
	if _has_relic("meadow_crown"):
		var mc := RelicDB.get_relic("meadow_crown")
		player_max_hp += mc.value


# =====================================================================
#  TURN FLOW
# =====================================================================

func _start_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	turn_number += 1
	_vampires_fang_used_this_turn = false

	player_max_mana = BASE_MAX_MANA
	if _has_relic("chronograph"):
		player_max_mana += 1
	if _has_relic("ash_crown") and turn_number == 1:
		player_max_mana += 1
	player_mana = player_max_mana

	for c in _player_field:
		if c != null:
			c.has_attacked_this_turn = false
			c.summoned_this_turn = false

	if _has_relic("bloodstone"):
		var bs := RelicDB.get_relic("bloodstone")
		player_hp = mini(player_hp + bs.value, player_max_hp)

	var draw_count = HAND_DRAW_PER_TURN
	if _has_relic("witchs_grimoire"):
		draw_count += 1
	for i in draw_count:
		draw_one()

	_end_turn_btn.disabled = false
	_update_hud()


func draw_one() -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	if _player_draw_pile.is_empty():
		if _player_discard_pile.is_empty():
			return
		_player_draw_pile = _player_discard_pile.duplicate()
		_player_draw_pile.shuffle()
		_player_discard_pile.clear()
	if _player_draw_pile.is_empty():
		return
	_draw_card(_player_draw_pile.pop_front())


func _discard_hand() -> void:
	for card in _hand:
		_player_discard_pile.append(card.card_id)
		card.queue_free()
	_hand.clear()


func damage_player_hero(amount: int) -> void:
	player_hp -= amount
	_on_hero_damaged(amount)
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	enemy_hp -= amount
	_update_hud()


func get_opposing_card(lane_idx: int, was_enemy: bool) -> Control:
	return _player_field[lane_idx] if was_enemy else _enemy_field[lane_idx]


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	_discard_hand()
	_start_enemy_turn()


func _start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	enemy_mana = mini(BASE_MAX_MANA + (turn_number - 1) / 2, BASE_MAX_MANA + 3)
	_end_turn_btn.disabled = true
	_update_hud()
	for c in _enemy_field:
		if c != null:
			c.has_attacked_this_turn = false
			c.summoned_this_turn = false
	get_tree().create_timer(0.5).timeout.connect(_enemy_ai)


func _enemy_ai() -> void:
	if phase != Phase.ENEMY_TURN:
		return
	for lane_idx in range(4):
		if _enemy_field[lane_idx] != null:
			continue
		if _enemy_deck.is_empty():
			break
		var card_id = _enemy_deck.pop_front()
		var data = CardDB.get_card_data(card_id)
		if data.is_empty():
			continue
		if data.cost <= enemy_mana:
			enemy_mana -= data.cost
			_place_lane_card(card_id, lane_idx, true)
			_resolve_onplay(card_id, lane_idx, true)
	_update_hud()
	get_tree().create_timer(0.5).timeout.connect(_do_combat)


# =====================================================================
#  COMBAT RESOLUTION
# =====================================================================

func _do_combat() -> void:
	phase = Phase.COMBAT
	_update_hud()
	var any_kill := false
	var hero_damage_to_player := 0

	for lane_idx in range(4):
		var p = _player_field[lane_idx]
		var e = _enemy_field[lane_idx]

		if p != null and e != null:
			var p_atk = _effective_attack(p, lane_idx, false)
			var e_atk = _effective_attack(e, lane_idx, true)
			e.take_damage(p_atk)
			p.take_damage(e_atk)
			if p.has_keyword("lifesteal"):
				player_hp = mini(player_hp + p_atk, player_max_hp)
			if e.has_keyword("lifesteal"):
				enemy_hp = mini(enemy_hp + e_atk, enemy_max_hp)
			screen_shake(0.3)
			if e.current_hp <= 0:
				_resolve_deathrattle(e, lane_idx, true)
				_enemy_field[lane_idx] = null
				if p.has_keyword("frenzy") and p.current_hp > 0:
					p.current_atk += 1
					p.update_stat_display()
				_on_card_killed(false)
				any_kill = true
			if p.current_hp <= 0:
				_resolve_deathrattle(p, lane_idx, false)
				_player_field[lane_idx] = null
				if e.has_keyword("frenzy") and e.current_hp > 0:
					e.current_atk += 1
					e.update_stat_display()
				any_kill = true

		elif p != null:
			var atk = _effective_attack(p, lane_idx, false)
			enemy_hp -= atk
			screen_shake(0.5)
			if p.has_keyword("lifesteal"):
				player_hp = mini(player_hp + atk, player_max_hp)

		elif e != null:
			var atk = _effective_attack(e, lane_idx, true)
			player_hp -= atk
			hero_damage_to_player += atk
			screen_shake(0.8)
			screen_flash(Color(0.7, 0.05, 0.05, 0.45), 0.35)
			if e.has_keyword("lifesteal"):
				enemy_hp = mini(enemy_hp + atk, enemy_max_hp)
			_on_hero_damaged(atk)

	if any_kill or hero_damage_to_player > 0:
		await freeze_frame(0.06)

	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		get_tree().create_timer(0.4).timeout.connect(_start_player_turn)


func _effective_attack(card: Control, lane_idx: int, is_enemy: bool) -> int:
	var atk = card.current_atk
	if not is_enemy and _has_relic("forge_banner") and lane_idx == 0:
		atk += 1
	if not is_enemy and _has_relic("burning_brand") and card.has_keyword("charge"):
		atk += 1
	return atk


func _resolve_onplay(card_id: String, lane_idx: int, is_enemy: bool) -> void:
	KeywordEffects.dispatch_on_play(card_id, lane_idx, is_enemy, self)


func _resolve_deathrattle(card: Control, lane_idx: int, was_enemy: bool) -> void:
	KeywordEffects.dispatch_on_death(card, lane_idx, was_enemy, self)


func _on_card_killed(_was_player_killed: bool) -> void:
	if _has_relic("vampires_fang") and not _vampires_fang_used_this_turn:
		_vampires_fang_used_this_turn = true
		player_hp = mini(player_hp + 1, player_max_hp)


func _on_hero_damaged(_amount: int) -> void:
	if _has_relic("phoenix_heart") and not RunState.phoenix_heart_consumed and player_hp <= 0:
		RunState.phoenix_heart_consumed = true
		player_hp = 1
	if _has_relic("thorned_pendant"):
		var targets: Array = []
		for c in _enemy_field:
			if c != null:
				targets.append(c)
		if targets.size() > 0:
			targets[randi() % targets.size()].take_damage(1)


func _check_game_over() -> void:
	if player_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "DEFEAT"
		_phase_label.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
		RunState.hero_hp = 0
		get_tree().create_timer(1.5).timeout.connect(func():
			RunState.end_run(false)
			get_tree().change_scene_to_file(GAMEOVER_SCENE)
		)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "VICTORY!"
		_phase_label.add_theme_color_override("font_color", Color(0.30, 0.92, 0.40))
		RunState.hero_hp = max(player_hp, 1)
		if RunState.node_type_for_floor(RunState.current_floor) == "boss":
			get_tree().create_timer(2.0).timeout.connect(func():
				RunState.end_run(true)
				get_tree().change_scene_to_file(GAMEOVER_SCENE)
			)
		else:
			get_tree().create_timer(1.0).timeout.connect(func():
				get_tree().change_scene_to_file(REWARD_SCENE)
			)


# =====================================================================
#  CARD PLACEMENT
# =====================================================================

func _place_lane_card(card_id: String, lane_idx: int, is_opponent: bool) -> void:
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.is_opponent = is_opponent
	card.is_on_battlefield = true
	card.card_data = CardDB.get_card_data(card_id)
	card.summoned_this_turn = true
	card.current_lane = lane_idx

	if is_opponent:
		_enemy_field[lane_idx] = card
		# Clear the placeholder label and add card
		var slot = _enemy_slots[lane_idx]
		for child in slot.get_children():
			child.queue_free()
		slot.add_child(card)
	else:
		_player_field[lane_idx] = card
		var slot = _player_slots[lane_idx]
		for child in slot.get_children():
			child.queue_free()
		slot.add_child(card)

	card.destroyed.connect(_on_card_destroyed.bind(card))


func _on_card_destroyed(card: Control) -> void:
	for i in range(4):
		if _player_field[i] == card:
			_player_field[i] = null
			_restore_slot_label(_player_slots[i], i)
		if _enemy_field[i] == card:
			_enemy_field[i] = null
			_restore_slot_label(_enemy_slots[i], i)


func _restore_slot_label(slot: PanelContainer, lane_idx: int) -> void:
	# Re-add the faint lane label after a card is removed
	await get_tree().process_frame
	if slot.get_child_count() == 0:
		var lbl := Label.new()
		lbl.text = "Lane %d" % (lane_idx + 1)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.35, 0.28, 0.4))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(lbl)


# =====================================================================
#  HAND
# =====================================================================

func _draw_card(card_id: String) -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.card_data = CardDB.get_card_data(card_id)
	_hand_container.add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))


func _on_card_played(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	var cost = card.card_data.cost
	if player_mana < cost:
		_show_info("Not enough mana!")
		return
	# Find best lane based on card's screen position
	var lane_idx = _nearest_lane_index(card.global_position)
	if _player_field[lane_idx] != null:
		_show_info("Lane occupied!")
		return
	player_mana -= cost
	_hand.erase(card)
	_hand_container.remove_child(card)
	card.is_on_battlefield = true
	card.summoned_this_turn = true
	card.current_lane = lane_idx
	_place_card_in_slot(card, lane_idx)
	_resolve_onplay(card.card_id, lane_idx, false)
	_update_hud()


func _place_card_in_slot(card: Control, lane_idx: int) -> void:
	_player_field[lane_idx] = card
	var slot = _player_slots[lane_idx]
	for child in slot.get_children():
		child.queue_free()
	slot.add_child(card)
	card.destroyed.connect(_on_card_destroyed.bind(card))


func _nearest_lane_index(screen_pos: Vector2) -> int:
	var best_idx := 0
	var best_dist := INF
	for i in range(4):
		var slot_center = _player_slots[i].global_position + _player_slots[i].size * 0.5
		var d = abs(screen_pos.x - slot_center.x)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


# =====================================================================
#  GAME FEEL
# =====================================================================

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
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _show_info(msg: String) -> void:
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_property(_info_label, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): _info_label.text = "")


func _process(delta: float) -> void:
	if _shake_amount > 0.001 and _shake_container:
		var jitter = Vector2((randf() - 0.5) * _shake_amount * 12,
			(randf() - 0.5) * _shake_amount * 12)
		_shake_container.position = jitter
		_shake_amount = lerp(_shake_amount, 0.0, clampf(delta * 7.0, 0, 1))
	elif _shake_container:
		_shake_container.position = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E, KEY_ENTER:
				_on_end_turn()
