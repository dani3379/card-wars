extends SceneTree
## Logs the net turn sequence (who is the active placer, per turn) to expose the
## back-to-back "extra turn" at round boundaries. Fake NET_HOST, no socket: we drive
## _net_finish_placement to end each turn and record _net_active_index.

var SS: Node
var NM: Node
var combat
var _seq: Array = []
var _last := -99


func _initialize(): _run()


func _run() -> void:
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	SS.reset()
	for cid in ["brute","goblin","brute","goblin","brute","goblin","brute","goblin"]:
		SS.add_card_to(0, cid)
	for cid in ["brute","goblin","brute","goblin","brute","goblin","brute","goblin"]:
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear(); NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0   # A = index 0 opens round 1
	root.add_child(combat)
	await create_timer(0.5).timeout
	if combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 10:
		await create_timer(0.2).timeout
		if int(combat._net_turn_round) >= 1:
			break

	# Drive 12 turns: whoever is active ends their turn immediately (no placement).
	for _t in 12:
		var who: int = int(combat._net_active_index)
		var rnd: int = int(combat._net_turn_round)
		_seq.append("R%d:P%d" % [rnd, who])
		await combat._net_finish_placement(who)
		await create_timer(0.15).timeout
		if combat._net_match_over:
			break

	print("[turnorder] sequence: ", " -> ".join(_seq))
	# Flag any back-to-back same-player turns (the "extra turn").
	var doubles := 0
	for i in range(1, _seq.size()):
		var a: String = _seq[i - 1].split(":")[1]
		var b: String = _seq[i].split(":")[1]
		if a == b:
			doubles += 1
	print("[turnorder] back-to-back same-player turns: %d (0 = strict alternation)" % doubles)
	quit()
