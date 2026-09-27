extends SceneTree
## _probe_net_soak.gd — PLAY REAL SKIRMISH MATCHES AND WATCH FOR BREAKAGE.
##
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_net_soak.gd
##
## Every other net probe stages ONE board and asserts ONE thing about it. None of
## them plays a MATCH. This one drives a full practice-bot skirmish from the toss to
## the verdict — both battle styles — playing the local side with a dumb-but-legal
## policy (drop whatever is affordable into the first empty slot, then commit), and
## it fails on anything the engine pushed to the error stream while that happened.
##
## HOUSE TRAP: all THREE terms of `is_connected_to_peer()` (`_connected` +
## `remote_present` + `_compatibility_confirmed`) or Combat boots SOLO and this
## silently soaks the campaign instead.

var SS: Node
var NM: Node
var US: Node
var combat: Node

var _started := false
var _done := false
var _fails := 0
var _notes: Array[String] = []
var _peak_mine: int = 0
var _spent_any: bool = false
# Peak size of a single EV_CLASH strike reel across the whole soak. NetProtocol
# rejects any array over MAX_ARRAY_ITEMS, and the reel is shipped as ONE array —
# so a clash that overruns it is dropped whole by `validate_envelope`
# ("payload_shape") and the watcher's screen simply snaps to the outcome with no
# fight in between. Nothing else measures this.
var _peak_reel: int = 0
var _peak_reel_where: String = ""
var _btn_flagged: bool = false
# SEALED HAS TO ACTUALLY BE SEALED. Mutation testing (tools/run_mutation_check.sh)
# made `_is_sealed()` return false and this soak stayed GREEN: the mode silently
# degraded to Alternating, creatures still reached the board, and every assertion
# held. The soak was proving "cards can be played", not "Sealed Orders ran". These
# two flags watch for the phases only the sealed flow has — a hidden orders window
# and an open spell step — so the mode cannot be switched off unnoticed.
var _saw_orders_phase: bool = false
var _saw_sorcery_step: bool = false


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


var _sample_tag: String = ""


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	# Sample the reel every frame: it is cleared by `_net_send_clash_log` the moment
	# a segment ships, so the peak only exists mid-clash.
	if is_instance_valid(combat):
		var n: int = combat._net_clash_log.size()
		if n > _peak_reel:
			_peak_reel = n
			_peak_reel_where = _sample_tag
		# The two phases unique to Sealed Orders, sampled per frame because both
		# are transient: the orders window closes at the reveal and the spell step
		# closes when both sides pass.
		if combat._is_sealed():
			if combat._sorcery_active < 0 and not combat._sealed_await_foe \
					and combat.phase == combat.Phase.PLAYER_TURN:
				_saw_orders_phase = true
			if combat._sorcery_active >= 0:
				_saw_sorcery_step = true
	return _done


func _finish(code: int) -> void:
	_done = true
	quit(code)


func _boot(style: int, seed_val: int, arsenal: int) -> bool:
	SS.reset()
	# A deck with real texture: bodies, a spell, keyword carriers.
	var pool: Array = ["brute", "goblin", "brute", "goblin", "strike", "brute",
		"goblin", "brute", "goblin", "strike", "brute", "goblin",
		"brute", "goblin", "strike", "brute", "goblin", "brute", "goblin", "strike"]
	for cid in pool:
		SS.add_card_to(0, cid)
		SS.add_card_to(1, cid)
	SS.combat_mode = SS.CombatMode.NET_HOST
	SS.local_index = 0
	SS.rng_seed = seed_val
	SS.vs_bot = true
	SS.best_of = 1
	# Arm the drafted arsenal the real modes hand over — otherwise the soak never
	# once exercises `_has_relic` in net or any host-authoritative potion resolver.
	var slot = SS.get_slot(0)
	if slot != null:
		var rp: Array = SS.NET_RELIC_POOL
		var pp: Array = SS.NET_POTION_POOL
		slot.relics = [
			String(rp[arsenal % rp.size()]),
			String(rp[(arsenal + 5) % rp.size()]),
			String(rp[(arsenal + 9) % rp.size()]),
		]
		slot.potions = [
			String(pp[arsenal % pp.size()]),
			String(pp[(arsenal + 4) % pp.size()]),
			String(pp[(arsenal + 8) % pp.size()]),
		]
	# ARM THE BOT TOO. A real practice match gives slot 1 three relics off
	# BOT_RELIC_POOL (NetMatch.send_draft_event's vs_bot "finished" echo) and no
	# potions. Arming only the human made this soak measure a match nobody plays —
	# and, more to the point, left `_relic_active_for_side(true, …)` — the whole
	# host-authoritative enemy-relic path — completely unexercised.
	var bot_slot = SS.get_slot(1)
	if bot_slot != null:
		var brp: Array = SS.BOT_RELIC_POOL
		bot_slot.relics = [
			String(brp[arsenal % brp.size()]),
			String(brp[(arsenal + 1) % brp.size()]),
			String(brp[(arsenal + 2) % brp.size()]),
		]
		bot_slot.potions = []
	NM.is_host = true
	NM.vs_bot = true
	NM.local_player_index = 0
	NM._connected = true
	NM.remote_present = true
	NM._compatibility_confirmed = true
	NM.client_peer_id = 0
	NM.battle_style = style
	NM.entities.clear()
	NM._next_entity_id = 1

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	for _i in 12:
		await create_timer(0.25).timeout
		if not is_instance_valid(combat) or combat._hand.size() > 0:
			break
	return is_instance_valid(combat)


## Spend the turn the way a player would: drink what is drinkable, cast what is
## castable (targeted spells get a real click on a real body), and drop every
## affordable creature into the first empty friendly slot — all through the REAL
## entry points, so a gate that refuses wrongly shows up as an empty board.
## Poll until the hand has finished ARRIVING, not just until the turn is ours.
##
## Combat._start_round STAGGERS the deal: only the first card is drawn inline,
## and every one after it lands on a `create_timer(0.08 * i)` — no headless
## branch, no reduce_motion branch, not scaled by `anim_speed` — while `phase`
## ALREADY reads PLAYER_TURN. CombatNet routes its round starts through that
## same function, so a skirmish driver inherits the stagger exactly as a solo
## one does. See CLAUDE.md's settle-until-stable note; it cost
## `_probe_deploy_curve` a published number before it was found.
##
## Stability polling, NOT a computed deal window: draw_count is the ramp plus
## four relics plus two mutators, and restating that arithmetic in a probe is
## the duplicate-rule pathology. Bounded, because an unbounded `while await`
## spins to the harness timeout and reports NOTHING at all.
func _settle_hand() -> void:
	const SETTLE_TICK := 0.03    # poll interval
	const STABLE_TICKS := 5      # 0.15s unchanged, a 1.9x margin on the 0.08s gap
	const SETTLE_BUDGET := 40    # ~1.2s ceiling
	var last := -1
	var stable := 0
	var waited := 0
	while waited < SETTLE_BUDGET:
		if not is_instance_valid(combat) or combat.phase != combat.Phase.PLAYER_TURN:
			return
		var n: int = combat._hand.size()
		if n == last:
			stable += 1
			if stable >= STABLE_TICKS:
				return
		else:
			stable = 0
			last = n
		await create_timer(SETTLE_TICK).timeout
		waited += 1


func _play_what_we_can() -> void:
	await _drink_something()
	for _pass in 10:
		if not is_instance_valid(combat):
			return
		var played := false
		for card in combat._hand.duplicate():
			if card == null or not is_instance_valid(card):
				continue
			if not (card.is_creature() or card.is_spell()):
				continue
			var cost: int = combat._effective_cost(card)
			if cost > combat.player_mana:
				continue
			if card.is_spell():
				if not await _cast_spell(card):
					continue
			else:
				var slot: Control = _first_empty_slot()
				if slot == null:
					continue
				card.global_position = slot.get_global_rect().get_center() - card.size * 0.5
				combat._on_card_played(card)
			await create_timer(0.05).timeout
			played = true
			break
		if not played:
			return


## Returns true if the cast was attempted. A targeted spell is resolved with a
## click on a live body — the same path `_input` drives.
func _cast_spell(card: Control) -> bool:
	combat._on_card_played(card)
	await create_timer(0.05).timeout
	if not is_instance_valid(combat):
		return false
	if combat._targeting_spell == null:
		return true                     # untargeted, already resolved (or refused)
	var pool: Array = combat._all_enemy_creatures()
	if pool.is_empty():
		pool = combat._all_player_creatures()
	for t in pool:
		if t != null and is_instance_valid(t) and t.current_hp > 0:
			combat._try_resolve_target(combat._card_center(t))
			await create_timer(0.05).timeout
			if combat._targeting_spell == null:
				return true
	combat._cancel_targeting()
	return false


func _drink_something() -> void:
	if not is_instance_valid(combat):
		return
	var belt: Array = combat._ctx_potions()
	if belt.is_empty():
		return
	combat._use_combat_potion(0)
	await create_timer(0.08).timeout
	if is_instance_valid(combat) and combat._targeting_potion_idx >= 0:
		var pool: Array = combat._all_player_creatures()
		if pool.is_empty():
			combat._cancel_potion_targeting()
			return
		combat._try_resolve_potion_target(combat._card_center(pool[0]))
		await create_timer(0.08).timeout
		if is_instance_valid(combat) and combat._targeting_potion_idx >= 0:
			combat._cancel_potion_targeting()


func _first_empty_slot() -> Control:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			if arr[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


## Drive one match to its end (or the turn budget). Returns the rounds observed.
func _drive(style: int, max_turns: int) -> int:
	var turns := 0
	var stalls := 0
	while turns < max_turns:
		if not is_instance_valid(combat) or combat._net_match_over:
			break
		var mine: bool = false
		if style == NM.STYLE_SEALED:
			mine = combat._sorcery_active == NM.local_player_index \
				or (combat._sorcery_active < 0 and not combat._sealed_await_foe \
					and combat.phase == combat.Phase.PLAYER_TURN)
		else:
			mine = combat._net_active_index == NM.local_player_index \
				and combat.phase == combat.Phase.PLAYER_TURN
		if not mine:
			stalls += 1
			if stalls > 400:
				_notes.append("STALL: no local turn for 400 ticks (style %d)" % style)
				break
			await create_timer(0.05).timeout
			continue
		stalls = 0
		turns += 1
		await _settle_hand()
		await _play_what_we_can()
		if not is_instance_valid(combat) or combat._net_match_over:
			break
		_peak_mine = maxi(_peak_mine, _count(false))
		# THE BUTTON MUST NAME ITS CONSEQUENCE. Every alternating turn ends in a
		# one-directional strike EXCEPT the opener's very first — `_net_finish_placement`
		# gates on exactly `_net_turn_round > 1 or _net_placed_count >= 2`. A button
		# reading END TURN ("commit your turn without a clash", per its own tooltip)
		# that then sends your whole line across the board is the button lying about
		# what it does. Checked live rather than by reading the label logic, because
		# the label is set in one place and the strike decided in another.
		if style == NM.STYLE_ALTERNATING and combat._end_turn_btn != null \
				and combat._net_turn_round > 1:
			var act := String(combat._end_turn_btn.get_meta("primary_action", ""))
			if act != "clash" and not _btn_flagged:
				_btn_flagged = true
				_notes.append("round %d commit button says '%s', not 'clash'" % [
					combat._net_turn_round, act])
		print("    turn %d (r%d): mine=%d theirs=%d hand=%d mana=%d hp %d/%d" % [
			turns, combat._net_turn_round, _count(false), _count(true),
			combat._hand.size(), combat.player_mana,
			combat.player_hp, combat.enemy_hp])
		combat._net_on_done_placing()
		await create_timer(0.35).timeout
	return turns


## DOES THE PRACTICE BOT EVER RUN OUT OF CARDS?
##
## Its hand was drawn by a one-way cursor walking `slot.deck` with no wrap and no
## reshuffle, while BOTH other draw paths recycle their discard when the pile runs
## dry (`Combat.draw_one`, `NetPlayerState.draw_one`). Past roughly turn eight the
## cursor hit the end of a 20-card list and the bot simply stopped fielding anything
## for the rest of the match — which reads as the AI giving up.
##
## Drawn far past the deck size here, because that is the state a long match reaches.
## The uid check is the other half: entity_id IS the deck uid for a drafted creature,
## so a recycled card handed out under its original uid would collide with the copy
## still standing on the board.
func _bot_endurance() -> void:
	print("\n[soak] === BOT ENDURANCE ===")
	if not await _boot(NM.STYLE_ALTERNATING, 5150, 0):
		_check(false, "endurance booted")
		return
	var slot = SS.get_slot(1)
	var deck_n: int = slot.deck.size() if slot != null else 0
	var seen_uids: Dictionary = {}
	var drawn: int = 0
	var dupes: int = 0
	# Drain and refill many times over — five full laps of the deck.
	for _cycle in deck_n * 5:
		combat._bot_hand.clear()
		combat.net._bot_refill_hand()
		if combat._bot_hand.is_empty():
			break
		for e in combat._bot_hand:
			drawn += 1
			var u: int = int(e.get("uid", -1))
			if seen_uids.has(u):
				dupes += 1
			seen_uids[u] = true
	print("[soak] endurance: deck=%d drawn=%d unique_uids=%d dupes=%d" % [
		deck_n, drawn, seen_uids.size(), dupes])
	_check(deck_n > 0, "the bot has a deck at all")
	_check(drawn > deck_n * 3,
		"the bot keeps drawing well past its deck size (drew %d from %d)" % [drawn, deck_n])
	_check(dupes == 0,
		"every card the bot draws carries a unique id (%d collisions)" % dupes)
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.4).timeout


## THE BUSIEST CLASH THE GAME CAN STAGE, measured against the envelope cap.
##
## A real match rarely fills the board, so the soak above peaks nowhere near
## `NetProtocol.MAX_ARRAY_ITEMS`. The number that matters is the WORST case: every
## slot occupied on both sides (4 front + 4 back each), keywords that each add
## their own chip to the reel, and the SIMULTANEOUS pass (`_net_run_clash(-1)`,
## the sealed style's form) where both lines swing in one segment instead of two.
## If that fits with headroom the cap is genuinely safe; if it does not, a busy
## clash is dropped whole by `validate_envelope` and the watcher sees no fight.
func _worst_case_reel() -> void:
	print("\n[soak] === WORST-CASE CLASH REEL ===")
	_sample_tag = "worst-case"
	if not await _boot(NM.STYLE_SEALED, 60613, 1):
		_check(false, "worst-case booted")
		return
	# Chip-generating keywords on both sides: thorns bites back, poison and
	# lifelink each raise their own callout, piercing logs a skewer entry.
	var kits: Array = [
		["thorns"], ["poison"], ["piercing"], ["lifelink"],
		["thorns", "poison"], ["piercing", "lifelink"], ["thorns"], ["poison"],
	]
	var eid := 9000
	for is_enemy in [false, true]:
		var i := 0
		for row in [combat.ROW_FRONT, combat.ROW_BACK]:
			for lane in range(combat.LANES_PER_ROW):
				var d: Dictionary = SS.skirmish_card_data("brute").duplicate(true)
				d["id"] = "wc_%d" % eid
				d["name"] = "Worst%d" % eid
				d["atk"] = 4
				d["hp"] = 6
				d["keywords"] = (kits[i % kits.size()] as Array).duplicate()
				combat.net._net_spawn_creature(d, eid, lane, row, is_enemy, false)
				eid += 1
				i += 1
	await create_timer(0.3).timeout
	var staged: int = _count(false) + _count(true)
	_check(staged == 16, "worst case staged a full 8-a-side board (%d bodies)" % staged)
	for c in combat._all_creatures_both_sides():
		if is_instance_valid(c):
			c.state.ready_to_swing = true      # the muster delay would hold every arrival
			c.has_attacked_this_turn = false
	var before: int = _peak_reel
	_peak_reel = 0                              # measure THIS clash, not the match above
	await combat.net._net_run_clash(-1)
	await create_timer(0.6).timeout
	var cap: int = load("res://scripts/net/NetProtocol.gd").MAX_ARRAY_ITEMS
	print("[soak] worst-case peak reel: %d entries (cap %d)" % [_peak_reel, cap])
	_check(_peak_reel > 0, "the worst-case clash produced a reel at all")
	_check(_peak_reel <= cap,
		"the worst-case reel fits the envelope (%d <= %d)" % [_peak_reel, cap])
	if _peak_reel > cap / 2:
		_notes.append("WORST-CASE reel %d of %d — under half the cap is the safe band"
			% [_peak_reel, cap])
	_peak_reel = maxi(_peak_reel, before)
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.4).timeout


## A BEST-OF-3 DRILL, PLAYED THROUGH THE RELAUNCH.
##
## `_probe_net_rematch` proves the between-games handshake FIRES; it says nothing
## about whether the next game is playable. The relaunch is a real
## `change_scene_to_file`, so game 2 is a different Combat instance built from the
## kept decks and the carried series tally — and every piece of state that survives
## that boundary (slot decks, drafted arsenals, `series_game` feeding `_combat_seed`,
## the authority seed) is state nothing else in the suite crosses.
func _best_of_three() -> void:
	print("\n[soak] === BEST OF 3 (drill, through the relaunch) ===")
	_sample_tag = "bo3"
	if not await _boot(NM.STYLE_ALTERNATING, 24601, 2):
		_check(false, "bo3 booted")
		return
	# Switch the match to a series AFTER boot so game 1 runs normally.
	SS.best_of = 3
	NM.best_of = 3
	SS.reset_series()
	var deck_before: int = SS.get_slot(0).deck.size()
	var relics_before: Array = (SS.get_slot(0).relics as Array).duplicate()

	var turns: int = await _drive(NM.STYLE_ALTERNATING, 60)
	_check(turns >= 2, "bo3 game 1 was played (%d turns)" % turns)
	_check(combat._net_match_over, "bo3 game 1 reached a verdict")
	_check(SS.series_wins[0] + SS.series_wins[1] == 1,
		"exactly one game is on the board (%d-%d)" % [SS.series_wins[0], SS.series_wins[1]])
	_check(SS.series_leader() == -1,
		"the series is still live after game 1 of 3")

	# The interstitial holds the standing ~2.8s, then drives the handshake itself.
	# `_combat_attached` going false is the relaunch (see _probe_net_rematch).
	var waited := 0.0
	while NM._combat_attached and waited < 10.0:
		await create_timer(0.2).timeout
		waited += 0.2
	_check(not NM._combat_attached, "the drill rolled on by itself (%.1fs)" % waited)

	# WHAT THIS CAN AND CANNOT ASSERT. `_enter_combat_local` ends in
	# `change_scene_to_file`, and that call is INERT in a `--script` SceneTree run:
	# it returns OK and never installs anything (verified against an unrelated
	# scene — `current_scene` simply stays null while the old scene is freed). So
	# the engine's swap is out of reach here, and testing it would be testing the
	# engine anyway — every screen transition in the game uses the same call.
	# What IS in reach, and is the part that could actually be wrong, is the STATE
	# the relaunch hands game 2: the series counter, the kept decks and arsenals,
	# and the refreshed heroes. Assert those, then boot game 2 exactly as
	# `_enter_combat_local` would and prove it plays.
	_check(SS.series_game == 2, "the series advanced to game 2 (series_game=%d)" % SS.series_game)
	_check(SS.get_slot(0).deck.size() == deck_before,
		"the drafted deck carried into game 2 (%d cards)" % SS.get_slot(0).deck.size())
	_check((SS.get_slot(0).relics as Array) == relics_before,
		"the drafted arsenal carried into game 2")
	_check(int(SS.get_slot(0).hero_hp) == SS.START_HP \
			and int(SS.get_slot(1).hero_hp) == SS.START_HP,
		"both heroes were refreshed to full for game 2 (%d/%d)" % [
			SS.get_slot(0).hero_hp, SS.get_slot(1).hero_hp])
	_check(NM.entities.is_empty(),
		"the entity registry was cleared for game 2 (%d left)" % NM.entities.size())

	# Boot game 2 the way the relaunch would have.
	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0
	root.add_child(combat)
	root.get_tree().current_scene = combat
	await create_timer(0.5).timeout
	if is_instance_valid(combat) and combat._hand.is_empty():
		combat._net_begin_combat()
	_check(int(combat.player_hp) == SS.START_HP and int(combat.enemy_hp) == SS.START_HP,
		"game 2 opened at full HP on both sides (%d/%d)" % [
			combat.player_hp, combat.enemy_hp])

	# Wait for game 2's deal, then actually play it out.
	var last := -1
	var stable := 0
	for _i in 60:
		await create_timer(0.2).timeout
		if not is_instance_valid(combat):
			break
		var n: int = combat._hand.size()
		stable = stable + 1 if n == last and n > 0 else 0
		last = n
		if stable >= 4:
			break
	_check(is_instance_valid(combat) and combat._hand.size() > 0,
		"game 2 dealt an opening hand (%d cards)" % (
			combat._hand.size() if is_instance_valid(combat) else -1))
	_peak_mine = 0
	var t2: int = await _drive(NM.STYLE_ALTERNATING, 60)
	_check(t2 >= 2, "bo3 game 2 was actually playable (%d turns)" % t2)
	_check(_peak_mine > 0, "the local player fielded creatures in game 2")
	_check(SS.series_wins[0] + SS.series_wins[1] >= 2,
		"game 2 was recorded on the series (%d-%d)" % [
			SS.series_wins[0], SS.series_wins[1]])
	# Leave the series behind for anything that runs after this.
	SS.best_of = 1
	NM.best_of = 1
	SS.reset_series()
	if is_instance_valid(combat):
		combat.queue_free()
	await create_timer(0.5).timeout


func _count(is_enemy: bool) -> int:
	var n := 0
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for c in combat._row_array(is_enemy, row):
			if c != null and is_instance_valid(c):
				n += 1
	return n


func _run() -> void:
	print("[soak] start")
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	US = root.get_node_or_null("UserSettings")
	if SS == null or NM == null:
		print("[soak] FATAL: autoloads missing"); _finish(1); return
	if US != null:
		US.anim_speed = 3.0
		US.reduce_motion = true
		US.end_turn_warning = false
		US.clash_dwell_scale = 1.0

	var runs: Array = []
	for style_spec in [[NM.STYLE_ALTERNATING, "ALTERNATING"], [NM.STYLE_SEALED, "SEALED"]]:
		for i in 3:
			runs.append([style_spec[0], "%s#%d" % [String(style_spec[1]), i + 1],
				991_733 + i * 7919, i])
	for spec in runs:
		var style: int = int(spec[0])
		var tag := String(spec[1])
		print("\n[soak] === %s ===" % tag)
		_sample_tag = tag
		if not await _boot(style, int(spec[2]), int(spec[3])):
			_check(false, "%s booted" % tag)
			continue
		_check(combat._is_net() and combat._is_host(), "%s booted as a NET HOST" % tag)
		_peak_mine = 0
		var turns: int = await _drive(style, 60)
		print("[soak] %s: %d local turns, round %d, hp %d/%d, over=%s" % [
			tag, turns, combat._net_turn_round,
			combat.player_hp, combat.enemy_hp, str(combat._net_match_over)])
		_check(turns >= 3, "%s played at least three turns" % tag)
		# THE REGRESSION THIS FILE WAS WRITTEN FOR. Sealed Orders sets
		# `_net_active_index = -1` during the orders phase on purpose, and
		# `_on_card_played`'s turn gate used to refuse every card because of it —
		# a whole battle style in which no creature could ever be seated. Every
		# other net probe stages a board directly, so none of them could see it.
		_check(_peak_mine > 0,
			"%s: the local player actually got creatures onto the board" % tag)
		_check(combat._net_match_over,
			"%s: the match reached a verdict inside the turn budget" % tag)
		if style == NM.STYLE_SEALED:
			_check(_saw_orders_phase and _saw_sorcery_step,
				"%s: the SEALED flow really ran (orders=%s, spell step=%s)" % [
					tag, str(_saw_orders_phase), str(_saw_sorcery_step)])
			_saw_orders_phase = false
			_saw_sorcery_step = false
		if is_instance_valid(combat):
			combat.queue_free()
		await create_timer(0.5).timeout

	await _bot_endurance()
	await _worst_case_reel()
	await _best_of_three()

	# THE REEL MUST FIT THE ENVELOPE. `NetProtocol.MAX_ARRAY_ITEMS` bounds every
	# array that crosses the wire, and `EV_CLASH` ships the whole strike reel as ONE
	# array — so a clash that overruns it is not truncated, it is REJECTED whole by
	# `validate_envelope` ("payload_shape"), and the watching peer's screen snaps
	# straight to the outcome with no fight in between. Reported with real headroom
	# rather than asserted at the limit, because the reel grows with board size,
	# keyword chips and second-swing phases, not with anything this soak controls.
	var cap: int = load("res://scripts/net/NetProtocol.gd").MAX_ARRAY_ITEMS
	print("\n[soak] peak EV_CLASH reel: %d entries (cap %d) — worst at %s" % [
		_peak_reel, cap, _peak_reel_where if _peak_reel_where != "" else "n/a"])
	_check(_peak_reel > 0, "the soak actually observed a clash reel")
	_check(_peak_reel <= cap,
		"the biggest clash reel still fits NetProtocol's array cap (%d <= %d)" % [
			_peak_reel, cap])
	if _peak_reel > cap / 2:
		_notes.append("reel peaked at %d of %d — over half the envelope cap" % [
			_peak_reel, cap])

	for n in _notes:
		print("  NOTE  ", n)
	print("\n[soak] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	_finish(1 if _fails > 0 else 0)
