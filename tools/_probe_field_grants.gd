extends Node
## FIELD-GRANT PROVENANCE + THE DEFECTION GUARD (2026-07-29)
##
## Why this exists: a guard was added to stop the player's Free Company Captain
## looting a keyword that an ENCOUNTER PASSIVE had lent an enemy for the fight.
## It compiled, every gate stayed green, and it was completely INERT — it checked
## only `_has_encounter_passive_keyword`, which matches on `_encounter_passive`
## and has arms for the six *conditional* grants only, so `formation_lockstep`
## and `iron_warden_siege` fell through to `return false`. (`sentinel_stone` was
## a third until 2026-09-16, when its blanket Armored grant was removed — this
## probe never used it as a fixture, so nothing here changed.)
##
## So this probe does not test that the guard COMPILES. It tests that it FIRES,
## and — just as importantly — that it does NOT fire on a keyword the victim
## printed on its own card. A guard that blanket-blocks would be the same bug
## wearing the opposite sign.
##
## It also pins the contract the obvious "fix" would have broken: the field grant
## must still write into `card_data.keywords`, because `Card2D.has_keyword` is the
## ONLY reader of Armored for damage, the forecast and the overkill arithmetic.
## Moving the write to a mirror would silently delete Armored from three boss
## phases while looking like a presentation change. Assertion 1 is that tripwire.
##
## `_probe_fighttrace` CANNOT cover this: `formation_lockstep` and
## `iron_warden_siege` both sit on `threshold: 0` FINAL boss phases the trace bot
## never reaches (it stalls around 18-23 HP against iron_warden across four
## heroes), so a before/after trace there is vacuously identical. Staging the
## dispatcher directly is the only honest way to reach them.
##
## Run: Godot --headless --path "D:\Godot" res://tools/_probe_field_grants.tscn
## (must run as a SCENE so the autoloads resolve.)

const COMBAT_SCENE := "res://scenes/combat.tscn"

var combat: Node = null
var _pass := 0
var _fail := 0
var _failed: Array[String] = []


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_failed.append(label)
		print("  FAIL  %s%s" % [label, ("   [%s]" % detail) if detail != "" else ""])


func _ready() -> void:
	print("[field-grants] start")
	await _boot_combat()
	if combat == null:
		print("[field-grants] FATAL: combat never booted")
		get_tree().quit(1)
		return
	await _test_iron_warden_siege()
	await _test_lockstep()
	print("[field-grants] ============ SUMMARY ============")
	print("[field-grants] passed : %d" % _pass)
	print("[field-grants] FAILED : %d %s" % [_fail, str(_failed)])
	print("[field-grants] %s" % ("ALL PASS" if _fail == 0 else "FAILURES ABOVE"))
	get_tree().quit(1 if _fail > 0 else 0)


func _boot_combat() -> void:
	# HAND THE FRAME BACK BEFORE ATTACHING (2026-09-19). This ran straight out of
	# `_ready`, while the root is still setting up ITS children — so
	# `root.add_child(combat)` failed outright ("Parent node is busy setting up
	# children"), Combat never entered the tree, and every `get_tree()` inside it
	# returned null. The probe then reported **ALL PASS on 18 checks** while
	# Combat threw from `_play_landing_pop` and `_check_game_over`, because a
	# GDScript error aborts its function silently and changes no exit code.
	# A gate that cannot boot its subject but still prints PASS is the fake-green
	# class — worse than a red one, because it reads as coverage.
	await get_tree().process_frame
	var packed: PackedScene = load(COMBAT_SCENE)
	combat = packed.instantiate()
	get_tree().root.add_child(combat)
	# Card2D resolves its VFX host through `current_scene`; without this every
	# damage number and keyword chip silently no-ops (the trap that left 24 shot
	# harnesses blind). Harmless here, but it keeps the staged board honest.
	get_tree().current_scene = combat
	# Gate on round_number, NOT on `phase == PLAYER_TURN` — PLAYER_TURN is enum 0
	# and is therefore the default before anything has happened.
	var guard := 0
	while guard < 900 and int(combat.round_number) < 1:
		await get_tree().process_frame
		guard += 1


## Clear both boards so each fixture starts from a known state.
##
## Defensive on purpose: this probe stages into a LIVE combat scene that is still
## running its own turn logic, so a row array can be shorter than LANES_PER_ROW at
## the moment we look, and a body we are holding can be freed underneath us
## between frames. Guarding here rather than trusting the board is what stops the
## probe from dying halfway and silently skipping its own later assertions — which
## is exactly the failure mode this whole file exists to catch.
func _wipe_board() -> void:
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			if arr == null:
				continue
			for lane in range(mini(combat.LANES_PER_ROW, arr.size())):
				var c = arr[lane]
				if c != null and is_instance_valid(c):
					arr[lane] = null
					c.queue_free()
	await get_tree().process_frame


## Seat an ENEMY body through the real placement path — `_defection_steal_target`
## gates on `defender.is_opponent`, so a hand-built node would not exercise it.
func _seat_enemy(nm: String, atk: int, hp: int, kw: Array, lane: int,
		row: int = -1) -> Control:
	var data := {
		"id": "probe_%s" % nm, "name": nm, "type": "creature",
		"cost": 0, "atk": atk, "hp": hp, "rarity": "enemy",
		"keywords": kw.duplicate(), "desc": "",
	}
	var use_row: int = combat.ROW_FRONT if row < 0 else row
	combat._place_enemy_card(data, lane, use_row)
	await get_tree().process_frame
	var arr = combat._row_array(true, use_row)
	if arr == null or lane >= arr.size():
		return null
	return arr[lane]


## A player Stray carrying the Captain's `defection` passive, with NO keywords of
## its own so every stealable keyword is a legal target for it.
func _make_captain() -> Control:
	var Card2D := load("res://scripts/Card2D.gd")
	var cap = Card2D.new()
	cap.card_data = {
		"id": "probe_captain", "name": "Free Company Captain", "type": "creature",
		"cost": 3, "atk": 3, "hp": 3, "rarity": "rare", "ctype": "stray",
		"keywords": [], "passive": "defection", "desc": "",
	}
	cap.is_opponent = false
	return cap


func _lent(card: Control) -> Array:
	return card.card_data.get("field_granted_keywords", [])


func _test_iron_warden_siege() -> void:
	print("[field-grants] -- iron_warden_siege (end of round, whole line)")
	await _wipe_board()
	combat._encounter_passive = "iron_warden_siege"
	# One body that PRINTS Armored, one bare. The distinction is the whole test.
	var printed := await _seat_enemy("Printed", 2, 6, ["armored"], 0)
	var bare := await _seat_enemy("Bare", 2, 6, [], 1)
	if printed == null or bare == null:
		_check("fixture seated", false, "placement returned null")
		return
	_check("fixture: one printed-Armored body, one bare", true)

	EncounterEffects.dispatch_passive_end_of_round(combat)
	await get_tree().process_frame

	# 1. RULES UNCHANGED — the tripwire for the "move it to a mirror" nerf.
	_check("the lent body really is Armored (keywords write preserved)",
		bare.has_keyword("armored"))

	# IDEMPOTENCE FIRST. The grant pass runs every round, so a re-grant must not
	# duplicate either the keyword or the receipt. Checked BEFORE the damage test
	# below, because that test is what can destroy the body and leave these two
	# assertions silently unreached.
	EncounterEffects.dispatch_passive_end_of_round(combat)
	await get_tree().process_frame
	if is_instance_valid(bare):
		var kw_n: int = (bare.card_data.keywords as Array).count("armored")
		var lent_n: int = _lent(bare).count("armored")
		_check("a second dispatch does not duplicate the keyword",
			kw_n == 1, "count=%d" % kw_n)
		_check("...nor the receipt", lent_n == 1, "count=%d" % lent_n)
	else:
		_check("body survived to the idempotence check", false, "freed early")

	var hp_before: int = int(bare.current_hp)
	bare.take_damage(3)
	_check("...and Armored actually reduces damage (3 dealt -> 2 lost)",
		hp_before - int(bare.current_hp) == 2,
		"lost %d" % (hp_before - int(bare.current_hp)))

	# 2. THE RECEIPT DISCRIMINATES.
	_check("the LENT body carries a field-grant receipt",
		_lent(bare).has("armored"), str(_lent(bare)))
	_check("the PRINTED body carries NO receipt (it owns its keyword)",
		not _lent(printed).has("armored"), str(_lent(printed)))

	# 3. THE LOOKUP ANSWERS from the receipt.
	_check("_has_encounter_passive_keyword true for the lent body",
		combat._has_encounter_passive_keyword(bare, "armored"))
	_check("...and FALSE for the printed body",
		not combat._has_encounter_passive_keyword(printed, "armored"))

	# 4. THE PAYOFF — does the guard actually fire?
	var cap := _make_captain()
	_check("Defection REFUSES to loot a keyword the fight lent",
		String(combat._defection_steal_target(cap, bare)) == "",
		"got '%s'" % String(combat._defection_steal_target(cap, bare)))
	_check("...but still loots a keyword the victim PRINTS",
		String(combat._defection_steal_target(cap, printed)) == "armored",
		"got '%s'" % String(combat._defection_steal_target(cap, printed)))
	cap.free()


func _test_lockstep() -> void:
	print("[field-grants] -- formation_lockstep (front row, from round 2)")
	await _wipe_board()
	combat._encounter_passive = "formation_lockstep"
	combat.round_number = 2   # the arm is gated on round >= 2
	var printed := await _seat_enemy("PrintedLS", 2, 6, ["armored"], 0)
	var bare := await _seat_enemy("BareLS", 2, 6, [], 1)
	if printed == null or bare == null:
		_check("lockstep fixture seated", false, "placement returned null")
		return
	_check("fixture: adjacent front-row bodies, one printed one bare", true)

	EncounterEffects.formation_drill_tick(combat, true)
	await get_tree().process_frame

	_check("lockstep lends Armored (keywords write preserved)",
		bare.has_keyword("armored"))
	var hp_before: int = int(bare.current_hp)
	bare.take_damage(3)
	_check("...and it reduces damage (3 dealt -> 2 lost)",
		hp_before - int(bare.current_hp) == 2,
		"lost %d" % (hp_before - int(bare.current_hp)))
	_check("lent body carries the receipt", _lent(bare).has("armored"),
		str(_lent(bare)))
	_check("printed body carries no receipt",
		not _lent(printed).has("armored"), str(_lent(printed)))

	var cap := _make_captain()
	_check("Defection refuses the lent keyword under lockstep",
		String(combat._defection_steal_target(cap, bare)) == "")
	_check("...and still takes the printed one",
		String(combat._defection_steal_target(cap, printed)) == "armored")
	cap.free()
