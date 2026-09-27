extends Node
## _probe_card_value.gd — WHAT IS THIS CARD WORTH, AND WHEN?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_card_value.tscn
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_card_value.tscn -- --boards=40 --top=30
##
## Runs as a SCENE because it reads CardDB, which is an autoload.
##
## ── WHAT IT MEASURES ──────────────────────────────────────────────────────
## Not "how big are its numbers" — what it is WORTH ON A BOARD. For each card,
## against many sampled positions:
##
##     value = rollout(position WITH the card played) - rollout(position without)
##
## i.e. the card's MARGINAL contribution, in BoardSim's own units, judged three
## rounds deep by the same scorer the bot plays with. Creatures are tried in every
## empty slot and keep their best placement, because "where it goes" is part of
## what a card is worth.
##
## ── THE COLUMN THAT MATTERS FOR BALANCE: SWING ────────────────────────────
## Every position is sampled in three bands — BEHIND, EVEN, AHEAD — and the table
## reports each separately plus
##
##     swing = value(behind) - value(ahead)
##
## **Positive swing = a comeback card** (worth more when you are losing).
## **Negative swing = a snowball card** (worth more when you are already winning).
##
## That is the direct instrument for "the game is ridiculously snowbally": if the
## pool's swing distribution sits almost entirely negative, the CARDS are part of
## the feedback loop, not just the combat rules. A healthy pool needs cards a
## losing player actively wants.
##
## ── HONESTY RULES BUILT IN ────────────────────────────────────────────────
## · **Unmodelled cards are reported, never scored as weak.** BoardSim implements
##   a subset of the 52 spell effect types; anything whose play leaves the board
##   bit-identical is marked UNMODELLED and excluded from the rankings. Scoring
##   those as 0.0 would quietly rank most of the spell pool as worthless, which is
##   the exact "0% clash damage" shape of error this harness keeps paying for.
## · **Weights are PINNED to the shipped constants** (`BoardEval.reset_weights`).
##   A half-trained `user://bot_brain.json` must not set card values — the trainer
##   itself reports its gain is still inside 2 sigma.
## · Values are BoardSim's opinion, not the engine's. BoardSim agrees with the
##   real clash on 1920/1920 slots but is blind to triggers, relics and encounter
##   passives, so a card whose whole point is a trigger will under-read. That is a
##   floor on its value, not a verdict.

const BoardSim = preload("res://scripts/combat/BoardSim.gd")
const BoardEval = preload("res://scripts/combat/BoardEval.gd")

const SIDE_PLAYER := 0
const SIDE_ENEMY := 1
const ROW_FRONT := 0
const ROW_BACK := 1
const LANES := 4

var _boards: int = 24        # sampled positions per band
var _top: int = 24           # rows to print per table
var _seed: int = 20260916
var _horizon: int = 3

var _rng := RandomNumberGenerator.new()
var _pool: Array = []        # creature entries used to furnish sampled boards


func _ready() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boards="):
			_boards = maxi(2, int(a.substr(9)))
		elif a.begins_with("--top="):
			_top = maxi(1, int(a.substr(6)))
		elif a.begins_with("--seed="):
			_seed = int(a.substr(7))
		elif a.begins_with("--horizon="):
			_horizon = clampi(int(a.substr(10)), 1, 6)


# =========================================================================
#  SCENARIO BANK
# =========================================================================

## A board is sampled, not authored. Authored fixtures measure the fixture; a
## seeded sample over the real card pool measures the GAME, and re-running with a
## different --seed is how you check a ranking is not an artifact of one board.
##
## `band` sets the gap the card has to act on:
##   behind → the foe outnumbers you and is bigger
##   even   → matched
##   ahead  → you outnumber them
func _sample_board(band: String) -> BoardSim.SimCtx:
	var c := BoardSim.SimCtx.new()
	var mine := 0
	var theirs := 0
	match band:
		"behind":
			mine = _rng.randi_range(0, 1)
			theirs = _rng.randi_range(3, 5)
			c.player_hp = _rng.randi_range(18, 26)
			c.enemy_hp = _rng.randi_range(24, 30)
		"even":
			mine = _rng.randi_range(2, 3)
			theirs = _rng.randi_range(2, 3)
			c.player_hp = _rng.randi_range(22, 30)
			c.enemy_hp = _rng.randi_range(22, 30)
		_:
			mine = _rng.randi_range(3, 5)
			theirs = _rng.randi_range(0, 1)
			c.player_hp = _rng.randi_range(24, 30)
			c.enemy_hp = _rng.randi_range(18, 28)
	c.player_max_hp = 30
	c.enemy_max_hp = 30
	# Heroes are kept healthy on purpose: a position that dies inside the horizon
	# saturates `evaluate` and stops being a measurement (see _value_on).
	_furnish(c, SIDE_PLAYER, mine)
	_furnish(c, SIDE_ENEMY, theirs)
	return c


func _furnish(c: BoardSim.SimCtx, side: int, n: int) -> void:
	var placed := 0
	var guard := 0
	while placed < n and guard < 40:
		guard += 1
		var row: int = ROW_FRONT if placed < LANES else ROW_BACK
		var lane: int = _rng.randi_range(0, LANES - 1)
		if c.at(side, row, lane) != null:
			continue
		var data: Dictionary = _pool[_rng.randi_range(0, _pool.size() - 1)]
		# `arrived = false` → already mustered. A sampled board is mid-fight, so
		# the bodies standing on it have had a round to form up; leaving them
		# unready would make every position read as safer than it is.
		c.put(side, row, lane, BoardSim.body_from_data(data, false))
		placed += 1


# =========================================================================
#  VALUATION
# =========================================================================

## The card's marginal worth on one position: best placement, minus doing nothing.
## Returns {"val": float, "touched": bool} — `touched` false means BoardSim did
## not model this card at all (see the honesty rules in the header).
## A SATURATING SENTINEL IS NOT A VALUE, and the first cut of this measured
## almost nothing else. `BoardSim.evaluate` returns ±LETHAL (1000) the moment a
## hero dies inside the rollout — so on any position that resolves within the
## horizon, `best - base` is a ~700-point jump that says only "this flipped the
## binary". Unrelated cards scored identically (Live Coal 698.26, Assassin
## 698.32, The Bravo 698.17) because they were all flipping the same coin.
##
## Two separate questions, so two separate numbers:
##   · CONTINUOUS value is measured only on positions that stay LIVE for the
##     whole horizon — there the units are stat points and cards are comparable.
##   · "Does it CLOSE the game" is counted, not averaged, as `close`.
## A board already decided before the card is played is discarded outright: it
## can teach nothing about the card.
const SATURATED := 900.0


func _value_on(c: BoardSim.SimCtx, data: Dictionary) -> Dictionary:
	var base := BoardSim.rollout(c, SIDE_PLAYER, _horizon)
	if absf(base) >= SATURATED:
		return {"val": 0.0, "touched": false, "live": false, "close": false}
	var best := -INF
	var best_live := -INF
	var closes := false
	var touched := false
	var is_spell := String(data.get("type", "creature")) == "spell"

	if is_spell:
		for play in _spell_plays(c, data):
			var w: BoardSim.SimCtx = BoardSim.apply_play(c, SIDE_PLAYER, play)
			if not _same_state(c, w):
				touched = true
			var v := BoardSim.rollout(w, SIDE_PLAYER, _horizon)
			if v >= SATURATED:
				closes = true
			elif v > best_live:
				best_live = v
			if v > best:
				best = v
	else:
		for row in [ROW_FRONT, ROW_BACK]:
			for lane in LANES:
				if c.at(SIDE_PLAYER, row, lane) != null:
					continue
				var w: BoardSim.SimCtx = BoardSim.apply_play(c, SIDE_PLAYER,
					{"kind": "creature", "data": data, "row": row, "lane": lane})
				if not _same_state(c, w):
					touched = true
				var v := BoardSim.rollout(w, SIDE_PLAYER, _horizon)
				if v >= SATURATED:
					closes = true
				elif v > best_live:
					best_live = v
				if v > best:
					best = v
	if best == -INF:
		return {"val": 0.0, "touched": false, "live": false, "close": false}
	if best_live == -INF:
		# Every legal play ended the fight — real, but not a continuous reading.
		return {"val": 0.0, "touched": touched, "live": false, "close": closes}
	return {"val": best_live - base, "touched": touched, "live": true,
		"close": closes}


## Every target a spell might sensibly want, so a targeted card is judged on its
## BEST use rather than an arbitrary one.
func _spell_plays(c: BoardSim.SimCtx, data: Dictionary) -> Array:
	var out: Array = [{"kind": "spell", "data": data, "target": null}]
	for side in [SIDE_ENEMY, SIDE_PLAYER]:
		for row in [ROW_FRONT, ROW_BACK]:
			for lane in LANES:
				if c.at(side, row, lane) != null:
					out.append({"kind": "spell", "data": data,
						"target": Vector3i(side, row, lane)})
	return out


## Did the play change anything at all? Used only to detect UNMODELLED cards.
func _same_state(a: BoardSim.SimCtx, b: BoardSim.SimCtx) -> bool:
	if a.player_hp != b.player_hp or a.enemy_hp != b.enemy_hp:
		return false
	for side in 2:
		for row in 2:
			for lane in LANES:
				var x: BoardSim.SimBody = a.at(side, row, lane)
				var y: BoardSim.SimBody = b.at(side, row, lane)
				if (x == null) != (y == null):
					return false
				if x != null and (x.atk != y.atk or x.current_hp != y.current_hp):
					return false
	return true


# =========================================================================
#  RUN
# =========================================================================

func _run() -> void:
	var db := get_node_or_null("/root/CardDB")
	if db == null:
		print("CardDB missing — the project does not compile.")
		get_tree().quit(1)
		return

	# PINNED. A learned brain must not decide what a card is worth.
	BoardEval.reset_weights()
	_rng.seed = _seed

	var pool: Dictionary = db.CARD_POOL
	var cards: Array = []
	for id in pool:
		var d: Dictionary = pool[id]
		var rarity := String(d.get("rarity", ""))
		if rarity == "enemy" or bool(d.get("draftable", true)) == false:
			continue
		if db.has_method("is_curse") and bool(db.call("is_curse", String(id))):
			continue
		cards.append(d)
		if String(d.get("type", "creature")) == "creature":
			_pool.append(d)
	if _pool.is_empty():
		print("no creatures to furnish boards with")
		get_tree().quit(1)
		return

	print("╔════════════════════════════════════════════════════════════════╗")
	print("║  CARD VALUE — marginal worth on sampled boards                  ║")
	print("╚════════════════════════════════════════════════════════════════╝")
	print("  %d cards · %d boards/band · horizon %d · seed %d · weights PINNED" % [
		cards.size(), _boards, _horizon, _seed])

	# One bank per band, SHARED by every card — so two cards are compared on the
	# same positions and the difference between them is the card, not the deal.
	var bank: Dictionary = {}
	for band in ["behind", "even", "ahead"]:
		var list: Array = []
		for i in _boards:
			list.append(_sample_board(band))
		bank[band] = list

	var rows: Array = []
	var unmodelled: Array = []
	for d in cards:
		var per: Dictionary = {}
		var touched_any := false
		var closes := 0
		var live_total := 0
		for band in ["behind", "even", "ahead"]:
			var sum := 0.0
			var n := 0
			for c in bank[band]:
				var r := _value_on(c, d)
				if bool(r["touched"]):
					touched_any = true
				if bool(r["close"]):
					closes += 1
				if not bool(r["live"]):
					continue
				sum += float(r["val"])
				n += 1
			live_total += n
			per[band] = (sum / float(n)) if n > 0 else 0.0
		var cost: int = maxi(int(d.get("cost", 1)), 1)
		var mean: float = (float(per["behind"]) + float(per["even"])
			+ float(per["ahead"])) / 3.0
		var rec := {
			"name": String(d.get("name", "?")),
			"id": String(d.get("id", "?")),
			"cost": cost,
			"type": String(d.get("type", "creature")),
			"behind": float(per["behind"]), "even": float(per["even"]),
			"ahead": float(per["ahead"]),
			"mean": mean, "per_cmd": mean / float(cost),
			"swing": float(per["behind"]) - float(per["ahead"]),
			"close": closes, "live": live_total,
		}
		# A CREATURE WHOSE WHOLE POINT IS A TRIGGER IS NOT A WEAK CREATURE —
		# it is an unmeasured one, and `touched` cannot tell the difference because
		# PLACING ANY BODY changes the board. That is why every armament and
		# Grave-Goods scored an identical 3.20/3.54/0.75: BoardSim seated them as
		# near-empty bodies and their real text never ran. Flag them so the
		# "weakest" table cannot be read as a balance verdict.
		rec["partial"] = false
		for k in ["on_enter", "on_death", "on_play", "floop", "passive", "adj_buff"]:
			if d.has(k):
				rec["partial"] = true
				break
		if String(d.get("type", "")) == "armament":
			rec["partial"] = true
		if touched_any:
			rows.append(rec)
		else:
			unmodelled.append(rec)

	_print_table("STRONGEST (value per Command)", rows, "per_cmd", true)
	var solid: Array = []
	for r in rows:
		if not bool(r.get("partial", false)):
			solid.append(r)
	_print_table("WEAKEST (value per Command) — vanilla bodies only, triggers excluded",
		solid, "per_cmd", false)
	_print_table("COMEBACK CARDS — worth MORE when behind (swing > 0)", rows,
		"swing", true)
	_print_table("SNOWBALL CARDS — worth more when AHEAD (swing < 0)", rows,
		"swing", false)

	var pos := 0
	var swing_sum := 0.0
	for r in rows:
		if float(r["swing"]) > 0.0:
			pos += 1
		swing_sum += float(r["swing"])
	print("")
	print("  ── THE SNOWBALL READING ──────────────────────────────────────")
	print("    cards worth MORE when behind : %d of %d  (%.0f%%)" % [
		pos, rows.size(), 100.0 * float(pos) / float(maxi(rows.size(), 1))])
	print("    mean swing across the pool   : %+.2f  (negative = the pool itself" % [
		swing_sum / float(maxi(rows.size(), 1))])
	print("                                    rewards the player already winning)")
	print("")
	var partial := 0
	for r in rows:
		if bool(r.get("partial", false)):
			partial += 1
	print("    NOTE: %d of the %d scored cards carry a trigger BoardSim does not" % [
		partial, rows.size()])
	print("          model (on_enter / on_death / floop / passive / armament).")
	print("          Their number is a FLOOR on their value, never a verdict.")
	print("")
	print("  UNMODELLED by BoardSim (NOT scored, NOT weak): %d cards" % unmodelled.size())
	var names: Array = []
	for r in unmodelled:
		names.append(String(r["name"]))
	names.sort()
	print("    %s" % ", ".join(PackedStringArray(names)).substr(0, 900))
	print("")
	print("CARD_VALUE: %d scored, %d unmodelled" % [rows.size(), unmodelled.size()])
	get_tree().quit(0)


func _print_table(title: String, rows: Array, key: String, desc: bool) -> void:
	var sorted: Array = rows.duplicate()
	sorted.sort_custom(func(a, b):
		return float(a[key]) > float(b[key]) if desc else float(a[key]) < float(b[key]))
	print("")
	print("  ── %s ──" % title)
	print("    %-26s %4s %-8s %7s %7s %7s %7s %7s %6s" % [
		"card", "cost", "type", "behind", "even", "ahead", "mean", "swing", "close"])
	for i in mini(_top, sorted.size()):
		var r: Dictionary = sorted[i]
		print("    %-26s %4d %-8s %7.2f %7.2f %7.2f %7.2f %+7.2f %6d" % [
			String(r["name"]).substr(0, 26), int(r["cost"]),
			String(r["type"]).substr(0, 8),
			float(r["behind"]), float(r["even"]), float(r["ahead"]),
			float(r["mean"]), float(r["swing"]), int(r["close"])])
		if bool(r.get("partial", false)):
			pass
