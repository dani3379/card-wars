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
# The opening flow is two one-pick stages before the card triplets: a battle
# RELIC slate, then a battle POTION slate (pick 1 of 3 or decline on each — see
# SkirmishState.NET_RELIC_POOL / NET_POTION_POOL). The 20 card picks follow.
var _relic_stage: bool = true
var _potion_stage: bool = false

# Card-triplet rerolls. Each player gets a fixed budget for the whole draft;
# spending one re-deals the current triplet from the local salted stream. Purely
# LOCAL — a reroll consumes more of this player's own bag/RNG and is never sent
# over the wire (the opponent only ever receives pick counts + the sealed deck,
# so it can't observe or be desynced by a reroll). Equal budgets keep it fair.
const DRAFT_REROLLS: int = 2
var _rerolls_left: int = DRAFT_REROLLS
# Guards the reroll while its sweep animation plays (blocks a double-spend from a
# fast double-click before the fresh triplet is dealt).
var _rerolling: bool = false

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
	AudioBank.play_music_random(["map_c", "map_d", "rest_c"])  # muster pool

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
	_present_relic_slate()
	_install_net_chrome()


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
		CardDB.act_rarity_weights(SkirmishState.DRAFT_ACT))


## 3 distinct battle relics off the net-safe pool. Rolled from the same salted
## per-player stream as the card triplets — each player sees their own slate.
func _roll_relic_slate() -> Array[String]:
	return SkirmishState.deal_unique_cards(SkirmishState.NET_RELIC_POOL, 3, _rng)


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
	add_child(_root)

	_root.add_child(GameTheme.make_screen_title("DRAFT YOUR WARBAND", GILT_BRIGHT))

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


## The opening stage: one battle relic to fight with — or none. Relics here are
## resource-local by construction (see SkirmishState.NET_RELIC_POOL), so each
## side's pick works over the wire without host resolution.
func _present_relic_slate() -> void:
	_clear_card_row()
	_header.text = "Choose a battle relic — it fights beside your warband"
	_update_progress()

	var idx := 0
	for rid in _roll_relic_slate():
		var r := RelicDB.get_relic(rid)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 10)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.custom_minimum_size = Vector2(230, 0)
		_card_row.add_child(slot)

		var chip := GameTheme.make_relic_chip(rid, 96)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(chip)

		var name_lbl := GameTheme.make_label(String(r.get("name", rid)), 20, GILT_BRIGHT)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(name_lbl)

		var desc_lbl := GameTheme.make_label(String(r.get("desc", "")), 16, IVORY)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(220, 64)
		slot.add_child(desc_lbl)

		var pick_btn := GameTheme.make_themed_button("CHOOSE",
			Color(0.18, 0.36, 0.18), Vector2(140, 38), 16)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick_btn.pressed.connect(_on_relic_pick.bind(rid))
		slot.add_child(pick_btn)

		_animate_card_reveal(slot, pick_btn, idx)
		idx += 1

	# The decline column — fighting unadorned is a legitimate choice, not an error.
	var skip_slot := VBoxContainer.new()
	skip_slot.add_theme_constant_override("separation", 10)
	skip_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_child(skip_slot)
	var skip_btn := GameTheme.make_themed_button("FIGHT WITHOUT ONE",
		Color(0.24, 0.20, 0.16), Vector2(210, 38), 16)
	skip_btn.pressed.connect(_on_relic_pick.bind(""))
	skip_slot.add_child(skip_btn)


func _on_relic_pick(rid: String) -> void:
	if _local_finished or not _relic_stage:
		return
	_relic_stage = false
	if rid != "":
		var slot := SkirmishState.local_slot()
		if slot != null:
			slot.relics.append(rid)
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
	_rebuild_ledger()
	# The potion slate follows the relic — one draught to fight with, or none.
	_potion_stage = true
	_present_potion_slate()


## 3 distinct battle potions off the net-safe pool (same salted per-player stream
## as the relic slate and card triplets — each side sees its own three).
func _roll_potion_slate() -> Array[String]:
	return SkirmishState.deal_unique_cards(SkirmishState.NET_POTION_POOL, 3, _rng)


## The second opening stage: one battle potion to fight with — or none. Every
## potion here is non-targeted and caster-resolved (SkirmishState.NET_POTION_POOL),
## so each side's pick works over the wire like the relic.
## Host-side board/HP bottles are now handled by Combat's net potion resolver.
## Current rule: targeted and host-authoritative potions are allowed when Combat
## has an explicit net resolver for their effect.
func _present_potion_slate() -> void:
	_clear_card_row()
	_header.text = "Choose a battle potion — one draught for the fight"
	_update_progress()

	var idx := 0
	for pid in _roll_potion_slate():
		var p := PotionDB.get_potion(pid)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 10)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.custom_minimum_size = Vector2(230, 0)
		_card_row.add_child(slot)

		var chip := GameTheme.make_potion_chip(pid, 96)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(chip)

		var name_lbl := GameTheme.make_label(String(p.get("name", pid)), 20, GILT_BRIGHT)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(name_lbl)

		var desc_lbl := GameTheme.make_label(String(p.get("desc", "")), 16, IVORY)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(220, 64)
		slot.add_child(desc_lbl)

		var pick_btn := GameTheme.make_themed_button("CHOOSE",
			Color(0.18, 0.36, 0.18), Vector2(140, 38), 16)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick_btn.pressed.connect(_on_potion_pick.bind(pid))
		slot.add_child(pick_btn)

		_animate_card_reveal(slot, pick_btn, idx)
		idx += 1

	var skip_slot := VBoxContainer.new()
	skip_slot.add_theme_constant_override("separation", 10)
	skip_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_child(skip_slot)
	var skip_btn := GameTheme.make_themed_button("FIGHT WITHOUT ONE",
		Color(0.24, 0.20, 0.16), Vector2(210, 38), 16)
	skip_btn.pressed.connect(_on_potion_pick.bind(""))
	skip_slot.add_child(skip_btn)


func _on_potion_pick(pid: String) -> void:
	if _local_finished or not _potion_stage:
		return
	_potion_stage = false
	if pid != "":
		var slot := SkirmishState.local_slot()
		if slot != null:
			slot.potions.append(pid)
		if AudioBank != null:
			AudioBank.play_sfx("card_play")
	_rebuild_ledger()
	_present_triplet()


func _present_triplet() -> void:
	_clear_card_row()
	_header.text = "Pick a card  ·  %d / %d" % [_picks_made + 1, _target]
	_update_progress()

	var idx := 0
	for id in _roll_triplet():
		var data := CardDB.get_card_data(id)
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 8)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		_card_row.add_child(slot)

		var card = CARD_SCENE.instantiate()
		card.card_data = data.duplicate(true)
		card.card_id = id
		card.is_on_battlefield = true
		card.live_baked_mode = true
		CardTextureCache.bake(data)
		slot.add_child(card)

		var pick_btn := GameTheme.make_themed_button("CHOOSE",
			Color(0.18, 0.36, 0.18), Vector2(140, 38), 16)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick_btn.pressed.connect(_on_pick.bind(id))
		slot.add_child(pick_btn)

		_animate_card_reveal(card, pick_btn, idx)
		idx += 1

	_refresh_reroll_btn()


## Show/label the reroll button for the current triplet. Visible only in the
## card-pick stage with budget remaining; the label carries the running count.
func _refresh_reroll_btn() -> void:
	if _reroll_btn == null:
		return
	var can := not _local_finished and not _relic_stage and not _potion_stage \
		and _rerolls_left > 0
	_reroll_btn.visible = can
	if can:
		_reroll_btn.disabled = false
		_reroll_btn.text = "Reroll these three  (%d left)" % _rerolls_left


## The three live Card2D nodes in the current triplet (one per slot column).
func _current_triplet_cards() -> Array:
	var out: Array = []
	for slot in _card_row.get_children():
		for c in slot.get_children():
			if "card_id" in c:
				out.append(c)
				break
	return out


## Spend one reroll: sweep the current three off the table and re-deal from the
## local salted stream. Purely local (no draft event) — the opponent never sees
## or resolves it. Guarded so a double-click or a click landed after finishing
## can't over-draw the budget; _rerolling blocks re-entry during the sweep.
func _on_reroll_triplet() -> void:
	if _rerolling or _local_finished or _relic_stage or _potion_stage \
			or _rerolls_left <= 0:
		return
	_rerolling = true
	_rerolls_left -= 1
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	if _reroll_btn != null:
		_reroll_btn.disabled = true
	# Arcane reshuffle: a cool-blue pulse scatters the current three.
	GameTheme.reroll_sweep(self, _current_triplet_cards(), SPELL_BLUE)
	await get_tree().create_timer(0.18).timeout
	_present_triplet()
	_rerolling = false


func _animate_card_reveal(card: Control, pick_btn: Control, idx: int) -> void:
	card.modulate.a = 0.0
	card.scale = Vector2(0.6, 0.6)
	pick_btn.modulate.a = 0.0
	var delay := 0.10 + float(idx) * 0.10
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.24).set_delay(delay)
	tw.tween_property(card, "scale", Vector2.ONE, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	tw.tween_property(pick_btn, "modulate:a", 1.0, 0.20).set_delay(delay + 0.14)


func _clear_card_row() -> void:
	for c in _card_row.get_children():
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
	_ledger_panel.offset_left = -306.0
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

	var title := GameTheme.make_label("YOUR WARBAND", 18, GILT_BRIGHT)
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
		c.queue_free()

	var slot := SkirmishState.local_slot()
	var deck: Array = slot.deck if slot != null else []

	# The chosen battle relic leads the roll — chip + name on one line.
	if slot != null and not slot.relics.is_empty():
		var rid := String(slot.relics[0])
		var rrow := HBoxContainer.new()
		rrow.add_theme_constant_override("separation", 8)
		rrow.mouse_filter = Control.MOUSE_FILTER_PASS
		rrow.add_child(GameTheme.make_relic_chip(rid, 30))
		var rname := GameTheme.make_label(
			String(RelicDB.get_relic(rid).get("name", rid)), 16, GILT_BRIGHT)
		rname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rrow.add_child(rname)
		_ledger_list.add_child(rrow)

	# The chosen battle potion sits just under the relic — same chip + name line.
	if slot != null and not slot.potions.is_empty():
		var ppid := String(slot.potions[0])
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		prow.mouse_filter = Control.MOUSE_FILTER_PASS
		prow.add_child(GameTheme.make_potion_chip(ppid, 30))
		var pname := GameTheme.make_label(
			String(PotionDB.get_potion(ppid).get("name", ppid)), 16, GILT_BRIGHT)
		pname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		prow.add_child(pname)
		_ledger_list.add_child(prow)

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
	var d := CardDB.get_card_data(id)
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
	card.card_data = CardDB.get_card_data(id).duplicate(true)
	card.card_id = id
	card.is_on_battlefield = true
	card.live_baked_mode = true
	CardTextureCache.bake(card.card_data)
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

func _on_pick(id: String) -> void:
	if _local_finished:
		return
	SkirmishState.add_card_to(SkirmishState.local_index, id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_rebuild_ledger()
	_picks_made += 1
	NetMatch.send_draft_event({"t": "pick", "n": _picks_made})
	if _picks_made >= _target:
		_finish_draft()
	else:
		_present_triplet()


func _finish_draft() -> void:
	_local_finished = true
	var my_deck: Array = SkirmishState.local_slot().deck.duplicate()
	# Bake the sealed warband's card textures behind the waiting screen (idle
	# time) so the fight's _prebake_hand_textures opens on cache hits.
	ScenePreload.warm_card_ids(my_deck)
	# Auto-keep the drafted warband so it can be replayed later via Constructed →
	# LOAD without drafting again (the player asked for exactly this). Timestamped
	# name keeps each draft distinct; SavedDecks caps the list and drops the oldest.
	var stamp := Time.get_datetime_string_from_system().substr(5, 11).replace("T", " ")
	SavedDecks.save_deck("Draft %s" % stamp, my_deck)
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
	if not (_local_finished and _remote_finished):
		return
	# Both decks are committed to SkirmishState (local picks via _on_pick, the
	# opponent's via _store_opponent_deck). The host is authoritative for the
	# transition: launch_combat sets the skirmish mode on both sides and drops
	# both peers into combat.tscn together. The client does NOT change scene on
	# its own — it waits for the host's launch RPC (handled inside NetMatch).
	_show_marching_status()
	if NetMatch.is_host:
		NetMatch.launch_combat()


func _show_marching_status() -> void:
	_clear_card_row()
	if _reroll_btn != null:
		_reroll_btn.visible = false
	_header.text = "Both warbands drafted — marching to battle…"
	_header.add_theme_color_override("font_color", GREEN)
	_update_progress()


# ─────────────────────────────────────────────────────────────────────────
#  WAITING SCREEN
# ─────────────────────────────────────────────────────────────────────────

func _build_waiting_ui() -> void:
	_clear_card_row()
	if _reroll_btn != null:
		_reroll_btn.visible = false
	_header.text = "Warband sealed — 20 cards."
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
	_header.text = "Opponent disconnected."
	_header.add_theme_color_override("font_color", Color(0.90, 0.45, 0.35))
	_progress.text = ""
	var back := GameTheme.make_themed_button("BACK TO MENU",
		Color(0.26, 0.16, 0.14), Vector2(220, 44), 16)
	back.pressed.connect(func():
		NetMatch.leave()
		get_tree().change_scene_to_file(MENU_SCENE))
	_root.add_child(back)
