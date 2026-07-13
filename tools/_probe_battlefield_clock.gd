extends SceneTree
## Focused contract probe for Card2D's consolidated battlefield visual clock.

var _fails := 0
var _card_script: GDScript


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _make_card(data: Dictionary):
	var card = load("res://scenes/card_2d.tscn").instantiate()
	card.card_id = String(data.get("id", ""))
	card.card_data = data.duplicate(true)
	card.is_on_battlefield = true
	card.compact_mode = true
	root.add_child(card)
	return card


func _live_registry_count() -> int:
	var count := 0
	var refs: Array = _card_script.get("_battlefield_visual_refs")
	for ref_variant in refs:
		var ref = ref_variant as WeakRef
		if ref != null and is_instance_valid(ref.get_ref()):
			count += 1
	return count


func _driver():
	var ref = _card_script.get("_battlefield_visual_driver") as WeakRef
	return ref.get_ref() if ref != null else null


func _run() -> void:
	_card_script = load("res://scripts/Card2D.gd") as GDScript
	_card_script.set("_battlefield_visual_refs", [])
	_card_script.set("_battlefield_visual_driver", null)
	var settings: Node = root.get_node_or_null("UserSettings")
	var db: Node = root.get_node_or_null("CardDB")
	_check(settings != null and db != null, "probe dependencies are present")
	if settings == null or db == null:
		quit(1)
		return
	var old_reduce_motion: bool = settings.reduce_motion
	settings.reduce_motion = true
	var data: Dictionary = db.get_card_data("pikeman")
	var first = _make_card(data)
	var second = _make_card(data)
	await process_frame

	var driver = _driver()
	_check(_live_registry_count() == 2,
		"non-Combat compact cards join one weak battlefield registry")
	_check(driver == first or driver == second,
		"one compact card is elected as the shared visual driver")
	_check(not first.is_processing() and not second.is_processing(),
		"compact cards have no per-instance frame callback")
	_check(driver != null and driver._battlefield_visual_timer != null \
			and is_equal_approx(driver._battlefield_visual_timer.wait_time,
				first.BATTLEFIELD_VISUAL_TICK_SEC),
		"the elected driver owns one 30 Hz timer")

	# The status rail must still catch a mutation that deliberately bypasses
	# update_stat_display, even though Reduce Motion prevents the idle bob.
	var status_card = second if driver == first else first
	var old_sig: String = status_card._status_rail_sig
	status_card.state.has_shield = true
	await create_timer(0.45).timeout
	print("status fallback: old='%s' new='%s' accum=%.3f" % [
		old_sig, status_card._status_rail_sig, status_card._status_poll_accum])
	_check(not status_card._idle_bob_enabled,
		"Reduce Motion keeps decorative bob disabled")
	_check(status_card._status_rail_sig != old_sig \
			and status_card._status_rail_sig.contains("shield"),
		"shared clock preserves the 4 Hz status fallback under Reduce Motion")
	settings.reduce_motion = false
	status_card.enable_idle_bob()
	status_card._bob_time = 0.0
	status_card._bob_phase = 0.0
	status_card._bob_freq = 3.0
	status_card._bob_amplitude = 3.0
	status_card._bob_base_y = status_card.position.y
	_driver()._dispatch_battlefield_visual_tick()
	_check(status_card._bob_time > 0.0 \
			and not is_equal_approx(status_card.position.y, status_card._bob_base_y),
		"shared clock advances the decorative bob at its coarse cadence")

	# Free the elected timer owner while its peer stays alive. PREDELETE must hand
	# the clock over immediately rather than leaving the board visually stale.
	var survivor = second if driver == first else first
	driver.queue_free()
	await process_frame
	await process_frame
	var replacement = _driver()
	_check(replacement == survivor and survivor._battlefield_visual_timer != null,
		"freeing the elected card hands the clock to a survivor")
	_check(_live_registry_count() == 1,
		"driver handoff removes the freed weak entry")

	survivor.queue_free()
	await process_frame
	await process_frame
	_check(_live_registry_count() == 0 and _driver() == null,
		"freeing the final card clears the registry and driver")

	# Real player-play transition: the hand card is already ready, Combat detaches
	# it, marks + rebuilds it compact while off-tree, then seats it. With Reduce
	# Motion the landing's enable_idle_bob call must still register status polling
	# before declining the decorative animation.
	settings.reduce_motion = true
	var transitioned = load("res://scenes/card_2d.tscn").instantiate()
	transitioned.card_id = String(data.get("id", ""))
	transitioned.card_data = data.duplicate(true)
	root.add_child(transitioned)
	await process_frame
	root.remove_child(transitioned)
	transitioned.is_on_battlefield = true
	transitioned.set_compact_mode(true)
	_check(_live_registry_count() == 0,
		"off-tree hand-to-compact rebuild cannot register prematurely")
	root.add_child(transitioned)
	transitioned.enable_idle_bob()
	_check(_live_registry_count() == 1 and _driver() == transitioned \
			and not transitioned._idle_bob_enabled,
		"Reduce Motion landing registers a reattached player card before bob exit")
	var transition_sig: String = transitioned._status_rail_sig
	transitioned.state.is_frozen = true
	await create_timer(0.45).timeout
	_check(transitioned._status_rail_sig != transition_sig \
			and transitioned._status_rail_sig.contains("frozen"),
		"reattached Reduce Motion card retains the 4 Hz status fallback")
	transitioned.queue_free()
	await process_frame
	await process_frame
	_check(_live_registry_count() == 0 and _driver() == null,
		"transitioned card unregisters cleanly")
	settings.reduce_motion = old_reduce_motion
	print("battlefield clock probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
