extends Node
## KeywordEffects.gd — 16 keywords from design doc.
## Combat.gd calls dispatch_* hooks. Display helpers used by Card2D.

const KEYWORDS: Dictionary = {
	"armored":    {"display": "Armored",     "desc": "Takes 1 less damage from creature attacks (min 1)."},
	"swift":      {"display": "Swift",       "desc": "Attacks before simultaneous combat."},
	"ranged":     {"display": "Ranged",      "desc": "Attacks random enemy creature. Lane counts as empty."},
	"thorns":     {"display": "Thorns",      "desc": "Deals 1 back to anything that attacks it."},
	"regenerate": {"display": "Regenerate",  "desc": "Heals 1 HP at start of each round."},
	"summon":     {"display": "Summon",      "desc": "Summons 1/1 token in adjacent empty lane."},
	"last_stand": {"display": "Last Stand",  "desc": "First lethal hit leaves it at 1 HP."},
	"piercing":   {"display": "Piercing",    "desc": "Excess kill damage hits enemy face."},
	"sacrifice":  {"display": "Sacrifice",   "desc": "Kill a friendly creature to play."},
	"exhaust":    {"display": "Exhaust",     "desc": "Removed from fight after use."},
	"retain":     {"display": "Retain",      "desc": "Keep instead of discarding at end of turn."},
	"wither":     {"display": "Wither",      "desc": "Loses ATK at start of each round (min 0)."},
	"on_enter":   {"display": "On-Enter",    "desc": "Effect triggers when placed."},
	"on_death":   {"display": "On-Death",    "desc": "Effect triggers when creature dies."},
	"floop":      {"display": "Floop",       "desc": "Skip attack to use special ability."},
	"adj_buff":   {"display": "Adj. Buff",   "desc": "Neighboring creatures get stat bonus."},
}


static func display_text_for(keywords: Array) -> String:
	var out: Array[String] = []
	for k in keywords:
		if KEYWORDS.has(k):
			out.append(KEYWORDS[k].display)
	return "  ".join(out)


static func tooltip_for(keyword: String) -> String:
	if KEYWORDS.has(keyword):
		return "%s: %s" % [KEYWORDS[keyword].display, KEYWORDS[keyword].desc]
	return ""


static func dispatch_on_enter(card, lane_idx: int, is_enemy: bool, ctx) -> void:
	var data = card.card_data if card is Control else CardDB.get_card_data(card)
	if data.is_empty() or not data.has("on_enter"):
		return
	var effect = data.on_enter
	_run_on_enter(effect, lane_idx, is_enemy, ctx)
	if data.has("keywords") and data.keywords.has("summon"):
		_do_summon(lane_idx, is_enemy, ctx)


static func dispatch_on_death(card, lane_idx: int, was_enemy: bool, ctx) -> void:
	if card == null:
		return
	var data = card.card_data if card is Control else {}
	if data.is_empty() or not data.has("on_death"):
		return
	var effect = data.on_death
	var times = 1
	if not was_enemy and ctx._has_passive_on_field("double_on_death"):
		times = 2
	for i in times:
		_run_on_death(effect, lane_idx, was_enemy, ctx)


static func dispatch_start_of_round(ctx) -> void:
	for lane_idx in range(4):
		for field_arr in [ctx._player_field, ctx._enemy_field]:
			var is_enemy = (field_arr == ctx._enemy_field)
			var card = field_arr[lane_idx]
			if card == null:
				continue
			if card.has_keyword("regenerate"):
				card.current_hp = mini(card.current_hp + 1, card.card_data.hp)
				card.update_stat_display()
			if card.has_keyword("wither"):
				var w = card.card_data.get("wither", 1)
				card.current_atk = maxi(0, card.current_atk - w)
				card.update_stat_display()


static func _run_on_enter(effect: Dictionary, lane_idx: int, is_enemy: bool, ctx) -> void:
	match effect.get("type", ""):
		"damage_opposing":
			var target = ctx.get_opposing_card(lane_idx, not is_enemy)
			if target != null:
				target.take_damage(effect.value)
		"damage_opposing_draw":
			var target = ctx.get_opposing_card(lane_idx, not is_enemy)
			if target != null:
				target.take_damage(effect.value)
			if not is_enemy:
				ctx.draw_one()
		"damage_random_player":
			var targets: Array = []
			var field = ctx._player_field if is_enemy else ctx._enemy_field
			for c in field:
				if c != null:
					targets.append(c)
			if targets.size() > 0:
				targets[randi() % targets.size()].take_damage(effect.value)
		"damage_all_enemies":
			var field = ctx._player_field if is_enemy else ctx._enemy_field
			for c in field:
				if c != null:
					c.take_damage(effect.value)
		"draw":
			if not is_enemy:
				for i in effect.value:
					ctx.draw_one()
		"gain_gold":
			if not is_enemy:
				RunState.gold += effect.value
		"atk_per_cards_played":
			pass  # handled in Combat.gd
		"damage_face":
			if is_enemy:
				ctx.damage_player_hero(effect.value)
			else:
				ctx.damage_enemy_hero(effect.value)
		"debuff_opposing_atk":
			var target = ctx.get_opposing_card(lane_idx, not is_enemy)
			if target != null:
				target.current_atk = maxi(0, target.current_atk - effect.value)
				target.update_stat_display()
		"discard_random":
			if is_enemy and ctx._hand.size() > 0:
				var idx = randi() % ctx._hand.size()
				var c = ctx._hand[idx]
				ctx._hand.remove_at(idx)
				ctx._player_discard_pile.append(c.card_id)
				ctx._hand_container.remove_child(c)
				c.queue_free()
		_:
			pass


static func _run_on_death(effect: Dictionary, lane_idx: int, was_enemy: bool, ctx) -> void:
	match effect.get("type", ""):
		"damage_opposing_lane":
			var target = ctx.get_opposing_card(lane_idx, was_enemy)
			if target != null:
				target.take_damage(effect.value)
			else:
				if was_enemy:
					ctx.damage_player_hero(effect.value)
				else:
					ctx.damage_enemy_hero(effect.value)
		"damage_opposing":
			var target = ctx.get_opposing_card(lane_idx, was_enemy)
			if target != null:
				target.take_damage(effect.value)
		"damage_all_enemies":
			var field = ctx._player_field if was_enemy else ctx._enemy_field
			for c in field:
				if c != null:
					c.take_damage(effect.value)
		"summon":
			ctx.summon_token(effect.atk, effect.hp, lane_idx, was_enemy)
		"bonus_mana":
			if not was_enemy:
				ctx._bonus_mana_next_turn += effect.value
		"return_to_hand_once":
			if not was_enemy:
				ctx._return_dead_to_hand(lane_idx)
		"damage_face":
			if was_enemy:
				ctx.damage_player_hero(effect.value)
			else:
				ctx.damage_enemy_hero(effect.value)
		"debuff_all_player_atk":
			if was_enemy:
				for c in ctx._player_field:
					if c != null:
						c.current_atk = maxi(0, c.current_atk - effect.value)
						c.update_stat_display()
		"damage_adjacent":
			var field = ctx._enemy_field if was_enemy else ctx._player_field
			for adj in [lane_idx - 1, lane_idx + 1]:
				if adj >= 0 and adj < 4 and field[adj] != null:
					field[adj].take_damage(effect.value)
		_:
			pass


static func _do_summon(lane_idx: int, is_enemy: bool, ctx) -> void:
	var adj_lanes: Array[int] = []
	if lane_idx > 0:
		adj_lanes.append(lane_idx - 1)
	if lane_idx < 3:
		adj_lanes.append(lane_idx + 1)
	adj_lanes.shuffle()
	var field = ctx._enemy_field if is_enemy else ctx._player_field
	for l in adj_lanes:
		if field[l] == null:
			ctx.summon_token(1, 1, l, is_enemy)
			return
