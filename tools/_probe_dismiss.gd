extends SceneTree
## Probe for the 2026-07-07 discard rework: HAND_REFILL_TARGET 5, right-click
## MARKS any number of hand cards for discard (toggle; curses exempt), and the
## end-of-turn flush cascades every marked card to the discard pile. Boots a
## SOLO campaign combat and drives _on_card_dismiss_requested +
## _flush_marked_discards directly — the Card2D right-click merely emits the
## signal the handler receives, and the end-turn paths all call the flush.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_dismiss.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()
	return _done


func _run_test() -> void:
	print("[dismiss] start")
	var RS = root.get_node_or_null("RunState")
	if RS == null:
		print("[dismiss] FATAL: RunState missing")
		_finish(1)
		return
	RS.start_new_run("stalwart")
	RS.current_node_type = "combat"
	RS.current_encounter_id = "bandit_camp"
	await create_timer(0.1).timeout

	var combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	# Let the intro + round-1 deal fully settle: the hand deals card-by-card
	# (~80ms apart), so wait until the count is STABLE across two ticks —
	# grabbing it mid-deal races the checks against incoming cards.
	var last_n := -1
	for _tick in 30:
		await create_timer(0.4).timeout
		var n: int = combat._hand.size()
		if n > 0 and n == last_n and combat.phase == combat.Phase.PLAYER_TURN:
			break
		last_n = n
	_check(combat.HAND_REFILL_TARGET == 5, "refill target is 5")
	_check(combat._hand.size() > 0, "hand dealt (%d cards)" % combat._hand.size())
	if combat._hand.is_empty():
		_finish(1)
		return

	# Mark two cards — no per-turn cap any more.
	var a = combat._hand[0]
	combat._on_card_dismiss_requested(a)
	_check(a.marked_for_discard, "right-click marks a card for discard")
	var b = null
	if combat._hand.size() > 1:
		b = combat._hand[1]
		combat._on_card_dismiss_requested(b)
		_check(b.marked_for_discard, "a second mark the same turn is allowed")

	# Toggle: right-click again unmarks.
	combat._on_card_dismiss_requested(a)
	_check(not a.marked_for_discard, "right-click again unmarks")
	combat._on_card_dismiss_requested(a)
	_check(a.marked_for_discard, "re-marking works")

	# Nothing leaves the hand until the flush.
	var h0: int = combat._hand.size()
	var d0: int = combat._player_discard_pile.size()
	_check(h0 == last_n, "marking alone removes nothing from hand")

	var expected: int = 2 if b != null else 1
	var shed: int = combat._flush_marked_discards()
	await create_timer(0.3).timeout
	_check(shed == expected, "flush reported %d discards (got %d)" % [expected, shed])
	_check(combat._hand.size() == h0 - expected, "flush removed the marked cards from hand")
	_check(combat._player_discard_pile.size() == d0 + expected, "flushed cards landed in the discard")

	# Curses can never be shed: forge a synthetic curse card into hand state.
	if combat._hand.size() > 0:
		var mule = combat._hand[0]
		var real_id: String = mule.card_id
		mule.card_id = "curse"
		combat._on_card_dismiss_requested(mule)
		_check(not mule.marked_for_discard, "curse marking refused")
		mule.card_id = real_id

	# Deep Satchel raises the refill target computation (relic exists + value 1).
	var RDB = root.get_node_or_null("RelicDB")
	var satchel: Dictionary = RDB.get_relic("deep_satchel") if RDB != null else {}
	_check(not satchel.is_empty() and int(satchel.get("value", 0)) == 1,
		"Deep Satchel relic registered (+1 refill target)")

	_finish(_fails)


func _finish(code: int) -> void:
	if code == 0:
		print("[dismiss] ALL PASS")
	else:
		print("[dismiss] FAILED: %d checks" % code)
	_done = true
	quit(code)
