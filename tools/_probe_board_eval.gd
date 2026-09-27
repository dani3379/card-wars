extends SceneTree
## _probe_board_eval.gd — DID THE RETUNE ACTUALLY FIX WHAT IT CLAIMED?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_board_eval.gd
##
## `scripts/combat/BoardEval.gd` replaced the scoring that lived inside
## `SkirmishBot`, on the claim that the old version had four DEFECTS — not soft
## weights, but rules of this game it did not model at all. A claim like that
## needs a test that fails on the old behaviour, or it is just a rewrite with a
## confident comment on top.
##
## WHY THIS RUNS WITHOUT A COMBAT SCENE. Trying to A/B the two scorers through
## `_probe_net_soak` was inconclusive and that result is worth recording: both
## bots end a game around 4-5 HP, because that soak's driver holds a drafted
## `NET_RELIC_POOL` arsenal (+2 Command, +2 cards) against the bot's flat 3
## Command and board-only relics. It measures the RELIC GAP, not play quality, so
## it cannot see a scoring change at all. These assertions are made against the
## scorer directly instead — which is possible only because BoardEval is pure and
## takes the board as ARGUMENTS, so a handful of stubs stand in for the whole
## combat scene and the probe runs in a second.
##
## It also doubles as the standing check on BoardEval's no-autoload rule: this is
## a `--script` probe, so anything BoardEval named by autoload identifier would be
## a hard compile error here while `_probe_parsecheck` stayed green.

const BoardEval = preload("res://scripts/combat/BoardEval.gd")

var _pass := 0
var _fail := 0


class StubBody extends RefCounted:
	var current_hp: int = 1
	var card_data: Dictionary = {}
	var atk: int = 0
	var swings: bool = true
	func effective_atk() -> int:
		return atk
	func can_attack() -> bool:
		return swings
	func is_inert_structure() -> bool:
		return false


class StubCtx extends RefCounted:
	var player_hp: int = 30
	var player_max_hp: int = 30
	var enemy_hp: int = 30
	var enemy_max_hp: int = 30
	# [side][row] -> Array of 4 slots. side 0 = player, 1 = enemy.
	var grid: Array = []

	func _init() -> void:
		grid = []
		for side in 2:
			var rows: Array = []
			for row in 2:
				rows.append([null, null, null, null])
			grid.append(rows)

	func _row_array(is_enemy: bool, row: int) -> Array:
		return grid[1 if is_enemy else 0][row]

	func put(is_enemy: bool, row: int, lane: int, b) -> void:
		grid[1 if is_enemy else 0][row][lane] = b


static func body(atk: int, hp: int, printed_hp: int = -1) -> StubBody:
	var b := StubBody.new()
	b.atk = atk
	b.current_hp = hp
	b.card_data = {"atk": atk, "hp": (hp if printed_hp < 0 else printed_hp),
		"keywords": []}
	return b


func ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s%s" % [label, ("" if detail.is_empty() else "  — " + detail)])


func _init() -> void:
	print("[board-eval] start")

	# ── DEFECT 1: NO CONCEPT OF LETHAL ───────────────────────────────────
	# Old: `damage_face` scored `value * 1.0` — the same number whether the foe
	# sat at 30 or at 3 — so a 2/2 creature (scored ~3.2) beat exact lethal and
	# the bot could sit on the win.
	var c1 := StubCtx.new()
	c1.player_hp = 3          # the pilot's foe... whichever side is "not mine"
	var lethal := BoardEval.face_damage_value(c1, true, 3)   # bot's view
	var chip := BoardEval.face_damage_value(c1, true, 2)
	ok(lethal >= BoardEval.LETHAL,
		"exact lethal is valued as lethal, not as 3 chip damage",
		"got %.1f" % lethal)
	ok(chip < BoardEval.LETHAL and chip > 0.0,
		"non-lethal face damage is still worth something, but not the game",
		"got %.1f" % chip)
	var vanilla := BoardEval.body_value({"atk": 2, "hp": 2, "keywords": []}, true)
	ok(lethal > vanilla, "lethal outranks playing a 2/2 (the old scorer's bug)",
		"lethal=%.1f vanilla=%.1f" % [lethal, vanilla])

	# ── DEFECT 2: OVERKILL WAS FREE ──────────────────────────────────────
	# Old: score was `target_atk * 1.3 + (3.0 if value >= hp)`, so a 6-damage
	# spell on a 2/1 scored exactly what it scored on a 2/6 — removal went to
	# whatever had the highest ATK regardless of how much of the spell was wasted.
	var small := body(2, 1)
	var big := body(2, 6)
	var on_small := BoardEval.damage_value(small, 6)
	var on_big := BoardEval.damage_value(big, 6)
	ok(on_big > on_small,
		"a 6-damage spell prefers the 2/6 over the 2/1 (overkill is wasted)",
		"2/6=%.2f  2/1=%.2f" % [on_big, on_small])
	var exact := BoardEval.damage_value(body(2, 6), 6)
	var overkill := BoardEval.damage_value(body(2, 6), 99)
	ok(is_equal_approx(exact, overkill),
		"damage past lethal on a body adds nothing",
		"6dmg=%.2f 99dmg=%.2f" % [exact, overkill])
	# A kill must still beat mere chip damage of the same landed amount.
	var chip_only := BoardEval.damage_value(body(2, 10), 3)
	var kills := BoardEval.damage_value(body(2, 3), 3)
	ok(kills > chip_only, "killing a body beats chipping one for the same damage",
		"kill=%.2f chip=%.2f" % [kills, chip_only])

	# ── DEFECT 3: IT PREDATED THE MUSTER DELAY (2026-07-21) ──────────────
	# A creature does NOT swing in the clash that ends the round it arrived in.
	# Old: credited `atk * 0.8` of "unblocked pressure" and `+2.0` for "we can
	# kill it" — both describing a swing that cannot happen. Only Swift is exempt,
	# so a Swift body into an open lane must be worth MORE than a vanilla one with
	# identical stats, and the gap is the whole point of the keyword.
	var c3 := StubCtx.new()
	var plain_open := BoardEval.score_creature(c3, true,
		{"atk": 4, "hp": 2, "keywords": []})
	var swift_open := BoardEval.score_creature(c3, true,
		{"atk": 4, "hp": 2, "keywords": ["swift"]})
	ok(float(swift_open["score"]) > float(plain_open["score"]),
		"into an OPEN lane, Swift beats an identical non-Swift body",
		"swift=%.2f plain=%.2f" % [
			float(swift_open["score"]), float(plain_open["score"])])
	# And the arriving body must not be credited with a kill it cannot make.
	var c3b := StubCtx.new()
	c3b.put(false, BoardEval.ROW_FRONT, 0, body(1, 3))   # a killable human body
	var plain_vs := BoardEval.score_creature(c3b, true,
		{"atk": 4, "hp": 2, "keywords": []})
	var swift_vs := BoardEval.score_creature(c3b, true,
		{"atk": 4, "hp": 2, "keywords": ["swift"]})
	ok(float(swift_vs["score"]) > float(plain_vs["score"]),
		"a kill is credited to the body that can actually swing for it",
		"swift=%.2f plain=%.2f" % [
			float(swift_vs["score"]), float(plain_vs["score"])])

	# ── DEFECT 4: THE BACK ROW IS PLAY SPACE ─────────────────────────────
	# Old: a flat `score -= 2.0` with the comment "back row: no immediate combat".
	# Both rows strike every round in this game; front merely goes first. So a
	# fragile hard-hitter placed BEHIND an existing body must not be punished for
	# taking the shelter the back row exists to give.
	#
	# THE FIRST VERSION OF THIS TEST WAS WRONG, and in the way this harness keeps
	# teaching: it left the enemy board EMPTY and then expected a body to seek
	# shelter. With nothing to hide from, an open front lane is the better play
	# and the scorer was right to take it. A shelter test needs a threat.
	var c4 := StubCtx.new()
	c4.put(true, BoardEval.ROW_FRONT, 0, body(1, 5))     # our own wall, lane 0
	for lane in [1, 2, 3]:
		c4.put(false, BoardEval.ROW_FRONT, lane, body(6, 6))   # lethal threats
	var glass := {"atk": 5, "hp": 2, "keywords": []}
	var placed := BoardEval.score_creature(c4, true, glass)
	ok(not placed.is_empty(), "a placement was found")
	ok(int(placed["row"]) == BoardEval.ROW_BACK and int(placed["lane"]) == 0,
		"a fragile hard-hitter shelters behind our own body rather than chumping",
		"chose row=%d lane=%d" % [int(placed["row"]), int(placed["lane"])])
	# And the shelter term itself, isolated: the SAME body in the SAME row is
	# worth more behind one of ours than in an empty column. This is the claim the
	# old flat `-2.0  # back row: no immediate combat` could not express at all.
	var c4b := StubCtx.new()
	c4b.put(true, BoardEval.ROW_FRONT, 0, body(1, 5))
	var occ_b: Array = [[true, true, true, true], [false, false, false, false]]
	var sheltered := BoardEval.score_creature(c4b, true, glass, occ_b)
	ok(int(sheltered["lane"]) == 0 and int(sheltered["row"]) == BoardEval.ROW_BACK,
		"with the whole front row taken, the back slot behind our body wins",
		"chose row=%d lane=%d" % [int(sheltered["row"]), int(sheltered["lane"])])

	# ── ONE CURRENCY ─────────────────────────────────────────────────────
	# The point of the rewrite: numbers from different branches are comparable.
	# A heal that heals nothing is worth nothing, whatever the card prints.
	var full := body(2, 4, 4)
	var hurt := body(2, 1, 4)
	ok(is_equal_approx(BoardEval.heal_value(full, 3), 0.0),
		"healing a full-health body is worth zero, not its printed value")
	ok(BoardEval.heal_value(hurt, 3) > 0.0, "healing a hurt body is worth something")
	ok(BoardEval.heal_value(hurt, 99) <= BoardEval.heal_value(hurt, 3) + 0.01,
		"overhealing adds nothing past what was missing")
	# A buff on a body that cannot swing this round is worth less than on one
	# that can — same card, same target stats, different board.
	var ready := body(3, 3)
	var mustering := body(3, 3)
	mustering.swings = false
	ok(BoardEval.buff_value(ready, 2, 0) > BoardEval.buff_value(mustering, 2, 0),
		"+ATK is worth more on a body that can actually swing this round")

	# ── THE `known` FLAG ─────────────────────────────────────────────────
	# The bot HOLDS what it cannot evaluate; the pilot CASTS it anyway (an
	# unscored spell is an unexercised resolver). That decision belongs to the
	# caller, so the flag has to survive to it rather than be folded into a score.
	var c5 := StubCtx.new()
	var weird := BoardEval.score_play(c5, true,
		{"type": "spell", "spell": {"type": "a_type_nobody_models", "value": 2}})
	ok(not bool(weird.get("known", true)),
		"an unmodelled spell reports known=false rather than a confident zero")
	var dmg := BoardEval.score_play(c5, true,
		{"type": "spell", "spell": {"type": "damage_face", "value": 2}})
	ok(bool(dmg.get("known", false)), "a modelled spell reports known=true")

	# ── THE occ_override CONTRACT ────────────────────────────────────────
	# SkirmishBot picks several plays in one pass and the board does not yet show
	# the slots it already committed to. Without this the bot puts every creature
	# it plays into the same lane.
	var c6 := StubCtx.new()
	var first := BoardEval.score_creature(c6, true, {"atk": 2, "hp": 2, "keywords": []})
	var occ: Array = [[false, false, false, false], [false, false, false, false]]
	occ[int(first["row"])][int(first["lane"])] = true
	var second := BoardEval.score_creature(c6, true,
		{"atk": 2, "hp": 2, "keywords": []}, occ)
	ok(not (int(second["row"]) == int(first["row"])
			and int(second["lane"]) == int(first["lane"])),
		"a committed-but-unapplied slot is not offered twice in one turn",
		"first=(%d,%d) second=(%d,%d)" % [int(first["row"]), int(first["lane"]),
			int(second["row"]), int(second["lane"])])

	# ── THE RAMP CAP IS RESTATED, SO IT IS PINNED ───────────────────────
	# BoardEval names no autoload and holds no Combat reference — that is what
	# lets this gate run with stubs and no scene at all — so it carries its own
	# copy of the Command ramp's ceiling, which `_command_scarcity` divides by
	# and SkirmishBot.build_deck uses as its deck-building ceiling. A restated
	# magnitude is the drift this codebase has already paid for once
	# (NetPlayerState restating every relic's value as a literal), so the copy is
	# checked against the authority here rather than trusted.
	var combat_src := FileAccess.get_file_as_string("res://scripts/scenes/Combat.gd")
	var cap_re := RegEx.new()
	cap_re.compile("const COMMAND_RAMP_CAP: int = (\\d+)")
	var cap_m := cap_re.search(combat_src)
	ok(cap_m != null, "Combat.gd still declares COMMAND_RAMP_CAP")
	if cap_m != null:
		ok(int(cap_m.get_string(1)) == BoardEval.RAMP_CAP_ASSUMED,
			"BoardEval.RAMP_CAP_ASSUMED matches Combat.COMMAND_RAMP_CAP",
			"combat=%s boardeval=%d" % [cap_m.get_string(1), BoardEval.RAMP_CAP_ASSUMED])

	# ── DEFECT 5: A BODY IN A COLUMN DENIES THE FACE (2026-09-19) ────────
	# `_clash_lane_pass` resolves "opposing front, else opposing back, else
	# FACE", so an unblocked column bills the hero in full every round. The
	# scorer priced a block at the damage the blocker's own HP absorbed and
	# credited the hero's skin at nothing — which is why the pilot's own damage
	# ledger found 93-96% of all damage taken arriving through open lanes.
	var cD := StubCtx.new()
	cD.put(false, BoardEval.ROW_FRONT, 0, body(5, 5))   # a live threat, lane 0
	var wall := {"atk": 1, "hp": 8, "keywords": []}     # survives the blow
	var guard := BoardEval.score_creature_at(cD, true, wall, 0, BoardEval.ROW_FRONT)
	var idle := BoardEval.score_creature_at(cD, true, wall, 2, BoardEval.ROW_FRONT)
	ok(guard > idle,
		"a wall in the threatened column beats the same wall in an empty one",
		"guard=%.2f idle=%.2f" % [guard, idle])

	# ...AND A CHUMP IS NOT A WALL. A body that dies to the blow has not closed
	# the lane, it has moved one instalment back by a round. Priced the same,
	# the scorer chumps every lane it can reach instead of winning.
	var paper := {"atk": 1, "hp": 2, "keywords": []}
	var stone := {"atk": 1, "hp": 8, "keywords": []}
	var d_paper := BoardEval.score_creature_at(cD, true, paper, 0, BoardEval.ROW_FRONT) \
		- BoardEval.score_creature_at(cD, true, paper, 2, BoardEval.ROW_FRONT)
	var d_stone := BoardEval.score_creature_at(cD, true, stone, 0, BoardEval.ROW_FRONT) \
		- BoardEval.score_creature_at(cD, true, stone, 2, BoardEval.ROW_FRONT)
	ok(d_stone > d_paper,
		"blocking is worth more to a body that SURVIVES the blow than to one that dies",
		"stone=%+.2f paper=%+.2f" % [d_stone, d_paper])

	# PIERCING READS THROUGH THE WALL, so the same wall denies less against it.
	#
	# THE FIRST VERSION OF THIS TEST COULD NOT FAIL, in the house way: it put an
	# 8 HP wall in front of a 5 ATK piercer, where `mini(fa, hp)` IS `fa` and
	# there is no overflow for Piercing to carry. Both arms returned 18.75 and
	# the test was reading its own fixture, not the rule. Piercing only means
	# anything when the blow EXCEEDS the blocker, so the blocker has to be one
	# the blow gets through.
	var cDp := StubCtx.new()
	var spear := body(5, 5)
	spear.card_data["keywords"] = ["piercing"]
	cDp.put(false, BoardEval.ROW_FRONT, 0, spear)
	var thin := {"atk": 1, "hp": 3, "keywords": []}     # 5 damage gets through
	var vs_pierce := BoardEval.score_creature_at(cDp, true, thin, 0, BoardEval.ROW_FRONT)
	var vs_plain := BoardEval.score_creature_at(cD, true, thin, 0, BoardEval.ROW_FRONT)
	ok(vs_pierce < vs_plain,
		"a wall is worth less against Piercing, which reads on to the face anyway",
		"pierce=%.2f plain=%.2f" % [vs_pierce, vs_plain])

	# ── THE BACK ROW REACHES THE FACE (2026-09-19) ───────────────────────
	# The front arm has always credited `atk * FACE * OPEN_LANE` for an
	# unopposed lane; the back arm scored the same body in the same empty column
	# a flat +0.3. That is not a preference for the front row, it is the back
	# row's offence being invisible — the same blind spot DEFECT 4 was about.
	var cE := StubCtx.new()
	cE.put(true, BoardEval.ROW_FRONT, 0, body(1, 5))    # our own wall to hide behind
	var hitter := {"atk": 6, "hp": 2, "keywords": []}
	var behind := BoardEval.score_creature_at(cE, true, hitter, 0, BoardEval.ROW_BACK)
	var tiny := {"atk": 1, "hp": 2, "keywords": []}
	var behind_small := BoardEval.score_creature_at(cE, true, tiny, 0, BoardEval.ROW_BACK)
	ok(behind - behind_small > 3.0,
		"a big hitter in a clear column is worth more in the back row than a small one",
		"big=%.2f small=%.2f" % [behind, behind_small])

	# ── DRAFT VALUE (2026-09-19) ─────────────────────────────────────────
	# `score_play` asks what a card is worth on THIS board. Drafting asks what it
	# is worth to OWN, and the pilot answered that with `randi_range` until today
	# — including at the shop's paid removal, where a coin-flip can delete the
	# run's best card for 60 gold. These are the claims the replacement makes.
	var vanilla_2 := {"id": "a", "type": "creature", "cost": 2, "atk": 2, "hp": 2,
		"keywords": []}
	var beefy_2 := {"id": "b", "type": "creature", "cost": 2, "atk": 4, "hp": 4,
		"keywords": []}
	ok(BoardEval.draft_value(beefy_2) > BoardEval.draft_value(vanilla_2),
		"at equal cost, the bigger body drafts higher",
		"4/4=%.2f 2/2=%.2f" % [BoardEval.draft_value(beefy_2),
			BoardEval.draft_value(vanilla_2)])
	var dear := vanilla_2.duplicate()
	dear["cost"] = 5
	ok(BoardEval.draft_value(dear) < BoardEval.draft_value(vanilla_2),
		"the same body costs more to own at a higher price",
		"cost5=%.2f cost2=%.2f" % [BoardEval.draft_value(dear),
			BoardEval.draft_value(vanilla_2)])

	# THE CURVE IS A DECK TERM, NOT A CARD TERM. A deck of six-drops cannot act
	# before round 6 and loses the board while it waits — which is not any one
	# card's fault, and is exactly why this is keyed off the profile.
	var flat := BoardEval.deck_profile([])
	var stacked := BoardEval.deck_profile([vanilla_2, vanilla_2, vanilla_2,
		vanilla_2, vanilla_2])
	ok(BoardEval.draft_value(vanilla_2, stacked)
			< BoardEval.draft_value(vanilla_2, flat),
		"the sixth copy of a cost band is worth less than the first",
		"stacked=%.2f empty=%.2f" % [BoardEval.draft_value(vanilla_2, stacked),
			BoardEval.draft_value(vanilla_2, flat)])
	ok(int((stacked["costs"] as Dictionary).get(2, 0)) == 5,
		"deck_profile counts cost bands")

	# AN UNREADABLE SPELL MUST NOT BE AUTOMATICALLY DECLINED. 78 of the 87 spells
	# carry `type: "custom"` and say what they do only in their rules text, so a
	# COST-INDEPENDENT floor made every expensive one score strongly negative:
	# measured live, `holy_smite` at cost 4 came out at -2.90 against a 4-cost
	# creature at +3.10, purely because the model could not read it.
	var mystery := {"id": "s", "type": "spell", "cost": 4, "keywords": [],
		"spell": {"type": "custom"}}
	var mystery_cheap := {"id": "s2", "type": "spell", "cost": 1, "keywords": [],
		"spell": {"type": "custom"}}
	ok(BoardEval.draft_value(mystery) > -1.5,
		"an unreadable spell is priced as if fairly costed, not as worthless",
		"cost4 spell = %.2f" % BoardEval.draft_value(mystery))
	# AGAINST A DECK THAT ALREADY HOLDS CHEAP PLAYS, so the "nothing castable on
	# rounds 1-2" bonus is not firing. The first version of this check left the
	# profile EMPTY and measured a 1.95 gap — of which 1.5 was that bonus, a DECK
	# term, landing on the cost-1 card. It was reading two rules and attributing
	# both to the one under test.
	var one_drop := {"id": "c", "type": "creature", "cost": 1, "atk": 1, "hp": 2,
		"keywords": []}
	var has_cheap := BoardEval.deck_profile([one_drop, one_drop, one_drop,
		one_drop, one_drop])
	ok(absf(BoardEval.draft_value(mystery, has_cheap)
			- BoardEval.draft_value(mystery_cheap, has_cheap)) < 1.5,
		"and the prior scales with cost, so price alone does not decide it",
		"cost4=%.2f cost1=%.2f" % [BoardEval.draft_value(mystery, has_cheap),
			BoardEval.draft_value(mystery_cheap, has_cheap)])

	# SYNERGY IS DELIBERATELY SMALL. A draft policy that chases a tribe hard
	# enough to take a weak card for it builds a themed deck that loses.
	var tribal := vanilla_2.duplicate()
	tribal["ctype"] = "soldier"
	var soldiers: Array = []
	for _i in 6:
		soldiers.append(tribal)
	var tribe_profile := BoardEval.deck_profile(soldiers)
	ok(BoardEval.draft_value(tribal, tribe_profile)
			< BoardEval.draft_value(beefy_2, tribe_profile),
		"tribe synergy cannot lift a weak card over a clearly better one",
		"2/2 soldier=%.2f 4/4 off-tribe=%.2f" % [
			BoardEval.draft_value(tribal, tribe_profile),
			BoardEval.draft_value(beefy_2, tribe_profile)])

	# A Command is worth more when you hold fewer of them. A ctx with no round at
	# all (BoardSim's SimCtx) must fall through to the neutral late-game value,
	# never to a divide-by-zero or a silent 0.
	var r1 := BoardEval._command_scarcity(StubCtx.new())
	ok(is_equal_approx(r1, 1.0),
		"a ctx with no round scores Command neutrally (%.2f)" % r1)

	print("")
	if _fail == 0:
		print("[board-eval] ALL PASS (%d checks)" % _pass)
	else:
		print("[board-eval] %d FAILED of %d" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)
