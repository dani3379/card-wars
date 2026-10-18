extends Control
## A restrained lane spotlight for solo clash resolution. The board outside the
## active column is inked down; a thin side-colored rule keeps the resolving
## lane readable without covering cards or adding another floating HUD widget.

var _focus_rect := Rect2()
var _strength := 0.0
var _accent := Color(0.92, 0.72, 0.28)
var _focus_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# MUST be set_anchors_AND_OFFSETS_preset (2026-07-29). `set_anchors_preset`
	# alone recomputes the OFFSETS to preserve the node's current rect — and at
	# `_ready` this node is already in the tree at 0x0, so it anchored itself to a
	# zero-size rect and stayed there. `_draw` then clamped every slab against
	# `size`, got x1 <= x0, and returned early on every single frame.
	#
	# This control had therefore NEVER DRAWN A PIXEL. `_strength` still tweened to
	# 1.0 and reported healthy to anything that asked, which is exactly why it went
	# unnoticed — including through a tuning pass that raised the surround ink from
	# 0.30 to 0.46 on a control that was rendering nothing at all.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func focus_lane(rect: Rect2, enemy_strike: bool) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	# THE SPOTLIGHT TRAVELS INSTEAD OF CUTTING (2026-07-30, STRIKE_DESIGN §5).
	#
	# This rect IS the camera — with no Camera2D in the game it is the only thing
	# on screen that says where to look. It used to be ASSIGNED outright, so the
	# serialized clash presented as eight hard cuts down the line and the eye had
	# to re-find the action at each one. Tweening it does three jobs at once: it
	# leads the eye with a saccade it can follow, it converts part of the lane
	# dwell from stillness into motion (the condemned 100-500ms band forbids EMPTY
	# windows, not occupied ones), and eight cuts become one sweep down the front.
	var prev: Rect2 = _focus_rect
	var travels: bool = prev.size.x > 0.0 and prev.size.y > 0.0 and _strength > 0.05
	_accent = Color(0.72, 0.20, 0.13) if enemy_strike \
		else Color(0.96, 0.76, 0.30)
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	# Informational: Reduce Motion gets the mark, just without the ramp. Snapping
	# to the end state is the house pattern for a cue that carries game state.
	if UserSettings != null and UserSettings.reduce_motion:
		_focus_rect = rect
		_set_strength(1.0)
		return
	var start := _strength
	_focus_tween = create_tween()
	if travels:
		var from_r: Rect2 = prev
		var to_r: Rect2 = rect
		_focus_tween.tween_method(func(t: float):
				_focus_rect = Rect2(from_r.position.lerp(to_r.position, t),
					from_r.size.lerp(to_r.size, t))
				queue_redraw(),
				0.0, 1.0, 0.14) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_focus_tween.parallel().tween_method(_set_strength, start, 1.0, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_focus_rect = rect
		_focus_tween.tween_method(_set_strength, start, 1.0, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func clear_focus() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	if _strength <= 0.001:
		_focus_rect = Rect2()
		queue_redraw()
		return
	_focus_tween = create_tween()
	_focus_tween.tween_method(_set_strength, _strength, 0.0, 0.16) \
		.set_ease(Tween.EASE_IN)
	_focus_tween.tween_callback(func():
		_focus_rect = Rect2()
		queue_redraw())


func _set_strength(value: float) -> void:
	_strength = value
	queue_redraw()


func _draw() -> void:
	if _strength <= 0.001 or _focus_rect.size.x <= 0.0:
		return
	var x0 := clampf(_focus_rect.position.x, 0.0, size.x)
	var y0 := clampf(_focus_rect.position.y, 0.0, size.y)
	var x1 := clampf(_focus_rect.end.x, 0.0, size.x)
	var y1 := clampf(_focus_rect.end.y, 0.0, size.y)
	if x1 <= x0 or y1 <= y0:
		return
	# BACK TO 0.30 (2026-07-29). It was raised to 0.46 on 2026-07-28 with the
	# rationale "at 30% the surround was suggestion, not direction" — but that
	# observation was impossible: the control was 0x0 and drew nothing at all (see
	# _ready). The evidence for the raise was void, so the raise is withdrawn rather
	# than replaced with a second guess.
	#
	# NOW THAT IT ACTUALLY RENDERS, THIS WANTS EYES — it is the one number in the
	# 2026-07-28 legibility pass never chosen with a human looking at it.
	#
	# Measured with tools/_probe_lane_focus.tscn (WINDOWED — it samples real pixels,
	# so it cannot run headless), as unfocused-band brightness / lit brightness:
	#     alpha 0.46  ->  0.486   (over half the light gone; reads as a blackout)
	#     alpha 0.30  ->  0.651   (shipped)
	#     alpha 0.00  ->  0.982   (what it measured while the control was 0x0 and
	#                              drawing nothing at all — the bug this replaced)
	# The values track `1 - alpha` closely, as they should: the ink is near-black,
	# so the surround is simply multiplied down.
	#
	# WHERE TO SAMPLE, if you re-measure: the ink draws on `board_zone`, a CHILD
	# canvas item — the hand and HUD sit on higher CanvasLayers and stay bright by
	# design. A full-screen luminance average will therefore under-report the effect.
	# Sample the board plate only, and entirely OUTSIDE the focus rect: `_draw` fills
	# four slabs around an untouched hole, so a band straddling the boundary averages
	# lit and inked pixels into a meaningless number.
	#
	# Tune this against a real fight, not against a probe.
	var ink := Color(0.018, 0.013, 0.010, 0.30 * _strength)
	# Four slabs leave the active column untouched instead of tinting the cards
	# inside it. The hand and HUD live on higher CanvasLayers and stay bright.
	if y0 > 0.0:
		draw_rect(Rect2(0.0, 0.0, size.x, y0), ink)
	if y1 < size.y:
		draw_rect(Rect2(0.0, y1, size.x, size.y - y1), ink)
	if x0 > 0.0:
		draw_rect(Rect2(0.0, y0, x0, y1 - y0), ink)
	if x1 < size.x:
		draw_rect(Rect2(x1, y0, size.x - x1, y1 - y0), ink)
	var edge := Color(_accent.r, _accent.g, _accent.b, 0.62 * _strength)
	draw_line(Vector2(x0, y0), Vector2(x0, y1), edge, 2.2, true)
	draw_line(Vector2(x1, y0), Vector2(x1, y1), edge, 2.2, true)
	# Short corner ticks read as a surveyor's bracket, matching the chart rather
	# than a modern rectangular selection glow.
	var tick := 13.0
	for yy in [y0, y1]:
		draw_line(Vector2(x0, yy), Vector2(x0 + tick, yy), edge, 2.2, true)
		draw_line(Vector2(x1 - tick, yy), Vector2(x1, yy), edge, 2.2, true)
