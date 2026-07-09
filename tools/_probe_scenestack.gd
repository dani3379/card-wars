extends SceneTree
## Regression probe: with supersampling ON, change_scene_to_file must NOT leave old
## scenes alive inside the SubViewport. Guards the "all previous screens visible in
## the back" bug — reparenting the scene into _svp nulls get_tree().current_scene,
## so Godot's own free-the-outgoing-scene step is skipped and screens used to stack.
## Run: Godot..._console.exe --headless --path "D:\Godot" --script res://tools/_probe_scenestack.gd

var _svp: SubViewport = null
var _pass := 0
var _fail := 0

func _check(cond: bool, label: String) -> void:
	if cond: _pass += 1; print("  ok   ", label)
	else: _fail += 1; print("  FAIL ", label)


func _svp_scene_count() -> int:
	if _svp == null or not is_instance_valid(_svp):
		return -1
	return _svp.get_child_count()


func _initialize() -> void:
	await process_frame
	var SUP = root.get_node_or_null("Supersample")
	var NM = root.get_node_or_null("NetMatch")
	var SS = root.get_node_or_null("SkirmishState")

	# Force SSAA on (the bug only manifests with the SubViewport rig).
	SUP.apply_scale(2.0)
	await process_frame
	_svp = root.get_node_or_null("SupersampleLayer/SupersampleVP")
	if _svp == null:
		print("[scenestack] FATAL: SubViewport missing"); quit(); return

	change_scene_to_file("res://scenes/main_menu.tscn")
	for i in 5: await process_frame
	_check(_svp_scene_count() == 1, "menu: exactly 1 scene in viewport (got %d)" % _svp_scene_count())

	change_scene_to_file("res://scenes/net_lobby.tscn")
	for i in 5: await process_frame
	_check(_svp_scene_count() == 1, "lobby: previous scene freed, 1 remains (got %d)" % _svp_scene_count())

	if NM != null and SS != null:
		NM.start_vs_bot(SS.MatchMode.QUICK, 1)
	change_scene_to_file("res://scenes/net_quick.tscn")
	for i in 5: await process_frame
	_check(_svp_scene_count() == 1, "quick battle: still 1 scene, no stacking (got %d)" % _svp_scene_count())
	_check(String(_svp.get_child(0).name) == "NetQuick", "the one remaining scene is the current one")

	print("[scenestack] RESULT: %d passed, %d failed" % [_pass, _fail])
	quit()
