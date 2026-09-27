extends Node
## _probe_smear.gd — the gate for ▲2, the strike smear.
##
##   Godot.exe --path "D:\Godot" res://tools/_probe_smear.tscn
##   (WINDOWED — the smear gates itself off headless, having nothing to draw.)
##
## Four parts. Part B is the one that would have caught the pitch's own error.
##
##   A. IT EXISTS, AND IT IS GONE AGAIN. A smear that outlives the drive is not a
##      smear, it is a duplicate card standing on the board.
##   B. IT IS DRAWN WHERE THE BODY IS STILL MOVING. The drive is EXPO-out, which
##      front-loads distance on purpose, so "somewhere during the drive" is not
##      good enough — by the halfway point the body has covered 93% and stopped.
##      The pitch specified t −55 → −22 and that window is the SLOW TAIL. This
##      asserts the ghost is placed inside the span the body actually crosses
##      while fast, derived from the easing rather than from a remembered number.
##   C. IT IS A SMEAR, NOT A SECOND CARD. Elongated along travel, pinched across,
##      faint, and behind the body that threw it.
##   D. REDUCE MOTION DROPS IT, like the arc and roll it rides beside.

const EPS := 0.001

var _hits := 0
var _card: Control = null


func _ready() -> void:
	UserSettings.reduce_motion = false
	UserSettings.anim_speed = 1.0
	print("[smear] ▲2 — does the blow leave a speed line, and in the right place?\n")

	var CardScene = load("res://scenes/card_2d.tscn")
	# A plain Control host, NOT a container: the real board seats tokens in a
	# CenterContainer, and the ghost must not be able to perturb that — which is
	# why it is parented to the card with top_level rather than to the slot.
	var host := Control.new()
	host.size = Vector2(400, 400)
	host.position = Vector2(300, 200)
	add_child(host)

	# EVERYTHING BEFORE add_child. `_ready` builds the face from `card_data`, so
	# a probe that seats the data afterwards gets a card with no texture — and the
	# smear then correctly declines to draw, which reads as the feature being
	# broken. That cost one confident false failure.
	_card = CardScene.instantiate()
	_card.card_id = "troll"
	_card.card_data = CardDB.get_card_data("troll")
	if _card.card_data.is_empty():
		_fail("CardDB has no 'troll' — the probe is testing nothing")
		get_tree().quit(1)
		return
	_card.is_on_battlefield = true
	_card.compact_mode = true
	host.add_child(_card)
	_card.current_hp = int(_card.card_data.get("hp", 3))
	_card.current_atk = int(_card.card_data.get("atk", 2))
	_card.state.ready_to_swing = true
	_card.position = Vector2(80, 120)
	await get_tree().create_timer(1.6).timeout

	var rest: Vector2 = _card.position
	await _run_case(rest, 1.0, "strength 1.0")
	await _run_case(rest, 1.4, "heavy 1.4")

	# ── D: Reduce Motion ──────────────────────────────────────────────────
	print("\n  -- D, reduce motion --")
	UserSettings.reduce_motion = true
	_card.position = rest
	_card.play_attack_lunge(1.0)
	await get_tree().create_timer(Motion.LUNGE_ANTICIPATION + 0.05).timeout
	if _find_ghost() != null:
		_fail("Reduce Motion still draws a smear")
	else:
		print("  ok    Reduce Motion drops it")
	UserSettings.reduce_motion = false

	print("\n[smear] %s" % ("PASS" if _hits == 0 else "%d FAIL" % _hits))
	get_tree().quit(1 if _hits > 0 else 0)


func _fail(msg: String) -> void:
	_hits += 1
	print("  FAIL  %s" % msg)


## The sprite's y scale carries BOTH the supersampled-texture fit and the smear;
## this recovers the fit so the stretch can be judged on its own.
func fitted_y(g: Sprite2D) -> float:
	if g.texture == null or g.texture.get_size().y <= 0.0:
		return 1.0
	return _card.size.y / g.texture.get_size().y


func _find_ghost() -> Sprite2D:
	for ch in _card.get_children():
		if ch is Sprite2D and (ch as CanvasItem).top_level:
			return ch
	return null


func _run_case(rest: Vector2, strength: float, label: String) -> void:
	print("  -- %s --" % label)
	_card.position = rest
	_card.play_attack_lunge(strength)

	# Sample just after the drive begins — the window the smear claims.
	await get_tree().create_timer(Motion.LUNGE_ANTICIPATION + 0.012).timeout
	var g := _find_ghost()
	if g == null:
		# Say WHY. The smear declines when it has no face to copy, and a bare
		# "no smear" sends the reader to the wrong file.
		var cf = _card._compact_face
		var bf = _card._baked_face
		_fail("no smear during the drive (compact_face=%s tex=%s | baked_face=%s tex=%s)"
			% [str(cf != null), str(cf != null and cf.texture != null),
				str(bf != null), str(bf != null and bf.texture != null)])
		return
	# A centred Sprite2D is positioned by its middle.
	var gp: Vector2 = g.global_position
	var host_p: Vector2 = (_card.get_parent() as Control).global_position

	# ── B: is it inside the fast span? ────────────────────────────────────
	# Derived from the easing, not from a remembered t. EXPO-out covers
	# 1 − 2^(−10·p) of the distance by fraction p of the phase; the body is
	# "still fast" over roughly the first third, which ends at ~90% of reach.
	var dir := -1.0                                   # player token lunges up
	var back: float = -dir * 7.0
	var full: float = dir * 26.0 * strength
	var lo: float = minf(back, full * 0.92)
	var hi: float = maxf(back, full * 0.92)
	var local_y: float = gp.y - host_p.y - _card.size.y * 0.5
	var off: float = local_y - rest.y
	if off < lo - 2.0 or off > hi + 2.0:
		_fail("the smear sits at %+.1f px, outside the fast span [%+.1f, %+.1f]"
			% [off, lo, hi])
	else:
		print("  ok    placed at %+.1f px, inside the fast span [%+.1f, %+.1f]"
			% [off, lo, hi])
	# And it must be well short of full extension — that is the slow tail, where
	# the body has effectively stopped and a speed line is a lie.
	if absf(off) > absf(full) * 0.80:
		_fail("the smear is at %.0f%% of reach — that is the slow tail"
			% (absf(off) / absf(full) * 100.0))
	else:
		print("  ok    %.0f%% of reach — not the tail" % (absf(off) / absf(full) * 100.0))

	# ── C: shaped and weighted like a smear ───────────────────────────────
	# The sprite's scale carries the supersampled-texture fit as well as the smear,
	# so judge the RATIO between the axes, which is the smear alone.
	# The stretch is DERIVED from the travel, so the assertion derives it too — a
	# hardcoded expectation here would just restate the constant and would not
	# notice the smear becoming longer than the ground it claims to cover.
	var ratio: float = g.scale.y / maxf(g.scale.x, EPS)
	var travel: float = absf(full * 0.92 - back)
	var want: float = _card._smear_stretch(travel, _card.size.y) / _card.SMEAR_PINCH
	if ratio <= 1.0 + EPS:
		_fail("not elongated along travel (axis ratio %.2f)" % ratio)
	elif absf(ratio - want) > 0.05:
		_fail("axis ratio %.2f does not match the travel-derived %.2f" % [ratio, want])
	else:
		print("  ok    elongated %.2fx, derived from %.0f px of travel on a %.0f px body"
			% [ratio, travel, _card.size.y])
	# A smear must never be LONGER than the ground it covers, or there is no
	# motion to explain it and the eye files it as a second object.
	var physical: float = 1.0 + travel / _card.size.y
	if g.scale.y / maxf(fitted_y(g), EPS) > physical + 0.06:
		_fail("stretched %.2f past the physical %.2f — that is a duplicate, not a smear"
			% [g.scale.y / maxf(fitted_y(g), EPS), physical])
	else:
		print("  ok    within the physical span (%.2f)" % physical)
	# 0.30 was shot and read as a DOUBLED CARD: at that weight a full-art copy
	# resolves as an object instead of as motion. The ceiling is set below what
	# was seen to fail.
	if g.modulate.a > 0.22:
		_fail("too solid at alpha %.2f — a full-art copy resolves as a second card"
			% g.modulate.a)
	else:
		print("  ok    faint at alpha %.2f" % g.modulate.a)
	# It must NOT sink below the world. A negative z on a top_level node puts the
	# ghost under the table plate, where it renders nowhere — which is how this
	# first shipped, and only a screenshot caught it.
	if g.z_index < 0:
		_fail("z %d — a top_level ghost below zero renders under the board" % g.z_index)
	else:
		print("  ok    rides at the body's own depth (z %d)" % g.z_index)

	# ── A: gone before contact ────────────────────────────────────────────
	await get_tree().create_timer(Motion.LUNGE_STRIKE + 0.08).timeout
	if _find_ghost() != null:
		_fail("the smear outlived the drive — that is a duplicate card")
	else:
		print("  ok    gone before the blow lands")
	await get_tree().create_timer(0.35).timeout
