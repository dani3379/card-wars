extends "res://scripts/scenes/NetDeckBuilder.gd"
## NetQuick.gd — Quick Battle mode: both players get a randomly generated
## 20-card deck, preview it, and fight immediately. No pick screen, no wait.
##
## Mirror mode (default): both machines seed from SkirmishState.rng_seed with
## NO per-side salt, so both generate the identical card list → symmetric fight.
## Random mode: seed is salted by SkirmishState.local_index, so decks differ.
## The HOST picks the mode and broadcasts it via a "cfg" draft_event before
## either player presses READY. A REROLL button (HOST-only) picks a fresh
## sub-seed and rebroadcasts. The client regenerates on receipt.
##
## Deck handoff (mirrors NetDraft):
##   local deck → "finished" event → peer stores it → _maybe_begin_combat.
##   HOST calls NetMatch.launch_combat(); CLIENT waits.

# Scene constants + palette (MENU_SCENE, MAX_COPIES, THUMB_SCALE, and the
# colors) are inherited from NetDeckBuilder.

# ── Deck generation state ── (_rng, _target inherited from NetDeckBuilder)
var _pool: Array[String] = []
var _mirror: bool = false
var _sub_seed: int = 0      # host-chosen; 0 means unset (use base seed)
var _local_deck: Array[String] = []

# ── Handoff state (mirrors NetDraft) ── (_local/_remote_finished inherited)
var _local_ready: bool = false
var _remote_ready: bool = false

# ── UI refs ── (_root, _header inherited)
var _status: Label
var _deck_box: HFlowContainer
# Bumped each preview rebuild; the async bake loop checks it after every await so a
# Reroll / Mirror / cfg change that fires mid-build abandons the stale stream.
var _deck_gen: int = 0
var _reroll_btn: Button
var _ready_btn: Button
var _mirror_btn: Button
var _mode_ui_ready := false
var _deck_ui_ready := false


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")
	AudioBank.play_music_random(["net_lobby", "net_lobby_b", "rest_c"])  # muster pool

	if not NetMatch.is_connected_to_peer():
		get_tree().change_scene_to_file(MENU_SCENE)
		return

	SkirmishState.begin_session()
	_target = SkirmishState.DECK_TARGET

	for id in SkirmishState.skirmish_legal_pool():
		_pool.append(String(id))

	NetMatch.draft_event_received.connect(_on_draft_event)
	NetMatch.peer_left.connect(_on_peer_lost)
	NetMatch.host_closed.connect(_on_peer_lost)

	if NetMatch.is_host:
		# Host decides the initial cfg and broadcasts it so the client's first
		# generation matches. sub_seed 0 → use base rng_seed unchanged.
		_sub_seed = 0
		_broadcast_cfg()
	# Host generates immediately (client regenerates when cfg arrives).
	_regenerate_deck()
	# Every net game opens with the shared arsenal stage (the host sets how many
	# relic and potion picks it offers; 0 + 0 raises no stage at all);
	# present it before constructing the obscured deck preview. The mode UI starts
	# one frame later and normally finishes during the five Arsenal decisions.
	_begin_arsenal()
	_prepare_mode_ui()


func _prepare_mode_ui() -> void:
	# Waiting through a completed draw keeps hidden deck work out of the entry
	# frame. The extra process boundary also prevents signal-resume order from
	## charging this work to another frame_post_draw waiter (including benchmarks).
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await get_tree().process_frame
	if not is_inside_tree() or not NetMatch.is_connected_to_peer():
		return
	_build_scaffold()
	_mode_ui_ready = true
	_refresh_deck_ui()
	_update_status()
	_install_net_chrome()
	_flatten_net_chart_styles(self)


# ─────────────────────────────────────────────────────────────────────────
#  DECK GENERATION
# ─────────────────────────────────────────────────────────────────────────

func _effective_seed() -> int:
	var base: int = SkirmishState.rng_seed
	if _sub_seed != 0:
		base = base ^ (_sub_seed * 0x9E3779B9)
	if not _mirror:
		# Per-side salt so decks differ.
		base = base ^ ((SkirmishState.local_index + 1) * 0x6C62272E)
	return base


func _regenerate_deck() -> void:
	_rng.seed = _effective_seed()
	_local_deck = SkirmishState.deal_weighted_cards(_pool, _target, _rng,
		SkirmishState.SKIRMISH_DRAFT_WEIGHTS)
	if _local_deck.size() >= _target:
		return

	var counts: Dictionary = {}
	for existing_id in _local_deck:
		counts[existing_id] = int(counts.get(existing_id, 0)) + 1
	var guard := 0
	while _local_deck.size() < _target and guard < 4000:
		guard += 1
		if _pool.is_empty():
			break
		var pick_id: String = _pool[_rng.randi() % _pool.size()]
		var cnt: int = int(counts.get(pick_id, 0))
		if cnt < MAX_COPIES:
			_local_deck.append(pick_id)
			counts[pick_id] = cnt + 1


# ─────────────────────────────────────────────────────────────────────────
#  UI BUILD
# ─────────────────────────────────────────────────────────────────────────

func _build_scaffold() -> void:
	_root = VBoxContainer.new()
	_root.name = "Quick"
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 14)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_top = 32
	_root.offset_bottom = -24
	add_child(_root)

	_root.add_child(GameTheme.make_screen_title("QUICK BATTLE", GILT_BRIGHT))

	_header = GameTheme.make_label("Your deck — %d cards, dealt at random." % _target, 18, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	# Deck preview — the dealt warband staged as one centered muster sheet (a
	# tacked parchment plate) instead of a thumbnail sprawl pinned top-left.
	# 20 cards at thumb scale are always ≤2 rows, so the sheet needs no scroll.
	var sheet_center := CenterContainer.new()
	sheet_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(sheet_center)

	var sheet := PanelContainer.new()
	var sheet_style := GameTheme.make_panel_style(GameTheme.PARCHMENT,
		Color(0.60, 0.51, 0.34, 0.80), 1, 6)
	sheet_style.content_margin_left = 22
	sheet_style.content_margin_right = 22
	sheet_style.content_margin_top = 18
	sheet_style.content_margin_bottom = 18
	sheet.add_theme_stylebox_override("panel", sheet_style)
	# Narrower than the canvas so ~20 thumbs wrap into two balanced rows rather
	# than one long row plus a stub.
	sheet.custom_minimum_size = Vector2(1064, 0)
	sheet_center.add_child(sheet)

	_deck_box = HFlowContainer.new()
	# BOTH alignments: `alignment` centers the full lines, `last_wrap_alignment`
	# the final partial one — without the second, the last row left-aligns and
	# the sheet reads lopsided.
	_deck_box.alignment = FlowContainer.ALIGNMENT_CENTER
	_deck_box.last_wrap_alignment = FlowContainer.LAST_WRAP_ALIGNMENT_CENTER
	_deck_box.add_theme_constant_override("h_separation", 8)
	_deck_box.add_theme_constant_override("v_separation", 8)
	_deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_child(_deck_box)

	_root.add_child(GameTheme.make_separator(Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.35), 400.0))

	# Bottom controls row
	var ctrl_row := HBoxContainer.new()
	ctrl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_row.add_theme_constant_override("separation", 20)
	_root.add_child(ctrl_row)

	# All three buttons speak in the sepia world and in one voice: the two
	# secondary actions sit in muted ash-brown, the commit action in ember, and
	# every label is caps. This row used to mix a blue tile, a brown tile, and a
	# green tile with three different casings.
	if NetMatch.is_host:
		_mirror_btn = GameTheme.make_themed_button("MIRRORED" if _mirror else "RANDOM",
			Color(0.20, 0.17, 0.13), Vector2(140, 38), 15)
		_mirror_btn.tooltip_text = "Host only: Mirrored deals both sides the same 20 cards; Random deals each side its own."
		_mirror_btn.pressed.connect(_on_toggle_mirror)
		ctrl_row.add_child(_mirror_btn)

		_reroll_btn = GameTheme.make_themed_button("REROLL",
			Color(0.28, 0.20, 0.10), Vector2(130, 38), 15)
		_reroll_btn.tooltip_text = "Host only: deal both decks again."
		_reroll_btn.pressed.connect(_on_reroll)
		ctrl_row.add_child(_reroll_btn)

	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.34, 0.22, 0.08), Vector2(160, 44), 17)
	_ready_btn.pressed.connect(_on_ready_pressed)
	ctrl_row.add_child(_ready_btn)

	_status = GameTheme.make_label("", 16, ASH)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)


func _refresh_deck_ui() -> void:
	if _deck_box == null:
		return
	_deck_ui_ready = false
	_deck_gen += 1
	var gen := _deck_gen
	_clear_hover_preview_under(_deck_box)   # a previewed tile is about to be freed
	for c in _deck_box.get_children():
		_deck_box.remove_child(c)
		c.queue_free()

	# Group the random warband by id and show each as real card art with a ×N
	# badge, sorted by cost then name. No click: the deck is fixed — you Reroll it,
	# you don't edit it — so the thumbnails are a read-only preview.
	var counts: Dictionary = {}
	var catalog: Dictionary = {}
	var order: Array[String] = []
	for id in _local_deck:
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
			catalog[id] = SkirmishState.skirmish_card_data(id)
		counts[id] = int(counts[id]) + 1
	order.sort_custom(func(a: String, b: String) -> bool:
		var ca := int((catalog[a] as Dictionary).get("cost", 0))
		var cb := int((catalog[b] as Dictionary).get("cost", 0))
		if ca != cb:
			return ca < cb
		return String((catalog[a] as Dictionary).get("name", a)) < \
			String((catalog[b] as Dictionary).get("name", b)))

	# Reserve the complete final grid before the first await. Rich faces are built
	# hidden over these backs, then the entire warband turns at once.
	var slots: Array[Control] = []
	var sleeves: Array[Control] = []
	for id in order:
		var data: Dictionary = catalog[id]
		var loading := _make_loading_card_slot(THUMB_SIZE,
			GameTheme.rarity_color(String(data.get("rarity", "common"))),
			_deck_box)
		var slot: Control = loading["slot"]
		_deck_box.add_child(slot)
		slots.append(slot)
		sleeves.append(loading["sleeve"])

	var build_alive := func() -> bool:
		return is_inside_tree() and gen == _deck_gen
	var faces: Array[Control] = []
	var buttons: Array[Button] = []
	for idx in order.size():
		var id: String = order[idx]
		if not build_alive.call():
			return
		var d: Dictionary = catalog[id]
		if not CardTextureCache.has(d) and not CardTextureCache.has_gallery(d):
			await CardArtAliases.prewarm_card_art(d)
			if not build_alive.call():
				CardArtAliases.release_card_art(d)
				return
			if not CardTextureCache.has(d):
				await CardTextureCache.bake_gallery(d, build_alive)
			CardArtAliases.release_card_art(d)
		if not build_alive.call():
			return
		var n := int(counts[id])
		var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
		var badge := thumb["badge"] as Label
		badge.text = "×%d" % n
		badge.visible = n > 1
		# No add/remove click in Quick — but hovering still pops the full card
		# beside the tile (the shared builder preview), so the sealed 20 can be
		# read properly before READY.
		var button := thumb["button"] as Button
		button.disabled = true
		button.set_meta("card_loading", true)
		_attach_hover_preview(button, id)
		var face := thumb["root"] as Control
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

	# One simultaneous flip after every full Card2D face is ready. This keeps the
	# centered flow immutable during cold loads and rerolls.
	await _reveal_complete_hand(faces, sleeves)
	if not build_alive.call():
		return
	for button in buttons:
		if button != null and is_instance_valid(button):
			button.set_meta("card_loading", false)
			button.disabled = false
	_deck_ui_ready = true
	_update_status()


func quick_cards_ready() -> bool:
	return _deck_ui_ready

func _update_status() -> void:
	if _status == null:
		return
	var mode_str: String = "Mirrored decks" if _mirror else "Random decks"
	var you_str: String = "READY" if _local_ready else "not ready"
	var opp_str: String = "READY" if _remote_ready else "not ready"
	_status.text = "%s   ·   You: %s   ·   Opponent: %s" % [mode_str, you_str, opp_str]

	if _local_ready and _remote_ready:
		_status.add_theme_color_override("font_color", GREEN)
	elif _local_ready:
		_status.add_theme_color_override("font_color", HOST_BLUE)
	else:
		_status.add_theme_color_override("font_color", ASH)
	var config_locked := _config_locked()
	if _mirror_btn != null:
		_mirror_btn.disabled = config_locked or not _deck_ui_ready
	if _reroll_btn != null:
		_reroll_btn.disabled = config_locked or not _deck_ui_ready
	if _ready_btn != null:
		_ready_btn.disabled = config_locked or not _deck_ui_ready


# ─────────────────────────────────────────────────────────────────────────
#  HOST CONTROLS
# ─────────────────────────────────────────────────────────────────────────

func _config_locked() -> bool:
	return _local_ready or _remote_ready or _local_finished or _remote_finished


func _on_toggle_mirror() -> void:
	if not NetMatch.is_host or not _deck_ui_ready or _config_locked():
		return
	_mirror = not _mirror
	if _mirror_btn != null:
		_mirror_btn.text = "MIRRORED" if _mirror else "RANDOM"
	_regenerate_deck()
	_refresh_deck_ui()
	_update_status()
	_broadcast_cfg()


func _on_reroll() -> void:
	if not NetMatch.is_host or not _deck_ui_ready or _config_locked():
		return
	_sub_seed = NetMatch.fresh_seed()
	_regenerate_deck()
	_refresh_deck_ui()
	_update_status()
	_broadcast_cfg()


func _broadcast_cfg() -> void:
	NetMatch.set_loadout_source_config(_mirror, _sub_seed)
	NetMatch.send_draft_event({
		"t": "cfg",
		"mirror": _mirror,
		"seed": _sub_seed,
	})


# ─────────────────────────────────────────────────────────────────────────
#  READY / HANDOFF FLOW  (mirrors NetDraft finish tail)
# ─────────────────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	if not _deck_ui_ready or _local_ready or _local_finished:
		return
	_local_ready = true
	if _ready_btn != null:
		_ready_btn.disabled = true
		_ready_btn.text = "READY ✓"
	# Broadcast ready state to peer.
	NetMatch.send_draft_event({"t": "ready"})
	_update_status()
	_maybe_fight()


func _maybe_fight() -> void:
	if not (_local_ready and _remote_ready):
		return
	_finish_and_handoff()


func _finish_and_handoff() -> void:
	if _local_finished:
		return   # guard: commit the deck exactly once
	_local_finished = true
	# Commit local deck to SkirmishState.
	for id in _local_deck:
		SkirmishState.add_card_to(SkirmishState.local_index, id)
	# Send full deck to peer (same "finished" contract as NetDraft).
	var my_deck: Array = SkirmishState.local_slot().deck.duplicate()
	NetMatch.send_draft_event({"t": "finished", "cards": my_deck,
		"relics": SkirmishState.local_slot().relics.duplicate(),
		"potions": SkirmishState.local_slot().potions.duplicate()})
	# Bake the sealed warband's textures behind the waiting screen (idle time).
	ScenePreload.warm_card_ids(my_deck, true)
	_show_marching()
	_maybe_begin_combat()


func _on_draft_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		"cfg":
			# Client applies the host's config (host ignores its own echo).
			if not NetMatch.is_host and not _config_locked():
				_mirror = bool(event.get("mirror", true))
				_sub_seed = int(event.get("seed", 0))
				if _mirror_btn != null:
					_mirror_btn.text = "MIRRORED" if _mirror else "RANDOM"
				_regenerate_deck()
				if _mode_ui_ready:
					_refresh_deck_ui()
					_update_status()
		"ready":
			_remote_ready = true
			_update_status()
			_maybe_fight()
		"finished":
			_remote_finished = true
			_store_opponent_deck(event.get("cards", []))
			var opp_slot := SkirmishState.get_slot(SkirmishState.opponent_index())
			if opp_slot != null:
				opp_slot.relics = event.get("relics", [])
				opp_slot.potions = event.get("potions", [])
			_maybe_begin_combat()


## Mirrors NetDraft — store the opponent's deck into their SkirmishState slot.
func _store_opponent_deck(cards: Array) -> void:
	var opp := SkirmishState.opponent_index()
	var slot := SkirmishState.get_slot(opp)
	if slot == null:
		return
	slot.deck.clear()
	slot.deck_uids.clear()
	for cid in cards:
		SkirmishState.add_card_to(opp, String(cid))


## Mirrors NetDraft — host launches when both decks are committed.
func _maybe_begin_combat() -> void:
	if not _claim_combat_launch():
		return
	_show_marching()
	if NetMatch.is_host:
		NetMatch.launch_combat(true)


# ─────────────────────────────────────────────────────────────────────────
#  STATUS SCREENS
# ─────────────────────────────────────────────────────────────────────────

func _show_marching() -> void:
	if _header == null:
		return
	_header.text = "Both decks ready — starting the match…"
	_header.add_theme_color_override("font_color", GREEN)
	Motion.pulse_label(_header, GILT_BRIGHT)


## Mirrors NetDraft — disconnect handler.
func _on_peer_lost(_id: int = 0) -> void:
	if _root == null:
		return
	for c in _deck_box.get_children():
		c.queue_free()
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
