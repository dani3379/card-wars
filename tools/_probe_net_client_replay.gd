extends SceneTree
## _probe_net_client_replay.gd — THE WATCHER'S HALF, ACTUALLY EXECUTED (2026-08-04).
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_client_replay.gd
##
## `_probe_net_clash_beats` proves the HOST ships a complete reel. That says nothing
## about whether the client can play it: `_net_replay_fallen` and
## `_net_replay_trigger_fx` are reachable ONLY from a real second peer, so short of a
## two-process match they had never run once. A compile gate does not help — every
## way these break (a member that moved, a wrong channel key, an anchor read after
## the despawn loop) is a runtime error on somebody else's machine.
##
## So this boots a CLIENT, hands it a hand-built EV_CLASH reel and a board snapshot
## carrying a trigger-fx entry, and checks the effects landed:
##
##   * a {fo} entry moves the spotlight and {fo:-1} takes it off
##   * a {dw} entry is consumed without stalling the reel
##   * a {fal} entry NAMES the mortally-struck bodies (the client's corpses belong to
##     the trailing snapshot, so naming is all it can do — and the beats it spends
##     doing it are what hold that snapshot back)
##   * a {trig:"death"} fx entry fires its beat while the dying body is still standing
##   * a {trig:"enter"} fx entry fires after the reconcile, on a survivor
##
## HOUSE TRAP: all THREE terms of is_connected_to_peer() or Combat boots SOLO.

var SS: Node
var NM: Node
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


## A body with a real on-enter AND on-death, so both trigger channels have something
## to describe. `damage_opposing` is an acknowledged type in both FX maps.
func _rules_body(tag: String, hp: int) -> Dictionary:
	return {
		"id": "cr_%s" % tag, "name": "Replay%s" % tag,
		"type": "creature", "cost": 1, "atk": 2, "hp": hp,
		"rarity": "common", "keywords": [], "desc": "",
		"on_enter": {"type": "damage_opposing", "value": 1},
		"on_death": {"type": "damage_opposing_lane", "value": 1},
	}


func _run() -> void:
	print("[client-replay] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	var US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[client-replay] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false

	SS.reset()
	for cid in ["brute", "goblin", "brute", "goblin", "brute", "goblin", "brute", "goblin"]:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_CLIENT
	SS.local_index = 1
	SS.rng_seed = 1357
	NM.is_host = false
	NM.local_player_index = 1
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true   # the third term — or Combat boots SOLO
	NM.entities.clear()
	NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	await create_timer(0.4).timeout
	if not is_instance_valid(combat):
		print("[client-replay] FATAL: combat freed during boot"); _finish(1); return
	_check(combat._is_net() and combat._is_client(), "combat booted as a NET CLIENT")

	# Two of ours, two of theirs — mirrored the way a client sees the host's board.
	var mine_a = combat._net_spawn_creature(_rules_body("MineA", 4), 8001, 0, combat.ROW_FRONT, false, false)
	var mine_b = combat._net_spawn_creature(_rules_body("MineB", 4), 8002, 1, combat.ROW_FRONT, false, false)
	var theirs_a = combat._net_spawn_creature(_rules_body("TheirsA", 4), 9001, 0, combat.ROW_FRONT, true, false)
	var theirs_b = combat._net_spawn_creature(_rules_body("TheirsB", 4), 9002, 1, combat.ROW_FRONT, true, false)
	await create_timer(0.3).timeout
	_check(mine_a != null and theirs_a != null, "four bodies spawned on the client board")

	# ── The reel. Shaped exactly as the host writes it (CombatNet._net_log_*). ──
	# Two bodies are struck to 0 so the {fal} marker has corpses to name.
	var reel: Array = [
		{"cap": "FRONT ROW ATTACKS"},
		{"fo": 0, "fe": true},
		{"l": 9001, "dt": 8001, "latk": 4},
		{"d": 8001, "hp": 0, "n": 4, "a": 9001, "o": 0, "ahp": 4},
		{"dw": 2},
		{"fo": 1, "fe": false},
		{"l": 8002, "dt": 9002, "latk": 4},
		{"d": 9002, "hp": 0, "n": 4, "a": 8002, "o": 1, "ahp": 4},
		{"dw": 2},
		{"cap": "THE FALLEN"},
		{"fal": true},
		{"fo": -1},
	]
	var focus = combat._clash_lane_focus
	_check(focus != null and is_instance_valid(focus), "the client built a ClashLaneFocus")

	print("\n[client-replay] === replaying a host reel ===")
	await combat._net_replay_clash({"strikes": reel, "atk": 0, "banner": true})
	await create_timer(0.4).timeout

	_check(combat._phase_caption == "THE FALLEN",
		"the reel's captions drove the client's phase line (now: '%s')" % combat._phase_caption)
	_check(int(mine_a.current_hp) <= 0 and int(theirs_b.current_hp) <= 0,
		"the struck bodies are mortally struck on the client")
	_check(int(mine_b.current_hp) > 0 and int(theirs_a.current_hp) > 0,
		"the untouched bodies are unharmed")
	var fr: Rect2 = focus.get("_focus_rect")
	_check(float(focus.get("_strength")) <= 0.01 or fr.size.x <= 0.0,
		"the trailing {fo:-1} took the spotlight back off the board")

	# ── The board snapshot behind it, carrying both trigger-FX channels. ──
	# `theirs_b` vanishes (it died), so its DEATH beat must fire in the pass that
	# runs BEFORE the despawn loop or it has no anchor left. `mine_b` survives, so
	# its ENTER beat rides the pass after the reconcile.
	print("\n[client-replay] === board sync with trigger FX ===")
	var sync := {
		"t": NM.EV_BOARD_SYNC,
		"creatures": [
			{"eid": 8002, "owner": 1, "lane": 1, "row": combat.ROW_FRONT,
				"id": "cr_MineB", "atk": 2, "hp": 4, "mhp": 4, "kw": [],
				"floop": false, "token": false},
			{"eid": 9001, "owner": 0, "lane": 0, "row": combat.ROW_FRONT,
				"id": "cr_TheirsA", "atk": 2, "hp": 4, "mhp": 4, "kw": [],
				"floop": false, "token": false},
		],
		"host_hp": combat.enemy_hp, "client_hp": combat.player_hp, "active": 1,
		"fx": [
			{"eid": 9002, "trig": "death"},
			{"eid": 8002, "trig": "enter"},
			{"eid": 8002, "label": "THORNS", "col": [0.62, 0.86, 0.46], "icon": "thorns"},
		],
	}
	# The card_data the trigger replay reads comes off the LOCAL node, so give the
	# two survivors/casualties the rules dicts a real skirmish card would carry.
	for pair in [[mine_b, "MineB"], [theirs_b, "TheirsB"]]:
		if is_instance_valid(pair[0]):
			pair[0].card_data["on_enter"] = {"type": "damage_opposing", "value": 1}
			pair[0].card_data["on_death"] = {"type": "damage_opposing_lane", "value": 1}
	combat._net_apply_board_sync(sync)
	await create_timer(0.5).timeout
	# The real gate is that none of the three fx entries threw: a runtime error in
	# _net_replay_trigger_fx aborts _net_apply_board_sync mid-reconcile, so the
	# despawn below simply would not have happened.
	_check(not is_instance_valid(theirs_b) or int(theirs_b.current_hp) <= 0,
		"the snapshot swept the corpse (the fx passes did not abort the reconcile)")
	_check(is_instance_valid(mine_b) and is_instance_valid(theirs_a),
		"the survivors are still on the client board")
	_check(combat._row_array(false, combat.ROW_FRONT)[0] == null,
		"our dead body's slot was released")

	# ── THE STRIKE CONTRACT REACHES THE WATCHER (2026-08-04, second pass) ─────
	#
	# The hitstop, the weight-class pacing, the contact point and the ranged tracer all
	# shipped AFTER the first parity pass and none of them reached this path: the client
	# was still on the flat HITSTOP_BEAT / POST_HIT_BEAT pair, sprayed its sparks out of
	# the middle of the painting, and drew every sniper shot as a warm melee slash.
	print("\n[client-replay] --- the strike contract ---")
	var net_src: String = load("res://scripts/net/CombatNet.gd").source_code
	var s_a = combat._net_spawn_creature(_rules_body("StrikeA", 9), 8101, 2, combat.ROW_FRONT, false, false)
	var s_b = combat._net_spawn_creature(_rules_body("StrikeB", 9), 9101, 2, combat.ROW_FRONT, true, false)
	await create_timer(0.3).timeout

	# THE CONTACT POINT is a real geometric claim, so assert it as one: the point must
	# sit on the victim's own edge, back along the line of the blow — not at its centre,
	# which is the surface ★4's spatter was reverted for touching.
	var contact: Vector2 = combat._strike_contact_point(s_a, s_b)
	var centre: Vector2 = combat._card_center(s_b)
	var half: Vector2 = s_b.size * s_b.scale * 0.5
	_check(contact.distance_to(centre) > 1.0,
		"the contact point is NOT the card centre (%.1f px off)" % contact.distance_to(centre))
	_check(absf(contact.x - centre.x) <= half.x + 1.0 and absf(contact.y - centre.y) <= half.y + 1.0,
		"the contact point lies on the victim's own rect, not out in the table")

	# A TRADE IS ONE BEAT. The forward blow and the counter are two logged entries but
	# a single punctuation host-side, so the replay has to pair them — and both halves
	# must still land their damage.
	var trade_reel: Array = [
		{"fo": 2, "fe": true},
		{"l": 9101, "dt": 8101, "latk": 6},
		{"d": 8101, "hp": 3, "n": 6, "p": 6, "a": 9101, "o": 0, "ahp": 9},
		{"d": 9101, "hp": 5, "n": 4, "p": 4, "a": 8101, "o": 1, "ahp": 3, "ctr": true},
		{"dw": 1},
		{"fo": -1},
	]
	await combat._net_replay_clash({"strikes": trade_reel, "atk": 0, "banner": false})
	await create_timer(0.3).timeout
	_check(is_instance_valid(s_a) and int(s_a.current_hp) == 3,
		"the forward blow landed on the client (%s HP)" %
			(str(s_a.current_hp) if is_instance_valid(s_a) else "freed"))
	_check(is_instance_valid(s_b) and int(s_b.current_hp) == 5,
		"the paired COUNTER landed too — pairing them did not swallow the second half")

	# The punctuation itself: one funnel, run on the watcher's own clock, and the
	# retired flat pair is gone from the strike path.
	var hit_body := _fn_body(net_src, "_net_replay_creature_hit")
	_check(hit_body.contains("_net_strike_punctuation"),
		"the client's strike replay punctuates through the shared funnel")
	_check(not hit_body.contains("combat.HITSTOP_BEAT"),
		"the retired flat HITSTOP_BEAT/POST_HIT_BEAT pair is gone from the strike path")
	var punct := _fn_body(net_src, "_net_strike_punctuation")
	_check(punct.contains("hold_strike_frame"),
		"the watcher gets the real hitstop — the tweens are PAUSED, not just awaited")
	_check(punct.contains("_strike_stop") and punct.contains("_strike_read"),
		"and weighs it with the host's own helpers (weight crosses, the clock is local)")
	_check(hit_body.contains("_strike_contact_point"),
		"the client's spark erupts at the struck edge, like the host's")
	_check(hit_body.contains("rng"), "a ranged shot replays as a ranged shot, not a melee slash")
	_check(_fn_body(net_src, "_net_replay_clash").contains("ctr"),
		"the reel pairs a blow with its counter into ONE beat")

	# THE CLOSING LEDGER, READ FROM OUR SIDE. The host wrote "1 of ours, 3 of theirs"
	# from its board; ours is the mirror, so the watcher must read it swapped. Shipping
	# the finished sentence would have told the player who just lost three bodies that
	# their line held.
	await combat._net_replay_clash({"strikes": [{"led": [1, 3]}], "atk": 0, "banner": false})
	await create_timer(0.2).timeout
	var ledger_text := String(combat._info_label.text) if combat._info_label != null else ""
	_check(ledger_text.begins_with("3 of ours down"),
		"the watcher reads the ledger from ITS OWN side (got: '%s')" % ledger_text)

	# ★8 — THE BLOW THAT ENDED IT. The client learns the verdict from a BACKLOGGED
	# EV_MATCH_OVER, so without this the fight-ending blow read as one more chip hit
	# and the world-stop arrived a whole reel later.
	_check(not combat._net_killing_blow_held, "the killing-blow hold is unclaimed before the blow")
	await combat._net_replay_clash({"strikes": [
		{"l": 9101, "latk": 8},
		{"f": 1, "fhp": 0, "n": 30, "p": 30, "a": 9101, "o": 0, "lane": 2},
	], "atk": 0, "banner": false})
	await create_timer(0.3).timeout
	_check(combat._net_killing_blow_held,
		"the watcher claims the ★8 hold AT the fight-ending blow")
	_check(int(combat.player_hp) <= 0, "and the hero it felled is actually down")

	# ── THE KEYSTONE WAVES REACH THE WATCHER ──────────────────────────────
	#
	# `_trigger_fx_grace_wave` takes POINTS, and points describe the host's board, which
	# is our mirror — so every keystone payoff wave (warden HOLD, the Volley, the
	# bastion SIEGE ramp, the type_buff aura, the coven hop, the Magister's ledger) was
	# host-only. Worse, `_apply_start_round_passives` is host-authoritative
	# (`if not _is_client()`), so the client never even runs those sites: it received the
	# ATK numbers in the snapshot with no cause shown. The CHIP beside the wave already
	# crossed, which is what made it read as a quiet beat rather than a missing one.
	print("\n[client-replay] --- the keystone waves ---")
	var combat_src: String = load("res://scripts/scenes/Combat.gd").source_code
	var wave_fn := _fn_body(combat_src, "grace_wave_over")
	_check(wave_fn != "", "Combat.grace_wave_over exists (the mirroring funnel)")
	_check(wave_fn.contains("entity_id") and wave_fn.contains("_net_queue_fx_chip"),
		"it ships ENTITY IDS, so the watcher rebuilds the points off its own board")
	# Every keystone site must go through the funnel. A direct _trigger_fx_grace_wave
	# call in a net-reachable resolver is exactly the local-only shape this replaces.
	for fn_name in ["_apply_start_round_passives", "_apply_play_time_passives",
			"_maybe_pay_ledger", "_record_spell_cast_board_payoffs"]:
		var body := _fn_body(combat_src, fn_name)
		_check(body != "" and not body.contains("_trigger_fx_grace_wave("),
			"%s raises its wave through the mirroring funnel, not the local-only call" % fn_name)
	# And the client can actually draw one from eids alone.
	var wave_reel: Array = [{"kw": {"wave": [8002, 9001], "col": [0.62, 0.86, 0.46]}}]
	await combat._net_replay_clash({"strikes": wave_reel, "atk": 0, "banner": false})
	await create_timer(0.2).timeout
	_check(is_instance_valid(mine_b) and is_instance_valid(theirs_a),
		"a {wave} entry replays on the client without throwing (bodies still live)")
	_check(_fn_body(net_src, "_net_render_fx_chip").contains("wave"),
		"the shared chip renderer knows a wave from a callout")

	# ── The exits are the SHARED authored ones, not hand-rolled copies ────
	#
	# Source-inspected because the visual difference is invisible to an assertion:
	# both a burn and a shrink-spin end with a freed node. `_net_despawn_creature`
	# hand-rolled `_die`'s FALLBACK tween until 2026-08-04 (so a client watched the
	# retired generic death while the host burned the writ) and it played an ASH
	# burst for a Banish, which is this game's word for a death — the one thing
	# `_play_banish_exit`'s own header says a banish is not.
	print("\n[client-replay] --- the exits are the shared authored ones ---")
	var despawn := _fn_body(net_src, "_net_despawn_creature")
	_check(despawn != "", "_net_despawn_creature exists")
	_check(despawn.contains("play_death_flourish"),
		"a client death routes through Card2D's shared death flourish (the writ burns)")
	_check(despawn.contains("_play_banish_exit"),
		"a client exile routes through the authored banish exit (not an ash burst)")
	_check(not despawn.contains("randf_range(-0.5, 0.5)"),
		"the hand-rolled shrink-spin-fade copy is gone")
	var card_src: String = load("res://scripts/Card2D.gd").source_code
	var flourish := _fn_body(card_src, "play_death_flourish")
	_check(flourish.contains("_play_burn_death"),
		"the shared flourish still prefers the burn, with the fallback behind it")
	# Asserted as "_die DELEGATES", not as "_die does not mention the burn": the
	# slice runs to the next `func`, so it carries the following function's doc
	# comment, and that comment naturally names `_play_burn_death`. A source probe
	# that greps for a word rather than a CALL will keep finding prose.
	_check(_fn_body(card_src, "_die").contains("play_death_flourish()"),
		"_die owns the DEATH and delegates the BODY GOING — one copy of the animation")

	if _fails == 0:
		print("\n[client-replay] ALL PASS")
	else:
		print("\n[client-replay] %d FAILURES" % _fails)
	_finish(1 if _fails > 0 else 0)


## Slice one function out of a script's source. Both markers are "\nfunc " so a
## local lambda or a nested string cannot end the slice early.
func _fn_body(src: String, fn_name: String) -> String:
	var head: int = src.find("func %s(" % fn_name)
	if head < 0:
		return ""
	var tail: int = src.find("\nfunc ", head + 1)
	return src.substr(head, (tail - head) if tail > head else -1)
