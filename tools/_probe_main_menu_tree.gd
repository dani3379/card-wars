extends SceneTree
## Counts each top-level Main Menu subtree to make accidental UI fan-out visible.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for _i in 4:
		await process_frame
	for child in menu.get_children():
		var counts := {"nodes": 0, "canvas": 0, "controls": 0, "labels": 0,
			"particles": 0, "panels": 0}
		_count(child, counts)
		print("[menu-tree] %s type=%s nodes=%d canvas=%d controls=%d labels=%d particles=%d panels=%d" % [
			child.name, child.get_class(), counts.nodes, counts.canvas,
			counts.controls, counts.labels, counts.particles, counts.panels])
		if child.name == "CommandDossier":
			_print_children(child, "  ", 3)
	menu.queue_free()
	await process_frame
	quit()


func _count(node: Node, out: Dictionary) -> void:
	out.nodes += 1
	if node is CanvasItem:
		out.canvas += 1
	if node is Control:
		out.controls += 1
	if node is Label:
		out.labels += 1
	if node is CPUParticles2D:
		out.particles += 1
	if node is PanelContainer:
		out.panels += 1
	for child in node.get_children():
		_count(child, out)


func _print_children(node: Node, indent: String, depth: int) -> void:
	if depth <= 0:
		return
	for child in node.get_children():
		print("[menu-tree] %s%s type=%s children=%d" % [
			indent, child.name, child.get_class(), child.get_child_count()])
		_print_children(child, indent + "  ", depth - 1)
