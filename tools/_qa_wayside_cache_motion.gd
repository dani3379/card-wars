extends SceneTree

var _started := false
var _fails := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_fails += 1
		print("  FAIL  " + label)


func _settle(frames := 3) -> void:
	for _i in frames:
		await process_frame


func _run() -> void:
	var rs: Node = root.get_node_or_null("RunState")
	if rs == null:
		print("  FAIL  RunState autoload exists")
		quit(1)
		return
	rs.start_new_run("raider", 0, 9393)
	rs.current_wayside_id = "supply_cache"
	var wayside = load("res://scenes/wayside.tscn").instantiate()
	root.add_child(wayside)
	await _settle()

	wayside._on_cache_take("free_lance")
	_check(String(rs.next_combat_gift_creature.get("name", "")) == "Free Lance",
		"Free Lance reward applies synchronously")
	_check(not wayside._cache_taken, "non-card reward releases the cache latch")

	var deck_before: int = rs.deck.size()
	wayside._on_cache_take("commission")
	await _settle()
	_check(rs.deck.size() == deck_before + 1, "commission adds exactly one card")
	_check(not wayside._cache_taken, "card reward releases the cache latch")

	deck_before = rs.deck.size()
	wayside._on_cache_take("banner_case")
	await _settle()
	_check(rs.deck.size() == deck_before + 1, "banner case adds exactly one card")
	_check(not wayside._cache_taken, "second card reveal can reuse the same scene")

	var command_before: int = rs.next_combat_mana_bonus
	wayside._on_cache_take("dispatches")
	_check(rs.next_combat_mana_bonus == command_before + 1,
		"dispatches apply exactly once")
	_check(not wayside._cache_taken, "dispatches release the cache latch")

	wayside.queue_free()
	await _settle()
	print("[wayside-cache] %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
