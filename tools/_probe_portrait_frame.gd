extends Node
## _probe_portrait_frame.gd — the hero plates' PORTRAIT FRAMING contract.
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_portrait_frame.tscn
##
## WHY THIS EXISTS, and why no gate already covered it (2026-09-17).
## `Combat._mount_portrait_art` replaced `STRETCH_KEEP_ASPECT_COVERED` on both
## hero plates, because that mode is CSS `object-fit: cover` with NO
## `object-position` — the crop is hardwired to CENTRE, and a centred cover crop
## took 125 source px off the player hero's crown and 160 off the foe's horns.
## The replacement does the cover arithmetic itself and pins the window to the
## TOP of the source, which is where these paintings keep their headroom.
##
## That swap moved two rects off ANCHORS and onto explicit size/position — the
## precise shape CLASS C32 exists to catch. `_probe_uiscale` cannot see it: that
## gate measures each SCREEN'S INK BOUNDING BOX, so it catches a layout pinned
## WHOLESALE and is blind to one plate inside a screen that is otherwise fine
## (its own header says so). So the framing is asserted here instead.
##
## IT PINS THE CONTRACT, NEVER THE NUMBERS. Nothing below hardcodes 210x222 or
## 236x232 — restating the plate constants in a probe is the duplicate-rule
## pathology this codebase has paid for repeatedly (NetPlayerState vs RelicDB).
## The claims are relations that must hold whatever anyone retunes the plates to:
## cover with no gap, aspect preserved, pinned top, centred horizontally — and
## every one of them IDENTICAL at UI Scale 1.0 and 0.6, which is the C32 half.

const SCALES: Array[float] = [1.0, 0.6]
const EPS := 0.75

var _fails: Array[String] = []
var _checks := 0


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)


func _ready() -> void:
	await get_tree().process_frame
	RunState.start_new_run("raider")
	RunState.current_node_type = "combat"
	# A PLAIN combat on purpose: that is the arm which lost its card-art
	# fallback, so it exercises the borrowed portrait as well as the framing.
	RunState.current_encounter_id = "borrowed_faces"
	await get_tree().process_frame

	var combat: Node = load("res://scenes/combat.tscn").instantiate()
	get_tree().root.add_child(combat)
	get_tree().current_scene = combat
	# The plates are built inside `_build_hud`, which is a coroutine that yields
	# between stages. Settle until BOTH rects exist and hold — a readiness flag
	# answers about the flag, never about the state it implies.
	var waited := 0.0
	while waited < 20.0:
		await get_tree().process_frame
		waited += 0.05
		if combat.get("_player_portrait_rect") != null \
				and combat.get("_enemy_portrait_rect") != null:
			break
	await get_tree().process_frame

	var root := get_tree().root
	var per_scale: Dictionary = {}
	for s in SCALES:
		root.content_scale_factor = s
		# Two frames: one for the resize to propagate, one to settle layout.
		await get_tree().process_frame
		await get_tree().process_frame
		per_scale[s] = {
			"player": _audit("player", combat.get("_player_portrait_rect"), s),
			"enemy": _audit("enemy", combat.get("_enemy_portrait_rect"), s),
		}
	root.content_scale_factor = 1.0

	# ── C32: the framing must be INVARIANT under UI Scale ──────────────────
	# The plates are corner-anchored at constant offsets, so their rects are
	# fixed logical px at any canvas size. If that ever stops being true this is
	# where it surfaces, rather than in a screenshot nobody re-reads.
	var base: Dictionary = per_scale[SCALES[0]]
	for i in range(1, SCALES.size()):
		var other: Dictionary = per_scale[SCALES[i]]
		for who in ["player", "enemy"]:
			var a: Dictionary = base[who]
			var b: Dictionary = other[who]
			if a.is_empty() or b.is_empty():
				continue
			_ok(a["box"].is_equal_approx(b["box"]),
				"%s: art box moves with UI Scale %.2f (%s vs %s)"
					% [who, SCALES[i], str(a["box"]), str(b["box"])])
			_ok(a["drawn"].is_equal_approx(b["drawn"]),
				"%s: drawn size moves with UI Scale %.2f (%s vs %s)"
					% [who, SCALES[i], str(a["drawn"]), str(b["drawn"])])
			_ok(a["pos"].is_equal_approx(b["pos"]),
				"%s: crop offset moves with UI Scale %.2f (%s vs %s)"
					% [who, SCALES[i], str(a["pos"]), str(b["pos"])])

	print("[portrait_frame] %d checks" % _checks)
	if _fails.is_empty():
		print("PROBE PASS: portrait_frame")
	else:
		for f in _fails:
			print("  FAIL ", f)
		print("PROBE FAIL: portrait_frame (%d)" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


## Returns the measured geometry, and asserts every framing claim that does not
## involve a second scale. Empty dict if the plate is missing entirely.
func _audit(who: String, rect: TextureRect, s: float) -> Dictionary:
	var tag := "%s @%.2f" % [who, s]
	_ok(rect != null and is_instance_valid(rect), "%s: no portrait rect" % tag)
	if rect == null or not is_instance_valid(rect):
		return {}
	var tex: Texture2D = rect.texture
	_ok(tex != null, "%s: portrait rect has no texture" % tag)
	if tex == null:
		return {}

	# EVERY plate must show a PORTRAIT-ORIENTATION painting. This is the half of
	# the fix that has nothing to do with cropping: the enemy plate used to fall
	# back to a creature's CARD art, which is 3:2 LANDSCAPE, and no amount of
	# focal-point maths rescues a wide painting in a tall window.
	_ok(tex.get_height() > tex.get_width(),
		"%s: source is not portrait-orientation (%dx%d) — a card painting has "
			% [tag, tex.get_width(), tex.get_height()]
			+ "leaked back into a hero plate")

	var clip := rect.get_parent() as Control
	_ok(clip != null and clip.clip_contents,
		"%s: portrait is not inside a clip_contents scissor" % tag)
	if clip == null:
		return {}
	var box: Vector2 = clip.size
	var drawn: Vector2 = rect.size
	var pos: Vector2 = rect.position

	_ok(box.x > 1.0 and box.y > 1.0, "%s: art box collapsed (%s)" % [tag, str(box)])

	# COVER — the drawn painting must reach both edges, or plate shows through.
	_ok(drawn.x >= box.x - EPS and drawn.y >= box.y - EPS,
		"%s: does not cover the box (drawn %s vs box %s)"
			% [tag, str(drawn), str(box)])

	# NO STRETCH — the whole complaint that started this was proportions.
	var src_ar := float(tex.get_width()) / float(maxi(tex.get_height(), 1))
	var drawn_ar := drawn.x / maxf(drawn.y, 1.0)
	_ok(absf(src_ar - drawn_ar) < 0.01,
		"%s: aspect distorted (source %.3f vs drawn %.3f)"
			% [tag, src_ar, drawn_ar])

	# PINNED TOP — the headroom claim. Source y 0 must be on screen, so the
	# crown/hood/horns survive; the loss is taken below the collarbone instead.
	_ok(absf(pos.y) < EPS,
		"%s: crop is not pinned to the top of the source (y=%.1f) — the head "
			% [tag, pos.y] + "is being cut by arithmetic again")

	# CENTRED HORIZONTALLY — the axis with no focal rule.
	var want_x: float = (box.x - drawn.x) * 0.5
	_ok(absf(pos.x - want_x) < EPS,
		"%s: horizontal crop off-centre (x=%.1f, want %.1f)"
			% [tag, pos.x, want_x])

	# NEVER a positive offset: that would be a gap with plate behind it.
	_ok(pos.x <= EPS and pos.y <= EPS,
		"%s: crop offset is positive (%s) — a gap is showing" % [tag, str(pos)])

	return {"box": box, "drawn": drawn, "pos": pos}
