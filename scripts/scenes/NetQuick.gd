extends Control
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

const MENU_SCENE := "res://scenes/main_menu.tscn"

# Max duplicate copies of the same id allowed in the generated deck.
const MAX_COPIES: int = 2

# Card-thumbnail scale for the warband preview (matches Constructed / Sealed).
const THUMB_SCALE: float = 0.46

const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
const GREEN := Color(0.55, 0.85, 0.45, 1.0)
const RED_WARN := Color(0.90, 0.45, 0.35, 1.0)
const HOST_BLUE := Color(0.45, 0.70, 1.0, 1.0)

# ── Deck generation state ──
var _pool: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _mirror: bool = true
var _sub_seed: int = 0      # host-chosen; 0 means unset (use base seed)
var _local_deck: Array[String] = []
var _target: int = 20   # SkirmishState.DECK_TARGET

# ── Handoff state (mirrors NetDraft) ──
var _local_finished: bool = false
var _remote_finished: bool = false
var _local_ready: bool = false
var _remote_ready: bool = false

# ── UI refs ──
var _root: VBoxContainer
var _header: Label
var _status: Label
var _deck_box: HFlowContainer
# Bumped each preview rebuild; the async bake loop checks it after every await so a
# Reroll / Mirror / cfg change that fires mid-build abandons the stale stream.
var _deck_gen: int = 0
var _reroll_btn: Button
var _ready_btn: Button
var _mirror_btn: Button


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")

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

	_build_scaffold()

	if NetMatch.is_host:
		# Host decides the initial cfg and broadcasts it so the client's first
		# generation matches. sub_seed 0 → use base rng_seed unchanged.
		_sub_seed = 0
		_broadcast_cfg()
	# Host generates immediately (client regenerates when cfg arrives).
	_regenerate_deck()
	_refresh_deck_ui()
	_update_status()


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
	_local_deck.clear()
	var counts: Dictionary = {}
	var guard := 0
	while _local_deck.size() < _target and guard < 2000:
		guard += 1
		if _pool.is_empty():
			break
		var id: String = _pool[_rng.randi() % _pool.size()]
		var cnt: int = int(counts.get(id, 0))
		if cnt < MAX_COPIES:
			_local_deck.append(id)
			counts[id] = cnt + 1


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

	_header = GameTheme.make_label("Your warband — random 20 cards.", 18, IVORY)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_header)

	# Deck preview — real card art (wrapping grid of thumbnails), matching the
	# Constructed / Sealed builders rather than a text list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	_deck_box = HFlowContainer.new()
	_deck_box.add_theme_constant_override("h_separation", 8)
	_deck_box.add_theme_constant_override("v_separation", 8)
	_deck_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_deck_box)

	_root.add_child(GameTheme.make_separator(Color(GILT_BRIGHT.r, GILT_BRIGHT.g, GILT_BRIGHT.b, 0.35), 400.0))

	# Bottom controls row
	var ctrl_row := HBoxContainer.new()
	ctrl_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_row.add_theme_constant_override("separation", 20)
	_root.add_child(ctrl_row)

	if NetMatch.is_host:
		_mirror_btn = GameTheme.make_themed_button("Mirrored",
			Color(0.15, 0.25, 0.40), Vector2(140, 38), 15)
		_mirror_btn.pressed.connect(_on_toggle_mirror)
		ctrl_row.add_child(_mirror_btn)

		_reroll_btn = GameTheme.make_themed_button("REROLL",
			Color(0.28, 0.20, 0.10), Vector2(130, 38), 15)
		_reroll_btn.pressed.connect(_on_reroll)
		ctrl_row.add_child(_reroll_btn)

	_ready_btn = GameTheme.make_themed_button("READY",
		Color(0.18, 0.36, 0.18), Vector2(160, 44), 17)
	_ready_btn.pressed.connect(_on_ready_pressed)
	ctrl_row.add_child(_ready_btn)

	_status = GameTheme.make_label("", 14, ASH)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)


func _refresh_deck_ui() -> void:
	if _deck_box == null:
		return
	_deck_gen += 1
	var gen := _deck_gen
	for c in _deck_box.get_children():
		c.queue_free()

	# Group the random warband by id and show each as real card art with a ×N
	# badge, sorted by cost then name. No click: the deck is fixed — you Reroll it,
	# you don't edit it — so the thumbnails are a read-only preview.
	var counts: Dictionary = {}
	var order: Array[String] = []
	for id in _local_deck:
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	order.sort_custom(func(a: String, b: String) -> bool:
		var ca := int(CardDB.get_card_data(a).get("cost", 0))
		var cb := int(CardDB.get_card_data(b).get("cost", 0))
		if ca != cb:
			return ca < cb
		return String(CardDB.get_card_data(a).get("name", a)) < String(CardDB.get_card_data(b).get("name", b)))

	# Bake-then-add (Collection pattern): warm each card's texture before its thumb
	# so the Card2D builds the cheap baked overlay; a warm-cache Reroll fills instantly.
	for id in order:
		if gen != _deck_gen or not is_instance_valid(_deck_box):
			return
		await CardTextureCache.bake(CardDB.get_card_data(id))
		if gen != _deck_gen or not is_instance_valid(_deck_box):
			return
		var n := int(counts[id])
		var d := CardDB.get_card_data(id)
		var thumb := GameTheme.make_card_thumb(d, THUMB_SCALE)
		var badge := thumb["badge"] as Label
		badge.text = "×%d" % n
		badge.visible = n > 1
		(thumb["button"] as Button).tooltip_text = String(d.get("name", id))   # hover-name; no add/remove
		_deck_box.add_child(thumb["root"])


func _update_status() -> void:
	if _status == null:
		return
	var mode_str: String = "Mirrored" if _mirror else "Random"
	var you_str: String = "READY" if _local_ready else "waiting"
	var opp_str: String = "READY" if _remote_ready else "waiting"
	_status.text = "[%s]  You: %s   ·   Opponent: %s" % [mode_str, you_str, opp_str]

	if _local_ready and _remote_ready:
		_status.add_theme_color_override("font_color", GREEN)
	elif _local_ready:
		_status.add_theme_color_override("font_color", HOST_BLUE)
	else:
		_status.add_theme_color_override("font_color", ASH)


# ─────────────────────────────────────────────────────────────────────────
#  HOST CONTROLS
# ─────────────────────────────────────────────────────────────────────────

func _on_toggle_mirror() -> void:
	if not NetMatch.is_host:
		return
	_mirror = not _mirror
	if _mirror_btn != null:
		_mirror_btn.text = "Mirrored" if _mirror else "Random"
	_regenerate_deck()
	_refresh_deck_ui()
	_update_status()
	_broadcast_cfg()


func _on_reroll() -> void:
	if not NetMatch.is_host:
		return
	_sub_seed = randi()
	_regenerate_deck()
	_refresh_deck_ui()
	_update_status()
	_broadcast_cfg()


func _broadcast_cfg() -> void:
	NetMatch.send_draft_event({
		"t": "cfg",
		"mirror": _mirror,
		"seed": _sub_seed,
	})


# ─────────────────────────────────────────────────────────────────────────
#  READY / HANDOFF FLOW  (mirrors NetDraft finish tail)
# ─────────────────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	if _local_ready or _local_finished:
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
	NetMatch.send_draft_event({"t": "finished", "cards": my_deck})
	_show_marching()
	_maybe_begin_combat()


func _on_draft_event(event: Dictionary) -> void:
	match String(event.get("t", "")):
		"cfg":
			# Client applies the host's config (host ignores its own echo).
			if not NetMatch.is_host:
				_mirror = bool(event.get("mirror", true))
				_sub_seed = int(event.get("seed", 0))
				if _mirror_btn != null:
					_mirror_btn.text = "Mirrored" if _mirror else "Random"
				_regenerate_deck()
				_refresh_deck_ui()
				_update_status()
		"ready":
			_remote_ready = true
			_update_status()
			_maybe_fight()
		"finished":
			_remote_finished = true
			_store_opponent_deck(event.get("cards", []))
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
	if not (_local_finished and _remote_finished):
		return
	_show_marching()
	if NetMatch.is_host:
		NetMatch.launch_combat()


# ─────────────────────────────────────────────────────────────────────────
#  STATUS SCREENS
# ─────────────────────────────────────────────────────────────────────────

func _show_marching() -> void:
	if _header == null:
		return
	_header.text = "Both warbands ready — marching to battle…"
	_header.add_theme_color_override("font_color", GREEN)


## Mirrors NetDraft — disconnect handler.
func _on_peer_lost(_id: int = 0) -> void:
	if _root == null:
		return
	for c in _deck_box.get_children():
		c.queue_free()
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
