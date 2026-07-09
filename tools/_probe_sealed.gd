extends SceneTree
## SEALED ORDERS battle-style harness (docs/MULTIPLAYER_SKIRMISH_PLAN.md §16.2).
##
## Boots the REAL combat scene as a fake connected host with
## NetMatch.battle_style = STYLE_SEALED and drives one full sealed round with
## scripted client traffic — no sockets: orders open (both draw, no opener, no
## Coin), a private creature commit (stand-in occupies the slot but NEVER leaks
## into a board snapshot), the foe's ghost ping, both bundles → the reveal
## (initiative interleave through the authoritative spawn path), the two
## sorcery steps, the simultaneous clash, and round 2 reopening with flipped
## initiative. Mirrors tools/_probe_skirmish_combat.gd's harness mechanics.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_sealed.gd

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
		_run_test()
	return _done


func _run_test() -> void:
	print("[sealed] start")
	CDB = root.get_node_or_null("CardDB")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	if CDB == null or SS == null or NM == null:
		print("[sealed] FATAL: autoloads missing")
		_finish(1)
		return

	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0   # send_to_client no-ops — no real peer
	NM.entities.clear()
	NM._next_entity_id = 1
	NM.battle_style = NM.STYLE_SEALED

	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	combat._net_first_player_override = 0   # deterministic initiative
	root.add_child(combat)
	await create_timer(0.5).timeout
	# Headless: _ready parks on the texture prebake — kick begin-combat directly
	# (idempotent; see _probe_skirmish_combat.gd for the full note).
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for tick in 8:
		await create_timer(0.4).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	if not is_instance_valid(combat):
		_check(false, "combat scene survived boot (got freed)")
		_finish(1)
		return

	# ── Orders phase opened, symmetric (no opener, no Coin, nobody active) ──
	print("— sealed round 1: orders phase opens for both at once")
	_check(bool(combat._is_sealed()), "combat runs in the SEALED battle style")
	_check(int(combat._net_turn_round) == 1, "round 1 open")
	_check(int(combat._net_active_index) == -1, "no active turn — both sides act at once")
	_check(int(combat._net_initiative) == 0, "initiative = the (forced) seed coin flip")
	_check(combat._hand.size() > 0, "host drew an orders hand (%d)" % combat._hand.size())
	var coins := 0
	for c in combat._hand:
		if is_instance_valid(c) and String(c.card_id) == "coin":
			coins += 1
	_check(coins == 0, "no Coin — sealed play needs no going-second compensation")
	_check(combat._end_turn_btn != null and String(combat._end_turn_btn.text).begins_with("SEAL"),
		"the button reads SEAL ORDERS")

	# ── A private commit: stand-in seats, nothing registers, snapshots skip it ──
	print("— a creature order is a PRIVATE commitment")
	var hand_card: Control = null
	for c in combat._hand:
		if is_instance_valid(c) and c.is_creature() \
				and int(c.card_data.get("cost", 9)) <= int(combat.player_mana):
			if hand_card == null or int(c.card_data.get("cost", 9)) < int(hand_card.card_data.get("cost", 9)):
				hand_card = c
	if hand_card == null:
		_check(false, "found an affordable creature in the orders hand")
		_finish(1)
		return
	var order_uid: int = int(hand_card.deck_uid)
	var mana_before: int = int(combat.player_mana)
	var order_cost: int = int(hand_card.card_data.get("cost", 0))
	combat._sealed_commit_creature(hand_card, order_cost, 0, combat.ROW_FRONT)
	await create_timer(0.2).timeout
	_check(combat._sealed_pending.size() == 1, "the order joined the pending bundle")
	_check(int(combat.player_mana) == mana_before - order_cost, "Command paid at commit")
	var stand = combat._row_array(false, combat.ROW_FRONT)[0]
	_check(stand != null and is_instance_valid(stand) and stand.get_meta("sealed_pending", false),
		"a stand-in occupies the slot (second orders can't stack on it)")
	combat._net_sync_board()
	await create_timer(0.1).timeout
	_check(stand != null and is_instance_valid(stand) and int(stand.entity_id) < 0 \
			and not NM.entities.values().has(stand),
		"the stand-in never enters a snapshot (no entity id — the order stays private)")

	# ── The foe's ghost ping shows position only ──
	combat._on_net_intent(2, {"t": NM.IN_ORDER_GHOST, "lane": 2, "row": 0})
	await create_timer(0.15).timeout
	_check(combat._sealed_ghosts.size() == 1, "the foe's commit shows as a face-down ghost")
	_check(combat._row_array(true, combat.ROW_FRONT)[2] == null,
		"the ghost is pure UI — no creature on the enemy board yet")

	# ── Host seals; nothing resolves until BOTH bundles are in ──
	print("— seal + reveal: both bundles seat together, initiative first")
	combat._sealed_on_button()
	await create_timer(0.2).timeout
	_check(bool(combat._sealed_await_foe), "host sealed — awaiting the foe")
	_check(combat._sealed_bundles.has(0), "host bundle stored")
	_check(combat._row_array(true, combat.ROW_FRONT)[2] == null,
		"one sealed side resolves nothing (the reveal waits for both)")

	# ── The client's bundle lands → the orders break open ──
	combat._on_net_intent(2, {"t": NM.IN_ORDERS, "mana": 1, "list": [
		{"id": "brute", "uid": 501, "lane": 2, "row": 0},
		{"id": "goblin", "uid": 502, "lane": 0, "row": 0},
	]})
	await create_timer(1.6).timeout
	var host_c = combat._row_array(false, combat.ROW_FRONT)[0]
	_check(host_c != null and is_instance_valid(host_c) \
			and not host_c.get_meta("sealed_pending", false) \
			and int(host_c.entity_id) == order_uid,
		"the host's REAL creature replaced its stand-in (registered under its uid)")
	var cli_a = combat._row_array(true, combat.ROW_FRONT)[2]
	var cli_b = combat._row_array(true, combat.ROW_FRONT)[0]
	_check(cli_a != null and is_instance_valid(cli_a) and int(cli_a.entity_id) == 501,
		"client order 1 seated on the enemy side (eid 501)")
	_check(cli_b != null and is_instance_valid(cli_b) and int(cli_b.entity_id) == 502,
		"client order 2 seated on the enemy side (eid 502)")
	_check(combat._sealed_ghosts.is_empty(), "the ghosts cleared at the reveal")
	_check(int(combat._net_cards_played[0]) == 1 and int(combat._net_cards_played[1]) == 2,
		"per-side play tallies kept through the reveal (1 host / 2 client)")

	# ── Sorcery: two sequential steps, initiative first, second pass → clash ──
	print("— sorcery window: initiative's step, foe's step, then the lines clash")
	_check(int(combat._sorcery_active) == 0, "initiative (host) holds the first spell step")
	_check(combat._end_turn_btn != null and String(combat._end_turn_btn.text).begins_with("PASS"),
		"the button reads PASS in the sorcery window")
	var host_hp_before: int = int(combat.player_hp)
	var cli_hp_before: int = int(cli_b.current_hp) if is_instance_valid(cli_b) else 0
	combat._sealed_on_button()   # host passes
	await create_timer(0.2).timeout
	_check(int(combat._sorcery_active) == 1, "the step passed to the foe")
	combat._on_net_intent(2, {"t": NM.IN_SORCERY_PASS})
	# Second pass → the simultaneous clash + the next orders phase. Real-time pauses.
	for tick in 30:
		await create_timer(0.4).timeout
		if not is_instance_valid(combat) or int(combat._net_turn_round) >= 2 \
				or combat._net_match_over:
			break
	if combat._net_match_over:
		_check(true, "match ended in the round-1 clash (acceptable at these decks)")
		_finish(_fails)
		return
	print("— round 2: sealed loop continues with flipped initiative")
	_check(int(combat._net_turn_round) == 2, "the clash resolved into round 2")
	_check(int(combat._net_initiative) == 1, "initiative flipped for the new round")
	_check(combat._sealed_bundles.is_empty(), "bundles cleared for the new orders")
	_check(combat._end_turn_btn != null and String(combat._end_turn_btn.text).begins_with("SEAL"),
		"the button is back to SEAL ORDERS")
	# The round-1 clash was real: the lane-0 pair (host creature vs client goblin)
	# must have traded — at least one side of that column took damage or died.
	var host_after = combat._row_array(false, combat.ROW_FRONT)[0]
	var cli_after = combat._row_array(true, combat.ROW_FRONT)[0]
	var traded: bool = (host_after == null or not is_instance_valid(host_after)) \
		or (cli_after == null or not is_instance_valid(cli_after)) \
		or int(combat.player_hp) < host_hp_before \
		or (is_instance_valid(cli_after) and int(cli_after.current_hp) < cli_hp_before)
	_check(traded, "the round-1 clash actually struck (lane-0 trade or face damage)")

	_finish(_fails)


func _finish(code: int) -> void:
	if is_instance_valid(combat):
		combat.queue_free()
	NM.battle_style = NM.STYLE_ALTERNATING
	NM.leave()
	_done = true
	if code == 0:
		print("[sealed] ALL PASS")
	else:
		print("[sealed] %d FAILURES" % code)
	quit(1 if code > 0 else 0)
