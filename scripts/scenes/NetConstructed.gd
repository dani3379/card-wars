extends "res://scripts/scenes/NetDeckBuilder.gd"
## NetConstructed.gd — Constructed mode: each player builds any DECK_TARGET-card
## deck from the full skirmish-legal pool, then both fight. No seed, no triplets —
## pure deckbuilding. Each side builds INDEPENDENTLY and ships its finished deck on
## READY (the same "finished" handoff the draft uses); the host launches combat
## once both decks are in.
##
## Deck handoff (mirrors NetDraft/NetQuick):
##   local deck → "finished" event → peer stores it → _maybe_begin_combat.
##   HOST calls NetMatch.launch_combat(); CLIENT waits.

# Scene constants + palette (MENU_SCENE, MAX_COPIES, THUMB_SCALE, the colors)
# and shared sync flags / refs (_target, _rng, _local_finished, _remote_finished,
# _root, _header, _pool_rows) are inherited from NetDeckBuilder.
var _pool: Array[String] = []    # legal ids, sorted by cost then name
var _deck: Array[String] = []    # working deck (ids), in add order
var _counts: Dictionary = {}     # id -> copies currently in deck
# The constructed catalogue is much larger than the viewport. Keep one cheap,
# fixed-size slot per legal card so the flow container retains honest scroll
# geometry, but only materialize Card2D for the viewport and a short runway.
# The wider cold margin prevents a card from churning while it brushes an edge.
const POOL_THUMB_SIZE := Vector2(103.5, 138.0) # 225x300 at THUMB_SCALE (0.46)
const POOL_VIRTUAL_REFRESH := 0.08
const POOL_WARM_MARGIN_SCREENS := 0.35
const POOL_COLD_MARGIN_SCREENS := 0.85
const POOL_PLACEHOLDER_YIELD_EVERY := 12
const POOL_HYDRATE_YIELD_EVERY := 4
const POOL_CARD_SCENE := preload("res://scenes/card_2d.tscn")

var _pool_data: Dictionary = {}       # id -> one skirmish-adjusted data copy
var _pool_sort_keys: Dictionary = {}  # id -> {cost, name}; no comparator copies
var _pool_jobs: Array[Dictionary] = []
var _pool_scroll: ScrollContainer
var _pool_generation: int = 0
var _pool_hydration_generation: int = -1
var _pool_virtual_accum: float = 0.0
var _pool_refresh_queued: bool = false
var _pool_empty_style: StyleBoxEmpty
var _pool_hover_style: StyleBoxFlat
var _pool_badge_style: StyleBoxFlat


# UI refs.
var _status: Label
var _deck_box: HFlowContainer
var _pool_box: HFlowContainer
var _deck_count_lbl: Label
var _ready_btn: Button
var _name_field: LineEdit         # save-as name
var _saved_option: OptionButton   # saved-deck picker
var _mode_ui_ready := false


## One CanvasItem ghost replaces the ornate ~20-node Card2D until its tile is
## near the scroll viewport. It stays identifiable while the permanent slot
## keeps geometry stable; interaction unlocks when its ornate face is hydrated.
class PoolCardGhost extends Control:
	var title_text: String = ""
	var command_cost: int = 0
	var attack: int = 0
	var health: int = 0
	var spell: bool = false
	var accent: Color = Color(0.68, 0.58, 0.38)
	var face_font: Font = null

	func configure(data: Dictionary, font: Font) -> void:
		title_text = String(data.get("name", data.get("id", "")))
		if title_text.length() > 16:
			title_text = title_text.left(15) + "..."
		command_cost = int(data.get("cost", 0))
		attack = int(data.get("atk", 0))
		health = int(data.get("hp", 0))
		spell = String(data.get("type", "creature")) == "spell"
		accent = GameTheme.rarity_color(String(data.get("rarity", "common")))
		face_font = font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 0.0 or h <= 0.0:
			return
		var ink := Color(0.055, 0.045, 0.035, 0.96)
		var paper := Color(0.20, 0.17, 0.13, 0.98)
		var rule := Color(accent.r, accent.g, accent.b, 0.62)
		draw_rect(Rect2(1, 1, w - 2, h - 2), paper)
		draw_rect(Rect2(1, 1, w - 2, h - 2), rule, false, 1.0)
		draw_rect(Rect2(5, 6, w - 10, h * 0.48), ink.lightened(0.08))
		draw_rect(Rect2(5, h * 0.57, w - 10, h * 0.14), ink)
		draw_rect(Rect2(7, h * 0.73, w - 14, h * 0.16), paper.lightened(0.07))
		draw_circle(Vector2(11, 11), 9.0, Color(0.16, 0.24, 0.42))
		if not spell:
			draw_circle(Vector2(11, h - 11), 9.0, Color(0.42, 0.33, 0.12))
			draw_circle(Vector2(w - 11, h - 11), 9.0, Color(0.44, 0.14, 0.12))
		if face_font == null:
			return
		var pale := Color(0.86, 0.79, 0.64, 0.90)
		draw_string(face_font, Vector2(2, 15), str(command_cost),
			HORIZONTAL_ALIGNMENT_CENTER, 18, 10, pale)
		draw_string(face_font, Vector2(5, h * 0.675), title_text,
			HORIZONTAL_ALIGNMENT_CENTER, w - 10, 10, pale)
		if spell:
			draw_string(face_font, Vector2(5, h - 6), "SPELL",
				HORIZONTAL_ALIGNMENT_CENTER, w - 10, 9, pale.darkened(0.18))
		else:
			draw_string(face_font, Vector2(2, h - 7), str(attack),
				HORIZONTAL_ALIGNMENT_CENTER, 18, 10, pale)
			draw_string(face_font, Vector2(w - 20, h - 7), str(health),
				HORIZONTAL_ALIGNMENT_CENTER, 18, 10, pale)


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")
	AudioBank.play_music_random(["net_lobby", "net_lobby_b", "rest_c"])  # muster pool

	if not NetMatch.is_connected_to_peer():
		get_tree().change_scene_to_file(MENU_SCENE)
		return

	SkirmishState.begin_session()
	_target = SkirmishState.DECK_TARGET
	_rng.seed = NetMatch.match_seed ^ ((SkirmishState.local_index + 1) * 0x6C62272E)
	_build_pool()

	NetMatch.draft_event_received.connect(_on_draft_event)
	NetMatch.peer_left.connect(_on_peer_lost)
	NetMatch.host_closed.connect(_on_peer_lost)

	# Every net game opens with the shared arsenal stage (the host sets how many
	# relic and potion picks it offers; 0 + 0 raises no stage at all);
	# present it before constructing the obscured 100+ card catalogue.
	_begin_arsenal()
	_prepare_mode_ui()


func _prepare_mode_ui() -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await get_tree().process_frame
	if not is_inside_tree() or not NetMatch.is_connected_to_peer():
		return
	_build_scaffold()
	_mode_ui_ready = true
	_refresh_all()
	_install_net_chrome()
	_flatten_net_chart_styles(self)


# ─────────────────────────────────────────────────────────────────────────
#  POOL
# ─────────────────────────────────────────────────────────────────────────

func _build_pool() -> void:
	_pool.clear()
	_pool_data.clear()
	_pool_sort_keys.clear()
	for raw_id in SkirmishState.skirmish_legal_pool():
		var id := String(raw_id)
		var data: Dictionary = SkirmishState.skirmish_card_data(id)
		_pool.append(id)
		_pool_data[id] = data
		_pool_sort_keys[id] = {
			"cost": int(data.get("cost", 0)),
			"name": String(data.get("name", id)).to_lower(),
		}
	# CardDB returns deep copies. Sorting against the cached scalar key avoids
	# hundreds of dictionary copies every time this full catalogue is ordered.
	_pool.sort_custom(_pool_sort_before)


func _pool_sort_before(a: String, b: String) -> bool:
	var ka: Dictionary = _pool_sort_keys.get(a, {})
	var kb: Dictionary = _pool_sort_keys.get(b, {})
	var ca: int = int(ka.get("cost", 0))
	var cb: int = int(kb.get("cost", 0))
	if ca != cb:
		return ca < cb
	return String(ka.get("name", a)) < String(kb.get("name", b))


# ─────────────────────────────────────────────────────────────────────────
#  UI BUILD
# ─────────────────────────────────────────────────────────────────────────

func _build_scaffold() -> void:
	_root = VBoxContainer.new()
	_root.name = "Constructed"
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 12)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_top = 24
	_root.offset_bottom = -20
	_root.offset_left = 40
	_root.offset_right = -40
	add_child(_root)

	_root.add_child(GameTheme.make_screen_title("BUILD YOUR DECK", GILT_BRIGHT))

	_header = GameTheme.make_label("Choose any 20 cards from the full card pool.", 17, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	# Two column plates: the muster roll (left) and the working warband (right).
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)

	# ── Pool column ──
	var pool := _make_builder_column("CARD POOL", 1.4)
	cols.add_child(pool.panel)
	_pool_box = pool.flow
	_pool_scroll = pool.scroll
	_pool_scroll.get_v_scroll_bar().value_changed.connect(_on_pool_scroll_changed)
	_pool_scroll.resized.connect(_on_pool_scroll_resized)
	# Lay out cheap fixed-size ghosts first. The virtual window below replaces only
	# nearby ghosts with 1x gallery snapshots, so opening this 100+ card catalogue
	# no longer waits for every painting and Card2D.
	_populate_pool()

	# ── Deck column ──
	var deck := _make_builder_column("DECK  0 / %d" % _target, 1.0)
	cols.add_child(deck.panel)
	_deck_count_lbl = deck.header
	_deck_box = deck.flow

	# Running cost histogram — the build readout that earns the column's air.
	(deck.col as VBoxContainer).add_child(_make_curve_strip())

	# Deck-tools row.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	(deck.col as VBoxContainer).add_child(tools)
	var fill_btn := GameTheme.make_themed_button("FILL RANDOM",
		Color(0.20, 0.17, 0.13), Vector2(140, 32), 13)
	fill_btn.pressed.connect(_on_fill_random)
	tools.add_child(fill_btn)
	var clear_btn := GameTheme.make_themed_button("CLEAR",
		Color(0.30, 0.18, 0.16), Vector2(100, 32), 13)
	clear_btn.pressed.connect(_on_clear)
	tools.add_child(clear_btn)

	# Saved-decks row: name + SAVE (keep a finished warband), and a picker +
	# LOAD / DELETE to reuse one without drafting or rebuilding.
	var saved := HBoxContainer.new()
	saved.add_theme_constant_override("separation", 6)
	(deck.col as VBoxContainer).add_child(saved)
	_name_field = _make_ink_field("", 120, "Deck name")
	saved.add_child(_name_field)
	var save_btn := GameTheme.make_themed_button("SAVE",
		Color(0.20, 0.17, 0.13), Vector2(72, 32), 14)
	save_btn.pressed.connect(_on_save_deck)
	saved.add_child(save_btn)
	_saved_option = OptionButton.new()
	_saved_option.custom_minimum_size = Vector2(150, 32)
	_saved_option.fit_to_longest_item = false
	_style_option_chip(_saved_option)
	saved.add_child(_saved_option)
	var load_btn := GameTheme.make_themed_button("LOAD",
		Color(0.20, 0.17, 0.13), Vector2(72, 32), 14)
	load_btn.pressed.connect(_on_load_deck)
	saved.add_child(load_btn)
	var del_btn := GameTheme.make_themed_button("DELETE",
		Color(0.30, 0.18, 0.16), Vector2(60, 32), 14)
	del_btn.pressed.connect(_on_delete_deck)
	saved.add_child(del_btn)
	_refresh_saved_options()

	# Bottom: READY + status.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 18)
	_root.add_child(bottom)

	# Ember commit tile, matching every other skirmish screen. (Audit 2026-07-21.)
	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.34, 0.22, 0.08), Vector2(180, 44), 17)
	_ready_btn.pressed.connect(_on_ready_pressed)
	bottom.add_child(_ready_btn)

	_status = GameTheme.make_label("", 16, ASH)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)


func _populate_pool() -> void:
	_pool_generation += 1
	var generation: int = _pool_generation
	_pool_hydration_generation = -1
	_pool_virtual_accum = 0.0
	_pool_refresh_queued = false
	_clear_hover_preview_under(_pool_box)
	for child in _pool_box.get_children():
		_pool_box.remove_child(child)
		child.queue_free()
	_pool_jobs.clear()
	_pool_rows.clear()
	_ensure_pool_shared_styles()

	for id in _pool:
		if not _pool_build_valid(generation):
			return
		var data: Dictionary = _pool_data.get(id, {})
		var parts: Dictionary = _make_pool_slot(id, data)
		var slot: Control = parts["slot"]
		_pool_box.add_child(slot)
		_pool_jobs.append({
			"id": id,
			"data": data,
			"slot": slot,
			"visual": parts["visual"],
			"state": "placeholder",
			"busy": false,
		})
		_pool_rows[id] = {
			"button": parts["button"],
			"badge": parts["badge"],
			"card": parts["visual"],
			"hydrated": false,
		}
		_apply_pool_row_state(id, _deck.size() >= _target)

	# The flow needs one layout pass before slot global rects are meaningful.
	await get_tree().process_frame
	if _pool_build_valid(generation):
		_refresh_pool_virtual_window(generation)


func _pool_build_valid(generation: int) -> bool:
	return generation == _pool_generation and is_inside_tree() \
		and _pool_box != null and is_instance_valid(_pool_box) \
		and _pool_scroll != null and is_instance_valid(_pool_scroll)


func _pool_hydration_valid(generation: int) -> bool:
	return _pool_build_valid(generation) \
		and _pool_hydration_generation == generation \
		and not arsenal_active()


func _ensure_pool_shared_styles() -> void:
	if _pool_empty_style != null:
		return
	_pool_empty_style = StyleBoxEmpty.new()
	_pool_hover_style = StyleBoxFlat.new()
	_pool_hover_style.bg_color = Color(1, 1, 1, 0.0)
	_pool_hover_style.border_color = Color(
		GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.85)
	_pool_hover_style.set_border_width_all(2)
	_pool_hover_style.set_corner_radius_all(6)
	_pool_badge_style = StyleBoxFlat.new()
	_pool_badge_style.bg_color = Color(0.06, 0.05, 0.04, 0.92)
	_pool_badge_style.border_color = GameTheme.GILT
	_pool_badge_style.set_border_width_all(1)
	_pool_badge_style.set_corner_radius_all(4)


func _make_pool_slot(id: String, data: Dictionary) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = POOL_THUMB_SIZE
	slot.size = POOL_THUMB_SIZE
	slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slot.mouse_filter = Control.MOUSE_FILTER_PASS

	var visual := _make_pool_placeholder_visual(data)
	slot.add_child(visual)
	visual.set_anchors_preset(Control.PRESET_FULL_RECT)

	# This permanent hit target survives placeholder/card swaps, so click, tooltip,
	# focus and hover-preview signals never need to be reconnected while scrolling.
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _pool_empty_style)
	button.add_theme_stylebox_override("focus", _pool_empty_style)
	button.add_theme_stylebox_override("hover", _pool_hover_style)
	button.add_theme_stylebox_override("pressed", _pool_hover_style)
	slot.add_child(button)
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(_on_add.bind(id))
	button.tooltip_text = String(data.get("name", id))
	_attach_hover_preview(button, id)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 16)
	if GameTheme.font_stat != null:
		badge.add_theme_font_override("font", GameTheme.font_stat)
	badge.add_theme_color_override("font_color", GILT_BRIGHT)
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("normal", _pool_badge_style)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -36.0
	badge.offset_right = -5.0
	badge.offset_top = -27.0
	badge.offset_bottom = -5.0
	badge.visible = false
	slot.add_child(badge)

	return {"slot": slot, "visual": visual, "button": button, "badge": badge}


func _make_pool_placeholder_visual(data: Dictionary) -> Control:
	var ghost := PoolCardGhost.new()
	ghost.configure(data, GameTheme.font_body)
	return ghost


func _process(delta: float) -> void:
	if _pool_jobs.is_empty() or arsenal_active():
		return
	_pool_virtual_accum += delta
	if _pool_virtual_accum < POOL_VIRTUAL_REFRESH:
		return
	_pool_virtual_accum = fmod(_pool_virtual_accum, POOL_VIRTUAL_REFRESH)
	_refresh_pool_virtual_window(_pool_generation)


func _exit_tree() -> void:
	# Invalidates both a threaded art prewarm and a bake parked across render
	# frames. Each path releases any source-art pin before it returns.
	_pool_generation += 1
	_pool_hydration_generation = -1
	_pool_refresh_queued = false


func _on_pool_scroll_changed(_value: float) -> void:
	_queue_pool_virtual_refresh()


func _on_pool_scroll_resized() -> void:
	_queue_pool_virtual_refresh()


func _queue_pool_virtual_refresh() -> void:
	if _pool_jobs.is_empty() or _pool_refresh_queued or arsenal_active():
		return
	_pool_refresh_queued = true
	call_deferred("_flush_pool_virtual_refresh", _pool_generation)


func _flush_pool_virtual_refresh(generation: int) -> void:
	_pool_refresh_queued = false
	if _pool_build_valid(generation) and not arsenal_active():
		_refresh_pool_virtual_window(generation)


func _pool_virtual_rect(margin_screens: float) -> Rect2:
	if _pool_scroll == null or not is_instance_valid(_pool_scroll):
		return Rect2()
	var viewport_rect := _pool_scroll.get_global_rect()
	var margin := viewport_rect.size.y * margin_screens
	return Rect2(
		Vector2(viewport_rect.position.x, viewport_rect.position.y - margin),
		Vector2(viewport_rect.size.x, viewport_rect.size.y + margin * 2.0))


func _pool_job_intersects(job: Dictionary, rect: Rect2) -> bool:
	var slot: Control = job.get("slot", null)
	return slot != null and is_instance_valid(slot) and slot.is_inside_tree() \
		and slot.get_global_rect().intersects(rect)


func _refresh_pool_virtual_window(generation: int) -> void:
	if not _pool_build_valid(generation) or arsenal_active():
		return
	var cold_rect := _pool_virtual_rect(POOL_COLD_MARGIN_SCREENS)
	for i in range(_pool_jobs.size()):
		var job: Dictionary = _pool_jobs[i]
		if String(job.get("state", "")) != "card" \
				or _pool_job_intersects(job, cold_rect):
			continue
		var card: Control = job.get("visual", null)
		var slot: Control = job.get("slot", null)
		if card == null or slot == null or not is_instance_valid(card) \
				or not is_instance_valid(slot):
			continue
		var ghost := _make_pool_placeholder_visual(job.get("data", {}))
		slot.add_child(ghost)
		ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.move_child(ghost, 0)
		slot.remove_child(card)
		card.queue_free()
		job["visual"] = ghost
		job["state"] = "placeholder"
		job["busy"] = false
		_pool_jobs[i] = job
		_set_pool_row_visual(String(job.get("id", "")), ghost, false)
	if _pool_hydration_generation != generation:
		_hydrate_visible_pool_cards(generation)


func _pool_placeholder_batch(rect: Rect2) -> Array[int]:
	var indices: Array[int] = []
	for i in range(_pool_jobs.size()):
		var job: Dictionary = _pool_jobs[i]
		if String(job.get("state", "")) == "placeholder" \
				and not bool(job.get("busy", false)) \
				and _pool_job_intersects(job, rect):
			indices.append(i)
	return indices


func _hydrate_visible_pool_cards(generation: int) -> void:
	_pool_hydration_generation = generation
	while _pool_hydration_valid(generation):
		# Capture a whole visible set before doing any expensive work. Faces stage
		# hidden over their named backs and commit together only after the batch is
		# complete; the runway is a second (normally offscreen) batch.
		var batch := _pool_placeholder_batch(_pool_virtual_rect(0.0))
		if batch.is_empty():
			batch = _pool_placeholder_batch(_pool_virtual_rect(POOL_WARM_MARGIN_SCREENS))
		if batch.is_empty():
			break

		var staged: Array[int] = []
		var hydrated_since_yield := 0
		for raw_job_index in batch:
			if not _pool_hydration_valid(generation):
				break
			var job_index: int = raw_job_index
			var job: Dictionary = _pool_jobs[job_index]
			job["busy"] = true
			_pool_jobs[job_index] = job
			var data: Dictionary = job.get("data", {})
			var baked: Texture2D = null
			var loaded_source_art := false
			if CardTextureCache.has_gallery(data):
				baked = CardTextureCache.get_gallery_texture(data)
			elif DisplayServer.get_name() == "headless":
				# Dummy rendering never posts the frame signal needed by the baker. Leave
				# the fixed named back in place for headless behavior probes.
				job["busy"] = false
				_pool_jobs[job_index] = job
				break
			else:
				await CardArtAliases.prewarm_card_art(data)
				loaded_source_art = true
				if not _pool_hydration_valid(generation):
					CardArtAliases.release_card_art(data)
					_clear_pool_job_busy(job_index, generation)
					break
				baked = await CardTextureCache.bake_gallery(
					data, _pool_hydration_valid.bind(generation))
			if loaded_source_art:
				# The gallery texture owns the flattened pixels; keeping the full source
				# painting pinned would defeat the memory bound provided by virtualization.
				CardArtAliases.release_card_art(data)
			if not _pool_hydration_valid(generation):
				_clear_pool_job_busy(job_index, generation)
				break

			job = _pool_jobs[job_index]
			job["busy"] = false
			if baked == null:
				_pool_jobs[job_index] = job
				break
			var slot: Control = job.get("slot", null)
			var old_visual: Control = job.get("visual", null)
			if slot != null and old_visual != null and is_instance_valid(slot) \
					and is_instance_valid(old_visual) \
					and _pool_job_intersects(job,
						_pool_virtual_rect(POOL_COLD_MARGIN_SCREENS)):
				var card = POOL_CARD_SCENE.instantiate()
				card.card_data = data.duplicate(true)
				card.card_id = data.get("id", "")
				card.is_on_battlefield = true
				card.static_display = true
				card.live_baked_mode = true
				card.gallery_baked_mode = true
				card.scale = Vector2(THUMB_SCALE, THUMB_SCALE)
				card.position = Vector2.ZERO
				slot.add_child(card)
				# Keep the named back in front until every face in this viewport batch
				# is complete. The face is edge-hidden, not progressively exposed.
				slot.move_child(card, 1)
				_stage_complete_hand_member(card)
				job["pending_visual"] = card
				job["state"] = "staged"
				staged.append(job_index)
			_pool_jobs[job_index] = job

			hydrated_since_yield += 1
			if hydrated_since_yield >= POOL_HYDRATE_YIELD_EVERY:
				hydrated_since_yield = 0
				await get_tree().process_frame

		if not _pool_hydration_valid(generation):
			break
		if staged.is_empty():
			break

		var faces: Array[Control] = []
		var covers: Array[Control] = []
		for job_index in staged:
			if job_index < 0 or job_index >= _pool_jobs.size():
				continue
			var job: Dictionary = _pool_jobs[job_index]
			var slot: Control = job.get("slot", null)
			var face: Control = job.get("pending_visual", null)
			var cover: Control = job.get("visual", null)
			job.erase("pending_visual")
			if slot == null or face == null or cover == null \
					or not is_instance_valid(slot) or not is_instance_valid(face) \
					or not is_instance_valid(cover) \
					or not _pool_job_intersects(job,
						_pool_virtual_rect(POOL_COLD_MARGIN_SCREENS)):
				if face != null and is_instance_valid(face):
					face.queue_free()
				job["state"] = "placeholder"
				job["busy"] = false
				_pool_jobs[job_index] = job
				continue
			job["visual"] = face
			job["state"] = "card"
			job["busy"] = false
			_pool_jobs[job_index] = job
			# The ornate face exists, but the permanent hit target stays locked until
			# the entire viewport batch has completed its shared turn.
			_set_pool_row_visual(String(job.get("id", "")), face, false)
			faces.append(face)
			covers.append(cover)
		await _reveal_complete_hand(faces, covers)
		if not _pool_hydration_valid(generation):
			break
		for job_index in staged:
			if job_index < 0 or job_index >= _pool_jobs.size():
				continue
			var revealed_job: Dictionary = _pool_jobs[job_index]
			var revealed_face: Control = revealed_job.get("visual", null)
			if String(revealed_job.get("state", "")) != "card" \
					or revealed_face == null or not is_instance_valid(revealed_face):
				continue
			_set_pool_row_visual(String(revealed_job.get("id", "")),
				revealed_face, true)
	_pool_hydration_generation = -1 \
		if _pool_hydration_generation == generation \
		else _pool_hydration_generation


func _clear_pool_job_busy(job_index: int, generation: int) -> void:
	if generation != _pool_generation or job_index < 0 \
			or job_index >= _pool_jobs.size():
		return
	var job: Dictionary = _pool_jobs[job_index]
	job["busy"] = false
	_pool_jobs[job_index] = job


func _set_pool_row_visual(id: String, visual: Control,
		hydrated: bool = true) -> void:
	if not _pool_rows.has(id):
		return
	var refs: Dictionary = _pool_rows[id]
	refs["card"] = visual
	refs["hydrated"] = hydrated
	_pool_rows[id] = refs
	_apply_pool_row_state(id, _deck.size() >= _target)


# ─────────────────────────────────────────────────────────────────────────
#  DECK EDITING
# ─────────────────────────────────────────────────────────────────────────

func _on_add(id: String) -> void:
	if _local_finished or not _pool_rows.has(id) \
			or not bool((_pool_rows[id] as Dictionary).get("hydrated", false)):
		return
	if _deck.size() >= _target:
		return
	if int(_counts.get(id, 0)) >= MAX_COPIES:
		return
	var pool_refs: Dictionary = _pool_rows.get(id, {})
	var source_button: Button = pool_refs.get("button", null)
	if source_button != null and is_instance_valid(source_button):
		GameTheme.claim_pop(source_button)
	_deck.append(id)
	_counts[id] = int(_counts.get(id, 0)) + 1
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_refresh_all(id, 1)


func _on_remove(id: String) -> void:
	if _local_finished:
		return
	var idx := _deck.rfind(id)
	if idx < 0:
		return
	_deck.remove_at(idx)
	_counts[id] = max(0, int(_counts.get(id, 0)) - 1)
	if int(_counts[id]) == 0:
		_counts.erase(id)
	_refresh_all(id, -1)


func _on_clear() -> void:
	if _local_finished:
		return
	_deck.clear()
	_counts.clear()
	_refresh_all()


func _on_fill_random() -> void:
	if _local_finished or _pool.is_empty():
		return
	var blocked: Array[String] = []
	for counted_id in _counts.keys():
		if int(_counts.get(counted_id, 0)) > 0:
			blocked.append(String(counted_id))
	var need: int = _target - _deck.size()
	for dealt_id in SkirmishState.deal_weighted_cards(_pool, need, _rng,
			SkirmishState.SKIRMISH_DRAFT_WEIGHTS, blocked):
		if _deck.size() >= _target:
			break
		_deck.append(dealt_id)
		_counts[dealt_id] = int(_counts.get(dealt_id, 0)) + 1

	# Fallback only matters if the legal pool is smaller than the deck target.
	var guard := 0
	while _deck.size() < _target and guard < 4000:
		guard += 1
		var pick_id: String = _pool[_rng.randi() % _pool.size()]
		if int(_counts.get(pick_id, 0)) < MAX_COPIES:
			_deck.append(pick_id)
			_counts[pick_id] = int(_counts.get(pick_id, 0)) + 1
	_refresh_all()


# ─────────────────────────────────────────────────────────────────────────
#  SAVED DECKS  (save a finished warband / reuse one without rebuilding)
# ─────────────────────────────────────────────────────────────────────────

func _refresh_saved_options() -> void:
	if _saved_option == null:
		return
	_saved_option.clear()
	var saved := SavedDecks.list_decks()
	if saved.is_empty():
		_saved_option.add_item("(no saved decks)")
		_saved_option.disabled = true
		return
	_saved_option.disabled = false
	for i in saved.size():
		var nm := String(saved[i].get("name", "Deck"))
		var n := (saved[i].get("cards", []) as Array).size()
		_saved_option.add_item("%s  (%d)" % [nm, n])


func _on_save_deck() -> void:
	if _local_finished:
		return
	if _deck.size() != _target:
		_flash_status("Build a full %d-card deck before saving." % _target, RED_WARN)
		return
	var nm := SavedDecks.save_deck(_name_field.text, _deck)
	_refresh_saved_options()
	_flash_status("Saved \"%s\"." % nm, GREEN)


func _on_load_deck() -> void:
	if _local_finished or SavedDecks.count() == 0:
		return
	var idx := _saved_option.selected
	var cards := SavedDecks.get_cards(idx)
	if cards.is_empty():
		return
	_deck.clear()
	_counts.clear()
	for cid in cards:
		var id := String(cid)
		if not _pool.has(id):
			continue                     # card no longer skirmish-legal — skip
		if _deck.size() >= _target:
			break
		if int(_counts.get(id, 0)) >= MAX_COPIES:
			continue
		_deck.append(id)
		_counts[id] = int(_counts.get(id, 0)) + 1
	_refresh_all()
	_flash_status("Loaded \"%s\"." % SavedDecks.deck_name(idx), GREEN)


func _on_delete_deck() -> void:
	if SavedDecks.count() == 0:
		return
	SavedDecks.delete_deck(_saved_option.selected)
	_refresh_saved_options()


## Transient one-liner in the status line (overwritten by the next _refresh_all).
## IT DID NOT FLASH. It set text and colour and stopped, so the one case that
## most needs feedback got none: pressing SAVE twice against the same refusal
## ("Build a full 30-card deck before saving.") rewrote identical text in an
## identical colour, i.e. NOTHING on screen changed and the second press read as
## a dead button. That is the silent-refusal class `_probe_silent_refusal`
## exists for, arriving through a function whose NAME already promised the fix.
##
## The colour is set BEFORE the pulse on purpose: `pulse_label` reads the
## label's current theme colour as its rest state, so setting it after would
## make the label settle back to the previous message's colour.
func _flash_status(msg: String, col: Color) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", col)
		Motion.pulse_label(_status, Color(1.0, 0.95, 0.72))


# ─────────────────────────────────────────────────────────────────────────
#  REFRESH
# ─────────────────────────────────────────────────────────────────────────

func _refresh_all(changed_id: String = "", change: int = 0) -> void:
	_refresh_pool_counts()
	_refresh_deck_panel(changed_id, change)
	_update_ready()
	if change != 0 and _deck_count_lbl != null:
		Motion.pulse_label(_deck_count_lbl, GILT_BRIGHT if change > 0 else RED_WARN)
	_update_status()


func _refresh_pool_counts() -> void:
	var full := _deck.size() >= _target
	for id in _pool_rows:
		_apply_pool_row_state(String(id), full)


func _apply_pool_row_state(id: String, full: bool) -> void:
	if not _pool_rows.has(id):
		return
	var n := int(_counts.get(id, 0))
	var refs: Dictionary = _pool_rows[id]
	var badge: Label = refs.get("badge", null)
	var button: Button = refs.get("button", null)
	var visual: Control = refs.get("card", null)
	var hydrated := bool(refs.get("hydrated", false))
	if badge != null and is_instance_valid(badge):
		badge.text = "×%d" % n
		badge.visible = n > 0
	var copies_maxed := n >= MAX_COPIES
	if button != null and is_instance_valid(button):
		button.set_meta("card_loading", not hydrated)
		button.disabled = not hydrated or _local_finished or full or copies_maxed
	if visual != null and is_instance_valid(visual):
		visual.modulate = Color(0.45, 0.45, 0.45, 0.8) \
			if copies_maxed else Color.WHITE


func _refresh_deck_panel(changed_id: String = "", change: int = 0) -> void:
	_clear_hover_preview_under(_deck_box)   # a previewed deck tile may be freed below
	for c in _deck_box.get_children():
		_deck_box.remove_child(c)
		c.queue_free()
	# Keep cost/name order, but render each physical copy. Together with the
	# vacant slots this holds the HFlow at exactly twenty footprints throughout.
	var ids := _counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _pool_sort_before(a, b))
	for raw_id in ids:
		var id := String(raw_id)
		var n := int(_counts[id])
		if n <= 0:
			continue
		for copy_idx in n:
			var d: Dictionary = _pool_data.get(id, {})
			var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
			(thumb["badge"] as Label).visible = false
			var btn := thumb["button"] as Button
			btn.tooltip_text = "%s — click to remove" % String(d.get("name", id))
			_attach_hover_preview(btn, id)
			if _local_finished:
				btn.disabled = true
			else:
				btn.pressed.connect(_on_remove.bind(id))
			var root := thumb["root"] as Control
			_deck_box.add_child(root)
			if change > 0 and id == changed_id and copy_idx == n - 1:
				Motion.deal_card(root, 0.0, {"face": thumb["card"],
					"from": Vector2(-54.0, 20.0), "spin": -0.08,
					"dur": 0.24, "bow": 0.10})
	var missing: int = maxi(_target - _deck.size(), 0)
	for _i in missing:
		_deck_box.add_child(_make_deck_ghost_slot())


func _update_ready() -> void:
	_refresh_curve(_deck)
	if _deck_count_lbl != null:
		_deck_count_lbl.text = "DECK  %d / %d" % [_deck.size(), _target]
		_deck_count_lbl.add_theme_color_override("font_color",
			GREEN if _deck.size() == _target else IVORY)
	if _ready_btn != null:
		_ready_btn.disabled = _local_finished or _deck.size() != _target


func _update_status() -> void:
	if _status == null:
		return
	var you := "READY" if _local_finished else ("building (%d/%d)" % [_deck.size(), _target])
	var opp := "READY" if _remote_finished else "building…"
	_status.text = "You: %s   ·   Opponent: %s" % [you, opp]
	_status.add_theme_color_override("font_color",
		GREEN if (_local_finished and _remote_finished) else ASH)


# ─────────────────────────────────────────────────────────────────────────
#  READY / HANDOFF  (mirrors NetDraft finish tail)
# ─────────────────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	if _local_finished or _deck.size() != _target:
		return
	_local_finished = true
	# Commit the built deck to SkirmishState (deterministic uids assigned in order).
	for id in _deck:
		SkirmishState.add_card_to(SkirmishState.local_index, id)
	# Ship the full deck to the peer (same "finished" contract as the draft).
	NetMatch.send_draft_event({"t": "finished",
		"cards": SkirmishState.local_slot().deck.duplicate(),
		"relics": SkirmishState.local_slot().relics.duplicate(),
		"potions": SkirmishState.local_slot().potions.duplicate()})
	# Bake the sealed warband's textures behind the waiting screen (idle time).
	ScenePreload.warm_card_ids(_deck, true)
	if _ready_btn != null:
		_ready_btn.text = "READY ✓"
	_refresh_all()
	_show_waiting()
	_maybe_begin_combat()


func _on_draft_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		"finished":
			_remote_finished = true
			_store_opponent_deck(event.get("cards", []))
			var opp_slot := SkirmishState.get_slot(SkirmishState.opponent_index())
			if opp_slot != null:
				opp_slot.relics = event.get("relics", [])
				opp_slot.potions = event.get("potions", [])
			_update_status()
			_maybe_begin_combat()


func _store_opponent_deck(cards: Array) -> void:
	var opp := SkirmishState.opponent_index()
	var slot := SkirmishState.get_slot(opp)
	if slot == null:
		return
	slot.deck.clear()
	slot.deck_uids.clear()
	for cid in cards:
		SkirmishState.add_card_to(opp, String(cid))


func _maybe_begin_combat() -> void:
	if not _claim_combat_launch():
		return
	_show_marching()
	if NetMatch.is_host:
		NetMatch.launch_combat(true)


# ─────────────────────────────────────────────────────────────────────────
#  STATUS SCREENS
# ─────────────────────────────────────────────────────────────────────────

func _show_waiting() -> void:
	if _header != null and not _remote_finished:
		_header.text = "Deck ready — waiting for your opponent…"
		_header.add_theme_color_override("font_color", ASH)


func _show_marching() -> void:
	if _header != null:
		_header.text = "Both decks ready — starting the match…"
		_header.add_theme_color_override("font_color", GREEN)
		Motion.pulse_label(_header, GILT_BRIGHT)


func _on_peer_lost(_id: int = 0) -> void:
	if _root == null:
		return
	if _header != null:
		_header.text = "Opponent disconnected — the match is off."
		_header.add_theme_color_override("font_color", RED_WARN)
	if _status != null:
		_status.text = ""
	if _ready_btn != null:
		_ready_btn.disabled = true
	var back := GameTheme.make_themed_button("BACK TO MENU",
		Color(0.26, 0.16, 0.14), Vector2(220, 44), 16)
	back.pressed.connect(_leave_to_menu.bind(back))
	_root.add_child(back)
