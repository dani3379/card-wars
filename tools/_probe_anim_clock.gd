extends SceneTree
## Animation-clock probe (2026-07-16 — R1+R2 of docs/ANIMATION_AUDIT_20260716.md).
##
## R1 (one clock): Combat's pacing constants must EQUAL the Motion clock's —
## the conductor's awaits and Card2D's lunge/recoil tweens read the same
## numbers — and LUNGE_APEX must be derived (anticipation + strike), so the
## impact beat lands exactly at the lunge tween's full extension. Motion.time()
## must scale by UserSettings.anim_speed exactly like Combat._short_pause.
##
## R2 (trauma shake): impulses compound and clamp at 1; the shaken property
## moves while trauma is live and is restored EXACTLY to its rest value when
## trauma decays out; a freed target releases safely; the Screen Shake setting
## gates new impulses.
##
## Run: Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_anim_clock.gd
## Grep for "ALL PASS" — don't trust the exit code alone.

var _ran := false
var _fails := 0
# ★8 hold test runs across real frames (a timer must fire and a tween resume),
# so the probe gets a second phase with a hard frame guard — every path quits.
var _hold_card: Control = null
var _hold_frames := 0
var _hold_rest := Vector2.ZERO
var _hold_released := false
var _us_ref: Node = null
var _old_rm_hold := false


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[anim_clock] PASS  ", label)
	else:
		_fails += 1
		print("[anim_clock] FAIL  ", label, ("  — " + detail) if detail != "" else "")


func _process(_delta: float) -> bool:
	if _ran:
		return _tick_hold_test()
	_ran = true

	var us: Node = root.get_node_or_null("UserSettings")
	var theme: Node = root.get_node_or_null("GameTheme")
	if us == null or theme == null:
		print("[anim_clock] FATAL: autoloads missing (UserSettings/GameTheme)")
		return true

	# ── R1: one clock ──────────────────────────────────────────────────
	var motion := load("res://scripts/ui/Motion.gd")
	var combat_consts: Dictionary = \
		load("res://scripts/scenes/Combat.gd").get_script_constant_map()
	_check("LUNGE_APEX derived from tween phases",
		is_equal_approx(motion.LUNGE_APEX,
			motion.LUNGE_ANTICIPATION + motion.LUNGE_STRIKE))
	for pair in [["LUNGE_APEX", motion.LUNGE_APEX],
			["POST_HIT_BEAT", motion.POST_HIT_BEAT],
			["HITSTOP_BEAT", motion.HITSTOP_BEAT]]:
		_check("Combat.%s == Motion.%s" % [pair[0], pair[0]],
			combat_consts.has(pair[0]) \
				and is_equal_approx(float(combat_consts[pair[0]]), float(pair[1])),
			"Combat=%s Motion=%s" % [combat_consts.get(pair[0]), pair[1]])

	var old_speed: float = us.anim_speed
	us.anim_speed = 1.0
	_check("Motion.time passthrough at speed 1.0",
		is_equal_approx(motion.time(0.4), 0.4))
	us.anim_speed = 2.0
	_check("Motion.time halves at speed 2.0",
		is_equal_approx(motion.time(0.4), 0.2))
	us.anim_speed = 3.0
	_check("Motion.time thirds at speed 3.0 (Instant)",
		is_equal_approx(motion.time(0.3), 0.1))
	us.anim_speed = old_speed  # direct restore, never saved

	# ── R2: trauma shake ───────────────────────────────────────────────
	var old_shake: bool = us.screen_shake
	us.screen_shake = true

	var node := Node2D.new()
	node.position = Vector2(37.0, 11.0)
	root.add_child(node)
	var rest: Vector2 = node.position

	theme.set_shake_target(node)
	theme.add_trauma(0.4)
	theme.add_trauma(0.4)
	_check("impulses compound (0.4 + 0.4 = 0.8)",
		is_equal_approx(theme._shake_trauma, 0.8),
		"trauma=%s" % theme._shake_trauma)
	theme.add_trauma(5.0)
	_check("trauma clamps at 1.0", is_equal_approx(theme._shake_trauma, 1.0))
	theme.set_shake_target(node)  # idempotent — must NOT reset the live shake
	_check("re-registering the same target keeps trauma",
		is_equal_approx(theme._shake_trauma, 1.0))

	# Drive the decay by hand and watch the node actually move.
	var moved := false
	var guard := 0
	while theme._shake_trauma > 0.0 and guard < 1000:
		theme._process(1.0 / 60.0)
		if node.position.distance_to(rest) > 0.5:
			moved = true
		guard += 1
	_check("target visibly displaced during the shake", moved)
	_check("decay terminates (%d frames)" % guard, guard < 1000)
	theme._process(1.0 / 60.0)  # the release frame
	_check("rest value restored EXACTLY", node.position == rest,
		"pos=%s rest=%s" % [node.position, rest])
	_check("target released after decay", theme._shake_target == null)

	# A freed target must release safely, not crash.
	var doomed := Node2D.new()
	root.add_child(doomed)
	theme.set_shake_target(doomed)
	theme.add_trauma(0.5)
	doomed.free()
	theme._process(1.0 / 60.0)
	_check("freed target releases without crash", theme._shake_target == null)

	# ── Multi-target lockstep (2026-07-17: the board takes the blow) ────
	# Combat shakes _board_container AND _hud_layer off one reservoir. They must
	# move by the SAME offset (or the HUD's bursts and damage numbers tear off
	# the cards they were spawned on), and BOTH must restore exactly.
	var b_node := Node2D.new()          # stands in for _board_container
	b_node.position = Vector2(5.0, -3.0)
	root.add_child(b_node)
	var h_node := CanvasLayer.new()     # stands in for _hud_layer (offset, not position)
	h_node.offset = Vector2(-9.0, 2.0)
	root.add_child(h_node)
	var b_rest: Vector2 = b_node.position
	var h_rest: Vector2 = h_node.offset

	theme.set_shake_targets([b_node, h_node])
	theme.add_trauma(0.9)
	_check("multi-target: CanvasLayer co-target uses `offset`, Control uses `position`",
		theme._shake_prop == "position" and theme._shake_extra.size() == 1
			and theme._shake_extra[0]["prop"] == "offset")
	theme.set_shake_targets([b_node, h_node])  # idempotent — must NOT reset
	_check("multi-target: re-registering the same set keeps trauma",
		is_equal_approx(theme._shake_trauma, 0.9),
		"trauma=%s" % theme._shake_trauma)

	var lockstep := true
	var both_moved := false
	var g2 := 0
	while theme._shake_trauma > 0.0 and g2 < 1000:
		theme._process(1.0 / 60.0)
		var bd: Vector2 = b_node.position - b_rest
		var hd: Vector2 = h_node.offset - h_rest
		if not bd.is_equal_approx(hd):
			lockstep = false
		if bd.length() > 0.5 and hd.length() > 0.5:
			both_moved = true
		g2 += 1
	_check("multi-target: board and HUD move by the SAME offset", lockstep)
	_check("multi-target: both layers visibly displaced", both_moved)
	theme._process(1.0 / 60.0)  # release frame
	_check("multi-target: BOTH rest values restored EXACTLY",
		b_node.position == b_rest and h_node.offset == h_rest,
		"board=%s/%s hud=%s/%s" % [b_node.position, b_rest, h_node.offset, h_rest])
	_check("multi-target: co-targets cleared on release",
		theme._shake_extra.is_empty())

	# A freed CO-target (not the primary) must also release safely.
	var doomed2 := Node2D.new()
	root.add_child(doomed2)
	theme.set_shake_targets([b_node, doomed2])
	theme.add_trauma(0.5)
	doomed2.free()
	theme._process(1.0 / 60.0)
	_check("multi-target: freed co-target does not crash", true)
	theme.set_shake_target(null)
	b_node.free()
	h_node.free()

	# The Screen Shake setting gates new impulses.
	us.screen_shake = false
	theme.set_shake_target(node)
	theme.add_trauma(0.5)
	_check("screen_shake=false gates impulses",
		is_equal_approx(theme._shake_trauma, 0.0),
		"trauma=%s" % theme._shake_trauma)
	theme.set_shake_target(null)
	us.screen_shake = old_shake  # direct restore, never saved
	node.free()

	_check_card_lean(us)
	_check_stat_beats(us)
	_begin_hold_test(us)
	return false   # phase 2: frames must pass for the hold timer to fire


func _finish() -> bool:
	if _fails == 0:
		print("[anim_clock] ALL PASS")
	else:
		print("[anim_clock] %d FAILURE(S)" % _fails)
	return true


func _begin_hold_test(us: Node) -> void:
	# ── ★8: hold_lunge_apex freezes the killer at extension ────────────
	# The contract: the hold PAUSES the lunge tweens (position keeps exactly
	# one owner — time stops for it, no second writer), the idle bob must
	# treat the held lunge as live (_combat_tween_active), and the tween
	# RESUMES after the hold. Reduce Motion skips the hold outright.
	_us_ref = us
	_old_rm_hold = us.reduce_motion
	us.reduce_motion = false

	var card := _make_card(us)
	_hold_rest = card.position
	card.play_attack_lunge(1.0)
	_check("★8: lunge tween runs before the hold",
		card._lunge_tween != null and card._lunge_tween.is_running())
	card.hold_lunge_apex(0.12)
	_check("★8: hold engages", card._lunge_hold_active)
	_check("★8: hold PAUSES the lunge (one owner, time stopped)",
		card._lunge_tween != null and card._lunge_tween.is_valid()
			and not card._lunge_tween.is_running())
	_check("★8: idle bob yields to a held lunge (_combat_tween_active)",
		card._combat_tween_active())

	var idle := _make_card(us)
	idle.hold_lunge_apex(0.12)
	_check("★8: hold no-ops without a running lunge", not idle._lunge_hold_active)
	idle.free()

	us.reduce_motion = true
	var rm_card := _make_card(us)
	rm_card.play_attack_lunge(1.0)
	rm_card.hold_lunge_apex(0.12)
	_check("★8: Reduce Motion never engages the hold",
		not rm_card._lunge_hold_active and rm_card._lunge_tween.is_running())
	rm_card.free()
	us.reduce_motion = false
	_hold_card = card


func _tick_hold_test() -> bool:
	_hold_frames += 1
	if _hold_card == null or not is_instance_valid(_hold_card):
		_check("★8: hold card survived the wait", false)
		return _finish()
	if _hold_card._lunge_hold_active and _hold_frames < 600:
		return false   # still held — let frames pass
	if not _hold_released:
		_hold_released = true
		_check("★8: hold releases within the guard (%d frames)" % _hold_frames,
			_hold_frames < 600)
	# The user-visible contract, immune to tween-lifecycle frame ordering:
	# after the hold releases, the resumed settle must carry the killer back
	# to its rest position. A tween left PAUSED forever would park it at
	# extension and trip the frame guard here.
	if not _hold_card.position.is_equal_approx(_hold_rest) and _hold_frames < 600:
		return false
	_check("★8: the killer settles home after the hold (%d frames)" % _hold_frames,
		_hold_card.position.is_equal_approx(_hold_rest),
		"pos=%s rest=%s" % [_hold_card.position, _hold_rest])
	_hold_card.free()
	if _us_ref != null:
		_us_ref.reduce_motion = _old_rm_hold  # direct restore, never saved
	return _finish()


func _make_card(_us: Node) -> Control:
	# A real Card2D, off a real CardDB entry, parented so _ready() runs.
	# (Autoloads are nodes here, not compile-time globals — a --script probe
	# compiles before the autoload singletons register.)
	var db: Node = root.get_node("CardDB")
	var card = load("res://scripts/Card2D.gd").new()
	card.card_data = db.get_card_data("pikeman").duplicate(true)
	root.add_child(card)
	return card


func _check_card_lean(us: Node) -> void:
	# ── C1: the card leans, and `rotation` keeps exactly one owner ──────
	var old_rm: bool = us.reduce_motion
	us.reduce_motion = false

	var card := _make_card(us)
	_check("card _process is OFF at rest (no per-card frame cost)",
		not card.is_processing())

	# Arm as a drag and damp toward a hard right-swing target.
	card._is_being_dragged = true
	card._arm_lean()
	_check("drag arms the lean driver", card.is_processing() and card._lean_active)
	card.rotation = 0.0
	card._lean_target = 0.30
	for i in 30:
		# _process recomputes _lean_target from live cursor velocity (0 in
		# headless), so drive the damp directly against a held target.
		card.rotation = lerpf(card.rotation, card._lean_target,
			1.0 - exp(-card.LEAN_DAMP_DRAG * (1.0 / 60.0)))
	_check("lean damps toward its target", card.rotation > 0.25,
		"rot=%s" % card.rotation)
	_check("lean never exceeds the clamp",
		absf(card.rotation) <= card.LEAN_DRAG_MAX + 0.001)

	# Releasing hands rotation back to the tweens — the driver must let go.
	card._is_being_dragged = false
	card._disarm_lean()
	_check("release disarms the lean (tweens own rotation again)",
		not card.is_processing() and not card._lean_active)
	card.free()

	# Reduce Motion: the lean must never arm — the card stays rigid.
	us.reduce_motion = true
	var rigid := _make_card(us)
	rigid._is_being_dragged = true
	rigid._arm_lean()
	_check("Reduce Motion never arms the lean",
		not rigid._lean_active and not rigid.is_processing())
	rigid.free()
	us.reduce_motion = old_rm  # direct restore, never saved


func _check_stat_beats(us: Node) -> void:
	# ── C2: stat GAINS float, losses stay owned by the damage number ────
	var old_rm: bool = us.reduce_motion
	us.reduce_motion = false
	var card := _make_card(us)
	card.update_stat_display()  # first paint arms the sentinels

	var base_hp: int = card.current_hp
	_check("first paint records HP without floating a phantom heal",
		card._displayed_hp == base_hp, "displayed=%s hp=%s"
			% [card._displayed_hp, base_hp])

	# A buff (+2 HP) must be seen by the funnel.
	card.current_hp += 2
	card.update_stat_display()
	_check("HP gain is tracked by the display funnel",
		card._displayed_hp == base_hp + 2, "displayed=%s" % card._displayed_hp)

	# A loss must be tracked but NOT floated (take_damage owns that number).
	card.current_hp -= 1
	card.update_stat_display()
	_check("HP loss is tracked (float stays with the damage number)",
		card._displayed_hp == base_hp + 1, "displayed=%s" % card._displayed_hp)

	var base_atk: int = card.effective_atk()
	card.temp_atk_buff += 3
	card.update_stat_display()
	_check("ATK buff is tracked by the display funnel",
		card._displayed_effective_atk == base_atk + 3,
		"displayed=%s" % card._displayed_effective_atk)

	# show_heal_number must no longer float — update_stat_display owns every
	# stat float, and both Combat call sites refresh the display first.
	var src: String = load("res://scripts/Card2D.gd").source_code
	var heal_fn: int = src.find("func show_heal_number")
	var heal_end: int = src.find("\nfunc ", heal_fn + 1)
	var heal_body: String = src.substr(heal_fn, heal_end - heal_fn)
	_check("show_heal_number floats no second number (funnel owns it)",
		not heal_body.contains("spawn_floating_number"))
	card.free()
	us.reduce_motion = old_rm  # direct restore, never saved
