extends SceneTree
## THE OLD KING'S BODY — behaviour gate (2026-07-20).
##
## The encounter makes three promises. Each is enforced at a DIFFERENT chokepoint,
## so each needs its own check or a future refactor breaks one silently:
##   1. The foe takes NO face damage        (Combat.damage_enemy_hero early-return)
##   2. The Body is untouched by EFFECTS    (Card2D.take_damage whitelist flag)
##   3. ...but a creature's STRIKE lands    (Card2D.strike_damage_active raised
##                                           only inside _creature_attacks_creature)
##   4. Killing the Body ends the fight     (holds_the_fight in the death dispatch)
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_kings_body.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

var _ran := false
var _pass := 0
var _fail := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("[kings_body] PASS  %s" % label)
	else:
		_fail += 1
		print("[kings_body] FAIL  %s" % label)


func _process(_d: float) -> bool:
	# MUST return false: _run() is a coroutine, so returning true here quits the
	# SceneTree at its first await and the whole behaviour half never runs.
	# _run() calls quit() itself when it is finished.
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _find_body(combat) -> Control:
	for row in [0, 1]:
		for c in combat._row_array(true, row):
			if c != null and is_instance_valid(c) \
					and bool(c.card_data.get("holds_the_fight", false)):
				return c
	return null


func _run() -> void:
	var RS = root.get_node_or_null("/root/RunState")
	if RS == null:
		print("[kings_body] FAIL  RunState autoload missing")
		quit(1); return

	# The encounter must exist and be flagged before we spend a fight setting up.
	var EDB = root.get_node_or_null("/root/EncounterDB")
	var enc: Dictionary = EDB.ENCOUNTERS.get("kings_body", {})
	_ok(not enc.is_empty(), "encounter 'kings_body' exists")
	_ok(String(enc.get("passive_id", "")) == "kings_body", "passive_id wired")
	var deck: Array = enc.get("deck", [])
	var flagged := 0
	for d in deck:
		if bool(d.get("effect_immune", false)) and bool(d.get("holds_the_fight", false)):
			flagged += 1
	_ok(flagged == 1, "exactly ONE body carries effect_immune + holds_the_fight (got %d)" % flagged)

	RS.start_new_run("raider")
	RS.current_node_type = "elite"
	RS.current_encounter_id = "kings_body"
	await process_frame

	var combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	# Let the intro/deal settle so the opening board is seated.
	for i in range(140):
		await process_frame

	var body := _find_body(combat)
	if body == null:
		# THE ENEMY DEPLOYS AT THE ENEMY-PLACEMENT BEAT, NOT AT ROUND 1 PHASE 0
		# (probe fixed 2026-08-05). The OPENING MUSTER (2026-07-25) took over
		# from `_place_starting_board`, and it is consumed inside the reserve
		# dealer — i.e. after the player's turn ends. Round 1 is a MUSTER round:
		# the player's line goes down during their phase, the hold's answers at
		# the close, and neither swings. At a General the INITIATIVE (2026-07-30)
		# reinforces that: taking the field means the hold ANSWERS what you set
		# down.
		#
		# So an empty enemy board here is correct, and waiting longer will never
		# fix it — this probe waited 540 frames and then ABORTED, skipping the
		# twelve immunity assertions that are its entire point. End the turn
		# once and let the hold muster.
		combat._on_end_turn()
		for i in range(240):
			await process_frame
			body = _find_body(combat)
			if body != null:
				break
	_ok(body != null, "the Body is on the board")
	if body == null:
		print("[kings_body]   enc_id=%s passive=%s deck_left=%d round=%d phase=%d"
			% [combat._encounter_id, combat._encounter_passive,
			   combat._enemy_deck.size(), combat.round_number, combat.phase])
		var seen: Array = []
		for row in [0, 1]:
			for c in combat._row_array(true, row):
				if c != null and is_instance_valid(c):
					seen.append(String(c.card_data.get("name", "?")))
		print("[kings_body]   enemy board: %s" % str(seen))
		var names: Array = []
		for d in combat._enemy_deck:
			names.append(String(d.get("name", "?")))
		print("[kings_body]   deck order: %s" % str(names))
		print("[kings_body] ABORT — no body to test")
		_summary(); return

	_ok(bool(body.state.effect_immune), "Body carries state.effect_immune")

	# 1. FACE DAMAGE IS ZERO.
	var hp_before: int = combat.enemy_hp
	combat.damage_enemy_hero(7)
	_ok(combat.enemy_hp == hp_before,
		"face damage does nothing (%d -> %d)" % [hp_before, combat.enemy_hp])

	# 2. EFFECT DAMAGE BOUNCES — plain take_damage is the path every spell,
	#    battlecry, on-death and potion ultimately uses.
	var bhp: int = body.current_hp
	body.take_damage(9)
	_ok(body.current_hp == bhp, "effect damage bounces (%d -> %d)" % [bhp, body.current_hp])
	# The kill convention (99+) must ALSO bounce, or Offering/rituals delete it.
	body.take_damage(999)
	_ok(body.current_hp == bhp, "kill-convention damage bounces (%d)" % body.current_hp)
	# Thorns/venom path.
	body.take_damage_bypass_armor(9)
	_ok(body.current_hp == bhp, "bypass-armor (Thorns/venom) bounces (%d)" % body.current_hp)

	# 3. STATUS EFFECTS BOUNCE.
	_ok(not combat._apply_stun(body), "stun refuses to stick")
	_ok(not combat._apply_freeze(body), "freeze refuses to stick")
	_ok(not bool(body.state.stunned), "Body is not stunned")
	var push: Dictionary = combat._flank_push(body, 3)
	_ok(not bool(push.get("moved", false)), "push does not move the Body")

	# 4. IT CANNOT BE CHOSEN as a target (the other half of immunity).
	_ok(combat._is_effect_immune(body), "_is_effect_immune reports true")

	# 5. A STRIKE LANDS. This is the whitelist — if this fails the fight is
	#    unwinnable, which is worse than the immunity leaking.
	var Card2DRef = load("res://scripts/Card2D.gd")
	Card2DRef.strike_damage_active = true
	body.take_damage(6)
	Card2DRef.strike_damage_active = false
	_ok(body.current_hp == bhp - 6,
		"a creature STRIKE lands (%d -> %d, expected %d)" % [bhp, body.current_hp, bhp - 6])

	# 6. KILLING IT WINS. Strike it down and confirm the fight ends.
	Card2DRef.strike_damage_active = true
	body.take_damage(body.current_hp)
	Card2DRef.strike_damage_active = false
	if is_instance_valid(body) and body.has_method("try_die"):
		body.try_die()
	for i in range(30):
		await process_frame
	_ok(combat.enemy_hp <= 0 or combat.phase == combat.Phase.GAME_OVER,
		"the Body's death ends the fight (enemy_hp=%d phase=%d)" % [combat.enemy_hp, combat.phase])

	_summary()


func _summary() -> void:
	print("")
	if _fail == 0:
		print("[kings_body] ALL PASS (%d checks)" % _pass)
	else:
		print("[kings_body] %d FAILED, %d passed" % [_fail, _pass])
	quit(0 if _fail == 0 else 1)
