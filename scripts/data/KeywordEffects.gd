extends Node
## KeywordEffects.gd — the 27 keywords.
## Combat.gd calls dispatch_* hooks. Display helpers used by Card2D.

const KEYWORDS: Dictionary = {
	"armored":    {"display": "Armored",     "desc": "Takes 1 less damage from each hit (minimum 1)."},
	"swift":      {"display": "Swift",       "desc": "Attacks first each round, before enemies can strike back."},
	"thorns":     {"display": "Thorns",      "desc": "Deals 1 damage back to each creature that attacks this."},
	"regenerate": {"display": "Regenerate",  "desc": "Heals 1 HP at the start of each round."},
	"summon":     {"display": "Summon",      "desc": "When played, also summons a 1/1 token in an adjacent empty lane."},
	"last_stand": {"display": "Last Stand",  "desc": "Survives the first killing blow at 1 HP. Once per fight."},
	"piercing":   {"display": "Piercing",    "desc": "When this kills its target, leftover damage carries to the creature behind it, then to enemy face."},
	"sniper":     {"display": "Sniper",      "desc": "After the clash, hits the lowest-HP enemy creature. If it kills, it shoots again."},
	"sacrifice":  {"display": "Sacrifice",   "desc": "Cost: destroy one of your own creatures to play this card."},
	"exhaust":    {"display": "Exhaust",     "desc": "Once played, this card is gone for the rest of the fight."},
	"retain":     {"display": "Retain",      "desc": "Stays in your hand at end of turn instead of being discarded."},
	"wither":     {"display": "Wither N",    "desc": "Loses N ATK at the start of each round."},
	"on_enter":   {"display": "On-Enter",    "desc": "Effect triggers the moment this creature is placed on the board."},
	"on_death":   {"display": "On-Death",    "desc": "Effect triggers when this creature dies (HP reaches 0)."},
	"adj_buff":   {"display": "Adj. Buff",   "desc": "Friendlies to its left and right get a stat bonus while this is in play."},
	"poison":     {"display": "Poison",      "desc": "Any creature it damages dies, no matter its remaining HP."},
	"shield":     {"display": "Shield",      "desc": "Absorbs the first hit completely, then Shield is removed."},
	"guardian":   {"display": "Guardian",    "desc": "Enemies to its left and right must attack this creature."},
	"structure":  {"display": "Structure",   "desc": "Can't be attacked or targeted by spells."},
	"slay":       {"display": "Slay",        "desc": "An effect that fires when this kills the creature it's fighting."},
	"adjacent":   {"display": "Adjacent",    "desc": "The creatures directly to its left and right."},
	"doom":       {"display": "Doom N",      "desc": "Counts down 1 per round. At 0, deals its ATK to enemy face, then dies."},
	"rampage":    {"display": "Rampage",     "desc": "Gains +1 ATK this fight each time it kills an enemy creature (more if a number is shown)."},
	"lifelink":   {"display": "Lifelink",    "desc": "You heal 1 HP whenever this deals damage in battle."},
	"overrun":    {"display": "Overrun",     "desc": "Start of each round: +1 ATK this round if no enemy stands directly across."},
	"formation":  {"display": "Formation",   "desc": "Start of each round: +1/+1 this fight if a friendly stands beside it."},
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
	if data.is_empty():
		return
	# Read the Summon keyword BEFORE the effect runs: transform on-enters
	# (copy_friendly / copy_last_dead) graft the source's keywords onto this
	# card mid-dispatch, and a grafted Summon must not fire as a play trigger
	# — copies skip enter-triggers by design (see _copy_creature_onto).
	# Keyword-only carriers (Mule) have no on_enter dict,
	# so Summon dispatches independently of it. Combat.gd has no separate
	# summon pass — this is the single dispatch point for both sides.
	var summon_on_play: bool = data.has("keywords") and data.keywords.has("summon")
	if data.has("on_enter"):
		_run_on_enter(data.on_enter, card, lane_idx, is_enemy, ctx)
		# Name the battlecry on the creature that cast it, so the visible result
		# (a card drawn, the foe's face ticking down) ties back to its cause.
		_trigger_callout(card, ctx, _effect_label(data.on_enter, false, is_enemy), false)
	if summon_on_play:
		_do_summon(lane_idx, is_enemy, ctx)
		_trigger_callout(card, ctx, "SUMMON", false)
		if not is_enemy:
			ctx._dispatch_reactive("ON_PLAYER_SUMMON", card, lane_idx)


static func dispatch_on_death(card, lane_idx: int, was_enemy: bool, ctx, row: int = -1) -> void:
	if card == null:
		return
	var data = card.card_data if card is Control else {}
	if data.is_empty() or not data.has("on_death"):
		return
	var effect = data.on_death
	# Capture the dying card's screen anchor NOW — it may be freed before the
	# effect (and our deathrattle callout) resolve.
	var death_anchor := Vector2.ZERO
	var have_anchor := false
	if card is Control and is_instance_valid(card):
		death_anchor = card.global_position + Vector2(
			card.size.x * card.scale.x * 0.5, card.size.y * card.scale.y * 0.06)
		have_anchor = true
	# Griffin (return_to_hand_once): identity- and once-based — resolve it HERE while
	# the dying `card` (and its deck uid) is still in scope, never via the value-based
	# _run_on_death doubling loop (returning to hand twice is nonsense, and the shared
	# _last_dead_creature_* trackers aren't set until after this dispatch). Net routes
	# to the caster's hand; solo floats it to the player's, once per fight.
	if String(effect.get("type", "")) == "return_to_hand_once":
		if ctx._is_net():
			ctx._net_return_dead_to_caster(was_enemy)
		elif not was_enemy:
			ctx._griffin_return_to_hand(card)
		if have_anchor and ctx.has_method("spawn_trigger_callout"):
			ctx.spawn_trigger_callout(death_anchor,
				_effect_label(effect, true, was_enemy), true)
		return
	var times = 1
	if not was_enemy and ctx._has_passive_on_field("double_on_death"):
		times = 2
	# Net: the CLIENT's Warden of Graves doubles the CLIENT's on-deaths too (the
	# player-side check above only ever sees the host's board over the wire).
	if was_enemy and ctx._is_net() and ctx._has_passive_on_side("double_on_death", true):
		times = 2
	# Lich's Bargain (boss): friendly on-deaths fire twice run-wide. The post-
	# combat HP cost is paid in Combat's _post_combat_cleanup (max 3 per fight).
	if not was_enemy and ctx._has_relic("lichs_bargain"):
		times = 2
	# "Frenzied" mutator doubles ENEMY on-death effects (the mirror case the
	# necromancer_tower reactive used to cover only for that one encounter).
	if was_enemy and ctx.has_method("mutator_doubles_enemy_on_death") \
			and ctx.mutator_doubles_enemy_on_death():
		times = 2
	for i in times:
		_run_on_death(effect, lane_idx, was_enemy, ctx, row)
	if have_anchor and ctx.has_method("spawn_trigger_callout"):
		ctx.spawn_trigger_callout(death_anchor,
			_effect_label(effect, true, was_enemy), true)


static func dispatch_start_of_round(ctx) -> void:
	# 4x4: iterate every creature on both sides, both rows.
	# Doom detonations destroy creatures, so collect them during the tick and
	# fire them AFTER the loop — mutating the field arrays mid-iteration would
	# skip neighbours.
	var doomed: Array = []
	for card in ctx._all_creatures_both_sides():
		if card.has_keyword("regenerate") and card.current_hp < int(card.card_data.hp):
			card.current_hp = mini(card.current_hp + 1, int(card.card_data.hp))
			card.update_stat_display()
			# Surface the heal — this used to tick silently, so the player never
			# saw WHY an enemy kept coming back to full each round.
			if ctx.has_method("spawn_keyword_callout_kw"):
				ctx.spawn_keyword_callout_kw(card, "regenerate", " +1")
		if card.has_keyword("wither"):
			var w = card.card_data.get("wither", 1)
			if card.current_atk > 0:
				card.current_atk = maxi(0, card.current_atk - w)
				card.update_stat_display()
				if ctx.has_method("spawn_keyword_callout_kw"):
					ctx.spawn_keyword_callout_kw(card, "wither", " -%d" % w)
		# Doom: tick the per-creature countdown. At 0 the creature is queued to
		# detonate (damage opposing face + destroy via the canonical routine).
		if card.has_keyword("doom"):
			if card.has_method("_ensure_doom_init"):
				card._ensure_doom_init()
			card.doom_counter -= 1
			if card.has_method("update_doom_display"):
				card.update_doom_display()
			if card.has_method("flash_doom_tick"):
				card.flash_doom_tick()
			if card.doom_counter <= 0:
				doomed.append(card)
	for card in doomed:
		if is_instance_valid(card) and card.current_hp > 0:
			ctx._detonate_doom(card)

	# Overrun / Formation — positional start-of-round engines (the conquest
	# keywords; the enemy-side twin of Formation is
	# EncounterEffects.formation_drill_tick — keep the semantics in lockstep).
	# Both skip the setup round so the opening read stays clean (engines fire
	# from round 2 — CONQUEST_REDESIGN.md §15.2; for player creatures this is a
	# no-op gate, since the player board is empty at round 1 start anyway).
	# Runs AFTER the doom detonations above so a lane opened — or a line
	# broken — by a bomb this round is read correctly.
	if ctx.round_number >= 2:
		for side_is_enemy in [false, true]:
			for row in [ctx.ROW_FRONT, ctx.ROW_BACK]:
				var arr: Array = ctx._row_array(side_is_enemy, row)
				for i in arr.size():
					var c = arr[i]
					if c == null or not is_instance_valid(c) or c.current_hp <= 0:
						continue
					# Overrun: an open opposing front lane is the carrier's
					# highway — +N ATK this round (temp buff; clears in the
					# end-of-turn upkeep, so it covers this round's combat).
					if c.has_keyword("overrun") \
							and ctx._row_array(not side_is_enemy, ctx.ROW_FRONT)[i] == null:
						var ov: int = int(c.card_data.get("overrun", 1))
						# "+" versions charge harder (Overrun 2) — same
						# is_upgraded bump idiom as Rampage in Combat.gd.
						if bool(c.card_data.get("is_upgraded", false)):
							ov += 1
						if ov > 0:
							c.temp_atk_buff += ov
							c.update_stat_display()
							ctx.spawn_floating_number(
								c.global_position + Vector2(c.size.x * c.scale.x * 0.5, -10),
								"OVERRUN +%d" % ov, Color(1.0, 0.78, 0.25), false)
					# Formation: a friendly in the same row, adjacent column —
					# the carrier grows +N/+N permanently (max HP rises and the
					# body heals into it, mirroring formation_drill_tick).
					if c.has_keyword("formation"):
						var left = arr[i - 1] if i > 0 else null
						var right = arr[i + 1] if i < arr.size() - 1 else null
						if left != null or right != null:
							var fm: int = int(c.card_data.get("formation", 1))
							if fm > 0:
								c.current_atk += fm
								c.card_data.hp = int(c.card_data.get("hp", 1)) + fm
								c.current_hp = mini(c.current_hp + fm, c.card_data.hp)
								c.update_stat_display()
								ctx.spawn_floating_number(
									c.global_position + Vector2(c.size.x * c.scale.x * 0.5, -10),
									"FORMATION +%d/+%d" % [fm, fm], Color(0.62, 0.78, 0.95), false)


const COMBAT_KEYWORDS := ["armored", "swift", "thorns", "regenerate", "last_stand", "piercing", "sniper", "poison", "shield", "guardian"]


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
	for dict_key in ["on_death", "on_play", "adj_buff"]:
		if src.has(dict_key):
			card.card_data[dict_key] = src[dict_key].duplicate(true)
	if src.has("passive"):
		card.card_data["passive"] = src["passive"]
	if src.has("wither"):
		card.card_data["wither"] = src["wither"]
	card.update_stat_display()


## Fire a trigger (battlecry / deathrattle) callout above `card`, when a non-empty
## label was derived. Static, so it routes through the ctx (Combat) to spawn.
static func _trigger_callout(card, ctx, text: String, is_death: bool) -> void:
	if text == "" or not (card is Control) or not is_instance_valid(card):
		return
	if not ctx.has_method("spawn_trigger_callout"):
		return
	var anchor: Vector2 = card.global_position + Vector2(
		card.size.x * card.scale.x * 0.5, card.size.y * card.scale.y * 0.06)
	# Pass the firing creature's entity_id so the host can replay this label on the
	# client (it never runs the dispatcher). -1 in solo / for an unsynced card = no replay.
	var eid: int = int(card.entity_id) if "entity_id" in card else -1
	ctx.spawn_trigger_callout(anchor, text, is_death, eid)


## Map an on-enter / on-death effect dict to a short callout label. Returns ""
## (no callout) for an effect that does nothing on this side — an enemy creature
## can't "draw" — or that already shows its own UI (Discover opens a picker), so
## a chip never claims something that did not happen.
static func _effect_label(effect: Dictionary, is_death: bool, side_is_enemy: bool) -> String:
	var t := String(effect.get("type", ""))
	var v := int(effect.get("value", 0))
	if is_death:
		match t:
			"damage_opposing_lane", "damage_opposing": return "DEATH BLOW %d" % v
			"damage_all_enemies":    return "DEATH NOVA %d" % v
			"summon":                return "SUMMON"
			"bonus_mana":            return "" if side_is_enemy else "+%d COMMAND" % v
			"return_to_hand_once":   return "" if side_is_enemy else "RETURN"
			"damage_face":           return "TO FACE %d" % v
			"debuff_all_player_atk": return ("WEAKEN ALL %d" % v) if side_is_enemy else ""
			"damage_adjacent":       return "BACKLASH %d" % v
			"grant_shield_adjacent": return "SHIELDS UP"
		return ""
	match t:
		"damage_opposing", "damage_opposing_draw", "damage_random_player":
			return "STRIKE %d" % v
		"damage_all_enemies":     return "VOLLEY %d" % v
		"damage_face":            return "TO FACE %d" % v
		"draw":                   return ("DRAW %d" % v) if not side_is_enemy else ""
		"gain_gold":              return ("+%d GOLD" % v) if not side_is_enemy else ""
		"debuff_opposing_atk":    return "WEAKEN %d" % v
		"discard_random":         return "DISCARD" if side_is_enemy else ""
		"copy_friendly":          return "COPY"
		"copy_opposing_keywords": return "MIMIC"
		"copy_last_dead":         return "RAISE DEAD"
		"look_top":               return "SCRY" if not side_is_enemy else ""
		"cast_random_spell":      return "CAST" if not side_is_enemy else ""
		"glutton_devour":         return "DEVOUR"
	return ""


static func _run_on_enter(effect: Dictionary, card, lane_idx: int, is_enemy: bool, ctx) -> void:
	# (Vanguard's Cry used to add +1 here to every player On-Enter damage —
	# redesigned 2026-07-03 into the first-creature war-cry in
	# Combat._play_creature. The bonus var stays so the arithmetic below is
	# untouched; it is now always 0.)
	var on_enter_bonus: int = 0
	match effect.get("type", ""):
		"damage_opposing":
			var target = ctx.get_opposing_card(lane_idx, is_enemy)
			if target != null:
				target.take_damage(effect.value + on_enter_bonus)
		"damage_opposing_draw":
			var target = ctx.get_opposing_card(lane_idx, is_enemy)
			if target != null:
				target.take_damage(effect.value + on_enter_bonus)
			# Draw goes to the creature's OWNER (the client over the wire in skirmish).
			ctx._battlecry_draw(is_enemy, 1)
		"damage_random_player":
			# "From the placer's perspective, hit a random opposing creature." 4x4: both rows.
			var opponents = ctx._all_friendly(not is_enemy)
			if opponents.size() > 0:
				opponents[randi() % opponents.size()].take_damage(effect.value + on_enter_bonus)
		"damage_all_enemies":
			for c in ctx._all_friendly(not is_enemy):
				c.take_damage(effect.value + on_enter_bonus)
		"draw":
			ctx._battlecry_draw(is_enemy, int(effect.value))
		"gain_gold":
			if not is_enemy:
				RunState.gain_gold(effect.value)
		"atk_hp_per_own_kills":
			pass  # Old Campaigner — handled in Combat.gd (_apply_play_time_passives)
		"atk_hp_per_unspent_mana":
			pass  # Condottiere — handled in Combat.gd (_apply_play_time_passives)
		"damage_face":
			if is_enemy:
				ctx.damage_player_hero(effect.value)
			else:
				ctx.damage_enemy_hero(effect.value + on_enter_bonus)
		"debuff_opposing_atk":
			var target = ctx.get_opposing_card(lane_idx, is_enemy)
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
				if AudioBank != null:
					# The stolen card leaves the hand with a paper-slip, slightly
					# louder than a chosen pitch — it wasn't the player's idea.
					AudioBank.play_sfx("card_discard", 0.08, -4.0)
		"copy_friendly":
			# Copycat: take on the body of another friendly creature. The OWNER picks.
			# Solo: player picks via the friendly-creature picker (fire-and-forget like
			# discover so on_enter stays sync); a solo enemy uses random (no AI UI).
			# Net: the host owns the picker for its OWN creature; for the CLIENT's
			# creature it asks the client to pick (EV_CHOICE → IN_CHOICE round-trip).
			if card != null:
				if ctx._is_net():
					if is_enemy:
						ctx._net_request_client_choice(card, "copy_friendly")
					else:
						ctx._show_copy_friendly_picker(card)
				elif is_enemy:
					var pool := []
					for c in ctx._all_friendly(is_enemy):
						if c != card:
							pool.append(c)
					if pool.size() > 0:
						_copy_creature_onto(card, pool[randi() % pool.size()].card_data)
				else:
					ctx._show_copy_friendly_picker(card)
		"copy_opposing_keywords":
			# Mirror Knight: mirror the opposing creature's combat keywords AND
			# its persistent abilities (on_death / adj_buff / passive / wither)
			# without changing Mirror Knight's body or overriding its own floop.
			# Previously this only copied combat keywords, so vs anything without
			# armored/swift/thorns Mirror Knight landed as a vanilla 2/3.
			if card != null:
				var opp = ctx.get_opposing_card(lane_idx, is_enemy)
				if opp != null:
					_copy_abilities_partial(card, opp.card_data)
		"copy_last_dead":
			# Doppelganger: become a copy of the last creature that died. Net uses the
			# CASTER's per-side grave (a client doppelganger copies the CLIENT's last
			# corpse, not the host's); solo uses the global last-dead. Host-resolved
			# either way, so the copied body rides the trailing board-sync to the client.
			if card != null:
				var src = ctx._net_last_dead_copy_data(is_enemy) if ctx._is_net() else ctx._last_dead_copy_data()
				if not src.is_empty():
					_copy_creature_onto(card, src)
		"look_top":
			# Stray Cat: look at the top N of the draw pile, draw the cheapest.
			if not is_enemy:
				ctx._look_top_pick(int(effect.get("value", 3)))
		"cast_random_spell":
			# Chaos Imp: cast a random spell for free, auto-targeted. Net resolves a
			# random NET-PLAYABLE spell host-side with the caster's perspective so a
			# CLIENT chaos imp actually casts (the old `if not is_enemy` no-op'd it).
			if ctx._is_net():
				ctx._net_cast_random_spell_free(is_enemy)
			elif not is_enemy:
				ctx.cast_random_spell_free()
		"discover":
			# Discover: player-only — opens the 3-card pick overlay filtered
			# by type/rarity on the card. Fires-and-forgets so the on_enter
			# dispatcher itself doesn't have to be awaitable.
			if not is_enemy:
				var tf: String = effect.get("type_filter", "any")
				var rf: String = effect.get("rarity_filter", "")
				ctx._show_discover(tf, rf)
		"discover_link":
			# Familiar: Discover a creature AND remember the picked uid on this
			# card so the Familiar's floop can find and buff it later.
			if not is_enemy:
				var tf: String = effect.get("type_filter", "creature")
				var rf: String = effect.get("rarity_filter", "")
				ctx._show_discover_linked(tf, rf, card)
		"choose_keyword":
			# Adaptable: the OWNER picks one of Swift/Piercing/Armored/Thorns to add to
			# this creature. Solo: player's modal. Net: the host's own creature uses the
			# local modal; the CLIENT's creature is asked to pick (EV_CHOICE → IN_CHOICE).
			if ctx._is_net():
				if is_enemy:
					ctx._net_request_client_choice(card, "keyword")
				else:
					ctx._show_keyword_choice(card)
			elif not is_enemy:
				ctx._show_keyword_choice(card)
		"glutton_devour":
			# The Glutton (Marvel Snap Carnage port) — destroy adjacent friendlies
			# in the same row, gain +2/+2 (+3/+3 upgraded) AND their keywords for
			# each. Routing through take_damage(999) fires their on_death effects
			# (Soul Lantern mana, Husk grow, Corpse Eater grow), so Glutton
			# synergizes with the rest of the death-payoff bucket.
			if card != null:
				var my_row: int = card.current_row
				var field = ctx._row_array(is_enemy, my_row)
				var devoured: int = 0
				var eaten_keywords: Array = []
				for adj_lane in [lane_idx - 1, lane_idx + 1]:
					if adj_lane < 0 or adj_lane >= 4:
						continue
					var victim = field[adj_lane]
					if victim != null and victim != card:
						# "You are what you eat": digest the meal's keywords BEFORE the
						# kill frees it. Drawback keywords (doom / wither) are digested
						# away; value-carrying rampage/lifelink default to 1 on the
						# Glutton, which is exactly what the base keywords mean.
						for kw in victim.card_data.get("keywords", []):
							if (kw in COMBAT_KEYWORDS or kw in ["rampage", "lifelink"]) \
									and kw not in eaten_keywords:
								eaten_keywords.append(kw)
						# Eating your own creature IS a sacrifice — route it through
						# the sacrifice hook so Bone Pile, Butcher's Cleaver, Reaper's
						# Scythe and the ON_PLAYER_SACRIFICE reactive fire, the same as
						# Offering / Fuel the Pyre. (take_damage(999) below still does
						# the actual kill, which fires the victim's on_death payoffs.)
						if not is_enemy:
							ctx._trigger_player_sacrifice(victim)
						victim.take_damage(999)
						devoured += 1
				if devoured > 0:
					var g_gain: int = 3 if bool(card.card_data.get("is_upgraded", false)) else 2
					card.current_atk += g_gain * devoured
					card.card_data.hp += g_gain * devoured
					card.current_hp += g_gain * devoured
					for kw in eaten_keywords:
						if not card.card_data.keywords.has(kw):
							card.card_data.keywords.append(kw)
					# A digested Shield keyword must also arm the live shield state —
					# has_shield is snapshotted from keywords at spawn, not re-derived.
					if eaten_keywords.has("shield") and not card.state.has_shield:
						card.state.has_shield = true
					card.update_stat_display()
		_:
			pass


static func _run_on_death(effect: Dictionary, lane_idx: int, was_enemy: bool, ctx, row: int = -1) -> void:
	# Bone Ring relic: "On-death damage effects deal +1 damage and chip the
	# enemy face for 1." Only applies when one of the player's own creatures
	# dies — enemy on-deaths keep their base values. The face chip fires up
	# front (before the match) so every damage-type case gets it exactly once.
	var on_death_bonus: int = 1 if (not was_enemy and ctx._has_relic("bone_ring")) else 0
	if on_death_bonus > 0 and String(effect.get("type", "")) in [
			"damage_opposing_lane", "damage_opposing", "damage_all_enemies",
			"damage_face", "damage_adjacent"]:
		ctx.damage_enemy_hero(1)
	match effect.get("type", ""):
		"damage_opposing_lane":
			var target = ctx.get_opposing_card(lane_idx, was_enemy)
			if target != null:
				target.take_damage(effect.value + on_death_bonus)
			else:
				if was_enemy:
					ctx.damage_player_hero(effect.value)
				else:
					ctx.damage_enemy_hero(effect.value + on_death_bonus)
		"damage_opposing":
			var target = ctx.get_opposing_card(lane_idx, was_enemy)
			if target != null:
				target.take_damage(effect.value + on_death_bonus)
		"damage_all_enemies":
			for c in ctx._all_friendly(not was_enemy):
				c.take_damage(effect.value + on_death_bonus)
		"summon":
			# Old Bones (diminish): the token inherits a smaller summon of its
			# own, chaining down one size per death until the 1/1 stays dead.
			var bequest := {}
			if bool(effect.get("diminish", false)) and int(effect.atk) > 1:
				bequest = {"type": "summon", "atk": int(effect.atk) - 1,
					"hp": maxi(1, int(effect.hp) - 1), "diminish": true}
			ctx.summon_token(effect.atk, effect.hp, lane_idx, was_enemy, 0, bequest)
			# Necromancer (both_rows): a second token rises in the lane's OTHER
			# row — the grave fills the whole column when both slots are free.
			# (The death path nulls the dying card's slot before dispatch, so
			# the front call above lands in the vacated seat, not the back.)
			if bool(effect.get("both_rows", false)):
				ctx.summon_token(effect.atk, effect.hp, lane_idx, was_enemy, 1, bequest)
		"detonate_dooms":
			# Powder Cart: the wagon goes up — every OTHER friendly Doom creature
			# on its side detonates immediately (each with its own blast and
			# on-death). The cart itself is already dying (hp <= 0), so the
			# hp > 0 guard keeps it — and anything else mid-death — out of
			# the chain; two carts can't re-detonate each other.
			for c in ctx._all_friendly(was_enemy):
				if c != null and is_instance_valid(c) and c.current_hp > 0 \
						and c.has_keyword("doom"):
					ctx._detonate_doom(c)
		"bonus_mana":
			# Mourner: +value max Command on the OWNER's next turn. Routed through
			# the battlecry channel so a client-owned death in net pays the CLIENT —
			# the bare `if not was_enemy` bump this replaced was host-only.
			ctx._battlecry_bonus_mana_next_turn(was_enemy, effect.value)
			# (return_to_hand_once / Griffin is resolved in dispatch_on_death, above —
			# it needs the dying card's identity, which this value-based path lacks.)
		"damage_face":
			if was_enemy:
				ctx.damage_player_hero(effect.value)
			else:
				ctx.damage_enemy_hero(effect.value + on_death_bonus)
		"debuff_all_player_atk":
			if was_enemy:
				for c in ctx._all_player_creatures():
					c.current_atk = maxi(0, c.current_atk - effect.value)
					c.update_stat_display()
		"damage_adjacent":
			# 4x4: hit the same-row left/right neighbours of the dead creature
			# ("creatures directly to its left and right"). When the caller knows
			# the dead card's row (the normal death path threads it), restrict to
			# that one row; the legacy -1 fallback (e.g. the necromancer_tower
			# reactive, which only has lane) still hits both rows' adjacencies.
			var rows_to_hit := [row] if row >= 0 else [0, 1]
			for r in rows_to_hit:
				var field = ctx._row_array(was_enemy, r)
				for adj in [lane_idx - 1, lane_idx + 1]:
					if adj >= 0 and adj < 4 and field[adj] != null:
						field[adj].take_damage(effect.value + on_death_bonus)
		"grant_shield_adjacent":
			# Shieldmaiden — she falls so others stand: same-row neighbours of the
			# dead creature gain Shield. Mirrors the on-play grant (Crystal Sentry)
			# but keyed off the death slot.
			var sm_rows := [row] if row >= 0 else [0, 1]
			for r in sm_rows:
				var field = ctx._row_array(was_enemy, r)
				for adj in [lane_idx - 1, lane_idx + 1]:
					if adj >= 0 and adj < 4 and field[adj] != null:
						var ally = field[adj]
						if is_instance_valid(ally) and ally.current_hp > 0 and not ally.state.has_shield:
							ally.state.has_shield = true
							if ally.has_method("_spawn_keyword_chip"):
								ally._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
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
