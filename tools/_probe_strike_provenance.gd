extends Node
## _probe_strike_provenance.gd — THE MATCHED PAIR (2026-09-13).
##
##   Godot_v4.6.x-stable_win64_console.exe --headless --path "D:\Godot" \
##     res://tools/_probe_strike_provenance.tscn
##
## WHY IT EXISTS. `_flash_strike_provenance` names the CAUSE of a blow that
## disagrees with its printed card: the relic chips lending ATK pulse in the
## rail during the lunge's wind-up, so opaque arithmetic becomes visible
## causality instead of a number the card appears to contradict.
##
## It reads its attribution from `_relic_atk_sources`, which is a hand-written
## MIRROR of `_relic_atk_for`'s six conditions — one returns the amount, the
## other the names. **Nothing in the language keeps them in step.** A condition
## edited in one and forgotten in the other produces the one failure that is
## worse than no feedback at all: a chip lighting up for a relic that
## contributed nothing, which teaches the player a causal link that does not
## exist. It fails silently and looks entirely correct.
##
## So this asserts the pair agrees, per relic, under the condition that relic
## actually needs — and, in both directions:
##   · every relic that CONTRIBUTES is NAMED, and
##   · nothing is named when nothing contributes.
##
## `steady_banner` is the interesting case and is deliberately included: it
## SUBTRACTS, so the sum test must be "non-zero", never "positive". A blow that
## landed lighter than its card promised needs its cause named just as much.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fail := 0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[provenance] WATCHDOG fired")
		get_tree().quit(1))

	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = _find_act1_combat()
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
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
	if not _check(combat.round_number >= 1, "combat reached round 1"):
		_finish()
		return

	# ── BASELINE: no relics, nothing named ───────────────────────────────────
	_set_relics(combat, [])
	_clear_board(combat)
	var solo = _put(combat, false, combat.ROW_FRONT, 1, 3, 9)
	if _check(solo != null, "fixture: a lone 3/9 on our front line"):
		var amt: int = combat._relic_atk_for(solo)
		var src: PackedStringArray = combat._relic_atk_sources(solo)
		_check(amt == 0 and src.is_empty(),
			"no relics: contributes %d, names %d source(s)" % [amt, src.size()])

	# ── EACH RELIC, under the condition it actually needs ─────────────────────
	# The fixture per relic is the point: `glass_cannon` is unconditional, but
	# `phalanx_stone` needs all four front lanes full and `linked_banner` needs
	# two adjacent friendlies, so testing them on a bare board would report a
	# matched pair that had simply never fired.
	for spec in [
		{"id": "glass_cannon", "fill": false, "round1": false},
		{"id": "linked_banner", "fill": true, "round1": false},
		{"id": "phalanx_stone", "fill": true, "round1": false},
		{"id": "steady_banner", "fill": false, "round1": true},
	]:
		var rid: String = String(spec["id"])
		_set_relics(combat, [rid])
		_clear_board(combat)
		combat.round_number = 1 if bool(spec["round1"]) else 3
		var subject
		if bool(spec["fill"]):
			for ln in range(combat.LANES_PER_ROW):
				_put(combat, false, combat.ROW_FRONT, ln, 3, 9)
			subject = combat._row_array(false, combat.ROW_FRONT)[1]
		else:
			subject = _put(combat, false, combat.ROW_FRONT, 1, 3, 9)
		if subject == null:
			_check(false, "%s: fixture failed to seat a body" % rid)
			continue
		var amount: int = combat._relic_atk_for(subject)
		var names: PackedStringArray = combat._relic_atk_sources(subject)
		# THE PAIR, in both directions.
		_check(amount != 0,
			"%s: the fixture actually makes it contribute (got %+d)" % [rid, amount])
		_check(names.has(rid),
			"%s: contributing, and NAMED (names=%s)" % [rid, str(names)])
		_check(names.size() == 1,
			"%s: names exactly its own one source, not others (names=%s)"
				% [rid, str(names)])

	# ── THE OTHER DIRECTION: held but its CONDITION UNMET names nothing ───────
	# This is the half that catches a drifted condition. `phalanx_stone` held
	# with a thin front line contributes nothing; if the mirror forgot the
	# `_front_row_full` test it would still light the chip, teaching a causal
	# link that is not there.
	_set_relics(combat, ["phalanx_stone"])
	_clear_board(combat)
	combat.round_number = 3
	var thin = _put(combat, false, combat.ROW_FRONT, 1, 3, 9)
	if _check(thin != null, "fixture: phalanx_stone held, front line NOT full"):
		var amt2: int = combat._relic_atk_for(thin)
		var src2: PackedStringArray = combat._relic_atk_sources(thin)
		_check(amt2 == 0, "phalanx_stone: contributes nothing on a thin line (%d)" % amt2)
		_check(src2.is_empty(),
			"phalanx_stone: and names nothing (names=%s)" % str(src2))

	# ── CAN THE BEAT EVER OPEN? ──────────────────────────────────────────────
	# Everything above proves the attribution is honest; none of it proves the
	# feature ever RUNS. `_flash_strike_provenance` only speaks when the blow
	# strays from its printed card by STRIKE_PROVENANCE_MIN_DELTA, so if that
	# threshold were unreachable in real play the whole thing would be dead code
	# that passes every test — the content-census lesson (a gate is only correct
	# if it can open), and the exact shape of the inert-material bug found
	# earlier today.
	#
	# This is also the case the feature exists FOR: three relics lending at once
	# is Balatro's "several contributions, shown in turn", not a lone +1.
	_set_relics(combat, ["glass_cannon", "linked_banner", "phalanx_stone"])
	_clear_board(combat)
	combat.round_number = 3
	for ln in range(combat.LANES_PER_ROW):
		_put(combat, false, combat.ROW_FRONT, ln, 3, 9)
	var stacked = combat._row_array(false, combat.ROW_FRONT)[1]
	if _check(stacked != null, "fixture: full front line, three ATK relics held"):
		var printed: int = int(stacked.card_data.get("atk", 0))
		var shown: int = combat._effective_attack(stacked, 1, false)
		var names3: PackedStringArray = combat._relic_atk_sources(stacked)
		print("[provenance] stacked: printed %d, swings %d, sources %s"
			% [printed, shown, str(names3)])
		_check(absi(shown - printed) >= combat.STRIKE_PROVENANCE_MIN_DELTA,
			"the surprise threshold is REACHABLE in real play (delta %d >= %d)"
				% [absi(shown - printed), combat.STRIKE_PROVENANCE_MIN_DELTA])
		_check(names3.size() == 3,
			"all three lenders are named, so the chain has something to show (%d)"
				% names3.size())

	_finish()


func _finish() -> void:
	print("[provenance] %s" % ("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail))
	get_tree().quit(1 if _fail > 0 else 0)


## Relics live on RunState, but `_has_relic` reads a CACHE rebuilt at combat
## start — setting the array alone leaves every lookup answering for the old
## loadout, which would make every case below agree for the wrong reason.
func _set_relics(combat, ids: Array) -> void:
	RunState.relics.clear()
	for i in ids:
		RunState.relics.append(String(i))
	combat._relic_set.clear()


func _clear_board(combat) -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var field = combat._row_array(is_enemy, row)
			for ln in range(combat.LANES_PER_ROW):
				var c = field[ln]
				if c != null and is_instance_valid(c):
					c.queue_free()
				field[ln] = null


func _put(combat, is_enemy: bool, row: int, lane: int, atk: int, hp: int):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", [])
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


func _find_act1_combat() -> String:
	var ids: Array = EncounterDB.get_ids_for(1, "combat")
	return String(ids[0]) if not ids.is_empty() else ""


func _check(ok: bool, what: String) -> bool:
	if not ok:
		_fail += 1
	print("[provenance] %s  %s" % ["PASS" if ok else "FAIL", what])
	return ok
