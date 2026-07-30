extends SceneTree
## Focused contract probe for the shared campaign/skirmish combat shell.
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_battle_ui_standard.gd

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var script := load("res://scripts/scenes/Combat.gd") as GDScript
	var ok := script != null and script.can_instantiate()
	var combat = script.new() if ok else null
	for method_name in [
		"_combat_visual_act",
		"_resolve_player_portrait",
		"_display_round_number",
		"_player_turn_caption",
		"_set_primary_action",
	]:
		var found: bool = combat != null and combat.has_method(method_name)
		print(("PASS  " if found else "FAIL  ") + method_name)
		ok = ok and found
	if combat != null:
		combat.free()
	print("PROBE_RESULT ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
	return true
