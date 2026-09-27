extends SceneTree
## _probe_personas.gd — THE PERSONAS ARE ACTUALLY DIFFERENT PLAYERS (2026-09-16).
##
## `scripts/combat/Personas.gd` exists so difficulty can be read as an ENVELOPE
## across several agents instead of one number from one policy. That only works if
## the agents genuinely play differently, and the single most likely failure is
## that they do not: a persona is a weight vector, and the sensitivity sweep in
## CLAUDE.md measured FOUR of BoardEval's thirteen weights (`card`, `command`,
## `kill`, `back_exposed`) changing not one decision in skirmish. A roster
## differentiated on inert weights would install cleanly, print five names, produce
## five plausible win rates, and be measuring the baseline five times.
##
## So the headline assertion here is DIVERGENCE, and it is deliberately the
## expensive kind: every persona is asked to choose on the same staged boards, and
## pairs that never once disagree are named as failures. An upper-bound style
## "they are configured differently" check would pass on exactly the roster this
## probe exists to reject.
##
## It runs `--script` with STUB boards and no Combat scene, which is what
## `BoardEval` taking the board as an argument buys — and being `--script` is also
## the standing check that neither file names an autoload (a bare `CardDB` inside
## one is a hard compile error here while parsecheck, which runs as a SCENE, stays
## green).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_personas.gd

const BoardEval = preload("res://scripts/combat/BoardEval.gd")
const Personas = preload("res://scripts/combat/Personas.gd")

var _checks := 0
var _fails: Array[String] = []


# ── STUBS (the _probe_board_eval pattern — one board, no scene) ──────────────
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


class StubCard extends RefCounted:
	var card_data: Dictionary = {}


class StubCtx extends RefCounted:
	var player_hp: int = 30
	var player_max_hp: int = 30
	var enemy_hp: int = 30
	var enemy_max_hp: int = 30
	var player_mana: int = 6
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


func _init() -> void:
	call_deferred("_run")


func _body(atk: int, hp: int) -> StubBody:
	var b := StubBody.new()
	b.atk = atk
	b.current_hp = hp
	b.card_data = {"atk": atk, "hp": hp, "keywords": []}
	return b


func _card(id: String, cost: int, atk: int, hp: int, kws: Array = []) -> StubCard:
	var c := StubCard.new()
	c.card_data = {"id": id, "name": id, "type": "creature", "cost": cost,
		"atk": atk, "hp": hp, "keywords": kws.duplicate(), "rarity": "common"}
	return c


func _spell(id: String, cost: int, type: String, value: int, targeting: String) -> StubCard:
	var c := StubCard.new()
	c.card_data = {"id": id, "name": id, "type": "spell", "cost": cost,
		"keywords": [], "rarity": "common", "targeting": targeting,
		"spell": {"type": type, "value": value}}
	return c


## A hand wide enough that preference can express itself. A two-card hand makes
## every persona agree by force and would report a roster of clones as healthy.
func _hand() -> Array:
	return [
		_card("bruiser", 3, 4, 2),          # aggro's pick: all damage, dies fast
		_card("wall", 3, 1, 6),             # control's pick: stops a column
		_card("balanced", 3, 3, 3),
		_card("cheap_body", 1, 1, 2),
		_spell("bolt", 2, "damage", 4, "enemy_creature"),   # trader's pick
		_spell("burn_face", 2, "damage_face", 3, "none"),   # aggro's other pick
	]


func _board() -> StubCtx:
	var c := StubCtx.new()
	# A real mid-fight position: the foe holds a column and threatens, the player
	# has one body. Both a wall and a race are defensible here, which is exactly
	# the state that separates personas — a board with one legal play cannot.
	c.put(true, 0, 0, _body(3, 4))
	c.put(true, 0, 1, _body(2, 2))
	c.put(true, 1, 0, _body(5, 1))
	c.put(false, 0, 0, _body(2, 3))
	c.enemy_hp = 14
	c.player_hp = 18
	return c


## A second position with the hero nearly dead — `face` and `kill` weights bite
## hardest near lethal, and a roster that only diverges on a quiet board has not
## been tested where the differences matter.
func _board_lethal_range() -> StubCtx:
	var c := StubCtx.new()
	c.put(true, 0, 1, _body(2, 2))
	c.put(false, 0, 0, _body(3, 3))
	c.enemy_hp = 5
	c.player_hp = 26
	return c


func _board_under_pressure() -> StubCtx:
	var c := StubCtx.new()
	c.put(true, 0, 0, _body(4, 3))
	c.put(true, 0, 1, _body(4, 3))
	c.put(true, 0, 2, _body(2, 5))
	c.enemy_hp = 24
	c.player_hp = 7
	return c


func _run() -> void:
	print("[personas] roster: %s" % str(Personas.ids()))

	# ── A · THE ROSTER IS WELL FORMED ───────────────────────────────────────
	var names := {}
	for pid in Personas.ids():
		var w: Dictionary = Personas.weights_of(String(pid))
		_check("%s: weight vector is COMPLETE" % pid,
			w.size() == BoardEval.WEIGHT_NAMES.size())
		for k in BoardEval.WEIGHT_NAMES:
			if not w.has(k):
				_fail("%s: missing weight '%s' — a partial vector inherits whatever the previous persona set" % [pid, k])
				break
		# THE GAUGE. BoardEval is invariant under a uniform rescale, so a persona
		# free to move `atk` could differ from another by a pure scale factor and
		# be the same player under a different name.
		_check("%s: `atk` is pinned at the 1.0 gauge" % pid,
			absf(float(w.get("atk", 0.0)) - 1.0) < 0.0001)
		var dn: String = Personas.display_name(String(pid))
		_check("%s: has a display name" % pid, dn != "" and dn != String(pid) or String(pid) == dn)
		names[dn] = true
		# Traits must resolve for every persona, defaulted or named.
		_check("%s: blunder_rate resolves to a float in [0,1)" % pid,
			float(Personas.trait_of(String(pid), "blunder_rate", -1.0)) >= 0.0
			and float(Personas.trait_of(String(pid), "blunder_rate", -1.0)) < 1.0)
		_check("%s: reserve_command never exceeds what can be banked" % pid,
			int(Personas.trait_of(String(pid), "reserve_command", 0)) <= 2)

	_check("`curve` is the untouched control arm (defaults verbatim)",
		Personas.weights_of("curve").hash() == BoardEval.default_weights().hash())

	# ── B · INSTALL / RESTORE IS EXACT ──────────────────────────────────────
	# The weights are STATIC and shared with SkirmishBot/BotBrain. A persona that
	# leaks past its own fight silently retunes the practice bot.
	var before: Dictionary = BoardEval.export_weights()
	for pid in Personas.ids():
		var prev: Dictionary = Personas.install(String(pid))
		var live: Dictionary = BoardEval.export_weights()
		_check("%s: install() actually writes the vector" % pid,
			live.hash() == Personas.weights_of(String(pid)).hash())
		Personas.restore(prev)
		_check("%s: restore() puts back EXACTLY what was there" % pid,
			BoardEval.export_weights().hash() == before.hash())
	_check("the weights are untouched after the whole install sweep",
		BoardEval.export_weights().hash() == before.hash())

	# ── C · THE HEADLINE: THEY MUST ACTUALLY DIVERGE ────────────────────────
	# Four of the thirteen weights were measured inert; a roster differentiated on
	# those would pass every check above and be one player wearing five names.
	var boards: Array = [_board(), _board_lethal_range(), _board_under_pressure()]
	var board_names: Array = ["contested", "lethal-range", "under-pressure"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 90916

	# persona -> [chosen card id per board]
	var picks := {}
	for pid in Personas.ids():
		var row: Array = []
		for b in boards:
			# blunder_rate is defeated by passing rng = null, so this measures the
			# WEIGHTS. Otherwise `novice` would "diverge" by rolling dice, which
			# proves nothing about whether the vectors differ.
			var play: Dictionary = Personas.choose(b, String(pid), _hand(), null)
			row.append("" if play.is_empty() else String(play["card"].card_data.get("id", "?")))
		picks[String(pid)] = row
		print("[personas]   %-8s picks: %s" % [pid, str(row)])

	for i in range(board_names.size()):
		var seen := {}
		for pid in Personas.ids():
			seen[picks[String(pid)][i]] = true
		_check("board '%s': the roster does not move as one (%d distinct plays)"
			% [board_names[i], seen.size()], seen.size() >= 2)

	# Every PAIR must disagree somewhere. This is the check that actually rejects
	# a clone: a roster where four personas agree always and one differs still
	# scores "2 distinct plays" on every board above.
	var ids: Array = Personas.ids()
	for a in range(ids.size()):
		for b in range(a + 1, ids.size()):
			var pa := String(ids[a])
			var pb := String(ids[b])
			if pa == "novice" or pb == "novice":
				continue   # novice IS `curve`'s vector by design — it differs by SKILL, checked in D
			var differs := false
			for i in range(boards.size()):
				if picks[pa][i] != picks[pb][i]:
					differs = true
					break
			_check("%s and %s choose differently on at least one board" % [pa, pb], differs)

	_check("`novice` shares `curve`'s vector (it is a SKILL tier, not a style)",
		Personas.weights_of("novice").hash() == Personas.weights_of("curve").hash())

	# ── D · SKILL IS A REAL DIAL, SEPARATE FROM STYLE ───────────────────────
	# `novice` must actually misplay, and `curve` must never do so. Without this
	# the skill axis is decoration.
	var board := _board()
	var expert_pick: Dictionary = Personas.choose(board, "curve", _hand(), null)
	_check("a scored board yields a play at all", not expert_pick.is_empty())

	var blunders := 0
	var novice_rng := RandomNumberGenerator.new()
	novice_rng.seed = 4242
	for _i in 200:
		var p: Dictionary = Personas.choose(board, "novice", _hand(), novice_rng)
		if not p.is_empty() and bool(p.get("blundered", false)):
			blunders += 1
	var rate := float(blunders) / 200.0
	var want := float(Personas.trait_of("novice", "blunder_rate", 0.0))
	print("[personas]   novice blundered %d/200 (%.2f, wants %.2f)" % [blunders, rate, want])
	_check("novice's blunder rate lands near its declared dial (%.2f vs %.2f)" % [rate, want],
		absf(rate - want) < 0.10)

	var curve_rng := RandomNumberGenerator.new()
	curve_rng.seed = 4242
	var curve_blunders := 0
	for _i in 200:
		var p: Dictionary = Personas.choose(board, "curve", _hand(), curve_rng)
		if not p.is_empty() and bool(p.get("blundered", false)):
			curve_blunders += 1
	_check("an expert persona NEVER blunders (%d/200)" % curve_blunders, curve_blunders == 0)

	# A blunder must be a genuinely different play, never a re-roll onto the best
	# one — otherwise the dial reads higher than the misplay rate it produces.
	var best_id := String(expert_pick["card"].card_data.get("id", "?"))
	var blunder_hit_best := false
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 777
	for _i in 300:
		var p: Dictionary = Personas.choose(board, "novice", _hand(), nrng)
		if p.is_empty() or not bool(p.get("blundered", false)):
			continue
		if String(p["card"].card_data.get("id", "?")) == best_id:
			blunder_hit_best = true
			break
	_check("a blunder is never the best play wearing the label", not blunder_hit_best)

	# ── E · TRAITS ARE HONOURED ─────────────────────────────────────────────
	var poor := _board()
	poor.player_mana = 1
	var p1: Dictionary = Personas.choose(poor, "curve", _hand(), null)
	_check("at Command 1 only a 1-cost play is offered",
		p1.is_empty() or int(p1["card"].card_data.get("cost", 99)) <= 1)

	# A reserve must not be able to produce a dead turn. `control` holds 1 back;
	# at exactly 1 Command that would leave nothing spendable, and a persona that
	# passes every round measures nothing.
	var tight := _board()
	tight.player_mana = 1
	var pc: Dictionary = Personas.choose(tight, "control", _hand(), null)
	_check("a reserve never starves the turn entirely", not pc.is_empty())

	var reserved := _board()
	reserved.player_mana = 3
	var pr: Dictionary = Personas.choose(reserved, "control", _hand(), null)
	_check("control holds its reserve back when it can afford to (<= 2 of 3 spent)",
		pr.is_empty() or int(pr["card"].card_data.get("cost", 99)) <= 2)

	# `use_potions` / `drink_below_hp` are consumed by `should_drink`, not by
	# `choose`. Asserted here because a trait with no consumer is dead config that
	# reads as behaviour — the reason `mark_discards` was removed rather than kept
	# as a promise.
	var hurt := _board()
	hurt.player_hp = 10
	hurt.player_max_hp = 30
	var healthy := _board()
	healthy.player_hp = 30
	healthy.player_max_hp = 30
	_check("a drinker reaches for the belt when hurt", Personas.should_drink(hurt, "curve"))
	_check("a drinker leaves it alone at full HP", not Personas.should_drink(healthy, "curve"))
	_check("novice never drinks, hurt or not",
		not Personas.should_drink(hurt, "novice") and not Personas.should_drink(healthy, "novice"))
	var zero := _board()
	zero.player_max_hp = 0
	_check("a zero max-HP board does not divide by zero", not Personas.should_drink(zero, "curve"))

	var blocked: Dictionary = Personas.choose(_board(), "curve", _hand(), null,
		["bruiser", "wall", "balanced", "cheap_body", "bolt", "burn_face"])
	_check("a fully blocklisted hand yields a pass, not a crash", blocked.is_empty())
	_check("an empty hand yields a pass", Personas.choose(_board(), "curve", [], null).is_empty())
	_check("an unknown persona id yields a pass rather than a wrong player",
		Personas.choose(_board(), "no_such_persona", _hand(), null).is_empty())

	# The roster must not have leaked a persona into the process on the way out.
	_check("weights are still the shipped defaults at teardown",
		BoardEval.export_weights().hash() == before.hash())

	print("")
	if _fails.is_empty():
		print("[personas] %d checks, all pass" % _checks)
		print("PROBE PASS: personas")
		quit(0)
	else:
		for f in _fails:
			printerr("  FAIL  %s" % f)
		printerr("[personas] %d checks, %d FAIL" % [_checks, _fails.size()])
		printerr("PROBE FAIL: personas")
		quit(1)


func _check(msg: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails.append(msg)


func _fail(msg: String) -> void:
	_checks += 1
	_fails.append(msg)
