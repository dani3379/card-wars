extends RefCounted
## BotBrain — THE BOT LEARNS FROM THE GAME IT JUST LOST.
##
## `BoardEval` scores a play by looking at the board as it stands: one ply, hand-
## picked weights, no idea what happens next. This file closes the loop around
## it. During a match it records every decision the bot faced — the board, every
## play it COULD have made, and the one it did. When the match ends it goes back
## over those decisions with a deeper look (`BoardSim.rollout`), works out what
## the best play would actually have been, and nudges the scorer's weights so
## that next time the shallow judgement agrees with the deep one.
##
## ── WHERE THIS COMES FROM ────────────────────────────────────────────────
## Four established ideas, each doing a job the others cannot:
##
##  1. SEARCH BOOTSTRAPPING (Veness, Silver, Uther & Blair, NeurIPS 2009,
##     "Bootstrapping from Game Tree Search" — RootStrap/TreeStrap; the lineage
##     runs back through Samuel's 1959 checkers player and Baxter's TDLeaf).
##     The training signal is NOT the final result of the game, it is the value
##     a DEEPER SEARCH assigned to the position. That is the core move here: a
##     3-round rollout is slow but better informed than a one-ply score, so the
##     one-ply score is trained toward it. It gives a dense signal — every
##     decision teaches something — where win/loss gives one bit per game.
##
##  2. COUNTERFACTUAL REGRET (Zinkevich et al.; the CFR family behind Libratus).
##     "How much better would I have done had I chosen differently?" Here the
##     regret of a decision is `rollout(best_alternative) − rollout(chosen)`,
##     measured in stat points, and it SCALES the correction: a decision that
##     cost a third of a point is noise, one that cost eight points is a blunder
##     and is worth moving the weights for. This is the only reason the learner
##     spends its budget on mistakes instead of on every routine play.
##
##  3. OUTCOME WEIGHTING (Texel's tuning, the standard chess-engine practice of
##     fitting eval weights against real game results). The rollout can be
##     wrong; the scoreboard cannot. The final result scales the step, so games
##     that were actually lost teach harder than games that were won.
##
##  4. SELF-PLAY HILL CLIMBING WITH AN ACCEPTANCE TEST (the backgammon
##     self-playing hill-climber; evolution strategies for CCG evaluators).
##     THIS IS THE SAFETY PROPERTY AND IT IS NOT OPTIONAL. Everything above is
##     gradient-following against an approximate model, which is a machine for
##     drifting somewhere confident and wrong. So learning does not touch the
##     weights the bot plays with. It accumulates into a CHALLENGER, and the
##     challenger only becomes the CHAMPION after it beats the champion over a
##     batch of simulated games. If it loses, it is thrown away and the
##     champion stands. A learner with no acceptance test has no way to notice
##     it has made the bot worse — and neither does anyone else.
##
## ── WHAT IT CANNOT DO, STATED UP FRONT ───────────────────────────────────
## This tunes THIRTEEN NUMBERS in an evaluation function. It does not discover
## strategy, it cannot learn a card's text, and it will never learn to hold a
## trick for two turns — none of that is representable in the weight vector. Nor
## are all thirteen live: measured over the real skirmish pool, `card`,
## `command` and `back_exposed` never change a single decision there, because
## nothing in a creature placement reads them. They are not dead code (a
## draw/gain-mana spell would read the first two) but they are not being learned.
##
## AND THE MEASUREMENT IS IN THE MODEL, NOT THE GAME. Training and evaluation
## both run on `BoardSim`, so "the trained bot beats the shipped bot 0.81" means
## *according to BoardSim*. Anything the sim does not model — on-enter and
## on-death triggers, relics, encounter passives, the 52 spell effect types
## against the dozen it knows — is a way for that number to be optimistic. Two
## things bound it: `_probe_bot_brain` phase A pins the sim's clash to the rules
## the real engine states, and the clamp band stops any weight travelling far
## enough to be catastrophic if the model is wrong. It is a bound, not a proof.
##
## ── AUTOLOAD RULE ────────────────────────────────────────────────────────
## Plain RefCounted, preloaded by `--script` probes: it may not name an autoload.
## Everything it needs arrives as an argument or is read off disk directly.

const BoardEval = preload("res://scripts/combat/BoardEval.gd")
const BoardSim = preload("res://scripts/combat/BoardSim.gd")

const SAVE_PATH := "user://bot_brain.json"
## 2 (2026-09-16): THE ECONOMY UNDERNEATH THE WEIGHTS CHANGED.
##
## A champion vector is not data about this file, it is data about the GAME it
## was trained on — and that game no longer exists. The Command ramp replaced a
## flat 3, the draw became a fixed 2, and the cost curve was rescaled from 0-5
## to 1-6, which moves 173 of 236 cards. Every gradient step in a brain on disk
## was justified by a rollout under those old rules, so carrying one forward is
## not "a head start", it is a bot confidently playing the previous build.
##
## The version guard already does the right thing with a mismatch — `_read_disk`
## returns early and the weights stay the shipped constants — so bumping this is
## the whole invalidation. Nothing is deleted: an old file is simply ignored, and
## the safety property holds (a fresh profile IS the shipped vector).
##
## BUMP THIS whenever a balance change moves what a rollout would conclude, not
## just when this file's SHAPE changes. A shape-only guard would have let the
## stale vector through here, which is exactly the failure worth naming.
## 2 -> 3 on 2026-09-19: `BoardEval` gained a fourteenth weight (`deny`, what a
## closed lane is worth) and corrected two placement rules the scorer had never
## modelled — a body in a column denies the FACE, and the back row reaches it
## through a clear one. A champion trained before that was fitted against a
## scorer that could not see either, so its vector is a set of answers to a
## question the game no longer asks.
const SAVE_VERSION := 3

## How far the retrospective look searches. Kept at BoardSim's default for one
## reason: past ~3 rounds the "nobody plays another card" assumption dominates
## the answer, and a confident number from a wrong model is worse than a vague
## one from an honest model.
const HORIZON := BoardSim.DEFAULT_HORIZON
## Regret below this is not a mistake, it is two reasonable plays. Moving weights
## for it fits noise.
const REGRET_FLOOR := 0.75
## Base step size. Raised from 0.010 on 2026-09-15 after measuring what the
## timid version achieved: over 120 self-play games it moved the HP weight by
## about 4% — in the RIGHT direction, confirmed by a sensitivity sweep, but
## nowhere near far enough to matter, while the acceptance test threw most of it
## away. A step so small that no test can see it is not caution, it is a learner
## that cannot learn.
const LEARN_RATE := 0.055
## A loss teaches harder than a win. Both teach — a won game still contains
## blunders, and throwing those away is how a learner overfits to "whatever I
## did while winning".
const WEIGHT_ON_LOSS := 1.5
const WEIGHT_ON_WIN := 0.7
## Finite-difference step for the margin gradient. Large enough to clear float
## noise on scores of order 10, small enough to stay local.
const GRAD_H := 0.05
## Per-game clamp on how far any single weight may travel, as a fraction of
## itself. One game is not evidence enough to move a weight by half.
const MAX_STEP_FRAC := 0.15
## Hard band every weight lives in, as a multiple of its shipped default. A
## learner that can reach zero can delete a consideration outright, and one that
## can reach twenty can make a single term swamp the sum.
const CLAMP_LO := 0.25
const CLAMP_HI := 4.00

## The acceptance test. Every N games, the challenger plays the champion.
const TRIAL_EVERY := 5
## A `static var` so an offline trainer can run a decisive batch; see
## `trial_budget_ms` for why the in-game figure is the small one.
static var trial_games := 24
## Fewer DECISIVE PAIRS than this and the trial has no verdict either way — it
## keeps testing. A 3-pair verdict is not a verdict.
const TRIAL_MIN_GAMES := 8
## THE TEST IS SEQUENTIAL. One in-game batch is 12 duplicate pairs, and only the
## pairs where the two brains actually diverged count for anything — typically a
## quarter of them — so batches ACCUMULATE against a FROZEN challenger until the
## evidence crosses a bound or this cap of DECISIVE PAIRS is reached. At 60 the
## bar is 30 + √60 ≈ 38, i.e. 63%, and a hypothesis resolves inside roughly
## twenty played games.
const TRIAL_MAX_PAIRS := 60
## How many standard deviations a challenger must clear before the trial calls
## it. Two is the usual bar and it is not a decoration:
##
## THE FIRST VERSION OF THIS WAS A FLAT 56% OVER 24 GAMES, AND THAT IS NOISE.
## Under the null hypothesis (challenger exactly as good as champion) the win
## count is Binomial(24, ½) with a standard deviation of 2.45, so 56% is barely
## 0.6σ out and clears by chance **about one trial in four**. The probe caught
## it the only way such a thing is ever caught — an IDENTICAL challenger, which
## cannot be better by construction, was promoted at 0.67. A hill climber that
## accepts noise a quarter of the time is not climbing, it is drifting, and
## every generation counter it prints is a lie about progress.
##
## The threshold is derived from the number of DECISIVE PAIRS actually recorded
## rather than fixed, because the in-game trial runs under a wall-clock budget
## and most pairs tie: n/2 + σ·√n·½ wins. Ten pairs can only ever prove a large
## effect, and this says so instead of pretending otherwise.
const TRIAL_SIGMA := 2.0
## Wall-clock ceiling for a trial. It runs at the verdict screen, where the
## player is watching a ceremony; a learner is never allowed to be the reason a
## frame is late. A `static var` rather than a const so an OFFLINE trainer can
## lift it — that budget exists to protect a frame, and a headless training run
## has no frame to protect.
static var trial_budget_ms := 70

## Sim-game rules, matching skirmish: flat Command, refill-to-5 hand.
const SIM_MANA := 3
const SIM_BANK := 2
const SIM_HAND := 5
const SIM_HERO_HP := 30


# ── STATE. Static, so it survives the scene changes between one match and the
#    next without needing an autoload of its own. ──────────────────────────
static var champion: Dictionary = {}
static var challenger: Dictionary = {}
static var stats: Dictionary = {}
static var _loaded := false
## This game's decisions, cleared at the start of each match.
static var _records: Array = []
## Card data the sim driver may deal from. The bot's own deck, cached at match
## start — this file may not name CardDB, and a pool invented here would train
## the brain on cards the game does not contain.
static var _pool: Array = []
## Last analysis, for the probes and for anyone who wants to look.
static var last_report: Dictionary = {}
## The standing trial: a FROZEN copy of the challenger plus its running record.
## See `run_trial` — evidence accumulated against a moving target is not evidence.
static var _under_test: Dictionary = {}
static var _trial_played := 0
static var _trial_wins := 0
## Learning can be switched off wholesale without touching a call site.
static var enabled := true


# =========================================================================
#  LIFECYCLE
# =========================================================================

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	champion = BoardEval.default_weights()
	challenger = champion.duplicate()
	stats = {"games": 0, "wins": 0, "promotions": 0, "reverts": 0,
		"inconclusive": 0, "generation": 0, "blunders": 0}
	_read_disk()
	# THE BOT PLAYS THE CHAMPION, ALWAYS. The challenger is an untested
	# hypothesis; putting it on the board would make every match an experiment
	# the player did not agree to run.
	BoardEval.apply_weights(champion)


## Call at the top of a match. `pool` is the card data the sim driver deals from.
static func begin_game(pool: Array = []) -> void:
	ensure_loaded()
	_records.clear()
	if not pool.is_empty():
		_pool = pool
	BoardEval.apply_weights(champion)


## Record one decision: the board as it stood, every play that was available,
## and which one was taken.
##
## `cands` is an Array of {data, kind, lane, row, target, score}, where `target`
## is a LIVE NODE (what BoardEval returns) and is converted here to a board
## coordinate. THAT CONVERSION IS THE WHOLE REASON THIS TAKES A SNAPSHOT AT ALL:
## analysis runs after the match, when every node in it has been freed. A record
## holding node references is a record that cannot be replayed.
## `ctx` may be a live Combat OR an already-built `BoardSim.SimCtx` — the bot
## hands in the latter, because it scores its whole turn against a working
## snapshot with its own committed plays applied, and re-capturing that through
## the live board would throw away exactly the part it needs.
static func record_decision(ctx, mine_is_enemy: bool, cands: Array,
		chosen: int) -> void:
	if not enabled or ctx == null or cands.is_empty():
		return
	ensure_loaded()
	var snap: BoardSim.SimCtx = (ctx as BoardSim.SimCtx).clone() \
		if ctx is BoardSim.SimCtx else BoardSim.capture(ctx)
	var plays: Array = []
	for c in cands:
		var cd: Dictionary = c
		# POOL FALLBACK. `begin_game` is normally handed the bot's deck, but the
		# bot's deck does not always come through `build_deck` (a constructed or
		# sealed drill supplies one), and a brain with no pool can never run its
		# acceptance test — so the cards it is actually being offered are
		# harvested here. Deduped by id, because a candidate slate repeats.
		var cdata: Dictionary = cd.get("data", {})
		if _pool.size() < 40 and not cdata.is_empty() and not _pool.has(cdata):
			_pool.append(cdata)
		plays.append({
			"data": cd.get("data", {}),
			"kind": String(cd.get("kind", "creature")),
			"lane": int(cd.get("lane", -1)),
			"row": int(cd.get("row", BoardSim.ROW_FRONT)),
			"target": _locate(ctx, cd.get("target", null)),
			"score": float(cd.get("score", 0.0)),
		})
	_records.append({
		"snap": snap,
		"side": BoardSim.SIDE_ENEMY if mine_is_enemy else BoardSim.SIDE_PLAYER,
		"cands": plays,
		"chosen": clampi(chosen, 0, plays.size() - 1),
	})


## Where on the board is this node? Returns a Vector3i(side, row, lane), or a
## null when the node is not on the board (an untargeted spell, most often).
static func _locate(ctx, node: Variant) -> Variant:
	if node == null or ctx == null or not is_instance_valid(node):
		return null
	if not ctx.has_method("_row_array"):
		return null
	for side in 2:
		for row in 2:
			var arr: Variant = ctx.call("_row_array", side == BoardSim.SIDE_ENEMY, row)
			if not (arr is Array):
				continue
			var a: Array = arr
			for lane in a.size():
				if a[lane] == node:
					return Vector3i(side, row, lane)
	return null


# =========================================================================
#  THE SLATE — what are my options here, and which one scores best?
# =========================================================================

## Score every affordable card and return the whole slate plus the winner.
##
## ONE IMPLEMENTATION, TWO CALLERS, and that is deliberate. `SkirmishBot` runs it
## on a live match and the sim driver below runs it thousands of times in a
## trial. Written twice they would be two definitions of "what the bot considers"
## with nothing comparing them — so a training run would tune the weights for a
## slate the real bot never sees. It is the same reasoning that put the scoring
## in `BoardEval` in the first place; see that file's header.
##
## `datas` is an Array of card-data Dictionaries. Each candidate carries `idx`,
## its position in `datas`, so a caller holding richer objects (uids, ids, hand
## slots) can map the answer back without this file knowing anything about them.
## The PASS candidate carries idx -1.
static func enumerate_slate(ctx, mine_is_enemy: bool, datas: Array,
		budget: int) -> Dictionary:
	var cands: Array = []
	var chosen := -1
	var best_score := -1.0e9
	for i in datas.size():
		var data: Dictionary = datas[i]
		var cost := int(data.get("cost", 0))
		if cost > budget:
			continue
		var play: Dictionary = BoardEval.score_play(ctx, mine_is_enemy, data)
		if play.is_empty():
			continue
		# A spell BoardEval cannot evaluate is HELD, not dumped — dumping it for
		# nothing is how a bot throws a game away.
		if not bool(play.get("known", true)):
			continue
		# Mild cheap-first nudge so a 1-drop edges out an equal-scored 3-drop.
		var score: float = float(play["score"]) - float(cost) * 0.15
		cands.append({"data": data, "kind": String(play["kind"]),
			"lane": int(play.get("lane", -1)), "row": int(play.get("row", 0)),
			"target": play.get("target", null), "score": score,
			"cost": cost, "idx": i})
		if score > best_score:
			best_score = score
			chosen = cands.size() - 1
	# PASSING IS ON THE SLATE. Holding is a real option with a real consequence,
	# and it is the one taken whenever nothing scores — so it has to be learnable
	# too, or a board where waiting was right teaches nothing at all.
	cands.append({"data": {}, "kind": "pass", "lane": -1, "row": -1,
		"target": null, "score": 0.0, "cost": 0, "idx": -1})
	# Only act on a play with POSITIVE expected value: an affordable spell with no
	# good target is worse than the Command it costs.
	if chosen < 0 or best_score <= 0.0:
		chosen = cands.size() - 1
	return {"cands": cands, "chosen": chosen}


# =========================================================================
#  THE POST-GAME ANALYSIS
# =========================================================================

## Called once when a match ends. Works out what the bot should have played at
## every decision, moves the challenger's weights toward that judgement, and
## every `TRIAL_EVERY` games makes the challenger earn its place.
## `persist` is false only for an offline training run, which writes once at the
## end instead of once per game — a few hundred games is a few hundred rewrites
## of the same file otherwise.
static func on_game_over(won: bool, persist: bool = true) -> Dictionary:
	ensure_loaded()
	stats["games"] = int(stats.get("games", 0)) + 1
	if won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
	if not enabled or _records.is_empty():
		_records.clear()
		if persist:
			_write_disk()
		return {}

	var report := analyse(_records, won)
	_records.clear()
	stats["blunders"] = int(stats.get("blunders", 0)) + int(report.get("blunders", 0))

	# A trial ALREADY RUNNING gets another batch every game — it is sequential,
	# and leaving a half-finished record sitting for five games would mean a
	# hypothesis that is measurably bad keeps playing while the evidence waits.
	if trial_in_progress() or int(stats.get("games", 0)) % TRIAL_EVERY == 0:
		report["trial"] = run_trial()
	last_report = report
	if persist:
		_write_disk()
	# The player's bot is the champion; re-assert it in case a trial moved the
	# global weights around while it ran.
	BoardEval.apply_weights(champion)
	return report


## THE ANALYSIS PROPER. For every recorded decision: what did each candidate
## actually lead to, which was best, how much did the chosen one cost, and which
## way would the weights have to move for the scorer to have preferred it?
static func analyse(records: Array, won: bool) -> Dictionary:
	ensure_loaded()
	var w: Dictionary = challenger.duplicate()
	var saved: Dictionary = BoardEval.export_weights()
	var blunders := 0
	var total_regret := 0.0
	var worst := {}
	var worst_regret := 0.0
	var step_total: Dictionary = {}
	for n in BoardEval.WEIGHT_NAMES:
		step_total[n] = 0.0

	var outcome_scale: float = WEIGHT_ON_LOSS if not won else WEIGHT_ON_WIN

	for rec_v in records:
		var rec: Dictionary = rec_v
		var snap: BoardSim.SimCtx = rec["snap"]
		var side := int(rec["side"])
		var cands: Array = rec["cands"]
		var chosen := int(rec["chosen"])
		if cands.size() < 2:
			continue   # no alternative means no counterfactual to learn from

		# ── THE DEEPER LOOK ──────────────────────────────────────────────
		# Resolve each candidate forward and see where the board ends up. This
		# is what the one-ply scorer could not see.
		var values: Array = []
		for c_v in cands:
			var c: Dictionary = c_v
			var after: BoardSim.SimCtx = BoardSim.apply_play(snap, side, c)
			values.append(BoardSim.rollout(after, side, HORIZON))
		var best := 0
		for i in values.size():
			if float(values[i]) > float(values[best]):
				best = i
		var regret: float = float(values[best]) - float(values[chosen])
		if regret > worst_regret:
			worst_regret = regret
			worst = {"played": String((cands[chosen] as Dictionary).get("data", {})
					.get("name", "?")),
				"better": String((cands[best] as Dictionary).get("data", {})
					.get("name", "?")),
				"regret": regret}
		if regret <= REGRET_FLOOR or best == chosen:
			continue
		blunders += 1
		total_regret += regret

		# ── THE CORRECTION ───────────────────────────────────────────────
		# Which way must the weights move for the SCORER to prefer `best` over
		# `chosen`? Measured by finite differences on the ranking margin rather
		# than by hand-deriving a gradient, because the score is full of caps
		# and branches (`mini(dmg, hp)`, the chump test, the lethal sentinel) —
		# it is only piecewise linear in the weights, and a symbolic derivative
		# would be quietly wrong at exactly the interesting boundaries.
		var grad := _margin_gradient(snap, side, cands[best], cands[chosen], w)
		# Regret scales the step: a blunder moves the weights, a near-tie does
		# not. `sqrt` because regret is unbounded above (a missed lethal is
		# worth 1000) and a single such decision must not dominate a game.
		var mag: float = outcome_scale * LEARN_RATE * sqrt(minf(regret, 100.0))
		for name in BoardEval.WEIGHT_NAMES:
			step_total[name] = float(step_total[name]) + float(grad.get(name, 0.0)) * mag

	# Apply the game's accumulated step in one go, bounded. Per-decision writes
	# would let the LAST decision of a long game outweigh the first thirty.
	#
	# `atk` IS NEVER STEPPED, and that is how the gauge is held — see BoardEval's
	# W_ATK note. The first build let it move and then divided the whole vector
	# by it to re-pin the unit, which worked exactly as designed and had a
	# consequence nobody had thought through: a weight with ZERO gradient still
	# got inflated by every rescale. Over 250 games the four weights that never
	# change a decision in skirmish (card, command, kill, back_exposed) rode a
	# 3.35× cumulative rescale straight up into their clamp ceiling and STUCK
	# there — so a bot that had learned nothing whatsoever about drawing cards
	# came out valuing a draw at 6.7 stat points instead of 2.0, a latent lie
	# waiting for the first pool that contains a draw spell. Fixing the unit by
	# not moving it means no rescale ever happens on the learning path.
	for name in BoardEval.WEIGHT_NAMES:
		if name == "atk":
			continue
		var cur := float(w.get(name, 0.0))
		var lim: float = absf(cur) * MAX_STEP_FRAC
		w[name] = cur + clampf(float(step_total[name]), -lim, lim)
	challenger = normalise(w)

	BoardEval.apply_weights(saved)
	return {"decisions": records.size(), "blunders": blunders,
		"total_regret": total_regret, "worst": worst, "won": won,
		"challenger": challenger.duplicate()}


## d(margin)/dw by central differences, where margin = score(better) − score(chosen).
## A positive component means "raising this weight makes the scorer prefer the
## play the rollout liked", which is the direction to move.
static func _margin_gradient(snap: BoardSim.SimCtx, side: int, better: Dictionary,
		chosen: Dictionary, w: Dictionary) -> Dictionary:
	var grad: Dictionary = {}
	var mine_is_enemy: bool = side == BoardSim.SIDE_ENEMY
	for name in BoardEval.WEIGHT_NAMES:
		var base := float(w.get(name, 0.0))
		# `atk` IS THE GAUGE, not a parameter. It is held at 1.0 by definition
		# (see `normalise`), so measuring a derivative along it would produce a
		# step that the very next normalise throws away — and, worse, one that
		# used to drag every other weight with it on the way out.
		if name == "atk" or is_zero_approx(base):
			grad[name] = 0.0
			continue
		var up: Dictionary = w.duplicate()
		up[name] = base + GRAD_H
		BoardEval.apply_weights(up)
		var m_up := _fixed_score(snap, mine_is_enemy, better) \
			- _fixed_score(snap, mine_is_enemy, chosen)
		var dn: Dictionary = w.duplicate()
		dn[name] = base - GRAD_H
		BoardEval.apply_weights(dn)
		var m_dn := _fixed_score(snap, mine_is_enemy, better) \
			- _fixed_score(snap, mine_is_enemy, chosen)
		grad[name] = (m_up - m_dn) / (2.0 * GRAD_H)
	return grad


## Score a play EXACTLY as it was played — the fixed slot for a creature, so the
## argmax cannot slide between the two evaluations of a finite difference and
## turn a gradient into a comparison of two different plays. A spell has no
## placement, so it re-scores through the ordinary path.
static func _fixed_score(snap: BoardSim.SimCtx, mine_is_enemy: bool,
		play: Dictionary) -> float:
	var data: Dictionary = play.get("data", {})
	var kind := String(play.get("kind", "creature"))
	if kind == "pass":
		# PLAYING NOTHING IS A PLAY, and it has to be on the slate or the bot can
		# never learn that holding the card was right. It scores a flat zero,
		# which is also its gradient — so when the rollout says the pass was
		# best, the whole correction lands on pushing the chosen play DOWN.
		return 0.0
	if kind == "creature":
		var lane := int(play.get("lane", -1))
		if lane < 0:
			return 0.0
		return BoardEval.score_creature_at(snap, mine_is_enemy, data, lane,
			int(play.get("row", BoardSim.ROW_FRONT)))
	var s: Dictionary = BoardEval.score_spell(snap, mine_is_enemy, data)
	return float(s.get("score", 0.0))


## Re-impose the gauge and the band. See BoardEval's W_ATK note: the scorer is
## invariant under a uniform rescale of the whole vector, so one weight has to be
## pinned or the learner is free to wander along that direction forever, growing
## without ever changing a single decision.
##
## IT PINS `atk` AND DOES NOT RESCALE THE REST — the first version DIVIDED the
## whole vector by whatever `atk` had drifted to, and that was wrong in a way
## only the report made visible. Four of the thirteen weights never receive a
## gradient at all in skirmish (`card`, `command`, `kill`, `back_exposed` — see
## the sensitivity sweep in `_probe_bot_train`), and the rescale DRAGGED THEM
## ANYWAY: a 250-game run ended with `card` and `command` at 6.69, pinned against
## the clamp ceiling, having never once changed a decision. Learning had not
## discovered anything about drawing cards; the gauge had simply pushed them
## there. Pinning `atk` without rescaling removes the degeneracy just as well —
## with `atk` held at 1, a uniform scaling of the others is no longer a no-op —
## and nothing moves unless its own gradient moved it.
static func normalise(w: Dictionary) -> Dictionary:
	var out: Dictionary = w.duplicate()
	var defaults: Dictionary = BoardEval.default_weights()
	for name in BoardEval.WEIGHT_NAMES:
		var d := float(defaults.get(name, 1.0))
		var lo: float = d * CLAMP_LO
		var hi: float = d * CLAMP_HI
		out[name] = clampf(float(out.get(name, d)), minf(lo, hi), maxf(lo, hi))
	out["atk"] = BoardEval.PT_ATK
	return out


# =========================================================================
#  THE ACCEPTANCE TEST — the challenger has to earn it
# =========================================================================

## Add one batch of games to the standing trial, and rule on it if the evidence
## is now decisive. Sides ALTERNATE: whoever moves second sees the other's board
## and can answer it, so a fixed seating would measure the seat, not the brain.
##
## THE CHALLENGER IS FROZEN FOR THE WHOLE TRIAL (`_under_test`), because evidence
## accumulated against a moving target is not evidence at all — every game the
## learner would have changed the very thing being measured, and the record would
## describe a brain that never existed.
static func run_trial() -> Dictionary:
	ensure_loaded()
	if _pool.size() < 8:
		return {"result": "no_pool"}
	if int(_trial_played) == 0:
		_under_test = challenger.duplicate()
	var saved: Dictionary = BoardEval.export_weights()
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(stats.get("games", 0)) * 7919 + _trial_played * 31 + 13
	# DUPLICATE PAIRS, not independent games — see `head_to_head`. A pair the
	# cards decided is a tie and is not counted at all, which is the whole point:
	# the record only accumulates evidence about the two BRAINS.
	for _i in maxi(1, trial_games / 2):
		if Time.get_ticks_msec() - t0 > trial_budget_ms:
			break
		match pair_result(_under_test, champion, _pool, rng.randi()):
			1:
				_trial_played += 1
				_trial_wins += 1
			-1:
				_trial_played += 1
	BoardEval.apply_weights(saved)

	var played := _trial_played
	var wins := _trial_wins
	var rate := score_rate(wins, played)
	var verdict := trial_verdict(wins, played)
	var out: Dictionary = {"result": verdict, "played": played, "wins": wins,
		"rate": rate, "promote_at": promote_bound(played),
		"reject_at": reject_bound(played)}
	if verdict == "testing":
		return out       # not enough evidence yet — keep the record and add to it

	if verdict == "rejected":
		# THE GUARDRAIL FIRED. The hypothesis measurably LOSES; the champion
		# stands and learning restarts from what is known to work. Keeping a
		# losing challenger and continuing to push it is how a hill climber walks
		# downhill with complete confidence.
		challenger = champion.duplicate()
		stats["reverts"] = int(stats.get("reverts", 0)) + 1
	else:
		champion = _under_test.duplicate()
		stats["promotions"] = int(stats.get("promotions", 0)) + 1
		stats["generation"] = int(stats.get("generation", 0)) + 1
		if verdict == "adopted":
			stats["inconclusive"] = int(stats.get("inconclusive", 0)) + 1
		BoardEval.apply_weights(champion)
	_trial_played = 0
	_trial_wins = 0
	_under_test = {}
	return out


## A trial is open from the moment `_under_test` is frozen, NOT from the first
## decisive pair — most early batches yield none at all, and reporting "no trial
## running" while a hypothesis is frozen is how a caller ends up believing it has
## started testing something new when it is still measuring the old one.
static func trial_in_progress() -> bool:
	return not _under_test.is_empty()


## Abandon the standing trial without ruling on it. For a caller that wants to
## test a DIFFERENT hypothesis — swapping `challenger` mid-trial does nothing,
## because the trial deliberately measures its frozen copy.
static func cancel_trial() -> void:
	_under_test = {}
	_trial_played = 0
	_trial_wins = 0


## Wins that would put a challenger TRIAL_SIGMA above a coin flip, and the
## mirror bound below it. Binomial(n, ½) has standard deviation ½·√n.
static func promote_bound(played: int) -> float:
	return float(played) * 0.5 + TRIAL_SIGMA * sqrt(float(played)) * 0.5


static func reject_bound(played: int) -> float:
	return float(played) * 0.5 - TRIAL_SIGMA * sqrt(float(played)) * 0.5


## THE DECISION RULE, pulled out as a pure function so it can be asserted
## directly instead of through a coin flip. A test that fires a random batch at a
## threshold and checks the answer is testing the random number generator — which
## is how the first version of this shipped a 56% bar that a Binomial(24, ½)
## clears one time in four.
##
## THE THREE BANDS ARE NOT SYMMETRIC, AND THAT ASYMMETRY IS THE DESIGN.
##   · clearly ahead  → "promoted"
##   · clearly behind → "rejected"
##   · neither, at the cap → "ADOPTED", not rejected.
## A step here is not a random mutation: it came from a rollout that examined the
## actual alternatives and said this play was better. It arrives with its own
## justification, so the trial's job is to CATCH IT BEING WRONG, not to re-prove
## it right. Demanding proof of improvement for every step sounds stricter and is
## in fact fatal — a single gradient step is worth roughly 1% win rate, ~240
## games cannot resolve 1%, so every step would be discarded and the bot would
## never move at all. That is exactly what the first build did: 23 reverts, one
## promotion, and 4% of travel on a weight that wanted 60%.
## THE RISK THIS ACCEPTS, stated plainly: drift. A long run of steps that are
## each individually undetectable can accumulate somewhere worse. Three things
## bound it — the clamp band every weight lives in, the guardrail that fires on
## any step big enough to measurably hurt, and the fact that the direction comes
## from a model of the real clash rather than from noise.
static func trial_verdict(wins: int, played: int) -> String:
	if played < TRIAL_MIN_GAMES:
		return "testing"
	if float(wins) >= promote_bound(played):
		return "promoted"
	if float(wins) <= reject_bound(played):
		return "rejected"
	if played >= TRIAL_MAX_PAIRS:
		return "adopted"
	return "testing"


## One whole game, board only, no scene: two weight vectors driving two sides
## through `BoardEval` on a `BoardSim.SimCtx`. Returns the winning side, or -1
## for a draw / a game that never ended.
##
## THE WEIGHTS ARE A GLOBAL AND THAT IS A TRAP WORTH NAMING: `BoardEval.W_*` are
## static, so this swaps them either side of each decision. Nothing here may be
## called re-entrantly or from two places in one frame, and every caller
## restores the previous vector when it is done.
static func play_sim_game(w0: Dictionary, w1: Dictionary, pool: Array,
		seed_val: int, record_side: int = -1) -> int:
	var local := RandomNumberGenerator.new()
	local.seed = seed_val
	var c := BoardSim.SimCtx.new()
	c.player_hp = SIM_HERO_HP
	c.player_max_hp = SIM_HERO_HP
	c.enemy_hp = SIM_HERO_HP
	c.enemy_max_hp = SIM_HERO_HP

	var hands: Array = [[], []]
	var banks: Array = [0, 0]
	var weights: Array = [w0, w1]

	for _round in BoardSim.MAX_SIM_ROUNDS:
		for side in 2:
			while hands[side].size() < SIM_HAND:
				hands[side].append(pool[local.randi() % pool.size()])
			BoardEval.apply_weights(weights[side])
			_sim_take_turn(c, side, hands[side], SIM_MANA + int(banks[side]), banks,
				side == record_side)
		BoardSim.step_round(c)
		if c.player_hp <= 0 or c.enemy_hp <= 0:
			break
	if c.player_hp <= 0 and c.enemy_hp <= 0:
		return -1
	if c.enemy_hp <= 0:
		return BoardSim.SIDE_PLAYER
	if c.player_hp <= 0:
		return BoardSim.SIDE_ENEMY
	# NO KILL INSIDE THE ROUND CAP. Deciding it on remaining hero HP is the
	# honest call — the alternative is scoring it as a draw, which throws away
	# every grinding board game and biases the trial toward whichever brain is
	# better at stalling.
	if c.player_hp == c.enemy_hp:
		return -1
	return BoardSim.SIDE_PLAYER if c.player_hp > c.enemy_hp else BoardSim.SIDE_ENEMY


## One side's turn in a simulated game: greedy best-play until the Command runs
## out, the same policy `SkirmishBot.decide_turn` runs on a real board.
static func _sim_take_turn(c: BoardSim.SimCtx, side: int, hand: Array,
		budget: int, banks: Array, record: bool = false) -> void:
	var mine_is_enemy: bool = side == BoardSim.SIDE_ENEMY
	var left := budget
	var guard := 0
	while guard < 12 and left > 0 and not hand.is_empty():
		guard += 1
		# THE SAME SLATE THE REAL BOT SEES. See `enumerate_slate`: if this loop
		# re-derived its own idea of the options, a training run would tune the
		# weights against a bot that does not exist.
		var slate: Dictionary = enumerate_slate(c, mine_is_enemy, hand, left)
		var cands: Array = slate["cands"]
		var chosen := int(slate["chosen"])
		if record:
			record_decision(c, mine_is_enemy, cands, chosen)
		var play: Dictionary = cands[chosen]
		var idx := int(play.get("idx", -1))
		if idx < 0:
			break        # the slate chose to hold
		if not _apply_sim_play(c, side, play.get("data", {}), play):
			break
		left -= int(play.get("cost", 0))
		hand.remove_at(idx)
	banks[side] = clampi(left, 0, SIM_BANK)


## Train offline: play `games` self-play games, recording one side, and run the
## ordinary post-game analysis on each. It is the SAME path a real match takes —
## `enumerate_slate` → `record_decision` → `on_game_over` — so a training run
## cannot tune a bot the game does not ship.
static func train_on_sim_games(pool: Array, games: int, seed_val: int = 1) -> Dictionary:
	ensure_loaded()
	_pool = pool
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var saved: Dictionary = BoardEval.export_weights()
	var wins := 0
	for g in games:
		_records.clear()
		# SELF-PLAY: both sides on the champion, so the outcome is decided by the
		# deal and by play, never by a handicap. The learning signal is the ROLLOUT
		# regret at each decision; the result only scales the step.
		var winner := play_sim_game(champion, champion, pool, rng.randi(), 0)
		if winner == 0:
			wins += 1
		on_game_over(winner == 0, false)
	_write_disk()
	BoardEval.apply_weights(champion)
	return {"games": games, "self_play_wins": wins,
		"generation": int(stats.get("generation", 0)),
		"promotions": int(stats.get("promotions", 0)),
		"reverts": int(stats.get("reverts", 0)),
		"blunders": int(stats.get("blunders", 0)),
		"champion": champion.duplicate()}


## Head-to-head over `games`, played as DUPLICATE PAIRS. Returns `a`'s score over
## the pairs that were decisive.
##
## ── WHY PAIRS, AND WHY THIS WAS THE FIX THAT MATTERED ────────────────────
## The first version played independent games with the seats alternating. That
## is unbiased and it is far too noisy to be useful here: measured over the real
## card pool, the BEST weight vector this learner can reach is worth about +6%
## win rate and the worst is about −3%, while the standard error on 240
## independent games is ±3%. The acceptance test was being asked to resolve an
## effect the same size as its own noise, and it could not — a deliberately
## crippled brain came back at 0.494 against a 0.488 baseline, i.e. invisible.
##
## Almost all of that noise is the DEAL, not the play. So play each seed TWICE
## with the brains swapped, exactly as duplicate bridge does: both brains get
## both hands. A pair where the same seat wins regardless of who sat in it was
## decided by the cards and cancels to a tie; only pairs where the brains
## actually diverged score at all. What remains is a sign test on decisive
## pairs, and it sees differences the independent version never could.
static func head_to_head(w_a: Dictionary, w_b: Dictionary, pool: Array,
		games: int, seed_val: int = 1) -> Dictionary:
	var saved: Dictionary = BoardEval.export_weights()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var wins := 0
	var losses := 0
	var ties := 0
	for _i in maxi(1, games / 2):
		match pair_result(w_a, w_b, pool, rng.randi()):
			1: wins += 1
			-1: losses += 1
			_: ties += 1
	BoardEval.apply_weights(saved)
	return {"games": games, "pairs": wins + losses + ties, "wins": wins,
		"losses": losses, "draws": ties, "decided": wins + losses,
		"rate": score_rate(wins, wins + losses)}


## Wins over decisive pairs — and 0.5, NOT 0.0, when nothing was decisive.
##
## This is not a defensive `maxi(n, 1)`: with duplicate pairing, two IDENTICAL
## brains produce ZERO decisive pairs by construction (both games of every pair
## go the same way by seat, so every pair cancels). That is the pairing working
## perfectly — and the first version reported it as a 0.000 win rate, which reads
## as the most catastrophic possible result. "No difference detected" is 0.5.
static func score_rate(wins: int, decided: int) -> float:
	return 0.5 if decided <= 0 else float(wins) / float(decided)


## One duplicate pair on a shared deal: +1 if `w_a` came out ahead across the two
## seats, -1 if behind, 0 if the cards decided it either way.
static func pair_result(w_a: Dictionary, w_b: Dictionary, pool: Array,
		seed_val: int) -> int:
	var g1 := play_sim_game(w_a, w_b, pool, seed_val)   # A in seat 0
	var g2 := play_sim_game(w_b, w_a, pool, seed_val)   # A in seat 1
	var score := 0.0
	score += 1.0 if g1 == 0 else (0.0 if g1 == 1 else 0.5)
	score += 1.0 if g2 == 1 else (0.0 if g2 == 0 else 0.5)
	if score > 1.0:
		return 1
	return -1 if score < 1.0 else 0


static func _apply_sim_play(c: BoardSim.SimCtx, side: int, data: Dictionary,
		play: Dictionary) -> bool:
	if String(play.get("kind", "creature")) == "creature":
		var lane := int(play.get("lane", -1))
		var row := int(play.get("row", BoardSim.ROW_FRONT))
		if lane < 0 or c.at(side, row, lane) != null:
			return false
		c.put(side, row, lane, BoardSim.body_from_data(data, true))
		return true
	var tgt: Variant = play.get("target", null)
	var coord: Variant = null
	if tgt is BoardSim.SimBody:
		coord = _find_in(c, tgt)
	var applied: BoardSim.SimCtx = BoardSim.apply_play(c, side,
		{"kind": "spell", "data": data, "target": coord})
	# apply_play works on a copy (it is a search primitive); a live turn wants
	# the mutation, so adopt the result.
	c.player_hp = applied.player_hp
	c.enemy_hp = applied.enemy_hp
	c.grid = applied.grid
	return true


static func _find_in(c: BoardSim.SimCtx, body: Variant) -> Variant:
	for side in 2:
		for row in 2:
			for lane in BoardSim.LANES:
				if c.at(side, row, lane) == body:
					return Vector3i(side, row, lane)
	return null


# =========================================================================
#  PERSISTENCE
# =========================================================================

static func _write_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"champion": champion,
		"challenger": challenger,
		"stats": stats,
	}, "\t"))
	f.close()


## Read the brain off disk, and REFUSE ANYTHING THAT DOES NOT PARSE CLEANLY.
## A weight vector is 13 floats read from a plain text file in `user://` that
## anyone may edit; a NaN or a string in there reaches every scoring decision in
## the game, and a NaN propagates silently through `clampf` and every comparison
## (`NaN > x` is false for all x, so the bot would simply never find a best play
## and would stop playing cards). Falling back to the shipped defaults is always
## a legal outcome — that is just the bot the game shipped with.
static func _read_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	if int(d.get("version", 0)) != SAVE_VERSION:
		return
	champion = _sanitise(d.get("champion", {}))
	challenger = _sanitise(d.get("challenger", champion))
	var s: Variant = d.get("stats", {})
	if s is Dictionary:
		for k in (s as Dictionary):
			stats[k] = int((s as Dictionary)[k])


static func _sanitise(w: Variant) -> Dictionary:
	var defaults: Dictionary = BoardEval.default_weights()
	if not (w is Dictionary):
		return defaults
	var out: Dictionary = defaults.duplicate()
	for name in BoardEval.WEIGHT_NAMES:
		var v: Variant = (w as Dictionary).get(name, null)
		if not (v is float or v is int):
			continue
		var f := float(v)
		if is_nan(f) or is_inf(f):
			continue
		out[name] = f
	return normalise(out)


## Throw the learning away and go back to the shipped bot. Exposed so a player
## (or a probe) can always get back to a known state.
static func forget() -> void:
	ensure_loaded()
	champion = BoardEval.default_weights()
	challenger = champion.duplicate()
	stats = {"games": 0, "wins": 0, "promotions": 0, "reverts": 0,
		"inconclusive": 0, "generation": 0, "blunders": 0}
	last_report = {}
	_under_test = {}
	_trial_played = 0
	_trial_wins = 0
	_records.clear()
	BoardEval.apply_weights(champion)
	_write_disk()


## One line for a log or a debug readout.
static func summary() -> String:
	ensure_loaded()
	return "gen %d · %d games · %d promoted / %d reverted · %d blunders seen" % [
		int(stats.get("generation", 0)), int(stats.get("games", 0)),
		int(stats.get("promotions", 0)), int(stats.get("reverts", 0)),
		int(stats.get("blunders", 0))]
