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

	print("[menu] DONE — no crash")
	quit(0)
