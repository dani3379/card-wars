extends Control
## Combat.gd — design-doc combat: simultaneous + Swift, floop, sacrifice, spells.
## Round flow: draw → play/sacrifice/floop → Swift phase → simultaneous →
## deaths → discard → enemy places → passives → new round.
## Round 1 is setup only (no combat phase).

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
const MAP_SCENE = "res://scenes/map.tscn"
const REWARD_SCENE = "res://scenes/reward.tscn"
const GAMEOVER_SCENE = "res://scenes/game_over.tscn"

enum Phase { PLAYER_TURN, RESOLVING, GAME_OVER }
var phase := Phase.PLAYER_TURN
var round_number := 0

const BASE_MAX_MANA: int = 3
const HAND_DRAW_PER_TURN: int = 5
const MAX_HAND_SIZE := 10

var player_hp: int
var player_max_hp: int
var player_mana: int = 0
var player_max_mana: int = 0
var enemy_hp: int
var enemy_max_hp: int

var _player_draw_pile: Array[String] = []
var _player_discard_pile: Array[String] = []
var _exhaust_pile: Array[String] = []
var _enemy_deck: Array[String] = []

var _hand: Array[Control] = []
var _player_field: Array = [null, null, null, null]
var _enemy_field: Array = [null, null, null, null]

var _sacrifice_used_this_turn: bool = false
var _sacrifice_mode: bool = false
var _targeting_spell: Control = null
var _targeting_data: Dictionary = {}
var _first_creature_played: bool = false
var _first_spell_this_turn: bool = false
var _cards_played_this_turn: int = 0
var _last_spell_played_this_turn: Dictionary = {}
var _bonus_mana_next_turn: int = 0
var _face_damage_taken_this_fight: int = 0
var _friendly_deaths_this_fight: int = 0
var _friendly_deaths_this_round: int = 0
var _last_dead_creature_id: String = ""
var _grave_pact_active: bool = false
var _soul_lantern_used_this_round: bool = false
var _starting_hp: int = 0

# Board UI
var _board_bg: ColorRect
var _player_slots: Array[Control] = []
var _enemy_slots: Array[Control] = []
var _hand_container: HBoxContainer
var _midline: ColorRect

# HUD
var _hud_layer: CanvasLayer
var _phase_label: Label
var _player_hp_label: Label
var _enemy_hp_label: Label
var _mana_label: Label
var _turn_label: Label
var _info_label: Label
var _floor_label: Label
var _end_turn_btn: Button
var _sacrifice_btn: Button
var _relic_panel: HBoxContainer

# Game feel
var _shake_amount: float = 0.0
var _shake_layer: CanvasLayer
var _shake_container: Control
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect

# Colors
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
	_start_round()


# =====================================================================
#  SETUP
# =====================================================================

func _setup_fight_state() -> void:
	player_max_hp = RunState.hero_max_hp
	player_hp = RunState.hero_hp
	_starting_hp = player_hp
	var act = RunState.get_act()
	var node_type = RunState.node_type_for_floor(RunState.current_floor)
	match node_type:
		"combat":
			enemy_max_hp = [12, 17, 21][act - 1] + randi() % 4
			_build_enemy_deck(act, false, false)
		"elite":
			enemy_max_hp = [18, 26, 30][act - 1] + randi() % 4
			_build_enemy_deck(act, true, false)
		"boss":
			enemy_max_hp = [25, 32, 40][act - 1]
			_build_enemy_deck(act, false, true)
	enemy_hp = enemy_max_hp


func _build_enemy_deck(act: int, is_elite: bool, is_boss: bool) -> void:
	var count = 8 if not is_elite and not is_boss else 12
	for i in range(count):
		_enemy_deck.append(CardDB.random_enemy_for_act(act))
	if is_boss:
		var boss_ids = ["e_warden_champ", "e_collector_champ", "e_devil_champ"]
		_enemy_deck.push_front(boss_ids[clampi(act - 1, 0, 2)])
	_enemy_deck.shuffle()


func _init_decks() -> void:
	_player_draw_pile.clear()
	_player_discard_pile.clear()
	for id in RunState.deck:
		_player_draw_pile.append(id)
	_player_draw_pile.shuffle()


# =====================================================================
#  ROUND FLOW
# =====================================================================

func _start_round() -> void:
	round_number += 1
	_sacrifice_used_this_turn = false
	_first_creature_played = false
	_first_spell_this_turn = false
	_cards_played_this_turn = 0
	_last_spell_played_this_turn = {}
	_friendly_deaths_this_round = 0
	_soul_lantern_used_this_round = false
	phase = Phase.PLAYER_TURN

	KeywordEffects.dispatch_start_of_round(self)

	# Mana
	player_max_mana = BASE_MAX_MANA + _bonus_mana_next_turn
	if _has_relic("battle_scars") and round_number == 1:
		player_max_mana += 1
	_bonus_mana_next_turn = 0
	player_mana = player_max_mana

	# Draw
	var draw_count = HAND_DRAW_PER_TURN
	if _has_relic("couriers_bag") and round_number == 1:
		draw_count += 1
	for i in draw_count:
		draw_one()

	_end_turn_btn.disabled = false
	_sacrifice_btn.visible = true
	_sacrifice_btn.disabled = _sacrifice_used_this_turn
	_update_hud()


func _on_end_turn() -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _targeting_spell != null:
		_cancel_targeting()
		return
	if _sacrifice_mode:
		_cancel_sacrifice()
		return
	_end_turn_btn.disabled = true
	_sacrifice_btn.visible = false
	phase = Phase.RESOLVING
	_update_hud()

	# Resolve floop abilities
	_resolve_floops()

	if round_number == 1:
		# Round 1: setup only, no combat
		_post_combat_sequence()
	else:
		get_tree().create_timer(0.3).timeout.connect(_do_combat)


func _resolve_floops() -> void:
	for lane_idx in range(4):
		var card = _player_field[lane_idx]
		if card != null and card.will_floop and card.has_floop():
			_resolve_floop_ability(card, lane_idx, false)
			card.will_floop = false
			card.has_attacked_this_turn = true
			card.update_floop_display()
		var e_card = _enemy_field[lane_idx]
		if e_card != null and e_card.has_floop() and randi() % 3 == 0:
			_resolve_floop_ability(e_card, lane_idx, true)


func _resolve_floop_ability(card: Control, lane_idx: int, is_enemy: bool) -> void:
	var floop_data = card.card_data.get("floop", {})
	var times = 1
	if not is_enemy and _has_relic("echo_staff"):
		times = 2
	for _i in times:
		match floop_data.get("type", ""):
			"damage_any":
				var targets: Array = []
				var field = _player_field if is_enemy else _enemy_field
				for c in field:
					if c != null:
						targets.append(c)
				if targets.size() > 0:
					targets[randi() % targets.size()].take_damage(floop_data.value)
			"summon_random":
				var empty_lanes: Array[int] = []
				var field = _enemy_field if is_enemy else _player_field
				for i in range(4):
					if field[i] == null:
						empty_lanes.append(i)
				if empty_lanes.size() > 0:
					var l = empty_lanes[randi() % empty_lanes.size()]
					summon_token(floop_data.atk, floop_data.hp, l, is_enemy)
			"kill_adjacent_summon":
				var field = _enemy_field if is_enemy else _player_field
				var adj: Array[int] = []
				if lane_idx > 0 and field[lane_idx - 1] != null:
					adj.append(lane_idx - 1)
				if lane_idx < 3 and field[lane_idx + 1] != null:
					adj.append(lane_idx + 1)
				if adj.size() > 0:
					var target_lane = adj[randi() % adj.size()]
					var victim = field[target_lane]
					if victim != null:
						victim.take_damage(999)
					summon_token(floop_data.atk, floop_data.hp, target_lane, is_enemy)
			"steal_atk":
				var opp = get_opposing_card(lane_idx, not is_enemy)
				if opp != null and opp.current_atk > 0:
					opp.current_atk = maxi(0, opp.current_atk - floop_data.get("value", 1))
					card.current_atk += floop_data.get("value", 1)
					opp.update_stat_display()
					card.update_stat_display()


# =====================================================================
#  COMBAT RESOLUTION
# =====================================================================

func _do_combat() -> void:
	_update_hud()

	# Snapshot which lanes are empty BEFORE combat (for face damage rules)
	var player_empty_at_start: Array[bool] = []
	var enemy_empty_at_start: Array[bool] = []
	for i in range(4):
		player_empty_at_start.append(_player_field[i] == null)
		enemy_empty_at_start.append(_enemy_field[i] == null)

	# SWIFT PHASE: swift creatures attack first
	for lane_idx in range(4):
		_resolve_swift_attack(lane_idx, false, enemy_empty_at_start)
		_resolve_swift_attack(lane_idx, true, player_empty_at_start)

	# SIMULTANEOUS PHASE: remaining creatures
	for lane_idx in range(4):
		var p = _player_field[lane_idx]
		var e = _enemy_field[lane_idx]

		if p != null and e != null:
			if p.has_attacked_this_turn or not p.can_attack():
				if not e.has_attacked_this_turn and e.can_attack():
					_creature_attacks_creature(e, p, lane_idx, true)
			elif e.has_attacked_this_turn or not e.can_attack():
				_creature_attacks_creature(p, e, lane_idx, false)
			else:
				_simultaneous_combat(p, e, lane_idx)

		elif p != null and not p.has_attacked_this_turn and p.can_attack():
			if enemy_empty_at_start[lane_idx]:
				_creature_hits_face(p, lane_idx, false)

		elif e != null and not e.has_attacked_this_turn and e.can_attack():
			if player_empty_at_start[lane_idx]:
				_creature_hits_face(e, lane_idx, true)

	# Process ranged attacks
	_resolve_ranged_attacks()

	# Berserker growth
	for lane_idx in range(4):
		for field in [_player_field, _enemy_field]:
			var c = field[lane_idx]
			if c != null and c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
				c.current_atk += 1
				c.update_stat_display()

	# Clean dead
	_cleanup_dead()

	await _short_pause(0.15)
	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		_post_combat_sequence()


func _resolve_swift_attack(lane_idx: int, is_enemy: bool, opponent_empty: Array[bool]) -> void:
	var attacker_field = _enemy_field if is_enemy else _player_field
	var defender_field = _player_field if is_enemy else _enemy_field
	var card = attacker_field[lane_idx]
	if card == null or not card.has_keyword("swift") or card.has_attacked_this_turn or not card.can_attack():
		return
	card.has_attacked_this_turn = true
	var opponent = defender_field[lane_idx]
	if opponent != null:
		var atk = _effective_attack(card, lane_idx, is_enemy)
		_apply_thorns(opponent, card, is_enemy)
		opponent.take_damage(atk)
		screen_shake(0.3)
		if opponent.current_hp <= 0 and card.has_keyword("piercing"):
			var excess = abs(opponent.current_hp)
			var bonus = 1 if (not is_enemy and _has_relic("piercing_crown")) else 0
			if is_enemy:
				damage_player_hero(excess + bonus)
			else:
				damage_enemy_hero(excess + bonus)
	elif opponent_empty[lane_idx]:
		_creature_hits_face(card, lane_idx, is_enemy)


func _simultaneous_combat(p: Control, e: Control, lane_idx: int) -> void:
	var p_atk = _effective_attack(p, lane_idx, false)
	var e_atk = _effective_attack(e, lane_idx, true)

	_apply_thorns(p, e, true)
	_apply_thorns(e, p, false)

	e.take_damage(p_atk)
	p.take_damage(e_atk)
	p.has_attacked_this_turn = true
	e.has_attacked_this_turn = true
	screen_shake(0.3)

	# Piercing
	if e.current_hp <= 0 and p.has_keyword("piercing"):
		var excess = abs(e.current_hp)
		var bonus = 1 if _has_relic("piercing_crown") else 0
		damage_enemy_hero(excess + bonus)
	if p.current_hp <= 0 and e.has_keyword("piercing"):
		var excess = abs(p.current_hp)
		damage_player_hero(excess)

	# Vampire Lord passive
	if p.card_data.get("passive", "") == "vampire_lord" and e.current_hp <= 0:
		player_hp = mini(player_hp + 2, player_max_hp)
		p.current_atk += 1
		p.update_stat_display()


func _creature_attacks_creature(attacker: Control, defender: Control, lane_idx: int, attacker_is_enemy: bool) -> void:
	var atk = _effective_attack(attacker, lane_idx, attacker_is_enemy)
	_apply_thorns(defender, attacker, attacker_is_enemy)
	defender.take_damage(atk)
	attacker.has_attacked_this_turn = true
	screen_shake(0.3)
	if defender.current_hp <= 0 and attacker.has_keyword("piercing"):
		var excess = abs(defender.current_hp)
		var bonus = 1 if (not attacker_is_enemy and _has_relic("piercing_crown")) else 0
		if attacker_is_enemy:
			damage_player_hero(excess + bonus)
		else:
			damage_enemy_hero(excess + bonus)


func _creature_hits_face(card: Control, lane_idx: int, is_enemy: bool) -> void:
	var atk = _effective_attack(card, lane_idx, is_enemy)
	if is_enemy:
		# Check for wall damage reduction
		var reduction = _get_wall_reduction(lane_idx, false)
		atk = maxi(0, atk - reduction)
		if atk > 0:
			damage_player_hero(atk)
			screen_shake(0.8)
			screen_flash(Color(0.7, 0.05, 0.05, 0.45), 0.35)
	else:
		damage_enemy_hero(atk)
		screen_shake(0.5)
	card.has_attacked_this_turn = true


func _resolve_ranged_attacks() -> void:
	for lane_idx in range(4):
		for is_enemy in [false, true]:
			var field = _enemy_field if is_enemy else _player_field
			var card = field[lane_idx]
			if card == null or not card.has_keyword("ranged") or card.has_attacked_this_turn:
				continue
			card.has_attacked_this_turn = true
			var targets: Array = []
			var opp_field = _player_field if is_enemy else _enemy_field
			for c in opp_field:
				if c != null:
					targets.append(c)
			if targets.size() > 0:
				var target = targets[randi() % targets.size()]
				var atk = _effective_attack(card, lane_idx, is_enemy)
				target.take_damage(atk)


func _apply_thorns(defender: Control, attacker: Control, attacker_is_enemy: bool) -> void:
	if defender.has_keyword("thorns") and defender.current_hp > 0:
		var thorns_dmg = 1
		if not attacker_is_enemy and _has_relic("briar_amulet"):
			thorns_dmg = 2
		attacker.take_damage_bypass_armor(thorns_dmg)


func _effective_attack(card: Control, lane_idx: int, is_enemy: bool) -> int:
	var atk = card.effective_atk()
	if not is_enemy:
		atk += _get_adj_buff_atk(lane_idx, false)
		if card.has_keyword("swift") and _has_relic("swift_boots"):
			atk += 1
		if _has_bannerman_buff(false):
			atk += 1
		if _has_relic("glass_cannon"):
			atk += 1
		if _has_relic("stone_skin"):
			atk = maxi(0, atk - 1)
	return maxi(0, atk)


func _get_adj_buff_atk(lane_idx: int, is_enemy: bool) -> int:
	var field = _enemy_field if is_enemy else _player_field
	var total := 0
	for adj in [lane_idx - 1, lane_idx + 1]:
		if adj < 0 or adj > 3:
			continue
		var neighbor = field[adj]
		if neighbor != null and neighbor.card_data.has("adj_buff"):
			total += neighbor.card_data.adj_buff.get("atk", 0)
			if not is_enemy and _has_relic("banner_of_unity"):
				total += 1
	return total


func _has_bannerman_buff(is_enemy: bool) -> bool:
	var field = _enemy_field if is_enemy else _player_field
	for c in field:
		if c != null and c.card_data.get("passive", "") == "global_atk_buff":
			return true
	return false


func _has_passive_on_field(passive_name: String) -> bool:
	for c in _player_field:
		if c != null and c.card_data.get("passive", "") == passive_name:
			return true
	return false


func _get_wall_reduction(lane_idx: int, _is_enemy: bool) -> int:
	var reduction := 0
	for i in range(4):
		var c = _player_field[i]
		if c != null and c.card_data.get("passive", "") == "cannot_attack_wall":
			if i == lane_idx or abs(i - lane_idx) == 1:
				reduction += 1
		if c != null and c.card_data.get("passive", "") == "reduce_face_damage":
			reduction += 1
	return reduction


func _cleanup_dead() -> void:
	for lane_idx in range(4):
		if _player_field[lane_idx] != null and _player_field[lane_idx].current_hp <= 0:
			var card = _player_field[lane_idx]
			KeywordEffects.dispatch_on_death(card, lane_idx, false, self)
			_on_friendly_death(card, lane_idx)
			_player_field[lane_idx] = null
		if _enemy_field[lane_idx] != null and _enemy_field[lane_idx].current_hp <= 0:
			var card = _enemy_field[lane_idx]
			KeywordEffects.dispatch_on_death(card, lane_idx, true, self)
			_enemy_field[lane_idx] = null


func _on_friendly_death(card: Control, _lane_idx: int) -> void:
	_friendly_deaths_this_fight += 1
	_friendly_deaths_this_round += 1
	_last_dead_creature_id = card.card_id
	# Gravedigger
	if _friendly_deaths_this_round == 1 and _has_passive_on_field("draw_on_ally_death"):
		draw_one()
	# Corpse Eater
	for i in range(4):
		var c = _player_field[i]
		if c != null and c.card_data.get("passive", "") == "grow_on_ally_death":
			c.current_atk += 1
			c.update_stat_display()
	# Soul Lantern
	if _has_relic("soul_lantern") and not _soul_lantern_used_this_round:
		_soul_lantern_used_this_round = true
		_bonus_mana_next_turn += 1


func _post_combat_sequence() -> void:
	# Discard hand (retain cards stay)
	_discard_hand()

	# Enemy places creatures
	await _short_pause(0.3)
	_enemy_place_creatures()

	# Assassin dies at end of turn
	for i in range(4):
		var c = _player_field[i]
		if c != null and c.card_data.get("passive", "") == "dies_end_of_turn":
			c.take_damage(999)
			_player_field[i] = null

	_update_hud()
	_check_game_over()
	if phase != Phase.GAME_OVER:
		await _short_pause(0.3)
		_start_round()


func _enemy_place_creatures() -> void:
	var placed := 0
	for lane_idx in range(4):
		if placed >= 2:
			break
		if _enemy_field[lane_idx] != null:
			continue
		if _enemy_deck.is_empty():
			_enemy_deck.append(CardDB.random_enemy_for_act(RunState.get_act()))
		var card_id = _enemy_deck.pop_front()
		_place_lane_card(card_id, lane_idx, true)
		KeywordEffects.dispatch_on_enter(card_id, lane_idx, true, self)
		placed += 1


func _short_pause(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


# =====================================================================
#  CARD PLAY
# =====================================================================

func _on_card_played(card: Control) -> void:
	if phase != Phase.PLAYER_TURN:
		return
	if _sacrifice_mode:
		_cancel_sacrifice()
	if _targeting_spell != null:
		_cancel_targeting()

	var cost = card.card_data.cost
	if card.is_spell() and _has_relic("ember_crown") and not _first_spell_this_turn:
		cost = 0
	if player_mana < cost:
		_show_info("Not enough mana!")
		return

	if card.is_spell():
		_play_spell(card, cost)
	else:
		_play_creature(card, cost)


func _play_creature(card: Control, cost: int) -> void:
	if card.has_keyword("sacrifice"):
		# Need to sacrifice first — enter sacrifice-to-play mode
		_show_info("Click a creature to sacrifice for this card.")
		return

	var lane_idx = _nearest_lane_index(card.global_position)
	if _player_field[lane_idx] != null:
		# Replace creature: old goes to discard
		var old = _player_field[lane_idx]
		_player_discard_pile.append(old.card_id)
		old.queue_free()
		_player_field[lane_idx] = null

	player_mana -= cost
	_cards_played_this_turn += 1
	_hand.erase(card)
	_hand_container.remove_child(card)

	card.is_on_battlefield = true
	card.summoned_this_turn = true
	card.current_lane = lane_idx

	# Relic buffs on play
	if not _first_creature_played and _has_relic("iron_buckler"):
		card.current_hp += 2
		card.card_data.hp += 2
	if _has_relic("veterans_medal") and card.card_data.cost == 1 and card.is_creature():
		card.current_atk += 1
		card.current_hp += 1
		card.card_data.hp += 1
	if _has_relic("glass_cannon") and card.is_creature():
		card.current_hp = maxi(1, card.current_hp - 1)
		card.card_data.hp = maxi(1, card.card_data.hp - 1)
	if _has_relic("stone_skin") and card.is_creature():
		card.current_hp += 1
		card.card_data.hp += 1

	_first_creature_played = true
	_place_card_in_slot(card, lane_idx)

	# On-enter effects
	KeywordEffects.dispatch_on_enter(card, lane_idx, false, self)

	# Ironclad Veteran
	if card.card_data.get("on_enter", {}).get("type", "") == "atk_per_cards_played":
		card.current_atk += _cards_played_this_turn - 1
		card.update_stat_display()

	# Vengeful Spirit
	if card.card_data.get("passive", "") == "atk_per_face_damage":
		card.current_atk += _face_damage_taken_this_fight
		card.update_stat_display()

	# Summon keyword
	if card.has_keyword("summon"):
		KeywordEffects._do_summon(lane_idx, false, self)

	card.update_stat_display()
	_update_hud()


func _play_spell(card: Control, cost: int) -> void:
	var targeting = card.card_data.get("targeting", "none")
	if targeting != "none":
		player_mana -= cost
		_first_spell_this_turn = true
		_cards_played_this_turn += 1
		_hand.erase(card)
		_hand_container.remove_child(card)
		_targeting_spell = card
		_targeting_data = card.card_data
		_show_info("Click a target...")
		_update_hud()
		return

	# Non-targeted spell: resolve immediately
	player_mana -= cost
	_first_spell_this_turn = true
	_cards_played_this_turn += 1
	_hand.erase(card)
	_hand_container.remove_child(card)
	_resolve_spell(card.card_data, null, -1)
	_after_spell(card)


func _resolve_spell(data: Dictionary, target: Control, target_lane: int) -> void:
	var spell = data.get("spell", {})
	var spell_type = spell.get("type", "")
	var value = spell.get("value", 0)

	# Spell damage bonus
	if _has_relic("worn_spellbook") and spell_type == "damage":
		value += 1

	match spell_type:
		"damage":
			if target != null:
				target.take_damage(value)
		"damage_face":
			var bonus = 1 if _has_relic("pyromaniac_ring") else 0
			damage_enemy_hero(value + bonus)
		"damage_all_enemies":
			for c in _enemy_field:
				if c != null:
					c.take_damage(value)
		"damage_all":
			for c in _player_field + _enemy_field:
				if c != null:
					c.take_damage(value)
			_cleanup_dead()
		"buff_atk":
			if target != null:
				var bonus = 1 if _has_relic("war_horn") else 0
				if spell.get("permanent", false):
					target.current_atk += value + bonus
				else:
					target.temp_atk_buff += value + bonus
				target.update_stat_display()
		"buff_hp":
			if target != null:
				target.current_hp += value
				target.card_data.hp += value
				target.update_stat_display()
		"heal":
			if target != null:
				target.current_hp = mini(target.current_hp + value, target.card_data.hp)
				target.update_stat_display()
		"draw":
			for i in value:
				draw_one()
		"buff_all_atk":
			var bonus = 1 if _has_relic("war_horn") else 0
			for c in _player_field:
				if c != null:
					if spell.get("permanent", false):
						c.current_atk += value + bonus
					else:
						c.temp_atk_buff += value + bonus
					c.update_stat_display()
		"custom":
			_resolve_custom_spell(spell.get("id", ""), target, target_lane)

	_last_spell_played_this_turn = data


func _resolve_custom_spell(spell_id: String, target: Control, _target_lane: int) -> void:
	match spell_id:
		"blood_tithe":
			var bonus = 1 if _has_relic("pyromaniac_ring") else 0
			damage_enemy_hero(2 + bonus)
			damage_player_hero(1)
		"reckless_charge":
			if target != null:
				var value = 3 + (1 if _has_relic("worn_spellbook") else 0)
				target.take_damage(value)
			draw_one()
			damage_player_hero(1)
		"shove":
			if target != null:
				var empty: Array[int] = []
				for i in range(4):
					if _enemy_field[i] == null and _enemy_field[i] != target:
						empty.append(i)
				target.take_damage(1)
				if empty.size() > 0:
					var old_lane = -1
					for i in range(4):
						if _enemy_field[i] == target:
							old_lane = i
							break
					var new_lane = empty[randi() % empty.size()]
					if old_lane >= 0:
						_enemy_field[old_lane] = null
						_enemy_field[new_lane] = target
		"second_wind":
			if target != null:
				target.current_hp = target.card_data.hp
				target.current_atk += 1
				target.update_stat_display()
		"lightning":
			if target != null:
				target.take_damage(2)
			damage_enemy_hero(2)
		"offering":
			if target != null:
				target.take_damage(999)
				player_mana += 2
		"unholy_bargain":
			for i in 3:
				draw_one()
			damage_player_hero(3)
		"dark_pact":
			for c in _player_field:
				if c != null:
					c.current_atk += 1
					c.update_stat_display()
			damage_player_hero(2)
		"kings_command":
			for c in _player_field:
				if c != null:
					c.temp_atk_buff += 3
					c.current_hp += 1
					c.card_data.hp += 1
					c.update_stat_display()
		"mass_grave":
			var kills := 0
			for i in range(4):
				if _player_field[i] != null:
					_player_field[i].take_damage(999)
					_player_field[i] = null
					kills += 1
			damage_enemy_hero(kills * 3)
		"grave_robbery":
			if _last_dead_creature_id != "":
				_player_draw_pile.push_front(_last_dead_creature_id)
				draw_one()
		"cataclysm":
			var max_atk := 0
			for c in _player_field:
				if c != null:
					max_atk = maxi(max_atk, c.effective_atk())
			for c in _enemy_field:
				if c != null:
					c.take_damage(max_atk)
		"soul_swap":
			if target != null:
				var tmp = target.current_atk
				target.current_atk = target.current_hp
				target.current_hp = tmp
				target.card_data.hp = target.current_hp
				target.update_stat_display()
		"apocalypse":
			var kills := 0
			for field in [_player_field, _enemy_field]:
				for i in range(4):
					if field[i] != null:
						field[i].take_damage(999)
						field[i] = null
						kills += 1
			damage_player_hero(kills)
		"grave_pact":
			_grave_pact_active = true
		"fuel_the_pyre":
			if target != null:
				var atk = target.effective_atk()
				target.take_damage(999)
				# Next target click for damage... simplified: hit random enemy
				var enemies: Array = []
				for c in _enemy_field:
					if c != null:
						enemies.append(c)
				if enemies.size() > 0:
					enemies[randi() % enemies.size()].take_damage(atk)
				else:
					damage_enemy_hero(atk)
		"pillage":
			if target != null:
				var value = 3 + (1 if _has_relic("worn_spellbook") else 0)
				target.take_damage(value)
				if target.current_hp <= 0:
					RunState.gold += 10
		"war_chant":
			# Discard 2 from hand
			var discarded := 0
			while _hand.size() > 0 and discarded < 2:
				var c = _hand.pop_back()
				_player_discard_pile.append(c.card_id)
				_hand_container.remove_child(c)
				c.queue_free()
				discarded += 1
			if discarded > 0:
				player_mana += 1
		"scrap":
			if _hand.size() > 0:
				var c = _hand.pop_back()
				_player_discard_pile.append(c.card_id)
				_hand_container.remove_child(c)
				c.queue_free()
				player_mana += 1
		"gambit":
			var to_discard = mini(3, _hand.size())
			for i in to_discard:
				if _hand.size() > 0:
					var c = _hand.pop_back()
					_player_discard_pile.append(c.card_id)
					_hand_container.remove_child(c)
					c.queue_free()
			for i in to_discard:
				draw_one()
		"barricade":
			if target != null:
				target.current_hp += 3
				target.card_data.hp += 3
				target.update_stat_display()
		_:
			pass

	_update_hud()


func _after_spell(card: Control) -> void:
	if card.has_keyword("exhaust"):
		_exhaust_pile.append(card.card_id)
	else:
		_player_discard_pile.append(card.card_id)
	card.queue_free()
	_cleanup_dead()
	_update_hud()


# =====================================================================
#  TARGETING MODE
# =====================================================================

func _input(event: InputEvent) -> void:
	if _targeting_spell != null and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_resolve_target(event.global_position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_targeting()
			get_viewport().set_input_as_handled()
	elif _sacrifice_mode and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_sacrifice_target(event.global_position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_sacrifice()
			get_viewport().set_input_as_handled()


func _try_resolve_target(pos: Vector2) -> void:
	var targeting = _targeting_data.get("targeting", "none")
	# Check if clicked on a creature
	for lane_idx in range(4):
		if targeting in ["enemy_creature", "any_creature", "any"]:
			var e = _enemy_field[lane_idx]
			if e != null and _is_click_on_card(pos, e):
				_resolve_spell(_targeting_data, e, lane_idx)
				_after_spell(_targeting_spell)
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				return
		if targeting in ["friendly_creature", "any_creature", "any"]:
			var p = _player_field[lane_idx]
			if p != null and _is_click_on_card(pos, p):
				_resolve_spell(_targeting_data, p, lane_idx)
				_after_spell(_targeting_spell)
				_targeting_spell = null
				_targeting_data = {}
				_info_label.text = ""
				return
	# "any" targeting: check if clicked enemy hero area (top of screen)
	if targeting == "any" and pos.y < get_viewport_rect().size.y * 0.15:
		var spell = _targeting_data.get("spell", {})
		var value = spell.get("value", 0)
		if _has_relic("worn_spellbook") and spell.get("type", "") == "damage":
			value += 1
		damage_enemy_hero(value)
		_after_spell(_targeting_spell)
		_targeting_spell = null
		_targeting_data = {}
		_info_label.text = ""
		return


func _cancel_targeting() -> void:
	if _targeting_spell == null:
		return
	# Return spell to hand
	player_mana += _targeting_data.cost
	_cards_played_this_turn -= 1
	_hand_container.add_child(_targeting_spell)
	_hand.append(_targeting_spell)
	_targeting_spell.played.connect(_on_card_played.bind(_targeting_spell))
	_targeting_spell = null
	_targeting_data = {}
	_info_label.text = ""
	_update_hud()


func _is_click_on_card(pos: Vector2, card: Control) -> bool:
	var rect = Rect2(card.global_position, card.size)
	return rect.has_point(pos)


# =====================================================================
#  SACRIFICE
# =====================================================================

func _on_sacrifice_pressed() -> void:
	if phase != Phase.PLAYER_TURN or _sacrifice_used_this_turn:
		return
	if _targeting_spell != null:
		_cancel_targeting()
	_sacrifice_mode = true
	_sacrifice_btn.text = "CANCEL [X]"
	_show_info("Click a creature to sacrifice...")


func _cancel_sacrifice() -> void:
	_sacrifice_mode = false
	_sacrifice_btn.text = "SACRIFICE [S]"
	_info_label.text = ""


func _try_sacrifice_target(pos: Vector2) -> void:
	for lane_idx in range(4):
		var card = _player_field[lane_idx]
		if card != null and _is_click_on_card(pos, card):
			_sacrifice_creature(lane_idx)
			return


func _sacrifice_creature(lane_idx: int) -> void:
	var card = _player_field[lane_idx]
	if card == null:
		return
	_sacrifice_used_this_turn = true
	_sacrifice_mode = false
	_sacrifice_btn.text = "SACRIFICE [S]"
	_sacrifice_btn.disabled = true

	# Bone Pile relic
	if _has_relic("bone_pile"):
		var opp = get_opposing_card(lane_idx, false)
		if opp != null:
			opp.take_damage(card.effective_atk())

	# Butcher's Cleaver relic
	if _has_relic("butchers_cleaver"):
		# Next creature this turn gets +2 ATK
		pass  # Simplified: handled via flag

	KeywordEffects.dispatch_on_death(card, lane_idx, false, self)
	_on_friendly_death(card, lane_idx)
	card.take_damage(999)
	_player_field[lane_idx] = null
	_restore_slot_label(_player_slots[lane_idx], lane_idx)
	_info_label.text = ""
	_update_hud()


# =====================================================================
#  HAND & DECK
# =====================================================================

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


func _draw_card(card_id: String) -> void:
	if _hand.size() >= MAX_HAND_SIZE:
		return
	var card = CARD_SCENE.instantiate()
	card.card_id = card_id
	card.card_data = CardDB.get_card_data(card_id)
	_hand_container.add_child(card)
	_hand.append(card)
	card.played.connect(_on_card_played.bind(card))


func _discard_hand() -> void:
	var to_keep: Array[Control] = []
	for card in _hand:
		if card.has_keyword("retain"):
			to_keep.append(card)
		else:
			_player_discard_pile.append(card.card_id)
			card.queue_free()
	_hand = to_keep
	# Reset temp buffs on all battlefield creatures
	for field in [_player_field, _enemy_field]:
		for c in field:
			if c != null:
				c.temp_atk_buff = 0
				c.has_attacked_this_turn = false
				c.summoned_this_turn = false
				c.update_stat_display()


# =====================================================================
#  PUBLIC API (used by KeywordEffects)
# =====================================================================

func damage_player_hero(amount: int) -> void:
	player_hp -= amount
	_face_damage_taken_this_fight += amount
	if _has_relic("bloodstone_relic"):
		for c in _player_field:
			if c != null:
				c.temp_atk_buff += 1
				c.update_stat_display()
	_on_hero_damaged(amount)
	_update_hud()


func damage_enemy_hero(amount: int) -> void:
	enemy_hp -= amount
	_update_hud()


func get_opposing_card(lane_idx: int, from_enemy_perspective: bool) -> Control:
	if from_enemy_perspective:
		return _player_field[lane_idx]
	return _enemy_field[lane_idx]


func summon_token(atk: int, hp: int, lane_idx: int, is_enemy: bool) -> void:
	var field = _enemy_field if is_enemy else _player_field
	if field[lane_idx] != null:
		return
	var token_hp = hp
	if not is_enemy and _has_relic("conscription_relic"):
		token_hp += 1
	var card = CARD_SCENE.instantiate()
	card.card_id = "token_%d_%d" % [atk, token_hp]
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.card_data = {"id": card.card_id, "name": "Token", "type": "creature",
		"cost": 0, "atk": atk, "hp": token_hp, "keywords": [], "rarity": "enemy", "desc": ""}
	card.current_atk = atk
	card.current_hp = token_hp
	card.summoned_this_turn = true
	card.current_lane = lane_idx
	field[lane_idx] = card
	var slot = _enemy_slots[lane_idx] if is_enemy else _player_slots[lane_idx]
	for child in slot.get_children():
		child.queue_free()
	slot.add_child(card)
	card.destroyed.connect(_on_card_destroyed.bind(card))


func _return_dead_to_hand(lane_idx: int) -> void:
	if _grave_pact_active and _last_dead_creature_id != "":
		_player_draw_pile.push_front(_last_dead_creature_id)
		draw_one()
		_grave_pact_active = false


func _on_hero_damaged(amount: int) -> void:
	if player_hp <= 0 and _has_relic("phoenix_heart") and not RunState.phoenix_heart_consumed:
		RunState.phoenix_heart_consumed = true
		player_hp = 1


# =====================================================================
#  GAME OVER
# =====================================================================

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
		# Vulture's Feast
		if _has_relic("vultures_feast"):
			var heal = mini(_friendly_deaths_this_fight, 5)
			RunState.heal_hero(heal)
		# Coin Purse
		if _has_relic("coin_purse"):
			RunState.gold += 10
		# Thief's Gloves
		if _has_relic("thiefs_gloves") and player_hp == _starting_hp:
			RunState.gold += 5
		# Gold reward
		var node_type = RunState.node_type_for_floor(RunState.current_floor)
		match node_type:
			"combat": RunState.gold += 25
			"elite": RunState.gold += 40
			"boss": RunState.gold += 40

		if node_type == "boss":
			# Post-boss heal: 75% of missing HP
			var missing = RunState.hero_max_hp - RunState.hero_hp
			RunState.heal_hero(int(missing * 0.75))
			get_tree().create_timer(2.0).timeout.connect(func():
				if RunState.current_floor >= RunState.FLOOR_COUNT:
					RunState.end_run(true)
					get_tree().change_scene_to_file(GAMEOVER_SCENE)
				else:
					get_tree().change_scene_to_file(REWARD_SCENE)
			)
		else:
			get_tree().create_timer(1.0).timeout.connect(func():
				get_tree().change_scene_to_file(REWARD_SCENE)
			)


# =====================================================================
#  RELIC HELPERS
# =====================================================================

func _has_relic(id: String) -> bool:
	return RunState.has_relic(id)


# =====================================================================
#  BOARD LAYOUT
# =====================================================================

func _build_board() -> void:
	_shake_layer = CanvasLayer.new()
	_shake_layer.layer = 0
	add_child(_shake_layer)
	_shake_container = Control.new()
	_shake_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shake_layer.add_child(_shake_container)

	_board_bg = ColorRect.new()
	_board_bg.color = BOARD_BG
	_board_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shake_container.add_child(_board_bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.anchor_top = 0.08
	main_vbox.anchor_bottom = 1.0
	main_vbox.anchor_left = 0.1
	main_vbox.anchor_right = 0.9
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shake_container.add_child(main_vbox)

	var enemy_label := Label.new()
	enemy_label.text = "— ENEMY SIDE —"
	enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_label.add_theme_font_size_override("font_size", 12)
	enemy_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 0.6))
	enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(enemy_label)

	var enemy_row := HBoxContainer.new()
	enemy_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_row.add_theme_constant_override("separation", 8)
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(enemy_row)

	_midline = ColorRect.new()
	_midline.custom_minimum_size = Vector2(0, 3)
	_midline.color = GILT
	_midline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_midline)

	var player_label := Label.new()
	player_label.text = "— YOUR SIDE —"
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.add_theme_font_size_override("font_size", 12)
	player_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.4, 0.6))
	player_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(player_label)

	var player_row := HBoxContainer.new()
	player_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_row.add_theme_constant_override("separation", 8)
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	player_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(player_row)

	for i in range(4):
		var e_slot := _make_lane_slot(true, i)
		enemy_row.add_child(e_slot)
		_enemy_slots.append(e_slot)
		var p_slot := _make_lane_slot(false, i)
		player_row.add_child(p_slot)
		_player_slots.append(p_slot)

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
	var lbl := Label.new()
	lbl.text = "Lane %d" % (lane_idx + 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.35, 0.28, 0.4))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(lbl)
	return slot


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


func _place_card_in_slot(card: Control, lane_idx: int) -> void:
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
#  HUD
# =====================================================================

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 12
	add_child(_hud_layer)

	var top := _make_panel(Vector2(0.5, 0.0), Vector2(-160, 10), Vector2(320, 68))
	_hud_layer.add_child(top)
	_floor_label = _make_text_label("Floor %d / %d" %
		[RunState.current_floor, RunState.FLOOR_COUNT], 14, GILT)
	_floor_label.position = Vector2(0, 6)
	_floor_label.size = Vector2(320, 20)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_floor_label)
	_phase_label = _make_text_label("ROUND 1", 24, IVORY)
	_phase_label.position = Vector2(0, 28)
	_phase_label.size = Vector2(320, 34)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_phase_label)

	var enemy_panel := _make_panel(Vector2(0.5, 0.0), Vector2(-90, 84), Vector2(180, 32))
	_hud_layer.add_child(enemy_panel)
	_enemy_hp_label = _make_text_label("Enemy  %d / %d" % [enemy_hp, enemy_max_hp],
		15, Color(0.95, 0.55, 0.40))
	_enemy_hp_label.position = Vector2(0, 5)
	_enemy_hp_label.size = Vector2(180, 22)
	_enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_panel.add_child(_enemy_hp_label)

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

	var turn_panel := _make_panel(Vector2(1.0, 1.0), Vector2(-140, -72), Vector2(120, 30))
	_hud_layer.add_child(turn_panel)
	_turn_label = _make_text_label("Round 1", 13, GILT)
	_turn_label.position = Vector2(0, 5)
	_turn_label.size = Vector2(120, 20)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_panel.add_child(_turn_label)

	_build_end_turn_button()
	_build_sacrifice_button()

	_info_label = _make_text_label("", 22, Color(1, 0.78, 0.40))
	_info_label.set_anchors_preset(Control.PRESET_CENTER)
	_info_label.position = Vector2(-200, -30)
	_info_label.size = Vector2(400, 60)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_info_label.add_theme_constant_override("outline_size", 6)
	_hud_layer.add_child(_info_label)

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
	_style_button(btn)
	_end_turn_btn = btn
	_hud_layer.add_child(btn)


func _build_sacrifice_button() -> void:
	var btn := Button.new()
	btn.text = "SACRIFICE [S]"
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -170
	btn.offset_top = -78
	btn.offset_right = -16
	btn.offset_bottom = -46
	btn.pressed.connect(_on_sacrifice_pressed)
	_style_button(btn)
	_sacrifice_btn = btn
	_hud_layer.add_child(btn)


func _style_button(btn: Button) -> void:
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
	_turn_label.text = "Round %d" % round_number
	match phase:
		Phase.PLAYER_TURN:
			_phase_label.text = "ROUND %d — YOUR TURN" % round_number
			_phase_label.add_theme_color_override("font_color", IVORY)
		Phase.RESOLVING:
			_phase_label.text = "COMBAT"
			_phase_label.add_theme_color_override("font_color", Color(1.00, 0.60, 0.25))
		Phase.GAME_OVER:
			pass


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


func freeze_frame(duration: float) -> void:
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func screen_flash(color: Color, duration: float) -> void:
	_flash_rect.color = color
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color",
		Color(color.r, color.g, color.b, 0.0), duration)


func _show_info(msg: String) -> void:
	_info_label.text = msg
	_info_label.modulate = Color(1, 1, 1, 1)
	var t := create_tween()
	t.tween_interval(1.5)
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
			KEY_S:
				if phase == Phase.PLAYER_TURN:
					if _sacrifice_mode:
						_cancel_sacrifice()
					else:
						_on_sacrifice_pressed()
