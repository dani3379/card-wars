extends Node
## THE TRANSITION STATE MACHINE (2026-09-11). Headless, runs as a SCENE.
##
##   Godot.exe --headless --path "D:\Godot" res://tools/_probe_transition.tscn
##
## `fade_out_then_change_scene` now owns BOTH halves of a screen change: it
## covers, holds the cover across the incoming scene's `_ready`, then reveals
## with the same overlay. That is the most-travelled code path in the game and
## none of it can be checked by eye in CI, so this checks the part that actually
## matters — that the cover always goes away.
##
## THE FAILURE THIS EXISTS FOR IS RECORDED IN THE FUNCTION ITSELF: a lambda whose
## capture had been freed aborted before either statement ran, so the scene
## change was dropped AND a full-rect MOUSE_FILTER_STOP overlay at z_index 1000
## was never freed — a black screen that ate every click with no way out. An
## overlay that outlives its transition is not a cosmetic defect, it is the worst
## bug this file can ship, and it deserves a standing gate.
##
## TWO HARNESS TRAPS, BOTH PAID FOR HERE:
##
##   1. `change_scene_to_file` FREES `current_scene`. A driver that IS the
##      current scene frees itself mid-transition, and since the driver is a
##      coroutine parked on a timer it simply never resumes — the probe hangs
##      instead of reporting. (Under `--script` the call is inert entirely; see
##      CLAUDE.md.) So the work runs on a node parented to the ROOT.
##   2. THE ROOT IS BUSY DURING THE MAIN SCENE'S `_ready`, so parenting the
##      driver to it must be DEFERRED. A direct `add_child` there fails with
##      "Parent node is busy setting up children" and the driver is never added
##      at all — which is a HANG, not a failure, because the thing that would
##      have reported the problem is the thing that did not exist. Two cuts of
##      this probe died that way and the error was easy to miss among Godot's
##      exit-time noise.

const TARGET := "res://scenes/credits.tscn"


func _ready() -> void:
	var driver := TransitionDriver.new()
	driver.name = "TransitionProbeDriver"
	driver.target = TARGET
	# DEFERRED, or nothing runs: the root is still setting up its children while
	# the main scene's `_ready` executes, so a direct `add_child` there fails with
	# "Parent node is busy setting up children" and the driver is silently never
	# added. That error was the real cause of two earlier hangs in this probe —
	# the driver did not exist, so nobody was left to report or to call quit().
	get_tree().root.add_child.call_deferred(driver)


class TransitionDriver extends Node:
	var target := ""
	var _fails: Array[String] = []
	var _t0 := 0

	func _ready() -> void:
		_run()

	func _run() -> void:
		await get_tree().process_frame
		await get_tree().process_frame

		var before := _overlay_count()
		if GameTheme._transition_reveal_pending:
			_fails.append("reveal flag was already set before any transition")

		_t0 = Time.get_ticks_msec()
		GameTheme.fade_out_then_change_scene(self, target, 0.20)

		# 1 — the cover must exist while the wipe runs.
		await get_tree().create_timer(0.10).timeout
		if _overlay_count() <= before:
			_fails.append("no cover overlay spawned during the wipe")

		# 1b — STAMP THE HAND-OVER. `_transition_reveal_pending` goes true the
		# instant the wipe's callback fires, which is the moment the HOLD begins,
		# so watching for it turns an inference into a measurement. See the note
		# at check 4 for why that matters.
		var t_hold := 0
		var spin := 0
		while not GameTheme._transition_reveal_pending and spin < 600:
			spin += 1
			await get_tree().process_frame
		t_hold = Time.get_ticks_msec()

		# 2 — the wipe must hand over to a reveal it OWNS, and while it does, a
		#     scene calling fade_in must stand down rather than stack a cover.
		await get_tree().create_timer(0.30).timeout
		if not GameTheme._transition_reveal_pending:
			_fails.append("wipe did not claim the reveal after the scene change")
		var during := _overlay_count()
		GameTheme.fade_in(self, 0.2)
		await get_tree().process_frame
		await get_tree().process_frame
		if _overlay_count() > during:
			_fails.append("fade_in stacked a second cover while a reveal was pending")

		# 3 — the scene actually changed.
		var cur := get_tree().current_scene
		if cur == null or not String(cur.scene_file_path).ends_with("credits.tscn"):
			_fails.append("scene did not change (got %s)" % [
				"null" if cur == null else String(cur.scene_file_path)])

		# 4 — THE COVER GOES AWAY, and the wait for it is also the measurement.
		#
		# THE HOLD MUST TRACK THE LOAD, not be a constant wearing a load-aware
		# name. The whole elapsed time is wipe + hold + reveal, and both wipe and
		# reveal run for the duration we passed in, so what is left is the hold
		# itself. It has to land inside the declared band: under the floor means
		# the settle loop never engaged, over the ceiling means it never let go.
		var settled := 0.0
		var guard := 0
		while GameTheme._transition_reveal_pending and guard < 600:
			guard += 1
			await get_tree().process_frame
		settled = float(Time.get_ticks_msec() - _t0) / 1000.0
		# MEASURE THE HOLD, DO NOT INFER IT (2026-09-13). This used to be
		# `settled - 2.0 * duration`: the whole span from the call, minus two
		# NOMINAL tween durations. That put every scrap of frame-granularity
		# error from three separate phases into the remainder, and the remainder
		# IS the quantity — so the number drifted low and the gate failed 5 runs
		# out of 9 inside the full suite while passing 10 out of 10 standalone.
		# Nothing was ever wrong with the cover; the ruler was elastic.
		#
		# `t_hold` is stamped when the reveal flag goes true, which is the hold's
		# actual start, so only ONE nominal term is left to subtract instead of
		# two — and the wipe, where the tween timing lives, is out of the
		# measurement entirely.
		var cover := float(Time.get_ticks_msec() - t_hold) / 1000.0 - 0.20
		print("[transition] cover held %.3fs (band %.2f..%.2f) · whole span %.3fs"
			% [cover, GameTheme.TRANSITION_COVER_MIN,
				GameTheme.TRANSITION_COVER_MAX, settled])
		if cover < GameTheme.TRANSITION_COVER_MIN - 0.03:
			_fails.append("cover lifted after %.3fs, under the %.2fs floor — "
				% [cover, GameTheme.TRANSITION_COVER_MIN]
				+ "the settle wait is not engaging")
		if cover > GameTheme.TRANSITION_COVER_MAX + 0.05:
			_fails.append("cover held %.3fs, past the %.2fs ceiling"
				% [cover, GameTheme.TRANSITION_COVER_MAX])

		await get_tree().process_frame
		await get_tree().process_frame
		if _overlay_count() > before:
			_fails.append("cover overlay OUTLIVED the transition (%d still up) — "
				% [_overlay_count() - before]
				+ "this is the black-screen-that-eats-clicks failure")
		if GameTheme._transition_reveal_pending:
			_fails.append("reveal flag stuck true — every later fade_in stands down")

		_report()

	## Full-rect covers parked on the root, counted by SHAPE rather than by name
	## so a rename cannot fool it.
	func _overlay_count() -> int:
		var n := 0
		for c in get_tree().root.get_children():
			if c is ColorRect and int((c as ColorRect).z_index) >= 1000:
				n += 1
		return n

	func _report() -> void:
		for f in _fails:
			print("  FAIL  %s" % f)
		if _fails.is_empty():
			print("[transition] THE COVER ALWAYS LIFTS")
		else:
			print("[transition] %d FAILURE(S)" % _fails.size())
		get_tree().quit(0 if _fails.is_empty() else 1)
