extends SceneTree
## vs-bot integration probe. Verifies the practice opponent end to end:
##   1. SkirmishBot.build_deck() yields a full, skirmish-legal warband.
##   2. SavedDecks round-trips a named deck (save → list → delete).
##   3. In a LIVE combat scene the bot takes its turn, seats creatures on its
##      board, and passes the turn back to the host.
## Run: Godot..._console.exe --headless --path "D:\Godot" --script res://tools/_probe_vsbot.gd

var SS: Node
var NM: Node
var BOT: Node
var DECKS: Node
var combat
var _pass := 0
var _fail := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ok   ", label)
	else:
		_fail += 1
		print("  FAIL ", label)


func _initialize() -> void:
	_run()


func _run() -> void:
	SS = root.get_node_or_null("SkirmishState")
	NM = root.get_node_or_null("NetMatch")
	BOT = root.get_node_or_null("SkirmishBot")
	DECKS = root.get_node_or_null("SavedDecks")
	if SS == null or NM == null or BOT == null or DECKS == null:
		print("[vsbot] FATAL: autoloads missing"); quit(); return

	# 1. Deck builder.
	var deck: Array = BOT.build_deck(12345)
	_check(deck.size() == SS.DECK_TARGET,
		"build_deck() returns %d cards (got %d)" % [SS.DECK_TARGET, deck.size()])
	var legal: Array = SS.skirmish_legal_pool()
	var all_legal := true
	for id in deck:
		if not legal.has(id):
			all_legal = false
	_check(all_legal, "every bot card is skirmish-legal")

	# 2. SavedDecks round-trip.
	DECKS.save_deck("ProbeDeck", deck)
	var found := false
	for d in DECKS.list_decks():
		if String(d.get("name", "")) == "ProbeDeck" and (d.get("cards", []) as Array).size() == deck.size():
			found = true
	_check(found, "SavedDecks persisted + listed ProbeDeck")
	for i in range(DECKS.count() - 1, -1, -1):
		if DECKS.deck_name(i) == "ProbeDeck":
			DECKS.delete_deck(i)   # don't pollute the real list

	# 3. Live combat — the bot takes a turn.
	NM.start_vs_bot(SS.MatchMode.QUICK, 1)
	SS.begin_session()
	for cid in BOT.build_deck(111):
		SS.add_card_to(0, cid)   # human (slot 0)
	for cid in BOT.build_deck(222):
		SS.add_card_to(1, cid)   # bot (slot 1)

	combat = load("res://scenes/combat.tscn").instantiate()
	combat._net_first_player_override = 0   # host opens round 1 (deterministic — the bot
	# then places SECOND, during the monitored wait loop, so the board sample is reliable)
	root.add_child(combat)
	await create_timer(0.6).timeout
	# combat._ready parks on the headless texture prebake; kick the net handshake
	# directly (idempotent — guarded by _net_signals_wired).
	if not combat._net_signals_wired:
		combat._net_begin_combat()
	# Wait until round 1 has genuinely OPENED (not just the default state) AND it is the
	# host's placement turn. _net_begin_combat opens round 1 on a 0.6 s delay; since
	# _net_active_index defaults to 0, a bare "while active != 0" would fall through
	# before the round opens and race the delayed _net_begin_round(1). Gate on the round
	# counter too. If the bot is the coin-flip's first placer, this also waits out its
	# opening turn (it auto-places, then hands to the host → active=0).
	var t := 0
	while (int(combat._net_turn_round) < 1 or int(combat._net_active_index) != 0) and t < 60:
		await create_timer(0.1).timeout
		t += 1
	_check(combat.combat_mode == combat.CombatMode.NET_HOST, "combat booted in NET_HOST mode")
	_check(SS.vs_bot, "SkirmishState.vs_bot carried into combat")
	_check(int(combat._net_active_index) == 0, "opening turn is the host's (active=0)")

	# Finish the host's opening placement → the bot takes ITS placement turn (active=1)
	# → once both have placed, the host runs the simultaneous clash → round advances.
	# The bot ANIMATES each creature out of its hand (~0.4 s per play), so poll on
	# _bot_turns_taken (a latching "the bot finished a turn" counter) rather than a
	# fixed wait. Snapshot the bot's peak board size before the clash can cull it.
	var bot_peak := 0
	combat._net_finish_placement(0)
	var waited := 0
	while int(combat._bot_turns_taken) < 1 and not combat._net_match_over and waited < 250:
		await create_timer(0.1).timeout
		var live := 0
		for row in [0, 1]:
			for n in combat._row_array(true, row):
				if n != null and is_instance_valid(n):
					live += 1
		bot_peak = maxi(bot_peak, live)
		waited += 1
	_check(int(combat._bot_turns_taken) >= 1 or combat._net_match_over,
		"bot took its placement turn (turns=%d)" % int(combat._bot_turns_taken))
	_check(bot_peak > 0, "bot seated creature(s) on its board (peak %d)" % bot_peak)
	# Let the simultaneous clash resolve and the round advance (or the match end).
	var waited2 := 0
	while int(combat._net_turn_round) < 2 and not combat._net_match_over and waited2 < 150:
		await create_timer(0.1).timeout
		waited2 += 1
	_check(int(combat._net_turn_round) >= 2 or combat._net_match_over,
		"clash resolved → round advanced to %d (or match ended)" % int(combat._net_turn_round))

	print("[vsbot] RESULT: %d passed, %d failed" % [_pass, _fail])
	quit()
