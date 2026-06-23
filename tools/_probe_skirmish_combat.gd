extends SceneTree
## Fake-peer COMBAT harness — Online Skirmish (docs/MULTIPLAYER_SKIRMISH_PLAN.md §16.3).
##
## Unlike _probe_skirmish.gd (pure logic, no scene), this boots the REAL combat
## scene as the HOST and drives a full turn cycle with SCRIPTED CLIENT INTENTS —
## no sockets. It forces NetMatch into a "connected host" state so the scene runs
## its NET_HOST path; NetMatch.send_to_client / broadcast_event no-op (client_peer_id
## stays 0), so the host's authoritative engine runs without a real peer.
##
## This is the first thing to actually EXECUTE the net combat engine: turn start +
## local draw, host creature play (on-enter + entity_id registration + board sync),
## the attack clash (Swift/column/Ranged/cleanup reusing the campaign resolvers),
## turn passing, client creature & spell intents seated on the enemy side, and
## match-over. It catches runtime crashes the parse-check and logic probe can't.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_skirmish_combat.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false

var CDB: Node
var SS: Node
var NM: Node
var combat: Node


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()   # fire the coroutine; control returns here immediately
	return _done       # keep ticking frames until the coroutine finishes


func _run_test() -> void:
	print("[skirmish-combat] start")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if CDB == null or SS == null or NM == null:
		print("[skirmish-combat] FATAL: autoloads missing")
		_finish(1)
		return

	_setup_state()

	# Boot the real combat scene as host.
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)

	# Let _ready build the board / HUD / decks (everything up to the prebake).
	await create_timer(0.5).timeout
	# HEADLESS NOTE: _ready ends with `await _prebake_hand_textures()`, and that
	# bake awaits RenderingServer.frame_post_draw — which NEVER fires under the
	# dummy renderer, so _ready parks there forever and _net_begin_combat() is
	# never reached. That is a headless-only stall (a real windowed game emits
	# frame_post_draw every frame and the bake finishes in ~6 frames). To test the
	# host turn loop we kick the begin-combat path directly; it's idempotent
	# (_net_signals_wired guard) and has no renderer dependency.
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	# _net_begin_combat awaits 0.6s before _net_start_turn(0); poll for the draw.
	for tick in 8:
		await create_timer(0.4).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break

	if not is_instance_valid(combat):
		_check(false, "combat scene survived boot (got freed)")
		_finish(1)
		return
	_check(combat.combat_mode == combat.CombatMode.NET_HOST, "scene booted in NET_HOST mode")
	_check(int(combat._net_active_index) == 0, "turn 1 opened for the host (active=0)")
	_check(int(combat.player_hp) == SS.START_HP, "host hero at START_HP (%d)" % int(combat.player_hp))
	_check(int(combat.enemy_hp) == SS.START_HP, "client hero at START_HP")
	_check(combat._hand.size() > 0, "host drew an opening hand (%d cards)" % combat._hand.size())

	await _test_opp_mana_seal()
	await _host_plays_a_creature()
	await _test_net_draw_spell()
	await _host_attacks()
	await _client_places_a_creature()
	await _test_host_applies_reposition()
	await _client_casts_a_spell()
	await _client_attacks()
	await _test_net_custom_spell_perspective()
	await _test_net_sacrifice_spell()
	_test_match_over()

	# Phase 2: second-player opening hand (pre-deal + going-second card + skip-draw).
	await _test_client_opening_hand()
	# Phase 3: the OTHER half of the engine — the client reconciling host snapshots.
	await _run_client_reconcile_test()
	# Phase 4: rematch (HP refresh + handshake flags).
	_test_rematch_logic()

	if _fails == 0:
		print("[skirmish-combat] ALL PASS")
	else:
		print("[skirmish-combat] %d FAILURES" % _fails)
	_finish(1 if _fails > 0 else 0)


# ─────────────────────────────────────────────────────────────────────────

func _setup_state() -> void:
	SS.reset()
	# Host deck (slot 0): creatures + a couple of damage spells so the opening hand
	# offers a real creature to play. Client deck (slot 1) is filled for symmetry
	# (the host doesn't draw it in v1, but keep it real).
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345

	# Force NetMatch to look like a connected host (no real socket).
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0   # 0 => send_to_client no-ops, no rpc on a null peer
	NM.entities.clear()
	NM._next_entity_id = 1


## Foe Command seal — the opponent's mana mirror. Built during _net_begin_combat
## (same builder as the player's seal), seeded from the opponent slot, and fed by the
## client's EV_HAND_COUNT, which now carries the client's live Command. Verifies the
## host reads that into the foe seal with the player's exact numeral formatting
## (including the banked "(+N)" overflow).
func _test_opp_mana_seal() -> void:
	print("— foe Command seal: built, seeded from the opponent slot, tracks synced Command")
	_check(combat._net_opp_mana_post != null and is_instance_valid(combat._net_opp_mana_post),
		"opponent Command seal instrument was built")
	_check(combat._net_opp_mana_label != null and is_instance_valid(combat._net_opp_mana_label),
		"opponent Command numeral label exists")
	_check(int(combat._net_opp_max_mana) == SS.BASE_MAX_MANA,
		"opp max Command seeded from the opponent slot (%d)" % int(combat._net_opp_max_mana))
	# A client hand-count intent now carries the client's live Command; the host
	# reads it into the foe seal.
	combat._on_net_intent(2, {"t": NM.EV_HAND_COUNT, "n": 4, "mana": 2, "maxmana": 4})
	await create_timer(0.1).timeout
	_check(int(combat._net_opp_mana) == 2 and int(combat._net_opp_max_mana) == 4,
		"host stored the client's synced Command (%d/%d)" % [int(combat._net_opp_mana), int(combat._net_opp_max_mana)])
	_check(combat._net_opp_mana_label.text == "2 / 4",
		"foe seal numeral reads '2 / 4' (got '%s')" % combat._net_opp_mana_label.text)
	# Banked carryover (current > max) shows the (+N) overflow, mirroring the player.
	combat._on_net_intent(2, {"t": NM.EV_HAND_COUNT, "n": 4, "mana": 5, "maxmana": 3})
	await create_timer(0.1).timeout
	_check(combat._net_opp_mana_label.text == "5 / 3 (+2)",
		"foe seal shows banked overflow '5 / 3 (+2)' (got '%s')" % combat._net_opp_mana_label.text)


func _first_hand_creature():
	for c in combat._hand:
		if is_instance_valid(c) and c.is_creature():
			return c
	return null


func _host_plays_a_creature() -> void:
	print("— host plays a creature on its turn")
	var card = _first_hand_creature()
	if card == null:
		_check(false, "host hand contained a playable creature")
		return
	# Aim the drop at front-row lane 0 so placement is deterministic (the play path
	# reads card.global_position + size*0.5 and snaps to the nearest slot).
	var slot = combat._slot_array(false, combat.ROW_FRONT)[0]
	if is_instance_valid(slot):
		card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5
	var before: int = combat._all_player_creatures().size()
	var ents_before: int = NM.entities.size()
	combat._on_card_played(card)
	await create_timer(0.4).timeout
	var after: int = combat._all_player_creatures().size()
	_check(after == before + 1, "a creature is now seated on the host's board (%d -> %d)" % [before, after])
	_check(NM.entities.size() > ents_before, "the host registered an entity_id for it")
	# Its entity_id should equal its deck uid (drafted-creature contract).
	var seated = combat._all_player_creatures()
	if seated.size() > 0:
		var c = seated[0]
		_check(int(c.entity_id) == int(c.deck_uid), "host creature entity_id == deck_uid (%d)" % int(c.entity_id))


## Draw/Command channel — HOST side: a draw spell the host casts must draw into the
## host's OWN hand locally (caster_is_enemy false). quick_shot with no target also
## hits the caster's enemy face. (The client-receive side is covered in the
## opening-hand test via _on_net_event EV_DRAW.)
func _test_net_draw_spell() -> void:
	print("— host casts a draw spell (quick_shot): draws locally + hits client face")
	var hand_before: int = combat._hand.size()
	var enemy_face_before: int = int(combat.enemy_hp)
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "quick_shot"}}, -1, 0)
	await create_timer(0.2).timeout
	_check(combat._hand.size() == hand_before + 1,
		"host drew 1 from quick_shot (%d -> %d)" % [hand_before, combat._hand.size()])
	_check(int(combat.enemy_hp) < enemy_face_before,
		"quick_shot (no target) hit the client face (%d -> %d)" % [enemy_face_before, int(combat.enemy_hp)])


func _host_attacks() -> void:
	print("— host 'attacks' on turn 1 (PLACE-ONLY: no free face damage)")
	var enemy_hp_before: int = int(combat.enemy_hp)
	_check(int(combat._net_turn_round) == 1, "host's opening turn is round 1")
	# Call the async resolver directly so we can await the full pass.
	await combat._net_run_attack(0)
	_check(is_instance_valid(combat), "scene survived the opening-turn pass")
	# Turn 1 is place-only — the opener must NOT deal face damage into an empty board.
	_check(int(combat.enemy_hp) == enemy_hp_before, "no attack landed on turn 1 (%d -> %d)" % [enemy_hp_before, int(combat.enemy_hp)])
	_check(int(combat._net_active_index) == 1, "turn passed to the client (active=1, round 2)")
	_check(int(combat._net_turn_round) == 2, "turn counter advanced to round 2")


func _client_places_a_creature() -> void:
	print("— client places a creature via a play intent")
	var enemy_before: int = combat._all_enemy_creatures().size()
	# Slot-1 uid space (deterministic): SkirmishState slot 1 starts at STRIDE.
	var uid: int = SS.UID_SLOT_STRIDE + 0
	combat._on_net_intent(2, {
		"t": NM.IN_PLAY_CREATURE, "uid": uid, "id": "brute",
		"lane": 1, "row": combat.ROW_FRONT,
	})
	await create_timer(0.3).timeout
	var enemy_after: int = combat._all_enemy_creatures().size()
	_check(enemy_after == enemy_before + 1, "client creature seated on the host's enemy side (%d -> %d)" % [enemy_before, enemy_after])
	_check(NM.get_entity(uid) != null, "client creature registered under its uid as entity_id")


## HOST applies the client's reposition intent: the client's creature sits on the
## host's ENEMY side; moving it to an empty enemy slot must update the board arrays.
func _test_host_applies_reposition() -> void:
	print("— host applies the client's reposition intent (client's turn, active=1)")
	var eid: int = SS.UID_SLOT_STRIDE + 0
	var node = NM.get_entity(eid)
	if node == null or not is_instance_valid(node):
		_check(false, "client creature present to reposition")
		return
	var src_lane: int = int(node.current_lane)
	combat._net_apply_remote_reposition({"t": NM.IN_REPOSITION, "eid": eid, "lane": 2, "row": combat.ROW_FRONT})
	await create_timer(0.2).timeout
	_check(int(node.current_lane) == 2, "host moved the client creature to lane 2 (from %d)" % src_lane)
	_check(combat._row_array(true, combat.ROW_FRONT)[2] == node, "creature occupies the destination enemy slot")
	_check(combat._row_array(true, combat.ROW_FRONT)[src_lane] == null, "source enemy slot cleared")


## A NEW custom net spell, resolved with CLIENT perspective (caster_index 1): an
## AoE must hit the CASTER's foes (the host's creatures + face), never the caster's
## own board. Spawns its OWN fresh pair so it's self-contained (earlier creatures may
## have died) and drives _net_resolve_spell directly (no card-id lookup needed).
func _test_net_custom_spell_perspective() -> void:
	print("— net custom spell perspective: client's inferno hits the HOST side only")
	if combat._net_match_over:
		_check(true, "match already over before perspective test (skipped, acceptable)")
		return
	# Fresh creatures in empty back-row lane 3: one on the host's own side, one on the
	# client's side (host POV: is_enemy_side true). Entity ids are arbitrary probe ids.
	var host_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 90001, 3, combat.ROW_BACK, false, false)
	var client_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 90002, 3, combat.ROW_BACK, true, false)
	await create_timer(0.2).timeout
	if not is_instance_valid(host_c) or not is_instance_valid(client_c):
		_check(false, "spawned a fresh host + client creature for the perspective test")
		return
	var host_hp_before: int = int(host_c.current_hp)
	var client_hp_before: int = int(client_c.current_hp)
	var host_face_before: int = int(combat.player_hp)
	# caster_index 1 = client. Inferno: 4 to the caster's foes (the host's creatures)
	# + 4 to the caster's enemy face (the host hero == player_hp from the host POV).
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "inferno"}}, -1, 1)
	await create_timer(0.2).timeout
	_check(not is_instance_valid(host_c) or int(host_c.current_hp) < host_hp_before,
		"inferno damaged the host's creature (caster's foe)")
	_check(int(combat.player_hp) < host_face_before,
		"inferno damaged the host face (caster's enemy face)")
	_check(is_instance_valid(client_c) and int(client_c.current_hp) == client_hp_before,
		"inferno spared the client's OWN creature (perspective correct)")


func _client_casts_a_spell() -> void:
	print("— client casts a damage spell at a host creature")
	var targets = combat._all_player_creatures()
	if targets.is_empty():
		_check(false, "a host creature exists to target")
		return
	var target = targets[0]
	var eid: int = int(target.entity_id)
	var hp_before: int = int(target.current_hp)
	combat._on_net_intent(2, {
		"t": NM.IN_PLAY_SPELL, "uid": SS.UID_SLOT_STRIDE + 4,
		"id": "strike", "target": eid,
	})
	await create_timer(0.3).timeout
	var hit := not is_instance_valid(target) or int(target.current_hp) < hp_before
	_check(hit, "the targeted host creature took spell damage (or died)")


func _client_attacks() -> void:
	print("— client attacks on round 2 (real contested clash — attacks ARE allowed now)")
	var host_hero_before: int = int(combat.player_hp)
	# The client's end-of-actions intent triggers _net_run_attack(1) inside the
	# host; call the resolver directly so we can await it.
	await combat._net_run_attack(1)
	_check(is_instance_valid(combat), "scene survived the client clash")
	# Round 2 > 1, so the client's creature DOES strike — into an undefended host
	# lane it reaches the host's face. (Turn-1 lockout is only the opening turn.)
	_check(int(combat.player_hp) < host_hero_before, "client's round-2 attack landed (host hero %d -> %d)" % [host_hero_before, int(combat.player_hp)])
	if is_instance_valid(combat) and not combat._net_match_over:
		_check(int(combat._net_active_index) == 0, "turn returned to the host (active=0)")


## Sacrifice (offering): the host sacrifices its OWN fresh creature and gains Command.
## Self-contained — spawns the victim so it doesn't disturb the other board tests.
func _test_net_sacrifice_spell() -> void:
	print("— host casts offering: sacrifices its own creature, gains Command")
	if combat._net_match_over:
		_check(true, "match already over before sacrifice test (skipped, acceptable)")
		return
	var victim = combat._net_spawn_creature(CDB.get_card_data("brute"), 90003, 0, combat.ROW_BACK, false, false)
	await create_timer(0.2).timeout
	if not is_instance_valid(victim):
		_check(false, "spawned a host creature to sacrifice")
		return
	var mana_before: int = int(combat.player_mana)
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "offering"}}, int(victim.entity_id), 0)
	await create_timer(0.2).timeout
	_check(not is_instance_valid(victim) or int(victim.current_hp) <= 0,
		"offering sacrificed the host's own creature")
	_check(int(combat.player_mana) >= mana_before + 2,
		"host gained Command from offering (%d -> %d)" % [mana_before, int(combat.player_mana)])


func _test_match_over() -> void:
	print("— match-over detection + winner attribution")
	if not is_instance_valid(combat) or combat._net_match_over:
		_check(combat._net_match_over, "match already concluded during the clash (acceptable)")
		return
	combat.enemy_hp = 0
	combat._net_host_check_match_over()
	_check(combat._net_match_over, "match flagged over when a hero hits 0 HP")
	_check(combat.phase == combat.Phase.GAME_OVER, "phase moved to GAME_OVER")


## Boot a fresh NET_CLIENT scene and verify the second player's opening hand is
## pre-dealt (so they can see it during turn 1) at refill+1 (going-second card),
## and that their first turn skips the draw rather than topping the hand up.
func _test_client_opening_hand() -> void:
	print("— second player (client) opening hand: pre-dealt + going-second card")
	if is_instance_valid(combat):
		combat.queue_free()
		await create_timer(0.2).timeout
	NM.leave()
	SS.combat_mode = SS.CombatMode.NET_CLIENT
	SS.local_index = 1
	NM.is_host = false
	NM.local_player_index = 1
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	await create_timer(0.5).timeout
	if not is_instance_valid(combat):
		_check(false, "client opening-hand scene booted")
		return
	# _ready stalls at prebake headless; the client branch of _net_begin_combat
	# pre-deals the opening hand (no renderer dependency).
	combat._net_begin_combat()
	await create_timer(0.4).timeout
	var refill: int = combat.HAND_REFILL_TARGET
	_check(combat._hand.size() == refill + 1,
		"client opened with refill+1 = %d cards (got %d)" % [refill + 1, combat._hand.size()])
	_check(combat._net_skip_draw_this_round, "skip-draw armed so turn 1 won't top it up")
	# Simulate the client's first turn (round 2): _start_round must SKIP the draw.
	var before: int = combat._hand.size()
	combat._net_client_turn_begin(1, 2)
	await create_timer(0.4).timeout
	_check(combat._hand.size() == before, "first turn kept the pre-dealt hand, no re-draw (%d)" % combat._hand.size())
	_check(not combat._net_skip_draw_this_round, "skip-draw flag cleared after the first turn")
	# EV_DRAW receive: a draw spell the client cast resolves on the host, which tells
	# the client to draw from its own pile. Verify the client grows its hand on it.
	var pre_draw: int = combat._hand.size()
	combat._on_net_event({"t": NM.EV_DRAW, "n": 2})
	await create_timer(0.3).timeout
	_check(combat._hand.size() == pre_draw + 2,
		"client drew 2 cards on EV_DRAW (%d -> %d)" % [pre_draw, combat._hand.size()])


## Boot a fresh combat scene as NET_CLIENT and feed it host board snapshots to
## verify the reconcile path: owner→side mapping, HP perspective (me=1 reads
## client_hp as player_hp), spawn / stat-update / despawn.
func _run_client_reconcile_test() -> void:
	print("— client reconciles host board snapshots")
	# Tear down the host scene + shared net state (real matches have separate
	# NetMatch singletons per process; in one process we must reset between roles).
	if is_instance_valid(combat):
		combat.queue_free()
		await create_timer(0.2).timeout
	NM.leave()

	SS.combat_mode = SS.CombatMode.NET_CLIENT
	SS.local_index = 1
	NM.is_host = false
	NM.local_player_index = 1
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	# Wait for _ready to build the board/HUD (it stalls at prebake afterward, but
	# the board exists by then). The client renders snapshots; no turn loop needed.
	await create_timer(0.6).timeout
	if not is_instance_valid(combat):
		_check(false, "client scene survived boot")
		return
	_check(combat.combat_mode == combat.CombatMode.NET_CLIENT, "scene booted in NET_CLIENT mode")

	# Snapshot 1: a host creature (owner 0 → the client's ENEMY side) and a client
	# creature (owner 1 → the client's OWN side). Host POV HPs: host=20, client=18.
	var host_eid: int = 7
	var mine_eid: int = SS.UID_SLOT_STRIDE + 2
	combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": host_eid, "owner": 0, "lane": 0, "row": combat.ROW_FRONT,
			 "id": "brute", "atk": 3, "hp": 5, "mhp": 5, "kw": [], "floop": false, "token": false},
			{"eid": mine_eid, "owner": 1, "lane": 1, "row": combat.ROW_FRONT,
			 "id": "goblin", "atk": 2, "hp": 2, "mhp": 2, "kw": [], "floop": false, "token": false},
		],
		"host_hp": 20, "client_hp": 18, "active": 1,
	})
	await create_timer(0.2).timeout
	_check(combat._all_player_creatures().size() == 1, "owner-1 creature landed on the client's own side")
	_check(combat._all_enemy_creatures().size() == 1, "owner-0 creature landed on the client's enemy side")
	_check(int(combat.player_hp) == 18, "client reads client_hp as its own hero HP (got %d)" % int(combat.player_hp))
	_check(int(combat.enemy_hp) == 20, "client reads host_hp as the opponent HP (got %d)" % int(combat.enemy_hp))
	_check(NM.get_entity(host_eid) != null and NM.get_entity(mine_eid) != null, "both creatures registered by entity_id")

	# Snapshot 1.5: both creatures reposition (host_eid 0->2, mine_eid 1->3).
	# Verifies _net_reslot moves existing entities on the correct local side.
	combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": host_eid, "owner": 0, "lane": 2, "row": combat.ROW_FRONT,
			 "id": "brute", "atk": 3, "hp": 5, "mhp": 5, "kw": [], "floop": false, "token": false},
			{"eid": mine_eid, "owner": 1, "lane": 3, "row": combat.ROW_FRONT,
			 "id": "goblin", "atk": 2, "hp": 2, "mhp": 2, "kw": [], "floop": false, "token": false},
		],
		"host_hp": 20, "client_hp": 18, "active": 1,
	})
	await create_timer(0.2).timeout
	var moved_enemy = NM.get_entity(host_eid)
	var moved_mine = NM.get_entity(mine_eid)
	_check(moved_enemy != null and int(moved_enemy.current_lane) == 2 \
		and combat._row_array(true, combat.ROW_FRONT)[2] == moved_enemy,
		"client reslotted the enemy creature to lane 2")
	_check(moved_mine != null and int(moved_mine.current_lane) == 3 \
		and combat._row_array(false, combat.ROW_FRONT)[3] == moved_mine,
		"client reslotted its own creature to lane 3")
	_check(combat._row_array(true, combat.ROW_FRONT)[0] == null \
		and combat._row_array(false, combat.ROW_FRONT)[1] == null,
		"old slots cleared after reslot")

	# Snapshot 2: the host creature took damage (5 -> 2), the client creature died
	# (dropped from the list). Verifies stat-update + despawn-on-vanish.
	combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": host_eid, "owner": 0, "lane": 0, "row": combat.ROW_FRONT,
			 "id": "brute", "atk": 3, "hp": 2, "mhp": 5, "kw": [], "floop": false, "token": false},
		],
		"host_hp": 20, "client_hp": 12, "active": 0,
	})
	await create_timer(0.2).timeout
	var surviving = combat._all_enemy_creatures()
	_check(surviving.size() == 1 and int(surviving[0].current_hp) == 2, "host creature stat-updated to the new HP")
	_check(combat._all_player_creatures().is_empty(), "the vanished client creature was despawned")
	_check(NM.get_entity(mine_eid) == null, "despawned creature was unregistered")
	_check(int(combat.player_hp) == 12, "client hero HP updated from the snapshot")


## Rematch: HP refresh keeps decks but restores HP, and the handshake flags set
## correctly. Driven on the client scene so it can't self-relaunch (host-only).
func _test_rematch_logic() -> void:
	print("— rematch: HP refresh keeps decks + handshake flags (client, no relaunch)")
	SS.get_slot(0).hero_hp = 3
	SS.get_slot(1).hero_hp = 0
	var deck_size_before: int = SS.get_slot(1).deck.size()
	SS.refresh_heroes()
	_check(SS.get_slot(0).hero_hp == SS.START_HP and SS.get_slot(1).hero_hp == SS.START_HP,
		"refresh_heroes restored both heroes to START_HP")
	_check(SS.get_slot(1).deck.size() == deck_size_before and deck_size_before > 0,
		"refresh_heroes kept the drafted decks intact (%d cards)" % deck_size_before)
	if not is_instance_valid(combat) or not combat._is_client():
		_check(false, "client scene present for the rematch-flag test")
		return
	combat._net_match_over = true
	combat._net_request_rematch()
	_check(combat._net_rematch_local, "pressing REMATCH set the local want-rematch flag")
	combat._net_on_remote_rematch()
	_check(combat._net_rematch_remote, "receiving the opponent's rematch set the remote flag")
	_check(is_instance_valid(combat) and combat._is_client(),
		"client did not self-relaunch (the host drives the rematch)")


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	NM.leave()
	_done = true
	quit(code)
