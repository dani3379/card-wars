extends "res://scripts/scenes/NetDeckBuilder.gd"
## NetDraft.gd — the online Skirmish draft (Phase 1). Each player independently
## drafts a DECK_TARGET-card deck by picking 1 of 3 cards, DECK_TARGET times.
## Picks/progress sync over NetMatch; on finish each player ships its full deck
## to the other so the HOST holds both decks (it is authoritative for combat).
##
## Determinism: triplets come from a per-player seeded RNG (NetMatch.match_seed
## salted by player index). Card uids are deterministic (SkirmishState slot +
## position), so the host and client agree on every card's identity without
## extra negotiation.
##
## See docs/MULTIPLAYER_SKIRMISH_PLAN.md §11.

const CARD_SCENE = preload("res://scenes/card_2d.tscn")
# Scene constants, palette, and sync flags (MENU_SCENE, the colors, _rng,
# _target, _local_finished/_remote_finished, _root, _header) are inherited from
# NetDeckBuilder. The combat scene is launched via NetMatch.launch_combat()
# (host-authoritative, both peers transition together) — this script never
# change_scenes into it.

# ── Draft state ──
var _pool: Array[String] = []
# The legal pool split into the three reward tiers, plus a running draw bag per
# tier. Triplets roll each slot's RARITY at act-3 reward odds (30/50/20 — see
# _roll_triplet / CardDB.act_rarity_weights), then draw an id from that tier's
# bag WITHOUT replacement, so the slate leans uncommon/rare like a late-campaign
# reward instead of mirroring the flat pool. Starters have no reward tier, so
# SkirmishState.rarity_buckets() drops them from the draft entirely.
var _buckets: Dictionary = {}   # rarity → Array[String] of legal ids
var _bags: Dictionary = {}      # rarity → shuffled Array[String] (drawn down)
var _picks_made: int = 0
var _remote_picks: int = 0
# The opening flow is the shared ARSENAL stage (NetDeckBuilder._begin_arsenal —
# 3 battle-relic picks + 2 battle-potion picks, 1-of-3 each, pass allowed per
# slate) before the card triplets. The 20 card picks follow.

# Card-triplet rerolls. Each player gets a fixed budget for the whole draft;
# spending one re-deals the current triplet from the local salted stream. Purely
# LOCAL — a reroll consumes more of this player's own bag/RNG and is never sent
# over the wire (the opponent only ever receives pick counts + the sealed deck,
# so it can't observe or be desynced by a reroll). Equal budgets keep it fair.
const DRAFT_REROLLS: int = 2

## The deck ledger owns the right-hand strip of the canvas, and `_root` must be
## kept out of it — see `_build_ui` and `_build_ledger`, the only two readers.
const LEDGER_W := 306.0
const DRAFT_SLOT_SIZE := Vector2(Card2D.CARD_W, Card2D.CARD_H + 46.0)
var _rerolls_left: int = DRAFT_REROLLS
# Guards the reroll while its sweep animation plays (blocks a double-spend from a
# fast double-click before the fresh triplet is dealt).
var _rerolling: bool = false
var _triplet_build_generation := 0
var _triplet_ready := false

# ── UI refs ──
var _progress: Label
var _card_row: HBoxContainer
var _reroll_btn: Button

# ── Warband ledger (the running "cards picked so far" panel, à la Hearthstone's
# draft deck list — a mana-sorted roll of your picks, docked at the right edge,
# with a hover-to-enlarge preview). ──
var _ledger_list: VBoxContainer
var _ledger_count: Label
var _ledger_panel: PanelContainer
var _preview: Control = null

# Ledger row-art strips (the Hearthstone deck-list look): each row carries a
# band of its card's painting bleeding in from the right edge. The bands are
# AtlasTexture regions over the SAME memoized textures the card faces already
# use (CardArtAliases' static caches), so the strips add no disk reads and
# nothing per-frame — the only cost is a handful of extra Controls per row.
const ROW_H := 30.0
const ROW_ART_W := 118.0
const ROW_BG := Color(0.105, 0.088, 0.068, 1.0)
var _row_art_cache: Dictionary = {}          # card id → AtlasTexture (misses cached as null)
var _row_fade_tex: GradientTexture2D = null  # one shared bg→clear fade, built once


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")
	AudioBank.play_music_random(["net_lobby", "net_lobby_b", "rest_c"])  # muster pool

	# Safety: the draft is only reachable with a live peer. If someone lands here
	# cold (e.g. scene opened directly), bounce to the menu.
	if not NetMatch.is_connected_to_peer():
		get_tree().change_scene_to_file(MENU_SCENE)
		return

	# Configure the skirmish session from the live connection (combat mode, local
	# index, shared seed, match format, series reset). Shared by every mode.
	SkirmishState.begin_session()
	_target = SkirmishState.DECK_TARGET

	# Per-player triplet stream: same seed, different salt per side.
	_rng.seed = NetMatch.match_seed + (SkirmishState.local_index + 1) * 0x9E3779B1
	# Skirmish-legal pool lives in SkirmishState so the draft and combat agree on
	# what is playable. It returns the same stable-sorted list on both machines.
	# Split it by rarity so triplets can be rolled at act-3 reward ODDS (see
	# _roll_triplet) rather than flat over the whole pool.
	for id in SkirmishState.skirmish_legal_pool():
		_pool.append(String(id))
	_buckets = SkirmishState.rarity_buckets(_pool)

	NetMatch.draft_event_received.connect(_on_draft_event)
	NetMatch.peer_left.connect(_on_peer_lost)
	NetMatch.host_closed.connect(_on_peer_lost)

	_build_scaffold()
	_build_ledger()
	_begin_arsenal(_arsenal_finished)
	_install_net_chrome()
	_flatten_net_chart_styles(self)


## The arsenal overlay closed — surface the picks on the ledger, then open the
## card draft proper.
func _arsenal_finished() -> void:
	_rebuild_ledger()
	_present_triplet()


# ─────────────────────────────────────────────────────────────────────────
#  CARD POOL
# ─────────────────────────────────────────────────────────────────────────

func _roll_triplet() -> Array[String]:
	# Deal 3 distinct cards whose RARITY mix follows act-3 reward odds (30/50/20
	# common/uncommon/rare) — the draft's answer to "make the odds like act 3".
	# The per-rarity bags draw without replacement (state carried in _bags across
	# the whole draft), so a rarity's ids don't recur until its bag cycles. Uses
	# the salted per-player _rng, so the slate stays reproducible from the seed.
	return SkirmishState.deal_weighted_triplet(_buckets, _bags, _rng,
		SkirmishState.SKIRMISH_DRAFT_WEIGHTS)




# ─────────────────────────────────────────────────────────────────────────
#  UI
# ─────────────────────────────────────────────────────────────────────────

func _build_scaffold() -> void:
	_root = VBoxContainer.new()
	_root.name = "Draft"
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_theme_constant_override("separation", 18)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_top = 40
	_root.offset_bottom = -40
	# ── CENTRE IN THE SPACE THAT IS ACTUALLY FREE (2026-09-03) ──
	# `_root` was FULL_RECT while the deck ledger sits on top of the rightmost
	# 306px, so every centred child centred on the canvas (800) instead of on the
	# column it actually has. Measured off the render: 426px of dead space to the
	# left of the card triplet and 84px between its selection ring and the
	# ledger's edge — a 5:1 lean that reads as the cards crowding the panel.
	_root.offset_right = -LEDGER_W
	add_child(_root)

	_root.add_child(GameTheme.make_screen_title("DRAFT YOUR DECK", GILT_BRIGHT))

	_header = GameTheme.make_label("", 20, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	_progress = GameTheme.make_label("", 16, ASH)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_progress)

	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 30)
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_card_row)

	# Reroll button sits below the triplet — a sibling of _card_row so it survives
	# _clear_card_row(). Hidden outside the card-pick stage and toggled by budget
	# in _present_triplet / _refresh_reroll_btn.
	_reroll_btn = GameTheme.make_themed_button("", Color(0.20, 0.14, 0.06),
		Vector2(300, 40), 16)
	_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reroll_btn.visible = false
	_reroll_btn.pressed.connect(_on_reroll_triplet)
	_root.add_child(_reroll_btn)




func _present_triplet() -> void:
	_clear_card_row()
	_triplet_ready = false
	var build_generation := _triplet_build_generation
	_header.text = "Pick a card  ·  %d / %d" % [_picks_made + 1, _target]
	_update_progress()

	# Keep reroll usable while a cold slate is still being flattened.
	_refresh_reroll_btn()
	var picker_alive := func() -> bool:
		return is_inside_tree() and not _local_finished \
			and build_generation == _triplet_build_generation
	var triplet: Array[String] = _roll_triplet()
	var data_list: Array[Dictionary] = []
	var slots: Array[Control] = []
	var sleeves: Array[Control] = []
	# Establish the complete three-card geometry before the first await. A cold
	# card can take several render frames to flatten, but no earlier card is ever
	# recentered as a later sibling arrives.
	for id in triplet:
		var data: Dictionary = SkirmishState.skirmish_card_data(id)
		data_list.append(data)
		var loading := _make_loading_card_slot(DRAFT_SLOT_SIZE,
			GameTheme.rarity_color(String(data.get("rarity", "common"))),
			_card_row)
		var slot: Control = loading["slot"]
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_card_row.add_child(slot)
		slots.append(slot)
		sleeves.append(loading["sleeve"])
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	if not picker_alive.call():
		return

	var faces: Array[Control] = []
	var buttons: Array[Button] = []
	var card_wraps: Array[Control] = []
	for idx in range(triplet.size()):
		var id: String = triplet[idx]
		var data: Dictionary = data_list[idx]
		if not CardTextureCache.has(data) \
				and not CardTextureCache.has_gallery(data):
			await CardArtAliases.prewarm_card_art(data)
			if not picker_alive.call():
				CardArtAliases.release_card_art(data)
				return
			if not CardTextureCache.has(data):
				await CardTextureCache.bake_gallery(data, picker_alive)
			CardArtAliases.release_card_art(data)
		if not picker_alive.call():
			return
		var use_gallery := not CardTextureCache.has(data) \
			and CardTextureCache.has_gallery(data)
		var slot: Control = slots[idx]
		var face := VBoxContainer.new()
		face.add_theme_constant_override("separation", 8)
		face.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_stage_complete_hand_member(face)
		slot.set_meta("draft_face", face)
		slot.set_meta("draft_id", id)
		faces.append(face)

		# Plain-Control wrapper, exactly as the campaign muster slate builds it
		# (Recruit._present_choices): the rarity shine parents itself to the node
		# it decorates and centres on it, so that node must NOT be a Container —
		# a Container re-fits its children every layout pass and would drag the
		# sunburst back to the corner.
		var card_wrap := Control.new()
		card_wrap.custom_minimum_size = Vector2(Card2D.CARD_W, Card2D.CARD_H)
		card_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_wrap.pivot_offset = card_wrap.custom_minimum_size * 0.5
		# Contact shadow, height-aware — it reads what `Motion.deal_card` writes,
		# so it spreads and pales while the card is in flight and tightens on
		# landing. Same helper the campaign slates use.
		card_wrap.draw.connect(_draw_draft_shadow.bind(card_wrap))
		face.add_child(card_wrap)

		var card = CARD_SCENE.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = id
		card.is_on_battlefield = true
		card.static_display = true
		card.live_baked_mode = true
		card.gallery_baked_mode = use_gallery
		card_wrap.add_child(card)
		slot.set_meta("draft_card", card)
		card_wraps.append(card_wrap)

		# Ember, not the old olive green — the commit action wears the same
		# warm tile as every other commit in the game. (Audit 2026-07-21.)
		var pick_btn := GameTheme.make_themed_button("CHOOSE",
			Color(0.34, 0.22, 0.08), Vector2(140, 38), 16)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick_btn.disabled = true
		pick_btn.pressed.connect(_on_pick.bind(id, build_generation))
		slot.set_meta("draft_pick_button", pick_btn)
		face.add_child(pick_btn)
		buttons.append(pick_btn)
		_flatten_net_chart_styles(pick_btn)
		if DisplayServer.get_name() == "headless":
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		if not picker_alive.call():
			return

	# One hand, one turn: all three backs close together and all three ornate
	# faces open together. Interaction unlocks only after the whole hand exists.
	await _reveal_complete_hand(faces, sleeves)
	if not picker_alive.call():
		return
	for button in buttons:
		if button != null and is_instance_valid(button):
			button.disabled = false
	for idx in card_wraps.size():
		GameTheme.rarity_reveal(card_wraps[idx],
			String(data_list[idx].get("rarity", "")), 0.31)
	_triplet_ready = true
	_refresh_reroll_btn()


## Show/label the reroll button for the current triplet. Visible only in the
## card-pick stage with budget remaining; the label carries the running count.
func _refresh_reroll_btn() -> void:
	if _reroll_btn == null:
		return
	var can := not _local_finished and not arsenal_active() \
		and _rerolls_left > 0
	_reroll_btn.visible = can
	if can:
		_reroll_btn.disabled = not _triplet_ready or _rerolling
		_reroll_btn.text = "REROLL THESE THREE  (%d left)" % _rerolls_left


## The three complete choice faces in the current triplet. The fixed slots stay
## seated during a reroll while each card and CHOOSE plaque leave as one object.
func _current_triplet_faces() -> Array:
	var out: Array = []
	for slot in _card_row.get_children():
		var face = slot.get_meta("draft_face", null)
		if face is Control and is_instance_valid(face):
			out.append(face)
	return out


func _set_triplet_choices_disabled(disabled: bool) -> void:
	for slot in _card_row.get_children():
		var button: Button = slot.get_meta("draft_pick_button", null) as Button
		if button != null and is_instance_valid(button):
			button.disabled = disabled


func _triplet_face_for(id: String) -> Control:
	for slot in _card_row.get_children():
		if String(slot.get_meta("draft_id", "")) == id:
			return slot.get_meta("draft_face", null) as Control
	return null


## Spend one reroll: sweep the current three off the table and re-deal from the
## local salted stream. Purely local (no draft event) — the opponent never sees
## or resolves it. Guarded so a double-click or a click landed after finishing
## can't over-draw the budget; _rerolling blocks re-entry during the sweep.
func _on_reroll_triplet() -> void:
	if _rerolling or not _triplet_ready or _local_finished or arsenal_active() \
			or _rerolls_left <= 0:
		return
	_rerolling = true
	_triplet_build_generation += 1
	_rerolls_left -= 1
	_triplet_ready = false
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	if _reroll_btn != null:
		_reroll_btn.disabled = true
	_set_triplet_choices_disabled(true)
	# Arcane reshuffle: the complete choice leaves while its fixed slot remains.
	var sweep_duration := GameTheme.reroll_sweep(
		self, _current_triplet_faces(), SPELL_BLUE)
	await get_tree().create_timer(sweep_duration).timeout
	_rerolling = false
	_present_triplet()


func _clear_card_row() -> void:
	_triplet_build_generation += 1
	_triplet_ready = false
	for c in _card_row.get_children():
		_card_row.remove_child(c)
		c.queue_free()


# ─────────────────────────────────────────────────────────────────────────
#  WARBAND LEDGER  (the running "what have I drafted" panel)
# ─────────────────────────────────────────────────────────────────────────

## Right-docked panel listing every card picked so far, grouped by id, ×N-counted,
## and sorted by Command cost — the running deck list. A sibling of _root, so it
## survives the waiting / marching screens (the player can review the sealed 20).
func _build_ledger() -> void:
	_ledger_panel = PanelContainer.new()
	_ledger_panel.add_theme_stylebox_override("panel",
		GameTheme.make_panel_style(Color(0.06, 0.05, 0.042, 0.94),
			Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.55), 1, 6))
	_ledger_panel.anchor_left = 1.0
	_ledger_panel.anchor_right = 1.0
	_ledger_panel.anchor_top = 0.0
	_ledger_panel.anchor_bottom = 1.0
	_ledger_panel.offset_left = -LEDGER_W
	_ledger_panel.offset_right = -16.0
	_ledger_panel.offset_top = 78.0
	_ledger_panel.offset_bottom = -20.0
	add_child(_ledger_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_ledger_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := GameTheme.make_label("YOUR DECK", 18, GILT_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_ledger_count = GameTheme.make_label("0 / %d" % _target, 15, ASH)
	_ledger_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_ledger_count)

	col.add_child(GameTheme.make_separator(
		Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.28), 240.0))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	GameTheme.style_thin_scrollbar(scroll)
	col.add_child(scroll)

	_ledger_list = VBoxContainer.new()
	_ledger_list.add_theme_constant_override("separation", 4)
	_ledger_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ledger_list)

	_rebuild_ledger()


## Repaint the ledger from the local deck: dedupe → count → sort by (cost, name).
func _rebuild_ledger() -> void:
	if _ledger_list == null:
		return
	_hide_preview()                     # a hovered row may be about to be freed
	for c in _ledger_list.get_children():
		_ledger_list.remove_child(c)
		c.queue_free()

	var slot := SkirmishState.local_slot()
	var deck: Array = slot.deck if slot != null else []

	# The drafted arsenal leads the roll — one chip + name line per relic, then
	# per potion (up to 3 + 2 from the arsenal stage).
	#
	# SAY WHAT THEY ARE, AND RULE THEM OFF. These rows used to run straight into
	# the card list with no heading and no divider, inside a panel titled YOUR
	# DECK whose count line read "5 / 20" — so five relics and potions sat above
	# five cards and the panel insisted there were five things in it. Every one of
	# them reads as a card at a glance (a chip, a gilt name, a row), and the count
	# openly contradicting the rows is the sort of thing a player reports as the
	# deck counter being broken. They are not cards and they are not part of the
	# twenty; the caption and the rule below say so.
	if slot != null and not (slot.relics.is_empty() and slot.potions.is_empty()):
		var ars_cap := GameTheme.make_label("ARSENAL", 13, ASH)
		ars_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ledger_list.add_child(ars_cap)
		for rid_v in slot.relics:
			var rid := String(rid_v)
			var rrow := HBoxContainer.new()
			rrow.add_theme_constant_override("separation", 8)
			rrow.mouse_filter = Control.MOUSE_FILTER_PASS
			rrow.add_child(GameTheme.make_relic_chip(rid, 30))
			var rname := GameTheme.make_label(
				String(RelicDB.get_relic(rid).get("name", rid)), 16, GILT_BRIGHT)
			rname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# EXPAND_FILL is load-bearing: a trim-ellipsis label reports ~0 min
			# width, so without it the HBox gives the name no room at all.
			rname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			rrow.add_child(rname)
			_ledger_list.add_child(rrow)
		for pid_v in slot.potions:
			var ppid := String(pid_v)
			var prow := HBoxContainer.new()
			prow.add_theme_constant_override("separation", 8)
			prow.mouse_filter = Control.MOUSE_FILTER_PASS
			prow.add_child(GameTheme.make_potion_chip(ppid, 30))
			var pname := GameTheme.make_label(
				String(PotionDB.get_potion(ppid).get("name", ppid)), 16, GILT_BRIGHT)
			pname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			prow.add_child(pname)
			_ledger_list.add_child(prow)
		# The rule that separates "what you carry" from "the twenty".
		_ledger_list.add_child(GameTheme.make_separator(
			Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.20), 200.0))
		var cards_cap := GameTheme.make_label("CARDS", 13, ASH)
		cards_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ledger_list.add_child(cards_cap)

	var counts: Dictionary = {}
	var order: Array[String] = []
	for cid in deck:
		var s := String(cid)
		if not counts.has(s):
			counts[s] = 0
			order.append(s)
		counts[s] += 1

	order.sort_custom(func(a: String, b: String) -> bool:
		var da := CardDB.get_card_data(a)
		var db := CardDB.get_card_data(b)
		var ca := int(da.get("cost", 0))
		var cb := int(db.get("cost", 0))
		if ca != cb:
			return ca < cb
		return String(da.get("name", a)) < String(db.get("name", b)))

	for s in order:
		_ledger_list.add_child(_make_ledger_row(s, int(counts[s])))

	if _ledger_count != null:
		_ledger_count.text = "%d / %d" % [deck.size(), _target]

	if deck.is_empty():
		var hint := GameTheme.make_label(
			"Cards you choose appear here.", 14, ASH)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ledger_list.add_child(hint)


## One ledger line, Hearthstone deck-list style: a dark tile with a band of the
## card's own painting bleeding in from the right, [cost gem] Name on the solid
## left, the ×N tally chipped over the art. Hovering still enlarges the full card.
func _make_ledger_row(id: String, count: int) -> Control:
	var d := SkirmishState.skirmish_card_data(id)
	var is_spell := String(d.get("type", "")) == "spell"

	# PASS (not STOP): the row still emits hover signals, but mouse-wheel events
	# bubble up to the ScrollContainer so a long ledger can still be scrolled.
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.clip_contents = true

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = ROW_BG
	# Rounded on the left only — the right edge stays square so the art band's
	# corners sit flush instead of overhanging the rounding.
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_bottom_left = 4
	bg.add_theme_stylebox_override("panel", bg_style)
	row.add_child(bg)

	var art := _row_art_for(id, d)
	if art != null:
		var strip := TextureRect.new()
		strip.texture = art
		strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		strip.stretch_mode = TextureRect.STRETCH_SCALE
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		strip.offset_left = -ROW_ART_W
		# Knock the band back before the gradient touches it. The fade below only
		# darkens the band's LEFT edge (it reaches zero alpha at the right), so a
		# cold, saturated painting — the teals and blood-reds in this pool — hit
		# the row's right edge at full strength and read as a colour bar bleeding
		# through the list rather than as card art behind a name. Hearthstone's
		# deck list keeps the name the hero; so should this. (Audit 2026-07-21.)
		strip.modulate = Color(0.70, 0.68, 0.66, 0.80)
		row.add_child(strip)

		var fade := TextureRect.new()
		fade.texture = _row_fade()
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		fade.offset_left = -ROW_ART_W
		row.add_child(fade)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 4.0
	hbox.offset_right = -6.0
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var gem := Label.new()
	gem.text = str(int(d.get("cost", 0)))
	gem.custom_minimum_size = Vector2(26, 26)
	gem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameTheme.font_stat != null:
		gem.add_theme_font_override("font", GameTheme.font_stat)
	gem.add_theme_font_size_override("font_size", 15)
	gem.add_theme_color_override("font_color", IVORY)
	var gem_bg := StyleBoxFlat.new()
	gem_bg.bg_color = Color(0.13, 0.16, 0.30, 1.0)        # Command-seal navy
	gem_bg.border_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.7)
	gem_bg.set_border_width_all(1)
	gem_bg.set_corner_radius_all(13)
	gem.add_theme_stylebox_override("normal", gem_bg)
	hbox.add_child(gem)

	# Outlined so the name stays readable where it crosses into the painting.
	var name_lbl := GameTheme.make_label(String(d.get("name", id)), 16,
		SPELL_BLUE if is_spell else IVORY, true)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_lbl)

	if count > 1:
		var cnt := GameTheme.make_label("×%d" % count, 16, GILT_BRIGHT)
		cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Dark backing chip so the tally reads over the painting.
		var cnt_bg := StyleBoxFlat.new()
		cnt_bg.bg_color = Color(0.05, 0.04, 0.03, 0.88)
		cnt_bg.border_color = Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.35)
		cnt_bg.set_border_width_all(1)
		cnt_bg.set_corner_radius_all(9)
		cnt_bg.content_margin_left = 7.0
		cnt_bg.content_margin_right = 7.0
		cnt.add_theme_stylebox_override("normal", cnt_bg)
		hbox.add_child(cnt)
	else:
		# Keep the art's right end clear of text — long names ellipsize before it.
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(44, 0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(spacer)

	row.mouse_entered.connect(_show_preview.bind(id))
	row.mouse_exited.connect(_hide_preview)
	return row


## Resolve a card's painting to a wide band for its ledger row. Mirrors
## Card2D._find_card_art's resolution order (spell art first for spells, then
## creature id → name → "e_"+name); those loaders memoize their probes, so after
## the first look-up this is dictionary hits all the way down. The band is an
## AtlasTexture region — a rectangle over the existing texture, no pixel copies —
## biased above center, where the paintings keep their faces. Misses cache as
## null (curses and art-less tokens keep a bare tile).
func _row_art_for(id: String, d: Dictionary) -> Texture2D:
	if _row_art_cache.has(id):
		return _row_art_cache[id]
	var name_id := String(d.get("name", "")).to_lower().replace(" ", "_").replace("'", "")
	var art: Texture2D = null
	if String(d.get("type", "")) == "spell":
		art = CardArtAliases.try_load_spell_art(id)
		if art == null and name_id != "":
			art = CardArtAliases.try_load_spell_art(name_id)
	if art == null:
		art = CardArtAliases.try_load_creature_art(id)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art(name_id)
	if art == null and name_id != "":
		art = CardArtAliases.try_load_creature_art("e_" + name_id)
	var band: Texture2D = null
	if art != null:
		var tw := float(art.get_width())
		var th := float(art.get_height())
		if tw > 0.0 and th > 0.0:
			var band_h := minf(th, tw * ROW_H / ROW_ART_W)
			var band_y := clampf(th * 0.38 - band_h * 0.5, 0.0, th - band_h)
			var atlas := AtlasTexture.new()
			atlas.atlas = art
			atlas.region = Rect2(0.0, band_y, tw, band_h)
			band = atlas
	_row_art_cache[id] = band
	return band


## The shared left-edge fade laid over every art band: row-bg ink at the left
## (so the name sits on solid ground) dissolving to clear at the right where
## the painting shows through. Built once; every row reuses the same texture.
func _row_fade() -> GradientTexture2D:
	if _row_fade_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			ROW_BG,
			Color(ROW_BG.r, ROW_BG.g, ROW_BG.b, 0.35),
			Color(ROW_BG.r, ROW_BG.g, ROW_BG.b, 0.0),
		])
		_row_fade_tex = GradientTexture2D.new()
		_row_fade_tex.gradient = g
		_row_fade_tex.width = 128
		_row_fade_tex.height = 4
	return _row_fade_tex


## Pop the full card just left of the ledger while a row is hovered (Hearthstone's
## draft-list behaviour). Mouse-transparent so it never eats a click on the board.
func _show_preview(id: String) -> void:
	_hide_preview()
	if _ledger_panel == null:
		return
	var card = CARD_SCENE.instantiate()
	card.card_data = SkirmishState.skirmish_card_data(id)
	card.card_id = id
	card.is_on_battlefield = true
	card.static_display = true
	card.live_baked_mode = true
	card.gallery_baked_mode = not CardTextureCache.has(card.card_data) \
		and CardTextureCache.has_gallery(card.card_data)
	add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview = card
	# Right edge sits just left of the panel; vertically centred on the panel rect.
	var cw := 225.0
	var ch := 300.0
	var px: float = _ledger_panel.position.x - cw - 14.0
	var py: float = _ledger_panel.position.y + (_ledger_panel.size.y - ch) * 0.5
	card.position = Vector2(maxf(px, 8.0), maxf(py, 8.0))


func _hide_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


# ─────────────────────────────────────────────────────────────────────────
#  PICK / FINISH FLOW
# ─────────────────────────────────────────────────────────────────────────

func _on_pick(id: String, source_generation: int = -1) -> void:
	if _rerolling or not _triplet_ready or _local_finished:
		return
	if source_generation >= 0 and source_generation != _triplet_build_generation:
		return
	_triplet_ready = false
	_set_triplet_choices_disabled(true)
	if _reroll_btn != null:
		_reroll_btn.disabled = true
	# Invalidate the suspended slate builder and every old bound button at once.
	_triplet_build_generation += 1
	SkirmishState.add_card_to(SkirmishState.local_index, id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_picks_made += 1
	NetMatch.send_draft_event({"t": "pick", "n": _picks_made, "id": id})

	# Keep cause and effect connected: the chosen writ joins the warband ledger
	# while the two passed-over choices retire together. State/network mutation
	# above remains immediate; this short beat is presentation only.
	var chosen := _triplet_face_for(id)
	if chosen != null and is_instance_valid(chosen) \
			and not (UserSettings != null and UserSettings.reduce_motion) \
			and DisplayServer.get_name() != "headless":
		GameTheme.claim_pop(chosen)
		for other in _current_triplet_faces():
			if other != chosen and other is Control and is_instance_valid(other):
				GameTheme.fade_exit(other, 0.18)
		await get_tree().create_timer(0.09).timeout
		if is_inside_tree() and is_instance_valid(chosen) \
				and _ledger_panel != null and is_instance_valid(_ledger_panel):
			var target := _ledger_panel.global_position \
				+ Vector2(_ledger_panel.size.x * 0.5, 66.0)
			await GameTheme.pocket_away(chosen, target, 0.28)
	if not is_inside_tree():
		return
	_rebuild_ledger()
	if _ledger_panel != null and is_instance_valid(_ledger_panel):
		GameTheme.punch(_ledger_panel, 1.015)
	if _picks_made >= _target:
		_finish_draft()
	else:
		_present_triplet()


func _finish_draft() -> void:
	_local_finished = true
	var my_deck: Array = SkirmishState.local_slot().deck.duplicate()
	# Bake the sealed warband's card textures behind the waiting screen (idle
	# time) so the fight's _prebake_hand_textures opens on cache hits.
	ScenePreload.warm_card_ids(my_deck, true)
	# Auto-keep the drafted warband so it can be replayed later via Constructed →
	# LOAD without drafting again (the player asked for exactly this). Timestamped
	# name keeps each draft distinct; SavedDecks caps the list and drops the oldest.
	var stamp := Time.get_datetime_string_from_system().replace("T", " ")
	var unique_suffix := Time.get_ticks_msec() % 1000
	SavedDecks.save_deck("Draft %s.%03d" % [stamp, unique_suffix], my_deck)
	# The battle relic AND potion ride the deck handoff so the host's slot table
	# knows both sides' picks (each peer's combat only READS its own, but the
	# record is whole — and the host resolves the client's heal potion for it).
	var my_relics: Array = SkirmishState.local_slot().relics.duplicate()
	var my_potions: Array = SkirmishState.local_slot().potions.duplicate()
	NetMatch.send_draft_event({"t": "finished", "cards": my_deck,
		"relics": my_relics, "potions": my_potions})
	_build_waiting_ui()
	_maybe_begin_combat()


func _on_draft_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		"pick":
			_remote_picks = int(event.get("n", 0))
			_update_progress()
		"finished":
			_remote_finished = true
			_store_opponent_deck(event.get("cards", []))
			var opp_slot := SkirmishState.get_slot(SkirmishState.opponent_index())
			if opp_slot != null:
				opp_slot.relics = event.get("relics", [])
				opp_slot.potions = event.get("potions", [])
			_update_progress()
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
	# Both decks are committed to SkirmishState (local picks via _on_pick, the
	# opponent's via _store_opponent_deck). The host is authoritative for the
	# transition: launch_combat sets the skirmish mode on both sides and drops
	# both peers into combat.tscn together. The client does NOT change scene on
	# its own — it waits for the host's launch RPC (handled inside NetMatch).
	_show_marching_status()
	if NetMatch.is_host:
		NetMatch.launch_combat(true)


func _show_marching_status() -> void:
	if _reroll_btn != null:
		_reroll_btn.visible = false
	_header.text = "Both decks drafted — starting the match…"
	_header.add_theme_color_override("font_color", GREEN)
	Motion.pulse_label(_header, GILT_BRIGHT)
	_update_progress()


# ─────────────────────────────────────────────────────────────────────────
#  WAITING SCREEN
# ─────────────────────────────────────────────────────────────────────────

func _build_waiting_ui() -> void:
	_clear_card_row()
	if _reroll_btn != null:
		_reroll_btn.visible = false
	_header.text = "Deck complete — %d cards." % _target
	_update_progress()
	var note := GameTheme.make_label("Waiting for your opponent to finish drafting…",
		16, ASH)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_row.add_child(note)


# ─────────────────────────────────────────────────────────────────────────
#  PROGRESS / DISCONNECT
# ─────────────────────────────────────────────────────────────────────────

func _update_progress() -> void:
	if _progress == null:
		return
	var you := _target if _local_finished else _picks_made
	var opp := _target if _remote_finished else _remote_picks
	_progress.text = "You: %d / %d picked   ·   Opponent: %d / %d picked" % [
		you, _target, opp, _target]


func _on_peer_lost(_id: int = 0) -> void:
	if _root == null:
		return
	_clear_card_row()
	if _reroll_btn != null:
		_reroll_btn.visible = false
	_header.text = "Opponent disconnected — the match is off."
	_header.add_theme_color_override("font_color", Color(0.90, 0.45, 0.35))
	_progress.text = ""
	var back := GameTheme.make_themed_button("BACK TO MENU",
		Color(0.26, 0.16, 0.14), Vector2(220, 44), 16)
	back.pressed.connect(_leave_to_menu.bind(back))
	_root.add_child(back)


## Contact shadow under a drafted card — the shared kit helper, reading the
## height `Motion.deal_card` writes to the wrapper.
func _draw_draft_shadow(card_wrap: Control) -> void:
	Motion.card_shadow(card_wrap,
		Vector2(Card2D.CARD_W * 0.5, Card2D.CARD_H + 8.0),
		float(card_wrap.get_meta("deal_lift", 0.0)), 96.0,
		card_wrap.get_meta("deal_off", Vector2.ZERO))
