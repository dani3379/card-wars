extends SceneTree
## Throwaway parse-check: load the Skirmish draft script (and its base) AFTER the
## first frame, so the project autoloads (CardDB/GameTheme/SkirmishState) are live
## and identifier resolution is real. A compile error makes can_instantiate() false.

var _done := false

func _init() -> void:
	process_frame.connect(_go)

func _go() -> void:
	if _done:
		return
	_done = true
	var ok := true
	for path in [
		"res://scripts/scenes/NetDeckBuilder.gd",
		"res://scripts/scenes/NetDraft.gd",
	]:
		var s = load(path)
		if s == null or not (s as GDScript).can_instantiate():
			push_error("COMPILE FAILED: " + path)
			ok = false
		else:
			print("OK ", path)
	print("PROBE_RESULT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
