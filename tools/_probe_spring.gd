extends Node
## _probe_spring.gd — the gate for ▲3, the hand reflow spring.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_spring.tscn
##
## A SCENE, not `--script`, and that is not cosmetic. Naming `Motion` at parse
## time in a `--script` probe drags Motion.gd into the compile that happens BEFORE
## the autoloads register, so its `UserSettings` reference becomes a hard compile
## error and the whole probe fails to load. It is pure math, so it still runs
## headless — it just needs a real scene lifecycle underneath it.
##
## Four parts. Part B is the whole reason springs were worth building.
##
##   A. THE MATH. Settles, lands exactly, overshoots a little but not absurdly,
##      and — the one that matters in this project — SURVIVES A FRAME HITCH. The
##      integrator is only stable while dt is small against k2, and this codebase
##      ships 100 ms+ gaps during a cold board build. Without the stability clamp
##      one long frame sends a card to infinity.
##   B. INTERRUPTION IS CONTINUOUS. A tween killed and restarted mid-flight
##      resumes from a STANDSTILL; a spring carries its velocity through. That is
##      the defect `docs/ANIMATION_AUDIT_20260716.md` filed as C3, and it is
##      measured here as the velocity surviving a retarget.
##   C. IT IS NOT SLOWER THAN WHAT IT REPLACED. The tween took 0.17 s (0.24 s on
##      a deal). A hand that became continuous but sluggish would be a downgrade,
##      so the settle time is asserted against that budget rather than asserted
##      to "feel right".
##   D. THE CHANNELS STAY SEPARATE. `rotation` must still have exactly one writer
##      (C1): the spring may never touch it.

const DT := 1.0 / 60.0

var _hits := 0


func _ready() -> void:
	_run()


func _fail(msg: String) -> void:
	_hits += 1
	print("  FAIL  %s" % msg)


## Steps a spring to its target, returning (seconds, peak overshoot px).
func _settle(sp, target: Vector2, from: Vector2) -> Array:
	sp.reset(from)
	var t := 0.0
	var peak := 0.0
	var span: float = maxf(from.distance_to(target), 0.001)
	while t < 3.0:
		sp.update(DT, target)
		t += DT
		var beyond: float = sp.value.distance_to(from) - span
		peak = maxf(peak, beyond)
		if sp.is_settled(target):
			break
	return [t, peak]


func _run() -> void:
	print("[spring] ▲3 — second-order hand reflow\n")

	# ── A: the math ───────────────────────────────────────────────────────
	print("  -- A, the math --")
	var sp = Motion.Spring.new(3.6, 0.78, 0.0)
	var res := _settle(sp, Vector2(400, 0), Vector2.ZERO)
	print("  ..    settles in %.3f s, overshoot %.1f px" % [res[0], res[1]])
	if res[0] >= 3.0:
		_fail("never settled")
	elif sp.value.distance_to(Vector2(400, 0)) > 0.5:
		_fail("settled %.2f px off target" % sp.value.distance_to(Vector2(400, 0)))
	else:
		print("  ok    reaches the target and stops")
	if res[1] > 60.0:
		_fail("overshoots %.0f px on a 400 px move — that is a bounce" % res[1])
	else:
		print("  ok    overshoot %.1f px is a settle, not a bounce" % res[1])

	# THE FRAME HITCH. 250 ms in one step, which this project really does ship.
	var hitch = Motion.Spring.new(3.6, 0.78, 0.0)
	hitch.reset(Vector2.ZERO)
	for i in 6:
		hitch.update(0.25, Vector2(400, 0))
	if not is_finite(hitch.value.x) or not is_finite(hitch.value.y) \
			or hitch.value.length() > 4000.0:
		_fail("a 250 ms frame detonated the spring (%s) — the clamp is not working"
			% str(hitch.value))
	else:
		print("  ok    survives a 250 ms frame (at %s, still bounded)"
			% str(hitch.value.round()))

	# ── B: interruption carries velocity ──────────────────────────────────
	print("\n  -- B, interruption --")
	var s2 = Motion.Spring.new(3.6, 0.78, 0.0)
	s2.reset(Vector2.ZERO)
	for i in 8:                      # get it moving
		s2.update(DT, Vector2(400, 0))
	var v_before: Vector2 = s2.vel
	var p_before: Vector2 = s2.value
	# Retarget mid-flight, exactly as a relayout does, and REVERSE it — the
	# hardest case, and the one a killed tween handles worst.
	s2.update(DT, Vector2(-200, 0))
	var moved: Vector2 = s2.value - p_before

	# THE ASSERTION IS ABOUT POSITION, NOT VELOCITY, and the first draft got that
	# wrong. A stiff spring SHOULD accelerate hard when the target jumps 600 px
	# behind it — demanding a small velocity change would be demanding a mushy
	# spring, not a continuous one. What continuity means is that the body keeps
	# travelling the way it was for the frame the interruption lands on, instead
	# of restarting from rest the way a killed and rebuilt tween does.
	var expected: Vector2 = v_before * DT
	print("  ..    carried %.2f px into the frame after the retarget (was moving %.2f px/frame)"
		% [moved.x, expected.x])
	if v_before.length() < 50.0:
		_fail("the spring was not actually moving — the test proves nothing")
	elif signf(moved.x) != signf(v_before.x):
		_fail("the body reversed WITHIN the interruption frame — that is a restart")
	elif absf(moved.x - expected.x) > 0.01:
		_fail("position is not continuous across the retarget (%.3f vs %.3f)"
			% [moved.x, expected.x])
	else:
		print("  ok    momentum carries through the retarget")
	# And it must actually turn around soon after — carrying momentum for ever
	# would be a different bug.
	for i in 30:
		s2.update(DT, Vector2(-200, 0))
	if s2.value.x > p_before.x:
		_fail("half a second later it is still heading the old way")
	else:
		print("  ok    and it turns around under the new target")

	# ── C: not slower than the tween it replaced ──────────────────────────
	print("\n  -- C, pace --")
	# Budget 1.25x the tween it replaced, not 2x. At 2x this passed while the
	# reflow took 0.30 s against a 0.17 s tween — the gate agreed with a hand that
	# had become measurably slower, which is the regression it exists to catch.
	for row in [["reflow", 5.4, 0.68, 0.17], ["deal", 4.6, 0.70, 0.24]]:
		var s3 = Motion.Spring.new(float(row[1]), float(row[2]), 0.0)
		var r3 := _settle(s3, Vector2(260, 0), Vector2.ZERO)
		var budget: float = float(row[3]) * 1.25
		if float(r3[0]) > budget:
			_fail("%s settles in %.3f s against a %.3f s budget — sluggish"
				% [row[0], r3[0], budget])
		else:
			print("  ok    %-6s settles in %.3f s (tween was %.2f s)"
				% [row[0], r3[0], float(row[3])])

	# ── D: the spring never touches rotation ──────────────────────────────
	print("\n  -- D, channels --")
	var src := FileAccess.open("res://scripts/Card2D.gd", FileAccess.READ)
	var body := "" if src == null else src.get_as_text()
	if src != null:
		src.close()
	var fn := body.find("func _tick_hand_spring")
	var fn_end := body.find("\nfunc ", fn + 10)
	var chunk := body.substr(fn, maxi(fn_end - fn, 0)) if fn >= 0 else ""
	if chunk == "":
		_fail("could not find _tick_hand_spring to audit")
	elif chunk.find("rotation") >= 0:
		_fail("the spring writes `rotation` — that is a second writer (C1)")
	else:
		print("  ok    the spring touches position only; rotation keeps one writer")

	# ── E: the real hand, in a real fight ─────────────────────────────────
	#
	# Parts A–D are about a spring on its own. This is the part with the risk in
	# it: the hand is the most-touched surface in the game, and the failure that
	# matters is not "feels wrong", it is A CARD THAT NEVER ARRIVES — stranded
	# between two slots because the driver stopped owning it. `_disarm_lean` used
	# to call `set_process(false)` unconditionally, which would do exactly that.
	print("\n  -- E, the real hand --")
	RunState.start_new_run("stalwart", 0, 4242)
	RunState.current_encounter_id = "goblin_scouts"
	RunState.current_node_type = "combat"
	var cb = load("res://scenes/combat.tscn").instantiate()
	add_child(cb)
	await get_tree().create_timer(6.0).timeout

	var hand: Array = cb._hand
	if hand.is_empty():
		_fail("no hand to measure")
	else:
		# Force a relayout, then let it settle, then demand every card be exactly
		# on its slot — the same contract the tween met.
		cb._layout_hand()
		await get_tree().create_timer(1.2).timeout
		var worst := 0.0
		var stuck := 0
		for c in hand:
			if not is_instance_valid(c):
				continue
			var d: float = c.position.distance_to(c._hand_target_position)
			worst = maxf(worst, d)
			if d > 1.0:
				stuck += 1
		print("  ..    %d cards, worst offset %.3f px" % [hand.size(), worst])
		if stuck > 0:
			_fail("%d card(s) never reached the slot (worst %.2f px)" % [stuck, worst])
		else:
			print("  ok    every card landed exactly on its slot")
		# And the drivers must have stood down — a hand that keeps processing
		# forever is a per-frame cost on the busiest screen in the game.
		var busy := 0
		for c in hand:
			if is_instance_valid(c) and c.is_processing():
				busy += 1
		if busy > 0:
			_fail("%d card(s) still processing after settling" % busy)
		else:
			print("  ok    the drivers stood down when idle")

		# THE SPRING MUST YIELD `position` TO ANY OTHER WRITER.
		#
		# Found by review, not by a failing test: Combat's discard fly-away
		# (`Combat.gd`, the marked-discard sweep) tweens a card that is STILL a
		# hand card all the way to the pile. With a spring armed from the
		# relayout that preceded it, the card would be hauled back toward its hand
		# slot in mid-flight. The spring is the least authoritative writer of the
		# three and must always be the one that gives way.
		var yielder = hand[mini(1, hand.size() - 1)]
		if is_instance_valid(yielder):
			var slot2: Vector2 = yielder._hand_target_position
			yielder.position = slot2 + Vector2(0, 300)
			yielder._arm_hand_spring(0.0, false)
			await get_tree().process_frame
			await get_tree().process_frame
			# Someone else moves the card — exactly what the fly-away tween does.
			var hijack := Vector2(-500, -500)
			yielder.position = hijack
			await get_tree().process_frame
			await get_tree().process_frame
			if yielder._hand_spring_active:
				_fail("the spring kept the channel after another writer moved the card")
			elif yielder.position.distance_to(hijack) > 1.0:
				_fail("the spring dragged the card %.1f px away from the other writer"
					% yielder.position.distance_to(hijack))
			else:
				print("  ok    yields position the moment another writer takes it")

		# THE LINE THIS CHANGE ACTUALLY RISKED. `_disarm_lean` used to stop
		# `_process` unconditionally, and it fires on hover-exit and _end_drag —
		# both of which can land while a reflow is in flight. If it still did
		# that, the card would freeze wherever it happened to be, between slots,
		# for the rest of the fight. Simulate it directly.
		var probe_card = hand[0]
		if is_instance_valid(probe_card):
			var slot: Vector2 = probe_card._hand_target_position
			probe_card.position = slot + Vector2(0, 220)
			probe_card._arm_hand_spring(0.0, false)
			await get_tree().process_frame
			await get_tree().process_frame
			probe_card._disarm_lean()          # hover-exit mid-flight
			await get_tree().create_timer(0.9).timeout
			var d2: float = probe_card.position.distance_to(slot)
			if d2 > 1.0:
				_fail("a lean disarm mid-reflow stranded the card %.1f px from its slot" % d2)
			else:
				print("  ok    survives a lean disarm mid-reflow")
	if is_instance_valid(cb):
		cb.queue_free()
	await get_tree().process_frame

	print("\n[spring] %s" % ("PASS" if _hits == 0 else "%d FAIL" % _hits))
	get_tree().quit(1 if _hits > 0 else 0)
