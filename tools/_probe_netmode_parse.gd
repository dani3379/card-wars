extends SceneTree
## Parse-check every online deck-acquisition screen.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_netmode_parse.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var ok := true
	for path in [
		"res://scripts/scenes/NetDeckBuilder.gd",
		"res://scripts/scenes/NetDraft.gd",
		"res://scripts/scenes/NetQuick.gd",
		"res://scripts/scenes/NetSealed.gd",
		"res://scripts/scenes/NetConstructed.gd",
	]:
		var script = load(path)
		if script == null or not (script as GDScript).can_instantiate():
			push_error("COMPILE FAILED: " + path)
			ok = false
		else:
			print("OK ", path)
	print("PROBE_RESULT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true
