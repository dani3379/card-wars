extends Control
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
const MENU_SCENE := "res://scenes/main_menu.tscn"
# The combat scene is launched via NetMatch.launch_combat() (host-authoritative,
# both peers transition together) — this script never change_scenes into it.

const GILT_BRIGHT := Color(1.0, 0.85, 0.45, 1.0)
const IVORY := Color(0.96, 0.92, 0.78, 1.0)
const ASH := Color(0.62, 0.58, 0.52, 1.0)
const GREEN := Color(0.55, 0.85, 0.45, 1.0)

# ── Draft state ──
var _pool: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _target: int = 20   # set from SkirmishState.DECK_TARGET in _ready
var _picks_made: int = 0
var _remote_picks: int = 0
var _local_finished: bool = false
var _remote_finished: bool = false

# ── UI refs ──
var _root: VBoxContainer
var _header: Label
var _progress: Label
var _card_row: HBoxContainer


func _ready() -> void:
	GameTheme.add_atmosphere(self, "reward")

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
	for id in SkirmishState.skirmish_legal_pool():
		_pool.append(String(id))

	NetMatch.draft_event_received.connect(_on_draft_event)
	NetMatch.peer_left.connect(_on_peer_lost)
	NetMatch.host_closed.connect(_on_peer_lost)

	_build_scaffold()
	_present_triplet()


# ─────────────────────────────────────────────────────────────────────────
#  CARD POOL
# ─────────────────────────────────────────────────────────────────────────

func _roll_triplet() -> Array[String]:
	var out: Array[String] = []
	var guard := 0
	while out.size() < 3 and guard < 500 and _pool.size() > 0:
		guard += 1
		var id: String = _pool[_rng.randi() % _pool.size()]
		if not out.has(id):
			out.append(id)
	return out


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
		slot.add_child(card)

		var pick_btn := GameTheme.make_themed_button("CHOOSE",
			Color(0.18, 0.36, 0.18), Vector2(140, 38), 16)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick_btn.pressed.connect(_on_pick.bind(id))
		slot.add_child(pick_btn)

		_animate_card_reveal(card, pick_btn, idx)
		idx += 1


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
#  PICK / FINISH FLOW
# ─────────────────────────────────────────────────────────────────────────

func _on_pick(id: String) -> void:
	if _local_finished:
		return
	SkirmishState.add_card_to(SkirmishState.local_index, id)
	if AudioBank != null:
		AudioBank.play_sfx("card_play")
	_picks_made += 1
	NetMatch.send_draft_event({"t": "pick", "n": _picks_made})
	if _picks_made >= _target:
		_finish_draft()
	else:
		_present_triplet()


func _finish_draft() -> void:
	_local_finished = true
	var my_deck: Array = SkirmishState.local_slot().deck.duplicate()
	# Auto-keep the drafted warband so it can be replayed later via Constructed →
	# LOAD without drafting again (the player asked for exactly this). Timestamped
	# name keeps each draft distinct; SavedDecks caps the list and drops the oldest.
	var stamp := Time.get_datetime_string_from_system().substr(5, 11).replace("T", " ")
	SavedDecks.save_deck("Draft %s" % stamp, my_deck)
	NetMatch.send_draft_event({"t": "finished", "cards": my_deck})
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
	_header.text = "Both warbands drafted — marching to battle…"
	_header.add_theme_color_override("font_color", GREEN)
	_update_progress()


# ─────────────────────────────────────────────────────────────────────────
#  WAITING SCREEN
# ─────────────────────────────────────────────────────────────────────────

func _build_waiting_ui() -> void:
	_clear_card_row()
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
	_header.text = "Opponent disconnected."
	_header.add_theme_color_override("font_color", Color(0.90, 0.45, 0.35))
	_progress.text = ""
	var back := GameTheme.make_themed_button("BACK TO MENU",
		Color(0.26, 0.16, 0.14), Vector2(220, 44), 16)
	back.pressed.connect(func():
		NetMatch.leave()
		get_tree().change_scene_to_file(MENU_SCENE))
	_root.add_child(back)
