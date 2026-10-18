extends "res://scripts/scenes/NetDeckBuilder.gd"
## NetSealed.gd — Sealed mode: each player OPENS a fixed pool of cards rolled from
## the shared seed, then builds a DECK_TARGET-card deck using only what they pulled
## (each card capped at the number of copies opened). Half luck-of-the-pull, half
## deckbuilding skill.
##
## Pool config (host-controlled, broadcast before READY — mirrors NetQuick):
##   Sealed (default): seed salted per side → each player opens a DIFFERENT pool.
##   Mirror: no salt → both open the IDENTICAL pool (a fair build-off).
##   REROLL (host) picks a fresh sub-seed and rebroadcasts; the client regenerates.
##
## Deck handoff (mirrors NetDraft/NetQuick):
##   local deck → "finished" event → peer stores it → _maybe_begin_combat.

# MENU_SCENE, THUMB_SCALE, the palette, and the shared sync flags / refs
# (_target, _rng, _local_finished, _remote_finished, _root, _header, _pool_rows)
# are inherited from NetDeckBuilder.

# How many cards are opened into the sealed pool, and the most copies of any one
# id the pool will contain (so a roll can't hand you 30 of the same card).
const SEALED_POOL_SIZE: int = 30
const SEALED_MAX_PER_ID: int = 3

var _legal: Array[String] = []   # full skirmish-legal pool (the roll source)
var _avail: Dictionary = {}      # id -> copies opened into the sealed pool
var _deck: Array[String] = []    # working deck (ids), in add order
var _counts: Dictionary = {}     # id -> copies currently in deck

# Host-broadcast pool config.
var _mirror: bool = false        # Sealed (per-side) by default
var _sub_seed: int = 0           # 0 = use base seed unchanged

# UI refs.
var _status: Label
var _pool_grid: HFlowContainer
var _deck_box: HFlowContainer
var _deck_count_lbl: Label
var _ready_btn: Button
var _mirror_btn: Button
var _reroll_btn: Button
# Bumped each pool rebuild; the async bake loop checks it after every await so a
# re-sort / reopen that fires mid-build abandons the stale stream cleanly.
var _pool_gen: int = 0
var _pool_catalog: Dictionary = {}
var _sorted_pool_ids: Array[String] = []
var _mode_ui_ready := false
var _pool_ui_ready := false


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")
	AudioBank.play_music_random(["net_lobby", "net_lobby_b", "rest_c"])  # muster pool

	if not NetMatch.is_connected_to_peer():
		get_tree().change_scene_to_file(MENU_SCENE)
		return

	SkirmishState.begin_session()
	_target = SkirmishState.DECK_TARGET
	for id in SkirmishState.skirmish_legal_pool():
		_legal.append(String(id))

	NetMatch.draft_event_received.connect(_on_draft_event)
	NetMatch.peer_left.connect(_on_peer_lost)
	NetMatch.host_closed.connect(_on_peer_lost)

	if NetMatch.is_host:
		_sub_seed = 0
		_broadcast_cfg()
	_regenerate_pool()
	# Every net game opens with the shared arsenal stage (the host sets how many
	# relic and potion picks it offers; 0 + 0 raises no stage at all);
	# present it before constructing the obscured pool and deck columns.
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
	_rebuild_pool_ui()
	_refresh_all()
	_install_net_chrome()
	_flatten_net_chart_styles(self)


# ─────────────────────────────────────────────────────────────────────────
#  POOL GENERATION
# ─────────────────────────────────────────────────────────────────────────

func _effective_seed() -> int:
	var base: int = SkirmishState.rng_seed
	if _sub_seed != 0:
		base = base ^ (_sub_seed * 0x9E3779B9)
	if not _mirror:
		base = base ^ ((SkirmishState.local_index + 1) * 0x6C62272E)
	return base


func _regenerate_pool() -> void:
	_rng.seed = _effective_seed()
	_avail.clear()

	var opened: Array[String] = SkirmishState.deal_weighted_cards(
		_legal, mini(SEALED_POOL_SIZE, _legal.size()), _rng,
		SkirmishState.SKIRMISH_DRAFT_WEIGHTS)
	for opened_id in opened:
		_avail[opened_id] = 1

	var rolled := opened.size()
	var guard := 0
	# Tiny-pool fallback: duplicate only after the unique bag is exhausted.
	while rolled < SEALED_POOL_SIZE and guard < 6000 and not _legal.is_empty():
		guard += 1
		var roll_id: String = _legal[_rng.randi() % _legal.size()]
		var c: int = int(_avail.get(roll_id, 0))
		if c < SEALED_MAX_PER_ID:
			_avail[roll_id] = c + 1
			rolled += 1
	# The pool changed underneath the builder — start the deck fresh.
	_deck.clear()
	_counts.clear()
	_rebuild_pool_catalog()


func _rebuild_pool_catalog() -> void:
	_pool_catalog.clear()
	_sorted_pool_ids.clear()
	for raw_id in _avail.keys():
		var id := String(raw_id)
		_pool_catalog[id] = SkirmishState.skirmish_card_data(id)
		_sorted_pool_ids.append(id)
	_sorted_pool_ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := int((_pool_catalog[a] as Dictionary).get("cost", 0))
		var cb := int((_pool_catalog[b] as Dictionary).get("cost", 0))
		if ca != cb:
			return ca < cb
		return String((_pool_catalog[a] as Dictionary).get("name", a)) < \
			String((_pool_catalog[b] as Dictionary).get("name", b)))


func _sorted_avail_ids() -> Array:
	return _sorted_pool_ids


# ─────────────────────────────────────────────────────────────────────────
#  UI BUILD
# ─────────────────────────────────────────────────────────────────────────

func _build_scaffold() -> void:
	_root = VBoxContainer.new()
	_root.name = "Sealed"
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 12)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_top = 24
	_root.offset_bottom = -20
	_root.offset_left = 40
	_root.offset_right = -40
	add_child(_root)

	_root.add_child(GameTheme.make_screen_title("BUILD YOUR DECK", GILT_BRIGHT))

	_header = GameTheme.make_label("Build 20 from the cards you opened.", 17, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)

	# ── Opened-pool column ──
	var pool := _make_builder_column("YOUR POOL", 1.4)
	cols.add_child(pool.panel)
	_pool_grid = pool.flow

	# ── Deck column ──
	var deck := _make_builder_column("DECK  0 / %d" % _target, 1.0)
	cols.add_child(deck.panel)
	_deck_count_lbl = deck.header
	_deck_box = deck.flow

	# Running cost histogram — the build readout that earns the column's air.
	(deck.col as VBoxContainer).add_child(_make_curve_strip())

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	(deck.col as VBoxContainer).add_child(tools)
	var fill_btn := GameTheme.make_themed_button("AUTO-FILL",
		Color(0.20, 0.17, 0.13), Vector2(130, 32), 13)
	fill_btn.pressed.connect(_on_fill)
	tools.add_child(fill_btn)
	var clear_btn := GameTheme.make_themed_button("CLEAR",
		Color(0.30, 0.18, 0.16), Vector2(100, 32), 13)
	clear_btn.pressed.connect(_on_clear)
	tools.add_child(clear_btn)

	# Bottom: host pool controls + READY + status.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	_root.add_child(bottom)

	# Muted ash-brown for the secondary toggle, ember for the commit below —
	# the same two-tone the other skirmish screens use, replacing a blue tile
	# and a green one. Caps to match its row. (Audit 2026-07-21.)
	if NetMatch.is_host:
		# NOT "SEALED" / "MIRROR". This toggle answers "do both players open the
		# SAME pool or their own?", and its off-state used to be labelled with the
		# MODE'S OWN NAME — a button reading SEALED, on the Sealed screen, under a
		# status line already reading "[Sealed]". Nothing on screen distinguished
		# the setting from the format, and pressing it appeared to turn on the
		# thing you were already doing. Its identical twin in Quick Battle has
		# always said MIRRORED / RANDOM, which collides with nothing — so this now
		# says the same words, and carries the same explanatory tooltip, which it
		# was missing entirely.
		_mirror_btn = GameTheme.make_themed_button("MIRRORED" if _mirror else "RANDOM",
			Color(0.20, 0.17, 0.13), Vector2(130, 38), 14)
		_mirror_btn.tooltip_text = "Host only: Mirrored opens the same pool for both players; Random opens each side its own."
		_mirror_btn.pressed.connect(_on_toggle_mirror)
		bottom.add_child(_mirror_btn)
		_reroll_btn = GameTheme.make_themed_button("NEW POOL",
			Color(0.28, 0.20, 0.10), Vector2(120, 38), 14)
		_reroll_btn.tooltip_text = "Host only: open both pools again."
		_reroll_btn.pressed.connect(_on_reroll)
		bottom.add_child(_reroll_btn)

	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.34, 0.22, 0.08), Vector2(170, 44), 17)
	_ready_btn.pressed.connect(_on_ready_pressed)
	bottom.add_child(_ready_btn)

	_status = GameTheme.make_label("", 16, ASH)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)


func _rebuild_pool_ui() -> void:
	if _pool_grid == null:
		return
	_pool_ui_ready = false
	_clear_hover_preview_under(_pool_grid)   # reopen/mirror frees the opened-pool tiles
	_pool_gen += 1
	var gen := _pool_gen
	var build_alive := func() -> bool:
		return is_inside_tree() and gen == _pool_gen
	for c in _pool_grid.get_children():
		_pool_grid.remove_child(c)
		c.queue_free()
	_pool_rows.clear()
	var ids: Array = _sorted_avail_ids()
	var slots: Array[Control] = []
	var sleeves: Array[Control] = []
	# The opened pool gets its complete grid before any texture await. These are
	# exact thumbnail footprints, so a centered/wrapped line cannot grow sideways
	# as cards finish loading.
	for raw_id in ids:
		var id := String(raw_id)
		var data: Dictionary = _pool_catalog[id]
		var loading := _make_loading_card_slot(THUMB_SIZE,
			GameTheme.rarity_color(String(data.get("rarity", "common"))),
			_pool_grid)
		var slot: Control = loading["slot"]
		_pool_grid.add_child(slot)
		slots.append(slot)
		sleeves.append(loading["sleeve"])

	var faces: Array[Control] = []
	var buttons: Array[Button] = []
	for idx in ids.size():
		var id := String(ids[idx])
		if not build_alive.call():
			return
		var data: Dictionary = _pool_catalog[id]
		if not CardTextureCache.has(data) \
				and not CardTextureCache.has_gallery(data):
			await CardArtAliases.prewarm_card_art(data)
			if not build_alive.call():
				CardArtAliases.release_card_art(data)
				return
			if not CardTextureCache.has(data):
				await CardTextureCache.bake_gallery(data, build_alive)
			CardArtAliases.release_card_art(data)
		if not build_alive.call():
			return
		var face: Control = _build_pool_thumb(id, data)
		var refs: Dictionary = _pool_rows[id]
		var button := refs["button"] as Button
		button.disabled = true
		button.set_meta("card_loading", true)
		slots[idx].add_child(face)
		_stage_complete_hand_member(face)
		faces.append(face)
		buttons.append(button)
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		if not build_alive.call():
			return

	# All opened cards turn together only after every ornate face is complete.
	await _reveal_complete_hand(faces, sleeves)
	if not build_alive.call():
		return
	for button in buttons:
		if button != null and is_instance_valid(button):
			button.set_meta("card_loading", false)
	_pool_ui_ready = true
	_refresh_pool_counts()
	_update_ready()
	_update_status()


func sealed_cards_ready() -> bool:
	return _pool_ui_ready

# _build_pool_thumb is inherited from NetDeckBuilder (identical across the
# pool-based modes); _on_add below overrides the base no-op.


# ─────────────────────────────────────────────────────────────────────────
#  DECK EDITING
# ─────────────────────────────────────────────────────────────────────────

func _on_add(id: String) -> void:
	if not _pool_ui_ready or _local_finished or _deck.size() >= _target:
		return
	if int(_counts.get(id, 0)) >= int(_avail.get(id, 0)):
		return   # can't run more copies than you opened
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


func _on_fill() -> void:
	if not _pool_ui_ready or _local_finished:
		return
	# Greedy fill from the opened pool, cheapest first, respecting opened copies.
	for id in _sorted_avail_ids():
		while _deck.size() < _target and int(_counts.get(id, 0)) < int(_avail.get(id, 0)):
			_deck.append(id)
			_counts[id] = int(_counts.get(id, 0)) + 1
		if _deck.size() >= _target:
			break
	_refresh_all()


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
		var have := int(_avail.get(id, 0))
		var used := int(_counts.get(id, 0))
		var refs: Dictionary = _pool_rows[id]
		var badge := refs["badge"] as Label
		badge.text = "%d/%d" % [used, have]
		# Only surface the tally when it says something: you've spent a copy, or
		# you opened more than one. A stark "0/1" chip on all 30 untouched cards
		# read as debug overlay noise.
		badge.visible = used > 0 or have > 1
		# Dim only cards you've used all opened copies of; a merely-full deck
		# disables the click but keeps the art bright.
		var copies_maxed := used >= have
		(refs["button"] as Button).disabled = not _pool_ui_ready \
			or _local_finished or full or copies_maxed
		(refs["card"] as Control).modulate = \
			Color(0.45, 0.45, 0.45, 0.8) if copies_maxed else Color.WHITE


func _refresh_deck_panel(changed_id: String = "", change: int = 0) -> void:
	_clear_hover_preview_under(_deck_box)   # a previewed deck tile may be freed below
	for c in _deck_box.get_children():
		_deck_box.remove_child(c)
		c.queue_free()
	# (The "Click cards you opened to enlist them" hint lived here. It was an
	# EXPAND_FILL label inside an HFlowContainer, so once the ghost slots below
	# existed it did not claim a clean row — it shouldered the first two slots
	# off to the right and broke the grid. The instruction is already on screen
	# one line above, in the header: "Build 20 from the cards you opened." The
	# twenty vacant slots say the rest without a sentence.)
	for id in _sorted_avail_ids():
		var n := int(_counts.get(id, 0))
		if n <= 0:
			continue
		# One visible tile per physical card copy. The previous grouped tile used
		# one footprint for two copies while consuming two ghosts, so the whole
		# HFlow contracted and re-centred on a duplicate pick.
		for copy_idx in n:
			var d: Dictionary = _pool_catalog[id] if _pool_catalog.has(id) \
				else SkirmishState.skirmish_card_data(id)
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
	# ── GHOST SLOTS (2026-07-30) ─────────────────────────────────────────
	# At 0/20 this panel was ~75% empty: a heading, one line of grey hint, a
	# large void, and a Command Curve with an axis and no bars. It read as a
	# screen that had failed to load rather than as a deck you haven't built.
	#
	# An empty state should show the SHAPE OF THE TASK. Twenty vacant slots say
	# "twenty" spatially and instantly — no counting, no reading — and they fill
	# in as you draft, so the panel becomes a progress bar made of the thing it
	# is measuring. It also gives the curve below something to sit under instead
	# of floating in the middle of nowhere.
	#
	# The empty-writ idiom already exists in this game (the Collection's
	# ghost-of-writ for uncollected cards), so this reads as house language
	# rather than a new device.
	var missing: int = maxi(_target - _deck.size(), 0)
	for _i in missing:
		_deck_box.add_child(_make_ghost_slot())


## A vacant warband slot: the silhouette of a card that isn't there yet. Sized
## from the same THUMB_SCALE the real tiles use, so a filled row and an empty
## row line up exactly.
func _make_ghost_slot() -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(225.0, 300.0) * THUMB_SCALE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.045, 0.035, 0.55)
	sb.border_color = Color(0.52, 0.42, 0.22, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", sb)
	return slot


func _update_ready() -> void:
	_refresh_curve(_deck)
	if _deck_count_lbl != null:
		_deck_count_lbl.text = "DECK  %d / %d" % [_deck.size(), _target]
		_deck_count_lbl.add_theme_color_override("font_color",
			GREEN if _deck.size() == _target else IVORY)
	if _ready_btn != null:
		_ready_btn.disabled = not _pool_ui_ready \
			or _local_finished or _deck.size() != _target


func _update_status() -> void:
	if _status == null:
		return
	var mode_str := "Mirrored" if _mirror else "Random"
	var you := "READY" if _local_finished else ("building (%d/%d)" % [_deck.size(), _target])
	var opp := "READY" if _remote_finished else "building…"
	_status.text = "[%s]  You: %s   ·   Opponent: %s" % [mode_str, you, opp]
	_status.add_theme_color_override("font_color",
		GREEN if (_local_finished and _remote_finished) else ASH)
	var config_locked := _config_locked()
	if _mirror_btn != null:
		_mirror_btn.disabled = config_locked or not _pool_ui_ready
	if _reroll_btn != null:
		_reroll_btn.disabled = config_locked or not _pool_ui_ready


# ─────────────────────────────────────────────────────────────────────────
#  HOST POOL CONTROLS  (mirrors NetQuick cfg broadcast)
# ─────────────────────────────────────────────────────────────────────────

func _config_locked() -> bool:
	return _local_finished or _remote_finished


func _on_toggle_mirror() -> void:
	if not NetMatch.is_host or not _pool_ui_ready or _config_locked():
		return
	_mirror = not _mirror
	if _mirror_btn != null:
		_mirror_btn.text = "MIRROR" if _mirror else "SEALED"
	_regenerate_pool()
	_rebuild_pool_ui()
	_refresh_all()
	_broadcast_cfg()


func _on_reroll() -> void:
	if not NetMatch.is_host or not _pool_ui_ready or _config_locked():
		return
	_sub_seed = NetMatch.fresh_seed()
	_regenerate_pool()
	_rebuild_pool_ui()
	_refresh_all()
	_broadcast_cfg()


func _broadcast_cfg() -> void:
	NetMatch.set_loadout_source_config(_mirror, _sub_seed)
	NetMatch.send_draft_event({"t": "cfg", "mirror": _mirror, "seed": _sub_seed})


# ─────────────────────────────────────────────────────────────────────────
#  READY / HANDOFF
# ─────────────────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	if not _pool_ui_ready or _local_finished or _deck.size() != _target:
		return
	_local_finished = true
	for id in _deck:
		SkirmishState.add_card_to(SkirmishState.local_index, id)
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
		"cfg":
			# Client adopts the host's pool config and re-opens to match.
			if not NetMatch.is_host and not _config_locked():
				_mirror = bool(event.get("mirror", false))
				_sub_seed = int(event.get("seed", 0))
				if _mirror_btn != null:
					_mirror_btn.text = "MIRRORED" if _mirror else "RANDOM"
				_regenerate_pool()
				if _mode_ui_ready:
					_rebuild_pool_ui()
					_refresh_all()
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
