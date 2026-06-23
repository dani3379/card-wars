extends SceneTree
## Regression probe: INTERACTIVE board reposition on the Skirmish CLIENT.
##
## Guards the bug where dragging a board creature in multiplayer made it "glitch to
## a random place": the idle-bob (_process writes position.y every frame and owns it)
## fought the drag, pinning the card's Y to its anchor while only X tracked the
## cursor — and could lock the card off-slot after the move. The logic-only net
## probes never drive the real Card2D drag entry points, so this one does:
## _begin/_update/_end_field_grab, then the host's board_sync that performs the move.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_repos_client.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false
var SS: Node
var NM: Node
var combat: Node


func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		_fails += 1


func _center(slot) -> Vector2:
	return slot.global_position + slot.size * 0.5


func _card_center(c) -> Vector2:
	return c.global_position + c.size * 0.5


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()
	return _done


func _run_test() -> void:
	print("[net-repos-client] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_CLIENT
	SS.local_index = 1
	SS.rng_seed = 777
	NM.is_host = false
	NM.local_player_index = 1
	NM._connected = true
	NM.remote_present = true
	NM.entities.clear()
	NM._next_entity_id = 1
	# send_intent no-ops safely with a null multiplayer peer — we observe EFFECTS.

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	await create_timer(0.3).timeout

	# Make the client ACTIVE (its turn) so the board is interactive.
	combat._net_active_index = 1
	combat._net_turn_round = 2
	combat._net_local_turn_begin()
	await create_timer(0.2).timeout
	combat._moves_used_this_turn = 0

	# Spawn one of the client's OWN creatures (owner=1, friendly side locally).
	var eid: int = 5001
	var data = root.get_node("CardDB").get_card_data("brute")
	var card = combat._net_spawn_creature(data, eid, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.3).timeout
	if card == null or not is_instance_valid(card):
		_check(false, "client spawned its own creature")
		_finish(1)
		return
	var home_slot = combat._slot_array(false, combat.ROW_FRONT)[0]
	_check(_card_center(card).distance_to(_center(home_slot)) < 80.0, "spawned card sits ON its slot")

	# ── Drag it onto front lane 2 via the REAL Card2D drag entry points. ──
	var dest_slot = combat._slot_array(false, combat.ROW_FRONT)[2]
	var dest_center: Vector2 = _center(dest_slot)
	var start_pos: Vector2 = _card_center(card)
	card._begin_field_grab(start_pos)
	card._update_field_grab(start_pos + Vector2(60, 0))   # cross threshold → lift
	await create_timer(0.1).timeout                       # frames run: bob must NOT pin Y
	card._update_field_grab(dest_center)                  # drag to destination
	await create_timer(0.1).timeout
	_check(_card_center(card).distance_to(dest_center) < 30.0,
		"card tracks the cursor mid-drag (not pinned by the idle bob)")
	card._end_field_grab(dest_center)                     # drop → intent + return home
	await create_timer(0.2).timeout

	# Client doesn't move locally: it returns home and waits for the host snapshot.
	_check(int(combat._moves_used_this_turn) == 1, "client counted the move locally")
	_check(int(card.current_lane) == 0, "card snapped back home pending host sync")
	_check(_card_center(card).distance_to(_center(home_slot)) < 80.0,
		"returned card sits ON its home slot (not off in a random place)")

	# ── The host's board_sync arrives and performs the actual move to lane 2. ──
	combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [{
			"eid": eid, "owner": 1, "lane": 2, "row": combat.ROW_FRONT,
			"id": "brute", "atk": int(card.current_atk), "hp": int(card.current_hp),
			"mhp": int(data.get("hp", 1)), "kw": data.get("keywords", []),
			"floop": false, "token": false,
		}],
		"host_hp": combat.enemy_hp, "client_hp": combat.player_hp, "active": 1,
	})
	await create_timer(0.4).timeout

	_check(int(card.current_lane) == 2, "after sync, card is at lane 2")
	_check(combat._row_array(false, combat.ROW_FRONT)[2] == card, "friendly array slot 2 holds the card")
	_check(combat._row_array(false, combat.ROW_FRONT)[0] == null, "friendly array slot 0 cleared")
	_check(_card_center(card).distance_to(dest_center) < 80.0,
		"card landed ON the destination slot")

	if _fails == 0:
		print("[net-repos-client] ALL PASS")
	else:
		print("[net-repos-client] %d FAILURES" % _fails)
	_finish(1 if _fails > 0 else 0)


func _finish(code: int) -> void:
	_done = true
	quit(code)
