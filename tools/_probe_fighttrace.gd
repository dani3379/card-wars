extends SceneTree
## Round-by-round trace of ONE fight, to answer WHY a run dies rather than
## guessing at levers. Four tuning/skill interventions in a row moved the run
## simulator by ~0.1 fights, which means the loss is structural and needs to be
## watched, not modelled.
##
##   Godot.exe --headless --path . --script res://tools/_probe_fighttrace.gd -- --enc=orc_warband --hero=raider

const TICK := 0.1
const TURN_WAIT_TICKS := 80
const MAX_ROUNDS := 25
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp",
	"war_chant", "gambit", "censer_light", "recycle"]

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
var combat: Node
var _started := false
var _done := false
var _enc := "orc_warband"
var _hero := "raider"


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--enc="):
			_enc = s.substr(6)
		elif s.begins_with("--hero="):
			_hero = s.substr(7)
	RS = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()

	var enc: Dictionary = EDB.get_encounter(_enc)
	RS.start_new_run(_hero, 0, 4242)
	RS.current_encounter_id = _enc
	RS.current_setpiece_id = ""
	RS.current_mutator_id = ""
	RS.current_node_type = String(enc.get("type", "combat"))
	RS.current_act_idx = clampi(int(enc.get("act", 1)), 1, 3) - 1

	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_turn():
		print("FATAL: never reached a player turn")
		_done = true
		quit(1)
		return

	print("=== %s vs %s (act %d %s) ===" % [
		_hero, String(enc.get("name", _enc)),
		int(enc.get("act", 1)), String(enc.get("type", "combat"))])
	print("rnd | you | foe | your board (atk/hp)      | foe board (atk/hp)        | hand cmd")
	var last_php: int = int(combat.player_hp)
	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER \
			and rounds < MAX_ROUNDS:
		# BEFORE _line, not after: the trace prints the hand size, so sampling
		# ahead of the settle reports round 1 as a one-card hand — the very
		# artifact this call exists to remove.
		await _settle_hand()
		if not is_instance_valid(combat):
			break
		_line(rounds + 1, last_php)
		last_php = int(combat.player_hp)
		await _auto_play_turn()
		if not is_instance_valid(combat):
			break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_turn():
			break
	if is_instance_valid(combat):
		var won: bool = int(combat.enemy_hp) <= 0
		print("")
		print("RESULT after %d rounds: %s   you %d   foe %d" % [
			rounds, "WIN" if won else "LOSS",
			maxi(0, int(combat.player_hp)), maxi(0, int(combat.enemy_hp))])
	_done = true
	quit(0)


func _line(rnd: int, prev_php: int) -> void:
	var mine := _board_str(false)
	var theirs := _board_str(true)
	var dmg: int = prev_php - int(combat.player_hp)
	var dtag := ""
	if dmg > 0:
		dtag = " (-%d)" % dmg
	print("%3d | %3d%-5s| %3d | %-24s | %-25s | %d/%d" % [
		rnd, int(combat.player_hp), dtag, int(combat.enemy_hp),
		mine, theirs, combat._hand.size(), int(combat.player_mana)])


func _board_str(is_enemy: bool) -> String:
	var parts: Array[String] = []
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(is_enemy, row)
		for lane in range(combat.LANES_PER_ROW):
			var c = arr[lane]
			if c != null and is_instance_valid(c) and c.current_hp > 0:
				parts.append("%d/%d" % [int(c.effective_atk()), int(c.current_hp)])
	if parts.is_empty():
		return "(empty)"
	return " ".join(parts)


func _wait_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		if combat.phase == combat.Phase.PLAYER_TURN and int(combat.round_number) >= 1:
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


## Poll until the hand has finished ARRIVING, not just until input is accepted.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. A driver that starts there is playing a hand the
## game has not finished dealing it: on round 1 that is ONE card of five, and at
## Command 1 a single 2-drop means the whole turn plays nothing.
##
## Rounds 2+ hide it, because the hand is PERSISTENT and carries unplayed stock
## forward — so the fault is worst exactly where round-1 measurements live. It
## cost `_probe_deploy_curve` a published number before it was found; see
## CLAUDE.md's settle-until-stable note.
##
## Stability polling, NOT a computed deal window: draw_count is the ramp plus
## four relics plus two mutators, and restating that arithmetic in a probe is
## the duplicate-rule pathology. Bounded, because an unbounded `while await`
## spins to the harness timeout and reports NOTHING at all.
func _settle_hand() -> void:
	const SETTLE_TICK := 0.03    # poll interval
	const STABLE_TICKS := 5      # 0.15s unchanged, a 1.9x margin on the 0.08s gap
	const SETTLE_BUDGET := 40    # ~1.2s ceiling
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _auto_play_turn() -> void:
	# THE HAND ARRIVES ON TIMERS. _start_round draws one card immediately and
	# staggers the rest on 0.08s timers, so `phase == PLAYER_TURN` is true while
	# the hand is still being dealt. A bot that acts at once plays a ONE-CARD
	# hand every turn — which is what every measurement in this session was
	# actually testing, and why four unrelated levers all moved nothing.
	# Wait for the hand to stop growing before deciding anything.
	var stable := 0
	var last_n: int = -1
	while stable < 3:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last_n:
			stable += 1
		else:
			stable = 0
			last_n = n
		await create_timer(0.05).timeout
	for _pass in 4:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var played_any := false
		for card in combat._hand.duplicate():
			if not is_instance_valid(card) or not (card in combat._hand):
				continue
			var cd: Dictionary = card.card_data
			if String(cd.get("id", "")) in MODAL_BLOCKLIST:
				continue
			var cost: int = int(cd.get("cost", 0))
			if int(combat.player_mana) < cost:
				continue
			if String(cd.get("type", "")) == "creature":
				var slot = _slot()
				if slot == null:
					continue
				card.global_position = slot.global_position + slot.size * 0.5 \
					- card.size * 0.5
				combat._on_card_played(card)
				played_any = true
				await create_timer(0.03).timeout
			elif String(cd.get("targeting", "none")) == "none":
				combat._on_card_played(card)
				played_any = true
				await create_timer(0.03).timeout
		if not played_any:
			return


func _slot():
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_FRONT)[lane] == null:
			return combat._slot_array(false, combat.ROW_FRONT)[lane]
	for lane in range(combat.LANES_PER_ROW):
		if combat._row_array(false, combat.ROW_BACK)[lane] == null:
			return combat._slot_array(false, combat.ROW_BACK)[lane]
	return null
