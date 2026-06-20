extends SceneTree
## Modal-card combat coverage probe (2026-06-18). The autorun / balance / spell
## bots all SKIP cards whose on-play opens a picker (Discover / Choose-keyword /
## Copy) — those `await` a click and would stall a headless bot — so every one of
## those resolvers was unexercised in real combat. This boots real combat and
## drives each one: inject the card into hand, play it, and AUTO-DRIVE any picker
## that appears by emitting the first option's `pressed` signal. The discover /
## keyword-choice / copy / cast-random resolvers then run to completion and any
## crash surfaces as SCRIPT ERROR between the per-card markers.
##
## Covered (the handoff's untested-in-combat set):
##   familiar / scholar / treasure_hunter — Discover creature / spell / rare
##   lost_tome / war_council              — Discover (cast as a spell)
##   adaptable                            — Choose-keyword (4-button overlay)
##   copycat                              — Copy a friendly (auto-resolves at 1 cand)
##   doppelganger                         — Copy the last dead (reads death log)
##   chaos_imp                            — Cast a random spell free (may itself
##                                          roll a Discover -> driver handles it)
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_modal.gd

const TURN_WAIT_TICKS := 80
const TICK := 0.1
const DRIVE_FRAMES := 40        # frames to watch for / dismiss a picker per card

# Cards to exercise + the board state each one needs:
#   "" plain (just an empty slot), "friendly" needs one other friendly body so
#   copy_friendly auto-resolves, "dead" needs a corpse in the death log.
const MODAL_CARDS := [
	["familiar", ""], ["scholar", ""], ["treasure_hunter", ""],
	["lost_tome", "spell"], ["war_council", "spell"],
	["adaptable", ""], ["chaos_imp", ""],
	["copycat", "friendly"], ["doppelganger", "dead"],
]

var RS: Node
var CDB: Node
var EDB: Node
var US: Node
var SS: Node
var combat: Node
var _started := false
var _ok := 0
var _fail: Array = []
var _no_picker: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	print("[modal] start")
	RS = root.get_node_or_null("RunState")
	CDB = root.get_node_or_null("CardDB")
	EDB = root.get_node_or_null("EncounterDB")
	US = root.get_node_or_null("UserSettings")
	SS = root.get_node_or_null("SkirmishState")
	if RS == null or CDB == null or EDB == null:
		print("[modal] FATAL autoloads"); quit(1); return
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO

	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	var scene = load("res://scenes/combat.tscn")
	combat = scene.instantiate()
	root.add_child(combat)
	if not await _wait_for_player_turn():
		print("[modal] FATAL: never reached player turn"); quit(1); return

	for entry in MODAL_CARDS:
		await _exercise(String(entry[0]), String(entry[1]))

	print("[modal] ============ SUMMARY ============")
	print("[modal] resolved cleanly : %d / %d" % [_ok, MODAL_CARDS.size()])
	print("[modal] no picker opened : %s" % str(_no_picker))
	print("[modal] FAILED           : %s" % str(_fail))
	print("[modal] (scan log above for SCRIPT ERROR / Invalid call to attribute a crash)")
	print("[modal] DONE")
	quit(1 if _fail.size() > 0 else 0)


func _exercise(card_id: String, need: String) -> void:
	print("[modal] >>> %s (need=%s)" % [card_id, need])
	combat.player_mana = 9
	# Board prep.
	if need == "friendly":
		_clear_player_board()
		_place_friendly_dummy()
	else:
		_ensure_empty_slot()
	if need == "dead":
		# copy_last_dead reads _last_dead_copy_data() -> _last_dead_creature_id.
		combat._last_dead_creature_id = "brute"
		combat._last_dead_creature_uid = -999

	# Inject the card into hand using the game's own discovered-card path (fully
	# wires the node into _hand with the played/dragging signals).
	combat._add_discovered_card_to_hand(card_id)
	var card = combat._hand.back()
	if card == null or not is_instance_valid(card):
		_fail.append(card_id + ":inject"); return

	# Place a creature over an empty slot so the drag-play resolves into the board;
	# spells resolve from hand directly.
	if String(card.card_data.get("type", "")) == "creature":
		var slot = _find_empty_player_slot()
		if slot == null:
			_fail.append(card_id + ":no_slot"); return
		card.global_position = slot.global_position + slot.size * 0.5 - card.size * 0.5

	# Fire-and-forget the play (do NOT await — the on-play chain parks on the
	# picker's await; we drive it from here), then auto-dismiss any picker.
	combat._on_card_played(card)
	var driven := await _drive_pickers(DRIVE_FRAMES)
	if driven == 0:
		_no_picker.append(card_id)
	if combat.phase == combat.Phase.GAME_OVER:
		# Shouldn't happen mid-turn, but guard so one card can't abort the sweep.
		_fail.append(card_id + ":game_over"); return
	_ok += 1
	# Let any lingering tween/timer settle before the next card.
	await create_timer(0.05).timeout


## Watch up to `frames` process-frames; whenever a button-based modal overlay
## (z_index >= 200) is up, emit its first non-cancel button's `pressed`. Resets
## the idle counter after each press so chained pickers (e.g. chaos_imp -> a
## Discover) get driven too. Returns how many pickers it dismissed.
func _drive_pickers(frames: int) -> int:
	var driven := 0
	var idle := 0
	while idle < frames:
		await process_frame
		if not is_instance_valid(combat):
			break
		var btn := _find_modal_button()
		if btn != null:
			btn.pressed.emit()
			driven += 1
			idle = 0
		else:
			idle += 1
	return driven


## First clickable option in the topmost modal overlay, or null. A modal overlay
## is a ColorRect child of combat with z_index >= 200 (the discover / keyword /
## recycle pickers all use that). Prefers a non-CANCEL button.
func _find_modal_button() -> BaseButton:
	for child in combat.get_children():
		if child is ColorRect and child.z_index >= 200 and child.visible:
			var buttons: Array = []
			_collect_buttons(child, buttons)
			if buttons.is_empty():
				continue
			for b in buttons:
				if String(b.text).to_upper() not in ["CANCEL", "SKIP", "DONE"]:
					return b
			return buttons[0]
	return null


func _collect_buttons(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is BaseButton:
			out.append(c)
		if c.get_child_count() > 0:
			_collect_buttons(c, out)


func _place_friendly_dummy() -> void:
	# One friendly body so copy_friendly auto-resolves at a single candidate.
	if combat._row_array(false, combat.ROW_FRONT)[0] == null:
		combat.summon_token(2, 5, 0, false, combat.ROW_FRONT)


func _ensure_empty_slot() -> void:
	if _find_empty_player_slot() == null:
		_clear_player_board()


func _clear_player_board() -> void:
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		var arr: Array = combat._row_array(false, row)
		for lane in range(combat.LANES_PER_ROW):
			var c = arr[lane]
			if c != null and is_instance_valid(c):
				arr[lane] = null
				c.queue_free()


func _find_empty_player_slot():
	for row in [combat.ROW_FRONT, combat.ROW_BACK]:
		for lane in range(combat.LANES_PER_ROW):
			if combat._row_array(false, row)[lane] == null:
				return combat._slot_array(false, row)[lane]
	return null


func _wait_for_player_turn() -> bool:
	var waited := 0
	while waited < TURN_WAIT_TICKS:
		if not is_instance_valid(combat): return false
		if combat.phase == combat.Phase.GAME_OVER: return true
		if combat.phase == combat.Phase.PLAYER_TURN: return true
		await create_timer(TICK).timeout
		waited += 1
	return false
