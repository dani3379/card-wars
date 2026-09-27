extends SceneTree
## Focused windowed regression for Game Over's final-deck strip.
##
## The bug this guards is perceptual layout shift: finished cards used to enter a
## centred HBox one by one, moving every card already on screen. The production
## contract is now:
##   1. every exact-size slot and face-down back exists synchronously,
##   2. ornate Card2D faces hydrate invisibly inside those fixed slots,
##   3. inherited opacity changes 0 -> N in one frame,
##   4. the turn-over is synchronized, and Reduce Motion snaps the same N faces.

# LOADED AT RUNTIME, NEVER `preload`ed. The host inherits GameOver.gd, which
# names autoloads directly — correct in a scene, a hard compile error under
# `--script`, where a preload is resolved BEFORE the autoloads register. The
# symptom is not a clean failure: the script comes back half-built
# ("p_script->implicit_initializer is null"), every `call()` into it reports
# "Nonexistent function", and the probe sails on to print failures=0 having
# exercised nothing. Same trap the C14 audit hit by naming Card2D at parse time.
const HOST_SCRIPT_PATH := "res://tools/_game_over_strip_probe_host.gd"
const CARD_BACK_TEXTURE = preload("res://assets/ui/card_back.png")
const CASE_TIMEOUT_MS := 12000
const EXTRA_CARD_IDS: Array[String] = [
	"lookout", "thornguard", "raven", "battle_drummer", "hound",
	"warding_stone", "basilisk", "palisade", "mourner",
]

var _started := false
var _done := false
var _failures := 0
var _run_state: Node
var _cache: Node
var _settings: Node
# Resolved through the tree like its three siblings, NOT named directly. This
# probe is driven with `--script`, where a bare autoload identifier is a hard
# COMPILE error ("Identifier not found: CardDB") that takes the whole file down
# before a line of it runs — the blind spot parsecheck cannot see, because
# parsecheck runs as a SCENE and autoload names resolve there.
var _card_db: Node
var _old_reduce_motion := false


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
	_run_state = root.get_node_or_null("RunState")
	_cache = root.get_node_or_null("CardTextureCache")
	_settings = root.get_node_or_null("UserSettings")
	_card_db = root.get_node_or_null("CardDB")
	if _run_state == null or _cache == null or _settings == null \
			or _card_db == null:
		_fail("required autoloads are present")
		_finish()
		return
	_old_reduce_motion = bool(_settings.get("reduce_motion"))
	_settings.set("particles", false)
	_settings.set("graphics_preset", "medium")
	_settings.set("render_scale", 1.0)
	await process_frame
	await _wait_for_idle_baker()
	_prepare_deck()
	var expected := _expected_visual_groups()
	_check(expected >= 8, "fixture contains a deck-sized set of visual identities")
	await _run_case("animated", false, expected)
	await _run_case("reduce_motion", true, expected)
	_settings.set("reduce_motion", _old_reduce_motion)
	_finish()


func _prepare_deck() -> void:
	_run_state.start_new_run("raider", 0, 20260915)
	_run_state.set("active_slot", -1)
	for card_id: String in EXTRA_CARD_IDS:
		if not _card_db.get_card_data(card_id).is_empty():
			_run_state.add_card(card_id)


func _run_case(label: String, reduced: bool, expected: int) -> void:
	print("[game-over-strip] CASE %s expected=%d" % [label, expected])
	_settings.set("reduce_motion", reduced)
	await _wait_for_idle_baker()
	_cache.clear()

	var host := Control.new()
	host.set_script(load(HOST_SCRIPT_PATH))
	host.name = "GameOverStripProbeHost_%s" % label
	# A GATE THAT CANNOT ACT MUST GO RED, NOT QUIET. Without this the probe
	# printed failures=0 through two whole cases in which every call into the
	# host had failed — the fake-gate shape the mutation run (C12) was built to
	# catch, and the reason a green run here is now worth something.
	if not host.has_method("_populate_deck_strip"):
		_fail("probe host exposes the production strip builder")
		host.queue_free()
		return
	host.size = Vector2(1600, 900)
	root.add_child(host)
	var row := HBoxContainer.new()
	row.name = "DeckStripProbeRow"
	row.position = Vector2(100, 340)
	row.size = Vector2(1400, 180)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	host.add_child(row)

	# Calling an async GDScript method without await executes through its first
	# await. These assertions therefore prove the pre-await production state.
	host.call("_populate_deck_strip", row)
	var immediate_slots := row.get_child_count()
	var immediate_backs := _direct_back_count(row)
	var immediate_cards := _card_nodes(row).size()
	_check(immediate_slots == expected,
		"%s reserves every card slot before its first await" % label)
	_check(immediate_backs == expected,
		"%s installs every face-down back before its first await" % label)
	_check(immediate_cards == 0,
		"%s does not hydrate an ornate face before the reserved shell" % label)
	_check(_slot_minimums_are_exact(row),
		"%s slots reserve non-zero exact card proportions immediately" % label)

	var node_progression: Array[int] = [immediate_cards]
	var visible_progression: Array[int] = [_visible_card_count(row)]
	var back_progression: Array[int] = [immediate_backs]
	var baseline: Array[Vector2] = []
	var candidate: Array[Vector2] = []
	var layout_calm := 0
	# Containers get one initial sort; lock the baseline only after two calm ticks.
	for _i in 16:
		await process_frame
		_record_progression(row, node_progression, visible_progression, back_progression)
		var current := _slot_centers(row)
		if not candidate.is_empty() and _max_position_delta(candidate, current) <= 0.01:
			layout_calm += 1
		else:
			layout_calm = 0
		candidate = current
		if layout_calm >= 2:
			baseline = current
			break
	_check(baseline.size() == expected,
		"%s completes one stable initial HBox layout" % label)
	_check(_visible_card_count(row) == 0,
		"%s keeps all partially hydrated faces hidden" % label)

	var max_shift := 0.0
	var max_face_scale_spread := 0.0
	var min_face_scale := 1.0
	var reduced_reveal_was_resting := true
	var saw_reveal := false
	var settled := false
	var deadline := Time.get_ticks_msec() + CASE_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		_record_progression(row, node_progression, visible_progression, back_progression)
		var current := _slot_centers(row)
		max_shift = maxf(max_shift, _max_position_delta(baseline, current))
		var cards := _card_nodes(row)
		if cards.size() == expected:
			var scales := _face_scales(cards)
			if not scales.is_empty():
				var lo: float = scales.min()
				var hi: float = scales.max()
				max_face_scale_spread = maxf(max_face_scale_spread, hi - lo)
				if _visible_card_count(row) > 0:
					saw_reveal = true
					min_face_scale = minf(min_face_scale, lo)
					if reduced and (lo < 0.999 or hi > 1.001):
						reduced_reveal_was_resting = false
		if cards.size() == expected and _visible_card_count(row) == expected \
				and _direct_back_count(row) == 0 and _faces_at_rest(cards):
			settled = true
			break

	var cards := _card_nodes(row)
	print(("[game-over-strip] %s nodes=%s visible=%s backs=%s "
		+ "shift=%.3fpx scale_spread=%.4f min_scale=%.4f settled=%s") % [
		label, str(node_progression), str(visible_progression),
		str(back_progression), max_shift, max_face_scale_spread,
		min_face_scale, str(settled)])
	_check(settled, "%s reaches a complete settled deck" % label)
	_check(visible_progression == [0, expected],
		"%s reveals visible Card2D faces atomically 0 -> N" % label)
	_check(back_progression == [expected, 0],
		"%s removes the complete back set as one group" % label)
	_check(max_shift <= 0.01,
		"%s slot centres never move during bake, hydration, or reveal" % label)
	_check(max_face_scale_spread <= 0.01,
		"%s face transforms remain synchronized" % label)
	_check(saw_reveal, "%s presents the completed deck" % label)
	if reduced:
		_check(reduced_reveal_was_resting and min_face_scale >= 0.999,
			"Reduce Motion snaps every face directly to its resting transform")
	else:
		_check(min_face_scale < 0.95,
			"animated mode performs a coordinated card-turn before settling")
	_check(_full_ornate_cards_settled(cards),
		"%s settles N full ornate cached Card2D faces" % label)

	host.queue_free()
	for _i in 5:
		await process_frame


func _record_progression(row: Node, node_progression: Array[int],
		visible_progression: Array[int], back_progression: Array[int]) -> void:
	_append_change(node_progression, _card_nodes(row).size())
	_append_change(visible_progression, _visible_card_count(row))
	_append_change(back_progression, _direct_back_count(row))


func _append_change(values: Array[int], value: int) -> void:
	if values.is_empty() or values[-1] != value:
		values.append(value)


func _expected_visual_groups() -> int:
	var seen := {}
	for i in _run_state.deck.size():
		var data: Dictionary = _run_state.get_upgraded_card_data(i)
		if not data.is_empty():
			seen[String(_cache.cache_key(data))] = true
	return seen.size()


func _direct_back_count(row: Node) -> int:
	var count := 0
	for slot in row.get_children():
		for child in slot.get_children():
			if child is TextureRect and child.texture == CARD_BACK_TEXTURE:
				count += 1
	return count


func _slot_minimums_are_exact(row: Node) -> bool:
	for slot in row.get_children():
		if not (slot is Control):
			return false
		var sz: Vector2 = slot.custom_minimum_size
		if sz.x <= 0.0 or sz.y <= 0.0 or absf(sz.y / sz.x - 4.0 / 3.0) > 0.01:
			return false
	return true


func _slot_centers(row: Node) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if row == null or not is_instance_valid(row):
		return out
	for child in row.get_children():
		if child is Control:
			out.append(child.position + child.size * 0.5)
	return out


func _max_position_delta(a: Array[Vector2], b: Array[Vector2]) -> float:
	if a.size() != b.size():
		return INF
	var delta := 0.0
	for i in a.size():
		delta = maxf(delta, a[i].distance_to(b[i]))
	return delta


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return out


func _card_nodes(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in _walk(host):
		var script := node.get_script() as Script
		if script != null and String(script.resource_path).get_file() == "Card2D.gd":
			out.append(node)
	return out


func _effective_alpha(node: Node, boundary: Node) -> float:
	var alpha := 1.0
	var cursor := node
	while cursor != null:
		if cursor is CanvasItem:
			if not cursor.visible:
				return 0.0
			alpha *= cursor.modulate.a
		if cursor == boundary:
			break
		cursor = cursor.get_parent()
	return alpha


func _visible_card_count(row: Node) -> int:
	var count := 0
	for card in _card_nodes(row):
		if _effective_alpha(card, row) > 0.99:
			count += 1
	return count


func _face_scales(cards: Array[Node]) -> Array[float]:
	var out: Array[float] = []
	for card in cards:
		var face := card.get_parent() as Control
		if face != null:
			out.append(face.scale.x)
	return out


func _faces_at_rest(cards: Array[Node]) -> bool:
	for card in cards:
		var face := card.get_parent() as Control
		if face == null or not face.scale.is_equal_approx(Vector2.ONE):
			return false
	return not cards.is_empty()


func _full_ornate_cards_settled(cards: Array[Node]) -> bool:
	if cards.is_empty():
		return false
	for card in cards:
		if not (card is Control) or not bool(card.get("live_baked_mode")):
			return false
		var data: Dictionary = card.get("card_data")
		if data.is_empty() or not _cache.has(data):
			return false
		var baked_face = card.get("_baked_face")
		if not (baked_face is TextureRect) or not is_instance_valid(baked_face) \
				or baked_face.texture == null:
			return false
		if card.size.x < 224.0 or card.size.y < 299.0:
			return false
	return true


func _wait_for_idle_baker() -> void:
	var preloader := root.get_node_or_null("ScenePreload")
	if preloader != null and preloader.has_method("cancel_deck_warm"):
		preloader.cancel_deck_warm()
	var deadline := Time.get_ticks_msec() + 15000
	while bool(_cache.get("_bake_busy")) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not bool(_cache.get("_bake_busy")), "card baker becomes idle")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[game-over-strip] PASS ", message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	push_error("[game-over-strip] FAIL " + message)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[game-over-strip] DONE failures=%d" % _failures)
	quit(1 if _failures > 0 else 0)
