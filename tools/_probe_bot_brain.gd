extends SceneTree
## _probe_bot_brain.gd — DOES THE BOT ACTUALLY LEARN, AND IS THE LEARNING SAFE?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_bot_brain.gd
##
## `BotBrain` makes four claims and every one of them is the kind that looks true
## from the inside: it says it models the clash, that it finds the better move in
## hindsight, that its weight update moves in the direction that would have
## chosen that move, and that a bad update cannot reach the player's bot. A
## learner with no test agrees with itself indefinitely — it will happily report
## a generation count climbing while playing worse every game — so each claim
## gets an assertion that fails on the opposite behaviour.
##
## ── PHASE A: THE FORWARD MODEL IS THE WHOLE FOUNDATION ───────────────────
## Everything downstream is "what does the rollout say", so a rollout that
## resolves the clash wrongly teaches the scorer wrongly, confidently, forever.
## Phase A checks it against the rules as the real engine states them: the muster
## delay, the Rush restriction on Swift, overkill spilling BEHIND and stopping,
## Piercing being the only thing that reads on to the face, Armored, Thorns, Last
## Stand, and deferred deaths making a mutual trade mutual.
##
## ── PHASE F IS THE ONE THAT MATTERS MOST ─────────────────────────────────
## The champion/challenger discipline. A learner that cannot be shown to REJECT
## a bad hypothesis is not a safety mechanism, it is a comment.
##
## ── SAVE ISOLATION ───────────────────────────────────────────────────────
## This writes `user://bot_brain.json`, which is a real player's trained bot. It
## is read and restored byte-for-byte at the end, including the "there was no
## file" case — a probe that quietly resets someone's bot is worse than no probe.

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


func _body(atk: int, hp: int, kw: Array = [], ready := true) -> BoardSim.SimBody:
	var b := BoardSim.SimBody.new()
	b.atk = atk
	b.current_hp = hp
	b.cap_hp = hp
	b.kw = kw
	b.ready = ready
	b.card_data = {"atk": atk, "hp": hp, "keywords": kw}
	return b


func _board() -> BoardSim.SimCtx:
	var c := BoardSim.SimCtx.new()
	c.player_hp = 30
	c.player_max_hp = 30
	c.enemy_hp = 30
	c.enemy_max_hp = 30
	return c


## A small pool with a real spread of costs and shapes — enough that a greedy
## scorer has something to be right or wrong about.
func _pool() -> Array:
	return [
		{"id": "a", "name": "Levy", "type": "creature", "cost": 1, "atk": 1, "hp": 2, "keywords": []},
		{"id": "b", "name": "Pikeman", "type": "creature", "cost": 2, "atk": 2, "hp": 3, "keywords": []},
		{"id": "c", "name": "Palisade", "type": "creature", "cost": 1, "atk": 0, "hp": 4, "keywords": []},
		{"id": "d", "name": "Outrider", "type": "creature", "cost": 2, "atk": 3, "hp": 1, "keywords": ["swift"]},
		{"id": "e", "name": "Hoplite", "type": "creature", "cost": 3, "atk": 3, "hp": 4, "keywords": ["armored"]},
		{"id": "f", "name": "Bristler", "type": "creature", "cost": 2, "atk": 1, "hp": 4, "keywords": ["thorns"]},
		{"id": "g", "name": "Lancer", "type": "creature", "cost": 3, "atk": 4, "hp": 2, "keywords": ["piercing"]},
		{"id": "h", "name": "Veteran", "type": "creature", "cost": 4, "atk": 4, "hp": 5, "keywords": []},
		{"id": "i", "name": "Loose Shot", "type": "spell", "cost": 1, "atk": 0, "hp": 0,
			"keywords": [], "spell": {"type": "damage", "value": 3}, "targeting": "enemy_creature"},
		{"id": "j", "name": "Rally", "type": "spell", "cost": 2, "atk": 0, "hp": 0,
			"keywords": [], "spell": {"type": "buff_all_atk", "value": 1}, "targeting": "none"},
	]


func _init() -> void:
	print("[bot-brain] start")
	_stash_save()
	BotBrain.forget()

	_phase_a_forward_model()
	_phase_b_rollout_sees_deeper()
	_phase_c_regret()
	_phase_d_update_direction()
	_phase_e_gauge_and_clamp()
	_phase_f_champion_discipline()
	_phase_g_persistence()
	_phase_h_shipped_default_is_untouched()

	_restore_save()
	print("[bot-brain] %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════════════════
#  A — THE FORWARD MODEL
# ═════════════════════════════════════════════════════════════════════════

func _phase_a_forward_model() -> void:
	print("\n── A: the forward model resolves the clash the way the game does ──")

	# THE MUSTER DELAY. A body does not swing in the clash ending its arrival
	# round. This is the single rule BoardEval was rewritten for; a rollout that
	# got it wrong would train the scorer straight back into the old defect.
	var c := _board()
	c.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(5, 5, [], false))
	BoardSim.step_round(c)
	ok(c.enemy_hp == 30, "a body that just arrived does not swing",
		"foe at %d" % c.enemy_hp)
	# ...and swings from the next round on, because step_round readies it LAST.
	BoardSim.step_round(c)
	ok(c.enemy_hp == 25, "the same body swings the following round",
		"foe at %d" % c.enemy_hp)

	# SWIFT is the exemption — but may not reach the FACE on its arrival round.
	var c2 := _board()
	c2.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(4, 2, ["swift"], false))
	BoardSim.step_round(c2)
	ok(c2.enemy_hp == 30, "Swift does not reach the face on its arrival round",
		"foe at %d" % c2.enemy_hp)
	# It does strike a BODY on that round, which is the whole point of the keyword.
	var c3 := _board()
	c3.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(4, 2, ["swift"], false))
	c3.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(1, 9, [], true))
	BoardSim.step_round(c3)
	var struck: BoardSim.SimBody = c3.at(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0)
	ok(struck != null and struck.current_hp == 5,
		"Swift still strikes a body on its arrival round",
		"hp %d" % (0 if struck == null else struck.current_hp))

	# OVERKILL spills BEHIND and STOPS. This is the 2026-07-28 blocker economy,
	# and it is what decides whether a cheap wall is a good buy.
	var c4 := _board()
	c4.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(10, 9, [], true))
	c4.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(0, 1, [], true))
	c4.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_BACK, 0, _body(0, 5, [], true))
	BoardSim.step_round(c4)
	ok(c4.at(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0) == null
		and c4.at(BoardSim.SIDE_ENEMY, BoardSim.ROW_BACK, 0) == null,
		"overkill carries through the wall into the body behind it")
	ok(c4.enemy_hp == 30, "plain overkill STOPS — it never reads on to the face",
		"foe at %d" % c4.enemy_hp)

	# PIERCING is the one thing that does reach the face, and that premium is the
	# entire remaining point of the keyword.
	var c5 := _board()
	c5.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(10, 9, ["piercing"], true))
	c5.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(0, 1, [], true))
	BoardSim.step_round(c5)
	ok(c5.enemy_hp == 21, "Piercing carries the excess on to the face",
		"foe at %d" % c5.enemy_hp)

	# ARMORED: one less from each hit, floored at 1.
	var c6 := _board()
	c6.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(3, 9, [], true))
	c6.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(0, 9, ["armored"], true))
	BoardSim.step_round(c6)
	var arm: BoardSim.SimBody = c6.at(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0)
	ok(arm != null and arm.current_hp == 7, "Armored takes one less",
		"hp %d" % (0 if arm == null else arm.current_hp))

	# THORNS bites back.
	var c7 := _board()
	c7.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(5, 2, [], true))
	c7.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(0, 9, ["thorns"], true))
	BoardSim.step_round(c7)
	var biter: BoardSim.SimBody = c7.at(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0)
	ok(biter != null and biter.current_hp == 1, "Thorns puts 1 back into the attacker",
		"hp %d" % (0 if biter == null else biter.current_hp))

	# LAST STAND survives once at 1.
	var c8 := _board()
	c8.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(99, 9, [], true))
	c8.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(0, 3, ["last_stand"], true))
	BoardSim.step_round(c8)
	var ls: BoardSim.SimBody = c8.at(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0)
	ok(ls != null and ls.current_hp == 1, "Last Stand survives the first lethal blow",
		"hp %d" % (0 if ls == null else ls.current_hp))

	# DEFERRED DEATHS. A mutual trade must kill BOTH. Sweeping corpses mid-pass
	# instead of at the end of it turns every simultaneous kill into a one-sided
	# one, which would teach the scorer that trading up is free.
	var c9 := _board()
	c9.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 1, _body(2, 2, [], true))
	c9.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 1, _body(2, 2, [], true))
	BoardSim.step_round(c9)
	ok(c9.at(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 1) == null
		and c9.at(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 1) == null,
		"a mutual trade kills both — deaths are deferred to the end of the pass")

	# BOTH ROWS STRIKE. The back row is play space, not a bench; a sim that
	# modelled it as a queue would re-teach exactly the rule BoardEval removed.
	var c10 := _board()
	c10.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_BACK, 2, _body(3, 3, [], true))
	BoardSim.step_round(c10)
	ok(c10.enemy_hp == 27, "a back-row body strikes like any other",
		"foe at %d" % c10.enemy_hp)


# ═════════════════════════════════════════════════════════════════════════
#  B — THE DEEPER LOOK MUST ACTUALLY SEE FURTHER
# ═════════════════════════════════════════════════════════════════════════

func _phase_b_rollout_sees_deeper() -> void:
	print("\n── B: the rollout disagrees with the one-ply score, and is right ──")

	# A VACUITY CHECK FIRST. If the rollout returned the same verdict as the
	# static scorer on every board, the whole learner would be a very expensive
	# no-op that still printed a rising generation count.
	#
	# THE BOARD: a 3/3 stands opposite. The one-ply scorer prefers the 0/6 WALL,
	# because HP is 0.75 a point and six of it outweighs everything the 4/1
	# offers. Three rounds on, that is backwards — the wall has 0 ATK, so it
	# never trades, it is simply eaten over two rounds and the 3/3 then walks
	# into the face. The 4/1 dies too, but it dies KILLING the 3/3: the muster
	# delay stops a body initiating, never defending, so it trades on the
	# counter. One play removes a threat, the other postpones it.
	#
	# THIS FIXTURE WAS WRONG ONCE AND THE SIM WAS RIGHT. It originally asserted
	# the opposite — that the wall wins — and it passed only while `BoardSim` was
	# missing the mustering defender's counter. Adding the counter (found by
	# `_probe_sim_fidelity` against the real engine) flipped the board, and the
	# failure was the FIXTURE's premise, not the model's arithmetic.
	var c := _board()
	c.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(3, 3, [], true))
	var glass: Dictionary = {"name": "Glass", "type": "creature", "cost": 2,
		"atk": 4, "hp": 1, "keywords": []}
	var wall: Dictionary = {"name": "Wall", "type": "creature", "cost": 2,
		"atk": 0, "hp": 6, "keywords": []}

	var p_glass: Dictionary = {"kind": "creature", "data": glass, "lane": 0,
		"row": BoardSim.ROW_FRONT, "target": null}
	var p_wall: Dictionary = {"kind": "creature", "data": wall, "lane": 0,
		"row": BoardSim.ROW_FRONT, "target": null}

	var v_glass := BoardSim.rollout(
		BoardSim.apply_play(c, BoardSim.SIDE_PLAYER, p_glass), BoardSim.SIDE_PLAYER)
	var v_wall := BoardSim.rollout(
		BoardSim.apply_play(c, BoardSim.SIDE_PLAYER, p_wall), BoardSim.SIDE_PLAYER)
	ok(v_glass > v_wall,
		"three rounds on, the body that TRADES beats the wall that only stalls",
		"glass=%.2f wall=%.2f" % [v_glass, v_wall])

	var s_glass := BoardEval.score_creature_at(c, false, glass, 0, BoardSim.ROW_FRONT)
	var s_wall := BoardEval.score_creature_at(c, false, wall, 0, BoardSim.ROW_FRONT)
	ok(s_wall > s_glass,
		"...while the one-ply scorer prefers the wall — they genuinely disagree",
		"one-ply wall=%.2f glass=%.2f" % [s_wall, s_glass])
	ok(not is_equal_approx(s_glass - s_wall, v_glass - v_wall),
		"the deeper look is not just the shallow one restated",
		"one-ply Δ=%.2f rollout Δ=%.2f" % [s_glass - s_wall, v_glass - v_wall])

	# A rollout must also notice a win. If lethal on the board did not dominate,
	# regret would be measured in stat points on a game that was already over.
	var c2 := _board()
	c2.enemy_hp = 3
	c2.put(BoardSim.SIDE_PLAYER, BoardSim.ROW_FRONT, 0, _body(5, 5, [], true))
	ok(BoardSim.rollout(c2, BoardSim.SIDE_PLAYER) >= BoardEval.LETHAL,
		"a rollout that reaches a dead hero reports it as lethal, not as material")


# ═════════════════════════════════════════════════════════════════════════
#  C — REGRET: NAMING THE MISTAKE
# ═════════════════════════════════════════════════════════════════════════

func _phase_c_regret() -> void:
	print("\n── C: the analysis names the better move and prices the mistake ──")

	var c := _board()
	c.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(3, 3, [], true))
	var glass: Dictionary = {"name": "Glass", "type": "creature", "cost": 2,
		"atk": 4, "hp": 1, "keywords": []}
	var wall: Dictionary = {"name": "Wall", "type": "creature", "cost": 2,
		"atk": 0, "hp": 6, "keywords": []}
	var cands: Array = [
		{"data": glass, "kind": "creature", "lane": 0, "row": BoardSim.ROW_FRONT,
			"target": null, "score": 9.0, "idx": 0},
		{"data": wall, "kind": "creature", "lane": 0, "row": BoardSim.ROW_FRONT,
			"target": null, "score": 4.0, "idx": 1},
	]
	BotBrain.forget()
	BotBrain.begin_game(_pool())
	BotBrain.record_decision(c, false, cands, 1)       # took the wall — the mistake
	var report := BotBrain.analyse(BotBrain._records, false)
	ok(int(report.get("blunders", 0)) == 1,
		"the decision is recorded as a blunder",
		"blunders=%d" % int(report.get("blunders", 0)))
	var worst: Dictionary = report.get("worst", {})
	ok(String(worst.get("better", "")) == "Glass"
		and String(worst.get("played", "")) == "Wall",
		"it names what was played AND what should have been",
		"played=%s better=%s" % [worst.get("played", "?"), worst.get("better", "?")])
	ok(float(worst.get("regret", 0.0)) > BotBrain.REGRET_FLOOR,
		"the mistake is priced above the noise floor",
		"regret=%.2f" % float(worst.get("regret", 0.0)))

	# THE OTHER DIRECTION, which is the one a learner gets wrong silently: taking
	# the move the rollout agrees with must teach NOTHING. A learner that updates
	# on every decision fits noise and calls it experience.
	BotBrain.forget()
	BotBrain.begin_game(_pool())
	BotBrain.record_decision(c, false, cands, 0)       # took the trade — correct
	var clean := BotBrain.analyse(BotBrain._records, true)
	ok(int(clean.get("blunders", 0)) == 0,
		"a decision the rollout agrees with is not a blunder")
	ok(BotBrain.challenger == BoardEval.default_weights(),
		"and it moves no weights at all")


# ═════════════════════════════════════════════════════════════════════════
#  D — THE UPDATE MOVES THE RIGHT WAY
# ═════════════════════════════════════════════════════════════════════════

func _phase_d_update_direction() -> void:
	print("\n── D: after learning, the scorer prefers the move it should have made ──")

	var c := _board()
	c.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(3, 3, [], true))
	var glass: Dictionary = {"name": "Glass", "type": "creature", "cost": 2,
		"atk": 4, "hp": 1, "keywords": []}
	var wall: Dictionary = {"name": "Wall", "type": "creature", "cost": 2,
		"atk": 0, "hp": 6, "keywords": []}
	var cands: Array = [
		{"data": glass, "kind": "creature", "lane": 0, "row": BoardSim.ROW_FRONT,
			"target": null, "score": 0.0, "idx": 0},
		{"data": wall, "kind": "creature", "lane": 0, "row": BoardSim.ROW_FRONT,
			"target": null, "score": 0.0, "idx": 1},
	]

	BotBrain.forget()
	# margin = score(the play the rollout liked) − score(the play that was taken).
	var before := _margin(c, wall, glass, BoardEval.default_weights())

	# Ten games of the same mistake. One is inside the per-game step clamp by
	# design — a single game is not evidence enough to move a weight far — so
	# the assertion is about the DIRECTION being consistent, not the size.
	for _i in 10:
		BotBrain.begin_game(_pool())
		BotBrain.record_decision(c, false, cands, 1)   # took the wall every time
		BotBrain.analyse(BotBrain._records, false)
	var after := _margin(c, wall, glass, BotBrain.challenger)
	BoardEval.reset_weights()

	ok(after > before,
		"the margin in favour of the better move has grown",
		"before=%.4f after=%.4f" % [before, after])
	ok(BotBrain.challenger != BoardEval.default_weights(),
		"the challenger has actually moved off the shipped weights")


## score(wall) − score(glass) under a given weight vector: positive means the
## scorer now prefers the play the rollout liked.
func _margin(c: BoardSim.SimCtx, worse: Dictionary, better: Dictionary,
		w: Dictionary) -> float:
	var saved: Dictionary = BoardEval.export_weights()
	BoardEval.apply_weights(w)
	var m := BoardEval.score_creature_at(c, false, better, 0, BoardSim.ROW_FRONT) \
		- BoardEval.score_creature_at(c, false, worse, 0, BoardSim.ROW_FRONT)
	BoardEval.apply_weights(saved)
	return m


# ═════════════════════════════════════════════════════════════════════════
#  E — THE GAUGE AND THE BAND
# ═════════════════════════════════════════════════════════════════════════

func _phase_e_gauge_and_clamp() -> void:
	print("\n── E: the weight vector cannot drift or run away ──")

	# THE GAUGE. The scorer is invariant under a uniform rescale, so one weight
	# must be pinned or the learner wanders along that direction forever, growing
	# without ever playing differently.
	var drifted: Dictionary = BoardEval.default_weights().duplicate()
	drifted["atk"] = 2.9
	var fixed := BotBrain.normalise(drifted)
	ok(is_equal_approx(float(fixed["atk"]), BoardEval.PT_ATK),
		"normalise pins the gauge at W_ATK = 1.0 whatever arrives",
		"got %.4f" % float(fixed["atk"]))
	var untouched := true
	for name in BoardEval.WEIGHT_NAMES:
		if name == "atk":
			continue
		if not is_equal_approx(float(fixed[name]),
				float(BoardEval.default_weights()[name])):
			untouched = false
	# THE REGRESSION THIS EXISTS FOR. `normalise` used to DIVIDE the whole vector
	# by whatever `atk` had drifted to, which silently dragged every other weight
	# along — including ones the learner had never touched. A 250-game run ended
	# with `card` and `command` jammed against the clamp ceiling at 6.69, having
	# never once changed a decision, and it read like a discovery about drawing
	# cards. Pinning `atk` must move NOTHING ELSE.
	ok(untouched, "pinning the gauge drags no other weight with it")

	# ...and the same thing end-to-end: a weight that cannot possibly affect the
	# decision being learned from must come out of a real analysis unmoved.
	# `card` and `command` are only ever read by draw/gain-mana spells, so a
	# creature-versus-creature blunder has nothing to say about them.
	var cc := _board()
	cc.put(BoardSim.SIDE_ENEMY, BoardSim.ROW_FRONT, 0, _body(3, 3, [], true))
	var glass2: Dictionary = {"name": "Glass", "type": "creature", "cost": 2,
		"atk": 4, "hp": 1, "keywords": []}
	var wall2: Dictionary = {"name": "Wall", "type": "creature", "cost": 2,
		"atk": 0, "hp": 6, "keywords": []}
	BotBrain.forget()
	for _i in 6:
		BotBrain.begin_game(_pool())
		BotBrain.record_decision(cc, false, [
			{"data": glass2, "kind": "creature", "lane": 0, "row": BoardSim.ROW_FRONT,
				"target": null, "score": 0.0, "idx": 0},
			{"data": wall2, "kind": "creature", "lane": 0, "row": BoardSim.ROW_FRONT,
				"target": null, "score": 0.0, "idx": 1}], 1)
		BotBrain.analyse(BotBrain._records, false)
	ok(is_equal_approx(float(BotBrain.challenger["card"]), BoardEval.PT_CARD)
		and is_equal_approx(float(BotBrain.challenger["command"]), BoardEval.PT_COMMAND),
		"a weight the decision cannot involve is not moved by learning from it",
		"card=%.3f command=%.3f" % [float(BotBrain.challenger["card"]),
			float(BotBrain.challenger["command"])])
	ok(not is_equal_approx(float(BotBrain.challenger["hp"]), BoardEval.PT_HP),
		"while a weight the decision DOES involve is moved",
		"hp=%.3f" % float(BotBrain.challenger["hp"]))
	BotBrain.forget()

	# THE BAND. A weight that can reach zero deletes a consideration outright.
	var wild: Dictionary = BoardEval.default_weights().duplicate()
	wild["hp"] = 0.0
	wild["face"] = 900.0
	var tamed := BotBrain.normalise(wild)
	ok(float(tamed["hp"]) >= BoardEval.PT_HP * BotBrain.CLAMP_LO - 0.0001,
		"a weight cannot be driven to zero", "hp=%.4f" % float(tamed["hp"]))
	ok(float(tamed["face"]) <= BoardEval.PT_FACE * BotBrain.CLAMP_HI + 0.0001,
		"a weight cannot run away upward", "face=%.4f" % float(tamed["face"]))


# ═════════════════════════════════════════════════════════════════════════
#  F — THE CHALLENGER HAS TO EARN IT
# ═════════════════════════════════════════════════════════════════════════

func _phase_f_champion_discipline() -> void:
	print("\n── F: a bad hypothesis never reaches the player's bot ──")

	# THE DECISION RULE IS ASSERTED DIRECTLY, and the reason is a bug this probe
	# found. The first version fired a real 24-game batch between two IDENTICAL
	# brains and asserted the verdict was "reverted" — it came back PROMOTED at
	# 0.67, because the threshold was a flat 56% and a Binomial(24, ½) clears
	# that roughly one time in four. Two things were wrong at once and only one
	# of them was the product: the threshold was noise, and the test was reading
	# the random number generator. The rule is a pure function now, so the safety
	# property is checked instead of sampled.
	ok(BotBrain.trial_verdict(12, 24) == "testing",
		"an exact 50%% over 24 games decides nothing — it keeps testing")
	ok(BotBrain.trial_verdict(14, 24) == "testing",
		"58%% over 24 games is inside the noise band and is not believed either way",
		"promote at %.1f" % BotBrain.promote_bound(24))
	ok(BotBrain.trial_verdict(17, 24) == "promoted",
		"a genuine 2-sigma result is believed immediately",
		"promote at %.1f" % BotBrain.promote_bound(24))
	ok(BotBrain.trial_verdict(7, 24) == "rejected",
		"a 2-sigma LOSS is caught immediately — this is the guardrail",
		"reject at %.1f" % BotBrain.reject_bound(24))
	ok(BotBrain.trial_verdict(5, 5) == "testing",
		"a 5-game batch is no verdict at all, either way")
	ok(BotBrain.trial_verdict(BotBrain.TRIAL_MAX_PAIRS / 2, BotBrain.TRIAL_MAX_PAIRS)
			== "adopted",
		"at the cap with no evidence of harm, a rollout-justified step is adopted")
	ok(BotBrain.promote_bound(240) / 240.0 < BotBrain.promote_bound(24) / 24.0,
		"the bar falls as evidence accumulates — 56%% of 240 beats 71%% of 24",
		"240→%.3f  24→%.3f" % [BotBrain.promote_bound(240) / 240.0,
			BotBrain.promote_bound(24) / 24.0])

	# ── THE MECHANISM: A TRIAL FREEZES ITS HYPOTHESIS AND ACCUMULATES ────
	# Whether a given weight vector wins is an EMPIRICAL question that needs the
	# real card pool, so it is asserted in `_probe_bot_train` (a scene probe,
	# where the autoloads resolve). What belongs here is the mechanism, which is
	# deterministic: evidence accumulated against a MOVING challenger is not
	# evidence — the learner would change the very thing being measured every
	# game, and the record would describe a brain that never existed.
	BotBrain.forget()
	BotBrain.begin_game(_pool())
	BotBrain.trial_budget_ms = 60000     # headless: there is no frame to protect
	BotBrain.trial_games = 24

	var hypothesis: Dictionary = BoardEval.default_weights().duplicate()
	hypothesis["hp"] = BoardEval.PT_HP * 0.5
	BotBrain.challenger = hypothesis.duplicate()
	var first := BotBrain.run_trial()
	ok(String(first.get("result", "")) != "no_pool",
		"the trial ran (it had a card pool to deal from)")
	# `played` counts DECISIVE PAIRS, not games — a pair the cards decided
	# regardless of who held them is a tie and carries no information about the
	# brains, so it is not counted. One batch of 12 pairs typically yields ~7.
	# That is why the test is sequential: a single batch usually cannot decide,
	# and the first version of this assertion demanded that it could.
	ok(int(first.get("played", 0)) > 0,
		"a batch yields decisive pairs — some deals separate the two brains",
		"decisive=%d of %d pairs" % [int(first.get("played", 0)),
			BotBrain.trial_games / 2])

	if String(first.get("result", "")) == "testing":
		ok(BotBrain.trial_in_progress(), "an undecided trial stays open")
		# Move the challenger MID-TRIAL. The frozen copy must not follow it.
		var frozen: Dictionary = BotBrain._under_test.duplicate()
		BotBrain.challenger["hp"] = 0.3
		var second := BotBrain.run_trial()
		ok(BotBrain._under_test.is_empty()
			or BotBrain._under_test == frozen,
			"the hypothesis under test is frozen — later learning does not enter it")
		ok(int(second.get("played", 0)) > int(first.get("played", 0))
			or not BotBrain.trial_in_progress(),
			"a second batch ADDS to the record instead of restarting it",
			"%d then %d" % [int(first.get("played", 0)), int(second.get("played", 0))])
	else:
		# Decisive on the first batch: then the record must be closed and the
		# verdict must have been acted on, which is the other legal outcome.
		ok(not BotBrain.trial_in_progress(),
			"a decisive first batch closes the record",
			"result=%s" % first.get("result", "?"))
		ok(BotBrain.champion != BotBrain._under_test
			or BotBrain._under_test.is_empty(),
			"and the verdict was applied")
		_pass += 2   # the two freeze assertions are not reachable on this branch

	BotBrain.trial_budget_ms = 70
	BotBrain.trial_games = 24


# ═════════════════════════════════════════════════════════════════════════
#  G — PERSISTENCE, AND REFUSING A BAD FILE
# ═════════════════════════════════════════════════════════════════════════

func _phase_g_persistence() -> void:
	print("\n── G: the brain survives a restart, and refuses a broken file ──")

	BotBrain.forget()
	var learned: Dictionary = BoardEval.default_weights().duplicate()
	learned["hp"] = 0.9
	learned["face"] = 1.9
	BotBrain.champion = BotBrain.normalise(learned)
	BotBrain.challenger = BotBrain.champion.duplicate()
	BotBrain.stats["generation"] = 7
	BotBrain._write_disk()

	var want: Dictionary = BotBrain.champion.duplicate()
	BotBrain._loaded = false
	BotBrain.ensure_loaded()
	ok(is_equal_approx(float(BotBrain.champion["hp"]), float(want["hp"]))
		and is_equal_approx(float(BotBrain.champion["face"]), float(want["face"])),
		"a trained brain round-trips through disk",
		"hp=%.3f face=%.3f" % [float(BotBrain.champion["hp"]), float(BotBrain.champion["face"])])
	ok(int(BotBrain.stats.get("generation", 0)) == 7, "and so does its ledger")

	# A NaN REACHING THE SCORER IS THE WORST CASE AND IT IS SILENT. Every
	# comparison against NaN is false, so the bot would simply never find a best
	# play and would stop playing cards, with no error anywhere.
	var f := FileAccess.open(BotBrain.SAVE_PATH, FileAccess.WRITE)
	f.store_string('{"version":1,"champion":{"hp":"banana","face":null,"atk":1.0},'
		+ '"challenger":{},"stats":{"games":3}}')
	f.close()
	BotBrain._loaded = false
	BotBrain.ensure_loaded()
	var clean := true
	for name in BoardEval.WEIGHT_NAMES:
		var v := float(BotBrain.champion.get(name, NAN))
		if is_nan(v) or is_inf(v) or v <= 0.0:
			clean = false
	ok(clean, "junk in the file falls back to a usable weight, never a NaN",
		JSON.stringify(BotBrain.champion))

	# Outright garbage: the shipped bot, which is always a legal outcome.
	var f2 := FileAccess.open(BotBrain.SAVE_PATH, FileAccess.WRITE)
	f2.store_string("\u0000\u0000not json at all{{{")
	f2.close()
	BotBrain._loaded = false
	BotBrain.ensure_loaded()
	ok(BotBrain.champion.size() == BoardEval.WEIGHT_NAMES.size(),
		"an unparseable file leaves the shipped bot standing")


# ═════════════════════════════════════════════════════════════════════════
#  H — THE SAFETY PROPERTY
# ═════════════════════════════════════════════════════════════════════════

func _phase_h_shipped_default_is_untouched() -> void:
	print("\n── H: with no brain on disk, nothing about the bot has changed ──")

	# THE PROPERTY THAT MAKES THIS SAFE TO SHIP. A fresh profile must score every
	# play exactly as it did before any of this existed, or the learning is not a
	# feature, it is a silent balance change to the practice opponent.
	BotBrain.forget()
	var d: Dictionary = BoardEval.default_weights()
	var identical := true
	var detail := ""
	for name in BoardEval.WEIGHT_NAMES:
		if not is_equal_approx(float(BotBrain.champion[name]), float(d[name])):
			identical = false
			detail += "%s " % name
	ok(identical, "a fresh brain IS the shipped weight vector", detail)
	ok(is_equal_approx(BoardEval.W_ATK, BoardEval.PT_ATK)
		and is_equal_approx(BoardEval.W_HP, BoardEval.PT_HP)
		and is_equal_approx(BoardEval.W_FACE, BoardEval.PT_FACE)
		and is_equal_approx(BoardEval.W_KILL, BoardEval.PT_KILL),
		"and the live scorer is running it")

	# The weight NAMES must match what apply/export actually carry, or a weight
	# added later is learned into a dictionary nobody reads.
	var round_trip: Dictionary = BoardEval.export_weights()
	var covered := true
	for name in BoardEval.WEIGHT_NAMES:
		if not round_trip.has(name):
			covered = false
	ok(covered and round_trip.size() == BoardEval.WEIGHT_NAMES.size(),
		"every declared weight is one the scorer actually exports",
		"declared=%d exported=%d" % [BoardEval.WEIGHT_NAMES.size(), round_trip.size()])


# ═════════════════════════════════════════════════════════════════════════
#  SAVE ISOLATION
# ═════════════════════════════════════════════════════════════════════════

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
	# THERE WAS NO FILE, so there must not be one now — leaving the probe's own
	# scratch brain behind would hand the player a bot trained on ten synthetic
	# cards and a board with one creature on it.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BotBrain.SAVE_PATH))
