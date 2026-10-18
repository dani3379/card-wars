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

## THE SCORING LIVES IN `BoardEval` (2026-09-15), shared with the input pilot.
## What moved out was not just weights — the scoring here had four defects, all
## of them rules the game has had for a long time and none of them visible from
## inside a branch that only compares against its own siblings:
##   · NO CONCEPT OF LETHAL. `damage_face` scored `value * 1.0`, identically at
##     30 foe HP and at 3, so the bot could hold exact lethal and play a 2/2.
##   · OVERKILL WAS FREE. A 6-damage spell on a 2/1 scored the same as on a 2/6,
##     so removal went to the cheapest body on the board.
##   · IT PREDATED THE MUSTER DELAY (2026-07-21). It credited `atk * 0.8` of
##     "unblocked pressure" and `+2.0` for "we can kill it" to a body that does
##     not swing in the clash ending the round it arrived in.
##   · `score -= 2.0  # back row: no immediate combat` — not this game. BOTH rows
##     strike every round; front merely goes first. The flat penalty punished
##     exactly the play the back row is for (shielding something fragile).
## Weights were also unitless across branches (1.0 / 0.6 / 1.2 / 1.3 / 0.9 / 0.6),
## so they ordered plays within a branch and meant nothing between them. BoardEval
## denominates everything in one unit. See its header.
const BoardEval = preload("res://scripts/combat/BoardEval.gd")
## AND THE BOT LEARNS FROM WHAT IT DID WITH IT (2026-09-15). `BotBrain` records
## every decision below — the board, the whole slate of plays that were legal,
## and the one taken — then re-examines them after the match with a deeper look
## and tunes BoardEval's weights toward what that deeper look says. `decide_turn`
## is still the single seam; what changed is that the seam now reports.
const BotBrain = preload("res://scripts/combat/BotBrain.gd")
const BoardSim = preload("res://scripts/combat/BoardSim.gd")

var rng := RandomNumberGenerator.new()


# ─────────────────────────────────────────────────────────────────────────
#  DECK BUILDING
# ─────────────────────────────────────────────────────────────────────────

## A 20-card deck biased to cheap cards, creatures-heavy with a few spells,
## max 2 copies. Returned in shuffled draw order. seed_val 0 → random each match.
##
## 2026-09-16: the ceiling was 4, and its reason was "skirmish Command is a flat
## 3 + bank 2, so anything over cost 4 is near-unplayable". Both halves of that
## are now false — Command ramps to COMMAND_RAMP_CAP, and the cost rescale moved
## the pool onto a 1-6 curve where 34 draftable cards sit at 5 or 6. Left at 4,
## the bot would simply never field the top two tiers of the game's content, and
## nothing would have reported it: a deck filter that silently empties is
## invisible to every gate that only asks whether the bot played SOMETHING.
##
## The cheap BIAS is still right and still there — `_cheaper_of` samples two and
## keeps the cheaper — but that shapes a curve rather than truncating it.
func build_deck(seed_val: int = 0) -> Array:
	rng.seed = seed_val if seed_val != 0 else (int(Time.get_unix_time_from_system()) ^ randi())
	var creatures: Array = []
	var spells: Array = []
	var legal_pool := SkirmishState.skirmish_legal_pool()
	var source_pool := SkirmishState.deal_weighted_cards(legal_pool,
		mini(legal_pool.size(), SkirmishState.DECK_TARGET * 3), rng,
		SkirmishState.SKIRMISH_DRAFT_WEIGHTS)
	if source_pool.size() < SkirmishState.DECK_TARGET:
		source_pool = legal_pool
	for id in source_pool:
		var d: Dictionary = CardDB.get_card_data(id)
		if int(d.get("cost", 99)) > BoardEval.RAMP_CAP_ASSUMED:
			continue
		match String(d.get("type", "")):
			"creature": creatures.append(id)
			"spell": spells.append(id)

	var deck: Array = []
	var counts: Dictionary = {}
	var available_creatures: Array = creatures.duplicate()
	var available_spells: Array = spells.duplicate()
	var spell_cap := 5
	var spells_added := 0
	var guard := 0
	while deck.size() < SkirmishState.DECK_TARGET and guard < 8000:
		guard += 1
		var take_spell := (not available_spells.is_empty()) \
			and spells_added < spell_cap and rng.randf() < 0.22
		var src: Array = available_spells if take_spell else available_creatures
		if src.is_empty():
			if not available_creatures.is_empty():
				src = available_creatures
				take_spell = false
			else:
				src = available_spells
				take_spell = true
		if src.is_empty():
			break
		var id: String = _pick_cheap(src)
		if int(counts.get(id, 0)) >= 2:
			continue
		counts[id] = int(counts.get(id, 0)) + 1
		deck.append(id)
		src.erase(id)
		if take_spell:
			spells_added += 1
	# Degenerate tiny-pool guard: only now allow second copies.
	var pad_guard := 0
	while deck.size() < SkirmishState.DECK_TARGET and pad_guard < 4000 \
			and not creatures.is_empty():
		pad_guard += 1
		var pad_id: String = creatures[rng.randi() % creatures.size()]
		if int(counts.get(pad_id, 0)) >= 2:
			continue
		counts[pad_id] = int(counts.get(pad_id, 0)) + 1
		deck.append(pad_id)
	_shuffle(deck)
	# THE BRAIN'S SELF-PLAY NEEDS REAL CARDS. Its acceptance test plays the
	# challenger against the champion on simulated boards, and a pool invented
	# inside `BotBrain` would train it on a game this one does not contain — so
	# the bot hands over the deck it is about to play with. This is also the
	# only place in the flow that names `CardDB`, which `BotBrain` may not.
	var pool: Array = []
	for id in deck:
		pool.append(SkirmishState.skirmish_card_data(id))
	BotBrain.begin_game(pool)
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
	# THE TURN IS SCORED AGAINST A WORKING SNAPSHOT, NOT THE LIVE BOARD (2026-09-15).
	# It used to score against `ctx` with a hand-kept 2×4 occupancy grid patched
	# over it, because the plays chosen earlier in the same turn are still only
	# INTENTS and the board does not show them yet. That grid knew a slot was
	# TAKEN but not by WHAT — so every play after the first was reasoning about a
	# board with holes in it: the back-row shelter test could not see the wall the
	# bot had just committed in front, and the block arithmetic could not see its
	# own new front line. A snapshot with the committed plays applied answers both,
	# and it is the same object the recorder stores, so the board the decision was
	# made on is exactly the board the post-game analysis replays.
	var snap: BoardSim.SimCtx = BoardSim.capture(ctx)
	var guard := 0
	while guard < 30 and budget > 0 and not avail.is_empty():
		guard += 1
		var best := _best_play(snap, avail, budget)
		if best.is_empty():
			break
		intents.append(best["intent"])
		budget -= int(best["cost"])
		avail.erase(best["card"])
		snap = BoardSim.apply_play(snap, BoardSim.SIDE_ENEMY, best["play"])
	return intents


## Evaluate every affordable card and return the single highest-scoring play, or {}.
##
## It also hands the WHOLE SLATE to `BotBrain` — every play that was legal here,
## not just the winner. A counterfactual needs the road not taken: without the
## alternatives there is nothing to compare the choice against, and "learn from
## your mistakes" degenerates into "do more of whatever you did while winning".
func _best_play(snap: BoardSim.SimCtx, avail: Array, budget: int) -> Dictionary:
	var datas: Array = []
	for card in avail:
		datas.append(card.get("data", {}))
	# The bot plays the `is_enemy` side of the board — that is the ONE thing that
	# differs from the pilot's call, and it is a parameter rather than a second
	# copy of the scorer. See BoardEval's header.
	var slate: Dictionary = BotBrain.enumerate_slate(snap, true, datas, budget)
	var cands: Array = slate["cands"]
	var chosen := int(slate["chosen"])
	BotBrain.record_decision(snap, true, cands, chosen)

	var play: Dictionary = cands[chosen]
	var idx := int(play.get("idx", -1))
	if idx < 0:
		return {}    # the slate chose to hold — nothing to seat this step
	var card: Dictionary = avail[idx]
	var cost := int(play.get("cost", 0))
	if String(play["kind"]) == "creature":
		return {
			"intent": {"t": NetMatch.IN_PLAY_CREATURE, "id": String(card["id"]),
				"uid": int(card["uid"]), "lane": play["lane"], "row": play["row"]},
			"cost": cost, "card": card, "play": play,
		}
	var tgt: Variant = play.get("target")
	var tid := -1
	# The target is a body on the WORKING SNAPSHOT, so it answers `entity_id`
	# only when it was captured off a live Card2D. A snapshot-only body (one the
	# bot itself seated earlier this turn) has none, and -1 is the game's own
	# "no specific target" value.
	if tgt != null and is_instance_valid(tgt) and tgt.get("entity_id") != null:
		tid = int(tgt.entity_id)
	return {
		"intent": {"t": NetMatch.IN_PLAY_SPELL, "id": String(card["id"]),
			"uid": int(card["uid"]), "target": tid},
		"cost": cost, "card": card, "play": play,
	}


# ── THE MATCH IS OVER: go back over it and learn ─────────────────────────────
#    Called from `CombatNet._net_show_result`, which is the one place that knows
#    a draw from a win. The bot is slot 1 → its board is the "enemy" side; the
#    human host is slot 0 → the "player" side, so a win for slot 1 is a win here.

func on_match_over(winner_index: int) -> Dictionary:
	return BotBrain.on_game_over(winner_index == 1)


func brain_summary() -> String:
	return BotBrain.summary()
