extends Node
## _shot_hand_fan.gd — the hand's RESTING read, at every size it actually reaches.
##
##   Godot.exe --path "D:\Godot" res://tools/_shot_hand_fan.tscn
##
## WHY THIS EXISTS. Every number in Combat._layout_hand is a claim about a
## silhouette — how much a wing leans, how deep the arc sags, how much of a card
## the next one covers — and not one of them is checkable by reading the code. The
## two defects that produced this harness were both invisible to every gate in the
## project and obvious in one frame:
##   · the playable affordance (a 16 px lift + a 1.06 grow) was LARGER than the
##     whole arc it perturbed, so the fan's line came out a cost-keyed sawtooth;
##   · past six cards the spacing went on tightening while the fan angle and the
##     arc had both hit their own separate ceilings, so a full hand stopped being
##     a fan and became a flat pile.
##
## It shoots the hand at 2 / 4 / 6 / 8 / 10 cards with the Command pool set so the
## hand is deliberately MIXED — some payable, some not — because a cue that only
## ever fires on every card or no card cannot be judged. Each size is saved whole
## and again as a tight crop of the hand band, since the things under test are a
## few pixels of lean and a bloom on a card's top edge, neither of which is
## decidable at 1600×900 (the house rule from _shot_coach_devices).
##
## Then the HOVER pair, which is the one claim a still of a resting hand cannot
## make: the wing card and the centre card are hovered in turn and the harness
## PRINTS the y they each land on. The fan rides a circle, so those two rest up to
## ~26 px apart; if the two hovered y's differ by more than a pixel or two, the
## hover is lifting from where the card sits instead of from the fan's crest, and
## sweeping the hand will look like the fan bobbing.

const SIZES := [2, 4, 6, 8, 10]
## Mid-pool Command: cheap cards light, dear ones stay dim. A full pool would make
## every card payable and photograph nothing.
const POOL := 2
const SETTLE := 1.5
## The hand band, in canvas pixels — container top (690) up a little for the
## hovered pose, down to the screen edge.
const BAND := Rect2i(300, 590, 1060, 310)

var _combat: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()

	# A windowed harness sits in the real desktop session, so the coach's scrim
	# and the end-turn confirm can and do land on top of the thing being shot.
	if UserSettings != null:
		UserSettings.end_turn_warning = false
		UserSettings.coaching_mode = TutorialDB.COACH_OFF

	# SEEDED. An unseeded run deals a different hand every time, so two runs of
	# this harness are not comparable — which matters most for the hover pair,
	# where the whole output is a difference between two cards.
	RunState.start_new_run("raider", -1, 20260917)
	RunState.current_node_type = "combat"
	RunState.current_encounter_id = "bandit_camp"
	await get_tree().process_frame

	_combat = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(_combat)
	get_tree().current_scene = _combat
	await _await_hand()

	for n in SIZES:
		await _set_hand_size(int(n))
		await get_tree().create_timer(SETTLE).timeout
		var frame: Image = await _shoot("fan_%02d" % int(n))
		_report(int(n), frame)

	# ── the hover pair ────────────────────────────────────────────────────────
	await _set_hand_size(8)
	await get_tree().create_timer(SETTLE).timeout
	var wing_y := await _hover_shot(0, "hover_wing")
	var mid_y := await _hover_shot(4, "hover_mid")
	print("HOVER wing_y=%.1f  mid_y=%.1f  delta=%.1f  (want |delta| < 3 — these two"
		% [wing_y, mid_y, absf(wing_y - mid_y)]
		+ " rest ~30px apart, so an uncancelled arc reads here as ~30)")

	print("SHOTS_DONE")
	get_tree().quit()


func _await_hand() -> void:
	var guard := 0
	while guard < 400:
		guard += 1
		await get_tree().process_frame
		if _combat._hand.size() > 0 and _combat.round_number >= 1:
			break
	# _start_round STAGGERS the deal on timers, so the first card arriving is not
	# the hand arriving — poll until the count HOLDS (the house readiness rule).
	var last := -1
	var stable := 0
	guard = 0
	while stable < 12 and guard < 400:
		guard += 1
		await get_tree().process_frame
		var cur: int = _combat._hand.size()
		stable = stable + 1 if cur == last else 0
		last = cur


## Drive the real hand to exactly `n` cards through the real entry points.
##
## A SHED CARD GOES TO THE DISCARD, and that is not tidiness — `draw_one` gives up
## when BOTH piles are empty, so a harness that frees cards without returning them
## drains a ten-card hero deck and silently stops. The first run of this file did
## exactly that: it reported "n=8" and "n=10" over the same SEVEN cards, and the
## two sizes the harness exists to photograph were the two it never reached.
func _set_hand_size(n: int) -> void:
	while _combat._hand.size() > n:
		var card = _combat._hand.pop_back()
		if card != null and is_instance_valid(card):
			_combat._player_discard_pile.append(
				_combat._pile_entry(card.card_id, card.deck_uid))
			card.queue_free()
		await get_tree().process_frame
	var guard := 0
	while _combat._hand.size() < n and guard < 60:
		guard += 1
		var before: int = _combat._hand.size()
		_combat.draw_one()
		await get_tree().process_frame
		await get_tree().process_frame
		if _combat._hand.size() == before:
			push_error("_set_hand_size stalled at %d of %d — both piles dry"
				% [before, n])
			break
	_combat.player_mana = POOL
	_combat.player_max_mana = maxi(_combat.player_max_mana, POOL)
	_combat._update_hud()
	_combat._layout_hand()
	await get_tree().process_frame


## THE FRAMEBUFFER IS NOT THE CANVAS. `get_viewport().get_texture()` is the
## WINDOW's size, and under `canvas_items` stretch the window is whatever the
## desktop gave us — this box hands back 1920×1080 for a requested 1600×900. The
## first cut of this harness cropped BAND in canvas pixels and photographed the
## empty board two rows above the hand, i.e. it shot a perfectly good frame of the
## wrong part of the screen. Derive the factor from the image itself.
func _shoot(tag: String) -> Image:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("res://tools/screenshot/_hand_%s.png" % tag)
	var k: float = float(img.get_height()) / 900.0
	var band_px := Rect2i(
		Vector2i(int(BAND.position.x * k), int(BAND.position.y * k)),
		Vector2i(int(BAND.size.x * k), int(BAND.size.y * k)))
	band_px = band_px.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var band: Image = img.get_region(band_px)
	# 2x nearest so a 2 px lean and the crown's falloff are actually decidable.
	band.resize(int(band.get_width() * 1.4), int(band.get_height() * 1.4),
		Image.INTERPOLATE_NEAREST)
	band.save_png("res://tools/screenshot/_hand_%s_zoom.png" % tag)
	print("SAVED _hand_%s.png (+zoom, frame %dx%d)"
		% [tag, img.get_width(), img.get_height()])
	return img


## ── THE CROWN IS READ OFF THE FRAMEBUFFER, NOT OFF THE NODE ─────────────────
## `_playable_glow.modulate.a` only proves the node was told to be lit. Whether
## any warmth actually reaches the table above the card is a question about
## pixels, and it is the question the first cut got wrong in BOTH directions at
## once — invisible on a two-card hand and a solid fog bank on a six-card one.
## So the report samples a few pixels above each card's top edge, along the
## card's OWN up-vector (the wings are rotated ~11°, so screen-up is not card-up),
## and prints the value. A lit card must read materially warmer than an unlit one;
## if lit and unlit sample the same, the cue is not on screen whatever the node
## says.
func _report(n: int, img: Image) -> void:
	var k: float = float(img.get_height()) / 900.0
	var line := "n=%d " % n
	for card in _combat._hand:
		if card == null or not is_instance_valid(card):
			continue
		var lit := "·"
		if card._playable_glow != null and is_instance_valid(card._playable_glow):
			lit = "*" if card._playable_glow.modulate.a > 0.5 else "·"
		# get_global_transform() carries the bottom-centre pivot, the rest scale
		# and the fan angle, so card-local coordinates map straight to the screen.
		#
		# SAMPLE THE LEFT QUARTER, not the centre: at a ten-card hand the next card
		# covers ~50% of this one, so top-centre sits right on the seam. The left
		# quarter of the top edge is visible at every hand size.
		var xf: Transform2D = card.get_global_transform()
		var probe: Vector2 = (xf * Vector2(Card2D.CARD_W * 0.25,
			Card2D.PLAYABLE_EDGE_INSET + Card2D.PLAYABLE_EDGE_WIDTH * 0.5)) * k
		var v := 0.0
		var px := Vector2i(int(probe.x), int(probe.y))
		if px.x >= 0 and px.y >= 0 and px.x < img.get_width() \
				and px.y < img.get_height():
			var c: Color = img.get_pixelv(px)
			v = c.r * 0.5 + c.g * 0.4 + c.b * 0.1
		line += "[%s y%.0f r%+.1f° s%.2f L%.2f] " % [lit,
			card._hand_target_position.y, rad_to_deg(card._hand_target_rotation),
			card.scale.x, v]
	print(line)


## Hover one card and report the screen y its TOP edge lands on. Returns the y so
## the caller can diff the wing against the centre.
func _hover_shot(idx: int, tag: String) -> float:
	if idx >= _combat._hand.size():
		return 0.0
	var card = _combat._hand[idx]
	# A MARKED CARD SITS 20 px OUT OF THE FAN ON PURPOSE, and that offset is NOT
	# part of the arc the hover cancels — so a marked card legitimately hovers
	# low and would read here as a broken sag cancellation. Clear it rather than
	# exempt it: a windowed harness sits in the live desktop session and a stray
	# right-click anywhere in the window marks whatever is under it. (That is what
	# a 20.0 px delta on one run of this file turned out to be.)
	if card.marked_for_discard:
		_combat._on_card_dismiss_requested(card)
		await get_tree().create_timer(0.3).timeout
	card._on_mouse_entered()
	await get_tree().create_timer(0.6).timeout
	var _frame: Image = await _shoot(tag)
	# Bottom-centre pivot: the card's foot is position + (W/2, H) and its painted
	# top edge is that foot minus the RENDERED height.
	# MEASURE THE POSE, NOT A QUANTITY DERIVED FROM IT. The first cut returned the
	# painted top edge (foot − CARD_H × scale.y), which folds in the hover's SCALE
	# tween — and the two cards are sampled at different moments of their own
	# tweens, so it reported a 13.6 px disagreement over two cards sitting at a
	# byte-identical y. The sag cancellation is a claim about POSITION; that is
	# what the oracle reads, and the scale is printed beside it as context.
	print("  hover[%d] sag=%.1f rest_y=%.1f now_y=%.1f scale=%.3f marked=%s"
		% [idx, card._hand_arc_sag, card._hand_target_position.y,
		card.position.y, card.scale.y, str(card.marked_for_discard)])
	var top_y: float = card.position.y
	card._on_mouse_exited()
	await get_tree().create_timer(0.4).timeout
	return top_y
