extends Control
## NetConstructed.gd — Constructed mode: each player builds any DECK_TARGET-card
## deck from the full skirmish-legal pool, then both fight. No seed, no triplets —
## pure deckbuilding. Each side builds INDEPENDENTLY and ships its finished deck on
## READY (the same "finished" handoff the draft uses); the host launches combat
## once both decks are in.
##
## Deck handoff (mirrors NetDraft/NetQuick):
##   local deck → "finished" event → peer stores it → _maybe_begin_combat.
##   HOST calls NetMatch.launch_combat(); CLIENT waits.

const MENU_SCENE := "res://scenes/main_menu.tscn"

# Max copies of any single card id in the built deck.
const MAX_COPIES: int = 2
# Deck-builder card-thumbnail scale (225×300 → ~104×138).
const THUMB_SCALE: float = 0.46

const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
const GREEN := Color(0.55, 0.85, 0.45, 1.0)
const RED_WARN := Color(0.90, 0.45, 0.35, 1.0)
const SPELL_BLUE := Color(0.70, 0.88, 1.0, 1.0)

var _target: int = 20            # SkirmishState.DECK_TARGET
var _pool: Array[String] = []    # legal ids, sorted by cost then name
var _deck: Array[String] = []    # working deck (ids), in add order
var _counts: Dictionary = {}     # id -> copies currently in deck
var _rng := RandomNumberGenerator.new()

# Handoff state (mirrors NetDraft).
var _local_finished: bool = false
var _remote_finished: bool = false

# UI refs.
var _root: VBoxContainer
var _header: Label
var _status: Label
var _deck_box: HFlowContainer
var _pool_box: HFlowContainer
var _deck_count_lbl: Label
var _ready_btn: Button
var _pool_rows: Dictionary = {}   # id -> {"button": Button, "badge": Label, "card": Card2D}
var _name_field: LineEdit         # save-as name
var _saved_option: OptionButton   # saved-deck picker


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")

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

	_build_scaffold()
	_refresh_all()


# ─────────────────────────────────────────────────────────────────────────
#  POOL
# ─────────────────────────────────────────────────────────────────────────

func _build_pool() -> void:
	for id in SkirmishState.skirmish_legal_pool():
		_pool.append(String(id))
	# Sort by cost then name so the pool list reads like a curve, not an id dump.
	_pool.sort_custom(func(a: String, b: String) -> bool:
		var da := CardDB.get_card_data(a)
		var db := CardDB.get_card_data(b)
		var ca := int(da.get("cost", 0))
		var cb := int(db.get("cost", 0))
		if ca != cb:
			return ca < cb
		return String(da.get("name", a)) < String(db.get("name", b)))


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

	_root.add_child(GameTheme.make_screen_title("BUILD YOUR WARBAND", GILT_BRIGHT))

	_header = GameTheme.make_label("Pick any 20 cards from the muster roll.", 17, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	# Two columns: pool (left) and current deck (right).
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)

	# ── Pool column ──
	var pool_col := VBoxContainer.new()
	pool_col.add_theme_constant_override("separation", 6)
	pool_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_col.size_flags_stretch_ratio = 1.4
	cols.add_child(pool_col)

	var pool_hdr := GameTheme.make_label("MUSTER ROLL", 15, GILT_BRIGHT)
	pool_col.add_child(pool_hdr)

	var pool_scroll := ScrollContainer.new()
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pool_col.add_child(pool_scroll)

	_pool_box = HFlowContainer.new()
	_pool_box.add_theme_constant_override("h_separation", 10)
	_pool_box.add_theme_constant_override("v_separation", 10)
	_pool_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_scroll.add_child(_pool_box)
	# Streamed bake-then-build (see _populate_pool) so the ~N Card2D thumbnails come
	# in cheap (baked) and top-down instead of hitching the frame as live layouts.
	_populate_pool()

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

	# Deck-tools row.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	deck_col.add_child(tools)
	var fill_btn := GameTheme.make_themed_button("FILL RANDOM",
		Color(0.20, 0.24, 0.34), Vector2(140, 32), 13)
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
	deck_col.add_child(saved)
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Deck name"
	_name_field.custom_minimum_size = Vector2(120, 30)
	if GameTheme.font_body:
		_name_field.add_theme_font_override("font", GameTheme.font_body)
	saved.add_child(_name_field)
	var save_btn := GameTheme.make_themed_button("SAVE",
		Color(0.18, 0.30, 0.22), Vector2(72, 32), 14)
	save_btn.pressed.connect(_on_save_deck)
	saved.add_child(save_btn)
	_saved_option = OptionButton.new()
	_saved_option.custom_minimum_size = Vector2(140, 30)
	saved.add_child(_saved_option)
	var load_btn := GameTheme.make_themed_button("LOAD",
		Color(0.20, 0.24, 0.34), Vector2(72, 32), 14)
	load_btn.pressed.connect(_on_load_deck)
	saved.add_child(load_btn)
	var del_btn := GameTheme.make_themed_button("DEL",
		Color(0.30, 0.18, 0.16), Vector2(60, 32), 14)
	del_btn.pressed.connect(_on_delete_deck)
	saved.add_child(del_btn)
	_refresh_saved_options()

	_root.add_child(GameTheme.make_separator(
		Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.30), 500.0))

	# Bottom: READY + status.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 18)
	_root.add_child(bottom)

	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.18, 0.36, 0.18), Vector2(180, 44), 17)
	_ready_btn.pressed.connect(_on_ready_pressed)
	bottom.add_child(_ready_btn)

	_status = GameTheme.make_label("", 16, ASH)
	_root.add_child(_status)


func _populate_pool() -> void:
	# Bake each card's texture BEFORE building its thumbnail (the Collection
	# pattern): the thumb's Card2D then hits a warm cache and builds the cheap
	# ~5-node baked overlay instead of the heavy ~20-node live layout. Cards stream
	# in top-down; a warm cache (revisit / after combat) returns instantly. Baking
	# sequentially also stops the shared bake viewport being stomped by the dozens of
	# concurrent fire-and-forget bakes the old burst-build kicked off.
	for id in _pool:
		if not is_instance_valid(_pool_box) or not is_inside_tree():
			return
		await CardTextureCache.bake(CardDB.get_card_data(id))
		if not is_instance_valid(_pool_box) or not is_inside_tree():
			return
		_pool_box.add_child(_build_pool_thumb(id))
	_refresh_pool_counts()


func _build_pool_thumb(id: String) -> Control:
	var d := CardDB.get_card_data(id)
	var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
	var btn := thumb["button"] as Button
	btn.pressed.connect(_on_add.bind(id))
	btn.tooltip_text = String(d.get("name", id))
	_pool_rows[id] = {"button": btn, "badge": thumb["badge"], "card": thumb["card"]}
	return thumb["root"]


# ─────────────────────────────────────────────────────────────────────────
#  DECK EDITING
# ─────────────────────────────────────────────────────────────────────────

func _on_add(id: String) -> void:
	if _local_finished:
		return
	if _deck.size() >= _target:
		return
	if int(_counts.get(id, 0)) >= MAX_COPIES:
		return
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


func _on_fill_random() -> void:
	if _local_finished or _pool.is_empty():
		return
	var guard := 0
	while _deck.size() < _target and guard < 4000:
		guard += 1
		var id: String = _pool[_rng.randi() % _pool.size()]
		if int(_counts.get(id, 0)) < MAX_COPIES:
			_deck.append(id)
			_counts[id] = int(_counts.get(id, 0)) + 1
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
		var nm := String(saved[i].get("name", "Warband"))
		var n := (saved[i].get("cards", []) as Array).size()
		_saved_option.add_item("%s  (%d)" % [nm, n])


func _on_save_deck() -> void:
	if _local_finished:
		return
	if _deck.size() != _target:
		_flash_status("Build a full %d-card warband before saving." % _target, RED_WARN)
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
func _flash_status(msg: String, col: Color) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", col)


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
		var n := int(_counts.get(id, 0))
		var refs: Dictionary = _pool_rows[id]
		var badge := refs["badge"] as Label
		badge.text = "×%d" % n
		badge.visible = n > 0
		# Dim only cards at their copy limit; a merely-full deck disables the click
		# but keeps the art bright (greying the whole pool reads as broken).
		var copies_maxed := n >= MAX_COPIES
		(refs["button"] as Button).disabled = _local_finished or full or copies_maxed
		(refs["card"] as Control).modulate = \
			Color(0.45, 0.45, 0.45, 0.8) if copies_maxed else Color.WHITE


func _refresh_deck_panel() -> void:
	for c in _deck_box.get_children():
		c.queue_free()
	# Group the deck by id and list it sorted by cost then name.
	var ids := _counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := int(CardDB.get_card_data(a).get("cost", 0))
		var cb := int(CardDB.get_card_data(b).get("cost", 0))
		if ca != cb:
			return ca < cb
		return String(CardDB.get_card_data(a).get("name", a)) < String(CardDB.get_card_data(b).get("name", b)))
	for id in ids:
		var n := int(_counts[id])
		if n <= 0:
			continue
		var d := CardDB.get_card_data(id)
		var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
		var badge := thumb["badge"] as Label
		badge.text = "×%d" % n
		badge.visible = n > 1
		var btn := thumb["button"] as Button
		btn.tooltip_text = "%s — click to remove" % String(d.get("name", id))
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
		"cards": SkirmishState.local_slot().deck.duplicate()})
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
