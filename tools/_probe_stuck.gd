extends SceneTree
## Stuck-screen finder (2026-06-28) — frame-accurate.
##
## Walks every EVENT choice (top-level, follow_up) by driving the REAL Event
## scene in-tree: builds the choice screen, resolves the choice, AWAITS two
## frames so deferred queue_free() actually clears the prior screen, then
## classifies what remains.
##
## A screen is OK if, after the prior screen has been freed, ANY holds:
##   - a scene transition was started (fade overlay parented to root), OR
##   - the event subtree still holds a Button wired to `pressed`.
## Otherwise it is STUCK (dead end, nothing to click).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_stuck.gd

var RS: Node
var CDB: Node
var EVENTS: Dictionary = {}
var _stuck: Array = []
var _tested := 0
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	# Return false every frame so the async _run() coroutine can resume across
	# frames; _run() calls quit() itself when finished.
	return false


func _run() -> void:
	print("[stuck] start")
	RS  = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	if RS == null or CDB == null:
		print("[stuck] FATAL: autoloads missing"); quit(1); return

	var EvScript = load("res://scripts/scenes/Event.gd")
	EVENTS = EvScript.EVENTS

	var ids: Array = EVENTS.keys(); ids.sort()
	for id in ids:
		var data: Dictionary = EVENTS[id]
		await _test_node(String(id), data, data)

	print("[stuck] ============ SUMMARY ============")
	print("[stuck] choices tested : %d" % _tested)
	if _stuck.is_empty():
		print("[stuck] no dead-end screens found")
	else:
		print("[stuck] STUCK screens (%d):" % _stuck.size())
		for s in _stuck:
			print("   - " + s)
	print("[stuck] DONE")
	quit(0)


func _test_node(event_id: String, event_data: Dictionary, node: Dictionary) -> void:
	var choices: Array = node.get("choices", [])
	for ci in range(choices.size()):
		var choice: Dictionary = choices[ci]
		var tag := "%s :: choice[%d] %s" % [event_id, ci,
			String(choice.get("label", choice.get("tell", "?"))).split("\n")[0]]

		if choice.has("follow_up"):
			await _test_node(event_id, event_data, choice["follow_up"])
			continue

		_tested += 1
		_fixture_rich()
		var ev = load("res://scenes/event.tscn").instantiate()
		root.add_child(ev)
		ev._event_id = event_id
		ev._event_data = event_data
		ev._current_node = node
		ev._build_ui()
		ev._resolve_choice(choice)

		# Let deferred queue_free() from _clear_ui() actually run, so stale
		# buttons from the prior screen don't inflate the count.
		await process_frame
		await process_frame

		var transitioned := _root_has_fade_overlay()
		var live_buttons := _count_wired_buttons(ev)
		if not transitioned and live_buttons == 0:
			_stuck.append(tag + "   [no exit, no buttons]")

		_clear_fade_overlays()
		ev.free()


func _root_has_fade_overlay() -> bool:
	for c in root.get_children():
		if c is ColorRect and c.z_index >= 1000:
			return true
	return false


func _clear_fade_overlays() -> void:
	for c in root.get_children():
		if c is ColorRect and c.z_index >= 1000:
			c.free()


func _count_wired_buttons(n: Node) -> int:
	var total := 0
	if n is Button and (n as Button).pressed.get_connections().size() > 0:
		total += 1
	for c in n.get_children():
		total += _count_wired_buttons(c)
	return total


func _fixture_rich() -> void:
	RS.start_new_run("raider", 0, 4242)
	RS.gold = 500
	RS.hero_hp = RS.hero_max_hp
	RS.add_potion("healing")
	RS.add_card(CDB.random_curse_id())
