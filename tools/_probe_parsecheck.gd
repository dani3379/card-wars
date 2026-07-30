extends Node
## Honest production-script parse gate.
## Run as a project scene so autoload names exist while scripts compile:
## Godot.exe --headless --path "D:\\Godot" res://tools/_probe_parsecheck.tscn
## load() alone is insufficient: it can return a GDScript after a compile error.

const PROBE_NAME := "parsecheck"
const SCRIPT_ROOT := "res://scripts"


func _ready() -> void:
	var paths: Array[String] = []
	var failures: Array[String] = []
	_collect_scripts(SCRIPT_ROOT, paths, failures)
	paths.sort()
	for path in paths:
		var resource := ResourceLoader.load(path, "GDScript")
		if resource == null or not (resource is GDScript):
			failures.append("LOAD-FAIL: %s" % path)
			continue
		var err := (resource as GDScript).reload(true)
		if err != OK:
			failures.append("COMPILE-FAIL (%s): %s" % [error_string(err), path])
	print("[parsecheck] checked %d production scripts" % paths.size())
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
