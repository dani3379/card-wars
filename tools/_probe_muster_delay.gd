extends Node
## _probe_muster_delay.gd — the Cross Blitz summoning-sickness rule.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_muster_delay.gd
##
## Asserts the delay is EXACTLY one round, on BOTH sides, and that Swift is the
## documented exception. The failure this is really guarding against is a DOUBLE
## delay on enemy arrivals: the enemy places in the post-combat phase, so a
## sweep placed beside the end-of-turn `has_attacked_this_turn` reset (which runs
## BEFORE _enemy_place_creatures) would leave every enemy body unready through
## the whole following round. The sweep must live at round START.

const COMBAT_SCENE := "res://scenes/combat.tscn"

var _fails := 0


func _ready() -> void:
	RunState.start_new_run("stalwart", 0, 4242)
	# Combat needs the node staged the way visit_node would leave it, or it never
	# reaches the player's turn and never deals a hand.
	# The fixture must reinforce with a NON-Swift body: the reserves block at the
	# bottom asks whether an arrival can swing in the next clash, and Swift is the
	# sanctioned exception to the muster delay, so a Swift-reinforced hold (most
	# of act 1 — goblin_scouts deals a 1/1 Swift Whelp) would filter its own
	# fixture down to nothing and report a hollow pass.
	var enc_id := ""
	for id in EncounterDB.ENCOUNTERS:
		var e: Dictionary = EncounterDB.ENCOUNTERS[id]
		if int(e.get("act", 1)) != 1 or String(e.get("type", "")) != "combat":
			continue
		# ...and it must reinforce UNCONDITIONALLY. The Owed only commit bodies
		# against banked enemy deaths (nothing has died here, so they deal zero),
		# grasswake runs dry after two waves, and lanternhall alternates 1/0 —
		# any of those can hand this block an empty fixture on the wrong round.
		# last_wall trickles exactly one body every round, forever.
		if String(e.get("faction", "")) != "last_wall":
			continue
		var reinf: Dictionary = e.get("reinforcement", {})
		if reinf.is_empty() or "swift" in reinf.get("kw", []):
			continue
		var pool_has_swift := false
		for alt in e.get("reinforcement_pool", []):
			if "swift" in alt.get("kw", []):
				pool_has_swift = true
		if pool_has_swift:
			continue
		enc_id = String(id)
		break
	_check(enc_id != "", "found an act-1 combat fixture (%s)" % enc_id)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = enc_id
	RunState.current_setpiece_id = ""
	RunState.current_mutator_id = ""
	RunState.current_act_idx = 0
	RunState.hero_max_hp = 400
	RunState.hero_hp = 400
	await get_tree().process_frame
	var combat = load(COMBAT_SCENE).instantiate()
	add_child(combat)
	# Poll on round + hand, NOT on phase: Phase.PLAYER_TURN is enum value 0, which
	# is also the uninitialised default, so a phase check passes on frame zero
	# before combat has dealt anything (this exact trap cost a debug cycle).
	var waited := 0
	while waited < 400:
		if is_instance_valid(combat) and combat.round_number >= 1 \
				and not combat._hand.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
		waited += 1

	_check(combat.round_number >= 1, "combat reached round 1")
	_check(not combat._hand.is_empty(), "the opening hand was dealt")

	# Each block re-deals before spawning: _start_round() both sweeps the muster
	# AND refills the hand, so without this the later fixtures come back null and
	# their assertions are skipped silently — which is how this probe first
	# reported ALL PASS while testing a third of what it claimed.

	# ── A fresh body is NOT ready, SHOWS it, and becomes ready in ONE round ───
	var body = _spawn(combat, "", false, 0)
	if _check(body != null, "fixture: a plain (non-Swift) body in hand"):
		_check(not body.state.ready_to_swing, "a body that just arrived is unready")
		_check(not body.can_attack(),
			"an unready body cannot attack in its arrival round")
		# The mark is checked HERE, on the body we already have, rather than on a
		# fourth fixture — the board fills up and the extra spawn had no free lane.
		_check(_status_ids(body).has("mustering"),
			"unready body shows the Mustering mark (got: %s)" % str(_status_ids(body)))
		_check(GameTheme.get_keyword_icon("mustering") != null,
			"the Mustering icon is registered (rail drops null-texture entries)")
		# One sweep = ready. Two must not be needed (the double-delay bug).
		combat._start_round()
		_check(body.state.ready_to_swing, "one round start makes the body ready")
		_check(body.can_attack(), "a mustered body can attack the NEXT round")
		_check(not _status_ids(body).has("mustering"),
			"the Mustering mark clears once the body is ready")

	# ── Swift ignores the delay ───────────────────────────────────────────────
	# Granted Swift (War Cry / the Drummer) rather than a drawn Swift card: the
	# hero deck under test need not contain one, and the granted path is the same
	# ignores_muster_delay() branch a printed keyword takes.
	# Fielded through the enemy dealer, which is deterministic — the player's hand
	# runs out of creatures by this point. The muster rule is side-agnostic, so
	# this exercises the same branch.
	combat._start_round()
	var swift = _spawn(combat, "goblin", true, 1)
	if _check(swift != null, "fixture: a body to grant Swift"):
		_check(not swift.can_attack(), "...unready before Swift is granted")
		swift.state.war_cry_swift = true
		_check(swift.ignores_muster_delay(), "Swift ignores the muster delay")
		_check(swift.can_attack(), "Swift CAN attack the round it arrives")
		_check(not swift.state.ready_to_swing,
			"Swift does not fake the flag — state stays honest")

	# ── The enemy side gets the SAME rule, and only one round of it ───────────
	var foe = _spawn(combat, "goblin", true, 0)
	if _check(foe != null, "fixture: an enemy arrival"):
		_check(not foe.can_attack(), "enemy arrival is unready too")
		combat._start_round()
		_check(foe.can_attack(),
			"enemy arrival is ready after ONE round start (not two)")

	# ── "Cannot attack" must NOT decay into "cannot fight back" ───────────────
	# A mustering body still trades with whatever strikes it, or arriving would
	# mean handing the foe a free kill.
	combat._start_round()
	var green = _spawn(combat, "goblin", true, 2)
	if _check(green != null, "fixture: a mustering defender"):
		_check(not green.can_attack(), "...it cannot initiate")
		_check(combat._defender_is_mustering(green),
			"it is recognised as mustering")
		_check(combat._defender_will_counter(green),
			"a mustering defender STILL counters when struck")

	# ── Swift may break bodies on arrival, but not reach the face ─────────────
	combat._start_round()
	var rush = _spawn(combat, "goblin", true, 3)
	if _check(rush != null, "fixture: a Swift body on its arrival round"):
		rush.state.war_cry_swift = true
		_check(rush.can_attack(), "Swift swings on arrival")
		var face_before: int = int(combat.player_hp)
		await combat._creature_hits_face(rush, 3, true)
		_check(int(combat.player_hp) == face_before,
			"Swift did NOT reach the face on its arrival round (Rush rule)")
		rush.state.ready_to_swing = true
		await combat._creature_hits_face(rush, 3, true)
		_check(int(combat.player_hp) < face_before,
			"...and DOES reach the face once mustered")

	# ── CHARGE: the one keyword that ignores the delay AND reaches the face ───
	combat._start_round()
	var chg = _spawn(combat, "war_boar", true, 1)
	if _check(chg != null, "fixture: a Charge body on its arrival round"):
		_check(chg.has_keyword("charge"), "War Boar carries Charge")
		_check(GameTheme.get_keyword_icon("charge") != null,
			"the Charge device icon is registered (unregistered = silently no device)")
		_check(KeywordEffects.KEYWORDS.has("charge"),
			"Charge is in the glossary (drives gilding + the hover tooltip)")
		_check(not chg.state.ready_to_swing, "...still flagged unready")
		_check(chg.can_attack(), "Charge swings on arrival")
		var f0: int = int(combat.player_hp)
		await combat._creature_hits_face(chg, 1, true)
		_check(int(combat.player_hp) < f0,
			"Charge DOES reach the face on arrival (unlike Swift)")

	# ── The flag survives the snapshot round trip (skirmish replication) ──────
	var snap: Dictionary = CreatureInstance.new().to_snapshot()
	_check(snap.has("ready"), "ready_to_swing is in to_snapshot()")
	var live = CreatureInstance.new()
	live.ready_to_swing = true
	_check(live.to_replication_snapshot().has("ready"),
		"ready_to_swing replicates to the peer")
	var rt = CreatureInstance.new()
	rt.apply_snapshot(live.to_snapshot())
	_check(rt.ready_to_swing, "ready survives the snapshot round trip")
	# Legacy peers/saves carry no "ready" key — must default READY, never
	# unready, or an old save would freeze its whole board for a round.
	var legacy = CreatureInstance.new()
	legacy.apply_snapshot({"hp": 3})
	_check(legacy.ready_to_swing,
		"a snapshot with no 'ready' key defaults to READY (legacy safe)")

	# ── RESERVES PAY THE DELAY TOO — measured in CLASHES SKIPPED ─────────────
	# Everything above this line counts ROUND STARTS, and that is precisely how
	# the enemy came to skip the delay entirely for months: reinforcements are
	# placed in _post_combat_sequence AFTER the clash, and the _start_round()
	# call at the tail of that same function readied them before their first
	# possible clash. One round start, zero clashes sat out — while a played
	# card sits out one. The assertion "ready after ONE round start" passed the
	# whole time because it seats its fixture by hand and never runs the real
	# end-of-round.
	#
	# So this block drives the SHIPPED _post_combat_sequence and asks the only
	# question that matters: on the round after reserves land, can they swing?
	var pre_ids := {}
	for c in combat._all_enemy_creatures():
		if is_instance_valid(c):
			pre_ids[c.get_instance_id()] = true
	var round_before: int = int(combat.round_number)
	await combat._post_combat_sequence()
	var arrivals: Array = []
	for c in combat._all_enemy_creatures():
		# Swift is the sanctioned exception and would mask the result.
		if is_instance_valid(c) and not pre_ids.has(c.get_instance_id()) \
				and not c.has_keyword("swift"):
			arrivals.append(c)
	_check(int(combat.round_number) == round_before + 1,
		"the end-of-round sequence advanced the round")
	if _check(not arrivals.is_empty(),
			"fixture: the hold committed reserves (%d non-Swift)" % arrivals.size()):
		var ready_now := 0
		for c in arrivals:
			if c.can_attack():
				ready_now += 1
		_check(ready_now == 0,
			"reserves CANNOT swing in the clash after they land (%d/%d could)"
				% [ready_now, arrivals.size()])
		combat._start_round()
		var ready_after := 0
		for c in arrivals:
			if is_instance_valid(c) and c.can_attack():
				ready_after += 1
		_check(ready_after == arrivals.size(),
			"...and CAN one round later — exactly one clash of delay (%d/%d)"
				% [ready_after, arrivals.size()])

	print("[muster] ALL PASS" if _fails == 0 else "[muster] FAILURES=%d" % _fails)
	get_tree().quit(_fails)


## Both sides go through their REAL arrival path — the enemy dealer and the
## player's own _play_creature — so the probe exercises the shipped plumbing
## rather than a fiction that happens to set the same flag.
func _spawn(combat, card_id: String, is_enemy: bool, lane: int):
	if is_enemy:
		var data: Dictionary = CardDB.get_card_data(card_id)
		if data.is_empty():
			_check(false, "fixture card '%s' exists" % card_id)
			return null
		combat._place_enemy_card(data.duplicate(true), lane)
		return combat._row_array(true, 0)[lane]
	# Player side: field a real creature out of the real hand.
	# card_id "" = any body that does NOT ignore the delay (Swift bodies are a
	# valid draw and would legitimately show no mark — an unlucky fixture read
	# as a failure the first time this ran). card_id "swift" = the exception.
	for c in combat._hand:
		if not is_instance_valid(c) or String(c.card_data.get("type", "")) != "creature":
			continue
		if card_id == "" and c.ignores_muster_delay():
			continue
		if card_id == "swift" and not c.ignores_muster_delay():
			continue
		if card_id != "" and card_id != "swift" and String(c.card_id) != card_id:
			continue
		combat.player_mana = 99
		combat._play_creature(c, 0)
		for row in [0, 1]:
			for i in 4:
				var occupant = combat._row_array(false, row)[i]
				if occupant == c:
					return c
		return null
	return null


func _status_ids(card) -> Array:
	var out: Array = []
	for e in card._active_effect_entries(true):
		out.append(String(e.get("id", "")))
	return out


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		printerr("  FAIL  " + label)
	return ok
