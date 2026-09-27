extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rs: Node = root.get_node("RunState")
	rs.start_new_run("raider", 0, 9696)
	rs.hero_hp = 10
	rs.potions.clear()
	rs.add_potion("healing")
	var map_view = load("res://scripts/scenes/MapView.gd").new()
	var before_count: int = rs.potions.size()
	map_view._use_map_potion(0)
	var ok := true
	if rs.hero_hp != 18:
		ok = false
		print("FAIL  healing potion changes HP once (got %d)" % rs.hero_hp)
	else:
		print("PASS  healing potion changes HP once")
	if rs.potions.size() != before_count - 1:
		ok = false
		print("FAIL  healing potion consumes one belt slot")
	else:
		print("PASS  healing potion consumes one belt slot")
	if map_view._potion_use_busy:
		ok = false
		print("FAIL  potion-use latch releases")
	else:
		print("PASS  potion-use latch releases")
	map_view.free()
	print("[map-potion-route] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
