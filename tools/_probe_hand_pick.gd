extends SceneTree
## _probe_hand_pick — can every card in the hand actually be picked up?
##
## THE QUESTION. `_layout_hand` fans the hand on one circle and clamps the
## centre-to-centre SPREAD down as the hand grows, while the cards keep their
## own width. Past the point where spread < half a card width, a card's own
## GEOMETRIC CENTRE is covered by the neighbour drawn after it — and Godot picks
## by tree order, so the click lands on the neighbour.
##
## WHY NO EXISTING GATE SEES THIS. `_probe_input_reach` (C29) re-implements the
## picking rule statically over a settled screen, and `_probe_occlusion` looks
## for one control painted over another. Neither asks the question a player asks,
## which is "if I point at this card, do I get this card". The input pilot found
## it live (three OCCLUDED findings in one windowed run, all in Combat's hand,
## all naming the same occluding neighbour) — this is the cheap, deterministic
## restatement of that finding so it can be tracked per hand size.
##
## THE ORACLE IS THE ENGINE'S OWN PICKER, never geometry re-derived here:
## `Viewport.gui_get_hovered_control()` at the card's centre must resolve to that
## card (or a descendant of it). Re-deriving the rule would only prove this file
## agrees with itself.
##
## REPORT, NOT A GATE. Overlap is intended — every card game fans its hand, and
## the card a player actually points at is the VISIBLE sliver, not the geometric
## middle. What this measures is how much of each card is its own, and at which
## hand size the middle stops belonging to it. Read the numbers and decide.

const TICK := 0.1
const WAIT_TICKS := 90

var combat: Node
var _started := false
var _rows: Array = []


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _boot() -> bool:
	var RS = root.get_node_or_null("RunState")
	var US = root.get_node_or_null("UserSettings")
	var SS = root.get_node_or_null("SkirmishState")
	if RS == null:
		print("[handpick] FATAL: no RunState")
		return false
	if US != null:
		US.anim_speed = 3.0
		US.end_turn_warning = false
		US.reduce_motion = true   # park the fan at its RESTING pose
	if SS != null:
		SS.combat_mode = SS.CombatMode.SOLO
	RS.start_new_run("raider", 0, 4242)
	RS.current_encounter_id = "goblin_scouts"
	RS.current_node_type = "combat"
	combat = load("res://scenes/combat.tscn").instantiate()
	root.add_child(combat)
	var waited := 0
	while waited < WAIT_TICKS:
		if not is_instance_valid(combat):
			return false
		if combat.phase == combat.Phase.PLAYER_TURN and combat.round_number >= 1:
			break
		await create_timer(TICK).timeout
		waited += 1
	return is_instance_valid(combat)


## The hand deals one card at a time, so a size read mid-deal is a lie. Poll
## until the count HOLDS (the house `reference_settle_until_stable` rule).
func _settle_hand() -> int:
	var last := -1
	var stable := 0
	for _i in range(80):
		await create_timer(0.05).timeout
		if not is_instance_valid(combat):
			return 0
		var nn: int = combat._hand.size()
		if nn == last:
			stable += 1
			if stable >= 4:
				return nn
		else:
			stable = 0
			last = nn
	return last


func _owns(node, card) -> bool:
	var n = node
	while n != null:
		if n == card:
			return true
		n = n.get_parent()
	return false


func _measure(n_target: int) -> void:
	# Top the hand up to the requested size.
	var guard := 0
	while combat._hand.size() < n_target and guard < 40:
		combat.draw_one()
		guard += 1
		await create_timer(0.03).timeout
	await _settle_hand()
	await create_timer(0.25).timeout   # let the fan reach its resting pose

	var hand: Array = combat._hand.duplicate()
	var n := hand.size()
	if n == 0:
		return
	var vp := combat.get_viewport()
	var covered: Array = []
	for card in hand:
		if not is_instance_valid(card):
			continue
		# THE CENTRE MUST COME OFF THE TRANSFORM, not off position+size*scale.
		# The fan ROTATES every card about its own pivot_offset, and an
		# axis-aligned `position + size*scale*0.5` is not the visual middle of a
		# rotated control — on the wings it is tens of pixels out, which would
		# manufacture exactly the finding this probe exists to test.
		var centre: Vector2 = card.get_global_transform() * (card.size * 0.5)
		vp.warp_mouse(centre)
		await create_timer(0.02).timeout
		var hit = vp.gui_get_hovered_control()
		if hit == null or not _owns(hit, card):
			covered.append(String(card.card_data.get("name", "?")))

	# Report the geometry alongside, so a reader can see WHY.
	var w: float = 0.0
	var pitch: float = 0.0
	if n > 0:
		w = hand[0].size.x * hand[0].scale.x
	if n > 1:
		pitch = absf(hand[1].global_position.x - hand[0].global_position.x)
	var ov := 0.0
	if w > 0.0 and pitch > 0.0:
		ov = clampf((w - pitch) / w, 0.0, 1.0)
	_rows.append({
		"n": n, "w": w, "pitch": pitch, "overlap": ov,
		"covered": covered.size(), "names": covered,
	})
	print("  hand %2d: card_w %6.1f  pitch %6.1f  overlap %3.0f%%  "
		% [n, w, pitch, ov * 100.0]
		+ "centre-unreachable %d/%d %s"
		% [covered.size(), n, str(covered) if covered.size() > 0 else ""])


func _run() -> void:
	print("\n[handpick] can each hand card be picked up at its own centre?\n")
	if not await _boot():
		print("[handpick] FATAL: combat never reached a player turn")
		quit(1)
		return
	print("  oracle = Viewport.gui_get_hovered_control() at each card's centre\n")
	for target in [3, 5, 6, 7, 8, 9, 10]:
		await _measure(target)

	var worst := 0
	for r in _rows:
		worst = maxi(worst, int(r["covered"]))
	print("\n[handpick] %d hand size(s) measured" % _rows.size())
	if worst == 0:
		print("[handpick] every card answers its own centre at every size")
	else:
		print("[handpick] %d card(s) at the worst size cannot be picked up at"
			% worst)
		print("[handpick] their own centre — the click lands on a neighbour.")
		print("[handpick] REPORT, not a failure: overlap is intended. The")
		print("[handpick] question is whether the sliver a player CAN point at")
		print("[handpick] is big enough, which is a design call.")
	quit(0)
