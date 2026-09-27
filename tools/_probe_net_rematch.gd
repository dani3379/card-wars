extends SceneTree
## _probe_net_rematch.gd — CAN A PRACTICE MATCH EVER PLAY A SECOND GAME?
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_rematch.gd
##
## The lobby's PRACTICE VS BOT panel offers SINGLE GAME **and BEST OF 3**, and both
## routes end in the same two-sided rematch handshake: each side flags itself, tells
## the peer, and the host relaunches once BOTH flags are up. A drill has no peer.
## `send_to_client` returns early on `not remote_present`, so `_net_rematch_remote`
## could never turn true and the handshake waited forever on an answer that had no
## sender:
##
##   * Bo1 — REMATCH relabelled itself "WAITING FOR OPPONENT…" and stuck there.
##   * Bo3 — game 1 ended, the standing showed, and game 2 never started. No panel,
##           no buttons, nothing to press.
##
## Neither is visible to a probe that stages a board, which is why every existing net
## probe missed it. This one asks the question at the two entry points a player
## actually reaches: the REMATCH button and the between-games interstitial.
##
## THE SIGNAL is `NetMatch._combat_attached`. `launch_combat` → `_enter_combat_local`
## calls `detach_combat()` synchronously on its way into the new scene, so the flag
## going false is unambiguous proof the relaunch fired — and unlike the scene swap
## itself it can be read the instant it happens.

var SS: Node
var NM: Node
var US: Node
var combat: Node

var _started := false
var _done := false
var _fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


## `change_scene_to_file` fires deferred and boots a WHOLE new practice match behind
## us. Left alone it would run through the next phase and stir the shared autoloads,
## so the newborn is put down before the next boot re-seeds them.
func _sweep_newborn() -> void:
	await create_timer(0.4).timeout
	var newborn = root.get_tree().current_scene
	if newborn != null and is_instance_valid(newborn):
		newborn.queue_free()
	await create_timer(0.4).timeout


func _boot(best_of: int) -> bool:
	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "strike", "brute", "goblin",
			"brute", "goblin", "strike"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = 4242
	SS.vs_bot = true
	SS.best_of = best_of
	SS.reset_series()
	NM.is_host = true
	NM.vs_bot = true
	NM.best_of = best_of
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = false     # THE POINT: a drill has no peer to answer
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.battle_style = NM.STYLE_ALTERNATING
	NM.entities.clear()
	NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 10:
		await create_timer(0.25).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	return is_instance_valid(combat)


func _run() -> void:
	print("[rematch] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[rematch] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true

	# ── Bo1: the REMATCH button ──────────────────────────────────────────
	print("\n[rematch] === SINGLE GAME: the REMATCH button ===")
	if not await _boot(1):
		_check(false, "bo1 booted"); _finish(1); return
	_check(SS.vs_bot and not NM.remote_present, "booted as a peerless practice drill")
	_check(NM._combat_attached, "the combat channel is attached before the verdict")
	combat._net_show_result(0)                       # we won; the panel appears
	_check(combat._net_result_panel != null and is_instance_valid(combat._net_result_panel),
		"the result panel was built")
	combat.net._net_request_rematch()
	_check(not NM._combat_attached,
		"pressing REMATCH in a drill actually starts the next game")
	await _sweep_newborn()

	# ── Bo3: the between-games interstitial (no button involved) ──────────
	print("\n[rematch] === BEST OF 3: the between-games roll-on ===")
	if not await _boot(3):
		_check(false, "bo3 booted"); _finish(1); return
	combat._net_show_result(0)                       # game 1 to us; series still live
	_check(SS.series_leader() == -1,
		"after game 1 of 3 the series is still undecided (interstitial path)")
	_check(NM._combat_attached,
		"the interstitial has not relaunched yet — it holds the standing first")
	# The interstitial holds the standing for 2.8s, then drives the handshake itself.
	var waited := 0.0
	while NM._combat_attached and waited < 8.0:
		await create_timer(0.2).timeout
		waited += 0.2
	_check(not NM._combat_attached,
		"a Bo3 drill rolls on into game 2 by itself (waited %.1fs)" % waited)
	await _sweep_newborn()

	print("\n[rematch] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_finish(1 if _fails > 0 else 0)
