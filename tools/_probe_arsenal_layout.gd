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
	var skirmish := root.get_node("SkirmishState")
	net_match.local_hero = "raider"
	net_match.start_vs_bot(2, 1)
	net_match.match_seed = 20260909
	net_match.match_mode = 2
	net_match.local_hero = "raider"
	net_match.remote_hero = "stalwart"
	skirmish.reset()
	var packed := load("res://scenes/net_quick.tscn") as PackedScene
	var screen := packed.instantiate()
	root.add_child(screen)
	for _i in 4:
		await RenderingServer.frame_post_draw
	var row := screen.get("_ars_row") as HBoxContainer
	if row != null:
		print("[arsenal-layout] row_size=", row.size,
			" row_min=", row.get_combined_minimum_size())
		for i in row.get_child_count():
			var tile := row.get_child(i) as Control
			if tile != null:
				print("[arsenal-layout] tile=", i, " size=", tile.size,
					" min=", tile.custom_minimum_size,
					" combined=", tile.get_combined_minimum_size())
	screen.queue_free()
	for _i in 3:
		await process_frame
	net_match.leave()
	_done = true
