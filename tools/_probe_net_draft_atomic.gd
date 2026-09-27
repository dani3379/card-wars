extends SceneTree
## Focused headless regression for NetDraft's fixed-slot coordinated reveal.
## Rich Card2D faces may hydrate over several frames, but the player must see
## exactly three stable backs followed by one all-at-once face-up hand.

const MATCH_SEED := 20260915
const DEADLINE_MS := 20000
const EXPECTED := 3

var _fails := 0
var _draft: Control
var _ss: Node
var _nm: Node
var _cache: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[net-draft-atomic] BEGIN")
	_ss = root.get_node_or_null("SkirmishState")
	_nm = root.get_node_or_null("NetMatch")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	_check(DisplayServer.get_name() == "headless", "probe uses the deterministic snap branch")
	_check(_ss != null and _nm != null and _cache != null and settings != null,
		"NetDraft dependencies are present")
	if _ss == null or _nm == null or _cache == null or settings == null:
		await _finish()
		return

	settings.reduce_motion = true
	settings.particles = false
	_nm.local_hero = "raider"
	_nm.start_vs_bot(_ss.MatchMode.DRAFT, 1)
	_nm.match_seed = MATCH_SEED
	_nm.match_mode = _ss.MatchMode.DRAFT
	_nm.best_of = 1
	_ss.reset()
	_cache.clear()
	CardArtAliases.clear_runtime_caches()

	_draft = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(_draft)
	await process_frame
	_check(_draft.is_inside_tree(), "real NetDraft scene survives boot")
	await _skip_arsenal()

	_check(await _wait_slots_reserved(),
		"initial triplet reserves all three final slots before hydration completes")
	_check(not bool(_draft.get("_triplet_ready")),
		"initial triplet stays input-locked behind its sleeves")
	var generation := int(_draft.get("_triplet_build_generation"))
	var deck_before: Array = _local_deck().duplicate()
	var rerolls_before := int(_draft.get("_rerolls_left"))
	_draft.call("_on_pick", "synthetic_early_pick", generation)
	_draft.call("_on_reroll_triplet")
	_check(_local_deck() == deck_before and int(_draft.get("_rerolls_left")) == rerolls_before,
		"pick and reroll handlers reject loading-time input")
	_check(_existing_pick_buttons_locked(),
		"every CHOOSE target that already exists remains disabled during hydration")

	var initial := await _sample_until_ready()
	print("[net-draft-atomic] initial slots=", initial.slots,
		" visible=", initial.visible, " shift=", initial.max_shift)
	_assert_atomic_sample(initial, "initial triplet")
	_assert_live_hand("initial triplet")

	var first_button := _pick_buttons()[0] as Button
	var first_id := _card_ids()[0]
	var picks_before := int(_draft.get("_picks_made"))
	var old_generation := int(_draft.get("_triplet_build_generation"))
	first_button.emit_signal("pressed")
	first_button.emit_signal("pressed")
	_check(int(_draft.get("_picks_made")) == picks_before + 1 \
		and _local_deck().size() == deck_before.size() + 1 \
		and String(_local_deck().back()) == first_id,
		"one revealed CHOOSE commits the displayed card exactly once")
	_check(int(_draft.get("_triplet_build_generation")) > old_generation,
		"accepted pick invalidates every old bound button")
	_check(await _wait_slots_reserved(),
		"replacement triplet immediately restores complete face-down geometry")
	var replacement := await _sample_until_ready()
	_assert_atomic_sample(replacement, "post-pick replacement")
	_assert_live_hand("post-pick replacement")

	var stale_button := _pick_buttons()[0] as Button
	var budget_before := int(_draft.get("_rerolls_left"))
	var picks_before_reroll := int(_draft.get("_picks_made"))
	var deck_before_reroll: Array = _local_deck().duplicate()
	_draft.call("_on_reroll_triplet")
	_draft.call("_on_reroll_triplet")
	stale_button.emit_signal("pressed")
	_check(int(_draft.get("_rerolls_left")) == budget_before - 1,
		"double reroll signal spends exactly one charge")
	_check(int(_draft.get("_picks_made")) == picks_before_reroll \
		and _local_deck() == deck_before_reroll,
		"stale CHOOSE cannot commit during the reroll sweep")
	_check(await _wait_reroll_slots(),
		"reroll replaces the old hand with three reserved slots")
	var rerolled := await _sample_until_ready()
	_assert_atomic_sample(rerolled, "rerolled triplet")
	_assert_live_hand("rerolled triplet")

	await _finish()


func _skip_arsenal() -> void:
	_check(bool(_draft.call("arsenal_active")), "Draft begins behind the authentic Arsenal")
	for pick in 5:
		var deadline := Time.get_ticks_msec() + DEADLINE_MS
		while bool(_draft.call("arsenal_active")) \
				and not bool(_draft.call("arsenal_slate_ready")) \
				and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(not bool(_draft.call("arsenal_active")) \
			or bool(_draft.call("arsenal_slate_ready")),
			"Arsenal slate %d reveals before input" % [pick + 1])
		if not bool(_draft.call("arsenal_active")):
			break
		_draft.call("_on_ars_pass")
		await process_frame
	_check(not bool(_draft.call("arsenal_active")),
		"all Arsenal slates finish through their gated action")


func _wait_slots_reserved() -> bool:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		if _live_slots().size() == EXPECTED:
			await process_frame
			return _live_slots().size() == EXPECTED
		await process_frame
	return false


func _wait_reroll_slots() -> bool:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var saw_reroll := bool(_draft.get("_rerolling"))
	while Time.get_ticks_msec() < deadline:
		saw_reroll = saw_reroll or bool(_draft.get("_rerolling"))
		if saw_reroll and not bool(_draft.get("_rerolling")) \
				and _live_slots().size() == EXPECTED:
			await process_frame
			return _live_slots().size() == EXPECTED
		await process_frame
	return false


func _sample_until_ready() -> Dictionary:
	var slots: Array[int] = []
	var visible: Array[int] = []
	var baseline: Array[Vector2] = []
	var max_shift := 0.0
	var stable := 0
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var live := _live_slots()
		slots.append(live.size())
		visible.append(_visible_card_count())
		var positions := _slot_positions(live)
		if baseline.is_empty() and positions.size() == EXPECTED:
			baseline = positions
		elif positions.size() == baseline.size():
			for i in positions.size():
				max_shift = maxf(max_shift, positions[i].distance_to(baseline[i]))
		if bool(_draft.get("_triplet_ready")) and live.size() == EXPECTED:
			stable += 1
			if stable >= 3:
				break
		else:
			stable = 0
		await process_frame
	_check(stable >= 3, "triplet reaches a stable ready state")
	return {"slots": slots, "visible": visible, "max_shift": max_shift}


func _assert_atomic_sample(sample: Dictionary, label: String) -> void:
	var slot_counts: Array = sample.slots
	var visible_counts: Array = sample.visible
	var slots_fixed := not slot_counts.is_empty()
	for count in slot_counts:
		slots_fixed = slots_fixed and int(count) == EXPECTED
	var visibility_atomic := not visible_counts.is_empty() \
		and int(visible_counts.back()) == EXPECTED
	for count in visible_counts:
		visibility_atomic = visibility_atomic and (int(count) == 0 or int(count) == EXPECTED)
	_check(slots_fixed, "%s keeps all three slots for every sampled frame" % label)
	_check(visibility_atomic, "%s visible faces jump only from 0 to 3" % label)
	_check(float(sample.max_shift) <= 0.01, "%s slot shift stays below 0.01 px" % label)


func _assert_live_hand(label: String) -> void:
	var buttons := _pick_buttons()
	_check(_card_ids().size() == EXPECTED and buttons.size() == EXPECTED,
		"%s contains three ornate cards and three CHOOSE targets" % label)
	var enabled := true
	for button in buttons:
		enabled = enabled and not (button as Button).disabled
	_check(enabled, "%s unlocks every CHOOSE target after reveal" % label)


func _live_slots() -> Array[Node]:
	var out: Array[Node] = []
	if _draft == null or not is_instance_valid(_draft):
		return out
	var row: HBoxContainer = _draft.get("_card_row") as HBoxContainer
	if row == null:
		return out
	for child in row.get_children():
		if child.is_inside_tree() and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _slot_positions(slots: Array[Node]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for slot in slots:
		out.append((slot as Control).global_position)
	return out


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _visible_card_count() -> int:
	var count := 0
	for node in _walk(_draft.get("_card_row")):
		var script: Script = node.get_script()
		if node is Control and script != null \
				and String(script.resource_path).ends_with("/Card2D.gd") \
				and (node as Control).is_visible_in_tree():
			count += 1
	return count


func _card_ids() -> Array[String]:
	var out: Array[String] = []
	for node in _walk(_draft.get("_card_row")):
		if "card_id" in node and String(node.get("card_id")) != "":
			out.append(String(node.get("card_id")))
	return out


func _pick_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node in _walk(_draft.get("_card_row")):
		if node is Button and (node as Button).text == "CHOOSE":
			out.append(node as Button)
	return out


func _existing_pick_buttons_locked() -> bool:
	for button in _pick_buttons():
		if not button.disabled:
			return false
	return true


func _local_deck() -> Array:
	var slot = _ss.local_slot()
	return slot.deck if slot != null else []


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		push_error("FAIL  %s" % label)


func _finish() -> void:
	if _draft != null and is_instance_valid(_draft):
		_draft.queue_free()
	for _i in 4:
		await process_frame
	if _cache != null:
		_cache.clear()
	CardArtAliases.clear_runtime_caches()
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music(0.0)
	if _nm != null:
		_nm.leave()
	if _ss != null:
		_ss.reset()
	print("[net-draft-atomic] PROBE_RESULT %s failures=%d" % [
		"PASS" if _fails == 0 else "FAIL", _fails])
	call_deferred("_quit_after_unwind", 0 if _fails == 0 else 1)


func _quit_after_unwind(code: int) -> void:
	quit(code)
