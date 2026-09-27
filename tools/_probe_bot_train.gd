extends Node
## _probe_bot_train.gd — DID THE LEARNING MAKE THE BOT BETTER, OR JUST BUSIER?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_bot_train.tscn
##   ... -- --games=400 --eval=600     (defaults: 300 / 400)
##
## `_probe_bot_brain` proves the MACHINERY is correct: the forward model resolves
## the clash the way the game does, the analysis names the better move, the
## update moves the right way, a bad challenger is refused. All of that can be
## true of a learner that never improves anything. This is the other question,
## and it is the only one a player would ask: after training, does the bot WIN
## MORE than the bot that shipped?
##
## It runs as a SCENE, not `--script`, because it trains on the REAL skirmish
## card pool and that means resolving `CardDB` / `SkirmishState` — autoloads,
## which a `--script` probe does not have. (Its sibling `_probe_board_eval` goes
## the other way, asserting against stubs precisely so it can stay `--script`.)
##
## ── THE MEASUREMENT, AND WHY IT IS SHAPED LIKE THIS ──────────────────────
## Trained-vs-shipped, sides ALTERNATING, on a pool neither was tuned against by
## hand. Alternating matters: whoever plays second sees the other's board and can
## answer it, so a fixed seating would measure the seat. The baseline run
## (shipped vs shipped) is printed first as a vacuity check — if two identical
## brains do not come out near even, the harness is measuring something other
## than play quality and every number after it is void.
##
## ── IT IS A REPORT WITH ONE GATE, NOT A PASS/FAIL ON THE WIN RATE ────────
## Training is stochastic and the honest bar is "learning must not make the bot
## WORSE" — that is the regression this can actually enforce. Whether a given run
## finds an improvement is data, printed and not asserted; asserting it would
## make the suite fail on an unlucky seed and teach everyone to re-run until
## green, which is the worst thing a test can teach.

const BoardEval = preload("res://scripts/combat/BoardEval.gd")
const BoardSim = preload("res://scripts/combat/BoardSim.gd")
const BotBrain = preload("res://scripts/combat/BotBrain.gd")

var _pass := 0
var _fail := 0
var _saved_brain: Variant = null


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s%s" % [label, ("" if detail.is_empty() else "  — " + detail)])


func _arg(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--%s=" % name):
			return int(String(a).split("=")[1])
	return fallback


func _ready() -> void:
	print("[bot-train] start")
	_stash_save()

	var pool := _real_pool()
	print("  pool: %d real skirmish cards (cost <= 4, as the bot drafts)" % pool.size())
	if pool.size() < 12:
		ok(false, "the skirmish pool resolved", "got %d cards" % pool.size())
		_finish()
		return

	var train_games := _arg("games", 300)
	var eval_games := _arg("eval", 400)
	var shipped: Dictionary = BoardEval.default_weights()

	# ── VACUITY: the harness can tell a difference at all ─────────────────
	# With DUPLICATE PAIRING this is a sharper check than it looks. Two identical
	# brains cancel EXACTLY: every pair plays the same deal twice with the seats
	# swapped, both games go the same way, every pair ties, and the decisive count
	# is zero. A single decisive pair between a brain and itself would mean the
	# simulation is not deterministic in its seed — which would make every other
	# number in this report noise.
	var base := BotBrain.head_to_head(shipped, shipped, pool, eval_games, 11)
	print("\n  baseline   shipped vs shipped : %.3f  (%d pairs, %d decisive, %d tied)"
		% [float(base["rate"]), int(base["pairs"]), int(base["decided"]),
			int(base["draws"])])
	ok(int(base["decided"]) == 0,
		"a brain against ITSELF cancels exactly — the pairing removes the deal",
		"decisive=%d of %d pairs" % [int(base["decided"]), int(base["pairs"])])
	ok(is_equal_approx(float(base["rate"]), 0.5),
		"and 'no difference' reports as 0.5, not as a 0.000 wipeout")

	# A CRIPPLED BRAIN MUST LOSE, or a win rate here means nothing at all.
	#
	# PICKING ONE WAS ITSELF THE FINDING. The first attempt put `face` and `kill`
	# at the floor — "a brain that will not close a game" — and it scored EXACTLY
	# 0.500. A sensitivity sweep over the real pool explained why: those two
	# weights barely enter a creature placement (`kill` needs a Swift body that
	# can kill, or a plain `damage` spell; `face` only reaches the open-lane
	# term), and FOUR of the thirteen — card, command, kill, back_exposed —
	# never change a single decision in skirmish play. HP and BLOCK do, heavily.
	# A sanity check that cannot fail is not a sanity check, and this one could
	# not: it was crippling a leg the bot does not walk on.
	var crippled: Dictionary = shipped.duplicate()
	crippled["hp"] = BoardEval.PT_HP * 4.0
	crippled["block"] = BoardEval.PT_BLOCK * 4.0
	crippled["shelter"] = BoardEval.PT_SHELTER * 4.0
	var crip := BotBrain.head_to_head(crippled, shipped, pool, eval_games, 12)
	print("  sanity     crippled vs shipped: %.3f" % float(crip["rate"]))
	ok(float(crip["rate"]) < 0.47,
		"a brain that overvalues walls loses to the shipped one",
		"rate=%.3f" % float(crip["rate"]))

	# ── THE GUARDRAIL AND THE POSITIVE CONTROL, ON THE REAL POOL ──────────
	# The acceptance test has to do BOTH jobs or it does neither: reject a
	# challenger that loses, and accept one that wins. A trial that rejects
	# everything passes the first test and is useless.
	BotBrain.forget()
	BotBrain.trial_budget_ms = 60000
	BotBrain.trial_games = BotBrain.TRIAL_MAX_PAIRS
	BotBrain.begin_game(pool)
	var champ_before: Dictionary = BotBrain.champion.duplicate()
	var reject := _test_to_verdict(crippled)
	print("\n  guardrail  crippled challenger: %s at %.3f (reject at or below %.1f of %d)"
		% [reject.get("result", "?"), float(reject.get("rate", -1)),
			float(reject.get("reject_at", -1)), int(reject.get("played", 0))])
	ok(String(reject.get("result", "")) == "rejected",
		"the guardrail NAMES a losing challenger rather than timing out on it",
		"result=%s" % reject.get("result", "?"))
	ok(BotBrain.champion == champ_before,
		"a challenger that loses never becomes the bot the player faces")

	# THE POSITIVE CONTROL, and it must not be a magic constant.
	#
	# It used to be a hand-picked vector (hp and block at a quarter) measured as
	# stronger — and the measurement went STALE the moment `BoardSim` was
	# corrected: once the mustering defender's counter was added, walls became
	# worth what the engine always said they were worth, gutting `hp`/`block`
	# stopped being clever, and that vector started LOSING at 0.29. The test
	# failed for a constant that had quietly expired, which is the standing
	# hazard of pinning a number measured under an older model.
	#
	# So the control is derived IN THIS RUN instead: the crippled brain was just
	# measured losing, therefore the shipped brain is stronger THAN IT, by the
	# same measurement. Seat the cripple as champion and offer the shipped
	# weights as challenger — the trial must promote. It cannot expire, because
	# both halves come from the same sample.
	BotBrain.champion = crippled.duplicate()
	var accept := _test_to_verdict(shipped)
	print("  control    stronger challenger: %s at %.3f (promote at or above %.1f of %d)"
		% [accept.get("result", "?"), float(accept.get("rate", -1)),
			float(accept.get("promote_at", -1)), int(accept.get("played", 0))])
	ok(String(accept.get("result", "")) == "promoted",
		"a challenger that really is stronger IS promoted — the trial can measure",
		"result=%s" % accept.get("result", "?"))
	ok(BotBrain.champion != crippled,
		"and it replaces the weaker champion it beat")

	# ── TRAIN ─────────────────────────────────────────────────────────────
	BotBrain.forget()
	BotBrain.trial_budget_ms = 60000     # headless: there is no frame to protect
	BotBrain.trial_games = 120           # and a decisive batch is affordable
	var t0 := Time.get_ticks_msec()
	var result := BotBrain.train_on_sim_games(pool, train_games, 7)
	var train_ms := Time.get_ticks_msec() - t0
	print("\n  trained %d self-play games in %.1fs" % [train_games, train_ms / 1000.0])
	print("    blunders found : %d" % int(result["blunders"]))
	print("    promotions     : %d   reverts: %d   generation: %d"
		% [int(result["promotions"]), int(result["reverts"]), int(result["generation"])])
	ok(int(result["blunders"]) > 0,
		"the analysis actually found mistakes to learn from",
		"blunders=%d" % int(result["blunders"]))

	var trained: Dictionary = result["champion"]
	print("\n  weights   shipped            trained")
	for name in BoardEval.WEIGHT_NAMES:
		var a := float(shipped[name])
		var b := float(trained[name])
		var mark: String = "" if is_equal_approx(a, b) else "   <-- moved"
		print("    %-14s %6.3f   ->   %6.3f%s" % [name, a, b, mark])

	# ── MEASURE ───────────────────────────────────────────────────────────
	var head := BotBrain.head_to_head(trained, shipped, pool, eval_games, 99)
	var rate := float(head["rate"])
	print("\n  RESULT     trained vs shipped : %.3f  (%d wins of %d decisive pairs; %d of %d tied)"
		% [rate, int(head["wins"]), int(head["decided"]), int(head["draws"]),
			int(head["pairs"])])
	# Elo, for scale. A rate of 0.5 is 0 Elo; the formula is the standard
	# inversion of the logistic expectation curve.
	if rate > 0.001 and rate < 0.999:
		print("             ≈ %+.0f Elo" % (-400.0 * log(1.0 / rate - 1.0) / log(10.0)))
	# The band is on DECISIVE PAIRS, not on games played — the tied pairs carry no
	# information about the brains and must not be counted as evidence either way.
	var n_dec: int = maxi(int(head["decided"]), 1)
	var band: float = BotBrain.TRIAL_SIGMA * 0.5 / sqrt(float(n_dec))
	var needed_lo: float = 0.5 - band
	print("             (a 2-sigma band on %d decisive pairs is ±%.3f)" % [n_dec, band])

	# THE GATE. Not "did it improve" — that is a stochastic outcome and asserting
	# it would make this fail on an unlucky seed. The enforceable claim is that
	# the champion/challenger discipline did its job: whatever learning happened,
	# the bot that came out is NOT WORSE than the bot that went in.
	ok(rate >= needed_lo,
		"learning did not make the bot worse than the one that shipped",
		"rate=%.3f floor=%.3f" % [rate, needed_lo])

	if rate > 0.5 + band:
		print("  >> the trained bot is STRONGER than shipped by more than 2 sigma.")
	elif rate > 0.5:
		print("  >> ahead, but inside the noise band: not yet a result.")
	else:
		print("  >> no improvement measured on this seed.")

	# ── THE FRAME-COST CLAIM ──────────────────────────────────────────────
	# `CombatNet._net_show_result` calls this on the verdict screen. The comment
	# there says it is never the reason a frame is late; here is the number.
	BotBrain.forget()
	BotBrain.trial_budget_ms = 70
	BotBrain.trial_games = 24
	BotBrain.begin_game(pool)
	BotBrain.play_sim_game(BotBrain.champion, BotBrain.champion, pool, 5, 0)
	var recorded: int = BotBrain._records.size()
	var t1 := Time.get_ticks_usec()
	BotBrain.on_game_over(true, false)
	var cost_ms := float(Time.get_ticks_usec() - t1) / 1000.0
	print("\n  post-game analysis of %d decisions: %.1f ms (no trial)"
		% [recorded, cost_ms])
	# And one WITH the periodic trial, which is the expensive tick.
	BotBrain.begin_game(pool)
	BotBrain.play_sim_game(BotBrain.champion, BotBrain.champion, pool, 6, 0)
	BotBrain.stats["games"] = BotBrain.TRIAL_EVERY - 1
	var t2 := Time.get_ticks_usec()
	BotBrain.on_game_over(false, false)
	var trial_ms := float(Time.get_ticks_usec() - t2) / 1000.0
	print("  the same tick including the acceptance trial: %.1f ms" % trial_ms)
	ok(trial_ms < 400.0,
		"the heaviest learning tick stays inside its budget",
		"%.1f ms" % trial_ms)

	_finish()


## Run the sequential trial to a VERDICT, one batch at a time.
##
## TWO THINGS THIS PROBE GOT WRONG BEFORE, both of them the trial working as
## designed: (1) one batch usually decides nothing — most duplicate pairs tie,
## which is the pairing doing its job, so a single call returning "testing" is
## normal and not a failure; (2) the trial measures a FROZEN copy of the
## challenger, so assigning `BotBrain.challenger` while a trial is open changes
## nothing at all. The second attempt here set a known-STRONGER vector and
## watched it come back "rejected at 0.091" — it was still measuring the crippled
## brain from the previous block. `cancel_trial` is the way to start a new one.
func _test_to_verdict(hypothesis: Dictionary) -> Dictionary:
	BotBrain.cancel_trial()
	BotBrain.challenger = hypothesis.duplicate()
	var out: Dictionary = {}
	for _batch in 40:
		out = BotBrain.run_trial()
		if String(out.get("result", "")) != "testing":
			return out
	return out


## The cards the bot actually drafts: the skirmish-legal pool, cost-capped the
## same way `SkirmishBot.build_deck` caps it. Training on cards the bot can never
## hold would tune it for a game it does not play.
func _real_pool() -> Array:
	var out: Array = []
	var legal: Array = SkirmishState.skirmish_legal_pool()
	for id in legal:
		var d: Dictionary = SkirmishState.skirmish_card_data(id)
		if d.is_empty() or int(d.get("cost", 99)) > 4:
			continue
		out.append(d)
	return out


func _finish() -> void:
	_restore_save()
	print("\n[bot-train] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _stash_save() -> void:
	if FileAccess.file_exists(BotBrain.SAVE_PATH):
		var f := FileAccess.open(BotBrain.SAVE_PATH, FileAccess.READ)
		if f != null:
			_saved_brain = f.get_as_text()
			f.close()


func _restore_save() -> void:
	if _saved_brain is String:
		var f := FileAccess.open(BotBrain.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(String(_saved_brain))
			f.close()
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BotBrain.SAVE_PATH))
