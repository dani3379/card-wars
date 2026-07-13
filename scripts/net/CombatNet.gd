## CombatNet.gd — Combat's online-skirmish layer, extracted verbatim from
## Combat.gd (backend restructure 2026-07-14). Bodies are unchanged except
## that Combat members are reached through `combat` (the ctx — KeywordEffects
## precedent). All net STATE still lives on Combat (probes and saves read it
## there); Combat keeps thin same-name delegators for every function here, so
## probes, KeywordEffects ctx calls, and core call sites are unchanged.
## Instantiated as a plain child Node of Combat (see Combat._init), so signal
## connections and the Card2D.net_last_stand_cb hook die with the scene.
extends Node

var combat  # the Combat scene (untyped: Combat.gd has no class_name)


# ═════════════════════════════════════════════════════════════════════════
#  ONLINE SKIRMISH — combat networking (docs/MULTIPLAYER_SKIRMISH_PLAN.md §12-13)
#
#  Architecture (v1): HOST-AUTHORITATIVE with FULL BOARD-SNAPSHOT SYNC.
#   • Draw + Command are local per side (each player draws their own deck on
#     their own turn — the existing _start_round machinery, with all relic /
#     mutator / encounter branches inert in net mode).
#   • Placement, on-enter / on-death effects, and the attack clash are computed
#     ONLY on the host. After every authoritative mutation the host pushes a full
#     board snapshot (_net_sync_board); the client reconciles its board to it.
#   • The client never resolves combat — it sends intents and renders snapshots.
#   • Turn model: FULL-ALTERNATING. One active player at a time; on ATTACK the
#     active side strikes the other side one direction, then the turn passes.
#   • entity_id == the card's deck uid for drafted creatures (both machines agree
#     without negotiation); tokens get host-issued ids above any uid.
#
#  v1 scope: CREATURES (place + on-enter + Swift/column/Ranged clash + on-death),
#  SPELLS (curated set, perspective-aware host resolver), match-over, mid-match
#  disconnect, coarse client clash animation. DEFERRED: combat-time floop toggles
#  + reposition (board interaction stays off), exotic pile/draw/Discover spells
#  (denylisted in draft), per-strike clash replay, a dedicated opp-hand widget.
# ═════════════════════════════════════════════════════════════════════════



func _net_issue_token_id() -> int:
	var id = combat._net_token_id_next
	combat._net_token_id_next += 1
	return id




# ── Match lifecycle ──────────────────────────────────────────────────────

func _net_begin_combat() -> void:
	if combat._net_signals_wired:
		return
	combat._net_signals_wired = true
	NetMatch.combat_event_received.connect(_on_net_event)
	if combat._is_host():
		NetMatch.combat_intent_received.connect(_on_net_intent)
		# Last Stand mirror: the flare fires inside Card2D.take_damage, which only
		# ever runs on the host — install the hook so the save ships to the client
		# via the eid-anchored fx channel (rides the next board sync).
		Card2D.net_last_stand_cb = _net_on_last_stand_saved
	# Mid-match disconnect: bail to the menu rather than hang (plan §15).
	NetMatch.peer_left.connect(func(_id): _net_on_peer_lost())
	NetMatch.host_closed.connect(_net_on_peer_lost)
	# Open-hand spectating: build the face-up "opponent's hand" strip up top now so
	# it's ready when the first EV_HAND_COUNT (which now carries the cards) lands.
	_net_build_opp_hand_ui()
	# Foe's Command seal (mirror of the player's): seed its max from the opponent's
	# slot so it reads "0 / <base>" until their first turn-begin sync, then build it.
	var opp_slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(SkirmishState.opponent_index())
	if opp_slot != null:
		combat._net_opp_max_mana = opp_slot.base_max_mana
	if combat._net_opp_mana_post == null:
		combat._build_command_seal_post(true)
	# Foe's arsenal rail: their drafted battle relic + potion, on the table like
	# HS trinkets (the picks crossed the wire in NetDraft's deck handoff).
	_net_build_foe_arsenal()
	combat.phase = combat.Phase.PLAYER_TURN
	# ── SEALED ORDERS style: no opener, no Coin — both sides give orders blind,
	# so there is nothing to compensate. Initiative (reveal order + sorcery
	# opener) starts on the seed coin flip and alternates per round. ──
	if _is_sealed():
		combat._net_initiative = combat._net_first_player()
		combat._show_info("Sealed Orders — both lines are set in secret.")
		# Listeners are wired and the scene is built — replay any opening messages
		# the peer sent while we were still booting (see NetMatch.attach_combat).
		NetMatch.attach_combat()
		if combat._is_host():
			if SkirmishState.vs_bot:
				_bot_refill_hand()
				_bot_sync_hand_display()
				_net_prebake_bot_textures()
			await combat.get_tree().create_timer(0.6).timeout
			_sealed_begin_round(1)
		return
	# ── THE TOSS (2026-07-11): the seed coin flip now decides who CHOOSES the
	# ground, not who marches first. The winner picks MARCH FIRST (dictate the
	# opening line, act first every round) or HOLD BACK (see the foe's line,
	# keep the Coin, and your very first turn STRIKES — the second player's
	# opening turn is de facto turn 2, so it fights like one). The pick lands in
	# _net_first_player_override on BOTH machines, so everything downstream
	# (pre-deal, Coin, button labels, the host's turn loop) keys off the settled
	# order. Probes pre-set the override and skip the toss; headless resolves to
	# the raw flip; the bot never chooses — the human always takes the toss.
	# attach_combat must be wired BEFORE the wait so the peer's pick (buffered
	# during our boot) can land — it stays ahead of the host's round 1 either way.
	NetMatch.attach_combat()
	if combat._net_first_player_override < 0:
		var toss_winner: int = combat._net_my_index() if SkirmishState.vs_bot \
			else combat._net_first_player()
		if DisplayServer.get_name() == "headless":
			combat._net_first_player_override = combat._net_first_player()
		elif toss_winner == combat._net_my_index():
			var pick_first: bool = await _net_show_order_choice()
			combat._net_first_player_override = combat._net_my_index() if pick_first \
				else 1 - combat._net_my_index()
			if not SkirmishState.vs_bot:
				if combat._is_host():
					NetMatch.send_to_client({"t": NetMatch.EV_ORDER_PICK,
						"first": combat._net_first_player_override})
				else:
					NetMatch.send_intent({"t": NetMatch.IN_ORDER_PICK,
						"first": combat._net_first_player_override})
		else:
			combat._show_info("The foe won the toss — they are choosing the ground…")
			# Wait for the pick to cross the wire; a generous timeout falls back
			# to the raw flip so a dropped message can never soft-lock the match.
			var toss_waited := 0.0
			while combat._net_first_player_override < 0 and toss_waited < 90.0 \
					and not combat._net_match_over:
				await combat.get_tree().create_timer(0.2).timeout
				toss_waited += 0.2
			if combat._net_first_player_override < 0:
				combat._net_first_player_override = combat._net_first_player()
	# The opening experience keys off going first / second, not host / client —
	# both roles are identical and swap with the settled order.
	var first_index: int = combat._net_first_player()
	var i_go_first: bool = first_index == NetMatch.local_player_index
	if i_go_first:
		# Going first: the opening turn is place-only (no free attack into an empty
		# board); the hand is drawn on turn-start, not pre-dealt.
		combat._show_info("Skirmish — you have the first move.")
	else:
		# Going second: pre-deal the opening hand NOW so it's readable during the
		# opponent's opener (otherwise the second player stares at an empty hand),
		# at the normal refill PLUS a single Coin — the going-second compensation. A
		# raw extra card proved too strong, so the second player now gets a one-time
		# +1 Command (the Coin) instead. The skip flag stops this side's first
		# _start_round from topping the pre-dealt hand up again.
		_net_set_local_active(false)
		# The pre-deal honours the drafted battle relic (Deep Satchel) — without
		# this, the going-second player's skip-draw flag would push its +1 refill
		# to turn 2 while the going-first player enjoys it from turn 1.
		var predeal: int = combat.HAND_REFILL_TARGET
		if combat._has_relic("deep_satchel"):
			predeal += int(RelicDB.get_relic("deep_satchel").get("value", 1))
		for _i in predeal:
			combat.draw_one()
		# _draw_card adds the Coin as a synthetic hand card (uid -1) so it never enters
		# a draw/discard pile or reshuffles — it just vanishes once cast.
		combat._draw_card("coin")
		combat._net_skip_draw_this_round = true
		combat._layout_hand()
		# Share the pre-dealt opening hand so the opponent's foe-readout is correct.
		_net_broadcast_hand_count()
		combat._show_info("Skirmish — the foe marches first. Your opening turn will STRIKE.")
	# (attach_combat already ran ahead of the toss above — the buffered-message
	# replay that used to live here rides that earlier call; see NetMatch.attach_combat.)
	# Only the HOST drives the authoritative turn machine — but it opens the match for
	# WHOEVER the coin flip chose (first_index), host or client alike.
	if combat._is_host():
		# Practice bot: deal its opening hand now so the human sees the opponent
		# holding cards through the opener (the +1 going-second card is folded into
		# _bot_refill_hand only when the bot is the side going second — no double draw
		# when its first _bot_take_turn tops the same hand up to the same target), and
		# warm its deck's card faces (fire-and-forget — ready by the bot's first play).
		if SkirmishState.vs_bot:
			_bot_refill_hand()
			_bot_sync_hand_display()
			_net_prebake_bot_textures()
		await combat.get_tree().create_timer(0.6).timeout
		_net_begin_round(1)




## The toss modal: the coin-flip winner picks the ground. Awaitable; returns
## true = MARCH FIRST, false = HOLD BACK (go second). Mouse-only like the rest
## of the game; lives on its own CanvasLayer so it sits above board and hand.
func _net_show_order_choice() -> bool:
	var layer := CanvasLayer.new()
	layer.layer = 30
	combat.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -330
	col.offset_right = 330
	col.offset_top = -240
	col.offset_bottom = 240
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	dim.add_child(col)
	var title = GameTheme.make_label("YOU WON THE TOSS", 34, GameTheme.GILT_BRIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub = GameTheme.make_label("Choose the ground.", 18, GameTheme.DESC_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var picked: Array = [-1]
	for opt in [
		["MARCH FIRST", "Dictate the opening line — you act first every round.", 1],
		["HOLD BACK", "See their line before yours, keep the Coin — and your first turn STRIKES.", 0],
	]:
		var btn = GameTheme.make_themed_button(String(opt[0]),
			Color(0.14, 0.10, 0.05), Vector2(560, 64), 22)
		btn.pressed.connect(func():
			picked[0] = int(opt[2])
			layer.queue_free())
		col.add_child(btn)
		var line = GameTheme.make_label(String(opt[1]), 15, GameTheme.IVORY)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(540, 0)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(line)
		GameTheme.hover_lift(btn)
	GameTheme.deal_in(col, 0.05)
	while picked[0] < 0:
		await combat.get_tree().process_frame
	return picked[0] == 1




## HOST: open a new combat ROUND. Both players take a placement turn (opener first,
## then the other side), each striking one-directionally as its turn ends.
## The coin-flip winner opens EVERY round, so turns strictly alternate
## (P0, P1, P0, P1 …). We used to flip the opener each round — but with a "round"
## being BOTH players' placements, that made whoever placed second also place first
## the next round: two turns back-to-back at every round boundary, which read as a
## confusing "extra turn" (you commit your line and, instead of the foe answering,
## you just go again). Going first is the tempo edge; the going-second player's
## one-time Coin is the compensation — the standard card-game model.
func _net_begin_round(round_no: int) -> void:
	if combat._net_match_over or not combat._is_host():
		return
	combat._net_turn_round = round_no
	combat._net_first_placer = combat._net_first_player()   # fixed opener → strict alternation
	combat._net_placed_count = 0
	_net_open_placement(combat._net_first_placer)




# ═══════════════════════════════════════════════════════════════════════════
#  SEALED ORDERS battle style (plan §16.2)
#  Round = ORDERS (both place simultaneously in private; the foe sees only
#  face-down ghosts at lane positions) → REVEAL (host seats both bundles,
#  initiative side first) → SORCERY (two sequential open spell steps) →
#  CLASH (_net_run_clash(-1), the verified simultaneous pass). Perfect
#  symmetry: no opener, no Coin. Initiative = seed coin flip, alternates.
# ═══════════════════════════════════════════════════════════════════════════



func _is_sealed() -> bool:
	return combat._is_net() and NetMatch.battle_style == NetMatch.STYLE_SEALED




func _sealed_in_orders() -> bool:
	return _is_sealed() and combat.phase == combat.Phase.PLAYER_TURN \
		and combat._sorcery_active < 0 and not combat._sealed_await_foe




## HOST: open a sealed round — both sides give orders at once.
func _sealed_begin_round(round_no: int) -> void:
	if combat._net_match_over or not combat._is_host():
		return
	combat._net_turn_round = round_no
	if round_no <= 1:
		combat._net_initiative = combat._net_first_player()
	else:
		combat._net_initiative = 1 - combat._net_initiative
	combat._sealed_bundles.clear()
	combat._sorcery_active = -1
	combat._sorcery_passes = 0
	combat._net_active_index = -1   # nobody "has the turn" — the existing turn gates
							 # (client creature/spell paths) block by construction
	NetMatch.send_to_client({"t": NetMatch.EV_ORDERS_PHASE,
		"round": round_no, "init": combat._net_initiative})
	# Host-authoritative per-round passives for the CLIENT side (its local
	# _start_round is non-authoritative) — same contract as _net_open_placement.
	combat._apply_start_round_passives(true)
	_sealed_open_orders_local()
	_net_sync_board()
	if SkirmishState.vs_bot:
		_bot_sealed_orders()




## BOTH machines: enter the orders phase locally (draw + Command + private board).
func _sealed_open_orders_local() -> void:
	combat.phase = combat.Phase.PLAYER_TURN
	combat._sealed_pending.clear()
	combat._sealed_await_foe = false
	combat._sorcery_active = -1
	combat._moves_used_this_turn = 0
	combat._net_spells_this_turn = 0
	combat._start_round()
	Card2D.board_interactive = false   # no reposition drags in sealed v1
	Card2D.hand_interactive = true     # both sides give orders at once
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = false
		combat._end_turn_btn.text = "SEAL ORDERS  [E]"
	var init_line: String = "You hold the initiative." \
		if combat._net_initiative == NetMatch.local_player_index else "The foe holds the initiative."
	combat._show_combat_banner("SEALED ORDERS", "Set your line in secret — " + init_line,
		Color(0.98, 0.86, 0.55))
	if AudioBank != null:
		AudioBank.play_sfx("turn_start", 0.03, -2.0)
	combat._show_info("Round %d — orders are sealed until both sides commit." % combat._net_turn_round)
	_net_broadcast_hand_count()




## A creature play during the orders phase: a PRIVATE commitment. Nothing crosses
## the wire but a face-down ghost at the lane; the bundle ships at SEAL.
func _sealed_commit_creature(card: Control, cost: int, lane_idx: int, row: int) -> void:
	var uid: int = card.deck_uid
	var cid: String = card.card_id
	var data: Dictionary = card.card_data.duplicate(true)
	combat.player_mana -= cost
	combat._pulse_mana_label(cost)
	combat._hand.erase(card)
	combat._hand_container.remove_child(card)
	card.queue_free()
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# Display-only stand-in: seats visually + occupies the row array (so a second
	# order can't take the slot) but is NOT registered / entered — the reveal frees
	# it and the authoritative spawn takes its place. _net_sync_board skips it.
	var stand: Control = combat.CARD_SCENE.instantiate()
	stand.card_id = cid
	stand.is_on_battlefield = true
	stand.compact_mode = true
	stand.card_data = data
	stand.current_lane = lane_idx
	stand.current_row = row
	stand.set_meta("sealed_pending", true)
	combat._row_array(false, row)[lane_idx] = stand
	combat._slot_set_card(combat._slot_array(false, row)[lane_idx], stand)
	combat._play_landing_pop(stand)
	combat._sealed_pending.append({"id": cid, "uid": uid, "lane": lane_idx, "row": row, "node": stand})
	# The foe learns only WHERE: a face-down ghost at the slot.
	if combat._is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_ORDER_GHOST, "lane": lane_idx, "row": row})
	else:
		NetMatch.send_intent({"t": NetMatch.IN_ORDER_GHOST, "lane": lane_idx, "row": row})
	_net_broadcast_hand_count()
	combat._layout_hand()
	combat._update_hud()




## The foe committed an order at {lane,row} — show a face-down card back there.
func _sealed_show_ghost(lane: int, row: int) -> void:
	if lane < 0 or lane >= combat.LANES_PER_ROW or row < combat.ROW_FRONT or row > combat.ROW_BACK:
		return
	if combat._net_card_back_tex == null:
		combat._net_card_back_tex = load("res://assets/ui/card_back.png") as Texture2D
	var slot: Control = combat._slot_array(true, row)[lane]
	if slot == null or not is_instance_valid(slot) or combat._net_card_back_tex == null:
		return
	var g := TextureRect.new()
	g.texture = combat._net_card_back_tex
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.size = Vector2(104, 136)
	g.global_position = slot.get_global_rect().get_center() - g.size * 0.5
	g.z_index = 5
	g.modulate.a = 0.0
	var g_parent: Node = combat._hud_layer if combat._hud_layer != null else combat
	g_parent.add_child(g)
	var tw: Tween = g.create_tween()
	tw.tween_property(g, "modulate:a", 0.92, 0.2)
	combat._sealed_ghosts.append(g)




## The button in sealed play: SEAL ORDERS during the orders phase, PASS in sorcery.
func _sealed_on_button() -> void:
	if combat._net_match_over:
		return
	if combat._sorcery_active >= 0:
		if combat._sorcery_active != NetMatch.local_player_index:
			return
		# Cards marked during the open spell step discard as we pass.
		combat._flush_marked_discards()
		if combat._end_turn_btn != null:
			combat._end_turn_btn.disabled = true
		if combat._is_host():
			_sealed_sorcery_pass(0)
		else:
			NetMatch.send_intent({"t": NetMatch.IN_SORCERY_PASS})
		return
	if combat._sealed_await_foe or combat.phase != combat.Phase.PLAYER_TURN:
		return
	# Marked discards leave with the sealed orders (hand-local, so the foe
	# learns the count — never the faces — via the fx beat inside the flush).
	combat._flush_marked_discards()
	combat._sealed_await_foe = true
	# Orders committed — lock the hand until the reveal / your spell step.
	Card2D.hand_interactive = false
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = true
		combat._end_turn_btn.text = "AWAITING THE FOE"
	var list: Array = []
	for p in combat._sealed_pending:
		list.append({"id": p.id, "uid": p.uid, "lane": p.lane, "row": p.row})
	combat._show_info("Orders sealed. Awaiting the foe…")
	if combat._is_host():
		_sealed_store_bundle(0, list, combat.player_mana)
	else:
		NetMatch.send_intent({"t": NetMatch.IN_ORDERS, "list": list, "mana": combat.player_mana})




## HOST: hold a side's sealed bundle; reveal once both are in.
func _sealed_store_bundle(side: int, list: Array, unspent: int) -> void:
	if not combat._is_host() or combat._net_match_over:
		return
	if combat._sealed_bundles.has(side):
		return   # duplicate seal — ignore
	combat._sealed_bundles[side] = {"list": list, "mana": unspent}
	if combat._sealed_bundles.size() >= 2:
		await _sealed_reveal()




## HOST: both bundles are in — the orders break open. Initiative side's whole
## bundle seats first (deterministic on-enter order), through the SAME
## authoritative spawn path client plays already use.
func _sealed_reveal() -> void:
	if not combat._is_host() or combat._net_match_over:
		return
	combat.phase = combat.Phase.RESOLVING
	NetMatch.send_to_client({"t": NetMatch.EV_REVEAL})
	_sealed_clear_pending_local()
	combat._show_combat_banner("THE ORDERS BREAK OPEN", "", Color(1.0, 0.78, 0.35))
	if AudioBank != null:
		AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
	combat._net_cards_played[0] = 0
	combat._net_cards_played[1] = 0
	for side in [combat._net_initiative, 1 - combat._net_initiative]:
		var b: Dictionary = combat._sealed_bundles.get(side, {})
		# Condottiere reads the caster's unspent pool: the client's rides its
		# bundle; the host's own pool is live in player_mana.
		combat._net_client_unspent_mana = int(b.get("mana", 0)) if side == 1 else 0
		for o_raw in b.get("list", []):
			var o: Dictionary = o_raw
			var data := SkirmishState.skirmish_card_data(String(o.get("id", "")))
			if data.is_empty():
				continue
			var lane := int(o.get("lane", -1))
			var row = int(o.get("row", combat.ROW_FRONT))
			if lane < 0 or lane >= combat.LANES_PER_ROW or row < combat.ROW_FRONT or row > combat.ROW_BACK:
				continue
			if combat._row_array(side == 1, row)[lane] != null:
				continue   # conflicting/stale order — dropped (host is authoritative)
			combat._net_cards_played[side] += 1
			_net_spawn_creature(data, int(o.get("uid", _net_issue_token_id())),
				lane, row, side == 1, true)
			await combat._short_pause(0.12)
	_net_sync_board()
	await combat._short_pause(combat.COMBAT_PAUSE_SHORT)
	if combat._net_match_over:
		return   # an on-enter chain ended it
	_sealed_open_sorcery()




## BOTH machines: drop my pending stand-ins + the foe's ghosts. The authoritative
## board arrives via the reveal spawns (host) / trailing snapshot (client).
func _sealed_clear_pending_local() -> void:
	for g in combat._sealed_ghosts:
		if g != null and is_instance_valid(g):
			g.queue_free()
	combat._sealed_ghosts.clear()
	for p in combat._sealed_pending:
		var n = p.get("node")
		if n != null and is_instance_valid(n):
			var r: int = int(p.get("row", 0))
			var l: int = int(p.get("lane", 0))
			if combat._row_array(false, r)[l] == n:
				combat._row_array(false, r)[l] = null
			n.queue_free()
	combat._sealed_pending.clear()
	combat._sealed_await_foe = false




## HOST: open the sorcery window — two sequential open spell steps, initiative first.
## (Sequential, not per-cast alternation: caster-local spells never reach the host,
## so only the explicit PASS can end a step.)
func _sealed_open_sorcery() -> void:
	if not combat._is_host() or combat._net_match_over:
		return
	combat._sorcery_passes = 0
	_sealed_set_sorcery(combat._net_initiative)
	NetMatch.send_to_client({"t": NetMatch.EV_SORCERY, "who": combat._net_initiative})
	if SkirmishState.vs_bot and combat._net_initiative == 1:
		_bot_sealed_sorcery()




## BOTH machines: reflect whose spell step is open.
func _sealed_set_sorcery(who: int) -> void:
	combat._sorcery_active = who
	combat.phase = combat.Phase.PLAYER_TURN
	combat._net_active_index = who   # the existing "not your turn" spell gates now work
	var mine: bool = who == NetMatch.local_player_index
	# Only the caster whose spell step is open may play from hand.
	Card2D.hand_interactive = mine
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = not mine
		combat._end_turn_btn.text = "PASS  [E]"
	if mine:
		combat._set_phase_caption("YOUR SPELL STEP")
		combat._show_info("Your spell step — cast freely over the revealed lines, then pass.")
	else:
		combat._set_phase_caption("FOE'S SPELL STEP")
		combat._show_info("The foe weighs its spells…")




## HOST: a side passed its spell step. Second pass → the lines clash.
func _sealed_sorcery_pass(side: int) -> void:
	if not combat._is_host() or combat._net_match_over or combat._sorcery_active != side:
		return
	combat._sorcery_passes += 1
	if combat._sorcery_passes >= 2:
		combat._sorcery_active = -1
		combat._net_active_index = -1
		await _net_run_clash(-1)
		if not combat._net_match_over:
			_sealed_begin_round(combat._net_turn_round + 1)
		return
	var nxt: int = 1 - side
	_sealed_set_sorcery(nxt)
	NetMatch.send_to_client({"t": NetMatch.EV_SORCERY, "who": nxt})
	if SkirmishState.vs_bot and nxt == 1:
		_bot_sealed_sorcery()




## Practice bot, sealed style: build its bundle from the same heuristic the
## alternating bot uses, ping ghosts as it "commits", then seal.
func _bot_sealed_orders() -> void:
	if not SkirmishState.vs_bot or combat._net_match_over:
		return
	await combat._short_pause(0.8)
	_bot_refill_hand()
	var mana: int = SkirmishState.BASE_MAX_MANA + combat._bot_banked_mana
	_bot_sync_hand_display(mana)
	var plays: Array = SkirmishBot.decide_turn(combat, combat._bot_hand, mana)
	var list: Array = []
	var spent := 0
	for intent in plays:
		if String(intent.get("t", "")) != NetMatch.IN_PLAY_CREATURE:
			continue   # v1: the sealed bot fields creatures only
		var lane := int(intent.get("lane", -1))
		var row = int(intent.get("row", combat.ROW_FRONT))
		spent += _bot_consume_card(int(intent.get("uid", -1)))
		_bot_sync_hand_display(mana - spent)
		list.append({"id": String(intent.get("id", "")),
			"uid": int(intent.get("uid", -1)), "lane": lane, "row": row})
		_sealed_show_ghost(lane, row)
		await combat._short_pause(0.25)
	combat._bot_banked_mana = clampi(mana - spent, 0, combat.MAX_BANKED_MANA)
	combat._bot_turns_taken += 1
	await combat._short_pause(0.5)
	_sealed_store_bundle(1, list, mana - spent)




func _bot_sealed_sorcery() -> void:
	await combat._short_pause(0.5)
	_sealed_sorcery_pass(1)   # v1: the bot casts no spells in the window




## HOST: open a PLACEMENT turn for `active_index` (0 = host, 1 = client) and tell the
## client. The placer develops their board; ending the turn sends THEIR line across
## the board (one-directional — see _net_finish_placement; round 1 is place-only).
func _net_open_placement(active_index: int) -> void:
	if combat._net_match_over or not combat._is_host():
		return
	combat._net_active_index = active_index
	combat.phase = combat.Phase.PLAYER_TURN
	# Reset the host-side reposition budget so it tracks WHOEVER is active this
	# turn (the host's own turns also reset it via _start_round; this covers the
	# client's turns, where the host validates the client's reposition intents).
	combat._moves_used_this_turn = 0
	combat._net_spells_this_turn = 0   # per-turn spell tally (flame_bolt combo)
	combat._net_last_spell_data = {}   # Echo only reaches back within the current turn
	combat._net_last_spell_target_eid = -1
	# Per-turn passive counters for the side whose turn is opening (Ironclad's cards-
	# this-turn).
	combat._net_cards_played[active_index] = 0
	NetMatch.send_to_client({
		"t": NetMatch.EV_TURN_BEGIN, "active": active_index, "round": combat._net_turn_round,
	})
	if active_index == 0:
		_net_local_turn_begin()
	else:
		_net_set_local_active(false)
		combat._show_info(_net_opp_turn_msg())
		# Host-authoritative per-round passive recompute for the CLIENT's side — its own
		# _start_round runs non-authoritatively, so the host applies Riteforge/Warchief
		# for Player 2 here and the snapshot below carries the result.
		combat._apply_start_round_passives(true)
	_net_sync_board()
	# Practice bot: no remote client will send intents for slot 1 — drive it locally.
	if SkirmishState.vs_bot and active_index == 1 and not combat._net_match_over:
		_bot_take_turn()




## HOST: the active side finished its turn. ALTERNATING battle style — ending
## YOUR turn sends YOUR line across the board (one-directional; the defender
## answers on its own turn). Round 1 is place-only for BOTH sides: the opener
## can't free-hit an empty board, and the second player gets the first
## contested strike on round 2 (alongside the Coin). The both-sides
## simultaneous pass lives on as _net_run_clash(-1) for the SEALED style.
func _net_finish_placement(who: int) -> void:
	if combat._net_match_over or not combat._is_host():
		return
	if combat._net_active_index != who:
		return   # stale / duplicate DONE — ignore
	combat._net_placed_count += 1
	# Every DONE strikes EXCEPT the opener's very first (an empty opposing board
	# would mean free face hits). The second player's first turn is de facto
	# turn 2 — the foe's line is already standing — so it fights like one
	# (2026-07-11; round 1 used to be place-only for both sides).
	if combat._net_turn_round > 1 or combat._net_placed_count >= 2:
		await _net_run_clash(who)
	if combat._net_match_over:
		return
	if combat._net_placed_count < 2:
		_net_open_placement(1 - who)
	else:
		_net_begin_round(combat._net_turn_round + 1)




## Runs on whichever side just became active: draw + Command + enable the board.
func _net_local_turn_begin() -> void:
	_net_set_local_active(true)
	# The handoff is a felt beat, not just an info line: banner sweep + the turn
	# horn. Runs on whichever machine just became active (host 1st-turn included);
	# solo never routes through here.
	combat._show_combat_banner("YOUR TURN", "", Color(0.98, 0.86, 0.55))
	if AudioBank != null:
		AudioBank.play_sfx("turn_start", 0.03, -2.0)
	# _start_round = the per-turn draw + Command + banking. Its solo-only tail
	# (enemy intents on the mirrored opponent, waves, boss phases) is inert here.
	combat._start_round()
	# The active player may reposition this turn — _start_round already re-enabled
	# board_interactive.
	Card2D.board_interactive = true
	# The button names its consequence (mirrors solo's CLASH label): every turn
	# ends in a strike EXCEPT the opener's first — the second player's opening
	# turn already faces a standing line, so it strikes too.
	if combat._end_turn_btn != null:
		var will_strike: bool = combat._net_turn_round > 1 \
			or combat._net_goes_second(NetMatch.local_player_index)
		combat._end_turn_btn.text = "STRIKE  [E]" if will_strike else "DONE  [E]"
	_net_broadcast_hand_count()




## CLIENT: react to the host's turn-begin event.
func _net_client_turn_begin(active: int, rnd: int) -> void:
	combat._net_active_index = active
	combat._net_turn_round = rnd
	if active == NetMatch.local_player_index:
		_net_local_turn_begin()
	else:
		_net_set_local_active(false)
		combat._show_info(_net_opp_turn_msg())




func _net_set_local_active(active: bool) -> void:
	# The active player may reposition their own board creatures (board_interactive);
	# the inactive player's board is locked. Hand plays + spell targeting still
	# route through _input regardless.
	Card2D.board_interactive = active
	# Lock the HAND on the foe's turn: cards can't be lifted (hand_interactive)
	# and _refresh_hand_affordability greys them all, so you can't try to spend
	# Command while it isn't your turn.
	Card2D.hand_interactive = active
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = not active
	if active:
		combat.phase = combat.Phase.PLAYER_TURN




# ── DONE / CLASH (the end-turn button's skirmish role) ───────────────────

## The DONE / STRIKE button commits THIS side's turn. Every commit fires the
## one-directional clash for the committing side EXCEPT the opener's very first
## turn (empty opposing board = free face hits); the second player's first turn
## faces a standing line, so it strikes like any other.
func _net_on_done_placing() -> void:
	# Sealed style: the button is SEAL ORDERS / PASS, never a turn hand-off.
	if _is_sealed():
		_sealed_on_button()
		return
	if combat._net_match_over or combat._net_active_index != NetMatch.local_player_index:
		return
	# Marked discards cash out as the turn is committed (hand-local; the foe
	# gets the EV_DISCARD_FX beat + hand-count tick from inside the flush).
	combat._flush_marked_discards()
	if combat._net_turn_round > 1 or combat._net_goes_second(NetMatch.local_player_index):
		combat._play_clash_commit_vfx()
	if combat._is_host():
		_net_finish_placement(0)
	else:
		_net_set_local_active(false)
		combat._show_info("Ready — waiting for the clash…")
		NetMatch.send_intent({"t": NetMatch.IN_END_ACTIONS})




# ── Clash replay log (host → EV_CLASH → client paced replay) ─────────────
#  The client never runs the clash resolver — before this channel it watched the
#  fight as one-frame board snapshots while the host got the full sequenced
#  cinematic (lunges, paced blows, kill cues). While _net_clash_recording is on,
#  the strike funnels log one entry per beat; _net_send_clash_log ships each
#  segment AHEAD of its outcome snapshot so the client replays the fight first
#  and the deaths still flush with the trailing sync (the deferred-deaths feel).
#  Entry shapes: {l} attacker lunge · {a,o,ahp,d,hp,n} creature hit (post-
#  mitigation HP is authoritative — Armored/Shield/Poison math ships pre-solved;
#  ahp carries Thorns/self-bite chip) · {f,fhp,n} face hit by owner index.
# Cross-Blitz mutual trade: true only during the MP one-directional MAIN clash, so
# a struck defender hits its attacker straight back (see _apply_mutual_retaliation).
# Solo/sealed are already simultaneous, so this stays false there.


func _net_log_lunge(attacker: Control) -> void:
	if not combat._net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return   # mid-clash tokens have no eid yet — the snapshot reconciles them
	# "latk" = the swing's weight, so the client's replay lunges with the same
	# drive (effective_atk is close enough to the host's lane-aware value for a
	# purely cosmetic scale).
	var entry := {"l": int(attacker.entity_id)}
	if attacker.has_method("effective_atk"):
		entry["latk"] = int(attacker.effective_atk())
	combat._net_clash_log.append(entry)




func _net_arm_face_hit_source(attacker: Control, lane_idx: int, power: int = -1) -> void:
	combat._net_face_hit_source.clear()
	if not combat._net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return
	combat._net_face_hit_source = {
		"a": int(attacker.entity_id),
		"o": 1 if attacker.is_opponent else 0,
		"lane": lane_idx,
	}
	if power > 0:
		combat._net_face_hit_source["p"] = power




func _net_clear_face_hit_source() -> void:
	combat._net_face_hit_source.clear()




func _net_enrich_face_hit(entry: Dictionary) -> Dictionary:
	if not combat._net_face_hit_source.is_empty():
		entry.merge(combat._net_face_hit_source, true)
	return entry




func _net_log_hit(attacker: Control, defender: Control, hp_before: int, is_counter: bool = false) -> void:
	if not combat._net_clash_recording:
		return
	if defender == null or not is_instance_valid(defender) or int(defender.entity_id) < 0:
		return
	var entry := {
		"d": int(defender.entity_id),
		"hp": int(defender.current_hp),
		"n": maxi(0, hp_before - int(defender.current_hp)),
	}
	if attacker != null and is_instance_valid(attacker) and int(attacker.entity_id) >= 0:
		entry["a"] = int(attacker.entity_id)
		entry["o"] = 1 if attacker.is_opponent else 0
		entry["ahp"] = int(attacker.current_hp)
	# Counter (Cross-Blitz return blow): the victim is the still-lunging attacker, so
	# the client must NOT play a position recoil on it (it would fight the lunge tween
	# and drift the card) — the flash from the hit is enough. See _net_replay_creature_hit.
	if is_counter:
		entry["ctr"] = true
	combat._net_clash_log.append(entry)




## Log the sub-phase caption the host flips mid-clash (only THE DOUBLED HOUR reaches
## the net clash) so the client's phase line matches instead of going blank.
func _net_log_caption(text: String) -> void:
	if combat._net_clash_recording:
		combat._net_clash_log.append({"cap": text})




## Log a piercing kill's skewer so the client draws the same lance. Both eids survive
## the beat (attacker lives through a pierce; victim isn't flushed until the snapshot),
## so the client can reconstruct the lance from its own card centres.
func _net_log_pierce(attacker: Control, victim: Control) -> void:
	if not combat._net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return
	if victim == null or not is_instance_valid(victim) or int(victim.entity_id) < 0:
		return
	combat._net_clash_log.append({"pl": int(attacker.entity_id), "pv": int(victim.entity_id)})




## Buffer a floating text callout (e.g. a warden's "+N ATK" pump) onto a creature by
## eid so it replays on the client via the fx channel — the host spawns these at world
## positions the client can't reuse. Rides the next board sync like every other fx.
func _net_fx_text(creature: Control, label: String, color: Color) -> void:
	if not combat._is_host() or creature == null or not is_instance_valid(creature):
		return
	if int(creature.entity_id) < 0:
		return
	combat._net_fx_queue.append({
		"eid": int(creature.entity_id), "label": label,
		"col": [color.r, color.g, color.b],
	})




## HOST: a creature just cheated death via Last Stand (Card2D's flare site calls
## this through the net_last_stand_cb static hook). The chip + overbright flare are
## Card2D-local — host screen only — so mirror the moment over the fx channel;
## _net_replay_fx special-cases the label to reproduce the same presentation
## (icon pill + _play_last_stand_flare) on the client's copy of the survivor.
func _net_on_last_stand_saved(card: Control) -> void:
	_net_fx_text(card, "LAST STAND", Color(1.0, 0.85, 0.20))




# Which side is striking in the pass being recorded (-1 = both, simultaneous).
# Shipped with each EV_CLASH so the client's banner names the striker.

func _net_send_clash_log() -> void:
	combat._net_clash_recording = false
	if combat._net_clash_log.is_empty():
		return
	if combat._is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_CLASH,
			"strikes": combat._net_clash_log.duplicate(true),
			"atk": combat._net_clash_attacking_side,
			"banner": not combat._net_clash_banner_sent})
		combat._net_clash_banner_sent = true
	combat._net_clash_log.clear()




## HOST: the attack pass. In the both-sides form (-1) every attacker lands its
## blow and a creature slain by the first striker still retaliates (Card2D.defer_deaths
## holds deaths until the phase flushes), so nobody gets a de-facto Swift. This is the
## net analogue of solo's _do_combat clash: Swift pre-phase, main column strike, then
## Ranged. Thorns / Piercing / Armored / Last Stand / Lifesteal / Rampage
## / on-death all come free from the shared campaign resolvers.
## Resolve an attack pass. attacking_side: -1 = BOTH sides strike simultaneously
## (the SEALED battle style's resolution + the pre-2026-07 legacy clash);
## 0 (host) / 1 (client) = ONE-DIRECTIONAL — only that side's creatures attack,
## the defender answers on its own turn (the ALTERNATING battle style).
func _net_run_clash(attacking_side: int = -1) -> void:
	if combat._net_match_over or not combat._is_host():
		return
	combat.phase = combat.Phase.RESOLVING
	Card2D.board_interactive = false
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = true
	if attacking_side < 0:
		combat._show_info("The lines clash!")
	elif attacking_side == 0:
		combat._show_info("Your line strikes!")
	else:
		combat._show_info("The foe's line strikes!")
	# Clash replay: from here every strike beat is logged for the client's paced
	# replay (see the EV_CLASH block above). Recording stays on through each
	# segment's death flush so on-death face chips keep their place in the reel.
	combat._net_clash_log.clear()
	combat._net_clash_banner_sent = false
	combat._net_clash_attacking_side = attacking_side
	combat._net_clash_recording = true
	# Adjacency current before the strike math reads effective_atk for both warbands.
	combat._refresh_adjacency_buffs()
	# Stunned/frozen creatures forfeit their swing (can_attack honours is_frozen
	# but not stunned — mirror solo's _do_combat pre-mark). Only sides that will
	# actually swing are pre-marked: marking the passive defender would hand its
	# stunned Twinblades a phantom "already attacked" flag.
	var host_strikes: bool = attacking_side != 1
	var client_strikes: bool = attacking_side != 0
	if host_strikes:
		_net_premark_skip_attack(false)
	if client_strikes:
		_net_premark_skip_attack(true)
	# Cross-Blitz mutual trade (ONE-DIRECTIONAL passes only): a struck defender fires
	# its ATK straight back at its attacker in the same beat, so evenly-matched
	# creatures trade and both fall — matching solo's simultaneous clash instead of
	# handing the turn player a free first-strike kill. Each defender counters ONCE
	# per clash (its single swing); reset the per-clash latch here.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			c.remove_meta("counter_spent_this_clash")
	# Snapshot which columns had a front-row blocker at clash start (face-damage rule).
	# is_enemy=false is the HOST/player side (0); is_enemy=true is the CLIENT side (1).
	var player_front_empty: Array[bool] = []
	var enemy_front_empty: Array[bool] = []
	for i in range(combat.LANES_PER_ROW):
		player_front_empty.append(combat._row_array(false, combat.ROW_FRONT)[i] == null)
		enemy_front_empty.append(combat._row_array(true, combat.ROW_FRONT)[i] == null)
	var net_swift_queued := false
	for c in combat._all_creatures_both_sides():
		if not is_instance_valid(c):
			continue
		var c_side_strikes: bool = client_strikes if c.is_opponent else host_strikes
		if c_side_strikes and combat._is_swift_attacker(c) and c.can_attack() and not c.has_attacked_this_turn:
			net_swift_queued = true
			break
	if net_swift_queued:
		combat._set_phase_caption("SWIFT STRIKES")
		_net_log_caption("SWIFT STRIKES")
	# SWIFT PHASE — striking sides only, deaths HELD so Swift-vs-Swift trades
	# (see _do_combat).
	Card2D.defer_deaths = true
	for lane_idx in range(combat.LANES_PER_ROW):
		if host_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_FRONT, false, enemy_front_empty)
		if client_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_FRONT, true, player_front_empty)
	for lane_idx in range(combat.LANES_PER_ROW):
		if host_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_BACK, false, enemy_front_empty)
		if client_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_BACK, true, player_front_empty)
	Card2D.defer_deaths = false
	combat._cleanup_dead()
	_net_send_clash_log()   # ship the Swift beats AHEAD of their outcome snapshot
	_net_sync_board()   # let the client see the Swift results before the main clash
	combat._net_clash_recording = true
	combat._set_phase_caption("CLASH")
	_net_log_caption("CLASH")
	# MAIN PASS — striking sides per lane, deaths HELD so mutual kills drop both.
	# In a one-directional pass this is where the Cross-Blitz counterstrike lives:
	# the struck defender hits back inside _creature_attacks_creature (gated below).
	# A both-sides pass (sealed) is already simultaneous, so it stays off there.
	combat._net_mutual_retaliation = attacking_side >= 0
	Card2D.defer_deaths = true
	for lane_idx in range(combat.LANES_PER_ROW):
		if host_strikes:
			await combat._resolve_column_attack(lane_idx, combat.ROW_FRONT, false, enemy_front_empty)
		if client_strikes:
			await combat._resolve_column_attack(lane_idx, combat.ROW_FRONT, true, player_front_empty)
	for lane_idx in range(combat.LANES_PER_ROW):
		if host_strikes:
			await combat._resolve_column_attack(lane_idx, combat.ROW_BACK, false, enemy_front_empty)
		if client_strikes:
			await combat._resolve_column_attack(lane_idx, combat.ROW_BACK, true, player_front_empty)
	combat._net_mutual_retaliation = false
	Card2D.defer_deaths = false
	combat._cleanup_dead()
	# THE DOUBLED HOUR / Ranged: in a one-directional pass the DEFENDER's armed
	# Doubled Hour must not fire (it swings on its own turn) — stash its flag
	# around the shared helpers. Twinblade + Berserker self-filter (they key on
	# has_attacked_this_turn, which only strikers carry).
	var _dh_stash: bool = false
	if attacking_side >= 0:
		_dh_stash = combat._doubled_hour[1 - attacking_side]
		combat._doubled_hour[1 - attacking_side] = false
	await combat._run_doubled_hour_swing(player_front_empty, enemy_front_empty)
	# Twinblade — second swings (shared helper with solo).
	await combat._run_twinblade_swings(player_front_empty, enemy_front_empty)
	# Ranged archers reach over the line (side_filter -1 = everyone).
	await combat._resolve_ranged_attacks(attacking_side)
	await combat._run_doubled_hour_snipe()
	if attacking_side >= 0:
		combat._doubled_hour[1 - attacking_side] = _dh_stash
	# Berserker growth — scan both rows on both sides. `grow` = per-attack ATK gain.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c) and c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
			c.current_atk += int(c.card_data.get("grow", 1))
			c.update_stat_display()
	combat._cleanup_dead()
	# Clear per-turn attack flags so both sides can swing again next round.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			c.has_attacked_this_turn = false
	# Decay per-round temp states (stun, freeze, the Charge! rider, temp Poison).
	# One-directional pass: only the STRIKING side's turn is ending, so only its
	# states expire — the defender's freeze/stun must hold through the strike it
	# was cast to deny. Both-sides pass: everyone's round ends together.
	if host_strikes:
		_net_decay_side_states(false)
	if client_strikes:
		_net_decay_side_states(true)
	# Assassin (dies_end_of_turn): dies when ITS OWN side's turn ends — striking
	# sides only. Collected first so deaths don't mutate the array mid-iterate.
	var _eot_dying: Array = []
	for _ase in combat._all_creatures_both_sides():
		if not is_instance_valid(_ase):
			continue
		if _ase.card_data.get("passive", "") != "dies_end_of_turn":
			continue
		var _ase_side_strikes: bool = client_strikes if _ase.is_opponent else host_strikes
		if _ase_side_strikes:
			_eot_dying.append(_ase)
	for _ase in _eot_dying:
		if is_instance_valid(_ase):
			_ase.take_damage(999)
	if not _eot_dying.is_empty():
		combat._cleanup_dead()
	await combat._short_pause(combat.COMBAT_PAUSE_SHORT)
	_net_send_clash_log()   # ship the main-clash beats AHEAD of the final snapshot
	combat._update_hud()
	_net_sync_board()
	_net_host_check_match_over()
	# Flow control (whose turn / which round comes next) belongs to the CALLER:
	# the alternating style strikes mid-round at each turn's end, the sealed
	# style clashes once per round — neither wants a round advance baked in here.




## Stunned/frozen creatures forfeit their swing. can_attack() honours is_frozen but
## NOT stunned, so mirror solo's _do_combat pre-mark for the active side here.
func _net_premark_skip_attack(is_enemy: bool) -> void:
	for c in combat._all_friendly(is_enemy):
		if is_instance_valid(c) and (c.state.stunned or c.state.is_frozen):
			c.has_attacked_this_turn = true




## End-of-turn temp-state decay for ONE side — the full-alternating net analogue of
## solo's _post_combat_cleanup. In net each side attacks on its own turn, so a
## creature's per-turn states expire when ITS side finishes attacking (the moment it
## would have swung): stun, freeze, the Charge! rider, and temp Poison.
func _net_decay_side_states(is_enemy: bool) -> void:
	# Round-scoped side flags (Unclean Blessing / The Doubled Hour) expire with
	# the clash they were cast for.
	combat._virulence_active[1 if is_enemy else 0] = false
	combat._doubled_hour[1 if is_enemy else 0] = false
	for c in combat._all_friendly(is_enemy):
		if not is_instance_valid(c):
			continue
		c.state.stunned = false
		c.state.is_frozen = false
		if c.get_meta("temp_poison", false):
			c.card_data.keywords.erase("poison")
			c.remove_meta("temp_poison")
			c.update_stat_display()
		if c.has_meta("charges_this_turn"):
			c.remove_meta("charges_this_turn")




## HOST: declare the match over if a hero has fallen. Idempotent.
func _net_host_check_match_over() -> void:
	if combat._net_match_over:
		return
	if combat.player_hp > 0 and combat.enemy_hp > 0:
		return
	# winner by GLOBAL index: host = 0 (player side), client = 1 (enemy side).
	var winner: int = -1
	if combat.player_hp <= 0 and combat.enemy_hp <= 0:
		winner = -1
	elif combat.enemy_hp <= 0:
		winner = 0
	else:
		winner = 1
	NetMatch.send_to_client({"t": NetMatch.EV_MATCH_OVER, "winner": winner})
	_net_sync_board()
	_net_show_result(winner)




func _net_show_result(winner_index: int) -> void:
	if combat._net_match_over:
		return   # one result per game — guards the Best-of-N tally against double-count
	combat._net_match_over = true
	combat.phase = combat.Phase.GAME_OVER
	Card2D.board_interactive = false
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = true
	# The face-up opponent-hand strip is meaningless once the game is over; hide it
	# so it doesn't sit over the result / rematch panel.
	if combat._net_opp_hand_box != null and is_instance_valid(combat._net_opp_hand_box):
		combat._net_opp_hand_box.visible = false
	var me: int = NetMatch.local_player_index

	# ── Best-of-N series ────────────────────────────────────────────────────
	# Both peers run this symmetrically (host via _net_host_check_match_over, client
	# via the EV_MATCH_OVER event), so record the game on each side; the SkirmishState
	# tally stays in sync. Then either roll into the next game or crown the series.
	if SkirmishState.best_of > 1:
		SkirmishState.record_game_winner(winner_index)
		if SkirmishState.series_leader() == -1:
			_net_show_series_interstitial(winner_index)   # series live → next game
			return
		var series_won := SkirmishState.series_leader() == me
		var sverdict := "SERIES WON" if series_won else "SERIES LOST"
		if combat._phase_label != null:
			combat._phase_label.text = sverdict
		combat._show_info("%s  (%s)  —  rematch, or leave?" % [sverdict, _net_series_score_str()])
		if AudioBank != null:
			AudioBank.play_sfx("victory" if series_won else "defeat")
		_net_build_result_panel(sverdict)
		combat._show_battle_verdict(series_won, 0, false, true)
		return

	# ── Single game (Bo1): the original behaviour. ──
	var verdict := "DRAW"
	if winner_index == me:
		verdict = "VICTORY!"
	elif winner_index >= 0:
		verdict = "DEFEAT"
	if combat._phase_label != null:
		combat._phase_label.text = verdict
	combat._show_info(verdict + "  —  rematch with the same decks, or leave?")
	if AudioBank != null:
		AudioBank.play_sfx("victory" if winner_index == me else "defeat")
	# Stay connected: offer a rematch (same drafted decks, fresh HP/board) instead
	# of auto-dropping to the menu. The connection is held open until someone leaves.
	_net_build_result_panel(verdict)
	if winner_index >= 0:
		combat._show_battle_verdict(winner_index == me, 0, false, true)




## "You N – M Opponent" from the local player's POV (Best-of-N standing).
func _net_series_score_str() -> String:
	var me: int = NetMatch.local_player_index
	var opp: int = 1 - me
	return "You %d – %d Opponent" % [
		SkirmishState.series_wins[me], SkirmishState.series_wins[opp]]




## A live series game just ended: show this game's verdict + the running score, then
## auto-roll into the next game by driving the SAME rematch handshake both sides use
## (each side flags itself + signals the peer → the host relaunches; HP/board reset
## via NetMatch._enter_combat_local; the kept decks and series tally carry over).
func _net_show_series_interstitial(winner_index: int) -> void:
	var me: int = NetMatch.local_player_index
	var game_verdict := "DRAW"
	if winner_index == me:
		game_verdict = "GAME WON"
	elif winner_index >= 0:
		game_verdict = "GAME LOST"
	if combat._phase_label != null:
		combat._phase_label.text = game_verdict
	combat._show_info("%s  ·  %s  ·  first to %d  —  next game…" % [
		game_verdict, _net_series_score_str(), SkirmishState.games_to_win()])
	if AudioBank != null:
		AudioBank.play_sfx("victory" if winner_index == me else "defeat")
	# Hold the standing on screen, then advance. The host only relaunches once BOTH
	# sides have signalled, so a small clock skew between the two timers is harmless.
	await combat.get_tree().create_timer(2.2).timeout
	if not combat._net_match_over:
		return   # peer left during the pause; _net_on_peer_lost already handled it
	combat._net_rematch_local = true
	if combat._is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_REMATCH})
	else:
		NetMatch.send_intent({"t": NetMatch.IN_REMATCH})
	_net_try_start_rematch()




# ── Rematch (keep both peers connected; replay with the same decks) ──────────

## Build the post-match overlay: a verdict line + REMATCH / LEAVE buttons.
func _net_build_result_panel(verdict: String) -> void:
	if combat._net_result_panel != null and is_instance_valid(combat._net_result_panel):
		combat._net_result_panel.queue_free()
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 14)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = -90
	panel.offset_bottom = 90
	var v_lbl = combat._make_text_label(verdict, 40, Color(1.0, 0.85, 0.45))
	v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(v_lbl)
	var rematch_btn := Button.new()
	rematch_btn.text = "REMATCH"
	rematch_btn.custom_minimum_size = Vector2(280, 50)
	combat._style_button(rematch_btn)
	rematch_btn.add_theme_font_size_override("font_size", 22)
	rematch_btn.pressed.connect(_net_request_rematch)
	panel.add_child(rematch_btn)
	var leave_btn := Button.new()
	leave_btn.text = "LEAVE TO MENU"
	leave_btn.custom_minimum_size = Vector2(280, 44)
	combat._style_button(leave_btn)
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.pressed.connect(_net_leave_to_menu)
	panel.add_child(leave_btn)
	combat._net_result_panel = panel
	combat._hud_layer.add_child(panel)




## This side wants a rematch: flag it, tell the peer, and start if both agree.
func _net_request_rematch() -> void:
	if combat._net_rematch_local:
		return
	# After a decided series, REMATCH starts a FRESH best-of-N (both sides reset
	# symmetrically as each presses; the tally otherwise persists between games).
	if SkirmishState.best_of > 1 and SkirmishState.series_leader() != -1:
		SkirmishState.reset_series()
	combat._net_rematch_local = true
	if combat._net_result_panel != null and is_instance_valid(combat._net_result_panel):
		# Disable the REMATCH button + relabel so the player knows we're waiting.
		for c in combat._net_result_panel.get_children():
			if c is Button and c.text == "REMATCH":
				c.disabled = true
				c.text = "WAITING FOR OPPONENT…"
	if combat._is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_REMATCH})
	else:
		NetMatch.send_intent({"t": NetMatch.IN_REMATCH})
	_net_try_start_rematch()




## The peer signalled it wants a rematch.
func _net_on_remote_rematch() -> void:
	combat._net_rematch_remote = true
	if not combat._net_rematch_local:
		combat._show_info("Opponent wants a rematch — press REMATCH to play again.")
	_net_try_start_rematch()




## When BOTH sides want a rematch, the HOST relaunches combat (host-authoritative,
## both peers transition together; _enter_combat_local resets HP + the board).
func _net_try_start_rematch() -> void:
	if not (combat._net_rematch_local and combat._net_rematch_remote):
		return
	if combat._is_host():
		combat._show_info("Rematch — redrawing the line…")
		NetMatch.launch_combat()




func _net_leave_to_menu() -> void:
	# Dropping the connection bounces the opponent to the menu via peer_left.
	NetMatch.leave()
	GameTheme.fade_out_then_change_scene(combat, "res://scenes/main_menu.tscn", 0.5)




# ── Board snapshot (host → client) ───────────────────────────────────────

## HOST: serialize the whole board + both hero HPs and push it to the client.
func _net_sync_board() -> void:
	if not combat._is_host():
		return
	# This fires after every authoritative mutation, so it's the one place that
	# guarantees the snapshot's per-creature atk (serialised from effective_atk
	# below) reflects current adjacency — for BOTH sides, on the client's screen.
	combat._refresh_adjacency_buffs()
	var creatures: Array = []
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				var c = arr[lane]
				if c == null or not is_instance_valid(c) or c.current_hp <= 0:
					continue
				# Sealed-orders stand-ins are PRIVATE commitments — shipping one
				# in a snapshot would leak the order to the foe before the reveal.
				if c.get_meta("sealed_pending", false):
					continue
				if c.entity_id < 0:
					c.entity_id = _net_issue_token_id()
					NetMatch.register_entity(c.entity_id, c)
				creatures.append({
					"eid": c.entity_id,
					"owner": (1 if is_enemy else 0),
					"lane": lane, "row": row,
					"id": String(c.card_id),
					"atk": int(c.effective_atk()),
					"hp": int(c.current_hp),
					"mhp": int(c.card_data.get("hp", c.current_hp)),
					"kw": c.card_data.get("keywords", []),
					"floop": bool(c.will_floop),
					"token": bool(c.is_token),
					# Temp combat states (freeze/stun/shield) — so the client can render
					# WHY one of its creatures isn't swinging, not just that it didn't.
					"frz": bool(c.state.is_frozen),
					"stn": bool(c.state.stunned),
					"shd": bool(c.state.has_shield),
					# Doom countdown — authoritative on the host (the client no longer
					# ticks it locally). -1 for non-doom creatures. maxi(0,…) so a bomb
					# mid-detonation reads 0, never the -999 sentinel.
					"doom": maxi(0, int(c.doom_counter)) if c.has_keyword("doom") else -1,
				})
	NetMatch.send_to_client({
		"t": NetMatch.EV_BOARD_SYNC,
		"creatures": creatures,
		"host_hp": combat.player_hp,
		"client_hp": combat.enemy_hp,
		"active": combat._net_active_index,
		# Entities removed by exile (Banish) this sync — the client drops them WITHOUT
		# recycling to discard, since an exiled creature is gone, not dead.
		"exiled": combat._net_exiled_eids.duplicate(),
		# Keyword combat callouts (POISON/THORNS/PIERCING) the host spawned since the
		# last sync — the client replays each on its matching entity for VFX parity.
		"fx": combat._net_fx_queue.duplicate(),
	})
	combat._net_exiled_eids.clear()
	combat._net_fx_queue.clear()




## CLIENT: reconcile the local board to a host snapshot.
func _net_apply_board_sync(ev: Dictionary) -> void:
	var me: int = NetMatch.local_player_index
	var seen: Dictionary = {}
	for cd in ev.get("creatures", []):
		var eid: int = int(cd.get("eid", -1))
		if eid < 0:
			continue
		seen[eid] = true
		var is_enemy_local: bool = int(cd.get("owner", 0)) != me
		var existing = NetMatch.get_entity(eid)
		if existing != null and is_instance_valid(existing):
			_net_update_creature(existing, cd)
		else:
			var data := _net_display_data_from_sync(cd)
			_net_spawn_creature(data, eid, int(cd.get("lane", 0)), int(cd.get("row", 0)), is_enemy_local, false)
	# Entities the host exiled (Banish) this sync — drop these without recycling.
	var exiled: Dictionary = {}
	for e in ev.get("exiled", []):
		exiled[int(e)] = true
	# Drop any creature that vanished from the snapshot (deaths / clears / exile).
	var despawned_n: int = 0
	for eid in NetMatch.entities.keys():
		if seen.has(eid):
			continue
		var node = NetMatch.get_entity(eid)
		if node != null and is_instance_valid(node):
			# Battle log — a vanished creature fell (log BEFORE despawn frees it).
			# Exiled (Banished) creatures skip the "falls" line, same as they skip
			# the death recycle. Tokens read fine here (they have a real name).
			if not exiled.has(eid):
				combat._log_event("%s falls." % combat._log_card_ref(node),
					combat._log_data(node), combat._log_side(node))
			_net_despawn_creature(node, exiled.has(eid))
			despawned_n += 1
		NetMatch.unregister_entity(eid)
	# Mass-grave parity with the solo clash's 3+-fallen beat: the client's deaths
	# flush here (trailing snapshot), so the heavier shake lands here too.
	if despawned_n >= 3:
		combat.screen_shake(11.0)
	var prev_player_hp: int = combat.player_hp
	var prev_enemy_hp: int = combat.enemy_hp
	if me == 0:
		combat.player_hp = int(ev.get("host_hp", combat.player_hp))
		combat.enemy_hp = int(ev.get("client_hp", combat.enemy_hp))
	else:
		combat.player_hp = int(ev.get("client_hp", combat.player_hp))
		combat.enemy_hp = int(ev.get("host_hp", combat.enemy_hp))
	combat._net_active_index = int(ev.get("active", combat._net_active_index))
	combat._update_hud()
	# Face-damage feedback (the client only learns hero HP from the snapshot).
	# NOTE: a clash's face blows are already applied+logged in _net_replay_face_hit
	# (it sets player_hp/enemy_hp directly), so the delta here is zero for those —
	# this block only fires for NON-clash face damage (spell to face), which is
	# exactly what should be logged here to avoid double-counting the clash.
	if combat.enemy_hp < prev_enemy_hp and combat._enemy_hp_label != null:
		combat.spawn_floating_number(combat._enemy_hp_label.get_global_rect().get_center(),
			"-%d" % (prev_enemy_hp - combat.enemy_hp), Color(0.95, 0.5, 0.3), true)
		combat._log_event("The foe takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
			% [prev_enemy_hp - combat.enemy_hp, maxi(combat.enemy_hp, 0)])
	if combat.player_hp < prev_player_hp:
		combat.screen_shake(7.0)
		if combat._player_hp_label != null:
			combat.spawn_floating_number(combat._player_hp_label.get_global_rect().get_center(),
				"-%d" % (prev_player_hp - combat.player_hp), Color(0.95, 0.38, 0.38), true)
		combat._log_event("You take [color=#e06a50]%d[/color] — [color=#f2e6c8]%d[/color] life left." \
			% [prev_player_hp - combat.player_hp, maxi(combat.player_hp, 0)])
	# VFX parity: replay the host's keyword combat callouts on the matching local
	# entities now that the board is reconciled (survivors are at their final slots).
	_net_replay_fx(ev)




# ── Clash replay (client) ────────────────────────────────────────────────
#  The host streams its clash as a per-strike log (EV_CLASH) AHEAD of the
#  outcome snapshot. Replaying it here gives the watcher the same fight the
#  host saw — lunges, tracers, paced blows, damage numbers, kill cues — instead
#  of a one-frame snap to the result. HP values in the log are authoritative
#  (mitigation pre-solved host-side), so the trailing snapshot reconciles with
#  zero deltas and the deaths still flush with it (despawn + ash burst), which
#  mirrors the host's deferred-deaths rhythm.


func _net_replay_clash(ev: Dictionary) -> void:
	combat._net_replay_active = true
	if bool(ev.get("banner", false)):
		var atk_side: int = int(ev.get("atk", -1))
		if atk_side < 0:
			combat._show_info("The lines clash!")
		elif atk_side == NetMatch.local_player_index:
			combat._show_info("Your line strikes!")
		else:
			combat._show_info("The foe's line strikes!")
	for s_raw in ev.get("strikes", []):
		var s: Dictionary = s_raw
		if s.has("l"):        # attacker wind-up
			var lunger = NetMatch.get_entity(int(s.get("l", -1)))
			if lunger != null and is_instance_valid(lunger) and lunger.has_method("play_attack_lunge"):
				lunger.play_attack_lunge(combat._lunge_strength(int(s.get("latk", 2))))
			await combat._short_pause(combat.LUNGE_APEX)
		elif s.has("cap"):    # a mid-clash phase caption (THE DOUBLED HOUR)
			combat._set_phase_caption(String(s.get("cap", "")))
		elif s.has("pl"):     # a piercing kill's skewer
			_net_replay_pierce(int(s.get("pl", -1)), int(s.get("pv", -1)))
		elif s.has("f"):      # a hero took the blow
			await _net_replay_face_hit(s)
		elif s.has("d"):      # a creature took the blow
			await _net_replay_creature_hit(s)
	combat._net_replay_active = false
	_net_flush_backlog()




func _net_flush_backlog() -> void:
	while not combat._net_event_backlog.is_empty():
		if combat._net_replay_active:
			return   # a queued clash log started a new replay — it owns the flush now
		_net_process_event(combat._net_event_backlog.pop_front())




func _net_replay_creature_hit(s: Dictionary) -> void:
	var victim = NetMatch.get_entity(int(s.get("d", -1)))
	if victim == null or not is_instance_valid(victim):
		return   # a mid-clash token we never saw — the snapshot reconciles it
	var striker = NetMatch.get_entity(int(s.get("a", -1)))
	var attacker_is_foe: bool = int(s.get("o", 0)) != NetMatch.local_player_index
	var dmg: int = int(s.get("n", 0))
	var hp_after: int = int(s.get("hp", victim.current_hp))
	# Battle log — the client learns each blow only from this replay stream; mirror
	# the host's strike line (counters read "strikes back at", matching
	# _apply_mutual_retaliation). The trailing snapshot logs the resulting deaths.
	if striker != null and is_instance_valid(striker):
		var verb: String = "strikes back at" if bool(s.get("ctr", false)) else "strikes"
		combat._log_event("%s %s %s for [color=#f2e6c8]%d[/color]." \
			% [combat._log_card_ref(striker), verb, combat._log_card_ref(victim), dmg],
			combat._log_data(striker), combat._log_side(striker))
	if striker != null and is_instance_valid(striker):
		# Cross-Blitz counter: the striker is the defender biting back — lunge it into
		# the attacker so the return blow reads as a real attack (mirrors the host's
		# will_counter lunge). Forward strikes keep their existing lunge (logged as a
		# separate {l} entry), so only the counter needs one synthesized here.
		if bool(s.get("ctr", false)) and striker.has_method("play_attack_lunge"):
			striker.play_attack_lunge(combat._lunge_strength(maxi(dmg, 1)))
		combat._play_attack_tracer(combat._card_center(striker), combat._card_center(victim),
			attacker_is_foe, float(maxi(dmg, 1)), dmg >= combat.HEAVY_HIT_DAMAGE)
		# Thorns / Hydra self-bite: the attacker's own chip rides the same entry.
		if s.has("ahp") and int(s.get("ahp", 0)) < int(striker.current_hp):
			var sting: int = int(striker.current_hp) - int(s.get("ahp", 0))
			striker.current_hp = int(s.get("ahp", 0))
			striker.update_stat_display()
			if striker.has_method("_flash_hit"):
				striker._flash_hit()
			combat.spawn_floating_number(combat._card_center(striker), "-%d" % sting, Color(0.95, 0.38, 0.38), false)
	victim.current_hp = hp_after
	victim.update_stat_display()
	# Counter blows land on the still-lunging attacker — a position recoil there fights
	# its lunge tween and drifts the card out of its slot (mirrors the host-side guard in
	# _apply_mutual_retaliation). The _flash_hit below still shows the hit. Forward
	# strikes recoil normally (the victim is a static defender).
	if not bool(s.get("ctr", false)) and victim.has_method("play_hit_recoil"):
		victim.play_hit_recoil(attacker_is_foe)
	# Contact-point spark parity with the host's strike path. Power uses the
	# post-mitigation damage (all the log carries) — cosmetic-only divergence
	# from the host's pre-mitigation atk on Armored/Shield hits.
	if striker != null and is_instance_valid(striker):
		combat._spawn_impact_burst(combat._card_center(victim),
			combat._card_center(victim) - combat._card_center(striker), float(maxi(dmg, 1)), hp_after <= 0)
	if dmg > 0:
		combat.spawn_floating_number(combat._card_center(victim), "-%d" % dmg, Color(0.95, 0.38, 0.38), false)
	if hp_after > 0:
		# Survivor contract: _flash_hit owns the red punch AND the "hit_creature" cue.
		if dmg > 0 and victim.has_method("_flash_hit"):
			victim._flash_hit()
		await combat._short_pause(combat.HITSTOP_BEAT if dmg >= combat.HEAVY_HIT_DAMAGE else combat.POST_HIT_BEAT)
	else:
		# Kill contract: the cue sounds at the impact beat; the corpse slumps and
		# stands until the trailing snapshot flushes it — the deferred-deaths feel.
		victim.death_cue_played = true
		AudioBank.play_sfx("creature_death", 0.05)
		if victim.has_method("_mark_mortally_struck"):
			victim._mark_mortally_struck()
		combat.screen_shake(6.0)
		await combat._short_pause(combat.HITSTOP_BEAT)




## CLIENT: redraw a piercing kill's lance from the host's log. Both entities are still
## alive on the board here (the victim is mortally struck but not flushed until the
## trailing snapshot), so the client reconstructs the same skewer + spark from its own
## card centres — the world coords the host drew at are meaningless on a mirrored board.
func _net_replay_pierce(attacker_eid: int, victim_eid: int) -> void:
	var attacker = NetMatch.get_entity(attacker_eid)
	var victim = NetMatch.get_entity(victim_eid)
	if attacker == null or not is_instance_valid(attacker) \
			or victim == null or not is_instance_valid(victim):
		return
	var a = combat._card_center(attacker)
	var v = combat._card_center(victim)
	var lance_dir = v - a
	if lance_dir.length() > 1.0:
		var beyond = v + lance_dir.normalized() * 130.0
		combat._play_pierce_lance(a, beyond)
		combat.spawn_ash_burst(beyond, Color(1.0, 0.86, 0.46), 14)




func _net_replay_face_hit(entry, hp_after_legacy: int = -1, dmg_legacy: int = -1) -> void:
	# Mirrors the juice of damage_player_hero (own face — loud) and
	# damage_enemy_hero (foe face — lighter) for whichever hero the log names.
	var s: Dictionary = entry if entry is Dictionary else {
		"f": int(entry),
		"fhp": hp_after_legacy,
		"n": dmg_legacy,
	}
	var owner_idx: int = int(s.get("f", 0))
	var hp_after: int = int(s.get("fhp", 0))
	var dmg: int = int(s.get("n", 0))
	var mine: bool = owner_idx == NetMatch.local_player_index
	if dmg > 0 and s.has("a"):
		var striker = NetMatch.get_entity(int(s.get("a", -1)))
		if striker != null and is_instance_valid(striker):
			var vfx_power: int = int(s.get("p", dmg))
			combat._play_face_strike_vfx(striker, int(s.get("lane", striker.current_lane)),
				striker.is_opponent, vfx_power)
	if mine:
		combat.player_hp = hp_after
		if dmg > 0:
			combat.screen_shake(clampf(8.0 + dmg * 3.4, 10.0, 28.0))
			combat._play_face_damage_flash(dmg)
			if combat._player_hp_label != null:
				combat.spawn_floating_number(combat._player_hp_label.get_global_rect().get_center() + Vector2(0, -6),
					"-%d" % dmg, Color(1.0, 0.28, 0.22), true)
				combat._punch_label(combat._player_hp_label, 1.22)
			if AudioBank != null:
				AudioBank.play_sfx("hit_hero")
			combat._log_event("You take [color=#e06a50]%d[/color] — [color=#f2e6c8]%d[/color] life left." \
				% [dmg, maxi(hp_after, 0)])
	else:
		combat.enemy_hp = hp_after
		if dmg > 0:
			combat.screen_shake(clampf(dmg * 2.0, 4.0, 15.0))
			if combat._enemy_hp_label != null:
				combat.spawn_floating_number(combat._enemy_hp_label.get_global_rect().get_center(),
					"-%d" % dmg, Color(1.0, 0.45, 0.2), true)
			if AudioBank != null:
				AudioBank.play_sfx("hit_hero")
			combat._log_event("The foe takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
				% [dmg, maxi(hp_after, 0)])
	combat._update_hud()
	await combat._short_pause(combat.HITSTOP_BEAT if dmg > 0 else combat.POST_HIT_BEAT)




## CLIENT: re-spawn the keyword callouts (POISON/THORNS/PIERCING) the host buffered
## into this snapshot, each on its own creature by entity_id. A callout whose creature
## died this sync has no anchor left — skipped; the death burst already shows the kill.
func _net_replay_fx(ev: Dictionary) -> void:
	for fx in ev.get("fx", []):
		var node = NetMatch.get_entity(int(fx.get("eid", -1)))
		if node == null or not is_instance_valid(node):
			continue
		var c: Array = fx.get("col", [1, 1, 1])
		var col := Color(float(c[0]), float(c[1]), float(c[2])) if c.size() >= 3 else Color(1, 1, 1)
		var anchor: Vector2 = node.global_position + Vector2(
			node.size.x * node.scale.x * 0.5, node.size.y * node.scale.y * 0.06)
		# Battle log — mirror the host's status line (the host logs these via
		# spawn_keyword_callout_kw → log_status; the client re-plays them here).
		combat.log_status(node, String(fx.get("label", "")))
		# Last Stand: reproduce the host's exact presentation — the keyword-icon
		# pill (what _spawn_keyword_chip shows there) plus the overbright flare on
		# the surviving card itself, not just a bare text callout.
		if String(fx.get("label", "")) == "LAST STAND":
			combat.spawn_keyword_callout(anchor, "LAST STAND", col,
				GameTheme.get_keyword_icon("last_stand"))
			if node.has_method("_play_last_stand_flare"):
				node._play_last_stand_flare()
			continue
		combat.spawn_keyword_callout(anchor, String(fx.get("label", "")), col)




func _net_display_data_from_sync(cd: Dictionary) -> Dictionary:
	var base := SkirmishState.skirmish_card_data(String(cd.get("id", "")))
	var data: Dictionary
	if base.is_empty():
		data = {"id": String(cd.get("id", "token")), "name": "Token", "type": "creature", "cost": 0}
	else:
		data = base.duplicate(true)
	data["atk"] = int(cd.get("atk", data.get("atk", 0)))
	data["hp"] = int(cd.get("mhp", data.get("hp", 1)))
	data["cur_hp"] = int(cd.get("hp", data.get("hp", 1)))
	data["keywords"] = cd.get("kw", data.get("keywords", []))
	# Carry the temp combat states through so a creature that spawns into a frozen/
	# stunned/shielded state on the client renders it (the spawn path reads these).
	for k in ["frz", "stn", "shd"]:
		if cd.has(k):
			data[k] = cd[k]
	return data




func _net_update_creature(node: Control, cd: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Reposition reconcile: if the host says this entity is in a different slot than
	# we have it locally, re-slot it on the correct local side before updating stats.
	var me: int = NetMatch.local_player_index
	var is_enemy_local: bool = int(cd.get("owner", 0)) != me
	var new_lane: int = int(cd.get("lane", node.current_lane))
	var new_row: int = int(cd.get("row", node.current_row))
	if new_lane != node.current_lane or new_row != node.current_row:
		_net_reslot(node, new_lane, new_row, is_enemy_local)
	var old_hp: int = int(node.current_hp)
	var new_hp: int = int(cd.get("hp", node.current_hp))
	node.current_atk = int(cd.get("atk", node.current_atk))
	node.current_hp = new_hp
	# Propagate keyword + max-HP changes (hex/buff) to an already-spawned client
	# node — the spawn path applies these, but the update path used to skip them,
	# leaving the client's glossary/chips stale on a mutated creature.
	node.card_data["keywords"] = cd.get("kw", node.card_data.get("keywords", []))
	node.card_data["hp"] = int(cd.get("mhp", node.card_data.get("hp", new_hp)))
	node.will_floop = bool(cd.get("floop", node.will_floop))
	_net_apply_creature_states(node, cd)
	# Doom counter is host-authoritative (the client no longer ticks it locally, so
	# it can't drift). Flash on a decrement so the bomb still visibly counts down.
	if int(cd.get("doom", -1)) >= 0 and node.has_method("update_doom_display"):
		var old_doom: int = int(node.doom_counter)
		node.doom_counter = int(cd["doom"])
		node.update_doom_display()
		if node.doom_counter < old_doom and old_doom >= 0 and node.has_method("flash_doom_tick"):
			node.flash_doom_tick()
	if node.has_method("update_stat_display"):
		node.update_stat_display()
	if node.has_method("update_floop_display"):
		node.update_floop_display()
	# Snapshots carry only final stats, so animate the delta for clash feel — the
	# client never runs the resolver, this is its only combat feedback (v1 coarse).
	if new_hp < old_hp:
		var lost_hp: int = old_hp - new_hp
		if node.has_method("play_hit_recoil"):
			node.play_hit_recoil(bool(node.is_opponent))
		combat._spawn_impact_burst(combat._card_center(node),
			Vector2(0.0, 1.0 if bool(node.is_opponent) else -1.0),
			float(lost_hp), new_hp <= 0)
		combat.spawn_floating_number(combat._card_center(node), "-%d" % lost_hp, Color(0.95, 0.38, 0.38), false)
		if new_hp > 0 and node.has_method("_flash_hit"):
			node._flash_hit()
		elif new_hp <= 0 and node.has_method("_mark_mortally_struck"):
			node._mark_mortally_struck()
	elif new_hp > old_hp:
		combat.spawn_floating_number(combat._card_center(node), "+%d" % (new_hp - old_hp), Color(0.45, 0.9, 0.5), false)




## CLIENT: mirror a creature's temp combat states (freeze / stun / shield) from a
## host snapshot, and pop a one-shot chip when freeze or stun NEWLY turns on so the
## player sees why their creature is about to forfeit a swing. Absent keys preserve
## the current value (host-side spawns omit them — a fresh body defaults to clear).
func _net_apply_creature_states(node: Control, cd: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	var was_frozen: bool = node.state.is_frozen
	var was_stunned: bool = node.state.stunned
	node.state.is_frozen = bool(cd.get("frz", node.state.is_frozen))
	node.state.stunned = bool(cd.get("stn", node.state.stunned))
	node.state.has_shield = bool(cd.get("shd", node.state.has_shield))
	if node.has_method("_spawn_keyword_chip"):
		if node.state.is_frozen and not was_frozen:
			node._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
		elif node.state.stunned and not was_stunned:
			node._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))




## CLIENT: relocate an already-spawned creature to a new slot to match a host
## snapshot (the visible half of a reposition). Clears the old board-array cell,
## re-parents into the destination slot on the correct local side.
func _net_reslot(node: Control, new_lane: int, new_row: int, is_enemy_local: bool) -> void:
	if new_lane < 0 or new_lane >= combat.LANES_PER_ROW or new_row < combat.ROW_FRONT or new_row > combat.ROW_BACK:
		return
	var old_arr = combat._row_array(is_enemy_local, node.current_row)
	if node.current_lane >= 0 and node.current_lane < old_arr.size() and old_arr[node.current_lane] == node:
		old_arr[node.current_lane] = null
	node.current_lane = new_lane
	node.current_row = new_row
	combat._reset_card_after_drag(node)
	combat._slot_set_card(combat._slot_array(is_enemy_local, new_row)[new_lane], node)
	combat._row_array(is_enemy_local, new_row)[new_lane] = node
	combat._play_landing_pop(node)




func _net_despawn_creature(node: Control, exiled: bool = false) -> void:
	# A creature vanished from the host's authoritative snapshot — for the local
	# player's OWN board cards that means death, so recycle them into the discard
	# pile exactly as the solo death pipeline does (see line ~9878). The host
	# already discards its own fallen creatures via _cleanup_dead; this is the
	# client-side mirror so BOTH warbands' decks cycle their creatures across a
	# long match. Tokens/summons (deck_uid < 0) and the opponent's creatures
	# (tracked in their own deck, on their own machine) are skipped — and so is an
	# EXILED creature (Banish removes it from the game, it does not go to discard).
	if not exiled and is_instance_valid(node) and not node.is_opponent and node.deck_uid >= 0:
		if combat._pending_return_uids.has(int(node.deck_uid)):
			# An EV_GIVE_CARD already floated this uid back to our hand (Griffin /
			# Grave Robbery) — filing it too would double-count the card.
			combat._pending_return_uids.erase(int(node.deck_uid))
		else:
			combat._player_discard_pile.append(combat._pile_entry(node.card_id, node.deck_uid))
	for is_enemy in [false, true]:
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			var arr = combat._row_array(is_enemy, row)
			for lane in range(combat.LANES_PER_ROW):
				if arr[lane] == node:
					arr[lane] = null
	if is_instance_valid(node):
		var pos = combat._card_center(node)
		if exiled:
			combat.spawn_ash_burst(pos, Color(0.62, 0.60, 0.66), 18)
			var xtw := node.create_tween()
			xtw.tween_property(node, "modulate:a", 0.0, UserSettings.anim_time(0.18))
			xtw.tween_callback(node.queue_free)
			return
		var cue_already_played: bool = bool(node.death_cue_played)
		node.death_cue_played = true
		if not cue_already_played and AudioBank != null:
			AudioBank.play_sfx("creature_death", 0.05)
			combat.screen_shake(5.0)
		if node.has_method("_mark_mortally_struck"):
			node._mark_mortally_struck()
		combat._play_creature_death_vfx(node, bool(node.is_opponent))
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = node.size * 0.5
		node.z_index = maxi(int(node.z_index), 40)
		var tw := node.create_tween()
		tw.set_parallel(true)
		tw.tween_property(node, "modulate", Color(0.35, 0.08, 0.08, 0.0),
			UserSettings.anim_time(0.34)).set_ease(Tween.EASE_IN)
		tw.tween_property(node, "scale", node.scale * 0.45,
			UserSettings.anim_time(0.34)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "rotation", node.rotation + randf_range(-0.5, 0.5),
			UserSettings.anim_time(0.34))
		tw.chain().tween_callback(node.queue_free)




## Materialize a board creature from card data on a given side. On the host
## (run_on_enter=true) the on-enter fires authoritatively; on the client it never
## does (the client only renders the snapshot the host already resolved).
func _net_spawn_creature(data: Dictionary, entity_id: int, lane: int, row: int,
		is_enemy_side: bool, run_on_enter: bool) -> Control:
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = String(data.get("id", ""))
	card.is_opponent = is_enemy_side
	card.is_on_battlefield = true
	card.compact_mode = true
	card.card_data = data.duplicate(true)
	card.entity_id = entity_id
	card.deck_uid = entity_id if entity_id < _net_token_id_base() else -1
	card.current_lane = lane
	card.current_row = row
	if is_enemy_side:
		combat._row_array(true, row)[lane] = card
		var slot = combat._slot_array(true, row)[lane]
		combat._slot_set_card(slot, card)
		card.destroyed.connect(combat._on_card_destroyed.bind(card))
		card.will_die.connect(combat._on_card_will_die.bind(card))
		combat._play_landing_pop(card)
	else:
		combat._place_card_in_slot(card, lane, row, Vector2.ZERO, false)
	# Card2D._ready inits stats from card_data on add_child; override with the
	# exact atk / current-hp the caller specified (covers buffed/damaged sync).
	if data.has("atk"):
		card.current_atk = int(data["atk"])
	if data.has("cur_hp"):
		card.current_hp = int(data["cur_hp"])
	elif data.has("hp"):
		card.current_hp = int(data["hp"])
	_net_apply_creature_states(card, data)
	card.update_stat_display()
	NetMatch.register_entity(entity_id, card)
	# Battle log — a genuine hand placement (drafted creatures have entity_id ==
	# deck_uid < the token base; summoned tokens are ≥ it and don't log a "fields"
	# line, matching solo). This single hook covers the client's own + foe plays
	# (both arrive via board sync) AND the host's view of the foe's play (applied
	# via _net_apply_remote_creature). The host's OWN play logs in _play_creature.
	if entity_id < _net_token_id_base():
		if is_enemy_side:
			combat._log_event("The foe fields %s." % combat._log_card_ref(card),
				combat._log_data(card), combat._log_side(card))
		else:
			combat._log_event("You field %s." % combat._log_card_ref(card),
				combat._log_data(card), combat._log_side(card))
	if run_on_enter:
		KeywordEffects.dispatch_on_enter(card, lane, is_enemy_side, combat)
		if card.card_data.has("on_play"):
			combat._resolve_on_play_ability(card, lane, is_enemy_side)
		# Enter-with-a-bonus passives for this side (Ironclad / Hexblade / Warchief /
		# Tallow / Standard Bearer) — run for the client's creatures too, reading the
		# client's per-side counters (the solo path only ran them for the host's plays).
		combat._apply_play_time_passives(card, is_enemy_side)
	return card




func _net_token_id_base() -> int:
	return 1000000




# ── Intents (client → host) ──────────────────────────────────────────────

# A client creature play now animates (the same hand-fan arc the bot gets),
# which suspends intent processing for the flight. Intents arriving mid-flight
# queue here and apply FIFO after — without this, an IN_END_ACTIONS racing the
# flight would end the turn and silently DROP the animated play (the client
# already paid Command and discarded the card → board desync). Mirrors the
# client's _net_event_backlog contract.

func _on_net_intent(sender_id: int, intent: Dictionary) -> void:
	if not combat._is_host():
		return
	# Rematch requests arrive AFTER the match is over — handle them before the
	# match-over gate below (which would otherwise swallow them).
	if String(intent.get("t", "")) == NetMatch.IN_REMATCH:
		_net_on_remote_rematch()
		return
	if combat._net_match_over:
		return
	if combat._net_intent_busy:
		combat._net_intent_backlog.append(intent)
		return
	combat._net_intent_busy = true
	await _net_process_intent(intent)
	while not combat._net_intent_backlog.is_empty():
		if combat._net_match_over:
			combat._net_intent_backlog.clear()
			break
		await _net_process_intent(combat._net_intent_backlog.pop_front())
	combat._net_intent_busy = false




func _net_process_intent(intent: Dictionary) -> void:
	match String(intent.get("t", "")):
		NetMatch.IN_PLAY_CREATURE:
			# animate=true — a human opponent's play arcs from the foe's hand fan,
			# the same ceremony the bot already had. The ghost bails headless, so
			# probe-driven intents resume synchronously.
			await _net_apply_remote_creature(intent, true)
		NetMatch.IN_PLAY_SPELL:
			_net_apply_remote_spell(intent)
		NetMatch.IN_REPOSITION:
			_net_apply_remote_reposition(intent)
		NetMatch.IN_USE_POTION:
			# The client drank a host-authoritative potion. Apply it to the
			# client's side (enemy side from the host's view) + re-sync. A targeted
			# bottle carries its target as an entity_id.
			var pid := String(intent.get("pid", ""))
			if pid != "":
				var pot_target: Control = null
				var pot_eid: int = int(intent.get("target", -1))
				if pot_eid >= 0:
					var pn = NetMatch.get_entity(pot_eid)
					if pn != null and is_instance_valid(pn):
						pot_target = pn
				_net_apply_host_potion(pid, true, pot_target)
				_net_sync_board()
			elif String(intent.get("effect", "")) == "heal_hp":
				# Legacy payload shape from the first net-potion pass.
				_net_heal_hero(true, int(intent.get("value", 8)))
				_net_sync_board()
		NetMatch.IN_ORDER_PICK:
			# The client won the toss — its settled order binds the host too.
			combat._net_first_player_override = int(intent.get("first", 0))
		NetMatch.IN_END_ACTIONS:
			if combat._net_active_index == 1:
				_net_finish_placement(1)
		NetMatch.IN_CHOICE:
			# The client picked an option for its own Copycat / Adaptable — apply + sync.
			_net_apply_client_choice(intent)
		NetMatch.IN_ORDERS:
			# Sealed style: the client's whole creature bundle. Awaited so the
			# reveal (once both bundles are in) sequences ahead of queued intents.
			await _sealed_store_bundle(1, intent.get("list", []), int(intent.get("mana", 0)))
		NetMatch.IN_ORDER_GHOST:
			_sealed_show_ghost(int(intent.get("lane", -1)), int(intent.get("row", 0)))
		NetMatch.IN_SORCERY_PASS:
			_sealed_sorcery_pass(1)
		NetMatch.EV_HAND_COUNT:
			combat._net_opp_hand_count = int(intent.get("n", 0))
			_net_refresh_opp_hand()
			_net_set_opp_mana(int(intent.get("mana", combat._net_opp_mana)),
				int(intent.get("maxmana", combat._net_opp_max_mana)))
		NetMatch.EV_DISCARD_FX:
			# The client threw cards away at its turn commit — show the beat.
			_net_show_foe_discard_fx(int(intent.get("n", 0)))
		NetMatch.EV_POTION_FX:
			# The client drank a potion — show the drink beat over its portrait.
			_net_show_foe_potion_fx(String(intent.get("pid", "")))
		NetMatch.EV_RELIC_FX:
			# The client's resource relic paid out on its machine — pulse its
			# chip on our foe-arsenal rail (HS trinket beat).
			_net_on_relic_fx(intent)
		NetMatch.EV_EMOTE:
			# The client sent an emote — float their line over the enemy plate.
			combat._net_show_foe_emote(int(intent.get("idx", -1)))
		_:
			pass




## HOST: seat the client's creature on the host's ENEMY side, run its on-enter
## authoritatively, then snapshot the new board to the client.
func _net_apply_remote_creature(intent: Dictionary, animate: bool = false) -> void:
	if combat._net_active_index != 1:
		return   # not the client's turn
	var lane: int = int(intent.get("lane", -1))
	var row: int = int(intent.get("row", combat.ROW_FRONT))
	if lane < 0 or lane >= combat.LANES_PER_ROW or row < combat.ROW_FRONT or row > combat.ROW_BACK:
		return
	if combat._row_array(true, row)[lane] != null:
		return   # slot occupied — drop the play (client mis-synced)
	var data := SkirmishState.skirmish_card_data(String(intent.get("id", "")))
	if data.is_empty():
		return
	var uid: int = int(intent.get("uid", _net_issue_token_id()))
	if animate:
		# Foe play (bot or human opponent): throw the card from the foe's hand
		# into the slot before seating it.
		await _bot_animate_creature_play(data, lane, row)
		# The throw awaited a few frames — re-validate the turn/slot before committing.
		if combat._net_match_over or combat._net_active_index != 1:
			return
		if combat._row_array(true, row)[lane] != null:
			return
	combat._net_cards_played[1] += 1   # client's per-side card tally (Ironclad Veteran), pre-spawn
	# The client stamps its unspent Command (post-payment) on the intent so
	# play-time passives that scale off the caster's pool (Condottiere) read the
	# CLIENT's pool, not the host's. Bot intents omit it → 0 (vanilla body).
	combat._net_client_unspent_mana = int(intent.get("mana", 0))
	_net_spawn_creature(data, uid, lane, row, true, true)
	_net_sync_board()




# ── Reposition (battlefield "move") over the wire ────────────────────────
#
#  The active player drags one of their OWN board creatures to an empty friendly
#  slot (Card2D.board_interactive is on during their turn; floop stays off). The
#  HOST is authoritative: it applies its own moves directly + snapshots, and it
#  validates + applies the client's move from an IN_REPOSITION intent. The client
#  never moves its board directly — it sends the intent and the host's board
#  snapshot performs the visible move (reconciled in _net_update_creature).

func _net_field_move_dropped(global_pos: Vector2, card: Control) -> void:
	var active_local: bool = combat._net_active_index == NetMatch.local_player_index
	if not active_local or combat.phase != combat.Phase.PLAYER_TURN or combat._net_match_over:
		combat._return_card_to_slot(card)
		return
	if combat._moves_used_this_turn >= combat.MOVES_PER_TURN:
		combat._show_info("No moves left this turn.")
		combat._return_card_to_slot(card)
		return
	var drop = combat._nearest_player_slot(global_pos)
	var dest_row: int = drop.row
	var dest_lane: int = drop.lane
	var src_row: int = card.current_row
	var src_lane: int = card.current_lane
	if dest_row == src_row and dest_lane == src_lane:
		combat._return_card_to_slot(card)
		return
	if combat._row_array(false, dest_row)[dest_lane] != null:
		combat._show_info("That slot is occupied.")
		combat._return_card_to_slot(card)
		return
	if combat._is_host():
		# Authoritative local move (mirrors the solo path), then snapshot.
		combat._row_array(false, src_row)[src_lane] = null
		card.current_row = dest_row
		card.current_lane = dest_lane
		combat._reset_card_after_drag(card)
		combat._slot_set_card(combat._slot_array(false, dest_row)[dest_lane], card)
		combat._row_array(false, dest_row)[dest_lane] = card
		combat._moves_used_this_turn += 1
		combat._play_landing_pop(card)
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
		_net_sync_board()
	else:
		# Client: predict the approved local move immediately for feel, then let the
		# card home — the host's snapshot will perform the actual move.
		combat._moves_used_this_turn += 1
		combat._row_array(false, src_row)[src_lane] = null
		card.current_row = dest_row
		card.current_lane = dest_lane
		combat._reset_card_after_drag(card)
		combat._slot_set_card(combat._slot_array(false, dest_row)[dest_lane], card)
		combat._row_array(false, dest_row)[dest_lane] = card
		combat._play_landing_pop(card)
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
		NetMatch.send_intent({
			"t": NetMatch.IN_REPOSITION, "eid": int(card.entity_id),
			"lane": dest_lane, "row": dest_row,
		})




## HOST: validate + apply the client's reposition (its creatures sit on the host's
## ENEMY side), then snapshot so both sides see the move.
func _net_apply_remote_reposition(intent: Dictionary) -> void:
	if combat._net_active_index != 1:
		return   # not the client's turn
	if combat._moves_used_this_turn >= combat.MOVES_PER_TURN:
		return
	var dest_lane: int = int(intent.get("lane", -1))
	var dest_row: int = int(intent.get("row", combat.ROW_FRONT))
	if dest_lane < 0 or dest_lane >= combat.LANES_PER_ROW or dest_row < combat.ROW_FRONT or dest_row > combat.ROW_BACK:
		return
	var node = NetMatch.get_entity(int(intent.get("eid", -1)))
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		return   # unknown entity or not the client's own creature
	if combat._row_array(true, dest_row)[dest_lane] != null:
		return   # destination occupied — drop the move (client mis-synced)
	var src_row: int = node.current_row
	var src_lane: int = node.current_lane
	if dest_row == src_row and dest_lane == src_lane:
		return
	combat._row_array(true, src_row)[src_lane] = null
	node.current_row = dest_row
	node.current_lane = dest_lane
	combat._reset_card_after_drag(node)
	combat._slot_set_card(combat._slot_array(true, dest_row)[dest_lane], node)
	combat._row_array(true, dest_row)[dest_lane] = node
	combat._moves_used_this_turn += 1
	combat._play_landing_pop(node)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_net_sync_board()




# ─────────────────────────────────────────────────────────────────────────
#  PRACTICE BOT — drives slot 1 in a vs-bot match (SkirmishState.vs_bot).
#  The bot stands in for an absent client: it keeps its own hand drawn from slot
#  1's deck and a flat Command budget (3 + bank 2), asks SkirmishBot for an
#  ordered list of plays, applies each through the SAME host intent path a remote
#  client would hit, then ends actions (which resolves its strike + passes turn).
# ─────────────────────────────────────────────────────────────────────────

func _bot_refill_hand() -> void:
	var slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(1)
	if slot == null:
		return
	# The bot refills to the standard target. Its going-second compensation is the
	# Coin — a one-time +1 Command on its opening turn (granted in _bot_take_turn),
	# mirroring the human's Coin card rather than the old raw extra card.
	var target: int = combat.HAND_REFILL_TARGET
	while combat._bot_hand.size() < target and combat._bot_deck_cursor < slot.deck.size():
		var id = String(slot.deck[combat._bot_deck_cursor])
		var uid: int = int(slot.deck_uids[combat._bot_deck_cursor]) \
			if combat._bot_deck_cursor < slot.deck_uids.size() else _net_issue_token_id()
		combat._bot_hand.append({"uid": uid, "id": id, "data": SkirmishState.skirmish_card_data(id)})
		combat._bot_deck_cursor += 1




func _bot_take_turn() -> void:
	await combat._short_pause(combat.COMBAT_PAUSE_SHORT)
	if combat._net_match_over or combat._net_active_index != 1:
		return
	_bot_refill_hand()
	var mana: int = SkirmishState.BASE_MAX_MANA + combat._bot_banked_mana
	# The Coin: the side going second gets a one-time +1 Command on its opening turn.
	# The bot can't hold/play a card the way the human does, so the tempo is granted
	# directly here — same net effect as casting the Coin on turn one.
	if combat._bot_turns_taken == 0 and combat._net_goes_second(1):
		mana += 1
	_bot_sync_hand_display(mana)   # the foe's hand fills up + Command seal lights
	var plays: Array = SkirmishBot.decide_turn(combat, combat._bot_hand, mana)
	var spent := 0
	for intent in plays:
		if combat._net_match_over or combat._net_active_index != 1:
			break
		await combat._short_pause(combat.COMBAT_PAUSE_SHORT)
		spent += _bot_consume_card(int(intent.get("uid", -1)))
		# Drop the card from the visible fan BEFORE the play animates, so the throw
		# reads as that card leaving the hand (not a phantom extra).
		_bot_sync_hand_display(mana - spent)
		await _bot_apply_intent(intent)
	combat._bot_banked_mana = clampi(mana - spent, 0, combat.MAX_BANKED_MANA)
	combat._bot_turns_taken += 1
	await combat._short_pause(combat.COMBAT_PAUSE_SHORT)
	if not combat._net_match_over and combat._net_active_index == 1:
		_net_finish_placement(1)




## Remove the played card from the bot's hand and return its Command cost.
func _bot_consume_card(uid: int) -> int:
	for i in combat._bot_hand.size():
		if int(combat._bot_hand[i].get("uid", -2)) == uid:
			var cost = int((combat._bot_hand[i].get("data", {}) as Dictionary).get("cost", 0))
			combat._bot_hand.remove_at(i)
			return cost
	return 0




func _bot_apply_intent(intent: Dictionary) -> void:
	match String(intent.get("t", "")):
		NetMatch.IN_PLAY_CREATURE:
			# animate=true → the card arcs from the foe's hand into its slot first.
			await _net_apply_remote_creature(intent, true)
		NetMatch.IN_PLAY_SPELL:
			await _net_apply_remote_spell(intent)
		NetMatch.IN_REPOSITION:
			await _net_apply_remote_reposition(intent)




## Push the bot's virtual hand (count) and Command budget to the readouts the human
## watches — the face-down fan up top and the foe Command seal — so the bot reads as
## an opponent who holds, then spends, a real hand. `mana_now` is the bot's REMAINING
## budget this turn (-1 = recompute the full turn budget, e.g. on the opening deal).
func _bot_sync_hand_display(mana_now: int = -1) -> void:
	combat._net_opp_hand_count = combat._bot_hand.size()
	_net_refresh_opp_hand()
	if mana_now < 0:
		mana_now = SkirmishState.BASE_MAX_MANA + combat._bot_banked_mana
	_net_set_opp_mana(maxi(0, mana_now), SkirmishState.BASE_MAX_MANA)




## Warm the CardTextureCache for the bot's whole deck so its played creatures fly in
## showing their real FACE (not the fallback card back). Mirrors _prebake_hand_textures:
## the same headless guard skips it in automated runs (bake_many parks on the
## RenderingServer frames that never fire under the dummy display server). Fired
## (not awaited) at match start, so it warms during the human's opening turn.
func _net_prebake_bot_textures() -> void:
	if DisplayServer.get_name() == "headless" or CardTextureCache == null:
		return
	var slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(1)
	if slot == null:
		return
	var seen := {}
	var to_bake: Array = []
	for id in slot.deck:
		var sid := String(id)
		if seen.has(sid):
			continue
		seen[sid] = true
		to_bake.append(SkirmishState.skirmish_card_data(sid))
	await CardTextureCache.bake_many(to_bake)
	await CardTextureCache.bake_battlefield_many(to_bake)




## Cosmetic: a ghost of the card the foe (bot OR human opponent) is about to play
## arcs from the opponent's hand (top) down to its destination slot, so a foe
## creature reads as "taken from hand and set down" rather than teleported onto
## the board. Awaited by _net_apply_remote_creature before the real creature is
## seated. Shows the card FACE when its texture is already baked (the bot's deck
## is warmed at match start via _net_prebake_bot_textures), and the face-down
## card back otherwise. It NEVER awaits bake() — that blocks on RenderingServer
## frames which never fire headless, and this is purely cosmetic, so it must not
## be able to stall the foe's turn.
func _bot_animate_creature_play(data: Dictionary, lane: int, row: int) -> void:
	# Headless bail BEFORE any await: probe-driven plays must seat synchronously
	# (awaiting a coroutine that never suspends resumes the caller in-line).
	if DisplayServer.get_name() == "headless":
		return
	if combat._hud_layer == null or not is_instance_valid(combat._hud_layer):
		return
	var slots: Array = combat._slot_array(true, row)
	if lane < 0 or lane >= slots.size() or slots[lane] == null \
			or not is_instance_valid(slots[lane]):
		return
	var dest: Vector2 = slots[lane].get_global_rect().get_center()
	# Origin = the opponent's hand fan (top-right); fall back to the top-right corner.
	var origin = Vector2(combat.get_viewport_rect().size.x - 150.0, 56.0)
	if combat._net_opp_hand_box != null and is_instance_valid(combat._net_opp_hand_box) \
			and combat._net_opp_hand_box.visible:
		origin = combat._net_opp_hand_box.get_global_rect().get_center()
	var tex: Texture2D = null
	if CardTextureCache != null:
		tex = CardTextureCache.get_texture(data)   # sync read; null if not yet baked
	if tex == null:
		tex = combat._net_card_back_tex                    # face-down fallback (always loaded)
	var travel := Vector2(132, 172)   # readable card in flight
	var land := Vector2(104, 136)     # settles toward the board-token footprint
	var ghost := TextureRect.new()
	if tex != null:
		ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 220
	ghost.size = travel
	ghost.pivot_offset = travel * 0.5   # rotate/settle about the card's centre
	ghost.position = origin - travel * 0.5
	ghost.modulate.a = 0.0
	combat._hud_layer.add_child(ghost)

	var duration := 0.42
	# Bow the path downward — the foe reaches up out of its hand and sets the card down.
	var ctrl = origin.lerp(dest, 0.5) + Vector2(0, -86.0)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var p1 = origin.lerp(ctrl, t)
		var p2 = ctrl.lerp(dest, t)
		var sz: Vector2 = travel.lerp(land, t)
		ghost.size = sz
		ghost.position = p1.lerp(p2, t) - sz * 0.5
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ghost, "modulate:a", 1.0, 0.12)
	tw.tween_property(ghost, "rotation", 0.0, duration).from(randf_range(-0.12, 0.12)) \
		.set_ease(Tween.EASE_OUT)
	# Gate on a real timer (NOT tw.finished) so the bot's turn can never stall on a
	# tween — the tween only drives the cosmetics in parallel; the timer is the clock.
	await combat._short_pause(duration)
	if is_instance_valid(ghost):
		ghost.queue_free()
	if AudioBank != null:
		AudioBank.play_sfx("card_play")




## CLIENT: a cosmetic ghost of the client's OWN creature play, arcing from the hand
## up to the destination slot. The real creature still arrives via the host snapshot
## (the client never seats locally), so this only bridges the visual gap the HOST gets
## for free from its local seat — without it, a Player-2 creature just pops into the
## slot. Fire-and-forget: it never gates the intent (sent before this is called).
func _client_animate_own_play(data: Dictionary, lane: int, row: int, origin: Vector2) -> void:
	if combat._hud_layer == null or not is_instance_valid(combat._hud_layer):
		return
	var slots: Array = combat._slot_array(false, row)
	if lane < 0 or lane >= slots.size() or slots[lane] == null or not is_instance_valid(slots[lane]):
		return
	var dest: Vector2 = slots[lane].get_global_rect().get_center()
	var tex: Texture2D = null
	if CardTextureCache != null:
		tex = CardTextureCache.get_texture(data)   # sync read; null if not yet baked
	if tex == null:
		tex = combat._net_card_back_tex
	var travel := Vector2(132, 172)
	var land := Vector2(104, 136)
	var ghost := TextureRect.new()
	if tex != null:
		ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = 220
	ghost.size = travel
	ghost.pivot_offset = travel * 0.5
	ghost.position = origin - travel * 0.5
	ghost.modulate.a = 0.0
	combat._hud_layer.add_child(ghost)
	var duration := 0.34
	# Bow the path UP toward the board — the player lifts the card from hand onto the line.
	var ctrl := origin.lerp(dest, 0.5) + Vector2(0, -64.0)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		var p1 := origin.lerp(ctrl, t)
		var p2 := ctrl.lerp(dest, t)
		var sz: Vector2 = travel.lerp(land, t)
		ghost.size = sz
		ghost.position = p1.lerp(p2, t) - sz * 0.5
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ghost, "modulate:a", 1.0, 0.10)
	# Real timer, never tw.finished (unreliable headless), mirroring the bot ghost.
	await combat._short_pause(duration)
	if is_instance_valid(ghost):
		ghost.queue_free()




# ── Events (host → client) ───────────────────────────────────────────────

func _on_net_event(event: Dictionary) -> void:
	if combat._is_host():
		return   # host is authoritative; it never consumes its own broadcasts
	# While a clash replay is animating, every incoming event queues behind it —
	# otherwise the outcome snapshot would snap the fight's result in under the
	# replay, and the next turn-begin would start play mid-cinematic.
	if combat._net_replay_active:
		combat._net_event_backlog.append(event)
		return
	_net_process_event(event)




## The event dispatch body — reached live via _on_net_event or deferred via
## _net_flush_backlog once a clash replay finishes.
func _net_process_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		NetMatch.EV_ORDER_PICK:
			# The host settled the toss (its own pick, applied host-side already).
			combat._net_first_player_override = int(event.get("first", 0))
		NetMatch.EV_TURN_BEGIN:
			_net_client_turn_begin(int(event.get("active", 0)), int(event.get("round", 0)))
		NetMatch.EV_ORDERS_PHASE:
			combat._net_turn_round = int(event.get("round", 1))
			combat._net_initiative = int(event.get("init", 0))
			_sealed_open_orders_local()
		NetMatch.EV_ORDER_GHOST:
			_sealed_show_ghost(int(event.get("lane", -1)), int(event.get("row", 0)))
		NetMatch.EV_REVEAL:
			combat.phase = combat.Phase.RESOLVING
			_sealed_clear_pending_local()
			combat._show_combat_banner("THE ORDERS BREAK OPEN", "", Color(1.0, 0.78, 0.35))
			if AudioBank != null:
				AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
		NetMatch.EV_SORCERY:
			_sealed_set_sorcery(int(event.get("who", 0)))
		NetMatch.EV_CLASH:
			# The host's per-strike clash log — replay it paced (lunges, blows,
			# numbers, kill cues). Fire-and-forget coroutine: everything that
			# arrives while it runs queues in the backlog and applies after.
			_net_replay_clash(event)
		NetMatch.EV_BOARD_SYNC:
			_net_apply_board_sync(event)
		NetMatch.EV_HAND_COUNT:
			combat._net_opp_hand_count = int(event.get("n", 0))
			_net_refresh_opp_hand()
			_net_set_opp_mana(int(event.get("mana", combat._net_opp_mana)),
				int(event.get("maxmana", combat._net_opp_max_mana)))
		NetMatch.EV_DISCARD_FX:
			# The host threw cards away at its turn commit — show the beat.
			_net_show_foe_discard_fx(int(event.get("n", 0)))
		NetMatch.EV_POTION_FX:
			# The host drank a potion — show the drink beat over its portrait.
			_net_show_foe_potion_fx(String(event.get("pid", "")))
		NetMatch.EV_RELIC_FX:
			# A relic beat: theirs (mine=true → our foe rail) or OURS resolved
			# host-side (mine=false → our own grid pulses).
			_net_on_relic_fx(event)
		NetMatch.EV_EMOTE:
			# The host sent an emote — float their line over the enemy plate.
			combat._net_show_foe_emote(int(event.get("idx", -1)))
		NetMatch.EV_SPELL:
			# The host cast a spell — show its arrow + thrown card + target burst so we
			# see exactly what they pointed at (client casts are shown host-side).
			_net_on_opp_spell_event(event)
		NetMatch.EV_DRAW:
			# A spell we cast told us to draw from our own pile (host resolved it).
			for _i in int(event.get("n", 0)):
				combat.draw_one()
			combat._layout_hand()
			_net_broadcast_hand_count()
			combat._update_hud()
		NetMatch.EV_GIVE_CARD:
			# The host returned a specific card to our hand (Grave Robbery / Grave Pact).
			_net_give_card_local(String(event.get("id", "")), int(event.get("uid", -1)))
		NetMatch.EV_MANA:
			if bool(event.get("next", false)):
				# Next-turn max-Command grant (Mourner's on-death). Our own
				# _start_round folds it in at the next turn-begin, above the
				# banking cap — same as the host's side of the same effect.
				combat._bonus_mana_next_turn += int(event.get("n", 0))
			else:
				# A spell we cast granted us Command on our own side.
				combat.player_mana += int(event.get("n", 0))
				combat._update_hud()
				_net_broadcast_hand_count()   # push the bumped Command to the foe's seal
		NetMatch.EV_MATCH_OVER:
			_net_show_result(int(event.get("winner", -1)))
		NetMatch.EV_REMATCH:
			_net_on_remote_rematch()
		NetMatch.EV_CHOICE:
			# Host asked us to pick an option for one of our own creatures (Copycat /
			# Adaptable). Show the picker; the answer goes back as an IN_CHOICE intent.
			_net_client_show_choice(int(event.get("eid", -1)), String(event.get("kind", "")))
		_:
			pass




## Tell the opponent our hand SIZE (a number; never the cards — they only see how
## many we hold, as face-down backs). Host → event, client → intent; the receiver
## stores it in _net_opp_hand_count and refreshes the face-down fan up top.
func _net_broadcast_hand_count() -> void:
	# The hand count rides with our live Command (current + max) so the opponent's
	# foe-Command seal tracks what we can afford. This fires on every hand/mana
	# change (turn-begin refill, each play, spell draw/Command rewards), so the
	# foe's readout stays current without a separate channel.
	var msg = {"t": NetMatch.EV_HAND_COUNT, "n": combat._hand.size(),
		"mana": combat.player_mana, "maxmana": combat.player_max_mana}
	if combat._is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)




## Tell the opponent we just discarded N cards (count only — never the faces),
## so their side shows the beat instead of the fan silently shrinking. Sent
## from _flush_marked_discards ahead of the hand-count update; the channel is
## reliable and ordered, so the fx always lands before the fan ticks down.
func _net_send_discard_fx(n: int) -> void:
	if n <= 0:
		return
	var msg := {"t": NetMatch.EV_DISCARD_FX, "n": n}
	if combat._is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)




## The foe discarded N cards: peel that many card-backs off their face-down fan
## and flick them away (down-right, spinning, fading) with a labelled beat, so
## the opponent's churn is a visible act — the mirror of our own discard cascade.
func _net_show_foe_discard_fx(n: int) -> void:
	if n <= 0 or combat._hud_layer == null:
		return
	if combat._net_opp_hand_box == null or not is_instance_valid(combat._net_opp_hand_box):
		return
	var origin: Vector2 = combat._net_opp_hand_box.global_position \
		+ Vector2(combat._net_opp_hand_box.size.x * 0.5, 40.0)
	for i in mini(n, 6):   # cap the volley — past 6 backs it's just confetti
		var back := _net_make_card_back(Vector2(46.0, 64.0))
		combat._hud_layer.add_child(back)
		back.z_index = 30
		back.global_position = origin + Vector2(float(i - 1) * 10.0, 0.0)
		var dest: Vector2 = origin + Vector2(randf_range(60.0, 140.0), randf_range(120.0, 180.0))
		var delay := 0.10 * float(i)
		var tw = combat.create_tween().set_parallel(true)
		tw.tween_property(back, "global_position", dest, 0.42) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(delay)
		tw.tween_property(back, "rotation", randf_range(0.5, 1.1), 0.42) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(delay)
		tw.tween_property(back, "modulate:a", 0.0, 0.42) \
			.set_ease(Tween.EASE_IN).set_delay(delay + 0.06)
		tw.chain().tween_callback(back.queue_free)
		combat.get_tree().create_timer(delay).timeout.connect(func():
			if AudioBank != null:
				AudioBank.play_sfx("card_discard", 0.08, -6.0))
	combat.spawn_floating_number(origin + Vector2(0.0, -18.0),
		"FOE DISCARDS %d" % n, Color(0.78, 0.72, 0.62), false)




## Skirmish potion resolution. Command and draw resolve on the caster's machine;
## HP/board effects route through the host, targeted bottles send an entity_id,
## then the local belt consumes the potion and the foe gets a drink beat.
func _net_use_potion(pid: String, index: int, target: Control = null) -> void:
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect := String(data.get("effect", ""))
	# Caster-local resource rider: Butcher's Dram's +3 Command lands on the
	# drinker's OWN machine (each peer owns its Command); its accompanying
	# sacrifice is the host-side board mutation routed below.
	if effect == "sacrifice_for_command":
		combat.player_mana += 3
	match effect:
		"gain_mana":
			combat.player_mana += 2
		"draw":
			for _i in range(3):
				combat.draw_one()
		_:
			if _net_potion_needs_host(effect):
				if combat._is_host():
					_net_apply_host_potion(pid, false, target)
					_net_sync_board()
				else:
					# The target rides as an entity_id — the cross-wire handle
					# targeted spells use (host resolves via NetMatch.get_entity).
					var msg := {"t": NetMatch.IN_USE_POTION, "pid": pid}
					if target != null and is_instance_valid(target):
						msg["target"] = int(target.entity_id)
					NetMatch.send_intent(msg)
					if effect == "heal_hp":
						var heal: int = int(data.get("value", 8)) if data.has("value") else 8
						combat._show_lifelink_heal(heal) # optimistic; the sync sets true HP
			else:
				push_warning("Combat: net potion effect '%s' is not supported" % effect)
	_net_send_potion_fx(pid)
	combat._ctx_consume_potion(index)
	combat._rebuild_potion_bar()
	combat._update_hud()
	_net_broadcast_hand_count()




func _net_potion_needs_host(effect: String) -> bool:
	return effect in [
		"heal_hp",
		"aoe_enemies",
		"chain_lightning",
		"shield_wall",
		"summon_recruits",
		"revive_last_dead",
		# 2026-07-09 targeted + board bottles (net-aware potion targeting):
		"column_strike",        # Sapper's Charge — target enemy + lane-mate
		"grant_rampage",        # War Paint — target friendly
		"grant_lifelink",       # Vampiric Draught — target friendly + caster heal
		"sacrifice_for_command",# Butcher's Dram — sac target friendly (Command is caster-local)
		"detonate_doom_all",    # Doomsday Draught — non-targeted, caster's Doom bombs
	]




func _net_apply_host_potion(pid: String, caster_is_enemy: bool, target: Control = null) -> void:
	var data: Dictionary = PotionDB.get_potion(pid)
	match String(data.get("effect", "")):
		"heal_hp":
			var heal: int = int(data.get("value", 8)) if data.has("value") else 8
			var before: int = combat.enemy_hp if caster_is_enemy else combat.player_hp
			_net_heal_hero(caster_is_enemy, heal)
			if not caster_is_enemy and combat.player_hp > before:
				combat._show_lifelink_heal(combat.player_hp - before)
		"aoe_enemies":
			for c in _net_side_creatures(not caster_is_enemy):
				c.take_damage(3)
			combat._cleanup_dead()
		"chain_lightning":
			for _i in range(4):
				var pool := _net_side_creatures(not caster_is_enemy)
				if pool.is_empty():
					break
				var pick: Control = pool[randi() % pool.size()]
				pick.take_damage(2)
				if pick.current_hp <= 0:
					combat._cleanup_dead()
		"shield_wall":
			for c in _net_side_creatures(caster_is_enemy):
				c.state.has_shield = true
				if c.has_method("_spawn_keyword_chip"):
					c._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
				c.update_stat_display()
		"summon_recruits":
			var made := 0
			for row in [combat.ROW_FRONT, combat.ROW_BACK]:
				if made >= 2:
					break
				var arr = combat._row_array(caster_is_enemy, row)
				for lane in range(combat.LANES_PER_ROW):
					if made >= 2:
						break
					if arr[lane] == null:
						combat.summon_token(3, 3, lane, caster_is_enemy, row)
						var recruit = combat._row_array(caster_is_enemy, row)[lane]
						if recruit != null and is_instance_valid(recruit):
							recruit.card_data["name"] = "Recruit"
							if recruit.has_method("_spawn_keyword_chip"):
								recruit._spawn_keyword_chip("RECRUIT", Color(0.82, 0.70, 0.48))
							recruit.update_stat_display()
						made += 1
		"revive_last_dead":
			var side := 1 if caster_is_enemy else 0
			var grave: Dictionary = combat._net_last_dead[side]
			if not grave.is_empty():
				var gd: Dictionary = grave.get("data", {})
				var keywords: Array = gd.get("keywords", [])
				_net_place_token(caster_is_enemy, 1, 1,
					String(gd.get("name", "Revived")), keywords)
		"column_strike":
			# Sapper's Charge: 4 to the target creature + its lane-mate in the other
			# row. target.is_opponent picks the correct side array regardless of
			# which peer cast (it lives on the caster's FOE side).
			if target != null and is_instance_valid(target) and target.is_creature():
				var sap_lane: int = target.current_lane
				var sap_other: int = combat.ROW_BACK if target.current_row == combat.ROW_FRONT else combat.ROW_FRONT
				var sap_mate: Control = combat._row_array(target.is_opponent, sap_other)[sap_lane]
				target.take_damage(4)
				if sap_mate != null and is_instance_valid(sap_mate):
					sap_mate.take_damage(4)
				combat._cleanup_dead()
		"grant_rampage":
			# War Paint: Rampage 2 + +1 ATK on the caster's own creature for the
			# fight. The keyword + effective ATK both ride the board snapshot, so
			# the foe sees the chip and the buffed stat.
			if target != null and is_instance_valid(target) and target.is_creature():
				if "rampage" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("rampage")
				target.card_data["rampage"] = maxi(2, int(target.card_data.get("rampage", 0)))
				target.persistent_atk_buff += 1
				target.persistent_atk_buff_rounds = 99
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("RAMPAGE", Color(1.0, 0.62, 0.20))
				target.update_stat_display()
		"grant_lifelink":
			# Vampiric Draught: Lifesteal on a friendly for the fight + a 4 HP
			# caster top-up (host-authoritative HP).
			if target != null and is_instance_valid(target) and target.is_creature():
				if "lifelink" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("lifelink")
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LIFESTEAL", Color(0.95, 0.35, 0.45))
				target.update_stat_display()
			_net_heal_hero(caster_is_enemy, 4)
		"sacrifice_for_command":
			# Butcher's Dram: kill the caster's own target (the +3 Command already
			# landed caster-side in _net_use_potion). The 999 mirrors the Offering
			# spell; solo's relic/reactive sacrifice hooks don't exist in skirmish,
			# so a plain kill is faithful.
			if target != null and is_instance_valid(target) and target.is_creature():
				target.take_damage(999)
				combat._cleanup_dead()
		"detonate_doom_all":
			# Doomsday Draught: fire every one of the caster's own Doom creatures
			# now. _detonate_doom attributes face damage by is_opponent, so on the
			# host it hits the correct hero for either caster.
			var bombs: Array = []
			for c in _net_side_creatures(caster_is_enemy):
				if c.has_keyword("doom"):
					bombs.append(c)
			for c in bombs:
				if is_instance_valid(c) and c.current_hp > 0:
					combat._detonate_doom(c)
			combat._cleanup_dead()




func _net_side_creatures(is_enemy: bool) -> Array:
	var out: Array = []
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(is_enemy, row):
			if c != null and is_instance_valid(c) and c.current_hp > 0:
				out.append(c)
	return out




## Tell the opponent we drank potion `pid` so their side shows a drink beat (the
## potion never touches THEIR state — this is presentation only, the mirror of
## our own drink). Host → event, client → intent, like the discard beat.
func _net_send_potion_fx(pid: String) -> void:
	var msg := {"t": NetMatch.EV_POTION_FX, "pid": pid}
	if combat._is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)




## The foe drank a potion — a Hearthstone-style reveal: the bottle lifts off
## their arsenal rail, blooms enlarged over the enemy half of the board with its
## name on a plate, holds a beat, then burns out. The rail chip drains to a dim
## empty husk so the belt tracks what they have left. Reduce-motion keeps the
## old floating-text beat (plus the chip drain, which is state, not motion).
func _net_show_foe_potion_fx(pid: String) -> void:
	if combat._hud_layer == null:
		return
	var data: Dictionary = PotionDB.get_potion(pid)
	var nm: String = String(data.get("name", "a potion"))
	var col: Color = data.get("color", Color(0.82, 0.74, 0.58))
	if AudioBank != null:
		AudioBank.play_sfx("potion_use", 0.06, -3.0)
	var rail_chip: Control = _net_foe_consume_potion_chip(pid)
	# Keep our copy of the foe's slot honest: the drinker consumes from ITS OWN
	# slot only, so without this a Bo3 game-2 rail (rebuilt from our copy) would
	# show a bottle they already drank in game 1.
	var fx_opp_slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(SkirmishState.opponent_index())
	if fx_opp_slot != null:
		fx_opp_slot.potions.erase(pid)
	if UserSettings != null and UserSettings.reduce_motion:
		var anchor = Vector2(combat.get_viewport_rect().size.x * 0.5, 120.0)
		if combat._enemy_hp_label != null and is_instance_valid(combat._enemy_hp_label):
			anchor = combat._enemy_hp_label.get_global_rect().get_center() + Vector2(0.0, 34.0)
		combat.spawn_floating_number(anchor, "FOE DRINKS: %s" % nm.to_upper(), col, false)
		return
	_net_show_potion_reveal(pid, nm, col, rail_chip)




## HS "opponent played a card" reveal for a foe potion: a big framed bottle chip
## with the potion's name flies from its rail slot (or the enemy plate), blooms
## at center over the enemy rows with a colour-burst ring, holds long enough to
## read, then fades upward. Pure presentation — the effect resolves elsewhere.
func _net_show_potion_reveal(pid: String, nm: String, col: Color, from_chip: Control) -> void:
	const CHIP := 116.0
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 60
	combat._hud_layer.add_child(holder)
	# Children are laid out around the holder's ORIGIN, so scaling the holder
	# (pivot_offset default 0,0) blooms the whole reveal around its center.
	var chip := GameTheme.make_potion_chip(pid, int(CHIP))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Plain-Control parent: size must be set by hand (custom_minimum_size only
	# binds inside containers — an unsized Panel renders as nothing).
	chip.size = Vector2(CHIP, CHIP)
	chip.position = Vector2(-CHIP * 0.5, -CHIP * 0.5)
	holder.add_child(chip)
	var caption = combat._make_rail_caption("THE FOE DRINKS")
	caption.position = Vector2(-160.0, -CHIP * 0.5 - 34.0)
	caption.size = Vector2(320.0, 24.0)
	holder.add_child(caption)
	var name_lbl := Label.new()
	name_lbl.text = nm.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	name_lbl.add_theme_constant_override("outline_size", 6)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		name_lbl.add_theme_font_override("font", GameTheme.font_display)
	name_lbl.position = Vector2(-180.0, CHIP * 0.5 + 8.0)
	name_lbl.size = Vector2(360.0, 32.0)
	holder.add_child(name_lbl)
	# From the drained rail chip when it exists, else the enemy plate — to a
	# bloom point over the enemy rows (upper-center, clear of the title band).
	var vp = combat.get_viewport_rect().size
	var dest = Vector2(vp.x * 0.5, vp.y * 0.34)
	var start = dest
	if from_chip != null and is_instance_valid(from_chip):
		start = from_chip.get_global_rect().get_center()
	elif combat._enemy_banner_for_info != null and is_instance_valid(combat._enemy_banner_for_info):
		start = combat._enemy_banner_for_info.get_global_rect().get_center()
	holder.global_position = start
	holder.scale = Vector2(0.35, 0.35)
	holder.modulate.a = 0.0
	var tw = combat.create_tween().set_parallel(true)
	tw.tween_property(holder, "global_position", dest, UserSettings.anim_time(0.34)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "scale", Vector2.ONE, UserSettings.anim_time(0.34)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, UserSettings.anim_time(0.16))
	tw.chain().tween_callback(_spawn_chip_burst.bind(dest, CHIP * 0.72, col))
	tw.chain().tween_interval(UserSettings.anim_time(0.95))
	var out = tw.chain()
	out.tween_property(holder, "modulate:a", 0.0, UserSettings.anim_time(0.30)) \
		.set_ease(Tween.EASE_IN)
	out.parallel().tween_property(holder, "global_position", dest + Vector2(0.0, -46.0),
		UserSettings.anim_time(0.30)).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(holder.queue_free)




## Drain the foe-rail chip for potion `pid`: mark the first unused slot with that
## potion as spent and dim it to an empty husk. Returns the chip (the reveal
## animation launches from it) or null when the rail never listed it.
func _net_foe_consume_potion_chip(pid: String) -> Control:
	for entry in combat._net_foe_potion_slots_ui:
		if bool(entry.get("used", false)) or String(entry.get("pid", "")) != pid:
			continue
		entry["used"] = true
		var chip: Control = entry.get("chip", null)
		if chip == null or not is_instance_valid(chip):
			return null
		chip.pivot_offset = chip.size * 0.5
		if UserSettings != null and UserSettings.reduce_motion:
			chip.modulate = Color(0.45, 0.42, 0.38, 0.55)
		else:
			var tw = combat.create_tween().set_parallel(true)
			tw.tween_property(chip, "modulate", Color(0.45, 0.42, 0.38, 0.55),
				UserSettings.anim_time(0.45)).set_ease(Tween.EASE_OUT)
			tw.tween_property(chip, "scale", Vector2(0.9, 0.9),
				UserSettings.anim_time(0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return chip
	return null




# ── Foe's arsenal rail (skirmish): the opponent's drafted relic + potion ─────
#
#  HS shows you the opponent's weapon and trinkets on their side of the table;
#  this is that rail for the skirmish draft picks. Both peers exchanged their
#  relic + potion ids in NetDraft's deck handoff, so the data is already local —
#  this only makes it VISIBLE. Chips reuse the GameTheme relic/potion kit, so
#  the rich hover (name + rules) comes free; trigger/drink beats animate them.

func _net_build_foe_arsenal() -> void:
	if combat._hud_layer == null or combat._net_foe_rail_root != null:
		return
	var opp_slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(SkirmishState.opponent_index())
	if opp_slot == null:
		return
	var rids: Array = []
	for rid in opp_slot.relics:
		if not RelicDB.get_relic(String(rid)).is_empty():
			rids.append(String(rid))
	var pids: Array = []
	for pid in opp_slot.potions:
		if not PotionDB.get_potion(String(pid)).is_empty():
			pids.append(String(pid))
	if rids.is_empty() and pids.is_empty():
		return   # the foe declined both drafts — no rail, no orphan caption
	# Right rail, directly under the foe's Command seal (which ends at y 556),
	# spanning the enemy column's full plate width. The glossary "?" orb
	# (bottom-anchored, x -72..-24, y ~598 at 900px) stays clear of the
	# centered chip row (2 chips end at x -84).
	const CHIP := 44
	const GAP := 8
	var root := Control.new()
	root.name = "NetFoeArsenal"
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.anchor_top = 0.0
	root.anchor_bottom = 0.0
	root.offset_left = -250
	root.offset_right = -14
	root.offset_top = 560
	root.offset_bottom = 560 + 26 + CHIP
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 5
	combat._hud_layer.add_child(root)
	combat._net_foe_rail_root = root
	var caption = combat._make_rail_caption("FOE'S ARSENAL")
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.offset_top = 0
	caption.offset_bottom = 20
	root.add_child(caption)
	var n: int = rids.size() + pids.size()
	var total_w: float = float(n * CHIP + (n - 1) * GAP)
	var x: float = (236.0 - total_w) * 0.5
	# Plain-Control parent: chip sizes must be set by hand (custom_minimum_size
	# only binds inside containers — an unsized Panel renders as nothing).
	for rid in rids:
		var chip := GameTheme.make_relic_chip(rid, CHIP)
		chip.size = Vector2(CHIP, CHIP)
		chip.position = Vector2(x, 26.0)
		root.add_child(chip)
		combat._net_foe_relic_chips[rid] = chip
		x += CHIP + GAP
	for pid in pids:
		var chip := GameTheme.make_potion_chip(pid, CHIP)
		chip.size = Vector2(CHIP, CHIP)
		chip.position = Vector2(x, 26.0)
		root.add_child(chip)
		combat._net_foe_potion_slots_ui.append({"pid": pid, "chip": chip, "used": false})
		x += CHIP + GAP




# ── Relic trigger beats (HS trinket flash) ────────────────────────────────────
#
#  One funnel for "a relic visibly did its thing": the chip pops + flashes +
#  rings on whichever rail owns it, and in skirmish the beat crosses the wire
#  (EV_RELIC_FX) so the OPPONENT sees your relic fire on their foe rail. Wire
#  new trigger sites through _relic_fired (local resource relics — each peer
#  fires its own) or _relic_fired_for_side (host-authoritative board relics).

## A LOCAL relic paid out on this machine (solo player or net local side).
func _relic_fired(rid: String) -> void:
	_pulse_relic_chip(rid, false)
	if combat._is_net():
		_net_send_relic_fx(rid, true)




## Host-side hooks that resolve a relic for EITHER warband (the
## _relic_active_for_side sites) report through here with the owner side.
func _relic_fired_for_side(owner_is_enemy: bool, rid: String) -> void:
	if not combat._is_net():
		if not owner_is_enemy:
			_pulse_relic_chip(rid, false)
		return
	# Net host: owner false = my relic (own rail, tell the client "foe relic
	# fired"); owner true = the client's relic (my foe rail, tell the client
	# "YOUR relic fired" so it pulses its own grid).
	_pulse_relic_chip(rid, owner_is_enemy)
	_net_send_relic_fx(rid, not owner_is_enemy)




## Tell the opponent about a relic beat. `mine` is from the SENDER's view.
## Host → event, client → intent — the EV_POTION_FX channel's shape.
func _net_send_relic_fx(rid: String, mine: bool) -> void:
	var msg := {"t": NetMatch.EV_RELIC_FX, "rid": rid, "mine": mine}
	if combat._is_host():
		NetMatch.send_to_client(msg)
	else:
		NetMatch.send_intent(msg)




func _net_on_relic_fx(msg: Dictionary) -> void:
	# mine is the sender's perspective: their relic → our FOE rail; the host
	# saying mine=false means OUR board relic fired host-side → our own rail.
	_pulse_relic_chip(String(msg.get("rid", "")), bool(msg.get("mine", true)))




## The HS trinket flash on a relic chip: scale pop (back-eased), bright flash,
## and an expanding gilt ring. `foe` picks the rail. Debounced per chip so a
## multi-part trigger (Tome of Many's two draws, Bulwark over a wall) reads as
## ONE beat. Foe triggers also float the relic's name — your own relics you
## know by sight; theirs need the attribution.
func _pulse_relic_chip(rid: String, foe: bool) -> void:
	if rid == "":
		return
	var key := "%s|%d" % [rid, 1 if foe else 0]
	var now := Time.get_ticks_msec()
	if now - int(combat._relic_fx_gate.get(key, -10000)) < 450:
		return
	combat._relic_fx_gate[key] = now
	var chip: Control = combat._net_foe_relic_chips.get(rid, null) if foe \
		else combat._relic_chip_by_id.get(rid, null)
	if chip == null or not is_instance_valid(chip):
		return
	if AudioBank != null:
		AudioBank.play_sfx("relic_trigger", 0.05, -9.0, 1.3)
	if foe:
		# Attribution chip (self-centering callout). The rail hugs the screen
		# edge, so clamp the anchor inward — a long relic name centered on the
		# chip itself would run off the right side.
		var r := RelicDB.get_relic(rid)
		var anchor: Vector2 = chip.get_global_rect().get_center() + Vector2(0.0, -34.0)
		anchor.x = clampf(anchor.x, 150.0, combat.get_viewport_rect().size.x - 150.0)
		combat.spawn_keyword_callout(anchor, String(r.get("name", rid)).to_upper(),
			GameTheme.GILT_BRIGHT, null)
	if UserSettings != null and UserSettings.reduce_motion:
		return
	chip.pivot_offset = chip.size * 0.5
	var tw = combat.create_tween()
	tw.tween_property(chip, "scale", Vector2(1.4, 1.4), UserSettings.anim_time(0.14)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "scale", Vector2.ONE, UserSettings.anim_time(0.26)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var fl = combat.create_tween()
	fl.tween_property(chip, "modulate", Color(1.8, 1.65, 1.25), UserSettings.anim_time(0.10))
	fl.tween_property(chip, "modulate", Color.WHITE, UserSettings.anim_time(0.30))
	_spawn_chip_burst(chip.get_global_rect().get_center(), chip.size.x * 0.72,
		GameTheme.GILT_BRIGHT)




## An expanding, fading ring — the "trigger burst" both the relic pulse and the
## potion reveal use. Drawn as a border-only rounded panel scaled from within.
func _spawn_chip_burst(center: Vector2, radius: float, color: Color) -> void:
	if combat._hud_layer == null:
		return
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = 59
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = color
	st.set_border_width_all(3)
	st.set_corner_radius_all(int(radius))
	ring.add_theme_stylebox_override("panel", st)
	ring.size = Vector2(radius * 2.0, radius * 2.0)
	ring.pivot_offset = ring.size * 0.5
	ring.global_position = center - ring.size * 0.5
	ring.scale = Vector2(0.55, 0.55)
	combat._hud_layer.add_child(ring)
	var tw = combat.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.6, 1.6), UserSettings.anim_time(0.42)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, UserSettings.anim_time(0.42)) \
		.set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)




## Store the opponent's synced Command and refresh the foe's wax seal numeral.
## Mirrors _update_hud's player-mana formatting (banked carryover shown as "(+N)").
func _net_set_opp_mana(cur: int, mx: int) -> void:
	combat._net_opp_mana = cur
	combat._net_opp_max_mana = mx
	if combat._net_opp_mana_label == null or not is_instance_valid(combat._net_opp_mana_label):
		return
	combat._set_seal_readout(combat._net_opp_mana_label,
		"%d / %d" % [combat._net_opp_mana, combat._net_opp_max_mana])




## The "Opponent's turn" line, annotated with their hand size when we know it.
func _net_opp_turn_msg() -> String:
	if combat._net_opp_hand_count > 0:
		return "Opponent's turn — %d in hand" % combat._net_opp_hand_count
	return "Opponent's turn…"




# ── Opponent's hand (face-down fan by the enemy plate) ───────────────────────
#
#  A small fan of face-down card backs, the way other card games show the foe's
#  hand. Placed in the gap just LEFT of the enemy plate (top-right): next to the
#  foe, clear of the centred title, above the board. You see THAT they hold cards
#  and how many — never what they are. Driven by _net_opp_hand_count.

func _net_build_opp_hand_ui() -> void:
	if combat._hud_layer == null or combat._net_opp_hand_box != null:
		return
	if combat._net_card_back_tex == null:
		combat._net_card_back_tex = load("res://assets/ui/card_back.png") as Texture2D

	# Box sits in the gap between the centred title (right edge ~x1100) and the
	# enemy plate (left edge x1350). Right-anchored so it tracks the plate.
	combat._net_opp_hand_box = Control.new()
	combat._net_opp_hand_box.name = "NetOppHand"
	combat._net_opp_hand_box.anchor_left = 1.0
	combat._net_opp_hand_box.anchor_right = 1.0
	combat._net_opp_hand_box.anchor_top = 0.0
	combat._net_opp_hand_box.anchor_bottom = 0.0
	combat._net_opp_hand_box.offset_left = -494   # ~x1106
	combat._net_opp_hand_box.offset_right = -250  # x1350 (the plate's left edge)
	combat._net_opp_hand_box.offset_top = 0.0
	combat._net_opp_hand_box.offset_bottom = 96.0
	combat._net_opp_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat._net_opp_hand_box.z_index = 6
	combat._net_opp_hand_box.visible = false
	combat._hud_layer.add_child(combat._net_opp_hand_box)

	var label := Label.new()
	# Name the fan after the foe's chosen lord — "OPPONENT" was a placeholder.
	label.text = String(HeroDB.get_hero(combat._foe_hero_id()).get("name", "Opponent")).to_upper()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.90, 0.80, 0.60, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_top = 74.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_display:
		label.add_theme_font_override("font", GameTheme.font_display)
	combat._net_opp_hand_box.add_child(label)

	combat._net_opp_hand_row = Control.new()
	combat._net_opp_hand_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	combat._net_opp_hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat._net_opp_hand_box.add_child(combat._net_opp_hand_row)




## Rebuild the face-down fan from _net_opp_hand_count. Cheap (a few TextureRects
## sharing one texture), so we rebuild on every hand-count change.
func _net_refresh_opp_hand() -> void:
	if combat._net_opp_hand_row == null or not is_instance_valid(combat._net_opp_hand_row):
		return
	if combat._net_opp_hand_box != null:
		combat._net_opp_hand_box.visible = combat._net_opp_hand_count > 0
	for child in combat._net_opp_hand_row.get_children():
		child.queue_free()
	var n: int = combat._net_opp_hand_count
	if n <= 0:
		return
	const BACK_W := 46.0
	const BACK_H := 64.0
	const BASE_Y := 6.0
	var area_w: float = combat._net_opp_hand_box.size.x if combat._net_opp_hand_box != null else 244.0
	# Overlapping fan, centred in the gap. Tighten the spacing as the hand grows so
	# a big hand still fits the narrow gap.
	var spacing: float = BACK_W * 0.62
	var usable: float = area_w - BACK_W - 6.0
	if n > 1 and spacing * float(n - 1) > usable:
		spacing = usable / float(n - 1)
	var total: float = spacing * float(n - 1)
	var start_x: float = (area_w - total) * 0.5
	var mid: float = float(n - 1) * 0.5
	for i in range(n):
		var back := _net_make_card_back(Vector2(BACK_W, BACK_H))
		combat._net_opp_hand_row.add_child(back)
		var off: float = float(i) - mid                 # signed distance from centre
		var norm: float = 0.0 if mid <= 0.0 else off / mid
		# A hand held at the top hangs DOWN: edges ride a little lower, middle highest,
		# with the cards splayed outward (rotated about their bottom-centre).
		var x: float = start_x + float(i) * spacing - BACK_W * 0.5
		var y: float = BASE_Y + norm * norm * 7.0
		back.position = Vector2(x, y)
		back.rotation = off * 0.085




## One face-down card: the shared card-back art, rotated about its bottom-centre
## (the held point of a fanned hand). A soft shadow lifts it off the board.
func _net_make_card_back(sz: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = sz
	holder.size = sz
	holder.pivot_offset = Vector2(sz.x * 0.5, sz.y)   # rotate around the bottom-centre
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow := Panel.new()
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sst := StyleBoxFlat.new()
	sst.bg_color = Color(0.02, 0.015, 0.01, 0.0)
	sst.set_corner_radius_all(4)
	sst.shadow_color = Color(0, 0, 0, 0.5)
	sst.shadow_size = 4
	shadow.add_theme_stylebox_override("panel", sst)
	holder.add_child(shadow)

	if combat._net_card_back_tex != null:
		var pic := TextureRect.new()
		pic.texture = combat._net_card_back_tex
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # shrink the big art into sz
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(pic)
	else:
		# No card-back art — a gilt-edged dark plate still reads as "a card".
		var plate := Panel.new()
		plate.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pst := StyleBoxFlat.new()
		pst.bg_color = Color(0.16, 0.07, 0.06, 0.96)
		pst.border_color = Color(combat.GILT.r, combat.GILT.g, combat.GILT.b, 0.55)
		pst.set_border_width_all(2)
		pst.set_corner_radius_all(4)
		plate.add_theme_stylebox_override("panel", pst)
		holder.add_child(plate)
	return holder




# ── Opponent spell telegraph (arrow + thrown card to the target) ─────────────
#
#  When the opponent casts, we show what they pointed at: a gold arrow from their
#  hand (top) to the struck target, a thrown ghost of the spell card, and the
#  spell's family burst on the target. The casting side already saw its own arrow
#  during target selection, so this only fires for the WATCHER.

## CLIENT: the host announced a spell (EV_SPELL). Resolve the target locally (the
## entity registry is shared by eid) and play the telegraph. Fires before the board
## snapshot, so the target node is still alive even for a lethal spell.
func _net_on_opp_spell_event(event: Dictionary) -> void:
	var data := SkirmishState.skirmish_card_data(String(event.get("id", "")))
	if data.is_empty():
		return
	var teid: int = int(event.get("target", -1))
	var tnode: Control = null
	var tcenter := Vector2.ZERO
	var has_t := false
	if teid >= 0:
		var n = NetMatch.get_entity(teid)
		if n != null and is_instance_valid(n):
			tnode = n
			tcenter = n.get_global_rect().get_center()
			has_t = true
	_net_spell_telegraph(data, tcenter, has_t, tnode)




func _net_spell_telegraph(card_data: Dictionary, target_center: Vector2,
		has_target: bool, target_node: Control) -> void:
	if combat._hud_layer == null:
		return
	var vp = combat.get_viewport_rect().size
	# The opponent casts from their corner — origin at the enemy plate (top-right),
	# so the arrow + thrown card visibly come from the foe.
	var origin = Vector2(vp.x - 130.0, 150.0)
	if combat._enemy_banner_for_info != null and is_instance_valid(combat._enemy_banner_for_info):
		origin = combat._enemy_banner_for_info.get_global_rect().get_center()
	var dest = target_center if has_target else Vector2(vp.x * 0.5, vp.y * 0.4)
	if has_target:
		_net_flash_arrow(origin, dest)
	# Show the opponent's actual card, held readably center-screen. The old quick
	# thrown-ghost (fly-from-corner + shrink in 0.4s) was too fast to read — the
	# whole point of the telegraph is "what did the foe just play?", so reveal the
	# real face. The arrow still carries the from-foe / to-target directionality.
	combat._reveal_cast_card(card_data, "OPPONENT CASTS", Color(0.96, 0.56, 0.34))
	# Battle log — this fires on the peer WATCHING the opponent cast (client sees the
	# host's EV_SPELL; host sees the client's IN_PLAY_SPELL), so it's the foe's cast
	# on both sides. The local caster's own line comes from _net_log_local_cast.
	combat._net_log_foe_cast(card_data, target_node if (has_target and target_node != null \
		and is_instance_valid(target_node)) else null)
	# Burst at the struck point — reuse the family VFX while we still have the node.
	if target_node != null and is_instance_valid(target_node):
		combat._play_spell_cast_vfx(card_data, target_node)
	elif has_target:
		combat.spawn_spell_burst(dest,
			combat._legacy_spell_color(String(card_data.get("spell", {}).get("type", ""))))
	else:
		combat._play_spell_cast_vfx(card_data, null)




## A one-shot version of the targeting arrow (the live one tracks the cursor): a
## gold bezier from the opponent's hand to the target that fades in, holds, fades.
func _net_flash_arrow(from: Vector2, to: Vector2) -> void:
	if combat._hud_layer == null:
		return
	var line := Line2D.new()
	line.width = 7.0
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 239
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.35, 0.55))
	grad.set_color(1, Color(1.0, 0.45, 0.15, 1.0))
	line.gradient = grad
	# Bow the curve downward — the opponent throws the spell down at our board.
	var dir := to - from
	var ctrl1 := from + Vector2(dir.x * 0.15, 150.0)
	var ctrl2 := to + Vector2(0.0, -70.0)
	var points := PackedVector2Array()
	var steps := 26
	for i in range(steps + 1):
		points.append(combat._bezier_cubic(from, ctrl1, ctrl2, to, float(i) / float(steps)))
	line.points = points
	line.modulate.a = 0.0
	combat._hud_layer.add_child(line)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([Vector2(0, 0), Vector2(-22, -10), Vector2(-22, 10)])
	head.color = Color(1.0, 0.40, 0.12, 1.0)
	head.z_index = 240
	head.position = to
	head.modulate.a = 0.0
	if points.size() >= 2:
		var tangent: Vector2 = points[points.size() - 1] - points[points.size() - 2]
		if tangent.length_squared() > 0.01:
			head.rotation = tangent.angle()
	combat._hud_layer.add_child(head)

	var tw = combat.create_tween()
	# Fade in (line + head together), hold, fade out (together), then free.
	tw.tween_property(line, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(head, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.45)
	tw.tween_property(line, "modulate:a", 0.0, 0.30)
	tw.parallel().tween_property(head, "modulate:a", 0.0, 0.30)
	tw.tween_callback(func():
		if is_instance_valid(line): line.queue_free()
		if is_instance_valid(head): head.queue_free())




## The other peer dropped — end cleanly and return to the menu. Handles both the
## mid-match case and the post-match case (opponent declined the rematch / left
## the result screen), which the plain _net_match_over guard would otherwise eat.
func _net_on_peer_lost() -> void:
	if combat._net_match_over:
		# Already on the result screen: the opponent left rather than rematch.
		if combat._net_result_panel != null and is_instance_valid(combat._net_result_panel):
			combat._net_result_panel.queue_free()
			combat._net_result_panel = null
			if combat._phase_label != null:
				combat._phase_label.text = "OPPONENT LEFT"
			combat._show_info("Opponent left — returning to menu…")
			combat.get_tree().create_timer(2.0).timeout.connect(func():
				NetMatch.leave()
				GameTheme.fade_out_then_change_scene(combat, "res://scenes/main_menu.tscn", 0.5))
		return
	combat._net_match_over = true
	combat.phase = combat.Phase.GAME_OVER
	Card2D.board_interactive = false
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = true
	if combat._phase_label != null:
		combat._phase_label.text = "OPPONENT LEFT"
	combat._show_info("Opponent disconnected — returning to menu…")
	combat.get_tree().create_timer(2.5).timeout.connect(func():
		NetMatch.leave()
		GameTheme.fade_out_then_change_scene(combat, "res://scenes/main_menu.tscn", 0.5)
	)




# ── Spells over the wire ─────────────────────────────────────────────────
#
#  Both players' spells resolve on the HOST through _net_resolve_spell, which is
#  perspective-aware (caster_index 0 = host, 1 = client). Explicitly-targeted
#  spells carry their perspective in the target entity_id (take_damage on a node
#  is side-agnostic), so only face / board-wide effects need the caster flip.
#  Spell VFX are coarse in v1 (the client just sees the resulting board snapshot).
#  Supported set is gated at play time so unsupported spells never silently fizzle.

func _net_spell_supported(data: Dictionary) -> bool:
	# The Coin is a granted system card (going-second compensation), not part of the
	# draftable spell economy — always castable, independent of the lists below. It's
	# deliberately kept out of NET_SPELL_CUSTOMS so the draft pool never offers it.
	if String(data.get("id", "")) == "coin":
		return true
	# Single source of truth lives in SkirmishState so the draft pool and this
	# play-time gate can never drift (see SkirmishState.NET_SPELL_TYPES / CUSTOMS).
	return SkirmishState.is_net_playable_spell(data)




## Recycle a just-played skirmish spell into the local player's pile so each side's
## deck cycles exactly as in solo (_play_spell line ~5349): exhaust-keyword spells
## are removed to the exhaust pile, everything else returns to the discard pile to
## be reshuffled. Both the host AND the client call this for their OWN spell, so
## neither warband's deck silently shrinks over a long match. Synthetic/token
## spells (deck_uid < 0) aren't real deck cards and are skipped.
func _net_recycle_spell(card: Control) -> void:
	if card == null or not is_instance_valid(card) or card.deck_uid < 0:
		return
	if card.has_keyword("exhaust"):
		combat._exhaust_pile.append(combat._pile_entry(card.card_id, card.deck_uid))
	else:
		combat._player_discard_pile.append(combat._pile_entry(card.card_id, card.deck_uid))




## Spells whose hand / pile / Command / draw effects resolve on the CASTER's own
## machine (those resources never leave the caster). War Chant & Mass Grave also
## forward a board consequence to the host; the rest are fully caster-local.


## Pitch one hand card to the caster's own discard (a card the player chose to
## discard). Real cards keep their uid; tokens/synthetic cards just vanish.
func _net_pitch_card(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	combat._hand.erase(c)
	if c.get_parent() != null:
		c.get_parent().remove_child(c)
	if c.deck_uid >= 0:
		combat._player_discard_pile.append(combat._pile_entry(c.card_id, c.deck_uid))
	c.queue_free()




## Caster-LOCAL pile/hand spells. The hand, piles, Command and draw all live on the
## caster's machine, so the caster resolves those here (with its own picker UI)
## rather than round-tripping the host. War Chant / Mass Grave forward only their
## BOARD consequence (Soldier count / discard size) for the host to apply. Mirrors
## the solo resolver branches, kept compact so no solo-only spell state is dragged in.
func _net_play_caster_local_spell(card: Control, cost: int) -> void:
	var id: String = card.card_id
	var sid: String = String(card.card_data.get("spell", {}).get("id", ""))
	var plus_draw: int = int(card.card_data.get("extra_draw", 0))
	var spell_start_global: Vector2 = card.global_position
	combat._net_log_local_cast(card.card_data, null)   # "You cast X." (hand/pile spell)
	# Spend Command + pull the card from hand up front (matches the generic path).
	combat.player_mana -= cost
	combat._pulse_mana_label(cost)
	combat._first_spell_this_turn = true   # Witch's first-spell discount rests (parity w/ solo)
	combat._hand.erase(card)
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	combat._spawn_spell_cast_ghost(card.card_data, spell_start_global, null)
	combat._play_spell_cast_vfx(card.card_data, null)
	var board_n: int = 0          # board consequence to forward (War Chant / Mass Grave)
	match sid:
		"recycle":
			if combat._hand.size() > 0:
				var rp: Control = await combat._show_recycle_modal()
				if rp != null and is_instance_valid(rp):
					var rcost: int = int(rp.card_data.get("cost", 0))
					combat._hand.erase(rp)
					if rp.get_parent() != null:
						rp.get_parent().remove_child(rp)
					combat._exhaust_pile.append(combat._pile_entry(rp.card_id, rp.deck_uid))
					rp.queue_free()
					combat.player_mana += rcost
					for _i in plus_draw:
						combat.draw_one()
		"gambit":
			var gmax: int = mini(3, combat._hand.size())
			if gmax > 0:
				var gp: Array = await combat._show_discard_picker(gmax,
					"Gambit — discard up to %d, draw that many" % gmax, true)
				for c in gp:
					_net_pitch_card(c)
				for _gi in gp.size():
					combat.draw_one()
		"turbo":
			combat.player_mana += 2
			for _i in plus_draw:
				combat.draw_one()
			combat._player_discard_pile.append(CardDB.random_curse_id())
		"war_chant":
			var wmax: int = mini(3, combat._hand.size())
			if wmax > 0:
				var wp: Array = await combat._show_discard_picker(wmax,
					"War Chant — discard up to %d to muster that many Soldiers" % wmax, true)
				for c in wp:
					_net_pitch_card(c)
				board_n = wp.size()
		"mass_grave":
			board_n = combat._player_discard_pile.size()
	# Forward the board consequence: host resolves locally + syncs; client ships the
	# count as an IN_PLAY_SPELL the host applies via _net_resolve_custom_spell.
	if sid == "war_chant" or sid == "mass_grave":
		if combat._is_host():
			var hdata: Dictionary = card.card_data.duplicate(true)
			hdata["_net_picks"] = board_n
			_net_resolve_spell(hdata, -1, 0)
			NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": id, "target": -1})
			_net_sync_board()
		else:
			NetMatch.send_intent({"t": NetMatch.IN_PLAY_SPELL, "uid": card.deck_uid,
				"id": id, "target": -1, "n": board_n})
	# Recycle the spell card itself, then refresh the local UI / hand count.
	_net_recycle_spell(card)
	if is_instance_valid(card):
		card.queue_free()
	_net_broadcast_hand_count()
	combat._layout_hand()
	combat._update_hud()




## Local entry for a spell play (host or client). Non-targeted resolve/send now;
## targeted spells enter the normal targeting mode and finish in _try_resolve_target.
func _net_play_spell(card: Control, cost: int) -> void:
	# SEALED ORDERS: deployment is secret, spellcraft is open — spells belong to
	# the sorcery window after the reveal, and only on your own step. (This is
	# the one gate that covers the HOST too; the client is also caught by the
	# _net_active_index turn gates.)
	if _is_sealed():
		if combat._sorcery_active < 0:
			combat._show_info("Spells wait for the reveal — creatures only while orders are sealed.")
			combat._layout_hand()
			return
		if combat._sorcery_active != NetMatch.local_player_index:
			combat._show_info("The foe's spell step — yours comes next.")
			combat._layout_hand()
			return
	var data: Dictionary = card.card_data
	if not _net_spell_supported(data):
		combat._show_info("That spell isn't in skirmish yet.")
		combat._layout_hand()
		return
	# Caster-local pile/hand spells resolve their hand part on the caster's own
	# machine (the hand/piles/Command live here, not on the host) — route them out.
	if String(data.get("spell", {}).get("id", "")) in combat._NET_CASTER_LOCAL_SPELLS:
		await _net_play_caster_local_spell(card, cost)
		return
	var targeting: String = String(data.get("targeting", "none"))
	var uid: int = card.deck_uid
	var id: String = card.card_id
	var spell_start_global: Vector2 = card.global_position
	combat.player_mana -= cost
	combat._pulse_mana_label(cost)
	combat._first_spell_this_turn = true   # Witch's first-spell discount rests (parity w/ solo)
	combat._hand.erase(card)
	combat._hand_container.remove_child(card)
	combat._spawn_spell_cast_ghost(data, spell_start_global, null)
	if targeting == "none":
		combat._net_log_local_cast(data, null)   # "You cast X." (non-targeted)
		combat._play_spell_cast_vfx(data, null)
		if combat._is_host():
			_net_resolve_spell(data, -1, 0)
			# Tell the client what we cast (no target) — sent before the board snapshot
			# so its telegraph plays, then the result reconciles.
			NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": id, "target": -1})
			_net_sync_board()
		else:
			NetMatch.send_intent({"t": NetMatch.IN_PLAY_SPELL, "uid": uid, "id": id, "target": -1})
		_net_recycle_spell(card)
		card.queue_free()
		_net_broadcast_hand_count()
		combat._update_hud()
	else:
		# Hold the card in targeting mode; _net_cast_targeted finishes the cast.
		combat._targeting_spell = card
		combat._targeting_data = data
		combat._show_info("Click a target...")
		combat._show_targeting_arrow()
		combat._update_hud()




## Finish a targeted skirmish spell once the player clicked a target (or face).
func _net_cast_targeted(spell_card: Control, target: Control) -> void:
	var eid: int = -1
	if target != null and is_instance_valid(target):
		eid = int(target.entity_id)
	combat._net_log_local_cast(spell_card.card_data, target)   # "You cast X on Y."
	combat._play_spell_cast_vfx(spell_card.card_data, target)
	if combat._is_host():
		_net_resolve_spell(spell_card.card_data, eid, 0)
		# Tell the client which target we pointed at — sent before the board snapshot
		# so the arrow + thrown card play, then the result reconciles.
		NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": spell_card.card_id, "target": eid})
		_net_sync_board()
	else:
		NetMatch.send_intent({
			"t": NetMatch.IN_PLAY_SPELL, "uid": spell_card.deck_uid,
			"id": spell_card.card_id, "target": eid,
		})
	_net_recycle_spell(spell_card)
	if is_instance_valid(spell_card):
		spell_card.queue_free()
	_net_broadcast_hand_count()
	combat._update_hud()




## HOST: apply the client's spell intent (caster perspective = index 1).
func _net_apply_remote_spell(intent: Dictionary) -> void:
	if combat._net_active_index != 1:
		return
	var data := SkirmishState.skirmish_card_data(String(intent.get("id", "")))
	if data.is_empty() or not _net_spell_supported(data):
		return
	# Caster-local pile spells (War Chant / Mass Grave) resolve their hand part on the
	# client and forward only the board consequence as a pick/size count.
	if intent.has("n"):
		data = data.duplicate(true)
		data["_net_picks"] = int(intent.get("n", 0))
	var target_eid: int = int(intent.get("target", -1))
	# Capture the target's screen position BEFORE resolving — _net_resolve_spell
	# runs _cleanup_dead, which can free the node a lethal spell just killed.
	var tnode: Control = null
	var tcenter := Vector2.ZERO
	var has_t := false
	if target_eid >= 0:
		var n = NetMatch.get_entity(target_eid)
		if n != null and is_instance_valid(n):
			tnode = n
			tcenter = n.get_global_rect().get_center()
			has_t = true
	_net_resolve_spell(data, target_eid, 1)
	# The host is the watcher of the client's spell — show its arrow + thrown card.
	_net_spell_telegraph(data, tcenter, has_t,
		tnode if (tnode != null and is_instance_valid(tnode)) else null)
	_net_sync_board()




## HOST-only, perspective-aware spell resolution. caster_index: 0 = host (player
## side), 1 = client (enemy side, host POV). Target effects use the node directly
## (side-agnostic); face / board-wide effects key off the caster's side.
func _net_resolve_spell(data: Dictionary, target_eid: int, caster_index: int) -> void:
	if not combat._is_host():
		return
	var caster_is_enemy: bool = caster_index == 1
	var spell: Dictionary = data.get("spell", {})
	var stype: String = String(spell.get("type", ""))
	var value: int = int(spell.get("value", 0))
	# Worn Spellbook (board relic, host-authoritative): the caster's damage spells
	# deal +1. Built-in damage types here; custom damage spells fold it into `plus`
	# in _net_resolve_custom_spell. Mirrors the solo path (see _resolve_spell).
	if combat._relic_active_for_side(caster_is_enemy, "worn_spellbook") \
			and stype in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		value += 1
		_relic_fired_for_side(caster_is_enemy, "worn_spellbook")
	var permanent: bool = bool(spell.get("permanent", false))
	var target: Control = null
	if target_eid >= 0:
		var node = NetMatch.get_entity(target_eid)
		if node != null and is_instance_valid(node):
			target = node
	var caster_friendlies: Array = combat._all_friendly(caster_is_enemy)
	var caster_foes: Array = combat._all_friendly(not caster_is_enemy)
	match stype:
		"damage":
			if target != null:
				target.take_damage(value)
		"damage_face":
			_net_damage_hero(not caster_is_enemy, value)
		"damage_all_enemies":
			for c in caster_foes:
				c.take_damage(value)
		"damage_all":
			for c in combat._all_creatures_both_sides():
				c.take_damage(value)
		"buff_atk":
			if target != null:
				if permanent:
					target.current_atk += value
				else:
					target.temp_atk_buff += value
				target.update_stat_display()
		"buff_hp":
			if target != null:
				target.current_hp += value
				target.card_data.hp = int(target.card_data.get("hp", target.current_hp)) + value
				target.update_stat_display()
		"heal":
			if target != null:
				target.current_hp = mini(target.current_hp + value, int(target.card_data.get("hp", target.current_hp)))
				target.update_stat_display()
		"buff_all_atk":
			for c in caster_friendlies:
				if permanent:
					c.current_atk += value
				else:
					c.temp_atk_buff += value
				c.update_stat_display()
		"custom":
			_net_resolve_custom_spell(String(spell.get("id", "")), target, caster_is_enemy, data)
	combat._cleanup_dead()
	# Remember the last host-resolved spell (and its target) for Echo — but never
	# Echo itself, so a chain of Echoes can't form. Caster-local pile spells don't
	# pass through here, so Echo only ever copies a board/damage/buff spell.
	if String(spell.get("id", "")) != "echo_spell":
		combat._net_last_spell_data = data.duplicate(true)
		combat._net_last_spell_target_eid = target_eid
	# Count this cast for the active side's combo spells (flame_bolt). Incremented
	# AFTER resolution so a combo spell reads the count of PRIOR spells this turn.
	combat._net_spells_this_turn += 1
	# Per-spell passives for the CASTER's side (the solo spell path's Hexblade /
	# Emberwright loops never run over the wire). Hexblade grows +1 ATK per spell;
	# Emberwright pings the caster's enemy face. The per-side fight tally lets a
	# freshly-played Hexblade read its owner's spell count (_apply_play_time_passives).
	combat._net_spells_fight[caster_index] += 1
	combat._net_cards_played[caster_index] += 1   # spells count as cards this turn (Ironclad)
	for _sp in combat._all_friendly(caster_is_enemy):
		match _sp.card_data.get("passive", ""):
			"atk_per_spell":
				_sp.temp_atk_buff += 1   # this round only (resets end of turn)
				_sp.update_stat_display()
			"ember_per_spell":
				_hurt_opposing_hero(caster_is_enemy, 3 if bool(_sp.card_data.get("is_upgraded", false)) else 2)




func _net_resolve_custom_spell(spell_id: String, target: Control, caster_is_enemy: bool, data: Dictionary) -> void:
	spell_id = combat._canonical_custom_spell_id(spell_id)
	# Perspective-aware ports of the solo custom spells that need NO draw / pile /
	# gold / Command-gain / sacrifice / Discover / hand-picker — those resolve wrong
	# host-only and stay deferred until pile+draw sync lands. Keep this match in sync
	# with SkirmishState.NET_SPELL_CUSTOMS (tools/_probe_skirmish.gd checks parity).
	#
	# caster_is_enemy = the caster sits on the HOST's enemy side (i.e. the client).
	# Target effects operate on the node directly (the node carries its own side, so
	# no flip). Side-relative effects use the caster's own / enemy side:
	#   friendlies = the caster's creatures   foes = the caster's opponents
	#   caster's enemy face  = _net_damage_hero(not caster_is_enemy, v)
	#   caster's own   face  = _net_damage_hero(caster_is_enemy, v)
	var plus: int = int(data.get("dmg_bonus", 0))
	# Worn Spellbook (board relic): +1 to the caster's PURE-damage custom spells.
	# Folded into `plus` — safe because for every id below `plus` is used ONLY on
	# damage expressions (never an ATK/heal/buff line). Mirrors the solo
	# spell_dmg_bonus inclusion set: excludes hex (debuff), holy_smite (execute),
	# cataclysm / fuel_the_pyre (ATK-scaled), apocalypse (999), and self-face hits.
	if combat._relic_active_for_side(caster_is_enemy, "worn_spellbook") and spell_id in [
			"immolate", "inferno", "wildfire", "petard", "earthquake", "blood_tithe",
			"flame_bolt", "ricochet", "quick_shot", "slash", "smite_spell",
			"ballista_bolt"]:
		plus += 1
		_relic_fired_for_side(caster_is_enemy, "worn_spellbook")
	var plus_draw: int = int(data.get("extra_draw", 0))
	var is_plus: bool = bool(data.get("is_upgraded", false))
	var friendlies: Array = combat._all_friendly(caster_is_enemy)
	var foes: Array = combat._all_friendly(not caster_is_enemy)
	match spell_id:
		"shove":
			# Into-the-Breach flank push — mirrors the 2026-07-09 solo rework.
			# _flank_push is side-agnostic (reads the node's own position), and
			# "nearest flank" is symmetric, so no perspective flip is needed.
			if target != null:
				if plus > 0:
					target.take_damage(plus)
				if is_instance_valid(target) and target.current_hp > 0:
					combat._flank_push(target, 2)
				combat._cleanup_dead()
				combat._refresh_adjacency_buffs()
		"hex":
			if target != null:
				var had_keywords: bool = combat._strip_hex_keywords(target)
				target.take_damage((4 if had_keywords else 1) + plus)
		"second_wind":
			if target != null:
				target.current_hp = int(target.card_data.get("hp", target.current_hp))
				target.current_atk += 1
				target.update_stat_display()
		"soul_swap":
			if target != null:
				var eff_atk: int = target.effective_atk()
				var new_atk: int = target.current_hp
				# Floor swapped HP at 1 (see single-player soul_swap): a 0-ATK body
				# would otherwise swap to 0 HP and be culled silently.
				var new_hp: int = maxi(1, eff_atk)
				target.current_atk = maxi(0, new_atk - target.temp_atk_buff - target.persistent_atk_buff)
				target.current_hp = new_hp
				target.card_data.hp = new_hp
				target.update_stat_display()
				# Upgraded Soul Swap: the promised "+ takes 2 damage" parting blow.
				if plus > 0:
					target.take_damage(plus)
		"testudo":
			# The caster's front line locks shields (both rows forged). Shield
			# state ships in the board snapshot (shd), so the client renders it.
			for tst_row in ([combat.ROW_FRONT, combat.ROW_BACK] if is_plus else [combat.ROW_FRONT]):
				for tst_c in combat._row_array(caster_is_enemy, tst_row):
					if tst_c != null and is_instance_valid(tst_c) and tst_c.current_hp > 0 \
							and not tst_c.state.has_shield:
						tst_c.state.has_shield = true
						if tst_c.has_method("_spawn_keyword_chip"):
							tst_c._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
						tst_c.update_stat_display()
		"barricade":
			if target != null:
				target.current_hp += 4
				target.card_data.hp = int(target.card_data.get("hp", target.current_hp)) + 4
				if "armored" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("armored")
				target.update_stat_display()
		"censer_light":
			# All the caster's ZEALOTS gain Lifesteal for the fight ("+" adds
			# +1 ATK). Keyword + folded buff ride the board snapshot, so the
			# client renders both.
			for zc in friendlies:
				if not is_instance_valid(zc) or String(zc.card_data.get("ctype", "")) != "zealot":
					continue
				if "lifelink" not in zc.card_data.get("keywords", []):
					zc.card_data.keywords.append("lifelink")
				if plus > 0:
					zc.persistent_atk_buff += plus
					zc.persistent_atk_buff_rounds = 99
				if zc.has_method("_spawn_keyword_chip"):
					zc._spawn_keyword_chip("LIFESTEAL", Color(0.95, 0.35, 0.45))
				zc.update_stat_display()
		"virulence":
			# The caster's side attacks poisonously this round — the shared strike
			# code reads the per-side flag, so it covers later plays too. Decays in
			# _net_decay_side_states after the clash.
			combat._virulence_active[1 if caster_is_enemy else 0] = true
			for c in friendlies:
				combat.spawn_keyword_callout_kw(c, "poison")
		"lightning":
			if target != null:
				target.take_damage(2 + plus)
			_net_damage_hero(not caster_is_enemy, 1 + plus)
		"immolate":
			if target != null:
				var imm: int = 4 + plus
				target.take_damage(imm)
				if target.current_hp <= 0:
					_net_damage_hero(not caster_is_enemy, imm)
		"cataclysm":
			if target != null:
				var cat_hit: int = target.effective_atk() + plus
				var first_lane: int = maxi(0, target.current_lane - 1)
				var last_lane: int = mini(combat.LANES_PER_ROW - 1, target.current_lane + 1)
				for lane in range(first_lane, last_lane + 1):
					for row in [combat.ROW_FRONT, combat.ROW_BACK]:
						var victim = combat._row_array(not caster_is_enemy, row)[lane]
						if victim != null and is_instance_valid(victim) and victim.current_hp > 0:
							victim.take_damage(cat_hit)
		"inferno":
			for c in foes:
				c.take_damage(4 + plus)
			_net_damage_hero(not caster_is_enemy, 4 + plus)
		"wildfire":
			var wf_kills: int = 0
			for c in foes:
				if is_instance_valid(c):
					var hp_before: int = c.current_hp
					c.take_damage(2 + plus)
					if hp_before > 0 and c.current_hp <= 0:
						wf_kills += 1
			if wf_kills > 0:
				_net_damage_hero(not caster_is_enemy, wf_kills)
		"ambush":
			for c in foes:
				c.take_damage(1 + plus)
			for c in friendlies:
				# Mirrors solo: granted Swift (War Cry / Battle Drummer) counts.
				if combat._is_swift_attacker(c):
					c.temp_atk_buff += 1 + plus
					c.update_stat_display()
		"plague_bell":
			for _i in 12:
				var any_died := false
				for c in combat._all_creatures_both_sides():
					var hp_before: int = c.current_hp
					c.take_damage(1 + plus)
					if hp_before > 0 and c.current_hp <= 0:
						any_died = true
				combat._cleanup_dead()
				if not any_died:
					break
		"petard":
			if target != null:
				var pd_pos: Dictionary = combat._find_creature_position(target)
				var pd_main: int = 5 + plus
				var pd_splash: int = 2 + plus
				target.take_damage(pd_main)
				if not pd_pos.is_empty():
					var pd_row = combat._row_array(bool(pd_pos.is_enemy), int(pd_pos.row))
					for pd_lane in [int(pd_pos.lane) - 1, int(pd_pos.lane) + 1]:
						if pd_lane >= 0 and pd_lane < combat.LANES_PER_ROW:
							var pd_adj = pd_row[pd_lane]
							if pd_adj != null and is_instance_valid(pd_adj) and pd_adj.current_hp > 0:
								pd_adj.take_damage(pd_splash)
		"sappers_charge":
			# Mirrors solo (2026-07-10 all-physics rework): 1 scorch on the
			# body, the throws carry the payload — crashes at 4 ("+" 6).
			# _flank_push works on the node's own position, so the whole arm is
			# side-agnostic — no perspective flip needed.
			if target != null:
				var keg_pos: Dictionary = combat._find_creature_position(target)
				var keg_crash: int = 4 + plus
				target.take_damage(1)
				if not keg_pos.is_empty():
					var keg_row = combat._row_array(bool(keg_pos.is_enemy), int(keg_pos.row))
					for keg_dir in [-1, 1]:
						var keg_lane: int = int(keg_pos.lane) + keg_dir
						if keg_lane < 0 or keg_lane >= combat.LANES_PER_ROW:
							continue
						var keg_adj = keg_row[keg_lane]
						if keg_adj != null and is_instance_valid(keg_adj) and keg_adj.current_hp > 0:
							combat._flank_push(keg_adj, keg_crash, keg_dir)
				combat._cleanup_dead()
				combat._refresh_adjacency_buffs()
		"ballista_bolt":
			# Mirrors solo punch-through; only the face hit needs the caster's
			# perspective (the caster's ENEMY face takes the final spill).
			if target != null:
				var bb_pos: Dictionary = combat._find_creature_position(target)
				var bb_force: int = 5 + plus
				var bb_absorb: int = target.current_hp \
					+ (1 if target.has_keyword("armored") else 0)
				target.take_damage(bb_force)
				var bb_spill: int = bb_force - bb_absorb
				var bb_stopped: bool = is_instance_valid(target) and target.current_hp > 0
				if bb_spill > 0 and not bb_stopped and not bb_pos.is_empty():
					var bb_behind: Control = null
					if int(bb_pos.row) == combat.ROW_FRONT:
						bb_behind = combat._row_array(bool(bb_pos.is_enemy), combat.ROW_BACK)[int(bb_pos.lane)]
					if bb_behind != null and is_instance_valid(bb_behind) \
							and bb_behind.current_hp > 0 and not bb_behind.has_keyword("structure"):
						var bb_absorb2: int = bb_behind.current_hp \
							+ (1 if bb_behind.has_keyword("armored") else 0)
						bb_behind.take_damage(bb_spill)
						bb_spill -= bb_absorb2
						bb_stopped = is_instance_valid(bb_behind) and bb_behind.current_hp > 0
					if bb_spill > 0 and not bb_stopped:
						_net_damage_hero(not caster_is_enemy, bb_spill)
				combat._cleanup_dead()
		"scatter_line":
			# Blow the caster's FOES one lane toward their nearest flank —
			# outer lanes first so inner bodies cascade, mirroring solo.
			var sc_crash: int = 2 + plus
			for sc_row in [combat.ROW_FRONT, combat.ROW_BACK]:
				for sc_lane in [0, 1, 3, 2]:
					var sc = combat._row_array(not caster_is_enemy, sc_row)[sc_lane]
					if sc != null and is_instance_valid(sc) and sc.current_hp > 0:
						combat._flank_push(sc, sc_crash)
			combat._cleanup_dead()
			combat._refresh_adjacency_buffs()
		"dark_pact":
			if target != null:
				var dp_gain: int = 1 + plus
				target.take_damage(999)
				for c in friendlies:
					if c == target or not is_instance_valid(c) or c.current_hp <= 0:
						continue
					c.current_atk += dp_gain
					c.card_data.hp = int(c.card_data.get("hp", c.current_hp)) + dp_gain
					c.current_hp += dp_gain
					c.update_stat_display()
		"apocalypse":
			var kills := 0
			for c in combat._all_creatures_both_sides():
				c.take_damage(999)
				if c.current_hp <= 0:
					kills += 1
			_net_damage_hero(caster_is_enemy, kills)
		"blood_tithe":
			# Desc + solo: 4 to the enemy face, 2 self-harm (the self hit never
			# takes `plus` — Worn Spellbook sharpens the tithe, not the cost).
			_net_damage_hero(not caster_is_enemy, 4 + plus)
			_net_damage_hero(caster_is_enemy, 2)
		"kings_command":
			# The king calls the charge, mirroring solo: +1 ATK THIS ROUND per
			# friendly, to every friendly ("+" = cheaper call, not a bigger one).
			# temp_atk_buff folds into the board snapshot's effective stats and
			# _net_decay_side_states washes it after the owner's clash.
			var kc_g: int = friendlies.size()
			for c in friendlies:
				c.temp_atk_buff += kc_g
				c.update_stat_display()
		"earthquake":
			# Mirrors the 2026-07-09 solo reshape: the shake collapses BOTH
			# front lines (the quake never took sides on damage either).
			var quake_hit: int = 2 + plus
			for c in combat._all_creatures_both_sides():
				if c != null and is_instance_valid(c):
					c.take_damage(quake_hit)
			combat._cleanup_dead()
			for quake_lane in range(combat.LANES_PER_ROW):
				for quake_side in [true, false]:
					var quake_c = combat._row_array(quake_side, combat.ROW_FRONT)[quake_lane]
					if quake_c != null and is_instance_valid(quake_c) and quake_c.current_hp > 0:
						combat._relocate_creature(quake_c, quake_side, combat.ROW_BACK, quake_lane)
			combat._refresh_adjacency_buffs()
		"war_cry":
			# Swift-only rally ("+" adds +1 ATK while they charge) — mirrors solo.
			for c in friendlies:
				c.set_meta("war_cry_swift", true)
				if plus > 0:
					c.temp_atk_buff += plus
				c.update_stat_display()
		"turncoat":
			# A caster foe of 3 ATK or less (4 forged) walks over: banish-style
			# removal (entity exiled, no on-death) + a fresh body with the
			# deserter's live stats, name and keywords on the caster's side —
			# _net_place_token leaves entity_id -1 so the trailing board sync
			# registers + ships it. Too strong / structure / full camp → it
			# hesitates instead (stunned; honoured by _net_premark_skip_attack).
			if target != null:
				var tcn_gate: int = 4 if is_plus else 3
				var tcn_spot: Dictionary = combat._pick_empty_for_summon(caster_is_enemy, combat.ROW_FRONT)
				if target.effective_atk() <= tcn_gate \
						and not target.has_keyword("structure") and not tcn_spot.is_empty():
					var tcn_name: String = String(target.card_data.get("name", "Deserter"))
					var tcn_kws: Array = target.card_data.get("keywords", []).duplicate()
					var tcn_atk: int = target.current_atk
					var tcn_hp: int = target.current_hp
					var tcn_eid: int = int(target.entity_id)
					if tcn_eid >= 0:
						combat._net_exiled_eids.append(tcn_eid)
					for tcn_e in [false, true]:
						for tcn_r in [combat.ROW_FRONT, combat.ROW_BACK]:
							var tcn_arr = combat._row_array(tcn_e, tcn_r)
							for tcn_ln in range(combat.LANES_PER_ROW):
								if tcn_arr[tcn_ln] == target:
									tcn_arr[tcn_ln] = null
									var tcn_slots = combat._slot_array(tcn_e, tcn_r)
									if tcn_ln < tcn_slots.size():
										combat._restore_slot_label(tcn_slots[tcn_ln], tcn_ln)
					if tcn_eid >= 0:
						NetMatch.unregister_entity(tcn_eid)
					target.queue_free()
					var tcn_new = _net_place_token(caster_is_enemy, tcn_atk, tcn_hp, tcn_name, tcn_kws)
					if tcn_new != null and tcn_new.has_method("_spawn_keyword_chip"):
						tcn_new._spawn_keyword_chip("DESERTED", Color(0.42, 0.75, 0.58))
					combat._refresh_adjacency_buffs()
				else:
					target.state.stunned = true
					if target.has_method("_spawn_keyword_chip"):
						target._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
		"rout":
			# Drive the caster's foes into their back row; they forfeit their swing
			# this round. Mirrors solo; stun is honoured by
			# _net_premark_skip_attack before the clash.
			var rout_hit: int = 1 + plus
			for c in foes:
				if not is_instance_valid(c):
					continue
				if c.current_row == combat.ROW_FRONT:
					combat._relocate_creature(c, not caster_is_enemy, combat.ROW_BACK, c.current_lane)
				c.state.stunned = true
				if c.has_method("_spawn_keyword_chip"):
					c._spawn_keyword_chip("STUNNED", Color(0.85, 0.78, 0.45))
				c.take_damage(rout_hit)
			combat._refresh_adjacency_buffs()
		"flame_bolt":
			# Combo: ramps to 5 if the caster already cast a spell THIS turn.
			var fb: int = (5 if combat._net_spells_this_turn >= 1 else 3) + plus
			_net_damage_hero(not caster_is_enemy, fb)
		"holy_smite":
			# Execute scaling: hit for the target's missing HP, floored at 3 so it's
			# never a dead draw on a healthy body.
			if target != null:
				var missing: int = int(target.card_data.get("hp", target.current_hp)) - target.current_hp
				target.take_damage(maxi(3, missing) + plus)
				if target.current_hp <= 0:
					_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"ricochet":
			var rc_back_hit: int = 2 + plus
			var rc_fallback_hit: int = 1 + plus
			var rc_hit_any: bool = false
			for victim in combat._row_array(not caster_is_enemy, combat.ROW_BACK):
				if victim != null and is_instance_valid(victim) and victim.current_hp > 0:
					victim.take_damage(rc_back_hit)
					rc_hit_any = true
			if not rc_hit_any and foes.size() > 0:
				foes[randi() % foes.size()].take_damage(rc_fallback_hit)
			combat._cleanup_dead()
		"provision":
			# Muster a 2/1 body in the caster's first open lane (front, then back).
			# entity_id stays -1 so the trailing _net_sync_board registers + ships it.
			var prov_placed := false
			for prow in [combat.ROW_FRONT, combat.ROW_BACK]:
				if prov_placed:
					break
				var pfield = combat._row_array(caster_is_enemy, prow)
				for pl in range(combat.LANES_PER_ROW):
					if pfield[pl] == null:
						combat.summon_token(2, 1, pl, caster_is_enemy, prow)
						prov_placed = true
						break
		"baggage_train":
			# Next-turn Command is caster-local: the Mourner channel ships it
			# (EV_MANA next=true) so the owner's own _start_round folds it in.
			combat._battlecry_bonus_mana_next_turn(caster_is_enemy, 4 if is_plus else 3)
		"coin":
			# Going-second compensation: a one-time +1 Command (Hearthstone's Coin).
			_net_caster_gain_mana(caster_is_enemy, 1)
		"bloodletting":
			_net_damage_hero(caster_is_enemy, 1)   # self-harm cost (caster's own face)
			_net_caster_gain_mana(caster_is_enemy, 2 + int(data.get("extra_mana", 0)))
			var bl_fallen: int = combat._enemy_deaths_this_fight if caster_is_enemy else combat._friendly_deaths_this_fight
			if bl_fallen > 0:
				_net_caster_draw(caster_is_enemy, 1)
		# ── Draw / Command spells (use the EV_DRAW / EV_MANA caster channel) ──
		"quick_shot":
			var qs_slay: bool = false
			if target != null:
				target.take_damage(1 + plus)
				qs_slay = target.current_hp <= 0
			else:
				_net_damage_hero(not caster_is_enemy, 1 + plus)
			if qs_slay:
				_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"slash":
			if target != null:
				var can_blast_move: bool = target.current_row == combat.ROW_FRONT \
					and combat._row_array(not caster_is_enemy, combat.ROW_BACK)[target.current_lane] == null
				var slash_dmg: int = 2 + plus
				if not can_blast_move:
					slash_dmg += 2
				target.take_damage(slash_dmg)
				if is_instance_valid(target) and target.current_hp > 0 and can_blast_move:
					combat._relocate_creature(target, not caster_is_enemy, combat.ROW_BACK, target.current_lane)
		"patch_up":
			# Field Surgery — mirrors solo: full heal + Last Stand (the keyword
			# rides card_data, so the board snapshot ships it like Barricade's
			# Armored; a spent printed Last Stand is re-armed).
			if target != null:
				target.current_hp = int(target.card_data.get("hp", target.current_hp))
				if "last_stand" not in target.card_data.get("keywords", []):
					target.card_data.keywords.append("last_stand")
				target.last_stand_used = false
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("LAST STAND", Color(1.0, 0.85, 0.20), "last_stand")
				target.update_stat_display()
		"smite_spell":
			if target != null:
				target.take_damage(6 + plus)
				if target.current_hp <= 0:
					_net_caster_gain_mana(caster_is_enemy, 1 + int(data.get("slay_mana", 0)))
					_net_caster_draw(caster_is_enemy, 1 + int(data.get("slay_draw", 0)))
		"unholy_bargain":
			var ub_fallen: int = combat._enemy_deaths_this_fight if caster_is_enemy else combat._friendly_deaths_this_fight
			var ub_draws: int = 2 + int(data.get("extra_draw", 0)) + (1 if ub_fallen > 0 else 0)
			_net_caster_draw(caster_is_enemy, ub_draws)
			_net_damage_hero(caster_is_enemy, 2)
		# ── Sacrifice spells (kill the caster's own target = take_damage 999) ──
		"offering":
			if target != null:
				target.take_damage(999)
				_net_caster_gain_mana(caster_is_enemy, 2)
				_net_caster_draw(caster_is_enemy, plus_draw)
		"fuel_the_pyre":
			if target != null:
				var fp_atk: int = target.effective_atk()
				var fp_lane: int = target.current_lane
				target.take_damage(999)
				# Deterministic revenge (mirrors solo): hit whatever stands across
				# the victim's lane; only an empty column scatters the flame.
				var fp_opp: Control = combat.get_opposing_card(fp_lane, caster_is_enemy)
				if fp_opp != null:
					fp_opp.take_damage(fp_atk + plus)
				elif foes.size() > 0:
					foes[randi() % foes.size()].take_damage(fp_atk + plus)
				else:
					_net_damage_hero(not caster_is_enemy, fp_atk + plus)
		# ── Temp-state spells (freeze / stun / poison / charge) ──────────────
		# The shared attack resolver already HONOURS these (can_attack reads
		# is_frozen; _resolve_column_attack reads charges_this_turn; the strike
		# applies poison) — the only net-specific work is decay, which
		# _net_decay_side_states does at the end of the owning side's attack turn.
		"doubled_hour":
			# The caster's creatures attack twice this round — _net_run_clash runs
			# the second swing per side; decays in _net_decay_side_states.
			combat._doubled_hour[1 if caster_is_enemy else 0] = true
			_net_caster_draw(caster_is_enemy, 1)
		"frost_bolt":
			if target != null:
				target.state.is_frozen = true
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
				if plus > 0:
					target.take_damage(plus)
		"hoarfrost":
			# Target friendly gains Shield; the creature opposing it freezes.
			if target != null:
				target.state.has_shield = true
				target.update_stat_display()
				if target.has_method("_spawn_keyword_chip"):
					target._spawn_keyword_chip("SHIELD", Color(0.65, 0.85, 1.0))
				var hf_lane: int = target.current_lane
				var hf_foe: bool = not caster_is_enemy
				var hf_opp = combat._row_array(hf_foe, combat.ROW_FRONT)[hf_lane]
				if hf_opp == null:
					hf_opp = combat._row_array(hf_foe, combat.ROW_BACK)[hf_lane]
				if hf_opp != null:
					hf_opp.state.is_frozen = true
					if hf_opp.has_method("_spawn_keyword_chip"):
						hf_opp._spawn_keyword_chip("FROZEN", Color(0.55, 0.80, 1.0))
		"venom_tip":
			# Grant Poison to a friendly for this round (decayed via temp_poison).
			if target != null:
				if not target.card_data.keywords.has("poison"):
					target.card_data.keywords.append("poison")
				target.set_meta("temp_poison", true)
				target.update_stat_display()
				combat.spawn_keyword_callout_kw(target, "poison")
		"charge_spell":
			# Target friendly strikes every opposing lane on the caster's turn
			# (the strike pass reads charges_this_turn; decay clears it after).
			if target != null:
				target.set_meta("charges_this_turn", true)
		# ── Pile / grave / exile spells (host-authoritative; see Phase B) ─────
		"banish":
			if target != null:
				var banish_limit: int = 4 + plus
				if target.current_hp <= banish_limit:
					var beid: int = int(target.entity_id)
					if beid >= 0:
						combat._net_exiled_eids.append(beid)
					for b_e in [false, true]:
						for b_r in [combat.ROW_FRONT, combat.ROW_BACK]:
							var b_arr = combat._row_array(b_e, b_r)
							for b_ln in range(combat.LANES_PER_ROW):
								if b_arr[b_ln] == target:
									b_arr[b_ln] = null
									var b_slots = combat._slot_array(b_e, b_r)
									if b_ln < b_slots.size():
										combat._restore_slot_label(b_slots[b_ln], b_ln)
					if beid >= 0:
						NetMatch.unregister_entity(beid)
					target.queue_free()
					combat._refresh_adjacency_buffs()
				else:
					target.take_damage(banish_limit)
				if int(data.get("extra_draw", 0)) > 0:
					_net_caster_draw(caster_is_enemy, int(data.get("extra_draw", 0)))
		"reanimate":
			# Revive the CASTER's last corpse as a 1/1 (2/2 if upgraded) on the caster's
			# side, keeping its keywords. Reads the per-side grave so the client's cast
			# raises the client's dead, not the host's.
			var grave_re: Dictionary = combat._net_last_dead[1 if caster_is_enemy else 0]
			if not grave_re.is_empty():
				var gd: Dictionary = grave_re.get("data", {})
				var rev_n: int = 1 + plus
				_net_place_token(caster_is_enemy, rev_n, rev_n,
					String(gd.get("name", "Revived")), gd.get("keywords", []))
		"grave_robbery":
			# Float the caster's last REAL corpse (uid >= 0; tokens have no hand
			# identity) back to its hand via the caster channel.
			var grave_gr: Dictionary = combat._net_last_dead[1 if caster_is_enemy else 0]
			if not grave_gr.is_empty() and int(grave_gr.get("uid", -1)) >= 0:
				_net_caster_give_card(caster_is_enemy,
					String(grave_gr.get("id", "")), int(grave_gr.get("uid", -1)))
		"last_rites":
			# Morbid removal, caster-side: 6 once one of the CASTER's creatures has
			# fallen this fight (client deaths land in the enemy tally).
			if target != null:
				var lr_fallen: int = combat._enemy_deaths_this_fight if caster_is_enemy else combat._friendly_deaths_this_fight
				target.take_damage((6 if lr_fallen > 0 else 3) + plus)
		"echo_spell":
			# Re-resolve the caster's last host-resolved spell this turn, same target.
			# (Echo isn't recorded as last-spell, so it can't echo an echo.)
			if not combat._net_last_spell_data.is_empty():
				_net_resolve_spell(combat._net_last_spell_data, combat._net_last_spell_target_eid,
					1 if caster_is_enemy else 0)
		"war_chant":
			# The caster pitched _net_picks cards on its own machine; muster one Soldier
			# per pitch (2/1, or 3/2 upgraded) on the caster's side.
			var wc_atk: int = 3 if is_plus else 2
			var wc_hp: int = 2 if is_plus else 1
			for _wi in int(data.get("_net_picks", 0)):
				var wc_s = combat._pick_empty_for_summon(caster_is_enemy, combat.ROW_FRONT)
				if wc_s.is_empty():
					break
				combat.summon_token(wc_atk, wc_hp, wc_s.lane, caster_is_enemy, wc_s.row)
		"mass_grave":
			# Damage every caster foe by the caster's discard size (sent as _net_picks).
			var mg_dmg: int = maxi(1, int(data.get("_net_picks", 0))) + plus
			for c in foes:
				c.take_damage(mg_dmg)




## Place a keyword-carrying token on a side (net Reanimate). Returns the node, or
## null if the caster's board is full. entity_id stays -1 so the trailing board sync
## registers and ships it to the other peer.
func _net_place_token(is_enemy: bool, atk: int, hp: int, tname: String, keywords: Array) -> Control:
	var slot = combat._pick_empty_for_summon(is_enemy, combat.ROW_FRONT)
	if slot.is_empty():
		return null
	var card = combat.CARD_SCENE.instantiate()
	card.card_id = "token_revive_%d_%d" % [atk, hp]
	card.is_opponent = is_enemy
	card.is_on_battlefield = true
	card.is_token = true
	card.compact_mode = true
	card.card_data = {"id": card.card_id, "name": tname, "type": "creature", "cost": 0,
		"atk": atk, "hp": hp, "keywords": keywords.duplicate(), "rarity": "enemy",
		"desc": "Reanimated.", "is_token": true}
	card.current_atk = atk
	card.current_hp = hp
	card.current_lane = slot.lane
	card.current_row = slot.row
	combat._row_array(is_enemy, slot.row)[slot.lane] = card
	combat._slot_set_card(combat._slot_array(is_enemy, slot.row)[slot.lane], card)
	card.destroyed.connect(combat._on_card_destroyed.bind(card))
	card.will_die.connect(combat._on_card_will_die.bind(card))
	if keywords.has("shield"):
		card.state.has_shield = true
	combat._refresh_adjacency_buffs()
	return card




## Damage a hero by host-side: is_enemy_side true → the host's enemy (client),
## false → the host's own hero. Lets a spell hit "the caster's enemy face."
func _net_damage_hero(is_enemy_side: bool, value: int) -> void:
	if is_enemy_side:
		combat.damage_enemy_hero(value)
	else:
		combat.damage_player_hero(value)




## Heal a hero by host-side, capped at the skirmish starting HP. is_enemy_side
## true → the host's enemy (client) hero; false → the host's own hero.
func _net_heal_hero(is_enemy_side: bool, value: int) -> void:
	var cap: int = SkirmishState.START_HP
	if is_enemy_side:
		var nb_e: int = combat.enemy_hp
		combat.enemy_hp = mini(combat.enemy_hp + value, cap)
		if combat.enemy_hp > nb_e:
			combat._stoke_acolytes(true)
	else:
		var nb_p: int = combat.player_hp
		combat.player_hp = mini(combat.player_hp + value, cap)
		if combat.player_hp > nb_p:
			combat._stoke_acolytes(false)




# ── Owner-relative hero routing for per-side passives (Wave: passive parity) ──
# Player passives only ran for the host's side (the combat engine reads
# `_all_player_creatures()` / `if not is_enemy`). These route a passive's hero effect
# to the creature's OWN side so a Player-2 Vampire Lord heals Player 2, etc. In solo
# they're only ever called with owner_is_enemy=false, so solo behaviour is unchanged.

## Sides whose creatures run player-passive logic. Solo: the player only (enemies use
## EncounterEffects). Net: BOTH warbands — the host is authoritative for each side.
func _passive_sides() -> Array:
	return [false, true] if combat._is_net() else [false]



## Heal the hero that OWNS owner_is_enemy's side.
func _heal_owner_hero(owner_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if combat._is_net():
		_net_heal_hero(owner_is_enemy, n)
	elif combat.player_hp < combat.player_max_hp:
		var healed: int = mini(n, combat.player_max_hp - combat.player_hp)
		combat.player_hp += healed
		combat._show_lifelink_heal(healed)   # green +N at the HP medallion — any hero heal, not just Lifesteal
		combat._stoke_acolytes(false)
		combat._update_hud()



## Damage the hero OPPOSING owner_is_enemy's side (a drain / reach payoff).
func _hurt_opposing_hero(owner_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if combat._is_net():
		_net_damage_hero(not owner_is_enemy, n)
	else:
		combat.damage_enemy_hero(n)




## Make the CASTER draw n cards from THEIR OWN pile. The host can only draw into
## its own hand, so when the client is the caster (caster_is_enemy) it sends an
## EV_DRAW event and the client draws locally; when the host casts, it draws here.
func _net_caster_draw(caster_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if caster_is_enemy:
		NetMatch.send_to_client({"t": NetMatch.EV_DRAW, "n": n})
	else:
		for _i in n:
			combat.draw_one()
		combat._layout_hand()
		_net_broadcast_hand_count()
		combat._update_hud()




## Return a SPECIFIC card to the caster's hand (Grave Robbery / Grave Pact). Same
## host→caster split as the draw channel: the client gets it via EV_GIVE_CARD; the
## host adds it locally. The card goes to the front of the caster's draw pile and is
## drawn, so it respects the hand-size cap exactly like solo's return-to-hand.
func _net_caster_give_card(caster_is_enemy: bool, id: String, uid: int) -> void:
	if id == "":
		return
	if caster_is_enemy:
		NetMatch.send_to_client({"t": NetMatch.EV_GIVE_CARD, "id": id, "uid": uid})
	else:
		_net_give_card_local(id, uid)




## Caster-side: push {id,uid} onto the front of our own draw pile and draw it, so a
## returned creature lands in hand carrying its real deck identity (upgrades, uid).
func _net_give_card_local(id: String, uid: int) -> void:
	if id == "":
		return
	# The corpse's entry may ALREADY be filed in a local pile (death → discard,
	# maybe reshuffled to draw) — pull that exact entry out before re-adding,
	# or the return leaves a duplicate uid and the deck grows for the fight.
	# If it is NOT filed yet (on-death returns run before the death filing —
	# host's own Griffin — or the client's EV_GIVE_CARD lands before the death
	# snapshot), flag the uid so the upcoming filing skips it instead.
	var entry = combat._pile_entry(id, uid)
	var was_filed: bool = combat._player_discard_pile.has(entry) or combat._player_draw_pile.has(entry)
	combat._player_discard_pile.erase(entry)
	combat._player_draw_pile.erase(entry)
	if uid >= 0:
		for hc in combat._hand:
			if is_instance_valid(hc) and hc.deck_uid == uid:
				return   # already cycled back on its own — don't duplicate it
		if not was_filed:
			combat._pending_return_uids[uid] = true
	combat._player_draw_pile.push_front(entry)
	combat.draw_one()
	combat._layout_hand()
	_net_broadcast_hand_count()
	combat._update_hud()




## Grant the CASTER n Command. Same split as the draw channel — the client gains it
## on its own side via EV_MANA; the host gains it locally.
func _net_caster_gain_mana(caster_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if caster_is_enemy:
		NetMatch.send_to_client({"t": NetMatch.EV_MANA, "n": n})
	else:
		combat.player_mana += n
		combat._update_hud()
		_net_broadcast_hand_count()   # push the bumped Command to the foe's seal




# ─────────────────────────────────────────────────────────────────────────
#  CLIENT-OWNED CREATURE EFFECTS — perspective-correct ports of the on-enter /
#  on-death effects that solo only ever ran for the player side. The host
#  resolves a CLIENT creature with is_enemy=true; these route the result to the
#  right owner so Player 2's Doppelganger / Chaos Imp / Griffin / Copycat /
#  Adaptable behave identically to Player 1's.
# ─────────────────────────────────────────────────────────────────────────

## Doppelganger: the CASTER's most-recent corpse (per-side grave), as card_data.
## side_is_enemy = the caster sits on the host's enemy side (the client).
func _net_last_dead_copy_data(side_is_enemy: bool) -> Dictionary:
	var side: int = 1 if side_is_enemy else 0
	var entry: Dictionary = combat._net_last_dead[side]
	return entry.get("data", {}) if not entry.is_empty() else {}




## Griffin: float the just-dead creature back to its OWNER's hand, once per fight.
## Reads the per-side grave (recorded in _on_card_destroyed BEFORE on_death fires),
## guards against a re-return of the same uid, and routes via the caster channel.
func _net_return_dead_to_caster(was_enemy: bool) -> void:
	if not combat._is_host():
		return
	var side: int = 1 if was_enemy else 0
	var entry: Dictionary = combat._net_last_dead[side]
	if entry.is_empty():
		return
	var uid: int = int(entry.get("uid", -1))
	if uid < 0:
		return   # tokens have no deck identity to return
	if combat._net_return_once_used[side].has(uid):
		return   # already came back once this fight
	combat._net_return_once_used[side][uid] = true
	_net_caster_give_card(was_enemy, String(entry.get("id", "")), uid)




## Chaos Imp: cast a random NET-PLAYABLE spell for free with the caster's perspective.
## caster_is_enemy = the imp is the client's. Picks a self-resolving spell (no picker /
## pile / self-harm / sacrifice), auto-targets the caster's side, and resolves through
## the authoritative net resolver; the result rides the trailing board-sync.
func _net_cast_random_spell_free(caster_is_enemy: bool) -> void:
	if not combat._is_host():
		return
	# Exclude spells that need the caster's hand/pile, harm the caster, or recurse —
	# mirrors solo cast_random_spell_free's CHAOS_DENY, intersected with net-playable.
	var deny := {
		"offering": true, "fuel_the_pyre": true, "bloodletting": true,
		"unholy_bargain": true, "dark_pact": true, "blood_tithe": true,
		"apocalypse": true, "echo_spell": true,
		# (grave_pact used to sit here when it armed a pile-return; its Last Rites
		# redesign is a clean damage bolt, so the imp may sling it.)
	}
	var candidates: Array = []
	for id in CardDB.CARD_POOL:
		var d: Dictionary = CardDB.CARD_POOL[id]
		if String(d.get("type", "")) != "spell" or CardDB.is_curse(id):
			continue
		if not SkirmishState.is_net_playable_spell(d):
			continue
		var sid: String = String(d.get("spell", {}).get("id", ""))
		if sid in combat._NET_CASTER_LOCAL_SPELLS or deny.has(id) or deny.has(sid):
			continue
		if int(d.get("cost", 0)) > 1:   # cap the roll at cheap spells (no 4-cost blowout)
			continue
		if not bool(_net_random_spell_context_for(d, caster_is_enemy).get("ok", false)):
			continue
		candidates.append(id)
	if candidates.is_empty():
		return
	var data: Dictionary = CardDB.get_card_data(candidates[randi() % candidates.size()])
	var cast_ctx: Dictionary = _net_random_spell_context_for(data, caster_is_enemy)
	if not bool(cast_ctx.get("ok", false)):
		return
	var target_eid: int = int(cast_ctx.get("eid", -1))
	combat._show_info("Chaos Imp casts %s!" % data.get("name", "a spell"))
	_net_resolve_spell(data, target_eid, 1 if caster_is_enemy else 0)




## Pick a random valid target ENTITY id for an auto-cast net spell, from the caster's
## perspective: enemy/any → a random foe creature; friendly → a random own creature.
## Structures are never valid targets. Returns -1 when no legal target exists.
func _net_random_spell_context_for(data: Dictionary, caster_is_enemy: bool) -> Dictionary:
	var targeting := String(data.get("targeting", "none"))
	if targeting == "none":
		return {
			"ok": _net_untargeted_random_spell_can_resolve(data, caster_is_enemy),
			"eid": -1,
		}
	var target_eid: int = _net_auto_target_for(targeting, caster_is_enemy)
	if target_eid >= 0:
		return {"ok": true, "eid": target_eid}
	if targeting == "any":
		return {"ok": true, "eid": -1}
	return {"ok": false, "eid": -1}




func _net_untargeted_random_spell_can_resolve(data: Dictionary, caster_is_enemy: bool) -> bool:
	var spell: Dictionary = data.get("spell", {})
	var stype := String(spell.get("type", ""))
	var sid := String(spell.get("id", ""))
	var friendlies: Array = combat._all_friendly(caster_is_enemy)
	var foes: Array = combat._all_friendly(not caster_is_enemy)
	match stype:
		"damage_face", "draw":
			return true
		"damage_all_enemies":
			return not foes.is_empty()
		"damage_all":
			return not combat._all_creatures_both_sides().is_empty()
		"buff_all_atk":
			return not friendlies.is_empty()
	if stype != "custom":
		return true
	match sid:
		"provision", "muster_fallen":
			return combat._has_open_creature_slot(caster_is_enemy)
		"reanimate":
			return not combat._net_last_dead[1 if caster_is_enemy else 0].is_empty() \
				and combat._has_open_creature_slot(caster_is_enemy)
		"grave_robbery":
			var grave: Dictionary = combat._net_last_dead[1 if caster_is_enemy else 0]
			return not grave.is_empty() and int(grave.get("uid", -1)) >= 0
		"mass_grave", "ricochet", "wildfire":
			return not foes.is_empty()
		"ambush":
			return not foes.is_empty() or combat._has_swift_friendly(caster_is_enemy)
		"plague_bell", "earthquake":
			return not combat._all_creatures_both_sides().is_empty()
		"war_cry", "virulence", "kings_command":
			return not friendlies.is_empty()
		"censer_light":
			# The smoke needs a zealot to settle on — grey without one.
			for cl_g in friendlies:
				if is_instance_valid(cl_g) and String(cl_g.card_data.get("ctype", "")) == "zealot":
					return true
			return false
		"testudo":
			# Base writ reaches only the front row; the forged one takes any body.
			if bool(data.get("is_upgraded", false)):
				return not friendlies.is_empty()
			for tst_g in combat._row_array(caster_is_enemy, combat.ROW_FRONT):
				if tst_g != null and is_instance_valid(tst_g):
					return true
			return false
		"doubled_hour":
			return true
	return true




func _net_auto_target_for(targeting: String, caster_is_enemy: bool) -> int:
	var pool: Array = []
	if targeting == "enemy_creature":
		pool = combat._all_friendly(not caster_is_enemy)
	elif targeting == "friendly_creature":
		pool = combat._all_friendly(caster_is_enemy)
	elif targeting in ["any_creature", "any"]:
		pool = combat._all_friendly(not caster_is_enemy) + combat._all_friendly(caster_is_enemy)
	var valid: Array = []
	for c in pool:
		if is_instance_valid(c) and not c.has_keyword("structure"):
			valid.append(c)
	if valid.is_empty():
		return -1
	return int(valid[randi() % valid.size()].entity_id)




# ── Networked choice (Copycat / Adaptable): the OWNER always makes the pick ──

## HOST: a CLIENT creature's on-enter needs a player choice. Ask the client to pick (it
## has the creature on its own board via the board sync); the answer returns as an
## IN_CHOICE intent and _net_apply_client_choice applies it host-authoritatively.
func _net_request_client_choice(card, kind: String) -> void:
	if not combat._is_host() or card == null or not is_instance_valid(card):
		return
	NetMatch.send_to_client({"t": NetMatch.EV_CHOICE, "eid": int(card.entity_id), "kind": kind})




## HOST: apply the client's pick for an EV_CHOICE prompt, then board-sync so both sides
## see the result. Validates the entity is still the client's own creature.
func _net_apply_client_choice(intent: Dictionary) -> void:
	if not combat._is_host() or combat._net_active_index != 1:
		return
	var eid: int = int(intent.get("eid", -1))
	var node = NetMatch.get_entity(eid)
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		return
	match String(intent.get("kind", "")):
		"keyword":
			var kw: String = String(intent.get("pick", ""))
			if kw in ["swift", "piercing", "armored", "thorns"]:
				if kw not in node.card_data.keywords:
					node.card_data.keywords.append(kw)
				node.update_stat_display()
				_net_sync_board()
		"copy_friendly":
			var src_eid: int = int(intent.get("pick", -1))
			if src_eid == eid:
				return   # can't copy itself
			var src = NetMatch.get_entity(src_eid)
			if src != null and is_instance_valid(src) and src.is_opponent:
				KeywordEffects._copy_creature_onto(node, src.card_data)
				node.update_stat_display()
				_net_sync_board()




## CLIENT: an EV_CHOICE arrived for one of our creatures — show the picker and send the
## answer back as IN_CHOICE. We never apply locally; the host applies + syncs the result.
func _net_client_show_choice(eid: int, kind: String) -> void:
	if not combat._is_client():
		return
	var node = NetMatch.get_entity(eid)
	match kind:
		"keyword":
			var kw: String = await combat._keyword_choice_overlay()
			if kw != "":
				NetMatch.send_intent({"t": NetMatch.IN_CHOICE, "eid": eid, "kind": "keyword", "pick": kw})
		"copy_friendly":
			var src = await combat._pick_friendly_creature(node, "Changeling — click a friendly to copy")
			if src != null and is_instance_valid(src):
				NetMatch.send_intent({"t": NetMatch.IN_CHOICE, "eid": eid,
					"kind": "copy_friendly", "pick": int(src.entity_id)})
