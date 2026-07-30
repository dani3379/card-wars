extends SceneTree
## Deck-count conservation probe (2026-07-09).
##
## Guards the invariant behind every deck/pile counter the player sees: a card
## that starts a fight in the deck is always in EXACTLY ONE zone — draw pile,
## discard pile, exhaust pile, hand, or battlefield. A uid that appears twice
## means a double-count (deck grows after reshuffle); a uid that appears
## nowhere means a leak (deck silently shrinks — the "deck doesn't count my
## cards" bug class, e.g. the old pop-then-_draw_card-with-a-full-hand paths).
##
## Two parts:
##   1. Micro-tests: the two historical hand-full vanish paths (_look_top_pick
##      / Stray Cat, and the raise_dead on-play verb) with a 10-card hand.
##   2. Sweep: auto-plays every EncounterDB fight (autorun-style dumb pilot)
##      and asserts conservation at the start of every player turn.
##
## Encounters whose PASSIVE deliberately exiles cards (void_exile passive,
## exile_card reactive) are exempt from the "vanished" check — exile is the
## design there — but still checked for duplicates.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_deck_conservation.gd

const HEROES := ["raider", "stalwart", "acolyte", "pyromancer", "kindler"]
const MAX_ROUNDS := 40
const TURN_WAIT_TICKS := 80
const TICK := 0.1
const SETTLE_TICK := 0.05
const SETTLE_MAX_TICKS := 40
const MODAL_BLOCKLIST := ["familiar", "scholar", "treasure_hunter", "adaptable",
	"copycat", "doppelganger", "lost_tome", "war_council", "chaos_imp"]
const POOL_WINDOW := 16

var RS: Node
var EDB: Node
var US: Node
var SS: Node
var NM: Node
var CDB: Node
var combat: Node
var _pool: Array = []

var _started := false
var _done := false
var _fails := 0
var _checks := 0
var _fights := 0
var _stuck: Array = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("[conserve]   OK   %s" % label)
	else:
		_fails += 1
		print("[conserve]   FAIL %s" % label)


func _run() -> void:
	print("[conserve] start")
	RS  = root.get_node_or_null("RunState")
	EDB = root.get_node_or_null("EncounterDB")
	US  = root.get_node_or_null("UserSettings")
	SS  = root.get_node_or_null("SkirmishState")
	NM  = root.get_node_or_null("NetMatch")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or EDB == null or CDB == null:
		print("[conserve] FATAL: autoloads missing")
		_finish(1)
		return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	if NM != null and NM.has_method("leave"):
		NM.leave()
	for id in CDB.CARD_POOL.keys():
		var d: Dictionary = CDB.CARD_POOL[id]
		if String(d.get("type", "")) in ["creature", "spell"] \
				and String(d.get("rarity", "")) != "enemy" and not CDB.is_curse(String(id)):
			_pool.append(String(id))
	_pool.sort()

	await _micro_tests()

	var enc_ids: Array = []
	for id in EDB.ENCOUNTERS.keys():
		enc_ids.append(String(id))
	enc_ids.sort()
	print("[conserve] sweeping %d encounters" % enc_ids.size())
	for i in enc_ids.size():
		var hero: String = HEROES[i % HEROES.size()]
		await _fight(i + 1, enc_ids.size(), hero, enc_ids[i])

	print("[conserve] ============ SUMMARY ============")
	print("[conserve] fights: %d  checks: %d  FAILS: %d  softlocks: %d %s"
		% [_fights, _checks, _fails, _stuck.size(), str(_stuck)])
	print("[conserve] DONE %s" % ("(all green)" if _fails == 0 and _stuck.is_empty() else "(FAILURES ABOVE)"))
	_finish(0 if _fails == 0 and _stuck.is_empty() else 1)


# ── Part 1: hand-full micro-tests ────────────────────────────────────────────

func _micro_tests() -> void:
	print("[conserve] — micro-tests: hand-full draw sinks —")
	RS.start_new_run("raider", 0, 777)
	# Fatten the deck so the hand can be filled to the cap with pile to spare.
	for _i in 14:
		RS.add_card("pikeman")
	var enc_ids: Array = EDB.ENCOUNTERS.keys()
	enc_ids.sort()
	RS.current_encounter_id = String(enc_ids[0])
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		_check(false, "micro-test combat reached a player turn")
		await _teardown()
		return

	# Fill the hand to the cap.
	var guard := 0
	while combat._hand.size() < combat.MAX_HAND_SIZE and guard < 40:
		var before: int = combat._hand.size()
		combat.draw_one()
		if combat._hand.size() == before:
			break
		guard += 1
	_check(combat._hand.size() == combat.MAX_HAND_SIZE,
		"hand filled to cap (%d/%d)" % [combat._hand.size(), combat.MAX_HAND_SIZE])

	# Stray Cat's look-top pick must NOT eat a card when the hand is full.
	var pile_before: int = combat._player_draw_pile.size()
	combat._look_top_pick(3)
	_check(combat._player_draw_pile.size() == pile_before,
		"_look_top_pick with a full hand leaves the draw pile intact (%d)" % pile_before)
	_check(combat._hand.size() == combat.MAX_HAND_SIZE,
		"_look_top_pick with a full hand adds nothing")

	# raise_dead must NOT eat the discard entry when the hand is full.
	combat._player_discard_pile.append(combat._pile_entry("pikeman", -777))
	var fake = combat.CARD_SCENE.instantiate()
	fake.card_id = "probe_raiser"
	fake.card_data = {"id": "probe_raiser", "name": "Probe Raiser", "type": "creature",
		"cost": 0, "atk": 1, "hp": 1, "rarity": "starter", "keywords": [],
		"desc": "probe", "on_play": {"type": "raise_dead"}}
	fake.is_on_battlefield = true
	combat.add_child(fake)
	var disc_before: int = combat._player_discard_pile.size()
	await combat._resolve_on_play_ability(fake, 0, false)
	_check(combat._player_discard_pile.size() == disc_before,
		"raise_dead with a full hand leaves the discard intact (%d)" % disc_before)

	# Free a hand slot: the same verbs must then work (and conserve the card).
	var dropped = combat._hand.pop_back()
	combat._player_discard_pile.append(
		combat._pile_entry(dropped.card_id, dropped.deck_uid))
	dropped.queue_free()
	disc_before = combat._player_discard_pile.size()
	await combat._resolve_on_play_ability(fake, 0, false)
	_check(combat._player_discard_pile.size() == disc_before - 1
			and combat._hand.size() == combat.MAX_HAND_SIZE,
		"raise_dead with a free slot moves one discard creature to hand")
	fake.queue_free()
	await _teardown()


# ── Part 2: encounter sweep with per-round conservation ─────────────────────

func _fight(n: int, total: int, hero: String, enc_id: String) -> void:
	var enc: Dictionary = EDB.get_encounter(enc_id)
	var etype: String = String(enc.get("type", "combat"))
	print("[conserve] >>> FIGHT %d/%d hero=%s enc=%s" % [n, total, hero, enc_id])
	RS.start_new_run(hero, 0, 4242)
	RS.current_encounter_id = enc_id
	RS.current_node_type = etype if etype in ["combat", "elite", "boss"] else "combat"
	for k in POOL_WINDOW:
		if _pool.size() > 0:
			RS.add_card(_pool[((n - 1) * POOL_WINDOW + k) % _pool.size()])

	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	_fights += 1
	if not await _wait_for_player_turn():
		_record_stuck(enc_id, "boot")
		await _teardown()
		return

	# Exile passives remove cards from the fight BY DESIGN — skip only the
	# "vanished" half of the check there. Amalgam/phase fights can SWITCH to an
	# exile passive mid-fight, so re-check every round and LATCH (cards exiled
	# in an earlier phase stay legitimately gone).
	var exile_fight := false

	# THE DECK CAN GROW MID-FIGHT. Black Contract (unholy_bargain) calls
	# RunState.add_card("war_debt"), which appends to the RUN's permanent deck and
	# deliberately does NOT deal the card into the fight in progress — it arrives
	# from the NEXT fight on (see Combat._add_discovered_card_to_hand's header for
	# why mid-fight insertion was removed). Re-reading RS.deck_uids every round
	# therefore reports a legitimate new uid as a leak.
	#
	# The invariant this probe actually guards is the one in its header: a card
	# that STARTS a fight in the deck is always in exactly one zone. Snapshot the
	# roster at the opening bell and hold every round against that.
	var start_uids: Array = RS.deck_uids.duplicate()
	var start_ids: Array = RS.deck.duplicate()

	var rounds := 0
	while is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER and rounds < MAX_ROUNDS:
		if String(combat._encounter_passive) == "void_exile" \
				or String(combat._reactive_passive.get("type", "")) == "exile_card":
			exile_fight = true
		_assert_conservation(enc_id, rounds + 1, exile_fight, start_uids, start_ids)
		await _auto_play_turn()
		if not is_instance_valid(combat):
			break
		combat._end_turn_confirmed = true
		if combat.phase == combat.Phase.PLAYER_TURN:
			combat._on_end_turn()
		rounds += 1
		if not await _wait_for_player_turn():
			break
	if is_instance_valid(combat) and combat.phase != combat.Phase.GAME_OVER \
			and rounds < MAX_ROUNDS:
		_record_stuck(enc_id, "no_player_turn")
	elif rounds >= MAX_ROUNDS:
		_record_stuck(enc_id, "max_rounds")
	await _teardown()


func _assert_conservation(enc_id: String, rnd: int, exile_fight: bool,
		start_uids: Array, start_ids: Array) -> void:
	var zones: Dictionary = {}   # uid -> Array[zone names]
	var note := func(uid: int, zone: String) -> void:
		if uid < 0:
			return
		if not zones.has(uid):
			zones[uid] = []
		zones[uid].append(zone)
	for e in combat._player_draw_pile:
		note.call(combat._entry_uid(e), "draw")
	for e in combat._player_discard_pile:
		note.call(combat._entry_uid(e), "discard")
	for e in combat._exhaust_pile:
		note.call(combat._entry_uid(e), "exhaust")
	for c in combat._hand:
		if c != null and is_instance_valid(c):
			note.call(int(c.deck_uid), "hand")
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			for c in combat._row_array(is_enemy, row):
				if c != null and is_instance_valid(c):
					note.call(int(c.deck_uid), "field")

	var errs: Array = []
	for uid in zones:
		if zones[uid].size() > 1:
			errs.append("uid %d DOUBLE-COUNTED in %s" % [uid, str(zones[uid])])
	if not exile_fight:
		for i in start_uids.size():
			var uid: int = int(start_uids[i])
			if not zones.has(uid):
				errs.append("uid %d (%s) VANISHED" % [uid, String(start_ids[i])])
	if errs.is_empty():
		_checks += 1   # one silent OK per clean round keeps the log readable
	else:
		for e in errs:
			_check(false, "%s R%d: %s" % [enc_id, rnd, e])


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.GAME_OVER:
			return true
		# NOT `phase == PLAYER_TURN` on its own. `Phase.PLAYER_TURN` is enum 0 AND
		# the declared default of `var phase`, so it reads true on the very first
		# tick — before `_ready` has awaited its way through _build_hud() and
		# _init_decks(). A probe that trusts it gets a Combat with a null HUD and
		# an EMPTY draw pile, which reads as "every uid in the deck VANISHED".
		# `round_number` starts at 0 and only leaves it inside _start_round(),
		# strictly after both. See docs: the probe-readiness trap.
		if int(combat.round_number) >= 1 and combat.phase == combat.Phase.PLAYER_TURN:
			await _wait_hand_settled()
			return true
		await create_timer(TICK).timeout
		waited += 1
	return false


## The refill deals ONE card immediately and staggers the rest on 0.08 s timers
## (Combat._start_round). Conservation itself is safe mid-stagger — a not-yet-
## dealt card is still an entry in the draw pile, and draw_one/_draw_card move it
## atomically — but the micro-tests and the auto-play pilot both need the settled
## hand, or they measure a one-card turn.
func _wait_hand_settled() -> void:
	var last := -1
	var stable := 0
	var waited := 0
	while stable < 3 and waited < SETTLE_MAX_TICKS:
		if not is_instance_valid(combat):
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _auto_play_turn() -> void:
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
			var ctype: String = String(cd.get("type", ""))
			if ctype == "creature":
				var slot = _find_empty_player_slot()
				if slot == null:
					continue
				card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
				combat._on_card_played(card)
				played_any = true
				await create_timer(0.03).timeout
			elif ctype == "spell":
				if String(cd.get("targeting", "none")) == "none":
					combat._on_card_played(card)
					played_any = true
					await create_timer(0.03).timeout
		if not played_any:
			return


func _find_empty_player_slot():
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


func _record_stuck(enc_id: String, why: String) -> void:
	print("[conserve] <<< STUCK (%s) enc=%s" % [why, enc_id])
	_stuck.append("%s:%s" % [enc_id, why])


func _teardown() -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	combat = null
	await create_timer(0.1).timeout


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	_done = true
	quit(code)
