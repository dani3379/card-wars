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

# ── Mana / draw constants — STS-style: fixed pool refilled each turn ──
const BASE_MAX_MANA: int = 3
const HAND_DRAW_PER_TURN: int = 5

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
const HAND_CENTER := Vector3(0.0, 0.06, 1.95)
const HAND_CARD_SPACING := 0.46
const HAND_CARD_TILT_X := -0.32
const LANE_X := [-1.35, -0.45, 0.45, 1.35]
const PLAYER_ZONE_Z := 0.6
const ENEMY_ZONE_Z := -0.6

# ── Camera ──
var _cam_pivot := Vector3(0, 0, 0.3)
var _cam_distance := 5.4
var _cam_angle_x := -42.0
var _cam_angle_y := 0.0
# Drift + mouse-follow state. Read each frame in _process so the camera
# breathes a little instead of being a static viewport.
const CAMERA_DRIFT_AMPLITUDE_X := 0.06
const CAMERA_DRIFT_AMPLITUDE_Y := 0.04
const CAMERA_DRIFT_SPEED := 0.35
const CAMERA_MOUSE_FOLLOW_X := 0.22
const CAMERA_MOUSE_FOLLOW_Y := 0.12
const CAMERA_MOUSE_LERP := 4.0
var _cam_drift_t: float = 0.0
var _cam_mouse_offset: Vector3 = Vector3.ZERO

# ── Relic-related per-turn state ──
var _vampires_fang_used_this_turn: bool = false

# ── HUD (2D overlay so it's always on-screen, not Label3D in world space) ──
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

# ── Game feel ──
var _shake_amount: float = 0.0
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect


func _ready() -> void:
	get_viewport().physics_object_picking = true
	_setup_fight_state()
	_build_lane_labels()
	_build_atmosphere()
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

	# Mana fixed at BASE_MAX_MANA, refilled every turn (STS-style).
	player_max_mana = BASE_MAX_MANA
	# Chronograph: +1 max mana for the whole fight.
	if _has_relic("chronograph"):
		player_max_mana += 1
	# Ash Crown: +1 mana on the first turn of every fight.
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

	# Draw a fresh hand each turn. Witch's Grimoire: +1 draw per turn.
	var draw_count = HAND_DRAW_PER_TURN
	if _has_relic("witchs_grimoire"):
		draw_count += 1
	for i in draw_count:
		draw_one()

	_end_turn_btn.disabled = false
	_update_hud()


# Public helper used by KeywordEffects (onplay_draw) and turn-start logic.
func draw_one() -> void:
	if _hand.size() >= MAX_HAND_SIZE: return
	if _player_draw_pile.is_empty():
		if _player_discard_pile.is_empty():
			return
		_player_draw_pile = _player_discard_pile.duplicate()
		_player_draw_pile.shuffle()
		_player_discard_pile.clear()
	if _player_draw_pile.is_empty(): return
	_draw_card(_player_draw_pile.pop_front())


# Discard the entire hand into the discard pile and remove the visual cards.
func _discard_hand() -> void:
	for card in _hand:
		_player_discard_pile.append(card.card_id)
		card.queue_free()
	_hand.clear()


# Helpers exposed for KeywordEffects so it doesn't reach into private state.
func damage_player_hero(amount: int) -> void:
	player_hp -= amount
	_on_hero_damaged(amount)
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	enemy_hp -= amount
	_update_hud()


func get_opposing_card(lane_idx: int, was_enemy: bool) -> Node3D:
	return _player_field[lane_idx] if was_enemy else _enemy_field[lane_idx]


func _start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	# Enemy mana scales modestly with turn; matched roughly to player's
	# fixed pool but with light ramp to keep late-game pressure on.
	enemy_mana = mini(BASE_MAX_MANA + (turn_number - 1) / 2, BASE_MAX_MANA + 3)
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
	KeywordEffects.dispatch_on_play(card_id, lane_idx, is_enemy, self)


func _resolve_deathrattle(card: Node3D, lane_idx: int, was_enemy: bool) -> void:
	KeywordEffects.dispatch_on_death(card, lane_idx, was_enemy, self)


func _on_card_killed(_was_player_killed: bool) -> void:
	# Vampire's Fang: heal 1 on first kill per turn
	if _has_relic("vampires_fang") and not _vampires_fang_used_this_turn:
		_vampires_fang_used_this_turn = true
		player_hp = mini(player_hp + 1, player_max_hp)


func _on_hero_damaged(_amount: int) -> void:
	# Phoenix Heart: revive on lethal once per run.
	# Tracked on RunState so it persists across fights, not per-combat.
	if _has_relic("phoenix_heart") and not RunState.phoenix_heart_consumed and player_hp <= 0:
		RunState.phoenix_heart_consumed = true
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
# ── Atmosphere ──
# A small candle on the table edge with a real flickering point light, drifting
# embers, and dust motes lit by the candle. Pure procedural setup — no scene
# editing needed. Tweak the constants here for "feel".
const CANDLE_BASE_ENERGY := 1.4
const CANDLE_FLICKER_AMOUNT := 0.55
const CANDLE_POSITION := Vector3(-2.4, 0.45, 1.35)

var _candle_light: OmniLight3D
var _candle_flame: MeshInstance3D
var _candle_flicker_t: float = 0.0


func _build_atmosphere() -> void:
	_build_candle()
	_build_embers()
	_build_dust_motes()
	_build_back_glow()


func _build_candle() -> void:
	var stem = MeshInstance3D.new()
	var stem_mesh = CylinderMesh.new()
	stem_mesh.top_radius = 0.07
	stem_mesh.bottom_radius = 0.075
	stem_mesh.height = 0.32
	var stem_mat = StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.92, 0.86, 0.70)
	stem_mat.roughness = 0.85
	stem_mesh.material = stem_mat
	stem.mesh = stem_mesh
	stem.position = CANDLE_POSITION + Vector3(0, 0.16, 0)
	add_child(stem)

	# Flame: a small emissive cone-ish mesh.
	_candle_flame = MeshInstance3D.new()
	var flame_mesh = SphereMesh.new()
	flame_mesh.radius = 0.04
	flame_mesh.height = 0.13
	var flame_mat = StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.albedo_color = Color(1.0, 0.78, 0.32)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.65, 0.25)
	flame_mat.emission_energy_multiplier = 4.0
	flame_mesh.material = flame_mat
	_candle_flame.mesh = flame_mesh
	_candle_flame.position = CANDLE_POSITION + Vector3(0, 0.40, 0)
	add_child(_candle_flame)

	# Warm point light driving the scene's mood.
	_candle_light = OmniLight3D.new()
	_candle_light.light_color = Color(1.0, 0.65, 0.30)
	_candle_light.light_energy = CANDLE_BASE_ENERGY
	_candle_light.omni_range = 6.0
	_candle_light.shadow_enabled = true
	_candle_light.position = CANDLE_POSITION + Vector3(0, 0.40, 0)
	add_child(_candle_light)


func _build_embers() -> void:
	# Drifting embers rising from the candle.
	var p = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 0.55
	mat.gravity = Vector3(0, 0.4, 0)  # rise, not fall
	mat.scale_min = 0.4
	mat.scale_max = 1.2
	mat.color = Color(1.0, 0.55, 0.2, 1.0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.04
	p.process_material = mat
	var mesh = SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.024
	var ember_mat = StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.albedo_color = Color(1.0, 0.55, 0.2)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.45, 0.15)
	ember_mat.emission_energy_multiplier = 3.0
	mesh.material = ember_mat
	p.draw_pass_1 = mesh
	p.amount = 24
	p.lifetime = 2.4
	p.preprocess = 1.5
	p.position = CANDLE_POSITION + Vector3(0, 0.45, 0)
	add_child(p)


func _build_dust_motes() -> void:
	# Slow ambient dust drifting through the candle's light cone.
	var p = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0.2, -0.05, 0.1)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.12
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.5
	mat.scale_max = 1.6
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(3.0, 1.2, 2.5)
	mat.color = Color(0.9, 0.85, 0.7, 0.5)
	p.process_material = mat
	var mesh = SphereMesh.new()
	mesh.radius = 0.006
	mesh.height = 0.012
	var dust_mat = StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.95, 0.9, 0.78)
	dust_mat.roughness = 1.0
	mesh.material = dust_mat
	p.draw_pass_1 = mesh
	p.amount = 80
	p.lifetime = 6.0
	p.preprocess = 4.0
	p.position = Vector3(0, 1.0, 0)
	add_child(p)


func _build_back_glow() -> void:
	# Dim warm rim light from the back to push the table out of pure darkness.
	var rim = OmniLight3D.new()
	rim.light_color = Color(0.6, 0.4, 0.5)
	rim.light_energy = 0.6
	rim.omni_range = 8.0
	rim.position = Vector3(2.0, 1.5, -2.5)
	add_child(rim)


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
	# Single CanvasLayer hosts every HUD label + button + relic strip in 2D.
	# Positioned by anchors so the layout works at any window size.
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	# Top center: floor + phase
	_floor_label = _make_2d_label(
		"Floor %d / %d" % [RunState.current_floor, RunState.FLOOR_COUNT],
		22, Color(0.85, 0.85, 0.95))
	_floor_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_floor_label.offset_top = 12
	_floor_label.offset_bottom = 38
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_floor_label)

	_phase_label = _make_2d_label("YOUR TURN", 32, Color(1, 0.9, 0.4))
	_phase_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_phase_label.offset_top = 38
	_phase_label.offset_bottom = 78
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_phase_label)

	# Top center: enemy HP
	_enemy_hp_label = _make_2d_label(
		"Enemy ♥ %d/%d" % [enemy_hp, enemy_max_hp], 26, Color(0.95, 0.45, 0.45))
	_enemy_hp_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_enemy_hp_label.offset_top = 86
	_enemy_hp_label.offset_bottom = 120
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_enemy_hp_label)

	# Bottom-left: player HP
	_player_hp_label = _make_2d_label("♥ 25/25", 28, Color(0.95, 0.3, 0.3))
	_player_hp_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_player_hp_label.offset_left = 24
	_player_hp_label.offset_top = -64
	_player_hp_label.offset_bottom = -28
	_player_hp_label.offset_right = 320
	_hud_layer.add_child(_player_hp_label)

	# Bottom-center: mana
	_mana_label = _make_2d_label("◆ 3/3", 30, Color(0.45, 0.7, 1.0))
	_mana_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_mana_label.offset_top = -64
	_mana_label.offset_bottom = -28
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_mana_label)

	# Bottom-right: turn counter
	_turn_label = _make_2d_label("Turn 1", 22, Color(0.7, 0.7, 0.7))
	_turn_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_turn_label.offset_left = -200
	_turn_label.offset_right = -24
	_turn_label.offset_top = -56
	_turn_label.offset_bottom = -28
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_layer.add_child(_turn_label)

	# Center: transient info messages ("Not enough mana", etc.)
	_info_label = _make_2d_label("", 30, Color(1, 0.65, 0.3))
	_info_label.set_anchors_preset(Control.PRESET_CENTER)
	_info_label.offset_left = -300
	_info_label.offset_right = 300
	_info_label.offset_top = 60
	_info_label.offset_bottom = 110
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_layer.add_child(_info_label)


func _make_2d_label(text: String, size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _build_end_turn_button() -> void:
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "END TURN  [E]"
	_end_turn_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_end_turn_btn.offset_left = -200
	_end_turn_btn.offset_right = -24
	_end_turn_btn.offset_top = -130
	_end_turn_btn.offset_bottom = -80
	_end_turn_btn.pressed.connect(_on_end_turn)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.42, 0.18, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_end_turn_btn.add_theme_stylebox_override("normal", style)
	_end_turn_btn.add_theme_color_override("font_color", Color.WHITE)
	_end_turn_btn.add_theme_font_size_override("font_size", 18)
	_hud_layer.add_child(_end_turn_btn)


func _build_relic_display() -> void:
	# Top-left strip showing icons for all owned relics, just under the floor label.
	_relic_panel = HBoxContainer.new()
	_relic_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_relic_panel.offset_left = 24
	_relic_panel.offset_top = 24
	_relic_panel.add_theme_constant_override("separation", 8)
	_hud_layer.add_child(_relic_panel)
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
	_player_hp_label.text = "♥ %d / %d" % [player_hp, player_max_hp]
	_enemy_hp_label.text = "Enemy ♥ %d / %d" % [enemy_hp, enemy_max_hp]
	_mana_label.text = "◆ %d / %d" % [player_mana, player_max_mana]
	_turn_label.text = "Turn %d" % turn_number
	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "YOUR TURN"
			_phase_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		Phase.ENEMY_TURN:
			_phase_label.text = "ENEMY TURN"
			_phase_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45))
		Phase.COMBAT:
			_phase_label.text = "COMBAT"
			_phase_label.add_theme_color_override("font_color", Color(1, 0.55, 0.25))
		Phase.GAME_OVER:
			pass


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN: return
	# STS-style: discard the entire hand at end of turn.
	_discard_hand()
	_arrange_hand()
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
	_info_label.add_theme_color_override("font_color", Color(1, 0.65, 0.3))
	get_tree().create_timer(1.5).timeout.connect(func(): _info_label.text = "")


# ── Camera ──
func _process(delta: float) -> void:
	_cam_drift_t += delta * CAMERA_DRIFT_SPEED
	_update_mouse_offset(delta)
	_update_camera_transform()
	_update_candle_flicker(delta)
	if _shake_amount > 0.001:
		var jitter = Vector3(randf()-0.5, randf()-0.5, randf()-0.5) * _shake_amount * 0.06
		camera.position += jitter
		_shake_amount = lerp(_shake_amount, 0.0, clampf(delta * 7.0, 0, 1))


# Two layered noise sines + a small random kick = a candle that doesn't loop.
func _update_candle_flicker(delta: float) -> void:
	if _candle_light == null:
		return
	_candle_flicker_t += delta
	var n = sin(_candle_flicker_t * 11.3) * 0.5 + sin(_candle_flicker_t * 4.7 + 1.3) * 0.5
	n += (randf() - 0.5) * 0.4
	var energy = CANDLE_BASE_ENERGY + n * CANDLE_FLICKER_AMOUNT
	_candle_light.light_energy = max(0.4, energy)
	if _candle_flame != null:
		var s = 1.0 + n * 0.18
		_candle_flame.scale = Vector3(s, 1.0 + n * 0.25, s)


# Smoothly chase the mouse-driven camera offset so the scene parallaxes
# slightly with the cursor. Lerped so it never feels jittery.
func _update_mouse_offset(delta: float) -> void:
	var vp = get_viewport().get_visible_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var mp = get_viewport().get_mouse_position()
	# Normalise to -1..1 with the centre at 0.
	var nx = clampf((mp.x / vp.x) * 2.0 - 1.0, -1.0, 1.0)
	var ny = clampf((mp.y / vp.y) * 2.0 - 1.0, -1.0, 1.0)
	var target = Vector3(
		nx * CAMERA_MOUSE_FOLLOW_X,
		-ny * CAMERA_MOUSE_FOLLOW_Y,
		0.0,
	)
	_cam_mouse_offset = _cam_mouse_offset.lerp(target, clampf(delta * CAMERA_MOUSE_LERP, 0.0, 1.0))


func _update_camera_transform() -> void:
	var pitch_rad = deg_to_rad(_cam_angle_x)
	var yaw_rad = deg_to_rad(_cam_angle_y)
	var offset = Vector3(
		sin(yaw_rad) * cos(pitch_rad) * _cam_distance,
		-sin(pitch_rad) * _cam_distance,
		cos(yaw_rad) * cos(pitch_rad) * _cam_distance
	)
	# Subtle idle drift — independent of mouse — so the camera always breathes.
	var drift = Vector3(
		sin(_cam_drift_t * 0.7) * CAMERA_DRIFT_AMPLITUDE_X,
		cos(_cam_drift_t * 0.5) * CAMERA_DRIFT_AMPLITUDE_Y,
		0.0,
	)
	camera.position = _cam_pivot + offset + drift + _cam_mouse_offset
	camera.look_at(_cam_pivot + _cam_mouse_offset * 0.35, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E or event.keycode == KEY_ENTER:
			_on_end_turn()
