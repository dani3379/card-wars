extends Node
## _shot_event_pass.gd — renders the 2026-07-04 event presentation pass to
## PNGs for visual verification (windowed, editor closed):
##   Godot.exe --path "D:\Godot" res://tools/_shot_event_pass.tscn
## Outputs tools/_shot_event_{main,blue,dice,result,picker}.png
##   main   — the Bone Pit choice screen: bone mood, ladder, stakes ledger
##   blue   — the Pawnbroker with the buy-back blue option (diamond marker)
##   dice   — the pot display + coin heap on the dice screen
##   result — gained card + relic standing on the result page
##   picker — remove picker over the dimmed art scrim

const EVENT_SCENE := "res://scenes/event.tscn"


func _ready() -> void:
	RunState.start_new_run("stalwart")
	RunState.gold = 137
	RunState.hero_hp = 17
	await get_tree().process_frame

	var ev = await _spawn_event("the_bone_pit")
	await _settle(1.6)
	await _capture("main")
	ev.queue_free()
	await get_tree().process_frame

	# Blue option needs the shelf stocked + act 2 + fee affordable.
	RunState.pawned_cards = ["militia_pikeman"]
	if RunState.pawned_cards[0].is_empty() or CardDB.get_card_data(RunState.pawned_cards[0]).is_empty():
		RunState.pawned_cards = [RunState.deck[0]]
	RunState.current_act_idx = 1
	ev = await _spawn_event("pawnbrokers_window")
	await _settle(1.6)
	await _capture("blue")
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("the_bone_pit")
	ev._start_dice_run({"start": 85, "bank_relic": "warm_knucklebone",
		"bank_relic_at": 75})
	await _settle(1.4)
	await _capture("dice")
	ev.queue_free()
	await get_tree().process_frame

	# The 2026-07-18 gamble stage: spinner at rest, a settled winning cast
	# (pips), a settled bust (skulls up + drained heap). The winning cast uses
	# the pit's REAL effect dict with the spinner already in events_seen, so
	# the seen_texts story beat ("You have met the spinner") is in frame.
	ev = await _spawn_event("coin_on_edge")
	ev._start_dice_run(ev.EVENTS["coin_on_edge"]["choices"][0]["effects"][0])
	await _settle(1.6)
	await _capture("spin")
	ev.queue_free()
	await get_tree().process_frame

	if not RunState.events_seen.has("coin_on_edge"):
		RunState.events_seen.append("coin_on_edge")
	ev = await _spawn_event("the_bone_pit")
	ev._start_dice_run(ev.EVENTS["the_bone_pit"]["choices"][0]["effects"][0])
	await _settle(1.2)
	await ev._play_bone_cast(false)
	await _capture("cast_win")
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("the_bone_pit")
	ev._start_dice_run({"start": 60})
	await _settle(1.2)
	await ev._play_bone_cast(true)
	await _capture("cast_bust")
	ev.queue_free()
	await get_tree().process_frame

	# Reduce Motion: the same winning cast must SNAP to stamped faces — no
	# orphan mid-tumble state, outcome fully readable without motion.
	UserSettings.reduce_motion = true
	ev = await _spawn_event("the_bone_pit")
	ev._start_dice_run({"start": 60})
	await _settle(0.8)
	await ev._play_bone_cast(false)
	await _capture("cast_rm")
	ev.queue_free()
	UserSettings.reduce_motion = false
	await get_tree().process_frame

	# The Burning Inch: the Gravesong Choir's candle fresh (verse 0), then
	# burned down two verses with the drips piled up.
	ev = await _spawn_event("gravesong_choir")
	ev._start_risk_loop(ev.EVENTS["gravesong_choir"]["choices"][0]["effects"][0])
	await _settle(1.2)
	await _capture("candle0")
	ev._risk_step = 2
	ev._build_risk_screen("A ring. A chain. A saint's little finger in silver.")
	await _settle(1.0)
	await _capture("candle2")
	ev.queue_free()
	await get_tree().process_frame

	# Drawing lots: a roll_table commit resolving as the drawn slip, caught
	# mid-unfold over the held result page. Settle past the beat before
	# freeing so the fire-and-forget coroutine finishes on a live instance.
	ev = await _spawn_event("the_crossing")
	ev._show_result(ev._apply_effect(
		ev.EVENTS["the_crossing"]["choices"][2]["effects"][0]))
	await _settle(0.95)
	await _capture("lots")
	await _settle(1.0)
	ev.queue_free()
	await get_tree().process_frame

	# The Old Army Game: the stage after the honest shuffle (ladder rows
	# armed), then the winning lift mid-reveal.
	ev = await _spawn_event("old_army_game")
	ev._start_shell_game(ev.EVENTS["old_army_game"]["choices"][0]["effects"][0])
	await _settle(5.4)
	await _capture("shells")
	ev._on_shell_pick(ev._shell_prize_helm)
	await _settle(0.75)
	await _capture("shell_win")
	await _settle(1.5)
	ev.queue_free()
	await get_tree().process_frame

	# The Short Straw: the fresh drawing at a fixed count, then the state
	# after one exchange — spent straws piled at both edges, count updated.
	ev = await _spawn_event("the_short_straw")
	var straw_cfg: Dictionary = \
		ev.EVENTS["the_short_straw"]["choices"][0]["effects"][0].duplicate()
	straw_cfg["counts"] = [15]
	ev._start_straw_game(straw_cfg)
	await _settle(1.0)
	await _capture("straws")
	ev._on_straw_take(2)
	await _settle(2.4)
	await _capture("straws_mid")
	ev.queue_free()
	await get_tree().process_frame

	# The Widow's Cut: your chit face-up with the open odds and the round tally,
	# then a cut played so the dead's reveal reads.
	ev = await _spawn_event("widows_tray")
	ev._start_cut_game(ev.EVENTS["widows_tray"]["choices"][0]["effects"][0])
	await _settle(0.6)
	ev._cut_your_rank = 11
	ev._cut_your_num.text = "11"
	ev._cut_refresh_odds()
	await _settle(0.3)
	await _capture("cut_open")
	ev._cut_deck[ev._cut_pos] = 4   # rig the dead to cut low so YOU win the round
	ev._on_cut_play()
	await _settle(1.4)
	await _capture("cut_play")
	ev.queue_free()
	await get_tree().process_frame

	# The Courier's Satchel: two draws in (two chits can't bust), the slate
	# ticked down, the sum standing.
	ev = await _spawn_event("the_couriers_satchel")
	ev._start_sack_game(
		ev.EVENTS["the_couriers_satchel"]["choices"][0]["effects"][0])
	await _settle(1.0)
	ev._on_sack_draw()
	await _settle(0.95)
	ev._on_sack_draw()
	await _settle(1.15)
	await _capture("satchel")
	ev.queue_free()
	await get_tree().process_frame

	# The Wheel of the Fourth: the wheel at rest with the colour-bet rows, then
	# mid-spin after backing a colour.
	ev = await _spawn_event("the_beetle_derby")
	ev._start_wheel_game(
		ev.EVENTS["the_beetle_derby"]["choices"][0]["effects"][0])
	await _settle(0.9)
	await _capture("wheel_open")
	ev._on_wheel_bet(0)
	await _settle(1.2)
	await _capture("wheel_spin")
	await _settle(2.6)
	ev.queue_free()
	await get_tree().process_frame

	# The Wet Cards deal (L4): backs mid-flip, then the full face-up row.
	ev = await _spawn_event("strangers_hand")
	await _settle(0.62)
	await _capture("wet_deal")
	await _settle(1.5)
	await _capture("wet")
	ev.queue_free()
	await get_tree().process_frame

	# The Provost Marshal: the deal settled with his opening bid standing
	# (your bones open, his helm down, raise/call rows armed), then one
	# raise in, then the showdown mid-count.
	ev = await _spawn_event("the_provost_marshal")
	ev._start_liar_game(
		ev.EVENTS["the_provost_marshal"]["choices"][0]["effects"][0])
	await _settle(2.6)
	await _capture("liar_open")
	ev._on_liar_raise(ev._liar_q + 1, ev._liar_f)
	await _settle(1.3)
	await _capture("liar_mid")
	ev._on_liar_call()
	await _settle(2.4)
	await _capture("liar_reveal")
	await _settle(4.0)
	ev.queue_free()
	await get_tree().process_frame

	# The Old Game: fists and studs at the first throw, then the flash —
	# both hands open, the count chalked, his spent throw joining the pile.
	ev = await _spawn_event("the_old_game")
	ev._start_morra_game(ev.EVENTS["the_old_game"]["choices"][0]["effects"][0])
	await _settle(1.2)
	await _capture("morra_open")
	ev._on_morra_call(3)
	await _settle(1.0)
	await _capture("morra_flash")
	await _settle(2.6)
	ev.queue_free()
	await get_tree().process_frame

	# The Burial Fund: both throws open with the table's law chalked, then
	# a two-bone recast mid-flight into the signifer's drill.
	RunState.gold = 300
	ev = await _spawn_event("the_burial_fund")
	ev._start_tali_game(ev.EVENTS["the_burial_fund"]["choices"][0]["effects"][0])
	await _settle(2.2)
	await _capture("tali_open")
	ev._tali_keep = [true, true, false, false]
	ev._tali_mark_keeps()
	ev._on_tali_throw()
	await _settle(1.5)
	await _capture("tali_recast")
	await _settle(5.0)
	ev.queue_free()
	await get_tree().process_frame

	# The Proving Ground: the raked field at the start, one safe step with
	# its count chalked, then the bust's honest show (crater + charges).
	RunState.gold = 300
	ev = await _spawn_event("the_proving_ground")
	ev._start_field_game(
		ev.EVENTS["the_proving_ground"]["choices"][0]["effects"][0])
	await _settle(1.0)
	await _capture("field_open")
	var safe_r: int = 0
	if int(ev._field_mine_at(0)) == 0:
		safe_r = 1
	ev._on_field_step(0, safe_r)
	await _settle(1.2)
	await _capture("field_step")
	while true:
		var c: int = int(ev._field_col)
		if c >= 5:
			break
		var mr: int = int(ev._field_mine_at(c))
		if mr >= 0:
			ev._on_field_step(c, mr)
			break
		ev._on_field_step(c, 0 if int(ev._field_mine_at(c)) != 0 else 1)
		await _settle(1.1)
	await _settle(1.2)
	await _capture("field_bust")
	await _settle(1.8)
	ev.queue_free()
	await get_tree().process_frame

	# The Gibbet Green: the gauge at rest (chain lean = wind), then a throw
	# that lands and settles a ringer/leaner on the board.
	RunState.gold = 120
	ev = await _spawn_event("the_gibbet_green")
	ev._start_quoits_game(
		ev.EVENTS["the_gibbet_green"]["choices"][0]["effects"][0])
	await _settle(1.0)
	await _capture("gibbet_open")
	# Aim to null the baked wind — lands the ring on or beside the peg.
	ev._on_quoits_loose(-ev._quoits_wind if absi(ev._quoits_wind) <= 1 else 0)
	await _settle(1.4)
	await _capture("gibbet_throw")
	await _settle(1.0)
	ev.queue_free()
	await get_tree().process_frame

	# Crown & Pike: the six war-marks and three dice at rest, then a mark backed
	# (selection ring + cast row), then the dice cast and landed.
	RunState.gold = 120
	ev = await _spawn_event("the_drummers_tattoo")
	ev._start_crown_game(
		ev.EVENTS["the_drummers_tattoo"]["choices"][0]["effects"][0])
	await _settle(0.6)
	await _capture("crown_open")
	ev._on_crown_mark(0)
	await _settle(0.4)
	await _capture("crown_mark")
	ev._on_crown_cast()
	await _settle(1.4)
	await _capture("crown_cast")
	await _settle(0.6)
	ev.queue_free()
	await get_tree().process_frame

	# The Quartermaster's Scale: coins assigned to the pans, then the beam
	# dropped so it tips toward the heavier side (the light coin's pan rises).
	RunState.gold = 140
	ev = await _spawn_event("the_quartermasters_scale")
	ev._start_scale_game(
		ev.EVENTS["the_quartermasters_scale"]["choices"][0]["effects"][0])
	await _settle(0.6)
	# Assign 3 v 3 the way a player would: coins 0,1,2 to the left (one
	# click), coins 3,4,5 to the right (two clicks each), a frame between
	# clicks as in real play so the row rebuild's deferred frees resolve.
	for i in [0, 1, 2]:
		ev._on_scale_coin(i)
		await get_tree().process_frame
	for i in [3, 4, 5]:
		ev._on_scale_coin(i)
		await get_tree().process_frame
		ev._on_scale_coin(i)
		await get_tree().process_frame
	await _settle(0.3)
	await _capture("scale_setup")
	ev._on_scale_drop()
	await _settle(1.4)
	await _capture("scale_drop")
	await _settle(0.6)
	ev.queue_free()
	await get_tree().process_frame

	# The Fourth's Strongbox: set the wards to a guess and try it, showing
	# the honest seated/loose feedback in the ledger.
	RunState.gold = 160
	ev = await _spawn_event("the_fourths_strongbox")
	ev._start_box_game(
		ev.EVENTS["the_fourths_strongbox"]["choices"][0]["effects"][0])
	await _settle(0.5)
	# Turn the wards to 2/4/1/5 and try; then a second guess for the ledger.
	ev._box_guess = [2, 4, 1, 5]
	for i in range(4):
		ev._box_numlabels[i].text = str(ev._box_guess[i])
	ev._box_arm_rows()
	await _settle(0.3)
	await _capture("box_setup")
	ev._on_box_try()
	await _settle(0.6)
	ev._box_guess = [3, 4, 6, 2]
	for i in range(4):
		ev._box_numlabels[i].text = str(ev._box_guess[i])
	ev._on_box_try()
	await _settle(0.7)
	await _capture("box_feedback")
	await _settle(0.5)
	ev.queue_free()
	await get_tree().process_frame

	# The Dead Man's Deal: the big face-up pay-chit with the open odds, then a
	# call that climbs the streak so the flip + spent-row + ladder all read.
	RunState.gold = 130
	ev = await _spawn_event("the_powder_move")
	ev._start_deal_game(
		ev.EVENTS["the_powder_move"]["choices"][0]["effects"][0])
	await _settle(0.5)
	await _capture("deal_open")
	# Force a held call (rig the deck so the next chit clears) and read the
	# spent-row + streak ladder after the flip.
	ev._deal_deck = [7, 11, 3, 9, 2, 13, 5, 8, 1]
	ev._deal_pos = 0
	ev._deal_refresh()
	await _settle(0.2)
	ev._deal_call(true)
	await _settle(0.8)
	await _capture("deal_held")
	ev.queue_free()
	await get_tree().process_frame

	# The Signal Line: the half-lit beacon wall, then one strike flipping a
	# cresset and its two neighbours.
	RunState.gold = 100
	ev = await _spawn_event("the_signal_line")
	ev._start_signal_game(
		ev.EVENTS["the_signal_line"]["choices"][0]["effects"][0])
	await _settle(0.5)
	# Hover-telegraph: preview the three cressets a strike on #3 would flip.
	ev._on_signal_hover(3, true)
	await _settle(0.2)
	await _capture("signal_start")
	ev._on_signal_press(3)
	await _settle(0.6)
	await _capture("signal_strike")
	await _settle(0.5)
	ev.queue_free()
	await get_tree().process_frame

	# ── The Sentry's Board (morris_game): placement with the hover ghost,
	# then the march with a lifted stone's legal posts ringed green. The
	# drill's replies are deterministic (see _probe_morris_solve.gd), so
	# the board below is by construction: you 0/2, him 4 then blocking 1.
	ev = await _spawn_event("the_sentrys_board")
	ev._start_morris_game(
		ev.EVENTS["the_sentrys_board"]["choices"][0]["effects"][0])
	await _settle(0.5)
	await ev._on_mor_post(0)
	await _settle(0.3)
	await ev._on_mor_post(2)
	await _settle(0.3)
	ev._on_mor_hover(7)
	await _settle(0.2)
	await _capture("morris_place")
	# From here the shot plays the SOLVED forced line from
	# _probe_morris_solve.gd: place 7 (he rolls 3), the waiting march
	# 7->6 leaves his whole drill in zugzwang, the middle post is forced
	# out, and 0->4 closes the [2,4,6] mill.
	await ev._on_mor_post(7)
	await _settle(0.4)
	# Movement phase: lift the near post; 6 and 8 ring green.
	await ev._on_mor_post(7)
	ev._on_mor_hover(6)
	await _settle(0.2)
	await _capture("morris_march")
	await ev._on_mor_post(6)
	await _settle(0.4)
	# The kill: 0 -> the vacated middle post. Fired via call_deferred
	# (a bare unawaited coroutine call is a runtime error) so the chalk
	# stroke and win caption are caught mid-ceremony.
	await ev._on_mor_post(0)
	ev.call_deferred("_on_mor_post", 4)
	await _settle(0.55)
	await _capture("morris_mill")
	await _settle(1.2)
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("the_last_garrison")
	ev._apply_effect({"type": "add_card_id", "id": "old_bones"})
	ev._apply_effect({"type": "random_relic"})
	ev._show_result("You improvise the relief order with full honors. The sergeant, out of habit, falls in with you.")
	await _settle(2.0)
	await _capture("result")
	ev.queue_free()
	await get_tree().process_frame

	ev = await _spawn_event("the_remount_fair")
	ev._start_remove_mode()
	await _settle(1.4)
	await _capture("picker")
	ev.queue_free()
	await get_tree().process_frame

	print("[shot] all done")
	get_tree().quit()


func _spawn_event(id: String) -> Node:
	var ev = load(EVENT_SCENE).instantiate()
	add_child(ev)
	await get_tree().process_frame
	# _ready rolled a random event; force ours and rebuild. The preserved art
	# and scrim nodes carry the random pick's texture/mood — drop them so
	# _build_ui recreates both for the forced id.
	for n in ["EventArt", "EventOverlayLeft"]:
		var node = ev.get_node_or_null(n)
		if node != null:
			ev.remove_child(node)
			node.free()
	ev._event_id = id
	ev._event_data = ev.EVENTS[id]
	ev._current_node = ev._event_data
	# Invalidate the random pick's in-flight threaded art request (its serial
	# is still valid, so a late landing would stamp the WRONG painting onto
	# the rebuilt screen) and hydrate fresh for the forced id.
	ev._event_art_request_serial += 1
	ev._event_art_loading = false
	ev._event_image = null
	ev._event_image_path = ""
	ev._build_ui()
	ev._begin_event_art_hydration()
	return ev


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/_shot_event_%s.png" % name)
	print("[shot] saved ", name, " ", img.get_size())
