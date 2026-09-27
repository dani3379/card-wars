extends SceneTree
## Checks optimized plaque geometry independently of screenshots/tooltips.

var _started := false
var _done := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var scene: Node = load("res://scenes/collection.tscn").instantiate()
	root.add_child(scene)
	scene.call("show_tab", "relics")
	await create_timer(3.0).timeout
	var plaques: Array[Control] = []
	_collect_plaques(scene, plaques)
	var h_overflow := 0
	var v_overflow := 0
	var bad_size := 0
	for chrome in plaques:
		var tile := chrome.get_parent() as Control
		if tile == null:
			continue
		var tr := tile.get_global_rect()
		if not tile.size.is_equal_approx(Vector2(466, 120)):
			bad_size += 1
		var labels: Array[Control] = []
		_collect_labels(tile, labels)
		for label in labels:
			var lr := label.get_global_rect()
			if lr.position.x < tr.position.x - 0.5 \
					or lr.end.x > tr.end.x + 0.5:
				h_overflow += 1
				print("[plaque-layout] horizontal overflow tile=%s label=%s text=%s" % [
					str(tr), str(lr), String(label.get("text"))])
			if lr.position.y < tr.position.y - 0.5 \
					or lr.end.y > tr.end.y + 0.5:
				v_overflow += 1
				print("[plaque-layout] vertical overflow tile=%s label=%s text=%s" % [
					str(tr), str(lr), String(label.get("text"))])
	print("[plaque-layout] plaques=%d bad_size=%d h_overflow=%d v_overflow=%d" % [
		plaques.size(), bad_size, h_overflow, v_overflow])
	scene.queue_free()
	for _i in 5:
		await process_frame
	_done = true
	quit(0 if bad_size == 0 and h_overflow == 0 and v_overflow == 0 else 1)


func _collect_plaques(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control and child.name == "PlaqueChrome":
			out.append(child)
		_collect_plaques(child, out)


func _collect_labels(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child)
		_collect_labels(child, out)
