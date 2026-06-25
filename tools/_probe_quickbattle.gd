extends SceneTree
## Regression probe for the Quick Battle vs-bot hang ("Opponent: waiting" forever).
## Quick Battle is the only mode with a TWO-step handshake — a "ready" gate, THEN
## the "finished" deck handoff. The bot must echo BOTH or the lobby never launches.
## Run: Godot..._console.exe --headless --path "D:\Godot" --script res://tools/_probe_quickbattle.gd

var _pass := 0
var _fail := 0
var _got_ready := false
var _got_finished_cards := -1


func _check(cond: bool, label: String) -> void:
	if cond: _pass += 1; print("  ok   ", label)
	else: _fail += 1; print("  FAIL ", label)


## Records what the (emulated) opponent answers back over the draft channel.
func _on_evt(ev: Dictionary) -> void:
	var t := String(ev.get("t", ""))
	if t == "ready":
		_got_ready = true
	elif t == "finished":
		_got_finished_cards = (ev.get("cards", []) as Array).size()


func _initialize() -> void:
	var NM = root.get_node_or_null("NetMatch")
	var SS = root.get_node_or_null("SkirmishState")
	var BOT = root.get_node_or_null("SkirmishBot")
	if NM == null or SS == null or BOT == null:
		print("[quickbattle] FATAL: autoloads missing"); quit(); return

	NM.start_vs_bot(SS.MatchMode.QUICK, 1)
	SS.begin_session()
	NM.draft_event_received.connect(_on_evt)

	# 1. Player presses READY → NetQuick sends {"t":"ready"}. The bot must echo it so
	#    NetQuick's both-ready gate (_remote_ready) clears.
	NM.send_draft_event({"t": "ready"})
	await process_frame
	await process_frame
	_check(_got_ready, "bot echoes 'ready' so Quick Battle's both-ready gate clears")

	# 2. Both-ready → NetQuick sends {"t":"finished", cards}. The bot must answer with
	#    its own full warband so _remote_finished clears and the host launches combat.
	NM.send_draft_event({"t": "finished", "cards": ["goblin", "goblin"]})
	await process_frame
	await process_frame
	_check(_got_finished_cards == SS.DECK_TARGET,
		"bot answers 'finished' with a full %d-card deck (got %d)" % [SS.DECK_TARGET, _got_finished_cards])

	# 3. Sanity: real multiplayer is untouched — with vs_bot off, send_draft_event must
	#    NOT self-answer (no live peer here, so nothing should come back).
	NM.vs_bot = false
	_got_ready = false
	NM.send_draft_event({"t": "ready"})
	await process_frame
	await process_frame
	_check(not _got_ready, "with vs_bot off, no self-answer (multiplayer path unchanged)")

	print("[quickbattle] RESULT: %d passed, %d failed" % [_pass, _fail])
	quit()
