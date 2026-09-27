extends SceneTree
## Headless behavior regression for NetDraft's progressive card-triplet builder.
##
## Exercises the real scene and real Button signals without sockets:
##   1. The initial triplet appears one card per process frame.
##   2. Choosing the first visible card while hydration is suspended commits once;
##      the retained old Button cannot double-pick after its generation is stale.
##   3. A complete triplet has exactly three cards/buttons, all bound to the live
##      build generation.
##   4. Rerolling both during hydration and after a completed deal spends exactly
##      one charge per accepted press; immediate repeat signals are rejected.
##   5. Cancelled builders cannot append old-generation slots behind a new slate.
##   6. Ledger previews select the gallery cache on a gallery-only hit, while a
##      gameplay cache hit takes precedence exactly as the production code asks.
##
## Run:
##   Godot_v4.6.2-stable_win64_console.exe --headless --path "D:\\Godot" ^
##       --script res://tools/_probe_net_draft_progressive.gd

const MATCH_SEED := 20260910
const DEADLINE_MS := 15000
const EXPECTED_TRIPLET := 3

var _fails := 0
var _draft: Control = null
var _ss: Node = null
var _nm: Node = null
var _cache: Node = null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_fails += 1
		print("FAIL  ", label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[net-draft-progressive] BEGIN")
	_check(DisplayServer.get_name() == "headless",
		"probe is running on the headless display server")
	if DisplayServer.get_name() != "headless":
		print("[net-draft-progressive] REFUSED: this regression is headless-only")
		quit(1)
		return

	_ss = root.get_node_or_null("SkirmishState")
	_nm = root.get_node_or_null("NetMatch")
	_cache = root.get_node_or_null("CardTextureCache")
	var settings := root.get_node_or_null("UserSettings")
	_check(_ss != null and _nm != null and _cache != null and settings != null,
		"NetDraft dependencies are present")
	if _ss == null or _nm == null or _cache == null or settings == null:
		quit(1)
		return

	settings.reduce_motion = true
	settings.particles = false
	_nm.local_hero = "raider"
	_nm.start_vs_bot(_ss.MatchMode.DRAFT, 1)
	# start_vs_bot creates a valid practice-peer contract, then we pin its entropy
	# before the scene's _ready seeds either draft stream.
	_nm.match_seed = MATCH_SEED
	_nm.match_mode = _ss.MatchMode.DRAFT
	_nm.best_of = 1
	_ss.reset()
	_cache.clear()
	CardArtAliases.clear_runtime_caches()

	_draft = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(_draft)
	await process_frame
	_check(is_instance_valid(_draft) and _draft.is_inside_tree(),
		"real NetDraft scene survives boot")
	_check(bool(_draft.call("arsenal_active")),
		"draft begins behind the authentic arsenal stage")
	if not is_instance_valid(_draft):
		await _finish()
		return

	# Skip the authentic 3 relic + 2 potion rounds. Headless is the production
	# instant-motion branch, so the fifth call synchronously opens the triplet and
	# then suspends at its explicit one-card-per-frame staging yield.
	for _i in 3:
		_draft.call("_on_ars_pick", "", true)
	for _i in 2:
		_draft.call("_on_ars_pick", "", false)
	_check(not bool(_draft.call("arsenal_active")),
		"arsenal completion enters the card-triplet stage")

	# --- Initial staged deal + click during hydration -----------------------
	var initial_progress := await _wait_for_partial_triplet()
	print("[net-draft-progressive] initial progression=", initial_progress)
	_check(_contains_partial(initial_progress),
		"initial deal exposes a partial triplet before all three cards exist")
	_check(_unit_staged(initial_progress),
		"initial triplet grows by at most one visible slot per process frame")
	var initial_slots := _live_slots()
	var first_button := _slot_pick_button(initial_slots[0]) \
		if not initial_slots.is_empty() else null
	var first_id := _slot_card_id(initial_slots[0]) \
		if not initial_slots.is_empty() else ""
	var first_generation := int(_draft.get("_triplet_build_generation"))
	_check(first_button != null and first_id != "" \
			and initial_slots.size() < EXPECTED_TRIPLET,
		"first visible card has a live CHOOSE target while hydration is suspended")

	var picks_before := int(_draft.get("_picks_made"))
	var deck_before := _local_deck().duplicate()
	if first_button != null:
		first_button.emit_signal("pressed")
		# Deliberately retain and re-emit the exact old Button before queue_free has
		# run. Its bound source_generation must make the duplicate harmless.
		first_button.emit_signal("pressed")
	_check(int(_draft.get("_picks_made")) == picks_before + 1,
		"early visible-card click advances the pick count exactly once")
	var deck_after_early := _local_deck()
	_check(deck_after_early.size() == deck_before.size() + 1 \
			and String(deck_after_early.back()) == first_id,
		"early click commits exactly the displayed card (%s)" % first_id)
	_check(int(_draft.get("_triplet_build_generation")) > first_generation,
		"accepted early click invalidates its suspended builder generation")

	var post_pick_progress := await _wait_for_full_triplet()
	print("[net-draft-progressive] post-pick progression=", post_pick_progress)
	_check(not post_pick_progress.is_empty() \
			and post_pick_progress.back() == EXPECTED_TRIPLET,
		"replacement triplet completes after the early pick")
	_check(_unit_staged(post_pick_progress),
		"replacement triplet also stages no more than one slot per frame")
	_assert_clean_live_triplet("post-pick replacement")

	# --- Preview cache-class selection -------------------------------------
	await _check_preview_cache_selection()

	# --- Reroll during hydration -------------------------------------------
	# A real second card pick starts the next progressive deal. Press reroll as
	# soon as only its first slot is visible, while its builder is still parked.
	var complete_slots := _live_slots()
	var second_pick := _slot_pick_button(complete_slots[0]) \
		if not complete_slots.is_empty() else null
	if second_pick != null:
		second_pick.emit_signal("pressed")
	var before_partial_reroll := await _wait_for_partial_triplet()
	print("[net-draft-progressive] pre-reroll partial progression=",
		before_partial_reroll)
	_check(_contains_partial(before_partial_reroll),
		"next deal is caught while hydration is incomplete")
	var partial_slots := _live_slots()
	var stale_partial_button := _slot_pick_button(partial_slots[0]) \
		if not partial_slots.is_empty() else null
	var partial_generation := int(_draft.get("_triplet_build_generation"))
	var rerolls_before := int(_draft.get("_rerolls_left"))
	var picks_before_reroll := int(_draft.get("_picks_made"))
	var deck_before_reroll := _local_deck().duplicate()
	var reroll_button: Button = _draft.get("_reroll_btn") as Button
	_check(reroll_button != null and reroll_button.visible \
			and not reroll_button.disabled,
		"reroll remains live while a cold triplet is still hydrating")
	if reroll_button != null:
		reroll_button.emit_signal("pressed")
		# emit_signal bypasses Button.disabled, intentionally reaching the handler's
		# own _rerolling latch and proving it rejects a same-frame double signal.
		reroll_button.emit_signal("pressed")
	if stale_partial_button != null and is_instance_valid(stale_partial_button):
		stale_partial_button.emit_signal("pressed")
	_check(int(_draft.get("_rerolls_left")) == rerolls_before - 1,
		"double reroll signal during hydration spends exactly one charge")
	_check(bool(_draft.get("_rerolling")),
		"accepted reroll latches re-entry for the sweep interval")
	_check(int(_draft.get("_triplet_build_generation")) == partial_generation + 1,
		"reroll immediately invalidates the suspended triplet generation once")
	_check(int(_draft.get("_picks_made")) == picks_before_reroll \
			and _local_deck() == deck_before_reroll,
		"stale partial CHOOSE signal cannot pick during the reroll sweep")

	var during_reroll_progress := await _wait_for_reroll_and_full_triplet()
	print("[net-draft-progressive] during-hydration reroll progression=",
		during_reroll_progress)
	_check(not during_reroll_progress.is_empty() \
			and during_reroll_progress.back() == EXPECTED_TRIPLET,
		"reroll during hydration completes a fresh three-card deal")
	_check(_unit_staged(during_reroll_progress),
		"post-cancellation replacement still stages at one slot per frame")
	_check(int(_draft.get("_rerolls_left")) == rerolls_before - 1,
		"sweep completion does not spend another reroll")
	_assert_clean_live_triplet("during-hydration reroll replacement")

	# Let the sweep overlay retire. Exactly three Card2Ds should remain in this
	# scene: the fresh live row, with none leaked from the cancelled coroutine.
	await create_timer(0.65).timeout
	_check(_count_scene_cards() == EXPECTED_TRIPLET,
		"cancelled generation leaves no stale Card2D outside the fresh row")

	# --- Reroll after full population --------------------------------------
	var full_generation := int(_draft.get("_triplet_build_generation"))
	var full_old_slots := _live_slots()
	var full_stale_button := _slot_pick_button(full_old_slots[0]) \
		if not full_old_slots.is_empty() else null
	var budget_before_full := int(_draft.get("_rerolls_left"))
	var full_picks_before := int(_draft.get("_picks_made"))
	var full_deck_before := _local_deck().duplicate()
	if reroll_button != null:
		reroll_button.emit_signal("pressed")
		reroll_button.emit_signal("pressed")
	if full_stale_button != null and is_instance_valid(full_stale_button):
		full_stale_button.emit_signal("pressed")
	_check(int(_draft.get("_rerolls_left")) == budget_before_full - 1,
		"double reroll signal on a complete triplet spends exactly one charge")
	_check(int(_draft.get("_triplet_build_generation")) == full_generation + 1,
		"complete-triplet reroll advances the generation exactly once at acceptance")
	_check(int(_draft.get("_picks_made")) == full_picks_before \
			and _local_deck() == full_deck_before,
		"stale complete-triplet CHOOSE signal cannot commit during reroll")

	var full_reroll_progress := await _wait_for_reroll_and_full_triplet()
	print("[net-draft-progressive] full-triplet reroll progression=",
		full_reroll_progress)
	_check(not full_reroll_progress.is_empty() \
			and full_reroll_progress.back() == EXPECTED_TRIPLET,
		"reroll after full population completes its replacement triplet")
	_assert_clean_live_triplet("full-triplet reroll replacement")
	_check(int(_draft.get("_rerolls_left")) == 0,
		"two accepted rerolls exhaust the fixed budget at zero")
	_check(reroll_button != null and not reroll_button.visible,
		"reroll action hides when its budget is exhausted")

	# Even a direct signal on the retained persistent button must be inert at zero.
	var zero_generation := int(_draft.get("_triplet_build_generation"))
	var zero_ids := _live_card_ids()
	if reroll_button != null:
		reroll_button.emit_signal("pressed")
	for _i in 3:
		await process_frame
	_check(int(_draft.get("_rerolls_left")) == 0 \
			and int(_draft.get("_triplet_build_generation")) == zero_generation \
			and _live_card_ids() == zero_ids,
		"exhausted reroll signal cannot spend below zero or replace the slate")

	await _finish()


func _check_preview_cache_selection() -> void:
	var ids := _live_card_ids()
	if ids.is_empty():
		_check(false, "preview cache test has a live card id")
		return
	var id := String(ids[0])
	var data: Dictionary = _ss.skirmish_card_data(id)
	_cache.clear()
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.45, 0.30, 0.15, 1.0))
	var gallery_texture := ImageTexture.create_from_image(image)
	var gallery_key := String(_cache.call("gallery_cache_key", data))
	_install_cache_texture(gallery_key, gallery_texture)
	_check(not bool(_cache.call("has", data)) \
			and bool(_cache.call("has_gallery", data)),
		"fixture provides a gallery-only cache hit for preview card %s" % id)
	_draft.call("_show_preview", id)
	await process_frame
	var gallery_preview: Control = _draft.get("_preview") as Control
	var gallery_face: TextureRect = gallery_preview.get("_baked_face") as TextureRect \
		if gallery_preview != null else null
	_check(gallery_preview != null \
			and bool(gallery_preview.get("live_baked_mode")) \
			and bool(gallery_preview.get("gallery_baked_mode")) \
			and gallery_face != null and gallery_face.texture == gallery_texture,
		"ledger preview consumes the native gallery cache on a gallery-only hit")
	_draft.call("_hide_preview")
	await process_frame

	var gameplay_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	gameplay_image.fill(Color(0.18, 0.30, 0.46, 1.0))
	var gameplay_texture := ImageTexture.create_from_image(gameplay_image)
	var gameplay_key := String(_cache.call("gameplay_cache_key", data))
	_install_cache_texture(gameplay_key, gameplay_texture)
	_check(bool(_cache.call("has", data)) and bool(_cache.call("has_gallery", data)),
		"fixture exposes both cache classes for precedence check")
	_draft.call("_show_preview", id)
	await process_frame
	var gameplay_preview: Control = _draft.get("_preview") as Control
	var gameplay_face: TextureRect = gameplay_preview.get("_baked_face") as TextureRect \
		if gameplay_preview != null else null
	_check(gameplay_preview != null \
			and bool(gameplay_preview.get("live_baked_mode")) \
			and not bool(gameplay_preview.get("gallery_baked_mode")) \
			and gameplay_face != null and gameplay_face.texture == gameplay_texture,
		"ledger preview prefers gameplay cache when both classes are available")
	_draft.call("_hide_preview")
	await process_frame
	_cache.clear()


func _install_cache_texture(key: String, texture: Texture2D) -> void:
	var backing: Dictionary = _cache.get("_cache")
	backing[key] = texture
	_cache.set("_cache", backing)
	var order: Array = _cache.get("_cache_order")
	order.erase(key)
	order.append(key)
	_cache.set("_cache_order", order)


func _wait_for_partial_triplet() -> Array[int]:
	var progression: Array[int] = []
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var count := _live_slots().size()
		_append_distinct(progression, count)
		if count > 0 and count < EXPECTED_TRIPLET:
			return progression
		await process_frame
	return progression


func _wait_for_full_triplet() -> Array[int]:
	var progression: Array[int] = []
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var count := _live_slots().size()
		_append_distinct(progression, count)
		if count == EXPECTED_TRIPLET and not bool(_draft.get("_rerolling")):
			return progression
		await process_frame
	return progression


func _wait_for_reroll_and_full_triplet() -> Array[int]:
	var progression: Array[int] = []
	var saw_reroll := bool(_draft.get("_rerolling"))
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while Time.get_ticks_msec() < deadline:
		var rerolling := bool(_draft.get("_rerolling"))
		saw_reroll = saw_reroll or rerolling
		var count := _live_slots().size()
		_append_distinct(progression, count)
		if saw_reroll and not rerolling and count == EXPECTED_TRIPLET:
			return progression
		await process_frame
	return progression


func _append_distinct(values: Array[int], value: int) -> void:
	if values.is_empty() or values.back() != value:
		values.append(value)


func _contains_partial(progression: Array[int]) -> bool:
	for count in progression:
		if count > 0 and count < EXPECTED_TRIPLET:
			return true
	return false


func _unit_staged(progression: Array[int]) -> bool:
	for i in range(1, progression.size()):
		if progression[i] - progression[i - 1] > 1:
			return false
	return true


func _live_slots() -> Array[Node]:
	var out: Array[Node] = []
	if _draft == null or not is_instance_valid(_draft):
		return out
	var row: HBoxContainer = _draft.get("_card_row") as HBoxContainer
	if row == null:
		return out
	for child in row.get_children():
		if child is Node and child.is_inside_tree() and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _slot_pick_button(slot: Node) -> Button:
	if slot == null or not is_instance_valid(slot):
		return null
	for child in slot.get_children():
		if child is Button and not child.is_queued_for_deletion():
			return child as Button
	return null


func _slot_card_id(slot: Node) -> String:
	if slot == null or not is_instance_valid(slot):
		return ""
	for node in _walk(slot):
		if "card_id" in node:
			return String(node.get("card_id"))
	return ""


func _live_card_ids() -> Array[String]:
	var out: Array[String] = []
	for slot in _live_slots():
		var id := _slot_card_id(slot)
		if id != "":
			out.append(id)
	return out


func _button_bound_generation(button: Button) -> int:
	if button == null or not is_instance_valid(button):
		return -1
	for connection in button.get_signal_connection_list("pressed"):
		var callable: Callable = connection.get("callable", Callable())
		if not callable.is_valid():
			continue
		var bound := callable.get_bound_arguments()
		if bound.size() >= 2 and String(bound[0]) != "":
			return int(bound.back())
	return -1


func _assert_clean_live_triplet(label: String) -> void:
	var slots := _live_slots()
	var live_generation := int(_draft.get("_triplet_build_generation"))
	var cards := 0
	var buttons := 0
	var generations_match := true
	for slot in slots:
		if _slot_card_id(slot) != "":
			cards += 1
		var button := _slot_pick_button(slot)
		if button != null:
			buttons += 1
			if _button_bound_generation(button) != live_generation:
				generations_match = false
	_check(slots.size() == EXPECTED_TRIPLET and cards == EXPECTED_TRIPLET \
			and buttons == EXPECTED_TRIPLET,
		"%s has exactly three live card/button slots" % label)
	_check(generations_match,
		"%s contains only current-generation CHOOSE bindings (%d)" % [
			label, live_generation])


func _count_scene_cards() -> int:
	var count := 0
	for node in _walk(_draft):
		if "card_id" in node and String(node.get("card_id")) != "" \
				and not node.is_queued_for_deletion():
			count += 1
	return count


func _local_deck() -> Array:
	var slot = _ss.local_slot()
	return slot.deck if slot != null else []


func _walk(host: Node) -> Array[Node]:
	var out: Array[Node] = []
	if host == null or not is_instance_valid(host):
		return out
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _finish() -> void:
	if _draft != null and is_instance_valid(_draft):
		_draft.queue_free()
	for _i in 4:
		await process_frame
	if _cache != null:
		_cache.clear()
	CardArtAliases.clear_runtime_caches()
	# NetDraft starts a music track in _ready. Stop and detach it explicitly so
	# this short-lived SceneTree probe does not exit while MP3 playback still owns
	# a decoder reference (the normal game keeps AudioBank alive for the session).
	var audio := root.get_node_or_null("AudioBank")
	if audio != null:
		audio.stop_music(0.0)
		for player_name in ["_music_a", "_music_b"]:
			var player: AudioStreamPlayer = audio.get(player_name) as AudioStreamPlayer
			if player != null:
				player.stop()
				player.stream = null
		var music_streams: Dictionary = audio.get("_music_streams")
		music_streams.clear()
		audio.set("_music_streams", music_streams)
	if _nm != null:
		_nm.leave()
	if _ss != null:
		_ss.reset()
	print("[net-draft-progressive] %s" % (
		"PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	# Defer quitting until _run's coroutine has unwound. It deliberately retains
	# stale Button and cache-texture references for its assertions; quitting inside
	# this awaited helper would report those live locals as exit-time leaks.
	call_deferred("_quit_after_unwind", 0 if _fails == 0 else 1)


func _quit_after_unwind(code: int) -> void:
	quit(code)
