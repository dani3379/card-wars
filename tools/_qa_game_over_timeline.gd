extends SceneTree
## Result-screen choreography regression: one monotonic page reveal, stable
## geometry once paint begins, all ink dry before the closing seal, and a fully
## snapped Reduce Motion path.

const TIMEOUT_MS := 5000

var _started := false
var _failures := 0


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 240
	var settings: Node = root.get_node("UserSettings")
	settings.set("particles", false)
	settings.set("reduce_motion", false)
	_prepare_run()
	await _warm_deck()

	var scene: Node = load("res://scenes/game_over.tscn").instantiate()
	root.add_child(scene)
	var last_alpha := 0.0
	var page_monotonic := true
	var page_started_after_verdict := true
	var baseline := Rect2()
	var have_baseline := false
	var max_rect_delta := 0.0
	var seal_seen := false
	var seal_after_ink := true
	var settled := false
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var panel := scene.get_node_or_null("RunSummaryPanel") as Control
		if panel == null or not panel.visible:
			continue
		var alpha := panel.modulate.a
		if alpha + 0.01 < last_alpha:
			page_monotonic = false
		last_alpha = maxf(last_alpha, alpha)
		if alpha > 0.05:
			var title := scene.get_node("Title") as Control
			if title.modulate.a < 0.65:
				page_started_after_verdict = false
			var now := Rect2(panel.position, panel.size)
			if not have_baseline:
				baseline = now
				have_baseline = true
			else:
				max_rect_delta = maxf(max_rect_delta,
					baseline.position.distance_to(now.position))
				max_rect_delta = maxf(max_rect_delta,
					baseline.size.distance_to(now.size))
		var seal := scene.get_node_or_null("ClosingSeal") as Control
		if seal != null and seal.modulate.a > 0.5:
			seal_seen = true
			for ink in _ink_roots(panel):
				if ink.modulate.a < 0.98:
					seal_after_ink = false
		if alpha > 0.99 and seal_seen and seal.scale.is_equal_approx(Vector2.ONE):
			settled = true
			break

	print("[game-over-timeline] alpha=%.3f rect_delta=%.3f seal=%s settled=%s" % [
		last_alpha, max_rect_delta, str(seal_seen), str(settled)])
	_check(page_monotonic, "chronicle opacity never reverses")
	_check(page_started_after_verdict,
		"the verdict is established before the chronicle begins painting")
	_check(have_baseline and max_rect_delta <= 0.5,
		"chronicle geometry is stable once any page paint is visible")
	_check(seal_seen and seal_after_ink,
		"closing seal appears only after every authored ink block is dry")
	_check(settled, "authored result sequence reaches its resting state")

	scene.queue_free()
	for _i in 4:
		await process_frame

	settings.set("reduce_motion", true)
	var reduced: Node = load("res://scenes/game_over.tscn").instantiate()
	root.add_child(reduced)
	for _i in 14:
		await process_frame
	var reduced_panel := reduced.get_node_or_null("RunSummaryPanel") as Control
	var reduced_seal := reduced.get_node_or_null("ClosingSeal") as Control
	var reduced_title := reduced.get_node("Title") as Control
	var reduced_subtitle := reduced.get_node("Subtitle") as Control
	_check(reduced_panel != null and reduced_panel.visible \
			and reduced_panel.modulate.a > 0.99,
		"Reduce Motion snaps the complete chronicle on")
	_check(reduced_title.modulate.a > 0.99 \
			and reduced_title.scale.is_equal_approx(Vector2.ONE) \
			and reduced_subtitle.modulate.a > 0.99,
		"Reduce Motion snaps verdict and subtitle to rest")
	var reduced_ink_ready := reduced_panel != null
	if reduced_panel != null:
		for ink in _ink_roots(reduced_panel):
			if ink.modulate.a < 0.99:
				reduced_ink_ready = false
	_check(reduced_ink_ready, "Reduce Motion leaves no staggered ink")
	_check(reduced_seal != null and reduced_seal.modulate.a > 0.99 \
			and reduced_seal.scale.is_equal_approx(Vector2.ONE),
		"Reduce Motion leaves the seal at its final pose")

	reduced.queue_free()
	for _i in 4:
		await process_frame
	settings.set("reduce_motion", false)
	_finish()


func _prepare_run() -> void:
	var run_state: Node = root.get_node("RunState")
	run_state.start_new_run("raider", 0, 20260927)
	run_state.set("active_slot", -1)
	run_state.set("hero_hp", 0)
	run_state.set("last_run_victorious", false)
	run_state.set("current_floor", 11)
	run_state.set("fights_won", 9)
	run_state.set("gold", 186)
	run_state.set("cause_of_death", "the Kindler")
	run_state.add_relic("whetstone")
	run_state.add_relic("war_horn")
	run_state.set("fallen", [
		{"uid": 9001, "name": "Pikeman the Grim", "enc": "the Bone Pit", "act": 1},
		{"uid": 9002, "name": "Outrider", "enc": "the Kindler", "act": 2},
	])
	run_state.set("creature_kills", {9001: 7})


func _warm_deck() -> void:
	var run_state: Node = root.get_node("RunState")
	var cache: Node = root.get_node("CardTextureCache")
	var datas: Array = []
	var seen := {}
	for i in run_state.deck.size():
		var data: Dictionary = run_state.get_upgraded_card_data(i)
		var key := String(cache.cache_key(data))
		if not seen.has(key):
			seen[key] = true
			datas.append(data)
	await cache.bake_many(datas)


func _ink_roots(panel: Control) -> Array[Control]:
	var out: Array[Control] = []
	var scroll := panel.get_node_or_null("PageScroll")
	if scroll != null and scroll.get_child_count() > 0:
		for child in scroll.get_child(0).get_children():
			if child is Control:
				out.append(child)
	var foot := panel.get_node_or_null("PageFoot")
	if foot != null:
		for child in foot.get_children():
			if child is Control:
				out.append(child)
	return out


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[game-over-timeline] PASS ", message)
	else:
		_failures += 1
		push_error("[game-over-timeline] FAIL " + message)


func _finish() -> void:
	print("[game-over-timeline] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
