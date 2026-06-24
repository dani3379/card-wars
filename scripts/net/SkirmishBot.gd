extends Node
## SkirmishBot — the local practice opponent for vs-bot skirmish matches. Two jobs:
##   1. build_deck()  — assemble a competent 20-card warband from the legal pool.
##   2. decide_turn() — on the bot's turn, return an ordered list of play intents
##      (the SAME IN_PLAY_CREATURE / IN_PLAY_SPELL dicts a remote client sends), so
##      Combat applies them through the existing host-authoritative path.
##
## It is a SMART HEURISTIC, not a learned policy: it contests the human's lanes,
## trades up, fills the front row for pressure, sequences plays to its Command
## budget, and points damage/buff spells at sensible targets. decide_turn() is the
## single seam a PlayLog-trained policy would replace later — everything it needs
## is read live from the Combat instance, so a smarter brain can drop straight in.

const ROW_FRONT := 0
const ROW_BACK := 1
const LANES := 4

var rng := RandomNumberGenerator.new()


# ─────────────────────────────────────────────────────────────────────────
#  DECK BUILDING
# ─────────────────────────────────────────────────────────────────────────

## A 20-card deck biased to cheap cards (skirmish Command is a flat 3 + bank 2, so
## anything over cost 4 is near-unplayable), creatures-heavy with a few spells,
## max 2 copies. Returned in shuffled draw order. seed_val 0 → random each match.
func build_deck(seed_val: int = 0) -> Array:
	rng.seed = seed_val if seed_val != 0 else (int(Time.get_unix_time_from_system()) ^ randi())
	var creatures: Array = []
	var spells: Array = []
	for id in SkirmishState.skirmish_legal_pool():
		var d := CardDB.get_card_data(id)
		if int(d.get("cost", 99)) > 4:
			continue
		match String(d.get("type", "")):
			"creature": creatures.append(id)
			"spell": spells.append(id)

	var deck: Array = []
	var counts: Dictionary = {}
	var spell_cap := 5
	var spells_added := 0
	var guard := 0
	while deck.size() < SkirmishState.DECK_TARGET and guard < 8000:
		guard += 1
		var take_spell := (not spells.is_empty()) and spells_added < spell_cap and rng.randf() < 0.22
		var src: Array = spells if take_spell else creatures
		if src.is_empty():
			src = creatures if not creatures.is_empty() else spells
		if src.is_empty():
			break
		var id: String = _pick_cheap(src)
		if int(counts.get(id, 0)) >= 2:
			continue
		counts[id] = int(counts.get(id, 0)) + 1
		deck.append(id)
		if take_spell:
			spells_added += 1
	# Degenerate tiny-pool guard: pad with whatever creatures exist (copies allowed).
	while deck.size() < SkirmishState.DECK_TARGET and not creatures.is_empty():
		deck.append(creatures[rng.randi() % creatures.size()])
	_shuffle(deck)
	return deck


## Bias toward low cost without hard-excluding anything: sample two, keep the cheaper.
func _pick_cheap(src: Array) -> String:
	var a: String = src[rng.randi() % src.size()]
	var b: String = src[rng.randi() % src.size()]
	return a if int(CardDB.get_card_data(a).get("cost", 9)) <= int(CardDB.get_card_data(b).get("cost", 9)) else b


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ─────────────────────────────────────────────────────────────────────────
#  TURN DECISIONS
# ─────────────────────────────────────────────────────────────────────────

## Greedily pick the best affordable play until Command runs out or nothing helps.
## `hand` is an Array of {uid:int, id:String, data:Dictionary}; `mana` the budget;
## `ctx` the Combat instance (board reads via ctx._row_array). Returns intent dicts.
func decide_turn(ctx, hand: Array, mana: int) -> Array:
	var intents: Array = []
	var budget := mana
	var avail: Array = hand.duplicate()
	var occ := _bot_occupancy(ctx)   # 2×4 bool grid of the bot's filled slots
	var guard := 0
	while guard < 30 and budget > 0 and not avail.is_empty():
		guard += 1
		var best := _best_play(ctx, avail, budget, occ)
		if best.is_empty():
			break
		intents.append(best["intent"])
		budget -= int(best["cost"])
		avail.erase(best["card"])
		var slot = best.get("slot", null)
		if slot != null:
			occ[slot.y][slot.x] = true
	return intents


## Evaluate every affordable card and return the single highest-scoring play, or {}.
func _best_play(ctx, avail: Array, budget: int, occ: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0e9
	for card in avail:
		var data: Dictionary = card.get("data", {})
		var cost := int(data.get("cost", 0))
		if cost > budget:
			continue
		var ctype := String(data.get("type", "creature"))
		if ctype == "creature":
			var cand := _best_creature_slot(ctx, data, occ)
			if cand.is_empty():
				continue
			# Mild cheap-first nudge so a 1-drop edges out an equal-scored 3-drop.
			var score: float = cand["score"] - cost * 0.15
			if score > best_score:
				best_score = score
				best = {
					"intent": {"t": NetMatch.IN_PLAY_CREATURE, "id": String(card["id"]),
						"uid": int(card["uid"]), "lane": cand["lane"], "row": cand["row"]},
					"cost": cost, "card": card, "slot": Vector2i(cand["lane"], cand["row"]),
				}
		elif ctype == "spell":
			var sp := _best_spell(ctx, data)
			if sp.is_empty():
				continue
			var sscore: float = sp["score"] - cost * 0.15
			if sscore > best_score:
				best_score = sscore
				best = {
					"intent": {"t": NetMatch.IN_PLAY_SPELL, "id": String(card["id"]),
						"uid": int(card["uid"]), "target": int(sp["target"])},
					"cost": cost, "card": card,
				}
	# Only act on a play with positive expected value (avoids dumping a spell with
	# no good target just because it is affordable).
	if best.is_empty() or best_score <= 0.0:
		return {}
	return best


## Best lane/row for a creature, with a score. Front row contests the human's
## attackers and applies pressure; the back row is a weaker fallback.
func _best_creature_slot(ctx, data: Dictionary, occ: Array) -> Dictionary:
	var atk := int(data.get("atk", 0))
	var hp := int(data.get("hp", 0))
	var kws: Array = data.get("keywords", [])
	var best_lane := -1
	var best_row := -1
	var best_score := -1.0e9
	for lane in LANES:
		for row in [ROW_FRONT, ROW_BACK]:
			if occ[row][lane]:
				continue
			var score := atk * 1.0 + hp * 0.6
			if "swift" in kws: score += 1.5
			if "piercing" in kws: score += 1.0
			if "armored" in kws: score += 1.0
			if "thorns" in kws: score += 0.8
			var foe = _node_at(ctx, false, ROW_FRONT, lane)   # human front creature
			if row == ROW_FRONT:
				if foe != null:
					var fa := int(foe.effective_atk())
					var fh := int(foe.current_hp)
					score += fa * 1.2                          # neutralise their attacker
					if atk >= fh: score += 2.0 + fh * 0.3      # we can kill it
					if hp > fa: score += 1.5                    # we survive their swing
					if atk < fh and hp <= fa: score -= 1.5      # chump block
				else:
					score += atk * 0.8                          # unblocked pressure
			else:
				score -= 2.0                                    # back row: no immediate combat
				if foe == null:
					score -= 0.5
			if score > best_score:
				best_score = score
				best_lane = lane
				best_row = row
	if best_lane < 0:
		return {}
	return {"score": best_score, "lane": best_lane, "row": best_row}


## Best target + score for a spell the bot understands (damage / AoE / buff / heal).
## Unknown or untargetable-right-now spells return {} so they stay in hand.
func _best_spell(ctx, data: Dictionary) -> Dictionary:
	var spell: Dictionary = data.get("spell", {})
	var stype := String(spell.get("type", ""))
	var val := int(spell.get("value", 0))
	match stype:
		"damage":
			# Single-target removal: prefer a kill on the highest-ATK human creature.
			var target = _pick_enemy_creature(ctx, val)
			if target == null:
				return {}
			var ta := int(target.effective_atk())
			var th := int(target.current_hp)
			var score := ta * 1.3 + (3.0 if val >= th else 0.0)
			return {"score": score, "target": int(target.entity_id)}
		"damage_face":
			return {"score": val * 1.0, "target": -1}
		"damage_all_enemies", "damage_all":
			var n := _enemy_creature_count(ctx)
			if n == 0:
				return {}
			return {"score": val * n * 0.9, "target": -1}
		"buff_atk", "buff_hp":
			var ally = _pick_ally_creature(ctx)
			if ally == null:
				return {}
			return {"score": val * 1.0, "target": int(ally.entity_id)}
		"buff_all_atk":
			var m := _ally_creature_count(ctx)
			if m == 0:
				return {}
			return {"score": val * m * 0.9, "target": -1}
		"heal":
			# Face heal — only worth it when the bot hero is actually hurt.
			if ctx.enemy_hp < ctx.enemy_max_hp - val:
				return {"score": val * 0.6, "target": -1}
			return {}
		_:
			return {}


# ── Board-read helpers (the bot is slot 1 → its board is the "enemy" side; the
#    human host is slot 0 → the "player" side). ───────────────────────────────

func _bot_occupancy(ctx) -> Array:
	var grid: Array = [[false, false, false, false], [false, false, false, false]]
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			if _node_at(ctx, true, row, lane) != null:
				grid[row][lane] = true
	return grid


func _node_at(ctx, is_enemy: bool, row: int, lane: int):
	var arr = ctx._row_array(is_enemy, row)
	if lane < 0 or lane >= arr.size():
		return null
	var n = arr[lane]
	if n != null and is_instance_valid(n):
		return n
	return null


## Highest-ATK human creature, preferring one this much damage would kill.
func _pick_enemy_creature(ctx, dmg: int):
	var best = null
	var best_key := -1.0
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			var n = _node_at(ctx, false, row, lane)
			if n == null or int(n.entity_id) < 0:
				continue
			var a := int(n.effective_atk())
			var key := a + (100.0 if int(n.current_hp) <= dmg else 0.0)
			if key > best_key:
				best_key = key
				best = n
	return best


## The bot's own strongest front creature (best buff target).
func _pick_ally_creature(ctx):
	var best = null
	var best_atk := -1
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			var n = _node_at(ctx, true, row, lane)
			if n == null or int(n.entity_id) < 0:
				continue
			var a := int(n.effective_atk())
			if a > best_atk:
				best_atk = a
				best = n
	return best


func _enemy_creature_count(ctx) -> int:
	var c := 0
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			if _node_at(ctx, false, row, lane) != null:
				c += 1
	return c


func _ally_creature_count(ctx) -> int:
	var c := 0
	for row in [ROW_FRONT, ROW_BACK]:
		for lane in LANES:
			if _node_at(ctx, true, row, lane) != null:
				c += 1
	return c
