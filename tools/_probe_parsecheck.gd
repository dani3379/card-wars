extends Node
## Honest production-script parse gate.
## Run as a project scene so autoload names exist while scripts compile:
## Godot.exe --headless --path "D:\\Godot" res://tools/_probe_parsecheck.tscn
## load() alone is insufficient: it can return a GDScript after a compile error.

const PROBE_NAME := "parsecheck"
const SCRIPT_ROOT := "res://scripts"


## THE SWEEP IS RACY, AND THE RETRY IS WHAT MAKES IT HONEST (2026-08-05).
##
## Measured: three consecutive runs over an IDENTICAL, unedited working tree
## gave PASS · PASS · FAIL, and the failing run named a DIFFERENT file each time
## (Event.gd on one, Combat.gd on another). Every spurious failure carried the
## same signature —
##
##     Parse Error: Cannot infer the type of "rm" variable
##     because the value doesn't have a set type
##
## — on a line of the form `var rm := UserSettings.reduce_motion`. That is the
## autoload false positive CLAUDE.md documents for `--check-only`, reaching this
## gate too: `reload(true)` on one script momentarily invalidates the class type
## another script is reading an autoload member through, so whoever is swept
## while the graph is torn fails to infer.
##
## This was costing real time — a phantom "break" in a file nobody had touched.
##
## The fix cannot be to ignore the error (a genuine `var x := <untyped>` is a
## real break). It is to RETRY the failures once the sweep has finished and the
## graph is whole again. A real compile error is deterministic and fails both
## times; a race victim compiles clean on the second pass. The retry therefore
## cannot turn a broken script into a pass — and any script that needed one is
## REPORTED, so a flaky run stays visible instead of being silently smoothed.
func _ready() -> void:
	var paths: Array[String] = []
	var failures: Array[String] = []
	var suspects: Array[String] = []
	_collect_scripts(SCRIPT_ROOT, paths, failures)
	paths.sort()
	for path in paths:
		var resource := ResourceLoader.load(path, "GDScript")
		if resource == null or not (resource is GDScript):
			failures.append("LOAD-FAIL: %s" % path)
			continue
		var err := (resource as GDScript).reload(true)
		if err != OK:
			suspects.append(path)
	# Second pass, graph whole. Only the suspects, so the cost is zero on a
	# clean run and one extra compile per suspect otherwise.
	var recovered: Array[String] = []
	for path in suspects:
		var resource := ResourceLoader.load(path, "GDScript")
		if resource == null or not (resource is GDScript):
			failures.append("LOAD-FAIL: %s" % path)
			continue
		var err := (resource as GDScript).reload(true)
		if err == OK:
			recovered.append(path)
		else:
			failures.append("COMPILE-FAIL (%s): %s" % [error_string(err), path])
	print("[parsecheck] checked %d production scripts" % paths.size())
	if not recovered.is_empty():
		# Never silent. If this line appears on a clean tree it is the known
		# sweep race; if it appears together with a real failure, read it as a
		# hint about which edit destabilised the graph.
		print("[parsecheck] %d script(s) failed the first sweep and compiled "
			% recovered.size() + "clean on retry (known autoload-typing race):")
		for path in recovered:
			print("[parsecheck]   recovered: %s" % path)
	if paths.is_empty():
		failures.append("No scripts found under %s" % SCRIPT_ROOT)
	if failures.is_empty():
		print("PROBE PASS: %s" % PROBE_NAME)
		get_tree().quit(0)
		return
	for failure in failures:
		printerr("[parsecheck] " + failure)
	printerr("PROBE FAIL: %s (%d failures)" % [PROBE_NAME, failures.size()])
	get_tree().quit(1)


func _collect_scripts(root: String, paths: Array[String],
		failures: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		failures.append("Cannot open script directory: %s" % root)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				_collect_scripts(path, paths, failures)
			elif entry.ends_with(".gd"):
				paths.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
