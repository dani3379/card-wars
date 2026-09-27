extends SceneTree

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var net_match := root.get_node("NetMatch")
	root.get_node("UserSettings").reduce_motion = false
	net_match.local_hero = "raider"
	net_match.start_vs_bot(0, 1)
	net_match.match_seed = 20260909
	root.get_node("SkirmishState").reset()
	var screen: Control = load("res://scenes/net_draft.tscn").instantiate()
	root.add_child(screen)
	await create_timer(1.0).timeout
	var row: HBoxContainer = screen.get("_ars_row")
	for child in row.get_children():
		print("[ars-flight] row child=", child, " id=",
			child.get_meta("ars_id", ""), " chip=",
			child.get_meta("ars_chip", null))
	var first: Control = row.get_child(0)
	var id := String(first.get_meta("ars_id", ""))
	print("[ars-flight] pick id=", id)
	screen.call("_on_ars_pick", id, true)
	await process_frame
	var layer: CanvasLayer = screen.get("_ars_layer")
	for child in layer.get_children():
		if child is Control:
			print("[ars-flight] layer child=", child,
				" top_level=", (child as Control).top_level,
				" pos=", (child as Control).global_position)
	_done = true
