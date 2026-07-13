extends Node
## _probe_hand_dim.gd — diagnostic: stages the same fake net host as
## _shot_foe_arsenal, waits for the opening turn, then prints the state that
## decides hand-card brightness (modulate / unplayable veil / affordability
## inputs) plus the resolved combat mood. Windowed (needs the real render path):
##   Godot.exe --path "D:\Godot" res://tools/_probe_hand_dim.tscn

var _combat: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	var SS := get_node("/root/SkirmishState")
	var NM := get_node("/root/NetMatch")
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "strike", "goblin", "strike"]:
		SS.add_card_to(0, cid)
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin", "brute"]:
		SS.add_card_to(1, cid)
	SS.slots[0].relics = ["lantern"]
	SS.slots[0].potions = ["healing"]
	SS.slots[1].relics = ["gravewardens_pact"]
	SS.slots[1].potions = ["inferno_vial"]
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 12345
	NM.is_host = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM.client_peer_id = 0
	NM.entities.clear()
	NM._next_entity_id = 1

	_combat = load("res://scenes/combat.tscn").instantiate()
	_combat._net_first_player_override = 0
	get_tree().root.add_child(_combat)
	await get_tree().create_timer(0.6).timeout
	if _combat._hand.is_empty():
		_combat._net_begin_combat()
	await get_tree().create_timer(3.0).timeout

	print("=== HAND DIM PROBE ===")
	print("hand_interactive=", Card2D.hand_interactive,
		"  board_interactive=", Card2D.board_interactive)
	print("player_mana=", _combat.player_mana, "/", _combat.player_max_mana)
	print("phase=", _combat.phase, "  _net_active_index=", _combat._net_active_index,
		"  local_index=", NM.local_player_index)
	print("resolved_mood=", _combat._resolve_combat_mood(),
		"  node_type='", RunState.current_node_type, "'",
		"  act=", RunState.get_act(),
		"  encounter_id='", RunState.current_encounter_id, "'")
	var stranded := 0
	for card in _combat._hand:
		if card == null or not is_instance_valid(card):
			continue
		var veil_vis := "none"
		if card._unplayable_veil != null and is_instance_valid(card._unplayable_veil):
			veil_vis = str(card._unplayable_veil.visible)
		if card.modulate.a < 0.999:
			stranded += 1
		print("  card=", card.card_id,
			"  cost=", card.card_data.get("cost", "?"),
			"  eff=", _combat._effective_cost(card),
			"  modulate=", card.modulate,
			"  veil=", veil_vis)
	# The regression this probe guards: a hand relayout during the deal window
	# kills the deal-in alpha tween (Card2D.set_hand_target) and the card
	# strands translucent. All hand cards must be fully opaque once settled.
	if stranded > 0:
		print("HAND_DIM_PROBE_FAIL — %d hand card(s) stranded translucent" % stranded)
	else:
		print("HAND_DIM_PROBE_PASS — all hand cards fully opaque")
	print("HAND_DIM_PROBE_DONE")
	get_tree().quit()
