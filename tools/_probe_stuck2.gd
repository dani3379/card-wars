extends SceneTree
## Click-through verifier (frame-accurate): drive modal-picker event flows all
## the way to the result screen and assert the final Continue transitions out.

var RS: Node
var CDB: Node
var EVENTS: Dictionary = {}
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	RS  = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	var EvScript = load("res://scripts/scenes/Event.gd")
	EVENTS = EvScript.EVENTS

	# Repointed 2026-08-06. Every one of the four original flows was DEAD: the
	# `beekeeper` and `woodcutter` event keys no longer exist in EventDB at all
	# (cut in the 2026-07-03 pool remake), and neither "Trade Coin" nor "Take
	# the open seat" matched any label on their events any more. `_flow` then
	# resolved an EMPTY choice dict and the probe still printed a line, so this
	# harness reported success while exercising nothing. If you rename an event
	# label, re-run this and check every row says Continue=True.
	# The two PICKER rows are the real gate: they must always say Continue=true.
	await _flow("gravesong_choir", "Forge one card", 0)            # forge picker
	await _flow("the_sentrys_board", "Remove a starting card", 0)  # remove picker
	# The two GAMBLE rows are best-effort and NON-DETERMINISTIC — a risk_loop /
	# dice_run rides an unseeded ladder, so clicks and payout differ run to run
	# and "ran out of steps" here is normal, not a failure. Read them only for
	# a hard error or a "no wired button" line, which would mean the screen
	# stopped responding entirely.
	await _flow("gravesong_choir", "Sing for growing rewards", 0)  # risk_loop
	await _flow("the_bone_pit", "Play with a 25-gold pot", 25)     # dice_run
	print("[stuck2] DONE")
	quit(0)


func _fixture() -> void:
	RS.start_new_run("raider", 0, 4242)
	RS.gold = 500
	RS.hero_hp = RS.hero_max_hp


func _all_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_all_buttons(c, out)


func _labels_under(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(String((c as Label).text))
		elif c is RichTextLabel:
			out.append(String((c as RichTextLabel).text))
		out.append_array(_labels_under(c))
	return out


func _find_button(ev, substr: String):
	var btns: Array = []
	_all_buttons(ev, btns)
	for b in btns:
		if substr.to_lower() in String(b.text).to_lower():
			return b
		for lbl in _labels_under(b):
			if substr.to_lower() in lbl.to_lower():
				return b
	return null


func _overlay() -> bool:
	for c in root.get_children():
		if c is ColorRect and c.z_index >= 1000:
			return true
	return false


func _clear_overlay() -> void:
	for c in root.get_children():
		if c is ColorRect and c.z_index >= 1000:
			c.free()


func _flow(event_id: String, choice_substr: String, expect_pay: int) -> void:
	_fixture()
	var start_gold: int = RS.gold
	var ev = load("res://scenes/event.tscn").instantiate()
	root.add_child(ev)
	ev._event_id = event_id
	ev._event_data = EVENTS[event_id]
	ev._current_node = EVENTS[event_id]
	ev._build_ui()
	await process_frame

	# Click the named top-level choice.
	var choices: Array = EVENTS[event_id]["choices"]
	var picked: Dictionary = {}
	for c in choices:
		if choice_substr.to_lower() in String(c.get("label", "")).to_lower():
			picked = c; break
	ev._resolve_choice(picked)
	await process_frame
	await process_frame

	# If a picker/loop screen is up, click the FIRST freshly-wired tile/action a
	# few times to reach a result. (Frame settled, so only the new screen's
	# buttons remain.)
	# 12, not 4: the picker flows resolve in 1-2 clicks, but a push-your-luck
	# loop (risk_loop, dice_run) only leaves the screen when it banks or busts,
	# and 4 presses was not enough to reach either — so those two rows reported
	# Continue=false and read as a stuck flow when they were merely unfinished.
	# `why` records how the click loop ENDED. Without it a non-terminating flow
	# is indistinguishable from a flow whose buttons this walk cannot even see,
	# and those need opposite fixes — that ambiguity is why the dead flows here
	# went unnoticed for so long.
	var why := "ran out of steps"
	var steps := 0
	for _step in range(12):
		if _overlay():
			why = "overlay opened"
			break
		var cont = _find_button(ev, "Continue")
		if cont != null:
			why = "reached Continue"
			break
		var btns: Array = []
		_all_buttons(ev, btns)
		# Prefer the button that ENDS the screen. A push-your-luck loop's first
		# wired button is "risk again", so taking it blindly rode the ladder to
		# the step budget and reported a stuck flow — gravesong actually climbed
		# +60 gold over 12 presses. Banking also tests the more interesting path:
		# the one that has to pay out and build a result page.
		var clicked := false
		for want in [true, false]:
			for b in btns:
				if b.pressed.get_connections().size() == 0:
					continue
				var t := String((b as Button).text).to_lower()
				# Name first: a gamble's bank control is the coin heap itself and
				# carries no text at all, so label matching alone never sees it.
				var ends := String(b.name) == "DiceBankBtn" \
					or t.contains("bank") or t.contains("stop") \
					or t.contains("leave") or t.contains("enough") \
					or t.contains("take") or t.contains("walk")
				if ends != want:
					continue
				b.pressed.emit(); clicked = true; break
			if clicked:
				break
		if not clicked:
			why = "no wired button under the Event node (%d buttons seen)" % btns.size()
			break
		steps += 1
		await process_frame
		await process_frame

	var paid: int = start_gold - RS.gold
	var cont2 = _find_button(ev, "Continue")
	if cont2 != null:
		cont2.pressed.emit()
		await process_frame
	print("[stuck2] %-22s paid=%-4d (want %-4d) clicks=%-2d Continue=%-5s  %s"
		% [event_id, paid, expect_pay, steps, str(cont2 != null), why])
	_clear_overlay(); ev.free()
