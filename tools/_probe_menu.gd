extends SceneTree
## Reproduces the NEW RUN crash by driving the real MainMenu scene: instantiate
## it, run hero-select, and focus every hero (builds the detail pane each time).
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_menu.gd

var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


var _step_fails: Array[String] = []


func _step_check(ok: bool, what: String) -> void:
	if ok:
		print("[menu]   PASS  ", what)
	else:
		_step_fails.append(what)
		print("[menu]   FAIL  ", what)


## THE MUSTER became three steps 2026-07-31, which moved a pile of state OUT of
## the screen and onto the object: the seed field is built on step III alone, the
## doctrine toggles on step I, and the terms are dealt once at entry. Stepping is
## the only thing that can break any of it, and nothing else drives the steps —
## the shot harness renders them but asserts nothing.
func _drive_muster_steps(mm) -> void:
	print("[menu] driving THE MUSTER's three steps ...")
	mm._show_muster_step(1)
	await process_frame
	mm._focus_hero("stalwart")
	await process_frame

	# A typed seed set on step III must survive walking back to step I. Parked in
	# the LineEdit (which only step III builds) it would silently revert to the
	# random seed, and the run would commit a different map than the one previewed.
	mm._show_muster_step(3)
	await process_frame
	# Type into the REAL field, not just the handler. Driving the handler alone
	# left the LineEdit empty, and a regression that reads the widget instead of
	# the object then passed the first assertion by comparing two random seeds —
	# verified by reverting the fix and watching which assertions fired.
	if mm._seed_edit != null and is_instance_valid(mm._seed_edit):
		mm._seed_edit.text = "burning-meadow"
	mm._on_muster_seed_changed("burning-meadow")
	# WAIT OUT THE DEBOUNCE. _on_muster_seed_changed sets _muster_seed_text
	# immediately but defers the re-deal by 0.35 s, so that a seven-character seed
	# deals once instead of seven times. Capturing after a single frame therefore
	# recorded the slate of the OLD (random) seed, and the comparison further down
	# then failed against the typed seed's slate on re-entry — a probe reporting a
	# reproducibility bug the product does not have.
	await create_timer(0.5).timeout
	await process_frame
	var seed_on_three: int = mm._pending_run_seed()
	var slate_on_three: Array = (mm._muster_writ_slate as Array).duplicate(true)

	mm._show_muster_step(1)
	await process_frame
	_step_check(mm._pending_run_seed() == seed_on_three,
		"the typed seed survives stepping off the step that owns its field")
	_step_check(String(mm._selected_hero) == "stalwart",
		"the chosen lord survives a round trip")

	# The bonus screen is the one place the dealt slate is PAINTED, and it is a
	# different screen from the one that owns the seed field — which is exactly
	# the drift this block exists to catch.
	mm._show_starting_bonus()
	for _i in 4:
		await process_frame
	_step_check(String(mm._selected_hero) == "stalwart",
		"the chosen lord survives the walk to the bonus")
	_step_check(mm._pending_run_seed() == seed_on_three,
		"the seed is unchanged by opening the bonus")
	_step_check(mm._muster_writ_buttons.size() == 4,
		"the bonus screen paints all four dealt terms")

	# Same seed, same four terms. If the slate re-rolled on every visit the
	# player could shop for a better deal by stepping back and forth, and the
	# screen's promise that a seed reproduces a run would be false.
	var reproduced := true
	var slate_now: Array = mm._muster_writ_slate
	if slate_now.size() != slate_on_three.size():
		reproduced = false
	else:
		for i in range(slate_now.size()):
			if String((slate_now[i] as Dictionary).get("id", "")) \
					!= String((slate_on_three[i] as Dictionary).get("id", "")):
				reproduced = false
	_step_check(reproduced, "the same seed deals the same four terms on re-entry")
	_step_check(String(mm._selected_writ_id) != "",
		"a term is always selected, so the commit can never resolve nothing")

	# ── THE SIGNING TABLE HAS ONE OWNER (2026-09-17) ──
	#
	# `BonusTable` is a SIBLING of the Menu column, because a Container lays out
	# every Control child it has and a full-rect backdrop parented into the
	# column would be dealt a slot in the stack. The cost of that is that
	# clearing the column does NOT take the table with it: BACK lands on run
	# setup through `_show_muster_step`, which only frees the column's children,
	# so a wood table would be left lying across a screen that has no paper on
	# it. Both directions are asserted because only one of them is obvious.
	_step_check(mm.get_node_or_null("BonusTable") != null,
		"the bonus screen stages its signing table")
	mm._leave_starting_bonus()
	for _i in 4:
		await process_frame
	_step_check(mm.get_node_or_null("BonusTable") == null,
		"BACK off the bonus screen takes the table with it")
	mm._show_starting_bonus()
	for _i in 4:
		await process_frame
	_step_check(mm.get_node_or_null("BonusTable") != null,
		"re-entering the bonus screen stages the table again")
	# And never TWICE: _set_bonus_table frees any standing table before adding
	# one, so a second entry cannot stack a second plane of wood.
	var tables := 0
	for child in mm.get_children():
		if String(child.name).begins_with("BonusTable"):
			tables += 1
	_step_check(tables == 1, "exactly one signing table is staged")

	# Clear the typed seed so the rest of the drive (and the committed run) uses
	# the ordinary random path rather than this probe's fixture.
	mm._on_muster_seed_changed("")
	await process_frame
	if _step_fails.is_empty():
		print("[menu]   muster step machine OK")
	else:
		print("[menu]   muster step machine FAILED: %s" % ", ".join(_step_fails))


func _run() -> void:
	# Snapshot the real saves FIRST — this probe drives the REAL new-run path,
	# which claims slot 0 and (once map.tscn checkpoints) writes into it. The
	# snapshot is restored before quit so a probe run never costs the player a
	# campaign. (Learned the hard way 2026-07-02: a probe run stomped run_0.)
	for i in range(3):
		var p := "user://run_%d.save" % i
		if FileAccess.file_exists(p):
			DirAccess.copy_absolute(p, p + ".probebak")

	print("[menu] instancing main_menu.tscn ...")
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm)
	await process_frame
	await process_frame
	print("[menu] _ready done")

	var RS: Node = root.get_node_or_null("RunState")
	# Faithful path: the user has all 3 slots full, so _on_new_run routes to the
	# OVERWRITE load screen (reads every save's get_slot_summary).
	print("[menu] empty slot = %d (expect -1 if all full)" % mm._first_empty_slot())
	for i in range(3):
		var s = RS.get_slot_summary(i)
		print("[menu]   slot %d has_save=%s keys=%s" % [i, str(s.get("has_save", false)), str(s.keys())])
	print("[menu] calling REAL entry _on_new_run() ...")
	mm._on_new_run()
	await process_frame
	print("[menu]   _on_new_run routed OK (overwrite screen or hero select built)")

	print("[menu] picking slot 0 -> _begin_new_in_slot(0) -> hero select ...")
	mm._begin_new_in_slot(0)
	await process_frame
	print("[menu]   hero select built OK")

	var HDB: Node = root.get_node_or_null("HeroDB")
	for hid in HDB.HERO_ORDER:
		mm._focus_hero(String(hid))
		await process_frame
	print("[menu]   focused all heroes OK")

	await _drive_muster_steps(mm)

	print("[menu] picking hero -> _begin_run_with('raider') (start_new_run + blessing select) ...")
	mm._begin_run_with("raider")
	await process_frame
	await process_frame
	print("[menu]   blessing select built OK")

	print("[menu] loading map.tscn with the new run state ...")
	var mv = load("res://scenes/map.tscn").instantiate()
	root.add_child(mv)
	await process_frame
	await process_frame
	await process_frame
	print("[menu]   map.tscn built OK")

	# Put the player's saves back exactly as they were before the drive.
	for i in range(3):
		var b := "user://run_%d.save.probebak" % i
		if FileAccess.file_exists(b):
			DirAccess.copy_absolute(b, "user://run_%d.save" % i)
			DirAccess.remove_absolute(b)
	print("[menu] saves restored from pre-probe snapshot")

	if _step_fails.is_empty():
		print("[menu] DONE — no crash")
		quit(0)
	else:
		print("[menu] DONE — no crash, but %d muster-step assertion(s) FAILED"
			% _step_fails.size())
		quit(1)
