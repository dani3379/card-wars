extends Node
## KeywordEffects.gd — 16 keywords from design doc.
## Combat.gd calls dispatch_* hooks. Display helpers used by Card2D.

const KEYWORDS: Dictionary = {
	"armored":    {"display": "Armored",     "desc": "Takes 1 less damage from creature attacks (min 1)."},
	"swift":      {"display": "Swift",       "desc": "Attacks before simultaneous combat."},
	"ranged":     {"display": "Ranged",      "desc": "Attacks back-row enemies first, then front. Blocked column is fine."},
	"thorns":     {"display": "Thorns",      "desc": "Deals 1 back to anything that attacks it."},
	"regenerate": {"display": "Regenerate",  "desc": "Heals 1 HP at start of each round."},
	"summon":     {"display": "Summon",      "desc": "Summons 1/1 token in adjacent empty lane."},
	"last_stand": {"display": "Last Stand",  "desc": "First lethal hit leaves it at 1 HP."},
	"piercing":   {"display": "Piercing",    "desc": "Excess kill damage hits enemy back row, then face."},
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


# Wrap any occurrence of a keyword display name in BBCode color+bold tags so a
# RichTextLabel renders them in gold. Match is case-insensitive but preserves
# the original word casing. Multi-word keywords ("Last Stand", "On-Enter",
# "On-Death", "Adj. Buff") are handled by sorting longest-first so the longer
# names match before their substrings.
const KEYWORD_GOLD := "#e8b547"  # warm parchment gold, 5.1:1 contrast on #4E4956 text well (WCAG AA)

static func colorize_keywords(text: String) -> String:
	if text.is_empty():
		return ""
	var names: Array[String] = []
	for k in KEYWORDS.keys():
		names.append(KEYWORDS[k].display)
	# Sort longest-first so "Last Stand" matches before "Last".
	names.sort_custom(func(a, b): return a.length() > b.length())
	var out = text
	for n in names:
		# Build a regex matching whole-word (or hyphenated-word) occurrences.
		# We use case-insensitive search via lowercase compare.
		var idx = 0
		var lowered = out.to_lower()
		var n_low = n.to_lower()
		var result = ""
		while idx < out.length():
			var found = lowered.find(n_low, idx)
			if found == -1:
				result += out.substr(idx)
				break
			# Word-boundary check: prev/next char must not be alphanumeric.
			var prev_ok = (found == 0) or not _is_word_char(out[found - 1])
			var end = found + n.length()
			var next_ok = (end >= out.length()) or not _is_word_char(out[end])
			if prev_ok and next_ok:
				result += out.substr(idx, found - idx)
				result += "[b][color=%s]%s[/color][/b]" % [KEYWORD_GOLD, out.substr(found, n.length())]
				idx = end
			else:
				result += out.substr(idx, found - idx + 1)
				idx = found + 1
		out = result
		lowered = out.to_lower()
	return out


static func _is_word_char(c: String) -> bool:
	# Hyphens and periods are NOT word chars here, so "On-Enter" inside text like
	# "...On-Enter trigger" still matches.
	return c.length() > 0 and (c.to_lower() != c.to_upper() or (c >= "0" and c <= "9"))


static func dispatch_on_enter(card, lane_idx: int, is_enemy: bool, ctx) -> void:
	var data = card.card_data if card is Control else CardDB.get_card_data(card)
	if data.is_empty() or not data.has("on_enter"):
		return
	var effect = data.on_enter
	_run_on_enter(effect, card, lane_idx, is_enemy, ctx)
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
	# 4x4: iterate every creature on both sides, both rows.
	for card in ctx._all_creatures_both_sides():
		if card.has_keyword("regenerate"):
			card.current_hp = mini(card.current_hp + 1, card.card_data.hp)
			card.update_stat_display()
		if card.has_keyword("wither"):
			var w = card.card_data.get("wither", 1)
			card.current_atk = maxi(0, card.current_atk - w)
			card.update_stat_display()


const COMBAT_KEYWORDS := ["armored", "swift", "ranged", "thorns", "regenerate", "last_stand", "piercing"]


static func _copy_abilities_partial(card, src: Dictionary) -> void:
	# Mirror Knight scope: gain combat keywords + persistent abilities of `src`
	# without changing the card's own body or overriding its intrinsic floop.
	# Adds on_death / adj_buff / passive / wither only if the card doesn't
	# already have one — so Mirror Knight keeps its own swap_atk floop while
	# inheriting the defender's death-rattles, auras, and stat-keywords.
	for kw in src.get("keywords", []):
		if kw in COMBAT_KEYWORDS and not card.card_data.keywords.has(kw):
			card.card_data.keywords.append(kw)
	if src.has("on_death") and not card.card_data.has("on_death"):
		card.card_data["on_death"] = src["on_death"].duplicate(true)
	if src.has("adj_buff") and not card.card_data.has("adj_buff"):
		card.card_data["adj_buff"] = src["adj_buff"].duplicate(true)
	if src.has("passive") and not card.card_data.has("passive"):
		card.card_data["passive"] = src["passive"]
	if src.has("wither") and not card.card_data.has("wither"):
		card.card_data["wither"] = src["wither"]
	card.update_stat_display()


static func _copy_creature_onto(card, src: Dictionary) -> void:
	# Doppelganger scope: full transform — body + all keywords + every persistent
	# ability dict from `src` (on_death, floop, adj_buff, passive, wither). Skips
	# on_enter because we're already inside the copying card's on_enter dispatch;
	# re-running the source's on_enter from here would recurse and was the
	# original reason this function was abilities-blind. The card now actually
	# *becomes* the source instead of grafting only its ATK/HP and a couple of
	# combat keywords.
	var atk := int(src.get("atk", card.current_atk))
	var hp := int(src.get("hp", card.current_hp))
	card.card_data.atk = atk
	card.card_data.hp = hp
	card.current_atk = atk
	card.current_hp = hp
	for kw in src.get("keywords", []):
		if not card.card_data.keywords.has(kw):
			card.card_data.keywords.append(kw)
	for dict_key in ["on_death", "floop", "adj_buff"]:
		if src.has(dict_key):
			card.card_data[dict_key] = src[dict_key].duplicate(true)
	if src.has("passive"):
		card.card_data["passive"] = src["passive"]
	if src.has("wither"):
		card.card_data["wither"] = src["wither"]
	card.update_stat_display()


static func _run_on_enter(effect: Dictionary, card, lane_idx: int, is_enemy: bool, ctx) -> void:
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
			# "From the placer's perspective, hit a random opposing creature." 4x4: both rows.
			var opponents = ctx._all_friendly(not is_enemy)
			if opponents.size() > 0:
				opponents[randi() % opponents.size()].take_damage(effect.value)
		"damage_all_enemies":
			for c in ctx._all_friendly(not is_enemy):
				c.take_damage(effect.value)
		"draw":
			if not is_enemy:
				for i in effect.value:
					ctx.draw_one()
		"gain_gold":
			if not is_enemy:
				RunState.gain_gold(effect.value)
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
				ctx._player_discard_pile.append(ctx._pile_entry(c.card_id, c.deck_uid))
				ctx._hand_container.remove_child(c)
				c.queue_free()
		"copy_friendly":
			# Copycat: take on the body of a random other friendly creature.
			if card != null:
				var pool := []
				for c in ctx._all_friendly(is_enemy):
					if c != card:
						pool.append(c)
				if pool.size() > 0:
					_copy_creature_onto(card, pool[randi() % pool.size()].card_data)
		"copy_opposing_keywords":
			# Mirror Knight: mirror the opposing creature's combat keywords AND
			# its persistent abilities (on_death / adj_buff / passive / wither)
			# without changing Mirror Knight's body or overriding its own floop.
			# Previously this only copied combat keywords, so vs anything without
			# armored/swift/thorns Mirror Knight landed as a vanilla 2/3.
			if card != null:
				var opp = ctx.get_opposing_card(lane_idx, not is_enemy)
				if opp != null:
					_copy_abilities_partial(card, opp.card_data)
		"copy_last_dead":
			# Doppelganger: become a copy of the last creature that died.
			if card != null:
				var src = ctx._last_dead_copy_data()
				if not src.is_empty():
					_copy_creature_onto(card, src)
		"look_top":
			# Stray Cat: look at the top N of the draw pile, draw the cheapest.
			if not is_enemy:
				ctx._look_top_pick(int(effect.get("value", 3)))
		"cast_random_spell":
			# Chaos Imp: cast a random non-custom spell for free, auto-targeted.
			if not is_enemy:
				ctx.cast_random_spell_free()
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
			for c in ctx._all_friendly(not was_enemy):
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
				for c in ctx._all_player_creatures():
					c.current_atk = maxi(0, c.current_atk - effect.value)
					c.update_stat_display()
		"damage_adjacent":
			# 4x4: hit same-row adjacency on the dead creature's side.
			# Without a row reference we hit both rows' adjacencies.
			for row in [0, 1]:
				var field = ctx._row_array(was_enemy, row)
				for adj in [lane_idx - 1, lane_idx + 1]:
					if adj >= 0 and adj < 4 and field[adj] != null:
						field[adj].take_damage(effect.value)
		_:
			pass


static func _do_summon(lane_idx: int, is_enemy: bool, ctx) -> void:
	# 4x4: try same-row adjacent empties first (front), then fall through.
	var adj_lanes: Array[int] = []
	if lane_idx > 0:
		adj_lanes.append(lane_idx - 1)
	if lane_idx < 3:
		adj_lanes.append(lane_idx + 1)
	adj_lanes.shuffle()
	for row in [0, 1]:
		var field = ctx._row_array(is_enemy, row)
		for l in adj_lanes:
			if field[l] == null:
				ctx.summon_token(1, 1, l, is_enemy, row)
				return
