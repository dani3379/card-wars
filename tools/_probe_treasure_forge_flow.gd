extends SceneTree
## Headless behavior coverage for Treasure._show_forged_card.
##
## GPU snapshots deliberately do not run under the headless display server, so
## this checks the supported cold-cache fallback as well as the modal's index
## gate and its lifetime guard when the preview is dismissed mid-beat.

var _started := false
var _done := false
var _normal_done := false
var _dismiss_done := false
var _failures := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var run_state = root.get_node_or_null("RunState")
	var cache = root.get_node_or_null("CardTextureCache")
	var card_db = root.get_node_or_null("CardDB")
	var settings = root.get_node_or_null("UserSettings")
	if run_state == null or cache == null or card_db == null or settings == null:
		_fail("required autoload missing")
		_finish()
		return

	run_state.start_new_run("raider", 0, 20260910)
	run_state.active_slot = -1
	run_state.current_node_type = "treasure"
	var old_reduce_motion: bool = settings.reduce_motion
	settings.reduce_motion = true

	var treasure = load("res://scenes/treasure.tscn").instantiate()
	root.add_child(treasure)
	for _i in 3:
		await process_frame

	# A cancelled picker returns -1; an out-of-range result must be equally inert.
	var overlays_before := _forge_overlays(treasure).size()
	treasure._show_forged_card(-1)
	treasure._show_forged_card(run_state.deck.size())
	await process_frame
	_check(_forge_overlays(treasure).size() == overlays_before,
		"cancelled and out-of-range picks create no preview")

	var target := _first_upgradeable(run_state, card_db)
	_check(target >= 0, "starter deck contains a forgeable card")
	if target < 0:
		settings.reduce_motion = old_reduce_motion
		treasure.queue_free()
		_finish()
		return
	run_state.upgrade_card(target, "plus")
	var expected: Dictionary = run_state.get_upgraded_card_data(target)

	_normal_done = false
	_run_reveal(treasure, target, false)
	await process_frame
	var overlays := _forge_overlays(treasure)
	_check(overlays.size() == overlays_before + 1,
		"valid forge creates exactly one blocking preview")
	var overlay: Control = overlays.back() if not overlays.is_empty() else null
	var cards := _card_nodes(overlay)
	_check(cards.size() == 1, "preview contains exactly one card")
	if cards.size() == 1:
		var card = cards[0]
		_check(bool(card.static_display), "preview card is static")
		_check(bool(card.live_baked_mode) and bool(card.gallery_baked_mode),
			"preview requests the native gallery cache class")
		_check(String(card.card_data.get("id", "")) == String(expected.get("id", ""))
			and bool(card.card_data.get("is_upgraded", false)),
			"preview renders the already-upgraded deck entry")
		_check(card.get("_baked_face") == null and card.get_child_count() > 0,
			"headless cache miss falls back to the live card renderer")
	_check(not bool(cache.get("_bake_busy")),
		"headless gallery request does not seize the bake viewport")

	await create_timer(1.05).timeout
	_check(_normal_done, "forge reveal completes after its presentation beat")
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	await process_frame

	# Simulate a modal/scene teardown while the anticipation timer is pending.
	# The wrapper guard should return before forge_strike touches freed controls.
	_dismiss_done = false
	_run_reveal(treasure, target, true)
	await process_frame
	overlays = _forge_overlays(treasure)
	overlay = overlays.back() if not overlays.is_empty() else null
	_check(overlay != null, "dismissal case reaches the preview beat")
	if overlay != null:
		overlay.queue_free()
	await create_timer(0.55).timeout
	_check(_dismiss_done, "dismissed preview exits through its lifetime guard")
	_check(_forge_overlays(treasure).is_empty(),
		"dismissal leaves no forge preview nodes behind")
	_check(not bool(cache.get("_bake_busy")),
		"dismissal leaves the shared bake viewport unlocked")

	settings.reduce_motion = old_reduce_motion
	treasure.queue_free()
	for _i in 3:
		await process_frame
	_finish()


func _run_reveal(treasure: Node, deck_index: int, dismissal_case: bool) -> void:
	await treasure._show_forged_card(deck_index)
	if dismissal_case:
		_dismiss_done = true
	else:
		_normal_done = true


func _first_upgradeable(run_state: Node, card_db: Node) -> int:
	for i in run_state.deck.size():
		if not run_state.has_upgrade_path(i, "plus") \
				and card_db.is_upgradeable(run_state.deck[i]):
			return i
	return -1


func _forge_overlays(host: Node) -> Array[Control]:
	var out: Array[Control] = []
	if host == null or not is_instance_valid(host):
		return out
	for child: Node in host.get_children():
		if child is ColorRect and (child as Control).z_index == 120:
			out.append(child as Control)
	return out


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script = node.get_script()
		if script != null and String(script.resource_path).ends_with("/Card2D.gd"):
			out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[treasure-forge-flow] PASS ", label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	push_error("[treasure-forge-flow] FAIL %s" % label)


func _finish() -> void:
	print("[treasure-forge-flow] RESULT failures=%d" % _failures)
	_done = true
	quit(1 if _failures > 0 else 0)
