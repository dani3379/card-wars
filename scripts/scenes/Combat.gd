extends Node3D
## Combat.gd — single-fight combat. Reads enemy composition from RunState,
## resolves fight, applies relics + keywords + lane effects, returns to map
## on victory or to game-over on defeat.
##
## This is the spiritual successor to the old PlayArea.gd, but slimmer:
## the meta-game state lives in RunState, not here.

const CARD_SCENE = preload("res://scenes/card.tscn")
const MAP_SCENE = "res://scenes/map.tscn"
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"

@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun

# ── Combat state ──
enum Phase { PLAYER_TURN, ENEMY_TURN, COMBAT, GAME_OVER }
var phase := Phase.PLAYER_TURN
var turn_number := 0

# ── Hero stats — player pulled from RunState, enemy generated per-fight ──
var player_hp: int
var player_max_hp: int
var player_mana: int = 0
var player_max_mana: int = 0
var enemy_hp: int
var enemy_max_hp: int
var enemy_mana: int = 0

# ── Decks for this fight ──
var _player_draw_pile: Array[String] = []
var _player_discard_pile: Array[String] = []
var _enemy_deck: Array[String] = []

# ── Hand and field ──
var _hand: Array[Node3D] = []
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]
const MAX_HAND_SIZE := 8
const HAND_CENTER := Vector3(0.0, 0.06, 2.2)
const HAND_CARD_SPACING := 0.46
const HAND_CARD_TILT_X := -0.35
const LANE_X := [-1.35, -0.45, 0.45, 1.35]
const PLAYER_ZONE_Z := 0.6
const ENEMY_ZONE_Z := -0.6

# ── Camera ──
var _cam_pivot := Vector3(0, 0, 0.3)
var _cam_distance := 4.2
var _cam_angle_x := -45.0
var _cam_angle_y := 0.0

# ── Relic-related per-turn state ──
var _vampires_fang_used_this_turn: bool = false
var _phoenix_heart_consumed: bool = false

# ── HUD ──
var _phase_label: Label3D
var _player_hp_label: Label3D
var _enemy_hp_label: Label3D
var _mana_label: Label3D
var _turn_label: Label3D
var _info_label: Label3D
var _floor_label: Label3D
var _end_turn_btn: Button
var _relic_panel: HBoxContainer

# ── Game feel ──
var _shake_amount: float = 0.0
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect


func _ready() -> void:
	get_viewport().physics_object_picking = true
	_setup_fight_state()
	_build_lane_labels()
	_build_hud()
	_build_end_turn_button()
	_build_flash_layer()
	_build_relic_display()
	_init_decks()
	_apply_combat_start_relics()
	_start_player_turn()
	_update_camera_transform()


func _setup_fight_state() -> void:
	player_max_hp = RunState.hero_max_hp
	player_hp = RunState.hero_hp

	# Build enemy based on floor / node type
	var node_type = RunState.node_type_for_floor(RunState.current_floor)
	var floor_num = RunState.current_floor

	match node_type:
		"combat":
			enemy_max_hp = 18 + floor_num * 2
			_build_enemy_deck_normal(floor_num)
		"elite":
			enemy_max_hp = 25 + floor_num * 2
			_build_enemy_deck_elite(floor_num)
		"boss":
			enemy_max_hp = 60
			_build_enemy_deck_boss()
	enemy_hp = enemy_max_hp


func _build_enemy_deck_normal(floor_num: int) -> void:
	# Mostly tier 1, some tier 2 starting around floor 3
	for i in range(8):
		var tier = 1 if (floor_num < 3 or randi() % 3 != 0) else 2
		_enemy_deck.append(CardDB.random_enemy_card_at_tier(tier))
	_enemy_deck.shuffle()


func _build_enemy_deck_elite(floor_num: int) -> void:
	# Heavier card pool
	for i in range(10):
		var tier = 2 if randi() % 3 != 0 else 3
		var id = CardDB.random_enemy_card_at_tier(tier)
		if id == "":
			id = CardDB.random_enemy_card_at_tier(2)
		_enemy_deck.append(id)
	_enemy_deck.shuffle()


func _build_enemy_deck_boss() -> void:
	# Boss has its signature card plus a strong support pool
	_enemy_deck = ["the_first_flame"]
	for i in range(10):
		_enemy_deck.append(CardDB.random_enemy_card_at_tier(2))
	# Don't shuffle the_first_flame to bottom — let it appear naturally
	_enemy_deck.shuffle()


func _init_decks() -> void:
	_player_draw_pile.clear()
	_player_discard_pile.clear()
	for id in RunState.deck:
		_player_draw_pile.append(id)
	_player_draw_pile.shuffle()


# ── Relics ──
func _has_relic(id: String) -> bool:
	return RunState.has_relic(id)


func _apply_combat_start_relics() -> void:
	# These adjust max HP / max mana before the fight begins.
	if _has_relic("meadow_crown"):
		var mc := RelicDB.get_relic("meadow_crown")
		player_max_hp += mc.value


func _start_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	turn_number += 1
	_vampires_fang_used_this_turn = false

	# Mana baseline 4 + 1 per turn up to 10
	player_max_mana = mini(turn_number + 3, 10)
	# Chronograph: +1 max mana
	if _has_relic("chronograph"):
		player_max_mana += 1
	# Ash Crown: +1 mana on the first turn of every fight
	if _has_relic("ash_crown") and turn_number == 1:
		player_max_mana += 1

	player_mana = player_max_mana

	# Reset all field cards' attack flags
	for c in _player_field:
		if c != null:
			c.has_attacked_this_turn = false
			c.summoned_this_turn = false

	# Bloodstone: heal on turn start
	if _has_relic("bloodstone"):
		var bs := RelicDB.get_relic("bloodstone")
		player_hp = mini(player_hp + bs.value, player_max_hp)

	# Witch's Grimoire: +1 draw per turn
	var draw_count = 4 if turn_number == 1 else 1
	if _has_relic("witchs_grimoire"):
		draw_count += 1
	for i in draw_count:
		if _hand.size() < MAX_HAND_SIZE and _player_draw_pile.size() > 0:
			_draw_card(_player_draw_pile.pop_front())
		elif _player_draw_pile.is_empty() and not _player_discard_pile.is_empty():
			# Reshuffle discard into draw pile
			_player_draw_pile = _player_discard_pile.duplicate()
			_player_draw_pile.shuffle()
			_player_discard_pile.clear()
			if _hand.size() < MAX_HAND_SIZE:
				_draw_card(_player_draw_pile.pop_front())

	_end_turn_btn.disabled = false
	_update_hud()


func _start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	enemy_mana = mini(turn_number + 3, 10)
	_end_turn_btn.disabled = true
	_update_hud()
	# Reset enemy attack flags
	for c in _enemy_field:
		if c != null:
			c.has_attacked_this_turn = false
			c.summoned_this_turn = false
	get_tree().create_timer(0.6).timeout.connect(_enemy_ai)


func _enemy_ai() -> void:
	if phase != Phase.ENEMY_TURN: return
	for lane_idx in range(4):
		if _enemy_field[lane_idx] != null: continue
		if _enemy_deck.is_empty(): break
		var card_id = _enemy_deck.pop_front()
		var data = CardDB.get_card_data(card_id)
		if data.is_empty(): continue
		if data.cost <= enemy_mana:
			enemy_mana -= data.cost
			_place_lane_card(card_id, lane_idx, true)
			_resolve_onplay(card_id, lane_idx, true)
	_update_hud()
	get_tree().create_timer(0.6).timeout.connect(_do_combat)


# ── Combat resolution ──
func _do_combat() -> void:
	phase = Phase.COMBAT
	_update_hud()
	var any_kill := false
	var hero_damage_to_player := 0
	var hero_damage_to_enemy := 0

	for lane_idx in range(4):
		var p = _player_field[lane_idx]
		var e = _enemy_field[lane_idx]
		var lane = RunState.LANES[lane_idx]

		if p != null and e != null:
			# Both cards engage
			var p_atk = _effective_attack(p, lane_idx, false)
			var e_atk = _effective_attack(e, lane_idx, true)
			var damage_to_e = _apply_lane_damage(p_atk, lane, true)
			var damage_to_p = _apply_lane_damage(e_atk, lane, false)
			e.take_damage(damage_to_e)
			p.take_damage(damage_to_p)
			# Lifesteal
			if p.has_keyword("lifesteal"):
				player_hp = mini(player_hp + damage_to_e, player_max_hp)
			if e.has_keyword("lifesteal"):
				enemy_hp = mini(enemy_hp + damage_to_p, enemy_max_hp)
			screen_shake(0.3)
			# Frenzy check + kill check
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
			# Hits enemy hero
			var atk = _effective_attack(p, lane_idx, false)
			enemy_hp -= atk
			hero_damage_to_enemy += atk
			screen_shake(0.5)
			if p.has_keyword("lifesteal"):
				player_hp = mini(player_hp + atk, player_max_hp)

		elif e != null:
			# Hits player hero, with Void lane doubling
			var atk = _effective_attack(e, lane_idx, true)
			if lane.id == "void":
				atk *= 2
			player_hp -= atk
			hero_damage_to_player += atk
			screen_shake(0.8)
			screen_flash(Color(0.7, 0.05, 0.05, 0.45), 0.35)
			if e.has_keyword("lifesteal"):
				enemy_hp = mini(enemy_hp + atk, enemy_max_hp)
			_on_hero_damaged(atk)

	if any_kill or hero_damage_to_player > 0:
		await freeze_frame(0.06)

	# Grove healing — after all combat, surviving cards in Grove heal 1
	for lane_idx in range(4):
		if RunState.LANES[lane_idx].id == "grove":
			var c = _player_field[lane_idx]
			if c != null and c.current_hp < c.card_data.hp:
				c.current_hp += 1
				c.update_stat_display()

	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		get_tree().create_timer(0.5).timeout.connect(_start_player_turn)


func _effective_attack(card: Node3D, lane_idx: int, is_enemy: bool) -> int:
	var atk = card.current_atk
	# Forge lane: +1 ATK for owner's cards
	if not is_enemy and RunState.LANES[lane_idx].id == "forge":
		atk += 1
	# Forge Banner relic: +1 to lane-0 cards
	if not is_enemy and _has_relic("forge_banner") and lane_idx == 0:
		atk += 1
	# Burning Brand relic: +1 to Charge cards
	if not is_enemy and _has_relic("burning_brand") and card.has_keyword("charge"):
		atk += 1
	return atk


func _apply_lane_damage(amount: int, lane: Dictionary, _to_player_card: bool) -> int:
	# Tide lane: -1 damage taken (minimum 1)
	if lane.id == "tide":
		return maxi(1, amount - 1)
	return amount


func _resolve_onplay(card_id: String, lane_idx: int, is_enemy: bool) -> void:
	var data = CardDB.get_card_data(card_id)
	if data.is_empty(): return
	if not data.has("keywords"): return
	for kw in data.keywords:
		match kw:
			"onplay_draw":
				if not is_enemy and _hand.size() < MAX_HAND_SIZE and _player_draw_pile.size() > 0:
					_draw_card(_player_draw_pile.pop_front())
			"onplay_smite":
				if is_enemy:
					player_hp -= 2
					_on_hero_damaged(2)
				else:
					enemy_hp -= 2
				_update_hud()


func _resolve_deathrattle(card: Node3D, lane_idx: int, was_enemy: bool) -> void:
	for kw in card.card_data.keywords:
		match kw:
			"deathrattle_smite":
				# Damage opposing card if any
				var target = _enemy_field[lane_idx] if not was_enemy else _player_field[lane_idx]
				if target != null:
					target.take_damage(2)
			"deathrattle_burn":
				if was_enemy:
					player_hp -= 1
					_on_hero_damaged(1)
				else:
					enemy_hp -= 1


func _on_card_killed(_was_player_killed: bool) -> void:
	# Vampire's Fang: heal 1 on first kill per turn
	if _has_relic("vampires_fang") and not _vampires_fang_used_this_turn:
		_vampires_fang_used_this_turn = true
		player_hp = mini(player_hp + 1, player_max_hp)


func _on_hero_damaged(_amount: int) -> void:
	# Phoenix Heart: revive on lethal once per run
	if _has_relic("phoenix_heart") and not _phoenix_heart_consumed and player_hp <= 0:
		_phoenix_heart_consumed = true
		player_hp = 1
	# Thorned Pendant: 1 dmg to random enemy card
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
		_phase_label.modulate = Color(0.9, 0.2, 0.2)
		# Persist current HP for run-end screen, then transition
		RunState.hero_hp = 0
		get_tree().create_timer(1.5).timeout.connect(func():
			RunState.end_run(false)
			get_tree().change_scene_to_file(GAMEOVER_SCENE)
		)
	elif enemy_hp <= 0:
		phase = Phase.GAME_OVER
		_phase_label.text = "VICTORY!"
		_phase_label.modulate = Color(0.2, 0.9, 0.3)
		# Save current HP back to RunState
		RunState.hero_hp = max(player_hp, 1)
		# Was this the boss?
		if RunState.node_type_for_floor(RunState.current_floor) == "boss":
			get_tree().create_timer(2.0).timeout.connect(func():
				RunState.end_run(true)
				get_tree().change_scene_to_file(GAMEOVER_SCENE)
			)
		else:
			# Reward, then back to map
			get_tree().create_timer(1.2).timeout.connect(func():
				get_tree().change_scene_to_file(REWARD_SCENE)
			)


# ── Card placement ──
func _place_lane_card(card_id: String, lane_idx: int, is_opponent: bool) -> void:
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.is_opponent = is_opponent
	card.is_on_battlefield = true
	card.card_data = CardDB.get_card_data(card_id)
	card.summoned_this_turn = true
	card.current_lane = lane_idx
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
		if _player_field[i] == card: _player_field[i] = null
		if _enemy_field[i] == card: _enemy_field[i] = null


# ── Hand ──
func _draw_card(card_id: String) -> void:
	if _hand.size() >= MAX_HAND_SIZE: return
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.card_data = CardDB.get_card_data(card_id)
	add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))
	_arrange_hand()


func _arrange_hand() -> void:
	var n = _hand.size()
	if n == 0: return
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
	if phase != Phase.PLAYER_TURN: return
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
	card.summoned_this_turn = true
	card.current_lane = lane_idx
	var play_pos = Vector3(LANE_X[lane_idx], 0.01, PLAYER_ZONE_Z)
	card.fly_to_play_area(play_pos)
	card.destroyed.connect(_on_card_destroyed.bind(card))
	_arrange_hand()
	_resolve_onplay(card.card_id, lane_idx, false)
	_update_hud()


func _nearest_lane_index(world_pos: Vector3) -> int:
	var best_idx := 0
	var best_dist := INF
	for i in range(4):
		var d = abs(world_pos.x - LANE_X[i])
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


# ── HUD ──
func _build_lane_labels() -> void:
	# A small label above each lane showing its identity
	for i in range(4):
		var lane = RunState.LANES[i]
		var lbl = Label3D.new()
		lbl.text = "%s %s" % [lane.icon, lane.name]
		lbl.font_size = 28
		lbl.pixel_size = 0.001
		lbl.position = Vector3(LANE_X[i], 0.01, 1.55)
		lbl.rotation = Vector3(-PI/2, 0, 0)
		lbl.modulate = lane.color
		lbl.outline_modulate = Color.BLACK
		lbl.outline_size = 6
		add_child(lbl)


func _build_hud() -> void:
	_phase_label = _make_hud_label(Vector3(0, 2.6, -2.5), "YOUR TURN", 44, Color(1, 0.9, 0.4))
	_floor_label = _make_hud_label(Vector3(0, 3.0, -2.5),
		"Floor %d / %d" % [RunState.current_floor, RunState.FLOOR_COUNT], 26,
		Color(0.85, 0.85, 0.95))
	_player_hp_label = _make_hud_label(Vector3(-1.7, 0.15, 2.6),
		"♥ 25/25", 36, Color(0.9, 0.3, 0.3))
	_enemy_hp_label = _make_hud_label(Vector3(0, 2.5, -2.5),
		"Enemy ♥ %d/%d" % [enemy_hp, enemy_max_hp], 30, Color(0.9, 0.4, 0.4))
	_mana_label = _make_hud_label(Vector3(0, 0.15, 2.6), "◆ 5/5", 36, Color(0.4, 0.65, 1.0))
	_turn_label = _make_hud_label(Vector3(1.7, 0.15, 2.6), "Turn 1", 26, Color(0.6, 0.6, 0.6))
	_info_label = _make_hud_label(Vector3(0, 1.5, 0), "", 40, Color(1, 0.6, 0.3))


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


func _build_end_turn_button() -> void:
	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "END TURN  [E]"
	_end_turn_btn.position = Vector2(20, 20)
	_end_turn_btn.custom_minimum_size = Vector2(140, 38)
	_end_turn_btn.pressed.connect(_on_end_turn)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.42, 0.18, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_end_turn_btn.add_theme_stylebox_override("normal", style)
	_end_turn_btn.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(_end_turn_btn)


func _build_relic_display() -> void:
	# Top-right strip showing icons for all owned relics
	var layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_relic_panel = HBoxContainer.new()
	_relic_panel.position = Vector2(20, 70)
	_relic_panel.add_theme_constant_override("separation", 8)
	layer.add_child(_relic_panel)
	_refresh_relic_display()


func _refresh_relic_display() -> void:
	for child in _relic_panel.get_children():
		child.queue_free()
	for relic_id in RunState.relics:
		var relic = RelicDB.get_relic(relic_id)
		if relic.is_empty(): continue
		var lbl = Label.new()
		lbl.text = "[%s]" % relic.name
		lbl.tooltip_text = relic.desc
		lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		lbl.add_theme_font_size_override("font_size", 14)
		_relic_panel.add_child(lbl)


func _update_hud() -> void:
	_player_hp_label.text = "♥ %d/%d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "Enemy ♥ %d/%d" % [enemy_hp, enemy_max_hp]
	_mana_label.text = "◆ %d/%d" % [player_mana, player_max_mana]
	_turn_label.text = "Turn %d" % turn_number
	match phase:
		Phase.PLAYER_TURN: _phase_label.text = "YOUR TURN"; _phase_label.modulate = Color(1, 0.9, 0.4)
		Phase.ENEMY_TURN: _phase_label.text = "ENEMY TURN"; _phase_label.modulate = Color(0.9, 0.4, 0.4)
		Phase.COMBAT: _phase_label.text = "COMBAT"; _phase_label.modulate = Color(1, 0.5, 0.2)
		Phase.GAME_OVER: pass


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN: return
	_start_enemy_turn()


# ── Game-feel ──
func _build_flash_layer() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 5
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1,1,1,0)
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
	_info_label.modulate = Color(1, 0.6, 0.3)
	get_tree().create_timer(1.5).timeout.connect(func(): _info_label.text = "")


# ── Camera ──
func _process(delta: float) -> void:
	_update_camera_transform()
	if _shake_amount > 0.001:
		var jitter = Vector3(randf()-0.5, randf()-0.5, randf()-0.5) * _shake_amount * 0.06
		camera.position += jitter
		_shake_amount = lerp(_shake_amount, 0.0, clampf(delta * 7.0, 0, 1))


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E or event.keycode == KEY_ENTER:
			_on_end_turn()
