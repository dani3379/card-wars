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


# ── Battle-log inspection helpers (used by _test_net_battle_log) ──────────────
func _collect_richtext(n: Node, out: Array) -> void:
	if n is RichTextLabel:
		out.append(String(n.text))
	for c in n.get_children():
		_collect_richtext(c, out)


func _log_texts() -> Array:
	var out: Array = []
	if combat._battle_log_list == null or not is_instance_valid(combat._battle_log_list):
		return out
	_collect_richtext(combat._battle_log_list, out)
	return out


func _log_has(sub: String) -> bool:
	for t in _log_texts():
		if sub in t:
			return true
	return false


func _clear_log() -> void:
	if combat._battle_log_list == null or not is_instance_valid(combat._battle_log_list):
		return
	for c in combat._battle_log_list.get_children():
		combat._battle_log_list.remove_child(c)
		c.free()
	combat._battle_log_round_marked = -1


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
	# Force host-first so the turn-loop assertions below are deterministic (the live
	# opener is a seed coin flip — exercised on its own in _test_first_player_fairness).
	combat._net_first_player_override = 0
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

	_test_first_player_fairness()
	await _test_opp_mana_seal()
	await _host_plays_a_creature()
	await _test_net_draw_spell()
	await _host_finishes_placing()
	await _client_places_a_creature()
	await _test_host_applies_reposition()
	await _test_net_shove_relocate()
	await _test_net_fx_channel()
	await _client_casts_a_spell()
	await _client_finishes_placing()
	await _test_net_custom_spell_perspective()
	await _test_net_sacrifice_spell()
	await _test_net_targeted_potions()
	await _test_net_client_board_relic()
	await _test_net_worn_spellbook()
	await _test_net_new_board_spells()
	await _test_net_spell_magnitudes()
	await _test_net_temp_state_spells()
	await _test_net_phase_b_spells()
	await _test_net_client_owned_effects()
	await _test_net_clash_replay()
	await _test_net_battle_log()
	await _test_net_one_directional()
	await _test_net_start_of_round_authority()
	await _test_net_summoner_authority()
	await _test_net_last_stand_mirror()
	await _test_net_client_passives()
	_test_match_over()

	# Phase 2: second-player opening hand (pre-deal + going-second card + skip-draw).
	await _test_client_opening_hand()
	# Phase 3: the OTHER half of the engine — the client reconciling host snapshots.
	await _run_client_reconcile_test()
	# Parity: a locally-cast spell recycles into the discard pile too.
	await _test_net_spell_recycle()
	# Caster-local pile spell end-to-end (no UI): Frenzy through the real play path.
	await _test_net_caster_local_turbo()
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
	# Banked carryover (current > max): the seal shows the raw pool, mirroring
	# the player seal — the 2026-07-06 layout-fit pass CUT the "(+N)" annotation
	# (current > max IS the overflow read).
	combat._on_net_intent(2, {"t": NM.EV_HAND_COUNT, "n": 4, "mana": 5, "maxmana": 3})
	await create_timer(0.1).timeout
	_check(combat._net_opp_mana_label.text == "5 / 3",
		"foe seal shows the banked pool '5 / 3' (got '%s')" % combat._net_opp_mana_label.text)


## The opener is a COIN FLIP from the shared seed — never "the host" — and alternates
## each game of a series. Verifies determinism (same seed → same opener), that BOTH
## outcomes are reachable across seeds (so it is NOT always the host), and the per-game
## series alternation. Restores the host-first override + the probe's working seed
## afterward so the downstream turn-loop tests (which assume the host opens) hold.
func _test_first_player_fairness() -> void:
	print("— opener is a seed coin flip (not the host) + alternates per series game")
	combat._net_first_player_override = -1
	var saved_seed: int = int(SS.rng_seed)
	var saved_game: int = int(SS.series_game)
	SS.series_game = 1
	# Determinism: same seed → the same opener every call.
	SS.rng_seed = 12345
	var a: int = int(combat._net_first_player())
	var b: int = int(combat._net_first_player())
	_check(a == b and (a == 0 or a == 1), "opener is deterministic for a fixed seed (got %d)" % a)
	# Both outcomes reachable: scan seeds until we see a host-first AND a client-first.
	var saw0 := false
	var saw1 := false
	for s in range(1, 400):
		SS.rng_seed = s
		if int(combat._net_first_player()) == 0:
			saw0 = true
		else:
			saw1 = true
		if saw0 and saw1:
			break
	_check(saw0 and saw1, "both host-first and client-first occur across seeds (never always the host)")
	# Series alternation: same seed, consecutive games → opposite openers.
	SS.rng_seed = 777
	SS.series_game = 1
	var g1: int = int(combat._net_first_player())
	SS.series_game = 2
	var g2: int = int(combat._net_first_player())
	_check(g1 != g2, "the opener alternates between games of a series (g1=%d g2=%d)" % [g1, g2])
	# Restore host-first determinism + the probe's working seed for the turn-loop tests.
	SS.rng_seed = saved_seed
	SS.series_game = saved_game
	combat._net_first_player_override = 0


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


## Draw/Command channel — HOST side. Quick Shot with no target pings the caster's
## enemy face, but only draws on Slay. (The client-receive draw side is covered in
## the opening-hand test via _on_net_event EV_DRAW.)
func _test_net_draw_spell() -> void:
	print("— host casts quick_shot without a target: face ping, no Slay draw")
	var hand_before: int = combat._hand.size()
	var enemy_face_before: int = int(combat.enemy_hp)
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "quick_shot"}}, -1, 0)
	await create_timer(0.2).timeout
	_check(combat._hand.size() == hand_before,
		"quick_shot without Slay did not draw (%d -> %d)" % [hand_before, combat._hand.size()])
	_check(int(combat.enemy_hp) == enemy_face_before - 1,
		"quick_shot (no target) hit the client face for exactly 1 (%d -> %d)" % [enemy_face_before, int(combat.enemy_hp)])


func _host_finishes_placing() -> void:
	print("— host finishes placing on round 1 (placement only — NO clash yet)")
	var enemy_hp_before: int = int(combat.enemy_hp)
	_check(int(combat._net_turn_round) == 1, "host's opening placement is round 1")
	# DONE finishes the host's placement; with only one side placed, no clash fires —
	# it just passes the placement turn to the client.
	await combat._net_finish_placement(0)
	_check(is_instance_valid(combat), "scene survived the host's DONE")
	# Placement never attacks — the opposing hero must be untouched.
	_check(int(combat.enemy_hp) == enemy_hp_before, "no attack during placement (%d -> %d)" % [enemy_hp_before, int(combat.enemy_hp)])
	_check(int(combat._net_active_index) == 1, "placement passed to the client (active=1)")
	_check(int(combat._net_turn_round) == 1, "still round 1 — the clash waits until BOTH have placed")


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


## The SHOVE spell is a board verb: it must push the struck front-row creature into
## its own back row (the half the net port originally dropped). Verify for BOTH
## caster sides — the target sits on the caster's FOE side, and the relocate must
## land on THAT side, not the caster's.
func _test_net_shove_relocate() -> void:
	print("— shove spell relocates the struck front creature to its own back row (both sides)")
	if combat._net_match_over:
		_check(true, "match already over before shove test (skipped, acceptable)")
		return
	# Host caster (index 0): foe = the client = host's ENEMY side. Target a front-row
	# client creature in a lane whose back slot is empty; it must drop to ROW_BACK.
	combat._row_array(true, combat.ROW_BACK)[3] = null
	var ec = combat._net_spawn_creature(CDB.get_card_data("brute"), 91001, 3, combat.ROW_FRONT, true, false)
	await create_timer(0.15).timeout
	if is_instance_valid(ec):
		ec.card_data["hp"] = 20
		ec.current_hp = 20
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "shove"}}, int(ec.entity_id), 0)
		await create_timer(0.15).timeout
		_check(is_instance_valid(ec) and int(ec.current_row) == combat.ROW_BACK,
			"host's shove pushed the CLIENT front creature to its back row")
		_check(combat._row_array(true, combat.ROW_BACK)[3] == ec,
			"the shoved creature occupies the client back slot (host POV enemy array)")
		_check(combat._row_array(true, combat.ROW_FRONT)[3] == null,
			"the client front slot was vacated by the shove")
		# The board ARRAY can move while the visual node stays stuck in the old cell
		# (the _relocate_creature reparent bug) — assert the actual node re-parented.
		var back_slot3 = combat._slot_array(true, combat.ROW_BACK)[3]
		_check(back_slot3 != null and back_slot3.is_ancestor_of(ec),
			"the shoved creature's VISUAL node re-parented into the back slot (not just the array)")
	# Client caster (index 1): foe = the host = host's PLAYER side. The relocate must
	# land on the player side, proving it keys off the target's side, not the caster's.
	combat._row_array(false, combat.ROW_BACK)[0] = null
	var pc = combat._net_spawn_creature(CDB.get_card_data("brute"), 91002, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.15).timeout
	if is_instance_valid(pc):
		pc.card_data["hp"] = 20
		pc.current_hp = 20
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "shove"}}, int(pc.entity_id), 1)
		await create_timer(0.15).timeout
		_check(is_instance_valid(pc) and int(pc.current_row) == combat.ROW_BACK,
			"client's shove pushed the HOST front creature to its back row")
		_check(combat._row_array(false, combat.ROW_BACK)[0] == pc,
			"the shoved host creature occupies the player back slot (not the caster's side)")


## VFX parity: the host buffers keyword combat callouts (POISON/THORNS/PIERCING) into
## the board snapshot so the client — which never runs the resolver — can replay them
## on the matching creature. Verifies the host enqueues with the right eid/label, the
## sync clears the queue (no double-replay), and the client replay is crash-safe.
func _test_net_fx_channel() -> void:
	print("— keyword-callout FX channel (host buffers → snapshot ships → client replays)")
	if combat._net_match_over:
		_check(true, "match already over before FX test (skipped, acceptable)")
		return
	combat._net_fx_queue.clear()
	var fc = combat._net_spawn_creature(CDB.get_card_data("brute"), 92001, 1, combat.ROW_BACK, true, false)
	await create_timer(0.1).timeout
	if not is_instance_valid(fc):
		_check(false, "spawned a creature to fire a callout on")
		return
	combat.spawn_keyword_callout_kw(fc, "thorns")
	_check(combat._net_fx_queue.size() == 1, "host buffered the THORNS callout into the FX queue")
	if combat._net_fx_queue.size() == 1:
		var e: Dictionary = combat._net_fx_queue[0]
		_check(int(e.get("eid", -1)) == 92001, "the buffered FX carries the creature's entity_id")
		_check(String(e.get("label", "")) == "THORNS", "the buffered FX carries the THORNS label")
	# Battlecry/deathrattle (trigger) callouts ride the SAME channel, by eid.
	combat.spawn_trigger_callout(Vector2(100, 100), "DRAW", false, 92001)
	var found_draw := false
	for fx in combat._net_fx_queue:
		if String((fx as Dictionary).get("label", "")) == "DRAW":
			found_draw = true
	_check(found_draw, "host buffered a battlecry trigger callout (DRAW) into the FX queue by eid")
	combat._net_sync_board()
	_check(combat._net_fx_queue.is_empty(), "the FX queue cleared after the board sync shipped it (no double-replay)")
	# Client replay must tolerate a callout whose creature already died (unknown eid).
	combat._net_replay_fx({"fx": [{"eid": 987654, "label": "GHOST", "col": [1, 0, 0]}]})
	_check(true, "client FX replay tolerated an unknown entity_id without crashing")


## Clash replay channel: the host logs per-strike beats during _net_run_clash
## (lunges, creature hits with authoritative post-mitigation HP, face hits) and
## ships them over EV_CLASH; the client replays them paced, queueing every event
## that lands mid-replay so the outcome can't snap in under the cinematic.
## ALTERNATING battle style is ONE-DIRECTIONAL (2026-07-07): _net_run_clash(side)
## sends only that side's line across the board — the defender takes no swing of its
## OWN (that waits for its turn), and its per-turn states (freeze/stun) survive the
## foe's pass; only the STRIKING side decays. Cross-Blitz mutual trade (2026-07-08):
## a struck LIVE defender fires its ATK straight back at the attacker in the same
## beat, so evenly-matched creatures kill each other — UNLESS the defender is frozen
## or stunned (incapacitated → no counter), which is what makes freeze real tempo.
func _test_net_one_directional() -> void:
	print("— one-directional strike + Cross-Blitz counter (frozen defender can't answer)")
	if combat._net_match_over:
		_check(true, "match over before one-directional test (skipped, acceptable)")
		return
	await _clear_net_board()
	# Brutes are 2/3, so a single strike (2) never one-shots — both bodies survive
	# the frozen pass, leaving a live defender to draw the counter in the second pass.
	var host_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 94001, 1, combat.ROW_FRONT, false, false)
	var client_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 94002, 1, combat.ROW_FRONT, true, false)
	await create_timer(0.15).timeout
	if not is_instance_valid(host_c) or not is_instance_valid(client_c):
		_check(false, "spawned a host + client brute in one lane")
		return
	var host_hp0: int = int(host_c.current_hp)
	var client_hp0: int = int(client_c.current_hp)
	# FROZEN defender: the host's pass damages it, but a frozen body can't counter,
	# and the freeze must SURVIVE (decay is striking-side-only) — a Frost Bolt denies
	# both the foe's next swing AND its counter this turn.
	client_c.state.is_frozen = true
	await combat._net_run_clash(0)   # HOST strikes only
	var client_struck: bool = (not is_instance_valid(client_c)) \
		or int(client_c.current_hp) < client_hp0
	_check(client_struck, "host pass damaged the client creature")
	_check(is_instance_valid(host_c) and int(host_c.current_hp) == host_hp0,
		"a FROZEN defender did NOT counter (host creature untouched)")
	if is_instance_valid(client_c):
		_check(client_c.state.is_frozen,
			"defender's freeze SURVIVED the foe's pass (decays on its own turn)")
		client_c.state.is_frozen = false
	# CROSS-BLITZ MUTUAL TRADE, and the defender's own pass in one: the CLIENT now
	# strikes on its turn — its forward blow bleeds the host creature (proving the
	# one-directional pass), and the host creature (a LIVE, thawed defender) counters
	# straight back, finishing the client attacker.
	if is_instance_valid(client_c) and is_instance_valid(host_c):
		await combat._net_run_clash(1)   # CLIENT strikes only — host defends + counters
		_check((not is_instance_valid(host_c)) or int(host_c.current_hp) < host_hp0,
			"client pass answered on its own turn (host creature struck)")
		_check((not is_instance_valid(client_c)) or int(client_c.current_hp) < client_hp0 - 2,
			"a LIVE defender struck back (Cross-Blitz counter hit the attacker)")
	combat.phase = combat.Phase.PLAYER_TURN


func _test_net_clash_replay() -> void:
	print("— clash replay: host strike log + client paced replay + event backlog")
	if combat._net_match_over:
		_check(true, "match over before clash-replay test (skipped, acceptable)")
		return
	await _clear_net_board()

	# ── HOST: recording captures lunge / hit / face beats with the right shape ──
	combat._net_clash_log.clear()
	combat._net_clash_recording = true
	var atk_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 93001, 0, combat.ROW_FRONT, false, false)
	var def_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 93002, 0, combat.ROW_FRONT, true, false)
	await create_timer(0.15).timeout
	if not is_instance_valid(atk_c) or not is_instance_valid(def_c):
		combat._net_clash_recording = false
		_check(false, "spawned a host attacker + client defender for the log test")
		return
	combat._net_log_lunge(atk_c)
	var hp_before: int = int(def_c.current_hp)
	def_c.current_hp = hp_before - 3   # "post-mitigation" outcome the log must carry
	combat._net_log_hit(atk_c, def_c, hp_before)
	var foe_hp_before: int = int(combat.enemy_hp)
	combat.damage_enemy_hero(2, false)   # face hook logs while recording
	combat._net_clash_recording = false
	_check(combat._net_clash_log.size() == 3, "host logged lunge + creature hit + face hit (3 entries)")
	if combat._net_clash_log.size() == 3:
		var lunge: Dictionary = combat._net_clash_log[0]
		var hit: Dictionary = combat._net_clash_log[1]
		var face: Dictionary = combat._net_clash_log[2]
		_check(int(lunge.get("l", -1)) == 93001, "lunge entry carries the attacker's eid")
		_check(int(hit.get("d", -1)) == 93002 and int(hit.get("n", 0)) == 3 \
				and int(hit.get("hp", -1)) == hp_before - 3 and int(hit.get("a", -1)) == 93001,
			"hit entry carries victim eid + shown damage + authoritative post-hit HP + attacker")
		_check(int(face.get("f", -1)) == 1 and int(face.get("n", 0)) == 2 \
				and int(face.get("fhp", -1)) == foe_hp_before - 2,
			"face entry names the struck owner with amount + resulting HP")
	combat._net_send_clash_log()
	_check(combat._net_clash_log.is_empty(), "send ships + clears the strike log (no double-replay)")

	# ── HOST: the flourish channels — caption, pierce lance, and warden +ATK text ──
	combat._net_clash_recording = true
	combat._net_log_caption("THE DOUBLED HOUR")
	combat._net_log_pierce(atk_c, def_c)
	combat._net_clash_recording = false
	_check(combat._net_clash_log.size() == 2, "host logged the caption + pierce beats")
	if combat._net_clash_log.size() == 2:
		_check(String(combat._net_clash_log[0].get("cap", "")) == "THE DOUBLED HOUR",
			"caption entry carries the phase text")
		_check(int(combat._net_clash_log[1].get("pl", -1)) == 93001 \
				and int(combat._net_clash_log[1].get("pv", -1)) == 93002,
			"pierce entry carries the attacker + victim eids")
	combat._net_clash_log.clear()
	# Warden +ATK rides the fx channel (not the clash log): host-only, anchored by eid.
	combat._net_fx_queue.clear()
	combat._net_fx_text(def_c, "+2 ATK", Color(1.0, 0.62, 0.20))
	_check(combat._net_fx_queue.size() == 1 \
			and int(combat._net_fx_queue[0].get("eid", -1)) == 93002 \
			and String(combat._net_fx_queue[0].get("label", "")) == "+2 ATK",
		"warden +ATK buffers into the fx queue by eid")
	combat._net_fx_queue.clear()

	# ── CLIENT: the replay applies logged HP paced, and queues mid-replay events ──
	var replay_hp: int = int(def_c.current_hp)
	var cap_before: String = String(combat._phase_caption)
	var strikes := [
		{"l": 93001},
		{"cap": "THE DOUBLED HOUR"},
		{"a": 93001, "o": 0, "ahp": int(atk_c.current_hp), "d": 93002, "hp": replay_hp - 3, "n": 3},
		{"pl": 93001, "pv": 93002},
		{"f": 1, "fhp": int(combat.enemy_hp), "n": 2},
	]
	var saved_mode: int = int(combat.combat_mode)
	var bonus_before: int = int(combat._bonus_mana_next_turn)
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	combat._net_replay_clash({"strikes": strikes, "banner": true})   # fire-and-forget
	_check(combat._net_replay_active, "replay marks itself active while animating")
	combat._on_net_event({"t": NM.EV_MANA, "n": 1, "next": true})
	_check(combat._net_event_backlog.size() == 1, "an event landing mid-replay queues in the backlog")
	_check(int(combat._bonus_mana_next_turn) == bonus_before, "the queued event is NOT applied early")
	var spins: int = 0
	while combat._net_replay_active and spins < 100:
		spins += 1
		await create_timer(0.05).timeout
	_check(not combat._net_replay_active, "the replay finished and cleared its active flag")
	_check(is_instance_valid(def_c) and int(def_c.current_hp) == replay_hp - 3,
		"the replay applied the entry's authoritative post-hit HP to the victim")
	_check(String(combat._phase_caption) == "THE DOUBLED HOUR" and cap_before != "THE DOUBLED HOUR",
		"the replay set the mirrored phase caption on the client")
	_check(combat._net_event_backlog.is_empty() and int(combat._bonus_mana_next_turn) == bonus_before + 1,
		"the backlog flushed after the replay (queued event applied)")
	combat.combat_mode = saved_mode
	await _clear_net_board()


## Battle-log PARITY: the client renders combat via replay/snapshot paths (not the
## solo resolver funnels), so every beat it SHOWS must also reach _log_event. Drive
## each client render path with controlled input and assert the chronicle line lands.
func _test_net_battle_log() -> void:
	print("— battle log parity: client logs fields / strikes / face / deaths / status / casts")
	if combat._net_match_over:
		_check(true, "match over before battle-log test (skipped, acceptable)")
		return
	await _clear_net_board()
	var saved_mode: int = int(combat.combat_mode)
	combat.combat_mode = combat.CombatMode.NET_CLIENT

	_check(combat._battle_log_list != null and is_instance_valid(combat._battle_log_list),
		"battle log list built in the combat HUD")

	# ── PLACEMENT — the client's own + the foe's both arrive via _net_spawn_creature ──
	_clear_log()
	var mine_c = combat._net_spawn_creature(CDB.get_card_data("brute"), 95001, 0, combat.ROW_FRONT, false, false)
	_check(_log_has("You field"), "client logs its OWN placement (You field)")
	var foe_c = combat._net_spawn_creature(CDB.get_card_data("goblin"), 95002, 1, combat.ROW_FRONT, true, false)
	_check(_log_has("The foe fields"), "client logs the FOE placement (The foe fields)")

	# A summoned token (eid ≥ the token base) must NOT log a fields line (matches solo).
	_clear_log()
	var _tok = combat._net_spawn_creature(CDB.get_card_data("brute"),
		combat._net_token_id_base() + 7, 2, combat.ROW_FRONT, true, false)
	_check(not _log_has("fields"), "a summoned token does NOT log a fields line")

	# ── STRIKE — the client learns each blow only from the clash replay ──
	_clear_log()
	if is_instance_valid(foe_c) and is_instance_valid(mine_c):
		combat._net_replay_creature_hit({"a": 95001, "o": 0, "ahp": int(mine_c.current_hp),
			"d": 95002, "hp": int(foe_c.current_hp) - 2, "n": 2})
		await create_timer(0.2).timeout
	_check(_log_has("strikes"), "client logs a creature strike from the replay")

	_clear_log()
	if is_instance_valid(foe_c) and is_instance_valid(mine_c):
		combat._net_replay_creature_hit({"a": 95002, "o": 1, "d": 95001,
			"hp": int(mine_c.current_hp) - 1, "n": 1, "ctr": true})
		await create_timer(0.2).timeout
	_check(_log_has("strikes back at"), "a Cross-Blitz counter logs 'strikes back at'")

	# ── FACE — clash face blows come through _net_replay_face_hit ──
	_clear_log()
	combat._net_replay_face_hit(int(NM.local_player_index), int(combat.player_hp) - 3, 3)
	await create_timer(0.2).timeout
	_check(_log_has("You take"), "client logs its own face damage (clash)")
	_clear_log()
	combat._net_replay_face_hit(1 - int(NM.local_player_index), int(combat.enemy_hp) - 2, 2)
	await create_timer(0.2).timeout
	_check(_log_has("The foe takes"), "client logs the foe's face damage (clash)")

	# ── STATUS — keyword callouts replayed via the fx channel ──
	_clear_log()
	combat._net_replay_fx({"fx": [{"eid": 95001, "label": "POISON", "col": [0.5, 0.85, 0.45]}]})
	_check(_log_has("POISON"), "client logs a keyword status from the fx channel")

	# ── SPELLS — foe cast (telegraph) + the local-cast funnel ──
	_clear_log()
	combat._net_spell_telegraph(CDB.get_card_data("strike"), Vector2.ZERO, false, null)
	_check(_log_has("The foe casts"), "client logs the foe's spell cast (telegraph)")
	_clear_log()
	combat._net_log_local_cast(CDB.get_card_data("strike"), null)
	_check(_log_has("You cast"), "the local-cast funnel logs 'You cast'")

	# ── DEATH — the client's deaths flush on the trailing board snapshot ──
	_clear_log()
	# host_hp/client_hp map back to the current hero HP (local_index 0 here) so no face
	# delta noise; an empty creatures list despawns everything still registered.
	combat._net_apply_board_sync({"creatures": [], "host_hp": int(combat.player_hp),
		"client_hp": int(combat.enemy_hp), "active": int(combat._net_active_index)})
	_check(_log_has("falls"), "client logs creature deaths on the board-sync flush")

	combat.combat_mode = saved_mode
	await _clear_net_board()


## Start-of-round keyword ticks (Regenerate / Wither / Doom) are HOST-authoritative
## in net: the client must NOT run dispatch_start_of_round on its own placement turn
## (its _start_round is non-authoritative) or it double-applies the effect. Verify the
## _is_client() gate skips the tick, the host runs it, and the doom counter — which
## isn't reconstructable from hp/atk — reaches the client via the board snapshot.
func _test_net_start_of_round_authority() -> void:
	print("— start-of-round authority: client doesn't double-tick regen/wither/doom; doom counter syncs")
	if combat._net_match_over:
		_check(true, "match over before start-of-round test (skipped, acceptable)")
		return
	await _clear_net_board()
	var KE = root.get_node_or_null("KeywordEffects")

	var regen = combat._net_spawn_creature({"id": "troll", "name": "Troll", "type": "creature",
		"atk": 2, "hp": 4, "keywords": ["regenerate"]}, 95001, 0, combat.ROW_FRONT, false, false)
	var bomb = combat._net_spawn_creature({"id": "cinder_pup", "name": "Cinder Pup", "type": "creature",
		"atk": 2, "hp": 1, "keywords": ["doom"], "doom": 2}, 95002, 1, combat.ROW_FRONT, false, false)
	await create_timer(0.15).timeout
	if not is_instance_valid(regen) or not is_instance_valid(bomb):
		_check(false, "spawned a regen creature + a doom bomb")
		return
	regen.current_hp = 2   # damaged so Regenerate has room to heal
	bomb._ensure_doom_init()
	var saved_mode: int = int(combat.combat_mode)

	# HOST authority: the guard runs the tick.
	combat.combat_mode = combat.CombatMode.NET_HOST
	_check(not combat._is_client(), "net host is NOT the client (guard runs the tick)")
	KE.dispatch_start_of_round(combat)
	_check(int(regen.current_hp) == 3, "host: Regenerate healed the damaged troll +1 (2 -> 3)")
	_check(int(bomb.doom_counter) == 1, "host: Doom counter ticked 2 -> 1")

	# CLIENT: the exact _start_round gate (_is_client()) skips the local tick.
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	_check(combat._is_client(), "net client IS the client (guard skips the local tick)")
	var hp_pre: int = int(regen.current_hp)
	var doom_pre: int = int(bomb.doom_counter)
	if not combat._is_client():   # mirror _start_round's guard verbatim
		KE.dispatch_start_of_round(combat)
	_check(int(regen.current_hp) == hp_pre, "client: Regenerate did NOT tick locally (no double-heal)")
	_check(int(bomb.doom_counter) == doom_pre, "client: Doom did NOT tick locally (no counter drift)")

	# The doom counter reaches the client via the snapshot instead of a local tick.
	bomb.doom_counter = 5
	combat._net_update_creature(bomb, {"doom": 2})
	_check(int(bomb.doom_counter) == 2, "client applies the host's synced doom counter (5 -> 2)")

	combat.combat_mode = saved_mode
	await _clear_net_board()


## SUMMONER PHANTOM: the summon_each_round passive calls summon_token(), which
## instantiates a REAL local Card2D node. If the client runs _apply_start_round_passives
## on its own placement turn it musters a phantom the host never registers — and the
## board-sync reconcile only despawns REGISTERED entities, so the phantom is permanent
## and accumulates one per round. Verify the host musters and the client's guard skips.
func _test_net_summoner_authority() -> void:
	print("— summoner authority: client doesn't locally muster a phantom token")
	if combat._net_match_over:
		_check(true, "match over before summoner test (skipped, acceptable)")
		return
	await _clear_net_board()

	var summoner = combat._net_spawn_creature({"id": "summoner", "name": "Summoner",
		"type": "creature", "atk": 1, "hp": 4, "keywords": ["guardian"],
		"passive": "summon_each_round"}, 95101, 1, combat.ROW_FRONT, false, false)
	await create_timer(0.15).timeout
	if not is_instance_valid(summoner):
		_check(false, "spawned a Summoner")
		return
	var saved_mode: int = int(combat.combat_mode)

	# HOST authority: the passive musters a token in an adjacent empty column.
	combat.combat_mode = combat.CombatMode.NET_HOST
	var host_pre: int = combat._all_friendly(false).size()
	combat._apply_start_round_passives(false)
	var host_post: int = combat._all_friendly(false).size()
	_check(host_post == host_pre + 1, "host: Summoner mustered a token (%d -> %d)" % [host_pre, host_post])

	# CLIENT: the exact _start_round gate (_is_client()) skips the local muster, so no
	# phantom is created — the real token arrives via the host's snapshot instead.
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	var cli_pre: int = combat._all_friendly(false).size()
	if not combat._is_client():   # mirror _start_round's guard verbatim
		combat._apply_start_round_passives(false)
	var cli_post: int = combat._all_friendly(false).size()
	_check(cli_post == cli_pre, "client: no phantom token mustered (%d -> %d)" % [cli_pre, cli_post])

	combat.combat_mode = saved_mode
	await _clear_net_board()


## LAST STAND MIRROR: the chip + overbright flare fire inside Card2D.take_damage —
## which only ever runs on the HOST — so the client used to see the survivor snap to
## 1 HP with no ceremony. Verify the flare site ships an eid-anchored "LAST STAND"
## fx entry (via the Card2D.net_last_stand_cb hook _net_begin_combat installs) and
## the client replay runs the flare on the matching node, crash-safe on a dead eid.
func _test_net_last_stand_mirror() -> void:
	print("— last stand mirror: host ships the save; client replays chip + flare")
	if combat._net_match_over:
		_check(true, "match over before last-stand test (skipped, acceptable)")
		return
	await _clear_net_board()

	var survivor = combat._net_spawn_creature({"id": "paladin", "name": "Paladin",
		"type": "creature", "atk": 2, "hp": 4, "keywords": ["last_stand"]},
		95201, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.15).timeout
	if not is_instance_valid(survivor):
		_check(false, "spawned a Last Stand survivor")
		return
	var saved_mode: int = int(combat.combat_mode)

	# HOST: take_damage's flare site fires the static hook -> eid-anchored fx entry.
	# (Static accessed via the instance — naming Card2D at parse time force-compiles
	# it before autoloads exist under --script, breaking the whole probe load.)
	combat.combat_mode = combat.CombatMode.NET_HOST
	_check(survivor.net_last_stand_cb.is_valid(), "host installed the Last Stand mirror hook")
	combat._net_fx_queue.clear()
	survivor.take_damage(999)
	_check(int(survivor.current_hp) == 1 and survivor.last_stand_used,
		"Last Stand saved the creature at 1 HP")
	var ls_found := false
	for fx in combat._net_fx_queue:
		if int(fx.get("eid", -1)) == 95201 and String(fx.get("label", "")) == "LAST STAND":
			ls_found = true
	_check(ls_found, "host buffered the LAST STAND fx entry for the survivor's eid")

	# CLIENT: the replay special-case runs the flare on the matching node (the flare
	# centers pivot_offset — observable headless) and skips a dead eid crash-free.
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	survivor.pivot_offset = Vector2.ZERO
	combat._net_replay_fx({"fx": [{"eid": 95201, "label": "LAST STAND", "col": [1.0, 0.85, 0.2]}]})
	_check(survivor.pivot_offset == survivor.size * 0.5,
		"client replay ran the flare on the survivor (pivot centered)")
	combat._net_replay_fx({"fx": [{"eid": 999999, "label": "LAST STAND", "col": [1, 1, 1]}]})
	_check(true, "client replay crash-safe on an unknown eid")

	combat.combat_mode = saved_mode
	combat._net_fx_queue.clear()
	await _clear_net_board()


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


func _client_finishes_placing() -> void:
	print("— client finishes placing → the SIMULTANEOUS clash fires (both boards)")
	# The client's end-of-actions intent routes to _net_finish_placement(1); with both
	# sides now placed, the host runs the simultaneous clash. Call it directly to await.
	await combat._net_finish_placement(1)
	# The clash awaits internally; give it room to resolve + advance the round.
	for _i in 12:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat) or int(combat._net_turn_round) >= 2 or combat._net_match_over:
			break
	_check(is_instance_valid(combat), "scene survived the simultaneous clash")
	if is_instance_valid(combat) and not combat._net_match_over:
		_check(int(combat._net_turn_round) == 2, "clash resolved → round advanced to 2")
		# Strict alternation (2026-07-08): the fixed opener opens EVERY round (P0,P1,P0,P1),
		# so with round 1 opened by host (0) round 2 opens host (0) again — not the alternate.
		_check(int(combat._net_active_index) == 0, "round 2 opens for the fixed opener (active=0)")


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


## Targeted + board potions (2026-07-09): the host-authoritative resolvers must
## hit the right creatures. Mirrors the offering test's direct-resolver approach —
## the entity_id wire handoff is the same one the proven spell tests already use.
func _test_net_targeted_potions() -> void:
	print("— targeted potions: War Paint friendly buff, Sapper's Charge column strike")
	if combat._net_match_over:
		_check(true, "match already over before potion test (skipped, acceptable)")
		return
	# War Paint (grant_rampage) on a host friendly — Rampage keyword + +1 ATK.
	var wp = combat._net_spawn_creature(CDB.get_card_data("brute"), 90050, 1, combat.ROW_BACK, false, false)
	await create_timer(0.2).timeout
	if is_instance_valid(wp):
		var atk_before: int = int(wp.effective_atk())
		combat._net_apply_host_potion("war_paint", false, wp)
		await create_timer(0.15).timeout
		_check(wp.has_keyword("rampage"), "War Paint granted Rampage to the target friendly")
		_check(int(wp.effective_atk()) == atk_before + 1,
			"War Paint added +1 ATK (%d -> %d)" % [atk_before, int(wp.effective_atk())])
	# Sapper's Charge (column_strike) on an enemy creature + its lane-mate: both take 4.
	var scf = combat._net_spawn_creature(CDB.get_card_data("brute"), 90051, 3, combat.ROW_FRONT, true, false)
	var scb = combat._net_spawn_creature(CDB.get_card_data("brute"), 90052, 3, combat.ROW_BACK, true, false)
	await create_timer(0.2).timeout
	if is_instance_valid(scf) and is_instance_valid(scb):
		scf.card_data["hp"] = 12; scf.current_hp = 12
		scb.card_data["hp"] = 12; scb.current_hp = 12
		combat._net_apply_host_potion("bottled_fury", false, scf)
		await create_timer(0.15).timeout
		_check(is_instance_valid(scf) and int(scf.current_hp) == 8,
			"Sapper's Charge hit the target enemy for 4 (12 -> 8)")
		_check(is_instance_valid(scb) and int(scb.current_hp) == 8,
			"Sapper's Charge hit the enemy lane-mate for 4 (12 -> 8)")
	# Self-contained: clear the spawned creatures so later board-sum tests
	# (Crossfire) aren't polluted by leftover bodies.
	for n in [wp, scf, scb]:
		if is_instance_valid(n):
			n.current_hp = 0
	combat._cleanup_dead()
	await create_timer(0.15).timeout


## Client-owned BOARD relic (Gravewarden's Pact, 2026-07-09): a client creature's
## death must rebirth a 1/1 Imp on the CLIENT's side, driven host-authoritatively by
## _relic_active_for_side reading slot 1. Proves the board-relic pattern over the wire.
func _test_net_client_board_relic() -> void:
	print("— client-owned board relic: Gravewarden's Pact rebirths on a client death")
	if combat._net_match_over:
		_check(true, "match already over before board-relic test (skipped, acceptable)")
		return
	var slot1 = SS.get_slot(1)
	if slot1 == null:
		_check(false, "client slot exists")
		return
	if not slot1.relics.has("gravewardens_pact"):
		slot1.relics.append("gravewardens_pact")
	# _relic_active_for_side must read slot 1 for the client, and reject the host slot.
	_check(combat._relic_active_for_side(true, "gravewardens_pact"),
		"_relic_active_for_side(client) sees the client's Pact")
	_check(not combat._relic_active_for_side(false, "gravewardens_pact"),
		"_relic_active_for_side(host) does NOT see the client's Pact")
	# Seat a client (enemy-side) creature, vacate its slot like the death pipeline
	# does (arrays null before the death hooks), then run the per-side death payoff.
	var victim = combat._net_spawn_creature(CDB.get_card_data("brute"), 90060, 0, combat.ROW_FRONT, true, false)
	await create_timer(0.2).timeout
	if not is_instance_valid(victim):
		_check(false, "seated a client creature to kill")
		return
	combat._enemy_field[0] = null
	combat._gravewardens_rebirths[1] = 0
	var before: int = combat._net_side_creatures(true).size()
	combat._apply_ally_death_passives(true, victim)
	await create_timer(0.2).timeout
	var after: int = combat._net_side_creatures(true).size()
	_check(after > before, "a reborn Imp appeared on the CLIENT's side (%d -> %d)" % [before, after])
	# Cleanup: drop the reborn Imp + the orphaned victim so later tests see a clean board.
	var imp = combat._enemy_field[0]
	if imp != null and is_instance_valid(imp):
		imp.current_hp = 0
	combat._cleanup_dead()
	if is_instance_valid(victim):
		victim.queue_free()
	await create_timer(0.1).timeout


## Worn Spellbook (board relic, 2026-07-09): the CASTER's damage spells deal +1,
## host-authoritative and per-side (gated by _relic_active_for_side). Covers a
## built-in damage type and a custom damage spell, and proves the host (no book)
## still deals base — so the relic is owner-scoped, not global.
func _test_net_worn_spellbook() -> void:
	print("— Worn Spellbook (board relic): the caster's damage spells deal +1")
	if combat._net_match_over:
		_check(true, "match already over before spellbook test (skipped, acceptable)")
		return
	var slot1 = SS.get_slot(1)
	if slot1 == null:
		_check(false, "client slot exists")
		return
	if not slot1.relics.has("worn_spellbook"):
		slot1.relics.append("worn_spellbook")
	# Built-in damage spell (value 3) cast by the CLIENT → target takes 4 (3 + book).
	var t1 = combat._net_spawn_creature(CDB.get_card_data("brute"), 90070, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.2).timeout
	if is_instance_valid(t1):
		t1.card_data["hp"] = 20
		t1.current_hp = 20
		combat._net_resolve_spell({"spell": {"type": "damage", "value": 3}}, int(t1.entity_id), 1)
		await create_timer(0.15).timeout
		_check(is_instance_valid(t1) and int(t1.current_hp) == 16,
			"built-in damage spell +1 from Worn Spellbook (20 -> 16)")
	# Custom damage spell (Smite, 6 base) cast by the CLIENT → 7 with the book.
	var t2 = combat._net_spawn_creature(CDB.get_card_data("brute"), 90071, 1, combat.ROW_FRONT, false, false)
	await create_timer(0.2).timeout
	if is_instance_valid(t2):
		t2.card_data["hp"] = 20
		t2.current_hp = 20
		combat._net_resolve_custom_spell("smite_spell", t2, true, {})
		await create_timer(0.15).timeout
		_check(is_instance_valid(t2) and int(t2.current_hp) == 13,
			"custom damage spell (Smite 6+1) from Worn Spellbook (20 -> 13)")
	# Per-side gating: the HOST has no book, so its Smite deals base 6.
	var t3 = combat._net_spawn_creature(CDB.get_card_data("brute"), 90072, 2, combat.ROW_FRONT, true, false)
	await create_timer(0.2).timeout
	if is_instance_valid(t3):
		t3.card_data["hp"] = 20
		t3.current_hp = 20
		combat._net_resolve_custom_spell("smite_spell", t3, false, {})
		await create_timer(0.15).timeout
		_check(is_instance_valid(t3) and int(t3.current_hp) == 14,
			"host (no Worn Spellbook) deals base Smite 6 (20 -> 14)")
	for n in [t1, t2, t3]:
		if is_instance_valid(n):
			n.current_hp = 0
	combat._cleanup_dead()
	# Test isolation: disarm the book, or every later client-cast damage spell
	# (e.g. the Crossfire magnitude check) reads +1 and fails mysteriously.
	slot1.relics.erase("worn_spellbook")
	await create_timer(0.1).timeout


## The newly-ported board/utility spells (holy_smite / ricochet / provision /
## adrenaline / bloodletting): each must resolve with the right perspective using
## the net primitives. Self-contained — spawns its own creatures with bumped HP so
## the damage reads are exact regardless of leftover board clutter.
func _test_net_new_board_spells() -> void:
	print("— newly-ported skirmish spells: holy_smite / ricochet / provision / adrenaline / bloodletting")
	if combat._net_match_over:
		_check(true, "match already over before new-spell test (skipped, acceptable)")
		return
	# holy_smite (client caster): floor-3 hit on a full-HP target.
	var hs = combat._net_spawn_creature(CDB.get_card_data("brute"), 90010, 0, combat.ROW_FRONT, false, false)
	await create_timer(0.15).timeout
	if is_instance_valid(hs):
		hs.card_data["hp"] = 12
		hs.current_hp = 12
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "holy_smite"}}, int(hs.entity_id), 1)
		await create_timer(0.15).timeout
		_check(is_instance_valid(hs) and int(hs.current_hp) == 9,
			"holy_smite dealt its floor-3 hit to the caster's foe (12 -> 9)")
	# Crossfire / ricochet (client caster): hits the caster's back-row foes.
	var rc = combat._net_spawn_creature(CDB.get_card_data("brute"), 90011, 2, combat.ROW_BACK, false, false)
	await create_timer(0.15).timeout
	if is_instance_valid(rc):
		rc.card_data["hp"] = 30
		rc.current_hp = 30
		var sum_before := 0
		for c in combat._all_player_creatures():
			sum_before += int(c.current_hp)
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "ricochet"}}, -1, 1)
		await create_timer(0.15).timeout
		var sum_after := 0
		for c in combat._all_player_creatures():
			sum_after += int(c.current_hp)
		_check(sum_before - sum_after == 2, "Crossfire removed 2 HP from the caster's back-row foe (%d -> %d)" % [sum_before, sum_after])
	# provision (client caster): a 2/1 token lands on the client's side (host POV enemy).
	var enemy_before: int = combat._all_enemy_creatures().size()
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "provision"}}, -1, 1)
	await create_timer(0.15).timeout
	var enemy_after: Array = combat._all_enemy_creatures()
	_check(enemy_after.size() == enemy_before + 1, "provision mustered a body on the caster's (client) side")
	var has_token := false
	for c in enemy_after:
		if bool(c.is_token):
			has_token = true
	_check(has_token, "the mustered body is a token (2/1 soldier)")
	# adrenaline / Second Wind (host caster): +2 Command and +1 card into the host's own hand.
	combat._player_draw_pile.append(combat._pile_entry("goblin", 998877))   # guarantee a draw
	var mana0: int = int(combat.player_mana)
	var hand0: int = combat._hand.size()
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "adrenaline"}}, -1, 0)
	await create_timer(0.15).timeout
	_check(int(combat.player_mana) == mana0 + 2, "adrenaline gave the host caster +2 Command")
	_check(combat._hand.size() == hand0 + 1, "adrenaline drew the host caster a card")
	# bloodletting (host caster): -1 own face, +2 Command.
	var face0: int = int(combat.player_hp)
	var mana1: int = int(combat.player_mana)
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "bloodletting"}}, -1, 0)
	await create_timer(0.15).timeout
	_check(int(combat.player_hp) == face0 - 1, "bloodletting cost the host caster 1 HP")
	_check(int(combat.player_mana) == mana1 + 2, "bloodletting gave the host caster +2 Command")


## Spell MAGNITUDE parity: the net resolver must deal the SAME numbers as solo / the
## card desc. These diverged in older builds: blood_tithe dealt 3/2 while the desc
## then read 4/1, and patch_up's draw was gated on a full-HP rider solo had removed.
## This locks the CURRENT desc values in (blood_tithe reads "Take 2 damage yourself"
## today — desc, solo and net all agree on 4 enemy / 2 self).
func _test_net_spell_magnitudes() -> void:
	print("— spell magnitude parity: blood_tithe (4 enemy / 2 self) + patch_up (heal + draw)")
	if combat._net_match_over:
		_check(true, "match over before magnitude test (skipped, acceptable)")
		return
	# blood_tithe (host caster, no target): 4 to the client face, 2 to the host's own face.
	var ef0: int = int(combat.enemy_hp)
	var pf0: int = int(combat.player_hp)
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "blood_tithe"}}, -1, 0)
	await create_timer(0.12).timeout
	_check(int(combat.enemy_hp) == ef0 - 4, "blood_tithe dealt 4 to the enemy face per its desc (%d -> %d)" % [ef0, int(combat.enemy_hp)])
	_check(int(combat.player_hp) == pf0 - 2, "blood_tithe cost the caster exactly 2 per its desc (%d -> %d)" % [pf0, int(combat.player_hp)])
	# patch_up (Field Surgery): FULL heal + the patient sits the round out
	# (stunned) + a draw — the cantrip rider RETURNED in the 2026-07-07 buff
	# pass (unconditional this time, not the old full-HP-gated version).
	var pu = combat._net_spawn_creature(CDB.get_card_data("brute"), 93001, 2, combat.ROW_BACK, false, false)
	await create_timer(0.1).timeout
	if is_instance_valid(pu):
		pu.card_data["hp"] = 10
		pu.current_hp = 5
		var hand_pu: int = combat._hand.size()
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "patch_up"}}, int(pu.entity_id), 0)
		await create_timer(0.12).timeout
		_check(int(pu.current_hp) == 10, "Field Surgery fully healed the target (5 -> 10)")
		_check(bool(pu.state.stunned), "Field Surgery stunned the patient for the round")
		_check(combat._hand.size() == hand_pu + 1, "Field Surgery drew 1 for the caster (cantrip rider)")
		# Self-contained cleanup: leave the board as we found it for later tests.
		combat._row_array(false, combat.ROW_BACK)[2] = null
		NM.unregister_entity(93001)
		pu.queue_free()
		await create_timer(0.05).timeout


## Temp-state spells (freeze / stun / poison / charge / shield) + their net decay.
## Host is the caster (index 0 = player side); the client's creatures sit on the
## host's enemy side. Verifies: the resolvers set the right CreatureInstance flags,
## _net_premark_skip_attack benches stunned/frozen on the active side, and
## _net_decay_side_states clears each side's per-turn states.
func _test_net_temp_state_spells() -> void:
	print("— temp-state spells: frost_bolt / time_snare / venom_tip / charge / hoarfrost + decay")
	if combat._net_match_over:
		_check(true, "match already over before temp-state test (skipped, acceptable)")
		return
	# Enemy (client) creatures on the host's enemy side, lanes 1 & 2.
	var ea = combat._net_spawn_creature(CDB.get_card_data("brute"), 90030, 1, combat.ROW_FRONT, true, false)
	var eb = combat._net_spawn_creature(CDB.get_card_data("brute"), 90031, 2, combat.ROW_FRONT, true, false)
	# Friendly (host) creature opposite ea (lane 1) for venom/charge/hoarfrost.
	var fr = combat._net_spawn_creature(CDB.get_card_data("brute"), 90032, 1, combat.ROW_FRONT, false, false)
	await create_timer(0.2).timeout
	if not (is_instance_valid(ea) and is_instance_valid(eb) and is_instance_valid(fr)):
		_check(false, "spawned the temp-state test creatures")
		return
	# frost_bolt (host caster) on an enemy creature → it freezes.
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "frost_bolt"}}, int(ea.entity_id), 0)
	_check(ea.state.is_frozen, "frost_bolt froze the targeted enemy creature")
	# doubled_hour (time_snare's 2026-07-02 redesign, host caster) → arms the
	# caster side's attack-twice flag (decays with the side's states below).
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "doubled_hour"}}, -1, 0)
	_check(combat._doubled_hour[0], "doubled_hour armed the caster side's attack-twice flag")
	# rout (overwhelming_force's redesign, host caster) → the caster's foes are
	# driven to their back row and stunned.
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "rout"}}, -1, 0)
	_check(ea.state.stunned and eb.state.stunned, "rout stunned all of the caster's foes")
	_check(int(eb.current_row) == int(combat.ROW_BACK), "rout drove a front foe into its back row")
	# venom_tip (host caster) on a friendly → it gains the poison keyword + temp tag.
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "venom_tip"}}, int(fr.entity_id), 0)
	_check(fr.card_data.keywords.has("poison") and fr.get_meta("temp_poison", false),
		"venom_tip gave the friendly Poison for the round")
	# charge_spell (host caster) on the friendly → charges_this_turn rider.
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "charge_spell"}}, int(fr.entity_id), 0)
	_check(fr.get_meta("charges_this_turn", false), "charge_spell armed the friendly's multi-strike")
	# hoarfrost (host caster) on the friendly → friendly shielded, opposing enemy frozen.
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "hoarfrost"}}, int(fr.entity_id), 0)
	_check(fr.state.has_shield, "hoarfrost shielded the friendly")
	_check(ea.state.is_frozen, "hoarfrost froze the enemy opposing the friendly's lane")
	# Pre-mark: the enemy side is about to attack — stunned/frozen forfeit the swing.
	for c in [ea, eb]:
		c.has_attacked_this_turn = false
	combat._net_premark_skip_attack(true)
	_check(ea.has_attacked_this_turn and eb.has_attacked_this_turn,
		"_net_premark_skip_attack benched the stunned/frozen enemy creatures")
	# Decay the enemy side → stun/freeze clear (so they swing again next turn).
	combat._net_decay_side_states(true)
	_check(not ea.state.is_frozen and not ea.state.stunned and not eb.state.stunned,
		"decay cleared the enemy side's stun/freeze")
	# Decay the host side → the friendly's temp Poison + charge rider clear,
	# and the round-scoped Doubled Hour flag rests with them.
	combat._net_decay_side_states(false)
	_check(not fr.card_data.keywords.has("poison") and not fr.has_meta("charges_this_turn"),
		"decay stripped the friendly's temp Poison + charge rider")
	_check(not combat._doubled_hour[0], "decay cleared the caster side's Doubled Hour flag")
	# Shield is NOT a per-turn state — it must survive the decay (consumed on hit).
	_check(fr.state.has_shield, "decay left the friendly's Shield intact (not a per-turn state)")
	# Clean up so the match-over test board stays predictable.
	for c in [ea, eb, fr]:
		if is_instance_valid(c):
			combat._net_despawn_creature(c)


## Phase B — grave / exile / pile spells (host-authoritative parts). Host is the
## caster (index 0 = player side). Clears the board first so summon-slot counts are
## exact. The caster-LOCAL picker spells (scrap/recycle/gambit/turbo) need modal UI
## the headless harness can't drive, so this verifies the host-side board math:
## banish exile, per-side grave recording, reanimate, grave robbery/pact return-to-
## hand, echo re-resolution, and the war_chant/mass_grave board consequences.
func _test_net_phase_b_spells() -> void:
	print("— Phase B spells: banish / reanimate / grave_robbery / grave_pact / echo / war_chant / mass_grave")
	if combat._net_match_over:
		_check(true, "match already over before Phase-B test (skipped, acceptable)")
		return
	# Clean slate: pull every creature off the board WITHOUT routing through death
	# (so no stray graves), giving the summon tests room and exact counts.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			for is_e in [false, true]:
				for r in [combat.ROW_FRONT, combat.ROW_BACK]:
					var arr = combat._row_array(is_e, r)
					for ln in range(combat.LANES_PER_ROW):
						if arr[ln] == c:
							arr[ln] = null
			c.queue_free()
	await create_timer(0.2).timeout

	# ── banish: exile an enemy creature (freed + exile signal, no discard) ──
	var bz = combat._net_spawn_creature(CDB.get_card_data("brute"), 70001, 0, combat.ROW_BACK, true, false)
	await create_timer(0.12).timeout
	if is_instance_valid(bz):
		var bz_eid: int = int(bz.entity_id)
		combat._net_exiled_eids.clear()
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "banish"}}, bz_eid, 0)
		await create_timer(0.12).timeout
		_check(not is_instance_valid(bz), "banish removed the target from the game")
		_check(combat._net_exiled_eids.has(bz_eid), "banish stamped the exile signal so the client won't recycle it")

	# ── a host-side death records the per-side grave ──
	var gv = combat._net_spawn_creature(CDB.get_card_data("goblin"), 70002, 1, combat.ROW_BACK, false, false)
	await create_timer(0.12).timeout
	if is_instance_valid(gv):
		gv.take_damage(999)
		combat._cleanup_dead()
		await create_timer(0.12).timeout
		_check(not combat._net_last_dead[0].is_empty() and String(combat._net_last_dead[0].get("id", "")) == "goblin",
			"a host-side death recorded the per-side grave (last dead = goblin)")

	# ── reanimate: raise the host's last corpse as a 1/1 keeping its keywords ──
	combat._net_last_dead[0] = {"id": "brute", "uid": -1,
		"data": {"id": "brute", "name": "Brute", "keywords": ["swift"]}}
	var pc_before: int = combat._all_player_creatures().size()
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "reanimate"}}, -1, 0)
	await create_timer(0.12).timeout
	var revived_ok := false
	for c in combat._all_player_creatures():
		if c.is_token and c.card_data.get("keywords", []).has("swift"):
			revived_ok = true
	_check(combat._all_player_creatures().size() == pc_before + 1, "reanimate summoned a body on the caster's side")
	_check(revived_ok, "the revived token kept the corpse's keywords (swift)")

	# ── grave_robbery: float the host's last REAL corpse back to hand ──
	combat._net_last_dead[0] = {"id": "goblin", "uid": 444555, "data": CDB.get_card_data("goblin")}
	var hand_gr: int = combat._hand.size()
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "grave_robbery"}}, -1, 0)
	await create_timer(0.12).timeout
	_check(combat._hand.size() == hand_gr + 1, "grave_robbery returned the corpse to the caster's hand")

	# ── last_rites (was grave_pact): caster-side morbid bolt, 3 or 6 once a
	# friendly has fallen this fight. The 2026-07-02 overhaul retired the old
	# pile-return `_net_grave_pact` arming — this is a clean damage spell now. ──
	var lr = combat._net_spawn_creature(CDB.get_card_data("brute"), 70003, 2, combat.ROW_BACK, true, false)
	await create_timer(0.12).timeout
	if is_instance_valid(lr):
		lr.card_data["hp"] = 30
		lr.current_hp = 30
		var lr_expected: int = 6 if combat._friendly_deaths_this_fight > 0 else 3
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "last_rites"}}, int(lr.entity_id), 0)
		await create_timer(0.12).timeout
		_check(is_instance_valid(lr) and int(lr.current_hp) == 30 - lr_expected,
			"last_rites dealt its morbid bolt (%d) caster-side" % lr_expected)

	# ── echo_spell: re-resolve the last host spell (a 3-damage strike) ──
	var ec = combat._net_spawn_creature(CDB.get_card_data("brute"), 70004, 3, combat.ROW_FRONT, true, false)
	await create_timer(0.12).timeout
	if is_instance_valid(ec):
		ec.card_data["hp"] = 30
		ec.current_hp = 30
		combat._net_resolve_spell({"spell": {"type": "damage", "value": 3}}, int(ec.entity_id), 0)
		var hp_first: int = int(ec.current_hp)
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "echo_spell"}}, -1, 0)
		await create_timer(0.12).timeout
		_check(is_instance_valid(ec) and int(ec.current_hp) == hp_first - 3,
			"echo re-resolved the last spell (another 3 damage)")

	# ── war_chant: one Soldier per pitched card (forwarded as _net_picks) ──
	var wc_before: int = combat._all_player_creatures().size()
	combat._net_resolve_spell({"spell": {"type": "custom", "id": "war_chant"}, "_net_picks": 2}, -1, 0)
	await create_timer(0.12).timeout
	_check(combat._all_player_creatures().size() == wc_before + 2, "war_chant mustered 2 Soldiers from 2 pitched cards")

	# ── mass_grave: damage caster foes by discard size (forwarded as _net_picks) ──
	var mg = combat._net_spawn_creature(CDB.get_card_data("brute"), 70005, 0, combat.ROW_FRONT, true, false)
	await create_timer(0.12).timeout
	if is_instance_valid(mg):
		mg.card_data["hp"] = 30
		mg.current_hp = 30
		combat._net_resolve_spell({"spell": {"type": "custom", "id": "mass_grave"}, "_net_picks": 4}, -1, 0)
		await create_timer(0.12).timeout
		_check(is_instance_valid(mg) and int(mg.current_hp) == 26, "mass_grave hit the caster's foe for discard-size (4)")


## Player-2 parity for the 6 client-owned creature effects that solo only ran for the
## player side. The host resolves a CLIENT creature with is_enemy=true; verify each
## reaches the right owner: Doppelganger (per-side grave), Adaptable + Copycat (the
## EV_CHOICE → IN_CHOICE pick), Chaos Imp (perspective auto-target), Griffin (return-
## to-caster + once-guard), Mourner (next-turn Command via EV_MANA next=true).
func _test_net_client_owned_effects() -> void:
	print("— client-owned effects: doppelganger / adaptable / copycat / chaos_imp / griffin / mourner")
	if combat._net_match_over:
		_check(true, "match over before client-effect test (skipped, acceptable)")
		return
	combat._net_active_index = 1   # the client's turn (the host validates client effects)

	# Clean slate so target/owner reads are exact.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			for is_e in [false, true]:
				for r in [combat.ROW_FRONT, combat.ROW_BACK]:
					var arr = combat._row_array(is_e, r)
					for ln in range(combat.LANES_PER_ROW):
						if arr[ln] == c:
							arr[ln] = null
			c.queue_free()
	await create_timer(0.15).timeout

	# ── doppelganger (client): copies the CLIENT's per-side grave, NOT the host's ──
	combat._net_last_dead[1] = {"id": "brute", "uid": -1, "data":
		{"id": "brute", "name": "Brute", "type": "creature", "atk": 7, "hp": 7, "keywords": ["swift"]}}
	combat._net_last_dead[0] = {"id": "goblin", "uid": -1, "data":
		{"id": "goblin", "name": "Goblin", "type": "creature", "atk": 1, "hp": 1, "keywords": []}}
	var dop = combat._net_spawn_creature(CDB.get_card_data("doppelganger"), 80001, 0, combat.ROW_FRONT, true, true)
	await create_timer(0.15).timeout
	_check(is_instance_valid(dop) and int(dop.current_atk) == 7 and dop.card_data.keywords.has("swift"),
		"client doppelganger copied the CLIENT's last dead (7-atk swift, not the host's goblin)")

	# ── adaptable (client): EV_CHOICE on-enter, then the client's IN_CHOICE keyword pick ──
	var adp = combat._net_spawn_creature(CDB.get_card_data("adaptable"), 80002, 1, combat.ROW_FRONT, true, true)
	await create_timer(0.15).timeout
	combat._on_net_intent(2, {"t": NM.IN_CHOICE, "eid": 80002, "kind": "keyword", "pick": "piercing"})
	await create_timer(0.1).timeout
	_check(is_instance_valid(adp) and adp.card_data.keywords.has("piercing"),
		"client adaptable gained the keyword IT picked (piercing) via IN_CHOICE")
	combat._on_net_intent(2, {"t": NM.IN_CHOICE, "eid": 80002, "kind": "keyword", "pick": "bogus"})
	await create_timer(0.1).timeout
	_check(not adp.card_data.keywords.has("bogus"), "an invalid keyword pick is rejected host-side")

	# ── copycat (client): EV_CHOICE on-enter, then the client's IN_CHOICE copy pick ──
	var tgt = combat._net_spawn_creature(CDB.get_card_data("brute"), 80003, 2, combat.ROW_FRONT, true, false)
	if is_instance_valid(tgt):
		tgt.card_data["keywords"] = ["armored"]
	var cpy = combat._net_spawn_creature(CDB.get_card_data("copycat"), 80004, 3, combat.ROW_FRONT, true, true)
	await create_timer(0.15).timeout
	# Capture copycat's own body (CardDB base ATK) — asserting "unchanged" is robust to
	# the base-stat balance value (it was 0, now 1 in the working tree), unlike a hardcode.
	var cpy_base_atk: int = int(cpy.current_atk) if is_instance_valid(cpy) else -99
	combat._on_net_intent(2, {"t": NM.IN_CHOICE, "eid": 80004, "kind": "copy_friendly", "pick": 80004})
	await create_timer(0.1).timeout
	_check(is_instance_valid(cpy) and int(cpy.current_atk) == cpy_base_atk, "copycat can't copy itself (keeps its own body, unchanged)")
	combat._on_net_intent(2, {"t": NM.IN_CHOICE, "eid": 80004, "kind": "copy_friendly", "pick": 80003})
	await create_timer(0.1).timeout
	_check(is_instance_valid(cpy) and int(cpy.current_atk) == int(tgt.current_atk) and cpy.card_data.keywords.has("armored"),
		"client copycat became a copy of the friendly IT picked (brute, armored)")

	# ── chaos_imp auto-target perspective: a client cast aims at the HOST side ──
	combat._net_spawn_creature(CDB.get_card_data("brute"), 80005, 0, combat.ROW_BACK, false, false)
	await create_timer(0.1).timeout
	_check(combat._net_auto_target_for("enemy_creature", true) == 80005,
		"client chaos_imp auto-targets the HOST side (caster's foe)")
	var t_friend: int = combat._net_auto_target_for("friendly_creature", true)
	_check(t_friend != -1 and t_friend != 80005,
		"client chaos_imp friendly-target stays on the CLIENT side (not the host foe)")
	combat._net_cast_random_spell_free(true)
	await create_timer(0.15).timeout
	_check(is_instance_valid(combat), "client chaos_imp random cast resolved without crashing")

	# ── griffin (client): return routes to the caster + the once-per-fight guard ──
	combat._net_last_dead[1] = {"id": "griffin", "uid": 100123, "data": CDB.get_card_data("griffin")}
	combat._net_return_dead_to_caster(true)
	_check(combat._net_return_once_used[1].has(100123), "client griffin's return fired + marked the once-guard")
	combat._net_return_dead_to_caster(true)
	_check(combat._net_return_once_used[1].size() == 1, "griffin won't return the same uid twice in a fight")
	# Host side routes through the same guard to the host's own give-card channel.
	combat._net_last_dead[0] = {"id": "griffin", "uid": 555, "data": CDB.get_card_data("griffin")}
	combat._net_return_dead_to_caster(false)
	_check(combat._net_return_once_used[0].has(555), "host griffin routed to its OWN hand (per-side, mirrored)")

	# ── mourner's bonus_mana (on-death): next-turn Command reaches the OWNER ──
	var KE = root.get_node_or_null("KeywordEffects")
	var base_bonus: int = int(combat._bonus_mana_next_turn)
	KE._run_on_death({"type": "bonus_mana", "value": 1}, 0, false, combat)
	_check(int(combat._bonus_mana_next_turn) == base_bonus + 1,
		"host mourner's bonus_mana bumps the HOST's next-turn Command")
	KE._run_on_death({"type": "bonus_mana", "value": 1}, 0, true, combat)
	_check(int(combat._bonus_mana_next_turn) == base_bonus + 1,
		"client mourner's bonus_mana ships to the client, never the host's pool")
	# Receive side: the client folds EV_MANA next=true into its OWN next-turn pool
	# (flip to NET_CLIENT so _on_net_event's host guard lets the event through).
	var saved_mode: int = int(combat.combat_mode)
	combat.combat_mode = combat.CombatMode.NET_CLIENT
	combat._on_net_event({"t": NM.EV_MANA, "n": 1, "next": true})
	combat.combat_mode = saved_mode
	_check(int(combat._bonus_mana_next_turn) == base_bonus + 2,
		"client folds EV_MANA next=true into its own next-turn Command")
	combat._bonus_mana_next_turn = base_bonus


func _clear_net_board() -> void:
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			for is_e in [false, true]:
				for r in [combat.ROW_FRONT, combat.ROW_BACK]:
					var arr = combat._row_array(is_e, r)
					for ln in range(combat.LANES_PER_ROW):
						if arr[ln] == c:
							arr[ln] = null
			c.queue_free()
	await create_timer(0.12).timeout
	# Harness hygiene: queue_free above leaves the freed nodes REGISTERED in
	# NetMatch.entities. A later board-sync walk (_net_apply_board_sync with an
	# empty creatures list) calls get_entity on every registered eid — purge the
	# now-freed ones so it never touches a previously-freed instance.
	for eid in NM.entities.keys():
		if not is_instance_valid(NM.entities[eid]):
			NM.entities.erase(eid)


func _spawn_passive(eid: int, lane: int, row: int, is_enemy: bool, passive: String,
		atk: int = 2, hp: int = 5, kw: Array = []):
	return combat._net_spawn_creature({"id": "p%d" % eid, "name": "P", "type": "creature",
		"atk": atk, "hp": hp, "passive": passive, "keywords": kw}, eid, lane, row, is_enemy, false)


## Player-2 parity for the host-only PASSIVES — the combat engine read
## _all_player_creatures() / `if not is_enemy`, so these only ran for Player 1. Verify
## each now routes to the creature's OWN side: hero heals/drains, grow-on-event, the
## per-round/per-spell/play-time engines, walls, and double-on-death.
func _test_net_client_passives() -> void:
	print("— client PASSIVES route to Player 2 (heal/drain/grow/recompute/play-time/walls)")
	if combat._net_match_over:
		_check(true, "match over before passive test (skipped, acceptable)")
		return
	combat._net_active_index = 1
	await _clear_net_board()

	# ── owner-relative hero routing ──
	combat.player_hp = 20; combat.enemy_hp = 20
	combat._heal_owner_hero(true, 3)
	combat._heal_owner_hero(false, 2)
	_check(int(combat.enemy_hp) == 23 and int(combat.player_hp) == 22,
		"heal_owner_hero routes to each owner's hero (client 23 / host 22)")
	combat.player_hp = 20
	combat._hurt_opposing_hero(true, 4)
	_check(int(combat.player_hp) == 16, "hurt_opposing_hero(client) reaches the HOST hero")

	# ── death cluster (client side): Corpse Eater grows, Carrion Priest drains host ──
	var ce = _spawn_passive(82010, 0, combat.ROW_FRONT, true, "grow_on_ally_death")
	var cp = _spawn_passive(82011, 1, combat.ROW_FRONT, true, "drain_on_ally_death")
	await create_timer(0.1).timeout
	combat.player_hp = 20
	combat._apply_ally_death_passives(true)
	_check(is_instance_valid(ce) and int(ce.current_atk) == 3, "client Corpse Eater grew on a client ally death (2->3)")
	_check(int(combat.player_hp) == 19, "client Carrion Priest drained the HOST hero")

	# ── plague_doctor: a HOST death feeds the client apothecary (hits host face) ──
	_spawn_passive(82012, 2, combat.ROW_FRONT, true, "plague_doctor")
	await create_timer(0.1).timeout
	combat.player_hp = 20
	combat._apply_plague_doctor(false)   # a host creature just died
	_check(int(combat.player_hp) == 19, "client Apothecary pinged the HOST hero on a host death")

	# ── vengeance: the client hero taking face damage grows client Vengeance ──
	var vn = _spawn_passive(82013, 3, combat.ROW_FRONT, true, "vengeance_growth")
	await create_timer(0.1).timeout
	combat.enemy_hp = 20
	combat.damage_enemy_hero(1)
	_check(is_instance_valid(vn) and int(vn.current_atk) == 4, "client Vengeance grew +2 when the CLIENT hero took face damage")

	# ── per-round recompute: client Riteforge ramps its ally host-side ──
	await _clear_net_board()
	_spawn_passive(82020, 0, combat.ROW_FRONT, true, "riteforge_ramp")
	var ally = combat._net_spawn_creature(CDB.get_card_data("brute"), 82021, 1, combat.ROW_FRONT, true, false)
	await create_timer(0.1).timeout
	var ally0: int = int(ally.current_atk)
	combat._apply_start_round_passives(true)
	_check(is_instance_valid(ally) and int(ally.current_atk) == ally0 + 1, "client Riteforge ramped its ally +1 at round start")

	# ── Lifelink end-to-end: a client face hit heals the CLIENT hero ──
	await _clear_net_board()
	combat.enemy_hp = 15
	var ll = _spawn_passive(82030, 0, combat.ROW_FRONT, true, "", 3, 5, ["lifelink"])
	await create_timer(0.1).timeout
	await combat._creature_hits_face(ll, 0, true)
	_check(int(combat.enemy_hp) > 15, "client Lifelink healed the CLIENT hero on a face hit")

	# ── wall: a client Iron Bastion blunts a HOST attacker's face hit ──
	await _clear_net_board()
	combat.enemy_hp = 20
	_spawn_passive(82040, 0, combat.ROW_BACK, true, "reduce_face_damage", 0, 8)
	var ha = _spawn_passive(82041, 0, combat.ROW_FRONT, false, "", 4, 5)
	await create_timer(0.1).timeout
	await combat._creature_hits_face(ha, 0, false)
	_check(int(combat.enemy_hp) == 17, "client Iron Bastion blunted the host's face hit (4 -> 3)")

	# ── play-time enter bonuses read the CLIENT's per-side counters ──
	await _clear_net_board()
	combat._net_tallow_played[1] = 2
	var tl = _spawn_passive(82050, 0, combat.ROW_FRONT, true, "tallow_stacking", 1, 1)
	await create_timer(0.1).timeout
	combat._apply_play_time_passives(tl, true)
	_check(is_instance_valid(tl) and int(tl.current_atk) == 3 and int(tl.current_hp) == 3,
		"client Tallow Doll stacked +2/+2 from 2 priors (1/1 -> 3/3)")
	_check(int(combat._net_tallow_played[1]) == 3, "client Tallow count incremented to 3")
	combat._net_spells_fight[1] = 4
	var hx = _spawn_passive(82051, 1, combat.ROW_FRONT, true, "atk_per_spell", 2, 3)
	await create_timer(0.1).timeout
	combat._apply_play_time_passives(hx, true)
	_check(is_instance_valid(hx) and int(hx.current_atk) == 6, "client Hexblade entered +4 ATK for 4 client spells (2 -> 6)")

	# ── per-spell: a client spell grows the client Hexblade + Emberwright pings host ──
	combat.player_hp = 20
	_spawn_passive(82052, 2, combat.ROW_FRONT, true, "ember_per_spell", 2, 3)
	await create_timer(0.1).timeout
	var hx_atk: int = int(hx.current_atk)
	combat._net_resolve_spell({"spell": {"type": "damage_face", "value": 0}}, -1, 1)
	_check(is_instance_valid(hx) and int(hx.current_atk) == hx_atk + 1, "a client spell grew the client Hexblade +1")
	_check(int(combat.player_hp) < 20, "a client spell pinged the HOST hero via client Emberwright")

	# ── double_on_death detected on the client side ──
	_spawn_passive(82053, 3, combat.ROW_FRONT, true, "double_on_death")
	await create_timer(0.1).timeout
	_check(combat._has_passive_on_side("double_on_death", true), "client Warden of Graves seen on the client side")
	await _clear_net_board()


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
## pre-dealt (so they can see it during turn 1) at the normal refill PLUS the Coin
## (the going-second compensation — a one-time +1 Command card, not a raw extra
## draw), and that their first turn skips the draw rather than topping the hand up.
func _test_client_opening_hand() -> void:
	print("— second player (client) opening hand: pre-dealt refill + the Coin")
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
	# Host-first → this client (slot 1) is the going-SECOND player, so it pre-deals
	# the refill+1 opening hand the assertions below check.
	combat._net_first_player_override = 0
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
	# Going second deals the normal refill of real deck cards PLUS one synthetic Coin,
	# so the opening hand is refill+1 total — but the +1 is the Coin, not a raw draw.
	_check(combat._hand.size() == refill + 1,
		"client opened with refill + Coin = %d cards (got %d)" % [refill + 1, combat._hand.size()])
	var coins: int = 0
	var deck_cards: int = 0
	for c in combat._hand:
		if c.card_id == "coin":
			coins += 1
		else:
			deck_cards += 1
	_check(coins == 1, "the going-second compensation is exactly one Coin (got %d)" % coins)
	_check(deck_cards == refill,
		"the rest of the opening hand is the normal refill of deck cards (got %d)" % deck_cards)
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
	# Parity fix: the client's OWN fallen creature must recycle into its discard
	# pile, just as the host discards its dead via _cleanup_dead — otherwise the
	# client's deck silently shrinks over a long match.
	_check(combat._player_discard_pile.has(combat._pile_entry("goblin", mine_eid)),
		"client's fallen creature recycled into its discard pile")

	# Exile parity (Banish): a client creature that vanishes WITH its eid in the
	# snapshot's "exiled" list must be dropped WITHOUT recycling — exile ≠ death.
	var exile_eid: int = 8123
	combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": host_eid, "owner": 0, "lane": 0, "row": combat.ROW_FRONT,
			 "id": "brute", "atk": 3, "hp": 2, "mhp": 5, "kw": [], "floop": false, "token": false},
			{"eid": exile_eid, "owner": 1, "lane": 1, "row": combat.ROW_FRONT,
			 "id": "goblin", "atk": 2, "hp": 2, "mhp": 2, "kw": [], "floop": false, "token": false},
		],
		"host_hp": 20, "client_hp": 12, "active": 0,
	})
	await create_timer(0.2).timeout
	var disc_pre_exile: int = combat._player_discard_pile.size()
	combat._net_apply_board_sync({
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": host_eid, "owner": 0, "lane": 0, "row": combat.ROW_FRONT,
			 "id": "brute", "atk": 3, "hp": 2, "mhp": 5, "kw": [], "floop": false, "token": false},
		],
		"host_hp": 20, "client_hp": 12, "active": 0,
		"exiled": [exile_eid],
	})
	await create_timer(0.2).timeout
	_check(combat._player_discard_pile.size() == disc_pre_exile \
		and not combat._player_discard_pile.has(combat._pile_entry("goblin", exile_eid)),
		"an EXILED client creature was dropped WITHOUT recycling to discard")


## A spell the LOCAL player casts must return to their discard pile so their deck
## reshuffles — the same parity gap the creature fix closes (net plays weren't
## recycling like the solo path). Drives the recycle helper with a real spell card.
func _test_net_spell_recycle() -> void:
	print("— a locally-cast spell recycles into the discard pile")
	if not is_instance_valid(combat):
		_check(false, "client scene present for the spell-recycle test")
		return
	var uid: int = SS.UID_SLOT_STRIDE + 4
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = "strike"
	card.card_data = CDB.get_card_data("strike")
	card.deck_uid = uid
	combat.add_child(card)
	await create_timer(0.1).timeout
	var disc_before: int = combat._player_discard_pile.size()
	combat._net_recycle_spell(card)
	_check(combat._player_discard_pile.size() == disc_before + 1 \
		and combat._player_discard_pile.has(combat._pile_entry("strike", uid)),
		"the cast spell landed in the client's discard pile")
	if is_instance_valid(card):
		card.queue_free()


## Caster-LOCAL pile spell, driven through the real entry point (_net_play_caster_
## local_spell) with a no-UI spell so the headless harness can exercise it end to
## end: Frenzy grants +2 Command and adds a Curse to the caster's own discard, and
## the spell card itself recycles. (scrap/recycle/gambit/war_chant share this path
## but gate on a hand-picker modal the harness can't drive.)
func _test_net_caster_local_turbo() -> void:
	print("— caster-local Frenzy (turbo) through the real play path: +2 Command + Curse to discard")
	if not is_instance_valid(combat):
		_check(false, "scene present for the caster-local turbo test")
		return
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = "turbo"
	card.card_data = CDB.get_card_data("turbo")
	card.deck_uid = SS.UID_SLOT_STRIDE + 9
	combat.add_child(card)
	combat._hand.append(card)
	await create_timer(0.1).timeout
	var mana_before: int = int(combat.player_mana)
	var disc_before: int = combat._player_discard_pile.size()
	await combat._net_play_caster_local_spell(card, 0)
	await create_timer(0.1).timeout
	_check(int(combat.player_mana) == mana_before + 2, "Frenzy granted +2 Command (%d -> %d)" % [mana_before, int(combat.player_mana)])
	# +2: the Curse (turbo's effect) and the spell card itself (generic recycle).
	_check(combat._player_discard_pile.size() == disc_before + 2,
		"Frenzy added the Curse AND recycled the spell card into discard")
	var still_in_hand := false
	for h in combat._hand:
		if is_instance_valid(h) and int(h.deck_uid) == SS.UID_SLOT_STRIDE + 9:
			still_in_hand = true
	_check(not still_in_hand, "Frenzy left the caster's hand (card consumed)")


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
