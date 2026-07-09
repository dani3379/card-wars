extends SceneTree
## Smoke test for the General's Forge (2026-07-06 progression pass): after an
## elite win the Reward screen offers a chosen "+" forge. Boots the real
## reward scene with an elite node type, opens the confirm modal for the
## first candidate, presses FORGE IT, and asserts the upgrade landed and the
## screen stayed (relic still pending).
##
## Run:
##   Godot.exe --headless --path "D:\Godot" --script res://tools/_probe_general_forge.gd

var _fails: int = 0
var _started: bool = false
var _done: bool = false


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_test()
	return _done


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c in node.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _run_test() -> void:
	print("[general-forge] start")
	var RS = root.get_node_or_null("RunState")
	if RS == null:
		print("[general-forge] FATAL: RunState missing")
		_finish(1)
		return
	RS.start_new_run("stalwart")
	RS.current_node_type = "elite"

	var reward = load("res://scenes/reward.tscn").instantiate()
	root.add_child(reward)
	await create_timer(0.6).timeout
	if not is_instance_valid(reward):
		_check(false, "reward scene survived boot")
		_finish(1)
		return

	var candidates: Array[int] = reward._forge_candidates()
	_check(candidates.size() > 0, "forge candidates found (%d)" % candidates.size())
	if candidates.is_empty():
		_finish(_fails)
		return
	var idx: int = candidates[0]
	_check(not RS.has_upgrade_path(idx, "plus"), "candidate starts unforged")

	reward._show_forge_confirm(idx)
	await create_timer(0.3).timeout
	var dim = reward.get_node_or_null("ForgeDim")
	_check(dim != null, "confirm modal (before/after) opened")
	var go := _find_button(reward, "FORGE IT")
	_check(go != null, "FORGE IT button present")
	if go != null:
		go.emit_signal("pressed")
		await create_timer(0.4).timeout
		_check(RS.has_upgrade_path(idx, "plus"), "the '+' forge was applied to the chosen card")
		_check(bool(reward._forge_done), "forge marked consumed")
		_check(is_instance_valid(reward) and reward.is_inside_tree(),
			"screen stayed up (relic still pending — no early march-off)")
		_check(reward._forge_candidates().find(idx) == -1,
			"forged card no longer a candidate")

	_finish(_fails)


func _finish(code: int) -> void:
	if code == 0:
		print("[general-forge] ALL PASS")
	else:
		print("[general-forge] FAILED: %d checks" % code)
	_done = true
	quit(code)
