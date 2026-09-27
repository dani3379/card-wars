extends Node
## _probe_turn_order.gd — WHO ACTUALLY MOVES FIRST? (2026-09-19)
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_turn_order.tscn
##
## WHY: `docs/COMBAT_SHAPE_PASS_20260727.md` §3.4 is headlined "the player already
## goes second in every fight, uncompensated", and CLAUDE.md repeats that summary
## and calls the fix "one `if`" that is SPECCED, NOT BUILT. But `Combat.gd:1628`
## carries a TAKE THE FIELD note dated the SAME DAY saying the opposite — that
## `_opening_muster_pending` is deliberately left standing so the hold forms up at
## the END of round 1, i.e. the player moves first.
##
## Both cannot be true, and the question is worth settling by MEASUREMENT rather
## than by trusting whichever document was read last: a session that believes the
## stale version would "fix" a thing already fixed, and the obvious way to do that
## is to restore the pre-2026-07-27 behaviour the measured trace rejected.
##
## THE ORACLE IS DELIBERATELY CRUDE, because the claim is crude: how many enemy
## bodies are standing at the instant the player is first allowed to act? Going
## second means facing a formed line; going first means an empty field.
##
## Readiness is polled on `round_number` and a SETTLED hand, never on `phase`:
## Phase.PLAYER_TURN is enum 0 and therefore also the uninitialised default, and
## `_start_round` staggers the deal on timers — both are documented traps that
## make a driver measure a half-built scene.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0


func _ready() -> void:
	var rows: Array = []
	for eid in _sample_encounters():
		var n := await _bodies_at_first_turn(eid)
		rows.append([eid, n])
	print("[turnorder] enemy bodies standing when the player may first act:")
	var total := 0
	for r in rows:
		print("[turnorder]   %-26s %d" % [r[0], r[1]])
		total += int(r[1])
	var mean := float(total) / maxf(1.0, float(rows.size()))
	print("[turnorder] mean = %.2f over %d ordinary combats" % [mean, rows.size()])
	print("")
	if mean <= 0.01:
		print("[turnorder] VERDICT: the PLAYER MOVES FIRST — the field is empty on")
		print("[turnorder]   round 1 and the hold forms up at the end of it.")
		print("[turnorder]   COMBAT_SHAPE_PASS §3.4 and the CLAUDE.md line that")
		print("[turnorder]   repeats it ('already goes second, uncompensated') are")
		print("[turnorder]   STALE — TAKE THE FIELD (Combat.gd:1628) built it.")
	else:
		print("[turnorder] VERDICT: the player faces %.2f bodies before acting —" % mean)
		print("[turnorder]   the doc's 'goes second' reading still holds.")
		_fails += 1
	print("[turnorder] %s" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0)


## A handful of ORDINARY act-1 combats. Generals and keeps are excluded on
## purpose: those run THE INITIATIVE, where going first or second is an explicit
## player choice and the answer is therefore whatever was chosen.
func _sample_encounters() -> Array:
	var out: Array = []
	for eid in EncounterDB.ENCOUNTERS.keys():
		var e: Dictionary = EncounterDB.ENCOUNTERS[eid]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			out.append(eid)
		if out.size() >= 6:
			break
	out.sort()
	return out


func _bodies_at_first_turn(eid: String) -> int:
	RunState.start_new_run("raider", 0, 4242)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = eid
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
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
	# Let the hand SETTLE — the deal is staggered, and a count taken mid-deal is a
	# measurement of the harness. Poll until the size holds.
	var settled := -1
	for _i in 20:
		var now: int = combat._hand.size()
		if now > 0 and now == settled:
			break
		settled = now
		await get_tree().create_timer(0.05).timeout

	var n := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(true, row):
			if c != null and is_instance_valid(c):
				n += 1
	combat.queue_free()
	await get_tree().process_frame
	return n
