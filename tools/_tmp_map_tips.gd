extends Node
## TEMP: print every map tooltip string and shoot the two new ones rendered.
##   Godot.exe --path "D:\Godot" res://tools/_tmp_map_tips.tscn

var _map: Node = null


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ss := get_node_or_null("/root/Supersample")
	if ss != null and ss.has_method("apply_scale"):
		ss.apply_scale(1.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_move_to_foreground()
	RunState.start_new_run("kindler")
	RunState.holds_broken_in_act = 3
	await get_tree().process_frame

	_map = load("res://scenes/map.tscn").instantiate()
	get_tree().root.add_child(_map)
	await get_tree().create_timer(3.0).timeout

	print("=== COMPANY TIP ===")
	print(_map._company_tip_text())
	print("=== ARMS SENTENCE === ", _map._arms_sentence())
	print("=== OWN STANDARD  === ", _map._own_standard_text())

	var longest := ""
	var longest_nd: Dictionary = {}
	for nd in _map._nodes:
		var t := String(nd.get("type", ""))
		if t not in ["combat", "elite", "boss"]:
			continue
		var s: String = _map._tip(nd)
		print("--- [%s] r%d c%d ---" % [t, int(nd.row), int(nd.col)])
		print(s)
		if s.length() > longest.length():
			longest = s
			longest_nd = nd
	# Synthetic worst case: General + the longest non-boss passive + mutator +
	# terrain + bridge + pursuit.
	var worst_enc := ""
	var worst_len := 0
	for eid in EncounterDB.ENCOUNTERS.keys():
		var e: Dictionary = EncounterDB.ENCOUNTERS[eid]
		if String(e.get("type", "")) == "boss":
			continue
		var pd := String(e.get("passive_desc", ""))
		if pd.length() > worst_len:
			worst_len = pd.length()
			worst_enc = String(eid)
	var mut_worst := ""
	var mut_len := 0
	for mid in MutatorDB.MUTATORS.keys():
		var m: Dictionary = MutatorDB.MUTATORS[mid]
		var l: int = String(m.get("name", "")).length() + String(m.get("desc", "")).length()
		if l > mut_len:
			mut_len = l
			mut_worst = String(mid)
	var synth := {
		"type": "elite", "row": 6, "col": 2, "vis": false,
		"encounter_id": worst_enc, "mutator_id": mut_worst,
		"terrain": "woods", "bridge": true,
	}
	print("=== SYNTHETIC WORST (enc=%s mut=%s) ===" % [worst_enc, mut_worst])
	var synth_tip: String = _map._tip(synth)
	print(synth_tip)

	# Render: company tip (left) and the synthetic worst tip (right).
	var layer := CanvasLayer.new()
	layer.layer = 90
	_map.add_child(layer)
	var t1: Control = _map._build_map_tooltip(_map._company_tip_text())
	t1.position = Vector2(60, 240)
	layer.add_child(t1)
	var t2: Control = _map._build_map_tooltip(synth_tip)
	t2.position = Vector2(700, 240)
	layer.add_child(t2)
	var t3: Control = _map._build_map_tooltip(longest)
	t3.position = Vector2(700, 620)
	layer.add_child(t3)
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_map_tips.png")
	print("SAVED _tmp_map_tips.png")
	print("TIPS_DONE")
	get_tree().quit()
