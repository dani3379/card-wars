extends Node
## _probe_sim_fidelity.gd — HOW WRONG IS THE FORWARD MODEL?
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_sim_fidelity.tscn
##   ... -- --boards=120        (default 120)
##
## `BoardSim` is a SECOND implementation of the clash. This codebase has a
## standing rule about that shape and has already paid for breaking it once
## (`NetPlayerState` restating every relic's magnitude as a literal instead of
## reading RelicDB: equal on the day it was written, one retune from silently
## diverging). The usual fix — delete the copy — is not available here:
## `Combat._do_combat` awaits animation beats, mutates Card2D nodes, fires audio
## and ships net events, and a rollout has to resolve a board thousands of times
## a second with no scene at all. The copy has to exist.
##
## So the rule becomes: **if you cannot remove the second implementation, measure
## the gap and fail when it widens.** That is this file. It stages the same
## random board in both, runs the REAL clash and one `BoardSim.step_round`, and
## diffs the results slot by slot.
##
## ── THIS IS THE NUMBER BEHIND "0.810 ACCORDING TO BOARDSIM" ──────────────
## `_probe_bot_train` reports the trained bot beating the shipped one 0.810, and
## says in the same breath that both were measured inside the model. Everything
## the model gets wrong is a way for that figure to be optimistic. Until now the
## size of "everything" was unknown. `_probe_bot_brain` phase A pins ten named
## rules one fixture at a time, which proves the rules are implemented and says
## nothing about how they COMPOSE on a full board — and composition is exactly
## where a re-implementation drifts.
##
## ── IT IS A BUDGET, NOT AN EQUALITY ──────────────────────────────────────
## Perfect agreement is not the goal and is not reachable: the sim deliberately
## omits triggers, relics and encounter passives (see its header). The fixtures
## here are raw stat bodies with no card text precisely so that those omissions
## are not what is being measured — what is left is the CLASH ARITHMETIC, and
## that should agree almost exactly. A drop below the floor means the two
## implementations have drifted on a rule, and the report names which board.

const BoardEval = preload("res://scripts/combat/BoardEval.gd")
const BoardSim = preload("res://scripts/combat/BoardSim.gd")
const COMBAT_SCENE := "res://scenes/combat.tscn"

## Keywords the sim claims to model. Deliberately NOT the whole keyword table:
## staging a board out of effects the sim never promised to resolve would measure
## the omission list, which is already written down, instead of the arithmetic.
const KW_POOL := ["", "", "", "armored", "thorns", "piercing", "last_stand",
	"swift", "regenerate", "lifelink"]

## ── WHAT THIS FOUND, AND WHERE IT STANDS ────────────────────────────────
## First run: 78.6% of slots agreed. Four real rules were missing from the model,
## and every one of them was invisible to `_probe_bot_brain` phase A because
## phase A checks one rule per fixture and these only show up in composition:
##   1. THE MUSTERING DEFENDER'S COUNTER. The muster delay stops a body
##      INITIATING, never DEFENDING — a creature that arrived this round trades
##      on the counter instead. The model gave it nothing, so every rollout
##      treated a freshly-played blocker as a free kill and the learner was being
##      taught to undervalue the play the front row exists for.
##   2. SWIFT TAKES NOTHING BACK (quick attack) — it must not draw that counter.
##   3. A 0-ATK BODY STILL ENGAGES, so a wall still gets its counter off it.
##   4. READINESS IS `ready_to_swing`, NOT `can_attack()` — they differ on
##      exactly the body that matters, a Swift creature on its arrival round,
##      and the Rush face-bar keys off the former.
## With those four fixed: **960 of 960 slots agree and 91.7% of boards match
## exactly.** The residual is FACE DAMAGE ONLY — about 0.2 HP per board — and is
## not yet explained; it is bounded, measured, and left named rather than
## papered over. Bodies are what a rollout's valuation is mostly made of.
##
## Floors are set from that measurement with slack. They are a REGRESSION floor,
## not a target to tune toward: the number to care about is the direction it
## moves after someone edits the clash.
const MATCH_FLOOR := 0.85
const SLOT_FLOOR := 0.99

var _pass := 0
var _fail := 0
var _rng := RandomNumberGenerator.new()


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
	print("[sim-fidelity] start")
	_rng.seed = 20260915

	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _plain_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	# BIG HEROES ON BOTH SIDES. The clash must never end the fight mid-fixture:
	# a match-over check would stop the real pass early and the sim would resolve
	# a round the engine never finished, which reads as a model error and is not.
	RunState.hero_max_hp = 9000
	RunState.hero_hp = 9000
	# NO RELICS. `start_new_run` deals the hero's doctrine relics, and a relic is
	# not part of the clash — the sim never claimed to model one. Left in, they
	# fire extra strike phases (`_run_armament_second_strikes`, twinblade,
	# doubled-hour) and death-triggered summons, and the diff then reports bodies
	# on the real board that the fixture never staged. That is the relic working,
	# not the model failing.
	RunState.relics.clear()
	await get_tree().process_frame

	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	ok(combat.round_number >= 1, "the real combat scene reached round 1")
	# SETTLE UNTIL IT HOLDS, never a fixed timer. `_deal_opening_muster` seats the
	# enemy line over several frames, and the first version of this probe started
	# staging fixtures while it was still dealing — so bodies the fixture never
	# placed kept appearing on the real board mid-clash and were reported as the
	# model inventing creatures. Wait for the board to stop changing.
	var stable := 0
	var last := -1
	while stable < 12 and waited < 600:
		var n: int = combat._all_creatures_both_sides().size()
		stable = stable + 1 if n == last else 0
		last = n
		await get_tree().process_frame
		waited += 1
	ok(stable >= 12, "the opening muster finished dealing before fixtures began",
		"board settled at %d bodies" % last)
	combat.enemy_hp = 9000
	combat.enemy_max_hp = 9000
	combat.player_hp = 9000
	combat.player_max_hp = 9000
	# NOTHING MAY ARRIVE MID-FIXTURE. The enemy's deck and its infinite
	# reinforcement are the round ladder's business, not the clash's — but the
	# clash awaits many frames and the scene is live, so a placement landing in
	# the middle of one shows up in the diff as the model losing a creature it
	# never had. Empty the sources rather than trying to out-race them.
	combat._enemy_deck.clear()
	combat._reinforcement = {}
	var round_at_start: int = int(combat.round_number)

	var boards := _arg("boards", 120)
	var exact := 0
	var bodies_seen := 0
	var bodies_wrong := 0
	var face_err_total := 0
	var worst: Array[String] = []

	for b in boards:
		_clear_board(combat)
		var plan := _stage(combat)
		combat.player_hp = 9000
		combat.enemy_hp = 9000

		# CAPTURE FIRST — the snapshot must describe the board the real pass is
		# about to resolve, including each body's readiness.
		var snap: BoardSim.SimCtx = BoardSim.capture(combat)
		snap.player_hp = 9000
		snap.enemy_hp = 9000
		snap.player_max_hp = 9000
		snap.enemy_max_hp = 9000

		# CLASH AGAINST CLASH — the model runs `clash` only, because the round
		# ladder around it (start-of-round ticks, the muster sweep) is a different
		# beat. Calling `step_round` here charges the model for a Regenerate tick
		# the engine has not run yet.
		await _real_clash(combat)
		BoardSim.clash(snap)

		var diff := _diff(combat, snap)
		if _arg("verbose", 0) > 0 and (diff["wrong"] != 0 or diff["face_err"] != 0) \
				and worst.size() < 2:
			print("\n  --- board %d ---" % b)
			print("  staged : %s" % plan)
			print("  real   : %s   face %d/%d" % [_dump_real(combat),
				int(combat.player_hp), int(combat.enemy_hp)])
			print("  sim    : %s   face %d/%d" % [_dump_sim(snap),
				snap.player_hp, snap.enemy_hp])
		bodies_seen += int(diff["slots"])
		bodies_wrong += int(diff["wrong"])
		face_err_total += int(diff["face_err"])
		if diff["wrong"] == 0 and diff["face_err"] == 0:
			exact += 1
		elif worst.size() < 6:
			worst.append("%s  ->  %s" % [plan, String(diff["why"])])

		# The real pass sets has_attacked_this_turn on everything it moved; the
		# next fixture needs a clean board anyway, so teardown handles it.
		if b % 20 == 19:
			await get_tree().process_frame

	# If the scene ran its OWN round ladder while the fixtures were running, every
	# number above describes two games interleaved and none of it means anything.
	ok(int(combat.round_number) == round_at_start,
		"the live scene never advanced a round of its own during the fixtures",
		"round %d -> %d" % [round_at_start, int(combat.round_number)])
	var rate := float(exact) / float(maxi(boards, 1))
	var body_rate := 1.0 - float(bodies_wrong) / float(maxi(bodies_seen, 1))
	print("\n  boards compared      : %d" % boards)
	print("  exact whole-board    : %d  (%.3f)" % [exact, rate])
	print("  slots agreeing       : %d of %d  (%.4f)"
		% [bodies_seen - bodies_wrong, bodies_seen, body_rate])
	print("  total face-HP error  : %d across %d boards" % [face_err_total, boards])
	if not worst.is_empty():
		print("\n  boards where they disagreed:")
		for w in worst:
			print("    " + w)

	ok(rate >= MATCH_FLOOR,
		"the forward model reproduces the real clash on at least %d%% of boards"
			% int(MATCH_FLOOR * 100.0),
		"got %.3f over %d boards" % [rate, boards])
	# A per-slot floor as well as a per-board one: one board can be wrong in one
	# corner and it matters much less than every board being wrong everywhere.
	ok(body_rate >= SLOT_FLOOR,
		"and agrees on at least %d%% of individual slots" % int(SLOT_FLOOR * 100.0),
		"got %.4f" % body_rate)
	# VACUITY. If the fixtures never put anything on the board, everything above
	# passes by describing nothing.
	ok(bodies_seen >= boards * 4,
		"the fixtures actually staged boards worth comparing",
		"%d slots over %d boards" % [bodies_seen, boards])

	print("\n[sim-fidelity] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════════════════
#  FIXTURES
# ═════════════════════════════════════════════════════════════════════════

## An encounter with NO passive. A fight passive is not part of the clash and the
## sim never claimed to model one, so staging on top of one would measure the
## omission list rather than the arithmetic.
func _plain_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat" \
				and String(e.get("passive_id", "")).is_empty():
			return String(id)
	return ""


## Random bodies on both sides. Returns a one-line description so a disagreement
## can be reproduced by hand.
func _stage(combat) -> String:
	var desc: PackedStringArray = PackedStringArray()
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			for lane in range(combat.LANES_PER_ROW):
				if _rng.randf() > 0.55:
					continue
				var atk := _rng.randi_range(0, 7)
				var hp := _rng.randi_range(1, 8)
				var kw: Array = []
				var pick := String(KW_POOL[_rng.randi() % KW_POOL.size()])
				if not pick.is_empty():
					kw.append(pick)
				var card = _put(combat, is_enemy, row, lane, atk, hp, kw)
				if card == null:
					continue
				# READINESS IS PART OF THE FIXTURE, not a detail. The muster
				# delay is the rule the old scorer got wrong, so roughly a third
				# of the bodies are left mustering and the sim has to agree about
				# which ones may swing.
				var ready: bool = _rng.randf() > 0.33
				card.state.ready_to_swing = ready
				desc.append("%s%s%d %d/%d%s%s" % [
					"E" if is_enemy else "P",
					"f" if row == combat.ROW_FRONT else "b", lane, atk, hp,
					("" if kw.is_empty() else " " + String(kw[0])),
					("" if ready else " (mustering)")])
	return " | ".join(desc)


func _clear_board(combat) -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null


## Rides `summon_token`, the engine's own token primitive — deliberately not
## `_place_enemy_card` / `_play_creature`, which roll real card data. These
## bodies must carry NO card text, so that what is compared is the clash and not
## a trigger the sim never promised to resolve.
func _put(combat, is_enemy: bool, row: int, lane: int, atk: int, hp: int,
		kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.has_attacked_this_turn = false
	return card


## THE REAL CLASH, AND ONLY THE CLASH.
##
## `_do_combat` would be the obvious thing to call and it cannot be used: in
## headless the scene drives its own turn loop, so awaiting that coroutine let
## `_post_combat_sequence` → `_enemy_place_creatures` land bodies in the middle
## of a fixture. The diff then reported creatures the model had "lost" that it
## was never given — two games interleaved, and every number meaningless.
##
## So this drives the engine's own clash PRIMITIVES, in `_do_combat`'s order:
## the whole front row's Swift for both sides, then the whole back row's, then
## the lane passes front-then-back, with `defer_deaths` held exactly as the
## engine holds it. It is the same pattern `_probe_overkill` uses and for the
## same reason. **If `_do_combat` ever reorders its clash, this must follow** —
## the diff would otherwise blame the model for the probe's stale copy.
func _real_clash(combat) -> void:
	var enemy_front_empty: Array[bool] = []
	var player_front_empty: Array[bool] = []
	for i in range(combat.LANES_PER_ROW):
		player_front_empty.append(combat._row_array(false, combat.ROW_FRONT)[i] == null)
		enemy_front_empty.append(combat._row_array(true, combat.ROW_FRONT)[i] == null)

	Card2D.defer_deaths = true
	for lane in range(combat.LANES_PER_ROW):
		await combat._resolve_swift_attack(lane, combat.ROW_FRONT, false)
		await combat._resolve_swift_attack(lane, combat.ROW_FRONT, true)
	for lane in range(combat.LANES_PER_ROW):
		await combat._resolve_swift_attack(lane, combat.ROW_BACK, false)
		await combat._resolve_swift_attack(lane, combat.ROW_BACK, true)
	Card2D.defer_deaths = false

	# SWIFT_HOLDS_THE_LANE: a body slain in the pre-phase is barred from swinging
	# and held standing through the clash rather than swept now.
	var swift_slain := false
	if combat.SWIFT_HOLDS_THE_LANE:
		for c in combat._all_creatures_both_sides():
			if c != null and is_instance_valid(c) and c.current_hp <= 0:
				c.has_attacked_this_turn = true
				swift_slain = true
	Card2D.defer_deaths = true
	for lane in range(combat.LANES_PER_ROW):
		await combat._clash_lane_pass(lane, combat.ROW_FRONT, enemy_front_empty,
			player_front_empty)
		await combat._clash_lane_pass(lane, combat.ROW_BACK, enemy_front_empty,
			player_front_empty)
	Card2D.defer_deaths = false
	# Sweep by hand rather than through `_cleanup_dead_paced`: that runs the death
	# ceremony (on-death dispatch, the mass-grave beat, the ledger), which is the
	# round ladder's business and not the clash arithmetic under test.
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				var n = arr[i]
				if n != null and is_instance_valid(n) and int(n.current_hp) <= 0:
					n.queue_free()
					arr[i] = null


func _dump_real(combat) -> String:
	var out: PackedStringArray = PackedStringArray()
	for side in 2:
		var is_enemy: bool = side == BoardSim.SIDE_ENEMY
		for row in 2:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				var n = arr[lane]
				if n == null or not is_instance_valid(n):
					continue
				out.append("%s%s%d=%d/%d%s" % ["E" if is_enemy else "P",
					"f" if row == 0 else "b", lane,
					int(n.effective_atk()), int(n.current_hp),
					"" if n.can_attack() else "*"])
	return " ".join(out)


func _dump_sim(snap: BoardSim.SimCtx) -> String:
	var out: PackedStringArray = PackedStringArray()
	for side in 2:
		for row in 2:
			for lane in BoardSim.LANES:
				var b: BoardSim.SimBody = snap.at(side, row, lane)
				if b == null:
					continue
				out.append("%s%s%d=%d/%d" % ["E" if side == 1 else "P",
					"f" if row == 0 else "b", lane, b.atk, b.current_hp])
	return " ".join(out)


## Slot-by-slot comparison of the real board against the simulated one.
func _diff(combat, snap: BoardSim.SimCtx) -> Dictionary:
	var slots := 0
	var wrong := 0
	var why: PackedStringArray = PackedStringArray()
	for side in 2:
		var is_enemy: bool = side == BoardSim.SIDE_ENEMY
		for row in 2:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				slots += 1
				var live = arr[lane]
				var live_alive: bool = live != null and is_instance_valid(live) \
					and int(live.current_hp) > 0
				var sim: BoardSim.SimBody = snap.at(side, row, lane)
				var sim_alive: bool = sim != null and sim.current_hp > 0
				if live_alive != sim_alive:
					wrong += 1
					if why.size() < 3:
						why.append("%s%s%d: real=%s sim=%s" % [
							"E" if is_enemy else "P",
							"f" if row == 0 else "b", lane,
							"alive" if live_alive else "dead",
							"alive" if sim_alive else "dead"])
					continue
				if live_alive and int(live.current_hp) != sim.current_hp:
					wrong += 1
					if why.size() < 3:
						why.append("%s%s%d: real hp=%d sim hp=%d" % [
							"E" if is_enemy else "P",
							"f" if row == 0 else "b", lane,
							int(live.current_hp), sim.current_hp])
	var face_err: int = absi(int(combat.enemy_hp) - snap.enemy_hp) \
		+ absi(int(combat.player_hp) - snap.player_hp)
	if face_err > 0 and why.size() < 4:
		why.append("face: real %d/%d sim %d/%d" % [int(combat.player_hp),
			int(combat.enemy_hp), snap.player_hp, snap.enemy_hp])
	return {"slots": slots, "wrong": wrong, "face_err": face_err,
		"why": " ; ".join(why)}
