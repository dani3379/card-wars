extends RefCounted
## HumanPilot — the solo-combat play policy, expressed as a PURE function of a
## decision-time state snapshot.
##
## Why this exists: the pilot that drives `_probe_cardpower` / `_probe_field`
## is welded to a live Combat instance (it reads `combat._hand`, moves Card2D
## nodes, calls `_on_card_played`). That makes it impossible to ask "what would
## you do here?" about a state we did not simulate — which is exactly what you
## need to check the bot against the recorded decisions of real players.
##
## So the decision logic lives here, over the SAME dictionary shape PlayLog
## writes (see scripts/state/PlayLog.gd):
##   {round, php, ehp, mana, max_mana,
##    hand:[{id,cost,type}],
##    player_board:[8], enemy_board:[8]}      # [front0..3, back0..3]
## A board slot is null or {id, atk, hp, kw:[]}.
##
## `decide()` returns ONE action — the next thing the pilot would do from this
## exact state — so a scorer can compare it against what the human did next:
##   {"kind":"creature", "id":.., "hand_index":i, "lane":0-3, "row":0|1}
##   {"kind":"spell",    "id":.., "hand_index":i}
##   {"kind":"end_turn"}
##
## Card stats are looked up through an injected CardDB (the snapshot's hand
## entries carry only id/cost/type), so this stays testable and autoload-free.

const LANES := 4
const ROW_FRONT := 0
const ROW_BACK := 1

# Cards whose play needs a modal choice the pilot can't make headlessly.
const MODAL := ["familiar", "scholar", "treasure_hunter", "adaptable", "copycat",
	"war_council", "quartermaster", "the_understudy", "rat_piper", "muster_the_fallen"]


# ── Tunables ────────────────────────────────────────────────────────────────
# Everything the policy can be steered by lives here, so a tuning pass is a
# diff in one block rather than a rewrite. Defaults reproduce the 2026-07-13
# pilot's behaviour exactly, which is the honest baseline to measure against.
class Params extends RefCounted:
	## Card choice. "hand_order" replays the 2026-07-13 pilot (first affordable
	## card in hand order). "curve" spends the largest affordable body first.
	## "cheapest" plays the smallest body first — which is what the recorded
	## players actually do (49% vs 33% for priciest on the real choices): a
	## cheap body first leaves change for a second body, and width wins lanes.
	var creature_order := "cheapest"
	## Play spells before creatures instead of after.
	var spells_first := false
	## Leave this much Command unspent when nothing high-value is affordable.
	var bank_below := 0
	## Score for an open enemy lane (a clear road to the face).
	##
	## This used to be 50, against a block score of `lane_threat - enemy_hp`
	## (usually ~0 or negative), so the pilot almost always took the empty lane.
	## The recorded players do the opposite: 64% of their front-row placements
	## go into a lane that ALREADY holds an enemy and 62% opposite the biggest
	## threat, while "first open road" explains only 27%. They block; the bot
	## raced. Open road is now the fallback, not the default.
	var open_lane_score := 5
	## Base score for a kill-trade, before the victim's ATK is added. Must stay
	## clear of block_score + max lane threat — a lane you can KILL into is
	## strictly better than one you merely wall, and an earlier draft of these
	## numbers (trade 100 vs block 120) silently inverted that.
	var trade_score := 250
	## Base score for blocking an occupied lane, before its threat is added.
	var block_score := 120
	## Softmax temperature for `sample_slot`. 0 = deterministic argmax (what the
	## probes score); >0 spreads the choice over near-equal lanes.
	##
	## Human play is NOT deterministic and modelling it as argmax is a mistake
	## the literature is explicit about: state-of-the-art human move prediction
	## (Maia-2) tops out near 53% top-1 accuracy because "even the same player
	## won't always make the same decision when faced with the same position".
	## Measured on this game's own logs, the same player repeats their lane
	## choice in equivalent situations only ~57% of the time. So a bot that
	## always picks the argmax lane is provably LESS human-like than one that
	## spreads over near-equal options — and reads as robotic besides.
	## 12.0 is calibrated to the score gaps used above (a ~60-point block/open
	## gap stays decisive; ties and near-ties get shared).
	var temperature := 12.0

	func duplicate_params() -> Params:
		var p := Params.new()
		p.creature_order = creature_order
		p.spells_first = spells_first
		p.bank_below = bank_below
		p.open_lane_score = open_lane_score
		p.trade_score = trade_score
		p.block_score = block_score
		p.temperature = temperature
		return p


static func default_params() -> Params:
	return Params.new()


# ── Entry point ─────────────────────────────────────────────────────────────

static func decide(state: Dictionary, cards, params: Params = null) -> Dictionary:
	if params == null:
		params = Params.new()
	var order: Array = ["creature", "spell"]
	if params.spells_first:
		order = ["spell", "creature"]
	for kind in order:
		var act: Dictionary = _decide_kind(state, cards, params, String(kind))
		if not act.is_empty():
			return act
	return {"kind": "end_turn"}


## Play out a WHOLE turn from a turn-start snapshot, rolling the state forward
## locally after each action. Returns the ordered list of actions taken.
##
## This is the unit that "plays the same way" should actually be judged on. A
## per-decision card comparison punishes the pilot for playing goblin→brute
## where the human played brute→goblin, even though the turn ends in exactly
## the same board — measured that way the pilot scored 43%, while its true
## card agreement ignoring order is ~81%. Compare turns, not keystrokes.
static func simulate_turn(state: Dictionary, cards,
		params: Params = null, max_actions: int = 12) -> Array:
	if params == null:
		params = Params.new()
	var st: Dictionary = _clone_state(state)
	var out: Array = []
	for _i in max_actions:
		var act: Dictionary = decide(st, cards, params)
		if String(act.get("kind", "end_turn")) == "end_turn":
			break
		out.append(act)
		_apply(st, act, cards)
	return out


## Apply a pilot action to a local state copy: pay the Command, drop the card
## out of hand, and occupy the slot. Deliberately shallow — this models the
## bookkeeping a placement decision depends on (mana, hand, occupancy), NOT
## combat resolution. Nothing here should grow into a second combat engine;
## if a policy ever needs real resolution it belongs in the live-Combat pilot.
static func _apply(state: Dictionary, act: Dictionary, cards) -> void:
	var idx: int = int(act.get("hand_index", -1))
	var hand: Array = state.get("hand", [])
	var cost := 0
	if idx >= 0 and idx < hand.size():
		cost = int((hand[idx] as Dictionary).get("cost", 0))
		hand.remove_at(idx)
	state["mana"] = maxi(0, int(state.get("mana", 0)) - cost)
	if String(act.get("kind", "")) != "creature":
		return
	var cd: Dictionary = _card_data(cards, String(act.get("id", "")))
	var board: Array = state.get("player_board", [])
	var slot_i: int = int(act.get("row", 0)) * LANES + int(act.get("lane", 0))
	if slot_i >= 0 and slot_i < board.size():
		board[slot_i] = {
			"id": act.get("id", ""),
			"atk": cd.get("atk", 0),
			"hp": cd.get("hp", 1),
			"kw": cd.get("keywords", []),
		}


static func _clone_state(state: Dictionary) -> Dictionary:
	var st: Dictionary = state.duplicate(true)
	if not st.has("hand"):
		st["hand"] = []
	if not st.has("player_board"):
		st["player_board"] = []
	return st


static func _decide_kind(state: Dictionary, cards, params: Params,
		kind: String) -> Dictionary:
	if kind == "creature":
		return _choose_creature(state, cards, params)
	return _choose_spell(state, cards, params)


# ── Creatures ───────────────────────────────────────────────────────────────

static func _choose_creature(state: Dictionary, cards, params: Params) -> Dictionary:
	var mana: int = int(state.get("mana", 0))
	var hand: Array = state.get("hand", [])
	var best_i := -1
	var best_rank := -99999
	for i in hand.size():
		var h: Dictionary = hand[i]
		if String(h.get("type", "")) != "creature":
			continue
		var id := String(h.get("id", ""))
		if id in MODAL:
			continue
		var cost := int(h.get("cost", 0))
		if cost > mana:
			continue
		if mana - cost < params.bank_below and cost < mana:
			continue
		var rank := 0
		match params.creature_order:
			"curve":
				# Spend the biggest body you can afford; ties to hand order.
				rank = cost * 100 - i
			"cheapest":
				# Smallest body first; ties to hand order.
				rank = -cost * 100 - i
			_:
				rank = -i          # hand order: earliest playable wins
		if rank > best_rank:
			best_rank = rank
			best_i = i
	if best_i < 0:
		return {}
	var h2: Dictionary = hand[best_i]
	var id2 := String(h2.get("id", ""))
	var cd: Dictionary = _card_data(cards, id2)
	var slot: Dictionary = _pick_slot(state, cd, params)
	if slot.is_empty():
		return {}
	return {"kind": "creature", "id": id2, "hand_index": best_i,
		"lane": int(slot["lane"]), "row": int(slot["row"])}


## Placement policy: walls hold the front opposite the biggest attacker;
## snipers/siege pieces shelter in back (the front row is struck first);
## attackers hunt a kill-trade, then an open road to the face, then a block;
## everything overflows to the back row as queue space once the front fills.
static func _pick_slot(state: Dictionary, cd: Dictionary,
		params: Params) -> Dictionary:
	var kws: Array = cd.get("keywords", [])
	var atk := int(cd.get("atk", 0))
	var hp := int(cd.get("hp", 1))
	var is_wall: bool = ("guardian" in kws) or (atk <= 1 and hp >= 4)
	# NOTE — a back-row rule was TRIED HERE AND REVERTED (2026-07-20). Humans
	# put 26% of creatures in the back and 68% of those are voluntary (their
	# front row was not full), on ordinary cheap bodies (goblin x10, ratling
	# x7, brute x5), not snipers — so the pilot's 89%-front looked like a clear
	# gap. But "shelter fragile trigger bodies behind a held line" fires on
	# ~55% of plays, because nearly every cheap creature carries an on-enter or
	# on-death trigger; it overshot to 55% back and made row TVD WORSE
	# (0.151 -> 0.283). Narrowing to 1-cost changed nothing (those cards ARE
	# the bulk of plays).
	# The lesson is a rate cannot be matched by a hard predicate when the
	# qualifying cards are half the deck: the row choice has to be SAMPLED
	# (see Params.temperature, which already does this for lanes). Don't
	# re-add a deterministic version of this rule without re-measuring row TVD.
	var wants_back: bool = ("sniper" in kws) \
		or String(cd.get("passive", "")) == "trebuchet_volley" \
		or (atk == 0 and not ("guardian" in kws))

	var mine: Array = state.get("player_board", [])
	var front_free: Array = []
	var back_free: Array = []
	for lane in LANES:
		if _slot(mine, ROW_FRONT, lane) == null:
			front_free.append(lane)
		if _slot(mine, ROW_BACK, lane) == null:
			back_free.append(lane)

	if wants_back and back_free.size() > 0:
		var pick_b: int = int(back_free[0])
		for l in back_free:
			if _slot(mine, ROW_FRONT, int(l)) != null:
				pick_b = int(l)      # shelter behind a held front lane
				break
		return {"lane": pick_b, "row": ROW_BACK}

	if front_free.size() > 0:
		# Tie-break centre-out, not left-to-right. When every free lane scores
		# the same (an empty enemy front, common on the opening turns) the old
		# pilot always took lane 0; measured against real placements that is
		# EXACTLY chance (33.3% vs a 33.3% random baseline), while centre-out
		# explains 43.6%. Sorting the candidate list up front means every
		# scoring branch below inherits the better tie-break.
		front_free.sort_custom(func(a, b):
			return absf(float(a) - 1.5) < absf(float(b) - 1.5))
		var pick: int = int(front_free[0])
		if is_wall:
			var best_t := -1
			for l in front_free:
				var t := _lane_threat(state, int(l))
				if t > best_t:
					best_t = t
					pick = int(l)
		else:
			var best_s := -999
			for l in front_free:
				var e = _slot(state.get("enemy_board", []), ROW_FRONT, int(l))
				var s := 0
				if e != null:
					if int(e.get("hp", 0)) <= atk:
						s = params.trade_score + int(e.get("atk", 0))
					else:
						# Blocking is worth more the harder the lane hits.
						s = params.block_score + _lane_threat(state, int(l))
				else:
					s = params.open_lane_score
				if s > best_s:
					best_s = s
					pick = int(l)
		return {"lane": pick, "row": ROW_FRONT}

	if back_free.size() > 0:
		return {"lane": int(back_free[0]), "row": ROW_BACK}
	return {}


## Every front-lane candidate with its score, best first. Exposed so evaluation
## can report TOP-K rather than only top-1: with four lanes and several near-
## equivalent ones, top-1 is a harsh and partly meaningless target, which is
## why the human-move-prediction literature reports top-3 alongside it ("player
## move decisions involve inherent uncertainty, and relying on Top-1 move
## prediction alone often leads to suboptimal accuracy").
static func rank_front_lanes(state: Dictionary, cd: Dictionary,
		params: Params = null) -> Array:
	if params == null:
		params = Params.new()
	var kws: Array = cd.get("keywords", [])
	var atk := int(cd.get("atk", 0))
	var hp := int(cd.get("hp", 1))
	var is_wall: bool = ("guardian" in kws) or (atk <= 1 and hp >= 4)
	var mine: Array = state.get("player_board", [])
	var out: Array = []
	for lane in LANES:
		if _slot(mine, ROW_FRONT, lane) != null:
			continue
		var s := 0
		if is_wall:
			s = _lane_threat(state, lane)
		else:
			var e = _slot(state.get("enemy_board", []), ROW_FRONT, lane)
			if e != null:
				if int(e.get("hp", 0)) <= atk:
					s = params.trade_score + int(e.get("atk", 0))
				else:
					s = params.block_score + _lane_threat(state, lane)
			else:
				s = params.open_lane_score
		# Centre-out tie-break folded in as a sub-point nudge.
		out.append({"lane": lane,
			"score": float(s) - 0.1 * absf(float(lane) - 1.5)})
	out.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return out


## Pick a front lane by SAMPLING the softmax over lane scores instead of taking
## the argmax — the human-likeness fix (see Params.temperature). Deterministic
## when temperature <= 0. `rng` is injected so callers own reproducibility.
static func sample_front_lane(state: Dictionary, cd: Dictionary,
		rng: RandomNumberGenerator, params: Params = null) -> int:
	if params == null:
		params = Params.new()
	var ranked: Array = rank_front_lanes(state, cd, params)
	if ranked.is_empty():
		return -1
	if params.temperature <= 0.0 or ranked.size() == 1:
		return int((ranked[0] as Dictionary)["lane"])
	var top: float = float((ranked[0] as Dictionary)["score"])
	var weights: Array = []
	var total := 0.0
	for r in ranked:
		# Subtract the max before exp() — the scores here run into the
		# hundreds and exp() of those overflows to inf.
		var w: float = exp((float((r as Dictionary)["score"]) - top) / params.temperature)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in ranked.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return int((ranked[i] as Dictionary)["lane"])
	return int((ranked[0] as Dictionary)["lane"])


# ── Spells ──────────────────────────────────────────────────────────────────

static func _choose_spell(state: Dictionary, cards, params: Params) -> Dictionary:
	var mana: int = int(state.get("mana", 0))
	var hand: Array = state.get("hand", [])
	for i in hand.size():
		var h: Dictionary = hand[i]
		if String(h.get("type", "")) != "spell":
			continue
		var id := String(h.get("id", ""))
		if id in MODAL:
			continue
		if int(h.get("cost", 0)) > mana:
			continue
		var cd: Dictionary = _card_data(cards, id)
		# Army-wide support with no army is a wasted card; humans bank instead.
		if String(cd.get("scope", "")) == "YOUR ARMY" \
				and _friendly_count(state) == 0:
			continue
		# A targeted spell with nothing to point at is likewise held.
		var targeting := String(cd.get("targeting", "none"))
		if targeting in ["enemy_creature"] and _enemy_count(state) == 0:
			continue
		if targeting in ["friendly_creature"] and _friendly_count(state) == 0:
			continue
		if targeting == "any_creature" \
				and _enemy_count(state) + _friendly_count(state) == 0:
			continue
		return {"kind": "spell", "id": id, "hand_index": i}
	return {}


# ── Board helpers ───────────────────────────────────────────────────────────

static func _slot(board: Array, row: int, lane: int):
	var idx: int = row * LANES + lane
	if idx < 0 or idx >= board.size():
		return null
	return board[idx]


## Is there already a friendly body in the front row to shelter behind? A
## trigger-body only goes to the back if someone is holding the line.
static func _has_front_line(state: Dictionary) -> bool:
	var mine: Array = state.get("player_board", [])
	for lane in LANES:
		if _slot(mine, ROW_FRONT, lane) != null:
			return true
	return false


static func _lane_threat(state: Dictionary, lane: int) -> int:
	var foe: Array = state.get("enemy_board", [])
	var t := 0
	for row in [ROW_FRONT, ROW_BACK]:
		var e = _slot(foe, row, lane)
		if e != null:
			t += int(e.get("atk", 0))
	return t


static func _friendly_count(state: Dictionary) -> int:
	return _live_count(state.get("player_board", []))


static func _enemy_count(state: Dictionary) -> int:
	return _live_count(state.get("enemy_board", []))


static func _live_count(board: Array) -> int:
	var n := 0
	for s in board:
		if s != null:
			n += 1
	return n


static func _card_data(cards, id: String) -> Dictionary:
	if cards == null:
		return {}
	return cards.call("get_card_data", id)
