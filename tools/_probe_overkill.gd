extends Node
## _probe_overkill.gd — the blocker-economy rules (2026-07-28).
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_overkill.tscn
##
## Two rules land on one funnel (Combat._apply_piercing_overflow), and they are
## easy to collapse into each other by accident:
##
##   OVERKILL — universal, no keyword. A killing blow carries its excess into the
##              body standing BEHIND the victim, then STOPS. This is what makes
##              HP a currency: before it, a body absorbed one whole attack
##              regardless of size, so a 1-cost 1/2 and a 2-cost 3/4 both denied
##              exactly 3.0 damage per Command.
##   PIERCING — the keyword (plus Bodkin Points / inspire_piercing). Same spill,
##              but it reads on through an empty column into the enemy. If
##              overkill ever leaks facewards, Piercing prints blank — that is
##              the regression this file exists to catch.
##
## Third rule under test: the FACE ARM reads LIVE occupancy, not the pre-clash
## snapshot. A blocker that dies earlier in the same clash used to go on denying
## the whole column — a second attacker found a corpse it could not hit and an
## arm it could not reach, and dealt nothing at all.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0


func _ready() -> void:
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
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum 0, which is
	# also the uninitialised default (documented trap).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check(combat.round_number >= 1, "combat reached round 1")

	# ── OVERKILL spills into the body behind ─────────────────────────────────
	_clear_board(combat)
	var front = _put(combat, true, combat.ROW_FRONT, 0, 1, 2)    # enemy 1/2
	var back = _put(combat, true, combat.ROW_BACK, 0, 1, 9)      # enemy 1/9 behind
	var hitter = _put(combat, false, combat.ROW_FRONT, 0, 7, 9)  # our 7/9
	if _check(front != null and back != null and hitter != null, "fixture: 7/9 vs 1/2 screening a 1/9"):
		var behind_before: int = int(back.current_hp)
		var face_before: int = int(combat.enemy_hp)
		await combat._creature_attacks_creature(hitter, front, 0, false)
		_check(front.current_hp <= 0, "the screen died")
		_check(back.current_hp == behind_before - 5,
			"5 excess carried into the body behind (%d -> %d, expected %d)"
				% [behind_before, back.current_hp, behind_before - 5])
		_check(combat.enemy_hp == face_before,
			"...and NOT to the face (overkill stops at the body)")

	# ── OVERKILL with an empty column STOPS — it does not reach the face ─────
	_clear_board(combat)
	var lone = _put(combat, true, combat.ROW_FRONT, 1, 1, 2)
	var hitter2 = _put(combat, false, combat.ROW_FRONT, 1, 7, 9)
	if _check(lone != null and hitter2 != null, "fixture: 7/9 vs a lone 1/2, nothing behind"):
		var face_before2: int = int(combat.enemy_hp)
		await combat._creature_attacks_creature(hitter2, lone, 1, false)
		_check(lone.current_hp <= 0, "the lone blocker died")
		_check(combat.enemy_hp == face_before2,
			"plain overkill did NOT reach the face (%d -> %d)"
				% [face_before2, combat.enemy_hp])

	# ── PIERCING is what buys the face ───────────────────────────────────────
	_clear_board(combat)
	var lone2 = _put(combat, true, combat.ROW_FRONT, 2, 1, 2)
	var pierce = _put(combat, false, combat.ROW_FRONT, 2, 7, 9, ["piercing"])
	if _check(lone2 != null and pierce != null, "fixture: a 7/9 PIERCING vs a lone 1/2"):
		_check(combat._strike_reaches_face(pierce, false),
			"_strike_reaches_face is true for a printed Piercing body")
		var face_before3: int = int(combat.enemy_hp)
		await combat._creature_attacks_creature(pierce, lone2, 2, false)
		_check(combat.enemy_hp == face_before3 - 5,
			"Piercing carried the 5 excess to the face (%d -> %d, expected %d)"
				% [face_before3, combat.enemy_hp, face_before3 - 5])

	# ── The keyword still reads as a premium over plain overkill ─────────────
	_clear_board(combat)
	var plain_body = _put(combat, false, combat.ROW_FRONT, 3, 2, 2)
	if _check(plain_body != null, "fixture: a plain body"):
		_check(not combat._strike_reaches_face(plain_body, false),
			"_strike_reaches_face is FALSE for a body with no Piercing (else the keyword prints blank)")

	# ── The face arm reads LIVE occupancy, not the pre-clash snapshot ────────
	# One enemy body in a column, two of ours stacked against it. The first kills
	# it; the second must reach the face rather than being silently blanked.
	_clear_board(combat)
	var screen = _put(combat, true, combat.ROW_FRONT, 0, 1, 3)
	var killer = _put(combat, false, combat.ROW_FRONT, 0, 3, 5)
	var second = _put(combat, false, combat.ROW_BACK, 0, 4, 5)
	if _check(screen != null and killer != null and second != null,
			"fixture: two of ours stacked on one enemy 1/3"):
		for c in [killer, second]:
			c.state.ready_to_swing = true
			c.has_attacked_this_turn = false
		var face_before4: int = int(combat.enemy_hp)
		Card2D.defer_deaths = true
		await combat._resolve_column_attack(0, combat.ROW_FRONT, false, _snapshot(combat, true))
		await combat._resolve_column_attack(0, combat.ROW_BACK, false, _snapshot(combat, true))
		Card2D.defer_deaths = false
		_check(screen.current_hp <= 0, "the screen fell to the first attacker")
		_check(combat.enemy_hp == face_before4 - 4,
			"the SECOND attacker reached the face through the emptied column (%d -> %d, expected %d)"
				% [face_before4, combat.enemy_hp, face_before4 - 4])

	print("[overkill] %s" % ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _find_act1_combat() -> String:
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) == 1 and String(e.get("type", "")) == "combat":
			return String(id)
	return ""


## Wipe both boards so each block owns a clean column. Bypasses _die() on
## purpose — this is fixture teardown, not a game event, and firing on_death
## chains here would contaminate the next block's face total.
func _clear_board(combat) -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for i in range(combat.LANES_PER_ROW):
				if arr[i] != null and is_instance_valid(arr[i]):
					arr[i].queue_free()
				arr[i] = null


## Drop a synthetic body onto a slot with exact stats. Rides summon_token, the
## engine's own token primitive — deliberately not _place_enemy_card /
## _play_creature, which roll real card data, while these assertions are
## arithmetic on specific numbers.
func _put(combat, is_enemy: bool, row: int, lane: int, atk: int, hp: int,
		kw: Array = []):
	combat.summon_token(atk, hp, lane, is_enemy, row, {}, "Probe Body", kw)
	var card = combat._row_array(is_enemy, row)[lane]
	if card == null:
		return null
	# Tokens arrive mustering (ready_to_swing defaults false). Every block here
	# is testing the strike itself, so stand them up by hand.
	card.state.ready_to_swing = true
	card.has_attacked_this_turn = false
	return card


func _snapshot(combat, of_enemy: bool) -> Array[bool]:
	var out: Array[bool] = []
	for i in range(combat.LANES_PER_ROW):
		out.append(combat._row_array(of_enemy, combat.ROW_FRONT)[i] == null)
	return out


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
