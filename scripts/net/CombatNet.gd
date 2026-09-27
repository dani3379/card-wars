## CombatNet.gd — Combat's online-skirmish layer, extracted verbatim from
## Combat.gd (backend restructure 2026-07-14). Bodies are unchanged except
## that Combat members are reached through `combat` (the ctx — KeywordEffects
## precedent). Shared net STATE still lives on Combat (probes and saves read it
## there); only the sealed per-caster spell-step ledger is private here. Combat
## keeps thin same-name delegators for every function here, so
## probes, KeywordEffects ctx calls, and core call sites are unchanged.
## Instantiated as a plain child Node of Combat (see Combat._init), so signal
## connections and the Card2D.net_last_stand_cb hook die with the scene.
extends Node

const NetPlayerStateScript = preload("res://scripts/net/NetPlayerState.gd")
## The Old King's coinage — the same prop the gambling events spin. Reused here
## so the match's toss is physically the same coin the world already uses.
const COIN_PROP = preload("res://scripts/ui/painters/CoinProp.gd")

var combat  # the Combat scene (untyped: Combat.gd has no class_name)
var _remote_state = null # NetPlayerState, allocated only by the real-network host

# Sealed Orders gives each side a separate spell step inside the same round.
# Keep its combo/Echo ledger side-indexed here, while mirroring whichever side is
# active into Combat's legacy scalar fields for existing UI/probe call sites.
var _sealed_spell_counts: Array[int] = [0, 0]
var _sealed_last_spell_data: Array[Dictionary] = [{}, {}]
var _sealed_last_spell_targets: Array[int] = [-1, -1]
var _sealed_remote_ghosts: Dictionary = {} # "row:lane" -> true, host validation
var _pending_remote_choices: Dictionary = {} # entity id -> choice kind


func _net_init_remote_authority() -> bool:
	if not combat._is_host() or SkirmishState.vs_bot:
		return false
	var slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(1)
	if slot == null:
		return false
	_remote_state = NetPlayerStateScript.new()
	var authority_seed := int(SkirmishState.rng_seed) ^ 0x51A7E \
		^ (int(SkirmishState.series_game) * 0x9E3779B1)
	if not _remote_state.setup(slot.deck, slot.deck_uids, slot.relics,
			slot.potions, authority_seed, slot.base_max_mana,
			Callable(SkirmishState, "skirmish_card_data")):
		_remote_state = null
		return false
	return true


## COERCE A PEER-SUPPLIED FIELD WITHOUT TRUSTING ITS TYPE.
##
## `int(x)` THROWS on a Dictionary, an Array or an Object — "Invalid call.
## Nonexistent 'int' constructor" — and a thrown call ABORTS the function where it
## stands. Every intent handler read its peer's fields with a bare `int(...)`, so a
## modified or simply buggy client could stop a host-side handler half-finished by
## sending `{"t": "play_creature", "lane": {}}`: found by fuzzing the wire
## (tools/_probe_fuzz_wire.gd), which is the only pass that ever fed this game input
## it did not write itself. `NetProtocol` cannot prevent it — the envelope contract
## is about SHAPE, and `{"lane": {}}` is a perfectly well-shaped payload — so the
## coercion itself has to be total.
##
## Returns `fallback` for anything that is not sensibly a number, which puts the
## value straight into the range checks the handlers already perform.
static func _wire_int(v, fallback: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			var f := float(v)
			return int(f) if is_finite(f) else fallback
		TYPE_BOOL:
			return 1 if bool(v) else 0
		TYPE_STRING, TYPE_STRING_NAME:
			return int(String(v)) if String(v).is_valid_int() else fallback
	return fallback


## The same guarantee for text. `String(x)` does not throw, but it happily renders a
## whole nested Dictionary into an id field, which then travels into lookups and log
## lines. Anything that is not already text is refused.
static func _wire_str(v, fallback: String = "") -> String:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
	return fallback


func _net_remote_empty_edge_columns() -> int:
	var count := 0
	for lane in [0, combat.LANES_PER_ROW - 1]:
		if combat._enemy_field[lane] == null and combat._enemy_back[lane] == null:
			count += 1
	return count


func _net_remote_has_first_spell_discount() -> bool:
	for card in combat._all_friendly(true):
		if is_instance_valid(card) \
				and String(card.card_data.get("passive", "")) == "first_spell_discount":
			return true
	return false


func _net_send_private_state(reason: String = "") -> void:
	if _remote_state == null or not combat._is_host() or SkirmishState.vs_bot:
		return
	var event: Dictionary = _remote_state.state_payload()
	event["t"] = NetMatch.EV_HAND_SET
	if reason != "":
		event["reason"] = reason
	NetMatch.send_to_client(event)
	combat._net_opp_hand_count = _remote_state.hand.size()
	_net_refresh_opp_hand()
	_net_set_opp_mana(_remote_state.mana, _remote_state.max_mana)


func _net_reject_remote(reason: String) -> void:
	_net_send_private_state(reason)


func _net_remote_field_card_left(card: Control, was_enemy: bool,
		exiled: bool = false) -> void:
	if not was_enemy or _remote_state == null or card == null \
			or not is_instance_valid(card):
		return
	_pending_remote_choices.erase(int(card.entity_id))
	if int(card.deck_uid) < 0:
		return
	_remote_state.field_card_left(int(card.deck_uid), String(card.card_id), exiled)
	_net_send_private_state()


func _net_payload_entries(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for raw_entry in entries:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var id := String(entry.get("id", ""))
		var uid := int(entry.get("uid", -1))
		if not SkirmishState.skirmish_card_data(id).is_empty() or id == "coin":
			out.append(combat._pile_entry(id, uid))
	return out


func _net_apply_private_state(event: Dictionary) -> void:
	if not combat._is_client():
		return
	var rejection_reason := _wire_str(event.get("reason", ""))
	if rejection_reason != "" and _is_sealed() and combat._sorcery_active < 0:
		_sealed_clear_pending_local()
	for key in ["hand", "draw", "discard", "exhaust", "potions"]:
		if typeof(event.get(key, null)) != TYPE_ARRAY:
			return
	var wanted: Dictionary = {}
	for raw_entry in event.get("hand", []):
		if not (raw_entry is Dictionary):
			return
		var entry: Dictionary = raw_entry
		var id := String(entry.get("id", ""))
		var uid := int(entry.get("uid", -2))
		if (SkirmishState.skirmish_card_data(id).is_empty() and id != "coin") \
				or wanted.has(uid):
			return
		wanted[uid] = entry

	for card in combat._hand.duplicate():
		if card == null or not is_instance_valid(card):
			combat._hand.erase(card)
			continue
		if not wanted.has(int(card.deck_uid)) \
				or String(wanted[int(card.deck_uid)].get("id", "")) != String(card.card_id):
			combat._hand.erase(card)
			if card.get_parent() != null:
				card.get_parent().remove_child(card)
			card.queue_free()

	var existing: Dictionary = {}
	for card in combat._hand:
		if card != null and is_instance_valid(card):
			existing[int(card.deck_uid)] = card
	for raw_entry in event.get("hand", []):
		var entry: Dictionary = raw_entry
		var uid := int(entry.get("uid", -1))
		var board_copy = NetMatch.get_entity(uid)
		if board_copy != null and is_instance_valid(board_copy) \
				and not bool(board_copy.is_opponent):
			combat._pending_return_uids[uid] = true
		var card: Control = existing.get(uid, null)
		if card == null or not is_instance_valid(card):
			combat._draw_card(combat._pile_entry(String(entry.get("id", "")), uid))
			card = combat._hand.back() if not combat._hand.is_empty() else null
		if card != null and is_instance_valid(card):
			card.card_data["cost"] = maxi(0, int(entry.get("cost", card.card_data.get("cost", 0))))
			card.state.pact_of_embers_zero = bool(entry.get("pact_zero", false))
			if card.has_method("update_stat_display"):
				card.update_stat_display()

	combat._player_draw_pile = _net_payload_entries(event.get("draw", []))
	combat._player_discard_pile = _net_payload_entries(event.get("discard", []))
	combat._exhaust_pile = _net_payload_entries(event.get("exhaust", []))
	combat.player_mana = maxi(0, _wire_int(event.get("mana", 0), 0))
	combat.player_max_mana = maxi(0, _wire_int(event.get("max_mana", 0), 0))
	var slot := SkirmishState.local_slot()
	if slot != null:
		slot.potions = event.get("potions", []).duplicate()
	combat._layout_hand()
	combat._refresh_hand_affordability()
	combat._rebuild_potion_bar()
	combat._update_hud()
	if rejection_reason != "":
		combat._show_info("Action rejected: " + rejection_reason.replace("_", " "))
		if _is_sealed() and combat._sorcery_active < 0:
			combat._sealed_await_foe = false
			Card2D.hand_interactive = true
			if combat._end_turn_btn != null:
				combat._end_turn_btn.disabled = false
				combat._set_primary_action("seal")


# ═════════════════════════════════════════════════════════════════════════
#  ONLINE SKIRMISH — combat networking (docs/MULTIPLAYER_SKIRMISH_PLAN.md §12-13)
#
#  Architecture: HOST-AUTHORITATIVE with public board snapshots + private state.
#   • The host owns both decks, hands, piles, Command pools, consumables, RNG
#     consequences, public board state, and all combat resolution.
#   • The client receives its own private zone membership (draw order redacted)
#     and a count for the foe, sends bounded intents, and renders the host's
#     board snapshots / paced strike log. It never resolves game state.
#   • Alternating style lets both sides place in sequence, then resolves the
#     simultaneous clash. Sealed style commits both creature bundles privately,
#     reveals them together, then opens the two sequential sorcery steps.
#   • entity_id == the card's deck uid for drafted creatures (both machines agree
#     without negotiation); tokens get host-issued ids above any uid.
#
#  DEFERRED: combat-time floop toggles, unsupported Discover/economy spells,
#  reconnect/resume, and neutral-server competitive authority.
# ═════════════════════════════════════════════════════════════════════════



func _net_issue_token_id() -> int:
	var id = combat._net_token_id_next
	combat._net_token_id_next += 1
	return id




# ── Match lifecycle ──────────────────────────────────────────────────────

func _net_begin_combat() -> void:
	if combat._net_signals_wired:
		return
	_pending_remote_choices.clear()
	combat._net_signals_wired = true
	NetMatch.combat_event_received.connect(_on_net_event)
	if combat._is_host():
		NetMatch.combat_intent_received.connect(_on_net_intent)
		if not SkirmishState.vs_bot and not _net_init_remote_authority():
			combat._show_info("The opponent's submitted deck could not be verified.")
			return
		# Last Stand mirror: the flare fires inside Card2D.take_damage, which only
		# ever runs on the host — install the hook so the save ships to the client
		# via the eid-anchored fx channel (rides the next board sync).
		Card2D.net_last_stand_cb = _net_on_last_stand_saved
	# Mid-match disconnect: bail to the menu rather than hang (plan §15).
	NetMatch.peer_left.connect(func(_id): _net_on_peer_lost())
	NetMatch.host_closed.connect(_net_on_peer_lost)
	# The foe's hand fan: build the FACE-DOWN strip of card backs up top now so it's
	# ready when the first EV_HAND_COUNT lands. That event carries {n, mana, maxmana}
	# — a count and their Command, never the identities. (This comment used to claim
	# open-hand face-up spectating; that was never true and was drift, corrected
	# 2026-07-27. Hands stay hidden — see feedback_enemy_is_real_opponent.)
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
	# ── THE TOSS (2026-07-11; extended to EVERY format 2026-07-21): the seed coin
	# flip decides who CHOOSES, not who takes it. Both formats have something for
	# the winner to pick, so both show the toss:
	#   ALTERNATING — who takes the first turn (loser keeps the Coin).
	#   SEALED      — who holds the initiative in round 1 (reveal + sorcery
	#                 order). Nothing to compensate there, because initiative
	#                 cuts both ways: you resolve first, but you also cast first.
	# Sealed needs no extra plumbing — its `_net_initiative = _net_first_player()`
	# reads the same override this block writes. The winner picks GO FIRST (takes the first turn and
	# every turn after) or GO SECOND (sees the foe's line before committing, and
	# keeps the Coin — the second player's opening turn is de facto turn 2, so it
	# fights like one). The pick lands in
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
			await _net_show_order_wait()
	# ── SEALED ORDERS style: no opener, no Coin — both sides give orders blind,
	# so there is nothing to COMPENSATE. There is still something to DECIDE:
	# initiative (reveal order + the sorcery opener), which alternates per round
	# after the first. The toss above already settled it — _net_first_player()
	# reads the override, so this line inherits the winner's pick for free. ──
	if _is_sealed():
		combat._net_initiative = combat._net_first_player()
		combat._show_info("Sealed Orders — both lines are set in secret.")
		if combat._is_host():
			if SkirmishState.vs_bot:
				_bot_refill_hand()
				_bot_sync_hand_display()
				_net_prebake_bot_textures()
			await combat.get_tree().create_timer(0.6).timeout
			_sealed_begin_round(1)
		return
	# The opening experience keys off going first / second, not host / client —
	# both roles are identical and swap with the settled order.
	var first_index: int = combat._net_first_player()
	if combat._is_host() and not SkirmishState.vs_bot and _remote_state != null:
		# Slot 1's private opening hand comes from the host authority.
		if first_index == 0:
			var remote_predeal: int = combat.HAND_REFILL_TARGET
			# Read the relic's own value, exactly as the local pre-deal below does
			# (line ~329). This was a hardcoded +1: identical today, but the two
			# paths would diverge silently the moment Deep Satchel is retuned, and
			# the divergence would land on the CLIENT's opening hand only — the
			# hardest place to notice it.
			if _remote_state.relics.has("deep_satchel"):
				remote_predeal += int(RelicDB.get_relic("deep_satchel").get("value", 1))
			_remote_state.predeal(remote_predeal, true)
		_net_send_private_state()
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
		if not combat._is_client():
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
		combat._show_info("Your opponent goes first. You go second — you keep The Coin, and your first turn attacks.")
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




## The toss modal: the coin-flip winner picks who goes first. Awaitable; returns
## true = go first, false = go second. Mouse-only like the rest of the game; lives
## on its own CanvasLayer so it sits above board and hand.
##
## Copy rule: this is a RULES screen, so it says what it means. It used to read
## "MARCH FIRST" / "HOLD BACK" / "Choose the ground", which made the player decode
## a metaphor to answer a question about turn order. Flavour belongs in the
## fiction, not on the buttons.
func _net_show_order_choice() -> bool:
	var layer := CanvasLayer.new()
	layer.layer = 30
	combat.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	if UserSettings != null and UserSettings.reduce_motion:
		dim.color = Color(0, 0, 0, 0.80)
	else:
		var dim_tw := dim.create_tween()
		dim_tw.tween_property(dim, "color", Color(0, 0, 0, 0.80), 0.35)

	# ── The toss itself: the Old King's coin, spun on its edge. ───────────────
	var coin = COIN_PROP.new()
	coin.seed_text = "toss_%d" % SkirmishState.rng_seed
	coin.custom_minimum_size = Vector2(150, 150)
	coin.size = Vector2(150, 150)
	coin.set_anchors_preset(Control.PRESET_CENTER)
	coin.position = Vector2(-75, -280)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(coin)
	await _net_play_coin_toss(coin)
	# THE TOSS IS A MULTI-SECOND SUSPENSION AND `layer` IS A CHILD OF THE COMBAT
	# SCENE. If the peer drops while the coin is in the air, `_net_on_peer_lost`
	# arms a scene change two seconds out, the scene and this layer are freed, and
	# every line below is operating on a freed object — which in GDScript aborts
	# the function silently rather than raising. Nothing after this point would
	# run, so the toss winner would be left staring at a coin with no choice
	# buttons under it and no error anywhere.
	#
	# The abort ANSWER follows the convention already established for the wait loop
	# below: the caller only feeds it to `_net_first_player_override` for a match
	# that is ending, so hand back whatever makes that override a no-op.
	if not is_instance_valid(layer) or not is_instance_valid(combat):
		if not is_instance_valid(combat):
			return true
		return combat._net_first_player() == combat._net_my_index()

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -330
	col.offset_right = 330
	col.offset_top = -150
	col.offset_bottom = 300
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 12)
	layer.add_child(col)
	var title = GameTheme.make_label("YOU WON THE TOSS", 34, GameTheme.GILT_BRIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	# The two formats decide DIFFERENT things, so the modal asks the actual
	# question rather than a generic one. In Alternating, going first is plainly
	# better and the loser is paid in the Coin. In Sealed nothing needs paying,
	# because initiative genuinely cuts both ways — you resolve first, but you
	# also commit your spell first.
	var sealed_toss: bool = _is_sealed()
	var sub = GameTheme.make_label(
		"Do you want to resolve first or second?" if sealed_toss
			else "Do you want to go first or second?",
		18, GameTheme.DESC_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var picked: Array = [-1]
	var choices: Array = [
		["RESOLVE FIRST", "Your creatures arrive first. Your spells also resolve first, before you see the opponent's spells.", 1],
		["RESOLVE SECOND", "They reveal and cast first. You answer the spell step already knowing what they played.", 0],
	] if sealed_toss else [
		["GO FIRST", "You take the first turn, and every turn after it.", 1],
		["GO SECOND", "You see their line before you commit yours, and you start with The Coin (+1 Command, once).", 0],
	]
	for opt in choices:
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
	GameTheme.stamp_in(title, 0.10)
	# THE TWIN'S GUARD, WHICH THIS LOOP NEVER HAD. `_net_show_order_wait` — the
	# other half of the same toss — waits with BOTH a timeout and a
	# `not combat._net_match_over` term. This one waited on nothing but the click.
	#
	# So if the opponent quit while you were choosing (people close the game at
	# match start more than anywhere else), `_net_on_peer_lost` set `_net_match_over`
	# and armed a 2.5s fade to the menu; the scene changed, `combat` was freed, and
	# this coroutine went on dereferencing it once a frame — `combat.get_tree()` on
	# a previously-freed instance — with no exit, because the modal it was waiting
	# for a click on had been freed too.
	#
	# On an abort the return value is moot (the caller only feeds it to
	# `_net_first_player_override` for a match that is ending), so hand back the
	# answer that makes the override a NO-OP: whatever the raw flip already said.
	while picked[0] < 0:
		if not is_instance_valid(combat) or combat._net_match_over:
			if is_instance_valid(layer):
				layer.queue_free()
			if not is_instance_valid(combat):
				return true
			return combat._net_first_player() == combat._net_my_index()
		await combat.get_tree().process_frame
	return picked[0] == 1


## THE LOSER OF THE TOSS WATCHES THE SAME TOSS (2026-08-04).
##
## The opening ceremony used to be one-sided: the winner got the Old King's coin spun
## on its edge over a dimmed board, and the other player got a single info line and up
## to ninety seconds of a static board while somebody else decided how the match opens.
## The very first thing a skirmish does was the least mutual thing in it.
##
## So the watcher now sees the same coin — and it is genuinely THE SAME COIN, not a
## lookalike: CoinProp is seeded off `SkirmishState.rng_seed`, which both peers already
## share, so the two machines draw identical wear and the same faces come up. Then the
## verdict lands as a BEAT ("They go first." / "They go second — you hold The Coin.")
## rather than as a silent state change, which is how the player learns what the other
## chose at all.
##
## Keeps the old wait loop verbatim, timeout and all: a dropped EV_ORDER_PICK still
## falls back to the raw flip, and a match that ends under us still bails.
func _net_show_order_wait() -> void:
	var headless: bool = DisplayServer.get_name() == "headless"
	var layer: CanvasLayer = null
	var status: Label = null
	if not headless:
		layer = CanvasLayer.new()
		layer.layer = 30
		combat.add_child(layer)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.0)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		layer.add_child(dim)
		if UserSettings != null and UserSettings.reduce_motion:
			dim.color = Color(0, 0, 0, 0.80)
		else:
			var dim_tw := dim.create_tween()
			dim_tw.tween_property(dim, "color", Color(0, 0, 0, 0.80), 0.35)
		var coin = COIN_PROP.new()
		coin.seed_text = "toss_%d" % SkirmishState.rng_seed   # the same coin, both peers
		coin.custom_minimum_size = Vector2(150, 150)
		coin.size = Vector2(150, 150)
		coin.set_anchors_preset(Control.PRESET_CENTER)
		coin.position = Vector2(-75, -280)
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(coin)
		await _net_play_coin_toss(coin)
		# Same suspension hazard as the winner's screen above: a drop during the
		# toss frees this layer with the rest of the combat scene.
		if not is_instance_valid(layer) or not is_instance_valid(combat):
			return
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_CENTER)
		col.offset_left = -330
		col.offset_right = 330
		col.offset_top = -150
		col.offset_bottom = 300
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		col.add_theme_constant_override("separation", 12)
		layer.add_child(col)
		# Ember, not gilt: the winner's title is gilt, and the two screens should not
		# claim the same colour for opposite outcomes.
		var title = GameTheme.make_label("OPPONENT WON THE TOSS", 34, GameTheme.ATK_RED, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
		status = GameTheme.make_label("They are choosing the order…", 18, GameTheme.DESC_DIM)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(status)
		GameTheme.deal_in(col, 0.05)
		GameTheme.stamp_in(title, 0.10)
	else:
		combat._show_info("Your opponent won the toss — they are choosing…")

	# Wait for the pick to cross the wire; a generous timeout falls back to the raw
	# flip so a dropped message can never soft-lock the match.
	var toss_waited := 0.0
	while combat._net_first_player_override < 0 and toss_waited < 90.0 \
			and not combat._net_match_over:
		await combat.get_tree().create_timer(0.2).timeout
		toss_waited += 0.2
	if combat._net_first_player_override < 0:
		combat._net_first_player_override = combat._net_first_player()

	# The verdict as a BEAT. Said from OUR side of the table — what matters to this
	# player is whether they move first and whether they hold the Coin, not which
	# global index won.
	if status != null and is_instance_valid(status):
		var they_lead: bool = combat._net_first_player() != combat._net_my_index()
		if _is_sealed():
			status.text = "They resolve first." if they_lead \
				else "They resolve second — you reveal and cast first."
		else:
			status.text = "They go first." if they_lead \
				else "They go second — you hold The Coin."
		status.add_theme_color_override("font_color", GameTheme.GILT_BRIGHT)
		GameTheme.stamp_in(status, 0.0)
		await combat.get_tree().create_timer(1.15).timeout
	if layer != null and is_instance_valid(layer):
		layer.queue_free()


## The coin goes up, turns on its edge, and comes down. `face_t` is the honest
## way to spin a CoinProp (1.0 face-on -> 0.0 edge-on), so the thin moment
## genuinely flashes the milled edge instead of a scaled-down face. Reduce Motion
## skips straight to the settled coin with a reading pause.
func _net_play_coin_toss(coin) -> void:
	if UserSettings != null and UserSettings.reduce_motion:
		coin.face_t = 1.0
		await combat.get_tree().create_timer(0.45).timeout
		return
	var rest_y: float = coin.position.y
	coin.face_t = 1.0
	coin.modulate.a = 0.0
	var tw: Tween = coin.create_tween()
	tw.set_parallel(true)
	tw.tween_property(coin, "modulate:a", 1.0, 0.12)
	# Up and down once — a real arc, not a hover.
	tw.tween_property(coin, "position:y", rest_y - 90.0, 0.34) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(coin, "position:y", rest_y, 0.30) 		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Five half-turns over the arc, each one passing through edge-on.
	var spin: Tween = coin.create_tween()
	for i in 5:
		spin.tween_property(coin, "face_t", 0.06, 0.064) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		spin.tween_callback(func():
			if is_instance_valid(coin):
				coin.tails = not coin.tails)
		spin.tween_property(coin, "face_t", 1.0, 0.064) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await combat.get_tree().create_timer(0.64).timeout
	if AudioBank != null:
		AudioBank.play_sfx("coin_pour", 0.04, -3.0)
	if is_instance_valid(coin):
		GameTheme.add_trauma(0.10)
		var land: Tween = coin.create_tween()
		land.tween_property(coin, "scale", Vector2(1.12, 0.90), 0.07)
		land.tween_property(coin, "scale", Vector2.ONE, 0.16) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await combat.get_tree().create_timer(0.26).timeout


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



## Reset BOTH sealed spell steps at the round boundary. A single scalar reset lets
## initiative-side casts leak Flame Bolt/Leyline/Echo state into the second caster.
func _net_reset_sealed_spell_state() -> void:
	for side in 2:
		_sealed_spell_counts[side] = 0
		_sealed_last_spell_data[side] = {}
		_sealed_last_spell_targets[side] = -1
	combat._net_spells_this_turn = 0
	combat._net_last_spell_data = {}
	combat._net_last_spell_target_eid = -1


func _net_spell_count_for(caster_index: int) -> int:
	if _is_sealed() and caster_index >= 0 and caster_index < 2:
		return _sealed_spell_counts[caster_index]
	return combat._net_spells_this_turn


func _net_last_spell_for(caster_index: int) -> Dictionary:
	if _is_sealed() and caster_index >= 0 and caster_index < 2:
		return _sealed_last_spell_data[caster_index]
	return combat._net_last_spell_data


func _net_last_spell_target_for(caster_index: int) -> int:
	if _is_sealed() and caster_index >= 0 and caster_index < 2:
		return _sealed_last_spell_targets[caster_index]
	return combat._net_last_spell_target_eid


func _net_store_last_spell_for(caster_index: int, data: Dictionary, target_eid: int) -> void:
	var stored := data.duplicate(true)
	if _is_sealed() and caster_index >= 0 and caster_index < 2:
		_sealed_last_spell_data[caster_index] = stored
		_sealed_last_spell_targets[caster_index] = target_eid
	combat._net_last_spell_data = stored
	combat._net_last_spell_target_eid = target_eid


func _net_increment_spell_count_for(caster_index: int) -> void:
	if _is_sealed() and caster_index >= 0 and caster_index < 2:
		_sealed_spell_counts[caster_index] += 1
		combat._net_spells_this_turn = _sealed_spell_counts[caster_index]
	else:
		combat._net_spells_this_turn += 1


func _sealed_load_spell_state(who: int) -> void:
	if who < 0 or who >= 2:
		return
	combat._net_spells_this_turn = _sealed_spell_counts[who]
	combat._net_last_spell_data = _sealed_last_spell_data[who].duplicate(true)
	combat._net_last_spell_target_eid = _sealed_last_spell_targets[who]




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
	_sealed_remote_ghosts.clear()
	combat._sorcery_active = -1
	combat._sorcery_passes = 0
	combat._net_active_index = -1   # nobody "has the turn" — the existing turn gates
							 # (client creature/spell paths) block by construction
	if not SkirmishState.vs_bot and _remote_state != null:
		_remote_state.begin_turn(round_no, _net_remote_empty_edge_columns())
		_net_send_private_state()
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
	_net_reset_sealed_spell_state()
	if not combat._is_client():
		# NOT awaited, and must stay that way. _start_round is a coroutine solo-side
		# (it paces its visible groups apart — see Combat._round_beat), but
		# _round_beat returns synchronously whenever _is_net(), so it never suspends
		# here and this call behaves exactly as it did before. Do not add an
		# unconditional await inside _start_round without making this chain async.
		combat._start_round()
	Card2D.board_interactive = false   # no reposition drags in sealed v1
	Card2D.hand_interactive = true     # both sides give orders at once
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = false
		combat._set_primary_action("seal")
	combat._update_hud()
	var init_line: String = "You hold the initiative." \
		if combat._net_initiative == NetMatch.local_player_index else "Your opponent holds the initiative."
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
	# THE SPEND IS ITS OWN BEAT (parity, 2026-08-04). Every solo play site passes
	# MANA_SPEND_BEAT so the RESOURCE lands half a beat behind the CARD — otherwise the
	# card's exit, the play cue, the seal punch and the arrival press all share one
	# frame and four simultaneous events read as one indistinct event. All three
	# skirmish play sites were passing the 0.0 default, so a skirmish play was exactly
	# the mush that offset was introduced to fix.
	combat._pulse_mana_label(cost, false, combat.MANA_SPEND_BEAT)
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
	stand.state.sealed_pending = true
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
		if not SkirmishState.vs_bot:
			_net_reject_remote("illegal_slot")
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


func _sealed_accept_remote_ghost(lane: int, row: int) -> void:
	if not combat._is_host() or not _is_sealed() or combat._sealed_bundles.has(1):
		return
	if combat.phase != combat.Phase.PLAYER_TURN or combat._sorcery_active >= 0:
		_net_reject_remote("orders_phase_closed")
		return
	if lane < 0 or lane >= combat.LANES_PER_ROW \
			or row < combat.ROW_FRONT or row > combat.ROW_BACK:
		return
	var key := "%d:%d" % [row, lane]
	if _sealed_remote_ghosts.has(key) or _sealed_remote_ghosts.size() >= 8:
		return
	if combat._row_array(true, row)[lane] != null:
		return
	_sealed_remote_ghosts[key] = true
	_sealed_show_ghost(lane, row)




## The button in sealed play: SEAL ORDERS during the orders phase, PASS in sorcery.
func _sealed_on_button() -> void:
	if combat._net_match_over:
		return
	if combat._sorcery_active >= 0:
		if combat._sorcery_active != NetMatch.local_player_index:
			return
		# Cards marked during the open spell step discard as we pass.
		var sorcery_discards: Array = []
		for card in combat._hand:
			if card != null and is_instance_valid(card) and card.marked_for_discard:
				sorcery_discards.append(int(card.deck_uid))
		combat._flush_marked_discards()
		if combat._end_turn_btn != null:
			combat._end_turn_btn.disabled = true
		if combat._is_host():
			_sealed_sorcery_pass(0)
		else:
			NetMatch.send_intent({"t": NetMatch.IN_SORCERY_PASS,
				"discards": sorcery_discards})
		return
	if combat._sealed_await_foe or combat.phase != combat.Phase.PLAYER_TURN:
		return
	# Marked discards leave with the sealed orders (hand-local, so the foe
	# learns the count — never the faces — via the fx beat inside the flush).
	var order_discards: Array = []
	for card in combat._hand:
		if card != null and is_instance_valid(card) and card.marked_for_discard:
			order_discards.append(int(card.deck_uid))
	combat._flush_marked_discards()
	combat._sealed_await_foe = true
	# Orders committed — drop the planning overlay (same beat solo drops it, see
	# _net_on_done_placing) and lock the hand until the reveal / your spell step.
	combat._clear_threat_flags()
	Card2D.hand_interactive = false
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = true
		combat._set_primary_action("waiting")
	combat._update_hud()
	var list: Array = []
	for p in combat._sealed_pending:
		list.append({"id": p.id, "uid": p.uid, "lane": p.lane, "row": p.row})
	combat._show_info("Orders sealed. Waiting for your opponent…")
	if combat._is_host():
		_sealed_store_bundle(0, list, combat.player_mana)
	else:
		NetMatch.send_intent({"t": NetMatch.IN_ORDERS, "list": list,
			"discards": order_discards})




## HOST: hold a side's sealed bundle; reveal once both are in.
func _sealed_store_bundle(side: int, list_value: Variant, unspent: int,
		discards_value: Variant = []) -> void:
	if not combat._is_host() or combat._net_match_over or not _is_sealed():
		return
	if combat._sealed_bundles.has(side):
		return   # duplicate seal — ignore
	if typeof(list_value) != TYPE_ARRAY or typeof(discards_value) != TYPE_ARRAY:
		if side == 1 and not SkirmishState.vs_bot:
			_net_reject_remote("illegal_orders_shape")
		return
	var list: Array = list_value
	var discards: Array = discards_value
	if side == 1 and not SkirmishState.vs_bot:
		if combat.phase != combat.Phase.PLAYER_TURN or combat._sorcery_active >= 0:
			_net_reject_remote("orders_phase_closed")
			return
		if _remote_state == null or list.size() > 8 or discards.size() > 10:
			_net_reject_remote("illegal_orders")
			return
		var seen_uids: Dictionary = {}
		var seen_slots: Dictionary = {}
		var total_cost := 0
		for raw_order in list:
			if not (raw_order is Dictionary):
				_net_reject_remote("illegal_order_shape")
				return
			var order: Dictionary = raw_order
			var uid := int(order.get("uid", -2))
			var id := String(order.get("id", ""))
			var lane := int(order.get("lane", -1))
			var row := int(order.get("row", -1))
			var slot_key := "%d:%d" % [row, lane]
			var entry: Dictionary = _remote_state.hand_entry(uid)
			var data := SkirmishState.skirmish_card_data(id)
			if entry.is_empty() or String(entry.get("id", "")) != id \
					or String(data.get("type", "")) != "creature" \
					or seen_uids.has(uid) or seen_slots.has(slot_key) \
					or lane < 0 or lane >= combat.LANES_PER_ROW \
					or row < combat.ROW_FRONT or row > combat.ROW_BACK \
					or combat._row_array(true, row)[lane] != null \
					or not _sealed_remote_ghosts.has(slot_key):
				_net_reject_remote("illegal_order_card")
				return
			seen_uids[uid] = true
			seen_slots[slot_key] = true
			total_cost += _remote_state.effective_cost(entry, data,
				_net_remote_has_first_spell_discount())
		if seen_slots.size() != _sealed_remote_ghosts.size() or total_cost > _remote_state.mana:
			_net_reject_remote("illegal_order_total")
			return
		for raw_discard in discards:
			if seen_uids.has(int(raw_discard)):
				_net_reject_remote("ordered_card_discarded")
				return
		var discard_result: Dictionary = _remote_state.discard_cards(discards)
		if not bool(discard_result.get("ok", false)):
			_net_reject_remote(String(discard_result.get("reason", "illegal_discard")))
			return
		for raw_order in list:
			var order: Dictionary = raw_order
			var check: Dictionary = _remote_state.validate_play(int(order.get("uid", -2)),
				String(order.get("id", "")), _net_remote_has_first_spell_discount())
			if not bool(check.get("ok", false)) \
					or _remote_state.commit_play(check, true).is_empty():
				_net_reject_remote("order_commit_failed")
				return
		unspent = _remote_state.mana
		_net_send_private_state()
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
	# The backs turn edge-on (★5); the real cards open out of them below. This
	# is the one moment in the game that has earned a flip, and it used to be a
	# texture swap: the ghosts vanished and the cards popped in.
	_sealed_clear_pending_local(true)
	combat._show_combat_banner("ORDERS REVEALED", "", Color(1.0, 0.78, 0.35))
	if AudioBank != null:
		AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
	combat._net_cards_played[0] = 0
	combat._net_cards_played[1] = 0
	for side in [combat._net_initiative, 1 - combat._net_initiative]:
		# STOP STAMPING A FIGHT THAT IS OVER. `run_on_enter` is true for these spawns,
		# so a battlecry chain can end the match part-way through the reveal — the
		# function's own tail acknowledges that ("an on-enter chain ended it") but only
		# AFTER the loop had seated every remaining order. The watcher then read the
		# verdict and went on receiving fresh bodies behind it. Latent before the
		# per-order sync above (one trailing snapshot hid it); plainly visible now.
		if combat._net_match_over:
			break
		var b: Dictionary = combat._sealed_bundles.get(side, {})
		# Condottiere reads the caster's unspent pool: the client's rides its
		# bundle; the host's own pool is live in player_mana.
		combat._net_client_unspent_mana = int(b.get("mana", 0)) if side == 1 else 0
		for o_raw in b.get("list", []):
			if combat._net_match_over:
				break   # same reason as the outer break — see above
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
			# NOTE (★5): the card deliberately does NOT flip in here. It arrives
			# on the WAX PRESS — _net_spawn_creature → _play_landing_pop →
			# play_wax_press, which owns `scale` outright and defers a frame to
			# let the slot's CenterContainer lay out first. A Motion.flip_in
			# would be a second writer on the same property and the press would
			# clobber it regardless. The press is also the better beat: it's the
			# house's established "an order is STAMPED onto the board" language,
			# where a flip is generic. So the reveal's turn-over lives entirely
			# in the ghost going edge-on above; giving the card its own half
			# needs the landing-pop-vs-flip ownership settled first.
			_net_spawn_creature(data, int(o.get("uid", _net_issue_token_id())),
				lane, row, side == 1, true)
			# SHIP EACH ORDER AS IT LANDS (2026-08-04). The sync used to sit after the
			# loop, so the host watched the orders STAMP DOWN one at a time in
			# initiative order — the mode's signature moment — while the watcher got a
			# single snapshot and every card appeared on one frame. Syncing per order
			# gives the client the same paced arrival through the path it already has
			# (`_net_apply_board_sync` → `_net_spawn_creature` → `_play_landing_pop` →
			# the wax press), with no new message kind and no second authoritative
			# spawn path: the snapshot stays the client's single source of truth, which
			# is what keeps this cheap in risk. A sealed round commits at most eight
			# orders, so it is at most eight small snapshots.
			_net_sync_board()
			await combat._short_pause(0.12)
	_net_sync_board()
	await combat._short_pause(combat.COMBAT_PAUSE_SHORT)
	if combat._net_match_over:
		return   # an on-enter chain ended it
	_sealed_open_sorcery()




## BOTH machines: drop my pending stand-ins + the foe's ghosts. The authoritative
## board arrives via the reveal spawns (host) / trailing snapshot (client).
##
## `flip` is opt-in and belongs to the REVEAL only (★5): the face-down backs
## turn edge-on so the real cards can open out of them a beat later. Every other
## caller — rejection, round teardown, a closed orders phase — is an ERROR or
## bookkeeping path where the ghosts must simply be gone, and a flourish there
## would dress up a failure as a reveal.
func _sealed_clear_pending_local(flip: bool = false) -> void:
	for g in combat._sealed_ghosts:
		if g != null and is_instance_valid(g):
			if flip:
				Motion.flip_out(g)
			else:
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
	_sealed_load_spell_state(who)
	var mine: bool = who == NetMatch.local_player_index
	# Only the caster whose spell step is open may play from hand.
	Card2D.hand_interactive = mine
	combat._refresh_hand_affordability()
	if combat._end_turn_btn != null:
		combat._end_turn_btn.disabled = not mine
		combat._set_primary_action("pass" if mine else "waiting")
	if mine:
		combat._set_phase_caption("YOUR SPELL STEP")
		combat._show_info("Your spell step — cast freely over the revealed lines, then pass.")
	else:
		combat._set_phase_caption("OPPONENT'S SPELL STEP")
		combat._show_info("Your opponent is casting spells…")




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
		if _wire_str(intent.get("t", "")) != NetMatch.IN_PLAY_CREATURE:
			continue   # v1: the sealed bot fields creatures only
		var lane := _wire_int(intent.get("lane", -1), -1)
		var row = _wire_int(intent.get("row", combat.ROW_FRONT), combat.ROW_FRONT)
		spent += _bot_consume_card(_wire_int(intent.get("uid", -1), -1))
		_bot_sync_hand_display(mana - spent)
		list.append({"id": _wire_str(intent.get("id", "")),
			"uid": _wire_int(intent.get("uid", -1), -1), "lane": lane, "row": row})
		_sealed_show_ghost(lane, row)
		await combat._short_pause(0.25)
	combat._bot_banked_mana = clampi(mana - spent, 0, _bot_bank_cap())
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
	combat._reset_free_moves_for_side(active_index == 1)
	combat._net_spells_this_turn = 0   # per-turn spell tally (flame_bolt combo)
	combat._net_last_spell_data = {}   # Echo only reaches back within the current turn
	combat._net_last_spell_target_eid = -1
	# Per-turn passive counters for the side whose turn is opening (Ironclad's cards-
	# this-turn).
	combat._net_cards_played[active_index] = 0
	if active_index == 1 and not SkirmishState.vs_bot and _remote_state != null:
		_remote_state.begin_turn(combat._net_turn_round, _net_remote_empty_edge_columns())
		_net_send_private_state()
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
	# NOT awaited, and must stay that way: it is a coroutine solo-side (paced
	# groups — see Combat._round_beat), but _round_beat returns synchronously
	# whenever _is_net(), so it never suspends here.
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
		combat._set_primary_action("clash" if will_strike else "end_turn")
	_net_broadcast_hand_count()




## CLIENT: react to the host's turn-begin event.
func _net_client_turn_begin(active: int, rnd: int) -> void:
	combat._net_active_index = active
	combat._net_turn_round = rnd
	if active == NetMatch.local_player_index:
		combat._moves_used_this_turn = 0
		combat._reset_free_moves_for_side(false)
	if active == NetMatch.local_player_index:
		# Slot 1's draw, piles and Command were already applied from EV_HAND_SET.
		# Only the host-side local player still runs Combat._start_round directly.
		if combat._is_client():
			_net_set_local_active(true)
			combat._show_combat_banner("YOUR TURN", "", Color(0.98, 0.86, 0.55))
			if AudioBank != null:
				AudioBank.play_sfx("turn_start", 0.03, -2.0)
			if combat._end_turn_btn != null:
				var will_strike: bool = combat._net_turn_round > 1 \
					or combat._net_goes_second(NetMatch.local_player_index)
				combat._set_primary_action("clash" if will_strike else "end_turn")
		else:
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
	if active or (combat._net_active_index >= 0
			and combat._net_active_index != NetMatch.local_player_index):
		combat._update_hud()




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
	var discard_uids: Array = []
	for card in combat._hand:
		if card != null and is_instance_valid(card) and card.marked_for_discard:
			discard_uids.append(int(card.deck_uid))
	combat._flush_marked_discards()
	# Drop the planning overlay before the lines meet (2026-08-04). Solo does this
	# at the same beat — `_on_end_turn` calls `_clear_threat_flags()` the instant it
	# flips to RESOLVING, because the clash itself is now the read and the forecast
	# was only ever an aid for the decision you have just made. The skirmish commit
	# never did, so a shot of a net clash had DIES / TAKES 1 - 8 HP chips floating
	# over the bodies actually dying, which is the forecast contradicting the board.
	# `_refresh_lane_forecast` bails outside PLAYER_TURN, so nothing re-adds them.
	combat._clear_threat_flags()
	if combat._net_turn_round > 1 or combat._net_goes_second(NetMatch.local_player_index):
		combat._play_clash_commit_vfx()
	if combat._is_host():
		_net_finish_placement(0)
	else:
		_net_set_local_active(false)
		combat._set_primary_action("waiting")
		combat._set_phase_caption("WAITING FOR OPPONENT")
		combat._show_info("Turn committed — waiting for the clash…")
		NetMatch.send_intent({"t": NetMatch.IN_END_ACTIONS, "discards": discard_uids})




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


func _net_log_lunge(attacker: Control, defender: Control = null) -> void:
	if not combat._net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return   # mid-clash tokens have no eid yet — the snapshot reconciles them
	# "latk" = the swing's weight, so the client's replay lunges with the same
	# drive (effective_atk is close enough to the host's lane-aware value for a
	# purely cosmetic scale).
	var entry := {"l": int(attacker.entity_id)}
	# "dt" = who is about to be hit. The client otherwise learns the target only
	# at the {d} entry, which lands AFTER contact — too late to brace. Carrying
	# it here is what lets both peers show the same wind-up instead of the host
	# alone. (docs/STRIKE_DESIGN_20260730.md §8)
	if defender != null and is_instance_valid(defender) and int(defender.entity_id) >= 0:
		entry["dt"] = int(defender.entity_id)
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




## `power` = the blow's PRE-mitigation size, and it is the reason this entry exists
## in its current shape. The host weighs a strike's punctuation off that number
## (`_strike_stop` / `_strike_read` / the tracer's width / the burst's spray), while
## `n` is only what survived Armored, a Shield or an HP floor. A client working from
## `n` alone therefore ran a DIFFERENT weight class for the same blow — an 8-ATK
## swing fully eaten by a Shield is a heavy strike that removed nothing, and the two
## peers disagreed about it. Optional so the ten incidental sites (cleave splash,
## overflow spill, hydra, stampede, the ledger) can keep passing nothing and fall
## back to `n`, which is the right answer for a rider that has no separate weight.
##
## `ranged` marks a shot rather than a swing. The tracer draws tighter and colder
## for one so a marksman does not read like a melee attacker — the client had no way
## to know, so every sniper shot in skirmish came out as a warm melee slash.
func _net_log_hit(attacker: Control, defender: Control, hp_before: int,
		is_counter: bool = false, power: int = -1, ranged: bool = false) -> void:
	if not combat._net_clash_recording:
		return
	if defender == null or not is_instance_valid(defender) or int(defender.entity_id) < 0:
		return
	var entry := {
		"d": int(defender.entity_id),
		"hp": int(defender.current_hp),
		"n": maxi(0, hp_before - int(defender.current_hp)),
	}
	if power > 0:
		entry["p"] = power
	if ranged:
		entry["rng"] = true
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




## Log the sub-phase caption the host flips mid-clash so the client's phase line
## matches instead of going blank. Since 2026-08-04 that is the same set of captions
## solo raises — SWIFT STRIKES, FRONT ROW ATTACKS, BACK ROW ATTACKS, CLASH, THE FALLEN,
## THE DOUBLED HOUR, RAIN OF BLOWS — because the clash the client watches is now the
## same paced, named sequence the campaign runs.
func _net_log_caption(text: String) -> void:
	if combat._net_clash_recording:
		combat._net_clash_log.append({"cap": text})




## THE PACING CROSSES THE WIRE AS DECISIONS, NOT AS SECONDS (2026-08-04).
##
## The skirmish clash used to be a burst on BOTH machines: the host resolved every
## column on adjacent frames, and the client replayed a flat strike list with no
## sense of which column was being decided. Solo, meanwhile, has spent two passes
## learning to spotlight one column at a time and to spend its dwell where the
## information is. These two entries carry that structure across:
##
##   {fo: lane, fe: enemy_strike}  — put the spotlight on this column
##   {dw: kind}                    — this column earned a MINOR / NORMAL / KILL slot
##
## Both are *choices*, not durations. The watching peer runs its own
## `_focus_combat_lane` and `_run_lane_dwell`, so the Clash Pause dial and Animation
## Speed that pace the host's clash are the CLIENT's own settings on the client's
## screen. Shipping a float would have quietly handed one player's reading speed to
## the other, which is exactly what that dial exists to prevent.
##
## `fe` is written from the HOST's point of view ("the striker is on the enemy half
## of my board") and the client INVERTS it on replay — the clash log only ever flows
## host → client, so the two boards are exact mirrors of each other and one flip is
## the whole transform. Lane index needs no transform: the board mirrors front-to-
## back, not left-to-right, so column 2 is column 2 on both screens.
func _net_log_focus(lane_idx: int, enemy_strike: bool) -> void:
	if combat._net_clash_recording:
		combat._net_clash_log.append({"fo": lane_idx, "fe": enemy_strike})


func _net_log_dwell(kind: int) -> void:
	if combat._net_clash_recording:
		combat._net_clash_log.append({"dw": kind})


## Mark the point in the reel where the host's paced corpse flush runs. The client's
## corpses are swept by the TRAILING SNAPSHOT, not by this log, so it cannot simply
## replay a death list — instead it names its own mortally-struck bodies on the same
## budget (see _net_replay_fallen), and the beats it spends doing so are what hold
## the snapshot back until the names have been read.
func _net_log_fallen() -> void:
	# Only when there is actually a flush to pace. A marker over an empty sweep would
	# make the client run a naming pass with nothing to name — harmless, but it is
	# the same rule the captions follow (never announce an empty beat) and it keeps
	# the reel honest for anyone reading one.
	if combat._net_clash_recording and combat._downed_count() > 0:
		combat._net_clash_log.append({"fal": true})




## Log a piercing kill's skewer so the client draws the same lance. Both eids survive
## the beat (attacker lives through a pierce; victim isn't flushed until the snapshot),
## so the client can reconstruct the lance from its own card centres.
##
## THE TERMINUS IS HOST-AUTHORITATIVE (2026-07-30). The entry used to carry only the
## two ends of the KILL and let the client work out where the mark went, which is the
## one thing a client may never do: it may compute WHERE, never WHETHER. The client's
## `_pierce_body_behind` returned null for any back-row victim AND — because a live
## body behind makes the host spill to it instead — for every `reach_face` mark as
## well, so it fell back to a fixed 156 px stub into bare table while the host drew a
## ~400 px stroke to the hero plate. The plate terminus, which is piercing's whole
## absolute tell, never once rendered on the client.
##
## `pr` = the receiver's eid, or -1. `pf` = the OWNER INDEX of the plate the mark ends
## on (same convention as the face-hit entries' `f`), or -1 when it ends on a body.
## With both absent the client draws nothing — the honest failure, and the one the
## host itself performs when nothing carried.
func _net_log_pierce(attacker: Control, victim: Control,
		receiver: Control = null, face_owner: int = -1,
		is_pierce: bool = true) -> void:
	if not combat._net_clash_recording:
		return
	if attacker == null or not is_instance_valid(attacker) or int(attacker.entity_id) < 0:
		return
	if victim == null or not is_instance_valid(victim) or int(victim.entity_id) < 0:
		return
	var recv_eid: int = -1
	if receiver != null and is_instance_valid(receiver):
		recv_eid = int(receiver.entity_id)
	# `pp` is the host's own `reach_face` — the KEYWORD flag that picks the stroke's
	# material. It is deliberately separate from `pf`: a piercing attacker whose
	# spill lands on the body behind still draws the piercing mark, so "ends on a
	# plate" and "is a piercing mark" are different questions and the client must
	# not infer one from the other.
	combat._net_clash_log.append({
		"pl": int(attacker.entity_id),
		"pv": int(victim.entity_id),
		"pr": recv_eid,
		"pf": face_owner,
		"pp": is_pierce,
	})




## Buffer a floating text callout (e.g. a warden's "+N ATK" pump) onto a creature by
## eid so it replays on the client — the host spawns these at world positions the client
## cannot reuse.
##
## Routed through `_net_queue_fx_chip` since 2026-08-04 rather than straight onto the fx
## queue: several of its callers (`_apply_ally_death_passives` above all, which fires
## during the recorded corpse flush) run MID-CLASH, and the queue does not ship until the
## trailing snapshot. So those floats arrived in a batch after the fight instead of on
## the body they described, while every other chip had already been moved into the reel.
func _net_fx_text(creature: Control, label: String, color: Color) -> void:
	if not combat._is_host() or creature == null or not is_instance_valid(creature):
		return
	if int(creature.entity_id) < 0:
		return
	_net_queue_fx_chip({
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




## Take the spotlight off the board on the watcher's screen too. Purely local on the
## host (it just calls clear_focus), so this only has to exist for the replay.
func _net_log_focus_clear() -> void:
	if combat._net_clash_recording:
		combat._net_clash_log.append({"fo": -1})


## The clash's closing ledger, shipped as COUNTS and never as the finished sentence.
## The host writes "ours" from its own board; the client's board is the mirror, so the
## pair is swapped on replay and each player reads "ours" as their OWN line. Sending
## the string would have told the player who just lost four bodies that their line
## held — the same class of mistake `fe` avoids by inverting rather than re-deriving.
func _net_log_ledger(ours: int, theirs: int) -> void:
	if combat._net_clash_recording:
		combat._net_clash_log.append({"led": [ours, theirs]})




## A KEYWORD CHIP FIRES WHERE IT HAPPENED (2026-08-04, second pass).
##
## Every callout the host raises — POISON, THORNS, REFLECT, THE WORKS, SPLINTER,
## LAST STAND, a deathrattle's label — used to go on the fx QUEUE, which ships with
## the trailing board snapshot. The clash log is deliberately sent AHEAD of that
## snapshot, so on the client the entire clash played through with no chips at all
## and then every chip in it arrived at once, in a batch, over a settled board. The
## host saw a reason beside each blow; the watcher saw a pile of words afterwards.
##
## Mid-clash the chip therefore rides the REEL instead, at the position it fired, and
## falls back to the queue everywhere else (a battlecry during the play phase has no
## reel to ride). The two channels are exclusive by construction — one `if` — so a
## chip can never be drawn twice.
##
## Anchors are safe here: during a clash every callout is raised on a body that was
## already on the board when the reel was sent. A chip on a token summoned mid-clash
## would find no entity and be skipped, which is exactly what the {d} entries already
## do with the same bodies.
func _net_queue_fx_chip(entry: Dictionary) -> void:
	if not combat._is_host():
		return
	if combat._net_clash_recording:
		combat._net_clash_log.append({"kw": entry})
	else:
		combat._net_fx_queue.append(entry)


# Per-CLASH baselines for the closing beats. Private to CombatNet: solo reads the
# same facts off its own locals inside _do_combat, and nothing outside the clash
# has any use for them.
var _alive_before_clash: int = 0
var _ledger_ours_before: int = 0
var _ledger_theirs_before: int = 0


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
		combat._show_info("Their line strikes!")
	# Clash replay: from here every strike beat is logged for the client's paced
	# replay (see the EV_CLASH block above). Recording stays on through each
	# segment's death flush so on-death face chips keep their place in the reel.
	combat._net_clash_log.clear()
	combat._net_clash_banner_sent = false
	combat._net_clash_attacking_side = attacking_side
	combat._net_clash_recording = true
	# Baselines for the closing beats (2026-08-04): the headcount funds the mass-grave
	# punctuation, the two tallies fund the post-clash ledger. Both are per-CLASH here
	# rather than per-round — the alternating style runs this twice a round.
	_alive_before_clash = combat._all_creatures_both_sides().size()
	_ledger_ours_before = combat._friendly_deaths_this_round
	_ledger_theirs_before = combat._enemy_deaths_this_round
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
	# Lives on c.state (see the decay note in _net_decay_side_states): this was a
	# dead remove_meta, so the latch never cleared and a creature counter-attacked
	# exactly ONCE per match instead of once per clash.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			c.state.counter_spent_this_clash = false
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
	# SWIFT PHASE — striking sides only, deaths HELD so Swift-vs-Swift trades
	# (see _do_combat).
	Card2D.defer_deaths = true
	for lane_idx in range(combat.LANES_PER_ROW):
		if host_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_FRONT, false)
		if client_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_FRONT, true)
	for lane_idx in range(combat.LANES_PER_ROW):
		if host_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_BACK, false)
		if client_strikes:
			await combat._resolve_swift_attack(lane_idx, combat.ROW_BACK, true)
	Card2D.defer_deaths = false
	_net_log_fallen()
	await combat._cleanup_dead_paced()
	_net_send_clash_log()   # ship the Swift beats AHEAD of their outcome snapshot
	_net_sync_board()   # let the client see the Swift results before the main clash
	# NOT re-armed once the fight is decided. A Swift striker can reach the face, and
	# `damage_enemy_hero` declares the match over SYNCHRONOUSLY from inside that pass —
	# which flushes the reel and sends the verdict (see _net_host_check_match_over).
	# Re-arming unconditionally here would record the now-moot main pass and ship it
	# AFTER that verdict, putting the watcher back in front of the very inversion the
	# flush exists to prevent, just one phase later.
	if not combat._net_match_over:
		combat._net_clash_recording = true
	# MAIN PASS — striking sides per lane, deaths HELD so mutual kills drop both.
	# In a one-directional pass this is where the Cross-Blitz counterstrike lives:
	# the struck defender hits back inside _creature_attacks_creature (gated below).
	# A both-sides pass (sealed) is already simultaneous, so it stays off there.
	#
	# SERIALIZED THROUGH THE SAME UNIT AS SOLO (2026-08-04). This used to call
	# `_resolve_column_attack` twice per column inline, which resolved the whole line
	# on adjacent frames — the exact undifferentiated burst the campaign clash was
	# rebuilt to stop being. `_clash_lane_pass` is that rebuild, and it takes a
	# `side_filter` now precisely so the one-directional net pass can be the same
	# code: spotlight the column, swing, weigh what happened, hold long enough to
	# read it. The two ranks are named for the same reason they are in solo — a
	# clash with phase boundaries beats one eight-beat "CLASH".
	combat._net_mutual_retaliation = attacking_side >= 0
	Card2D.defer_deaths = true
	var front_strikes: bool = combat._rank_will_strike(combat.ROW_FRONT, attacking_side)
	var back_strikes: bool = combat._rank_will_strike(combat.ROW_BACK, attacking_side)
	if front_strikes or back_strikes:
		combat._set_phase_caption("CLASH")
	if front_strikes:
		combat._set_phase_caption("FRONT ROW ATTACKS")
	for lane_idx in range(combat.LANES_PER_ROW):
		await combat._clash_lane_pass(lane_idx, combat.ROW_FRONT,
			enemy_front_empty, player_front_empty, attacking_side)
	# Re-asked after the front rank resolved, exactly as solo asks it — the answer
	# can move (a back-row body spent by an interpose, a Twinblade already swung).
	if combat._rank_will_strike(combat.ROW_BACK, attacking_side):
		combat._set_phase_caption("BACK ROW ATTACKS")
	for lane_idx in range(combat.LANES_PER_ROW):
		await combat._clash_lane_pass(lane_idx, combat.ROW_BACK,
			enemy_front_empty, player_front_empty, attacking_side)
	combat._net_mutual_retaliation = false
	Card2D.defer_deaths = false
	# Name the beat BEFORE the bodies go (the 2026-07-28 lesson): `_downed_count`
	# reads the dead-but-still-standing that defer_deaths has been holding, which is
	# the same information one beat sooner than a headcount diff could give it.
	if combat._downed_count() > 0:
		combat._set_phase_caption("THE FALLEN")
	_net_log_fallen()
	await combat._cleanup_dead_paced()
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
	# Rain of Blows resolves after the normal ranged volley so an ordered Sniper has
	# completed its first strike before the shared helper considers its second.
	await combat._run_battle_order_strikes(player_front_empty, enemy_front_empty,
		attacking_side)
	await combat._run_doubled_hour_snipe()
	if attacking_side >= 0:
		combat._doubled_hour[1 - attacking_side] = _dh_stash
	# Berserker growth — scan both rows on both sides. `grow` = per-attack ATK gain.
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c) and c.card_data.get("passive", "") == "grow_on_attack" and c.has_attacked_this_turn:
			c.current_atk += int(c.card_data.get("grow", 1))
			c.update_stat_display()
	# The late sweep — whatever the ranged / second-swing phases killed after the main
	# flush. Paced like solo's, and the spotlight comes off the board here so the
	# settled result is read without one column still lit.
	if combat._downed_count() > 0 and combat._phase_caption != "THE FALLEN":
		combat._set_phase_caption("THE FALLEN")
	_net_log_fallen()
	await combat._cleanup_dead_paced()
	if combat._clash_lane_focus != null and is_instance_valid(combat._clash_lane_focus):
		combat._clash_lane_focus.clear_focus()
	_net_log_focus_clear()
	# A mass grave is a beat, not a blink — the same 3+-fallen punctuation solo gets.
	# (The client's copy of this already fires in _net_apply_board_sync, where its
	# deaths flush; this is the host's half.)
	var fallen_n: int = _alive_before_clash - combat._all_creatures_both_sides().size()
	if fallen_n >= 3:
		combat.screen_shake(11.0)
		await combat._short_pause(combat.HITSTOP_BEAT * 2.0)
	combat._post_clash_ledger(_ledger_ours_before, _ledger_theirs_before)
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
		# These four live on CreatureInstance (c.state), NOT as node metadata.
		# They were node meta before the CreatureInstance migration and these
		# lines were left as remove_meta calls afterwards — no set_meta call for
		# any of these keys exists anywhere, so the decay was a silent no-op and
		# net had NO reset at all (solo is covered by tick_end_of_round). That
		# left Charge! and Rain of Blows firing every clash for the rest of the
		# match. Write the fields.
		if c.state.temp_poison:
			c.card_data.keywords.erase("poison")
			c.state.temp_poison = false
			c.update_stat_display()
		c.state.charges_this_turn = false
		c.state.battle_order_second_strike = false




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
	# SHIP THE FIGHT BEFORE THE VERDICT (2026-08-04). This is reached SYNCHRONOUSLY from
	# `damage_enemy_hero` -> `_check_game_over`, i.e. from inside the clash, while the
	# reel that contains the killing blow is still sitting unsent in `_net_clash_log`
	# (it does not ship until the clash ends). So the watcher used to receive
	# EV_MATCH_OVER first, show the verdict banner over a settled board, and only THEN
	# get the reel and replay the fight that produced it — the result before its cause.
	#
	# Flushing here puts the reel on the wire first, and the client's existing backlog
	# does the rest: `_net_replay_active` goes true for the replay and EV_MATCH_OVER
	# queues behind it, so the killing blow lands, claims its ★8 hold, and the ceremony
	# follows it. Recording is deliberately left OFF afterwards — the remainder of the
	# host's clash is post-lethal and moot, the trailing sync still reconciles the
	# board, and the watcher is in the verdict ceremony by then.
	if combat._net_clash_recording:
		_net_send_clash_log()
	NetMatch.send_to_client({"t": NetMatch.EV_MATCH_OVER, "winner": winner})
	_net_sync_board()
	_net_show_result(winner)




func _net_show_result(winner_index: int) -> void:
	if combat._net_match_over:
		return   # one result per game — guards the Best-of-N tally against double-count
	combat._net_match_over = true
	# THE BOT GOES BACK OVER THE GAME IT JUST PLAYED (2026-09-15). Here rather
	# than in the Bo1 arm below, because every game of a series is a game to learn
	# from and the series arm returns early. `on_match_over` is bounded work
	# (a few hundred rollouts, and a trial only every fifth game under a
	# wall-clock budget) — it is never allowed to be the reason this frame is late.
	if SkirmishState.vs_bot:
		SkirmishBot.on_match_over(winner_index)
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
		combat._play_killing_blow_moment(series_won)  # ★8: same world-stop as solo
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
		combat._play_killing_blow_moment(winner_index == me)  # ★8: same world-stop as solo
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
	# A GAME INSIDE A SERIES IS STILL A FIGHT THAT ENDED (2026-08-04). This used to be
	# the one fight-ending in the game with no ceremony at all — a 24px caption swap and
	# a sting, which is precisely the "decisive beat presented as a label" that
	# _show_battle_verdict was built to replace. Every solo fight gets the banner and so
	# does the series' last game; games 1 and 2 of a Bo3 got nothing. Both peers run this
	# path symmetrically, so adding it keeps the two screens identical.
	#
	# Guarded on a real winner for the same reason the Bo1 path is: a DRAW is neither
	# VICTORY nor DEFEAT, and the banner can only say one of those two words.
	if winner_index >= 0:
		combat._play_killing_blow_moment(winner_index == me)
		combat._show_battle_verdict(winner_index == me, 0, false, true,
			_net_series_score_str())
	# Hold the standing on screen, then advance. The host only relaunches once BOTH
	# sides have signalled, so a small clock skew between the two timers is harmless.
	# 2.8s, not the old 2.2: the banner alone holds 1.7 and fades over 0.4, so the
	# shorter wait would have advanced the scene into its own fade.
	await combat.get_tree().create_timer(2.8).timeout
	# THE SCENE CAN BE GONE BEFORE THIS RESUMES. _net_on_peer_lost runs a 2.0s
	# timer then a 0.5s fade into the menu, so a peer dropping during this
	# interstitial frees Combat (and this node with it) at ~2.5s — a full 0.3s
	# before the 2.8s wait is up. A SceneTreeTimer survives the scene change, so
	# the latch test below was reading a member off a freed instance: the guard
	# that exists specifically for this case was itself past the point of no
	# return. Check the instance FIRST, then the latch.
	if not is_instance_valid(combat):
		return   # the scene left while we waited; nothing here has an owner
	# Was a dead guard: _net_match_over is set TRUE by _net_show_result before we
	# run, and _net_on_peer_lost never clears it, so this could never be true and
	# the stated protection never once fired. Test the peer-lost latch instead.
	if combat._net_peer_lost_handled:
		return   # peer left during the pause; _net_on_peer_lost owns the teardown
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
		combat._show_info("Opponent wants a rematch — press Rematch to play again.")
	_net_try_start_rematch()




## When BOTH sides want a rematch, the HOST relaunches combat (host-authoritative,
## both peers transition together; _enter_combat_local resets HP + the board).
func _net_try_start_rematch() -> void:
	# THE PRACTICE BOT ALWAYS SAYS YES, because there is nobody to ask. A drill has
	# no peer, so `EV_REMATCH` goes into `send_to_client`'s `not remote_present`
	# early return and `_net_rematch_remote` can never turn true — the handshake
	# was waiting on an answer that could not arrive. Two live consequences, both
	# reachable straight from the lobby's PRACTICE VS BOT panel:
	#   * Bo1 — REMATCH relabels itself "WAITING FOR OPPONENT…" and stays there
	#     forever. LEAVE TO MENU was the only working button on the panel.
	#   * Bo3 — worse, and silent: the lobby offers BEST OF 3 against the bot, and
	#     `_net_show_series_interstitial` drives this same handshake with no button
	#     involved. Game 1 ended, the standing was shown, and game 2 never started.
	#     The player was left on a settled board with no panel and no way forward.
	var remote_agrees: bool = combat._net_rematch_remote or SkirmishState.vs_bot
	if not (combat._net_rematch_local and remote_agrees):
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
				if c.state.sealed_pending:
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
					# Versioned, Variant-only runtime contract. Viewer-relative
					# ownership/position and folded ATK remain the fields above.
					"state": c.state.to_replication_snapshot(),
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
		"moves": combat._moves_used_this_turn,
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
	# Deathrattle beats FIRST, while the bodies that fired them are still standing —
	# they radiate out of a seat the loop below is about to empty.
	_net_replay_trigger_fx(ev, "death")
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
	combat._moves_used_this_turn = int(ev.get("moves", combat._moves_used_this_turn))
	combat._update_hud()
	# Face-damage feedback (the client only learns hero HP from the snapshot).
	# NOTE: a clash's face blows are already applied+logged in _net_replay_face_hit
	# (it sets player_hp/enemy_hp directly), so the delta here is zero for those —
	# this block only fires for NON-clash face damage (spell to face), which is
	# exactly what should be logged here to avoid double-counting the clash.
	if combat.enemy_hp < prev_enemy_hp and combat._enemy_hp_label != null:
		combat.spawn_floating_number(combat._enemy_hp_label.get_global_rect().get_center(),
			"-%d" % (prev_enemy_hp - combat.enemy_hp), Color(0.95, 0.5, 0.3), true)
		combat._log_event("The enemy takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
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
	# Battlecries / on-play abilities: after the reconcile, so a creature that arrived
	# in THIS snapshot exists to announce from.
	_net_replay_trigger_fx(ev, "enter")
	_net_replay_trigger_fx(ev, "play")




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
			combat._show_info("Their line strikes!")
	var strikes: Array = ev.get("strikes", [])
	var i: int = -1
	while i + 1 < strikes.size():
		i += 1
		var s: Dictionary = strikes[i]
		if s.has("fo"):       # the spotlight moves to a column (-1 = take it off)
			var fo_lane: int = int(s.get("fo", -1))
			if fo_lane < 0:
				if combat._clash_lane_focus != null \
						and is_instance_valid(combat._clash_lane_focus):
					combat._clash_lane_focus.clear_focus()
			else:
				# The host wrote `fe` from ITS board; ours is the mirror, so a striker
				# the host called friendly is our foe and the mark leans the other way.
				combat._focus_combat_lane(fo_lane, not bool(s.get("fe", false)))
		elif s.has("dw"):     # this column earned a registration slot — hold on it
			await combat._run_lane_dwell(int(s.get("dw", 0)))
		elif s.has("fal"):    # the host's corpse flush — name ours on the same budget
			await _net_replay_fallen()
		elif s.has("l"):      # attacker wind-up
			var lunger = NetMatch.get_entity(int(s.get("l", -1)))
			if lunger != null and is_instance_valid(lunger) and lunger.has_method("play_attack_lunge"):
				lunger.play_attack_lunge(combat._lunge_strength(int(s.get("latk", 2))))
			# Mirror the brace so the client sees the same collision, not a
			# one-sided swing. Host-named target; the client never guesses it.
			if int(s.get("dt", -1)) >= 0:
				var braced = NetMatch.get_entity(int(s.get("dt", -1)))
				if braced != null and is_instance_valid(braced) \
						and braced.has_method("play_defend_brace"):
					# `from_below` names where the ATTACKER is, so it is the braced
					# body's own side: a body drawn at the top of the board is struck
					# from below. Host-side that reads `not attacker_is_enemy`, which
					# IS the defender's side — inverted here, the watcher's defender
					# leaned away from the blow instead of into it.
					braced.play_defend_brace(bool(braced.is_opponent))
			await combat._short_pause(combat.LUNGE_APEX)
		elif s.has("cap"):    # a mid-clash phase caption (THE DOUBLED HOUR)
			combat._set_phase_caption(String(s.get("cap", "")))
		elif s.has("kw"):     # a keyword chip, fired where it happened
			_net_render_fx_chip(s.get("kw", {}))
		elif s.has("led"):    # the clash's closing ledger — counts, read from OUR side
			var led: Array = s.get("led", [])
			if led.size() >= 2:
				combat._show_info(combat._clash_ledger_line(int(led[1]), int(led[0])))
		elif s.has("pl"):     # a piercing kill's skewer
			_net_replay_pierce(int(s.get("pl", -1)), int(s.get("pv", -1)),
				int(s.get("pr", -1)), int(s.get("pf", -1)), bool(s.get("pp", true)))
		elif s.has("f"):      # a hero took the blow
			await _net_replay_face_hit(s)
		elif s.has("d"):      # a creature took the blow
			# A CROSS-BLITZ TRADE IS ONE BEAT, NOT TWO. Host-side the forward blow and
			# the defender's counter both resolve inside _creature_attacks_creature and
			# a SINGLE weighted hold punctuates the exchange at its tail. Replaying the
			# two logged halves as independently-punctuated strikes paid that hold
			# twice and pushed the counter's tracer a whole beat behind the blow that
			# provoked it — and the mutual trade is the DEFAULT in the alternating
			# style, not an edge case. So a blow followed by its counter is replayed
			# dry, and the forward blow's weight buys the one hold, as host-side.
			var nxt: Dictionary = strikes[i + 1] if i + 1 < strikes.size() else {}
			var paired: bool = not bool(s.get("ctr", false)) \
				and nxt.has("d") and bool(nxt.get("ctr", false))
			await _net_replay_creature_hit(s, not paired)
			if paired:
				i += 1
				await _net_replay_creature_hit(nxt, false)
				await _net_strike_punctuation(s)
	combat._net_replay_active = false
	_net_flush_backlog()




func _net_flush_backlog() -> void:
	while not combat._net_event_backlog.is_empty():
		if combat._net_replay_active:
			return   # a queued clash log started a new replay — it owns the flush now
		_net_process_event(combat._net_event_backlog.pop_front())




## CLIENT: the naming half of the host's corpse flush, run on our own clock.
##
## We cannot replay a death list: the client's corpses belong to the trailing board
## snapshot, which despawns them with the ash burst and the slump. What we CAN do —
## and what the host does in `_cleanup_dead_paced` — is name each body over the slot
## it fell in, one beat at a time, under the shared budget. The beats spent here are
## load-bearing twice over: they are what makes the names readable one at a time, AND
## they are what holds the snapshot back (it is queued in `_net_event_backlog` while
## `_net_replay_active` is on), so the corpses sweep AFTER their names have been read
## instead of vanishing under them.
##
## The bodies are already `_mark_mortally_struck` from the strike replay, so a
## `current_hp <= 0` scan finds exactly the set the host is flushing — the same
## predicate `_downed_count` uses, which is what keeps the two budgets identical.
func _net_replay_fallen() -> void:
	var corpse_n: int = combat._downed_count()
	if corpse_n <= 0:
		return
	var beat: float = combat._death_flush_beat(corpse_n)
	await combat._short_pause(beat)
	if not combat._death_beat_names(beat):
		return   # a wipe: past the subitizing limit the names stop being casualties
	var seen_one := false
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for is_enemy in [false, true]:
			var arr = combat._row_array(is_enemy, row)
			for lane_idx in range(combat.LANES_PER_ROW):
				var c = arr[lane_idx]
				if c == null or not is_instance_valid(c) or c.current_hp > 0:
					continue
				if seen_one:
					await combat._short_pause(beat)
				seen_one = true
				combat._name_the_fallen(c, is_enemy)




## CLIENT: replay one logged blow. `punctuate` is false for the two halves of a
## Cross-Blitz trade, which the caller punctuates ONCE for the pair — see
## _net_replay_clash.
func _net_replay_creature_hit(s: Dictionary, punctuate: bool = true) -> void:
	var victim = NetMatch.get_entity(int(s.get("d", -1)))
	if victim == null or not is_instance_valid(victim):
		return   # a mid-clash token we never saw — the snapshot reconciles it
	var striker = NetMatch.get_entity(int(s.get("a", -1)))
	# `o` is the striker's OWNER INDEX, and it only rides the entry when the host had
	# a registered attacker to name (see _net_log_hit). The incidental sites that pass
	# no attacker — or one whose token has no eid yet — left this falling back to the
	# literal 0, which on the CLIENT (index 1) reads as "the foe struck" for EVERY such
	# blow, including the ones landing on the foe's own line. The recoil below and the
	# tracer both take their direction from it, so a friendly-fire chip kicked the
	# wrong way. Absent an owner, read it off the VICTIM: a blow on my body came from
	# the foe, a blow on theirs came from me.
	var attacker_is_foe: bool = (int(s["o"]) != NetMatch.local_player_index) \
		if s.has("o") else (not bool(victim.is_opponent))
	var dmg: int = int(s.get("n", 0))
	var hp_after: int = int(s.get("hp", victim.current_hp))
	# THE BLOW'S WEIGHT CLASS, as the host measured it (see _net_log_hit). Every
	# decision below that used to read `dmg` reads this instead, because `dmg` is
	# post-mitigation: a heavy swing a Shield swallowed whole is still a heavy swing,
	# and weighing it at 0 made the two peers punctuate the same strike differently.
	# Absent (a rider with no weight of its own, or an older peer) → fall back to the
	# damage, which is exactly what this path did for everything before 2026-08-04.
	var power: int = int(s.get("p", maxi(dmg, 1)))
	var ranged: bool = bool(s.get("rng", false))
	var lethal: bool = hp_after <= 0
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
			striker.play_attack_lunge(combat._lunge_strength(power))
		combat._play_attack_tracer(combat._card_center(striker), combat._card_center(victim),
			attacker_is_foe, float(power), power >= combat.HEAVY_HIT_DAMAGE, ranged)
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
	# THE BLOW LANDS SOMEWHERE. The host crosses the attacker->defender segment with
	# the defender's rect so the spark erupts at the struck EDGE rather than out of
	# the middle of the painting; the client drew from the centre, which is the one
	# surface ★4's spatter was reverted for touching.
	if striker != null and is_instance_valid(striker):
		combat._spawn_impact_burst(combat._strike_contact_point(striker, victim),
			combat._card_center(victim) - combat._card_center(striker), float(power), lethal)
	if dmg > 0:
		combat.spawn_floating_number(combat._card_center(victim), "-%d" % dmg, Color(0.95, 0.38, 0.38), false)
	if not lethal:
		# Survivor contract: _flash_hit owns the red punch AND the "hit_creature" cue.
		if dmg > 0 and victim.has_method("_flash_hit"):
			victim._flash_hit()
	else:
		# Kill contract: the cue sounds at the impact beat; the corpse slumps and
		# stands until the trailing snapshot flushes it — the deferred-deaths feel.
		victim.death_cue_played = true
		AudioBank.play_sfx("creature_death", 0.05)
		if victim.has_method("_mark_mortally_struck"):
			victim._mark_mortally_struck()
		combat.screen_shake(6.0)
	if punctuate:
		await _net_strike_punctuation(s)




## THE WORLD STOPS, then breathes — the strike punctuation, run on the watcher's own
## clock from the host's logged blow.
##
## This path was still on the flat HITSTOP_BEAT / POST_HIT_BEAT pair that predates the
## 2026-07-31 rework, so a skirmish client got no freeze at all AND a differently
## weighted clash than the host watching the same strike: a chip blow held 130 ms
## against the host's 70, a heavy one 260 against 200, a kill 260 against 280.
##
## The freeze goes on BOTH bodies for the reason it does host-side: on the attacker
## alone it reads as a stutter, on the defender alone as a hitch — the WORLD stopping
## is what reads as impact. It PAUSES the running tweens rather than adding a second
## writer on `position`, which is what lets a body that died mid-lunge hold its pose
## instead of snapping home. `_strike_stop` / `_strike_read` are the host's own
## helpers, run here against the local Motion.time and anim_speed: the same "the
## decision crosses the wire, the clock belongs to whoever is reading the screen"
## rule the lane dwell follows.
func _net_strike_punctuation(s: Dictionary) -> void:
	var victim = NetMatch.get_entity(int(s.get("d", -1)))
	var striker = NetMatch.get_entity(int(s.get("a", -1)))
	var power: int = int(s.get("p", maxi(int(s.get("n", 0)), 1)))
	var lethal: bool = int(s.get("hp", 1)) <= 0
	var stop: float = combat._strike_stop(power, lethal)
	if stop > 0.0:
		for body in [striker, victim]:
			if body != null and is_instance_valid(body) and body.has_method("hold_strike_frame"):
				body.hold_strike_frame(stop)
		await combat._short_pause(stop)
	await combat._short_pause(combat._strike_read(power, lethal))




## CLIENT: redraw a piercing kill's lance from the host's log. Both entities are still
## alive on the board here (the victim is mortally struck but not flushed until the
## trailing snapshot), so the client reconstructs the same skewer + spark from its own
## card centres — the world coords the host drew at are meaningless on a mirrored board.
func _net_replay_pierce(attacker_eid: int, victim_eid: int,
		recv_eid: int = -1, face_owner: int = -1, is_pierce: bool = true) -> void:
	var attacker = NetMatch.get_entity(attacker_eid)
	var victim = NetMatch.get_entity(victim_eid)
	if attacker == null or not is_instance_valid(attacker) \
			or victim == null or not is_instance_valid(victim):
		return
	var a = combat._card_center(attacker)
	var v = combat._card_center(victim)
	var lance_dir = v - a
	if lance_dir.length() <= 1.0:
		return
	# The mark runs FROM the slain body onward — a consequence, not a reach. WHERE it
	# ends is the host's ruling, carried in the entry (see _net_log_pierce); the
	# client only looks the terminus up. It used to re-derive it and got it wrong in
	# every reach_face case.
	var recv: Control = null
	if recv_eid >= 0:
		var node = NetMatch.get_entity(recv_eid)
		if node != null and is_instance_valid(node):
			recv = node
	var beyond := Vector2.ZERO
	if recv != null:
		beyond = combat._card_center(recv)
	elif face_owner >= 0:
		# Same owner→plate mapping the face-hit replay uses, so a mirrored board
		# resolves to the correct hero on either peer.
		var mine: bool = face_owner == NetMatch.local_player_index
		var plate: Label = combat._player_hp_label if mine else combat._enemy_hp_label
		if plate == null or not is_instance_valid(plate):
			return
		beyond = plate.get_global_rect().get_center()
	else:
		# Nothing carried (or a host too old to say). Draw nothing — the host draws
		# nothing here too, and a stub into bare table taught that something had
		# carried when nothing had.
		return
	combat._play_rubric_stroke(victim, beyond, recv, is_pierce)
	combat.spawn_ash_burst(beyond, Color(1.0, 0.86, 0.46), 14)


## (`_pierce_body_behind` lived here until 2026-07-30. It let the client work out
## the spill target off its own board, which is exactly the re-derivation that made
## the two peers draw different marks for one blow. The receiver now rides the clash
## log — see _net_log_pierce — and there is deliberately no local fallback: a client
## that cannot name the terminus draws nothing rather than guessing.)




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
	var killer: Control = null
	if dmg > 0 and s.has("a"):
		var striker = NetMatch.get_entity(int(s.get("a", -1)))
		if striker != null and is_instance_valid(striker):
			killer = striker
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
			combat._log_event("The enemy takes [color=#f2e6c8]%d[/color] — [color=#e06a50]%d[/color] left." \
				% [dmg, maxi(hp_after, 0)])
	combat._update_hud()
	# ★8 — THE BLOW THAT ENDED IT. The host freezes its killer at full extension the
	# instant the damage lands (see _net_killing_blow_held); the watcher, replaying
	# that same blow, takes the same hold here rather than reading it as one more chip
	# hit and meeting the verdict a whole reel later.
	#
	# Deliberately the HOLD only — the ceremony (_play_killing_blow_moment: the music
	# duck, the colour drain, the heavy shake) still rides the backlogged EV_MATCH_OVER
	# through _net_show_result, which is the one place that knows a DRAW from a win and
	# owns the Bo3 tally. Firing it here too would double it.
	if hp_after <= 0 and not combat._net_killing_blow_held:
		combat._net_killing_blow_held = true
		if killer != null and is_instance_valid(killer) and killer.has_method("hold_lunge_apex"):
			killer.hold_lunge_apex(combat.KILLING_BLOW_HOLD)
		await combat._short_pause(combat.KILLING_BLOW_HOLD)
		return
	# Paced like the host's face cascade (_creature_hits_face's tail), which weighs the
	# beat by the blow: _impact_hold ramps 150 -> 230 ms with the swing's size. The flat
	# HITSTOP_BEAT here was 260 ms for every hit, so a skirmish client watched an
	# unblocked line batter a hero on a metronome while the host watched it escalate.
	# The power the host measured already rides this entry as "p" (see
	# _net_arm_face_hit_source); "n" is only what the gate/boss actually lost.
	await combat._short_pause(combat._impact_hold(int(s.get("p", dmg)), false) \
		if dmg > 0 else combat.POST_HIT_BEAT)




## CLIENT: re-spawn the keyword callouts (POISON/THORNS/PIERCING) the host buffered
## into this snapshot, each on its own creature by entity_id. A callout whose creature
## died this sync has no anchor left — skipped; the death burst already shows the kill.
func _net_replay_fx(ev: Dictionary) -> void:
	for fx in ev.get("fx", []):
		if fx.has("trig"):
			continue   # trigger beats have their own pass — see _net_replay_trigger_fx
		_net_render_fx_chip(fx)




## Draw ONE mirrored callout. Shared by the snapshot's fx pass and the clash reel's
## `{kw}` entries (see _net_queue_fx_chip) so a chip looks the same whichever channel
## carried it — the mid-clash and post-clash paths cannot drift into two chips.
func _net_render_fx_chip(fx: Dictionary) -> void:
	var c: Array = fx.get("col", [1, 1, 1])
	var col := Color(float(c[0]), float(c[1]), float(c[2])) if c.size() >= 3 else Color(1, 1, 1)
	# A KEYSTONE RING off one body — the Alpha's howl, the Stampede's charge, the
	# Coven Mother's pulse. Position-anchored host-side, so only the eid can cross.
	if fx.has("ring"):
		var ring_body = NetMatch.get_entity(int(fx.get("ring", -1)))
		if ring_body != null and is_instance_valid(ring_body):
			combat._draw_keystone_ring(combat._card_center(ring_body), col,
				float(fx.get("rad", 30.0)), int(fx.get("z", 218)),
				bool(fx.get("plain", false)))
		return
	# THE REAP'S WISP — slot-anchored at both ends (the corpse is swept by this very
	# snapshot, so an eid origin would be gone). Side inverts: the host wrote it from
	# its board, ours is the mirror.
	if fx.has("wisp"):
		var w: Array = fx.get("wisp", [])
		if w.size() >= 5:
			combat._draw_slot_wisp(int(w[0]) == 0, int(w[1]), int(w[2]),
				int(w[3]), int(w[4]), col)
		return
	# A KEYSTONE WAVE — see Combat.grace_wave_over. The host names the bodies it swept;
	# we rebuild the points off OUR board, because the host's screen coordinates
	# describe a board that is our mirror. Sorted here too, so the glint runs
	# left-to-right for both readers (the board mirrors front-to-back, never sideways).
	if fx.has("wave"):
		var pts: Array = []
		for raw_eid in fx.get("wave", []):
			var body = NetMatch.get_entity(int(raw_eid))
			if body != null and is_instance_valid(body):
				pts.append(combat._card_center(body))
		if pts.is_empty():
			return
		pts.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		combat._trigger_fx_grace_wave(pts, col)
		return
	var node = NetMatch.get_entity(int(fx.get("eid", -1)))
	if node == null or not is_instance_valid(node):
		return
	var anchor: Vector2 = node.global_position + Vector2(
		node.size.x * node.scale.x * 0.5, node.size.y * node.scale.y * 0.06)
	# Battle log — mirror the host's status line (the host logs these via
	# spawn_keyword_callout_kw → log_status; the client re-plays them here).
	combat.log_status(node, String(fx.get("label", "")))
	# The device rides the entry now (`icon` = the keyword-icon alias the host
	# looked up), so every mirrored chip carries the same silhouette its twin does.
	# Older peers send no alias; a null texture just yields the bare word, which is
	# what this path did for everything but Last Stand before 2026-08-04.
	var icon_tex: Texture2D = null
	var icon_id := String(fx.get("icon", ""))
	if icon_id != "":
		icon_tex = GameTheme.get_keyword_icon(icon_id)
	# Last Stand also flares the surviving card itself — the chip alone reads as a
	# label on a body that visibly should have died.
	if String(fx.get("label", "")) == "LAST STAND":
		if icon_tex == null:
			icon_tex = GameTheme.get_keyword_icon("last_stand")
		combat.spawn_keyword_callout(anchor, "LAST STAND", col, icon_tex)
		if node.has_method("_play_last_stand_flare"):
			node._play_last_stand_flare()
		return
	combat.spawn_keyword_callout(anchor, String(fx.get("label", "")), col, icon_tex)




## CLIENT: play the creature-trigger beats (battlecry / deathrattle / on-play) the
## host fired while resolving this snapshot — the ring off the body, the tracer to
## what it struck, the grace wave over what it helped.
##
## Split into two passes around the reconcile because the two channels have opposite
## anchoring needs, and getting this wrong is how the beat would silently vanish:
##
##   • "death" runs BEFORE the despawn loop, while the dying body is still standing.
##     Its FX radiate out of a seat that is about to be empty; after the loop there
##     is no node to read a position from.
##   • "enter" / "play" run AFTER the reconcile, so a creature that ARRIVED in this
##     very snapshot already exists to announce from.
##
## The effect dict comes back out of the local node's own card_data — the wire
## carries the eid and the channel and nothing else, so a battlecry cannot describe
## itself differently on the two machines.
func _net_replay_trigger_fx(ev: Dictionary, only_channel: String) -> void:
	for fx in ev.get("fx", []):
		if String(fx.get("trig", "")) != only_channel:
			continue
		var node = NetMatch.get_entity(int(fx.get("eid", -1)))
		if node == null or not is_instance_valid(node):
			continue
		var key := "on_enter"
		if only_channel == "death":
			key = "on_death"
		elif only_channel == "play":
			key = "on_play"
		var effect: Dictionary = node.card_data.get(key, {})
		if effect.is_empty():
			continue
		# The on-play channel's announce is the card's own floop pulse (the funnel
		# deliberately skips its ring there) — without it the client would get the
		# delivery with nothing to say which body sent it.
		if only_channel == "play" and node.has_method("play_floop_pulse"):
			node.play_floop_pulse()
		combat._play_trigger_fx(effect, node, int(node.current_lane),
			bool(node.is_opponent), only_channel, Vector2.ZERO, int(node.current_row))


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
	if cd.get("state", null) is Dictionary:
		data["state"] = cd["state"]
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




## CLIENT: apply the host's versioned runtime state and pop a one-shot chip when
## freeze or stun newly turns on. The short keys remain as a compatibility path for
## peers from before the typed-state snapshot was introduced.
func _net_apply_creature_states(node: Control, cd: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	var was_frozen: bool = node.state.is_frozen
	var was_stunned: bool = node.state.stunned
	var runtime = cd.get("state", null)
	if runtime is Dictionary:
		node.state.apply_snapshot(runtime)
	else:
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
		if exiled:
			# Banish reads as BANISH on both screens (2026-08-04). This used to play
			# an ash burst and an 0.18 s fade — and ash is this game's word for DEATH,
			# which is precisely what `_play_banish_exit`'s own header says a banish is
			# not ("not a death (no ash, no On-Death)"). So the client was told the
			# wrong thing about the removal it was watching. The authored exit — the
			# token spiralling small into a contracting pale ring — is safe to call
			# here because the row arrays are already cleared above, which is the
			# precondition it states.
			combat._play_banish_exit(node)
			return
		var cue_already_played: bool = bool(node.death_cue_played)
		node.death_cue_played = true
		if not cue_already_played and AudioBank != null:
			AudioBank.play_sfx("creature_death", 0.05)
			combat.screen_shake(5.0)
		if node.has_method("_mark_mortally_struck"):
			node._mark_mortally_struck()
		combat._play_creature_death_vfx(node, bool(node.is_opponent))
		# THE WRIT BURNS HERE TOO (2026-08-04). This used to hand-roll a
		# shrink-spin-fade — which was a verbatim copy of `_die`'s FALLBACK, i.e. the
		# exact animation `_play_burn_death` was written to replace. So on a skirmish
		# CLIENT every death played the retired generic beat while the host's screen
		# burned the parchment: two players in one match watching different deaths, in
		# the game whose whole identity is paper and ink. It also skipped the death
		# burst and never stopped the clash tweens, which are still writing `position`
		# on a body that died mid-lunge (most of them do).
		#
		# `play_death_flourish` is the visual half of `_die`, split out for exactly
		# this call site. NOT `try_die`/`_die`: those emit `destroyed`, which runs
		# on-death dispatch and the encounter / ally-death hooks — and a client must
		# never resolve any of that. The host already did; we render its outcome.
		node.play_death_flourish()




## Materialize a board creature from card data on a given side. On the host
## (run_on_enter=true) the on-enter fires authoritatively; on the client it never
## does (the client only renders the snapshot the host already resolved).
## BOUNDS AT THE CHOKEPOINT (2026-08-04). Two of the three production callers already
## validate lane/row before arriving here (`_sealed_reveal`, `_net_apply_remote_creature`,
## which additionally `_net_reject_remote`s a bad one) — but `_net_apply_board_sync` reads
## them straight out of the snapshot and does not, so a host that shipped an out-of-range
## seat took the CLIENT down on `_row_array(...)[lane]` instead of dropping one body.
##
## The host is authoritative and therefore trusted, so this is not a security control;
## it is the difference between a peer's bug degrading and a peer's bug crashing you.
## Guarding here rather than at the third call site covers every future caller too.
## Returning null is safe: no production caller reads the result.
func _net_spawn_creature(data: Dictionary, entity_id: int, lane: int, row: int,
		is_enemy_side: bool, run_on_enter: bool) -> Control:
	if lane < 0 or lane >= combat.LANES_PER_ROW \
			or row < combat.ROW_FRONT or row > combat.ROW_BACK:
		push_warning("[net] spawn dropped — seat out of range (lane %d, row %d)" % [lane, row])
		return null
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
			combat._log_event("The enemy fields %s." % combat._log_card_ref(card),
				combat._log_data(card), combat._log_side(card))
		else:
			combat._log_event("You field %s." % combat._log_card_ref(card),
				combat._log_data(card), combat._log_side(card))
	if run_on_enter:
		KeywordEffects.dispatch_on_enter(card, lane, is_enemy_side, combat)
		if card.card_data.has("on_play"):
			combat._resolve_on_play_ability(card, lane, is_enemy_side)
		combat._maybe_beast_encore(card, is_enemy_side)   # Bloodmoon Alpha doubles a Beast's arrival
		combat._maybe_stampede(card, is_enemy_side)      # The Dire Alpha charges the pack in
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
	if _wire_str(intent.get("t", "")) == NetMatch.IN_REMATCH:
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
	match _wire_str(intent.get("t", "")):
		NetMatch.IN_PLAY_CREATURE:
			if _is_sealed() and not SkirmishState.vs_bot:
				_net_reject_remote("creature_outside_orders")
				return
			# animate=true — a human opponent's play arcs from the foe's hand fan,
			# the same ceremony the bot already had. The ghost bails headless, so
			# probe-driven intents resume synchronously.
			await _net_apply_remote_creature(intent, true)
		NetMatch.IN_PLAY_SPELL:
			_net_apply_remote_spell(intent)
		NetMatch.IN_REPOSITION:
			if _is_sealed():
				_net_reject_remote("move_not_allowed_in_sealed")
				return
			_net_apply_remote_reposition(intent)
		NetMatch.IN_SNIPER_AIM:
			if _is_sealed():
				_net_reject_remote("aim_not_allowed_in_sealed")
				return
			_net_apply_remote_sniper_aim(intent)
		NetMatch.IN_USE_POTION:
			if _is_sealed() and combat._sorcery_active != 1:
				_net_reject_remote("potion_outside_sorcery")
				return
			var pid := _wire_str(intent.get("pid", ""))
			var potion_data := PotionDB.get_potion(pid)
			if combat._net_active_index != 1 or _remote_state == null \
					or potion_data.is_empty() or not _remote_state.potions.has(pid):
				_net_reject_remote("illegal_potion")
				return
			var pot_target: Control = null
			var pot_eid: int = _wire_int(intent.get("target", -1), -1)
			if pot_eid >= 0:
				var pn = NetMatch.get_entity(pot_eid)
				if pn != null and is_instance_valid(pn) and pn is Control:
					pot_target = pn
			var targeting := String(potion_data.get("targeting", "none"))
			var target_ok := targeting == "none" and pot_target == null
			if targeting == "friendly_creature":
				target_ok = pot_target != null and bool(pot_target.is_opponent) \
					and pot_target.is_creature() and not pot_target.has_keyword("structure")
			elif targeting == "enemy_creature":
				target_ok = pot_target != null and not bool(pot_target.is_opponent) \
					and pot_target.is_creature() and not pot_target.has_keyword("structure")
			elif targeting in ["any_creature", "any"]:
				target_ok = pot_target != null and pot_target.is_creature() \
					and not pot_target.has_keyword("structure")
			if not target_ok or not _remote_state.consume_potion(pid):
				_net_reject_remote("illegal_potion_target")
				return
			var effect := String(potion_data.get("effect", ""))
			if effect == "gain_mana":
				_remote_state.gain_mana(2)
			elif effect == "draw":
				_remote_state.draw_cards(3)
			elif effect == "sacrifice_for_command":
				_remote_state.gain_mana(3)
			if _net_potion_needs_host(effect):
				_net_apply_host_potion(pid, true, pot_target)
			elif effect not in ["gain_mana", "draw"]:
				_net_reject_remote("unsupported_potion")
				return
			_net_show_foe_potion_fx(pid)
			_net_send_private_state()
			_net_sync_board()
		NetMatch.IN_ORDER_PICK:
			# The client won the toss — its settled order binds the host too.
			var settled := _wire_int(intent.get("first", -1), -1)
			if combat._net_first_player_override < 0 and combat._net_first_player() == 1 \
					and settled in [0, 1]:
				combat._net_first_player_override = settled
		NetMatch.IN_END_ACTIONS:
			if _is_sealed():
				_net_reject_remote("alternating_commit_in_sealed")
				return
			if combat._net_active_index == 1:
				var discard_result: Dictionary = _remote_state.discard_cards(intent.get("discards", [])) \
					if _remote_state != null else {"ok": false, "reason": "authority_unavailable"}
				if not bool(discard_result.get("ok", false)):
					_net_reject_remote(String(discard_result.get("reason", "illegal_discard")))
					return
				var discard_count := int(discard_result.get("count", 0))
				if discard_count > 0:
					_net_show_foe_discard_fx(discard_count)
				_remote_state.end_turn()
				_net_send_private_state()
				_net_finish_placement(1)
		NetMatch.IN_CHOICE:
			# The client picked an option for its own Copycat / Adaptable — apply + sync.
			_net_apply_client_choice(intent)
		NetMatch.IN_ORDERS:
			# Sealed style: the client's whole creature bundle. Awaited so the
			# reveal (once both bundles are in) sequences ahead of queued intents.
			await _sealed_store_bundle(1, intent.get("list", []), 0,
				intent.get("discards", []))
		NetMatch.IN_ORDER_GHOST:
			_sealed_accept_remote_ghost(_wire_int(intent.get("lane", -1), -1),
				_wire_int(intent.get("row", 0), 0))
		NetMatch.IN_SORCERY_PASS:
			if not _is_sealed() or combat._sorcery_active != 1:
				_net_reject_remote("sorcery_phase_closed")
				return
			var pass_discards: Dictionary = _remote_state.discard_cards(intent.get("discards", [])) \
				if _remote_state != null else {"ok": false, "reason": "authority_unavailable"}
			if not bool(pass_discards.get("ok", false)):
				_net_reject_remote(String(pass_discards.get("reason", "illegal_discard")))
				return
			_remote_state.end_turn()
			_net_send_private_state()
			_sealed_sorcery_pass(1)
		NetMatch.EV_HAND_COUNT:
			if _remote_state != null:
				combat._net_opp_hand_count = _remote_state.hand.size()
				_net_refresh_opp_hand()
				_net_set_opp_mana(_remote_state.mana, _remote_state.max_mana)
		NetMatch.EV_DISCARD_FX:
			# The client threw cards away at its turn commit — show the beat.
			pass
		NetMatch.EV_POTION_FX:
			# The client drank a potion — show the drink beat over its portrait.
			pass
		NetMatch.EV_RELIC_FX:
			# The client's resource relic paid out on its machine — pulse its
			# chip on our foe-arsenal rail (HS trinket beat).
			_net_on_relic_fx(intent)
		NetMatch.EV_EMOTE:
			# The client sent an emote — float their line over the enemy plate.
			combat._net_show_foe_emote(_wire_int(intent.get("idx", -1), -1))
		_:
			_net_reject_remote("unknown_intent")




## HOST: seat the client's creature on the host's ENEMY side, run its on-enter
## authoritatively, then snapshot the new board to the client.
func _net_apply_remote_creature(intent: Dictionary, animate: bool = false) -> void:
	if _is_sealed() and not SkirmishState.vs_bot:
		_net_reject_remote("creature_outside_orders")
		return
	if combat._net_active_index != 1:
		if not SkirmishState.vs_bot:
			_net_reject_remote("not_your_turn")
		return   # not the client's turn
	var lane: int = _wire_int(intent.get("lane", -1), -1)
	var row: int = _wire_int(intent.get("row", combat.ROW_FRONT), combat.ROW_FRONT)
	if lane < 0 or lane >= combat.LANES_PER_ROW or row < combat.ROW_FRONT or row > combat.ROW_BACK:
		return
	if combat._row_array(true, row)[lane] != null:
		if not SkirmishState.vs_bot:
			_net_reject_remote("slot_occupied")
		return   # slot occupied — drop the play (client mis-synced)
	var data := SkirmishState.skirmish_card_data(_wire_str(intent.get("id", "")))
	if data.is_empty() or String(data.get("type", "")) != "creature":
		if not SkirmishState.vs_bot:
			_net_reject_remote("card_not_creature")
		return
	var uid: int = _wire_int(intent.get("uid", -1), -1)
	var authority_check: Dictionary = {}
	if not SkirmishState.vs_bot:
		if _remote_state == null:
			_net_reject_remote("authority_unavailable")
			return
		authority_check = _remote_state.validate_play(uid, _wire_str(intent.get("id", "")),
			_net_remote_has_first_spell_discount())
		if not bool(authority_check.get("ok", false)):
			_net_reject_remote(String(authority_check.get("reason", "illegal_play")))
			return
	if animate:
		# Foe play (bot or human opponent): throw the card from the foe's hand
		# into the slot before seating it.
		await _bot_animate_creature_play(data, lane, row)
		# The throw awaited a few frames — re-validate the turn/slot before committing.
		if combat._net_match_over or combat._net_active_index != 1:
			return
		if combat._row_array(true, row)[lane] != null:
			return
	if not SkirmishState.vs_bot:
		if _remote_state.commit_play(authority_check, true).is_empty():
			_net_reject_remote("play_commit_failed")
			return
	combat._net_cards_played[1] += 1   # client's per-side card tally (Ironclad Veteran), pre-spawn
	# The client stamps its unspent Command (post-payment) on the intent so
	# play-time passives that scale off the caster's pool (Condottiere) read the
	# CLIENT's pool, not the host's. Bot intents omit it → 0 (vanilla body).
	combat._net_client_unspent_mana = _wire_int(intent.get("mana", 0), 0) if SkirmishState.vs_bot \
		else _remote_state.mana
	_net_spawn_creature(data, uid, lane, row, true, true)
	if not SkirmishState.vs_bot:
		_net_send_private_state()
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
	var free_move: bool = combat._has_free_move_available(card)
	if combat._moves_used_this_turn >= combat.MOVES_PER_TURN and not free_move:
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
		if free_move:
			combat._consume_free_move(card)
			combat._apply_free_move_bonus(card)
		else:
			combat._moves_used_this_turn += 1
		combat._play_landing_pop(card)
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
		_net_sync_board()
	else:
		# Client predicts position and free-use state; the host snapshot confirms or rolls both back.
		if free_move:
			combat._consume_free_move(card)
		else:
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
		_net_sync_board()
		return
	var dest_lane: int = _wire_int(intent.get("lane", -1), -1)
	var dest_row: int = _wire_int(intent.get("row", combat.ROW_FRONT), combat.ROW_FRONT)
	if dest_lane < 0 or dest_lane >= combat.LANES_PER_ROW or dest_row < combat.ROW_FRONT or dest_row > combat.ROW_BACK:
		_net_sync_board()
		return
	var node = NetMatch.get_entity(_wire_int(intent.get("eid", -1), -1))
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		_net_sync_board()
		return
	var free_move: bool = combat._has_free_move_available(node)
	if combat._moves_used_this_turn >= combat.MOVES_PER_TURN and not free_move:
		_net_sync_board()
		return
	if combat._row_array(true, dest_row)[dest_lane] != null:
		_net_sync_board()
		return
	var src_row: int = node.current_row
	var src_lane: int = node.current_lane
	if dest_row == src_row and dest_lane == src_lane:
		_net_sync_board()
		return
	combat._row_array(true, src_row)[src_lane] = null
	node.current_row = dest_row
	node.current_lane = dest_lane
	combat._reset_card_after_drag(node)
	combat._slot_set_card(combat._slot_array(true, dest_row)[dest_lane], node)
	combat._row_array(true, dest_row)[dest_lane] = node
	if free_move:
		combat._consume_free_move(node)
		combat._apply_free_move_bonus(node)
	else:
		combat._moves_used_this_turn += 1
	combat._play_landing_pop(node)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_net_sync_board()


# ── Take Aim over the wire (2026-07-21 sniper rework) ───────────────────────
# The HOST's _sniper_marks is authoritative for the clash. Each peer aims only
# its OWN snipers: the host writes directly; the client sets a local mark for
# its thread/telegraph and ships an IN_SNIPER_AIM intent. A foe's order is
# NEVER surfaced on your screen (applied silently, no thread, no log) — the
# same information rule as the hidden hand. Sealed style seals aim too: the
# drill fires unaimed there, matching its no-reposition rule.

func _net_sniper_aim_dropped(card: Control, quarry: Control) -> void:
	var active_local: bool = combat._net_active_index == NetMatch.local_player_index
	if not active_local or combat.phase != combat.Phase.PLAYER_TURN or combat._net_match_over:
		# The sealed branch below explains itself and this one did not, so the same
		# gesture was answered with a sentence in one style and a silent snap-back
		# in the other. The caller restores the card either way, so this was never
		# a stranded marksman — just an unexplained one.
		if not combat._net_match_over and combat.phase == combat.Phase.PLAYER_TURN:
			combat._show_info("Not your turn.")
		return
	if _is_sealed():
		combat._show_info("Sealed orders — no aiming.")
		return
	combat._set_sniper_mark(card, quarry)
	if not combat._is_host():
		NetMatch.send_intent({
			"t": NetMatch.IN_SNIPER_AIM, "eid": int(card.entity_id),
			"tgt": int(quarry.entity_id),
		})


func _net_sniper_aim_clear(card: Control) -> void:
	var active_local: bool = combat._net_active_index == NetMatch.local_player_index
	if not active_local or combat.phase != combat.Phase.PLAYER_TURN or combat._net_match_over:
		return
	combat._clear_sniper_mark(card)
	if not combat._is_host():
		NetMatch.send_intent({
			"t": NetMatch.IN_SNIPER_AIM, "eid": int(card.entity_id), "tgt": -1,
		})


## HOST: validate + apply the client's aim order (its snipers sit on the host's
## ENEMY side, its quarry on the host side). Silent — the order is hidden intel.
func _net_apply_remote_sniper_aim(intent: Dictionary) -> void:
	if combat._net_active_index != 1:
		return   # not the client's turn
	var node = NetMatch.get_entity(_wire_int(intent.get("eid", -1), -1))
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		return   # unknown entity or not the client's own creature
	if not combat._is_sniper(node, true, int(node.current_row)):
		return
	var tgt_id: int = _wire_int(intent.get("tgt", -1), -1)
	if tgt_id < 0:
		combat._clear_sniper_mark(node, false)
		return
	var quarry = NetMatch.get_entity(tgt_id)
	if quarry == null or not is_instance_valid(quarry) or quarry.is_opponent \
			or quarry.current_hp <= 0:
		return   # quarry must be a living host-side creature
	combat._set_sniper_mark(node, quarry, false)




# ─────────────────────────────────────────────────────────────────────────
#  PRACTICE BOT — drives slot 1 in a vs-bot match (SkirmishState.vs_bot).
#  The bot stands in for an absent client: it keeps its own hand drawn from slot
#  1's deck and a flat Command budget (3 + bank 2), asks SkirmishBot for an
#  ordered list of plays, applies each through the SAME host intent path a remote
#  client would hit, then ends actions (which resolves its strike + passes turn).
# ─────────────────────────────────────────────────────────────────────────

func _bot_refill_hand() -> void:
	var slot: SkirmishState.PlayerSlot = SkirmishState.get_slot(1)
	if slot == null or slot.deck.is_empty():
		return   # no deck to draw from — and the loop below must never spin on one
	# The bot refills to the standard target. Its going-second compensation is the
	# Coin — a one-time +1 Command on its opening turn (granted in _bot_take_turn),
	# mirroring the human's Coin card rather than the old raw extra card.
	var target: int = combat.HAND_REFILL_TARGET
	while combat._bot_hand.size() < target:
		# THE BOT USED TO DECK OUT AND NEVER COME BACK. This cursor only ever walked
		# forward through 20 cards, with no wrap and no reshuffle — while BOTH of the
		# other draw paths recycle their discard when the pile runs dry
		# (`Combat.draw_one` reshuffles and plays the pile VFX; `NetPlayerState.draw_one`
		# does the same for a real client). So a drill that ran past roughly turn eight
		# hit the end of the list, the hand drained, and the bot stopped fielding
		# anything at all for the rest of the match. It reads exactly like the AI giving
		# up, and the longer the game the more certain it was.
		if combat._bot_deck_cursor >= slot.deck.size():
			combat._bot_deck_cursor = 0
			combat._bot_deck_recycled = true
		var id = String(slot.deck[combat._bot_deck_cursor])
		# FRESH IDS ON EVERY LAP AFTER THE FIRST. `entity_id == deck uid` for drafted
		# creatures, so handing out a second-lap card under its original uid would
		# collide in `NetMatch.register_entity` with the first copy if that one is still
		# standing. `_net_issue_token_id` is the existing "above any uid" allocator the
		# summon path already uses for exactly this reason.
		var uid: int
		if combat._bot_deck_recycled or combat._bot_deck_cursor >= slot.deck_uids.size():
			uid = _net_issue_token_id()
		else:
			uid = int(slot.deck_uids[combat._bot_deck_cursor])
		combat._bot_hand.append({"uid": uid, "id": id, "data": SkirmishState.skirmish_card_data(id)})
		combat._bot_deck_cursor += 1




## How much Command the practice bot may carry between its turns.
##
## 2026-09-16: zero for everybody without the carryover relic, and the bot's
## drafted arsenal comes off BOT_RELIC_POOL, which does not contain it — so this
## is 0 today and will follow the pool if that ever changes, instead of being a
## flat literal somebody has to remember to revisit. Reads the SLOT (what it
## actually drafted) rather than the pool (what it could have), because a cap
## derived from what a side might hold is not a cap on what it does hold.
func _bot_bank_cap() -> int:
	var slot = SkirmishState.get_slot(SkirmishState.opponent_index())
	if slot == null:
		return 0
	return combat.bank_cap_for(slot.relics)


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
		spent += _bot_consume_card(_wire_int(intent.get("uid", -1), -1))
		# Drop the card from the visible fan BEFORE the play animates, so the throw
		# reads as that card leaving the hand (not a phantom extra).
		_bot_sync_hand_display(mana - spent)
		await _bot_apply_intent(intent)
	combat._bot_banked_mana = clampi(mana - spent, 0, _bot_bank_cap())
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
	match _wire_str(intent.get("t", "")):
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

	# Motion.time() so the tween and the wait below scale TOGETHER (2026-08-03).
	# This was a bare 0.42 while the wait was `_short_pause(0.42)`, which applies
	# the anim-speed scale itself — so at any speed above 1x the ghost was freed
	# partway through its own flight and the foe's card vanished in mid-air.
	# The wait stays `_short_pause` rather than a bare timer on purpose: it also
	# carries the hold-to-rush divisor, and a player holding ui_accept IS asking
	# to cut this short, so an early free is correct on that path only.
	var duration := Motion.time(0.42)
	# Bow the path downward — the foe reaches up out of its hand and sets the card down.
	# Left un-derived: unlike the player's own play, this origin is genuinely the
	# far corner of the screen, so `reach` would pin near 1.0 and the bow is honest.
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
	# Capped against the flight itself: at Instant the whole trip is shorter than a
	# fixed 0.12 fade, which left the ghost freed while still half transparent.
	tw.tween_property(ghost, "modulate:a", 1.0, minf(Motion.time(0.12), duration * 0.45))
	tw.tween_property(ghost, "rotation", 0.0, duration).from(randf_range(-0.12, 0.12)) \
		.set_ease(Tween.EASE_OUT)
	# Gate on a real timer (NOT tw.finished) so the bot's turn can never stall on a
	# tween — the tween only drives the cosmetics in parallel; the timer is the clock.
	await combat._short_pause(duration)
	if is_instance_valid(ghost):
		ghost.queue_free()
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	# A RULES-BEARING BODY GETS READ, NOT GLIMPSED (2026-08-04).
	#
	# Skirmish already reveals the foe's SPELLS readably — `_net_spell_telegraph`
	# holds the real face center-screen under "OPPONENT CASTS", because "what did
	# they just play?" is the question. Their CREATURES got only this 420 ms fly-by
	# at 132px, which is not long enough or large enough to read a battlecry off,
	# so the foe's whole kit arrived as anonymous stat blocks and then did things
	# nothing on screen had accounted for.
	#
	# Solo hit the identical problem from the other side and answered it with
	# `_announce_enemy_muster`; this reuses its two decisions rather than inventing
	# new ones — the SAME `_card_has_hidden_rules` filter (a plain 3/2 says nothing,
	# so it buys no reveal) and the same `_reveal_cast_card` overlay, which is
	# click-through and never gates the turn. Not awaited: the seat must not wait on
	# presentation, and the host has already validated the play by this point.
	if combat._card_has_hidden_rules(data):
		combat._reveal_cast_card(data, "OPPONENT PLAYS", Color(0.96, 0.56, 0.34))




## CLIENT: a cosmetic ghost of the client's OWN creature play, arcing from the drop
## point to the destination slot. The real creature still arrives via the host snapshot
## (the client never seats locally), so this only bridges the visual gap the HOST gets
## for free from its local seat — without it, a Player-2 creature just pops into the
## slot. Fire-and-forget: it never gates the intent (sent before this is called).
##
## THE FLIGHT IS MEASURED, NOT FIXED (2026-08-03). This shipped at a flat 0.34 s over a
## flat 64 px bow, neither of them through Motion.time() — the same flatness the solo
## path was just cured of, and worse here: `origin` is the DROP POINT (the client branch
## of _on_card_played captures it off the dragged hand card, exactly as the solo branch
## captures play_start_global), so the usual travel is about a slot-width, and a 64 px
## lift over ~40 px of ground is not an arc, it is a loop back over the gesture the
## player just made. It now reads Combat's ONE set of arc constants (ARC_FULL_TRAVEL /
## ARC_MAX_LIFT / ARC_MIN_TIME / ARC_MAX_TIME) off the ctx rather than keeping copies —
## a duplicated 78.0 is precisely how these two paths drifted apart in the first place —
## so retuning the campaign's card-play arc retunes the skirmish's with it, and a player
## crossing between the two cannot tell the flights apart.
func _client_animate_own_play(data: Dictionary, lane: int, row: int, origin: Vector2) -> void:
	# Bail BEFORE any allocation or await. Headless: probe-driven plays must not build a
	# TextureRect or suspend (the rule _bot_animate_creature_play already follows).
	# Reduce Motion: this ghost is DECORATIVE by definition — the information is the
	# creature reaching the slot, and the host's snapshot delivers that either way — so
	# it gates off at the same beat _play_landing_pop drops its arc, and a Reduce Motion
	# player is shown the same flightless play in skirmish as in the campaign.
	if DisplayServer.get_name() == "headless" \
			or (UserSettings != null and UserSettings.reduce_motion):
		return
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
	# Hand size → board-token footprint. This pair is deliberately NOT reach-derived:
	# the card the player was dragging one frame ago really was hand-sized and the slot
	# really is smaller, and that is equally true of a seat and of a long deal. Only the
	# things that describe the FLIGHT — hang time, apex, spin — scale with travel.
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
	# How much of a flight this actually IS, 0..1 — Combat's reach model, read through
	# the ctx the same way this file already reads combat.LANES_PER_ROW. Everything the
	# arc does scales off this one number, so a short seat can never pick up a long
	# deal's hang time, apex or spin.
	var reach: float = clampf(origin.distance_to(dest) / float(combat.ARC_FULL_TRAVEL),
		0.0, 1.0)
	var duration: float = Motion.time(lerpf(float(combat.ARC_MIN_TIME),
		float(combat.ARC_MAX_TIME), reach))
	# Bow the path UP toward the board — the player lifts the card from hand onto the line.
	var ctrl := origin.lerp(dest, 0.5) + Vector2(0, -float(combat.ARC_MAX_LIFT) * reach)
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
		if not is_instance_valid(ghost):
			return
		# THE HANDOFF (2026-08-03). Nothing synchronises this flight with the host and the
		# host does not wait for it: over a LAN the EV_BOARD_SYNC that seats the REAL card
		# lands well inside the ghost's own travel, and the ghost rides _hud_layer at
		# z 220, ABOVE the board. The player therefore watched the creature stamp into its
		# slot and then watched a second copy of it glide down on top of itself. The
		# instant the real body occupies the destination there is no gap left to bridge,
		# so the ghost hands off and goes. CUT, not faded: any fade is more duplicate
		# frames, and the real card's wax press is a loud enough beat to carry the eye by
		# itself. The lane is empty at t=0 by construction (Combat validated the drop and
		# nothing awaits between the intent send and this call), so a body here is always
		# the arrival this ghost was standing in for. queue_free() is deferred, so freeing
		# from inside the tween's own callback is safe — and the tween dies with its node,
		# which is exactly why the wait below must be a timer.
		var seated = combat._row_array(false, row)[lane]
		if seated != null and is_instance_valid(seated):
			if not ghost.is_queued_for_deletion():
				ghost.queue_free()
			return
		var p1 := origin.lerp(ctrl, t)
		var p2 := ctrl.lerp(dest, t)
		var sz: Vector2 = travel.lerp(land, t)
		ghost.size = sz
		ghost.pivot_offset = sz * 0.5   # keep the spin about the card's centre as it shrinks
		ghost.position = p1.lerp(p2, t) - sz * 0.5
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	# The fade-in is capped against the flight for the same reason the flight is derived:
	# a fixed 0.10 s over a 0.04 s Instant-speed flight left the ghost freed while still
	# half transparent — a flicker where a card-play should be.
	tw.tween_property(ghost, "modulate:a", 1.0, minf(Motion.time(0.10), duration * 0.45))
	# The same reach-scaled spin the solo arc takes, settling square as it lands.
	tw.tween_property(ghost, "rotation", 0.0, duration) \
		.from(randf_range(-0.07, 0.07) * reach).set_ease(Tween.EASE_OUT)
	# A REAL TIMER on a BARE duration. NOT combat._short_pause: `duration` is already
	# Motion.time()-scaled, and _short_pause scales it AGAIN and applies the hold-to-rush
	# divisor on top — which is the standing bug, the ghost being freed a third of the way
	# through its own flight at any speed above 1.0. NOT tw.finished either: a killed tween
	# never emits it, and the handoff above kills this one on purpose, so awaiting the
	# signal would park this coroutine forever holding a freed node.
	await combat.get_tree().create_timer(duration).timeout
	if is_instance_valid(ghost) and not ghost.is_queued_for_deletion():
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
	match _wire_str(event.get("t", "")):
		NetMatch.EV_ORDER_PICK:
			# The host settled the toss (its own pick, applied host-side already).
			# CLAMPED, to match its host-side twin (IN_ORDER_PICK, which checks
			# `settled in [0, 1]`). This side took the value raw, and it is not an
			# opaque flag: it becomes `_net_first_player()`, which feeds
			# `1 - attacking_side` into `_doubled_hour[...]` and `1 - initiative` into
			# the sealed reveal order. An out-of-range value is therefore a negative
			# array index on the WATCHER — a crash, not a wrong turn order.
			combat._net_first_player_override = clampi(_wire_int(event.get("first", 0), 0), 0, 1)
		NetMatch.EV_TURN_BEGIN:
			_net_client_turn_begin(_wire_int(event.get("active", 0), 0), _wire_int(event.get("round", 0), 0))
		NetMatch.EV_HAND_SET:
			_net_apply_private_state(event)
		NetMatch.EV_ORDERS_PHASE:
			combat._net_turn_round = _wire_int(event.get("round", 1), 1)
			# Clamped for the same reason EV_ORDER_PICK is: `_net_initiative` is not an
			# opaque flag. `_sealed_reveal` iterates `[initiative, 1 - initiative]` and
			# subscripts `_net_cards_played[side]`, which is size 2 — so an out-of-range
			# initiative is an array index error on the watcher mid-reveal.
			combat._net_initiative = clampi(_wire_int(event.get("init", 0), 0), 0, 1)
			_sealed_open_orders_local()
		NetMatch.EV_ORDER_GHOST:
			_sealed_show_ghost(_wire_int(event.get("lane", -1), -1), _wire_int(event.get("row", 0), 0))
		NetMatch.EV_REVEAL:
			combat.phase = combat.Phase.RESOLVING
			# WITH THE FLIP (2026-08-04). This passed no argument, so the watcher took
			# `_sealed_clear_pending_local`'s BOOKKEEPING path — the ghosts simply
			# blinked out — while the host played ★5's authored turn-over, the backs
			# going edge-on so the real cards open out of them. That function's own
			# header says the flip "belongs to the REVEAL only"; this IS the reveal, and
			# it was the one caller that had to pass it and didn't. Same shape as the
			# client death that hand-rolled `_die`'s fallback: the watcher got the error
			# path where the host got the ceremony.
			_sealed_clear_pending_local(true)
			combat._show_combat_banner("ORDERS REVEALED", "", Color(1.0, 0.78, 0.35))
			if AudioBank != null:
				AudioBank.play_sfx("card_play", 0.04, 2.0, 0.62)
		NetMatch.EV_SORCERY:
			_sealed_set_sorcery(_wire_int(event.get("who", 0), 0))
		NetMatch.EV_CLASH:
			# The host's per-strike clash log — replay it paced (lunges, blows,
			# numbers, kill cues). Fire-and-forget coroutine: everything that
			# arrives while it runs queues in the backlog and applies after.
			_net_replay_clash(event)
		NetMatch.EV_BOARD_SYNC:
			_net_apply_board_sync(event)
		NetMatch.EV_HAND_COUNT:
			combat._net_opp_hand_count = _wire_int(event.get("n", 0), 0)
			_net_refresh_opp_hand()
			_net_set_opp_mana(_wire_int(event.get("mana", combat._net_opp_mana), combat._net_opp_mana),
				_wire_int(event.get("maxmana", combat._net_opp_max_mana), combat._net_opp_max_mana))
		NetMatch.EV_DISCARD_FX:
			# The host threw cards away at its turn commit — show the beat.
			_net_show_foe_discard_fx(_wire_int(event.get("n", 0), 0))
		NetMatch.EV_POTION_FX:
			# The host drank a potion — show the drink beat over its portrait.
			_net_show_foe_potion_fx(_wire_str(event.get("pid", "")))
		NetMatch.EV_RELIC_FX:
			# A relic beat: theirs (mine=true → our foe rail) or OURS resolved
			# host-side (mine=false → our own grid pulses).
			_net_on_relic_fx(event)
		NetMatch.EV_EMOTE:
			# The host sent an emote — float their line over the enemy plate.
			combat._net_show_foe_emote(_wire_int(event.get("idx", -1), -1))
		NetMatch.EV_SPELL:
			# The host cast a spell — show its arrow + thrown card + target burst so we
			# see exactly what they pointed at (client casts are shown host-side).
			_net_on_opp_spell_event(event)
		NetMatch.EV_DRAW:
			# A spell we cast told us to draw from our own pile (host resolved it).
			# Bounded by the hand cap: this is a raw loop count off the wire, and
			# `draw_one` reshuffles the discard when the deck runs dry, so a bad `n`
			# does not terminate early — it spins. MAX_HAND_SIZE is the most any real
			# draw effect can profitably ask for (the rest would burn anyway).
			for _i in clampi(_wire_int(event.get("n", 0), 0), 0, combat.MAX_HAND_SIZE):
				combat.draw_one()
			combat._layout_hand()
			_net_broadcast_hand_count()
			combat._update_hud()
		NetMatch.EV_GIVE_CARD:
			# The host returned a specific card to our hand (Grave Robbery / Grave Pact).
			_net_give_card_local(_wire_str(event.get("id", "")), _wire_int(event.get("uid", -1), -1))
		NetMatch.EV_MANA:
			if bool(event.get("next", false)):
				# Compatibility path for a next-turn max-Command grant. Our own
				# _start_round folds it in at turn-begin, above the banking cap.
				combat._bonus_mana_next_turn += _wire_int(event.get("n", 0), 0)
			else:
				# A spell we cast granted us Command on our own side.
				combat.player_mana += _wire_int(event.get("n", 0), 0)
				combat._update_hud()
				_net_broadcast_hand_count()   # push the bumped Command to the foe's seal
		NetMatch.EV_MATCH_OVER:
			_net_show_result(_wire_int(event.get("winner", -1), -1))
		NetMatch.EV_REMATCH:
			_net_on_remote_rematch()
		NetMatch.EV_CHOICE:
			# Host asked us to pick an option for one of our own creatures (Copycat /
			# Adaptable). Show the picker; the answer goes back as an IN_CHOICE intent.
			_net_client_show_choice(_wire_int(event.get("eid", -1), -1), _wire_str(event.get("kind", "")))
		_:
			pass




## HOST: tell the client the host hand's public size/Command so its foe rail stays
## current. The client never claims its own count or Command; the host's private
## remote-state ledger already knows and publishes those values locally.
func _net_broadcast_hand_count() -> void:
	# The hand count rides with our live Command (current + max) so the opponent's
	# foe-Command seal tracks what we can afford. This fires on every hand/mana
	# change (turn-begin refill, each play, spell draw/Command rewards), so the
	# foe's readout stays current without a separate channel.
	if not combat._is_host():
		return
	NetMatch.send_to_client({"t": NetMatch.EV_HAND_COUNT, "n": combat._hand.size(),
		"mana": combat.player_mana, "maxmana": combat.player_max_mana})




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
	# Client discard faces travel as validated uid lists on the enclosing commit.




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
		"OPPONENT DISCARDS %d" % n, Color(0.78, 0.72, 0.62), false)




## The local drinker's beat + chronicle line for a skirmish quaff — the presentation
## half of `_resolve_combat_potion`, which skirmish never reaches (it has its own
## host-authoritative resolver). Kept in ONE place so the two entry branches of
## `_net_use_potion` cannot come to disagree about whether a drink is visible.
func _net_drink_beat(pid: String, target: Control) -> void:
	var data: Dictionary = PotionDB.get_potion(pid)
	var quaff_line := "You quaff the [color=%s]%s[/color]" \
		% [combat._LOG_PLAYER_COL, String(data.get("name", pid))]
	if target != null and is_instance_valid(target):
		quaff_line += " on %s" % combat._log_card_ref(target)
	# Potion glyph in the margin: painted PNG shows untinted, the white silhouette
	# kit renders tinted by the potion's colour (same rule as Shop / solo).
	var pot_icon: Texture2D = PotionDB.icon_for(pid)
	var pot_tint: Color = Color.WHITE if PotionDB.is_painted_icon(pid) \
		else data.get("color", Color(0.7, 0.7, 0.7))
	combat._log_event(quaff_line + ".", {}, 0, pot_icon, pot_tint)
	combat._play_potion_drink_fx(pid, target)
	# NOT the Apothecary: `tonic_vigor` is a board mutation and the host already fires
	# it for the drinker's side inside `_net_apply_host_potion`. Firing it here too
	# would double it on the host and desync it on the client. This function is
	# presentation only, which is why it is safe to call from both branches.


## Skirmish potion resolution. Host drinks resolve locally. A client sends only
## its potion id/target intent; the host validates the remaining private loadout,
## consumes it, and resolves resource and board effects authoritatively.
func _net_use_potion(pid: String, index: int, target: Control = null) -> void:
	var data: Dictionary = PotionDB.get_potion(pid)
	var effect := String(data.get("effect", ""))
	# YOUR OWN QUAFF IS AN ACT (2026-08-04). Both branches below used to hand the
	# drink straight to the resolver, so a skirmish player watched the FOE's potion
	# bloom center-screen with its name on a plate and got, for their own, an empty
	# belt slot and a number that moved. Solo has always played the drink; run it here
	# so it lands on both peers for their own bottle, on the caster's clock, before
	# any of the resolution below.
	_net_drink_beat(pid, target)
	if combat._is_client():
		var request := {"t": NetMatch.IN_USE_POTION, "pid": pid}
		if target != null and is_instance_valid(target):
			request["target"] = int(target.entity_id)
		NetMatch.send_intent(request)
		# EMPTY THE SLOT NOW, not when the round trip lands. The belt is
		# host-authoritative and the next EV_HAND_SET overwrites it wholesale
		# (`slot.potions = event.potions` in _net_apply_private_state), so this is
		# purely optimistic — the same optimism `_net_play_spell` already applies
		# to Command. Without it the bottle stayed lit for a full round trip and a
		# second click sent a second intent for a potion the host had already
		# spent, which came back to the player as the raw rejection string
		# "Action rejected: illegal potion target" for an entirely legal drink.
		combat._ctx_consume_potion(index)
		combat._rebuild_potion_bar()
		combat._update_hud()
		# THE HEAL HAS TO SHOW ON THE DRINKER'S SCREEN TOO. The optimistic green wash
		# lived in the `else` arm further down, which this early return makes
		# unreachable — the only non-host net role IS the client, so that branch has
		# never once executed. A client's own Healing Draught therefore emptied a belt
		# slot and moved a number: `_net_apply_board_sync` floats a figure on HP LOSS
		# only, so a gain arrived silently. Host-side the same bottle plays the wash.
		# Optimistic by design (the host's snapshot sets the true HP a beat later),
		# exactly as the dead branch intended.
		if effect == "heal_hp":
			# Clamped against our own known ceiling, the way solo's arm reports the
			# REAL delta (`player_hp - pot_before`) rather than the bottle's face
			# value — a "+8" beside a hero two off full is a number the following
			# snapshot immediately contradicts.
			combat._show_lifelink_heal(mini(int(data.get("value", 8)),
				maxi(0, combat._ctx_hero_max_hp() - combat.player_hp)))
		return
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
				# HOST-ONLY BY CONSTRUCTION. The client sent its intent and RETURNED
				# at the top of this function, and CombatMode has exactly three
				# values (SOLO / NET_HOST / NET_CLIENT), so the host is the only
				# role that can reach here. This used to carry an `else` arm that
				# sent a SECOND IN_USE_POTION and replayed the heal wash. It was
				# dead — but a live trap for the next reader, because it made
				# _net_use_potion look like it had two send sites and two heal
				# sites, one of each being a lie. The real client-side heal now
				# lives in the live client branch above.
				_net_apply_host_potion(pid, false, target)
				_net_sync_board()
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
	# The Apothecary (tonic_vigor) drinks along on the DRINKER's side — host-
	# authoritative board mutation, rides the snapshot to the client. (Caster-
	# local potions that never reach the host — gain_mana / draw — don't feed
	# her in net; every board-touching drink does.)
	combat._apply_tonic_vigor(caster_is_enemy)
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
				var pick: Control = combat._combat_ops.pick(pool)
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
			# landed caster-side in _net_use_potion). Like Offering, this is a paid
			# sacrifice rather than damage, so Shield / Last Stand cannot retain it.
			if target != null and is_instance_valid(target) and target.is_creature():
				combat._force_destroy_creature(target)
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




## HOST: tell the client that the host drank `pid`. Client drinks are announced
## by the same host path after their IN_USE_POTION intent is accepted.
func _net_send_potion_fx(pid: String) -> void:
	if combat._is_host():
		NetMatch.send_to_client({"t": NetMatch.EV_POTION_FX, "pid": pid})




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
		combat.spawn_floating_number(anchor, "OPPONENT DRINKS: %s" % nm.to_upper(), col, false)
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
	var caption = combat._make_rail_caption("OPPONENT DRINKS")
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
	# spanning the enemy column's full plate width.
	#
	# THE RAIL IS ONE ROW AND CANNOT GROW. Measured on a real board: the glossary
	# "?" orb sits at (1532, 598) 48x48 and the primary action button at
	# (1390, 656) 190x52, so there are ~70px between the caption and the next
	# thing — one row of chips, with no second row available above (the Command
	# seal) or below (those two). Meanwhile the arsenal size is the host's
	# setting and can be dialled to the pool, so "just shrink to fit" has a floor
	# it will blow through: at 14 relics + 4 potions the old sizing put chips out
	# to x1814 on a 1600 canvas — off the screen entirely.
	#
	# So the rail shows WHAT FITS at a readable size and counts the rest. A "+N"
	# tally is the honest failure mode for a fixed rail holding an unbounded
	# list; a 10px icon is not. 22px is the floor — below it a relic silhouette
	# stops resolving, and the rich hover is the reading copy anyway.
	const RAIL_W := 236.0
	const CHIP_FLOOR := 22
	# HALO_PAD is not slack: make_relic_chip draws a tier glow overhanging its own
	# rect by ~3px a side, so a run packed to the nominal 236 measured 6px past
	# the rail's right edge. Fit the INK, not the boxes — and BOTH the chip size
	# and the fit count must be computed against this one budget. Sizing chips to
	# 236 and then counting them against 228 disagrees by exactly one chip, which
	# put a "+2" tally on the DEFAULT five-item rail that has always fit.
	const HALO_PAD := 8.0
	var budget: float = RAIL_W - HALO_PAD
	var total_chips: int = rids.size() + pids.size()
	var GAP: int = 8 if total_chips <= 4 else (6 if total_chips <= 5 else 4)
	var CHIP: int = clampi(
		int((budget - float(total_chips - 1) * float(GAP)) / float(total_chips)),
		CHIP_FLOOR, 44)
	# How many chips actually fit at that size? Anything past this is tallied.
	var fits: int = maxi(1, int((budget + float(GAP)) / float(CHIP + GAP)))
	var overflow: int = maxi(0, total_chips - fits)
	if overflow > 0:
		fits -= 1          # the last cell becomes the tally
		overflow += 1
	var shown_relics: int = mini(rids.size(), fits)
	var shown_potions: int = mini(pids.size(), maxi(0, fits - shown_relics))
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
	var caption = combat._make_rail_caption("OPPONENT'S ITEMS")
	caption.anchor_left = 0.0
	caption.anchor_right = 1.0
	caption.offset_top = 0
	caption.offset_bottom = 20
	root.add_child(caption)
	var n: int = shown_relics + shown_potions + (1 if overflow > 0 else 0)
	var total_w: float = float(n * CHIP + (n - 1) * GAP)
	var x: float = maxf(0.0, (RAIL_W - total_w) * 0.5)
	# Plain-Control parent: chip sizes must be set by hand (custom_minimum_size
	# only binds inside containers — an unsized Panel renders as nothing).
	for i in shown_relics:
		var rid: String = String(rids[i])
		var chip := GameTheme.make_relic_chip(rid, CHIP)
		chip.size = Vector2(CHIP, CHIP)
		chip.position = Vector2(x, 26.0)
		root.add_child(chip)
		combat._net_foe_relic_chips[rid] = chip
		x += CHIP + GAP
	for i in shown_potions:
		var pid: String = String(pids[i])
		var chip := GameTheme.make_potion_chip(pid, CHIP)
		chip.size = Vector2(CHIP, CHIP)
		chip.position = Vector2(x, 26.0)
		root.add_child(chip)
		combat._net_foe_potion_slots_ui.append({"pid": pid, "chip": chip, "used": false})
		x += CHIP + GAP
	if overflow > 0:
		# The tally. It is a LABEL, not a chip: a "+4" that looked like an item
		# would read as a fifth relic nobody can name. Its tooltip lists them, so
		# nothing about the foe's arsenal becomes unknowable — only unglanceable.
		var more := GameTheme.make_label("+%d" % overflow, maxi(14, CHIP / 2),
			GameTheme.GILT)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.size = Vector2(CHIP, CHIP)
		more.position = Vector2(x, 26.0)
		more.mouse_filter = Control.MOUSE_FILTER_STOP
		var hidden_names: Array[String] = []
		for i in range(shown_relics, rids.size()):
			hidden_names.append(String(RelicDB.get_relic(String(rids[i])).get("name", rids[i])))
		for i in range(shown_potions, pids.size()):
			hidden_names.append(String(PotionDB.get_potion(String(pids[i])).get("name", pids[i])))
		more.tooltip_text = "Also carrying: " + ", ".join(hidden_names)
		root.add_child(more)




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
	# House grammar: QUAD-out out, BACK-out home. It used to overshoot on the way
	# out and ease flat on the way back — the inverse of Motion.punch, which is
	# what every other impact in the game reads like.
	tw.tween_property(chip, "scale", Vector2(1.4, 1.4), UserSettings.anim_time(0.14)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "scale", Vector2.ONE, UserSettings.anim_time(0.26)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var fl = combat.create_tween()
	fl.tween_property(chip, "modulate", Color(1.8, 1.65, 1.25), UserSettings.anim_time(0.10))
	fl.tween_property(chip, "modulate", Color.WHITE, UserSettings.anim_time(0.30))
	_spawn_chip_burst(chip.get_global_rect().get_center(), chip.size.x * 0.72,
		GameTheme.GILT_BRIGHT)




## An expanding, fading ring — the "trigger burst" both the relic pulse and the
## potion reveal use. Motion.ring is the one ring engine since R5.
func _spawn_chip_burst(center: Vector2, radius: float, color: Color) -> void:
	if combat._hud_layer == null:
		return
	Motion.ring(combat._hud_layer, center, color, {
		"radius": radius, "start_scale": 0.55, "end_scale": 1.6,
		"duration": 0.42, "width": 3.0, "z_index": 59,
		"trans": Tween.TRANS_CUBIC, "scale_time": true,
	})




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
	var data := SkirmishState.skirmish_card_data(_wire_str(event.get("id", "")))
	if data.is_empty():
		return
	var teid: int = _wire_int(event.get("target", -1), -1)
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
	# THE WATCHER MUST SEE WHAT THE CASTER SEES. This is the mirror of the solo
	# targeting arrow, and it was built the same flat way — a 7px untextured
	# Line2D whose `width_curve` and lengthwise `gradient` both worked along the
	# run and neither across the width, which is where a glow lives. Same
	# construction as its twin, so the two screens stay honest with each other.
	var line := Motion.beam_line(
		PackedVector2Array(), Color(1.0, 0.62, 0.22, 0.98), 22.0,
		"comet", 0.90, "comet")
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 239
	# Bow the curve downward — the opponent throws the spell down at our board.
	var dir := to - from
	var ctrl1 := from + Vector2(dir.x * 0.15, 150.0)
	var ctrl2 := to + Vector2(0.0, -70.0)
	var points := PackedVector2Array()
	var steps := 26
	for i in range(steps + 1):
		points.append(combat._bezier_cubic(from, ctrl1, ctrl2, to, float(i) / float(steps)))
	line.points = points
	# The BEAM fades through its shader, not through modulate — see the tween
	# below. Starting hidden has to go through the same channel or the arrow
	# would snap to full on its first frame.
	var line_mat: ShaderMaterial = line.material as ShaderMaterial
	if line_mat != null:
		line_mat.set_shader_parameter("fade", 0.0)
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
	#
	# THE LINE AND THE HEAD FADE THROUGH DIFFERENT CHANNELS, which looks like an
	# inconsistency and is not: the head is a plain Polygon2D and answers
	# `modulate`, while the beam's material writes COLOR outright and never
	# reads it. Left as a `modulate:a` tween the arrow would have hung at full
	# strength for the whole beat and then vanished on the free — a silent
	# failure, since nothing errors and the tween reports success.
	var fade_line := func(v: float) -> void:
		if line_mat != null:
			line_mat.set_shader_parameter("fade", v)
	tw.tween_method(fade_line, 0.0, 1.0, 0.12)
	tw.parallel().tween_property(head, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.45)
	tw.tween_method(fade_line, 1.0, 0.0, 0.30)
	tw.parallel().tween_property(head, "modulate:a", 0.0, 0.30)
	tw.tween_callback(func():
		if is_instance_valid(line): line.queue_free()
		if is_instance_valid(head): head.queue_free())




## The other peer dropped — end cleanly and return to the menu. Handles both the
## mid-match case and the post-match case (opponent declined the rematch / left
## the result screen), which the plain _net_match_over guard would otherwise eat.
func _net_on_peer_lost() -> void:
	if combat._net_match_over:
		# Past a game's end. TWO states reach here: the result screen (Bo1, or a
		# decided series), which HAS a panel — and the between-games interstitial
		# of a LIVE Bo3, which builds no panel at all (_net_show_result returns
		# early into _net_show_series_interstitial). The teardown used to sit
		# INSIDE the panel null-check, so a drop during the interstitial was
		# swallowed whole: no notice, no menu return, no timeout, and the survivor
		# then waited forever on a rematch handshake the departed peer never sends.
		if combat._net_peer_lost_handled:
			return
		combat._net_peer_lost_handled = true
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
	# ONE TEARDOWN PER DROP. This branch handled a lost peer without ever claiming
	# the latch that says so, so a second delivery — both `peer_left` and
	# `host_closed` are wired to this function — fell through to the post-match
	# branch above and armed a SECOND leave-and-fade over the one already counting
	# down. Two `fade_out_then_change_scene` calls race each other on a scene that
	# is already tearing down. The latch is what the post-match branch has always
	# used; the mid-match branch simply never set it.
	if combat._net_peer_lost_handled:
		return
	combat._net_peer_lost_handled = true
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
## machine (those resources never leave the caster). Every cast still notifies the
## host for spell counters and board passives; War Chant & Mass Grave additionally
## forward a numeric board consequence.


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




## Caster-LOCAL pile/hand spells. The hand, piles, and resulting draws all live on
## the caster's machine, so the caster resolves those here (with its own picker UI)
## rather than round-tripping the host. War Chant / Mass Grave forward only their
## BOARD consequence (Soldier count / fallen count) for the host to apply. Mirrors
## the solo resolver branches, kept compact so no solo-only spell state is dragged in.
func _net_play_caster_local_spell(card: Control, cost: int) -> void:
	var id: String = card.card_id
	var sid: String = String(card.card_data.get("spell", {}).get("id", ""))
	var plus_draw: int = int(card.card_data.get("extra_draw", 0))
	# CENTRE, not top-left (2026-08-04). `_spawn_spell_cast_ghost` positions the raised
	# writ around this point and both solo call sites pass `global_position + size * 0.5`;
	# skirmish passed the raw origin, so the writ rose from half a card up-and-left of the
	# sheet the player had just let go of.
	var spell_start_global: Vector2 = card.global_position + card.size * 0.5
	combat._net_log_local_cast(card.card_data, null)   # "You cast X." (hand/pile spell)
	# Spend Command + pull the card from hand up front (matches the generic path).
	combat.player_mana -= cost
	# THE SPEND IS ITS OWN BEAT (parity, 2026-08-04). Every solo play site passes
	# MANA_SPEND_BEAT so the RESOURCE lands half a beat behind the CARD — otherwise the
	# card's exit, the play cue, the seal punch and the arrival press all share one
	# frame and four simultaneous events read as one indistinct event. All three
	# skirmish play sites were passing the 0.0 default, so a skirmish play was exactly
	# the mush that offset was introduced to fix.
	combat._pulse_mana_label(cost, false, combat.MANA_SPEND_BEAT)
	combat._first_spell_this_turn = true   # Witch's first-spell discount rests (parity w/ solo)
	combat._hand.erase(card)
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	combat._spawn_spell_cast_ghost(card.card_data, spell_start_global, null)
	combat._play_spell_cast_vfx(card.card_data, null)
	var board_n: int = 0          # board consequence to forward (War Chant / Mass Grave)
	var picked_uids: Array = []   # private choices; the host validates each uid
	match sid:
		"recycle":
			if combat._hand.size() > 0:
				var rp: Control = await combat._show_recycle_modal()
				if rp != null and is_instance_valid(rp):
					picked_uids.append(int(rp.deck_uid))
					var rcost: int = int(rp.card_data.get("cost", 0))
					combat._hand.erase(rp)
					if rp.get_parent() != null:
						rp.get_parent().remove_child(rp)
					combat._exhaust_pile.append(combat._pile_entry(rp.card_id, rp.deck_uid))
					rp.queue_free()
					for _i in rcost + plus_draw:
						combat.draw_one()
		"gambit":
			var gmax: int = mini(3, combat._hand.size())
			if gmax > 0:
				var gp: Array = await combat._show_discard_picker(gmax,
					"Gambit — discard up to %d, draw that many" % gmax, true)
				for c in gp:
					picked_uids.append(int(c.deck_uid))
					_net_pitch_card(c)
				# Draw once per discarded card (the loop lives OUTSIDE the
				# per-card loop, or a 3-discard would draw 9).
				for _gi in gp.size():
					combat.draw_one()
		"war_chant":
			var wmax: int = mini(3, combat._hand.size())
			if wmax > 0:
				var wp: Array = await combat._show_discard_picker(wmax,
					"Call the Militia — discard up to %d to summon that many Soldiers" % wmax, true)
				for c in wp:
					picked_uids.append(int(c.deck_uid))
					_net_pitch_card(c)
				board_n = wp.size()
		"mass_grave":
			# Caster's own fallen count — mirrored on both machines, but ship the
			# number anyway so resolution never leans on counter sync.
			board_n = combat._friendly_deaths_this_fight
	# Every caster-local spell still gets a host-authoritative empty board arm. That
	# is where the ordinary spell counter, Hexblade/Emberwright and Leyline Conduit
	# live; Recycle/Gambit simply have no custom board case. War Chant / Mass Grave
	# attach the one numeric consequence calculated from the caster's private piles.
	if combat._is_host():
		var hdata: Dictionary = card.card_data.duplicate(true)
		if sid == "war_chant" or sid == "mass_grave":
			hdata["_net_picks"] = board_n
		_net_resolve_spell(hdata, -1, 0)
		NetMatch.send_to_client({"t": NetMatch.EV_SPELL, "id": id, "target": -1})
		_net_sync_board()
	else:
		var intent := {"t": NetMatch.IN_PLAY_SPELL, "uid": card.deck_uid,
			"id": id, "target": -1, "picks": picked_uids}
		if sid == "war_chant" or sid == "mass_grave":
			intent["n"] = board_n
		NetMatch.send_intent(intent)
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
			combat._show_info("Your opponent's spell step — yours comes next.")
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
	# CENTRE, not top-left (2026-08-04). `_spawn_spell_cast_ghost` positions the raised
	# writ around this point and both solo call sites pass `global_position + size * 0.5`;
	# skirmish passed the raw origin, so the writ rose from half a card up-and-left of the
	# sheet the player had just let go of.
	var spell_start_global: Vector2 = card.global_position + card.size * 0.5
	combat.player_mana -= cost
	# THE SPEND IS ITS OWN BEAT (parity, 2026-08-04). Every solo play site passes
	# MANA_SPEND_BEAT so the RESOURCE lands half a beat behind the CARD — otherwise the
	# card's exit, the play cue, the seal punch and the arrival press all share one
	# frame and four simultaneous events read as one indistinct event. All three
	# skirmish play sites were passing the 0.0 default, so a skirmish play was exactly
	# the mush that offset was introduced to fix.
	combat._pulse_mana_label(cost, false, combat.MANA_SPEND_BEAT)
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
		combat._targeting_paid_cost = cost
		combat._targeting_spell = card
		combat._targeting_data = data
		combat._show_info("Click a target.")
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




## HOST: validate the target carried by a remote spell intent against the
## authoritative CardDB targeting contract. The client sits on the host's enemy
## side, but keep the caster-side parameter explicit so the ownership rule stays
## readable: friendly targets share that side; enemy targets do not.
func _net_remote_spell_target_valid(data: Dictionary, target_eid: int,
		caster_is_enemy: bool) -> bool:
	var targeting: String = String(data.get("targeting", "none"))
	if targeting == "none":
		return target_eid == -1
	# `any` alone may point at the opposing hero. A null target is how that face
	# choice crosses the wire; every other targeted mode requires a creature.
	if targeting == "any" and target_eid == -1:
		return true
	if target_eid < 0:
		return false
	var node = NetMatch.get_entity(target_eid)
	if node == null or not is_instance_valid(node) or not (node is Control):
		return false
	if not node.has_method("is_creature") or not node.is_creature():
		return false
	if not node.has_method("has_keyword") or node.has_keyword("structure"):
		return false
	# Membership in the authoritative board arrays proves both that this is a
	# seated combat creature and which side owns it. Do not trust a peer-supplied
	# id (or even a loose node property) to establish ownership.
	var target_is_enemy_side := false
	if combat._all_friendly(true).has(node):
		target_is_enemy_side = true
	elif not combat._all_friendly(false).has(node):
		return false
	match targeting:
		"friendly_creature":
			return target_is_enemy_side == caster_is_enemy
		"enemy_creature":
			return target_is_enemy_side != caster_is_enemy
		"any_creature", "any":
			return true
	return false



## HOST: apply the client's spell intent (caster perspective = index 1).
func _net_apply_remote_spell(intent: Dictionary) -> void:
	if combat._net_active_index != 1:
		if not SkirmishState.vs_bot:
			_net_reject_remote("not_your_turn")
		return
	# THE PRACTICE BOT HAS NO AUTHORITY OBJECT, AND THAT IS BY DESIGN.
	# `_net_init_remote_authority` returns false the moment `vs_bot` is set — there
	# is no remote hand to own — so `_remote_state` is null in every practice match.
	# This arm dereferenced it unguarded and bailed here, which meant the bot could
	# never cast a spell AT ALL: `SkirmishBot.build_deck` puts up to five in its
	# twenty, `decide_turn` scores and returns IN_PLAY_SPELL intents for them, and
	# `_bot_take_turn` charges the bot for the card (`_bot_consume_card` pulls it
	# from hand and adds its cost to `spent`) BEFORE handing it here — so a quarter
	# of the bot's deck was dead weight that it also PAID Command for. Silently:
	# `_net_reject_remote` is itself a no-op in a practice match.
	# The creature arm beside this one has always guarded every authority call with
	# `if not SkirmishState.vs_bot:`; the spell arm simply never got the same
	# treatment. The bot's hand/Command live in `_bot_hand` / `_bot_banked_mana` and
	# are already spent by its caller, so skipping the private-state ledger is
	# exactly right — there is no second ledger to keep.
	if _remote_state == null and not SkirmishState.vs_bot:
		_net_reject_remote("authority_unavailable")
		return
	var id := _wire_str(intent.get("id", ""))
	var uid := _wire_int(intent.get("uid", -2), -2)
	var data := SkirmishState.skirmish_card_data(id)
	if data.is_empty() or String(data.get("type", "")) != "spell" \
			or not _net_spell_supported(data):
		if not SkirmishState.vs_bot:
			_net_reject_remote("card_not_spell")
		return
	var authority_check: Dictionary = {}
	if not SkirmishState.vs_bot:
		authority_check = _remote_state.validate_play(uid, id,
			_net_remote_has_first_spell_discount())
		if not bool(authority_check.get("ok", false)):
			_net_reject_remote(String(authority_check.get("reason", "illegal_play")))
			return
	var target_eid: int = _wire_int(intent.get("target", -1), -1)
	if not _net_remote_spell_target_valid(data, target_eid, true):
		if not SkirmishState.vs_bot:
			_net_reject_remote("illegal_target")
		return
	# Caster-local pile spells (War Chant / Mass Grave) resolve their hand part on the
	# client and forward only the board consequence as a pick/size count.
	var sid := String(data.get("spell", {}).get("id", ""))
	var picks: Array = intent.get("picks", []) if intent.get("picks", []) is Array else []
	var max_picks := 0
	if sid == "recycle":
		max_picks = 1
	elif sid in ["gambit", "war_chant"]:
		max_picks = 3
	if picks.size() > max_picks or (max_picks == 0 and not picks.is_empty()):
		if not SkirmishState.vs_bot:
			_net_reject_remote("illegal_private_choice")
		return
	# Everything from here to the resolve is the CLIENT'S PRIVATE LEDGER — the hand
	# entry checks, the commit, and the pile consequences of the four caster-local
	# pile spells. The bot has no such ledger (its hand is `_bot_hand`, already
	# debited by `_bot_take_turn`), so the whole block is skipped for it and the
	# board resolution below runs on its own. SkirmishBot never emits a pick-bearing
	# spell in the first place — `_best_spell` only scores damage / AoE / buff /
	# heal — so no bot cast reaches these arms with picks to spend.
	if not SkirmishState.vs_bot:
		var seen_picks: Dictionary = {}
		for raw_pick in picks:
			var pick_uid := int(raw_pick)
			if pick_uid == uid or seen_picks.has(pick_uid) \
					or _remote_state.hand_entry(pick_uid).is_empty():
				_net_reject_remote("private_choice_not_in_hand")
				return
			seen_picks[pick_uid] = true
		if _remote_state.commit_play(authority_check, false).is_empty():
			_net_reject_remote("play_commit_failed")
			return
		if sid == "recycle" and not picks.is_empty():
			var recycled: Dictionary = _remote_state.hand_entry(int(picks[0]))
			var recycle_draw := int(recycled.get("cost", 0)) + int(data.get("extra_draw", 0))
			_remote_state.move_hand_cards(picks, true)
			_remote_state.draw_cards(recycle_draw)
		elif sid == "gambit":
			_remote_state.discard_cards(picks)
			_remote_state.draw_cards(picks.size())
		elif sid == "war_chant":
			_remote_state.discard_cards(picks)
			data = data.duplicate(true)
			data["_net_picks"] = picks.size()
	if sid == "mass_grave":
		data = data.duplicate(true)
		data["_net_picks"] = combat._enemy_deaths_this_fight
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
	_net_send_private_state()
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
	# Worn Spellbook (board relic, host-authoritative). The card reads: "When you
	# cast a spell already cast this fight: draw 1; if it deals damage, it deals
	# +2." The old net arm honoured NONE of that — it had no repeat gate (it fired
	# on every damage spell), no draw, and a hardcoded +1 instead of the relic's
	# printed value. Resolve the repeat ONCE here, for the caster's own side, and
	# let both the built-in arm below and the custom arm in _net_resolve_custom_spell
	# read the result out of _net_spellbook_bonus.
	var spell_key: String = String(data.get("id", spell.get("id", data.get("name", ""))))
	var sb_seen: Dictionary = combat._net_spell_names_fight[caster_index]
	var sb_repeat: bool = int(sb_seen.get(spell_key, 0)) > 0
	sb_seen[spell_key] = int(sb_seen.get(spell_key, 0)) + 1
	var sb_bonus: int = 0
	if sb_repeat and combat._relic_active_for_side(caster_is_enemy, "worn_spellbook"):
		_net_caster_draw(caster_is_enemy, 1)
		sb_bonus = int(RelicDB.get_relic("worn_spellbook").get("value", 2))
		_relic_fired_for_side(caster_is_enemy, "worn_spellbook")
	if sb_bonus > 0 \
			and stype in ["damage", "damage_face", "damage_all_enemies", "damage_all"]:
		value += sb_bonus
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
			_net_resolve_custom_spell(String(spell.get("id", "")), target, caster_is_enemy, data, sb_bonus)
	combat._cleanup_dead()
	# Remember the last host-resolved spell (and its target) for Echo — but never
	# Echo itself, so a chain of Echoes can't form. Caster-local pile spells don't
	# pass through here, so Echo only ever copies a board/damage/buff spell.
	if String(spell.get("id", "")) != "echo_spell":
		_net_store_last_spell_for(caster_index, data, target_eid)
	# Leyline Conduit shields its column after its owner's first resolved spell.
	if _net_spell_count_for(caster_index) == 0:
		combat._trigger_first_spell_column_shields(caster_is_enemy)
	# The Magister's Ledger (warlock MOMENT) — host-side, per caster, reading the
	# count BEFORE this cast, exactly as the solo site does.
	combat._maybe_pay_ledger(caster_is_enemy, _net_spell_count_for(caster_index))
	# Count this cast for the active side's combo spells (flame_bolt). Incremented
	# AFTER resolution so a combo spell reads the count of PRIOR spells this turn.
	_net_increment_spell_count_for(caster_index)
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
			"coven_spell":
				# Coven Mother — every spell permanently grows the caster's Warlocks
				# +1 ATK for the fight (forged also heals its hero 1). Host-side per
				# side; the folded buff rides the board snapshot to the client.
				for _wl in combat._all_friendly(caster_is_enemy):
					if not is_instance_valid(_wl) or String(_wl.card_data.get("ctype", "")) != "warlock":
						continue
					_wl.persistent_atk_buff += 1
					_wl.persistent_atk_buff_rounds = 99
					_wl.update_stat_display()
				if bool(_sp.card_data.get("is_upgraded", false)):
					combat._heal_owner_hero(caster_is_enemy, 1)
			"spark_on_spell":
				# Cinder Acolyte, host-side per caster: sparks the enemy opposing
				# her lane (2 forged) — the solo loop's perspective-aware twin.
				var _spk = combat.get_opposing_card(_sp.current_lane, caster_is_enemy)
				if _spk != null and is_instance_valid(_spk) and _spk.current_hp > 0:
					_spk.take_damage(2 if bool(_sp.card_data.get("is_upgraded", false)) else 1)
			"shield_on_spell":
				# Ember Warden, host-side per caster: Shield on every cast
				# (forged: her column-mate shields too). Shield state rides the
				# board snapshot like Leyline's column shields.
				combat._grant_combat_shield(_sp)
				if bool(_sp.card_data.get("is_upgraded", false)):
					var _ewr: int = combat.ROW_BACK if _sp.current_row == combat.ROW_FRONT else combat.ROW_FRONT
					var _ewm = combat._row_array(caster_is_enemy, _ewr)[_sp.current_lane]
					if _ewm != null and is_instance_valid(_ewm):
						combat._grant_combat_shield(_ewm)




func _net_resolve_custom_spell(spell_id: String, target: Control, caster_is_enemy: bool, data: Dictionary, spellbook_bonus: int = 0) -> void:
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
	# The repeat gate, the draw and the chip pulse were all resolved once in
	# _net_resolve_spell (our only caller) — this arm just spends the bonus it left.
	if spellbook_bonus > 0 and spell_id in [
			"immolate", "inferno", "wildfire", "petard", "earthquake", "blood_tithe",
			"flame_bolt", "ricochet", "quick_shot", "slash",
			"ballista_bolt"]:
		plus += spellbook_bonus
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
			# All the caster's DEAD gain Lifesteal for the fight ("+" adds
			# +1 ATK). Keyword + folded buff ride the board snapshot, so the
			# client renders both.
			for zc in friendlies:
				if not is_instance_valid(zc) or String(zc.card_data.get("ctype", "")) != "dead":
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
				combat._force_destroy_creature(target)
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
				c.state.war_cry_swift = true
				if plus > 0:
					c.temp_atk_buff += plus
				c.update_stat_display()
				combat.spawn_keyword_callout_kw(c, "granted_swift")
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
					_net_remote_field_card_left(target, bool(target.is_opponent), true)
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
			var fb_caster: int = 1 if caster_is_enemy else 0
			var fb: int = (5 if _net_spell_count_for(fb_caster) >= 1 else 3) + plus
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
				combat._combat_ops.pick(foes).take_damage(rc_fallback_hit)
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
			combat._apply_reserve_orders(target, is_plus)
		"coin":
			# Going-second compensation: a one-time +1 Command (Hearthstone's Coin).
			_net_caster_gain_mana(caster_is_enemy, 1)
		"bloodletting":
			_net_damage_hero(caster_is_enemy, 1)   # self-harm cost (caster's own face)
			_net_caster_gain_mana(caster_is_enemy, 2 + int(data.get("extra_mana", 0)))
			var bl_fallen: int = combat._enemy_deaths_this_fight if caster_is_enemy else combat._friendly_deaths_this_fight
			if bl_fallen > 0:
				_net_caster_draw(caster_is_enemy, 1)
		# ── Targeted tactical spells ───────────────────────────────────────────
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
			combat._arm_battle_order(target)
		"turbo":
			combat._apply_frenzy(target, is_plus)
		"unholy_bargain":
			# Campaign-only and denylisted in SkirmishState; retain a safe no-op arm
			# so stale peers cannot invoke its retired net behavior.
			pass
		# ── Sacrifice spells (forced death bypasses Shield / Last Stand) ───────
		"offering":
			if target != null:
				target.state.offering_extra_on_death = 1
				combat._force_destroy_creature(target)
				_net_caster_draw(caster_is_enemy, plus_draw)
		"fuel_the_pyre":
			if target != null:
				var fp_atk: int = target.effective_atk()
				var fp_lane: int = target.current_lane
				combat._force_destroy_creature(target)
				# Deterministic revenge (mirrors solo): hit whatever stands across
				# the victim's lane; only an empty column scatters the flame.
				var fp_opp: Control = combat.get_opposing_card(fp_lane, caster_is_enemy)
				if fp_opp != null:
					fp_opp.take_damage(fp_atk + plus)
				elif foes.size() > 0:
					combat._combat_ops.pick(foes).take_damage(fp_atk + plus)
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
			# temp_poison is the erase order the decay obeys — raise it ONLY on a
			# body this cast envenomed, or a printed Poison is stripped for good.
			# Mirrors the solo fix; see Combat.gd's venom_tip arm.
			if target != null:
				if not target.card_data.keywords.has("poison"):
					target.card_data.keywords.append("poison")
					target.state.temp_poison = true
				target.update_stat_display()
				combat.spawn_keyword_callout_kw(target, "poison")
		"charge_spell":
			# Target friendly strikes every opposing lane on the caster's turn
			# (the strike pass reads charges_this_turn; decay clears it after).
			if target != null:
				target.state.charges_this_turn = true
				combat.spawn_keyword_callout_kw(target, "charging")
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
					_net_remote_field_card_left(target, bool(target.is_opponent), true)
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
			var echo_caster: int = 1 if caster_is_enemy else 0
			var echo_data := _net_last_spell_for(echo_caster)
			if not echo_data.is_empty():
				_net_resolve_spell(echo_data, _net_last_spell_target_for(echo_caster), echo_caster)
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
			# Damage every caster foe by the caster's fallen count (sent as _net_picks).
			var mg_dmg: int = int(data.get("_net_picks", 0)) + plus
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
	combat._combat_ops.damage_hero(combat, is_enemy_side, value)




## Heal a hero by host-side, capped at the skirmish starting HP. is_enemy_side
## true → the host's enemy (client) hero; false → the host's own hero.
func _net_heal_hero(is_enemy_side: bool, value: int) -> void:
	combat._combat_ops.heal_hero(combat, is_enemy_side, value, SkirmishState.START_HP)




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
	else:
		var healed: int = combat._combat_ops.heal_hero(
			combat, false, n, combat.player_max_hp)
		if healed <= 0:
			return
		combat._show_lifelink_heal(healed)   # green +N at the HP medallion — any hero heal, not just Lifesteal
		combat._update_hud()



## Damage the hero OPPOSING owner_is_enemy's side (a drain / reach payoff).
func _hurt_opposing_hero(owner_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	combat._combat_ops.damage_opposing_hero(combat, owner_is_enemy, n)




## Make the CASTER draw n cards from THEIR OWN pile. The host can only draw into
## its own hand, so when the client is the caster (caster_is_enemy) it sends an
## EV_DRAW event and the client draws locally; when the host casts, it draws here.
func _net_caster_draw(caster_is_enemy: bool, n: int) -> void:
	if n <= 0:
		return
	if caster_is_enemy:
		if _remote_state != null:
			_remote_state.draw_cards(n)
			_net_send_private_state()
		else:
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
		if _remote_state != null:
			_remote_state.give_card(id, uid)
			_net_send_private_state()
		else:
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
		if _remote_state != null:
			_remote_state.gain_mana(n)
			_net_send_private_state()
		else:
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
	var data: Dictionary = CardDB.get_card_data(String(combat._combat_ops.pick(candidates)))
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
		"mass_grave":
			# Greyed until the caster's own side has a fallen (forged + 2 stays live).
			var mg_fallen: int = combat._enemy_deaths_this_fight if caster_is_enemy \
				else combat._friendly_deaths_this_fight
			return not foes.is_empty() \
				and (mg_fallen > 0 or bool(data.get("is_upgraded", false)))
		"ricochet", "wildfire":
			return not foes.is_empty()
		"ambush":
			return not foes.is_empty() or combat._has_swift_friendly(caster_is_enemy)
		"plague_bell", "earthquake":
			return not combat._all_creatures_both_sides().is_empty()
		"war_cry", "virulence", "kings_command":
			return not friendlies.is_empty()
		"censer_light":
			# The smoke needs one of your Dead to settle on — grey without one.
			for cl_g in friendlies:
				if is_instance_valid(cl_g) and String(cl_g.card_data.get("ctype", "")) == "dead":
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
	return int(combat._combat_ops.pick(valid).entity_id)




# ── Networked choice (Copycat / Adaptable): the OWNER always makes the pick ──

## HOST: a CLIENT creature's on-enter needs a player choice. Ask the client to pick (it
## has the creature on its own board via the board sync); the answer returns as an
## IN_CHOICE intent and _net_apply_client_choice applies it host-authoritatively.
func _net_request_client_choice(card, kind: String) -> void:
	if not combat._is_host() or card == null or not is_instance_valid(card):
		return
	if kind not in ["keyword", "copy_friendly"]:
		return
	_pending_remote_choices[int(card.entity_id)] = kind
	NetMatch.send_to_client({"t": NetMatch.EV_CHOICE, "eid": int(card.entity_id), "kind": kind})




## HOST: apply the client's pick for an EV_CHOICE prompt, then board-sync so both sides
## see the result. Validates the entity is still the client's own creature.
func _net_apply_client_choice(intent: Dictionary) -> void:
	if not combat._is_host() or combat._net_active_index != 1:
		return
	var eid: int = _wire_int(intent.get("eid", -1), -1)
	var kind := _wire_str(intent.get("kind", ""))
	if String(_pending_remote_choices.get(eid, "")) != kind:
		_net_reject_remote("choice_not_pending")
		return
	_pending_remote_choices.erase(eid)
	var node = NetMatch.get_entity(eid)
	if node == null or not is_instance_valid(node) or not node.is_opponent:
		_net_reject_remote("choice_entity_invalid")
		return
	match kind:
		"keyword":
			var kw: String = _wire_str(intent.get("pick", ""))
			if kw in ["swift", "piercing", "armored", "thorns"]:
				if kw not in node.card_data.keywords:
					node.card_data.keywords.append(kw)
				node.update_stat_display()
				_net_sync_board()
		"copy_friendly":
			var src_eid: int = _wire_int(intent.get("pick", -1), -1)
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
