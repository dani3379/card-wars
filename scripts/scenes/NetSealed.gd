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
# Bumped each pool rebuild; the async bake loop checks it after every await so a
# re-sort / reopen that fires mid-build abandons the stale stream cleanly.
var _pool_gen: int = 0


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")
	AudioBank.play_music_random(["map_c", "map_d", "rest_c"])  # muster pool

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

	_build_scaffold()

	if NetMatch.is_host:
		_sub_seed = 0
		_broadcast_cfg()
	_regenerate_pool()
	_rebuild_pool_ui()
	_refresh_all()
	_install_net_chrome()


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

	var opened: Array[String] = SkirmishState.deal_unique_cards(
		_legal, mini(SEALED_POOL_SIZE, _legal.size()), _rng)
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


func _sorted_avail_ids() -> Array:
	var ids := _avail.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := int(CardDB.get_card_data(a).get("cost", 0))
		var cb := int(CardDB.get_card_data(b).get("cost", 0))
		if ca != cb:
			return ca < cb
		return String(CardDB.get_card_data(a).get("name", a)) < String(CardDB.get_card_data(b).get("name", b)))
	return ids


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

	_root.add_child(GameTheme.make_screen_title("SEALED MUSTER", GILT_BRIGHT))

	_header = GameTheme.make_label("Build 20 from the cards you opened.", 17, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)

	# ── Opened-pool column ──
	var pool_col := VBoxContainer.new()
	pool_col.add_theme_constant_override("separation", 6)
	pool_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_col.size_flags_stretch_ratio = 1.4
	cols.add_child(pool_col)

	pool_col.add_child(GameTheme.make_label("YOU OPENED", 15, GILT_BRIGHT))

	var pool_scroll := ScrollContainer.new()
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pool_col.add_child(pool_scroll)

	_pool_grid = HFlowContainer.new()
	_pool_grid.add_theme_constant_override("h_separation", 10)
	_pool_grid.add_theme_constant_override("v_separation", 10)
	_pool_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_scroll.add_child(_pool_grid)

	# ── Deck column ──
	var deck_col := VBoxContainer.new()
	deck_col.add_theme_constant_override("separation", 6)
	deck_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(deck_col)

	_deck_count_lbl = GameTheme.make_label("WARBAND  0 / %d" % _target, 15, IVORY)
	deck_col.add_child(_deck_count_lbl)

	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_col.add_child(deck_scroll)

	_deck_box = HFlowContainer.new()
	_deck_box.add_theme_constant_override("h_separation", 8)
	_deck_box.add_theme_constant_override("v_separation", 8)
	_deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.add_child(_deck_box)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	deck_col.add_child(tools)
	var fill_btn := GameTheme.make_themed_button("AUTO-FILL",
		Color(0.20, 0.24, 0.34), Vector2(130, 32), 13)
	fill_btn.pressed.connect(_on_fill)
	tools.add_child(fill_btn)
	var clear_btn := GameTheme.make_themed_button("CLEAR",
		Color(0.30, 0.18, 0.16), Vector2(100, 32), 13)
	clear_btn.pressed.connect(_on_clear)
	tools.add_child(clear_btn)

	_root.add_child(GameTheme.make_separator(
		Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.30), 500.0))

	# Bottom: host pool controls + READY + status.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	_root.add_child(bottom)

	if NetMatch.is_host:
		_mirror_btn = GameTheme.make_themed_button("Sealed",
			Color(0.15, 0.25, 0.40), Vector2(130, 38), 14)
		_mirror_btn.pressed.connect(_on_toggle_mirror)
		bottom.add_child(_mirror_btn)
		var reroll := GameTheme.make_themed_button("REOPEN",
			Color(0.28, 0.20, 0.10), Vector2(120, 38), 14)
		reroll.pressed.connect(_on_reroll)
		bottom.add_child(reroll)

	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.18, 0.36, 0.18), Vector2(170, 44), 17)
	_ready_btn.pressed.connect(_on_ready_pressed)
	bottom.add_child(_ready_btn)

	_status = GameTheme.make_label("", 16, ASH)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)


func _rebuild_pool_ui() -> void:
	if _pool_grid == null:
		return
	_clear_hover_preview_under(_pool_grid)   # reopen/mirror frees the opened-pool tiles
	# Bake-then-build (Collection pattern): warm each card's texture before its
	# thumbnail so the Card2D builds the cheap baked overlay, not the heavy live
	# layout. Cards stream in; a warm cache returns instantly. The gen guard lets a
	# later rebuild supersede this one without two streams fighting over the grid.
	_pool_gen += 1
	var gen := _pool_gen
	for c in _pool_grid.get_children():
		c.queue_free()
	_pool_rows.clear()
	for id in _sorted_avail_ids():
		if gen != _pool_gen or not is_instance_valid(_pool_grid):
			return
		await CardTextureCache.bake(CardDB.get_card_data(id))
		if gen != _pool_gen or not is_instance_valid(_pool_grid):
			return
		_pool_grid.add_child(_build_pool_thumb(id))


# _build_pool_thumb is inherited from NetDeckBuilder (identical across the
# pool-based modes); _on_add below overrides the base no-op.


# ─────────────────────────────────────────────────────────────────────────
#  DECK EDITING
# ─────────────────────────────────────────────────────────────────────────

func _on_add(id: String) -> void:
	if _local_finished or _deck.size() >= _target:
		return
	if int(_counts.get(id, 0)) >= int(_avail.get(id, 0)):
		return   # can't run more copies than you opened
	_deck.append(id)
	_counts[id] = int(_counts.get(id, 0)) + 1
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_refresh_all()


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
	_refresh_all()


func _on_clear() -> void:
	if _local_finished:
		return
	_deck.clear()
	_counts.clear()
	_refresh_all()


func _on_fill() -> void:
	if _local_finished:
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

func _refresh_all() -> void:
	_refresh_pool_counts()
	_refresh_deck_panel()
	_update_ready()
	_update_status()


func _refresh_pool_counts() -> void:
	var full := _deck.size() >= _target
	for id in _pool_rows:
		var have := int(_avail.get(id, 0))
		var used := int(_counts.get(id, 0))
		var refs: Dictionary = _pool_rows[id]
		var badge := refs["badge"] as Label
		badge.text = "%d/%d" % [used, have]
		badge.visible = true
		# Dim only cards you've used all opened copies of; a merely-full deck
		# disables the click but keeps the art bright.
		var copies_maxed := used >= have
		(refs["button"] as Button).disabled = _local_finished or full or copies_maxed
		(refs["card"] as Control).modulate = \
			Color(0.45, 0.45, 0.45, 0.8) if copies_maxed else Color.WHITE


func _refresh_deck_panel() -> void:
	_clear_hover_preview_under(_deck_box)   # a previewed deck tile may be freed below
	for c in _deck_box.get_children():
		c.queue_free()
	for id in _sorted_avail_ids():
		var n := int(_counts.get(id, 0))
		if n <= 0:
			continue
		var d := CardDB.get_card_data(id)
		var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
		var badge := thumb["badge"] as Label
		badge.text = "×%d" % n
		badge.visible = n > 1
		var btn := thumb["button"] as Button
		btn.tooltip_text = "%s — click to remove" % String(d.get("name", id))
		_attach_hover_preview(btn, id)
		if _local_finished:
			btn.disabled = true
		else:
			btn.pressed.connect(_on_remove.bind(id))
		_deck_box.add_child(thumb["root"])


func _update_ready() -> void:
	if _deck_count_lbl != null:
		_deck_count_lbl.text = "WARBAND  %d / %d" % [_deck.size(), _target]
		_deck_count_lbl.add_theme_color_override("font_color",
			GREEN if _deck.size() == _target else IVORY)
	if _ready_btn != null:
		_ready_btn.disabled = _local_finished or _deck.size() != _target


func _update_status() -> void:
	if _status == null:
		return
	var mode_str := "Mirror" if _mirror else "Sealed"
	var you := "READY" if _local_finished else ("building (%d/%d)" % [_deck.size(), _target])
	var opp := "READY" if _remote_finished else "opening…"
	_status.text = "[%s]  You: %s   ·   Opponent: %s" % [mode_str, you, opp]
	_status.add_theme_color_override("font_color",
		GREEN if (_local_finished and _remote_finished) else ASH)


# ─────────────────────────────────────────────────────────────────────────
#  HOST POOL CONTROLS  (mirrors NetQuick cfg broadcast)
# ─────────────────────────────────────────────────────────────────────────

func _on_toggle_mirror() -> void:
	if not NetMatch.is_host:
		return
	_mirror = not _mirror
	if _mirror_btn != null:
		_mirror_btn.text = "Mirror" if _mirror else "Sealed"
	_regenerate_pool()
	_rebuild_pool_ui()
	_refresh_all()
	_broadcast_cfg()


func _on_reroll() -> void:
	if not NetMatch.is_host:
		return
	_sub_seed = NetMatch.fresh_seed()
	_regenerate_pool()
	_rebuild_pool_ui()
	_refresh_all()
	_broadcast_cfg()


func _broadcast_cfg() -> void:
	NetMatch.send_draft_event({"t": "cfg", "mirror": _mirror, "seed": _sub_seed})


# ─────────────────────────────────────────────────────────────────────────
#  READY / HANDOFF
# ─────────────────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	if _local_finished or _deck.size() != _target:
		return
	_local_finished = true
	for id in _deck:
		SkirmishState.add_card_to(SkirmishState.local_index, id)
	NetMatch.send_draft_event({"t": "finished",
		"cards": SkirmishState.local_slot().deck.duplicate()})
	# Bake the sealed warband's textures behind the waiting screen (idle time).
	ScenePreload.warm_card_ids(_deck)
	if _ready_btn != null:
		_ready_btn.text = "READY ✓"
	_refresh_all()
	_show_waiting()
	_maybe_begin_combat()


func _on_draft_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		"cfg":
			# Client adopts the host's pool config and re-opens to match.
			if not NetMatch.is_host:
				_mirror = bool(event.get("mirror", false))
				_sub_seed = int(event.get("seed", 0))
				if _mirror_btn != null:
					_mirror_btn.text = "Mirror" if _mirror else "Sealed"
				_regenerate_pool()
				_rebuild_pool_ui()
				_refresh_all()
		"finished":
			_remote_finished = true
			_store_opponent_deck(event.get("cards", []))
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
	if not (_local_finished and _remote_finished):
		return
	_show_marching()
	if NetMatch.is_host:
		NetMatch.launch_combat()


# ─────────────────────────────────────────────────────────────────────────
#  STATUS SCREENS
# ─────────────────────────────────────────────────────────────────────────

func _show_waiting() -> void:
	if _header != null and not _remote_finished:
		_header.text = "Warband sealed — waiting for your opponent…"
		_header.add_theme_color_override("font_color", ASH)


func _show_marching() -> void:
	if _header != null:
		_header.text = "Both warbands ready — marching to battle…"
		_header.add_theme_color_override("font_color", GREEN)


func _on_peer_lost(_id: int = 0) -> void:
	if _root == null:
		return
	if _header != null:
		_header.text = "Opponent disconnected."
		_header.add_theme_color_override("font_color", RED_WARN)
	if _status != null:
		_status.text = ""
	if _ready_btn != null:
		_ready_btn.disabled = true
	var back := GameTheme.make_themed_button("BACK TO MENU",
		Color(0.26, 0.16, 0.14), Vector2(220, 44), 16)
	back.pressed.connect(func():
		NetMatch.leave()
		get_tree().change_scene_to_file(MENU_SCENE))
	_root.add_child(back)
